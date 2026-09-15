---
title: '📘 Module 10: Policy-Managed Oracle RAC Databases'
course: 04-rac-administration
source: The-Oracle-Database-RAC-Administration-Course/modules/module_10/module_10_guide.md
---

# 📘 Module 10: Policy-Managed Oracle RAC Databases

> **Section**: 10/14
> **Khóa học**: Oracle Database RAC Administration Course (Ahmed Baraka)
> **Thời gian học ước tính**: 3-4 giờ

---

## 📋 Bài học trong Module

| #   | Bài học                                                      | File nguồn                      | Loại        |
| --- | ------------------------------------------------------------ | ------------------------------- | ----------- |
| 1   | Managing Policy-Managed RAC — Part I                         | `Section 10/... Part I.pdf`     | Lý thuyết   |
| 2   | Managing Policy-Managed RAC — Part II                        | `Section 10/... Part II.pdf`    | Lý thuyết   |
| 3   | Practice 15: Creating Policy-managed RAC Database            | `Section 10/Practice 15 ...pdf` | 🔧 Thực hành |
| 4   | Practice 16: Server Categorization & Cluster Config Policies | `Section 10/Practice 16 ...pdf` | 🔧 Thực hành |

---

## 🎯 Mục tiêu Module

- Hiểu **server pool** và cách policy-managed RAC dùng nó.
- Nắm **lợi ích** của policy-managed và **convert** admin-managed → policy-managed.
- Tạo **service** (SINGLETON/UNIFORM) cho policy-managed database/PDB.
- Dùng **server categorization**, **cluster configuration policy** và **policy set**; đọc/ghi **server configuration attributes**.

---

## 📋 Nội dung chính — Part I

> 📄 Nguồn: `Section 10/Managing Policy-Managed Oracle RAC Databases - Part I.pdf`

### 1. Hai kiểu triển khai RAC

|              | Administrator-managed                       | Policy-managed           |
| ------------ | ------------------------------------------- | ------------------------ |
| Có từ        | Kiểu duy nhất trước 11.2                    | Từ 11.2                  |
| Gán instance | **Tĩnh** vào node cụ thể                    | Dựa trên **server pool** |
| Service      | preferred / available trên instance cụ thể  | Chạy theo pool           |
| Hạn chế      | Khi failover **không tận dụng** server rảnh | —                        |

### 2. Server Pool

- **Nhóm logic các node** trong cluster; server không thuộc pool nào nằm ở **FREE**.
- Policy-managed database cấu hình theo **pool, không theo server**.
- Một server chỉ thuộc **một pool** tại một thời điểm; Clusterware **tự thêm/bớt** server.
- Service chạy dạng **singleton** hoặc **uniform**.
- Chỉ **một instance** của một RAC database trên một server tại một thời điểm.

**Thuộc tính pool:**

| Thuộc tính   | Ý nghĩa                                                    |
| ------------ | ---------------------------------------------------------- |
| `MIN_SIZE`   | Số server tối thiểu (chấp nhận 0)                          |
| `MAX_SIZE`   | Số server tối đa (**-1 = không giới hạn**)                 |
| `IMPORTANCE` | Độ ưu tiên **0–1000** (càng cao càng ưu tiên khi failover) |

### 3. Lợi ích của Policy-Management

1. **Đảm bảo thứ tự start** của database service.
2. **Failover tốt hơn**: tự dùng server trong **FREE pool**; ưu tiên service quan trọng (theo `IMPORTANCE`).
3. **Relocate** server theo **categorization**.
4. **Dynamic resource provisioning**: dời server theo **thời gian/sự kiện** (vd ngày/đêm).

### 4. Default server pools

- **Free**: chứa server chưa gán pool nào (chỉ sửa được `IMPORTANCE` và `ACL`).
- **Generic**: chứa server của **admin-managed** database.

### 5. Tạo & quản lý server pool

