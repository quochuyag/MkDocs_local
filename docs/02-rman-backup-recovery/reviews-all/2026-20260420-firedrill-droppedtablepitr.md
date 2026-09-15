---
title: '🚨 Báo Động Đỏ: Developer Lỡ Tay DROP Bảng (PITR)'
course: 02-rman-backup-recovery
source: Oracle-Database-Backup-and-Recovery-using-RMAN/reviews_all/20260420_FireDrill_DroppedTablePITR.md
---

# 🚨 Báo Động Đỏ: Developer Lỡ Tay DROP Bảng (PITR)

**Chế độ**: Fire Drill (Diễn tập sự cố khẩn cấp - Module 12)
**Ngày tạo**: 2026-04-20

## 1. Tình trạng sự cố
Vào lúc 14:45 chiều thứ Ba, một Senior Developer mồ hôi nhễ nhại chạy đến bàn của bạn. 
Lúc 14:30, trong lúc dọn dẹp môi trường Production, anh ta đã gõ nhầm và chạy lệnh:
`DROP TABLE CORE_APP.SYSTEM_CONFIG;`

Bảng `SYSTEM_CONFIG` chứa toàn bộ tham số hoạt động của ứng dụng, khiến ứng dụng báo lỗi HTTP 500 liên tục.
Tin tốt: Database `PRODDB` vẫn đang hoạt động tốt.
Tin xấu: Bạn KHÔNG được quyền tắt DB (Downtime) vì các module khác vẫn đang có user truy cập. Bảng này không có Recycle Bin (vì đã bị purge hoặc dùng DROP TABLE ... PURGE).

## 2. Nhiệm vụ của bạn (DBA)
Bạn cần khôi phục lại bảng `CORE_APP.SYSTEM_CONFIG` về thời điểm chính xác là 14:29:00 (trước khi bị drop) mà **không làm gián đoạn** hoạt động của toàn bộ cơ sở dữ liệu.

## 3. Câu hỏi
1. Lệnh RMAN nào cho phép bạn khôi phục một bảng duy nhất?
2. RMAN sẽ thực hiện quá trình khôi phục bảng này như thế nào ở phía hậu trường (behind the scenes)?
3. Bạn cần chuẩn bị những gì ở mức OS để thực thi lệnh này?

---

## 4. Hướng dẫn xử lý (Action Plan - Đáp án)

Dưới đây là các bước xử lý khôi phục bảng (Table Point-In-Time Recovery) được hỗ trợ từ Oracle 12c:

### Bước 1: Chuẩn bị không gian tạm (Auxiliary Destination)
Để khôi phục 1 bảng, RMAN sẽ tự động tạo một database tạm (Auxiliary Database) ẩn ở hậu trường, restore các tablespace liên quan (SYSTEM, SYSAUX, UNDO, và tablespace chứa bảng đó), khôi phục dữ liệu tới thời điểm 14:29:00, Data Pump Export bảng đó, và cuối cùng Import ngược lại vào `PRODDB`.
Để RMAN làm được việc này, bạn cần cung cấp một thư mục trống đủ lớn trên server.
```bash
mkdir -p /u01/app/oracle/oradata/aux_dest
```

### Bước 2: Thực thi lệnh RMAN Khôi phục Bảng
Truy cập vào RMAN (kết nối tới target `PRODDB`):
```rman
RMAN> RECOVER TABLE 'CORE_APP'.'SYSTEM_CONFIG'
      UNTIL TIME "TO_DATE('2026-04-20 14:29:00', 'YYYY-MM-DD HH24:MI:SS')"
      AUXILIARY DESTINATION '/u01/app/oracle/oradata/aux_dest';
```

### Bước 3: Theo dõi quá trình tự động
RMAN sẽ in ra màn hình toàn bộ tiến trình:
1. Tạo instance tạm thời với tên sinh ngẫu nhiên (vd: `xpt_`)
2. Restore Control file và các Tablespace cần thiết vào thư mục `/aux_dest`.
3. Recover database tạm tới đúng thời điểm `14:29:00`.
4. Mở database tạm ở chế độ Read-Only.
5. Dùng Data Pump (expdp) xuất bảng `SYSTEM_CONFIG` ra một dump file.
6. Dùng Data Pump (impdp) nạp bảng đó ngược lại vào `PRODDB`.
7. Dọn dẹp: Tắt instance tạm và xóa sạch thư mục `/aux_dest`.

> [!TIP]
> Bạn có thể thêm tham số `REMAP TABLE 'CORE_APP'.'SYSTEM_CONFIG':'SYSTEM_CONFIG_RESTORED'` nếu không muốn ghi đè hoặc muốn DEV kiểm tra lại bảng đã restore trước khi đổi tên thay thế bảng chính.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Backup-and-Recovery-using-RMAN/reviews_all/20260420_FireDrill_DroppedTablePITR.md`
