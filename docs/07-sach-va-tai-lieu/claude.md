---
title: CLAUDE.md
course: 07-sach-va-tai-lieu
source: pdf_md/CLAUDE.md
---

# CLAUDE.md

> Đây là bộ nhớ chính của Claude Code cho dự án học từ sách.
> Đọc file này **trước tiên** trước mọi thao tác trong session.

---

## 🎯 Mục tiêu dự án

Đọc các file `.md` chapter (đã có sẵn trong thư mục sách) và tạo **bài học study guide** chất lượng cao bằng tiếng Việt, tối ưu cho NotebookLM và tự học.

**Không cần xử lý PDF.** Pipeline PDF → MD đã hoàn chỉnh và không thuộc phạm vi nhiệm vụ này.

---

## 📁 Cấu trúc thư mục

```
pdf_md/                                  ← Root của dự án
│
├── CLAUDE.md                            ← File này
├── STATUS.md                            ← Tổng tiến độ tất cả sách
│
├── references/
│   ├── guide-structure.md               ← Template đầy đủ của guide
│   └── notebooklm-tips.md               ← Quy tắc format cho NotebookLM
│
├── <book-slug>/                         ← Thư mục mỗi cuốn sách
│   ├── STATUS.md                        ← Tiến độ riêng của sách này
│   ├── 00_front-matter.md               ← Chapter files (đã có sẵn)
│   ├── 01_chapter-one.md
│   ├── 02_chapter-two.md
│   └── guide_ai/                        ← Output: guide do Claude tạo
│       ├── 01_chapter-one_guide.md
│       └── 02_chapter-two_guide.md
│
└── tools/                               ← Scripts Python (không dùng trong task này)
    ├── pdf2md.py
    ├── pdf_parser.py
    ├── md_writer.py
    └── utils.py
```

### Ví dụ thực tế trong dự án

```
itil-foundation-v5/
├── STATUS.md
├── 01_introduction.md
├── 02_key-concepts.md
└── guide_ai/
    └── 01_introduction_guide.md

oracle-cloud-infrastructure-a-guide-to-building-/
├── STATUS.md
├── 00_front-matter.md
├── 01_introduction.md
└── guide_ai/
    └── 01_introduction_guide.md
```

---

## 🔄 Quy trình làm việc (Workflow)

### Bước 1 — Bắt đầu session

1. Đọc `STATUS.md` của sách đang làm việc để biết chapter nào còn `❌`
2. Hỏi người dùng: "Bắt đầu từ chapter nào?" nếu chưa rõ
3. Xác nhận đường dẫn file nguồn trước khi đọc

### Bước 2 — Đọc chapter nguồn

- Đọc file `<book-slug>/XX_chapter-title.md`
- Nắm rõ: số chapter, tiêu đề, các section chính, thuật ngữ quan trọng
- **Không dịch thẳng** — phân tích rồi viết lại bằng ngôn ngữ dễ hiểu

### Bước 3 — Tạo guide

- Tạo file `<book-slug>/guide_ai/XX_chapter-title_guide.md`
- Theo đúng **9 sections** trong phần Guide Structure bên dưới
- Ngôn ngữ: **Tiếng Việt là chính**, giữ nguyên thuật ngữ tiếng Anh (có giải thích trong ngoặc)

### Bước 4 — Cập nhật STATUS.md

Sau khi tạo xong guide:
1. Đổi `❌` → `✅` cho chapter vừa xong
2. Cập nhật `Cập nhật lần cuối` và `Tiến độ` ở đầu file
3. Nếu người dùng nói **"xong" / "done" / "kết thúc"** → ghi thêm vào bảng Lịch sử session

---

## 📝 Guide Structure — 9 sections bắt buộc theo thứ tự

### Section 1 — Header

```markdown
# [Tiêu đề chapter bằng tiếng Việt]

| Trường        | Nội dung                              |
|---------------|---------------------------------------|
| 📚 Nguồn      | Tên sách — Chapter XX                 |
| 📅 Ngày tạo   | YYYY-MM-DD                            |
| ⏱ Thời gian   | ~XX phút                              |
| 🔢 Phiên bản  | Guide v1.0                            |
```

### Section 2 — 🎯 Mục tiêu học tập

5–7 bullet points, dùng động từ hành động:

```markdown
Sau khi học xong chapter này, bạn có thể:
- **Hiểu** được...
- **Phân biệt** được...
- **Mô tả** được...
- **Áp dụng** được...
- **Đánh giá** được...
```