```bash
# srvctl: pool cho DATABASE  |  crsctl: pool cho ứng dụng khác
srvctl add srvpool -serverpool spool1 -importance 1 -min 1 -max 1
crsctl add serverpool sp1 -attr "MIN_SIZE=1, MAX_SIZE=1, IMPORTANCE=1"

crsctl status serverpool [-p | -v | -f]
srvctl config srvpool [-serverpool spool1]
crsctl status server [-g | -p | -v | -f]
```

> ⚠️ Pool tạo bằng **`srvctl`** được Clusterware **thêm tiền tố `ora.`**. Khi dùng **`crsctl`** phải gõ kèm `ora.`; khi dùng **`srvctl`** thì **không** kèm.

### 6. Convert Administrator-managed → Policy-managed

```bash
srvctl config database -d rac                 # xem deployment type hiện tại
srvctl stop database   -d rac
srvctl modify database -d rac -serverpool sp1
```

> Tên instance đổi sang định dạng **`SID_n`** (vd `rac_1`, `rac_2`) — instance **không cố định** trên một server nữa.

### 7. Tạo service cho Policy-Managed DB/PDB

`cardinality` nhận **SINGLETON** (một instance) hoặc **UNIFORM** (mọi instance trong pool):

```bash
# singleton cho PDB
srvctl add service -db rac -pdb pdb1 -service hrsrv -serverpool spool1 -cardinality singleton
# uniform cho RAC database
srvctl add service -db rac -service hrsrv -serverpool spool1 -cardinality uniform
```

---

## 📋 Nội dung chính — Part II

> 📄 Nguồn: `Section 10/Managing Policy-Managed Oracle RAC Databases - Part II.pdf`

### 8. Ba khái niệm

- **Server categorization**: tổ chức server thành **category** theo **attribute**.
- **Cluster configuration policy**: một "tài liệu" chứa **đúng một định nghĩa cho mỗi server pool** do policy set quản lý.
- **Cluster configuration policy set**: chứa **một hoặc nhiều** policy; **chỉ một policy active** tại một thời điểm; admin đặt policy active.

### 9. Server Configuration Attributes

| Attribute              | Ý nghĩa                                 |
| ---------------------- | --------------------------------------- |
| `ACTIVE_CSS_ROLE`      | Role đang chạy: **LEAF** hoặc **HUB**   |
| `CONFIGURED_CSS_ROLE`  | Role được cấu hình                      |
| `CPU_CLOCK_RATE`       | Tốc độ CPU (MHz)                        |
| `CPU_COUNT`            | Số processor                            |
| `CPU_EQUIVALENCY`      | Giá trị tương đối mô tả sức mạnh CPU    |
| `MEMORY_SIZE`          | Bộ nhớ (MB)                             |
| `RESOURCE_USE_ENABLED` | 1: server có thể dời; 0: giữ trong FREE |
| `SERVER_LABEL`         | Nhãn do user đặt                        |

```bash
crsctl set server label GoldS      # chạy bằng root; PHẢI restart CRS để có hiệu lực
crsctl get server label
```

### 10. Server Category

`EXPRESSION` xác định server thuộc category; toán tử: `=`, `eqi`, `>`, `<`, `!=`, `co` (contains), `coi`, `st` (starts), `en` (ends), `nc`, `nci`; boolean `AND`/`OR`.

```bash
crsctl add category silvercat -attr "EXPRESSION='(CPU_COUNT > 2) AND (MEMORY_SIZE > 2048)'"
crsctl add category highIO    -attr "EXPRESSION='SERVER_LABEL co IOGold'"
crsctl modify category silvercat -attr "EXPRESSION=..."
crsctl status category silvercat
# gán category cho pool
srvctl modify srvpool goldpool -category "goldcat"
```

### 11. Cluster Configuration Policy Set

**Cách 1 (dòng lệnh):**

```bash
crsctl add policy daytime -attr "DESCRIPTION='Day Time Policy'"
crsctl modify policyset  -attr "SERVER_POOL_NAMES='Free prodpool devpool testpool'" -ksp
crsctl modify serverpool prodpool -attr "MAX_SIZE=2,MIN_SIZE=2,SERVER_CATEGORY=GoldS" -policy daytime
crsctl modify policyset  -attr "LAST_ACTIVATED_POLICY='daytime'"
```

