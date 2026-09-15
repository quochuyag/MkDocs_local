---
title: Runbook 07 — MongoDB Atlas (Managed)
course: 06-high-availability
source: HA/mongo/runbooks/07-atlas-managed.md
---

# Runbook 07 — MongoDB Atlas (Managed)

## 1. Khi nào dùng

✅ Phù hợp:
- Không có DBA chuyên trách.
- Cần multi-region < 1 ngày.
- Cần serverless / autoscaling.
- Budget OK với tier M10+ (~$60/tháng).

❌ Không phù hợp:
- Yêu cầu trên-prem strict (data sovereignty không cho phép cloud).
- Throughput cực lớn — chi phí Atlas leo nhanh, tự host rẻ hơn ở scale > 10TB.
- Cần custom build, custom plugins.

## 2. Tier & topology

| Tier | RAM | Storage | Use case | Giá ước tính |
|---|---|---|---|---|
| M0 (free) | 512 MB | 5 GB | Dev / POC | $0 |
| M10 | 2 GB | 10 GB | Small prod | ~$60/mo |
| M30 | 8 GB | 40 GB | Medium prod | ~$280/mo |
| M40+ | 16+ GB | 80+ GB | Large prod | $$$$ |
| Serverless | auto | auto | Bursty | Pay-per-op |

Mọi tier ≥ M10 mặc định **replica set 3 nodes**. Sharded cluster từ M30 trở lên (Global Clusters).

## 3. Setup nhanh (Atlas UI)

1. Account → Create Cluster → chọn region.
2. Network Access → IP Allowlist (thêm `0.0.0.0/0` cho lab; production: thêm CIDR app servers + VPC peering).
3. Database Access → Create user `appuser` với `readWrite@appdb`.
4. Connect → "Drivers" → copy connection string:
   ```
   mongodb+srv://appuser:<pwd>@cluster0.xxxxx.mongodb.net/appdb?retryWrites=true&w=majority
   ```

## 4. Setup qua Terraform (production)

```hcl
provider "mongodbatlas" {
  public_key  = var.atlas_public_key
  private_key = var.atlas_private_key
}

resource "mongodbatlas_cluster" "prod" {
  project_id   = var.project_id
  name         = "prod-cluster"
  cluster_type = "REPLICASET"

  provider_name               = "AWS"
  provider_instance_size_name = "M30"
  provider_region_name        = "AP_SOUTHEAST_1"

  mongo_db_major_version = "7.0"
  backup_enabled         = true
  pit_enabled            = true   # Point-in-time recovery

  replication_specs {
    num_shards = 1
    regions_config {
      region_name     = "AP_SOUTHEAST_1"
      electable_nodes = 3
      priority        = 7
      read_only_nodes = 0
    }
    # DR region:
    regions_config {
      region_name     = "AP_NORTHEAST_1"
      electable_nodes = 0
      priority        = 0
      read_only_nodes = 2
    }
  }
}
```

## 5. HA features Atlas đã bao gồm

| Feature | Default | Ghi chú |
|---|---|---|
| Automatic failover | Có | Election như RS tự host |
| Backup snapshots | M10+ | Continuous + on-demand |
| Point-in-time recovery | M10+ với `pit_enabled` | Granularity tới giây trong 24h gần nhất |
| TLS | Bắt buộc | Atlas tự rotate cert |
| Encryption at rest | Có | Optional với customer KMS |
| Cross-region replica | M10+ | UI 1-click |
| Auto-scaling tier | M10+ optional | RAM/disk tự scale theo workload |

## 6. Monitoring

Atlas UI có sẵn:
- Real-time metrics: ops/sec, replication lag, oplog window.
- Performance Advisor: gợi ý index missing.
- Profile slow queries.

Tích hợp Prometheus/Grafana qua **Atlas Metrics Integration** hoặc API endpoint:
```
https://cloud.mongodb.com/api/atlas/v1.0/groups/{groupId}/processes/{host}/measurements
```

## 7. Migration self-host → Atlas

1. **Atlas Live Migrate** (UI): nhập source connection string + target cluster → Atlas chạy initial sync + tail oplog → cut-over.
2. **mongomirror** (CLI) cho migration phức tạp / lọc collection.
3. **mongodump → mongorestore** cho dataset nhỏ < 100 GB (downtime).

## 8. Kết luận

Atlas thay thế Runbook 01-06 hoàn toàn nếu bạn chấp nhận trade-off: chi phí cao hơn nhưng không có ops overhead. Self-host (Runbook 01-06) là lựa chọn khi:
- Compliance bắt buộc on-prem.
- Scale cực lớn (cost optimization).
- Cần custom mongo build.

## 9. Tham khảo

- https://www.mongodb.com/docs/atlas/
- https://registry.terraform.io/providers/mongodb/mongodbatlas/latest/docs
- https://www.mongodb.com/docs/atlas/import/live-import/


---

!!! info "Nguồn gốc"
    `HA/mongo/runbooks/07-atlas-managed.md`
