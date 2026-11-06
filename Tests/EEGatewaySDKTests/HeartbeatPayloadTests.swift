import XCTest
@testable import EEGatewaySDK

final class HeartbeatPayloadTests: XCTestCase {

    private let runtime = HeartbeatPayload.Runtime(
        osVersion: "iOS 19.1.2",
        uptimeSeconds: 3600,
        lastPacketAtMillis: nil,
        gpsStatus: "no_fix"
    )
    private var deltas: Counters.Snapshot {
        var snap = Counters.Snapshot()
        snap.heard = 14
        snap.forwarded = 12
        return snap
    }

    private func with(_ mutate: (inout HeartbeatPayload.Runtime) -> Void) -> HeartbeatPayload.Runtime {
        var r = runtime
        mutate(&r)
        return r
    }

    func testContainsContractFields() {
        let json = HeartbeatPayload.build(runtime, deltas)
        XCTAssertTrue(json.contains("\"worker_version\":\"ee-sdk-ios/"))
        XCTAssertTrue(json.contains("\"platform\":\"ios\""))
        XCTAssertTrue(json.contains("\"os_version\":\"iOS 19.1.2\""))
        XCTAssertTrue(json.contains("\"uptime_seconds\":3600"))
        XCTAssertTrue(json.contains("\"gps_status\":\"no_fix\""))
        XCTAssertTrue(json.contains("\"packets_heard_delta\":14"))
        XCTAssertTrue(json.contains("\"packets_forwarded_delta\":12"))
        XCTAssertTrue(json.contains("\"packets_dropped_no_fix_delta\":0"))
        XCTAssertTrue(json.contains("\"ble_scan_errors_delta\":0"))
    }

    func testWorkerVersionMatchesSdkVersionConstant() {
        XCTAssertEqual(HeartbeatPayload.workerVersion, "ee-sdk-ios/\(EEGateway.version)")
    }

    func testOmitsLastPacketAtWhenNeverHeard() {
        XCTAssertFalse(HeartbeatPayload.build(runtime, deltas).contains("last_packet_at"))
    }

    func testFormatsLastPacketAtAsUtcIso() {
        let json = HeartbeatPayload.build(with { $0.lastPacketAtMillis = 1_783_780_342_000 }, deltas)
        XCTAssertNotNil(
            json.range(of: "\"last_packet_at\":\"\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z\"", options: .regularExpression),
            json
        )
    }

    func testOmitsLastKnownPositionAtWhenNoFixEver() {
        XCTAssertFalse(HeartbeatPayload.build(runtime, deltas).contains("last_known_position_at"))
    }

    func testIncludesLastKnownPositionAtWhenPresent() {
        let json = HeartbeatPayload.build(with { $0.lastKnownPositionAtMillis = 1_783_780_342_000 }, deltas)
        XCTAssertTrue(json.contains("\"last_known_position_at\":\"2026-07-11T14:32:22Z\""), json)
    }

    func testOmitsClientStateWhenAbsent() {
        // Absence means "no change" server-side; never send an empty status.
        XCTAssertFalse(HeartbeatPayload.build(runtime, deltas).contains("\"status\""))
    }

    func testIncludesClientStateWhenPresent() {
        let json = HeartbeatPayload.build(with { $0.clientState = "active" }, deltas)
        XCTAssertTrue(json.contains("\"status\":\"active\""), json)
    }

    func testIncludesDevicesSeenBlockVerbatim() {
        var rollup = DeviceRollup()
        rollup.heard(eid: "5f982837", rssi: -54, at: Date(timeIntervalSince1970: 1_783_780_342))
        let block = rollup.heartbeatRaw(now: Date(timeIntervalSince1970: 1_783_780_343))!
        let json = HeartbeatPayload.build(with { $0.devicesSeen = block }, deltas)
        XCTAssertTrue(json.contains("\"devices_seen\":" + block.text), json)
    }

    func testOmitsDevicesSeenWhenAbsent() {
        XCTAssertFalse(HeartbeatPayload.build(runtime, deltas).contains("devices_seen"))
    }

    func testOmitsScanModeWhenAbsent() {
        XCTAssertFalse(HeartbeatPayload.build(runtime, deltas).contains("scan_mode"))
    }

    func testIncludesScanModeWhenPresent() {
        let json = HeartbeatPayload.build(with { $0.scanMode = "reduced" }, deltas)
        XCTAssertTrue(json.contains("\"scan_mode\":\"reduced\""), json)
    }

    func testIsoUtcIsStable() {
        // 1783780342 unix seconds is the plan §1a fixture timestamp.
        XCTAssertEqual(HeartbeatPayload.isoUtc(1_783_780_342_000), "2026-07-11T14:32:22Z")
    }

    func testJsonEscapesQuotes() throws {
        XCTAssertEqual(try Json.obj([("a", "x\"y")]), "{\"a\":\"x\\\"y\"}")
    }
}
