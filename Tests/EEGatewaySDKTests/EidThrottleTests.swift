import XCTest
@testable import EEGatewaySDK

final class EidThrottleTests: XCTestCase {

    func testForwardsFirstSighting() {
        let t = EidThrottle(windowMillis: 3_000)
        XCTAssertTrue(t.shouldForward(eid: "98b628e", nowMillis: 1_000))
    }

    func testSuppressesWithinWindow() {
        let t = EidThrottle(windowMillis: 3_000)
        XCTAssertTrue(t.shouldForward(eid: "98b628e", nowMillis: 1_000))
        XCTAssertFalse(t.shouldForward(eid: "98b628e", nowMillis: 2_000))
        XCTAssertFalse(t.shouldForward(eid: "98b628e", nowMillis: 3_999))
    }

    func testForwardsAgainAfterWindow() {
        let t = EidThrottle(windowMillis: 3_000)
        XCTAssertTrue(t.shouldForward(eid: "98b628e", nowMillis: 1_000))
        XCTAssertTrue(t.shouldForward(eid: "98b628e", nowMillis: 4_000))
    }

    func testTracksEidsIndependently() {
        let t = EidThrottle(windowMillis: 3_000)
        XCTAssertTrue(t.shouldForward(eid: "98b628e", nowMillis: 1_000))
        XCTAssertTrue(t.shouldForward(eid: "efcacfae", nowMillis: 1_001))
        XCTAssertFalse(t.shouldForward(eid: "98b628e", nowMillis: 1_002))
    }

    func testSuppressionDoesNotExtendTheWindow() {
        // A sighting rejected mid-window must not reset the clock: the EID
        // becomes forwardable windowMillis after the last FORWARD, not the
        // last sighting.
        let t = EidThrottle(windowMillis: 3_000)
        XCTAssertTrue(t.shouldForward(eid: "98b628e", nowMillis: 1_000))
        XCTAssertFalse(t.shouldForward(eid: "98b628e", nowMillis: 3_500))
        XCTAssertTrue(t.shouldForward(eid: "98b628e", nowMillis: 4_100))
    }

    func testBoundedUnderIdentifierFlood() {
        // 0.2.0 item iv: a rotating-identifier flood must not grow the map
        // without limit. After 2x maxEntries distinct EIDs, the first one
        // has rotated out of both generations: forwardable again even
        // inside its window.
        let t = EidThrottle(windowMillis: 100_000_000)
        XCTAssertTrue(t.shouldForward(eid: "eid0", nowMillis: 1_000))
        for i in 1...(EidThrottle.maxEntries * 2) {
            XCTAssertTrue(t.shouldForward(eid: "eid\(i)", nowMillis: 2_000 + Int64(i)))
        }
        XCTAssertTrue(t.shouldForward(eid: "eid0", nowMillis: 500_000))
    }

    func testHotEidSurvivesTheFlood() {
        // A suppressed sighting refreshes recency: an EID that keeps being
        // SEEN between generation-sized bursts must never be the eviction
        // victim (still throttled at the end).
        let t = EidThrottle(windowMillis: 100_000_000)
        XCTAssertTrue(t.shouldForward(eid: "hot", nowMillis: 1_000))
        let burst = EidThrottle.maxEntries / 2
        for g in 0..<4 {
            for i in 0..<burst {
                _ = t.shouldForward(
                    eid: "g\(g)-\(i)", nowMillis: 10_000 + Int64(g * burst + i)
                )
            }
            XCTAssertFalse(
                t.shouldForward(eid: "hot", nowMillis: 90_000 + Int64(g)),
                "hot eid evicted after burst \(g)"
            )
        }
    }
}
