---
title: 'Section 6 — Time Model Views: Deep Dive for Senior DBA'
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/section_all_new/section_6_time_model_senior_guide.md
---

# Section 6 — Time Model Views: Deep Dive for Senior DBA

> **Nguồn:** `pdf_extracted/section_6/Practice_2_-_Using_Time_Model_Views.md` (Ahmed Baraka)
> `section_all/section_6_time_model_guide.md` — Oracle 19c internals

---

## OUTPUT 1 — LECTURE NOTES

---

## 1. Mental Model

Time Model là hệ thống **kế toán thời gian foreground** của Oracle — nó đo tổng lượng công việc database thực hiện cho user sessions, không phải tốc độ. Trên hệ thống 32-core với 200 concurrent active sessions, DB Time trong 60 giây wall clock có thể đạt 12,000+ giây — đây là signal healthy về parallelism, không phải bug. Cái bẫy thực sự là khi DB Time tăng đột biến nhưng DB CPU tăng không tương xứng: đó là lúc wait events đang ăn mòn throughput. AWR dùng DB Time làm **mẫu số** cho mọi phần trăm trong "Top Timed Events" — nếu bạn không hiểu DB Time là gì, bạn đọc AWR sai từ đầu.

---

## 2. Internals & Mechanics

**Storage và accumulation:**
Values trong `V$SYS_TIME_MODEL` là microseconds, tích lũy từ instance startup, lưu trong SGA. `TIMED_STATISTICS = TRUE` (default từ Oracle 10g) bắt buộc — nếu FALSE, hầu hết stats trả về 0. Verify trước khi trust bất cứ con số nào:

```sql
SELECT VALUE FROM V$PARAMETER WHERE NAME = 'timed_statistics';
```

**Cấu trúc phân cấp — không phải phép cộng:**

```text
DB time                                  ← mẫu số của AWR
 ├── sql execute elapsed time            ← thường 85–95% trong OLTP
 │    ├── parse time elapsed
 │    │    └── hard parse elapsed time   ← subset của parse
 │    ├── PL/SQL execution elapsed time
 │    │    └── inbound PL/SQL rpc elapsed time
 │    └── Java execution elapsed time
 ├── connection management call elapsed time
 ├── failed parse elapsed time
 ├── sequence load elapsed time
 └── RMAN cpu time (backup/restore)
```

Tổng phần trăm các "con" **không bằng 100%** vì overlap: `sql execute elapsed time` đã bao gồm `parse time elapsed`. Ahmed Baraka nhấn mạnh điều này trong practice step 10: *"The total of the percentage figures in the children rows is not 100. That is normal."*

**Background processes bị loại hoàn toàn:**
LGWR, DBWR, CKPT, MMON không tính vào DB Time. I/O bottleneck do DBWR quá tải chỉ thấy gián tiếp — foreground sessions tăng wait `db file parallel write` và `log file sync`. Time Model không show nguyên nhân root, nó show hậu quả trên foreground.

**Công thức cốt lõi từ practice scripts:**

```text
DB Time  = DB CPU  +  Wait Time
Wait Time = DB Time - DB CPU
WAIT_PCT  = (DB Time - DB CPU) / DB Time × 100
WAIT_USER_SHARE = (DB Time - DB CPU) / USERS_CNT
```

`WAIT_USER_SHARE` — metric ít được nhắc đến nhưng rất thực tế: đo wait time trung bình mỗi user session. Khi số này tăng phi tuyến khi concurrency tăng, đó là dấu hiệu scalability bottleneck đang xuất hiện.

**Delta là thứ duy nhất có ý nghĩa:**
V$SYS_TIME_MODEL là odometer (tích lũy từ startup), không phải speedometer. Practice của Ahmed Baraka implement manual snapshot table `TM_HISTORY` + `LAG()` để tính delta — đây chính xác là cơ chế AWR dùng nội bộ với `DBA_HIST_SYS_TIME_MODEL`. Khi không có AWR license, `TM_HISTORY` approach là equivalent hợp lệ.

**RAC và CDB:**

- RAC: `V$SYS_TIME_MODEL` chỉ hiện node hiện tại → dùng `GV$SYS_TIME_MODEL` + `INST_ID` để cross-node compare.
- CDB 19c: từ CDB$ROOT nhận aggregate toàn CDB; từ PDB context nhận PDB-scoped values. Luôn verify `SELECT SYS_CONTEXT('USERENV','CON_NAME') FROM DUAL` trước khi interpret.

