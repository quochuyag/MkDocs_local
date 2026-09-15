---
title: Lab Section 20 — Latch & Mutex Contention
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/labs/section_20/README.md
---

# Lab Section 20 — Latch & Mutex Contention

> Nguồn: Practice 19 (Ahmed Baraka) · Guide: [section_all/](../../section_all/)
> Chạy từ thư mục này (`labs/section_20/`). Quy ước chung: [labs/README.md](../readme.md)
> ⚠️ **Chưa kiểm chứng trên VM** — buổi chạy đầu tiên điền số thật vào mục "Số đo".

**Câu hỏi lab trả lời:** bão hard parse do LITERAL gây `library cache: mutex X` thế nào, fix bằng bind variable chứng minh bằng số ra sao — và CBC latch / cursor pin S khác nhau chỗ nào?

## Chạy lab — lab dạng FIX (01→04 bằng system; 05 mở rộng bằng SYS)

```powershell
sqlplus system/oracle_4U@//localhost:15210/ORADB
```

```
@01_setup.sql     -- toàn cảnh latch/mutex lúc khỏe + check 10000/10001 cùng block
@02_workload.sql  -- BỆNH: bão literal 2 phiên × 150s → mutex X tăng vọt (đo 2 lần)
@03_diagnose.sql  -- FORCE_MATCHING_SIGNATURE buộc tội literal + hard parse rate
@04_fix.sql       -- FIX: cùng workload bằng BIND → 1 cursor, mutex đứng yên, đo lại
@05_cbc_pin.sql   -- (mở rộng, SYS trong PDB) CBC latch + cursor: pin S
@99_cleanup.sql   -- drop jobs + FLUSH SHARED_POOL (dọn rác literal)
```

File phụ trợ: `hard_parse.sh` (bão literal/bind), `cbc_pin_demo.sh` (2 kịch bản cbc/pin).
Khác course: vòng lặp vô hạn + Ctrl+C → giới hạn thời gian; ROWID gõ tay → phiên tự lấy; 10 phiên pin → 6 (2 vCPU); X$BH giữ nguyên (nên 05 chạy SYS).

## Số đo (điền sau buổi chạy đầu tiên)

| Chỉ số | Kỳ vọng | Số thật |
|---|---|---|
| Cursor literal sau ~1 phút bão | hàng nghìn (rồi tụt do age-out) | |
| `library cache: mutex X` giữa 2 lần đo (bão) | tăng rõ | |
| Hard parse / 15s: bão vs bind | hàng trăm-nghìn vs vài chục | |
| Cursor phiên bản bind | 1 cursor, executions rất lớn | |
| Top event kịch bản pin | `cursor: pin S` (+ mutex X) | |

## 3 bài học phải thuộc

1. **Latch/mutex vs enqueue**: micro-lock bảo vệ cấu trúc SGA, spin-and-sleep (đốt CPU) — không xếp hàng như enqueue. Triệu chứng đặc trưng: GETS/MISSES/**SLEEPS** cùng tăng (V$LATCH/V$LATCH_CHILDREN).
2. **Literal storm**: mỗi literal = 1 parent cursor mới = 1 hard parse = giữ mutex library cache → `library cache: mutex X`. Máy dò: `FORCE_MATCHING_SIGNATURE` có MATCHES lớn. Fix thật: **bind variable trong code**; băng gạc: CURSOR_SHARING=FORCE.
3. **CBC latch vs cursor pin**: CBC = tranh hash chain của BLOCK nóng (đọc cùng block, nặng thêm khi có CR block do update chưa commit); `cursor: pin S` = tranh pin cùng CURSOR. Cùng "Concurrency" nhưng đối tượng tranh chấp khác nhau → cách chữa khác nhau.

## Câu hỏi tự kiểm tra

1. Vì sao latch contention thường đi kèm CPU cao? (gợi ý: spin)
2. GETS / MISSES / SLEEPS trong V$LATCH nghĩa là gì? Cái nào là báo động thật?
3. CURSOR_SHARING=FORCE giải quyết literal storm thế nào, và tác dụng phụ là gì?
4. Vì sao update CHƯA COMMIT trên row 10001 làm reader row 10000 khổ hơn? (cùng block, CR)
5. `cursor: pin S` xuất hiện ở lab section_8 với workload toolkit — giờ giải thích được vì sao chưa?


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/labs/section_20/README.md`
