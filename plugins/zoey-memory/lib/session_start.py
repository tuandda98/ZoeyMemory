#!/usr/bin/env python3
"""Render the context that session-start.sh injects at the start of a session.

Usage: session_start.py <root> <cfg> <i18n_dir> <events>

<events>: newline-separated records emitted by the bash sync step, fields separated by TAB:
  FETCH_SLOW | FETCH_FAILED | CFG_INVALID
  PULLED <n> <upstream> | PULL_SLOW <n> <upstream> | PULL_FAILED <n> <upstream>
  DIRTY <n> <upstream> | DIVERGED <n> <upstream> | BEHIND_NO_PULL <n> <upstream>
  UNPUSHED <n>

Prints the hook JSON ({"hookSpecificOutput": {"additionalContext": ...}}) or nothing.
Never raises: on an internal error it prints an English fallback that names the error and still
carries the sync lines, so a bad translation or config can never hide a git warning.
"""
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import zoey  # noqa: E402

SYNC_KEYS = {
    "FETCH_SLOW": "sync_fetch_slow",
    "FETCH_FAILED": "sync_fetch_failed",
    "PULLED": "sync_pulled",
    "PULL_SLOW": "sync_pull_slow",
    "PULL_FAILED": "sync_pull_failed",
    "DIRTY": "sync_dirty",
    "DIVERGED": "sync_diverged",
    "BEHIND_NO_PULL": "sync_behind_no_pull",
    "UNPUSHED": "sync_unpushed",
}


def emit(ctx):
    print(json.dumps({
        "hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": ctx},
        "suppressOutput": True,
    }))


def sh(root, *cmd):
    try:
        return subprocess.run(cmd, cwd=root, capture_output=True, text=True, timeout=10).stdout.strip()
    except Exception:
        return ""


def parse_events(events):
    out = []
    for ev in events.splitlines():
        f = ev.split("\t")
        if f and f[0] in SYNC_KEYS:
            out.append(f)
    return out


def render_sync(t, events):
    lines = []
    for f in events:
        key = SYNC_KEYS[f[0]]
        if f[0] in ("UNPUSHED",):
            lines.append(t.get(key, n=f[1] if len(f) > 1 else "?"))
        elif len(f) >= 3:
            lines.append(t.get(key, n=f[1], upstream=f[2]))
        else:
            lines.append(t.get(key))
    return lines


def render(root, cfg_path, i18n_dir, events):
    cfg, err = zoey.load_cfg(cfg_path)
    if cfg is None:
        t = zoey.I18n(i18n_dir, "en")
        emit(t.get("ctx_title") + "\n\n" + t.get("cfg_invalid", path=cfg_path, reason=err or "?"))
        return

    lang, _ = zoey.resolve_lang(cfg, i18n_dir)
    t = zoey.I18n(i18n_dir, lang or "en")
    p_rel, s_rel = zoey.journal_paths(cfg)
    n_prompts = zoey.cfg_value(cfg, "context.recentPrompts")
    parts = []

    sync_lines = render_sync(t, events)
    if sync_lines:
        parts.append(t.get("sync_title") + "\n" + "\n".join(sync_lines))

    if zoey.cfg_value(cfg, "context.enabled") is False:
        if parts:
            emit(t.get("ctx_title") + "\n\n" + "\n\n".join(parts))
        return

    # 1. What the user asked recently (old journals may still contain machine noise: filter here too).
    asks = []
    for ln in zoey.read_text(os.path.join(root, p_rel)).splitlines():
        m = re.match(r"^- \[(\d{2}:\d{2})\] (.+)$", ln)
        if not m or zoey.is_noise(m.group(2)):
            continue
        asks.append("[%s] %s" % (m.group(1), m.group(2).strip()[:200]))
    if asks:
        parts.append(t.get("asks_title", n=n_prompts, path=p_rel) + "\n" + "\n".join(asks[-n_prompts:]))

    # 2. Latest session note. Entries are "## " headings at column 0; the header's example is
    #    indented so it is not one, and "YYYY" is skipped as a second guard.
    blocks = [b.strip() for b in re.split(r"(?m)^(?=## )", zoey.read_text(os.path.join(root, s_rel)))
              if b.strip().startswith("## ") and "YYYY" not in b.splitlines()[0]]
    if blocks:
        parts.append(t.get("session_title", path=s_rel) + "\n" + blocks[-1][:1500])

    # 3. OpenSpec: open changes with task progress. Filesystem only - a CLI change cannot break this.
    os_dir = os.path.join(root, "openspec")
    ch_dir = os.path.join(os_dir, "changes")
    if os.path.isdir(ch_dir):
        rows = []
        for name in sorted(os.listdir(ch_dir)):
            d = os.path.join(ch_dir, name)
            if not os.path.isdir(d) or name == "archive" or name.startswith("."):
                continue
            arts = [a for a in ("proposal.md", "design.md", "specs", "tasks.md") if os.path.exists(os.path.join(d, a))]
            done = total = 0
            for ln in zoey.read_text(os.path.join(d, "tasks.md")).splitlines():
                s = ln.strip()
                if re.match(r"^[-*] \[[ xX]\]", s):
                    total += 1
                    if re.match(r"^[-*] \[[xX]\]", s):
                        done += 1
            prog = t.get("tasks_done", done=done, total=total) if total else t.get("no_tasks")
            rows.append(t.get("openspec_row", name=name, progress=prog, artifacts=", ".join(arts) or t.get("empty")))
        if rows:
            parts.append(t.get("openspec_open_title") + "\n" + "\n".join(rows) + "\n\n" + t.get("openspec_hint"))
        else:
            parts.append(t.get("openspec_none"))
    elif not os.path.isdir(os_dir):
        parts.append(t.get("openspec_missing"))

    # 4. Recent commits.
    log = sh(root, "git", "log", "--oneline", "-8")
    if log:
        parts.append(t.get("git_title", branch=zoey.git_branch(root)) + "\n" + log)

    if parts:
        emit(t.get("ctx_title") + "\n\n" + t.get("ctx_intro") + "\n\n" + "\n\n".join(parts))


def main():
    root, cfg_path, i18n_dir = sys.argv[1:4]
    events = parse_events(sys.argv[4] if len(sys.argv) > 4 else "")
    try:
        render(root, cfg_path, i18n_dir, events)
    except Exception as e:  # fallback: English, still carries the git warnings
        try:
            t = zoey.I18n(i18n_dir, "en")
            lines = render_sync(t, events)
            body = t.get("render_failed", error="%s: %s" % (type(e).__name__, e))
            if lines:
                body += "\n\n" + t.get("sync_title") + "\n" + "\n".join(lines)
            emit(t.get("ctx_title") + "\n\n" + body)
        except Exception:
            pass


if __name__ == "__main__":
    main()