**Cách 2 (file):** viết mỗi policy trong file text (định nghĩa các pool + attribute) → `crsctl modify policyset -file <file>` → activate bằng `LAST_ACTIVATED_POLICY`.

### 12. Lưu ý khi dùng Policy-Managed

- Phải **lập kế hoạch & test kỹ** — cấu hình sai có thể làm service **unavailable**.
- Thử hiệu ứng policy **không** cần activate thật:

  ```bash
  crsctl eval activate policy NighShift -admin -l 'resources'
  ```

- Troubleshooting phức tạp hơn · quy ước đặt tên instance khác · ảnh hưởng **GoldenGate** (có thể cần Clusterware Bundled Agents).

---

## 🔧 Practices

### Practice 15 — Tạo Policy-managed CDB RAC

1. Tạo 2 pool: `spool1` (importance 1) > `spool2` (importance 0), mỗi pool min=max=1.
2. DBCA tạo **Policy-managed CDB RAC** `rac` dùng **existing server pools** spool1+spool2 → instance tên **`rac_1`/`rac_2`** (không cố định trên server nào). **Comment `ORACLE_SID`** trong `.bash_profile`.
3. Tạo 2 **uniform service** `service1` (spool1) & `service2` (spool2) cho `pdb1`.
4. **Test node failover**: reboot server trong spool1 → Clusterware **kéo server từ spool2 sang spool1** (vì spool1 importance cao hơn) ⇒ `service2` mất server → unavailable. Sau reboot, server quay lại spool2. Set `spool1 importance 0` cho bằng spool2.

### Practice 16 — Server Categorization & Config Policies

- **Category**: đặt label `GoldS` (srv1) / `SilverS` (srv2) bằng root (restart CRS) → tạo `GoldCat`/`SilverCat` với `EXPRESSION='SERVER_LABEL co ...'` → gán vào spool1/spool2 (`srvctl modify srvpool -category ... -force`) → xác nhận srv1∈spool1, srv2∈spool2.
- **Policy set**: file `policy.txt` với `SetPol1` (mỗi pool min=max=1) và `SetPol2` (spool1 min=max=2, spool2 min=max=0) — nhớ dùng **`ora.spool1`** trong file crsctl. Activate `LAST_ACTIVATED_POLICY=SetPol1/SetPol2 -f` và quan sát phân bổ server thay đổi.

---

## 🧠 Tóm tắt để nhớ lâu

- **Admin-managed** (instance gán tĩnh vào node) vs **Policy-managed** (theo **server pool**, instance đặt tên `SID_n`, không cố định).
- Pool có `MIN_SIZE`/`MAX_SIZE`(-1=∞)/`IMPORTANCE`(0–1000); server ngoài pool nằm ở **FREE**; default pools **Free** + **Generic**.
- **`srvctl`** quản lý pool database (không `ora.`), **`crsctl`** dùng cho ứng dụng & phải kèm **`ora.`**.
- Service policy-managed: **cardinality SINGLETON/UNIFORM**, gắn với `-serverpool`.
- Part II: **server categorization** (label/EXPRESSION), **policy** & **policy set** (chỉ 1 active) cho phép **dynamic resource provisioning** (ngày/đêm).

---

## 🛠️ Sau khi học xong, hãy tự làm

1. Tạo 2 server pool khác importance và tạo policy-managed CDB dùng chúng.
2. Convert một admin-managed DB sang policy-managed và quan sát tên instance `SID_n`.
3. Tạo uniform/singleton service theo pool.
4. Đặt server label + category, gán vào pool; tạo policy set 2 policy và activate lần lượt.

---

## ⏭️ Module tiếp theo

**Module 11: Oracle Flex Clusters** — Hub/Leaf nodes và Flex ASM.


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-RAC-Administration-Course/modules/module_10/module_10_guide.md`
