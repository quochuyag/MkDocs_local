// ============================================================================
// VietPay — Neo4j Cypher Queries for Fraud Detection
// ============================================================================
// File: neo4j/cypher-queries.cypher
// Database: neo4j (VietPay Fraud Graph)
// Neo4j Version: 5.x+
// ============================================================================


// ═══════════════════════════════════════════════════════════════════════════
// SECTION 0: SCHEMA CREATION — Constraints & Indexes
// ═══════════════════════════════════════════════════════════════════════════

CREATE CONSTRAINT account_id_unique IF NOT EXISTS
FOR (a:Account) REQUIRE a.account_id IS UNIQUE;

CREATE CONSTRAINT device_id_unique IF NOT EXISTS
FOR (d:Device) REQUIRE d.device_id IS UNIQUE;

CREATE CONSTRAINT ip_address_unique IF NOT EXISTS
FOR (ip:IPAddress) REQUIRE ip.ip_address IS UNIQUE;

CREATE CONSTRAINT phone_unique IF NOT EXISTS
FOR (p:PhoneNumber) REQUIRE p.phone_number IS UNIQUE;

CREATE CONSTRAINT txn_id_unique IF NOT EXISTS
FOR (t:Transaction) REQUIRE t.transaction_id IS UNIQUE;

CREATE CONSTRAINT merchant_id_unique IF NOT EXISTS
FOR (m:Merchant) REQUIRE m.merchant_id IS UNIQUE;

// Performance Indexes
CREATE INDEX account_fraud_flag IF NOT EXISTS FOR (a:Account) ON (a.fraud_flag);
CREATE INDEX account_risk_tier IF NOT EXISTS FOR (a:Account) ON (a.risk_tier);
CREATE INDEX account_created_at IF NOT EXISTS FOR (a:Account) ON (a.created_at);
CREATE INDEX account_fraud_score IF NOT EXISTS FOR (a:Account) ON (a.fraud_score);
CREATE INDEX device_type IF NOT EXISTS FOR (d:Device) ON (d.device_type);
CREATE INDEX device_emulator IF NOT EXISTS FOR (d:Device) ON (d.is_emulator);
CREATE INDEX ip_type IF NOT EXISTS FOR (ip:IPAddress) ON (ip.ip_type);
CREATE INDEX ip_country IF NOT EXISTS FOR (ip:IPAddress) ON (ip.country_code);
CREATE INDEX ip_threat IF NOT EXISTS FOR (ip:IPAddress) ON (ip.threat_score);
CREATE INDEX phone_virtual IF NOT EXISTS FOR (p:PhoneNumber) ON (p.is_virtual);
CREATE INDEX txn_created_at IF NOT EXISTS FOR (t:Transaction) ON (t.created_at);
CREATE INDEX txn_amount IF NOT EXISTS FOR (t:Transaction) ON (t.amount);
CREATE INDEX txn_flagged IF NOT EXISTS FOR (t:Transaction) ON (t.is_flagged);
CREATE INDEX merchant_mcc IF NOT EXISTS FOR (m:Merchant) ON (m.mcc);
CREATE INDEX merchant_risk IF NOT EXISTS FOR (m:Merchant) ON (m.risk_tier);


// ═══════════════════════════════════════════════════════════════════════════
// SECTION 1: SAMPLE DATA INSERTION
// ═══════════════════════════════════════════════════════════════════════════

// ─── Accounts ───
CREATE (:Account {account_id:'ACC_001', full_name:'Nguyễn Văn An', phone_primary:'+84901234567',
    email:'nguyen.an@email.com', kyc_level:2, account_status:'active',
    created_at:datetime('2025-01-15T10:00:00Z'), fraud_flag:false, fraud_score:15.0,
    risk_tier:'low', total_transaction_count:156, total_transaction_volume:45000000.0});

CREATE (:Account {account_id:'ACC_002', full_name:'Trần Thị Bình', phone_primary:'+84912345678',
    email:'tran.binh@tempmail.com', kyc_level:1, account_status:'active',
    created_at:datetime('2026-06-01T08:00:00Z'), fraud_flag:false, fraud_score:45.0,
    risk_tier:'medium', total_transaction_count:28, total_transaction_volume:120000000.0});

CREATE (:Account {account_id:'ACC_003', full_name:'Lê Hoàng Cường', phone_primary:'+84923456789',
    email:'le.cuong@gmail.com', kyc_level:2, account_status:'active',
    created_at:datetime('2025-06-20T14:00:00Z'), fraud_flag:true, fraud_score:78.0,
    risk_tier:'high', total_transaction_count:89, total_transaction_volume:250000000.0});

