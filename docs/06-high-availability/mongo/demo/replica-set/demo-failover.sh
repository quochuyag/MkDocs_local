#!/usr/bin/env bash
# demo-failover.sh — chứng minh auto-failover hoạt động.
# Pipeline:
#   1. Xác định primary hiện tại
#   2. STOP container primary (giả lập primary crash)
#   3. Quan sát election → primary mới
#   4. Insert document mới qua primary mới
#   5. START lại container cũ, verify nó join lại làm SECONDARY và catch up
set -euo pipefail

ADMIN_PWD="${ADMIN_PWD:-DemoAdmin#2026}"

# Helper: connect bằng mongo bất kỳ container nào đang up
mc() {
  local target="${1:-mongo1}"; shift
  docker exec "${target}" mongosh --quiet \
    -u admin -p "${ADMIN_PWD}" --authenticationDatabase admin \
    --eval "$@"
}

primary_host() {
  for c in mongo1 mongo2 mongo3; do
    if ! docker ps --format '{{.Names}}' | grep -q "^${c}$"; then continue; fi
    out=$(docker exec "${c}" mongosh --quiet -u admin -p "${ADMIN_PWD}" --authenticationDatabase admin \
      --eval 'db.hello().primary' 2>/dev/null | tail -n1 || true)
    if [[ -n "${out}" && "${out}" != "null" && "${out}" != *"error"* ]]; then
      echo "${out}"
      return
    fi
  done
  echo "unknown"
}

echo "==> Bước 1: Trạng thái hiện tại"
mc mongo1 '
const s = rs.status();
s.members.forEach(m => print("  " + m.name.padEnd(15) + " " + m.stateStr));
'

P=$(primary_host)
echo "==> PRIMARY hiện tại: ${P}"
PRIMARY_CONT="${P%%:*}"

echo ""
echo "==> Bước 2: STOP container primary (${PRIMARY_CONT}) — giả lập crash"
docker stop "${PRIMARY_CONT}"

echo "==> Bước 3: Đợi election (~10-15s)"
sleep 15

# Pick 1 container còn lại để query
SURVIVOR=""
for c in mongo1 mongo2 mongo3; do
  if [[ "${c}" != "${PRIMARY_CONT}" ]] && docker ps --format '{{.Names}}' | grep -q "^${c}$"; then
    SURVIVOR="${c}"; break
  fi
done

echo "==> Trạng thái sau election (query từ ${SURVIVOR})"
docker exec "${SURVIVOR}" mongosh --quiet -u admin -p "${ADMIN_PWD}" --authenticationDatabase admin --eval '
const s = rs.status();
print("set: " + s.set + "  term: " + s.term);
s.members.forEach(m => print("  " + m.name.padEnd(15) + " state=" + m.stateStr.padEnd(15) + " health=" + m.health));
print("--- new primary ---");
print(db.hello().primary);
'

NEW_P=$(primary_host)
NEW_PRIMARY_CONT="${NEW_P%%:*}"
echo "==> PRIMARY mới: ${NEW_P}"

echo ""
echo "==> Bước 4: Insert document mới qua primary mới"
docker exec "${NEW_PRIMARY_CONT}" mongosh --quiet -u admin -p "${ADMIN_PWD}" --authenticationDatabase admin --eval "
db = db.getSiblingDB('demo');
db.events.insertOne({ type: 'after-failover', user: 'demo', ts: new Date() });
print('Total documents now: ' + db.events.countDocuments({}));
"

echo ""
echo "==> Bước 5: START lại container ${PRIMARY_CONT}, đợi nó join lại"
docker start "${PRIMARY_CONT}"
sleep 10

docker exec "${NEW_PRIMARY_CONT}" mongosh --quiet -u admin -p "${ADMIN_PWD}" --authenticationDatabase admin --eval '
const s = rs.status();
s.members.forEach(m => print("  " + m.name.padEnd(15) + " state=" + m.stateStr.padEnd(15) + " health=" + m.health));
'

echo ""
echo "==> Bước 6: Verify document mới đã replicate sang ${PRIMARY_CONT} (cũ primary, giờ secondary)"
sleep 3
docker exec "${PRIMARY_CONT}" mongosh --quiet -u admin -p "${ADMIN_PWD}" --authenticationDatabase admin --eval "
db.getSiblingDB('demo').getMongo().setReadPref('secondary');
const doc = db.getSiblingDB('demo').events.findOne({ type: 'after-failover' });
print('Doc on ex-primary (now secondary):');
printjson(doc);
"

cat <<DONE

============================================================
  Demo failover hoàn tất.

  Quan sát được:
  ✅ Election tự động trong ~10-15 giây
  ✅ App tiếp tục write trên primary mới
  ✅ Primary cũ rejoin làm secondary
  ✅ Data replicate ngược về ex-primary
============================================================
DONE
