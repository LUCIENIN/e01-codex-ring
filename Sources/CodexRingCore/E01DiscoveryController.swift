import CoreBluetooth
import Foundation

public struct E01DiscoveredDevice: Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let serviceUUIDs: [String]

    public init(id: UUID, name: String, serviceUUIDs: [String]) {
        self.id = id
        self.name = name
        self.serviceUUIDs = serviceUUIDs
    }
}

public enum E01DiscoveryError: Error, Equatable {
    case invalidTimeout
    case bluetoothUnavailable
    case scanAlreadyRunning
}

public final class E01DiscoveryController: NSObject, CBCentralManagerDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "CodexRing.E01Discovery")
    private var centralManager: CBCentralManager?
    private var continuation: CheckedContinuation<[E01DiscoveredDevice], Error>?
    private var timeoutWorkItem: DispatchWorkItem?
    private var discoveredDevices: [UUID: E01DiscoveredDevice] = [:]

    public static func makeCandidate(
        identifier: UUID,
        name: String?,
        advertisedServiceUUIDs: [CBUUID]
    ) -> E01DiscoveredDevice? {
        let serviceUUIDs = advertisedServiceUUIDs.map { $0.uuidString.uppercased() }
        guard serviceUUIDs.contains(where: E01SafetyPolicy.isRegularDataService) else {
            return nil
        }

        return E01DiscoveredDevice(
            id: identifier,
            name: name?.isEmpty == false ? name! : "unnamed",
            serviceUUIDs: [E01SafetyPolicy.dataServiceUUID]
        )
    }

    public func scan(timeout: TimeInterval) async throws -> [E01DiscoveredDevice] {
        guard (1...30).contains(timeout) else {
            throw E01DiscoveryError.invalidTimeout
        }

        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: E01DiscoveryError.bluetoothUnavailable)
                    return
                }
                guard self.continuation == nil else {
                    continuation.resume(throwing: E01DiscoveryError.scanAlreadyRunning)
                    return
                }

                self.continuation = continuation
                self.discoveredDevices = [:]
                self.centralManager = CBCentralManager(delegate: self, queue: self.queue)
                let workItem = DispatchWorkItem { [weak self] in
                    self?.finish(result: .success(()))
                }
                self.timeoutWorkItem = workItem
                self.queue.asyncAfter(deadline: .now() + timeout, execute: workItem)
            }
        }
    }

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            central.scanForPeripherals(
                withServices: E01SafetyPolicy.regularDataServiceAliases.map(CBUUID.init(string:)),
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
            )
        case .unknown, .resetting:
            break
        default:
            finish(result: .failure(E01DiscoveryError.bluetoothUnavailable))
        }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        guard let candidate = Self.makeCandidate(
            identifier: peripheral.identifier,
            name: peripheral.name ?? advertisedName,
            advertisedServiceUUIDs: serviceUUIDs
        ) else {
            return
        }
        discoveredDevices[candidate.id] = candidate
    }

    private func finish(result: Result<Void, Error>) {
        centralManager?.stopScan()
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        centralManager = nil

        let continuation = continuation
        self.continuation = nil
        switch result {
        case .success:
            continuation?.resume(returning: discoveredDevices.values.sorted { $0.id.uuidString < $1.id.uuidString })
        case let .failure(error):
            continuation?.resume(throwing: error)
        }
    }
}
