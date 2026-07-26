# iOS Hardening (Build C) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the gova-ios template a real UI test target with a generic launch-and-navigate smoke test, and ship device-ready defaults (ATS local-networking + a `DEVELOPMENT_TEAM` slot) so a first real-device install isn't blocked.

**Architecture:** Add a pre-committed, app-agnostic XCUITest that walks every tab and pushes a detail (catching navigation-binding bugs unit tests/greps miss); wire it as a test target in `project.yml`; add ATS + signing defaults to `project.yml` (the durable source `xcodegen` regenerates from). Docs teach `/build` and `prep` accordingly. No app behavior changes.

**Tech Stack:** Swift / XCUITest, xcodegen (`project.yml`), Markdown. Tools available here: `xcodegen`, `swift`, `swiftc`. No simulator — verification is structural (`xcodegen generate` parses+wires; `swiftc -parse` checks syntax). The real `xcodebuild test` runs in the developer's Xcode.

## Global Constraints

- **The smoke test is generic** — no app-specific names or identifiers; only native XCUITest queries (`tabBars`, `cells`, `navigationBars`). It must degrade gracefully (no tab bar → assert something interactive rendered, then return) so it never fails spuriously on a single-screen or auth-gated app.
- **Durability:** everything that must survive `xcodegen generate` (ATS, `DEVELOPMENT_TEAM`, test-target wiring) lives in `project.yml`, never hand-edited into the generated `.xcodeproj` (which is gitignored).
- **ATS relaxation is local-only:** `NSAllowsLocalNetworking: true` — never `NSAllowsArbitraryLoads`.
- **No behavior change:** `APIClient`, decoding, auth flow, and existing app sources are untouched.
- **`.xcodeproj` is gitignored** — `xcodegen generate` during verification produces an untracked project; do not commit it, and it needs no revert (git ignores it).

---

### Task 1: Generic launch-and-navigate smoke test

**Files:**
- Create: `ios/GovaAppUITests/SmokeTest.swift`

**Interfaces:**
- Consumes: nothing (pure XCUITest against a launched `XCUIApplication`).
- Produces: the `GovaAppUITests` target's source (Task 2 wires the target to this directory).

- [ ] **Step 1: Write the smoke test**

Create `ios/GovaAppUITests/SmokeTest.swift`:

```swift
import XCTest

/// App-agnostic smoke test: launches the app, taps every tab, and confirms that
/// tapping a list row pushes a detail screen. It uses only native XCUITest
/// queries, so it works on any generated GOVA app without app-specific
/// identifiers. It degrades gracefully on a single-screen or auth-gated app.
final class SmokeTest: XCTestCase {

    func testLaunchesWalksTabsAndPushesADetail() {
        let app = XCUIApplication()
        app.launch()

        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 15) else {
            // No tab bar: a single-screen app, or a login gate. A blank launch is
            // still a failure, so assert *something* interactive rendered.
            let rendered = app.buttons.firstMatch.waitForExistence(timeout: 5)
                || app.staticTexts.firstMatch.waitForExistence(timeout: 5)
                || app.textFields.firstMatch.waitForExistence(timeout: 5)
            XCTAssertTrue(rendered, "app launched to an empty screen")
            return
        }

        // Every tab must be tappable and respond.
        let tabs = tabBar.buttons
        XCTAssertGreaterThan(tabs.count, 0, "tab bar has no tabs")
        for i in 0..<tabs.count {
            let tab = tabs.element(boundBy: i)
            tab.tap()
            XCTAssertTrue(tab.exists, "tab \(i) disappeared after tapping")
        }

        // From the first tab that has rows, push a detail and confirm it bound.
        // A row that fails to push a real detail (the Logger bug) fails here.
        for i in 0..<tabs.count {
            tabs.element(boundBy: i).tap()
            let firstCell = app.cells.firstMatch
            if firstCell.waitForExistence(timeout: 3) {
                firstCell.tap()
                let backButton = app.navigationBars.buttons.firstMatch
                XCTAssertTrue(
                    backButton.waitForExistence(timeout: 5),
                    "tapping a row did not push a detail screen (no nav back button appeared)"
                )
                if backButton.exists { backButton.tap() }
                return
            }
        }
        // No tab had rows (empty data set) — the tab walk above still validated
        // navigation; nothing more to push.
    }
}
```

