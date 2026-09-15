---
title: 'Bài 39: Quản lý Undo Data'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/39-quan-ly-undo-data.md
---

# Bài 39: Quản lý Undo Data

## Mục tiêu
Sau bài học này, bạn sẽ có thể:
- Mô tả các lợi ích của Undo
- Mô tả các tác vụ quản lý không gian Undo
- Thiết lập tham số quản lý Undo
- Đặt Undo Retention
- Tinh chỉnh Undo Data
- Sử dụng Undo Advisor
- Kích hoạt Undo Guarantee
- Kích hoạt Temporary Undo
- Bật chế độ Shared hoặc Local Undo

---

## 1. Undo Data là gì?

Khi một user thực hiện lệnh DML (UPDATE, DELETE, INSERT), Oracle ghi lại **dữ liệu trước khi thay đổi** vào **Undo Segment** (segment hoàn tác). Dữ liệu này được gọi là **Undo Data**.

### Ví dụ cụ thể:

```sql
-- User thực hiện UPDATE
UPDATE EMPLOYEES SET SALARY = 2000 WHERE EMPNO = 100;
-- Oracle ghi vào Undo: EMPNO=100, SALARY=1000 (giá trị gốc)
```

Trong quá trình thực hiện DML:
- **Data Block**: lưu giá trị mới (SALARY = 2000)
- **Undo Segment**: lưu giá trị cũ (SALARY = 1000)
- **Redo Log**: ghi lại cả thay đổi trên Data Block và Undo Segment

---

## 2. Lợi ích của Undo

### 2.1 Phục vụ lệnh ROLLBACK
Khi user thực hiện ROLLBACK, Oracle dùng dữ liệu trong Undo Segment để khôi phục lại giá trị gốc trong Data Block.

### 2.2 Read Consistency (Nhất quán khi đọc)
Oracle đảm bảo rằng các query luôn thấy một **snapshot nhất quán** của dữ liệu tại thời điểm query bắt đầu:

- **Readers trước COMMIT/ROLLBACK**: Một user đang query bảng EMPLOYEES sẽ thấy SALARY = 1000 (giá trị cũ), dù user khác đã UPDATE thành 2000 nhưng chưa COMMIT.
- **Long running queries**: Một query bắt đầu lúc 9:00 AM sẽ thấy dữ liệu tại 9:00 AM, dù có nhiều DML xảy ra sau đó.

> **Lưu ý**: Nếu Undo Data cũ bị ghi đè trước khi query hoàn thành, sẽ xảy ra lỗi **ORA-01555: Snapshot too old**.

### 2.3 Phục hồi transaction thất bại
Khi một transaction bị gián đoạn (máy crash, mất điện), Oracle dùng Undo Data để hoàn tác các thay đổi chưa được commit.

### 2.4 Flashback Queries
Undo Data cho phép truy vấn dữ liệu tại thời điểm trong quá khứ:
```sql
SELECT * FROM EMPLOYEES AS OF TIMESTAMP (SYSTIMESTAMP - INTERVAL '1' HOUR);
```

---

## 3. Nội dung Undo Tablespace

Undo Tablespace chứa các loại dữ liệu:

| Loại | Mô tả |
|------|-------|
| **Active** | Undo của các transaction đang chạy |
| **Unexpired (Old)** | Undo đã commit nhưng chưa hết thời hạn giữ lại — dùng cho read consistency |
| **Expired** | Undo đã qua thời hạn, có thể bị ghi đè |

---

## 4. Quản lý không gian Undo

### 4.1 Tham số UNDO_MANAGEMENT
- **AUTO** (mặc định): Oracle tự quản lý Undo — chế độ khuyến nghị
- **MANUAL**: Quản lý thủ công (không hỗ trợ trong CDB, không khuyến nghị)

### 4.2 Tham số UNDO_TABLESPACE
Chỉ định tablespace Undo đang được sử dụng:

```sql
-- Tạo tablespace Undo mới
CREATE UNDO TABLESPACE undotbs2
  DATAFILE '/u01/oracle/rbdb1/undo2.dbf' SIZE 2M REUSE AUTOEXTEND ON;

-- Chuyển sang dùng tablespace Undo mới
ALTER SYSTEM SET UNDO_TABLESPACE = undotbs2;
```

> **Lưu ý**: Có thể tạo nhiều Undo Tablespace, nhưng chỉ một cái hoạt động tại một thời điểm. Không được tạo object của user trong Undo Tablespace.

---

## 5. Lỗi ORA-01555: "Snapshot Too Old"

