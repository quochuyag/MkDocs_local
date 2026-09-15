---
title: Server-generated Alerts — Deep Dive for Senior DBA
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/section_all_new/section_10_server_generated_alerts_senior_guide.md
---

# Server-generated Alerts — Deep Dive for Senior DBA

## 1. Mental Model

Server-generated alerts là Oracle's threshold-based reactive monitoring layer được built trực tiếp vào AWR metric framework. MMON background process evaluate threshold conditions và push alert records vào DBA_OUTSTANDING_ALERTS khi breach. Điểm then chốt: đây là **event-driven system, không phải polling** — nhưng Oracle chỉ *generate* alert, không *deliver* notification. Notification delivery là trách nhiệm của DBA (EM, DBMS_SCHEDULER, custom).

Frame nó như một IDS (Intrusion Detection System) cho database: threshold evaluation liên tục, nhưng bạn vẫn cần wire up alerting channel để alert thực sự reach operational team.

---

## 2. Internals & Mechanics

**Alert evaluation pipeline:**
1. MMON samples instance statistics mỗi 60 giây → feeds V$SYSMETRIC_HISTORY
2. V$SYSMETRIC_HISTORY có hai granularity groups:
   - GROUP_ID = 2: 1-minute slices (short interval)
   - GROUP_ID = 3: 5-minute slices (long interval) — được dùng cho threshold evaluation
3. MMON computes metric value: `DATABASE_WAIT_TIME_RATIO = (DB Time − DB CPU) / DB Time × 100`
4. Compare với thresholds trong WRI$_ALERT_THRESHOLD (internal table, exposed qua DBA_THRESHOLDS)
5. Breach → INSERT hoặc UPDATE WRI$_ALERT_OUTSTANDING → visible qua DBA_OUTSTANDING_ALERTS
6. Khi metric drops below threshold → alert transitions "cleared" → moves to DBA_ALERT_HISTORY

**CONSECUTIVE_OCCURRENCES mechanics:**
Khi set CONSECUTIVE_OCCURRENCES = N, Oracle chỉ fire alert sau N lần breach liên tiếp trong OBSERVATION_PERIOD-minute windows. Nếu bất kỳ observation nào trong chuỗi không breach → counter reset về 0.

**V$SYSMETRIC duality:**
```sql
-- Trả về 2 rows cùng metric name, phân biệt bằng INTSIZE_CSEC
SELECT METRIC_NAME, VALUE, INTSIZE_CSEC
FROM V$SYSMETRIC
WHERE METRIC_NAME = 'Database Wait Time Ratio';
-- INTSIZE_CSEC ≈ 6000  → 60-second interval (instantaneous)
-- INTSIZE_CSEC ≈ 30000 → 5-minute interval (smoothed, dùng cho threshold evaluation)
```

Khi dùng `SELECT MAX(INTSIZE_CSEC)`, bạn lấy 5-minute value — consistent với threshold evaluation. Để detect instantaneous spike, dùng `MIN(INTSIZE_CSEC)`.

**METRIC_ID mapping:**
- 2107 → Database Wait Time Ratio (non-CDB / CDB root)
- PDB metrics có METRIC_ID khác; join V$METRICNAME với CON_ID filter khi làm việc trong CDB

**Alert lifecycle state machine:**
```
OUTSTANDING (WARNING) → OUTSTANDING (CRITICAL) → cleared (auto)
         ↑                        ↑
    threshold breach          escalation
    N consecutive times

Once OUTSTANDING: metric value updated in-place, no duplicate records created
```

---

## 3. Production Realities

**Static threshold calibration là bài toán khó nhất trong section này.** Practice dùng 70%/90% — đây là teaching example, không phải production values:

- OLTP system nhẹ: baseline wait time ~15-25%, có thể set WARNING=60%, CRITICAL=85%
- Batch-heavy system: overnight batch push wait time 75-85% một cách bình thường → 70% threshold sẽ fire false alerts mỗi đêm
- Mixed workload với peak hours: chênh lệch peak vs off-peak 3-5x → single static threshold luôn sai ở một thời điểm

