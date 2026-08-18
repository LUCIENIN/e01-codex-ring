import CoreBluetooth
import XCTest
@testable import CodexRingCore

final class E01DiscoveryControllerTests: XCTestCase {
    func testDiscoveryCandidateRequiresRegularDataService() {
        let candidate = E01DiscoveryController.makeCandidate(
            identifier: UUID(),
            name: "E01",
            advertisedServiceUUIDs: [CBUUID(string: E01SafetyPolicy.dataServiceUUID)]
        )

        XCTAssertNotNil(candidate)
        XCTAssertEqual(candidate?.name, "E01")
        XCTAssertEqual(candidate?.serviceUUIDs, [E01SafetyPolicy.dataServiceUUID])
    }

    func testOtaOnlyAdvertisementIsNotAValidCandidate() {
        let candidate = E01DiscoveryController.makeCandidate(
            identifier: UUID(),
            name: "E01",
            advertisedServiceUUIDs: [CBUUID(string: "AE00")]
        )

        XCTAssertNil(candidate)
    }

    func testFD00AdvertisementIsRecognizedAsRegularDataService() {
        let candidate = E01DiscoveryController.makeCandidate(
            identifier: UUID(),
            name: "E01",
            advertisedServiceUUIDs: [CBUUID(string: "FD00")]
        )

        XCTAssertNotNil(candidate)
        XCTAssertEqual(candidate?.serviceUUIDs, [E01SafetyPolicy.dataServiceUUID])
    }
}
