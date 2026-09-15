---
title: 📚 Hướng dẫn học Section 19 — Enqueue Waits (thực hành trong Linux VM)
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/labs/section_19/HUONG_DAN_HOC_SECTION_19.md
---

# 📚 Hướng dẫn học Section 19 — Enqueue Waits (thực hành trong Linux VM)

> ⚠️ Lab này **chưa chạy kiểm chứng trên VM** — output dưới đây là KỲ VỌNG; buổi chạy đầu tiên điền số thật vào [README.md](readme.md).
> Thời lượng gợi ý: ~70 phút (lecture 15' + lab 35' + debrief 20').
> Nguồn: Practice 18 (Ahmed Baraka) · [README lab](readme.md)

---

## 0. Kiến thức nền 5 phút (đọc trước khi gõ lệnh)

**Enqueue** = lock CÓ HÀNG ĐỢI (xếp hàng FIFO, chờ ngoan) — đối lập với **latch/mutex** (section 20: spin-and-retry, không xếp hàng). Hai loại gặp nhiều nhất:

| | enq: TX (transaction) | enq: TM (table/DML) |
|---|---|---|
| Khi nào | Row lock, ITL đầy, trùng unique key | Khóa bảng: DDL, lock table, direct-path (APPEND — lab 14) |
| P2/P3 trỏ về | Transaction của holder (usn/slot/sequence) | P2 = object_id |
| Wait class | **Application** | Application |

**Điểm mấu chốt:** chờ `enq: TX` là **chờ TRANSACTION nhả**, không phải chờ row — holder chưa commit/rollback thì waiter còn treo, dù holder "không làm gì" hàng giờ.

**3 thì của điều tra — 3 bộ công cụ (khung của cả lab):**

```
ĐANG xảy ra → V$LOCK (ai giữ/ai chờ) + V$SESSION (event, P1-P3, ROW_WAIT_*)
VỪA xảy ra  → V$SYSTEM_EVENT (tổng) / V$SEGMENT_STATISTICS (object nào) / V$SQLSTATS (SQL nào) / ASH
ĐÃ QUA      → AWR / ASH history — hết retention là hết bằng chứng
```

---

## 1. Khởi động môi trường (5 phút)

```powershell
cd D:\Dba_project\vagrant-projects\OracleDatabase\19.3.0
vagrant up
vagrant ssh
```

```bash
sudo -u oracle -i
cd /labs/section_19   # ⚠️ BẮT BUỘC: script gọi lock_pair.sh
echo exit | sqlplus -S -L system/oracle_4U@//localhost:1521/ORADB @../_toolkit/00_env_check.sql
sqlplus system/oracle_4U@//localhost:1521/ORADB
```

---

## 2. Lab chính (user `system`, ~35 phút)

### Bước 1 — Nền tảng: `@01_setup.sql` (~30 giây)

🤔 **Dự đoán:** khi victim treo, V$LOCK của HOLDER và WAITER khác nhau ở cột nào?

```sql
@01_setup.sql
```

**Kỳ vọng:** danh sách lock type (hàng trăm loại!), mô tả TX/TM, row customers 100 tồn tại, hệ thống sạch (0 phiên chờ lock).

### Bước 2 — Thả kịch bản: `@02_workload.sql` (~15 giây)

```sql
@02_workload.sql
```

**Kỳ vọng:** thấy `LAB19_BLOCKER` (ACTIVE/INACTIVE) và `LAB19_VICTIM` với event `enq: TX - row lock contention`, seconds_in_wait tăng.

⚠️ **Đồng hồ đang chạy:** blocker giữ lock **120 giây** — chạy bước 3 NGAY. Lỡ nhịp thì chạy lại 02 (vô hại, mọi thứ rollback).

### Bước 3 — Điều tra ĐANG XẢY RA: `@03_diagnose.sql` (chạy ngay, ~2 phút)

🤔 **Dự đoán:** câu UPDATE của victim dùng bind — làm sao ra ĐÚNG row mà KHÔNG cần ASH (khác lab 13)?

```sql
@03_diagnose.sql
```

**Kỳ vọng theo 4 mốc:**

1. **[1] V$LOCK:** 2 dòng cùng `(ID1, ID2, TYPE=TX)` — Holder `LMODE=6, REQUEST=0`; Waiter `LMODE=0, REQUEST=6`. (ID1,ID2) chính là transaction của holder.
2. **[2]** chi tiết waiter: event + mô tả từ V$LOCK_TYPE + câu SQL đang kẹt + P1/P2/P3.
3. **[3]** V$SESSION có sẵn `ROW_WAIT_OBJ#/FILE#/BLOCK#/ROW#` → script tự dựng câu SELECT theo ROWID.
4. **[4]** chạy luôn → **CUSTOMER_ID = 100**. So với lab 13: lock ĐANG sống thì V$SESSION đủ, ASH chỉ cần khi hiện trường đã nguội.

### Bước 4 — VỪA XẢY RA + ĐÃ QUA: `@04_usecase_recent_past.sql` (sau khi nhả, ~2 phút)

Đợi blocker tự rollback (hết 120s — mốc [0] của script kiểm tra giúp).

🤔 **Dự đoán:** `V$SEGMENT_STATISTICS 'row lock waits'` của CUSTOMERS sẽ ghi số GÌ — thời gian hay số lần?

```sql
@04_usecase_recent_past.sql
```

**Kỳ vọng:** [1] `enq: TX - row lock contention` cộng dồn ~100+ giây, wait_class **Application**; [2] CUSTOMERS đứng đầu `row lock waits` (số LẦN, không phải thời gian); [3] câu UPDATE của victim đứng đầu `APPLICATION_WAIT_TIME` trong V$SQLSTATS; [4] chụp AWR snapshot chốt bằng chứng — mai muốn xem lại thì dùng kỹ thuật lab 9 (AWR report) / lab 13 (ASH history).

💡 **Routine chủ động của senior:** query [1]+[2] định kỳ. enq: TX xuất hiện đều đặn = ứng dụng có điểm nghẽn tranh chấp — user thường KHÔNG than phiền ("hệ thống nó thế mà") nên đừng chờ ticket.

---

## 3. Dọn dẹp (BẮT BUỘC — 30 giây)

```sql
@99_cleanup.sql
exit
```

Kết thúc buổi: `exit` × 2 rồi `vagrant halt`.

---

## 4. Debrief — tự trả lời KHÔNG nhìn tài liệu (20 phút)

1. LMODE=6 nghĩa là gì? Vì sao waiter REQUEST=6 mà không phải 3?
2. Vì sao "chờ enq: TX là chờ transaction, không phải chờ row"? Hệ quả khi holder là transaction chạy 2 tiếng?
3. enq: TX thuộc wait class nào — vì sao class đó "oan" cho database?
4. Ngoài row lock contention, kể 2 nguyên nhân khác cũng sinh enq: TX.
5. `row lock waits` trong V$SEGMENT_STATISTICS cho số lần — muốn THỜI GIAN chờ theo object thì dùng gì?

<details>
<summary>📖 Đáp án (bấm mở sau khi tự trả lời)</summary>

1. LMODE=6 = **exclusive (X)** — mode cao nhất. Waiter muốn UPDATE cùng ROW nên cũng cần TX exclusive trên transaction slot đó → REQUEST=6. (Mode 3 = row-exclusive là mode **TM trên BẢNG** khi DML thường — hai tầng lock khác nhau: TM bảo vệ bảng khỏi DDL, TX bảo vệ thay đổi của transaction.)
2. Cơ chế: row bị khóa ghi trong block (lock byte trỏ về ITL → transaction). Waiter không "canh row" mà **xếp hàng trên TX enqueue của holder** — chỉ được đánh thức khi transaction đó commit/rollback. Hệ quả: transaction dài ôm lock là mọi waiter treo theo cả 2 tiếng; giải pháp nằm ở **thiết kế ứng dụng** (commit sớm, tránh giữ lock qua user think-time), không phải ở tham số DB.
3. **Application** — tên nói thẳng: lỗi thiết kế/hành vi ỨNG DỤNG (tự chặn nhau), không phải database chậm. Khi báo cáo lên quản lý, wait class này là bằng chứng để đẩy việc sửa về phía dev thay vì "tune DB".
4. (a) **ITL shortage** — block hết chỗ trong Interested Transaction List (INITRANS thấp + nhiều transaction cùng block) → `enq: TX - allocate ITL entry`, thấy ở V$SEGMENT_STATISTICS 'ITL waits'; (b) **unique key contention** — 2 phiên INSERT cùng giá trị unique, phiên sau chờ xem phiên trước commit hay rollback (`enq: TX - row lock contention` dù chẳng UPDATE row nào); (c) bonus: chờ index block split hoàn tất.
5. **ASH**: đếm sample có `event='enq: TX...'` GROUP BY `current_obj#` — mỗi sample ≈ 1 giây chờ trên object đó (kỹ thuật lab 13 phần [4]). V$SEGMENT_STATISTICS chỉ đếm sự kiện; ASH cho chiều thời gian.

</details>

---

## 5. Sự cố thường gặp

| Triệu chứng | Nguyên nhân → Xử lý |
|---|---|
| 02 không thấy victim treo | Job chưa kịp chạy → đợi 5s query lại; job FAILED → password OS (`chpasswd`) |
| 03 chạy khi lock đã nhả ([1] ra 0 row) | Quá 120s → chạy lại `@02_workload.sql` rồi 03 ngay |
| [4] của 03 trả 0 row | ROW_WAIT_* đã bị xóa (victim vừa được nhả đúng lúc chạy) → chạy lại 02→03 |
| [2] của 04: CUSTOMERS không hiện | V$SEGMENT_STATISTICS cần vài giây cập nhật → đợi rồi query lại |
| customers 100 bị khóa bởi lab khác | workload toolkit đang chạy update ngẫu nhiên → `@../_toolkit/workload_stop.sql` trước |

---

## 6. Sau buổi học

- [ ] Điền số thật vào [README.md](readme.md) + bỏ dòng "chưa kiểm chứng"
- [ ] Báo Claude "chốt buổi" → cập nhật `progress.md` + memory
- [ ] `vagrant halt`
- [ ] Buổi kế tiếp: Section 20 — Latch & Mutex (người anh em KHÔNG xếp hàng của enqueue)


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/labs/section_19/HUONG_DAN_HOC_SECTION_19.md`
