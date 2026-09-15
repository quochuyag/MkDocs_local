---
title: 📚 Hướng dẫn học Section 16 — Real-time SQL Monitoring (thực hành trong Linux VM)
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/labs/section_16/HUONG_DAN_HOC_SECTION_16.md
---

# 📚 Hướng dẫn học Section 16 — Real-time SQL Monitoring (thực hành trong Linux VM)

> ⚠️ Lab này **chưa chạy kiểm chứng trên VM** — output dưới đây là KỲ VỌNG; buổi chạy đầu tiên điền số thật vào [README.md](readme.md).
> Thời lượng gợi ý: ~70 phút (lecture 15' + lab 40' + debrief 15').
> Nguồn: Practice 16 (Ahmed Baraka) · [README lab](readme.md)

---

## 0. Kiến thức nền 5 phút (đọc trước khi gõ lệnh)

Bài toán: "câu SQL đang chạy 10 phút rồi — nó **tới đâu rồi**, còn bao lâu?" — trace (lab 15) không trả lời được câu đang chạy dở; ASH cho biết đang chờ gì nhưng không cho biết **tiến độ theo plan**.

**Real-time SQL Monitoring**: Oracle TỰ ĐỘNG theo dõi mọi câu chạy **song song** hoặc tiêu **>5 giây CPU/IO** — không cần bật gì:

| View | Cho biết |
|---|---|
| `V$SQL_MONITOR` | Mỗi lần chạy của câu được monitor: status (EXECUTING/DONE), CPU, IO... — cả khi ĐANG chạy |
| `V$SQL_PLAN_MONITOR` | **Plan sống**: từng step với OUTPUT_ROWS nhảy theo thời gian thực → thấy kẹt ở step nào |
| `DBMS_SQL_MONITOR.REPORT_SQL_MONITOR` | Báo cáo tổng hợp (text/html) — thứ EM Express hiển thị |

**Composite operation**: gom NHIỀU câu của một session thành một "nghiệp vụ" có tên — `BEGIN_OPERATION(dbop_name, sid, serial#, forced_tracking=>'Y')` ... `END_OPERATION`. Row có `DBOP_NAME` = operation; row có `IN_DBOP_NAME` = câu thuộc nó.

**License:** thuộc **Tuning Pack** (`CONTROL_MANAGEMENT_PACK_ACCESS = DIAGNOSTIC+TUNING`) — cao hơn cả Diagnostics Pack của AWR/ASH.

---

## 1. Khởi động môi trường (5 phút)

```powershell
cd D:\Dba_project\vagrant-projects\OracleDatabase\19.3.0
vagrant up
vagrant ssh
```

```bash
sudo -u oracle -i
cd /labs/section_16   # ⚠️ BẮT BUỘC: script gọi monitor_client.sh
echo exit | sqlplus -S -L system/oracle_4U@//localhost:1521/ORADB @../_toolkit/00_env_check.sql
sqlplus system/oracle_4U@//localhost:1521/ORADB
```

---

## 2. Lab chính (user `system`, ~40 phút)

### Bước 1 — Điều kiện + hàm đốt CPU: `@01_setup.sql` (~30 giây)

🤔 **Dự đoán:** query `SELECT lab_consume_cpu(60)` có bị V$SQL_MONITOR bắt không? Bạn có phải enable gì không?

```sql
@01_setup.sql
```

**Kỳ vọng:** `control_management_pack_access = DIAGNOSTIC+TUNING` + function tạo xong.

### Bước 2 — Query đơn được "tự ghi danh": `@02_workload.sql` (~1.5 phút)

```sql
@02_workload.sql
```

**Kỳ vọng theo mốc:** [2] sau ~15s query xuất hiện trong V$SQL_MONITOR, `STATUS=EXECUTING` → [3] đo lại sau 20s: **CPU_TIME tăng, DISK_READS đứng im ở 0** (đúng bản chất: đốt CPU không đụng đĩa) → [4] query xong: `STATUS=DONE`, row **vẫn còn** xem lại được.

💡 Trả lời dự đoán: KHÔNG cần enable — vượt ngưỡng 5 giây là tự được monitor. So với trace: không overhead cấu hình, nhưng câu <5s vô hình (tác giả course coi đây là nhược điểm lớn nhất).

### Bước 3 — Composite operation: `@03_diagnose.sql` (~4.5 phút, timeline tự động)

🤔 **Dự đoán:** operation có `FORCED_TRACKING='Y'` — vậy câu `SELECT SYSDATE` (nhanh) có hiện thành task không?

```sql
@03_diagnose.sql
```

**Kỳ vọng theo 4 mốc:**

1. **[2]** tìm SID/SERIAL# của phiên client (nhãn `LAB16_DBOP`) → `BEGIN_OPERATION` in ra OP_ID.
2. **[3]** danh sách task: row `DBOP_NAME` (operation) + row `IN_DBOP_NAME` chỉ có **query NẶNG** — `SELECT SYSDATE` và PL/SQL loop ngắn KHÔNG hiện (forced_tracking ép track *operation*, từng *câu* vẫn theo ngưỡng 5s).
3. **[4]** plan real-time đo 2 lần cách 25s: **OUTPUT_ROWS tăng** giữa 2 lần — bạn đang nhìn NESTED LOOPS "chạy" bằng mắt.
4. **[5]** `END_OPERATION` → status **vẫn EXECUTING** → sau khi client làm roundtrip kế tiếp (~40s) → **DONE**. Status là thông tin do session "gửi kèm" call — không có call thì không cập nhật.

### Bước 4 — Báo cáo: `@04_usecase_report.sql` (~1 phút + 10 phút đọc)

```sql
@04_usecase_report.sql
```

Đọc `/tmp/lab16_sqlmon_report.txt` (`less` trong shell VM) theo 3 khối: **Global Information** (status, duration) → **Global Stats** (elapsed phân rã CPU/wait — nghẽn ở đâu) → **SQL Plan Monitoring Details** (từng step: Execs, Rows, **Activity %** — step nào ăn thời gian lộ ra ngay). Đây là công cụ trả lời "SQL chạy tới đâu" nhanh nhất của senior.

---

## 3. Dọn dẹp (BẮT BUỘC — 30 giây)

```sql
@99_cleanup.sql
exit
```

Kết thúc buổi: `exit` × 2 rồi `vagrant halt`.

---

## 4. Debrief — tự trả lời KHÔNG nhìn tài liệu (15 phút)

1. Điều kiện license nào để dùng SQL Monitoring? Khác gì điều kiện của AWR/ASH?
2. Vì sao SELECT SYSDATE không xuất hiện thành task dù operation có FORCED_TRACKING='Y'?
3. Sau END_OPERATION status vẫn EXECUTING — vì sao, và khi nào nó đổi?
4. Khi nào dùng SQL Monitor thay vì trace (lab 15)? Khi nào ngược lại?
5. Muốn xem report SQL Monitor của một câu chạy HÔM QUA thì lấy ở đâu (19c)?

<details>
<summary>📖 Đáp án (bấm mở sau khi tự trả lời)</summary>

1. **Tuning Pack** (`CONTROL_MANAGEMENT_PACK_ACCESS = DIAGNOSTIC+TUNING`). AWR/ASH chỉ cần Diagnostics Pack — tức có shop được dùng AWR nhưng KHÔNG được dùng SQL Monitoring (chỉ mua Diagnostics). Standard Edition: không cái nào.
2. `FORCED_TRACKING` ép track **operation như một khối** (kể cả khi tổng < 5s). Nhưng việc từng CÂU có được ghi thành row task riêng hay không vẫn theo ngưỡng tự nhiên (>5s CPU/IO hoặc parallel). SELECT SYSDATE vài micro-giây → không thành task, nhưng thời gian của nó vẫn TÍNH VÀO tổng của operation.
3. STATUS của operation do **session client báo về kèm theo call**. END_OPERATION chỉ đánh dấu phía server; session chưa thực hiện call nào tiếp theo thì chưa "nhận ra" — roundtrip kế tiếp (bất kỳ query nào) mới cập nhật thành DONE. Bài học: đọc số real-time phải hiểu cơ chế cập nhật của nó.
4. **SQL Monitor thắng**: câu ĐANG chạy (cần tiến độ theo plan step), zero cấu hình, nhìn được cả lịch sử gần. **Trace thắng**: cần từng call/bind/wait chính xác 100%, câu ngắn <5s chạy hàng nghìn lần (SQL Monitor mù hoàn toàn với loại này — phải tkprof aggregate), hoặc không có Tuning Pack.
5. `DBA_HIST_REPORTS` (+ `DBA_HIST_REPORTS_DETAILS`) — từ 12c AWR tự lưu các report SQL Monitor đáng chú ý; 19c dùng tốt. Lấy report_id rồi `DBMS_AUTO_REPORT.REPORT_REPOSITORY_DETAIL`. Không có thì đành AWR SQL report (mất chi tiết theo step-time).

</details>

---

## 5. Sự cố thường gặp

| Triệu chứng | Nguyên nhân → Xử lý |
|---|---|
| [2] của 02 không có row | Query chưa vượt 5s hoặc client chưa chạy → đợi 10s query lại tay; job FAILED → `chpasswd` |
| Không tìm thấy phiên LAB16_DBOP ở [2] của 03 | Job spawn chậm → đợi 5s, query lại; hoặc chạy lại 03 |
| [4] hai lần đo OUTPUT_ROWS giống nhau | Query nặng đã xong trước khi đo (VM nhanh hơn dự kiến) → tăng 8000 thành 12000 trong monitor_client.sh; hoặc query đã bị flush → chạy lại 03 |
| STATUS mãi EXECUTING ở [5] | Client chưa tới roundtrip → đợi thêm 30s query lại tay; phiên client chết sớm → xem [3] status |
| REPORT_SQL_MONITOR trả NULL | sql_id không còn trong V$SQL_MONITOR (bị đẩy khỏi vùng nhớ) → chạy lại 03 rồi 04 ngay |

---

## 6. Sau buổi học

- [ ] Điền số thật vào [README.md](readme.md) + bỏ dòng "chưa kiểm chứng"
- [ ] Báo Claude "chốt buổi" → cập nhật `progress.md` + memory
- [ ] `vagrant halt`
- [ ] Buổi kế tiếp: Section 17 — Automated Maintenance Tasks (những job nền Oracle tự chạy — và cách kiểm soát chúng)


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/labs/section_16/HUONG_DAN_HOC_SECTION_16.md`
