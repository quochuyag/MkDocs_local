---
title: section_all_new — Senior DBA Lesson Index
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/section_all_new/_INDEX.md
---

# section_all_new — Senior DBA Lesson Index

Thư mục này chứa bài học được tạo theo tiêu chuẩn **Senior DBA / Expert-level**,
tích hợp từ framework `oracle_dba_system_prompt.md`.

---

## So sánh với section_all/

| Tiêu chí | section_all/ | section_all_new/ |
| -------- | ------------ | ---------------- |
| Đối tượng | Chung (học viên khóa học) | Senior DBA / Expert |
| Cấu trúc | Tự do theo nội dung PDF | Bắt buộc: 6 sections + 3 lab exercises |
| Nội dung | Giải thích từng bước, theo practice | Internals, production realities, decision framework |
| Tone | Hướng dẫn học viên | Peer-to-peer, không patronizing |
| Lab | Không có | 3 exercises (bao gồm troubleshooting scenario expert-level) |
| Độ dài | Không cố định | Lecture 800–1200 words + Lab 3×150–250 words |

---

## Cấu trúc mỗi file _senior_guide.md

### OUTPUT 1 — LECTURE NOTES

```text
## 1. Mental Model
## 2. Internals & Mechanics
## 3. Production Realities
## 4. Decision Framework
## 5. Key SQL / Commands
## 6. Senior Checklist
```

### OUTPUT 2 — LAB EXERCISES

```text
## Exercise 1 — [Tên ngắn gọn, action-oriented]
   - Scenario (production thực tế)
   - Tasks
   - Expected Findings
   - Debrief Questions

## Exercise 2 — [Tên]

## Exercise 3 — Troubleshooting Scenario (Expert level)
   - Incident Brief
   - Evidence Provided (AWR/ASH snippet realistic)
   - Your Mission
   - Evaluation Criteria
```

---

## Quy tắc đặt tên file

```text
section_<N>_<topic_slug>_senior_guide.md
```

Ví dụ:

- Section 9  → `section_9_awr_senior_guide.md`
- Section 21 → `section_21_shared_pool_senior_guide.md`

---

## Danh sách file dự kiến (28 sections)

| File | Section | Trạng thái |
| ---- | ------- | ---------- |
| section_2_preparing_environment_senior_guide.md | 2 — Môi trường | ⬜ Chưa tạo |
| section_6_time_model_senior_guide.md | 6 — Time Model | ✅ Đã tạo |
| section_8_instance_activity_wait_events_senior_guide.md | 8 — Wait Events | ✅ Đã tạo |
| section_9_awr_senior_guide.md | 9 — AWR | ✅ Đã tạo |
| section_10_server_generated_alerts_senior_guide.md | 10 — Alerts | ✅ Đã tạo |
| section_11_statspack_senior_guide.md | 11 — Statspack | ✅ Đã tạo |
| section_12_addm_senior_guide.md | 12 — ADDM | ✅ Đã tạo |
| section_13_ash_senior_guide.md | 13 — ASH | ✅ Đã tạo |
| section_14_database_service_statistics_senior_guide.md | 14 — Service Stats | ✅ Đã tạo |
| section_15_sql_tracing_senior_guide.md | 15 — SQL Tracing | ✅ Đã tạo |
| section_16_realtime_monitoring_senior_guide.md | 16 — Real-time Monitoring | ✅ Đã tạo |
| section_17_automated_maintenance_senior_guide.md | 17 — Maintenance Tasks | ✅ Đã tạo |
| section_19_enqueue_waits_senior_guide.md | 19 — Enqueue Waits | ✅ Đã tạo |
| section_20_latch_mutex_senior_guide.md | 20 — Latch & Mutex | ✅ Đã tạo |
| section_21_shared_pool_senior_guide.md | 21 — Shared Pool | ✅ Đã tạo |
| section_22_buffer_cache_flash_cache_senior_guide.md | 22 — Buffer Cache | ✅ Đã tạo |
| section_23_pga_senior_guide.md | 23 — PGA | ✅ Đã tạo |
| section_24_redo_path_senior_guide.md | 24 — Redo Path | ✅ Đã tạo |
| section_25_cpu_bottleneck_senior_guide.md | 25 — CPU Bottleneck | ✅ Đã tạo |
| section_26_disk_io_senior_guide.md | 26 — Disk I/O | ✅ Đã tạo |
| section_27_index_defrag_senior_guide.md | 27 — Index Defrag | ✅ Đã tạo |
| section_28_row_migration_chaining_senior_guide.md | 28 — Row Migration | ✅ Đã tạo (kèm lab thật `labs/section_28/`) |
| section_29_table_fragmentation_senior_guide.md | 29 — Table Fragmentation | ✅ Đã tạo (kèm lab `labs/section_29/`) |
| section_30_table_compression_senior_guide.md | 30 — Table Compression | ✅ Đã tạo (kèm lab `labs/section_30/`) |
| section_31_in_memory_column_store_senior_guide.md | 31 — In-Memory | ✅ Đã tạo (kèm lab `labs/section_31/`) |
| section_32_database_connection_optimization_senior_guide.md | 32 — DB Connection | ✅ Đã tạo (kèm lab `labs/section_32/`) |
| section_34_os_performance_senior_guide.md | 34 — OS Performance | ✅ Đã tạo (kèm lab `labs/section_34/`) |
| section_35_sql_performance_analyzer_senior_guide.md | 35 — SQL Analyzer | ✅ Đã tạo (kèm lab `labs/section_35/`) |
| section_36_database_replay_senior_guide.md | 36 — DB Replay | ✅ Đã tạo (kèm lab `labs/section_36/`) |

---

## Nguồn tạo bài học

| Ưu tiên | Nguồn | Nội dung cung cấp |
| ------- | ----- | ----------------- |
| 1 | `pdf_extracted/section_<N>/<Practice>.md` | Exact SQL scripts, step-by-step lab, analysis criteria từ tác giả gốc (Ahmed Baraka) |
| 2 | `section_all/<section_name>_guide.md` | Concepts tổng hợp, scripts có annotation, tóm tắt học tập |
| 3 | `oracle_dba_system_prompt.md` | Framework cấu trúc output (role + 6-section Lecture + 3-exercise Lab) |
| 4 | `oracle_dba_README.md` | 4D framework, validation criteria, iteration guidance |
| 5 | Oracle internals + MOS notes | Fallback khi hai nguồn trên thiếu depth hoặc chưa extract |

**Nguyên tắc tổng hợp:**

- PDF gốc cung cấp **"what and how"** (scripts chính xác, practice flow)
- `section_all` cung cấp **"why"** (explanations, context)
- Senior guide bổ sung **"what senior needs to know"** (internals, edge cases, production realities không có trong course)

---

## Self-check trước khi lưu mỗi file (từ oracle_dba_system_prompt.md)

1. Lecture Notes có gì mà senior đọc Oracle docs không có được không?
2. Lab scenario 3 có đủ ambiguous để gây tranh luận không?
3. Có claim kỹ thuật nào không chắc chắn? → Ghi chú `[⚠️ verify with MOS]`
4. Tone có đang dạy "xuống" không? → Sửa thành peer conversation


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/section_all_new/_INDEX.md`
