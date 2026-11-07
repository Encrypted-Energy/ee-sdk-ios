import Foundation

/// Radio park policy (0.2.0 items ii+iii): decides whether the BLE scanner
/// should run at all. Pure, clock-injected, Linux-tested; the Engine owns
/// the tick cadence and the inputs.
///
/// Two independent reasons to park, in priority order:
///
///  - **Low Power Mode** (item ii): the iOS precedent is the shipped app's
///    LPM pause, so the SDK keys on the same signal instead of a raw
///    battery percent (Android uses 20%/25% hysteresis; LPM is already a
///    debounced user intent and needs none).
///  - **Dead fix stream** (item iii, new fleet-wide): after
///    `noFixPauseMillis` without a fresh fix every heard packet is a
///    guaranteed drop (the 25 s stamp gate), so the radio burns battery
///    for nothing. The location source MUST keep running while parked —
///    it is the recovery signal.
///
/// The no-fix clock arms from `reset` (pipeline start), so a phone that
/// never gets a first fix still scans for the grace window instead of
/// parking at birth.
final class RadioGate {

    enum Verdict: Equatable {
        case scan
        case pausedLowPower
        case pausedNoFix
    }

    static let noFixPauseMillis: Int64 = 5 * 60_000

    private var lowPower = false
    private var lastFixMillis: Int64?
    private var armedMillis: Int64 = 0

    /// Pipeline start: arm the no-fix grace window, keep power state.
    func reset(nowMillis: Int64) {
        armedMillis = nowMillis
        lastFixMillis = nil
    }

    func onLowPower(_ enabled: Bool) {
        lowPower = enabled
    }

    func onFix(nowMillis: Int64) {
        lastFixMillis = nowMillis
    }

    func verdict(nowMillis: Int64) -> Verdict {
        if lowPower { return .pausedLowPower }
        let anchor = lastFixMillis ?? armedMillis
        if nowMillis - anchor > Self.noFixPauseMillis { return .pausedNoFix }
        return .scan
    }
}
