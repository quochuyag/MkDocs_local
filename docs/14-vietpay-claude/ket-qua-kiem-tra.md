---
title: Kết quả kiểm tra lại (re-validation log)
course: 14-vietpay-claude
source: vietpay_cluade/KET_QUA_KIEM_TRA.md
---

# Kết quả kiểm tra lại (re-validation log)

Toàn bộ SQL của Task 1–3 được chạy thật trên **PostgreSQL 16**. Đây là bằng
chứng mọi thứ hoạt động đúng, không chỉ viết lý thuyết.

## Task 1 — Ledger & ràng buộc toàn vẹn
| Kiểm thử | Kỳ vọng | Kết quả |
|---|---|---|
| Áp dụng 6 file schema | Không lỗi | ✅ OK |
| Số dư sau ví dụ nạp $100 (phí $2) | CASH 10000 / FEE 200 / ví 9800 (cân) | ✅ Đúng |
| Bút toán lệch (chỉ 1 vế) | Bị từ chối lúc COMMIT | ✅ `journal entry does not balance in USD: diff = 500` |
| Sai loại tiền tệ so với tài khoản | Bị chặn ngay | ✅ `posting currency VND does not match account USD` |
| Request trùng idempotency key | Không post gì | ✅ `duplicate request; nothing posted` |

## Task 2 — Hiệu năng (đo trên 2.000.000 dòng, ~1.33M SETTLED)
| Chỉ số | TRƯỚC (bảng phẳng) | SAU (partition + covering index) |
|---|---|---|
| Kiểu quét | Bitmap Heap Scan | **Index Only Scan, Heap Fetches: 0** |
| Gộp (aggregate) | HashAggregate, **spill 15 MB ra đĩa tạm** | GroupAggregate, **không spill** |
| Buffers đọc | 22.294 | **3.289** (~6.8× ít hơn) |
| Số partition quét | cả bảng | **1 / N** (nhờ partition pruning) |

## Task 3 — Migration zero-downtime (chạy trên bảng 2.000.000 dòng)
| Bước | Kết quả |
|---|---|
| V1 expand (thêm cột nullable) | ✅ tức thời |
| V2 tạo procedure backfill | ✅ |
| Guard chặn promote khi chưa backfill xong | ✅ `Backfill incomplete: 2000000 NULL rows remain` |
| Backfill theo batch (idempotent) | ✅ 0 dòng NULL còn lại |
| V3 promote → NOT NULL + validate FK | ✅ cột thành `NOT NULL` |
| Rollback (undo) | ✅ đảo ngược sạch sẽ |

> Tự kiểm chứng: chạy `./run_all.sh` sau khi tạo database `fintech`.


---

!!! info "Nguồn gốc"
    `vietpay_cluade/KET_QUA_KIEM_TRA.md`
