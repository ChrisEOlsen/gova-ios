---
description: Translate a gova-monolith web app to a native iOS SwiftUI app
---

You are running the GOVA iOS build workflow. Read this file completely before taking any action.

---

## Step 1: Validate

Read `SEED.md`. Check that the Generated Context block is populated — it must contain
screen definitions and API endpoints, not just the placeholder comment.

If it is empty or contains only the placeholder, STOP and tell the developer:

> "The Generated Context section of SEED.md is empty. Run `/export:mobile` in your
> gova-monolith project first, then paste the output into SEED.md below the placeholder comment."

---

## Step 2: Brainstorm

Use the `superpowers:brainstorming` skill with `SEED.md` as input.

Confirm with the developer:
- The complete list of screens to generate (one per JS module in Generated Context)
- Navigation flow: which screen is root, which push onto the stack
- Whether authentication is required
- Any iOS-specific UX notes beyond the CLAUDE.md defaults

Wait for developer approval before proceeding.

---

## Step 3: Write an Implementation Plan

Use the `superpowers:writing-plans` skill.

**Mandatory plan order:**
1. `scaffold_mobile_auth` via MCP (if auth required and MCP is wired) — idempotent, safe to run first
2. Swift model structs — one file per data model in Generated Context
3. Auth screens: `LoginViewModel.swift` + `LoginView.swift` (if auth required)
4. One task per screen from SEED.md: ViewModel → View → `xcodegen generate`
5. Navigation wiring in `ContentView.swift`
6. Build verification: `xcodebuild -scheme GovaApp -sdk iphonesimulator build`

**Mandatory constraints for every task in the plan:**
- Follow the CLAUDE.md translation guide before writing each screen
- Run `xcodegen generate` inside `ios/` after adding every new Swift file
- `APIClient.swift` and `AuthManager.swift` are pre-committed — never regenerate them
- Every ViewModel must have `@Published var isLoading = false` and `@Published var errorMessage: String?`
- Every View must display `errorMessage` when non-nil

---

## Step 4: Create Feature Branch

Use `superpowers:using-git-worktrees` to create an isolated branch.
Derive the branch name from the app name in SEED.md: "Task Manager" → `build/task-manager`

---

## Step 5: Implement

Use `superpowers:subagent-driven-development` to execute the plan.

Each subagent must confirm before starting each screen task:
> "According to CLAUDE.md, the ViewModel for this screen owns [list state],
> calls [list API endpoints], and the View renders [describe UI elements]."

After every new Swift file is written, the subagent must run:
```bash
cd ios && xcodegen generate
```

---

## Step 6: Verify

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

## Step 7: Done

Report to the developer:

> **Build complete.**
>
> Open `ios/GovaApp.xcodeproj` in Xcode and run on the iOS Simulator.
> Branch: `build/[app-name]`
>
> Make sure your gova-monolith API is running and `Config.plist` points to the correct base URL.
