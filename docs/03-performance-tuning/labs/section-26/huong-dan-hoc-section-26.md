---
title: 📚 Hướng dẫn học Section 26 — Disk I/O Tuning (thực hành trong Linux VM)
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/labs/section_26/HUONG_DAN_HOC_SECTION_26.md
---

# 📚 Hướng dẫn học Section 26 — Disk I/O Tuning (thực hành trong Linux VM)

> ⚠️ **Lab này CHƯA được chạy kiểm chứng end-to-end trên VM.** Output mẫu là **kỳ vọng** dựa trên Practice 28 + Oracle internals. Cần đúng **xu hướng**, không cần khớp từng số.
> Thời lượng gợi ý: ~85 phút (lecture 20' + lab chính 40' + calibration 10' + debrief 15').
> Nguồn: Practice 28 (Ahmed Baraka) + [senior guide](../../section-all-new/section-26-disk-io-senior-guide.md)

---

## 0. Kiến thức nền 5 phút (đọc trước khi gõ lệnh)

Khi thấy I/O wait events ở top, câu hỏi ĐÚNG **không** phải "storage của tôi chậm không?" mà là:
**"Query này đang làm quá nhiều physical I/O, hay storage thật sự không đáp ứng nổi?"**

```
I/O wait cao
   ├── LOGIC problem (90% ca)   → query đọc thừa: FTS thay index, index UNUSABLE, plan xấu
   │                             → Fix: sửa query / index / stats
   └── CAPACITY problem          → storage không đủ băng thông (nhiều session cùng chờ, latency/req cao)
                                  → Fix: async I/O, ASM striping, thêm disk
```

**3 loại I/O read event:**

| Event | Sinh ra khi | Đọc vào đâu |
|---|---|---|
| `db file sequential read` | đọc **1 block** (index lookup, fetch 1 row by rowid) | buffer cache |
| `db file scattered read` | **multiblock** (FTS, index range lớn) | buffer cache (slot rời rạc) |
| `direct path read` | FTS lớn / parallel / sort spill | thẳng vào PGA (bypass cache) |

**Trap kinh điển của lab này:** `ALTER TABLE MOVE` → mỗi row nhận **ROWID mới** → B-tree index (lưu `key,rowid`) trỏ sai → Oracle mark index **UNUSABLE** → optimizer bỏ index → `WHERE order_id = :x` thành **FTS**. Application vẫn đúng kết quả, chỉ chậm 50-100x.

---

## 1. Khởi động môi trường (5 phút)

```powershell
cd D:\Dba_project\vagrant-projects\OracleDatabase\19.3.0
vagrant up
vagrant ssh
```
```bash
sudo -u oracle -i
cd /labs/section_26
echo exit | sqlplus -S -L system/oracle_4U@//localhost:1521/ORADB @../_toolkit/00_env_check.sql
```
**Kỳ vọng:** 8 mục PASS.

**Grant một lần** cho `before_after.sql` (mất sau restore snapshot) — bằng **SYS**:
```bash
sqlplus / as sysdba
```
```sql
GRANT SELECT ON sys.v_$session_event TO soe;
EXIT
```

---

## 2. PHẦN A — Lab chính: UNUSABLE index → FTS (user `soe`, ~40 phút)

```bash
sqlplus soe/soe@//localhost:1521/ORADB
```
> Trong VM port **1521** (host là 15210).

### Bước A1 — Tạo bệnh: `@01_setup.sql` (~1-2 phút)

🤔 **Dự đoán:** tạo IO_ORDERS 1M rows + index trên ORDER_ID (index VALID). Sau `ALTER TABLE MOVE`, index còn dùng được không?

```sql
@01_setup.sql
```

**Kỳ vọng:** trước MOVE `IO_ORD_IDX` **VALID**; sau MOVE **UNUSABLE**. Bệnh đã cấy nhưng chưa ai biết — application vẫn chạy đúng.

### Bước A2 — Đo BASELINE: `@02_workload.sql 300`

🤔 **Dự đoán:** 300 lần `SELECT * FROM io_orders WHERE order_id = :x`. Với index UNUSABLE, mỗi lookup Oracle làm gì? `session logical reads` cỡ bao nhiêu?

```sql
@02_workload.sql 300
```

**Output kỳ vọng — GHI 3 SỐ:**

