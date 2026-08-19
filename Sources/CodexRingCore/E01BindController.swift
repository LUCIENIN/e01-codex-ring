import CoreBluetooth
import Foundation

public struct E01BindResult: Equatable, Sendable {
    public let deviceName: String
    public let responseLength: Int
    public let displaySize: E01PictureSize
    public let memoryBytes: UInt32
    public let protocolVersion: String?
    public let firmwareVersion: String?
    public let platform: UInt8?
    public let modelNumber: UInt16?
    public let rcspTargetInfoHex: String?

    public init(
        deviceName: String,
        responseLength: Int,
        displaySize: E01PictureSize,
        memoryBytes: UInt32,
        protocolVersion: String? = nil,
        firmwareVersion: String? = nil,
        platform: UInt8? = nil,
        modelNumber: UInt16? = nil,
        rcspTargetInfoHex: String? = nil
    ) {
        self.deviceName = deviceName
        self.responseLength = responseLength
        self.displaySize = displaySize
        self.memoryBytes = memoryBytes
        self.protocolVersion = protocolVersion
        self.firmwareVersion = firmwareVersion
        self.platform = platform
        self.modelNumber = modelNumber
        self.rcspTargetInfoHex = rcspTargetInfoHex
    }
}

public enum E01BindError: Error, Equatable, Sendable {
    case invalidTimeout
    case bluetoothUnavailable
    case deviceNotFound
    case connectFailed
    case missingDataService
    case missingRCSPService
    case missingWriteCharacteristic
    case notificationUnavailable
    case notificationFailed
    case writeUnsupported
    case writeFailed
    case noBindResponse(
        primaryEvents: Int,
        auxiliaryEvents: Int,
        primaryBytes: Int,
        auxiliaryBytes: Int,
        packetHeaders: [String]
    )
    case noBadgeInfoResponse(packetHeaders: [String])
    case noRCSPResponse(packetHeaders: [String])
    case noRCSPAuthResponse(packetHeaders: [String])
    case rcspAuthFailed
    case rcspRejected(opcode: UInt8, status: UInt8)
    case missingSDCard
    case invalidTransferRequest
    case transferFailed(reason: UInt8)
    case timedOut(stage: String)
}

/// Runs the E01 normal-data bind handshake and, only for `probeRCSP`/`display`, the allowlisted
/// Jieli RCSP service. `display` uses the vendor's ordinary large-file media transfer; it does not
/// send firmware-update or QR-card commands.
public final class E01BindController: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate, @unchecked Sendable {
    private struct NormalWriteJob {
        let data: Data
        let stage: String
        let isFinalFragment: Bool
    }

    private struct RCSPWriteJob {
        let data: Data
        let stage: String
        let isFinalFragment: Bool
    }

    private static let writeCharacteristicUUIDString = "C2E6FD02-E966-1000-8000-BEF9C223DF6A"
    private static let primaryNotifyCharacteristicUUIDString = "C2E6FD01-E966-1000-8000-BEF9C223DF6A"
    private static let auxiliaryNotifyCharacteristicUUIDString = "C2E6FD03-E966-1000-8000-BEF9C223DF6A"
    private static let rcspServiceUUIDString = E01SafetyPolicy.rcspServiceUUID
    private static let rcspWriteCharacteristicUUIDString = E01SafetyPolicy.rcspWriteCharacteristicUUID
    private static let rcspNotifyCharacteristicUUIDString = E01SafetyPolicy.rcspNotifyCharacteristicUUID

    private let queue = DispatchQueue(label: "CodexRing.E01Bind")
    private var centralManager: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var primaryNotificationCharacteristic: CBCharacteristic?
    private var auxiliaryNotificationCharacteristic: CBCharacteristic?
    private var rcspWriteCharacteristic: CBCharacteristic?
    private var rcspNotificationCharacteristic: CBCharacteristic?
    private var normalCharacteristicsDiscovered = false
    private var rcspCharacteristicsDiscovered = false
    private var packet: [UInt8] = []
    private var continuation: CheckedContinuation<E01BindResult, Error>?
    private var timeoutWorkItem: DispatchWorkItem?
    private var writeWasAcknowledged = false
    private var primaryResponseAssembler = E01NormalDataResponseAssembler()
    private var auxiliaryResponseAssembler = E01NormalDataResponseAssembler()
    private var primaryNotificationEvents = 0
    private var auxiliaryNotificationEvents = 0
    private var primaryNotificationBytes = 0
    private var auxiliaryNotificationBytes = 0
    private var notificationPacketHeaders: [String] = []
    private var stage = "waiting_for_bluetooth"
    private var shouldProbeRCSP = false
    private var rcspParser = E01RCSPFrame.Parser()
    private var rcspAuthenticator = E01RCSPAuthenticator()
    private var badgeResult: E01BindResult?
    private var bindIdentity: E01BindIdentityResponse?
    private var mediaBytes: [UInt8]?
    private var mediaFileName = "CODEX.AVI"
    private var rcspSerialNumber: UInt8 = 0
    private var storageHandler: UInt32?
    private var firmwareUsesTransferCRC = false
    private var rcspWriteQueue: [RCSPWriteJob] = []
    private var activeRCSPWrite: RCSPWriteJob?
    private var transferPacketSize = 0
    private var lastReadRequest: E01RCSPTransferProtocol.ReadRequest?
    private var transferProgressStage = "waiting_for_transfer_requests"
    private var normalWriteQueue: [NormalWriteJob] = []
    private var activeNormalWrite: NormalWriteJob?
    private var videoDialUpdateData: [UInt8]?
    private var updateAllowedLength = 0
    private var updateSerialNumber: UInt8 = 0
    private var updateHeaderIndex = 0
    private let knownDeviceStore = E01KnownDeviceStore()
    private var usedKnownDevice = false

