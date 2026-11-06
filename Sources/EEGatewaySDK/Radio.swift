import Foundation

/// What the radio reported last. Mirrors the app scanner's State.
enum RadioState: Equatable {
    case scanning, poweredOff, unauthorized, unsupported, idle
}

/// The scanning seam. The Darwin conformance below ports the app's
/// BLEScanner; Engine tests drive a fake, so the dormancy gate and packet
/// path are provable on Linux — coverage the Android Engine (stub-compiled
/// only) never had.
protocol PacketRadio: AnyObject {
    var onState: ((RadioState) -> Void)? { get set }
    /// Every FCA6 advertisement, pre-throttle: (parsed, rssi, heardAt).
    var onHeard: ((ParsedPacket, Int, Date) -> Void)? { get set }
    /// Only packets with an EID that passed the per-EID throttle. Caller
    /// attaches the current GPS fix and enqueues, or drops without one (§4).
    var onPacket: ((ParsedPacket, Int, Date) -> Void)? { get set }
    func start()
    func stop()
}

#if canImport(CoreBluetooth)
import CoreBluetooth

/// FCA6 scan loop (plan §2, §4), ported from the app's BLEScanner with the
/// SDK deltas:
///
///  - **Never prompts (plan §3).** Instantiating CBCentralManager is what
///    fires the system Bluetooth dialog, so `start()` refuses to create one
///    while authorization is .notDetermined and reports `.unauthorized`
///    instead — the engine's dormancy poll retries after the HOST obtains
///    the grant. The app's O2-primer `prepare()` dance has no SDK
///    counterpart.
///  - **No foreground duty cycle.** The app's 10s/30s cycle is a
///    foreground product feature driven by its UI state; an embedded SDK is
///    background-first, where iOS already coalesces service-filtered scans.
///    (Battery honesty per plan §6 risk 3 — documented in NOTES.md.)
///  - **Per-EID throttle rides the shared EidThrottle** (3 s, same window
///    as the app's inline map and the Android SDK).
///  - **SDK-namespaced restore identifier** — never the app's.
///
/// Callbacks arrive on the queue handed to init (the engine's serial queue).
final class BleScanner: NSObject, PacketRadio {

    static let serviceUUID = CBUUID(string: "FCA6")
    private static let restoreID = "com.encryptedenergy.sdk.central"
    private static let perEIDThrottleMillis: Int64 = 3_000

    var onState: ((RadioState) -> Void)?
    var onHeard: ((ParsedPacket, Int, Date) -> Void)?
    var onPacket: ((ParsedPacket, Int, Date) -> Void)?

    private let queue: DispatchQueue
    private var central: CBCentralManager?
    private let throttle = EidThrottle(windowMillis: BleScanner.perEIDThrottleMillis)
    private var wantScanning = false

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    func start() {
        wantScanning = true
        // Creating the manager while undetermined would PROMPT — contract
        // violation. Report unauthorized; the dormancy poll re-enters start()
        // after the host's own permission flow runs.
        guard CBManager.authorization != .notDetermined else {
            onState?(.unauthorized)
            return
        }
        if central == nil {
            central = CBCentralManager(
                delegate: self,
                queue: queue,
                options: [CBCentralManagerOptionRestoreIdentifierKey: Self.restoreID]
            )
        }
        startIfPoweredOn()
    }

    func stop() {
        wantScanning = false
        if central?.state == .poweredOn { central?.stopScan() }
        onState?(.idle)
    }

    private func startIfPoweredOn() {
        guard wantScanning, let central, central.state == .poweredOn else { return }
        central.scanForPeripherals(
            withServices: [Self.serviceUUID],
            // Duplicates are coalesced in the background regardless; fine (§6).
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        onState?(.scanning)
    }
}

extension BleScanner: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: startIfPoweredOn()
        case .poweredOff: onState?(.poweredOff)
        case .unauthorized: onState?(.unauthorized)
        case .unsupported: onState?(.unsupported)
        default: break
        }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        // Relaunched after jetsam mid-scan: resume the persisted intent.
        wantScanning = true
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data],
              let raw = serviceData[Self.serviceUUID],
              let parsed = HubblePacketParser.parse(raw) else { return }
        let now = Date()
        onHeard?(parsed, RSSI.intValue, now)

        // No EID -> never forwarded: one bad packet 422s the whole batch (§1a).
        guard let eid = parsed.eidHex else { return }
        guard throttle.shouldForward(eid: eid, nowMillis: Int64(now.timeIntervalSince1970 * 1000)) else { return }
        onPacket?(parsed, RSSI.intValue, now)
    }
}
#endif
