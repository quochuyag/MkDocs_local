---
title: Cài đặt chi tiết
course: 09-dba-ai
source: dba_ai/auto_ai/docs/setup.md
---

# Cài đặt chi tiết

## 1. Yêu cầu

| Phần mềm   | Tối thiểu | Ghi chú                    |
|------------|-----------|----------------------------|
| Windows    | 10 64-bit | 11 Pro khuyến nghị         |
| Node.js    | 20 LTS    | Cho OpenClaw CLI + skills  |
| PowerShell | 7.0+      | 7.4+ khuyến nghị           |
| VSCode     | 1.85+     | Mới nhất                   |

## 2. Cài Node.js

```powershell
winget install OpenJS.NodeJS.LTS
# Verify
node --version   # ≥ 20
npm --version    # ≥ 10
```

## 3. Cài Claude Code

```powershell
npm install -g @anthropic-ai/claude-code
claude login
```

Hoặc xem <https://docs.claude.com/claude-code> cho cách cài khác.

## 4. Cài VSCode + extension

1. Cài VSCode: <https://code.visualstudio.com/>
2. Mở thư mục `auto_ai` trong VSCode (`code .`).
3. VSCode sẽ hỏi cài extension được đề xuất → **Install All**.

Extension chính:
- `anthropic.claude-code` — Claude Code panel

## 5. Cài OpenClaw + cấu hình

### 5.1 Cài CLI

```powershell
npm install -g openclaw
openclaw --version   # xác nhận: 2026.x.x
```

### 5.2 Cài dependencies cho skills

```powershell
cd d:\Dba_project\dba_ai\auto_ai
npm install   # cài imapflow cho openclaw-mail-skill.js
```

### 5.3 Tạo credentials Gmail

```powershell
$credDir = "$env:USERPROFILE\.openclaw\credentials"
New-Item -ItemType Directory -Force -Path $credDir | Out-Null
# Paste 16-char App Password từ Google Account → Security → App Passwords
Set-Content "$credDir\gmail-app-pass.txt" "xxxx xxxx xxxx xxxx" -Encoding ASCII -NoNewline
```

> **Lấy App Password:** [myaccount.google.com](https://myaccount.google.com) → Security → 2-Step Verification → App passwords → Tạo mới cho "Mail".

### 5.4 File cấu hình `~/.openclaw/openclaw.json`

Config đầy đủ nằm tại `C:\Users\<user>\.openclaw\openclaw.json`. Xem ví dụ hoàn chỉnh trong [docs/runbook.md](runbook.md) (Section 6.3).

Các field tối thiểu cần có:
- `gateway.mode: "local"` — bắt buộc để gateway start
- `gateway.auth.token` — tự sinh bởi `openclaw onboard`
- `channels.zalouser.enabled: true`

### 5.5 Onboard lần đầu

```powershell
# Bước 1: Khởi động gateway nền
Start-Process powershell -ArgumentList "-Command openclaw gateway run" -WindowStyle Hidden

# Bước 2: Onboard — tạo device token
openclaw onboard

# Bước 3: Restart gateway để dùng token mới
# Tìm PID: netstat -ano | findstr ":18789"
taskkill /F /PID <pid>
Start-Process powershell -ArgumentList "-Command openclaw gateway run" -WindowStyle Hidden

# Bước 4: Xác nhận
openclaw health
```

### 5.6 Đăng nhập Zalo

```powershell
openclaw plugins install @openclaw/zalouser
openclaw channels login --channel zalouser
# Quét QR tại: D:\TEMP\openclaw\openclaw-zalouser-qr-default.png
# Xác nhận trên điện thoại trong vòng 60 giây
```

### 5.7 Đăng ký skills

```powershell
.\scripts\register-skills.ps1
```

Script này đăng ký `openclaw-mail-skill.js` (Gmail IMAP) và các skill bundled vào OpenClaw.

## 6. Verify

```powershell
openclaw health        # → agents + heartbeat
openclaw doctor        # → full diagnostic
```

Nếu thấy warning về missing credentials hoặc skill, xem [Troubleshoot](#troubleshoot).

## 7. Đăng ký tự khởi động

```powershell
.\scripts\register-openclaw-startup.ps1
# → Task 'OpenClaw-Gateway-AutoStart' đăng ký trong Task Scheduler (user-level)
# → Gateway tự start ẩn sau mỗi lần login
```

## Troubleshoot

### "Gateway không start"

```powershell
# Kiểm tra port
netstat -ano | findstr ":18789"
# Xem log
openclaw gateway run   # chạy foreground để xem lỗi
```

Lỗi thường gặp: thiếu `gateway.mode: "local"` trong `openclaw.json`.

### "Gmail IMAP lỗi authentication"

- Kiểm tra App Password đúng format 16 ký tự (không dấu cách): `cat "$env:USERPROFILE\.openclaw\credentials\gmail-app-pass.txt"`
- Gmail phải bật IMAP: Gmail Settings → See all settings → Forwarding and POP/IMAP → Enable IMAP.
- Tài khoản phải bật 2-Step Verification để dùng App Password.

### "Zalo QR timeout"

Thực hiện lại:
```powershell
openclaw channels logout --channel zalouser
openclaw channels login --channel zalouser
```

### "Skill not found / 503"

```powershell
openclaw skills list           # xem trạng thái skill
openclaw gateway restart       # restart để reload skill
```


---

!!! info "Nguồn gốc"
    `dba_ai/auto_ai/docs/setup.md`
