---
title: Runbook 03 — Group Replication (cấu hình thuần, không qua InnoDB Cluster)
course: 06-high-availability
source: HA/Mysql/runbooks/03-group-replication.md
---

# Runbook 03 — Group Replication (cấu hình thuần, không qua InnoDB Cluster)

Bạn chọn cách này khi muốn full control config thay vì để `mysqlsh dba.*` tự sinh — ví dụ tự động hoá bằng Ansible/Puppet, hoặc tích hợp với load balancer khác (ProxySQL, HAProxy) thay vì MySQL Router.

## 1. Khác biệt vs InnoDB Cluster

| | Pure Group Replication | InnoDB Cluster |
|---|---|---|
| Control plane | `SQL` (START/STOP GROUP_REPLICATION) | `mysqlsh` JS APIs |
| Metadata store | Không | `mysql_innodb_cluster_metadata` schema |
| Proxy mặc định | Tự chọn (ProxySQL/HAProxy) | MySQL Router |
| Tự sinh user | Phải tạo tay | `clusterAdmin` được sinh |

## 2. Topology & GR group UUID

GR group được định danh bằng 1 UUID — mọi node trong cùng group phải dùng cùng giá trị. Đặt trong `scripts/common/env.sh`:
```bash
GR_GROUP_UUID=aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa
```

## 3. Các bước

### B1. Primary (node1)
```bash
bash scripts/group-replication/primary-setup.sh
```
- Ghi config `loose-group_replication_*` vào `/etc/mysql/mysql.conf.d/zz-group-replication.cnf`
- Restart MySQL
- Tạo user `repl` với grant `REPLICATION SLAVE, BACKUP_ADMIN, GROUP_REPLICATION_STREAM`
- `CHANGE REPLICATION SOURCE ... FOR CHANNEL 'group_replication_recovery'`
- Bootstrap group: `SET GLOBAL group_replication_bootstrap_group=ON; START GROUP_REPLICATION; SET ...=OFF;`

### B2. Secondaries (node2, node3)
```bash
bash scripts/group-replication/secondary-setup.sh
```
Script tự lấy `hostname -I` → `loose-group_replication_local_address`, ghi cùng group seeds, không bật bootstrap, `START GROUP_REPLICATION` để join.

### B3. Verify
```sql
SELECT * FROM performance_schema.replication_group_members;
```
Kỳ vọng: 3 dòng, mọi `MEMBER_STATE = ONLINE`, đúng 1 node `MEMBER_ROLE = PRIMARY`.

```sql
SELECT * FROM performance_schema.replication_group_member_stats\G
```
Theo dõi `COUNT_TRANSACTIONS_IN_QUEUE` — tăng dần liên tục = node đang chậm.

## 4. Switch sang multi-primary

Tất cả node đều cho phép ghi. Phù hợp khi không có write conflict (ví dụ shard theo user_id).
```bash
bash scripts/group-replication/switch-to-multi-primary.sh
```
Hoặc thủ công:
```sql
SELECT group_replication_switch_to_multi_primary_mode();
```
Đổi lại:
```sql
SELECT group_replication_switch_to_single_primary_mode('UUID_OF_CHOSEN_PRIMARY');
```

## 5. Vận hành thường gặp

### 5.1 Một node rời nhóm bất ngờ
```sql
-- trên node đó:
START GROUP_REPLICATION;
```
Nếu vẫn fail → kiểm tra `errlog`, thường do GTID set không tương thích (node bị tụt nhiều) — clone lại từ donor:
```sql
SET GLOBAL clone_valid_donor_list='node1:3306';
CLONE INSTANCE FROM 'clusteradmin'@'node1':3306 IDENTIFIED BY '...';
-- MySQL tự restart sau khi clone xong
START GROUP_REPLICATION;
```

### 5.2 Quorum loss
Trong cluster 3 node, mất 2 node → còn 1 node sẽ ở `MEMBER_STATE=ERROR/UNREACHABLE` và **block writes**. Bắt buộc can thiệp:
```sql
-- chỉ chạy trên node duy nhất còn sống, sau khi xác nhận 2 node kia thực sự chết
SET GLOBAL group_replication_force_members = '<ip>:33061';
```

### 5.3 Đổi seeds list
```sql
STOP GROUP_REPLICATION;
SET GLOBAL group_replication_group_seeds = 'node1:33061,node2:33061,node3:33061,node4:33061';
START GROUP_REPLICATION;
```

## 6. Rollback / tháo

Trên mỗi node:
```sql
STOP GROUP_REPLICATION;
SET GLOBAL group_replication_bootstrap_group = OFF;
```
Xoá `zz-group-replication.cnf`, restart MySQL.

## 7. Lưu ý

- Cần `binlog_checksum=NONE` (script đã set) — GR không hỗ trợ checksum CRC32.
- `transaction_write_set_extraction=XXHASH64` để conflict detection hoạt động.
- Khi chạy multi-primary, **không** dùng `SERIALIZABLE` isolation và bảng phải có PK.
- Network partition trong WAN: dùng `group_replication_consistency='BEFORE_ON_PRIMARY_FAILOVER'` để giảm rủi ro mất dữ liệu sau failover.

## 8. Tham khảo
- https://dev.mysql.com/doc/refman/8.0/en/group-replication.html


---

!!! info "Nguồn gốc"
    `HA/Mysql/runbooks/03-group-replication.md`
