---
title: 'Giai đoạn 2 — Kế hoạch chi tiết: Môi trường thực hành với Vagrant'
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/ke_hoach/02_phase2_environment_vagrant_plan.md
---

# Giai đoạn 2 — Kế hoạch chi tiết: Môi trường thực hành với Vagrant

> Tạo ngày: 2026-07-13 · Thuộc [01_learning_plan.md](001-learning-plan.md) Giai đoạn 2
> Mục tiêu: dựng VM Oracle Database bằng Vagrant — tự động, tái tạo được, snapshot/rollback bằng lệnh — thay cho quy trình VirtualBox thủ công 25 bước của Practice 1 gốc.

---

## 1. Vì sao dùng Vagrant thay vì làm theo Practice 1 gốc?

Practice 1 gốc (viết ~2017) yêu cầu: Oracle Linux **6.10** (EOL từ 2021) + Oracle **12.2** (hết support), cài tay qua GUI VirtualBox ~25 bước, mất 3–5 giờ và dễ sai.

| Tiêu chí | Practice 1 gốc | Vagrant (kế hoạch này) |
|---|---|---|
| OS | Oracle Linux 6.10 (EOL) | Oracle Linux 8 (supported) |
| Database | 12.2 (hết support) | **19c EE** (LTS, gần course nhất) |
| Cách dựng | Thủ công 25 bước GUI | `vagrant up` — 1 lệnh, ~30–45 phút |
| Làm lại từ đầu | Cài lại 3–5 giờ | `vagrant destroy && vagrant up` |
| Snapshot | GUI VirtualBox từng bước | `vagrant snapshot save/restore <tên>` |
| Trao đổi file host↔VM | Shared folder cấu hình tay (`sf_extdisk`) | `/vagrant` tự động mount |
| Tái lập trên máy khác | Không | Copy Vagrantfile là xong |

**Lưu ý tương thích nội dung khóa học:** 99% view/công cụ trong course (AWR, ASH, ADDM, V$*, DBMS_MONITOR…) hoạt động y hệt trên 19c. Khác biệt nhỏ sẽ ghi chú trong từng lab (ví dụ: 19c mặc định là CDB/PDB thay vì non-CDB).

---

## 2. Kiến trúc môi trường đích

```
┌─ Hosting PC (Windows 11) ──────────────────────────────────┐
│  VirtualBox 7.x + Vagrant 2.4.x                            │
│  Swingbench 2.5 (GUI sinh workload)  + Java JRE 8          │
│  SQLcl / SQL*Plus (client kết nối từ host)                 │
│  VS Code + Claude Code (thư mục dự án này)                 │
│                                                            │
│  ┌─ VM "srv1" (Vagrant) ────────────────────────────────┐  │
│  │  Oracle Linux 8 · 6 GB RAM · 2 vCPU · ~60 GB disk    │  │
│  │  Oracle Database 19c EE                              │  │
│  │  CDB: ORCLCDB  →  PDB: ORADB  (giữ tên như course)   │  │
│  │  Schema: SOE (Order Entry, import từ soe.dmp)        │  │
│  │  stress-ng (giả lập tải CPU/memory/IO cho Section 25/34) │
│  │  Port forward: 1521 (listener), 5500 (EM Express)    │  │
│  │  /vagrant  ←→  thư mục chứa Vagrantfile trên host    │  │
│  └──────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────┘
```

Quy đổi so với course: `srv1` giữ nguyên vai trò; `ORADB` giờ là **PDB** trong CDB `ORCLCDB`; thư mục staging `sf_extdisk` thay bằng `/vagrant`.

---

## 3. Yêu cầu trước khi bắt đầu (host)

