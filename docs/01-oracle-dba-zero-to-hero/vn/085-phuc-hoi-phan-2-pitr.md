---
title: 'Bài 85: Khôi phục Phần II - Chuyển sang Image Copies và PITR'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/85-phuc-hoi-phan-2-pitr.md
---

# Bài 85: Khôi phục Phần II - Chuyển sang Image Copies và PITR

## Mục tiêu
Trong bài học này, bạn sẽ học các công việc sau:
- Khôi phục nhanh bằng cách chuyển (Switch) sang Image Copies.
- Hiểu về công nghệ Point-in-Time Recovery (PITR - Khôi phục về thời điểm trong quá khứ).

## Khôi phục bằng cách Switch sang Image Copies
- Thông thường, quy trình `RESTORE` yêu cầu RMAN đọc file backup từ thiết bị lưu trữ, bung nén (nếu là backupset) và sao chép từng byte trả về vị trí gốc của datafile. Quá trình này rất mất thời gian đối với các database lớn.
- Nếu bạn có sẵn **Image Copies** của datafile (ví dụ lưu trong FRA), bạn có thể "biến" chính Image Copy đó thành datafile thực sự (đang hoạt động) ngay lập tức bằng lệnh `SWITCH DATAFILE`. 
- Thao tác này cực nhanh vì thực chất nó chỉ thay đổi đường dẫn vật lý trỏ đến datafile mới trong Control File, bỏ qua hoàn toàn bước sao chép chép lại file.

### Cú pháp Switch
**1. Switch toàn bộ Database (khi Database Mount):**
```rman
STARTUP MOUNT;
SWITCH DATABASE TO COPY;
RECOVER DATABASE;
ALTER DATABASE OPEN;
```
**2. Switch một Datafile (khi Database Open):**
```rman
ALTER DATABASE DATAFILE 4 OFFLINE;
SWITCH DATAFILE 4 TO COPY;
RECOVER DATAFILE 4;
ALTER DATABASE DATAFILE 4 ONLINE;
```

### Ưu nhược điểm
- **Ưu điểm:** Thời gian phục hồi cực kỳ nhanh (chỉ mất vài giây để cập nhật Control File).
- **Nhược điểm:** Yêu cầu ổ đĩa lưu trữ backup phải có hiệu năng cao ngang ngửa ổ đĩa chạy database thật (vì nay database chạy trực tiếp trên ổ đĩa backup đó). Đồng thời, tốn gấp đôi dung lượng vật lý để lưu trữ.

## Về Point-in-Time Recovery (PITR)
- **Point-in-Time Recovery (PITR)** nhằm mục đích đưa database (hoặc một thành phần của nó) quay ngược thời gian trở về một trạng thái trong quá khứ (Ví dụ: 10:00 sáng hôm qua).
- Bạn dùng PITR khi có lỗi Logic nghiêm trọng, ví dụ một user vừa lỡ tay chạy lệnh `DROP TABLE` hoặc `DELETE` toàn bộ dữ liệu kế toán.
- PITR có thể được thực hiện ở 3 cấp độ: Database (DBPITR), Tablespace (TSPITR), hoặc Table.

### Yêu cầu đối với Database PITR (DBPITR)
- Database bắt buộc phải đang chạy ở chế độ **ARCHIVELOG**.
- Bạn bắt buộc phải có đủ file backupset/image copy của các datafile **TRƯỚC** thời điểm mục tiêu.
- Bạn phải có đủ các archived redo log được tạo ra trong khoảng thời gian từ lúc backup tới thời điểm mục tiêu.
- Thao tác DBPITR yêu cầu Database phải được **OFFLINE** (Mount state).

### Thực hiện Database Point-in-Time Recovery (DBPITR)
Có nhiều cách để định dạng thời điểm quay lại: Thời gian (Time), SCN, hoặc Log Sequence.

```rman
-- Thiết lập thời điểm mục tiêu bằng SCN
RUN { 
  SET UNTIL SCN 12345;
  RESTORE DATABASE;
  RECOVER DATABASE;  
}

-- Hoặc thiết lập bằng mốc thời gian cụ thể:
RUN {
  SET UNTIL TIME "TO_DATE('12-OCT-2023 09:00:00','DD-MON-YYYY HH24:MI:SS')";
  RESTORE DATABASE;
  RECOVER DATABASE;
}
```
Sau khi hoàn thành DBPITR, bạn BẮT BUỘC phải mở lại database bằng tùy chọn `RESETLOGS`:
```rman
ALTER DATABASE OPEN RESETLOGS;
```
*(Nếu bạn mở lên nhưng phát hiện mình phục hồi sai giờ (quá sớm hoặc quá muộn), bạn có thể lùi xa hơn vào quá khứ, nhưng vì đã `RESETLOGS` nên bạn phải chỉ định lại Incarnation cũ).*

---
## Câu hỏi ôn tập

**Câu 1: Lợi ích chính của việc sử dụng lệnh `SWITCH DATAFILE TO COPY` là gì?**
- **Trả lời:** Tiết kiệm được toàn bộ thời gian phải di chuyển/sao chép lượng dữ liệu khổng lồ của thao tác `RESTORE`. Quá trình chuyển đổi chỉ mất vài giây vì nó chỉ thay đổi con trỏ đường dẫn trong Control File.

**Câu 2: Nhược điểm lớn nhất khi "Switch" database sang vị trí chạy trên ổ đĩa Backup (FRA) là gì?**
- **Trả lời:** Ổ đĩa Backup (FRA) thường sử dụng phần cứng tốc độ chậm và giá rẻ hơn để lưu trữ. Nếu bạn chuyển database để chạy trực tiếp trên phân vùng này, hiệu năng của database (I/O) có thể sụt giảm nghiêm trọng.

**Câu 3: PITR (Point-in-Time Recovery) được sử dụng để khắc phục lỗi Vật lý (như ổ cứng hỏng) hay lỗi Logic?**
- **Trả lời:** PITR được sử dụng để khắc phục Lỗi Logic (do lỗi thao tác của người dùng như chạy nhầm `DROP TABLE` hoặc code bị sai).

**Câu 4: PITR có thể áp dụng cho database đang chạy chế độ NOARCHIVELOG được không?**
- **Trả lời:** Không thể. Ở chế độ NOARCHIVELOG, không có archived log để RMAN tính toán và dừng lại (roll forward) ở chính xác một mốc thời gian tùy ý. Database chỉ có thể quay về đúng mốc thời gian lúc file backup được tạo ra.

**Câu 5: Tại sao bắt buộc phải dùng `ALTER DATABASE OPEN RESETLOGS;` sau khi hoàn thành thao tác DBPITR?**
- **Trả lời:** Việc mở `RESETLOGS` sẽ bắt đầu một kiếp mới (incarnation) của database và đặt lại các Redo log sequence về 1. Việc này là bắt buộc vì bạn đang phá vỡ dòng thời gian hiện tại của database để sinh ra một nhánh lịch sử dữ liệu mới.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/85-phuc-hoi-phan-2-pitr.md`
