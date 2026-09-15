---
title: Nhật ký thực hiện Giai đoạn 2 — Dựng môi trường Vagrant (step-by-step)
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/ke_hoach/03_phase2_setup_log.md
---

# Nhật ký thực hiện Giai đoạn 2 — Dựng môi trường Vagrant (step-by-step)

> Ghi ngày: 2026-07-13 · Thực hiện theo [02_phase2_environment_vagrant_plan.md](002-phase2-environment-vagrant-plan.md)
> Mục đích: ghi lại **chính xác các lệnh đã chạy** để tái lập môi trường trên máy khác hoặc dựng lại từ đầu.

---

## Bước 0 — Chuẩn bị (đã làm thủ công trước đó)

```powershell
# 0.1. Cài VirtualBox 7.0.20 + Vagrant 2.4.9 (installer từ trang chủ)
# Kiểm tra:
vagrant --version                                        # → Vagrant 2.4.9
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" --version   # → 7.0.20r163906

# 0.2. Clone repo vagrant-projects chính thức của Oracle
cd D:\Dba_project
git clone https://github.com/oracle/vagrant-projects.git

# 0.3. Tải file cài Oracle 19c (login tài khoản Oracle miễn phí):
# https://www.oracle.com/database/technologies/oracle19c-linux-downloads.html
# → LINUX.X64_193000_db_home.zip (3,059,705,302 bytes)
# Đặt vào: D:\Dba_project\vagrant-projects\OracleDatabase\19.3.0\  (cạnh Vagrantfile)
```

---

## Bước 1 — Cấu hình VM: tạo `config.local.yaml`

Repo đọc cấu hình từ `config.yaml` (mặc định) và **`config.local.yaml`** (override, không bị ghi đè khi update repo — luôn sửa ở file này).

File đã tạo: `D:\Dba_project\vagrant-projects\OracleDatabase\19.3.0\config.local.yaml`

```yaml
---
VM_NAME: 'srv1'              # tên VM + hostname — giữ tên như course
VM_MEMORY: 6144              # 6 GB (course dùng 4 GB cho 12.2; 19c cần nhiều hơn)
VM_CPUS: 2                   # tham số tự thêm vào Vagrantfile (Bước 2)
VM_ORACLE_SID: 'ORCLCDB'     # CDB giữ mặc định
VM_ORACLE_PDB: 'ORADB'       # PDB tên ORADB — connect string giống course
VM_ORACLE_CHARACTERSET: 'AL32UTF8'
VM_ORACLE_EDITION: 'EE'      # Enterprise Edition — cần cho AWR/ADDM/ASH
VM_ORACLE_PWD: 'oracle_4U'   # password SYS/SYSTEM/PDBADMIN
VM_LISTENER_HOST_PORT: 15210 # xem Bước 4 — host đã có tnslsnr chiếm 1521
```

---

## Bước 2 — Sửa `Vagrantfile` (2 chỗ)

Vagrantfile gốc không hỗ trợ số CPU và không tách host-port/guest-port. Đã thêm:

**2.1. Tham số `VM_CPUS`** (sau khối `VM_MEMORY`):

```ruby
  # Number of CPUs for the VM
  VM_CPUS = default_i('VM_CPUS', 2)
```

**2.2. Tham số `VM_LISTENER_HOST_PORT`** (sau khối `VM_LISTENER_PORT`):

```ruby
  # Host port forwarded to the guest listener (change when 1521 is taken on the host)
  VM_LISTENER_HOST_PORT = default_i('VM_LISTENER_HOST_PORT', VM_LISTENER_PORT)
```

**2.3. Áp dụng vào provider config:**

```ruby
  config.vm.provider "virtualbox" do |v|
    v.memory = VM_MEMORY
    v.cpus = VM_CPUS          # ← thêm
    v.name = VM_NAME
  end
```

**2.4. Sửa dòng port forwarding:**

```ruby
  # Trước:
  config.vm.network "forwarded_port", guest: VM_LISTENER_PORT, host: VM_LISTENER_PORT
  # Sau:
  config.vm.network "forwarded_port", guest: VM_LISTENER_PORT, host: VM_LISTENER_HOST_PORT
```

---

## Bước 3 — Validate và chạy lần 1

```powershell
cd D:\Dba_project\vagrant-projects\OracleDatabase\19.3.0
vagrant validate        # → Vagrantfile validated successfully.
vagrant status          # → srv1: not created (virtualbox)
vagrant up 2>&1 | Tee-Object -FilePath vagrant_up.log
```

