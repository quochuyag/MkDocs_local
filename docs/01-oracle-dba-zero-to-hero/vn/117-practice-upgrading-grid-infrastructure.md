---
title: 'Bài 117: Thực hành - Nâng cấp Oracle Grid Infrastructure'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/117-practice-upgrading-grid-infrastructure.md
---

# Bài 117: Thực hành - Nâng cấp Oracle Grid Infrastructure

## Mục tiêu
Trong bài thực hành cuối cùng này, bạn sẽ làm quen với việc:
- Hiểu quy trình nâng cấp Oracle Grid Infrastructure từ bản 19c lên 21c (Trên máy chủ có ASM `srv1-asm`).
- Sử dụng tiện ích Cluster Verification Utility (CVU) để kiểm tra tính tương thích.
- Chạy cài đặt nâng cấp bằng phần mềm dạng đồ họa (OUI).

## Nguyên lý cơ bản
Grid Infrastructure (Clusterware và ASM) là lớp phần mềm quản lý ổ cứng và hạ tầng mạng bên dưới Database. Nguyên tắc bất di bất dịch của Oracle: **Bạn PHẢI nâng cấp Grid Infrastructure lên bản mới TRƯỚC, rồi sau đó mới được nâng cấp Database.** 

Grid Infrastructure tương thích ngược (Ví dụ Grid 21c chạy tốt với Database 19c). Nhưng Database mới KHÔNG BAO GIỜ có thể chạy trên Grid cũ (Database 21c không thể cắm vào Grid 19c).

## Các bước thực hiện

**1. Khởi tạo môi trường Grid mới**
- Đăng nhập bằng tải khoản OS `grid`.
- Tạo một thư mục `GRID_HOME` hoàn toàn mới cho 21c, ví dụ: `/u01/app/21.0.0/grid`.
- Giải nén phần mềm cài đặt `LINUX.X64_213000_grid_home.zip` thẳng vào thư mục mới này (Từ 19c trở đi, Oracle đóng gói dạng image, phải giải nén đúng thư mục nhà luôn).

**2. Quét kiểm tra sức khỏe bằng CVU (Cluster Verification Utility)**
- Di chuyển vào thư mục Grid mới: `cd /u01/app/21.0.0/grid/`
- Chạy tiện ích phân tích lỗi trước khi cài:
```bash
./runcluvfy.sh stage -pre crsinst -upgrade -rolling -src_crshome /u01/app/19.0.0/grid -dest_crshome /u01/app/21.0.0/grid -dest_version 21.0.0.0.0 -fixup -verbose
```
*(Nếu nó báo lỗi RAM thiếu 1 chút so với 8GB thì có thể bỏ qua).*

**3. Dừng Database**
- Vì chúng ta đang nâng cấp hạ tầng bên dưới, hãy tắt Database bằng quyền `oracle`:
```bash
srvctl stop database -d oradb -o immediate
```
*(Chú ý: Dừng database nhưng KHÔNG ĐƯỢC tắt tiến trình của Grid/ASM).*

**4. Chạy Cài đặt Nâng cấp (Installer)**
- Bằng user `grid`, đảm bảo đã gỡ bỏ các biến môi trường ORACLE_HOME cũ (`unset ORACLE_HOME`).
- Chạy cài đặt từ thư mục 21c: `./gridSetup.sh`.
- Tại màn hình đồ họa Configuration Option, HỆ THỐNG SẼ TỰ ĐỘNG NHẬN DIỆN MÔI TRƯỜNG CŨ và hỏi bạn: "Bạn có muốn Upgrade Oracle Grid Infrastructure không?". Hãy chọn nó.
- Tích vào nút "Automatically Run Configuration Scripts" và gõ mật khẩu `root` để nó tự chạy script cập nhật OS mà không bắt ta phải mở thêm cửa sổ Terminal gõ tay.
- Bấm Next đến cuối và chờ đợi hệ thống tự nâng cấp.

**5. Hoàn tất & Cập nhật tương thích ASM**
- Cập nhật lại biến môi trường `ORACLE_HOME` trong `.bash_profile` của `grid` trỏ tới `/21.0.0`.
- Gỡ đăng ký (detach) thư mục Grid 19c cũ ra khỏi hệ thống Inventory.
- Kết nối vào ASM (Bằng `sysasm`) và nâng mức tương thích đĩa cứng (Compatible Attribute) lên hệ 21c để tận dụng các tính năng I/O mới nhất.
```sql
ALTER DISKGROUP data SET ATTRIBUTE 'compatible.asm' = '21.0.0.0.0';
```
- Bật Database lại (`srvctl start database -d oradb`). Sau bước này, bạn đã có thể bắt đầu cài phần mềm DB 21c để nâng cấp DB như Bài 116.

---
## Câu hỏi ôn tập

**Câu 1: Chuyện gì xảy ra nếu tôi lỡ tay nâng cấp phần mềm Database (từ 19c lên 21c) xong rồi mới đi nâng cấp Grid Infrastructure (ASM)?**
- **Trả lời:** Database 21c của bạn sẽ không bao giờ khởi động được. Nó sẽ văng lỗi phiên bản không tương thích (Incompatible version) vì các thư viện giao tiếp của nó từ chối làm việc với ASM hệ 19c.

**Câu 2: "Tương thích ngược" (Backward Compatibility) của Grid mang lại lợi ích gì trong doanh nghiệp?**
- **Trả lời:** Nó giúp tối thiểu hóa thời gian hệ thống ngừng hoạt động (Downtime). Bạn có thể ngừng máy vài chục phút vào thứ Bảy để nâng cấp Grid lên 21c, trong khi vẫn để Database 19c chạy phục vụ kinh doanh. Tháng sau bạn mới phải xin lịch dừng máy để nâng cấp Database 19c lên 21c.

**Câu 3: Tiện ích `runcluvfy.sh` (CVU) đóng vai trò gì?**
- **Trả lời:** CVU là công cụ kiểm tra sức khỏe cực kỳ khắc nghiệt. Nó đi kiểm tra độ trễ mạng, tình trạng đồng hồ (NTP), thông số kernel OS, cấp quyền hệ điều hành. Nếu CVU báo đỏ, bạn tuyệt đối không nên cài đặt để tránh thảm họa gián đoạn hệ thống.

**Câu 4: Chức năng `Automatically Run Configuration Scripts` cung cấp tiện ích gì khi cài đặt?**
- **Trả lời:** Trước đây (bản 11g, 12c), đến 90% quá trình cài, trình cài đặt sẽ bị dừng lại và hiện một popup bắt bạn mở cửa sổ dòng lệnh root ra, copy paste bằng tay cái file `rootupgrade.sh`. Bằng việc nhập thẳng password root vào giao diện, OUI sẽ gọi một tiến trình bảo mật ngầm chạy thay bạn, giúp mọi thứ liền mạch từ đầu tới cuối.

**Câu 5: Tại sao tôi lại phải gỡ đăng ký (detach) thư mục Grid 19c cũ ra khỏi `inventory.xml`?**
- **Trả lời:** Cuốn sổ trung tâm `oraInventory` theo dõi mọi phần mềm cài trên máy. Nếu không gỡ 19c cũ ra, OPatch hoặc các công cụ báo cáo bảo mật của Oracle vẫn sẽ quét cái thư mục 19c đó, gây thông báo rác hoặc nhầm lẫn khi áp dụng bản vá bảo mật hàng quý. Bỏ theo dõi nó sẽ giúp bạn an tâm xóa thư mục cũ đi.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/117-practice-upgrading-grid-infrastructure.md`
