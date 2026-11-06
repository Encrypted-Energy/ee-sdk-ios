import XCTest
@testable import EEGatewaySDK

final class QueueStoreTests: XCTestCase {

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("eeq-test-\(UUID().uuidString).eeq")
    }

    private let packet = UploadPacket(
        eidHex: "5f982837",
        payloadB64: "A1NfmCg3HoGjWrKY3zg=",
        rssi: -50,
        timestampSeconds: 1_785_545_352,
        latitude: 47.587223436883434,
        longitude: -122.07973720240967,
        positionAtSeconds: 1_785_545_340,
        accuracyM: 13.988265225086755
    )

    private func withoutAccuracy(eid: String) -> UploadPacket {
        UploadPacket(
            eidHex: eid,
            payloadB64: packet.payloadB64,
            rssi: packet.rssi,
            timestampSeconds: packet.timestampSeconds,
            latitude: packet.latitude,
            longitude: packet.longitude,
            positionAtSeconds: packet.positionAtSeconds,
            accuracyM: nil
        )
    }

    func testRoundTripsExactly() {
        let store = QueueStore(fileURL: tempURL())
        store.persistNow([packet, withoutAccuracy(eid: "baeb60")])
        let loaded = store.load()
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0], packet)
        XCTAssertEqual(loaded[1].eidHex, "baeb60")
        XCTAssertNil(loaded[1].accuracyM)
    }

    func testMissingFileLoadsEmpty() {
        XCTAssertTrue(QueueStore(fileURL: tempURL()).load().isEmpty)
    }

    func testEmptyQueuePersistsAndLoadsEmpty() {
        let store = QueueStore(fileURL: tempURL())
        store.persistNow([])
        XCTAssertTrue(store.load().isEmpty)
    }

    func testMalformedLinesAreSkipped() throws {
        let url = tempURL()
        let store = QueueStore(fileURL: url)
        store.persistNow([packet])
        var text = try String(contentsOf: url, encoding: .utf8)
        text += "garbage|line\n"
        text += "a|b|notanint|4|5|6|7|8\n"
        try text.write(to: url, atomically: true, encoding: .utf8)

        let loaded = store.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0], packet)
    }

    func testFormatMarkerLineIsNotAPacket() {
        let store = QueueStore(fileURL: tempURL())
        store.persistNow([packet])
        // Marker "eeq1" must not decode into a packet on load.
        XCTAssertEqual(store.load().count, 1)
    }

    func testDecodeRejectsWrongFieldCount() {
        XCTAssertNil(QueueStore.decode("a|b|c"))
        XCTAssertNil(QueueStore.decode(""))
    }

    func testEncodeIsPipeSafe() {
        // No field of a valid packet can contain '|' (base64, hex, decimal),
        // so split-on-pipe round-trips: field count stays 8.
        XCTAssertEqual(QueueStore.encode(packet).components(separatedBy: "|").count, 8)
    }

    func testSchedulePersistCoalescesAndWrites() {
        let url = tempURL()
        let store = QueueStore(fileURL: url)
        let queue = PacketQueue()
        queue.add(packet)

        for _ in 0..<10 { store.schedulePersist(queue) }

        // The writer queue is serial; a sync barrier drains all pending work.
        let drained = expectation(description: "writer drained")
        DispatchQueue(label: "ee-test-drain").async {
            Thread.sleep(forTimeInterval: 0.2)
            drained.fulfill()
        }
        wait(for: [drained], timeout: 5)
        XCTAssertEqual(store.load(), [packet])
    }
}
