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

    /// One drain pass. No-op (and no callback) on an empty queue.
    func tick() async {
        let batch = queue.takeBatch(PacketQueue.maxBatch)
        if batch.isEmpty { return }
        let outcome = await BatchSender.send(batch, ingest: ingest)
        // Undecided packets (transient/401) go back to the FRONT so a
        // recovered network uploads oldest-first; capacity re-trim drops the
        // stalest if the queue filled meanwhile.
        if !outcome.requeue.isEmpty { queue.requeue(outcome.requeue) }
        counters.forwarded(outcome.forwarded)
        onOutcome(outcome)
    }
}
