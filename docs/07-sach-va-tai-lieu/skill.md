---
title: Book Study Guide — Tạo Bài Giảng Từ Sách
course: 07-sach-va-tai-lieu
source: pdf_md/SKILL.md
---

---
name: book-study-guide
description: |
  Tạo bài giảng học tập chi tiết bằng tiếng Việt từ các file chapter sách (.md).
  Dùng khi người dùng nói "tạo bài giảng", "tạo guide cho chapter", "học chapter này",
  "tạo tài liệu học tập", "tạo study guide", "học cuốn sách này", "tạo bài học từ file md",
  hoặc yêu cầu học/ôn tập nội dung từ file chapter bất kỳ.
  Đảm bảo dùng skill này bất cứ khi nào người dùng muốn học từ file md sách,
  tạo guide học tập, hoặc chuẩn bị tài liệu để đưa lên NotebookLM.
license: MIT
metadata:
  author: user
  version: 1.0.0
---

# Book Study Guide — Tạo Bài Giảng Từ Sách

## Tổng quan

Skill này đọc file chapter sách định dạng `.md`, tạo bài giảng học tập chuyên sâu bằng **tiếng Việt** (file `x_guide.md`), lưu vào thư mục `bai-hoc/`, rồi upload lên Google Drive để chuẩn bị đưa vào NotebookLM. Mỗi bài giảng gồm 5 phần: tóm tắt, khái niệm, ví dụ thực tế, sơ đồ/bảng, và câu hỏi ôn tập.

---

## Khi nào dùng skill này

- Người dùng upload hoặc chỉ định file chapter dạng `.md` và muốn học nội dung
- Người dùng muốn tạo bài học tiếng Việt từ sách tiếng Anh
- Người dùng muốn chuẩn bị tài liệu học tập cho NotebookLM
- Người dùng muốn tạo guide cho một hoặc nhiều chapter liên tiếp

**Không dùng khi:** Người dùng chỉ hỏi câu hỏi nhanh về nội dung sách (trả lời trực tiếp); hoặc muốn dịch nguyên văn file (không phải tạo bài giảng).

---

## Quy trình thực hiện

### Bước 1: Xác định file chapter cần xử lý

Kiểm tra đầu vào từ người dùng:

- **Nếu người dùng upload file** → Đọc file đó, xác định số chapter từ tên file (vd: `04_chapter-1-...md` → chapter 1, prefix `04`)
- **Nếu người dùng chỉ định tên** → Xác nhận file tồn tại trong `/mnt/user-data/uploads/`
- **Nếu người dùng muốn xử lý nhiều chapter** → Hỏi rõ danh sách hoặc phạm vi

**Tên file output:** Giữ nguyên prefix số, thêm `_guide` → vd: `04_chapter-1_guide.md`

**Thư mục lưu:** `bai-hoc/` (tạo nếu chưa có)

---

### Bước 2: Đọc và phân tích nội dung chapter

Đọc toàn bộ file chapter. Xác định:

- Chủ đề chính của chapter
- Các section/heading chính
- Khái niệm kỹ thuật quan trọng (in đậm, định nghĩa rõ ràng)
- Case study / ví dụ thực tế được đề cập
- Bảng, hình, mô hình trong sách

**QUAN TRỌNG:** Không dịch nguyên văn. Mục tiêu là **diễn giải, giải thích và dạy lại** nội dung bằng tiếng Việt dễ hiểu cho người học.

---

### Bước 3: Tạo file bài giảng `x_guide.md`

Viết bài giảng theo cấu trúc chuẩn sau (xem `references/guide-structure.md`):

```
# [Số Chapter]: [Tên Chapter — tiếng Việt]

## 🎯 Mục tiêu học tập
## 📋 Tóm tắt nội dung chính
## 🔑 Khái niệm quan trọng
## 🌍 Ví dụ thực tế & Case Study
## 📊 Sơ đồ & Bảng tổng hợp
## ❓ Câu hỏi ôn tập
## 💡 Ghi nhớ nhanh (Key Takeaways)
```

Lưu file vào thư mục `bai-hoc/`.

**Kết quả mong đợi:** File `bai-hoc/04_chapter-1_guide.md` được tạo thành công.

---

### Bước 4: Upload lên Google Drive

Sau khi file được tạo, dùng Google Drive MCP để upload:

1. Tìm hoặc tạo folder `NotebookLM-Books` trên Drive (nếu chưa có)
2. Upload file `x_guide.md` vào folder đó
3. Lấy link chia sẻ của file

```
Tool: Google Drive MCP
Action: Upload file bai-hoc/x_guide.md → folder NotebookLM-Books
```

**Nếu Drive MCP không kết nối:** Thông báo cho người dùng file đã được tạo tại `bai-hoc/`, hướng dẫn upload thủ công.

---

### Bước 5: Hướng dẫn thêm vào NotebookLM

Sau khi upload Drive thành công, cung cấp hướng dẫn:

