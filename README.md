# claude-kyuc — bộ làm việc với Claude Code, dùng chung cho mọi dự án

Ba bộ ghép lại, mỗi bộ một việc, không chồng nhau:

| Việc | Bộ | Nguồn |
|---|---|---|
| Ký ức giữa các phiên, giữa 2 máy | **kyuc** (plugin trong repo này) | `plugins/kyuc/` |
| Spec, thiết kế, lý do quyết định, lịch sử | **OpenSpec** | [Fission-AI/openspec](https://github.com/Fission-AI/openspec) |
| TDD, debug, verify, code review | **superpowers** | [obra/superpowers](https://github.com/obra/superpowers) |

Chi tiết plugin kyuc: [`plugins/kyuc/README.md`](plugins/kyuc/README.md).

## Cài (mỗi máy một lần)

```bash
bash setup-may-moi.sh
```

Script cài cả ba: marketplace + plugin superpowers, marketplace + plugin kyuc, và openspec CLI
(cần Node 20.19+). Chạy lại không sao.

Cài tay:

```bash
claude plugin marketplace add obra/superpowers-marketplace
claude plugin install superpowers@superpowers-marketplace
claude plugin marketplace add tuandda98/claude-kyuc      # hoặc đường dẫn local tới repo này
claude plugin install kyuc@claude-kyuc
npm i -g @fission-ai/openspec@latest
```

## Bật cho một repo (mỗi repo một lần)

Mở Claude Code trong repo, gõ:

```
/kyuc:khoi-tao
```

Nó chạy `openspec init`, tạo `.claude/kyuc.json`, `docs/nhatky/`, thêm khối phân vai vào
`CLAUDE.md`, rồi commit. Từ phiên sau hook bắt đầu ghi nhật ký và nạp ngữ cảnh.

## Một ngày làm việc

1. Mở máy → hook tự pull + nạp ngữ cảnh. Đổi máy thì gõ thêm `/kyuc:dau-ca`.
2. Việc mới đáng nhớ → `/opsx:propose <tên>` → `/opsx:apply` (superpowers TDD/verify tự bật).
3. Xong → `/opsx:archive <tên>`.
4. Rời máy → `/kyuc:cuoi-ca`.

## Phát triển plugin này

Sửa file trong `plugins/kyuc/`, rồi:

```bash
claude plugin marketplace update claude-kyuc
claude plugin install kyuc@claude-kyuc      # cài lại bản mới
```

Thử hook không cần mở Claude:

```bash
export CLAUDE_PROJECT_DIR=/đường/dẫn/repo-test
echo '{"hook_event_name":"UserPromptSubmit","prompt":"thử ghi nhật ký"}' | bash plugins/kyuc/hooks/ghi-nhat-ky.sh
bash plugins/kyuc/hooks/dau-phien.sh | python3 -m json.tool
```
