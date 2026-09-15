---
title: labs/ — Phòng thực hành Oracle Performance Tuning
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/labs/README.md
---

# labs/ — Phòng thực hành Oracle Performance Tuning

> Môi trường: VM `srv1` (Vagrant, Oracle 19c EE), PDB `ORADB`, schema `SOE`.
> Chi tiết dựng môi trường: [ke_hoach/03_phase2_setup_log.md](../ke-hoach/003-phase2-setup-log.md)

## Bắt đầu mỗi buổi

```powershell
cd D:\Dba_project\vagrant-projects\OracleDatabase\19.3.0
vagrant up                # bật VM (DB tự start, chờ ~1-2 phút)

cd D:\Dba_project\The-Oracle-Database-Performance-Tuning-Course
sqlplus -S -L "system/oracle_4U@//localhost:15210/ORADB" "@labs\_toolkit\00_env_check.sql"
```

⚠️ Quy tắc PowerShell: luôn **quote chuỗi connect và `@file`** (ký tự `@` không quote bị PowerShell hiểu là splatting).

**Chuẩn bị một lần** (và làm lại sau mỗi `vagrant snapshot restore baseline`):

1. User `soe` cần đọc `v$session_event` cho `before_after.sql` — grant bằng SYS (system không grant được object của SYS):

```powershell
sqlplus "sys/oracle_4U@//localhost:15210/ORADB as sysdba"
# GRANT SELECT ON sys.v_$session_event TO soe;
```

2. Bộ sinh tải (`workload_soe.sql`) cần password OS của user oracle trong VM (credential `LAB_OS_CRED` tự tạo khi chạy lần đầu):

```powershell
cd D:\Dba_project\vagrant-projects\OracleDatabase\19.3.0
vagrant ssh -c "echo 'oracle:oracle_4U' | sudo chpasswd"
```

Cuối buổi: `vagrant halt`. Trước lab "nguy hiểm": `vagrant snapshot save <tên>`; quay về sạch: `vagrant snapshot restore baseline`.

## Kết nối

| Mục đích | Lệnh |
|---|---|
| DBA (toolkit, tạo tablespace, ALTER SYSTEM) | `sqlplus system/oracle_4U@//localhost:15210/ORADB` |
| Schema thực hành | `sqlplus soe/soe@//localhost:15210/ORADB` |
| SYSDBA trong VM | `vagrant ssh` → `sudo -u oracle -i` → `sqlplus / as sysdba` |

## Chạy lab từ TRONG VM (thay vì từ host)

Thư mục `labs/` này được **mount sẵn tại `/labs` trong VM** (synced folder — sửa script trên host là VM thấy ngay). SSH vào, thành user oracle rồi chạy tại chỗ:

```bash
vagrant ssh                       # hoặc: ssh srv1 (xem hướng dẫn)
sudo -u oracle -i
cd /labs/section_28
sqlplus soe/soe@//localhost:1521/ORADB    # trong VM port là 1521, không phải 15210
```

Chi tiết SSH (account/pass/key, 3 cách vào, bẫy vboxsf, troubleshooting): [ke_hoach/05_huong_dan_ssh_vm.md](../ke-hoach/005-huong-dan-ssh-vm.md)

## 📖 Sổ tay chẩn đoán tổng hợp

**[SO_TAY_CHAN_DOAN.md](so-tay-chan-doan.md)** — tổng hợp toàn bộ code chẩn đoán quan trọng của khóa học (23 nhóm chuyên đề): mỗi query kèm ý nghĩa, cách đọc số, và case cần xử lý; cuối file có bảng tra nhanh *triệu chứng → hướng điều tra*. Dùng làm tài liệu tra cứu khi "chạy mù" hoặc xử lý sự cố thật.

**[SO_TAY_MO_HINH.html](so-tay-mo-hinh.html)** — 🎨 **bản tương tác, mở bằng trình duyệt** (khuyên dùng): 16 mô hình vẽ bằng đồ họa màu, có **cây quyết định bấm từng bước** (M1), bộ lọc wait event → root cause (M5), sơ đồ block trực quan (M9/M13/M14), đường cong advisory (M8)… Mỗi mô hình 4 lớp: *sơ đồ + cách đọc + 🧭 diễn giải mạch lạc + 🎓 mở rộng chuyên sâu* + quiz. **Kèm phần chuyên gia E1–E6** (ngoài giáo trình): AAS/Little's Law, lý thuyết hàng đợi, Method R (Millsap), 3-circle (Shallahamer), Cardinality Feedback (Breitling), session-first/snapper (Poder).

**[SO_TAY_MO_HINH.md](so-tay-mo-hinh.md)** — cùng 16 mô hình dạng sơ đồ Mermaid (xem trên GitHub/VS Code preview); bản sao lưu: `SO_TAY_MO_HINH_BK.md`. Học mô hình TRƯỚC, tra code SAU.

