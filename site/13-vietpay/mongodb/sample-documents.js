// ============================================================================
// VietPay — MongoDB Sample Documents & Operations
// ============================================================================
// File: mongodb/sample-documents.js
// Purpose: Realistic sample documents, index creation, aggregation pipelines
// Database: vietpay_webhooks
// ============================================================================

// ─────────────────────────────────────────────────────────────────────────────
// 0. DATABASE & COLLECTION SETUP
// ─────────────────────────────────────────────────────────────────────────────

use("vietpay_webhooks");

// Tạo collection với JSON Schema validation
db.createCollection("webhook_events", {
    validator: {
        $jsonSchema: {
            bsonType: "object",
            required: ["event_id", "provider", "event_type", "raw_payload", "received_at"],
            properties: {
                event_id: {
                    bsonType: "string",
                    description: "Unique event identifier for idempotency"
                },
                provider: {
                    bsonType: "string",
                    enum: [
                        "visa", "mastercard", "napas", "vnpay",
                        "bank_vcb", "bank_tcb", "bank_bidv", "bank_mb",
                        "momo", "zalopay"
                    ],
                    description: "Payment provider name"
                },
                event_type: {
                    bsonType: "string",
                    description: "Event type in dot notation (e.g., payment.completed)"
                },
                raw_payload: {
                    bsonType: "object",
                    description: "Original webhook payload — stored as-is"
                },
                received_at: {
                    bsonType: "date",
                    description: "Timestamp when VietPay received the webhook"
                }
            }
        }
    },
    validationLevel: "moderate",
    validationAction: "warn"
});

db.createCollection("payment_notifications");
db.createCollection("event_processing_deadletter");

// ─────────────────────────────────────────────────────────────────────────────
// 1. SAMPLE DOCUMENTS — Webhook Events với các schema khác nhau
// ─────────────────────────────────────────────────────────────────────────────

// ─── Event Type 1: payment.completed (Visa) ─────────────────────────────────
// Schema đặc trưng Visa: có authorizationCode, cardAcceptorData, pointOfServiceData
db.webhook_events.insertOne({
    event_id: "evt_visa_20260623_143022_a1b2c3",
    provider: "visa",
    provider_event_id: "VSA_EVT_98765432",
    event_type: "payment.completed",
    event_category: "payment",
    internal_transaction_id: "txn_vp_20260623_001",

    // Visa-specific raw payload — schema riêng của Visa
    raw_payload: {
        transactionIdentifier: "VISA_TXN_20260623_001",
        authorizationCode: "AUTH_V_456789",
        responseCode: "00",                    // 00 = Approved
        approvalCode: "AP7891",
        transactionAmount: {
            amount: "1500000.00",
            currency: "704"                    // ISO 4217: 704 = VND
        },
        surchargeAmount: {
            amount: "15000.00",
            currency: "704"
        },
        cardAcceptorData: {
            name: "COFFEE HOUSE DISTRICT 1",
            streetAddress: "123 Nguyen Hue",
            city: "Ho Chi Minh City",
            stateProvince: "SG",
            postalCode: "700000",
            countryCode: "VN",
            merchantCategoryCode: "5814",      // Fast Food Restaurants
            terminalId: "TRM_CH_001",
            merchantId: "MCH_COFFEE_001"
        },
        pointOfServiceData: {
            entryMode: "contactless",
            terminalType: "POS",
            cardPresent: true,
            cardholderPresent: true,
            terminalCapability: "chip_contactless"
        },
        cardData: {
            cardNumberMasked: "4532****1234",
            expiryDate: "12/28",               // Chỉ lưu tháng/năm, KHÔNG lưu full PAN
            cardScheme: "VISA",
            cardType: "CREDIT",
            issuingBank: "Vietcombank"
        },
        acquirerData: {
            acquirerBankCode: "970436",
            acquirerReferenceNumber: "ACQ_REF_001",
            settlementDate: "2026-06-24"
        },
        additionalData: {
            originalTransactionId: null,
            recurringPayment: false,
            ecommerceIndicator: null
        },
        timestamps: {
            transactionDateTime: "2026-06-23T14:30:20.000Z",
            transmissionDateTime: "2026-06-23T14:30:21.500Z"
        }
    },

    http_metadata: {
        method: "POST",
        path: "/webhooks/visa/payment",
        headers: {
            "content-type": "application/json",
            "x-visa-signature": "sha256=a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8",
            "x-request-id": "req_visa_20260623_001",
            "x-visa-transaction-id": "VSA_EVT_98765432",
            "user-agent": "VisaNet-Webhook/3.1"
        },
        source_ip: "198.51.100.42",
        received_at: ISODate("2026-06-23T14:30:22.456Z")
    },

    processing: {
        status: "processed",
        processed_at: ISODate("2026-06-23T14:30:22.789Z"),
        processing_duration_ms: 333,
        attempts: 1,
        last_error: null,
        processor_instance: "webhook-worker-03",
        correlation_id: "cor_20260623_001"
    },

    verification: {
        signature_valid: true,
        verified_at: ISODate("2026-06-23T14:30:22.460Z"),
        algorithm: "HMAC-SHA256"
    },

    extracted: {
        amount: NumberDecimal("1500000"),
        currency: "VND",
        merchant_id: "MCH_COFFEE_001",
        card_last_four: "1234",
        response_code: "00",
        mcc: "5814"
    },

    received_at: ISODate("2026-06-23T14:30:22.456Z"),
    provider_timestamp: ISODate("2026-06-23T14:30:20.000Z"),
    created_at: ISODate("2026-06-23T14:30:22.456Z"),
    updated_at: ISODate("2026-06-23T14:30:22.789Z"),
    expires_at: ISODate("2026-09-21T14:30:22.456Z")
});


