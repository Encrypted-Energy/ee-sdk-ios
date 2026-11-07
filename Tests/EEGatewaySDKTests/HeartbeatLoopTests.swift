import XCTest
@testable import EEGatewaySDK

/// Tick semantics: deltas snapshot-and-reset before the POST, restored on
/// transient failure, dropped on terminal — the Pi worker's rules.
/// Everything runs through tick() — no timer, no clock. Android's
/// throwing-wire-call and throwing-callback tests have no counterpart: the
/// closure types here are non-throwing by construction.
final class HeartbeatLoopTests: XCTestCase {

    private let runtime = HeartbeatPayload.Runtime(
        osVersion: "iOS 19.1.2", uptimeSeconds: 60,
        lastPacketAtMillis: nil, gpsStatus: "no_fix"
    )

    private func countersWithHeard(_ n: Int) -> Counters {
        let c = Counters()
        (0..<n).forEach { _ in c.heardPacket() }
        return c
    }

    private func ok(disable: Bool = false) -> EEClient.Result {
        .ok(code: 200, bountyEarned: 0, disable: disable, publicId: nil)
    }

    func testPostsDeltasAndResetsOnOk() async {
        let counters = countersWithHeard(2)
        var body: String?
        await HeartbeatLoop(heartbeat: { body = $0; return self.ok() }, counters: counters, runtimeInfo: { self.runtime }).tick()
        XCTAssertTrue(body?.contains("\"packets_heard_delta\":2") == true, body ?? "nil")
        XCTAssertEqual(counters.takeSnapshot().heard, 0)
    }

    func testTransientRestoresDeltas() async {
        let counters = countersWithHeard(3)
        await HeartbeatLoop(heartbeat: { _ in .transient(reason: "network") }, counters: counters, runtimeInfo: { self.runtime }).tick()
        XCTAssertEqual(counters.takeSnapshot().heard, 3)
    }

    func testRestoreAddsOnTopOfCountsSinceSnapshot() async {
        let counters = countersWithHeard(3)
        let loop = HeartbeatLoop(
            heartbeat: { _ in counters.heardPacket(); return .transient(reason: "network") },
            counters: counters,
            runtimeInfo: { self.runtime }
        )
        await loop.tick()
        XCTAssertEqual(counters.takeSnapshot().heard, 4)
    }

    func testTerminalDropsDeltas() async {
        let counters = countersWithHeard(2)
        await HeartbeatLoop(heartbeat: { _ in .terminal(code: 422, body: nil) }, counters: counters, runtimeInfo: { self.runtime }).tick()
        XCTAssertEqual(counters.takeSnapshot().heard, 0)
    }

    func testUnauthorizedDropsDeltas() async {
        let counters = countersWithHeard(2)
        await HeartbeatLoop(heartbeat: { _ in .unauthorized }, counters: counters, runtimeInfo: { self.runtime }).tick()
        XCTAssertEqual(counters.takeSnapshot().heard, 0)
    }

    func testOkResultReachesCallbackWithDisableFlag() async {
        var result: EEClient.Result?
        await HeartbeatLoop(heartbeat: { _ in self.ok(disable: true) }, counters: Counters(), runtimeInfo: { self.runtime }) { result = $0 }.tick()
        if case .ok(_, _, let disable, _)? = result {
            XCTAssertTrue(disable)
        } else {
            XCTFail("expected ok, got \(String(describing: result))")
        }
    }

    func testSdkCadenceIsThreeMinutes() {
        // Plan §3 + §6 risk 3: conservative fleet cadence, NOT the
        // first-party app's 60 s. A partner's battery budget is a contract.
        // 300 s at launch; 180 s per John 11/6 after first-device dogfood.
        XCTAssertEqual(HeartbeatLoop.intervalSeconds, 180)
    }
}
