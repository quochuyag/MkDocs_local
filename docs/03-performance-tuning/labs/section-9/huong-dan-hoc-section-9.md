---
title: '📚 Hướng dẫn học Section 9 — AWR: Reports, SQL Reports, Baselines (thực hành trong
  Linux VM)'
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/labs/section_9/HUONG_DAN_HOC_SECTION_9.md
---

# 📚 Hướng dẫn học Section 9 — AWR: Reports, SQL Reports, Baselines (thực hành trong Linux VM)

> Số đo mẫu trong file này là **số thật đo trên VM 2026-07-14**.
> Thời lượng gợi ý: ~90 phút (lecture 20' + lab 50' + debrief 20').
> Nguồn: Practice 4–7 (Ahmed Baraka) gộp thành 1 lab + guide [section_all/section_9_awr_guide.md](../../section-all/section-9-awr-guide.md) · [README lab](readme.md)

---

## 0. Kiến thức nền 5 phút (đọc trước khi gõ lệnh)

Section 8 kết thúc bằng bài học đau: mọi view V$SESSION* **chết theo session**. AWR là câu trả lời — MMON chụp toàn bộ số liệu hiệu năng định kỳ vào SYSAUX, giữ N ngày.

| Khái niệm | Nhớ nhanh |
|---|---|
| **Snapshot** | Ảnh chụp toàn bộ V$ stats tại 1 thời điểm; mặc định 60 phút/lần, giữ 8 ngày |
| **3 điều kiện sống của AWR** | `STATISTICS_LEVEL >= TYPICAL` + MMON còn sống + SYSAUX còn chỗ |
| **AWR report** | So 2 snapshot → "trong cửa sổ đó database làm gì/chờ gì" |
| **AWR SQL report** | Lịch sử 1 SQL_ID qua các snapshot — kể cả khi nó có NHIỀU execution plan |
| **Baseline** | "Đóng băng" cặp snapshot đại diện trạng thái bình thường: purge không xóa, làm mốc so sánh, nuôi adaptive thresholds |

**⚠️ Bài học multitenant KHÔNG có trong course** (sẽ thấy tận mắt ở lab): trong PDB, `DBA_HIST_*` trộn **HAI stream AWR độc lập** — CDB stream (MMON chụp ở root) và PDB-local stream (mặc định TẮT) — mỗi stream một dãy `snap_id` RIÊNG, phân biệt bằng `DBID`. Mọi thao tác AWR trong PDB phải lọc `dbid = con_dbid` trước, quên là `ORA-13506`.

**Chuỗi tư duy của lab:** quản lý settings/snapshot → dựng "lịch sử hiệu năng" có chủ đích (1 SQL, 2 plan) → đọc lại từ AWR → đóng băng làm baseline.

---

## 1. Khởi động môi trường (5 phút)

### 1.1. Bật VM (PowerShell trên host)

```powershell
cd D:\Dba_project\vagrant-projects\OracleDatabase\19.3.0
vagrant up
```

### 1.2. SSH vào VM và thành user oracle

```powershell
vagrant ssh
```

```bash
sudo -u oracle -i
cd /labs/section_9   # ⚠️ BẮT BUỘC: script gọi ../_toolkit/
```

### 1.3. Kiểm tra môi trường sẵn sàng

```bash
echo exit | sqlplus -S -L system/oracle_4U@//localhost:1521/ORADB @../_toolkit/00_env_check.sql
```

**Kỳ vọng:** 8 mục PASS.

---

## 2. Lab chính (user `system`, ~50 phút)

```bash
sqlplus system/oracle_4U@//localhost:1521/ORADB
```

> Trong VM port là **1521**. (Từ host Windows mới là 15210.)

### Bước 1 — Quản lý AWR settings + snapshot: `@01_setup.sql` (~2 phút)

🤔 **Dự đoán trước khi chạy:** `DBA_HIST_WR_CONTROL` trong PDB sẽ có mấy dòng? Interval của dòng PDB-local là bao nhiêu?

```sql
@01_setup.sql
```

**Đọc output theo 7 phần của script:**

| Phần | Kết quả phải thấy | Bài học |
|---|---|---|
| [2] Settings | **HAI dòng**: CDB (interval 60p) + PDB-local (interval `+40150` ngày = TẮT) | 2 stream AWR — điểm mấu chốt của cả lab |
| [3] Đổi interval → 30p | Dòng PDB-local đổi thành 30p | Việc này đồng thời **BẬT** auto-snapshot PDB-local |
| [4] Snapshot hiện có | 2 dãy snap_id ĐỘC LẬP (CDB đánh số lớn, PDB-local bắt đầu từ 1) | Chọn dbid trước khi đụng snap_id |
| [5] Snapshot thủ công level 2 | `CREATE_SNAPSHOT(flush_level=>'ALL')` → tạo rồi xóa ngay bằng `DROP_SNAPSHOT_RANGE` | Vòng đời snapshot thủ công |
| [6] SYSAUX | `SM/OPTSTAT` thường TO HƠN `SM/AWR` | Thủ phạm quen thuộc làm đầy SYSAUX là optimizer stats history, không phải AWR |
| [7] Tạo `soe.LAB_ORDERS2` | ~140-150k rows, đã gather stats bằng DBMS_STATS | Bảng thí nghiệm cho bước 2 |

### Bước 2 — Dựng lịch sử "1 SQL, 2 plan": `@02_workload.sql` (~3 phút)

🤔 **Dự đoán:** cùng 1 câu SQL chạy 30 lần trước và 30 lần sau khi tạo index — AWR SQL report sẽ hiện mấy execution plan? `buffer gets/exec` của pha index sẽ giảm khoảng bao nhiêu lần (bảng ~140k rows, lọc 10%)?

```sql
@02_workload.sql
```

**Kịch bản script tự chạy — GHI LẠI 3 SNAP_ID in ra:**

```text
tải nền 2 user × 150s (cho report có nền OLTP)
→ snap B → 30 lần query /* LAB9 */ (FULL TABLE SCAN)
→ ADD_COLORED_SQL (đánh dấu SQL để AWR LUÔN bắt — mặc định chỉ giữ top-N)
→ snap M → tạo index + gather stats → 30 lần query đó nữa (INDEX RANGE SCAN)
→ snap E
```

Để ý `SET TIMING ON`: pha 1 (FTS × 30) chậm hơn hẳn pha 2 — cảm nhận được trước khi thấy số.

### Bước 3 — Đọc lại từ AWR: `@03_diagnose.sql` (~2 phút + 10 phút đọc report)

⚠️ Chạy trong VM phải đổi thư mục spool (oracle không ghi được vào /labs — vboxsf): mở `03_diagnose.sql`, sửa `DEFINE spool_dir = .` thành `DEFINE spool_dir = /tmp`.

```sql
@03_diagnose.sql
```

**Output thật (2026-07-14) — bảng từ DBA_HIST_SQLSTAT:**

| Pha | PLAN_HASH_VALUE | Executions | Buffer gets/exec | Elapsed/exec |
|---|---|---|---|---|
| Full table scan (B→M) | 44121814 | 30 | **1,765.6** | 6.68 ms |
| Index range scan (M→E) | 321851430 | 30 | **147.0** | 1.02 ms |

**Cùng một SQL_ID** (`00wtg6c16ut2p`) — chi phí lệch **12 lần**. Mở 2 file report để thấy nguồn số liệu:

```bash
-- (shell khác, hoặc exit sqlplus tạm)
less /tmp/lab9_awr_report.txt        # tìm mục: "Top 10 Foreground Events", "SQL ordered by Gets"
less /tmp/lab9_awr_sql_report.txt    # tìm: "Plan Statistics" của TỪNG plan — 2 plan nằm cạnh nhau
```

💡 **Ý nghĩa production:** một SQL có nhiều plan chênh nhau cỡ này trong AWR SQL report = tín hiệu phải tìm root cause (stats đổi? bind peeking? index mới?).

### Bước 4 — Use case: baseline: `@04_usecase_baseline.sql` (~1 phút)

🤔 **Dự đoán:** `DBA_HIST_BASELINE` sẽ có sẵn baseline nào trước khi bạn tạo cái đầu tiên?

```sql
@04_usecase_baseline.sql
```

**Các mốc output:**

1. Baseline `LAB9_NORMAL` tạo trên cửa sổ 3 snapshot của lab (hết hạn sau 30 ngày). Chú ý script phải lọc `dbid = con_dbid` trước khi lấy MAX(snap_id) — quên là **ORA-13506** (đã dính thật khi build lab).
2. Danh sách baseline hiện `SYSTEM_MOVING_WINDOW` **2 dòng** (mỗi stream AWR một cái) — baseline động nuôi adaptive thresholds (Section 10 dùng).
3. Baseline template `LAB9_BT` (demo): kinh nghiệm tác giả course — template **không đáng tin**, baseline có khi vài ngày sau mới xuất hiện; cần tự động thì dùng Scheduler job gọi `CREATE_BASELINE`. Cũng lưu ý phải `COMMIT` sau khi tạo template.

### Bước 5 (mở rộng) — Hộp công cụ AWR use cases: `05` → `09` (~20 phút, rất đáng)

> ⚠️ Các script 05-09 **chưa kiểm chứng trên VM** (thêm 2026-07-15) — output mô tả dưới đây là kỳ vọng. Chúng chạy độc lập sau `02_workload.sql`, và dùng được trên **mọi DB có AWR** chứ không riêng lab.

Mỗi script trả lời MỘT câu hỏi production. Trước khi chạy từng cái, đọc câu hỏi và 🤔 tự nghĩ xem bạn sẽ query view nào:

1. **`@05_usecase_plan_regression.sql`** — *"Báo cáo hôm qua 2s, nay 40s — SQL nào vừa ĐỔI PLAN?"*
   Máy dò quét `DBA_HIST_SQLSTAT` tìm SQL có ≥2 plan, xếp theo độ lệch gets/exec. **Kỳ vọng:** SQL LAB9 đứng đầu, lệch ~12 lần; hồ sơ từng plan theo dòng thời gian; `DBMS_XPLAN.DISPLAY_AWR` in cả 2 plan. Cuối script có checklist điều tra 4 bước (stats? index? bind peeking? → SPM baseline).
2. **`@06_usecase_trend_dbtime.sql`** — *"Hệ thống có nặng dần không? Cao điểm giờ nào? Do CPU hay WAIT?"*
   Delta DB time/CPU/wait theo từng snapshot + **AAS** (Average Active Sessions = DB time/elapsed). Quy tắc đọc: AAS < số vCPU (2) = thoải mái, ≈ = bão hòa, >> = xếp hàng. Kèm load profile (logical reads/s, redo/s, execs/s) và wait class delta — chính là cách tìm "cửa sổ đáng mở report".
3. **`@07_usecase_diff_report.sql`** — *"Batch đêm qua 3h, đêm kia 1h — khác nhau chỗ nào?"*
   `AWR_DIFF_REPORT_TEXT` đặt 2 cửa sổ cạnh nhau → `/tmp/lab9_awr_diff.txt`. Với dữ liệu lab: cửa sổ FULL SCAN vs cửa sổ INDEX SCAN. Đọc 4 mục theo thứ tự trong PROMPT cuối script — mục 1 (Workload Comparison) quyết định các mục sau có đáng tin không (bài SQL Commonality của lab 12).
4. **`@08_usecase_top_segments_io.sql`** — *"I/O tăng vọt — bảng nào, datafile nào, đọc mất mấy ms?"*
   `DBA_HIST_SEG_STAT` (bản lịch sử của V$SEGMENT_STATISTICS lab 19) + `DBA_HIST_FILESTATXS` (avg read ms từng file — dùng lại ở Section 26). **Kỳ vọng:** LAB_ORDERS2 chiếm top logical reads.
5. **`@09_usecase_awr_hygiene.sql`** — *"AWR của DB lạ này có TIN được không?"* — checklist tiếp quản:
   nhịp chụp có đều không (phát hiện restart/lỗ hổng lịch sử), retention khai báo vs lịch sử thật, SYSAUX ai ăn, colored SQL/baseline "mồ côi" giữ snapshot sống mãi. Chạy script này ĐẦU TIÊN mỗi khi nhận một database mới.

💡 **Chuỗi truy án ghép 5 use case:** `09` (dữ liệu nền tin được?) → `06` (cửa sổ nào bất thường?) → `07` (cửa sổ đó khác bình thường chỗ nào?) → `05` (SQL nào đổi plan?) / `08` (segment/file nào gánh?).

---

## 3. Dọn dẹp (BẮT BUỘC — 1 phút)

```sql
@99_cleanup.sql
exit
```

**Kỳ vọng:** drop LAB_ORDERS2 + index, gỡ colored SQL, xóa baseline/template, trả interval về mặc định. Kết thúc buổi: `exit` × 2 rồi `vagrant halt`.

---

## 4. Debrief — tự trả lời KHÔNG nhìn tài liệu (20 phút)

1. AWR cần điều kiện gì để hoạt động? Snapshot level 1 và level 2 (`FLUSH_LEVEL=ALL`) khác gì?
2. `ADD_COLORED_SQL` giải quyết vấn đề gì? Không color thì SQL nào được AWR giữ lại?
3. Interval 30p thay vì 60p: được gì, mất gì?
4. Baseline khác snapshot thường chỗ nào? `SYSTEM_MOVING_WINDOW` dùng cho việc gì?
5. Vì sao tác giả course khuyên KHÔNG dựa vào baseline template mà dùng Scheduler job?

<details>
<summary>📖 Đáp án (bấm mở sau khi tự trả lời)</summary>

1. Ba điều kiện: `STATISTICS_LEVEL >= TYPICAL` (BASIC là tắt hẳn), tiến trình **MMON** hoạt động, **SYSAUX** còn chỗ. Level 1 (mặc định) chỉ flush top-N SQL và số liệu chuẩn; level 2 (`FLUSH_LEVEL=>'ALL'`) flush đầy đủ SQL statistics — nặng hơn, dùng khi cần chụp chi tiết quanh một thí nghiệm/sự cố (SNAP_LEVEL trong DBA_HIST_SNAPSHOT sẽ ghi 2).
2. Mặc định AWR chỉ giữ **top-N SQL** theo các tiêu chí (topnsql) — câu SQL bạn quan tâm có thể "rớt sổ" nếu không đủ nặng trong cửa sổ đó. `ADD_COLORED_SQL` đánh dấu SQL_ID để AWR **luôn** bắt nó từ snapshot sau, bất kể có lọt top hay không — công cụ chuẩn khi theo dõi một SQL nghi vấn dài hạn.
3. Được: độ phân giải chẩn đoán gấp đôi — sự cố 10 phút không bị pha loãng trong cửa sổ 60 phút; cửa sổ report càng hẹp số càng "sắc". Mất: SYSAUX tốn chỗ hơn (gấp ~2 số snapshot), overhead MMON tăng nhẹ. Riêng trong PDB, MODIFY_SNAPSHOT_SETTINGS còn BẬT luôn auto-snapshot PDB-local (muốn tắt: `interval => 0`).
4. Snapshot thường bị **purge tự động** khi quá retention; baseline là cặp snapshot được đóng băng — purge bỏ qua, tồn tại tới khi hết `expiration` hoặc bị DROP. Dùng làm mốc "trạng thái bình thường" để so khi có sự cố. `SYSTEM_MOVING_WINDOW` là baseline động trên cửa sổ trượt (mặc định 8 ngày) — nguồn dữ liệu cho **adaptive thresholds** của server alerts (Section 10).
5. Kinh nghiệm thực chiến của tác giả: baseline từ template được MMON xử lý **trễ không kiểm soát được** (có khi vài ngày sau cửa sổ mới xuất hiện), khó tin cậy cho vận hành. Scheduler job gọi thẳng `CREATE_BASELINE` sau thời điểm mong muốn thì chắc chắn, kiểm soát được lỗi, và biết ngay kết quả.

</details>

---

## 5. Sự cố thường gặp

| Triệu chứng | Nguyên nhân → Xử lý |
|---|---|
| `SP2-0310: unable to open file "../_toolkit/..."` | Không đứng ở `/labs/section_9` → `cd /labs/section_9` |
| `ORA-13506 invalid snapshot range` | Lấy snap_id không lọc dbid (trộn 2 stream) → mọi query snapshot phải có `WHERE dbid = (SELECT con_dbid FROM v$database)` |
| Spool lỗi `unable to open file` ở 03 | oracle không ghi được vào /labs (vboxsf) → sửa `DEFINE spool_dir = /tmp` |
| AWR report gần như trống | 2 snapshot quá sát nhau hoặc tải nền chưa chạy (credential hỏng sau restore → `chpasswd`, xem [labs/README.md](../readme.md)) |
| `ADD_COLORED_SQL` báo lỗi | SQL đã được color từ lần chạy trước → vô hại, script tự bắt exception |
| Số gets/exec lệch vài % so với mẫu | Bình thường. Cần ĐÚNG XU HƯỚNG: index giảm gets/exec ~10× trở lên |

---

## 6. Sau buổi học

- [ ] Báo Claude "chốt buổi" → cập nhật `progress.md` + memory
- [ ] `vagrant halt`
- [ ] Buổi kế tiếp: Section 10 — Server-generated Alerts (dùng chính SYSTEM_MOVING_WINDOW vừa thấy cho adaptive thresholds)


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/labs/section_9/HUONG_DAN_HOC_SECTION_9.md`
