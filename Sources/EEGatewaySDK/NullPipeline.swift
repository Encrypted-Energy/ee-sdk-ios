import Foundation

/// Inert seam conformances. They back the facade's default engine factory on
/// platforms without CoreBluetooth/CoreLocation (the Linux harness), where a
/// started gateway honestly parks in awaitingPermissions forever — there is
/// no radio to wait for. Tests override the factory with real fakes.
final class NullRadio: PacketRadio {
    var onState: ((RadioState) -> Void)?
    var onHeard: ((ParsedPacket, Int, Date) -> Void)?
    var onPacket: ((ParsedPacket, Int, Date) -> Void)?
    func start() { onState?(.unsupported) }
    func stop() {}
}

final class NullLocation: LocationSource {
    var onFix: ((LocationFix) -> Void)?
    func start() {}
    func stop() {}
    func freshFix(nowMillis: Int64) -> LocationFix? { nil }
    func lastFix() -> LocationFix? { nil }
}

/// In-memory TokenStore: the Linux fallback factory's store, and the test
/// double for provisioning flows.
final class InMemoryTokenStore: TokenStore {
    private let lock = NSLock()
    private var token: String?
    private var gatewayName: String?

    func load() -> String? { lock.lock(); defer { lock.unlock() }; return token }
    func save(_ token: String) { lock.lock(); defer { lock.unlock() }; self.token = token }
    func clear() { lock.lock(); defer { lock.unlock() }; token = nil; gatewayName = nil }
    func loadGatewayName() -> String? { lock.lock(); defer { lock.unlock() }; return gatewayName }
    func saveGatewayName(_ name: String) { lock.lock(); defer { lock.unlock() }; gatewayName = name }
}
