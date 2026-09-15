---
title: 📚 Hướng dẫn học Section 31 — In-Memory Column Store (thực hành trong Linux VM)
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/labs/section_31/HUONG_DAN_HOC_SECTION_31.md
---

# 📚 Hướng dẫn học Section 31 — In-Memory Column Store (thực hành trong Linux VM)

> ⚠️ **Lab này CHƯA được chạy kiểm chứng end-to-end trên VM.** Output mẫu là **kỳ vọng** dựa trên Practice 33 + Oracle internals.
> ⚠️⚠️ **SNAPSHOT BẮT BUỘC** (thay đổi SGA + INMEMORY_SIZE + restart) · **LICENSE**: In-Memory Option tính phí riêng.
> Thời lượng gợi ý: ~80 phút (lecture 25' + lab 40' + debrief 15').
> Nguồn: Practice 33 (Ahmed Baraka) + [senior guide](../../section-all-new/section-31-in-memory-column-store-senior-guide.md)

---

## 0. Kiến thức nền 5 phút

Database In-Memory **không phải cache query riêng** — là kiến trúc **dual-format**:

```
DISK (row) ──► Buffer Cache (ROW)    ──► OLTP: lookup, DML 1 row
           ──► In-Memory Store (COLUMNAR) ──► Analytics: scan, aggregate
                        ▲
              Optimizer TỰ chọn format theo query
```

- Optimizer tự chọn: query analytic → `TABLE ACCESS INMEMORY FULL`; lookup PK → row store. IM **không** tăng tốc single-row lookup.
- Nhanh nhờ: columnar scan (chỉ đọc cột cần) + SIMD (tỷ row/giây) + In-Memory Storage Index (min/max prune IMCU).
- IM **transient**: không persist, restart là mất → phải populate lại (background `Wnnn`).
- Populate **bất đồng bộ**: `PRIORITY NONE` populate khi bị quét lần đầu; `CRITICAL` populate ngay lúc startup.

**Chuỗi tư duy:** cấu hình IM → đo baseline FTS → bật IM, chờ populate → đo lại (giảm dần qua các lần chạy) → footprint IM << segment.

---

## 1. Khởi động + Snapshot bắt buộc (5 phút)

```powershell
cd D:\Dba_project\vagrant-projects\OracleDatabase\19.3.0
vagrant up
vagrant snapshot save pre_inmemory      # ⚠️ BẮT BUỘC — lab đổi SGA + restart
vagrant ssh
```
```bash
sudo -u oracle -i
cd /labs/section_31
```

---

## 2. Cấu hình In-Memory (SYS, ~10 phút)

```bash
sqlplus / as sysdba
```
```sql
@01_setup.sql
```
🤔 **Dự đoán:** INMEMORY_SIZE nằm trong SGA. Vì sao phải nâng SGA **trước** khi cấp cho IM?

- BƯỚC 1 hiện cấu hình bộ nhớ hiện tại (INMEMORY_SIZE = 0).
- **Bỏ comment BƯỚC 2** để: set SGA 2.5G + INMEMORY_SIZE 300M (spfile) + `SHUTDOWN IMMEDIATE`/`STARTUP`.
- BƯỚC 3: xác nhận `V$INMEMORY_AREA` có pool ~300M.

**Kỳ vọng:** sau restart, `V$INMEMORY_AREA` hiện `1MB POOL` + `64KB POOL`, tổng ~300M.

---

## 3. Thực nghiệm (soe, ~30 phút)

```bash
sqlplus soe/soe@//localhost:1521/ORADB
```

### Bước 1 — Tạo bảng + đo baseline: `@02_workload.sql`

🤔 **Dự đoán:** ORDERS2 2M row, query `SUM(order_total) GROUP BY month`. Baseline dùng plan gì? Sau khi `ALTER TABLE INMEMORY`, plan đổi thành gì?

```sql
@02_workload.sql
```

**Kỳ vọng — GHI logical reads từng mốc:**
```text
Baseline (buffer cache) : TABLE ACCESS FULL,          logical reads CAO
Sau IM (đã populate)    : TABLE ACCESS INMEMORY FULL, logical reads THẤP
```
💡 Script dùng `PRIORITY CRITICAL` + vòng chờ `POPULATE_STATUS=COMPLETED` để deterministic. **Chạy lại khối before_after 2-3 lần** để thấy logical reads giảm dần rồi ổn định thấp (physical reads → 0).

### Bước 2 — Kiểm tra vùng IM: `@03_diagnose.sql`

🤔 **Dự đoán:** Footprint IM của bảng so với kích thước segment trên đĩa — lớn hơn, bằng, hay nhỏ hơn nhiều?

```sql
@03_diagnose.sql
```
| Bước | Kỳ vọng | Bài học |
|---|---|---|
| 1. V$INMEMORY_AREA | pool ~300M, populate DONE | Vùng IM tách trong SGA |
| 2. V$IM_SEGMENTS | IM_MB << SEGMENT_MB, COMPLETED | Nén columnar; phải COMPLETED mới đo đúng |
| 3. USER_TABLES | INMEMORY=ENABLED, priority CRITICAL | Thuộc tính IM của bảng |

> Nếu soe không đọc được V$IM_SEGMENTS: chạy phần này bằng SYS, hoặc SYS grant `SELECT ON v_$im_segments`, `v_$inmemory_area` cho soe.

### Bước 3 (tùy chọn) — Nén/cột/index: `@04_usecase_compress_col.sql`

```sql
@04_usecase_compress_col.sql
```
**Kỳ vọng:** `CAPACITY HIGH` footprint nhỏ hơn `QUERY LOW`; loại cột NOTE → footprint giảm; optimizer chọn INMEMORY FULL thay vì index analytic → lập luận **bỏ index thừa để DML nhanh hơn**.

---

## 4. Dọn dẹp (BẮT BUỘC)

```sql
@99_cleanup.sql
exit
```
```bash
exit
exit
```
```powershell
vagrant snapshot restore pre_inmemory   # trả SGA/INMEMORY_SIZE/restart về trước lab
```

---

## 5. Debrief — tự trả lời KHÔNG nhìn tài liệu (15 phút)

1. IM là cache riêng hay dual-format? Ai chọn dùng IM cho query?
2. Vì sao query lần 1 sau khi bật IM chưa nhanh, lần 3 mới nhanh?
3. IM lấy RAM từ đâu? Không tăng SGA thì cái gì bị bóp?
4. IM có tăng tốc `WHERE order_id = :x` không? Vì sao?
5. `PRIORITY NONE` vs `CRITICAL` — thời điểm populate khác gì? Liên quan cold-start sau restart?
6. Vì sao "bỏ được analytic index" thường là ROI lớn hơn cả tốc độ query?

<details>
<summary>📖 Đáp án</summary>

1. **Dual-format** — cùng bảng ở cả row (buffer cache) và columnar (IMCS), nhất quán giao dịch. **Optimizer tự chọn** format theo query, không phải bạn viết query khác.
2. Populate bất đồng bộ. Query lần 1 chạy khi IMCU chưa populate xong (đọc đĩa + đang populate) → stats còn cao; lần 2 giảm nửa; lần 3+ populate xong (`COMPLETED`) → đọc thẳng columnar trong RAM → physical reads = 0, consistent gets rất thấp.
3. IM là pool **tách riêng trong SGA** (`INMEMORY_SIZE`), không auto-tune. Không tăng SGA khi bật IM → buffer cache/shared pool bị bóp → OLTP degrade. Phải nâng SGA trước.
4. **Không.** IM tăng tốc scan/aggregate (columnar + SIMD + storage index). Single-row lookup qua PK/index đi thẳng tới rowid trong row store — IM không giúp. Dùng IM cho bảng OLTP lookup thuần là lãng phí license.
5. `NONE` (mặc định): partition/bảng chỉ populate khi bị **quét lần đầu** → query analytic đầu tiên sau restart chậm (cold-start). `CRITICAL/HIGH`: populate ngay lúc startup → sẵn sàng ngay nhưng startup lâu hơn + tốn I/O đầu giờ. IM không persist nên cold-start lặp lại mỗi restart → PRIORITY quan trọng.
6. Sau khi IM phục vụ query báo cáo (thay index analytic bằng INMEMORY scan), có thể **drop các index chỉ dùng cho báo cáo**. Ít index hơn → INSERT/UPDATE/DELETE nhanh hơn, bảng nhỏ hơn. Lợi ích DML này thường lớn và bền hơn bản thân tốc độ query.

</details>

---

## 6. Sự cố thường gặp

| Triệu chứng | Xử lý |
|---|---|
| `ORA-00439: feature not enabled: In-Memory Column Store` | Edition/phiên bản không hỗ trợ → không chạy được lab này |
| `ORA-02097 / ORA-00838` khi set INMEMORY_SIZE | SGA quá nhỏ so với INMEMORY_SIZE → nâng SGA trước (BƯỚC 2 đã làm) |
| Plan vẫn `TABLE ACCESS FULL` sau khi bật IM | Chưa populate xong → chờ `POPULATE_STATUS=COMPLETED` (V$IM_SEGMENTS) |
| soe không query được V$IM_SEGMENTS | Chạy bằng SYS, hoặc SYS grant `SELECT ON v_$im_segments` cho soe |
| `SP2-0310` không mở `../_toolkit/...` | `cd /labs/section_31` rồi vào lại sqlplus |
| Muốn hoàn tác cấu hình IM | `vagrant snapshot restore pre_inmemory` (99_cleanup không undo restart được) |

---

## 7. Sau buổi học

- [ ] Báo Claude "chốt buổi" → cập nhật `progress.md` + memory
- [ ] `vagrant snapshot restore pre_inmemory` rồi `vagrant halt` (+ xóa snapshot nếu muốn)
- [ ] **Lab chưa kiểm chứng VM** — chạy thật để ghi số đo thật
- [ ] Buổi kế tiếp: Section 32 (Database Connection Optimization)


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/labs/section_31/HUONG_DAN_HOC_SECTION_31.md`
