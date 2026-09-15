---
title: '📘 Bài học 2: Upgrading Oracle RAC (chi tiết)'
course: 04-rac-administration
source: The-Oracle-Database-RAC-Administration-Course/modules/module_07/upgrading_oracle_rac.md
---

# 📘 Bài học 2: Upgrading Oracle RAC (chi tiết)

> Nguồn: `Section 07/Upgrading Oracle RAC.pdf` + `Practice 12` — khóa của Ahmed Baraka.
> Mục tiêu: phân biệt upgrade vs data migration, đọc release number, chạy pre-upgrade tool và upgrade RAC bằng **DBUA** (12.1 → 12.2).

---

## 1. Upgrade vs Data Migration

- **Upgrade**: biến môi trường Oracle hiện tại thành một **release Oracle mới hơn**.
- **Data migration**: **chuyển dữ liệu** từ database này sang database khác.

| Nhóm               | Công cụ                                                                          |
| ------------------ | -------------------------------------------------------------------------------- |
| **Upgrade tools**  | **DBUA** (khuyến nghị), Manual upgrade, Rapid Home Provisioning (RHP)            |
| **Data migration** | Oracle Data Pump, Full Transportable Tablespaces (TTS) export/import, GoldenGate |

---

## 2. Release Number Format (ví dụ 12.2.0.1.0)

```text
12   .  2  .  0  .  1  .  0
│       │     │     │     └─ platform-specific patch
│       │     │     └─────── patch set number
│       │     └───────────── application server release
│       └─────────────────── database maintenance release
└─────────────────────────── major database release
```

---

## 3. Đường upgrade cho production

1. Chuẩn bị **database test** để upgrade.
2. Thực hiện **test upgrade** trên DB test.
3. Test **ứng dụng** trên DB đã upgrade.
4. Chuẩn bị & **bảo toàn** bản production.
5. **Upgrade** production.
6. **Tune & điều chỉnh** DB production mới.

---

## 4. Pre-Upgrade Information Tool

|          | 12.2                                 | Trước 12.2         |
| -------- | ------------------------------------ | ------------------ |
| Utility  | **`preupgrade.jar`**                 | **`preupgrd.sql`** |
| Chạy từ  | Operating System                     | SQL*Plus           |
| Mục tiêu | Xác định DB đã sẵn sàng upgrade chưa | (như trên)         |

```bash
# ORACLE_HOME/BASE/SID phải trỏ theo version CŨ
$EARLIER_ORACLE_HOME/jdk/bin/java -jar \
  $NEW_ORACLE_HOME/rdbms/admin/preupgrade.jar FILE TEXT DIR /home/oracle/scripts
```

**File sinh ra:**
- `preupgrade.log` — log của tool.
- **`preupgrade_fixups.sql`** — chạy **trước** upgrade (CDB có thêm script riêng cho từng PDB).
- **`postupgrade_fixups.sql`** — chạy **sau** upgrade.

---

## 5. Upgrade Grid Infrastructure

- **Upgrade GI TRƯỚC khi upgrade Database.**
- Cài vào **home mới** (out-of-place), không đè lên home cũ.
- Linux: Oracle khuyến nghị dùng **HugePages** để có hiệu năng tốt.
- **12.2**: OUI có thể **tự chạy `root.sh`** trên các node.

---

## 6. Upgrade Database bằng DBUA

- **DBUA được khuyến nghị**:
  - GUI dễ dùng, tiết kiệm thời gian.
  - Gọi **cùng script** như phương pháp manual.
  - Tự thực hiện **validation sau upgrade**.
  - Tự **khóa các account mới** trong DB mới.
- **Clusterware phải đang chạy** trong suốt quá trình upgrade.

**Low-downtime options:** Oracle Data Guard (transient logical standby — có giới hạn kiểu dữ liệu), Oracle GoldenGate.

---

## 7. Thực hành (Practice 12) — tóm tắt: 12.1.0.2 → 12.2.0.1

> Home mới: GI `/u01/app/12.2.0/grid`, DB `/u01/app/oracle/product/12.2.0/db_1`.

1. **Mở rộng CRS diskgroup** (12.2 cần nhiều dung lượng CRS): thêm **DISK4 40GB** shareable → `fdisk` → `oracleasm createdisk DISK4 /dev/sde1` → `asmca` Add Disks vào CRS.
2. **Upgrade GI**: `unzip` image vào home mới → `export ORACLE_HOME=/u01/app/12.2.0/grid` → `./gridSetup.sh` → chọn *"Upgrade Oracle Grid Infrastructure"*, đặt **srv2 = Batch 2** (giữ hệ thống phục vụ). Verify:

   ```bash
   /u01/app/12.2.0/grid/bin/crsctl check cluster -all
   /u01/app/12.2.0/grid/bin/crsctl query crs activeversion
   ```

3. **Cài DB 12.2 software only** (RAC, EE) vào home mới — chưa upgrade database.
4. **Pre-Upgrade Tool**:

   ```bash
   /u01/app/oracle/product/12.1.0/db_1/jdk/bin/java -jar \
     /u01/app/oracle/product/12.2.0/db_1/rdbms/admin/preupgrade.jar FILE TEXT DIR /home/oracle/scripts
   sqlplus / as sysdba
     @/home/oracle/scripts/preupgrade_fixups.sql
     EXEC DBMS_STATS.GATHER_DICTIONARY_STATS;
     PURGE DBA_RECYCLEBIN;
   ```

5. **DBUA** upgrade `rac` → 12.2: `export ORACLE_HOME=$ORACLE_BASE/product/12.2.0/db_1` → `./dbua` → chọn *"I have my own backup and restore strategy"*.
6. **Post-upgrade**: sửa `ORACLE_HOME` trong `.bash_profile` (oracle & grid, **cả 2 node**), copy `*.ora` sang home mới, chạy `@/home/oracle/scripts/postupgrade_fixups.sql`, **restart lần lượt từng node** để kiểm tra, backup lại.

---

## 8. Lưu ý & lỗi thường gặp

- **Thứ tự bắt buộc**: GI trước → Database sau.
- Bảo toàn **HA**: dùng batch upgrade (node còn lại vẫn phục vụ).
- GI 12.2 upgrade cần patch **21255373** (đã nằm trong PSU đã áp ở Practice 11).
- Theo dõi **alert log, CRS log, upgrade log** để xác minh thành công.

---

## 9. Ghi nhớ quan trọng

- Phân biệt **upgrade** (đổi release) và **data migration** (chuyển dữ liệu).
- **preupgrade.jar** (12.2, chạy từ OS) vs **preupgrd.sql** (trước 12.2, chạy trong SQL*Plus).
- **Upgrade GI trước Database**; dùng **DBUA**; **Clusterware phải chạy** trong lúc upgrade.
- Sinh & chạy **preupgrade_fixups.sql** (trước) và **postupgrade_fixups.sql** (sau).
- Tài liệu tham chiếu chuẩn là **Oracle Database Upgrade Guide**, không phải guide này.


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-RAC-Administration-Course/modules/module_07/upgrading_oracle_rac.md`
