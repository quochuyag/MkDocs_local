---
title: Cách dùng — từng công cụ
course: 09-dba-ai
source: dba_ai/auto_ai/docs/usage.md
---

# Cách dùng — từng công cụ

## Claude Code (trong VSCode)

Mở Command Palette (`Ctrl+Shift+P`) → `Claude Code: Start Session`.

### Slash command tùy chỉnh (đã cấu hình trong `.claude/commands/`)

| Lệnh                      | Tác dụng                                                       |
|---------------------------|----------------------------------------------------------------|
| `/learn <chủ đề>`         | Giảng giải khái niệm + ra bài tập (gọi `learning-tutor` agent) |
| `/review [phạm vi]`       | Review code đã thay đổi (gọi `code-reviewer` agent)            |
| `/complete [file:line]`   | Hoàn thiện code dang dở (TODO, NotImplementedError)            |
| `/stabilize [file]`       | Phân tích race condition, edge case, error handling            |
| `/explain <symbol>`       | Giải thích hàm/class/module                                    |

Ví dụ:

```
/learn async/await trong Python
/review src/api/users.py
/complete src/utils/parser.py:42
/stabilize src/payment/
/explain UserService.authenticate
```

### Subagent có sẵn

- `assistant-orchestrator` — route tác vụ cá nhân (email, lịch, web search, AI)
- `code-reviewer` — review chất lượng
- `code-completer` — hoàn thiện hàm
- `learning-tutor` — gia sư
- `quality-checker` — chạy lint/test/coverage
- `stability-guard` — phân tích rủi ro production

Dùng trực tiếp:

```
@code-reviewer xem giúp file src/auth.py
```

---

## OpenClaw + Zalo (trợ lý cá nhân)

Gửi tin nhắn cho chính mình trên Zalo → OpenClaw nhận và route đến đúng skill.

### Các tác vụ hỗ trợ qua Zalo

| Yêu cầu                            | Skill được gọi         | Ví dụ                               |
|------------------------------------|------------------------|-------------------------------------|
| Đọc email                          | `list_emails`          | "Inbox mới nhất"                    |
| Tìm email                          | `search_emails`        | "Tìm email từ sếp"                  |
| Đọc nội dung email                 | `read_email`           | "Đọc email UID 12345"               |
| Xem lịch hôm nay                   | gcalcli                | "Hôm nay có gì không"               |
| Mở app                             | app-launcher           | "Mở VSCode"                         |
| Tìm kiếm web                       | Tavily search          | "Tìm tin tức về..."                 |
| Hỏi AI                             | Gemini / Claude        | "Giải thích X cho tôi"              |

### Cấu trúc lệnh Zalo

Không cần cú pháp đặc biệt — gõ tự nhiên. OpenClaw dùng `assistant-orchestrator` agent để hiểu ý định và gọi đúng tool.

### Kiểm tra trạng thái

```powershell
openclaw health                    # agents + heartbeat
openclaw channels status           # Zalo connected/disconnected
openclaw skills list               # tất cả skills và trạng thái
openclaw dashboard                 # mở browser dashboard
```

---

## Khi nào dùng cái gì?

```
Tác vụ                           → Công cụ
───────────────────────────────────────────
Viết/debug/refactor code          → Claude Code (VSCode)
Review code trước commit          → Claude /review
Học concept mới                   → Claude /learn
Hoàn thiện hàm còn TODO           → Claude /complete
Đọc email từ điện thoại           → Zalo → OpenClaw → Gmail skill
Xem lịch nhanh từ điện thoại      → Zalo → OpenClaw → Calendar
Hỏi nhanh từ điện thoại           → Zalo → OpenClaw → Gemini/Claude
```

---

## Quản lý OpenClaw

### Lệnh thường dùng

```powershell
# Khởi động
.\scripts\start-openclaw-gateway.ps1

# Trạng thái
openclaw health
openclaw doctor

# Agent (không cần gateway)
openclaw agent --local --agent main --message "..."

# Zalo session hết hạn (~90 ngày) → đăng nhập lại
openclaw channels logout --channel zalouser
openclaw channels login --channel zalouser
```

### Dashboard web

```powershell
openclaw dashboard   # mở browser tại http://127.0.0.1:18789/#overview
```

| Trang     | Nội dung                                        |
|-----------|-------------------------------------------------|
| Overview  | Uptime, tick interval, session count, cron jobs |
| Agents    | Danh sách agent, model, trạng thái              |
| Skills    | Tất cả skills, trạng thái ready/missing         |
| Logs      | Log real-time từ gateway                        |
| Chat      | Chat trực tiếp với agent qua browser            |


---

!!! info "Nguồn gốc"
    `dba_ai/auto_ai/docs/usage.md`
