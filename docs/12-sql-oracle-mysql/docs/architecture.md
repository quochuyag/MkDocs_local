---
title: Architecture
course: 12-sql-oracle-mysql
source: sql_oracle_mysqll/docs/ARCHITECTURE.md
---

# Architecture

## 1) Tổng quan
Hệ thống theo mô hình control plane + adapter:
- Control plane quản lý cấu hình server, lịch thu thập, lưu metadata chuẩn hóa.
- Adapter truy cập trực tiếp từng engine (SQL Server, Oracle, MySQL) để lấy dữ liệu kỹ thuật.

## 2) Thành phần
- API Layer:
  - CRUD server, credentials reference, policy, xem snapshot.
- Scheduler:
  - Tạo job định kỳ (5m, 15m, 1h) cho từng server.
- Collector Workers:
  - Thực thi job, gọi adapter tương ứng, ghi snapshot.
- Adapter Layer:
  - sqlserver_adapter
  - oracle_adapter
  - mysql_adapter
- Metadata Repository:
  - Lưu inventory + snapshot time-series.

## 3) Luồng xử lý chính
1. Admin khai báo server trong control plane.
2. Scheduler tạo job thu thập metadata.
3. Worker chọn adapter theo db_engine.
4. Adapter truy vấn system catalog/dynamic views của engine.
5. Chuẩn hóa dữ liệu và lưu vào bảng snapshot.
6. API trả dữ liệu tổng hợp cho dashboard/report.

## 4) Dữ liệu cần thu thập
- Server:
  - host, port, engine, version, environment, trạng thái kết nối.
- Database:
  - tên DB, trạng thái, charset/collation, created_at.
- Users:
  - account, quyền chính, trạng thái lock/expire (nếu có).
- Size:
  - tổng size, data size, log size theo timestamp.
- Files:
  - logical name, physical path, size, growth policy.
- Processes:
  - session/process id, user, db, command/sql text, elapsed time, status.

## 5) Non-functional
- Bảo mật:
  - Không lưu plaintext password, dùng secret manager hoặc mã hóa.
- Khả năng mở rộng:
  - Tách worker theo queue, scale ngang.
- Độ tin cậy:
  - Retry có backoff, dead-letter cho job lỗi.
- Quan sát:
  - Log có correlation_id, metrics cho từng adapter/job.

## 6) Nguyên tắc chuẩn hóa đa engine
- Dùng mô hình dữ liệu canonical tại control plane.
- Mỗi adapter map trường đặc thù engine -> canonical fields.
- Trường không tương thích để nullable + metadata JSON mở rộng.


---

!!! info "Nguồn gốc"
    `sql_oracle_mysqll/docs/ARCHITECTURE.md`
