---
description: Enable ZoeyMemory in the current repo - openspec init, journals, CLAUDE.md workflow block, then commit
argument-hint: [extra notes, e.g. "working branch is dev", "no pushing"]
---
Enable **ZoeyMemory** (memory) + **OpenSpec** (specs) + **superpowers** (quality) in the open repo.
Do everything yourself; ask only when something genuinely cannot be inferred.

## 1. Run the init script (the mechanical part)

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/init.sh"
```

Read the output carefully: every `WARN` line is unfinished work you must handle or report. The
script is idempotent and never overwrites what exists.

## 2. Fill `.claude/zoey-memory.json` from the actual repo (read the disk, do not guess)

- `git.workingBranch` - the real working branch (`git branch --show-current`, remote HEAD).
- `git.allowCommit` / `git.allowPush` - per the user's notes; default is allowed.
- `outsideGit.items` - scan for `.env*`, `supabase/migrations`, `prisma/`, docker, ssh... Keep only items that exist.
- `forbidden.items` - things specific to this repo (e.g. "never run `vercel --prod`").

## 3. Check CLAUDE.md

The `<!-- zoey-memory:start -->...<!-- zoey-memory:end -->` block just added must **not contradict**
existing rules in CLAUDE.md / AGENTS.md. If the repo already has another spec process
(docs/superpowers, a `project/` folder...), state which one wins - default is OpenSpec, and say so.

## 4. Check that OpenSpec is wired into Claude Code

`ls .claude/commands .claude/skills 2>/dev/null | grep -i opsx` must show `opsx-*` commands. If not,
run `openspec init --tools claude --language en` by hand and read the error.

## 5. Commit

Commit everything: `openspec/`, `.claude/zoey-memory.json`, `.claude/commands/` and `.claude/skills/`
(created by openspec), `docs/memory/`, `CLAUDE.md`, `.gitignore`. Message: `Enable ZoeyMemory + OpenSpec`.
This toolkit travels with git - that is how the other machine gets it. Do not push if `git.allowPush` is false.

## 6. Report briefly

- Which files were created, whether superpowers is installed (if not: give the two install commands).
- Hooks only load at session start -> **the current session is not journaling yet**; run
  `/reload-plugins` or open a new session.
- First thing to do next: `/opsx:propose <name>` for the work you are about to start.

**Extra notes from the user:** $ARGUMENTS
