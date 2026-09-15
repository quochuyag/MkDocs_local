---
title: Runbook — auto_ai
course: 09-dba-ai
source: dba_ai/auto_ai/docs/runbook.md
---

# Runbook — auto_ai

Tài liệu vận hành dự án `auto_ai`. Cập nhật mỗi khi có thay đổi quan trọng.

> **Đọc đúng phần — tiết kiệm token:** Dùng `Grep "^## " docs/runbook.md` để xem mục lục,
> sau đó `Read docs/runbook.md offset:<dòng> limit:80` để đọc đúng section cần thiết.
> Không đọc toàn bộ file này trừ khi cần tổng quan toàn bộ.

---

<!-- TOC — cập nhật khi thêm section mới -->
<!-- 1. Mục tiêu dự án        ~  7 -->
<!-- 2. Trạng thái hiện tại   ~ 19 -->
<!-- 3. Nhật ký 2026-05-03    ~ 46 -->
<!-- 4. Nhật ký 2026-05-04    ~ 97 -->
<!-- 5. Nhật ký 2026-05-04 p2 ~369 -->
<!-- 5b. Nhật ký 2026-05-05  ~389 -->
<!-- 6. Onboard OpenClaw      ~519 -->
<!-- 7. Vận hành hằng ngày    ~780 -->
<!-- 8. Bảo trì               ~817 -->
<!-- 9. Troubleshoot          ~880 -->
<!-- 10. Roadmap              ~892 -->
<!-- 11. Liên kết nhanh       ~920 -->

---

## 1. Mục tiêu dự án

Trợ lý AI cá nhân tự host trên Windows, kết hợp:

- **Claude Code** (cloud, mạnh) — refactor, kiến trúc, debug đa file
- **OpenClaw** — gateway AI cá nhân: nhận tin nhắn Zalo → route đến Gmail, Calendar, web search, AI (Gemini/Claude)

Phục vụ: học tập, viết code, review code, và điều phối tác vụ cá nhân qua Zalo.

---

## 2. Trạng thái hiện tại

| Thành phần | Trạng thái | Ghi chú |
|------------|-----------|---------|
| Claude Code | ✅ VSCode extension + CLI | Agent lập trình chính |
| OpenClaw 2026.5.2 | ✅ Gateway port 18789 | Zalo Personal kết nối (dm:pairing) |
| Zalo Personal (zalouser) | ✅ enabled, configured, running | Owner: `2281789073213379000` (Huy Huynh) |
| Gmail IMAP (imapflow) | ✅ `scripts/openclaw-mail-skill.js` | App Password tại `~/.openclaw/credentials/gmail-app-pass.txt` |
| Node.js deps | ✅ `npm install` ở root | imapflow cho mail skill |
| OpenClaw Gateway startup | ✅ Task Scheduler user-level | `register-openclaw-startup.ps1` |

### Skills đang hoạt động

| Skill | Loại | Tác dụng |
|-------|------|---------|
| `openclaw-mail-skill.js` | Custom MCP stdio | list/search/read Gmail IMAP |
| `himalaya` (bundled) | Bundled | Đã thay bằng imapflow — disabled |
| `gemini` (bundled) | Bundled | AI via Google Gemini |
| `vn-coder` | Custom SKILL.md | Trợ lý code tiếng Việt |
| `vn-reviewer` | Custom SKILL.md | Review code theo chuẩn OWASP |
| `vn-tutor` | Custom SKILL.md | Gia sư Socratic |

---

## 3. Nhật ký phiên 2026-05-03

### Đã làm

1. **Khởi tạo repo từ thư mục trống** tại `d:\Dba_project\dba_ai\auto_ai`.

2. **Tạo cấu trúc Claude Code:**
   - `CLAUDE.md` — hướng dẫn cho Claude Code
   - `.claude/settings.json` — permissions, hooks, env
   - 5 subagents trong `.claude/agents/`: code-reviewer, code-completer, learning-tutor, quality-checker, stability-guard
   - 5 slash commands trong `.claude/commands/`: /learn, /review, /complete, /stabilize, /explain
   - 2 hooks: `post-edit.ps1` (auto format), `session-stop.ps1` (log)

3. **Tạo cấu hình VSCode:**
   - `.vscode/settings.json`, `extensions.json`, `tasks.json` (7 tasks chạy được từ Command Palette)

4. **Cấu hình Ollama:**
   - 3 Modelfile (coder, tutor, reviewer) với system prompt tiếng Việt
   - `docker-compose.yml` (root) cho phương án Docker
   - `ollama/docker-compose.yml` standalone

5. **Cấu hình Open-WebUI** + `openwebui/docker-compose.yml`.

6. **Cấu hình Continue.dev** — `continue/config.yaml` với 3 chat model + autocomplete + 4 custom slash commands.

7. **7 PowerShell scripts** trong `scripts/`: setup (Docker), setup-native, start-all/native, stop-all/native, health-check/native, status, pull-models, build-custom-models, _common.

8. **3 docs:** setup, usage, workflows, openwebui, runbook (file này).

9. **Memory Claude Code:** lưu user_language, user_environment, project_purpose.

### Vấn đề gặp + cách fix

