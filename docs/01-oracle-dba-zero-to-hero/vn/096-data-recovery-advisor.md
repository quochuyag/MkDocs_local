---
title: 'Bài 96: Data Recovery Advisor (Cố vấn Phục hồi Dữ liệu)'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/96-data-recovery-advisor.md
---

# Bài 96: Data Recovery Advisor (Cố vấn Phục hồi Dữ liệu)

## Mục tiêu
Trong bài học này, bạn sẽ học cách thực hiện các công việc sau:
- Nắm bắt vòng đời và các thuật ngữ của Data Recovery Advisor (DRA).
- Sử dụng Data Recovery Advisor để phát hiện và chẩn đoán lỗi dữ liệu.
- Nhận các gợi ý sửa chữa tự động từ DRA.
- Dùng DRA để thực thi tự động các thao tác sửa lỗi.

## Tổng quan và Thuật ngữ của Data Recovery Advisor
Data Recovery Advisor (DRA) là một công cụ chẩn đoán tự động tích hợp sẵn của Oracle giúp các DBA nhanh chóng phát hiện nguyên nhân gây lỗi hỏng hóc dữ liệu (corruptions) và cung cấp script sửa lỗi tự động mà không cần DBA phải tự nghĩ ra các lệnh RMAN.

- **Data Integrity Check (Kiểm tra toàn vẹn):** Quá trình rà soát để tìm ra dữ liệu hỏng.
- **Failure (Lỗi):** Một sự cố dữ liệu vật lý (như mất file) được hệ thống phát hiện ra. Lỗi có 2 trạng thái: `OPEN` (Chưa được sửa) và `CLOSED` (Đã được sửa). Đi kèm là mức độ ưu tiên: `CRITICAL`, `HIGH`, `LOW`.
- **Repair Script (Kịch bản sửa chữa):** Đoạn mã RMAN/SQL tự động sinh ra bởi công cụ Advisor để khắc phục lỗi.

## Vòng đời hoạt động của Data Recovery Advisor
1. Lỗi bị phát hiện (Bởi hệ thống Health Monitor tự động hoặc do DBA chạy lệnh báo cáo).
2. DBA chạy `LIST FAILURE;` để xem danh sách lỗi.
3. Chạy `ADVISE FAILURE;` để công cụ đánh giá và đưa ra giải pháp khắc phục.
4. Chạy `REPAIR FAILURE;` để hệ thống tự động vá lỗi theo giải pháp đã đưa ra.

## 1. Phát hiện và Liệt kê lỗi (LIST FAILURE)
Bạn có thể ra lệnh cho RMAN kiểm tra chủ động các khối dữ liệu bằng lệnh:
```rman
VALIDATE DATABASE;
VALIDATE TABLESPACE users;
```
Sau đó, để xem các sự cố được hệ thống ghi nhận, sử dụng lệnh:
```rman
LIST FAILURE;
LIST FAILURE 105 DETAIL; -- (Xem chi tiết một mã lỗi cụ thể)
LIST FAILURE CLOSED; -- (Xem các lỗi đã từng được vá)
```

## 2. Lấy lời khuyên sửa chữa (ADVISE FAILURE)
Khi đã có mã lỗi (vd: Mất Datafile hệ thống), bạn dùng lệnh sau để yêu cầu Oracle đưa ra kịch bản sửa chữa (Repair Script):
```rman
ADVISE FAILURE;
```
Kết quả trả về sẽ cho bạn biết:
- Các thao tác tay bắt buộc (nếu có).
- Kế hoạch sửa tự động bằng RMAN (ví dụ: cần chạy `restore datafile` nào, `recover` tới block nào). Đường dẫn file script cũng được hiển thị (ví dụ `/prod/hm/reco_660.hm`).

## 3. Thực thi Sửa chữa (REPAIR FAILURE)
Sử dụng lệnh này để tự động thực thi kịch bản sửa lỗi gần nhất mà `ADVISE FAILURE` vừa tạo ra trong phiên làm việc hiện tại:
```rman
REPAIR FAILURE;
```
*(Hệ thống sẽ in lại script ra màn hình và hỏi bạn `Do you really want to execute the above repair (enter YES or NO)?`. Bạn có thể dùng tham số `NOPROMPT` nếu muốn nó chạy luôn bỏ qua bước xác nhận).*

Nếu bạn chỉ muốn xem trước những lệnh RMAN nào sẽ được thực thi mà không chạy thật sự:
```rman
REPAIR FAILURE PREVIEW;
```

## Thay đổi trạng thái lỗi
Nếu bạn đã tự sửa lỗi bằng tay bên ngoài, hệ thống DRA đôi khi không tự nhận ra, bạn có thể ép thay đổi trạng thái của lỗi đó:
```rman
CHANGE FAILURE 104 CLOSED;
CHANGE FAILURE ALL PRIORITY HIGH;
```

---
## Câu hỏi ôn tập

**Câu 1: Lợi ích chính của việc sử dụng Data Recovery Advisor là gì?**
- **Trả lời:** Giúp DBA (đặc biệt là người ít kinh nghiệm) không cần phải tự nghĩ và gõ các lệnh RMAN phức tạp để khôi phục dữ liệu. Hệ thống sẽ tự chẩn đoán nguyên nhân và sinh ra sẵn script sửa lỗi để xử lý tự động.

**Câu 2: Một "Failure" (Lỗi) trong DRA có những trạng thái (status) nào?**
- **Trả lời:** Có 2 trạng thái là `OPEN` (Lỗi đang tồn tại, chưa được xử lý) và `CLOSED` (Lỗi đã được khắc phục xong).

**Câu 3: Lệnh `VALIDATE DATABASE;` đóng vai trò gì trong vòng đời của DRA?**
- **Trả lời:** Lệnh này giúp kích hoạt quá trình quét chủ động toàn bộ database để tìm kiếm các khối dữ liệu hỏng vật lý hoặc logic, từ đó sinh ra các cảnh báo lỗi để DRA ghi nhận.

**Câu 4: Làm sao để xem nội dung của kịch bản sửa chữa (Repair Script) mà chưa cần chạy nó ngay?**
- **Trả lời:** Chạy lệnh `ADVISE FAILURE;` (Nó sẽ hiển thị đường dẫn file script để bạn mở bằng text editor) hoặc chạy `REPAIR FAILURE PREVIEW;` (Nó sẽ in các lệnh sắp sửa chạy ra màn hình).

**Câu 5: Nếu tôi đã tự chạy lệnh `RESTORE` và `RECOVER` bằng tay để sửa file hỏng, tôi có cần dùng tới DRA nữa không?**
- **Trả lời:** Không cần dùng để sửa nữa, tuy nhiên bạn nên chạy lệnh `CHANGE FAILURE <mã_lỗi> CLOSED;` để xóa cảnh báo lỗi đó khỏi hệ thống báo cáo của DRA.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/96-data-recovery-advisor.md`
