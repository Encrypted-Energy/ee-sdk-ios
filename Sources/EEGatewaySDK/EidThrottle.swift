/// Forward gate: at most one packet per EID per window (plan §2). Every heard
/// advertisement still counts toward heard tallies; this only gates what is
/// eligible for upload.
///
/// Port of ee-sdk-android EidThrottle. Not thread-safe by design: the engine
/// owns one instance on the scan callback path.
final class EidThrottle {

    private let windowMillis: Int64
    private var lastForwardByEid: [String: Int64] = [:]

    init(windowMillis: Int64) {
        self.windowMillis = windowMillis
    }

    func shouldForward(eid: String, nowMillis: Int64) -> Bool {
        if let last = lastForwardByEid[eid], nowMillis - last < windowMillis {
            return false
        }
        lastForwardByEid[eid] = nowMillis
        return true
    }
}