| Vấn đề | Nguyên nhân | Fix |
|--------|-------------|-----|
| `setup.ps1` báo "chưa cài Docker" | Máy không có Docker Desktop | Tạo phương án native (`setup-native.ps1`) — không cần Docker |
| Pull script gọi `docker exec` nhưng dùng native | Script viết cho Docker mode | Sửa `pull-models.ps1` + `build-custom-models.ps1` tự detect Docker vs native |
| `pip install open-webui` trên Python 3.13 báo "no matching distribution" | Open-WebUI yêu cầu `<3.13.0a1` | Cài Python 3.12.10 qua `winget install Python.Python.3.12 --scope user` |
| `pip install` nửa chừng OSError 32 (file lock) | Antivirus quét file đang ghi | Retry `pip install` — phần lớn dep đã cài, lần 2 thành công |
| Open-WebUI start crash UnicodeEncodeError cp1252 | Banner ASCII art Unicode không encode được trên Windows console | Set `PYTHONIOENCODING=utf-8` + `PYTHONUTF8=1` trong `start-native.ps1` |
| Symlink Continue config thất bại | Cần admin / Developer Mode | Fallback sang `Copy-Item` |
| `ollama pull` lần đầu chậm | Băng thông + size model | Pull background, để chạy nền |

### Quyết định kiến trúc

- **Tận dụng `gemma4:latest` đã có** → dùng làm base cho `auto_ai-tutor` thay vì pull thêm `llama3.1:8b` (tiết kiệm ~5GB).
- **Tạm bỏ Open-WebUI Docker compose** → chuyển sang native vì user không có Docker. Giữ file `docker-compose.yml` như tùy chọn dự phòng.
- **Continue.dev là autocomplete chính**, không phải Claude Code → tránh tốn token cloud cho tác vụ thường xuyên.

---

## 4. Nhật ký phiên 2026-05-04 — Tích hợp OpenClaw + Ollama

### Mục tiêu phiên

Kiểm tra OpenClaw đã có trên máy chưa, nếu có thì tích hợp Ollama vào OpenClaw và xây dựng kịch bản sử dụng OpenClaw làm trợ lý tự động cho coding và learning.

---

### Bước 1 — Kiểm tra OpenClaw đã có chưa

**Lệnh chạy:**

```powershell
where.exe openclaw
openclaw --version
```

**Kết quả:** OpenClaw đã được cài sẵn tại `C:\Users\HHC_HOME\AppData\Roaming\npm\openclaw`, phiên bản `2026.2.19-2`.

**Đồng thời kiểm tra trạng thái ban đầu:**

```powershell
openclaw health         # → lỗi: gateway chưa chạy
openclaw status         # → gateway unreachable, chưa có service
openclaw models status  # → chỉ có anthropic/claude-opus-4-6, chưa cấu hình Ollama
```

**Phát hiện:** OpenClaw có sẵn nhưng chưa cấu hình. Model mặc định là Claude (cloud), chưa trỏ về Ollama local. Gateway chưa khởi động.

---

### Bước 2 — Tìm hiểu cách tích hợp Ollama

**Tra docs:** Fetch `https://docs.openclaw.ai/providers/ollama`

**Phát hiện quan trọng:**

- OpenClaw có native Ollama provider (`api: "ollama"`) — **không dùng `/v1`** vì OpenAI-compat mode kém tin hơn cho tool calling
- URL đúng: `http://127.0.0.1:11434` (không có `/v1`)
- Format config: `provider/model` (ví dụ: `ollama/auto_ai-coder`)
- Command thiết lập nhanh: `openclaw onboard --non-interactive --auth-choice ollama --accept-risk`

**Kiểm tra models Ollama đang có:**

```powershell
curl http://localhost:11434/api/tags
```

Kết quả: 7 model — `nomic-embed-text`, `auto_ai-coder`, `auto_ai-reviewer`, `auto_ai-tutor`, `qwen2.5-coder:1.5b-base`, `qwen2.5-coder:7b`, `gemma4:latest`

---

### Bước 3 — Tạo file cấu hình `openclaw.json`

**File:** `C:\Users\HHC_HOME\.openclaw\openclaw.json`

**Nội dung cốt lõi** (ban đầu viết JSON5, OpenClaw tự convert sang JSON thuần):

```json5
{
  models: {
    mode: "merge",           // giữ models mặc định + thêm Ollama
    providers: {
      ollama: {
        baseUrl: "http://127.0.0.1:11434",
        apiKey: "ollama-local",
        api: "ollama",       // native API, KHÔNG phải openai-completions
        models: [
          { id: "auto_ai-coder",    contextWindow: 32768, maxTokens: 8192 },
          { id: "auto_ai-reviewer", contextWindow: 32768, maxTokens: 8192 },
          { id: "auto_ai-tutor",    contextWindow: 32768, maxTokens: 8192 },
          { id: "qwen2.5-coder:7b", contextWindow: 32768, maxTokens: 8192 },
          { id: "gemma4:latest",    contextWindow: 32768, maxTokens: 8192 }
        ]
      }
    }
  },
  agents: {
    defaults: { model: { primary: "ollama/auto_ai-coder", fallbacks: ["ollama/qwen2.5-coder:7b"] } },
    list: [
      { id: "main",     default: true, model: { primary: "ollama/auto_ai-coder" } },
      { id: "reviewer", model: { primary: "ollama/auto_ai-reviewer" } },
      { id: "tutor",    model: { primary: "ollama/auto_ai-tutor" } }
    ]
  },
  gateway: { mode: "local", port: 18789, bind: "loopback" }
}
```

**Lỗi gặp #1 — `systemPromptOverride` không nhận:**
Ban đầu thêm field `systemPromptOverride` vào mỗi agent, nhưng validator báo "Unrecognized key". Field này chưa hỗ trợ trong v2026.2.19. **Giải pháp:** Dùng SKILL.md thay thế (xem Bước 5).

