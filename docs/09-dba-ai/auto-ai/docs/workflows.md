---
title: Workflow đề xuất theo loại tác vụ
course: 09-dba-ai
source: dba_ai/auto_ai/docs/workflows.md
---

# Workflow đề xuất theo loại tác vụ

Đây là gợi ý — không bắt buộc. Mỗi workflow nói rõ: dùng công cụ gì, vì sao, và bước cụ thể.

---

## 1. Học một concept mới

**Công cụ:** Claude Code `/learn`.

**Bước:**

1. Trong VSCode, mở Claude Code session.
2. Gõ: `/learn <concept>` — ví dụ `/learn async/await trong Python`.
3. `learning-tutor` agent giảng → kiểm tra hiểu bằng câu hỏi ngược.
4. Yêu cầu bài tập: "Cho em 1 bài dễ về X."
5. Làm bài → paste code đã viết → tutor sửa.
6. Khi đã hiểu, mở dự án thật và áp dụng. Nếu kẹt, `/explain` thêm.

**Tránh:** Đừng hỏi "tóm tắt cho em 50 thứ về X" — overwhelming và vô dụng.

---

## 2. Viết tính năng mới (1–3 file)

**Công cụ:** Claude Code (chính).

**Bước:**

1. Trong VSCode, mở Claude Code session.
2. Mô tả tính năng cụ thể: "Anh muốn thêm endpoint POST /api/orders nhận body {items, customer_id}, validate, lưu DB."
3. Claude sẽ:
   - Đọc code hiện tại để hiểu pattern (router, model, validator).
   - Đề xuất plan trước khi viết.
   - Sau khi anh OK, viết tuần tự — anh review từng file.
4. Sau khi xong: chạy `/quality-checker` (subagent) để verify lint/test pass.

---

## 3. Refactor module lớn (4+ file)

**Công cụ:** Chỉ Claude Code (Opus).

**Bước:**

1. Mô tả mục tiêu refactor và **constraint** (giữ API cũ? giữ test cũ?).
2. Yêu cầu: "Em làm plan trước, đừng viết code vội."
3. Claude trả plan → anh review, sửa.
4. OK plan → Claude làm tuần tự, mỗi file là 1 bước.
5. Sau mỗi bước → chạy test → có pass không.
6. Cuối cùng: `/review` toàn bộ thay đổi.

---

## 4. Review pull request

**Công cụ:** Claude `/review`.

**Bước:**

1. Checkout branch PR: `git checkout pr-branch`.
2. Trong Claude Code: `/review`.
3. Đọc report → quyết định:
   - `[CRITICAL]` / `[MAJOR]` → comment yêu cầu fix.
   - `[MINOR]` / `[NIT]` → bỏ qua nếu không quá quan trọng.
4. Nếu PR là của chính anh: `/review` trước, fix luôn rồi mới push.

---

## 5. Debug bug khó tái hiện

**Công cụ:** Claude Code + `stability-guard` agent.

**Bước:**

1. Mô tả bug đầy đủ: "Khi A và B chạy song song, đôi khi C ra giá trị Y thay vì X. Tần suất: 1/100 request."
2. Yêu cầu: "Em phân tích race condition giúp anh."
3. Claude sẽ:
   - Đọc code A, B, C và state liên quan.
   - Liệt kê kịch bản có thể gây ra bug.
4. Reproduce bug bằng test case do Claude đề xuất.
5. Fix → verify bằng test mới.

---

## 6. Code đang viết dở dang (TODO khắp nơi)

**Công cụ:** Claude `/complete`.

**Bước:**

1. `/complete` → Claude liệt kê tất cả TODO/NotImplementedError trong repo.
2. Chọn cái cần làm trước.
3. Claude đọc context, viết, chạy test.
4. Tiếp tục cái khác — hoặc nhóm lại nếu liên quan.

---

## 7. Đảm bảo code ổn định trước deploy production

**Công cụ:** Claude `/stabilize` + `quality-checker`.

**Bước:**

1. `/quality-checker` — verify lint, type, test, coverage pass.
2. `/stabilize <module quan trọng>` — phân tích race, edge case, error handling.
3. Đọc rủi ro `[HIGH]` → fix.
4. Thêm test case mà `stabilize` đề xuất.
5. Chạy lại `/quality-checker` → tất cả xanh thì deploy.

---

## 8. Xử lý email / lịch nhanh từ điện thoại

**Công cụ:** Zalo → OpenClaw → Gmail skill / Calendar.

**Bước:**

1. Mở Zalo, nhắn cho chính mình.
2. Viết tự nhiên: "Inbox mới nhất", "Tìm email từ boss", "Hôm nay có lịch gì".
3. `assistant-orchestrator` agent hiểu ý định → gọi đúng tool.
4. Kết quả trả về Zalo trong vài giây.

**Lưu ý:** Gateway phải đang chạy. Nếu Zalo không có phản hồi:

```powershell
openclaw health
openclaw channels status
```

---

## 9. Học code bằng cách đọc dự án mã nguồn mở

**Công cụ:** Claude `/explain`.

**Bước:**

1. Clone repo → mở VSCode → Claude Code session.
2. Bắt đầu từ entry point (`main.py`, `index.ts`...): `/explain main`.
3. Khi gặp khái niệm lạ → hỏi Claude: "Giải thích X là gì."
4. Tiếp tục `/explain` các module liên quan.
5. Sau khi hiểu, thử thay đổi nhỏ (ví dụ: thêm log, đổi config) → chạy → quan sát.

---

## Anti-pattern (đừng làm)

| Việc                                          | Vì sao tránh                                      |
|-----------------------------------------------|---------------------------------------------------|
| Hỏi "có bug không" mà không paste code         | LLM phải đoán → bịa ra bug giả tưởng             |
| Dùng Claude cho refactor lớn mà không có plan  | Dễ đi lạc context → output nửa vời               |
| Yêu cầu Claude "code thật giỏi vào"            | Vô nghĩa — nói rõ ràng & cụ thể luôn             |
| Cho Claude tự chạy `git push --force`          | Đã chặn trong `.claude/settings.json`            |
| Nhắn Zalo khi gateway chưa chạy               | Tin nhắn mất — không có retry queue              |


---

!!! info "Nguồn gốc"
    `dba_ai/auto_ai/docs/workflows.md`
