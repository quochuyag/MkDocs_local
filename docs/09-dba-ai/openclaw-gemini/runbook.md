---
title: OpenClaw + Gemini + Zalo Bot — Runbook
course: 09-dba-ai
source: dba_ai/openclaw_gemini/RUNBOOK.md
---

# OpenClaw + Gemini + Zalo Bot — Runbook

Ghi lại các bước CLI đã chạy thành công để cấu hình OpenClaw chat hoạt động với Gemini và bot Zalo trên Windows. Các bước "dead-end" trong quá trình điều tra đã được lược bỏ — chỉ giữ lại các lệnh đúng, theo thứ tự.

Môi trường tham chiếu:

- Windows 11, PowerShell + Bash (Git Bash) đều dùng được.
- Node `v24.13.1` cài tại `C:\Program Files\nodejs\node.exe`.
- npm globals tại `C:\Users\HHC_HOME\AppData\Roaming\npm\`.
- OpenClaw home tại `C:\Users\HHC_HOME\.openclaw\`.
- Trước đó user đã chạy `openclaw onboard` và đăng nhập OAuth Gemini CLI (`huyhuynh20050615@gmail.com`).

Khi viết lại từ đầu trên máy khác: thay `HHC_HOME`, email, projectId, và token Zalo bằng giá trị thực của máy đó.

---

## 0. Kiểm tra hiện trạng (sanity check)

```bash
node --version          # v24.x
openclaw --version      # OpenClaw 2026.5.3-1 (...)
gemini --version        # 0.41.2
where.exe gemini        # phải thấy gemini.cmd dưới npm globals
where.exe openclaw      # tương tự
```

Mục đích: xác nhận 3 binary đều có trên PATH **của shell** (vẫn không đủ cho Node spawn — xem §2).

---

## 1. Validate cấu hình hiện tại

```bash
openclaw config validate
openclaw doctor
```

`config validate` chỉ kiểm tra schema. Nếu in `Config valid` thì JSON đúng dạng, **không** có nghĩa là chat chạy được. `doctor` mới phát hiện các vấn đề runtime (token sắp hết hạn, plugin registry stale, transcripts thiếu...).

Nếu doctor báo `Persisted plugin registry is missing or stale` thì chạy:

```bash
openclaw doctor --fix
```

---

## 2. Sửa lỗi `spawn gemini ENOENT` / `EINVAL` trên Windows

### Vấn đề

OpenClaw 2026.5.3-1 với `agentRuntime.id = "google-gemini-cli"` gọi `child_process.spawn("gemini", …)`. Trên Windows:

1. Node không tự thêm `.cmd` vào PATHEXT khi spawn → lỗi `ENOENT` dù `gemini --version` chạy được trong shell.
2. Sau khi sửa thành đường dẫn `.cmd` đầy đủ, Node 24 vẫn từ chối spawn `.cmd`/`.bat` trực tiếp (mitigation CVE-2024-27980) → lỗi `EINVAL`.

### Giải pháp đúng

Bỏ qua shim `.cmd`, gọi thẳng `node.exe` với file JS đích là arg đầu tiên.

#### 2.1. Backup config hiện tại trước khi sửa

```bash
cp "/c/Users/HHC_HOME/.openclaw/openclaw.json" \
   "/c/Users/HHC_HOME/.openclaw/openclaw.json.pre-cmd-fix"
```

OpenClaw cũng tự ghi `openclaw.json.bak` sau mỗi lần `config patch`, nhưng chỉ giữ 1 bản — mình giữ thêm bản gốc.

#### 2.2. Áp dụng override `cliBackends.google-gemini-cli`

Một câu lệnh duy nhất, dùng `--replace-path` cho `args` và `resumeArgs` để mảng được **thay** chứ không **merge**:

```bash
echo '{"agents":{"defaults":{"cliBackends":{"google-gemini-cli":{"command":"C:\\\\Program Files\\\\nodejs\\\\node.exe","args":["C:\\\\Users\\\\HHC_HOME\\\\AppData\\\\Roaming\\\\npm\\\\node_modules\\\\@google\\\\gemini-cli\\\\bundle\\\\gemini.js","--skip-trust","--output-format","json","--prompt","{prompt}"],"resumeArgs":["C:\\\\Users\\\\HHC_HOME\\\\AppData\\\\Roaming\\\\npm\\\\node_modules\\\\@google\\\\gemini-cli\\\\bundle\\\\gemini.js","--skip-trust","--resume","{sessionId}","--output-format","json","--prompt","{prompt}"],"env":{"GOOGLE_GENAI_USE_GCA":"true","GOOGLE_CLOUD_PROJECT":"celestial-bolt-2fvct"}}}}}}' \
| openclaw config patch --stdin \
  --replace-path "agents.defaults.cliBackends.google-gemini-cli.args" \
  --replace-path "agents.defaults.cliBackends.google-gemini-cli.resumeArgs"
