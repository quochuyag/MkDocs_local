---
title: '📘 Module 14: Oracle 19c RAC'
course: 04-rac-administration
source: The-Oracle-Database-RAC-Administration-Course/modules/module_14/module_14_guide.md
---

# 📘 Module 14: Oracle 19c RAC

> **Section**: 14/14
> **Khóa học**: Oracle Database RAC Administration Course (Ahmed Baraka)
> **Thời gian học ước tính**: 3-4 giờ

---

## 📋 Bài học trong Module

| #   | Bài học                                                     | File nguồn                        | Loại        |
| --- | ----------------------------------------------------------- | --------------------------------- | ----------- |
| 1   | Practice 19-a: Preparing the Environment for Oracle 19c RAC | `Section 14/Practice 19-a ...pdf` | 🔧 Thực hành |
| 2   | Practice 19-b: Creating an Oracle 19c RAC Database          | `Section 14/Practice 19-b ...pdf` | 🔧 Thực hành |

> ℹ️ Section 14 gồm **2 practice** (không có bài lý thuyết riêng). Đây là bản cập nhật quy trình cài đặt sang **Oracle 19c trên Oracle Linux 7.8**.

---

## 🎯 Mục tiêu Module

- Dựng lab 2 node cho **Oracle 19c RAC** trên **Oracle Linux 7.8**.
- Cài **Grid Infrastructure 19c** (dùng **Flex ASM**), tạo diskgroup, cài **Database 19c** và tạo **RAC CDB**.
- Nắm các **điểm khác** so với lab 12c ở Module 03.

---

## 📋 Nội dung chính

### Practice 19-a — Chuẩn bị môi trường

> 📄 Nguồn: `Section 14/Practice 19-a Preparing the Environment for Oracle 19c RAC.pdf`

Kiến trúc lab **giống Module 03** (2 node `srv1/srv2`, cùng dải IP public/priv/VIP/SCAN, 3 shared disk), nhưng nền tảng mới:

| Hạng mục       | 12c (Module 03)       | **19c (Module 14)**             |
| -------------- | --------------------- | ------------------------------- |
| OS             | Oracle Linux **6.10** | Oracle Linux **7.8**            |
| RAM tối thiểu  | 4 GB                  | **8 GB**                        |
| VirtualBox     | 6.1.x                 | **6.0.22+**                     |
| Phần mềm       | 12.1.0.2              | **19.3 (GI + DB), tải bản zip** |
| Interface mạng | eth0/eth1/eth2        | **enp0s3 / enp0s8 / enp0s9**    |
| Time sync      | disable NTP           | disable **chronyd**             |

**Điểm khác chính khi chuẩn bị OS (Linux 7):**

```bash
# users/groups (thêm groupadd oinstall)
groupadd asmadmin; groupadd asmdba; groupadd oinstall
useradd -u 54323 -g oinstall -G asmadmin,asmdba grid
usermod -a -G asmdba oracle; usermod -g oinstall oracle
usermod -a -G vboxsf oracle; usermod -a -G vboxsf grid

# gói preinstall MỚI cho 19c (tự set kernel params)
yum install oracle-database-preinstall-19c
sysctl -p

# ASMLib như cũ
yum install oracleasm-support kmod-oracleasm
oracleasm configure -i        # grid / oinstall / boot y / scan y
/usr/sbin/oracleasm init

# thư mục GI 19c
mkdir -p /u01/app/19.0.0/grid ; chown -R grid:oinstall /u01/app/19.0.0/grid
```

Clone `srv2` từ `srv1`, kích hoạt lại NIC bằng **`nmcli device status`** + đổi hostname bằng **`hostnamectl set-hostname srv2.localdomain`** (Linux 7). Shared disk **giống 12c**: DISK1(10GB/OCR), DISK2(15GB/DATA), DISK3(15GB/FRA), Shareable, `fdisk` + `oracleasm createdisk`.

### Practice 19-b — Tạo Oracle 19c RAC Database

> 📄 Nguồn: `Section 14/Practice 19-b Creating an Oracle 19c RAC Database.pdf`

**1. Biến môi trường** (ORACLE_HOME dùng `19.0.0`):

```bash
# oracle
ORACLE_HOME=$ORACLE_BASE/product/19.0.0/db_1     # SID rac1/rac2
# grid
ORACLE_HOME=/u01/app/19.0.0/grid                 # SID +ASM1/+ASM2
```

Resource limits trong `/etc/security/limits.conf` (thêm `data unlimited`).

**2. Prerequisite Linux 7 (khác 12c):**

```bash
systemctl disable --now avahi-daemon.socket avahi-daemon.service   # phải tắt
systemctl disable chronyd ; mv /etc/chrony.conf /etc/chrony.conf.bak
```

**3. Cài GI 19c** — **giải nén image trực tiếp vào Grid Home** rồi chạy `gridSetup.sh` (image-based, khác `runInstaller` của 12c):

