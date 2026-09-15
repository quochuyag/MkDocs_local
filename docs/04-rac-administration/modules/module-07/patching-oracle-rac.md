---
title: '📘 Bài học 1: Patching Oracle RAC (chi tiết)'
course: 04-rac-administration
source: The-Oracle-Database-RAC-Administration-Course/modules/module_07/patching_oracle_rac.md
---

# 📘 Bài học 1: Patching Oracle RAC (chi tiết)

> Nguồn: `Section 07/Patching Oracle RAC.pdf` + `Practice 11` — khóa của Ahmed Baraka.
> Mục tiêu: mô tả các loại patch, các phương pháp áp patch trên RAC, best practices, và cách dùng **OPatch** / **opatchauto**.

---

## 1. Về patch của Oracle

- Patch chứa **product fixes** (security + bug), gắn với **release/version** cụ thể của sản phẩm.
- Patch **nâng version, KHÔNG nâng release**; cập nhật executable, library, object trong **software home**.
- Cần tài khoản **Oracle Support** để tải; có thể tự động hóa qua **EM Cloud Control**.

---

## 2. Các loại patch (Patch Types)

| Loại                            | Mô tả (tên cũ)                                                       |
| ------------------------------- | -------------------------------------------------------------------- |
| **Interim patch**               | 1 hoặc vài bug fix (PSE / one-off / hot fix)                         |
| **Interim cho security**        | Fix bảo mật riêng (test patch / fix verification binary / e-fix)     |
| **Diagnostic patch**            | Hỗ trợ chẩn đoán/xác minh fix                                        |
| **BPU** – Bundle Patch Update   | Tập tích lũy fix cho một product/component                           |
| **PSU** – Patch Set Update ⭐    | Tập tích lũy fix **high-impact, low-risk, đã kiểm chứng** + security |
| **SPU** – Security Patch Update | Tập tích lũy fix bảo mật (tên cũ: **CPU** – Critical Patch Update)   |

---

## 3. Ba phương pháp áp patch cho RAC

> ⚠️ Đây là taxonomy chính xác của khóa học — **không** phải "Rolling vs Non-Rolling".

### 3.1 All Node Patching
- **Tắt tất cả node**, áp patch trên mọi node → **downtime tối đa**.
- OPatch dùng cách này khi patch **không** áp được theo kiểu rolling.

### 3.2 Rolling Patching ⭐
- Áp patch **một node tại một thời điểm**.
- Software home phải **local** cho từng node.
- Cho phép các version **cùng tồn tại tạm thời**.
- Không phải patch nào cũng hỗ trợ rolling → kiểm tra:

  ```bash
  opatch query -all <patch_location> | grep rolling
  ```

### 3.3 Minimum Downtime Patching
- Chia node thành **2 nhóm**, áp patch từng nhóm:
  1. Áp patch trên **node local trước** (dùng làm base để patch các node khác).
  2. Định nghĩa nhóm node patch trước; dừng nhóm 1 và patch **từng instance một**.
  3. Dừng nhóm 2 (khoảng downtime) và khởi động nhóm 1.
  4. Áp patch nhóm 2 rồi khởi động từng node.
- Kích hoạt khi chỉ định `minimize_downtime`.

---

## 4. OPatch

- Tiện ích **Java**, đi kèm GI home và DB home; nâng cấp riêng từ Oracle Support (Doc **293369.1** – Master Note For OPatch).

**Chuẩn bị môi trường dùng OPatch:** nâng OPatch lên bản mới nhất · kiểm tra `ORACLE_HOME` · backup software · stage patch trên **mỗi node** · thêm thư mục OPatch vào `PATH` · cấu hình **SSH user equivalency**.

```bash
export PATH=$PATH:/u01/app/12.1.0/grid/OPatch/
export ORACLE_HOME=/u01/app/12.1.0/grid
opatch version                 # version OPatch hiện tại
opatch lsinventory             # patch đã áp
opatch <command> -oh /u01/app/12.1.0/grid
opatch <command> -help
```

---

## 5. Quy trình áp patch thủ công (mỗi node)

```bash
# 1) Dừng resource DB home + toàn bộ GI stack ở node cục bộ
srvctl stop home -oraclehome $ORACLE_HOME -statefile ~/rac1_state.dmp -node srv1
crsctl stop crs [-f]                                   # chạy bằng root

# 2) Prepatch (root) trong GI home
cd /u01/app/12.2.0/grid/crs/install ; rootcrs.sh -prepatch

# 3) Áp patch: bằng grid trên GI home, rồi bằng oracle trên DB home
opatch apply

# 4) Postpatch (root)
rootcrs.sh -postpatch

# 5) Khởi động lại process của DB home
```

---

## 6. opatchauto (OPatch Automation Utility)

- Tự động áp patch cho **GI home + tất cả RAC DB home**.
- **Chạy bằng root**; GI và DB home phải **cùng version**; nếu home ở non-shared storage thì chạy **trên từng node** (một node tại một thời điểm).

```bash
opatchauto apply                    # patch cả GI + DB home
opatchauto apply -oh <Grid_home>    # chỉ GI home
opatchauto apply -analyze           # kiểm tra conflict trước khi áp
opatchauto apply resume             # tiếp tục sau khi bị lỗi
```

- Log: `ORACLE_HOME/cfgtoollogs/opatch` (mỗi file gắn timestamp) + chỉ mục `opatch_history.txt`.
- Truy vấn patch từ SQL: package **`DBMS_QOPATCH`** (đọc OUI inventory real-time; xem patch của mọi node từ một nơi).

---

## 7. Best practices

- Áp **PSU/SPU mới nhất**.
- Luôn test trên môi trường **non-production trước**.
- **Đọc README** đi kèm patch (đây mới là tài liệu tham chiếu chuẩn, không phải guide này).
- Môi trường IT lớn: dùng **EM Cloud Control** để tự động hóa.
- Trước khi áp PSU: **backup cả VM/shared disk + backup RMAN**, tắt job backup trong cron.

---

## 8. Thực hành (Practice 11) — tóm tắt

Áp **PSU 26635815 (12.1.0.2.171017)** rolling lên GI + DB:

1. Nâng OPatch ở GI/DB home (xóa cũ → copy mới → `chown`), verify `opatch lsinventory`.
2. Backup RMAN + tắt cron backup.
3. Tạo service `racsrv` (TAF BASIC) + Swingbench để có session thật.
4. `opatchauto apply` trên **srv1**: khi thấy *"Bringing down CRS service..."* → session failover sang **rac2**.
5. Verify + lặp lại trên **srv2**.
6. Post: `SELECT PATCH_ID,VERSION,ACTION,STATUS,DESCRIPTION FROM DBA_REGISTRY_SQLPATCH;` (chỉ đầy đủ khi patch xong **mọi node**); backup lại.

---

## 9. Ghi nhớ quan trọng

- **6 loại patch**; PSU/SPU là loại hay gặp nhất.
- **3 phương pháp** RAC: All Node / **Rolling** / Minimum Downtime.
- **OPatch** = thủ công per-node (prepatch → apply GI → apply DB → postpatch); **opatchauto** = tự động, chạy bằng **root**.
- Rolling PSU ⇒ **gần như không downtime** nhờ service/TAF.
- Luôn **backup + đọc README** trước khi áp patch.


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-RAC-Administration-Course/modules/module_07/patching_oracle_rac.md`
