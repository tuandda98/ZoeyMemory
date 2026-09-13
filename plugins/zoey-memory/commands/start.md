---
description: Start of day - sync code, dependencies and things outside git, summarize what the other machine did and which OpenSpec changes are open
---
The user just opened a machine (possibly **the other one**). Do every step, **run everything
yourself without asking step by step**, then report briefly.

> The `session-start.sh` hook already fetched/pulled and loaded context at session start. This
> command is the THOROUGH version: it also checks things that **do not travel with git**, which
> the hook cannot know about.

1. **Code:** `git fetch --all --prune && git status -sb`. If on the wrong branch compared to
   `git.workingBranch` in `.claude/zoey-memory.json`, switch to the right one, then `git pull`.
2. **Dependencies:** lockfile changed since the last install -> reinstall (`npm install` /
   `pub get` / `uv sync`... per stack).
3. **What the other machine did:** read `git log --oneline -10` + the tail of the prompt journal
   (`journal.prompts`) + the latest entry of the session journal (`journal.sessions`), then
   **summarize**. You have NO memory of the session on that machine - these three sources are
   everything that is left.
4. **Work in progress:** `openspec list` (or read `openspec/changes/*/tasks.md`) - which changes are
   open, how many tasks are done, what the next task is.
5. **Things that do NOT travel with git** - check every item in `outsideGit.items` of
   `.claude/zoey-memory.json`: env/secrets present, which DB it points at, migrations applied,
   keys/ssh. If missing, **ask for a manual transfer from the other machine**; do not try to
   rebuild from scratch.

Report: what the other machine did - open changes + next task - **anything out of sync that must
be handled before continuing**.
