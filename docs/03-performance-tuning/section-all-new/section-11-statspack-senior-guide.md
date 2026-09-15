---
title: Statspack — Deep Dive for Senior DBA
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/section_all_new/section_11_statspack_senior_guide.md
---

# Statspack — Deep Dive for Senior DBA

## 1. Mental Model

Statspack là bước đệm lịch sử nhưng vẫn có production relevance thực tế trong 2024: Standard Edition 2 (SE2) không có Diagnostics Pack license → AWR technically unavailable. Hiểu Statspack là hiểu AWR architecture từ first principles — AWR evolved từ Statspack, giữ nguyên nhiều concepts (snapshot pairs, delta computation, baseline) nhưng thêm automation, MMON background processing, và licensing overhead.

Critical internal distinction: Statspack **lưu absolute cumulative values** tại thời điểm snapshot, rồi **compute delta tại report time** (end − begin). AWR làm ngược lại — pre-compute delta trước khi store. Sự khác biệt này ảnh hưởng trực tiếp đến storage requirements, report performance, và behavior khi instance restart giữa hai snapshots.

---

## 2. Internals & Mechanics

**Snapshot collection mechanism:**
Statspack không có background process. `STATSPACK.SNAP` là synchronous PL/SQL call trong session context của caller:
1. Lock STATS$STATSPACK_PARAMETER để prevent concurrent snaps
2. Iterate qua fixed tables/views: V$SYSSTAT, V$SYSTEM_EVENT, V$SQL, V$LATCH, V$SGASTAT...
3. INSERT absolute cumulative values vào STATS$* tables
4. Commit → snapshot complete

Nếu session terminate mid-snapshot, partial data committed gây inconsistent snapshot — report trên snapshot đó có thể show incorrect deltas. AWR tránh vấn đề này vì MMON background process không bị affected bởi user session state.

**Storage model — absolute vs delta:**
```
Statspack STATS$SYSSTAT:
  snap 1: VALUE = 1,234,567  (cumulative from instance start)
  snap 2: VALUE = 1,456,789

  Report: delta = 1,456,789 - 1,234,567 = 222,222 (computed at report time)

AWR DBA_HIST_SYSSTAT:
  snap 2: VALUE = 222,222  (already computed delta, stored directly)
```

Implication khi instance restart giữa hai snapshots: delta = (small post-restart value) − (large pre-restart value) = negative → spreport shows 0 hoặc N/A cho affected statistics. Statspack report có warning note cho case này nhưng không always obvious.

**Snapshot levels và storage impact:**

| Level | Data thêm | Storage impact |
|-------|-----------|----------------|
| 0 | Wait events, instance activity, rollback, redo | Baseline |
| 5 (default) | Top SQL statements (STATS$SQL_SUMMARY) | Moderate increase |
| 6 | SQL execution plans (STATS$SQL_PLAN) | Significant |
| 7 | Segment-level statistics (STATS$SEG_STAT) | Large |
| 10 | Parent/child latch breakdown (STATS$LATCH_CHILDREN) | Largest |

Level 10 critical use case: child latch breakdown để diagnose latch contention — không available ở lower levels. Trên busy production system, level 10 có thể require 5-10x storage vs level 5. Không nên để level 10 permanently; bật lên khi investigating latch issue rồi reset về 5.

**SQL identifier mismatch:**
Statspack sử dụng HASH_VALUE (4-byte, Oracle 7-era mechanism). AWR và ASH sử dụng SQL_ID (13-character base-32 hash, Oracle 10g+). Hai hệ thống dùng **different hash algorithms** — không có reliable direct conversion. Khi phải correlate Statspack data với ASH/AWR data, phải join qua SQL text substring hoặc accept mismatch.

