---
title: Section 12 — ADDM (Automatic Database Diagnostic Monitor)
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/section_all/section_12_addm_guide.md
---

# Section 12 — ADDM (Automatic Database Diagnostic Monitor)

## Tổng quan

**ADDM** là công cụ tự động phân tích hiệu năng của Oracle, chạy sau mỗi AWR snapshot. ADDM đọc dữ liệu AWR, xác định các bottleneck, và đưa ra khuyến nghị cụ thể có định lượng impact.

**Practice 10 — Using Automatic Database Diagnostic Monitor (ADDM)**

Mục tiêu:
- Khám phá ADDM findings/recommendations qua EM Express
- Dùng ADDM trong test case thực tế
- Quản lý ADDM qua SQL*Plus
- Tạo ADDM Comparison Report

---

## Kiến thức lý thuyết

### ADDM hoạt động như thế nào?

```
AWR Snapshot N → AWR Snapshot N+1
                    ↓
              ADDM Task chạy tự động
                    ↓
         Phân tích bottleneck trong khoảng [N, N+1]
                    ↓
         Tạo Findings + Recommendations
```

- Mỗi AWR snapshot → Oracle tự tạo 1 ADDM task
- Task name format: `ADDM:<DBID>_<instance#>_<AWR_Snapshot_ID>`
- ADDM phân tích **DB Time** và xác định nguyên nhân chiếm phần lớn DB Time

### Views/Packages chính

| Đối tượng | Mô tả |
|-----------|-------|
| `DBA_ADDM_TASKS` | Danh sách ADDM tasks |
| `DBA_ADDM_FINDINGS` | Findings (vấn đề được phát hiện) của mỗi task |
| `DBA_ADVISOR_RECOMMENDATIONS` | Khuyến nghị xử lý cho mỗi finding |
| `DBA_ADVISOR_ACTIONS` | Hành động cụ thể trong mỗi khuyến nghị |
| `DBMS_ADVISOR` | Package tạo và quản lý ADDM tasks |
| `DBMS_ADDM` | Package sinh ADDM comparison report |

---

## Phần 1: Khám phá ADDM qua EM Express

### Truy cập EM Express

```
http://<server_IP>:5500/em
```

### Các bước khám phá

1. Login với tài khoản `sys`
2. **Performance Hub** → Tab **ADDM**
3. Chọn time range (real-time hoặc historical)
4. Chọn ADDM task có findings
5. Xem chi tiết từng finding và recommendation

> **EM Express dễ dùng hơn SQL*Plus nhiều** khi xem ADDM, nhờ có biểu đồ và drilldown trực quan.

---

## Phần 2: Xem ADDM qua SQL*Plus

### Lấy ADDM task gần nhất

```sql
SELECT
  'TASK_ID: ' || TASK_ID || CHR(10) ||
  'TASK_NAME: ' || TASK_NAME || CHR(10) ||
  'DESCRIPTION: ' || SUBSTR(DESCRIPTION,1,60) || CHR(10) ||
  'STATUS: ' || STATUS || CHR(10) ||
  'ACTIVITY_COUNTER: ' || ACTIVITY_COUNTER || CHR(10) ||
  'RECOMMENDATION_COUNT: ' || RECOMMENDATION_COUNT AS INFO
FROM DBA_ADDM_TASKS
ORDER BY TASK_ID DESC FETCH FIRST 1 ROWS ONLY;
```

### Lưu Task ID và Task Name vào biến

```sql
DEFINE V_TASK_ID = <task_id_value>
DEFINE V_TASK_NAME = '<task_name_value>'  -- có dấu nháy đơn
```

### Sinh ADDM text report

```sql
set long 1000000 longchunksize 1000000
set linesize 1000 pagesize 0
set trim on trimspool on
set echo off feedback off
spool /media/sf_extdisk/addm_report.txt

SELECT DBMS_ADVISOR.GET_TASK_REPORT('&V_TASK_NAME')
FROM DBA_ADVISOR_TASKS
WHERE TASK_ID = &V_TASK_ID;

spool off
```

> `GET_TASK_REPORT` chỉ hỗ trợ format **text**, không có HTML.

### Xem Findings

```sql
SELECT
  'FINDING_ID: ' || FINDING_ID || CHR(10) ||
  'FINDING_NAME: ' || FINDING_NAME || CHR(10) ||
  'TYPE: ' || TYPE || CHR(10) ||
  'IMPACT_TYPE: ' || IMPACT_TYPE || CHR(10) ||
  'IMPACT: ' || IMPACT || CHR(10) ||
  'MESSAGE: ' || MESSAGE || CHR(10) ||
  'MORE_INFO: ' || MORE_INFO AS INFO
FROM DBA_ADDM_FINDINGS F
WHERE F.TASK_ID = &V_TASK_ID;
```

**Cột quan trọng:**
- `IMPACT`: % DB Time bị ảnh hưởng bởi finding này
- `IMPACT_TYPE`: loại tác động (DB Time, IO, CPU, ...)
- `MESSAGE`: mô tả vấn đề
- `MORE_INFO`: thông tin bổ sung để điều tra

