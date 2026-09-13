---
description: Enable ZoeyMemory in the current repo - openspec init, journals, CLAUDE.md workflow block, then commit
argument-hint: [language code and/or notes, e.g. "vi", "language vi, working branch is dev", "no pushing"]
---
Enable **ZoeyMemory** (memory) + **OpenSpec** (specs) + **superpowers** (quality) in the open repo.
Do everything yourself; ask only when something genuinely cannot be inferred.

## 1. Run the init script (the mechanical part)

If the user's notes name a language (`vi`, `language vi`, "Vietnamese"...), pass it; otherwise omit
the flag (default `en`, or whatever the existing config says):

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/init.sh" [--language <code>]
```

Read the output carefully: every `WARN` line is unfinished work you must handle or report. The
script is idempotent: it never overwrites user files, and it refreshes only the plugin-owned block
between the `<!-- zoey-memory:start/end -->` markers in CLAUDE.md.

## 2. Fill `.claude/zoey-memory.json` from the actual repo (read the disk, do not guess)

- `git.workingBranch` - the real working branch (`git branch --show-current`, remote HEAD).
- `git.allowCommit` / `git.allowPush` - per the user's notes; default is allowed.
- `outsideGit.items` - scan for `.env*`, `supabase/migrations`, `prisma/`, docker, ssh... Keep only items that exist.
- `forbidden.items` - things specific to this repo (e.g. "never run `vercel --prod`").
- `language` - leave as set by the script.

## 3. Check CLAUDE.md

The `<!-- zoey-memory:start -->...<!-- zoey-memory:end -->` block must **not contradict** existing
rules in CLAUDE.md / AGENTS.md. If the repo already has another spec process (docs/superpowers, a
`project/` folder from the old `flow` plugin...), state which one wins - default is OpenSpec, and say so.

## 4. Check that OpenSpec is wired into Claude Code

`ls .claude/commands/opsx` must show `explore.md propose.md apply.md archive.md`. If not, run
`openspec init --tools claude --language <code>` by hand and read the error.

## 5. Commit

Commit everything: `openspec/`, `.claude/zoey-memory.json`, `.claude/commands/` and `.claude/skills/`
(created by openspec), `docs/memory/`, `CLAUDE.md`, `.gitignore`. Message: `Enable ZoeyMemory + OpenSpec`.
This toolkit travels with git - that is how the other machine gets it. Do not push if `git.allowPush` is false.

## 6. Report briefly

- Which files were created, the language, whether superpowers is installed (if not: give the two install commands).
- Hooks only load at session start -> **the current session is not journaling yet**; run
  `/reload-plugins` or open a new session.
- First thing to do next: `/opsx:propose <name>` for the work you are about to start.

Language: write the report in the language just configured.

**Extra notes from the user:** $ARGUMENTS