CREATE (:Account {account_id:'ACC_004', full_name:'Phạm Đức Duy', phone_primary:'+84934567890',
    email:'pham.duy@yahoo.com', kyc_level:1, account_status:'active',
    created_at:datetime('2026-05-28T16:00:00Z'), fraud_flag:false, fraud_score:35.0,
    risk_tier:'medium', total_transaction_count:42, total_transaction_volume:180000000.0});

CREATE (:Account {account_id:'ACC_005', full_name:'Võ Thị Hoa', phone_primary:'+84945678901',
    email:'vo.hoa@company.vn', kyc_level:3, account_status:'active',
    created_at:datetime('2024-03-10T09:00:00Z'), fraud_flag:false, fraud_score:5.0,
    risk_tier:'low', total_transaction_count:450, total_transaction_volume:85000000.0});

CREATE (:Account {account_id:'ACC_006', full_name:'Đỗ Minh Tuấn', phone_primary:'+84956789012',
    email:'do.tuan@disposable.com', kyc_level:1, account_status:'active',
    created_at:datetime('2026-06-10T11:00:00Z'), fraud_flag:false, fraud_score:55.0,
    risk_tier:'high', total_transaction_count:15, total_transaction_volume:95000000.0});

// ─── Devices ───
CREATE (:Device {device_id:'DEV_FP_SHARED_001', device_type:'mobile', os:'Android 14',
    brand:'Samsung', model:'Galaxy A54', fingerprint_hash:'fp_sha256_shared_abc123',
    first_seen:datetime('2026-05-28T16:00:00Z'), last_seen:datetime('2026-06-23T14:30:00Z'),
    is_emulator:false, is_rooted:true});

CREATE (:Device {device_id:'DEV_FP_EMU_001', device_type:'mobile', os:'Android 13',
    brand:'Google', model:'sdk_gphone64_arm64', fingerprint_hash:'fp_sha256_emulator_xyz789',
    first_seen:datetime('2026-06-15T09:00:00Z'), last_seen:datetime('2026-06-23T12:00:00Z'),
    is_emulator:true, is_rooted:false});

CREATE (:Device {device_id:'DEV_FP_LEGIT_001', device_type:'mobile', os:'iOS 18',
    brand:'Apple', model:'iPhone 16', fingerprint_hash:'fp_sha256_legit_def456',
    first_seen:datetime('2024-09-15T10:00:00Z'), last_seen:datetime('2026-06-23T15:00:00Z'),
    is_emulator:false, is_rooted:false});

// ─── IP Addresses ───
CREATE (:IPAddress {ip_address:'185.220.101.42', ip_type:'datacenter', country_code:'VN',
    city:'Ho Chi Minh City', isp:'Unknown Datacenter', asn:99999,
    is_proxy:true, is_vpn:true, is_tor:false, threat_score:75.0,
    first_seen:datetime('2026-06-01T00:00:00Z')});

CREATE (:IPAddress {ip_address:'113.160.92.100', ip_type:'residential', country_code:'VN',
    city:'Ha Noi', isp:'Viettel', asn:7552,
    is_proxy:false, is_vpn:false, is_tor:false, threat_score:5.0,
    first_seen:datetime('2025-01-01T00:00:00Z')});

CREATE (:IPAddress {ip_address:'104.238.170.55', ip_type:'vpn', country_code:'SG',
    city:'Singapore', isp:'NordVPN', asn:212238,
    is_proxy:false, is_vpn:true, is_tor:false, threat_score:60.0,
    first_seen:datetime('2026-06-10T00:00:00Z')});

CREATE (:IPAddress {ip_address:'14.161.22.33', ip_type:'residential', country_code:'VN',
    city:'Ho Chi Minh City', isp:'VNPT', asn:45899,
    is_proxy:false, is_vpn:false, is_tor:false, threat_score:2.0,
    first_seen:datetime('2024-03-10T09:00:00Z')});

// ─── Phone Numbers ───
CREATE (:PhoneNumber {phone_number:'+84700111222', country_code:'+84', carrier:'Unknown',
    phone_type:'voip', is_virtual:true, registered_name:'N/A',
    first_seen:datetime('2026-06-01T00:00:00Z')});