**Lỗi gặp #2 — Gateway không start:**

```text
Gateway start blocked: set gateway.mode=local (current: unset)
```

**Fix:** Thêm `"mode": "local"` vào section `gateway` trong config.

---

### Bước 4 — Khởi động Gateway

**Vấn đề:** `openclaw gateway install` để cài Windows Scheduled Task bị từ chối vì không có quyền admin:

```text
schtasks create failed: ERROR: Access is denied.
```

**Giải pháp thay thế:** Chạy gateway thủ công, dùng script PowerShell user-level để đăng ký auto-start (Bước 6).

**Quy trình khởi động đầy đủ:**

```powershell
# 1. Chạy gateway nền
openclaw gateway run &

# 2. Onboard: tạo device token + xác nhận config hợp lệ
openclaw onboard --non-interactive --auth-choice ollama --accept-risk
# → OpenClaw tự sinh gateway auth token, ghi vào openclaw.json

# 3. Restart gateway để dùng token mới (kill PID cũ → start lại)
openclaw gateway run &

# 4. Kiểm tra
openclaw health   # → "Agents: main (default), reviewer, tutor"
```

**Giải thích hoạt động của Gateway:**

- Gateway là WebSocket server chạy tại `ws://127.0.0.1:18789`
- Các lệnh `openclaw agent`, `openclaw health` kết nối đến gateway này
- Gateway nhận yêu cầu → gọi Ollama API (`http://127.0.0.1:11434`) → trả kết quả
- Auth token được lưu trong `openclaw.json` để CLI tự dùng, không cần nhập tay

---

### Bước 5 — Tạo Custom Skills (hướng dẫn vai trò cho Agent)

**Vị trí:** `C:\Users\HHC_HOME\.openclaw\skills\<tên-skill>\SKILL.md`

Mỗi skill là một folder chứa file `SKILL.md` với YAML frontmatter và nội dung hướng dẫn hành vi. OpenClaw tự scan và load khi khởi động gateway.

**3 skill đã tạo:**

#### `vn-coder` — Trợ lý code

- **Model:** `ollama/auto_ai-coder`
- **Vai trò:** Viết code, debug, refactor theo phong cách tiếng Việt
- **Quy tắc nội tại:** Code ngắn gọn, không comment thừa, ưu tiên giải pháp đơn giản nhất

#### `vn-reviewer` — Chuyên gia review

- **Model:** `ollama/auto_ai-reviewer`
- **Vai trò:** Phát hiện bug, security issue (OWASP), code smell
- **Format output chuẩn:** `[BUG/SECURITY/QUALITY/IMPROVEMENT] Dòng X: mô tả → gợi ý fix`

#### `vn-tutor` — Gia sư lập trình

- **Model:** `ollama/auto_ai-tutor`
- **Vai trò:** Giải thích khái niệm, ra bài tập, dạy theo phương pháp Socratic
- **Quy tắc:** Analogy trước, code sau; không sửa thẳng khi học viên làm sai

**Kết quả kiểm tra:**

```powershell
openclaw skills list | grep "vn-"
# → ✓ ready   💻 vn-coder
# → ✓ ready   🔍 vn-reviewer
# → ✓ ready   🎓 vn-tutor
```

---

### Bước 6 — Tạo Script PowerShell Tự Động

Vì không có quyền admin để cài Scheduled Task system-wide, tạo 2 script dùng Task Scheduler ở mức user (không cần admin):

**`scripts/start-openclaw-gateway.ps1`** — Khởi động gateway thủ công:

- Kiểm tra port 18789 đã có process chưa (tránh chạy 2 lần)
- Kiểm tra Ollama đang online
- Chạy `openclaw gateway run` dưới dạng background job
- Retry health check 5 lần để xác nhận thành công

**`scripts/register-openclaw-startup.ps1`** — Đăng ký tự khởi động:

- Dùng `New-ScheduledTask` với trigger `AtLogOn` (khi user login)
- Chạy ẩn (`-WindowStyle Hidden`) để không hiện cửa sổ
- Log ra `$env:TEMP\openclaw-gateway-startup.log`
- Không cần `-RunLevel Highest` → không cần admin

**Cách đăng ký (chạy 1 lần):**

```powershell
.\scripts\register-openclaw-startup.ps1
# → Task 'OpenClaw-Gateway-AutoStart' registered.
# → Gateway sẽ tự khởi động khi login lần sau.
```

---

### Bước 7 — Test Thực Tế

**Test 1 — Agent main (coder):**

```powershell
openclaw agent --local --agent main --message "Viết hàm Python đọc file JSON và trả về dict, xử lý FileNotFoundError"
```

Kết quả: Model viết hàm `read_json_file()` với try/except, giải thích bằng tiếng Việt. ✅

**Test 2 — Agent reviewer:**

```powershell
openclaw agent --local --agent reviewer --message "Review code này: def div(a,b): return a/b"
```

Kết quả: Model phát hiện lỗi division-by-zero và đề xuất thêm `if b == 0: raise ValueError(...)`. ✅

**Test 3 — Agent tutor:**

```powershell
openclaw agent --local --agent tutor --message "Closure JavaScript là gì? Giải thích ngắn tiếng Việt."
```

Kết quả: Model giải thích bằng analogy "hộp bút", ví dụ code `createCounter()`, và đặt câu hỏi kiểm tra ngược lại. ✅

---

### Kiến trúc sau tích hợp

