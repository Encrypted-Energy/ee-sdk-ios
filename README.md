# EEGatewaySDK (iOS)

Embed an Encrypted Energy gateway in your existing fleet app. Two lines:

```swift
EEGateway.configure(.gatewayToken(token: tokenFromYourBackend))
EEGateway.start()
```

No signup UI, no new permission prompts, no EE credential in the binary.
The SDK is dormant until your app holds its existing Bluetooth/location
grants, then scans, forwards packets, and heartbeats on its own.

Swift Package Manager, iOS 15+, zero dependencies. Status: pre-release
extraction in progress — see NOTES.md for the arc map.

Android counterpart: `Encrypted-Energy/ee-sdk-android`.

## Tests

```
./runtests.sh
```

Runs the full suite with the pinned Linux toolchain (or any Swift ≥ 6.0 via
`swift test`).