**PERFSTAT schema và tablespace:**
spcreate.sql prompt cho tablespace. Practice dùng USERS — acceptable cho lab, không cho production. Lý do cần dedicated tablespace:
- STATS$SQL_SUMMARY trên busy system (level 5+, retention 2 tuần) = hàng triệu rows
- Purge operations và space monitoring dễ hơn với dedicated tablespace
- Tránh contention với application data trong USERS

---

## 3. Production Realities

**Automated snapshot scheduling — không optional:**
Practice yêu cầu manual `exec STATSPACK.SNAP`. Production không ai làm thế. Implement ngay sau install:

```sql
-- Connect as perfstat sau khi install
BEGIN
  DBMS_SCHEDULER.CREATE_JOB(
    job_name        => 'STATSPACK_SNAP',
    job_type        => 'STORED_PROCEDURE',
    job_action      => 'STATSPACK.SNAP',
    start_date      => TRUNC(SYSDATE + 1),
    repeat_interval => 'FREQ=MINUTELY;INTERVAL=60',
    enabled         => TRUE,
    auto_drop       => FALSE,
    comments        => 'Hourly Statspack snapshot'
  );
END;
/
```

AWR equivalent: MMON background process chạy tự động. Statspack không có equivalent — đây là operational overhead SE2 DBA phải manage.

**Report generation performance trap:**
`spreport.sql` chạy chậm khi PERFSTAT statistics stale. Root cause: STATS$SQL_SUMMARY có thể grow to tens of millions of rows trên busy system. Without fresh optimizer stats, Oracle full scan thay vì index. Practice step "gather schema stats" không optional — nó critical cho report performance.

Gather stats sau mỗi purge lớn và weekly routine:
```sql
EXEC DBMS_STATS.GATHER_SCHEMA_STATS(OWNNAME=>'PERFSTAT', CASCADE=>TRUE);
```

**Baseline semantics khác AWR hoàn toàn:**
AWR baseline: named period, snapshots retained independently, có comparative reporting.
Statspack baseline: chỉ là `BASELINE='Y'` flag trên STATS$SNAPSHOT row. PURGE skip baseline-flagged snapshots — đó là toàn bộ baseline functionality. Không có tên, không có query interface riêng, không có baseline-to-baseline comparison report.

**Storage retention không tự quản lý:**
AWR có automatic retention policy (default 8 ngày). Statspack không có auto-purge — DBA phải implement DBMS_SCHEDULER purge job. Nếu không, PERFSTAT tablespace fills up. Common production incident: Statspack installed by previous DBA, no purge job, tablespace full sau 3 tháng.

**Statspack trong Oracle 19c/21c:**
Vẫn ship trong $ORACLE_HOME/rdbms/admin/sp*.sql. Oracle chưa deprecate. SE2 environments là primary use case hiện tại. Cloud environments (OCI, AWS) có licensing nuance — check provider terms trước khi decide AWR vs Statspack.

---

## 4. Decision Framework

**Statspack vs AWR:**

| Scenario | Choice | Reason |
|----------|--------|--------|
| Standard Edition 2 | **Statspack** | AWR requires Enterprise Edition + Diagnostics Pack |
| Enterprise Edition, no Diagnostics Pack | **Statspack** | AWR data unlicensed nếu queried directly |
| Enterprise Edition + Diagnostics Pack | **AWR** | More features, automation, ASH, ADDM |
| Cloud (OCI/AWS) with SE2 | Statspack hoặc cloud-native tools | Check provider's license terms |
| Test/Dev, no license concern | AWR preferred | Better tooling, less operational overhead |

**Snapshot level selection:**

| Situation | Level |
|-----------|-------|
| Routine production monitoring | 5 (default) |
| SQL execution plan investigation | 6 |
| Active latch contention incident | 10 (temporary, revert after investigation) |
| Space-constrained environment | 5 với aggressive retention (7 ngày) |

**Anti-patterns:**
- Level 10 permanently trên production → storage explosion trong vài tuần
- Không implement auto-purge → tablespace fills up silently
- Không gather PERFSTAT statistics → report generation timeout
- Dùng USERS tablespace cho PERFSTAT production → contention, space issues

