---
title: OpenClaw — Setup từ đầu
course: 09-dba-ai
source: dba_ai/openclaw_gemini/SETUP.md
---

# OpenClaw — Setup từ đầu

Hướng dẫn cài đặt full stack OpenClaw + Gemini + Zalo + Google Skills + Launcher + Antigravity Bridge **trên máy Windows mới**. Tài liệu này thiên về *command-first* — mỗi bước có lệnh và cách verify, không giải thích sâu. Khi cần biết "tại sao" hay troubleshooting, xem [RUNBOOK.md](runbook.md) — runbook là tài liệu nguồn chứa rationale, gotcha và rollback.

Tổng thời gian setup ước lượng: **45–75 phút** (chưa tính chờ Google Cloud Console enable APIs).

---

## Mục lục

- [0. Prerequisites](#0-prerequisites)
- [1. Cài OpenClaw + plugin npm](#1-cài-openclaw--plugin-npm)
- [2. Onboard Gemini (OAuth qua gemini-cli)](#2-onboard-gemini-oauth-qua-gemini-cli)
- [3. Fix Windows spawn bug (`ENOENT` / `EINVAL`)](#3-fix-windows-spawn-bug-enoent--einval)
- [4. Cài Zalo Bot channel](#4-cài-zalo-bot-channel)
- [5. Google Skills (Gmail + Calendar)](#5-google-skills-gmail--calendar)
- [6. Launcher Skill](#6-launcher-skill)
- [7. Antigravity Bridge](#7-antigravity-bridge)
- [8. Cron heartbeat (briefing 7h sáng)](#8-cron-heartbeat-briefing-7h-sáng)
- [9. Control script (start/stop/reload)](#9-control-script-startstopreload)
- [10. Verify cuối — toàn bộ stack](#10-verify-cuối--toàn-bộ-stack)

---

## 0. Prerequisites

| Yêu cầu | Cách verify |
| --- | --- |
| Windows 11, PowerShell 7+ | `pwsh --version` |
| Node.js 22.14+ (24.x recommended) | `node --version` |
| Tài khoản Google cho Gemini OAuth | sẵn sàng đăng nhập browser |
| Tài khoản Google cho Gmail/Calendar | có thể khác (ở đây: `quochuya@gmail.com`) |
| Project Google Cloud Console | tên gợi ý: `gmail-triage-lab` |
| Zalo Bot token (`<id>:<secret>`) | tạo trên Zalo Bot Platform |

Workspace mặc định: `d:\Dba_project\dba_ai\openclaw_gemini\` — đường dẫn dưới đây giả định layout này. Đổi nếu máy khác.

---

## 1. Cài OpenClaw + plugin npm

```powershell
npm install -g openclaw @openclaw/zalo @openclaw/zalouser @google/gemini-cli
```

Verify:

```powershell
openclaw --version    # OpenClaw 2026.5.x
gemini --version      # 0.41.x
where.exe openclaw    # ...\npm\openclaw.cmd
where.exe gemini      # ...\npm\gemini.cmd
```

---

## 2. Onboard Gemini (OAuth qua gemini-cli)

```powershell
openclaw onboard
```

Trong wizard chọn: **`google-gemini-cli`** runtime → bật browser → đăng nhập tài khoản Gemini → consent.

Kết quả mong đợi:

- `~/.gemini/oauth_creds.json` được tạo.
- `~/.openclaw/agents/main/agent/auth-profiles.json` chứa profile với `projectId`.

Lấy projectId cho bước 3:

```powershell
Get-Content "$env:USERPROFILE\.openclaw\agents\main\agent\auth-profiles.json" | Select-String projectId
```

Ghi nhớ giá trị (ví dụ `celestial-bolt-2fvct`) — sẽ dùng làm `GOOGLE_CLOUD_PROJECT` ở bước kế.

---

## 3. Fix Windows spawn bug (`ENOENT` / `EINVAL`)

Backup config trước khi sửa:

```bash
cp "/c/Users/$USER/.openclaw/openclaw.json" "/c/Users/$USER/.openclaw/openclaw.json.pre-cmd-fix"
```

Áp dụng override (thay `HHC_HOME` thành username thực, `celestial-bolt-2fvct` thành projectId của Anh Huy):

```bash
echo '{"agents":{"defaults":{"cliBackends":{"google-gemini-cli":{"command":"C:\\\\Program Files\\\\nodejs\\\\node.exe","args":["C:\\\\Users\\\\HHC_HOME\\\\AppData\\\\Roaming\\\\npm\\\\node_modules\\\\@google\\\\gemini-cli\\\\bundle\\\\gemini.js","--skip-trust","--output-format","json","--prompt","{prompt}"],"resumeArgs":["C:\\\\Users\\\\HHC_HOME\\\\AppData\\\\Roaming\\\\npm\\\\node_modules\\\\@google\\\\gemini-cli\\\\bundle\\\\gemini.js","--skip-trust","--resume","{sessionId}","--output-format","json","--prompt","{prompt}"],"env":{"GOOGLE_GENAI_USE_GCA":"true","GOOGLE_CLOUD_PROJECT":"celestial-bolt-2fvct"}}}}}}' \
| openclaw config patch --stdin \
  --replace-path "agents.defaults.cliBackends.google-gemini-cli.args" \
  --replace-path "agents.defaults.cliBackends.google-gemini-cli.resumeArgs"
```

Đổi default model sang `pro-preview` (Flash trả 404 qua OAuth path):

```bash
echo '{"agents":{"defaults":{"model":{"primary":"google/gemini-3.1-pro-preview"}}}}' \
| openclaw config patch --stdin
```

Verify:

```bash
openclaw agent --local --agent main --message "What is 2+2? Reply with just the number."
# → in "4". Warning "Context engine 'legacy' is not registered" có thể bỏ qua.
```

> Chi tiết tại sao 2 lỗi xảy ra → [RUNBOOK.md §2](runbook.md).

---

## 4. Cài Zalo Bot channel

### 4.1. Cài plugin

```powershell
openclaw plugins install @openclaw/zalo
```

### 4.2. Lưu token vào file ACL'd

Tạo `~/.openclaw/secrets/zalo-default.token` bằng editor (1 dòng, đúng token, KHÔNG `echo >` vào shell history).

```powershell
icacls "$env:USERPROFILE\.openclaw\secrets\zalo-default.token" `
  /inheritance:r `
  /grant:r "${env:USERNAME}:(R,W)" `
  /grant:r "SYSTEM:(R,W)" `
  /grant:r "Administrators:(R,W)"
```

### 4.3. Bật channel

```bash
echo '{"channels":{"zalo":{"enabled":true,"accounts":{"default":{"enabled":true,"name":"Zalo Bot Default","tokenFile":"C:\\\\Users\\\\HHC_HOME\\\\.openclaw\\\\secrets\\\\zalo-default.token","dmPolicy":"pairing"}}}}}' \
| openclaw config patch --stdin
```

Verify:

```bash
openclaw channels status --probe
# Mong đợi: "Zalo default ... running, mode:polling, dm:pairing, token:configFile, works"
```

### 4.4. Pairing lần đầu

Nhắn tin tới bot từ Zalo cá nhân → bot reply mã pairing → trên host:

```bash
openclaw pairing list zalo
openclaw pairing approve zalo <CODE>
```

> Mã có hiệu lực 1 giờ. Group policy không cần cấu hình — Zalo Marketplace bot không add được vào group.

---

## 5. Google Skills (Gmail + Calendar)

### 5.1. Trên Google Cloud Console

Project: `gmail-triage-lab` (hoặc tên Anh Huy chọn).

1. **APIs & Services → Library:** bật **Gmail API** và **Google Calendar API**.
2. **OAuth consent screen:** External, **Publishing = Testing**, add `quochuya@gmail.com` (hoặc email phase-1) vào Test Users; scopes: `gmail.readonly`, `gmail.modify`, `calendar.readonly`, `calendar.events`.
3. **Credentials → Create OAuth client ID:** Desktop app → download JSON → đặt vào `C:\Users\HHC_HOME\.openclaw\secrets\google-quochuya-credentials.json`.

ACL credentials:

```powershell
icacls "$env:USERPROFILE\.openclaw\secrets\google-quochuya-credentials.json" `
  /inheritance:r `
  /grant:r "${env:USERNAME}:(R,W)" `
  /grant:r "SYSTEM:(R,W)" `
  /grant:r "Administrators:(R,W)"
```

### 5.2. Lấy Gemini API key (cho triage)

Lấy ở <https://aistudio.google.com/app/apikey>, lưu vào `C:\Users\HHC_HOME\.openclaw\secrets\gemini-api-key.txt` (1 dòng key, không prefix), ACL như trên.

### 5.3. Cài deps + bootstrap OAuth

```powershell
cd "d:\Dba_project\dba_ai\openclaw_gemini\skills\google"
npm install
node auth-init.mjs
```

Browser mở consent → chọn email phase-1 → accept 4 scopes. Output mong đợi:

```text
Refresh token present: yes
Scopes granted: 4 scopes
```

ACL token file:

```powershell
icacls "$env:USERPROFILE\.openclaw\secrets\google-quochuya-tokens.json" `
  /inheritance:r /grant:r "${env:USERNAME}:(R,W)" /grant:r "SYSTEM:(R,W)" /grant:r "Administrators:(R,W)"
```

### 5.4. Smoke test

```powershell
node smoke-test.mjs
# All three Google APIs answered without auth errors. Phase 1 done.
```

Nếu 403 SERVICE_DISABLED → quay lại Console enable API tương ứng, đợi 1 phút, retry. Không cần re-auth.

### 5.5. Đăng ký MCP server

```bash
echo '{"mcp":{"servers":{"google-skills":{"command":"C:\\\\Program Files\\\\nodejs\\\\node.exe","args":["d:/Dba_project/dba_ai/openclaw_gemini/skills/google/mcp-server.mjs"]}}}}' \
| openclaw config patch --stdin
```

Verify:

```bash
openclaw mcp list                   # có "google-skills"
openclaw mcp show google-skills
openclaw agent --local --agent main \
  --message "Use the calendar_today tool to fetch upcoming events for the next 36 hours. Trả lời tiếng Việt."
```

> Re-auth định kỳ: Testing mode hết hạn refresh token sau **7 ngày**. Rerun `node auth-init.mjs` khi smoke test trả `invalid_grant`.

---

## 6. Launcher Skill

### 6.1. Cài deps

```powershell
cd "d:\Dba_project\dba_ai\openclaw_gemini\skills\launcher"
npm install
```

### 6.2. Cấu hình alias

Edit [skills/launcher/aliases.yaml](skills/launcher/aliases.yaml) — default 4 alias `code`, `terminal`, `explorer`, `notepad`. Thêm Unity / DBeaver / SQL Developer tuỳ nhu cầu. File được **re-read mỗi tool call** — sửa là live, không cần restart.

### 6.3. Đăng ký MCP server

```bash
echo '{"mcp":{"servers":{"launcher":{"command":"C:\\\\Program Files\\\\nodejs\\\\node.exe","args":["d:/Dba_project/dba_ai/openclaw_gemini/skills/launcher/mcp-server.mjs"]}}}}' \
| openclaw config patch --stdin

openclaw daemon restart
```

Verify:

```bash
openclaw mcp list                                           # có "launcher"
openclaw agent --local --agent main --message "Use list_launchers tool."
openclaw agent --local --agent main --message "Use app_launch to open notepad."
```

---

## 7. Antigravity Bridge

> Skip section này nếu chưa cài Antigravity IDE. Có thể bỏ qua hoàn toàn — bridge optional.

### 7.1. Cài deps

```powershell
cd "d:\Dba_project\dba_ai\openclaw_gemini\skills\antigravity_bridge"
npm install
```

### 7.2. Đăng ký MCP phía OpenClaw

```bash
echo '{"mcp":{"servers":{"antigravity_bridge":{"command":"C:\\\\Program Files\\\\nodejs\\\\node.exe","args":["d:/Dba_project/dba_ai/openclaw_gemini/skills/antigravity_bridge/mcp-server.mjs"]}}}}' \
| openclaw config patch --stdin

openclaw daemon restart
```

### 7.3. Đăng ký MCP phía Antigravity (reverse direction)

Tạo / sửa `~/.gemini/antigravity/mcp_config.json`:

```jsonc
{
  "$schema": "https://antigravity.google/schemas/mcp_config.json",
  "mcpServers": {
    "openclaw_antigravity_bridge": {
      "command": "C:/Program Files/nodejs/node.exe",
      "args": ["d:/Dba_project/dba_ai/openclaw_gemini/skills/antigravity_bridge/mcp-server.mjs"]
    },
    "openclaw_launcher": {
      "command": "C:/Program Files/nodejs/node.exe",
      "args": ["d:/Dba_project/dba_ai/openclaw_gemini/skills/launcher/mcp-server.mjs"]
    },
    "openclaw_google_skills": {
      "command": "C:/Program Files/nodejs/node.exe",
      "args": ["d:/Dba_project/dba_ai/openclaw_gemini/skills/google/mcp-server.mjs"],
      "authProviderType": "google_credentials"
    }
  }
}
```

Restart Antigravity (Command Palette → "Developer: Reload Window").

### 7.4. Smoke test

```powershell
cd "d:\Dba_project\dba_ai\openclaw_gemini\skills\antigravity_bridge"
node smoke-test.mjs --no-spawn --clean
node smoke-test.mjs --clean
node direct-mcp-test.mjs
```

PASS khi `dispatch elapsed < 2000ms`.

---

## 8. Cron heartbeat (briefing 7h sáng)

### 8.1. Upgrade CLI device scopes (1 lần)

Mở `openclaw` TUI một lần — dialog confirm tự bật scope upgrade. Verify: `openclaw daemon status` in `admin-capable`.

### 8.2. Tạo cron

```bash
openclaw cron add \
  --name morning-briefing \
  --cron "0 7 * * *" \
  --tz "Asia/Ho_Chi_Minh" \
  --agent main \
  --session isolated \
  --no-deliver \
  --exact \
  --thinking low \
  --timeout-seconds 180 \
  --message "Build briefing buổi sáng cho Anh Huy. Gọi tool calendar_today (horizonHours=17, soonMinutes=30) và gmail_triage (lookback=1d, maxMessages=30). Tiếng Việt ngắn gọn, format: 📅 Lịch hôm nay (in_progress + starting_soon + today_later) / ⚠️ Xung đột (chỉ in nếu có) / ✉️ Mail cần lưu ý (chỉ important_reply + important_fyi). Tối đa 12 dòng."
```

### 8.3. Debug-run ngay

```bash
openclaw cron list                # lấy UUID
openclaw cron run <uuid>          # enqueue ngay
tail -1 "$HOME/.openclaw/cron/runs/<uuid>.jsonl"
```

### 8.4. Bật delivery qua Zalo (sau khi pair)

```bash
openclaw channels logs --channel zalo                    # tìm chatId
openclaw cron edit <uuid> --channel zalo --to <chatId> --announce
```

---

## 9. Control script (start/stop/reload)

Script [scripts/openclaw-ctl.ps1](scripts/openclaw-ctl.ps1) wrap `openclaw daemon` cho 5 thao tác phổ biến.

```powershell
pwsh -File scripts/openclaw-ctl.ps1 status
pwsh -File scripts/openclaw-ctl.ps1 reload    # validate config -> restart -> show status
pwsh -File scripts/openclaw-ctl.ps1 restart
pwsh -File scripts/openclaw-ctl.ps1 start
pwsh -File scripts/openclaw-ctl.ps1 stop
pwsh -File scripts/openclaw-ctl.ps1 logs
```

Nếu PowerShell block script:

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
# hoặc per-invoke:
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/openclaw-ctl.ps1 status
```

Khi nào dùng `reload`:

- Sau khi sửa tay `~/.openclaw/openclaw.json`.
- Sau khi cài/uninstall plugin hoặc sửa `plugins.allow`.
- Sau khi đăng ký MCP server mới (MCP bind ở boot time).

---

## 10. Verify cuối — toàn bộ stack

```bash
openclaw doctor                          # mọi mục PASS
openclaw config validate                 # Config valid
openclaw channels status --probe         # Zalo: works
openclaw mcp list                        # google-skills, launcher, [antigravity_bridge]
openclaw cron list                       # morning-briefing
```

End-to-end smoke (qua agent → MCP tools → Gemini):

```bash
openclaw agent --local --agent main \
  --message "Use calendar_today (horizonHours=24). Trả lời tiếng Việt, tối đa 5 dòng."

openclaw agent --local --agent main \
  --message "Use gmail_triage (lookback=1d). Chỉ hiện important_reply + important_fyi."

openclaw agent --local --agent main \
  --message "Use list_launchers."
```

Bật allowlist plugin sau khi mọi thứ ổn định:

```bash
echo '{"plugins":{"allow":["zalo","google-skills","launcher","antigravity_bridge"]}}' \
| openclaw config patch --stdin
```

> MCP server name (`google-skills`, `launcher`, `antigravity_bridge`) **không** cần trong allowlist — chỉ plugin id (xem `openclaw plugins list`) cần.

---

## Khi cần tra sâu

- **Tại sao Windows lỗi spawn?** → [RUNBOOK.md §2](runbook.md)
- **Re-auth Google 7 ngày một lần?** → [RUNBOOK.md §4b.6](runbook.md)
- **403 SERVICE_DISABLED chi tiết?** → [RUNBOOK.md §4b.5](runbook.md)
- **Rollback config / đổi sang API key?** → [RUNBOOK.md §5](runbook.md)
- **Architecture 4 lớp?** → [CLAUDE.md "Architecture"](CLAUDE.md)
- **Roadmap 5 phase?** → [CLAUDE.md "Roadmap"](CLAUDE.md)

Khi sửa lệnh / fix mới phát hiện: cập nhật **RUNBOOK.md** (có rationale + alternatives), rồi mới đồng bộ thay đổi tóm lược vào tài liệu này nếu ảnh hưởng install path.


---

!!! info "Nguồn gốc"
    `dba_ai/openclaw_gemini/SETUP.md`
