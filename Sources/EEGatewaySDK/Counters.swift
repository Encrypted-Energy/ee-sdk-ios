import Foundation

/// Heartbeat delta counters with the Pi worker's snapshot/reset/restore
/// semantics (plan §1b): counters are snapshotted and reset atomically before
/// the POST; on a transient failure the snapshot is restored so deltas are
/// never lost; on 401/other-4xx the snapshot is dropped.
///
/// ADAPTED from gateway-ios Counters.swift (131c3f5): the app made this an
/// actor, which would force the engine's scan callback to spawn a Task per
/// heard advertisement (beacon-dense streets = task storms). A lock is the
/// Android SDK's shape (@Synchronized) and keeps the hot path synchronous.
/// The surface and semantics are unchanged.
final class Counters {

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

    private let lock = NSLock()
    private var current = Snapshot()
    /// Local-only: no-eid drops have no server field (plan §1a). Surfaced in
    /// diagnostics, never sent.
    private var _droppedNoEID = 0

    var droppedNoEID: Int {
        lock.lock(); defer { lock.unlock() }
        return _droppedNoEID
    }

    func heardPacket() {
        lock.lock(); defer { lock.unlock() }
        current.heard += 1
    }

    func forwarded(_ n: Int) {
        lock.lock(); defer { lock.unlock() }
        current.forwarded += n
    }

    func droppedNoFix() {
        lock.lock(); defer { lock.unlock() }
        current.droppedNoFix += 1
    }

    func scanError() {
        lock.lock(); defer { lock.unlock() }
        current.bleScanErrors += 1
    }

    func droppedNoEIDFrame() {
        lock.lock(); defer { lock.unlock() }
        _droppedNoEID += 1
    }

    /// Atomically take the current deltas and zero them. Call immediately
    /// before building the heartbeat body.
    func takeSnapshot() -> Snapshot {
        lock.lock(); defer { lock.unlock() }
        let snap = current
        current = Snapshot()
        return snap
    }

    /// Put a snapshot's deltas back after a transient heartbeat failure.
    /// Adds rather than assigns: scanning continued while the POST was in
    /// flight, so `current` may already be non-zero.
    func restore(_ snap: Snapshot) {
        lock.lock(); defer { lock.unlock() }
        current.heard += snap.heard
        current.forwarded += snap.forwarded
        current.droppedNoFix += snap.droppedNoFix
        current.bleScanErrors += snap.bleScanErrors
    }
}
