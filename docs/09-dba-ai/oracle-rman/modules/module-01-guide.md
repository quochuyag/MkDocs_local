---
title: '📘 Module 01: Giới thiệu Khóa học & Chuẩn bị Môi trường Thực hành (Lab Setup)'
course: 09-dba-ai
source: dba_ai/oracle_rman/modules/module_01_guide.md
---

# 📘 Module 01: Giới thiệu Khóa học & Chuẩn bị Môi trường Thực hành (Lab Setup)

> **Module**: 01/17 (Module Khởi động)
> **Phạm vi**: Bài 01 đến 05 (Lý thuyết Giới thiệu & Thực hành Practice 1)
> **Giảng viên**: Ahmed Baraka
> **Thời gian ước tính**: 3 - 4 giờ (Đa số thời gian dùng để cài đặt máy ảo)
> **Nguồn PDF**: `pdf_extracted/module_01/`

---

## 📑 Mục lục

- [Phần 1: Giới thiệu Khóa học](#-phần-1-giới-thiệu-khóa-học)
- [Phần 2: Chuẩn bị Môi trường Máy ảo (Practice 1)](#-phần-2-chuẩn-bị-môi-trường-máy-ảo-practice-1)
- [Lời khuyên khi làm Lab](#-lời-khuyên-cho-giai-đoạn-setup)

---

# 📖 Phần 1: Giới thiệu Khóa học

Khóa học **"Oracle Database 12c Backup and Recovery using RMAN"** được thiết kế bởi chuyên gia Ahmed Baraka (hơn 20 năm kinh nghiệm DBA) với mục tiêu đào tạo học viên trở thành kỹ sư thành thạo các kỹ năng sao lưu, phục hồi và xử lý thảm họa cơ sở dữ liệu trên môi trường Oracle 12c (Release 2).

### 1. Kỹ năng bạn sẽ đạt được:
- Sử dụng RMAN để thực hiện tất cả các chiến lược Backup: Toàn phần (Whole)/Một phần (Partial), Full/Incremental, và Complete/Incomplete.
- Sử dụng các tùy chọn Backup nâng cao: Nén (Compression), Mã hóa (Encryption), Đa luồng (Multisection), và Sao lưu lưu trữ (Archival Backups).
- Khắc phục mọi thảm họa phổ biến: Mất file cốt lõi (Control files, Redo logs), mất Datafiles, hay rớt mất Data Application (Tables).
- Vận chuyển dữ liệu chéo nền tảng (Cross-platform Data Transportation).
- Nhân bản hệ thống (Duplicate Database).
- Tối ưu RMAN trong kiến trúc Cụm (RAC), Đa người thuê (Multitenant), và Đám mây (Cloud Service).

### 2. Yêu cầu đầu vào (Prerequisites):
- Có kiến thức vận hành Quản trị CSDL Oracle cơ bản.
- Có kỹ năng sử dụng lệnh Linux (Command line) căn bản.

---

# 🎯 Phần 2: Chuẩn bị Môi trường Máy ảo (Practice 1)

Bài Lab khởi động (Practice 1) yêu cầu bạn một máy tính cá nhân cài đặt **Windows 64-bit** (khuyên dùng RAM >= 12GB và 170GB ổ cứng trống). Trọng tâm của bài Lab là cài đặt phần mềm Oracle VirtualBox để tạo ra 2 Máy chủ ảo mô phỏng môi trường Data Center.

### 1. Kiến trúc Lab cốt lõi ⭐⭐⭐

Bạn sẽ cần phân bổ 2 cỗ máy ảo (VirtualBox Appliances) có cấu hình chung là **CPU 2 Cores + 4GB RAM + Card mạng Bridged**:

- **Máy chủ 1: `srv1` (Hệ điều hành Linux)**
  - Chạy Oracle Linux 6.10 (64-bit).
  - Nhiệm vụ: Đóng vai trò là **Máy tính Production chính** của khóa học. Sẽ được cài Oracle Database 12c R2 và chạy một cơ sở dữ liệu mang tên `ORADB`.
  
- **Máy chủ 2: `winsrv2` (Hệ điều hành Windows Server)**
  - Chạy Windows Server 2012/2016.
  - Nhiệm vụ: Là máy khách/máy dự phòng. Cài Oracle Database 12c R2 chạy một CSDL mang tên `ORAWIN`. Máy này sẽ được dùng để lưu trữ Catalog và thực tập mô hình sao chép Cross-Platform OS (Linux bắn qua Windows).

### 2. Các ứng dụng Bổ trợ quan trọng
- **PuTTY:** Công cụ kết nối SSH từ máy Host vào Linux `srv1` để gõ lệnh dòng lệnh tiện lợi hơn.
- **Thư mục chia sẻ (Shared Folders):** Quy hoạch một ổ đĩa `C:\staging` hoặc `D:\staging` nằm trên máy Host nối thẳng vào 2 máy ảo (bằng tính năng VirtualBox Guest Additions). Chỗ này để chia sẻ File Backup giữa 2 hệ điều hành.
- **Ứng dụng Swingbench:** Phần mềm sinh tải dữ liệu chuyên nghiệp (Cần cài đặt Java Runtime JRE). Bạn sẽ dùng lệnh `oewizard` của Swingbench để kết nối vào Database `ORADB` và bơm vào đó dữ liệu mảng **Order Entry (SOE)** - hệ thống đơn hàng mô phỏng Data thực tế suốt khóa học.

---

# 💡 Lời khuyên cho Giai đoạn Setup

**1. Luôn Snapshots Máy Ảo:** 
Sau khi bạn cài xong HDĐ, cài xong CSDL và bơm chuẩn Data của Swingbench rồi, tuyệt đối hãy dùng chức năng **Take Snapshot** của VirtualBox. Đây là cái neo an toàn để bạn thoải mái luyện tập "phá hủy" Datafiles ở những Module sau rồi Restart lại điểm neo này mà không phải cài lại máy từ con số 0.

**2. Đừng cài RAM quá thấp:** 
Oracle Database 12c bản Enterprise cực kì ăn RAM. Tổng cộng 2 máy ảo cần chạy ít nhất 4GB x 2 = 8GB RAM, cộng thêm Windows Máy Host, nên 12GB là con số an toàn. Nếu máy Host của bạn yếu, bạn có thể chỉnh RAM của `winsrv2` xuống một chút và chỉ khởi động nó lên khi học các bài Lab có kết nối RMAN Catalog.

**3. Khắc phục lỗi Mạng (NAT / Bridged):** 
Nếu máy Host (Máy thật) không ping được vào IP của 2 máy ảo, hãy kiểm tra lại cấu hình Network Adapter trong giao diện VirtualBox. Ở môi trường dùng chung mạng xài Wifi gia đình, để 2 máy ảo ở chế độ **Bridged Adapter** là dễ có IP nhất.

> Rất vui khi được đồng hành cùng anh dọn xong nền móng hạ tầng của Module 1! Toàn bộ 17 Mảnh ghép của khóa học đã hội tụ đủ. Mời anh xem qua thiết lập của Module Khởi động này và chúc anh thành công khi chạy thực thi Cài đặt Máy ảo nhé! 🚀


---

!!! info "Nguồn gốc"
    `dba_ai/oracle_rman/modules/module_01_guide.md`
