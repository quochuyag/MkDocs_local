---
title: Runbook 00 — Overview & lựa chọn giải pháp HA cho MongoDB
course: 06-high-availability
source: HA/mongo/runbooks/00-overview.md
---

# Runbook 00 — Overview & lựa chọn giải pháp HA cho MongoDB

## 1. Matrix so sánh

| Đặc tính | Replica Set (PSS) | PSA | Sharded Cluster | Hidden/Delayed | Backup + PITR | Multi-region | Atlas |
|---|---|---|---|---|---|---|---|
| Loại | Native replication | Native (arbiter) | Horizontal scale + RS | DR/anti-mistake | Backup strategy | Geo-replication | Managed |
| Min nodes | 3 | 2 + 1 arbiter | 3 cfg + 3 shard + 1 mongos | +1 RS member | 1 backup host | ≥2 DCs | — |
| Auto-failover | Có (election) | Có (election, 2 voters mất quorum khi 1 data node + arbiter sống) | Có cho từng RS | — | — | Có nhưng giới hạn priority | Có (managed) |
| Write availability khi 1 node mất | OK (2/3 majority) | OK (1 data + arbiter = 2/3) | OK trong từng shard | — | — | Tuỳ priority | OK |
| Scale write | Single primary | Single primary | Multi shard | — | — | Single primary | Tùy tier |
| Sysadmin effort | ★ | ★★ | ★★★ | ★ | ★★ | ★★★ | ☆ |
| Khi nào nên | OLTP <500GB, 1 DC | Thiếu host thứ 3 | Dataset lớn hoặc throughput rất cao | Lỡ tay xoá data | Mọi prod | RPO/RTO geo | Không muốn ops |

## 2. Cây quyết định

```
Bạn cần HA cho MongoDB?
├─ Dataset < ~1 TB, 1 region đủ?
│   ├─ Có 3 host data → Replica Set PSS (Runbook 01) — DEFAULT
│   └─ Chỉ có 2 host data + 1 host rẻ → PSA (Runbook 02) [chấp nhận trade-off]
│
├─ Dataset > 1 TB hoặc write throughput vượt khả năng 1 primary?
│   └─ Sharded Cluster (Runbook 03) — 3 config + N shard RS + ≥1 mongos
│
├─ Cần phòng "xoá nhầm" hoặc cần snapshot logic 24h trước?
│   └─ Thêm Hidden + Delayed member (Runbook 04) lên RS hiện tại
│
├─ Cần RPO≈0 và PITR ≤1 phút?
│   └─ Backup snapshot + oplog tail (Runbook 05). Production: Percona PBM hoặc Ops Manager.
│
├─ Cần DR cross-region?
│   └─ Multi-region replica priority=0 (Runbook 06). Cluster lớn: zone sharding.
│
└─ Không muốn quản lý OS / mongod / backup?
    └─ Atlas managed (Runbook 07)
```

## 3. Khuyến nghị production

| Use case | Stack đề xuất |
|---|---|
| OLTP medium, 1 region, <1 TB | Replica Set PSS + delayed hidden + oplog tail backup |
| OLTP medium, 2 DCs limited | PSS với cross-DC priority=0 hidden member |
| OLTP rất lớn, multi-tenant | Sharded Cluster + zone sharding theo tenant region |
| Internal tool, không có DBA | Atlas M10+ managed |
| DR offsite | Snapshot (LVM/EBS) hàng giờ + oplog tail liên tục, PITR script test hàng tháng |

## 4. Chiến lược ramp

1. **Lab** (Runbook 08): `cd vagrant && make full-bootstrap` → 4 VMs Ubuntu 22.04.
2. Chạy lần lượt Runbook 01 → 03 → 04 → 05 → 06 trên cùng lab để hiểu trade-off.
   - Hoặc dùng demo labs độc lập: `demo/replica-set/`, `demo/sharded-cluster/`, `demo/hidden-delayed/`, `demo/backup-pitr/`, `demo/multi-region/`.
3. **Staging**: chọn 1 stack, chạy chaos (kill primary, network partition).
4. **Pre-prod**: load test với mgenerate / YCSB; đo failover time, oplog lag.
5. **Production**: rollout từng region, observability (mongodb_exporter + Grafana dashboards 2583/12079).

## 5. Observability mặc định

Mỗi runbook giả định bạn sẽ thêm:
- **mongodb_exporter** (Prometheus) trên mỗi node.
- Grafana dashboards: MongoDB Overview (2583), MongoDB Exporter (12079).
- Alert: `mongodb_up == 0`, `mongodb_mongod_replset_member_replication_lag > 60`, `mongodb_mongod_replset_member_state != 1 and != 2`, oplog window `< 24h`.

## 6. Cross-runbook constraints

- Replica Set PSS (Runbook 01) là **tiền đề** cho 04 (hidden/delayed), 05 (backup), 06 (multi-region).
- Sharded Cluster (03) là **mutually exclusive** với Replica Set thuần trên cùng port — runbook 03 dùng port 27018/27019, có thể coexist trên cùng VM cho lab.
- PSA (02) và PSS (01) không trộn — chọn 1 cho mỗi cluster.
- Atlas (07) thay thế tất cả runbook self-host — không kết hợp.


---

!!! info "Nguồn gốc"
    `HA/mongo/runbooks/00-overview.md`
