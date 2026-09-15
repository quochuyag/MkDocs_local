---
title: ADDM (Automatic Database Diagnostic Monitor) — Deep Dive for Senior DBA
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/section_all_new/section_12_addm_senior_guide.md
---

# ADDM (Automatic Database Diagnostic Monitor) — Deep Dive for Senior DBA

## 1. Mental Model

ADDM không phải monitoring tool — đây là engine RCA (Root Cause Analysis) tự động mà Oracle chạy sau mỗi AWR interval. Mental model đúng: ADDM là một expert system áp dụng predefined diagnostic rules lên DB Time attribution tree. Câu hỏi cốt lõi của ADDM: "What was consuming DB Time, and why?" — nó dịch AWR deltas thành finding hierarchy có quantified impact. Đây là giá trị chính của ADDM so với đọc AWR thủ công.

Limitation nằm ngay trong thiết kế: ADDM chỉ giỏi chẩn đoán sustained issues trong AWR interval. Transient spike kéo dài 15 phút trong một interval 60 phút sẽ bị dilute đến mức IMPACT thấp và có thể bị bỏ qua.

---

## 2. Internals & Mechanics

**ADDM execution pipeline:**

```
AWR Snapshot N-1 → AWR Snapshot N (taken by MMON)
                              ↓
              MMON triggers ADDM analysis
                              ↓
       ADDM reads DBA_HIST_* tables for [snap_N-1, snap_N]
                              ↓
       Applies rule-based heuristics against DB Time model
       (V$SYS_TIME_MODEL history in DBA_HIST_SYS_TIME_MODEL)
                              ↓
       Results stored in Oracle Advisor Framework
```

ADDM dùng chung Advisor Framework với SQL Tuning Advisor, Segment Advisor, và các advisors khác — đây là lý do DBA_ADVISOR_RECOMMENDATIONS được share giữa các loại advisor (luôn filter theo TASK_ID khi query).

**Object hierarchy:**

```
DBA_ADDM_TASKS                  — one row per ADDM run
    ↓ TASK_ID
DBA_ADDM_FINDINGS               — IMPACT = estimated % DB Time reduction
    ↓ TASK_ID + FINDING_ID
DBA_ADVISOR_RECOMMENDATIONS     — one or more recommendations per finding
    ↓ TASK_ID + REC_ID
DBA_ADVISOR_ACTIONS             — concrete actions (COMMAND, ATTR1-6, NUM_ATTR1-5)
```

**Task naming convention:** `ADDM:<DBID>_<instance#>_<end_snap_id>`

- DBID: identifies the database (critical khi có multiple databases trong MOS)
- Instance#: trong RAC, mỗi instance có ADDM task riêng
- End snap ID: snapshot kết thúc interval được phân tích

**Finding IMPACT semantics:** IMPACT là estimated % DB Time reduction nếu fixing được finding đó — derived từ DB Time attribution model, không phải đo thực nghiệm. IMPACT=40% không đảm bảo 40% performance improvement sau khi fix.

**ADDM Comparison Report mechanics:**

- `DBMS_ADDM.COMPARE_INSTANCES()` generates HTML report (dùng Flash trong các version cũ — không render được trên Chrome/Firefox hiện đại)
- SQL Commonality = % SQL trong comparison period cũng tồn tại trong baseline period
- Commonality < 80% → workload đã thay đổi → comparison trở thành apples-to-oranges
- So sánh hoạt động ở snapshot-pair granularity — không phân tích sub-interval spikes

---

## 3. Production Realities

**Misleading recommendations — pattern recognition:**

| ADDM Recommendation | Thực ra thường có nghĩa là |
|---------------------|---------------------------|
| "Add more CPUs or additional hosts" | Check missing indexes causing full scans; SQL plan regression; một vài sessions chiếm quá nhiều CPU |
| "Increase DB cache size" | Buffer cache pressure — trước tiên check xem có vài SQLs với logical reads cao bất thường không |
| "Increase shared pool" | Hard parse rate cao — investigate SQL dùng literal values thay vì bind variables trước khi touch SGA |
| "Reduce I/O" | Could mean missing index, full scan, hoặc storage issue — không thể hành động mà không drill deeper |

Quy tắc: ADDM pointing là điểm bắt đầu điều tra, không phải chỉ thị hành động.

**Version-specific behaviors:**

- Pre-19c: ADDM chỉ chạy ở CDB level. Để phân tích PDB-specific, phải connect trực tiếp vào PDB và chạy `addmrpt.sql`
- 19c+: Khi `AWR_PDB_AUTOFLUSH_ENABLED = TRUE`, mỗi PDB có AWR và ADDM riêng
- 12.1–18c: Comparison report dùng Flash → cần Internet Explorer để render. Trong 19c+ report format cải thiện
- 12.2+: `DBA_ADDM_TASKS` có thêm column `CON_ID` để distinguish CDB vs PDB tasks

