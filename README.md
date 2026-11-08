# EEGatewaySDK (iOS)

Your app already holds Bluetooth and location permissions. This SDK
borrows the idle radio: it hears encrypted beacon packets from
logistics sensor networks, stamps where they were heard, and relays
them up. Every device your installs hear first in a day earns your
org a bounty, paid in Bitcoin over Lightning. No ads, no data sale.

```swift
// at app launch
EEGateway.configure(.gatewayToken(token: tokenFromYourBackend))
EEGateway.start()
```

That's the whole integration.

## What actually changes

For your users:

- **No new permission prompts.** The SDK uses the grants your app
  already holds and never asks for anything itself.
- **One opt-in screen, shown by your app, before the first scan.**
  Your users granted Bluetooth and location for your features.
  Relaying beacon data to a third party is a new use of those grants,
  and Apple's Guideline 5.1.2 requires disclosure and explicit
  permission before an app does that. The opt-in screen is that
  permission, and it's what keeps your app on the right side of App
  Review. We ship the exact copy in
  [docs/COMPLIANCE.md](docs/COMPLIANCE.md). Users who decline keep
  using your app exactly as before; you never call `start()` for them.
- **A small, managed battery cost.** Background scanning is
  service-filtered and coalesced by iOS itself; the scanner parks in
  Low Power Mode and when GPS has no fix, and resumes on its own.
- **Nothing readable leaves the phone.** Packet payloads are encrypted
  by the sensor owner's key; neither you nor we can read them. The
  location stamps price bounties and draw the coverage map, and
  they're never sold.

For you:

1. Add the package and the two lines above.
2. Show the disclosure screen (our copy, restyled however you like)
   and call `start()` only for users who said yes.
3. Copy the App Privacy label answers from
   [docs/COMPLIANCE.md](docs/COMPLIANCE.md) into App Store Connect.
4. Provision one token per install from your backend
   ([Quickstart](#quickstart) below).
5. Get paid: 1 sat per unique device heard first per UTC day, pooled
   across your org, settled daily over Lightning.

## Requirements

- iOS 15+, Swift Package Manager, zero dependencies.
- Your app already holds Bluetooth and location grants (tracker,
  fitness, automotive, and field-ops apps do). The SDK never requests
  permissions: without the grants it parks in `awaitingPermissions`
  and starts itself the moment your permission flow completes.
- Info.plist: `NSBluetoothAlwaysUsageDescription`, your existing
  location usage strings, and the `bluetooth-central` background mode.
  Add the `location` background mode if you want fixes while
  backgrounded; without it the SDK still runs and reports, it just
  drops packets it can't stamp.

## Quickstart

1. **Create an org** at [encryptedenergy.com](https://encryptedenergy.com/sign-up)
   and mint an org API key (`ee_org_…`) under Settings → API Keys.
2. **Provision one gateway per install** from your backend: the org
   key never ships in your binary:

   ```
   POST https://encryptedenergy.com/api/v1/org/gateways
   Authorization: Bearer ee_org_...
   { "name": "install-8f3a" }
   → { "gateway": { ... }, "token": { "key": "ee_live_..." } }
   ```

3. **Install the package.** Xcode → File → Add Package Dependencies →
   `https://github.com/Encrypted-Energy/ee-sdk-ios.git`, rule Up to
   Next Minor. One product: `EEGatewaySDK`.
4. **Add the two lines** above at app launch, behind your opt-in
   screen, handing each device its `ee_live_…` token over your own
   authenticated channel. Tokens are verified against the server
   before they're persisted to the Keychain.
5. **Confirm it's alive.** Within 3 minutes your
   [dashboard](https://encryptedenergy.com/settings/org/gateways)
   shows the install's first heartbeat ("Seen seconds ago" plus a GPS
   status). That heartbeat means the integration works.

A word on what you'll see next: the gateway stays **"Pending first
packet"** until it hears a real beacon, and at a desk that can take a
while: beacon fleets cluster around warehouses, delivery routes, and
logistics corridors, not office parks. Heartbeats flowing = done;
packets follow wherever your users actually go. Take the sample for a
drive if you want to see one land.

Kicking the tires first? `EEGateway.configure(.selfMint())` lets a
device mint its own identity with no backend work: demo mode, not the
production path.

## Try the sample

[`Sample/`](Sample/) is a one-screen SwiftUI host app: the permission
flow, both identity modes, Start/Stop, and live status.
[`Sample/README.md`](Sample/README.md) is a 10-minute Xcode runbook.

## The contract

These are promises, not just behavior (frozen in
[api-freeze.md](api-freeze.md): the public API only grows, it never
changes meaning):

- **It never throws.** No force-unwraps, no fatalError, no crash
  vectors; problems surface in status, never in your crash reporter.
- **It never prompts.** The central manager is never even created
  while Bluetooth permission is undetermined. Your app owns the
  permission UX.
- **Your lifecycle drives it.** No services, no background modes of
  its own; it rides the ones your app already declares.
- **Battery is a contract.** Background scanning is service-filtered
  and coalesced by iOS itself; the scanner parks in Low Power Mode and
  when the fix stream dies (packets it can't stamp are wasted radio),
  and resumes on its own. A rate-limited server backs the uploader off
  instead of being hammered.
- **There's a fleet kill switch.** One flag parks every install within
  one heartbeat, no app update needed; heartbeats keep flowing so
  un-pausing is just as fast.
- **Packets queue through process death** (bounded at 1,000) and
  upload oldest-first when the network returns.

## Watching it run

```swift
EEGateway.setListener { status in log(status.state) }   // main queue, coalesced
let now = EEGateway.status()
```

Fleet-side, every install heartbeats as `ee-sdk-ios/<version>` with
packet counters and a devices-seen rollup, so your dashboard and EE
ops see the same truth.

## Store compliance

Apple's Guideline 5.1.2 requires disclosure and explicit permission
before granted permissions are used for a new purpose, and relaying
beacon data is a new purpose.
[docs/COMPLIANCE.md](docs/COMPLIANCE.md) has the drop-in disclosure
copy and the App Privacy label answers. Treat it as part of the
integration, not paperwork.

## Docs

| Doc | What's in it |
|---|---|
| [docs/INTEGRATION.md](docs/INTEGRATION.md) | Full guide: plist, identity modes, provisioning, the contract in detail |
| [docs/COMPLIANCE.md](docs/COMPLIANCE.md) | Disclosure copy + privacy-label answers |
| [api-freeze.md](api-freeze.md) | The frozen public surface |
| [CHANGELOG.md](CHANGELOG.md) | Release history |
| [NOTES.md](NOTES.md) | Engineering decisions and platform deltas |
| [RELEASING.md](RELEASING.md) | Maintainer release flow |

## Economics

1 sat per unique device heard first per UTC day, pooled across your
org, settled daily over Lightning once the pool clears 1,000 sats.
Founding-partner terms are a conversation:
[encryptedenergy.com/sdk](https://encryptedenergy.com/sdk) or
contact@encryptedenergy.com.

## Tests

```
./runtests.sh
```

217 tests on the pinned Linux toolchain (or any Swift ≥ 6.0 via
`swift test`; a Mac run adds the live Keychain tests).

## License

Apache-2.0 (see [LICENSE](LICENSE)). Use it in proprietary apps, no
strings attached.

Android counterpart: [`Encrypted-Energy/ee-sdk-android`](https://github.com/Encrypted-Energy/ee-sdk-android):
same wire contracts, same test fixtures.
