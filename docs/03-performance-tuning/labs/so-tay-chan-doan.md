---
title: SỔ TAY CHẨN ĐOÁN HIỆU NĂNG ORACLE — Tổng hợp toàn khóa học
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/labs/SO_TAY_CHAN_DOAN.md
---

# SỔ TAY CHẨN ĐOÁN HIỆU NĂNG ORACLE — Tổng hợp toàn khóa học

> Tổng hợp các câu SQL/lệnh chẩn đoán quan trọng nhất của khóa *Oracle Database Performance Tuning* (Ahmed Baraka), rút từ `labs/_toolkit/` + `labs/section_*/03_diagnose.sql`.
> Mỗi mục gồm: **code → ý nghĩa → cách đọc số → case cần xử lý**.
> 🗺️ Bản mô hình hóa bằng sơ đồ (16 mô hình tư duy): [SO_TAY_MO_HINH.md](so-tay-mo-hinh.md) — học sơ đồ trước, tra code sau.
>
> **Thứ tự tư duy chuẩn (LUÔN theo trình tự này):**
> `DB Time → Wait Event → SQL/Session → Root cause → Fix → Đo lại`
>
> Chạy từ host: `sqlplus system/oracle_4U@//localhost:15210/ORADB` (trong VM dùng port 1521).
> ⚠️ Số liệu V$ là **lũy kế từ startup** — muốn đo 1 khoảng thời gian phải lấy **delta** (AWR 2 snapshot, hoặc `_toolkit/before_after.sql` cho session).

---

## MỤC LỤC