**Kết quả lần 1: THẤT BẠI** ❌ — nhưng có tiến triển:

- ✅ Tải box `oraclelinux/7` v7.9.653 (~1.4 GB) từ yum.oracle.com thành công
- ✅ Import VM `srv1` thành công
- ❌ Lỗi: `The forwarded port to 1521 is already in use on the host machine.`

---

## Bước 4 — Chẩn đoán và xử lý xung đột port 1521

```powershell
# Tìm tiến trình chiếm port 1521 trên host:
Get-NetTCPConnection -LocalPort 1521 -State Listen |
  ForEach-Object { Get-Process -Id $_.OwningProcess }
# → Kết quả: tnslsnr (PID 7444) — Oracle listener CÀI LOCAL trên Windows
```

**Quyết định:** KHÔNG tắt listener local (tránh ảnh hưởng DB local đang có) → đổi host port forward sang **15210**:

- Thêm `VM_LISTENER_HOST_PORT` vào Vagrantfile (đã ghi ở Bước 2.2, 2.4)
- Thêm `VM_LISTENER_HOST_PORT: 15210` vào `config.local.yaml` (Bước 1)

**Hệ quả cho mọi bước sau:** từ host kết nối bằng `//localhost:15210/ORADB` (KHÔNG phải 1521). Bên trong VM vẫn là 1521 chuẩn.

---

## Bước 5 — Chạy lần 2 (thành công / đang chạy)

```powershell
cd D:\Dba_project\vagrant-projects\OracleDatabase\19.3.0
vagrant validate
vagrant up 2>&1 | Tee-Object -FilePath vagrant_up.log
```

Tiến trình provision tự động — **HOÀN TẤT** ✅ (2026-07-13):

1. ✅ Boot VM srv1 (OL7.9, 6 GB RAM, 2 vCPU), port-forward 15210→1521, 5500→5500
2. ✅ Giải nén `LINUX.X64_193000_db_home.zip` vào `/opt/oracle/product/19c/dbhome_1`
3. ✅ Cài Oracle 19c EE (runInstaller silent) — `INSTALLER: Oracle software installed`
4. ✅ Tạo listener + CDB `ORCLCDB` + PDB `ORADB` — `INSTALLER: Database created`
5. ✅ `INSTALLER: Installation complete, database ready to use!`

---

## Bước 6 — Xác minh sau provision ✅ ĐÃ CHẠY (2026-07-13)

**6.1. Script kiểm tra trong VM** — tạo `verify_db.sql` trong thư mục project (VM thấy tại `/vagrant/verify_db.sql`), chạy:

```powershell
cd D:\Dba_project\vagrant-projects\OracleDatabase\19.3.0
vagrant ssh -c "sudo -u oracle -i bash -c 'sqlplus -S / as sysdba @/vagrant/verify_db.sql'"
```

Kết quả thực tế:

| Kiểm tra | Kết quả |
| --- | --- |
| Version | Oracle Database 19c EE 19.3.0.0.0 ✅ |
| PDB ORADB | **READ WRITE**, không restricted ✅ |
| control_management_pack_access | **DIAGNOSTIC+TUNING** ✅ |
| SGA / PGA | 1152 MB / 384 MB (dbca tự tính — thấp hơn course 1652/552; sẽ chỉnh trong lab memory tuning nếu cần) |
| `ALTER SESSION SET CONTAINER=ORADB` | OK ✅ |

**6.2. Test kết nối từ host qua port 15210:**

```powershell
sqlplus -S -L system/oracle_4U@//localhost:15210/ORADB
-- SELECT sys_context('USERENV','CON_NAME') FROM dual;  → ORADB ✅
```

(Warning IPv6 `::1` khi Test-NetConnection là vô hại — listener bind IPv4.)

**6.3. Snapshot bảo hiểm sau cài sạch (trước khi import SOE):**

```powershell
vagrant snapshot save fresh-install   # ✅ đã lưu
vagrant snapshot list                 # → fresh-install
```

---

## Bước 7 — Giải nén tài nguyên Section 2 ✅ ĐÃ CHẠY (2026-07-13)

