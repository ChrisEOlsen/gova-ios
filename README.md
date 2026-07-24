# gova-ios

Template repo for translating a [gova-monolith](../gova-monolith) web app into a
native SwiftUI iOS app. The Go backend and JSON API stay shared — this repo only
builds the iOS client that talks to it.

## How it works

1. Run `./install-claude.sh` once — sets `Config.plist`'s API base URL. (`/export:mobile` reads the web app's
   committed `src/app/api.json` manifest directly — no MCP or running server needed;
   auth, cookie + bearer, is scaffolded on the monolith side with `scaffold_auth`.)
2. Run `/prep` — Claude asks for the app name, gova-monolith path, API base URL
   and any design notes, writes them into `SEED.md`, then runs the export for you.
   It reports when the repo is ready for `/build`.
3. Run `/build` — Claude reads `SEED.md` and translates each web screen
   into a SwiftUI View + ViewModel pair, wired into a working iOS app.

`/export:mobile` can also be run on its own — it re-reads the linked gova-monolith
repo and overwrites `SEED.md`'s Generated Context section in place. Use it whenever
the web app changes, then re-run `/build`.

See `CLAUDE.md` for the full translation guide and architecture rules.

## Requirements

- Xcode
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) —
  regenerates `ios/GovaApp.xcodeproj` from `ios/project.yml`
- A running gova-monolith instance (`docker compose up -d` in that repo)
