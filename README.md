# gova-ios

A template for turning a [gova-monolith](../gova-monolith) web app into a native
iPhone app.

## What it is

You already built a web app with gova-monolith. The Go server and its JSON API
stay exactly as they are — this repo builds only the iOS client that talks to
them, so you describe your data once.

It works by reading the web app's `api.json`: the models, their field types, and
which operations each resource exposes. From that, the assistant writes one
SwiftUI screen per resource, wired to the shared API.

Sign-in needs no setup here. Auth ships with the web app, so the token endpoints
the iPhone app uses always exist.

## Getting started

You need Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`).

```bash
./install-claude.sh          # sets the API URL, generates the Xcode project
```

Then:

1. Run `/prep` — the assistant asks for your app name, where the web app lives,
   and the API address, then reads the web app's data model
2. Run `/build` — it writes the screens
3. Open `ios/GovaApp.xcodeproj` and run

Re-run `/export:mobile` any time the web app's API changes.

## What's already written

`ios/GovaApp/Lib/` is hand-written and shared. Use it; never regenerate it.

| File | Does |
|---|---|
| `APIClient.swift` | every network call, with the response envelope unwrapped and the auth token attached |
| `AuthManager.swift` | the login token, kept in the Keychain |
| `VersionGate.swift` | at launch, asks the server whether this build is too old |
| `UpdateRequiredView.swift` | the screen shown when it is |

Everything else — models, view models, views — is generated per app.

## The Xcode project is generated

`GovaApp.xcodeproj` is built from `ios/project.yml` by XcodeGen and is not in
git. **After adding any Swift file, run `xcodegen generate` inside `ios/`**, or
the file is not in the project and the build ignores it.

## Verify

```bash
.claude/skills/gova-build-execution/scripts/verify
```

It regenerates the project, builds, and runs both test targets against the
first iPhone simulator installed on the machine (`GOVA_SIM="iPhone 17 Pro"`
pins a different one).

`GovaAppTests` holds unit tests. `GovaAppUITests` holds a smoke test that
launches the app and taps through it; `/build` adds a check per screen on top,
which is what actually proves each detail view works.

## Reference

- [`CLAUDE.md`](CLAUDE.md) — the rules the assistant works under
- `../gova-monolith/docs/API-CONTRACT.md` — what the shared API guarantees
