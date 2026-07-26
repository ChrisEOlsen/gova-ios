# Build B-consume — iOS reads the enriched contract

**Date:** 2026-07-25
**Repo:** gova-ios (consumer side). Emit side shipped in gova-monolith (Build B-emit).
**Status:** Approved in substance (design + forks), pending written-spec review.

## Why

Build B-emit made `api.json` carry the full contract: per-endpoint `request`/
`response` body schemas, `format` hints on string fields (`datetime-local`,
`date`, `time`, `json`, `email`), foreign-key `references`, and
`summary`+schemas on `kind:custom` endpoints. The iOS side does not yet read any
of it. Until it does, `/build` still: infers request bodies (four resources
shipped wrong in the field), renders semantic strings as raw text, flattens child
resources into meaningless top-level lists, and treats custom endpoints as a
black hole. This build teaches the deterministic export and the `/build` screen
rules to consume the new fields.

## Decisions (locked)

- **Child nesting:** a resource whose manifest fields include a `references`
  (foreign key) is a **child**. It gets **no top-level tab**; its list renders
  **inside the parent's detail screen**, filtered by the FK
  (`GET /api/v1/{child_plural}?filter={fk}:{parentId}` — supported by B-emit's
  list endpoint). Create/edit/delete for the child live in that nested list. A
  resource with no `references` is top-level.
- **Custom-endpoint UI:** generate an action from the request shape + summary. An
  empty/absent request → a button labeled from the summary. A request with fields
  → a form/sheet built from those fields (honoring their `format`). The action
  attaches to the **detail** screen when the path contains `{id}`, else to the
  **list** screen. The response schema drives what to do after (reload / show).
- **Format → control** is a fixed mapping (table below); the export surfaces each
  field's `format` and `/build` picks the control and write-format.
- **Determinism preserved:** the export stays a pure function of manifest content.
  All new sections sort deterministically; `test_export_manifest.py` gets cases
  for the new fields and a byte-stable golden.

## Format → SwiftUI control (CLAUDE.md rule)

| `format`         | control                                    | value written to API      |
|------------------|--------------------------------------------|---------------------------|
| `datetime-local` | `DatePicker(selection, .date & .hourAndMinute)` | `2026-07-27T11:45` (no seconds, no `Z`) |
| `date`           | `DatePicker(selection, .date)`             | `2026-07-27`              |
| `time`           | `DatePicker(selection, .hourAndMinute)`    | `11:45`                   |
| `email`          | `TextField().keyboardType(.emailAddress).textInputAutocapitalization(.never)` | string |
| `json`           | `TextEditor` (monospaced)                  | raw JSON string           |
| (none)           | `TextField` / `Toggle` / numeric field by `type` | as today            |

`datetime-local` is deliberately distinct from a `timestamp`/`Date` field
(RFC3339 via `models.Time`): the writer must NOT emit seconds or a `Z`, or the
web `datetime-local` input silently rejects the value.

## `export_manifest.py` changes

The script writes the `### Web App Context` block into `SEED.md`. Extend it:

1. **Models section** — for each field, append `format=<hint>` and
   `references=<parent>` when present (today it shows only type + nullability).
2. **Resources → endpoints** — under each endpoint, emit its `request` and
   `response` schema compactly: `request: object{title, remind_at:datetime-local, category_id->log_category}`,
   `response: object(reminder)` / `list(reminder)` / `object{ok}`.
3. **Relationships** (new section) — for each model with a `references` field,
   emit `` `<child>` is a child of `<parent>` via `<fk>` `` — the derived
   nesting map.
4. **Custom endpoints** (new section) — for each `kind:custom` endpoint:
   `METHOD path — <summary>` with its `request`/`response` schema, and a derived
   attach hint (`attach: detail` if the path has `{id}`, else `attach: list`).
5. **Screens to generate** (rewrite) —
   - **Top-level list screens:** models with a `list` endpoint **and no
     `references` field**.
   - **Nested child lists:** each model with a `references` field → "nested under
     `<parent>` detail, filtered by `<fk>`".
   - **Custom actions:** each custom endpoint → its attach target + control kind
     (button if no request fields, else form).

All new sections iterate models/endpoints in the script's existing sorted order —
no map iteration, no manifest-order dependence.

## `CLAUDE.md` changes (gova-ios)

- **Step 4 screen table** gains: a **child-resource** rule (nest under parent
  detail, filtered by FK — no top-level tab); a **format** rule (the mapping
  table above); a **custom-endpoint** rule (action from shape+summary, attached
  per the `{id}` heuristic).
- The **web→iOS mapping table** gains rows for the five formats, the `references`
  → nested-list mapping, and custom-endpoint → action.
- No `APIClient` change: custom `POST/PUT/DELETE/GET` reuse the existing
  `post/put/delete/get`. (The `kind` set introduces no `PATCH`.)

## `build.md` changes (gova-ios)

Steps that enumerate resources/screens now: build top-level screens only for
non-child resources; render each child as a nested filtered list on its parent's
detail; render custom actions; use the format mapping for form controls.

## Files touched

- `.claude/scripts/export_manifest.py` — new sections + per-field format/references.
- `.claude/scripts/test_export_manifest.py` — cases + golden for the new output.
- `CLAUDE.md` — screen table + mapping rows.
- `.claude/commands/build.md` — nested/custom/format drive.

## Non-goals

- No Swift written at template time — this is export output + `/build` rules only.
- No new `APIClient` method.
- **Registration endpoint** stays as-is (auth is hand-implemented in the
  pre-committed `AuthManager`; mobile registration, if wanted, is a manual
  addition). This matches B-emit leaving auth/register endpoints schema-less.
- No multi-parent nesting: a child with more than one `references` field nests
  under its **first** referenced parent; deeper graphs are out of scope.
- No offline/caching changes.

## Verification

- `python3 .claude/scripts/test_export_manifest.py` green, including new cases;
  running the export twice on the same manifest yields byte-identical SEED.md.
- Feed a synthetic enriched manifest (a parent, a child with a `ref` + a
  `datetime` field, and a custom `{id}` endpoint) through the export and confirm
  the SEED.md block shows: the child under Relationships, the custom endpoint with
  summary + attach hint, the datetime field's format, and the child excluded from
  top-level screens.
- Doc review: CLAUDE.md/build.md rules are internally consistent and reference
  only fields the manifest actually carries.
