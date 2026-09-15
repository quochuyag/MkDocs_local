---
title: 'Section 17 — Automated Maintenance Tasks: Deep Dive for Senior DBA'
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/section_all_new/section_17_automated_maintenance_senior_guide.md
---

# Section 17 — Automated Maintenance Tasks: Deep Dive for Senior DBA

---

## OUTPUT 1 — LECTURE NOTES

---

## 1. Mental Model

Automated Maintenance Tasks là Oracle's self-management layer — ba tasks chạy trong predefined Scheduler Windows để keep database healthy mà không cần DBA manual intervention. Frame nó như "Oracle's internal housekeeping crew": họ làm việc trong những giờ được phép (windows), và nếu windows không đủ dài hoặc bị set nhầm giờ, housekeeping bị incomplete → performance degradation tích lũy.

DBA's role không phải là chạy các tasks này thủ công — đó là **ensure the windows are properly sized** cho production workload, **verify tasks are completing** (không bị truncated), và **intervene khi auto tasks conflict với business-critical jobs**. Lý do phổ biến nhất dẫn đến bad query plans trong production: stats job bị truncated vì window quá ngắn → stale stats → optimizer chọn wrong plan.

---

## 2. Internals & Mechanics

**Three default tasks và Window Groups**:
| Task | CLIENT_NAME | Window Group |
|------|-------------|--------------|
| Auto Optimizer Stats | `auto optimizer stats collection` | `ORA$AT_WGRP_OS` |
| Auto Space Advisor | `auto space advisor` | `ORA$AT_WGRP_SA` |
| SQL Tuning Advisor | `sql tuning advisor` | `ORA$AT_WGRP_SQ` |

Mỗi task có Window Group riêng, nhưng các default Scheduler Windows (MONDAY_WINDOW, TUESDAY_WINDOW...) thuộc trong **tất cả** ba groups. Modify một window ảnh hưởng đến cả ba tasks nếu window đó shared.

**Window anatomy**: Window = REPEAT_INTERVAL (khi nào mở) + DURATION (kéo dài bao lâu). Weekday windows: 22:00, 4 giờ. Weekend windows: 06:00, 20 giờ. Khi window mở, Scheduler tạo job instance cho mỗi task thuộc window group đó.

**Task execution flow**: Window opens → DBMS_SCHEDULER creates a job instance (ephemeral job, không phải permanent job) → chạy trong SYS context với background process → nếu window đóng trước khi task complete, task bị killed gracefully. Remaining work picked up at next window.

**Auto Stats internals**: `DBMS_STATS.GATHER_DATABASE_STATS_JOB_PROC` (internal proc) chạy trong background. Priority algorithm: tables với stale stats (>10% rows changed, controlled by STALE_PERCENT) > never-collected > near-stale. Khi job bị truncated, high-priority tables đã done, lower-priority tables skip → các tables ít DML nhưng critical vẫn có fresh stats; các tables large với heavy DML có thể bị skip.

**Incremental stats on partitioned tables**: Khi `DBMS_STATS.SET_TABLE_PREFS(schema, table, 'INCREMENTAL', 'TRUE')`, Oracle maintain synopsis per partition. Stats job thời gian lâu hơn vì phải maintain synopsis. Benefit: chỉ gather stats cho changed partitions, không re-scan entire table. Net effect: nếu many partitions change, incremental có thể tốn **nhiều hơn** global scan. Evaluate case-by-case.

**SQL Tuning Advisor auto task**: Analyze top SQL từ AWR Workload Capture. Generate SQL Profiles (không SQL Plan Baselines). Auto-apply của SQL Profile: default OFF. Nếu ON (`ACCEPT_SQL_PROFILES = TRUE`), có risk: Profile được accept sau một workload sample có thể degrade performance nếu workload thay đổi. [⚠️ verify with MOS: auto-apply behavior in 19c]

---

## 3. Production Realities

