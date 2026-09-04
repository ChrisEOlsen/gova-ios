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

step "Generating Xcode project"
cd "$IOS_DIR"
xcodegen generate
ok "GovaApp.xcodeproj generated in ios/"

echo ""
echo "=================================="
echo -e "${GREEN}${BOLD}Setup complete!${NC}"
echo ""
echo "  1. Open Claude Code in this directory: claude"
echo "  2. Run: /prep   (asks what it needs, fills SEED.md, runs the export)"
echo "  3. Start translating: /build"
echo ""