```text
Người dùng
    │
    ├─ openclaw agent --local --agent main     ─→ ollama/auto_ai-coder    (qwen2.5-coder 7B)
    ├─ openclaw agent --local --agent reviewer ─→ ollama/auto_ai-reviewer (qwen2.5-coder 7B)
    └─ openclaw agent --local --agent tutor    ─→ ollama/auto_ai-tutor    (gemma4 8B)
                │
         OpenClaw Gateway
         ws://127.0.0.1:18789
                │
         Ollama API
         http://127.0.0.1:11434
```

**Phân chia trách nhiệm sau tích hợp:**

| Tác vụ | Công cụ | Lý do |
| --- | --- | --- |
| Refactor lớn, thiết kế kiến trúc | Claude Code | Cần lý luận sâu, đa file, cloud |
| Viết code, debug nhanh | `openclaw agent --agent main` | Local, miễn phí, tiếng Việt |
| Review code trước commit | `openclaw agent --agent reviewer` | Structured output, local |
| Học khái niệm, hỏi đáp | `openclaw agent --agent tutor` | Socratic method, tiếng Việt |
| Autocomplete inline | Continue.dev + `qwen2.5-coder:1.5b` | Tốc độ cao, không tốn token |

---

### Vấn đề gặp phải (tổng hợp)

| Vấn đề | Nguyên nhân | Giải pháp |
| --- | --- | --- |
| `systemPromptOverride` unrecognized | Field chưa có trong v2026.2.19 | Dùng SKILL.md thay thế |
| Gateway không start | Thiếu `gateway.mode: "local"` | Thêm field vào config |
| `gateway install` bị từ chối | Cần Admin cho schtasks | Dùng user-level scheduled task trong script |
| `--force` lỗi `lsof not found` | `lsof` là UNIX tool, không có trên Windows | Bỏ flag `--force`, kill PID thủ công |
| "session file locked" | Tiến trình cũ giữ lock file | Kill PID bằng Task Manager hoặc `taskkill` |
| Auth token bị reset | `gateway install` (dù fail) tự sinh token mới | Restart gateway sau onboard để dùng token mới |

---

## 5. Nhật ký phiên 2026-05-04 (phần 2) — Update + Zalo

### Mục tiêu

Update OpenClaw lên phiên bản mới nhất và tích hợp Zalo cá nhân (`zalouser`) vào stack.

---

### 5.1 Update OpenClaw v2026.2.19-2 → v2026.5.2

**Lý do update:** Banner CLI thông báo có phiên bản mới khi chạy lệnh.

```powershell
npm install -g openclaw@latest
openclaw --version
# → OpenClaw 2026.5.2 (8b2a6e5)
```

**Thay đổi đáng chú ý trong v2026.5.2:**

- Thêm channel `zalo` và `zalouser` trong danh sách hỗ trợ
- Thêm lệnh `openclaw plugins install` để cài plugin ngoài
- Plugins tăng từ ~4 lên 68 bundled plugins
- Skills tăng từ 8 lên 11 eligible

---

### 5.2 Cài plugin Zalo cá nhân (zalouser)

OpenClaw hỗ trợ 2 loại Zalo:

| Channel    | Gói plugin           | Dùng khi                                                 |
| ---------- | -------------------- | -------------------------------------------------------- |
| `zalo`     | `@openclaw/zalo`     | Zalo Official Account (OA/Bot) — cần App ID + Secret     |
| `zalouser` | `@openclaw/zalouser` | Tài khoản Zalo cá nhân — đăng nhập QR, như WhatsApp Web  |

Cài `zalouser` (tài khoản cá nhân):

```powershell
# Cài plugin qua OpenClaw plugin manager (KHÔNG dùng npm install -g)
openclaw plugins install @openclaw/zalouser

# Kiểm tra plugin đã load
openclaw plugins list | grep zalo
# → zalouser │ enabled │ ~\.openclaw\npm\node_modules\@openclaw\zalouser

# Xem capabilities
openclaw channels capabilities --channel zalouser
# → Zalo Personal default
# → Support: chatTypes=direct,group reactions media blockStreaming
# → Actions: send, broadcast, react
# → Status: not configured, enabled
```

**Lưu ý quan trọng — cài đặt plugin:**

- Plugin phải cài bằng `openclaw plugins install`, KHÔNG phải `npm install -g`
- `npm install -g @openclaw/zalouser` sẽ đặt plugin vào thư mục npm global — OpenClaw không nhận
- OpenClaw cài plugin vào `~/.openclaw/npm/node_modules/` (thư mục riêng)
- Nếu đã cài nhầm bằng npm global, chạy `openclaw plugins install @openclaw/zalouser --force` để ghi đè

**Lỗi gặp phải khi cài:**

```text
Error: plugin path not found: C:\UsersHHC_HOME...  (path bị corrupt)
```

Nguyên nhân: Đã thêm `plugins.load.paths` thủ công vào `openclaw.json` bằng JSON5 — backslash Windows bị parse thành escape sequence. Giải pháp: xóa section `plugins.load.paths` bằng Edit tool, sau đó dùng `openclaw plugins install` (tự quản lý path).

---

### 5.3 Đăng nhập Zalo bằng QR Code

```powershell
# Tạo QR code đăng nhập
openclaw channels login --channel zalouser
# → Scan QR image: D:\TEMP\openclaw\openclaw-zalouser-qr-default.png
```

**Quy trình đăng nhập trên điện thoại:**

1. Mở **Zalo** → nhấn biểu tượng QR (góc trên phải)
2. Quét QR từ file `D:\TEMP\openclaw\openclaw-zalouser-qr-default.png`
3. Điện thoại hiện **"Xác nhận đăng nhập"** → bấm **Xác nhận**
4. CLI nhận xác nhận → lưu session vào `~/.openclaw/agents/main/`

