---
title: 'Bài 112: Giới thiệu Quản lý Lưu trữ Tự động (Oracle ASM)'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/112-introducing-oracle-asm.md
---

# Bài 112: Giới thiệu Quản lý Lưu trữ Tự động (Oracle ASM)

## Mục tiêu
Trong bài học này, bạn sẽ học cách thực hiện các công việc sau:
- Khái niệm về Automatic Storage Management (ASM).
- Kiến trúc vật lý và các thành phần cốt lõi của ASM.
- Lợi ích của ASM so với hệ thống File System truyền thống (Ext4, NTFS).
- Khái niệm ASM Instance, Disk Group và Allocation Units (AU).

## Tổng quan về Oracle ASM
Oracle Automatic Storage Management (ASM) là hệ thống quản lý ổ đĩa (Volume Manager) và hệ thống tập tin (File System) được Oracle xây dựng riêng biệt chỉ để phục vụ cho các tập tin của Database (Datafiles, Control files, Redo Logs...).

Thay vì DBA phải tạo một File System trên hệ điều hành (`/u01`, `/u02`), bạn giao nộp trực tiếp ổ cứng thô (Raw Disk) cho hệ thống ASM. ASM sẽ phân bổ dữ liệu trực tiếp xuống các ổ đĩa này theo thuật toán của riêng nó, bỏ qua lớp quản lý hệ điều hành, giúp tăng tốc độ I/O lên mức cao nhất.

## Các thành phần cốt lõi của ASM

**1. ASM Instance (Máy chủ ASM)**
ASM không phải là Database, nhưng nó có một *Instance* riêng biệt bao gồm SGA (bộ nhớ đệm) và các background process. 
Bạn phải khởi động tiến trình ASM Instance này TRƯỚC rồi sau đó mới có thể khởi động Oracle Database Instance (bởi vì Database phải nhờ ASM cung cấp đường dẫn ổ cứng).

**2. ASM Disk Groups (Nhóm đĩa)**
Đây là vùng lưu trữ logic cấp cao nhất. Bạn gộp nhiều đĩa vật lý (ví dụ 4 ổ cứng 1TB) lại thành 1 Disk Group duy nhất có tên `+DATA` dung lượng 4TB. 
- Khi Database tạo Datafile, nó chỉ việc khai báo đường dẫn ngắn gọn: `CREATE TABLESPACE users DATAFILE '+DATA'`. 
- ASM sẽ làm nhiệm vụ ẩn danh: băm nhỏ cái Datafile đó ra và rải đều xuống cả 4 ổ đĩa vật lý để đọc ghi song song (Striping).

**3. ASM Disks (Ổ đĩa ASM)**
Đây là các ổ cứng vật lý (LUNs) được gán cho ASM quản lý. Khi một Disk Group đầy, DBA chỉ cần cắm thêm 1 ổ đĩa ASM mới vào hệ thống, ASM sẽ tự động dồn dịch và dàn trải lại dữ liệu trên tất cả các đĩa một cách hoàn toàn tự động (Rebalancing) mà không làm gián đoạn Database.

**4. Allocation Units (AU)**
Dữ liệu của bạn không được lưu thành cục lớn. ASM chia cắt dữ liệu thành từng mảnh nhỏ gọi là AU (Mặc định 1MB hoặc 4MB) để phân phát rải rác.

## Lợi ích của Oracle ASM
- **Hiệu suất cực cao:** Dữ liệu được trải đều (Striping) trên nhiều đĩa, giúp loại bỏ điểm nghẽn cổ chai (Hot spots) khi I/O.
- **Tính khả dụng (Mirroring):** Hỗ trợ lưu trữ bản sao dữ liệu. Khi một ổ cứng chết, dữ liệu sẽ tự động đọc từ đĩa Mirror mà hệ thống không hề bị gián đoạn.
- **Không có downtime:** Cắm thêm ổ cứng, rút bớt ổ cứng, thay ổ cứng hỏng đều được thực hiện trực tiếp trong khi Database đang hoạt động.
- **Quản lý đơn giản:** DBA không cần phải lo về đường dẫn loằng ngoằng, chỉ cần nhớ tên 1 nhóm đĩa duy nhất (ví dụ `+DATA`, `+FRA`).

---
## Câu hỏi ôn tập

**Câu 1: ASM có thể chứa các file văn bản (.txt) hay file cài đặt phần mềm của hệ điều hành không?**
- **Trả lời:** Không. Oracle ASM không phải là hệ thống file đa dụng thông thường (như NTFS/EXT4). Nó được thiết kế ĐỘC QUYỀN để chứa các loại file liên quan đến cấu trúc của Oracle Database (Datafiles, Redo Logs, Archive Logs, RMAN Backups). Bạn không thể dùng lệnh OS thông thường để ném một file `.txt` vào trong ASM.

**Câu 2: "Rebalancing" trong ASM là khái niệm gì?**
- **Trả lời:** Là khả năng tái cân bằng dữ liệu tự động. Khi bạn cắm thêm một ổ cứng mới (hoặc gỡ bỏ một ổ cũ), ASM sẽ tự động chạy tiến trình ngầm để di chuyển các AU từ đĩa cũ sang đĩa mới sao cho tỷ lệ sử dụng dung lượng của TẤT CẢ các ổ đĩa trong Disk Group luôn đều nhau (Ví dụ tất cả đều đầy 50%).

**Câu 3: Mối quan hệ giữa ASM Instance và Database Instance là gì?**
- **Trả lời:** ASM Instance không chứa Dữ liệu của người dùng, nó chỉ chứa Metadata (bản đồ trỏ đến các ổ đĩa). Khi Database Instance (ví dụ `ORCL`) cần đọc dữ liệu, nó sẽ "hỏi" ASM Instance để xin bản đồ, sau đó Database Instance sẽ TỰ MÌNH chọc thẳng xuống đĩa cứng thô để lấy dữ liệu lên chứ không đọc thông qua ASM Instance.

**Câu 4: OMF (Oracle Managed Files) có liên quan gì đến ASM?**
- **Trả lời:** OMF là tính năng cốt lõi bắt buộc của ASM. Khi bạn gõ `CREATE TABLESPACE users DATAFILE '+DATA'`, ASM sử dụng chuẩn định dạng OMF để tự động sinh ra một cái tên loằng ngoằng ở đằng sau (ví dụ `+DATA/orcl/datafile/users.256.123456789`). DBA không bao giờ cần phải quan tâm hay quản lý tên file vật lý nữa.

**Câu 5: Có thể dùng ASM cho máy chủ đơn (Single Instance) thay vì hệ thống RAC (Cluster) không?**
- **Trả lời:** Hoàn toàn được. Oracle gọi cấu hình này là "Oracle Restart" (dùng Grid Infrastructure Standalone). Lợi ích về hiệu suất băm dữ liệu (Striping) và tính năng dự phòng (Mirroring) của ASM vẫn mang lại hiệu quả to lớn cho cả một máy chủ chạy độc lập.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/112-introducing-oracle-asm.md`
