#!/usr/bin/env bash
# Verifies install.sh writes the expected statusLine entry into settings.json.
# Runs against a temporary HOME with --source so no network round-trip is
# required. Covers both the fresh-file path and the jq merge path.
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

command -v jq >/dev/null 2>&1 || { printf 'SKIP: jq not installed\n'; exit 0; }

fails=0
check() {
    local label="$1" settings="$2"
    if ! jq -e '.statusLine | has("hideVimModeIndicator") | not' "$settings" >/dev/null 2>&1; then
        printf 'FAIL [%s]: statusLine.hideVimModeIndicator must not be set\n' "$label" >&2
        fails=$((fails + 1))
    fi
    if ! jq -e '.statusLine.command | strings | length > 0' "$settings" >/dev/null 2>&1; then
        printf 'FAIL [%s]: statusLine.command missing\n' "$label" >&2
        fails=$((fails + 1))
    fi
    if ! jq -e '.statusLine.refreshInterval == 30' "$settings" >/dev/null 2>&1; then
        printf 'FAIL [%s]: statusLine.refreshInterval is not 30\n' "$label" >&2
        fails=$((fails + 1))
    fi
}

# Case 1: no settings.json → installer creates it.
TMPHOME1=$(mktemp -d)
HOME="$TMPHOME1" "$ROOT/install.sh" --source "$ROOT/statusline.js" >/dev/null 2>&1
check "fresh" "$TMPHOME1/.claude/settings.json"

# Case 2: settings.json with unrelated keys → jq merge must keep them.
TMPHOME2=$(mktemp -d)
mkdir -p "$TMPHOME2/.claude"
printf '{"model":"opus","statusLine":{"type":"command","command":"old"}}\n' > "$TMPHOME2/.claude/settings.json"
HOME="$TMPHOME2" "$ROOT/install.sh" --source "$ROOT/statusline.js" >/dev/null 2>&1
check "merge" "$TMPHOME2/.claude/settings.json"
if ! jq -e '.model == "opus"' "$TMPHOME2/.claude/settings.json" >/dev/null 2>&1; then
    printf 'FAIL [merge]: unrelated key "model" was lost\n' >&2
    fails=$((fails + 1))
fi

rm -rf "$TMPHOME1" "$TMPHOME2"
if [ "$fails" -ne 0 ]; then
    exit 1
fi
printf 'PASS: install.sh writes statusLine with refreshInterval (fresh + merge)\n'
