import XCTest
@testable import EEGatewaySDK

/// The published ingest contract, branch by branch: 500 max per request,
/// 413 split, 422 drop + invalid_reasons, transient/401 stop-and-requeue.
final class BatchSenderTests: XCTestCase {

    private func packet(_ i: Int) -> UploadPacket {
        UploadPacket(
            eidHex: "eid\(i)",
            payloadB64: "cGF5bG9hZA==",
            rssi: -60,
            timestampSeconds: 1_783_780_342 + Int64(i),
            latitude: 40.72,
            longitude: -74.04,
            positionAtSeconds: 1_783_780_342 + Int64(i),
            accuracyM: 12.0
        )
    }

    private func batch(_ n: Int) -> [UploadPacket] {
        (0..<n).map(packet)
    }

    /// Counts the packets in one ingest body without a real JSON parser.
    private func packetCount(_ body: String) -> Int {
        body.components(separatedBy: "\"payload_b64\"").count - 1
    }

    private func ok(_ bounty: Int = 0) -> EEClient.Result {
        .ok(code: 200, bountyEarned: bounty, disable: false, publicId: nil)
    }

    func testSmallBatchForwardsInOneCall() async {
        var bodies: [String] = []
        let out = await BatchSender.send(batch(3)) { body in
            bodies.append(body)
            return self.ok(2)
        }
        XCTAssertEqual(bodies.count, 1)
        XCTAssertEqual(out.forwarded, 3)
        XCTAssertEqual(out.bountyEarned, 2)
        XCTAssertEqual(out.dropped, 0)
        XCTAssertTrue(out.requeue.isEmpty)
        XCTAssertFalse(out.unauthorized)
        XCTAssertNil(out.transientReason)
    }

    func testOversizeBatchIsPreChunkedTo500() async {
        var sizes: [Int] = []
        let out = await BatchSender.send(batch(1_201)) { body in
            sizes.append(self.packetCount(body))
            return self.ok()
        }
        XCTAssertEqual(sizes, [500, 500, 201])
        XCTAssertEqual(out.forwarded, 1_201)
    }

    func testBountyAccumulatesAcrossChunks() async {
        var call = 0
        let out = await BatchSender.send(batch(600)) { _ in
            call += 1
            return self.ok(call)
        }
        XCTAssertEqual(out.bountyEarned, 3)   // 1 + 2
    }

    func testOn413TheChunkSplitsAndResends() async {
        var sizes: [Int] = []
        let out = await BatchSender.send(batch(10)) { body in
            let n = self.packetCount(body)
            sizes.append(n)
            return n > 5 ? .terminal(code: 413, body: nil) : self.ok()
        }
        XCTAssertEqual(sizes, [10, 5, 5])
        XCTAssertEqual(out.forwarded, 10)
        XCTAssertEqual(out.dropped, 0)
    }

    func testA413OnASinglePacketDropsIt() async {
        // Unsplittable: retrying a one-packet 413 can't change the answer.
        let out = await BatchSender.send(batch(1)) { _ in .terminal(code: 413, body: nil) }
        XCTAssertEqual(out.forwarded, 0)
        XCTAssertEqual(out.dropped, 1)
        XCTAssertTrue(out.requeue.isEmpty)
    }

    func testOn422TheChunkDropsAndReasonsSurface() async {
        let out = await BatchSender.send(batch(4)) { _ in
            .terminal(code: 422, body: #"{"ok":false,"invalid_reasons":["packet[1]: missing eid"]}"#)
        }
        XCTAssertEqual(out.forwarded, 0)
        XCTAssertEqual(out.dropped, 4)
        XCTAssertEqual(out.droppedReasons, ["packet[1]: missing eid"])
        XCTAssertTrue(out.requeue.isEmpty)
    }

    func testOtherTerminal4xxDropsWithoutReasons() async {
        let out = await BatchSender.send(batch(2)) { _ in .terminal(code: 400, body: nil) }
        XCTAssertEqual(out.dropped, 2)
        XCTAssertTrue(out.droppedReasons.isEmpty)
    }

    func testTransientStopsAndRequeuesEverythingUndecided() async {
        var call = 0
        let out = await BatchSender.send(batch(1_100)) { _ in
            call += 1
            return call == 1 ? self.ok() : .transient(reason: "HTTP 502")
        }
        XCTAssertEqual(out.forwarded, 500)
        XCTAssertEqual(out.requeue.count, 600)
        XCTAssertEqual(out.transientReason, "HTTP 502")
        XCTAssertFalse(out.unauthorized)
        // Order preserved: the requeue picks up exactly where the 2xx stopped.
        XCTAssertEqual(out.requeue.first?.eidHex, "eid500")
        XCTAssertEqual(out.requeue.last?.eidHex, "eid1099")
    }

    func testUnauthorizedStopsAndRequeuesEverythingUndecided() async {
        let out = await BatchSender.send(batch(7)) { _ in .unauthorized }
        XCTAssertEqual(out.forwarded, 0)
        XCTAssertEqual(out.requeue.count, 7)
        XCTAssertTrue(out.unauthorized)
        XCTAssertNil(out.transientReason)
    }

    func testThrowingIngestIsTreatedAsTransient() async {
        enum WiringBug: Error { case boom }
        let out = await BatchSender.send(batch(2)) { _ in throw WiringBug.boom }
        XCTAssertEqual(out.requeue.count, 2)
        XCTAssertEqual(out.transientReason, "WiringBug")
    }

    func testEmptyBatchMakesNoCalls() async {
        var calls = 0
        let out = await BatchSender.send([]) { _ in
            calls += 1
            return self.ok()
        }
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(out.forwarded, 0)
    }
}
