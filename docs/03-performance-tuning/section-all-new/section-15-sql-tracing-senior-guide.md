---
title: Section 15 — SQL Tracing với DBMS_MONITOR — Deep Dive for Senior DBA
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/section_all_new/section_15_sql_tracing_senior_guide.md
---

# Section 15 — SQL Tracing với DBMS_MONITOR — Deep Dive for Senior DBA

---

## 1. Mental Model

SQL Trace là forensic microscope, không phải dashboard. ASH cho bạn statistical sampling ở 1-second resolution — tốt để identify *đâu* đang có vấn đề. tkprof cho bạn exact microsecond accounting cho mọi parse/execute/fetch — tốt để answer *tại sao* một SQL cụ thể chậm.

Trade-off cốt lõi: SQL Trace là targeted activation, không phải passive collection. Bạn phải biết target, turn it on, chạy workload, turn it off. Overhead không negligible — trace file write là synchronous với foreground process. Kỹ năng senior là biết khi nào cần forensic precision (SQL Trace) vs. khi nào statistical approximation (ASH) là đủ. Trong production, bạn thường chỉ có một cơ hội bật trace trước khi stakeholders yêu cầu bạn dừng lại.

---

## 2. Internals & Mechanics

**SQL Trace là 10046 event dưới hood**: DBMS_MONITOR chỉ là API đẹp hơn. Underlying mechanism:

| Method | Equivalent 10046 level |
|---|---|
| SESSION_TRACE_ENABLE(WAITS=FALSE, BINDS=FALSE) | level 1 |
| SESSION_TRACE_ENABLE(WAITS=TRUE, BINDS=FALSE) | level 8 |
| SESSION_TRACE_ENABLE(WAITS=FALSE, BINDS=TRUE) | level 4 |
| SESSION_TRACE_ENABLE(WAITS=TRUE, BINDS=TRUE) | level 12 |

Direct event syntax vẫn hoạt động: `ALTER SESSION SET EVENTS '10046 trace name context forever, level 12'` — nhưng DBA_ENABLED_TRACES **không** capture method này. Nếu developer tự trace session của họ bằng event syntax, bạn sẽ không thấy trong DBA_ENABLED_TRACES.

**Trace file write mechanism**: Khi trace được enable, Oracle ghi trace records trực tiếp vào .trc file trong DIAGNOSTIC_DEST/diag/rdbms/.../trace/ sau mỗi parse, execute, fetch, và wait event completion. Write là synchronous — nếu filesystem I/O chậm, trace itself add overhead vào session được trace. Trên production NFS mounts với high latency, điều này có thể tạo feedback loop.

**TRACEFILE_IDENTIFIER là prefix search key**: `ALTER SESSION SET TRACEFILE_IDENTIFIER = 'PORDERS'` append chuỗi này vào filename: `ORADB_ora_12345_PORDERS.trc`. Không có TRACEFILE_IDENTIFIER, bạn phải identify files bằng PID (từ V$PROCESS.SPID) hoặc timestamp. Trong production trace directory với hàng trăm .trc files, không dùng TRACEFILE_IDENTIFIER là tự tra tấn.

**SERV_MOD_ACT_TRACE_ENABLE là persistent**: Stored trong SYSAUX (DBA_ENABLED_TRACES reads từ dictionary). Survives instance restart. Mọi session mới connect với matching SERVICE_NAME + MODULE_NAME sẽ bị trace tự động — kể cả sau reboot. Đây là khác biệt quan trọng với SESSION_TRACE_ENABLE (trace only existing session, dies khi session disconnect).

**ALTER SYSTEM FLUSH SHARED_POOL trước khi enable module trace**: Lý do trong practice là legitimate nhưng thường không được giải thích kỹ. Nếu có sessions đang chạy với MODULE='PROCESS_ORDERS' đã có cursors parsed và cached trong shared pool, Oracle sẽ không re-parse chúng chỉ vì trace được enable — existing hard-parsed cursors không trigger trace setup. Flush shared pool force re-parse của tất cả cursors → subsequent executions được trace. Đây là destructive operation — không làm trên production OLTP mà không cân nhắc cursor invalidation impact.

**PLAN_STATS parameter (12c+)**: Thường bị bỏ qua trong introductory courses.
- `PLAN_STATS=FIRST_EXECUTION` (default): chỉ capture execution plan lần đầu
- `PLAN_STATS=ALL_EXECUTIONS`: capture plan cho mọi execution

Khi điều tra plan instability (query có execution plan thay đổi mid-run), dùng ALL_EXECUTIONS để verify. tkprof output với ALL_EXECUTIONS sẽ show multiple row source operation blocks cho cùng SQL_ID.

