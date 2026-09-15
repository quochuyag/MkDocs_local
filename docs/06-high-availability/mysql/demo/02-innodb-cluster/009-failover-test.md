---
title: 'Bước 9 — Auto-failover test: halt primary, Router tự reroute'
course: 06-high-availability
source: HA/Mysql/demo/02-innodb-cluster/09-failover-test.md
---

# Bước 9 — Auto-failover test: halt primary, Router tự reroute

## Mục tiêu
Mô phỏng primary chết bằng `vagrant halt --force <primary>`. Group Replication **tự bầu** primary mới (1 trong 2 secondary còn lại). Router phát hiện qua metadata và **tự reroute** :6446 đến primary mới — **app không cần đổi IP**.

> **Cảnh báo**: bước này halt 1 VM thật. Sau khi xong, chạy [10-rollback.sh](10-rollback.sh) hoặc `vagrant up <node-bị-halt>` + `cluster.rejoinInstance()` để khôi phục.

## Cách chạy

```bash
bash demo/02-innodb-cluster/09-failover-test.sh
```

## Kịch bản

| Step | Action | Verify |
|------|--------|--------|
| 1 | Identify primary qua `cluster.status()` | `PRIMARY_HOST = node1/2/3` |
| 2 | Insert "sentinel row" qua `mgmt:6446` | Cả 3 node thấy được trước khi halt |
| 3 | `vagrant halt --force <PRIMARY_HOST>` | VM stop |
| 4 | Poll `cluster.status()` qua secondary còn sống | `topology[primary].status = UNREACHABLE`; sau ~5-10s có node mới `memberRole=PRIMARY` |
| 5 | Đo RTO: từ halt → :6446 chấp nhận write trở lại | Insert thành công qua `mgmt:6446` |
| 6 | Write 50 row mới qua `mgmt:6446` | Insert OK, secondary còn lại đếm = 50 trong < 1s |
| 7 | (manual) `vagrant up <halted>` + `cluster.rejoinInstance(...)` | Member rejoin → ONLINE (Clone hoặc incremental) |

> **Khác biệt với demo 01**: ở demo 01 phải chạy `manual-failover.sh` tay (~20s RTO). Ở đây Router + GR làm hết — chỉ cần halt và đợi.

## Output

[results/09-failover.log](results/09-failover.log) gồm:
- Primary trước halt
- Sentinel row đã sync trước halt chưa
- Last cluster.status() trước halt
- Thời điểm halt → thời điểm có primary mới (`PROMOTE_RTO`)
- Thời điểm halt → thời điểm :6446 chấp nhận write (`WRITE_RTO`)
- Insert 50 row post-failover + verify secondary catch-up
- `FAILOVER_PASS=true/false`

## Kết quả mong đợi

```
[node1] primary trước halt
[mgmt:6446] sentinel id=201 inserted, all 3 nodes đã thấy
[host]   halting node1...
[poll]   cluster.status() từ node2: node1=UNREACHABLE, node2 hoặc node3 = NEW PRIMARY (sau ~6s)
[mgmt:6446] insert OK sau 8s kể từ halt (RTO ~ 8-15s)
[mgmt:6446] post-failover insert 50 rows: 0.4s
[secondary còn sống] saw 50 rows after 0.2s
FAILOVER_PASS=true PROMOTE_RTO=6s WRITE_RTO=8s
```

## Khôi phục node bị halt thành member của cluster (post-failover)

Khi node1 (giả sử đã halt) sống lại:

```bash
# 1) Start lại VM
vagrant up node1

# 2) Rejoin vào cluster — Shell tự dùng Clone Plugin nếu binlog đã bị purge
vagrant ssh node1 -c "mysqlsh --uri='clusteradmin:ChangeMe!Admin#2026@127.0.0.1:3306' \
  -e \"dba.getCluster('myCluster').rejoinInstance('clusteradmin@node1:3306', {password:'ChangeMe!Admin#2026'});\""

# 3) Verify
vagrant ssh node1 -c "mysqlsh --uri='clusteradmin:ChangeMe!Admin#2026@127.0.0.1:3306' \
  -e \"print(JSON.stringify(dba.getCluster('myCluster').status(),null,2));\""
```

Nếu rejoin fail (purged GTID gap), dùng:
```bash
vagrant ssh node1 -c "mysqlsh --uri='clusteradmin:ChangeMe!Admin#2026@127.0.0.1:3306' \
  -e \"dba.getCluster('myCluster').removeInstance('clusteradmin@node1:3306',{force:true});\""
vagrant ssh node1 -c "mysqlsh --uri='clusteradmin:ChangeMe!Admin#2026@127.0.0.1:3306' \
  -e \"dba.getCluster('myCluster').addInstance('clusteradmin@node1:3306',{password:'ChangeMe!Admin#2026',recoveryMethod:'clone'});\""
```

## Lỗi thường gặp

| Hiện tượng | Nguyên nhân | Khắc phục |
|------------|-------------|-----------|
| `cluster.status()` → `"NO_QUORUM"` | Bị halt quá nửa member | `dba.getCluster().forceQuorumUsingPartitionOf('clusteradmin@<surviving-host>:3306');` |
| Primary mới không nhận write trong > 30s | Đang apply queued transactions (`consistency: BEFORE_ON_PRIMARY_FAILOVER`) | Đợi. Hoặc giảm `consistency` xuống `EVENTUAL` (sẽ mất tail consistency) |
| Router `:6446` từ chối connect | Router cache metadata stale | Đợi 5-10s cho Router refresh; check `/var/lib/mysqlrouter/log/mysqlrouter.log` |
| Halted node up lại, rejoin tự động? | Không, GR mặc định không tự rejoin sau crash | Cần `cluster.rejoinInstance()` thủ công. Production: cấu hình `group_replication_start_on_boot=ON` + `auto-rejoin` logic |
| Sentinel row mất sau failover | `consistency: EVENTUAL` + commit chưa replicate kịp → primary cũ crash mất binlog | Trong demo dùng `BEFORE_ON_PRIMARY_FAILOVER` để giảm rủi ro |


---

!!! info "Nguồn gốc"
    `HA/Mysql/demo/02-innodb-cluster/09-failover-test.md`
