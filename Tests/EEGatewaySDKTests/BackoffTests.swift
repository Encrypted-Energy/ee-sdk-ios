import XCTest
@testable import EEGatewaySDK

/// Deterministic stand-in for the RNG seam (Java's seeded Random in the
/// Android tests). SplitMix64 — quality is irrelevant, determinism isn't.
private final class SeededRandom {
    private var state: UInt64
    init(_ seed: UInt64) { state = seed }
    func next() -> Double {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z ^= z >> 31
        return Double(z >> 11) / Double(UInt64(1) << 53)
    }
}

final class BackoffTests: XCTestCase {

    /// Equal jitter: every delay lands in [ceiling/2, ceiling].
    func testDelaysStayInsideTheJitterWindow() {
        let rng = SeededRandom(42)
        let b = Backoff(baseMillis: 1_000, capMillis: 60_000, random: { rng.next() })
        var ceiling: Int64 = 1_000
        for _ in 0..<10 {
            let d = b.nextDelayMillis()
            XCTAssertGreaterThanOrEqual(d, ceiling / 2, "delay \(d) below half of \(ceiling)")
            XCTAssertLessThanOrEqual(d, ceiling, "delay \(d) above ceiling \(ceiling)")
            ceiling = min(ceiling * 2, 60_000)
        }
    }

    func testCeilingIsCappedForever() {
        let rng = SeededRandom(7)
        let b = Backoff(baseMillis: 1_000, capMillis: 8_000, random: { rng.next() })
        // base 1s reaches the 8s cap on the 4th attempt; everything later
        // stays in [4s, 8s] — including attempts far past the exponent clamp.
        for _ in 0..<3 { _ = b.nextDelayMillis() }
        for _ in 0..<50 {
            let d = b.nextDelayMillis()
            XCTAssertTrue((4_000...8_000).contains(d), "delay \(d) outside capped window")
        }
    }

    func testResetStartsTheLadderOver() {
        let rng = SeededRandom(1)
        let b = Backoff(baseMillis: 2_000, capMillis: 600_000, random: { rng.next() })
        for _ in 0..<5 { _ = b.nextDelayMillis() }
        b.reset()
        let d = b.nextDelayMillis()
        XCTAssertTrue((1_000...2_000).contains(d), "post-reset delay \(d) not back at the base window")
    }

    func testDefaultsMatchTheMintCapStory() {
        XCTAssertEqual(Backoff.defaultBaseMillis, 2_000)
        XCTAssertEqual(Backoff.defaultCapMillis, 600_000)
    }

    func testJitterActuallyVaries() {
        let rng = SeededRandom(3)
        let b = Backoff(baseMillis: 600_000, capMillis: 600_000, random: { rng.next() })
        var seen = Set<Int64>()
        for _ in 0..<8 { seen.insert(b.nextDelayMillis()) }
        XCTAssertGreaterThanOrEqual(seen.count, 6, "jitter produced \(seen.count) distinct delays")
    }
}
