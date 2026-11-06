#if canImport(Security)
import XCTest
@testable import EEGatewaySDK

/// Darwin-only: exercises the real SecItem plumbing. Skipped on the Linux
/// harness (no Security framework); John's Mac `swift test` runs it — a
/// live-storage check the Android Keystore could never get off-device.
final class KeychainTokenStoreTests: XCTestCase {

    private let store = KeychainTokenStore()

    override func setUp() {
        super.setUp()
        store.clear()
    }

    override func tearDown() {
        store.clear()
        super.tearDown()
    }

    func testTokenRoundTripAndUpsert() {
        XCTAssertNil(store.load())
        store.save("ee_live_first")
        XCTAssertEqual(store.load(), "ee_live_first")
        store.save("ee_live_rotated")   // update path, not add
        XCTAssertEqual(store.load(), "ee_live_rotated")
    }

    func testGatewayNameRidesBesideTheToken() {
        store.save("ee_live_x")
        store.saveGatewayName("quiet-river-201")
        XCTAssertEqual(store.loadGatewayName(), "quiet-river-201")
    }

    func testClearRemovesBoth() {
        store.save("ee_live_x")
        store.saveGatewayName("n")
        store.clear()
        XCTAssertNil(store.load())
        XCTAssertNil(store.loadGatewayName())
    }
}
#endif
