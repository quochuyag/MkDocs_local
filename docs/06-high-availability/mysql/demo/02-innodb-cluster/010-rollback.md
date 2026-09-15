---
title: Bước 10 — Rollback / Destroy
course: 06-high-availability
source: HA/Mysql/demo/02-innodb-cluster/10-rollback.md
---

# Bước 10 — Rollback / Destroy

## Mục tiêu
Cho phép quay về trạng thái sạch sau khi demo. Có 2 cấp:

| Mode | Hành động | Khi nào dùng |
|------|-----------|--------------|
| `soft` (mặc định) | `cluster.dissolve()`; stop + disable mysqlrouter; drop `smoke_db`; xoá `mysqlrouter.conf` của mgmt. **Giữ VMs.** | Demo lại nhiều lần mà không cần re-install MySQL |
| `hard` | `vagrant destroy -f` + xoá SSH key. **Xoá toàn bộ.** | Kết thúc workshop |

## Cách chạy

```bash
# Soft rollback — chỉ tháo cluster, giữ VMs
bash demo/02-innodb-cluster/10-rollback.sh

# Hard rollback — xoá hết VMs
MODE=hard bash demo/02-innodb-cluster/10-rollback.sh
```

## Soft rollback chi tiết

| Node | Action |
|------|--------|
| mgmt | `systemctl stop + disable mysqlrouter`; xoá `/var/lib/mysqlrouter/` |
| node1 (PRIMARY hoặc bất kỳ ONLINE) | `mysqlsh ... -e "dba.getCluster('myCluster').dissolve({force:true})"` → leave group trên 3 node + drop metadata schema |
| node1/2/3 | `DROP DATABASE IF EXISTS smoke_db;` |

Sau soft rollback:
- MySQL vẫn chạy, các cấu hình baseline (server_id, gtid_mode, plugin clone…) giữ nguyên.
- `clusteradmin` user vẫn còn → có thể re-run từ bước 5 (`cluster-bootstrap.sh`) ngay.
- Router service tắt; muốn dùng lại phải re-bootstrap (B6).

## Hard rollback chi tiết

```bash
cd vagrant
vagrant destroy -f
rm -f provision/cluster_id_rsa provision/cluster_id_rsa.pub
```

Logs trong `demo/02-innodb-cluster/results/` **không bị xoá** — phục vụ báo cáo.

## Verify sau rollback

### Soft:
```bash
# Cluster đã dissolve?
vagrant ssh node1 -c "mysqlsh --uri='clusteradmin:ChangeMe!Admin#2026@127.0.0.1:3306' \
  -e \"try{ dba.getCluster('myCluster'); print('STILL EXISTS'); }catch(e){ print('DISSOLVED OK'); }\""

# Router không còn chạy?
vagrant ssh mgmt -c "sudo systemctl is-active mysqlrouter || echo 'mysqlrouter not active (OK)'"

# smoke_db đã drop?
vagrant ssh node1 -c "mysql -uroot -p'ChangeMe!Root#2026' -e 'SHOW DATABASES;' | grep -E 'smoke_db|mysql_innodb_cluster_metadata' || echo 'CLEAN'"
```

### Hard:
```bash
vagrant status   # all 'not created (virtualbox)'
```

## Lỗi thường gặp

| Hiện tượng | Khắc phục |
|------------|-----------|
| `dissolve` báo "No quorum" | Một số node halt. Chạy `vagrant up <halted>` trước khi dissolve. Hoặc dùng `dba.dropMetadataSchema({force:true})` trên 1 node sống + STOP GROUP_REPLICATION thủ công các node còn lại. |
| `Router service masked` | `sudo systemctl unmask mysqlrouter && sudo systemctl reset-failed mysqlrouter` |
| Halted node up lại nhưng vẫn báo "metadata schema not found" | Đúng — sau dissolve thì metadata bị xoá. Để re-bootstrap, chạy lại B5. |


---

!!! info "Nguồn gốc"
    `HA/Mysql/demo/02-innodb-cluster/10-rollback.md`
