#!/usr/bin/env node
// SPDX-License-Identifier: MIT
// ============================================================================
// Claude Code Statusline — 4-line axis-separated layout (Node port)
// ============================================================================
//
// Cross-platform (Win/Linux/macOS) port of statusline.sh. Runtime: Node ≥18.
// Zero npm deps: only built-ins (fs, os, path, child_process).
//
// Layout:
//   Line 1: Filesystem  — cwd (dim prefix + bold basename)
//   Line 2: Git         — ⌥ worktree(conditional) · ⎇ branch · ✓/± status
//   Line 3: AI          — ✦ model · context bar pct · used/max · @ tenancy(conditional)
//   Line 4: Resources   — $ cost · Spend?(bar pct) · 5h bar pct (reset) · Week bar pct (reset)
// ============================================================================

'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

// ----------------------------------
// Config — CCSL_<NAME> env overrides, same defaults as statusline.sh
// ----------------------------------
const numEnv = (k, d) => {
    const v = process.env[k];
    if (v === undefined || v === '') return d;
    const n = Number(v);
    return Number.isFinite(n) ? n : d;
};

// Bar width: CCSL_BAR_WIDTH wins; otherwise 5 cells when the terminal
// (COLUMNS, passed by CC) is narrower than 100 columns, else 10.
function defaultBarWidth() {
    const cols = Number(process.env.COLUMNS);
    return Number.isFinite(cols) && cols > 0 && cols < 100 ? 5 : 10;
}

const CFG = {
    BAR_WIDTH:      numEnv('CCSL_BAR_WIDTH', defaultBarWidth()),
    CTX_WARN:       numEnv('CCSL_CTX_WARN', 50),
    CTX_CRIT:       numEnv('CCSL_CTX_CRIT', 80),
    FIRE_THRESHOLD: numEnv('CCSL_FIRE_THRESHOLD', 90),
    LIMIT_WARN_MIN: numEnv('CCSL_LIMIT_WARN_MIN', 15),
    COST_WARN:      process.env.CCSL_COST_WARN ?? '2.0',
    COST_CRIT:      process.env.CCSL_COST_CRIT ?? '5.0',
    GIT_TIMEOUT:    numEnv('CCSL_GIT_TIMEOUT', 1),
};

// ----------------------------------
// ANSI colors
// ----------------------------------
const C = {
    RESET:       '\x1b[0m',
    BOLD:        '\x1b[1m',
    FG_CYAN:     '\x1b[38;5;80m',
    FG_GREEN:    '\x1b[38;5;114m',
    FG_YELLOW:   '\x1b[38;5;179m',
    FG_RED:      '\x1b[38;5;203m',
    FG_PINK:     '\x1b[38;5;218m',
    FG_BLUE:     '\x1b[38;5;111m',
    FG_LAVENDER: '\x1b[38;5;147m',
    FG_MUTED:    '\x1b[38;5;246m',
    FG_SEP:      '\x1b[38;5;242m',
    FG_DIM:      '\x1b[38;5;238m',
};

const SEP = `  ${C.FG_SEP}·${C.RESET}  `;

// ----------------------------------
// Helpers
// ----------------------------------
function makeBar(pct, width = CFG.BAR_WIDTH) {
    let p = pct;
    if (p < 0) p = 0;
    if (p > 100) p = 100;
    const filled = Math.floor(p * width / 100);
    const empty = width - filled;
    return '▰'.repeat(filled) + C.FG_DIM + '▱'.repeat(empty) + C.RESET;
}

function colorByPct(pct) {
    if (pct < CFG.CTX_WARN) return C.FG_GREEN;
    if (pct < CFG.CTX_CRIT) return C.FG_YELLOW;
    return C.FG_RED;
}

