---
title: 📚 Hướng dẫn học Section 27 — Index Defragmentation (thực hành trong Linux VM)
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/labs/section_27/HUONG_DAN_HOC_SECTION_27.md
---

# 📚 Hướng dẫn học Section 27 — Index Defragmentation (thực hành trong Linux VM)

> ⚠️ **Lab này CHƯA được chạy kiểm chứng end-to-end trên VM.** Output mẫu là **kỳ vọng** dựa trên tài liệu Practice 29 + Oracle internals — có thể lệch theo phiên bản. Cần đúng **xu hướng**, không cần khớp từng số.
> Thời lượng gợi ý: ~80 phút (lecture 20' + lab 45' + debrief 15').
> Nguồn: Practice 29 (Ahmed Baraka) + [senior guide](../../section-all-new/section-27-index-defrag-senior-guide.md)

---

## 0. Kiến thức nền 5 phút (đọc trước khi gõ lệnh)

**Myth phổ biến nhất giới Oracle DBA:** "rebuild index định kỳ để giữ hiệu năng". Oracle Corp đã bác bỏ chính thức. B-tree **self-balancing** — không bao giờ mất cân bằng dù insert/delete bao nhiêu.

Fragmentation **chỉ** gây hại trong một pattern cụ thể:

| | Gây hại (cần defrag) | KHÔNG gây hại (Oracle tự lo) |
|---|---|---|
| Pattern | Khóa **tuần tự** (ID/timestamp) + **bulk delete** data cũ | Random insert + random delete |
| Vì sao | Deleted entry dồn về **bên trái**; không có insert mới với key nhỏ → Oracle **không reuse** được → leaf block "rỗng" vẫn nằm trong tree | Insert mới rơi vào cùng key range → Oracle **reuse** deleted entry → tự cân bằng |

**3 công cụ defrag (từ nhẹ → nặng):** `COALESCE` < `SHRINK SPACE COMPACT` < `SHRINK SPACE` < `REBUILD`.

| | Gộp leaf | Trả space về tablespace | Giảm BLEVEL | Cần lock |
|---|---|---|---|---|
| `COALESCE` | ✅ | ❌ | ❌ | Không |
| `SHRINK SPACE` | ✅ | ✅ (ASSM) | ❌ | Brief |
| `REBUILD` | ✅ (tạo mới) | ✅ | ✅ | Có (cutover) |

**Chuỗi tư duy của lab:** tạo fragmentation đúng pattern → chẩn đoán "có đáng defrag không" → so sánh COALESCE vs REBUILD bằng số → hiểu vì sao production ưu tiên COALESCE.

---

## 1. Khởi động môi trường (5 phút)

### 1.1. Bật VM (PowerShell trên host)

```powershell
cd D:\Dba_project\vagrant-projects\OracleDatabase\19.3.0
vagrant up
```

### 1.2. SSH vào VM, thành user oracle, vào đúng thư mục lab

```powershell
vagrant ssh
```

```bash
sudo -u oracle -i
cd /labs/section_27          # ⚠️ BẮT BUỘC đứng ở đây (script tham chiếu tương đối)
```

### 1.3. Kiểm tra môi trường

```bash
echo exit | sqlplus -S -L system/oracle_4U@//localhost:1521/ORADB @../_toolkit/00_env_check.sql
```

**Kỳ vọng:** 8 mục PASS.

---

## 2. PHẦN A — Lab chính (user `soe`, ~30 phút)

```bash
sqlplus soe/soe@//localhost:1521/ORADB
```

> Trong VM port là **1521** (từ host Windows là 15210).

### Bước A1 — Tạo bảng: `@01_setup.sql` (~30-60s)

🤔 **Dự đoán:** TTABLE 500k rows, R_ID = 1..500000 (tuần tự), index trên R_ID. Index lúc này có deleted entry chưa?

```sql
@01_setup.sql
```

**Kỳ vọng:** `500000 rows created` (×2), index tạo xong. Index **khỏe** — chưa có bệnh.

### Bước A2 — Gây fragmentation + đo baseline: `@02_workload.sql`

🤔 **Dự đoán:** DELETE 200k rows có R_ID nhỏ nhất (0..200000). Sau đó: (1) `DEL_LF_ROWS` = bao nhiêu? (2) `BLOCKS` (tổng size index) tăng, giảm, hay giữ nguyên?

```sql
@02_workload.sql
```

**Output kỳ vọng — GHI 3 SỐ (BƯỚC 4):**

```text
BEFORE delete:  BLOCKS ~1000   DEL_LF_ROWS = 0        PCT_USED ~90%
AFTER  delete:  BLOCKS ~1000   DEL_LF_ROWS = 200,000  PCT_USED van ~90%
```

💡 **Điểm mấu chốt:** DELETE **không** trả lại space — `BLOCKS` gần như không đổi, chỉ `DEL_LF_ROWS` nhảy lên 200k. Space của entry đã xóa **vẫn bị chiếm** = fragmentation. Và `USER_IND_STATISTICS` (dictionary) **không** có cột đếm deleted entry → phải `ANALYZE ... VALIDATE STRUCTURE` mới thấy.

### Bước A3 — Chẩn đoán "có đáng defrag không": `@03_diagnose.sql`

🤔 **Dự đoán:** DEL_LF_ROWS = 40% nghe rất cao. Nhưng con số đó có đủ để kết luận "phải rebuild" không? Cần thêm bằng chứng gì?

```sql
@03_diagnose.sql
```

| Bước | Kỳ vọng | Bài học |
|---|---|---|
| 1. BLEVEL | 1-2 (bình thường cho 500k) | BLEVEL bất thường mới cần REBUILD; ở đây bình thường → COALESCE đủ |
| 2. Fragmentation | DEL_LF_ROWS ~200k (~40%) | Con số cao — **nhưng chưa đủ kết luận** |
| 3. Pattern | MIN(R_ID) ≈ 200,001 | **Bằng chứng quyết định**: R_ID nhỏ đã bị xóa hết, không có insert mới ở đó → Oracle **không reuse được** → đáng defrag |

**Kết luận:** đây đúng là "sequential key + bulk delete old" → deleted entry dồn trái, không reuse → defrag đáng giá. (Nếu là random delete → Oracle tự cân bằng → **không** defrag.)

### Bước A4 — So sánh COALESCE vs REBUILD: `@04_fix.sql`

🤔 **Dự đoán trước khi chạy:** (1) COALESCE có làm `BLOCKS` giảm không? (2) REBUILD thì sao? (3) Cái nào trả space về tablespace?

```sql
@04_fix.sql
```

**Output kỳ vọng — so sánh:**

| Chỉ số | Sau COALESCE | Sau REBUILD |
|---|---|---|
| `DEL_LF_ROWS` | **0** | **0** |
| `LF_BLKS` | **giảm** | **giảm** |
| `BLOCKS` (tổng size) | **GIỮ NGUYÊN** | **GIẢM** |

💡 **Khác biệt cốt lõi:** cả hai đều xóa deleted entry (LF_BLKS giảm), nhưng **COALESCE không trả space** (BLOCKS giữ nguyên — space chỉ được gộp lại để tái dùng nội bộ index), còn **REBUILD tạo lại toàn bộ** nên trả space về tablespace (BLOCKS giảm). Đổi lại REBUILD cần lock cutover.

---

## 3. PHẦN B — Mở rộng: REBUILD hang dưới DML + SHRINK SPACE (~15 phút)

### 3.1. Thí nghiệm REBUILD ONLINE **hang** khi bảng đang DML

Đây là nhược điểm lớn nhất của REBUILD trên production 24x7.

**Cửa sổ 1 (soe, tạo lại fragmentation):** nếu vừa chạy 04 xong thì TTABLE đã rebuild sạch — tạo lại bệnh:
```sql
@01_setup.sql
@02_workload.sql
```

**Cửa sổ 2 (shell trong VM):** sinh DML liên tục 120 giây:
```bash
cd /labs/section_27
./idx_dml_load.sh 120        # hoặc: nohup ./idx_dml_load.sh 120 &
```

**Cửa sổ 1 (soe):** rebuild — sẽ **treo**:
```sql
EXEC DBMS_SESSION.SET_IDENTIFIER('Index Rebuild')
ALTER INDEX ttable_idx REBUILD ONLINE;
```

**Cửa sổ 3 (SYS, theo dõi):**
```sql
sqlplus / as sysdba
@05_shrink_and_dml.sql
```
(chạy PHẦN B của file — bỏ qua PHẦN A nếu index đang bị khóa)

**Kỳ vọng:** session 'Index Rebuild' có `EVENT = 'enq: TX - row lock contention'` hoặc `'blocking txn id for DDL'`, `blocking_session` trỏ về session `LAB27_DML`. Khi `idx_dml_load.sh` hết 120s (hoặc bạn Ctrl+C), REBUILD **hoàn thành ngay trong vài giây**.

💡 **Bài học:** REBUILD ONLINE vẫn cần một **DDL lock ngắn ở bước cutover cuối** — phải chờ **mọi** active transaction trên bảng đóng lại. DML liên tục giữ nó chờ vô hạn. `COALESCE` không có bước cutover → không hang → lựa chọn cho bảng 24x7.

### 3.2. SHRINK SPACE trả space (user soe)

```sql
@05_shrink_and_dml.sql      -- PHẦN A
```

**Kỳ vọng:** khác COALESCE, `BLOCKS` **giảm** (trả space về tablespace ASSM). SHRINK SPACE = COMPACT + deallocate; không cần `ENABLE ROW MOVEMENT` (khác table shrink).

---

## 4. Dọn dẹp (BẮT BUỘC — 1 phút)

```sql
@99_cleanup.sql
```

**Kỳ vọng:** các dòng `OK`, rồi query xác nhận `no rows selected`.

```sql
exit
```
```bash
exit    # thoát user oracle
exit    # thoát SSH
```
```powershell
vagrant halt
```

---

## 5. Debrief — tự trả lời KHÔNG nhìn tài liệu (15 phút)

1. Vì sao "DEL_LF_ROWS = 40%" chưa đủ để kết luận phải rebuild? Điều kiện gì mới khiến deleted entry **không được reuse**?
2. Với random insert/delete, tại sao Oracle **không** cần defrag định kỳ?
3. `COALESCE` vs `REBUILD` vs `SHRINK SPACE`: cái nào trả space? cái nào giảm BLEVEL? cái nào cần lock?
4. `REBUILD ONLINE` hang ở **bước nào**, chờ **gì**? Vì sao `COALESCE` không hang?
5. `INDEX_STATS` là view kiểu gì? ANALYZE index A rồi ANALYZE index B → đọc `INDEX_STATS` ra của ai?

<details>
<summary>📖 Đáp án</summary>

1. DEL_LF_ROWS cao chỉ nói "có nhiều entry đã xóa", không nói chúng có được reuse không. Điều kiện gây hại: **khóa tuần tự + xóa data cũ hàng loạt** → entry xóa dồn về bên trái, không có insert mới với key nhỏ → Oracle không reuse. Nếu delete rải rác (random) → insert mới rơi vào cùng key range → reuse → tự lành.
2. B-tree self-balancing: khi INSERT mới có key nằm trong key range của block chứa deleted entry, Oracle tái dùng chỗ đó ngay. Random workload luôn có insert mới rơi khắp key range → deleted entry liên tục được reuse → BLEVEL và LEAF_BLOCKS tự ổn định.
3. **Trả space:** REBUILD và SHRINK SPACE (không COMPACT). COALESCE **không**. **Giảm BLEVEL:** chỉ REBUILD. **Cần lock:** REBUILD (cutover) và SHRINK SPACE (brief); COALESCE không.
4. Hang ở **bước cutover cuối** (đổi index cũ → mới), cần **exclusive DDL lock ngắn**, phải chờ mọi active transaction trên bảng commit/rollback. DML liên tục (transaction luôn mở) → chờ vô hạn. COALESCE chỉ gộp leaf tại chỗ, không đổi cấu trúc segment → không cần cutover lock.
5. `INDEX_STATS` là **virtual view trong memory**, chỉ giữ kết quả của **lần ANALYZE VALIDATE STRUCTURE gần nhất trong session hiện tại** (một dòng, bị ghi đè). ANALYZE A rồi B → đọc ra của **B** (kết quả A đã mất).

</details>

---

## 6. Sự cố thường gặp

| Triệu chứng | Nguyên nhân → Xử lý |
|---|---|
| `SP2-0310: unable to open file "../_toolkit/..."` | Không đứng ở `/labs/section_27` → `cd /labs/section_27` rồi vào lại sqlplus |
| REBUILD ONLINE không hang dù đã chạy idx_dml_load | DML load đã hết giờ, hoặc commit quá thưa → tăng thời gian `./idx_dml_load.sh 300`, và rebuild ngay khi load đang chạy |
| `ORA-10635: Invalid segment or tablespace type` khi SHRINK | Tablespace không phải ASSM → dùng COALESCE thay thế, hoặc REBUILD |
| `idx_dml_load.sh: bad interpreter` / `^M` | File dính CRLF → `sed -i 's/\r$//' idx_dml_load.sh` trong VM |
| DEL_LF_ROWS = 0 ngay sau delete | Đã chạy 04/coalesce trước đó → chạy lại `@01_setup.sql` + `@02_workload.sql` |

---

## 7. Sau buổi học

- [ ] Báo Claude "chốt buổi" → cập nhật `progress.md` + memory
- [ ] `vagrant halt`
- [ ] **Lab này chưa kiểm chứng VM** — khi chạy thật, ghi lại số đo thật để cập nhật tài liệu (đổi "kỳ vọng" → "số đo thật")
- [ ] Buổi kế tiếp: Section 29 (Table Fragmentation) hoặc ôn "chạy mù" một section cũ


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/labs/section_27/HUONG_DAN_HOC_SECTION_27.md`