| # | Nhóm | Trả lời câu hỏi |
|---|------|-----------------|
| 1 | [Time Model](#1-time-model--db-time-tiêu-vào-đâu-section-6) | DB Time tiêu vào đâu? |
| 2 | [Wait Events](#2-wait-events--đang-chờ-cái-gì-section-8) | Đang chờ cái gì? CPU hay wait? |
| 3 | [ASH](#3-ash--5-phút-qua-ai-bận-vì-cái-gì-section-13) | Ai/bận vì cái gì, vừa xảy ra? |
| 4 | [Top SQL](#4-top-sql--sql-nào-tốn-nhất) | SQL nào tốn nhất? |
| 5 | [AWR](#5-awr--đo-delta-giữa-2-thời-điểm-section-9) | Trước/sau khác nhau thế nào? Quá khứ ra sao? |
| 6 | [ADDM](#6-addm--để-oracle-tự-chẩn-đoán-section-12) | Oracle tự khuyên gì? |
| 7 | [Service/Module/Trace](#7-servicemoduleclient-id--sql-trace-section-14-15) | Tải đến từ ứng dụng nào? Từng bước SQL tốn gì? |
| 8 | [Real-time SQL Monitoring](#8-real-time-sql-monitoring-section-16) | Câu SQL dài hơi đang chạy tới đâu? |
| 9 | [Enqueue/Lock](#9-enqueuelock--ai-giữ-ai-chờ-section-19) | Ai giữ — ai chờ — đúng row nào? |
| 10 | [Latch & Mutex](#10-latch--mutex--bão-hard-parse-section-20) | Vì sao library cache nghẽn? |
| 11 | [Shared Pool](#11-shared-pool--session-cursors--result-cache-section-21) | Shared pool thiếu hay bệnh code? |
| 12 | [Buffer Cache](#12-buffer-cache--keep-pool-section-22) | Cache thiếu chỗ? Ai chiếm? |
| 13 | [PGA](#13-pga--sort-tràn-temp-section-23) | Sort/hash tràn temp không? |
| 14 | [Redo](#14-redo-path-section-24) | Ghi log có nghẽn không? |
| 15 | [CPU](#15-cpu-bottleneck-section-25) | CPU do DB hay do process ngoài? |
| 16 | [Disk I/O](#16-disk-io-section-26) | I/O bùng nổ từ đâu? |
| 17 | [Index](#17-index-defragmentation-section-27) | Index có bloat không? COALESCE hay REBUILD? |
| 18 | [Row Migration/Chaining](#18-row-migration--chaining-section-28) | Row bị chuyển nhà hay quá khổ? |
| 19 | [Table Fragmentation](#19-table-fragmentation--hwm-section-29) | Bảng rỗng ruột, HWM cao? |
| 20 | [Segment/Compression/In-Memory](#20-compression--in-memory-section-30-31) | Nén/IM có đáng không? |
| 21 | [Connection/Network](#21-connection--arraysize-section-32) | Round-trip mạng có phí không? |
| 22 | [Tầng OS](#22-tầng-os--cầu-spid-section-34) | Host bận vì ai? Nối OS ↔ DB thế nào? |
| 23 | [Bảng tra nhanh triệu chứng](#23-bảng-tra-nhanh-triệu-chứng--hướng-điều-tra) | Thấy X thì nghĩ đến gì? |

---

## 1. Time Model — DB Time tiêu vào đâu? (Section 6)

**Script toolkit:** `_toolkit/time_model.sql` — **bước 1 của mọi cuộc điều tra.**

```sql
SELECT stat_name,
       ROUND(value/1e6, 2) AS time_sec,
       ROUND(100 * value / NULLIF((SELECT value FROM v$sys_time_model
                                   WHERE stat_name = 'DB time'), 0), 1) AS pct_db_time
FROM   v$sys_time_model
WHERE  stat_name NOT LIKE 'background%'
AND    value > 0
ORDER  BY value DESC;
```

**Ý nghĩa:** `DB time` = tổng thời gian foreground sessions làm việc (CPU + non-idle wait). Các thành phần con **lồng nhau, không cộng tuyến tính** (parse nằm trong sql execute) — % > 100% với `sql execute elapsed time` là bình thường. Mức session: `V$SESS_TIME_MODEL`.

**Case cần xử lý:**

| Thấy gì | Nghĩ đến | Đi tiếp |
|---|---|---|
| `DB CPU` ≈ `DB time` (ít wait) | Bottleneck CPU / SQL ngốn CPU | §15 (Section 25) + `top_sql.sql CPU` |
| `hard parse elapsed time` cao | Literal SQL, shared pool | §10, §11 (Section 20–21) |
| `PL/SQL execution elapsed time` cao | Code PL/SQL, không phải SQL | Tune logic PL/SQL |
| `DB time` >> `DB CPU` | Phần lớn thời gian là WAIT | §2 `top_waits.sql` |
| `parse time elapsed` >> `hard parse` | Soft parse quá nhiều | Session cursor cache (§11) |

---

## 2. Wait Events — đang chờ cái gì? (Section 8)

**Script toolkit:** `_toolkit/top_waits.sql` — **bước 2.**

```sql
-- Top 15 wait event toàn instance (lũy kế), kèm % và avg ms
SELECT * FROM (
  SELECT event, wait_class, total_waits,
         ROUND(time_waited_micro/1e6, 1)                          AS time_sec,
         ROUND(time_waited_micro/1000/NULLIF(total_waits,0), 2)   AS avg_ms,
         ROUND(100 * ratio_to_report(time_waited_micro) OVER (), 1) AS pct
  FROM   v$system_event
  WHERE  wait_class <> 'Idle'
  ORDER  BY time_waited_micro DESC
) WHERE ROWNUM <= 15;

-- Đối chiếu với DB CPU: wait to hay CPU to?
SELECT stat_name, ROUND(value/1e6, 1) AS time_sec
FROM   v$sys_time_model
WHERE  stat_name IN ('DB time', 'DB CPU');

-- Session ĐANG chờ ngay lúc này (real-time)
SELECT sid, username, event, sql_id, ROUND(wait_time_micro/1e6) AS wait_s
FROM   v$session
WHERE  wait_class <> 'Idle' AND state = 'WAITING' AND type = 'USER'
ORDER  BY wait_time_micro DESC;
```

**Ý nghĩa:** luôn so tổng wait với `DB CPU` — nếu CPU lớn hơn nhiều thì bottleneck là CPU/SQL chứ **không phải** wait. Mức session dùng `V$SESSION_EVENT`; tham số wait đang diễn ra: `V$SESSION` (`p1/p2/p3`, `p1text…`).

**Bản đồ wait event → chuyên đề:**

| Wait event | Root cause thường gặp | Mục |
|---|---|---|
| `db file sequential read` | Đọc đơn block (index/row-by-row); cache thiếu; row migration | §12, §18 |
| `db file scattered read` | Full table scan multiblock; index UNUSABLE; HWM cao | §16, §19 |
| `enq: TX - row lock contention` | Tranh chấp row lock ứng dụng | §9 |
| `enq: TM - contention` | FK không index / lock DDL / direct-path APPEND | §7 (case ETL) |
| `library cache: mutex X` | Bão hard parse (literal SQL) | §10 |
| `latch: cache buffers chains` | Hot block, SQL đọc lặp block nóng | §10 (05_cbc_pin) |
| `log file sync` | Commit quá dày / LGWR chậm | §14 |
| `direct path read/write temp` | Sort/hash tràn PGA xuống temp | §13 |
| `free buffer waits` / `buffer busy waits` | DBWR không kịp / hot block | §12 |
| `SQL*Net message from client` (Idle) | Không phải bệnh DB — chờ app; nhưng round-trip dày → §21 |

---

## 3. ASH — 5 phút qua ai bận vì cái gì? (Section 13)

**Script toolkit:** `_toolkit/ash_now.sql` — **bước 3.** ⚠️ Cần Diagnostic Pack.

```sql
-- Nhóm hoạt động 5 phút gần nhất theo event + SQL
SELECT * FROM (
  SELECT NVL(event, 'ON CPU') AS activity, sql_id, COUNT(*) AS samples,
         ROUND(100 * ratio_to_report(COUNT(*)) OVER (), 1) AS pct
  FROM   v$active_session_history
  WHERE  sample_time > SYSTIMESTAMP - INTERVAL '5' MINUTE
  GROUP  BY NVL(event, 'ON CPU'), sql_id
  ORDER  BY COUNT(*) DESC
) WHERE ROWNUM <= 15;
```

**Ý nghĩa:** mỗi sample ≈ 1 giây active của 1 session → `SAMPLES ≈ số giây DB time`. `ON CPU` = đang chạy CPU, không phải wait. ASH là **sampling** — tìm thủ phạm chính thì tốt, đếm chính xác số lần thực thi thì KHÔNG.

**Truy vết hậu kỳ tới ĐÚNG ROW bị tranh chấp (dimension views — lock đã chết vẫn tra được):**

```sql
-- Với enq: TX trong quá khứ: ASH lưu blocking_session + current_obj#/file#/block#/row#
SELECT h.sample_time, h.session_id waiter, h.blocking_session holder,
       o.object_name, h.current_obj#, h.current_file#, h.current_block#, h.current_row#,
       DBMS_ROWID.ROWID_CREATE(1, h.current_obj#, h.current_file#,
                               h.current_block#, h.current_row#) AS row_id
FROM   v$active_session_history h JOIN dba_objects o ON o.object_id = h.current_obj#
WHERE  h.event = 'enq: TX - row lock contention';
```

**Case cần xử lý:**
- Sự cố **vừa xảy ra xong** (đã hết) → ASH là công cụ duy nhất mức giây; xa hơn (~1h+) → `DBA_HIST_ACTIVE_SESS_HISTORY` (1/10 mẫu).
- Cần báo cáo đóng gói: `@?/rdbms/admin/ashrpt.sql` (chọn khung giờ chính xác đến phút).
- Không có dòng nào trả về = DB đang rảnh (không phải lỗi query).

---

## 4. Top SQL — SQL nào tốn nhất?

**Script toolkit:** `_toolkit/top_sql.sql &1` (`ELAPSED` | `CPU` | `GETS`).

```sql
SELECT * FROM (
  SELECT sql_id, executions AS execs,
         ROUND(elapsed_time/1e6, 2)                      AS elapsed_s,
         ROUND(elapsed_time/1e6/NULLIF(executions,0), 4) AS ela_per_exec,
         ROUND(cpu_time/1e6, 2)                          AS cpu_s,
         buffer_gets, disk_reads,
         REPLACE(SUBSTR(sql_text, 1, 55), CHR(10), ' ')  AS sql_text
  FROM   v$sql
  WHERE  parsing_schema_name NOT IN ('SYS')
  ORDER  BY elapsed_time DESC        -- hoặc cpu_time / buffer_gets
) WHERE ROWNUM <= 10;

-- Xem plan thật đang dùng của 1 SQL:
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR('&sql_id', NULL, 'ALLSTATS LAST'));
```

**Cách đọc — 3 điểm sống còn:**
1. **`ELA_PER_EXEC` quan trọng hơn tổng**: SQL 60s chạy 1 lần ≠ SQL 1ms chạy 60k lần — cách fix hoàn toàn khác (tune plan vs giảm số lần gọi/round-trip).
2. `BUFFER_GETS/exec` cao bất thường trên bảng nhỏ → row migration (§18), index bloat (§17), plan sai.
3. `V$SQL` chỉ chứa SQL **còn trong shared pool** — SQL bị age-out phải tìm trong AWR (`DBA_HIST_SQLSTAT`, §5).

---

## 5. AWR — đo delta giữa 2 thời điểm (Section 9)

**Script toolkit:** `_toolkit/awr_snap.sql` (chụp snapshot trước/sau workload).

```sql
-- Chụp snapshot thủ công (trước và sau workload)
EXEC DBMS_WORKLOAD_REPOSITORY.CREATE_SNAPSHOT;

-- Xem snapshot + cấu hình lưu trữ
SELECT snap_id, begin_interval_time FROM dba_hist_snapshot ORDER BY snap_id;
SELECT snap_interval, retention FROM dba_hist_wr_control;

-- Đổi interval/retention (phút): 30' / 30 ngày
EXEC DBMS_WORKLOAD_REPOSITORY.MODIFY_SNAPSHOT_SETTINGS(interval=>30, retention=>43200);

-- Sinh report / SQL report / so sánh 2 cửa sổ (chạy trong sqlplus):
-- @?/rdbms/admin/awrrpt.sql      -- report đầy đủ giữa 2 snapshot
-- @?/rdbms/admin/awrsqrpt.sql    -- report cho MỘT sql_id
-- @?/rdbms/admin/awrddrpt.sql    -- diff 2 cặp snapshot (trước/sau thay đổi)

-- Baseline: giữ cặp snapshot khỏi bị purge, làm mốc so sánh
EXEC DBMS_WORKLOAD_REPOSITORY.CREATE_BASELINE(start_snap_id=>&s, end_snap_id=>&e, baseline_name=>'golden_period');
```

**Săn plan regression trong lịch sử (use case 05 của lab 9):**

```sql
-- 1 sql_id có nhiều plan_hash_value, plan nào chậm hơn bao nhiêu?
SELECT sql_id, plan_hash_value,
       SUM(executions_delta) execs,
       ROUND(SUM(elapsed_time_delta)/1e6/NULLIF(SUM(executions_delta),0), 4) ela_per_exec
FROM   dba_hist_sqlstat
WHERE  sql_id = '&sql_id'
GROUP  BY sql_id, plan_hash_value
ORDER  BY ela_per_exec;
```

**Case cần xử lý:**
- "Hôm qua 2h sáng DB chậm" → không có ai online lúc đó: **AWR report giữa 2 snapshot bao khung giờ đó** + ASH history.
- "Sau khi deploy chậm hẳn" → `awrddrpt.sql` diff trước/sau, hoặc query `DBA_HIST_SQLSTAT` theo `plan_hash_value` như trên.
- Đo hiệu quả 1 lần fix trong lab → chụp snap B → workload → snap E → report B→E (mọi `04_fix.sql` dùng kỹ thuật này).
- ⚠️ AWR cần Diagnostic Pack; không license → Statspack (Section 11, cùng triết lý snapshot–delta, `spreport.sql`).

---

## 6. ADDM — để Oracle tự chẩn đoán (Section 12)

```sql
-- Chạy ADDM cho cặp snapshot (PDB dùng DBMS_ADDM, chế độ ANALYZE_INST)
VAR tname VARCHAR2(60)
EXEC :tname := 'lab_addm'; DBMS_ADDM.ANALYZE_INST(:tname, &begin_snap, &end_snap);
SELECT DBMS_ADDM.GET_REPORT(:tname) FROM dual;

-- Findings dạng bảng
SELECT finding_name, type, impact
FROM   dba_advisor_findings
WHERE  task_name = 'lab_addm'
ORDER  BY impact DESC;
```

**Ý nghĩa:** ADDM đọc AWR và xếp hạng finding theo **impact lên DB time** — đúng triết lý bước 1. Đọc từ finding impact cao nhất xuống; mỗi finding kèm recommendation (tune SQL / tăng memory / cách ly I/O…).

**Case:** dùng ADDM làm **ý kiến thứ hai** sau khi tự chẩn đoán bằng toolkit — nếu ADDM chỉ chỗ khác với kết luận của mình thì phải giải thích được vì sao. Đừng làm theo máy móc: ADDM đo trong lúc workload bất thường sẽ khuyên lệch (giống advisory §11, §12).

---

## 7. Service/Module/Client ID + SQL Trace (Section 14, 15)

**Gắn thẻ phiên (instrument) — điều kiện để chẩn đoán theo ứng dụng:**

```sql
EXEC DBMS_APPLICATION_INFO.SET_MODULE('BATCH_ETL', 'load_orders');
EXEC DBMS_SESSION.SET_IDENTIFIER('customer_123');

-- Bật thu thập thống kê theo module/action + xem
EXEC DBMS_MONITOR.SERV_MOD_ACT_STAT_ENABLE('ORADB', 'BATCH_ETL', 'load_orders');
SELECT aggregation_type, module, action, stat_name, value
FROM   v$serv_mod_act_stats WHERE value > 0;

-- Thống kê theo service (có sẵn, không cần bật)
SELECT service_name, stat_name, ROUND(value/1e6,1) sec
FROM   v$service_stats
WHERE  stat_name IN ('DB time','DB CPU') ORDER BY service_name, stat_name;
```

**SQL Trace bằng DBMS_MONITOR (Section 15) — khi cần mổ xẻ TỪNG bước:**

```sql
-- Trace theo session / theo module (kể cả connection pool nhiều session):
EXEC DBMS_MONITOR.SESSION_TRACE_ENABLE(&sid, &serial, waits=>TRUE, binds=>FALSE);
EXEC DBMS_MONITOR.SERV_MOD_ACT_TRACE_ENABLE('ORADB', 'BATCH_ETL');
-- ... tái hiện vấn đề ...
EXEC DBMS_MONITOR.SESSION_TRACE_DISABLE(&sid, &serial);

-- Trong VM: gộp file trace theo service/module rồi dịch ra báo cáo
-- trcsess output=etl.trc service=ORADB module=BATCH_ETL *.trc
-- tkprof etl.trc etl.txt sys=no sort=exeela
```

**Case cần xử lý:**
- "App X làm DB chậm" nhưng mọi session đều là pool chung → **chỉ tách được nếu app gắn module/action/client_id**; trace theo `SERV_MOD_ACT` thay vì SID.
- ETL chậm bất thường → case kinh điển lab 14: INSERT `/*+ APPEND */` giữ **lock TM exclusive cả bảng** → các job sau xếp hàng `enq: TM`; đối chiếu client_id trong ASH.
- Đọc tkprof: chú ý dòng tổng `elapsed` vs `cpu` chênh nhau = wait; mục `Misses in library cache` = hard parse; row source plan là plan **thật**.
- ⚠️ Trace ghi đĩa lớn — bật đúng phạm vi, nhớ DISABLE.

---

## 8. Real-time SQL Monitoring (Section 16)

⚠️ Cần Tuning Pack. Tự bật khi SQL chạy song song hoặc >5s CPU/IO.

```sql
-- Câu nào đang được monitor? Chạy tới đâu?
SELECT sql_id, status, username,
       ROUND(elapsed_time/1e6,1) ela_s, sql_text
FROM   v$sql_monitor ORDER BY sql_exec_start DESC FETCH FIRST 10 ROWS ONLY;

-- Report chi tiết 1 câu (plan sống: hàng nào đang chạy, actual rows từng bước)
SELECT DBMS_SQL_MONITOR.REPORT_SQL_MONITOR(sql_id => '&sql_id', type => 'TEXT') FROM dual;

-- Bọc cả nghiệp vụ nhiều câu SQL thành 1 DBOP để theo dõi chung:
VAR eid NUMBER
EXEC :eid := DBMS_SQL_MONITOR.BEGIN_OPERATION('nightly_batch', forced_tracking=>'Y');
-- ... chạy nghiệp vụ ...
EXEC DBMS_SQL_MONITOR.END_OPERATION('nightly_batch', :eid);
```

**Case:** batch/report **đang chạy** mãi không xong — thay vì kill mù, mở report monitor xem plan sống đang kẹt ở operation nào (HASH JOIN tràn temp? FTS bảng nào? actual rows lệch estimate ở đâu?). Đây là công cụ "đang xảy ra" tốt nhất cho SQL dài hơi.

---

## 9. Enqueue/Lock — ai giữ, ai chờ? (Section 19)

**Kỹ thuật V$LOCK kinh điển — holder và waiter cùng tranh MỘT tài nguyên:**

```sql
-- [1] Ai giữ — ai chờ (khi lock ĐANG sống)
SELECT DECODE(request, 0, 'Holder  SID: ', 'Waiter  SID: ') || sid AS sessions,
       id1, id2, lmode, request, type
FROM   v$lock
WHERE  (id1, id2, type) IN (SELECT id1, id2, type FROM v$lock WHERE request > 0)
ORDER  BY id1, request;
-- Holder: LMODE=6, REQUEST=0. Waiter: LMODE=0, REQUEST=6.
-- TYPE=TX: (ID1,ID2) là định danh TRANSACTION của holder — bạn chờ transaction, không phải chờ row.

-- [2] Waiter đang kẹt ở ĐÚNG ROW nào? (V$SESSION.ROW_WAIT_*)
SELECT 'SELECT * FROM "' || o.owner || '"."' || o.object_name ||
       '" WHERE ROWID = DBMS_ROWID.ROWID_CREATE(1, ' || s.row_wait_obj# || ', ' ||
       s.row_wait_file# || ', ' || s.row_wait_block# || ', ' || s.row_wait_row# || ');'
FROM   dba_objects o, v$session s
WHERE  s.row_wait_obj# = o.object_id AND s.sid = &waiter_sid;

-- [3] Cây blocking nhanh
SELECT sid, blocking_session, event, seconds_in_wait, sql_id
FROM   v$session WHERE blocking_session IS NOT NULL;
```

**Case cần xử lý:**
- Lock **đang sống** → V$LOCK + V$SESSION (như trên). Lock **đã chết** → ASH (`blocking_session`, `current_*` — §3).
- Chuỗi chờ dài (A chờ B chờ C) → lần theo `blocking_session` tới gốc; chỉ xử lý **gốc** (commit/rollback/kill), đừng kill waiter.
- `enq: TM - contention` hàng loạt → FK thiếu index trên bảng con, hoặc direct-path APPEND/DDL giữ TM X.
- Kill là biện pháp cuối: `ALTER SYSTEM KILL SESSION 'sid,serial#';` — luôn hỏi nghiệp vụ trước khi rollback transaction của người khác.

---

## 10. Latch & Mutex — bão hard parse (Section 20)

**Máy dò literal-SQL bằng FORCE_MATCHING_SIGNATURE:**

```sql
-- Cùng signature (chỉ khác literal) mà hàng nghìn cursor → thủ phạm số 1
SELECT * FROM (
  SELECT TO_CHAR(force_matching_signature) AS signature,
         SUBSTR(sql_text,1,44) AS sql_text, COUNT(*) AS matches
  FROM   v$sql
  WHERE  force_matching_signature <> 0 AND parsing_schema_name <> 'SYS'
  GROUP  BY TO_CHAR(force_matching_signature), SUBSTR(sql_text,1,44)
  HAVING COUNT(*) > 1
  ORDER  BY matches DESC
) WHERE ROWNUM <= 10;

-- Hard parse rate (delta 15 giây) — bình thường chỉ vài chục
COLUMN v_hp NEW_VALUE v_hp0 NOPRINT
SELECT value AS v_hp FROM v$sysstat WHERE name = 'parse count (hard)';
EXEC DBMS_SESSION.SLEEP(15)
SELECT value - &v_hp0 AS hard_parses_15s FROM v$sysstat WHERE name = 'parse count (hard)';

-- Thiệt hại phía shared pool
SELECT name, ROUND(bytes/1024/1024,1) AS mb
FROM   v$sgastat WHERE pool = 'shared pool' AND name IN ('free memory','SQLA');

-- Latch/mutex nào nóng?
SELECT * FROM (
  SELECT name, gets, misses, sleeps FROM v$latch ORDER BY sleeps DESC
) WHERE ROWNUM <= 10;
```

**Chuỗi nhân quả phải thuộc lòng:** literal → mỗi câu là cursor mới → hard parse liên tục → tranh `library cache: mutex X` + SQLA phình đuổi cursor tốt ra ngoài (nạn nhân gián tiếp: mọi ứng dụng khác).

**Case cần xử lý:**
- Fix thật = **sửa code dùng bind variable**; chữa cháy tạm = `CURSOR_SHARING=FORCE` (chấp nhận rủi ro plan vì mất giá trị literal cho histogram).
- `latch: cache buffers chains` (hot block) → tìm block nóng qua ASH `current_obj#` — fix hướng khác hẳn (giảm truy cập block nóng, không liên quan parse).
- Đừng tăng shared pool để chữa literal storm — xem §11.

---

## 11. Shared Pool + Session Cursors + Result Cache (Section 21)

```sql
-- Shared Pool Advisory: "nếu pool = X thì tiết kiệm được bao nhiêu thời gian parse"
SELECT shared_pool_size_for_estimate AS pool_mb,
       shared_pool_size_factor       AS size_factor,   -- 1.00 = hiện tại
       estd_lc_time_saved            AS est_time_saved_s,
       estd_lc_time_saved_factor     AS est_parse_saved_fctr
FROM   v$shared_pool_advice ORDER BY 1;

-- Library cache đang chứa gì
SELECT lc_namespace, lc_inuse_memory_objects, lc_inuse_memory_size
FROM   v$library_cache_memory ORDER BY lc_inuse_memory_objects DESC FETCH FIRST 5 ROWS ONLY;

-- Hiệu quả session cursor cache (soft parse rẻ hơn nữa = "softer parse")
SELECT n.name, s.value FROM v$sysstat s JOIN v$statname n ON n.statistic# = s.statistic#
WHERE  n.name IN ('session cursor cache hits','parse count (total)','parse count (hard)');

-- Result cache: có đáng dùng cho query nhỏ chạy dày trên bảng ít đổi?
SELECT DBMS_RESULT_CACHE.STATUS() FROM dual;
SELECT name, value FROM v$result_cache_statistics;  -- Create/Find Count = tỉ lệ tái dùng
```

**Cách đọc Advisory (nguyên tắc VÀNG của course):**
- Dòng `size_factor = 1.00` là hiện tại. Tăng size mà `est_time_saved` **tăng rõ** → pool đang thiếu thật; **gần như phẳng** → thêm RAM vô ích. Điểm "gãy khúc" của đường cong ≈ size tối ưu.
- ⚠️ **Chỉ tin advisory đo lúc hệ thống BÌNH THƯỜNG.** Đo trong bão literal → advisory xui mua RAM cho bệnh mà thuốc thật là sửa code (§10).

**Case:** `parse time elapsed` cao nhưng hard parse thấp → soft parse dày → tăng `SESSION_CACHED_CURSORS`. Query lookup nhỏ chạy nghìn lần/phút trên bảng tĩnh → `RESULT_CACHE` (hint hoặc table annotation) — nhưng bảng hay DML thì invalidation liên tục phản tác dụng.

---

## 12. Buffer Cache + KEEP Pool (Section 22)

```sql
-- [1] Hit % (cùng công thức mục Instance Efficiency của AWR)
SELECT name,
       ROUND(100 * (1 - physical_reads / NULLIF(db_block_gets + consistent_gets, 0)), 2) hit_pct
FROM   v$buffer_pool_statistics;

-- [2] Ai đang chiếm cache? (V$BH group theo object)
SELECT * FROM (
  SELECT o.object_name, COUNT(*) blocks, ROUND(COUNT(*) * 8 / 1024) mb
  FROM   v$bh bh JOIN dba_objects o ON o.data_object_id = bh.objd
  WHERE  bh.status != 'free'
  GROUP  BY o.object_name ORDER BY blocks DESC
) WHERE ROWNUM <= 10;

-- [3] Buffer Pool Advisory
SELECT ROUND(size_for_estimate) size_mb, size_factor,
       estd_physical_read_factor, estd_physical_reads
FROM   v$db_cache_advice
WHERE  name = 'DEFAULT' AND block_size = 8192
ORDER  BY size_for_estimate;

-- [4] Cách ly bảng nóng nhỏ vào KEEP pool
-- ALTER SYSTEM SET DB_KEEP_CACHE_SIZE = 64M;
-- ALTER TABLE soe.hot_table STORAGE (BUFFER_POOL KEEP);
```

**Cách đọc:** OLTP hit% thường ~95%+ nhưng **hit% cao không chứng minh khỏe** (SQL tồi đọc logical nhiều vẫn đẩy hit% lên). Advisory: điểm "gãy khúc" của `estd_physical_read_factor` = size đáng cân nhắc. **2 cảnh báo của course:** (a) advisory chỉ chiếu tối đa ~200% size hiện tại — lợi ích nằm xa hơn 2x nó không nói; (b) đo lúc workload bất thường thì khuyến nghị bị nhiễm.

**Case:** bảng nhỏ nóng bị "lũ FTS" bảng lớn đuổi khỏi cache → `db file sequential/scattered read` chiếm top → hoặc tune SQL giảm I/O (ưu tiên 1), hoặc tăng cache, hoặc **cách ly bảng nóng vào KEEP pool** (đủ chỗ chứa TOÀN BỘ bảng, ngược lại vô nghĩa).

---

## 13. PGA — sort tràn temp? (Section 23)

```sql
-- Sức khỏe PGA tổng thể
SELECT name, ROUND(value/1024/1024) mb
FROM   v$pgastat
WHERE  name IN ('aggregate PGA target parameter','total PGA allocated',
                'total PGA used for auto workareas','over allocation count');

-- Tỉ lệ workarea chạy optimal / one-pass / multipass (lũy kế)
SELECT name, value FROM v$sysstat
WHERE  name LIKE 'workarea executions%' OR name IN ('sorts (memory)','sorts (disk)');

-- Từng SQL: ước tính vs được cấp vs tràn temp bao nhiêu
SELECT SUBSTR(q.sql_text,1,40) sql_text, w.operation_type,
       TRUNC(w.estimated_optimal_size/1024) est_optimal_kb,
       TRUNC(w.last_memory_used/1024)       last_mem_kb,
       TRUNC(w.max_tempseg_size/1024)       max_temp_kb
FROM   v$sql_workarea w JOIN v$sql q
       ON w.address = q.address AND w.hash_value = q.hash_value
WHERE  w.max_tempseg_size > 0
ORDER  BY w.max_tempseg_size DESC;

-- PGA Advisory: target bao nhiêu thì hết tràn?
SELECT ROUND(pga_target_for_estimate/1024/1024) target_mb,
       pga_target_factor, estd_pga_cache_hit_percentage,
       estd_overalloc_count
FROM   v$pga_target_advice ORDER BY 1;
```

**Cách đọc:** `optimal` = sort/hash trọn trong RAM; `one-pass/multipass` = mượn temp (I/O). Wait đi kèm: `direct path read/write temp`. Trong V$PGA_TARGET_ADVICE, **loại trước mọi dòng `estd_overalloc_count > 0`** (target không đủ cấp tối thiểu) rồi mới chọn theo hit%.

**Case:** báo cáo/batch chậm về đêm + `direct path * temp` chiếm top → xem `V$SQL_WORKAREA` câu nào tràn → tăng `PGA_AGGREGATE_TARGET` theo advisory, hoặc tune SQL giảm sort (index, bớt cột). Thấy `over allocation count` tăng đều = target đặt quá thấp so với nhu cầu tối thiểu.

---

## 14. Redo Path (Section 24)

```sql
-- Triệu chứng phía chờ đợi
SELECT event, total_waits, ROUND(time_waited_micro/1e6,1) time_s,
       ROUND(time_waited_micro/1000/NULLIF(total_waits,0),2) avg_ms
FROM   v$system_event
WHERE  event IN ('log file sync','log file parallel write','log buffer space');

-- Ai sinh nhiều redo + commit dày?
SELECT name, value FROM v$sysstat
WHERE  name IN ('redo size','user commits','user calls');

-- Log switch có quá dày không? (khỏe: ~vài lần/giờ)
SELECT TO_CHAR(first_time,'YYYY-MM-DD HH24') gio, COUNT(*) switches
FROM   v$log_history
WHERE  first_time > SYSDATE - 1
GROUP  BY TO_CHAR(first_time,'YYYY-MM-DD HH24') ORDER BY 1 DESC FETCH FIRST 12 ROWS ONLY;

SELECT group#, ROUND(bytes/1024/1024) mb, members, status FROM v$log;
```

**Cách đọc — phân biệt 2 bệnh:**
- `log file sync` cao + `avg_ms` của `log file parallel write` **thấp** → LGWR ghi nhanh nhưng bị gọi quá dày = **app commit từng row** → fix ở app (commit theo batch).
- `log file parallel write` avg_ms **cao** → đĩa chứa redo chậm → chuyển redo sang storage nhanh, tách khỏi datafile.
- Log switch mỗi vài phút → redo log quá nhỏ → tăng size group.

---

## 15. CPU Bottleneck (Section 25)

**Câu hỏi then chốt: CPU host bận do DB hay do process NGOÀI DB?**

```sql
-- Delta V$OSSTAT trong 30s: host bận bao nhiêu %?
-- (kỹ thuật cpu_sample.sql của lab 25 — lấy 2 mẫu trừ nhau)
SELECT stat_name, value FROM v$osstat
WHERE  stat_name IN ('BUSY_TIME','IDLE_TIME','NUM_CPUS');
-- ... đợi N giây, lấy lại, tính: %busy = ΔBUSY/(ΔBUSY+ΔIDLE)

-- DB dùng bao nhiêu CPU trong cùng khoảng? (delta DB CPU / thời gian / NUM_CPUS)
SELECT ROUND(value/1e6,1) db_cpu_s FROM v$sys_time_model WHERE stat_name = 'DB CPU';

-- SQL ngốn CPU nhất
@_toolkit/top_sql.sql CPU
```

**Logic kết luận:**
- `%busy host` cao ≈ `DB CPU` quy đổi → thủ phạm là **SQL trong DB** → top_sql CPU, xem plan (FTS lặp? hàm trong WHERE? parse CPU?).
- `%busy host` cao nhưng `DB CPU` thấp → **process ngoài DB** chiếm CPU (backup, batch OS, con trỏ khác) → sang tầng OS `top`/`ps` (§22).
- ASH toàn `ON CPU` mà host **chưa** hết CPU → bình thường, không phải bệnh; chỉ báo động khi runqueue > số core (vmstat cột `r`).
- Hard parse cũng đốt CPU — đối chiếu §10 trước khi kết luận "cần thêm core".

---

## 16. Disk I/O (Section 26)

```sql
-- I/O theo datafile: chỗ nào đọc/ghi nhiều, latency bao nhiêu?
SELECT f.file_name, s.phyrds, s.phywrts,
       ROUND(s.readtim*10/NULLIF(s.phyrds,0),1) avg_read_ms
FROM   v$filestat s JOIN dba_data_files f ON f.file_id = s.file#
ORDER  BY s.phyrds DESC;

-- Hoặc theo function (LGWR, DBWR, Direct...)
SELECT function_name, ROUND(SUM(number_of_waits)) waits,
       ROUND(SUM(wait_time)/1000) time_s
FROM   v$iostat_function GROUP BY function_name ORDER BY 3 DESC;

-- Nghi FTS bất thường: index có bị UNUSABLE không? (case lab 26: MOVE làm index chết)
SELECT index_name, status FROM dba_indexes
WHERE  table_name = '&TABLE' AND status <> 'VALID';

-- Segment nào bị đọc vật lý nhiều nhất (AWR)
SELECT * FROM (
  SELECT n.object_name, SUM(s.physical_reads_delta) phys_reads
  FROM   dba_hist_seg_stat s JOIN dba_hist_seg_stat_obj n
         ON n.obj# = s.obj# AND n.dataobj# = s.dataobj#
  GROUP  BY n.object_name ORDER BY 2 DESC
) WHERE ROWNUM <= 10;
```

**Case cần xử lý:**
- I/O bùng nổ đột ngột sau bảo trì → nghi **index UNUSABLE** (sau `ALTER TABLE MOVE` không rebuild) → plan rơi về FTS → `REBUILD`.
- `db file scattered read` avg_ms cao đều → storage chậm thật (đối chiếu `iostat` OS) ≠ số lần đọc quá nhiều (bệnh SQL/plan).
- Trước khi đổ lỗi phần cứng: **giảm số I/O bằng tune SQL trước, đo tốc độ I/O sau** (`DBMS_RESOURCE_MANAGER.CALIBRATE_IO` — chạy lúc idle, trong VM).

---

## 17. Index Defragmentation (Section 27)

```sql
-- Đo mức bloat: ANALYZE INDEX ... VALIDATE STRUCTURE → INDEX_STATS (⚠️ khóa DML khi chạy!)
ANALYZE INDEX soe.ord_status_ix VALIDATE STRUCTURE;
SELECT name, height, lf_rows, del_lf_rows,
       ROUND(100*del_lf_rows/NULLIF(lf_rows,0),1) del_pct,
       btree_space, used_space,
       ROUND(100*used_space/NULLIF(btree_space,0),1) used_pct
FROM   index_stats;

-- Fix: 2 con đường
ALTER INDEX soe.ord_status_ix COALESCE;          -- gộp block lá kề nhau, online, nhẹ
ALTER INDEX soe.ord_status_ix REBUILD ONLINE;    -- xây lại từ đầu, tốn hơn, reset HEIGHT
```

**Cách đọc:** `DEL_LF_ROWS/LF_ROWS > ~20%` + `USED_PCT` thấp → index rỗng ruột (điển hình sau delete hàng loạt, hoặc cột tăng đơn điệu bị xóa đầu dãy). B-tree **tự cân bằng về logic nhưng không tự thu hồi block lá rỗng** — myth "index tự cân bằng nên không bao giờ cần rebuild" chỉ đúng một nửa.

**Case:** COALESCE đủ cho phần lớn tình huống (online, không cần lock dài); REBUILD khi muốn giảm HEIGHT/đổi tablespace/PCTFREE — ⚠️ REBUILD ONLINE vẫn cần 2 khoảnh khắc lock, DML dày có thể làm nó hang (lab 27 chứng minh bằng `idx_dml_load.sh`).

---

## 18. Row Migration & Chaining (Section 28 — lab mẫu chuẩn)

```sql
-- ⚠️ DBMS_STATS KHÔNG đếm CHAIN_CNT (để NULL/0 giả) — phải dùng ANALYZE:
ANALYZE TABLE cust COMPUTE STATISTICS;
SELECT chain_cnt,
       ROUND(chain_cnt/NULLIF(num_rows,0)*100, 2) AS chain_pct,
       avg_row_len, pct_free, blocks
FROM   user_tables WHERE table_name = 'CUST';

-- Chỉ đích danh row nào (bảng chained_rows theo layout utlchain.sql):
ANALYZE TABLE cust LIST CHAINED ROWS INTO chained_rows;
SELECT COUNT(*) FROM chained_rows;

-- Triệu chứng lúc chạy: mỗi lần đọc row migrate = +1 lần đọc block
SELECT n.name, s.value FROM v$sysstat s JOIN v$statname n ON n.statistic#=s.statistic#
WHERE  n.name = 'table fetch continued row';

-- Fix migration: nới PCTFREE + xây lại bảng, rồi rebuild index (MOVE làm index UNUSABLE!)
ALTER TABLE cust PCTFREE 20;
ALTER TABLE cust MOVE ONLINE;
-- ANALYZE lại → chain_cnt về ~0; sau cùng GATHER_TABLE_STATS trả stats chuẩn
EXEC DBMS_STATS.GATHER_TABLE_STATS(USER, 'CUST')
```

**Phân biệt bằng AVG_ROW_LEN (mấu chốt):**

| AVG_ROW_LEN | Kết luận | Fix |
|---|---|---|
| << block size (8K) | **MIGRATION** — row vừa block nhưng bị chuyển nhà do UPDATE phình | PCTFREE đủ + MOVE |
| >~ block size | **CHAINING** — row to hơn block, PCTFREE không cứu được | Block size lớn hơn (tablespace 32K) / tách cột / LOB |

**Bẫy đã đúc kết:** sau `ANALYZE` phải `DBMS_STATS.GATHER_TABLE_STATS` lại (ANALYZE ghi đè optimizer stats theo cách deprecated); `MOVE` xong **bắt buộc** rebuild index; triệu chứng bề mặt là `buffer_gets/exec` tăng dù bảng không to lên + `db file sequential read` nhiều.

---

## 19. Table Fragmentation — HWM (Section 29)

```sql
-- 3 góc đo cùng 1 sự thật:
-- (a) Stats: bảng nhiều block nhưng ít row, mỗi block trống nhiều
SELECT num_rows, blocks, avg_space FROM user_tables WHERE table_name = '&T';

-- (b) DBMS_SPACE: block trống thật dưới HWM
SET SERVEROUTPUT ON
DECLARE
  l_fs1 NUMBER; l_fs2 NUMBER; l_fs3 NUMBER; l_fs4 NUMBER;
  l_b1 NUMBER; l_b2 NUMBER; l_b3 NUMBER; l_b4 NUMBER;
  l_full NUMBER; l_fullb NUMBER; l_un NUMBER; l_unb NUMBER;
BEGIN
  DBMS_SPACE.SPACE_USAGE(USER, '&T', 'TABLE',
    l_fs1,l_b1, l_fs2,l_b2, l_fs3,l_b3, l_fs4,l_b4, l_full,l_fullb, l_un,l_unb);
  DBMS_OUTPUT.PUT_LINE('FS4 (75-100% trống): '||l_fs4||' blocks; FULL: '||l_full);
END;
/

-- (c) FTS đọc bao nhiêu block? — FTS quét TỚI HWM, kể cả block rỗng
SET AUTOTRACE TRACEONLY STATISTICS
SELECT COUNT(*) FROM &T;   -- xem 'consistent gets' trước/sau fix

-- Fix: hạ HWM
ALTER TABLE &T ENABLE ROW MOVEMENT;
ALTER TABLE &T SHRINK SPACE CASCADE;   -- online, giữ index dùng được
-- (hoặc ALTER TABLE MOVE + rebuild index)
```

**Case:** sau bulk delete (nghiệp vụ archive), bảng "nhẹ" đi nhưng **FTS vẫn chậm y nguyên** — vì HWM không tự hạ, FTS vẫn quét đủ block rỗng. Điểm học quan trọng: fragment **chỉ phạt FTS, không phạt truy cập qua index** (index rowid trỏ thẳng block) → nếu workload toàn index access thì shrink không cấp bách. `SHRINK SPACE` cần ROW MOVEMENT (rowid đổi) — cân nhắc app nào cache rowid; DML dày lúc shrink dễ ORA-00054.

---

## 20. Compression & In-Memory (Section 30, 31)

```sql
-- Đo ratio nén thật (trước/sau): blocks + bytes từng bảng
SELECT segment_name, ROUND(bytes/1024/1024) mb, blocks
FROM   user_segments WHERE segment_name LIKE 'T%' ORDER BY 1;

-- Kiểu nén của bảng
SELECT table_name, compression, compress_for FROM user_tables;

-- In-Memory: populate xong chưa? tốn bao nhiêu so với segment gốc?
SELECT segment_name, populate_status,
       ROUND(bytes/1024/1024)          seg_mb,
       ROUND(inmemory_size/1024/1024)  im_mb
FROM   v$im_segments;
-- Plan phải thấy: TABLE ACCESS INMEMORY FULL
```

**Case:**
- **Basic compression chỉ nén direct-path** (APPEND/CTAS) — INSERT thường vào bảng COMPRESS BASIC **không nén**; Advanced (COMPRESS FOR OLTP) nén cả conventional nhưng cần **license ACO**. Ratio phụ thuộc độ lặp dữ liệu — đo trên dữ liệu thật, đừng tin con số brochure.
- IMCS: chờ `POPULATE_STATUS = COMPLETED` mới đo (populate là async); `INMEMORY_SIZE` cần restart; footprint IM thường << segment (nén cột). Chỉ thắng lớn với analytic scan/aggregate — OLTP điểm-truy-cập không lợi.

---

## 21. Connection & ARRAYSIZE (Section 32)

```sql
-- Đòn bẩy chính: fetch theo mảng. Round-trip = CEIL(rows / arraysize)
SET AUTOTRACE TRACEONLY STATISTICS
SET ARRAYSIZE 10     -- rồi thử 100, 500 — so 'SQL*Net roundtrips to/from client'
SELECT * FROM soe.customers WHERE ROWNUM <= 5000;

-- Nhìn từ phía DB: app nào round-trip dày?
SELECT n.name, s.value FROM v$sysstat s JOIN v$statname n ON n.statistic#=s.statistic#
WHERE  n.name IN ('SQL*Net roundtrips to/from client',
                  'bytes sent via SQL*Net to client', 'user calls');
```

**Case:** app kéo resultset lớn mà chậm, DB lại nhàn (`SQL*Net message from client` chiếm thời gian) → tăng fetch size phía driver (JDBC `setFetchSize`, sqlplus ARRAYSIZE). Hiệu quả tỉ lệ với **latency mạng** — LAN latency thấp thì SDU/socket buffer (BDP) chỉ là tinh chỉnh phụ.

---

## 22. Tầng OS + cầu SPID (Section 34)

**USE method: Utilization – Saturation – Errors, chạy trong VM:**

```bash
vmstat 5 3        # cột r > số core = CPU bão hòa; b = chờ I/O; si/so ≠ 0 = swap (nguy!)
top -o %CPU       # process nào chiếm CPU; oracle hay ngoài oracle?
iostat -xz 5 3    # %util, await theo device — I/O bão hòa?
mpstat -P ALL 5 1 # lệch core? %iowait?
free -m           # RAM/swap
```

**Cầu SPID — nối process OS ↔ session DB (2 chiều):**

```sql
-- Thấy PID ngốn CPU trong top → nó là session nào trong DB?
SELECT s.sid, s.serial#, s.username, s.sql_id, s.event, s.machine
FROM   v$session s JOIN v$process p ON p.addr = s.paddr
WHERE  p.spid = &os_pid;

-- Ngược lại: session DB này là process OS nào?
SELECT p.spid FROM v$process p JOIN v$session s ON p.addr = s.paddr WHERE s.sid = &sid;
```

**Case:** host 100% CPU — bước 1 là `top`: nếu process đầu bảng **không phải** oracle thì mọi tuning DB đều vô ích (case `cpu_load.sh external` của lab 25/34). Nếu là oracle → SPID bridge → sql_id → tune SQL. Thu thập dài hạn: OSWatcher (cần Java 8).

---

## 23. Bảng tra nhanh: triệu chứng → hướng điều tra

| Triệu chứng | Nghi phạm số 1 | Lệnh kiểm chứng | Mục |
|---|---|---|---|
| DB time >> DB CPU | Wait nào đó | `top_waits.sql` | §2 |
| DB CPU ≈ DB time | SQL ngốn CPU / thiếu core | `top_sql.sql CPU` + V$OSSTAT | §15 |
| `db file sequential read` cao | Cache thiếu / row migration / index access dày | V$BH, `table fetch continued row` | §12, §18 |
| `db file scattered read` cao | FTS: index UNUSABLE / HWM cao / plan sai | `dba_indexes.status`, DBMS_SPACE | §16, §19 |
| `enq: TX` | Row lock ứng dụng | V$LOCK holder/waiter, ROW_WAIT_* | §9 |
| `library cache: mutex X` | Literal SQL → hard parse | FORCE_MATCHING_SIGNATURE | §10 |
| `log file sync` | Commit từng row / đĩa redo chậm | `log file parallel write` avg_ms | §14 |
| `direct path read/write temp` | PGA thiếu, sort tràn | V$SQL_WORKAREA, PGA advisory | §13 |
| `buffer_gets/exec` tăng dần theo thời gian | Row migration / index bloat | ANALYZE chain_cnt, INDEX_STATS | §18, §17 |
| FTS chậm dù bảng đã delete gần hết | HWM không tự hạ | DBMS_SPACE + consistent gets | §19 |
| Chậm "hôm qua", giờ hết | Quá khứ → AWR/ASH history | awrrpt, DBA_HIST_ACTIVE_SESS_HISTORY | §5, §3 |
| Chậm sau deploy | Plan regression | DBA_HIST_SQLSTAT theo plan_hash_value | §5 |
| Batch đang chạy mãi không xong | Xem plan sống | REPORT_SQL_MONITOR | §8 |
| App chậm nhưng DB nhàn | Round-trip / app-side | ARRAYSIZE, SQL*Net stats | §21 |
| Host 100% CPU, DB CPU thấp | Process ngoài DB | `top` + SPID bridge | §22, §15 |

---

## Nhắc lại 5 nguyên tắc xuyên suốt khóa học

1. **Đo trước — fix sau — đo lại**: không có số baseline thì không có "đã nhanh hơn". Mọi `04_fix.sql` kết thúc bằng so sánh trước/sau.
2. **V$ là lũy kế**: mọi kết luận theo khoảng thời gian phải là **delta** (AWR, before_after, 2 mẫu trừ nhau).
3. **Advisory chỉ tin khi đo lúc tải BÌNH THƯỜNG** (shared pool, buffer cache, PGA — cả ba đều dính bẫy này).
4. **Chữa nguyên nhân, không chữa triệu chứng**: literal storm thì sửa code chứ không mua RAM; commit dày thì sửa app chứ không thay đĩa.
5. **Đúng công cụ cho đúng thì**: đang xảy ra → V$SESSION/V$LOCK/SQL Monitor; vừa xong → ASH; quá khứ xa → AWR/ASH history; cần chi tiết từng call → SQL Trace + tkprof.


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/labs/SO_TAY_CHAN_DOAN.md`
