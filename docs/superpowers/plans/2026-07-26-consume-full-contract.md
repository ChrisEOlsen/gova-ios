# iOS Consume Full-Contract (Build B-consume) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Teach gova-ios to consume the enriched `api.json` — emit request/response schemas, format hints, relationships, and custom-endpoint semantics into SEED.md, and give `/build` the screen rules to turn them into nested lists, format-aware forms, and custom actions.

**Architecture:** Extend the deterministic `export_manifest.py` (`render_context`) with new SEED.md sections derived purely from manifest content, and extend the `CLAUDE.md`/`build.md` generation rules that `/build` follows. No Swift is written at template time.

**Tech Stack:** Python 3 (stdlib only, `unittest`), Markdown. No Node, no build step. Tests: `python3 .claude/scripts/test_export_manifest.py`.

## Global Constraints

- **Determinism is non-negotiable.** `render_context` output must depend only on manifest *content*, never manifest *order*. All new sections iterate the already-sorted `models`/`endpoints` (models by name, endpoints by (path, method)) or a freshly-sorted derived list. The existing `test_deterministic_regardless_of_input_order` must still pass with the new sections.
- **Only reference fields the manifest actually carries:** `format`, `references` (on model fields and schema fields), `summary`, `request`, `response` (on endpoints). All are optional (`omitempty` on the emit side) — never assume presence; use `.get(...)`.
- **Child = a model with a `references` field.** It nests under its (first) referenced parent's detail, filtered by the FK; it gets no top-level tab. A model with no `references` is top-level.
- **Custom action attach heuristic:** `{id}` in the path → attach to detail; else → list. Empty/absent request fields → button; request with fields → form.
- **datetime-local writes without seconds or `Z`** (`2026-07-27T11:45`); it is distinct from a `timestamp`/`Date` field.
- **Registration stays schema-less** — no register UI rule (auth is pre-committed in `AuthManager`).
- **Stdlib only.** No new Python dependencies.

---

### Task 1: Extend `export_manifest.py` with schemas, relationships, and custom endpoints

**Files:**
- Modify: `.claude/scripts/export_manifest.py` — add `schema_str`/`_field_desc` helpers; annotate the Models and Resources sections; add Relationships and Custom-endpoints sections; rewrite Screens-to-generate.
- Modify: `.claude/scripts/test_export_manifest.py` — extend `SAMPLE` with a child + format + custom endpoint; add assertions; keep the determinism test green.

**Interfaces:**
- Consumes: the manifest dict (new optional keys `format`, `references` on fields; `summary`, `request`, `response` on endpoints; `request`/`response` are `{shape, model?, fields?}` or absent).
- Produces: `schema_str(schema) -> str`, `_field_desc(field) -> str`; an enriched `render_context(manifest) -> str`.

- [ ] **Step 1: Write failing tests** — extend `SAMPLE` and add assertions in `test_export_manifest.py`

Replace the `SAMPLE` dict's `models` and `endpoints` with enriched versions (a `log_category` parent, a `reminder` child with a `datetime` + a `ref`, and a custom snooze endpoint), and add a test class. Append this to the file (and update `SAMPLE` in place):