```bash
su - grid
unzip /media/sf_staging/LINUX.X64_193000_grid_home.zip -d $ORACLE_HOME
# cài cvuqdisk trên cả 2 node (bắt buộc)
cd $ORACLE_HOME ; ./gridSetup.sh
```

Lựa chọn OUI đáng chú ý (khác 12c):

| Màn hình      | 19c                                                                 |
| ------------- | ------------------------------------------------------------------- |
| Configuration | **Configure Oracle Grid Infrastructure for a New Cluster**          |
| Cluster type  | **Configure an Oracle Standalone Cluster**                          |
| Network       | enp0s3 = Public, **enp0s8 = ASM & Private**, enp0s9 = Do Not Use    |
| Storage       | **Use Oracle Flex ASM for Storage**                                 |
| GIMR          | Create Grid Infrastructure Management Repository = **No**           |
| Disk group    | `OCRDISK`, External, chọn `OCRDISK1`, path `/dev/oracleasm/disks/*` |

Kiểm tra: `crsctl status resource -t`, `crsctl check cluster -all`. Tạo **DATA** và **FRA** bằng `asmca`.

**4. Cài Database 19c** — cũng **image-based**: `unzip ... db_home.zip -d $ORACLE_HOME` rồi `./runInstaller` → chọn **Set up Software Only** + **RAC installation** + EE, Software `/u01/app/oracle/product/19.0.0/db_1`.

**5. Tạo database bằng DBCA** — mặc định **là CDB** (khác lab 12c non-CDB):

| Màn hình       | 19c                                                                                                       |
| -------------- | --------------------------------------------------------------------------------------------------------- |
| Database Type  | RAC, **Admin Managed**                                                                                    |
| Identification | Global `rac.localdomain`, SID `rac`, **Create as Container DB = ✔**, **Local Undo = ✔**, **1 PDB `pdb1`** |
| Storage        | `+DATA/{DB_UNIQUE_NAME}`, FRA `+FRA` 12GB                                                                 |
| Memory         | ASMM (SGA ~3248MB, PGA ~1083MB)                                                                           |
| Management     | Configure **EM Database Express**                                                                         |

**6. Kiểm tra:**

```bash
srvctl status database -d rac ; srvctl config database -d rac
sqlplus / as sysdba
  SELECT INST_NUMBER, INST_NAME FROM V$ACTIVE_INSTANCES;
  ALTER SESSION SET CONTAINER=pdb1;
  SELECT COUNT(*) FROM HR.EMPLOYEES;
```

> ⚠️ **EM Express 19c** báo "Secure Connection Failed" vì listener chạy bằng `grid` không có quyền ghi XDB wallet. Sửa trên **cả 2 node** (root):
> ```bash
> setfacl -R -m u:grid:rwx /u01/app/oracle/product/19.0.0/db_1/admin/rac/xdb_wallet
> ```

---

## 🧠 Tóm tắt để nhớ lâu

- 19c lab: **Oracle Linux 7.8**, RAM **8 GB**, dùng **`oracle-database-preinstall-19c`**, tắt **avahi-daemon** & **chronyd**, NIC **enp0sX**, hostname bằng **`hostnamectl`**.
- Cài **image-based**: giải nén zip **thẳng vào home** rồi `gridSetup.sh` / `runInstaller` (khác `runInstaller` truyền thống của 12c).
- GI 19c dùng **Flex ASM**; có thể chọn **không** tạo GIMR.
- DBCA 19c mặc định tạo **CDB + PDB + Local Undo**.
- Fix EM Express bằng **`setfacl`** cấp quyền XDB wallet cho `grid`.
- Kiến trúc RAC, `srvctl`/`crsctl`, kiểm tra `V$ACTIVE_INSTANCES` **vẫn như 12c** — nền tảng thay đổi, nguyên lý không đổi.

---

## 🛠️ Sau khi học xong, hãy tự làm

1. Lập bảng khác biệt lab 12c (Module 03) vs 19c (Module 14).
2. Dựng lab 19c 2 node và tạo RAC CDB `rac` + `pdb1`.
3. Xác minh bằng `srvctl status database` và `V$ACTIVE_INSTANCES`; kết nối vào `pdb1`.
4. Khắc phục lỗi EM Express bằng `setfacl` và mở EM Express thành công.

---

## 🎓 Kết thúc khóa học

Bạn đã đi hết 14 module: từ tổng quan/kiến trúc RAC, cài đặt, quản trị, backup/recovery, global resource & tuning, services/HA (LB/TAF/AC), patch/upgrade, RAC One Node, Multitenant, Policy-Managed, Flex Clusters, add/delete node, Data Guard, đến Oracle 19c. Bước tiếp theo (Oracle Maximum Availability): **Data Guard nâng cao, GoldenGate, Multitenant, ASM, Database Cloud**.


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-RAC-Administration-Course/modules/module_14/module_14_guide.md`
