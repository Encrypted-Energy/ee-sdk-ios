# API freeze

This is the frozen public surface of the EE gateway SDK for iOS, as of
0.1.0. It mirrors `ee-sdk-android/api-freeze.md` case for case: ship
both platforms and you write against one config model.

**Frozen-additive from 0.1.0 forward.** Once you ship against this surface
we can't force your app to update, so nothing here ever changes meaning,
signature, or removal. We only add: new types, new optional parameters
with defaults, new enum cases appended at the end. Switch every public
enum here with a `default`/`@unknown default`, per Swift convention, and
appends stay source-safe for you.

Anything not listed below is internal and may change at any time.

```swift
public enum EEGateway {
    public static let version: String
    public static func configure(_ config: EEConfig)
    public static func start()
    public static func stop()
    public static func status() -> EEStatus
    public static func setListener(_ listener: EEListener?)
}

public enum EEConfig: Equatable {
    case gatewayToken(token: String, baseUrl: String)
    case selfMint(deviceName: String?, baseUrl: String)
    public static let defaultBaseUrl: String
    public static func gatewayToken(token: String) -> EEConfig
    public static func selfMint(deviceName: String? = nil) -> EEConfig
    public var baseUrl: String { get }
}

public enum EEState: String, CaseIterable, Equatable {
    case unconfigured, ready, awaitingPermissions, running, pausedRemote, stopped
}

public struct EEStatus: Equatable {
    public let state: EEState
    public let pingsHeard: Int64
    public let packetsForwarded: Int64
    public let queueDepth: Int
    public let gatewayPublicId: String?
    public let lastHeartbeatAt: Int64?     // epoch millis
    public init(state:pingsHeard:packetsForwarded:queueDepth:gatewayPublicId:lastHeartbeatAt:)
}

public typealias EEListener = (EEStatus) -> Void
```

Platform delta vs Android, by design: `configure` takes no Context (iOS has
no equivalent), and the crash-isolated-listener clause is enforced by the
non-throwing closure type instead of a runtime catch.
