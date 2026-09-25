import XCTest

@testable import IslandCore

final class V8ValueTests: XCTestCase {
    func testDecodesScalars() {
        XCTAssertEqual(decode(.str("héllo")), .string("héllo"))
        XCTAssertEqual(decode(.wide("N8n与其他")), .string("N8n与其他"))
        XCTAssertEqual(decode(.utf8("工作流")), .string("工作流"))
        XCTAssertEqual(decode(.int(-3)), .number(-3))
        XCTAssertEqual(decode(.uint(7)), .number(7))
        XCTAssertEqual(decode(.num(1.5)), .number(1.5))
        XCTAssertEqual(decode(.date(1000)), .number(1000))
        XCTAssertEqual(decode(.bool(true)), .bool(true))
        XCTAssertEqual(decode(.bool(false)), .bool(false))
        XCTAssertEqual(decode(.null), .null)
        XCTAssertEqual(decode(.undefined), .null)
        XCTAssertEqual(decode(.ref(0)), .null)
    }

    func testDecodesContainers() throws {
        let value = try XCTUnwrap(
            decode(
                .obj([
                    ("dense", .dense([.int(1), .str("x")])),
                    ("sparse", .sparse([.str("a"), .str("b")])),
                    ("map", .map([(.str("k"), .int(2)), (.int(9), .bool(true))])),
                    ("set", .set([.str("s")])),
                    (nil, .int(4)),
                ])))

        XCTAssertEqual(value["dense"], .array([.number(1), .string("x")]))
        XCTAssertEqual(value["sparse"], .array([.string("a"), .string("b")]))
        XCTAssertEqual(value["map"]?["k"], .number(2))
        XCTAssertEqual(value["map"]?["9"], .bool(true))
        XCTAssertEqual(value["set"], .array([.string("s")]))
        XCTAssertEqual(value["4"], .number(4))
    }

    func testSparseArraysKeepIndexOrder() {
        let bytes: [UInt8] =
            [0x61, 3]  // 'a', length 3
            + V8Fixture.encode(.int(2)) + V8Fixture.encode(.str("c"))
            + V8Fixture.encode(.int(0)) + V8Fixture.encode(.str("a"))
            + [0x40, 2, 3]

        XCTAssertEqual(V8Value.decode(bytes), .array([.string("a"), .string("c")]))
    }

    func testDenseArraysSkipTrailingProperties() {
        let bytes: [UInt8] =
            [0x41, 1] + V8Fixture.encode(.int(1))
            + V8Fixture.encode(.str("extra")) + V8Fixture.encode(.int(2))
            + [0x24, 1, 1]

        XCTAssertEqual(V8Value.decode(bytes), .array([.number(1)]))
    }

    func testSkipsVersionHeadersAndPadding() {
        XCTAssertEqual(
            V8Value.decode([0xFF, 0x0F, 0x00, 0x00] + V8Fixture.encode(.int(5))), .number(5))
    }

    func testRejectsTruncatedOrUnknownInput() {
        XCTAssertNil(V8Value.decode([]))
        XCTAssertNil(V8Value.decode([0x7E]))  // unknown tag
        XCTAssertNil(V8Value.decode([0x22, 5, 0x61]))  // string runs past the end
        XCTAssertNil(V8Value.decode([0x4E, 0x00]))  // double runs past the end
        XCTAssertNil(V8Value.decode([0x6F, 0x22, 1, 0x61]))  // object never closed
        XCTAssertNil(V8Value.decode([0x41, 2, 0x5F]))  // dense array too short
        XCTAssertNil(V8Value.decode([0x49]))  // int missing its varint
        XCTAssertNil(V8Value.decode([0x63, 1, 0x61]))  // odd-length two-byte string
    }

    /// A cache file can be read mid-write; every truncation of a valid value
    /// must be rejected rather than half-decoded.
    func testEveryTruncationIsRejected() {
        let whole = V8Fixture.encode(
            .obj([
                ("dense", .dense([.int(1)])),
                ("sparse", .sparse([.str("a")])),
                ("map", .map([(.str("k"), .num(2))])),
                ("set", .set([.wide("s")])),
                ("text", .utf8("x")),
                ("n", .uint(300)),
            ]))
        XCTAssertNotNil(V8Value.decode(whole))

        for length in 0..<whole.count {
            XCTAssertNil(V8Value.decode(Array(whole.prefix(length))), "prefix \(length)")
        }
    }

    func testRejectsKeysThatAreNotStringsOrNumbers() {
        XCTAssertNil(V8Value.decode([0x6F, 0x54, 0x30, 0x7B, 1]))  // {true: null}
    }

