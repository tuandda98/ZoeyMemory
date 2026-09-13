---
description: Update superpowers, ZoeyMemory and the openspec CLI on this machine, regenerate this repo's OpenSpec files, then run the doctor
---
Run the updater, then the health check:

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/update.sh"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/doctor.sh"
```

Then:

1. If `openspec update` changed files under `.claude/commands/` or `.claude/skills/`, show `git diff --stat`
   and commit them (`Update OpenSpec generated files`) if `git.allowCommit` in `.claude/zoey-memory.json` allows it.
2. Handle every doctor `WARN` the way `/zoey-memory:doctor` describes.
3. Remind the user that plugin updates only apply after a restart or `/reload-plugins`.

Language: write the report in the `language` set in `.claude/zoey-memory.json`.

Report: versions before/after, files regenerated, warnings left.
