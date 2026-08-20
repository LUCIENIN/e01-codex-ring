import Foundation
import JavaScriptCore

public enum E01RCSPAuthError: Error, Equatable, Sendable {
    case invalidRandomLength
    case invalidChallengeLength
    case resourceUnavailable
    case scriptFailed
    case invalidEncryptedResponse
}

/// Executes the authentication transform published in Jieli's Apache-2.0
/// WeChat-Mini-Program-OTA repository. JavaScriptCore keeps the vendor algorithm
/// byte-for-byte identical while allowing the BLE transport to remain native macOS Swift.
public struct E01RCSPAuthTransformer: Sendable {
    public init() {}

    public func encrypt(_ challenge: [UInt8]) throws -> [UInt8] {
        guard challenge.count == 16 else {
            throw E01RCSPAuthError.invalidChallengeLength
        }
        let resourceURL = Bundle.main.url(
            forResource: "jl_auth_2.0.0",
            withExtension: "js"
        ) ?? Bundle.module.url(
            forResource: "jl_auth_2.0.0",
            withExtension: "js"
        )
        guard let resourceURL,
              let source = try? String(contentsOf: resourceURL, encoding: .utf8) else {
            throw E01RCSPAuthError.resourceUnavailable
        }
        guard let context = JSContext() else {
            throw E01RCSPAuthError.scriptFailed
        }
        var scriptException: JSValue?
        context.exceptionHandler = { _, exception in
            scriptException = exception
        }
        context.evaluateScript("var exports = {};\n" + source + "\nglobalThis.__jlEncrypt = f;")
        guard scriptException == nil,
              let function = context.objectForKeyedSubscript("__jlEncrypt"),
              !function.isUndefined,
              let value = function.call(withArguments: [challenge]),
              scriptException == nil,
              let numbers = value.toArray() as? [NSNumber]
        else {
            throw E01RCSPAuthError.scriptFailed
        }
        let bytes = numbers.map(\.uint8Value)
        guard bytes.count == 17, bytes.first == 1 else {
            throw E01RCSPAuthError.invalidEncryptedResponse
        }
        return bytes
    }
}

public struct E01RCSPAuthenticator: Sendable {
    public enum Action: Equatable, Sendable {
        case send([UInt8])
        case authenticated
        case failed
        case ignored
    }

    private static let pass: [UInt8] = [2, 112, 97, 115, 115]
    private let transformer: E01RCSPAuthTransformer

    public init(transformer: E01RCSPAuthTransformer = E01RCSPAuthTransformer()) {
        self.transformer = transformer
    }

    public mutating func start(randomBytes: [UInt8]) throws -> [UInt8] {
        guard randomBytes.count == 16 else {
            throw E01RCSPAuthError.invalidRandomLength
        }
        return [0] + randomBytes
    }

    public mutating func handle(_ bytes: [UInt8]) throws -> Action {
        guard let type = bytes.first else { return .ignored }
        switch (type, bytes.count) {
        case (0, 17):
            return .send(try transformer.encrypt(Array(bytes.dropFirst())))
        case (1, 17):
            return .send(Self.pass)
        case (2, 5):
            return bytes == Self.pass ? .authenticated : .failed
        default:
            return .ignored
        }
    }
}