CREATE (:PhoneNumber {phone_number:'+84901234567', country_code:'+84', carrier:'Viettel',
    phone_type:'mobile', is_virtual:false, registered_name:'Nguyễn Văn An',
    first_seen:datetime('2025-01-15T10:00:00Z')});

CREATE (:PhoneNumber {phone_number:'+84888999000', country_code:'+84', carrier:'Vinaphone',
    phone_type:'mobile', is_virtual:false, registered_name:'Lê Hoàng Cường',
    first_seen:datetime('2025-06-20T14:00:00Z')});

// ─── Merchants ───
CREATE (:Merchant {merchant_id:'MCH_COFFEE_001', merchant_name:'Coffee House Nguyễn Huệ',
    mcc:'5814', mcc_description:'Fast Food Restaurants', city:'Ho Chi Minh City',
    district:'Quận 1', registration_date:datetime('2024-06-01T00:00:00Z'),
    risk_tier:'low', chargeback_rate:0.15, monthly_volume:500000000.0});

CREATE (:Merchant {merchant_id:'MCH_ELECTRONICS_002', merchant_name:'Điện Máy Express',
    mcc:'5732', mcc_description:'Electronics Stores', city:'Ho Chi Minh City',
    district:'Quận 7', registration_date:datetime('2025-01-15T00:00:00Z'),
    risk_tier:'medium', chargeback_rate:1.2, monthly_volume:2000000000.0});

// ─── OWNS_DEVICE Relationships ───
// ACC_001, ACC_002, ACC_004 share DEV_FP_SHARED_001 (fraud ring signal)
MATCH (a:Account {account_id:'ACC_001'}), (d:Device {device_id:'DEV_FP_SHARED_001'})
CREATE (a)-[:OWNS_DEVICE {first_used:datetime('2026-06-15T10:00:00Z'),
    last_used:datetime('2026-06-23T08:00:00Z'), login_count:5, is_primary:false}]->(d);

MATCH (a:Account {account_id:'ACC_002'}), (d:Device {device_id:'DEV_FP_SHARED_001'})
CREATE (a)-[:OWNS_DEVICE {first_used:datetime('2026-06-01T08:00:00Z'),
    last_used:datetime('2026-06-23T14:30:00Z'), login_count:28, is_primary:true}]->(d);

MATCH (a:Account {account_id:'ACC_004'}), (d:Device {device_id:'DEV_FP_SHARED_001'})
CREATE (a)-[:OWNS_DEVICE {first_used:datetime('2026-05-28T16:00:00Z'),
    last_used:datetime('2026-06-22T20:00:00Z'), login_count:15, is_primary:true}]->(d);

// ACC_003, ACC_006 share emulator (critical)
MATCH (a:Account {account_id:'ACC_003'}), (d:Device {device_id:'DEV_FP_EMU_001'})
CREATE (a)-[:OWNS_DEVICE {first_used:datetime('2026-06-15T09:00:00Z'),
    last_used:datetime('2026-06-23T12:00:00Z'), login_count:42, is_primary:true}]->(d);

MATCH (a:Account {account_id:'ACC_006'}), (d:Device {device_id:'DEV_FP_EMU_001'})
CREATE (a)-[:OWNS_DEVICE {first_used:datetime('2026-06-10T11:00:00Z'),
    last_used:datetime('2026-06-23T11:00:00Z'), login_count:15, is_primary:true}]->(d);

// ACC_005 legitimate device (control)
MATCH (a:Account {account_id:'ACC_005'}), (d:Device {device_id:'DEV_FP_LEGIT_001'})
CREATE (a)-[:OWNS_DEVICE {first_used:datetime('2024-09-15T10:00:00Z'),
    last_used:datetime('2026-06-23T15:00:00Z'), login_count:890, is_primary:true}]->(d);

// ─── LOGGED_FROM Relationships ───
MATCH (a:Account {account_id:'ACC_002'}), (ip:IPAddress {ip_address:'185.220.101.42'})
CREATE (a)-[:LOGGED_FROM {first_login:datetime('2026-06-05T10:00:00Z'),
    last_login:datetime('2026-06-23T14:00:00Z'), login_count:35, is_usual:true}]->(ip);

MATCH (a:Account {account_id:'ACC_003'}), (ip:IPAddress {ip_address:'185.220.101.42'})
CREATE (a)-[:LOGGED_FROM {first_login:datetime('2026-06-01T08:00:00Z'),
    last_login:datetime('2026-06-23T12:00:00Z'), login_count:48, is_usual:true}]->(ip);

