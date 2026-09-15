---
title: Lab Section 11 — Statspack
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/labs/section_11/README.md
---

# Lab Section 11 — Statspack

> Nguồn: Practice 9 (Ahmed Baraka) · Guide: [section_all/](../../section_all/)
> Chạy từ thư mục này (`labs/section_11/`). Quy ước chung: [labs/README.md](../readme.md)
> ⚠️ **Chưa kiểm chứng trên VM** — buổi chạy đầu tiên điền số thật vào mục "Số đo".

**Câu hỏi lab trả lời:** khi KHÔNG có license Diagnostics Pack (AWR/ASH/ADDM bị cấm dùng), Statspack thay thế được đến đâu — và phải tự tay làm những gì mà AWR vẫn làm hộ?

## Chạy lab — 3 vai (SYS cài → SYSTEM sinh tải → PERFSTAT đọc report)

```powershell
sqlplus "sys/oracle_4U@//localhost:15210/ORADB as sysdba"   # ⚠️ vào PDB, không phải CDB root
@01_setup.sql                    -- cài spcreate + snap level 10 + grant cho system

sqlplus system/oracle_4U@//localhost:15210/ORADB
@02_workload.sql                 -- ~4 phút: snap B → tải 4 user × 150s → snap E

sqlplus perfstat/oracle@//localhost:15210/ORADB
@03_diagnose.sql                 -- spreport + sprepsql batch mode → /tmp/*.lst
@04_usecase_baseline_purge.sql   -- baseline (chỉ là cờ!) + purge + clear

sqlplus "sys/oracle_4U@//localhost:15210/ORADB as sysdba"
@99_cleanup.sql                  -- spdrop: xóa PERFSTAT + toàn bộ STATS$
```

Khác course: Swingbench → toolkit `workload_soe`; spreport/sprepsql interactive → batch mode (DEFINE trước); tablespace USERS → SOETBS; hash_value tìm tay trong vi → tự nhặt từ `STATS$SQL_SUMMARY`.

## Số đo (điền sau buổi chạy đầu tiên)

| Chỉ số | Kỳ vọng | Số thật |
|---|---|---|
| Thời gian cài spcreate | ~1-2 phút | |
| STATS$STATSPACK_PARAMETER trước khi set level | 0 row (bảng chỉ có row sau lần set đầu) | |
| Top 5 Timed Events trong report | CPU + log file sync (giống profile section_6/8) | |
| Purge range chứa snapshot baseline | Chỉ snapshot KHÔNG baseline bị xóa | |

## Điểm khác AWR phải thuộc

| | AWR | Statspack |
|---|---|---|
| License | Diagnostics Pack (EE option) | Miễn phí mọi edition |
| Chụp snapshot | MMON tự động | Tay / tự làm Scheduler job |
| Purge | Tự động theo retention | Tay (`STATSPACK.PURGE`) |
| Baseline | Object riêng, có tên + expiration | Chỉ là CỜ trên row snapshot |
| ASH / ADDM / SQL report theo plan | Có | Không / không / sprepsql (theo hash_value, không plan-aware bằng) |
| Định danh SQL | SQL_ID | HASH_VALUE (kiểu cũ) |

## Câu hỏi tự kiểm tra

1. Ba việc AWR làm tự động mà Statspack bắt DBA tự làm là gì?
2. Baseline Statspack khác baseline AWR chỗ nào (bản chất lưu trữ)?
3. Snap level 5/6/7/10 khác nhau gì? Vì sao không để mặc định 10 trong production?
4. Vì sao spreport phải chạy bằng PERFSTAT? (gợi ý: synonym)
5. Khi nào một shop trả tiền EE vẫn phải dùng Statspack? (gợi ý: Standard Edition thì sao?)


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/labs/section_11/README.md`
