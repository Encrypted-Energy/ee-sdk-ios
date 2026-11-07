import Foundation

/// 10 s queue-drain loop (plan §1a). Each tick takes up to one server batch
/// off the queue and hands it to BatchSender, which owns the published
/// contract (413 split, 422 drop + reasons, transient/401 stop). The loop's
/// jobs are the ones BatchSender deliberately doesn't do: pacing, requeueing
/// the undecided remainder in original order, and bumping the forwarded
/// counters.
///
/// Platform-free by design: the wire call is injected and `onOutcome` fires
/// on the loop's task, so every branch unit-tests via `tick()` — no timer,
/// no clock. The engine marshals outcomes onto its own queue.
///
/// Port of ee-sdk-android UploadLoop; ScheduledExecutorService becomes a
/// detached Task with Task.sleep. Android's throwing-callback guards have no
/// counterpart: the closure types here are non-throwing, so the compiler
/// enforces what Android could only catch.
final class UploadLoop {

    static let intervalSeconds: UInt64 = 10
    private static let initialDelaySeconds: UInt64 = 3

    private let ingest: (String) async -> EEClient.Result
    private let queue: PacketQueue
    private let counters: Counters
    private let onOutcome: (BatchSender.Outcome) -> Void

    private var task: Task<Void, Never>?

    init(
        ingest: @escaping (String) async -> EEClient.Result,
        queue: PacketQueue,
        counters: Counters,
        onOutcome: @escaping (BatchSender.Outcome) -> Void = { _ in }
    ) {
        self.ingest = ingest
        self.queue = queue
        self.counters = counters
        self.onOutcome = onOutcome
    }

    func start() {
        guard task == nil else { return }
        task = Task.detached(priority: .utility) { [weak self] in
            try? await Task.sleep(nanoseconds: Self.initialDelaySeconds * 1_000_000_000)
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(nanoseconds: Self.intervalSeconds * 1_000_000_000)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    // 429 cooldown (0.2.0 item vi, from the app's 2026-09-14 storm): a
    // rate-limited server must not be hit every 10 s for the rest of the
    // window. First 429 in a burst arms `cooldownBaseMillis`, each
    // subsequent 429 doubles up to `cooldownCapMillis`; ticks inside the
    // cooldown skip the drain entirely. The first accepted batch resets the
    // ladder. Other transients (network, 5xx) keep the plain cadence —
    // they are not the server asking us to back off. Single-writer: only
    // the loop task (or the test caller) touches these, inside tick().
    static let rateLimitedReason = "HTTP 429"
    static let cooldownBaseMillis: Int64 = 60_000
    static let cooldownCapMillis: Int64 = 15 * 60_000
    private var cooldownUntilMillis: Int64 = 0
    private var cooldownStepMillis: Int64 = 0

    /// Scheduler entry point.
    func tick() async {
        await tick(nowMillis: Int64(Date().timeIntervalSince1970 * 1000))
    }

    /// One drain pass. No-op (and no callback) on an empty queue or while a
    /// 429 cooldown is in force. Test seam: inject the clock.
    func tick(nowMillis: Int64) async {
        if nowMillis < cooldownUntilMillis { return }
        let batch = queue.takeBatch(PacketQueue.maxBatch)
        if batch.isEmpty { return }
        let outcome = await BatchSender.send(batch, ingest: ingest)
        if outcome.forwarded > 0 {
            // The server is accepting again: disarm the ladder.
            cooldownStepMillis = 0
            cooldownUntilMillis = 0
        } else if outcome.transientReason == Self.rateLimitedReason {
            cooldownStepMillis = cooldownStepMillis == 0
                ? Self.cooldownBaseMillis
                : min(cooldownStepMillis * 2, Self.cooldownCapMillis)
            cooldownUntilMillis = nowMillis + cooldownStepMillis
        }
        // Undecided packets (transient/401) go back to the FRONT so a
        // recovered network uploads oldest-first; capacity re-trim drops the
        // stalest if the queue filled meanwhile.
        if !outcome.requeue.isEmpty { queue.requeue(outcome.requeue) }
        counters.forwarded(outcome.forwarded)
        onOutcome(outcome)
    }
}