// ─── Event Type 2: payment.failed (Napas — schema hoàn toàn khác Visa) ─────
// Schema đặc trưng Napas: có napas_trace, ben_id, bank_code, response_code riêng
db.webhook_events.insertOne({
    event_id: "evt_napas_20260623_143155_x7y8z9",
    provider: "napas",
    provider_event_id: "NAP_TRC_20260623_00042",
    event_type: "payment.failed",
    event_category: "payment",
    internal_transaction_id: "txn_vp_20260623_002",

    // Napas-specific raw payload — format theo chuẩn Napas Việt Nam
    raw_payload: {
        napas_trace: "NAP20260623000042",
        transaction_type: "PURCHASE",
        ben_id: "970436",                      // Beneficiary bank ID (Vietcombank)
        acq_id: "970415",                      // Acquirer bank ID (Vietinbank)
        bank_code: "VCB",
        channel: "POS",
        amount: 25000000,                      // VND — số nguyên, không có decimal
        fee_amount: 0,
        currency_code: "VND",                  // Napas dùng string "VND", không phải ISO numeric
        card_number: "9704********5678",       // Masking theo chuẩn Napas
        card_type: "DEBIT",
        response_code: "51",                   // 51 = Insufficient funds
        response_message: "Số dư không đủ",
        approval_code: null,                   // null vì giao dịch thất bại
        merchant_info: {
            merchant_id: "NAP_MCH_ELEC_002",
            merchant_name: "DIEN MAY XANH Q7",
            terminal_id: "NAP_TRM_002",
            mcc: "5732"                        // Electronics Stores
        },
        issuer_response: {
            issuer_code: "970436",
            issuer_name: "Vietcombank",
            decline_reason: "INSUFFICIENT_BALANCE",
            available_balance_indicator: false   // Không trả về balance cụ thể (security)
        },
        transaction_time: "20260623143150",     // Format: YYYYMMDDHHmmss (Napas legacy format)
        settlement_date: "20260624",
        additional_data: {
            original_napas_trace: null,
            pos_condition_code: "00",
            service_code: "201"
        }
    },

    http_metadata: {
        method: "POST",
        path: "/webhooks/napas/payment",
        headers: {
            "content-type": "application/json; charset=utf-8",
            "x-napas-signature": "RSA-SHA256:base64encodedSignature==",
            "x-napas-key-id": "napas-prod-key-2026",
            "x-correlation-id": "NAP_COR_20260623_042"
        },
        source_ip: "10.20.30.40",             // Napas qua leased line / VPN
        received_at: ISODate("2026-06-23T14:31:55.123Z")
    },

    processing: {
        status: "processed",
        processed_at: ISODate("2026-06-23T14:31:55.567Z"),
        processing_duration_ms: 444,
        attempts: 1,
        last_error: null,
        processor_instance: "webhook-worker-01",
        correlation_id: "cor_20260623_002"
    },

    verification: {
        signature_valid: true,
        verified_at: ISODate("2026-06-23T14:31:55.200Z"),
        algorithm: "RSA-SHA256"
    },

    extracted: {
        amount: NumberDecimal("25000000"),
        currency: "VND",
        merchant_id: "NAP_MCH_ELEC_002",
        card_last_four: "5678",
        response_code: "51",
        mcc: "5732"
    },

    received_at: ISODate("2026-06-23T14:31:55.123Z"),
    provider_timestamp: ISODate("2026-06-23T14:31:50.000Z"),
    created_at: ISODate("2026-06-23T14:31:55.123Z"),
    updated_at: ISODate("2026-06-23T14:31:55.567Z"),
    expires_at: ISODate("2026-09-21T14:31:55.123Z")
});


