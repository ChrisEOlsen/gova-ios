# /export:mobile

Populate the SEED.md Generated Context from the linked gova-monolith web app's
machine-readable API manifest. Run this from the gova-ios directory.

This reads ONE file — the monolith's committed `src/app/api.json` (the manifest
Build 2 publishes) — and transforms it deterministically. It does not parse Go or
JS source, and requires no running server.

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
> scaffold at least one resource in gova-monolith with `./gova resource` — then
> run /export:mobile again."

If its `models` list holds only `user` and its endpoints only the auth set, warn
that the developer has not scaffolded any application resources yet, but continue.

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