```text
table scan blocks gotten   rất lớn   ← BẰNG CHỨNG: mỗi lookup quét cả bảng (FTS)
session logical reads      hàng triệu
physical reads             cao
Top wait: db file scattered read (hoặc direct path read)
```

⚠️ Nếu chạy quá lâu (FTS 1M block × 300), Ctrl+C và chạy lại với số nhỏ hơn: `@02_workload.sql 100`.

### Bước A3 — Chẩn đoán: `@03_diagnose.sql`

🤔 **Dự đoán:** query có `WHERE order_id = :x` (equality trên cột đã index) — nhưng execution plan sẽ là gì?

```sql
@03_diagnose.sql
```

| Bước | Kỳ vọng | Bài học |
|---|---|---|
| 1. Wait events phiên SALES | `db file scattered read` đứng đầu | I/O wait — nhưng do đâu? |
| 2. Execution plan | `TABLE ACCESS FULL IO_ORDERS` | FTS dù equality predicate → **bất thường** |
| 3. Index status | `IO_ORD_IDX = UNUSABLE` | Thủ phạm im lặng |
| 4. Root cause | MOVE ở 01_setup | ROWID đổi → index trỏ sai → UNUSABLE |
| 5. Rebuild script | sinh sẵn lệnh | Best practice: chuẩn bị trước khi fix |

### Bước A4 — Sửa + đo lại: `@04_fix.sql 300`

🤔 **Dự đoán:** (1) Sau REBUILD ONLINE, plan về index scan chưa? (2) `table scan blocks gotten` về bao nhiêu? (3) `session logical reads` giảm cỡ nào?

```sql
@04_fix.sql 300
```

**Output kỳ vọng — so với 3 số ở A2:**

| Chỉ số | A2 (FTS) | A4 (index) | Ý nghĩa |
|---|---|---|---|
| `table scan blocks gotten` | rất lớn | **~0** | Hết FTS |
| `session logical reads` | hàng triệu | hàng nghìn | Giảm ~1000x |
| `physical reads` | cao | thấp | I/O thật giảm |
| Top wait | scattered read | biến mất | I/O "cao" là hệ quả, không phải nguyên nhân |
| Index status | UNUSABLE | **VALID** | — |

💡 **Điểm đắt giá:** ta **không đụng gì tới storage** — chỉ REBUILD một index và "I/O bottleneck" biến mất. Đây là lý do luôn hỏi "query đọc thừa hay storage yếu?" trước khi đổ lỗi phần cứng.

---

## 3. PHẦN B — Mở rộng: I/O Calibration (user SYS trong VM, ~10 phút)

⚠️⚠️ **CẨN THẬN — thay đổi cấu hình instance + restart + quiesce.**

**Snapshot bắt buộc trước:**
```powershell
vagrant snapshot save pre_calibrate
```

```bash
sqlplus / as sysdba
@05_calibrate_io.sql
```

- **PHẦN A (an toàn, read-only):** xem `V$IOSTAT_FILE.ASYNCH_IO` (kỳ vọng ban đầu `ASYNC_OFF` theo PDF), latency `V$FILESTAT`, và `DBA_RSRC_IO_CALIBRATE` (NULL = chưa calibrate bao giờ).
- **PHẦN B (bỏ comment để chạy):** `FILESYSTEMIO_OPTIONS=SETALL` + `SHUTDOWN/STARTUP` → verify `ASYNC_ON`.
- **PHẦN C (bỏ comment để chạy):** `QUIESCE RESTRICTED` + `CALIBRATE_IO` (~9 phút) + `UNQUIESCE`.

💡 **Bài học:** Oracle dùng `DBA_RSRC_IO_CALIBRATE` để phân bổ I/O slave cho parallel query. Trên VM, `NUM_PHYSICAL_DISKS` thường sai (NULL/1) → parallel I/O mis-calibrate → **số calibration trên VM chỉ để hiểu quy trình, không lấy làm chuẩn**. `SETALL` bật async + bypass OS page cache (bỏ "double caching": Oracle buffer cache + OS page cache cùng giữ 1 block).

**Phục hồi sau khi chạy B/C:**
```powershell
vagrant snapshot restore pre_calibrate
```

---

## 4. Dọn dẹp (BẮT BUỘC — 1 phút)

Nếu chỉ chạy PHẦN A lab chính:
```sql
@99_cleanup.sql
```
Nếu đã chạy 05 PHẦN B/C: `vagrant snapshot restore pre_calibrate`.