```powershell
# 7.1. Giải nén archive chính (110 MB):
New-Item -ItemType Directory -Force "D:\staging\section2_files"
Expand-Archive "Section 2\Practice+1+-+Attached+Files.zip" -DestinationPath "D:\staging\section2_files"

# 7.2. Giải nén các zip con:
Expand-Archive "D:\staging\section2_files\create_soe.zip" -DestinationPath "D:\staging\section2_files"
Expand-Archive "D:\staging\section2_files\tnsnames.zip"   -DestinationPath "D:\staging\section2_files"

# 7.3. soedump.zip mã hóa AES → Expand-Archive THẤT BẠI ("unsupported compression method")
#      → dùng 7-Zip với password từ PDF:
& "C:\Program Files\7-Zip\7z.exe" x "D:\staging\section2_files\soedump.zip" `
    "-oD:\staging\section2_files" "-pAhmed@Baraka" -y
# → soe.dmp: 338,636,800 bytes (~330 MB, khớp PDF)

# 7.4. Giải nén Swingbench ra D:\ :
Expand-Archive "D:\staging\section2_files\swingbench25971.zip" -DestinationPath "D:\"
# → D:\swingbench (bin, winbin, configs, ...)
```

---

## Bước 8 — Import SOE schema vào PDB ORADB ✅ ĐÃ CHẠY (2026-07-13)

**8.1. Điều chỉnh script gốc cho 19c** — tạo `create_soe_19c.sql` (đặt trong thư mục Vagrant project). Khác bản gốc 4 điểm:

1. Thêm `ALTER SESSION SET CONTAINER = ORADB` (19c là CDB, SOE nằm trong PDB)
2. `@?/sqlplus/admin/plustrce.sql` thay vì đường dẫn home 12.2 cứng
3. Tablespace SOETBS có datafile tường minh `/opt/oracle/oradata/ORCLCDB/ORADB/soetbs01.dbf` (VM không bật OMF — đã kiểm tra `db_create_file_dest` rỗng)
4. Bỏ 2 grant trên `SYS.SYS_PLSQL_*` (object nội bộ DB 12.2 gốc, không tồn tại)

```powershell
# 8.2. Copy dump vào thư mục share + chạy script tạo user/tablespace:
Copy-Item "D:\staging\section2_files\soe.dmp" "D:\Dba_project\vagrant-projects\OracleDatabase\19.3.0\"
vagrant ssh -c "sudo -u oracle -i bash -c 'sqlplus -S / as sysdba @/vagrant/create_soe_19c.sql'"
# (3 lỗi đầu ORA-01918/00959/01919 là bình thường — DROP object chưa tồn tại)
```

**8.3. Import lần 1 — THẤT BẠI** ❌ vì Data Pump không đọc được dump trên vboxsf shared folder:

```text
ORA-27061: waiting for async I/Os failed
Linux-x86_64 Error: 95: Operation not supported
```

→ **Bài học: KHÔNG để impdp đọc dump trực tiếp từ /vagrant** (vboxsf không hỗ trợ async I/O).

```bash
# 8.4. Xử lý: copy dump vào đĩa local trong VM, trỏ lại directory:
cp /vagrant/soe.dmp /home/oracle/soe.dmp
# fix_stage_dir.sql: CREATE OR REPLACE DIRECTORY stage_dir AS '/home/oracle';

# 8.5. Import lần 2 — THÀNH CÔNG (42 giây):
impdp soe/soe@//localhost:1521/ORADB directory=STAGE_DIR dumpfile=soe.dmp logfile=soe_imp.log
# → ORDER_ITEMS 3,735,896 rows · ORDERS 1,352,070 rows · 16 tables
# → 1 cảnh báo ORA-39082: package body SOE.ORDERENTRY compile warning
```

```sql
-- 8.6. Xử lý cảnh báo + xác minh (check_soe.sql):
ALTER PACKAGE soe.orderentry COMPILE BODY;   -- → No errors.
-- Invalid objects: 0 ✅
-- Segments: 49 (khớp kỳ vọng PDF) · 958 MB (lớn hơn 330 MB của course
--   vì tablespace UNIFORM SIZE 1M — bình thường)
```

```powershell
# 8.7. Test từ host + dọn dump (bản gốc vẫn còn ở D:\staging\section2_files):
sqlplus soe/soe@//localhost:15210/ORADB   # → 16 tables ✅
# Xóa: /home/oracle/soe.dmp (trong VM) và soe.dmp trong thư mục Vagrant project
```

---

## Bước 9 — Cài công cụ OS trong VM ✅ ĐÃ CHẠY (2026-07-13)

```bash
sudo yum install -y stress-ng sysstat     # stress-ng 0.07.29; sysstat có sẵn trong box
sudo systemctl enable --now sysstat       # bật thu thập sar data (Section 34)
```

> Thay cho `stress-1.0.4-6.1.x86_64.rpm` của course (rpm đó build cho OL6).

---

## Bước 10 — Swingbench trên host ✅ HOÀN TẤT (2026-07-13, người dùng thao tác GUI)

Claude chuẩn bị: giải nén → `D:\swingbench`; Java trên PATH là Java 25 (không chạy được Swingbench 2.5) → dùng Java 1.8.0_291 bundle trong Oracle home local qua launcher **`D:\swingbench\start_swingbench.bat`**.

Người dùng thực hiện theo [04_huong_dan_swingbench.md](004-huong-dan-swingbench.md): kết nối `soe/soe@//localhost:15210/ORADB` OK, benchmark 10 users chạy được, đã lưu **`oltp.xml`** + **`warehouse.xml`** trong `D:\swingbench\winbin`.