```python
# --- add to SAMPLE["models"] (a child with a ref + a formatted field) ---
# {"name": "log_category", "table": "log_categories", "fields": [
#     {"name": "id", "type": "int", "nullable": False},
#     {"name": "title", "type": "string", "nullable": False},
#     {"name": "created_at", "type": "timestamp", "nullable": False}]},
# {"name": "reminder", "table": "reminders", "fields": [
#     {"name": "id", "type": "int", "nullable": False},
#     {"name": "remind_at", "type": "string", "nullable": False, "format": "datetime-local"},
#     {"name": "category_id", "type": "int", "nullable": False, "references": "log_category"},
#     {"name": "created_at", "type": "timestamp", "nullable": False}]},
#
# --- add to SAMPLE["endpoints"] ---
# {"method": "GET", "path": "/api/v1/reminders", "handler": "ReminderListGET", "deps": ["read"], "auth": False, "model": "reminder", "kind": "list",
#  "response": {"shape": "list", "model": "reminder"}},
# {"method": "POST", "path": "/api/v1/reminders", "handler": "ReminderCreatePOST", "deps": ["read"], "auth": False, "model": "reminder", "kind": "create",
#  "request": {"shape": "object", "fields": [{"name": "remind_at", "type": "string", "nullable": False, "format": "datetime-local"}, {"name": "category_id", "type": "int", "nullable": False, "references": "log_category"}]},
#  "response": {"shape": "object", "model": "reminder"}},
# {"method": "POST", "path": "/api/v1/reminders/{id}/snooze", "handler": "ReminderSnoozePOST", "deps": ["read"], "auth": False, "kind": "custom",
#  "summary": "Snooze a reminder by N minutes", "request": {"shape": "object", "fields": [{"name": "minutes", "type": "int", "nullable": False}]}, "response": {"shape": "object", "model": "reminder"}},

class TestEnrichedContract(unittest.TestCase):
    def setUp(self):
        self.out = render_context(SAMPLE)

    def test_format_hint_shown_on_field(self):
        self.assertIn("[format: datetime-local]", self.out)

    def test_reference_shown_on_field(self):
        self.assertIn("[ref → log_category]", self.out)

    def test_endpoint_shows_request_and_response(self):
        self.assertIn("request: object{remind_at:datetime-local, category_id->log_category}", self.out)
        self.assertIn("response: object(reminder)", self.out)

    def test_relationships_section(self):
        self.assertIn("#### Relationships", self.out)
        self.assertIn("`reminder` is a child of `log_category` (via `category_id`)", self.out)

    def test_custom_endpoints_section(self):
        self.assertIn("#### Custom endpoints", self.out)
        self.assertIn("POST /api/v1/reminders/{id}/snooze — Snooze a reminder by N minutes", self.out)
        self.assertIn("attach: detail  control: form", self.out)

    def test_top_level_excludes_child(self):
        # reminder is a child (has a ref) so it is NOT a top-level screen; log_category and project are.
        self.assertIn("Top-level list screens (list endpoint, not a child): [log_category, order_item, project]", self.out)

    def test_nested_screen_listed(self):
        self.assertIn("Nested: `reminder` list under `log_category` detail, filtered by `category_id`", self.out)
```

Uncomment/inline the `SAMPLE` additions (move the parent/child models and the three endpoints into the actual `SAMPLE` literal — they are shown commented above only to keep this step readable).

- [ ] **Step 2: Run tests — verify the new ones fail**

Run: `cd .claude/scripts && python3 test_export_manifest.py`
Expected: the `TestEnrichedContract` cases FAIL (sections not emitted yet); existing tests still pass.

- [ ] **Step 3: Add the schema helpers** (top of `export_manifest.py`, after `pascal`)

```python
def _field_desc(f: dict) -> str:
    """Compact one-field descriptor for a schema: name plus its ref or format."""
    s = f["name"]
    if f.get("references"):
        s += f"->{f['references']}"
    elif f.get("format"):
        s += f":{f['format']}"
    return s


def schema_str(schema: dict) -> str:
    """Render a BodySchema compactly. 'object(reminder)' for a model-backed body,
    'object{a, b:datetime-local}' for an inline-fields body, 'none' when absent."""
    if not schema:
        return "none"
    shape = schema.get("shape", "")
    if schema.get("model"):
        return f"{shape}({schema['model']})"
    fields = schema.get("fields") or []
    return f"{shape}{{{', '.join(_field_desc(f) for f in fields)}}}"
```

- [ ] **Step 4: Annotate the Models section** (in `render_context`, the `#### Models` loop)

Change the per-field append so it shows format/references. Replace:

```python
        for f in m.get("fields", []):
            display = f["type"] + ("?" if f.get("nullable") else "")
            lines.append(f"  - {f['name']}: {display} → {swift_type(f['type'], f.get('nullable', False))}")
```