**Trạng thái hiện tại:** QR đã được tạo và quét, nhưng session chưa được xác nhận đầy đủ (timed out). Cần thực hiện lại khi cần dùng Zalo.

**Lệnh kiểm tra sau khi đăng nhập thành công:**

```powershell
openclaw channels list            # phải thấy zalouser trong danh sách
openclaw channels status          # phải thấy trạng thái connected
```

---

### 5.4 Trạng thái sau phiên

**Đã hoàn thành:**

- ✅ OpenClaw cập nhật lên v2026.5.2
- ✅ Plugin `@openclaw/zalouser` đã cài và load thành công (enabled)
- ✅ Gateway restart, healthy với 3 agents (main, reviewer, tutor)

**Đang chờ:**

- ⏳ Đăng nhập Zalo cá nhân — cần quét QR và xác nhận trên điện thoại

**Doctor output sau phiên:**

```text
✅ Plugins: 68 loaded, 0 errors, 25 disabled
✅ Skills: 11 eligible
⚠️  commands.ownerAllowFrom chưa cấu hình (chưa set owner cho bot Zalo)
⚠️  OPENCLAW_GATEWAY_TOKEN mismatch (non-critical, từ phiên trước)
⚠️  Memory search: no active memory plugin registered
```

**Lệnh đăng nhập Zalo lại khi cần:**

```powershell
# Restart gateway trước
openclaw gateway stop
openclaw gateway run &

# Đăng nhập lại Zalo
openclaw channels login --channel zalouser
# Quét QR trong D:\TEMP\openclaw\openclaw-zalouser-qr-default.png
# Xác nhận trên điện thoại trong vòng 60 giây
```

---

## 5b. Nhật ký phiên 2026-05-05 — Hoàn tất tích hợp Zalo

Hoàn tất đăng nhập Zalo cá nhân còn dang dở từ phiên trước (QR bị timeout).

---

### Các bước đã thực hiện

1. **Kiểm tra trạng thái** — Gateway không chạy, channel Zalo "not configured".

2. **Khởi động gateway** bằng `Start-Process powershell -WindowStyle Hidden`.

3. **Chạy login Zalo** — `openclaw channels login --channel zalouser` tạo QR mới tại `D:\TEMP\openclaw\openclaw-zalouser-qr-default.png`. User quét và xác nhận trên điện thoại thành công.

4. **Thêm `channels` config** vào `openclaw.json` — thiếu section này là nguyên nhân channel "not configured":

   ```json
   "channels": {
     "zalouser": { "enabled": true, "dmPolicy": "pairing" }
   }
   ```

5. **Set `commands.ownerAllowFrom`** — lấy Zalo user ID thực bằng `openclaw directory self --channel zalouser` → ID = `2281789073213379000` (Huy Huynh).

6. **Thêm `plugins.allow`** — tắt cảnh báo auto-load: `["zalouser", "ollama"]`.

7. **Restart gateway** — xác nhận log: `[zalouser] [default] starting zalouser provider (Huy Huynh)`.

8. **Probe test** — `openclaw channels status --probe` trả về:
   ```
   Zalo Personal default: enabled, configured, running, dm:pairing, works
   ```

### Vấn đề gặp phải

| Vấn đề | Nguyên nhân | Giải pháp |
| --- | --- | --- |
| Channel "not configured" sau login | Thiếu section `channels` trong `openclaw.json` | Thêm `channels.zalouser.enabled: true` |
| `ownerAllowFrom` dùng sai user ID | Đoán từ cookie zpsid → `201794059` (sai) | Dùng `openclaw directory self --channel zalouser` → `2281789073213379000` |
| Warning `plugins.allow empty` | Plugin zalouser là external, chưa khai báo | Thêm `plugins.allow: ["zalouser", "ollama"]` |
| `@openclaw/zalouser` stale entry | Format sai — dùng short id không phải npm pkg name | Chỉ dùng `zalouser` trong `plugins.allow` |

### Trạng thái sau phiên

- ✅ Zalo Personal: **enabled, configured, running, dm:pairing, works**
- ✅ Owner: `zalouser:2281789073213379000` (Huy Huynh)
- ✅ `plugins.allow`: `["zalouser", "ollama"]`
- ✅ Gateway healthy: 3 agents + Zalo channel

---

## 6. Hướng dẫn Onboard OpenClaw (Tham chiếu đầy đủ)

Phần này là hướng dẫn cấu hình hoàn chỉnh để onboard OpenClaw từ đầu trên Windows. Áp dụng khi cài mới, hoặc khi cần khôi phục sau khi xóa config.

### 6.1 Yêu cầu tiên quyết

| Yêu cầu | Kiểm tra | Cài nếu thiếu |
| --- | --- | --- |
| Node.js ≥ 20 | `node --version` | `winget install OpenJS.NodeJS.LTS` |
| npm ≥ 10 | `npm --version` | Đi kèm Node.js |
| Ollama đang chạy | `curl http://localhost:11434/api/tags` | Tải tại ollama.ai |
| Models đã pull | `ollama list` | Xem mục 2 trong runbook này |

### 6.2 Cài đặt OpenClaw CLI

```powershell
npm install -g openclaw
openclaw --version   # xác nhận: 2026.x.x
```

Sau khi cài, binary nằm tại:
`C:\Users\<user>\AppData\Roaming\npm\openclaw.cmd`

### 6.3 File cấu hình `~/.openclaw/openclaw.json`

