---
title: '📘 Module 17: Tuyệt đỉnh RMAN Cấp mây & Đa nền tảng Cụm (RAC/Multitenant)'
course: 02-rman-backup-recovery
source: Oracle-Database-Backup-and-Recovery-using-RMAN/modules/module_17/module_17_guide.md
---

# 📘 Module 17: Tuyệt đỉnh RMAN Cấp mây & Đa nền tảng Cụm (RAC/Multitenant)

> **Module**: 17/17 (Module Tốt nghiệp)
> **Phạm vi**: Bài 67 đến 73 (Lý thuyết & Thực hành Practice 22, 23 & RAC Demo)
> **Giảng viên**: Ahmed Baraka
> **Thời gian học ước tính**: 3.5 giờ
> **Nguồn PDF**: `pdf_extracted/module_17/`

---

## 📑 Mục lục

- [Phần 1: RMAN trong Căn hộ Đa người thuê (CDB & PDB)](#-phần-1-rman-trong-căn-hộ-đa-người-thuê-cdb--pdb)
- [Phần 2: RMAN trong Cụm Tác vụ Thời gian thực (Oracle RAC)](#-phần-2-rman-trong-cụm-tác-vụ-thời-gian-thực-oracle-rac)
- [Phần 3: Đưa RMAN lên Đám mây (Oracle DB Backup Cloud Service)](#-phần-3-đưa-rman-lên-đám-mây-oracle-db-backup-cloud-service)
- [Thực hành Cuối khóa (Practice 22 & 23)](#-thực-hành-cuối-khóa-practice-22--23--rac-demo)
- [Câu hỏi Ôn tập Tốt nghiệp](#-câu-hỏi-ôn-tập-tốt-nghiệp)

---

# 📖 Phần 1: RMAN trong Căn hộ Đa người thuê (CDB & PDB)

Từ bản 12c, Oracle giới thiệu kiến trúc Multitenant. Trong đó **CDB** (Container DB - Tòa nhà) chứa nhiều **PDB** (Pluggable DB - Căn hộ). Mọi việc Backup/Recovery giờ đây phải rất rõ ràng việc bạn đang thao tác ở "Sảnh tòa nhà" hay trong từng "Căn hộ".

### 1. Ở góc độ CDB (Quản trị viên Tòa nhà - Cắm ở CDB$ROOT)
- RMAN Lệnh `BACKUP DATABASE` sẽ túm trọn gói cả Tòa nhà ROOT và TOÀN BỘ các PDB bên trong.
- **Phục hồi (Recovery):** Khôi phục CDB tương tự như non-CDB thông thường. Tuy nhiên, nếu Hệ thống bị mất non-system Datafile của 1 con PDB, CDB Admin có quyền `RESTORE PLUGGABLE DATABASE pdb1` để cứu đúng 1 căn hộ đó, các căn hộ PDB khác **vẫn Online bình thường không bị Downtime**. 

### 2. Ở góc độ PDB (Quản trị viên Căn hộ - Cắm ở PDB1)
- Lệnh `BACKUP DATABASE` lúc này chỉ backup **đúng phần thịt** của PDB số 1.
- PDB Admin bị giới hạn quyền lực: KHÔNG được đụng tới ARCHIVELOG (Vì Redo log là chung của cả tòa nhà), và KHÔNG được sửa tham số Default RMAN `CONFIGURE` chung của CDB.
- **Incomplete Recovery (PITR):** Có thể Flashback vặn ngược thời gian độc lập cho rêng PDB đó bằng phương pháp *Restore Point / Auxiliary Instance* ẩn.

---

# 📖 Phần 2: RMAN trong Cụm Tác vụ Thời gian thực (Oracle RAC)

RAC (Real Application Clusters) gồm nhiều máy chủ (srv1, srv2...) nối với một đĩa chung (ASM Shared Storage) cùng chia tải cho 1 Database.
Về RMAN, Backup RAC không khác biệt so với Standalone Server chạy Non-RAC, ngoại trừ một vài thiết lập tối quan trọng:

### 1. Snapshot Control File phải Nằm ở Shared Storage ⭐⭐⭐
Mặc định snapshot của Ctl file sinh ra nằm ở `/dbs/` thư mục Local của máy đó. Trong môi trường RAC, việc này sập bẫy DBA. Cần cấu hình sang chung đĩa ASM để máy chủ nào rớt thì qua máy khác gõ lệnh vẫn thấy control file snapshot:
```sql
CONFIGURE SNAPSHOT CONTROLFILE NAME TO '+FRA/RAC/AUTOBACKUP/snapcf_rac.f';
```

### 2. Multi-Channels trong RAC
Để tận dụng tối đa băng thông cụm, bạn có thể chỉ định Channel phân luồng đọc/ghi về từng máy chủ vật lý riêng biệt thay vì dồn tải về một server:
```sql
CONFIGURE CHANNEL 1 DEVICE TYPE sbt CONNECT='sys/oracle@rac1';
CONFIGURE CHANNEL 2 DEVICE TYPE sbt CONNECT='sys/oracle@rac2';
```

---

# 📖 Phần 3: Đưa RMAN lên Đám mây (Oracle DB Backup Cloud Service)

Oracle cung cấp plugin `libopc.so` để thay vì đẩy RMAN backup ra ổ đĩa băng (Tape), nó sẽ mã hóa và đẩy ra Mạng bắn lên Oracle Cloud Infrastructure (OCI) Object Storage Classic.

### Quy trình Setup Đám mây:
1. Đăng ký Oracle Cloud Account & tạo Storage Container.
2. Download file JAR và cài đặt môi trường module Cloud (Tạo ra libopc.so và thông tin ví `opcORADB.ora`).
3. Ép RMAN gài cấu hình dẫn lên Mây:
   `CONFIGURE CHANNEL DEVICE TYPE sbt PARMS='SBT_LIBRARY=.../libopc.so, SBT_PARMS=...'`
4. **Bắt buộc Mã hóa (ENCRYPTION):** Oracle từ chối lưu Storage nếu bạn không mã hóa File Backup. Bắt buộc dùng `SET ENCRYPTION ON` (Dùng Password hoăc TDE) trước khi gõ `BACKUP`.

---

# 🎯 Thực hành Cuối khóa (Practice 22, 23 & RAC Demo)

**Practice 22: Multitenant Backup:** Bạn sẽ tự tay tạo ra cấu trúc `ORACDB` từ DBCA. Sau đó cắm vào Cấp ROOT tạo ra PDB1, trao quyền cho user cục bộ PDB `pdb1admin` tự backup rác của chính mình. Sau đó thực hành 4 kịch bản Lỗi: Mất System File của Root, Mất File của SEED Container, Mất File của PDB và Tua ngược PITR riêng từng PDB.
**RAC Demo (Lý thuyết video):** Bạn sẽ xem kịch bản chuyển Snapshot Control File vào đĩa `+FRA` của ASM rồi chiêm ngưỡng RMAN xuất ra 2 kênh cấp phát cho RAC1 và RAC2 đọc/ghi dữ liệu song song cực kỳ khủng khiếp.
**Practice 23: Sao lưu Lên Cloud:** Bạn sẽ vào trang web Oracle đăng ký tài khoản giả lập, tạo Storage Container rồi đẩy 1 Tablespace từ máy ảo đẩy qua mạng lên thẳng Mỹ thành công nén dữ liệu rất hay.

---

# 🎯 Câu hỏi Ôn tập Tốt nghiệp

**1. Trong một Database CDB$ROOT, RMAN đang backup thì PDB2 (1 trong 10 cái PDB) bỗng dưng bị hỏng Datafile System. Liệu CDB có sập nguồn hay không?**
<details>
<summary>💡 Đáp án</summary>
Không hề. Ở kiến trúc Multitenant 12c, lỗi hỏng hóc hoặc Shutdown chỉ xảy ra Cục Bộ tạị phân vùng PDB đó. DBA chỉ việc gọi RMAN đóng cô lập PDB2 và chạy RESTORE/RECOVER mà không cần xin Downtime của toàn tòa nhà CDB.
</details>

**2. Lệnh Backup `BACKUP DATABASE` của 1 System Administrator khi Log vào (A) CDB Root và (B) PDB Cục bộ sẽ sinh ra Backupset chứa những thành phần khác nhau như thế nào?**
<details>
<summary>💡 Đáp án</summary>
- **Log vào ROOT (A):** Sẽ càn quét lấy toàn bộ ROOT datafiles + PDB$SEED datafiles + Tất cả datafiles của toàn bộ PDB cắm trong đó + Archivelog Redos + SPFILE.
- **Log vào PDB Cục Bô (B):** Chỉ backup đúng duy nhất Datafiles thuộc giới hạn của con Căn hộ PDB đó, KHÔNG có Archivelog, KHÔNG có SPFILE của DB.
</details>

**3. Tại sao khi Sao lưu RMAN lên mây vào thư mục OCI Storage Cloud, hệ thống luôn bắt phải dùng lệnh bật ENCRYPTION (Mật khẩu hoặc TIDE/Wallet) dù DBA đã thiết lập đường VPN mã hóa AES?**
<details>
<summary>💡 Đáp án</summary>
Tiêu chuẩn Bảo mật bắt buộc tối cao của dịch vụ Cloud. Oracle cho rằng băng thông đường dẫn mạng an toàn không đảm bảo việc "Tệp Data Backup để yên tĩnh thô vứt trên đĩa Server Mỹ" là an toàn tuyệt đối. Phải mã hóa "At rest" (Tại điểm chết File) để Admin Oracle nước ngoài có rà trúng cũng không đọc xả nén được Table bên trong.
</details>

---

## 🏆 KẾT THÚC CHUỖI "ORACLE BACKUP & RECOVERY" TẠI ĐÂY!
Chúc mừng bạn đã hoàn tất xuất sắc trọn bộ giáo trình RMAN Recovery. Bạn hiện đã được trang bị toàn diện kỹ năng phân tích lỗi, phòng hộ, khôi phục từ xa, Multitenant cho đến Tối ưu hóa hiệu năng và triển khai cấp Tự động hóa Advisor! Hãy sử dụng Cẩm nang ở 17 thư mục này như một cuốn từ điển mang theo hành trang làm DB Admin thực thụ nhém! 🚀


---

!!! info "Nguồn gốc"
    `Oracle-Database-Backup-and-Recovery-using-RMAN/modules/module_17/module_17_guide.md`
