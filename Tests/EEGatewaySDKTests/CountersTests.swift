import XCTest
@testable import EEGatewaySDK

final class CountersTests: XCTestCase {

    func testSnapshotReflectsIncrements() {
        let counters = Counters()
        counters.heardPacket()
        counters.heardPacket()
        counters.forwarded(3)
        counters.droppedNoFix()
        counters.scanError()

        let snap = counters.takeSnapshot()
        XCTAssertEqual(snap.heard, 2)
        XCTAssertEqual(snap.forwarded, 3)
        XCTAssertEqual(snap.droppedNoFix, 1)
        XCTAssertEqual(snap.bleScanErrors, 1)
        XCTAssertFalse(snap.isEmpty)
    }

    func testSnapshotResets() {
        let counters = Counters()
        counters.heardPacket()
        _ = counters.takeSnapshot()
        XCTAssertTrue(counters.takeSnapshot().isEmpty)
    }

    func testRestoreAddsOnTopOfNewCounts() {
        let counters = Counters()
        counters.heardPacket()
        let snap = counters.takeSnapshot()

        // Scanning continued while the POST was in flight.
        counters.heardPacket()
        counters.restore(snap)

        XCTAssertEqual(counters.takeSnapshot().heard, 2, "restore must add, not assign")
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

    func testDroppedNoEIDIsLocalOnly() {
        let counters = Counters()
        counters.droppedNoEIDFrame()
        XCTAssertTrue(counters.takeSnapshot().isEmpty, "no-eid drops have no server field (§1a)")
        XCTAssertEqual(counters.droppedNoEID, 1)
    }
}
