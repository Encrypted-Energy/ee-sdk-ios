/// The retry brain around TokenProvision (plan §3, S6): run provisioning
/// attempts until the server gives a verdict, sleeping out Backoff delays
/// between transient failures, and parking permanently on a rejection.
///
/// Rejection parks because retrying cannot change a deliberate server "no"
/// (revoked/typo'd token, failed mint shape): the SDK stays quiet until the
/// next EEGateway.start() — a new configure()+start with a rotated token is
/// the partner's recovery path, and every engine start re-runs provisioning
/// when the stored token doesn't match the config.
///
/// Pure: the attempt, the sleep, and liveness are injected, so the policy
/// unit-tests without tasks, HTTP, or a clock. In production the sleep is
/// Task.sleep inside the provisioning task; engine stop cancels it (the
/// sleep returns false — Android's InterruptedException).
///
/// Port of ee-sdk-android ProvisionRunner.
final class ProvisionRunner {

    /// What one provisioning attempt concluded.
    enum Outcome { case provisioned, rejected, retry }

    /// What the whole run concluded.
    enum Result { case provisioned, rejected, abandoned }

    private let attempt: () async -> Outcome
    private let backoff: Backoff
    /// Sleep `millis`; false means the sleep was cancelled (engine stopped).
    private let sleep: (Int64) async -> Bool

    init(
        attempt: @escaping () async -> Outcome,
        backoff: Backoff = Backoff(),
        sleep: @escaping (Int64) async -> Bool
    ) {
        self.attempt = attempt
        self.backoff = backoff
        self.sleep = sleep
    }

    /// Attempt until a verdict, or until `isActive` goes false (the engine
    /// stopped) or the sleep is cancelled. abandoned is not a verdict: the
    /// next start() tries again from scratch.
    func run(isActive: () -> Bool) async -> Result {
        while isActive() {
            switch await attempt() {
            case .provisioned:
                return .provisioned
            case .rejected:
                return .rejected
            case .retry:
                let sleptOut = await sleep(backoff.nextDelayMillis())
                if !sleptOut { return .abandoned }
            }
        }
        return .abandoned
    }
}