**Window timing conflict với batch jobs**: Pattern thường gặp nhất — stats window mở lúc 22:00, batch ETL cũng chạy từ 22:00 đến 02:00. Hai jobs compete I/O → stats job incomplete, ETL chạy chậm. Fix: shift stats window sang 02:00 hoặc 06:00 sau khi ETL xong. Check `DBA_AUTOTASK_CLIENT.MAX_DURATION_LAST_30_DAYS` để estimate window cần bao nhiêu giờ.

**Stats truncation silent failure**: Task bị kill khi window đóng không generate error — không có alert, không có ORA- error. DBA phải proactively query `DBA_AUTOTASK_OPERATION` hoặc check `DBA_SCHEDULER_JOB_LOG` để verify completion. Silent failure này là nguyên nhân của nhiều "mysterious plan regressions" sau periods với compressed maintenance windows.

**Disabling SQL Tuning Advisor in non-licensed environments**: SQL Tuning Advisor yêu cầu Tuning Pack license. Nếu chưa licensed, task vẫn chạy nhưng writes to SYSAUX, consume resources, và technically in violation. Disable: `DBMS_AUTO_TASK_ADMIN.DISABLE(client_name => 'sql tuning advisor', operation => NULL, window_name => NULL)`. Preferred 12c+ API thay vì manipulate Scheduler directly.

**DBMS_SCHEDULER.DISABLE requirement trước SET_ATTRIBUTE**: Oracle enforce: window phải disabled trước khi modify attributes. Nếu window đang trong middle of executing job, DISABLE sẽ wait hoặc fail. Sequence trong production: check `DBA_SCHEDULER_RUNNING_JOBS` trước khi disable.

**ASMM/AMM interaction**: Khi stats job chạy, nó tạo large sorts và hash operations (internal aggregation). Với AMM, Oracle có thể temporarily transfer memory từ Buffer Cache → PGA để accommodate stats job. Thấy spikes trong V$PGASTAT.AGGREGATE_PGA_TARGET_USED trong maintenance window là normal.

---

## 4. Decision Framework

| Tình huống | Action |
|-----------|--------|
| Batch ETL conflicts với maintenance window | Shift window sau batch; kiểm tra MEAN_JOB_DURATION để size new window |
| Stats job consistently truncated | Extend DURATION của relevant windows; check MAX_DURATION_LAST_30_DAYS |
| SQL Tuning Advisor không licensed | `DBMS_AUTO_TASK_ADMIN.DISABLE('sql tuning advisor', NULL, NULL)` |
| Need fresh stats ngay (không chờ window) | `DBMS_STATS.GATHER_TABLE_STATS` manual; CONCURRENT = TRUE cho parallel gathering |
| Auto-apply SQL Profile risky | Set `ACCEPT_SQL_PROFILES = FALSE` trong SQL Tuning Advisor task parameters |
| Auto Space Advisor tốn resources trong VLDB | Narrow window hoặc disable nếu DBA manually managing space |
| Window không đủ cho weekend catch-up | Extend SATURDAY_WINDOW/SUNDAY_WINDOW duration; weekend windows mặc định 20h nhưng có thể cần hơn trong VLDB |

**Anti-patterns**:
- Disable stats job hoàn toàn để "fix" performance issues → short-term relief, long-term stale stats accumulation
- Set DURATION quá dài (24h+) → window overlap với next window open → undefined behavior
- Modify window ngay trước window opens (race condition với Scheduler)

---

## 5. Key SQL / Commands

