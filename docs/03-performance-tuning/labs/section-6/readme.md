---
title: Lab Section 6 — Time Model Views
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/labs/section_6/README.md
---

# Lab Section 6 — Time Model Views

> Nguồn: Practice 2 (Ahmed Baraka) · Guide: [section_all/section_6_time_model_guide.md](../../section-all/section-6-time-model-guide.md)
> Chạy từ thư mục này (`labs/section_6/`). Quy ước chung: [labs/README.md](../readme.md)

**Câu hỏi lab trả lời:** DB time là gì, vì sao phải đo bằng DELTA (không đọc số cộng dồn), và khi số user tăng thì CPU/wait tăng theo quy luật nào?

## Chạy lab — user `system`

```powershell
sqlplus system/oracle_4U@//localhost:15210/ORADB
```

```
@01_setup.sql                  -- tạo LAB_TM_HISTORY + chụp snapshot #1 (chưa có tải)
@02_workload.sql               -- ~4 phút: tải 2 → 4 → 8 user ảo, chụp snapshot giữa mỗi mức
@03_diagnose.sql               -- phân tích delta + mổ xẻ DB time theo loại thao tác + cây
@04_usecase_top_sessions.sql   -- ~1 phút: tìm session tốn DB time nhất (V$SESS_TIME_MODEL)
@99_cleanup.sql
```

Khác course: Swingbench 10/30/60 user → thay bằng 2/4/8 phiên sqlplus thật qua `_toolkit/workload_soe.sql` (VM chỉ có 2 vCPU — đủ thấy quy luật). File `tm_snap.sql` là helper chụp snapshot, gọi lại tùy ý.

## Số đo thật (VM srv1, 2026-07-14 — mỗi mức tải 60s, snapshot chụp ở giây ~50)

| Snapshot | User ảo | DBCPU_DIFF | WAIT_DIFF | WAIT_PCT trong khoảng |
|---|---|---|---|---|
| #2 | 2 | 95.9s | 3.3s | **3.3%** |
| #3 | 4 | 115.2s | 103.5s | **47.3%** |
| #4 | 8 | 114.8s | 322.1s | **73.7%** |

Quy luật phải thấy: từ 4 user trở đi **DB CPU chạm trần** (~115s ≈ 2 vCPU × khoảng đo) — thêm user không thêm được CPU, toàn bộ phần tăng đổ vào **WAIT** (CPU queue + contention). Đây chính là lý do "thêm session không làm hệ thống nhanh hơn" khi CPU đã bão hòa.

Top session (04): phiên chạy sẵn 60s có DB time 59s; các phiên vào sau wait 52% — cùng một workload, wait% mỗi session phụ thuộc mức bão hòa lúc nó chạy.

## Bẫy đã gặp khi build lab (đọc để khỏi ngã lại)

- **Job PLSQL_BLOCK của DBMS_SCHEDULER không tính vào DB time** (slave J00x là background process — đo được: job 15s chỉ +0.01s DB time). Tải phải là session thật → external job spawn sqlplus, xem `../_toolkit/workload_soe.sql`.
- `WAIT_PCT` tính trên số cộng dồn từ startup (cách course) bị quá khứ pha loãng — 03 hiển thị cả hai để so.
- Snapshot phải chụp **giữa lúc tải chạy** thì `USERS_CNT` mới đúng.

## Câu hỏi tự kiểm tra (trả lời trước khi xem 03)

1. Vì sao `sql execute elapsed time` (1,105s) gần bằng `DB time` (1,108s) nhưng cộng các stat con lại vượt 100%?
2. DB time = ? (công thức theo CPU và wait). Idle wait có nằm trong DB time không?
3. Từ 4 lên 8 user, DBCPU_DIFF gần như không đổi — kết luận gì về nút thắt?
4. `V$SESS_TIME_MODEL` mất dữ liệu khi nào? Muốn giữ lịch sử thì dùng công cụ gì (section nào)?
5. Số trong `V$SYS_TIME_MODEL` là cộng dồn từ đâu, và vì thế mọi phân tích phải làm gì trước tiên?


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/labs/section_6/README.md`