function formatTokens(n) {
    if (n >= 1_000_000) {
        const tenths = Math.floor(n / 100_000);
        return `${Math.floor(tenths / 10)}.${tenths % 10}M`;
    }
    if (n >= 1_000) {
        return `${Math.floor((n + 500) / 1000)}k`;
    }
    return String(n);
}

// Mirror bash _to_cents: string-parse to avoid float drift.
// "1.34" -> 134, "0.5" -> 50, "5" -> 500, "" -> 0
function toCents(v) {
    const s = String(v ?? '');
    if (!s) return 0;
    if (s.includes('.')) {
        const [iPart, rest = ''] = s.split('.');
        const f = (rest + '00').slice(0, 2);
        return (parseInt(iPart || '0', 10) || 0) * 100 + (parseInt(f, 10) || 0);
    }
    return (parseInt(s, 10) || 0) * 100;
}

// Worktree names longer than this are cut to WT_MAX-2 chars + "…" so a
// UUID-style name (orca, claude --worktree) does not overflow Line 2.
const WT_MAX = 24;
function truncWt(name) {
    return name.length > WT_MAX ? name.slice(0, WT_MAX - 2) + '…' : name;
}

function pad3(n) {
    return String(n).padStart(3, ' ');
}

// ----------------------------------
// Stdin — synchronous read, non-blocking fallback.
// CC sends a bounded JSON payload and closes the pipe, so readFileSync(0)
// returns immediately. TTY / empty-pipe cases throw EAGAIN/ENOTTY → fall back
// to '{}'. No event-loop entry → keeps cold start tight.
// Note: test runner pipes with a trailing NUL; strip it before parsing.
// ----------------------------------
function readStdinSync() {
    try {
        return fs.readFileSync(0, 'utf8');
    } catch (e) {
        if (process.env.INPUT_EMPTY) {
            process.stderr.write(`(statusline debug: stdin read failed: ${e && e.code ? e.code : 'ERR'})\n`);
        }
        return '';
    }
}

function parseInput() {
    const raw = readStdinSync().replace(/\0/g, '').trim();
    if (!raw) return {};
    try {
        return JSON.parse(raw);
    } catch {
        return {};
    }
}

// ----------------------------------
// git — spawnSync with built-in timeout (cross-platform; no timeout/gtimeout fork)
// ----------------------------------
function gitSafe(cwd, args) {
    try {
        const r = spawnSync('git', args, {
            cwd,
            timeout: CFG.GIT_TIMEOUT * 1000,
            encoding: 'utf8',
            env: { ...process.env, LC_ALL: 'C' },
            windowsHide: true,
            shell: false,
        });
        // r.status === null when killed by the timeout signal — treat as failure.
        if (r.status === null || r.status !== 0 || r.error) return null;
        return (r.stdout || '').replace(/\n+$/, '');
    } catch {
        return null;
    }
}

// ----------------------------------
// Tenancy — read oauthAccount from ~/.claude.json
// ----------------------------------
function readTenancy() {
    try {
        const f = path.join(os.homedir() || '.', '.claude.json');
        const raw = fs.readFileSync(f, 'utf8');
        const j = JSON.parse(raw);
        const a = j.oauthAccount || {};
        const orgName = a.organizationName || '';
        const orgType = a.organizationType || '';
        const seatTier = typeof a.seatTier === 'string' ? a.seatTier : '';
        const displayName = a.displayName || '';
        const email = a.emailAddress || '';
        if (!displayName && !email) return null;
        return { orgName, orgType, seatTier, displayName, email };
    } catch {
        return null;
    }
}

