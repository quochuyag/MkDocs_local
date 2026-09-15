---
title: '📘 Module 12: Deleting and Adding a Node from/to Oracle RAC'
course: 04-rac-administration
source: The-Oracle-Database-RAC-Administration-Course/modules/module_12/module_12_guide.md
---

# 📘 Module 12: Deleting and Adding a Node from/to Oracle RAC

> **Section**: 12/14
> **Khóa học**: Oracle Database RAC Administration Course (Ahmed Baraka)
> **Thời gian học ước tính**: 2-3 giờ

---

## 📋 Bài học trong Module

| #   | Bài học                                          | File nguồn                                               | Loại        |
| --- | ------------------------------------------------ | -------------------------------------------------------- | ----------- |
| 1   | Deleting and Adding a Node from/to an Oracle RAC | `Section 12/Deleting and Adding a Node ...pdf` (+ Notes) | Lý thuyết   |
| 2   | Practice 17: Deleting an Oracle RAC Node         | `Section 12/Practice 17 ...pdf`                          | 🔧 Thực hành |
| 3   | Practice 18: Adding an Oracle RAC Node           | `Section 12/Practice 18 ...pdf`                          | 🔧 Thực hành |

---

## 🎯 Mục tiêu Module

- **Xóa** một node khỏi Oracle RAC (online).
- **Thêm** một node vào Oracle RAC (online).
- Nắm **đúng thứ tự** và **chạy lệnh ở đúng node** (tránh mất nhầm node muốn giữ).

---

## 📋 Nội dung chính

> 📄 Nguồn: `Section 12/Deleting and Adding a Node from-to an Oracle RAC.pdf`

> ⚠️ **Cảnh báo an toàn**: nhiều lệnh ở đây có tính **phá hủy** và phải chạy ở **đúng node**. Chạy nhầm node có thể làm **mất node muốn giữ**. Luôn kiểm tra đang ở node nào trước khi thực thi.

### 1. Xóa một node (admin-managed) — 4 bước tuần tự

Oracle RAC cho phép xóa node **online**. Giả sử xóa `srv2` (instance `rac2`):

| #   | Hành động                                                                 | Chạy ở đâu / user             |
| --- | ------------------------------------------------------------------------- | ----------------------------- |
| 1   | Xóa **database instance** của node cần xóa: `dbca`                        | Một node **giữ lại** (oracle) |
| 2   | Gỡ **Oracle Database home**: `$ORACLE_HOME/deinstall/deinstall -local`    | **Node cần xóa** (oracle)     |
| 3   | Gỡ **Oracle Clusterware home**: `$ORACLE_HOME/deinstall/deinstall -local` | **Node cần xóa** (grid)       |
| 4   | **Xóa node** khỏi cluster: `crsctl delete node -n srv2`                   | Một node **giữ lại** (root)   |

### 2. Thêm một node — 3 bước tuần tự

Oracle RAC cho phép thêm node **online** (sau khi đã làm xong prerequisite: network, storage, OS user/group...):

| #   | Hành động                                                       | Chạy ở đâu / user             |
| --- | --------------------------------------------------------------- | ----------------------------- |
| 1   | Mở rộng **Clusterware home**: `$ORACLE_HOME/addnode/addnode.sh` | Một node **đang có** (grid)   |
| 2   | Mở rộng **Database home**: `$ORACLE_HOME/addnode/addnode.sh`    | Một node **đang có** (oracle) |
| 3   | Thêm **database instance** ở node mới: `dbca`                   | Node mới (oracle)             |

---

## 🔧 Practice 17 — Xóa node `srv2`

> 📄 Nguồn: `Section 12/Practice 17 ...pdf`

**A. Xóa instance `rac2` (chạy ở srv1):** backup OCR trước cho an toàn.

```bash
ocrconfig -manualbackup ; ocrconfig -showbackup     # (root)
# DBCA (oracle) trên srv1: Instance Management → Delete an instance → chọn rac2
srvctl config database -db rac                       # xác nhận rac2 đã bị gỡ
sqlplus / as sysdba
  SELECT GROUP#, THREAD#, STATUS FROM V$LOG;          # chỉ còn thread 1
```

