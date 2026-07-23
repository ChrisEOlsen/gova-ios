# iOS Manifest Consumer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `gova-ios` read the monolith's machine-readable manifest instead of reverse-engineering source — `/export:mobile` transforms `api.json` deterministically, and the iOS app asserts its version against `/api/v1/_version` at launch.

**Architecture:** A tested `python3` script (`.claude/scripts/export_manifest.py`) transforms `api.json` → the SEED.md Generated Context block; the `/export:mobile` command just invokes it. A pre-committed Swift `VersionGate` checks `_version` at launch and fails open. Everything is in the `gova-ios` repo.

**Tech Stack:** `python3` (macOS system, stdlib only) for the deterministic transform + its `unittest` tests; Swift 5.9 / SwiftUI (iOS 17), XcodeGen, `xcodebuild` for the version gate; Markdown for the command/CLAUDE.md docs.

## Global Constraints

- **Spec:** `docs/superpowers/specs/2026-07-23-ios-manifest-consumer-design.md` — authoritative.
- **Branch:** `build/ios-manifest-consumer`. This build is entirely in the `gova-ios` repo. It touches NO monolith code.
- **Determinism is the point.** The spec requires re-running `/export:mobile` on an unchanged manifest to produce a byte-identical Generated Context. That is why the transform is a `python3` script, not LLM prose — prose transcription of JSON cannot guarantee it. Verify the transform with `python3` unit tests, not by eye.
- **Manifest source:** `$WEB_APP/src/app/api.json` on disk (committed, deterministic). Export reads no `.go`/`.js`/`main.go` and needs no running server and no MCP.
- **Swift type map (fixed):** `int`→`Int`, `string`→`String`, `boolean`→`Bool`, `float`→`Double`, `timestamp`→`Date`. `id` is `Int`. A `nullable:true` field takes the optional form (`String?`).
- **Bearer (mobile) auth ready** iff some endpoint has `kind == "mobile_login"`.
- **A screen** is generated per model that has an endpoint with `kind == "list"`.
- **Version gate fails OPEN:** any network/decode error, unreachable endpoint, or missing/malformed version → allow the app. Block ONLY when the client version is provably `<` `min_client_version`.
- **Client version** from `CFBundleShortVersionString` (added to `project.yml`), compared with a pure semver comparator.
- **No Swift test runner** in this repo — Swift is verified by `xcodebuild build` succeeding plus reasoning over the documented cases. Do NOT add an XCTest target.
- **Python is stdlib-only. No pip installs.** No Node/npm anywhere.
- `.claude/scripts/` and `.claude/commands/` are committed template files (not gitignored); `.mcp.json` and `.claude/settings.local.json` ARE gitignored.

---

## File Structure

**New files:**

| File | Responsibility |
|---|---|
| `.claude/scripts/export_manifest.py` | Pure `render_context(manifest)` + `splice_seed(seed, block)` + CLI; the deterministic transform |
| `.claude/scripts/test_export_manifest.py` | `unittest` coverage for both functions |
| `ios/GovaApp/Lib/VersionGate.swift` | Launch-time `_version` check, semver compare, fail-open |
| `ios/GovaApp/Lib/UpdateRequiredView.swift` | Blocking "update required" screen |

**Modified files:**

| File | Change |
|---|---|
| `.claude/commands/export-mobile.md` | Rewrite: read Web App Path → run the script → verify → report; delete the Go/JS/main.go/inspect_app steps |
| `ios/GovaApp/GovaAppApp.swift` | Wire `VersionGate`; swap `ContentView` ↔ `UpdateRequiredView` |
| `ios/project.yml` | Add `CFBundleShortVersionString` / `CFBundleVersion` to the target's `info.properties` |
| `CLAUDE.md` | Reframe screens as manifest-resource-derived; add version-gate infra note; list the two new files |
| `.claude/commands/build.md` | Reframe screen derivation from JS modules to manifest resources |

---

## Task 1: The manifest → Generated-Context transform

**Files:**
- Create: `.claude/scripts/export_manifest.py`
- Test: `.claude/scripts/test_export_manifest.py`

**Interfaces:**
- Consumes: nothing.
- Produces: `render_context(manifest: dict) -> str` — the Generated Context markdown block. Task 2 adds `splice_seed` and the CLI to the same file.

**Context:** The manifest shape is Build 2's `api.json`: `{api_version, hash, generated_at, models:[{name, table, fields:[{name, type, nullable}]}], endpoints:[{method, path, handler, deps, auth, model?, kind}]}`. `render_context` must be deterministic — sort models by `name`, endpoints by `(path, method)` — so output never depends on input ordering.