function formatTenancy(t) {
    if (!t) return '';
    const name = t.displayName || (t.email ? t.email.split('@')[0] : '');
    if (!name) return '';
    // Newer ~/.claude.json carries organizationType (e.g. claude_max,
    // claude_team) and seatTier (string only on team/enterprise seats): decide
    // from those alone. Older files fall back to the auto-generated name pattern.
    let personal;
    if (t.orgType) {
        personal = !(t.seatTier || /team|enterprise/i.test(t.orgType));
    } else {
        personal = !t.orgName || /'s (Individual )?Organization$/.test(t.orgName);
    }
    if (personal) {
        return `@ ${C.FG_LAVENDER}${name}${C.RESET}`;
    }
    return `@ ${C.FG_LAVENDER}${name}${C.RESET} ${C.FG_SEP}(${C.RESET}${C.FG_BLUE}${t.orgName}${C.RESET}${C.FG_SEP})${C.RESET}`;
}

// ----------------------------------
// Line 1 — cwd (dim parent + bold basename; "~" expansion)
// ----------------------------------
function renderLine1(cwd) {
    let p = cwd;
    const home = os.homedir();
    if (home && p.startsWith(home)) {
        p = '~' + p.slice(home.length);
    }
    // path.parse is OS-native: on Linux/macOS only "/" is a separator (matches
    // bash reference exactly — backslashes in input are treated as literal
    // chars), on Windows both "/" and "\" split, giving native UX without
    // breaking byte-equality with sh on the snapshot host.
    const parsed = path.parse(p);
    if (!parsed.base || parsed.dir === '') {
        return `${C.FG_CYAN}${C.BOLD}${p}${C.RESET}`;
    }
    const prefix = p.slice(0, p.length - parsed.base.length);
    return `${C.FG_MUTED}${prefix}${C.RESET}${C.FG_CYAN}${C.BOLD}${parsed.base}${C.RESET}`;
}

// ----------------------------------
// Line 2 — git info with 5s per-CWD file cache
// ----------------------------------
const CACHE_TTL = 5;

function cacheDir() {
    let user = 'user';
    try {
        // os.userInfo() can throw on restricted Windows accounts (EPERM) or
        // minimal containers without USER/SUDO_USER set.
        user = (os.userInfo().username || 'user').replace(/[^a-zA-Z0-9_-]/g, '_');
    } catch { /* fall back to 'user' */ }
    return path.join(os.tmpdir(), `claude-code-statusline-${user}`);
}

function computeLine2(cwd, wtName) {
    if (gitSafe(cwd, ['rev-parse', '--git-dir']) === null) {
        return `${C.FG_DIM}(no git repo)${C.RESET}`;
    }

    let branch = gitSafe(cwd, ['symbolic-ref', '--short', 'HEAD'])
        ?? gitSafe(cwd, ['rev-parse', '--abbrev-ref', 'HEAD'])
        ?? '';
    if (!branch || branch === 'HEAD') branch = 'detached';

    // Worktree — prefer CC-provided field, fall back to git-dir path pattern
    let wtPart = '';
    if (wtName) {
        wtPart = `⌥ ${C.FG_LAVENDER}wt:${truncWt(wtName)}${C.RESET}${SEP}`;
    } else {
        const gitDir = gitSafe(cwd, ['rev-parse', '--git-dir']);
        if (gitDir && gitDir.includes('/.git/worktrees/')) {
            const wtRoot = gitSafe(cwd, ['rev-parse', '--show-toplevel']) || '';
            const fallback = wtRoot.split('/').pop() || '';
            wtPart = `⌥ ${C.FG_LAVENDER}wt:${truncWt(fallback)}${C.RESET}${SEP}`;
        }
    }

    // Dirty status
    const porcelain = gitSafe(cwd, ['status', '--porcelain']) ?? '';
    let statusPart;
    if (!porcelain) {
        statusPart = `✓ ${C.FG_GREEN}clean${C.RESET}`;
    } else {
        const files = porcelain.split(/\r?\n/).filter(l => l.length > 0).length;
        const shortstat = gitSafe(cwd, ['diff', '--shortstat', 'HEAD']) ?? '';
        const addMatch = shortstat.match(/(\d+)\s+insertion/);
        const delMatch = shortstat.match(/(\d+)\s+deletion/);
        const added = addMatch ? addMatch[1] : '0';
        const deleted = delMatch ? delMatch[1] : '0';
        statusPart = `± ${C.FG_RED}${files} files${C.RESET} ${C.FG_SEP}·${C.RESET} ${C.FG_GREEN}+${added}${C.RESET} ${C.FG_RED}−${deleted}${C.RESET}`;
    }

    return `${wtPart}⎇ ${C.FG_YELLOW}${branch}${C.RESET}${SEP}${statusPart}`;
}

