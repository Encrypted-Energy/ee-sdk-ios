import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// ee-web API client. Response handling ports the shipped app's EEClient
/// (verified against the ee-web controllers 2026-07-12, re-verified after
/// the batch-forward rewrite @ 9216503) with the Android SDK's deltas: the
/// app-only claim flow is REMOVED (a fleet SDK has no end user to attach —
/// the partner's org already owns every gateway), verify() is ADDED for
/// verify-before-persist (S4), and the heartbeat 2xx body is parsed for the
/// C9 `disable` kill switch and `gateway.public_id`.
///
/// Zero third-party deps: URLSession, 10 s timeouts, Bearer auth. The wire
/// call is injected (`Transport`), so every status/body branch unit-tests
/// without HTTP — a seam the Android SDK's HttpURLConnection couldn't offer.
///
/// Response mapping copies the Pi worker: 2xx ok; 401 terminal-unauthorized;
/// other 4xx terminal; 408/429/5xx/network transient (§1a, §1b). Terminal
/// results keep the response body so the caller can surface 422
/// `invalid_reasons` (see BatchSender).
final class EEClient {

    /// One wire call: request in, (body, status) out; nil = network-level
    /// failure. The default is URLSession; tests stub it.
    typealias Transport = (URLRequest) async -> (Data, Int)?

    enum Result: Equatable {
        /// 2xx. `bountyEarned` is the server's count of bounty events THIS
        /// batch minted (first-to-report wins only; ee-web 19f4803) — 0 when
        /// the field is absent or this isn't an ingest response. `disable`
        /// is the heartbeat response's fleet kill switch (C9): parsed here,
        /// acted on in S6 — absent means enabled. `publicId` is
        /// `gateway.public_id` from a heartbeat 2xx body — feeds
        /// EEStatus.gatewayPublicId; nil when absent/malformed.
        case ok(code: Int, bountyEarned: Int, disable: Bool, publicId: String?)
        case unauthorized
        /// Non-401 4xx. `body` survives so 422 invalid_reasons can be read.
        case terminal(code: Int, body: String?)
        case transient(reason: String)
    }

    /// POST /api/v1/devices outcome (anonymous self-mint, no token yet).
    enum MintResult: Equatable {
        /// 2xx: org + gateway + key created. Save the key, start scanning.
        case minted(apiKey: String, gatewayName: String)
        /// 403 attestation / 422 shape / other 4xx: server said no, surfaced.
        case rejected(reason: String)
        /// Network / 5xx / 429: worth retrying with Backoff (300/hr mint cap).
        case transient
    }

    static let userAgentPrefix = "ee-sdk-ios"
    static let timeoutSeconds: TimeInterval = 10

    private let tokenProvider: () -> String?
    private let baseUrl: String
    private let transport: Transport

    init(
        tokenProvider: @escaping () -> String?,
        baseUrl: String = EEConfig.defaultBaseUrl,
        transport: @escaping Transport = EEClient.urlSessionTransport
    ) {
        self.tokenProvider = tokenProvider
        self.baseUrl = baseUrl
        self.transport = transport
    }

    // MARK: - Endpoints

    /// GET /api/v1/gateways/verify — token check. `tokenOverride` exists for
    /// verify-before-persist: a token handed to configure() is proven
    /// against the server BEFORE it ever reaches the TokenStore (S4), so a
    /// typo'd or revoked token can't poison stored state.
    func verify(tokenOverride: String? = nil) async -> Result {
        guard let token = tokenOverride ?? tokenProvider() else { return .unauthorized }
        return await call("GET", "/api/v1/gateways/verify", token: token, body: nil, tag: "verify") { code, _ in
            .ok(code: code, bountyEarned: 0, disable: false, publicId: nil)
        }
    }

    /// POST /api/v1/gateways/heartbeat — the telemetry ping (§1b). The 2xx
    /// body is parsed for the C9 `disable` flag and `gateway.public_id`.
    func heartbeat(_ payloadJson: String) async -> Result {
        guard let token = tokenProvider() else { return .unauthorized }
        return await call("POST", "/api/v1/gateways/heartbeat", token: token, body: payloadJson, tag: "heartbeat") { code, body in
            .ok(code: code, bountyEarned: 0, disable: Self.parseDisable(body), publicId: Self.parsePublicId(body))
        }
    }

    /// POST /api/v1/gateways/packets — batch BLE packet upload (§1a). The
    /// 2xx body is parsed for `bounty_earned`. Batch semantics (500 max,
    /// 413 split, 422 drop) live in BatchSender; this is one wire call.
    func ingest(_ batchJson: String) async -> Result {
        guard let token = tokenProvider() else { return .unauthorized }
        return await call("POST", "/api/v1/gateways/packets", token: token, body: batchJson, tag: "ingest") { code, body in
            .ok(code: code, bountyEarned: Self.parseBountyEarned(body), disable: false, publicId: nil)
        }
    }

