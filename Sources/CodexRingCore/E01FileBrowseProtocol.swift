import Foundation

public struct E01FileBrowseEntry: Equatable, Sendable {
    public let isFile: Bool
    public let deviceIndex: UInt8
    public let cluster: UInt32
    public let fileNumber: UInt16
    public let name: String

    public init(
        isFile: Bool,
        deviceIndex: UInt8,
        cluster: UInt32,
        fileNumber: UInt16 = 1,
        name: String
    ) {
        self.isFile = isFile
        self.deviceIndex = deviceIndex
        self.cluster = cluster
        self.fileNumber = fileNumber
        self.name = name
    }
}

public enum E01FileBrowseError: Error, Equatable, Sendable {
    case truncatedEntry
    case invalidName
}

public enum E01FileBrowseProtocol {
    public static func rootBrowseParameter(deviceHandler: UInt32) -> [UInt8] {
        browseParameter(deviceHandler: deviceHandler, pathClusters: [0])
    }

    public static func browseParameter(
        deviceHandler: UInt32,
        pathClusters: [UInt32],
        offset: UInt16 = 1,
        readCount: UInt8 = 10
    ) -> [UInt8] {
        let clusters = pathClusters.isEmpty ? [UInt32(0)] : pathClusters
        let pathBytes = clusters.flatMap(uint32BE)
        return [
            0x00,
            readCount,
            UInt8(truncatingIfNeeded: offset >> 8),
            UInt8(truncatingIfNeeded: offset),
        ]
            + uint32BE(deviceHandler)
            + [UInt8(truncatingIfNeeded: pathBytes.count >> 8), UInt8(truncatingIfNeeded: pathBytes.count)]
            + pathBytes
    }

    public static func parseEntries(_ bytes: [UInt8]) throws -> [E01FileBrowseEntry] {
        var entries: [E01FileBrowseEntry] = []
        var offset = 0
        while offset < bytes.count {
            guard bytes.count - offset >= 8 else {
                throw E01FileBrowseError.truncatedEntry
            }
            let flags = bytes[offset]
            let nameLength = Int(bytes[offset + 7])
            let entryEnd = offset + 8 + nameLength
            guard entryEnd <= bytes.count else {
                throw E01FileBrowseError.truncatedEntry
            }
            let nameBytes = Array(bytes[(offset + 8)..<entryEnd])
            let isUnicode = flags & 0x02 == 0
            let name: String?
            if isUnicode {
                name = String(data: Data(nameBytes), encoding: .utf16LittleEndian)
            } else {
                name = String(bytes: nameBytes, encoding: .utf8)
                    ?? String(bytes: nameBytes, encoding: .isoLatin1)
            }
            guard let name else {
                throw E01FileBrowseError.invalidName
            }
            entries.append(E01FileBrowseEntry(
                isFile: flags & 0x01 != 0,
                deviceIndex: (flags & 0x7C) >> 2,
                cluster: readUInt32BE(bytes, at: offset + 1),
                fileNumber: readUInt16BE(bytes, at: offset + 5),
                name: name
            ))
            offset = entryEnd
        }
        return entries
    }

    public static func clusterDeleteParameter(
        deviceHandler: UInt32,
        entryType: UInt8,
        cluster: UInt32,
        isLast: Bool
    ) -> [UInt8] {
        [isLast ? 0x01 : 0x00]
            + uint32BE(deviceHandler)
            + [entryType]
            + uint32BE(cluster)
    }

    public static func clusterDeletionParameters(
        deviceHandler: UInt32,
        entries: [E01FileBrowseEntry]
    ) -> [[UInt8]] {
        Array(entries.reversed()).enumerated().map { index, entry in
            clusterDeleteParameter(
                deviceHandler: deviceHandler,
                entryType: entry.isFile ? 1 : 0,
                cluster: entry.cluster,
                isLast: index == entries.count - 1
            )
        }
    }

    private static func uint32BE(_ value: UInt32) -> [UInt8] {
        [
            UInt8(truncatingIfNeeded: value >> 24),
            UInt8(truncatingIfNeeded: value >> 16),
            UInt8(truncatingIfNeeded: value >> 8),
            UInt8(truncatingIfNeeded: value),
        ]
    }

    private static func readUInt32BE(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        (UInt32(bytes[offset]) << 24)
            | (UInt32(bytes[offset + 1]) << 16)
            | (UInt32(bytes[offset + 2]) << 8)
            | UInt32(bytes[offset + 3])
    }

    private static func readUInt16BE(_ bytes: [UInt8], at offset: Int) -> UInt16 {
        (UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1])
    }
}

public enum E01ManagedMediaPolicy {
    public static func isManagedFileName(_ fileName: String) -> Bool {
        guard (fileName as NSString).lastPathComponent == fileName,
              ["avi", "jpg"].contains((fileName as NSString).pathExtension.lowercased())
        else {
            return false
        }
        let stem = (fileName as NSString).deletingPathExtension.lowercased()
        for prefix in ["codex_push", "badge", "codexa", "codexb"] where stem.hasPrefix(prefix) {
            return stem.dropFirst(prefix.count).allSatisfy(\.isNumber)
        }
        return false
    }

    public static func filesToDeleteBeforeUpload(
        _ entries: [E01FileBrowseEntry],
        activeFileName: String?,
        destinationFileName: String
    ) -> [E01FileBrowseEntry] {
        let managedFiles = entries.filter { $0.isFile && isManagedFileName($0.name) }
        let activeName = activeFileName?.lowercased()
        let destinationName = destinationFileName.lowercased()

        if let activeName,
           let active = managedFiles.first(where: { $0.name.lowercased() == activeName }) {
            return managedFiles.filter { $0.cluster != active.cluster }
        }

        if managedFiles.count == 1,
           managedFiles[0].name.lowercased() != destinationName {
            return []
        }

        let survivor = managedFiles
            .filter { $0.name.lowercased() != destinationName }
            .max { $0.cluster < $1.cluster }
        return managedFiles.filter { $0.cluster != survivor?.cluster }
    }

    public static func filesToDeleteAfterUpload(
        _ entries: [E01FileBrowseEntry],
        committedFileName: String
    ) -> [E01FileBrowseEntry] {
        let committedName = committedFileName.lowercased()
        return entries.filter {
            $0.isFile
                && isManagedFileName($0.name)
                && $0.name.lowercased() != committedName
        }
    }
}