### Section 3 — 📋 Tóm tắt nội dung chính

- Độ dài: **300–500 từ**
- Theo đúng thứ tự các section trong sách
- Paraphrase, không dịch literal
- Giữ thuật ngữ tiếng Anh + giải thích tiếng Việt trong ngoặc: `Service Management (Quản lý Dịch vụ)`

### Section 4 — 🔑 Khái niệm quan trọng

Bảng 4 cột, 5–10 khái niệm:

```markdown
| Khái niệm | Định nghĩa | Tại sao quan trọng | Ví dụ thực tế |
|-----------|------------|-------------------|---------------|
| ...       | ...        | ...               | ...           |
```

### Section 5 — 🌍 Ví dụ thực tế & Case Study

2–3 case studies, mỗi case theo cấu trúc:

```markdown
#### Case Study: [Tên tình huống]

- **Bối cảnh:** ...
- **Vấn đề:** ...
- **Giải pháp:** ...
- **Kết quả:** ...
- **Bài học:** ...
```

Ưu tiên ví dụ gắn với **bối cảnh Việt Nam** 🇻🇳 khi phù hợp.

### Section 6 — 📊 Sơ đồ & Bảng tổng hợp

1–3 bảng so sánh hoặc flow dạng text (không dùng ASCII art phức tạp).

Ví dụ bảng so sánh:

```markdown
| Tiêu chí     | Phương án A | Phương án B |
|--------------|-------------|-------------|
| Tốc độ       | Nhanh       | Chậm hơn    |
| Chi phí      | Cao         | Thấp hơn    |
```

### Section 7 — ❓ Câu hỏi ôn tập

Đúng 5 câu hỏi theo tỷ lệ:
- 2 câu **nhớ lại** (Recall) — định nghĩa, liệt kê
- 2 câu **hiểu sâu** (Comprehension) — so sánh, giải thích tại sao
- 1 câu **áp dụng** (Application) — tình huống thực tế

Mỗi câu hỏi bắt buộc có:

```markdown
**Câu X:** [Nội dung câu hỏi]

💡 **Gợi ý:** [Một câu gợi ý hướng suy nghĩ, không tiết lộ đáp án]

📝 **Đáp án:** [3–6 câu giải thích đầy đủ, đủ rõ để người mới hiểu mà không cần đọc lại sách]
```

### Section 8 — 💡 Ghi nhớ nhanh

5–7 bullets tổng kết:

```markdown
- ✅ [Điểm quan trọng cần nhớ]
- ✅ [Điểm quan trọng cần nhớ]
- ⚠️ [Lỗi thường gặp / hiểu sai phổ biến]
- ⚠️ [Lỗi thường gặp]
- 🔗 Chapter tiếp theo sẽ bàn về: [tên chủ đề]
```

### Section 9 — 📖 Giải thích thuật ngữ chuyên ngành

Mỗi thuật ngữ theo cấu trúc:

```markdown
#### **[English Term]** — [Nghĩa tiếng Việt]

**Định nghĩa:** [1–2 câu, không dùng jargon trong định nghĩa]

**Ví dụ/Tương tự:** [Một ví dụ cụ thể hoặc phép so sánh dễ hiểu]

**Tại sao quan trọng trong chapter này:** [1 câu]
```

---

## ✅ Quy tắc Format (NotebookLM-optimized)

**NÊN làm:**
- Heading hierarchy rõ ràng: H1 → H2 → H3
- Đoạn văn ngắn: 3–5 câu mỗi đoạn
- Dùng bullet list cho các danh sách
- Một tên duy nhất cho mỗi khái niệm — nhất quán xuyên suốt
- Bảng so sánh ≤ 5 cột
- Lặp lại key terms tự nhiên qua các section

**TRÁNH:**
- ASCII diagram phức tạp
- Code block dài không liên quan nội dung
- Bảng > 5 cột
- Footnote kiểu học thuật
- Dịch literal từng câu từ sách gốc

**NotebookLM limits:**
- Tối đa 50 sources mỗi Notebook, 500,000 words mỗi source
- Upload qua Google Drive folder `NotebookLM-Books`
- 1 Notebook mỗi sách, 1 source mỗi chapter guide

---

## 📊 STATUS.md — Tracking tiến độ

### Vị trí file

