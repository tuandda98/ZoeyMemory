#!/usr/bin/env python3
"""Append a session marker or a user prompt to the prompt journal.

Usage: log_prompt.py <root> <cfg> <i18n_dir>     (hook JSON on stdin)

- SessionStart JSON  -> writes the "new session" marker line
- UserPromptSubmit   -> writes "- [HH:MM] <prompt>" (truncated, machine-generated prompts skipped)
- missing/invalid config, journal disabled, or any error -> does nothing.
Always exits 0: a broken journal must never block a working session.
"""
import datetime
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import zoey  # noqa: E402


def main():
    root, cfg_path, i18n_dir = sys.argv[1:4]
    cfg, _err = zoey.load_cfg(cfg_path)
    if cfg is None:
        return  # missing or invalid: the doctor reports invalid configs; hooks stay silent
    if zoey.cfg_value(cfg, "journal.enabled") is False:
        return
    try:
        data = json.load(sys.stdin)
    except Exception:
        return
    if not isinstance(data, dict):
        return

    lang, _ = zoey.resolve_lang(cfg, i18n_dir)
    t = zoey.I18n(i18n_dir, lang or "en")
    zoey.apply_timezone(cfg)
    now = datetime.datetime.now()
    event = data.get("hook_event_name", "")

    if event == "SessionStart":
        line = t.get("new_session", stamp=now.strftime("%Y-%m-%d %H:%M"),
                     branch=zoey.git_branch(root), source=str(data.get("source", "?")))
    elif event == "UserPromptSubmit":
        prompt = " ".join(str(data.get("prompt", "")).split())
        if not prompt or zoey.is_noise(prompt):
            return
        if len(prompt) > zoey.PROMPT_MAX:
            prompt = prompt[:zoey.PROMPT_MAX] + "…"
        line = "- [%s] %s\n" % (now.strftime("%H:%M"), prompt)
    else:
        return

    prompts_rel, _ = zoey.journal_paths(cfg)
    path = os.path.join(root, prompts_rel)
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    if not os.path.exists(path) or os.path.getsize(path) == 0:
        header = t.get("prompts_header")
        with open(path, "w", encoding="utf-8") as f:
            f.write(header if header != "prompts_header" else "# Prompt journal (automatic)\n")
    with open(path, "a", encoding="utf-8") as f:
        f.write(line)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
