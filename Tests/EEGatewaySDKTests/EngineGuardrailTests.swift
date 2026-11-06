import Foundation
import XCTest
@testable import EEGatewaySDK
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// S6 guardrails: the remote kill switch, public-id capture, and the
/// provisioning reconcile — driven end-to-end through a stubbed transport
/// and direct loop ticks (heartbeatLoop is internal for exactly this).
final class EngineGuardrailTests: XCTestCase {

    private var radio = FakeRadio()
    private var location = FakeLocation()
    private var tokenStore = InMemoryTokenStore()
    /// Response the stub transport returns for any call.
    private var response: (String, Int)? = ("{}", 200)
    private var requests: [URLRequest] = []

    override func setUp() {
        super.setUp()
        radio = FakeRadio()
        location = FakeLocation()
        tokenStore = InMemoryTokenStore()
        response = ("{}", 200)
        requests = []
    }

    private func makeEngine(
        config: EEConfig = .gatewayToken(token: "ee_live_t"),
        mint: @escaping (String) async -> EEClient.MintResult = { _ in .rejected(reason: "test") },
        preloadToken: String? = "ee_live_t"
    ) -> Engine {
        if let preloadToken { tokenStore.save(preloadToken) }
        let transport: EEClient.Transport = { [weak self] request in
            guard let self else { return nil }
            self.requests.append(request)
            return self.response.map { ($0.0.data(using: .utf8)!, $0.1) }
        }
        return Engine(
            config: config,
            tokenStore: tokenStore,
            client: EEClient(tokenProvider: { [tokenStore] in tokenStore.load() }, transport: transport),
            radio: radio,
            location: location,
            permissionsGranted: { true },
            queueFileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("guardrail-\(UUID().uuidString).eeq"),
            osVersion: "iOS 19.1.2",
            mint: mint,
            pollInterval: 60,
            onChanged: {}
        )
    }

    private func drain(_ engine: Engine) { engine.workQueue.sync {} }

    private func waitUntil(_ timeout: TimeInterval = 2, _ condition: @escaping () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        XCTAssertTrue(condition(), "condition not met within \(timeout)s")
    }

    // MARK: Remote kill switch

    func testDisableParksPipelineButHeartbeatsContinue() async {
        let engine = makeEngine()
        engine.start()
        drain(engine)
        XCTAssertTrue(engine.scanning)

        response = (#"{"disable":true}"#, 200)
        await engine.heartbeatLoop.tick()
        drain(engine)

        XCTAssertTrue(engine.remotePaused)
        XCTAssertFalse(engine.scanning, "kill switch must park the radio")
        XCTAssertEqual(radio.stopCalls, 1)
        XCTAssertTrue(engine.started, "parked, not stopped — heartbeats keep flowing")
        engine.stop()
        drain(engine)
    }

    func testDisableClearingResumesPipeline() async {
        let engine = makeEngine()
        engine.start()
        drain(engine)

        response = (#"{"disable":true}"#, 200)
        await engine.heartbeatLoop.tick()
        drain(engine)
        XCTAssertTrue(engine.remotePaused)

        response = (#"{"disable":false}"#, 200)
        await engine.heartbeatLoop.tick()
        drain(engine)

        XCTAssertFalse(engine.remotePaused)
        XCTAssertTrue(engine.scanning, "flag cleared must resume what the grants allow")
        XCTAssertEqual(radio.startCalls, 2)
        engine.stop()
        drain(engine)
    }

    func testPublicIdAndLastHeartbeatCaptureFromOkBody() async {
        let engine = makeEngine()
        engine.start()
        drain(engine)

        response = (#"{"ok":true,"gateway":{"public_id":"gw_a1b2c3"}}"#, 200)
        await engine.heartbeatLoop.tick()
        drain(engine)

        XCTAssertEqual(engine.gatewayPublicId, "gw_a1b2c3")
        XCTAssertNotNil(engine.lastHeartbeatAt)
        engine.stop()
        drain(engine)
    }

    // MARK: Provisioning reconcile

    func testInjectedTokenVerifiesBeforePersistAndFiresImmediateHeartbeat() {
        let engine = makeEngine(
            config: .gatewayToken(token: "ee_live_new"),
            preloadToken: "ee_live_old"
        )
        engine.start()
        waitUntil { self.tokenStore.load() == "ee_live_new" }

        let verify = requests.first { $0.url?.path.contains("verify") == true }
        XCTAssertEqual(verify?.value(forHTTPHeaderField: "Authorization"), "Bearer ee_live_new",
                       "verify must prove the INJECTED token, not the stored one")
        // The immediate post-provision hello.
        waitUntil { self.requests.contains { $0.url?.path.contains("heartbeat") == true } }
        engine.stop()
    }

    func testRejectedTokenParksAndNeverPersists() {
        response = ("{}", 401)
        let engine = makeEngine(
            config: .gatewayToken(token: "ee_live_bad"),
            preloadToken: "ee_live_old"
        )
        engine.start()
        waitUntil { self.requests.contains { $0.url?.path.contains("verify") == true } }
        Thread.sleep(forTimeInterval: 0.2)   // give a wrong persist time to happen
        XCTAssertEqual(tokenStore.load(), "ee_live_old", "a rejected token must never poison the store")
        engine.stop()
    }

    func testSelfMintPersistsKeyAndName() {
        let engine = makeEngine(
            config: .selfMint(deviceName: "Fleet Van 12"),
            mint: { name in .minted(apiKey: "ee_live_minted", gatewayName: "quiet-river-\(name.count)") },
            preloadToken: nil
        )
        engine.start()
        waitUntil { self.tokenStore.load() == "ee_live_minted" }
        XCTAssertEqual(tokenStore.loadGatewayName(), "quiet-river-12")
        engine.stop()
    }

    func testMatchingStoreSkipsProvisioning() {
        let engine = makeEngine(config: .gatewayToken(token: "ee_live_t"), preloadToken: "ee_live_t")
        engine.start()
        drain(engine)
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertFalse(requests.contains { $0.url?.path.contains("verify") == true },
                       "matching store must not re-verify on every start")
        engine.stop()
    }
}
