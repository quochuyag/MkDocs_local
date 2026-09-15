---
title: 'Demo — Sharded Cluster (1 path: Vagrant)'
course: 06-high-availability
source: HA/mongo/demo/sharded-cluster/README.md
---

# Demo — Sharded Cluster (1 path: Vagrant)

Giải pháp **horizontal scale** trong toolkit: 1 shard (RS 3 nodes) + 1 config server (RS 3 nodes) + 1 mongos router. Demo này chỉ có 1 path Vagrant (không có Docker Compose path vì sharded cluster cần multi-instance/multi-network phức tạp hơn).

| Path | Setup | RAM | Mục tiêu |
|---|---|---|---|
| [**Vagrant lab tự động**](vagrant-lab/) | ~12-15 phút | ~10 GB | Hiểu sâu Sharding + mongos + config server |

**Fully automated** — `.\demo.ps1` (Windows) hoặc `make demo` (Linux/macOS/Git Bash) là xong. Không cần thao tác thủ công giữa các bước.

## Khi nào dùng demo này

- Hiểu sự khác biệt giữa Replica Set thuần (Runbook 01) và Sharded Cluster (Runbook 03)
- Test shard primary failover + mongos auto re-route
- Quan sát chunk distribution với hashed shard key
- Test thêm shard / drain shard (advanced — xem Runbook 03 §5)

❌ **KHÔNG nên dùng** sharded cluster nếu:

- Dataset < 500 GB và write < 10k/sec → Replica Set là đủ ([../replica-set/](../replica-set/))
- Lab mục tiêu chỉ học HA cơ bản → Replica Set đơn giản và rẻ hơn

## Quick start

```powershell
cd demo\sharded-cluster\vagrant-lab
.\demo.ps1                # full pipeline: keyfile + up + smoke + logs dump
.\demo.ps1 failover       # demo shard primary failover
```

Xem chi tiết tại [vagrant-lab/README.md](vagrant-lab/readme.md).

## So sánh với Replica Set demo

| | Replica Set demo | Sharded Cluster demo (đây) |
|---|---|---|
| VMs | 3 (rs-node1/2/3) | 4 (sc-node1/2/3 + sc-mgmt) |
| RAM | ~6 GB | ~10 GB |
| mongod instances | 1 mỗi VM (3 tổng) | 2 mỗi data VM + 1 mongos (7 tổng) |
| Subnet | 192.168.30.0/24 | 192.168.40.0/24 |
| App connect | `mongodb://...@rs-node1,rs-node2,rs-node3:27017/?replicaSet=rs0` | `mongodb://...@sc-mgmt:27017/appdb` (không có `replicaSet` param) |
| Failover | Election trong RS | Election trong từng shard + mongos re-route |
| Scale-out | Vertical (RAM + CPU) | Horizontal (thêm shard) |
| Best for | App < 500 GB, < 10k writes/sec | App > 1 TB hoặc cần horizontal scale |

## Tham khảo

- [Runbook 03 — Sharded Cluster](../../runbooks/003-sharded-cluster.md) — runbook gốc, chi tiết kiến trúc + vận hành.
- [demo/replica-set/](../replica-set/) — demo Replica Set PSS đơn giản hơn (3 VMs).
- [vagrant/](../../vagrant/) — main lab Vagrant chạy được mọi Runbook 01-06.


---

!!! info "Nguồn gốc"
    `HA/mongo/demo/sharded-cluster/README.md`
