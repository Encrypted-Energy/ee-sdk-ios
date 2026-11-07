import Foundation

/// Heartbeat body builder (plan §1b). Pure Foundation so it unit-tests
/// without a device. All fields are optional server-side.
///
/// `worker_version` identifies this as the SDK, not the consumer app: fleet
/// gateways report `ee-sdk-ios/<version>` so the ops side can tell SDK
/// traffic from the first-party app at a glance (and the C9 kill switch can
/// be reasoned about per worker string).
///
/// Port of ee-sdk-android HeartbeatPayload.
enum HeartbeatPayload {

    static let workerVersion = "ee-sdk-ios/" + SdkVersion.string

    struct Runtime {
        var osVersion: String
        var uptimeSeconds: Int64
        var lastPacketAtMillis: Int64?
        /// "fix" | "no_fix" | "dongle_missing" (permission denied) — §1b mapping.
        var gpsStatus: String
        /// When the newest fix was captured, any age (0004+).
        var lastKnownPositionAtMillis: Int64? = nil
        /// "active" | "backgrounded" — server client_state (0005+).
        var clientState: String? = nil
        /// DeviceRollup.heartbeatRaw output — devices_seen block (0005+).
        var devicesSeen: Json.Raw? = nil
        /// "paused" while RadioGate parks the radio (0.2.0); nil otherwise
        /// (no adaptive scan policy on iOS — background scans are
        /// OS-coalesced).
        var scanMode: String? = nil
        /// Host app identifier (0.2.0 item i): Bundle.main.bundleIdentifier,
        /// so the fleet dashboard can group installs by the app they live
        /// in and ops can spot a token minted for one app running inside
        /// another. Additive optional field; the server ignores it until it
        /// grows a column.
        var hostApp: String? = nil
    }

    static func build(_ runtime: Runtime, _ deltas: Counters.Snapshot) -> String {
        var fields: [(String, Any)] = [
            ("worker_version", workerVersion),
            ("platform", "ios"),
            ("os_version", runtime.osVersion),
            ("uptime_seconds", runtime.uptimeSeconds),
            ("gps_status", runtime.gpsStatus),
            ("packets_forwarded_delta", deltas.forwarded),
            ("packets_dropped_no_fix_delta", deltas.droppedNoFix),
            ("packets_heard_delta", deltas.heard),
            ("ble_scan_errors_delta", deltas.bleScanErrors),
        ]
        if let at = runtime.lastPacketAtMillis {
            fields.append(("last_packet_at", isoUtc(at)))
        }
        if let at = runtime.lastKnownPositionAtMillis {
            fields.append(("last_known_position_at", isoUtc(at)))
        }
        if let state = runtime.clientState {
            fields.append(("status", state))
        }
        if let devices = runtime.devicesSeen {
            fields.append(("devices_seen", devices))
        }
        if let mode = runtime.scanMode {
            fields.append(("scan_mode", mode))
        }
        if let host = runtime.hostApp {
            fields.append(("host_app", host))
        }
        // No field above can hold a non-finite Double (the one Json.obj
        // throw), so the fallback is unreachable; it exists because the
        // heartbeat path must never throw into the loop.
        return (try? Json.obj(fields)) ?? "{}"
    }

    /// YYYY-MM-DDTHH:MM:SSZ UTC (§1b).
    static func isoUtc(_ millis: Int64) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return formatter.string(from: Date(timeIntervalSince1970: Double(millis) / 1000))
    }
}

extension DeviceRollup {
    /// The §1b devices_seen block as embeddable JSON. Bridges the verbatim
    /// app extraction (`heartbeatValue` returns a dictionary) to the
    /// ordered-writer world; key order inside the block is unspecified,
    /// which the server doesn't care about.
    mutating func heartbeatRaw(now: Date = Date()) -> Json.Raw? {
        // 0.2.0 item vii: a quiet radio never calls heard(), and
        // heartbeatValue (verbatim app extraction) only reads — so prune
        // here, or devices_seen reports rows older than the 24 h window it
        // claims. The app fixed the same class in its 0001 field patch.
        prune(now: now)
        guard let data = try? JSONSerialization.data(withJSONObject: heartbeatValue(now: now)),
              let text = String(data: data, encoding: .utf8)
        else { return nil }
        return Json.Raw(text: text)
    }
}