// ─── Event Type 3: refund.initiated (VNPay — schema theo kiểu VNPay) ───────
// Schema đặc trưng VNPay: có vnp_ prefix fields, secure hash verification
db.webhook_events.insertOne({
    event_id: "evt_vnpay_20260623_150000_r3f4n5",
    provider: "vnpay",
    provider_event_id: "VNP_REF_20260623_001",
    event_type: "refund.initiated",
    event_category: "refund",
    internal_transaction_id: "txn_vp_20260623_003",

    // VNPay-specific raw payload — format riêng VNPay
    raw_payload: {
        vnp_Version: "2.1.0",
        vnp_Command: "refund",
        vnp_TmnCode: "VIETPAY1",
        vnp_TxnRef: "VP_ORD_20260620_789",          // Original order reference
        vnp_Amount: 5000000 * 100,                    // VNPay multiply by 100
        vnp_OrderInfo: "Hoan tien don hang VP_ORD_20260620_789",
        vnp_TransactionNo: "VNP_TXN_14023456",
        vnp_ResponseCode: "00",
        vnp_TransactionType: "02",                    // 02 = Full refund
        vnp_TransactionStatus: "00",                  // 00 = Success
        vnp_BankCode: "TCB",                          // Techcombank
        vnp_BankTranNo: "TCB_BT_20260623_001",
        vnp_PayDate: "20260623150000",                // YYYYMMDDHHmmss
        vnp_CreateDate: "20260623145500",
        vnp_IpAddr: "113.160.92.100",
        vnp_Locale: "vn",
        vnp_CurrCode: "VND",
        vnp_CardType: "ATM",
        vnp_SecureHash: "SHA512:a1b2c3d4e5f6789abcdef0123456789abcdef",
        vnp_SecureHashType: "SHA512",
        // VNPay-specific refund fields
        vnp_RefundCategory: "CUSTOMER_REQUEST",
        vnp_RefundReason: "Khách hàng yêu cầu hoàn tiền - sản phẩm lỗi",
        vnp_OriginalTxnRef: "VNP_TXN_14020000",
        vnp_OriginalAmount: 5000000 * 100,
        vnp_OriginalTransDate: "20260620103000"
    },

    http_metadata: {
        method: "POST",
        path: "/webhooks/vnpay/refund",
        headers: {
            "content-type": "application/x-www-form-urlencoded",  // VNPay gửi form-encoded
            "x-vnpay-checksum": "SHA512:a1b2c3d4e5f6789...",
            "user-agent": "VNPay-IPN/2.1"
        },
        source_ip: "113.160.92.50",
        received_at: ISODate("2026-06-23T15:00:00.789Z")
    },

    processing: {
        status: "processed",
        processed_at: ISODate("2026-06-23T15:00:01.234Z"),
        processing_duration_ms: 445,
        attempts: 1,
        last_error: null,
        processor_instance: "webhook-worker-02",
        correlation_id: "cor_20260623_003"
    },

    verification: {
        signature_valid: true,
        verified_at: ISODate("2026-06-23T15:00:00.850Z"),
        algorithm: "SHA512-HMAC"
    },

    extracted: {
        amount: NumberDecimal("5000000"),       // Đã chia 100 từ vnp_Amount
        currency: "VND",
        merchant_id: "VIETPAY1",
        card_last_four: null,                   // VNPay ATM không trả card info
        response_code: "00",
        mcc: null                               // VNPay không trả MCC
    },

    received_at: ISODate("2026-06-23T15:00:00.789Z"),
    provider_timestamp: ISODate("2026-06-23T15:00:00.000Z"),
    created_at: ISODate("2026-06-23T15:00:00.789Z"),
    updated_at: ISODate("2026-06-23T15:00:01.234Z"),
    expires_at: ISODate("2026-09-21T15:00:00.789Z")
});


