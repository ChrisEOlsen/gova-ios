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
    """Map a manifest type onto a Swift one.

    An unrecognised type is an error, never a silent `String` — see
    docs/API-CONTRACT.md, "An unrecognised type is an error at scaffold time".
    A String stand-in would decode as a type mismatch at runtime instead.
    """
    if field_type not in _SWIFT_TYPES:
        raise ValueError(
            f"unknown manifest type {field_type!r} "
            f"(known: {', '.join(sorted(_SWIFT_TYPES))})"
        )
    base = _SWIFT_TYPES[field_type]
    return base + "?" if nullable else base


def pascal(name: str) -> str:
    return "".join(part[:1].upper() + part[1:] for part in name.split("_") if part)


def _field_desc(f: dict) -> str:
    """Compact one-field descriptor for a schema: name plus its ref, scope or
    format.

    A scope is called out even inside a request body, because that is exactly
    where it misleads: the column appears in the body the manifest declares, and
    the server overwrites it from the session anyway. A form field for it lets
    somebody type a value that is then discarded.
    """
    s = f["name"]
    if f.get("references"):
        s += f"->{f['references']}"
    elif f.get("scope"):
        s += f"[scope:{f['scope']}, server set]"
    elif f.get("format"):
        s += f":{f['format']}"
    return s


def schema_str(schema: dict) -> str:
    """Render a BodySchema compactly. 'object(reminder)' for a model-backed body,
    'object{a, b:datetime-local}' for an inline-fields body, 'none' when absent."""
    if not schema:
        return "none"
    shape = schema.get("shape", "")
    if shape == "empty":
        return "empty"
    if schema.get("model"):
        return f"{shape}({schema['model']})"
    fields = schema.get("fields") or []
    return f"{shape}{{{', '.join(_field_desc(f) for f in fields)}}}"


def _control_for(endpoint: dict) -> str:
    """A custom endpoint with a request body is a form; without one, a button.

    A body is model-backed (`{"shape":"object","model":"x"}`) as often as it is
    inline, and testing only for `fields` renders a button that can never fill
    its required body.
    """
    request = endpoint.get("request") or {}
    if request.get("shape") == "empty":
        return "button"
    if request.get("fields") or request.get("model"):
        return "form"
    return "button"


# The manifest's inline schemas for the auth endpoints are abbreviated — the
# committed api.json lists login_token's response as `{token}` while the handler
# and docs/API-CONTRACT.md both return `{token, user}`. The contract wins, so the
# shapes a client binds are stated here rather than read off the manifest.
_AUTH_NOTES = {
    "mobile_login": [
        "  - `POST /api/v1/auth/login_token` — request `{email, password}`,",
        "    response `{token, user:{id, name, email}}`. Decode it with `LoginResponse`",
        "    from `Lib/AuthManager.swift`, then call `AuthManager.shared.login(token:user:)`.",
        "    (The manifest's inline schema omits `user`; the contract is authoritative.)",
    ],
    "mobile_me": [
        "  - `GET /api/v1/auth/me_token` — response `{id, name, email}`.",
        "    `AuthManager.restoreSession()` already calls this at launch; do not re-do it.",
    ],
    "mobile_logout": [
        "  - `DELETE /api/v1/auth/logout_token` — discard the payload",
        "    (`try await APIClient.shared.delete(path:)`), then `AuthManager.shared.logout()`.",
    ],
    "register": [
        "  - `POST /api/v1/auth/register` — **returns no bearer token.** It creates the",
        "    account and sets a browser session cookie, which a native client cannot use.",
        "    A registration screen must follow a successful register with `login_token`",
        "    using the same credentials, or skip registration entirely.",
    ],
}

_COOKIE_KINDS = ("auth_login", "auth_logout", "auth_logout_all", "auth_me")


def _auth_notes(kinds: set) -> list:
    lines = ["Bearer auth — the shapes to bind (docs/API-CONTRACT.md § Authentication):"]
    for kind, note in _AUTH_NOTES.items():
        if kind in kinds:
            lines.extend(note)
    if kinds & set(_COOKIE_KINDS):
        lines.append("  - `login`, `logout`, `logout_all` and `me` are the browser's cookie")
        lines.append("    endpoints — build no screen for them. `logout_all` does revoke this")
        lines.append("    device's bearer token, so a 401 afterwards is expected.")
    lines.append("  - `auth: true` on a resource endpoint means the server requires the")
    lines.append("    credential; `APIClient` attaches it to every request either way.")
    lines.append("")
    return lines


