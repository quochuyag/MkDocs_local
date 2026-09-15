---
title: CLAUDE.md
course: 09-dba-ai
source: dba_ai/auto_ai/CLAUDE.md
---

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Tổng quan dự án

`auto_ai` là trợ lý cá nhân tự host kết hợp hai thành phần:

1. **Claude Code (VSCode)** — agent lập trình chính: review, refactor, debug đa file (cloud).
2. **OpenClaw** — gateway AI cá nhân: nhận tin nhắn Zalo → route đến Gmail, Calendar, web search, AI (Gemini/Claude).

Mục đích: học tập, viết code, review code, và điều phối tác vụ cá nhân qua Zalo.

## Kiến trúc & luồng làm việc

```
Zalo (điện thoại)
    │  dm:pairing
    ▼
OpenClaw Gateway  ws://127.0.0.1:18789
    │
    ├── assistant-orchestrator agent
    │       ├── Gmail (imapflow)    ← scripts/openclaw-mail-skill.js
    │       ├── Google Calendar     ← gcalcli CLI
    │       ├── App Launcher        ← bundled skill
    │       ├── Web Search          ← Tavily API
    │       └── AI (Gemini / Claude)
    │
    └── Skills MCP stdio protocol
```

Sơ đồ chi tiết và phân chia tác vụ: [docs/setup.md](docs/setup.md), [docs/workflows.md](docs/workflows.md).

## Cấu trúc thư mục

```
auto_ai/
├── CLAUDE.md                  # File này — hướng dẫn cho Claude Code
├── README.md                  # Hướng dẫn người dùng
├── package.json               # Node.js deps cho skills (imapflow)
├── .claude/                   # Cấu hình Claude Code
│   ├── settings.json          # Permissions, env, hooks
│   ├── agents/                # Subagent tùy chỉnh (.md với frontmatter)
│   ├── commands/              # Slash command tùy chỉnh
│   └── hooks/                 # PowerShell hooks (pre/post tool)
├── .vscode/                   # Cấu hình VSCode + extensions
├── scripts/                   # PowerShell scripts + Node.js skills
│   ├── openclaw-mail-skill.js # MCP skill: đọc Gmail qua imapflow
│   ├── register-skills.ps1   # Đăng ký skills vào OpenClaw
│   └── setup-gcalcli.ps1     # Cài gcalcli (Google Calendar CLI)
├── docs/                      # Hướng dẫn chi tiết: setup / usage / workflows
└── before_bak/                # Backup tự động (scripts/backup.ps1)
```

## Lệnh thường dùng

Tất cả script chạy trên **PowerShell 7+** (Windows). Yêu cầu: Node.js 20+, VSCode, Claude Code CLI.

```powershell
# Cài Node.js dependencies cho skills (imapflow)
npm install

# Khởi động OpenClaw gateway
.\scripts\start-openclaw-gateway.ps1

# Đăng ký tự khởi động khi login (chạy 1 lần)
.\scripts\register-openclaw-startup.ps1

# Đăng ký skills vào OpenClaw
.\scripts\register-skills.ps1

# Backup trước khi thay đổi hệ thống
.\scripts\backup.ps1 -Label "before-<mo-ta>"
```

**Cổng mặc định:**

- OpenClaw Gateway: `http://localhost:18789`
- Dashboard: `http://localhost:18789/#overview`

## Quy ước khi Claude Code làm việc trong repo này

1. **Ngôn ngữ:** Trả lời người dùng bằng **tiếng Việt** (mặc định). Comment trong code có thể tiếng Anh nếu là code chung, tiếng Việt nếu là ghi chú giải thích cho người học.

2. **PowerShell first:** Người dùng dùng Windows + PowerShell. Mọi script tự động hóa viết bằng `.ps1`. Tránh `bash`/`sh` trừ khi nội bộ container Linux.

3. **Không tự ý cài extension/package toàn cục.** Đề xuất qua `.vscode/extensions.json` hoặc `package.json` tương ứng, để người dùng quyết định.

4. **Subagent có sẵn:** Ưu tiên dùng các subagent trong `.claude/agents/` thay vì làm thủ công:
   - `assistant-orchestrator` — route tác vụ cá nhân (email, lịch, web search, AI)
   - `code-reviewer` — review chất lượng, bug, security
   - `code-completer` — hoàn thiện hàm/class còn dang dở
   - `learning-tutor` — giải thích khái niệm, gợi ý bài tập
   - `quality-checker` — chạy linter, formatter, test coverage
   - `stability-guard` — phân tích race condition, edge case, error handling

5. **Slash command tùy chỉnh:** `/learn`, `/review`, `/complete`, `/stabilize`, `/explain` — định nghĩa trong `.claude/commands/`. Khi người dùng gọi, đọc file tương ứng để biết cách thực thi.

6. **Hook chạy ngầm:** `.claude/hooks/` chứa PowerShell scripts được kích hoạt bởi `settings.json`. Không sửa hook trừ khi được yêu cầu.

7. **Skills là MCP stdio server:** `scripts/openclaw-mail-skill.js` và các skill khác nói chuyện với OpenClaw qua JSON-RPC trên stdin/stdout. Khi sửa skill, kiểm tra `handleTool()` + `TOOLS` list luôn khớp nhau.

## Khi thêm tính năng mới vào stack

- **Thêm skill MCP mới:** Tạo `scripts/<tên>-skill.js`, đăng ký bằng `openclaw skills add`, liệt kê trong section "Skills" trên.
- **Thêm subagent:** Tạo `.claude/agents/<tên>.md` với YAML frontmatter (`name`, `description`, `tools`, `model`). Liệt kê trong CLAUDE.md mục "Subagent có sẵn" ở trên.
- **Thêm slash command:** Tạo `.claude/commands/<tên>.md`. Mô tả ngắn gọn ngữ cảnh và yêu cầu.
- **Thay đổi cổng:** Cập nhật đồng bộ `openclaw.json`, `health-check.ps1`, và section "Cổng mặc định" ở trên.

## Tham chiếu nhanh

- **Runbook (vận hành + nhật ký công việc):** [docs/runbook.md](docs/runbook.md)
- Hướng dẫn cài đặt chi tiết: [docs/setup.md](docs/setup.md)
- Cách dùng từng công cụ: [docs/usage.md](docs/usage.md)
- Workflow đề xuất theo loại tác vụ: [docs/workflows.md](docs/workflows.md)


---

!!! info "Nguồn gốc"
    `dba_ai/auto_ai/CLAUDE.md`
