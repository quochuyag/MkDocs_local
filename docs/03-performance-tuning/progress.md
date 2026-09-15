---
title: Tiến độ học tập — Oracle Database Performance Tuning
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/progress.md
---

# Tiến độ học tập — Oracle Database Performance Tuning

## Cập nhật: 2026-08-18 (buổi 14) — DỰNG LỘ TRÌNH HỌC LẠI 15 ĐÊM 📅

### Buổi học 2026-08-18 (buổi 14)

- Đã làm: **không chạy VM** — chốt cách học cho giai đoạn kiểm chứng: học lại **toàn khóa từ đầu** theo lộ trình **15 đêm liên tục 24/08 → 07/09/2026**, ca cố định **21:30–23:00** (20' ôn bài đêm trước + chuẩn bị · 25' giảng · 35' lab tự tay · 10' chốt số đo). Mỗi đêm có sẵn 3 câu hỏi ôn bài đêm trước, việc chuẩn bị, ý chính bài giảng, các bước lab theo đúng thứ tự file, và danh sách **số đo bắt buộc ghi lại**.
- Phân bổ: đêm 1 = S2 · 2 = S6+S8 · 3 = S9 · 4 = S10+S11 · 5 = S12+S13 · 6 = S14+S15 · 7 = S16+S17+chạy mù · 8 = S19+S20 · 9 = S21 · 10 = S22+S23 · 11 = S24+S25 · 12 = S26+S27 · 13 = S28+S29+S30 · 14 = S31+S32+S34 · 15 (đêm bù) = S35+S36 + tổng kết. Đêm 11, 14, 15 phải `vagrant snapshot save` trước.
- File đã tạo: `ke_hoach/06_lo_trinh_2_tuan.html` (runbook + lịch, checkbox tiến độ lưu localStorage; bản publish: https://claude.ai/code/artifact/175b3ab1-2e50-4311-805a-23f9e41d6291), `ke_hoach/06_lo_trinh_2_tuan.ics` (30 sự kiện để tự import vào Google Calendar), `tools/make_lo_trinh.py` + `tools/lo_trinh_template.html` (sinh lại khi đổi ngày/giờ: `--start` / `--hour`); cập nhật `ke_hoach/00_INDEX.md`.

### Gợi ý buổi tiếp theo (đêm 01 — 24/08/2026)

- Import file `.ics` vào Google Calendar, rồi tối 24/08 mở runbook đêm 01: Section 2 — kiểm chứng môi trường + làm chủ 9 script `_toolkit/`.
- Từ đêm 04 trở đi là các lab **chưa kiểm chứng VM** — mỗi đêm chốt được số thật thì cập nhật lại `labs/README.md` (bỏ dòng "⚠️ chưa kiểm chứng").

## Cập nhật: 2026-07-16 (buổi 13) — HOÀN TẤT 35 + 36: TRỌN BỘ SENIOR GUIDE + LAB 🎉

### Buổi học 2026-07-16 (buổi 13)

- Đã làm: dựng nốt **2 section cuối 35, 36** (senior guide + lab) → **HOÀN TẤT toàn bộ Real Application Testing**. Senior guide 26/29 → **28/29** (chỉ còn Section 2 — môi trường, không hợp format senior); **tổng lab: 29 thư mục** (mọi section có Practice + các section giám sát) — 6 kiểm chứng VM + 23 chưa kiểm chứng.
  - **Section 35 SQL Performance Analyzer** (Practice 37): change assurance **per-SQL**. STS (SQL Tuning Set) từ cursor cache → `TEST EXECUTE` before/after quanh "upgrade" mô phỏng bằng OFE 11.2→12.2 → `COMPARE PERFORMANCE` → report improved/regressed/plan changed. Chạy TRONG VM (OFE + restart, snapshot nên có, license RAT); task tên cố định `SPA_SOE_TASK` sống qua restart; `client_wrkld.sql` (8 câu bind, rút gọn về bảng lõi Swingbench SOE). Nhấn: TEST EXECUTE chạy thật (chỉ bản test); production dùng EXPLAIN PLAN; SPA không thấy concurrency.
  - **Section 36 Database Replay** (Practice 38): change assurance **toàn workload/concurrency**. Vòng đời **5 pha** Capture→Preprocess→[change]→Replay→Report qua `DBMS_WORKLOAD_CAPTURE/REPLAY` + **wrc** client (`wrc_replay.sh` calibrate/start). TRONG VM + **snapshot bắt buộc** + license RAT. Điểm học lớn: lab single-VM bỏ restore-to-SCN → **divergence≠0** (đúng như senior guide Exercise 3 dạy: thiếu restore-to-SCN + clock/GetHostTime + remap = divergence rác, không phải "upgrade hỏng"). Capture files ghi /home/oracle/workload (không /labs vboxsf). Reuse `_toolkit/workload_soe.sql` sinh tải capture.
- Cặp SPA↔DB Replay được dạy như **vi mô ↔ vĩ mô** của change assurance: SPA bắt plan regression per-SQL (nhẹ, sớm); DB Replay bắt concurrency/contention/throughput (nặng, thực tế); major upgrade dùng CẢ HAI. Troubleshooting scenario cả hai section xuất sắc (STS coverage giả + divergence do quy trình).
- File đã tạo: 2 senior guide `section_all_new/section_{35,36}_*_senior_guide.md`; 2 lab `labs/section_{35,36}/`; cập nhật `_INDEX.md`, `labs/README.md`. Shell LF chuẩn hóa.
- Môi trường: **không chạy VM** (chỉ dựng tài liệu).

### Trạng thái tổng thể (buổi 13)

- `section_all/`: 29/29 ✅ · `section_all_new/`: **28/29** (chỉ thiếu Section 2 — môi trường)
- `labs/`: toolkit 9 script ✅ + **29 lab** (mọi section) — **6 kiểm chứng VM** (2, 6, 8, 9, 10, 28, số đo thật) + **23 chưa kiểm chứng VM** (11-17, 19-27, 29-32, 34-36). **Đủ lab cho mọi section.**

### Gợi ý buổi tiếp theo (buổi 14)

- **Ưu tiên 1:** chuyển sang GIAI ĐOẠN KIỂM CHỨNG — tự tay chạy 23 lab chưa kiểm chứng VM theo HUONG_DAN_HOC, ghi số đo thật, bỏ dòng "chưa kiểm chứng" (ưu tiên các lab cần snapshot: 24 redo, 31 in-memory, 35 SPA, 36 DB Replay)
- **Ưu tiên 2 (tùy chọn):** Section 2 senior guide nếu muốn đủ 29/29 (nhưng format senior không hợp lab setup môi trường)
- Lý do: **tài liệu đã trọn vẹn** — giá trị lớn nhất giờ là học bằng tay trên DB thật

## Cập nhật: 2026-07-16 (buổi 12) — 5 SECTION 29-34: SENIOR GUIDE + LAB 🏗️🏗️

### Buổi học 2026-07-16 (buổi 12)

- Đã làm: dựng **trọn vẹn 5 section 29, 30, 31, 32, 34** (không có 33) — mỗi section gồm **senior guide (section_all_new/)** + **lab đầy đủ (labs/section_N/)**. ⚠️ Lab **CHƯA kiểm chứng VM**, số đo ghi "kỳ vọng". Nâng senior guide 21/29 → **26/29** (còn thiếu 2, 35, 36); lab 9 → **14**.
  - **Section 29 Table Fragmentation** (Practice 31): lab **fix**. CUST 100k + bulk delete/update co row → HWM cao → FTS đọc thừa; chứng minh fragment **chỉ phạt FTS** không phạt index (2 workload A/B); SHRINK SPACE CASCADE (index VALID, khác MOVE); 3 góc đo (AVG_SPACE/DBMS_SPACE.SPACE_USAGE/actual-vs-HWM); `cust_update.sh` cho thí nghiệm ORA-00054.
  - **Section 30 Table Compression** (Practice 32): lab **demo**. Basic (chỉ nén direct-path) vs Advanced (nén cả conventional, **license ACO!**); ratio phụ thuộc độ lặp (symbol table cấp block); T3 append-compress nạp nhanh nhất + query ít reads; `GET_COMPRESSION_RATIO`.
  - **Section 31 In-Memory Column Store** (Practice 33): **TRONG VM + snapshot bắt buộc** (INMEMORY_SIZE + SGA + restart) + **license In-Memory**. Dual-format; populate async (chờ `POPULATE_STATUS=COMPLETED`); `TABLE ACCESS INMEMORY FULL`; footprint IM << segment; 04 MEMCOMPRESS levels + NO INMEMORY cột + IM thay analytic index.
  - **Section 32 DB Connection** (Practice 34): đòn bẩy chính **ARRAYSIZE** (round-trip = CEIL(rows/arraysize), đo qua AUTOTRACE — cần PLUSTRACE); SDU/socket buffer (BDP) là config phụ (04, LAN latency thấp → tác dụng ít); phân biệt `SQL*Net message from client` (idle) vs round-trip thật.
  - **Section 34 OS Performance** (Practice 35+36): **lab tầng OS** (shell, không SQL). vmstat/top/iostat/mpstat/ps/iotop/netstat theo **USE method**; `os_stress.sh cpu|io` (không cần gói `stress`); **cầu SPID** `02_map_os_to_db.sql` nối OS process↔DB session; OSWatcher Black Box (Java 8 cho analyzer). Troubleshooting scenario xuất sắc (đọc oswvmstat/oswiostat chẩn đoán sự cố đã qua mà AWR không thấy).
- Kỹ thuật thiết kế mới:
  - Section 34 là lab OS-centric đầu tiên → cấu trúc lệch chuẩn 5-file SQL: `01_setup.sh` (check tool) + `os_stress.sh` + `02_map_os_to_db.sql` (cầu SPID) + `99_cleanup.sh`, phần "lab" chính nằm trong HUONG_DAN (đi qua từng utility).
  - Section 31 mirror pattern section_24 (chạy trong VM, snapshot bắt buộc, cleanup chính = restore snapshot) vì đổi INMEMORY_SIZE + restart.
  - Lab tạo bảng riêng (CUST/ORDERS2/ORDERS_CONN/T_SRC) không đụng schema SOE thật; shell helper chuẩn hóa LF.
- File đã tạo: 5 senior guide `section_all_new/section_{29,30,31,32,34}_*_senior_guide.md`; 5 lab `labs/section_{29,30,31,32,34}/` (mỗi lab 5-6 SQL/shell + README + HUONG_DAN); cập nhật `section_all_new/_INDEX.md`, `labs/README.md`.
- Môi trường: **không chạy VM buổi này** (chỉ dựng tài liệu).

### Trạng thái tổng thể (buổi 12)

- `section_all/`: 29/29 ✅ · `section_all_new/`: **26/29** (thiếu 2, 35, 36)
- `labs/`: toolkit 9 script ✅ + **14 lab** — 6 kiểm chứng VM (2, 6, 8, 9, 10, 28) + **8 chưa kiểm chứng** (25, 26, 27, 29, 30, 31, 32, 34); còn thiếu lab 35, 36

### Gợi ý buổi tiếp theo (buổi 13)

- **Ưu tiên 1:** TỰ TAY chạy các lab mới trên VM theo HUONG_DAN_HOC → ghi số đo thật (đặc biệt 29 shrink, 31 in-memory cần snapshot, 34 OS tools)
- **Ưu tiên 2:** hoàn tất 2 section cuối 35 (SQL Performance Analyzer) + 36 (Database Replay) — cặp senior guide + lab → đủ toàn khóa
- Lý do: gần trọn vẹn — chỉ còn 35, 36 là đủ 29/29 senior guide + lab toàn bộ

## Cập nhật: 2026-07-16 (buổi 11) — DỰNG 3 LAB GIAI ĐOẠN 5 (25, 26, 27) 🏗️

### Buổi học 2026-07-16 (buổi 11)

- Đã làm: dựng đầy đủ **3 phòng lab Storage & Object Tuning** theo template section_28 (5-6 file SQL + shell + README + HUONG_DAN_HOC 8 phần mỗi lab). ⚠️ **CHƯA kiểm chứng end-to-end trên VM** — số đo trong tài liệu ghi dạng **"kỳ vọng"**, cần chạy thật để chốt số.
  - `labs/section_25/` — **CPU Bottleneck** (Practice 27): lab **chẩn đoán** (04_usecase). Thay `stress`/AWR-HTML bằng `cpu_sample.sql` đo **delta `V$OSSTAT` vs `V$SYS_TIME_MODEL`** → tính `%Busy CPU` = discriminator. 2 kịch bản qua `cpu_load.sh <db|external>`: DB CPU (ASH ON CPU chỉ đích danh SQL_ID) vs external CPU (ASH mù — bài học ranh giới). 05 parse CPU tái dùng `section_20/hard_parse.sh literal`.
  - `labs/section_26/` — **Disk I/O** (Practice 28): lab **fix**. Bảng riêng `IO_ORDERS` 1M rows; `ALTER TABLE MOVE` làm index UNUSABLE → equality lookup thành FTS → I/O bùng nổ; REBUILD ONLINE đo lại (table scan blocks gotten → 0). 05 CALIBRATE_IO chạy TRONG VM (SETALL restart + QUIESCE ~9', **snapshot bắt buộc**, PHẦN B/C để comment).
  - `labs/section_27/` — **Index Defragmentation** (Practice 29): lab **fix + so sánh**. TTABLE 500k + bulk delete 200k rows trái → so sánh COALESCE (LF_BLKS giảm, BLOCKS giữ) vs REBUILD (cả hai giảm); myth-busting B-tree self-balancing. `idx_dml_load.sh` để REBUILD ONLINE hang ở `enq: TX`; 05 SHRINK SPACE trả space.
- Kỹ thuật thiết kế lab (mới, cho lab chưa có VM):
  - Lab chẩn đoán CPU không có gì để "fix" → dùng `04_usecase_*` (như section 6/8/9); discriminator `%Busy CPU = (DB CPU + bg cpu)/OS busy` tự tính trong `cpu_sample.sql` bằng 2 lần đọc cách nhau N giây (`DBMS_SESSION.SLEEP`).
  - Tạo bảng riêng (IO_ORDERS, TTABLE) thay vì đụng schema SOE thật → không hỏng dữ liệu gốc, tự kiểm soát kích thước để triệu chứng rõ.
  - Shell helper mới: `cpu_load.sh` (external=busy bash `timeout`, db=N phiên PL/SQL math thuần), `idx_dml_load.sh` (update loop có giới hạn giờ) — đã chuẩn hóa **LF** (bẫy CRLF).
- File đã tạo (24 file): `labs/section_25/{01_setup,02_workload,03_diagnose,04_usecase_external_cpu,05_parse_cpu,99_cleanup,cpu_sample}.sql + cpu_load.sh + README + HUONG_DAN`; `labs/section_26/{01,02,03,04_fix,05_calibrate_io,99}.sql + README + HUONG_DAN`; `labs/section_27/{01,02,03,04_fix,05_shrink_and_dml,99}.sql + idx_dml_load.sh + README + HUONG_DAN`; cập nhật `labs/README.md`.
- Môi trường: **không chạy VM buổi này** (chỉ dựng tài liệu). Lab cần chạy thật ở buổi sau để chuyển "kỳ vọng" → "số đo thật".

### Trạng thái tổng thể (buổi 11)

- `section_all/`: 29/29 ✅ · `section_all_new/`: 21/29 (thiếu 2, 29, 30, 31, 32, 34, 35, 36)
- `labs/`: toolkit 9 script ✅ + **9 lab** — 6 kiểm chứng VM (2, 6, 8, 9, 10, 28) + **3 mới chưa kiểm chứng (25, 26, 27)**; còn thiếu 29-36

### Gợi ý buổi tiếp theo (buổi 12)

- **Ưu tiên 1:** TỰ TAY chạy 1 trong 3 lab mới (25/26/27) trên VM theo HUONG_DAN_HOC → ghi số đo thật, chuyển "kỳ vọng" → "số đo thật" (như section_28)
- **Ưu tiên 2:** Section 29 — Table Fragmentation: cặp lab + senior guide (giai đoạn 5 tiếp theo)
- Lý do: 3 lab giai đoạn 5 đã có khung — giờ ưu tiên KIỂM CHỨNG bằng tay thay vì dựng thêm

## Cập nhật: 2026-07-14 (buổi 10) — 5 LAB MONITORING (2, 6, 8, 9, 10) CHẠY THẬT 🧪

### Buổi học 2026-07-14 (buổi 10)

- Đã làm: dựng + kiểm chứng end-to-end trên VM **5 lab nhóm giám sát** theo template section_28, mỗi lab có README kèm số đo thật + câu hỏi tự kiểm tra:
  - `labs/section_2/` — kiểm chứng môi trường (thay Practice 1) + smoke test bộ sinh tải (DB time +58.8s ≈ 2 phiên × 30s ✅)
  - `labs/section_6/` — Time Model: tải 2/4/8 user → DB CPU chạm trần 2 vCPU từ mức 4 (≈115s/khoảng), wait% vọt 3.3% → 47.3% → 73.7%
  - `labs/section_8/` — 6 view thống kê + **hung session tự động** (`lock_demo.sh`): victim treo `enq: TX` 72s, thấy đủ 3 bài học WAIT_TIME=0 / wait_history-chỉ-ghi-wait-đã-xong / view chết theo session
  - `labs/section_9/` — AWR gộp Practice 4-7: cùng 1 SQL_ID 2 plan — FTS 1.765,6 gets/exec vs index 147,0 (12×); report bằng `AWR_REPORT_TEXT`/`AWR_SQL_REPORT_TEXT` + `ADD_COLORED_SQL`; baseline + template
  - `labs/section_10/` — Server alerts (SYS qua **CDB root** — ORA-65040 y như Section 28): bão lock (`lock_storm.sh`) đẩy metric 2107 lên **99.96%** → alert nổ sau ~1 phút → dừng bão → MMON tự clear (`RESOLUTION: cleared`)
- **Hạ tầng sinh tải mới** `labs/_toolkit/workload_soe.sql` + `soe_load.sh` + `workload_stop.sql` (thay Swingbench):
  - Phát hiện quan trọng: **job PLSQL_BLOCK của DBMS_SCHEDULER là background — KHÔNG tính vào DB time** (đo: job 15s → +0.01s; foreground 10s → +9.8s) → phải external job spawn phiên `sqlplus soe` THẬT
  - Chuẩn bị một lần mới: password OS oracle (`vagrant ssh -c "echo 'oracle:oracle_4U' | sudo chpasswd"`) + credential `LAB_OS_CRED` (script tự tạo)
  - Cắt tải bằng CỜ DỪNG (`soe.lab_stop_flag`) — không kill session
- Bài học kỹ thuật mới (đúc kết từ chạy thật, đã ghi vào script/README):
  - `COMMIT` trong PL/SQL loop = batch/nowait → không sinh `log file sync`; phải `COMMIT WRITE IMMEDIATE WAIT` mới giống client thật
  - PDB có **2 stream AWR** (CDB + PDB-local, 2 dãy snap_id độc lập) → mọi thao tác AWR trong PDB phải lọc `dbid = con_dbid`, quên là ORA-13506; PDB-local mặc định tắt (interval +40150), tắt lại bằng `interval => 0`
  - `SET_THRESHOLD` trong PDB → ORA-65040 (làm ở root, metric 2107); gỡ threshold = truyền NULL (OPERATOR_DO_NOT_CHECK bị ORA-13900)
  - `v$session.USERNAME` của job slave = user TẠO job (không phải owner); PROMPT chứa `&` bị hỏi biến thế; PROMPT kết thúc `-` nuốt dòng sau
  - `credit_limit` của SOE có check constraint NOVALIDATE với dữ liệu vi phạm sẵn → update `x = x` vẫn ORA-02290
- File đã tạo: `labs/_toolkit/{workload_soe.sql,workload_stop.sql,soe_load.sh}`, `labs/section_2/{01,02,99,README}`, `labs/section_6/{01,tm_snap,02,03,04_usecase_top_sessions,99,README}`, `labs/section_8/{01,02,03,04_usecase_hung_session,lock_demo.sh,99,README}`, `labs/section_9/{01,02,03,04_usecase_baseline,99,README}`, `labs/section_10/{01,02,03,04_usecase_clear,lock_storm.sh,99,README}`
- Môi trường: mọi lab đã chạy `99_cleanup` — sạch (credential LAB_OS_CRED giữ lại làm hạ tầng); lưu ý bảng `CUST` (~121MB, section_28) đang tồn tại trong SOE — có thể user đang chạy dở lab 28, KHÔNG tự xóa

### Trạng thái tổng thể (buổi 10)

- `section_all/`: 29/29 ✅ · `section_all_new/`: 21/29 (thiếu 2, 29, 30, 31, 32, 34, 35, 36)
- `labs/`: toolkit **9 script** ✅ + **6 lab** (2, 6, 8, 9, 10, 28) ✅ — tất cả kiểm chứng trên VM với số đo thật

### Gợi ý buổi tiếp theo (buổi 11)

- **Ưu tiên 1:** bạn TỰ TAY chạy lab Section 28 theo `labs/section_28/HUONG_DAN_HOC_SECTION_28.md` (chưa làm) — hoặc học ngay Section 6 bằng lab mới (`labs/section_6/`) theo quy trình dự đoán → chạy → đối chiếu
- **Ưu tiên 2:** Section 29 — Table Fragmentation: cặp lab (`labs/section_29/`) + senior guide
- Lý do: lab nhóm monitoring đã sẵn — giờ là lúc HỌC bằng tay thay vì dựng thêm

## Cập nhật: 2026-07-14 (buổi 9) — TOOLKIT ĐỦ 7/7 + LAB MẪU SECTION 28 CHẠY THẬT 🧪

### Buổi học 2026-07-14 (buổi 9)

- Đã làm:
  - **Hoàn tất `labs/_toolkit/` 7/7 script** (thêm 6: `top_waits`, `time_model`, `top_sql`, `awr_snap`, `ash_now`, `before_after`) — tất cả smoke-test PASS trên VM srv1
  - **Lab mẫu đầu tiên `labs/section_28/`** (Row Migration & Chaining) chạy end-to-end trên DB thật, kèm số đo thật:
    - Trước fix: 30,637 `table fetch continued row`, 231,721 logical reads → sau PCTFREE 20 + MOVE ONLINE: continued row = **0**, logical reads −31k
    - Thí nghiệm chaining 32K: CHAIN_PCT 100% → 0%, BLOCKS 20,048 → 3,374
  - `labs/README.md` — quy ước lab + chuỗi chẩn đoán chuẩn
- Bài học kỹ thuật mới (đúc kết từ chạy thật, đã ghi vào script):
  - `@@` của SQL*Plus không xử lý path lồng thư mục → lab phải chạy từ `labs/section_28/`, gọi toolkit bằng `@../_toolkit/`
  - `before_after.sql` phải dùng dynamic SQL toàn bộ (bảng snapshot chưa tồn tại lúc compile block → ORA-00942)
  - `DB_32K_CACHE_SIZE` là tham số instance — ORA-65040 nếu set trong PDB → `05`/`99` chạy bằng SYS qua CDB root (`ORCLCDB`), có container switching; đổi container reset `DBMS_OUTPUT` → phải `SET SERVEROUTPUT ON` lại
  - Penalty chaining phụ thuộc **cột nào được đọc**: đọc cột ở piece đầu (FIRST_NAME) không bị phạt; phải đọc cột cuối (NOTE2) mới thấy `table fetch continued row`
  - Grant một-lần cho soe (mất nếu restore snapshot): `GRANT SELECT ON sys.v_$session_event TO soe;` (bằng SYS)
- File đã tạo: `labs/README.md`, `labs/_toolkit/{top_waits,time_model,top_sql,awr_snap,ash_now,before_after}.sql`, `labs/section_28/{README.md,01_setup,02_workload,03_diagnose,04_fix,05_row_chaining_32k,99_cleanup}.sql`
- Môi trường: đã chạy `99_cleanup.sql` — DB sạch như trước lab (đã xác nhận)
- **Mount `/labs` + hướng dẫn SSH** (bổ sung cùng buổi):
  - `labs/` của course mount vào `/labs` trong VM (`VM_LABS_DIR` trong `config.local.yaml` + synced_folder trong Vagrantfile, đã `vagrant reload`) — chạy lab trực tiếp trong VM, sửa script trên host thấy ngay; đã verify env check 8/8 PASS từ `/labs/section_28`
  - Tạo `ke_hoach/05_huong_dan_ssh_vm.md`: bảng account/pass/host, 3 cách SSH (vagrant ssh / key trực tiếp port 2222 / one-shot), user oracle, connect string trong VM (1521) vs host (15210), bẫy vboxsf, troubleshooting; cập nhật `ke_hoach/00_INDEX.md` + `labs/README.md`
- **Cập nhật CLAUDE.md** (bổ sung cùng buổi): chốt vai trò *Claude = chuyên gia Oracle Performance Tuning trực tiếp hướng dẫn học* + 5 nguyên tắc giảng dạy (dự đoán trước khi chạy, học bằng số liệu thật...) + bảng môi trường + **quy trình buổi học chuẩn 5 bước** (khởi động → lecture → lab → debrief → chốt buổi) — mọi session sau tự theo quy trình này
- **Kiểm chứng lab Section 28 TRONG VM + hướng dẫn học chi tiết** (bổ sung cùng buổi):
  - Chạy lại toàn bộ lab (01→04 bằng soe, 05+99 bằng `/ as sysdba`) từ BÊN TRONG VM qua `/labs` — sạch 100%, số liệu khớp lần chạy từ host; fix 1 lỗi hiển thị (PROMPT kết thúc bằng `--` bị SQL*Plus coi là nối dòng)
  - Bẫy mới ghi nhận: `sudo -u oracle -i bash -c '<lệnh nhiều dòng>'` bị sudo -i mangle → lệnh một dòng hoặc dùng file driver
  - Tạo **`labs/section_28/HUONG_DAN_HOC_SECTION_28.md`**: hướng dẫn buổi học 90' từng bước trong VM (SSH → sudo oracle → sqlplus → từng script kèm câu hỏi dự đoán + output thật + bảng so sánh + debrief 5 câu có đáp án ẩn + troubleshooting)

- **Tạo Senior Guide Section 28** (bổ sung cùng buổi): `section_all_new/section_28_row_migration_chaining_senior_guide.md` — Lecture 6 mục + 3 Lab Exercises theo đúng format `oracle_dba_system_prompt.md`; **nhúng toàn bộ số đo thật từ lab** (thuế 15% buffer gets, 46% workload-level, penalty-theo-cột, bẫy cold cache, ORA-65040); Exercise 3 là incident 2-root-cause (migration + ANALYZE ghi đè stats) kèm đề xuất sai (32K) để phản biện; cập nhật `_INDEX.md` → ✅

### Trạng thái tổng thể (buổi 9)

- `section_all/`: 29/29 ✅
- `section_all_new/`: **21/29** — còn thiếu Senior guide: 2, 29, 30, 31, 32, 34, 35, 36
- `labs/`: toolkit **7/7 ✅** + lab mẫu **section_28 ✅** (format lab đã chốt, kiểm chứng cả từ host lẫn trong VM)
- Giai đoạn 1 kế hoạch code lab: **HOÀN TẤT**; Giai đoạn 3 (senior guides còn lại) đã bắt đầu với Section 28

### Gợi ý buổi tiếp theo

- **Người dùng TỰ CHẠY lab Section 28** theo `labs/section_28/HUONG_DAN_HOC_SECTION_28.md` (đến giờ lab mới chạy bởi Claude để kiểm chứng — kiến thức chỉ "dính" khi tự tay gõ) + làm 3 Lab Exercises trong senior guide
- Sau đó: **Section 29 — Table Fragmentation** theo mô hình cặp *lab (`labs/section_29/`) + senior guide* — tái tạo bằng DELETE hàng loạt + đo HWM, dùng lại template section_28

---

## Cập nhật: 2026-07-13 (buổi 8) — DỰNG XONG MÔI TRƯỜNG THỰC HÀNH 🏁

### Buổi học 2026-07-13 (buổi 8)

- Đã làm:
  - Lập kế hoạch tổng thể code lab 4 giai đoạn (`ke_hoach/01_learning_plan.md`)
  - **Hoàn tất Giai đoạn 2**: dựng VM Oracle 19c EE bằng Vagrant (srv1, PDB ORADB), import SOE schema (49 segments, 3.7M rows ORDER_ITEMS), Swingbench 2.5 + oltp.xml/warehouse.xml, stress-ng/sysstat, snapshot `baseline`
  - Env check 8/8 PASS (`labs/_toolkit/00_env_check.sql`)
  - Tạo guide Section 2 → **section_all/ đủ 29/29** ✅
- File đã tạo:
  - `ke_hoach/00_INDEX.md` → `04_huong_dan_swingbench.md` (5 file, đánh số theo trình tự tạo)
  - `section_all/section_2_preparing_environment_guide.md`
  - `labs/_toolkit/00_env_check.sql`, `labs/_workload/{oltp,warehouse}.xml`
- Thông số môi trường: connect từ host `//localhost:15210/ORADB` (port 15210!), password `oracle_4U` — chi tiết trong `ke_hoach/03_phase2_setup_log.md`

### Trạng thái tổng thể (buổi 8)

- `section_all/`: **29/29** ✅ (đã bổ sung Section 2)
- `section_all_new/`: 21/29 — còn thiếu Senior guide: 2, 28, 29, 30, 31, 32, 34, 35, 36
- `labs/`: toolkit 1/7 script; chưa có lab section nào
- Môi trường thực hành: ✅ SẴN SÀNG

### Gợi ý buổi tiếp theo

- **Giai đoạn 1: tạo `labs/_toolkit/` (6 script còn lại) + lab mẫu `labs/section_28/`** (Row Migration & Chaining)
- Lý do: môi trường đã sẵn sàng — giờ là lúc chuyển từ "đọc chay" sang thực hành có đo lường; Section 28 là section tiếp theo trong lộ trình senior guide và có ScriptFiles.zip đối chiếu. Lab chạy được lần đầu tiên trên DB thật!

---

## Cập nhật: 2026-04-25 (buổi 7)

### Buổi học 2026-04-25 (buổi 7)

- Đã làm:
  - Tạo Senior Guide cho **Section 27 — Index Defragmentation**
- File đã tạo:
  - `section_all_new/section_27_index_defrag_senior_guide.md`
- File đã cập nhật: `section_all_new/_INDEX.md` (Section 27 → ✅ Đã tạo)

### Senior Guide — Trạng thái section_all_new/ (2026-04-25 buổi 7)

| Section | Tên | Trạng thái |
| --- | --- | --- |
| 6 | Time Model Views | ✅ Đã tạo |
| 8 | Instance Activity & Wait Events | ✅ Đã tạo |
| 9 | AWR | ✅ Đã tạo |
| 10 | Server-generated Alerts | ✅ Đã tạo |
| 11 | Statspack | ✅ Đã tạo |
| 12 | ADDM | ✅ Đã tạo |
| 13 | ASH | ✅ Đã tạo |
| 14 | Database Service Statistics + Module/Action/Client ID | ✅ Đã tạo |
| 15 | SQL Tracing với DBMS_MONITOR | ✅ Đã tạo |
| 16 | Real-time Database Operation Monitoring | ✅ Đã tạo |
| 17 | Automated Maintenance Tasks | ✅ Đã tạo |
| 19 | Enqueue Waits | ✅ Đã tạo |
| 20 | Latch & Mutex Contention | ✅ Đã tạo |
| 21 | Shared Pool Tuning | ✅ Đã tạo |
| 22 | Buffer Cache & Smart Flash Cache | ✅ Đã tạo |
| 23 | PGA Tuning | ✅ Đã tạo |
| 24 | Redo Path Tuning | ✅ Đã tạo |
| 25 | CPU Bottleneck Detection | ✅ Đã tạo |
| 26 | Disk I/O Tuning | ✅ Đã tạo |
| 27 | Index Defragmentation | ✅ Đã tạo |
| Còn lại 8 sections | — | ⬜ Chưa tạo |

### Gợi ý buổi tiếp theo

- **Section tiếp theo nên tạo: Section 28 — Row Migration & Row Chaining**
- Lý do: Natural companion của Index Defrag — cùng nằm trong object-level storage tuning. Row migration xảy ra khi PCTFREE quá thấp → rows không vừa sau UPDATE → chained/migrated → extra I/O per row fetch. Directly connects với BLEVEL concepts từ Section 27.

---

## Cập nhật: 2026-04-25 (buổi 6)

### Buổi học 2026-04-25 (buổi 6)

- Đã làm:
  - Tạo Senior Guide cho **Section 26 — Disk I/O Tuning**
- File đã tạo:
  - `section_all_new/section_26_disk_io_senior_guide.md`
- File đã cập nhật: `section_all_new/_INDEX.md` (Section 26 → ✅ Đã tạo)

### Senior Guide — Trạng thái section_all_new/ (2026-04-25 buổi 6)

| Section | Tên | Trạng thái |
| --- | --- | --- |
| 6 | Time Model Views | ✅ Đã tạo |
| 8 | Instance Activity & Wait Events | ✅ Đã tạo |
| 9 | AWR | ✅ Đã tạo |
| 10 | Server-generated Alerts | ✅ Đã tạo |
| 11 | Statspack | ✅ Đã tạo |
| 12 | ADDM | ✅ Đã tạo |
| 13 | ASH | ✅ Đã tạo |
| 14 | Database Service Statistics + Module/Action/Client ID | ✅ Đã tạo |
| 15 | SQL Tracing với DBMS_MONITOR | ✅ Đã tạo |
| 16 | Real-time Database Operation Monitoring | ✅ Đã tạo |
| 17 | Automated Maintenance Tasks | ✅ Đã tạo |
| 19 | Enqueue Waits | ✅ Đã tạo |
| 20 | Latch & Mutex Contention | ✅ Đã tạo |
| 21 | Shared Pool Tuning | ✅ Đã tạo |
| 22 | Buffer Cache & Smart Flash Cache | ✅ Đã tạo |
| 23 | PGA Tuning | ✅ Đã tạo |
| 24 | Redo Path Tuning | ✅ Đã tạo |
| 25 | CPU Bottleneck Detection | ✅ Đã tạo |
| 26 | Disk I/O Tuning | ✅ Đã tạo |
| Còn lại 9 sections | — | ⬜ Chưa tạo |

### Gợi ý buổi tiếp theo

- **Section tiếp theo nên tạo: Section 27 — Index Defragmentation**
- Lý do: Section 27 (index bloat detection, rebuild vs coalesce, monitoring `BLEVEL` và `DEL_LF_ROWS`) là object-level tuning topic tự nhiên sau storage I/O — hoàn chỉnh picture từ file-level I/O xuống object-level index efficiency. Còn Section 28 (Row Migration & Chaining) là companion topic.

---

## Cập nhật: 2026-04-23 (buổi 5)

### Buổi học 2026-04-23 (buổi 5)

- Đã làm:
  - Tạo Senior Guide cho **Section 24 — Redo Path Tuning**
  - Tạo Senior Guide cho **Section 25 — CPU Bottleneck Detection**
- File đã tạo:
  - `section_all_new/section_24_redo_path_senior_guide.md`
  - `section_all_new/section_25_cpu_bottleneck_senior_guide.md`
- File đã cập nhật: `section_all_new/_INDEX.md` (Sections 24, 25 → ✅ Đã tạo)

### Senior Guide — Trạng thái section_all_new/ (2026-04-23 buổi 5)

| Section | Tên | Trạng thái |
| --- | --- | --- |
| 6 | Time Model Views | ✅ Đã tạo |
| 8 | Instance Activity & Wait Events | ✅ Đã tạo |
| 9 | AWR | ✅ Đã tạo |
| 10 | Server-generated Alerts | ✅ Đã tạo |
| 11 | Statspack | ✅ Đã tạo |
| 12 | ADDM | ✅ Đã tạo |
| 13 | ASH | ✅ Đã tạo |
| 14 | Database Service Statistics + Module/Action/Client ID | ✅ Đã tạo |
| 15 | SQL Tracing với DBMS_MONITOR | ✅ Đã tạo |
| 16 | Real-time Database Operation Monitoring | ✅ Đã tạo |
| 17 | Automated Maintenance Tasks | ✅ Đã tạo |
| 19 | Enqueue Waits | ✅ Đã tạo |
| 20 | Latch & Mutex Contention | ✅ Đã tạo |
| 21 | Shared Pool Tuning | ✅ Đã tạo |
| 22 | Buffer Cache & Smart Flash Cache | ✅ Đã tạo |
| 23 | PGA Tuning | ✅ Đã tạo |
| 24 | Redo Path Tuning | ✅ Đã tạo |
| 25 | CPU Bottleneck Detection | ✅ Đã tạo |
| Còn lại 10 sections | — | ⬜ Chưa tạo |

### Gợi ý buổi tiếp theo

- **Section tiếp theo nên tạo: Section 26 — Disk I/O Tuning** hoặc **Section 27 — Index Defragmentation**
- Lý do: Section 26 (V$FILESTAT, V$IOSTAT_FILE, ASM stripe, SAME principle) là natural companion sau Redo Path — hoàn chỉnh storage I/O picture. Section 27 (index rebuild, coalescing, monitoring bloat) là object-level topic độc lập, có thể làm song song.

---

## Cập nhật: 2026-04-23 (buổi 4)

### Buổi học 2026-04-23 (buổi 4)

- Đã làm:
  - Tạo Senior Guide cho **Section 22 — Buffer Cache & Smart Flash Cache**
  - Tạo Senior Guide cho **Section 23 — PGA Tuning**
- File đã tạo:
  - `section_all_new/section_22_buffer_cache_flash_cache_senior_guide.md`
  - `section_all_new/section_23_pga_senior_guide.md`
- File đã cập nhật: `section_all_new/_INDEX.md` (Sections 22, 23 → ✅ Đã tạo)

### Senior Guide — Trạng thái section_all_new/ (2026-04-23 buổi 4)

| Section | Tên | Trạng thái |
| --- | --- | --- |
| 6 | Time Model Views | ✅ Đã tạo |
| 8 | Instance Activity & Wait Events | ✅ Đã tạo |
| 9 | AWR | ✅ Đã tạo |
| 10 | Server-generated Alerts | ✅ Đã tạo |
| 11 | Statspack | ✅ Đã tạo |
| 12 | ADDM | ✅ Đã tạo |
| 13 | ASH | ✅ Đã tạo |
| 14 | Database Service Statistics + Module/Action/Client ID | ✅ Đã tạo |
| 15 | SQL Tracing với DBMS_MONITOR | ✅ Đã tạo |
| 16 | Real-time Database Operation Monitoring | ✅ Đã tạo |
| 17 | Automated Maintenance Tasks | ✅ Đã tạo |
| 19 | Enqueue Waits | ✅ Đã tạo |
| 20 | Latch & Mutex Contention | ✅ Đã tạo |
| 21 | Shared Pool Tuning | ✅ Đã tạo |
| 22 | Buffer Cache & Smart Flash Cache | ✅ Đã tạo |
| 23 | PGA Tuning | ✅ Đã tạo |
| Còn lại 12 sections | — | ⬜ Chưa tạo |

### Gợi ý buổi tiếp theo

- **Memory tuning trilogy hoàn chỉnh!** (Shared Pool → Buffer Cache → PGA)
- **Section tiếp theo nên tạo: Section 24 — Redo Path Tuning** hoặc **Section 25 — CPU Bottleneck**
- Lý do: Section 24 (log buffer, log file sync, LGWR, redo group sizing) là natural next step sau PGA — hoàn thành I/O subsystem layer (buffer → redo). Section 25 (CPU wait analysis, SYS_TIME_MODEL CPU%, top SQL by CPU) là independent topic có thể làm song song.

---

## Cập nhật: 2026-04-23 (buổi 3)

### Buổi học 2026-04-23 (buổi 3)

- Đã làm:
  - Tạo Senior Guide cho **Section 16 — Real-time Database Operation Monitoring**
  - Tạo Senior Guide cho **Section 17 — Automated Maintenance Tasks**
  - Tạo Senior Guide cho **Section 19 — Enqueue Waits**
  - Tạo Senior Guide cho **Section 20 — Latch & Mutex Contention**
  - Tạo Senior Guide cho **Section 21 — Shared Pool Tuning**
- File đã tạo:
  - `section_all_new/section_16_realtime_monitoring_senior_guide.md`
  - `section_all_new/section_17_automated_maintenance_senior_guide.md`
  - `section_all_new/section_19_enqueue_waits_senior_guide.md`
  - `section_all_new/section_20_latch_mutex_senior_guide.md`
  - `section_all_new/section_21_shared_pool_senior_guide.md`
- File đã cập nhật: `section_all_new/_INDEX.md` (Sections 16, 17, 19, 20, 21 → ✅ Đã tạo)

### Senior Guide — Trạng thái section_all_new/ (2026-04-23 buổi 3)

| Section | Tên | Trạng thái |
| --- | --- | --- |
| 6 | Time Model Views | ✅ Đã tạo |
| 8 | Instance Activity & Wait Events | ✅ Đã tạo |
| 9 | AWR | ✅ Đã tạo |
| 10 | Server-generated Alerts | ✅ Đã tạo |
| 11 | Statspack | ✅ Đã tạo |
| 12 | ADDM | ✅ Đã tạo |
| 13 | ASH | ✅ Đã tạo |
| 14 | Database Service Statistics + Module/Action/Client ID | ✅ Đã tạo |
| 15 | SQL Tracing với DBMS_MONITOR | ✅ Đã tạo |
| 16 | Real-time Database Operation Monitoring | ✅ Đã tạo |
| 17 | Automated Maintenance Tasks | ✅ Đã tạo |
| 19 | Enqueue Waits | ✅ Đã tạo |
| 20 | Latch & Mutex Contention | ✅ Đã tạo |
| 21 | Shared Pool Tuning | ✅ Đã tạo |
| Còn lại 14 sections | — | ⬜ Chưa tạo |

### Gợi ý buổi tiếp theo

- **Section tiếp theo nên tạo: Section 22 — Buffer Cache & Flash Cache** hoặc **Section 23 — PGA Tuning**
- Lý do: Section 22 (Buffer Cache sizing, V$DB_CACHE_ADVICE, Smart Flash Cache) là natural next step sau Shared Pool — complete the memory tuning trilogy (Shared Pool → Buffer Cache → PGA). Section 23 (PGA, workarea sizing, V$SQL_WORKAREA) closes the memory tuning picture.

---

## Cập nhật: 2026-04-23 (buổi 2)

### Buổi học 2026-04-23 (buổi 2)
- Đã làm:
  - Tạo Senior Guide cho **Section 15 — SQL Tracing với DBMS_MONITOR**
- File đã tạo:
  - `section_all_new/section_15_sql_tracing_senior_guide.md`
- File đã cập nhật: `section_all_new/_INDEX.md` (Section 15 → ✅ Đã tạo)

### Senior Guide — Trạng thái section_all_new/ (2026-04-23 buổi 2)

| Section | Tên | Trạng thái |
| --- | --- | --- |
| 6 | Time Model Views | ✅ Đã tạo |
| 8 | Instance Activity & Wait Events | ✅ Đã tạo |
| 9 | AWR | ✅ Đã tạo |
| 10 | Server-generated Alerts | ✅ Đã tạo |
| 11 | Statspack | ✅ Đã tạo |
| 12 | ADDM | ✅ Đã tạo |
| 13 | ASH | ✅ Đã tạo |
| 14 | Database Service Statistics + Module/Action/Client ID | ✅ Đã tạo |
| 15 | SQL Tracing với DBMS_MONITOR | ✅ Đã tạo |
| Còn lại 19 sections | — | ⬜ Chưa tạo |

### Gợi ý buổi tiếp theo
- **Section tiếp theo nên tạo: Section 16 — Real-time Database Operation Monitoring** hoặc **Section 19 — Enqueue Waits**
- Lý do: Section 16 (V$SQL_MONITOR, DBMS_SQLTUNE.REPORT_SQL_MONITOR) là natural complement của SQL Trace — realtime monitoring thay vì post-hoc analysis. Section 19 (Enqueue Waits) build trực tiếp trên TM lock case study từ Section 14.

---

## Cập nhật: 2026-04-23

### Buổi học 2026-04-23
- Đã làm:
  - Tạo Senior Guide cho **Section 14 — Database Service Statistics + Module/Action/Client ID**
- File đã tạo:
  - `section_all_new/section_14_database_service_statistics_senior_guide.md`
- File đã cập nhật: `section_all_new/_INDEX.md` (Section 14 → ✅ Đã tạo)

### Senior Guide — Trạng thái section_all_new/ (2026-04-23)

| Section | Tên | Trạng thái |
| --- | --- | --- |
| 6 | Time Model Views | ✅ Đã tạo |
| 8 | Instance Activity & Wait Events | ✅ Đã tạo |
| 9 | AWR | ✅ Đã tạo |
| 10 | Server-generated Alerts | ✅ Đã tạo |
| 11 | Statspack | ✅ Đã tạo |
| 12 | ADDM | ✅ Đã tạo |
| 13 | ASH | ✅ Đã tạo |
| 14 | Database Service Statistics + Module/Action/Client ID | ✅ Đã tạo |
| Còn lại 20 sections | — | ⬜ Chưa tạo |

### Gợi ý buổi tiếp theo
- **Section tiếp theo nên tạo: Section 15 — SQL Tracing với DBMS_MONITOR**
- Lý do: Natural complement của Section 14 — khi ASH/CLIENT_STATS identify vấn đề ở module/action level, SQL Tracing (DBMS_MONITOR.SESSION_TRACE_ENABLE) đo exact microsecond timing từng bước execution

---

## Cập nhật: 2026-04-22 (buổi 3)

### Buổi học 2026-04-22 (buổi 3)

- Đã làm:
  - Tạo Senior Guide cho **Section 10 — Server-generated Alerts**
  - Tạo Senior Guide cho **Section 11 — Statspack**
- File đã tạo:
  - `section_all_new/section_10_server_generated_alerts_senior_guide.md`
  - `section_all_new/section_11_statspack_senior_guide.md`
- File đã cập nhật: `section_all_new/_INDEX.md` (Section 10, 11 → ✅ Đã tạo)

### Senior Guide — Trạng thái section_all_new/ (2026-04-22 buổi 3)

| Section | Tên | Trạng thái |
| --- | --- | --- |
| 6 | Time Model Views | ✅ Đã tạo |
| 8 | Instance Activity & Wait Events | ✅ Đã tạo |
| 9 | AWR | ✅ Đã tạo |
| 10 | Server-generated Alerts | ✅ Đã tạo |
| 11 | Statspack | ✅ Đã tạo |
| 12 | ADDM | ✅ Đã tạo |
| 13 | ASH | ✅ Đã tạo |
| Còn lại 21 sections | — | ⬜ Chưa tạo |

### Gợi ý buổi tiếp theo

- **Section tiếp theo nên tạo: Section 14 — Database Service Statistics** hoặc **Section 15 — SQL Tracing**
- Lý do: Section 14 build trực tiếp trên ASH MODULE/ACTION/CLIENT_ID dimensions; Section 15 là natural complement của ASH — khi ASH identify vấn đề, SQL Tracing đo microsecond timing

---

## Cập nhật: 2026-04-22 (buổi 2)

### Buổi học 2026-04-22 (tiếp theo)

- Đã làm:
  - Tạo Senior Guide cho **Section 12 — ADDM** (Automatic Database Diagnostic Monitor)
  - Tạo Senior Guide cho **Section 13 — ASH** (Active Session History — 2 practices)
- File đã tạo:
  - `section_all_new/section_12_addm_senior_guide.md`
  - `section_all_new/section_13_ash_senior_guide.md`
- File đã cập nhật: `section_all_new/_INDEX.md` (Section 12, 13 → ✅ Đã tạo)

### Senior Guide — Trạng thái section_all_new/ (2026-04-22 buổi 2)

| Section | Tên | Trạng thái |
| --- | --- | --- |
| 6 | Time Model Views | ✅ Đã tạo |
| 8 | Instance Activity & Wait Events | ✅ Đã tạo |
| 9 | AWR | ✅ Đã tạo |
| 12 | ADDM | ✅ Đã tạo |
| 13 | ASH | ✅ Đã tạo |
| Còn lại 23 sections | — | ⬜ Chưa tạo |

### Gợi ý buổi tiếp theo

- **Section tiếp theo nên tạo: Section 14 — Database Service Statistics** hoặc **Section 15 — SQL Tracing**
- Lý do: Section 14 build trực tiếp trên ASH dimensions (MODULE/ACTION/CLIENT_ID attributes); Section 15 là natural complement của ASH — khi ASH identify vấn đề, SQL Tracing đo chính xác microsecond timing

---

## Cập nhật: 2026-04-22

### Buổi học vừa rồi

- Đã làm:
  - Tạo Senior Guide cho **Section 8 — Instance Activity & Wait Events**
  - Tạo Senior Guide cho **Section 9 — AWR** (Automatic Workload Repository)
- File đã tạo:
  - `section_all_new/section_8_instance_activity_wait_events_senior_guide.md`
  - `section_all_new/section_9_awr_senior_guide.md`
- File đã cập nhật: `section_all_new/_INDEX.md` (Section 8, 9 → ✅ Đã tạo)

### Senior Guide — Trạng thái section_all_new/ (2026-04-22)

| Section | Tên | Trạng thái |
| --- | --- | --- |
| 6 | Time Model Views | ✅ Đã tạo |
| 8 | Instance Activity & Wait Events | ✅ Đã tạo |
| 9 | AWR | ✅ Đã tạo |
| 10–36 | Còn lại 26 sections | ⬜ Chưa tạo |

### Gợi ý buổi 2026-04-22

- **Section tiếp theo nên tạo: Section 12 — ADDM** hoặc **Section 13 — ASH**
- Lý do: ADDM và ASH đều build trực tiếp trên AWR data; ASH đặc biệt quan trọng vì giải quyết limitation 1-hour ASH ring buffer của Section 8

---

## Cập nhật: 2026-04-21

### Buổi học 2026-04-21

- Đã làm:
  - Tích hợp 2 file mới (`oracle_dba_system_prompt.md`, `oracle_dba_README.md`) vào CLAUDE.md
  - Tạo thư mục `section_all_new/` với framework Senior DBA
  - Tạo `section_all_new/_INDEX.md` — index 29 sections + cấu trúc bài học + bảng nguồn ưu tiên 5 cấp
  - Tạo `section_all_new/section_6_time_model_senior_guide.md` — tổng hợp từ pdf_extracted + section_all
- File đã tạo:
  - `section_all_new/_INDEX.md`
  - `section_all_new/section_6_time_model_senior_guide.md`
- File đã cập nhật:
  - `CLAUDE.md` — bổ sung workflow section_all_new, dual-source synthesis

### Senior Guide — Trạng thái section_all_new/

| Section  | Tên                      | Trạng thái      |
| -------- | ------------------------ | --------------- |
| 6        | Time Model Views         | ✅ Đã tạo       |
| 8–36     | Còn lại 28 sections      | ⬜ Chưa tạo     |

### Gợi ý buổi 2026-04-21

- Tiếp tục tạo Senior Guide cho section_all_new/ theo thứ tự học tập
- Section tiếp theo nên tạo: **Section 8 — Instance Activity & Wait Events** (nền tảng cho AWR/ASH)
- Lý do: Section 8 là bước đệm quan trọng trước AWR (Section 9), có pdf_extracted sẵn

---

## Cập nhật: 2026-04-20

### Buổi học 2026-04-20

- Đã làm: Section 36 (Database Replay) — **SECTION CUỐI CÙNG**
- File đã tạo:
  - `section_all/section_36_database_replay_guide.md`

### Trạng thái tổng thể

| Section | Tên | Trạng thái |
| --- | --- | --- |
| 2 | Chuẩn bị môi trường (SOE Schema, VirtualBox) | ⚠️ Học rồi, chưa có file |
| 6 | Time Model Views | ✅ Xong |
| 8 | Instance Activity & Wait Events | ✅ Xong |
| 9 | AWR (Snapshots, Reports, SQL Reports, Baselines) | ✅ Xong |
| 10 | Server-generated Alerts | ✅ Xong |
| 11 | Statspack | ✅ Xong |
| 12 | ADDM | ✅ Xong |
| 13 | ASH (Active Session History) | ✅ Xong |
| 14 | Database Service Statistics + Module/Action/Client ID | ✅ Xong |
| 15 | SQL Tracing với DBMS_MONITOR | ✅ Xong |
| 16 | Real-time Database Operation Monitoring | ✅ Xong |
| 17 | Automated Maintenance Tasks | ✅ Xong |
| 19 | Enqueue Waits | ✅ Xong |
| 20 | Latch & Mutex Contention | ✅ Xong |
| 21 | Shared Pool Tuning | ✅ Xong |
| 22 | Memory Tuning (Buffer Cache, Flash Cache) | ✅ Xong |
| 23 | PGA Tuning | ✅ Xong |
| 24 | Redo Path Tuning | ✅ Xong |
| 25 | CPU Bottleneck Detection | ✅ Xong |
| 26 | Disk I/O Tuning | ✅ Xong |
| 27 | Index Defragmentation | ✅ Xong |
| 28 | Row Migration & Row Chaining | ✅ Xong |
| 29 | Table Fragmentation | ✅ Xong |
| 30 | Table Compression | ✅ Xong |
| 31 | In-Memory Column Store | ✅ Xong |
| 32 | Database Connection Optimization | ✅ Xong |
| 34 | OS Performance (Linux, OSWatcher) | ✅ Xong |
| 35 | SQL Performance Analyzer | ✅ Xong |
| 36 | Database Replay | ✅ Xong |

### Tiến độ tổng thể

- Hoàn thành: **28 / 29 sections** (97%)
- Có file guide: 28 sections
- Cần tạo lại file: 1 section (Section 2)

### Gợi ý buổi 2026-04-20

- **Toàn bộ 28/29 sections đã hoàn thành!**
- Còn lại: Section 2 — Chuẩn bị môi trường (đã học nhưng chưa có guide file)
- Có thể ôn tập, làm quiz, hoặc tạo lại guide cho Section 2


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/progress.md`
