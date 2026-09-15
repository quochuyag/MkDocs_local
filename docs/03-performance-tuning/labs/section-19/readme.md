---
title: Lab Section 19 — Handling Enqueue Waits
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/labs/section_19/README.md
---

# Lab Section 19 — Handling Enqueue Waits

> Nguồn: Practice 18 (Ahmed Baraka) · Guide: [section_all/](../../section_all/)
> Chạy từ thư mục này (`labs/section_19/`). Quy ước chung: [labs/README.md](../readme.md)
> ⚠️ **Chưa kiểm chứng trên VM** — buổi chạy đầu tiên điền số thật vào mục "Số đo".

**Câu hỏi lab trả lời:** một vụ enqueue wait được điều tra khác nhau thế nào ở 3 thì — ĐANG xảy ra (V$LOCK), VỪA xảy ra (V$SYSTEM_EVENT / V$SEGMENT_STATISTICS / V$SQLSTATS), và ĐÃ QUA (AWR/ASH history)?

## Chạy lab — user `system` (không tạo object, mọi UPDATE đều rollback)

```powershell
sqlplus system/oracle_4U@//localhost:15210/ORADB
```

```
@01_setup.sql              -- enqueue là gì, TX vs TM, hiện trường sạch
@02_workload.sql           -- thả lock_pair.sh: blocker giữ row customers 100 × 120s
@03_diagnose.sql           -- ⚠️ chạy NGAY khi lock còn sống: V$LOCK holder/waiter → đúng ROW
@04_usecase_recent_past.sql -- sau khi nhả: 3 view "vừa xảy ra" + chốt AWR snapshot
@99_cleanup.sql
```

File phụ trợ: `lock_pair.sh` (blocker 120s + victim, dùng đúng soe.customers row 100 như course).
Khác course: 3 cửa sổ thủ công → external job; ashrpti/awrrpt interactive → tham chiếu kỹ thuật lab 9/13.

## Số đo (điền sau buổi chạy đầu tiên)

| Chỉ số | Kỳ vọng | Số thật |
|---|---|---|
| V$LOCK holder | TYPE=TX, LMODE=6, REQUEST=0 | |
| V$LOCK waiter | TYPE=TX, LMODE=0, REQUEST=6, cùng ID1/ID2 với holder | |
| Row truy từ ROW_WAIT_* | customers, CUSTOMER_ID=100 | |
| V$SYSTEM_EVENT enq: TX | +~100s sau kịch bản; wait_class=Application | |
| V$SEGMENT_STATISTICS | CUSTOMERS đứng đầu 'row lock waits' | |

## 3 bài học phải thuộc

1. **Đọc V$LOCK**: holder và waiter cùng (ID1, ID2, TYPE); holder LMODE>0/REQUEST=0, waiter ngược lại. Với enq: TX, (ID1,ID2) là **transaction** của holder — bạn xếp hàng chờ transaction, không chờ row.
2. **Hai đường tới đúng ROW**: lock đang sống → `V$SESSION.ROW_WAIT_OBJ#/FILE#/BLOCK#/ROW#` + DBMS_ROWID; lock đã chết → ASH `CURRENT_*` (kỹ thuật lab 13).
3. **3 thì, 3 bộ công cụ**: đang (V$LOCK/V$SESSION) → vừa (V$SYSTEM_EVENT cộng dồn, V$SEGMENT_STATISTICS theo object — số LẦN không phải thời gian, V$SQLSTATS.APPLICATION_WAIT_TIME theo SQL) → đã qua (AWR/ASH history, hết retention là hết bằng chứng).

## Câu hỏi tự kiểm tra

1. LMODE=6 nghĩa là gì? Vì sao waiter REQUEST=6 mà không phải 3?
2. Vì sao nói "chờ enq: TX là chờ transaction, không phải chờ row"? Hệ quả khi holder là transaction chạy 2 tiếng?
3. enq: TX thuộc wait class nào — và vì sao class đó "oan" cho database?
4. Ngoài row lock contention, kể 2 nguyên nhân khác cũng sinh enq: TX (gợi ý: ITL, unique key).
5. `V$SEGMENT_STATISTICS 'row lock waits'` cho số lần — muốn thời gian chờ theo object thì dùng gì?


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/labs/section_19/README.md`
