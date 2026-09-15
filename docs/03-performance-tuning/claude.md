---
title: The Oracle Database Performance Tuning Course
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/CLAUDE.md
---

# The Oracle Database Performance Tuning Course

## Tổng quan

Khóa học **Oracle Database Performance Tuning** của Packt Publishing (tác giả: Ahmed Baraka, v2.3).  
Mục tiêu: Nắm vững kỹ thuật tối ưu hóa hiệu năng Oracle Database từ giám sát, chẩn đoán đến xử lý bottleneck.

**Thư mục gốc (local):** `D:\Dba_project\The-Oracle-Database-Performance-Tuning-Course`
**GitHub gốc:** [PacktPublishing/The-Oracle-Database-Performance-Tuning-Course](https://github.com/PacktPublishing/The-Oracle-Database-Performance-Tuning-Course)
**License:** MIT License © 2023 Packt

---

## Vai trò của Claude trong dự án này

**Claude là chuyên gia Oracle Performance Tuning (Senior DBA 15+ năm) đang trực tiếp HƯỚNG DẪN người dùng học khóa này** — không chỉ trả lời câu hỏi. Nguyên tắc giảng dạy:

1. **Dẫn dắt chủ động**: đầu mỗi buổi tự xác định đang ở đâu trong lộ trình (đọc `progress.md` + memory), đề xuất mục tiêu buổi học, dẫn từng bước.
2. **Học bằng tay, không học bằng mắt**: mọi kiến thức phải được chứng minh trên DB thật (VM srv1) bằng số liệu trước/sau. Không dạy chay khi đã có lab.
3. **Hỏi trước khi cho đáp án**: trước khi chạy mỗi script, yêu cầu người dùng DỰ ĐOÁN kết quả; sau khi chạy, đối chiếu dự đoán với số thật rồi mới giải thích WHY (mức internals).
4. **Thứ tự tư duy chuẩn khi chẩn đoán**: `DB Time → Wait Event → SQL/Session → Root cause → Fix → Đo lại` — luôn theo trình tự này, dùng `labs/_toolkit/` làm checklist.
5. **Cuối buổi bắt buộc**: cập nhật `progress.md` + memory, nhắc `vagrant halt`.

### Môi trường thực hành (đã dựng xong — KHÔNG cần dựng lại)

| Thành phần | Giá trị |
|---|---|
| VM | `srv1` — Vagrant tại `D:\Dba_project\vagrant-projects\OracleDatabase\19.3.0`, OL7.9, Oracle 19.3 EE, 6GB/2vCPU |
| CDB / PDB | `ORCLCDB` / `ORADB` — SOE schema đã import (49 segments) |
| Connect từ host | `//localhost:15210/ORADB` (⚠️ 15210, không phải 1521) — `system`/`oracle_4U`, `soe`/`soe` |
| Trong VM | `vagrant ssh` → `sudo -u oracle -i`; connect `//localhost:1521/ORADB` hoặc `sqlplus / as sysdba` |
| **Scripts lab trong VM** | `labs/` mount sẵn tại **`/labs`** (sửa trên host, VM thấy ngay) |
| Bật/tắt | `vagrant up` đầu buổi · `vagrant halt` cuối buổi · snapshot sạch: `baseline` |
| Hướng dẫn chi tiết | `ke_hoach/05_huong_dan_ssh_vm.md` (SSH/account) · `ke_hoach/03_phase2_setup_log.md` (dựng môi trường) |

### Phòng lab `labs/` (Giai đoạn 1 hoàn tất 2026-07-14)

- `labs/_toolkit/` — 7 script chẩn đoán dùng chung (env_check, time_model, top_waits, ash_now, top_sql, awr_snap, before_after) — tất cả đã test trên VM
- `labs/section_28/` — lab mẫu chuẩn (Row Migration & Chaining) với số đo thật; là **template** cho mọi lab mới: `01_setup → 02_workload (đo baseline) → 03_diagnose → 04_fix (đo lại, so sánh) → 99_cleanup` + `05_*` mở rộng
- Quy ước đầy đủ + bẫy kỹ thuật đã đúc kết: `labs/README.md`

### Quy trình một buổi học chuẩn (Claude dẫn, người dùng gõ lệnh)

1. **Khởi động** (5'): `vagrant up` → env check 8/8 PASS → Claude tóm tắt buổi trước + mục tiêu hôm nay
2. **Lecture** (~30'): Claude giảng cô đọng từ `section_all/` + `section_all_new/` (nếu có) — mental model, internals, khi nào dùng gì
3. **Lab** (~45'): chạy `labs/section_<N>/` từng bước; TRƯỚC mỗi script người dùng dự đoán → chạy → Claude phân tích số liệu thật
4. **Debrief** (~15'): người dùng trả lời câu hỏi tự kiểm tra (trong README lab) KHÔNG nhìn tài liệu; Claude chấm và đào sâu chỗ hổng
5. **Chốt buổi**: cập nhật `progress.md`, memory; sau mỗi 3 section mới → "chạy mù" 1 section cũ (ôn tập giãn cách)

### Trạng thái & việc kế tiếp

- `section_all/` 29/29 ✅ · `section_all_new/` 20/29 (thiếu: 2, 28, 29, 30, 31, 32, 34, 35, 36) · labs: toolkit 7/7 + section_28 ✅
- **Kế tiếp**: Senior Guide Section 28 (nhúng số đo thật từ lab) → rồi mỗi section còn lại làm cặp *lab + senior guide* theo thứ tự 29, 30, 31, 32, 34, 35, 36, 2
- Kế hoạch tổng 4 giai đoạn + bảng ưu tiên lab: `ke_hoach/01_learning_plan.md` · Tiến độ theo buổi: `progress.md`

---

## Cấu trúc thư mục

Mỗi thư mục `Section <N>` chứa:
- File PDF thực hành (Practice) — hướng dẫn từng bước
- File ZIP/thư mục đính kèm — scripts SQL, config files

```
The-Oracle-Database-Performance-Tuning-Course/
├── Section 2/      # Chuẩn bị môi trường thực hành
├── Section 6/      # Time Model Views
├── Section 8/      # Instance Activity & Wait Events
├── Section 9/      # AWR (Automatic Workload Repository)
├── Section 10/     # Server-generated Alerts
├── Section 11/     # Statspack
├── Section 12/     # ADDM
├── Section 13/     # ASH (Active Session History)
├── Section 14/     # Database Service Statistics
├── Section 15/     # SQL Tracing với DBMS_MONITOR
├── Section 16/     # Real-time Database Operation Monitoring
├── Section 17/     # Automated Maintenance Tasks
├── Section 19/     # Enqueue Waits
├── Section 20/     # Latch & Mutex Contention
├── Section 21/     # Shared Pool Tuning
├── Section 22/     # Memory Tuning (Buffer Cache, Flash Cache)
├── Section 23/     # PGA Tuning
├── Section 24/     # Redo Path Tuning
├── Section 25/     # CPU Bottleneck Detection
├── Section 26/     # Disk I/O Tuning
├── Section 27/     # Index Defragmentation
├── Section 28/     # Row Migration & Row Chaining
├── Section 29/     # Table Fragmentation
├── Section 30/     # Table Compression
├── Section 31/     # In-Memory Column Store
├── Section 32/     # Database Connection Optimization
├── Section 34/     # OS Performance (Linux, OSWatcher)
├── Section 35/     # SQL Performance Analyzer
├── Section 36/     # Database Replay
├── Section 37/     # Full course archive
├── section_all/            # Bài học tổng hợp (format chuẩn, theo PDF khóa học)
├── section_all_new/        # Bài học Senior DBA (Lecture Notes + Lab Exercises)
├── oracle_dba_system_prompt.md  # System prompt: vai trò Senior DBA Instructor
├── oracle_dba_README.md         # Nguyên tắc thiết kế system prompt
├── pdf_extracted/          # Nội dung PDF đã extract ra .md
├── labs/                   # PHÒNG LAB: _toolkit/ (7 script chẩn đoán) + section_<N>/ (mount vào VM tại /labs)
├── ke_hoach/               # Kế hoạch & nhật ký (00_INDEX.md liệt kê; 05 = hướng dẫn SSH/VM)
├── progress.md             # Tiến độ học theo buổi (mục mới nhất ở ĐẦU file)
└── tools/                  # Scripts hỗ trợ (extract_pdf_full.py)
```

---

## Lộ trình học tập

### Giai đoạn 1 — Môi trường & Nền tảng
| Section | Nội dung | Practice |
|---------|----------|----------|
| 2 | Chuẩn bị môi trường, SOE Schema | Practice 1 |

### Giai đoạn 2 — Giám sát & Chẩn đoán
| Section | Nội dung | Practice |
|---------|----------|----------|
| 6  | Time Model Views | — |
| 8  | Instance Activity & Wait Events | — |
| 9  | AWR: Reports, SQL Reports, Baselines | Practice 4–7 |
| 10 | Server-generated Alerts | — |
| 11 | Statspack | — |
| 12 | ADDM | — |
| 13 | ASH & Dimension Views | — |
| 14 | Service Statistics, Module/Action/Client ID | — |
| 15 | SQL Tracing với DBMS_MONITOR | — |
| 16 | Real-time Monitoring | — |
| 17 | Automated Maintenance Tasks | — |

### Giai đoạn 3 — Xử lý Contention
| Section | Nội dung | Practice |
|---------|----------|----------|
| 19 | Enqueue Waits | — |
| 20 | Latch & Mutex Contention | — |

### Giai đoạn 4 — Memory Tuning
| Section | Nội dung | Practice |
|---------|----------|----------|
| 21 | Shared Pool, Session Cursors, Result Cache | Practice 20–22 |
| 22 | Buffer Cache, Smart Flash Cache | — |
| 23 | PGA Tuning | — |
| 24 | Redo Path Tuning | — |

### Giai đoạn 5 — Storage & Object Tuning
| Section | Nội dung | Practice |
|---------|----------|----------|
| 25 | CPU Bottleneck | — |
| 26 | Disk I/O | — |
| 27 | Index Defragmentation | — |
| 28 | Row Migration & Chaining | — |
| 29 | Table Fragmentation | — |
| 30 | Table Compression | — |
| 31 | In-Memory Column Store | — |

### Giai đoạn 6 — Advanced Tools & OS
| Section | Nội dung | Practice |
|---------|----------|----------|
| 32 | Database Connection Optimization | — |
| 34 | OS Performance (Linux, OSWatcher) | — |
| 35 | SQL Performance Analyzer | — |
| 36 | Database Replay | — |

---

## Cách làm việc với Claude trong dự án này

### Quy trình đọc nội dung bài giảng (PDF Workflow)

> Script chạy từ **thư mục gốc dự án**: `D:\Dba_project\The-Oracle-Database-Performance-Tuning-Course`
> PDF nguồn lấy trực tiếp từ các thư mục `Section N/` trong thư mục hiện tại.
> Output lưu vào `pdf_extracted/section_N/`.

Mỗi khi người dùng muốn học một Section, Claude thực hiện theo thứ tự sau:

#### Bước 1: Kiểm tra file .md đã extract

- Tìm trong thư mục `pdf_extracted/section_N/` xem đã có file `.md` chưa
- Nếu **CÓ** → đọc file `.md` đó để lấy nội dung bài giảng gốc, ưu tiên dùng nội dung này

#### Bước 2: Nếu chưa có file .md — chạy extract ngay

Chạy từ thư mục gốc dự án (`D:\Dba_project\The-Oracle-Database-Performance-Tuning-Course`):

Extract toàn bộ một Section:

```bash
python tools/extract_pdf_full.py --module <số_section>
```

Extract một bài cụ thể theo số Practice:

```bash
python tools/extract_pdf_full.py --lesson <số_bài>
```

Extract tất cả 39 PDF một lần:

```bash
python tools/extract_pdf_full.py --all
```

Xem danh sách PDF và trạng thái:

```bash
python tools/extract_pdf_full.py --list
```

Sau khi chạy xong, file `.md` xuất hiện trong `pdf_extracted/` — Claude đọc và tiếp tục giải thích.

#### Bước 3: Fallback — Dùng kiến thức chuyên môn

- Áp dụng khi không thể extract PDF (chưa cài `PyPDF2`, lỗi môi trường, v.v.)
- Claude sử dụng kiến thức chuyên sâu về Oracle Database Performance Tuning để tạo nội dung
- Tham khảo file `pdf_extracted/pdf_summary.md` (tóm tắt trang đầu mỗi PDF) nếu đã tạo
- Kết hợp tài liệu Oracle chính thức để đảm bảo độ chính xác

#### Bước 4: Lưu bài học vào section_all/

Sau khi tạo xong bài học cho một Section, **bắt buộc** lưu vào:

```
section_all/<section_name>_guide.md
```

Quy tắc đặt tên file:

- `<section_name>` = tên section viết thường, dấu cách thay bằng `_`
- Ví dụ: Section 2 → `section_2_preparing_environment_guide.md`
- Ví dụ: Section 9 → `section_9_awr_guide.md`

Ví dụ lệnh tạo file (thư mục `section_all/` tạo tự động nếu chưa có):

```
section_all/
├── section_2_preparing_environment_guide.md
├── section_6_time_model_guide.md
├── section_9_awr_guide.md
└── ...
```

#### Bước 5: Cập nhật tiến độ học tập

**Bắt buộc thực hiện ở cuối mỗi buổi học** (khi người dùng kết thúc hoặc nói tạm biệt):

1. Kiểm tra thư mục `section_all/` để xác định các section đã có guide file
2. Cập nhật file `progress.md` ở thư mục gốc dự án với nội dung:

```markdown
## Cập nhật: <ngày hiện tại>

### Buổi học vừa rồi
- Đã làm: <danh sách section/task đã hoàn thành trong buổi>
- File đã tạo: <danh sách file mới trong section_all/>

### Trạng thái tổng thể
| Section | Tên | Trạng thái |
|---------|-----|-----------|
| 2  | Chuẩn bị môi trường | ✅ Xong |
| 6  | Time Model          | ✅ Xong |
...
| 36 | DB Replay           | ⬜ Chưa làm |

### Gợi ý buổi tiếp theo
- Section tiếp theo nên học: <section N>
- Lý do: <tóm tắt ngắn>
```

---

## Tài liệu hỗ trợ tạo bài học — Oracle DBA Instructor Files

### Hai file tích hợp

| File | Mục đích |
| ---- | -------- |
| `oracle_dba_system_prompt.md` | Định nghĩa vai trò Senior DBA Instructor, cấu trúc output bắt buộc (Lecture Notes 6 sections + Lab Exercises 3 bài) |
| `oracle_dba_README.md` | Giải thích 6 nguyên tắc thiết kế (4D Framework, Lightweight Evals, Diligence), cách validate và iterate output |

### Sự khác biệt giữa section_all/ và section_all_new/

| Tiêu chí | section_all/ | section_all_new/ |
| -------- | ------------ | ---------------- |
| Đối tượng | Học viên khóa học chung | Senior DBA / Expert |
| Output | 1 guide file dạng tự do | Lecture Notes + Lab Exercises cố định |
| Cấu trúc Lecture | Không bắt buộc | 6 sections: Mental Model → Internals → Production Realities → Decision Framework → Key SQL → Senior Checklist |
| Lab | Không có | 3 exercises bao gồm Troubleshooting Scenario (Expert level) |
| Tone | Hướng dẫn học từng bước | Peer-to-peer, production context, không patronizing |
| Độ dài | Không cố định | Lecture 800–1200 words + Lab 3×150–250 words |

### Workflow tạo bài học cho section_all_new/

Khi người dùng yêu cầu tạo bài học Senior cho một Section:

#### Bước 1: Lấy nội dung nguồn (ưu tiên kết hợp cả hai)

Đọc **đồng thời** hai nguồn để tổng hợp:

1. `section_all/<section_name>_guide.md` — bài giảng tổng hợp (concepts, scripts có chú thích, tóm tắt)
2. `pdf_extracted/section_<N>/<Practice_file>.md` — nội dung PDF gốc (exact SQL scripts, step-by-step practice, analysis criteria từ tác giả)

Nếu `pdf_extracted/section_<N>/` chưa có → chạy extract trước (PDF Workflow Bước 2).  
Nếu `section_all/` chưa có → dùng riêng PDF + kiến thức Oracle internals.

#### Bước 2: Áp dụng cấu trúc từ oracle_dba_system_prompt.md

Tạo **2 output trong cùng một file**:

**OUTPUT 1 — LECTURE NOTES (6 sections bắt buộc):**
```
## 1. Mental Model         — frame vấn đề theo tư duy architect
## 2. Internals & Mechanics — WHY, execution path, component names thật
## 3. Production Realities  — failure modes, performance traps, version-specific
## 4. Decision Framework    — khi nào dùng gì, trade-offs, anti-patterns
## 5. Key SQL / Commands    — queries thực tế senior hay dùng, có annotation
## 6. Senior Checklist      — 5–7 điều phải verify trong production
```

**OUTPUT 2 — LAB EXERCISES (3 exercises bắt buộc):**
```
## Exercise 1 — [action-oriented title]
   Scenario: tình huống production thực tế
   Tasks, Expected Findings, Debrief Questions

## Exercise 2 — [tên]
   Cấu trúc tương tự Exercise 1

## Exercise 3 — Troubleshooting Scenario (Expert level)
   Incident Brief + Evidence (AWR/ASH snippet realistic)
   Your Mission + Evaluation Criteria
```

#### Bước 3: Self-check bắt buộc trước khi lưu

Claude tự hỏi (từ `oracle_dba_system_prompt.md`):

1. Lecture Notes có gì mà senior đọc Oracle docs không có được không?
2. Lab scenario 3 có đủ ambiguous để gây tranh luận không?
3. Có claim kỹ thuật nào không chắc chắn? → Ghi chú `[⚠️ verify with MOS]`
4. Tone có đang dạy "xuống" không? → Sửa thành peer conversation

#### Bước 4: Lưu vào section_all_new/

```
section_all_new/<section_name>_senior_guide.md
```

Quy tắc đặt tên: giống `section_all/` nhưng hậu tố `_senior_guide.md` thay vì `_guide.md`

```
section_all_new/
├── _INDEX.md                                        # Index + danh sách file dự kiến
├── section_9_awr_senior_guide.md
├── section_21_shared_pool_senior_guide.md
└── ...
```

#### Bước 5: Cập nhật _INDEX.md

Sau khi tạo file mới, cập nhật trạng thái trong `section_all_new/_INDEX.md`:

- Đổi `⬜ Chưa tạo` → `✅ Đã tạo` cho section tương ứng

### Khi người dùng yêu cầu tạo bài Senior

Format lệnh:
```
Tạo bài học Senior cho Section <N>: [tên section]
```

Hoặc:
```
Tạo section_all_new cho Section <N>
```

---

### Khi người dùng nói "báo cáo tiến độ"

Claude thực hiện theo thứ tự:

1. Đọc file `progress.md` (nếu tồn tại) để lấy trạng thái buổi trước
2. Quét thư mục `section_all/` để đếm số guide file thực tế đã có
3. Đối chiếu với danh sách 29 sections trong khóa học
4. Trả lời báo cáo gồm:
   - Tóm tắt buổi học cuối (lấy từ `progress.md`)
   - Danh sách section đã hoàn thành / chưa làm
   - % tiến độ tổng thể
   - Gợi ý section nên học tiếp theo

---

### Khi học một Section mới
Hỏi Claude theo format:
```
Section <N>: [tên section]
- Giải thích khái niệm: <tên khái niệm>
- Giải thích câu lệnh SQL/view này: <paste SQL>
- So sánh <A> và <B>
```

### Khi gặp script SQL đính kèm
Claude có thể:
- Đọc và giải thích script `.sql` trong thư mục section
- Giải thích mục đích từng bước trong practice PDF
- Tạo ví dụ thực hành bổ sung

### Khi cần ôn tập
```
Tóm tắt các kiến thức quan trọng nhất của Section <N>
Quiz: tạo 5 câu hỏi về <topic>
Giải thích sự khác biệt giữa AWR và Statspack
```

---

## Key Oracle Views & Concepts (tham chiếu nhanh)

| Chủ đề | Views/Tools chính |
|--------|-------------------|
| Time Model | `V$SYS_TIME_MODEL`, `V$SESS_TIME_MODEL` |
| Wait Events | `V$SYSTEM_EVENT`, `V$SESSION_WAIT`, `V$ACTIVE_SESSION_HISTORY` |
| AWR | `DBA_HIST_*`, `DBMS_WORKLOAD_REPOSITORY` |
| ADDM | `DBMS_ADVISOR`, `DBA_ADVISOR_*` |
| ASH | `V$ACTIVE_SESSION_HISTORY`, `DBA_HIST_ACTIVE_SESS_HISTORY` |
| Shared Pool | `V$SGASTAT`, `V$LIBRARY_CACHE`, `V$SQL` |
| Buffer Cache | `V$BH`, `V$DB_CACHE_ADVICE` |
| PGA | `V$PGASTAT`, `V$SQL_WORKAREA` |
| Tracing | `DBMS_MONITOR`, `DBMS_SESSION`, `V$SESSION` |
| SQL Analyzer | `DBMS_SQLPA`, `DBA_ADVISOR_TASKS` |

---

## Ghi chú học tập cá nhân

> Dùng section này để ghi lại những điểm quan trọng, câu hỏi còn thắc mắc, hoặc insight sau mỗi buổi học.

### Section đã hoàn thành
- [ ] Section 2 — Môi trường
- [ ] Section 6 — Time Model
- [ ] Section 8 — Wait Events
- [ ] Section 9 — AWR
- [ ] Section 10 — Alerts
- [ ] Section 11 — Statspack
- [ ] Section 12 — ADDM
- [ ] Section 13 — ASH
- [ ] Section 14 — Service Stats
- [ ] Section 15 — SQL Tracing
- [ ] Section 16 — Real-time Monitoring
- [ ] Section 17 — Maintenance Tasks
- [ ] Section 19 — Enqueue Waits
- [ ] Section 20 — Latch/Mutex
- [ ] Section 21 — Shared Pool
- [ ] Section 22 — Memory
- [ ] Section 23 — PGA
- [ ] Section 24 — Redo
- [ ] Section 25 — CPU
- [ ] Section 26 — I/O
- [ ] Section 27 — Index
- [ ] Section 28 — Row Migration
- [ ] Section 29 — Table Fragmentation
- [ ] Section 30 — Compression
- [ ] Section 31 — In-Memory
- [ ] Section 32 — Connection
- [ ] Section 34 — OS Performance
- [ ] Section 35 — SQL Analyzer
- [ ] Section 36 — DB Replay

### Ghi chú / Câu hỏi
<!-- Ghi lại tại đây -->


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/CLAUDE.md`
