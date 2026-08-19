import CodexRingCore
import AppKit
import Foundation

@main
struct CodexRingApp {
    private enum AppError: Error {
        case ffmpegUnavailable
        case ffmpegFailed(Int32)
        case imageDecodingFailed
    }

    static func main() async {
        do {
            let command = try RingCommandParser.parse(
                arguments: Array(CommandLine.arguments.dropFirst()),
                homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
                workingDirectory: URL(filePath: FileManager.default.currentDirectoryPath)
            )

            switch command.kind {
            case .preview:
                try renderOnce(options: command.options)
            case .watch:
                while true {
                    try renderOnce(options: command.options)
                    try await Task.sleep(for: .seconds(command.options.interval))
                }
            case .displayWatch:
                var syncState = DisplaySyncState()
                let reader = CodexSessionReader()
                while true {
                    var cycleOutcome = DisplaySyncCycleOutcome.noData
                    if let snapshot = try reader.latestSnapshot(in: command.options.sessionsDirectory) {
                        let remainingPercent = snapshot.presentation(now: Date()).primary.remainingPercent
                        if syncState.shouldPush(remainingPercent: remainingPercent) {
                            do {
                                let (result, mediaCount) = try await displayOnce(options: command.options)
                                syncState.recordSuccessfulPush(remainingPercent: remainingPercent)
                                writeOutputLine(
                                    "display_sync_complete device=\(result.deviceName) "
                                        + "remaining=\(remainingPercent) transferred_media_bytes=\(mediaCount)"
                                )
                                cycleOutcome = .pushed
                            } catch {
                                cycleOutcome = .failed
                                FileHandle.standardError.write(
                                    Data("display_sync_retry remaining=\(remainingPercent) error=\(error)\n".utf8)
                                )
                            }
                        } else {
                            cycleOutcome = .unchanged
                            writeOutputLine("display_sync_unchanged remaining=\(remainingPercent)")
                        }
                    } else {
                        FileHandle.standardError.write(Data("display_sync_waiting_for_usage\n".utf8))
                    }
                    let delay = DisplaySyncSchedule.delay(
                        after: cycleOutcome,
                        regularInterval: command.options.interval
                    )
                    try await Task.sleep(for: .seconds(delay))
                }
            case .scan:
                let devices = try await E01DiscoveryController().scan(timeout: command.options.scanTimeout)
                if devices.isEmpty {
                    print("no_device_found")
                } else {
                    for device in devices {
                        print("device name=\(device.name) service=data")
                    }
                }
            case .bind:
                let request = makeBindRequest()
                let result = try await E01BindController().bind(
                    request: request,
                    timeout: command.options.scanTimeout
                )
                let protocolVersion = result.protocolVersion ?? "unknown"
                let firmwareVersion = result.firmwareVersion ?? "unknown"
                let platform = result.platform.map(String.init) ?? "unknown"
                let modelNumber = result.modelNumber.map(String.init) ?? "unknown"
                print(
                    "bind_response device=\(result.deviceName) bytes=\(result.responseLength) "
                        + "badge_size=\(result.displaySize.width)x\(result.displaySize.height) "
                        + "memory=\(result.memoryBytes) "
                        + "protocol=\(protocolVersion) firmware=\(firmwareVersion) "
                        + "platform=\(platform) model=\(modelNumber)"
                )
            case .display:
                let (result, mediaCount) = try await displayOnce(options: command.options)
                print(
                    "display_transfer_complete device=\(result.deviceName) "
                        + "size=368x368 transferred_media_bytes=\(mediaCount)"
                )
            }
        } catch {
            FileHandle.standardError.write(Data("codex-ring: \(error)\n".utf8))
            Foundation.exit(2)
        }
    }

    private static func makeBindRequest() -> E01BindRequest {
        E01BindRequest(
            timestampMilliseconds: UInt64(Date().timeIntervalSince1970 * 1_000),
            usesNonChineseLocale: Locale.current.language.languageCode?.identifier.lowercased() != "zh",
            uses12HourClock: DateFormatter.dateFormat(
                fromTemplate: "j",
                options: 0,
                locale: .current
            )?.contains("a") == true
        )
    }

    private static func writeOutputLine(_ line: String) {
        FileHandle.standardOutput.write(Data("\(line)\n".utf8))
    }

    private static func displayOnce(options: RingCommandOptions) async throws -> (E01BindResult, Int) {
        let displayOptions = RingCommandOptions(
            sessionsDirectory: options.sessionsDirectory,
            outputURL: options.outputURL,
            size: CGSize(width: 368, height: 368),
            interval: options.interval,
            scanTimeout: options.scanTimeout
        )
        try renderOnce(options: displayOptions)
        let movieURL = options.outputURL
            .deletingLastPathComponent()
            .appending(path: "codex-ring-display.avi")
        try makeStillMovie(imageURL: options.outputURL, movieURL: movieURL)
        let media = try Data(contentsOf: movieURL)
        let result = try await E01BindController().display(
            media: media,
            fileName: "codex_push.avi",
            request: makeBindRequest(),
            timeout: max(options.scanTimeout, 120)
        )
        return (result, media.count)
    }

    private static func makeStillMovie(imageURL: URL, movieURL: URL) throws {
        let executable = URL(filePath: "/opt/homebrew/bin/ffmpeg")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw AppError.ffmpegUnavailable
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = E01MediaEncodingProfile.ffmpegArguments(
            imagePath: imageURL.path,
            moviePath: movieURL.path
        )
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw AppError.ffmpegFailed(process.terminationStatus)
        }
    }

    private static func makeRGB565(imageURL: URL, size: CGSize) throws -> Data {
        guard let imageData = try? Data(contentsOf: imageURL),
              let bitmap = NSBitmapImageRep(data: imageData),
              bitmap.pixelsWide == Int(size.width),
              bitmap.pixelsHigh == Int(size.height)
        else {
            throw AppError.imageDecodingFailed
        }

        var bytes = [UInt8]()
        bytes.reserveCapacity(bitmap.pixelsWide * bitmap.pixelsHigh * 2)
        for outputY in 0..<bitmap.pixelsHigh {
            let sourceY = bitmap.pixelsHigh - 1 - outputY
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: sourceY)?.usingColorSpace(.deviceRGB) else {
                    throw AppError.imageDecodingFailed
                }
                let red = UInt16((color.redComponent * 255).rounded())
                let green = UInt16((color.greenComponent * 255).rounded())
                let blue = UInt16((color.blueComponent * 255).rounded())
                let rgb565 = ((red >> 3) << 11) | ((green >> 2) << 5) | (blue >> 3)
                bytes.append(UInt8(truncatingIfNeeded: rgb565 >> 8))
                bytes.append(UInt8(truncatingIfNeeded: rgb565))
            }
        }
        return Data(bytes)
    }

    private static func renderOnce(options: RingCommandOptions) throws {
        let reader = CodexSessionReader()
        let renderer = RingCardRenderer()
        let now = Date()
        let data: Data

        if let snapshot = try reader.latestSnapshot(in: options.sessionsDirectory) {
            let presentation = snapshot.presentation(now: now)
            data = try renderer.render(presentation, size: options.size, now: now)
            print("primary_remaining=\(presentation.primary.remainingPercent) freshness=\(presentation.freshness)")
        } else {
            data = try renderer.renderUnavailable(size: options.size, now: now)
            print("no_usage_snapshot")
        }

        try FileManager.default.createDirectory(
            at: options.outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: options.outputURL, options: .atomic)
    }
}
