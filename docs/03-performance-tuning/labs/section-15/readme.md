---
title: Lab Section 15 — Tracing SQL bằng DBMS_MONITOR (+ trcsess, tkprof)
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/labs/section_15/README.md
---

# Lab Section 15 — Tracing SQL bằng DBMS_MONITOR (+ trcsess, tkprof)

> Nguồn: Practice 15 (Ahmed Baraka) · Guide: [section_all/](../../section_all/)
> Chạy từ thư mục này (`labs/section_15/`). Quy ước chung: [labs/README.md](../readme.md)
> ⚠️ **Chưa kiểm chứng trên VM** — buổi chạy đầu tiên điền số thật vào mục "Số đo".
> ⚠️ **Lab này BẮT BUỘC chạy TRONG VM** (`vagrant ssh` → `sudo -u oracle -i`) — các bước dùng `HOST grep/trcsess/tkprof` là lệnh OS trên máy chứa trace file.

**Câu hỏi lab trả lời:** khi cần độ chi tiết TUYỆT ĐỐI (từng parse/execute/fetch, từng wait, từng bind) mà sampling (ASH) không đủ — bật trace đúng phạm vi thế nào, và dịch trace ra kết luận bằng bộ trcsess + tkprof ra sao?

## Chạy lab — user `system`, TRONG VM

```bash
cd /labs/section_15
sqlplus system/oracle_4U@//localhost:1521/ORADB
```

```
@01_setup.sql          -- thư mục trace (V$DIAG_INFO) + kiểm tra file cũ
@02_workload.sql       -- ~1.5 phút: trace MỘT phiên (SESSION_TRACE_ENABLE theo SID/SERIAL#)
@03_diagnose.sql       -- ~2 phút: trace theo MODULE (3 phiên tự spawn) → 3 trace file
@04_usecase_tkprof.sql -- trcsess gộp 3 file → tkprof dịch → /tmp/lab15_PROCESS_ORDERS.txt
@99_cleanup.sql        -- tắt trace + xóa file lab
```

File phụ trợ: `trace_client.sh` (1 phiên sống 90s cho phần trace đơn), `traced_workload.sh` (3 phiên nối tiếp cùng module).
Khác course: 2 cửa sổ Putty → external job; EMP không có trong SOE Swingbench → query thuần orders/customers; report ra /tmp.

## Số đo (điền sau buổi chạy đầu tiên)

| Chỉ số | Kỳ vọng | Số thật |
|---|---|---|
| grep LAB15_SINGLE trong trace đơn | > 0 (query sau khi enable bị bắt) | |
| Số trace file *PORDERS*.trc | 3 (mỗi phiên một file) | |
| Câu đứng đầu tkprof (sort exeela) | query tổng hợp nặng của phiên 1 | |
| `/* my query */` trong tkprof | count=4 trong 1 mục (aggregate=yes) | |

## 3 bài học phải thuộc

1. **Chọn đúng phạm vi trace**: 1 phiên đã biết SID → `SESSION_TRACE_ENABLE`; workload production (không biết SID, connection pool, phiên tương lai) → `SERV_MOD_ACT_TRACE_ENABLE` theo service/module/action (tận dụng nhãn của lab 14). **Tắt trace là bắt buộc** — quên là trace chạy vô hạn, đầy đĩa.
2. **Bộ ba lệnh OS**: `TRACEFILE_IDENTIFIER` đánh dấu file → `trcsess` lọc & gộp nhiều file theo module/service/client_id → `tkprof SYS=no waits=yes aggregate=yes sort=(exeela,prsela,fchela)`.
3. **Đọc tkprof**: bảng count/cpu/elapsed/disk/query/current/rows × 3 pha Parse/Execute/Fetch; elapsed >> cpu → phần chênh nằm ở wait (mục "Elapsed times include waiting on..." ngay dưới).

## Câu hỏi tự kiểm tra

1. Trace phiên đang chạy giữa chừng — trace file có chứa các lệnh đã chạy TRƯỚC đó không?
2. Khi nào phải dùng trcsess? Khi nào bỏ qua được?
3. `SYS=no` trong tkprof loại bỏ gì? Vì sao thường muốn loại?
4. Ba cột `query`, `current`, `disk` trong tkprof nghĩa là gì (đơn vị nào)?
5. Trace vs ASH: mỗi cái thắng ở tình huống nào? Chi phí của trace là gì?


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/labs/section_15/README.md`
