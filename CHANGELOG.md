# Changelog

## Unreleased (0.1.0 candidate)

First extraction arc (S1–S6 + S7 sample), built 2026-11-06 from the shipped
gateway-ios 1.5 sources and the ee-sdk-android contracts:

- Frozen public API: `EEGateway` / `EEConfig` / `EEStatus` / `EEState` /
  `EEListener` (see api-freeze.md).
- Full pipeline: FCA6 scan (service-filtered CBCentralManager), per-EID
  throttle, fresh-fix stamping with the 25 s staleness gate, bounded
  persistent packet queue, batched ingest with the published 413/422
  contract, 5-minute heartbeats with delta snapshot/restore.
- Identity: gateway-token mode with verify-before-persist into the
  Keychain; self-mint demo mode; fleet kill switch (`pausedRemote`).
- Contracts: never throws, never prompts, no background modes of its own,
  zero dependencies, main-queue coalesced status callbacks.
- 198-test Linux harness + Darwin-only Keychain tests; sample host app and
  integration guide in `Sample/` and `docs/`.

Tag 0.1.0 after first-device dogfood (S7 runbook in Sample/README.md).
