---
title: 'Bài 114: Thực hành - Cập nhật Bản vá trên Oracle Restart'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/114-practice-patching-oracle-restart.md
---

# Bài 114: Thực hành - Cập nhật Bản vá trên Oracle Restart

## Mục tiêu
Trong bài thực hành này, bạn sẽ học cách:
- Cập nhật công cụ `OPatch` trong cả hai môi trường (Grid Home và Database Home).
- Cài đặt một bản vá RU (Release Update) lên môi trường có cấu trúc Oracle Restart (Grid Infrastructure Standalone).
- Hiểu được lệnh cấp quyền root (`opatchauto`).

## Tổng quan quy trình vá (Patching) trên Oracle Restart
Trong môi trường Single Instance bình thường, bạn chỉ việc gõ `opatch apply` bằng tài khoản `oracle` để nâng cấp bản vá. 
Nhưng với cấu trúc hạ tầng có chứa Grid/ASM, quy trình phức tạp hơn nhiều vì nó liên quan đến phần lõi quản lý ổ cứng và bảo mật cấp cao. Mọi thao tác cài đặt bản vá vật lý bắt buộc phải chạy dưới quyền của tài khoản **`root`**, thông qua một công cụ gọi là `opatchauto`. Công cụ này sẽ lo toàn bộ việc dừng, bật và vá cùng lúc cả phần mềm Grid lẫn phần mềm Database.

## Các bước thực hiện

**1. Tải bản vá RU mới (Ví dụ Grid RU 19.16) và cập nhật OPatch**
Bộ vá Grid (Grid Infrastructure Release Update) là một bộ vá khổng lồ (thường nặng hơn 2GB), bao gồm CẢ bản vá cho Grid VÀ bản vá cho Database tích hợp sẵn bên trong.
Bạn phải cập nhật thủ công phiên bản `OPatch` mới nhất (Patch 6880880) cho **CẢ HAI** thư mục:
- `$ORACLE_HOME` của user `oracle`
- `$ORACLE_HOME` (GRID_HOME) của user `grid`.

**2. Giải nén bản vá dưới tư cách quyền Root**
Bản vá phải được giải nén vào một thư mục tạm mà người dùng nào cũng có quyền truy cập (Ví dụ `/media/sf_staging/34133642`). Không nên nén vào Home directory của user cá nhân.

**3. Kiểm tra xung đột tự động (Pre-Check)**
Đăng nhập tài khoản `root`. Chạy lệnh phân tích rủi ro của `opatchauto` trên thư mục bản vá:
```bash
/u01/app/19.0.0/grid/OPatch/opatchauto apply /media/sf_staging/34133642 -analyze
```
*(Nếu kết quả cuối cùng ghi `OPatchAuto successful`, bạn được phép tiếp tục cài đặt thật).*

**4. Áp dụng bản vá (Apply)**
Tiếp tục dưới quyền `root`, bạn thực thi lệnh cài đặt không có cờ `-analyze`:
```bash
/u01/app/19.0.0/grid/OPatch/opatchauto apply /media/sf_staging/34133642
```
*(Lệnh này cực kỳ mạnh, nó sẽ tự động chạy lệnh dừng toàn bộ Database, dừng listener, dừng ASM Instance, cài đè các file binary cho Grid, sau đó cài đè file binary cho Oracle DB, rồi tự động bật lại toàn bộ hệ thống. Quá trình này diễn ra khá lâu).*

**5. Đồng bộ cấu trúc Data Dictionary (`datapatch`)**
Cũng giống như bài cài đặt trước, phần mềm vật lý đã lên bản mới nhưng Data Dictionary trong ruột database chưa hiểu.
- Chuyển sang tài khoản OS `oracle` (Không dùng root nữa).
- Mở tất cả các PDB lên.
- Di chuyển vào thư mục `$ORACLE_HOME/OPatch` và chạy lệnh cập nhật SQL nội bộ:
```bash
./datapatch -verbose
```

---
## Câu hỏi ôn tập

**Câu 1: Tôi có thể đăng nhập tài khoản OS `oracle` và chạy thủ công lệnh `opatch apply` cho máy có ASM được không?**
- **Trả lời:** Không thể. Bất kỳ cấu trúc hạ tầng nào chạy ASM (Grid Infrastructure / Oracle Restart / RAC) đều yêu cầu quy trình cấp quyền lõi can thiệp vào driver hệ điều hành. Chỉ có công cụ `opatchauto` chạy bằng quyền `root` mới được phép thao tác cài đặt bản vá vật lý này.

**Câu 2: Nếu lệnh `opatchauto apply` bị hỏng giữa chừng thì sao?**
- **Trả lời:** Bạn có thể phải chạy lệnh `opatchauto rollback` để khôi phục lại trạng thái cũ, HOẶC bạn phải tự tay phục hồi (restore) từ các bản sao lưu (tar/zip) của 2 thư mục `GRID_HOME` và `DB_HOME` mà bạn đã phải tạo thủ công trước khi cài. 

**Câu 3: Một file tải về Grid RU có chứa bản vá cho Database không?**
- **Trả lời:** Có. Các bản vá Grid RU (GIRU) là bản vá "tất cả trong một". Oracle đóng gói chung cả bản vá của phần mềm DB vào bên trong cấu trúc thư mục của GIRU. Khi `opatchauto` chạy, nó sẽ vá cho Grid trước, sau đó vá cho Database.

**Câu 4: Tại sao sau khi `opatchauto` chạy tự động hết rồi, tôi vẫn phải chạy tay lệnh `datapatch`?**
- **Trả lời:** `opatchauto` chỉ tự động nâng cấp các file nhị phân (Binary) và tự khởi động lại các Instance. Nhưng Oracle không muốn các câu lệnh chạy DDL rủi ro can thiệp ruột dữ liệu (Data Dictionary) bị nhúng ngầm vào trong lệnh root. Việc thao tác dữ liệu vẫn nên do DBA trực tiếp điều khiển bằng tay thông qua lệnh `datapatch`.

**Câu 5: Có thể cập nhật OPatch bằng lệnh `opatchauto` không?**
- **Trả lời:** Không. Mặc dù `opatchauto` lo tất cả việc vá, nhưng bản thân thư mục lõi của `OPatch` thì hệ thống không thể vừa chạy nó vừa xóa nó được. Bạn phải gỡ thủ công OPatch cũ và copy thư mục OPatch mới vào bằng tay.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/114-practice-patching-oracle-restart.md`