**tkprof aggregation model**: `aggregate=yes` group tất cả executions của cùng cursor (same SQL text) và sum tất cả statistics. Với multi-session trace được merge bằng trcsess, tkprof sum elapsed time từ **tất cả sessions**. Nếu 8 sessions song song mỗi session execute 180 giây, tkprof sẽ show `elapsed = 1440s` — nhưng wall clock chỉ có 180 giây. Senior phải biết divide by session count để có per-session picture.

**trcsess merge là chronological interleave**: trcsess đọc timestamp từ mỗi trace record và merge theo thứ tự thời gian. Nếu system clocks giữa RAC nodes không synchronized, merged trace sẽ có interleaving sai → misleading wait event attribution. Kiểm tra NTP sync trước khi tin vào merged trace từ RAC.

---

## 3. Production Realities

**Trace file size explosion** là risk số 1: WAITS=TRUE trên một session làm I/O heavy operations (full table scans, direct reads) có thể generate trace file GB/hour. BINDS=TRUE thêm bind value cho mỗi execution — với 10,000 executions/minute, trace file grows rất nhanh. Monitor `df -h $DIAGNOSTIC_DEST` trước và trong khi trace. Nếu DIAGNOSTIC_DEST filesystem fill lên 100%, toàn bộ Oracle diagnostic infrastructure bị ảnh hưởng — alert log, trace files của mọi sessions, ADR.

**Forgotten module traces** là silent overhead: Sau incident investigation, DBA thường forget disable SERV_MOD_ACT_TRACE_ENABLE. Check DBA_ENABLED_TRACES monthly trên tất cả production instances. Module traces bị bỏ quên có thể chạy months, tích lũy GBs trace files, và add CPU overhead cho mọi matching session.

**BINDS=TRUE và sensitive data**: Trace files là plaintext trên OS filesystem. Nếu ứng dụng pass passwords, PII, credit card numbers, SSN qua bind variables, những giá trị này sẽ plaintext trong .trc file. Đây là compliance issue (PCI-DSS, HIPAA). Verify với security team trước khi enable BINDS=TRUE trên any production system xử lý sensitive data.

**tkprof "Elapsed times" section interpretation trap**: Mục "Elapsed times include waiting on following events" ở cuối mỗi SQL trong tkprof là **subset** của total elapsed. Total elapsed = CPU + all waits. Nếu tổng wait events < total elapsed − CPU, phần còn lại là overhead không classified (scheduler latency, OS context switches, memory pressure). Đây là common confusion point khi số không cộng lại đúng.

**SYS=no trong tkprof là không negotiate**: Default SYS=yes include tất cả recursive SQL từ Oracle internal operations — dictionary lookups, trigger firing, constraint checking. Trong trace của một complex transaction, recursive SQL có thể chiếm 80% total lines. SYS=no filter chúng ra. Nếu bạn đang diagnose space management issues hoặc recursive trigger overhead, SYS=yes mới có ý nghĩa.

**RAC tracing**: Trace file của một session đi vào node mà session đang connect. Trong RAC với load balancing, cùng một MODULE có thể chạy trên nhiều nodes. SERV_MOD_ACT_TRACE_ENABLE phải được run trên tất cả nodes (hoặc via DBMS_MONITOR.DATABASE_TRACE_ENABLE với extreme caution). Trace files sẽ nằm ở các nodes khác nhau — cần collect từ tất cả nodes trước khi trcsess merge.

---

## 4. Decision Framework

