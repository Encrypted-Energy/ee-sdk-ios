import Foundation

/// Bounded FIFO between the scan callback and the upload loop (plan §1a).
/// Overflow drops the OLDEST packet — recent coverage is worth more than
/// stale backlog, and the bound keeps a dead network from growing the heap
/// forever.
///
/// `onChange` fires after any mutation that changed contents; the engine
/// uses it to schedule a QueueStore persist so the queue survives process
/// death. The callback must be cheap and non-blocking (it runs under the
/// queue's lock, same as the Android SDK's @Synchronized methods).
///
/// Port of ee-sdk-android PacketQueue. Android's @Volatile onChange becomes
/// lock-guarded access here — same visibility guarantee, one mechanism.
final class PacketQueue {

    static let defaultCapacity = 1_000
    /// ee-web MAX_PACKETS_PER_REQUEST — larger batches 413.
    static let maxBatch = 500

    private let lock = NSLock()
    private var deque: [UploadPacket] = []
    private var changeHandler: (() -> Void)?
    private let capacity: Int

    init(capacity: Int = PacketQueue.defaultCapacity) {
        self.capacity = capacity
    }

    var onChange: (() -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return changeHandler }
        set { lock.lock(); defer { lock.unlock() }; changeHandler = newValue }
    }

    func add(_ packet: UploadPacket) {
        lock.lock(); defer { lock.unlock() }
        if deque.count >= capacity { deque.removeFirst() }
        deque.append(packet)
        changeHandler?()
    }

    /// Removes and returns up to `max` packets, oldest first.
    func takeBatch(_ max: Int = PacketQueue.maxBatch) -> [UploadPacket] {
        lock.lock(); defer { lock.unlock() }
        let n = Swift.min(max, deque.count)
        let batch = Array(deque.prefix(n))
        deque.removeFirst(n)
        if n > 0 { changeHandler?() }
        return batch
    }

    /// Returns a failed batch to the FRONT in original order (transient
    /// failure — retry next tick). Re-trims to capacity, dropping oldest.
    func requeue(_ batch: [UploadPacket]) {
        guard !batch.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        deque.insert(contentsOf: batch, at: 0)
        if deque.count > capacity { deque.removeFirst(deque.count - capacity) }
        changeHandler?()
    }

    /// Copy of current contents, oldest first — used for persistence.
    func snapshot() -> [UploadPacket] {
        lock.lock(); defer { lock.unlock() }
        return deque
    }

    func size() -> Int {
        lock.lock(); defer { lock.unlock() }
        return deque.count
    }

    func clear() {
        lock.lock(); defer { lock.unlock() }
        guard !deque.isEmpty else { return }
        deque.removeAll()
        changeHandler?()
    }
}