- [ ] **Step 2: Syntax-check the Swift**

Run: `swiftc -parse ios/GovaAppUITests/SmokeTest.swift`
Expected: no output, exit 0 (syntax valid). Note: `-parse` is syntax-only; full XCTest typechecking needs the iOS SDK and happens in Xcode. If `swiftc -parse` complains it cannot find `XCTest` — that is a *type/import* resolution error, not a syntax error; re-run with `swiftc -parse -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" ios/GovaAppUITests/SmokeTest.swift` to parse against the SDK. If neither is available, fall back to visual review that braces/keywords are balanced (the file above is known-good).

- [ ] **Step 3: Commit**

```bash
git add ios/GovaAppUITests/SmokeTest.swift
git commit -m "test(ios): generic launch-and-navigate smoke test

App-agnostic XCUITest: launches, taps every tab, and asserts tapping a row
pushes a detail (a nav back button appears). Catches navigation-binding bugs
that unit tests and greps miss. Degrades gracefully on single-screen/auth-gated
apps.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Wire the UI test target + ship device-deploy defaults in `project.yml`

**Files:**
- Modify: `ios/project.yml` — add the `GovaAppUITests` target; set `scheme.testTargets`; add ATS to `GovaApp.info.properties`; add signing to `GovaApp.settings.base`.

**Interfaces:**
- Consumes: `ios/GovaAppUITests/SmokeTest.swift` (Task 1) — the target's source directory must exist for xcodegen to build the target.
- Produces: a `GovaAppUITests` target and a scheme test action; ATS + signing defaults.

- [ ] **Step 1: Add ATS + signing to the `GovaApp` target**

In `ios/project.yml`, under `targets: GovaApp: info: properties:`, add the ATS key (sibling of `CFBundleDisplayName` etc.):

```yaml
        NSAppTransportSecurity:
          NSAllowsLocalNetworking: true
```

And under `targets: GovaApp: settings: base:` (which today holds only `PRODUCT_BUNDLE_IDENTIFIER`), add:

```yaml
        # DEVELOPMENT_TEAM is written by /prep so it survives `xcodegen generate`.
        # Blank builds fine for the simulator; set it for a physical-device build.
        DEVELOPMENT_TEAM: ""
        CODE_SIGN_STYLE: Automatic
```

- [ ] **Step 2: Add the UI test target and wire the scheme**

In `ios/project.yml`, change the `GovaApp` scheme from `testTargets: []` to reference the new target:

```yaml
    scheme:
      testTargets:
        - GovaAppUITests
```

Then add a sibling target under `targets:` (after `GovaApp:`):

```yaml
  GovaAppUITests:
    type: bundle.ui-testing
    platform: iOS
    sources:
      - path: GovaAppUITests
    dependencies:
      - target: GovaApp
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.gova.GovaAppUITests
        TEST_TARGET_NAME: GovaApp
```

- [ ] **Step 3: Verify xcodegen parses and wires the target**

Run: `cd ios && xcodegen generate`
Expected: succeeds with no error (a benign note about the generated project is fine). Then confirm the target and its test wiring exist in the generated project:

```bash
cd ios
grep -q "GovaAppUITests" GovaApp.xcodeproj/project.pbxproj && echo "target present"
# the scheme's TestAction should reference the UITests target:
grep -rl "GovaAppUITests" GovaApp.xcodeproj/xcshareddata/xcschemes/ && echo "scheme test action present"
```

Expected: both echo. If `xcodegen generate` errors that the `GovaAppUITests` sources path is empty, confirm Task 1 created `ios/GovaAppUITests/SmokeTest.swift` first.

- [ ] **Step 4: Confirm ATS + signing landed in the generated Info.plist / build settings**

```bash
cd ios
# ATS is written into the generated Info.plist:
grep -A1 "NSAllowsLocalNetworking" GovaApp.xcodeproj/../GovaApp/Info.plist 2>/dev/null \
  || plutil -p GovaApp.xcodeproj/project.pbxproj | grep -i "NSAllowsLocalNetworking" \
  || grep -ri "NSAllowsLocalNetworking" GovaApp.xcodeproj GovaApp/Info.plist