```

Giải thích từng phần:

- `command: "C:\\Program Files\\nodejs\\node.exe"` — gọi Node trực tiếp, không qua `.cmd`.
- `args[0]` = đường dẫn tuyệt đối đến `gemini.js` (file JS thật mà shim `.cmd` wrap). Các arg sau (`--skip-trust --output-format json --prompt {prompt}`) là default mà OpenClaw kỳ vọng — copy nguyên từ source `dist/cli-backend-DLJhE14K.js`.
- `resumeArgs` tương tự nhưng có thêm `--resume {sessionId}` để OpenClaw có thể nối phiên cũ.
- `env.GOOGLE_GENAI_USE_GCA=true` — báo `gemini` CLI đọc OAuth credential từ `~/.gemini/oauth_creds.json` (đã được `openclaw onboard` ghi ra). Không có biến này thì gemini in: `Please set an Auth method in your ~/.gemini/settings.json …`.
- `env.GOOGLE_CLOUD_PROJECT=celestial-bolt-2fvct` — projectId trích từ `~/.openclaw/agents/main/agent/auth-profiles.json`. Tránh lỗi 404 ngẫu nhiên trên một số endpoint.

#### 2.3. Đổi default model sang model thật sự dùng được qua OAuth

Default cũ là `google/gemini-3-flash-latest` — model này trả `Requested entity was not found` qua OAuth path. Đổi sang Pro:

```bash
echo '{"agents":{"defaults":{"model":{"primary":"google/gemini-3.1-pro-preview"}}}}' \
| openclaw config patch --stdin
```

#### 2.4. Verify chat hoạt động

```bash
openclaw agent --local --agent main --message "What is 2+2? Reply with just the number."
```

Output mong đợi: dòng cuối in `4`. Có warning `Context engine "legacy" is not registered` về transcript persistence — không ảnh hưởng chat, là vấn đề khác.

---

## 3. Cài Zalo Bot channel (`@openclaw/zalo`)

### Tại sao phải cài tay

Doc OpenClaw nói `zalo` plugin "ships bundled" nhưng `package.json` thật của `openclaw@2026.5.3-1` lại có `!dist/extensions/zalo/**` trong `files` → bundle bị loại. Phải `plugins install` thủ công, giống `zalouser`.

### 3.1. Cài plugin

```bash
openclaw plugins install @openclaw/zalo
```

Plugin được cài vào `~/.openclaw/npm/`. Output kết thúc bằng `Installed plugin: zalo`.

### 3.2. Lưu token vào file (không bỏ thẳng vào openclaw.json)

Token Zalo có dạng `<numeric_id>:<secret>` và phần secret hoạt động như bearer credential — **không** nên ghi plaintext vào `openclaw.json` vì file đó được tự động backup ra `.bak`/`.last-good` mỗi lần edit.

```bash
mkdir -p "/c/Users/HHC_HOME/.openclaw/secrets"
# Dùng editor / Write tool để tạo file này, KHÔNG echo vào shell history.
# Nội dung file: đúng 1 dòng token, kết thúc bằng newline.
# C:\Users\HHC_HOME\.openclaw\secrets\zalo-default.token
```

Khoá ACL chỉ cho user hiện tại + SYSTEM + Administrators đọc được:

```powershell
icacls 'C:\Users\HHC_HOME\.openclaw\secrets\zalo-default.token' `
  /inheritance:r `
  /grant:r "${env:USERNAME}:(R,W)" `
  /grant:r "SYSTEM:(R,W)" `
  /grant:r "Administrators:(R,W)"
```

### 3.3. Bật channel và trỏ vào tokenFile

```bash
echo '{"channels":{"zalo":{"enabled":true,"accounts":{"default":{"enabled":true,"name":"Zalo Bot Default","tokenFile":"C:\\\\Users\\\\HHC_HOME\\\\.openclaw\\\\secrets\\\\zalo-default.token","dmPolicy":"pairing"}}}}}' \
| openclaw config patch --stdin
```

Giải thích:

- `tokenFile` — OpenClaw đọc token mỗi khi gateway start; symlinks bị từ chối.
- `dmPolicy: "pairing"` — DM lạ phải nhận pairing code rồi user approve. An toàn cho default.
- Không khai báo `groupPolicy` vì Zalo Marketplace bot không cho add bot vào group.

### 3.4. Verify channel

```bash
openclaw config validate
openclaw channels list
openclaw channels status --probe
```

Kết quả mong đợi từ `--probe`:

```text
- Zalo default (Zalo Bot Default): enabled, configured, running, mode:polling,
  dm:pairing, token:configFile, works
```

`works` = OpenClaw đã gọi thử Zalo API bằng token và nhận phản hồi hợp lệ.

---

## 4. Pairing flow lần đầu

Khi user lạ (kể cả chính mình từ tài khoản Zalo cá nhân) nhắn cho bot lần đầu:

1. Bot reply một pairing code.
2. Trên máy host, list code đang chờ rồi approve:

   ```bash
   openclaw pairing list zalo
   openclaw pairing approve zalo <CODE>
   ```

3. Code hết hạn sau 1 giờ. Nếu quá hạn thì user gửi tin nhắn lại để lấy code mới.

Sau khi approve, mọi tin nhắn từ user đó vào thẳng main session, qua agent, đến Gemini, và trả lời ngược lại trên Zalo.

---

## 4b. Phase 1 — Google OAuth (Gmail + Calendar) cho `quochuya@gmail.com`

### 4b.1. Việc làm trên Google Cloud Console (ngoài runbook này)

Trên project `gmail-triage-lab` (đã có sẵn — tên local cũ là `gmail-triage-desktop`, tên thực sau khi Anh Huy điều chỉnh):

1. **APIs & Services → Library:** bật **Gmail API** và **Google Calendar API**.
2. **OAuth consent screen:** External, **Publishing status = Testing**, add `quochuya@gmail.com` vào Test Users, thêm 4 scopes: `gmail.readonly`, `gmail.modify`, `calendar.readonly`, `calendar.events`.
3. **Credentials → Create OAuth client ID:** type **Desktop app**, download JSON.

Đặt file vào:

```text
C:\Users\HHC_HOME\.openclaw\secrets\google-quochuya-credentials.json
```

Khoá ACL:

```powershell
icacls 'C:\Users\HHC_HOME\.openclaw\secrets\google-quochuya-credentials.json' `
  /inheritance:r `
  /grant:r "${env:USERNAME}:(R,W)" `
  /grant:r "SYSTEM:(R,W)" `
  /grant:r "Administrators:(R,W)"
```

### 4b.2. Scaffold scripts Node ở `skills/google/`

```bash
mkdir -p "d:/Dba_project/dba_ai/openclaw_gemini/skills/google"
cd "d:/Dba_project/dba_ai/openclaw_gemini/skills/google"
npm init -y
npm pkg set type=module
npm install googleapis@latest open@latest
```

Các script trong thư mục này (xem source thực tế tại các đường dẫn dưới):

- [`auth-init.mjs`](skills/google/auth-init.mjs) — chạy OAuth loopback flow, lưu refresh token. Một lần duy nhất sau khi có credentials.
- [`_client.mjs`](skills/google/client.mjs) — helper load credentials + tokens, tự ghi đè token store khi access token được refresh.
- [`smoke-test.mjs`](skills/google/smoke-test.mjs) — gọi 3 endpoint xác nhận quyền hoạt động.

### 4b.3. Chạy OAuth flow lần đầu

```bash
cd "d:/Dba_project/dba_ai/openclaw_gemini/skills/google"
node auth-init.mjs
```

Browser tự mở trang Google consent. Anh Huy chọn `quochuya@gmail.com` → chấp nhận 4 scopes → tab tự đóng. Token được ghi vào:

```text
C:\Users\HHC_HOME\.openclaw\secrets\google-quochuya-tokens.json
```

Khoá ACL ngay sau đó:

```powershell
icacls 'C:\Users\HHC_HOME\.openclaw\secrets\google-quochuya-tokens.json' `
  /inheritance:r `
  /grant:r "${env:USERNAME}:(R,W)" `
  /grant:r "SYSTEM:(R,W)" `
  /grant:r "Administrators:(R,W)"
```

Output mong đợi:

```text
Refresh token present: yes
Scopes granted: <4 scopes của Gmail + Calendar>
```

Nếu `Refresh token present: NO` → vào <https://myaccount.google.com/permissions> revoke "OpenClaw Desktop", rồi rerun `node auth-init.mjs`. Google chỉ phát refresh token lần đầu user consent — revoke + re-consent reset trạng thái này.

### 4b.4. Smoke test 3 API

```bash
node smoke-test.mjs
```

Output mong đợi (tóm tắt):

```text
[1/3] gmail.users.labels.list      → ~22 labels (CHAT/SENT/INBOX/IMPORTANT/TRASH/...)
[2/3] gmail.users.messages.list    → 0–5 unread message(s) trong 24h gần nhất
[3/3] calendar.events.list         → 0–5 event sắp tới trên primary calendar
All three Google APIs answered without auth errors. Phase 1 done.
```

### 4b.5. Lỗi 403 SERVICE_DISABLED khi gọi Calendar

Triệu chứng: Gmail call work nhưng Calendar trả `403 PERMISSION_DENIED ... has not been used in project ... or it is disabled`.

Nguyên nhân: scope đã được consent rồi (OAuth grant OK), nhưng Calendar API chưa enabled trên project.

Fix: vào URL Google trả về (dạng `https://console.developers.google.com/apis/api/calendar-json.googleapis.com/overview?project=<PROJECT_NUMBER>`), bấm Enable, đợi ~1 phút, rerun `node smoke-test.mjs`. Không cần re-auth.

Mặc định lỗi tương tự với Gmail nếu Gmail API chưa enabled (`gmail.googleapis.com` thay vì `calendar-json.googleapis.com`) — fix giống.

### 4b.6. Re-auth định kỳ (gotcha của Testing mode)

Project ở **OAuth consent screen → Publishing status = Testing** với external Gmail user → Google invalidate refresh token sau **7 ngày**. Khi đó `node smoke-test.mjs` sẽ trả `invalid_grant`. Cách xử lý:

```bash
# Re-authorize
node auth-init.mjs
```

Anh Huy click chấp nhận lại trên browser ~5 giây, token store được refresh. Phase 4 (heartbeat cron) sau này sẽ schedule một job nhắc Anh Huy re-auth trước khi token chết.

Né hoàn toàn 7-day expiry: phải Publish to Production + qua Google's verification cho restricted scopes (Gmail) — chậm, không cần cho personal use case.

---

## 4c. Phase 2.1 — Email triage + Calendar today (standalone)

Hai script Node nhỏ chạy độc lập trước khi wrap thành plugin/MCP. Mục tiêu: verify accuracy trên inbox/calendar thật trước khi đầu tư build pipeline.

### 4c.1. Gemini API key

Lấy key từ Google AI Studio (<https://aistudio.google.com/app/apikey>), chọn project `gmail-triage-lab` cùng project OAuth. Key dạng `AIza...`.

```text
C:\Users\HHC_HOME\.openclaw\secrets\gemini-api-key.txt
```

Một dòng key, không có `GEMINI_API_KEY=` prefix.

```powershell
icacls 'C:\Users\HHC_HOME\.openclaw\secrets\gemini-api-key.txt' `
  /inheritance:r `
  /grant:r "${env:USERNAME}:(R,W)" `
  /grant:r "SYSTEM:(R,W)" `
  /grant:r "Administrators:(R,W)"
```

> Free tier `gemini-2.5-flash`: 15 RPM, 1500 RPD, 1M tokens/day. 25 email/lần phân loại ~7000 tokens — thoải mái.

### 4c.2. Cài SDK

```bash
cd "d:/Dba_project/dba_ai/openclaw_gemini/skills/google"
npm install @google/genai@latest
```

### 4c.3. Email triage

Script: [`gmail-triage.mjs`](skills/google/gmail-triage.mjs). Logic:

1. Fetch unread trong `TRIAGE_LOOKBACK` (default `1d`), max `TRIAGE_MAX` (default 25).
2. Lấy headers (`From`, `Subject`, `Date`, `List-Unsubscribe`) + snippet.
3. Gửi vào Gemini với `responseSchema` (JSON enum 4 nhãn) để output luôn parse được, không cần regex.
4. Retry tự động với exponential backoff khi gặp 429/503/504. Đọc `retry in Xs` từ message của 429 để tránh rate-limit thrashing.
5. In summary count + group theo nhãn, color-coded.

```bash
node gmail-triage.mjs
```

4 nhãn:

- `important_reply` — sếp/đối tác, hoá đơn, hợp đồng. Đỏ đậm.
- `important_fyi` — biên lai, cảnh báo bảo mật, kết quả phỏng vấn. Vàng.
- `notification` — LinkedIn, Shopee, newsletter. Cyan.
- `spam` — rác. Xám.

`thinkingConfig.thinkingBudget: 0` — bỏ thinking để tiết kiệm token (classification không cần reasoning).

### 4c.4. Calendar today

Script: [`calendar-today.mjs`](skills/google/calendar-today.mjs). Logic thuần — không cần Gemini:

1. Fetch events `now → now + CALENDAR_HORIZON_HOURS` (default 36h) từ primary calendar.
2. Phân loại 4 bucket: `in_progress` (đang diễn ra), `starting_soon` (≤ `CALENDAR_SOON_MINUTES`, default 30 phút), `today_later`, `future`.
3. Detect overlap: O(n²) sweep cặp event không phải all-day, break sớm khi events đã sort time-ordered.
4. Print với link conference, location, attendee count.

```bash
node calendar-today.mjs
```

`starting_soon` chính là rule #3 trong SOUL.md (alert meeting <30min).

### 4c.5. Lỗi quota khi run liên tục

Triệu chứng: `429 RESOURCE_EXHAUSTED ... Quota exceeded for metric: generate_content_free_tier_requests, limit: 20`.

`limit: 20` là RPM (requests/min) cho `gemini-2.5-flash` free tier, không phải daily. Script đã có retry tự động đọc `retry in Xs` — nếu chạy liên tiếp thì cứ đợi backoff. Tránh chạy nhiều lần liên tục để debug.

Nếu cần debug nhiều lần: temporarily set `MODEL = "gemini-2.0-flash"` (RPM cao hơn). Hoặc bật billing trên project — RPM tăng lên 1000.

---

## 4d. Phase 2.1 bước 3 — MCP server cho openclaw agent

Wrap 2 logic block ở 4c (gmail triage + calendar today) thành MCP server stdio để agent gọi như tool. Refactor logic thành `lib/` modules để cả CLI standalone và MCP server đều reuse được — không duplicate code.

### 4d.1. Cài SDK MCP

```bash
cd "d:/Dba_project/dba_ai/openclaw_gemini/skills/google"
npm install @modelcontextprotocol/sdk@latest zod@latest
```

### 4d.2. Cấu trúc thư mục sau refactor

```text
skills/google/
├── _client.mjs            OAuth helper (load credentials + refresh token store)
├── lib/
│   ├── gmail.mjs          triageInbox({ lookback, maxMessages }) → { groups, tokens, ... }
│   └── calendar.mjs       calendarSummary({ horizonHours, soonMinutes }) → { groups, overlaps, ... }
├── auth-init.mjs          OAuth bootstrap (chạy một lần)
├── smoke-test.mjs         verify API access
├── gmail-triage.mjs       CLI wrapper gọi triageInbox()
├── calendar-today.mjs     CLI wrapper gọi calendarSummary()
└── mcp-server.mjs         MCP stdio server expose 2 tool
```

Source xem trực tiếp tại các đường dẫn — không paste lại trong runbook.

### 4d.3. Đăng ký MCP server với openclaw

CLI `openclaw mcp set <name> <json>` bị Windows shim mangle JSON argv → patch thẳng vào `mcp.servers.<name>` qua `config patch --stdin`:

```bash
echo '{"mcp":{"servers":{"google-skills":{"command":"C:\\\\Program Files\\\\nodejs\\\\node.exe","args":["d:/Dba_project/dba_ai/openclaw_gemini/skills/google/mcp-server.mjs"]}}}}' \
| openclaw config patch --stdin
```

Lưu ý:

- `command` trỏ thẳng `node.exe` đúng đường dẫn — tránh `.cmd` shim như đã sửa cho Gemini CLI runtime trong §2.
- `args[0]` là forward-slash path, Node trên Windows accept; tránh phải double-escape backslash.
- Không truyền env riêng — `mcp-server.mjs` đọc credentials/token/api-key từ `~/.openclaw/secrets/` qua hardcoded path.

### 4d.4. Verify MCP entry

```bash
openclaw mcp list                       # phải in "- google-skills"
openclaw mcp show google-skills         # in JSON command + args đã set
```

### 4d.5. Smoke test end-to-end qua agent

```bash
openclaw agent --local --agent main \
  --message "Use the calendar_today tool to fetch my upcoming events for the next 36 hours. Reply with the result summary in Vietnamese."
```

Output mong đợi: agent gọi `calendar_today`, nhận structured + text result, diễn giải lại bằng tiếng Việt theo request. Confirm 4 thứ:

1. MCP server boot được (không có lỗi spawn).
2. Tool `calendar_today` xuất hiện trong tool list của agent.
3. Tool execute và trả data (events, count, overlaps).
4. Agent (Gemini) diễn giải kết quả.

Test gmail tương tự với prompt `"Use gmail_triage tool with lookback 1d. Show me only important_reply and important_fyi groups."` — chỉ chạy khi quota Gemini chưa hit cap.

### 4d.6. Hai tool đã expose

| Tool | Input schema | Output |
| --- | --- | --- |
| `gmail_triage` | `lookback` (string, default `"1d"`), `maxMessages` (1-50, default 25) | text summary + structuredContent (counts, groups, tokens) |
| `calendar_today` | `horizonHours` (1-168, default 36), `soonMinutes` (1-180, default 30) | text summary + structuredContent (counts, items, overlaps) |

Schema bằng `zod`. Description có tiếng Việt để agent hiểu nên dùng khi nào.

### 4d.7. Plugins allowlist (security warning)

Agent boot lần đầu in:

```text
plugins.allow is empty; discovered non-bundled plugins may auto-load: zalo (...). Set plugins.allow to explicit trusted ids.
```

Fix khi cả 2 plugin (`zalo`, MCP `google-skills`) đã verified stable:

```bash
echo '{"plugins":{"allow":["zalo","google-skills"]}}' | openclaw config patch --stdin
```

Sau bước này không-bundled plugin nào ngoài allowlist sẽ bị từ chối load, kể cả khi cài bằng `plugins install`. Phải explicit thêm vào allow.

> Lưu ý: tên trong `plugins.allow` phải là **plugin id** (xem `openclaw plugins list`), không phải MCP server name. MCP server (vd `google-skills`) đăng ký riêng ở `mcp.servers` và **không** cần trong allowlist.

---

## 4e. Phase 4 — Heartbeat cron (briefing 7h sáng)

### 4e.1. Upgrade scope CLI device (chỉ cần làm 1 lần)

CLI device sau khi pair mặc định chỉ có scope `operator.read` — không add được cron, MCP, channel. Cần upgrade lên full operator scopes.

Cách an toàn: mở `openclaw` TUI một lần, scope upgrade tự được approve qua dialog confirm.

Cách nhanh (manual, có rủi ro nếu sai key): sửa thẳng `~/.openclaw/devices/paired.json`. Tìm entry có `"clientId": "cli"`, đổi 3 mảng sau lên đầy đủ:

```json
"scopes": ["operator.admin","operator.read","operator.write","operator.approvals","operator.pairing"],
"approvedScopes": ["operator.admin","operator.read","operator.write","operator.approvals","operator.pairing"],
"tokens": {
  "operator": {
    "scopes": ["operator.admin","operator.approvals","operator.pairing","operator.read","operator.write"]
  }
}
```

Gateway pickup ngay lần probe kế tiếp; không cần restart. Verify bằng `openclaw daemon status` — capability phải in `admin-capable`.

### 4e.2. Tạo cron morning briefing

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
  --message "Build briefing buổi sáng cho Anh Huy. Gọi tool calendar_today (horizonHours=17, soonMinutes=30) và gmail_triage (lookback=1d, maxMessages=30). Tiếng Việt ngắn gọn, format theo: 📅 Lịch hôm nay (in_progress + starting_soon + today_later) / ⚠️ Xung đột (chỉ in nếu có) / ✉️ Mail cần lưu ý (chỉ important_reply + important_fyi). Tối đa 12 dòng."
```

Note 3 chỗ:

- `--session isolated` bắt buộc khi dùng `--message` — `main` session chỉ nhận `--system-event`.
- `--no-deliver` để output stay trong run-log file thay vì cố gắng gửi qua channel; bật lại sau khi pair Zalo và biết `chatId` (qua `openclaw cron edit <id> --channel zalo --to <chatId>`).
- `--tz "Asia/Ho_Chi_Minh"` — nếu không set, cron dùng host timezone (thường đúng cho VN nhưng explicit luôn rõ ràng hơn).

### 4e.3. Trigger debug-run

```bash
openclaw cron list                           # lấy job UUID
openclaw cron run <uuid>                     # enqueue ngay, không đợi 7h
```

Đọc kết quả:

```bash
tail -1 "C:/Users/HHC_HOME/.openclaw/cron/runs/<uuid>.jsonl"
```

Run-log JSONL chứa `summary` (final agent text), `status`, `durationMs`, `model`, `delivery`. Thời gian briefing chuẩn ~30–40s với gemini-3.1-pro-preview + 2 tool call.

### 4e.4. Bật delivery sang Zalo (sau khi pair)

Trình tự:

1. Anh Huy nhắn bot Zalo lần đầu, lấy pairing code.
2. `openclaw pairing approve zalo <CODE>`.
3. Lấy `chatId` của Anh Huy từ inbound message log: `openclaw channels logs --channel zalo | grep <số-Zalo>`.
4. Edit cron để bật delivery:

```bash
openclaw cron edit <uuid> --channel zalo --to <chatId> --announce
```

Sau bước này briefing 7h sáng tự động đẩy vào Zalo bot DM.

---

## 4f. Start / stop / reload OpenClaw — script tiện ích

Script: [`scripts/openclaw-ctl.ps1`](scripts/openclaw-ctl.ps1) (PowerShell 7+). Wrap `openclaw daemon` cho 5 hành động phổ biến + một vài validation.

```powershell
pwsh -File scripts/openclaw-ctl.ps1 status     # daemon + cron + mcp + channels
pwsh -File scripts/openclaw-ctl.ps1 reload     # validate config -> restart -> show status
pwsh -File scripts/openclaw-ctl.ps1 restart    # restart không validate
pwsh -File scripts/openclaw-ctl.ps1 start      # idempotent
pwsh -File scripts/openclaw-ctl.ps1 stop
pwsh -File scripts/openclaw-ctl.ps1 logs       # tail latest .log file
```

Khi nào nên dùng `reload`:

- Sau mỗi lần edit `~/.openclaw/openclaw.json` thủ công (rare — `config patch` đã tự reload).
- Sau khi sửa `paired.json` lớn (scope upgrade ở §4e.1 thì gateway tự pickup, không cần reload).
- Sau khi cài/uninstall plugin hoặc thay đổi `plugins.allow`.
- Khi cron không trigger đúng giờ (kiểm tra timezone qua `cron list`).

PowerShell mặc định block scripts ngoài. Một trong hai cách:

```powershell
# A. Allow user-scope một lần:
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned

# B. Mỗi lần invoke:
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/openclaw-ctl.ps1 status
```

Script chỉ dùng ASCII trong code paths để tránh PowerShell encoding pitfall trên Windows (không dùng arrow `→` Unicode trong source).

---

## 4g. Phase 2.2 — Application launcher (MCP server riêng)

Tách khỏi `google-skills` cho clean: alias config hỗn hợp Google sẽ phá single-responsibility. MCP server thứ 2 `launcher` ở `skills/launcher/` với 2 tool — `list_launchers` (read aliases) và `app_launch` (spawn process).

### 4g.1. Cài deps

```bash
cd "d:/Dba_project/dba_ai/openclaw_gemini/skills/launcher"
npm install @modelcontextprotocol/sdk@latest zod@latest yaml@latest
```

### 4g.2. Aliases config

File: [`skills/launcher/aliases.yaml`](skills/launcher/aliases.yaml). Schema mỗi alias:

```yaml
<alias-name>:                     # lowercase + dash, regex [a-z0-9-]+
  description: "..."              # text cho agent biết alias làm gì
  command: code                   # exe trên PATH hoặc absolute path
  args: ["%USERPROFILE%"]         # optional, env var %X% expand trên Windows nếu shell:true
  cwd: "C:/some/dir"              # optional working directory
  shell: true                     # default true trên Windows (cho .cmd/.bat shim + env expand)
```

MCP server **re-read YAML mỗi lần tool call** — sửa file là live ngay, không cần restart gateway hoặc daemon.

Default 4 alias: `code`, `terminal`, `explorer`, `notepad`. Anh Huy thêm Unity / DBeaver / SQL Developer / etc. bằng cách uncomment / paste section trong YAML.

### 4g.3. Đăng ký MCP server

```bash
echo '{"mcp":{"servers":{"launcher":{"command":"C:\\\\Program Files\\\\nodejs\\\\node.exe","args":["d:/Dba_project/dba_ai/openclaw_gemini/skills/launcher/mcp-server.mjs"]}}}}' \
| openclaw config patch --stdin

openclaw daemon restart
```

Restart cần thiết để gateway pickup MCP server mới (config hot-reload với `config patch` chỉ áp dụng cho `agents.*`, channel config; MCP servers bind ở boot time).

### 4g.4. Verify

```bash
openclaw mcp list                                # có "launcher" trong danh sách

openclaw agent --local --agent main \
  --message "Use list_launchers tool to show me aliases."
# → Agent gọi tool, in 4 alias mặc định.

openclaw agent --local --agent main \
  --message "Use app_launch to open notepad."
# → Notepad bật lên, agent in PID.
```

### 4g.5. Spawn behavior

- `detached: true` + `child.unref()` — process độc lập với gateway. Gateway shutdown / restart không kill ứng dụng đã launch.
- `stdio: 'ignore'` — không pipe output về MCP server (tránh treo stdio buffer).
- `shell: true` mặc định trên Windows → `.cmd` shim (`code.cmd`) + env-var expand (`%USERPROFILE%`) work.

### 4g.6. Khi nào KHÔNG nên dùng tool này

- Spawn shell script độc hại / script untrusted: tool spawn từ alias trong YAML, KHÔNG nhận command tùy ý từ agent. Agent chỉ chọn alias name + truyền extra args. Đây là safety boundary cố ý.
- Long-running compute job mà cần track exit code / stdout: `stdio: 'ignore'` đã làm tool fire-and-forget. Cho job kiểu đó nên build openclaw plugin riêng với child-process orchestration đầy đủ.

---

## 4h. Antigravity bridge — 2-way OpenClaw ↔ IDE

Antigravity là **Google's VS Code fork** (codename Jetski/Cascade, version 1.23.2 build trên VS Code 1.107.0 — `antigravity --version` báo VS Code base, không phải Antigravity). KHÔNG có headless `run --task` — Google official line là "Antigravity for visual development, Gemini CLI for headless". Bridge tận dụng 2 mặt native của IDE:

- **OpenClaw → Antigravity:** ghi PROMPT.md vào `<workspace>/.agent/workflows/<task_id>/`, IDE Workflow Editor render natively (selector trong [extensions/antigravity/package.json](file:///c:/Users/HHC_HOME/AppData/Local/Programs/Antigravity/resources/app/extensions/antigravity/package.json) match `**/.agent/workflows/**/*.md`).
- **Antigravity → OpenClaw:** Anh Huy đăng ký OpenClaw skills làm MCP servers trong `~/.gemini/antigravity/mcp_config.json` → agent built-in (Cascade) gọi tools của OpenClaw từ trong IDE.

Skill code: [skills/antigravity_bridge/](skills/antigravity_bridge/). Workflow folder: [.agent/workflows/](.agent/workflows/) (xem [.agent/workflows/README.md](.agent/workflows/README.md)). Rule cho agent in-IDE: [.agent/rules/openclaw-handoff.md](.agent/rules/openclaw-handoff.md).

### 4h.1. Cài deps + đăng ký phía OpenClaw

```bash
cd "d:/Dba_project/dba_ai/openclaw_gemini/skills/antigravity_bridge"
npm install

