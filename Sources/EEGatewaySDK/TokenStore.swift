import Foundation

/// ee_live_ token at rest (plan §1c). The protocol is the Android SDK's
/// TokenStore surface; the production conformance is the Keychain below.
/// Seamed so the provisioning invariants test on Linux with an in-memory
/// store — the Keychain calls themselves compile and round-trip under
/// `swift test` on a Mac, a check the Android Keystore could never get on
/// a JVM.
///
/// The gateway name rides beside the token — it's a display label, not a
/// secret, and keeping it in the same store means both move (or reset)
/// together. Self-mint keeps the server-assigned name for EEStatus
/// surfacing.
protocol TokenStore: AnyObject {
    func load() -> String?
    /// Best-effort, like the Android save: a storage failure leaves the
    /// previous state and the next start()'s provisioning reconciles.
    func save(_ token: String)
    /// Removes token AND gateway name.
    func clear()
    func loadGatewayName() -> String?
    func saveGatewayName(_ name: String)
}

#if canImport(Security)
import Security

/// Keychain conformance, ported from the app's KeychainStore with the names
/// SDK-namespaced: its own service string, so the SDK can never collide with
/// the host app's keychain items — including the first-party EE app
/// (service "com.encryptedenergy.gateway") if both ever share a device.
///
/// No TokenCrypto layer here, deliberately: Android needed Keystore AES-GCM
/// because SharedPreferences is plaintext on disk; the Keychain IS the
/// platform secure store (encrypted at rest, hardware-backed), and a second
/// envelope would add key-management failure modes for zero added secrecy.
final class KeychainTokenStore: TokenStore {

    /// SDK-owned namespace — never the host app's, never the EE app's.
    private static let service = "com.encryptedenergy.sdk"
    private static let tokenAccount = "ee_live_token"
    private static let nameAccount = "gateway_name"

    func load() -> String? { read(Self.tokenAccount) }

    func save(_ token: String) { write(Self.tokenAccount, token) }

    func clear() {
        delete(Self.tokenAccount)
        delete(Self.nameAccount)
    }

    func loadGatewayName() -> String? { read(Self.nameAccount) }

    func saveGatewayName(_ name: String) { write(Self.nameAccount, name) }

    // MARK: - SecItem plumbing (upsert/read/delete, app-parity)

    private func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
        ]
    }

    private func write(_ account: String, _ value: String) {
        let data = Data(value.utf8)
        // Upsert: try update first, add if absent.
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery(account) as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery(account)
            add[kSecValueData as String] = data
            // Available after first unlock so background BLE relaunches can
            // read it (carried from the app).
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    private func read(_ account: String) -> String? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func delete(_ account: String) {
        SecItemDelete(baseQuery(account) as CFDictionary)
    }
}
#endif
