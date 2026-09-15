---
title: Lab Section 32 — Database Connection Optimization
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/labs/section_32/README.md
---

# Lab Section 32 — Database Connection Optimization

> Nguồn: Practice 34 (Ahmed Baraka) · Guide: [section_all/section_32_database_connection_optimization_guide.md](../../section-all/section-32-database-connection-optimization-guide.md) · Senior: [section_all_new/section_32_database_connection_optimization_senior_guide.md](../../section-all-new/section-32-database-connection-optimization-senior-guide.md)
> Chạy từ thư mục này (`labs/section_32/`). Quy ước chung: [labs/README.md](../readme.md)
> ⚠️ **Lab chưa kiểm chứng end-to-end trên VM** — số đo là **kỳ vọng**.

**🎓 Học theo buổi đầy đủ:** 👉 **[HUONG_DAN_HOC_SECTION_32.md](huong-dan-hoc-section-32.md)**

## Ý tưởng lab

Query trả nhiều row: thời gian có thể bị chi phối bởi **số round-trip × latency**, không phải công việc DB. Ba đòn bẩy độc lập:

| Đòn bẩy | Sửa gì | Ở đâu |
|---|---|---|
| **ARRAYSIZE / fetch size** | giảm SỐ round-trip | app-side (ROI cao nhất, không restart) |
| **SDU** | giảm số packet/lần gửi | sqlnet.ora + tnsnames (restart listener) |
| **Socket buffer (BDP)** | giữ pipe đầy trên WAN | sqlnet.ora + tnsnames |

## Chạy lab — user `soe`

⚠️ Cần grant một lần (SYS) cho AUTOTRACE: `GRANT PLUSTRACE TO soe;` (nếu chưa có role: SYS chạy `@?/sqlplus/admin/plustrce.sql` rồi grant)

```powershell
sqlplus soe/soe@//localhost:15210/ORADB
```
```
@01_setup.sql             -- ORDERS_CONN 110k rows
@02_workload.sql          -- ARRAYSIZE 15/100/1000 → đọc 'SQL*Net roundtrips to/from client'
@03_diagnose.sql          -- SQL*Net wait events + đối chiếu công thức round-trip
@04_usecase_sdu_socket.sql -- SDU/socket config + 10046/nsconneg + BDP (tùy chọn, trong VM)
```

**Kỳ vọng (chưa kiểm chứng VM):**

| ARRAYSIZE | round-trips ≈ CEIL(110000/arraysize) | bytes sent |
|---|---|---|
| 15 (mặc định) | ~7,334 | ~không đổi |
| 100 | ~1,100 | ~không đổi |
| 1000 | ~110 | ~không đổi |

Chỉ **số round-trip** đổi (không phải lượng data) → arraysize giảm số lần đi lại.

## Dọn dẹp

```
@99_cleanup.sql           -- drop ORDERS_CONN (+ gỡ config sqlnet/tnsnames nếu đã chạy 04)
```

## Câu hỏi tự kiểm tra

1. Round-trip ≈ công thức nào theo arraysize? Vì sao `bytes sent` không đổi mà thời gian giảm?
2. `SQL*Net message from client` chiếm 88% DB time — có nghĩa "mạng chậm" không? Đây là event gì?
3. Ba đòn bẩy (arraysize / SDU / socket) — mỗi cái sửa nút thắt nào? Thứ tự ưu tiên?
4. BDP tính thế nào? Vì sao trên LAN latency thấp, chỉnh socket buffer gần như vô ích?
5. SDU đặt 512KB ở client nhưng server vẫn 8192 → SDU thực dùng là bao nhiêu?
6. Arraysize 1000 tốt hơn 100 — sao không đặt 100,000 luôn?


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/labs/section_32/README.md`
