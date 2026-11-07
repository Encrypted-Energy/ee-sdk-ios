# Changelog

## 0.1.0 — 2026-11-07

First extraction arc (S1–S6 + S7 sample), built 2026-11-06 from the shipped
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