MATCH (a:Account {account_id:'ACC_004'}), (ip:IPAddress {ip_address:'104.238.170.55'})
CREATE (a)-[:LOGGED_FROM {first_login:datetime('2026-06-12T14:00:00Z'),
    last_login:datetime('2026-06-23T10:00:00Z'), login_count:20, is_usual:false}]->(ip);

MATCH (a:Account {account_id:'ACC_006'}), (ip:IPAddress {ip_address:'104.238.170.55'})
CREATE (a)-[:LOGGED_FROM {first_login:datetime('2026-06-10T11:00:00Z'),
    last_login:datetime('2026-06-22T18:00:00Z'), login_count:12, is_usual:false}]->(ip);

MATCH (a:Account {account_id:'ACC_001'}), (ip:IPAddress {ip_address:'113.160.92.100'})
CREATE (a)-[:LOGGED_FROM {first_login:datetime('2025-01-15T10:00:00Z'),
    last_login:datetime('2026-06-23T08:00:00Z'), login_count:520, is_usual:true}]->(ip);

MATCH (a:Account {account_id:'ACC_005'}), (ip:IPAddress {ip_address:'14.161.22.33'})
CREATE (a)-[:LOGGED_FROM {first_login:datetime('2024-03-10T09:00:00Z'),
    last_login:datetime('2026-06-23T15:00:00Z'), login_count:1200, is_usual:true}]->(ip);

// ─── HAS_PHONE Relationships ───
MATCH (a:Account {account_id:'ACC_003'}), (p:PhoneNumber {phone_number:'+84700111222'})
CREATE (a)-[:HAS_PHONE {registered_at:datetime('2026-06-01T00:00:00Z'),
    is_primary:false, verified:true}]->(p);

MATCH (a:Account {account_id:'ACC_004'}), (p:PhoneNumber {phone_number:'+84700111222'})
CREATE (a)-[:HAS_PHONE {registered_at:datetime('2026-05-28T16:00:00Z'),
    is_primary:false, verified:true}]->(p);

MATCH (a:Account {account_id:'ACC_001'}), (p:PhoneNumber {phone_number:'+84901234567'})
CREATE (a)-[:HAS_PHONE {registered_at:datetime('2025-01-15T10:00:00Z'),
    is_primary:true, verified:true}]->(p);

MATCH (a:Account {account_id:'ACC_003'}), (p:PhoneNumber {phone_number:'+84888999000'})
CREATE (a)-[:HAS_PHONE {registered_at:datetime('2025-06-20T14:00:00Z'),
    is_primary:true, verified:true}]->(p);

MATCH (a:Account {account_id:'ACC_006'}), (p:PhoneNumber {phone_number:'+84888999000'})
CREATE (a)-[:HAS_PHONE {registered_at:datetime('2026-06-10T11:00:00Z'),
    is_primary:true, verified:true}]->(p);

// ─── SENT_TO Relationships (Circular money flow) ───
// Circle: ACC_002 → ACC_003 → ACC_004 → ACC_006 → ACC_002
MATCH (f:Account {account_id:'ACC_002'}), (t:Account {account_id:'ACC_003'})
CREATE (f)-[:SENT_TO {transaction_id:'TXN_CIRCLE_001', amount:50000000.0,
    currency:'VND', created_at:datetime('2026-06-23T10:00:00Z'),
    channel:'app', description:'Chuyển tiền mua hàng'}]->(t);

MATCH (f:Account {account_id:'ACC_003'}), (t:Account {account_id:'ACC_004'})
CREATE (f)-[:SENT_TO {transaction_id:'TXN_CIRCLE_002', amount:48000000.0,
    currency:'VND', created_at:datetime('2026-06-23T10:30:00Z'),
    channel:'app', description:'Thanh toán dịch vụ'}]->(t);

MATCH (f:Account {account_id:'ACC_004'}), (t:Account {account_id:'ACC_006'})
CREATE (f)-[:SENT_TO {transaction_id:'TXN_CIRCLE_003', amount:46000000.0,
    currency:'VND', created_at:datetime('2026-06-23T11:00:00Z'),
    channel:'app', description:'Hoàn tiền'}]->(t);

MATCH (f:Account {account_id:'ACC_006'}), (t:Account {account_id:'ACC_002'})
CREATE (f)-[:SENT_TO {transaction_id:'TXN_CIRCLE_004', amount:44000000.0,
    currency:'VND', created_at:datetime('2026-06-23T11:30:00Z'),
    channel:'app', description:'Trả nợ'}]->(t);