| Hạng mục | Yêu cầu | Kiểm tra |
|---|---|---|
| RAM host | ≥ 16 GB (VM chiếm 6 GB) | Task Manager → Performance |
| Disk trống | ≥ 80 GB (VM ~60 GB + staging ~5 GB) | `Get-PSDrive D` |
| CPU | Bật VT-x/AMD-V trong BIOS | Task Manager → CPU → Virtualization: Enabled |
| Hyper-V xung đột | VirtualBox 7 chạy được cùng Hyper-V nhưng **chậm rõ rệt**. Nếu VM ì ạch: tắt `Hyper-V`, `Virtual Machine Platform`, `Windows Hypervisor Platform` trong Windows Features rồi reboot | `systeminfo` → dòng "A hypervisor has been detected" nghĩa là Hyper-V đang bật |
| Tài khoản Oracle (miễn phí) | Để tải file cài 19c từ oracle.com | — |

**Phần mềm cần cài trên host:**

1. **VirtualBox 7.x** — https://www.virtualbox.org/wiki/Downloads
2. **Vagrant 2.4.x** — https://developer.hashicorp.com/vagrant/downloads (bản Windows AMD64; cài xong mở terminal mới, kiểm tra `vagrant --version`)
3. **Git for Windows** (đã có — dự án này là git repo)
4. **Java JRE 8 (x64)** — chỉ để chạy Swingbench 2.5 GUI trên host
5. **SQLcl** (khuyến nghị, thay Oracle Client 12.1 của course) — https://www.oracle.com/sqlcl — chỉ cần Java, không cần cài Oracle Client đầy đủ

---

## 4. Các bước thực hiện chi tiết

### Bước A — Giải nén và kiểm kê tài nguyên Section 2 (~15 phút)

File `Section 2/Practice+1+-+Attached+Files.zip` (110 MB) chứa đồ nghề của course. **Lưu ý:** các file .zip nhỏ (~130 bytes) đang thấy trong thư mục `Practice+1+-+Attached+Files/` chỉ là placeholder/link — phải giải nén file zip 110 MB mới có file thật.

```powershell
# Từ thư mục gốc dự án
Expand-Archive "Section 2\Practice+1+-+Attached+Files.zip" -DestinationPath "D:\staging\section2_files"
```

Kiểm kê sau giải nén — kỳ vọng có:

| File | Dùng cho | Ghi chú |
|---|---|---|
| `create_soe.sql` (trong create_soe.zip) | Tạo tablespace SOETBS + user SOE | Chạy trong PDB ORADB |
| `soe.dmp` (trong soedump.zip, ~330 MB sau giải nén) | Import schema SOE | Password giải nén: `Ahmed@Baraka`; dump 12.2 import lên 19c OK (upward compatible) |
| `swingbench25971.zip` | Swingbench 2.5.971 | Cài trên host |
| `stress-1.0.4-6.1.x86_64.zip` | ~~Cài trong VM~~ | **BỎ** — rpm này cho OL6; OL8 dùng `dnf install stress-ng` |
| `tnsnames.zip` | Mẫu tnsnames.ora | Tham khảo, sẽ tự viết cho localhost:1521 |

### Bước B — Dựng VM Oracle 19c bằng Vagrant (~45 phút, đa số là chờ)

Dùng repo chính thức của Oracle: **oracle/vagrant-projects** — đã tự động hóa toàn bộ phần cài đặt (tương đương các mục E→H của Practice 1).

```powershell
# 1. Clone repo vagrant-projects của Oracle (ra ngoài thư mục dự án học)
cd D:\Dba_project
git clone https://github.com/oracle/vagrant-projects.git
cd vagrant-projects\OracleDatabase\19.3.0

# 2. Tải file cài Oracle 19c (cần login tài khoản Oracle miễn phí):
#    https://www.oracle.com/database/technologies/oracle19c-linux-downloads.html
#    → LINUX.X64_193000_db_home.zip (~3 GB)
#    Đặt file vào đúng thư mục hiện tại (cạnh Vagrantfile)

# 3. Cấu hình VM: sửa file Vagrantfile (hoặc tạo .env.yml nếu repo hỗ trợ)
#    Các giá trị cần đặt:
#      VM_MEMORY / memory       : 6144        (6 GB — course dùng 4 GB, 19c cần nhiều hơn)
#      VM_CPUS                  : 2
#      VM_ORACLE_PDB / pdb_name : ORADB       (giữ tên database như course!)
#      VM_ORACLE_CHARACTERSET   : AL32UTF8    (khớp course)
#      VM_ORACLE_PWD            : oracle_4U   (hoặc tự đặt — ghi nhớ)
#      VM_ORACLE_EDITION        : EE          (Enterprise Edition — cần cho AWR/ADDM/ASH*)

# 4. Dựng VM — chờ ~30-45 phút (cài OS + Oracle + tạo DB tự động)
vagrant up

# 5. Xong khi thấy dòng: "INSTALLER: Installation complete, database ready to use!"
```

