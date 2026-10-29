#!/usr/bin/env bash
# Verifies the @ tenancy segment on Line 3. When ~/.claude.json carries the
# newer oauthAccount.organizationType field, team vs personal is decided from
# it (seatTier string or team/enterprise in the type → team, else personal) and
# organizationName is not consulted. Files without that field fall back to the
# legacy "'s Organization" name pattern. Both runners must agree byte-for-byte.
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
NOGIT="$TMP/nogit"; mkdir -p "$NOGIT"
FIXTURE="tests/fixtures/01-default.json"

strip_ansi() { sed $'s/\x1b\\[[0-9;]*m//g'; }

# run <runner> <home> <outfile>
run() {
    local runner="$1" home="$2" out="$3" cmd rcache
    case "$runner" in
        sh) cmd="$ROOT/statusline.sh" ;;
        js) cmd="node $ROOT/statusline.js" ;;
    esac
    rcache=$(mktemp -d)
    sed "s|__NOGIT__|$NOGIT|g" "$FIXTURE" | tr -d '\n' | { printf '%s\0' "$(cat)"; } \
        | HOME="$home" XDG_RUNTIME_DIR="$rcache" TMPDIR="$rcache" COLUMNS=200 $cmd > "$out"
    rm -rf "$rcache"
}
line3() { strip_ansi < "$1" | sed -n 3p; }

fails=0
# check <label> <oauthAccount-json> <expected-line3-suffix>
check() {
    local label="$1" account="$2" want="$3" home l3_sh l3_js
    home=$(mktemp -d)
    printf '{"oauthAccount":%s}\n' "$account" > "$home/.claude.json"
    run sh "$home" "$TMP/out.sh"; l3_sh=$(line3 "$TMP/out.sh")
    run js "$home" "$TMP/out.js"; l3_js=$(line3 "$TMP/out.js")
    rm -rf "$home"
    case "$l3_sh" in
        *"$want") printf 'PASS [sh] %s\n' "$label" ;;
        *) printf 'FAIL [sh] %s\n  want: *%s\n  got:  %s\n' "$label" "$want" "$l3_sh"; fails=$((fails + 1)) ;;
    esac
    case "$l3_js" in
        *"$want") printf 'PASS [js] %s\n' "$label" ;;
        *) printf 'FAIL [js] %s\n  want: *%s\n  got:  %s\n' "$label" "$want" "$l3_js"; fails=$((fails + 1)) ;;
    esac
    if ! cmp -s "$TMP/out.sh" "$TMP/out.js"; then
        printf 'FAIL [sh≠js] %s: runner outputs differ\n' "$label"; fails=$((fails + 1))
    fi
}

ID='"displayName":"Jane","emailAddress":"jane@x.io"'

check "A team seat, custom org name" \
    "{$ID,\"organizationName\":\"Acme\",\"organizationType\":\"claude_team\",\"seatTier\":\"team_standard\"}" \
    "  ·  @ Jane (Acme)"

check "B personal max, renamed org → personal" \
    "{$ID,\"organizationName\":\"Jane Lab\",\"organizationType\":\"claude_max\",\"seatTier\":null}" \
    "  ·  @ Jane"

check "C enterprise, auto-style org name → team" \
    "{$ID,\"organizationName\":\"Jane's Organization\",\"organizationType\":\"claude_enterprise\",\"seatTier\":null}" \
    "  ·  @ Jane (Jane's Organization)"

check "D legacy file, custom org name → team" \
    "{$ID,\"organizationName\":\"Acme\"}" \
    "  ·  @ Jane (Acme)"

check "E legacy file, auto-style org name → personal" \
    "{$ID,\"organizationName\":\"Jane's Individual Organization\"}" \
    "  ·  @ Jane"

[ "$fails" -eq 0 ] || exit 1
printf 'PASS: tenancy uses organizationType/seatTier when present, name pattern otherwise (sh == js)\n'
