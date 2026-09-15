---
title: Lab Section 10 — Server-generated Alerts
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/labs/section_10/README.md
---

# Lab Section 10 — Server-generated Alerts

> Nguồn: Practice 8 (Ahmed Baraka) · Guide: [section_all/section_10_server_alerts_guide.md](../../section-all/section-10-server-generated-alerts-guide.md)
> Chạy từ thư mục này (`labs/section_10/`). Quy ước chung: [labs/README.md](../readme.md)

**Câu hỏi lab trả lời:** làm sao để database TỰ báo động khi "Database Wait Time Ratio" vượt mức bình thường — và alert stateful tự sinh/tự xóa như thế nào?

## ⚠️ Toàn bộ lab chạy bằng SYS qua CDB ROOT

`DBMS_SERVER_ALERT.SET_THRESHOLD` trong PDB báo **ORA-65040** (đã test) — giống bài học `DB_32K_CACHE_SIZE` của Section 28: việc của instance thì làm ở root. Metric có 2 bản: **2107** (CDB-wide, lab dùng) và 18047 (PDB).

```powershell
sqlplus "sys/oracle_4U@//localhost:15210/ORCLCDB as sysdba"
```

```
@01_setup.sql           -- đo giá trị BÌNH THƯỜNG của metric (3 cách) — căn cứ chọn ngưỡng
@02_workload.sql        -- đặt threshold GE 60/85 + thả bão lock (blocker 300s + 3 victim enq: TX)
@03_diagnose.sql        -- CHẠY LẶP LẠI mỗi 30-60s tới khi thấy alert (thường 1-3 phút)
@04_usecase_clear.sql   -- dừng bão (cờ dừng) → xem alert TỰ chuyển sang history 'cleared'
@99_cleanup.sql         -- gỡ threshold + dọn 2 container
```

Khác course: Swingbench 40 user → bão lock (`lock_storm.sh`: wait thuần, đẩy ratio >85% chắc chắn trên VM yếu); alert xem bằng query lặp thủ công đúng tinh thần course.

## Số đo thật (VM srv1, 2026-07-14)

- Bình thường (V$SYSMETRIC_HISTORY 1h): avg 18%, max 76% (max cao do các lab tải trước đó — chính là minh họa: **chọn ngưỡng phải nhìn lịch sử, không đoán**).
- Bão lock: 3 victim `enq: TX` treo 114s → metric nhảy 0% → **99.51% → 99.96%** trong 2 điểm đo.
- Alert xuất hiện trong DBA_OUTSTANDING_ALERTS sau ~1 phút: `Metrics "Database Wait Time Ratio" is at 99.96` + suggested action "Run ADDM...".
- Dừng bão → metric về 0 → MMON tự clear sau ~2 phút: row biến khỏi OUTSTANDING, sang `DBA_ALERT_HISTORY` với `RESOLUTION: cleared`.

## Bẫy đã gặp khi build

- **ORA-65040**: SET_THRESHOLD phải ở CDB root.
- **Gỡ threshold**: `OPERATOR_DO_NOT_CHECK` bị ORA-13900 — cách đúng là truyền **NULL** cho cả operator lẫn value (xem 99).
- Threshold value là **%** (0–100), không phải ratio 0–1.
- Đổi container reset DBMS_OUTPUT → phải `SET SERVEROUTPUT ON` lại (bài cũ Section 28).

## Câu hỏi tự kiểm tra

1. Alert "stateful" khác gì cảnh báo kiểu log/email? Ai là người "xóa" alert?
2. Vì sao phải đo giá trị bình thường TRƯỚC khi đặt ngưỡng? Ngưỡng tĩnh có nhược điểm gì (gợi ý: hệ thống có chu kỳ ngày/đêm)?
3. `OBSERVATION_PERIOD` và `CONSECUTIVE_OCCURRENCES` dùng để chống cái gì?
4. Metric 2107 và 18047 khác nhau thế nào? Đặt threshold trong PDB được không?
5. Alert nằm ở view nào khi đang hiệu lực, và chuyển đi đâu sau khi hết?


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/labs/section_10/README.md`
