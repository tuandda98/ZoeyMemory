<!-- zoey-memory:start -->
# Quy trình làm việc (ZoeyMemory + OpenSpec + superpowers + ponytail)

Bốn bộ, mỗi bộ một việc, không chồng nhau:

| Việc | Bộ | Dùng thế nào |
|---|---|---|
| Ký ức giữa các phiên, giữa 2 máy | **ZoeyMemory** | Hook tự ghi từng câu hỏi vào `{prompts}` và tự nạp ngữ cảnh đầu phiên. Đổi máy: `/zoey-memory:start`. Rời máy: `/zoey-memory:handoff` (ghi nhật ký phiên vào `{sessions}`). Kiểm tra sức khoẻ: `/zoey-memory:doctor`. |
| Spec, thiết kế, lý do quyết định | **OpenSpec** | Việc mới đáng nhớ: `/opsx:explore` -> `/opsx:propose <tên>` -> `/opsx:apply` -> `/opsx:archive`. Mọi "tại sao" nằm ở `openspec/changes/<tên>/proposal.md` và `design.md`; lịch sử ở `openspec/changes/archive/`. |
| Chất lượng code | **superpowers** | Implement: `test-driven-development`. Gặp bug: `systematic-debugging`. Trước khi báo xong: `verification-before-completion`. Xong feature: `requesting-code-review`. |
| Thực thi (`/opsx:apply`) | **ponytail** | Trước khi viết code cho mỗi task trong `tasks.md`, chạy skill `ponytail` và dừng ở bậc đầu tiên đứng được: không cần -> đã có trong codebase -> stdlib -> tính năng sẵn của nền tảng -> dependency đã cài -> một dòng -> cuối cùng mới viết bản tối thiểu chạy được. Không bao giờ bỏ validation, xử lý lỗi, bảo mật hay accessibility. Chạy cùng TDD, không thay TDD. |

Chọn skill (xem cây này ở MỖI câu, gọi skill TRƯỚC khi trả lời; khớp nhiều nhánh thì gọi đủ):
```
Ý tưởng mơ hồ, chưa rõ cho ai/vì sao  -> interview-me, rồi /opsx:explore
Ý tưởng/tính năng mới đáng nhớ        -> /opsx:explore -> /opsx:propose <tên>
Thực thi change đã có                 -> /opsx:apply <tên> + ponytail + test-driven-development
  UI, trang, component               -> + frontend-ui-engineering
  API, endpoint, ranh giới module    -> + api-and-interface-design
  input người dùng, auth, dữ liệu    -> + security-and-hardening
Lỗi, test hỏng, chạy sai              -> systematic-debugging
Chậm, Core Web Vitals, N+1            -> performance-optimization
Sắp báo "xong"                        -> verification-before-completion
Xong feature, trước merge             -> requesting-code-review
Chuẩn bị lên production               -> shipping-and-launch (deploy vẫn phải hỏi, xem `forbidden`)
Việc khác                             -> xem danh sách skill hệ thống đưa, skill nào mô tả khớp thì gọi
```

Luật ranh giới:
- KHÔNG dùng `superpowers:brainstorming`, `writing-plans`, `executing-plans` - phần đó OpenSpec đã lo. Cần bàn ý tưởng thì `/opsx:explore`.
- Sửa lặt vặt một file, không cần nhớ lý do: làm thẳng, vẫn TDD + verify, không cần propose.
- Quyết định đáng nhớ mà không đi qua OpenSpec: ghi một dòng `> ` dưới câu hỏi tương ứng trong `{prompts}`.
- Việc cấm và thứ không đi theo git: xem `.claude/zoey-memory.json` (`forbidden`, `outsideGit`).
- Ngôn ngữ: viết nhật ký phiên, tóm tắt và báo cáo bằng ngôn ngữ đặt ở `language` trong `.claude/zoey-memory.json`.
<!-- zoey-memory:end -->
