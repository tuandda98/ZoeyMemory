#!/usr/bin/env bash
# New machine: install superpowers + ponytail + ZoeyMemory + openspec CLI + agent-skills. Safe to re-run.
#
# Usage: bash setup.sh [ZoeyMemory marketplace source]
#   default source: tuandda98/ZoeyMemory (GitHub). Not pushed yet? Pass a local path, e.g.:
#   bash setup.sh ~/ZoeyMemory
set -uo pipefail

ZOEY_SRC="${1:-tuandda98/ZoeyMemory}"

command -v claude >/dev/null 2>&1 || { echo "ERROR: Claude Code CLI not found"; exit 1; }

echo "# 1/5 superpowers"
claude plugin marketplace add obra/superpowers-marketplace 2>&1 | tail -1
claude plugin install superpowers@superpowers-marketplace 2>&1 | tail -1

echo "# 2/5 ponytail"
claude plugin marketplace add DietrichGebert/ponytail 2>&1 | tail -1
claude plugin install ponytail@ponytail 2>&1 | tail -1

echo "# 3/5 ZoeyMemory ($ZOEY_SRC)"
claude plugin marketplace add "$ZOEY_SRC" 2>&1 | tail -1
claude plugin install zoey-memory@zoey-memory 2>&1 | tail -1

echo "# 4/5 openspec CLI"
if command -v openspec >/dev/null 2>&1; then
  echo "OK    openspec $(openspec --version) already installed"
elif command -v npm >/dev/null 2>&1; then
  npm i -g @fission-ai/openspec@latest >/dev/null 2>&1 && echo "OK    openspec $(openspec --version)" || echo "WARN  openspec install failed - needs Node 20.19+"
else
  echo "WARN  npm missing - install Node 20.19+ then: npm i -g @fission-ai/openspec@latest"
fi

echo "# 5/5 agent-skills (addyosmani/agent-skills: the six skills the CLAUDE.md tree routes to)"
if command -v npx >/dev/null 2>&1; then
  sk=""; for s in frontend-ui-engineering api-and-interface-design security-and-hardening performance-optimization shipping-and-launch interview-me; do sk="$sk -s $s"; done
  (cd "${TMPDIR:-/tmp}" && npx -y skills add addyosmani/agent-skills -g -a claude-code --copy -y $sk >/dev/null 2>&1) \
    && echo "OK    agent-skills installed to ~/.claude/skills" || echo "WARN  agent-skills install failed"
  # The skills link to ../../references/*.md (shared checklists) - put them where those links resolve.
  mkdir -p "$HOME/.claude/references"
  for f in accessibility-checklist security-checklist performance-checklist definition-of-done; do
    curl -fsSL "https://raw.githubusercontent.com/addyosmani/agent-skills/main/references/$f.md" -o "$HOME/.claude/references/$f.md" || echo "WARN  could not fetch references/$f.md"
  done
else
  echo "WARN  npx missing - skipping agent-skills (install Node, then re-run)"
fi

echo
claude plugin list 2>/dev/null | grep -E "superpowers@|ponytail@|zoey-memory@" -A3
echo
echo "Done. Open a repo and run /zoey-memory:init to enable it there."
