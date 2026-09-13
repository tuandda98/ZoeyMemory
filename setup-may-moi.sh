#!/usr/bin/env bash
# Máy mới: cài đủ ba bộ — superpowers + kyuc + openspec CLI. Chạy lại không sao.
#
# Dùng: bash setup-may-moi.sh [nguồn marketplace kyuc]
#   nguồn mặc định: tuandda98/claude-kyuc (GitHub). Chưa push thì truyền đường dẫn local, vd:
#   bash setup-may-moi.sh ~/claude-kyuc
set -uo pipefail

KYUC_SRC="${1:-tuandda98/claude-kyuc}"

command -v claude >/dev/null 2>&1 || { echo "✗ chưa có Claude Code CLI"; exit 1; }

echo "# 1/3 superpowers"
claude plugin marketplace add obra/superpowers-marketplace 2>&1 | tail -1
claude plugin install superpowers@superpowers-marketplace 2>&1 | tail -1

echo "# 2/3 kyuc ($KYUC_SRC)"
claude plugin marketplace add "$KYUC_SRC" 2>&1 | tail -1
claude plugin install kyuc@claude-kyuc 2>&1 | tail -1

echo "# 3/3 openspec CLI"
if command -v openspec >/dev/null 2>&1; then
  echo "✓ đã có openspec $(openspec --version)"
elif command -v npm >/dev/null 2>&1; then
  npm i -g @fission-ai/openspec@latest >/dev/null 2>&1 && echo "✓ openspec $(openspec --version)" || echo "⚠ cài openspec lỗi — cần Node 20.19+"
else
  echo "⚠ thiếu npm — cài Node 20.19+ rồi: npm i -g @fission-ai/openspec@latest"
fi

echo
claude plugin list 2>/dev/null | grep -E "superpowers@|kyuc@" -A3
echo
echo "Xong. Vào repo, gõ /kyuc:khoi-tao để bật."