**Giải pháp phổ biến trong production:**
1. DBMS_SCHEDULER job reset threshold values theo schedule (peak hours vs off-peak)
2. Custom monitoring query V$SYSMETRIC_HISTORY trực tiếp với dynamic baseline từ last 7 days
3. AWR baseline comparison thay vì absolute threshold

**Alert delivery gap:** DBA_OUTSTANDING_ALERTS không tự push notification. Trong nhiều production environments, alerts được generated nhưng không ai biết vì không có notification wiring. Delivery options:
- Oracle EM: poll DBA_OUTSTANDING_ALERTS, send email/SMS — requires EM infrastructure
- Custom DBMS_SCHEDULER job với UTL_MAIL hoặc UTL_HTTP + webhook
- SNMP: Oracle có thể send SNMP traps qua snmp.ora config — rarely used in practice

**Alert suppression:** Khi một alert đang OUTSTANDING, Oracle không insert record mới — chỉ update METRIC_VALUE. Nếu bạn chỉ monitor `COUNT(*) > 0`, bạn bỏ lỡ WARNING→CRITICAL escalation. Phải track MESSAGE_TYPE change.

**Beyond DATABASE_WAIT_TIME:** ~100+ metrics có sẵn trong V$METRICNAME. Các metrics production-useful khác:
- Tablespace Space Used % (object-level alert, rất phổ biến — bắt buộc cấu hình)
- Average Active Sessions (db load indicator — correlates với CPU count)
- SQL Service Response Time (application SLA-oriented)
- User Commits Per Sec (throughput baseline)

**12c+ multitenant:** Trong CDB, thresholds set ở CDB root level. Alert cho PDB workload appear với CON_ID của PDB trong DBA_OUTSTANDING_ALERTS (12.2+).

---

## 4. Decision Framework

**Khi nào dùng server alert vs alternatives:**

| Scenario | Recommendation |
|----------|----------------|
| Simple threshold, stable workload | DBMS_SERVER_ALERT — built-in, zero maintenance |
| Dynamic workload (peak/off-peak varies 3x+) | Custom DBMS_SCHEDULER + V$SYSMETRIC_HISTORY với rolling average baseline |
| Need sub-1-minute detection | V$SYSMETRIC short interval (60s) + frequent DBMS_SCHEDULER job |
| Alert delivery beyond EM | Wire DBA_OUTSTANDING_ALERTS → custom notification job |
| Tablespace space management | OBJECT_TYPE_TABLESPACE alerts — standard practice, configure on all production DBs |
| SLA-based alerting (response time) | SQL Service Response Time metric (lookup METRIC_ID in V$METRICNAME) |

**CONSECUTIVE_OCCURRENCES tuning:**

| Value | Use case | Risk |
|-------|----------|------|
| 1 | Sensitive production systems, immediate detection needed | False positives from transient spikes |
| 2-3 | OLTP systems với some workload variability | May miss genuine 2-minute issue |
| 5+ | Highly variable workloads, alert fatigue prevention | May miss medium-duration issues |

**Anti-patterns:**
- Set threshold tanpa measuring baseline → almost always wrong values
- CONSECUTIVE_OCCURRENCES=1 trên variable workload → alert fatigue → team ignores alerts
- Không test alert delivery end-to-end → alerts generated, no one notified
- Monitor chỉ `COUNT(*) FROM DBA_OUTSTANDING_ALERTS` → miss WARNING→CRITICAL escalation

---

## 5. Key SQL / Commands

