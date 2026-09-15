---
title: Kế hoạch Code Lab & Lộ trình học — Oracle Database Performance Tuning
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/ke_hoach/01_learning_plan.md
---

# Kế hoạch Code Lab & Lộ trình học — Oracle Database Performance Tuning

> Tạo ngày: 2026-07-13 · Cập nhật khi hoàn thành mỗi giai đoạn
> Mục tiêu: chuyển dự án từ "đọc tài liệu" sang "thực hành có đo lường" — mỗi kiến thức đều được chứng minh bằng số liệu trước/sau.

---

## 1. Phân tích hiện trạng

### Đã có (phần tài liệu — 95% hoàn chỉnh)

| Thành phần | Trạng thái | Ghi chú |
|---|---|---|
| `pdf_extracted/` | ✅ 38/38 practice | Nội dung PDF gốc đã extract ra .md |
| `section_all/` | ✅ 28/29 guide | Chỉ thiếu Section 2 (môi trường) |
| `section_all_new/` | 🟡 21/29 senior guide | Thiếu: 2, 28, 29, 30, 31, 32, 34, 35, 36 |
| `progress.md` | ✅ Đến buổi 7 (25/04/2026) | Gợi ý tiếp theo: Section 28 |

### Còn thiếu (phần thực hành — khoảng trống lớn nhất)

- **Chỉ có 1 file SQL chạy được** trong toàn dự án: `Section 35/client_wrkld/client_wrkld.sql`
- Script thực hành bị kẹt trong PDF (dạng text) hoặc ZIP chưa giải nén:
  - `Section 2/Practice+1+-+Attached+Files.zip` (~110MB): SOE schema, Swingbench, soedump
  - `Section 28/Practice+30+-+ScriptFiles.zip`: script row migration
  - `Section 32/sqlnet.zip`, `tnsnames.zip`: config connection
- **Hệ quả:** muốn thực hành phải gõ lại SQL từ PDF thủ công mỗi lần → chậm, dễ sai, không ôn tập lại được.

---

## 2. Kế hoạch 4 giai đoạn

### Giai đoạn 1 — Xây bộ khung Code Lab (`labs/`) ⬅️ BẮT ĐẦU TỪ ĐÂY

Tạo thư mục `labs/` với cấu trúc chuẩn hóa:

```
labs/
├── _toolkit/                  # Bộ chẩn đoán dùng chung mọi section
│   ├── 00_env_check.sql       # Kiểm tra môi trường: version, SGA/PGA, SOE schema
│   ├── top_waits.sql          # Top wait events (V$SYSTEM_EVENT)
│   ├── time_model.sql         # DB Time breakdown (V$SYS_TIME_MODEL)
│   ├── top_sql.sql            # Top SQL theo elapsed / CPU / buffer gets
│   ├── awr_snap.sql           # Tạo AWR snapshot nhanh
│   ├── ash_now.sql            # ASH 5 phút gần nhất theo event/sql_id
│   └── before_after.sql       # Chụp thống kê session trước/sau khi tune
│
├── section_<N>/               # Mỗi section một lab, 5 file cố định
│   ├── 01_setup.sql           # Tạo object + dữ liệu test
│   ├── 02_workload.sql        # Sinh tải TÁI TẠO vấn đề hiệu năng
│   ├── 03_diagnose.sql        # Query chẩn đoán (script gốc PDF + annotation)
│   ├── 04_fix.sql             # Cách xử lý + đo lại kết quả
│   └── 99_cleanup.sql         # Dọn sạch, trả môi trường về ban đầu
│
└── README.md                  # Hướng dẫn dùng lab + quy ước
```

**Nguyên tắc:**
- SQL lấy từ `pdf_extracted/` (script gốc Ahmed Baraka) làm xương sống, bổ sung annotation tiếng Việt.
- Mỗi lab phải chạy được từ đầu đến cuối bằng SQL*Plus/SQLcl mà không cần sửa tay.
- Mỗi `04_fix.sql` kết thúc bằng so sánh số liệu trước/sau (buffer gets, elapsed, waits).

**Thứ tự tạo lab — ưu tiên section tái tạo được vấn đề bằng SQL thuần:**

