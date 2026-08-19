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
                let kimiSnapshot = await refreshedKimiSnapshot(previous: loadCachedKimiSnapshot())
                let dashboard = try makeDashboard(
                    options: command.options,
                    kimiSnapshot: kimiSnapshot,
                    now: Date()
                )
                try renderOnce(options: command.options, dashboard: dashboard)
            case .watch:
                var kimiSnapshot = loadCachedKimiSnapshot()
                while true {
                    kimiSnapshot = await refreshedKimiSnapshot(previous: kimiSnapshot)
                    let dashboard = try makeDashboard(
                        options: command.options,
                        kimiSnapshot: kimiSnapshot,
                        now: Date()
                    )
                    try renderOnce(options: command.options, dashboard: dashboard)
                    try await Task.sleep(for: .seconds(command.options.interval))
                }
            case .displayWatch:
                let stateStore = DisplaySyncStateStore()
                var syncState: DisplaySyncState
                do {
                    syncState = try stateStore.load() ?? DisplaySyncState()
                } catch {
                    syncState = DisplaySyncState()
                    FileHandle.standardError.write(
                        Data("display_sync_state_reset error=\(error)\n".utf8)
                    )
                }
                let reader = CodexSessionReader()
                var kimiSnapshot = loadCachedKimiSnapshot()
                var lastKimiRefreshAttemptAt: Date?
                var consecutiveFailures = 0
                while true {
                    var cycleOutcome = DisplaySyncCycleOutcome.noData
                    let refreshAttemptAt = Date()
                    if KimiUsageRefreshSchedule.shouldRefresh(
                        lastAttemptAt: lastKimiRefreshAttemptAt,
                        now: refreshAttemptAt
                    ) {
                        lastKimiRefreshAttemptAt = refreshAttemptAt
                        kimiSnapshot = await refreshedKimiSnapshot(previous: kimiSnapshot)
                    }
                    let now = Date()
                    let dashboard = QuotaDashboardPresentation(
                        codex: try reader.latestSnapshot(in: command.options.sessionsDirectory)?
                            .presentation(now: now),
                        kimi: kimiSnapshot?.presentation(now: now)
                    )
                    if dashboard.hasData {
                        let signature = dashboard.contentSignature
                        if syncState.shouldPush(
                            contentSignature: signature,
                            now: now,
                            maximumUnchangedAge: 300
                        ) {
                            do {
                                let previousMediaFileName = syncState.activeMediaFileName
                                let preferredMediaFileName = syncState.nextPreferredMediaFileName
                                let (result, mediaCount) = try await displayOnce(
                                    options: command.options,
                                    fileName: preferredMediaFileName,
                                    dashboard: dashboard
                                )
                                let committedMediaFileName = result.committedMediaFileName
                                    ?? preferredMediaFileName
                                syncState.recordSuccessfulPush(
                                    contentSignature: signature,
                                    at: Date(),
                                    activeMediaFileName: committedMediaFileName
                                )
                                do {
                                    try stateStore.save(syncState)
                                } catch {
                                    FileHandle.standardError.write(
                                        Data("display_sync_state_save_failed error=\(error)\n".utf8)
                                    )
                                }
                                writeOutputLine(
                                    "display_sync_complete device=\(result.deviceName) "
                                        + "\(dashboardLogFields(dashboard)) file=\(committedMediaFileName) "
                                        + "transferred_media_bytes=\(mediaCount)"
                                )
                                if let previousMediaFileName,
                                   previousMediaFileName != committedMediaFileName {
                                    do {
                                        try await cleanupPreviousMedia(
                                            previousMediaFileName,
                                            options: command.options
                                        )
                                    } catch {
                                        FileHandle.standardError.write(
                                            Data(
                                                ("display_sync_cleanup_deferred file=\(previousMediaFileName) "
                                                    + "error=\(error)\n").utf8
                                            )
                                        )
                                    }
                                }
                                cycleOutcome = .pushed
                                consecutiveFailures = 0
                            } catch {
                                cycleOutcome = .failed
                                consecutiveFailures += 1
                                if case let E01BindError.timedOut(stage) = error,
                                   E01KnownDeviceRecovery.shouldClearAfterTimeout(
                                       stage: stage,
                                       consecutiveFailures: consecutiveFailures
                                   ) {
                                    do {
                                        try E01KnownDeviceStore().clear()
                                        FileHandle.standardError.write(
                                            Data("display_sync_known_device_reset stage=\(stage)\n".utf8)
                                        )
                                        consecutiveFailures = 0
                                    } catch {
                                        FileHandle.standardError.write(
                                            Data("display_sync_known_device_reset_failed error=\(error)\n".utf8)
                                        )
                                    }
                                }
                                FileHandle.standardError.write(
                                    Data(
                                        ("display_sync_retry \(dashboardLogFields(dashboard)) "
                                            + "error=\(error)\n").utf8
                                    )
                                )
                            }
                        } else {
                            cycleOutcome = .unchanged
                            consecutiveFailures = 0
                            writeOutputLine("display_sync_unchanged \(dashboardLogFields(dashboard))")
                        }
                    } else {
                        consecutiveFailures = 0
                        FileHandle.standardError.write(Data("display_sync_waiting_for_usage\n".utf8))
                    }
                    let delay = DisplaySyncSchedule.delay(
                        after: cycleOutcome,
                        consecutiveFailures: consecutiveFailures,
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
            case .probe:
                let result = try await E01BindController().probeRCSP(
                    request: makeBindRequest(),
                    timeout: command.options.scanTimeout
                )
                print(
                    "probe_response device=\(result.deviceName) "
                        + "protocol=\(result.protocolVersion ?? "unknown") "
                        + "firmware=\(result.firmwareVersion ?? "unknown") "
                        + "platform=\(result.platform.map(String.init) ?? "unknown") "
                        + "model=\(result.modelNumber.map(String.init) ?? "unknown") "
                        + "rcsp_target=\(result.rcspTargetInfoHex ?? "unknown")"
                )
            case .cleanup:
                for fileName in ["codex_push001.avi", "codex_push002.avi", "codex_push003.avi"] {
                    let result = try await E01BindController().cleanupGeneratedMedia(
                        fileName: fileName,
                        request: makeBindRequest(),
                        timeout: command.options.scanTimeout
                    )
                    print("cleanup_complete device=\(result.deviceName) file=\(fileName)")
                }
            case .formatMedia:
                let result = try await E01BindController().formatMediaStorage(
                    request: makeBindRequest(),
                    timeout: command.options.scanTimeout
                )
                print("format_media_complete device=\(result.deviceName)")
            case .display:
                let kimiSnapshot = await refreshedKimiSnapshot(previous: loadCachedKimiSnapshot())
                let dashboard = try makeDashboard(
                    options: command.options,
                    kimiSnapshot: kimiSnapshot,
                    now: Date()
                )
                let (result, mediaCount) = try await displayOnce(
                    options: command.options,
                    fileName: "badge.avi",
                    dashboard: dashboard
                )
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

    private static func displayOnce(
        options: RingCommandOptions,
        fileName: String,
        dashboard: QuotaDashboardPresentation
    ) async throws -> (E01BindResult, Int) {
        let displayOptions = RingCommandOptions(
            sessionsDirectory: options.sessionsDirectory,
            outputURL: options.outputURL,
            size: CGSize(width: 368, height: 368),
            interval: options.interval,
            scanTimeout: options.scanTimeout
        )
        try renderOnce(options: displayOptions, dashboard: dashboard)
        let movieURL = options.outputURL
            .deletingLastPathComponent()
            .appending(path: "codex-ring-display.avi")
        try makeStillMovie(imageURL: options.outputURL, movieURL: movieURL)
        let media = try Data(contentsOf: movieURL)
        let result = try await E01BindController().display(
            media: media,
            fileName: fileName,
            request: makeBindRequest(),
            timeout: max(options.scanTimeout, 120)
        )
        return (result, media.count)
    }

    private static func cleanupPreviousMedia(
        _ fileName: String,
        options: RingCommandOptions
    ) async throws {
        try await Task.sleep(for: .seconds(1))
        let result = try await E01BindController().cleanupGeneratedMedia(
            fileName: fileName,
            request: makeBindRequest(),
            timeout: max(options.scanTimeout, 30)
        )
        writeOutputLine("display_sync_cleanup_complete device=\(result.deviceName) file=\(fileName)")
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

    private static func renderOnce(
        options: RingCommandOptions,
        dashboard: QuotaDashboardPresentation
    ) throws {
        let renderer = RingCardRenderer()
        let now = Date()
        let data = try renderer.renderDashboard(dashboard, size: options.size, now: now)
        print("quota_dashboard \(dashboardLogFields(dashboard))")

        try FileManager.default.createDirectory(
            at: options.outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: options.outputURL, options: .atomic)
    }

    private static func makeDashboard(
        options: RingCommandOptions,
        kimiSnapshot: KimiUsageSnapshot?,
        now: Date
    ) throws -> QuotaDashboardPresentation {
        QuotaDashboardPresentation(
            codex: try CodexSessionReader().latestSnapshot(in: options.sessionsDirectory)?
                .presentation(now: now),
            kimi: kimiSnapshot?.presentation(now: now)
        )
    }

    private static func loadCachedKimiSnapshot() -> KimiUsageSnapshot? {
        do {
            return try KimiUsageSnapshotStore().load()
        } catch {
            FileHandle.standardError.write(Data("kimi_usage_cache_load_failed error=\(error)\n".utf8))
            return nil
        }
    }

    private static func refreshedKimiSnapshot(
        previous: KimiUsageSnapshot?
    ) async -> KimiUsageSnapshot? {
        do {
            let snapshot = try await KimiUsageReader().latestSnapshot()
            do {
                try KimiUsageSnapshotStore().save(snapshot)
            } catch {
                FileHandle.standardError.write(
                    Data("kimi_usage_cache_save_failed error=\(error)\n".utf8)
                )
            }
            writeOutputLine(
                "kimi_usage_refresh_complete weekly_remaining=\(snapshot.weekly.remainingPercent) "
                    + "five_hour_remaining=\(snapshot.fiveHour.remainingPercent)"
            )
            return snapshot
        } catch {
            FileHandle.standardError.write(Data("kimi_usage_refresh_failed error=\(error)\n".utf8))
            return previous
        }
    }

    private static func dashboardLogFields(_ dashboard: QuotaDashboardPresentation) -> String {
        let codexRemaining = dashboard.codex.map { String($0.primary.remainingPercent) } ?? "unknown"
        let kimiWeekly = dashboard.kimi.map { String($0.weekly.remainingPercent) } ?? "unknown"
        let kimiFiveHour = dashboard.kimi.map { String($0.fiveHour.remainingPercent) } ?? "unknown"
        return "codex_remaining=\(codexRemaining) kimi_weekly_remaining=\(kimiWeekly) "
            + "kimi_five_hour_remaining=\(kimiFiveHour)"
    }
}
