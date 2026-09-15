---
title: Lab Section 14 — Service Statistics + Module/Action/Client Identifier
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/labs/section_14/README.md
---

# Lab Section 14 — Service Statistics + Module/Action/Client Identifier

> Nguồn: Practice 13 + 14 (Ahmed Baraka) gộp thành 1 lab · Guide: [section_all/](../../section_all/)
> Chạy từ thư mục này (`labs/section_14/`). Quy ước chung: [labs/README.md](../readme.md)
> ⚠️ **Chưa kiểm chứng trên VM** — buổi chạy đầu tiên điền số thật vào mục "Số đo".

**Câu hỏi lab trả lời:** database gánh nhiều ứng dụng thì đo "app nào/khối chức năng nào/luồng client nào ăn tài nguyên" thế nào — và dùng client-id aggregation phá một vụ án ETL chậm thật sự (hint APPEND sai ngữ cảnh)?

## Chạy lab

```powershell
sqlplus soe/soe@//localhost:15210/ORADB          # chỉ cho bước 01
@01_setup.sql                  -- ORDERS2 (rỗng) + LAB_ETL_SEQ

sqlplus system/oracle_4U@//localhost:15210/ORADB # các bước còn lại
@02_workload.sql               -- tải nền 4×240s + khám phá DBA_SERVICES/NAME_HASH
@03_diagnose.sql               -- V$SERVICE_STATS / V$SERVICE_EVENT / V$SERVICEMETRIC
@04_usecase_modact.sql         -- DBMS_MONITOR đo module 'Top Customers Report'
@05_usecase_clientid_etl.sql   -- ~5 phút: vụ án ETL — APPEND × 8 phiên → enq: TM → fix
@99_cleanup.sql
```

File phụ trợ: `cust_report.sql` (app gắn MODULE), `etl_load_append.sql`/`etl_load_noappend.sql` (bệnh/chữa), `etl_load.sh` (spawn N phiên).
Khác course: 2 cửa sổ admin/client → chạy trong 1 phiên + external job; 20 phiên ETL → 8 (2 vCPU); ashrpti → query ASH; KHÔNG đổi PROCESSES=500/restart (không cần với 8 phiên).

## Số đo (điền sau buổi chạy đầu tiên)

| Chỉ số | Kỳ vọng | Số thật |
|---|---|---|
| ETL bệnh: `application wait time` / `DB time` | % lớn (đa số thời gian là chờ lock) | |
| ASH event của ETL bệnh | `enq: TM - contention` áp đảo, P2 → ORDERS2 | |
| ETL chữa: `application wait time` | ≈ 0; `sql execute elapsed time` chiếm phần lớn | |
| Tổng elapsed 8 phiên: bệnh vs chữa | chữa nhanh hơn rõ rệt | |

## 3 bài học phải thuộc

1. **Tầng đo lường**: service (app nào) → module/action (chức năng nào) → client_id (luồng nào xuyên qua connection pool). ASH ước lượng được cả 3 chiều; `DBMS_MONITOR` aggregation đo THẬT nhưng phải bật trước.
2. **Đơn vị không đồng nhất**: V$SERVICE_STATS micro-giây, V$*EVENT centi-giây — đọc nhầm là sai 10.000 lần.
3. **APPEND là dao hai lưỡi**: direct-path insert giữ table lock exclusive tới commit → nhanh khi 1 phiên, serialize khi N phiên. Wait class **Application** cao = ứng dụng tự chặn nhau.

## Câu hỏi tự kiểm tra

1. Khi nào dùng service-level stats thay vì instance-level? Khi nào phải xuống module/action?
2. CLIENT_IDENTIFIER giải quyết bài toán gì mà USERNAME không giải quyết được? (gợi ý: connection pool)
3. V$SERVICE_EVENT có bản DBA_HIST không? Muốn lịch sử wait theo service thì nhìn đâu?
4. Vì sao `SET_IDENTIFIER` trong load script phải nằm ở PL/SQL block riêng?
5. Giải thích cơ chế enq: TM khi 8 phiên cùng INSERT /*+ APPEND */: lock gì, mode nào, giữ tới khi nào?


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/labs/section_14/README.md`