- [ ] **Step 1: Write the failing test**

Create `.claude/scripts/test_export_manifest.py`:

```python
import unittest
from export_manifest import render_context, swift_type, pascal

SAMPLE = {
    "api_version": "1.0.0",
    "hash": "sha256:abc123",
    "generated_at": "2026-07-23T00:00:00Z",
    "models": [
        {"name": "project", "table": "projects", "fields": [
            {"name": "id", "type": "int", "nullable": False},
            {"name": "name", "type": "string", "nullable": False},
            {"name": "notes", "type": "string", "nullable": True},
            {"name": "created_at", "type": "timestamp", "nullable": False},
        ]},
        {"name": "order_item", "table": "order_items", "fields": [
            {"name": "id", "type": "int", "nullable": False},
            {"name": "qty", "type": "int", "nullable": False},
            {"name": "created_at", "type": "timestamp", "nullable": False},
        ]},
    ],
    "endpoints": [
        {"method": "GET", "path": "/api/v1/order_items", "handler": "OrderItemListGET",
         "deps": ["read", "write", "cache"], "auth": False, "model": "order_item", "kind": "list"},
        {"method": "GET", "path": "/api/v1/projects", "handler": "ProjectListGET",
         "deps": ["read", "write", "cache"], "auth": False, "model": "project", "kind": "list"},
        {"method": "POST", "path": "/api/v1/auth/login_token", "handler": "MobileLoginPOST",
         "deps": ["read", "write", "cache"], "auth": False, "kind": "mobile_login"},
        {"method": "GET", "path": "/api/v1/auth/me_token", "handler": "MobileMeGET",
         "deps": ["read", "write", "cache"], "auth": False, "kind": "mobile_me"},
    ],
}


class TestSwiftType(unittest.TestCase):
    def test_map(self):
        self.assertEqual(swift_type("int", False), "Int")
        self.assertEqual(swift_type("string", False), "String")
        self.assertEqual(swift_type("boolean", False), "Bool")
        self.assertEqual(swift_type("float", False), "Double")
        self.assertEqual(swift_type("timestamp", False), "Date")

    def test_nullable_is_optional(self):
        self.assertEqual(swift_type("string", True), "String?")
        self.assertEqual(swift_type("int", True), "Int?")

    def test_unknown_type_defaults_to_string(self):
        self.assertEqual(swift_type("weird", False), "String")


class TestPascal(unittest.TestCase):
    def test_single(self):
        self.assertEqual(pascal("project"), "Project")

    def test_snake(self):
        self.assertEqual(pascal("order_item"), "OrderItem")


class TestRenderContext(unittest.TestCase):
    def setUp(self):
        self.out = render_context(SAMPLE)

    def test_header_and_hash(self):
        self.assertIn("Generated by /export:mobile from api.json — manifest hash sha256:abc123.", self.out)
        self.assertIn("- api_version: 1.0.0", self.out)

    def test_bearer_ready_yes(self):
        self.assertIn("- Bearer (mobile) auth ready: yes", self.out)

    def test_models_sorted_by_name(self):
        # order_item sorts before project regardless of manifest order
        self.assertLess(self.out.index("**OrderItem**"), self.out.index("**Project**"))

    def test_nullable_field_is_optional(self):
        self.assertIn("- notes: string? → String?", self.out)

    def test_nonnullable_field(self):
        self.assertIn("- name: string → String", self.out)

    def test_timestamp_maps_to_date(self):
        self.assertIn("- created_at: timestamp → Date", self.out)

    def test_table_shown(self):
        self.assertIn("**Project**  (table: projects)", self.out)

    def test_resource_endpoints_grouped(self):
        self.assertIn("**project**", self.out)
        self.assertIn("- GET /api/v1/projects  [list]  auth:no", self.out)

    def test_auth_endpoints_section(self):
        self.assertIn("- POST /api/v1/auth/login_token  [mobile_login]", self.out)
        self.assertIn("- GET /api/v1/auth/me_token  [mobile_me]", self.out)

    def test_screens_line(self):
        self.assertIn("One list screen per model with a `list` endpoint: [order_item, project]", self.out)
        self.assertIn("Login screen: yes", self.out)

    def test_deterministic_regardless_of_input_order(self):
        import copy
        shuffled = copy.deepcopy(SAMPLE)
        shuffled["models"].reverse()
        shuffled["endpoints"].reverse()
        self.assertEqual(render_context(shuffled), self.out)


class TestRenderContextEmpty(unittest.TestCase):
    def test_empty_manifest(self):
        out = render_context({"api_version": "1.0.0", "hash": "sha256:0", "models": [], "endpoints": []})
        self.assertIn("- Bearer (mobile) auth ready: no", out)
        self.assertIn("One list screen per model with a `list` endpoint: []", out)
        self.assertIn("Login screen: no", out)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd .claude/scripts && python3 -m unittest test_export_manifest -v`
