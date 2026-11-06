import XCTest
@testable import EEGatewaySDK

final class EEGatewayFacadeTests: XCTestCase {

    override func setUp() {
        super.setUp()
        EEGateway._resetForTests()
    }

    override func tearDown() {
        EEGateway._resetForTests()
        super.tearDown()
    }

    func testInitialStateIsUnconfigured() {
        XCTAssertEqual(EEGateway.status().state, .unconfigured)
    }

    func testStartBeforeConfigureIsANoOp() {
        EEGateway.start()
        XCTAssertEqual(EEGateway.status().state, .unconfigured)
    }

    func testStopBeforeConfigureIsANoOp() {
        EEGateway.stop()
        XCTAssertEqual(EEGateway.status().state, .unconfigured)
    }

    func testConfigureMovesToReady() {
        EEGateway.configure(.gatewayToken(token: "ee_live_abc"))
        XCTAssertEqual(EEGateway.status().state, .ready)
    }

    func testConfigureIsIdempotentAndNeverRegresses() {
        EEGateway.configure(.gatewayToken(token: "ee_live_abc"))
        EEGateway.start()
        XCTAssertEqual(EEGateway.status().state, .running)
        EEGateway.configure(.gatewayToken(token: "ee_live_other"))
        XCTAssertEqual(EEGateway.status().state, .running, "re-configure must not regress a running gateway")
    }

    func testStartStopLifecycle() {
        EEGateway.configure(.selfMint())
        EEGateway.start()
        XCTAssertEqual(EEGateway.status().state, .running)
        EEGateway.stop()
        XCTAssertEqual(EEGateway.status().state, .stopped)
        EEGateway.start()
        XCTAssertEqual(EEGateway.status().state, .running, "stopped → start must resume")
    }

    func testStartIsIdempotent() {
        EEGateway.configure(.selfMint())
        EEGateway.start()
        EEGateway.start()
        XCTAssertEqual(EEGateway.status().state, .running)
    }

    func testStopIsIdempotent() {
        EEGateway.configure(.selfMint())
        EEGateway.start()
        EEGateway.stop()
        EEGateway.stop()
        XCTAssertEqual(EEGateway.status().state, .stopped)
    }

    func testListenerSeesTransitions() {
        let queue = DispatchQueue(label: "ee.test.callbacks")
        EEGateway.callbackQueue = queue

        var seen: [EEState] = []
        let delivered = expectation(description: "three transitions delivered")
        delivered.expectedFulfillmentCount = 3
        EEGateway.setListener { status in
            seen.append(status.state)
            delivered.fulfill()
        }

        EEGateway.configure(.gatewayToken(token: "ee_live_abc"))
        EEGateway.start()
        EEGateway.stop()

        wait(for: [delivered], timeout: 5)
        queue.sync {}   // drain any trailing posts
        XCTAssertEqual(seen, [.ready, .running, .stopped])
    }

    func testListenerNotCalledWhenNothingChanged() {
        let queue = DispatchQueue(label: "ee.test.callbacks")
        EEGateway.callbackQueue = queue

        EEGateway.configure(.gatewayToken(token: "ee_live_abc"))
        EEGateway.start()

        var calls = 0
        EEGateway.setListener { _ in calls += 1 }
        EEGateway.start()           // idempotent: no transition
        EEGateway.configure(.gatewayToken(token: "ee_live_abc"))   // same state
        queue.sync {}
        XCTAssertEqual(calls, 0)
    }

    func testClearingListenerStopsCallbacks() {
        let queue = DispatchQueue(label: "ee.test.callbacks")
        EEGateway.callbackQueue = queue

        var calls = 0
        EEGateway.setListener { _ in calls += 1 }
        EEGateway.setListener(nil)
        EEGateway.configure(.selfMint())
        queue.sync {}
        XCTAssertEqual(calls, 0)
    }

    func testStatusCarriesVersionConstant() {
        XCTAssertEqual(EEGateway.version, "0.1.0")
    }
}