def render_context(manifest: dict) -> str:
    models = sorted(manifest.get("models") or [], key=lambda m: m["name"])
    endpoints = sorted(
        manifest.get("endpoints") or [],
        key=lambda e: (e["path"], e["method"]),
    )
    api_version = manifest.get("api_version", "")

    list_models = sorted(
        {e["model"] for e in endpoints if e.get("kind") == "list" and e.get("model")}
    )

    lines = []
    lines.append("### Web App Context")
    lines.append("Generated by /export:mobile from the web app's api.json.")
    lines.append("")
    lines.append("#### API")
    lines.append(f"- api_version: {api_version}")
    lines.append("- Lists are paginated: `?limit=` (1-200, default 50) and `?offset=`.")
    lines.append("  A list that can exceed 50 rows uses `APIClient.shared.getPage`, keeps")
    lines.append("  `meta`, and appends the next window while `page.hasMore`.")
    lines.append("- Lists also accept `?sort=<[-]col>` and `?filter=<col>:<value>`.")
    lines.append("")

    lines.append("#### Models")
    for m in models:
        lines.append(f"**{pascal(m['name'])}**  (table: {m['table']})")
        for f in m.get("fields", []):
            display = f["type"] + ("?" if f.get("nullable") else "")
            extra = ""
            if f.get("format"):
                extra += f"  [format: {f['format']}]"
            if f.get("references"):
                extra += f"  [ref → {f['references']}]"
            if f.get("scope"):
                extra += f"  [scope → {f['scope']}, server set]"
            try:
                st = swift_type(f["type"], f.get("nullable", False))
            except ValueError as exc:
                raise ValueError(f"model {m['name']}, field {f['name']}: {exc}") from None
            lines.append(f"  - {f['name']}: {display} → {st}{extra}")
        lines.append("")

    lines.append("#### Resources → endpoints")
    if not any(e.get("model") for e in endpoints):
        lines.append("  - (none — no application resource has been scaffolded yet)")
        lines.append("")
    for m in models:
        m_eps = [e for e in endpoints if e.get("model") == m["name"]]
        if not m_eps:
            continue
        lines.append(f"**{m['name']}**")
        for e in m_eps:
            lines.append(f"  - {e['method']} {e['path']}  [{e.get('kind', '')}]  auth:{'yes' if e.get('auth') else 'no'}")
            if e.get("request"):
                lines.append(f"      request: {schema_str(e['request'])}")
            if e.get("response"):
                lines.append(f"      response: {schema_str(e['response'])}")
        lines.append("")

    lines.append("#### Auth endpoints")
    kinds = set()
    for e in endpoints:
        if not e.get("model") and e.get("kind") != "custom":
            lines.append(f"  - {e['method']} {e['path']}  [{e.get('kind', '')}]")
            kinds.add(e.get("kind"))
    lines.append("")
    lines.extend(_auth_notes(kinds))

    # Relationships: any field with a `references` makes its model a child. Being
    # a child decides where a list may ALSO appear — never whether the model
    # deserves a screen of its own. See "Screens to generate" below.
    rels = sorted(
        (m["name"], f["references"], f["name"])
        for m in models
        for f in m.get("fields", [])
        if f.get("references")
    )
    # A scope column is not a relationship. It names whose rows these are, the
    # server sets it, and nesting on it produces a screen under a parent that
    # often has no screen at all.
    scopes = sorted(
        (m["name"], f["scope"], f["name"])
        for m in models
        for f in m.get("fields", [])
        if f.get("scope")
    )

    lines.append("#### Relationships")
    for model, target, col in scopes:
        lines.append(f"  - `{model}.{col}` scopes rows to `{target}` — the server sets it from the session. Never nest on it, and never put it in a create or update form: a value typed there is discarded.")
    if rels:
        for child, parent, fk in rels:
            lines.append(f"  - `{child}` is a child of `{parent}` (via `{fk}`) — its list may ALSO render inside `{parent}` detail, filtered by `{fk}`. It still gets its own top-level screen.")
    elif not scopes:
        lines.append("  - (none)")
    lines.append("")

    custom = [e for e in endpoints if e.get("kind") == "custom"]
    lines.append("#### Custom endpoints")
    if custom:
        for e in custom:  # endpoints are already sorted by (path, method)
            attach = "detail" if "{id}" in e["path"] else "list"
            control = _control_for(e)
            lines.append(f"  - {e['method']} {e['path']} — {e.get('summary', '(no summary)')}")
            lines.append(f"      request: {schema_str(e.get('request'))}  response: {schema_str(e.get('response'))}")
            lines.append(f"      attach: {attach}  control: {control}")
    else:
        lines.append("  - (none)")
    lines.append("")

    # Every model with a list endpoint gets a screen. Being somebody's child is
    # not a reason to hide one: a set log references the lift it was performed
    # on, and it is still the app. Suppressing children left one real app with a
    # lookup table as its only tab, its actual screens buried two taps down.
    top_level = list(list_models)
    lines.append("#### Screens to generate")
    lines.append(f"  - Top-level list screens (every model with a list endpoint): [{', '.join(top_level)}]")
    for child, parent, fk in rels:
        lines.append(f"  - Optionally also nested: `{child}` list inside `{parent}` detail, filtered by `{fk}`")
    for e in custom:
        attach = "detail" if "{id}" in e["path"] else "list"
        lines.append(f"  - Custom action: {e['method']} {e['path']} on {attach}")
    lines.append("  - Login screen: yes (bearer auth ships with the web app)")

    return "\n".join(lines)


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

    try:
        block = render_context(manifest)
    except (ValueError, KeyError) as exc:
        print(f"api.json cannot be translated: {exc}", file=sys.stderr)
        return 1

    with open(seed_path) as fh:
        seed = fh.read()
    with open(seed_path, "w") as fh:
        fh.write(splice_seed(seed, block))

    n_models = len(manifest.get("models") or [])
    n_endpoints = len(manifest.get("endpoints") or [])
    print(f"models={n_models} endpoints={n_endpoints}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