Expected: FAIL — `ModuleNotFoundError` / `ImportError: cannot import name 'render_context'`.

- [ ] **Step 3: Write the implementation**

Create `.claude/scripts/export_manifest.py`:

```python
#!/usr/bin/env python3
"""Transform a gova-monolith api.json manifest into the SEED.md Generated
Context block. Deterministic: output depends only on manifest content, not on
the ordering of models/endpoints within it."""

import json
import sys

_SWIFT_TYPES = {
    "int": "Int",
    "string": "String",
    "boolean": "Bool",
    "float": "Double",
    "timestamp": "Date",
}


def swift_type(field_type: str, nullable: bool) -> str:
    base = _SWIFT_TYPES.get(field_type, "String")
    return base + "?" if nullable else base


def pascal(name: str) -> str:
    return "".join(part[:1].upper() + part[1:] for part in name.split("_") if part)


def render_context(manifest: dict) -> str:
    models = sorted(manifest.get("models") or [], key=lambda m: m["name"])
    endpoints = sorted(
        manifest.get("endpoints") or [],
        key=lambda e: (e["path"], e["method"]),
    )
    api_version = manifest.get("api_version", "")
    hash_ = manifest.get("hash", "")

    bearer_ready = any(e.get("kind") == "mobile_login" for e in endpoints)
    list_models = sorted(
        {e["model"] for e in endpoints if e.get("kind") == "list" and e.get("model")}
    )

    lines = []
    lines.append("### Web App Context")
    lines.append(f"Generated by /export:mobile from api.json — manifest hash {hash_}.")
    lines.append("")
    lines.append("#### API")
    lines.append(f"- api_version: {api_version}")
    lines.append(f"- Bearer (mobile) auth ready: {'yes' if bearer_ready else 'no'}")
    lines.append("")

    lines.append("#### Models")
    for m in models:
        lines.append(f"**{pascal(m['name'])}**  (table: {m['table']})")
        for f in m.get("fields", []):
            display = f["type"] + ("?" if f.get("nullable") else "")
            lines.append(f"  - {f['name']}: {display} → {swift_type(f['type'], f.get('nullable', False))}")
        lines.append("")

    lines.append("#### Resources → endpoints")
    for m in models:
        m_eps = [e for e in endpoints if e.get("model") == m["name"]]
        if not m_eps:
            continue
        lines.append(f"**{m['name']}**")
        for e in m_eps:
            lines.append(f"  - {e['method']} {e['path']}  [{e.get('kind', '')}]  auth:{'yes' if e.get('auth') else 'no'}")
        lines.append("")

    lines.append("#### Auth endpoints")
    for e in endpoints:
        if not e.get("model"):
            lines.append(f"  - {e['method']} {e['path']}  [{e.get('kind', '')}]")
    lines.append("")

    lines.append("#### Screens to generate")
    lines.append(f"  - One list screen per model with a `list` endpoint: [{', '.join(list_models)}]")
    lines.append(f"  - Login screen: {'yes' if bearer_ready else 'no'}")

    return "\n".join(lines)
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd .claude/scripts && python3 -m unittest test_export_manifest -v`
Expected: PASS — all `TestSwiftType`, `TestPascal`, `TestRenderContext`, `TestRenderContextEmpty` cases (the `splice_seed`/CLI tests come in Task 2).

- [ ] **Step 5: Commit**

```bash
git add .claude/scripts/export_manifest.py .claude/scripts/test_export_manifest.py
git commit -m "feat: deterministic api.json -> Generated Context transform"
```

---

## Task 2: SEED.md idempotent splice + CLI

**Files:**
- Modify: `.claude/scripts/export_manifest.py` (add `splice_seed` + `main`)
- Modify: `.claude/scripts/test_export_manifest.py` (add splice tests)

**Interfaces:**
- Consumes: `render_context` (Task 1).
- Produces: `splice_seed(seed_text: str, block: str) -> str` — replaces everything below the marker, preserving everything above it byte-for-byte; `main()` — the CLI entry `export_manifest.py <api_json_path> <seed_md_path>`.

**Context:** The marker line is `<!-- /export:mobile WRITES BELOW THIS LINE -->`. Everything from the top of SEED.md through that marker is developer-authored and must survive byte-for-byte. If the marker is absent, append it then the block.

