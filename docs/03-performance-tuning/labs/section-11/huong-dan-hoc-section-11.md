---
title: 📚 Hướng dẫn học Section 11 — Statspack (thực hành trong Linux VM)
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/labs/section_11/HUONG_DAN_HOC_SECTION_11.md
---

# 📚 Hướng dẫn học Section 11 — Statspack (thực hành trong Linux VM)

> ⚠️ Lab này **chưa chạy kiểm chứng trên VM** — output ghi dưới đây là KỲ VỌNG; buổi chạy đầu tiên hãy điền số thật vào [README.md](readme.md).
> Thời lượng gợi ý: ~75 phút (lecture 15' + lab 45' + debrief 15').
> Nguồn: Practice 9 (Ahmed Baraka) · [README lab](readme.md)

---

## 0. Kiến thức nền 5 phút (đọc trước khi gõ lệnh)

**Statspack = AWR của người không có tiền license.** AWR/ASH/ADDM thuộc Diagnostics Pack (option trả tiền của EE, và **không bán cho Standard Edition**) — query DBA_HIST_* mà chưa mua là vi phạm license. Statspack miễn phí mọi edition.

| | AWR | Statspack |
|---|---|---|
| Chụp snapshot | MMON tự động (60p) | **Tay** — `STATSPACK.SNAP`, tự làm Scheduler job |
| Purge | Tự động theo retention | **Tay** — `STATSPACK.PURGE` |
| Baseline | Object riêng có tên + expiration | Chỉ là **CỜ** trên row snapshot |
| ASH / ADDM | Có | **Không** — mất khả năng truy vết session-level |
| Định danh SQL | SQL_ID | HASH_VALUE (kiểu cũ) |
| Lưu ở đâu | SYSAUX (SYS-owned) | Schema **PERFSTAT** (bảng STATS$, user thường) |

**Chuỗi tư duy của lab:** cài PERFSTAT → tự tay chụp snap 2 đầu khối tải → sinh report so sánh với AWR report đã biết (Section 9) → nghịch baseline/purge để thấy chúng "thô" cỡ nào.

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
cd /labs/section_11   # ⚠️ BẮT BUỘC: script gọi ../_toolkit/
```

### 1.3. Kiểm tra môi trường sẵn sàng

```bash
echo exit | sqlplus -S -L system/oracle_4U@//localhost:1521/ORADB @../_toolkit/00_env_check.sql
```

**Kỳ vọng:** 8 mục PASS. (Sau restore snapshot: đặt lại password OS oracle — xem [labs/README.md](../readme.md).)

---

## 2. Lab chính (~45 phút) — chú ý ĐỔI USER giữa các bước

> Trong VM port là **1521**. (Từ host Windows mới là 15210.)

### Bước 1 — Cài Statspack: `@01_setup.sql` (SYS trong **PDB**, ~3 phút)

⚠️ Phải connect vào **ORADB**, không phải CDB root — PERFSTAT sống trong PDB:

```bash
sqlplus sys/oracle_4U@//localhost:1521/ORADB as sysdba
```

🤔 **Dự đoán trước khi chạy:** bảng `STATS$STATSPACK_PARAMETER` ngay sau khi cài sẽ có mấy row?

```sql
@01_setup.sql
```

**Kỳ vọng:** `CON_NAME = ORADB` → spcreate chạy ~1-2 phút tạo user PERFSTAT + ~70 bảng STATS$ → bảng parameter **0 row** (chỉ xuất hiện sau lần set đầu) → set level 10 xong query lại thấy `SNAP_LEVEL = 10`.

💡 Level: 5 = SQL (mặc định), 6 = +plan, 7 = +segment stats, 10 = +latch con (nặng nhất — chỉ dùng khi điều tra latch; lab để 10 theo course, production thường 7).

### Bước 2 — Snapshot 2 đầu khối tải: `@02_workload.sql` (user `system`, ~4 phút)

```sql
exit
```

```bash
sqlplus system/oracle_4U@//localhost:1521/ORADB
```

🤔 **Dự đoán:** nếu quên chụp snap B trước khi tải chạy thì report còn dựng được không? (so với AWR — MMON có "chụp giùm" không?)

```sql
@02_workload.sql
```

**Kỳ vọng:** in ra `snap B = <n>` → tải 4 phiên × 150s → `snap E = <n+1>` → danh sách snapshot hiện 2 row level 10. **GHI LẠI 2 SNAP_ID.**

### Bước 3 — Sinh report: `@03_diagnose.sql` (user `perfstat`, ~3 phút + 10 phút đọc)

```sql
exit
```

```bash
sqlplus perfstat/oracle@//localhost:1521/ORADB
```

🤔 **Dự đoán:** Statspack report sẽ THIẾU những mục nào so với AWR report bạn đọc ở Section 9?

```sql
@03_diagnose.sql
```

**Kỳ vọng:** gather stats PERFSTAT → spreport batch → sprepsql cho SQL tốn CPU nhất (tự nhặt từ STATS$SQL_SUMMARY) → 2 file:

```bash
less /tmp/lab11_sp_report.lst       # tìm: "Load Profile", "Top 5 Timed Events", "SQL ordered by CPU"
less /tmp/lab11_sp_sql_report.lst
```

**Đối chiếu với AWR report:** có Load Profile/Top Events/SQL ordered by... nhưng **không có** ASH, ADDM findings, và SQL report kiểu cũ theo HASH_VALUE — đó là "giá của miễn phí".

### Bước 4 — Baseline & purge: `@04_usecase_baseline_purge.sql` (vẫn `perfstat`, ~2 phút)

🤔 **Dự đoán:** purge một range chứa cả snapshot đã baseline lẫn chưa — cái nào bị xóa?

```sql
@04_usecase_baseline_purge.sql
```

**Kỳ vọng theo 4 mốc:**

1. `MAKE_BASELINE` → cột `BASELINE = Y` trên 2 snapshot (chú ý: **không có tên** — chỉ là cờ).
2. Chụp thêm snap #3 không baseline.
3. `PURGE` cả range → **chỉ snap #3 bị xóa** — purge né snapshot có cờ.
4. `CLEAR_BASELINE` → snapshot còn nguyên nhưng cờ về NULL — giờ purge lại là mất.

---

## 3. Dọn dẹp (BẮT BUỘC — 2 phút)

Bằng SYS trong ORADB (như bước 1):

```sql
@99_cleanup.sql
```

**Kỳ vọng:** spdrop chạy → `perfstat_users = 0`. Kết thúc buổi: `exit` × 2 rồi `vagrant halt`.

---

## 4. Debrief — tự trả lời KHÔNG nhìn tài liệu (15 phút)

1. Ba việc AWR làm tự động mà Statspack bắt DBA tự làm là gì?
2. Baseline Statspack khác baseline AWR chỗ nào (bản chất lưu trữ)?
3. Snap level 5/6/7/10 khác nhau gì? Vì sao không để mặc định 10 trong production?
4. Vì sao spreport phải chạy bằng PERFSTAT?
5. Khi nào một shop trả tiền EE vẫn phải dùng Statspack?

<details>
<summary>📖 Đáp án (bấm mở sau khi tự trả lời)</summary>

1. (a) **Chụp snapshot** định kỳ — Statspack phải tự làm Scheduler job gọi `STATSPACK.SNAP`; (b) **purge** dữ liệu cũ — tự gọi `STATSPACK.PURGE` định kỳ kẻo PERFSTAT phình vô hạn; (c) **quản lý chỗ chứa** — AWR nằm SYSAUX có occupant tracking, Statspack nằm tablespace thường phải tự theo dõi.
2. Baseline AWR là **object độc lập** (có tên, expiration, view DBA_HIST_BASELINE, nuôi được adaptive thresholds). Baseline Statspack chỉ là **cờ Y/N trên row** của STATS$SNAPSHOT — tác dụng duy nhất là purge bỏ qua; không tên, không hạn, không tính năng gì thêm.
3. Level 5: SQL statistics; 6: + execution plan; 7: + segment-level statistics; 10: + latch child statistics. Level 10 tốn chỗ và thời gian chụp đáng kể mà latch con chỉ hữu ích khi đang điều tra latch contention cụ thể → production thường để 7.
4. spreport/sprepsql tham chiếu bảng `STATS$...` **không prefix schema** và spcreate **không tạo public synonym** → user khác chạy sẽ ORA-00942. (Lab cấp EXECUTE trên package cho system chỉ để chụp snap; report vẫn phải PERFSTAT.)
5. Khi hạ tầng là **Standard Edition** (Diagnostics Pack không được phép bán cho SE — không phải cứ EE là mặc định có!), hoặc EE nhưng công ty không mua Diagnostics Pack, hoặc môi trường audit license chặt muốn tắt hẳn `CONTROL_MANAGEMENT_PACK_ACCESS = NONE` — lúc đó AWR/ASH là "trái cấm" và Statspack là công cụ lịch sử hiệu năng hợp pháp duy nhất.

</details>

---

## 5. Sự cố thường gặp

| Triệu chứng | Nguyên nhân → Xử lý |
|---|---|
| spcreate báo user PERFSTAT đã tồn tại | Cài lần trước chưa gỡ → chạy `@99_cleanup.sql` (spdrop) rồi cài lại |
| `ORA-00942` khi chạy spreport | Đang không phải PERFSTAT → connect `perfstat/oracle` |
| spreport hỏi prompt begin/end snap | DEFINE chưa được set (chạy 03 lẻ tẻ từng đoạn) → chạy trọn `@03_diagnose.sql` |
| Report ghi lỗi permission | Spool vào /labs (vboxsf không cho oracle ghi) → script đã trỏ /tmp; nếu sửa thì giữ đường dẫn /tmp |
| ORA-65040 khi spcreate | Đang ở CDB root → connect vào **ORADB** |
| Tải không chạy (job FAILED) | Password OS oracle mất sau restore → `vagrant ssh -c "echo 'oracle:oracle_4U' | sudo chpasswd"` |

---

## 6. Sau buổi học

- [ ] Điền số thật vào bảng "Số đo" trong [README.md](readme.md) + bỏ dòng "chưa kiểm chứng"
- [ ] Báo Claude "chốt buổi" → cập nhật `progress.md` + memory
- [ ] `vagrant halt`
- [ ] Buổi kế tiếp: Section 12 — ADDM (thứ AWR có mà Statspack không bao giờ có)


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/labs/section_11/HUONG_DAN_HOC_SECTION_11.md`