```sql
-- List tất cả metrics với description (tìm metric quan tâm)
SELECT METRIC_ID, METRIC_NAME, GROUP_NAME, UNIT
FROM V$METRICNAME
ORDER BY METRIC_NAME;

-- Current metric values với cả hai granularities
SELECT METRIC_NAME, VALUE, INTSIZE_CSEC,
       CASE INTSIZE_CSEC
            WHEN (SELECT MAX(INTSIZE_CSEC) FROM V$SYSMETRIC)
            THEN '5-min (threshold eval)'
            ELSE '1-min (instantaneous)'
       END AS INTERVAL_TYPE
FROM V$SYSMETRIC
WHERE METRIC_NAME IN ('Database CPU Time Ratio', 'Database Wait Time Ratio')
ORDER BY METRIC_NAME, INTSIZE_CSEC;

-- Wait time % trend 30 phút qua, 1-minute resolution
SELECT BEGIN_TIME, END_TIME, ROUND(VALUE,2) WAIT_PCT
FROM V$SYSMETRIC_HISTORY
WHERE METRIC_ID = 2107
  AND GROUP_ID = 2  -- 1-minute granularity
  AND BEGIN_TIME >= SYSDATE - 30/1440
ORDER BY BEGIN_TIME;

-- Set threshold với CONSECUTIVE_OCCURRENCES=2 (production-safe)
BEGIN
  DBMS_SERVER_ALERT.SET_THRESHOLD(
    METRICS_ID              => 2107,
    WARNING_OPERATOR        => DBMS_SERVER_ALERT.OPERATOR_GE,
    WARNING_VALUE           => '70',
    CRITICAL_OPERATOR       => DBMS_SERVER_ALERT.OPERATOR_GE,
    CRITICAL_VALUE          => '90',
    OBSERVATION_PERIOD      => 1,
    CONSECUTIVE_OCCURRENCES => 2,     -- fire only after 2 consecutive breaches
    INSTANCE_NAME           => NULL,
    OBJECT_TYPE             => DBMS_SERVER_ALERT.OBJECT_TYPE_SYSTEM,
    OBJECT_NAME             => NULL
  );
END;
/

-- Check all configured thresholds
SELECT METRICS_NAME, WARNING_OPERATOR, WARNING_VALUE,
       CRITICAL_OPERATOR, CRITICAL_VALUE,
       OBSERVATION_PERIOD, CONSECUTIVE_OCCURRENCES, STATUS
FROM DBA_THRESHOLDS
ORDER BY METRICS_NAME;

-- Monitor active alerts với MESSAGE_TYPE (track escalation)
SELECT SEQUENCE_ID, METRIC_VALUE, MESSAGE_TYPE,
       SUBSTR(REASON, 1, 100) REASON,
       SUBSTR(SUGGESTED_ACTION, 1, 100) ACTION,
       CREATION_TIME, TIME_SUGGESTED
FROM DBA_OUTSTANDING_ALERTS
ORDER BY CREATION_TIME DESC;

-- Alert history — calculate incident duration
SELECT METRICS_NAME, MESSAGE_TYPE, METRIC_VALUE,
       CREATION_TIME, TIME_SUGGESTED, RESOLUTION,
       ROUND((CAST(TIME_SUGGESTED AS DATE) - CAST(CREATION_TIME AS DATE)) * 24 * 60, 1) DURATION_MIN
FROM DBA_ALERT_HISTORY
WHERE CREATION_TIME >= SYSDATE - 7
ORDER BY CREATION_TIME DESC;

-- Reset threshold về default (disable custom threshold)
BEGIN
  DBMS_SERVER_ALERT.SET_THRESHOLD(
    METRICS_ID              => 2107,
    WARNING_OPERATOR        => DBMS_SERVER_ALERT.OPERATOR_DO_NOT_CHECK,
    WARNING_VALUE           => NULL,
    CRITICAL_OPERATOR       => DBMS_SERVER_ALERT.OPERATOR_DO_NOT_CHECK,
    CRITICAL_VALUE          => NULL,
    OBSERVATION_PERIOD      => 1,
    CONSECUTIVE_OCCURRENCES => 1,
    INSTANCE_NAME           => NULL,
    OBJECT_TYPE             => DBMS_SERVER_ALERT.OBJECT_TYPE_SYSTEM,
    OBJECT_NAME             => NULL
  );
END;
/
```

