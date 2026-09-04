---
description: Translate a gova-monolith web app into a native SwiftUI iOS app
---

Run the GOVA iOS build workflow. Read this file completely before acting.

## 1. Validate

Read `SEED.md`. Its Generated Context block must hold real models and endpoints,
not the placeholder. If it is empty, STOP:

> "SEED.md's Generated Context is empty. Run `/prep` — it collects the app name,
> gova-monolith path and API base URL, then populates that section. Re-run
> `/build` once it reports ready. (If SEED.md is already filled in,
> `/export:mobile` alone is enough.)"

## 2. Set app identity

This repo is a template: `ios/project.yml` ships the same placeholders every
time. Skip this and every app you build gets bundle ID `com.gova.GovaApp` and
the name `GovaApp` — they cannot coexist on a device or be registered separately
in App Store Connect.

Read `## App Name` from `SEED.md`. Derive `BundleSlug` — lowercase,
alphanumeric only ("Task Manager" → `taskmanager`). In `ios/project.yml` set:

- `PRODUCT_BUNDLE_IDENTIFIER` → `com.gova.{BundleSlug}`
- `CFBundleDisplayName` → the app name, verbatim

Leave the top-level `name:`, the target names, and the scheme alone — they are
internal to this repo's tooling. Run `xcodegen generate` after editing.

## 3. Brainstorm

Use the `gova-brainstorm` skill with `SEED.md` as input. Design every screen the
Generated Context authorizes — building a subset and calling it done is the
failure mode here. Wait for approval before continuing.

## 4. Plan

Use the `gova-writing-plans` skill.

**Screens come from endpoint kinds, never from a flat model list.** Read the
Generated Context and follow `CLAUDE.md` § Step 4:

- **Top-level screens:** one per name on the `Top-level list screens` line.
  Child resources are deliberately absent from it.
- **Nested children:** each `Nested:` line becomes a list inside the parent's
  detail, loaded as `?filter={fk}:{parentId}`, with its own create sheet
  (pre-filling the fk), edit form and swipe-delete.
- **Custom actions:** each `Custom action:` line becomes a button or a form per
  its `control`, on its `attach` screen, called through `APIClient.shared`.
- **Form controls:** pick from each field's `[format: …]` per the CLAUDE.md
  format table; plain fields fall back to type-based controls.

**Never generate an operation a resource's endpoint kinds do not expose.**

Task order: models → auth screens (if required) → per resource, ViewModel then
View(s) → navigation wiring in `ContentView.swift`.

## 5. Branch

`git checkout -b build/<app-name>` in the main checkout. No worktrees.

## 6. Implement

Use `gova-build-execution`. It dispatches one implementer per task, **one at a
time** — `xcodegen generate` rewrites a single project file, so concurrent
implementers race for it.

Every subagent works under `CLAUDE.md` § Architecture Rules. Do not restate them
in the dispatch; point at them.

Auth ships with the web app, so nothing auth-related is scaffolded here — the
bearer endpoints already exist.

## 7. Verify

**No completion claim without fresh evidence.** Run each check, read the output,
then state the result:

```bash
cd ios && xcodebuild -scheme GovaApp -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 16' test 2>&1 | tail -20
```

- **Build and tests pass** — including the UI smoke test and the per-resource
  detail assertions.
- **Screens:** every screen in the Generated Context is implemented, and no
  operation exists that its endpoint kinds do not expose.
- **Every ViewModel** has `isLoading` and `errorMessage`; **every View** shows
  the error when it is non-nil.
- **Auth gate** wired if auth is required.
- Grep to confirm, don't assume: no force unwraps in generated code, no raw
  `URLSession`, no token in `UserDefaults`.
- `xcodegen generate` was run after the last file was added.

## 8. Report

> **Build complete.** Open `ios/GovaApp.xcodeproj` and run on the simulator.
> Branch: `build/<app-name>`.
> Make sure the gova-monolith API is running and `Config.plist` points at it.
