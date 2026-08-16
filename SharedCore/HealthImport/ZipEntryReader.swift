import Foundation
import Compression

/// Minimal ZIP reader for one very specific job: extracting `export.xml` from
/// an Apple Health `export.zip`. Supports stored and deflate entries via
/// libcompression. No third-party dependencies.
enum ZipEntryReader {
    enum ZipError: LocalizedError, Equatable {
        case endOfCentralDirectoryNotFound
        case centralDirectoryTruncated
        case entryNotFound(String)
        case unsupportedCompressionMethod(UInt16)
        case decompressionFailed
        case corruptEntry(String)

        var errorDescription: String? {
            switch self {
            case .endOfCentralDirectoryNotFound:
                return "This doesn't look like a valid .zip archive."
            case .centralDirectoryTruncated:
                return "The zip archive is truncated or corrupt."
            case .entryNotFound(let name):
                return "Could not find \(name) inside the archive. Expected an Apple Health export."
            case .unsupportedCompressionMethod(let method):
                return "Unsupported zip compression method \(method)."
            case .decompressionFailed:
                return "Could not decompress the archive entry."
            case .corruptEntry(let detail):
                return "Corrupt zip entry: \(detail)"
            }
        }
    }

    private static let endOfCentralDirectorySignature: [UInt8] = [0x50, 0x4B, 0x05, 0x06]
    private static let centralDirectorySignature: [UInt8] = [0x50, 0x4B, 0x01, 0x02]
    private static let localFileSignature: [UInt8] = [0x50, 0x4B, 0x03, 0x04]

    /// Extracts `name` (case-insensitive, top-level or nested) and returns its
    /// decompressed bytes.
    static func extractEntry(named name: String, from data: Data) throws -> Data {
        let bytes = [UInt8](data)
        let eocd = try findEndOfCentralDirectory(in: bytes)

        let entryCount = readUInt16(bytes, at: eocd + 10)
        var offset = Int(readUInt32(bytes, at: eocd + 16))

        for _ in 0..<max(entryCount, 1) {
            guard offset + 46 <= bytes.count else { throw ZipError.centralDirectoryTruncated }
            guard matches(bytes, at: offset, signature: centralDirectorySignature) else { break }

            let method = readUInt16(bytes, at: offset + 10)
            let compressedSize = Int(readUInt32(bytes, at: offset + 20))
            let uncompressedSize = Int(readUInt32(bytes, at: offset + 24))
            let nameLength = Int(readUInt16(bytes, at: offset + 28))
            let extraLength = Int(readUInt16(bytes, at: offset + 30))
            let commentLength = Int(readUInt16(bytes, at: offset + 32))
            let localHeaderOffset = Int(readUInt32(bytes, at: offset + 42))

            let nameStart = offset + 46
            guard nameStart + nameLength <= bytes.count else { throw ZipError.centralDirectoryTruncated }
            let entryName = String(decoding: bytes[nameStart..<(nameStart + nameLength)], as: UTF8.self)

            if entryName.lowercased().hasSuffix("/" + name.lowercased())
                || entryName.lowercased() == name.lowercased() {
                let payload = try readLocalEntry(
                    in: bytes,
                    at: localHeaderOffset,
                    compressedSize: compressedSize,
                    uncompressedSize: uncompressedSize,
                    method: method
                )
                return payload
            }

            offset = nameStart + nameLength + extraLength + commentLength
        }
        throw ZipError.entryNotFound(name)
    }

    // MARK: - Internals

    private static func findEndOfCentralDirectory(in bytes: [UInt8]) throws -> Int {
        guard bytes.count > 22 else { throw ZipError.endOfCentralDirectoryNotFound }
        let searchFloor = max(0, bytes.count - 65_557)
        var index = bytes.count - 22
        while index >= searchFloor {
            if matches(bytes, at: index, signature: endOfCentralDirectorySignature) {
                return index
            }
            index -= 1
        }
        throw ZipError.endOfCentralDirectoryNotFound
    }

    private static func readLocalEntry(
        in bytes: [UInt8],
        at localHeaderOffset: Int,
        compressedSize: Int,
        uncompressedSize: Int,
        method: UInt16
    ) throws -> Data {
        guard localHeaderOffset + 30 <= bytes.count,
              matches(bytes, at: localHeaderOffset, signature: localFileSignature) else {
            throw ZipError.corruptEntry("bad local header")
        }
        let nameLength = Int(readUInt16(bytes, at: localHeaderOffset + 26))
        let extraLength = Int(readUInt16(bytes, at: localHeaderOffset + 28))
        let dataStart = localHeaderOffset + 30 + nameLength + extraLength
        guard dataStart + compressedSize <= bytes.count else {
            throw ZipError.corruptEntry("payload out of bounds")
        }

        let compressed = Data(bytes[dataStart..<(dataStart + compressedSize)])
        switch method {
        case 0:
            return compressed
        case 8:
            return try inflate(compressed, uncompressedSize: uncompressedSize)
        default:
            throw ZipError.unsupportedCompressionMethod(method)
        }
    }

    /// Deflate via libcompression. Apple's COMPRESSION_ZLIB is raw DEFLATE —
    /// exactly what zip entries use (no zlib container).
    private static func inflate(_ data: Data, uncompressedSize: Int) throws -> Data {
        guard uncompressedSize > 0 else { return Data() }
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: uncompressedSize)
        defer { destination.deallocate() }

        var decoded = 0
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let source = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            decoded = compression_decode_buffer(
                destination,
                uncompressedSize,
                source,
                raw.count,
                nil,
                COMPRESSION_ZLIB
            )
        }
        guard decoded > 0 else { throw ZipError.decompressionFailed }
        return Data(bytes: destination, count: decoded)
    }

    private static func matches(_ bytes: [UInt8], at index: Int, signature: [UInt8]) -> Bool {
        guard index + signature.count <= bytes.count else { return false }
        for (offset, byte) in signature.enumerated() where bytes[index + offset] != byte {
            return false
        }
        return true
    }

    private static func readUInt16(_ bytes: [UInt8], at index: Int) -> UInt16 {
        UInt16(bytes[index]) | (UInt16(bytes[index + 1]) << 8)
    }

    private static func readUInt32(_ bytes: [UInt8], at index: Int) -> UInt32 {
        UInt32(bytes[index])
            | (UInt32(bytes[index + 1]) << 8)
            | (UInt32(bytes[index + 2]) << 16)
            | (UInt32(bytes[index + 3]) << 24)
    }
}
