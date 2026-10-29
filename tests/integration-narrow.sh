#!/usr/bin/env bash
# Verifies bar width follows the terminal: with no CCSL_BAR_WIDTH set, bars
# are 5 cells when COLUMNS < 100 and 10 cells otherwise; an explicit
# CCSL_BAR_WIDTH always wins. Both runners must agree byte-for-byte.
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
TMPHOME="$TMP/home"; mkdir -p "$TMPHOME"
NOGIT="$TMP/nogit"; mkdir -p "$NOGIT"

FIXTURE="tests/fixtures/02-rate-limits.json"   # 5h 22%, Week 12%, ctx 34%

strip_ansi() { sed $'s/\x1b\\[[0-9;]*m//g'; }

# run <runner> <outfile> <env...> → writes raw output to <outfile>
run() {
    local runner="$1" out="$2"; shift 2
    local cmd rcache
    case "$runner" in
        sh) cmd="$ROOT/statusline.sh" ;;
        js) cmd="node $ROOT/statusline.js" ;;
    esac
    rcache=$(mktemp -d)
    sed "s|__NOGIT__|$NOGIT|g" "$FIXTURE" | tr -d '\n' | { printf '%s\0' "$(cat)"; } \
        | env -u CCSL_BAR_WIDTH -u COLUMNS "$@" \
              HOME="$TMPHOME" XDG_RUNTIME_DIR="$rcache" TMPDIR="$rcache" $cmd > "$out"
    rm -rf "$rcache"
}
line4() { strip_ansi < "$1" | sed -n 4p; }

fails=0
# check <label> <expected-5h-bar-substring> <env...>
check() {
    local label="$1" want="$2"; shift 2
    local l4_sh l4_js
    run sh "$TMP/out.sh" "$@"; l4_sh=$(line4 "$TMP/out.sh")
    run js "$TMP/out.js" "$@"; l4_js=$(line4 "$TMP/out.js")
    case "$l4_sh" in
        *"$want"*) printf 'PASS [sh] %s\n' "$label" ;;
        *) printf 'FAIL [sh] %s\n  want: *%s*\n  got:  %s\n' "$label" "$want" "$l4_sh"; fails=$((fails + 1)) ;;
    esac
    case "$l4_js" in
        *"$want"*) printf 'PASS [js] %s\n' "$label" ;;
        *) printf 'FAIL [js] %s\n  want: *%s*\n  got:  %s\n' "$label" "$want" "$l4_js"; fails=$((fails + 1)) ;;
    esac
    if ! cmp -s "$TMP/out.sh" "$TMP/out.js"; then
        printf 'FAIL [sh≠js] %s: runner outputs differ\n' "$label"; fails=$((fails + 1))
    fi
}

check "narrow (COLUMNS=80) → 5 cells"            "5h ▰▱▱▱▱ "       COLUMNS=80
check "wide (COLUMNS=200) → 10 cells"            "5h ▰▰▱▱▱▱▱▱▱▱ "  COLUMNS=200
check "explicit CCSL_BAR_WIDTH=8 wins over narrow" "5h ▰▱▱▱▱▱▱▱ "   COLUMNS=80 CCSL_BAR_WIDTH=8

[ "$fails" -eq 0 ] || exit 1
printf 'PASS: bar width adapts to COLUMNS unless CCSL_BAR_WIDTH is set (sh == js)\n'
