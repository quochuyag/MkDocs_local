---
title: auto_ai — Trợ lý cá nhân Claude Code + Ollama + Open-WebUI
course: 09-dba-ai
source: dba_ai/auto_ai/README.md
---

# auto_ai — Trợ lý cá nhân Claude Code + Ollama + Open-WebUI

Bộ stack tự host kết hợp **Claude Code** (cloud, mạnh) với **Ollama** (cục bộ, miễn phí) và **Open-WebUI** (giao diện chat) — phục vụ học tập, viết code, review, và đảm bảo chất lượng code.

## Yêu cầu hệ thống

- Windows 10/11 (đã test trên Windows 11 Pro)
- PowerShell 7+
- [Ollama](https://ollama.com) — chạy nền (native, không cần Docker)
- [Node.js ≥ 20](https://nodejs.org) — cho OpenClaw CLI
- [VSCode](https://code.visualstudio.com/) + extension Continue.dev
- [Claude Code](https://docs.claude.com/claude-code) đã cài và đăng nhập
- *(Tùy chọn)* Docker Desktop — cho phương án container hóa
- *(Tùy chọn)* GPU NVIDIA + CUDA cho Ollama tăng tốc x10-20x

## Cài đặt nhanh

Chọn 1 trong 2 phương án:

### Phương án A — Docker (cô lập, dễ gỡ)

Cần [Docker Desktop](https://www.docker.com/products/docker-desktop/) đã cài và đang chạy.

```powershell
cd d:\Dba_project\dba_ai\auto_ai
.\scripts\setup.ps1              # Lần đầu — kéo image, pull model
.\scripts\start-all.ps1          # Khởi động
.\scripts\health-check.ps1
```

### Phương án B — Native (không cần Docker)

Cần [Python 3.11+](https://www.python.org/downloads/) (cho Open-WebUI). Ollama sẽ được installer cài tự động.

```powershell
cd d:\Dba_project\dba_ai\auto_ai
.\scripts\setup-native.ps1       # Cài Ollama + pip install open-webui
.\scripts\start-native.ps1       # Khởi động
.\scripts\health-native.ps1
```

Sau khi chạy:

- Mở Open-WebUI: <http://localhost:3000>
- Trong VSCode: bấm `Ctrl+Shift+P` → `Claude Code: Start` để dùng Claude Code
- Continue.dev sẽ tự kết nối Ollama cho autocomplete

## Tài liệu

- [docs/setup.md](docs/setup.md) — cài đặt chi tiết, troubleshoot
- [docs/usage.md](docs/usage.md) — hướng dẫn sử dụng từng công cụ
- [docs/workflows.md](docs/workflows.md) — workflow theo loại tác vụ (học, code, review, debug)
- [CLAUDE.md](claude.md) — hướng dẫn cho Claude Code khi làm việc trong repo này

## Mục đích sử dụng

| Tình huống | Công cụ nên dùng |
| --- | --- |
| Học khái niệm, hỏi đáp | Open-WebUI + `auto_ai-tutor` |
| Autocomplete khi gõ code | Continue.dev + `qwen2.5-coder:1.5b` |
| Chat nhanh về code (local, offline) | `openclaw agent --agent main` |
| Review code trước commit | `openclaw agent --agent reviewer` |
| Refactor / thiết kế kiến trúc | Claude Code (`/review`, subagent) |
| Debug bug phức tạp, đa file | Claude Code subagent |
| Nhắn tin Zalo tự động qua AI | OpenClaw + zalouser channel |

## Dừng / gỡ cài đặt

```powershell
.\scripts\stop-all.ps1               # Dừng container, giữ data
docker volume rm auto_ai_ollama_data # Xóa toàn bộ model đã pull (cẩn thận)
```


---

!!! info "Nguồn gốc"
    `dba_ai/auto_ai/README.md`
