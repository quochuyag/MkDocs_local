---
title: '📘 Module 16: Tối ưu Hiệu năng & Xử lý Sự cố RMAN (Performance Tuning & Troubleshooting)'
course: 02-rman-backup-recovery
source: Oracle-Database-Backup-and-Recovery-using-RMAN/modules/module_16/module_16_guide.md
---

# 📘 Module 16: Tối ưu Hiệu năng & Xử lý Sự cố RMAN (Performance Tuning & Troubleshooting)

> **Module**: 16/17
> **Phạm vi**: Bài 64 đến 66 (Lý thuyết Tuning và Troubleshooting)
> **Giảng viên**: Ahmed Baraka
> **Thời gian học ước tính**: 2 giờ
> **Nguồn PDF**: `pdf_extracted/module_16/`

---

## 📑 Mục lục

- [Phần 1: RMAN Performance Tuning (Tối ưu Hiệu năng)](#-phần-1-rman-performance-tuning-tối-u-hiệu-năng)
- [Phần 2: Quản lý RMAN Multiplexing (Đa luồng truyền tải)](#-phần-2-quản-lý-rman-multiplexing-đa-luồng-truyền-tải)
- [Phần 3: RMAN Troubleshooting (Xử lý sự cố lỗi)](#-phần-3-rman-troubleshooting-xử-lý-sự-cố-lỗi)
- [Câu hỏi ôn tập Module 16](#-câu-hỏi-ôn-tập-module-16)

---

# 📖 Phần 1: RMAN Performance Tuning (Tối ưu Hiệu năng)

Tốc độ chạy các lệnh RMAN phụ thuộc rất nhiều vào các yếu tố ngoại vi như: Thắt cổ chai tại Network (Network bandwidth), nghẽn cổ chai tại Ổ cứng (Disk I/O), và băng thông của thiết bị từ tính (Tape Drive). Database là thành phần ít gây nghẽn nhất.

### 1. Kích hoạt Asynchronous I/O (Vào/Ra Bất đồng bộ) ⭐⭐⭐
Trong hệ thống đồng bộ (Synchronous), mỗi khi RMAN gửi 1 Block dữ liệu ra ổ băng/ổ đĩa, nó phải **đứng chờ** (Wait) cho phần cứng báo cất xong rồi mới nạp Block tiếp theo. Khi bật Bất đồng bộ (Asynchronous), RMAN sẽ liên tục đẩy Block đi mà không cần đợi, giúp tăng vọt tốc độ!
- **Đới với Băng từ (Tape):** Cài đặt biến `BACKUP_TAPE_IO_SLAVES = TRUE`. Khi đó, bộ đệm IO sẽ được chuyển về tính toán trên phân vùng **SGA** (hoặc Large Pool).
- **Đối với Ổ đĩa (Disk):** Đa số HĐH hiện tại đã hỗ trợ giả lập Asynchronous I/O. Nếu không, gài `DBWR_IO_SLAVES` khác không.

### 2. Kỹ thuật chia chu kỳ (Multi-cycle Full Backup)
Nếu Server quá lớn (vd 50TB), 1 đêm chạy không kịp xong trước 7h sáng giờ kinh doanh, DBA có thể ra điểu kiện DURATION:
```sql
-- Cố gắng chạy 7 tiếng thôi, chạy đến đâu hay đến đấy (PARTIAL), 
-- Đêm mai chạy tiếp những File chưa được Backup trong 3 ngày qua.
BACKUP DATABASE NOT BACKED UP SINCE 'SYSDATE-3' 
DURATION 07:00 PARTIAL MINIMIZE TIME;
```

---

# 📖 Phần 2: Quản lý RMAN Multiplexing (Đa luồng truyền tải)

Tính năng Multiplexing hiểu nôm na là nhồi nhét nhiều luồng Datafiles vào chung một tệp Backup. Các kỹ thuật chia nhỏ/gộp chung này quyết định độ cơ động của RMAN trên mạng.

### 1. Chiêu thức MAXPIECESIZE (Chặt nhỏ File xuất ra)
- **Hành vi:** Datafile quá lớn (100GB). Gây khó di chuyển hoặc vượt quá giới hạn HĐH (FAT32 chỉ chịu tối đa 4GB file).
- **Thực thi:** Ép RMAN cứ nhả ra file dung lượng 2GB thì ngắt thành cục số 2.
```sql
ALLOCATE CHANNEL c1 DEVICE TYPE DISK 
MAXPIECESIZE 2048M 
FORMAT '/temp/%U.BAK';
```

### 2. Chiêu thức FILESPERSET (Luật nhồi nhét Datafile)
- **Hành vi:** Mặc định RMAN nhét tối đa **64** file Datafile vào chung 1 cục Backupset.
- **Thực thi:** Nếu bạn muốn RMAN nhét ít lại (Ví dụ để Restores riêng lẻ nhanh hơn), hãy hạ con số này xuống. (VD: `FILESPERSET = 3`).

### 3. Chiêu thức MAXOPENFILES (Giới hạn vòi rót)
- **Hành vi:** Định nghĩa số lượng Datafile TỐI ĐA sẽ được RMAN mở và đọc đút vào chung một tệp cùng lúc (Mặc định là 8 file). 

> **Công thức VÀNG:** Kích thước Multiplexing cuối cùng chạy trên thực tế được hệ thống lấy con số **NHỎ NHẤT (Minimum)** khi lôi `MAXOPENFILES` ra so sánh với `FILESPERSET`.

---

# 📖 Phần 3: RMAN Troubleshooting (Xử lý sự cố lỗi)

Đọc lỗi RMAN đôi khi là ác mộng. Hãy trang bị những nguyên tắc cơ bản sau để chẩn đoán.

### 1. Giải mã Error Stack (Ngăn xếp lỗi) ⭐⭐⭐
Lỗi RMAN in ra màn hình đổ dài dằng dặc. **Tuyệt chiêu:** Luôn đọc mảng lỗi từ **DƯỚI ĐÁY ĐỌC LÊN**.
RMAN là kẻ ngoài cùng kêu gào (Mã lỗi `RMAN-XXXXX`), đi chui xuống dưới là do Oracle Database báo mệt (Mã lỗi `ORA-XXXXX`), đi xuống trệt cấu trúc là Hệ điều hành (OS) thông báo Hết chỗ trống hoặc File bị khóa quyền... Do đó đọc dưới cùng để biết căn nguyên!

### 2. Bật còi Báo động rà quét (DEBUG Mode)
Nếu RMAN bị treo đứng im 3 tiếng mà chả nhả ra ORA Error nào thì ta bật ngầm PL/SQL TRACE để túm gáy xem nó đang làm gì kẹt ở sau lưng:
- **DEBUG ở dòng lệnh ngẫu hứng:** 
  `rman target / debug=all trace=rman.trc log=rman.log`
- **DEBUG ép cứng cho Channel (Level từ 1-5):**
  `ALLOCATE CHANNEL c1 TYPE DISK DEBUG=5 TRACE=5;`
- Nhớ phải tìm tắt đi (`debug off` / `CLEAR`). Bật Trace làm tốc độ server rớt siêu thảm hại.

---

# 🎯 Câu hỏi ôn tập Module 16

**1. Trong lúc cấu hình Parameter `BACKUP DURATION 4:00`, cái tham số đuôi `MINIMIZE LOAD` có tác dụng gì? Điều này khác gì với `MINIMIZE TIME`?**
<details>
<summary>💡 Đáp án</summary>
- <b>MINIMIZE TIME</b>: RMAN sẽ chạy với 100% công suất I/O để cố kết thúc nhanh nhất. <br/>
- <b>MINIMIZE LOAD</b>: RMAN lại trở nên rón rén. Nếu nó tính đoán thấy quá trình này vốn chỉ cần 1 tiếng là xong, nó sẽ chèn lệnh ngâm (sleeps) chia đều tiến trình cho nhẹ máy để tiến độ dàn trải đúng yểm 4 tiếng đồng hồ mới bắt đầu báo xong. (Giúp Prod Database buổi đêm đang chạy Load nhẹ lại hẳn!).
</details>

**2. RMAN gặp lỗi `ORA-19506` và sau đó báo thêm `SVR4 Error: 2: No such file`. Nên bắt đầu fix từ đâu?**
<details>
<summary>💡 Đáp án</summary>
Dựa trên nguyên lý ĐỌC TỪ DƯỚI LÊN. Ngọn nguồn lỗi là **SVR4 Error: 2 (Lệnh OS HĐH báo lỗi Không tìm thấy file/Folder định dạng)**. Không cần đi tuning gì trong Database vội, hãy kiểm tra ngay quyền truy cập cấp rwx thư mục ở OS Linux mà RMAN đang target tới xem ông sếp nào vừa đổi Tên Folder.
</details>

---

## ➡️ Bài tiếp theo
**Module 17: Tuyệt đỉnh RMAN Cấp mây & Cụm (RAC, Cloud, Multitenant)**
Đây là Module CUỐI CÙNG làm lễ tốt nghiệp cho Khóa Backup! Chúng ta sẽ xem ứng dụng và quy tắc khắt khe của RMAN khi đưa vào kiến trúc lưới chùm RAC (Real Application Clusters), đưa lên thẳng Đám mây Oracle Cloud (OSB Cloud Service) và cách Backup một Data Pluggable theo cơ chế Căn hộ đa chủ Multitenant cực kì thời thượng của bản 12c!

> Cẩm nang Module 16 Tối ưu Performance đã sẵn sàng. Những kiến thức này khá khô khan lý thuyết nhưng lúc đụng chuyện ngoài thực chiến Production thì nó cứu sống sinh mạng của DBA luôn đó anh! Anh đọc và ngâm cứu nhẹ nhàng nha, sau đó báo em để mình khởi động **Module 17: Bài Tốt Nghiệp Tổng Kết Khóa Cấu Trúc Khủng** nhé! 🚀


---

!!! info "Nguồn gốc"
    `Oracle-Database-Backup-and-Recovery-using-RMAN/modules/module_16/module_16_guide.md`
