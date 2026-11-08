# Changelog

## 0.2.0 — 2026-11-07

Guest-courtesy and resilience release; frozen public API unchanged
(everything below is internal behavior plus additive heartbeat fields).

- RadioGate: the scanner parks in Low Power Mode (mirroring the shipped
  app's LPM pause) and after 5 minutes without a fresh fix (every heard
  packet is a guaranteed drop then — scanning without a stampable fix is
  wasted radio). Location keeps running while parked as the recovery
  signal; heartbeats report `scan_mode: "paused"` and status
  `backgrounded`. Evaluated every 30 s while the pipeline is up.
- Upload 429 cooldown (from the app's 2026-09-14 dense-beacon storm): a
  rate-limited server backs the uploader off 60 s, doubling to 15 min,
  reset on the first accepted batch. Other transients keep the plain
  10 s cadence.
- EidThrottle bounded at 4,096 entries (two-generation scheme): a
  rotating-identifier flood can no longer grow the map without limit;
  suppressed sightings refresh recency so hot devices never evict.
- devices_seen now prunes on the heartbeat path too: a quiet radio no
  longer reports rows older than the 24 h window the block claims.
- New additive heartbeat field `host_app` (Bundle.main.bundleIdentifier)
  for per-app fleet grouping and cross-app token fraud checks.
- 198 → 217 Linux tests.

## 0.1.1 — 2026-11-07

- Relicensed from GPL-3.0 (dual) to Apache-2.0; COMMERCIAL-LICENSE.md
  removed (no separate commercial license needed for proprietary apps).
  Docs-only release: no source changes vs 0.1.0.

## 0.1.0 — 2026-11-07

First extraction arc, built 2026-11-06 from the shipped
gateway-ios 1.5 sources and the ee-sdk-android contracts:

- Frozen public API: `EEGateway` / `EEConfig` / `EEStatus` / `EEState` /
  `EEListener` (see api-freeze.md).
- Full pipeline: FCA6 scan (service-filtered CBCentralManager), per-EID
  throttle, fresh-fix stamping with the 25 s staleness gate, bounded
  persistent packet queue, batched ingest with the published 413/422
  contract, 3-minute heartbeats with delta snapshot/restore.
- Identity: gateway-token mode with verify-before-persist into the
  Keychain; self-mint demo mode; fleet kill switch (`pausedRemote`).
- Contracts: never throws, never prompts, no background modes of its own,
  zero dependencies, main-queue coalesced status callbacks.
- 198-test Linux harness + Darwin-only Keychain tests; sample host app and
  integration guide in `Sample/` and `docs/`.

First-device dogfood PASSED 2026-11-07 (gateway 408: provisioning,
heartbeats, 113 heard / 9 forwarded accepted under the org, GPS stamping,
devices rollup — zero EE credentials in the binary).
