import XCTest
@testable import CodexRingCore

final class E01RCSPAuthenticatorTests: XCTestCase {
    func testOfficialTransformerMatchesPublishedJavaScriptImplementation() throws {
        XCTAssertEqual(
            try E01RCSPAuthTransformer().encrypt(Array(0...15)),
            [1, 229, 128, 126, 136, 123, 222, 7, 99, 11, 77, 14, 113, 91, 62, 137, 145]
        )
    }

    func testAuthenticationHandshakeStateMachine() throws {
        var authenticator = E01RCSPAuthenticator()
        XCTAssertEqual(
            try authenticator.start(randomBytes: Array(0...15)),
            [0] + Array(0...15)
        )

        XCTAssertEqual(
            try authenticator.handle([0] + Array(0...15)),
            .send([1, 229, 128, 126, 136, 123, 222, 7, 99, 11, 77, 14, 113, 91, 62, 137, 145])
        )
        XCTAssertEqual(
            try authenticator.handle([1] + Array(repeating: 0, count: 16)),
            .send([2, 112, 97, 115, 115])
        )
        XCTAssertEqual(
            try authenticator.handle([2, 112, 97, 115, 115]),
            .authenticated
        )
    }

    func testRejectsMalformedOrFailedHandshake() throws {
        var authenticator = E01RCSPAuthenticator()
        XCTAssertThrowsError(try authenticator.start(randomBytes: [1]))
        XCTAssertEqual(try authenticator.handle([2, 102, 97, 105, 108]), .failed)
        XCTAssertEqual(try authenticator.handle([7]), .ignored)
    }
}
