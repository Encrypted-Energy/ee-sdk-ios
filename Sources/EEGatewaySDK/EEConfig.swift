import Foundation

/// How this device gets its gateway identity (plan §3). Pass one of the
/// cases to ``EEGateway/configure(_:)``; everything else about the SDK is
/// the same regardless of which you pick.
///
/// Mirrors the Android SDK's `EEConfig` sealed interface case for case, so a
/// partner integrating both platforms reasons about one config model.
public enum EEConfig: Equatable {

    /// Primary, production mode (plan §3). The partner's backend provisions
    /// one gateway per device through the Org API and hands the device its
    /// `ee_live_` token over the partner's own authenticated channel. No EE
    /// credential ever lives in the app binary, so there's nothing to
    /// extract.
    ///
    /// - Parameters:
    ///   - token: the per-device gateway token from the partner backend.
    ///   - baseUrl: ee-web base URL; leave as ``defaultBaseUrl``.
    case gatewayToken(token: String, baseUrl: String)

    /// Secondary, self-mint mode (plan §3) for demos and backend-less
    /// partners. The device mints its own org/gateway on first run.
    /// Economics diverge from production (multi-org overpays on fleet
    /// overlap), so this is a demo tool, not a production path.
    ///
    /// - Parameters:
    ///   - deviceName: name to register the gateway under; nil means use the
    ///     device model read at mint time (so a config object stays
    ///     platform-call-free).
    ///   - baseUrl: ee-web base URL; leave as ``defaultBaseUrl``.
    case selfMint(deviceName: String?, baseUrl: String)

    /// Production ee-web.
    public static let defaultBaseUrl = "https://encryptedenergy.com"

    /// ``gatewayToken(token:baseUrl:)`` against production ee-web.
    public static func gatewayToken(token: String) -> EEConfig {
        .gatewayToken(token: token, baseUrl: defaultBaseUrl)
    }

    /// ``selfMint(deviceName:baseUrl:)`` against production ee-web.
    public static func selfMint(deviceName: String? = nil) -> EEConfig {
        .selfMint(deviceName: deviceName, baseUrl: defaultBaseUrl)
    }

    /// ee-web base URL every network call hangs off. Override only for
    /// staging.
    public var baseUrl: String {
        switch self {
        case .gatewayToken(_, let baseUrl): return baseUrl
        case .selfMint(_, let baseUrl): return baseUrl
        }
    }
}
