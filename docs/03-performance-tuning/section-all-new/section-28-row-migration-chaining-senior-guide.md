---
title: Row Migration & Row Chaining — Deep Dive for Senior DBA
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/section_all_new/section_28_row_migration_chaining_senior_guide.md
---

# Row Migration & Row Chaining — Deep Dive for Senior DBA

> **Section 28** · Nguồn: Practice 30 (Ahmed Baraka) + `section_all/section_28_row_migration_chaining_guide.md`
> **Điểm khác các guide trước:** mọi con số trong bài này là **số đo thật** từ lab `labs/section_28/` chạy trên VM srv1 (Oracle 19.3, 2026-07-14) — không phải số minh họa. Tự tái tạo: [labs/section_28/HUONG_DAN_HOC_SECTION_28.md](../labs/section-28/huong-dan-hoc-section-28.md)

---

# OUTPUT 1 — LECTURE NOTES

## 1. Mental Model

Migration và chaining là **nợ storage phát sinh lúc ghi, trả lãi ở mọi lần đọc**. Một quyết định sai ở write-path (PCTFREE không khớp update pattern, schema để cột "béo" nullable rồi fill sau) chuyển thành thuế cố định trên read-path: +1 buffer get cho mỗi lần fetch qua index. Frame đúng của senior: đây không phải "table bị phân mảnh, cần rebuild" mà là **mismatch giữa row lifecycle và block layout** — rebuild chỉ xóa nợ hiện có, không sửa nguyên nhân vay. Và quan trọng nhất: thuế này **chỉ đánh vào một số access path** — kết luận có cần trả nợ hay không phụ thuộc workload đọc bảng đó bằng đường nào.

## 2. Internals & Mechanics

**Migration:** khi UPDATE làm row vượt free space còn lại trong block, Oracle rewrite toàn bộ row sang block khác, để lại ở vị trí cũ một **head piece stub** chứa forwarding rowid (nrid — next rowid). Index entries vẫn trỏ rowid cũ nên **không index nào bị invalidate** — cái giá là mỗi `TABLE ACCESS BY INDEX ROWID` chạm stub rồi phải theo nrid đọc block thứ hai, tăng thống kê `table fetch continued row` lên 1. Số thật từ lab: 66,666 queries trên bảng có 30.63% rows migrate → 30,637 continued fetch, logical reads 231,748 so với 200,438 sau khi fix — **thuế ~15% buffer gets** cho đúng workload đó.

**Chaining:** row lớn hơn free space của một block ngay từ INSERT → Oracle cắt row thành nhiều piece nối bằng nrid, **cắt từ cuối row**. Hệ quả ít người để ý (đo được trong lab): head piece chứa các cột đầu, nên `SELECT first_name` trên bảng chained 100% cho `table fetch continued row = 0` — trong khi `SELECT length(note2)` (cột cuối) cho đúng 6,667/6,667 queries phải theo chain. **Penalty của chaining phụ thuộc cột nào được đọc**, đó là lý do `SELECT *` và các cột LOB-ish đặt đầu bảng là thiết kế tồi, còn "bảng chained nặng" đôi khi vô hại nếu app chỉ đụng cột đầu.

**Đo lường:** `CHAIN_CNT` trong `USER_TABLES` chỉ được populate bởi `ANALYZE TABLE ... COMPUTE STATISTICS` — `DBMS_STATS` cố tình không tính (phải đọc từng row piece, quá đắt cho auto stats job) và trả về **số 0 giả**. `CHAIN_CNT` gộp chung migration + chaining; phân loại bằng `AVG_ROW_LEN` so với block size (431 << 8192 → migration; 8,101 ≈ block → chaining). Bảng >255 cột còn có intra-block chaining tính riêng vào cùng counter `[⚠️ verify with MOS 746778.1]`.

## 3. Production Realities