echo '{"mcp":{"servers":{"antigravity_bridge":{"command":"C:\\\\Program Files\\\\nodejs\\\\node.exe","args":["d:/Dba_project/dba_ai/openclaw_gemini/skills/antigravity_bridge/mcp-server.mjs"]}}}}' \
| openclaw config patch --stdin

openclaw daemon restart
```

Verify: `openclaw mcp list` thấy `antigravity_bridge`.

### 4h.2. Đăng ký phía Antigravity (reverse direction)

File chính thức Antigravity dùng: **`~/.gemini/antigravity/mcp_config.json`** (user-global; per-workspace MCP chưa support, theo Google forum). Schema validate qua `extensions/antigravity/schemas/mcp_config.schema.json`.

File đã được tạo bởi setup này:

```jsonc
{
  "$schema": "https://antigravity.google/schemas/mcp_config.json",
  "mcpServers": {
    "openclaw_antigravity_bridge": { "command": "...node.exe", "args": ["...skills/antigravity_bridge/mcp-server.mjs"] },
    "openclaw_launcher":           { "command": "...node.exe", "args": ["...skills/launcher/mcp-server.mjs"] },
    "openclaw_google_skills":      { "command": "...node.exe", "args": ["...skills/google/mcp-server.mjs"], "authProviderType": "google_credentials" }
  }
}
```

Sau khi sửa file, restart Antigravity (Command Palette → "Developer: Reload Window" hoặc đóng/mở IDE). Trong Agent pane → 3 dấu chấm → MCP Servers → "Manage MCP Servers" để xem trạng thái.

`authProviderType: "google_credentials"` cho `openclaw_google_skills`: Antigravity tự inject Google OAuth token của Anh Huy vào MCP server đó — không phải auth riêng.

### 4h.3. Smoke test

```bash
cd "d:/Dba_project/dba_ai/openclaw_gemini/skills/antigravity_bridge"
node smoke-test.mjs --no-spawn --clean    # logic only
node smoke-test.mjs --clean               # mở Antigravity thật
node direct-mcp-test.mjs                  # full MCP RPC, bypass OpenClaw + Gemini
```

PASS: `dispatch elapsed < 2000ms`. Đo trên máy hiện tại: 1ms (logic-only), 19ms (real spawn).

### 4h.4. Tools OpenClaw agent có thể gọi

| Tool | Tác dụng |
| --- | --- |
| `antigravity_dispatch` | Ghi `<workspace>/.agent/workflows/<id>/PROMPT.md`, spawn IDE detached, return `task_id` ngay (≤ vài chục ms). |
| `antigravity_status` | File-only check qua user index. Phase: `pending` / `running` / `done` / `timeout` / `cancelled`. |
| `antigravity_result` | Đọc `RESULT.md` khi phase = `done`. Default truncate 16k chars. |
| `antigravity_list_tasks` | Liệt kê tasks gần nhất từ user-global index. |
| `antigravity_cancel` | Set `cancelled_at` trong STATUS.json. **Không** kill IDE. |

### 4h.5. Convention bên trong Antigravity

Khi IDE mở `PROMPT.md` (Workflow Editor render):

1. Agent in-IDE (Cascade / Jetski / Claude Code panel — Anh Huy đang có cả 3 option trong IDE) đọc PROMPT.md. Rule [.agent/rules/openclaw-handoff.md](.agent/rules/openclaw-handoff.md) hướng dẫn agent biết phải làm gì.
2. Agent làm việc, có thể gọi ngược OpenClaw qua MCP tools đã register ở §4h.2.
3. Ghi `RESULT.md` vào CÙNG folder. Bridge poll mtime + existence → phase chuyển sang `done`.

Nếu Anh Huy không kích hoạt agent extension nào, làm bước 1–3 thủ công.

### 4h.6. State files

- **Per-task** (workspace-local): `<workspace>/.agent/workflows/<task_id>/{PROMPT.md, RESULT.md, STATUS.json, spawn.log}`.
- **User-global index**: `~/.openclaw/state/antigravity-bridge/index.json` mapping `task_id → {workspace, dir, title, dispatched_at}`. Cho phép `status`/`list_tasks`/`result` tìm lại task dù workspace khác nhau.
- **MCP config Antigravity**: `~/.gemini/antigravity/mcp_config.json`.

### 4h.7. Spawn `Antigravity.exe` trực tiếp thay vì `antigravity.cmd`

Cùng lý do với gemini-cli ở §2: Node 24 từ chối `.cmd` không có `shell:true`, mà `shell:true + args` thì có deprecation warning + injection surface. Bridge gọi:

```text
C:\Users\HHC_HOME\AppData\Local\Programs\Antigravity\Antigravity.exe
  C:\Users\HHC_HOME\AppData\Local\Programs\Antigravity\resources\app\out\cli.js
  --reuse-window --add <workspace> --goto <PROMPT.md path>