### Nguyên nhân
Xảy ra khi một query dài cần đọc Undo Data cũ hơn thời hạn giữ lại hiện tại. Oracle đã ghi đè Undo Data đó vì hết thời hạn.

### Ví dụ
- Query bắt đầu lúc 9:00 AM
- UNDO_RETENTION = 15 phút
- Lúc 9:16 AM, Undo Data cũ (từ trước 9:00 AM) đã bị ghi đè
- Query vẫn đang chạy → **ORA-01555**

### Giải pháp
- Tăng `UNDO_RETENTION`
- Tăng kích thước Undo Tablespace

---

## 6. Undo Retention

### 6.1 UNDO_RETENTION
Tham số chỉ định **thời gian tối thiểu** (tính bằng giây) mà Oracle cố gắng giữ lại Undo Data trước khi ghi đè:

```sql
-- Đặt Undo Retention thành 15 phút (900 giây)
ALTER SYSTEM SET UNDO_RETENTION = 900;

-- Đặt Undo Retention thành 1 giờ (3600 giây)
ALTER SYSTEM SET UNDO_RETENTION = 3600;
```

> **Lưu ý**: Oracle sẽ cố giữ Undo Data trong thời gian này, nhưng **không đảm bảo** (có thể bị ghi đè nếu tablespace đầy).

### 6.2 Vòng đời Undo trong Tablespace

```
[Active] → COMMIT → [Unexpired] → hết UNDO_RETENTION → [Expired] → bị ghi đè
```

---

## 7. Sử dụng V$UNDOSTAT để tinh chỉnh Undo

`V$UNDOSTAT` cung cấp thống kê Undo theo khoảng thời gian 10 phút:

| Cột | Mô tả |
|-----|-------|
| `BEGIN_TIME` | Thời điểm bắt đầu khoảng thống kê |
| `END_TIME` | Thời điểm kết thúc khoảng thống kê |
| `UNDOBLKS` | Tổng số undo blocks đã dùng |
| `MAXQUERYLEN` | Thời gian dài nhất (giây) của query trong khoảng |
| `MAXQUERYID` | SQL ID của query dài nhất |
| `SSOLDERRCNT` | Số lần xảy ra lỗi ORA-01555 |
| `UNXPBLKRELCNT` | Số block unexpired bị lấy lại |
| `TUNED_UNDORETENTION` | Thời gian giữ undo thực tế (giây) |

---

## 8. Tính kích thước Undo Tablespace

### 8.1 Phương pháp thủ công

```
Kích thước Undo = Thời gian giữ lại × Undo blocks/giây × Kích thước block
```

Lấy **Undo blocks/giây** tối đa từ V$UNDOSTAT:

```sql
SELECT MAX(UNDOBLKS / ((END_TIME - BEGIN_TIME) * 3600 * 24)) AS undo_bps
FROM V$UNDOSTAT;
```

**Ví dụ tính toán:**
- Cần giữ Undo 1 giờ = 3600 giây
- Undo blocks/giây = 28
- Block size = 8192 bytes = 8 KB

```
Undo size = 3600 × 28 × 8 KB = 806,400 KB ≈ 787.5 MB
```

### 8.2 Sử dụng Undo Advisor

Undo Advisor sử dụng dữ liệu AWR để đưa ra khuyến nghị:

```sql
-- Xem AWR snapshot để biết BEGIN_ID và END_ID
SELECT SNAP_ID, BEGIN_INTERVAL_TIME, END_INTERVAL_TIME
FROM DBA_HIST_SNAPSHOT
ORDER BY SNAP_ID DESC;

-- Tạo và chạy Undo Advisor Task
DECLARE
  tid    NUMBER;
  tname  VARCHAR2(30);
  oid    NUMBER;
BEGIN
  DBMS_ADVISOR.CREATE_TASK('Undo Advisor', tid, tname, 'Undo Advisor Task');
  DBMS_ADVISOR.CREATE_OBJECT(tname, 'UNDO_TBS', null, null, null, 'null', null, oid);
  DBMS_ADVISOR.SET_TASK_PARAMETER(tname, 'TARGET_OBJECTS', oid);
  DBMS_ADVISOR.SET_TASK_PARAMETER(tname, 'START_SNAPSHOT', 1);  -- thay bằng BEGIN_ID
  DBMS_ADVISOR.SET_TASK_PARAMETER(tname, 'END_SNAPSHOT', 2);    -- thay bằng END_ID
  DBMS_ADVISOR.SET_TASK_PARAMETER(tname, 'INSTANCE', 1);
  DBMS_ADVISOR.EXECUTE_TASK(tname);
END;
/

-- Xem kết quả khuyến nghị
SELECT * FROM DBA_ADVISOR_FINDINGS WHERE TASK_NAME = '<tên_task>';
SELECT * FROM DBA_ADVISOR_RECOMMENDATIONS WHERE TASK_NAME = '<tên_task>';
```

