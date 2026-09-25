import Foundation

/// A JavaScript value read back from V8's structured-clone format — the way
/// Chromium stores IndexedDB values. Only the shapes island needs survive:
/// arrays, sets and sparse arrays become `.array`; objects and maps become
/// `.object` with string keys; dates become `.number` (ms since 1970).
public indirect enum V8Value: Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([V8Value])
    case object([String: V8Value])

    public subscript(key: String) -> V8Value? {
        guard case .object(let fields) = self else { return nil }
        return fields[key]
    }

    public var string: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    public var number: Double? {
        guard case .number(let value) = self else { return nil }
        return value
    }

    /// The items of an array; empty for anything else, so lookups chain.
    public var elements: [V8Value] {
        guard case .array(let items) = self else { return [] }
        return items
    }

    /// Decodes one value; leading version headers and padding are skipped.
    /// Anything malformed or unsupported yields nil.
    public static func decode(_ bytes: [UInt8]) -> V8Value? {
        var decoder = V8Decoder(reader: ByteReader(bytes))
        return decoder.value(depth: 0)
    }
}

private struct V8Decoder {
    var reader: ByteReader

    /// Real caches nest a few dozen levels; far deeper means garbage.
    private static let maxDepth = 256

    private enum Tag {
        static let padding: UInt8 = 0x00
        static let version: UInt8 = 0xFF
        static let beginObject = UInt8(ascii: "o")
        static let endObject = UInt8(ascii: "{")
        static let beginDenseArray = UInt8(ascii: "A")
        static let endDenseArray = UInt8(ascii: "$")
        static let beginSparseArray = UInt8(ascii: "a")
        static let endSparseArray = UInt8(ascii: "@")
        static let beginMap = UInt8(ascii: ";")
        static let endMap = UInt8(ascii: ":")
        static let beginSet = UInt8(ascii: "'")
        static let endSet = UInt8(ascii: ",")
    }

    mutating func value(depth: Int) -> V8Value? {
        guard depth < Self.maxDepth else { return nil }
        guard let tag = nextTag() else { return nil }
        switch tag {
        case Tag.beginObject:
            guard let fields = keyedEntries(until: Tag.endObject, depth: depth),
                reader.varint() != nil
            else { return nil }
            return .object(fields.reduce(into: [:]) { $0[$1.0] = $1.1 })
        case Tag.beginMap:
            guard let fields = keyedEntries(until: Tag.endMap, depth: depth),
                reader.varint() != nil
            else { return nil }
            return .object(fields.reduce(into: [:]) { $0[$1.0] = $1.1 })
        case Tag.beginDenseArray:
            guard let count = reader.varint() else { return nil }
            var items: [V8Value] = []
            for _ in 0..<count {
                guard let item = value(depth: depth + 1) else { return nil }
                items.append(item)
            }
            // Extra named properties on the array carry nothing island needs.
            guard keyedEntries(until: Tag.endDenseArray, depth: depth) != nil,
                reader.varint() != nil, reader.varint() != nil
            else { return nil }
            return .array(items)
        case Tag.beginSparseArray:
            guard reader.varint() != nil,
                let entries = keyedEntries(until: Tag.endSparseArray, depth: depth),
                reader.varint() != nil, reader.varint() != nil
            else { return nil }
            let indexed = entries.compactMap { key, item in Int(key).map { ($0, item) } }
            return .array(indexed.sorted { $0.0 < $1.0 }.map(\.1))
        case Tag.beginSet:
            var items: [V8Value] = []
            while reader.peek() != Tag.endSet {
                guard let item = value(depth: depth + 1) else { return nil }
                items.append(item)
            }
            _ = reader.byte()
            guard reader.varint() != nil else { return nil }
            return .array(items)
        default:
            return scalar(tag)
        }
    }

    private mutating func scalar(_ tag: UInt8) -> V8Value? {
        switch tag {
        case UInt8(ascii: "\""):
            return lengthPrefixed().flatMap { String(bytes: $0, encoding: .isoLatin1) }.map(
                V8Value.string)
        case UInt8(ascii: "c"):
            guard let raw = lengthPrefixed(), raw.count % 2 == 0 else { return nil }
            return String(bytes: raw, encoding: .utf16LittleEndian).map(V8Value.string)
        case UInt8(ascii: "S"):
            return lengthPrefixed().map { .string(String(decoding: $0, as: UTF8.self)) }
        case UInt8(ascii: "I"):
            guard let zigzag = reader.varint() else { return nil }
            return .number(Double((zigzag >> 1) ^ -(zigzag & 1)))
        case UInt8(ascii: "U"):
            return reader.varint().map { .number(Double($0)) }
        case UInt8(ascii: "N"), UInt8(ascii: "D"):
            guard let raw = reader.littleEndian(byteCount: 8) else { return nil }
            return .number(Double(bitPattern: UInt64(bitPattern: Int64(raw))))
        case UInt8(ascii: "T"):
            return .bool(true)
        case UInt8(ascii: "F"):
            return .bool(false)
        case UInt8(ascii: "_"), UInt8(ascii: "0"):
            return .null
        case UInt8(ascii: "^"):
            // A back-reference to an object already read; island never needs one.
            return reader.varint().map { _ in .null }
        default:
            return nil
        }
    }

    /// The next tag, past padding and version headers.
    private mutating func nextTag() -> UInt8? {
        while let tag = reader.byte() {
            switch tag {
            case Tag.padding:
                continue
            case Tag.version:
                guard reader.varint() != nil else { return nil }
            default:
                return tag
            }
        }
        return nil
    }

    /// Key/value pairs up to `end` (consumed). Keys must be strings or numbers.
    private mutating func keyedEntries(until end: UInt8, depth: Int) -> [(String, V8Value)]? {
        var entries: [(String, V8Value)] = []
        while let next = reader.peek() {
            if next == end {
                _ = reader.byte()
                return entries
            }
            guard let key = value(depth: depth + 1).flatMap(Self.keyText),
                let item = value(depth: depth + 1)
            else { return nil }
            entries.append((key, item))
        }
        return nil
    }

    private static func keyText(_ key: V8Value) -> String? {
        switch key {
        case .string(let text): return text
        case .number(let number) where number == number.rounded(): return String(Int(number))
        case .number(let number): return String(number)
        default: return nil
        }
    }

    private mutating func lengthPrefixed() -> [UInt8]? {
        guard let count = reader.varint() else { return nil }
        return reader.bytes(count)
    }
}
