---
title: 'Bài 118: Mở rộng - Kiến trúc chuyên sâu của Oracle ASM'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/118-bonus-kien-truc-chuyen-sau-asm.md
---

# Bài 118: Mở rộng - Kiến trúc chuyên sâu của Oracle ASM

## Mục tiêu
Bài học bổ trợ này sẽ giúp bạn hiểu sâu hơn về cách thức hoạt động nội bộ của Automatic Storage Management (ASM), vượt ra ngoài các khái niệm cơ bản. Bạn sẽ học về:
- Cấu trúc cấp thấp: AU, Extents và ASM Files.
- Cơ chế chống lỗi với Failure Groups.
- Các cấp độ nhân bản dữ liệu (Redundancy).
- Tiến trình Rebalancing (Tái cân bằng).

## 1. Cấu trúc lưu trữ cấp thấp của ASM
ASM không lưu dữ liệu một cách lộn xộn. Nó phân rã không gian ổ đĩa thành các thành phần logic như sau:
- **Allocation Unit (AU):** Là đơn vị cấp phát không gian cơ bản nhất của ASM (tương tự như Data Block của Database). Theo mặc định từ bản 11g, mỗi AU có kích thước 1MB, từ bản 12c trở lên có thể tự động tăng lên 4MB hoặc lớn hơn để phù hợp với ổ đĩa dung lượng khủng (Multi-Terabyte).
- **Extents:** Một Extent trong ASM là một tập hợp các AU. Database cấp phát không gian theo từng Extent. Khi file database phình to (ví dụ Datafile đạt 20GB), ASM sẽ tự động dùng các Extent có kích thước siêu lớn (Variable Extent Size - ví dụ 64MB) để giảm số lượng con trỏ quản lý, giúp tiết kiệm bộ nhớ RAM.
- **ASM Files:** Các tệp tin thực tế của Database (như Datafile, Redo Log) được băm nhỏ thành các Extent và rải đều trên khắp các ổ cứng thuộc Disk Group.

## 2. Các cấp độ Redundancy (Nhân bản dữ liệu)
Khi tạo một Disk Group, bạn phải chọn mức độ an toàn dữ liệu. ASM tự động nhân bản (Mirroring) bằng phần mềm:
- **EXTERNAL Redundancy:** Không nhân bản. ASM tin tưởng hoàn toàn vào sự bảo vệ của phần cứng bên dưới (như SAN RAID-1 hoặc RAID-5). (Yêu cầu ít nhất 1 đĩa).
- **NORMAL Redundancy:** Nhân bản 2 chiều (2-way mirroring). Dữ liệu được ghi thành 2 bản gốc và bản sao lưu trên 2 đĩa khác nhau. (Yêu cầu ít nhất 2 đĩa, hệ thống chịu được lỗi chết 1 đĩa).
- **HIGH Redundancy:** Nhân bản 3 chiều (3-way mirroring). Cực kỳ an toàn, chuyên dùng cho các hệ thống viễn thông, ngân hàng. (Yêu cầu ít nhất 3 đĩa, hệ thống chịu được lỗi chết cùng lúc 2 đĩa).

## 3. Failure Groups (Nhóm chống lỗi)
Nếu bạn có 10 ổ cứng nhưng tất cả cắm chung trên 1 bộ điều khiển (Controller), khi bộ điều khiển cháy, toàn bộ 10 ổ đều mất, dù bạn dùng Normal hay High Redundancy.
Để giải quyết bài toán này, ASM sinh ra khái niệm **Failure Group**. Bạn nhóm các đĩa vật lý có cùng chung một điểm yếu rủi ro lại với nhau.
Khi cấu hình Normal Redundancy, ASM sẽ thông minh đảm bảo rằng bản gốc và bản sao chép (Mirror copy) KHÔNG BAO GIỜ được ghi chung vào cùng một Failure Group, bảo vệ dữ liệu khỏi thảm họa cấp độ hạ tầng (như đứt cáp tủ đĩa, mất điện một góc trạm server).

## 4. Quá trình Rebalancing (Tái cân bằng đĩa)
Khi bạn thêm 1 ổ đĩa mới (hoặc rút 1 ổ cũ sắp hỏng ra), ASM tự động chạy tiến trình tái cân bằng ở chế độ nền. 
- Quá trình này di chuyển các AU qua lại giữa các đĩa cho đến khi tỷ lệ sử dụng dung lượng của TẤT CẢ các đĩa bằng nhau.
- Sức mạnh của quá trình này được điều khiển bởi tham số **`ASM_POWER_LIMIT`** (chạy từ 0 đến 1024). 
- `POWER = 0` nghĩa là tạm dừng rebalance. `POWER` càng cao thì việc chuyển dữ liệu càng nhanh, nhưng sẽ "ăn" nhiều I/O đĩa, làm chậm database của người dùng.

---
## Câu hỏi ôn tập

**Câu 1: Tôi có thể thay đổi kích thước của Allocation Unit (AU) sau khi Disk Group đã tạo xong không?**
- **Trả lời:** Không. Kích thước của AU (ví dụ 4MB hay 8MB) phải được chỉ định thông qua mệnh đề `ATTRIBUTE 'au_size'` ngay trong câu lệnh `CREATE DISKGROUP`. Một khi đã tạo, nó không thể thay đổi trừ phi bạn xóa nhóm đĩa tạo lại.

**Câu 2: Tại sao Oracle lại phát triển tính năng "Variable Extent Size" trong ASM?**
- **Trả lời:** Với các Datafile khổng lồ (VD: 32TB), nếu ASM cứ chia nhỏ từng 1MB (AU) thì Shared Pool (RAM) của ASM Instance sẽ bị cạn kiệt do phải chứa một bản đồ vị trí (extent map) có hàng chục triệu dòng. Việc gộp lại thành các Extent kích thước lớn 64MB giúp bản đồ này nhỏ lại, tiết kiệm RAM đáng kể.

**Câu 3: Chế độ `EXTERNAL Redundancy` có nghĩa là không an toàn?**
- **Trả lời:** Không hẳn. Nó chỉ có nghĩa là ASM không tự làm nhiệm vụ Mirror. Trong thực tế, các doanh nghiệp thường sở hữu tủ đĩa SAN (Storage Area Network) đắt tiền đã có sẵn chế độ RAID phần cứng siêu an toàn. Việc đặt External Redundancy giúp tránh tình trạng "mirror chồng mirror" gây lãng phí dung lượng.

**Câu 4: Có bắt buộc phải cấu hình Failure Groups không?**
- **Trả lời:** Theo mặc định, nếu bạn không chỉ định rõ ràng, ASM coi MỖI MỘT ổ đĩa vật lý là một Failure Group riêng biệt. Tuy nhiên, nếu bạn triển khai hệ thống lớn trên nhiều tủ đĩa, bạn NÊN tự quy hoạch Failure Group bằng tay để tối đa hóa tính chống lỗi phần cứng.

**Câu 5: Database của tôi đang chịu tải rất nặng, tự dưng 1 ổ đĩa trong ASM bị hỏng khiến tiến trình Rebalance tự động kích hoạt làm hệ thống giật lag. Tôi nên làm gì?**
- **Trả lời:** Bạn có thể tạm thời hạ mức độ chiếm dụng I/O của nó bằng lệnh: `ALTER DISKGROUP data REBALANCE POWER 1;` để nó chạy từ từ nhẹ nhàng. Đêm đến khi hệ thống ít truy cập, bạn có thể tăng lại `POWER 1024` để quá trình rebalance diễn ra cực nhanh trước bình minh.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/118-bonus-kien-truc-chuyen-sau-asm.md`
