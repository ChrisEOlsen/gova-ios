---
description: Gather everything SEED.md needs, populate it, and get the repo ready for /build
---

You are running the GOVA iOS prep workflow. It collects the handful of facts only the
developer knows, writes them into `SEED.md`, runs the export, and hands off to `/build`.

Read this file completely before taking any action. Do not write Swift code here.

---

## Step 1 — Preflight

Check that `./install-claude.sh` has already been run:

- `ios/GovaApp/Config.plist` exists and has an `API_BASE_URL` key

If `Config.plist` is missing or has no `API_BASE_URL`, STOP:

> "Run `./install-claude.sh` from the repo root first — it sets the API base URL and
> generates the Xcode project. Then re-run `/prep`."

`/export:mobile` reads the web app's `src/app/api.json` off disk — it needs no
running server — it reads a committed file.

---

## Step 2 — Find likely gova-monolith paths (before asking)

Look for candidate web app repos so the developer can pick instead of typing a path.
Check, in order:

1. Sibling directories of this repo (`../*`) whose name contains `gova` or that contain
   `src/app/main.go`
2. `~/Desktop/repos/*` matching the same test

A directory is a valid gova-monolith repo only if **all** of these exist:
- `src/app/main.go`
- `src/app/models/`
- `src/app/static/js/`

Keep the valid candidates for Step 3. Do not ask about invalid ones.

---

## Step 3 — Gather from the developer

Read the current `SEED.md` values first and offer them as defaults — never ask for
something already filled in with a real (non-placeholder) value; show it and ask only
for confirmation.

Ask for all five in **one** `AskUserQuestion` call where the answers are selectable,
otherwise ask in plain text. Under Codex there is no such tool: ask all five as one
numbered list in a single message, each with its options. Keep it to a single
round-trip if possible.

**1. App Name** — free text. Used as the home-screen name and to derive the bundle ID
(`com.gova.{lowercased-alphanumeric}`) in Step 2 of `/build`. Must be unique per app.

**2. Web App Path** — absolute path to the gova-monolith repo. Offer the Step 2
candidates as options plus "Other" for a typed path.

**3. API Base URL** — where the iOS app talks to the Go API. Offer:
- the value currently in `Config.plist` (recommended if it is not a placeholder)
- `http://localhost:8080` — simulator against local Docker
- Other — a tunnel URL or LAN IP, for running on a physical device

Note for the developer: a physical iPhone cannot reach `localhost` — it needs the LAN
IP or a tunnel URL.

**4. Design Notes** — optional iOS-specific UX notes (tab bar vs. stack, dark mode,
list style). Say it is optional and that CLAUDE.md defaults apply if skipped.

**5. Apple Team ID** — *optional*. The 10-character Apple Developer Team ID used to
sign device builds (Xcode ▸ Settings ▸ Accounts, or the current `DEVELOPMENT_TEAM`
in `ios/project.yml`). Offer the current `project.yml` value if non-empty, and
"Skip (simulator only)". Blank is fine — the simulator needs no team.

---

## Step 4 — Validate the answers

- Web App Path resolves and passes the Step 2 validity test. If not, tell the developer
  exactly which of the three required paths is missing and ask again.
- API Base URL parses as a URL with a scheme. `http://` to a **local/LAN** host works
  on device — the template ships an ATS `NSAllowsLocalNetworking` exception. Warn
  (do not block) only if it is `http://` to a **non-local** host, which ATS still
  blocks; recommend the `/launch` https tunnel for that case.
- App Name is non-empty and its derived bundle slug is non-empty after stripping
  non-alphanumerics.

---

## Step 5 — Write SEED.md

Update the four fields above the `## Generated Context` heading in `SEED.md`, replacing
the placeholder text. Leave the `## Generated Context` section and its marker line alone —
Step 7 handles that.

---

## Step 6 — Sync Config.plist

If the chosen API Base URL differs from `API_BASE_URL` in `ios/GovaApp/Config.plist`,
update the plist to match. `SEED.md` and `Config.plist` must never disagree — `APIClient`
reads the plist, so the plist is what actually ships.

Do not run `xcodegen generate` here; no files were added.

---

## Step 6b — Set the signing team

If the developer gave an Apple Team ID, write it into `ios/project.yml` as the
`DEVELOPMENT_TEAM` value under `targets: GovaApp: settings: base:` (replace the
empty string). This lives in `project.yml` so it survives `xcodegen generate`. If
they skipped it, leave it empty — simulator builds do not need a team. Do not run
`xcodegen generate` here; `/build` regenerates the project.

---

## Step 7 — Run the export

Execute `.claude/commands/export-mobile.md` in full, now that `Web App Path` is set.
It reads the web app's API manifest (`$WEB_APP/src/app/api.json`) and writes the
`## Generated Context` section of `SEED.md` directly.

---

## Step 8 — Report

Show the developer a summary and confirm readiness:

> **Prep complete — ready for `/build`.**
>
> - App Name: [name] → bundle `com.gova.[slug]`
> - API Base URL: [url] (SEED.md + Config.plist in sync)
> - Web App Path: [path]
> - Exported: [N] models, [N] endpoints
>
> Run `/build` to translate the web app to iOS.

If anything is unresolved (an invalid path, an empty manifest), lead with that
blocker instead of the ready line.