- [ ] **Step 1: Write the failing test**

Add to `.claude/scripts/test_export_manifest.py`:

```python
from export_manifest import splice_seed, MARKER

SEED_WITH_MARKER = """# iOS App Specification

## App Name
Task Manager

## Web App Path
/Users/dev/gova-monolith

---
## Generated Context
> Auto-populated by /export:mobile.

<!-- /export:mobile WRITES BELOW THIS LINE -->
### Web App Context
OLD STALE BLOCK THAT MUST BE REPLACED
"""


class TestSpliceSeed(unittest.TestCase):
    def test_preserves_developer_section_byte_for_byte(self):
        head = SEED_WITH_MARKER[: SEED_WITH_MARKER.index(MARKER) + len(MARKER)]
        out = splice_seed(SEED_WITH_MARKER, "NEW BLOCK")
        self.assertTrue(out.startswith(head))

    def test_replaces_below_marker(self):
        out = splice_seed(SEED_WITH_MARKER, "NEW BLOCK")
        self.assertIn("NEW BLOCK", out)
        self.assertNotIn("OLD STALE BLOCK", out)

    def test_idempotent(self):
        once = splice_seed(SEED_WITH_MARKER, "NEW BLOCK")
        twice = splice_seed(once, "NEW BLOCK")
        self.assertEqual(once, twice)

    def test_marker_absent_appends_marker_and_block(self):
        seed = "# Spec\n\n## App Name\nFoo\n"
        out = splice_seed(seed, "NEW BLOCK")
        self.assertTrue(out.startswith(seed))
        self.assertIn(MARKER, out)
        self.assertIn("NEW BLOCK", out)

    def test_marker_appears_exactly_once(self):
        out = splice_seed(SEED_WITH_MARKER, "NEW BLOCK")
        self.assertEqual(out.count(MARKER), 1)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd .claude/scripts && python3 -m unittest test_export_manifest -v`
Expected: FAIL — `ImportError: cannot import name 'splice_seed'`.

- [ ] **Step 3: Add `splice_seed`, `MARKER`, and `main`**

Append to `.claude/scripts/export_manifest.py`:

```python
MARKER = "<!-- /export:mobile WRITES BELOW THIS LINE -->"


def splice_seed(seed_text: str, block: str) -> str:
    """Replace everything below the marker with block; preserve everything from
    the top through the marker byte-for-byte. Append the marker first if absent."""
    if MARKER in seed_text:
        head = seed_text[: seed_text.index(MARKER) + len(MARKER)]
        return head + "\n\n" + block + "\n"
    sep = "" if seed_text.endswith("\n") else "\n"
    return seed_text + sep + MARKER + "\n\n" + block + "\n"


def main(argv=None) -> int:
    argv = argv if argv is not None else sys.argv[1:]
    if len(argv) != 2:
        print("usage: export_manifest.py <api.json path> <SEED.md path>", file=sys.stderr)
        return 2
    api_path, seed_path = argv
    try:
        with open(api_path) as fh:
            manifest = json.load(fh)
    except FileNotFoundError:
        print(f"api.json not found at {api_path}", file=sys.stderr)
        return 1
    except json.JSONDecodeError as exc:
        print(f"api.json is not valid JSON: {exc}", file=sys.stderr)
        return 1

    block = render_context(manifest)
    with open(seed_path) as fh:
        seed = fh.read()
    with open(seed_path, "w") as fh:
        fh.write(splice_seed(seed, block))

    n_models = len(manifest.get("models") or [])
    n_endpoints = len(manifest.get("endpoints") or [])
    bearer = any(e.get("kind") == "mobile_login" for e in (manifest.get("endpoints") or []))
    print(f"models={n_models} endpoints={n_endpoints} bearer_auth={'yes' if bearer else 'no'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

Note: the existing `if __name__ == "__main__":` block at the end of Task 1's file (there is none yet — Task 1's file ends at `render_context`) is now this `main` guard. Ensure the file has exactly one `if __name__ == "__main__":` guard.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd .claude/scripts && python3 -m unittest test_export_manifest -v`
Expected: PASS — all Task 1 and Task 2 cases.

- [ ] **Step 5: End-to-end smoke against a fixture**