// Rapid fire transactions (smurfing pattern)
MATCH (f:Account {account_id:'ACC_002'}), (t:Account {account_id:'ACC_003'})
CREATE (f)-[:SENT_TO {transaction_id:'TXN_RAPID_001', amount:9900000.0,
    currency:'VND', created_at:datetime('2026-06-23T13:00:00Z'), channel:'app'}]->(t);
MATCH (f:Account {account_id:'ACC_002'}), (t:Account {account_id:'ACC_003'})
CREATE (f)-[:SENT_TO {transaction_id:'TXN_RAPID_002', amount:9800000.0,
    currency:'VND', created_at:datetime('2026-06-23T13:05:00Z'), channel:'app'}]->(t);
MATCH (f:Account {account_id:'ACC_002'}), (t:Account {account_id:'ACC_003'})
CREATE (f)-[:SENT_TO {transaction_id:'TXN_RAPID_003', amount:9700000.0,
    currency:'VND', created_at:datetime('2026-06-23T13:10:00Z'), channel:'app'}]->(t);
MATCH (f:Account {account_id:'ACC_002'}), (t:Account {account_id:'ACC_003'})
CREATE (f)-[:SENT_TO {transaction_id:'TXN_RAPID_004', amount:9600000.0,
    currency:'VND', created_at:datetime('2026-06-23T13:15:00Z'), channel:'app'}]->(t);
MATCH (f:Account {account_id:'ACC_002'}), (t:Account {account_id:'ACC_003'})
CREATE (f)-[:SENT_TO {transaction_id:'TXN_RAPID_005', amount:9500000.0,
    currency:'VND', created_at:datetime('2026-06-23T13:20:00Z'), channel:'app'}]->(t);
MATCH (f:Account {account_id:'ACC_002'}), (t:Account {account_id:'ACC_003'})
CREATE (f)-[:SENT_TO {transaction_id:'TXN_RAPID_006', amount:9400000.0,
    currency:'VND', created_at:datetime('2026-06-23T13:25:00Z'), channel:'app'}]->(t);

// Legitimate transaction (control)
MATCH (f:Account {account_id:'ACC_005'}), (t:Account {account_id:'ACC_001'})
CREATE (f)-[:SENT_TO {transaction_id:'TXN_LEGIT_001', amount:500000.0,
    currency:'VND', created_at:datetime('2026-06-23T12:00:00Z'),
    channel:'app', description:'Trả tiền ăn trưa'}]->(t);

// ─── TRANSACTED_WITH Relationships ───
MATCH (a:Account {account_id:'ACC_001'}), (m:Merchant {merchant_id:'MCH_COFFEE_001'})
CREATE (a)-[:TRANSACTED_WITH {transaction_count:45, total_amount:6750000.0,
    first_transaction:datetime('2024-08-01T09:00:00Z'),
    last_transaction:datetime('2026-06-23T07:30:00Z'), avg_amount:150000.0}]->(m);

MATCH (a:Account {account_id:'ACC_003'}), (m:Merchant {merchant_id:'MCH_ELECTRONICS_002'})
CREATE (a)-[:TRANSACTED_WITH {transaction_count:8, total_amount:45000000.0,
    first_transaction:datetime('2026-06-15T14:00:00Z'),
    last_transaction:datetime('2026-06-22T16:00:00Z'), avg_amount:5625000.0}]->(m);

MATCH (a:Account {account_id:'ACC_004'}), (m:Merchant {merchant_id:'MCH_ELECTRONICS_002'})
CREATE (a)-[:TRANSACTED_WITH {transaction_count:5, total_amount:35000000.0,
    first_transaction:datetime('2026-06-18T10:00:00Z'),
    last_transaction:datetime('2026-06-23T09:00:00Z'), avg_amount:7000000.0}]->(m);


// ═══════════════════════════════════════════════════════════════════════════
// QUERY 1: Find Accounts Sharing Devices — Phát hiện Fraud Ring qua Device
// ═══════════════════════════════════════════════════════════════════════════
// MỤC ĐÍCH: Tìm nhóm accounts sử dụng chung thiết bị.
// Người dùng hợp lệ hiếm khi chia sẻ device → strong fraud indicator.
// KẾT QUẢ MONG ĐỢI:
//   DEV_FP_SHARED_001: ACC_001, ACC_002, ACC_004 (3 accounts → WARNING)
//   DEV_FP_EMU_001: ACC_003, ACC_006 (emulator → CRITICAL)
// ═══════════════════════════════════════════════════════════════════════════