> (*) AWR/ASH/ADDM/SQL Monitor cần **Diagnostics & Tuning Pack** — trên môi trường học/lab cá nhân dùng được (OTN developer license), nhưng đừng dùng thói quen này trên production chưa mua license. Đặt `CONTROL_MANAGEMENT_PACK_ACCESS=DIAGNOSTIC+TUNING` (mặc định EE đã đúng).

**Xác minh:**

```powershell
vagrant ssh                          # SSH vào VM, không cần Putty như course
```

```bash
# Trong VM:
sudo su - oracle
sqlplus / as sysdba
```

```sql
SELECT name, open_mode FROM v$pdbs;          -- ORADB phải READ WRITE
SELECT banner_full FROM v$version;           -- 19.x
SHOW PARAMETER control_management_pack_access;
```

### Bước C — Cấu hình kết nối từ host (~10 phút)

Vagrant đã tự port-forward 1521 → localhost. Không cần IP tĩnh/bridged như course.

```powershell
# Test bằng SQLcl từ host:
sql system/oracle_4U@//localhost:1521/ORADB
```

Tạo alias trong tnsnames.ora của host (nếu dùng SQL*Plus/Swingbench cần TNS):

```
ORADB =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = localhost)(PORT = 1521))
    (CONNECT_DATA = (SERVER = DEDICATED)(SERVICE_NAME = ORADB))
  )
```

EM Express (thay DB Console của course): https://localhost:5500/em

### Bước D — Setup SOE schema (~20 phút)

Tương đương mục "Set up Order Entry Schema" của Practice 1, điều chỉnh cho PDB:

```powershell
# 1. Copy file vào thư mục chứa Vagrantfile → VM thấy ngay tại /vagrant
Copy-Item D:\staging\section2_files\create_soe.sql D:\Dba_project\vagrant-projects\OracleDatabase\19.3.0\
Copy-Item D:\staging\section2_files\soe.dmp        D:\Dba_project\vagrant-projects\OracleDatabase\19.3.0\
```

```bash
# 2. Trong VM (vagrant ssh → sudo su - oracle):
sqlplus / as sysdba
```

```sql
ALTER SESSION SET CONTAINER = ORADB;    -- ⚠️ khác course: phải vào PDB trước
@/vagrant/create_soe.sql                 -- tạo SOETBS + user SOE
-- Tạo directory object trỏ tới /vagrant để impdp đọc dump:
CREATE OR REPLACE DIRECTORY stage_dir AS '/vagrant';
GRANT READ, WRITE ON DIRECTORY stage_dir TO soe;
EXIT
```

```bash
# 3. Import (chú ý service ORADB — impdp phải chạy vào PDB):
impdp soe/soe@//localhost:1521/ORADB directory=STAGE_DIR dumpfile=soe.dmp logfile=soe_imp.log
```

```sql
-- 4. Xác minh: 49 objects, ~330 MB
CONNECT soe/soe@//localhost:1521/ORADB
SELECT COUNT(*), ROUND(SUM(bytes/1024/1024)) mb FROM user_segments;
```

```bash
# 5. Dọn: xóa soe.dmp khỏi /vagrant sau khi import thành công
rm /vagrant/soe.dmp
```

