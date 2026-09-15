---
title: 'Bài 40: Thực hành - Quản lý Undo Data'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/40-thuc-hanh-quan-ly-undo-data.md
---

# Bài 40: Thực hành - Quản lý Undo Data

## Mục tiêu thực hành
Trong bài thực hành này, bạn sẽ thực hiện các tác vụ quản lý Undo Data:
- Kiểm tra và hiểu thống kê Undo từ `V$UNDOSTAT`
- Kích hoạt Undo Advisor và lấy khuyến nghị
- Tính thủ công kích thước Undo cần thiết cho một giá trị Undo Retention

---

## Điều kiện tiên quyết
Máy ảo `srv1` được khôi phục từ snapshot **non-CDB** và đang chạy.

---

## Phần 1: Chuẩn bị

### Bước 1: Mở Putty kết nối srv1 với user oracle

### Bước 2: Tạo script hiển thị thống kê Undo

```bash
cat > display_undo_stats.sql <<EOF
/* Query lấy thống kê undo từ 2 khoảng thời gian gần nhất */
SELECT UNDOBLKS, MAXQUERYLEN, UNEXPIREDBLKS, EXPIREDBLKS, TUNED_UNDORETENTION RETENTION
FROM V\$UNDOSTAT
ORDER BY BEGIN_TIME DESC
FETCH FIRST 2 ROWS ONLY;
EOF
```

### Bước 3: Xác nhận non-CDB database đang chạy

```sql
sqlplus / as sysdba

SELECT CDB FROM V$DATABASE;
-- Kết quả mong đợi: NO
```

### Bước 4: Tạo bảng test lớn (kết nối với HR)

```sql
conn HR/ABcd##1234

set timing on

-- Tạo bảng EMP lớn từ EMPLOYEES (NOLOGGING để nhanh hơn)
CREATE TABLE EMP NOLOGGING AS
  SELECT A.* FROM EMPLOYEES A, EMPLOYEES B, EMPLOYEES C
  UNION ALL
  SELECT A.* FROM EMPLOYEES A, EMPLOYEES B, EMPLOYEES C
  UNION ALL
  SELECT A.* FROM EMPLOYEES A, EMPLOYEES B, EMPLOYEES C;

-- Thu thập thống kê bảng
ANALYZE TABLE EMP COMPUTE STATISTICS;

-- Tạo index
CREATE INDEX EMPNO_NDX ON EMP(EMPLOYEE_ID);
ANALYZE INDEX EMPNO_NDX COMPUTE STATISTICS;

set timing off

-- Kiểm tra kích thước bảng (MB)
SELECT BLOCKS * 8 / 1024 MB FROM USER_TABLES WHERE TABLE_NAME = 'EMP';
```

### Bước 5: Chuyển sang SYS (session admin)

```sql
conn / as sysdba
```

---

## Phần 2: Kiểm tra thống kê Undo

### Bước 6: Hiển thị thống kê Undo ban đầu

```sql
@ display_undo_stats.sql
```

> **Quan sát**: Khi không có session nào thay đổi dữ liệu, số undo blocks rất ít.

### Bước 7: Tạo AWR Snapshot thủ công

```sql
exec DBMS_WORKLOAD_REPOSITORY.CREATE_SNAPSHOT(FLUSH_LEVEL=>'ALL')
```

> **Lưu ý**: Trong môi trường thực, AWR snapshot được tạo tự động mỗi giờ. Chúng ta tạo thủ công để có dữ liệu ngay lập tức.

### Bước 8: Xem thông tin snapshot vừa tạo — ghi lại SNAP_ID

```sql
col BEGIN_INTERVAL_TIME for a26
col END_INTERVAL_TIME for a26

SELECT SNAP_ID, BEGIN_INTERVAL_TIME, END_INTERVAL_TIME
FROM DBA_HIST_SNAPSHOT
ORDER BY SNAP_ID DESC FETCH FIRST 1 ROWS ONLY;
```

> **Ghi lại**: `SNAP_ID` này là `BEGIN_ID` cho Undo Advisor sau.

### Bước 9: Mở session Putty thứ 2 (client session) — đăng nhập HR

