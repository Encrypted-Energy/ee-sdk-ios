/// Single source of truth for the SDK version string. ``EEGateway/version``
/// (the frozen public surface) and the heartbeat `worker_version` both read
/// from here, so the published artifact, the API constant, and fleet
/// telemetry can never disagree. Bump this, and only this, on release.
enum SdkVersion {
    static let string = "0.2.0"
}