**RAC-specific traps:**

- Mỗi RAC instance có ADDM tasks riêng — `DBA_ADDM_TASKS` có `INSTANCE_NUMBER` column
- ADDM không correlate cross-instance issues: gc buffer busy trên instance 1 ảnh hưởng instance 2 sẽ xuất hiện như 2 findings riêng biệt
- Để cross-instance analysis: dùng AWR Global Reports hoặc GV$ACTIVE_SESSION_HISTORY

**ADDM blind spots:**

- Intra-snapshot transient issues: spike 15 phút trong 60 phút interval → IMPACT bị dilute ~4x, có thể drop below visible threshold
- Connection storm: rapid connect/disconnect không được captured well trong time-averaged metrics
- Intra-PL/SQL block attribution: DML bên trong PL/SQL block đôi khi bị attributed sang block thay vì individual statement — misleading trong "Top SQL" findings

---

## 4. Decision Framework

| Tình huống | Dùng gì | Lý do |
|-----------|---------|-------|
| First-pass analysis sau incident | ADDM | Quantified impact, structured findings — nhanh hơn đọc raw AWR |
| Transient spike < 30 phút | ASH Report | ADDM không capture intra-interval events đủ rõ |
| So sánh pre/post change | ADDM Comparison | Yêu cầu SQL Commonality > 80% và baseline đã prepare sẵn |
| Deep SQL analysis | AWR SQL Report + ASH | ADDM findings chỉ pointing; drill vào SQL-level data riêng |
| RAC cross-instance issues | AWR Global / ASH GV$ | ADDM is per-instance only |
| Ongoing regression sau deployment | ADDM Comparison + AWR SQL Baseline | Compare pre/post với matching workload |

**Anti-patterns:**

- Implement ADDM recommendations mà không verify root cause — đặc biệt "Increase SGA" type
- Chạy comparison report khi SQL Commonality < 70% — kết quả statistically unreliable
- Xem ADDM STATUS = 'COMPLETED' là xác nhận không có vấn đề — COMPLETED chỉ nghĩa là task chạy xong, không phải system ổn

---

## 5. Key SQL / Commands

```sql
-- Recent ADDM tasks: task ID, status, finding count, time of execution
SELECT TASK_ID,
       TASK_NAME,
       STATUS,
       ACTIVITY_COUNTER,
       RECOMMENDATION_COUNT,
       TO_CHAR(EXECUTION_START, 'DD-MON HH24:MI') EXEC_START
FROM DBA_ADDM_TASKS
ORDER BY TASK_ID DESC
FETCH FIRST 10 ROWS ONLY;

-- Findings for a task, sorted by impact (filter out low-impact noise)
SELECT FINDING_ID,
       FINDING_NAME,
       TYPE,
       IMPACT_TYPE,
       ROUND(IMPACT, 1)        IMPACT_PCT,
       SUBSTR(MESSAGE, 1, 120) MESSAGE
FROM DBA_ADDM_FINDINGS
WHERE TASK_ID  = &V_TASK_ID
  AND IMPACT   > 5            -- skip findings below 5% impact
ORDER BY IMPACT DESC;

-- Recommendations + actions joined (the most useful ADDM query in practice)
SELECT F.FINDING_NAME,
       ROUND(F.IMPACT, 1)                          IMPACT_PCT,
       R.TYPE                                      REC_TYPE,
       R.RANK,
       ROUND(R.BENEFIT, 1)                         BENEFIT_PCT,
       SUBSTR(A.MESSAGE, 1, 150)                   ACTION_DETAIL
FROM DBA_ADDM_FINDINGS         F
JOIN DBA_ADVISOR_RECOMMENDATIONS R
  ON F.TASK_ID = R.TASK_ID AND F.FINDING_ID = R.FINDING_ID
JOIN DBA_ADVISOR_ACTIONS         A
  ON R.TASK_ID = A.TASK_ID AND R.REC_ID = A.REC_ID
WHERE F.TASK_ID = &V_TASK_ID
ORDER BY F.IMPACT DESC, R.RANK;

-- Generate text ADDM report (only text format supported by GET_TASK_REPORT)
SET LONG 1000000 LONGCHUNKSIZE 1000000
SET LINESIZE 1000 PAGESIZE 0 TRIM ON TRIMSPOOL ON ECHO OFF FEEDBACK OFF
SPOOL /tmp/addm_report.txt
SELECT DBMS_ADVISOR.GET_TASK_REPORT('&V_TASK_NAME')
FROM DBA_ADVISOR_TASKS
WHERE TASK_ID = &V_TASK_ID;
SPOOL OFF

-- Run ADDM manually across a specific snapshot range
@$ORACLE_HOME/rdbms/admin/addmrpt.sql

-- ADDM comparison report between baseline and test period (HTML output)
SET LONG 1000000 LONGCHUNKSIZE 1000000
SET LINESIZE 1000 PAGESIZE 0 TRIM ON TRIMSPOOL ON ECHO OFF FEEDBACK OFF
SPOOL /tmp/addm_compare_report.html

SELECT DBMS_ADDM.COMPARE_INSTANCES(
           BASE_INSTANCE_ID   => 1,
           BASE_BEGIN_SNAP_ID => &base_begin,
           BASE_END_SNAP_ID   => &base_end,
           COMP_INSTANCE_ID   => 1,
           COMP_BEGIN_SNAP_ID => &comp_begin,
           COMP_END_SNAP_ID   => &comp_end,
           REPORT_TYPE        => 'HTML') AS report
FROM dual;

SPOOL OFF
```