---

## 5. Key SQL / Commands

```sql
-- Install Statspack (as sysdba, batch mode)
DEFINE DEFAULT_TABLESPACE  = 'STATSPACK_DATA'
DEFINE TEMPORARY_TABLESPACE = 'TEMP'
DEFINE PERFSTAT_PASSWORD    = '<secure_password>'
@ ?/rdbms/admin/spcreate

-- Configure snapshot level
EXEC STATSPACK.MODIFY_STATSPACK_PARAMETER(I_SNAP_LEVEL => 5)
SELECT SNAP_LEVEL FROM STATS$STATSPACK_PARAMETER;

-- Automated hourly snapshot job (run as perfstat)
BEGIN
  DBMS_SCHEDULER.CREATE_JOB(
    job_name        => 'STATSPACK_SNAP',
    job_type        => 'STORED_PROCEDURE',
    job_action      => 'STATSPACK.SNAP',
    start_date      => TRUNC(SYSDATE + 1),
    repeat_interval => 'FREQ=MINUTELY;INTERVAL=60',
    enabled         => TRUE,
    auto_drop       => FALSE
  );
END;
/

-- Snapshot inventory với gap detection
SELECT SNAP_ID, SNAP_LEVEL, SNAP_TIME, BASELINE,
       ROUND((SNAP_TIME - LAG(SNAP_TIME) OVER (ORDER BY SNAP_ID)) * 24 * 60, 1) MINS_SINCE_PREV
FROM STATS$SNAPSHOT
ORDER BY SNAP_ID;
-- Gaps > expected interval → missed snapshots (job failed?)

-- Space monitoring
SELECT SEGMENT_NAME, ROUND(SUM(BYTES)/1024/1024, 1) MB
FROM DBA_SEGMENTS
WHERE OWNER = 'PERFSTAT' AND SEGMENT_TYPE = 'TABLE'
GROUP BY SEGMENT_NAME
ORDER BY SUM(BYTES) DESC FETCH FIRST 10 ROWS ONLY;
-- STATS$SQL_SUMMARY và STATS$LATCH_CHILDREN thường chiếm most space

-- Generate instance report (batch mode)
DEFINE BEGIN_SNAP  = 10
DEFINE END_SNAP    = 11
DEFINE REPORT_NAME = sp_10_11
@ ?/rdbms/admin/spreport

-- Generate SQL report (batch mode)
DEFINE BEGIN_SNAP   = 10
DEFINE END_SNAP     = 11
DEFINE HASH_VALUE   = 1234567890    -- từ "SQL ordered by CPU" trong spreport
DEFINE REPORT_NAME  = sql_detail
@ ?/rdbms/admin/sprepsql

-- Gather PERFSTAT stats (trước khi report, weekly, sau purge lớn)
EXEC DBMS_STATS.GATHER_SCHEMA_STATS(OWNNAME=>'PERFSTAT', CASCADE=>TRUE);

-- Purge old non-baselined snapshots
EXEC STATSPACK.PURGE(I_BEGIN_SNAP => 1, I_END_SNAP => 100);

-- Baseline và clear baseline
EXEC STATSPACK.MAKE_BASELINE(I_BEGIN_SNAP => 10, I_END_SNAP => 11)
EXEC STATSPACK.CLEAR_BASELINE(I_BEGIN_SNAP => 10, I_END_SNAP => 11, I_SNAP_RANGE => TRUE)

-- View operational documentation
HOST more $ORACLE_HOME/rdbms/admin/spdoc.txt

-- Remove Statspack (connect as sysdba)
@ ?/rdbms/admin/spdrop
```

---

## 6. Senior Checklist

