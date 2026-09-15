---
title: Bước 9 — Rollback / Destroy
course: 06-high-availability
source: HA/Mysql/demo/01-async-semisync/09-rollback.md
---

# Bước 9 — Rollback / Destroy

## Mục tiêu
Cho phép quay về trạng thái sạch sau khi demo. Có 2 cấp:

| Mode | Hành động | Khi nào dùng |
|------|-----------|--------------|
| `soft` (mặc định) | Trên MySQL: STOP REPLICA, UNINSTALL PLUGIN, DROP smoke_db, xoá `zz-semisync.cnf`. **Giữ VMs.** | Demo lại nhiều lần mà không cần re-install MySQL |
| `hard` | `vagrant destroy -f` + xoá SSH key sinh động. **Xoá toàn bộ.** | Kết thúc workshop |

## Cách chạy

```bash
# Soft rollback — chỉ tháo replication, giữ VMs
bash demo/01-async-semisync/09-rollback.sh

# Hard rollback — xoá hết VMs
MODE=hard bash demo/01-async-semisync/09-rollback.sh
```

## Soft rollback chi tiết

| Node | Action |
|------|--------|
| node2, node3 | `STOP REPLICA; RESET REPLICA ALL; SET GLOBAL super_read_only=0; SET GLOBAL read_only=0; UNINSTALL PLUGIN rpl_semi_sync_replica;` |
| node1 | `SET GLOBAL rpl_semi_sync_source_enabled=0; UNINSTALL PLUGIN rpl_semi_sync_source; DROP DATABASE IF EXISTS smoke_db;` |
| All  | `rm -f /etc/mysql/mysql.conf.d/zz-semisync.cnf` |

Sau soft rollback: MySQL vẫn chạy, baseline config (server_id, gtid_mode...) giữ nguyên → có thể re-run từ bước 4.

## Hard rollback chi tiết

```bash
cd vagrant
vagrant destroy -f                                 # xoá VMs
rm -f provision/cluster_id_rsa provision/cluster_id_rsa.pub
```

Logs trong `demo/01-async-semisync/results/` **không bị xoá** — phục vụ báo cáo.

## Verify sau rollback

### Soft:
```bash
vagrant ssh node1 -c "mysql -uroot -p'ChangeMe!Root#2026' -e \"
  SHOW PLUGINS;
  SHOW DATABASES;\"" | grep -E 'semi_sync|smoke_db' || echo 'CLEAN'
```

### Hard:
```bash
vagrant status   # all should report 'not created (virtualbox)'
```


---

!!! info "Nguồn gốc"
    `HA/Mysql/demo/01-async-semisync/09-rollback.md`
