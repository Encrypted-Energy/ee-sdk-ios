# EE Gateway SDK for iOS — Integration Guide

Turn the iPhones running your app into Encrypted Energy gateways. Two
lines:

```swift
EEGateway.configure(.gatewayToken(token: tokenFromYourBackend))
EEGateway.start()
```

That's the whole integration. No signup screens, no new permission prompts,
no EE credential in your binary. Your app keeps owning the user experience;
the SDK scans for sensor beacons in the background, stamps them with a
fresh GPS fix, and forwards them. You get paid per unique device covered
per day.

## Requirements

- iOS 15+, Swift Package Manager. Zero dependencies.
- Your app already holds Bluetooth and location grants (tracker,
  fitness, automotive, and field-ops apps do).
- Info.plist: `NSBluetoothAlwaysUsageDescription`, your existing location
  usage strings, and the `bluetooth-central` background mode. Add the
  `location` background mode if you want fixes while backgrounded; without
  it the SDK still runs and reports, it just drops packets it can't stamp.

## Install

Xcode → File → Add Package Dependencies → this repository. One product:
`EEGatewaySDK`.

## Identity: two modes

**Gateway token (production).** Your backend provisions one gateway per
device through the EE Org API and hands each device its `ee_live_` token
over your own authenticated channel:

```
POST /api/v1/org/gateways
Authorization: Bearer <your org API key>
{ "name": "van-042" }
→ { "gateway": { ... }, "token": { "key": "ee_live_..." } }
```

The org key stays on your servers. The device token is proven against the
server before it's ever persisted, so a revoked or mistyped token can't
poison a phone. Rotation: hand the device a new token, call
`configure` + `start` again.

API-created gateways default to `"email_alerts": false`: fleet installs
go quiet every shift end, and nobody wants a thousand outage emails. Pass
`"email_alerts": true` on create to opt a specific gateway in.

**Self-mint (demo).** `EEGateway.configure(.selfMint())` and the device
creates its own identity on first run. Great for kicking the tires; not the
production path (per-device orgs skew fleet economics).

## The contract

- **The SDK never throws and never prompts.** `start()` without the grants
  parks in `awaitingPermissions` and advances to `running` by itself the
  moment your permission flow completes. A revoked grant mid-run returns it
  to `awaitingPermissions`, same deal in reverse.
- **Status is observable, not polled.** `EEGateway.setListener { status in
  ... }` delivers on the main queue, coalesced to about once per second no
  matter how dense the beacon traffic gets.
- **Battery is a contract, not a hope.** Heartbeats every 3 minutes.
  Background scanning is filtered to the EE service UUID and coalesced by
  iOS itself. The scanner parks in Low Power Mode and whenever the fix
  stream dies for 5 minutes (packets it can't stamp are wasted radio),
  resuming on its own; heartbeats report `scan_mode: "paused"` so your
  fleet view stays honest. Packets queue locally (bounded) and upload in
  batches on a 10 second cadence; an offline phone holds up to 1,000
  packets and drains oldest-first when the network returns, and a
  rate-limited server backs the uploader off 60 s doubling to 15 min
  instead of being hammered.
- **There's a fleet kill switch.** One `gateways_paused` flag on your org
  (we flip it on request; self-serve toggle coming) parks every SDK phone
  within one heartbeat: scanning and upload stop, heartbeats keep flowing
  so un-pausing takes effect just as fast. No app release needed.

## What you can read

`EEGateway.status()` / the listener give you: lifecycle state
(`unconfigured / ready / awaitingPermissions / running / pausedRemote /
stopped`), pings heard, packets forwarded, local queue depth, the gateway's
public id, and the last successful heartbeat time. Fleet-side, every phone
reports as `worker_version: ee-sdk-ios/<version>` so you and EE ops can
tell SDK traffic from first-party apps at a glance.

## Sample app

`Sample/` in this repo is a one-screen host app showing the permission
flow, both identity modes, and live status. `Sample/README.md` has the
10-minute Xcode setup.

---

*Android counterpart: `Encrypted-Energy/ee-sdk-android`.*