- **Full table scan gần như miễn nhiễm với migration**: FTS đọc mọi block theo extent map và bỏ qua head stub (row đầy đủ nằm ở block sẽ được đọc sau). Nếu bảng chỉ bị đọc bằng FTS/smart scan, CHAIN_PCT 30% có thể **không đáng một lần rebuild**. Migration phạt index access path; chaining phạt cả hai khi cần cột ở piece sau.
- **ANALYZE là con dao hai lưỡi**: nó ghi đè optimizer statistics theo cơ chế cũ (deprecated từ 10g). Quy trình bắt buộc: `ANALYZE` lấy CHAIN_CNT → đọc số → `DBMS_STATS.GATHER_TABLE_STATS` ngay để trả stats chuẩn. Quên bước sau, plan có thể đổi âm thầm sau nửa đêm.
- **CDB đổi luật chơi với multi-blocksize**: `DB_32K_CACHE_SIZE` là tham số instance-level — set từ trong PDB dính `ORA-65040` (đo thật trên 19.3). Cache 32K nằm **ngoài vòng auto-tune của SGA_TARGET**, DBA tự chịu trách nhiệm size nó vĩnh viễn.
- **Bẫy đo lường sau fix**: lần chạy đầu sau MOVE là cold cache — lab đo được DB time **tăng** từ 26cs lên 115cs dù logical reads giảm 25%, do 3,323 physical reads vào pool 32K rỗng (`db file sequential read` 0.8s). Ai so sánh trước/sau bằng đúng một lần chạy sẽ kết luận ngược.
- **MOVE thường vs MOVE ONLINE (12.2+)**: MOVE thường để index UNUSABLE — trên hệ 24x7, một index unusable vài phút là incident. MOVE ONLINE maintain index tự động (lab: cả 2 index VALID ngay), đổi lại chậm hơn và cần journal space. `DBMS_REDEFINITION.REDEF_TABLE` sống chung với DML nhưng bước swap cuối **chờ mọi transaction chưa đóng** — job batch treo commit sẽ giữ redefinition treo theo.

## 4. Decision Framework

| Tình huống | Lựa chọn | Trade-off |
|---|---|---|
| Migration, có maintenance window | `MOVE` (+ rebuild index) | Nhanh nhất; lock + index UNUSABLE |
| Migration, 24x7, 12.2+ | `PCTFREE` mới + `MOVE ONLINE` | DML sống, index VALID; chậm hơn, cần ~2× space tạm |
| Migration, 24x7, cần kiểm soát/rollback từng bước | `DBMS_REDEFINITION` (multi-step) | Sync dần được, abort được; chậm nhất, tốn space nhất |
| Chaining do vài cột lớn ít dùng | **Tách cột sang bảng phụ / LOB** (thiết kế lại) | Sửa gốc; cần đổi app |
| Chaining, không sửa được schema | Tablespace 32K + `DB_32K_CACHE_SIZE` | Giải pháp ngách: cache tự quản, backup/clone phức tạp thêm |

**Ngưỡng hành động** (kinh nghiệm, không phải luật): CHAIN_PCT > 10% **và** bảng nóng trên index access path **và** `table fetch continued row` chiếm tỷ trọng đáng kể so với `table fetch by rowid` (lab: 30,637/66,854 ≈ 46% — đáng fix; < 5% thì để yên). **Anti-patterns:** rebuild định kỳ theo lịch "cho sạch" mà không đo; đuổi CHAIN_CNT về 0 trên bảng chỉ bị FTS; set PCTFREE 40 đại trà (blocks +18% ngay ở PCTFREE 20 trong lab — space và buffer cache đều trả giá); dùng ANALYZE làm nguồn optimizer stats.

## 5. Key SQL / Commands

```sql
-- 1. Lấy CHAIN_CNT (nhớ: DBMS_STATS trả "số 0 giả")
ANALYZE TABLE cust COMPUTE STATISTICS;
SELECT chain_cnt, ROUND(chain_cnt/NULLIF(num_rows,0)*100,2) chain_pct,
       avg_row_len,              -- << block size = migration; ~>= block = chaining
       pct_free, blocks
FROM   user_tables WHERE table_name = 'CUST';
EXEC DBMS_STATS.GATHER_TABLE_STATS(USER,'CUST')  -- BẮT BUỘC trả stats chuẩn ngay

-- 2. Đích danh row nào (layout chuẩn utlchain.sql)
ANALYZE TABLE cust LIST CHAINED ROWS INTO chained_rows;
SELECT head_rowid FROM chained_rows;   -- join về bảng gốc để tìm pattern cột/thời gian

-- 3. Thuế đang trả ở mức instance (trend theo AWR)
SELECT sn.snap_id, ss.value
FROM   dba_hist_sysstat ss JOIN dba_hist_snapshot sn USING (snap_id, dbid, instance_number)
WHERE  ss.stat_name = 'table fetch continued row'
ORDER  BY sn.snap_id;                  -- delta giữa các snap; spike sau batch = nghi phạm

-- 4. Đo trước/sau ở mức session (cùng 1 session!)
@labs/_toolkit/before_after.sql BEGIN
-- ... workload ...
@labs/_toolkit/before_after.sql END    -- nhìn cặp: continued row / table fetch by rowid

-- 5. Fix chuẩn 19c cho migration
ALTER TABLE cust PCTFREE 20;
ALTER TABLE cust MOVE ONLINE;          -- 12.2+: index tự VALID, DML không bị chặn
SELECT index_name, status FROM user_indexes WHERE table_name='CUST';  -- verify
```

