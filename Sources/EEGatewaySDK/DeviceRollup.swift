import Foundation

/// Per-EID 24 h stats behind the heartbeat's devices_seen rollup (plan §1b:
/// top 50 by packet count). In the app this also fed the Devices tab; the
/// SDK keeps only the heartbeat role.
///
/// Extracted VERBATIM from gateway-ios DeviceRollup.swift (131c3f5), doc
/// comment aside. Known cross-platform delta (documented in NOTES.md): the
/// Android SDK caps by recency and clamps last-seen monotonic; this port
/// keeps the shipped iOS behavior (cap by packet count).
struct DeviceRollup {

    struct Entry {
        var packets = 0
        var lastRSSI = 0
        var lastSeenAt = Date()
    }

    static let window: TimeInterval = 24 * 3600
    static let heartbeatLimit = 50

    private(set) var entries: [String: Entry] = [:]

    mutating func heard(eid: String, rssi: Int, at: Date = Date()) {
        var e = entries[eid] ?? Entry()
        e.packets += 1
        e.lastRSSI = rssi
        e.lastSeenAt = at
        entries[eid] = e
        prune(now: at)
    }

    mutating func prune(now: Date = Date()) {
        entries = entries.filter { now.timeIntervalSince($0.value.lastSeenAt) <= Self.window }
    }

    /// §1b devices_seen payload. Timestamps YYYY-MM-DDTHH:MM:SSZ UTC.
    func heartbeatValue(now: Date = Date()) -> [String: Any] {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        let top = entries.sorted { $0.value.packets > $1.value.packets }
            .prefix(Self.heartbeatLimit)
            .map { eid, e -> [String: Any] in
                ["eid": eid, "packets": e.packets, "last_rssi": e.lastRSSI,
                 "last_seen_at": fmt.string(from: e.lastSeenAt)]
            }
        return ["as_of": fmt.string(from: now), "window_hours": 24, "devices": Array(top)]
    }
}