// ─── Event Type 4: chargeback.received (Mastercard — ISO 8583 mapped) ───────
// Schema đặc trưng Mastercard: DE (Data Element) fields từ ISO 8583 standard
db.webhook_events.insertOne({
    event_id: "evt_mc_20260623_160000_c8b9k0",
    provider: "mastercard",
    provider_event_id: "MC_CB_ARN_74125896301234567890",
    event_type: "chargeback.received",
    event_category: "chargeback",
    internal_transaction_id: "txn_vp_20260618_055",

    // Mastercard-specific raw payload — ISO 8583 Data Elements mapped to JSON
    raw_payload: {
        messageType: "1442",                    // Chargeback request
        // ISO 8583 Data Elements
        DE2_PAN: "5425****9876",                // Primary Account Number (masked)
        DE3_ProcessingCode: "000000",           // Purchase
        DE4_TransactionAmount: "75000000",      // Amount in minor currency units
        DE6_CardholderBillingAmount: "3000.00", // USD equivalent
        DE7_TransmissionDateTime: "0623160000", // MMDDHHmmss
        DE12_LocalTransactionTime: "230000",
        DE13_LocalTransactionDate: "0623",
        DE22_POSEntryMode: "051",               // Chip
        DE25_POSConditionCode: "00",
        DE26_MerchantCategoryCode: "5411",      // Grocery Stores
        DE32_AcquiringInstitution: "970436",
        DE37_RetrievalReferenceNumber: "RRN626301234",
        DE38_AuthorizationCode: "AUTH_MC_789",
        DE41_CardAcceptorTerminalId: "MC_TRM_003",
        DE42_CardAcceptorId: "MCH_GROCERY_003",
        DE43_CardAcceptorNameLocation: {
            name: "BACH HOA XANH TAN BINH",
            city: "HO CHI MINH",
            state: "SG",
            country: "VN"
        },
        DE49_CurrencyCode: "704",               // VND
        DE51_CardholderBillingCurrency: "840",   // USD

        // Mastercard-specific chargeback fields
        chargebackData: {
            ARN: "74125896301234567890",         // Acquirer Reference Number
            reasonCode: "4837",                  // No Cardholder Authorization
            reasonDescription: "No Cardholder Authorization - Giao dịch không được chủ thẻ ủy quyền",
            chargebackAmount: 75000000,
            chargebackCurrency: "VND",
            originalTransactionDate: "2026-06-18",
            originalTransactionAmount: 75000000,
            chargebackType: "FIRST_CHARGEBACK",
            representmentDeadline: "2026-07-08",  // 15 ngày để representment
            documentationRequired: true,
            stage: 1,                             // First chargeback (có thể lên stage 2 = pre-arbitration)
            isPartial: false
        },

        // Network-specific metadata
        networkData: {
            networkReferenceId: "MC_NET_REF_001",
            authorizationCharacteristicsIndicator: "A",
            posTerminalCapability: "5",
            cardSequenceNumber: "001",
            iccSystemRelatedData: "9F2608A1B2C3D4E5F6..."
        }
    },

    http_metadata: {
        method: "POST",
        path: "/webhooks/mastercard/chargeback",
        headers: {
            "content-type": "application/json",
            "x-mc-signature": "RSA-SHA512:longBase64EncodedSignatureString==",
            "x-mc-key-id": "mc-prod-key-2026-q2",
            "x-mc-idempotency-key": "MC_IDEMP_20260623_CB_001",
            "x-mc-correlation-id": "MC_COR_20260623_001",
            "user-agent": "Mastercard-Connect/5.2"
        },
        source_ip: "203.0.113.100",
        received_at: ISODate("2026-06-23T16:00:00.321Z")
    },

    processing: {
        status: "processed",
        processed_at: ISODate("2026-06-23T16:00:01.100Z"),
        processing_duration_ms: 779,
        attempts: 1,
        last_error: null,
        processor_instance: "webhook-worker-01",
        correlation_id: "cor_20260623_004",
        // Chargeback cần xử lý đặc biệt — flag cho dispute team
        flags: ["requires_dispute_review", "high_priority", "deadline_2026-07-08"]
    },

    verification: {
        signature_valid: true,
        verified_at: ISODate("2026-06-23T16:00:00.400Z"),
        algorithm: "RSA-SHA512"
    },

    extracted: {
        amount: NumberDecimal("75000000"),
        currency: "VND",
        merchant_id: "MCH_GROCERY_003",
        card_last_four: "9876",
        response_code: "4837",                  // Chargeback reason code
        mcc: "5411"
    },

    // Chargeback-specific fields (không có trong payment events)
    chargeback_metadata: {
        arn: "74125896301234567890",
        reason_code: "4837",
        reason_category: "fraud",
        original_transaction_date: ISODate("2026-06-18T00:00:00Z"),
        response_deadline: ISODate("2026-07-08T00:00:00Z"),
        dispute_status: "open",
        assigned_to: null
    },

    received_at: ISODate("2026-06-23T16:00:00.321Z"),
    provider_timestamp: ISODate("2026-06-23T16:00:00.000Z"),
    created_at: ISODate("2026-06-23T16:00:00.321Z"),
    updated_at: ISODate("2026-06-23T16:00:01.100Z"),
    expires_at: ISODate("2026-09-21T16:00:00.321Z")
});


// ─────────────────────────────────────────────────────────────────────────────
// 2. INDEX CREATION — Tạo indexes cho production
// ─────────────────────────────────────────────────────────────────────────────

// ─── webhook_events indexes ───

// Unique index trên event_id — idempotency key để tránh duplicate processing
db.webhook_events.createIndex(
    { "event_id": 1 },
    { unique: true, name: "idx_event_id_unique",
      comment: "Idempotency: reject duplicate webhook events from providers" }
);

// Compound index cho primary query pattern: tìm events theo provider + time range
// Hỗ trợ queries: "Tất cả Visa events hôm nay", "Napas events 1 giờ qua"
db.webhook_events.createIndex(
    { "provider": 1, "received_at": -1 },
    { name: "idx_provider_received_at",
      comment: "Primary query pattern: filter by provider + time range, descending for recent-first" }
);