**B. Gỡ Database home khỏi srv2:**

```bash
srvctl stop    listener -listener LISTENER -node srv2   # trên srv2
srvctl disable listener -listener LISTENER -node srv2
$ORACLE_HOME/deinstall/deinstall -local                 # trên srv2 (oracle)
```

**C. Gỡ Clusterware home khỏi srv2:**

```bash
olsnodes -s -t                                          # srv2 active & unpinned
$ORACLE_HOME/deinstall/deinstall -local                 # trên srv2 (grid)
#  → script yêu cầu chạy rootcrs.sh với option cụ thể bằng root trên srv2
#  → kết thúc bằng "Successfully detached Oracle home"
```

**D. Xóa node khỏi cluster (chạy ở srv1):**

```bash
crsctl delete node -n srv2                              # (root) trên srv1
cluvfy stage -post nodedel -n srv2 -verbose             # (grid) xác nhận
```

---

## 🔧 Practice 18 — Thêm node `srv2`

> 📄 Nguồn: `Section 12/Practice 18 ...pdf`

> 📝 Trong thực tế phải làm đủ prerequisite (network, storage, OS user/group) cho node mới trước.

**A. Cài `cvuqdisk` trên srv2** (bắt buộc trước khi mở rộng Clusterware):

```bash
cp /u01/app/12.2.0/grid/cv/rpm/cvuqdisk-1.0.10-1.rpm /media/sf_staging     # srv1 (root)
# srv2 (root):
CVUQDISK_GRP=oinstall; export CVUQDISK_GRP
rpm -iv /media/sf_staging/cvuqdisk-1.0.10-1.rpm
```

**B. Mở rộng Clusterware home srv1 → srv2 (grid):**

```bash
cluvfy stage -pre nodeadd -n srv2
cd $ORACLE_HOME/addnode ; ./addnode.sh
#  OUI: Add Cluster Node → Public srv2.localdomain, Node Role HUB, VIP srv2-vip.localdomain
#       → SSH Connectivity → Install → chạy root.sh trên srv2 (root)
```

**C. Mở rộng Database home srv1 → srv2 (oracle):**

```bash
cd $ORACLE_HOME/addnode ; ./addnode.sh                  # chọn srv2 → Install → root.sh trên srv2
cluvfy stage -post nodeadd -n srv2                       # (grid) xác nhận
```

**D. Thêm instance ở srv2 (dbca trên srv1, oracle):**

```bash
# DBCA: RAC database instance management → Add an Instance → chọn database rac
cluvfy comp admprv -o db_config -d $ORACLE_HOME -n srv2
srvctl status database -d rac                            # thấy instance mới
```

---

## 🧠 Tóm tắt để nhớ lâu

- **Cả xóa và thêm node đều làm ONLINE** (không tắt Clusterware/database).
- **Xóa (4 bước)**: `dbca` xóa instance (node giữ lại) → `deinstall -local` DB home (node xóa) → `deinstall -local` GI home (node xóa) → `crsctl delete node -n` (node giữ lại).
- **Thêm (3 bước)**: `addnode.sh` GI home → `addnode.sh` DB home (đều từ node đang có) → `dbca` add instance ở node mới. Nhớ cài **`cvuqdisk`** trước.
- Dùng **`cluvfy stage -pre/-post nodeadd/nodedel`** để kiểm tra; backup **OCR** trước khi thao tác.
- ⚠️ Chạy lệnh phá hủy ở **đúng node** — sai node có thể mất node muốn giữ.

---

## 🛠️ Sau khi học xong, hãy tự làm

1. Vẽ sơ đồ 4 bước xóa node + ghi rõ node/user mỗi bước.
2. Vẽ sơ đồ 3 bước thêm node + prerequisite.
3. Giải thích vì sao phải cài `cvuqdisk` trước khi `addnode.sh`.
4. Thực hành xóa `srv2` rồi thêm lại (Practice 17 → 18).

---

## ⏭️ Module tiếp theo

**Module 13: RAC with Data Guard** — tạo Physical Standby RAC database.


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-RAC-Administration-Course/modules/module_12/module_12_guide.md`
