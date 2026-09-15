---
title: Demo — Replica Set PSS (2 paths)
course: 06-high-availability
source: HA/mongo/demo/replica-set/README.md
---

# Demo — Replica Set PSS (2 paths)

Giải pháp **đơn giản nhất** trong toolkit: Replica Set 3-node. Có 2 cách chạy demo, chọn theo mục tiêu:

| Path | Setup | RAM | Mục tiêu |
|---|---|---|---|
| [Docker Compose](#path-a--docker-compose-nhanh-nhất) (file trong folder này) | ~1 phút | ~1.5 GB | Smoke test, demo nhanh, CI |
| [**Vagrant lab tự động**](vagrant-lab/) (folder con) | ~10 phút | ~6 GB | Hiểu sâu HA, VM Ubuntu thật |

Cả 2 đều **fully automated** — không cần thao tác thủ công giữa các bước.

## Path A — Docker Compose (nhanh nhất)

## Yêu cầu

- **Docker Desktop** trên Windows/macOS, hoặc Docker engine trên Linux.
- 2 GB RAM rảnh (3 containers ~ 500MB mỗi cái).
- Bash (Git Bash trên Windows, hoặc WSL).

## Quick start (3 lệnh)

```bash
cd demo/replica-set

# 1. Sinh shared keyfile (1 lần)
openssl rand -base64 756 > keyfile && chmod 400 keyfile

# 2. Start 3 mongod containers
docker compose up -d

# 3. Initiate replica set + tạo users + insert sample data
bash init-rs.sh
```

Expected output bước 3: trạng thái 3 nodes, 1 PRIMARY + 2 SECONDARY, 5 documents replicate.

## Test failover (1 lệnh)

```bash
bash demo-failover.sh
```

Script tự:
1. Phát hiện PRIMARY hiện tại
2. `docker stop` container primary
3. Đợi election ~15 giây
4. Show PRIMARY mới, insert document mới
5. `docker start` container cũ, verify rejoin

## Cleanup

```bash
docker compose down -v       # stop + xoá data volumes
```

## Sau khi xong, kết nối từ bên ngoài

Từ máy host, các port đã expose:

| Container | Host port | URI sample |
|---|---|---|
| mongo1 | 27017 | `mongodb://admin:DemoAdmin#2026@localhost:27017/admin?replicaSet=rs0` |
| mongo2 | 27018 | (secondary) |
| mongo3 | 27019 | (secondary) |

App connection string khuyến nghị (driver tự discover topology):

```text
mongodb://appuser:DemoApp#2026@localhost:27017,localhost:27018,localhost:27019/demo?replicaSet=rs0
```

⚠ **Lưu ý** từ host kết nối: hostname trong replica set là `mongo1/2/3` (Docker DNS), không phải `localhost`. Driver từ host sẽ resolve fail. Cách workaround:

- Chạy mongosh trong container: `docker exec -it mongo1 mongosh ...`
- Hoặc thêm vào file hosts của Windows (`C:\Windows\System32\drivers\etc\hosts`):
  ```text
  127.0.0.1 mongo1
  127.0.0.1 mongo2
  127.0.0.1 mongo3
  ```

## So sánh với Vagrant lab (Runbook 08)

| | Docker Compose demo | Vagrant lab |
|---|---|---|
| Bootstrap time | ~1 phút | ~10-15 phút |
| RAM cần | ~1.5 GB | ~9 GB |
| Realistic | 3 containers cùng host | 4 VMs Ubuntu giống prod |
| Networking | Docker bridge | Host-only network 192.168.20.0/24 |
| Filesystem | Docker volumes | Ext4 trên VM |
| Phù hợp | Smoke test, demo, CI | Đầy đủ production-like |

**Demo này** = học khái niệm + chứng minh failover hoạt động.
**Vagrant lab** = lab production-like để chạy mọi Runbook 01-06.

## Nội dung file

| File | Mục đích |
|---|---|
| [docker-compose.yml](docker-compose.yml) | 3 mongod 7.0 với keyFile, replSet=rs0 |
| [init-rs.sh](init-rs.sh) | 7 bước: initiate → đợi primary → tạo users → insert data → verify |
| [demo-failover.sh](demo-failover.sh) | 6 bước: stop primary → đợi election → insert → start lại → verify rejoin |
| keyfile | Sinh local 1 lần bằng `openssl rand -base64 756`, KHÔNG commit |


---

!!! info "Nguồn gốc"
    `HA/mongo/demo/replica-set/README.md`
