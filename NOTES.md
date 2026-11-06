# Build notes — ee-sdk-ios

Decisions and caveats, chunk by chunk, for John and future chunks. Mirrors
the Android arc (ee-sdk-android C1–C10); iOS chunks are S1–S7 + shared
C9/C10. Extraction source: `gateway-ios` branch `anonymous-first-onboarding`
(131c3f5) — the shipped 1.5 app.

## Review (post-S3, 11/6): findings and fixes

Full S1–S3 pass against the plan contracts (never-throws, never-prompts,
zero deps, frozen surface), the verbatim-extraction claims, threading, and
harness honesty. One finding fixed:

1. **PacketQueue's lock had to be recursive.** Kotlin's @Synchronized is
   reentrant, so on Android an onChange handler that reads the queue
   (size(), snapshot()) is legal. The Swift port used NSLock, which
   self-deadlocks on reentry — an onChange wired that way in S5 would HANG
   the host app, the one failure mode worse than a crash for an embedded
   SDK. Fixed: NSRecursiveLock + a regression test that reenters from the
   handler (hangs under NSLock, passes now).

Verified clean:

- **Verbatim claims are byte-identical** — diffed HubblePacketParser,
  Counters, DeviceRollup against gateway-ios 131c3f5: comment-only deltas.
- **Public surface is exactly the frozen API** (grep-audited): EEGateway's
  five members + version, EEConfig (+factories/baseUrl), EEStatus, EEState,
  EEListener. Test seams (callbackQueue, _resetForTests) are internal.
