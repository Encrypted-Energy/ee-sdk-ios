import XCTest
@testable import EEGatewaySDK

/// The dormancy gate, packet path, and runtime composition — exercised for
/// real on Linux through the seams (the Android Engine only ever got
/// stub-compiled; this suite is iOS-arc-only coverage).
final class EngineTests: XCTestCase {

    private var radio = FakeRadio()
    private var location = FakeLocation()
    private var granted = true
    private var lowPowerFlag = false
    private var queue = PacketQueue()

    override func setUp() {
        super.setUp()
        radio = FakeRadio()
        location = FakeLocation()
        granted = true
        lowPowerFlag = false
        queue = PacketQueue()
    }

    private func makeEngine(
        pollInterval: TimeInterval = 0.05,
        gateInterval: TimeInterval = 0.05,
        hostApp: String? = nil
    ) -> Engine {
        Engine(
            client: EEClient(tokenProvider: { "ee_live_t" }, transport: { _ in nil }),
            radio: radio,
            location: location,
            permissionsGranted: { self.granted },
            queueFileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("engine-test-\(UUID().uuidString).eeq"),
            osVersion: "iOS 19.1.2",
            mint: { _ in .rejected(reason: "test: no network") },
            queue: queue,
            pollInterval: pollInterval,
            lowPower: { self.lowPowerFlag },
            hostApp: hostApp,
            gateInterval: gateInterval,
            onChanged: {}
        )
    }

    private func drain(_ engine: Engine) {
        engine.workQueue.sync {}
    }

    private func fix(ageSeconds: Int64 = 0, at nowMillis: Int64) -> LocationFix {
        LocationFix(latitude: 40.72, longitude: -74.04, accuracyM: 12.0,
                    capturedAtMillis: nowMillis - ageSeconds * 1000)
    }

    private func frame(eid: String?) -> ParsedPacket {
        ParsedPacket(version: 0, eidHex: eid, payload: Data([0x03, 0xAA, 0x01]))
    }

    // MARK: Dormancy gate

    func testStartWithGrantsRunsThePipeline() {
        let engine = makeEngine()
        engine.start()
        drain(engine)
        XCTAssertTrue(engine.scanning)
        XCTAssertEqual(radio.startCalls, 1)
        XCTAssertEqual(location.startCalls, 1)
        engine.stop()
        drain(engine)
    }

    func testStartWithoutGrantsIsDormantNotDead() {
        granted = false
        let engine = makeEngine(pollInterval: 60)   // poll never fires in-test
        engine.start()
        drain(engine)
        XCTAssertTrue(engine.started)
        XCTAssertFalse(engine.scanning, "radio must stay untouched without grants")
        XCTAssertEqual(radio.startCalls, 0)
        engine.stop()
        drain(engine)
    }

