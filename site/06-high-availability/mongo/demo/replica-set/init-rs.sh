#!/usr/bin/env bash
# init-rs.sh — sau khi `docker compose up -d`, chạy script này để:
#   1. rs.initiate() với 3 members (mongo1 priority=2)
#   2. Đợi PRIMARY được bầu
#   3. Tạo admin + appuser
#   4. Insert sample data + verify replication
set -euo pipefail

# Mặc định password lab. Đổi nếu muốn:
ADMIN_PWD="${ADMIN_PWD:-DemoAdmin#2026}"
APP_PWD="${APP_PWD:-DemoApp#2026}"

run() { docker exec mongo1 mongosh --quiet --eval "$1"; }
run_auth() { docker exec mongo1 mongosh --quiet -u admin -p "${ADMIN_PWD}" --authenticationDatabase admin --eval "$1"; }

echo "==> B1: rs.initiate()"
run "
rs.initiate({
  _id: 'rs0',
  members: [
    { _id: 0, host: 'mongo1:27017', priority: 2 },
    { _id: 1, host: 'mongo2:27017', priority: 1 },
    { _id: 2, host: 'mongo3:27017', priority: 1 }
  ]
});
"

echo "==> B2: Đợi PRIMARY (max 30s)"
for i in {1..15}; do
  STATE=$(run 'rs.status().myState' 2>/dev/null | tail -n1 || echo 0)
  if [[ "${STATE}" == "1" ]]; then
    echo "    PRIMARY ready (myState=1)"
    break
  fi
  sleep 2
done

echo "==> B3: Tạo admin user qua localhost exception"
run "
db = db.getSiblingDB('admin');
db.createUser({
  user: 'admin',
  pwd:  '${ADMIN_PWD}',
  roles: [{ role: 'root', db: 'admin' }]
});
"

echo "==> B4: Tạo appuser trên DB 'demo'"
run_auth "
db = db.getSiblingDB('demo');
db.createUser({
  user: 'appuser',
  pwd:  '${APP_PWD}',
  roles: [{ role: 'readWrite', db: 'demo' }]
});
"

echo "==> B5: Insert 5 documents mẫu"
run_auth "
db = db.getSiblingDB('demo');
db.events.insertMany([
  { type: 'login',  user: 'alice', ts: new Date() },
  { type: 'login',  user: 'bob',   ts: new Date() },
  { type: 'logout', user: 'alice', ts: new Date() },
  { type: 'view',   user: 'carol', ts: new Date() },
  { type: 'order',  user: 'bob',   amount: 42 }
]);
print('Inserted: ' + db.events.countDocuments({}));
"

echo "==> B6: Verify replication — đếm document trên SECONDARY mongo2"
docker exec mongo2 mongosh --quiet -u admin -p "${ADMIN_PWD}" --authenticationDatabase admin --eval "
db.getSiblingDB('demo').getMongo().setReadPref('secondary');
db.getSiblingDB('demo').events.countDocuments({});
"

echo "==> B7: rs.status() rút gọn"
run_auth '
const s = rs.status();
print("set: " + s.set + "  myState=" + s.myState);
s.members.forEach(m => print("  " + m.name.padEnd(15) + " state=" + m.stateStr.padEnd(10) + " health=" + m.health));
'

cat <<HINT

============================================================
  Replica Set rs0 sẵn sàng.

  Connect string từ host:
    mongodb://appuser:${APP_PWD}@localhost:27017,localhost:27018,localhost:27019/demo?replicaSet=rs0

  Connect mongosh từ host:
    mongosh "mongodb://admin:${ADMIN_PWD}@localhost:27017/admin?replicaSet=rs0"

  Test failover:
    bash demo-failover.sh

  Cleanup:
    docker compose down -v
============================================================
HINT
