/// Token provisioning invariants (plan §3). Pure: verify/mint/persist are
/// injected, so the one rule that matters — NOTHING persists until the
/// server said yes — unit-tests without Keychain or HTTP.
///
/// Verify-before-persist: a token handed to configure()
/// (EEConfig.gatewayToken) is proven against /gateways/verify before it
/// touches the TokenStore, so a typo'd, revoked, or stale token can never
/// poison stored state. Transient failures persist nothing either — the
/// caller retries with Backoff and the previous stored token (if any) stays
/// authoritative.
///
/// The facade (S6) wires these to the real EEClient and TokenStore and maps
/// outcomes onto EEState; the loops (S5) only ever read through the store,
/// so a rejected injection is invisible to them.
///
/// Port of ee-sdk-android TokenProvision; the injected calls are async
/// because EEClient is async here (Android's client blocks on its own
/// thread).
enum TokenProvision {

    enum InjectOutcome: Equatable {
        /// Server accepted the token; it is now persisted.
        case verified
        /// Server rejected the token (401/4xx). NOT persisted.
        case rejected(code: Int)
        /// Couldn't reach a verdict (network/5xx/429). NOT persisted; retry.
        case retry(reason: String)
    }

    enum MintOutcome: Equatable {
        /// Org + gateway minted; key and name are now persisted.
        case provisioned(gatewayName: String)
        /// Server said no (attestation/shape). NOT persisted; surfaced.
        case rejected(reason: String)
        /// 503/429 mint cap or network. NOT persisted; retry with Backoff.
        case retry
    }

    /// Prove `token` against the server, then persist it — in that order.
    /// `verify` is `EEClient.verify(tokenOverride:)` in production.
    static func injectToken(
        _ token: String,
        verify: (String) async -> EEClient.Result,
        persist: (String) -> Void
    ) async -> InjectOutcome {
        switch await verify(token) {
        case .ok:
            persist(token)
            return .verified
        case .unauthorized:
            return .rejected(code: 401)
        // verify only answers 200/401 today; any other 4xx still means the
        // server understood us and said no — never persist on a guess.
        case .terminal(let code, _):
            return .rejected(code: code)
        case .transient(let reason):
            return .retry(reason: reason)
        }
    }

    /// Self-mint (EEConfig.selfMint): one mint call; persist key + name only
    /// on minted. `mint` is `EEClient.mintDevice` in production; the mint
    /// response's key needs no verify round-trip — the server that just
    /// created it is the same server that vouched for it.
    static func selfMint(
        deviceName: String,
        mint: (String) async -> EEClient.MintResult,
        persist: (_ token: String, _ gatewayName: String) -> Void
    ) async -> MintOutcome {
        switch await mint(deviceName) {
        case .minted(let apiKey, let gatewayName):
            persist(apiKey, gatewayName)
            return .provisioned(gatewayName: gatewayName)
        case .rejected(let reason):
            return .rejected(reason: reason)
        case .transient:
            return .retry
        }
    }
}
