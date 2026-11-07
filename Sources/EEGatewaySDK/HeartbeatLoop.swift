import Foundation

/// Heartbeat loop (plan §1b): fires immediately on start, then every
/// `intervalSeconds`. The SDK's cadence is 3 MINUTES, not the first-party
/// app's 60 s — conservative battery/network cost on someone else's fleet is
/// a hard contract (plan §6 risk 3), and the architecture diagram pins it.
///
/// Deltas are snapshot-and-reset before the POST and restored on transient
/// failure so nothing is lost; terminal failures (401/4xx) drop the
/// snapshot, copying the Pi worker. A 2xx carries the C9 `disable`
/// kill-switch flag through `onResult` — surfaced here, ACTED ON in S6.
///
/// Platform-free by design: the wire call is injected and `onResult` fires
/// on the loop's task, so every branch unit-tests via `tick()`.
///
/// Port of ee-sdk-android HeartbeatLoop (same Task-for-executor and
/// non-throwing-closure deltas as UploadLoop).
final class HeartbeatLoop {

    /// 3 min — the SDK's conservative fleet cadence (300 s at launch;
    /// tightened to 180 s per John 11/6 after first-device dogfood).
    static let intervalSeconds: UInt64 = 180

    private let heartbeat: (String) async -> EEClient.Result
    private let counters: Counters
    private let runtimeInfo: () -> HeartbeatPayload.Runtime
    private let onResult: (EEClient.Result) -> Void

    private var task: Task<Void, Never>?

    init(
        heartbeat: @escaping (String) async -> EEClient.Result,
        counters: Counters,
        runtimeInfo: @escaping () -> HeartbeatPayload.Runtime,
        onResult: @escaping (EEClient.Result) -> Void = { _ in }
    ) {
        self.heartbeat = heartbeat
        self.counters = counters
        self.runtimeInfo = runtimeInfo
        self.onResult = onResult
    }

    func start() {
        guard task == nil else { return }
        task = Task.detached(priority: .utility) { [weak self] in
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

    /// One heartbeat POST.
    func tick() async {
        let snapshot = counters.takeSnapshot()
        let result = await heartbeat(HeartbeatPayload.build(runtimeInfo(), snapshot))
        if case .transient = result {
            counters.restore(snapshot)
        }
        onResult(result)
    }
}
