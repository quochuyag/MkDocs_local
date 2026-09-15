---
title: Lab Section 26 — Disk I/O Tuning
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/labs/section_26/README.md
---

# Lab Section 26 — Disk I/O Tuning

> Nguồn: Practice 28 (Ahmed Baraka) · Guide: [section_all/section_26_disk_io_guide.md](../../section-all/section-26-disk-io-guide.md) · Senior: [section_all_new/section_26_disk_io_senior_guide.md](../../section-all-new/section-26-disk-io-senior-guide.md)
> Chạy từ thư mục này (`labs/section_26/`). Quy ước chung: [labs/README.md](../readme.md)
> ⚠️ **Lab chưa kiểm chứng end-to-end trên VM** — số đo là **kỳ vọng**. Cần đúng **xu hướng**: FTS → index scan, logical/physical reads giảm mạnh.

**🎓 Học theo buổi đầy đủ (từng bước, dự đoán + đáp án):**
👉 **[HUONG_DAN_HOC_SECTION_26.md](huong-dan-hoc-section-26.md)**

## Ý tưởng lab

**90% "I/O bottleneck" trên production thực ra là logic problem** — query đọc nhiều block hơn cần. Lab tái tạo case kinh điển: một `ALTER TABLE MOVE` thầm lặng biến index thành **UNUSABLE** → optimizer bỏ index → equality lookup `WHERE order_id = :x` thành **Full Table Scan** → I/O bùng nổ. Không phải storage chậm.

## Chạy lab chính — user `soe`

⚠️ Cần grant một lần (mất sau restore snapshot) cho `before_after.sql`, bằng **SYS**:
```
GRANT SELECT ON sys.v_$session_event TO soe;
```

```powershell
sqlplus soe/soe@//localhost:15210/ORADB
```

```
@01_setup.sql       -- IO_ORDERS 1M rows + index, rồi MOVE làm index UNUSABLE (~1-2 phút)
@02_workload.sql 300 -- equality lookup nhưng bị FTS; đo baseline (ghi 3 số)
@03_diagnose.sql    -- plan là FTS dù equality; index STATUS=UNUSABLE
@04_fix.sql 300     -- REBUILD ONLINE, plan về index scan, đo lại
```

**Kỳ vọng (chưa kiểm chứng VM):**

| Chỉ số session | Trước fix (FTS) | Sau fix (index) |
|---|---|---|
| `table scan blocks gotten` | rất lớn (FTS mỗi lookup) | **~0** |
| `session logical reads` | hàng triệu | hàng nghìn |
| `physical reads` | cao | thấp |
| Top wait | `db file scattered read` / `direct path read` | gần như biến mất |
| Index status | `UNUSABLE` | `VALID` |

## Mở rộng (tùy chọn) — chạy TRONG VM, user SYS

```
@05_calibrate_io.sql   -- async I/O (V$IOSTAT_FILE) + FILESYSTEMIO_OPTIONS=SETALL + CALIBRATE_IO
```
⚠️ **CẨN THẬN:** PHẦN A read-only an toàn. PHẦN B (SETALL) cần **restart**; PHẦN C (CALIBRATE_IO) cần **QUIESCE + ~9 phút**. **Snapshot bắt buộc:** `vagrant snapshot save pre_calibrate`.

## Dọn dẹp

```
@99_cleanup.sql     -- xóa IO_ORDERS (nếu đã chạy 05 B/C: vagrant snapshot restore pre_calibrate)
```

## Câu hỏi tự kiểm tra (trả lời trước khi xem 03/04)

1. Vì sao `ALTER TABLE MOVE` làm index UNUSABLE thay vì Oracle tự cập nhật ROWID trong index?
2. Phân biệt `db file sequential read` / `db file scattered read` / `direct path read` — mỗi cái sinh ra khi nào?
3. "I/O bottleneck" — làm sao phân biệt **logic problem** (query đọc thừa) với **capacity problem** (storage thật sự không đủ)?
4. Có cách nào MOVE mà **không** làm index UNUSABLE? (2 cách trong 19c)
5. `FILESYSTEMIO_OPTIONS=SETALL` giải quyết gì? Vì sao "double caching" lãng phí?


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/labs/section_26/README.md`
