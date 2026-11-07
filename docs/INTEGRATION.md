# EE Gateway SDK for iOS — Integration Guide (draft)

Turn your fleet's iPhones into Encrypted Energy gateways. Two lines:

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
- Your app already holds Bluetooth and location grants (fleet apps do).
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
  iOS itself. Packets queue locally (bounded) and upload in batches on a
  10 second cadence; an offline phone holds up to 1,000 packets and drains
  oldest-first when the network returns.
- **The fleet kill switch is yours.** Flip `gateways_paused` on your org
  and every SDK phone parks within one heartbeat: scanning and upload stop,
  heartbeats keep flowing so un-pausing takes effect just as fast. No app
  release needed.

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

*Draft status: ships as C10 after first-device dogfood. Android
counterpart: `Encrypted-Energy/ee-sdk-android`.*