OpenClaw đọc config từ `C:\Users\<user>\.openclaw\openclaw.json`. Đây là cấu hình **đầy đủ cho stack auto_ai** (copy nguyên, thay `<TOKEN>` bằng token thực từ bước onboard):

```json
{
  "models": {
    "mode": "merge",
    "providers": {
      "ollama": {
        "baseUrl": "http://127.0.0.1:11434",
        "apiKey": "ollama-local",
        "api": "ollama",
        "models": [
          { "id": "auto_ai-coder",    "name": "auto_ai-coder (qwen2.5-coder 7B)", "contextWindow": 32768, "maxTokens": 8192, "input": ["text"], "cost": {"input":0,"output":0,"cacheRead":0,"cacheWrite":0} },
          { "id": "auto_ai-reviewer", "name": "auto_ai-reviewer (qwen2.5-coder 7B)", "contextWindow": 32768, "maxTokens": 8192, "input": ["text"], "cost": {"input":0,"output":0,"cacheRead":0,"cacheWrite":0} },
          { "id": "auto_ai-tutor",    "name": "auto_ai-tutor (gemma4 8B)", "contextWindow": 32768, "maxTokens": 8192, "input": ["text"], "cost": {"input":0,"output":0,"cacheRead":0,"cacheWrite":0} },
          { "id": "qwen2.5-coder:7b", "name": "qwen2.5-coder 7B (base)", "contextWindow": 32768, "maxTokens": 8192, "input": ["text"], "cost": {"input":0,"output":0,"cacheRead":0,"cacheWrite":0} },
          { "id": "gemma4:latest",    "name": "Gemma4 (8B)", "contextWindow": 32768, "maxTokens": 8192, "input": ["text"], "cost": {"input":0,"output":0,"cacheRead":0,"cacheWrite":0} }
        ]
      }
    }
  },
  "agents": {
    "defaults": {
      "model": { "primary": "ollama/auto_ai-coder", "fallbacks": ["ollama/qwen2.5-coder:7b"] },
      "workspace": "~/.openclaw/workspace",
      "memorySearch": {
        "enabled": true,
        "provider": "openai",
        "model": "nomic-embed-text",
        "remote": {
          "baseUrl": "http://127.0.0.1:11434",
          "apiKey": "ollama"
        }
      }
    },
    "list": [
      { "id": "main",     "default": true, "workspace": "~/.openclaw/workspace", "model": { "primary": "ollama/auto_ai-coder",    "fallbacks": ["ollama/qwen2.5-coder:7b"] } },
      { "id": "reviewer",                  "workspace": "~/.openclaw/workspace", "model": { "primary": "ollama/auto_ai-reviewer", "fallbacks": ["ollama/auto_ai-coder"] } },
      { "id": "tutor",                     "workspace": "~/.openclaw/workspace", "model": { "primary": "ollama/auto_ai-tutor",    "fallbacks": ["ollama/gemma4:latest"] } }
    ]
  },
  "commands": { "native": "auto", "nativeSkills": "auto", "restart": true },
  "gateway": {
    "port": 18789,
    "mode": "local",
    "bind": "loopback",
    "auth": { "mode": "token", "token": "<TOKEN>" },
    "tailscale": { "mode": "off", "resetOnExit": false }
  },
  "skills": { "install": { "nodeManager": "npm" } }
}
```

**Giải thích các trường quan trọng:**

| Trường | Giá trị | Ý nghĩa |
| --- | --- | --- |
| `models.mode` | `"merge"` | Giữ model cloud mặc định, thêm Ollama bên cạnh |
| `providers.ollama.api` | `"ollama"` | Dùng native API, KHÔNG phải `openai-completions` |
| `agents.defaults.memorySearch` | xem trên | Dùng `nomic-embed-text` qua Ollama `/v1/embeddings` để index ngữ cảnh; provider phải là `"openai"` (Ollama giả lập OpenAI compat) |
| `gateway.mode` | `"local"` | Bắt buộc — không có field này gateway sẽ từ chối start |
| `gateway.bind` | `"loopback"` | Chỉ nghe trên `127.0.0.1`, không expose ra mạng |
| `gateway.auth.token` | tự sinh | Token do `openclaw onboard` tạo — CLI tự đọc, không nhập tay |

### 6.4 Chạy Onboard

```powershell
# Bước 1: Khởi động gateway lần đầu (nền)
Start-Process powershell -ArgumentList "-Command openclaw gateway run" -WindowStyle Hidden

# Bước 2: Onboard — tạo device token + validate config
openclaw onboard
# → Chọn Ollama khi hỏi provider
# → OpenClaw tự sinh auth token và ghi vào openclaw.json

# Bước 3: Restart gateway để dùng token mới
# (kill PID cũ trước — tìm PID qua: netstat -ano | findstr ":18789")
taskkill /F /PID <pid>
Start-Process powershell -ArgumentList "-Command openclaw gateway run" -WindowStyle Hidden

# Bước 4: Xác nhận
openclaw health
# → Agents: main (default), reviewer, tutor
```

> **Lưu ý Windows:** Tránh dùng `&` để chạy nền trong PowerShell — dùng `Start-Process` hoặc `Start-Job` thay thế. Flag `--force` của `openclaw gateway` dùng lệnh `lsof` (UNIX only) — không chạy được trên Windows.

### 6.5 Kiểm tra sức khỏe: `openclaw doctor`

Sau onboard, chạy doctor để phát hiện vấn đề còn lại:

```powershell
openclaw doctor
```

