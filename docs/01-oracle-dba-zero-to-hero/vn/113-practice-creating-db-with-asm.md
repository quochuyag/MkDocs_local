---
title: 'Bài 113: Thực hành - Tạo cơ sở dữ liệu trên Oracle ASM'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/113-practice-creating-db-with-asm.md
---

# Bài 113: Thực hành - Tạo cơ sở dữ liệu trên Oracle ASM

## Mục tiêu
Trong bài thực hành này, bạn sẽ cấu hình và cài đặt một máy chủ hoàn toàn mới sử dụng kiến trúc Grid Infrastructure Standalone (Oracle Restart) kết hợp với ASM.

*Lưu ý: Vì yêu cầu có 2 tiến trình Instance cùng chạy (ASM Instance + Database Instance), máy ảo cần cấu hình RAM tối thiểu là 8GB.*

## A. Chuẩn bị Hệ thống và Ổ cứng ảo
**1.** Clone máy ảo "Linux7-seed" thành máy `srv1-asm`. Chỉnh sửa RAM lên 8GB.
**2.** Cấu hình IP tĩnh và khai báo vào file `/etc/hosts` tương tự như máy `srv1` cũ.
**3.** Trong giao diện VirtualBox, thêm 2 ổ cứng ảo hoàn toàn trống (Virtual Hard Disks) loại `VDI` (Dynamically allocated) chưa được định dạng:
- `OCRDISK1.vdi`: 12 GB
- `DATADISK1.vdi`: 12 GB
*(Đây chính là các ổ đĩa thô Raw Disks sẽ cung cấp cho hệ thống ASM).*

**4.** Cấu hình biến môi trường Linux. Lúc này hệ thống sẽ có 2 tài khoản quản trị riêng biệt:
- OS User `oracle`: Quản lý các file thuộc về Database Software.
- OS User `grid`: Chuyên quản lý ASM và Grid Infrastructure Software.

## B. Cài đặt Grid Infrastructure & Tạo ASM
**5.** Cài đặt thư viện kernel `oracleasm`:
```bash
yum install oracleasm-support oracleasmlib
```
**6.** Khởi tạo ổ đĩa ASM từ các đĩa thô vừa cắm vào (ví dụ `/dev/sdb`, `/dev/sdc`):
```bash
oracleasm createdisk OCRDISK /dev/sdb1
oracleasm createdisk DATADISK /dev/sdc1
```
*(Tiến trình này dán nhãn cho đĩa thô để phần mềm ASM nhận diện).*

**7.** Giải nén bộ cài đặt `Grid Infrastructure 19c` vào một thư mục được gọi là `GRID_HOME` (Ví dụ `/u01/app/19.0.0/grid`).
**8.** Chạy file cài đặt `gridSetup.sh` bằng tài khoản `grid`. Trong quá trình cài đặt, trình hướng dẫn (GUI) sẽ yêu cầu bạn:
- Khởi tạo 1 Disk Group đầu tiên. Đặt tên nó là `+OCRDISK` (Gắn ổ ảo 12GB số 1 vào).
- Chọn Redundancy là `EXTERNAL` (Không bật chức năng mirror dự phòng của ASM vì ta chỉ dùng 1 đĩa ảo).

**9.** Sau khi cài xong, đăng nhập bằng `grid`, chạy lệnh quản lý hệ thống cluster để xem các tiến trình đang hoạt động:
```bash
crsctl status resource -t
```
*(Bạn sẽ thấy tiến trình `ora.asm` đang báo trạng thái ONLINE).*

## C. Cài đặt Database Software và Khởi tạo CSDL
**10.** Dùng công cụ `asmca` (ASM Configuration Assistant) bằng user `grid` để tạo thêm một Disk Group số 2, đặt tên là `+DATA` (Gắn đĩa 12GB số 2 vào).
**11.** Bây giờ chuyển sang tài khoản OS `oracle`, cài đặt phần mềm Oracle Database 19c bình thường.
**12.** Chạy `dbca` để tạo CSDL tên là `oradb`. 
- Tại phần khai báo vị trí lưu trữ (Storage Type), không chọn `File System` nữa. Bạn **PHẢI** chọn **Automatic Storage Management (ASM)**.
- Gõ tên nhóm đĩa là `+DATA` vào. 
- Khai báo mật khẩu sysdba của ASM Instance.
**13.** Database tạo xong! Vào SQL*Plus, bạn kiểm tra sẽ thấy Datafile có đường dẫn kiểu OMF kỳ lạ: `+DATA/ORADB/DATAFILE/system.257.xxxx`.
**14.** Dùng công cụ `asmcmd` bằng tài khoản `grid` để duyệt cấu trúc thư mục của ASM giống y hệt như terminal của Linux:
```bash
asmcmd
ASMCMD> ls -l
ASMCMD> cd +DATA/ORADB
```

---
## Câu hỏi ôn tập

**Câu 1: Tại sao lại phải tách riêng tài khoản OS `oracle` và `grid`?**
- **Trả lời:** Đây là thiết kế bảo mật Best Practice của Oracle (Role Separation). Tài khoản `grid` quản lý cơ sở hạ tầng lõi (ổ cứng, cluster), còn tài khoản `oracle` chỉ quản lý dữ liệu nghiệp vụ của Database. Việc tách này ngăn DBA của Database vô ý xóa hỏng các đĩa quản lý của hạ tầng ASM.

**Câu 2: "Oracle Restart" là gì? Nó có phải là Oracle RAC không?**
- **Trả lời:** Oracle Restart là tên gọi của phần mềm Grid Infrastructure khi nó được cài trên **MỘT** máy chủ duy nhất (Standalone). Nó giúp tự động theo dõi và khởi động lại Database/Listener/ASM khi máy chủ bị crash. Nó không phải là RAC (Real Application Clusters - chạy trên nhiều server).

**Câu 3: Redundancy `EXTERNAL` nghĩa là gì khi tạo Disk Group?**
- **Trả lời:** Chế độ này khai báo cho ASM biết rằng: "Ổ cứng vật lý của tôi đã được bọc cơ chế RAID tự bảo vệ của hãng phần cứng rồi (ví dụ RAID-1 của SAN)". ASM không cần phải lãng phí tài nguyên để tự nhân bản dữ liệu (mirroring) thêm lần nào nữa.

**Câu 4: Chuyện gì xảy ra nếu tiến trình ASM Instance bị tắt đột ngột?**
- **Trả lời:** Toàn bộ các Database Instance (ORCL) phụ thuộc vào ASM sẽ LẬP TỨC SỤP ĐỔ (Crash/Abort) theo. Bởi vì các tiến trình của Database mất hoàn toàn đường dẫn giao tiếp vật lý xuống ổ cứng.

**Câu 5: Công cụ `asmcmd` có chức năng gì?**
- **Trả lời:** Các File System của OS (Linux) không thể đọc được phân vùng đĩa thô của ASM, bạn không thể dùng lệnh `ls`, `cd`, `mkdir` thông thường. Công cụ `asmcmd` giả lập một môi trường command-line giúp DBA thao tác điều hướng tạo và xóa file trên ASM y hệt như trên Linux.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/113-practice-creating-db-with-asm.md`
