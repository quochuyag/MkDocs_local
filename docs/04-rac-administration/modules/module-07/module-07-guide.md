---
title: '📘 Module 07: Patching & Upgrading Oracle RAC'
course: 04-rac-administration
source: The-Oracle-Database-RAC-Administration-Course/modules/module_07/module_07_guide.md
---

# 📘 Module 07: Patching & Upgrading Oracle RAC

> **Section**: 07/14
> **Khóa học**: Oracle Database RAC Administration Course (Ahmed Baraka)
> **Thời gian học ước tính**: 3-4 giờ

---

## 📋 Bài học trong Module

| #   | Bài học                                      | File nguồn                            | Loại        |
| --- | -------------------------------------------- | ------------------------------------- | ----------- |
| 1   | Patching Oracle RAC                          | `Section 07/Patching Oracle RAC.pdf`  | Lý thuyết   |
| 2   | Upgrading Oracle RAC                         | `Section 07/Upgrading Oracle RAC.pdf` | Lý thuyết   |
| 3   | Practice 11: Applying Patch Set Update (PSU) | `Section 07/Practice 11/`             | 🔧 Thực hành |
| 4   | Practice 12: Upgrading Oracle RAC Database   | `Section 07/Practice 12 ...pdf`       | 🔧 Thực hành |

> 📎 Xem thêm chi tiết: [patching_oracle_rac.md](patching-oracle-rac.md) · [upgrading_oracle_rac.md](upgrading-oracle-rac.md)

---

## 🎯 Mục tiêu Module

- Phân biệt các **loại patch** của Oracle và các **phương pháp áp patch** cho RAC.
- Dùng **OPatch** và **opatchauto** để áp patch (PSU) theo kiểu **rolling**.
- Phân biệt **upgrade** vs **data migration**; đọc **release number format**.
- Chạy **Pre-Upgrade Information Tool** và dùng **DBUA** để upgrade RAC (12.1 → 12.2).

---

## 📋 Nội dung chính

### 1. Patching Oracle RAC

> 📄 Nguồn: `Section 07/Patching Oracle RAC.pdf`

#### 1.1 Về patch của Oracle

- Patch = **product fixes** (security + bug); gắn với **release/version** cụ thể.
- Patch **nâng version, không nâng release**; cập nhật file executable/library/object trong **software home**.
- Cần tài khoản **Oracle Support** để tải; có thể tự động hóa bằng **EM Cloud Control**.

#### 1.2 Các loại patch (Patch Types)

| Loại                            | Mô tả                                                                |
| ------------------------------- | -------------------------------------------------------------------- |
| **Interim patch**               | 1 hoặc vài bug fix (tên cũ: PSE, one-off, hot fix)                   |
| **Interim cho security**        | Fix bảo mật riêng (tên cũ: test patch, e-fix)                        |
| **Diagnostic patch**            | Hỗ trợ chẩn đoán/xác minh fix                                        |
| **BPU** (Bundle Patch Update)   | Tập tích lũy fix cho một product/component                           |
| **PSU** (Patch Set Update) ⭐    | Tập tích lũy fix **high-impact, low-risk, đã kiểm chứng** + security |
| **SPU** (Security Patch Update) | Tập tích lũy fix bảo mật (tên cũ: **CPU**)                           |

#### 1.3 Ba phương pháp áp patch cho RAC

| Phương pháp            | Cách làm                                                                                            | Downtime                                         |
| ---------------------- | --------------------------------------------------------------------------------------------------- | ------------------------------------------------ |
| **All Node Patching**  | Tắt **tất cả node**, áp patch cùng lúc                                                              | **Tối đa** — dùng khi patch không hỗ trợ rolling |
| **Rolling Patching** ⭐ | Áp **lần lượt từng node**; software home phải **local**; cho phép các version cùng tồn tại tạm thời | **Gần như bằng 0**                               |
| **Minimum Downtime**   | Chia node thành **2 nhóm**, patch nhóm 1 (dùng node local làm base) rồi đổi sang nhóm 2             | Trung bình                                       |

```bash
# kiểm tra patch có hỗ trợ rolling không:
opatch query -all <patch_location> | grep rolling
```

#### 1.4 OPatch

- Tiện ích **Java**, đi kèm GI home và DB home; có thể **nâng cấp riêng** từ Oracle Support (Doc **293369.1**).

