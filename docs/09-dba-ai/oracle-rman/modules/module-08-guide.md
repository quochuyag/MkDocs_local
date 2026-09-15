---
title: '📘 Module 08: Tối ưu Cấp siêu Việt Backups (Improving Backups)'
course: 09-dba-ai
source: dba_ai/oracle_rman/modules/module_08_guide.md
---

# 📘 Module 08: Tối ưu Cấp siêu Việt Backups (Improving Backups)

> **Phạm vi**: Bài 24 - 27 (Improving RMAN Backups & Practice 8)
> **Thời gian học ước tính**: 3 giờ
> **Tiền điều kiện**: RMAN Multi-channel (Parallelism) từ Module 06 và RMAN Job Details Module 07.

---

## 📑 Mục lục
- [Bài 24-26: Tuyệt kỹ Tối ưu: Nén, Phâm Đoạn, Sao Chép Kép và Lưu Trữ Vĩnh Viễn](#-bài-24-26-tuyệt-kỹ-tối-ưu-nén-phâm-đoạn-sao-chép-kép-và-lưu-trữ-vĩnh-viễn)
- [Bài 27: Thực hành (Practice 8) Improving Backups](#-bài-27-thực-hành-practice-8-improving-backups)
- [Bảng tổng hợp & Cú pháp](#-bảng-tổng-hợp--cú-pháp)
- [Câu hỏi ôn tập tổng hợp](#-câu-hỏi-ôn-tập-tổng-hợp)

---

# 📖 Bài 24-26: Tuyệt kỹ Tối ưu: Nén, Phâm Đoạn, Sao Chép Kép và Lưu Trữ Vĩnh Viễn

## 🎯 Mục tiêu bài học
Sau khi hoàn thành bài này, bạn sẽ:
- ✅ Hiểu sâu cơ chế "Lơ đi" (Skip) khối Block trắng tự động của Oracle.
- ✅ Cấu hình Compression Algorithm đa cấp độ (BASIC, LOW, MEDIUM, HIGH) đánh đổi CPU lấy Storage.
- ✅ Áp dụng `MULTISECTION` để vỡ vụn các tệp Datafile hàng terabyte khổng lồ cho Nhiều Channels chạy.
- ✅ Duplex Backup Sets (Nhân đôi 4 bản) bảo hiểm tối đa khi tạo tape.
- ✅ Tạo riêng nhánh Sao lưu Lưu trữ Lâu dài (Archival Backups) nằm ngoài biên vòng quy định Retention hàng ngày.

## 💡 Ý tưởng cốt lõi (Memory Hack)
- RMAN xưa nay có **Parallelism (Song song hóa)**: 4 Channel cày 4 Files khác nhau. 
- Nhưng 1 File Datafile A mà to mập tới 5TB (Doanh nghiệp), 3 File kia chút éc. Kết quả: 3 Channels xong sớm nằm chơi xơi nước, 1 Channel hì hục cày 5TB hết 10 tiếng! Nghẽn cổ chai cục bộ!
- -> Khắc phục: Dùng **MULTISECTION SECTION SIZE**. 4 thằng xúm lại cắt cái bánh 5TB thành nhiều phần để xẻ cùng lúc!

---

## 📋 Nội dung chính

### 1. Thuật toán Tiết kiệm Block (Skipping Unused/Null Blocks)

Khi backup 1 datafile 100GB, liệu RMAN có copy luôn đoạn chứa khoảng không dung lượng trắng vô vần?
Hên quá, **KHÔNG!** RMAN có "Null Block Compression":
- RMAN tự động lơ đi các khúc sau đuôi High-Water Mark (Chưa hề có data).
- RMAN cũng bỏ qua các Unused Block (Block đã từng xóa đi table/row) NẾU nó đang đi vào DISK và không bị ghim Restore Point.
- Đây là cơ chế MẶC ĐỊNH tuyệt vời của riêng Backupsets. Đừng nhầm lẫn với "Compression Zip File".

### 2. Thuật toán Nén Nhị Phân (Binary Compression) ⭐⭐⭐

Đây mới là nén thực sự - Đè bẹp số Block còn sót lại thành kích thước nhỏ để bốc qua băng từ Tape.

Oracle 12c hỗ trợ chuẩn:
- `BASIC` (Miễn phí đi kèm gói Standard).
- `LOW, MEDIUM, HIGH` (Yêu cầu bằng giấy phép bạc tỷ 💰 *Oracle Advanced Compression*). Nén High thì giảm mỡ cực nhiều nhưng đốt CPU server cháy rực lửa, CỰC KÌ cẩn trọng.

**Lệnh RMAN thực thi cấu hình vĩnh viễn:**
```sql
RMAN> CONFIGURE COMPRESSION ALGORITHM 'MEDIUM';
RMAN> BACKUP AS COMPRESSED BACKUPSET DATABASE PLUS ARCHIVELOG;
```
> [!TIP]
> Việc thiết lập `OPTIMIZE FOR LOAD` thành FALSE sẽ ép RMAN tốn thêm CPU chạy pre-processor làm gọn các khối free-space giúp Compression Ratio lên cực chuẩn xác nhưng châm đi. Cân nhắc kỹ lưỡng ranh giới CPU/Tốc độ I-O.

### 3. Phân Lát Datafile đa mặt cắt (Multisection Backups) 🪚

Sức mạnh cứu cánh cho DataWareHouse (Các Datafiles vượt ngưỡng 1-2 TB mỗi file). 

```text
KHÔNG CÓ MULTISECTION
Channel 1 ──> Hì hục cày Datafile_Users.dbf (2 TB) ──> Backup piece 1 (Xong sau 4 tiếng)
Channel 2 ──> Cày Datafile_Tools.dbf (1 GB) ───────> Xong trong 2s (Rảnh chơi game 4 tiếng).

CÓ MULTISECTION SIZE = 500GB
Datafile_Users.dbf (2 TB):
├─ Lát 500GB số 1 ──> Channel 1 ──> Piece 1
├─ Lát 500GB số 2 ──> Channel 2 ──> Piece 2
├─ Lát 500GB số 3 ──> Channel 1 ──> Piece 3  (Xong sau 1 tiếng cả thảy)
```

**Lệnh RMAN thực thi cắt lát tại chỗ:**
```sql
-- Cắt Datafile ra từng lát 500M để cấy song song.
RMAN> BACKUP SECTION SIZE 500M DATAFILE '/oradata/orcl/users.dbf';
```

### 4. Nhân Bức Sao Lưu Kép (Duplexing Backup Sets)

Tạo cùng lúc được **tối đa 4 bản (COPIES)** cho 1 mẻ backup. Quăng 1 bản trên Tape, quăng 1 bản qua NFS rác của công ty kế bên. Bảo hiểm tuyệt đỉnh lúc Disaster Recovery.

**Lệnh RMAN thực thi:**
```sql
RMAN> BACKUP AS BACKUPSET DEVICE TYPE DISK
      COPIES 2 DATABASE FORMAT '/disk1/db_%U', '/disk2/db_%U';
```
*(Tham số `FORMAT` báo 2 cái tên phân tán ra 2 đĩa cách ly vật lý)*.
**Lỗi cấm chú ý:** RMAN CẤM không cho tạo Duplex vào khu vực Fast Recovery Area (FRA) tự động. FRA chỉ giữ 1 bản. Hãy ném ra thư mục thuần `/disk2`.

### 5. Sao lưu Trường Tồn Kỷ Nguyên (Archival Backups) ⭐⭐⭐

> [!CAUTION]
> Retention Policy có lệnh `DELETE OBSOLETE` sẽ bóp nát mọi thứ quá "7 ngày", kể cả mốc cuối năm (Quý IV) giám đốc yêu cầu lưu lại rà soát riêng biệt 10 năm nữa (Cục thuế/ Kiểm toán/ Pháp chế). Giải pháp: Bọc kén "Lực Hấp Dẫn" từ vựng `KEEP FOREVER`!

**Workflow:**
Bọc kén một bộ Full System, gán mác `KEEP` - Kháng tất cả mọi sự hủy hoại từ `OBSOLETE`.

**Lệnh RMAN thực thi (Tạo Restore point để lưu):**
```sql
RMAN> BACKUP DATABASE TAG 'YEAREND_2026' 
      KEEP FOREVER RESTORE POINT RP_YEAREND_2026;
      
-- Hoặc nếu chỉ giữ để Kiểm toán coi trong 5 năm:
RMAN> BACKUP DATABASE TAG 'HSO_LAW' KEEP UNTIL TIME 'SYSDATE+1825';
```
*(Tất nhiên KEEP FOREVER yêu cầu kết nối với siêu máy chủ Recovery Catalog. Control File cùi bắp dung lượng nhạy cảm 365 ngày không thể nhét thông tin forever vào mạch của nó)*.

---

# 💻 Bài 27: Thực hành (Practice 8) Improving Backups

> **Mục tiêu**: Cân đo sức hấp thụ tài nguyên phần cứng (CPU/Disk) khi test 3 chế độ Nén, và chặt khúc bằng Section.

## Tình huống 1: Benchmark Trận chiến Compression (Thuật toán vắt mỡ)
Thực hành xem thằng nào ép mạnh nhất và ai làm lơ tốc độ:
```sql
# Test 1: Không nén (Raw BaseLine)
RMAN> SET COMPRESSION ALGORITHM 'BASIC';
RMAN> BACKUP DATABASE TAG 'NO_COMP';
# Note lại Output Elapsed time và Size: Ví dụ 30GB, mất 5 phút.

# Test 2: Vắt Medium
RMAN> SET COMPRESSION ALGORITHM 'MEDIUM';
RMAN> BACKUP AS COMPRESSED BACKUPSET DATABASE TAG 'COMP_MEDIUM';
# Note lại: Còn 8GB, mất 10 phút. (CPU 70%)

# Test 3: Vắt Kiệt Nước High
RMAN> SET COMPRESSION ALGORITHM 'HIGH';
RMAN> BACKUP AS COMPRESSED BACKUPSET DATABASE TAG 'COMP_HIGH';
# Note lại: Còn 6GB, mất 35 phút! (CPU 100% hú lên báo động!). 
```
*Lời khuyên Production DBA:* Hiệu suất "Sống Còn" không phải file backup mà là Performance của Server đang chạy app. Set HIGH trên DB bận rộn = Đuổi khách hàng về vì Web giật lag. Nên dùng BASIC hoăc MEDIUM!

## Tình huống 2: Sức mạnh dao thớt Section Size 
So sánh cách 1 Channel vs 2 Channels tấn công 1 Datafile duy nhất khi bị xé rời (Dùng SQL OS check):
```sql
# Cho 2 họng súng (Channel) vô cuộc.
RMAN> RUN { 
  ALLOCATE CHANNEL c1 DEVICE TYPE DISK;  
  ALLOCATE CHANNEL c2 DEVICE TYPE DISK;  
  BACKUP TABLESPACE SOETBS TAG 'SOETBS_MULTIS' SECTION SIZE 500M; 
}
# Output RMAN Job Details: "2 channels running in parallel for exactly 1 Input Datafile". ĐỈNH CAO!

# Test Query V$ View 
SQL> SELECT PIECES, MULTI_SECTION FROM V$BACKUP_SET WHERE RECID=X;
# MULTI_SECTION = YES -> Oracle nhận diện cấu trúc chặt rã. Mừng rõ!
```

---

# 📊 Bảng tổng hợp & Cú pháp

| Nhược điểm cần trị | Liều thuốc đắc lực (Lệnh RMAN) | Cơ chế Giải Mã Kỹ Thuật |
|----------|-------------------|--------------------------------------|
| **Thiếu Ổ cứng kinh niên** | `BACKUP AS COMPRESSED ...;` | Đẩy sức mạnh CPU nhét data vô túi Zip. Oracle có 4 level nhưng cẩn thận License $! |
| **Một File Datafile quá bự 5TB** | `BACKUP ... SECTION SIZE 500GB;` | Chặt file 5TB thành 10 miếng, nhồi cho Parallel đa luồng đè ra xúc ngay. Hiệu quả tuyệt. |
| **Sợ cháy DataCenter Disk 1**| `BACKUP ... COPIES 2 ... FORMAT '/o1','/o2'` | Sinh đôi (hoặc sinh bốn). Mất 1 nơi, anh em nó ở nơi khác gánh team. Lệnh Duplexing. |
| **Compliance Pháp luật 10 Năm**| `BACKUP ... KEEP FOREVER RESTORE...;` | Thoát khỏi lưỡi hái thần chết (Retention Obsolete). Nhưng lưu ý: Đói Recovery Catalog. |

---

# 🎯 Câu hỏi ôn tập tổng hợp

1. Nêu sự khác biệt nguyên lý giữa Null Block Compression (Cơ chế lơ đi tự động của RMAN Backup Sets) và Thuật toán Binary Compression 'MEDIUM'? Cả hai có thể dùng chung với nhau không?
2. Giả sử bạn set Parameter RMAN `PARALLELISM = 4`. Bạn chạy backup chỉ chuyên duy nhất 1 Datafile System01.dbf dung lượng 10TB bằng `BACKUP DATAFILE 1;`. Theo tiến trình RMAN mặc định, việc này tốn bao nhiêu kênh Channel sẽ làm việc? (Tricks: Tầm quan trọng của Cụm từ Multisection).
3. Đội giám sát An toàn dữ liệu có ý định Backup bản Duplex làm đôi, 1 rớt vào `/disk1`, 1 rớt vào Fast Recovery Area bằng COPIES 2. Có nguy cơ Crash RMAN xảy ra lỗi không? Vì sao?
4. Đội Audit (Kiểm toán) công ty yêu cầu bạn phải lấy hệ thống Data quý 3 cất trong phòng tủ sắt 5 năm trời. Nếu bạn xài câu lệnh `KEEP UNTIL TIME 'SYSDATE+1825'`, nó có bị xóa bới lệnh dọn rác dĩa `DELETE OBSOLETE` chạy qua mạng hằng ngày trong 5 năm tới không? Giải phóng bùa trừ khử Retention nó sinh ra như thế nào?

---
## ➡️ Bài tiếp theo
Đã học được cách cấu hình "Nhớ lâu 10 năm" với Keep Forever, đã đến lúc giải bài toán "Cắm bộ nhớ ngoại vi" cho RMAN - bộ lưu trữ không giới hạn thời gian: **Module 09: Recovery Catalog**. Cách RMAN bỏ đi cơ chế nhớ trong RAM control file nghèo nàn và lưu vô 1 database hầm nấp Metadata xịn sò! 🚀 
Bạn có muốn thử review lại các biến CPU Benchmark của Compression test không hay bay luôn vào khái niệm mới Recovery Catalog?


---

!!! info "Nguồn gốc"
    `dba_ai/oracle_rman/modules/module_08_guide.md`
