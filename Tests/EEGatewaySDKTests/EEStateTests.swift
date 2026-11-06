import XCTest
@testable import EEGatewaySDK

final class EEStateTests: XCTestCase {

    // The roster is the Android SDK's EEState value for value; a new case is
    // a cross-platform API change, not a casual addition.
    func testRosterIsComplete() {
        XCTAssertEqual(EEState.allCases.count, 6)
        XCTAssertEqual(
            EEState.allCases,
            [.unconfigured, .ready, .awaitingPermissions, .running, .pausedRemote, .stopped]
        )
    }

    func testRawValuesAreStable() {
        XCTAssertEqual(EEState.unconfigured.rawValue, "unconfigured")
        XCTAssertEqual(EEState.ready.rawValue, "ready")
        XCTAssertEqual(EEState.awaitingPermissions.rawValue, "awaitingPermissions")
        XCTAssertEqual(EEState.running.rawValue, "running")
        XCTAssertEqual(EEState.pausedRemote.rawValue, "pausedRemote")
        XCTAssertEqual(EEState.stopped.rawValue, "stopped")
    }
}
