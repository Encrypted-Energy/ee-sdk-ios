import Foundation

/// Disk persistence for the packet queue (plan §1a, iOS 1.1 lesson: a queued
/// packet must survive process death — eid 439e42fd sat on a phone for
/// 56 min because it didn't).
///
/// Format: one packet per line, pipe-delimited (none of the fields can
/// contain '|': base64, hex, decimal numbers). Line 1 is the format marker,
/// shared byte-for-byte with the Android SDK's QueueStore. Writes are
/// atomic (temp-file-then-rename via Foundation) on a single serial queue,
/// coalescing bursts; a torn write costs the file, never a crash — load
/// skips anything malformed.
final class QueueStore {

    private static let formatMarker = "eeq1"

    private let fileURL: URL
    private let writer = DispatchQueue(label: "ee-queue-store")
    private let flag = NSLock()
    private var persistScheduled = false

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Missing/corrupt file -> empty list; malformed lines are skipped.
    func load() -> [UploadPacket] {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return []
        }
        return text.split(separator: "\n").compactMap { Self.decode(String($0)) }
    }

    /// Coalesced async persist; snapshot is taken on the writer queue.
    func schedulePersist(_ queue: PacketQueue) {
        flag.lock()
        let alreadyScheduled = persistScheduled
        persistScheduled = true
        flag.unlock()
        if alreadyScheduled { return }
        writer.async { [weak self] in
            guard let self else { return }
            self.flag.lock()
            self.persistScheduled = false
            self.flag.unlock()
            self.persistNow(queue.snapshot())
        }
    }

    func persistNow(_ packets: [UploadPacket]) {
        var text = Self.formatMarker + "\n"
        for p in packets { text += Self.encode(p) + "\n" }
        // Persistence is best-effort; the live queue is the source of truth
        // and must never be endangered by a disk problem.
        try? text.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    static func encode(_ p: UploadPacket) -> String {
        [
            p.eidHex,
            p.payloadB64,
            String(p.rssi),
            String(p.timestampSeconds),
            String(p.latitude),
            String(p.longitude),
            String(p.positionAtSeconds),
            p.accuracyM.map { String($0) } ?? "",
        ].joined(separator: "|")
    }

    static func decode(_ line: String) -> UploadPacket? {
        let parts = line.components(separatedBy: "|")
        guard parts.count == 8 else { return nil }
        guard !parts[0].isEmpty, !parts[1].isEmpty,
              let rssi = Int(parts[2]),
              let timestamp = Int64(parts[3]),
              let latitude = Double(parts[4]),
              let longitude = Double(parts[5]),
              let positionAt = Int64(parts[6])
        else { return nil }
        let accuracy: Double?
        if parts[7].isEmpty {
            accuracy = nil
        } else if let a = Double(parts[7]) {
            accuracy = a
        } else {
            return nil
        }
        return UploadPacket(
            eidHex: parts[0],
            payloadB64: parts[1],
            rssi: rssi,
            timestampSeconds: timestamp,
            latitude: latitude,
            longitude: longitude,
            positionAtSeconds: positionAt,
            accuracyM: accuracy
        )
    }
}