| Ưu tiên | Section | Lý do |
|---|---|---|
| 1 | 28 — Row Migration & Chaining | Tiếp theo trong lộ trình; có ScriptFiles.zip đối chiếu; dễ tái tạo bằng PCTFREE thấp + UPDATE |
| 2 | 27 — Index Defragmentation | Companion của 28; tái tạo bằng DELETE hàng loạt → đo BLEVEL/DEL_LF_ROWS |
| 3 | 29 — Table Fragmentation | Cùng nhóm storage; DELETE + đo HWM |
| 4 | 19 — Enqueue Waits | Tái tạo lock contention bằng 2 session |
| 5 | 21 — Shared Pool | Hard parse storm bằng literal SQL vòng lặp |
| 6 | 23 — PGA | Sort/hash tràn temp bằng query lớn |
| 7 | 30 — Table Compression | So sánh size + elapsed các loại compression |
| 8 | 22 — Buffer Cache | Cache advice, full scan lớn |
| 9 | 24 — Redo Path | log file sync bằng commit loop |
| 10+ | Các section còn lại | Monitoring sections (6–17) dùng chung `_toolkit/` là chính |

### Giai đoạn 2 — Dựng môi trường thực hành (Section 2, dùng Vagrant)

> 📋 **Kế hoạch chi tiết từng bước: [02_phase2_environment_vagrant_plan.md](002-phase2-environment-vagrant-plan.md)**

Tóm tắt: thay quy trình VirtualBox thủ công của Practice 1 gốc (OL6.10 + Oracle 12.2 — đã EOL) bằng **Vagrant + oracle/vagrant-projects → VM Oracle Linux 8 + Oracle 19c EE**, PDB tên `ORADB` (giữ tên như course).

1. Giải nén, kiểm kê `Section 2/Practice+1+-+Attached+Files.zip` (create_soe.sql, soe.dmp, Swingbench 2.5)
2. `vagrant up` dựng VM 19c (6 GB RAM, 2 vCPU) — ~45 phút tự động
3. Import SOE schema vào PDB ORADB; cài Swingbench 2.5 trên host (oltp.xml + warehouse.xml)
4. Cài `stress-ng` + `sysstat` trong VM (Section 25/34); snapshot `baseline` bằng `vagrant snapshot save`
5. Tạo guide còn thiếu: `section_all/section_2_preparing_environment_guide.md`
6. Hoàn thiện `labs/_toolkit/00_env_check.sql` để kiểm tra môi trường sẵn sàng chưa

### Giai đoạn 3 — Hoàn thành 9 Senior Guide còn lại

Thứ tự theo `progress.md`: **28 → 29 → 30 → 31 → 32 → 34 → 35 → 36 → 2**

Điểm mới: mỗi senior guide từ giờ **link sang lab tương ứng** trong `labs/` thay vì chỉ mô tả SQL. Lab Exercise 3 (Troubleshooting Scenario) dùng chính `02_workload.sql` để sinh incident thật.

### Giai đoạn 4 — Benchmark harness & chế độ ôn tập

- `labs/_toolkit/before_after.sql`: chụp `V$SESSTAT`/`V$SESSION_EVENT` trước và sau khi tune → chứng minh hiệu quả bằng con số, không bằng cảm giác
- **Chế độ "chạy mù"** cho ôn tập: chạy `02_workload.sql` của một section ngẫu nhiên → tự chẩn đoán bằng `_toolkit/` → so đáp án với `03_diagnose.sql`
- Quiz tổng hợp theo giai đoạn (dùng format quiz trong CLAUDE.md)

---

## 3. Lời khuyên lộ trình học (khuyến nghị tốt nhất)

### Nguyên tắc cốt lõi

1. **Học bằng tay, không học bằng mắt.** Đọc guide chỉ tạo "cảm giác hiểu". Chỉ khi tự tái tạo vấn đề → thấy wait event tăng → fix → thấy số giảm, kiến thức mới thành kỹ năng. Đây là lý do `labs/` quan trọng hơn việc hoàn thành 9 guide còn lại.

