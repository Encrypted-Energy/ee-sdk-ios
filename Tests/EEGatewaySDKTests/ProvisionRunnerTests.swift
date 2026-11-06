import XCTest
@testable import EEGatewaySDK

/// Retry policy around TokenProvision: verdicts return, transients sleep out
/// Backoff, rejection parks, stop abandons. Ported 1:1 from the Android
/// suite; "interrupted sleep" is a cancelled Task here (sleep → false).
final class ProvisionRunnerTests: XCTestCase {

    private final class Seeded {
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

    private func seededBackoff() -> Backoff {
        let rng = Seeded(42)
        return Backoff(random: { rng.next() })
    }

    func testProvisionedFirstTryNeverSleeps() async {
        var slept = false
        let result = await ProvisionRunner(
            attempt: { .provisioned },
            backoff: seededBackoff(),
            sleep: { _ in slept = true; return true }
        ).run(isActive: { true })
        XCTAssertEqual(result, .provisioned)
        XCTAssertFalse(slept)
    }

    func testRejectedParksImmediately() async {
        var attempts = 0
        let result = await ProvisionRunner(
            attempt: { attempts += 1; return .rejected },
            backoff: seededBackoff(),
            sleep: { _ in true }
        ).run(isActive: { true })
        XCTAssertEqual(result, .rejected)
        XCTAssertEqual(attempts, 1)
    }

    func testRetriesThroughBackoffThenSucceeds() async {
        var outcomes: [ProvisionRunner.Outcome] = [.retry, .retry, .provisioned]
        var delays: [Int64] = []
        let result = await ProvisionRunner(
            attempt: { outcomes.removeFirst() },
            backoff: seededBackoff(),
            sleep: { delays.append($0); return true }
        ).run(isActive: { true })
        XCTAssertEqual(result, .provisioned)
        XCTAssertEqual(delays.count, 2)
        // Equal jitter off the default 2 s base: first delay in [1s, 2s],
        // second in [2s, 4s].
        XCTAssertTrue((1_000...2_000).contains(delays[0]), "\(delays)")
        XCTAssertTrue((2_000...4_000).contains(delays[1]), "\(delays)")
    }

    func testStopsWhenNoLongerActive() async {
        var attempts = 0
        let result = await ProvisionRunner(
            attempt: { attempts += 1; return .retry },
            backoff: seededBackoff(),
            sleep: { _ in true }
        ).run(isActive: { attempts < 3 })
        XCTAssertEqual(result, .abandoned)
        XCTAssertEqual(attempts, 3)
    }

    func testCancelledSleepAbandons() async {
        let result = await ProvisionRunner(
            attempt: { .retry },
            backoff: seededBackoff(),
            sleep: { _ in false }   // Task cancelled mid-sleep
        ).run(isActive: { true })
        XCTAssertEqual(result, .abandoned)
    }

    func testInactiveBeforeFirstAttemptAbandonsWithoutAttempting() async {
        var attempts = 0
        let result = await ProvisionRunner(
            attempt: { attempts += 1; return .provisioned },
            backoff: seededBackoff(),
            sleep: { _ in true }
        ).run(isActive: { false })
        XCTAssertEqual(result, .abandoned)
        XCTAssertEqual(attempts, 0)
    }
}