MATCH (account:Account)-[owns:OWNS_DEVICE]->(device:Device)
WITH device,
     collect({
         account_id: account.account_id,
         full_name: account.full_name,
         fraud_flag: account.fraud_flag,
         fraud_score: account.fraud_score,
         login_count: owns.login_count
     }) AS connected_accounts
WHERE size(connected_accounts) >= 2
RETURN device.device_id AS device_id,
       device.brand + ' ' + device.model AS device_model,
       device.is_emulator AS is_emulator,
       device.is_rooted AS is_rooted,
       size(connected_accounts) AS shared_account_count,
       connected_accounts,
       CASE
           WHEN device.is_emulator THEN 'CRITICAL'
           WHEN size(connected_accounts) >= 5 THEN 'CRITICAL'
           WHEN size(connected_accounts) >= 3 THEN 'HIGH'
           ELSE 'WARNING'
       END AS risk_level
ORDER BY shared_account_count DESC;


// ═══════════════════════════════════════════════════════════════════════════
// QUERY 2: Detect Circular Money Flow — Phát hiện rửa tiền vòng tròn
// ═══════════════════════════════════════════════════════════════════════════
// PATTERN: A → B → C → D → A (tiền quay vòng)
// Amount giảm dần = classic layering pattern
// KẾT QUẢ MONG ĐỢI:
//   ACC_002 → ACC_003 → ACC_004 → ACC_006 → ACC_002
// ═══════════════════════════════════════════════════════════════════════════

MATCH circle = (start:Account)-[:SENT_TO*3..6]->(start)
WITH circle, start,
     [node IN nodes(circle) | node.account_id] AS account_ids,
     [rel IN relationships(circle) | rel.amount] AS amounts,
     [rel IN relationships(circle) | rel.created_at] AS timestamps,
     reduce(total = 0.0, rel IN relationships(circle) | total + rel.amount) AS total_flow,
     length(circle) AS ring_size
WHERE total_flow > 10000000
RETURN account_ids AS fraud_ring_members,
       ring_size,
       amounts AS transfer_amounts,
       total_flow AS total_money_flow,
       CASE
           WHEN total_flow > 100000000 THEN 'CRITICAL'
           WHEN total_flow > 50000000 THEN 'HIGH'
           ELSE 'MEDIUM'
       END AS risk_level
ORDER BY total_flow DESC;


// ═══════════════════════════════════════════════════════════════════════════
// QUERY 3: Find Suspicious Rapid Transactions
// ═══════════════════════════════════════════════════════════════════════════
// MỤC ĐÍCH: Phát hiện chuỗi giao dịch nhanh bất thường giữa accounts
// có shared resources. Patterns: smurfing, card testing, cash-out.
// KẾT QUẢ MONG ĐỢI:
//   ACC_002 → ACC_003: 6+ rapid transactions trong 25 phút
// ═══════════════════════════════════════════════════════════════════════════

MATCH (sender:Account)-[txns:SENT_TO]->(receiver:Account)
WHERE txns.created_at >= datetime('2026-06-23T00:00:00Z')
WITH sender, receiver,
     count(txns) AS txn_count,
     sum(txns.amount) AS total_amount,
     min(txns.created_at) AS first_txn,
     max(txns.created_at) AS last_txn,
     collect(txns.amount) AS amounts
WHERE txn_count >= 5
WITH sender, receiver, txn_count, total_amount, amounts,
     first_txn, last_txn,
     duration.between(first_txn, last_txn).minutes AS span_minutes
// Check for shared resources between sender and receiver
OPTIONAL MATCH (sender)-[:OWNS_DEVICE]->(d:Device)<-[:OWNS_DEVICE]-(receiver)
WITH sender, receiver, txn_count, total_amount, amounts, span_minutes,
     collect(DISTINCT d.device_id) AS shared_devices
OPTIONAL MATCH (sender)-[:LOGGED_FROM]->(ip:IPAddress)<-[:LOGGED_FROM]-(receiver)
RETURN sender.account_id AS sender_id,
       receiver.account_id AS receiver_id,
       txn_count AS transaction_count,
       total_amount,
       span_minutes AS time_span_minutes,
       amounts AS individual_amounts,
       shared_devices,
       collect(DISTINCT ip.ip_address) AS shared_ips,
       ALL(i IN range(0, size(amounts)-2) WHERE amounts[i] >= amounts[i+1]) AS decreasing_pattern,
       CASE
           WHEN size(shared_devices) > 0 AND span_minutes < 60
               THEN 'CRITICAL - Rapid + shared device'
           WHEN span_minutes < 30 AND txn_count > 5
               THEN 'HIGH - Very rapid (potential smurfing)'
           ELSE 'MEDIUM - Unusual velocity'
       END AS risk_assessment
