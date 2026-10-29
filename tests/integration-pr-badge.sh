#!/usr/bin/env bash
# Verifies the PR badge at the end of Line 2: "#N state" for GitHub PRs,
# "!N state" for GitLab MRs (pr.kind == "mr"), number only when review_state
# is absent, and no badge at all when `pr` is absent. Runs both runners
# inside a temporary repo and requires their output to match byte-for-byte.
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

command -v git >/dev/null 2>&1 || { printf 'SKIP: git not installed\n'; exit 0; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
TMPHOME="$TMP/home"; mkdir -p "$TMPHOME"

REPO="$TMP/repo"
git init -q "$REPO"
git -C "$REPO" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init

strip_ansi() { sed $'s/\x1b\\[[0-9;]*m//g'; }

# run <runner> <json> <outfile> → writes raw output to <outfile>
run() {
    local runner="$1" json="$2" out="$3" cmd rcache
    case "$runner" in
        sh) cmd="$ROOT/statusline.sh" ;;
        js) cmd="node $ROOT/statusline.js" ;;
    esac
    rcache=$(mktemp -d)
    printf '%s\0' "$json" \
        | HOME="$TMPHOME" XDG_RUNTIME_DIR="$rcache" TMPDIR="$rcache" $cmd > "$out"
    rm -rf "$rcache"
}
line2() { strip_ansi < "$1" | sed -n 2p; }

fails=0
# check <label> <json> <expected-line2-suffix>
check() {
    local label="$1" json="$2" want="$3" l2_sh l2_js
    run sh "$json" "$TMP/out.sh"; l2_sh=$(line2 "$TMP/out.sh")
    run js "$json" "$TMP/out.js"; l2_js=$(line2 "$TMP/out.js")
    case "$l2_sh" in
        *"$want") printf 'PASS [sh] %s\n' "$label" ;;
        *) printf 'FAIL [sh] %s\n  want: *%s\n  got:  %s\n' "$label" "$want" "$l2_sh"; fails=$((fails + 1)) ;;
    esac
    case "$l2_js" in
        *"$want") printf 'PASS [js] %s\n' "$label" ;;
        *) printf 'FAIL [js] %s\n  want: *%s\n  got:  %s\n' "$label" "$want" "$l2_js"; fails=$((fails + 1)) ;;
    esac
    if ! cmp -s "$TMP/out.sh" "$TMP/out.js"; then
        printf 'FAIL [sh≠js] %s: runner outputs differ\n' "$label"; fails=$((fails + 1))
    fi
}

WS="{\"workspace\":{\"current_dir\":\"$REPO\"}"

check "github approved" \
    "$WS,\"pr\":{\"number\":12,\"url\":\"https://github.com/x/y/pull/12\",\"review_state\":\"approved\"}}" \
    "✓ clean  ·  #12 approved"

check "gitlab draft (kind=mr)" \
    "$WS,\"pr\":{\"number\":7,\"kind\":\"mr\",\"review_state\":\"draft\"}}" \
    "✓ clean  ·  !7 draft"

check "number only (no review_state)" \
    "$WS,\"pr\":{\"number\":3}}" \
    "✓ clean  ·  #3"

check "no pr field → no badge" \
    "$WS}" \
    "✓ clean"

[ "$fails" -eq 0 ] || exit 1
printf 'PASS: PR badge renders #N / !N with review state (sh == js)\n'