function renderLine2(cwd, wtName) {
    const key = cwd.replace(/[^a-zA-Z0-9_-]/g, '_');
    const dir = cacheDir();
    const cacheFile = path.join(dir, `git-${key}.cache`);

    // Cache hit
    try {
        const st = fs.statSync(cacheFile);
        const ageSec = (Date.now() - st.mtimeMs) / 1000;
        if (ageSec < CACHE_TTL) {
            return fs.readFileSync(cacheFile, 'utf8');
        }
    } catch { /* miss */ }

    const out = computeLine2(cwd, wtName);

    // Best-effort atomic cache write (0700 perms on Unix; Windows ignores mode)
    try {
        fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
        const tmp = `${cacheFile}.tmp.${process.pid}`;
        fs.writeFileSync(tmp, out);
        fs.renameSync(tmp, cacheFile);
    } catch { /* ignore */ }

    return out;
}

// PR badge — appended outside the git cache so review-state changes show
// immediately. CC sends `pr` only inside a repo with an open PR/MR.
function prBadge(number, state, kind) {
    if (number === '' || number === null || number === undefined) return '';
    const colors = {
        approved: C.FG_GREEN, changes_requested: C.FG_RED, draft: C.FG_MUTED, '': C.FG_MUTED,
    };
    const color = colors[state] ?? C.FG_YELLOW;
    const prefix = kind === 'mr' ? '!' : '#';
    return `${SEP}${color}${prefix}${number}${state ? ` ${state}` : ''}${C.RESET}`;
}

// ----------------------------------
// Line 3 — model · context bar · used/max · tenancy?
// ----------------------------------
function renderLine3(model, effort, ctxPct, ctxUsed, ctxMax, cacheWarm, cacheHit) {
    const color = colorByPct(ctxPct);
    const bar = makeBar(ctxPct);
    const extra = ctxPct >= CFG.FIRE_THRESHOLD ? ' !' : '';
    const usedFmt = formatTokens(ctxUsed);
    const maxFmt = formatTokens(ctxMax);
    const t = readTenancy();
    const suffix = t ? `${SEP}${formatTenancy(t)}` : '';
    // effort.level is only sent for models that support reasoning effort.
    const effortSeg = effort ? ` ${C.FG_MUTED}(${effort})${C.RESET}` : '';
    // prompt_cache appears after the first API response; hit_ratio stays
    // null while token counts are zero.
    let cacheSeg = '';
    if (cacheWarm !== null && cacheWarm !== undefined) {
        const cacheColor = cacheWarm ? C.FG_GREEN : C.FG_MUTED;
        const pct = Number.isFinite(cacheHit) ? ` ${Math.floor(cacheHit * 100)}%` : '';
        cacheSeg = `${SEP}⚡ ${cacheColor}${cacheWarm ? 'warm' : 'cold'}${pct}${C.RESET}`;
    }

    return `✦ ${C.FG_PINK}${model}${C.RESET}${effortSeg}${SEP}${bar}  ${color}${C.BOLD}${pad3(ctxPct)}%${C.RESET}${extra} ${C.FG_SEP}·${C.RESET} ${C.FG_MUTED}${usedFmt} / ${maxFmt}${C.RESET}${cacheSeg}${suffix}`;
}

