/// Forward gate: at most one packet per EID per window (plan §2). Every heard
/// advertisement still counts toward heard tallies; this only gates what is
/// eligible for upload.
///
/// Port of ee-sdk-android EidThrottle. Not thread-safe by design: the engine
/// owns one instance on the scan callback path.
///
/// Bounded (0.2.0 item iv): identifiers rotate at least daily, so a phone
/// parked in a dense corridor accumulates unique EIDs without limit. Swift
/// has no access-ordered map, so the bound is a two-generation scheme: a
/// `current` and a `previous` dictionary of `maxEntries / 2` each. Inserts
/// and refreshes go to `current`; when it fills, it becomes `previous` and
/// the old `previous` (the coldest half) is dropped wholesale. Total tracked
/// EIDs never exceed `maxEntries`; any EID seen within the last generation
/// survives rotation, so hot devices are never the victim. Evicting a cold
/// EID at worst re-forwards one packet early — harmless, the server dedupes
/// bounties per day.
final class EidThrottle {

    static let maxEntries = 4_096

    private let windowMillis: Int64
    private let generationCapacity: Int
    private var current: [String: Int64] = [:]
    private var previous: [String: Int64] = [:]

    init(windowMillis: Int64, maxEntries: Int = EidThrottle.maxEntries) {
        self.windowMillis = windowMillis
        self.generationCapacity = max(1, maxEntries / 2)
    }

    func shouldForward(eid: String, nowMillis: Int64) -> Bool {
        let last = current[eid] ?? previous[eid]
        if let last, nowMillis - last < windowMillis {
            // Suppressed, but the sighting refreshes recency: promote into
            // the current generation so a hot device never rotates out.
            touch(eid: eid, value: last)
            return false
        }
        touch(eid: eid, value: nowMillis)
        return true
    }

    private func touch(eid: String, value: Int64) {
        previous.removeValue(forKey: eid)
        if current[eid] == nil && current.count >= generationCapacity {
            previous = current
            current = [:]
        }
        current[eid] = value
    }
}