    /// POST /api/v1/devices (ee-web 19f4803) — self-mint mode
    /// (EEConfig.selfMint). The one call that happens before any token
    /// exists, so it's static — no tokenProvider. attestation_token is
    /// omitted: the server runs DEVICE_ATTESTATION in log mode and allows
    /// its absence. Transient outcomes (503/429: the 300/hr global mint cap)
    /// must be retried through Backoff, never in a tight loop.
    static func mintDevice(
        deviceName: String,
        baseUrl: String = EEConfig.defaultBaseUrl,
        transport: Transport = EEClient.urlSessionTransport
    ) async -> MintResult {
        let body = (try? Json.obj([("platform", "ios"), ("device_name", deviceName)])) ?? "{}"
        guard let request = makeRequest("POST", baseUrl: baseUrl, path: "/api/v1/devices", token: nil, body: body, tag: "mint") else {
            return .transient
        }
        guard let (data, code) = await transport(request) else { return .transient }
        return mapMint(code: code, body: String(data: data, encoding: .utf8), fallbackName: deviceName)
    }

    // MARK: - Pure response mappers (status + body -> outcome)

    /// The shared worker status mapping; `onOk` shapes the 2xx result.
    static func map(code: Int, body: String?, onOk: (Int, String?) -> Result) -> Result {
        switch code {
        case 200...299: return onOk(code, body)
        case 401: return .unauthorized
        case 408, 429: return .transient(reason: "HTTP \(code)")
        case 400...499: return .terminal(code: code, body: body)
        default: return .transient(reason: "HTTP \(code)")
        }
    }

    /// `bounty_earned` from an ingest 2xx body; 0 if absent or malformed.
    static func parseBountyEarned(_ body: String?) -> Int {
        object(body)?["bounty_earned"] as? Int ?? 0
    }

    /// `disable` from a heartbeat 2xx body (C9 fleet kill switch); false if
    /// absent or malformed — a parse failure must never pause a fleet.
    static func parseDisable(_ body: String?) -> Bool {
        object(body)?["disable"] as? Bool ?? false
    }

    /// `gateway.public_id` from a heartbeat/verify 2xx body; nil if absent
    /// or malformed — identity is a nicety, never a failure.
    static func parsePublicId(_ body: String?) -> String? {
        (object(body)?["gateway"] as? [String: Any])?["public_id"] as? String
    }

    /// `invalid_reasons` from an ingest 422 body; empty if absent/malformed.
    static func parseInvalidReasons(_ body: String?) -> [String] {
        (object(body)?["invalid_reasons"] as? [Any])?.compactMap { $0 as? String } ?? []
    }

    static func mapMint(code: Int, body: String?, fallbackName: String) -> MintResult {
        let node = object(body)
        switch code {
        case 200...299:
            guard let key = node?["api_key"] as? String, key.hasPrefix("ee_live_") else {
                return .rejected(reason: "mint response missing api_key")
            }
            let gatewayName = (node?["gateway"] as? [String: Any])?["name"] as? String
            return .minted(apiKey: key, gatewayName: gatewayName ?? fallbackName)
        case 408, 429, 500...599:
            return .transient
        default:
            return .rejected(reason: node?["error"] as? String ?? "mint failed (\(code))")
        }
    }

    // MARK: - Private

    /// Top-level JSON object from a response body; nil on anything else.
    private static func object(_ body: String?) -> [String: Any]? {
        guard let body,
              let data = body.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data)
        else { return nil }
        return parsed as? [String: Any]
    }

    private func call(
        _ method: String,
        _ path: String,
        token: String,
        body: String?,
        tag: String,
        onOk: (Int, String?) -> Result
    ) async -> Result {
        guard let request = Self.makeRequest(method, baseUrl: baseUrl, path: path, token: token, body: body, tag: tag) else {
            return .transient(reason: "bad url")
        }
        guard let (data, code) = await transport(request) else {
            return .transient(reason: "network")
        }
        return Self.map(code: code, body: String(data: data, encoding: .utf8), onOk: onOk)
    }

    private static func makeRequest(
        _ method: String,
        baseUrl: String,
        path: String,
        token: String?,
        body: String?,
        tag: String
    ) -> URLRequest? {
        guard let url = URL(string: baseUrl + path) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: timeoutSeconds)
        request.httpMethod = method
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("\(userAgentPrefix)/\(tag)", forHTTPHeaderField: "User-Agent")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body.data(using: .utf8)
        }
        return request
    }

    /// The production transport. Continuation-wrapped dataTask rather than
    /// `URLSession.data(for:)` so it exists on every platform this package
    /// compiles on (Linux's FoundationNetworking included).
    static let urlSessionTransport: Transport = { request in
        await withCheckedContinuation { continuation in
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                guard error == nil, let http = response as? HTTPURLResponse else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: (data ?? Data(), http.statusCode))
            }
            task.resume()
        }
    }
}