## Bước 11 — Chốt Giai đoạn 2 ✅ HOÀN TẤT (2026-07-13)

```powershell
# 11.1. Backup workload configs vào dự án:
Copy-Item D:\swingbench\winbin\oltp.xml,D:\swingbench\winbin\warehouse.xml labs\_workload\

# 11.2. Snapshot môi trường hoàn chỉnh:
vagrant snapshot save baseline
# Snapshot hiện có: fresh-install (Oracle sạch) · baseline (đủ SOE + tools) · backup_1 (người dùng tự tạo)

# 11.3. Env check — chạy từ host, chú ý quote để PowerShell không hiểu nhầm @ là splatting:
sqlplus -S -L "system/oracle_4U@//localhost:15210/ORADB" "@labs\_toolkit\00_env_check.sql"
# → 8/8 PASS: 19c, ORADB READ WRITE, DIAGNOSTIC+TUNING, SOE 49 segments / 0 invalid / 3.7M rows
# Lỗi đã sửa khi viết script: v$version KHÔNG có cột VERSION (dùng v$instance);
# sga_target xem từ trong PDB trả về 0 (dùng SUM(v$sga))
```

Tạo guide Section 2 (file cuối cùng còn thiếu): `section_all/section_2_preparing_environment_guide.md` → **section_all đủ 29/29** ✅

## 🏁 GIAI ĐOẠN 2 HOÀN TẤT TOÀN BỘ (2026-07-13)

---

## Tóm tắt thông số môi trường (để tra cứu nhanh)

| Thông số | Giá trị |
| --- | --- |
| VM name / hostname | `srv1` |
| Thư mục Vagrant project | `D:\Dba_project\vagrant-projects\OracleDatabase\19.3.0` |
| OS | Oracle Linux 7.9 (box v7.9.653) |
| RAM / CPU | 6144 MB / 2 vCPU |
| Oracle | 19.3.0 Enterprise Edition |
| ORACLE_HOME | `/opt/oracle/product/19c/dbhome_1` |
| CDB / PDB | `ORCLCDB` / `ORADB` |
| Password SYS/SYSTEM/PDBADMIN | `oracle_4U` |
| Listener trong VM | 1521 |
| **Port từ host** | **15210** (vì tnslsnr local chiếm 1521) |
| EM Express | `https://localhost:5500/em` |
| Connect string từ host | `//localhost:15210/ORADB` |
| SSH vào VM | `vagrant ssh` (từ thư mục project) |
| Trao đổi file host↔VM | thư mục project ↔ `/vagrant` trong VM |

## Lệnh vận hành hằng ngày

```powershell
cd D:\Dba_project\vagrant-projects\OracleDatabase\19.3.0
vagrant up                          # bật VM đầu buổi học (DB tự start)
vagrant ssh                         # vào VM
vagrant halt                        # tắt VM cuối buổi
vagrant snapshot save <tên>         # chụp trạng thái trước lab nguy hiểm
vagrant snapshot restore baseline   # quay về trạng thái sạch
vagrant snapshot list               # liệt kê (nhớ xóa snapshot thừa — ăn disk)
vagrant destroy && vagrant up       # đập đi dựng lại toàn bộ (~45 phút)
```


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/ke_hoach/03_phase2_setup_log.md`