    func testDormantEngineAutoAdvancesWhenGrantsAppear() {
        granted = false
        let engine = makeEngine(pollInterval: 0.05)
        engine.start()
        drain(engine)
        XCTAssertFalse(engine.scanning)

        granted = true
        let advanced = expectation(description: "pipeline started by the poll")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
            if engine.scanning { advanced.fulfill() }
        }
        wait(for: [advanced], timeout: 2)
        XCTAssertEqual(radio.startCalls, 1)
        engine.stop()
        drain(engine)
    }

    func testMidRunRevocationTearsDownAndReturnsToDormant() {
        let engine = makeEngine(pollInterval: 60)
        engine.start()
        drain(engine)
        XCTAssertTrue(engine.scanning)

        granted = false
        engine.workQueue.sync { radio.onState?(.unauthorized) }
        XCTAssertFalse(engine.scanning, "unauthorized radio must tear the pipeline down")
        XCTAssertEqual(radio.stopCalls, 1)
        XCTAssertEqual(location.stopCalls, 1)
        XCTAssertTrue(engine.started, "still started — dormant, not stopped")
        engine.stop()
        drain(engine)
    }

    func testSynchronousRevocationInsideStartIsHandled() {
        // Grant revoked between the permission check and the radio call:
        // start() reports unauthorized synchronously and the pipeline must
        // end torn down, not half-up.
        radio.stateOnStart = .unauthorized
        let engine = makeEngine(pollInterval: 60)
        engine.start()
        drain(engine)
        XCTAssertFalse(engine.scanning)
        XCTAssertEqual(location.stopCalls, 1, "location must not stay up over a dead radio")
        engine.stop()
        drain(engine)
    }

    func testStopStopsPipelineAndIsIdempotent() {
        let engine = makeEngine()
        engine.start()
        drain(engine)
        engine.stop()
        drain(engine)
        XCTAssertFalse(engine.started)
        XCTAssertFalse(engine.scanning)
        XCTAssertEqual(radio.stopCalls, 1)
        engine.stop()
        drain(engine)
        XCTAssertEqual(radio.stopCalls, 1)
    }

    // MARK: Packet path

    func testHeardFrameCountsAndRollsUp() {
        let engine = makeEngine()
        engine.start()
        drain(engine)
        engine.workQueue.sync { radio.onHeard?(frame(eid: "98b628e"), -60, Date()) }
        XCTAssertEqual(engine.pingsHeard, 1)
        XCTAssertEqual(engine.counters.takeSnapshot().heard, 1)
        engine.stop()
        drain(engine)
    }

    func testPacketWithFreshFixIsStampedAndEnqueued() {
        let engine = makeEngine()
        engine.start()
        drain(engine)
        let heardAt = Date()
        let nowMillis = Int64(heardAt.timeIntervalSince1970 * 1000)
        location.fix = fix(ageSeconds: 10, at: nowMillis)

        engine.workQueue.sync { radio.onPacket?(frame(eid: "98b628e"), -60, heardAt) }
        XCTAssertEqual(engine.queueDepth(), 1)
        let packet = queue.snapshot()[0]
        XCTAssertEqual(packet.eidHex, "98b628e")
        XCTAssertEqual(packet.payloadB64, Data([0x03, 0xAA, 0x01]).base64EncodedString())
        XCTAssertEqual(packet.rssi, -60)
        XCTAssertEqual(packet.timestampSeconds, nowMillis / 1000)
        XCTAssertEqual(packet.positionAtSeconds, location.fix!.capturedAtMillis / 1000)
        XCTAssertEqual(packet.accuracyM, 12.0)
        engine.stop()
        drain(engine)
    }

    func testPacketWithoutFreshFixDropsNoFix() {
        let engine = makeEngine()
        engine.start()
        drain(engine)
        let heardAt = Date()
        location.fix = fix(ageSeconds: 30, at: Int64(heardAt.timeIntervalSince1970 * 1000))   // stale

        engine.workQueue.sync { radio.onPacket?(frame(eid: "98b628e"), -60, heardAt) }
        XCTAssertEqual(engine.queueDepth(), 0, "stale coords must never be stamped (7/31)")
        XCTAssertEqual(engine.counters.takeSnapshot().droppedNoFix, 1)
        engine.stop()
        drain(engine)
    }

    func testEidlessFrameNeverReachesTheQueue() {
        let engine = makeEngine()
        engine.start()
        drain(engine)
        location.fix = fix(at: Int64(Date().timeIntervalSince1970 * 1000))
        engine.workQueue.sync {
            radio.onHeard?(frame(eid: nil), -60, Date())
            radio.onPacket?(frame(eid: nil), -60, Date())
        }
        XCTAssertEqual(engine.queueDepth(), 0)
        XCTAssertEqual(engine.counters.droppedNoEID, 1)
        engine.stop()
        drain(engine)
    }

    // MARK: Persistence restore

    func testRestoresPersistedQueueOffTheCallerThread() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("engine-restore-\(UUID().uuidString).eeq")
        let persisted = UploadPacket(
            eidHex: "5f982837", payloadB64: "AQID", rssi: -50,
            timestampSeconds: 1_785_545_352, latitude: 40.5, longitude: -74.25,
            positionAtSeconds: 1_785_545_340, accuracyM: 14.0
        )
        QueueStore(fileURL: url).persistNow([persisted])

        let engine = Engine(
            client: EEClient(tokenProvider: { nil }, transport: { _ in nil }),
            radio: radio, location: location,
            permissionsGranted: { true },
            queueFileURL: url, osVersion: "iOS 19.1.2",
            mint: { _ in .rejected(reason: "test: no network") },
            queue: queue, pollInterval: 60, onChanged: {}
        )
        drain(engine)   // restore runs on workQueue
        XCTAssertEqual(engine.queueDepth(), 1)
        XCTAssertEqual(queue.snapshot()[0], persisted)
    }

    // MARK: Heartbeat runtime composition

    func testRuntimeInfoWhileDormantReportsDongleMissingAndBackgrounded() {
        granted = false
        let engine = makeEngine(pollInterval: 60)
        engine.start()
        drain(engine)
        let runtime = engine.runtimeInfo()
        XCTAssertEqual(runtime.gpsStatus, "dongle_missing")
        XCTAssertEqual(runtime.clientState, "backgrounded")
        XCTAssertEqual(runtime.osVersion, "iOS 19.1.2")
        XCTAssertNil(runtime.scanMode)
        engine.stop()
        drain(engine)
    }

    func testRuntimeInfoWhileScanningReportsFixAndActive() {
        let engine = makeEngine()
        engine.start()
        drain(engine)
        location.fix = fix(at: Int64(Date().timeIntervalSince1970 * 1000))
        let runtime = engine.runtimeInfo()
        XCTAssertEqual(runtime.gpsStatus, "fix")
        XCTAssertEqual(runtime.clientState, "active")
        XCTAssertEqual(runtime.lastKnownPositionAtMillis, location.fix?.capturedAtMillis)
        engine.stop()
        drain(engine)
    }

    func testRuntimeInfoWithGrantsButNoFixReportsNoFix() {
        let engine = makeEngine()
        engine.start()
        drain(engine)
        XCTAssertEqual(engine.runtimeInfo().gpsStatus, "no_fix")
        engine.stop()
        drain(engine)
    }

    // MARK: RadioGate wiring (0.2.0 — the policy itself is RadioGateTests)

    func testStartInLowPowerParksRadioFromBirth() {
        lowPowerFlag = true
        let engine = makeEngine()
        engine.start()
        drain(engine)
        XCTAssertEqual(radio.startCalls, 0, "radio must not start under LPM")
        XCTAssertEqual(location.startCalls, 1, "location is the recovery signal")
        XCTAssertTrue(engine.scanning)
        XCTAssertTrue(engine.radioParked)
        let runtime = engine.runtimeInfo()
        XCTAssertEqual(runtime.scanMode, "paused")
        XCTAssertEqual(runtime.clientState, "backgrounded")
        engine.stop()
        drain(engine)
    }

    func testLpmParksMidRunAndLiftingResumes() {
        let engine = makeEngine(gateInterval: 0.05)
        engine.start()
        drain(engine)
        XCTAssertEqual(radio.startCalls, 1)
        lowPowerFlag = true
        Thread.sleep(forTimeInterval: 0.15)
        drain(engine)
        XCTAssertEqual(radio.stopCalls, 1, "gate tick must park the radio")
        XCTAssertTrue(engine.radioParked)
        lowPowerFlag = false
        Thread.sleep(forTimeInterval: 0.15)
        drain(engine)
        XCTAssertEqual(radio.startCalls, 2, "lifting LPM must resume")
        XCTAssertFalse(engine.radioParked)
        engine.stop()
        drain(engine)
    }

    func testStopWhileParkedDoesNotDoubleStopTheRadio() {
        lowPowerFlag = true
        let engine = makeEngine()
        engine.start()
        drain(engine)
        XCTAssertTrue(engine.radioParked)
        engine.stop()
        drain(engine)
        XCTAssertEqual(radio.stopCalls, 0, "radio never started; nothing to stop")
        XCTAssertEqual(location.stopCalls, 1)
        XCTAssertFalse(engine.radioParked)
    }

    func testHostAppAndDefaultScanModeReachRuntime() {
        let engine = makeEngine(hostApp: "com.example.host")
        engine.start()
        drain(engine)
        let runtime = engine.runtimeInfo()
        XCTAssertEqual(runtime.hostApp, "com.example.host")
        XCTAssertNil(runtime.scanMode, "no adaptive policy: scan_mode omitted unless parked")
        XCTAssertEqual(runtime.clientState, "active")
        engine.stop()
        drain(engine)
    }
}