    func testRejectsRunawayNesting() {
        let bytes = [UInt8](repeating: 0x6F, count: 10_000)  // 'o' 'o' 'o' ...

        XCTAssertNil(V8Value.decode(bytes))
    }

    func testAccessors() {
        let object = V8Value.object(["a": .string("x"), "n": .number(2)])

        XCTAssertEqual(object["a"]?.string, "x")
        XCTAssertNil(object["n"]?.string)
        XCTAssertEqual(object["n"]?.number, 2)
        XCTAssertNil(object["a"]?.number)
        XCTAssertNil(object["missing"])
        XCTAssertNil(V8Value.string("x")["a"])
        XCTAssertEqual(V8Value.array([.null]).elements, [.null])
        XCTAssertEqual(object.elements, [])
    }

    private func decode(_ node: V8Fixture.Node) -> V8Value? {
        V8Value.decode(V8Fixture.encode(node))
    }
}

/// Test-only V8 serializer covering the tags island reads, so fixtures carry no
/// real conversations.
enum V8Fixture {
    indirect enum Node {
        case obj([(String?, Node)])
        case dense([Node])
        case sparse([Node])
        case map([(Node, Node)])
        case set([Node])
        case str(String)
        case wide(String)
        case utf8(String)
        case int(Int)
        case uint(Int)
        case num(Double)
        case date(Double)
        case bool(Bool)
        case null
        case undefined
        case ref(Int)
    }

    static func varint(_ value: Int) -> [UInt8] {
        var value = UInt64(value)
        var out: [UInt8] = []
        repeat {
            var byte = UInt8(value & 0x7F)
            value >>= 7
            if value != 0 { byte |= 0x80 }
            out.append(byte)
        } while value != 0
        return out
    }

    static func double(_ value: Double) -> [UInt8] {
        withUnsafeBytes(of: value.bitPattern.littleEndian) { Array($0) }
    }

    static func encode(_ node: Node) -> [UInt8] {
        switch node {
        case .obj(let pairs):
            // A nil key stands for the numeric key 4, to exercise non-string keys.
            return [0x6F]
                + pairs.flatMap { key, value in
                    (key.map { encode(.str($0)) } ?? encode(.int(4))) + encode(value)
                } + [0x7B] + varint(pairs.count)
        case .dense(let items):
            return [0x41] + varint(items.count) + items.flatMap(encode) + [0x24, 0]
                + varint(items.count)
        case .sparse(let items):
            return [0x61] + varint(items.count)
                + items.enumerated().flatMap { encode(.int($0.offset)) + encode($0.element) }
                + [0x40] + varint(items.count) + varint(items.count)
        case .map(let pairs):
            return [0x3B] + pairs.flatMap { encode($0.0) + encode($0.1) } + [0x3A]
                + varint(pairs.count * 2)
        case .set(let items):
            return [0x27] + items.flatMap(encode) + [0x2C] + varint(items.count)
        case .str(let text):
            let bytes = Array(text.data(using: .isoLatin1)!)
            return [0x22] + varint(bytes.count) + bytes
        case .wide(let text):
            let bytes = Array(text.data(using: .utf16LittleEndian)!)
            return [0x63] + varint(bytes.count) + bytes
        case .utf8(let text):
            let bytes = Array(text.utf8)
            return [0x53] + varint(bytes.count) + bytes
        case .int(let value):
            return [0x49] + varint((value << 1) ^ (value >> 63))
        case .uint(let value):
            return [0x55] + varint(value)
        case .num(let value):
            return [0x4E] + double(value)
        case .date(let value):
            return [0x44] + double(value)
        case .bool(let value):
            return [value ? 0x54 : 0x46]
        case .null:
            return [0x30]
        case .undefined:
            return [0x5F]
        case .ref(let id):
            return [0x5E] + varint(id)
        }
    }

    /// A snappy stream made only of literals, which every decoder must accept.
    static func snappyLiterals(_ bytes: [UInt8]) -> [UInt8] {
        var out = varint(bytes.count)
        var index = 0
        while index < bytes.count {
            let chunk = Array(bytes[index..<min(index + 60, bytes.count)])
            out += [UInt8((chunk.count - 1) << 2)] + chunk
            index += chunk.count
        }
        return out
    }

    /// What Chromium writes to an IndexedDB blob file: Blink's "compressed"
    /// wrapper, then the Blink envelope, then the V8 value.
    static func blob(_ root: Node) -> Data {
        let envelope: [UInt8] = [0xFF, 0x15, 0xFE, 0x00, 0x1D, 0x01, 0xF0, 0x52, 0xFF, 0x10]
        return Data([0xFF, 0x11, 0x02] + snappyLiterals(envelope + encode(root)))
    }
}
