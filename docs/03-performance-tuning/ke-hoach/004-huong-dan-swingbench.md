---
title: Hướng dẫn cài đặt & cấu hình Swingbench 2.5 (Bước 3 — bạn tự thao tác GUI)
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/ke_hoach/04_huong_dan_swingbench.md
---

# Hướng dẫn cài đặt & cấu hình Swingbench 2.5 (Bước 3 — bạn tự thao tác GUI)

> Tạo ngày: 2026-07-13 · Thuộc Giai đoạn 2, Bước E trong [02_phase2_environment_vagrant_plan.md](002-phase2-environment-vagrant-plan.md)
> Swingbench là công cụ sinh workload chuẩn của khóa học — dùng lại trong hầu hết practice sau này.

---

## Phần Claude đã làm sẵn cho bạn ✅

| Việc | Kết quả |
| --- | --- |
| Giải nén Swingbench 2.5.971 | `D:\swingbench` |
| Tìm Java 8 (Swingbench 2.5 KHÔNG chạy với Java 25 trên PATH của máy) | Dùng Java 1.8.0_291 bundle trong Oracle home local: `D:\ORACLE\jdk\jre\bin` |
| Tạo launcher tự set đúng Java | **`D:\swingbench\start_swingbench.bat`** — chỉ cần double-click |
| SOE schema trong VM | Đang import (Claude sẽ xác nhận khi xong — chờ xác nhận rồi hãy làm Bước 3 dưới đây) |

**Thông tin kết nối (dùng ở Bước 2):**

| Trường | Giá trị |
| --- | --- |
| Username | `soe` |
| Password | `soe` |
| Connect String | `//localhost:15210/ORADB` ← **port 15210, KHÔNG phải 1521** (1521 bị Oracle local của bạn chiếm) |
| Driver Type | Oracle jdbc Driver (thin) |

---

## Bước 1 — Khởi động Swingbench

1. Đảm bảo VM đang chạy (nếu chưa: mở PowerShell → `cd D:\Dba_project\vagrant-projects\OracleDatabase\19.3.0` → `vagrant up`)
2. Double-click **`D:\swingbench\start_swingbench.bat`**
3. Cửa sổ Swingbench mở ra, bên trái là cây cấu hình, bên phải là các tab

> ⚠️ **TUYỆT ĐỐI KHÔNG chạy "Order Entry Wizard" (oewizard)** — schema SOE đã được import sẵn vào database. Chạy wizard sẽ ghi đè/làm hỏng schema.

Nếu cửa sổ không mở: mở cmd, chạy `D:\swingbench\start_swingbench.bat` từ terminal để xem lỗi, chụp màn hình gửi Claude.

## Bước 2 — Cấu hình kết nối (tab User Details)

1. Chọn tab **User Details**, điền:
   - **Username:** `soe`
   - **Password:** `soe`
   - **Connect String:** `//localhost:15210/ORADB`
   - **Driver Type:** giữ `Oracle jdbc Driver` (thin)
2. Bấm nút **Test Connection** (biểu tượng ổ cắm/nút test)
3. Kỳ vọng: thông báo **"Connection Successful"** (hoặc tương tự)

Nếu lỗi kết nối:

| Lỗi | Nguyên nhân | Xử lý |
| --- | --- | --- |
| `IO Error: The Network Adapter could not establish the connection` | VM chưa chạy hoặc gõ nhầm port | `vagrant up`; kiểm tra connect string có `:15210` |
| `ORA-01017: invalid username/password` | SOE chưa import xong hoặc gõ nhầm | Chờ Claude xác nhận import xong |
| `ORA-12514: listener does not currently know of service` | Gõ nhầm service name | Phải là `ORADB` (không phải ORCLCDB) |

## Bước 3 — Chạy thử benchmark (xác nhận môi trường hoạt động)

1. Sang tab **Load**: đặt **Number of Users = 10** (số session Swingbench sẽ mở vào DB)
2. Bấm nút **Start Benchmark Run** (nút play ▶ trên toolbar)
3. Quan sát ~2–3 phút:
   - Biểu đồ **Transactions Per Minute (TPM)** tăng dần rồi bão hòa → đạt
   - Biểu đồ **Response Time**: ghi nhớ giá trị trung bình — đây là "cảm giác baseline" về hiệu năng, các lab sau sẽ so với nó
4. Bấm **Stop Benchmark Run** (nút stop ■)

## Bước 4 — Tạo 2 file cấu hình workload (dùng cho toàn khóa học)

Đây là bước quan trọng nhất — 2 file này được các practice sau gọi lại nhiều lần.

**Lấy tỷ lệ chính xác:** mở file PDF `Section 2/Practice+1+-+Preparing+Practice+Environment.pdf` **trang 21–22** — tỷ lệ nằm trong 2 screenshot (bản text extract không giữ được hình).

**4a. File `oltp.xml` (workload OLTP):**

1. Sang tab **Transactions**
2. Set tỷ lệ (cột Load Ratio) theo screenshot **trang 21** của PDF — nhóm giao dịch OLTP được bật (Customer Registration, Browse Products, Order Products, Process Orders, Browse Orders)
   - ⚠️ Mẹo từ tác giả: gõ số trực tiếp vào ô ratio có thể bị nhảy về giá trị cũ — **dùng mũi tên lên/xuống** của ô thay vì gõ
3. Bấm nút **Save** (lưu vào swingconfig.xml)
4. Menu **File → Save Benchmark As...** → lưu thành `D:\swingbench\winbin\oltp.xml`

**4b. File `warehouse.xml` (workload warehouse):**

1. Vẫn tab **Transactions**, đổi tỷ lệ theo screenshot **trang 22** — nhóm warehouse được bật (Warehouse Query, Warehouse Activity Query...)
2. Menu **File → Save Benchmark As...** → lưu thành `D:\swingbench\winbin\warehouse.xml`

**4c. Thoát:** File → Exit

## Bước 5 — Báo Claude sau khi xong

Nhắn "swingbench xong" — Claude sẽ:

1. Copy backup `oltp.xml` + `warehouse.xml` vào `labs/_workload/` trong dự án (không mất khi cài lại Swingbench)
2. Cập nhật checklist [03_phase2_setup_log.md](003-phase2-setup-log.md)
3. Tiếp tục bước còn lại (stress-ng trong VM, snapshot baseline, env check script)

---

## Tham khảo — chạy workload không cần GUI (dùng trong lab sau này)

```bat
cd /d D:\swingbench\winbin
set PATH=D:\ORACLE\jdk\jre\bin;%PATH%
rem 10 users, chạy 10 phút, workload OLTP:
charbench -c oltp.xml -u soe -p soe -cs //localhost:15210/ORADB -uc 10 -rt 0:10
```


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/ke_hoach/04_huong_dan_swingbench.md`
