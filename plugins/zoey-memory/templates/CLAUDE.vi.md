<!-- zoey-memory:start -->
# Quy trình làm việc (ZoeyMemory + OpenSpec + superpowers)

Ba bộ, mỗi bộ một việc, không chồng nhau:

| Việc | Bộ | Dùng thế nào |
|---|---|---|
| Ký ức giữa các phiên, giữa 2 máy | **ZoeyMemory** | Hook tự ghi từng câu hỏi vào `docs/memory/PROMPTS.md` và tự nạp ngữ cảnh đầu phiên. Đổi máy: `/zoey-memory:start`. Rời máy: `/zoey-memory:handoff`. Kiểm tra sức khoẻ: `/zoey-memory:doctor`. |
| Spec, thiết kế, lý do quyết định | **OpenSpec** | Việc mới đáng nhớ: `/opsx:explore` -> `/opsx:propose <tên>` -> `/opsx:apply` -> `/opsx:archive`. Mọi "tại sao" nằm ở `openspec/changes/<tên>/proposal.md` và `design.md`; lịch sử ở `openspec/changes/archive/`. |
| Chất lượng code | **superpowers** | Implement: `test-driven-development`. Gặp bug: `systematic-debugging`. Trước khi báo xong: `verification-before-completion`. Xong feature: `requesting-code-review`. |

Luật ranh giới:
- KHÔNG dùng `superpowers:brainstorming`, `writing-plans`, `executing-plans` - phần đó OpenSpec đã lo. Cần bàn ý tưởng thì `/opsx:explore`.
- Sửa lặt vặt một file, không cần nhớ lý do: làm thẳng, vẫn TDD + verify, không cần propose.
- Quyết định đáng nhớ mà không đi qua OpenSpec: ghi một dòng `> ` dưới câu hỏi tương ứng trong `docs/memory/PROMPTS.md`.
- Việc cấm và thứ không đi theo git: xem `.claude/zoey-memory.json` (`forbidden`, `outsideGit`).
- Ngôn ngữ: viết nhật ký phiên, tóm tắt và báo cáo bằng ngôn ngữ đặt ở `language` trong `.claude/zoey-memory.json`.
<!-- zoey-memory:end -->
