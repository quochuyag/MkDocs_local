---
title: Section 2 — Chuẩn bị Môi trường Thực hành (Practice 1)
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/section_all/section_2_preparing_environment_guide.md
---

# Section 2 — Chuẩn bị Môi trường Thực hành (Practice 1)

> Nguồn: Practice 1 - Preparing Practice Environment (Ahmed Baraka, v2.3)
> **Môi trường thực tế đã dựng khác bản gốc** — xem chi tiết tại [ke_hoach/03_phase2_setup_log.md](../ke-hoach/003-phase2-setup-log.md)
> Trạng thái: ✅ Đã dựng xong và kiểm tra PASS toàn bộ (2026-07-13)

---

## 1. Mục tiêu của Practice 1

Chuẩn bị môi trường dùng cho **toàn bộ** practice của khóa học:

1. Một VM Linux chạy Oracle Database (course gọi là `srv1`, database `ORADB`)
2. Schema mẫu **SOE (Order Entry)** — dữ liệu bán hàng ~330 MB, 16 tables (ORDERS, ORDER_ITEMS, CUSTOMERS...) — là "ứng dụng" mà ta sẽ tune xuyên suốt khóa
3. **Swingbench** — công cụ sinh workload OLTP/warehouse giả lập user thật
4. **stress** — công cụ giả lập tải CPU/memory/IO ở mức OS
5. Kỹ năng snapshot/rollback VM — chụp trước mỗi practice, khôi phục khi hỏng

## 2. Course gốc vs. môi trường đã dựng (hiện đại hóa)

Bản gốc (viết ~2017) dùng công nghệ đã hết vòng đời. Ta đã thay bằng stack mới, **giữ nguyên logic học tập**:

| Thành phần | Course gốc | Đã dựng (2026) |
| --- | --- | --- |
| Cách tạo VM | VirtualBox thủ công ~25 bước | **Vagrant** — `vagrant up` 1 lệnh |
| OS | Oracle Linux 6.10 (EOL) | Oracle Linux 7.9 |
| Database | 12.2 non-CDB tên `ORADB` | **19c EE**, CDB `ORCLCDB` + **PDB `ORADB`** |
| Kết nối từ host | IP tĩnh bridged, port 1521 | Port-forward `localhost:15210` (1521 host bị Oracle local chiếm) |
| SSH | Putty | `vagrant ssh` |
| Trao đổi file | Shared folder `sf_extdisk` | `/vagrant` tự mount |
| Snapshot | GUI VirtualBox | `vagrant snapshot save/restore <tên>` |
| stress tool | stress RPM (OL6) | `stress-ng` (yum) |
| Tự khởi động DB | script init.d `dbora` viết tay | systemd có sẵn trong box |

**Điểm khác biệt duy nhất cần nhớ khi làm các practice sau:**

1. Mọi connect string trong PDF: `@ORADB` → `@//localhost:15210/ORADB` (từ host) hoặc `@//localhost:1521/ORADB` (trong VM)
2. Khi làm việc as SYSDBA trong VM: thêm `ALTER SESSION SET CONTAINER = ORADB;` trước (19c là CDB/PDB)
3. Script nào tham chiếu `/u01/app/oracle/...` → đổi thành `/opt/oracle/...`

## 3. Thông số môi trường (tra cứu nhanh)

| Thông số | Giá trị |
| --- | --- |
| Thư mục Vagrant | `D:\Dba_project\vagrant-projects\OracleDatabase\19.3.0` |
| VM | `srv1` — OL7.9, 6 GB RAM, 2 vCPU |
| Database | Oracle 19.3 EE — CDB `ORCLCDB`, PDB `ORADB` |
| Password SYS/SYSTEM | `oracle_4U` |
| Connect từ host | `sqlplus system/oracle_4U@//localhost:15210/ORADB` |
| SOE schema | `soe/soe` — 49 segments, ORDER_ITEMS 3.7 triệu rows |
| Swingbench | `D:\swingbench\start_swingbench.bat` (Java 8 tự cấu hình) |
| Workload configs | `oltp.xml`, `warehouse.xml` (backup: `labs/_workload/`) |
| EM Express | `https://localhost:5500/em` |
| Kiểm tra môi trường | `labs/_toolkit/00_env_check.sql` |

## 4. SOE Schema — hiểu dữ liệu mình sẽ tune