---

## 3. Production Realities

**Graduated load reveals non-linear scalability:**
Pattern từ practice (10→30→60 users) thường cho thấy: WAIT_PCT tăng tuyến tính từ 10→30 users, sau đó tăng đột ngột từ 30→60 users. Điểm gãy đó là **scalability knee** — nơi một resource bắt đầu serialize. Hệ thống production healthy thường có WAIT_PCT < 30% ở peak load; > 60% là signal cần investigate ngay.

**Hard parse >10% DB Time — nhiều thứ xảy ra đồng thời:**
Hard parse không chỉ tốn CPU — nó acquire `library cache latch` (hoặc library cache mutex từ 11g) theo exclusive mode, serialize tất cả concurrent parsers. Một session hard parsing 500ms có thể block 50 sessions khác 1–2ms mỗi cái. `hard parse elapsed time` cao là multiplier, không phải additive cost.

**Connection management overhead:**
`connection management call elapsed time` > 3% DB Time thường chỉ connection pool thiếu hoặc misconfigured. Classic JDBC direct-connection pattern (connect per transaction) tạo login overhead: authentication, session initialization, SGA allocation. Trên Oracle với password complexity policy + auditing, login overhead càng cao hơn.

**RMAN làm skew toàn bộ phân tích:**
Backup job on-host đẩy `RMAN cpu time` vào DB Time, inflate mẫu số, làm các phần trăm khác trông thấp hơn thực tế. Khi phân tích Time Model mà thấy DB CPU % bất thường thấp trong khi hệ thống bận, check ngay xem RMAN có đang chạy không.

**Giá trị tích lũy sau restart ngắn:**
Practice note của Baraka: *"If the system was started short time ago, the view contents do not represent the actual database workload."* Sau restart, V$SYS_TIME_MODEL reflect chỉ workload từ lúc startup — baseline không có nghĩa. Luôn verify instance uptime trước khi dùng raw cumulative values.

**V$SESS_TIME_MODEL cho session-level triage:**
Top sessions theo DB Time thường là những session đang hold resource quan trọng (lock, latch) hoặc chạy long-running SQL. Kết hợp `WAIT_PCT` per session: session có DB Time cao + WAIT_PCT > 70% thường đang chờ external resource, không phải compute-bound.

---

## 4. Decision Framework

| Triệu chứng quan sát | Time Model signal | Bước tiếp theo |
| -------------------- | ----------------- | -------------- |
| Hệ thống chậm không rõ nguyên nhân | Chạy `V$SYS_TIME_MODEL` — xem stat nào top | Nếu `sql execute` > 90% → drill wait events; nếu `parse` > 10% → cursor sharing |
| WAIT_PCT tăng khi users tăng | Scalability bottleneck xuất hiện | Identify wait class dominant qua `V$SYSTEM_EVENT` |
| DB Time tăng 2x, DB CPU tăng 1.1x | Wait overhead đang dominate | Lock/latch/I/O contention — không phải compute |
| DB CPU tăng nhưng throughput flat | CPU inefficiency | Hard parse spike, full scan increase, plan regression |
| Login latency cao | `connection management` > 3% | Connection pool audit; authentication config |
| Sau deploy mới | `hard parse elapsed time` nhảy vọt | Literals vs bind vars; cursor sharing regression |
| RMAN running | `RMAN cpu time` inflate DB Time | Loại RMAN khỏi analysis hoặc schedule off-peak |

**Khi nào Time Model là entry point, không phải destination:**
Time Model trả lời "loại công việc nào chiếm thời gian" — không trả lời "SQL nào, session nào, object nào." Sau khi form hypothesis từ Time Model, luôn cross-reference với `V$SYSTEM_EVENT` (wait class breakdown) và `V$SQL` (top SQL by elapsed time).

---

## 5. Key SQL / Commands

**Manual delta snapshot — tương đương AWR, không cần license:**

