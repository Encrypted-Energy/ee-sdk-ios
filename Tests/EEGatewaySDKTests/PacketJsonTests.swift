import XCTest
@testable import EEGatewaySDK

final class PacketJsonTests: XCTestCase {

    // Values chosen so Double-to-String is identical on every platform
    // (short decimals round-trip unambiguously); the wire-parity test below
    // uses the real iOS 1.2 production fixture with contains-checks instead.
    private let clean = UploadPacket(
        eidHex: "5f982837",
        payloadB64: "AQID",
        rssi: -50,
        timestampSeconds: 1_785_545_352,
        latitude: 40.5,
        longitude: -74.25,
        positionAtSeconds: 1_785_545_340,
        accuracyM: 14.0
    )

    private func variant(latitude: Double? = nil, accuracyM: Double?? = nil) -> UploadPacket {
        UploadPacket(
            eidHex: clean.eidHex,
            payloadB64: clean.payloadB64,
            rssi: clean.rssi,
            timestampSeconds: clean.timestampSeconds,
            latitude: latitude ?? clean.latitude,
            longitude: clean.longitude,
            positionAtSeconds: clean.positionAtSeconds,
            accuracyM: accuracyM ?? clean.accuracyM
        )
    }

    func testPacketMatchesWireContractExactly() throws {
        XCTAssertEqual(
            try PacketJson.packet(clean),
            "{\"payload_b64\":\"AQID\",\"rssi\":-50,\"timestamp\":1785545352,"
                + "\"latitude\":40.5,\"longitude\":-74.25,\"position_at\":1785545340,"
                + "\"eid\":\"5f982837\",\"accuracy_m\":14.0}"
        )
    }

    func testIos12ProductionFixtureParity() throws {
        // Observed on the wire from iOS 1.2 in prod (Loki, 2026-08-01):
        // every key present, unix-seconds ints, unpadded lowercase hex eid.
        let p = UploadPacket(
            eidHex: "5f982837",
            payloadB64: "A1NfmCg3HoGjWrKY3zg=",
            rssi: -50,
            timestampSeconds: 1_785_545_352,
            latitude: 47.587223436883434,
            longitude: -122.07973720240967,
            positionAtSeconds: 1_785_545_340,
            accuracyM: 13.988265225086755
        )
        let json = try PacketJson.packet(p)
        XCTAssertTrue(json.contains("\"payload_b64\":\"A1NfmCg3HoGjWrKY3zg=\""), json)
        XCTAssertTrue(json.contains("\"timestamp\":1785545352"), json)
        XCTAssertTrue(json.contains("\"position_at\":1785545340"), json)
        XCTAssertTrue(json.contains("\"latitude\":47.58722"), json)
        XCTAssertTrue(json.contains("\"longitude\":-122.07973"), json)
        XCTAssertTrue(json.contains("\"accuracy_m\":13.98826"), json)
        XCTAssertTrue(json.contains("\"eid\":\"5f982837\""), json)
        XCTAssertTrue(json.contains("\"rssi\":-50"), json)
    }

    func testOmitsAccuracyWhenFixHadNone() throws {
        let json = try PacketJson.packet(variant(accuracyM: .some(nil)))
        XCTAssertFalse(json.contains("accuracy_m"), json)
    }

    func testBodyWrapsPacketsArray() throws {
        let one = try PacketJson.packet(clean)
        XCTAssertEqual(
            try PacketJson.body([clean, clean]),
            "{\"packets\":[\(one),\(one)]}"
        )
    }

    func testNonFiniteCoordinateFailsLoudly() {
        XCTAssertThrowsError(try PacketJson.packet(variant(latitude: .nan)))
    }
}
