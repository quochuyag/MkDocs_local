---
title: 📚 Hướng dẫn học Section 20 — Latch & Mutex Contention (thực hành trong Linux VM)
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/labs/section_20/HUONG_DAN_HOC_SECTION_20.md
---

# 📚 Hướng dẫn học Section 20 — Latch & Mutex Contention (thực hành trong Linux VM)

> ⚠️ Lab này **chưa chạy kiểm chứng trên VM** — output dưới đây là KỲ VỌNG; buổi chạy đầu tiên điền số thật vào [README.md](readme.md).
> Thời lượng gợi ý: ~90 phút (lecture 20' + lab 50' + debrief 20').
> Nguồn: Practice 19 (Ahmed Baraka) · [README lab](readme.md)

---

## 0. Kiến thức nền 5 phút (đọc trước khi gõ lệnh)

| | ENQUEUE (lab 19) | LATCH / MUTEX (lab này) |
|---|---|---|
| Bảo vệ | Dữ liệu (row, table, transaction) | **Cấu trúc bộ nhớ SGA** (hash chain buffer cache, cursor, library cache) |
| Thời gian giữ | Giây → giờ (theo transaction) | **Micro-giây** |
| Cách chờ | Xếp hàng FIFO, ngủ ngoan | **SPIN** (đốt CPU thử lại liên tục) rồi mới sleep |
| Hệ quả | Wait class Application | Wait class Concurrency + **CPU cao đi kèm** |

**3 kịch bản của lab:**

1. **`library cache: mutex X`** — bão hard parse: mỗi câu SQL literal khác nhau = 1 cursor mới = 1 hard parse = giữ mutex ghi lên library cache. N phiên cùng làm → tranh nhau. **Fix: bind variable.**
2. **`latch: cache buffers chains` (CBC)** — nhiều phiên đọc CÙNG BLOCK không nghỉ; nặng thêm khi block có update chưa commit (reader phải dựng CR copy).
3. **`cursor: pin S`** — nhiều phiên cùng chạy MỘT cursor: tranh nhau "ghim" cursor. (Chính là event bạn thấy ở lab section_8!)

**Chỉ số đọc trong V$LATCH:** `GETS` (xin), `MISSES` (trượt phải spin), `SLEEPS` (spin hết lượt phải ngủ) — **SLEEPS tăng nhanh mới là báo động thật**.

---

## 1. Khởi động môi trường (5 phút)

```powershell
cd D:\Dba_project\vagrant-projects\OracleDatabase\19.3.0
vagrant up
vagrant ssh
```

```bash
sudo -u oracle -i
cd /labs/section_20   # ⚠️ BẮT BUỘC: script gọi hard_parse.sh / cbc_pin_demo.sh
echo exit | sqlplus -S -L system/oracle_4U@//localhost:1521/ORADB @../_toolkit/00_env_check.sql
sqlplus system/oracle_4U@//localhost:1521/ORADB
```

---

## 2. Lab chính (user `system`, ~50 phút) — lab dạng FIX

### Bước 1 — Toàn cảnh lúc khỏe: `@01_setup.sql` (~1 phút)

🤔 **Dự đoán:** bão hard parse bằng LITERAL sẽ làm event nào tăng vọt — và vì sao là *mutex* chứ không phải *latch*?

```sql
@01_setup.sql
```

**Kỳ vọng:** [1] bảng wait tổng thể — các dòng latch/mutex chiếm % nhỏ (khỏe); [2] top latch theo wait_time; [3] kiểm tra row 10000/10001 có cùng block không (giả định của kịch bản CBC — khác block thì kịch bản bớt "sắc" nhưng vẫn chạy).

### Bước 2 — BỆNH — bão literal: `@02_workload.sql` (~3 phút)

```sql
@02_workload.sql
```

**Kỳ vọng theo mốc:** [1] baseline mutex wait của SOE → [3] số parent cursor `SELECT COUNT(*) FROM soe.orders WHERE order_id%` **phình hàng nghìn** (chạm trần thì tụt — age-out) → [4] đo 2 lần cách 20s: **`library cache: mutex X` nhảy rõ rệt** giữa 2 lần = contention đang sống. **GHI SỐ time_csec RA GIẤY.**

### Bước 3 — Buộc tội literal: `@03_diagnose.sql` (~1 phút)

🤔 **Dự đoán:** làm sao chứng minh hàng nghìn cursor đó thực chất là MỘT câu? (gợi ý: chữ ký)

```sql
@03_diagnose.sql
```

**Kỳ vọng:** [1] `FORCE_MATCHING_SIGNATURE` — câu orders đứng đầu với MATCHES hàng nghìn (cùng chữ ký = chỉ khác literal); [2] SQLA trong shared pool phình (nạn nhân gián tiếp: cursor tốt của app khác bị đuổi); [3] hard parse rate: **hàng trăm-nghìn / 15 giây** (nền chỉ vài chục).

### Bước 4 — FIX bằng bind: `@04_fix.sql` (~2.5 phút)

🤔 **Dự đoán:** cùng workload đổi sang bind — số cursor bao nhiêu? Mutex wait ra sao?

```sql
@04_fix.sql
```

**Kỳ vọng — so với số đã ghi ở bước 2:**

| Chỉ số | Literal (bệnh) | Bind (fix) |
|---|---|---|
| Cursor cho câu orders | hàng nghìn | **1** (executions tăng vùn vụt) |
| `library cache: mutex X` giữa 2 lần đo | nhảy liên tục | **đứng yên** |
| Hard parse / 15s | hàng trăm-nghìn | vài chục (mức nền) |

💡 Fix thật nằm ở **code**: literal → bind. `CURSOR_SHARING=FORCE` chỉ là băng gạc cấp cứu khi không sửa được code (tác dụng phụ: mất histogram theo giá trị cụ thể, kế hoạch có thể xấu đi cho data lệch).

### Bước 5 (mở rộng) — CBC + cursor pin: `@05_cbc_pin.sql` (SYS, ~5 phút)

Đổi user (X$BH chỉ SYS đọc được):

```sql
exit
```

```bash
sqlplus sys/oracle_4U@//localhost:1521/ORADB as sysdba
```

```sql
@05_cbc_pin.sql
```

**Kỳ vọng:** [A2] các phiên `ACCESS BLOCK` có `latch: cache buffers chains` (P1RAW = địa chỉ latch); [A3] child latch nóng: GETS/MISSES/SLEEPS cùng tăng khi đo lại; [A4] X$BH → latch đó che block của **CUSTOMERS** (TCH cao nhất); [B2] kịch bản pin: top wait là **`cursor: pin S`** — nhiều phiên cùng 1 cursor cùng 1 block, thời gian dồn về việc ghim cursor. VM 2 vCPU có thể cho số khiêm tốn — mục tiêu là THẤY event và hiểu cơ chế.

---

## 3. Dọn dẹp (BẮT BUỘC — 1 phút)

Bằng system (hoặc SYS):

```sql
@99_cleanup.sql
exit
```

**Kỳ vọng:** jobs bị drop, `FLUSH SHARED_POOL` dọn hàng nghìn cursor rác (chú thích trong script: production bình thường KHÔNG flush!). Kết thúc buổi: `exit` × 2 rồi `vagrant halt`.

---

## 4. Debrief — tự trả lời KHÔNG nhìn tài liệu (20 phút)

1. Vì sao latch contention thường đi kèm CPU cao?
2. GETS / MISSES / SLEEPS nghĩa là gì? Cái nào là báo động thật?
3. CURSOR_SHARING=FORCE giải quyết literal storm thế nào, tác dụng phụ là gì?
4. Vì sao update CHƯA COMMIT trên row 10001 làm reader row 10000 khổ hơn?
5. `cursor: pin S` từng xuất hiện ở lab section_8 với workload toolkit — giờ giải thích được chưa?

<details>
<summary>📖 Đáp án (bấm mở sau khi tự trả lời)</summary>

1. Vì cách chờ của latch là **spin**: trượt latch thì CPU quay vòng thử lại (mặc định ~2000 lần) trước khi ngủ. N phiên cùng spin = CPU cháy mà không làm được việc gì — vì thế đồ thị latch contention luôn kèm CPU cao, và trên máy ít CPU (VM 2 vCPU) mọi thứ tệ nhanh hơn.
2. `GETS` = tổng số lần xin latch (willing-to-wait); `MISSES` = xin mà trượt phải spin; `SLEEPS` = spin hết lượt vẫn trượt, phải ngủ chờ đánh thức. MISSES/GETS vài % có thể chấp nhận; **SLEEPS tăng đều đặn** là contention thật — mỗi sleep là một lần dừng hẳn công việc.
3. FORCE: engine tự thay literal bằng bind giả trước khi tính toán cursor → mọi biến thể literal dùng chung 1 cursor, hết bão hard parse ngay mà không sửa code. Tác dụng phụ: optimizer không còn thấy giá trị cụ thể (histogram/cardinality theo literal) → có thể chọn plan tồi cho dữ liệu lệch; thêm nữa là adaptive cursor sharing phải gánh. Nguyên tắc: FORCE là cấp cứu, sửa code là chữa bệnh.
4. Update chưa commit làm block có phiên bản "bẩn" — mỗi reader cần ảnh **consistent read**: phải clone block + áp undo, thao tác này cầm latch CBC của hash chain lâu hơn và tạo thêm CR copies trên cùng chain → chain càng nóng. Không có update thì các reader chỉ share latch để đọc, nhẹ hơn nhiều.
5. Được: workload toolkit là N phiên chạy **cùng một procedure** (`lab_soe_load`) tức cùng các cursor, trên máy ít CPU — nhiều phiên đồng thời execute cùng cursor phải tranh nhau pin nó ở shared mode → `cursor: pin S` (+ `latch: cache buffers chains` vì cùng đọc các block nóng của SOE). Profile Concurrency ~52% của lab section_8 giờ có lời giải trọn vẹn.

</details>

---

## 5. Sự cố thường gặp

| Triệu chứng | Nguyên nhân → Xử lý |
|---|---|
| [4] của 02: mutex không tăng rõ | Bão chưa đủ nóng trên VM → tăng phiên 2→3 hoặc kéo dài 150→240 trong tham số job của 02 |
| Job FAILED | Password OS mất sau restore → `chpasswd`; với 05 nhớ credential là `SYS.LAB_OS_CRED` |
| X$BH báo không tồn tại | Đang chạy 05 bằng system → phải `sqlplus ... as sysdba` |
| [A2] của 05 không thấy CBC | 10000/10001 khác block ([3] của 01) hoặc VM cache lạnh → vẫn học được qua [B]; thử tăng reader 3→5 |
| Shared pool đầy, app khác chậm sau lab | Quên 99_cleanup → chạy `ALTER SYSTEM FLUSH SHARED_POOL;` |
| ORA-04031 trong lúc bão | Shared pool ngộp literal — chính là bệnh đang học! → dừng job (drop) + flush |

---

## 6. Sau buổi học

- [ ] Điền số thật vào [README.md](readme.md) + bỏ dòng "chưa kiểm chứng"
- [ ] Báo Claude "chốt buổi" → cập nhật `progress.md` + memory
- [ ] `vagrant halt`
- [ ] Buổi kế tiếp: Section 21 — Shared Pool Tuning (đi sâu vào chính vùng nhớ vừa bị bão tàn phá)


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/labs/section_20/HUONG_DAN_HOC_SECTION_20.md`
