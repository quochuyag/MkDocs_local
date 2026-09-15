---
title: Neo4j — Graph Database Model cho Fraud Detection
course: 13-vietpay
source: vietpay/neo4j/fraud-detection-model.md
---

# Neo4j — Graph Database Model cho Fraud Detection

> **Phiên bản**: 1.0  
> **Ngày tạo**: 2026-06-23  
> **Tác giả**: VietPay DBA Team  
> **Trạng thái**: Proposed

---

## Mục lục

1. [Use Case — Phát hiện vòng gian lận (Fraud Ring Detection)](#1-use-case--phát-hiện-vòng-gian-lận)
2. [Tại sao đây là bài toán Graph](#2-tại-sao-đây-là-bài-toán-graph)
3. [Graph Model — Mô hình đồ thị](#3-graph-model--mô-hình-đồ-thị)
4. [Use Case Scenarios — Các kịch bản phát hiện gian lận](#4-use-case-scenarios--các-kịch-bản-phát-hiện-gian-lận)
5. [Performance và Scaling](#5-performance-và-scaling)
6. [Integration Architecture](#6-integration-architecture)

---

## 1. Use Case — Phát hiện vòng gian lận

### 1.1 Bối cảnh

VietPay xử lý hàng triệu giao dịch mỗi ngày qua nhiều kênh (ví điện tử, POS, banking, QR code). Các tổ chức gian lận (fraud rings) sử dụng các chiến thuật tinh vi:

| Loại gian lận | Mô tả | Thiệt hại tiềm tàng |
|---------------|--------|---------------------|
| **Account Takeover** | Chiếm quyền tài khoản hợp lệ, chuyển tiền ra ngoài | Mất tiền trực tiếp của người dùng |
| **Synthetic Identity** | Tạo danh tính giả kết hợp thông tin thật/giả | Vay tín dụng, mở ví không trả nợ |
| **Money Laundering** | Chuyển tiền vòng qua nhiều tài khoản để rửa | Vi phạm AML, phạt nặng từ NHNN |
| **Collusive Fraud** | Nhóm tài khoản phối hợp giao dịch giả | Chiếm tiền khuyến mãi, cashback |
| **Card Testing** | Thử hàng loạt thẻ đánh cắp với giao dịch nhỏ | Tiền đề cho fraud lớn hơn |

### 1.2 Tại sao phát hiện gian lận cần Graph Database?

Gian lận là bài toán về **mối quan hệ** (relationships), không phải bài toán về **thuộc tính** (attributes):

```
Ví dụ thực tế:
- Account A và Account B dùng chung Device X
- Account B và Account C có cùng IP address Y
- Account C chuyển tiền cho Account A qua Account D
  
→ A, B, C, D có thể là một fraud ring
→ Phát hiện pattern này yêu cầu duyệt qua 3-4 hop relationships
→ SQL JOIN hoặc recursive CTE trở nên cực kỳ chậm ở scale này
```

---

## 2. Tại sao đây là bài toán Graph

### 2.1 Multi-hop Traversal — Duyệt nhiều bước qua quan hệ

**Bài toán**: Tìm tất cả accounts kết nối với account nghi vấn qua shared devices, IPs, phone numbers — trong phạm vi 1 đến 5 hops.

**SQL approach (PostgreSQL — Recursive CTE):**

```sql
-- Tìm accounts chia sẻ device trong 3 hops — SQL CTE
-- ⚠️ Hiệu suất giảm EXPONENTIALLY khi tăng số hops

WITH RECURSIVE connected_accounts AS (
    -- Base case: accounts dùng chung device với account nghi vấn
    SELECT DISTINCT ad2.account_id, 1 AS depth
    FROM account_devices ad1
    JOIN account_devices ad2 ON ad1.device_id = ad2.device_id
    WHERE ad1.account_id = 'ACC_SUSPECT_001'
      AND ad2.account_id != 'ACC_SUSPECT_001'
    
    UNION
    
    -- Recursive: mở rộng thêm 1 hop
    SELECT DISTINCT ad2.account_id, ca.depth + 1
    FROM connected_accounts ca
    JOIN account_devices ad1 ON ca.account_id = ad1.account_id
    JOIN account_devices ad2 ON ad1.device_id = ad2.device_id
    WHERE ad2.account_id NOT IN (SELECT account_id FROM connected_accounts)
      AND ca.depth < 3
)
SELECT * FROM connected_accounts;

-- Vấn đề:
-- 1. Mỗi hop = thêm 1 JOIN → O(n^k) với k = số hops
-- 2. Phải JOINs riêng cho devices, IPs, phones → UNION ALL phức tạp
-- 3. Cycle detection phải tự implement
-- 4. Với 10M accounts, 3 hops mất > 30 giây
-- 5. 5 hops có thể mất hàng phút hoặc timeout
```

**Neo4j approach (Cypher):**

```cypher
// Cùng query — tìm connected accounts trong 1-5 hops qua BẤT KỲ shared resource nào
// ✅ Hoàn thành trong milliseconds, ngay cả ở 5+ hops

MATCH path = (suspect:Account {account_id: 'ACC_SUSPECT_001'})
              -[:OWNS_DEVICE|LOGGED_FROM|HAS_PHONE*1..5]-
              (connected:Account)
WHERE suspect <> connected
RETURN DISTINCT connected.account_id, length(path) AS hops
ORDER BY hops ASC

// Neo4j sử dụng index-free adjacency:
// - Mỗi node lưu trực tiếp pointer đến neighbors
// - Traversal = pointer following, không cần JOIN
// - O(k) với k = số hops, KHÔNG phụ thuộc vào tổng số nodes
```

### 2.2 Real-time Fraud Scoring — Chấm điểm gian lận thời gian thực

Khi một giao dịch mới đến, VietPay cần đánh giá rủi ro **trong < 100ms**:

```cypher
// Real-time fraud score: kiểm tra account có liên kết đến known fraud không
MATCH (account:Account {account_id: $account_id})
OPTIONAL MATCH (account)-[:OWNS_DEVICE]->(d:Device)<-[:OWNS_DEVICE]-(other:Account)
WHERE other.fraud_flag = true
WITH account, count(DISTINCT other) AS fraud_device_connections

OPTIONAL MATCH (account)-[:LOGGED_FROM]->(ip:IPAddress)<-[:LOGGED_FROM]-(other2:Account)
WHERE other2.fraud_flag = true
WITH account, fraud_device_connections, count(DISTINCT other2) AS fraud_ip_connections

OPTIONAL MATCH (account)-[:HAS_PHONE]->(p:PhoneNumber)<-[:HAS_PHONE]-(other3:Account)
WHERE other3.fraud_flag = true

RETURN account.account_id,
       fraud_device_connections,
       fraud_ip_connections,
       count(DISTINCT other3) AS fraud_phone_connections,
       // Weighted fraud score
       fraud_device_connections * 40 + 
       fraud_ip_connections * 30 + 
       count(DISTINCT other3) * 30 AS fraud_proximity_score
```

### 2.3 SQL Recursive CTEs — Giới hạn thực tế

| Số hops | PostgreSQL CTE (10M accounts) | Neo4j Traversal | Ghi chú |
|---------|------------------------------|-----------------|---------|
| 1 | ~50ms | ~5ms | Cả hai đều nhanh |
| 2 | ~200ms | ~10ms | SQL bắt đầu chậm |
| 3 | ~2-5s | ~15ms | SQL chậm rõ rệt |
| 4 | ~30-60s | ~25ms | SQL không khả thi cho real-time |
| 5 | Timeout / OOM | ~40ms | SQL thực tế không thể |
| 6+ | Không thể | ~60ms | Chỉ graph DB mới handle được |

**Nguyên nhân kỹ thuật:**
- PostgreSQL: Mỗi hop = hash join / nested loop join trên toàn bộ table → cost nhân lên
- Neo4j: Mỗi hop = follow pointers từ node hiện tại → cost cộng dồn tuyến tính

### 2.4 Pattern Matching — Phát hiện mẫu gian lận tự nhiên

Neo4j cho phép mô tả fraud patterns bằng **visual ASCII art**, gần giống cách vẽ trên whiteboard:

```cypher
// Pattern: Money laundering circle (vòng rửa tiền)
// A → B → C → D → A (tiền quay vòng trở lại)

MATCH circle = (a:Account)-[:SENT_TO]->(b:Account)
               -[:SENT_TO]->(c:Account)-[:SENT_TO]->(d:Account)
               -[:SENT_TO]->(a)
WHERE a <> b AND a <> c AND a <> d
  AND b <> c AND b <> d AND c <> d
RETURN circle

// Pattern: Star topology (1 tài khoản hub nhận từ nhiều nguồn)
MATCH (source:Account)-[t:SENT_TO]->(hub:Account)
WITH hub, count(DISTINCT source) AS source_count, 
     sum(t.amount) AS total_received
WHERE source_count > 10 AND total_received > 100000000
RETURN hub, source_count, total_received
```

Trong SQL, mô tả patterns vòng tròn hoặc star topology yêu cầu self-joins phức tạp và hard-coded cho mỗi pattern size.

---

## 3. Graph Model — Mô hình đồ thị

### 3.1 Tổng quan mô hình

```
                    ┌──────────┐
                    │  Device  │
                    │ (Node)   │
                    └────┬─────┘
                         │ OWNS_DEVICE
                         │
┌──────────┐    ┌────────┴────────┐    ┌─────────────┐
│IPAddress │────│    Account      │────│ PhoneNumber  │
│ (Node)   │ LF │    (Node)       │ HP │   (Node)     │
└──────────┘    └───┬────────┬────┘    └─────────────┘
                    │        │
              SENT_TO   RECEIVED_FROM
                    │        │
                ┌───┴────────┴───┐
                │  Transaction   │
                │    (Node)      │
                └───────┬────────┘
                        │ TRANSACTED_WITH
                        │
                  ┌─────┴──────┐
                  │  Merchant  │
                  │   (Node)   │
                  └────────────┘

Chú thích:
  LF = LOGGED_FROM
  HP = HAS_PHONE
```

### 3.2 Node Definitions — Định nghĩa Nodes

#### Node: Account

| Property | Type | Mô tả | Ví dụ |
|----------|------|--------|-------|
| `account_id` | String | **PK** — ID tài khoản từ PostgreSQL | `"ACC_001"` |
| `full_name` | String | Tên đầy đủ | `"Nguyễn Văn A"` |
| `phone_primary` | String | SĐT chính | `"+84901234567"` |
| `email` | String | Email đăng ký | `"user@email.com"` |
| `kyc_level` | Integer | Mức KYC (0-3) | `2` |
| `account_status` | String | Trạng thái | `"active"` / `"suspended"` / `"closed"` |
| `created_at` | DateTime | Ngày tạo tài khoản | `2025-01-15T10:00:00Z` |
| `fraud_flag` | Boolean | Đã bị đánh dấu gian lận | `false` |
| `fraud_score` | Float | Điểm rủi ro gian lận (0-100) | `15.5` |
| `risk_tier` | String | Mức rủi ro | `"low"` / `"medium"` / `"high"` / `"critical"` |
| `total_transaction_count` | Integer | Tổng số giao dịch | `156` |
| `total_transaction_volume` | Float | Tổng giá trị giao dịch (VND) | `45000000.0` |

**Constraints & Indexes:**
```cypher
CREATE CONSTRAINT account_id_unique FOR (a:Account) REQUIRE a.account_id IS UNIQUE;
CREATE INDEX account_fraud_flag FOR (a:Account) ON (a.fraud_flag);
CREATE INDEX account_risk_tier FOR (a:Account) ON (a.risk_tier);
CREATE INDEX account_created_at FOR (a:Account) ON (a.created_at);
```

#### Node: Device

| Property | Type | Mô tả | Ví dụ |
|----------|------|--------|-------|
| `device_id` | String | **PK** — Device fingerprint hash | `"DEV_FP_abc123"` |
| `device_type` | String | Loại thiết bị | `"mobile"` / `"desktop"` / `"tablet"` |
| `os` | String | Hệ điều hành | `"Android 14"` |
| `browser` | String | Trình duyệt (nếu web) | `"Chrome 126"` |
| `brand` | String | Hãng thiết bị | `"Samsung"` |
| `model` | String | Model | `"Galaxy S24"` |
| `fingerprint_hash` | String | Browser/device fingerprint | `"fp_sha256_xyz"` |
| `first_seen` | DateTime | Lần đầu xuất hiện | `2025-06-01T08:00:00Z` |
| `last_seen` | DateTime | Lần cuối xuất hiện | `2026-06-23T14:30:00Z` |
| `is_emulator` | Boolean | Có phải emulator không | `false` |
| `is_rooted` | Boolean | Thiết bị đã root/jailbreak | `false` |

**Constraints & Indexes:**
```cypher
CREATE CONSTRAINT device_id_unique FOR (d:Device) REQUIRE d.device_id IS UNIQUE;
CREATE INDEX device_fingerprint FOR (d:Device) ON (d.fingerprint_hash);
CREATE INDEX device_type FOR (d:Device) ON (d.device_type);
```

#### Node: IPAddress

| Property | Type | Mô tả | Ví dụ |
|----------|------|--------|-------|
| `ip_address` | String | **PK** — Địa chỉ IP | `"113.160.92.100"` |
| `ip_type` | String | Loại IP | `"residential"` / `"datacenter"` / `"vpn"` / `"tor"` |
| `country_code` | String | Quốc gia (GeoIP) | `"VN"` |
| `city` | String | Thành phố (GeoIP) | `"Ho Chi Minh City"` |
| `isp` | String | Nhà mạng | `"Viettel"` |
| `asn` | Integer | Autonomous System Number | `7552` |
| `is_proxy` | Boolean | Có phải proxy không | `false` |
| `is_vpn` | Boolean | Có phải VPN không | `false` |
| `is_tor` | Boolean | Có phải Tor exit node | `false` |
| `threat_score` | Float | Điểm đe dọa (0-100) | `5.0` |
| `first_seen` | DateTime | Lần đầu xuất hiện | `2025-03-15T12:00:00Z` |

**Constraints & Indexes:**
```cypher
CREATE CONSTRAINT ip_address_unique FOR (ip:IPAddress) REQUIRE ip.ip_address IS UNIQUE;
CREATE INDEX ip_type FOR (ip:IPAddress) ON (ip.ip_type);
CREATE INDEX ip_country FOR (ip:IPAddress) ON (ip.country_code);
CREATE INDEX ip_threat FOR (ip:IPAddress) ON (ip.threat_score);
```

#### Node: PhoneNumber

| Property | Type | Mô tả | Ví dụ |
|----------|------|--------|-------|
| `phone_number` | String | **PK** — SĐT chuẩn hóa E.164 | `"+84901234567"` |
| `country_code` | String | Mã quốc gia | `"+84"` |
| `carrier` | String | Nhà mạng | `"Viettel"` |
| `phone_type` | String | Loại SĐT | `"mobile"` / `"landline"` / `"voip"` |
| `is_virtual` | Boolean | SĐT ảo (VoIP) | `false` |
| `registered_name` | String | Tên đăng ký SĐT | `"Nguyễn Văn A"` |
| `first_seen` | DateTime | Lần đầu liên kết | `2025-01-15T10:00:00Z` |

**Constraints & Indexes:**
```cypher
CREATE CONSTRAINT phone_unique FOR (p:PhoneNumber) REQUIRE p.phone_number IS UNIQUE;
CREATE INDEX phone_carrier FOR (p:PhoneNumber) ON (p.carrier);
CREATE INDEX phone_virtual FOR (p:PhoneNumber) ON (p.is_virtual);
```

#### Node: Transaction

| Property | Type | Mô tả | Ví dụ |
|----------|------|--------|-------|
| `transaction_id` | String | **PK** — ID giao dịch | `"TXN_VP_20260623_001"` |
| `amount` | Float | Số tiền (VND) | `1500000.0` |
| `currency` | String | Loại tiền | `"VND"` |
| `transaction_type` | String | Loại giao dịch | `"transfer"` / `"payment"` / `"withdrawal"` |
| `status` | String | Trạng thái | `"completed"` / `"failed"` / `"reversed"` |
| `channel` | String | Kênh giao dịch | `"app"` / `"pos"` / `"web"` / `"qr"` |
| `created_at` | DateTime | Thời điểm tạo | `2026-06-23T14:30:00Z` |
| `completed_at` | DateTime | Thời điểm hoàn thành | `2026-06-23T14:30:02Z` |
| `description` | String | Nội dung chuyển khoản | `"Thanh toán đơn hàng"` |
| `risk_score` | Float | Điểm rủi ro (0-100) | `12.0` |
| `is_flagged` | Boolean | Đã bị flag | `false` |

**Constraints & Indexes:**
```cypher
CREATE CONSTRAINT txn_id_unique FOR (t:Transaction) REQUIRE t.transaction_id IS UNIQUE;
CREATE INDEX txn_created_at FOR (t:Transaction) ON (t.created_at);
CREATE INDEX txn_amount FOR (t:Transaction) ON (t.amount);
CREATE INDEX txn_status FOR (t:Transaction) ON (t.status);
CREATE INDEX txn_flagged FOR (t:Transaction) ON (t.is_flagged);
```

#### Node: Merchant

| Property | Type | Mô tả | Ví dụ |
|----------|------|--------|-------|
| `merchant_id` | String | **PK** — ID merchant | `"MCH_COFFEE_001"` |
| `merchant_name` | String | Tên thương hiệu | `"Coffee House"` |
| `mcc` | String | Merchant Category Code | `"5814"` |
| `mcc_description` | String | Mô tả MCC | `"Fast Food Restaurants"` |
| `city` | String | Thành phố | `"Ho Chi Minh City"` |
| `district` | String | Quận/Huyện | `"Quận 1"` |
| `registration_date` | DateTime | Ngày đăng ký | `2024-06-01T00:00:00Z` |
| `risk_tier` | String | Mức rủi ro merchant | `"low"` |
| `chargeback_rate` | Float | Tỷ lệ chargeback (%) | `0.15` |
| `monthly_volume` | Float | Doanh số tháng (VND) | `500000000.0` |

**Constraints & Indexes:**
```cypher
CREATE CONSTRAINT merchant_id_unique FOR (m:Merchant) REQUIRE m.merchant_id IS UNIQUE;
CREATE INDEX merchant_mcc FOR (m:Merchant) ON (m.mcc);
CREATE INDEX merchant_risk FOR (m:Merchant) ON (m.risk_tier);
```

### 3.3 Relationship Definitions — Định nghĩa Relationships

#### Relationship: OWNS_DEVICE

```
(Account)-[:OWNS_DEVICE]->(Device)
```

| Property | Type | Mô tả | Ví dụ |
|----------|------|--------|-------|
| `first_used` | DateTime | Lần đầu dùng device | `2025-06-01T08:00:00Z` |
| `last_used` | DateTime | Lần cuối dùng | `2026-06-23T14:30:00Z` |
| `login_count` | Integer | Số lần login từ device | `245` |
| `is_primary` | Boolean | Device chính | `true` |
| `registered_via` | String | Đăng ký qua device này | `"app_install"` |

**Ý nghĩa**: Một account có thể sở hữu nhiều devices, và một device bất thường có thể được nhiều accounts sử dụng (dấu hiệu fraud).

#### Relationship: LOGGED_FROM

```
(Account)-[:LOGGED_FROM]->(IPAddress)
```

| Property | Type | Mô tả | Ví dụ |
|----------|------|--------|-------|
| `first_login` | DateTime | Lần đầu login từ IP | `2025-03-15T12:00:00Z` |
| `last_login` | DateTime | Lần cuối login | `2026-06-23T14:29:00Z` |
| `login_count` | Integer | Số lần login | `89` |
| `is_usual` | Boolean | IP thường dùng | `true` |

**Ý nghĩa**: Nhiều accounts login từ cùng IP datacenter/VPN → potential fraud ring.

#### Relationship: HAS_PHONE

```
(Account)-[:HAS_PHONE]->(PhoneNumber)
```

| Property | Type | Mô tả | Ví dụ |
|----------|------|--------|-------|
| `registered_at` | DateTime | Ngày gắn SĐT | `2025-01-15T10:00:00Z` |
| `is_primary` | Boolean | SĐT chính | `true` |
| `verified` | Boolean | Đã xác minh OTP | `true` |
| `removed_at` | DateTime / null | Ngày gỡ (nếu có) | `null` |

**Ý nghĩa**: Nhiều accounts dùng chung SĐT → possible synthetic identity fraud.

#### Relationship: SENT_TO

```
(Account)-[:SENT_TO {via: Transaction}]->(Account)
```

| Property | Type | Mô tả | Ví dụ |
|----------|------|--------|-------|
| `transaction_id` | String | ID giao dịch | `"TXN_VP_001"` |
| `amount` | Float | Số tiền | `5000000.0` |
| `currency` | String | Loại tiền | `"VND"` |
| `created_at` | DateTime | Thời điểm | `2026-06-23T14:30:00Z` |
| `channel` | String | Kênh | `"app"` |
| `description` | String | Nội dung | `"Chuyển tiền"` |

**Ý nghĩa**: Mạng lưới chuyển tiền giữa accounts — pattern chuyển tiền vòng = money laundering.

#### Relationship: RECEIVED_FROM

```
(Account)-[:RECEIVED_FROM {via: Transaction}]->(Account)
```

Inverse relationship của SENT_TO — cùng properties. Lưu cả hai chiều để query hiệu quả hơn (bidirectional traversal mà không cần reverse direction).

#### Relationship: TRANSACTED_WITH

```
(Account)-[:TRANSACTED_WITH]->(Merchant)
```

| Property | Type | Mô tả | Ví dụ |
|----------|------|--------|-------|
| `transaction_count` | Integer | Số giao dịch | `15` |
| `total_amount` | Float | Tổng chi tiêu | `2500000.0` |
| `first_transaction` | DateTime | Giao dịch đầu tiên | `2025-08-01T09:00:00Z` |
| `last_transaction` | DateTime | Giao dịch gần nhất | `2026-06-23T14:30:00Z` |
| `avg_amount` | Float | Trung bình mỗi GD | `166666.67` |

**Ý nghĩa**: Pattern mua hàng bất thường tại merchant → potential card testing hoặc collusive fraud.

### 3.4 Mô hình Visual — Ví dụ Fraud Ring

```
Fraud Ring Example — 4 accounts dùng chung resources:

    Account_A ──OWNS_DEVICE──► Device_X ◄──OWNS_DEVICE── Account_B
        │                                                      │
    LOGGED_FROM                                          LOGGED_FROM
        │                                                      │
        ▼                                                      ▼
    IP_Datacenter_1 ◄─────────LOGGED_FROM──────────── Account_C
                                                           │
                                                       HAS_PHONE
                                                           │
                                                           ▼
    Account_D ──────────HAS_PHONE──────────────► Phone_VoIP_1

    Money flow: A ──SENT_TO──► B ──SENT_TO──► C ──SENT_TO──► D ──SENT_TO──► A
                (vòng tròn chuyển tiền — money laundering pattern)

    Detection score:
    - 4 accounts chia sẻ device/IP/phone = HIGH risk
    - Circular money flow detected = CRITICAL
    - VoIP phone number involved = additional risk factor
    - Datacenter IP = additional risk factor
```

---

## 4. Use Case Scenarios — Các kịch bản phát hiện gian lận

### 4.1 Scenario: Shared Device Fraud Ring

**Mô tả**: Phát hiện nhóm accounts sử dụng chung thiết bị — dấu hiệu mạnh nhất của fraud ring, vì người dùng thật hiếm khi chia sẻ thiết bị.

**Cypher Query**: Xem file `cypher-queries.cypher` — Query 1

**Tiêu chí phát hiện**:
- Một device được > 3 accounts sử dụng → **WARNING**
- Một device được > 5 accounts sử dụng → **CRITICAL**
- Device là emulator hoặc rooted → nhân risk score × 2

### 4.2 Scenario: Circular Money Flow (Money Laundering)

**Mô tả**: Phát hiện tiền chuyển vòng qua chuỗi accounts và quay lại account gốc. Đây là pattern kinh điển của money laundering.

**Cypher Query**: Xem file `cypher-queries.cypher` — Query 2

**Tiêu chí phát hiện**:
- Vòng 3-4 accounts, tổng giá trị > 50,000,000 VND → **ALERT**
- Các giao dịch trong vòng diễn ra trong < 24 giờ → **HIGH RISK**
- Amount giảm dần (trừ "phí") qua mỗi hop → classic layering pattern

### 4.3 Scenario: Rapid Sequential Transactions

**Mô tả**: Phát hiện chuỗi giao dịch nhanh bất thường giữa các accounts có kết nối — dấu hiệu automated fraud hoặc cash-out scheme.

**Cypher Query**: Xem file `cypher-queries.cypher` — Query 3

**Tiêu chí phát hiện**:
- > 5 giao dịch giữa 2 accounts trong 1 giờ → **SUSPICIOUS**
- Amounts tăng dần (testing limits) → **HIGH RISK**
- Account mới (< 7 ngày) + giao dịch lớn → **CRITICAL**

### 4.4 Scenario: Community Detection (Fraud Cluster)

**Mô tả**: Sử dụng thuật toán graph community detection để tìm clusters of highly interconnected accounts — có thể là organized fraud ring.

**Cypher Query**: Xem file `cypher-queries.cypher` — Query 4

**Tiêu chí phát hiện**:
- Community > 5 accounts với > 10 internal connections → **INVESTIGATE**
- Community có > 50% accounts mới (< 30 ngày) → **HIGH RISK**
- Community có tổng giao dịch nội bộ > 100,000,000 VND → **CRITICAL**

### 4.5 Scenario: Shortest Path Between Suspicious Accounts

**Mô tả**: Khi nhận được report về 2 accounts nghi vấn, tìm đường đi ngắn nhất giữa chúng để hiểu mối liên hệ.

**Cypher Query**: Xem file `cypher-queries.cypher` — Query 5

**Ứng dụng**:
- Law enforcement request: "Account A và B có liên quan không?"
- Internal investigation: "Tìm chuỗi kết nối giữa 2 fraud cases"
- Compliance: Báo cáo cho NHNN về mạng lưới nghi vấn

---

## 5. Performance và Scaling

### 5.1 Sizing Estimates

| Metric | Giá trị ước tính | Ghi chú |
|--------|------------------|---------|
| Accounts | 5,000,000 | Active accounts |
| Devices | 8,000,000 | Nhiều devices per account |
| IP Addresses | 2,000,000 | Unique IPs |
| Phone Numbers | 6,000,000 | Including inactive |
| Transactions | 100,000,000/tháng | Giao dịch tháng |
| Merchants | 50,000 | Active merchants |
| OWNS_DEVICE relationships | 12,000,000 | |
| LOGGED_FROM relationships | 15,000,000 | |
| SENT_TO relationships | 100,000,000/tháng | |
| **Total graph size** | **~25 GB in memory** | Working set (3 months) |

### 5.2 Hardware Recommendations

```
Production Neo4j Cluster:
├── Primary (Read/Write)
│   ├── RAM: 64 GB (heap: 31 GB + page cache: 25 GB)
│   ├── CPU: 16 cores
│   ├── Storage: 500 GB NVMe SSD
│   └── Network: 10 Gbps
│
├── Secondary #1 (Read replica)
│   └── Same specs — for fraud scoring queries
│
├── Secondary #2 (Read replica)
│   └── Same specs — for analytics/investigation queries
│
└── Config:
    ├── dbms.memory.heap.initial_size=31g
    ├── dbms.memory.heap.max_size=31g
    ├── dbms.memory.pagecache.size=25g
    └── dbms.jvm.additional=-XX:+UseG1GC
```

### 5.3 Data Pipeline

```
PostgreSQL (source of truth)
    │
    ├── New Account created ──CDC──► Kafka ──► Neo4j: CREATE Account node
    ├── New Transaction ──CDC──► Kafka ──► Neo4j: CREATE Transaction + relationships
    ├── Device login ──CDC──► Kafka ──► Neo4j: MERGE Device + OWNS_DEVICE
    └── IP login ──CDC──► Kafka ──► Neo4j: MERGE IPAddress + LOGGED_FROM
    
Lag target: < 5 giây từ PostgreSQL đến Neo4j
```

---

## 6. Integration Architecture

### 6.1 Fraud Detection Pipeline

```
Incoming Transaction Request
         │
         ▼
┌─────────────────────┐
│  Transaction Service │
│  (Microservice)     │
└────────┬────────────┘
         │ gRPC call (< 100ms SLA)
         ▼
┌─────────────────────┐     ┌────────────────┐
│  Fraud Scoring      │────►│   Neo4j        │
│  Service            │     │   (Real-time   │
│                     │◄────│    queries)    │
└────────┬────────────┘     └────────────────┘
         │
         │ fraud_score + decision
         ▼
┌─────────────────────┐
│  Decision Engine    │
│  score < 30: ALLOW  │
│  30-70: REVIEW      │
│  > 70: BLOCK        │
└─────────────────────┘
```

### 6.2 Data Retention trong Neo4j

| Data | Retention | Lý do |
|------|-----------|-------|
| Account nodes | Permanent | Core entity |
| Device/IP/Phone nodes | 1 năm sau last_seen | Giải phóng memory |
| Transaction relationships | 3 tháng | Working set cho pattern detection |
| SENT_TO (aggregated) | 1 năm | Aggregated counts/amounts |
| Fraud flags | Permanent | Historical fraud database |

### 6.3 API Endpoints cho Fraud Service

| Endpoint | Method | Neo4j Query | SLA |
|----------|--------|-------------|-----|
| `/fraud/score/{account_id}` | GET | Fraud proximity score | < 100ms |
| `/fraud/connections/{account_id}` | GET | Connected accounts (2 hops) | < 200ms |
| `/fraud/ring-check/{account_id}` | GET | Check membership in fraud ring | < 500ms |
| `/fraud/path/{from}/{to}` | GET | Shortest path between accounts | < 300ms |
| `/fraud/community/{account_id}` | GET | Community detection | < 1s |

---

> **Tài liệu tham khảo:**
> - [Neo4j Graph Data Science Library](https://neo4j.com/docs/graph-data-science/)
> - [Fraud Detection with Neo4j](https://neo4j.com/use-cases/fraud-detection/)
> - [Financial Crime Pattern Detection](https://neo4j.com/developer/guide-fraud-detection/)
> - NHNN Circular on AML/CFT (Thông tư 09/2023/TT-NHNN)


---

!!! info "Nguồn gốc"
    `vietpay/neo4j/fraud-detection-model.md`
