import XCTest
@testable import EEGatewaySDK

final class DeviceRollupTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    func testRecordsPerEidStats() {
        var rollup = DeviceRollup()
        rollup.heard(eid: "2a", rssi: -70, at: t0)
        rollup.heard(eid: "2a", rssi: -60, at: t0.addingTimeInterval(10))
        rollup.heard(eid: "efcacfae", rssi: -80, at: t0)

        XCTAssertEqual(rollup.entries.count, 2)
        XCTAssertEqual(rollup.entries["2a"]?.packets, 2)
        XCTAssertEqual(rollup.entries["2a"]?.lastRSSI, -60)
        XCTAssertEqual(rollup.entries["2a"]?.lastSeenAt, t0.addingTimeInterval(10))
    }

    func testEmptyRollupIsValidHeartbeatBlock() {
        let value = DeviceRollup().heartbeatValue(now: t0)
        XCTAssertEqual(value["window_hours"] as? Int, 24)
        XCTAssertEqual((value["devices"] as? [[String: Any]])?.count, 0)
        XCTAssertEqual(value["as_of"] as? String, "2023-11-14T22:13:20Z")
    }

    func testPrunesBeyondWindow() {
        var rollup = DeviceRollup()
        rollup.heard(eid: "old", rssi: -70, at: t0)
        rollup.heard(eid: "fresh", rssi: -70, at: t0.addingTimeInterval(DeviceRollup.window - 1))
        rollup.prune(now: t0.addingTimeInterval(DeviceRollup.window + 1))

        XCTAssertNil(rollup.entries["old"])
        XCTAssertNotNil(rollup.entries["fresh"])
    }

    func testHeartbeatCapsAtTopFiftyByPacketCount() {
        var rollup = DeviceRollup()
        for i in 0..<60 {
            // eid "d<i>" heard i+1 times: d59 is busiest, d0..d9 fall off.
            for _ in 0...i {
                rollup.heard(eid: "d\(i)", rssi: -70, at: t0)
            }
        }
        let devices = rollup.heartbeatValue(now: t0)["devices"] as! [[String: Any]]
        XCTAssertEqual(devices.count, DeviceRollup.heartbeatLimit)
        XCTAssertEqual(devices.first?["eid"] as? String, "d59")
        XCTAssertEqual(devices.first?["packets"] as? Int, 60)
        let kept = Set(devices.map { $0["eid"] as! String })
        XCTAssertFalse(kept.contains("d9"), "lowest packet counts fall off the top-50")
        XCTAssertTrue(kept.contains("d10"))
    }

    func testHeartbeatEntryShape() {
        var rollup = DeviceRollup()
        rollup.heard(eid: "2a", rssi: -63, at: t0)
        let devices = rollup.heartbeatValue(now: t0)["devices"] as! [[String: Any]]
        XCTAssertEqual(devices.count, 1)
        let entry = devices[0]
        XCTAssertEqual(entry["eid"] as? String, "2a")
        XCTAssertEqual(entry["packets"] as? Int, 1)
        XCTAssertEqual(entry["last_rssi"] as? Int, -63)
        XCTAssertEqual(entry["last_seen_at"] as? String, "2023-11-14T22:13:20Z")
    }
}