### Bước E — Cài Swingbench 2.5 trên host (~15 phút)

Giữ nguyên cách course (Swingbench 2.5 ổn định hơn 2.6 theo tác giả):

1. Giải nén `swingbench25971.zip` → `D:\swingbench`
2. Cần Java 8: `set PATH=<đường dẫn JRE8>\bin;%PATH%` rồi chạy `D:\swingbench\winbin\swingbench.bat`
3. User Details: connect string `//localhost:1521/ORADB`, user `soe/soe`
4. **KHÔNG chạy Order Entry Wizard** (schema đã import ở bước D)
5. Test Connection → Load: 10 users → Start Benchmark → thấy Transactions Per Minute tăng là đạt
6. Tạo và lưu 2 file cấu hình như course: `oltp.xml` (ratio nghiêng OLTP) và `warehouse.xml` (ratio nghiêng warehouse) — các practice sau dùng lại 2 file này
7. Lưu thêm bản copy 2 file xml vào `labs/_workload/` trong dự án để không mất

> Phương án B (headless, không GUI): dùng `charbench.bat -c oltp.xml -u soe -p soe -cs //localhost:1521/ORADB -uc 10 -rt 0:10` — hữu ích khi muốn sinh tải từ script trong lab.

### Bước F — Cài stress-ng trong VM (~5 phút)

Thay cho stress RPM cũ của OL6 (mục "Installing stress RPM" trong Practice 1):

```bash
# Trong VM, user vagrant:
sudo dnf install -y stress-ng
# Test: chiếm 2 CPU trong 10 giây
stress-ng --cpu 2 --timeout 10s
```

Dùng cho Section 25 (CPU bottleneck) và Section 34 (OS performance). Cũng cài luôn công cụ quan sát OS cho Section 34:

```bash
sudo dnf install -y sysstat htop iotop
sudo systemctl enable --now sysstat     # thu thập sar data
```

### Bước G — Snapshot baseline & quy trình hằng ngày (~5 phút)

Thay cho snapshot GUI VirtualBox (mục cuối Practice 1):

```powershell
# Chụp trạng thái sạch ngay sau khi setup xong:
vagrant snapshot save baseline

# Quy trình mỗi buổi học:
vagrant up                         # bật VM (DB tự khởi động — systemd đã config sẵn)
# ... học + chạy lab ...
vagrant halt                       # tắt VM cuối buổi

# Khi lab làm hỏng môi trường:
vagrant snapshot restore baseline  # quay về trạng thái sạch trong ~1 phút

# Trước lab nguy hiểm (thay đổi tham số instance, resize memory...):
vagrant snapshot save truoc_lab_X
vagrant snapshot delete truoc_lab_X   # nhớ xóa sau khi xong — snapshot ăn disk!
```

### Bước H — Script kiểm tra môi trường + tài liệu hóa (~30 phút)

1. Viết `labs/_toolkit/00_env_check.sql` — chạy 1 lệnh xác nhận tất cả sẵn sàng:
   - Version 19c, PDB ORADB open READ WRITE
   - SOE schema tồn tại, 49 objects, ~330 MB
   - `control_management_pack_access = DIAGNOSTIC+TUNING`
   - AWR snapshot interval (mặc định 60 phút — lab sẽ chỉnh)
   - SGA/PGA hiện tại
2. Viết guide còn thiếu: `section_all/section_2_preparing_environment_guide.md` — nội dung chính là file kế hoạch này cô đọng lại + đối chiếu với Practice 1 gốc
3. Cập nhật `01_learning_plan.md` (bảng tiến độ Giai đoạn 2) và `progress.md` cuối buổi

---

## 5. Checklist hoàn thành Giai đoạn 2

