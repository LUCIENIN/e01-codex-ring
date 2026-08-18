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
                let displaySize = CGSize(width: 368, height: 368)
                let displayOptions = RingCommandOptions(
                    sessionsDirectory: command.options.sessionsDirectory,
                    outputURL: command.options.outputURL,
                    size: displaySize,
                    interval: command.options.interval,
                    scanTimeout: command.options.scanTimeout
                )
                try renderOnce(options: displayOptions)
                let movieURL = command.options.outputURL
                    .deletingLastPathComponent()
                    .appending(path: "codex-ring-display.avi")
                try makeStillMovie(imageURL: command.options.outputURL, movieURL: movieURL)
                let media = try Data(contentsOf: movieURL)
                let result = try await E01BindController().display(
                    media: media,
                    fileName: "CODEX.AVI",
                    request: makeBindRequest(),
                    timeout: max(command.options.scanTimeout, 120)
                )
                print(
                    "display_transfer_complete device=\(result.deviceName) "
                        + "size=368x368 transferred_media_bytes=\(media.count)"
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
