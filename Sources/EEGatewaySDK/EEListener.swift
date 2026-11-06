/// Status callback (plan §3). Register one with
/// ``EEGateway/setListener(_:)`` to be told whenever the ``EEStatus``
/// changes instead of polling ``EEGateway/status()``.
///
/// Contract:
///  - Callbacks always arrive on the main queue.
///  - Counter-only changes are coalesced (≤ ~1/s) so a beacon-dense street
///    can't flood the host's main queue; state changes ride the same tick
///    and are never dropped.
///
/// The Android SDK's crash-isolation clause ("a throwing listener is
/// swallowed") has no Swift equivalent: the closure type is non-throwing, so
/// the compiler already guarantees no error propagates. The never-throws
/// contract on the facade itself still holds.
public typealias EEListener = (EEStatus) -> Void
