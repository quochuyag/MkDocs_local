---
title: README — Giải thích thiết kế System Prompt Oracle DBA
course: 04-rac-administration
source: The-Oracle-Database-RAC-Administration-Course/oracle_dba_README.md
---

# README — Giải thích thiết kế System Prompt Oracle DBA

Tài liệu này giải thích **tại sao** system prompt được thiết kế như vậy,
ánh xạ từng quyết định thiết kế về 6 nguyên tắc từ bài học.

---

## 🗺️ Nguyên tắc → Thiết kế cụ thể

---

### 1. Generic Response Fix → Role + Audience cực kỳ cụ thể

**Nguyên tắc:** Generic response xảy ra khi thiếu context về WHO và FOR WHOM.

**Áp dụng:**
> "Senior Oracle DBA Instructor với 15+ năm... dạy cho Senior DBA và Expert-level"

Không chỉ nói "bạn là Oracle expert" — prompt nêu rõ:
- Background của instructor (RAC, Data Guard, Exadata)
- Audience level (senior/expert, không cần giải thích cơ bản)
- Implication cho tone (peer-to-peer, không patronizing)

Kết quả: Claude không bắt đầu bằng "Transaction là quá trình..."

---

### 2. 4D Framework → Cả 4 chiều đều có mặt

**Nguyên tắc:** Không chỉ Description (giao thế nào) — cần cả Delegation, Discernment, Diligence.

| Chiều | Áp dụng trong file |
|---|---|
| **Delegation** (giao gì) | "Tạo 2 output: Lecture Notes + Lab Exercises" — rõ deliverable |
| **Description** (giao thế nào) | Cấu trúc 6 sections cho Lecture, 3 exercises cho Lab |
| **Discernment** (đánh giá) | Section "SELF-CHECK trước khi deliver" — Claude tự evaluate |
| **Diligence** (trách nhiệm) | `[⚠️ verify with MOS]` — đánh dấu uncertain claims, không hallucinate |

---

### 3. Iteration Mindset → "Cách sử dụng" có sẵn feedback templates

**Nguyên tắc:** Prompt đầu = draft, phải có feedback specific, know when to restart.

**Áp dụng:** Cuối file có sẵn 3 user message mẫu:
- Lệnh chuẩn để chạy
- Lệnh khi chỉ cần 1 output
- **Template feedback cụ thể** khi output chưa đúng

```
Lab Exercise 3 chưa đủ phức tạp — thêm ambiguity vào Evidence Provided,
và Debrief Questions cần hướng đến architectural implications hơn.
```

Feedback này chỉ đúng root cause (ambiguity, architectural scope),
không phải "làm lại đi" — tránh fix symptom.

---

### 4. Delegation-Diligence Loop → Constraints chống hallucination

**Nguyên tắc:** Validate trước khi trust — build confidence có căn cứ.

**Áp dụng trong CONSTRAINTS section:**
- ✅ "Mỗi claim kỹ thuật phải cụ thể (tên parameter, view, component)"
- ✅ "Lab scenario phải dựa trên nội dung chapter, không hallucinate topic ngoài"
- ✅ Gắn `[⚠️ verify with MOS]` cho claims không chắc

**Cách validate output (Lightweight Eval):**
Lần đầu dùng, test với 2-3 chapters bạn đã biết rõ nội dung.
So sánh Lecture Notes với kiến thức thực tế của bạn.
Nếu Section "Production Realities" khớp với những gì bạn gặp trong production → prompt đang hoạt động tốt.

---

### 5. Lightweight Evals → Checklist tự đánh giá tích hợp sẵn

**Nguyên tắc:** 5-10 examples đủ phát hiện systemic gaps.

**Áp dụng:** "SELF-CHECK trước khi deliver" là mini-eval tích hợp trong prompt:

```
1. Lecture Notes có gì mà senior đọc Oracle docs không có được không?
2. Lab scenario 3 có đủ ambiguous không?
3. Có claim nào không chắc? → ghi chú [⚠️ verify with MOS]
4. Tone có đang dạy "xuống" không?
```

→ Mỗi lần Claude chạy, nó tự eval output trước khi deliver.

**Schedule re-eval:** Sau mỗi 10 chapters, đọc lại 1 Lecture Notes cũ.
Nếu thấy depth bắt đầu giảm hoặc tone trở nên basic → review lại system prompt.

---

### 6. Diligence không delegate được → Bạn vẫn own 100%

**Nguyên tắc:** AI làm 95%, bạn own 100% responsibility.

**Điều này có nghĩa gì trong workflow này:**

- `[⚠️ verify with MOS]` là Claude báo hiệu để **bạn** verify, không phải để bỏ qua
- Lab Exercise 3 ("Troubleshooting Scenario") có "Evaluation Criteria" — bạn là người chạy đánh giá, không phải Claude
- Lecture Notes Section 6 "Senior Checklist" là để **bạn** review xem có missing gì không trước khi dùng dạy học

Claude tạo draft. Bạn sign off.

---

## 📁 Cách dùng trong thực tế

```
1. Mở Claude chat mới
2. Paste toàn bộ nội dung oracle_dba_system_prompt.md vào System Prompt
3. User message: paste chapter .md + lệnh tạo
4. Review output theo SELF-CHECK criteria
5. Feedback specific nếu cần iteration
6. Sau 10 chapters: re-eval chất lượng
```

---

## ⚠️ Known Limitations

- System prompt này optimize cho **Senior/Expert**. Nếu dùng cho junior, cần thêm section giải thích khái niệm.
- Lab Exercise 3 (troubleshooting) chất lượng phụ thuộc nhiều vào độ phong phú của chapter source.
- Chapters ngắn (<500 words) sẽ bị flag bởi constraint "nêu rõ limitation".


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-RAC-Administration-Course/oracle_dba_README.md`
