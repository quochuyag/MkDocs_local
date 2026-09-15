---
title: 📚 Hướng dẫn học Section 28 — Row Migration & Row Chaining (thực hành trong Linux VM)
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/labs/section_28/HUONG_DAN_HOC_SECTION_28.md
---

# 📚 Hướng dẫn học Section 28 — Row Migration & Row Chaining (thực hành trong Linux VM)

> Toàn bộ lệnh trong file này **đã được chạy kiểm chứng end-to-end trong VM ngày 2026-07-14** — output mẫu là số đo thật.
> Thời lượng gợi ý: ~90 phút (lecture 20' + lab 50' + debrief 20').
> Nguồn: Practice 30 (Ahmed Baraka) + guide [section_all/section_28_row_migration_chaining_guide.md](../../section-all/section-28-row-migration-chaining-guide.md)

---

## 0. Kiến thức nền 5 phút (đọc trước khi gõ lệnh)

| | ROW MIGRATION | ROW CHAINING |
|---|---|---|
| Nguyên nhân | UPDATE làm row **phình to**, block cũ hết chỗ → Oracle chuyển CẢ ROW sang block khác, để lại con trỏ | Row **to hơn block** ngay từ đầu → bị cắt thành nhiều piece trên nhiều block |
| Nhận diện | `AVG_ROW_LEN` **nhỏ hơn nhiều** so với block (8192) | `AVG_ROW_LEN` xấp xỉ/lớn hơn block |
| Phạt hiệu năng | Đọc qua index tốn THÊM 1 block/row (đi theo con trỏ) | Đọc cột nằm ở piece sau tốn thêm block |
| Bằng chứng đo được | Thống kê session `table fetch continued row` > 0 | (giống — Oracle gộp chung 2 loại) |
| Cách sửa | PCTFREE cao hơn + rebuild (MOVE) | Block size lớn hơn / tách cột to ra bảng phụ |

**Chuỗi tư duy của lab:** đo baseline (chưa biết gì) → chẩn đoán ra bệnh → sửa → **đo lại chứng minh bằng số**.

---

## 1. Khởi động môi trường (5 phút)

### 1.1. Bật VM (PowerShell trên host)

```powershell
cd D:\Dba_project\vagrant-projects\OracleDatabase\19.3.0
vagrant up          # chờ ~1-2 phút, DB tự start
```

### 1.2. SSH vào VM và thành user oracle

```powershell
vagrant ssh         # → vào shell user vagrant@srv1
```

```bash
sudo -u oracle -i   # → thành user oracle, tự nạp ORACLE_HOME/ORACLE_SID
                    # (KHÔNG có password — sudo từ vagrant là cách chuẩn)
cd /labs/section_28 # ⚠️ BẮT BUỘC đứng ở đây: script gọi ../_toolkit/
```

> SSH cách khác + đầy đủ account/pass: [ke_hoach/05_huong_dan_ssh_vm.md](../../ke-hoach/005-huong-dan-ssh-vm.md)

### 1.3. Kiểm tra môi trường sẵn sàng

```bash
echo exit | sqlplus -S -L system/oracle_4U@//localhost:1521/ORADB @../_toolkit/00_env_check.sql
```

**Kỳ vọng:** 8 mục PASS. (Dấu `—` hiện thành `???` là do locale terminal — vô hại.)

---

## 2. PHẦN A — Lab chính: Row Migration (user `soe`, ~35 phút)

Vào SQL*Plus bằng schema thực hành:

```bash
sqlplus soe/soe@//localhost:1521/ORADB
```

> Trong VM port là **1521**. (Từ host Windows mới là 15210.)

### Bước A1 — Tạo bệnh: `@01_setup.sql` (~1 phút)

🤔 **Dự đoán trước khi chạy:** 200k rows với NOTE=NULL, sau đó UPDATE 1/3 số rows phình NOTE lên 1000 ký tự. PCTFREE mặc định 10% có đủ chỗ cho row phình gấp ~12 lần không?

```sql
@01_setup.sql
```

**Output kỳ vọng:** `200000 rows created` (~10s) → `66666 rows updated` (~40s). Bệnh đã được cấy nhưng **chưa có bằng chứng gì** — đúng như production: bạn chỉ thấy hệ thống chậm.

### Bước A2 — Đo BASELINE: `@02_workload.sql 100000` (~30 giây)

🤔 **Dự đoán:** vòng lặp 100k, ~2/3 số vòng SELECT 1 row qua index. Mỗi lần đọc row bình thường tốn ~3 logical reads (index root→leaf→table block). Row bị migrate tốn bao nhiêu?

```sql
@02_workload.sql 100000
```

**Output thật (đo trong VM 2026-07-14) — GHI 3 SỐ NÀY RA GIẤY:**

```text
CPU used by this session        81
session logical reads           231,748
table fetch continued row       30,637   ← BẰNG CHỨNG: 30,637 lần phải đọc THÊM block vì row đã "chuyển nhà"
```

> Vì sao 30,637 mà không phải 61,267? Vòng lặp chỉ đụng customer_no 1..100000 (~66,666 queries), 1/3 trong đó là rows migrate ≈ 30.6k. Bảng có 200k rows → tổng 61k rows migrate.

### Bước A3 — Chẩn đoán: `@03_diagnose.sql` (~1 phút)

🤔 **Dự đoán:** `DBMS_STATS.GATHER_TABLE_STATS` (cách gather chuẩn) có đếm được số row migrate không?

```sql
@03_diagnose.sql
```

**Đọc output theo 4 bước của script:**

| Bước | Kết quả thật | Bài học |
|---|---|---|
| 1. DBMS_STATS | `CHAIN_CNT = 0` | **"Số 0 giả"** — DBMS_STATS không đếm chain. Đừng bao giờ kết luận "không có migration" từ nó |
| 2. ANALYZE COMPUTE | `CHAIN_CNT = 61,267 (30.63%)` | Cách duy nhất lấy CHAIN_CNT. `AVG_ROW_LEN=431 << 8192` → là **MIGRATION** |
| 3. LIST CHAINED ROWS | 61,267 rows, **100% khớp** quy luật `MOD(customer_id,3)=0` | Chỉ được đích danh row nào bị — dùng khi cần sửa chọn lọc |
| 4. Gather lại DBMS_STATS | — | ANALYZE là lệnh deprecated cho optimizer stats → production phải trả stats chuẩn về ngay |

### Bước A4 — Sửa + đo lại: `@04_fix.sql 100000` (~1 phút)

🤔 **Dự đoán:** (1) Sau MOVE ONLINE, index còn dùng được không? (2) `table fetch continued row` sẽ về bao nhiêu? (3) BLOCKS của bảng tăng hay giảm?

```sql
@04_fix.sql 100000
```

**Output thật — so với 3 số đã ghi ở A2:**

| Chỉ số | A2 (trước fix) | A4 (sau fix) | Ý nghĩa |
|---|---|---|---|
| `table fetch continued row` | 30,637 | **biến mất (= 0)** | Hết migration — bằng chứng thép |
| `session logical reads` | 231,748 | 200,438 | Giảm ≈ đúng số continued row |
| `CPU used by this session` | 81 | 76 | Đỡ công đi theo con trỏ |
| Index status | — | **VALID** (không cần rebuild) | `MOVE ONLINE` (12.2+) tự maintain index — khác `MOVE` thường |
| BLOCKS | 13,036 | 15,442 (**+18%**) | Giá phải trả của PCTFREE 20 — trade-off, không có bữa trưa miễn phí |

---

## 3. PHẦN B — Mở rộng: Row Chaining thật + block 32K (user SYS, ~15 phút)

⚠️ Phần này đổi user: thoát sqlplus (`exit`), vẫn ở shell oracle:

```bash
cd /labs/section_28      # nếu đã rời đi
sqlplus / as sysdba      # trong VM: vào thẳng CDB root, không cần password
```

🤔 **Dự đoán:** row ~8,100 bytes (2 cột VARCHAR2(4000) đầy) trên block 8K → CHAIN_PCT bao nhiêu? Đọc cột `FIRST_NAME` (đầu row) có bị phạt không?

```sql
@05_row_chaining_32k.sql
```

**Các mốc output thật cần đối chiếu:**

1. **BUOC 0:** phải thấy `CON_NAME = CDB$ROOT` rồi `System altered` — nếu chạy từ trong PDB sẽ dính `ORA-65040` (bài học CDB: `DB_32K_CACHE_SIZE` là tham số instance-level)
2. **BUOC 1:** `CHAIN_CNT = 10,000 / CHAIN_PCT = 100%` — mọi row đều chained ngay từ INSERT (~45s)
3. **BUOC 3 (baseline 8K, đọc NOTE2):** `table fetch continued row = 6,667` = **100% số query** — vì NOTE2 nằm ở piece sau, Oracle buộc đi theo chain.
   💡 **Điểm internals đắt giá:** đổi query sang đọc `FIRST_NAME` thì continued row = **0** — piece đầu đã có đủ dữ liệu. Penalty của chaining phụ thuộc **CỘT NÀO được đọc**!
4. **BUOC 4:** move sang TBS32K → `CHAIN_CNT = 0`, BLOCKS từ 20,048 → **3,374**. Chú ý ở đây dùng `MOVE` thường → phải `REBUILD` index tay (so với MOVE ONLINE ở Phần A)
5. **BUOC 5 (đo lại):** continued row = 0, logical reads 26,897 → 20,233. **Nhưng DB time TĂNG** (115 vs 26) vì cold cache pool 32K (`db file sequential read` ~0.8s, physical reads 3,323) — muốn so CPU công bằng phải chạy warm lần 2. Bài học: đọc số đo phải hiểu bối cảnh cache!

---

## 4. Dọn dẹp (BẮT BUỘC — 2 phút)

Vẫn trong `sqlplus / as sysdba`:

```sql
@99_cleanup.sql
```

**Kỳ vọng:** các dòng `OK`/`SKIP` (SKIP với ORA-00942 là bình thường — object không tồn tại), rồi **3 query xác nhận đều `no rows selected`** → DB sạch như trước lab.

Thoát và tắt máy cuối buổi:

```sql
exit
```

```bash
exit    # thoát user oracle
exit    # thoát SSH
```

```powershell
vagrant halt    # PowerShell trên host
```

---

## 5. Debrief — tự trả lời KHÔNG nhìn tài liệu (20 phút)

Trả lời xong mới cuộn xuống đáp án. Đây là phần quyết định kiến thức có "dính" hay không.

1. `CHAIN_CNT` do lệnh nào tạo ra? Vì sao sau đó phải gather lại bằng `DBMS_STATS`?
2. Nhìn `AVG_ROW_LEN = 431` với block 8K — migration hay chaining? Nếu là 8,101 thì sao? Cách sửa khác nhau thế nào?
3. Vì sao chỉ `ALTER TABLE ... PCTFREE 20` mà không `MOVE` thì bệnh vẫn còn nguyên?
4. `MOVE` vs `MOVE ONLINE` vs `DBMS_REDEFINITION` — chọn gì cho bảng 24x7? Trade-off của từng cách?
5. Thống kê nào trong V$MYSTAT là bằng chứng trực tiếp của migration/chaining? Vì sao đo baseline ở Phần B, chỉ đổi cột SELECT mà con số thay đổi từ 6,667 về 0?

<details>
<summary>📖 Đáp án (bấm mở sau khi tự trả lời)</summary>

1. `ANALYZE TABLE ... COMPUTE STATISTICS` — DBMS_STATS không đếm CHAIN_CNT (trả "số 0 giả"). ANALYZE ghi optimizer stats theo cơ chế cũ kém chính xác (deprecated) → phải `DBMS_STATS.GATHER_TABLE_STATS` lại ngay để optimizer không dùng stats cũ.
2. 431 << 8192 → **migration** (row vừa block, bị chuyển nhà do UPDATE phình) → sửa bằng PCTFREE + MOVE. 8,101 ≈ block → **chaining** (row không bao giờ vừa) → PCTFREE vô dụng, phải block lớn hơn hoặc tách cột to (NOTE/LOB) ra bảng phụ — tách bảng là lựa chọn production phổ biến hơn 32K tablespace.
3. PCTFREE chỉ áp dụng cho **block ghi mới**. Rows đã migrate vẫn nằm nguyên chỗ cũ với con trỏ. Phải MOVE (rewrite toàn bộ rows) thì fix mới có hiệu lực; PCTFREE 20 để chống tái phát.
4. `MOVE`: nhanh nhất nhưng lock bảng + index UNUSABLE (phải rebuild) → cần downtime. `MOVE ONLINE` (12.2+): DML chạy song song, index tự maintain → lựa chọn mặc định cho 19c. `DBMS_REDEFINITION`: bảng cực lớn 24x7 cần kiểm soát từng giai đoạn (có thể sync dần, rollback được) — chậm nhất, tốn gấp đôi dung lượng (bảng interim), bước swap cuối vẫn chờ transaction chưa đóng.
5. `table fetch continued row` — đếm số lần fetch phải đọc piece/block tiếp theo. Ở Phần B: chained row bị cắt từ CUỐI row; piece đầu chứa CUSTOMER_NO/FIRST_NAME/LAST_NAME. Đọc FIRST_NAME → đủ ở piece đầu → không đi theo chain → 0. Đọc NOTE2 (cột cuối) → buộc đọc piece sau → 6,667 (mỗi query 1 lần). Hệ quả production: bảng có cột "to" ít dùng nên đặt CUỐI bảng, và tránh `SELECT *`.

</details>

---

## 6. Sự cố thường gặp

| Triệu chứng | Nguyên nhân → Xử lý |
|---|---|
| `SP2-0310: unable to open file "../_toolkit/..."` | Không đứng ở `/labs/section_28` → `cd /labs/section_28` rồi vào lại sqlplus |
| `ORA-00942` khi before_after chụp waits | soe thiếu grant (mất sau restore snapshot) → bằng SYS: `GRANT SELECT ON sys.v_$session_event TO soe;` |
| `ORA-65040` ở BUOC 0 (05) | Đang connect vào PDB → phải `sqlplus / as sysdba` (vào CDB root) |
| `ORA-00384` khi set cache 32K | SGA không đủ → sửa 96M thành 64M trong `05_row_chaining_32k.sql` |
| Số đo lệch vài % so với hướng dẫn | Bình thường (cache, nền). Chỉ cần ĐÚNG XU HƯỚNG: continued row về 0, logical reads giảm |
| sqlplus: command not found | Thiếu `-i` khi sudo → `sudo -u oracle -i` |

---

## 7. Sau buổi học

- [ ] Báo Claude "chốt buổi" → cập nhật `progress.md` + memory
- [ ] `vagrant halt`
- [ ] Buổi kế tiếp: Senior Guide Section 28 (đào sâu internals + tình huống production) rồi sang Section 29


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/labs/section_28/HUONG_DAN_HOC_SECTION_28.md`