```bash
export PATH=$PATH:/u01/app/12.1.0/grid/OPatch/
export ORACLE_HOME=/u01/app/12.1.0/grid
opatch version           # version hiện tại
opatch lsinventory       # patch đã áp trên home
opatch <command> -oh /u01/app/12.1.0/grid   # chỉ định home khác
opatch <command> -help
```

#### 1.5 Quy trình áp patch thủ công (mỗi node)

```bash
# 1. Dừng resource của DB home + toàn bộ GI stack ở node cục bộ
srvctl stop home -oraclehome $ORACLE_HOME -statefile ~/rac1_state.dmp -node srv1
crsctl stop crs [-f]                       # (root)
# 2. Prepatch (root)
cd /u01/app/12.2.0/grid/crs/install ; rootcrs.sh -prepatch
# 3. Áp patch trên GI home (grid) rồi DB home (oracle)
opatch apply
# 4. Postpatch (root)
rootcrs.sh -postpatch
# 5. Khởi động lại các process của DB home
```

#### 1.6 opatchauto (OPatch Automation Utility)

- Tự động áp patch cho **GI home + RAC DB home**; **chạy bằng root**; GI và DB home phải **cùng version**; chạy **trên từng node** nếu home ở non-shared storage.

```bash
opatchauto apply                    # patch cả GI + DB home
opatchauto apply -oh <Grid_home>    # chỉ GI home
opatchauto apply -analyze           # kiểm tra conflict trước
opatchauto apply resume             # tiếp tục sau khi lỗi
```

- Log: `ORACLE_HOME/cfgtoollogs/opatch` + `opatch_history.txt`.
- Truy vấn patch từ SQL: package **`DBMS_QOPATCH`** (đọc OUI inventory real-time).

#### 1.7 Best practices

Áp **PSU/SPU mới nhất** · luôn test **trước khi lên production** · **đọc README** kèm patch · dùng **EM Cloud Control** cho môi trường lớn.

---

### 2. Upgrading Oracle RAC

> 📄 Nguồn: `Section 07/Upgrading Oracle RAC.pdf`

#### 2.1 Upgrade vs Data Migration

- **Upgrade**: biến môi trường Oracle hiện tại thành **release mới hơn**.
- **Data migration**: **chuyển dữ liệu** từ database này sang database khác.

| Nhóm               | Công cụ                                                               |
| ------------------ | --------------------------------------------------------------------- |
| **Upgrade tools**  | **DBUA** (khuyến nghị), Manual upgrade, Rapid Home Provisioning (RHP) |
| **Data migration** | Data Pump, Full Transportable Tablespaces (TTS), GoldenGate           |

#### 2.2 Release Number Format (ví dụ 12.2.0.1.0)

```text
12   .  2  .  0  .  1  .  0
│       │     │     │     └─ platform-specific patch
│       │     │     └─────── patch set number
│       │     └───────────── (application server release)
│       └─────────────────── database maintenance release
└─────────────────────────── major database release
```

#### 2.3 Pre-Upgrade Information Tool

|         | 12.2                 | Trước 12.2         |
| ------- | -------------------- | ------------------ |
| Utility | **`preupgrade.jar`** | **`preupgrd.sql`** |
| Chạy từ | Operating System     | SQL*Plus           |

```bash
$EARLIER_ORACLE_HOME/jdk/bin/java -jar \
  $NEW_ORACLE_HOME/rdbms/admin/preupgrade.jar FILE TEXT DIR /home/oracle/scripts
```

Sinh ra: `preupgrade.log`, **`preupgrade_fixups.sql`** (chạy trước), **`postupgrade_fixups.sql`** (chạy sau). Với CDB có thêm script riêng cho từng PDB.

#### 2.4 Quy trình & lưu ý

- **Upgrade Grid Infrastructure TRƯỚC, rồi mới upgrade Database.**
- GI/DB mới phải cài vào **home mới**; 12.2 OUI có thể **tự chạy root.sh** trên các node.
- **DBUA** khuyến nghị: GUI dễ dùng, gọi cùng script như manual, tự validate sau upgrade, tự khóa các account mới. **Clusterware phải đang chạy** trong lúc upgrade.
- Đường upgrade production: test upgrade trên DB test → test ứng dụng → bảo toàn bản production → upgrade production → tinh chỉnh.
- **Low-downtime options**: Data Guard (transient logical standby), GoldenGate.

