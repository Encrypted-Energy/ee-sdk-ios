import XCTest
@testable import EEGatewaySDK

final class PacketQueueTests: XCTestCase {

    private func packet(_ n: Int) -> UploadPacket {
        UploadPacket(
            eidHex: "eid\(n)",
            payloadB64: "AQID",
            rssi: -50,
            timestampSeconds: 1_785_545_352 + Int64(n),
            latitude: 40.5,
            longitude: -74.25,
            positionAtSeconds: 1_785_545_340 + Int64(n),
            accuracyM: 14.0
        )
    }

    func testFifoOrder() {
        let q = PacketQueue()
        (1...3).forEach { q.add(packet($0)) }
        XCTAssertEqual(q.takeBatch().map(\.eidHex), ["eid1", "eid2", "eid3"])
        XCTAssertEqual(q.size(), 0)
    }

    func testTakeBatchRespectsMaxAndLeavesRest() {
        let q = PacketQueue()
        (1...5).forEach { q.add(packet($0)) }
        XCTAssertEqual(q.takeBatch(2).map(\.eidHex), ["eid1", "eid2"])
        XCTAssertEqual(q.size(), 3)
    }

    func testOverflowDropsOldest() {
        let q = PacketQueue(capacity: 3)
        (1...4).forEach { q.add(packet($0)) }
        XCTAssertEqual(q.takeBatch().map(\.eidHex), ["eid2", "eid3", "eid4"])
    }

    func testRequeuePutsBatchBackInFrontInOrder() {
        let q = PacketQueue()
        (1...4).forEach { q.add(packet($0)) }
        let batch = q.takeBatch(2)   // [1, 2]; [3, 4] remain
        q.requeue(batch)
        XCTAssertEqual(q.takeBatch().map(\.eidHex), ["eid1", "eid2", "eid3", "eid4"])
    }

    func testRequeueRetrimsToCapacity() {
        let q = PacketQueue(capacity: 3)
        (1...3).forEach { q.add(packet($0)) }
        let batch = q.takeBatch(2)   // [1, 2]; [3] remains
        q.add(packet(4))
        q.add(packet(5))             // [3, 4, 5] — full again
        q.requeue(batch)             // 5 packets into capacity 3: oldest go
        XCTAssertEqual(q.size(), 3)
        XCTAssertEqual(q.takeBatch().map(\.eidHex), ["eid3", "eid4", "eid5"])
    }

    func testMaxBatchMatchesServerLimit() {
        // ee-web MAX_PACKETS_PER_REQUEST is 500; a bigger batch 413s.
        XCTAssertLessThanOrEqual(PacketQueue.maxBatch, 500)
    }

    func testOnChangeFiresOnMutationsOnly() {
        let q = PacketQueue()
        var fires = 0
        q.onChange = { fires += 1 }

        q.add(packet(1))             // 1
        _ = q.takeBatch()            // 2
        _ = q.takeBatch()            // empty take: no fire
        q.requeue([])                // empty requeue: no fire
        q.clear()                    // already empty: no fire
        q.add(packet(2))             // 3
        q.clear()                    // 4
        XCTAssertEqual(fires, 4)
    }
}