```sql
-- 1. Xem tất cả automated tasks và recent performance
SELECT 'CLIENT_NAME: '               || CLIENT_NAME               || CHR(10) ||
       'STATUS: '                     || STATUS                     || CHR(10) ||
       'WINDOW_GROUP: '               || WINDOW_GROUP               || CHR(10) ||
       'MEAN_JOB_DURATION: '          || MEAN_JOB_DURATION          || CHR(10) ||
       'MAX_DURATION_LAST_7_DAYS: '   || MAX_DURATION_LAST_7_DAYS   || CHR(10) ||
       'MAX_DURATION_LAST_30_DAYS: '  || MAX_DURATION_LAST_30_DAYS  AS "Task Info"
FROM DBA_AUTOTASK_CLIENT;

-- 2. Xem window schedule của một task (replace group name)
SELECT WINDOW_NAME, REPEAT_INTERVAL, DURATION, ENABLED
FROM DBA_SCHEDULER_WINDOWS
WHERE '"SYS"."' || WINDOW_NAME || '"' IN (
    SELECT MEMBER_NAME
    FROM DBA_SCHEDULER_GROUP_MEMBERS
    WHERE GROUP_NAME = 'ORA$AT_WGRP_OS'  -- OS=stats, SA=space, SQ=SQL Tuning
)
ORDER BY NEXT_START_DATE;

-- 3. Modify window: Disable → Set → Enable
BEGIN
    DBMS_SCHEDULER.DISABLE(NAME => 'MONDAY_WINDOW');
    DBMS_SCHEDULER.SET_ATTRIBUTE(
        NAME      => 'MONDAY_WINDOW',
        ATTRIBUTE => 'DURATION',
        VALUE     => NUMTODSINTERVAL(6, 'hour')  -- extend to 6 hours
    );
    DBMS_SCHEDULER.SET_ATTRIBUTE(
        NAME      => 'MONDAY_WINDOW',
        ATTRIBUTE => 'REPEAT_INTERVAL',
        VALUE     => 'freq=daily;byday=MON;byhour=2;byminute=0;bysecond=0'  -- shift to 02:00
    );
    DBMS_SCHEDULER.ENABLE(NAME => 'MONDAY_WINDOW');
END;
/

-- 4. Disable/Enable task (12c+ preferred API)
EXEC DBMS_AUTO_TASK_ADMIN.DISABLE('sql tuning advisor', NULL, NULL);
EXEC DBMS_AUTO_TASK_ADMIN.ENABLE('sql tuning advisor', NULL, NULL);

-- 5. Job execution history (last 10 runs per task)
SELECT TO_CHAR(LOG_DATE,'DD-MM-YYYY HH24:MI:SS') LOG_DATE,
       JOB_NAME, OPERATION, STATUS
FROM DBA_SCHEDULER_JOB_LOG
WHERE JOB_NAME LIKE 'ORA$AT%OS%'  -- OS=stats; SA=space; SQ=SQL Tuning
ORDER BY LOG_DATE DESC
FETCH FIRST 20 ROWS ONLY;

-- 6. Check stale tables waiting for next stats gather
SELECT OWNER, TABLE_NAME, LAST_ANALYZED, STALE_STATS, NUM_ROWS
FROM DBA_TAB_STATISTICS
WHERE STALE_STATS = 'YES'
  AND OWNER NOT IN ('SYS','SYSTEM')
ORDER BY NUM_ROWS DESC NULLS LAST;

-- 7. Verify window duration vs task duration risk
SELECT C.CLIENT_NAME,
       NUMTODSINTERVAL(EXTRACT(HOUR FROM C.MAX_DURATION_LAST_30_DAYS)*3600 +
                       EXTRACT(MINUTE FROM C.MAX_DURATION_LAST_30_DAYS)*60 +
                       EXTRACT(SECOND FROM C.MAX_DURATION_LAST_30_DAYS), 'SECOND') TASK_MAX,
       W.DURATION WINDOW_DURATION,
       CASE WHEN C.MAX_DURATION_LAST_30_DAYS > W.DURATION
            THEN '⚠️  TASK EXCEEDS WINDOW'
            ELSE 'OK'
       END STATUS
FROM DBA_AUTOTASK_CLIENT C
JOIN DBA_SCHEDULER_WINDOWS W ON W.WINDOW_NAME = 'MONDAY_WINDOW'  -- check representative window
WHERE C.STATUS = 'ENABLED';
```

---

## 6. Senior Checklist

