---
title: 📚 Hướng dẫn học Section 2 — Kiểm chứng môi trường thực hành (thực hành trong Linux
  VM)
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/labs/section_2/HUONG_DAN_HOC_SECTION_2.md
---

# 📚 Hướng dẫn học Section 2 — Kiểm chứng môi trường thực hành (thực hành trong Linux VM)

> Số đo mẫu trong file này lấy từ lần chạy kiểm chứng trên VM **2026-07-14**.
> Thời lượng gợi ý: ~40 phút (lecture 10' + lab 20' + debrief 10').
> Nguồn: thay thế Practice 1 (Ahmed Baraka — dựng VM OL6 + 12.2 thủ công, đã EOL) bằng môi trường Vagrant có sẵn · [README lab](readme.md)

---

## 0. Kiến thức nền 5 phút (đọc trước khi gõ lệnh)

Lab này KHÔNG dạy tuning — nó trả lời 2 câu hỏi nền tảng của **mọi** lab sau:

| Câu hỏi | Vì sao quan trọng |
|---|---|
| Môi trường có đúng "hình dạng" chuẩn không? (version, tham số, SOE schema) | Mọi số đo của khóa học đều so với môi trường này. `statistics_level` sai một cái là time model + AWR chết cả khóa |
| Bộ sinh tải có chạy được không? | Từ Section 6 trở đi, lab nào cũng cần sinh tải. Chuỗi sinh tải đứt ở đâu thì mọi lab sau đứt ở đó — smoke test NGAY từ đầu |

**Chuỗi sinh tải 4 mắt xích (hiểu một lần, dùng cả khóa):**

```
credential LAB_OS_CRED (user OS oracle / oracle_4U)
  → external job LAB_SOE_DRIVER (DBMS_SCHEDULER, job_type EXECUTABLE)
    → script soe_load.sh trong VM
      → N phiên sqlplus soe/soe THẬT chạy lab_soe_load(S giây)
```

Vì sao phải đi đường vòng: job PLSQL_BLOCK thường chạy bằng slave J00x = **background process, không tính vào DB time** (đo được: job 15s → +0.01s DB time). Khóa học đo mọi thứ bằng DB time nên tải phải là session foreground thật.

---

## 1. Khởi động môi trường (5 phút)

### 1.1. Bật VM (PowerShell trên host)

```powershell
cd D:\Dba_project\vagrant-projects\OracleDatabase\19.3.0
vagrant up          # chờ ~1-2 phút, DB tự start
```

### 1.2. Chuẩn bị một lần (chỉ khi VM mới restore snapshot)

Password OS của user oracle trong VM (mắt xích đầu của chuỗi sinh tải) — mất sau mỗi `vagrant snapshot restore`:

```powershell
vagrant ssh -c "echo 'oracle:oracle_4U' | sudo chpasswd"
```

### 1.3. SSH vào VM và thành user oracle

```powershell
vagrant ssh         # → vào shell user vagrant@srv1
```

```bash
sudo -u oracle -i   # → thành user oracle (KHÔNG có password)
cd /labs/section_2  # ⚠️ BẮT BUỘC đứng ở đây: script gọi ../_toolkit/
```

> SSH cách khác + đầy đủ account/pass: [ke_hoach/05_huong_dan_ssh_vm.md](../../ke-hoach/005-huong-dan-ssh-vm.md)

---

## 2. Lab chính (user `system`, ~20 phút — KHÔNG tạo object nào)

```bash
sqlplus system/oracle_4U@//localhost:1521/ORADB
```

> Trong VM port là **1521**. (Từ host Windows mới là 15210.)

### Bước 1 — Khám sức khỏe: `@01_setup.sql` (~2 phút)

🤔 **Dự đoán trước khi chạy:** SOE schema import từ Swingbench có bao nhiêu segment? `statistics_level` phải là gì để AWR/time model hoạt động? VM 6GB RAM thì `sga_target` cỡ bao nhiêu?

```sql
@01_setup.sql
```

**Đối chiếu output với checklist (số đo 2026-07-14):**

| Mục | Kỳ vọng |
|---|---|
| Instance / version | `ORCLCDB` / 19.0 trên host `srv1` |
| PDB ORADB | `READ WRITE`, con_id 3 — **ghi lại `con_dbid` ≠ `cdb_dbid`** (Section 9 sẽ cần để lọc 2 stream AWR) |
| cpu_count / db_block_size | 2 / 8192 |
| statistics_level | `TYPICAL` (nếu BASIC → time model + AWR chết!) |
| SOETBS | ~1.2GB |
| SOE segments | **49** gốc; nhiều hơn = object lab cũ còn sót (vd `CUST` ≈121MB của section_28 → dọn bằng `labs/section_28/99_cleanup.sql`) |
| CUSTOMERS / ORDERS / ORDER_ITEMS | ~48.6k / ~1.35M / ~3.7M rows |
| Invalid SOE objects | 0 |

💡 **Điểm đáng ghi nhớ:** `cpu_count = 2` là "trần CPU" của cả khóa — từ Section 6 bạn sẽ thấy bằng số: quá 2 phiên bận CPU là bắt đầu xếp hàng.

### Bước 2 — Smoke test bộ sinh tải: `@02_workload.sql` (~1 phút)

🤔 **Dự đoán:** 2 phiên × 30 giây thì DB time sẽ tăng bao nhiêu giây? (gợi ý: DB time = tổng thời gian foreground của MỌI session cộng lại)

```sql
@02_workload.sql
```

**Output kỳ vọng — 3 mục phải đạt:**

```text
[1] 2 phiên SOE status ACTIVE (event thường thấy: log file sync)
[2] DB time tăng ≈ +60s   (2 phiên × 30s — đúng bản chất DB time là số cộng của các phiên)
[3] job LAB_SOE_DRIVER: SUCCEEDED, error# = 0
```

Nếu cả 3 đạt → hạ tầng sinh tải sẵn sàng cho toàn bộ khóa học. Nếu không → xem mục 6.

### Bước 3 — Dọn dẹp: `@99_cleanup.sql` (~30 giây)

```sql
@99_cleanup.sql
```

**Kỳ vọng:** các dòng `OK`/`SKIP`, query kiểm tra cuối chỉ còn credential `LAB_OS_CRED` (hạ tầng — giữ lại, các lab sau dùng tiếp).

---

## 3. Dọn dẹp & tắt máy (nếu kết thúc buổi)

```sql
exit
```

```bash
exit    # thoát user oracle
exit    # thoát SSH
```

```powershell
vagrant halt    # PowerShell trên host
```

---

## 4. Debrief — tự trả lời KHÔNG nhìn tài liệu (10 phút)

Trả lời xong mới cuộn xuống đáp án.

1. `statistics_level=BASIC` thì những công cụ nào của khóa này ngừng hoạt động?
2. Vì sao phải ghi nhớ `con_dbid` của ORADB khác `dbid` của CDB? (gợi ý: DBA_HIST_*)
3. Smoke test dựa vào chuỗi 4 mắt xích nào? Mắt xích nào mất sau `vagrant snapshot restore`?
4. VM 2 vCPU nghĩa là gì với các lab tải nặng?

<details>
<summary>📖 Đáp án (bấm mở sau khi tự trả lời)</summary>

1. Gần như toàn bộ: **time model** (V$SYS_TIME_MODEL), **AWR** (MMON ngừng chụp snapshot), **ASH**, **metrics** (V$SYSMETRIC → server alerts Section 10 chết theo), các advisor (ADDM, buffer cache/PGA advice). BASIC chỉ nên tồn tại trên hệ thống cực kỳ nhạy overhead — thực tế gần như không bao giờ.
2. Trong multitenant, `DBA_HIST_*` trộn **hai stream AWR độc lập** (CDB stream + PDB-local stream), phân biệt duy nhất bằng cột `DBID` với hai dãy `snap_id` riêng. Mọi thao tác AWR trong PDB phải lọc `dbid = con_dbid` trước khi lấy MAX(snap_id) — quên là dính `ORA-13506 invalid snapshot range` (Section 9 sẽ thấy tận mắt).
3. Credential `LAB_OS_CRED` → external job `LAB_SOE_DRIVER` → `soe_load.sh` → phiên sqlplus SOE thật. Mắt xích đứt sau restore: **password OS của user oracle** (đĩa VM quay về ảnh cũ, password không còn khớp credential) → sửa bằng `chpasswd` (mục 1.2). Grant `v_$session_event` cho soe cũng mất theo.
4. Trần DB CPU ≈ 2 giây CPU / 1 giây đồng hồ. Tải từ ~4 phiên bận trở lên là CPU bão hòa: phần tăng thêm dồn hết vào WAIT (CPU queue + contention) — chính là quy luật Section 6 chứng minh bằng số (DBCPU_DIFF kịch trần ~115s/60s cửa sổ đo).

</details>

---

## 5. Sự cố thường gặp

| Triệu chứng | Nguyên nhân → Xử lý |
|---|---|
| `SP2-0310: unable to open file "../_toolkit/..."` | Không đứng ở `/labs/section_2` → `cd /labs/section_2` rồi vào lại sqlplus |
| Job LAB_SOE_DRIVER `FAILED` với ORA-27496/credential | Password OS oracle chưa đặt (sau restore snapshot) → chạy lại lệnh `chpasswd` ở mục 1.2 |
| SOE segments > 49 | Object lab cũ còn sót (vd `CUST` của section_28) → chạy `99_cleanup.sql` của lab tương ứng |
| DB time tăng ít hơn ~60s nhiều | Phiên tải chưa chạy đủ (VM chậm lúc khởi động) → chạy lại `@02_workload.sql` |
| Chạy từ host PowerShell bị lỗi lạ ở `@file` | Ký tự `@` không quote bị PowerShell hiểu là splatting → luôn quote: `"@labs\section_2\01_setup.sql"` |
| sqlplus: command not found | Thiếu `-i` khi sudo → `sudo -u oracle -i` |

---

## 6. Sau buổi học

- [ ] Báo Claude "chốt buổi" → cập nhật `progress.md` + memory
- [ ] `vagrant halt`
- [ ] Buổi kế tiếp: Section 6 — Time Model Views (dùng ngay bộ sinh tải vừa smoke test)


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/labs/section_2/HUONG_DAN_HOC_SECTION_2.md`
