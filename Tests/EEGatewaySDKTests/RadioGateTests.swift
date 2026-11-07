import XCTest
@testable import EEGatewaySDK

/// The 0.2.0 park policy. Invariants: Low Power Mode parks and unparks
/// immediately (it is already debounced user intent — no hysteresis), the
/// no-fix clock arms from reset (grace window at pipeline birth), any fix
/// reopens instantly, and LPM outranks no-fix.
final class RadioGateTests: XCTestCase {

    private func gate(now: Int64 = 0) -> RadioGate {
        let g = RadioGate()
        g.reset(nowMillis: now)
        return g
    }

    func testScansByDefaultInsideGraceWindow() {
        XCTAssertEqual(gate().verdict(nowMillis: 1_000), .scan)
    }

    func testLowPowerParksAndLiftingResumes() {
        let g = gate()
        g.onLowPower(true)
        XCTAssertEqual(g.verdict(nowMillis: 1_000), .pausedLowPower)
        g.onLowPower(false)
        XCTAssertEqual(g.verdict(nowMillis: 1_001), .scan)
    }

    func testParksAfterNoFixWindowFromReset() {
        let g = gate(now: 0)
        XCTAssertEqual(g.verdict(nowMillis: RadioGate.noFixPauseMillis), .scan)
        XCTAssertEqual(g.verdict(nowMillis: RadioGate.noFixPauseMillis + 1), .pausedNoFix)
    }

    func testFixReopensInstantlyAndRestartsTheClock() {
        let g = gate(now: 0)
        XCTAssertEqual(g.verdict(nowMillis: RadioGate.noFixPauseMillis + 1), .pausedNoFix)
        let fixAt = RadioGate.noFixPauseMillis + 2
        g.onFix(nowMillis: fixAt)
        XCTAssertEqual(g.verdict(nowMillis: fixAt + 1), .scan)
        // The window now runs from the fix, not from reset.
        XCTAssertEqual(g.verdict(nowMillis: fixAt + RadioGate.noFixPauseMillis), .scan)
        XCTAssertEqual(
            g.verdict(nowMillis: fixAt + RadioGate.noFixPauseMillis + 1), .pausedNoFix
        )
    }

    func testLowPowerOutranksNoFix() {
        let g = gate(now: 0)
        g.onLowPower(true)
        XCTAssertEqual(
            g.verdict(nowMillis: RadioGate.noFixPauseMillis + 1), .pausedLowPower
        )
    }

    func testResetArmsNewGraceWindowButKeepsPowerState() {
        let g = gate(now: 0)
        g.onLowPower(true)
        XCTAssertEqual(g.verdict(nowMillis: 1_000), .pausedLowPower)
        g.reset(nowMillis: 100_000)
        XCTAssertEqual(g.verdict(nowMillis: 100_001), .pausedLowPower)
        g.onLowPower(false)
        XCTAssertEqual(g.verdict(nowMillis: 100_002), .scan)
    }
}
