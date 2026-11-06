import XCTest
@testable import EEGatewaySDK

final class EEStatusTests: XCTestCase {

    func testDefaults() {
        let status = EEStatus(state: .ready)
        XCTAssertEqual(status.state, .ready)
        XCTAssertEqual(status.pingsHeard, 0)
        XCTAssertEqual(status.packetsForwarded, 0)
        XCTAssertEqual(status.queueDepth, 0)
        XCTAssertNil(status.gatewayPublicId)
        XCTAssertNil(status.lastHeartbeatAt)
    }

    func testWithStatePreservesEveryOtherField() {
        let status = EEStatus(
            state: .running,
            pingsHeard: 42,
            packetsForwarded: 7,
            queueDepth: 3,
            gatewayPublicId: "gw_pub_123",
            lastHeartbeatAt: 1_700_000_000_000
        )
        let stopped = status.with(state: .stopped)
        XCTAssertEqual(stopped.state, .stopped)
        XCTAssertEqual(stopped.pingsHeard, 42)
        XCTAssertEqual(stopped.packetsForwarded, 7)
        XCTAssertEqual(stopped.queueDepth, 3)
        XCTAssertEqual(stopped.gatewayPublicId, "gw_pub_123")
        XCTAssertEqual(stopped.lastHeartbeatAt, 1_700_000_000_000)
    }

    func testEquality() {
        XCTAssertEqual(EEStatus(state: .ready), EEStatus(state: .ready))
        XCTAssertNotEqual(EEStatus(state: .ready), EEStatus(state: .running))
        XCTAssertNotEqual(EEStatus(state: .ready), EEStatus(state: .ready, pingsHeard: 1))
    }
}
