#!/usr/bin/env bash
# Pure-bash snapshot runner. Compares `node statusline.js` output against
# tests/expected/<name>.txt (plain mode, ANSI-stripped) or
# tests/expected-ansi/<name>.txt (ansi mode, ANSI preserved).
# Missing expected files are created (first-run snapshot).
# Exits non-zero on any diff.
#
# Usage:  ./tests/run.sh                       # plain mode
#         ./tests/run.sh --mode ansi           # compare ANSI-preserved snapshots
#         ./tests/run.sh --update              # regenerate plain snapshots
#         ./tests/run.sh --mode ansi --update  # regenerate ansi snapshots
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

UPDATE=0
MODE=plain
while [ $# -gt 0 ]; do
    case "$1" in
        --update) UPDATE=1 ;;
        --mode)
            shift
            case "${1:-}" in
                plain|ansi) MODE="$1" ;;
                *) printf 'error: --mode expects plain or ansi\n' >&2; exit 2 ;;
            esac
            ;;
        *) printf 'error: unknown argument: %s\n' "$1" >&2; exit 2 ;;
    esac
    shift
done

case "$MODE" in
    plain) EXPECTED_DIR="tests/expected" ;;
    ansi)  EXPECTED_DIR="tests/expected-ansi" ;;
esac
mkdir -p "$EXPECTED_DIR"

command -v node >/dev/null 2>&1 || { printf 'error: node not found\n' >&2; exit 1; }
cmd="node $ROOT/statusline.js"

maybe_strip_ansi() {
    if [ "$MODE" = "plain" ]; then
        sed $'s/\x1b\\[[0-9;]*m//g'
    else
        cat
    fi
}

TMPHOME=$(mktemp -d)
NOGIT=$(mktemp -d)
NOGIT_PARENT="$(dirname "$NOGIT")"
NOGIT_BASE="$(basename "$NOGIT")"
trap 'rm -rf "$TMPHOME" "$NOGIT"' EXIT

pass=0
fail=0
for fx in tests/fixtures/*.json; do
    name=$(basename "$fx" .json)
    expected="${EXPECTED_DIR}/${name}.txt"

    input=$(sed "s|__NOGIT__|${NOGIT}|g" "$fx")
    # Execute from NOGIT so fixtures without explicit CWD ('.') resolve
    # to a non-git dir — removing host repo state from the snapshot.
    # Fresh cache dir per fixture so Line 2 is never served from cache.
    rcache=$(mktemp -d)
    # NOGIT path normalization: in plain mode the full path stays
    # contiguous after ANSI stripping, so the first sed wins. In ansi
    # mode the dim prefix and bold basename are separated by SGR escapes,
    # so we fall back to per-segment substitution.
    actual=$(cd "$NOGIT" && printf '%s\0' "$input" \
        | HOME="$TMPHOME" XDG_RUNTIME_DIR="$rcache" TMPDIR="$rcache" COLUMNS=200 \
          $cmd \
        | maybe_strip_ansi \
        | sed -e "s|${NOGIT}|__NOGIT__|g" \
              -e "s|${NOGIT_PARENT}|__NOGIT_PARENT__|g" \
              -e "s|${NOGIT_BASE}|__NOGIT_BASE__|g")
    rm -rf "$rcache"

    if [ $UPDATE -eq 1 ] || [ ! -f "$expected" ]; then
        printf '%s' "$actual" > "$expected"
        printf 'SNAP %s\n' "$name"
        pass=$((pass + 1))
        continue
    fi

    if [ "$actual" = "$(cat "$expected")" ]; then
        printf 'PASS %s\n' "$name"
        pass=$((pass + 1))
    else
        printf 'FAIL %s\n' "$name"
        diff <(cat "$expected") <(printf '%s' "$actual") || true
        fail=$((fail + 1))
    fi
done

printf '\n%d pass, %d fail\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
