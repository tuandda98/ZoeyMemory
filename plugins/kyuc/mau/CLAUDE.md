<!-- kyuc:start -->
# Quy trình làm việc (bộ kyuc + OpenSpec + superpowers)

Ba bộ, mỗi bộ một việc, không chồng nhau:

| Việc | Bộ | Dùng thế nào |
|---|---|---|
| Ký ức giữa các phiên, giữa 2 máy | **kyuc** | Hook tự ghi từng câu hỏi vào `docs/nhatky/CAU_HOI.md` và tự nạp ngữ cảnh đầu phiên. Mở máy khác: `/kyuc:dau-ca`. Rời máy: `/kyuc:cuoi-ca`. |
| Spec, thiết kế, lý do quyết định | **OpenSpec** | Việc mới đáng nhớ: `/opsx:explore` → `/opsx:propose <tên>` → `/opsx:apply` → `/opsx:archive`. Mọi "tại sao" nằm ở `openspec/changes/<tên>/proposal.md` và `design.md`; lịch sử ở `openspec/changes/archive/`. |
| Chất lượng code | **superpowers** | Implement: `test-driven-development`. Gặp bug: `systematic-debugging`. Trước khi báo xong: `verification-before-completion`. Xong feature: `requesting-code-review`. |

Luật ranh giới:
- KHÔNG dùng `superpowers:brainstorming`, `writing-plans`, `executing-plans` — phần đó OpenSpec đã lo. Cần bàn ý tưởng thì `/opsx:explore`.
- Sửa lặt vặt một file, không cần nhớ lý do: làm thẳng, vẫn TDD + verify, không cần propose.
- Quyết định nào đáng nhớ mà không đi qua OpenSpec thì ghi một dòng `> ` dưới câu hỏi tương ứng trong `docs/nhatky/CAU_HOI.md`.
- Việc cấm và thứ không đi theo git: xem `.claude/kyuc.json` (`camKy`, `ngoaiGit`).
<!-- kyuc:end -->
