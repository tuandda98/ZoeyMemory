#!/usr/bin/env python3
"""ZoeyMemory shared helpers - the ONE place that knows the config schema, its defaults, and i18n.

Imported by lib/log_prompt.py and lib/session_start.py. Called as a CLI by the bash scripts:

  zoey.py get <cfg> <dotted.key> [default]      print the value ('' if unset; booleans as true/false).
                                                 exit 2 if the config file is unreadable or invalid JSON.
  zoey.py validate <cfg>                         exit 0 valid, 2 invalid (reason on stderr).
  zoey.py lang <cfg|-> <i18n_dir> [requested]    print the resolved language code.
                                                 exit 1 (reason on stderr) if the requested/configured
                                                 language has no i18n file - never downgrades silently.
  zoey.py i18n <i18n_dir> <lang> <key>           print the string. exit 1 if missing or empty.
  zoey.py init-config <template> <dst> <name> <lang>
                                                 write a fresh config from the template (doc keys stripped).
  zoey.py set-lang <cfg> <lang>                  set `language` in an existing config.
  zoey.py block <claude_md> <template>           add or refresh the plugin-owned CLAUDE.md block.
                                                 prints added|refreshed|up-to-date; exit 3 = markers broken.
  zoey.py block-check <claude_md> <template>     prints ok|differs|missing|broken; exit 0 only for ok.

Python 3.6+ only, no third-party modules.
"""
import json
import os
import re
import subprocess
import sys

DEFAULTS = {
    "language": "en",
    "journal": {"enabled": True, "prompts": "docs/memory/PROMPTS.md", "sessions": "docs/memory/SESSIONS.md"},
    "context": {"enabled": True, "recentPrompts": 30},
    "git": {"autoPull": True, "allowCommit": True, "allowPush": True, "workingBranch": "main"},
}

LANG_RE = re.compile(r"^[a-z]{2,3}(-[A-Za-z0-9]{2,8})?$")
START = "<!-- zoey-memory:start -->"
END = "<!-- zoey-memory:end -->"
# Prompts that Claude Code generates itself (not typed by the user). Never journaled, never loaded.
NOISE_PREFIXES = ("<task-notification>", "<system-reminder>", "<local-command", "<command-name>")
PROMPT_MAX = 600


# ---------------------------------------------------------------- files

def read_text(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except Exception:
        return ""


def load_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


# ---------------------------------------------------------------- config

def load_cfg(path):
    """Return (cfg, error). cfg is a dict on success, None on error ('missing' or a reason)."""
    if not os.path.isfile(path):
        return None, "missing"
    try:
        c = load_json(path)
    except Exception as e:
        return None, "invalid JSON: %s" % e
    if not isinstance(c, dict):
        return None, "top level is not a JSON object"
    return c, None


def get(obj, dotted, default=None):
    cur = obj
    for k in dotted.split("."):
        if not isinstance(cur, dict):
            return default
        cur = cur.get(k)
    return default if cur is None else cur


def cfg_value(cfg, dotted):
    """Config value, falling back to the schema default when unset OR of the wrong type."""
    d = get(DEFAULTS, dotted)
    v = get(cfg or {}, dotted)
    if v is None:
        return d
    if isinstance(d, bool):
        return v if isinstance(v, bool) else d
    if isinstance(d, int):
        return v if (isinstance(v, int) and not isinstance(v, bool)) else d
    if isinstance(d, str):
        return v if (isinstance(v, str) and v.strip()) else d
    return v


def journal_paths(cfg):
    return cfg_value(cfg, "journal.prompts"), cfg_value(cfg, "journal.sessions")


def strip_doc_keys(o):
    if isinstance(o, dict):
        return {k: strip_doc_keys(v) for k, v in o.items() if not k.startswith("_")}
    if isinstance(o, list):
        return [strip_doc_keys(v) for v in o]
    return o


def write_json(path, obj):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False, indent=2)
        f.write("\n")


# ---------------------------------------------------------------- language / i18n

def resolve_lang(cfg, i18n_dir, requested=None):
    """Return (lang, error). Explicit request > config > 'en'. Error if the code is malformed or
    has no templates/i18n/<code>.json - callers must NOT fall back silently on error."""
    lang = requested or cfg_value(cfg, "language")
    if not isinstance(lang, str) or not LANG_RE.match(lang):
        return None, "invalid language code %r" % (lang,)
    if not os.path.isfile(os.path.join(i18n_dir, lang + ".json")):
        return None, "no i18n file for '%s' (expected %s)" % (lang, os.path.join(i18n_dir, lang + ".json"))
    return lang, None


