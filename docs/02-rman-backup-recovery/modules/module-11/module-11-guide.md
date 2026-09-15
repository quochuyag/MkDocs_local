---
title: '📘 Module 11: Common Backup Practices'
course: 02-rman-backup-recovery
source: Oracle-Database-Backup-and-Recovery-using-RMAN/modules/module_11/module_11_guide.md
---

# 📘 Module 11: Common Backup Practices

> **Module**: 11/17
> **Phạm vi**: Bài 33 & 34 (Chỉ có Lý thuyết, không có Lab Thực hành)
> **Giảng viên**: Ahmed Baraka
> **Thời gian học ước tính**: 1 giờ
> **Tiền điều kiện**: Đã hoàn thành Module 10
> **Nguồn PDF**: `pdf_extracted/module_11/`

---

## 📑 Mục lục

- [Bài 33-34: Thực tiễn Thiết kế Backup (Common Backup Practices)](#-bài-33-34-thực-tiễn-thiết-kế-backup-common-backup-practices)
- [Các Kịch bản Ứng dụng Thực tế Đáng chú ý](#-các-kịch-bản-ứng-dụng-thực-tế-đáng-chú-ý)
- [Câu hỏi ôn tập tổng hợp](#-câu-hỏi-ôn-tập-tổng-hợp)

---

# 📖 Bài 33-34: Thực tiễn Thiết kế Backup (Common Backup Practices)
> 📄 Nguồn: `Common Backup Practices.pdf` — 18 slides

## 🎯 Mục tiêu bài học
Module này **không có phần thực hành mã lệnh**. Trọng tâm là tư duy thiết kế kiến trúc (Architecture Design) của DBA trưởng:
- ✅ Định nghĩa RPO và RTO cho các tình huống thảm họa khác nhau.
- ✅ Áp dụng General Best Practices cho OLTP & Data Warehouse.
- ✅ Hiểu kiến trúc sao lưu truyền thống (Traditional) và Hiện đại (Cloud).
- ✅ Thiết kế kịch bản xử lý cho từng mức độ Database (Non-critical, Business Critical...).

---

## 📋 Nội dung chính

### 1. Phân loại Database và Mô hình Khả dụng

Trước khi lập lịch Backup, DBA cần xác định rõ loại hệ thống đang phục vụ:
- **Loại ứng dụng (Category):** OLTP (Giao dịch liên tục), Data Warehouse / OLAP (Lưu trữ và phân tích tĩnh), hoặc Hybrid (Lai cấy).
- **Mô hình Thời gian (Availability):** Phục vụ Hành chính `8x5` hay Phục vụ Bất chấp `24x7`.
- **Mức độ Nghiêm trọng (System Criticality):** Khi hệ thống sập sẽ tổn thất bao nhiêu $? Cấp độ ảnh hưởng tới sinh mạng và an toàn?

---

### 2. Định nghĩa Cốt lõi: RPO và RTO ⭐⭐⭐

Mọi thiết kế Backup đều xoay quanh 2 con số bắt buộc kí kết với Giám đốc/Doanh nghiệp:

- **RPO (Recovery Point Objective):** Dữ liệu bị mất TỐI ĐA là bao nhiêu khi sự cố xảy ra? (VD: Khách hàng đồng ý mất dữ liệu 2 giờ đánh máy trước khi sập, RPO = 2h).
- **RTO (Recovery Time Objective):** DB phải được KHÔI PHỤC trong bao lâu kể từ lúc bắt đầu sửa? (VD: Boss cho DBA đúng 5 tiếng để DB online lại, RTO = 5h).

> [!WARNING]
> RTO và RPO phải được **nhân chuẩn với từng kịch bản thảm họa** (Failure Type). Bạn không thể cam kết RTO 2 tiếng cho một thảm họa động đất cháy rụi toàn bộ Data Center!

**Ví dụ thiết kế:** (Lưu Backup dưới FRA (Disk), không có Standby DB - Mô hình rẻ tiền)
| Tình huống Thảm họa (Failure Type) | RTO (Cần bao lâu?) | RPO (Mất dữ liệu bao xa) |
|------------------------------------|--------------------|--------------------------|
| Hỏng ổ cứng cục bộ (Media Failure) | 5 hours            | 24 hours (Bkp mỗi ngày)  |
| Hỏng cả máy chủ (Server Failure)   | 1 week (Mua server mới) | 24 hours |
| Cháy Data Center (Disaster)        | 2 weeks (Xây móng mới)| 1 week (Vì Offsite 1 tuần/lần) |

---

### 3. Best Practices Chung (General Best Practices) ⭐⭐

- **Nơi cất giữ:** FRA (Fast Recovery Area) bắt buộc phải nằm ở Storage hoàn toàn khác biệt vật lý với Datafile.
- **Chiến lược Incremental:** Tích cực dùng *Cumulative/Differential* Incremental, hoăc *Incrementally Updated Backups (Image forever)*.
- **Tăng tốc:** Bật **Block Change Tracking (BCT)** để Incremental quét SIÊU NHANH.
- **Bảo mật và Tiết kiệm:** Bật mã hóa (Encryption) và nén (Compression) nếu có.

### 4. Đối với Hệ thống Data Warehouse (DB siêu to, ít sửa)
- Chuyển partition cũ sang tablespace `READ-ONLY`.
- Chỉ backup tablespace `READ-ONLY` 1 lần duy nhất thay vì suốt ngày backup.
- Sử dụng nén bảng (Table Compression) và bật Incremental + lệnh `NOLOGGING`.
- Nếu DB qua bự cho 1 đêm: Dùng câu lệnh giới hạn thời gian (Partial Window):
  `BACKUP DATABASE ... DURATION 07:00 PARTIAL MINIMIZE TIME;` (Chạy được bao nhiêu hay tới đó, đêm mai chạy nốt khối tiếp theo).

---

### 5. Kiến trúc Topology: Traditional vs Cloud ⭐⭐⭐

#### A. Kiến trúc Truyền thống (Traditional: D2D2T)

- **D2D (Disk-to-Disk):** RMAN Backup xuất ra FRA ở local SAN. Lưu ngắn ngày (`7-30 days`). Lợi ích: **Quick RTO** vì copy từ đĩa ra đĩa chớp mắt. (Dùng `Image copy` hoặc `Backupset`).
- **D2T (Disk-to-Tape) / D2D2T (Disk-Disk-Tape):** Bắn dữ liệu từ SAN vào bồn chứa Băng Từ (Tape Library) thông qua OSB/MML.
  - Mang Tape ra đi gửi (Off-site).
  - Thuộc tính kho dài hạn Archiving (Đòi hỏi luật định cất 5 năm).

#### B. Kiến trúc Đám mây (Modern Cloud Layout)

- Vẫn giữ local FRA cho **Short term** (`30 days`).
- Không xài Tape cũ kĩ nữa, dùng **Oracle Database Backup Cloud Service Module** ném thẳng qua HTTP vào Cloud Storage (AWS S3/Oracle OCI).
- Dùng cho Off-site xa vời vợi, Medium và Long term retention.

---

### 6. Testing Backups — Vấn đề Sống còn
"Một bản backup chưa được test thử là một bản backup vô dụng."
- Phải tự lên lịch test định kỳ và Ghi nhận (Document).
- Bắt buộc **Môi trường Test** phải tương đồng cấu hình/phiên bản với **Môi trường Prod**.

---

# 💡 Các Kịch bản Ứng dụng Thực tế Đáng chú ý

Là DBA, khi nghe yêu cầu từ Business, phải biết phản xạ ra thiết kế:

#### Kịch bản 1: CSDL Dev/Test (Non-Critical)
- **Đề bài:** RPO = 24h, RTO = 1 ngày. Giữ 3 bản. Có Internet.
- **Thiết kế:** Đẩy Backup thẳng lên Cloud (khỏi tốn Local Disk). Full chủ nhật rảnh, Incremental hàng ngày. Backup Archive log thỉnh thoảng để không mất data.

#### Kịch bản 2: Của hồi môn - Business Critical (RTO 2h rảnh rang)
- **Đề bài:** RTO=2h. Cần giữ 6 tháng dưới ổ cứng cục bộ, 5 năm ở Cloud.
- **Thiết kế:** Dùng `Backupset`. Lưu xuống Local (khôi phục trong 2h siêu ok). Cực năng backup Archive log (mỗi 2h) để đảm bảo RPO 2h. Đẩy Archival vĩnh viễn lên mây mỗi tháng.

#### Kịch bản 3: Sếp đuổi việc - Business Critical nhưng RTO = Ưng siêu nhanh (15 phút!)
- **Đề bài:** Đứt dữ liệu sếp muốn dựng lại trong 15 phút.
- **Thiết kế:** Dẹp Backupset. Dùng **Image Copies** lưu dưới DB Disk cục bộ và chạy chế độ **Incrementally Updated Image Copies** (Rolling Forward). Lúc có chuyện chỉ cần lệnh `SWITCH DATABASE TO COPY` mất chưa tới 2 phút! Phần Cloud dẫu để RTO là 2 ngày (chỉ để đề phòng tịt mạng).

#### Kịch bản 4: Trạm máy hẻo lánh - Không Internet (No Cloud Network)
- **Thiết kế:** Backup rớt xuống Local Disk bình thường. Setup một con máy chủ nằm ở vũng DMZ (Vừa nhìn được server vừa nhìn được cloud) -> Mount ổ đĩa qua mạng (NFS) sang cho nó để nó chịu trách nhiệm đem file backup đẩy lên mây vớt. Nhớ phải mã hóa vì ném qua NFS và Server public khá nguy hiểm.

---

# 🎯 Câu hỏi ôn tập tổng hợp

**1. RPO và RTO khác nhau ở điểm cốt lõi nào?**
<details>
<summary>💡 Đáp án</summary>
- **RPO (Recovery Point):** Dữ liệu bị thâm hụt tính bằng Giờ/Phút MẤT ĐI (tính VỀ QUÁ KHỨ tính từ lúc xảy ra sự cố). Ví dụ: Lỡ mất hoá đơn 1 giờ trước.
- **RTO (Recovery Time):** Thời gian cần thiết sửa máy TƯƠNG LAI tính từ lúc bị sập. Ví dụ: Kỹ sư phải ngáp ngủ sửa trong vòng 4 tiếng.
</details>

**2. Tại sao người ta gọi là kiến trúc D2D2T? Lợi ích là gì?**
<details>
<summary>💡 Đáp án</summary>
Disk-to-Disk-to-Tape. Dùng Disk để giữ bản backup ngắn hạn, khôi phục tốc độ ánh sáng cứu vãn tình thế khẩn cấp. Dùng Tape để bốc dữ liệu ra Offsite và cất trữ lâu vĩnh viễn không sợ hỏng từ trường, cực bền, mà giá lại rẻ hơn đĩa dung lượng khủng.
</details>

**3. Khách hàng yêu cầu RTO thời gian phục hồi bằng mọi giá không quá 10 phút nếu hỏng Datafile trên ổ SSD. Bạn dùng RMAN Backupset hay RMAN Image Copy? Tại sao?**
<details>
<summary>💡 Đáp án</summary>
Bắt buộc thiết kế **Image Copies**. 
Nếu dùng Backupset, mất đến 30 phút để giải nén (Restore) data trở lại vì file bị nén theo Box. Nếu dùng Image Copy, nó đã là tệp thuần `.dbf`. Bạn chỉ cần lệnh `SWITCH` trỏ Control File thẳng vào bản Image Copy thì hệ thống quay lại online ngay tắp lự.
</details>

---

## ➡️ Bài tiếp theo

**Module 12: Đỉnh cao Khôi phục (Performing Recovery)**
Trong chặng tới, bạn sẽ chia thành nửa tá Lab thực hành mô phỏng các thảm họa:
- Vỡ toàn bộ Database (Full Recovery).
- Switch Data Files và Point-In-Time (PITR) lùi thời gian như cỗ máy thời gian.
- Khôi phục SPFILE và Control File khi cháy đen cục cấu hình.
- Phục hồi khi sập Redo Log.

> Đây là nội dung rất hay về tư duy. Anh đã sẵn sàng nhảy vào **Module 12: Performing Recovery**, phần thực hành cực kỳ mỏi tay của khóa học RMAN chưa ạ? 🚀


---

!!! info "Nguồn gốc"
    `Oracle-Database-Backup-and-Recovery-using-RMAN/modules/module_11/module_11_guide.md`
