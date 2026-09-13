---
description: Đóng máy — ghi nhật ký phiên (đang dở tới đâu, vì sao dừng), commit và push để máy kia làm tiếp
---
Chủ dự án sắp rời máy. **Code dở nằm trên ổ cứng một máy = ca sau làm lại từ đầu.** Làm đủ, tự
chạy hết:

1. `git status --porcelain` — còn gì chưa commit, kể cả file rác cần dọn.
2. **Cập nhật tiến độ OpenSpec:** change đang làm → tick `- [x]` các task đã xong trong
   `openspec/changes/<tên>/tasks.md`. Xong hết task và đã verify → nhắc chủ dự án
   `/opsx:archive <tên>` (đừng tự archive).
3. **Ghi nhật ký phiên** (`nhatky.phien` trong `.claude/kyuc.json`, mặc định
   `docs/nhatky/PHIEN.md`) — thêm MỘT mục mới ở cuối, đúng khuôn trong file:
   - Đang dở: change nào, task nào, file nào đang sửa nửa chừng.
   - Vì sao dừng: hết giờ / kẹt gì / chờ gì.
   - Chờ ai quyết gì: câu hỏi mở cần chủ dự án trả lời.
   - Máy kia cần biết: giá trị env mới, secret vừa tạo, migration mới, thay đổi trên máy chủ.
   Đừng chép lại `git log` — commit trả lời "đã đổi gì", mục này trả lời "vì sao, tiếp theo là gì".
   Phiên chỉ sửa lặt vặt, không có gì dở → một dòng "Không có gì dở" là đủ.
4. **Commit kể cả việc còn dở** — message ghi rõ đang làm gì và còn thiếu gì
   (`WIP: <đang làm> — còn thiếu <…>`). Tôn trọng `git.choCommit` trong kyuc.json.
5. `git push` (nếu `git.choPush`) — không push thì mọi bước trên vô nghĩa với máy kia.
6. **Nhắc thứ KHÔNG đi theo git** theo `ngoaiGit.muc` mà máy kia sẽ thiếu.

⚠️ Tuyệt đối **không merge sang nhánh chính và không deploy production** ở bước này, trừ khi chủ
dự án đã nói rõ. Tôn trọng `camKy.muc`.

Báo cáo: đã commit gì · còn dở gì · máy kia cần biết gì trước khi tiếp tục.
