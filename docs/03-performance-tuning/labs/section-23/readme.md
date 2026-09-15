---
title: Lab Section 23 — PGA Tuning
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/labs/section_23/README.md
---

# Lab Section 23 — PGA Tuning

> Nguồn: Practice 25 (Ahmed Baraka) · Quy ước chung: [labs/README.md](../readme.md)
> ⚠️ **Chưa kiểm chứng trên VM** — buổi chạy đầu tiên điền số thật vào mục "Số đo".

**Câu hỏi lab trả lời:** PGA khỏe/ốm nhìn bằng 3 luật nào; sort "tràn xuống temp" trông ra sao khi tự tay ép nó xảy ra; và đọc `V$PGA_TARGET_ADVICE` theo thứ tự nào để chọn `PGA_AGGREGATE_TARGET`?

## Chạy lab

```powershell
sqlplus system/oracle_4U@//localhost:15210/ORADB
```

```text
@01_setup.sql               -- 3 luật khám PGA + baseline (wa_exec, pgastat, histogram)
@02_workload.sql            -- ~3': 3 phiên sort/hash lớn; soi V$SQL_WORKAREA_ACTIVE sống
@03_diagnose.sql            -- thí nghiệm SQLID 1/2/3: bóp sort area 160KB → tràn temp
@04_usecase_pga_advice.sql  -- ~3': target 50MB → over-allocation → đọc advisory → trả gốc
@99_cleanup.sql
```

File phụ trợ: `pga_sort.sh` (N phiên lặp window-sort toàn bộ ORDERS + hash join FULL orders×order_items).

## Khác bản gốc và vì sao

| Course (Practice 25) | Lab này | Vì sao |
|---|---|---|
| Swingbench warehouse.xml làm nền | `pga_sort.sh`: window sort + hash join hint | Không có Swingbench; window sort không bị optimizer loại, hash hint ép work area HASH-JOIN |
| Fetch 39.000 row ra Putty rồi xem V$ | `SET AUTOTRACE TRACEONLY STATISTICS` | Vẫn thực thi + fetch, không in row, in luôn `sorts (memory)/(disk)` từng câu |
| `ORDER_ID BETWEEN 10000 AND 400000` | Khoảng động `MIN → MIN+50000` | Dữ liệu SOE bản import của ta khác course |
| 7 file display_*.sql riêng | Gộp vào các script theo bước | Ít file mồ côi; query giữ nguyên |

## Số đo (điền sau buổi chạy đầu tiên)

| Chỉ số | Kỳ vọng | Số thật |
|---|---|---|
| Baseline: workarea multipass | 0 | |
| Baseline: cache hit percentage | ~100 | |
| 02: PASS của work area đang sống | 0 (optimal) | |
| 03 SQLID 2 (auto): sorts (disk) | 0 | |
| 03 SQLID 3 (manual 160KB): sorts (disk) | 1, có physical writes direct temp | |
| 03: EST_OPTIMAL vs LAST_MEM của SQLID 3 | est lớn >> mem thực (bị bóp) | |
| 04: total PGA allocated khi target 50MB | vượt xa 50MB | |
| 04: target nhỏ nhất có ESTD_OVERALLOC=0 | ghi lại từ advisory | |

## 3 bài học phải thuộc

1. **3 luật khám PGA** (course): `workarea executions — multipass` = 0 ở mọi môi trường; `sorts (disk)` thấp trong OLTP; `cache hit percentage` ~100. Nhìn thêm histogram: one-pass dồn vào giỏ size *nhỏ* mới đáng sợ (câu bé cũng tràn), dồn vào giỏ lớn là bình thường.
2. **PGA_AGGREGATE_TARGET là mục tiêu mềm**: thiếu thì Oracle *vượt* chứ không bóp chết session (đếm tại `over allocation count`). Đừng đọc "allocated > target" là bug — đọc là "target đặt thấp hơn mức sống được". Trần cứng thật sự là `PGA_AGGREGATE_LIMIT` (ORA-4036).
3. **Đọc V$PGA_TARGET_ADVICE theo thứ tự bắt buộc**: (1) loại mọi dòng `ESTD_OVERALLOC_COUNT > 0`; (2) trong phần còn lại chọn điểm gãy của hit%. Chọn theo hit% trước là sai — target đẹp hit% mà overalloc > 0 vẫn là target không đủ sống.

## Câu hỏi tự kiểm tra

1. Ba kiểu kết thúc của một work area? Kiểu nào chấp nhận được ở batch nhưng vẫn cấm ở OLTP?
2. Vì sao `SORT_AREA_SIZE` không có tác dụng khi `WORKAREA_SIZE_POLICY=AUTO`?
3. `V$SQL_WORKAREA_ACTIVE` và `V$SQL_WORKAREA` khác nhau chỗ nào? Khi điều tra một câu "hôm qua chậm" thì dùng cái nào?
4. `total PGA allocated` vượt target là hiện tượng gì? Tham số nào mới là trần cứng và vượt nó thì session bị gì?
5. Nêu thứ tự 2 bước đọc PGA Advisory. Vì sao advisory đo lúc hệ thống rảnh lại vô giá trị?


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/labs/section_23/README.md`
