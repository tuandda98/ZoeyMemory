---
description: Mở máy — đồng bộ code/phụ thuộc/thứ ngoài git, tóm tắt máy kia đã làm gì và change OpenSpec đang mở
---
Chủ dự án vừa mở máy (có thể là **máy còn lại**). Làm đủ các bước, **tự chạy hết, đừng hỏi từng
bước**, rồi báo cáo gọn.

> Hook `dau-phien.sh` đã tự fetch/pull và nạp ngữ cảnh ở đầu phiên. Lệnh này là bản KỸ hơn: nó
> kiểm cả những thứ **không đi theo git** — thứ hook không thể tự biết.

1. **Code:** `git fetch --all --prune && git status -sb`. Đang ở nhánh sai so với
   `git.nhanhLamViec` trong `.claude/kyuc.json` thì chuyển về đúng nhánh rồi `git pull`.
2. **Phụ thuộc:** lockfile đổi so với lần cài gần nhất → cài lại (`npm install` / `pub get` /
   `uv sync`… theo stack).
3. **Máy kia đã làm gì:** đọc `git log --oneline -10` + đuôi nhật ký câu hỏi (`nhatky.cauHoi`) +
   mục mới nhất nhật ký phiên (`nhatky.phien`) rồi **tóm tắt**. Bạn KHÔNG có ký ức về phiên ở
   máy đó — ba nguồn này là toàn bộ những gì còn lại.
4. **Việc đang dở:** `openspec list` (hoặc đọc `openspec/changes/*/tasks.md`) — change nào mở,
   bao nhiêu task xong, task kế tiếp là gì.
5. **Thứ KHÔNG đi theo git** — kiểm từng mục trong `ngoaiGit.muc` của `.claude/kyuc.json`:
   env/secret có chưa, đang trỏ DB nào, migration đã áp chưa, khoá/ssh. Thiếu thì **nhắc chuyển
   tay từ máy kia**, đừng cố dựng lại từ đầu.

Báo cáo: máy kia đã làm gì · change đang mở + task kế tiếp · **có gì lệch cần xử lý trước khi
làm tiếp**.
