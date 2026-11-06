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
}