---

### 3. Practice 11: Applying PSU (rolling)

> 📄 Nguồn: `Section 07/Practice 11/...pdf`

Áp **PSU 26635815 (12.1.0.2.171017)** lên cả GI home và DB home theo kiểu **rolling** (gần như không downtime). Các bước chính:

1. **Nâng OPatch** trong GI home và DB home (xóa `OPatch` cũ, copy bản mới, `chown`); kiểm tra bằng `opatch lsinventory`.
2. **Tắt job backup trong crontab**, chạy backup RMAN đầy đủ (⚠️ luôn backup cả VM/shared disk trước khi áp PSU).
3. Tạo service `racsrv` (TAF BASIC) + chạy **Swingbench** để có session thật quan sát failover.
4. Áp PSU trên **srv1** trước: `opatchauto apply` (root). Khi thấy *"Bringing down CRS service..."* → session Swingbench **failover sang rac2** (một số bị disconnect nếu đang có DML mở).
5. Verify (`opatch lsinventory`, `srvctl status database -d rac`), rồi lặp lại trên **srv2**.
6. Post: `SELECT ... FROM DBA_REGISTRY_SQLPATCH;` (chỉ populate khi patch xong **mọi node**); backup lại.

#### Practice 12: Upgrading RAC (12.1.0.2 → 12.2.0.1)

> 📄 Nguồn: `Section 07/Practice 12 ...pdf`

1. **Mở rộng CRS diskgroup**: thêm DISK4 (40 GB) shareable, `oracleasm createdisk`, `asmca` → Add Disks (12.2 cần nhiều dung lượng CRS hơn).
2. **Upgrade Grid Infrastructure** vào home mới `/u01/app/12.2.0/grid`: `gridSetup.sh` → chọn *"Upgrade Oracle Grid Infrastructure"*, đặt **srv2 vào Batch 2** (giữ hệ thống còn phục vụ). Verify: `crsctl query crs activeversion`.
3. **Cài Database 12.2 software only** vào `/u01/app/oracle/product/12.2.0/db_1` (RAC, EE).
4. **Pre-Upgrade Tool**: chạy `preupgrade.jar` → `preupgrade_fixups.sql`, gather dictionary stats, purge recyclebin.
5. **DBUA** upgrade `rac` → 12.2 (chọn *"I have my own backup and restore strategy"*).
6. **Post-upgrade**: sửa `ORACLE_HOME` trong `.bash_profile` (oracle & grid, cả 2 node), copy `*.ora`, chạy `postupgrade_fixups.sql`, restart lần lượt từng node, backup lại.

---

## 🧠 Tóm tắt để nhớ lâu

- Nhớ **6 loại patch** (Interim, security interim, diagnostic, BPU, **PSU**, **SPU**) và **3 phương pháp** áp patch RAC (**All Node / Rolling / Minimum Downtime**).
- **OPatch** (thủ công, per-node: prepatch → apply GI → apply DB → postpatch) vs **opatchauto** (tự động, chạy bằng **root**, GI/DB cùng version).
- PSU áp **rolling** ⇒ gần như **không downtime**; session failover nhờ service/TAF.
- **Upgrade GI trước Database**; dùng **preupgrade.jar** (12.2) + **DBUA**; Clusterware phải chạy trong lúc upgrade.
- Luôn **backup** (kể cả VM/shared disk) và **đọc README** trước khi patch/upgrade.

---

## 🛠️ Sau khi học xong, hãy tự làm

1. Lập bảng so sánh **All Node / Rolling / Minimum Downtime** và khi nào dùng mỗi loại.
2. Viết checklist chuẩn bị trước khi áp PSU (backup, OPatch version, README, tắt cron).
3. Giải thích khác nhau **OPatch** vs **opatchauto** và ai (user nào) chạy bước nào.
4. Mô tả luồng upgrade: mở rộng CRS → GI → DB software → preupgrade → DBUA → post.
5. Giải thích vì sao `DBA_REGISTRY_SQLPATCH` chỉ đầy đủ khi patch xong mọi node.

---

## ⏭️ Module tiếp theo

**Module 08: Oracle RAC One Node** — biến thể RAC một instance với khả năng online relocation.


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-RAC-Administration-Course/modules/module_07/module_07_guide.md`