## `_toolkit/` — bộ chẩn đoán dùng chung

Dùng theo đúng thứ tự tư duy tuning: **DB Time → Wait Event → SQL/Session → Root cause → Fix → Đo lại**.

| Script | Trả lời câu hỏi | Chạy bằng |
|---|---|---|
| `00_env_check.sql` | Môi trường sẵn sàng chưa? | system |
| `time_model.sql` | DB Time đang tiêu vào đâu? (bước 1) | system |
| `top_waits.sql` | Đang chờ cái gì? CPU hay wait? (bước 2) | system |
| `ash_now.sql` | 5 phút qua session nào/SQL nào bận? (bước 3) | system |
| `top_sql.sql &1` | SQL nào tốn nhất? (`ELAPSED`\|`CPU`\|`GETS`) | system |
| `awr_snap.sql` | Chụp AWR snapshot trước/sau workload | system |
| `before_after.sql &1` | Đoạn workload này tốn bao nhiêu? (`BEGIN`/`END`, **cùng 1 session**) | user chạy workload (soe) |
| `workload_soe.sql &1 &2` | Sinh tải: N phiên SOE **thật** × S giây (thay Swingbench) | system |
| `workload_stop.sql` | Cắt tải sớm (cờ dừng — không kill session) | system |

**Vì sao `workload_soe.sql` đi đường vòng external job → `soe_load.sh` → spawn sqlplus:** job PLSQL_BLOCK chạy bằng slave J00x = background process, thời gian tiêu tốn **không tính vào DB time** (đo được: job 15s → +0.01s DB time). Course đo mọi thứ bằng DB time/foreground waits nên tải phải là session thật. Chi tiết trong header script.

## `_frag_check/` — bộ kiểm tra phân mảnh toàn hệ thống

Chẩn đoán **mức độ phân mảnh của cả database** (không gắn với lab nào): bảng/HWM, block,
row migration & chaining, index, statistics, không gian tablespace — rồi chốt bằng câu hỏi
quan trọng nhất: *phân mảnh đó có thật sự tốn DB time không*.

| Script | Trả lời | Ghi chú |
|---|---|---|
| `_frag_config.sql` | Cấu hình phạm vi + ngưỡng (**nơi duy nhất cần sửa**) | mọi script đều include |
| `00_run_all.sql` | Chạy tất cả → `frag_report_<ts>.txt` | so file trước/sau khi fix |
| `01_tables_hwm.sql` | Bảng/partition/LOB nào HWM cao hơn dữ liệu thật | S29 |
| `02_blocks_space_usage.sql` | Bên trong block: FULL hay FS1 (gần rỗng) | S29 — `DBMS_SPACE` |
| `03_rows_migrated_chained.sql` | Row migration vs chaining + triệu chứng runtime | S28, S8 |
| `04_indexes.sql` | Index UNUSABLE, leaf thừa, BLEVEL, không ai dùng, trùng lặp | S27, S26 |
| `05_indexes_validate.sql` | `DEL_LF_ROWS` thật | ⚠️ khoá DML — mặc định tắt |
| `06_stats_health.sql` | Stats có đáng tin không (chạy **trước** 01/04) | S17, S28, S29 |
| `07_tablespace_free_space.sql` | Không gian trống bị vụn, headroom thật, recyclebin | mở rộng thực tế |
| `08_generate_fix_ddl.sql` | Sinh `frag_fix_<ts>.sql` — **không tự chạy** | S27/28/29 |
| `09_segment_advisor.sql` | Ý kiến độc lập của Oracle + xu hướng tăng trưởng | S17, S29 |
| `10_impact_awr.sql` | **Phân mảnh có tốn DB time không** — chốt việc cần làm | S6/8/9/13/26 |

⚠️ Chưa kiểm chứng trên VM. Cách dùng, ngưỡng đọc số, cây quyết định fix và bẫy thực tế:
[`_frag_check/README.md`](frag-check/readme.md).

## `section_<N>/` — lab theo section, 5 file cố định

| File | Vai trò |
|---|---|
| `01_setup.sql` | Tạo object + dữ liệu tái tạo vấn đề |
| `02_workload.sql` | Sinh tải + **đo số liệu baseline** (trước khi fix) |
| `03_diagnose.sql` | Chẩn đoán: xác nhận root cause bằng số liệu |
| `04_fix.sql` | Sửa + **đo lại để chứng minh** (so với baseline) |
| `99_cleanup.sql` | Trả môi trường về ban đầu |

File `05_*.sql` (nếu có) là thí nghiệm mở rộng, không bắt buộc.

