# gova-ios

Template repo for translating a [gova-monolith](../gova-monolith) web app into a
native SwiftUI iOS app. The Go backend and JSON API stay shared — this repo only
builds the iOS client that talks to it.

## How it works

1. Run `./install-claude.sh` once — sets `Config.plist`'s API base URL and wires
   up the `gova-builder` MCP tools (used to inspect the web app and scaffold
   mobile auth endpoints).
2. Fill in `SEED.md` (app name, API base URL, path to your gova-monolith repo).
3. Run `/export:mobile` from your gova-monolith project, paste the output into
   `SEED.md`'s Generated Context section.
4. Run `/build` here — Claude reads `SEED.md` and translates each web screen
   into a SwiftUI View + ViewModel pair, wired into a working iOS app.

See `CLAUDE.md` for the full translation guide and architecture rules.

## Requirements

- Xcode
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) —
  regenerates `ios/GovaApp.xcodeproj` from `ios/project.yml`
- A running gova-monolith instance (`docker compose up -d` in that repo)