// Internal transaction lookup — link webhook events với PostgreSQL transactions
db.webhook_events.createIndex(
    { "internal_transaction_id": 1, "event_type": 1 },
    { name: "idx_internal_txn_event_type",
      comment: "Join key: find all webhook events for a given PostgreSQL transaction" }
);

// Event processing status + time — cho monitoring dashboard
db.webhook_events.createIndex(
    { "event_type": 1, "processing.status": 1, "received_at": -1 },
    { name: "idx_event_type_status_time",
      comment: "Dashboard: show event counts by type and status over time" }
);

// Partial index cho failed events — chỉ index ~2% documents
// Tiết kiệm 98% disk space so với full index
db.webhook_events.createIndex(
    { "processing.status": 1, "received_at": -1 },
    {
        name: "idx_failed_events_partial",
        partialFilterExpression: {
            "processing.status": { $in: ["failed", "retrying"] }
        },
        comment: "Operational: quickly find events needing attention. Partial = small index size."
    }
);

// Provider event ID — để đối soát ngược với provider
db.webhook_events.createIndex(
    { "provider_event_id": 1 },
    { name: "idx_provider_event_id", sparse: true,
      comment: "Reconciliation: lookup by provider's own event ID" }
);

// Merchant lookup — hỗ trợ merchant dashboard queries
db.webhook_events.createIndex(
    { "extracted.merchant_id": 1, "received_at": -1 },
    { name: "idx_merchant_time",
      comment: "Merchant dashboard: show all events for a specific merchant" }
);

// Amount range + provider — reconciliation, fraud detection
db.webhook_events.createIndex(
    { "extracted.amount": 1, "provider": 1 },
    { name: "idx_amount_provider",
      comment: "Reconciliation: find transactions by amount range per provider" }
);

// TTL index — tự động xóa documents khi expires_at đến hạn
// MongoDB background thread kiểm tra mỗi 60 giây
db.webhook_events.createIndex(
    { "expires_at": 1 },
    { expireAfterSeconds: 0, name: "idx_ttl_expires_at",
      comment: "Auto-delete: documents removed when expires_at timestamp is reached (90 days)" }
);

// ─── payment_notifications indexes ───

db.payment_notifications.createIndex(
    { "notification_id": 1 },
    { unique: true, name: "idx_notification_id_unique" }
);

db.payment_notifications.createIndex(
    { "source_event_id": 1 },
    { name: "idx_source_event",
      comment: "Link notification back to the originating webhook event" }
);

db.payment_notifications.createIndex(
    { "target.merchant_id": 1, "delivery.status": 1 },
    { name: "idx_merchant_delivery_status",
      comment: "Merchant support: find pending/failed notifications for a merchant" }
);

// Retry queue index — worker tìm notifications cần retry
db.payment_notifications.createIndex(
    { "delivery.status": 1, "delivery.next_retry_at": 1 },
    {
        name: "idx_retry_queue",
        partialFilterExpression: {
            "delivery.status": { $in: ["failed", "pending"] },
            "delivery.next_retry_at": { $exists: true }
        },
        comment: "Worker queue: find notifications ready for retry, ordered by next_retry_at"
    }
);

db.payment_notifications.createIndex(
    { "expires_at": 1 },
    { expireAfterSeconds: 0, name: "idx_ttl_notifications" }
);

// ─── event_processing_deadletter indexes ───

db.event_processing_deadletter.createIndex(
    { "original_event_id": 1 },
    { unique: true, name: "idx_deadletter_event_id" }
);

db.event_processing_deadletter.createIndex(
    { "resolution.status": 1, "moved_to_deadletter_at": -1 },
    { name: "idx_deadletter_unresolved",
      comment: "Operations: find unresolved dead letter events, newest first" }
);

db.event_processing_deadletter.createIndex(
    { "expires_at": 1 },
    { expireAfterSeconds: 0, name: "idx_ttl_deadletter" }
);


// ─────────────────────────────────────────────────────────────────────────────
// 3. AGGREGATION PIPELINE EXAMPLES
// ─────────────────────────────────────────────────────────────────────────────

// ─── Pipeline 1: Daily Reconciliation Report ────────────────────────────────
// Báo cáo đối soát hàng ngày — group theo provider, event_type, giờ
// Dùng cho: Finance team đối soát số liệu với providers mỗi sáng

print("=== Pipeline 1: Daily Reconciliation Report ===");

