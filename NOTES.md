# Engineering notes: ee-sdk-ios

Design decisions and platform deltas that explain the code. Source
comments point here; the chronological build history lives in EE's
internal archives, not in this repo.

## Deltas vs ee-sdk-android (the reference implementation)

The two SDKs share wire contracts, test fixtures, and cadences
(3-minute heartbeats, 10 s upload ticks, 500-packet chunks, the 413/422
ingest contract). Where they differ, iOS differs on purpose:

- **DeviceRollup caps by packet count** (the shipped iOS app's rule),
  not Android's pure time-window rule. Same wire shape either way; the
  server keeps at most 50 devices.
- **Claim API removed, verify() added.** The SDK is a headless fleet
  worker; the consumer claim flow stayed in the first-party app.
- **PacketQueue is an ADAPTED port of Android's** (JSON file via
  QueueStore, 1,000-packet cap), not the first-party app's SwiftData
  queue. The eeq1 file format is byte-identical cross-platform.
- **No TokenCrypto.** Keychain is the platform secure store; Android
  needed Keystore-wrapped AES because its storage model differs.
- **Json writer throws on non-finite doubles** (Kotlin's is unchecked).
  PacketJson catches and maps to a transient outcome.
- **Transport seam:** EEClient takes an injected
  `(URLRequest) async -> (Data, Int)?`, which gives endpoint-level
  tests Android's HttpURLConnection can't support.

## Scanning and battery

- **No adaptive FULL/REDUCED scan policy** (Android's ScanPolicy).
  CoreBluetooth has no scan-power knob; in the background iOS itself
  throttles and coalesces service-filtered scans, so the OS is the duty
  cycler. The first-party app's 10 s/30 s cycle and CoreMotion ladder
  are foreground product behaviors, deliberately not ported: a guest
  SDK stays deterministic on someone else's battery. Revisit only with
  real partner battery numbers.
- **RadioGate (0.2.0)** parks the scanner in Low Power Mode and after
  5 minutes without a fresh fix (packets it can't stamp are wasted
  radio). Location keeps running while parked: it is the recovery
  signal. Heartbeats report `scan_mode: "paused"`.
- **CoreLocationSource runs a fixed moderate profile** (nearest-ten-
  meters, 10 m filter) and only enables background updates when the
  host's plist declares the location background mode.
- **The never-prompt contract is structural:** CBCentralManager is
  never created while authorization is `.notDetermined`.

## Accepted as-is (reviewed, deliberate)

- Per-call DateFormatter in DeviceRollup's heartbeat path (verbatim app
  extraction; cost is negligible at heartbeat cadence).
- Trailing-slash baseUrl values produce double slashes (server
  tolerates; matches Android).
- Darwin-vs-Linux JSONSerialization bool bridging differs in theory;
  unreachable in practice because the server sends real booleans. The
  Linux harness cannot prove the Darwin branch: Mac `swift test` can.

## Hazards for contributors

- **Engine's default mint targets production.** Every test constructs
  Engine with an injected mint stub; a test that forgets will hit the
  real API. All current tests inject.
- **runtests.sh pins the expected test count.** A refactor that
  silently drops a test file fails the harness instead of shrinking
  the suite unnoticed. Bump the pin when you add tests.
- Darwin-only tests (live Keychain round-trips) run via `swift test`
  on a Mac; the Linux harness compiles them out.
