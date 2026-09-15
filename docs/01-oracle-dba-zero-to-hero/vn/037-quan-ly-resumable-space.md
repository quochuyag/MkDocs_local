---
title: 'Bài 37: Quản lý Resumable Space Allocation'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/37-quan-ly-resumable-space.md
---

# Bài 37: Quản lý Resumable Space Allocation

## Mục tiêu
Sau bài này, bạn sẽ có thể:
- Mô tả cơ chế **resumable space allocation**
- Kích hoạt resumable space allocation
- Xác định các thao tác có thể resumable
- Cấu hình **timeout** cho resumable
- Dùng **LOGON trigger** để thiết lập mặc định
- Dùng **AFTER SUSPEND trigger** để xử lý sự kiện

---

## 1. Vấn đề và Giải pháp

### Tình huống thực tế:
```
Tablespace (100M)
  └── Datafile (100M)
       └── Table (segment)
            ← Đang nạp 150MB dữ liệu
```

**Không có Resumable**: Lỗi xảy ra ngay lập tức:
```
ORA-01653: unable to extend table ... in tablespace ...
```

**Có Resumable**: Statement tạm dừng (suspend) → DBA thêm datafile → Statement tiếp tục!

---

## 2. Resumable Space Allocation là gì?

- Cơ chế **tạm dừng** (suspend) và sau đó **tiếp tục** (resume) thực thi các thao tác database tiêu tốn nhiều space
- DBA có thể giải quyết vấn đề hoặc hủy session bị tạm dừng
- Sau khi giải quyết xong, statement tạm dừng sẽ tự tiếp tục
- **Yêu cầu**: User phải có system privilege `RESUMABLE`

---

## 3. Các Lỗi có thể được Xử lý (Correctable Errors)

| Lỗi | Mã lỗi |
|-----|--------|
| Hết không gian (Out of space) | `ORA-01653`, `ORA-01654` |
| Đạt giới hạn extents tối đa | `ORA-01631` |
| Vượt quota không gian | `ORA-01536` |

```
ORA-01653: unable to extend table ... in tablespace ...
ORA-01654: unable to extend index ... in tablespace ...
ORA-01631: max # extents ... reached in table ...
ORA-01536: space quota exceeded for tablespace "string"
```

---

## 4. Cách hoạt động của Resumable Space Allocation

### Bước 1: Kích hoạt Resumable

Statement chỉ chạy ở chế độ resumable khi **một trong hai điều kiện** sau đúng:
- `RESUMABLE_TIMEOUT` được đặt giá trị khác 0 **VÀ** `ALTER SESSION ENABLE RESUMABLE` được thực thi
- `ALTER SESSION ENABLE RESUMABLE TIMEOUT <n>` được thực thi với n ≠ 0

### Bước 2: Statement bị tạm dừng khi

- Hết không gian (Out of space)
- Đạt giới hạn extents tối đa
- Vượt quota không gian

### Bước 3: Khi bị tạm dừng, các hành động tự động

- Lỗi được ghi vào **alert log**
- System tạo cảnh báo **Resumable Session Suspended**
- **AFTER SUSPEND trigger** (nếu có) được thực thi

### Bước 4-7: Quy trình xử lý

4. DBA/User được **thông báo** về vấn đề (qua trigger, email, SMS)
5. DBA **giải quyết** vấn đề → statement tự tiếp tục
6. Có thể **hủy bắt buộc** với `DBMS_RESUMABLE.ABORT()`
7. Nếu không giải quyết trong thời gian timeout → statement trả về exception

> **Lưu ý**:
> - Một statement có thể bị suspend và resume **nhiều lần** trong một lần thực thi
> - Có thể bật/tắt resumable theo từng statement: `ALTER SESSION DISABLE RESUMABLE`

---

## 5. Các Thao tác có thể Resumable

| Loại | Ví dụ |
|------|-------|
| DML | `INSERT`, `UPDATE`, `DELETE` |
| DDL tạo segments | `CREATE TABLE`, `CREATE INDEX`, `CREATE MATERIALIZED VIEW` |
| Data Pump Import | Utility import dữ liệu |
| SQL Loader | Tham số dòng lệnh kiểm soát |
| Queries | Queries hết temporary space |

---

## 6. Cấu hình Timeout

Parameter `RESUMABLE_TIMEOUT` có thể được set ở cấp **system** hoặc **session**:

- Giá trị `0` = resumable space allocation **bị tắt** (mặc định)

```sql
-- Kích hoạt với timeout 1 giờ (3600 giây):
ALTER SESSION ENABLE RESUMABLE TIMEOUT 3600;
```

---

## 7. Dùng LOGON Trigger để Đặt Mặc định

Tạo LOGON trigger ở cấp database để tự động kích hoạt resumable cho user/schema:

```sql
CREATE OR REPLACE TRIGGER trg_resumable
AFTER LOGON
ON hr.SCHEMA
BEGIN
  EXECUTE IMMEDIATE 'ALTER SESSION ENABLE RESUMABLE TIMEOUT 600';
END;
/
```

---

## 8. Xử lý Sự kiện: AFTER SUSPEND Trigger

Dùng `AFTER SUSPEND` trigger để tự động thông báo và xử lý:

```sql
CREATE OR REPLACE TRIGGER resumable_trg
AFTER SUSPEND ON DATABASE
BEGIN
  /*
    Thêm code ở đây để:
    - Gửi email/SMS thông báo cho DBA
    - Ghi log
    - Thay đổi timeout
  */

  -- Thay đổi timeout của session bị tạm dừng
  DBMS_RESUMABLE.SET_TIMEOUT(900);
END;
/
```

---

## 9. Xem thông tin Session bị Tạm dừng

| View | Mô tả |
|------|-------|
| `DBA_RESUMABLE` / `USER_RESUMABLE` | Lấy thông tin các resumable statements đang thực thi hoặc bị tạm dừng |
| `V$SESSION_WAIT` | Khi statement bị tạm dừng, cột `EVENT` = `"statement suspended, wait error to be cleared"` |

---

## 10. Package DBMS_RESUMABLE

| Procedure/Function | Mô tả |
|-------------------|-------|
| `ABORT(sessionID)` | Hủy statement resumable đang bị tạm dừng |
| `GET_SESSION_TIMEOUT(sessionID)` | Lấy giá trị timeout của session theo sessionID |
| `GET_TIMEOUT()` | Lấy giá trị timeout của session hiện tại |
| `SET_TIMEOUT(timeout)` | Đặt giá trị timeout cho session hiện tại |

---

## 11. Best Practices

- **Tuyến phòng thủ thứ hai**: Theo dõi free space chủ động là ưu tiên số 1; resumable là biện pháp dự phòng
- Áp dụng khi có các **quy trình nạp dữ liệu lớn**, thời gian dài
- Dùng dictionary views để theo dõi trạng thái (executing hay suspended)
- Học từ sự cố để cải thiện lập kế hoạch storage

---

## Tổng kết

```
Thao tác hết space
       ↓
Statement SUSPEND (không bị lỗi ngay)
       ↓
Alert log + Trigger AFTER SUSPEND
       ↓
DBA được thông báo
       ↓
DBA thêm datafile/tăng quota
       ↓
Statement tự RESUME ✓
```


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/37-quan-ly-resumable-space.md`
