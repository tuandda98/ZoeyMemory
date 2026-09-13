---
description: End of day - write the session note (what is in progress, why we stopped), commit and push so the other machine can continue
---
The user is about to leave this machine. **Unfinished code sitting on one machine's disk = the next
session starts over.** Do everything, run it all yourself:

1. `git status --porcelain` - anything uncommitted, including junk files to clean up.
2. **Update OpenSpec progress:** for the change in progress, tick `- [x]` on the tasks that are done
   in `openspec/changes/<name>/tasks.md`. If every task is done and verified, remind the user to run
   `/opsx:archive <name>` (do not archive on your own).
3. **Write the session note** (`journal.sessions` in `.claude/zoey-memory.json`, default
   `docs/memory/SESSIONS.md`) - append ONE new entry at the end, using the shape in the file:
   - In progress: which change, which task, which file is half-edited.
   - Why we stopped: out of time / blocked on what / waiting for what.
   - Waiting on whom for what: open questions the user must answer.
   - The other machine needs to know: new env values, secrets just created, new migrations, server changes.
   Do not repeat `git log` - commits answer "what changed", this entry answers "why, and what comes next".
   A session with only trivial edits and nothing in progress -> one line "Nothing in progress" is enough.
4. **Commit even unfinished work** - the message must say what is being done and what is missing
   (`WIP: <doing> - missing <...>`). Respect `git.allowCommit` in the config.
5. `git push` (if `git.allowPush`) - without a push every step above is worthless to the other machine.
6. **Remind about things that do NOT travel with git** per `outsideGit.items` that the other machine will be missing.

WARNING: **never merge into the main branch and never deploy to production** in this step unless the
user explicitly said so. Respect `forbidden.items`.

Report: what was committed - what is still in progress - what the other machine needs to know before continuing.