db.webhook_events.aggregate([
    // Stage 1: Lọc events trong ngày 23/06/2026
    { $match: {
        received_at: {
            $gte: ISODate("2026-06-23T00:00:00Z"),
            $lt: ISODate("2026-06-24T00:00:00Z")
        },
        "processing.status": "processed",
        event_type: { $in: ["payment.completed", "payment.failed", "refund.initiated"] }
    }},

    // Stage 2: Group theo provider + event_type + hour
    { $group: {
        _id: {
            provider: "$provider",
            event_type: "$event_type",
            hour: { $hour: "$received_at" }
        },
        transaction_count: { $sum: 1 },
        total_amount: { $sum: "$extracted.amount" },
        avg_amount: { $avg: "$extracted.amount" },
        min_amount: { $min: "$extracted.amount" },
        max_amount: { $max: "$extracted.amount" },
        avg_processing_ms: { $avg: "$processing.processing_duration_ms" },
        unique_merchants: { $addToSet: "$extracted.merchant_id" }
    }},

    // Stage 3: Enrich với merchant count
    { $addFields: {
        merchant_count: { $size: "$unique_merchants" },
        avg_processing_ms: { $round: ["$avg_processing_ms", 2] }
    }},

    // Stage 4: Reshape output cho readability
    { $project: {
        _id: 0,
        provider: "$_id.provider",
        event_type: "$_id.event_type",
        hour: "$_id.hour",
        transaction_count: 1,
        total_amount: 1,
        avg_amount: { $round: ["$avg_amount", 0] },
        min_amount: 1,
        max_amount: 1,
        merchant_count: 1,
        avg_processing_ms: 1
    }},

    // Stage 5: Sort theo provider → hour → event_type
    { $sort: { provider: 1, hour: 1, event_type: 1 } }
]);


// ─── Pipeline 2: Provider Health Monitoring ─────────────────────────────────
// Theo dõi sức khỏe từng payment provider — success rate, latency, error distribution
// Dùng cho: Operations dashboard, real-time monitoring

print("=== Pipeline 2: Provider Health Monitoring (Last 1 Hour) ===");

db.webhook_events.aggregate([
    // Chỉ events trong 1 giờ qua
    { $match: {
        received_at: { $gte: new Date(Date.now() - 3600 * 1000) }
    }},

    // Multi-faceted analysis
    { $facet: {
        // ─── Facet A: Throughput & Success Rate per Provider ───
        "provider_health": [
            { $group: {
                _id: "$provider",
                total_events: { $sum: 1 },
                processed: {
                    $sum: { $cond: [{ $eq: ["$processing.status", "processed"] }, 1, 0] }
                },
                failed: {
                    $sum: { $cond: [{ $eq: ["$processing.status", "failed"] }, 1, 0] }
                },
                retrying: {
                    $sum: { $cond: [{ $eq: ["$processing.status", "retrying"] }, 1, 0] }
                },
                total_volume: { $sum: "$extracted.amount" }
            }},
            { $addFields: {
                success_rate_pct: {
                    $round: [
                        { $multiply: [
                            { $divide: ["$processed", { $max: ["$total_events", 1] }] },
                            100
                        ] },
                        2
                    ]
                }
            }},
            { $sort: { total_events: -1 } }
        ],

        // ─── Facet B: Event Type Distribution ───
        "event_distribution": [
            { $group: {
                _id: { provider: "$provider", event_type: "$event_type" },
                count: { $sum: 1 }
            }},
            { $sort: { "_id.provider": 1, count: -1 } }
        ],

        // ─── Facet C: Processing Latency Stats ───
        "latency_stats": [
            { $match: { "processing.processing_duration_ms": { $exists: true } } },
            { $group: {
                _id: "$provider",
                avg_ms: { $avg: "$processing.processing_duration_ms" },
                max_ms: { $max: "$processing.processing_duration_ms" },
                min_ms: { $min: "$processing.processing_duration_ms" }
            }},
            { $addFields: {
                avg_ms: { $round: ["$avg_ms", 1] }
            }}
        ],

        // ─── Facet D: Recent Errors ───
        "recent_errors": [
            { $match: { "processing.status": "failed" } },
            { $sort: { received_at: -1 } },
            { $limit: 10 },
            { $project: {
                event_id: 1,
                provider: 1,
                event_type: 1,
                "processing.last_error": 1,
                received_at: 1
            }}
        ]
    }}
]);


// ─── Pipeline 3: Chargeback Analysis ────────────────────────────────────────
// Phân tích chargebacks — quan trọng vì ảnh hưởng trực tiếp đến revenue
// Dùng cho: Risk team, compliance reporting

print("=== Pipeline 3: Chargeback Analysis (Last 30 Days) ===");

