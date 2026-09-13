#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$SCRIPT_DIR/ios"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
warn() { echo -e "  ${YELLOW}!${NC} $1"; }
fail() { echo -e "  ${RED}✗${NC} $1"; exit 1; }
step() { echo -e "\n${BOLD}▶ $1${NC}"; }

echo ""
echo -e "${BOLD}GOVA iOS — Codex Setup${NC}"
echo "=================================="

step "Checking prerequisites"
command -v git        >/dev/null 2>&1 || fail "git not found"
command -v python3    >/dev/null 2>&1 || fail "python3 not found — used to edit Config.plist"
command -v xcodebuild >/dev/null 2>&1 || fail "xcodebuild not found — install Xcode command line tools: xcode-select --install"
command -v xcodegen   >/dev/null 2>&1 || fail "xcodegen not found — install with: brew install xcodegen"
command -v codex      >/dev/null 2>&1 || fail "codex not found — install it: npm i -g @openai/codex, or see https://developers.openai.com/codex/cli"
ok "git, python3, xcodebuild, xcodegen present"
ok "codex $(codex --version 2>/dev/null | tail -1) present"

step "Setting API base URL"
CONFIG_PLIST="$IOS_DIR/GovaApp/Config.plist"
CURRENT_URL=$(python3 - "$CONFIG_PLIST" <<'PYEOF'
import plistlib, sys, os
path = sys.argv[1]
if os.path.exists(path):
    with open(path, 'rb') as f:
        d = plistlib.load(f)
    print(d.get('API_BASE_URL', 'http://localhost:8080'))
else:
    print('http://localhost:8080')
PYEOF
)
printf "  API base URL [%s]: " "$CURRENT_URL"
read -r INPUT_URL </dev/tty
API_URL="${INPUT_URL:-$CURRENT_URL}"
python3 - "$CONFIG_PLIST" "$API_URL" <<'PYEOF'
import plistlib, sys
path, url = sys.argv[1], sys.argv[2]
with open(path, 'rb') as f:
    data = plistlib.load(f)
data['API_BASE_URL'] = url
with open(path, 'wb') as f:
    plistlib.dump(data, f)
PYEOF
ok "API_BASE_URL set to: $API_URL"

# ---------------------------------------------------------------------------
# Trust
#
# Codex loads a project's `.codex/` layer only for a project the user has
# trusted. Untrusted, `.codex/config.toml` is read past in silence. The TUI does
# ask on first run in an unknown directory, but a `codex exec` run does not, so
# write the entry here.
# ---------------------------------------------------------------------------

step "Trusting this project"

python3 - "$SCRIPT_DIR" <<'PYEOF'
import os, re, sys

project_dir = os.path.realpath(sys.argv[1])
config_path = os.path.expanduser("~/.codex/config.toml")
header = f'[projects."{project_dir}"]'

text = ""
if os.path.exists(config_path):
    with open(config_path) as f:
        text = f.read()

# Only ever append a section, or rewrite the one trust_level line inside our own
# section. This file is the user's global Codex config -- model, sandbox,
# keymap, every other project's trust -- and a naive rewrite would lose it.
pattern = re.compile(
    r"^" + re.escape(header) + r"\s*$.*?(?=^\[|\Z)",
    re.MULTILINE | re.DOTALL,
)
match = pattern.search(text)

if match is None:
    if text and not text.endswith("\n"):
        text += "\n"
    if text:
        text += "\n"
    text += f'{header}\ntrust_level = "trusted"\n'
    print(f"  + trusted {project_dir}")
elif 'trust_level = "trusted"' in match.group(0):
    print("  - project already trusted")
    sys.exit(0)
else:
    block = match.group(0)
    if re.search(r"^trust_level\s*=", block, re.MULTILINE):
        block = re.sub(
            r"^trust_level\s*=.*$", 'trust_level = "trusted"', block,
            count=1, flags=re.MULTILINE,
        )
    else:
        block = block.rstrip("\n") + '\ntrust_level = "trusted"\n\n'
    text = text[: match.start()] + block + text[match.end() :]
    print("  ~ trust_level set to trusted")

os.makedirs(os.path.dirname(config_path), exist_ok=True)
with open(config_path, "w") as f:
    f.write(text)
PYEOF

ok "~/.codex/config.toml updated"

step "Generating Xcode project"
(cd "$IOS_DIR" && xcodegen generate)
ok "GovaApp.xcodeproj generated in ios/"

step "Verifying Codex picks everything up"

python3 - "$SCRIPT_DIR" <<'PYEOF'
import json, subprocess, sys

project_dir = sys.argv[1]

try:
    raw = subprocess.run(
        ["codex", "debug", "prompt-input"],
        capture_output=True, text=True, timeout=180, cwd=project_dir,
    ).stdout
    text = "".join(
        content.get("text", "")
        for item in json.loads(raw)
        for content in item.get("content", [])
    )
except Exception as e:  # noqa: BLE001 - advisory, never fatal
    print(f"  ! could not read the session prompt ({e}) — check manually with: codex debug prompt-input")
    sys.exit(0)

expected = [
    "gova-brainstorm", "gova-writing-plans", "gova-build-execution",
    "gova-build", "gova-prep", "gova-export-mobile",
]
found = [s for s in expected if f"- {s}:" in text]
print(f"  skills:   {', '.join(found) or 'none'}")
missing = [s for s in expected if s not in found]
if missing:
    print(f"  ! missing skills: {', '.join(missing)} — check the .agents/skills symlinks")

if "AGENTS.md instructions" in text:
    print("  context:  AGENTS.md loaded")
else:
    print("  ! AGENTS.md was not loaded — check that the symlink to CLAUDE.md resolves")
PYEOF

ok "Codex configuration verified"

echo ""
echo "=================================="
echo -e "${GREEN}${BOLD}Setup complete!${NC}"
echo ""
echo "  1. Open Codex in this directory: codex"
echo "  2. Use the gova-prep skill   (asks what it needs, fills SEED.md, runs the export)"
echo "  3. Start translating:        use the gova-build skill"
echo ""
echo "  Skills: gova-prep, gova-export-mobile, gova-build — pick one with"
echo "          /skills, or name it: \"use gova-build\""
echo "  Context: AGENTS.md (a symlink to CLAUDE.md — one file, both harnesses)"
echo ""
echo "  Using Claude Code too? Run ./install-claude.sh — it shares this"
echo "  Config.plist, this Xcode project, and the same workflow files."
echo ""
