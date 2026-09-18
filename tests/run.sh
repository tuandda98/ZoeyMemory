#!/usr/bin/env bash
# ZoeyMemory regression tests. Builds throwaway repos under a temp dir, runs the real hooks and
# scripts from this checkout, and asserts on files and rendered context. No network. bash 3.2 OK.
#
# Usage: bash tests/run.sh            (exit 0 = all passed)
#
# Assertions run in a child `bash -c '...'` with inputs passed through exported variables, never
# interpolated into code: rendered context contains backticks and `<name>` that must not be eval'd.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export P="$REPO/plugins/zoey-memory"
export H="$P/hooks" S="$P/scripts" I18N="$P/templates/i18n" ZOEY="$P/lib/zoey.py" REPO
export T="$(mktemp -d "${TMPDIR:-/tmp}/zoey-tests.XXXXXX")"
trap 'rm -rf "$T"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset CLAUDE_PROJECT_DIR

PASS=0; FAIL=0
pass() { PASS=$((PASS + 1)); printf 'PASS  %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL  %s\n' "$*"; }
t() { local name="$1"; shift; if bash -c "$1" >/dev/null 2>&1; then pass "$name"; else fail "$name"; fi; }

mkrepo() {  # <dir> -> git repo with one commit
  mkdir -p "$1" && git -C "$1" init -q -b main && printf '# x\n' > "$1/README.md" && git -C "$1" add -A && git -C "$1" commit -qm init
}
ctx() {  # run session-start.sh for repo $1 with SessionStart JSON on stdin; print additionalContext
  (cd "$1" && CLAUDE_PROJECT_DIR="$1" bash "$H/session-start.sh" <<<'{"hook_event_name":"SessionStart","source":"startup"}' 2>/dev/null) \
    | python3 -c 'import json,sys
raw=sys.stdin.read().strip()
print(json.loads(raw)["hookSpecificOutput"]["additionalContext"] if raw else "")'
}
prompt() {  # <repo> <prompt text>   (JSON built by python from stdin, so size does not matter)
  printf '%s' "$2" | python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"UserPromptSubmit","prompt":sys.stdin.read()}))' > "$T/prompt.json"
  (cd "$1" && CLAUDE_PROJECT_DIR="$1" bash "$H/log-prompt.sh" < "$T/prompt.json" 2>/dev/null)
}
setcfg() {  # <repo> <python statements on dict c>
  python3 - "$1/.claude/zoey-memory.json" "$2" <<'PY'
import json,sys; p=sys.argv[1]; c=json.load(open(p)); exec(sys.argv[2]); json.dump(c,open(p,"w"))
PY
}

