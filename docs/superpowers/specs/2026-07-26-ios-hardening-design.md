# Build C — iOS hardening: UI smoke test + device-deploy defaults

**Date:** 2026-07-26
**Repo:** gova-ios.
**Status:** Approved in substance (design + forks), pending written-spec review.

## Why

Two gaps the field review flagged:

1. **No UI test target** (`scheme.testTargets: []`). The entire verification story
   is unit tests, a build, and greps — none of which can see a navigation bug. The
   Logger bug (a `navigationDestination` registered inside a lazily-built row never
   bound, so tapping a category pushed a placeholder and unwound) passed every unit
   test, the build, and every grep. A launch-and-navigate UI test is the only thing
   that catches this class.
2. **Deploy defaults are simulator-shaped.** `Config.plist` is `http://localhost`,
   there is no ATS exception, and no `DEVELOPMENT_TEAM` — each blocks a first real
   device install. `prep` already guides the device URL and *mentions* ATS
   ("blocks cleartext to non-local hosts unless configured"), but nothing ships the
   configuration or the team setting.

## Decisions (locked)

- **Smoke test is generic and pre-committed** — one app-agnostic XCUITest that
  works on any generated app, using native XCUITest queries (`tabBars`, `cells`,
  `navigationBars`). No per-app test code; `/build` may add app-specific asserts on
  top. It always runs, so it can't be forgotten.
- **ATS ships `NSAllowsLocalNetworking: true`** — permits http to LAN/local hosts
  only (not arbitrary cleartext), so a first device install against a LAN dev
  server works out of the box. Production uses the `/launch` https tunnel (needs no
  exception).
- **`DEVELOPMENT_TEAM` lives in `project.yml`** as an empty placeholder (durable
  across `xcodegen generate`, which is the reviewer's "signing erased by xcodegen"
  point); `prep` prompts for and writes the real Team ID.

## The smoke test (`ios/GovaAppUITests/SmokeTest.swift`, generic)

Launch the app, then:
- Wait for a tab bar. If none appears (single-screen app, or an auth gate), assert
  *something* interactive rendered (a button or text) so a blank launch still fails
  — then return.
- Assert the tab bar has ≥1 tab; tap **each** tab button and assert it responds.
- Find the first tab that has list rows; tap the first cell and assert a **detail
  pushed** — detected by the tapped **row becoming non-hittable** (a portrait
  full-screen push covers the list; a nav-bar-button check is avoided because a
  list's own `+` toolbar button would false-pass it) — then pop. This is the Logger
  assertion: a row that pushes then unwinds leaves the row hittable and is caught.
  Limitation: a detail that itself contains cells can keep `cells.firstMatch`
  resolving to a hittable cell, so the generic test may skip it as read-only —
  which is why `/build` must add a per-resource detail assertion (see CLAUDE.md).

It uses only native accessibility queries, so it needs no app-specific identifiers.
It degrades gracefully on an auth-gated or single-screen app rather than failing
spuriously.

## `project.yml` changes

- **New target `GovaAppUITests`**: `type: bundle.ui-testing`, `platform: iOS`,
  sources `GovaAppUITests`, `dependencies: [target: GovaApp]`, product bundle id
  `com.gova.GovaAppUITests`, and `TEST_TARGET_NAME: GovaApp` in its settings.
- **`GovaApp.scheme.testTargets`**: `[]` → `[GovaAppUITests]`.
- **ATS** under `GovaApp.info.properties`:
  ```yaml
  NSAppTransportSecurity:
    NSAllowsLocalNetworking: true
  ```
- **Signing** under `GovaApp.settings.base`:
  ```yaml
  DEVELOPMENT_TEAM: ""      # set your Apple Team ID for device builds (prep writes this)
  CODE_SIGN_STYLE: Automatic
  ```

## `CLAUDE.md` changes

- A short **Verification** note: the app has a `GovaAppUITests` smoke test that
  walks every tab and pushes a detail; it must build and stay green, and running it
  (in Xcode / `xcodebuild test`) is the way to catch navigation-binding bugs that
  unit tests and greps miss. When generating screens, give `TabView` items and
  list rows stable `.accessibilityIdentifier`s so UI tests stay robust (the generic
  smoke test works without them, but app-specific asserts need them).
- A short **Device deploy** note: local-network http works on device by default
  (ATS `NSAllowsLocalNetworking`); set `DEVELOPMENT_TEAM` (via `prep`) for signing;
  for a public URL use the `/launch` https tunnel.

## `prep.md` changes

- Add a step to prompt for the **Apple Team ID** and write it to
  `project.yml`'s `DEVELOPMENT_TEAM` (so it survives `xcodegen generate`). Blank is
  allowed (simulator-only).
- Update the existing ATS note (~line 82) to state that local-network cleartext is
  now permitted by default via `NSAllowsLocalNetworking`, so a LAN IP works on
  device without further config; a non-local http host still needs the https
  tunnel.

## Files touched

- `ios/project.yml`
- `ios/GovaAppUITests/SmokeTest.swift` (new)
- `CLAUDE.md`
- `.claude/commands/prep.md`

## Non-goals

- No per-app UI test generation (the generic one covers the smoke path).
- No change to `APIClient`, decoding, or auth flow.
- No CI wiring (running the test is the developer's Xcode / `xcodebuild`); this
  build only makes the target exist and be correct.
- No signing automation beyond writing the Team ID — provisioning stays Xcode's job.

## Verification (structural — no simulator here)

- `cd ios && xcodegen generate` succeeds and the generated project contains the
  `GovaAppUITests` target and the scheme's test target (grep the generated
  `.xcodeproj` / `xcodegen` output). Revert the generated `.xcodeproj` if it is not
  committed.
- `swiftc -parse ios/GovaAppUITests/SmokeTest.swift` reports no syntax errors
  (syntax-only; full XCTest typecheck needs the iOS SDK and happens in Xcode).
- `project.yml` still parses for the existing app target (xcodegen doesn't warn/err).
- Doc review: `CLAUDE.md`/`prep.md` notes are consistent with the shipped ATS +
  signing defaults.
- The actual `xcodebuild test` / Xcode run of the smoke test is the developer's
  step on a machine with a simulator; called out, not run here.