---

## 6. Senior Checklist

- [ ] Filter `DBA_ADDM_FINDINGS` với `IMPACT > 10%` — findings dưới ngưỡng này thường là noise trong production
- [ ] Cross-reference ADDM findings với AWR Top 10 Foreground Events — nếu không align, có thể ADDM misattribution
- [ ] Trước khi accept bất kỳ recommendation nào: trace back to root cause qua V$SQL / ASH — không implement blindly
- [ ] Trong RAC: luôn query `DBA_ADDM_TASKS` với `INSTANCE_NUMBER` filter; đừng assume single-instance ADDM cover toàn bộ
- [ ] ADDM Comparison: verify SQL Commonality > 80% trước khi dùng comparison findings cho production decisions
- [ ] ADDM là mù với transient issues < 30 phút trong 60-phút interval — complement với ASH report
- [ ] Khi ADDM recommend tăng memory: check `V$DB_CACHE_ADVICE`, `V$LIBRARY_CACHE`, `V$SGAINFO` trước để quantify expected gain

---

# Lab: ADDM — Hands-on for Senior DBA

## Lab Overview

- **Mục tiêu:** Diagnose performance incidents bằng ADDM findings + correlation với AWR; đánh giá khi nào ADDM đủ và khi nào cần escalate sang ASH
- **Môi trường:** Oracle 12.2+ / CDB or non-CDB; SOE schema under Swingbench OLTP load
- **Thời gian ước tính:** 60 phút
- **Độ khó:** Senior

---

## Exercise 1 — Translating ADDM Findings to Root Cause

### Scenario

Hệ thống OLTP production SLA < 200ms. Sau release code mới vào thứ Hai, ADDM task của interval 14:00–15:00 báo hai findings:
1. "Hard Parse" — IMPACT: 34% — "Hard parsing of SQL statements was consuming significant database time"
2. "Top SQL by DB Time" — SQL_ID: `9fx2k...` — IMPACT: 22%

### Tasks

1. Query `DBA_ADDM_FINDINGS` và `DBA_ADVISOR_RECOMMENDATIONS` để lấy recommended actions cho cả hai findings
2. Lấy stats của SQL_ID từ finding #2 trong `V$SQLAREA`: `PARSE_CALLS`, `VERSION_COUNT`, `EXECUTIONS`, `SQL_TEXT`
3. Tính parse ratio: PARSE_CALLS / EXECUTIONS — xác định có phải hard parse mỗi lần execute không
4. Kiểm tra `VERSION_COUNT` > 10 trong `V$SQL` để identify cursor proliferation
5. Từ evidence trên, xác định nguyên nhân và đề xuất fix cụ thể

### Expected Findings

- PARSE_CALLS ≈ EXECUTIONS → hard parse mỗi lần execute → không reuse cursor
- VERSION_COUNT cao (>10) → cursor proliferation từ non-bind-variable SQL với nhiều literal values
- SQL text chứa literal values thay vì bind variables (dấu hiệu từ developer mới)

### Debrief Questions

- Tại sao ADDM report hai findings riêng biệt thay vì gộp? "Hard Parse" finding và "Top SQL" finding có phải cùng một vấn đề không?
- Nếu fix non-bind-variable SQL, IMPACT reduction thực tế có khớp với ADDM estimated 34% không? Tại sao có thể không?

---

## Exercise 2 — ADDM Comparison for Post-Change Validation

### Scenario

