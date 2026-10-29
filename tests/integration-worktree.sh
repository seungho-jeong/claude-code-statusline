#!/usr/bin/env bash
# Verifies the ⌥ worktree segment on Line 2: names longer than 24 chars are
# cut to 22 chars + "…", names up to 24 chars are left intact, and the git-dir
# fallback (no workspace.git_worktree field) follows the same rule. Runs both
# runners inside a temporary repo + linked worktree and requires their output
# to match byte-for-byte.
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

command -v git >/dev/null 2>&1 || { printf 'SKIP: git not installed\n'; exit 0; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
TMPHOME="$TMP/home"; mkdir -p "$TMPHOME"

LONG="84994-8f92caf2-8d17-43de-9895-44f94923334d"   # 43 chars
EDGE="abcdefghij0123456789wxyz"                     # 24 chars (boundary)

# Temp repo with one commit, plus a linked worktree whose directory name is LONG.
REPO="$TMP/repo"
git init -q "$REPO"
git -C "$REPO" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "$REPO" worktree add -q "$TMP/$LONG" -b wt-branch

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
# check <label> <json> <expected-line2-prefix>
check() {
    local label="$1" json="$2" want="$3" l2_sh l2_js
    run sh "$json" "$TMP/out.sh"; l2_sh=$(line2 "$TMP/out.sh")
    run js "$json" "$TMP/out.js"; l2_js=$(line2 "$TMP/out.js")
    case "$l2_sh" in
        "$want"*) printf 'PASS [sh] %s\n' "$label" ;;
        *) printf 'FAIL [sh] %s\n  want: %s*\n  got:  %s\n' "$label" "$want" "$l2_sh"; fails=$((fails + 1)) ;;
    esac
    case "$l2_js" in
        "$want"*) printf 'PASS [js] %s\n' "$label" ;;
        *) printf 'FAIL [js] %s\n  want: %s*\n  got:  %s\n' "$label" "$want" "$l2_js"; fails=$((fails + 1)) ;;
    esac
    if ! cmp -s "$TMP/out.sh" "$TMP/out.js"; then
        printf 'FAIL [sh≠js] %s: runner outputs differ\n' "$label"; fails=$((fails + 1))
    fi
}

check "long name (CC field)" \
    "{\"workspace\":{\"current_dir\":\"$REPO\",\"git_worktree\":\"$LONG\"}}" \
    "⌥ wt:84994-8f92caf2-8d17-43…"

check "24-char name untouched" \
    "{\"workspace\":{\"current_dir\":\"$REPO\",\"git_worktree\":\"$EDGE\"}}" \
    "⌥ wt:$EDGE  "

check "fallback (git-dir, no field)" \
    "{\"workspace\":{\"current_dir\":\"$TMP/$LONG\"}}" \
    "⌥ wt:84994-8f92caf2-8d17-43…"

[ "$fails" -eq 0 ] || exit 1
printf 'PASS: worktree names are truncated to 22 chars + … (sh == js)\n'