db.webhook_events.aggregate([
    { $match: {
        event_type: "chargeback.received",
        received_at: { $gte: new Date(Date.now() - 30 * 24 * 3600 * 1000) }
    }},

    { $group: {
        _id: {
            provider: "$provider",
            reason_code: "$chargeback_metadata.reason_code",
            reason_category: "$chargeback_metadata.reason_category"
        },
        chargeback_count: { $sum: 1 },
        total_chargeback_amount: { $sum: "$extracted.amount" },
        avg_chargeback_amount: { $avg: "$extracted.amount" },

        // Thống kê deadline — bao nhiêu chargeback cần respond urgent
        past_deadline: {
            $sum: { $cond: [
                { $lt: ["$chargeback_metadata.response_deadline", new Date()] },
                1, 0
            ]}
        },
        upcoming_deadline_7days: {
            $sum: { $cond: [
                { $and: [
                    { $gte: ["$chargeback_metadata.response_deadline", new Date()] },
                    { $lte: ["$chargeback_metadata.response_deadline",
                             new Date(Date.now() + 7 * 24 * 3600 * 1000)] }
                ]},
                1, 0
            ]}
        },

        // Merchants bị ảnh hưởng
        affected_merchants: { $addToSet: "$extracted.merchant_id" }
    }},

    { $addFields: {
        affected_merchant_count: { $size: "$affected_merchants" }
    }},

    { $project: {
        _id: 0,
        provider: "$_id.provider",
        reason_code: "$_id.reason_code",
        reason_category: "$_id.reason_category",
        chargeback_count: 1,
        total_chargeback_amount: 1,
        avg_chargeback_amount: { $round: ["$avg_chargeback_amount", 0] },
        past_deadline: 1,
        upcoming_deadline_7days: 1,
        affected_merchant_count: 1
    }},

    { $sort: { chargeback_count: -1 } }
]);


// ─── Pipeline 4: Webhook Processing Performance Over Time ───────────────────
// Time-series view of processing performance — cho Grafana dashboard
// Dùng cho: SRE team, capacity planning

print("=== Pipeline 4: Processing Performance Time Series (Last 24 Hours) ===");

db.webhook_events.aggregate([
    { $match: {
        received_at: { $gte: new Date(Date.now() - 24 * 3600 * 1000) }
    }},

    // Bucket theo intervals 15 phút
    { $group: {
        _id: {
            provider: "$provider",
            // Truncate to 15-minute intervals
            time_bucket: {
                $dateTrunc: {
                    date: "$received_at",
                    unit: "minute",
                    binSize: 15
                }
            }
        },
        events_count: { $sum: 1 },
        avg_processing_ms: { $avg: "$processing.processing_duration_ms" },
        max_processing_ms: { $max: "$processing.processing_duration_ms" },
        error_count: {
            $sum: { $cond: [{ $eq: ["$processing.status", "failed"] }, 1, 0] }
        },
        total_volume_vnd: { $sum: "$extracted.amount" }
    }},

    { $addFields: {
        // Events per second trong 15-minute window
        events_per_second: { $round: [{ $divide: ["$events_count", 900] }, 2] },
        error_rate_pct: {
            $round: [
                { $multiply: [
                    { $divide: ["$error_count", { $max: ["$events_count", 1] }] },
                    100
                ] },
                2
            ]
        }
    }},

    { $sort: { "_id.time_bucket": 1, "_id.provider": 1 } },

    // Output format phù hợp cho Grafana
    { $project: {
        _id: 0,
        timestamp: "$_id.time_bucket",
        provider: "$_id.provider",
        events_count: 1,
        events_per_second: 1,
        avg_processing_ms: { $round: ["$avg_processing_ms", 1] },
        max_processing_ms: 1,
        error_count: 1,
        error_rate_pct: 1,
        total_volume_vnd: 1
    }}
]);


// ─── Pipeline 5: Merchant Risk Scoring ──────────────────────────────────────
// Tính risk score cho merchants dựa trên webhook patterns
// Dùng cho: Risk management, merchant onboarding decisions

print("=== Pipeline 5: Merchant Risk Scoring (Last 30 Days) ===");