```bash
cd .claude/scripts
cat > /tmp/api-fixture.json <<'EOF'
{"api_version":"1.0.0","hash":"sha256:fix","generated_at":"2026-07-23T00:00:00Z",
 "models":[{"name":"project","table":"projects","fields":[
   {"name":"id","type":"int","nullable":false},
   {"name":"notes","type":"string","nullable":true},
   {"name":"created_at","type":"timestamp","nullable":false}]}],
 "endpoints":[{"method":"GET","path":"/api/v1/projects","handler":"ProjectListGET",
   "deps":["read","write","cache"],"auth":false,"model":"project","kind":"list"}]}
EOF
printf '# Spec\n\n## App Name\nFoo\n\n<!-- /export:mobile WRITES BELOW THIS LINE -->\nOLD\n' > /tmp/seed-fixture.md
python3 export_manifest.py /tmp/api-fixture.json /tmp/seed-fixture.md
echo "---- resulting SEED ----"
cat /tmp/seed-fixture.md
```
Expected: prints `models=1 endpoints=1 bearer_auth=no`; the SEED file keeps `# Spec ... ## App Name\nFoo` above the marker, and below it shows the `### Web App Context` block with `notes: string? → String?` and `Screens to generate ... [project]`, and `OLD` is gone.

- [ ] **Step 6: Commit**

```bash
git add .claude/scripts/export_manifest.py .claude/scripts/test_export_manifest.py
git commit -m "feat: idempotent SEED.md splice and export CLI"
```

---

## Task 3: Rewrite the `/export:mobile` command

**Files:**
- Modify: `.claude/commands/export-mobile.md` (full rewrite)

**Interfaces:**
- Consumes: the script from Tasks 1-2 (`python3 .claude/scripts/export_manifest.py <api.json> SEED.md`).
- Produces: no code. The command instructs the LLM to run the script.

**Context:** The command currently has 8 steps, of which Steps 2-5 parse Go structs / JS / main.go / call inspect_app. Those are deleted. The command becomes: read Web App Path, verify api.json exists, run the script, verify, report.

- [ ] **Step 1: Rewrite the command file**

Replace the entire contents of `.claude/commands/export-mobile.md` with:

```markdown
# /export:mobile

Populate the SEED.md Generated Context from the linked gova-monolith web app's
machine-readable API manifest. Run this from the gova-ios directory.

This reads ONE file — the monolith's committed `src/app/api.json` (the manifest
Build 2 publishes) — and transforms it deterministically. It does not parse Go or
JS source, does not grep main.go, and needs no running server and no MCP.

---

## Step 1 — Read Web App Path from SEED.md

Open `SEED.md`. Find the `## Web App Path` value. If it is blank or still the
placeholder, STOP and tell the developer:

> "Set `Web App Path` in SEED.md to the absolute path of your gova-monolith repo
> (e.g. `/Users/yourname/Desktop/repos/gova-monolith`), then run /export:mobile
> again."

Set `$WEB_APP` to the resolved absolute path.

---

## Step 2 — Check the manifest exists

Confirm `$WEB_APP/src/app/api.json` exists. If it does not, STOP and tell the
developer:

> "No manifest found at `$WEB_APP/src/app/api.json`. Build the web app first —
> scaffold at least one resource in gova-monolith (e.g. `scaffold_list`) so the
> manifest is populated — then run /export:mobile again."

If it exists but has empty `models` and `endpoints`, warn that there is nothing to
translate yet (the developer has not scaffolded any resources), but continue.

---

## Step 3 — Run the transform

Run the deterministic transform script. It reads the manifest, writes the
Generated Context into SEED.md below the marker (preserving everything above it),
and prints a one-line summary:

```bash
python3 .claude/scripts/export_manifest.py "$WEB_APP/src/app/api.json" SEED.md
```

Do NOT hand-transform the JSON or edit the Generated Context yourself — the script
is the single source of the transform, so the output is byte-identical every run.

---

## Step 4 — Verify

Re-read `SEED.md` and confirm:
- The developer-authored section above `<!-- /export:mobile WRITES BELOW THIS LINE -->`
  is intact (App Name, API Base URL, Web App Path, Design Notes unchanged).
- Below the marker, the `### Web App Context` block is present exactly once and
  contains real models/endpoints (not placeholders).

If the script exited non-zero, report its error message to the developer and stop.

---

## Step 5 — Report

Tell the developer the script's summary line, e.g.:

> "`SEED.md` Generated Context populated — N models, N endpoints. Ready to run
> `/build`."

If the summary shows `bearer_auth=no`, add:

