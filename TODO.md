# TODO

## Verified on 2026-09-12

Xcode 26.6, iOS 26.5 simulator, iPhone 17 Pro:

```
==> xcodegen generate
==> build          ** BUILD SUCCEEDED **
==> test           GovaAppTests.xctest   — 5 tests, 0 failures
                   GovaAppUITests.xctest — 1 test,  0 failures
```

Run with the stock toolchain (`xcode-select -p` →
`/Applications/Xcode.app/Contents/Developer`), no environment overrides. So:
`xcodegen generate` produces a valid project, the app compiles, both test
targets build and run, and `@testable import GovaApp` resolves `compareSemver`.
Fixing that run required adding `GENERATE_INFOPLIST_FILE: YES` to both test
targets in `project.yml` — without it neither could be code-signed, so neither
had ever built.

One environmental failure showed up twice in a row on the way there and is
worth knowing: a long-lived CoreSimulator service drifts into refusing every
app launch, reported as `Application failed preflight checks` and reading
exactly like a code failure. The cure is

```bash
killall -9 com.apple.CoreSimulator.CoreSimulatorService && xcrun simctl erase all
```

`scripts/verify` now prints that itself when it sees the phrase in the log.

## Still unexercised: the smoke test's main path

`SmokeTest` passed through its **degraded** branch. `ContentView` is still the
template placeholder, so there is no tab bar: the test asserted that something
rendered and returned. The tab walk, the `isSelected` assertion and the
row-tap-pushes-a-detail check have never run against a real app.

They get their first exercise on the first `/build` of an app with screens.
Read that run's output rather than trusting the green tick here.

## Confirm LAN http on a physical device

`project.yml` ships `NSAllowsLocalNetworking: true`, which should let a device
reach `http://<LAN-IP>:8080` without a tunnel. That is what the ATS
documentation says, and `CLAUDE.md` and `/prep` both tell the developer so, but
it has never been tried on hardware. One device run settles it.

## Upstream: `api.json` under-reports `login_token`

`gova-monolith`'s committed `src/app/api.json` lists the `login_token` response
as `{token}`. The handler (`auth_mobile.go`) and `docs/API-CONTRACT.md` both
say `{token, user}`. This repo now works around it — `/export:mobile` writes
the contract's shape into the Generated Context and `AuthManager` ships
`LoginResponse` — but the manifest is still wrong for every other client.

Fixing it belongs in the monolith: the auth rows in `api.json` are
hand-maintained, and `hash` is a sha256 over models + endpoints + pages, so the
file has to be rewritten by the builder rather than edited by hand.
