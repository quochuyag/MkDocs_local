---
title: Lab Section 22 — Buffer Cache Tuning + KEEP Pool (+ Smart Flash Cache)
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/labs/section_22/README.md
---

# Lab Section 22 — Buffer Cache Tuning + KEEP Pool (+ Smart Flash Cache)

> Nguồn: Practice 23 + 24 (Ahmed Baraka) gộp thành 1 lab · Quy ước chung: [labs/README.md](../readme.md)
> ⚠️ **Chưa kiểm chứng trên VM** — buổi chạy đầu tiên điền số thật vào mục "Số đo".

**Câu hỏi lab trả lời:** buffer cache "thiếu chỗ" trông thế nào (bảng nóng bị đọc đi đọc lại từ disk); đọc Buffer Pool Advisory ra sao; và vì sao KEEP pool cải thiện được hiệu năng **mà không cần thêm RAM**?

## Chạy lab

```powershell
# 01 cần SYS (grant V_$MYSTAT cho soe):
sqlplus "sys/oracle_4U@//localhost:15210/ORADB as sysdba" "@01_setup.sql"
# Còn lại bằng system:
sqlplus system/oracle_4U@//localhost:15210/ORADB
```

```text
@01_setup.sql      -- (SYS) 3 bảng nóng LAB_DEPT/EMP/JOBS + bật CACHE orders/order_items
@02_workload.sql   -- ~4': lũ FTS 150s + 3 reader đo physical reads → tag BASELINE
@03_diagnose.sql   -- hit%, V$BH ai chiếm cache, Buffer Pool Advisory + 2 cảnh báo
@04_fix.sql        -- ~4': KEEP pool 64MB ĐỘNG (không restart) → chạy lại → so sánh
@05_usecase_flash_cache.sql  -- (tùy chọn, TRONG VM, cần 2 lần RESTART) Practice 24
@99_cleanup.sql
```

File phụ trợ: `bc_demo.sh` (evictor FTS + reader tự chốt sổ số đo vào `soe.lab_bc_results`).

## Khác bản gốc và vì sao

| Course (Practice 23/24) | Lab này | Vì sao |
|---|---|---|
| Thu `DB_CACHE_SIZE` về 10MB, **restart DB 4 lần**, memory management thủ công | "Lũ FTS" 2 bảng lớn gắn cờ `CACHE` đẩy bảng nóng ra khỏi cache | Cùng triệu chứng "cache không đủ chỗ", môi trường còn nguyên, không restart. Cờ CACHE chính là chiêu Practice 24 dùng cho ORDERS |
| KEEP pool đặt qua SPFILE + restart | `DB_KEEP_CACHE_SIZE=64M SCOPE=MEMORY` (động) | ASMM lấy granule từ DEFAULT cache ngay lập tức |
| EMP/DEPT/JOBS có sẵn | Tự tạo LAB_DEPT (40) / LAB_EMP (5000, row phồng 500B) / LAB_JOBS (25) | SOE của Swingbench không có 3 bảng đó |
| Reader chạy theo **thời gian** 1 phút, đọc stats bằng cách chạy `display_stats.sql` liên tục | Reader chạy **10 vòng cố định** rồi tự INSERT số đo vào bảng trước khi exit | Khối lượng cố định → physical reads so sánh được trực tiếp; V$SESSTAT biến mất khi session thoát |
| Flash cache: vdisk trong `/mnt`, cần root chown | vdisk trong `/home/oracle` (dd bằng oracle) | Không cần root |

## Số đo (điền sau buổi chạy đầu tiên)

| Chỉ số | Kỳ vọng | Số thật |
|---|---|---|
| BASELINE: avg physical_reads / reader | >> 0 (hàng nghìn–chục nghìn) | |
| BASELINE: avg elapsed | dài hơn KEEP rõ rệt | |
| KEEP: avg physical_reads / reader | ≈ 0 | |
| KEEP: avg logical_reads | ≈ bằng BASELINE (cùng khối lượng) | |
| Advisory: điểm gãy khúc ở size_factor | tùy cache hiện tại | |
| (05) V$BH status 'flashcur' của ORDERS | > 0 khi FLASH_CACHE KEEP | |

## 3 bài học phải thuộc

1. **Physical reads của bảng nóng là triệu chứng, size cache là một trong nhiều thuốc**: ADDM của course khuyên tune SQL giảm I/O TRƯỚC, rồi mới tăng cache / quy hoạch KEEP. Logical reads không đổi giữa 2 lần chạy — chỉ physical đổi theo tình trạng cache: muốn giảm logical phải sửa SQL, muốn giảm physical mới là chuyện của cache.
2. **Buffer Pool Advisory chỉ nhìn xa tối đa 200% size hiện tại** — cache đang quá nhỏ thì advisory không thấy hết lợi ích, phải tăng dần nhiều lần và đọc lại sau mỗi lần (course tăng 10MB → 280MB → 460MB). Và như mọi advisory: chỉ tin khi đo lúc workload bình thường.
3. **KEEP pool = LRU riêng, không phải RAM thêm**: hiệu quả cho bảng *nhỏ + nóng + bị chèn ép*; block chỉ vào KEEP ở lần đọc tiếp theo (phải "mồi"); nhét bảng lớn vào KEEP là chiếm chỗ vô ích.

## Câu hỏi tự kiểm tra

1. Vì sao lab dùng số vòng cố định thay vì thời gian cố định cho reader? Nếu dùng thời gian thì so sánh bằng chỉ số gì mới đúng?
2. Cờ `CACHE` trên bảng lớn thay đổi hành vi FTS như thế nào (2 điểm) và vì sao thiếu nó thì "lũ" không hoạt động?
3. Hit% đọc từ `V$BUFFER_POOL_STATISTICS` khác gì hit% trong AWR report? Khi nào con số tích lũy đánh lừa?
4. KEEP pool 64MB lấy RAM từ đâu khi set động? Điều gì xảy ra nếu tổng object gắn KEEP lớn hơn 64MB?
5. Block của ORDERS ở status `flashcur` nghĩa là gì? Đường đi của 1 block từ RAM xuống flash rồi quay lại RAM diễn ra khi nào?


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/labs/section_22/README.md`
