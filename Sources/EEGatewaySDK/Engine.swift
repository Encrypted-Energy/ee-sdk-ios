import Foundation

/// The pipeline owner behind EEGateway (plan §5 S5/S6): scanner, location,
/// queue, heartbeat, upload. This is the Android SDK's Engine adapted to
/// iOS, minus what S6 adds there (provisioning orchestration, the remote
/// kill switch, public-id capture) — and minus the product surface the app
/// kept, same as Android.
///
/// ## Dormancy gate
/// start() with grants missing runs the heartbeat/upload loops (ops can see
/// a dormant fleet phone — gps_status `dongle_missing`, status
/// `backgrounded`) but leaves the radio and GPS untouched, and polls the
/// grants every `pollInterval`. The moment the host obtains them, the
/// pipeline starts on its own — awaitingPermissions → running with no
/// further host call. A mid-run revocation (radio lands in .unauthorized)
/// tears the pipeline down and returns to the same poll, so the state
/// machine is honest in both directions.
///
/// ## Threading
/// start()/stop() may be called from any thread (the facade's contract);
/// all pipeline mutation runs on `workQueue`, where the radio and location
/// callbacks also arrive (the Darwin adapters are constructed with it).
/// Facade-visible tallies are written under `stateLock` and read through
/// the thread-safe getters from arbitrary threads. `onChanged` fires
/// (possibly once per heard advertisement) on whatever thread produced the
/// change; the facade coalesces before notifying the host's listener.
///
/// Unlike Android's Engine (stub-compiled only, dogfood-checked), this one
/// is fully exercised on Linux through the PacketRadio/LocationSource seams.
final class Engine {

    static let defaultPollInterval: TimeInterval = 5
    /// SDK-namespaced (C4 rule): never collides with a host or the
    /// first-party app sharing the container.
    static let queueFileName = "com.encryptedenergy.sdk.packet-queue.eeq"

    private let radio: PacketRadio
    private let location: LocationSource
    private let permissionsCheck: () -> Bool
    private let onChanged: () -> Void
    private let osVersion: String
    private let pollInterval: TimeInterval

    let counters = Counters()
    private let queue: PacketQueue
    private let store: QueueStore
    private var heartbeatLoop: HeartbeatLoop!
    private var uploadLoop: UploadLoop!

    /// All pipeline mutation happens here; radio/location callbacks arrive
    /// here (Darwin adapters are constructed with this queue).
    let workQueue: DispatchQueue

    // Facade-visible state: written on workQueue or a loop task, read from
    // any thread via the getters.
    private let stateLock = NSLock()
    private var _pingsHeard: Int64 = 0
    private var _packetsForwarded: Int64 = 0
    private var _lastHeartbeatAt: Int64?
    private var _lastPacketAtMillis: Int64?
    private var _started = false
    private var _scanning = false
    private var rollup = DeviceRollup()

    private let startedAt = Date()