Schema Order Entry mô phỏng hệ thống bán hàng (ERD: `Section 2/SOE+Schema+ERD.pdf`):

- **ORDERS** (1.35M rows) ← **ORDER_ITEMS** (3.7M rows): cặp bảng master-detail chính, nơi phần lớn I/O xảy ra
- **CUSTOMERS** (45K) — ADDRESSES, CARD_DETAILS (55K)
- **PRODUCT_INFORMATION / PRODUCT_DESCRIPTIONS** (1K) — catalog
- **INVENTORIES** (902K) — tồn kho theo warehouse, hay bị lock contention khi update
- **WAREHOUSES** (1K), **LOGON** (442K) — lịch sử đăng nhập
- Package **SOE.ORDERENTRY** — logic nghiệp vụ mà Swingbench gọi

## 5. Swingbench — công cụ sinh tải chính của khóa

- **GUI:** `start_swingbench.bat` → Load tab đặt số users → Start Benchmark. Quan sát 2 chỉ số: **TPM** (throughput) và **Response Time** (độ trễ — cao hơn = tệ hơn)
- **2 cấu hình đã lưu:**
  - `oltp.xml` — giao dịch OLTP (đặt hàng, browse, đăng ký) → dùng cho lab contention, memory, redo
  - `warehouse.xml` — query warehouse nặng → dùng cho lab PGA, I/O, CPU
- **Headless (không GUI):** `charbench -c oltp.xml -u soe -p soe -cs //localhost:15210/ORADB -uc 10 -rt 0:10` (10 users, 10 phút)
- ⚠️ Không bao giờ chạy **oewizard** — sẽ phá schema SOE đã import

## 6. Quy trình mỗi buổi thực hành

```powershell
cd D:\Dba_project\vagrant-projects\OracleDatabase\19.3.0
vagrant up                              # 1. Bật VM (DB tự start)
vagrant snapshot save truoc_practice_X  # 2. Chụp snapshot trước practice "nguy hiểm"
# 3. ... làm practice ...
vagrant snapshot delete truoc_practice_X  # 4a. Xong ổn → xóa snapshot (đỡ tốn disk)
# hoặc: vagrant snapshot restore truoc_practice_X  # 4b. Hỏng → khôi phục
vagrant halt                            # 5. Tắt VM cuối buổi
```

Snapshot nền tảng luôn có sẵn: **`baseline`** (môi trường hoàn chỉnh SOE + tools) và `fresh-install` (Oracle sạch chưa có SOE).

## 7. Những bài học rút ra khi dựng (đáng nhớ cho DBA)

1. **Data Pump không đọc được file trên vboxsf shared folder** (`ORA-27061: async I/O failed`) — luôn copy dump vào filesystem local của VM trước khi impdp. Bài học tổng quát: Data Pump nhạy cảm với filesystem không hỗ trợ async I/O (tương tự với một số NFS mount thiếu option đúng).
2. **Dump 12.2 import thẳng lên 19c** không cần chuyển đổi — Data Pump tương thích xuôi (upward compatible).
3. **Script cũ viết cho non-CDB** chạy trên CDB phải thêm `ALTER SESSION SET CONTAINER` và kiểm tra đường dẫn datafile/OMF trước.
4. **Swingbench 2.5 cần Java 8** — không chạy với Java hiện đại; Oracle client home thường bundle sẵn JRE 8 dùng được.
5. Xung đột port trên máy host là chuyện thường — kiểm tra `Get-NetTCPConnection -LocalPort 1521` trước khi quy hoạch port forwarding.

## 8. Checklist xác nhận môi trường (đã PASS 2026-07-13)

Chạy `labs/_toolkit/00_env_check.sql` bất kỳ lúc nào nghi ngờ môi trường:

- [x] Oracle 19c, PDB ORADB READ WRITE
- [x] `control_management_pack_access = DIAGNOSTIC+TUNING` (điều kiện dùng AWR/ASH/ADDM)
- [x] SOE: 49 segments, 0 invalid objects, ORDER_ITEMS 3.7M rows
- [x] Swingbench benchmark 10 users chạy được, TPM tăng ổn định
- [x] stress-ng + sysstat trong VM
- [x] Snapshot `baseline` sẵn sàng


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/section_all/section_2_preparing_environment_guide.md`
