---
description: Health check - detect drift between ZoeyMemory, OpenSpec and superpowers after any of them was updated, and fix what is safe
---
Run the read-only, offline health check and act on it:

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/doctor.sh"
```

For every `WARN` line:

- **Safe to fix yourself, do it now:** regenerate OpenSpec files (`openspec update .`), refresh the
  CLAUDE.md block (`bash "${CLAUDE_PLUGIN_ROOT}/scripts/init.sh"`), fix the `Language:` line in
  `openspec/config.yaml`, create missing journal files (`init.sh` does that too). Re-run the doctor
  afterwards and show the before/after.
- **Needs the user:** installing or enabling plugins, setting a git upstream, disabling the old
  `flow` plugin, un-ignoring files. Give the exact command and stop.
- **Skill renamed upstream** (superpowers no longer has a skill the CLAUDE.md block mentions): look
  at what replaced it in `~/.claude/plugins/cache/superpowers-marketplace/superpowers/<version>/skills/`,
  propose the edit to `templates/CLAUDE.<lang>.md` and the list in `doctor.sh` inside the ZoeyMemory
  repo, but do not edit the plugin source without the user's approval.

Language: write the report in the `language` set in `.claude/zoey-memory.json`.

Report: what was healthy, what you fixed, what still needs the user.