> "Bearer (mobile) auth is not set up yet. In your gova-monolith project, run
> `scaffold_mobile_auth` (after `scaffold_auth`) to add token endpoints, then
> re-run /export:mobile."
```

- [ ] **Step 2: Verify the command references the script correctly**

```bash
grep -n "export_manifest.py" .claude/commands/export-mobile.md
grep -nE "Read every .go|Read every .js|inspect_app|grep .*main.go|r\\.Get" .claude/commands/export-mobile.md
```
Expected: the first grep shows the `python3 .claude/scripts/export_manifest.py ...` invocation; the second returns NOTHING (all the old parse-the-source instructions are gone).

- [ ] **Step 3: Commit**

```bash
git add .claude/commands/export-mobile.md
git commit -m "feat: /export:mobile transforms api.json via the script, no source parsing"
```

---

## Task 4: iOS launch-time version gate

**Files:**
- Create: `ios/GovaApp/Lib/VersionGate.swift`
- Create: `ios/GovaApp/Lib/UpdateRequiredView.swift`
- Modify: `ios/GovaApp/GovaAppApp.swift`
- Modify: `ios/project.yml`

**Interfaces:**
- Consumes: `APIClient.shared.get(path:)` (pre-committed — unwraps the envelope, returns the decoded `data` payload).
- Produces: `VersionGate` (`ObservableObject`, `@Published state: VersionGate.State`), `compareSemver(_:_:) -> ComparisonResult`, `UpdateRequiredView`.

**Context:** No Swift test runner exists here (do NOT add an XCTest target). Verify with `xcodebuild build`. `APIClient.shared.get` already unwraps `{"ok":...,"data":...}` and returns the `data` payload decoded as the generic type, and decodes dates with `.iso8601`. The gate reuses it.

- [ ] **Step 1: Write `VersionGate.swift`**

Create `ios/GovaApp/Lib/VersionGate.swift`:

```swift
import Foundation

/// Compares two dotted numeric version strings ("1.2.0" vs "1.10"). Missing
/// trailing components are treated as 0, so "1.2" == "1.2.0". Non-numeric
/// components are treated as 0.
///
/// Cases this must get right (verified by reasoning, since there is no Swift
/// test runner in this repo):
///   compareSemver("1.0.0", "1.0.0") == .orderedSame
///   compareSemver("1.0",   "1.0.0") == .orderedSame       (missing → 0)
///   compareSemver("1.9.0", "1.10.0") == .orderedAscending (numeric, not lexical)
///   compareSemver("2.0.0", "1.9.9") == .orderedDescending
///   compareSemver("1.0.0", "1.0.1") == .orderedAscending
func compareSemver(_ a: String, _ b: String) -> ComparisonResult {
    let pa = a.split(separator: ".").map { Int($0) ?? 0 }
    let pb = b.split(separator: ".").map { Int($0) ?? 0 }
    let count = max(pa.count, pb.count)
    for i in 0..<count {
        let x = i < pa.count ? pa[i] : 0
        let y = i < pb.count ? pb[i] : 0
        if x != y { return x < y ? .orderedAscending : .orderedDescending }
    }
    return .orderedSame
}

@MainActor
final class VersionGate: ObservableObject {
    enum State: Equatable { case checking, ok, updateRequired }

    @Published private(set) var state: State = .checking

    private struct VersionInfo: Decodable {
        let apiVersion: String
        let minClientVersion: String
        enum CodingKeys: String, CodingKey {
            case apiVersion = "api_version"
            case minClientVersion = "min_client_version"
        }
    }

    /// Checks the server's minimum supported client version against this build.
    /// FAILS OPEN: any error, unreachable endpoint, or missing version leaves the
    /// app usable. Only a provably-too-old client is blocked.
    func check() async {
        do {
            let info: VersionInfo = try await APIClient.shared.get(path: "/api/v1/_version")
            let client = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
            if !client.isEmpty,
               compareSemver(client, info.minClientVersion) == .orderedAscending {
                state = .updateRequired
            } else {
                state = .ok
            }
        } catch {
            state = .ok  // fail open
        }
    }
}
```

- [ ] **Step 2: Write `UpdateRequiredView.swift`**

Create `ios/GovaApp/Lib/UpdateRequiredView.swift`:

```swift
import SwiftUI