with:

```python
        for f in m.get("fields", []):
            display = f["type"] + ("?" if f.get("nullable") else "")
            extra = ""
            if f.get("format"):
                extra += f"  [format: {f['format']}]"
            if f.get("references"):
                extra += f"  [ref → {f['references']}]"
            lines.append(f"  - {f['name']}: {display} → {swift_type(f['type'], f.get('nullable', False))}{extra}")
```

- [ ] **Step 5: Show request/response under each resource endpoint** (in the `#### Resources → endpoints` loop)

After the existing `lines.append(f"  - {e['method']} {e['path']}  [{e.get('kind','')}]  auth:...")`, add:

```python
            if e.get("request"):
                lines.append(f"      request: {schema_str(e['request'])}")
            if e.get("response"):
                lines.append(f"      response: {schema_str(e['response'])}")
```

- [ ] **Step 6: Add Relationships and Custom-endpoints sections + rewrite Screens** (in `render_context`, replacing the current `#### Screens to generate` block)

First, just before the Screens block, derive the relationship and child data and add the two new sections:

```python
    # Relationships: any field with a `references` makes its model a child.
    rels = sorted(
        (m["name"], f["references"], f["name"])
        for m in models
        for f in m.get("fields", [])
        if f.get("references")
    )
    child_models = sorted({child for child, _parent, _fk in rels})

    lines.append("#### Relationships")
    if rels:
        for child, parent, fk in rels:
            lines.append(f"  - `{child}` is a child of `{parent}` (via `{fk}`) — nest its list under `{parent}` detail, filtered by `{fk}`")
    else:
        lines.append("  - (none)")
    lines.append("")

    custom = [e for e in endpoints if e.get("kind") == "custom"]
    lines.append("#### Custom endpoints")
    if custom:
        for e in custom:  # endpoints are already sorted by (path, method)
            attach = "detail" if "{id}" in e["path"] else "list"
            control = "form" if (e.get("request") and e["request"].get("fields")) else "button"
            lines.append(f"  - {e['method']} {e['path']} — {e.get('summary', '(no summary)')}")
            lines.append(f"      request: {schema_str(e.get('request'))}  response: {schema_str(e.get('response'))}")
            lines.append(f"      attach: {attach}  control: {control}")
    else:
        lines.append("  - (none)")
    lines.append("")
```

Then replace the existing Screens block:

```python
    lines.append("#### Screens to generate")
    lines.append(f"  - One list screen per model with a `list` endpoint: [{', '.join(list_models)}]")
    lines.append(f"  - Login screen: {'yes' if bearer_ready else 'no'}")
```

with:

```python
    top_level = [name for name in list_models if name not in child_models]
    lines.append("#### Screens to generate")
    lines.append(f"  - Top-level list screens (list endpoint, not a child): [{', '.join(top_level)}]")
    for child, parent, fk in rels:
        lines.append(f"  - Nested: `{child}` list under `{parent}` detail, filtered by `{fk}`")
    for e in custom:
        attach = "detail" if "{id}" in e["path"] else "list"
        lines.append(f"  - Custom action: {e['method']} {e['path']} on {attach}")
    lines.append(f"  - Login screen: {'yes' if bearer_ready else 'no'}")
```

(`list_models`, `models`, `endpoints`, `bearer_ready` are already defined earlier in `render_context`.)

- [ ] **Step 7: Run tests — verify all pass, including determinism**

Run: `cd .claude/scripts && python3 test_export_manifest.py`
Expected: all pass, including `test_deterministic_regardless_of_input_order` (the new sections must be order-independent) and `TestRenderContextEmpty` (empty manifest → `Relationships: (none)`, `Custom endpoints: (none)`, `Top-level list screens ... []`).

Note: `TestRenderContextEmpty` currently asserts the OLD screens line (`One list screen per model...`). Update that assertion to the new line: `self.assertIn("Top-level list screens (list endpoint, not a child): []", out)`.

- [ ] **Step 8: Commit**

