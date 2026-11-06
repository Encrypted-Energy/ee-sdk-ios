/// An immutable snapshot of what the gateway is doing right now (plan §3).
/// Returned by ``EEGateway/status()`` and handed to the listener on every
/// change. Mirrors the Android SDK's `EEStatus` field for field.
///
/// Counters are cumulative for the current process; they reset when the host
/// process is recreated, not on ``EEGateway/stop()``/``EEGateway/start()``.
public struct EEStatus: Equatable {
    /// The current lifecycle state; see ``EEState``.
    public let state: EEState
    /// Total BLE beacons heard since process start.
    public let pingsHeard: Int64
    /// Total packets accepted by ee-web since process start.
    public let packetsForwarded: Int64
    /// Packets waiting locally to upload right now.
    public let queueDepth: Int
    /// This device's public gateway id once known, else nil.
    public let gatewayPublicId: String?
    /// Epoch milliseconds of the last successful heartbeat, else nil.
    /// Millis (not Date) for field-level parity with the Android SDK and the
    /// wire format.
    public let lastHeartbeatAt: Int64?

    public init(
        state: EEState,
        pingsHeard: Int64 = 0,
        packetsForwarded: Int64 = 0,
        queueDepth: Int = 0,
        gatewayPublicId: String? = nil,
        lastHeartbeatAt: Int64? = nil
    ) {
        self.state = state
        self.pingsHeard = pingsHeard
        self.packetsForwarded = packetsForwarded
        self.queueDepth = queueDepth
        self.gatewayPublicId = gatewayPublicId
        self.lastHeartbeatAt = lastHeartbeatAt
    }

    /// Kotlin-`copy`-style helper so facade transitions read like the
    /// Android source they mirror.
    func with(state: EEState) -> EEStatus {
        EEStatus(
            state: state,
            pingsHeard: pingsHeard,
            packetsForwarded: packetsForwarded,
            queueDepth: queueDepth,
            gatewayPublicId: gatewayPublicId,
            lastHeartbeatAt: lastHeartbeatAt
        )
    }
}
