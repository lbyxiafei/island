import Foundation

/// Raw (unframed) snappy decompression — what Chromium applies to large
/// IndexedDB values. Island has no third-party dependencies, and reading is all
/// it needs. Malformed input yields nil, never a crash.
enum Snappy {
    static func decompress(_ input: [UInt8]) -> [UInt8]? {
        var reader = ByteReader(input)
        guard let expected = reader.varint() else { return nil }
        var output: [UInt8] = []
        output.reserveCapacity(expected)
        while !reader.isAtEnd {
            guard let tag = reader.byte() else { return nil }
            switch tag & 0x03 {
            case 0:
                var length = Int(tag >> 2)
                if length >= 60 {
                    guard let extra = reader.littleEndian(byteCount: length - 59) else {
                        return nil
                    }
                    length = extra
                }
                guard let literal = reader.bytes(length + 1) else { return nil }
                output += literal
            case 1:
                guard let low = reader.byte() else { return nil }
                let length = Int((tag >> 2) & 0x07) + 4
                let offset = Int(tag >> 5) << 8 | Int(low)
                guard copy(length: length, offset: offset, into: &output) else { return nil }
            default:
                let length = Int(tag >> 2) + 1
                guard let offset = reader.littleEndian(byteCount: tag & 0x03 == 2 ? 2 : 4),
                    copy(length: length, offset: offset, into: &output)
                else { return nil }
            }
        }
        return output.count == expected ? output : nil
    }

    /// Back-references may overlap what they produce ("a" + copy(5, 1) is
    /// "aaaaaa"), so copy one byte at a time.
    private static func copy(length: Int, offset: Int, into output: inout [UInt8]) -> Bool {
        guard offset > 0, offset <= output.count else { return false }
        let start = output.count - offset
        for index in 0..<length { output.append(output[start + index]) }
        return true
    }
}

/// Forward-only reader over a byte buffer; every read fails softly at the end.
struct ByteReader {
    private let bytes: [UInt8]
    private(set) var position = 0

    init(_ bytes: [UInt8], position: Int = 0) {
        self.bytes = bytes
        self.position = position
    }

    var isAtEnd: Bool { position >= bytes.count }

    func peek() -> UInt8? { isAtEnd ? nil : bytes[position] }

    mutating func byte() -> UInt8? {
        guard let value = peek() else { return nil }
        position += 1
        return value
    }

    mutating func bytes(_ count: Int) -> [UInt8]? {
        guard count >= 0, count <= bytes.count - position else { return nil }
        defer { position += count }
        return Array(bytes[position..<position + count])
    }

    /// Base-128 little-endian varint, as used by both snappy and V8.
    mutating func varint() -> Int? {
        var result = 0
        var shift = 0
        while shift < 64 {
            guard let byte = byte() else { return nil }
            result |= Int(byte & 0x7F) << shift
            if byte < 0x80 { return result }
            shift += 7
        }
        return nil
    }

    mutating func littleEndian(byteCount: Int) -> Int? {
        guard let raw = bytes(byteCount) else { return nil }
        return raw.reversed().reduce(0) { $0 << 8 | Int($1) }
    }
}
