---
title: 📚 Hướng dẫn học Section 29 — Table Fragmentation (thực hành trong Linux VM)
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/labs/section_29/HUONG_DAN_HOC_SECTION_29.md
---

# 📚 Hướng dẫn học Section 29 — Table Fragmentation (thực hành trong Linux VM)

> ⚠️ **Lab này CHƯA được chạy kiểm chứng end-to-end trên VM.** Output mẫu là **kỳ vọng** dựa trên Practice 31 + Oracle internals. Cần đúng **xu hướng**.
> Thời lượng gợi ý: ~80 phút (lecture 20' + lab 45' + debrief 15').
> Nguồn: Practice 31 (Ahmed Baraka) + [senior guide](../../section-all-new/section-29-table-fragmentation-senior-guide.md)

---

## 0. Kiến thức nền 5 phút

Table fragmentation là bài toán **High Water Mark (HWM)**, không phải "block có holes".

```
Segment:  [==== rows ====][ block gần rỗng ][ rỗng ][ rỗng ]│ HWM
FTS đọc từ đầu đến ─────────────────────────────────────────┘ (dù nửa sau hết row)
```

- DELETE/UPDATE co row để lại block gần rỗng nhưng **HWM KHÔNG tự hạ**.
- **FTS luôn quét tới HWM** → đọc thừa dù bảng chỉ còn nửa dữ liệu.
- Chỉ `TRUNCATE` / `ALTER TABLE MOVE` / `SHRINK SPACE` mới hạ HWM.
- Fragmentation **chỉ phạt FTS**; index unique lookup miễn nhiễm (đi thẳng tới rowid).

**SHRINK SPACE 3 pha:** compact (di chuyển row về đầu, **online**, cần `ENABLE ROW MOVEMENT` vì ROWID đổi) → hạ HWM (lock ngắn) → CASCADE (maintain index, không UNUSABLE — khác MOVE).

**Chuỗi tư duy:** tạo fragment → đo FTS vs index (chứng minh chỉ FTS bị phạt) → shrink → đo lại.

---

## 1. Khởi động môi trường (5 phút)

```powershell
cd D:\Dba_project\vagrant-projects\OracleDatabase\19.3.0
vagrant up
vagrant ssh
```
```bash
sudo -u oracle -i
cd /labs/section_29
echo exit | sqlplus -S -L system/oracle_4U@//localhost:1521/ORADB @../_toolkit/00_env_check.sql
```
**Grant một lần** (SYS) cho `before_after.sql`:
```bash
sqlplus / as sysdba
```
```sql
GRANT SELECT ON sys.v_$session_event TO soe;
EXIT
```

---

## 2. Lab chính (user `soe`, ~40 phút)

```bash
sqlplus soe/soe@//localhost:1521/ORADB
```

### Bước A1 — Tạo fragment: `@01_setup.sql` (~1-2 phút)

🤔 **Dự đoán:** INSERT 100k PCTFREE 0, UPDATE chẵn co row, DELETE bội-3. Sau đó ~bao nhiêu % bảng là free space? HWM có tự hạ khi DELETE không?

```sql
@01_setup.sql
```
**Kỳ vọng:** ~1/3 rows bị xóa, ~1/2 co lại. Bảng fragment nhưng HWM vẫn cao.

### Bước A2 — Đo baseline FTS vs index: `@02_workload.sql 1000`

🤔 **Dự đoán:** WORKLOAD A (FTS trên LAST_NAME không index) vs WORKLOAD B (index lookup trên CUSTOMER_NO). `session logical reads` của cái nào cao hơn nhiều lần?

```sql
@02_workload.sql 1000
```
**Kỳ vọng — GHI 2 SỐ:**
```text
WORKLOAD A (FTS)  : session logical reads RẤT CAO (quét tới HWM mỗi query)
WORKLOAD B (index): session logical reads THẤP (vài block/query)
```

### Bước A3 — Đo fragmentation: `@03_diagnose.sql`

🤔 **Dự đoán:** `AVG_SPACE` cho biết gì? DBMS_SPACE sẽ cho thấy nhiều block ở mức nào?

```sql
@03_diagnose.sql
```
| Góc | Kỳ vọng | Bài học |
|---|---|---|
| 1. AVG_SPACE | free ~40-50% total | Cách course; cần ANALYZE (không DBMS_STATS) |
| 2. DBMS_SPACE | nhiều block FS1 (gần rỗng) | Không cần ANALYZE, không lock |
| 3. actual vs HWM | frag% cao | HWM cao hơn nhiều số block thực chứa row |
| Plan | `TABLE ACCESS FULL` | FTS quét toàn bảng tới HWM |

### Bước A4 — Shrink + đo lại: `@04_fix.sql 1000`

🤔 **Dự đoán:** (1) Sau shrink BLOCKS giảm bao nhiêu? (2) FTS logical reads giảm bao nhiêu? (3) Index lookup có đổi không? (4) Index còn VALID không?

```sql
@04_fix.sql 1000
```
**Kỳ vọng — so với A2:**

| Chỉ số | Trước | Sau | Ý nghĩa |
|---|---|---|---|
| `BLOCKS` | cao | **giảm mạnh** | HWM đã hạ |
| WORKLOAD A (FTS) reads | rất cao | **giảm rõ** | FTS quét ít block hơn |
| WORKLOAD B (index) reads | thấp | ~không đổi | Index miễn nhiễm HWM |
| Index status | VALID | **VALID** | CASCADE maintain (khác MOVE) |

💡 **Điểm chốt:** shrink chỉ giúp FTS. Nếu bảng chỉ truy cập qua index → shrink gần như vô ích.

---

## 3. Mở rộng: SHRINK dưới tải DML + ORA-00054 (~15 phút)

**Cửa sổ 2 (VM):**
```bash
cd /labs/section_29
./cust_update.sh 120
```
**Cửa sổ 1 (soe):** thử bật row movement — sẽ lỗi:
```sql
ALTER TABLE cust ENABLE ROW MOVEMENT;      -- ORA-00054 resource busy
ALTER SESSION SET ddl_lock_timeout = 30;   -- DDL sẽ CHỜ thay vì fail ngay
ALTER TABLE cust ENABLE ROW MOVEMENT;
ALTER TABLE cust SHRINK SPACE COMPACT;     -- pha 1 chạy online cùng DML
```
**Cửa sổ 3 (SYS):** tìm thủ phạm giữ transaction mở:
```sql
sqlplus / as sysdba
@05_shrink_dml.sql      -- PHẦN B
```
**Kỳ vọng:** `ENABLE ROW MOVEMENT` báo ORA-00054 khi DML chạy; V$TRANSACTION chỉ ra session `LAB29_DML`. `DDL_LOCK_TIMEOUT` chỉ hoãn, không sửa gốc.

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
vagrant halt
```

---

## 5. Debrief — tự trả lời KHÔNG nhìn tài liệu (15 phút)

1. Fragmentation phạt FTS hay index lookup? Vì sao (HWM)?
2. Vì sao DELETE không giảm số block FTS phải đọc? Lệnh nào hạ HWM?
3. `AVG_SPACE` populate bởi lệnh gì? Vì sao không phải DBMS_STATS?
4. 3 pha SHRINK SPACE — pha nào online, pha nào cần lock?
5. Vì sao index VALID sau SHRINK CASCADE nhưng UNUSABLE sau MOVE?
6. Vì sao `ENABLE ROW MOVEMENT` báo ORA-00054 khi bảng đang UPDATE?

<details>
<summary>📖 Đáp án</summary>

1. **FTS**. FTS quét mọi block tới HWM; HWM cao dù bảng nửa rỗng → đọc thừa. Index unique lookup đi thẳng key→rowid→block chứa row, không quét khoảng rỗng → miễn nhiễm HWM.
2. DELETE giải phóng row trong block nhưng **không kéo HWM xuống** — HWM là "block cao nhất từng dùng". Chỉ `TRUNCATE` (về 0), `ALTER TABLE MOVE` (viết lại segment), `SHRINK SPACE` (compact + hạ HWM) mới hạ được.
3. `ANALYZE TABLE ... COMPUTE/ESTIMATE STATISTICS`. `DBMS_STATS` (chuẩn optimizer) để `AVG_SPACE` = NULL. Nên nếu dùng ANALYZE để đo → phải gather lại DBMS_STATS ngay sau để không bỏ optimizer stats kiểu cũ trên bảng.
4. **Compact** (di chuyển row về đầu — online, row-level lock, cần ROW MOVEMENT vì ROWID đổi) → **hạ HWM** (exclusive lock rất ngắn cuối pha) → **CASCADE** (maintain index). Pha 1 online; pha 2 cần lock ngắn.
5. `MOVE` viết lại toàn bộ segment một lần → mọi ROWID đổi đồng loạt → global index UNUSABLE. `SHRINK` di chuyển row từng phần **và maintain index đồng thời** trong pha compact → index luôn valid.
6. `ENABLE ROW MOVEMENT` là DDL → cần exclusive DDL lock ngắn, phải chờ mọi transaction mở đóng. Vòng lặp UPDATE commit thưa giữ transaction mở gần như liên tục → DDL không lấy được lock → ORA-00054.

</details>

---

## 6. Sự cố thường gặp

| Triệu chứng | Xử lý |
|---|---|
| `SP2-0310` không mở được `../_toolkit/...` | `cd /labs/section_29` rồi vào lại sqlplus |
| `ORA-00942` khi before_after chụp waits | SYS: `GRANT SELECT ON sys.v_$session_event TO soe;` |
| `ORA-10635: Invalid segment or tablespace type` khi shrink | SOETBS không ASSM → dùng `ALTER TABLE MOVE` thay thế |
| `ORA-00054` khi ENABLE ROW MOVEMENT (ngoài ý muốn) | Có DML đang chạy → dừng, hoặc `ddl_lock_timeout` |
| FTS logical reads không giảm sau shrink | Shrink chưa hạ HWM (thiếu ENABLE ROW MOVEMENT / dùng COMPACT) → chạy `SHRINK SPACE` đủ pha |
| `cust_update.sh: bad interpreter ^M` | CRLF → `sed -i 's/\r$//' cust_update.sh` |

---

## 7. Sau buổi học

- [ ] Báo Claude "chốt buổi" → cập nhật `progress.md` + memory
- [ ] `vagrant halt`
- [ ] **Lab chưa kiểm chứng VM** — chạy thật để ghi số đo thật
- [ ] Buổi kế tiếp: Section 30 (Table Compression)


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/labs/section_29/HUONG_DAN_HOC_SECTION_29.md`