2. **Mỗi buổi học = 1 vòng lặp đầy đủ:** đọc lecture (30') → chạy lab (45') → tự trả lời Debrief Questions không nhìn tài liệu (15'). Không chuyển section mới khi chưa chạy xong lab section cũ.

3. **Luôn bắt đầu từ triệu chứng, không từ giải pháp.** Thứ tự tư duy chuẩn của tuning: `DB Time → Wait Event → SQL/Session gây ra → Root cause → Fix → Đo lại`. Toolkit được thiết kế đúng theo thứ tự này — dùng nó như checklist mỗi lần chẩn đoán.

4. **Ôn tập giãn cách (spaced repetition):** sau mỗi 3 section mới, quay lại chạy "chạy mù" 1 section cũ. Kiến thức tuning rất dễ rơi nếu không dùng.

### Lịch học gợi ý (2–3 buổi/tuần, mỗi buổi ~90 phút)

| Tuần | Nội dung | Kết quả |
|---|---|---|
| 1 | GĐ1: `_toolkit/` + lab Section 28 (mẫu chuẩn) | Format lab được chốt |
| 2 | GĐ2: môi trường Section 2 + guide Section 2 | DB sẵn sàng, `section_all/` đủ 29/29 |
| 3–4 | Lab + Senior guide: Section 28, 29, 30 | Nhóm storage tuning xong |
| 5–6 | Lab + Senior guide: Section 31, 32 | In-Memory + Connection xong |
| 7–8 | Lab + Senior guide: Section 34, 35, 36 | Senior guide đủ 29/29 |
| 9 | GĐ4: benchmark harness + chạy mù 3 section ngẫu nhiên | Chế độ ôn tập hoạt động |
| 10 | Bổ sung lab cho các section cũ (19, 21, 23, 27...) theo bảng ưu tiên | Phòng lab đầy đủ |

### Anti-patterns cần tránh

- ❌ Hoàn thành nốt 9 guide trước rồi mới làm lab → lại rơi vào "đọc chay", guide viết xong không có lab kiểm chứng
- ❌ Copy script chạy mà không dự đoán trước kết quả → luôn tự hỏi "mình kỳ vọng thấy gì?" trước khi Enter
- ❌ Tune theo "best practice" thuộc lòng thay vì theo số liệu đo được — chính là bài học lớn nhất của khóa này

---

## 4. Theo dõi tiến độ kế hoạch

| Giai đoạn | Hạng mục | Trạng thái |
| --- | --- | --- |
| 1 | `labs/_toolkit/` (7 script) | ✅ 7/7 xong 2026-07-14 — tất cả đã smoke-test trên VM |
| 1 | `labs/_toolkit/` bộ sinh tải (workload_soe + soe_load.sh + workload_stop) | ✅ Xong 2026-07-14 (buổi 10) — thay Swingbench; external job spawn phiên SOE thật (job PLSQL không tính DB time) |
| 1 | `labs/section_28/` (lab mẫu) | ✅ Xong 2026-07-14 — chạy end-to-end trên DB thật, số liệu trước/sau ghi trong `labs/section_28/README.md` |
| 1 | `labs/section_2,6,8,9,10/` (nhóm monitoring) | ✅ Xong 2026-07-14 (buổi 10) — 5 lab test end-to-end trên VM, README kèm số đo thật |
| 1 | `labs/README.md` | ✅ Xong 2026-07-14 |
| **2** | **TOÀN BỘ Giai đoạn 2 — VM 19c + SOE + Swingbench + snapshot** | **✅ Xong 2026-07-13** — xem [03_phase2_setup_log.md](003-phase2-setup-log.md) |
| 2 | Kiểm kê Attached Files Section 2 | ✅ Xong 2026-07-13 |
| 2 | `section_all/section_2_preparing_environment_guide.md` | ✅ Xong 2026-07-13 → section_all đủ 29/29 |
| 3 | Senior guide 28, 29, 30, 31, 32, 34, 35, 36, 2 | ⬜ 0/9 |
| 4 | `before_after.sql` + chế độ chạy mù | ⬜ Chưa làm |

> Khi hoàn thành hạng mục nào, đổi ⬜ → ✅ và ghi ngày. Cuối mỗi buổi vẫn cập nhật `progress.md` như quy trình cũ trong CLAUDE.md.


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/ke_hoach/01_learning_plan.md`
