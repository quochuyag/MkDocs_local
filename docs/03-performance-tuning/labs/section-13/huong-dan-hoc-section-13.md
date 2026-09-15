---
title: 📚 Hướng dẫn học Section 13 — ASH & Dimension Views (thực hành trong Linux VM)
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/labs/section_13/HUONG_DAN_HOC_SECTION_13.md
---

# 📚 Hướng dẫn học Section 13 — ASH & Dimension Views (thực hành trong Linux VM)

> ⚠️ Lab này **chưa chạy kiểm chứng trên VM** — output dưới đây là KỲ VỌNG; buổi chạy đầu tiên điền số thật vào [README.md](readme.md).
> Thời lượng gợi ý: ~90 phút (lecture 20' + lab 50' + debrief 20').
> Nguồn: Practice 11 + 12 (Ahmed Baraka) · [README lab](readme.md)

---

## 0. Kiến thức nền 5 phút (đọc trước khi gõ lệnh)

**ASH = máy quay an ninh của database.** Mỗi **1 giây**, Oracle chụp ảnh mọi session đang ACTIVE (chạy CPU hoặc chờ non-idle) vào buffer trong SGA — session idle không để lại vết.

| | V$ACTIVE_SESSION_HISTORY | DBA_HIST_ACTIVE_SESS_HISTORY |
|---|---|---|
| Ở đâu | Buffer SGA (xoay vòng, ~giờ gần nhất) | AWR (đĩa, giữ theo retention) |
| Mật độ | Mỗi sample = **1 giây** | 1/10 sample được giữ = mỗi sample đại diện **10 giây** |
| Đếm thời gian | `COUNT(*)` ≈ giây | `SUM(10)` hoặc `COUNT(*)*10` |

**2 nguyên tắc vàng:**

1. **Đếm sample = ước lượng thời gian.** Victim treo 57 giây → ~57 sample `enq: TX`. Không cần cột thời gian nào khác.
2. **GROUP BY cột nào = phân rã DB time theo dimension đó.** Module, action, sql_id, event, user_id, current_obj#, p1/p2... — một mẫu query trả lời được hàng chục câu hỏi.

**Vị trí trong bộ công cụ:** section_8 dạy V$SESSION* chết theo session; section_9 dạy AWR nhưng cửa sổ 60' pha loãng sự cố ngắn. **ASH lấp đúng khoảng giữa: độ phân giải giây + sống sót sau khi session thoát.**

---

## 1. Khởi động môi trường (5 phút)

```powershell
cd D:\Dba_project\vagrant-projects\OracleDatabase\19.3.0
vagrant up
vagrant ssh
```

```bash
sudo -u oracle -i
cd /labs/section_13   # ⚠️ BẮT BUỘC: script gọi ../_toolkit/ và ash_lock_demo.sh
echo exit | sqlplus -S -L system/oracle_4U@//localhost:1521/ORADB @../_toolkit/00_env_check.sql
```

**Kỳ vọng:** 8 mục PASS.

---

## 2. Lab chính (~50 phút)

> Trong VM port là **1521**. (Từ host Windows mới là 15210.)

### Bước 1 — Tạo hiện trường: `@01_setup.sql` (user `soe`, ~30 giây)

```bash
sqlplus soe/soe@//localhost:1521/ORADB
```

🤔 **Dự đoán:** ASH sample mỗi giây — victim treo ~57 giây sẽ để lại bao nhiêu sample?

```sql
@01_setup.sql
exit
```

**Kỳ vọng:** `LAB_EMP` 200 rows, nhân vật chính `EMP_NO = 104`.

### Bước 2 — Dựng "sự cố đã qua": `@02_workload.sql` (user `system`, ~2 phút)

```bash
sqlplus system/oracle_4U@//localhost:1521/ORADB
```

🤔 **Dự đoán:** sau khi kịch bản kết thúc, `V$SESSION` còn thấy gì về 2 phiên PROCESS_CORDERS?

```sql
@02_workload.sql
```

**Kỳ vọng:** giữa chừng thấy 2 phiên `ACTION='PROCESS_CORDERS'` (victim đang `enq: TX`), cuối script **0 phiên còn lại** — hiện trường đã "nguội lạnh", đúng kịch bản "user báo lúc nãy bị treo".

### Bước 3 — Điều tra hậu kỳ: `@03_diagnose.sql` (~5 phút)

🤔 **Dự đoán:** câu UPDATE dùng bind variable — không đọc được giá trị từ SQL text. Vậy làm sao tìm ra ĐÚNG row bị tranh chấp?

```sql
@03_diagnose.sql
```

**Kỳ vọng theo 4 mốc:**

1. **[1] Dòng thời gian:** victim = chuỗi ~55-60 sample `enq: TX - row lock contention` liên tiếp, cột `BS#` = SID blocker. Số sample ≈ số giây treo — nguyên tắc vàng số 1 hiện ra bằng mắt.
2. **[2] SQL_ID** → `UPDATE lab_emp SET salary...` — biết CÂU, chưa biết ROW (bind variable).
3. **[3] Dựng ROWID:** ASH ghi `CURRENT_OBJ#/FILE#/BLOCK#/ROW#` từng sample → `DBMS_ROWID.ROWID_CREATE` ráp lại thành ROWID.
4. **[4] SELECT theo ROWID** → **EMP_NO = 104** — đúng nhân vật chính của 01_setup! Từ session ĐÃ CHẾT truy ra tận row.

### Bước 4 — ASH theo dimension: `@04_usecase_dimensions.sql` (~4 phút)

🤔 **Dự đoán:** phần [4] top object theo User I/O có thể ra 0 row — vì sao đó KHÔNG phải là lỗi?

```sql
@04_usecase_dimensions.sql
```

**Kỳ vọng:** [1] DB time theo MODULE (SQL*Plus áp đảo) — đổi điều kiện `ON CPU` là ra CPU theo module; [2] top 5 SQL của SOE; [3] SQL đệ quy có `TOP_LEVEL_SQL_ID` ≠ `SQL_ID` (tải chạy qua PL/SQL); [4]-[5] top object/block theo I/O — **có thể rỗng nếu workload toàn cache-hit**, bản thân điều đó là một chẩn đoán: "không nghẽn ở I/O".

### Bước 5 (mở rộng) — ASH report: `@05_ash_report.sql` (~1 phút)

```sql
@05_ash_report.sql
```

Đọc `/tmp/lab13_ash_report.txt` bằng `less`: tìm **"Top User Events"** (enq: TX của kịch bản có mặt?), **"Activity Over Time"** — spike nằm đúng slot thời gian kịch bản lock chạy. Câu hỏi của course: AWR comparison report có bắt được sự cố 60 giây này không? (Không — cửa sổ snapshot quá dài, spike bị pha loãng. Đó là chỗ ASH vô địch.)

---

## 3. Dọn dẹp (BẮT BUỘC — 30 giây)

```sql
@99_cleanup.sql
exit
```

Kết thúc buổi: `exit` × 2 rồi `vagrant halt`.

---

## 4. Debrief — tự trả lời KHÔNG nhìn tài liệu (20 phút)

1. V$ACTIVE_SESSION_HISTORY chứa session nào — mọi session hay chỉ session active? Idle session có để lại sample không?
2. Vì sao query trên DBA_HIST_ACTIVE_SESS_HISTORY phải SUM(10) thay vì COUNT(*)?
3. Sự cố kéo dài 90 giây: AWR report 60 phút có "thấy" không? Công cụ nào bắt được và bằng mục nào?
4. TOP_LEVEL_SQL_ID khác SQL_ID nói lên điều gì?
5. Vì sao wait `db file sequential read` có thể "lọt lưới" ASH?

<details>
<summary>📖 Đáp án (bấm mở sau khi tự trả lời)</summary>

1. Chỉ session **ACTIVE** tại khoảnh khắc sample: đang ON CPU hoặc đang trong non-idle wait. Session idle (chờ `SQL*Net message from client`) **không để lại sample** — vì thế COUNT sample ≈ DB time chứ không phải elapsed time, và ASH tự động "lọc nhiễu idle" giúp bạn.
2. AWR chỉ giữ **1/10 số sample** của ASH buffer khi flush xuống đĩa (tiết kiệm chỗ) → mỗi sample còn lại đại diện cho ~10 giây hoạt động. COUNT(*) sẽ thiếu 10 lần so với thực tế.
3. AWR report cửa sổ 60' gần như không thấy — 90 giây sự cố bị 3.510 giây bình thường pha loãng (~2.5%). **ASH report** bắt được, cụ thể mục **"Activity Over Time"** chia slot nhỏ — spike nhô hẳn lên ở slot chứa sự cố. Đây là lý do tồn tại của ASH report bên cạnh AWR report.
4. SQL đó là **recursive/child**: nó được gọi từ bên trong một khối khác (PL/SQL block, procedure). TOP_LEVEL_SQL_ID trỏ về "câu cha" mà ứng dụng thực sự gửi — khi tune phải nhìn cả cha (ngữ cảnh gọi, số lần gọi) chứ không chỉ tune câu con.
5. ASH sample mỗi **1 giây**, còn một single-block read chỉ vài ms — xác suất khoảnh khắc sample rơi đúng lúc đang wait là nhỏ. Wait ngắn xuất hiện trong ASH theo **xác suất tỷ lệ với tổng thời gian** của nó: tổng cộng đủ lớn thì vẫn hiện đủ đại diện, nhưng từng wait riêng lẻ có thể vô hình. Kết luận: ASH giỏi ước lượng "cái gì chiếm nhiều thời gian", không giỏi đếm "bao nhiêu lần wait".

</details>

---

## 5. Sự cố thường gặp

| Triệu chứng | Nguyên nhân → Xử lý |
|---|---|
| [1] của 03 ra 0 row | Kịch bản 02 chưa chạy/đã quá 15 phút → chạy lại 02 rồi 03 ngay; hoặc nới INTERVAL '15' thành '30' |
| Job LAB_ASH_LOCK FAILED | Password OS oracle mất sau restore → `chpasswd` (xem [labs/README.md](../readme.md)); LAB_EMP chưa có → chạy 01 trước |
| [4] của 04 rỗng | Workload toàn cache-hit, không I/O — không phải lỗi, đọc PROMPT trong script |
| ASH_REPORT_TEXT lỗi tham số | Thứ tự/kiểu tham số đổi theo version → chạy `DESC DBMS_WORKLOAD_REPOSITORY` xem chữ ký hàm |
| `SP2-0310 ../_toolkit/...` | Không đứng ở `/labs/section_13` → `cd /labs/section_13` |

---

## 6. Sau buổi học

- [ ] Điền số thật vào [README.md](readme.md) + bỏ dòng "chưa kiểm chứng"
- [ ] Báo Claude "chốt buổi" → cập nhật `progress.md` + memory
- [ ] `vagrant halt`
- [ ] Buổi kế tiếp: Section 14 — Service/Module/Action statistics (chính cột ACTION vừa dùng, nhưng làm hệ thống đo lường chủ động)


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/labs/section_13/HUONG_DAN_HOC_SECTION_13.md`