---

## 9. Undo Retention Guarantee

### Vấn đề mặc định
Mặc định, Oracle **có thể** ghi đè Undo Data chưa hết hạn nếu tablespace đầy → gây lỗi ORA-01555.

### Kích hoạt Guarantee

```sql
-- Bật Undo Guarantee (đảm bảo không ghi đè dữ liệu unexpired)
ALTER TABLESPACE undotbs1 RETENTION GUARANTEE;

-- Hoặc khi tạo tablespace
CREATE UNDO TABLESPACE undotbs2 ... RETENTION GUARANTEE;

-- Tắt Guarantee
ALTER TABLESPACE undotbs1 RETENTION NOGUARANTEE;

-- Kiểm tra trạng thái
SELECT RETENTION FROM DBA_TABLESPACES WHERE TABLESPACE_NAME = 'UNDOTBS1';
```

> **Cảnh báo**: Khi bật RETENTION GUARANTEE, các DML transaction có thể **thất bại** do thiếu không gian Undo (vì Oracle từ chối ghi đè Undo unexpired). Cần đảm bảo Undo Tablespace đủ lớn.

---

## 10. Temporary Undo

### Vấn đề mặc định
Khi UPDATE một **temporary table** (bảng tạm), Oracle ghi Undo vào **Undo Tablespace** và tạo **Redo entries** → tốn tài nguyên không cần thiết.

### Kích hoạt Temporary Undo (từ 12c)

```sql
-- Bật ở cấp system
ALTER SYSTEM SET TEMP_UNDO_ENABLED = TRUE;

-- Bật ở cấp session
ALTER SESSION SET TEMP_UNDO_ENABLED = TRUE;
```

**Lợi ích:**
- Undo của temporary table được lưu vào **Temporary Tablespace** thay vì Undo Tablespace
- **Giảm** lượng Undo trong Undo Tablespace
- **Giảm** kích thước Redo Log sinh ra

> **Lưu ý**: Giá trị `TEMP_UNDO_ENABLED` được thiết lập cho session khi lần đầu dùng temporary object và không thay đổi trong phiên đó.

---

## 11. Chế độ Undo trong Multitenant (CDB)

### 11.1 Shared Undo Mode (Chế độ Chia sẻ)
- Chỉ có **một** Undo Tablespace dùng chung cho toàn CDB (nằm ở CDB Root)
- Tất cả PDB đều sử dụng chung một Undo Tablespace này
- Chỉ common user mới có thể tạo Undo Tablespace

### 11.2 Local Undo Mode (Chế độ Cục bộ) — **Khuyến nghị**
- Mỗi PDB có **Undo Tablespace riêng**
- Linh hoạt hơn trong vận hành: unplug PDB, Point-in-Time Recovery
- Bắt buộc cho các tính năng: PDB relocation, PDB cloning

### 11.3 Chuyển đổi chế độ Undo

```sql
-- Khởi động ở chế độ UPGRADE
STARTUP UPGRADE;

-- Bật hoặc tắt Local Undo
ALTER DATABASE LOCAL UNDO ON;   -- chuyển sang Local Undo
ALTER DATABASE LOCAL UNDO OFF;  -- chuyển về Shared Undo

-- Restart lại database
-- Kiểm tra chế độ hiện tại
SELECT PROPERTY_NAME, PROPERTY_VALUE
FROM DATABASE_PROPERTIES
WHERE PROPERTY_NAME = 'LOCAL_UNDO_ENABLED';
```

---

## Tổng kết

| Khái niệm | Điểm chính |
|-----------|-----------|
| Undo Data | Dữ liệu gốc trước khi DML, dùng cho ROLLBACK, read consistency, flashback |
| UNDO_MANAGEMENT | AUTO (mặc định, khuyến nghị) |
| UNDO_RETENTION | Thời gian tối thiểu giữ Undo Data (giây) |
| ORA-01555 | Xảy ra khi Undo Data cũ bị ghi đè trước khi query hoàn thành |
| V$UNDOSTAT | View thống kê Undo theo khoảng 10 phút |
| Undo Guarantee | Đảm bảo không ghi đè unexpired undo (cần tablespace đủ lớn) |
| Temporary Undo | Lưu Undo của temp table vào Temporary Tablespace (từ 12c) |
| Local Undo | Mỗi PDB có Undo riêng — chế độ khuyến nghị cho CDB |


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/39-quan-ly-undo-data.md`