### Xem Recommendations

```sql
SELECT
  'REC_ID: ' || REC_ID || CHR(10) ||
  'FINDING_ID: ' || FINDING_ID || CHR(10) ||
  'TYPE: ' || TYPE || CHR(10) ||
  'RANK: ' || RANK || CHR(10) ||
  'BENEFIT_TYPE: ' || BENEFIT_TYPE || CHR(10) ||
  'BENEFIT: ' || BENEFIT AS INFO
FROM DBA_ADVISOR_RECOMMENDATIONS
WHERE TASK_ID = &V_TASK_ID
ORDER BY FINDING_ID, RANK;
```

### Xem Actions (hành động cụ thể)

```sql
SELECT
  'TASK_NAME: ' || TASK_NAME || CHR(10) ||
  'REC_ID: ' || REC_ID || CHR(10) ||
  'ACTION_ID: ' || ACTION_ID || CHR(10) ||
  'COMMAND: ' || COMMAND || CHR(10) ||
  'MESSAGE: ' || MESSAGE || CHR(10) ||
  'ATTR1: ' || ATTR1 || CHR(10) ||
  'ATTR2: ' || ATTR2 AS INFO
FROM DBA_ADVISOR_ACTIONS
WHERE TASK_ID = &V_TASK_ID
ORDER BY REC_ID;
```

---

## Phần 3: Chạy ADDM thủ công trên 2 AWR Snapshot

```sql
@ $ORACLE_HOME/rdbms/admin/addmrpt.sql
-- Script hỏi: begin snapshot ID, end snapshot ID, tên report
```

Dùng khi:
- Muốn phân tích một khoảng thời gian cụ thể (không phải interval gần nhất)
- Muốn span qua nhiều AWR snapshot intervals

---

## Phần 4: ADDM Comparison Report

So sánh hiệu năng giữa **baseline period** và **test period**.

### Lấy snapshot ID của baseline

```sql
SELECT START_SNAP_ID, END_SNAP_ID
FROM DBA_HIST_BASELINE
WHERE BASELINE_NAME = 'OLTP_NORMAL';
```

### Sinh comparison report

```sql
-- Bước 1: Setup spool
set long 1000000 longchunksize 1000000
set linesize 1000 pagesize 0
set trim on trimspool on
set echo off feedback off
spool /media/sf_extdisk/addm_compare_report.html

-- Bước 2: Chạy query
SELECT DBMS_ADDM.COMPARE_INSTANCES(
  BASE_INSTANCE_ID   => 1,
  BASE_BEGIN_SNAP_ID => &start_base_snap_id,
  BASE_END_SNAP_ID   => &end_base_snap_id,
  COMP_INSTANCE_ID   => 1,
  COMP_BEGIN_SNAP_ID => &start_comp_snap_id,
  COMP_END_SNAP_ID   => &end_comp_snap_id,
  REPORT_TYPE        => 'HTML'
) AS report
FROM dual;

-- Bước 3:
SPOOL OFF
```

### Đọc Comparison Report

Các phần quan trọng trong report:

| Phần | Ý nghĩa |
|------|---------|
| **SQL Commonality** | % SQL giống nhau giữa 2 period. Cần > 80% để so sánh có giá trị |
| **Load Charts** | Biểu đồ load của 2 period để trực quan so sánh |
| **Average Active Sessions** | Càng nhỏ càng tốt. So sánh giữa 2 period |
| **Findings** | Các vấn đề xuất hiện trong một hoặc cả hai period |
| **Resources** | CPU, I/O, Memory của 2 period |

---

## Nguyên tắc đọc ADDM

> **ADDM gợi ý, không phải chỉ thị.**

Ví dụ: ADDM báo "Consider adding more CPUs to the host" → Không có nghĩa là phải mua CPU. Thực tế, nguyên nhân có thể là:
- CPU bị stress test nhân tạo (như trong lab)
- Query không dùng index → table scan làm CPU căng
- Một số process chiếm CPU không cần thiết

Luôn **điều tra root cause** trước khi áp dụng recommendation.

---

## Tóm tắt

| Tác vụ | Phương pháp |
|--------|------------|
| Xem ADDM dễ nhất | EM Express → Performance Hub → ADDM tab |
| Xem findings trong SQL*Plus | `DBA_ADDM_FINDINGS` |
| Xem recommendations | `DBA_ADVISOR_RECOMMENDATIONS` |
| Xem actions cụ thể | `DBA_ADVISOR_ACTIONS` |
| Chạy ADDM thủ công | `@ $ORACLE_HOME/rdbms/admin/addmrpt.sql` |
| Comparison report | `DBMS_ADDM.COMPARE_INSTANCES(...)` |
| Text report trong SQL*Plus | `DBMS_ADVISOR.GET_TASK_REPORT(task_name)` |

> **Workflow tiêu chuẩn:** Có vấn đề → Xem AWR report để định hướng → Xem ADDM task của cùng khoảng thời gian → Đọc findings + recommendations → Điều tra chi tiết (ASH, SQL traces) → Xử lý.


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/section_all/section_12_addm_guide.md`