```bash
git add .claude/scripts/export_manifest.py .claude/scripts/test_export_manifest.py
git commit -m "feat(export): emit schemas, relationships, formats, custom endpoints

render_context now surfaces per-field format/references, per-endpoint
request/response schemas, a Relationships section (child->parent via FK), a
Custom endpoints section (summary + attach/control hints), and a Screens block
that excludes child resources from top-level and lists nested + custom actions.
Deterministic; tests extended.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Teach `/build` the new screen rules (`CLAUDE.md` + `build.md`)

**Files:**
- Modify: `CLAUDE.md` — Step 4 screen table + the web→iOS mapping table.
- Modify: `.claude/commands/build.md` — the per-resource generation drive.

**Interfaces:**
- Consumes: the SEED.md sections Task 1 emits (Relationships, Custom endpoints, per-field format, Screens-to-generate).
- Produces: prose rules only — no code symbols.

- [ ] **Step 1: Add the format→control mapping to `CLAUDE.md`**

In `CLAUDE.md`, immediately after the Step 4 screen-kind table (the table ending in the `delete` row), insert a new subsection:

```markdown
**Field format → control.** When a model/request field carries a `format` (shown in the Generated Context as `[format: X]`), use the matching SwiftUI control and write-format — do not render it as a plain `TextField`:

| `format` | control | value sent to the API |
|---|---|---|
| `datetime-local` | `DatePicker(selection, displayedComponents: [.date, .hourAndMinute])` | `2026-07-27T11:45` — **no seconds, no `Z`** |
| `date` | `DatePicker(selection, displayedComponents: .date)` | `2026-07-27` |
| `time` | `DatePicker(selection, displayedComponents: .hourAndMinute)` | `11:45` |
| `email` | `TextField(...).keyboardType(.emailAddress).textInputAutocapitalization(.never)` | the string |
| `json` | `TextEditor` (monospaced) | the raw JSON string |

A `datetime-local` field is distinct from a `timestamp` (`Date`) field: a `Date` decodes/encodes as RFC3339 via the pre-committed decoder, but a `datetime-local` is a `String` written **without** seconds or a trailing `Z`, or the web editor rejects it.
```

- [ ] **Step 2: Add the child-nesting and custom-action rules to `CLAUDE.md`**

After the format subsection from Step 1, insert:

```markdown
**Child resources nest — no top-level tab.** The Generated Context's **Relationships** section lists each child (`` `child` is a child of `parent` via `fk` ``). A child resource does **not** get its own top-level list screen. Instead, render its list **inside the parent's detail screen**, loaded filtered by the foreign key: `GET /api/v1/{child_plural}?filter={fk}:{parentId}`. The child's create sheet (pre-filling `{fk}` = the parent id), swipe-delete, and edit form all live in that nested list. Only resources with **no** `references` field (the "Top-level list screens" line in Screens-to-generate) become tabs.

