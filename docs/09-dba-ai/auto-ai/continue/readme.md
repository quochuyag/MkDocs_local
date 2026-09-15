---
title: Continue.dev — autocomplete & chat tại chỗ bằng Ollama
course: 09-dba-ai
source: dba_ai/auto_ai/continue/README.md
---

# Continue.dev — autocomplete & chat tại chỗ bằng Ollama

[Continue.dev](https://continue.dev) là extension VSCode (open source) cung cấp:
- **Tab autocomplete** — như Copilot nhưng dùng model cục bộ.
- **Chat panel** — hỏi đáp về code đang chọn.
- **Edit inline** (`Ctrl+I`) — sửa code bằng prompt.

## Cách áp dụng config

Cách 1 (khuyên dùng): symlink để Continue đọc trực tiếp file này.

```powershell
# Chạy 1 lần (cần PowerShell admin)
$src = "d:\Dba_project\dba_ai\auto_ai\continue\config.yaml"
$dst = "$env:USERPROFILE\.continue\config.yaml"
New-Item -ItemType Directory -Path (Split-Path $dst) -Force | Out-Null
if (Test-Path $dst) { Move-Item $dst "$dst.bak" }
New-Item -ItemType SymbolicLink -Path $dst -Target $src
```

Cách 2: Copy nội dung [config.yaml](config.yaml) → mở Command Palette trong VSCode (`Ctrl+Shift+P`) → `Continue: Open config.yaml` → paste vào.

## Yêu cầu model đã pull

Các model trong config (sẽ được pull tự động bởi `scripts\pull-models.ps1`):

- `qwen2.5-coder:7b` — chat & edit chính
- `qwen2.5-coder:1.5b-base` — tab autocomplete (nhẹ, nhanh)
- `deepseek-coder-v2:16b` — coder mạnh hơn (yêu cầu RAM/VRAM cao)
- `llama3.1:8b` — chat tổng quát
- `nomic-embed-text` — embedding cho codebase index


---

!!! info "Nguồn gốc"
    `dba_ai/auto_ai/continue/README.md`