**Các vấn đề thường gặp và cách fix:**

| Vấn đề doctor báo | Nguyên nhân | Fix |
| --- | --- | --- |
| `OAuth dir missing (~/.openclaw/credentials)` | Thư mục chưa tạo | `mkdir "$env:USERPROFILE\.openclaw\credentials"` |
| `OPENCLAW_GATEWAY_TOKEN does not match` | Env var stale (từ lần `gateway install` fail) | Bỏ qua — chỉ ảnh hưởng service mode, không ảnh hưởng `gateway run` |
| `Memory search enabled but no embedding provider` | Chưa cấu hình `memorySearch` | Thêm block `memorySearch` vào `agents.defaults`. Dùng `provider: "openai"` với `remote.baseUrl: "http://127.0.0.1:11434"` — Ollama hỗ trợ `/v1/embeddings` OpenAI-compat. `provider: "ollama"` là giá trị **không hợp lệ**. |
| `Shell completion cache missing` | Lần đầu dùng | Tự fix: `openclaw doctor --fix` |

```powershell
openclaw doctor --fix   # auto-apply các fix an toàn
```

### 6.6 Dashboard Web

OpenClaw có giao diện web đầy đủ. Token phải có trong URL hash để xác thực:

```powershell
# Mở dashboard trong browser (tự copy URL + token vào clipboard)
openclaw dashboard

# Hoặc mở thủ công:
# http://127.0.0.1:18789/#token=<token>
```

**Các trang trong dashboard:**

| Trang | URL | Nội dung |
| --- | --- | --- |
| Overview | `/#overview` | Uptime, tick interval, session count, cron jobs |
| Usage | `/#usage` | Biểu đồ usage theo thời gian (token, requests) |
| Agents | `/#agents` | Danh sách agent, model, trạng thái |
| Skills | `/#skills` | Tất cả skills (bundled + custom), trạng thái ready/missing |
| Sessions | `/#sessions` | Lịch sử session keys |
| Logs | `/#logs` | Log real-time từ gateway |
| Config | `/#config` | Cấu hình kết nối WebSocket, token, session key |
| Models | `/#models` | Model providers và model list |
| Chat | `/#chat` | Chat trực tiếp với agent qua dashboard |

> **Lưu ý:** Gateway là WebSocket SPA — mọi route đều trả về cùng HTML, dữ liệu được load qua WebSocket sau khi xác thực token. Không có REST API riêng.

**Config page** (quan trọng khi kết nối từ xa):

```text
WebSocket URL : ws://127.0.0.1:18789
Gateway Token : c1b037237704e562590a6bdb74c043215f14f28ea40fc926  (lấy từ openclaw.json)
Session Key   : (để trống = tự sinh mới mỗi phiên)
```

### 6.7 Custom Skills

Skills định nghĩa persona và behavior cho từng agent. Mỗi skill là một thư mục chứa `SKILL.md`:

```text
~/.openclaw/skills/
├── vn-coder/SKILL.md      💻  Trợ lý code tiếng Việt
├── vn-reviewer/SKILL.md   🔍  Chuyên gia review (OWASP, bug, quality)
└── vn-tutor/SKILL.md      🎓  Gia sư Socratic, ra bài tập
```

**Format `SKILL.md`:**

```markdown
---
name: tên-skill
description: "Mô tả ngắn — dùng khi nào, model nào, KHÔNG dùng khi nào."
metadata:
  { "openclaw": { "emoji": "💻" } }
---

# Nội dung hướng dẫn behavior ở đây
```

```powershell
openclaw skills list          # xem tất cả skills và trạng thái
openclaw skills list | grep vn-   # chỉ xem 3 skills tùy chỉnh
```

Kết quả mong đợi:

```text
✓ ready   💻 vn-coder
✓ ready   🔍 vn-reviewer
✓ ready   🎓 vn-tutor
```

### 6.8 Quản lý Gateway

**Khởi động thủ công:**

```powershell
.\scripts\start-openclaw-gateway.ps1
```

Script này: kiểm tra port 18789, xác nhận Ollama online, start gateway, retry health 5 lần.

**Đăng ký tự khởi động khi login (chỉ chạy 1 lần):**

```powershell
.\scripts\register-openclaw-startup.ps1
# → Task 'OpenClaw-Gateway-AutoStart' đăng ký ở Task Scheduler (user-level, không cần admin)
# → Gateway tự start ẩn sau mỗi lần login
```

**Quản lý Scheduled Task:**

```powershell
# Kiểm tra task đã đăng ký chưa
Get-ScheduledTask -TaskName "OpenClaw-Gateway-AutoStart"

# Xóa nếu không cần nữa
Unregister-ScheduledTask -TaskName "OpenClaw-Gateway-AutoStart" -Confirm:$false

# Xem log startup
Get-Content "$env:TEMP\openclaw-gateway-startup.log"
```

**Auth token:**

Token được lưu trong `openclaw.json` tại `gateway.auth.token`. CLI tự đọc, không cần nhập tay. Nếu cần token mới:

```powershell
openclaw doctor --generate-gateway-token
# Sau đó restart gateway để dùng token mới
```

### 6.9 Tham chiếu lệnh nhanh

```powershell
# Trạng thái
openclaw health                    # agents + heartbeat + sessions
openclaw doctor                    # full diagnostic
openclaw models list               # models đang cấu hình

# Agent (không cần gateway)
openclaw agent --local --agent main     --message "..."   # coding
openclaw agent --local --agent reviewer --message "..."   # review
openclaw agent --local --agent tutor    --message "..."   # học

# Gateway
openclaw gateway run               # chạy gateway (foreground)
openclaw dashboard                 # mở dashboard trong browser
openclaw skills list               # xem tất cả skills

# Quản lý
openclaw doctor --fix              # auto-fix các vấn đề an toàn
openclaw security audit --deep     # kiểm tra bảo mật
```

