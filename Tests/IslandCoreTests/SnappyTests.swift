import XCTest

@testable import IslandCore

final class SnappyTests: XCTestCase {
    func testDecodesShortAndLongLiterals() {
        let long = [UInt8](repeating: 0x61, count: 70)
        // Preamble 72, literal "hi" (tag 1<<2), literal of 70 bytes (tag 60<<2, 1 length byte 69).
        let stream: [UInt8] = [72, 0x04, 0x68, 0x69, 0xF0, 69] + long

        XCTAssertEqual(Snappy.decompress(stream), [0x68, 0x69] + long)
    }

    func testDecodesAllThreeCopyKinds() {
        // "abcd", then copy-1 (len 4, off 4), copy-2 (len 2, off 8), copy-4 (len 1, off 1).
        let stream: [UInt8] = [
            11, 0x0C, 0x61, 0x62, 0x63, 0x64,
            0x01, 0x04,
            0x06, 0x08, 0x00,
            0x03, 0x01, 0x00, 0x00, 0x00,
        ]

        XCTAssertEqual(
            Snappy.decompress(stream).map { String(decoding: $0, as: UTF8.self) }, "abcdabcdabb")
    }

    func testAnOverlappingCopyRepeatsTheRun() {
        // "a" then copy-1 of length 5 at offset 1 -> "aaaaaa".
        XCTAssertEqual(
            Snappy.decompress([6, 0x00, 0x61, 0x05, 0x01]), [UInt8](repeating: 0x61, count: 6))
    }

    func testRejectsMalformedStreams() {
        XCTAssertNil(Snappy.decompress([]))
        XCTAssertNil(Snappy.decompress([0x80]))  // unterminated preamble
        XCTAssertNil(Snappy.decompress([3, 0x08, 0x61]))  // literal runs past the end
        XCTAssertNil(Snappy.decompress([4, 0x00, 0x61, 0x01, 0x05]))  // copy before its offset
        XCTAssertNil(Snappy.decompress([4, 0x00, 0x61, 0x01]))  // copy missing its offset byte
        XCTAssertNil(Snappy.decompress([4, 0x00, 0x61, 0x02, 0x01]))  // copy-2 missing a byte
        XCTAssertNil(Snappy.decompress([4, 0x00, 0x61, 0x03, 0x01, 0x00]))  // copy-4 missing bytes
        XCTAssertNil(Snappy.decompress([5, 0xF0]))  // long literal missing its length byte
        XCTAssertNil(Snappy.decompress([9, 0x00, 0x61]))  // shorter than the preamble says
        XCTAssertNil(Snappy.decompress([UInt8](repeating: 0x80, count: 11)))  // varint over 64 bits
    }
}