| Tình huống | Method | Trade-off |
|---|---|---|
| Debug specific session ngay bây giờ | SESSION_TRACE_ENABLE(SID, SERIAL#) | Ngay lập tức, precise; session phải đang active |
| Catch session khi nó next connect | SERV_MOD_ACT_TRACE_ENABLE | Không cần timing; persistent — nhớ disable |
| Trace own session để test | ALTER SESSION SET SQL_TRACE hoặc event 10046 | Đơn giản nhất; không cần DBA privilege |
| Diagnose plan instability | SESSION/SERV trace với PLAN_STATS=ALL_EXECUTIONS | Full plan per execution; trace file lớn hơn |
| Diagnose bind variable sensitive issue | BINDS=TRUE | Security review trước; file size tăng mạnh |
| Trace toàn bộ database | DATABASE_TRACE_ENABLE | Emergency only; có thể kill production |
| Post-incident (session đã disconnect) | ASH + V$SQL + DBMS_SQLTUNE | SQL Trace không có retroactive capability |

**Khi nào SQL Trace KHÔNG phải đáp án:**
- Performance issue đã xảy ra và session đã disconnect → ASH
- Identify *which* SQL is the problem (not *why*) → ASH + V$SQL, không cần overhead của trace
- Wide-scope monitoring (nhiều modules cùng lúc) → DBMS_MONITOR aggregation + CLIENT_ID stats
- Real-time monitoring → V$SESSION_LONGOPS, V$SQL_MONITOR

---

## 5. Key SQL / Commands

```sql
-- Tìm trace directory
SELECT VALUE FROM V$DIAG_INFO WHERE NAME = 'Diag Trace';

-- Tìm trace file của một session đang active
-- Dùng ngay sau khi enable trace để ghi lại tên file
SELECT S.SID, S.SERIAL#, S.USERNAME, S.MODULE,
       P.SPID,           -- OS process ID = phần trong tên file
       P.TRACEFILE       -- full path
FROM V$SESSION S
JOIN V$PROCESS P ON S.PADDR = P.ADDR
WHERE S.SID = &target_sid;

-- Enable trace cho session cụ thể (với waits, không binds)
BEGIN
  DBMS_MONITOR.SESSION_TRACE_ENABLE(
    SESSION_ID => :sid,
    SERIAL_NUM => :serial#,
    WAITS      => TRUE,
    BINDS      => FALSE,
    PLAN_STATS => 'ALL_EXECUTIONS'  -- 12c+: capture plan per execution
  );
END;
/

-- Enable trace cho module (persistent — nhớ disable sau)
-- Flush shared pool TRƯỚC để existing cursors được re-parsed
-- Chỉ flush trên non-OLTP environments hoặc trong maintenance window
EXEC DBMS_MONITOR.SERV_MOD_ACT_TRACE_ENABLE(
  SERVICE_NAME => 'ORADB.localdomain',
  MODULE_NAME  => 'PROCESS_ORDERS',
  ACTION_NAME  => DBMS_MONITOR.ALL_ACTIONS,  -- NULL cũng được
  WAITS        => TRUE,
  BINDS        => FALSE
);

-- Audit: tất cả trace đang active (quan trọng để catch forgotten traces)
SELECT TRACE_TYPE,
       PRIMARY_ID,        -- service name
       QUALIFIER_ID1,     -- module name
       QUALIFIER_ID2,     -- action name
       WAITS, BINDS,
       PLAN_STATS
FROM DBA_ENABLED_TRACES;

-- Disable module trace
EXEC DBMS_MONITOR.SERV_MOD_ACT_TRACE_DISABLE(
  SERVICE_NAME => 'ORADB.localdomain',
  MODULE_NAME  => 'PROCESS_ORDERS'
);

-- Tìm trace files lớn nhất trong DIAGNOSTIC_DEST (OS level)
-- Chạy từ shell:
-- find $ORACLE_BASE/diag/rdbms -name "*.trc" -size +100M -ls | sort -k7 -rn | head -20
```

```bash
# Merge trace files của module — chạy từ $TRACE_DIR
trcsess output="$TRACE_DIR/MODULE_MERGED.trc" \
         module="PROCESS_ORDERS"
         # Alternatives: service="...", action="...", session=<sid,serial>

# tkprof production recipe
# SYS=no: bỏ recursive SQL | waits=yes: include wait events (bắt buộc)
# aggregate=yes: sum multiple executions | sort: worst elapsed first
tkprof MODULE_MERGED.trc MODULE_MERGED.txt \
  SYS=no \
  waits=yes \
  aggregate=yes \
  sort="(exeela,prsela,fchela)"

# Đọc output — tìm:
# 1. Top SQL by elapsed (đã sorted)
# 2. Từng SQL: elapsed >> cpu → wait-bound; elapsed ≈ cpu → CPU-bound
# 3. "Elapsed times include waiting on" section → identify wait event
# 4. Row Source Operation → verify plan
```

---

## 6. Senior Checklist

- **Audit DBA_ENABLED_TRACES định kỳ** trước khi bật trace mới — forgotten module traces đang chạy là common; cleanup trước khi add thêm overhead
- **Set TRACEFILE_IDENTIFIER** trước khi enable trace — không có nó, trace files trong production directory của hàng trăm .trc files là kim trong đống rơm
- **Monitor disk space** tại DIAGNOSTIC_DEST trước và trong khi trace heavy workload — trace file size tỷ lệ với I/O volume của session, không phải wall clock time
- **SERV_MOD_ACT_TRACE_ENABLE yêu cầu DISABLE explicit** — không tự-expire; lên lịch reminder để disable ngay sau khi collect đủ data
- **Khi đọc tkprof output của merged multi-session trace**: chia elapsed time cho số sessions để có per-session picture thực tế; sum elapsed từ parallel sessions sẽ khiến số bị inflate
- **FLUSH SHARED_POOL có impact**: nếu cần flush để catch existing cursors, đảm bảo đang trong maintenance window hoặc hệ thống có thể absorb cursor invalidation + re-parse storm
- **Sensitive data check**: verify với security team rằng bind variables của target SQL không chứa PII/credentials trước khi enable BINDS=TRUE trên production

---

---

# Lab: Section 15 — SQL Tracing với DBMS_MONITOR — Hands-on for Senior DBA

## Lab Overview
- **Mục tiêu:** Build end-to-end trace workflow; interpret tkprof output correctly; identify production pitfalls của SERV_MOD_ACT_TRACE_ENABLE
- **Môi trường:** Oracle 12c+ / non-CDB, có DIAGNOSTIC_DEST accessible từ OS
- **Thời gian ước tính:** 60–75 phút
- **Độ khó:** Senior / Expert

---

## Exercise 1 — Single Session Deep-Dive: Elapsed vs. CPU Analysis

### Scenario
Support ticket: "Query `SELECT * FROM ORDERS WHERE CUSTOMER_ID = :cid` chạy mất 8 giây cho customer_id = 1234, nhưng chỉ 0.1 giây cho customer_id = 5678." Developer đã log SQL_ID nhưng không có execution plan history đủ. Cần xác định root cause và liệu đây là plan problem hay data problem.

### Tasks
1. Identify session của developer (giả lập bằng session SOE), lấy SID và SERIAL#; enable SESSION_TRACE_ENABLE với WAITS=TRUE, BINDS=TRUE, PLAN_STATS=ALL_EXECUTIONS
2. Chạy query với customer_id = 1234 (slow) rồi với customer_id = 5678 (fast) trong cùng session; disable trace
3. Chạy tkprof với `sort="(exeela)"` và `SYS=no`; identify query trong output
4. So sánh: (a) elapsed vs. cpu — xác định wait-bound hay CPU-bound, (b) Row Source Operation — plan có khác giữa hai executions không (với ALL_EXECUTIONS), (c) wait events section — event nào chiếm phần lớn elapsed

### Expected Findings
Với BINDS=TRUE, trace file capture giá trị bind variable cho từng execution. Nếu plan giống nhau nhưng elapsed khác xa, likely là data skew (ít rows cho 5678, nhiều rows cho 1234). Nếu Row Source Operation khác nhau giữa 2 executions, đây là adaptive cursor sharing issue. ALL_EXECUTIONS sẽ show multiple plan sections trong tkprof output cho cùng SQL.

### Debrief Questions
- Nếu query này cũng chậm trên 100 other customer_ids, liệu SQL Trace vẫn là tool phù hợp hay có option tốt hơn?
- BINDS=TRUE capture bind value tại thời điểm nào trong execution lifecycle — parse, execute, hay fetch? Implication gì nếu bind value thay đổi mid-cursor?

---

## Exercise 2 — Module Trace Lifecycle và Forgotten Trace Audit

### Scenario
Bạn join một team mới. Trong tuần đầu, bạn notice disk space của DIAGNOSTIC_DEST tăng 4GB/ngày — bất thường với production throughput hiện tại. Không ai biết tại sao. Bạn cần investigate và remediate mà không interrupt production.

### Tasks
1. Query DBA_ENABLED_TRACES để xem tất cả active traces — note TRACE_TYPE, PRIMARY_ID, QUALIFIER_ID1, timestamp enable (nếu có)
2. Tìm trace files mới nhất trong $TRACE_DIR — correlate filename patterns với module names trong DBA_ENABLED_TRACES; estimate growth rate bằng `ls -lt | head -20`
3. Identify module traces có TRACE_TYPE = 'SERVICE_MODULE' hoặc 'SERVICE_MODULE_ACTION' mà không có owner rõ ràng (no active support ticket, no recent incident); propose remediation
4. Disable một forgotten trace; verify DBA_ENABLED_TRACES sau khi disable; estimate disk space saved per day

### Expected Findings
Forgotten module traces là thường gặp hơn tưởng. Một module trace bật cho batch job đã bị deprecated 3 tháng trước có thể vẫn fire khi code path chạy qua. DBA_ENABLED_TRACES không có timestamp enable — không thể biết ai enable và khi nào mà không có external change log.

### Debrief Questions
- DBA_ENABLED_TRACES có persistent qua instance restart không? Nếu yes, implication gì cho DR failover (instance restart trên standby)?
- Nếu DIAGNOSTIC_DEST filesystem fill lên 100%, điều gì xảy ra với Oracle alertlog? Với production sessions?

---

## Exercise 3 — Troubleshooting Scenario *(Expert level)*

### Incident Brief
Batch job `MONTH_END_RPT` (module='MONTH_END_RPT') chạy 3.8 giờ tối qua thay vì 22 phút bình thường. Module trace luôn enabled cho module này (theo policy). Sau khi trcsess merge 6 trace files (6 parallel sessions), tkprof processing xong sau 7 phút. File output 14,000 dòng.

### Evidence Provided

```
-- tkprof output (SYS=no, aggregate=yes, sorted by exeela+fchela) — top 2 SQLs

==== SQL #1 (SQL_ID: f7k2p9r) ====
SELECT A.ACCT_ID, SUM(T.AMOUNT) TOTAL
FROM ACCOUNTS A, TRANSACTIONS T
WHERE A.ACCT_ID = T.ACCT_ID
  AND T.TXN_DATE >= :b_start
  AND T.TXN_DATE < :b_end
GROUP BY A.ACCT_ID

call     count     cpu     elapsed    disk      query    current    rows
Parse        6    0.00        0.01       0          0          0       0
Execute      6    0.00        0.00       0          0          0       0
Fetch        6  190.4s   13,680.0s  245,880  5,040,000        0  46,200

Elapsed times include waiting on following events:
  db file scattered read   30,420 times   0.92s max   13,672s total

Row Source Operation:
HASH JOIN (cr=5040000 pr=245880 pw=0 time=13680000000 us)
  TABLE ACCESS FULL ACCOUNTS (cr=1240 pr=210 ...)
  TABLE ACCESS FULL TRANSACTIONS (cr=5038760 pr=245670 ...)

==== SQL #2 (SQL_ID: 9xm4v8r) ====
UPDATE MONTHLY_SUMMARY SET RPT_TOTAL=:b1 WHERE ACCT_ID=:b2 AND PERIOD=:b3
call     count     cpu    elapsed    disk     query   current    rows
Execute  46,200  280.0s    280.0s       0  184,800  138,600  46,200
Waited on: (none significant)

-- Context:
-- Wall clock time for the job: ~2,280 seconds (38 minutes × 6)... wait
-- Actually wall clock = 3.8 hours = 13,680 seconds
-- Last successful run (prior month): 22 minutes wall clock
-- DBA_HIST_SQL_STATS for SQL f7k2p9r last month: elapsed=240s, disk=1,200, query=180,000
-- Schema stats were refreshed 2 days ago (DBMS_STATS.GATHER_DATABASE_STATS)
-- No DDL changes to TRANSACTIONS table
-- TRANSACTIONS table rows: 480M rows (same as last month per DBA_SEGMENTS)
```

### Your Mission
1. **Reconcile the numbers**: tkprof shows elapsed=13,680s cho SQL #1 với 6 executions, wall clock = 13,680s. Is this coincidence? What does it actually mean about parallelism và session count?
2. **Explain the plan regression**: prior month disk=1,200, query=180,000. This month disk=245,880, query=5,040,000. Cùng SQL, cùng data volume. Identify chính xác cái gì đã thay đổi và mechanism tại sao stats refresh có thể trigger full scan thay vì index range scan — gợi ý: xem xét bind variable peeking behavior và histogram statistics
3. **Identify the smoking gun**: với thông tin hiện có trong tkprof output, bạn có thể confirm root cause không? Nếu không, bạn cần thêm evidence gì — và từ nguồn nào (không cần re-run trace)?
4. **Remediation**: đề xuất ít nhất 2 options với trade-offs về: stability, maintenance overhead, và risk of over-fixing (making things worse for other execution contexts)

### Evaluation Criteria
- Number reconciliation phải address cả hai câu hỏi: (1) tại sao elapsed 6 sessions ≈ wall clock, và (2) tại sao tkprof wall clock cho Exercise scenario này không phải 6× wall clock như Exercise 1 pattern
- Plan regression analysis phải connect stats refresh → histogram change → bind variable peeking → plan selection — không chỉ "stats changed so plan changed"
- Evidence gap analysis phải identify specific view/query để confirm (ví dụ: V$SQL_PLAN_STATISTICS_ALL, DBA_HIST_SQL_PLAN, AWR SQL report) và explain tại sao tkprof alone không đủ
- Remediation options phải include trade-off giữa: SQL Plan Baseline (safe, overhead to manage) vs. DBMS_STATS hint/preference (risky, có thể affect other SQLs) vs. dynamic sampling (phù hợp cho ad-hoc, không phải batch)


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/section_all_new/section_15_sql_tracing_senior_guide.md`
