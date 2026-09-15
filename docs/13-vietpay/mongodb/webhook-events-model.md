---
title: MongoDB — Document Store Model cho VietPay Webhook Events
course: 13-vietpay
source: vietpay/mongodb/webhook-events-model.md
---

# MongoDB — Document Store Model cho VietPay Webhook Events

> **Phiên bản**: 1.0  
> **Ngày tạo**: 2026-06-23  
> **Tác giả**: VietPay DBA Team  
> **Trạng thái**: Proposed

---

## Mục lục

1. [Use Case — Bối cảnh sử dụng](#1-use-case--bối-cảnh-sử-dụng)
2. [Tại sao chọn MongoDB thay vì PostgreSQL JSONB](#2-tại-sao-chọn-mongodb-thay-vì-postgresql-jsonb)
3. [Collection Design — Thiết kế Collection](#3-collection-design--thiết-kế-collection)
4. [Index Strategy — Chiến lược Index](#4-index-strategy--chiến-lược-index)
5. [Sharding Strategy — Chiến lược Sharding](#5-sharding-strategy--chiến-lược-sharding)
6. [Aggregation Pipeline Examples](#6-aggregation-pipeline-examples)
7. [Data Lifecycle Management](#7-data-lifecycle-management)
8. [Monitoring và Operational Considerations](#8-monitoring-và-operational-considerations)

---

## 1. Use Case — Bối cảnh sử dụng

### 1.1 Vấn đề cần giải quyết

VietPay tích hợp với nhiều payment provider khác nhau (Visa, Mastercard, Napas, VNPay, banking APIs của các ngân hàng đối tác). Mỗi provider gửi webhook/event payload với **schema hoàn toàn khác nhau**:

| Provider | Định dạng payload | Đặc điểm |
|----------|-------------------|-----------|
| **Visa** | JSON phức tạp, nhiều nested objects | Có `transactionIdentifier`, `merchantVerificationValue` |
| **Mastercard** | JSON chuẩn ISO 8583 mapped | Có `DE` fields (Data Elements), bitmap-based |
| **Napas** | JSON riêng theo chuẩn Napas | Có `napas_trace`, `ben_id`, `bank_code` |
| **VNPay** | Query string encoded → JSON | Có `vnp_TxnRef`, `vnp_SecureHash` |
| **Banking APIs** | Mỗi ngân hàng có format riêng | Vietcombank, Techcombank, BIDV, etc. |

### 1.2 Yêu cầu hệ thống

- **Throughput**: 5,000 – 20,000 webhook events/giây trong peak hours
- **Latency**: Ghi nhận webhook < 50ms (p99) để trả HTTP 200 cho provider
- **Retention**: Raw events lưu 90 ngày, aggregated metrics lưu 2 năm
- **Query patterns**: 
  - Lookup theo `event_id`, `transaction_id`, `provider`
  - Range query theo `received_at` cho audit/troubleshooting
  - Aggregation cho analytics và reconciliation
- **Compliance**: PCI-DSS yêu cầu lưu trữ audit trail đầy đủ

### 1.3 Luồng dữ liệu

```
Payment Provider → HTTPS Webhook → API Gateway → Kafka Topic
                                                      ↓
                                        ┌──────────────┴──────────────┐
                                        ↓                             ↓
                               MongoDB (Raw Store)         PostgreSQL (Processed)
                               - Lưu nguyên bản payload    - Cập nhật trạng thái giao dịch
                               - Schema-less ingestion      - Ledger entries
                               - Audit/compliance           - Balance updates
```

---

## 2. Tại sao chọn MongoDB thay vì PostgreSQL JSONB

### 2.1 Schema-less Ingestion — Khả năng tiếp nhận dữ liệu không cần schema cố định

**Vấn đề với PostgreSQL JSONB:**

```sql
-- PostgreSQL: Phải biết trước cấu trúc để query hiệu quả
CREATE TABLE webhook_events (
    id UUID PRIMARY KEY,
    provider TEXT NOT NULL,
    payload JSONB NOT NULL,
    received_at TIMESTAMPTZ NOT NULL
);

-- Query JSONB phức tạp, khó tối ưu
SELECT * FROM webhook_events 
WHERE payload->>'transactionId' = 'TXN123'
  AND payload->'metadata'->>'merchantId' = 'MCH456';

-- GIN index trên toàn bộ payload rất tốn tài nguyên
CREATE INDEX idx_payload ON webhook_events USING GIN (payload jsonb_path_ops);
```

**Ưu điểm MongoDB:**

```javascript
// MongoDB: Insert trực tiếp, không cần biết schema trước
db.webhook_events.insertOne({
    event_id: "evt_visa_20260623_001",
    provider: "visa",
    event_type: "payment.completed",
    // Visa payload — schema riêng
    payload: {
        transactionIdentifier: "TXN_VISA_001",
        merchantVerificationValue: "MVV123",
        authorizationCode: "AUTH456",
        cardAcceptorData: {
            name: "VietPay Merchant",
            city: "Ho Chi Minh",
            countryCode: "VN"
        }
    },
    received_at: ISODate("2026-06-23T10:30:00Z")
});

// Napas payload — schema hoàn toàn khác
db.webhook_events.insertOne({
    event_id: "evt_napas_20260623_002",
    provider: "napas",
    event_type: "payment.completed",
    payload: {
        napas_trace: "NAP20260623001",
        ben_id: "970436",
        bank_code: "VCB",
        amount: 1500000,
        currency: "VND",
        response_code: "00"
    },
    received_at: ISODate("2026-06-23T10:30:01Z")
});
```

**So sánh chi tiết:**

| Tiêu chí | PostgreSQL JSONB | MongoDB |
|-----------|-----------------|---------|
| Schema validation | Phải tự implement với CHECK hoặc triggers | JSON Schema Validation tích hợp, áp dụng per-collection |
| Nested query | `payload->'a'->'b'->>'c'` — cú pháp khó đọc | `payload.a.b.c` — dot notation tự nhiên |
| Array operations | `jsonb_array_elements()` — cần lateral join | `$elemMatch`, `$unwind` — native operators |
| Partial index trên nested field | Hỗ trợ nhưng cú pháp phức tạp | Wildcard indexes, partial indexes tự nhiên |
| Full-text search trong JSONB | Phải extract text ra column riêng | `$text` index trực tiếp trên document fields |

### 2.2 Horizontal Scalability — Khả năng mở rộng ngang

**PostgreSQL limitations:**
- Vertical scaling chủ yếu (thêm CPU, RAM, SSD)
- Logical replication cho read replicas nhưng tất cả writes đều đi vào primary
- Citus extension hỗ trợ sharding nhưng tăng độ phức tạp vận hành
- Partitioning (range/hash) giới hạn trong single node

**MongoDB sharding:**
- Native sharding — chia dữ liệu across multiple nodes tự động
- Horizontal write scaling — mỗi shard nhận writes độc lập
- Auto-balancing — MongoDB tự di chuyển chunks giữa các shards
- Với shard key `{provider: 1, received_at: 1}`:
  - Visa events → Shard A, B
  - Mastercard events → Shard C, D
  - Napas events → Shard E
  - Writes phân tán đều, tránh hotspot

```
                    mongos (Router)
                   /       |        \
            Shard 1     Shard 2     Shard 3
           (visa-Q1)   (visa-Q2)   (mastercard)
           RS: P+S+S   RS: P+S+S   RS: P+S+S
```

### 2.3 TTL Indexes — Tự động quản lý vòng đời dữ liệu

```javascript
// MongoDB: TTL index xóa documents sau 90 ngày — ZERO application code
db.webhook_events.createIndex(
    { "received_at": 1 },
    { expireAfterSeconds: 7776000 } // 90 days = 90 * 24 * 3600
);
```

```sql
-- PostgreSQL: Phải tự implement với pg_cron hoặc pg_partman
-- Option 1: pg_cron job — phải manage thêm extension
SELECT cron.schedule('0 2 * * *', $$
    DELETE FROM webhook_events 
    WHERE received_at < NOW() - INTERVAL '90 days'
$$);
-- Vấn đề: DELETE hàng triệu rows gây vacuum pressure, lock contention

-- Option 2: Partition by range + drop partition
-- Phức tạp hơn nhưng hiệu quả hơn
CREATE TABLE webhook_events_2026_q1 PARTITION OF webhook_events
    FOR VALUES FROM ('2026-01-01') TO ('2026-04-01');
-- Phải tạo partition mới trước khi cần, drop partition cũ manually
```

### 2.4 Native Document Queries vs Limited JSONB Operators

```javascript
// MongoDB: Aggregation pipeline — mạnh mẽ và linh hoạt
db.webhook_events.aggregate([
    { $match: { 
        provider: "visa", 
        "payload.transactionAmount": { $gte: 10000000 },
        received_at: { $gte: ISODate("2026-06-01") }
    }},
    { $group: { 
        _id: "$payload.cardAcceptorData.city",
        total_amount: { $sum: "$payload.transactionAmount" },
        count: { $sum: 1 },
        avg_amount: { $avg: "$payload.transactionAmount" }
    }},
    { $sort: { total_amount: -1 } },
    { $limit: 10 }
]);
```

```sql
-- PostgreSQL JSONB: Cùng logic nhưng phức tạp hơn rất nhiều
SELECT 
    payload->'cardAcceptorData'->>'city' AS city,
    SUM((payload->>'transactionAmount')::NUMERIC) AS total_amount,
    COUNT(*) AS count,
    AVG((payload->>'transactionAmount')::NUMERIC) AS avg_amount
FROM webhook_events
WHERE provider = 'visa'
  AND (payload->>'transactionAmount')::NUMERIC >= 10000000
  AND received_at >= '2026-06-01'
GROUP BY payload->'cardAcceptorData'->>'city'
ORDER BY total_amount DESC
LIMIT 10;
-- Vấn đề: Cast liên tục, GIN index không giúp range queries trên nested values
```

### 2.5 Operational Isolation — Cô lập vận hành

Đây là yếu tố quan trọng nhất trong kiến trúc fintech:

| Khía cạnh | Nếu dùng chung PostgreSQL | Khi tách ra MongoDB |
|-----------|--------------------------|---------------------|
| **Write amplification** | Webhook writes cạnh tranh I/O với ledger updates | Hoàn toàn độc lập |
| **Vacuum pressure** | TTL deletes tạo dead tuples, ảnh hưởng autovacuum cho core tables | MongoDB reclaims space riêng |
| **Connection pool** | Webhook ingestion chiếm connections từ core OLTP | Connection pools tách biệt |
| **Backup/Restore** | Backup chậm hơn do data webhook chiếm majority storage | Backup policies riêng |
| **Resource contention** | Shared buffer cache bị ô nhiễm bởi webhook scans | Separate WiredTiger cache |
| **Failure blast radius** | Webhook storage issue → core payment affected | Webhook down ≠ payment down |

**Kết luận**: MongoDB cho webhook events là **polyglot persistence** hợp lý — chọn đúng database cho đúng workload.

---

## 3. Collection Design — Thiết kế Collection

### 3.1 Collection `webhook_events`

Đây là collection chính, lưu trữ **raw webhook payload** nguyên bản từ payment providers.

**Thiết kế document:**

```javascript
{
    // === Metadata fields (controlled by VietPay) ===
    _id: ObjectId("667916a0e4b0f1a2b3c4d5e6"),
    
    // Unique event identifier — idempotency key
    event_id: "evt_visa_20260623_143022_a1b2c3",
    
    // Provider identification
    provider: "visa",                    // enum: visa, mastercard, napas, vnpay, bank_vcb, bank_tcb, ...
    provider_event_id: "VSA_EVT_98765",  // ID từ phía provider (để đối soát)
    
    // Event classification
    event_type: "payment.completed",     // payment.completed, payment.failed, refund.initiated, 
                                         // chargeback.received, settlement.completed, etc.
    event_category: "payment",           // payment, refund, chargeback, settlement, notification
    
    // VietPay internal reference
    internal_transaction_id: "txn_vp_20260623_001",  // Mapping sang PostgreSQL transaction
    
    // === Raw payload (KHÔNG transform, lưu nguyên bản) ===
    raw_payload: {
        // Toàn bộ body từ webhook request — schema tùy thuộc provider
        transactionIdentifier: "TXN_VISA_001",
        authorizationCode: "AUTH456",
        responseCode: "00",
        transactionAmount: {
            amount: "1500000",
            currency: "VND"
        },
        cardAcceptorData: {
            name: "Coffee Shop ABC",
            city: "Ho Chi Minh City",
            countryCode: "VN",
            mcc: "5814"
        },
        pointOfServiceData: {
            entryMode: "contactless",
            terminalType: "POS"
        }
    },
    
    // === HTTP Request metadata ===
    http_metadata: {
        method: "POST",
        path: "/webhooks/visa/payment",
        headers: {
            "content-type": "application/json",
            "x-visa-signature": "sha256=abc123...",   // Signature để verify
            "x-request-id": "req_visa_xyz789",
            "user-agent": "Visa-Webhook/2.0"
        },
        source_ip: "198.51.100.42",
        received_at: ISODate("2026-06-23T14:30:22.456Z")
    },
    
    // === Processing status ===
    processing: {
        status: "processed",          // received, processing, processed, failed, retrying
        processed_at: ISODate("2026-06-23T14:30:22.789Z"),
        processing_duration_ms: 333,
        attempts: 1,
        last_error: null,
        processor_instance: "webhook-worker-03"
    },
    
    // === Signature verification ===
    verification: {
        signature_valid: true,
        verified_at: ISODate("2026-06-23T14:30:22.460Z"),
        algorithm: "HMAC-SHA256"
    },
    
    // === Extracted fields (denormalized for querying) ===
    extracted: {
        amount: NumberDecimal("1500000"),
        currency: "VND",
        merchant_id: "MCH_COFFEE_001",
        card_last_four: "4532",        // Chỉ lưu 4 số cuối (PCI-DSS compliance)
        response_code: "00",
        mcc: "5814"
    },
    
    // === Timestamps ===
    received_at: ISODate("2026-06-23T14:30:22.456Z"),   // Khi VietPay nhận webhook
    provider_timestamp: ISODate("2026-06-23T14:30:20.000Z"), // Timestamp từ provider
    created_at: ISODate("2026-06-23T14:30:22.456Z"),
    updated_at: ISODate("2026-06-23T14:30:22.789Z"),
    
    // === TTL field ===
    expires_at: ISODate("2026-09-21T14:30:22.456Z")     // 90 ngày sau received_at
}
```

**JSON Schema Validation:**

```javascript
db.createCollection("webhook_events", {
    validator: {
        $jsonSchema: {
            bsonType: "object",
            required: ["event_id", "provider", "event_type", "raw_payload", "received_at"],
            properties: {
                event_id: {
                    bsonType: "string",
                    description: "Unique event identifier — required"
                },
                provider: {
                    bsonType: "string",
                    enum: ["visa", "mastercard", "napas", "vnpay", "bank_vcb", "bank_tcb", 
                           "bank_bidv", "bank_mb", "bank_acb", "momo", "zalopay"],
                    description: "Payment provider name — must be from allowed list"
                },
                event_type: {
                    bsonType: "string",
                    pattern: "^[a-z]+\\.[a-z_]+$",
                    description: "Event type in dot notation"
                },
                raw_payload: {
                    bsonType: "object",
                    description: "Original webhook payload — must be an object"
                },
                received_at: {
                    bsonType: "date",
                    description: "Timestamp when event was received"
                },
                processing: {
                    bsonType: "object",
                    properties: {
                        status: {
                            bsonType: "string",
                            enum: ["received", "processing", "processed", "failed", "retrying"]
                        }
                    }
                }
            }
        }
    },
    validationLevel: "moderate",    // Cho phép existing documents không match
    validationAction: "warn"        // Log warning thay vì reject — quan trọng cho webhook ingestion
});
```

### 3.2 Collection `payment_notifications`

Collection này lưu trữ **outbound notifications** — thông báo VietPay gửi cho merchants/users.

```javascript
{
    _id: ObjectId("667916a0e4b0f1a2b3c4d5e7"),
    
    // Notification identification
    notification_id: "notif_20260623_001",
    
    // Reference back to webhook event
    source_event_id: "evt_visa_20260623_143022_a1b2c3",
    internal_transaction_id: "txn_vp_20260623_001",
    
    // Notification target
    target: {
        type: "merchant",                    // merchant, user, internal
        merchant_id: "MCH_COFFEE_001",
        callback_url: "https://coffee-shop.vn/api/payment-callback",
        method: "POST"
    },
    
    // Notification content (what we sent to merchant)
    payload: {
        transaction_id: "txn_vp_20260623_001",
        status: "completed",
        amount: 1500000,
        currency: "VND",
        payment_method: "visa",
        completed_at: "2026-06-23T14:30:22Z",
        merchant_reference: "ORDER_12345"
    },
    
    // Delivery tracking
    delivery: {
        status: "delivered",            // pending, sending, delivered, failed, exhausted
        attempts: [
            {
                attempt_number: 1,
                sent_at: ISODate("2026-06-23T14:30:23.100Z"),
                response_status: 200,
                response_body: "{\"received\": true}",
                response_time_ms: 150,
                success: true
            }
        ],
        total_attempts: 1,
        max_attempts: 5,
        next_retry_at: null,
        delivered_at: ISODate("2026-06-23T14:30:23.250Z")
    },
    
    // Retry configuration
    retry_config: {
        strategy: "exponential_backoff",
        base_delay_ms: 1000,
        max_delay_ms: 300000,           // 5 phút
        multiplier: 2
    },
    
    // Timestamps
    created_at: ISODate("2026-06-23T14:30:23.000Z"),
    updated_at: ISODate("2026-06-23T14:30:23.250Z"),
    expires_at: ISODate("2026-09-21T14:30:23.000Z")
}
```

### 3.3 Collection `event_processing_deadletter`

Dead letter queue cho events không thể xử lý — quan trọng cho operational reliability:

```javascript
{
    _id: ObjectId("667916a0e4b0f1a2b3c4d5e8"),
    
    original_event_id: "evt_napas_20260623_bad_001",
    provider: "napas",
    event_type: "payment.completed",
    
    // Original payload that failed processing
    raw_payload: { /* ... */ },
    
    // Error details
    error: {
        type: "VALIDATION_ERROR",
        message: "Missing required field: napas_trace",
        stack_trace: "at WebhookProcessor.validate() ...",
        error_code: "WH_VAL_001"
    },
    
    // Processing history
    processing_history: [
        {
            attempt: 1,
            processed_at: ISODate("2026-06-23T14:31:00Z"),
            error: "Missing required field: napas_trace",
            processor: "webhook-worker-01"
        },
        {
            attempt: 2,
            processed_at: ISODate("2026-06-23T14:32:00Z"),
            error: "Missing required field: napas_trace",
            processor: "webhook-worker-02"
        }
    ],
    
    // Resolution tracking
    resolution: {
        status: "unresolved",       // unresolved, investigating, resolved, ignored
        assigned_to: null,
        resolved_at: null,
        resolution_notes: null
    },
    
    moved_to_deadletter_at: ISODate("2026-06-23T14:32:00Z"),
    // Dead letter giữ lâu hơn — 1 năm
    expires_at: ISODate("2027-06-23T14:32:00Z")
}
```

---

## 4. Index Strategy — Chiến lược Index

### 4.1 Indexes cho `webhook_events`

```javascript
// ─── PRIMARY LOOKUP INDEXES ───

// 1. Unique index trên event_id — đảm bảo idempotency
//    Use case: Kiểm tra webhook đã được nhận chưa (deduplication)
db.webhook_events.createIndex(
    { "event_id": 1 },
    { unique: true, name: "idx_event_id_unique" }
);

// 2. Compound index cho lookup theo provider + thời gian
//    Use case: "Tìm tất cả Visa events trong 24h qua"
//    Query pattern: db.webhook_events.find({ provider: "visa", received_at: { $gte: ... } })
db.webhook_events.createIndex(
    { "provider": 1, "received_at": -1 },
    { name: "idx_provider_received_at" }
);

// 3. Compound index cho internal transaction lookup
//    Use case: "Tìm tất cả webhook events liên quan đến transaction X"
db.webhook_events.createIndex(
    { "internal_transaction_id": 1, "event_type": 1 },
    { name: "idx_internal_txn_event_type" }
);

// ─── QUERY OPTIMIZATION INDEXES ───

// 4. Index cho event_type + processing status
//    Use case: "Tìm tất cả payment.failed events chưa xử lý"
db.webhook_events.createIndex(
    { "event_type": 1, "processing.status": 1, "received_at": -1 },
    { name: "idx_event_type_status_time" }
);

// 5. Partial index cho failed/retrying events only
//    Use case: Dashboard hiển thị events cần attention
//    Tiết kiệm space vì chỉ index ~2% documents (98% processed thành công)
db.webhook_events.createIndex(
    { "processing.status": 1, "received_at": -1 },
    { 
        name: "idx_failed_events",
        partialFilterExpression: {
            "processing.status": { $in: ["failed", "retrying"] }
        }
    }
);

// 6. Index cho provider_event_id — đối soát với provider
//    Use case: Provider gửi inquiry "Event VSA_EVT_98765 đã nhận chưa?"
db.webhook_events.createIndex(
    { "provider_event_id": 1 },
    { name: "idx_provider_event_id", sparse: true }
);

// ─── ANALYTICS INDEXES ───

// 7. Index cho extracted fields — hỗ trợ analytics queries
db.webhook_events.createIndex(
    { "extracted.merchant_id": 1, "received_at": -1 },
    { name: "idx_merchant_time" }
);

// 8. Index cho amount range queries (reconciliation)
db.webhook_events.createIndex(
    { "extracted.amount": 1, "provider": 1 },
    { name: "idx_amount_provider" }
);

// ─── TTL INDEX ───

// 9. TTL index — tự động xóa documents sau 90 ngày
db.webhook_events.createIndex(
    { "expires_at": 1 },
    { expireAfterSeconds: 0, name: "idx_ttl_expires_at" }
);

// ─── WILDCARD INDEX (Optional — cho ad-hoc queries) ───

// 10. Wildcard index trên raw_payload cho ad-hoc troubleshooting
//     Cẩn thận: Tốn nhiều space, chỉ dùng trong dev/staging hoặc nếu thực sự cần
// db.webhook_events.createIndex(
//     { "raw_payload.$**": 1 },
//     { name: "idx_wildcard_payload" }
// );
```

### 4.2 Indexes cho `payment_notifications`

```javascript
// 1. Unique notification ID
db.payment_notifications.createIndex(
    { "notification_id": 1 },
    { unique: true, name: "idx_notification_id_unique" }
);

// 2. Lookup by source event
db.payment_notifications.createIndex(
    { "source_event_id": 1 },
    { name: "idx_source_event" }
);

// 3. Merchant callback tracking
db.payment_notifications.createIndex(
    { "target.merchant_id": 1, "delivery.status": 1 },
    { name: "idx_merchant_delivery_status" }
);

// 4. Retry queue — tìm notifications cần retry
db.payment_notifications.createIndex(
    { "delivery.status": 1, "delivery.next_retry_at": 1 },
    {
        name: "idx_retry_queue",
        partialFilterExpression: {
            "delivery.status": { $in: ["failed", "pending"] },
            "delivery.next_retry_at": { $exists: true }
        }
    }
);

// 5. TTL
db.payment_notifications.createIndex(
    { "expires_at": 1 },
    { expireAfterSeconds: 0, name: "idx_ttl_notifications" }
);
```

### 4.3 Index Size Estimation

| Collection | Index | Ước tính size (100M docs) | Ghi chú |
|-----------|-------|---------------------------|---------|
| `webhook_events` | `idx_event_id_unique` | ~4 GB | String key, unique |
| `webhook_events` | `idx_provider_received_at` | ~2.5 GB | Compound, high cardinality |
| `webhook_events` | `idx_internal_txn_event_type` | ~3 GB | Compound |
| `webhook_events` | `idx_failed_events` | ~50 MB | Partial (~2% docs) |
| `webhook_events` | `idx_ttl_expires_at` | ~1.5 GB | Date field |
| **Total working set** | | **~12 GB** | Cần fit trong RAM |

---

## 5. Sharding Strategy — Chiến lược Sharding

### 5.1 Shard Key Selection

**Shard key được chọn: `{ provider: 1, received_at: 1 }`**

**Lý do:**

| Tiêu chí | `{ provider, received_at }` | `{ event_id }` (hashed) | `{ received_at }` alone |
|-----------|---------------------------|------------------------|----------------------|
| **Write distribution** | ✅ Tốt — phân tán theo provider | ✅ Tốt — hash phân đều | ❌ Hotspot trên shard mới nhất |
| **Query isolation** | ✅ Targeted queries theo provider | ❌ Scatter-gather | ❌ Chỉ targeted cho time ranges |
| **Range queries** | ✅ Hỗ trợ time range | ❌ Không hỗ trợ range | ✅ Tốt cho time range |
| **Cardinality** | ✅ Cao (provider × time) | ✅ Rất cao | ⚠️ Trung bình |
| **Monotonic avoidance** | ✅ Provider prefix ngăn monotonic | ✅ Hash ngăn monotonic | ❌ Monotonically increasing |

### 5.2 Shard Configuration

```javascript
// Enable sharding trên database
sh.enableSharding("vietpay_webhooks");

// Shard collection với compound key
sh.shardCollection(
    "vietpay_webhooks.webhook_events",
    { "provider": 1, "received_at": 1 }
);

// Pre-split chunks cho mỗi provider để tránh balancing storm khi bắt đầu
// Giả sử 3 shards ban đầu
sh.splitAt("vietpay_webhooks.webhook_events", { provider: "mastercard", received_at: MinKey });
sh.splitAt("vietpay_webhooks.webhook_events", { provider: "napas", received_at: MinKey });
sh.splitAt("vietpay_webhooks.webhook_events", { provider: "vnpay", received_at: MinKey });

// Move chunks để phân bố đều
sh.moveChunk("vietpay_webhooks.webhook_events", 
    { provider: "mastercard", received_at: MinKey }, "shard002");
sh.moveChunk("vietpay_webhooks.webhook_events", 
    { provider: "napas", received_at: MinKey }, "shard003");
```

### 5.3 Topology khuyến nghị

```
                          ┌─────────────┐
                          │   mongos    │
                          │  (Router)   │
                          └──────┬──────┘
                                 │
              ┌──────────────────┼──────────────────┐
              │                  │                  │
       ┌──────┴──────┐   ┌──────┴──────┐   ┌──────┴──────┐
       │   Shard 1   │   │   Shard 2   │   │   Shard 3   │
       │ visa, vnpay │   │ mastercard  │   │ napas, banks│
       │             │   │             │   │             │
       │  Primary    │   │  Primary    │   │  Primary    │
       │  Secondary  │   │  Secondary  │   │  Secondary  │
       │  Secondary  │   │  Secondary  │   │  Secondary  │
       └─────────────┘   └─────────────┘   └─────────────┘
       
       Config Server Replica Set (3 nodes) — quản lý metadata
```

**Sizing cho mỗi shard:**
- RAM: 32 GB (đủ cho working set + indexes)
- Storage: 500 GB NVMe SSD (WiredTiger nén ~3:1)
- CPU: 8 vCPU
- Network: 10 Gbps (inter-shard communication)

---

## 6. Aggregation Pipeline Examples

### 6.1 Daily Reconciliation Report — Báo cáo đối soát hàng ngày

```javascript
db.webhook_events.aggregate([
    // Stage 1: Lọc events trong ngày
    { $match: {
        received_at: {
            $gte: ISODate("2026-06-23T00:00:00Z"),
            $lt: ISODate("2026-06-24T00:00:00Z")
        },
        event_type: { $in: ["payment.completed", "payment.failed"] }
    }},
    
    // Stage 2: Group theo provider và status
    { $group: {
        _id: {
            provider: "$provider",
            event_type: "$event_type",
            hour: { $hour: "$received_at" }
        },
        count: { $sum: 1 },
        total_amount: { $sum: "$extracted.amount" },
        avg_processing_time_ms: { $avg: "$processing.processing_duration_ms" },
        min_amount: { $min: "$extracted.amount" },
        max_amount: { $max: "$extracted.amount" }
    }},
    
    // Stage 3: Reshape output
    { $project: {
        _id: 0,
        provider: "$_id.provider",
        event_type: "$_id.event_type",
        hour: "$_id.hour",
        count: 1,
        total_amount: 1,
        avg_processing_time_ms: { $round: ["$avg_processing_time_ms", 2] },
        min_amount: 1,
        max_amount: 1
    }},
    
    // Stage 4: Sắp xếp
    { $sort: { provider: 1, hour: 1, event_type: 1 } }
]);
```

### 6.2 Failed Events Analysis — Phân tích events thất bại

```javascript
db.webhook_events.aggregate([
    // Chỉ lấy failed events trong 7 ngày
    { $match: {
        "processing.status": "failed",
        received_at: { $gte: ISODate("2026-06-16T00:00:00Z") }
    }},
    
    // Phân tích lỗi theo provider và error type
    { $group: {
        _id: {
            provider: "$provider",
            event_type: "$event_type",
            error_code: "$extracted.response_code"
        },
        failure_count: { $sum: 1 },
        sample_event_ids: { $push: { $cond: [
            { $lte: [{ $size: { $ifNull: ["$sample_event_ids", []] } }, 5] },
            "$event_id",
            "$$REMOVE"
        ]}},
        first_failure: { $min: "$received_at" },
        last_failure: { $max: "$received_at" }
    }},
    
    // Tính failure rate
    { $sort: { failure_count: -1 } },
    
    { $limit: 20 }
]);
```

### 6.3 Provider Health Dashboard — Theo dõi sức khỏe từng provider

```javascript
db.webhook_events.aggregate([
    // Events trong 1 giờ gần nhất
    { $match: {
        received_at: { $gte: new Date(Date.now() - 3600000) }
    }},
    
    // Faceted analysis — nhiều metrics cùng lúc
    { $facet: {
        // Throughput theo provider
        "throughput_by_provider": [
            { $group: {
                _id: "$provider",
                events_per_hour: { $sum: 1 },
                success_count: { $sum: { $cond: [
                    { $eq: ["$processing.status", "processed"] }, 1, 0
                ]}},
                failure_count: { $sum: { $cond: [
                    { $eq: ["$processing.status", "failed"] }, 1, 0
                ]}}
            }},
            { $addFields: {
                success_rate: {
                    $multiply: [
                        { $divide: ["$success_count", { $max: ["$events_per_hour", 1] }] },
                        100
                    ]
                }
            }},
            { $sort: { events_per_hour: -1 } }
        ],
        
        // Latency percentiles
        "latency_analysis": [
            { $group: {
                _id: "$provider",
                processing_times: { $push: "$processing.processing_duration_ms" }
            }},
            { $project: {
                provider: "$_id",
                p50: { $arrayElemAt: [
                    "$processing_times",
                    { $floor: { $multiply: [{ $size: "$processing_times" }, 0.5] } }
                ]},
                p95: { $arrayElemAt: [
                    "$processing_times",
                    { $floor: { $multiply: [{ $size: "$processing_times" }, 0.95] } }
                ]},
                p99: { $arrayElemAt: [
                    "$processing_times",
                    { $floor: { $multiply: [{ $size: "$processing_times" }, 0.99] } }
                ]}
            }}
        ],
        
        // Event type distribution
        "event_distribution": [
            { $group: {
                _id: { provider: "$provider", event_type: "$event_type" },
                count: { $sum: 1 }
            }},
            { $sort: { count: -1 } }
        ]
    }}
]);
```

### 6.4 Merchant Transaction Summary — Tổng hợp giao dịch theo merchant

```javascript
db.webhook_events.aggregate([
    { $match: {
        event_type: "payment.completed",
        received_at: {
            $gte: ISODate("2026-06-01T00:00:00Z"),
            $lt: ISODate("2026-07-01T00:00:00Z")
        }
    }},
    
    { $group: {
        _id: "$extracted.merchant_id",
        total_transactions: { $sum: 1 },
        total_volume: { $sum: "$extracted.amount" },
        avg_transaction_value: { $avg: "$extracted.amount" },
        providers_used: { $addToSet: "$provider" },
        daily_breakdown: {
            $push: {
                date: { $dateToString: { format: "%Y-%m-%d", date: "$received_at" } },
                amount: "$extracted.amount"
            }
        }
    }},
    
    { $addFields: {
        provider_count: { $size: "$providers_used" },
        avg_daily_volume: {
            $divide: ["$total_volume", 30]    // Ước tính trung bình ngày
        }
    }},
    
    { $sort: { total_volume: -1 } },
    { $limit: 50 }
]);
```

---

## 7. Data Lifecycle Management

### 7.1 Retention Policy

| Collection | Hot (SSD) | Warm (HDD) | Archive (S3) | Total Retention |
|-----------|-----------|------------|---------------|-----------------|
| `webhook_events` | 30 ngày | 60 ngày | 2 năm | 2 năm + 90 ngày |
| `payment_notifications` | 30 ngày | 60 ngày | 1 năm | 1 năm + 90 ngày |
| `event_processing_deadletter` | 365 ngày | — | 5 năm | 5 năm + 365 ngày |

### 7.2 Archival Strategy

```javascript
// Cron job chạy hàng ngày — archive events > 90 ngày sang S3 trước khi TTL xóa
// Sử dụng MongoDB Connector for Spark hoặc custom script

// Option 1: mongoexport cho batch archival
// mongoexport --db vietpay_webhooks --collection webhook_events \
//   --query '{"received_at": {"$lt": ISODate("2026-03-25T00:00:00Z")}}' \
//   --out /archive/webhook_events_pre_20260325.json

// Option 2: Change Streams cho real-time archival
const pipeline = [
    { $match: { "operationType": "delete" } }
];

const changeStream = db.webhook_events.watch(pipeline);
changeStream.on("change", (change) => {
    // Archive to S3 before TTL deletion
    archiveToS3(change.fullDocumentBeforeChange);
});
```

---

## 8. Monitoring và Operational Considerations

### 8.1 Key Metrics to Monitor

| Metric | Threshold Warning | Threshold Critical | Ý nghĩa |
|--------|-------------------|-------------------|----------|
| Oplog window | < 24h | < 6h | Thời gian có thể recover secondary |
| Replication lag | > 1s | > 10s | Secondary bị trễ so với primary |
| Cache hit ratio | < 95% | < 90% | WiredTiger cache không đủ |
| Connections in use | > 80% max | > 95% max | Connection pool cạn kiệt |
| Document count growth/day | > 150% baseline | > 200% baseline | Anomaly — possible duplicate ingestion |
| TTL deletion rate | Backlog > 1M | Backlog > 10M | TTL thread không kịp xóa |

### 8.2 Backup Strategy

```
┌─────────────────────────────────────────────────────────┐
│                    Backup Schedule                       │
├──────────────────┬──────────────────────────────────────┤
│ Continuous       │ Oplog tailing → S3 (point-in-time)  │
│ Every 6 hours    │ mongodump → compressed → S3          │
│ Daily            │ Snapshot (EBS/disk level)             │
│ Weekly           │ Full backup + verification restore    │
└──────────────────┴──────────────────────────────────────┘
```

### 8.3 Security Considerations (PCI-DSS)

- **Encryption at rest**: WiredTiger encrypted storage engine (AES-256)
- **Encryption in transit**: TLS 1.3 cho tất cả connections
- **Field-level encryption**: Client-Side Field Level Encryption (CSFLE) cho sensitive fields
- **Access control**: RBAC với principle of least privilege
- **Audit logging**: Enable MongoDB audit log cho compliance
- **Network isolation**: MongoDB cluster trong private subnet, chỉ accessible qua VPN/peering

```javascript
// Ví dụ RBAC roles
db.createRole({
    role: "webhookWriter",
    privileges: [
        { resource: { db: "vietpay_webhooks", collection: "webhook_events" },
          actions: ["insert", "find"] }       // Chỉ insert và read, KHÔNG update/delete
    ],
    roles: []
});

db.createRole({
    role: "webhookAnalyst",
    privileges: [
        { resource: { db: "vietpay_webhooks", collection: "webhook_events" },
          actions: ["find", "aggregate"] }     // Chỉ read và aggregate
    ],
    roles: []
});
```

---

> **Tài liệu tham khảo:**
> - [MongoDB Data Modeling](https://www.mongodb.com/docs/manual/core/data-modeling-introduction/)
> - [MongoDB Sharding](https://www.mongodb.com/docs/manual/sharding/)
> - [PCI-DSS v4.0 Requirements](https://www.pcisecuritystandards.org/)
> - VietPay Internal Architecture Documents


---

!!! info "Nguồn gốc"
    `vietpay/mongodb/webhook-events-model.md`