/// Full-screen blocking view shown when the app build is older than the server's
/// minimum supported client version. Deliberately has no dismiss action.
struct UpdateRequiredView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Update Required")
                .font(.title2).bold()
            Text("A newer version of this app is required to continue. Please update to the latest version.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 3: Wire `GovaAppApp.swift`**

Replace `ios/GovaApp/GovaAppApp.swift` with:

```swift
import SwiftUI

@main
struct GovaAppApp: App {
    @StateObject private var auth = AuthManager.shared
    @StateObject private var versionGate = VersionGate()

    var body: some Scene {
        WindowGroup {
            Group {
                if versionGate.state == .updateRequired {
                    UpdateRequiredView()
                } else {
                    ContentView()
                        .environmentObject(auth)
                }
            }
            .task { await versionGate.check() }
        }
    }
}
```

(The `.updateRequired` comparison needs `State: Equatable`, which `VersionGate.State` declares.)

- [ ] **Step 4: Add the version to `project.yml`**

In `ios/project.yml`, under `targets: GovaApp: info: properties:` (where `CFBundleDisplayName` already is), add two keys so `CFBundleShortVersionString` exists for the gate to read:

```yaml
    info:
      path: GovaApp/Info.plist
      properties:
        CFBundleDisplayName: GovaApp
        CFBundleShortVersionString: "1.0.0"
        CFBundleVersion: "1"
        UILaunchScreen:
          UIColorName: ""
        UISupportedInterfaceOrientations:
          - UIInterfaceOrientationPortrait
```

- [ ] **Step 5: Regenerate the project and build**

```bash
cd ios && xcodegen generate
xcodebuild -scheme GovaApp -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`. If the simulator name `iPhone 16` is unavailable, run `xcodebuild -showdestinations -scheme GovaApp` and use an available iOS Simulator device name.

- [ ] **Step 6: Confirm the version key landed in the built Info.plist**

```bash
grep -n "CFBundleShortVersionString" ios/GovaApp/Info.plist 2>/dev/null || \
  echo "(xcodegen writes it into the generated project; confirm via project.yml instead)"
grep -n "CFBundleShortVersionString" ios/project.yml
```
Expected: `project.yml` shows `CFBundleShortVersionString: "1.0.0"`.

- [ ] **Step 7: Commit**

```bash
cd ..
git add ios/GovaApp/Lib/VersionGate.swift ios/GovaApp/Lib/UpdateRequiredView.swift \
        ios/GovaApp/GovaAppApp.swift ios/project.yml
git commit -m "feat: launch-time version gate (checks _version, fails open)"
```

---

## Task 5: CLAUDE.md + build.md reorientation

**Files:**
- Modify: `CLAUDE.md`
- Modify: `.claude/commands/build.md`

**Interfaces:**
- Consumes: everything above. Produces no code.

**Context:** The translation guide and build workflow currently say "one screen per JS module." With the manifest, screens derive from resources (models with a `list` endpoint). `CLAUDE.md` Step 3's model-typing is already manifest-aware from Build 2 — keep it.

- [ ] **Step 1: Reframe the screen-derivation language in CLAUDE.md**

In `CLAUDE.md`:
1. The line `- The list of screens (one per JS module in the web app)` → `- The list of screens (one per model with a \`list\` endpoint in the Generated Context)`.
2. The header `### Step 4 — Build screens (one per JS module in the web app)` → `### Step 4 — Build screens (one per model with a \`list\` endpoint)`.
3. The Web-to-iOS Pattern Mapping table header `| Web (JS module pattern) | iOS (SwiftUI equivalent) |` → `| Web app resource (from the manifest) | iOS (SwiftUI equivalent) |`. Leave the table rows unchanged — the SwiftUI equivalents are still correct.

- [ ] **Step 2: Add the version-gate infra note to CLAUDE.md**

In the "Infrastructure Files (Pre-committed — Do Not Regenerate)" section, add two entries alongside `APIClient.swift` and `AuthManager.swift`:

```markdown
**`VersionGate.swift`**
- Launch-time compatibility check. Calls `GET /api/v1/_version`, compares this
  build's `CFBundleShortVersionString` against the server's `min_client_version`.
- **Fails open** — any error or unreachable endpoint leaves the app usable; only a
  provably-too-old client is blocked.
- Wired in `GovaAppApp.swift`; shows `UpdateRequiredView` when the client is too old.

**`UpdateRequiredView.swift`**
- The blocking "Update Required" screen shown by `VersionGate`. Pre-committed;
  never regenerate.
```

- [ ] **Step 3: Reframe build.md**

In `.claude/commands/build.md`:
1. Step 3 (Brainstorm), the bullet `- The complete list of screens to generate (one per JS module in Generated Context)` → `- The complete list of screens to generate (one per model with a \`list\` endpoint in the Generated Context)`.
2. Step 4 (plan order), the item `4. One task per screen from SEED.md: ViewModel → View → \`xcodegen generate\`` → `4. One task per resource screen in the Generated Context: ViewModel → View → \`xcodegen generate\``.
Leave everything else (scaffold_mobile_auth note, Swift-generation mechanics, xcodebuild verification) unchanged.

- [ ] **Step 4: Verify no stale "JS module" screen framing remains**

```bash
grep -n "per JS module\|one per JS\|JS module pattern" CLAUDE.md .claude/commands/build.md
```
Expected: no output.

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md .claude/commands/build.md
git commit -m "docs: screens derive from manifest resources; document version gate"
```

---

## Task 6: End-to-end verification against the real monolith manifest

**Files:** none modified — run and observe.

**Interfaces:** consumes everything above.

**Context:** Prove the whole chain works against a real, populated `api.json` from the sibling `gova-monolith` checkout at `../gova-monolith`. The committed monolith `api.json` is the empty manifest, so this task generates a populated one into a temp file (without touching the monolith) and runs the export against it, then restores.

- [ ] **Step 1: Build a populated manifest fixture from real scaffold output**

The monolith's committed `../gova-monolith/src/app/api.json` is empty. Rather than scaffold into the monolith, copy it and inject a resource so the fixture mirrors real manifest shape:

```bash
cat > /tmp/e2e-api.json <<'EOF'
{"api_version":"1.0.0","hash":"sha256:e2e","generated_at":"2026-07-23T00:00:00Z",
 "models":[{"name":"project","table":"projects","fields":[
   {"name":"id","type":"int","nullable":false},
   {"name":"name","type":"string","nullable":false},
   {"name":"notes","type":"string","nullable":true},
   {"name":"created_at","type":"timestamp","nullable":false}]}],
 "endpoints":[
   {"method":"GET","path":"/api/v1/projects","handler":"ProjectListGET","deps":["read","write","cache"],"auth":false,"model":"project","kind":"list"},
   {"method":"POST","path":"/api/v1/auth/login_token","handler":"MobileLoginPOST","deps":["read","write","cache"],"auth":false,"kind":"mobile_login"}]}
EOF
```

- [ ] **Step 2: Run the export against a copy of the real SEED.md**

```bash
cp SEED.md /tmp/e2e-seed.md
python3 .claude/scripts/export_manifest.py /tmp/e2e-api.json /tmp/e2e-seed.md
echo "==== resulting Generated Context ===="
sed -n '/<!-- \/export:mobile WRITES BELOW THIS LINE -->/,$p' /tmp/e2e-seed.md
```
Expected — the summary line `models=1 endpoints=2 bearer_auth=yes`, and the block below the marker shows:
- `notes: string? → String?` (nullability from the manifest)
- `created_at: timestamp → Date`
- `**project**` with `- GET /api/v1/projects  [list]  auth:no`
- `- POST /api/v1/auth/login_token  [mobile_login]` under Auth endpoints
- `One list screen per model with a \`list\` endpoint: [project]` and `Login screen: yes`

- [ ] **Step 3: Confirm idempotency end-to-end**

```bash
cp /tmp/e2e-seed.md /tmp/e2e-seed-before.md
python3 .claude/scripts/export_manifest.py /tmp/e2e-api.json /tmp/e2e-seed.md
diff /tmp/e2e-seed-before.md /tmp/e2e-seed.md && echo "IDEMPOTENT: second run byte-identical"
```
Expected: no diff — `IDEMPOTENT: second run byte-identical`.

- [ ] **Step 4: Confirm the developer section of the real SEED.md is preservable**

```bash
head -c 200 /tmp/e2e-seed.md
```
Expected: the top of the file (`# iOS App Specification`, `## App Name`, …) is intact — the export only rewrites below the marker.

- [ ] **Step 5: Full unit suite + build, clean tree**

```bash
cd .claude/scripts && python3 -m unittest test_export_manifest -v && cd ../..
cd ios && xcodebuild -scheme GovaApp -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -3 && cd ..
git status --short
git log --oneline main..HEAD | wc -l
```
Expected: all python tests pass; `** BUILD SUCCEEDED **`; tree clean (the `/tmp` fixtures are outside the repo); the log shows the Build 3a commits.

---

## Verification Summary

| Concern | Where proven |
|---|---|
| Deterministic manifest → context transform | Task 1 (incl. order-independence) |
| Nullability & timestamp reach the context as facts | Task 1, Task 6 Step 2 |
| SEED.md developer section preserved; idempotent | Task 2, Task 6 Steps 3-4 |
| Export parses no source, needs no server/MCP | Task 3 Step 2 |
| Version gate fails open; semver correct | Task 4 Step 1 (documented cases) |
| App builds with the gate wired | Task 4 Step 5, Task 6 Step 5 |
| Screens derive from manifest resources in docs | Task 5 Step 4 |
| Whole chain works on real manifest shape | Task 6 |
