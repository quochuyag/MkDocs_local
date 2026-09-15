---
title: 'Bài 93: Thực hành - Nhân bản Databases và PDBs bằng RMAN'
course: 01-oracle-dba-zero-to-hero
source: Oracle-Database-Administration-from-Zero-to-Hero/VN/93-thuc-hanh-nhan-ban-database.md
---

# Bài 93: Thực hành - Nhân bản Databases và PDBs bằng RMAN

## Mục tiêu
Trong bài thực hành này, bạn sẽ làm quen với việc:
- Chuẩn bị môi trường (Auxiliary Database) để tiến hành nhân bản.
- Thực hiện Active Database Duplication (clone trực tiếp qua mạng).
- Thực hiện Backup-Based Duplication (clone từ file backup).
- Thực hiện nhân bản riêng một PDB (Active PDB Duplication).

## A. Chuẩn bị Auxiliary Database (Máy chủ/Instance Đích)
Trong môi trường LAB này, chúng ta sẽ clone database ngay trên cùng một máy chủ `srv1` (từ `oradb` sang `oradb2`).

**1.** Khởi động `srv1` quyền oracle.
**2.** Tạo các thư mục vật lý để chứa database mới (`oradb2`):
```bash
mkdir -p /u01/app/oracle/oradata/oradb2
mkdir -p /u01/app/oracle/fra/oradb2
```
**3.** Chỉnh sửa file `tnsnames.ora` và `listener.ora` (mở kết nối Tĩnh cho `oradb2`).
*(Trong bài LAB, các file cấu hình mẫu đã được cấp sẵn trong thư mục bài học, bạn chỉ cần copy đè chúng vào `$ORACLE_HOME/network/admin` và reload lại listener)*:
```bash
lsnrctl reload
```
**4.** Kiểm tra xem RMAN có thể nhìn thấy instance mới (dù nó chưa bật) thông qua TNS không:
```bash
sqlplus sys/password@oradb2 as sysdba
```
*(Bạn sẽ nhận được lỗi "Connected to an idle instance" -> Kết nối thành công!)*
**5.** Tạo file PFILE tối thiểu cho `oradb2` và copy Password file:
```bash
vi $ORACLE_HOME/dbs/initoradb2.ora
# Nhập dòng duy nhất: DB_NAME=oradb2 (Lưu lại :wq)

cp $ORACLE_HOME/dbs/orapworadb $ORACLE_HOME/dbs/orapworadb2
```
**6.** Bật Auxiliary Instance lên trạng thái `NOMOUNT`:
```bash
export ORACLE_SID=oradb2
sqlplus / as sysdba
STARTUP NOMOUNT
```

## B. Thực hiện Active Database Duplication
**7.** Mở RMAN, kết nối đồng thời vào Nguồn (`TARGET`) và Đích (`AUXILIARY`):
```bash
rman TARGET sys/password@oradb AUXILIARY sys/password@oradb2
```
**8.** Thực thi đoạn script tự động cấu hình lại đường dẫn và nạp dữ liệu trực tiếp:
```rman
RUN {
  DUPLICATE DATABASE TO oradb2
  FROM ACTIVE DATABASE
  SPFILE
  SET CONTROL_FILES '/u01/app/oracle/oradata/oradb2/control1.ctl', 
                    '/u01/app/oracle/fra/oradb2/control2.ctl'
  SET DB_CREATE_FILE_DEST '/u01/app/oracle/oradata'
  SET DB_RECOVERY_FILE_DEST '/u01/app/oracle/fra/oradb2'
  SET DB_RECOVERY_FILE_DEST_SIZE '40G';
}
```
*(RMAN sẽ tự động copy toàn bộ datafile sang thư mục mới, gán ID mới và OPEN database cho bạn).*

