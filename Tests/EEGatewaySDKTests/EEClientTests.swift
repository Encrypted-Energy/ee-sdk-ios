import Foundation
import XCTest
@testable import EEGatewaySDK
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The pure status+body mappers behind mint/ingest/heartbeat, carried 1:1
/// from the Android SDK — these pin the branch logic that decides the
/// outcome: "missing key is rejection", "bounty_earned drives the earn
/// signal", "a malformed disable can never pause a fleet". Endpoint-level
/// request/response shaping is covered separately via the Transport seam.
final class EEClientTests: XCTestCase {

    // MARK: bounty_earned (ingest 2xx body)

    func testBountyEarnedParsesTheField() {
        XCTAssertEqual(EEClient.parseBountyEarned(#"{"bounty_earned":3,"accepted":12}"#), 3)
    }

    func testBountyEarnedAbsentIsZero() {
        XCTAssertEqual(EEClient.parseBountyEarned(#"{"accepted":12}"#), 0)
    }

    func testBountyEarnedNilBodyIsZero() {
        XCTAssertEqual(EEClient.parseBountyEarned(nil), 0)
    }

    func testBountyEarnedMalformedIsZero() {
        XCTAssertEqual(EEClient.parseBountyEarned(#"{not json"#), 0)
    }

    // MARK: disable (heartbeat 2xx body, the C9 fleet kill switch)

    func testDisableParsesTrue() {
        XCTAssertTrue(EEClient.parseDisable(#"{"ok":true,"disable":true}"#))
    }

    func testDisableAbsentIsFalse() {
        XCTAssertFalse(EEClient.parseDisable(#"{"ok":true}"#))
    }

    func testDisableNilBodyIsFalse() {
        XCTAssertFalse(EEClient.parseDisable(nil))
    }

    func testDisableMalformedIsFalse() {
        // A parse failure must never pause a fleet.
        XCTAssertFalse(EEClient.parseDisable(#"{broken"#))
    }

    func testDisableNonBooleanIsFalse() {
        XCTAssertFalse(EEClient.parseDisable(#"{"disable":"yes"}"#))
    }

    // MARK: gateway.public_id (heartbeat/verify 2xx body)

    func testPublicIdParsesFromGatewayBlock() {
        XCTAssertEqual(
            EEClient.parsePublicId(#"{"ok":true,"gateway":{"name":"Fleet 7","public_id":"gw_a1b2c3"}}"#),
            "gw_a1b2c3"
        )
    }

    func testPublicIdAbsentIsNil() {
        XCTAssertNil(EEClient.parsePublicId(#"{"ok":true}"#))
        XCTAssertNil(EEClient.parsePublicId(#"{"ok":true,"gateway":{"name":"x"}}"#))
    }

    func testPublicIdNilOrMalformedBodyIsNil() {
        // Identity is a nicety, never a failure.
        XCTAssertNil(EEClient.parsePublicId(nil))
        XCTAssertNil(EEClient.parsePublicId(#"{broken"#))
        XCTAssertNil(EEClient.parsePublicId(#"{"gateway":"not an object"}"#))
    }

    // MARK: invalid_reasons (ingest 422 body)

    func testInvalidReasonsParsesStrings() {
        XCTAssertEqual(
            EEClient.parseInvalidReasons(
                #"{"ok":false,"error":"invalid packets","invalid_reasons":["packet[0]: missing eid","packet[2]: latitude/longitude out of range"]}"#
            ),
            ["packet[0]: missing eid", "packet[2]: latitude/longitude out of range"]
        )
    }

    func testInvalidReasonsAbsentIsEmpty() {
        XCTAssertEqual(EEClient.parseInvalidReasons(#"{"ok":false}"#), [])
    }

    func testInvalidReasonsNilBodyIsEmpty() {
        XCTAssertEqual(EEClient.parseInvalidReasons(nil), [])
    }

    func testInvalidReasonsMalformedIsEmpty() {
        XCTAssertEqual(EEClient.parseInvalidReasons("not json"), [])
    }

    // MARK: mint (POST /api/v1/devices)

    func testMintMintedPullsKeyAndGatewayName() {
        XCTAssertEqual(
            EEClient.mapMint(code: 201, body: #"{"api_key":"ee_live_xyz","gateway":{"name":"iPhone 17"}}"#, fallbackName: "fallback"),
            .minted(apiKey: "ee_live_xyz", gatewayName: "iPhone 17")
        )
    }

    func testMintFallsBackToDeviceNameWhenGatewayNameAbsent() {
        XCTAssertEqual(
            EEClient.mapMint(code: 201, body: #"{"api_key":"ee_live_xyz"}"#, fallbackName: "iPad mini"),
            .minted(apiKey: "ee_live_xyz", gatewayName: "iPad mini")
        )
    }

    func testMintRejectsMissingApiKey() {
        XCTAssertEqual(
            EEClient.mapMint(code: 201, body: #"{"gateway":{"name":"x"}}"#, fallbackName: "fb"),
            .rejected(reason: "mint response missing api_key")
        )
    }

    func testMintRejectsWrongKeyPrefix() {
        XCTAssertEqual(
            EEClient.mapMint(code: 201, body: #"{"api_key":"nope_123"}"#, fallbackName: "fb"),
            .rejected(reason: "mint response missing api_key")
        )
    }

    func testMintSurfacesServerErrorMessage() {
        XCTAssertEqual(
            EEClient.mapMint(code: 403, body: #"{"error":"attestation failed"}"#, fallbackName: "fb"),
            .rejected(reason: "attestation failed")
        )
    }

    func testMintTreats5xxAndThrottleAsTransient() {
        XCTAssertEqual(EEClient.mapMint(code: 503, body: nil, fallbackName: "fb"), .transient)
        XCTAssertEqual(EEClient.mapMint(code: 500, body: nil, fallbackName: "fb"), .transient)
        XCTAssertEqual(EEClient.mapMint(code: 429, body: nil, fallbackName: "fb"), .transient)
        XCTAssertEqual(EEClient.mapMint(code: 408, body: nil, fallbackName: "fb"), .transient)
    }

    // MARK: endpoint shaping through the Transport seam

    private func stub(
        code: Int,
        body: String = "{}",
        capture: @escaping (URLRequest) -> Void = { _ in }
    ) -> EEClient.Transport {
        { request in
            capture(request)
            return (body.data(using: .utf8)!, code)
        }
    }

    func testVerifyUsesGetAndBearerToken() async {
        var seen: URLRequest?
        let client = EEClient(tokenProvider: { "ee_live_t" }, transport: stub(code: 200) { seen = $0 })
        let result = await client.verify()
        XCTAssertEqual(result, .ok(code: 200, bountyEarned: 0, disable: false, publicId: nil))
        XCTAssertEqual(seen?.httpMethod, "GET")
        XCTAssertEqual(seen?.value(forHTTPHeaderField: "Authorization"), "Bearer ee_live_t")
        XCTAssertEqual(seen?.value(forHTTPHeaderField: "User-Agent"), "ee-sdk-ios/verify")
        XCTAssertEqual(seen?.url?.absoluteString, "https://encryptedenergy.com/api/v1/gateways/verify")
    }

    func testVerifyTokenOverrideWinsOverProvider() async {
        var seen: URLRequest?
        let client = EEClient(tokenProvider: { "stored" }, transport: stub(code: 200) { seen = $0 })
        _ = await client.verify(tokenOverride: "candidate")
        XCTAssertEqual(seen?.value(forHTTPHeaderField: "Authorization"), "Bearer candidate")
    }

    func testMissingTokenIsUnauthorizedWithoutAWireCall() async {
        var calls = 0
        let client = EEClient(tokenProvider: { nil }, transport: stub(code: 200) { _ in calls += 1 })
        let heartbeat = await client.heartbeat("{}")
        let ingest = await client.ingest("{}")
        XCTAssertEqual(heartbeat, .unauthorized)
        XCTAssertEqual(ingest, .unauthorized)
        XCTAssertEqual(calls, 0)
    }

    func testHeartbeatParsesDisableAndPublicId() async {
        let client = EEClient(
            tokenProvider: { "t" },
            transport: stub(code: 200, body: #"{"disable":true,"gateway":{"public_id":"gw_9"}}"#)
        )
        let result = await client.heartbeat("{}")
        XCTAssertEqual(result, .ok(code: 200, bountyEarned: 0, disable: true, publicId: "gw_9"))
    }

    func testIngestParsesBountyAndPostsBody() async {
        var seen: URLRequest?
        let client = EEClient(
            tokenProvider: { "t" },
            transport: stub(code: 200, body: #"{"bounty_earned":2}"#) { seen = $0 }
        )
        let result = await client.ingest(#"{"packets":[]}"#)
        XCTAssertEqual(result, .ok(code: 200, bountyEarned: 2, disable: false, publicId: nil))
        XCTAssertEqual(seen?.httpMethod, "POST")
        XCTAssertEqual(seen?.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(seen?.httpBody, #"{"packets":[]}"#.data(using: .utf8))
    }

    func testNetworkFailureIsTransient() async {
        let client = EEClient(tokenProvider: { "t" }, transport: { _ in nil })
        let result = await client.ingest("{}")
        XCTAssertEqual(result, .transient(reason: "network"))
    }

    func testStatusMapping() async {
        for (code, expected) in [
            (401, EEClient.Result.unauthorized),
            (408, .transient(reason: "HTTP 408")),
            (429, .transient(reason: "HTTP 429")),
            (422, .terminal(code: 422, body: "{}")),
            (502, .transient(reason: "HTTP 502")),
        ] {
            let client = EEClient(tokenProvider: { "t" }, transport: stub(code: code))
            let result = await client.heartbeat("{}")
            XCTAssertEqual(result, expected, "code \(code)")
        }
    }

    func testMintSendsNoAuthHeaderAndIosPlatform() async {
        var seen: URLRequest?
        let result = await EEClient.mintDevice(
            deviceName: "iPhone 17",
            transport: stub(code: 201, body: #"{"api_key":"ee_live_k"}"#) { seen = $0 }
        )
        XCTAssertEqual(result, .minted(apiKey: "ee_live_k", gatewayName: "iPhone 17"))
        XCTAssertNil(seen?.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(seen?.value(forHTTPHeaderField: "User-Agent"), "ee-sdk-ios/mint")
        let body = String(data: seen?.httpBody ?? Data(), encoding: .utf8)!
        XCTAssertTrue(body.contains(#""platform":"ios""#), body)
        XCTAssertTrue(body.contains(#""device_name":"iPhone 17""#), body)
    }
}
