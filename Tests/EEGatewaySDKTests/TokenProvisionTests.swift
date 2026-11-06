import XCTest
@testable import EEGatewaySDK

/// The one invariant that matters: nothing persists until the server said
/// yes. Every non-ok branch must leave the store untouched.
final class TokenProvisionTests: XCTestCase {

    private func ok() -> EEClient.Result {
        .ok(code: 200, bountyEarned: 0, disable: false, publicId: nil)
    }

    // MARK: injectToken (verify-before-persist)

    func testVerifiedTokenPersists() async {
        var persisted: String?
        let out = await TokenProvision.injectToken(
            "ee_live_good",
            verify: { _ in self.ok() },
            persist: { persisted = $0 }
        )
        XCTAssertEqual(out, .verified)
        XCTAssertEqual(persisted, "ee_live_good")
    }

    func testVerifySeesTheInjectedTokenNotTheStoredOne() async {
        var seen: String?
        _ = await TokenProvision.injectToken(
            "ee_live_new",
            verify: { seen = $0; return self.ok() },
            persist: { _ in }
        )
        XCTAssertEqual(seen, "ee_live_new")
    }

    func testUnauthorizedTokenNeverPersists() async {
        var persisted: String?
        let out = await TokenProvision.injectToken(
            "ee_live_revoked",
            verify: { _ in .unauthorized },
            persist: { persisted = $0 }
        )
        XCTAssertEqual(out, .rejected(code: 401))
        XCTAssertNil(persisted)
    }

    func testTerminalRejectionNeverPersists() async {
        var persisted: String?
        let out = await TokenProvision.injectToken(
            "ee_live_odd",
            verify: { _ in .terminal(code: 403, body: nil) },
            persist: { persisted = $0 }
        )
        XCTAssertEqual(out, .rejected(code: 403))
        XCTAssertNil(persisted)
    }

    func testTransientVerifyNeverPersists() async {
        var persisted: String?
        let out = await TokenProvision.injectToken(
            "ee_live_maybe",
            verify: { _ in .transient(reason: "network") },
            persist: { persisted = $0 }
        )
        XCTAssertEqual(out, .retry(reason: "network"))
        XCTAssertNil(persisted)
    }

    // MARK: selfMint

    func testMintedKeyAndNamePersist() async {
        var token: String?
        var name: String?
        let out = await TokenProvision.selfMint(
            deviceName: "iPhone 17",
            mint: { _ in .minted(apiKey: "ee_live_minted", gatewayName: "quiet-river-201") },
            persist: { t, n in token = t; name = n }
        )
        XCTAssertEqual(out, .provisioned(gatewayName: "quiet-river-201"))
        XCTAssertEqual(token, "ee_live_minted")
        XCTAssertEqual(name, "quiet-river-201")
    }

    func testMintPassesTheDeviceName() async {
        var seen: String?
        _ = await TokenProvision.selfMint(
            deviceName: "iPad mini",
            mint: { seen = $0; return .transient },
            persist: { _, _ in }
        )
        XCTAssertEqual(seen, "iPad mini")
    }

    func testRejectedMintNeverPersists() async {
        var persisted = false
        let out = await TokenProvision.selfMint(
            deviceName: "iPhone 17",
            mint: { _ in .rejected(reason: "attestation failed") },
            persist: { _, _ in persisted = true }
        )
        XCTAssertEqual(out, .rejected(reason: "attestation failed"))
        XCTAssertFalse(persisted)
    }

    func testTransientMintNeverPersists() async {
        var persisted = false
        let out = await TokenProvision.selfMint(
            deviceName: "iPhone 17",
            mint: { _ in .transient },
            persist: { _, _ in persisted = true }
        )
        XCTAssertEqual(out, .retry)
        XCTAssertFalse(persisted)
    }
}
