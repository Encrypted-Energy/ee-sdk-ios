# Sample host app (S7)

One screen: permission primers, token paste / self-mint toggle, Start /
Stop, live status. The SDK's analog of ee-sdk-android's `:sample` — and the
reference code for the C10 guide. An iOS app bundle can't be built by SPM
alone, so the Xcode project is created once on a Mac (~10 minutes):

## Create the project

1. Xcode → File → New → Project → **iOS App**. Product name `EESample`,
   organization identifier `com.encryptedenergy` (bundle id becomes
   `com.encryptedenergy.EESample`), interface SwiftUI, language Swift. Save
   it anywhere OUTSIDE this repo (e.g. `~/projects/ee/EESample`).
2. File → Add Package Dependencies → **Add Local…** → select this repo's
   root folder (`ee-sdk-ios`). Add the `EEGatewaySDK` library product to the
   EESample target.
3. Delete the generated `ContentView.swift` and `EESampleApp.swift`; drag in
   `Sample/EESampleApp.swift` from this repo (copy files in).
4. Target → Info tab, add:
   - `NSBluetoothAlwaysUsageDescription` — "Relays nearby sensor beacons to
     the Encrypted Energy network."
   - `NSLocationWhenInUseUsageDescription` and
     `NSLocationAlwaysAndWhenInUseUsageDescription` — "Stamps relayed
     beacons with the location they were heard at."
5. Target → Signing & Capabilities:
   - Add **Background Modes** → check *Uses Bluetooth LE accessories*
     (`bluetooth-central`) and *Location updates*.
   - Set your signing team.
6. Minimum deployment: iOS 15.

## Run it (the S7/C8-equivalent dogfood)

1. Build to a real iPhone (BLE + GPS need hardware).
2. Tap **1. Request Bluetooth** → allow. Tap **2. Request Location** →
   allow (While Using, then upgrade to Always from Settings for background).
3. Leave **Self-mint** on for the first run → **Start**. State should go
   `running`; within seconds the immediate post-mint heartbeat fills in the
   gateway public id, and the fleet dashboard shows a new device-mint
   gateway reporting `worker_version: ee-sdk-ios/0.1.0`.
4. Walk past a Hubble beacon (or sit near the desk sensor): pings heard
   climbs, queue drains on the 10 s tick, forwarded climbs.
5. Production-mode pass: provision a token via the Org API (same curl as
   the Android C8 runbook in `ee-sdk-android/NOTES.md`), toggle self-mint
   OFF, paste the token, Start — verify-before-persist proves it against
   /gateways/verify before it ever reaches the Keychain.
6. Kill-switch pass: flip the org's `gateways_paused` on, wait one
   heartbeat (≤3 min) → state `pausedRemote`, scanning stops; flip it off →
   `running` resumes on its own.