```sql
-- Tạo bảng history (từ practice script của Ahmed Baraka)
DROP TABLE TM_HISTORY;
DROP SEQUENCE s_tmhist;
CREATE SEQUENCE s_tmhist;

CREATE TABLE TM_HISTORY AS
SELECT s_tmhist.NEXTVAL                                  AS snap_id,
       dbtime.VALUE / 1e6                                AS dbtime,
       dbcpu.VALUE  / 1e6                                AS dbcpu,
       (dbtime.VALUE - dbcpu.VALUE) / 1e6                AS wait_time,
       (SELECT COUNT(*) FROM V$SESSION
        WHERE  USERNAME IS NOT NULL)                     AS users_cnt
FROM   V$SYS_TIME_MODEL dbtime,
       V$SYS_TIME_MODEL dbcpu
WHERE  dbtime.STAT_NAME = 'DB time'
AND    dbcpu.STAT_NAME  = 'DB CPU';
-- Self-join V$SYS_TIME_MODEL để lấy 2 stats trong 1 INSERT
```

**Chụp snapshot tại một thời điểm:**

```sql
INSERT INTO TM_HISTORY
SELECT s_tmhist.NEXTVAL,
       dbtime.VALUE / 1e6,
       dbcpu.VALUE  / 1e6,
       (dbtime.VALUE - dbcpu.VALUE) / 1e6,
       (SELECT COUNT(*) FROM V$SESSION WHERE USERNAME IS NOT NULL)
FROM   V$SYS_TIME_MODEL dbtime,
       V$SYS_TIME_MODEL dbcpu
WHERE  dbtime.STAT_NAME = 'DB time'
AND    dbcpu.STAT_NAME  = 'DB CPU';
COMMIT;
```

**Phân tích history với LAG() — cơ chế delta chính xác:**

```sql
SET LINESIZE 180
SELECT
    TO_CHAR(dbtime,    '999,999,999')      dbtime,
    TO_CHAR(dbcpu,     '999,999,999')      dbcpu,
    ROUND(dbcpu - LAG(dbcpu, 1, 0)
          OVER (ORDER BY snap_id))         dbcpu_diff,
    TO_CHAR(wait_time, '999,999,999')      wait_time,
    ROUND(wait_time - LAG(wait_time, 1, 0)
          OVER (ORDER BY snap_id))         wait_time_diff,
    TO_CHAR((dbtime - dbcpu) / NULLIF(dbtime,0) * 100,
            '99.99') || '%'               wait_pct,
    users_cnt,
    ROUND((dbtime - dbcpu) / NULLIF(users_cnt,0)) wait_user_share
FROM   TM_HISTORY
ORDER  BY snap_id;
-- LAG(col,1,0): compare với snapshot liền trước, default=0 nếu không có row trước
-- NULLIF bảo vệ division khi dbtime=0 (idle instance) hoặc users_cnt=0
```

**Phân tích % phân cấp theo DB Time:**

```sql
SELECT stat_name,
       ROUND(VALUE / 1e6, 2)                                  seconds,
       ROUND(VALUE /
             NULLIF((SELECT VALUE FROM V$SYS_TIME_MODEL
                     WHERE  stat_name = 'DB time'), 0)
             * 100, 1)                                        pct_dbtime
FROM   V$SYS_TIME_MODEL
WHERE  stat_name != 'DB time'
ORDER  BY VALUE DESC;
-- Bỏ 'DB time' ra khỏi list để tránh 100% tự reference
```

**Top sessions — production triage nhanh:**

```sql
SELECT s.SID, s.SERIAL#, s.USERNAME, s.PROGRAM,
       s.STATUS,
       ROUND(t_time.VALUE / 1e6, 1)                         sess_dbtime_sec,
       ROUND(t_cpu.VALUE  / 1e6, 1)                         sess_cpu_sec,
       ROUND((t_time.VALUE - t_cpu.VALUE)
             / NULLIF(t_time.VALUE, 0) * 100, 1)            wait_pct
FROM   V$SESSION          s
JOIN   V$SESS_TIME_MODEL  t_time ON s.SID = t_time.SID
                               AND t_time.STAT_NAME = 'DB time'
JOIN   V$SESS_TIME_MODEL  t_cpu  ON s.SID = t_cpu.SID
                               AND t_cpu.STAT_NAME  = 'DB CPU'
WHERE  s.USERNAME IS NOT NULL
AND    t_time.VALUE > 0
ORDER  BY t_time.VALUE DESC
FETCH FIRST 15 ROWS ONLY;
```