db.webhook_events.aggregate([
    { $match: {
        received_at: { $gte: new Date(Date.now() - 30 * 24 * 3600 * 1000) },
        "extracted.merchant_id": { $exists: true, $ne: null }
    }},

    { $group: {
        _id: "$extracted.merchant_id",
        total_transactions: { $sum: 1 },
        total_volume: { $sum: "$extracted.amount" },

        // Count by event type
        completed_count: {
            $sum: { $cond: [{ $eq: ["$event_type", "payment.completed"] }, 1, 0] }
        },
        failed_count: {
            $sum: { $cond: [{ $eq: ["$event_type", "payment.failed"] }, 1, 0] }
        },
        refund_count: {
            $sum: { $cond: [{ $eq: ["$event_type", "refund.initiated"] }, 1, 0] }
        },
        chargeback_count: {
            $sum: { $cond: [{ $eq: ["$event_type", "chargeback.received"] }, 1, 0] }
        },

        // Amount stats
        avg_transaction_amount: { $avg: "$extracted.amount" },
        max_transaction_amount: { $max: "$extracted.amount" },

        // Providers used
        providers: { $addToSet: "$provider" },

        // Activity days
        first_event: { $min: "$received_at" },
        last_event: { $max: "$received_at" }
    }},

    // Compute risk indicators
    { $addFields: {
        failure_rate: {
            $round: [
                { $multiply: [
                    { $divide: ["$failed_count", { $max: ["$total_transactions", 1] }] },
                    100
                ] },
                2
            ]
        },
        refund_rate: {
            $round: [
                { $multiply: [
                    { $divide: ["$refund_count", { $max: ["$completed_count", 1] }] },
                    100
                ] },
                2
            ]
        },
        chargeback_rate: {
            $round: [
                { $multiply: [
                    { $divide: ["$chargeback_count", { $max: ["$completed_count", 1] }] },
                    100
                ] },
                2
            ]
        },
        // Risk score: weighted combination
        risk_score: {
            $round: [
                { $add: [
                    // Chargeback rate weight = 50 (most critical)
                    { $multiply: [
                        { $divide: ["$chargeback_count", { $max: ["$completed_count", 1] }] },
                        5000
                    ] },
                    // Refund rate weight = 30
                    { $multiply: [
                        { $divide: ["$refund_count", { $max: ["$completed_count", 1] }] },
                        3000
                    ] },
                    // Failure rate weight = 20
                    { $multiply: [
                        { $divide: ["$failed_count", { $max: ["$total_transactions", 1] }] },
                        2000
                    ] }
                ] },
                1
            ]
        }
    }},

    // Classify risk level
    { $addFields: {
        risk_level: {
            $switch: {
                branches: [
                    { case: { $gte: ["$risk_score", 50] }, then: "CRITICAL" },
                    { case: { $gte: ["$risk_score", 25] }, then: "HIGH" },
                    { case: { $gte: ["$risk_score", 10] }, then: "MEDIUM" },
                ],
                default: "LOW"
            }
        }
    }},

    { $sort: { risk_score: -1 } },
    { $limit: 50 },

    { $project: {
        _id: 0,
        merchant_id: "$_id",
        total_transactions: 1,
        total_volume: 1,
        completed_count: 1,
        failed_count: 1,
        refund_count: 1,
        chargeback_count: 1,
        failure_rate: 1,
        refund_rate: 1,
        chargeback_rate: 1,
        risk_score: 1,
        risk_level: 1,
        providers: 1,
        avg_transaction_amount: { $round: ["$avg_transaction_amount", 0] },
        max_transaction_amount: 1,
        active_days: {
            $round: [
                { $divide: [
                    { $subtract: ["$last_event", "$first_event"] },
                    86400000  // ms per day
                ] },
                0
            ]
        }
    }}
]);


// ─────────────────────────────────────────────────────────────────────────────
// 4. SAMPLE NOTIFICATION DOCUMENT
// ─────────────────────────────────────────────────────────────────────────────

db.payment_notifications.insertOne({
    notification_id: "notif_20260623_001",
    source_event_id: "evt_visa_20260623_143022_a1b2c3",
    internal_transaction_id: "txn_vp_20260623_001",

    target: {
        type: "merchant",
        merchant_id: "MCH_COFFEE_001",
        callback_url: "https://coffeehouse.vn/api/v2/payment-callback",
        method: "POST"
    },

    payload: {
        transaction_id: "txn_vp_20260623_001",
        status: "completed",
        amount: 1500000,
        currency: "VND",
        payment_method: "visa",
        completed_at: "2026-06-23T14:30:22Z",
        merchant_reference: "ORDER_CH_12345",
        card_last_four: "1234"
    },

    delivery: {
        status: "delivered",
        attempts: [
            {
                attempt_number: 1,
                sent_at: ISODate("2026-06-23T14:30:23.100Z"),
                response_status: 200,
                response_body: "{\"success\": true, \"message\": \"Đã nhận thông báo\"}",
                response_time_ms: 142,
                success: true
            }
        ],
        total_attempts: 1,
        max_attempts: 5,
        next_retry_at: null,
        delivered_at: ISODate("2026-06-23T14:30:23.242Z")
    },

    retry_config: {
        strategy: "exponential_backoff",
        base_delay_ms: 1000,
        max_delay_ms: 300000,
        multiplier: 2.0
    },

    created_at: ISODate("2026-06-23T14:30:23.000Z"),
    updated_at: ISODate("2026-06-23T14:30:23.242Z"),
    expires_at: ISODate("2026-09-21T14:30:23.000Z")
});


// ─────────────────────────────────────────────────────────────────────────────
// 5. VERIFICATION QUERIES
// ─────────────────────────────────────────────────────────────────────────────

print("\n=== Verification: Document counts ===");
print("webhook_events: " + db.webhook_events.countDocuments());
print("payment_notifications: " + db.payment_notifications.countDocuments());

print("\n=== Verification: Index list ===");
db.webhook_events.getIndexes().forEach(idx => {
    print(`  ${idx.name}: ${JSON.stringify(idx.key)}`);
});

print("\n=== Verification: Collection stats ===");
printjson(db.webhook_events.stats());
