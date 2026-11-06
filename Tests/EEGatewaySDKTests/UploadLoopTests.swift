import XCTest
@testable import EEGatewaySDK

/// The loop's own jobs around BatchSender (which has its own contract
/// tests): pacing (one server batch per tick), requeue of the undecided
/// remainder in original order, forwarded-counter bumps, and the outcome
/// callback. Everything runs through tick() — no timer, no clock.
/// Android's two throwing-callback tests have no counterpart: the closure
/// types here are non-throwing by construction.
final class UploadLoopTests: XCTestCase {

    private func packet(_ i: Int) -> UploadPacket {
        UploadPacket(
            eidHex: "eid\(i)", payloadB64: "AQID", rssi: -50,
            timestampSeconds: 1_785_545_352 + Int64(i),
            latitude: 40.5, longitude: -74.25,
            positionAtSeconds: 1_785_545_340 + Int64(i), accuracyM: 14.0
        )
    }

    private func loaded(_ n: Int) -> PacketQueue {
        let q = PacketQueue()
        (1...n).forEach { q.add(packet($0)) }
        return q
    }

    private func ok(_ bounty: Int = 0) -> EEClient.Result {
        .ok(code: 200, bountyEarned: bounty, disable: false, publicId: nil)
    }

    func testEmptyQueueMakesNoWireCallAndNoCallback() async {
        let loop = UploadLoop(
            ingest: { _ in XCTFail("wire call on empty queue"); return self.ok() },
            queue: PacketQueue(),
            counters: Counters(),
            onOutcome: { _ in XCTFail("callback on empty queue") }
        )
        await loop.tick()
    }

    func testOkDrainsQueueAndCountsForwarded() async {
        let queue = loaded(3)
        let counters = Counters()
        var outcome: BatchSender.Outcome?
        await UploadLoop(ingest: { _ in self.ok() }, queue: queue, counters: counters) { outcome = $0 }.tick()
        XCTAssertEqual(queue.size(), 0)
        XCTAssertEqual(counters.takeSnapshot().forwarded, 3)
        XCTAssertEqual(outcome?.forwarded, 3)
    }

    func testTransientRequeuesInOriginalOrderAndCountsNothing() async {
        let queue = loaded(3)
        let counters = Counters()
        await UploadLoop(ingest: { _ in .transient(reason: "HTTP 502") }, queue: queue, counters: counters).tick()
        XCTAssertEqual(queue.snapshot().map(\.eidHex), ["eid1", "eid2", "eid3"])
        XCTAssertEqual(counters.takeSnapshot().forwarded, 0)
    }

    func testUnauthorizedRequeuesAndFlagsOutcome() async {
        let queue = loaded(2)
        var outcome: BatchSender.Outcome?
        await UploadLoop(ingest: { _ in .unauthorized }, queue: queue, counters: Counters()) { outcome = $0 }.tick()
        XCTAssertEqual(queue.size(), 2)
        XCTAssertEqual(outcome?.unauthorized, true)
    }

    func testTerminalDropsBatch() async {
        let queue = loaded(3)
        let counters = Counters()
        var outcome: BatchSender.Outcome?
        await UploadLoop(ingest: { _ in .terminal(code: 400, body: nil) }, queue: queue, counters: counters) { outcome = $0 }.tick()
        XCTAssertEqual(queue.size(), 0)
        XCTAssertEqual(counters.takeSnapshot().forwarded, 0)
        XCTAssertEqual(outcome?.dropped, 3)
    }

    func testOutcomeCarries422Reasons() async {
        var outcome: BatchSender.Outcome?
        await UploadLoop(
            ingest: { _ in .terminal(code: 422, body: #"{"ok":false,"invalid_reasons":["packet[0]: missing eid"]}"#) },
            queue: loaded(1),
            counters: Counters()
        ) { outcome = $0 }.tick()
        XCTAssertEqual(outcome?.droppedReasons, ["packet[0]: missing eid"])
    }

    func testDrainsAtMostOneServerBatchPerTick() async {
        // Pacing: a tick takes maxBatch off the queue; the rest wait for the
        // next tick rather than hammering the server in one pass.
        let queue = loaded(PacketQueue.maxBatch + 1)
        var calls = 0
        await UploadLoop(ingest: { _ in calls += 1; return self.ok() }, queue: queue, counters: Counters()).tick()
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(queue.size(), 1)
    }

    func testBountySurfacesInOutcome() async {
        var outcome: BatchSender.Outcome?
        await UploadLoop(ingest: { _ in self.ok(2) }, queue: loaded(2), counters: Counters()) { outcome = $0 }.tick()
        XCTAssertEqual(outcome?.bountyEarned, 2)
    }
}