---

## 7. Vận hành hằng ngày

### Khởi động (sau khi reboot máy)

Gateway tự khởi động nếu đã đăng ký `register-openclaw-startup.ps1`. Kiểm tra nhanh:

```powershell
openclaw health
openclaw channels status
```

Nếu gateway chưa chạy:

```powershell
.\scripts\start-openclaw-gateway.ps1
```

### Kết thúc phiên làm việc

Gateway chạy nền, không cần tắt thủ công. Nếu muốn tắt:

```powershell
# Tìm PID: netstat -ano | findstr ":18789"
taskkill /F /PID <pid>
```

### Sử dụng

- **VSCode + Claude Code:** `Ctrl+Shift+P` → "Claude Code: Start Session" — refactor/review/debug.
- **Zalo:** Nhắn cho chính mình → OpenClaw route tự động đến Gmail/Calendar/AI.
- **Dashboard:** `openclaw dashboard` → `http://127.0.0.1:18789/#overview`

### Test stack nhanh từ terminal

```powershell
openclaw health
openclaw agent --local --agent main --message "Viết hàm Python đảo ngược chuỗi"
openclaw channels status --probe
```

---

## 8. Bảo trì

### Backup trước khi thay đổi

**Bắt buộc** chạy trước khi sửa bất kỳ file cấu hình, script, hoặc nâng cấp hệ thống:

```powershell
.\scripts\backup.ps1                          # backup toàn bộ file quan trọng mặc định
.\scripts\backup.ps1 -Files "path1","path2"   # backup file chỉ định
.\scripts\backup.ps1 -Label "before-update"   # thêm nhãn mô tả vào tên file
```

File backup lưu tại `before_bak\<đường-dẫn-giống-gốc>\<tên>_<timestamp>.ext`.
File ngoài project (như `~/.openclaw/openclaw.json`) lưu dưới `before_bak\_external\`.

Rollback:

```powershell
Copy-Item "before_bak\docs\runbook_20260504_120000.md" "docs\runbook.md" -Force
Copy-Item "before_bak\_external\openclaw\openclaw_20260504_120000.json" `
          "$env:USERPROFILE\.openclaw\openclaw.json" -Force
```

Xem tất cả bản backup:

```powershell
Get-ChildItem before_bak -Recurse -File | Sort-Object LastWriteTime -Descending
```

---

### Cập nhật OpenClaw

```powershell
npm install -g openclaw@latest
openclaw --version

# Restart gateway sau khi update
taskkill /F /IM node.exe   # hoặc dùng PID cụ thể
.\scripts\start-openclaw-gateway.ps1
```

### Cập nhật Node.js dependencies (skills)

```powershell
cd d:\Dba_project\dba_ai\auto_ai
npm update
```

### Đăng nhập lại Zalo (session ~90 ngày)

```powershell
openclaw channels logout --channel zalouser
openclaw channels login --channel zalouser
# Quét QR tại: D:\TEMP\openclaw\openclaw-zalouser-qr-default.png
```

---

## 9. Troubleshoot

| Triệu chứng | Kiểm tra | Fix |
|-------------|----------|-----|
| Gateway không start | `openclaw gateway run` (foreground) | Kiểm tra `gateway.mode: "local"` trong `openclaw.json` |
| Zalo không phản hồi | `openclaw channels status` | Restart gateway; nếu session hết hạn → login lại |
| Gmail skill lỗi authentication | Kiểm tra App Password file | `cat "$env:USERPROFILE\.openclaw\credentials\gmail-app-pass.txt"` phải là 16 ký tự |
| Skill trả 503 | `openclaw skills list` | Kiểm tra skill "ready"; restart gateway |
| `npm install` lỗi | Kiểm tra Node.js version | `node --version` phải ≥ 20 |

---

## 10. Roadmap / việc còn để mở

### Đã hoàn tất

- ✅ **OpenClaw + Zalo Personal** (2026-05-04 / 2026-05-05) — xem Section 5 & 6
- ✅ **Gmail IMAP qua imapflow** (2026-05-06) — thay thế himalaya, kết nối ổn định
- ✅ **CLAUDE.md + docs cleanup** (2026-05-06) — xóa Docker/Ollama/Open-WebUI

### Việc còn lại

- [ ] Hoàn tất `register-skills.ps1` — đăng ký `openclaw-mail-skill.js` thành custom MCP skill
- [ ] Test đầu-cuối: gửi Zalo → OpenClaw nhận → đọc Gmail → trả kết quả
- [ ] `setup-gcalcli.ps1` — tích hợp Google Calendar (đã defer)
- [ ] `send_email` skill — gửi email qua SMTP (imapflow hỗ trợ nodemailer)
- [ ] Backup `~/.openclaw/` định kỳ (chứa session Zalo + credentials)

---

## 11. Liên kết nhanh

- Tổng quan: [README.md](../readme.md)
- Hướng dẫn Claude Code: [CLAUDE.md](../claude.md)
- Cài đặt: [docs/setup.md](setup.md)
- Cách dùng: [docs/usage.md](usage.md)
- Workflow: [docs/workflows.md](workflows.md)


---

!!! info "Nguồn gốc"
    `dba_ai/auto_ai/docs/runbook.md`