ORDER BY txn_count DESC;


// ═══════════════════════════════════════════════════════════════════════════
// QUERY 4: Community Detection — Tìm cluster accounts liên kết chặt chẽ
// ═══════════════════════════════════════════════════════════════════════════
// MỤC ĐÍCH: Tìm clusters của accounts có nhiều shared resources.
// Simplified version không cần GDS library.
// KẾT QUẢ MONG ĐỢI:
//   Cluster {ACC_002, ACC_003, ACC_004, ACC_006} — nhiều connections
// ═══════════════════════════════════════════════════════════════════════════

MATCH (a:Account) WHERE a.account_status = 'active'
OPTIONAL MATCH (a)-[:OWNS_DEVICE]->(:Device)<-[:OWNS_DEVICE]-(dn:Account)
WITH a, collect(DISTINCT dn.account_id) AS device_conn
OPTIONAL MATCH (a)-[:LOGGED_FROM]->(:IPAddress)<-[:LOGGED_FROM]-(ipn:Account)
WITH a, device_conn, collect(DISTINCT ipn.account_id) AS ip_conn
OPTIONAL MATCH (a)-[:HAS_PHONE]->(:PhoneNumber)<-[:HAS_PHONE]-(phn:Account)
WITH a, device_conn, ip_conn, collect(DISTINCT phn.account_id) AS phone_conn
OPTIONAL MATCH (a)-[:SENT_TO]->(txn:Account)
WITH a, device_conn, ip_conn, phone_conn,
     collect(DISTINCT txn.account_id) AS txn_conn
WITH a,
     device_conn + ip_conn + phone_conn + txn_conn AS all_raw,
     size(device_conn) AS dev_cnt,
     size(ip_conn) AS ip_cnt,
     size(phone_conn) AS ph_cnt,
     size(txn_conn) AS tx_cnt
WHERE dev_cnt + ip_cnt + ph_cnt + tx_cnt >= 2
RETURN a.account_id AS account_id,
       a.full_name AS full_name,
       a.fraud_score AS fraud_score,
       dev_cnt AS shared_devices,
       ip_cnt AS shared_ips,
       ph_cnt AS shared_phones,
       tx_cnt AS sent_to_count,
       dev_cnt * 40 + ip_cnt * 30 + ph_cnt * 30 + tx_cnt * 10 AS risk_score,
       CASE
           WHEN dev_cnt * 40 + ip_cnt * 30 + ph_cnt * 30 + tx_cnt * 10 > 100 THEN 'CRITICAL'
           WHEN dev_cnt * 40 + ip_cnt * 30 + ph_cnt * 30 + tx_cnt * 10 > 50 THEN 'HIGH'
           ELSE 'MEDIUM'
       END AS risk_level
ORDER BY risk_score DESC;


// ═══════════════════════════════════════════════════════════════════════════
// QUERY 5: Shortest Path Between Suspicious Accounts
// ═══════════════════════════════════════════════════════════════════════════
// MỤC ĐÍCH: Tìm đường đi ngắn nhất giữa 2 accounts nghi vấn qua
// bất kỳ relationship nào. Giúp investigators hiểu mối liên hệ.
// ═══════════════════════════════════════════════════════════════════════════

// 5a: Single shortest path với annotated nodes
MATCH path = shortestPath(
    (source:Account {account_id:'ACC_001'})-[*..10]-(target:Account {account_id:'ACC_003'})
)
RETURN length(path) AS hops,
       [node IN nodes(path) |
           CASE
               WHEN node:Account THEN 'Account:' + node.account_id +
                   CASE WHEN node.fraud_flag THEN ' [FLAGGED]' ELSE '' END
               WHEN node:Device THEN 'Device:' + node.device_id +
                   CASE WHEN node.is_emulator THEN ' [EMULATOR]' ELSE '' END
               WHEN node:IPAddress THEN 'IP:' + node.ip_address +
                   CASE WHEN node.is_vpn THEN ' [VPN]' ELSE '' END
               WHEN node:PhoneNumber THEN 'Phone:' + node.phone_number +
                   CASE WHEN node.is_virtual THEN ' [VIRTUAL]' ELSE '' END
               ELSE 'Unknown'
           END
       ] AS path_description,
       [rel IN relationships(path) | type(rel)] AS relationship_types;

