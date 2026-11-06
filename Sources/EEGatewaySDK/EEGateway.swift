import Foundation
#if canImport(UIKit)
import UIKit
#endif

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
///    propagates into the host app; failures surface in ``status()``.
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
///  - **Listener callbacks arrive on the main queue and are coalesced**
///    (≤ ~1/s for counter-only changes) so a beacon-dense street can't flood
///    the host's main queue; state changes ride the same tick and are never
///    dropped (``transition(_:)`` compares snapshots).
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
    private static var engine: Engine?
    /// The config `engine` was built with — a later configure() may differ.
    private static var engineConfig: EEConfig?
    private static var refreshPending = false

    /// Test seam: callbacks post here. Defaults to main; the contract that a
    /// partner-visible callback arrives on the main queue is unchanged.
    static var callbackQueue: DispatchQueue = .main
    /// Test seam: the ~1/s coalescing window for engine-change refreshes.
    static var refreshCoalesceMillis = 1_000
    /// Test seam: how start() builds its Engine. The default wires the real
    /// Darwin pipeline; the Linux harness overrides with fakes.
    static var engineFactory: (EEConfig, @escaping () -> Void) -> Engine = EEGateway.defaultEngine

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
        guard let cfg = config else { return }   // nothing to start; not an error
        switch current.state {
        case .running, .awaitingPermissions, .pausedRemote:
            return                               // idempotent (incl. remote-paused: already started)
        case .unconfigured, .ready, .stopped:
            break
        }
        // A config change (new token, new base URL) takes effect here, from
        // a non-running state: tear down and rebuild.
        if engine != nil && engineConfig != cfg {
            engine?.stop()
            engine = nil
        }
        let e: Engine
        if let existing = engine {
            e = existing
        } else {
            e = engineFactory(cfg, engineChanged)
            engine = e
            engineConfig = cfg
        }
        e.start()
        transition(
            composeStatus(
                e.remotePaused ? .pausedRemote
                    : e.permissionsGranted() ? .running
                    : .awaitingPermissions
            )
        )
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
            engine?.stop()
            transition(composeStatus(.stopped))
        }
    }

    /// The current ``EEStatus`` snapshot. Never throws.
    public static func status() -> EEStatus {
        lock.lock(); defer { lock.unlock() }
        return composeStatus(current.state)
    }

    /// Register (or clear, with nil) the status `listener`. Callbacks always
    /// arrive on the main queue. Never throws.
    public static func setListener(_ listener: EEListener?) {
        lock.lock(); defer { lock.unlock() }
        self.listener = listener
    }

    // MARK: - Internals (call under `lock`)

    /// Live counters from the engine grafted onto `state`.
    private static func composeStatus(_ state: EEState) -> EEStatus {
        guard let e = engine else { return current.with(state: state) }
        return EEStatus(
            state: state,
            pingsHeard: e.pingsHeard,
            packetsForwarded: e.packetsForwarded,
            queueDepth: e.queueDepth(),
            gatewayPublicId: e.gatewayPublicId,
            lastHeartbeatAt: e.lastHeartbeatAt
        )
    }

    /// Engine change feed — potentially once per heard advertisement, from
    /// the engine queue or a loop task. Coalesced to one refresh per
    /// `refreshCoalesceMillis`: dense traffic becomes at most ~1 listener
    /// callback/s, and the dormancy-gate flip (awaitingPermissions ↔
    /// running) rides the next tick, never lost because `transition`
    /// compares snapshots.
    private static func engineChanged() {
        lock.lock()
        if refreshPending { lock.unlock(); return }
        refreshPending = true
        lock.unlock()
        callbackQueue.asyncAfter(deadline: .now() + .milliseconds(refreshCoalesceMillis)) {
            lock.lock(); defer { lock.unlock() }
            refreshPending = false
            refreshLocked()
        }
    }

    /// Recompute status from the engine and notify if it changed. Under `lock`.
    private static func refreshLocked() {
        guard let e = engine else { return }
        let state: EEState
        if !e.started {
            state = current.state          // ready or stopped: host-driven
        } else if e.remotePaused {
            state = .pausedRemote
        } else if e.scanning {
            state = .running
        } else {
            state = .awaitingPermissions
        }
        transition(composeStatus(state))
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

    // MARK: - Default engine wiring

    private static func defaultEngine(_ config: EEConfig, onChanged: @escaping () -> Void) -> Engine {
        #if canImport(CoreBluetooth) && canImport(CoreLocation) && canImport(Security)
        let workQueue = DispatchQueue(label: "ee-sdk-engine")
        let tokenStore = KeychainTokenStore()
        let dir = (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return Engine(
            config: config,
            tokenStore: tokenStore,
            client: EEClient(tokenProvider: { tokenStore.load() }, baseUrl: config.baseUrl),
            radio: BleScanner(queue: workQueue),
            location: CoreLocationSource(),
            permissionsGranted: { ScanPermissions.granted() },
            queueFileURL: dir.appendingPathComponent(Engine.queueFileName),
            osVersion: platformOSVersion,
            defaultDeviceName: { platformDeviceName },
            workQueue: workQueue,
            onChanged: onChanged
        )
        #else
        // No radio on this platform (the Linux harness): an inert pipeline
        // that honestly parks in awaitingPermissions. Tests override
        // `engineFactory`.
        return Engine(
            config: config,
            tokenStore: InMemoryTokenStore(),
            client: EEClient(tokenProvider: { nil }, transport: { _ in nil }),
            radio: NullRadio(),
            location: NullLocation(),
            permissionsGranted: { false },
            queueFileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(Engine.queueFileName),
            osVersion: platformOSVersion,
            onChanged: onChanged
        )
        #endif
    }

    private static var platformOSVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        #if os(iOS)
        return "iOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        #elseif os(macOS)
        return "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        #else
        return "Linux \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        #endif
    }

    private static var platformDeviceName: String {
        #if canImport(UIKit) && !os(watchOS)
        return UIDevice.current.name
        #else
        return ProcessInfo.processInfo.hostName
        #endif
    }

    /// Test seam: return the facade to factory state between test cases.
    static func _resetForTests() {
        lock.lock(); defer { lock.unlock() }
        engine?.stop()
        engine = nil
        engineConfig = nil
        config = nil
        listener = nil
        current = EEStatus(state: .unconfigured)
        refreshPending = false
        callbackQueue = .main
        refreshCoalesceMillis = 1_000
        engineFactory = EEGateway.defaultEngine
    }
}