- [ ] Verify Diagnostics Pack licensing — Statspack là mandatory cho SE2, optional fallback cho EE without pack
- [ ] Implement DBMS_SCHEDULER snapshot job ngay sau install — không bao giờ manual snap trong production
- [ ] Dùng dedicated tablespace cho PERFSTAT, không phải USERS
- [ ] Implement DBMS_SCHEDULER auto-purge job với appropriate retention (2-4 tuần) — prevent tablespace full
- [ ] Gather PERFSTAT schema stats weekly và sau purge lớn — critical cho report performance
- [ ] Hiểu HASH_VALUE ≠ SQL_ID limitation trước khi correlate Statspack data với ASH/AWR
- [ ] Document: snapshot level, retention policy, và scheduled jobs với justification

---

# Lab: Statspack — Hands-on for Senior DBA

## Lab Overview
- **Mục tiêu:** Operational deployment production-ready, không chỉ install-snap-report
- **Môi trường:** Oracle 12c–19c SE2 hoặc EE without Diagnostics Pack
- **Thời gian ước tính:** 75 phút
- **Độ khó:** Senior

---

## Exercise 1 — Production-ready Deployment

### Scenario
Bạn được giao task: deploy Statspack trên production SE2 database (24GB SGA, moderate OLTP, ~200 active sessions peak). System đã chạy 6 tháng mà không có performance monitoring tool. DBA cũ từng dùng manual AWR queries mà không biết cần license (compliance issue vừa được legal flagged).

### Tasks
1. Install Statspack vào dedicated tablespace — tạo và size tablespace trước khi install, không dùng USERS
2. Xác định snapshot level phù hợp cho routine OLTP monitoring với workload hiện tại
3. Tạo DBMS_SCHEDULER job: snapshot mỗi 30 phút trong business hours (08:00–20:00), mỗi 60 phút ngoài business hours
4. Tạo DBMS_SCHEDULER purge job: delete snapshots > 14 ngày (non-baselined), chạy mỗi Sunday 02:00 — I_END_SNAP phải được xác định dynamically

### Expected Findings
- Dedicated tablespace simplifies space monitoring và purge planning
- Level 5 phù hợp cho routine monitoring; level 10 chỉ khi debugging latch issues
- Two separate jobs với different intervals requires time-window logic hoặc two separate job definitions
- Dynamic PURGE job phải compute I_BEGIN_SNAP bằng subquery trên STATS$SNAPSHOT

### Debrief Questions
- Tại sao không nên set STATSPACK tablespace AUTOEXTEND ON unlimited trong production?
- Nếu STATSPACK_SNAP job fail silently trong 48 giờ, bạn phát hiện thế nào trước khi cần report?
- Level 6 (SQL execution plans) có storage overhead như thế nào? Conditions nào trigger plan capture vào STATS$SQL_PLAN?

---

## Exercise 2 — Report Interpretation và Limitation Analysis

### Scenario
Spreport được generate cho period 09:00–10:00 ngày thứ 2. Users báo cáo "database slow" vào khoảng 09:30. DBA cũ không configure AWR (SE2) — Statspack report là duy nhất available.

### Tasks
1. Trong spreport output, identify: DB Time, Elapsed Time, DB CPU — tính DB Wait Time % thủ công và verify với Top 5 Wait Events
2. Từ "SQL ordered by CPU" section: extract HASH_VALUE của top SQL, generate SQL report riêng bằng sprepsql
3. So sánh: SQL A với total DB Time 40%, Execute Count 1 vs SQL B với DB Time 35%, Execute Count 50,000 — tuning priority khác nhau như thế nào?
4. Identify ít nhất một limitation của Statspack cho scenario này: bạn biết incident xảy ra 09:30 nhưng report cover 09:00–10:00 — bạn thiếu gì mà AWR+ASH sẽ cung cấp?