**Custom endpoints become actions.** The **Custom endpoints** section lists each `kind:custom` endpoint with its `summary`, `request`/`response` schema, and an `attach` + `control` hint. Generate:
- `control: button` (no request fields) → a button labeled from the summary that calls the endpoint and applies the response (reload the affected screen, or update the shown model from the response body).
- `control: form` (request has fields) → a `.sheet` with one control per request field (honoring each field's `format`), submitting the body and applying the response.
- `attach: detail` (path has `{id}`) → place the control on the resource's detail screen; `attach: list` → on the list screen's toolbar.
Use `APIClient.shared.{post|put|delete|get}` per the endpoint's method — never `URLSession`.
```

- [ ] **Step 2b: Extend the web→iOS mapping table in `CLAUDE.md`**

In the existing web→iOS mapping table (the one with `api.js get/post/put/del` rows), add these rows:

```markdown
| field `[format: datetime-local]` | `DatePicker([.date,.hourAndMinute])`; send `yyyy-MM-dd'T'HH:mm` (no seconds/Z) |
| field `[format: date]` / `[time]` | `DatePicker(.date)` / `DatePicker(.hourAndMinute)` |
| field `[format: email]` / `[json]` | `.keyboardType(.emailAddress)` / `TextEditor` |
| field `[ref → parent]` (foreign key) | resource nests under `parent` detail; load `?filter={fk}:{parentId}`, no top-level tab |
| `kind:custom` endpoint | an action (button/form per its `control`) on the `attach` screen; call via `APIClient.shared` |
```

- [ ] **Step 3: Drive nested/custom/format generation in `build.md`**

In `.claude/commands/build.md`, find the step that enumerates resources and generates a screen per resource. Update its guidance so it (a) builds top-level screens only for resources on the **Top-level list screens** line, (b) renders each **Relationships** child as a nested filtered list on its parent's detail, (c) renders each **Custom endpoints** entry as its action, and (d) uses the format→control mapping for all form fields. Add this paragraph to that step:

```markdown
Drive screen generation from the Generated Context, not from a flat model list:
- **Top-level screens:** one per name on the `Top-level list screens` line (child resources are intentionally absent).
- **Nested children:** for each `Nested:` line, add the child's list (create/edit/delete) inside the parent's detail view, loaded with `?filter={fk}:{parentId}`.
- **Custom actions:** for each `Custom action:` line, add the button/form (per its `control`) on the `attach` screen, wired through `APIClient.shared`.
- **Form controls:** for every create/edit form field, pick the control from the field's `[format: …]` per the CLAUDE.md format table; plain fields fall back to type-based controls.
Never generate an operation a resource's endpoint kinds don't expose.
```

- [ ] **Step 4: Consistency check (no test target here — docs)**

Re-read the three edits together. Confirm: the SEED.md section names referenced in CLAUDE.md/build.md (`Relationships`, `Custom endpoints`, `Top-level list screens`, `Nested:`, `Custom action:`, `[format: …]`, `[ref → …]`) **exactly match** the strings Task 1's `export_manifest.py` emits. Any mismatch is a bug — fix the doc to match the emitter (the emitter is the source of truth, already tested).

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md .claude/commands/build.md
git commit -m "docs: /build rules for nested children, custom actions, format controls

CLAUDE.md gains a format->control table, a child-nesting rule (nest under parent
detail, filtered by FK, no top-level tab), and a custom-endpoint->action rule;
build.md drives screen generation from the Generated Context sections. Section
names match the export emitter exactly.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: End-to-end verify against a synthetic enriched manifest

**Files:** none committed — runs the export on a synthetic manifest and inspects the SEED.md block, proving the pipeline emits what the docs promise.

**Interfaces:**
- Consumes: Tasks 1–2.
- Produces: evidence; a clean tree.

- [ ] **Step 1: Build a synthetic enriched manifest + a SEED with the marker**

Write a temp manifest and a temp SEED to the scratch dir (not committed):

```bash
mkdir -p /tmp/bconsume && cat > /tmp/bconsume/api.json <<'JSON'
{"api_version":"1.0.0","hash":"sha256:test","generated_at":"2026-07-26T00:00:00Z",
 "models":[
   {"name":"log_category","table":"log_categories","fields":[
     {"name":"id","type":"int","nullable":false},
     {"name":"title","type":"string","nullable":false},
     {"name":"created_at","type":"timestamp","nullable":false}]},
   {"name":"reminder","table":"reminders","fields":[
     {"name":"id","type":"int","nullable":false},
     {"name":"remind_at","type":"string","nullable":false,"format":"datetime-local"},
     {"name":"category_id","type":"int","nullable":false,"references":"log_category"},
     {"name":"created_at","type":"timestamp","nullable":false}]}],
 "endpoints":[
   {"method":"GET","path":"/api/v1/reminders","handler":"ReminderListGET","deps":["read"],"auth":false,"model":"reminder","kind":"list","response":{"shape":"list","model":"reminder"}},
   {"method":"POST","path":"/api/v1/reminders","handler":"ReminderCreatePOST","deps":["read"],"auth":false,"model":"reminder","kind":"create","request":{"shape":"object","fields":[{"name":"remind_at","type":"string","nullable":false,"format":"datetime-local"},{"name":"category_id","type":"int","nullable":false,"references":"log_category"}]},"response":{"shape":"object","model":"reminder"}},
   {"method":"POST","path":"/api/v1/reminders/{id}/snooze","handler":"ReminderSnoozePOST","deps":["read"],"auth":false,"kind":"custom","summary":"Snooze a reminder by N minutes","request":{"shape":"object","fields":[{"name":"minutes","type":"int","nullable":false}]},"response":{"shape":"object","model":"reminder"}}]}
JSON
printf '# iOS App Specification\n\n## Web App Path\n/tmp/bconsume\n\n<!-- /export:mobile WRITES BELOW THIS LINE -->\n' > /tmp/bconsume/SEED.md
```

- [ ] **Step 2: Run the export and inspect the block**

```bash
cd .claude/scripts && python3 export_manifest.py /tmp/bconsume/api.json /tmp/bconsume/SEED.md
sed -n '/### Web App Context/,$p' /tmp/bconsume/SEED.md
```

Confirm the emitted block shows:
- `reminder` model: `remind_at` with `[format: datetime-local]`; `category_id` with `[ref → log_category]`.
- `POST /api/v1/reminders`: `request: object{remind_at:datetime-local, category_id->log_category}` and `response: object(reminder)`.
- `#### Relationships`: `` `reminder` is a child of `log_category` (via `category_id`) ``.
- `#### Custom endpoints`: the snooze line with `attach: detail  control: form`.
- `#### Screens to generate`: `Top-level list screens (...): [log_category]` (reminder absent), a `Nested: reminder ...` line, and a `Custom action: POST .../snooze on detail` line.

- [ ] **Step 3: Prove determinism on the real file**

```bash
cd .claude/scripts && python3 -c "
import json, export_manifest as e
m = json.load(open('/tmp/bconsume/api.json'))
import copy; s = copy.deepcopy(m); s['models'].reverse(); s['endpoints'].reverse()
assert e.render_context(m) == e.render_context(s), 'NONDETERMINISTIC'
print('deterministic OK')
"
```

- [ ] **Step 4: Run the unit suite once more, clean up scratch**

```bash
cd .claude/scripts && python3 test_export_manifest.py
rm -rf /tmp/bconsume
cd - && git status --porcelain   # expect: clean (Tasks 1-2 already committed; nothing new)
```

- [ ] **Step 5: Record evidence** (no commit) — note the inspected block passed in the execution ledger.

---

## Self-Review

**1. Spec coverage:**
- Export emits schemas/formats/relationships/custom (spec §export_manifest.py) → T1. ✅
- Format→control mapping (spec table) → T2 Step 1 (CLAUDE.md). ✅
- Child nesting (spec decision) → T1 (Relationships + Screens) + T2 Step 2 (rule). ✅
- Custom-action generation (spec decision) → T1 (Custom section) + T2 Step 2 (rule). ✅
- build.md drive (spec §build.md) → T2 Step 3. ✅
- Determinism preserved (spec) → T1 Step 7 + T3 Step 3. ✅
- Register schema-less / multi-parent-first / no APIClient change (non-goals) → nothing added for them; T2 uses existing APIClient methods only. ✅

**2. Placeholder scan:** No TBD/TODO. Every code step shows complete code. The one "find the step that enumerates resources" instruction in T2 Step 3 is a locate-then-append with the exact paragraph to add. ✅

**3. Type consistency:** The emitted section strings (`#### Relationships`, `#### Custom endpoints`, `Top-level list screens (list endpoint, not a child):`, `Nested:`, `Custom action:`, `[format: …]`, `[ref → …]`, `request: object{…}`, `response: object(model)`) are used identically in T1 (emitter), the T1 tests, and the T2 doc references — and T2 Step 4 is an explicit cross-check against the emitter. `schema_str`/`_field_desc` signatures match between helper definition and call sites. ✅
