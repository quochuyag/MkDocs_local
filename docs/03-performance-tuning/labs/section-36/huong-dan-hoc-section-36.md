---
title: 📚 Hướng dẫn học Section 36 — Database Replay (thực hành trong VM)
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/labs/section_36/HUONG_DAN_HOC_SECTION_36.md
---

# 📚 Hướng dẫn học Section 36 — Database Replay (thực hành trong VM)

> ⚠️ **Lab này CHƯA được chạy kiểm chứng end-to-end trên VM.** Output mẫu là **kỳ vọng** dựa trên Practice 38 + Oracle internals.
> ⚠️⚠️ **SNAPSHOT BẮT BUỘC** · **LICENSE** RAT · lab **single-VM** → divergence ≠ 0 (điểm học, không phải lỗi).
> Thời lượng gợi ý: ~95 phút (lecture 25' + lab 55' + debrief 15').
> Nguồn: Practice 38 (Ahmed Baraka) + [senior guide](../../section-all-new/section-36-database-replay-senior-guide.md)

---

## 0. Kiến thức nền 5 phút

Database Replay tái tạo **TOÀN BỘ workload** (mọi session, concurrency, timing) chạy lại trên test đã áp thay đổi → bắt **lock/contention/throughput** mà SPA (per-SQL) không thấy.

```
SPA (35)       → từng SQL, plan regression, tuần tự
DB Replay (36) → TOÀN workload, concurrency thật
```

**5 pha:** Capture (prod) → Preprocess (test) → [áp thay đổi] → Replay (test, qua **wrc** client) → Report.

**3 điều kiện sống còn cho replay đáng tin (senior guide Exercise 3):**
1. Test DB **restore về capture-start SCN** (data state đúng) — không thì ORA-01403/ORA-00001 + divergence rác.
2. **Đồng hồ** test = thời điểm capture (SQL phụ thuộc SYSDATE); VM phải tắt VirtualBox `GetHostTimeDisabled`.
3. **Remap** external references (db link/dir/URL) → tránh gọi nhầm hệ ngoài.

⚠️ **Lab single-VM** bỏ qua restore-to-SCN → divergence ≠ 0. Mục tiêu là **vòng đời + API**, không phải divergence đẹp.

---

## 1. Khởi động + Snapshot (5 phút)

```powershell
cd D:\Dba_project\vagrant-projects\OracleDatabase\19.3.0
vagrant up
vagrant snapshot save pre_dbreplay
vagrant ssh
```
```bash
sudo -u oracle -i
mkdir -p /home/oracle/workload && rm -f /home/oracle/workload/*   # thư mục capture phải RỖNG
cd /labs/section_36
```

---

## 2. PHA 1 — Capture (SYS, ~15 phút)

### Bước 1 — Chuẩn bị: `@01_setup.sql`

🤔 **Dự đoán:** Filter USER=SOE với `DEFAULT_ACTION=EXCLUDE` — nghĩa là bắt gì, bỏ gì?

```bash
sqlplus / as sysdba
```
```sql
@01_setup.sql
```
Ghi lại OFE gốc; bỏ comment OFE=11.2.0.2 + restart; directory + filter tạo xong.

### Bước 2 — Capture: `@02_capture.sql`

🤔 **Dự đoán:** Vì sao ghi `CURRENT_SCN` trước capture? Trong production nó dùng làm gì?

```sql
@02_capture.sql
```
**Cửa sổ shell khác — sinh tải SOE đồng thời** (trong lúc capture chạy):
```bash
sqlplus system/oracle_4U@//localhost:1521/ORADB @../_toolkit/workload_soe.sql 4 90
```
Chờ ~120s, chạy lại query BƯỚC 4 tới khi `STATUS=COMPLETED`.

**Kỳ vọng:** capture files trong `/home/oracle/workload`; `DBA_WORKLOAD_CAPTURES` COMPLETED, `CONNECTS`/`USER_CALLS` > 0.

---

## 3. PHA 2 — Preprocess + áp thay đổi (SYS, ~5 phút)

```sql
@03_preprocess_change.sql
```
🤔 **Dự đoán:** `PROCESS_CAPTURE` tạo ra gì? Vì sao phải preprocess trên đúng version đích?

Bỏ comment OFE=12.2.0.1 + restart. 💡 Trong production, **đây** là lúc restore test DB từ backup + `RECOVER UNTIL SCN` (lab bỏ qua → chấp nhận divergence).

**Xử lý đồng hồ (nếu workload phụ thuộc SYSDATE):** tắt VirtualBox GetHostTime cho srv1 (trên host, PowerShell trong thư mục cài VirtualBox):
```powershell
.\VBoxManage setextradata "<tên VM>" "VBoxInternal/Devices/VMMDev/0/Config/GetHostTimeDisabled" 1
```
rồi trong VM `sudo date +%T -s "HH:MM:SS"` về thời điểm capture. (Lab SOE ít phụ thuộc SYSDATE → có thể bỏ qua, nhưng phải biết bẫy này.)

---

## 4. PHA 3+4 — Replay + Report (SYS + shell, ~25 phút)

### `@04_replay.sql` (SYS)

🤔 **Dự đoán:** `SYNCHRONIZATION=SCN` giữ điều gì? Đánh đổi gì so với OFF?

```sql
@04_replay.sql
```
Chạy tới BƯỚC 4 (dừng lại), rồi:

**Cửa sổ shell — wrc client:**
```bash
cd /labs/section_36
./wrc_replay.sh calibrate        # gợi ý số client cần
./wrc_replay.sh start 1          # client CHỜ "Wait for the replay to start"
```
**Quay lại SQL (SYS) — BƯỚC 5:** `START_REPLAY()` (script đã có). Giám sát BƯỚC 6 tới `COMPLETED`, rồi BƯỚC 7 report.

**Kỳ vọng:**
```text
DBA_WORKLOAD_REPLAYS: STATUS COMPLETED, NUM_CLIENTS_DONE = NUM_CLIENTS
Report: so DB Time capture vs replay; DIVERGENCE + ERRORS
        (single-VM không restore-to-SCN → divergence ≠ 0 — đúng như dự kiến)
```

💡 **wrc là lệnh OS**, không phải SQL — nó đóng vai "client ứng dụng" đẩy request. Khởi động wrc **không** bắt đầu replay; `START_REPLAY()` (từ SQL) mới bắt đầu.

---

## 5. Dọn dẹp (BẮT BUỘC)

```sql
@99_cleanup.sql
```
```bash
rm -f /home/oracle/workload/*
```
```powershell
vagrant snapshot restore pre_dbreplay
vagrant halt
```

---

## 6. Debrief — tự trả lời KHÔNG nhìn tài liệu (15 phút)

1. 5 pha? Pha nào ở prod, pha nào ở test?
2. Vì sao test DB phải restore về capture-start SCN? Không làm → lỗi gì (2 ví dụ)?
3. `SYNCHRONIZATION=SCN` vs `OFF` — đánh đổi gì?
4. `wrc` là gì? Vì sao là OS command? `START_REPLAY` khác khởi động wrc thế nào?
5. Bẫy đồng hồ VirtualBox ảnh hưởng workload nào? Vì sao phải tắt GetHostTime?
6. SPA (35) vs DB Replay (36) — khi nào cái nào, khi nào cả hai?

<details>
<summary>📖 Đáp án</summary>

1. **Capture** (prod) → **Preprocess** (test) → áp thay đổi (test) → **Replay** (test) → **Report**. Capture ở production; preprocess/replay/report ở test.
2. Workload replay giả định dữ liệu như production **tại capture SCN**. Test ở data state khác → SELECT kỳ vọng row không có → **ORA-01403**; INSERT key mà test đã có → **ORA-00001**. Phải `RESTORE` từ backup prod + `RECOVER UNTIL SCN <capture_scn>` + `OPEN RESETLOGS`.
3. `SCN` giữ đúng **thứ tự commit** → concurrency/data divergence thấp nhất, nhưng có thể **serialize** (replay chậm hơn, ít song song → không phản ánh đúng throughput). `OFF` cho throughput thực hơn nhưng divergence cao hơn. Chọn theo mục tiêu (correctness → SCN; throughput → lỏng hơn).
4. `wrc` (Workload Replay Client) là **tiến trình OS** đóng vai client ứng dụng, đọc capture metadata và đẩy request vào DB — nên nó là lệnh shell, không phải SQL (SQL không thể mô phỏng nhiều client bên ngoài). Khởi động wrc chỉ làm client **chờ**; `START_REPLAY()` (từ SQL, SYS) mới ra lệnh bắt đầu đồng loạt.
5. SQL phụ thuộc `SYSDATE`/`SYSTIMESTAMP` (lọc theo ngày, insert ngày, tính hạn/tuổi) → sai nếu đồng hồ test khác thời điểm capture. VirtualBox tự đồng bộ giờ guest với host → ghi đè `date -s` → phải tắt `GetHostTimeDisabled` mới set được clock về thời điểm capture.
6. **SPA**: kiểm plan/hiệu năng **từng SQL** (rẻ, nhanh, không cần restore/clock/wrc) — bắt plan regression. **DB Replay**: kiểm **toàn workload đồng thời** (lock/contention/throughput) — nặng, thực tế. Thay đổi lớn (upgrade/migration): dùng **cả hai** — SPA trước (bắt regression sớm), DB Replay sau (validate concurrency trước go-live).

</details>

---

## 7. Sự cố thường gặp

| Triệu chứng | Xử lý |
|---|---|
| `ORA-15505: cannot start workload capture` | Directory không rỗng → `rm -f /home/oracle/workload/*` |
| Capture file không ghi được | Dùng `/home/oracle/workload` (ext4), KHÔNG `/labs` (vboxsf lỗi quyền ghi cho Oracle) |
| `wrc: ORA-15552` login fail | Mật khẩu SYSTEM sắp hết hạn → đổi/gia hạn trước khi chạy wrc |
| Replay treo ở "Wait for the replay to start" | wrc đang chờ đúng — sang SQL chạy `EXEC DBMS_WORKLOAD_REPLAY.START_REPLAY()` |
| Divergence/errors cao | Đúng kỳ vọng single-VM (không restore-to-SCN); production phải restore + set clock + remap |
| `date -s` bị reset về giờ host | Chưa tắt VirtualBox `GetHostTimeDisabled` |
| Muốn hoàn tác sạch | `vagrant snapshot restore pre_dbreplay` |

---

## 8. Sau buổi học

- [ ] Báo Claude "chốt buổi" → cập nhật `progress.md` + memory
- [ ] `vagrant snapshot restore pre_dbreplay` rồi `vagrant halt`
- [ ] **Lab chưa kiểm chứng VM** — chạy thật để ghi số đo thật
- [ ] 🎉 **Đã hết toàn khóa** — senior guide + lab đủ mọi section có Practice. Ôn tập: "chạy mù" các lab, hoặc tự tay kiểm chứng lab chưa chạy VM.


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/labs/section_36/HUONG_DAN_HOC_SECTION_36.md`
