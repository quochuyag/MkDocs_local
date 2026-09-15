---
title: Tối ưu tài liệu cho NotebookLM
course: 07-sach-va-tai-lieu
source: pdf_md/references/notebooklm-tips.md
---

# Tối ưu tài liệu cho NotebookLM

## Định dạng tốt nhất cho NotebookLM

NotebookLM đọc tốt nhất với:
- **Markdown có cấu trúc rõ ràng** — headings H1, H2, H3
- **Đoạn văn ngắn** — mỗi đoạn 3–5 câu
- **Bullet points** — giúp AI trích xuất thông tin chính xác hơn
- **Thuật ngữ nhất quán** — dùng một tên duy nhất cho mỗi khái niệm

## Những gì NÊN có trong file guide để NotebookLM phát huy tối đa

- ✅ Định nghĩa rõ ràng cho mỗi khái niệm
- ✅ Câu hỏi và gợi ý trả lời (giúp tạo quiz tốt hơn)
- ✅ Bảng so sánh (NotebookLM xử lý table rất tốt)
- ✅ Ví dụ cụ thể với tên công ty/tổ chức thực
- ✅ Từ khóa quan trọng xuất hiện nhiều lần tự nhiên

## Những gì NÊN TRÁNH

- ❌ Sơ đồ ASCII phức tạp (NotebookLM không render tốt)
- ❌ Inline code block dài (```code```) không liên quan đến nội dung học
- ❌ Bảng quá nhiều cột (>5 cột)
- ❌ Footnote/endnote kiểu academic

## Cách thêm nguồn vào NotebookLM

### Từ Google Drive (cách khuyến nghị):
1. Mở https://notebooklm.google.com
2. Tạo hoặc mở Notebook
3. Click **"+ Add source"**
4. Chọn **"Google Drive"**
5. Tìm file trong folder `NotebookLM-Books`
6. Click **"Insert"**

### Giới hạn cần biết:
- Tối đa **50 nguồn** mỗi Notebook
- Mỗi nguồn tối đa **500,000 từ**
- Định dạng hỗ trợ: PDF, Google Doc, Google Slide, text, Markdown (qua Drive)

## Gợi ý cấu trúc Notebook học sách

```
Notebook: "[Tên sách]"
├── Source 1: 04_chapter-1_guide.md
├── Source 2: 05_chapter-2_guide.md
├── Source 3: 06_chapter-3_guide.md
...
└── Source N: [chapter cuối]_guide.md
```

Sau khi thêm đủ chapters, dùng NotebookLM để:
- Tạo **Study Guide** tổng hợp toàn sách
- Tạo **FAQ** từ câu hỏi ôn tập
- Tạo **Audio Overview** để nghe khi di chuyển
- Chat hỏi đáp về nội dung bất kỳ


---

!!! info "Nguồn gốc"
    `pdf_md/references/notebooklm-tips.md`