# DEVELOPMENT_TEAM setting present (empty is fine):
grep -i "DEVELOPMENT_TEAM" GovaApp.xcodeproj/project.pbxproj && echo "team setting present"
```

Expected: ATS local-networking and the `DEVELOPMENT_TEAM` build setting both appear. (`xcodegen` writes `info.properties` into `GovaApp/Info.plist`; if the app's Info.plist is regenerated, the ATS dict is in it.)

- [ ] **Step 5: Commit** (do NOT commit the gitignored `.xcodeproj`)

```bash
git add ios/project.yml
git status --porcelain    # confirm only project.yml staged; GovaApp.xcodeproj is gitignored
git commit -m "build(ios): UI test target + ATS local-networking + signing slot

Adds a GovaAppUITests target wired into the scheme's test action, an ATS
NSAllowsLocalNetworking exception (LAN http on device works out of the box), and
a DEVELOPMENT_TEAM/CODE_SIGN_STYLE slot in project.yml so signing survives
xcodegen. .xcodeproj stays gitignored.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: Docs — `CLAUDE.md` verification/deploy notes + `prep` team prompt

**Files:**
- Modify: `CLAUDE.md` — a Verification note (smoke test) and a Device-deploy note.
- Modify: `.claude/commands/prep.md` — prompt for the Apple Team ID and write it to `project.yml`; update the ATS note.

**Interfaces:**
- Consumes: the target/defaults from Task 2.
- Produces: prose rules only.

- [ ] **Step 1: Add a Verification + Device-deploy note to `CLAUDE.md`**

Add a new subsection near the other build/verification guidance in `CLAUDE.md` (place it after the Step 4 screen rules / before the constraints list — wherever the app-structure guidance ends):

```markdown
### Verification — UI smoke test

The template ships `ios/GovaAppUITests/SmokeTest.swift`, a generic XCUITest that
launches the app, taps every tab, and asserts that tapping a list row pushes a
detail screen. It is app-agnostic — keep it building and green. Running it (Xcode
▸ Test, or `xcodebuild test`) is the way to catch **navigation-binding** bugs that
unit tests, a successful build, and greps cannot see (e.g. a `navigationDestination`
that never binds, so a row taps into a blank and unwinds).

When generating screens, give each `TabView` item and each list row a stable
`.accessibilityIdentifier` (e.g. the resource name). The generic smoke test works
without them, but any app-specific UI assertions you add will need them.

### Device deploy

- **LAN http works on device by default** — `project.yml` ships an ATS
  `NSAllowsLocalNetworking` exception, so a physical iPhone can reach a dev server
  at `http://<LAN-IP>:8080`. (A non-local http host still needs the `/launch`
  https tunnel.)
- **Signing:** set `DEVELOPMENT_TEAM` (your Apple Team ID) — `/prep` writes it into
  `project.yml` so it survives `xcodegen generate`. Blank is fine for the simulator.
```

- [ ] **Step 2: Add the Team-ID prompt to `prep.md` Step 3**

In `.claude/commands/prep.md`, add a fifth gathered item to Step 3 (after item **4. Design Notes**):

```markdown
**5. Apple Team ID** — *optional*. The 10-character Apple Developer Team ID used to
sign device builds (Xcode ▸ Settings ▸ Accounts, or the current `DEVELOPMENT_TEAM`
in `ios/project.yml`). Offer the current `project.yml` value if non-empty, and
"Skip (simulator only)". Blank is fine — the simulator needs no team.
```

- [ ] **Step 3: Add a step to write the Team ID to `project.yml`**

In `.claude/commands/prep.md`, add a new step after Step 6 (Sync Config.plist):

```markdown
## Step 6b — Set the signing team

If the developer gave an Apple Team ID, write it into `ios/project.yml` as the
`DEVELOPMENT_TEAM` value under `targets: GovaApp: settings: base:` (replace the
empty string). This lives in `project.yml` so it survives `xcodegen generate`. If
they skipped it, leave it empty — simulator builds do not need a team. Do not run
`xcodegen generate` here; `/build` regenerates the project.
```

- [ ] **Step 4: Update the ATS note in `prep.md` Step 4**

In `.claude/commands/prep.md` Step 4, replace the API-Base-URL warning line:

```markdown
- API Base URL parses as a URL with a scheme. Warn (do not block) if it is `http://`
  and not localhost — iOS ATS blocks cleartext to non-local hosts unless configured.