echo "# static"
for f in "$H"/*.sh "$S"/*.sh "$P/lib/common.sh" "$REPO/setup.sh"; do bash -n "$f" || fail "syntax $f"; done; pass "bash syntax"
python3 -m py_compile "$P"/lib/*.py && pass "python compiles" || fail "python compiles"
for j in "$REPO/.claude-plugin/marketplace.json" "$P/.claude-plugin/plugin.json" "$P/hooks/hooks.json" "$P/templates/zoey-memory.json" "$I18N"/*.json; do python3 -m json.tool "$j" >/dev/null || fail "json $j"; done; pass "json valid"
t "i18n key parity en/vi" 'python3 -c "import json;e=set(json.load(open(\"$I18N/en.json\")));v=set(json.load(open(\"$I18N/vi.json\")));raise SystemExit(0 if e==v else 1)"'
t "no Vietnamese diacritics outside vi files" 'python3 - <<PY
import os,re,sys
bad=[]
for d,_,fs in os.walk(os.environ["REPO"]):
    if "/.git" in d or "/tests" in d: continue
    for f in fs:
        p=os.path.join(d,f)
        if p.endswith(("i18n/vi.json","CLAUDE.vi.md")): continue
        try: s=open(p,encoding="utf-8").read()
        except Exception: continue
        if re.search("[ăâđêôơưàáảãạèéẻẽẹìíỉĩịòóỏõọùúủũụỳýỷỹỵ]", s): bad.append(p)
print(bad); sys.exit(1 if bad else 0)
PY'
t "hooks.json: SessionStart runs only session-start.sh" 'python3 -c "import json;h=json.load(open(\"$H/hooks.json\"))[\"hooks\"][\"SessionStart\"][0][\"hooks\"];raise SystemExit(0 if len(h)==1 and \"session-start.sh\" in h[0][\"command\"] else 1)"'
t "doctor makes no network calls" '! grep -qE "npm view|curl |wget " "$S/doctor.sh"'
t "sessions_header example is not a column-0 heading" 'python3 -c "import json;s=json.load(open(\"$I18N/en.json\"))[\"sessions_header\"];raise SystemExit(1 if any(l.startswith(\"## \") for l in s.splitlines()) else 0)"'
t "CLAUDE.<lang>.md templates use {prompts}/{sessions}, no hardcoded journal path" 'for f in "$P"/templates/CLAUDE.*.md; do grep -q "{prompts}" "$f" && grep -q "{sessions}" "$f" && ! grep -q "docs/memory" "$f" || exit 1; done'

echo; echo "# init"
export R="$T/en"; mkrepo "$R"
bash "$S/init.sh" "$R" >/dev/null 2>&1
t "init creates config/journals/block" '[ -s "$R/.claude/zoey-memory.json" ] && [ -s "$R/docs/memory/PROMPTS.md" ] && [ -s "$R/docs/memory/SESSIONS.md" ] && grep -q "zoey-memory:start" "$R/CLAUDE.md"'
t "init sets language en" '[ "$(python3 "$ZOEY" get "$R/.claude/zoey-memory.json" language)" = en ]'
t "block rendered with the default journal paths, no raw placeholder left" 'grep -q "docs/memory/PROMPTS.md" "$R/CLAUDE.md" && grep -q "docs/memory/SESSIONS.md" "$R/CLAUDE.md" && ! grep -q "{prompts}\|{sessions}" "$R/CLAUDE.md"'
export OUT="$(bash "$S/init.sh" "$R" 2>&1)"
t "init is idempotent (no OK lines except tool checks)" '! printf "%s" "$OUT" | grep -E "^OK " | grep -vE "openspec CLI|superpowers|ponytail" | grep -q .'
t "--language without value aborts (no infinite loop)" '! (cd "$T" && bash "$S/init.sh" --language)'
mkrepo "$T/xx"
t "--language xx aborts before writing anything" '! bash "$S/init.sh" --language xx "$T/xx" && [ ! -e "$T/xx/.claude/zoey-memory.json" ] && [ ! -e "$T/xx/CLAUDE.md" ]'
mkdir -p "$R/apps/web"; bash "$S/init.sh" "$R/apps/web" >/dev/null 2>&1
t "init from a subdirectory enables the repo root, no nested .git" '[ ! -e "$R/apps/web/.git" ] && [ ! -e "$R/apps/web/.claude" ]'
git -C "$R" add -A >/dev/null && git -C "$R" commit -qm enable
git -C "$R" worktree add -q "$T/wt" -b wt 2>/dev/null
export OUT="$(bash "$S/init.sh" "$T/wt" 2>&1)"
t "init inside a git worktree does not git init" 'printf "%s" "$OUT" | grep -q "git already present"'
printf '<!-- zoey-memory:start -->\nhalf\n' > "$T/xx/CLAUDE.md"; git -C "$T/xx" add -A; git -C "$T/xx" commit -qm x
export OUT="$(bash "$S/init.sh" "$T/xx" 2>&1)"
t "broken block (start without end) is reported, file untouched" 'printf "%s" "$OUT" | grep -q broken && [ "$(cat "$T/xx/CLAUDE.md")" = "$(printf "<!-- zoey-memory:start -->\nhalf")" ]'

echo; echo "# journal hook"
export OUT="$(prompt "$R" "hello there")"
t "skill reminder printed on a real prompt" 'printf "%s" "$OUT" | grep -q "Picking a skill"'
t "prompt journaled" 'grep -q "\] hello there" "$R/docs/memory/PROMPTS.md"'
export OUT="$(prompt "$R" "<system-reminder>noise</system-reminder>")"
t "no skill reminder for machine noise" '[ -z "$OUT" ]'
t "machine noise not journaled" '! grep -q noise "$R/docs/memory/PROMPTS.md"'
python3 -c 'print("x"*1200000, end="")' > "$T/big.txt"; prompt "$R" "$(cat "$T/big.txt")"
t "1.2 MB prompt truncated to 600 chars, hook survives" '[ "$(grep -c "xxxxxxxxxx…$" "$R/docs/memory/PROMPTS.md")" = 1 ] && [ "$(grep "xxxxxxxxxx…$" "$R/docs/memory/PROMPTS.md" | wc -c | tr -d " ")" -lt 700 ]'
setcfg "$R" 'c["journal"]["enabled"]=False'; prompt "$R" "MUST-NOT-APPEAR"
t "journal.enabled=false -> no write" '! grep -q MUST-NOT-APPEAR "$R/docs/memory/PROMPTS.md"'
setcfg "$R" 'c["context"]["skillReminder"]=False'; export OUT="$(prompt "$R" "quiet please")"
t "context.skillReminder=false -> no reminder" '[ -z "$OUT" ]'
git -C "$R" checkout -q -- .claude/zoey-memory.json

echo; echo "# sync + marker order"
git init -q --bare "$T/origin.git"; git -C "$R" remote add origin "$T/origin.git"; git -C "$R" add -A; git -C "$R" commit -qm j; git -C "$R" push -q -u origin main
git clone -q "$T/origin.git" "$T/other" && git -C "$T/other" commit -q --allow-empty -m "from other" && git -C "$T/other" push -q origin main
export C="$(ctx "$R")"
t "behind+clean -> PULLED" 'printf "%s" "$C" | grep -q "brought in 1 new commit"'
t "marker written after the pull (tree dirty only by the journal)" 'grep -q "^## New session" "$R/docs/memory/PROMPTS.md" && [ "$(git -C "$R" status --porcelain | wc -l | tr -d " ")" = 1 ] && [ "$(git -C "$R" rev-list --count HEAD..origin/main)" = 0 ]'
git -C "$T/other" commit -q --allow-empty -m "from other 2" && git -C "$T/other" push -q origin main
export C="$(ctx "$R")"
t "behind+dirty -> DIRTY, no pull" 'printf "%s" "$C" | grep -q "UNCOMMITTED CHANGES" && [ "$(git -C "$R" rev-list --count HEAD..origin/main)" = 1 ]'
git -C "$R" add -A && git -C "$R" commit -qm local
export C="$(ctx "$R")"
t "behind+ahead -> DIVERGED" 'printf "%s" "$C" | grep -q DIVERGED'
t "ahead -> UNPUSHED" 'printf "%s" "$C" | grep -q "NOT PUSHED"'
git -C "$R" add -A; git -C "$R" commit -qm marker; git -C "$R" pull -q --rebase origin main && git -C "$R" push -q origin main
git -C "$T/other" pull -q --rebase origin main && git -C "$T/other" commit -q --allow-empty -m "from other 3" && git -C "$T/other" push -q origin main
git -C "$R" fetch -q; git -C "$R" remote set-url origin "$T/does-not-exist.git"
export C="$(ctx "$R")"
t "fetch fails -> FETCH_FAILED + BEHIND_NO_PULL, never a DIVERGED lie" 'printf "%s" "$C" | grep -q "git fetch failed" && printf "%s" "$C" | grep -q "no pull was attempted" && ! printf "%s" "$C" | grep -q DIVERGED'
git -C "$R" remote set-url origin "$T/origin.git"; git -C "$R" add -A; git -C "$R" commit -qm m2; git -C "$R" pull -q --rebase origin main; git -C "$R" push -q origin main
git -C "$R" checkout -q -b 'feat|x' && git -C "$R" push -q -u origin 'feat|x' && git -C "$R" commit -q --allow-empty -m up
export C="$(ctx "$R")"
t "branch name with | renders UNPUSHED" 'printf "%s" "$C" | grep -q "1 commit(s) from the previous session are NOT PUSHED"'
git -C "$R" add -A; git -C "$R" commit -qm m3; git -C "$R" push -q origin 'feat|x'
git -C "$T/other" fetch -q && git -C "$T/other" checkout -q 'feat|x' && git -C "$T/other" commit -q --allow-empty -m o && git -C "$T/other" push -q origin 'feat|x'
printf 'dirty\n' >> "$R/README.md"
export C="$(ctx "$R")"
t "upstream origin/feat|x survives the event encoding" 'printf "%s" "$C" | grep -q "BEHIND origin/feat|x"'
git -C "$R" checkout -q -- README.md; git -C "$R" add -A; git -C "$R" commit -qm m4; git -C "$R" checkout -q main
git -C "$R" config protocol.ext.allow always; git -C "$R" remote set-url origin 'ext::sleep 60'
start=$(date +%s); export C="$(ctx "$R")"; export EL=$(( $(date +%s) - start ))
t "hanging remote -> FETCH_SLOW, hook done in ${EL}s (< 30)" 'printf "%s" "$C" | grep -q "took over 8s" && [ "$EL" -lt 30 ]'
git -C "$R" remote set-url origin "$T/origin.git"

echo; echo "# config robustness"
cp "$R/.claude/zoey-memory.json" "$T/cfg.bak"; printf '{ broken' > "$R/.claude/zoey-memory.json"
export N_BEFORE="$(wc -l < "$R/docs/memory/PROMPTS.md" | tr -d ' ')"
export C="$(ctx "$R")"; prompt "$R" "while-broken"
t "invalid JSON -> warning in context, no marker, no journal write" 'printf "%s" "$C" | grep -q "could not be read" && [ "$(wc -l < "$R/docs/memory/PROMPTS.md" | tr -d " ")" = "$N_BEFORE" ]'
cp "$T/cfg.bak" "$R/.claude/zoey-memory.json"
setcfg "$R" 'c["context"]["enabled"]=False; c["journal"]="oops"; c["language"]=False'
export C="$(ctx "$R")"
t "context.enabled=false + wrong-typed keys -> no crash, no sections" '! printf "%s" "$C" | grep -q "asked recently"'
cp "$T/cfg.bak" "$R/.claude/zoey-memory.json"
mkdir -p "$T/i18n-bad" && cp "$I18N/en.json" "$T/i18n-bad/" && printf '{"asks_title":"bad {nope}","ctx_title":""}' > "$T/i18n-bad/vi.json"
t "broken translation falls back to English per key" '[ "$(python3 -c "import sys;sys.path.insert(0,\"$P/lib\");import zoey;t=zoey.I18n(\"$T/i18n-bad\",\"vi\");print(t.get(\"asks_title\",n=3,path=\"p\"))")" = "## What the user asked recently (last 3, source p)" ]'

echo; echo "# session note + openspec"
export C="$(ctx "$R")"
t "header-only SESSIONS.md -> no session-note section" '! printf "%s" "$C" | grep -q "Latest session note"'
printf '\n## 2026-01-01 10:00 - branch `main` - machine A\n- In progress: task Z\n' >> "$R/docs/memory/SESSIONS.md"
mkdir -p "$R/openspec/changes/thing" && printf -- '- [x] a\n- [ ] b\n- [ ] c\n' > "$R/openspec/changes/thing/tasks.md"
export C="$(ctx "$R")"
t "session note + openspec progress rendered" 'printf "%s" "$C" | grep -q "task Z" && printf "%s" "$C" | grep -q "1/3 tasks done"'

echo; echo "# paths with quotes + vi language + doctor"
export Q="$T/it's a \"test\""; mkrepo "$Q"
bash "$S/init.sh" --language vi "$Q" >/dev/null 2>&1
prompt "$Q" "xin chào"
export C="$(ctx "$Q")"
t "apostrophe/quote in repo path: init, journal, context all work (vi)" 'grep -q "xin chào" "$Q/docs/memory/PROMPTS.md" && printf "%s" "$C" | grep -q "Ngữ cảnh tự nạp"'
t "vi journals and CLAUDE block" 'head -1 "$Q/docs/memory/SESSIONS.md" | grep -q "Nhật ký phiên" && grep -q "Quy trình làm việc" "$Q/CLAUDE.md"'
bash "$S/init.sh" --language en "$Q" >/dev/null 2>&1
t "language switch vi -> en refreshes block and config" 'grep -q "^# Workflow" "$Q/CLAUDE.md" && [ "$(python3 "$ZOEY" get "$Q/.claude/zoey-memory.json" language)" = en ]'
export D="$(cd "$R" && bash "$S/doctor.sh" 2>&1)"
t "doctor with no args and no CLAUDE_PROJECT_DIR runs (no unbound \$1)" 'printf "%s" "$D" | grep -q "^# ZoeyMemory doctor"'
t "doctor: language + block + upstream OK on a healthy repo" 'printf "%s" "$D" | grep -q "language .en." && printf "%s" "$D" | grep -q "block matches" && printf "%s" "$D" | grep -q "upstream origin/main"'
export D="$(bash "$S/doctor.sh" "$T/xx" 2>&1)"
t "doctor reports the broken block" 'printf "%s" "$D" | grep -q "broken ZoeyMemory block"'
: > "$R/docs/memory/SESSIONS.md"
export D="$(bash "$S/doctor.sh" "$R" 2>&1)"
t "doctor flags an EMPTY journal file" 'printf "%s" "$D" | grep -q "is EMPTY"'

echo; echo "# custom journal paths"
export CP="$T/custom"; mkrepo "$CP"
mkdir -p "$CP/.claude" && printf '{"language":"en","journal":{"prompts":"notes/HISTORY.md","sessions":"notes/SESSIONS.md"}}' > "$CP/.claude/zoey-memory.json"
bash "$S/init.sh" "$CP" >/dev/null 2>&1
t "custom paths: init writes the journals there and renders them into the block" '[ -s "$CP/notes/HISTORY.md" ] && [ -s "$CP/notes/SESSIONS.md" ] && [ ! -e "$CP/docs" ] && grep -q "notes/HISTORY.md" "$CP/CLAUDE.md" && grep -q "notes/SESSIONS.md" "$CP/CLAUDE.md" && ! grep -q "docs/memory" "$CP/CLAUDE.md"'
export D="$(bash "$S/doctor.sh" "$CP" 2>&1)"
t "doctor: custom-path block matches" 'printf "%s" "$D" | grep -q "block matches.*notes/HISTORY.md"'
setcfg "$CP" 'c["journal"]["prompts"]="notes/OTHER.md"'
export D="$(bash "$S/doctor.sh" "$CP" 2>&1)"
t "doctor: journal path changed without re-init -> block differs" 'printf "%s" "$D" | grep -q "block differs"'
bash "$S/init.sh" "$CP" >/dev/null 2>&1
t "re-init after a path change refreshes the block" 'grep -q "notes/OTHER.md" "$CP/CLAUDE.md" && ! grep -q "notes/HISTORY.md" "$CP/CLAUDE.md"'
setcfg "$CP" 'c["journal"]["prompts"]=123'
t "wrong-typed journal path -> default, same as the hooks" '[ "$(python3 "$ZOEY" paths "$CP/.claude/zoey-memory.json" | head -1)" = docs/memory/PROMPTS.md ]'
t "block-check without a cfg arg still works (schema defaults)" 'python3 "$ZOEY" block-check "$R/CLAUDE.md" "$P/templates/CLAUDE.en.md"'

echo; echo "# 0.4.3: untracked files, compact, long notes, timezone, '> ' notes"
export U="$T/u"; mkrepo "$U"; bash "$S/init.sh" "$U" >/dev/null 2>&1
git -C "$U" add -A && git -C "$U" commit -qm enable
git init -q --bare "$T/u-origin.git"; git -C "$U" remote add origin "$T/u-origin.git"; git -C "$U" push -q -u origin main
git clone -q "$T/u-origin.git" "$T/u-other" && git -C "$T/u-other" commit -q --allow-empty -m "from other" && git -C "$T/u-other" push -q origin main
mkdir -p "$U/.qoder" && printf '{}' > "$U/.qoder/settings.local.json"
export C="$(ctx "$U")"
t "untracked file only -> still PULLED" 'printf "%s" "$C" | grep -q "brought in 1 new commit" && [ "$(git -C "$U" rev-list --count HEAD..origin/main)" = 0 ]'
git -C "$U" add docs && git -C "$U" commit -qm j && git -C "$U" push -q origin main
git -C "$T/u-other" pull -q && git -C "$T/u-other" commit -q --allow-empty -m "from other 2" && git -C "$T/u-other" push -q origin main
export HB="$(git -C "$U" rev-parse HEAD)" NM="$(grep -c '^## New session' "$U/docs/memory/PROMPTS.md")"
export C="$( (cd "$U" && CLAUDE_PROJECT_DIR="$U" bash "$H/session-start.sh" <<<'{"hook_event_name":"SessionStart","source":"compact"}' 2>/dev/null) | python3 -c 'import json,sys
raw=sys.stdin.read().strip()
print(json.loads(raw)["hookSpecificOutput"]["additionalContext"] if raw else "")')"
t "compact -> context re-loaded, no pull, no new session marker" 'printf "%s" "$C" | grep -q "## Git" && [ "$(git -C "$U" rev-parse HEAD)" = "$HB" ] && [ "$(grep -c "^## New session" "$U/docs/memory/PROMPTS.md")" = "$NM" ]'
t "hooks.json: SessionStart matcher includes compact" 'python3 -c "import json;m=json.load(open(\"$H/hooks.json\"))[\"hooks\"][\"SessionStart\"][0][\"matcher\"];raise SystemExit(0 if \"compact\" in m.split(\"|\") else 1)"'
python3 - "$U/docs/memory/SESSIONS.md" <<'PY'
import sys
open(sys.argv[1], "a").write("\n## 2026-02-02 10:00 - branch `main` - machine B\n- In progress: HEAD-MARK\n- filler "
                             + "x" * 5000 + "\n- The other machine needs to know: TAIL-MARK\n")
PY
export C="$(ctx "$U")"
t "long session note keeps head AND tail, says where the cut is" 'printf "%s" "$C" | grep -q HEAD-MARK && printf "%s" "$C" | grep -q TAIL-MARK && printf "%s" "$C" | grep -q "cut from the middle"'
setcfg "$U" 'c["timezone"]="Asia/Ho_Chi_Minh"'
export VN1="$(TZ=Asia/Ho_Chi_Minh date +%H:%M)"; (export TZ=UTC; prompt "$U" "tz-probe"); export VN2="$(TZ=Asia/Ho_Chi_Minh date +%H:%M)"
t "timezone config -> journal time in that zone, not the machine's (TZ=UTC here)" 'l="$(grep "tz-probe" "$U/docs/memory/PROMPTS.md")"; [ "$l" = "- [$VN1] tz-probe" ] || [ "$l" = "- [$VN2] tz-probe" ]'
setcfg "$U" 'c["timezone"]="Nowhere/Nope"'
export D="$(bash "$S/doctor.sh" "$U" 2>&1)"
t "doctor warns about an unknown timezone" 'printf "%s" "$D" | grep -q "not a known zone"'
printf -- '- [10:00] ask-with-note\n> decided: use plan B\n- [10:01] <task-notification>x\n> NOT-ATTACHED\n' >> "$U/docs/memory/PROMPTS.md"
export C="$(ctx "$U")"
t "'> ' note under a prompt is loaded with it; a note under noise is not" 'printf "%s" "$C" | grep -q "ask-with-note" && printf "%s" "$C" | grep -q "> decided: use plan B" && ! printf "%s" "$C" | grep -q NOT-ATTACHED'

echo
echo "passed=$PASS failed=$FAIL"
[ "$FAIL" -eq 0 ]