    init(
        client: EEClient,
        radio: PacketRadio,
        location: LocationSource,
        permissionsGranted: @escaping () -> Bool,
        queueFileURL: URL,
        osVersion: String,
        queue: PacketQueue = PacketQueue(),
        workQueue: DispatchQueue = DispatchQueue(label: "ee-sdk-engine"),
        pollInterval: TimeInterval = Engine.defaultPollInterval,
        onChanged: @escaping () -> Void
    ) {
        self.radio = radio
        self.location = location
        self.permissionsCheck = permissionsGranted
        self.osVersion = osVersion
        self.queue = queue
        self.workQueue = workQueue
        self.pollInterval = pollInterval
        self.onChanged = onChanged
        self.store = QueueStore(fileURL: queueFileURL)

        // Restore packets that survived process death — OFF the caller's
        // thread: configure()/start() may run on the host's main thread, and
        // a disk read there is a hang seed. Persistence arms only after the
        // restore, so loading through add() can't trigger a rewrite per
        // line; anything heard in the gap persists on the next queue change
        // (the 10 s upload tick at the latest).
        workQueue.async { [store, queue, onChanged] in
            store.load().forEach { queue.add($0) }
            queue.onChange = { [weak store, weak queue] in
                guard let store, let queue else { return }
                store.schedulePersist(queue)
            }
            onChanged()
        }

        wireRadio()

        heartbeatLoop = HeartbeatLoop(
            heartbeat: { [client] in await client.heartbeat($0) },
            counters: counters,
            runtimeInfo: { [weak self] in self?.runtimeInfo() ?? Engine.emptyRuntime }
        ) { [weak self] result in
            guard let self else { return }
            if case .ok = result {
                self.stateLock.lock()
                self._lastHeartbeatAt = Int64(Date().timeIntervalSince1970 * 1000)
                self.stateLock.unlock()
                // S6 acts on `disable` and captures publicId here.
            }
            self.onChanged()
        }
        uploadLoop = UploadLoop(
            ingest: { [client] in await client.ingest($0) },
            queue: queue,
            counters: counters
        ) { [weak self] outcome in
            guard let self else { return }
            self.stateLock.lock()
            self._packetsForwarded += Int64(outcome.forwarded)
            self.stateLock.unlock()
            self.onChanged()
        }
    }

    // MARK: - Facade-visible state

    var pingsHeard: Int64 { stateLock.lock(); defer { stateLock.unlock() }; return _pingsHeard }
    var packetsForwarded: Int64 { stateLock.lock(); defer { stateLock.unlock() }; return _packetsForwarded }
    var lastHeartbeatAt: Int64? { stateLock.lock(); defer { stateLock.unlock() }; return _lastHeartbeatAt }
    /// Host asked us to run (start() without a matching stop()).
    var started: Bool { stateLock.lock(); defer { stateLock.unlock() }; return _started }
    /// Radio + GPS actually up — false while dormant on missing grants.
    var scanning: Bool { stateLock.lock(); defer { stateLock.unlock() }; return _scanning }

    func queueDepth() -> Int { queue.size() }
    func permissionsGranted() -> Bool { permissionsCheck() }

    // MARK: - Lifecycle (any thread)

    /// Begin: loops immediately (heartbeats make dormant phones visible to
    /// ops), pipeline when the grants allow. Idempotent.
    func start() {
        stateLock.lock()
        if _started { stateLock.unlock(); return }
        _started = true
        stateLock.unlock()
        heartbeatLoop.start()
        uploadLoop.start()
        workQueue.async { [weak self] in self?.maybeStartPipeline() }
    }

    /// Stop everything. Idempotent.
    func stop() {
        stateLock.lock()
        if !_started { stateLock.unlock(); return }
        _started = false
        stateLock.unlock()
        heartbeatLoop.stop()
        uploadLoop.stop()
        workQueue.async { [weak self] in self?.stopPipeline() }
    }

    // MARK: - Pipeline (workQueue only)

    private func maybeStartPipeline() {
        guard started, !scanning else { return }
        if permissionsCheck() {
            startPipeline()
        } else {
            schedulePermissionPoll()
        }
        onChanged()
    }

    /// The dormancy gate's clock: cheap grant checks, workQueue, only while
    /// started-but-dormant. No cancel handle — a late fire re-checks the
    /// flags and is a no-op after stop().
    private func schedulePermissionPoll() {
        workQueue.asyncAfter(deadline: .now() + pollInterval) { [weak self] in
            guard let self, self.started, !self.scanning else { return }
            if self.permissionsCheck() {
                self.startPipeline()
                self.onChanged()
            } else {
                self.schedulePermissionPoll()
            }
        }
    }

    private func startPipeline() {
        guard !scanning else { return }
        location.start()
        setScanning(true)
        radio.start()
        // A grant revoked between the permission check and the radio call
        // surfaces as a SYNCHRONOUS .unauthorized inside radio.start(): the
        // onState handler tears the pipeline back down (scanning must
        // already be true for it to act — hence the order above).
    }

