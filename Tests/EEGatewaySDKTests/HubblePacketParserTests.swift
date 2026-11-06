import XCTest
@testable import EEGatewaySDK

/// Contract tests for HubblePacketParser (plan §2), including the two REAL
/// FCA6 service-data payloads captured at John's desk in JC on 2026-07-11.
/// Carried verbatim from gateway-ios HubblePacketParserTests.swift, plus the
/// v2 high-bit EID fixture the Android SDK added, so the fixture set is
/// identical on both platforms.
///
/// A frame whose eidHex is nil must be dropped before the queue (§1a: ee-web
/// 422s any batch containing a packet without an eid).
final class HubblePacketParserTests: XCTestCase {

    private func data(_ b64: String) -> Data { Data(base64Encoded: b64)! }

    // MARK: v0 — real field payloads (JC desk tally, 2026-07-11)

    func testV0RealPayloadDevice1() {
        // raw = 03aa098b628e9a7eb126dc49f552 (14 bytes)
        let raw = data("A6oJi2KOmn6xJtxJ9VI=")
        let p = HubblePacketParser.parse(raw)!
        XCTAssertEqual(p.version, 0)                       // 0x03 >> 2 == 0
        // EID bytes are 09 8b 62 8e -> 0x098b628e -> unpadded hex drops the
        // leading zero. THE zero-padding regression test: "098b628e" is wrong.
        XCTAssertEqual(p.eidHex, "98b628e")
        XCTAssertEqual(p.payload, raw)                     // v0 forwards entire raw
    }

    func testV0RealPayloadDevice2() {
        // raw = 03aaefcacfae392cc3cfe12ed923 (14 bytes)
        let raw = data("A6rvys+uOSzDz+Eu2SM=")
        let p = HubblePacketParser.parse(raw)!
        XCTAssertEqual(p.version, 0)
        XCTAssertEqual(p.eidHex, "efcacfae")
        XCTAssertEqual(p.payload, raw)
    }

    func testV0TooShortForEID() {
        // 5-byte v0 frame: header parses but raw.count < 6 -> no EID -> must
        // be droppable (nil eidHex), never forwarded.
        let p = HubblePacketParser.parse(data("AwECAwQ="))!
        XCTAssertEqual(p.version, 0)
        XCTAssertNil(p.eidHex)
    }

    // MARK: v1 — unencrypted, carries no EID -> local drop (§1a)

    func testV1ParsesButHasNoEID() {
        // 40-bit BE header: version=1 (hdr40 >> 34), network_id=5,
        // then 3 payload bytes aa bb cc. raw = 0400000005aabbcc.
        let raw = data("BAAAAAWqu8w=")
        let p = HubblePacketParser.parse(raw)!
        XCTAssertEqual(p.version, 1)
        XCTAssertNil(p.eidHex)                             // -> drop before queue
        XCTAssertEqual(p.payload, data("qrvM"))            // raw[5...]
    }

    // MARK: v2 — AES-EAX, 8-byte little-endian EID

    func testV2LittleEndianEID() {
        // raw = 08 0102 8877665544332211 aabb deadbeef (17 bytes >= 15)
        // ver 0x08 >> 2 == 2; EID = raw[3..<11] as LE UInt64 = 0x1122334455667788
        let raw = data("CAECiHdmVUQzIhGqu96tvu8=")
        let p = HubblePacketParser.parse(raw)!
        XCTAssertEqual(p.version, 2)
        XCTAssertEqual(p.eidHex, "1122334455667788")
        XCTAssertEqual(p.payload, data("qrs="))            // raw[11..<(count-4)]
    }

    func testV2HighBitEIDFormatsUnsigned() {
        // Android-SDK parity fixture. Swift's UInt64 never had the signed-Long
        // hazard, but both platforms run the identical vector anyway.
        // EID bytes LE 88 77 66 55 44 33 22 f1 -> 0xf122334455667788.
        let raw = Data([
            0x08, 0x01, 0x02,
            0x88, 0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0xF1,
            0xAA, 0xBB,
            0xDE, 0xAD, 0xBE, 0xEF,
        ])
        let p = HubblePacketParser.parse(raw)!
        XCTAssertEqual(p.version, 2)
        XCTAssertEqual(p.eidHex, "f122334455667788")
    }

    // MARK: unknown version -> no EID -> local drop (§1a)

    func testUnknownVersionHasNoEID() {
        // 0xFF >> 2 == 63: unknown. Whole raw is the payload, no EID.
        let raw = Data([0xFF, 0x01, 0x02, 0x03, 0x04, 0x05])
        let p = HubblePacketParser.parse(raw)!
        XCTAssertNil(p.eidHex)
        XCTAssertEqual(p.payload, raw)
    }

    // MARK: EID formatting must match Python format(eid, 'x') exactly

    func testEIDHexNeverZeroPadded() {
        // Server-side dedup key and bounty cap are keyed on the unpadded
        // string; "098b628e" and "98b628e" would split into two devices.
        // v0 frame with EID bytes 00 00 00 2a -> "2a", not "0000002a".
        var raw = Data([0x03, 0x00, 0x00, 0x00, 0x00, 0x2A])
        raw.append(contentsOf: [0xDE, 0xAD, 0xBE, 0xEF])   // auth tag filler
        let p = HubblePacketParser.parse(raw)!
        XCTAssertEqual(p.eidHex, "2a")
    }
}
