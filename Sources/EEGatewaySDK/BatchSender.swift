/// Batch semantics for packet upload, per the published ingest contract
/// (ee-web /docs):
///
///  - at most `maxBatch` packets per request — pre-chunked here;
///  - 413 (server disagrees about the limit): split the batch and resend;
///  - 422: drop the chunk — retrying can't help — and surface the body's
///    `invalid_reasons`;
///  - other non-401 4xx: drop (ee-web already said it will never be
///    accepted);
///  - 401: stop, return everything unsent — the operator's token is the
///    problem, not the packets;
///  - 502/5xx/408/429/network: stop, return everything unsent for the next
///    pass (the S5 loop requeues; pacing is the loop's job).
///
/// Pure Foundation: the wire call is injected, so every branch above
/// unit-tests without HTTP. The S5 upload loop wires this to EEClient.ingest
/// and PacketQueue.
///
/// Port of ee-sdk-android BatchSender. Note the SDK follows the Android
/// batch contract (500/chunk against the server cap), not the app's modest
/// 10/batch — one fleet phone can drain a long-offline queue in two calls.
enum BatchSender {

    /// ee-web MAX_PACKETS_PER_REQUEST — Hubble's per-upload ceiling.
    static let maxBatch = 500

    /// What one `send` pass did. `requeue` is every packet that was not
    /// decided (transient failure or 401) in original order — the caller
    /// puts them back. `droppedReasons` carries 422 `invalid_reasons` lines
    /// for diagnostics.
    struct Outcome: Equatable {
        let forwarded: Int
        let bountyEarned: Int
        let dropped: Int
        let droppedReasons: [String]
        let requeue: [UploadPacket]
        let unauthorized: Bool
        let transientReason: String?
    }

    /// Send `batch` through `ingest` (one wire call per ≤`maxBatch` chunk),
    /// applying the contract above. Stops at the first transient/401
    /// outcome; everything undecided comes back in `Outcome.requeue`. A
    /// throwing `ingest` (an S5 wiring mistake — EEClient.ingest itself
    /// never throws) is treated as transient so it can't kill the loop.
    static func send(
        _ batch: [UploadPacket],
        ingest: (String) async throws -> EEClient.Result
    ) async -> Outcome {
        var forwarded = 0
        var bounty = 0
        var dropped = 0
        var reasons: [String] = []
        var pending: [[UploadPacket]] = stride(from: 0, to: batch.count, by: maxBatch).map {
            Array(batch[$0..<min($0 + maxBatch, batch.count)])
        }

        while !pending.isEmpty {
            let chunk = pending.removeFirst()
            let result: EEClient.Result
            do {
                result = try await ingest(PacketJson.body(chunk))
            } catch {
                result = .transient(reason: String(describing: type(of: error)))
            }
            switch result {
            case .ok(_, let bountyEarned, _, _):
                forwarded += chunk.count
                bounty += bountyEarned
            case .unauthorized:
                return Outcome(
                    forwarded: forwarded, bountyEarned: bounty, dropped: dropped,
                    droppedReasons: reasons,
                    requeue: chunk + pending.flatMap { $0 },
                    unauthorized: true, transientReason: nil
                )
            case .transient(let reason):
                return Outcome(
                    forwarded: forwarded, bountyEarned: bounty, dropped: dropped,
                    droppedReasons: reasons,
                    requeue: chunk + pending.flatMap { $0 },
                    unauthorized: false, transientReason: reason
                )
            case .terminal(let code, let body):
                if code == 413 && chunk.count > 1 {
                    // Server's limit is lower than ours: halve until it
                    // fits. A size-1 413 falls through to the drop arm —
                    // unsplittable, and retrying can't change the answer.
                    let mid = chunk.count / 2
                    pending.insert(Array(chunk[mid...]), at: 0)
                    pending.insert(Array(chunk[..<mid]), at: 0)
                } else {
                    dropped += chunk.count
                    if code == 422 {
                        reasons += EEClient.parseInvalidReasons(body)
                    }
                }
            }
        }
        return Outcome(
            forwarded: forwarded, bountyEarned: bounty, dropped: dropped,
            droppedReasons: reasons, requeue: [], unauthorized: false,
            transientReason: nil
        )
    }
}