// ----------------------------------
// Line 4 — cost · Spend · 5h · Week
// ----------------------------------
function formatCost(cost) {
    const ci = toCents(cost);
    const cw = toCents(CFG.COST_WARN);
    const cc = toCents(CFG.COST_CRIT);
    let color, extra = '';
    if (ci < cw) color = C.FG_GREEN;
    else if (ci < cc) color = C.FG_YELLOW;
    else { color = C.FG_RED; extra = ' !'; }
    const n = Number(cost);
    const shown = Number.isFinite(n) ? n.toFixed(2) : '0.00';
    return `$ ${color}${C.BOLD}${shown}${C.RESET}${extra}`;
}

function formatRemaining(resetEpoch) {
    if (resetEpoch === '' || resetEpoch === null || resetEpoch === undefined) return '--';
    // Future: if upstream switches to ISO8601 strings, allow Date.parse here.
    // While sh treats non-integer values as fallback "--", we mirror that.
    const ep = Number(resetEpoch);
    if (!Number.isInteger(ep) || ep < 0) return '--';
    const now = Math.floor(Date.now() / 1000);
    const diff = ep - now;
    if (diff <= 0) return 'reset';
    if (diff >= 86400) return `${Math.floor(diff / 86400)}d ${Math.floor((diff % 86400) / 3600)}h`;
    if (diff >= 3600)  return `${Math.floor(diff / 3600)}h ${Math.floor((diff % 3600) / 60)}m`;
    return `${Math.floor(diff / 60)}m`;
}

function renderLine4(cost, spendPct, spendReset, spendUsed, spendLimit,
                     fivePct, fiveReset, weekPct, weekReset) {
    const costPart = formatCost(cost);

    // Spend block — only behind a spend limit (Claude apps gateway, 2.1.251+).
    // Dollar figures are optional even when the block is present.
    let spendSeg = '';
    if (spendPct !== '' && spendPct !== null && spendPct !== undefined) {
        const parts = [];
        if (spendUsed !== '' && spendLimit !== '') {
            parts.push(`$${Math.round(Number(spendUsed))}/$${Math.round(Number(spendLimit))}`);
        }
        const spendRemain = formatRemaining(spendReset);
        if (spendRemain !== '--') parts.push(spendRemain);
        const paren = parts.length
            ? ` ${C.FG_SEP}(${C.FG_MUTED}${parts.join(' · ')}${C.RESET}${C.FG_SEP})${C.RESET}`
            : '';
        spendSeg = `${SEP}Spend ${makeBar(spendPct)}  ${colorByPct(spendPct)}${pad3(spendPct)}%${C.RESET}${paren}`;
    }

    // 5h block
    const fiveRemainStr = formatRemaining(fiveReset);
    let fiveColor, fiveBar, fivePctStr;
    if (fivePct !== '' && fivePct !== null && fivePct !== undefined) {
        fiveColor = colorByPct(fivePct);
        fiveBar = makeBar(fivePct);
        fivePctStr = `${pad3(fivePct)}%`;
    } else {
        fiveColor = C.FG_MUTED;
        fiveBar = makeBar(0);
        fivePctStr = ' --%';
    }
    let fiveExtra = '';
    const fiveMin = fiveRemainStr.match(/^(\d+)m$/);
    if (fiveMin && Number(fiveMin[1]) <= CFG.LIMIT_WARN_MIN) fiveExtra = ' !';
    let fiveRemainSeg = '';
    if (fiveRemainStr !== '--') {
        fiveRemainSeg = ` ${C.FG_SEP}(${C.FG_MUTED}${fiveRemainStr}${fiveExtra}${C.RESET}${C.FG_SEP})${C.RESET}`;
    }

    // Week block
    const weekRemainStr = formatRemaining(weekReset);
    let weekColor, weekBar, weekPctStr;
    if (weekPct !== '' && weekPct !== null && weekPct !== undefined) {
        weekColor = colorByPct(weekPct);
        weekBar = makeBar(weekPct);
        weekPctStr = `${pad3(weekPct)}%`;
    } else {
        weekColor = C.FG_MUTED;
        weekBar = makeBar(0);
        weekPctStr = ' --%';
    }
    let weekRemainSeg = '';
    if (weekRemainStr !== '--') {
        weekRemainSeg = ` ${C.FG_SEP}(${C.FG_MUTED}${weekRemainStr}${C.RESET}${C.FG_SEP})${C.RESET}`;
    }

    return `${costPart}${spendSeg}${SEP}5h ${fiveBar}  ${fiveColor}${fivePctStr}${C.RESET}${fiveRemainSeg}${SEP}Week ${weekBar}  ${weekColor}${weekPctStr}${C.RESET}${weekRemainSeg}`;
}

