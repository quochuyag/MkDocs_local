---
title: 00 — Tổng quan bài demo
course: 06-high-availability
source: HA/Mysql/demo/06-galera/00-overview.md
---

# 00 — Tổng quan bài demo

## Mục tiêu

Chứng minh giải pháp HA **Galera Cluster (Percona XtraDB Cluster 8.0)**:
1. Cài PXC 8.0 từ Percona repo trên 3 nodes (không dùng MySQL community).
2. Bootstrap node1 bằng `mysql@bootstrap.service` — chỉ 1 lần duy nhất.
3. Join node2, node3 — SST tự động từ donor (xtrabackup-v2 stream).
4. Verify 3 ONLINE + Synced + Primary status qua `wsrep_*`.
5. Chứng minh **mọi node đều writable** + data consistency.
6. Demo split brain: halt 2/3 node → node còn lại chuyển sang non-Primary (block writes).

## Kiến trúc

- **PXC = MySQL fork bởi Percona + Galera wsrep plugin**:
  - port 3306 — client (như MySQL bình thường)
  - port 4567 — gcomm (group communication)
  - port 4568 — IST (Incremental State Transfer)
  - port 4444 — SST (full State Snapshot Transfer qua xtrabackup-v2)
- **Cert-based replication**: mọi node nhận write request → tạo write-set → broadcast → mọi node certify song song → commit nếu pass cert (không conflict).
- **wsrep_provider**: libgalera_smm.so — quản lý protocol replication.
- **pxc_strict_mode=ENFORCING**: ép user dùng các pattern đúng (InnoDB only, PK, autoinc_lock_mode=2, ...).

## Phạm vi demo

| Có | Không |
|----|-------|
| Sync multi-master, mọi node writable | WAN deployment (latency cao → fail) |
| Auto-recovery khi 1 node restart | Auto split-brain resolution (cần can thiệp `pc.bootstrap`) |
| Test consistency parallel writes | Sysbench performance benchmark |
| Demo split-brain behaviour | MariaDB Galera (chỉ test PXC) |

## Tiêu chí thành công

| # | Tiêu chí | Cách kiểm tra |
|---|----------|---------------|
| 1 | 4 VMs running, ping nội bộ OK | `vagrant status`, ping test |
| 2 | PXC 8.0 cài thành công trên 3 nodes | `dpkg -l \| grep percona-xtradb-cluster` |
| 3 | node1 bootstrap OK (`wsrep_cluster_size=1` rồi `=3` sau join) | `SHOW STATUS LIKE 'wsrep_cluster_size';` |
| 4 | `wsrep_local_state_comment=Synced` trên cả 3 node | `SHOW STATUS LIKE 'wsrep_local_state_comment';` |
| 5 | `wsrep_cluster_status=Primary` trên cả 3 node | `SHOW STATUS LIKE 'wsrep_cluster_status';` |
| 6 | INSERT trên node1, SELECT trên node2/3 < 50ms (sync) | smoke test |
| 7 | Parallel INSERT trên 3 node — count đồng nhất | smoke test consistency |
| 8 | Halt 2 node → node còn lại `wsrep_cluster_status=non-Primary` | split-brain test |

## Thời gian ước tính

| Pha | Thời gian |
|-----|-----------|
| `vagrant up` lần đầu | 10–15 phút |
| Prepare OS | 2 phút |
| Install PXC (3 nodes, ~250 MB / node) | 8–12 phút |
| Bootstrap + join | 2 phút |
| Verify + smoke test | 1 phút |
| Split-brain test | 2 phút |
| **Tổng** | **~28–35 phút** |

## Lưu ý quan trọng

- **Mỗi bảng PHẢI có primary key** (Galera certify yêu cầu).
- **InnoDB only** cho write (MyISAM read-only nếu cần).
- `innodb_autoinc_lock_mode=2` bắt buộc.
- Tránh `LOCK TABLES`, `GET_LOCK()`, table-level locks.
- App nên retry trên `ER_LOCK_DEADLOCK` (1213) — certification fail tạo lock_deadlock.
- DDL: TOI mode block cluster ngắn. Dùng RSU cho DDL dài (alter table lớn).


---

!!! info "Nguồn gốc"
    `HA/Mysql/demo/06-galera/00-overview.md`
