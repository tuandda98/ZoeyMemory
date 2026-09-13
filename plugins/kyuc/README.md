# kyuc — ký ức giữa các phiên và giữa hai máy

Plugin này giải đúng một vấn đề: **ký ức của Claude không đi theo phiên, cũng không đi theo
máy.** Nó không làm spec, không làm TDD — hai việc đó giao cho OpenSpec và superpowers.

| Việc | Ai lo | Dùng gì |
|---|---|---|
| Ký ức: câu đã hỏi, đang dở tới đâu, máy kia làm gì | **kyuc** (plugin này) | 2 hook + 3 lệnh |
| Spec, thiết kế, lý do quyết định, lịch sử theo ngày | **OpenSpec** | `/opsx:explore` `propose` `apply` `archive` |
| TDD, debug có hệ thống, verify trước khi báo xong, code review | **superpowers** | skill tự bật |

## Có gì

**2 hook tự chạy** (im lặng thoát nếu repo không có `.claude/kyuc.json`):

| Hook | Khi nào | Làm gì |
|---|---|---|
| `ghi-nhat-ky.sh` | mở phiên + **mỗi câu bạn nhắn** | Ghi vào `docs/nhatky/CAU_HOI.md` (được commit → máy kia đọc được) |
| `dau-phien.sh` | mở phiên | `git fetch` → tự `pull --ff-only` nếu an toàn → **nạp vào context**: 30 câu vừa nhờ · mục mới nhất nhật ký phiên · change OpenSpec đang mở + tiến độ task · git log |

**3 lệnh** (`/kyuc:<tên>`):

| Lệnh | Việc |
|---|---|
| `/kyuc:khoi-tao` | **Bật cho một repo** — openspec init, `.claude/kyuc.json`, `docs/nhatky/`, khối phân vai trong CLAUDE.md, commit |
| `/kyuc:dau-ca` | Mở máy: đồng bộ code + phụ thuộc + thứ ngoài git, tóm tắt máy kia đã làm gì |
| `/kyuc:cuoi-ca` | Rời máy: tick task OpenSpec, ghi nhật ký phiên, commit WIP, push |

## Bốn loại nhật ký, đừng gộp

| File | Trả lời | Ai ghi |
|---|---|---|
| `docs/nhatky/CAU_HOI.md` | *chủ dự án đã nhờ gì, theo thứ tự nào* | hook, tự động |
| `docs/nhatky/PHIEN.md` | *đang dở tới đâu, vì sao dừng, chờ ai quyết* | Claude, `/kyuc:cuoi-ca` |
| `openspec/changes/<tên>/` và `archive/` | *làm gì, tại sao, đã làm chưa* | OpenSpec |
| `git log` | *đã đổi những dòng code nào* | commit |

## Bật cho một repo

```
/kyuc:khoi-tao
```

Hoặc chạy tay phần máy móc: `bash <plugin>/scripts/khoi-tao.sh [đường dẫn repo]`.

## Cấu hình `.claude/kyuc.json`

Mẫu đầy đủ kèm chú thích: [`mau/kyuc.json`](mau/kyuc.json). Tóm tắt:

- `nhatky.cauHoi` / `nhatky.phien` — đường dẫn hai nhật ký. `nhatky.bat=false` tắt ghi tự động.
- `ngucanh.bat` / `ngucanh.soCau` — có nạp ngữ cảnh đầu phiên không, bao nhiêu câu.
- `git.tuPull` / `choCommit` / `choPush` / `nhanhLamViec`.
- `ngoaiGit.muc` — thứ không đi theo git, `/kyuc:dau-ca` kiểm riêng.
- `camKy.muc` — việc Claude tuyệt đối không tự làm.
