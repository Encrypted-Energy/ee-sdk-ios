import Foundation

/// Heartbeat delta counters with the Pi worker's snapshot/reset/restore
/// semantics (plan §1b): counters are snapshotted and reset atomically before
/// the POST; on a transient failure the snapshot is restored so deltas are
/// never lost; on 401/other-4xx the snapshot is dropped.
///
/// Extracted VERBATIM from gateway-ios Counters.swift (131c3f5).
actor Counters {

    struct Snapshot {
        var heard = 0
        var forwarded = 0
        var droppedNoFix = 0
        var bleScanErrors = 0

        var isEmpty: Bool { heard == 0 && forwarded == 0 && droppedNoFix == 0 && bleScanErrors == 0 }

        var heartbeatFields: [String: Int] {
            [
                "packets_heard_delta": heard,
                "packets_forwarded_delta": forwarded,
                "packets_dropped_no_fix_delta": droppedNoFix,
                "ble_scan_errors_delta": bleScanErrors,
            ]
        }
    }

    private var current = Snapshot()
    /// Local-only: no-eid drops have no server field (plan §1a). Surfaced in
    /// Diagnostics, never sent.
    private(set) var droppedNoEID = 0

    func heardPacket()   { current.heard += 1 }
    func forwarded(_ n: Int) { current.forwarded += n }
    func droppedNoFix()  { current.droppedNoFix += 1 }
    func scanError()     { current.bleScanErrors += 1 }
    func droppedNoEIDFrame() { droppedNoEID += 1 }

    /// Atomically take the current deltas and zero them. Call immediately
    /// before building the heartbeat body.
    func takeSnapshot() -> Snapshot {
        let snap = current
        current = Snapshot()
        return snap
    }

    /// Put a snapshot's deltas back after a transient heartbeat failure.
    /// Adds rather than assigns: scanning continued while the POST was in
    /// flight, so `current` may already be non-zero.
    func restore(_ snap: Snapshot) {
        current.heard += snap.heard
        current.forwarded += snap.forwarded
        current.droppedNoFix += snap.droppedNoFix
        current.bleScanErrors += snap.bleScanErrors
    }
}