## 6. Senior Checklist

- [ ] Phân loại trước khi fix: `AVG_ROW_LEN` vs block size — migration hay chaining? Fix khác nhau hoàn toàn.
- [ ] Xác định access path thật của bảng (ASH/plan): bảng chỉ bị FTS thì CHAIN_PCT cao chưa chắc đáng fix.
- [ ] Đo baseline bằng `table fetch continued row` **của workload thật** trước khi rebuild — và đo lại warm cache sau fix.
- [ ] Sau mọi `ANALYZE`: gather lại `DBMS_STATS` ngay. Không có ngoại lệ trong production.
- [ ] Fix migration phải đủ cặp: PCTFREE mới (chống tái phát) **+** MOVE (xóa nợ cũ) — thiếu một nửa là công cốc.
- [ ] Trước MOVE ONLINE/REDEF trên bảng lớn: kiểm tra space tạm (~2× segment) và transaction dài đang mở (`v$transaction`).
- [ ] Chaining tái diễn → đặt câu hỏi schema (tách cột lớn, thứ tự cột) trước khi nghĩ đến 32K tablespace; nếu vẫn 32K: nhớ cache nằm ngoài SGA auto-tune và chỉ chỉnh được ở CDB root.

---

# OUTPUT 2 — LAB EXERCISES

# Lab: Row Migration & Chaining — Hands-on for Senior DBA

## Lab Overview

- **Mục tiêu:** định lượng thuế migration/chaining trên workload thật và ra quyết định fix có căn cứ số liệu
- **Môi trường:** Oracle 19c CDB (VM srv1, PDB ORADB, SOE schema) — dùng `labs/section_28/` có sẵn
- **Thời gian ước tính:** 75–90 phút
- **Độ khó:** Senior / Expert

---

## Exercise 1 — Định lượng thuế migration và ra ngưỡng hành động

### Scenario

Team storage than phiền bảng khách hàng "phân mảnh 30%" và đề xuất rebuild toàn bộ trong weekend maintenance. Trước khi ký, bạn cần trả lời: 30% đó **tốn bao nhiêu thật** trên workload hiện tại, và ngưỡng nào thì rebuild mới bõ công?

### Tasks

1. Tạo hiện trường bằng `@01_setup.sql` + đo baseline `@02_workload.sql 100000` (user soe, trong VM qua `/labs/section_28`).
2. Từ output before/after, tính: tỷ lệ `table fetch continued row` / `table fetch by rowid`, và % logical reads dôi ra do migration.
3. Chạy `@03_diagnose.sql`, đối chiếu CHAIN_PCT (bảng-level) với tỷ lệ ở task 2 (workload-level). Hai con số này đo hai thứ khác nhau — thứ gì?
4. Đổi vòng lặp trong `02_workload.sql` sang truy cập `WHERE customer_no > N` bằng full scan (hint `FULL`) và đo lại. Migration còn tính thuế không?

### Expected Findings

Tỷ lệ workload-level (~46%) cao hơn CHAIN_PCT (30.63%) vì phân bố truy cập ≠ phân bố migrate; FTS cho continued row ≈ 0 — bằng chứng "CHAIN_PCT cao" một mình chưa đủ để rebuild.

### Debrief Questions

- Nếu bảng này 500 GB và chỉ được đọc bởi báo cáo batch FTS ban đêm, bạn ký lệnh rebuild không? Chi phí cơ hội là gì?
- Tại sao Oracle chọn để lại forwarding stub thay vì update mọi index entry khi row migrate? Trade-off nằm ở đâu?

---

## Exercise 2 — Chọn phương pháp rebuild dưới ràng buộc DML liên tục

### Scenario

Bảng cần fix migration nhưng có job upsert chạy 24x7, SLA không cho phép lock quá 5 giây. Bạn phải chọn giữa `MOVE`, `MOVE ONLINE` và `DBMS_REDEFINITION` — và chứng minh lựa chọn bằng thí nghiệm chứ không bằng niềm tin.

### Tasks

