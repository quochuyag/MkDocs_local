---
title: Lab Section 9 — AWR (Automatic Workload Repository)
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/labs/section_9/README.md
---

# Lab Section 9 — AWR (Automatic Workload Repository)

> Nguồn: Practice 4–7 (Ahmed Baraka) gộp thành 1 lab · Guide: [section_all/section_9_awr_guide.md](../../section-all/section-9-awr-guide.md)
> Chạy từ thư mục này (`labs/section_9/`). Quy ước chung: [labs/README.md](../readme.md)

**Câu hỏi lab trả lời:** AWR lưu gì, quản lý thế nào, và dùng nó chứng minh "cùng một SQL, hai execution plan, chi phí khác nhau 12 lần" ra sao?

## Chạy lab — user `system`

```powershell
sqlplus system/oracle_4U@//localhost:15210/ORADB
```

```
@01_setup.sql              -- settings 2 stream AWR, snapshot thủ công, SYSAUX, tạo LAB_ORDERS2
@02_workload.sql           -- ~3 phút: snap B → 30 lần FTS → snap M → index → 30 lần nữa → snap E
@03_diagnose.sql           -- xuất AWR report + AWR SQL report (2 file .txt) + số từ DBA_HIST_SQLSTAT
@04_usecase_baseline.sql   -- baseline LAB9_NORMAL + baseline template (demo)
@99_cleanup.sql
```

## Hộp công cụ AWR use cases (05-09 — mở rộng, chạy độc lập sau 02)

Mỗi script trả lời MỘT câu hỏi production thật; chạy được trên mọi DB có AWR (không riêng lab):

| Script | Câu hỏi production | Nguồn dữ liệu chính |
|---|---|---|
| `05_usecase_plan_regression.sql` | "Báo cáo hôm qua 2s, nay 40s — SQL nào vừa ĐỔI PLAN?" | DBA_HIST_SQLSTAT (máy dò ≥2 plan, xếp theo độ lệch) + DBMS_XPLAN.DISPLAY_AWR |
| `06_usecase_trend_dbtime.sql` | "Hệ thống có nặng dần không? Cao điểm giờ nào? Do CPU hay WAIT?" | DBA_HIST_SYS_TIME_MODEL/SYSSTAT (delta + **AAS**) |
| `07_usecase_diff_report.sql` | "Batch đêm qua 3h, đêm kia 1h — hai đêm khác nhau chỗ nào?" | `AWR_DIFF_REPORT_TEXT` — 2 cửa sổ cạnh nhau, cột Diff |
| `08_usecase_top_segments_io.sql` | "I/O tăng vọt — bảng/index nào, datafile nào, đọc mất mấy ms?" | DBA_HIST_SEG_STAT(+_OBJ), DBA_HIST_FILESTATXS |
| `09_usecase_awr_hygiene.sql` | "AWR của DB lạ này có tin được không?" — checklist tiếp quản | DBA_HIST_SNAPSHOT (nhịp chụp, restart), WR_CONTROL, V$SYSAUX_OCCUPANTS, colored SQL/baseline mồ côi |

Khác course: `run_query.sh` 30 phiên → vòng lặp 30 executions; `awrrpt.sql`/`awrsqrpt.sql` (interactive) → hàm `AWR_REPORT_TEXT`/`AWR_SQL_REPORT_TEXT` + SPOOL; ANALYZE → DBMS_STATS. Trong VM: đổi `DEFINE spool_dir = /tmp` trong 03 (oracle không ghi được vào /labs).

## Số đo thật (VM srv1, 2026-07-14, LAB_ORDERS2 ≈ 140k rows, lọc 10%)

| Pha | PLAN_HASH_VALUE | Executions | Buffer gets/exec | Elapsed/exec |
|---|---|---|---|---|
| Full table scan (snap 3→4) | 44121814 | 30 | **1,765.6** | 6.68 ms |
| Index range scan (snap 4→5) | 321851430 | 30 | **147.0** | 1.02 ms |

Cùng một `SQL_ID` (`00wtg6c16ut2p`) — AWR SQL report hiện cả 2 plan cạnh nhau; nếu production thấy một SQL có nhiều plan chênh nhau cỡ này thì phải tìm root cause (stats? bind peeking? index mới?).

## Bài học multitenant KHÔNG có trong course (đo được trên lab)

Trong PDB, `DBA_HIST_WR_CONTROL`/`DBA_HIST_SNAPSHOT` trộn **hai stream AWR độc lập**:

- **CDB stream** (MMON chụp ở root, interval 60p) — snap_id dãy riêng
- **PDB-local stream** — mặc định TẮT (interval hiển thị `+40150` ngày); `CREATE_SNAPSHOT` chạy trong PDB rơi vào stream này với **dãy snap_id riêng bắt đầu từ 1**

Hệ quả: mọi thao tác AWR trong PDB **phải lọc `dbid = con_dbid`** trước khi lấy MAX(snap_id) — quên là dính `ORA-13506 invalid snapshot range` (đã dính thật khi build lab). `MODIFY_SNAPSHOT_SETTINGS(interval=>30)` trong PDB đồng thời BẬT auto-snapshot PDB; muốn tắt lại: `interval => 0`.

## Câu hỏi tự kiểm tra

1. AWR cần điều kiện gì để hoạt động? Snapshot level 1 và level 2 (`FLUSH_LEVEL=ALL`) khác gì?
2. `ADD_COLORED_SQL` giải quyết vấn đề gì? Không color thì SQL nào được AWR giữ lại?
3. Interval 30p thay vì 60p: được gì, mất gì?
4. Baseline khác snapshot thường chỗ nào? `SYSTEM_MOVING_WINDOW` dùng cho việc gì?
5. Vì sao tác giả course khuyên KHÔNG dựa vào baseline template mà dùng Scheduler job?


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/labs/section_9/README.md`
