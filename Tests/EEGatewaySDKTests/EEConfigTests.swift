import XCTest
@testable import EEGatewaySDK

final class EEConfigTests: XCTestCase {

    func testGatewayTokenDefaultsToProductionBaseUrl() {
        let config = EEConfig.gatewayToken(token: "ee_live_abc")
        XCTAssertEqual(config.baseUrl, "https://encryptedenergy.com")
        XCTAssertEqual(config, .gatewayToken(token: "ee_live_abc", baseUrl: EEConfig.defaultBaseUrl))
    }

    func testGatewayTokenBaseUrlOverride() {
        let config = EEConfig.gatewayToken(token: "ee_live_abc", baseUrl: "https://staging.example.com")
        XCTAssertEqual(config.baseUrl, "https://staging.example.com")
    }

    func testSelfMintDefaults() {
        let config = EEConfig.selfMint()
        XCTAssertEqual(config, .selfMint(deviceName: nil, baseUrl: EEConfig.defaultBaseUrl))
        XCTAssertEqual(config.baseUrl, "https://encryptedenergy.com")
    }

    func testSelfMintWithDeviceName() {
        let config = EEConfig.selfMint(deviceName: "Fleet Van 12")
        XCTAssertEqual(config, .selfMint(deviceName: "Fleet Van 12", baseUrl: EEConfig.defaultBaseUrl))
    }

    func testConfigsWithDifferentTokensAreNotEqual() {
        XCTAssertNotEqual(EEConfig.gatewayToken(token: "a"), EEConfig.gatewayToken(token: "b"))
    }

    func testTokenAndSelfMintAreNeverEqual() {
        XCTAssertNotEqual(
            EEConfig.gatewayToken(token: "x"),
            EEConfig.selfMint(deviceName: "x")
        )
    }
}