class I18n:
    """Strings for one language, overlaid on English. `get` never raises: a bad translation
    (missing key, broken {placeholder}) falls back to English, then to the key name."""

    def __init__(self, i18n_dir, lang):
        self.en = self._load(os.path.join(i18n_dir, "en.json"))
        self.t = dict(self.en)
        if lang and lang != "en":
            self.t.update(self._load(os.path.join(i18n_dir, lang + ".json")))

    @staticmethod
    def _load(path):
        try:
            d = load_json(path)
            return {k: v for k, v in d.items() if isinstance(v, str) and not k.startswith("_")}
        except Exception:
            return {}

    def get(self, key, **kw):
        for table in (self.t, self.en):
            s = table.get(key)
            if not s:
                continue
            try:
                return s.format(**kw) if kw else s
            except Exception:
                continue
        return key


# ---------------------------------------------------------------- misc

def is_noise(prompt):
    return prompt.lstrip().startswith(NOISE_PREFIXES)


def git_branch(root):
    try:
        out = subprocess.run(["git", "-C", root, "branch", "--show-current"],
                             capture_output=True, text=True, timeout=5).stdout.strip()
        return out or "?"
    except Exception:
        return "?"


# ---------------------------------------------------------------- CLAUDE.md block

def block_status(claude_md, template, write):
    """added | refreshed | up-to-date | broken. With write=False nothing is touched."""
    src = read_text(claude_md) if os.path.exists(claude_md) else ""
    new = read_text(template).strip()
    if not new:
        return "broken"
    has_start, has_end = START in src, END in src
    if has_start != has_end:
        return "broken"
    if not has_start:
        if write:
            sep = "" if not src else ("\n" if src.endswith("\n") else "\n\n")
            with open(claude_md, "a", encoding="utf-8") as f:
                f.write(sep + new + "\n")
        return "added"
    pat = re.compile(re.escape(START) + r".*?" + re.escape(END), re.S)
    m = pat.search(src)
    if not m:
        return "broken"  # end marker before start marker
    if m.group(0).strip() == new:
        return "up-to-date"
    if write:
        with open(claude_md, "w", encoding="utf-8") as f:
            f.write(pat.sub(lambda _: new, src, count=1))
    return "refreshed"


# ---------------------------------------------------------------- CLI

def _fmt(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if v is None:
        return ""
    if isinstance(v, (dict, list)):
        return json.dumps(v, ensure_ascii=False)
    return str(v)


def main(argv):
    if not argv:
        print(__doc__)
        return 1
    cmd, args = argv[0], argv[1:]

    if cmd == "get":
        cfg, err = load_cfg(args[0])
        if cfg is None and err != "missing":
            print(err, file=sys.stderr)
            return 2
        default = args[2] if len(args) > 2 else ""
        v = get(cfg or {}, args[1])
        print(_fmt(v) if v is not None else default)
        return 0

    if cmd == "validate":
        cfg, err = load_cfg(args[0])
        if cfg is None:
            print(err, file=sys.stderr)
            return 2
        return 0

    if cmd == "lang":
        cfg = {}
        if args[0] != "-":
            cfg, err = load_cfg(args[0])
            if cfg is None and err != "missing":
                print(err, file=sys.stderr)
                return 2
            cfg = cfg or {}
        lang, err = resolve_lang(cfg, args[1], args[2] if len(args) > 2 and args[2] else None)
        if err:
            print(err, file=sys.stderr)
            return 1
        print(lang)
        return 0

    if cmd == "i18n":
        s = I18n(args[0], args[1]).get(args[2])
        if not s or s == args[2]:
            print("missing i18n key %r for %s" % (args[2], args[1]), file=sys.stderr)
            return 1
        sys.stdout.write(s)
        return 0

    if cmd == "init-config":
        tpl, dst, name, lang = args[:4]
        c = strip_doc_keys(load_json(tpl))
        c["name"] = name
        c["language"] = lang
        write_json(dst, c)
        return 0

    if cmd == "set-lang":
        cfg, err = load_cfg(args[0])
        if cfg is None:
            print(err, file=sys.stderr)
            return 2
        cfg["language"] = args[1]
        write_json(args[0], cfg)
        return 0

    if cmd == "block":
        st = block_status(args[0], args[1], write=True)
        print(st)
        return 3 if st == "broken" else 0

    if cmd == "block-check":
        st = block_status(args[0], args[1], write=False)
        print({"added": "missing", "refreshed": "differs", "up-to-date": "ok", "broken": "broken"}[st])
        return 0 if st == "up-to-date" else 1

    print("unknown command %r" % cmd, file=sys.stderr)
    return 1


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except IndexError:
        print("missing arguments; see --help", file=sys.stderr)
        sys.exit(1)