| # | Hạng mục | Lệnh xác minh | Trạng thái |
|---|---|---|---|
| A | Giải nén Attached Files, đủ 4 file thật | `ls D:\staging\section2_files` | ⬜ |
| B1 | VirtualBox + Vagrant cài xong | `vagrant --version` | ⬜ |
| B2 | VM 19c dựng xong, PDB ORADB mở | `SELECT open_mode FROM v$pdbs` | ⬜ |
| C | Kết nối từ host OK | `sql system@//localhost:1521/ORADB` | ⬜ |
| D | SOE schema: 49 objects ~330 MB | `SELECT COUNT(*) FROM user_segments` | ⬜ |
| E | Swingbench chạy benchmark 10 users OK; có oltp.xml + warehouse.xml | GUI: TPM tăng | ⬜ |
| F | stress-ng + sysstat trong VM | `stress-ng --version` | ⬜ |
| G | Snapshot `baseline` đã lưu | `vagrant snapshot list` | ⬜ |
| H | `00_env_check.sql` + guide Section 2 | file tồn tại, chạy sạch | ⬜ |

**Tổng thời gian ước tính: ~2.5–3 giờ** (so với 3–5 giờ+ nếu làm tay theo Practice 1 gốc, và những lần dựng lại sau chỉ mất ~45 phút).

---

## 6. Rủi ro & cách xử lý

| Rủi ro | Triệu chứng | Xử lý |
|---|---|---|
| Hyper-V xung đột VirtualBox | VM cực chậm, hoặc lỗi `VERR_VMX_IN_VMX_ROOT_MODE` | Tắt Hyper-V/WSL2/Memory Integrity trong Windows Features + `bcdedit /set hypervisorlaunchtype off`, reboot |
| Thiếu RAM host | Host đơ khi VM chạy + Swingbench | Giảm VM xuống 4096 MB (SGA course chỉ cần 1652 MB) |
| Zip 110 MB thiếu file/hỏng | Giải nén không đủ 4 file | Tải lại từ resources của khóa học trên Packt/Udemy, hoặc SOE tạo mới bằng oewizard của Swingbench (chậm hơn nhưng không cần dump) |
| Dump 12.2 import lỗi trên 19c | ORA- khi impdp | Dump cũ import lên bản mới là supported; nếu lỗi ORA-39142 → kiểm tra đã import vào PDB (không phải CDB root) |
| Port 1521 bị chiếm trên host | `vagrant up` báo port collision | Sửa forwarded_port trong Vagrantfile sang 15210, connect string đổi theo |
| Quên xóa snapshot | Ổ đĩa đầy dần | Định kỳ `vagrant snapshot list` và xóa snapshot không dùng |

---

## 7. Việc KHÔNG cần làm nữa (so với Practice 1 gốc)

Vagrant/19c đã thay thế các mục sau — đọc để hiểu, không cần thực hiện:

- ❌ Tải appliance OL6.10 dựng sẵn / cài OS thủ công (mục B) → box OL8 tự tải
- ❌ Cấu hình Bridged Adapter, IP tĩnh, /etc/hosts, firewall GUI (mục B.5–12) → port forwarding tự động
- ❌ Putty + KeepAlive (mục C) → `vagrant ssh`
- ❌ Shared folder `sf_extdisk` + usermod vboxsf (mục D) → `/vagrant` tự mount
- ❌ Cài Oracle bằng runInstaller GUI + netca + dbca GUI (mục E–G) → script provision tự làm
- ❌ Script init.d dbora tự khởi động DB (mục H) → systemd service có sẵn trong box
- ❌ Cài Oracle Database Client 12.1 đầy đủ trên host → SQLcl gọn nhẹ
- ❌ stress RPM cho OL6 → `dnf install stress-ng`

---

## 8. Sau khi xong Giai đoạn 2

→ Quay lại [01_learning_plan.md](001-learning-plan.md): Giai đoạn 1 lab mẫu Section 28 giờ có môi trường để **chạy thật**, và mọi `02_workload.sql` về sau có thể kết hợp Swingbench (`charbench`) để sinh tải nền giống production.


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/ke_hoach/02_phase2_environment_vagrant_plan.md`
