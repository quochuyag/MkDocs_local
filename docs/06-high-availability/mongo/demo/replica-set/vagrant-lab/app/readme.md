---
title: load-data — app push test data vào Replica Set rs0
course: 06-high-availability
source: HA/mongo/demo/replica-set/vagrant-lab/app/README.md
---

# load-data — app push test data vào Replica Set rs0

Hai chế độ:
- **CLI** (`load-data.py`) — bulk insert nhanh, dùng cho script/automation
- **GUI** (`ui/server.py`) — web console real-time, chọn kịch bản / target node, có animation

Dùng để:
- Test throughput insert / replication lag
- Chuẩn bị dataset trước khi demo failover / oplog window
- Đo dung lượng disk / index size
- Demo cho người không quen mongosh

## Cài đặt

```powershell
cd demo\replica-set\vagrant-lab\app
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

Yêu cầu: Python 3.10+, replica set đã `vagrant up` (xem `..\demo.ps1`).

## GUI web console

```powershell
python ui\server.py
# Tự mở browser tại http://localhost:5000
# (đổi port: $env:PORT=5050; python ui\server.py)
```

Tính năng:
- **4 kịch bản** có sẵn — chọn bằng card visual:
  - 🛒 E-commerce events (purchase / cart / view / login)
  - 📡 IoT sensor data (telemetry + geolocation)
  - 📋 Application logs (level / service / trace_id)
  - 👤 User profiles (signup)
- **Target node** — chọn:
  - `Auto` (mặc định) — replica set tự route tới PRIMARY
  - `rs-node1/2/3` — direct connection tới node cụ thể (write tới SECONDARY sẽ fail với `NotWritablePrimary`, hữu ích để demo)
- **Số lượng** — input + quick buttons 1K / 10K / 100K / 500K / 1M
- **Write concern** — majority (safe) / w=1 (fast) / w=0 (fire&forget)
- **Real-time SSE stream** — progress bar smooth, live counter, 3 docs mới nhất mỗi batch hiển thị dạng card animate slideIn
- **STOP** — cancel job giữa chừng
- **Cluster status** — top bar refresh 5s, hiển thị PRIMARY hiện tại

API endpoints (cho integration):

| Endpoint | Mô tả |
|---|---|
| `GET  /api/status`          | replica set state (set name, primary, members) |
| `POST /api/load`            | start job — body `{scenario,target,count,batch,write_concern,drop}` → trả `job_id` |
| `GET  /api/stream/<job_id>` | SSE stream progress events |
| `POST /api/cancel/<job_id>` | cancel job đang chạy |
| `GET  /api/recent`          | 10 docs mới nhất (sort seq DESC) |

## CLI (`load-data.py`)

```powershell
# 10,000 docs (mặc định)
python load-data.py

# 100k docs với 4 workers, batch 2000
python load-data.py --count 100000 --batch 2000 --workers 4

# 1 triệu docs, drop cũ, write concern nhanh w=1
python load-data.py --count 1000000 --drop --write-concern 1

# Connection string tuỳ biến
python load-data.py --uri "mongodb://appuser:DemoApp%232026@192.168.30.11:27017/demo?replicaSet=rs0"
```

## Tham số

| Flag | Mặc định | Mô tả |
|---|---|---|
| `--count`         | 10000   | Tổng documents cần insert |
| `--batch`         | 1000    | Batch size cho mỗi `insertMany` |
| `--workers`       | 4       | Số thread chạy song song |
| `--write-concern` | majority | `w` parameter (`1` nhanh, `majority` an toàn) |
| `--drop`          | off     | Drop collection trước khi insert |
| `--no-index`      | off     | Bỏ qua bước tạo index sau insert |
| `--db`            | demo    | Database |
| `--collection`    | loadtest | Collection |
| `--uri`           | (xem code) | MongoDB connection URI |

## Schema document mẫu

```json
{
  "_id":        ObjectId,
  "seq":        12345,
  "type":       "purchase|view|login|...",
  "user_id":    "user-00321",
  "session_id": "a1b2c3d4...",
  "ts":         ISODate,
  "ip":         "192.168.x.y",
  "page":       "/products",
  "product_id": "prod-0042",   // chỉ với purchase/cart_*
  "amount":     42.50          // chỉ với purchase/cart_*
}
```

Doc trung bình ~200–300 bytes → 1M docs ≈ 250 MB data + index.

## Throughput tham khảo (laptop i7-10875H, 1 vCPU/VM, w=majority)

| Count | Time   | Rate     |
|---|---|---|
| 10,000    | ~3s    | ~3,000 docs/s |
| 100,000   | ~30s   | ~3,300 docs/s |
| 1,000,000 | ~5–8 min | ~2,500 docs/s |

Tăng `--workers` và dùng `--write-concern 1` để đẩy nhanh khi không cần durability.

## Verify

```powershell
# Đếm trên PRIMARY
.\..\demo.ps1 ssh node1
mongosh -u admin -p 'DemoAdmin#2026' --authenticationDatabase admin \
  --eval 'print(db.getSiblingDB("demo").loadtest.countDocuments({}))'

# Đếm trên SECONDARY (verify replication)
.\..\demo.ps1 ssh node2
mongosh -u admin -p 'DemoAdmin#2026' --authenticationDatabase admin \
  --eval 'db.getMongo().setReadPref("secondary");
          print(db.getSiblingDB("demo").loadtest.countDocuments({}))'
```


---

!!! info "Nguồn gốc"
    `HA/mongo/demo/replica-set/vagrant-lab/app/README.md`
