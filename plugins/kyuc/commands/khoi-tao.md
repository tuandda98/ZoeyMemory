---
description: Bật bộ kyuc cho repo hiện tại — openspec init, nhật ký, khối CLAUDE.md phân vai, rồi commit
argument-hint: [ghi chú thêm, vd "nhánh làm việc là dev", "không cho push"]
---
Bật **bộ `kyuc`** (ký ức) + **OpenSpec** (spec) + **superpowers** (chất lượng) cho repo đang mở.
Tự làm hết, chỉ hỏi khi thật sự không suy ra được.

## 1. Chạy script khởi tạo (phần máy móc)

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/khoi-tao.sh"
```

Đọc kỹ output: dòng `⚠` là việc chưa xong, phải xử lý hoặc báo lại. Script idempotent, không
ghi đè thứ đã có.

## 2. Điền `.claude/kyuc.json` theo thực tế repo (đọc đĩa, đừng đoán)

- `git.nhanhLamViec` — nhánh làm việc thật (`git branch --show-current`, remote HEAD).
- `git.choCommit` / `git.choPush` — theo ghi chú của chủ dự án; mặc định cho phép.
- `ngoaiGit.muc` — dò `.env*`, `supabase/migrations`, `prisma/`, docker, ssh… Chỉ giữ mục có thật.
- `camKy.muc` — thứ cụ thể của repo này (vd "không chạy `vercel --prod`").

## 3. Kiểm CLAUDE.md

Khối `<!-- kyuc:start -->…<!-- kyuc:end -->` vừa thêm phải **không mâu thuẫn** với luật sẵn có
trong CLAUDE.md / AGENTS.md. Nếu repo đã có quy trình spec khác (docs/superpowers, project/ của
flow…), ghi rõ cái nào thắng — mặc định OpenSpec thắng, và nói điều đó.

## 4. Kiểm OpenSpec đã nối với Claude Code chưa

`ls .claude/commands .claude/skills 2>/dev/null | grep -i opsx` phải thấy lệnh `opsx-*`. Không
thấy thì chạy tay `openspec init --tools claude --language vi` rồi xem lỗi.

## 5. Commit

Commit tất cả: `openspec/`, `.claude/kyuc.json`, `.claude/commands/` hoặc `.claude/skills/`
(do openspec tạo), `docs/nhatky/`, `CLAUDE.md`, `.gitignore`. Message: `Bật kyuc + OpenSpec`.
Bộ này đi theo git — đó là cách máy kia có nó. Không push nếu `git.choPush` là false.

## 6. Báo lại gọn

- Đã tạo file nào, superpowers đã cài chưa (nếu chưa: đưa đúng 2 lệnh cài).
- ⚠️ Hook chỉ nạp lúc mở phiên → **phiên hiện tại chưa ghi nhật ký**; gõ `/reload-plugins`
  hoặc mở phiên mới.
- Việc đầu tiên nên làm: `/opsx:propose <tên>` cho việc đang định làm.

**Ghi chú thêm từ chủ dự án:** $ARGUMENTS
