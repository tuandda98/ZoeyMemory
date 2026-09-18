<!-- zoey-memory:start -->
# Workflow (ZoeyMemory + OpenSpec + superpowers + ponytail)

Four tools, one job each, no overlap:

| Job | Tool | How |
|---|---|---|
| Memory across sessions and machines | **ZoeyMemory** | Hooks log every prompt to `{prompts}` and load context at session start. Switching machines: `/zoey-memory:start`. Leaving: `/zoey-memory:handoff` (session note in `{sessions}`). Health check: `/zoey-memory:doctor`. |
| Specs, design, reasoning behind decisions | **OpenSpec** | New work worth remembering: `/opsx:explore` -> `/opsx:propose <name>` -> `/opsx:apply` -> `/opsx:archive`. Every "why" lives in `openspec/changes/<name>/proposal.md` and `design.md`; history in `openspec/changes/archive/`. |
| Code quality | **superpowers** | Implementing: `test-driven-development`. Hitting a bug: `systematic-debugging`. Before claiming done: `verification-before-completion`. Feature complete: `requesting-code-review`. |
| Executing (`/opsx:apply`) | **ponytail** | Before writing code for each task in `tasks.md`, run the `ponytail` skill and stop at the first rung that holds: not needed -> already in the codebase -> stdlib -> native platform -> installed dependency -> one line -> only then the minimum that works. Never cut validation, error handling, security or accessibility. Runs together with TDD, it does not replace it. |

Boundaries:
- Do NOT use `superpowers:brainstorming`, `writing-plans`, or `executing-plans` - OpenSpec owns that. To discuss an idea, use `/opsx:explore`.
- Small single-file fixes with no reasoning worth keeping: just do them, still with TDD + verification, no proposal needed.
- A decision worth remembering that did not go through OpenSpec: add a `> ` line under the matching prompt in `{prompts}`.
- Forbidden actions and things outside git: see `.claude/zoey-memory.json` (`forbidden`, `outsideGit`).
- Language: write session notes, summaries and reports in the `language` set in `.claude/zoey-memory.json`.
<!-- zoey-memory:end -->
