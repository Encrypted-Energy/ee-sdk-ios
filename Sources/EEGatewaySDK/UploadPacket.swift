/// One BLE packet stamped with a fresh GPS fix, ready for upload (plan §1a).
/// `eidHex` is non-null by construction: the scanner drops eid-less frames
/// before onPacket, and ee-web 422s any batch containing one.
///
/// Port of ee-sdk-android UploadPacket (the app's SwiftData PendingPacket is
/// not SDK material — see NOTES.md).
struct UploadPacket: Equatable {
    let eidHex: String
    let payloadB64: String
    let rssi: Int
    /// When the packet was heard (unix seconds).
    let timestampSeconds: Int64
    let latitude: Double
    let longitude: Double
    /// When the stamped fix was captured (unix seconds) -> `position_at`.
    let positionAtSeconds: Int64
    let accuracyM: Double?
}