**RAC cluster-wide profile:**

```sql
SELECT inst_id,
       stat_name,
       ROUND(VALUE / 1e6, 0)                                  cumul_sec,
       ROUND(VALUE /
             SUM(DECODE(stat_name,'DB time',VALUE,0))
             OVER (PARTITION BY inst_id) * 100, 1)            pct_dbtime
FROM   GV$SYS_TIME_MODEL
WHERE  stat_name IN ('DB time','DB CPU',
                     'sql execute elapsed time',
                     'parse time elapsed',
                     'hard parse elapsed time',
                     'connection management call elapsed time')
ORDER  BY inst_id, cumul_sec DESC;
-- PARTITION BY inst_id: tính % riêng cho từng node, không blend chéo
```

---

## 6. Senior Checklist

- Verify `TIMED_STATISTICS = TRUE` trước khi trust bất kỳ số liệu nào — query V$PARAMETER.
- Luôn làm việc với **delta** (interval), không phải giá trị tích lũy raw — V$SYS_TIME_MODEL là odometer.
- Check instance uptime (`SELECT STARTUP_TIME FROM V$INSTANCE`) — instance mới restart có raw values thấp, không represent steady-state.
- Trên RAC, so sánh `GV$SYS_TIME_MODEL` chéo nodes — imbalance giữa instances thường chỉ sequence contention hoặc hot block.
- Khi `hard parse elapsed time / DB time > 5–10%`, audit cursor sharing ngay: `SELECT FORCE_MATCHING_SIGNATURE, COUNT(*) child_cnt FROM V$SQL GROUP BY FORCE_MATCHING_SIGNATURE HAVING COUNT(*) > 10`.
- RMAN running on-host làm inflate `RMAN cpu time` trong DB Time — loại ra trước khi so sánh với baseline.
- Time Model là **entry point** — form hypothesis xong thì cross-reference với `V$SYSTEM_EVENT` và `V$SQL` để có root cause.

---

---

## OUTPUT 2 — LAB EXERCISES

---

## Lab: Time Model Views — Hands-on for Senior DBA

## Lab Overview

- **Mục tiêu:** Xây dựng phản xạ triage từ Time Model — từ raw numbers đến actionable hypothesis trong < 5 phút; validate scalability curve qua graduated load
- **Môi trường:** Oracle 19c / Non-CDB hoặc PDB; Swingbench SOE schema (hoặc workload tương đương)
- **Thời gian ước tính:** 50 phút
- **Độ khó:** Senior / Expert

---

## Exercise 1 — Graduated Load Profiling và Scalability Knee Detection

### Scenario

Production OLTP system sắp được scale thêm user từ 500 → 1500 concurrent. Management muốn data-driven answer: liệu database có chịu được 3x load không, hay cần hardware upgrade trước? Bạn được yêu cầu deliver một báo cáo trong 2 tiếng với con số cụ thể. Không có AWR Diagnostic Pack license trên môi trường test.

### Tasks

1. Implement `TM_HISTORY` snapshot mechanism theo design của Ahmed Baraka: tạo bảng lưu `DBTIME`, `DBCPU`, `WAIT_TIME`, `USERS_CNT` + sequence. Chụp snapshot baseline (t0) trước khi có workload.
2. Chạy 3 load levels (tương đương 10 → 30 → 60 Swingbench users hoặc equivalent concurrent sessions). Sau mỗi level chạy đủ **1 phút** (không ước lượng — dùng stopwatch), chụp snapshot.
3. Query `TM_HISTORY` với `LAG()` để tính `DBCPU_DIFF`, `WAIT_TIME_DIFF`, `WAIT_PCT`, `WAIT_USER_SHARE` cho từng interval.
4. Tìm **scalability knee**: interval nào `WAIT_TIME_DIFF` tăng nhanh hơn `DBCPU_DIFF` một cách đáng kể? Tính ratio `WAIT_TIME_DIFF / DBCPU_DIFF` cho mỗi interval.
5. Kết luận: ở mức load nào hệ thống bắt đầu serialize? Con số `WAIT_USER_SHARE` tại mức đó là bao nhiêu, và nó có acceptable với SLA của hệ thống không?

### Expected Findings

