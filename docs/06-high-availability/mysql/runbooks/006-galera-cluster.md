---
title: Runbook 06 — Galera Cluster (Percona XtraDB Cluster 8.0)
course: 06-high-availability
source: HA/Mysql/runbooks/06-galera-cluster.md
---

# Runbook 06 — Galera Cluster (Percona XtraDB Cluster 8.0)

Galera = **synchronous multi-master**: mọi node đều writable, transaction commit chỉ khi quorum certify thành công ⇒ không có replication lag, không cần failover. Trade-off: latency cao hơn async, write throughput bị giới hạn bởi node chậm nhất, không phù hợp WAN.

Có 3 distribution chính:
- **Percona XtraDB Cluster (PXC)** — runbook này dùng.
- **MariaDB Galera Cluster** — gần như tương đương về flow.
- **Codership Galera** thuần (ít dùng).

## 1. Kiến trúc & ports

```
node1:3306 ◀──gcomm:4567──▶ node2:3306 ◀──gcomm:4567──▶ node3:3306
                            (cert-based replication)
   SST: 4444   (full state snapshot khi join lần đầu)
   IST: 4568   (incremental state khi node tụt 1 đoạn)
```

## 2. Tiền đề

- 3 nodes Linux, đã chạy `common/00-prepare-os.sh`.
- **KHÔNG** chạy `01-install-mysql.sh` của MySQL community — PXC thay thế hẳn package này.
- Latency LAN ≤ 5ms khuyến nghị.

## 3. Các bước

### B1. Cài PXC trên CẢ 3 nodes
```bash
bash scripts/galera/install-pxc.sh
```
Script cài `percona-xtradb-cluster` từ repo Percona, ghi `zz-pxc.cnf` (wsrep_provider, gcomm address, cluster name, sst_method=xtrabackup-v2, pxc_strict_mode=ENFORCING), **KHÔNG start** dịch vụ.

### B2. Bootstrap node1
```bash
bash scripts/galera/bootstrap-node.sh
```
Tương đương `systemctl start mysql@bootstrap.service` — chỉ làm 1 lần. Sau đó tạo user `sstuser` cho xtrabackup SST.

### B3. Join node2 + node3
```bash
# trên node2 và node3
bash scripts/galera/join-node.sh
```
Lần đầu join: xtrabackup streaming dữ liệu từ donor sang joiner (SST). Theo dõi:
```sql
SHOW STATUS LIKE 'wsrep_local_state_comment';
-- Joiner → Donor/Desynced → Joined → Synced
```

### B4. Verify
```sql
SHOW STATUS LIKE 'wsrep_cluster_size';            -- 3
SHOW STATUS LIKE 'wsrep_local_state_comment';     -- Synced
SHOW STATUS LIKE 'wsrep_cluster_status';          -- Primary
SHOW STATUS LIKE 'wsrep_connected';               -- ON
SHOW STATUS LIKE 'wsrep_ready';                   -- ON
SHOW STATUS LIKE 'wsrep_local_commits';           -- tăng theo write
```

## 4. Vận hành

### 4.1 Add node mới
- Cài PXC trên node4 với cùng `wsrep_cluster_address=gcomm://node1,node2,node3,node4`.
- `systemctl start mysql` — tự SST từ donor.
- Update config cùng `wsrep_cluster_address` trên các node hiện hữu để khi restart vẫn thấy node4.

### 4.2 Rolling restart (đổi config)
Mỗi lần 1 node, lần lượt:
```bash
systemctl stop mysql                              # node rời cluster (cluster_size -= 1)
# sửa config
systemctl start mysql                             # tự IST hoặc SST tuỳ delta
# đợi Synced
```

### 4.3 Full cluster shutdown — graceful
Tắt thứ tự bất kỳ. Node tắt cuối cùng sẽ là "most up-to-date" → cần là node bootstrap lần kế tiếp.

### 4.4 Recover sau full outage
Xem `scripts/galera/recover-split-brain.sh`. Tóm tắt:
1. Trên mỗi node, xem `/var/lib/mysql/grastate.dat`:
   ```
   seqno: <số>
   safe_to_bootstrap: 0 hoặc 1
   ```
2. Nếu `seqno=-1` → chạy `mysqld_safe --wsrep-recover` xem log lấy seqno thật.
3. Node có seqno cao nhất: sửa `safe_to_bootstrap: 1`.
4. Trên node đó: `systemctl start mysql@bootstrap.service`.
5. Trên các node khác: `systemctl start mysql` để join.

### 4.5 Split-brain (50/50 partition)
Galera tự shutdown bên thiểu số (non-Primary). Khi mạng phục hồi, bên thiểu số tự rejoin. Nếu cluster còn ≤ 1 node mà cần lên cấp:
```sql
SET GLOBAL wsrep_provider_options='pc.bootstrap=true';
```

## 5. Lưu ý quan trọng

- **Mỗi bảng phải có primary key** (Galera certify yêu cầu).
- **InnoDB only** (không MyISAM cho write).
- `innodb_autoinc_lock_mode=2` — bắt buộc.
- Tránh `LOCK TABLES`, `GET_LOCK()`, table-level lock.
- Long-running transactions có thể bị abort do certification fail — design app để retry trên `ER_LOCK_DEADLOCK` (1213).
- DDL: dùng `wsrep_OSU_method=TOI` (mặc định, block cluster) hoặc `RSU` (rolling — chậm hơn nhưng không block).
- **Không** trộn PXC 8.0 với MariaDB Galera trong cùng cluster (wire protocol khác).

## 6. Rollback / tháo

```bash
systemctl stop mysql
apt-get remove --purge percona-xtradb-cluster*
rm -rf /var/lib/mysql /etc/mysql/mysql.conf.d/zz-pxc.cnf
```

## 7. Tham khảo
- https://www.percona.com/doc/percona-xtradb-cluster/8.0/install/index.html
- https://galeracluster.com/library/documentation/


---

!!! info "Nguồn gốc"
    `HA/Mysql/runbooks/06-galera-cluster.md`
