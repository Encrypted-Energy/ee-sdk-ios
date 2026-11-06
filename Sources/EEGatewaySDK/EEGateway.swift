import Foundation

/// The entire public surface of the EE gateway SDK (plan §1, §3). A partner
/// app integrates in two lines:
///
/// ```swift
/// EEGateway.configure(.gatewayToken(token: token))
/// EEGateway.start()   // from your existing app/background lifecycle
/// ```
///
/// Next app update, every phone in the fleet is a silent EE gateway: no
/// signup, no UI, no new permission prompts, no EE credential in the binary.
///
/// ## Contracts (these ARE the product, plan §3)
///  - **Never throws.** No public method is `throws`, and no internal failure
///    propagates into the host app; failures surface in ``status()`` and the
///    unified log (subsystem `com.encryptedenergy.sdk`).
///  - **Never prompts for permissions.** The SDK is dormant without the
///    host's Bluetooth/location grants. ``start()`` with grants missing lands
///    in ``EEState/awaitingPermissions``; it does not request anything, and
///    it advances to ``EEState/running`` on its own once the host obtains the
///    grants. The host app owns the permission UX, because fleet apps already
///    hold the grants.
///  - **No background modes of its own.** The host's Info.plist declares
///    `bluetooth-central` (and its location usage string); the reference
///    setup ships in the sample app, not here.
///  - **``configure(_:)`` is idempotent.** A changed config applies the next
///    time the gateway is started from a non-running state; it never
///    regresses a running gateway.
///  - **``start()``/``stop()`` are idempotent and main-thread safe.** Call
///    them from your lifecycle as often as you like.
///  - **Listener callbacks arrive on the main queue**, coalesced to ≤ ~1/s
///    for counter-only changes (see ``EEListener``).
///
/// Thread-safety: all state transitions are serialized on a single lock, so
/// the facade is safe to call from any thread even though callbacks land on
/// main.
public enum EEGateway {

    /// SDK version, matching the published package.
    public static let version = SdkVersion.string

    private static let lock = NSLock()

    // Held state, guarded by `lock`.
    private static var config: EEConfig?
    private static var listener: EEListener?
    private static var current = EEStatus(state: .unconfigured)

    /// Test seam: callbacks post here. Defaults to main; the contract that a
    /// partner-visible callback arrives on the main queue is unchanged.
    static var callbackQueue: DispatchQueue = .main

    /// Store the `config`, then move to ``EEState/ready`` if this is the
    /// first configuration. Idempotent: calling it again just refreshes the
    /// config and never regresses a running gateway.
    ///
    /// Never throws.
    public static func configure(_ config: EEConfig) {
        lock.lock(); defer { lock.unlock() }
        self.config = config
        if current.state == .unconfigured {
            transition(current.with(state: .ready))
        }
    }

    /// Begin (or resume) the gateway from the host's lifecycle. Idempotent
    /// and main-thread safe. A no-op if not yet configured.
    ///
    /// With the host's Bluetooth/location grants present this lands in
    /// ``EEState/running``; without them, ``EEState/awaitingPermissions`` —
    /// the pipeline stays dormant, heartbeats still flow (so the fleet
    /// dashboard can see the phone), and the SDK advances by itself when the
    /// grants appear.
    ///
    /// Never throws; never prompts for permissions.
    public static func start() {
        lock.lock(); defer { lock.unlock() }
        guard config != nil else { return }   // nothing to start; not an error
        switch current.state {
        case .running, .awaitingPermissions, .pausedRemote:
            return                            // idempotent (incl. remote-paused: already started)
        case .unconfigured, .ready, .stopped:
            // S1 stub: the engine (scanner, queue, loops, permission gate)
            // lands in S5; until then start lands in RUNNING directly.
            transition(current.with(state: .running))
        }
    }

    /// Stop the gateway from the host's lifecycle. Idempotent and main-thread
    /// safe. A no-op if not yet configured or already stopped.
    ///
    /// Never throws.
    public static func stop() {
        lock.lock(); defer { lock.unlock() }
        switch current.state {
        case .unconfigured, .stopped:
            return
        case .ready, .awaitingPermissions, .running, .pausedRemote:
            transition(current.with(state: .stopped))
        }
    }

    /// The current ``EEStatus`` snapshot. Never throws.
    public static func status() -> EEStatus {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    /// Register (or clear, with nil) the status `listener`. Callbacks always
    /// arrive on the main queue. Never throws.
    public static func setListener(_ listener: EEListener?) {
        lock.lock(); defer { lock.unlock() }
        self.listener = listener
    }

    /// Commit a new status and notify the listener on the callback queue.
    /// Called only while holding `lock`; the notification itself is posted,
    /// so it never runs under the lock and a slow listener can't stall a
    /// caller. A no-op when nothing changed, so coalesced refreshes don't
    /// echo.
    private static func transition(_ next: EEStatus) {
        if next == current { return }
        current = next
        guard let l = listener else { return }
        callbackQueue.async { l(next) }
    }

    /// Test seam: return the facade to factory state between test cases.
    static func _resetForTests() {
        lock.lock(); defer { lock.unlock() }
        config = nil
        listener = nil
        current = EEStatus(state: .unconfigured)
        callbackQueue = .main
    }
}