```
📌 Cách thêm vào NotebookLM:
1. Mở https://notebooklm.google.com
2. Tạo Notebook mới hoặc mở Notebook hiện có
3. Click "+ Add source" → chọn "Google Drive"
4. Tìm file "[tên file]_guide.md" trong folder NotebookLM-Books
5. Click "Insert" → file đã được thêm vào Notebook
```

---

## Cấu trúc bài giảng chi tiết

Mỗi section trong file `x_guide.md` cần viết như sau:

### 🎯 Mục tiêu học tập
- 3–5 bullet points: "Sau chapter này, bạn sẽ hiểu được..."
- Dùng động từ hành động: hiểu, phân biệt, áp dụng, đánh giá

### 📋 Tóm tắt nội dung chính
- Tóm tắt theo từng section của sách
- Mỗi section: 3–5 câu, ngôn ngữ đơn giản, dễ hiểu
- Giữ nguyên thuật ngữ tiếng Anh chuyên ngành, kèm giải thích tiếng Việt

### 🔑 Khái niệm quan trọng
Format cho mỗi khái niệm:
```
**[Tên khái niệm]** *(tên tiếng Anh nếu có)*
Định nghĩa: [1–2 câu rõ ràng]
Tại sao quan trọng: [1 câu]
Ví dụ: [1 ví dụ cụ thể]
```

### 🌍 Ví dụ thực tế & Case Study
- Lấy case study từ sách, diễn giải lại bằng tiếng Việt
- Thêm phân tích: Bài học rút ra là gì?
- Nếu có thể, liên hệ với bối cảnh Việt Nam/châu Á

### 📊 Sơ đồ & Bảng tổng hợp
- Tái tạo bảng từ sách bằng Markdown table
- Tạo sơ đồ dạng text/ASCII nếu cần thể hiện quy trình
- Tổng hợp so sánh các khái niệm liên quan

### ❓ Câu hỏi ôn tập
- 5 câu hỏi: mix giữa nhớ (2), hiểu (2), áp dụng (1)
- Kèm gợi ý trả lời ngắn (không phải đáp án đầy đủ)

### 💡 Ghi nhớ nhanh
- 5–7 bullet points: những điều PHẢI nhớ từ chapter này
- Ngắn gọn, dễ nhớ, có thể dùng để flashcard

---

## Ví dụ thực tế

### Ví dụ 1: Tạo guide cho một chapter

**Người dùng nói:** "Tạo bài giảng cho chapter 1 này" (kèm upload file)

**Claude sẽ:**
1. Đọc file `04_chapter-1-designing-performance-based-strategic-planning-systems.md`
2. Phân tích: chủ đề là IT Strategic Planning, các section chính là IT Roadmap, Strategic Planning, Strategy Implementation
3. Tạo file `bai-hoc/04_chapter-1_guide.md` với đầy đủ 7 sections bằng tiếng Việt
4. Upload lên Google Drive folder `NotebookLM-Books`
5. Cung cấp link Drive + hướng dẫn thêm vào NotebookLM

**Kết quả:** File guide tiếng Việt ~500–800 dòng, sẵn sàng học trên NotebookLM.

---

### Ví dụ 2: Tạo guide nhiều chapter

**Người dùng nói:** "Tạo bài giảng cho chapter 1 đến chapter 3"

**Claude sẽ:**
1. Xác nhận 3 file tương ứng có sẵn
2. Xử lý tuần tự từng chapter (1 → 2 → 3)
3. Tạo 3 file guide riêng biệt trong `bai-hoc/`
4. Upload cả 3 lên Drive cùng folder
5. Báo cáo tổng kết: 3/3 file hoàn thành, kèm links

---

## Xử lý lỗi thường gặp

### Lỗi: File chapter không đọc được hoặc bị cắt ngắn

**Nguyên nhân:** File quá dài, bị truncate khi đọc

**Giải pháp:**
1. Dùng `bash_tool` để đọc file theo phần: `head -n 200`, sau đó `tail -n +200`
2. Hoặc dùng `view` tool với `view_range` để đọc từng đoạn
3. Tổng hợp tất cả phần trước khi viết guide

---

### Lỗi: Google Drive MCP không upload được

**Nguyên nhân:** Chưa kết nối Drive MCP hoặc hết quyền

**Giải pháp:**
1. Thông báo: "File đã được tạo tại `bai-hoc/x_guide.md`"
2. Hướng dẫn download file từ output
3. Hướng dẫn upload thủ công lên Drive → NotebookLM

---

### Lỗi: Nội dung chapter quá chuyên ngành, khó diễn giải

**Nguyên nhân:** Sách dùng thuật ngữ kỹ thuật dày đặc

**Giải pháp:**
1. Giữ nguyên thuật ngữ gốc tiếng Anh
2. Thêm giải thích trong ngoặc đơn
3. Dùng ví dụ quen thuộc để minh họa
4. Đánh dấu rõ phần nào cần đọc tài liệu gốc để hiểu sâu hơn

---

## Tham khảo thêm

- Xem `references/guide-structure.md` để biết chi tiết cấu trúc từng section
- Xem `references/notebooklm-tips.md` để tối ưu tài liệu cho NotebookLM


---

!!! info "Nguồn gốc"
    `pdf_md/SKILL.md`
