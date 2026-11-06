import Foundation
@testable import EEGatewaySDK

/// Shared seam fakes for Engine and facade suites.
final class FakeRadio: PacketRadio {
    var onState: ((RadioState) -> Void)?
    var onHeard: ((ParsedPacket, Int, Date) -> Void)?
    var onPacket: ((ParsedPacket, Int, Date) -> Void)?
    var startCalls = 0
    var stopCalls = 0
    /// When set, start() synchronously reports this state — the
    /// revoked-between-check-and-call race.
    var stateOnStart: RadioState?

    func start() {
        startCalls += 1
        if let state = stateOnStart { onState?(state) }
    }

    func stop() { stopCalls += 1 }
}

final class FakeLocation: LocationSource {
    var onFix: ((LocationFix) -> Void)?
    var startCalls = 0
    var stopCalls = 0
    var fix: LocationFix?

    func start() { startCalls += 1 }
    func stop() { stopCalls += 1 }
    func freshFix(nowMillis: Int64) -> LocationFix? {
        fix.flatMap { $0.isFresh(nowMillis: nowMillis) ? $0 : nil }
    }
    func lastFix() -> LocationFix? { fix }
}