```sql
exit
```
```bash
exit
exit
```
```powershell
vagrant halt
```

---

## 5. Debrief — tự trả lời KHÔNG nhìn tài liệu (15 phút)

1. Vì sao `ALTER TABLE MOVE` làm index UNUSABLE thay vì Oracle tự cập nhật ROWID?
2. `db file sequential read` / `scattered read` / `direct path read` — mỗi cái sinh khi nào, đọc vào đâu?
3. Làm sao phân biệt **logic problem** với **capacity problem**? Cần bằng chứng gì ở cả phía Oracle lẫn OS?
4. Có 2 cách MOVE mà **không** làm index UNUSABLE trong 19c — là gì?
5. `FILESYSTEMIO_OPTIONS=SETALL` bật gì? "Double caching" là gì và vì sao lãng phí?

<details>
<summary>📖 Đáp án</summary>

1. ROWID mã hóa vị trí vật lý (file#, block#, row#). MOVE viết lại toàn bộ rows sang extent mới → **mọi ROWID đổi**. Cập nhật ROWID cho từng entry trong mọi index sẽ cực đắt và không nguyên tử; Oracle chọn mark UNUSABLE (an toàn) để optimizer biết mà bỏ qua, thay vì để index trỏ sai gây kết quả sai.
2. **sequential**: đọc 1 block (index lookup, fetch by rowid) → buffer cache. **scattered**: multiblock (FTS/index range lớn) → buffer cache, block vào slot rời rạc. **direct path**: FTS lớn / parallel / sort spill → thẳng vào PGA, bypass buffer cache (không làm ấm cache).
3. **Logic**: query đọc nhiều block hơn cần (FTS thay index, plan xấu, UNUSABLE index) → xem execution plan + `table scan blocks gotten`. **Capacity**: throughput vượt hardware, latency/request cao (>10ms cơ, >2ms SSD), nhiều session cùng chờ → cần cả Oracle wait time **và** OS `iostat -x` (`%util>80%`, `await>10ms`). Fix logic ≠ fix capacity.
4. `ALTER TABLE ... MOVE ONLINE` (12.2+, Oracle tự maintain index) hoặc `ALTER TABLE ... MOVE ... UPDATE INDEXES`. Cả hai giữ index VALID xuyên suốt.
5. `SETALL` = ASYNCH (submit I/O rồi tiếp tục, OS báo khi xong) + DIRECTIO (bypass OS page cache). **Double caching**: Oracle đã cache data block trong buffer cache; nếu OS cũng cache cùng block trong page cache → tốn RAM 2 lần, giảm hiệu quả. DIRECTIO loại lớp cache OS. (Lưu ý: trên ASM, FILESYSTEMIO_OPTIONS thường bị bỏ qua — ASM tự lo async.)

</details>

---

## 6. Sự cố thường gặp

| Triệu chứng | Nguyên nhân → Xử lý |
|---|---|
| `SP2-0310: unable to open "../_toolkit/..."` | Không đứng ở `/labs/section_26` → `cd` rồi vào lại sqlplus |
| `ORA-00942` khi before_after chụp waits | soe thiếu grant → SYS: `GRANT SELECT ON sys.v_$session_event TO soe;` |
| 02_workload chạy quá lâu | FTS 1M block × N → giảm N: `@02_workload.sql 100`, hoặc Ctrl+C |
| Plan ở 03 **không** FTS | Index chưa UNUSABLE (chạy lại `@01_setup.sql`), hoặc bind peeking → thử literal |
| `ORA-01033` khi calibrate | DB đang quiesce/restart dở → chờ, hoặc `ALTER SYSTEM UNQUIESCE` |
| Muốn hoàn tác 05 B/C | `vagrant snapshot restore pre_calibrate` (99_cleanup không hoàn tác restart được) |

---

## 7. Sau buổi học

- [ ] Báo Claude "chốt buổi" → cập nhật `progress.md` + memory
- [ ] `vagrant halt` (và xóa snapshot pre_calibrate nếu đã tạo)
- [ ] **Lab chưa kiểm chứng VM** — khi chạy thật, ghi số đo thật để cập nhật tài liệu
- [ ] Buổi kế tiếp: Section 27 (Index Defragmentation) — cùng chủ đề index/storage


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/labs/section_26/HUONG_DAN_HOC_SECTION_26.md`
