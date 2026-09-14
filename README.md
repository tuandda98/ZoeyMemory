# ZoeyMemory

**Memory across Claude Code sessions and machines - with OpenSpec for specs and superpowers for code quality, in one install.**

Claude Code forgets everything when a session ends, and nothing it knew on your laptop exists on
your desktop. ZoeyMemory fixes that with two small hooks and a few conventions that live in git:

- every prompt you send is journaled to a committed file,
- every session starts by pulling the repo and loading what happened last time (on any machine),
- every decision goes through OpenSpec, so the "why" is written down and archived by date,
- every implementation goes through superpowers, so tests, debugging and verification are not optional.

It is a Claude Code **plugin** plus a **toolkit** around it. One install per machine, one command per repo.

---

## Table of contents

- [How it works](#how-it-works)
- [Install (once per machine)](#install-once-per-machine)
- [Enable in a repo (once per repo)](#enable-in-a-repo-once-per-repo)
- [A working day](#a-working-day)
- [Commands](#commands)
- [Hooks](#hooks)
- [The four journals](#the-four-journals)
- [Configuration](#configuration)
- [Language](#language)
- [Keeping the three tools current](#keeping-the-three-tools-current)
- [Failure policy](#failure-policy)
- [Repository layout](#repository-layout)
- [Developing and testing](#developing-and-testing)
- [FAQ](#faq)
- [License](#license)

---

## How it works

Three tools, one job each, no overlap:

| Job | Tool | Source |
|---|---|---|
| Memory across sessions and machines | **ZoeyMemory** (this repo) | `plugins/zoey-memory/` |
| Specs, design, reasoning behind decisions, dated history | **OpenSpec** | [Fission-AI/openspec](https://github.com/Fission-AI/openspec) |
| TDD, systematic debugging, verification before "done", code review | **superpowers** | [obra/superpowers](https://github.com/obra/superpowers) |

ZoeyMemory declares superpowers as a **plugin dependency** and installs the OpenSpec CLI on first
use, so you never install the other two by hand. A block that ZoeyMemory appends to your repo's
`CLAUDE.md` tells Claude which tool owns which job, so the three never fight (for example,
superpowers' own brainstorming skill is switched off in favor of OpenSpec's `/opsx:explore`).

```
 you type a prompt ──► log-prompt hook ──► docs/memory/PROMPTS.md   (committed)
                                                                      │
 new session ──► session-start hook:                                   │
     1. git fetch, pull --ff-only if safe                              │
     2. write the "new session" marker                                 ▼
     3. load into Claude's context:  last 30 prompts ◄────────────────┘
                                     latest session note   ◄── docs/memory/SESSIONS.md  (/zoey-memory:handoff)
                                     open OpenSpec changes ◄── openspec/changes/*/tasks.md
                                     recent git log
```

Everything ZoeyMemory writes is plain Markdown in your repo. Delete the folder and nothing is lost
but the convenience.

---

## Install (once per machine)

Requirements: Claude Code 2.1.242 or later, git, python3 (ships with macOS), Node.js 20.19+ for the
OpenSpec CLI.

```bash
claude plugin marketplace add obra/superpowers-marketplace   # once; makes the dependency resolvable
claude plugin marketplace add tuandda98/ZoeyMemory
claude plugin install zoey-memory@zoey-memory                 # installs zoey-memory + superpowers
```

The first line is needed because Claude Code never auto-adds a marketplace you have not reviewed;
once it is known, the dependency resolves on its own.

One-liner that does the same and installs the OpenSpec CLI too (safe to re-run):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/tuandda98/ZoeyMemory/main/setup.sh)
```

Verify:

```bash
claude plugin list        # zoey-memory and superpowers both "enabled"
openspec --version        # after setup.sh, or after the first /zoey-memory:init
```

Because of the dependency, `claude plugin disable superpowers@...` is refused while ZoeyMemory is
enabled; Claude Code prints the chained command to disable both. `claude plugin uninstall
zoey-memory --prune` removes superpowers too unless you installed it yourself.

---

## Enable in a repo (once per repo)

Open Claude Code in the repo and type:

```
/zoey-memory:init          # English
/zoey-memory:init vi       # Vietnamese journals, context and CLAUDE.md block
```

What it does, idempotently:

1. `git init` if the folder is not a repo yet (never inside an existing repo or worktree).
2. Installs the OpenSpec CLI if missing, then `openspec init --tools claude --language <code>`,
   which generates `/opsx:*` commands under `.claude/commands/opsx/`.
3. Writes `.claude/zoey-memory.json` (the only file the hooks read) with the chosen language.
4. Creates `docs/memory/PROMPTS.md` and `docs/memory/SESSIONS.md` with localized headers.
5. Appends the plugin-owned block to `CLAUDE.md` (between `<!-- zoey-memory:start/end -->` markers;
   re-running refreshes only that block). The block names your real journal paths: `{prompts}` and
   `{sessions}` in the template are filled from `journal.*` in the config.
6. Adds `.claude/settings.local.json` to `.gitignore`, checks that superpowers is installed.
7. Claude then fills `outsideGit` and `forbidden` in the config from what is actually in the repo,
   and commits everything.

Hooks take effect from the next session (or after `/reload-plugins`). Working on two machines?
Push now: the hooks can only sync a branch that has an upstream.

Everything created is committed, so the second machine just clones the repo - no init needed there.

---

## A working day

```
open a machine    ──►  hook pulls + loads context. Switched machines? also /zoey-memory:start
think             ──►  /opsx:explore <idea>            talk it through, no files written
decide            ──►  /opsx:propose <name>            proposal.md, design.md, specs/, tasks.md
build             ──►  /opsx:apply <name>              superpowers TDD + verification kick in
close             ──►  /opsx:archive <name>            dated history, living specs updated
leave a machine   ──►  /zoey-memory:handoff            session note, WIP commit, push
```

Small single-file fixes with no reasoning worth keeping: skip explore/propose and just ask; TDD and
verification still apply.

---

## Commands

All commands are `/zoey-memory:<name>`.

| Command | When | What it does |
|---|---|---|
| `init [code]` | once per repo | Enable ZoeyMemory + OpenSpec here (see above). Optional language code. Re-run with another code to switch languages. Unknown code or invalid existing config: aborts before writing anything. |
| `start` | start of day, especially after switching machines | Fetch and move to the working branch; reinstall dependencies if the lockfile changed; summarize what the other machine did from `git log` and both journals; list open OpenSpec changes and the next task; check every item in `outsideGit` (env files, migrations, keys) and ask for a manual transfer if something is missing. |
| `handoff` | before leaving a machine | Tick finished tasks in `openspec/changes/<name>/tasks.md`; append one entry to `docs/memory/SESSIONS.md` (in progress / why we stopped / waiting on whom / what the other machine needs to know); commit even unfinished work with a `WIP:` message; push; remind about things outside git. Never merges or deploys. |
| `doctor` | after updating any of the three tools, or when a hook seems silent | Read-only, offline health check: config valid, language has a translation file, journals present and non-empty, git upstream set, nothing git-ignored, OpenSpec CLI + `/opsx:*` commands + language line, superpowers enabled and still has every skill the CLAUDE.md block names, CLAUDE.md block matches the template. Claude fixes what is safe and hands you the command for the rest. |
| `update` | now and then | Update marketplaces, superpowers, ZoeyMemory and the OpenSpec CLI; run `openspec update` in this repo to regenerate its command files; then run the doctor. The only thing that touches the network. |

The mechanical parts are plain scripts you can run without Claude:
`scripts/init.sh [--language <code>] [repo]`, `scripts/doctor.sh [repo]`, `scripts/update.sh`.

---

## Hooks

Both exit silently when the repo has no `.claude/zoey-memory.json`, so installing the plugin never
bothers repos that did not opt in. The repo root is the git top level of the directory Claude was
launched in, so launching in a subdirectory works.

| Hook | Event | What it does |
|---|---|---|
| `session-start.sh` | SessionStart (startup, resume, `/clear`) | **1. Sync:** `git fetch` with an 8 s limit; if behind the upstream, the tree is clean and nothing is unpushed, `git pull --ff-only` with a 20 s limit. Every other situation only warns (dirty tree, diverged, unpushed, fetch failed, pull failed or stalled). **2. Marker:** writes the "new session" line to the prompt journal - after the pull, so the journal never blocks it. **3. Context:** loads the last 30 prompts, the latest session note, open OpenSpec changes with task progress, and the last 8 commits, in the configured language. |
| `log-prompt.sh` | UserPromptSubmit | Appends `- [HH:MM] <prompt>` to `docs/memory/PROMPTS.md`. Skips machine-generated prompts, truncates at 600 characters. |

SessionStart deliberately runs a single hook: hooks on the same event run concurrently, and the
marker must be written after the pull. Budget: 45 s for session start, 15 s per prompt; the
watchdogs keep the hook well inside that even when the network is dead.

---

## The four journals

They answer four different questions. Do not merge them.

| File | Answers | Written by |
|---|---|---|
| `docs/memory/PROMPTS.md` | *what did the user ask, in what order* | hook, automatically |
| `docs/memory/SESSIONS.md` | *what is in progress, why we stopped, who decides what* | Claude, on `/zoey-memory:handoff` |
| `openspec/changes/<name>/` and `openspec/changes/archive/` | *what, why, is it done* | OpenSpec |
| `git log` | *which lines of code changed* | commits |

To note the outcome of a prompt, add a `> ` line right under it in `PROMPTS.md`. To record why
something was decided, use OpenSpec - that is what `proposal.md` and `design.md` are for.

---

## Configuration

`.claude/zoey-memory.json`, created by `init`, safe to edit by hand. Full template with inline
documentation: [`plugins/zoey-memory/templates/zoey-memory.json`](plugins/zoey-memory/templates/zoey-memory.json).

| Key | Default | Meaning |
|---|---|---|
| `language` | `"en"` | Language of everything you read (see [Language](#language)). |
| `journal.enabled` | `true` | Automatic prompt journaling. |
| `journal.prompts` / `journal.sessions` | `docs/memory/PROMPTS.md` / `SESSIONS.md` | Journal paths, relative to the repo root. Point them at an existing file to keep an older journal going. The CLAUDE.md block names them too: re-run `init` after changing them (`doctor` flags the drift). |
| `context.enabled` | `true` | Load context at session start. Sync warnings are shown even when off. |
| `context.recentPrompts` | `30` | How many recent prompts to load. |
| `git.autoPull` | `true` | Fetch and fast-forward pull at session start. |
| `git.allowCommit` / `git.allowPush` | `true` | Whether `handoff` and `init` may commit / push. |
| `git.workingBranch` | `"main"` | Branch `start` switches back to. |
| `outsideGit.items` | env files, migrations, keys | Things that do not travel with git; `start` checks them, `handoff` reminds about them. |
| `forbidden.items` | deploy to production, delete real data | Things Claude must never do on its own in this repo. |

Keys of the wrong type fall back to their defaults. An unreadable file disables journaling and
sync and puts one warning line in the loaded context.

---

## Language

Plugin **source** is English only. Everything the **user reads** follows `language`: journal
headers, the session marker, the context loaded at session start, the CLAUDE.md block, and the
language Claude uses for session notes and reports. The same code is passed to
`openspec init --language`.

- Pick it at enable time: `/zoey-memory:init vi`.
- Switch later: `bash <plugin>/scripts/init.sh --language en`. Updates the config and refreshes the
  CLAUDE.md block; existing journal entries are left alone. Edit the `Language:` line in
  `openspec/config.yaml` yourself.
- An unknown code aborts `init` before it writes anything. At runtime a missing translation file or
  a broken string falls back to English per key.
- Add a language: copy `templates/i18n/en.json` to `<code>.json` and `templates/CLAUDE.en.md` to
  `CLAUDE.<code>.md`, translate, keep the `{placeholders}` (in the CLAUDE block: `{prompts}` and
  `{sessions}`, filled from the config's journal paths) and keep the example entry in
  `sessions_header` indented. Ships with `en` and `vi`.

---

## Keeping the three tools current

ZoeyMemory depends on OpenSpec and superpowers loosely, on purpose:

- The session hook reads `openspec/changes/*/tasks.md` from the **filesystem**, never the CLI. A CLI
  change cannot break session start; at worst the section says "no open changes".
- superpowers is referenced only **by skill name** in the CLAUDE.md block. A renamed skill makes a
  rule stale; nothing breaks.

| Upstream change | Effect on you | Caught by |
|---|---|---|
| New OpenSpec CLI | Generated `.claude/commands/opsx/*` in your repo are outdated | `update` runs `openspec update`; `doctor` checks the four commands exist |
| OpenSpec renames `/opsx:*` | CLAUDE.md block and context hint name old commands | `doctor` (missing commands) - then edit `templates/i18n/*.json` and `CLAUDE.<lang>.md` |
| superpowers renames a skill | CLAUDE.md block names a skill that no longer exists | `doctor` looks the install path up with `claude plugin list --json` and checks each skill |
| ZoeyMemory template changes | Your repo's CLAUDE.md block has the old wording | `doctor` diffs the block; `init` refreshes it |
| You change `journal.*` paths | The CLAUDE.md block still names the old paths | `doctor` diffs against the template rendered with your config; `init` refreshes it |

Routine: `/zoey-memory:update` on each machine now and then, `/zoey-memory:doctor` in each repo
after that. Auto-update is off by default for non-Anthropic marketplaces; enable it for
`zoey-memory` in `/plugin` if you prefer.

---

## Failure policy

- No config file: both hooks exit silently.
- Invalid config: no journaling, no sync, one warning line in the loaded context.
- Network slow or down: `FETCH_SLOW` / `FETCH_FAILED`, no pull attempted, hook returns in seconds.
- Pull fails or stalls: `PULL_FAILED` / `PULL_SLOW`, never misreported as a diverged branch.
- Dirty tree or unpushed commits: warned, never touched. The plugin never stashes, rebases, merges,
  deploys or pushes on its own; only `/zoey-memory:handoff` commits and pushes, and only if the
  config allows it.
- Bad translation: that string falls back to English. Crash while rendering: an English fallback
  that still carries the git warnings. A hook never blocks a session.
- Huge prompt: truncated to 600 characters, journaled anyway.

---

## Repository layout

```
.claude-plugin/marketplace.json     marketplace manifest (allows the cross-marketplace dependency)
setup.sh                            new machine: marketplaces + plugins + openspec CLI
tests/run.sh                        regression suite (41 checks, throwaway repos, no network)
plugins/zoey-memory/
  .claude-plugin/plugin.json        plugin manifest, declares superpowers as a dependency
  hooks/hooks.json                  SessionStart -> session-start.sh, UserPromptSubmit -> log-prompt.sh
  hooks/*.sh                        thin bash: git sync, then call into lib/
  lib/common.sh                     repo-root resolution, git detection, command watchdog
  lib/zoey.py                       the ONE place that knows the config schema, defaults, i18n, CLAUDE.md block
  lib/log_prompt.py                 journal writer (hook JSON on stdin)
  lib/session_start.py              context renderer
  scripts/init.sh                   enable in a repo
  scripts/doctor.sh                 offline health check
  scripts/update.sh                 update all three tools
  commands/*.md                     the five /zoey-memory:* commands
  templates/zoey-memory.json        config template with inline docs
  templates/CLAUDE.<lang>.md        the CLAUDE.md block per language
  templates/i18n/<lang>.json        runtime strings per language
```

Bash 3.2 (macOS default), BSD userland, Python 3.6+, no third-party packages.

---

## Developing and testing

```bash
git clone https://github.com/tuandda98/ZoeyMemory ~/ZoeyMemory
cd ~/ZoeyMemory
bash tests/run.sh                                  # ~1 minute, must end with failed=0
claude plugin validate . && claude plugin validate plugins/zoey-memory
```

Release: bump `version` in both `.claude-plugin/*.json`, commit, push. Machines pick it up with
`/zoey-memory:update` (or `claude plugin update zoey-memory@zoey-memory`).

Local marketplace while developing:

```bash
claude plugin marketplace add ~/ZoeyMemory         # local path instead of GitHub
claude plugin marketplace update zoey-memory       # after each commit
claude plugin update zoey-memory@zoey-memory       # reinstall the new version
```

Try the hooks by hand:

```bash
export CLAUDE_PROJECT_DIR=/path/to/test-repo
echo '{"hook_event_name":"UserPromptSubmit","prompt":"journal test"}' | bash plugins/zoey-memory/hooks/log-prompt.sh
echo '{"hook_event_name":"SessionStart","source":"startup"}' | bash plugins/zoey-memory/hooks/session-start.sh | python3 -m json.tool
bash plugins/zoey-memory/scripts/doctor.sh /path/to/test-repo
```

The test suite runs assertions in a child shell with inputs passed as environment variables, never
interpolated into code - rendered context contains backticks and `<name>` that must not be eval'd.

---

## FAQ

**Do I need to install OpenSpec and superpowers myself?**
No. superpowers is a declared dependency (installed with the plugin once its marketplace is
added); the OpenSpec CLI is installed by `/zoey-memory:init` or `setup.sh`.

**Do I enable it every session?**
No. Once per machine (install), once per repo (`init`). After that the hooks run on their own.

**What about my second machine?**
Install the plugin there. The repo's config and journals travel with git, so no `init` is needed.
Run `/zoey-memory:start` after switching to catch the things git does not carry.

**Can I use it without superpowers or without OpenSpec?**
Yes. Without OpenSpec the context just says it is not initialized; without superpowers the
CLAUDE.md block's quality rules have no skills to trigger. Both are degraded, not broken.

**Where do decisions go?**
`openspec/changes/<name>/proposal.md` and `design.md`, archived by date on `/opsx:archive`. A
decision that did not go through OpenSpec: a `> ` line under the prompt in `PROMPTS.md`.

**How do I brainstorm, design, implement?**
`/opsx:explore` to think, `/opsx:propose` to write it down, `/opsx:apply` to build (superpowers
handles tests and verification), `/opsx:archive` to close.

**Does the plugin ever push, merge or deploy?**
Never on its own. Only `/zoey-memory:handoff` commits and pushes, and only when the config allows.
Merging and deploying are always yours.

**Why the name?**
Zoey is the memory. The rest is other people's good work, wired together.

---

## License

MIT - see [LICENSE](LICENSE). OpenSpec and superpowers are separate projects under their own licenses.
