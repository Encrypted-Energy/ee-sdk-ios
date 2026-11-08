# Releasing (SPM)

A release of this SDK is a git tag — SPM resolves versions from tags, so
there's no artifact to upload. The repo is public (flipped 2026-11-07);
partners add the package by URL and pin a version rule.

## Checklist

1. All of `./runtests.sh` green (Linux) AND `swift test` green on a Mac
   (the Mac run adds the Darwin-only Keychain tests and compiles the
   CoreBluetooth/CoreLocation adapters, which Linux can't).
2. Sample app built and dogfooded against prod on a real device for any
   release that touched the pipeline (Engine, loops, adapters).
3. Public surface unchanged, or additively extended with `api-freeze.md`
   updated in the same commit.
4. Bump `SdkVersion.string` (single source of truth: the facade constant
   and the heartbeat `worker_version` both read it). Update CHANGELOG.md.
5. Commit, then tag and push:

   ```
   git tag -a 0.1.0 -m "0.1.0: <one-liner>"
   git push origin main --tags
   ```

6. Verify fleet telemetry: within one heartbeat of a dogfood device
   updating, `gateways.worker_version` should read `ee-sdk-ios/<new>`.

## Partner consumption

Xcode → Add Package Dependencies →
`https://github.com/Encrypted-Energy/ee-sdk-ios.git`. Dependency rule:
Up to Next Minor from the tagged version. The SDK is Apache-2.0, so
proprietary hosts need no separate license.

## CI (one-time setup)

`ci/github-workflow-tests.yml` is a ready GitHub Actions workflow (the
pinned harness in a swift:6.0.3 container on every push). This box's token
lacks the `workflow` scope, so a human moves it once:

```
git mv ci/github-workflow-tests.yml .github/workflows/tests.yml
git commit -m "CI: enable Linux test workflow" && git push
```