// 5b: All shortest paths (multiple routes)
MATCH paths = allShortestPaths(
    (source:Account {account_id:'ACC_001'})-[*..10]-(target:Account {account_id:'ACC_003'})
)
RETURN length(paths) AS hops,
       [node IN nodes(paths) |
           coalesce(node.account_id, node.device_id, node.ip_address, node.phone_number)
       ] AS path_nodes,
       [rel IN relationships(paths) | type(rel)] AS via_relationships
ORDER BY hops ASC;

// 5c: Weighted shortest path with risk scoring
MATCH path = shortestPath(
    (source:Account {account_id:'ACC_001'})-[*..8]-(target:Account {account_id:'ACC_006'})
)
WITH path, length(path) AS hops, nodes(path) AS pn, relationships(path) AS pr
RETURN hops,
       [n IN pn | coalesce(n.account_id, n.device_id, n.ip_address, n.phone_number)] AS path_nodes,
       [r IN pr | type(r)] AS relationship_chain,
       size([n IN pn WHERE n:Account AND n.fraud_flag = true]) AS flagged_on_path,
       size([n IN pn WHERE n:Device AND n.is_emulator = true]) AS emulators_on_path,
       size([n IN pn WHERE n:IPAddress AND n.threat_score > 50]) AS risky_ips_on_path,
       CASE
           WHEN size([n IN pn WHERE n:Account AND n.fraud_flag = true]) > 0
               THEN 'HIGH RISK - Flagged account on path'
           WHEN size([n IN pn WHERE n:Device AND n.is_emulator = true]) > 0
               THEN 'HIGH RISK - Emulator on path'
           ELSE 'MODERATE - Indirect connection'
       END AS path_assessment;


// ═══════════════════════════════════════════════════════════════════════════
// BONUS: Real-time Fraud Proximity Score
// ═══════════════════════════════════════════════════════════════════════════
// Called real-time khi giao dịch mới đến. SLA: < 100ms.
// Input: $account_id
// Output: fraud_proximity_score (0-100) + recommended action
// ═══════════════════════════════════════════════════════════════════════════

MATCH (account:Account {account_id: $account_id})
OPTIONAL MATCH (account)-[:OWNS_DEVICE]->(:Device)<-[:OWNS_DEVICE]-(fd:Account {fraud_flag:true})
WHERE fd <> account
WITH account, count(DISTINCT fd) AS fraud_device_links
OPTIONAL MATCH (account)-[:LOGGED_FROM]->(:IPAddress)<-[:LOGGED_FROM]-(fi:Account {fraud_flag:true})
WHERE fi <> account
WITH account, fraud_device_links, count(DISTINCT fi) AS fraud_ip_links
OPTIONAL MATCH (account)-[:HAS_PHONE]->(:PhoneNumber)<-[:HAS_PHONE]-(fp:Account {fraud_flag:true})
WHERE fp <> account
WITH account, fraud_device_links, fraud_ip_links, count(DISTINCT fp) AS fraud_phone_links,
     duration.between(account.created_at, datetime()).days AS age_days
RETURN account.account_id AS account_id,
       fraud_device_links, fraud_ip_links, fraud_phone_links,
       age_days AS account_age_days,
       toInteger(
           CASE WHEN fraud_device_links > 0 THEN least(fraud_device_links * 15, 30) ELSE 0 END +
           CASE WHEN fraud_ip_links > 0 THEN least(fraud_ip_links * 12, 25) ELSE 0 END +
           CASE WHEN fraud_phone_links > 0 THEN least(fraud_phone_links * 10, 20) ELSE 0 END +
           CASE WHEN age_days < 7 THEN 10 WHEN age_days < 30 THEN 7 WHEN age_days < 90 THEN 3 ELSE 0 END
       ) AS fraud_proximity_score,
       CASE
           WHEN fraud_device_links > 0 AND fraud_ip_links > 0 THEN 'BLOCK'
           WHEN fraud_device_links > 2 OR fraud_ip_links > 2 THEN 'BLOCK'
           WHEN fraud_device_links > 0 OR fraud_ip_links > 0 OR fraud_phone_links > 0 THEN 'REVIEW'
           ELSE 'ALLOW'
       END AS recommended_action;