```bash
# Mở cửa sổ Putty mới, đặt màu font khác để phân biệt (ví dụ: xanh lá)
sqlplus hr/ABcd##1234
```

### Bước 10: Trong client session — chạy UPDATE (tạo Undo Data)

```sql
-- Chạy lệnh này trong client session (HR), KHÔNG cần đợi hoàn thành
UPDATE EMP SET SALARY = SALARY * 1 WHERE EMPLOYEE_ID BETWEEN 100 AND 150;
```

### Bước 11: Trong admin session — theo dõi thống kê Undo

```sql
@ display_undo_stats.sql
```

> **Quan sát**: Số `UNDOBLKS` tăng đáng kể khi UPDATE đang thực thi. V$UNDOSTAT làm mới mỗi 10 phút — có thể cần chờ.

### Bước 12: Trong client session — COMMIT

```sql
COMMIT;
```

### Bước 13: Trong admin session — xem lại thống kê

```sql
@ display_undo_stats.sql
```

> **Quan sát**: Sau COMMIT, số `UNEXPIREDBLKS` tăng đáng kể (có thể cần 5 phút để thấy).

---

## Phần 3: Quan sát MAXQUERYLEN

### Bước 14: Mở session Putty thứ 3 — đăng nhập HR

```sql
sqlplus hr/ABcd##1234
```

### Bước 15: Trong session 3 — chạy UPDATE tạo active undo

```sql
UPDATE EMP SET SALARY = SALARY * 1 WHERE EMPLOYEE_ID = 100;
```

### Bước 16: Trong client session (session 2) — chạy query cần đọc Undo

```sql
SELECT * FROM EMP WHERE EMPLOYEE_ID IN (100, 101, 102);
```

> Query này cần đọc Undo để đảm bảo read consistency (EMPLOYEE_ID=100 đang bị lock).

### Bước 17: Trong admin session — kiểm tra MAXQUERYLEN

```sql
@ display_undo_stats.sql
```

> **Quan sát**: Cột `MAXQUERYLEN` tăng do query dài phải đọc Undo.

### Bước 18: Tạo AWR Snapshot thứ 2

```sql
exec DBMS_WORKLOAD_REPOSITORY.CREATE_SNAPSHOT(FLUSH_LEVEL=>'ALL')
```

### Bước 19: Xem thông tin snapshot — ghi lại SNAP_ID thứ 2

```sql
col BEGIN_INTERVAL_TIME for a26
col END_INTERVAL_TIME for a26

SELECT SNAP_ID, BEGIN_INTERVAL_TIME, END_INTERVAL_TIME
FROM DBA_HIST_SNAPSHOT
ORDER BY SNAP_ID DESC FETCH FIRST 1 ROWS ONLY;
```

> **Ghi lại**: `SNAP_ID` này là `END_ID` cho Undo Advisor.

### Bước 20: Thoát session thứ 3 (session đang UPDATE)

```sql
EXIT;
```

---

## Phần 4: Kích hoạt Undo Advisor

### Bước 21: Trong admin session — tạo và chạy Undo Advisor Task

```sql
conn / as sysdba

set serveroutput on

DECLARE
  tid    NUMBER;
  tname  VARCHAR2(30);
  oid    NUMBER;
BEGIN
  DBMS_ADVISOR.CREATE_TASK('Undo Advisor', tid, tname, 'Undo Advisor Task');
  DBMS_OUTPUT.PUT_LINE('Task name....: ' || tname);
  
  DBMS_ADVISOR.CREATE_OBJECT(tname, 'UNDO_TBS', null, null, null, 'null', null, oid);
  DBMS_ADVISOR.SET_TASK_PARAMETER(tname, 'TARGET_OBJECTS', oid);
  DBMS_ADVISOR.SET_TASK_PARAMETER(tname, 'START_SNAPSHOT', &beginid);  -- nhập BEGIN_ID ở bước 8
  DBMS_ADVISOR.SET_TASK_PARAMETER(tname, 'END_SNAPSHOT', &endid);      -- nhập END_ID ở bước 19
  DBMS_ADVISOR.SET_TASK_PARAMETER(tname, 'INSTANCE', 1);
  DBMS_ADVISOR.EXECUTE_TASK(tname);
END;
/
```