---

## 6. Senior Checklist

- [ ] Đo baseline wait time % trước khi set threshold — minimum 1 tuần data, bao gồm peak và off-peak patterns
- [ ] Verify CONSECUTIVE_OCCURRENCES phù hợp với workload variability — alert fatigue = team ignores alerts
- [ ] Wire alert delivery: DBA_OUTSTANDING_ALERTS không self-notify — cần EM hoặc custom DBMS_SCHEDULER notification job
- [ ] Test end-to-end: generate artificial threshold breach, verify notification reaches intended recipient
- [ ] Monitor MESSAGE_TYPE transition (WARNING→CRITICAL) trong DBA_OUTSTANDING_ALERTS — không chỉ count(*)
- [ ] Configure tablespace space alerts (OBJECT_TYPE_TABLESPACE) trên tất cả production databases — thường bị bỏ qua
- [ ] Document threshold values và rationale — static threshold magic numbers cần context để understand sau 6 tháng

---

# Lab: Server-generated Alerts — Hands-on for Senior DBA

## Lab Overview
- **Mục tiêu:** Configure production-ready alert strategy; hiểu pipeline từ metric sampling đến notification
- **Môi trường:** Oracle 12c–19c, non-CDB hoặc CDB
- **Thời gian ước tính:** 60 phút
- **Độ khó:** Senior

---

## Exercise 1 — Baseline Calibration Before Threshold Setting

### Scenario
Bạn vừa join một production team. DBA cũ đã set DATABASE_WAIT_TIME threshold ở 70%/90%. Alert đang fire 3-4 lần mỗi tuần, nhưng khi application team kiểm tra response time, không có user impact nào. Management lo ngại về alert fatigue — team bắt đầu ignore alerts.

### Tasks
1. Collect 1-hour wait time % history từ V$SYSMETRIC_HISTORY — compute p50, p90, p95, max theo từng 5-minute bucket
2. Phân tích distribution: peak hours vs off-peak có pattern gì khác nhau không?
3. Propose threshold values với justification dựa trên actual data — warning và critical với rationale
4. Set CONSECUTIVE_OCCURRENCES phù hợp với observations, và explain trade-off với value bạn chọn

### Expected Findings
- P95 during off-peak thường thấp hơn P50 during batch/peak significantly
- 70% threshold hợp lý cho peak hours nhưng quá thấp cho baseline stable period
- Cần ít nhất 7 ngày data để thấy weekly pattern đầy đủ

### Debrief Questions
- Tại sao dùng AVG(WAIT_TIME_PCT) cho threshold calibration có thể misleading?
- CONSECUTIVE_OCCURRENCES=3 với OBSERVATION_PERIOD=1 nghĩa là spike phải kéo dài tối thiểu bao nhiêu phút?
- Nếu workload có weekly pattern mạnh (heavy Friday batch, light Monday morning), single static threshold đủ chưa? Alternatives là gì?

---

## Exercise 2 — Alert Delivery và Monitoring Pipeline

### Scenario
Team hiện tại monitor DBA_OUTSTANDING_ALERTS qua EM dashboard, nhưng EM agent đã crash 3 lần trong tháng trước mà không ai biết (EM không alert về chính nó). Management yêu cầu backup alerting mechanism không depend on EM.

### Tasks
1. Viết DBMS_SCHEDULER job chạy mỗi 5 phút: query DBA_OUTSTANDING_ALERTS, nếu có MESSAGE_TYPE='CRITICAL' → log vào custom audit table với timestamp
2. Modify logic để detect MESSAGE_TYPE escalation (WARNING → CRITICAL) giữa hai job executions
3. Test: verify alert suppression behavior — khi alert đang OUTSTANDING và metric vẫn breach, bao nhiêu records trong DBA_OUTSTANDING_ALERTS?