1. Monthly: query `DBA_AUTOTASK_CLIENT.MAX_DURATION_LAST_30_DAYS` và compare với window DURATION — nếu task max > window duration → truncation đang xảy ra
2. Check `DBA_SCHEDULER_JOB_LOG` sau major batch scheduling changes — verify maintenance tasks still completing with STATUS = 'SUCCEEDED'
3. Sau database upgrade hoặc large data load: manual `DBMS_STATS.GATHER_DATABASE_STATS` để không chờ next window
4. Verify `DBMS_STATS.GET_PREFS('STALE_PERCENT')` — default 10%, có thể quá high cho tables với targeted DML (always same 1% của rows changed → never considered stale despite plan impact)
5. SQL Tuning Advisor auto-apply SQL Profile: check `DBA_SQL_PROFILES` sau maintenance window — nếu auto-apply enabled, verify accepted profiles không degrade production queries
6. Trong CDB: maintenance tasks chạy từ CDB root, gather stats cho ALL PDBs. Ensure windows adequate cho total database, không chỉ một PDB
7. Sau incident của "bad plan sau weekend": đầu tiên check `DBA_TAB_STATISTICS.LAST_ANALYZED` và `DBA_SCHEDULER_JOB_LOG` xem stats job có complete không

---

## OUTPUT 2 — LAB EXERCISES

---

# Lab: Section 17 — Automated Maintenance Tasks

## Lab Overview

- **Mục tiêu:** Diagnose maintenance window sizing issues và manage task conflicts với production workload
- **Môi trường:** Oracle 12c–19c / non-CDB hoặc CDB
- **Thời gian ước tính:** 40 phút
- **Độ khó:** Senior / Expert

---

## Exercise 1 — Window Sizing Audit

### Scenario
DBA mới tiếp nhận production system. Trong tháng qua, users báo cáo "query plans thay đổi ngẫu nhiên, đặc biệt sau cuối tuần." DBA nghi ngờ stats collection không hoàn chỉnh. Nhiệm vụ: verify maintenance window adequacy.

### Tasks
1. Query `DBA_AUTOTASK_CLIENT` lấy `MAX_DURATION_LAST_30_DAYS` cho tất cả tasks
2. Query `DBA_SCHEDULER_WINDOWS` lấy DURATION của các weekday windows
3. Compare: có task nào consistently exceed window duration không?
4. Query `DBA_SCHEDULER_JOB_LOG` tìm STOPPED (không phải SUCCEEDED) status trong 30 ngày qua

### Expected Findings
- Nếu stats job MAX_DURATION_LAST_30_DAYS > window DURATION → truncation confirmed → correlate với stale stats dates trong `DBA_TAB_STATISTICS`
- Job log shows STATUS = 'STOPPED' khi window closes mid-execution — đây là evidence rõ nhất
- Tables với highest STALE_STATS frequency → candidates cho manual gather hoặc incremental stats

### Debrief Questions
- `MAX_DURATION_LAST_30_DAYS` là max, không phải average. Trong scenario nào max có thể misleading (ví dụ: một ngày outlier sau full DR test)?
- Nếu tăng window duration có thể conflict với early morning batch: approach nào để balance?

---

## Exercise 2 — Task Conflict Resolution

### Scenario
ETL batch chạy mỗi đêm từ 23:00–03:00. Stats job chạy từ 22:00. Sau khi investigate, DBA confirm cả hai overlap và ETL slowdown correlates chính xác với stats job active period. Business requires ETL complete by 03:30.

### Tasks
1. Identify windows đang conflict (MONDAY_WINDOW qua FRIDAY_WINDOW) với ETL schedule
2. Modify weekday windows: shift start time từ 22:00 sang 03:30, duration từ 4h sang 5h
3. Verify SATURDAY_WINDOW/SUNDAY_WINDOW đủ dài để compensate cho shorter weekday windows
4. Query `DBA_TAB_STATISTICS` để estimate backlog: bao nhiêu tables hiện stale sau change?

### Expected Findings
- Sau shift sang 03:30 start: ETL không còn compete với stats job → ETL throughput improves
- Weekend windows (20h default) có capacity để catch up accumulated stale stats
- Tables với high DML frequency sẽ accumulate stale stats giữa weekday windows — acceptable nếu weekend catch-up đủ

