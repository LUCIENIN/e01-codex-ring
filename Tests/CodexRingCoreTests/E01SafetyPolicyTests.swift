import XCTest
@testable import CodexRingCore

final class E01SafetyPolicyTests: XCTestCase {
    func testRCSPServiceAllowsOnlyItsWriteAndNotifyCharacteristics() {
        XCTAssertTrue(E01SafetyPolicy.canUseRCSP(serviceUUID: "AE00", characteristicUUID: "AE01"))
        XCTAssertTrue(E01SafetyPolicy.canUseRCSP(
            serviceUUID: E01SafetyPolicy.rcspServiceUUID,
            characteristicUUID: E01SafetyPolicy.rcspNotifyCharacteristicUUID
        ))
        XCTAssertFalse(E01SafetyPolicy.canUseRCSP(serviceUUID: "AE00", characteristicUUID: "AE03"))
    }

    func testRegularDataServiceAllowsOnlyKnownDataCharacteristics() {
        XCTAssertTrue(E01SafetyPolicy.canUse(
            serviceUUID: E01SafetyPolicy.dataServiceUUID.lowercased(),
            characteristicUUID: "c2e6fd01-e966-1000-8000-bef9c223df6a"
        ))
        XCTAssertFalse(E01SafetyPolicy.canUse(
            serviceUUID: E01SafetyPolicy.dataServiceUUID,
            characteristicUUID: "C2E6FD04-E966-1000-8000-BEF9C223DF6A"
        ))
    }

    func testRegularServiceDiscoveryAcceptsOnlyTheTwoKnownDataAliases() {
        XCTAssertTrue(E01SafetyPolicy.isRegularDataService(E01SafetyPolicy.dataServiceUUID))
        XCTAssertTrue(E01SafetyPolicy.isRegularDataService("FD00"))
        XCTAssertFalse(E01SafetyPolicy.isRegularDataService("AE00"))
    }

    func testMediaCannotBeSentBeforeReadyAndExplicitApproval() {
        XCTAssertFalse(MediaUploadGate(phase: .unbound, userApprovedLiveSend: true).canSendMedia)
        XCTAssertFalse(MediaUploadGate(phase: .ready, userApprovedLiveSend: false).canSendMedia)
        XCTAssertTrue(MediaUploadGate(phase: .ready, userApprovedLiveSend: true).canSendMedia)
    }
}