- **No crash vectors in Sources/**: zero force-unwraps, try!, as!,
  fatalError, precondition.
- **Harness honesty verified both directions**: injected XCTFail → exit 1
  with the failure printed; count pin fails if the suite shrinks below the
  expected floor.

Reviewed and ACCEPTED as-is (all Android-parity):

- isoUtc builds a DateFormatter per call — heartbeats are 300 s apart.
- EidThrottle's map is unbounded — bounded in practice by unique EIDs/24 h,
  same as both shipped apps.
- A partner baseUrl with a trailing slash yields `//api/...` — server
  tolerates; same on Android.
- JSONSerialization bridging quirk: on Darwin `{"disable":1}` would parse
  as true, on Linux false. ee-web sends real JSON booleans, so unreachable;
  noting it because the Linux harness can't prove the Darwin branch.

## Arc map

| Chunk | Scope | Status |
|---|---|---|
| S1 | SPM scaffold, frozen public API (EEGateway/EEConfig/EEStatus/EEState/EEListener), Linux harness | DONE 11/6 |
| S2 | Pure core: HubblePacketParser, Counters, DeviceRollup, UploadPacket, PacketQueue + QueueStore (de-SwiftData'd), EidThrottle, Backoff | DONE 11/6 (66 tests) |
| S3 | Headless EEClient + BatchSender + payload builders (Json/PacketJson/HeartbeatPayload/LocationFix) | DONE 11/6 (141 tests) |
| S4 | TokenStore protocol + KeychainTokenStore + TokenProvision (verify-before-persist) | DONE 11/6 (151 tests on Linux; +3 Keychain tests Darwin-only) |
| S5 | Pipeline: loops, PacketRadio/LocationSource seams + Darwin adapters, Engine, dormancy gate | DONE 11/6 (180 tests) |
| S6 | Guardrails: ProvisionRunner wiring, PAUSED_REMOTE kill switch, publicId, facade↔engine wiring | open |
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
- **PacketQueue + QueueStore are ADAPTED ports of the Android SDK**, not
  app extractions: the app's queue is SwiftData + MainActor-pinned, which
  fails every SDK constraint (zero deps, iOS 15 floor, Linux testability,
  no main-actor coupling). The Android pair was itself distilled from the
  same plan contracts, so it's the spec. Deltas from Android, both
  mechanical: `@Volatile onChange` → lock-guarded accessor (same guarantee,
  one mechanism); temp-file-then-rename → Foundation's
  `write(atomically:)`, which is the same scheme under the hood. File
  format `eeq1` is byte-identical cross-platform. Capacity note: the SDK
  keeps Android's 1,000-packet bound, NOT the app's 5,000 — SDK memory
  discipline beats app parity here, same call the Android arc made.
- **UploadPacket, EidThrottle, Backoff ported from the Android SDK** (the
  app has no standalones — throttling/retry live inside its loops, and the
  queue model doubles as the packet type). Backoff's Java `Random` seam
  became a `() -> Double` closure; tests use a SplitMix64 stand-in for
  seeded determinism. All Android test cases carried 1:1, plus a new
  onChange-fires-on-mutations-only case and a schedulePersist coalescing
  case.

## S3 decisions

- **EEClient = app client + Android SDK deltas.** Response mapping is the
  shipped app's (verified vs ee-web controllers 7/12); SDK deltas mirror
  Android: claim flow REMOVED (no end user in a fleet SDK), verify() ADDED
  (verify-before-persist, S4), heartbeat 2xx parsed for `disable` +
  `gateway.public_id`, token via provider closure (rotation after
  provisioning).
- **Transport seam.** The wire call is `(URLRequest) async -> (Data, Int)?`
  injected at init — something HttpURLConnection never allowed Android, so
  this port adds endpoint-level tests (method/headers/body shaping, status
  mapping, no-call-without-token) on top of the pure-mapper suite carried
  1:1. Production transport wraps `URLSession.dataTask` in a continuation
  (works on Linux FoundationNetworking; `URLSession.data(for:)` does not
  exist there in all toolchains).
- **Json.swift is the Android ordered writer, write-half only.** Response
  parsing rides JSONSerialization instead of porting the hand-rolled
  parser; writing stays hand-rolled because neither JSONEncoder nor
  JSONSerialization guarantees key order, and wire-parity tests pin exact
  body strings (iOS 1.2 production fixture). Kotlin's unchecked
  IllegalArgumentException on non-finite doubles became a thrown
  `Json.WriteError` — PacketJson is `throws`; BatchSender catches and maps
  to transient (same behavior Android's catch-all gives).
- **HeartbeatPayload.build is non-throwing** (`try?` + unreachable "{}"
  fallback): none of its field types can hold a non-finite Double, and the
  heartbeat loop must never throw. `worker_version` = `ee-sdk-ios/<ver>` so
  ops can tell SDK traffic from the first-party app. devices_seen bridges
  the verbatim DeviceRollup dictionary through JSONSerialization
  (`heartbeatRaw`) — key order inside the block is unspecified, server
  doesn't care.
- **BatchSender ported 1:1** including the 413 halving ladder and
  stop-and-requeue ordering. SDK keeps the Android/server batch contract
  (500/chunk), NOT the app's modest 10/batch — one fleet phone drains a
  long-offline queue in two calls instead of a hundred.
- **ios-platform mint**: mintDevice sends `"platform":"ios"`; attestation
  stays omitted (server runs DEVICE_ATTESTATION=log) — revisit when the
  DeviceCheck build lands in the app, same caveat as Android.

## S4 decisions

- **No TokenCrypto on iOS, deliberately.** Android layers Keystore AES-GCM
  over SharedPreferences because prefs are plaintext on disk. The Keychain
  IS the platform secure store (encrypted at rest, hardware-backed); a
  second envelope would add key-management failure modes for zero added
  secrecy. So S4 = TokenStore protocol + KeychainTokenStore + the
  TokenProvision invariants, and the Android TokenCrypto/TokenCryptoTest
  pair has no iOS counterpart.
- **TokenStore is a protocol** (Android surface: load/save/clear/
  loadGatewayName/saveGatewayName) with the Keychain conformance behind
  `#if canImport(Security)`. The Linux harness proves the provisioning
  invariants through the seam; John's Mac `swift test` compiles AND
  round-trips the real SecItem plumbing (KeychainTokenStoreTests,
  Darwin-only) — live-storage coverage the Android Keystore never had off-
  device. Linux pin is 151; a Mac run reports 154.
- **Keychain details carried from the app's KeychainStore**: generic-
  password class, upsert (update-then-add), and
  kSecAttrAccessibleAfterFirstUnlock so background BLE relaunches can read
  the token. SDK delta: service is `com.encryptedenergy.sdk` (the app owns
  `com.encryptedenergy.gateway`), so SDK and first-party app never collide
  on one device; gateway_name is a second account in the same service.
- **TokenProvision ported 1:1** (all 9 invariant tests). The injected
  verify/mint closures are async because this EEClient is async; Android's
  blocking client took sync closures. save() stays best-effort void like
  Android — a storage failure leaves the previous state and the next
  start()'s reconcile sorts it out.

## S5 decisions

- **Engine is seam-built and Linux-tested** — the big structural delta from
  Android, whose Engine was stub-compiled only and dogfood-checked. The
  dormancy gate (grants poll, mid-run revocation, the synchronous
  revoked-between-check-and-call race), the packet path (fresh-fix stamp,
  no-fix drop, eid-less drop), queue restore, and heartbeat runtime
  composition are all proven with fake radio/location on Linux.
- **Loops are Task-based** (ScheduledExecutorService → detached Task +
  Task.sleep), tick()-testable, cadences pinned: upload 10 s (3 s initial),
  heartbeat 300 s — the fleet-conservative cadence, NOT the app's 60 s.
  Android's throwing-callback/throwing-wire guards have no counterpart: the
  closure types are non-throwing, compiler-enforced.
- **Counters became ADAPTED (lock-based class)** — was the verbatim app
  actor until S5; an actor forces a Task spawn per heard advertisement on
  the scan path. Same surface and semantics; Android-parity shape.
- **BleScanner (Darwin) never prompts**: creating CBCentralManager fires the
  system dialog, so start() refuses while authorization is .notDetermined
  and reports unauthorized — the dormancy poll re-enters after the host's
  own flow. The app's O2-primer prepare() dance has no SDK counterpart.
  SDK-namespaced restore ID; per-EID throttle via the shared EidThrottle
  (3 s).
- **No adaptive scan machinery in v1** (app duty cycle, Android ScanPolicy,
  battery receiver): the app's 10s/30s cycle is a FOREGROUND product
  feature, and an embedded SDK is background-first where iOS already
  coalesces service-filtered scans. scan_mode is omitted from heartbeats
  (optional field). Revisit with real partner battery numbers; until then
  the 300 s heartbeat + OS-coalesced background scanning is the battery
  story.
- **CoreLocationSource (Darwin)**: fixed moderate profile (NearestTenMeters,
  10 m filter) — the app's 1.3 CoreMotion power ladder is NOT ported
  (determinism on someone else's battery) and neither is the fixed-location
  override (coverage-spoofing lever, same call as Android).
  allowsBackgroundLocationUpdates is set ONLY when the host's Info.plist
  declares the location background mode — setting it without one throws
  into the host.
- **gps_status composition moved into Engine** (dongle_missing/fix/no_fix)
  so the LocationSource seam stays minimal; Android kept it in
  LocationProvider.
- **Facade still runs S1 stub transitions** — EEGateway↔Engine wiring lands
  in S6 with provisioning + kill switch (Android did the wiring in C5, but
  its facade tests were stub-level; ours assert real behavior, so the
  wiring moves with the state machine it completes).