Sau hardware upgrade (RAM 64GB → 128GB, SGA tăng tương ứng), management yêu cầu bằng chứng cụ thể về performance improvement. Bạn có AWR baseline `OLTP_NORMAL` được tạo trước khi upgrade (cùng business hours, thứ Tư 10:00–11:00).

### Tasks

1. Query `DBA_HIST_BASELINE` để lấy `START_SNAP_ID`, `END_SNAP_ID` của `OLTP_NORMAL`
2. Lấy snapshot IDs của post-upgrade period (cùng thứ Tư 10:00–11:00, tuần tiếp theo)
3. Generate HTML comparison report bằng `DBMS_ADDM.COMPARE_INSTANCES()`
4. Trong report: kiểm tra SQL Commonality, Average Active Sessions của cả hai periods, Top Findings
5. Đánh giá: nếu SQL Commonality = 68%, report có còn valid không? Bạn làm gì tiếp?

### Expected Findings

- Average Active Sessions post-upgrade thấp hơn nếu upgrade có effect (đặc biệt sau khi SGA buffer cache tăng)
- Buffer Cache miss rate improvement xuất hiện trong resource section
- SQL Commonality có thể < 100% nếu workload pattern thay đổi (new code deployed, different query mix)

### Debrief Questions

- SQL Commonality 68% — bạn sẽ explain kết quả comparison như thế nào cho management? Nên refine baseline hay accept limitation?
- ADDM comparison cho thấy I/O cải thiện 15% nhưng user vẫn report response time không đổi — ít nhất 3 explanations là gì?

---

## Exercise 3 — Troubleshooting Scenario *(Expert level)*

### Incident Brief

Thứ Tư 09:15: Monitoring alert DB response time tăng 3x trong 20 phút. Swingbench OLTP load bình thường (400 TPS). Incident kéo dài đến 09:35 rồi tự resolve. DBA on-call không thực hiện bất kỳ action nào.

Bạn điều tra lúc 10:30.

### Evidence Provided

**ADDM Task — interval 09:00–10:00 (60 phút):**

```
ADDM:1834729183_1_4521 — STATUS: COMPLETED
ACTIVITY_COUNTER: 3   RECOMMENDATION_COUNT: 3

Finding 1: "Unusual db file sequential read Wait" — IMPACT: 8%
Finding 2: "SQL statements consuming significant database time" — IMPACT: 12%
Finding 3: "Individual database segments responsible for significant I/O" — IMPACT: 9%
  Recommendation: Consider using ALTER TABLE SOE.ORDERS SHRINK SPACE
```

**AWR Report — same 09:00–10:00 interval:**

```
Top 5 Foreground Events:
  db file sequential read:  12,847 waits   avg 2.3ms   4.7% DB Time
  CPU time:                                            61.3% DB Time
  db file scattered read:    1,203 waits   avg 8.1ms   1.6% DB Time
  log file sync:             3,891 waits   avg 0.4ms   0.2% DB Time
  enq: TX - row lock:           18 waits   avg 1.2s    0.3% DB Time
```

### Your Mission

1. Tại sao ADDM total IMPACT chỉ ~29% trong khi users thấy 3x slowdown kéo dài 20 phút?
2. Finding #3 recommend SHRINK SPACE trên SOE.ORDERS — đây có phải root cause của incident không?
3. CPU 61.3% DB Time vs I/O findings — có gì mâu thuẫn ở đây?
4. Cần thêm data gì để confirm root cause của 09:15–09:35 spike?
5. Plan phòng ngừa nếu không có thêm evidence nào khác

### Evaluation Criteria

- Identify ADDM time-averaging limitation: 20-phút spike trong 60-phút interval → IMPACT bị dilute xuống ~1/3 của actual severity
- Nhận ra contradiction: workload 61.3% CPU-dominant không phải I/O-bound → I/O findings (8–9%) là secondary symptom, không phải root cause
- Đề xuất ASH analysis cho exactly 09:15–09:35 với Activity Over Time để isolate spike cause
- Evaluate SHRINK SPACE recommendation critically: row migration vs fragmentation? Verify via DBA_EXTENTS trước khi execute (SHRINK là online DDL nhưng có locking implications)
- Red herring detection: `enq: TX - row lock` (18 waits, 0.3%) không phải cause của CPU spike — too few waits

---

*Self-check: Lecture Notes expose ADDM limitation và misleading recommendation patterns không có trong Oracle docs standard. Lab Ex3 có intentional contradiction (CPU-dominant + I/O recommendation) để force critical thinking. Tone: peer conversation throughout.*


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/section_all_new/section_12_addm_senior_guide.md`