    public func bind(
        request: E01BindRequest,
        timeout: TimeInterval
    ) async throws -> E01BindResult {
        try await start(request: request, timeout: timeout, shouldProbeRCSP: false)
    }

    public func probeRCSP(
        request: E01BindRequest,
        timeout: TimeInterval
    ) async throws -> E01BindResult {
        try await start(request: request, timeout: timeout, shouldProbeRCSP: true)
    }

    public func display(
        media: Data,
        fileName: String = "CODEX.AVI",
        request: E01BindRequest,
        timeout: TimeInterval
    ) async throws -> E01BindResult {
        try await start(
            request: request,
            timeout: timeout,
            shouldProbeRCSP: true,
            mediaBytes: [UInt8](media),
            mediaFileName: fileName
        )
    }

    private func start(
        request: E01BindRequest,
        timeout: TimeInterval,
        shouldProbeRCSP: Bool,
        mediaBytes: [UInt8]? = nil,
        mediaFileName: String = "CODEX.AVI"
    ) async throws -> E01BindResult {
        guard (5...180).contains(timeout) else {
            throw E01BindError.invalidTimeout
        }

        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [weak self] in
                guard let self, self.continuation == nil else {
                    continuation.resume(throwing: E01BindError.bluetoothUnavailable)
                    return
                }

                self.continuation = continuation
                self.packet = E01NormalDataFrame.firstBindPacket(request)
                self.writeWasAcknowledged = false
                self.primaryResponseAssembler = E01NormalDataResponseAssembler()
                self.auxiliaryResponseAssembler = E01NormalDataResponseAssembler()
                self.primaryNotificationEvents = 0
                self.auxiliaryNotificationEvents = 0
                self.primaryNotificationBytes = 0
                self.auxiliaryNotificationBytes = 0
                self.notificationPacketHeaders = []
                self.shouldProbeRCSP = shouldProbeRCSP
                self.rcspParser = E01RCSPFrame.Parser()
                self.rcspAuthenticator = E01RCSPAuthenticator()
                self.badgeResult = nil
                self.bindIdentity = nil
                self.mediaBytes = mediaBytes
                self.mediaFileName = mediaFileName
                self.rcspSerialNumber = 0
                self.storageHandler = nil
                self.firmwareUsesTransferCRC = false
                self.rcspWriteQueue = []
                self.activeRCSPWrite = nil
                self.transferPacketSize = 0
                self.lastReadRequest = nil
                self.transferProgressStage = "waiting_for_transfer_requests"
                self.normalWriteQueue = []
                self.activeNormalWrite = nil
                self.videoDialUpdateData = nil
                self.updateAllowedLength = 0
                self.updateSerialNumber = 0
                self.updateHeaderIndex = 0
                self.usedKnownDevice = false
                self.normalCharacteristicsDiscovered = false
                self.rcspCharacteristicsDiscovered = false
                self.stage = "waiting_for_bluetooth"
                self.centralManager = CBCentralManager(delegate: self, queue: self.queue)
                let timeoutWorkItem = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    if self.usedKnownDevice,
                       (self.stage == "connecting" || self.stage == "discovering_service") {
                        try? self.knownDeviceStore.clear()
                        self.traceTransfer("known_device_cleared_after_timeout")
                    }
                    let error: E01BindError
                    if self.stage.contains("rcsp_auth") {
                        error = .noRCSPAuthResponse(packetHeaders: self.notificationPacketHeaders)
                    } else if self.stage == "writing_rcsp_probe" || self.stage == "waiting_for_rcsp_probe" {
                        error = .noRCSPResponse(packetHeaders: self.notificationPacketHeaders)
                    } else if self.stage == "writing_badge_info_request"
                        || self.stage == "waiting_for_badge_info_response" {
                        error = .noBadgeInfoResponse(packetHeaders: self.notificationPacketHeaders)
                    } else if self.stage.contains("transfer") || self.stage.contains("update")
                        || self.stage.hasPrefix("transferring_") {
                        error = .timedOut(stage: self.stage)
                    } else {
                        error = self.writeWasAcknowledged
                            ? .noBindResponse(
                                primaryEvents: self.primaryNotificationEvents,
                                auxiliaryEvents: self.auxiliaryNotificationEvents,
                                primaryBytes: self.primaryNotificationBytes,
                                auxiliaryBytes: self.auxiliaryNotificationBytes,
                                packetHeaders: self.notificationPacketHeaders
                            )
                            : .timedOut(stage: self.stage)
                    }
                    self.finish(with: .failure(error))
                }
                self.timeoutWorkItem = timeoutWorkItem
                self.queue.asyncAfter(deadline: .now() + timeout, execute: timeoutWorkItem)
            }
        }
    }

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if let identifier = knownDeviceStore.load(),
               let peripheral = central.retrievePeripherals(withIdentifiers: [identifier]).first {
                usedKnownDevice = true
                traceTransfer("known_device_retrieved")
                connect(peripheral, using: central)
                return
            }
            usedKnownDevice = false
            stage = "scanning"
            central.scanForPeripherals(
                withServices: Self.advertisedDataServiceAliases(),
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
            )
        case .unknown, .resetting:
            break
        default:
            finish(with: .failure(.bluetoothUnavailable))
        }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard self.peripheral == nil else { return }
        let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        guard E01DiscoveryController.makeCandidate(
            identifier: peripheral.identifier,
            name: peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String,
            advertisedServiceUUIDs: serviceUUIDs
        ) != nil else {
            return
        }

        usedKnownDevice = false
        traceTransfer("device_discovered rssi=\(RSSI)")
        connect(peripheral, using: central)
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        traceTransfer("device_connected")
        stage = "discovering_service"
        var services = Self.regularDataServiceAliases()
        if shouldProbeRCSP {
            services.append(Self.rcspServiceUUID())
        }
        peripheral.discoverServices(services)
    }

    public func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        traceTransfer("device_connect_failed")
        finish(with: .failure(.connectFailed))
    }

    private func connect(_ peripheral: CBPeripheral, using central: CBCentralManager) {
        central.stopScan()
        stage = "connecting"
        self.peripheral = peripheral
        peripheral.delegate = self
        central.connect(peripheral)
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil,
              let service = peripheral.services?.first(where: { $0.uuid == Self.dataServiceUUID() })
        else {
            finish(with: .failure(.missingDataService))
            return
        }
        try? knownDeviceStore.save(peripheral.identifier)
        traceTransfer("known_device_saved")

        // The E01 advertises the service in short form (`FD00`). Its characteristic UUID
        // representation is device/stack dependent, so enumerate only this already-confirmed
        // normal service and retain the existing strict FD01/FD02 allowlist below.
        peripheral.discoverCharacteristics(nil, for: service)
        if shouldProbeRCSP {
            guard let rcspService = peripheral.services?.first(where: { $0.uuid == Self.rcspServiceUUID() }) else {
                finish(with: .failure(.missingRCSPService))
                return
            }
            peripheral.discoverCharacteristics(
                [Self.rcspWriteCharacteristicUUID(), Self.rcspNotifyCharacteristicUUID()],
                for: rcspService
            )
        }
        stage = "discovering_characteristics"
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard error == nil else {
            finish(with: .failure(service.uuid == Self.rcspServiceUUID() ? .missingRCSPService : .missingDataService))
            return
        }

        if service.uuid == Self.dataServiceUUID() {
            for characteristic in service.characteristics ?? [] {
                traceTransfer(
                    "characteristic uuid=\(characteristic.uuid.uuidString) "
                        + "properties=\(characteristic.properties.rawValue)"
                )
                switch characteristic.uuid {
                case Self.primaryNotifyCharacteristicUUID():
                    primaryNotificationCharacteristic = characteristic
                case Self.auxiliaryNotifyCharacteristicUUID():
                    auxiliaryNotificationCharacteristic = characteristic
                case Self.writeCharacteristicUUID():
                    writeCharacteristic = characteristic
                default:
                    continue
                }
            }
            normalCharacteristicsDiscovered = true
        } else if service.uuid == Self.rcspServiceUUID() {
            for characteristic in service.characteristics ?? [] {
                switch characteristic.uuid {
                case Self.rcspWriteCharacteristicUUID():
                    rcspWriteCharacteristic = characteristic
                case Self.rcspNotifyCharacteristicUUID():
                    rcspNotificationCharacteristic = characteristic
                default:
                    continue
                }
            }
            rcspCharacteristicsDiscovered = true
        } else {
            return
        }

        startNotificationsIfReady(peripheral)
    }

    private func startNotificationsIfReady(_ peripheral: CBPeripheral) {
        guard normalCharacteristicsDiscovered,
              !shouldProbeRCSP || rcspCharacteristicsDiscovered
        else { return }

        guard let primaryNotificationCharacteristic,
              primaryNotificationCharacteristic.properties.contains(.notify),
              let auxiliaryNotificationCharacteristic,
              auxiliaryNotificationCharacteristic.properties.contains(.notify)
        else {
            finish(with: .failure(.notificationUnavailable))
            return
        }
        guard let writeCharacteristic else {
            finish(with: .failure(.missingWriteCharacteristic))
            return
        }
        guard writeCharacteristic.properties.contains(.write) else {
            finish(with: .failure(.writeUnsupported))
            return
        }
        if shouldProbeRCSP {
            guard let rcspNotificationCharacteristic,
                  rcspNotificationCharacteristic.properties.contains(.notify),
                  let rcspWriteCharacteristic,
                  rcspWriteCharacteristic.properties.contains(.write)
                    || rcspWriteCharacteristic.properties.contains(.writeWithoutResponse)
            else {
                finish(with: .failure(.notificationUnavailable))
                return
            }
        }

        stage = "enabling_primary_notification"
        peripheral.setNotifyValue(true, for: primaryNotificationCharacteristic)
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard continuation != nil else { return }
        guard characteristic.uuid == Self.primaryNotifyCharacteristicUUID()
                || characteristic.uuid == Self.auxiliaryNotifyCharacteristicUUID()
                || characteristic.uuid == Self.rcspNotifyCharacteristicUUID()
        else { return }
        guard error == nil, characteristic.isNotifying else {
            finish(with: .failure(.notificationFailed))
            return
        }

        if characteristic.uuid == Self.primaryNotifyCharacteristicUUID() {
            guard let auxiliaryNotificationCharacteristic else {
                finish(with: .failure(.notificationUnavailable))
                return
            }
            stage = "enabling_auxiliary_notification"
            peripheral.setNotifyValue(true, for: auxiliaryNotificationCharacteristic)
            return
        }

        if characteristic.uuid == Self.auxiliaryNotifyCharacteristicUUID(), shouldProbeRCSP {
            guard let rcspNotificationCharacteristic else {
                finish(with: .failure(.notificationUnavailable))
                return
            }
            stage = "enabling_rcsp_notification"
            peripheral.setNotifyValue(true, for: rcspNotificationCharacteristic)
            return
        }

        if characteristic.uuid == Self.rcspNotifyCharacteristicUUID() {
            writeNormal(packet, stage: "writing_bind_request")
            return
        }

        writeNormal(packet, stage: "writing_bind_request")
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard characteristic.uuid == Self.writeCharacteristicUUID()
                || characteristic.uuid == Self.auxiliaryNotifyCharacteristicUUID()
                || characteristic.uuid == Self.rcspWriteCharacteristicUUID()
        else { return }
        guard error == nil else {
            finish(with: .failure(.writeFailed))
            return
        }
        let completedStage: String
        if characteristic.uuid == Self.rcspWriteCharacteristicUUID(), let activeRCSPWrite {
            completedStage = activeRCSPWrite.stage
            let wasFinal = activeRCSPWrite.isFinalFragment
            self.activeRCSPWrite = nil
            sendNextQueuedRCSPWrite()
            guard wasFinal else { return }
        } else if characteristic.uuid == Self.writeCharacteristicUUID(), let activeNormalWrite {
            completedStage = activeNormalWrite.stage
            let wasFinal = activeNormalWrite.isFinalFragment
            self.activeNormalWrite = nil
            sendNextQueuedNormalWrite()
            guard wasFinal else { return }
        } else {
            completedStage = stage
        }
        // A notification may advance the state machine before CoreBluetooth reports the
        // corresponding write callback. Never overwrite that newer stage with stale state.
        guard stage == completedStage else { return }
        switch completedStage {
        case "writing_bind_request":
            writeWasAcknowledged = true
            stage = "waiting_for_bind_response"
        case "writing_badge_info_request":
            stage = "waiting_for_badge_info_response"
        case "writing_rcsp_probe":
            stage = "waiting_for_rcsp_probe"
        case "writing_rcsp_auth":
            stage = "waiting_for_rcsp_auth"
        case "writing_rcsp_auth_reset":
            stage = "waiting_for_rcsp_auth_reset"
        case "writing_video_info_request":
            stage = "waiting_for_video_info_response"
        case "writing_update_start":
            stage = "waiting_for_update_request"
        case "writing_update_data":
            stage = "waiting_for_update_progress"
        default:
            break
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil, let value = characteristic.value else {
            return
        }

        // Preserve only a short protocol prefix for failed-handshake diagnostics. The response
        // payload can contain a device serial number, so never retain or print the full packet.
        let prefix = value.prefix(8).map { String(format: "%02X", $0) }.joined()
        notificationPacketHeaders.append("\(characteristic.uuid.uuidString):\(value.count):\(prefix)")

        if shouldProbeRCSP, characteristic.uuid == Self.rcspNotifyCharacteristicUUID() {
            if stage.contains("rcsp_auth") {
                do {
                    switch try rcspAuthenticator.handle([UInt8](value)) {
                    case let .send(bytes):
                        try writeRCSP(bytes, stage: "writing_rcsp_auth")
                    case .authenticated:
                        // Media files use the device's proven RCSP file-transfer path.
                        // The normal-service C0 dial updater rejects this E01 firmware
                        // before it requests any payload bytes.
                        sendRCSPProbe()
                    case .failed:
                        finish(with: .failure(.rcspAuthFailed))
                    case .ignored:
                        break
                    }
                } catch {
                    finish(with: .failure(.rcspAuthFailed))
                }
                return
            }
            for packet in rcspParser.append([UInt8](value)) {
                handleRCSPPacket(packet)
                guard continuation != nil else { return }
            }
            return
        }

        let bytes: [UInt8]?
        switch characteristic.uuid {
        case Self.primaryNotifyCharacteristicUUID():
            primaryNotificationEvents += 1
            primaryNotificationBytes += value.count
            bytes = primaryResponseAssembler.append([UInt8](value))
        case Self.auxiliaryNotifyCharacteristicUUID():
            auxiliaryNotificationEvents += 1
            auxiliaryNotificationBytes += value.count
            bytes = auxiliaryResponseAssembler.append([UInt8](value))
        default:
            return
        }

        guard let bytes else { return }
        traceTransfer(String(format: "normal_frame command=%02X bytes=%d stage=%@", bytes[3], bytes.count, stage))

        if let request = E01VideoDialProtocol.parseUpdateRequest(bytes),
           stage == "writing_update_start" || stage == "waiting_for_update_request" {
            guard request.status == 1 else {
                finish(with: .failure(.transferFailed(reason: request.status)))
                return
            }
            updateAllowedLength = request.allowedLength
            sendNextVideoDialChunk(offset: request.offset)
            return
        }

        if let progress = E01VideoDialProtocol.parseProgress(bytes),
           stage == "writing_update_data" || stage == "waiting_for_update_progress" {
            guard progress.status == 0 else {
                finish(with: .failure(.transferFailed(reason: progress.status)))
                return
            }
            if let videoDialUpdateData, progress.offset < videoDialUpdateData.count {
                sendNextVideoDialChunk(offset: progress.offset)
            } else {
                stage = "waiting_for_update_result"
            }
            return
        }

        if let reason = E01VideoDialProtocol.parseResult(bytes), stage.contains("update") {
            if reason == 5,
               (stage == "writing_update_start" || stage == "waiting_for_update_request"),
               updateHeaderIndex < 31 {
                updateHeaderIndex += 1
                traceTransfer("authenticated_static_dial_slot_retry index=\(updateHeaderIndex)")
                startVideoDialUpdate(headerIndex: updateHeaderIndex)
                return
            }
            guard reason == 0, let badgeResult else {
                finish(with: .failure(.transferFailed(reason: reason)))
                return
            }
            queue.asyncAfter(deadline: .now() + .milliseconds(300)) { [weak self] in
                self?.finish(with: .success(badgeResult))
            }
            return
        }

        // A peripheral notification can arrive before CoreBluetooth delivers the
        // with-response write callback. Accept the response in either ordering.
        if (stage == "writing_bind_request" || stage == "waiting_for_bind_response"),
           E01BindResponseValidator.isExplicitBindResponse(bytes) {
            bindIdentity = E01BindIdentityResponse.parse(bytes)
            packet = E01NormalDataFrame.packet(command: 0xC6, payload: [0x01], serialNumber: 1)
            writeNormal(packet, stage: "writing_badge_info_request")
            return
        }

        if (stage == "writing_badge_info_request" || stage == "waiting_for_badge_info_response"),
           let badgeInfo = E01BadgeInfoResponse.parse(bytes) {
            traceTransfer("badge_info picture=\(badgeInfo.pictureWidth)x\(badgeInfo.pictureHeight) memory=\(badgeInfo.memoryBytes)")
            let result = E01BindResult(
                deviceName: peripheral.name ?? "E01",
                responseLength: bytes.count,
                displaySize: E01PictureSize(
                    width: badgeInfo.pictureWidth,
                    height: badgeInfo.pictureHeight
                ),
                memoryBytes: badgeInfo.memoryBytes,
                protocolVersion: bindIdentity?.protocolVersion,
                firmwareVersion: bindIdentity?.firmwareVersion,
                platform: bindIdentity?.platform,
                modelNumber: bindIdentity?.modelNumber
            )
            guard shouldProbeRCSP else {
                guard let mediaBytes else {
                    finish(with: .success(result))
                    return
                }
                badgeResult = result
                _ = mediaBytes
                startVideoDialUpdate(headerIndex: 0)
                return
            }
            badgeResult = result
            switch E01DisplayPreparation.nextStepAfterBadgeInfo() {
            case .authenticateRCSP:
                startRCSPAuthentication()
            }
            return
        }
    }

    private func startVideoDialUpdate(headerIndex: Int) {
        guard let mediaBytes, let badgeResult else {
            finish(with: .failure(.invalidTransferRequest))
            return
        }
        let wrapped: [UInt8]
        if mediaFileName.uppercased().hasSuffix(".AVI") {
            wrapped = E01VideoDialProtocol.wrapAVI(
                mediaBytes,
                width: badgeResult.displaySize.width,
                height: badgeResult.displaySize.height,
                backgroundSupportFlag: headerIndex,
                usesAnimatedHeader: false
            )
        } else {
            wrapped = E01VideoDialProtocol.wrapRGB565(
                mediaBytes,
                width: badgeResult.displaySize.width,
                height: badgeResult.displaySize.height,
                dialIndex: headerIndex
            )
        }
        videoDialUpdateData = Array(wrapped.dropFirst(27))
        writeUpdateCommand(
            command: 0xC0,
            payload: Array(wrapped.prefix(27)),
            stage: "writing_update_start"
        )
    }

    private func sendNextVideoDialChunk(offset: Int) {
        guard let videoDialUpdateData,
              let payload = E01VideoDialProtocol.dataPayload(
                data: videoDialUpdateData,
                allowedLength: updateAllowedLength,
                offset: offset
              )
        else {
            finish(with: .failure(.invalidTransferRequest))
            return
        }
        traceTransfer("dial_update offset=\(offset) length=\(payload.count - 8) total=\(videoDialUpdateData.count)")
        writeUpdateCommand(command: 0xC2, payload: payload, stage: "writing_update_data")
    }

    private func writeUpdateCommand(command: UInt8, payload: [UInt8], stage: String) {
        let packet = E01VideoDialProtocol.commandPacket(
            command: command,
            payload: payload,
            serialNumber: updateSerialNumber
        )
        updateSerialNumber = (updateSerialNumber + 1) & 0x0F
        writeNormal(packet, stage: stage)
    }

    private func writeControlPoint(_ bytes: [UInt8], stage: String) {
        guard let peripheral,
              let auxiliaryNotificationCharacteristic,
              auxiliaryNotificationCharacteristic.properties.contains(.write)
                || auxiliaryNotificationCharacteristic.properties.contains(.writeWithoutResponse)
        else {
            finish(with: .failure(.writeUnsupported))
            return
        }
        self.stage = stage
        let writeType: CBCharacteristicWriteType = auxiliaryNotificationCharacteristic.properties.contains(.write)
            ? .withResponse
            : .withoutResponse
        traceTransfer(String(format: "control_write command=%02X bytes=%d stage=%@", bytes[3], bytes.count, stage))
        peripheral.writeValue(Data(bytes), for: auxiliaryNotificationCharacteristic, type: writeType)
        if writeType == .withoutResponse {
            self.stage = "waiting_for_video_info_response"
        }
    }

    private func writeNormal(_ bytes: [UInt8], stage: String) {
        guard let peripheral, writeCharacteristic != nil else {
            finish(with: .failure(.missingWriteCharacteristic))
            return
        }
        let maximumLength = max(20, peripheral.maximumWriteValueLength(for: .withResponse))
        traceTransfer(String(format: "normal_write command=%02X bytes=%d stage=%@ mtu=%d", bytes.count > 3 ? bytes[3] : 0, bytes.count, stage, maximumLength))
        var offset = 0
        while offset < bytes.count {
            let end = min(offset + maximumLength, bytes.count)
            normalWriteQueue.append(NormalWriteJob(
                data: Data(bytes[offset..<end]),
                stage: stage,
                isFinalFragment: end == bytes.count
            ))
            offset = end
        }
        self.stage = stage
        sendNextQueuedNormalWrite()
    }

    private func sendNextQueuedNormalWrite() {
        guard activeNormalWrite == nil,
              !normalWriteQueue.isEmpty,
              let peripheral,
              let writeCharacteristic
        else { return }
        let job = normalWriteQueue.removeFirst()
        activeNormalWrite = job
        peripheral.writeValue(job.data, for: writeCharacteristic, type: .withResponse)
    }

    private func startRCSPAuthentication() {
        do {
            let authStart = try rcspAuthenticator.start(
                randomBytes: (0..<16).map { _ in UInt8.random(in: .min ... .max) }
            )
            try writeRCSP(
                [0xFE, 0xDC, 0xBA, 0xC0, 0x06, 0x00, 0x02, 0x00, 0x01, 0xEF],
                stage: "writing_rcsp_auth_reset"
            )
            queue.asyncAfter(deadline: .now() + .milliseconds(50)) { [weak self] in
                guard let self, self.continuation != nil else { return }
                do {
                    try self.writeRCSP(authStart, stage: "writing_rcsp_auth")
                } catch {
                    self.finish(with: .failure(.rcspAuthFailed))
                }
            }
        } catch {
            finish(with: .failure(.rcspAuthFailed))
        }
    }

    private func sendRCSPProbe() {
        let request = E01RCSPFrame.command(
            opcode: 0x03,
            serialNumber: nextRCSPSerialNumber(),
            parameter: [0xFF, 0xFF, 0xFF, 0xFF, 0x00]
        )
        do {
            try writeRCSP(request, stage: "writing_rcsp_probe")
        } catch {
            finish(with: .failure(.writeFailed))
        }
    }

    private func handleRCSPPacket(_ packet: E01RCSPFrame.Packet) {
        if packet.isCommand {
            handleRCSPCommand(packet)
            return
        }

        guard packet.status == 0 else {
            finish(with: .failure(.rcspRejected(opcode: packet.opcode, status: packet.status ?? 0xFF)))
            return
        }
        switch packet.opcode {
        case 0x03:
            guard mediaBytes != nil else {
                guard let badgeResult else { return }
                let inspectedResult = E01BindResult(
                    deviceName: badgeResult.deviceName,
                    responseLength: badgeResult.responseLength,
                    displaySize: badgeResult.displaySize,
                    memoryBytes: badgeResult.memoryBytes,
                    protocolVersion: badgeResult.protocolVersion,
                    firmwareVersion: badgeResult.firmwareVersion,
                    platform: badgeResult.platform,
                    modelNumber: badgeResult.modelNumber,
                    rcspTargetInfoHex: packet.parameter.map { String(format: "%02X", $0) }.joined()
                )
                finish(with: .success(inspectedResult))
                return
            }
            sendCommand(
                opcode: 0x07,
                parameter: E01RCSPTransferProtocol.getStorageParameter(),
                stage: "waiting_for_storage"
            )
        case 0x07:
            guard let handler = E01RCSPTransferProtocol.sdCardOneHandler(
                fromGetSysInfoParameter: packet.parameter
            ) else {
                finish(with: .failure(.missingSDCard))
                return
            }
            storageHandler = handler
            sendCommand(
                opcode: 0x21,
                parameter: [0x00],
                stage: "waiting_for_transfer_prepare"
            )
        case 0x21:
            guard let storageHandler else {
                finish(with: .failure(.missingSDCard))
                return
            }
            sendCommand(
                opcode: 0x27,
                parameter: E01RCSPTransferProtocol.deviceExtendParameter(deviceHandler: storageHandler),
                stage: "waiting_for_transfer_capability"
            )
        case 0x27:
            firmwareUsesTransferCRC = packet.parameter.last == 1
            guard let mediaBytes else { return }
            let parameter = E01RCSPTransferProtocol.startParameter(
                fileSize: mediaBytes.count,
                crc16: E01RCSPTransferProtocol.crc16(mediaBytes),
                temporaryPath: "CODEXRNG.tmp"
            )
            sendCommand(opcode: 0x1B, parameter: parameter, stage: "waiting_for_transfer_start")
        case 0x1B:
            if packet.parameter.count >= 2 {
                transferPacketSize = (Int(packet.parameter[0]) << 8) | Int(packet.parameter[1])
            }
            guard transferPacketSize > 0 else {
                finish(with: .failure(.invalidTransferRequest))
                return
            }
            stage = "waiting_for_transfer_requests"
        case 0x01:
            break
        default:
            break
        }
    }

    private func handleRCSPCommand(_ packet: E01RCSPFrame.Packet) {
        switch packet.opcode {
        case 0x1D:
            guard let request = E01RCSPTransferProtocol.readRequest(from: packet.parameter),
                  let mediaBytes,
                  transferPacketSize > 0,
                  request.offset >= 0,
                  request.length > 0,
                  request.offset < mediaBytes.count
            else {
                finish(with: .failure(.invalidTransferRequest))
                return
            }
            if lastReadRequest == request {
                traceTransfer("duplicate_read_ignored offset=\(request.offset) length=\(request.length)")
                return
            }
            lastReadRequest = request
            let endOffset = min(request.offset + request.length, mediaBytes.count)
            let chunk = Array(mediaBytes[request.offset..<endOffset])
            let payloads = E01RCSPTransferProtocol.dataPayloads(
                chunk,
                packetSize: transferPacketSize,
                usesCRC16: firmwareUsesTransferCRC
            )
            traceTransfer(
                "read offset=\(request.offset) length=\(request.length) "
                    + "packets=\(payloads.count) mtu=\(transferPacketSize) crc=\(firmwareUsesTransferCRC ? 1 : 0)"
            )
            transferProgressStage = "transferring_\(endOffset)_of_\(mediaBytes.count)"
            for payload in payloads {
                let frame = E01RCSPFrame.command(
                    opcode: 0x01,
                    serialNumber: nextRCSPSerialNumber(),
                    parameter: [UInt8(0x1D)] + payload,
                    requestsResponse: false
                )
                do {
                    try writeRCSP(frame, stage: transferProgressStage)
                } catch {
                    finish(with: .failure(.writeFailed))
                    return
                }
            }
        case 0x20:
            let nameParameter = Array(mediaFileName.utf8) + [0x00, 0x00]
            do {
                try writeRCSP(
                    E01RCSPFrame.response(
                        opcode: packet.opcode,
                        serialNumber: packet.serialNumber,
                        status: 0,
                        parameter: nameParameter
                    ),
                    stage: "waiting_for_transfer_finish"
                )
            } catch {
                finish(with: .failure(.writeFailed))
            }
        case 0x1C:
            let reason = packet.parameter.first ?? 0xFF
            do {
                try writeRCSP(
                    E01RCSPFrame.response(
                        opcode: packet.opcode,
                        serialNumber: packet.serialNumber,
                        status: 0
                    ),
                    stage: "acknowledging_transfer_finish"
                )
            } catch {
                finish(with: .failure(.writeFailed))
                return
            }
            guard reason == 0, let badgeResult else {
                finish(with: .failure(.transferFailed(reason: reason)))
                return
            }
            queue.asyncAfter(deadline: .now() + .milliseconds(150)) { [weak self] in
                self?.finish(with: .success(badgeResult))
            }
        case 0x1E:
            finish(with: .failure(.transferFailed(reason: packet.parameter.first ?? 0xFF)))
        default:
            break
        }
    }

    private func traceTransfer(_ message: String) {
        FileHandle.standardError.write(Data("rcsp_transfer \(message)\n".utf8))
    }

    private func sendCommand(opcode: UInt8, parameter: [UInt8], stage: String) {
        do {
            try writeRCSP(
                E01RCSPFrame.command(
                    opcode: opcode,
                    serialNumber: nextRCSPSerialNumber(),
                    parameter: parameter
                ),
                stage: stage
            )
        } catch {
            finish(with: .failure(.writeFailed))
        }
    }

    private func nextRCSPSerialNumber() -> UInt8 {
        defer { rcspSerialNumber &+= 1 }
        return rcspSerialNumber
    }

    private func writeRCSP(_ data: [UInt8], stage: String) throws {
        guard let peripheral, let rcspWriteCharacteristic else {
            throw E01BindError.missingWriteCharacteristic
        }
        let writeType: CBCharacteristicWriteType = rcspWriteCharacteristic.properties.contains(.write)
            ? .withResponse
            : .withoutResponse
        let maximumLength = peripheral.maximumWriteValueLength(for: writeType)
        guard maximumLength > 0 else { throw E01BindError.writeUnsupported }
        let fragments = stride(from: 0, to: data.count, by: maximumLength).map { offset in
            Data(data[offset..<min(offset + maximumLength, data.count)])
        }
        if fragments.count > 1 {
            traceTransfer("gatt_fragments=\(fragments.count) max_write=\(maximumLength) rcsp_bytes=\(data.count)")
        }
        if writeType == .withoutResponse {
            self.stage = stage
            for fragment in fragments {
                peripheral.writeValue(fragment, for: rcspWriteCharacteristic, type: writeType)
            }
            self.stage = stage.replacingOccurrences(of: "writing_", with: "waiting_for_")
            return
        }
        for (index, fragment) in fragments.enumerated() {
            rcspWriteQueue.append(RCSPWriteJob(
                data: fragment,
                stage: stage,
                isFinalFragment: index == fragments.count - 1
            ))
        }
        sendNextQueuedRCSPWrite()
    }

    private func sendNextQueuedRCSPWrite() {
        guard activeRCSPWrite == nil,
              !rcspWriteQueue.isEmpty,
              let peripheral,
              let rcspWriteCharacteristic
        else { return }
        let job = rcspWriteQueue.removeFirst()
        activeRCSPWrite = job
        stage = job.stage
        peripheral.writeValue(job.data, for: rcspWriteCharacteristic, type: .withResponse)
    }

    private func finish(with result: Result<E01BindResult, E01BindError>) {
        guard let continuation else { return }

        centralManager?.stopScan()
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        if let peripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        self.peripheral = nil
        writeCharacteristic = nil
        primaryNotificationCharacteristic = nil
        auxiliaryNotificationCharacteristic = nil
        rcspWriteCharacteristic = nil
        rcspNotificationCharacteristic = nil
        centralManager = nil
        self.continuation = nil

        switch result {
        case let .success(value):
            continuation.resume(returning: value)
        case let .failure(error):
            continuation.resume(throwing: error)
        }
    }

    private static func dataServiceUUID() -> CBUUID {
        CBUUID(string: E01SafetyPolicy.dataServiceUUID)
    }

    private static func advertisedDataServiceAliases() -> [CBUUID] {
        regularDataServiceAliases()
    }

    private static func regularDataServiceAliases() -> [CBUUID] {
        E01SafetyPolicy.regularDataServiceAliases.map(CBUUID.init(string:))
    }

    private static func writeCharacteristicUUID() -> CBUUID {
        CBUUID(string: writeCharacteristicUUIDString)
    }

    private static func primaryNotifyCharacteristicUUID() -> CBUUID {
        CBUUID(string: primaryNotifyCharacteristicUUIDString)
    }

    private static func auxiliaryNotifyCharacteristicUUID() -> CBUUID {
        CBUUID(string: auxiliaryNotifyCharacteristicUUIDString)
    }

    private static func rcspServiceUUID() -> CBUUID {
        CBUUID(string: rcspServiceUUIDString)
    }

    private static func rcspWriteCharacteristicUUID() -> CBUUID {
        CBUUID(string: rcspWriteCharacteristicUUIDString)
    }

    private static func rcspNotifyCharacteristicUUID() -> CBUUID {
        CBUUID(string: rcspNotifyCharacteristicUUIDString)
    }
}
