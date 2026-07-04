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
echo -e "${BOLD}GOVA iOS — Claude Code Setup${NC}"
echo "=================================="

step "Checking prerequisites"
command -v git        >/dev/null 2>&1 || fail "git not found"
command -v xcodebuild >/dev/null 2>&1 || fail "xcodebuild not found — install Xcode command line tools: xcode-select --install"
command -v xcodegen   >/dev/null 2>&1 || fail "xcodegen not found — install with: brew install xcodegen"
ok "git, xcodebuild, xcodegen present"

step "Registering superpowers plugin"
python3 - <<'PYEOF'
import json, os
settings_path = os.path.expanduser("~/.claude/settings.json")
try:
    with open(settings_path) as f:
        settings = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    settings = {}
settings.setdefault("enabledPlugins", {})
if "superpowers@claude-plugins-official" not in settings["enabledPlugins"]:
    settings["enabledPlugins"]["superpowers@claude-plugins-official"] = True
    print("  + superpowers@claude-plugins-official added")
else:
    print("  - superpowers already registered")
with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")
PYEOF
ok "~/.claude/settings.json updated"

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

step "Configuring gova-builder MCP (optional)"
printf "  gova-monolith container name (press Enter to skip): "
read -r CONTAINER_NAME </dev/tty
if [ -n "$CONTAINER_NAME" ]; then
    python3 - "$SCRIPT_DIR" "$CONTAINER_NAME" <<'PYEOF'
import json, sys, os
project_dir, container = sys.argv[1], sys.argv[2]
config = {
    "mcpServers": {
        "gova-builder": {
            "command": "docker",
            "args": ["exec", "-i", container, "/usr/local/bin/mcp-server"]
        }
    }
}
with open(os.path.join(project_dir, ".mcp.json"), "w") as f:
    json.dump(config, f, indent=2)
    f.write("\n")
print(f"  + .mcp.json → gova-builder via {container}")
PYEOF
    ok "gova-builder MCP configured"
else
    warn "MCP skipped — scaffold_mobile_auth will not be available"
    warn "Re-run install-claude.sh and enter a container name to enable it"
fi

step "Generating Xcode project"
cd "$IOS_DIR"
xcodegen generate
ok "GovaApp.xcodeproj generated in ios/"

echo ""
echo "=================================="
echo -e "${GREEN}${BOLD}Setup complete!${NC}"
echo ""
echo "  1. Fill in 'Web App Path' in SEED.md, then run: /export:mobile"
echo "  2. Paste mobile-seed-context.md into SEED.md (Generated Context section)"
echo "  3. Open Claude Code in this directory: claude"
echo "  4. Verify MCP tools: /mcp"
echo "  5. Start translating: /build"
echo ""
