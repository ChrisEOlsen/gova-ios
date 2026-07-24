---
description: Translate a gova-monolith web app to a native iOS SwiftUI app
---

You are running the GOVA iOS build workflow. Read this file completely before taking any action.

---

## Step 1: Validate

Read `SEED.md`. Check that the Generated Context block is populated — it must contain
screen definitions and API endpoints, not just the placeholder comment.

If it is empty or contains only the placeholder, STOP and tell the developer:

> "The Generated Context section of SEED.md is empty. Run `/prep` — it collects the app
> name, gova-monolith path and API base URL, then populates that section for you. Re-run
> `/build` once it reports ready. (If SEED.md is already filled in, `/export:mobile` alone
> is enough.)"

---

## Step 2: Set App Identity

This repo is a template — every new app starts from a fresh clone, and `ios/project.yml`
ships with the same placeholder values every time (`PRODUCT_BUNDLE_IDENTIFIER:
com.gova.GovaApp`, `CFBundleDisplayName: GovaApp`). If you skip this step, every app
you build from this template gets the same bundle ID and home-screen name — they
can't coexist on one device, and they can't be registered as separate App IDs in
App Store Connect.

Read `## App Name` from `SEED.md`. Derive `BundleSlug` — lowercase, alphanumeric only,
no spaces (e.g. "Task Manager" → `taskmanager`).

Edit `ios/project.yml`:
- `PRODUCT_BUNDLE_IDENTIFIER` → `com.gova.{BundleSlug}` (must be unique per app)
- `CFBundleDisplayName` → the app name from SEED.md, verbatim

Leave the top-level `name:`, the `GovaApp` target, and the scheme name alone — they're
internal to this repo's tooling and don't need to be unique across apps.

Run `xcodegen generate` after editing.

---

## Step 3: Brainstorm

Use the `superpowers:brainstorming` skill with `SEED.md` as input.

Confirm with the developer:
- The screens each resource needs, driven by its endpoint kinds in the Generated Context (a `list` kind → a list screen; `detail` → a detail screen; `create`/`update`/`delete` → a create sheet / edit form / swipe-delete on those screens). A `scaffold_list` resource is list-only; a `scaffold_resource` resource is full CRUD.
- Navigation flow: which screen is root, which push onto the stack
- Whether authentication is required
- Any iOS-specific UX notes beyond the CLAUDE.md defaults

Wait for developer approval before proceeding.

---

## Step 4: Write an Implementation Plan

Use the `superpowers:writing-plans` skill.

**Mandatory plan order:**
1. Swift model structs — one file per data model in Generated Context
2. Auth screens: `LoginViewModel.swift` + `LoginView.swift` (if auth required)
3. Per resource in the Generated Context: a ViewModel with one method per available endpoint kind, then its View(s) — a list View (with create sheet / swipe-delete if those kinds exist) and, if a `detail` kind exists, a detail View (with edit form / delete). Generate ONLY the operations the resource's endpoints expose (see the CLAUDE.md Step 4 kind→screen table). Run `xcodegen generate` after each file.
4. Navigation wiring in `ContentView.swift`
5. Build verification: `xcodebuild -scheme GovaApp -sdk iphonesimulator build`

Note: bearer auth ships with the web app's `scaffold_auth` (cookie + bearer in one run), so
`/build` scaffolds nothing auth-related here. If `/export:mobile`'s summary showed
`bearer_auth=no`, the developer needs to run `scaffold_auth` in their gova-monolith project
before this plan's auth screens have a token endpoint to call.

**Mandatory constraints for every task in the plan:**
- Follow the CLAUDE.md translation guide before writing each screen
- Run `xcodegen generate` inside `ios/` after adding every new Swift file
- `APIClient.swift` and `AuthManager.swift` are pre-committed — never regenerate them
- Every ViewModel must have `@Published var isLoading = false` and `@Published var errorMessage: String?`
- Every View must display `errorMessage` when non-nil

---

## Step 5: Create Feature Branch

Use `superpowers:using-git-worktrees` to create an isolated branch.
Derive the branch name from the app name in SEED.md: "Task Manager" → `build/task-manager`

---

## Step 6: Implement

Use `superpowers:subagent-driven-development` to execute the plan.

Each subagent must confirm before starting each screen task:
> "According to CLAUDE.md, the ViewModel for this screen owns [list state],
> calls [list API endpoints], and the View renders [describe UI elements]."

After every new Swift file is written, the subagent must run:
```bash
cd ios && xcodegen generate
```

---

## Step 7: Verify

Run:
```bash
cd ios && xcodebuild -scheme GovaApp -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
```

Expected last line: `** BUILD SUCCEEDED **`

Then use `superpowers:verification-before-completion` and confirm:
- All screens from SEED.md Generated Context are implemented
- Every ViewModel has `isLoading` and `errorMessage` states
- Every View displays an error when `errorMessage` is non-nil
- No force unwraps (`!`) in generated code
- No raw `URLSession` calls — always `APIClient.shared`
- No tokens in `UserDefaults`
- Auth gate wired if auth was required
- `xcodegen generate` was run after the last file was added

---

## Step 8: Done

Report to the developer:

> **Build complete.**
>
> Open `ios/GovaApp.xcodeproj` in Xcode and run on the iOS Simulator.
> Branch: `build/[app-name]`
>
> Make sure your gova-monolith API is running and `Config.plist` points to the correct base URL.