## C. Thực hiện Backup-Based Duplication (Không kết nối Target)
Giả sử bạn chỉ mang các file backup (.bkp) copy vào thư mục `/media/sf_staging/backup` và muốn clone database.
**9.** Truy cập RMAN, CHỈ kết nối vào máy đích:
```bash
rman AUXILIARY sys/password@oradb2
```
**10.** Chạy lệnh nhân bản. Ở đây ta phải thêm dòng `BACKUP LOCATION` để báo vị trí file vật lý:
```rman
RUN {
  DUPLICATE DATABASE TO oradb2
  SPFILE
  SET CONTROL_FILES '/u01/app/oracle/oradata/oradb2/control1.ctl'
  SET DB_CREATE_FILE_DEST '/u01/app/oracle/oradata'
  BACKUP LOCATION '/media/sf_staging/backup';
}
```

## D. Thực hiện Active PDB Duplication (Chỉ clone 1 PDB)
Để chỉ clone riêng `PDB1` từ hệ thống gốc.
**11.** Kết nối RMAN vào cả Target và Auxiliary.
**12.** Thực hiện lệnh y hệt phần B, nhưng có thêm đuôi `PLUGGABLE DATABASE`:
```rman
RUN {
  DUPLICATE DATABASE TO oradb2
  PLUGGABLE DATABASE pdb1
  FROM ACTIVE DATABASE
  SPFILE
  SET CONTROL_FILES '/.../control1.ctl'
  SET DB_CREATE_FILE_DEST '/.../oradata';
}
```
*(Khi hoàn tất, instance `oradb2` sẽ được sinh ra, bên trong nó chỉ chứa đúng Seed và `pdb1`, các PDB khác bị loại bỏ).*

---
## Câu hỏi ôn tập

**Câu 1: Ở bước số 5, tại sao file cấu hình PFILE của database mới (`initoradb2.ora`) chỉ cần duy nhất 1 dòng `DB_NAME=oradb2`?**
- **Trả lời:** Vì ở trạng thái `NOMOUNT`, Instance chỉ cần biết tên tối thiểu để cấp phát vùng nhớ SGA tạm thời. Sau khi lệnh `DUPLICATE` chạy, RMAN sẽ tự động copy cấu hình chuẩn (SPFILE) từ máy nguồn sang để đè lên các tham số cấu hình.

**Câu 2: Tại sao trước khi gõ lệnh DUPLICATE, ta lại phải copy file mật khẩu (Password File) từ hệ thống cũ sang hệ thống mới?**
- **Trả lời:** Oracle sử dụng Password File để xác thực các User có quyền quản trị (như SYS). Khi kết nối RMAN qua mạng (`AUXILIARY sys/password@oradb2`), instance đích cần Password File này để thẩm định tài khoản truy cập.

**Câu 3: Mục đích của cụm lệnh `SET DB_CREATE_FILE_DEST` trong khối RUN là gì?**
- **Trả lời:** Đây là các lệnh ép cấu hình Oracle Managed Files (OMF) cho database mới. RMAN sẽ dựa vào đường dẫn này để tự động đổi tên và sinh các datafiles cho database mới mà ta không cần cấu hình đổi tên thủ công từng file một.

**Câu 4: Điểm khác biệt lớn nhất giữa câu lệnh ở Kịch bản B (Active) và Kịch bản C (Backup-based) là gì?**
- **Trả lời:** Kịch bản B sử dụng cú pháp `FROM ACTIVE DATABASE` (kéo data trực tiếp qua mạng). Kịch bản C KHÔNG kết nối vào mạng gốc, thay vào đó sử dụng `BACKUP LOCATION '/thư_mục/'` để RMAN tự moi móc các file backup nội bộ trên máy đó.

**Câu 5: Trong Kịch bản D (PDB Duplication), database đích sinh ra (oradb2) sẽ là Non-CDB hay CDB?**
- **Trả lời:** Nó vẫn sẽ là một CDB. RMAN sẽ tự động tạo Root container (CDB$ROOT), Seed container (PDB$SEED) và gắn cái PDB được chỉ định (PDB1) vào đó.


---

!!! info "Nguồn gốc"
    `Oracle-Database-Administration-from-Zero-to-Hero/VN/93-thuc-hanh-nhan-ban-database.md`