### Expected Findings
- Average Active Sessions = DB Time / Elapsed Time (consistency check)
- Single high-DB-Time SQL với Execute Count=1 → individual statement tuning hoặc one-off issue
- 30-minute granularity cannot isolate 09:30 spike — bạn cần manual snap tại 09:30 (hindsight)
- ASH absence là critical gap: không có per-session second-granularity data

### Debrief Questions
- Tại sao AWR report format dễ navigate hơn spreport mà không phải chỉ là presentation difference?
- Nếu instance restart lúc 09:45 trong report period, spreport sẽ show gì cho affected wait event counts?
- Để isolate incident lúc 09:30, bạn cần gì từ Statspack mà hiện tại chưa có? Có thể implement không?

---

## Exercise 3 — Troubleshooting Scenario *(Expert level)*

### Incident Brief
Production SE2 database. Statspack snapshot mỗi 30 phút. Incident reported lúc 03:45. On-call DBA lấy manual snapshot lúc 03:48. Available snapshots: 03:30, 03:48 (manual), 04:00.

### Evidence Provided

```
-- Statspack snapshot inventory
SNAP_ID   SNAP_LEVEL   SNAP_TIME          BASELINE
45        5            01-APR-24 03:30    N
46        5            01-APR-24 03:48    N   ← manual (on-call DBA)
47        5            01-APR-24 04:00    N

-- spreport trên snap 45→47 (03:30→04:00, 30-minute window):
DB Time:      87.3 minutes
Elapsed Time: 30.0 minutes
DB CPU:        4.1 minutes (4.7% of DB Time)

Top 5 Timed Events:
Event                       Waits    Time(s)   %DB Time
db file sequential read     42,381   2,847.3   54.4%
log file sync                8,234     891.2   17.0%
buffer busy waits            3,102     412.7    7.9%
db file scattered read       1,847     298.4    5.7%
free buffer waits              234      67.1    1.3%

-- spreport trên snap 45→46 (03:30→03:48, 18-minute window):
DB Time:      61.7 minutes
Elapsed Time: 18.0 minutes

Top 5 Timed Events:
Event                       Waits    Time(s)   %DB Time
db file sequential read     31,247   2,208.4   59.7%
log file sync                6,891     801.3   21.7%
buffer busy waits            2,894     391.2   10.6%
db file scattered read          43       5.2    0.1%
free buffer waits                8       2.1    0.1%
```

### Your Mission
1. Tính Average Active Sessions cho cả hai report periods (45→47 và 45→46). Difference ngụ ý gì về severity?
2. `db file scattered read` tăng từ 43 waits (18-min window 45→46) lên 1,847 waits (30-min window 45→47). Điều này nói gì về timing của event gây scattered reads?
3. `free buffer waits` tăng từ 8 lên 234. Relationship với `db file scattered read` spike là gì?
4. Với Statspack level 5 (no ASH, no per-session data): bạn có thể xác định root cause không? Nếu không, bạn thiếu gì cụ thể và sẽ tìm thông tin đó ở đâu?
5. Propose incident timeline hypothesis: gì xảy ra trước 03:48 vs sau 03:48?

### Evaluation Criteria
- Tính đúng Average Active Sessions: period 45→47: 87.3/30 ≈ 2.9; period 45→46: 61.7/18 ≈ 3.4 — period 03:30–03:48 actually heavier per-minute load
- Nhận ra scattered read spike = large full scan workload bắt đầu sau 03:48 (vì data chỉ xuất hiện significant trong 45→47, không có trong 45→46)
- Link `free buffer waits` tăng với scattered read pressure: large scan consuming buffer cache → DBWR không kịp flush → free buffer waits khi sessions cần buffer allocation
- Nhận ra Statspack limitation: không có session-level attribution cho window 03:48–04:00 riêng lẻ — cần V$SESSION snapshot hoặc custom logging để identify specific session
- Hypothesis: batch job hoặc large table scan bắt đầu sau 03:48, gây buffer cache pressure cascade


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/section_all_new/section_11_statspack_senior_guide.md`