- **Cấp sách:** `<book-slug>/STATUS.md` — theo dõi chapters của sách đó
- **Cấp project:** `pdf_md/STATUS.md` — tổng hợp tất cả sách

### Khi nào cập nhật

| Sự kiện | Hành động |
|---------|-----------|
| Tạo xong 1 guide | Đổi `❌` → `✅`, ghi ngày |
| Người dùng nói "xong" / "done" / "kết thúc" | Ghi vào bảng Lịch sử session |
| Bắt đầu session mới | Đọc STATUS.md trước để biết còn gì chưa làm |

### Format STATUS.md

```markdown
# STATUS — [Tên sách]

**Cập nhật lần cuối:** YYYY-MM-DD
**Tiến độ:** X/Y chapters hoàn thành

---

## Danh sách chapters

| # | File nguồn | Tiêu đề ngắn | Guide | Ngày hoàn thành |
|---|------------|--------------|-------|-----------------|
| 01 | 01_intro.md | Introduction to ... | ✅ | 2026-04-25 |
| 02 | 02_concepts.md | Key Concepts | ❌ | — |

---

## Lịch sử session

| Ngày | Chapters hoàn thành | Ghi chú |
|------|---------------------|---------|
| 2026-04-25 | Ch.01 | Session đầu tiên |
```

---

## 🔍 Kiểm tra chất lượng guide (Quality Check)

Sau khi tạo xong guide, **bắt buộc** đối chiếu lại với file nguồn theo checklist này trước khi báo hoàn thành:

### Checklist nội dung

| Hạng mục | Câu hỏi kiểm tra |
| --- | --- |
| **Tóm tắt đủ section** | Mọi heading `##` trong nguồn đều có trong Section 3 chưa? |
| **Lợi ích đủ số** | Nếu nguồn liệt kê N lợi ích, guide có đủ N lợi ích không? |
| **Chi tiết kỹ thuật** | Số liệu cụ thể (GB, IOPS, giờ, giá...) có được giữ lại không? |
| **Note/Warning** | Các khung Note/Warning trong nguồn đã được xử lý chưa? |
| **Free Tier đầy đủ** | Nếu chương có Free Tier — liệt kê đủ mọi nhóm dịch vụ không? |
| **SLA và điều kiện** | Các điều kiện/constraint quan trọng (account limit, SLA...) có ghi không? |
| **Đội ngũ/vai trò** | Nếu có bảng vai trò/team — đã liệt kê đủ tên từng vai trò chưa? |
| **Feedback loop & văn hóa** | Các yếu tố soft (collaboration, feedback loop, training) có trong guide không? |

### Checklist format (Markdown)

- Danh sách sau dấu `:` phải có **dòng trống** trước item đầu tiên
- Case Study dùng heading `###` (không dùng `####` nếu section cha là `##`)
- Bảng separator dùng `| --- |` với khoảng trắng hai bên
- Heading trong Section 9 (thuật ngữ) dùng `####` đồng nhất

### Khi phát hiện thiếu nội dung

1. Bổ sung vào đúng section tương ứng (không tạo section mới ngoài 9 sections)
2. Cập nhật version header: `Guide v1.0` → `Guide v1.1`
3. Cập nhật `⏱ Thời gian` nếu nội dung tăng đáng kể

---

## 🚦 Quy tắc ưu tiên khi làm việc

1. **Đọc STATUS.md trước** — không bắt đầu mà không biết tiến độ hiện tại
2. **Một chapter một lúc** — hoàn thành và cập nhật STATUS trước khi sang chapter tiếp
3. **Hỏi khi không chắc** — nếu file nguồn không tìm thấy hoặc nội dung không rõ
4. **Không tự ý sửa file nguồn** — chỉ đọc chapter `.md`, không chỉnh sửa
5. **Tiếng Việt là ngôn ngữ chính** của guide — thuật ngữ chuyên ngành giữ tiếng Anh

---

## 🔖 Tham chiếu nhanh

| Tài liệu | Đường dẫn | Mục đích |
|----------|-----------|----------|
| Template guide đầy đủ | `references/guide-structure.md` | Xem ví dụ mẫu hoàn chỉnh |
| NotebookLM tips | `references/notebooklm-tips.md` | Quy tắc format chi tiết |
| Status tổng | `pdf_md/STATUS.md` | Tổng tiến độ tất cả sách |


---

!!! info "Nguồn gốc"
    `pdf_md/CLAUDE.md`
