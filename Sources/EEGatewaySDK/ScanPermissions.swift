import Foundation
#if canImport(CoreBluetooth)
import CoreBluetooth
#endif
#if canImport(CoreLocation)
import CoreLocation
#endif

/// Grant check for the pipeline (plan §3): the SDK NEVER requests — it only
/// checks. The host app owns the permission UX; start() without the grants
/// parks in EEState.awaitingPermissions until they appear.
///
/// iOS mapping of the Android SDK's ScanPermissions: Bluetooth authorization
/// (CBManager.authorization == .allowedAlways — iOS Bluetooth has no
/// when-in-use tier) AND location (always or when-in-use; when-in-use means
/// background fixes stop, which surfaces as dropped-no-fix, not as a broken
/// gateway).
enum ScanPermissions {

    #if canImport(CoreBluetooth) && canImport(CoreLocation)
    static func granted() -> Bool {
        CBManager.authorization == .allowedAlways && locationGranted()
    }

    private static func locationGranted() -> Bool {
        let status = CLLocationManager().authorizationStatus
        return status == .authorizedAlways || status == .authorizedWhenInUse
    }
    #endif
}
