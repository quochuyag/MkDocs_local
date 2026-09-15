---
title: Runbook 02 — MySQL InnoDB Cluster
course: 06-high-availability
source: HA/Mysql/runbooks/02-mysql-innodb-cluster.md
---

# Runbook 02 — MySQL InnoDB Cluster

InnoDB Cluster = **Group Replication** (data plane) + **MySQL Shell** (control plane) + **MySQL Router** (proxy). Đây là giải pháp HA chính thức từ Oracle, khuyến nghị cho MySQL 8.0 mới.

## 1. Kiến trúc & ports

```
            ┌────────────────────────┐
   App ──▶  │  MySQL Router (6446)   │── RW ──▶ Primary
            │  MySQL Router (6447)   │── RO ──▶ Secondaries (round-robin)
            └────────────────────────┘
                       │
       ┌───────────────┼───────────────┐
       ▼               ▼               ▼
   node1:3306      node2:3306      node3:3306
   :33061  ◀── Group Replication channel ──▶
```

- 3306: SQL
- 33060: X-Protocol (mysqlsh dùng)
- 33061: Group Replication

## 2. Tiền đề

- 3 nodes đã chạy `common/00-prepare-os.sh`, `01-install-mysql.sh`, `02-firewall.sh`.
- `gtid_mode=ON`, `enforce_gtid_consistency=ON`, `log_bin=ON`, `binlog_format=ROW`, `server_id` khác nhau (script common đã làm).
- Hostname resolution OK (kiểm `getent hosts node2`).

## 3. Các bước

### B1. Configure instance (chạy trên CẢ 3 nodes)
```bash
bash scripts/innodb-cluster/node-setup.sh
```
Script tạo user `clusteradmin`, gọi `dba.configureInstance(...)` — Shell sẽ tự thêm các option vào `mysqld-auto.cnf` và restart nếu cần.

### B2. Bootstrap cluster (chạy CHỈ trên node1)
```bash
bash scripts/innodb-cluster/cluster-bootstrap.sh
```
Lần lượt: `dba.createCluster(...)` → `addInstance(node2, recoveryMethod='clone')` → `addInstance(node3, recoveryMethod='clone')`.

> `recoveryMethod='clone'` dùng **Clone Plugin** copy dữ liệu từ donor — không cần xtrabackup hay dump. Yêu cầu MySQL ≥ 8.0.17.

### B3. Setup MySQL Router (trên mgmt hoặc app host)
```bash
bash scripts/innodb-cluster/router-setup.sh
```
Router tự lấy metadata cluster từ node1, sinh config, mở 6446 (RW) và 6447 (RO).

### B4. Verify
```bash
mysqlsh --uri="clusteradmin:${ADMIN_PWD}@192.168.10.11" \
  -e "print(JSON.stringify(dba.getCluster('myCluster').status(),null,2));"
```
Kỳ vọng: 1 PRIMARY, 2 SECONDARY, tất cả `status: "ONLINE"`, `clusterErrors: []`.

App test:
```bash
mysql -uappuser -p -h<router-host> -P6446 -e "SELECT @@hostname"   # luôn ra primary
mysql -uappuser -p -h<router-host> -P6447 -e "SELECT @@hostname"   # round-robin secondaries
```

## 4. Vận hành

| Tác vụ | Lệnh |
|---|---|
| Xem trạng thái | `bash scripts/innodb-cluster/cluster-ops.sh status` |
| Chuyển primary | `bash scripts/innodb-cluster/cluster-ops.sh switch 192.168.10.12` |
| Rejoin node lỗi | `bash scripts/innodb-cluster/cluster-ops.sh rejoin 192.168.10.13` |
| Rescan (sau đổi topology) | `bash scripts/innodb-cluster/cluster-ops.sh rescan` |
| Cluster chết hoàn toàn | `bash scripts/innodb-cluster/cluster-ops.sh reboot-from-outage` |

### 4.1 Tự động failover
Mặc định Group Replication tự bầu primary mới khi primary cũ chết. Router phát hiện qua metadata và route lại ≤ vài giây — **app không cần biết IP mới**.

### 4.2 Thêm node thứ 4
```js
// trong mysqlsh, connect tới primary hiện tại
dba.getCluster('myCluster').addInstance('clusteradmin@node4:3306', {recoveryMethod:'clone'});
```

### 4.3 Loại node ra
```js
dba.getCluster('myCluster').removeInstance('clusteradmin@node3:3306');
```

### 4.4 Group quorum bị mất (chỉ còn 1 node sống trong cluster 3 node)
Group sẽ **block writes**. Khắc phục:
```js
dba.getCluster('myCluster').forceQuorumUsingPartitionOf('clusteradmin@node1:3306');
```

## 5. Rollback / tháo cluster

```js
dba.getCluster('myCluster').dissolve({force:true});
```
Sau đó tắt Router service: `systemctl stop mysqlrouter`.

## 6. Lưu ý quan trọng

- **Tối thiểu 3 nodes** để có quorum chống split-brain. Với 2 nodes cần dùng arbitrator.
- Group Replication yêu cầu tất cả bảng có **primary key**. Tools như pt-online-schema-change tạo trigger — cần version mới hỗ trợ.
- Tránh `ALTER TABLE` lớn trong giờ peak — bị serialize qua group.
- Latency mạng giữa các node nên ≤ 5ms (LAN). Cross-region cần dùng async secondary cluster (ClusterSet).

## 7. Tham khảo
- https://dev.mysql.com/doc/mysql-shell/8.0/en/mysql-innodb-cluster.html
- https://dev.mysql.com/doc/refman/8.0/en/group-replication.html


---

!!! info "Nguồn gốc"
    `HA/Mysql/runbooks/02-mysql-innodb-cluster.md`