> **Lưu lại tên Task** được in ra (ví dụ: `TASK_1`).

### Bước 22: Mở SQL Developer — xem kết quả Undo Advisor

```sql
-- Kết nối non-CDB với SYSTEM trong SQL Developer
-- Thay <tên_task> bằng tên task đã ghi ở bước 21

SELECT * FROM DBA_ADVISOR_FINDINGS WHERE TASK_NAME = '&TNAME';

SELECT * FROM DBA_ADVISOR_RECOMMENDATIONS WHERE TASK_NAME = '&TNAME';
```

---

## Phần 5: Tính kích thước Undo cần thiết

### Bước 23: Kiểm tra Undo Tablespace hiện tại

```sql
SELECT TABLESPACE_NAME FROM DBA_TABLESPACES WHERE CONTENTS = 'UNDO';
-- Kết quả: UNDOTBS1
```

### Bước 24: Xem thông số datafile của Undo Tablespace

```sql
SELECT FILE_ID, BYTES/1024/1024 MB, STATUS, AUTOEXTENSIBLE,
       ROUND(MAXBYTES/1024/1024) MAX_MB
FROM DBA_DATA_FILES
WHERE TABLESPACE_NAME = 'UNDOTBS1';
```

> **Ghi lại** kích thước hiện tại của Undo Tablespace.

### Bước 25: Lấy Undo blocks/giây tối đa

```sql
SELECT MAX(UNDOBLKS / ((END_TIME - BEGIN_TIME) * 3600 * 24)) undo_bps
FROM V$UNDOSTAT;
```

> **Lưu ý**: Trong thực tế, nên chạy query này sau khi hệ thống đã chạy ở tải bình thường vài giờ hoặc vài ngày.

### Bước 26: Kiểm tra UNDO_RETENTION hiện tại

```sql
show parameter UNDO_RETENTION
-- Kết quả: 900 giây = 15 phút
```

### Bước 27: Kiểm tra kích thước block

```sql
show parameter DB_BLOCK_SIZE
-- Kết quả: 8192 bytes = 8 KB
```

### Bước 28: Tính kích thước Undo cần cho Undo Retention 1 giờ

```
Công thức:
Undo size = Thời gian giữ lại (giây) × Undo blocks/giây × Kích thước block (bytes)

Ví dụ tính (dựa trên undo_bps = 28):
Undo size = 3600 × 28 × 8192 bytes
           = 825,753,600 bytes
           = 806,400 KB
           ≈ 787.5 MB
```

> **So sánh** kết quả với kích thước Undo Tablespace hiện tại (bước 24).

### Bước 29: So sánh kết quả

| Thông số | Giá trị |
|---------|---------|
| Kích thước Undo Tablespace hiện tại | ___ MB |
| Kích thước Undo cần thiết (1 giờ retention) | ___ MB |
| Kết luận | Đủ / Cần tăng thêm |

---

## Dọn dẹp

### Bước 30: Thoát SQL Developer và các session Putty

```sql
-- Trong SQL*Plus (HR session)
DROP TABLE EMP PURGE;
EXIT;
```

---

## Tổng kết

| Kết quả thực hành | Điểm chính |
|------------------|-----------| 
| V$UNDOSTAT | Hiển thị thống kê Undo theo khoảng 10 phút |
| AWR Snapshot | Cần tạo snapshot thủ công trong lab (thực tế tự động) |
| Undo Advisor | Dùng `DBMS_ADVISOR` để tạo task và xem khuyến nghị |
| Công thức tính | `Undo size = Retention × undo_bps × block_size` |
| RETENTION GUARANTEE | Đảm bảo không ghi đè unexpired undo nhưng có rủi ro DML thất bại |

> **Ghi nhớ**: Thiết lập Undo Tablespace đúng kích thước **không đảm bảo** retention luôn được duy trì vì workload có thể thay đổi. Dùng `RETENTION GUARANTEE` nếu cần đảm bảo tuyệt đối.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/40-thuc-hanh-quan-ly-undo-data.md`
