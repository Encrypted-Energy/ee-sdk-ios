/// The lifecycle states the gateway can be in (plan §3). Every ``EEStatus``
/// carries exactly one of these. Mirrors the Android SDK's `EEState` value
/// for value.
public enum EEState: String, CaseIterable, Equatable {
    /// No ``EEConfig`` yet. ``EEGateway/configure(_:)`` has not been called.
    case unconfigured

    /// Configured and idle. Waiting for ``EEGateway/start()``.
    case ready

    /// Started, but the host app is missing a Bluetooth or location grant,
    /// so the pipeline is dormant. The SDK never prompts; the state simply
    /// reports what it's waiting on. It advances to ``running`` on its own
    /// once the host holds the grants and start is in effect.
    case awaitingPermissions

    /// Scanning, forwarding packets, and sending heartbeats.
    case running

    /// The server-driven kill switch (plan §3, §4.1). A heartbeat response
    /// of `{"disable": true}` lands here: scanning and upload stop, but
    /// heartbeats keep going so the fleet re-enables the instant the flag
    /// clears. Not a host action and not an error.
    case pausedRemote

    /// ``EEGateway/stop()`` has been called. Idle until the next start.
    case stopped
}