### Debrief Questions
- Database ở timezone UTC nhưng business hours là Vietnam (UTC+7). REPEAT_INTERVAL trong DBMS_SCHEDULER dùng timezone nào?
- Nếu một table bị modify liên tục 24/7 (ví dụ: audit log table), window-based stats gathering có adequate không?

---

## Exercise 3 — Troubleshooting Scenario *(Expert level)*

### Incident Brief
Production system, 19c, CDB với 3 PDBs. Thứ Hai sáng (9:00), DBA nhận complaint: "Query `MONTHLY_REVENUE_SUMMARY` chạy 45 phút, trước đây 3 phút." DBA check `DBA_HIST_SQLSTAT` và thấy `PLAN_HASH_VALUE` thay đổi lúc 06:47 sáng nay.

### Evidence Provided

```
DBA_SCHEDULER_JOB_LOG (last 5 entries, PDB: PROD_PDB):
  LOG_DATE              JOB_NAME                STATUS
  2026-04-21 22:00:12   ORA$AT_OS_WEDN_4928     SUCCEEDED
  2026-04-22 22:00:08   ORA$AT_OS_THUR_5021     STOPPED      ← Thursday window
  2026-04-23 22:00:05   ORA$AT_OS_FRID_5118     STOPPED      ← Friday window
  2026-04-25 06:00:31   ORA$AT_OS_SATU_5234     SUCCEEDED
  2026-04-26 06:00:29   ORA$AT_OS_SUND_5318     SUCCEEDED

DBA_TAB_STATISTICS for REVENUE_FACT table:
  LAST_ANALYZED: 2026-04-26 10:14:52
  NUM_ROWS:      892,000,000
  STALE_STATS:   NO

DBA_HIST_SQLSTAT for MONTHLY_REVENUE_SUMMARY:
  SNAP_ID  END_TIME         PLAN_HASH_VALUE  ELAPSED_S
  14823    2026-04-26 02:00  1892047312        178
  14824    2026-04-27 06:00  1892047312        183
  14825    2026-04-27 09:00  3741829054      2,847   ← plan change

V$SQL for new plan:
  ROWS_PROCESSED: 892000000 (full table)
  OPTIMIZER_COST: 2,400,000
```

### Your Mission
1. Trace exact sequence of events: stats updated WHEN, plan changed WHEN, complaint arrived WHEN
2. Explain why plan change happened at 06:47 specifically (not during Saturday window, not during Sunday window)
3. Identify what changed in stats that caused plan regression
4. Propose immediate fix (không touch stats) và permanent prevention

### Evaluation Criteria
- **Timeline reconstruction**: Thursday+Friday windows STOPPED → stats stale. Saturday window: SUCCEEDED 06:00–10:14 → REVENUE_FACT stats freshly gathered (LAST_ANALYZED 10:14). New stats → next execution after 10:14 sees new statistics → plan re-evaluated → new PLAN_HASH_VALUE
- **Root cause ambiguity**: New stats should normally improve plans, not degrade. Must investigate: (a) new histogram on skewed column → bind peeking now picks worse plan for common bind value; (b) stats show larger NUM_ROWS (892M) after weekend load → NL plan that was optimal at 100M rows → catastrophic at 892M
- **Missing evidence needed**: DBA_HIST_SQL_PLAN cho cả hai PLAN_HASH_VALUE để compare plans; DBA_HIST_OPTSTAT_LOG để see which object stats changed; DBA_HISTOGRAMS cho columns in WHERE clause → confirm histogram-driven regression
- **Immediate fix**: `DBMS_SPM.LOAD_PLANS_FROM_AWR_CURSOR_CACHE` để create SQL Plan Baseline với old plan_hash_value; hoặc `DBMS_STATS.LOCK_TABLE_STATS` (reverts plan to pre-refresh behavior, risky long-term)
- **Permanent fix**: Investigate why 892M row table has stats that produce NL join at this scale → likely missing histogram or stale NDV. Solution: `METHOD_OPT => 'FOR ALL INDEXED COLUMNS SIZE AUTO'` trong table stats gather; consider incremental stats nếu partition available

---


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/section_all_new/section_17_automated_maintenance_senior_guide.md`
