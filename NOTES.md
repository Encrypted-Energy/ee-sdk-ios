# Build notes — ee-sdk-ios

Decisions and caveats, chunk by chunk, for John and future chunks. Mirrors
the Android arc (ee-sdk-android C1–C10); iOS chunks are S1–S7 + shared
C9/C10. Extraction source: `gateway-ios` branch `anonymous-first-onboarding`
(131c3f5) — the shipped 1.5 app.

## Arc map

| Chunk | Scope | Status |
|---|---|---|
| S1 | SPM scaffold, frozen public API (EEGateway/EEConfig/EEStatus/EEState/EEListener), Linux harness | DONE 11/6 |
| S2 | Pure core: HubblePacketParser, Counters, DeviceRollup, PacketQueue (de-SwiftData'd), Backoff/EidThrottle (new ports — app had none; Android SDK is the spec), payload builders | parser+counters+rollup DONE 11/6; rest open |
| S3 | Headless EEClient (mint, claim-status, ingest, heartbeat; URLSession) | open |
| S4 | TokenStore (Keychain; protocol seam so logic tests on Linux) | open |
| S5 | Pipeline: CBCentralManager scanner + CoreLocation via seams, loops, Engine, dormancy gate | open |
| S6 | Guardrails: ProvisionRunner, PAUSED_REMOTE kill switch, publicId from heartbeat | open |
| S7 | Minimal sample app (Xcode project — John's Mac) | open |

## Toolchain / harness

- Swift 6.0.3 Linux toolchain at `/home/clawuser/toolchain/swift` (swift.org
  tarball, Ubuntu 24.04). `./runtests.sh` = `swift test` with that toolchain.
- Pure-Foundation sources test natively on Linux — no stub modules needed so
  far. CoreBluetooth/CoreLocation/Security arrive S4–S5; plan is protocol
  seams (scanner/location/keychain behind internal protocols) so logic stays
  Linux-testable, with either `#if canImport` shims or stub SPM targets for
  the caught-by-compile guarantee. Decide at S4.
- Harness honesty (Android arc-review finding 1): `swift test` fails loudly
  on compile errors and reports exact test counts — the masking hazard the
  kotlinc harness had doesn't exist here. Expected count is pinned in
  runtests.sh and checked.

## S1 decisions

- **Package/module name `EEGatewaySDK`**, platforms iOS 15 / macOS 12 (macOS
  entry exists so `swift test` runs on mac and Linux; no mac support claim).
- **Language mode v5** (tools 6.0): matches the shipped app the sources come
  from. Strict-concurrency adoption is a deliberate later pass, not a
  scaffold default.
- **Zero dependencies** is a product contract, same as Android.
- **EEConfig is an enum**, not a sealed-interface mirror: Swift can't default
  associated values, so production-default construction ships as static
  factory overloads (`.gatewayToken(token:)`, `.selfMint()`), full cases take
  explicit baseUrl. Case-for-case parity with Android otherwise.
- **EEListener is a typealias closure**, not a protocol — Swift idiom for a
  `fun interface`. The Android "throwing listener is swallowed" clause has no
  Swift equivalent (closure type is non-throwing by construction); the
  facade-level never-throws contract stands.
- **EEStatus.lastHeartbeatAt stays epoch millis** (not Date) for field-level
  parity with Android and the wire.
- **EEGateway is a caseless enum with static members** — Swift's `object`.
  NSLock serializes transitions; callbacks post to `callbackQueue` (internal
  test seam, default `.main` — the public contract is unchanged).
  `_resetForTests()` is internal, used by the facade suite.
- S1 stub behavior matches Android C1: configure → READY, start → RUNNING
  directly (engine + AWAITING_PERMISSIONS gate land in S5), stop → STOPPED.
  start from PAUSED_REMOTE/AWAITING/RUNNING is a no-op (already started).

## S2 decisions (so far)

- **HubblePacketParser extracted verbatim** from the app; fixture tests
  carried verbatim PLUS the Android SDK's v2 high-bit EID vector, so both
  platforms run an identical fixture set (8 tests).
- **Counters extracted verbatim** (it's an `actor` in the app; kept — tests
  are async). `droppedNoEID` stays local-only (§1a: no server field).
- **DeviceRollup extracted verbatim.** Known cross-platform delta kept
  as-shipped: iOS caps the heartbeat block at top-50 **by packet count**;
  the Android SDK caps by recency and clamps last-seen monotonic. Shipped-app
  parity wins over cross-SDK unification until a partner complains.
- PacketQueue in the app leans on SwiftData (`import SwiftData`) — the SDK
  port must drop that (zero-dependency + iOS 15 floor + Linux testability).
  Plan: mirror the Android SDK's PacketQueue + QueueStore (JSON file
  persistence) semantics instead. That makes PacketQueue an ADAPTED port,
  not verbatim — flagged here because everything else so far is verbatim.
