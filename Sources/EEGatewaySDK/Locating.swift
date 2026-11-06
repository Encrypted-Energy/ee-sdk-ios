import Foundation

/// The location seam (plan §1a). Darwin conformance below; Engine tests
/// drive a fake. Fix hygiene (null island, range, staleness) lives in
/// LocationFix, and the heartbeat gps_status composition lives in Engine —
/// the seam stays minimal.
protocol LocationSource: AnyObject {
    /// Every accepted fix — feeds nothing yet (scan-policy hook, later).
    var onFix: ((LocationFix) -> Void)? { get set }
    func start()
    func stop()
    /// Fix usable for a packet heard at `nowMillis`, else nil -> drop (§1a).
    func freshFix(nowMillis: Int64) -> LocationFix?
    /// Most recent fix regardless of age — heartbeat last_known_position_at.
    func lastFix() -> LocationFix?
}

#if canImport(CoreLocation)
import CoreLocation

/// CLLocationManager conformance. Deltas from the app's LocationProvider:
/// the 1.3 adaptive power ladder (CoreMotion tiers) is NOT ported — a fixed
/// moderate profile keeps the SDK deterministic on someone else's battery
/// budget; revisit with real partner numbers. The app's fixed-location
/// override is NOT ported either, same reasoning as Android: a
/// partner-settable static location is a coverage-spoofing lever.
///
/// Never prompts: start() is a no-op unless the HOST already obtained
/// authorization (checked by the caller via scanPermissionsGranted;
/// belt-and-braces re-checked here). allowsBackgroundLocationUpdates is set
/// only when the host's Info.plist declares the location background mode —
/// setting it without one throws NSInvalidArgumentException into the host.
final class CoreLocationSource: NSObject, LocationSource {

    var onFix: ((LocationFix) -> Void)?

    private let manager = CLLocationManager()
    private var listening = false
    /// Written on the manager's delegate thread, read from loop threads.
    private let lock = NSLock()
    private var latest: LocationFix?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 10
    }

    func start() {
        guard !listening else { return }
        let status = manager.authorizationStatus
        guard status == .authorizedAlways || status == .authorizedWhenInUse else { return }
        if Self.hostDeclaresLocationBackgroundMode {
            manager.allowsBackgroundLocationUpdates = true
            manager.pausesLocationUpdatesAutomatically = false
        }
        manager.startUpdatingLocation()
        // Seed from the manager's cached fix so a warm start doesn't wait
        // out the first update; the staleness gate decides usability.
        if let cached = manager.location { accept(cached) }
        listening = true
    }

    func stop() {
        guard listening else { return }
        manager.stopUpdatingLocation()
        listening = false
    }

    func freshFix(nowMillis: Int64) -> LocationFix? {
        lock.lock(); defer { lock.unlock() }
        return latest.flatMap { $0.isFresh(nowMillis: nowMillis) ? $0 : nil }
    }

    func lastFix() -> LocationFix? {
        lock.lock(); defer { lock.unlock() }
        return latest
    }

    private func accept(_ location: CLLocation) {
        // LocationFix.of applies the ingest sanity rules (null island,
        // range, time, accuracy bounds) so a junk platform fix never
        // reaches the queue.
        guard let fix = LocationFix.of(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            accuracyM: location.horizontalAccuracy > 0 ? location.horizontalAccuracy : nil,
            capturedAtMillis: Int64(location.timestamp.timeIntervalSince1970 * 1000)
        ) else { return }
        lock.lock()
        latest = fix
        lock.unlock()
        onFix?(fix)
    }

    private static var hostDeclaresLocationBackgroundMode: Bool {
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
        return modes?.contains("location") ?? false
    }
}

extension CoreLocationSource: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        locations.forEach(accept)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Transient by nature; the staleness gate handles a quiet provider.
    }
}
#endif