```

với `env.ELECTRON_RUN_AS_NODE=1`. Override binary qua env var `ANTIGRAVITY_BIN` nếu cần.

### 4h.8. Heartbeat-safety

- `spawn(..., { detached: true, stdio: "ignore" })` + `child.unref()` → child độc lập, parent return ngay.
- Toàn bộ IO của tool là sync `writeFileSync`/`readFileSync` trên file size kB → microseconds.
- Không `await child.on('close')`, không HTTP, không lock.
- → Antigravity treo 1 giờ vì agent suy nghĩ, OpenClaw cron heartbeat (§4e) vẫn fire đúng giờ.

---

## 5. Rollback / xử lý sự cố

### Khôi phục config trước khi sửa

```bash
cp "/c/Users/HHC_HOME/.openclaw/openclaw.json.pre-cmd-fix" \
   "/c/Users/HHC_HOME/.openclaw/openclaw.json"
openclaw config validate
```

### Sau khi `openclaw upgrade` — kiểm tra xem fix Windows đã có chưa

Nếu OpenClaw đã sửa lỗi spawn trên Windows trong release mới, có thể xoá toàn bộ block override:

```bash
echo '{"agents":{"defaults":{"cliBackends":null}}}' \
| openclaw config patch --stdin
openclaw agent --local --agent main --message "say hi"
```

Nếu vẫn `OK` → fix đã có sẵn, override không cần nữa. Nếu lỗi `spawn` quay lại → áp dụng lại §2.2.

### Đổi token Zalo (sau khi rotate trên Bot Platform dashboard)

```bash
# Ghi đè file token (dùng editor/Write tool, không echo vào shell history)
# Sau đó restart gateway:
openclaw daemon restart    # hoặc dừng và mở lại openclaw TUI
openclaw channels status --probe
```

### Đổi sang API-key Gemini (bỏ subprocess CLI hoàn toàn)

Nếu muốn rời hẳn khỏi `google-gemini-cli` runtime (vd: Google rate-limit hay revoke OAuth của CLI không chính thức):

```bash
openclaw onboard --auth-choice gemini-api-key
echo '{"agents":{"defaults":{"agentRuntime":null,"cliBackends":{"google-gemini-cli":null}}}}' \
| openclaw config patch --stdin
```

---

## Phụ lục: tóm tắt các file/đường dẫn quan trọng

| Đường dẫn | Mục đích |
| --- | --- |
| `~/.openclaw/openclaw.json` | Config chính (chỉnh qua `openclaw config patch`, đừng sửa tay) |
| `~/.openclaw/openclaw.json.bak` | Backup tự động sau mỗi `config patch` |
| `~/.openclaw/openclaw.json.last-good` | Bản hợp lệ gần nhất (khi config bị corrupt) |
| `~/.openclaw/openclaw.json.pre-cmd-fix` | Backup tay trước khi áp §2.2 |
| `~/.openclaw/secrets/zalo-default.token` | Token Zalo Bot, ACL-restricted |
| `~/.openclaw/agents/main/agent/auth-profiles.json` | OAuth credential OpenClaw lưu cho Gemini CLI provider |
| `~/.gemini/oauth_creds.json` | OAuth credential mà chính `gemini` CLI đọc khi `GOOGLE_GENAI_USE_GCA=true` |
| `~/.openclaw/logs/config-health.json` | Trạng thái health của config |
| `C:\Users\HHC_HOME\AppData\Roaming\npm\node_modules\openclaw\docs\` | Doc upstream đi kèm bản cài (tra trước khi đoán flag) |


---

!!! info "Nguồn gốc"
    `dba_ai/openclaw_gemini/RUNBOOK.md`
