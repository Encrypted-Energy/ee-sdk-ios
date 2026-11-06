/// Exponential backoff with equal jitter, for retrying transient outcomes
/// (self-mint 503/429 against the 300/hr global cap, dead-network verify).
/// The caller owns the clock and the sleep — this only computes delays, so
/// the policy unit-tests deterministically with an injected `random`.
///
/// Delay for attempt n is uniform in [cap/2, cap] where
/// cap = min(base * 2^n, capMillis) — the "equal jitter" scheme: half the
/// ceiling is guaranteed spacing, half is randomized so a fleet of phones
/// that all failed together (one 503 from the mint cap) doesn't retry
/// together.
///
/// Port of ee-sdk-android Backoff; the Java Random seam becomes a
/// `() -> Double` closure. Not thread-safe by design: each retry loop owns
/// one instance.
final class Backoff {

    /// First retry ~2 s — polite to the mint cap, invisible to a human.
    static let defaultBaseMillis: Int64 = 2_000

    /// Ceiling 10 min: a capped-out mint window clears within the hour.
    static let defaultCapMillis: Int64 = 10 * 60_000

    private static let maxExponent = 20

    private let baseMillis: Int64
    private let capMillis: Int64
    /// Uniform in [0, 1), like Java's Random.nextDouble().
    private let random: () -> Double

    private var attempt = 0

    init(
        baseMillis: Int64 = Backoff.defaultBaseMillis,
        capMillis: Int64 = Backoff.defaultCapMillis,
        random: @escaping () -> Double = { Double.random(in: 0..<1) }
    ) {
        self.baseMillis = baseMillis
        self.capMillis = capMillis
        self.random = random
    }

    /// Call after a success so the next failure starts the ladder over.
    func reset() {
        attempt = 0
    }

    /// The next delay, in millis. Advances the attempt counter.
    func nextDelayMillis() -> Int64 {
        // The exponent is clamped well before the shift can wrap.
        let exponent = min(attempt, Self.maxExponent)
        let ceiling = min(baseMillis << exponent, capMillis)
        attempt += 1
        let half = ceiling / 2
        // random() in [0,1): delay in [half, ceiling], never past the cap.
        return half + Int64(random() * Double(half))
    }
}