```

with:

```markdown
- API Base URL parses as a URL with a scheme. `http://` to a **local/LAN** host works
  on device — the template ships an ATS `NSAllowsLocalNetworking` exception. Warn
  (do not block) only if it is `http://` to a **non-local** host, which ATS still
  blocks; recommend the `/launch` https tunnel for that case.
```

- [ ] **Step 5: Consistency check (docs)**

Re-read the three doc edits together with `project.yml`. Confirm: the ATS key name (`NSAllowsLocalNetworking`), the setting name (`DEVELOPMENT_TEAM`), the target name (`GovaAppUITests`), and the smoke-test path (`ios/GovaAppUITests/SmokeTest.swift`) match exactly across `CLAUDE.md`, `prep.md`, and `project.yml`. Fix any drift (the code/project.yml is the source of truth).

- [ ] **Step 6: Commit**

```bash
git add CLAUDE.md .claude/commands/prep.md
git commit -m "docs(ios): smoke-test verification note + device-deploy/team guidance

CLAUDE.md documents the smoke test and the LAN-http/signing device defaults;
prep prompts for the Apple Team ID and writes it to project.yml, and its ATS note
reflects that local-network http now works by default.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: End-to-end structural verification

**Files:** none committed — regenerates the project and parses the test, proving the target wires up and the smoke test is valid Swift.

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces: evidence; a clean tracked tree (the regenerated `.xcodeproj` is gitignored).

- [ ] **Step 1: Regenerate and confirm the full wiring**

```bash
cd ios && xcodegen generate
grep -q "GovaAppUITests" GovaApp.xcodeproj/project.pbxproj && echo "OK: UITests target"
grep -rq "GovaAppUITests" GovaApp.xcodeproj/xcshareddata/xcschemes/ && echo "OK: scheme test action"
grep -qi "NSAllowsLocalNetworking" GovaApp/Info.plist && echo "OK: ATS in Info.plist"
grep -qi "DEVELOPMENT_TEAM" GovaApp.xcodeproj/project.pbxproj && echo "OK: signing slot"
```

Expected: four `OK:` lines.

- [ ] **Step 2: Parse the smoke test against the simulator SDK**

```bash
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path 2>/dev/null) && \
  swiftc -parse -sdk "$SDK" ios/GovaAppUITests/SmokeTest.swift && echo "OK: smoke test parses" \
  || swiftc -parse ios/GovaAppUITests/SmokeTest.swift && echo "OK: syntax parses"
```

Expected: an `OK:` line (SDK parse preferred; plain syntax parse acceptable).

- [ ] **Step 3: Confirm the tracked tree is clean of generated artifacts**

```bash
cd /Users/crispychris/Desktop/repos/gova-ios
git status --porcelain
```

Expected: empty (Tasks 1–3 already committed; `GovaApp.xcodeproj` is gitignored so it does not appear). If anything untracked appears that is NOT the gitignored project, investigate.

- [ ] **Step 4: Record evidence** (no commit) — note the four `OK:` lines + parse result in the execution ledger.

---

## Self-Review

**1. Spec coverage:**
- UI test target (spec §project.yml) → T2 (target + testTargets). ✅
- Generic smoke test walking tabs + pushing a detail (spec) → T1. ✅
- ATS `NSAllowsLocalNetworking` (spec decision) → T2 Step 1 + doc T3. ✅
- `DEVELOPMENT_TEAM` in `project.yml` + `prep` prompt (spec decision) → T2 Step 1 + T3 Steps 2–3. ✅
- CLAUDE.md verification + deploy notes; prep ATS note update (spec) → T3. ✅
- Structural verification via xcodegen + swiftc (spec) → T2 Step 3–4, T4. ✅
- Non-goals (no per-app test gen, no APIClient/auth change, no CI) → nothing added for them; T1 test is generic; no Swift app source touched. ✅

**2. Placeholder scan:** No TBD/TODO. Full smoke-test code and exact YAML/doc blocks shown. The one "place it wherever the app-structure guidance ends" in T3 Step 1 is a placement note with the exact content to insert. ✅

**3. Type/name consistency:** `GovaAppUITests` (target + dir), `ios/GovaAppUITests/SmokeTest.swift`, `NSAllowsLocalNetworking`, `DEVELOPMENT_TEAM`, `CODE_SIGN_STYLE: Automatic`, `TEST_TARGET_NAME: GovaApp` used identically across T1/T2/T3, and T3 Step 5 cross-checks them against `project.yml`. ✅