**Quy trình chuẩn một lab:** đọc header từng file → **dự đoán kết quả trước khi chạy** → `01 → 02 (ghi số) → 03 → 04 (so số) → 99`.

**Chế độ "chạy mù" (ôn tập):** chạy `01 + 02` của một section ngẫu nhiên rồi tự chẩn đoán chỉ bằng `_toolkit/`, sau đó mới mở `03_diagnose.sql` so đáp án.

## Lab hiện có

Mỗi lab có 2 tài liệu: `README.md` (tham chiếu cô đọng: số đo thật, bẫy, câu hỏi tự kiểm tra) và `HUONG_DAN_HOC_SECTION_<N>.md` (kịch bản buổi học đầy đủ từng bước: dự đoán trước khi chạy → output kỳ vọng → debrief có đáp án → sự cố thường gặp) — dùng file hướng dẫn học khi tự học không có Claude dẫn.

| Lab | Chủ đề | Ghi chú |
|---|---|---|
| [section_2/](section_2/) | Kiểm chứng môi trường + smoke test bộ sinh tải | system; không tạo object |
| [section_6/](section_6/) | Time Model Views | system; tải 3 mức 2/4/8 user |
| [section_8/](section_8/) | Instance Activity & Wait Events | 01 bằng soe; hung session tự động (`lock_demo.sh`) |
| [section_9/](section_9/) | AWR: settings, report, SQL report, baseline | system; bài học 2 stream AWR CDB/PDB; **+ hộp AWR use cases 05-09** (plan regression, trend/AAS, diff report, top segment/IO, hygiene — ⚠️ 05-09 chưa kiểm chứng VM) |
| [section_10/](section_10/) | Server-generated Alerts | **SYS qua CDB root** (ORA-65040); bão lock (`lock_storm.sh`) |
| [section_11/](section_11/) | Statspack | ⚠️ chưa kiểm chứng VM; 3 vai: SYS cài → system tải → PERFSTAT report |
| [section_12/](section_12/) | ADDM | ⚠️ chưa kiểm chứng VM; DBMS_ADDM trên snapshot PDB-local + compare report |
| [section_13/](section_13/) | ASH & Dimension Views | ⚠️ chưa kiểm chứng VM; `ash_lock_demo.sh` — điều tra hậu kỳ tới đúng ROW |
| [section_14/](section_14/) | Service/Module/Client-ID stats | ⚠️ chưa kiểm chứng VM; vụ án ETL APPEND → enq: TM (`etl_load.sh`) |
| [section_15/](section_15/) | SQL Tracing (DBMS_MONITOR) | ⚠️ chưa kiểm chứng VM; **chạy TRONG VM** (trcsess/tkprof là lệnh OS) |
| [section_16/](section_16/) | Real-time SQL Monitoring | ⚠️ chưa kiểm chứng VM; composite DBOP + plan sống (`monitor_client.sh`) |
| [section_17/](section_17/) | Automated Maintenance Tasks | ⚠️ chưa kiểm chứng VM; lab cấu hình — 99_cleanup khôi phục window |
| [section_19/](section_19/) | Enqueue Waits | ⚠️ chưa kiểm chứng VM; `lock_pair.sh` 120s — V$LOCK 3 thì điều tra |
| [section_20/](section_20/) | Latch & Mutex Contention | ⚠️ chưa kiểm chứng VM; lab dạng fix (bind vs literal); 05 cần SYS (X$BH) |
| [section_21/](section_21/) | Shared Pool + Session Cursors + Result Cache | ⚠️ chưa kiểm chứng VM; gộp Practice 20-22; KHÔNG restart DB (ALTER SESSION thay thế); 06 cần SYS (X$KGLOB); tái dùng section_20/hard_parse.sh |
| [section_22/](section_22/) | Buffer Cache + KEEP Pool (+ Flash Cache) | ⚠️ chưa kiểm chứng VM; gộp Practice 23-24; 01 cần SYS (grant V_$MYSTAT); "lũ FTS" thay việc bóp cache 10MB+restart; 05 flash cache TRONG VM (2 restart) |
| [section_23/](section_23/) | PGA Tuning | ⚠️ chưa kiểm chứng VM; Practice 25; thí nghiệm bóp SORT_AREA_SIZE ép tràn temp; đọc V$PGA_TARGET_ADVICE (loại overalloc trước) |
| [section_24/](section_24/) | Redo Path | ⚠️ chưa kiểm chứng VM; Practice 26; **CHẠY TRONG VM** (redo DDL cấp CDB) + **snapshot bắt buộc**; thu redo 10MB→đo→phục hồi; `redo_update.sh` |
| [section_25/](section_25/) | CPU Bottleneck Detection | ⚠️ chưa kiểm chứng VM; Practice 27; lab **chẩn đoán** (04_usecase); external vs DB CPU qua `%Busy CPU` = `cpu_sample.sql` (delta V$OSSTAT vs Time Model); `cpu_load.sh <db\|external>`; 05 parse CPU (tái dùng section_20/hard_parse.sh) |
| [section_26/](section_26/) | Disk I/O Tuning | ⚠️ chưa kiểm chứng VM; Practice 28; lab **fix**: MOVE → index UNUSABLE → FTS → I/O bùng nổ, REBUILD; 05 CALIBRATE_IO **TRONG VM** (SETALL restart + QUIESCE ~9', **snapshot bắt buộc**) |
| [section_27/](section_27/) | Index Defragmentation | ⚠️ chưa kiểm chứng VM; Practice 29; lab **fix + so sánh** COALESCE vs REBUILD (myth-busting self-balancing); `idx_dml_load.sh` để REBUILD ONLINE hang; 05 SHRINK SPACE |
| [section_28/](section_28/) | Row Migration & Row Chaining | Lab mẫu chuẩn đầu tiên; `05_row_chaining_32k.sql` cần system |
| [section_29/](section_29/) | Table Fragmentation | ⚠️ chưa kiểm chứng VM; Practice 31; lab **fix**: bulk delete → HWM cao → FTS đọc thừa, SHRINK SPACE CASCADE; chứng minh fragment chỉ phạt FTS không phạt index; 3 góc đo (AVG_SPACE/DBMS_SPACE/HWM); `cust_update.sh` cho ORA-00054 |
| [section_30/](section_30/) | Table Compression | ⚠️ chưa kiểm chứng VM; Practice 32; lab **demo**: Basic (chỉ nén direct-path) vs Advanced (nén cả conventional, **license!**); ratio phụ thuộc độ lặp; T3 append-compress nạp nhanh nhất + query ít reads |
| [section_31/](section_31/) | In-Memory Column Store | ⚠️ chưa kiểm chứng VM; Practice 33; **TRONG VM + snapshot bắt buộc** (INMEMORY_SIZE + restart) + **license**; dual-format, populate async (chờ COMPLETED), `TABLE ACCESS INMEMORY FULL`, footprint IM << segment |
| [section_32/](section_32/) | Database Connection Optimization | ⚠️ chưa kiểm chứng VM; Practice 34; đòn bẩy chính ARRAYSIZE (round-trip = CEIL(rows/arraysize), đo qua AUTOTRACE — cần PLUSTRACE); SDU/socket (BDP) là config phụ (04, LAN latency thấp → tác dụng ít) |
| [section_34/](section_34/) | OS Performance (Linux + OSWatcher) | ⚠️ chưa kiểm chứng VM; Practice 35+36; **lab tầng OS** (shell, không SQL): vmstat/top/iostat/mpstat/ps/iotop/netstat theo USE method; `os_stress.sh cpu\|io`; **cầu SPID** `02_map_os_to_db.sql` nối OS↔DB; OSWatcher (Java 8) |
| [section_35/](section_35/) | SQL Performance Analyzer (SPA) | ⚠️ chưa kiểm chứng VM; Practice 37; **TRONG VM + snapshot** (OFE + restart 2 lần) + **license RAT**; STS → TEST EXECUTE before/after quanh OFE 11.2→12.2 → COMPARE PERFORMANCE; change assurance per-SQL; `client_wrkld.sql` nạp cursor cache |
| [section_36/](section_36/) | Database Replay | ⚠️ chưa kiểm chứng VM; Practice 38; **TRONG VM + snapshot bắt buộc** + **license RAT**; vòng đời **5 pha** Capture→Preprocess→Replay→Report; `wrc_replay.sh` (client OS); single-VM bỏ restore-to-SCN → divergence≠0 (điểm học); mức toàn workload/concurrency (bổ sung SPA) |

**Quy ước file `04_*`:** lab dạng *fix* (20, 28...) dùng `04_fix.sql`; lab dạng *monitoring* (6, 8, 9, 10, 11–17, 19) không có gì để fix — `04_usecase_*.sql` là tình huống áp dụng thực tế của công cụ vừa học.

## Quy ước viết lab mới

- SQL gốc lấy từ `pdf_extracted/` (script Ahmed Baraka) làm xương sống, chú thích tiếng Việt, ghi rõ chỗ nào **khác bản gốc và vì sao** (tối ưu cho 19c/môi trường Vagrant).
- Header mỗi file ghi: chạy bằng user nào, lệnh chạy từ host, kỳ vọng thấy gì.
- Mọi DROP bọc trong PL/SQL nuốt lỗi → chạy lại được từ đầu không cần dọn tay.
- `04_fix.sql` bắt buộc kết thúc bằng so sánh số liệu trước/sau.


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/labs/README.md`
