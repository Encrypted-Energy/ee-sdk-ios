import XCTest
@testable import EEGatewaySDK

final class CountersTests: XCTestCase {

    func testSnapshotReflectsIncrements() async {
        let counters = Counters()
        await counters.heardPacket()
        await counters.heardPacket()
        await counters.forwarded(3)
        await counters.droppedNoFix()
        await counters.scanError()

        let snap = await counters.takeSnapshot()
        XCTAssertEqual(snap.heard, 2)
        XCTAssertEqual(snap.forwarded, 3)
        XCTAssertEqual(snap.droppedNoFix, 1)
        XCTAssertEqual(snap.bleScanErrors, 1)
        XCTAssertFalse(snap.isEmpty)
    }

    func testSnapshotResets() async {
        let counters = Counters()
        await counters.heardPacket()
        _ = await counters.takeSnapshot()

        let second = await counters.takeSnapshot()
        XCTAssertTrue(second.isEmpty)
    }

    func testRestoreAddsOnTopOfNewCounts() async {
        let counters = Counters()
        await counters.heardPacket()
        let snap = await counters.takeSnapshot()

        // Scanning continued while the POST was in flight.
        await counters.heardPacket()
        await counters.restore(snap)

        let merged = await counters.takeSnapshot()
        XCTAssertEqual(merged.heard, 2, "restore must add, not assign")
    }

    func testHeartbeatFieldKeysMatchWireFormat() {
        var snap = Counters.Snapshot()
        snap.heard = 5
        snap.forwarded = 4
        snap.droppedNoFix = 3
        snap.bleScanErrors = 2
        XCTAssertEqual(snap.heartbeatFields, [
            "packets_heard_delta": 5,
            "packets_forwarded_delta": 4,
            "packets_dropped_no_fix_delta": 3,
            "ble_scan_errors_delta": 2,
        ])
    }

    func testDroppedNoEIDIsLocalOnly() async {
        let counters = Counters()
        await counters.droppedNoEIDFrame()

        let snap = await counters.takeSnapshot()
        XCTAssertTrue(snap.isEmpty, "no-eid drops have no server field (§1a)")
        let local = await counters.droppedNoEID
        XCTAssertEqual(local, 1)
    }
}