### Expected Findings
- Job cần store previous check state để detect escalation (alert suppression → count stays at 1)
- METRIC_VALUE trong DBA_OUTSTANDING_ALERTS cập nhật in-place — chỉ TIME_SUGGESTED thay đổi
- Custom monitoring table cần track: sequence_id, metric_value, message_type, first_seen, last_checked

### Debrief Questions
- Tại sao alert suppression (no duplicate records khi OUTSTANDING) là design decision hợp lý? Trade-off gì?
- Nếu DBMS_SCHEDULER notification job chính nó fail silently, ai monitor the monitor?
- Có cách nào detect khi DBA_OUTSTANDING_ALERTS record bị stale (metric đã về normal nhưng alert chưa clear)?

---

## Exercise 3 — Troubleshooting Scenario *(Expert level)*

### Incident Brief
Production system tại 14:30. On-call DBA nhận 2 alerts gần như đồng thời:
1. DATABASE_WAIT_TIME_RATIO = 87.3% (CRITICAL threshold = 90%)
2. Average Active Sessions = 18.4 (threshold = 16, based on CPU count 16)

Application team báo cáo: một số users bị slow (không phải tất cả). Batch job vừa start lúc 14:15. APM shows: P50 response time normal, P95 elevated 3x.

### Evidence Provided

```
-- DBA_OUTSTANDING_ALERTS tại 14:31
METRIC_VALUE   MESSAGE_TYPE   CREATION_TIME
87.3           CRITICAL       14:27:05

-- V$SYSMETRIC tại 14:31
INTSIZE_CSEC   METRIC_NAME                   VALUE
30000          Database Wait Time Ratio       87.3   ← 5-min (threshold eval)
30000          Database CPU Time Ratio        12.7
6000           Database Wait Time Ratio       91.2   ← 1-min (instantaneous)
6000           Average Active Sessions        22.1

-- V$SYSMETRIC_HISTORY (METRIC_ID=2107, GROUP_ID=2 = 1-min, last 20 mins)
BEGIN_TIME   WAIT_PCT
14:10        24.1
14:11        23.8
14:14        24.9
14:15        27.3   ← batch starts
14:16        41.2
14:17        62.7
14:18        74.1
14:19        79.8
14:20        83.4
14:21        85.2
14:22        86.9
14:23        87.1
14:25        88.3
14:26        89.1
14:27        90.4   ← threshold breach (1-min value)
14:28        91.2

-- Configured threshold: WARNING=70%, CRITICAL=90%, CONSECUTIVE_OCCURRENCES=1
```

### Your Mission
1. DBA_OUTSTANDING_ALERTS shows 87.3% nhưng V$SYSMETRIC short interval shows 91.2% tại cùng thời điểm 14:31. Tại sao?
2. Alert fired lúc 14:27 với CRITICAL threshold=90%, CONSECUTIVE_OCCURRENCES=1. Tại sao không fire sớm hơn dù wait % vượt 70% từ 14:16?
3. Nếu CONSECUTIVE_OCCURRENCES=3, alert CRITICAL sẽ fire lúc mấy giờ? Tính chính xác.
4. MESSAGE_TYPE trong DBA_OUTSTANDING_ALERTS tại 14:27 là gì? Tại sao không phải WARNING dù threshold WARNING=70% đã breach từ 14:16?
5. Bước đầu tiên để distinguish: batch job contention vs genuine application degradation?

### Evaluation Criteria
- Giải thích đúng: 87.3% (5-min long interval) vs 91.2% (1-min short interval) — threshold eval dùng long interval
- Hiểu tại sao WARNING không fire trước CRITICAL: CRITICAL threshold được evaluate trên cùng 5-minute window, và khi 5-min average đạt 90%+, nó direct vào CRITICAL state
- CONSECUTIVE_OCCURRENCES=3 calculation: 14:27, 14:28, 14:29 là 3 consecutive breaches → fire tại 14:29
- Nhận ra root cause investigation cần ASH drill-down (session breakdown trong batch window), không phải immediate tuning


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/section_all_new/section_10_server_generated_alerts_senior_guide.md`