    private func stopPipeline() {
        guard scanning else { return }
        radio.stop()
        location.stop()
        setScanning(false)
    }

    private func setScanning(_ value: Bool) {
        stateLock.lock()
        _scanning = value
        stateLock.unlock()
    }

    // MARK: - Radio wiring (callbacks arrive on workQueue)

    private func wireRadio() {
        radio.onState = { [weak self] state in
            guard let self else { return }
            // Mid-run revocation: the radio said no. Back to dormant; the
            // poll re-arms and the pipeline resumes if the grant returns.
            if state == .unauthorized && self.scanning {
                self.stopPipeline()
                if self.started { self.schedulePermissionPoll() }
            }
            self.onChanged()
        }
        radio.onHeard = { [weak self] parsed, rssi, at in
            guard let self else { return }
            self.stateLock.lock()
            self._pingsHeard += 1
            if let eid = parsed.eidHex {
                self.rollup.heard(eid: eid, rssi: rssi, at: at)
            }
            self.stateLock.unlock()
            self.counters.heardPacket()
            if parsed.eidHex == nil { self.counters.droppedNoEIDFrame() }
            self.onChanged()
        }
        radio.onPacket = { [weak self] parsed, rssi, at in
            guard let self, let eid = parsed.eidHex else { return }
            let heardMillis = Int64(at.timeIntervalSince1970 * 1000)
            guard let fix = self.location.freshFix(nowMillis: heardMillis) else {
                // No fix fresher than 25 s: drop, never stamp stale coords
                // (the 7/31 incident).
                self.counters.droppedNoFix()
                self.onChanged()
                return
            }
            self.queue.add(
                UploadPacket(
                    eidHex: eid,
                    payloadB64: parsed.payload.base64EncodedString(),
                    rssi: rssi,
                    timestampSeconds: heardMillis / 1000,
                    latitude: fix.latitude,
                    longitude: fix.longitude,
                    positionAtSeconds: fix.capturedAtMillis / 1000,
                    accuracyM: fix.accuracyM
                )
            )
            self.stateLock.lock()
            self._lastPacketAtMillis = heardMillis
            self.stateLock.unlock()
            self.onChanged()
        }
    }

    // MARK: - Heartbeat runtime (called from the heartbeat task)

    func runtimeInfo() -> HeartbeatPayload.Runtime {
        let nowMillis = Int64(Date().timeIntervalSince1970 * 1000)
        stateLock.lock()
        let lastPacket = _lastPacketAtMillis
        let active = _scanning
        let devices = rollup.heartbeatRaw()
        stateLock.unlock()
        // gps_status (§1b): permission denied maps to dongle_missing —
        // composed here from the seam so LocationSource stays minimal.
        let gpsStatus: String
        if !permissionsCheck() {
            gpsStatus = "dongle_missing"
        } else if location.freshFix(nowMillis: nowMillis) != nil {
            gpsStatus = "fix"
        } else {
            gpsStatus = "no_fix"
        }
        return HeartbeatPayload.Runtime(
            osVersion: osVersion,
            uptimeSeconds: Int64(Date().timeIntervalSince(startedAt)),
            lastPacketAtMillis: lastPacket,
            gpsStatus: gpsStatus,
            lastKnownPositionAtMillis: location.lastFix()?.capturedAtMillis,
            // "active" = radio up and earning; a dormant or stopped SDK
            // reports "backgrounded", matching what the silent-gateway
            // tooling expects from a phone that isn't scanning.
            clientState: active ? "active" : "backgrounded",
            devicesSeen: devices,
            // scan_mode omitted: no adaptive scan policy in the iOS SDK v1
            // (see NOTES.md — background scans are OS-coalesced).
            scanMode: nil
        )
    }

    private static let emptyRuntime = HeartbeatPayload.Runtime(
        osVersion: "", uptimeSeconds: 0, lastPacketAtMillis: nil, gpsStatus: "no_fix"
    )
}
