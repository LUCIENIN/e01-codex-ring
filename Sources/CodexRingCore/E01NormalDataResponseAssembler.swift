import Foundation

/// Reassembles the vendor's normal-data frames when CoreBluetooth delivers a
/// header-bearing first notification followed by raw continuation fragments.
public struct E01NormalDataResponseAssembler: Sendable {
    private var buffer: [UInt8] = []
    private var expectedLength: Int?

    public init() {}

    public mutating func append(_ fragment: [UInt8]) -> [UInt8]? {
        guard !fragment.isEmpty else { return nil }

        if fragment[0] == 0x9E {
            reset()
            guard fragment.count >= 6 else { return nil }

            let payloadLength = Int(fragment[4]) | (Int(fragment[5]) << 8)
            expectedLength = payloadLength + 6
            buffer = fragment
        } else {
            guard expectedLength != nil else { return nil }
            buffer.append(contentsOf: fragment)
        }

        guard let expectedLength, buffer.count >= expectedLength else {
            return nil
        }

        let candidate = buffer
        reset()

        guard candidate.count == expectedLength else { return nil }
        let checksum = candidate.dropFirst(2).reduce(UInt8(0), &+)
        guard checksum == candidate[1] else { return nil }

        return candidate
    }

    private mutating func reset() {
        buffer.removeAll(keepingCapacity: true)
        expectedLength = nil
    }
}