// ----------------------------------
// Extract — mirror bash jq field selection with safe defaults
// ----------------------------------
function extract(data) {
    const cw = data.context_window ?? {};
    const inTok = Number(cw.total_input_tokens ?? 0) || 0;
    const ctxMax = Number(cw.context_window_size ?? 200000) || 200000;
    // CC's used_percentage counts input only (input + cache_creation +
    // cache_read = total_input_tokens); mirror that so bar and count agree.
    const ctxUsed = inTok;
    const ctxPctRaw = cw.used_percentage;
    const ctxPct = Math.floor(
        ctxPctRaw === null || ctxPctRaw === undefined
            ? (ctxUsed * 100) / ctxMax
            : Number(ctxPctRaw),
    );

    const rl = data.rate_limits ?? {};
    const fh = rl.five_hour ?? {};
    const sd = rl.seven_day ?? {};
    const sl = rl.spend_limit ?? {};

    const pctOrEmpty = (v) => (v === null || v === undefined) ? '' : Math.floor(Number(v));

    return {
        model:      data.model?.display_name ?? 'Claude',
        cwd:        data.workspace?.current_dir ?? '.',
        ctxUsed,
        ctxMax,
        ctxPct,
        cost:       data.cost?.total_cost_usd ?? 0,
        fiveReset:  fh.resets_at ?? '',
        fivePct:    pctOrEmpty(fh.used_percentage),
        weekPct:    pctOrEmpty(sd.used_percentage),
        weekReset:  sd.resets_at ?? '',
        spendPct:   pctOrEmpty(sl.used_percentage),
        spendReset: sl.resets_at ?? '',
        spendUsed:  sl.used_usd ?? '',
        spendLimit: sl.limit_usd ?? '',
        prNumber:   data.pr?.number ?? '',
        prState:    data.pr?.review_state ?? '',
        prKind:     data.pr?.kind ?? '',
        wtName:     data.workspace?.git_worktree ?? '',
        effort:     data.effort?.level ?? '',
        cacheWarm:  data.prompt_cache?.warm ?? null,       // true/false, null → segment omitted
        cacheHit:   data.prompt_cache?.hit_ratio ?? null,  // 0..1, null → % omitted
    };
}

// ----------------------------------
// Main — catch-all so CC never sees a half-written line on unexpected throws
// ----------------------------------
function main() {
    const data = parseInput();
    const f = extract(data);

    const out =
        renderLine1(f.cwd) + '\n' +
        renderLine2(f.cwd, f.wtName) + prBadge(f.prNumber, f.prState, f.prKind) + '\n' +
        renderLine3(f.model, f.effort, f.ctxPct, f.ctxUsed, f.ctxMax, f.cacheWarm, f.cacheHit) + '\n' +
        renderLine4(f.cost, f.spendPct, f.spendReset, f.spendUsed, f.spendLimit,
                    f.fivePct, f.fiveReset, f.weekPct, f.weekReset) + '\n';

    process.stdout.write(out);
}

try {
    main();
} catch (e) {
    let msg = e && e.message ? e.message : 'unknown';
    const home = os.homedir();
    if (home) msg = msg.split(home).join('~');
    process.stdout.write(`▸ (statusline error: ${msg})\n`);
}
