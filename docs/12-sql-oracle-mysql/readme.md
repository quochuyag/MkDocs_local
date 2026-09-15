---
title: SQL Multi-Server Management Platform
course: 12-sql-oracle-mysql
source: sql_oracle_mysqll/README.md
---

# SQL Multi-Server Management Platform

Nền tảng quản lý tập trung nhiều máy chủ CSDL: SQL Server, Oracle, MySQL.

## Mục tiêu
- Quản lý tập trung nhiều server theo môi trường (dev, uat, prod).
- Theo dõi trên từng server:
  - Database
  - User / Account
  - Database size
  - Data files / log files
  - File path
  - Process đang chạy (sessions / jobs / long-running queries)

## Chức năng chính
- Inventory:
  - Đăng ký server, thông tin kết nối, loại CSDL, phiên bản.
- Discovery:
  - Thu thập định kỳ metadata (db, user, file, size, process).
- Monitoring:
  - Snapshot theo thời gian để so sánh tăng trưởng dung lượng.
  - Cảnh báo tiến trình chạy lâu hoặc bất thường.
- RBAC:
  - Phân quyền xem theo nhóm server/môi trường.

## Kiến trúc đề xuất
- Control Plane (trung tâm):
  - API + Scheduler + Metadata Repository.
- Collector/Adapter theo loại CSDL:
  - sqlserver, oracle, mysql.
- Storage:
  - Metadata database dùng chung (schema ở sql/control_plane_schema.sql).

Xem chi tiết tại docs:
- docs/ARCHITECTURE.md
- docs/DATA_MODEL.md
- docs/COLLECTOR_QUERY_HINTS.md

## Cấu trúc thư mục gợi ý
- src/api: REST API quản trị
- src/services: nghiệp vụ
- src/adapters: kết nối từng loại CSDL
- src/collectors: job thu thập metadata
- src/scheduler: lịch chạy và retry
- sql: schema, migration
- docs: tài liệu kiến trúc và mô hình dữ liệu

## Lộ trình triển khai
1. Khởi tạo metadata schema và API server.
2. Làm adapter MySQL trước, sau đó SQL Server, Oracle.
3. Triển khai scheduler thu thập snapshot theo chu kỳ.
4. Bổ sung cảnh báo, dashboard và phân quyền.


---

!!! info "Nguồn gốc"
    `sql_oracle_mysqll/README.md`
