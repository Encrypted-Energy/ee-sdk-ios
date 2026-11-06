import Foundation

/// A GPS fix eligible for stamping onto packets (plan §1a). Pure Foundation
/// so the staleness gate and ingest sanity rules unit-test without a device.
///
/// Construct via `of`, never directly from platform values: ee-web validates
/// per-packet fields and rejects the ENTIRE batch over one bad value, so a
/// single junk fix must be filtered here, not discovered server-side.
///
/// `accuracyM` is nil when the platform fix carried no usable accuracy
/// estimate; PacketJson omits accuracy_m in that case (the field is optional
/// server-side).
///
/// Port of ee-sdk-android LocationFix.
struct LocationFix: Equatable {
    let latitude: Double
    let longitude: Double
    let accuracyM: Double?
    /// When the fix was captured (epoch millis) — becomes `position_at`.
    let capturedAtMillis: Int64

    /// The 25 s staleness gate, same constant as iOS 1.2 fixForPacket and
    /// the Pi worker's GPS TTL. A stale fix must never be stamped on a
    /// packet — that was the whole stale-location incident (7/31).
    /// Future-dated fixes (clock skew) count as fresh; the server clamps.
    func isFresh(nowMillis: Int64) -> Bool {
        nowMillis - capturedAtMillis <= Self.maxAgeMillis
    }

    static let maxAgeSeconds: Int64 = 25
    static let maxAgeMillis: Int64 = maxAgeSeconds * 1000

    /// ee-web rejects accuracy_m > 10000; a >10 km fix is also useless.
    static let maxAccuracyM = 10_000.0

    /// Applies ee-web's ingest sanity rules client-side:
    /// - non-finite lat/lon -> nil: NaN slips through the range check
    ///   (abs(NaN) > 90 is false) and would only fail later inside JSON
    ///   serialization.
    /// - (0, 0) -> nil: the null-island tell, batch-rejected upstream.
    /// - lat/lon out of range -> nil: batch-rejected upstream.
    /// - capture time <= 0 -> nil: can't pass an honest staleness gate, and
    ///   position_at <= 0 is batch-rejected upstream.
    /// - accuracy > 10 km -> nil: coverage-useless, and batch-rejected
    ///   upstream.
    /// - accuracy <= 0 or absent -> fix kept, accuracy omitted (optional
    ///   field; <= 0 is batch-rejected upstream).
    static func of(
        latitude: Double,
        longitude: Double,
        accuracyM: Double?,
        capturedAtMillis: Int64
    ) -> LocationFix? {
        if !latitude.isFinite || !longitude.isFinite { return nil }
        if latitude == 0.0 && longitude == 0.0 { return nil }
        if abs(latitude) > 90.0 || abs(longitude) > 180.0 { return nil }
        if capturedAtMillis <= 0 { return nil }
        if let a = accuracyM, !a.isFinite || a > maxAccuracyM { return nil }
        return LocationFix(
            latitude: latitude,
            longitude: longitude,
            accuracyM: accuracyM.flatMap { $0 > 0.0 ? $0 : nil },
            capturedAtMillis: capturedAtMillis
        )
    }
}
