---
title: 'Bài 120: Mở rộng - Oracle Grid Infrastructure trong môi trường RAC'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/120-bonus-oracle-grid-infrastructure-rac.md
---

# Bài 120: Mở rộng - Oracle Grid Infrastructure trong môi trường RAC

## Mục tiêu
Khóa học "Zero to Hero" chủ yếu tập trung vào hệ thống Single Instance (Oracle Restart). Ở bài bổ trợ cuối cùng này, bạn sẽ được có một cái nhìn tổng quan về môi trường **Oracle RAC (Real Application Clusters)**, nơi mà Grid Infrastructure thể hiện sức mạnh thực sự của nó.
- Cấu trúc kiến trúc của RAC.
- Các tiến trình Clusterware.
- Cấu trúc mạng VIP, SCAN.
- Các ổ đĩa dùng chung (Voting Disk & OCR).

## 1. Khái niệm Oracle RAC
RAC là kiến trúc nhiều máy chủ (Multiple Nodes) cùng chia sẻ và đọc/ghi chung vào MỘT hệ thống ổ đĩa lưu trữ duy nhất.
- Ví dụ bạn có 3 máy chủ vật lý, trên mỗi máy chạy một Database Instance (`ORCL1`, `ORCL2`, `ORCL3`).
- Nhưng cả 3 Instance này đều truy cập xuống một kho dữ liệu duy nhất nằm trên tủ đĩa chung SAN/ASM.
- Nếu Server 1 cháy, hệ thống vẫn hoạt động bình thường, các phiên làm việc tự động văng sang Server 2 và 3.

## 2. Clusterware Components
Để 3 máy chủ có thể chạy đồng bộ với nhau như một thể thống nhất mà không dẫm đạp lên dữ liệu của nhau, Oracle Grid cung cấp các tiến trình Cluster:
- **CSS (Cluster Synchronization Services):** Giám sát "nhịp tim" (heartbeat) giữa các node trong cụm để biết node nào còn sống hay đã chết.
- **CRS (Cluster Ready Services):** Quản lý khởi động và tắt tự động các tài nguyên (Database, Listener, ASM). Khi một node sập, CRS sẽ tự động chuyển dời (failover) các dịch vụ IP sang node khác.
- **CTSS (Cluster Time Synchronization Service):** Đảm bảo đồng hồ thời gian của 3 máy chủ phải chạy chính xác đến từng mili-giây với nhau.

## 3. Hệ thống mạng (Public, Private, VIP và SCAN)
Trong môi trường RAC, cấu hình IP vô cùng phức tạp:
- **Public IP:** IP thật của máy chủ để Admin truy cập qua SSH.
- **Private IP (Interconnect):** Đường dây mạng nội bộ siêu tốc kết nối 3 máy chủ để chúng trao đổi dữ liệu RAM (Cache Fusion) với nhau.
- **VIP (Virtual IP):** Một địa chỉ IP ảo chạy trượt trên Public Network. Khi Server 1 cháy mạng, cái VIP đó sẽ lập tức được tự động gắn sang Server 2, giúp ứng dụng không bị kẹt ngâm (hang) TCP Timeout mà nhận được lỗi báo kết nối bị đứt ngay lập tức để thử lại.
- **SCAN (Single Client Access Name):** Một cái tên miền (Domain) duy nhất cấp cho hàng nghìn người dùng cuối. Ứng dụng chỉ việc trỏ kết nối vào cái tên SCAN này, SCAN sẽ làm nhiệm vụ Load Balancer, rải đều các kết nối vào 3 server để cân bằng tải.

## 4. Quản lý Đĩa chung (Voting Disk và OCR)
Bởi vì tất cả các node chạy chung, phải có những thành phần quản lý bầu cử và lưu trữ cấu hình:
- **Oracle Cluster Registry (OCR):** Là cuốn sổ cái (registry) chứa toàn bộ thiết lập cấu hình của cụm (IP nào nằm ở node nào, tên database là gì, trạng thái các dịch vụ).
- **Voting Disk (Đĩa bầu cử):** Nơi các Node đóng dấu xác nhận trạng thái sống (heartbeat) của mình xuống đĩa. Nếu xảy ra sự cố đứt mạng nội bộ (Split Brain), các node sẽ nhìn vào Voting Disk để "bầu phiếu" xem nhóm Node nào đông hơn sẽ được quyền tiếp tục chạy, nhóm ít hơn sẽ bị khởi động lại bằng vũ lực (Fencing/Reboot) để bảo vệ an toàn cho dữ liệu.

---
## Câu hỏi ôn tập

**Câu 1: Chuyện gì xảy ra nếu mạng Private (Interconnect) bị đứt kết nối vật lý (chuột cắn cáp)?**
- **Trả lời:** Đây là hiện tượng "Split-brain" khét tiếng. Các node không nhìn thấy nhau qua mạng nữa, chúng đều nghĩ rằng các node kia đã chết và cố giành quyền kiểm soát tủ đĩa (có nguy cơ ghi đè hỏng dữ liệu). Lúc này cơ chế CSS và Voting Disk sẽ ra tay, cưỡng chế tắt nóng (kill/reboot) node phụ đi để bảo vệ dữ liệu, chỉ để lại 1 nhóm node sống sót.

**Câu 2: Nếu Server 2 chết, dữ liệu của khách hàng đang nằm trên RAM của Server 2 có bị mất không?**
- **Trả lời:** Các thay đổi quan trọng nếu chưa được ghi xuống đĩa (commit) thì sẽ mất. Tuy nhiên, tính năng Instant Recovery của RAC sẽ sử dụng các Instance còn sống (Server 1 và 3) đọc lại Redo Log của Server 2 trên hệ thống lưu trữ dùng chung, và tự động khôi phục (Roll forward/Rollback) để đảm bảo tính nhất quán hoàn hảo.

**Câu 3: Tôi cấu hình ứng dụng trỏ vào Public IP của Server 1. Điều này có sai không?**
- **Trả lời:** Sai thiết kế nghiêm trọng. Nếu Server 1 sập, Public IP đó bị ngắt kết nối. Trình điều khiển TCP của ứng dụng sẽ chờ đợi (timeout) từ 10 đến 15 phút. Bạn nên cấu hình trỏ vào SCAN Name hoặc danh sách các VIP. Khi VIP nhảy sang máy khác, tiến trình TCP sẽ văng lỗi ngay và kết nối lại qua máy mới trong vài giây.

**Câu 4: Ổ đĩa dùng chung (Shared Storage) thường được cài đặt bằng công nghệ gì?**
- **Trả lời:** Trong các hệ thống Enterprise, hệ thống lưu trữ dùng chung này thường là các dàn đĩa (Storage Array) khổng lồ cấp phát LUNs qua mạng quang (SAN Fibre Channel) hoặc iSCSI. Oracle ASM sẽ được dùng để bọc lên các LUNs này, ảo hóa ra cấu trúc thư mục dùng chung.

**Câu 5: Cấu trúc ASM trong môi trường RAC khác gì so với cấu trúc Standalone?**
- **Trả lời:** Khác biệt lớn nhất là trong môi trường RAC, MỖI MỘT Node đều phải chạy một tiến trình ASM Instance riêng của nó (VD: `+ASM1`, `+ASM2`, `+ASM3`). Tất cả các ASM Instance này đều phải nhìn thấy chung cấu trúc của các tủ đĩa SAN vật lý ở dưới. Nếu có thay đổi, chúng sẽ báo cho nhau qua đường Private Network.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/120-bonus-oracle-grid-infrastructure-rac.md`