- `WAIT_PCT` tăng moderate từ 10→30 users (linear scaling zone), tăng đột ngột từ 30→60 users (contention zone).
- `WAIT_TIME_DIFF / DBCPU_DIFF ratio` > 3.0 tại interval 30→60 thường chỉ một resource đang serialize.
- `WAIT_USER_SHARE` tăng phi tuyến — nếu tăng 5x khi users tăng 2x, database không scale linearly.

### Debrief Questions

- Nếu `WAIT_PCT = 70%` tại 60 users, điều đó có nghĩa là gì về utilization thực tế của CPU cores? DB Time / Elapsed Time ratio là bao nhiêu tại thời điểm đó?
- Tại sao phải chạy đúng 1 phút và không được ước lượng? Hint: liên quan đến cách tính delta và statistical significance của interval.

---

## Exercise 2 — Hard Parse Regression Post-Deployment

### Scenario

Thứ Hai 09:30, sau weekend deployment application v4.2. DBA nhận notification: CPU utilization tăng 55% so với baseline thứ Hai tuần trước, nhưng throughput (transactions/sec) thực ra thấp hơn 10%. User không nhận ra vì response time chỉ tăng vừa phải. Không có code change nào được document trong release note. Time Model delta từ 08:00–09:30 cho thấy `hard parse elapsed time` = 19.3% của DB Time (baseline: 1.1%).

### Tasks

1. Corroborate hard parse spike từ 3 angles: (a) `V$SYS_TIME_MODEL` delta, (b) `V$LIBRARY_CACHE` — tính ratio `RELOADS / PINS` và so với baseline, (c) `V$SQL` — tính ratio `PARSE_CALLS / EXECUTIONS` cho top 50 SQL by parse_calls.
2. Identify SQL bị ảnh hưởng bằng cách group `V$SQL` theo `FORCE_MATCHING_SIGNATURE` — tìm signatures có > 20 child cursors trong 90 phút deploy.
3. Phân loại nguyên nhân: phân biệt giữa (a) literal values thay vì bind variables, (b) `CURSOR_SHARING` parameter bị thay đổi, (c) ORM framework thay đổi SQL generation pattern, (d) connection pool cursor cache bị disable.
4. Propose remediation với explicit trade-off: `CURSOR_SHARING=FORCE` vs application fix vs `DBMS_SHARED_POOL.KEEP` cho critical cursors.

### Expected Findings

- `V$SQL` sẽ show nhiều rows với cùng `FORCE_MATCHING_SIGNATURE` nhưng SQL text khác nhau ở literal values.
- `LIBRARY_CACHE.RELOADS / PINS` tăng cao → shared pool bị pressure do cursor proliferation, không phải do shared pool size thiếu.
- Pattern phổ biến nhất ở regression sau deploy: ORM (Hibernate, MyBatis) thay đổi cách generate WHERE clause từ bind params sang interpolated strings khi một config flag bị reset.

### Debrief Questions

- `CURSOR_SHARING=FORCE` solve được symptom ngay, nhưng Oracle documentation cảnh báo về potential plan instability với adaptive features (12c+). Trong môi trường 19c với Adaptive Query Optimization, risk cụ thể là gì và bạn giảm thiểu nó bằng cách nào?
- Nếu root cause là ORM và fix code cần 2 sprints, monitoring pipeline nào bạn set up để detect hard parse regression sớm hơn lần sau — trước khi nó impact users?

---

## Exercise 3 — Troubleshooting Scenario *(Expert level)*

### Incident Brief

Thứ Tư 10:15. On-call page: P95 response time tăng từ 115ms lên 870ms trong 2.5 giờ qua. Gradual degradation — không phải spike đột ngột. Không có deployment. DB server CPU ở 43% (baseline ~38%). Memory OK. Application logs: không có error, chỉ slow transactions. DBA trước đó trong shift không tìm ra nguyên nhân và escalate.

### Evidence Provided

**Time Model delta — 07:30 đến 10:15 (165 phút), hôm nay:**

```text
STAT_NAME                                 DELTA_SEC    PCT_DBTIME
----------------------------------------  ---------    ----------
DB time                                    31,200          100.0%
sql execute elapsed time                   29,450           94.4%
  PL/SQL execution elapsed time             9,180           29.4%
  parse time elapsed                        1,290            4.1%
    hard parse elapsed time                   175            0.6%
DB CPU                                      9,840           31.5%
connection management call elapsed time       510            1.6%
```