1. Tái tạo migration (`@01_setup.sql`). Mở session soe thứ hai chạy vòng lặp UPDATE vô hạn (code trong comment cuối `04_fix.sql` — dùng `DBMS_SESSION.SLEEP`).
2. Trong session một: thử `ALTER TABLE cust MOVE;` (không ONLINE). Quan sát nó chờ gì (`v$session.event` của cả hai session) và index status sau đó.
3. Thử `MOVE ONLINE` rồi `DBMS_REDEFINITION.REDEF_TABLE` trong cùng điều kiện; bấm giờ từng cách; để một transaction **không commit** trong session hai và quan sát bước swap của redefinition.
4. Lập bảng: thời gian / hành vi lock / trạng thái index / space tạm của 3 phương pháp.

### Expected Findings

MOVE thường chờ được lock rồi khóa DML + index UNUSABLE; MOVE ONLINE nhanh hơn REDEF đáng kể và index VALID; REDEF treo ở swap khi còn transaction mở — điểm chết ít người test trước.

### Debrief Questions

- Transaction "treo commit" của một job batch lỗi sẽ làm gì với cửa sổ maintenance của bạn ở từng phương pháp?
- Với bảng có FK con (CUST_ORDERS trong lab), REDEF_TABLE một-lệnh xử lý dependent objects thế nào — và khi nào bạn buộc phải dùng multi-step API? `[⚠️ verify with MOS]`

---

## Exercise 3 — Troubleshooting Scenario *(Expert level)*

### Incident Brief

Ứng dụng OLTP báo latency màn hình khách hàng tăng ~15% từ hai tuần nay, tệ dần theo ngày. Không có deploy code. Team hạ tầng nói "storage vẫn 8ms như cũ". Một DBA junior đã chạy ANALYZE trên bảng nghi vấn tối qua "để lấy số liệu" và sáng nay có thêm báo cáo chậm bất thường ở module khác. Đồng nghiệp đề xuất chuyển bảng sang tablespace 32K "cho triệt để".

### Evidence Provided

```text
AWR (delta 7 ngày trước vs hiện tại, giờ cao điểm):
  table fetch by rowid          41.2M  ->  43.1M   (+4.6%)
  table fetch continued row      1.1M  ->   9.8M   (+790%)
  session logical reads          312M  ->  361M    (+15.7%)
  db file sequential read avg          8.1ms -> 8.3ms

Top SQL by gets: sql_id 7xk...  SELECT ... FROM customer_profile WHERE cust_no = :b1
  buffer gets/exec: 4.1 -> 5.9        plan_hash: KHÔNG ĐỔI

Segment stats: CUSTOMER_PROFILE — physical reads tăng nhẹ, logical reads +18%
USER_TABLES (sáng nay): CHAIN_CNT=88,412 (11.2%), AVG_ROW_LEN=612, BLOCK 8K, PCTFREE 10
Ghi chú vận hành: 3 tuần trước, job đêm mới bắt đầu ghi cột JSON_PREFS (VARCHAR2 900,
trước đây NULL) cho ~5% khách hàng mỗi đêm.
```

### Your Mission

Root cause analysis đầy đủ: (1) chuỗi nhân quả từ evidence — vì sao buffer gets/exec tăng mà plan không đổi; (2) giải thích sự cố **thứ hai** sáng nay (module báo cáo chậm) — thủ phạm có phải migration không; (3) remediation plan có thứ tự, ước lượng tác động, và rollback; (4) phản biện đề xuất 32K tablespace của đồng nghiệp bằng số liệu trong evidence.

### Evaluation Criteria

- Nhận ra AVG_ROW_LEN=612 << 8192 → migration (không phải chaining) → 32K là **sai thuốc** và phải nói được vì sao
- Truy được sự cố sáng nay về ANALYZE ghi đè optimizer stats (không phải migration) — hai incident, hai root cause
- Plan có đủ cặp PCTFREE + MOVE ONLINE, chọn được thời điểm theo job đêm, có bước đo lại warm-cache
- Chỉ ra được migration sẽ **tiếp tục phát sinh mỗi đêm** (~5%/đêm) nếu chỉ rebuild mà không tăng PCTFREE — nợ vay lại ngay hôm sau

---

## Self-check đã thực hiện

1. ✅ Có nội dung ngoài docs: số đo thật (thuế 15% buffer gets, 46% workload-level), penalty-theo-cột đo được, bẫy cold cache, ORA-65040 trên 19.3
2. ✅ Exercise 3 có 2 root cause chồng nhau (migration + ANALYZE) và một đề xuất sai (32K) để gây tranh luận
3. ✅ Claim chưa chắc: intra-block chaining >255 cột, REDEF với FK — đã gắn `[⚠️ verify with MOS]`
4. ✅ Tone peer-to-peer, không giải thích khái niệm cơ bản


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/section_all_new/section_28_row_migration_chaining_senior_guide.md`
