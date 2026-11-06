import Foundation
import XCTest
@testable import EEGatewaySDK

/// The frozen surface over a REAL Engine (fake radio/location seams) — the
/// facade suite asserts actual behavior, not stub flips: grants decide
/// running vs awaitingPermissions, the dormancy gate advances on its own,
/// and counter storms coalesce to ~1 callback per window.
final class EEGatewayFacadeTests: XCTestCase {

    private var radio = FakeRadio()
    private var location = FakeLocation()
    private var granted = true
    private var engines: [Engine] = []

    override func setUp() {
        super.setUp()
        EEGateway._resetForTests()
        radio = FakeRadio()
        location = FakeLocation()
        granted = true
        engines = []
        EEGateway.engineFactory = { [self] config, onChanged in
            let store = InMemoryTokenStore()
            // Skip the provisioning reconcile: the store already matches.
            if case .gatewayToken(let token, _) = config { store.save(token) }
            let engine = Engine(
                config: config,
                tokenStore: store,
                client: EEClient(tokenProvider: { store.load() }, transport: { _ in nil }),
                radio: radio,
                location: location,
                permissionsGranted: { self.granted },
                queueFileURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("facade-\(UUID().uuidString).eeq"),
                osVersion: "iOS 19.1.2",
                mint: { _ in .rejected(reason: "test: no network") },
                pollInterval: 0.05,
                onChanged: onChanged
            )
            engines.append(engine)
            return engine
        }
    }

    override func tearDown() {
        EEGateway._resetForTests()
        super.tearDown()
    }

    private func drainEngines() {
        engines.forEach { $0.workQueue.sync {} }
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
        XCTAssertTrue(engines.isEmpty, "no engine before start()")
    }

    func testStartWithGrantsRunsAndDrivesTheRealPipeline() {
        EEGateway.configure(.gatewayToken(token: "ee_live_abc"))
        EEGateway.start()
        XCTAssertEqual(EEGateway.status().state, .running)
        drainEngines()
        XCTAssertEqual(radio.startCalls, 1, "facade start must reach the radio")
    }

    func testStartWithoutGrantsAwaitsPermissions() {
        granted = false
        EEGateway.configure(.gatewayToken(token: "ee_live_abc"))
        EEGateway.start()
        XCTAssertEqual(EEGateway.status().state, .awaitingPermissions)
        drainEngines()
        XCTAssertEqual(radio.startCalls, 0, "dormant SDK must not touch the radio")
    }

    func testDormantFacadeAdvancesToRunningOnItsOwn() {
        granted = false
        EEGateway.refreshCoalesceMillis = 50
        EEGateway.configure(.gatewayToken(token: "ee_live_abc"))

        var seen: [EEState] = []
        let running = expectation(description: "advanced to running")
        EEGateway.setListener { status in
            seen.append(status.state)
            if status.state == .running { running.fulfill() }
        }

        EEGateway.start()
        granted = true   // the host's permission flow completes
        wait(for: [running], timeout: 3)
        XCTAssertTrue(seen.contains(.awaitingPermissions), "\(seen)")
    }

    func testConfigureIsIdempotentAndNeverRegresses() {
        EEGateway.configure(.gatewayToken(token: "ee_live_abc"))
        EEGateway.start()
        XCTAssertEqual(EEGateway.status().state, .running)
        EEGateway.configure(.gatewayToken(token: "ee_live_other"))
        XCTAssertEqual(EEGateway.status().state, .running, "re-configure must not regress a running gateway")
        XCTAssertEqual(engines.count, 1, "config change applies on the NEXT start, not now")
    }

    func testConfigChangeRebuildsEngineOnNextStart() {
        EEGateway.configure(.gatewayToken(token: "ee_live_abc"))
        EEGateway.start()
        EEGateway.stop()
        EEGateway.configure(.gatewayToken(token: "ee_live_rotated"))
        EEGateway.start()
        XCTAssertEqual(engines.count, 2, "changed config from a non-running state must rebuild")
        XCTAssertEqual(EEGateway.status().state, .running)
    }

    func testStartStopLifecycle() {
        EEGateway.configure(.gatewayToken(token: "ee_live_abc"))
        EEGateway.start()
        XCTAssertEqual(EEGateway.status().state, .running)
        EEGateway.stop()
        XCTAssertEqual(EEGateway.status().state, .stopped)
        EEGateway.start()
        XCTAssertEqual(EEGateway.status().state, .running, "stopped → start must resume")
    }

    func testStartIsIdempotent() {
        EEGateway.configure(.gatewayToken(token: "ee_live_abc"))
        EEGateway.start()
        EEGateway.start()
        XCTAssertEqual(EEGateway.status().state, .running)
        drainEngines()
        XCTAssertEqual(radio.startCalls, 1)
    }

    func testStopIsIdempotent() {
        EEGateway.configure(.gatewayToken(token: "ee_live_abc"))
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
        queue.sync {}
        XCTAssertEqual(Array(seen.prefix(3)), [.ready, .running, .stopped])
    }

    func testStatusGraftsEngineCounters() {
        EEGateway.configure(.gatewayToken(token: "ee_live_abc"))
        EEGateway.start()
        drainEngines()
        engines[0].workQueue.sync {
            radio.onHeard?(ParsedPacket(version: 0, eidHex: "2a", payload: Data([1])), -60, Date())
        }
        XCTAssertEqual(EEGateway.status().pingsHeard, 1, "status() must read live engine tallies")
    }

    func testCounterStormCoalescesToOneCallbackPerWindow() {
        EEGateway.refreshCoalesceMillis = 100
        let queue = DispatchQueue(label: "ee.test.callbacks")
        EEGateway.callbackQueue = queue

        EEGateway.configure(.gatewayToken(token: "ee_live_abc"))
        EEGateway.start()
        drainEngines()

        var calls = 0
        EEGateway.setListener { _ in calls += 1 }
        engines[0].workQueue.sync {
            for i in 0..<100 {
                radio.onHeard?(ParsedPacket(version: 0, eidHex: "eid\(i)", payload: Data([1])), -60, Date())
            }
        }
        Thread.sleep(forTimeInterval: 0.3)
        queue.sync {}
        XCTAssertGreaterThanOrEqual(calls, 1, "the storm's net change must arrive")
        XCTAssertLessThanOrEqual(calls, 3, "100 beacons must not mean 100 callbacks")
        XCTAssertEqual(EEGateway.status().pingsHeard, 100)
    }

    func testClearingListenerStopsCallbacks() {
        let queue = DispatchQueue(label: "ee.test.callbacks")
        EEGateway.callbackQueue = queue

        var calls = 0
        EEGateway.setListener { _ in calls += 1 }
        EEGateway.setListener(nil)
        EEGateway.configure(.gatewayToken(token: "ee_live_abc"))
        queue.sync {}
        XCTAssertEqual(calls, 0)
    }

    func testStatusCarriesVersionConstant() {
        XCTAssertEqual(EEGateway.version, "0.1.0")
    }
}