**Baseline — cùng ngày thứ Tư tuần trước, 07:30–10:15:**

```text
STAT_NAME                                 DELTA_SEC    PCT_DBTIME
----------------------------------------  ---------    ----------
DB time                                    16,100          100.0%
sql execute elapsed time                   14,950           92.9%
  PL/SQL execution elapsed time             2,890           17.9%
  parse time elapsed                          720            4.5%
    hard parse elapsed time                   130            0.8%
DB CPU                                      9,510           59.1%
connection management call elapsed time       445            2.8%
```

**V$SESS_TIME_MODEL — top 5 active sessions tại 10:15:**

```text
SID    USERNAME   STATUS    WAIT_PCT    SESS_DBTIME_SEC   PROGRAM
-----  ---------  -------   --------    ---------------   --------
2847   SOE        ACTIVE       74%            1,840        JDBC Thin
1203   SOE        ACTIVE       71%            1,760        JDBC Thin
3091   SOE        ACTIVE       76%            1,650        JDBC Thin
 934   SOE        ACTIVE       68%            1,590        JDBC Thin
1556   SOE        ACTIVE       72%            1,520        JDBC Thin
```

**V$SYSTEM_EVENT — top wait events, delta 07:30–10:15:**

```text
EVENT                            WAITS     TIME_SEC   AVG_MS
-------------------------------  -------   --------   ------
db file sequential read           61,400    10,290      168
enq: TX - row lock contention      1,580     9,240    5,848
log file sync                     67,200     3,840       57
```

**Thông tin bổ sung:**

- Swingbench vẫn chạy với 25 users (không thay đổi so với tuần trước)
- DBA shift trước đã chạy `ALTER SYSTEM FLUSH SHARED_POOL` lúc 09:00 — không có tác động
- `db file sequential read avg_ms = 168` — storage team confirm I/O latency tăng từ ~4ms lên ~165ms từ khoảng 07:15 sáng

### Your Mission

1. Quantify: DB Time tăng bao nhiêu % so với baseline? DB CPU thay đổi ra sao? Rút ra kết luận gì từ sự chênh lệch giữa hai con số này?
2. `PL/SQL execution elapsed time` tăng từ 17.9% lên 29.4% (tăng ~220% tuyệt đối). Đây là **cause hay effect** của vấn đề chính? Argue từ evidence.
3. `enq: TX - row lock contention` có 1,580 waits nhưng chiếm 9,240 giây (avg 5,848ms mỗi wait). `db file sequential read` có 61,400 waits và chiếm 10,290 giây (avg 168ms). Bottleneck **primary** là gì và bottleneck **secondary** là gì? Chúng có causal relationship không?
4. `ALTER SYSTEM FLUSH SHARED_POOL` không có tác động — tại sao điều này actually helpful cho diagnosis? Nó loại ra hypothesis nào?
5. Đưa ra **root cause hypothesis** và **3 diagnostic queries cụ thể** (tên view + điều kiện WHERE) để confirm hoặc reject trong vòng 5 phút tiếp theo.

### Evaluation Criteria

- Nhận ra DB Time tăng ~94% trong khi DB CPU chỉ tăng ~3% → gần như toàn bộ increment là wait time, không phải compute?
- Identify được I/O latency (168ms vs baseline ~4ms) là **root cause** và lock contention là **cascading effect** (slow I/O → transaction kéo dài → lock hold time tăng → blocking chain dài hơn)?
- Giải thích được `PL/SQL elapsed time` tăng là **effect**: stored procedures gọi SQL queries, SQL queries bị chậm do I/O, do đó PL/SQL execution time inflate theo?
- Propose kiểm tra `V$SESSION_BLOCKERS` hoặc `V$LOCK` để confirm lock chain, không chỉ nói "có lock contention"?
- Không propose `FLUSH SHARED_POOL` lần hai (đã proven vô hiệu) — nhận ra đây là I/O infrastructure issue, không phải SGA issue?
- Identify được next escalation path: storage team cần investigate I/O subsystem từ 07:15, không phải DBA cần tune database?


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/section_all_new/section_6_time_model_senior_guide.md`
