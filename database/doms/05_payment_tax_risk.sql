-- DOMS enterprise OMS schema - payment, tax, fraud/risk, and reconciliation.
-- PostgreSQL 11 compatible. Applied after 03_order_capture_lifecycle.sql.
--
-- Payment credentials are deliberately out of scope.  DOMS stores only opaque
-- references to a PCI-compliant provider vault or an external secret manager.
-- Raw PAN, CVV, provider tokens, passwords, API secrets, and authorization
-- headers must never be persisted in this schema or its JSON documents.

CREATE OR REPLACE FUNCTION doms.is_luhn_pan(p_value text)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
STRICT
PARALLEL SAFE
AS $function$
DECLARE
    normalized_value text;
    value_length integer;
    position_from_right integer;
    digit_value integer;
    checksum_total integer := 0;
BEGIN
    IF p_value !~ '^[0-9 -]+$' THEN
        RETURN false;
    END IF;
    normalized_value := regexp_replace(p_value, '[ -]', '', 'g');
    IF normalized_value !~ '^[0-9]{13,19}$' THEN
        RETURN false;
    END IF;
    value_length := length(normalized_value);
    FOR position_from_right IN 1 .. value_length LOOP
        digit_value := substr(
            normalized_value,
            value_length - position_from_right + 1,
            1
        )::integer;
        IF mod(position_from_right, 2) = 0 THEN
            digit_value := digit_value * 2;
            IF digit_value > 9 THEN
                digit_value := digit_value - 9;
            END IF;
        END IF;
        checksum_total := checksum_total + digit_value;
    END LOOP;
    RETURN mod(checksum_total, 10) = 0;
END;
$function$;

COMMENT ON FUNCTION doms.is_luhn_pan(text) IS
    'Detects a 13-19 digit Luhn-valid PAN after removing spaces and hyphens; used only to reject raw card data.';

CREATE TABLE IF NOT EXISTS doms.payment_gateway_accounts (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id) ON DELETE RESTRICT,
    sales_channel_id uuid REFERENCES doms.sales_channels(id) ON DELETE RESTRICT,
    organization_id uuid REFERENCES doms.organizations(id) ON DELETE RESTRICT,
    gateway_account_code varchar(80) NOT NULL,
    gateway_account_name varchar(200) NOT NULL,
    provider_code varchar(60) NOT NULL,
    environment varchar(20) NOT NULL DEFAULT 'PRODUCTION',
    merchant_reference varchar(200) NOT NULL,
    credential_secret_ref varchar(500),
    webhook_secret_ref varchar(500),
    settlement_timezone varchar(100) NOT NULL DEFAULT 'Asia/Seoul',
    capture_mode varchar(20) NOT NULL DEFAULT 'MANUAL',
    supports_partial_capture boolean NOT NULL DEFAULT true,
    supports_partial_refund boolean NOT NULL DEFAULT true,
    settings jsonb NOT NULL DEFAULT '{}'::jsonb,
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    UNIQUE (tenant_id, gateway_account_code),
    UNIQUE (tenant_id, provider_code, environment, merchant_reference),
    CONSTRAINT ck_payment_gateway_environment CHECK (environment IN ('SANDBOX','PRODUCTION')),
    CONSTRAINT ck_payment_gateway_capture_mode CHECK (capture_mode IN ('AUTOMATIC','MANUAL')),
    CONSTRAINT ck_payment_gateway_status CHECK (status IN ('DRAFT','ACTIVE','DEGRADED','SUSPENDED','REVOKED','CLOSED')),
    CONSTRAINT ck_payment_gateway_settings_secrets CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(settings)
    )
);

COMMENT ON TABLE doms.payment_gateway_accounts IS
    'Tenant payment-gateway merchant accounts. Only external secret-manager references are stored; credentials and provider tokens are prohibited.';
COMMENT ON COLUMN doms.payment_gateway_accounts.credential_secret_ref IS
    'Opaque external secret-manager locator, never the credential value.';
COMMENT ON COLUMN doms.payment_gateway_accounts.webhook_secret_ref IS
    'Opaque external secret-manager locator, never the webhook signing secret.';

CREATE TABLE IF NOT EXISTS doms.payment_method_vault_references (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id) ON DELETE RESTRICT,
    gateway_account_id uuid NOT NULL REFERENCES doms.payment_gateway_accounts(id) ON DELETE RESTRICT,
    customer_id uuid NOT NULL REFERENCES doms.customers(id) ON DELETE RESTRICT,
    provider_customer_reference varchar(300),
    vault_reference varchar(500) NOT NULL,
    method_type varchar(30) NOT NULL,
    scheme_or_brand varchar(60),
    wallet_type varchar(60),
    masked_last4 char(4),
    expiry_month smallint,
    expiry_year smallint,
    issuing_country_code char(2) REFERENCES doms.countries(country_code),
    funding_type varchar(30),
    fingerprint_hash char(64),
    billing_name_masked varchar(200),
    consent_reference varchar(200),
    consented_at timestamptz,
    verified_at timestamptz,
    last_used_at timestamptz,
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    UNIQUE (tenant_id, gateway_account_id, vault_reference),
    CONSTRAINT ck_payment_vault_type CHECK (method_type IN (
        'CARD','BANK_ACCOUNT','WALLET','VIRTUAL_ACCOUNT','MOBILE','BUY_NOW_PAY_LATER','OTHER'
    )),
    CONSTRAINT ck_payment_vault_last4 CHECK (masked_last4 IS NULL OR masked_last4 ~ '^[0-9A-Za-z]{4}$'),
    CONSTRAINT ck_payment_vault_expiry CHECK (
        (expiry_month IS NULL AND expiry_year IS NULL) OR
        (expiry_month BETWEEN 1 AND 12 AND expiry_year BETWEEN 2000 AND 9999)
    ),
    CONSTRAINT ck_payment_vault_fingerprint CHECK (
        fingerprint_hash IS NULL OR fingerprint_hash ~ '^[0-9A-Fa-f]{64}$'
    ),
    CONSTRAINT ck_payment_vault_reference_safe CHECK (
        btrim(vault_reference) <> '' AND
        vault_reference !~ '[[:space:]]' AND
        vault_reference !~* '(^|[^a-z])bearer([^a-z]|$)' AND
        vault_reference !~ '^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$' AND
        vault_reference !~* '-----BEGIN[[:space:]]' AND
        NOT doms.is_luhn_pan(vault_reference)
    ),
    CONSTRAINT ck_payment_vault_status CHECK (status IN ('PENDING','ACTIVE','EXPIRED','SUSPENDED','REVOKED','DELETED')),
    CONSTRAINT ck_payment_vault_metadata_secrets CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(metadata)
    )
);

COMMENT ON TABLE doms.payment_method_vault_references IS
    'References payment methods held by a PCI-compliant external vault. Raw PAN, CVV, bank credentials, and provider tokens are prohibited.';

CREATE INDEX IF NOT EXISTS ix_payment_vault_customer
    ON doms.payment_method_vault_references (tenant_id, customer_id, status)
    WHERE deleted_at IS NULL;

CREATE TABLE IF NOT EXISTS doms.payment_intents (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id) ON DELETE RESTRICT,
    payment_intent_no varchar(100) NOT NULL,
    sales_order_id uuid NOT NULL REFERENCES doms.sales_orders(id) ON DELETE RESTRICT,
    customer_id uuid NOT NULL REFERENCES doms.customers(id) ON DELETE RESTRICT,
    sales_channel_id uuid NOT NULL REFERENCES doms.sales_channels(id) ON DELETE RESTRICT,
    gateway_account_id uuid REFERENCES doms.payment_gateway_accounts(id) ON DELETE RESTRICT,
    payment_method_vault_id uuid REFERENCES doms.payment_method_vault_references(id) ON DELETE RESTRICT,
    currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    amount numeric(20,6) NOT NULL,
    capture_method varchar(20) NOT NULL DEFAULT 'AUTOMATIC',
    confirmation_method varchar(20) NOT NULL DEFAULT 'AUTOMATIC',
    usage_type varchar(20) NOT NULL DEFAULT 'ONE_TIME',
    idempotency_key varchar(200) NOT NULL,
    client_reference varchar(200),
    provider_intent_reference varchar(300),
    status varchar(30) NOT NULL DEFAULT 'REQUIRES_PAYMENT_METHOD',
    status_reason_code varchar(80),
    description varchar(500),
    expires_at timestamptz,
    confirmed_at timestamptz,
    cancelled_at timestamptz,
    completed_at timestamptz,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, payment_intent_no),
    UNIQUE (tenant_id, idempotency_key),
    CONSTRAINT ck_payment_intent_amount CHECK (amount > 0),
    CONSTRAINT ck_payment_intent_capture CHECK (capture_method IN ('AUTOMATIC','MANUAL')),
    CONSTRAINT ck_payment_intent_confirmation CHECK (confirmation_method IN ('AUTOMATIC','MANUAL')),
    CONSTRAINT ck_payment_intent_usage CHECK (usage_type IN ('ONE_TIME','OFF_SESSION','RECURRING')),
    CONSTRAINT ck_payment_intent_status CHECK (status IN (
        'REQUIRES_PAYMENT_METHOD','REQUIRES_CONFIRMATION','REQUIRES_ACTION','PROCESSING',
        'AUTHORIZED','PARTIALLY_CAPTURED','CAPTURED','PARTIALLY_REFUNDED','REFUNDED',
        'DISPUTED','FAILED','CANCELLED','EXPIRED'
    )),
    CONSTRAINT ck_payment_intent_dates CHECK (
        (expires_at IS NULL OR expires_at > created_at) AND
        (confirmed_at IS NULL OR confirmed_at >= created_at) AND
        (cancelled_at IS NULL OR cancelled_at >= created_at) AND
        (completed_at IS NULL OR completed_at >= created_at)
    ),
    CONSTRAINT ck_payment_intent_cancelled CHECK (status <> 'CANCELLED' OR cancelled_at IS NOT NULL),
    CONSTRAINT ck_payment_intent_metadata_secrets CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(metadata)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_payment_intent_provider_ref
    ON doms.payment_intents (tenant_id, gateway_account_id, provider_intent_reference)
    WHERE provider_intent_reference IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_payment_intents_order
    ON doms.payment_intents (tenant_id, sales_order_id, created_at DESC);
CREATE INDEX IF NOT EXISTS ix_payment_intents_status
    ON doms.payment_intents (tenant_id, status, created_at DESC);

CREATE TABLE IF NOT EXISTS doms.payment_intent_lines (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id) ON DELETE RESTRICT,
    payment_intent_id uuid NOT NULL REFERENCES doms.payment_intents(id) ON DELETE CASCADE,
    line_no integer NOT NULL,
    sales_order_line_id uuid REFERENCES doms.sales_order_lines(id) ON DELETE RESTRICT,
    line_type varchar(30) NOT NULL,
    description varchar(500),
    quantity numeric(20,6) NOT NULL DEFAULT 1,
    unit_amount numeric(20,6),
    line_amount numeric(20,6) NOT NULL,
    currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (payment_intent_id, line_no),
    CONSTRAINT ck_payment_intent_line_no CHECK (line_no > 0),
    CONSTRAINT ck_payment_intent_line_quantity CHECK (quantity > 0),
    CONSTRAINT ck_payment_intent_line_type CHECK (line_type IN (
        'ORDER_ITEM','SHIPPING','TAX','FEE','DISCOUNT','GIFT_WRAP','ROUNDING','OTHER'
    )),
    CONSTRAINT ck_payment_intent_line_order_item CHECK (
        line_type <> 'ORDER_ITEM' OR sales_order_line_id IS NOT NULL
    ),
    CONSTRAINT ck_payment_intent_line_sign CHECK (
        (line_type = 'DISCOUNT' AND line_amount <= 0) OR
        (line_type <> 'DISCOUNT' AND line_amount >= 0)
    ),
    CONSTRAINT ck_payment_intent_line_metadata_secrets CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(metadata)
    )
);

CREATE INDEX IF NOT EXISTS ix_payment_intent_lines_order_line
    ON doms.payment_intent_lines (tenant_id, sales_order_line_id)
    WHERE sales_order_line_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS doms.payment_authorizations (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id) ON DELETE RESTRICT,
    payment_intent_id uuid NOT NULL REFERENCES doms.payment_intents(id) ON DELETE RESTRICT,
    gateway_account_id uuid NOT NULL REFERENCES doms.payment_gateway_accounts(id) ON DELETE RESTRICT,
    payment_method_vault_id uuid REFERENCES doms.payment_method_vault_references(id) ON DELETE RESTRICT,
    authorization_sequence integer NOT NULL,
    currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    authorized_amount numeric(20,6) NOT NULL,
    idempotency_key varchar(200) NOT NULL,
    provider_authorization_reference varchar(300),
    provider_response_code varchar(100),
    network_transaction_reference varchar(300),
    avs_result_code varchar(30),
    security_code_result varchar(30),
    status varchar(30) NOT NULL DEFAULT 'PENDING',
    authorized_at timestamptz,
    expires_at timestamptz,
    closed_at timestamptz,
    response_summary jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (payment_intent_id, authorization_sequence),
    UNIQUE (tenant_id, gateway_account_id, idempotency_key),
    CONSTRAINT ck_payment_authorization_sequence CHECK (authorization_sequence > 0),
    CONSTRAINT ck_payment_authorization_amount CHECK (authorized_amount > 0),
    CONSTRAINT ck_payment_authorization_status CHECK (status IN (
        'PENDING','PROCESSING','REQUIRES_ACTION','AUTHORIZED','PARTIALLY_CAPTURED',
        'CAPTURED','PARTIALLY_VOIDED','VOIDED','DECLINED','FAILED','CANCELLED','EXPIRED'
    )),
    CONSTRAINT ck_payment_authorization_dates CHECK (
        (authorized_at IS NULL OR authorized_at >= created_at) AND
        (expires_at IS NULL OR authorized_at IS NULL OR expires_at > authorized_at) AND
        (closed_at IS NULL OR closed_at >= created_at)
    ),
    CONSTRAINT ck_payment_authorization_success_time CHECK (
        status NOT IN ('AUTHORIZED','PARTIALLY_CAPTURED','CAPTURED','PARTIALLY_VOIDED','VOIDED')
        OR authorized_at IS NOT NULL
    ),
    CONSTRAINT ck_payment_authorization_response_secrets CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(response_summary)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_payment_authorization_provider_ref
    ON doms.payment_authorizations (tenant_id, gateway_account_id, provider_authorization_reference)
    WHERE provider_authorization_reference IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_payment_authorizations_intent
    ON doms.payment_authorizations (tenant_id, payment_intent_id, created_at DESC);

CREATE TABLE IF NOT EXISTS doms.payment_captures (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id) ON DELETE RESTRICT,
    payment_authorization_id uuid NOT NULL REFERENCES doms.payment_authorizations(id) ON DELETE RESTRICT,
    payment_intent_id uuid NOT NULL REFERENCES doms.payment_intents(id) ON DELETE RESTRICT,
    capture_sequence integer NOT NULL,
    currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    capture_amount numeric(20,6) NOT NULL,
    idempotency_key varchar(200) NOT NULL,
    provider_capture_reference varchar(300),
    status varchar(20) NOT NULL DEFAULT 'PENDING',
    requested_at timestamptz NOT NULL DEFAULT now(),
    captured_at timestamptz,
    settled_at timestamptz,
    response_summary jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (payment_authorization_id, capture_sequence),
    UNIQUE (tenant_id, idempotency_key),
    CONSTRAINT ck_payment_capture_sequence CHECK (capture_sequence > 0),
    CONSTRAINT ck_payment_capture_amount CHECK (capture_amount > 0),
    CONSTRAINT ck_payment_capture_status CHECK (status IN ('PENDING','PROCESSING','SUCCEEDED','FAILED','CANCELLED')),
    CONSTRAINT ck_payment_capture_dates CHECK (
        requested_at >= created_at AND
        (captured_at IS NULL OR captured_at >= requested_at) AND
        (settled_at IS NULL OR captured_at IS NULL OR settled_at >= captured_at)
    ),
    CONSTRAINT ck_payment_capture_success_time CHECK (status <> 'SUCCEEDED' OR captured_at IS NOT NULL),
    CONSTRAINT ck_payment_capture_response_secrets CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(response_summary)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_payment_capture_provider_ref
    ON doms.payment_captures (tenant_id, provider_capture_reference)
    WHERE provider_capture_reference IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_payment_captures_intent
    ON doms.payment_captures (tenant_id, payment_intent_id, created_at DESC);

CREATE TABLE IF NOT EXISTS doms.payment_voids (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id) ON DELETE RESTRICT,
    payment_authorization_id uuid NOT NULL REFERENCES doms.payment_authorizations(id) ON DELETE RESTRICT,
    void_sequence integer NOT NULL,
    currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    void_amount numeric(20,6) NOT NULL,
    idempotency_key varchar(200) NOT NULL,
    provider_void_reference varchar(300),
    reason_code varchar(80),
    status varchar(20) NOT NULL DEFAULT 'PENDING',
    requested_at timestamptz NOT NULL DEFAULT now(),
    voided_at timestamptz,
    response_summary jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (payment_authorization_id, void_sequence),
    UNIQUE (tenant_id, idempotency_key),
    CONSTRAINT ck_payment_void_sequence CHECK (void_sequence > 0),
    CONSTRAINT ck_payment_void_amount CHECK (void_amount > 0),
    CONSTRAINT ck_payment_void_status CHECK (status IN ('PENDING','PROCESSING','SUCCEEDED','FAILED','CANCELLED')),
    CONSTRAINT ck_payment_void_dates CHECK (
        requested_at >= created_at AND (voided_at IS NULL OR voided_at >= requested_at)
    ),
    CONSTRAINT ck_payment_void_success_time CHECK (status <> 'SUCCEEDED' OR voided_at IS NOT NULL),
    CONSTRAINT ck_payment_void_response_secrets CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(response_summary)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_payment_void_provider_ref
    ON doms.payment_voids (tenant_id, provider_void_reference)
    WHERE provider_void_reference IS NOT NULL;

CREATE TABLE IF NOT EXISTS doms.payment_refund_requests (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id) ON DELETE RESTRICT,
    refund_request_no varchar(100) NOT NULL,
    sales_order_id uuid NOT NULL REFERENCES doms.sales_orders(id) ON DELETE RESTRICT,
    payment_intent_id uuid NOT NULL REFERENCES doms.payment_intents(id) ON DELETE RESTRICT,
    customer_id uuid NOT NULL REFERENCES doms.customers(id) ON DELETE RESTRICT,
    currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    requested_amount numeric(20,6) NOT NULL,
    approved_amount numeric(20,6),
    reason_code varchar(80) NOT NULL,
    reason_detail text,
    status varchar(30) NOT NULL DEFAULT 'REQUESTED',
    requested_by uuid REFERENCES doms.users(id) ON DELETE SET NULL,
    requested_at timestamptz NOT NULL DEFAULT now(),
    reviewed_by uuid REFERENCES doms.users(id) ON DELETE SET NULL,
    reviewed_at timestamptz,
    review_note text,
    expires_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, refund_request_no),
    CONSTRAINT ck_payment_refund_request_amount CHECK (requested_amount > 0),
    CONSTRAINT ck_payment_refund_request_status CHECK (status IN (
        'REQUESTED','UNDER_REVIEW','APPROVED','PARTIALLY_APPROVED','REJECTED',
        'PROCESSING','PARTIALLY_REFUNDED','REFUNDED','CANCELLED','EXPIRED'
    )),
    CONSTRAINT ck_payment_refund_request_dates CHECK (
        requested_at >= created_at AND
        (reviewed_at IS NULL OR reviewed_at >= requested_at) AND
        (expires_at IS NULL OR expires_at > requested_at)
    ),
    CONSTRAINT ck_payment_refund_request_review CHECK (
        status NOT IN ('APPROVED','PARTIALLY_APPROVED','REJECTED') OR reviewed_at IS NOT NULL
    ),
    CONSTRAINT ck_payment_refund_request_approval_amount CHECK (
        (status IN ('REQUESTED','UNDER_REVIEW','REJECTED')
            AND approved_amount IS NULL) OR
        (status = 'APPROVED' AND approved_amount = requested_amount) OR
        (status = 'PARTIALLY_APPROVED'
            AND approved_amount > 0 AND approved_amount < requested_amount) OR
        (status IN ('PROCESSING','PARTIALLY_REFUNDED','REFUNDED')
            AND approved_amount > 0 AND approved_amount <= requested_amount) OR
        (status IN ('CANCELLED','EXPIRED')
            AND (approved_amount IS NULL OR
                 (approved_amount > 0 AND approved_amount <= requested_amount)))
    )
);

CREATE INDEX IF NOT EXISTS ix_payment_refund_requests_order
    ON doms.payment_refund_requests (tenant_id, sales_order_id, requested_at DESC);

CREATE TABLE IF NOT EXISTS doms.payment_refund_request_lines (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id) ON DELETE RESTRICT,
    refund_request_id uuid NOT NULL REFERENCES doms.payment_refund_requests(id) ON DELETE CASCADE,
    line_no integer NOT NULL,
    sales_order_line_id uuid REFERENCES doms.sales_order_lines(id) ON DELETE RESTRICT,
    requested_quantity numeric(20,6),
    principal_amount numeric(20,6) NOT NULL DEFAULT 0,
    tax_amount numeric(20,6) NOT NULL DEFAULT 0,
    shipping_amount numeric(20,6) NOT NULL DEFAULT 0,
    fee_amount numeric(20,6) NOT NULL DEFAULT 0,
    total_amount numeric(20,6) NOT NULL,
    disposition varchar(30),
    reason_code varchar(80),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (refund_request_id, line_no),
    CONSTRAINT ck_refund_request_line_no CHECK (line_no > 0),
    CONSTRAINT ck_refund_request_line_quantity CHECK (requested_quantity IS NULL OR requested_quantity > 0),
    CONSTRAINT ck_refund_request_line_amounts CHECK (
        principal_amount >= 0 AND tax_amount >= 0 AND shipping_amount >= 0 AND fee_amount >= 0 AND
        total_amount > 0 AND total_amount = principal_amount + tax_amount + shipping_amount + fee_amount
    ),
    CONSTRAINT ck_refund_request_line_disposition CHECK (
        disposition IS NULL OR disposition IN ('RESTOCK','RETURN_TO_VENDOR','SCRAP','KEEP_ITEM','SERVICE','NOT_APPLICABLE')
    )
);

CREATE TABLE IF NOT EXISTS doms.payment_refunds (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id) ON DELETE RESTRICT,
    refund_request_id uuid NOT NULL REFERENCES doms.payment_refund_requests(id) ON DELETE RESTRICT,
    payment_capture_id uuid NOT NULL REFERENCES doms.payment_captures(id) ON DELETE RESTRICT,
    payment_intent_id uuid NOT NULL REFERENCES doms.payment_intents(id) ON DELETE RESTRICT,
    refund_sequence integer NOT NULL,
    currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    refund_amount numeric(20,6) NOT NULL,
    idempotency_key varchar(200) NOT NULL,
    provider_refund_reference varchar(300),
    reason_code varchar(80),
    status varchar(20) NOT NULL DEFAULT 'PENDING',
    requested_at timestamptz NOT NULL DEFAULT now(),
    refunded_at timestamptz,
    settled_at timestamptz,
    response_summary jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (payment_capture_id, refund_sequence),
    UNIQUE (tenant_id, idempotency_key),
    CONSTRAINT ck_payment_refund_sequence CHECK (refund_sequence > 0),
    CONSTRAINT ck_payment_refund_amount CHECK (refund_amount > 0),
    CONSTRAINT ck_payment_refund_status CHECK (status IN ('PENDING','PROCESSING','SUCCEEDED','FAILED','CANCELLED')),
    CONSTRAINT ck_payment_refund_dates CHECK (
        requested_at >= created_at AND
        (refunded_at IS NULL OR refunded_at >= requested_at) AND
        (settled_at IS NULL OR refunded_at IS NULL OR settled_at >= refunded_at)
    ),
    CONSTRAINT ck_payment_refund_success_time CHECK (status <> 'SUCCEEDED' OR refunded_at IS NOT NULL),
    CONSTRAINT ck_payment_refund_response_secrets CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(response_summary)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_payment_refund_provider_ref
    ON doms.payment_refunds (tenant_id, provider_refund_reference)
    WHERE provider_refund_reference IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_payment_refunds_intent
    ON doms.payment_refunds (tenant_id, payment_intent_id, created_at DESC);

CREATE TABLE IF NOT EXISTS doms.payment_allocations (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id) ON DELETE RESTRICT,
    payment_capture_id uuid NOT NULL REFERENCES doms.payment_captures(id) ON DELETE RESTRICT,
    sales_order_id uuid NOT NULL REFERENCES doms.sales_orders(id) ON DELETE RESTRICT,
    sales_order_line_id uuid REFERENCES doms.sales_order_lines(id) ON DELETE RESTRICT,
    allocation_sequence integer NOT NULL,
    currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    allocated_amount numeric(20,6) NOT NULL,
    allocation_type varchar(20) NOT NULL DEFAULT 'PAYMENT',
    reversal_of_id uuid REFERENCES doms.payment_allocations(id) ON DELETE RESTRICT,
    idempotency_key varchar(200) NOT NULL,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid REFERENCES doms.users(id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (payment_capture_id, allocation_sequence),
    UNIQUE (tenant_id, idempotency_key),
    CONSTRAINT ck_payment_allocation_sequence CHECK (allocation_sequence > 0),
    CONSTRAINT ck_payment_allocation_amount CHECK (allocated_amount > 0),
    CONSTRAINT ck_payment_allocation_type CHECK (allocation_type IN ('PAYMENT','REVERSAL')),
    CONSTRAINT ck_payment_allocation_reversal CHECK (
        (allocation_type = 'REVERSAL' AND reversal_of_id IS NOT NULL) OR
        (allocation_type = 'PAYMENT' AND reversal_of_id IS NULL)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_payment_allocation_single_reversal
    ON doms.payment_allocations (reversal_of_id)
    WHERE reversal_of_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_payment_allocations_order
    ON doms.payment_allocations (tenant_id, sales_order_id, occurred_at DESC);

CREATE TABLE IF NOT EXISTS doms.payment_refund_allocations (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id) ON DELETE RESTRICT,
    payment_refund_id uuid NOT NULL REFERENCES doms.payment_refunds(id) ON DELETE RESTRICT,
    refund_request_line_id uuid REFERENCES doms.payment_refund_request_lines(id) ON DELETE RESTRICT,
    sales_order_id uuid NOT NULL REFERENCES doms.sales_orders(id) ON DELETE RESTRICT,
    sales_order_line_id uuid REFERENCES doms.sales_order_lines(id) ON DELETE RESTRICT,
    allocation_sequence integer NOT NULL,
    principal_amount numeric(20,6) NOT NULL DEFAULT 0,
    tax_amount numeric(20,6) NOT NULL DEFAULT 0,
    shipping_amount numeric(20,6) NOT NULL DEFAULT 0,
    fee_amount numeric(20,6) NOT NULL DEFAULT 0,
    allocated_amount numeric(20,6) NOT NULL,
    currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (payment_refund_id, allocation_sequence),
    CONSTRAINT ck_payment_refund_allocation_sequence CHECK (allocation_sequence > 0),
    CONSTRAINT ck_payment_refund_allocation_amounts CHECK (
        principal_amount >= 0 AND tax_amount >= 0 AND shipping_amount >= 0 AND fee_amount >= 0 AND
        allocated_amount > 0 AND
        allocated_amount = principal_amount + tax_amount + shipping_amount + fee_amount
    )
);

CREATE INDEX IF NOT EXISTS ix_payment_refund_allocations_order
    ON doms.payment_refund_allocations (tenant_id, sales_order_id, created_at DESC);

CREATE TABLE IF NOT EXISTS doms.payment_events (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id) ON DELETE RESTRICT,
    payment_intent_id uuid NOT NULL REFERENCES doms.payment_intents(id) ON DELETE RESTRICT,
    payment_authorization_id uuid REFERENCES doms.payment_authorizations(id) ON DELETE RESTRICT,
    payment_capture_id uuid REFERENCES doms.payment_captures(id) ON DELETE RESTRICT,
    payment_void_id uuid REFERENCES doms.payment_voids(id) ON DELETE RESTRICT,
    payment_refund_id uuid REFERENCES doms.payment_refunds(id) ON DELETE RESTRICT,
    event_type varchar(100) NOT NULL,
    event_source varchar(30) NOT NULL,
    previous_status varchar(30),
    new_status varchar(30),
    provider_event_reference varchar(300),
    correlation_id varchar(100),
    payload_summary jsonb NOT NULL DEFAULT '{}'::jsonb,
    occurred_at timestamptz NOT NULL,
    received_at timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_payment_event_source CHECK (event_source IN ('OMS','GATEWAY','CHANNEL','CUSTOMER','OPERATOR','SCHEDULED_JOB')),
    CONSTRAINT ck_payment_event_payload_secrets CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(payload_summary)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_payment_event_provider_ref
    ON doms.payment_events (tenant_id, provider_event_reference)
    WHERE provider_event_reference IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_payment_events_intent_time
    ON doms.payment_events (tenant_id, payment_intent_id, occurred_at DESC);

CREATE TABLE IF NOT EXISTS doms.payment_failures (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id) ON DELETE RESTRICT,
    payment_intent_id uuid REFERENCES doms.payment_intents(id) ON DELETE RESTRICT,
    payment_authorization_id uuid REFERENCES doms.payment_authorizations(id) ON DELETE RESTRICT,
    payment_capture_id uuid REFERENCES doms.payment_captures(id) ON DELETE RESTRICT,
    payment_void_id uuid REFERENCES doms.payment_voids(id) ON DELETE RESTRICT,
    payment_refund_id uuid REFERENCES doms.payment_refunds(id) ON DELETE RESTRICT,
    operation_type varchar(30) NOT NULL,
    failure_category varchar(30) NOT NULL,
    failure_code varchar(100) NOT NULL,
    provider_decline_code varchar(100),
    message_masked text,
    retryable boolean NOT NULL DEFAULT false,
    retry_after timestamptz,
    attempt_no integer NOT NULL DEFAULT 1,
    correlation_id varchar(100),
    diagnostic_summary jsonb NOT NULL DEFAULT '{}'::jsonb,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_payment_failure_operation CHECK (operation_type IN ('INTENT','AUTHORIZE','CAPTURE','VOID','REFUND','WEBHOOK','RECONCILIATION')),
    CONSTRAINT ck_payment_failure_category CHECK (failure_category IN (
        'CUSTOMER_ACTION','PAYMENT_METHOD','INSUFFICIENT_FUNDS','FRAUD','LIMIT',
        'VALIDATION','NETWORK','PROVIDER','CONFIGURATION','DUPLICATE','INTERNAL','UNKNOWN'
    )),
    CONSTRAINT ck_payment_failure_attempt CHECK (attempt_no > 0),
    CONSTRAINT ck_payment_failure_reference CHECK (
        payment_intent_id IS NOT NULL OR payment_authorization_id IS NOT NULL OR
        payment_capture_id IS NOT NULL OR payment_void_id IS NOT NULL OR payment_refund_id IS NOT NULL
    ),
    CONSTRAINT ck_payment_failure_diagnostic_secrets CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(diagnostic_summary)
    )
);

CREATE INDEX IF NOT EXISTS ix_payment_failures_intent_time
    ON doms.payment_failures (tenant_id, payment_intent_id, occurred_at DESC);

CREATE TABLE IF NOT EXISTS doms.payment_disputes (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id) ON DELETE RESTRICT,
    dispute_no varchar(100) NOT NULL,
    payment_capture_id uuid NOT NULL REFERENCES doms.payment_captures(id) ON DELETE RESTRICT,
    payment_intent_id uuid NOT NULL REFERENCES doms.payment_intents(id) ON DELETE RESTRICT,
    sales_order_id uuid NOT NULL REFERENCES doms.sales_orders(id) ON DELETE RESTRICT,
    customer_id uuid NOT NULL REFERENCES doms.customers(id) ON DELETE RESTRICT,
    provider_dispute_reference varchar(300) NOT NULL,
    dispute_type varchar(30) NOT NULL,
    reason_code varchar(100) NOT NULL,
    reason_detail_masked text,
    currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    disputed_amount numeric(20,6) NOT NULL,
    disputed_fee_amount numeric(20,6) NOT NULL DEFAULT 0,
    status varchar(30) NOT NULL DEFAULT 'OPEN',
    response_due_at timestamptz,
    opened_at timestamptz NOT NULL,
    submitted_at timestamptz,
    resolved_at timestamptz,
    resolution_code varchar(80),
    assigned_to uuid REFERENCES doms.users(id) ON DELETE SET NULL,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, dispute_no),
    UNIQUE (tenant_id, provider_dispute_reference),
    CONSTRAINT ck_payment_dispute_type CHECK (dispute_type IN ('CHARGEBACK','INQUIRY','RETRIEVAL','PRE_ARBITRATION','ARBITRATION')),
    CONSTRAINT ck_payment_dispute_amount CHECK (disputed_amount > 0 AND disputed_fee_amount >= 0),
    CONSTRAINT ck_payment_dispute_status CHECK (status IN (
        'OPEN','NEEDS_RESPONSE','EVIDENCE_PREPARING','SUBMITTED','UNDER_REVIEW',
        'WON','LOST','ACCEPTED','CANCELLED','CLOSED'
    )),
    CONSTRAINT ck_payment_dispute_dates CHECK (
        (response_due_at IS NULL OR response_due_at >= opened_at) AND
        (submitted_at IS NULL OR submitted_at >= opened_at) AND
        (resolved_at IS NULL OR resolved_at >= opened_at)
    ),
    CONSTRAINT ck_payment_dispute_resolution CHECK (
        status NOT IN ('WON','LOST','ACCEPTED','CANCELLED','CLOSED') OR resolved_at IS NOT NULL
    )
);

CREATE INDEX IF NOT EXISTS ix_payment_disputes_due
    ON doms.payment_disputes (tenant_id, status, response_due_at)
    WHERE status IN ('OPEN','NEEDS_RESPONSE','EVIDENCE_PREPARING');

CREATE TABLE IF NOT EXISTS doms.payment_dispute_evidence (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id) ON DELETE RESTRICT,
    payment_dispute_id uuid NOT NULL REFERENCES doms.payment_disputes(id) ON DELETE CASCADE,
    evidence_type varchar(50) NOT NULL,
    evidence_sequence integer NOT NULL,
    file_id uuid REFERENCES doms.files(id) ON DELETE RESTRICT,
    evidence_text_masked text,
    source_reference varchar(300),
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    prepared_by uuid REFERENCES doms.users(id) ON DELETE SET NULL,
    submitted_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (payment_dispute_id, evidence_sequence),
    CONSTRAINT ck_payment_dispute_evidence_sequence CHECK (evidence_sequence > 0),
    CONSTRAINT ck_payment_dispute_evidence_content CHECK (file_id IS NOT NULL OR evidence_text_masked IS NOT NULL),
    CONSTRAINT ck_payment_dispute_evidence_status CHECK (status IN ('DRAFT','READY','SUBMITTED','ACCEPTED','REJECTED','WITHDRAWN')),
    CONSTRAINT ck_payment_dispute_evidence_submission CHECK (status <> 'SUBMITTED' OR submitted_at IS NOT NULL),
    CONSTRAINT ck_payment_dispute_evidence_metadata_secrets CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(metadata)
    )
);

CREATE TABLE IF NOT EXISTS doms.payment_dispute_events (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id) ON DELETE RESTRICT,
    payment_dispute_id uuid NOT NULL REFERENCES doms.payment_disputes(id) ON DELETE RESTRICT,
    event_type varchar(80) NOT NULL,
    event_source varchar(30) NOT NULL,
    previous_status varchar(30),
    new_status varchar(30),
    provider_event_reference varchar(300),
    detail_masked text,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    actor_user_id uuid REFERENCES doms.users(id) ON DELETE SET NULL,
    occurred_at timestamptz NOT NULL,
    received_at timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_payment_dispute_event_source CHECK (event_source IN ('OMS','GATEWAY','OPERATOR','CUSTOMER','NETWORK')),
    CONSTRAINT ck_payment_dispute_event_metadata_secrets CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(metadata)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_payment_dispute_event_provider_ref
    ON doms.payment_dispute_events (tenant_id, provider_event_reference)
    WHERE provider_event_reference IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_payment_dispute_events_time
    ON doms.payment_dispute_events (tenant_id, payment_dispute_id, occurred_at DESC);

CREATE TABLE IF NOT EXISTS doms.gift_card_programs (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id) ON DELETE RESTRICT,
    program_code varchar(80) NOT NULL,
    program_name varchar(200) NOT NULL,
    sales_channel_id uuid REFERENCES doms.sales_channels(id) ON DELETE RESTRICT,
    currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    minimum_issue_amount numeric(20,6) NOT NULL DEFAULT 0,
    maximum_issue_amount numeric(20,6),
    maximum_balance numeric(20,6),
    expiry_policy varchar(30) NOT NULL DEFAULT 'NONE',
    expiry_days integer,
    transferable boolean NOT NULL DEFAULT false,
    reloadable boolean NOT NULL DEFAULT false,
    refundable boolean NOT NULL DEFAULT false,
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    UNIQUE (tenant_id, program_code),
    CONSTRAINT ck_gift_card_program_amounts CHECK (
        minimum_issue_amount >= 0 AND
        (maximum_issue_amount IS NULL OR maximum_issue_amount >= minimum_issue_amount) AND
        (maximum_balance IS NULL OR maximum_balance >= minimum_issue_amount)
    ),
    CONSTRAINT ck_gift_card_program_expiry CHECK (
        expiry_policy IN ('NONE','FIXED_DAYS','FIXED_DATE') AND
        ((expiry_policy = 'FIXED_DAYS' AND expiry_days > 0) OR
         (expiry_policy <> 'FIXED_DAYS' AND expiry_days IS NULL))
    ),
    CONSTRAINT ck_gift_card_program_status CHECK (status IN ('DRAFT','ACTIVE','SUSPENDED','CLOSED'))
);

CREATE TABLE IF NOT EXISTS doms.gift_cards (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id) ON DELETE RESTRICT,
    gift_card_program_id uuid NOT NULL REFERENCES doms.gift_card_programs(id) ON DELETE RESTRICT,
    owner_customer_id uuid REFERENCES doms.customers(id) ON DELETE RESTRICT,
    purchaser_customer_id uuid REFERENCES doms.customers(id) ON DELETE RESTRICT,
    code_lookup_hash char(64) NOT NULL,
    code_last4 char(4) NOT NULL,
    external_distribution_reference varchar(300),
    currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    issued_amount numeric(20,6) NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'PENDING',
    issued_at timestamptz,
    activated_at timestamptz,
    expires_at timestamptz,
    suspended_at timestamptz,
    closed_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, code_lookup_hash),
    CONSTRAINT ck_gift_card_code_hash CHECK (code_lookup_hash ~ '^[0-9A-Fa-f]{64}$'),
    CONSTRAINT ck_gift_card_code_last4 CHECK (code_last4 ~ '^[0-9A-Za-z]{4}$'),
    CONSTRAINT ck_gift_card_issued_amount CHECK (issued_amount > 0),
    CONSTRAINT ck_gift_card_status CHECK (status IN ('PENDING','ACTIVE','SUSPENDED','EXPIRED','DEPLETED','CLOSED')),
    CONSTRAINT ck_gift_card_dates CHECK (
        (activated_at IS NULL OR activated_at >= created_at) AND
        (expires_at IS NULL OR expires_at > COALESCE(activated_at, created_at)) AND
        (suspended_at IS NULL OR suspended_at >= created_at) AND
        (closed_at IS NULL OR closed_at >= created_at)
    )
);

COMMENT ON COLUMN doms.gift_cards.code_lookup_hash IS
    'Keyed lookup hash produced outside PostgreSQL. Plain gift-card codes are never stored.';

CREATE TABLE IF NOT EXISTS doms.gift_card_ledger_entries (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id) ON DELETE RESTRICT,
    gift_card_id uuid NOT NULL REFERENCES doms.gift_cards(id) ON DELETE RESTRICT,
    entry_sequence bigint NOT NULL,
    entry_type varchar(30) NOT NULL,
    amount_delta numeric(20,6) NOT NULL,
    balance_after numeric(20,6) NOT NULL,
    currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    sales_order_id uuid REFERENCES doms.sales_orders(id) ON DELETE RESTRICT,
    payment_intent_id uuid REFERENCES doms.payment_intents(id) ON DELETE RESTRICT,
    payment_refund_id uuid REFERENCES doms.payment_refunds(id) ON DELETE RESTRICT,
    reversal_of_id uuid REFERENCES doms.gift_card_ledger_entries(id) ON DELETE RESTRICT,
    idempotency_key varchar(200) NOT NULL,
    reason_code varchar(80),
    occurred_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid REFERENCES doms.users(id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (gift_card_id, entry_sequence),
    UNIQUE (tenant_id, idempotency_key),
    CONSTRAINT ck_gift_card_ledger_sequence CHECK (entry_sequence > 0),
    CONSTRAINT ck_gift_card_ledger_nonzero CHECK (amount_delta <> 0),
    CONSTRAINT ck_gift_card_ledger_balance CHECK (balance_after >= 0),
    CONSTRAINT ck_gift_card_ledger_type CHECK (entry_type IN (
        'ISSUE','RELOAD','REDEEM','REFUND','EXPIRE','ADJUSTMENT_CREDIT','ADJUSTMENT_DEBIT','REVERSAL'
    )),
    CONSTRAINT ck_gift_card_ledger_sign CHECK (
        (entry_type IN ('ISSUE','RELOAD','REFUND','ADJUSTMENT_CREDIT') AND amount_delta > 0) OR
        (entry_type IN ('REDEEM','EXPIRE','ADJUSTMENT_DEBIT') AND amount_delta < 0) OR
        (entry_type = 'REVERSAL' AND reversal_of_id IS NOT NULL)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_gift_card_ledger_single_reversal
    ON doms.gift_card_ledger_entries (reversal_of_id)
    WHERE reversal_of_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_gift_card_ledger_time
    ON doms.gift_card_ledger_entries (tenant_id, gift_card_id, occurred_at DESC);

CREATE TABLE IF NOT EXISTS doms.store_credit_accounts (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id) ON DELETE RESTRICT,
    customer_id uuid NOT NULL REFERENCES doms.customers(id) ON DELETE RESTRICT,
    currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    account_no varchar(100) NOT NULL,
    maximum_balance numeric(20,6),
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    suspended_at timestamptz,
    closed_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, account_no),
    UNIQUE (tenant_id, customer_id, currency_code),
    CONSTRAINT ck_store_credit_max_balance CHECK (maximum_balance IS NULL OR maximum_balance >= 0),
    CONSTRAINT ck_store_credit_status CHECK (status IN ('ACTIVE','SUSPENDED','CLOSED')),
    CONSTRAINT ck_store_credit_dates CHECK (
        (suspended_at IS NULL OR suspended_at >= created_at) AND
        (closed_at IS NULL OR closed_at >= created_at)
    )
);

CREATE TABLE IF NOT EXISTS doms.store_credit_ledger_entries (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id) ON DELETE RESTRICT,
    store_credit_account_id uuid NOT NULL REFERENCES doms.store_credit_accounts(id) ON DELETE RESTRICT,
    entry_sequence bigint NOT NULL,
    entry_type varchar(30) NOT NULL,
    amount_delta numeric(20,6) NOT NULL,
    balance_after numeric(20,6) NOT NULL,
    currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    sales_order_id uuid REFERENCES doms.sales_orders(id) ON DELETE RESTRICT,
    payment_intent_id uuid REFERENCES doms.payment_intents(id) ON DELETE RESTRICT,
    payment_refund_id uuid REFERENCES doms.payment_refunds(id) ON DELETE RESTRICT,
    reversal_of_id uuid REFERENCES doms.store_credit_ledger_entries(id) ON DELETE RESTRICT,
    idempotency_key varchar(200) NOT NULL,
    reason_code varchar(80),
    expires_at timestamptz,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid REFERENCES doms.users(id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (store_credit_account_id, entry_sequence),
    UNIQUE (tenant_id, idempotency_key),
    CONSTRAINT ck_store_credit_ledger_sequence CHECK (entry_sequence > 0),
    CONSTRAINT ck_store_credit_ledger_nonzero CHECK (amount_delta <> 0),
    CONSTRAINT ck_store_credit_ledger_balance CHECK (balance_after >= 0),
    CONSTRAINT ck_store_credit_ledger_type CHECK (entry_type IN (
        'GRANT','REFUND','REDEEM','EXPIRE','ADJUSTMENT_CREDIT','ADJUSTMENT_DEBIT','REVERSAL'
    )),
    CONSTRAINT ck_store_credit_ledger_sign CHECK (
        (entry_type IN ('GRANT','REFUND','ADJUSTMENT_CREDIT') AND amount_delta > 0) OR
        (entry_type IN ('REDEEM','EXPIRE','ADJUSTMENT_DEBIT') AND amount_delta < 0) OR
        (entry_type = 'REVERSAL' AND reversal_of_id IS NOT NULL)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_store_credit_ledger_single_reversal
    ON doms.store_credit_ledger_entries (reversal_of_id)
    WHERE reversal_of_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_store_credit_ledger_time
    ON doms.store_credit_ledger_entries (tenant_id, store_credit_account_id, occurred_at DESC);

CREATE TABLE IF NOT EXISTS doms.tax_registrations (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id) ON DELETE RESTRICT,
    organization_id uuid NOT NULL REFERENCES doms.organizations(id) ON DELETE RESTRICT,
    country_code char(2) NOT NULL REFERENCES doms.countries(country_code),
    jurisdiction_code varchar(100) NOT NULL,
    registration_type varchar(40) NOT NULL,
    registration_no_encrypted text,
    registration_no_hash char(64) NOT NULL,
    registration_no_masked varchar(120),
    filing_frequency varchar(20),
    tax_inclusive_pricing boolean NOT NULL DEFAULT false,
    status varchar(20) NOT NULL DEFAULT 'PENDING',
    valid_from date NOT NULL,
    valid_to date,
    verified_at timestamptz,
    verification_reference varchar(300),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, organization_id, jurisdiction_code, registration_type, registration_no_hash),
    CONSTRAINT ck_tax_registration_hash CHECK (registration_no_hash ~ '^[0-9A-Fa-f]{64}$'),
    CONSTRAINT ck_tax_registration_type CHECK (registration_type IN ('VAT','GST','SALES_TAX','BUSINESS','MARKETPLACE','IMPORT','OTHER')),
    CONSTRAINT ck_tax_registration_frequency CHECK (
        filing_frequency IS NULL OR filing_frequency IN ('MONTHLY','BIMONTHLY','QUARTERLY','SEMIANNUAL','ANNUAL','EVENT_BASED')
    ),
    CONSTRAINT ck_tax_registration_status CHECK (status IN ('PENDING','ACTIVE','SUSPENDED','EXPIRED','CANCELLED')),
    CONSTRAINT ck_tax_registration_dates CHECK (valid_to IS NULL OR valid_to >= valid_from),
    CONSTRAINT ck_tax_registration_verified CHECK (status <> 'ACTIVE' OR verified_at IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS ix_tax_registrations_effective
    ON doms.tax_registrations (tenant_id, organization_id, country_code, jurisdiction_code, status, valid_from);

CREATE TABLE IF NOT EXISTS doms.tax_exemptions (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id) ON DELETE RESTRICT,
    customer_id uuid NOT NULL REFERENCES doms.customers(id) ON DELETE RESTRICT,
    country_code char(2) NOT NULL REFERENCES doms.countries(country_code),
    jurisdiction_code varchar(100) NOT NULL,
    tax_code_id uuid REFERENCES doms.tax_codes(id) ON DELETE RESTRICT,
    exemption_type varchar(40) NOT NULL,
    certificate_no_encrypted text,
    certificate_no_hash char(64) NOT NULL,
    certificate_no_masked varchar(120),
    certificate_file_id uuid REFERENCES doms.files(id) ON DELETE RESTRICT,
    status varchar(20) NOT NULL DEFAULT 'PENDING',
    valid_from date NOT NULL,
    valid_to date,
    verified_by uuid REFERENCES doms.users(id) ON DELETE SET NULL,
    verified_at timestamptz,
    rejection_reason text,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, customer_id, jurisdiction_code, exemption_type, certificate_no_hash),
    CONSTRAINT ck_tax_exemption_hash CHECK (certificate_no_hash ~ '^[0-9A-Fa-f]{64}$'),
    CONSTRAINT ck_tax_exemption_type CHECK (exemption_type IN ('RESALE','DIPLOMATIC','NONPROFIT','GOVERNMENT','EXPORT','PRODUCT','OTHER')),
    CONSTRAINT ck_tax_exemption_status CHECK (status IN ('PENDING','VERIFIED','REJECTED','EXPIRED','REVOKED')),
    CONSTRAINT ck_tax_exemption_dates CHECK (valid_to IS NULL OR valid_to >= valid_from),
    CONSTRAINT ck_tax_exemption_verification CHECK (
        status <> 'VERIFIED' OR (verified_at IS NOT NULL AND verified_by IS NOT NULL)
    )
);

CREATE INDEX IF NOT EXISTS ix_tax_exemptions_effective
    ON doms.tax_exemptions (tenant_id, customer_id, country_code, jurisdiction_code, status, valid_from);

CREATE TABLE IF NOT EXISTS doms.tax_calculation_requests (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id) ON DELETE RESTRICT,
    request_no varchar(100) NOT NULL,
    idempotency_key varchar(200) NOT NULL,
    sales_order_id uuid NOT NULL REFERENCES doms.sales_orders(id) ON DELETE RESTRICT,
    customer_id uuid NOT NULL REFERENCES doms.customers(id) ON DELETE RESTRICT,
    sales_channel_id uuid NOT NULL REFERENCES doms.sales_channels(id) ON DELETE RESTRICT,
    selling_organization_id uuid REFERENCES doms.selling_organizations(id) ON DELETE RESTRICT,
    transaction_type varchar(30) NOT NULL DEFAULT 'SALE',
    currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    subtotal_amount numeric(20,6) NOT NULL,
    discount_amount numeric(20,6) NOT NULL DEFAULT 0,
    shipping_amount numeric(20,6) NOT NULL DEFAULT 0,
    handling_amount numeric(20,6) NOT NULL DEFAULT 0,
    requested_total_amount numeric(20,6) NOT NULL,
    destination_country_code char(2) NOT NULL REFERENCES doms.countries(country_code),
    destination_region_code varchar(100),
    destination_postal_prefix varchar(30),
    tax_point_at timestamptz NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'PENDING',
    provider_code varchar(60),
    provider_request_reference varchar(300),
    input_summary jsonb NOT NULL DEFAULT '{}'::jsonb,
    requested_at timestamptz NOT NULL DEFAULT now(),
    completed_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, request_no),
    UNIQUE (tenant_id, idempotency_key),
    CONSTRAINT ck_tax_calculation_request_type CHECK (transaction_type IN ('SALE','RETURN','EXCHANGE','QUOTE','ADJUSTMENT')),
    CONSTRAINT ck_tax_calculation_request_amounts CHECK (
        subtotal_amount >= 0 AND discount_amount >= 0 AND shipping_amount >= 0 AND handling_amount >= 0 AND
        requested_total_amount = subtotal_amount - discount_amount + shipping_amount + handling_amount AND
        requested_total_amount >= 0
    ),
    CONSTRAINT ck_tax_calculation_request_status CHECK (status IN ('PENDING','PROCESSING','SUCCEEDED','FAILED','CANCELLED','EXPIRED')),
    CONSTRAINT ck_tax_calculation_request_dates CHECK (
        requested_at >= created_at AND (completed_at IS NULL OR completed_at >= requested_at)
    ),
    CONSTRAINT ck_tax_calculation_request_completed CHECK (
        status NOT IN ('SUCCEEDED','FAILED','CANCELLED','EXPIRED') OR completed_at IS NOT NULL
    ),
    CONSTRAINT ck_tax_calculation_request_summary_secrets CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(input_summary)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_tax_calculation_provider_ref
    ON doms.tax_calculation_requests (tenant_id, provider_code, provider_request_reference)
    WHERE provider_request_reference IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_tax_calculation_requests_order
    ON doms.tax_calculation_requests (tenant_id, sales_order_id, requested_at DESC);

CREATE TABLE IF NOT EXISTS doms.tax_calculation_request_lines (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id) ON DELETE RESTRICT,
    tax_calculation_request_id uuid NOT NULL REFERENCES doms.tax_calculation_requests(id) ON DELETE CASCADE,
    line_no integer NOT NULL,
    sales_order_line_id uuid REFERENCES doms.sales_order_lines(id) ON DELETE RESTRICT,
    tax_code_id uuid REFERENCES doms.tax_codes(id) ON DELETE RESTRICT,
    line_type varchar(30) NOT NULL,
    quantity numeric(20,6) NOT NULL DEFAULT 1,
    gross_amount numeric(20,6) NOT NULL,
    discount_amount numeric(20,6) NOT NULL DEFAULT 0,
    net_amount numeric(20,6) NOT NULL,
    currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    item_tax_category varchar(80),
    origin_country_code char(2) REFERENCES doms.countries(country_code),
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tax_calculation_request_id, line_no),
    CONSTRAINT ck_tax_calculation_request_line_no CHECK (line_no > 0),
    CONSTRAINT ck_tax_calculation_request_line_quantity CHECK (quantity > 0),
    CONSTRAINT ck_tax_calculation_request_line_type CHECK (line_type IN ('ITEM','SHIPPING','HANDLING','FEE','DISCOUNT','OTHER')),
    CONSTRAINT ck_tax_calculation_request_line_amounts CHECK (
        gross_amount >= 0 AND discount_amount >= 0 AND net_amount = gross_amount - discount_amount AND net_amount >= 0
    ),
    CONSTRAINT ck_tax_calculation_request_line_metadata_secrets CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(metadata)
    )
);

CREATE TABLE IF NOT EXISTS doms.tax_calculation_results (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id) ON DELETE RESTRICT,
    tax_calculation_request_id uuid NOT NULL REFERENCES doms.tax_calculation_requests(id) ON DELETE RESTRICT,
    result_version integer NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    taxable_amount numeric(20,6) NOT NULL DEFAULT 0,
    exempt_amount numeric(20,6) NOT NULL DEFAULT 0,
    tax_amount numeric(20,6) NOT NULL DEFAULT 0,
    total_amount numeric(20,6) NOT NULL DEFAULT 0,
    provider_result_reference varchar(300),
    calculation_method varchar(30) NOT NULL DEFAULT 'INTERNAL',
    calculated_at timestamptz NOT NULL,
    committed_at timestamptz,
    expires_at timestamptz,
    result_summary jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tax_calculation_request_id, result_version),
    CONSTRAINT ck_tax_calculation_result_version CHECK (result_version > 0),
    CONSTRAINT ck_tax_calculation_result_status CHECK (status IN ('DRAFT','FINALIZED','COMMITTED','SUPERSEDED','VOIDED')),
    CONSTRAINT ck_tax_calculation_result_method CHECK (calculation_method IN ('INTERNAL','EXTERNAL_PROVIDER','MANUAL')),
    CONSTRAINT ck_tax_calculation_result_amounts CHECK (
        taxable_amount >= 0 AND exempt_amount >= 0 AND tax_amount >= 0 AND
        total_amount = taxable_amount + exempt_amount + tax_amount
    ),
    CONSTRAINT ck_tax_calculation_result_dates CHECK (
        (committed_at IS NULL OR committed_at >= calculated_at) AND
        (expires_at IS NULL OR expires_at > calculated_at)
    ),
    CONSTRAINT ck_tax_calculation_result_committed CHECK (status <> 'COMMITTED' OR committed_at IS NOT NULL),
    CONSTRAINT ck_tax_calculation_result_summary_secrets CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(result_summary)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_tax_calculation_committed_result
    ON doms.tax_calculation_results (tax_calculation_request_id)
    WHERE status = 'COMMITTED';

CREATE TABLE IF NOT EXISTS doms.tax_calculation_result_lines (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id) ON DELETE RESTRICT,
    tax_calculation_result_id uuid NOT NULL REFERENCES doms.tax_calculation_results(id) ON DELETE CASCADE,
    tax_calculation_request_line_id uuid NOT NULL REFERENCES doms.tax_calculation_request_lines(id) ON DELETE RESTRICT,
    line_no integer NOT NULL,
    sales_order_line_id uuid REFERENCES doms.sales_order_lines(id) ON DELETE RESTRICT,
    tax_code_id uuid REFERENCES doms.tax_codes(id) ON DELETE RESTRICT,
    tax_rate_id uuid REFERENCES doms.tax_rates(id) ON DELETE RESTRICT,
    jurisdiction_code varchar(100) NOT NULL,
    tax_type varchar(40) NOT NULL,
    rate_percent numeric(9,6) NOT NULL,
    taxable_amount numeric(20,6) NOT NULL DEFAULT 0,
    exempt_amount numeric(20,6) NOT NULL DEFAULT 0,
    tax_amount numeric(20,6) NOT NULL DEFAULT 0,
    tax_inclusive boolean NOT NULL DEFAULT false,
    exemption_id uuid REFERENCES doms.tax_exemptions(id) ON DELETE RESTRICT,
    calculation_detail jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tax_calculation_result_id, line_no, jurisdiction_code, tax_type),
    CONSTRAINT ck_tax_result_line_no CHECK (line_no > 0),
    CONSTRAINT ck_tax_result_line_rate CHECK (rate_percent BETWEEN 0 AND 100),
    CONSTRAINT ck_tax_result_line_amounts CHECK (taxable_amount >= 0 AND exempt_amount >= 0 AND tax_amount >= 0),
    CONSTRAINT ck_tax_result_line_exemption CHECK (exempt_amount = 0 OR exemption_id IS NOT NULL),
    CONSTRAINT ck_tax_result_line_detail_secrets CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(calculation_detail)
    )
);

CREATE TABLE IF NOT EXISTS doms.tax_adjustments (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id) ON DELETE RESTRICT,
    tax_calculation_result_id uuid NOT NULL REFERENCES doms.tax_calculation_results(id) ON DELETE RESTRICT,
    tax_calculation_result_line_id uuid REFERENCES doms.tax_calculation_result_lines(id) ON DELETE RESTRICT,
    sales_order_id uuid NOT NULL REFERENCES doms.sales_orders(id) ON DELETE RESTRICT,
    sales_order_line_id uuid REFERENCES doms.sales_order_lines(id) ON DELETE RESTRICT,
    adjustment_no varchar(100) NOT NULL,
    adjustment_type varchar(30) NOT NULL,
    taxable_amount_delta numeric(20,6) NOT NULL DEFAULT 0,
    exempt_amount_delta numeric(20,6) NOT NULL DEFAULT 0,
    tax_amount_delta numeric(20,6) NOT NULL,
    currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    reason_code varchar(80) NOT NULL,
    reason_detail text,
    status varchar(20) NOT NULL DEFAULT 'PENDING',
    requested_by uuid REFERENCES doms.users(id) ON DELETE SET NULL,
    approved_by uuid REFERENCES doms.users(id) ON DELETE SET NULL,
    requested_at timestamptz NOT NULL DEFAULT now(),
    approved_at timestamptz,
    posted_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, adjustment_no),
    CONSTRAINT ck_tax_adjustment_nonzero CHECK (
        taxable_amount_delta <> 0 OR exempt_amount_delta <> 0 OR tax_amount_delta <> 0
    ),
    CONSTRAINT ck_tax_adjustment_type CHECK (adjustment_type IN ('CORRECTION','REFUND','ROUNDING','EXEMPTION','RATE_CHANGE','MANUAL')),
    CONSTRAINT ck_tax_adjustment_status CHECK (status IN ('PENDING','APPROVED','REJECTED','POSTED','VOIDED')),
    CONSTRAINT ck_tax_adjustment_dates CHECK (
        (approved_at IS NULL OR approved_at >= requested_at) AND
        (posted_at IS NULL OR approved_at IS NULL OR posted_at >= approved_at)
    ),
    CONSTRAINT ck_tax_adjustment_approval CHECK (
        status NOT IN ('APPROVED','POSTED') OR (approved_at IS NOT NULL AND approved_by IS NOT NULL)
    )
);

CREATE TABLE IF NOT EXISTS doms.fraud_rules (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id) ON DELETE RESTRICT,
    rule_code varchar(100) NOT NULL,
    rule_name varchar(250) NOT NULL,
    rule_scope varchar(30) NOT NULL,
    description text,
    priority integer NOT NULL DEFAULT 100,
    default_action varchar(30) NOT NULL DEFAULT 'REVIEW',
    execution_mode varchar(20) NOT NULL DEFAULT 'ENFORCE',
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    UNIQUE (tenant_id, rule_code),
    CONSTRAINT ck_fraud_rule_scope CHECK (rule_scope IN ('ORDER','PAYMENT','REFUND','CUSTOMER','ACCOUNT','DISPUTE')),
    CONSTRAINT ck_fraud_rule_priority CHECK (priority >= 0),
    CONSTRAINT ck_fraud_rule_action CHECK (default_action IN ('ALLOW','REVIEW','HOLD','CHALLENGE','DECLINE','BLOCK')),
    CONSTRAINT ck_fraud_rule_mode CHECK (execution_mode IN ('SHADOW','MONITOR','ENFORCE'))
);

CREATE TABLE IF NOT EXISTS doms.fraud_rule_versions (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id) ON DELETE RESTRICT,
    fraud_rule_id uuid NOT NULL REFERENCES doms.fraud_rules(id) ON DELETE RESTRICT,
    version_no integer NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    condition_expression jsonb NOT NULL,
    action_parameters jsonb NOT NULL DEFAULT '{}'::jsonb,
    checksum_sha256 char(64) NOT NULL,
    effective_from timestamptz,
    effective_to timestamptz,
    approved_by uuid REFERENCES doms.users(id) ON DELETE SET NULL,
    approved_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (fraud_rule_id, version_no),
    CONSTRAINT ck_fraud_rule_version_no CHECK (version_no > 0),
    CONSTRAINT ck_fraud_rule_version_status CHECK (status IN ('DRAFT','APPROVED','ACTIVE','RETIRED','REJECTED')),
    CONSTRAINT ck_fraud_rule_version_checksum CHECK (checksum_sha256 ~ '^[0-9A-Fa-f]{64}$'),
    CONSTRAINT ck_fraud_rule_version_dates CHECK (
        effective_to IS NULL OR effective_from IS NULL OR effective_to > effective_from
    ),
    CONSTRAINT ck_fraud_rule_version_approval CHECK (
        status NOT IN ('APPROVED','ACTIVE') OR (approved_by IS NOT NULL AND approved_at IS NOT NULL)
    ),
    CONSTRAINT ck_fraud_rule_condition_secrets CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(condition_expression)
    ),
    CONSTRAINT ck_fraud_rule_parameters_secrets CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(action_parameters)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_fraud_rule_active_version
    ON doms.fraud_rule_versions (fraud_rule_id)
    WHERE status = 'ACTIVE';

CREATE TABLE IF NOT EXISTS doms.risk_assessments (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id) ON DELETE RESTRICT,
    assessment_no varchar(100) NOT NULL,
    assessment_type varchar(30) NOT NULL,
    customer_id uuid REFERENCES doms.customers(id) ON DELETE RESTRICT,
    sales_order_id uuid REFERENCES doms.sales_orders(id) ON DELETE RESTRICT,
    payment_intent_id uuid REFERENCES doms.payment_intents(id) ON DELETE RESTRICT,
    payment_refund_request_id uuid REFERENCES doms.payment_refund_requests(id) ON DELETE RESTRICT,
    payment_dispute_id uuid REFERENCES doms.payment_disputes(id) ON DELETE RESTRICT,
    sales_channel_id uuid REFERENCES doms.sales_channels(id) ON DELETE RESTRICT,
    currency_code char(3) REFERENCES doms.currencies(currency_code),
    assessed_amount numeric(20,6),
    status varchar(20) NOT NULL DEFAULT 'PENDING',
    risk_score numeric(9,4),
    risk_level varchar(20) NOT NULL DEFAULT 'UNASSESSED',
    model_code varchar(100),
    model_version varchar(100),
    ruleset_version varchar(100),
    correlation_id varchar(100),
    input_summary jsonb NOT NULL DEFAULT '{}'::jsonb,
    started_at timestamptz NOT NULL DEFAULT now(),
    completed_at timestamptz,
    expires_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, assessment_no),
    CONSTRAINT ck_risk_assessment_type CHECK (assessment_type IN ('ORDER','PAYMENT','REFUND','CUSTOMER','DISPUTE','MANUAL_REVIEW')),
    CONSTRAINT ck_risk_assessment_reference CHECK (
        customer_id IS NOT NULL OR sales_order_id IS NOT NULL OR payment_intent_id IS NOT NULL OR
        payment_refund_request_id IS NOT NULL OR payment_dispute_id IS NOT NULL
    ),
    CONSTRAINT ck_risk_assessment_amount CHECK (assessed_amount IS NULL OR assessed_amount >= 0),
    CONSTRAINT ck_risk_assessment_status CHECK (status IN ('PENDING','RUNNING','COMPLETED','FAILED','CANCELLED','EXPIRED')),
    CONSTRAINT ck_risk_assessment_score CHECK (risk_score IS NULL OR risk_score BETWEEN 0 AND 1000),
    CONSTRAINT ck_risk_assessment_level CHECK (risk_level IN ('UNASSESSED','LOW','MEDIUM','HIGH','CRITICAL','BLOCKED')),
    CONSTRAINT ck_risk_assessment_dates CHECK (
        (completed_at IS NULL OR completed_at >= started_at) AND
        (expires_at IS NULL OR expires_at > started_at)
    ),
    CONSTRAINT ck_risk_assessment_completed CHECK (
        status <> 'COMPLETED' OR (completed_at IS NOT NULL AND risk_score IS NOT NULL AND risk_level <> 'UNASSESSED')
    ),
    CONSTRAINT ck_risk_assessment_input_secrets CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(input_summary)
    )
);

CREATE INDEX IF NOT EXISTS ix_risk_assessments_order
    ON doms.risk_assessments (tenant_id, sales_order_id, started_at DESC)
    WHERE sales_order_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_risk_assessments_review
    ON doms.risk_assessments (tenant_id, risk_level, status, started_at DESC);

CREATE TABLE IF NOT EXISTS doms.risk_signals (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id) ON DELETE RESTRICT,
    risk_assessment_id uuid NOT NULL REFERENCES doms.risk_assessments(id) ON DELETE CASCADE,
    signal_code varchar(100) NOT NULL,
    signal_category varchar(40) NOT NULL,
    signal_source varchar(40) NOT NULL,
    observed_value_masked text,
    normalized_value numeric(20,6),
    boolean_value boolean,
    score_impact numeric(9,4) NOT NULL DEFAULT 0,
    severity varchar(20) NOT NULL DEFAULT 'INFO',
    evidence_summary jsonb NOT NULL DEFAULT '{}'::jsonb,
    observed_at timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (risk_assessment_id, signal_code, signal_source, observed_at),
    CONSTRAINT ck_risk_signal_category CHECK (signal_category IN (
        'IDENTITY','DEVICE','NETWORK','VELOCITY','PAYMENT','ORDER','ADDRESS','BEHAVIOR','ACCOUNT','CHARGEBACK','EXTERNAL'
    )),
    CONSTRAINT ck_risk_signal_source CHECK (signal_source IN ('OMS','GATEWAY','CHANNEL','RULE_ENGINE','MODEL','OPERATOR','EXTERNAL_PROVIDER')),
    CONSTRAINT ck_risk_signal_severity CHECK (severity IN ('INFO','LOW','MEDIUM','HIGH','CRITICAL')),
    CONSTRAINT ck_risk_signal_value CHECK (
        observed_value_masked IS NOT NULL OR normalized_value IS NOT NULL OR boolean_value IS NOT NULL
    ),
    CONSTRAINT ck_risk_signal_evidence_secrets CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(evidence_summary)
    )
);

CREATE INDEX IF NOT EXISTS ix_risk_signals_assessment
    ON doms.risk_signals (tenant_id, risk_assessment_id, severity, observed_at DESC);

CREATE TABLE IF NOT EXISTS doms.risk_rule_evaluations (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id) ON DELETE RESTRICT,
    risk_assessment_id uuid NOT NULL REFERENCES doms.risk_assessments(id) ON DELETE CASCADE,
    fraud_rule_version_id uuid NOT NULL REFERENCES doms.fraud_rule_versions(id) ON DELETE RESTRICT,
    evaluation_sequence integer NOT NULL,
    matched boolean NOT NULL,
    score_delta numeric(9,4) NOT NULL DEFAULT 0,
    recommended_action varchar(30),
    evaluation_duration_ms integer,
    fact_summary jsonb NOT NULL DEFAULT '{}'::jsonb,
    evaluated_at timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (risk_assessment_id, evaluation_sequence),
    UNIQUE (risk_assessment_id, fraud_rule_version_id),
    CONSTRAINT ck_risk_rule_evaluation_sequence CHECK (evaluation_sequence > 0),
    CONSTRAINT ck_risk_rule_evaluation_action CHECK (
        recommended_action IS NULL OR recommended_action IN ('ALLOW','REVIEW','HOLD','CHALLENGE','DECLINE','BLOCK')
    ),
    CONSTRAINT ck_risk_rule_evaluation_duration CHECK (evaluation_duration_ms IS NULL OR evaluation_duration_ms >= 0),
    CONSTRAINT ck_risk_rule_evaluation_facts_secrets CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(fact_summary)
    )
);

CREATE TABLE IF NOT EXISTS doms.risk_decisions (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id) ON DELETE RESTRICT,
    risk_assessment_id uuid NOT NULL REFERENCES doms.risk_assessments(id) ON DELETE RESTRICT,
    decision_sequence integer NOT NULL,
    decision_code varchar(30) NOT NULL,
    decision_source varchar(20) NOT NULL,
    reason_code varchar(100) NOT NULL,
    reason_detail_masked text,
    is_final boolean NOT NULL DEFAULT false,
    decided_by uuid REFERENCES doms.users(id) ON DELETE SET NULL,
    decided_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (risk_assessment_id, decision_sequence),
    CONSTRAINT ck_risk_decision_sequence CHECK (decision_sequence > 0),
    CONSTRAINT ck_risk_decision_code CHECK (decision_code IN ('APPROVE','REVIEW','HOLD','CHALLENGE','DECLINE','BLOCK','RELEASE')),
    CONSTRAINT ck_risk_decision_source CHECK (decision_source IN ('RULE','MODEL','MANUAL','POLICY','EXTERNAL')),
    CONSTRAINT ck_risk_decision_actor CHECK (decision_source <> 'MANUAL' OR decided_by IS NOT NULL),
    CONSTRAINT ck_risk_decision_dates CHECK (expires_at IS NULL OR expires_at > decided_at),
    CONSTRAINT ck_risk_decision_metadata_secrets CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(metadata)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_risk_decision_final
    ON doms.risk_decisions (risk_assessment_id)
    WHERE is_final;

CREATE TABLE IF NOT EXISTS doms.fraud_cases (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id) ON DELETE RESTRICT,
    case_no varchar(100) NOT NULL,
    case_type varchar(30) NOT NULL,
    customer_id uuid REFERENCES doms.customers(id) ON DELETE RESTRICT,
    sales_order_id uuid REFERENCES doms.sales_orders(id) ON DELETE RESTRICT,
    payment_intent_id uuid REFERENCES doms.payment_intents(id) ON DELETE RESTRICT,
    payment_dispute_id uuid REFERENCES doms.payment_disputes(id) ON DELETE RESTRICT,
    primary_risk_assessment_id uuid REFERENCES doms.risk_assessments(id) ON DELETE RESTRICT,
    currency_code char(3) REFERENCES doms.currencies(currency_code),
    exposure_amount numeric(20,6),
    priority varchar(20) NOT NULL DEFAULT 'MEDIUM',
    status varchar(30) NOT NULL DEFAULT 'OPEN',
    queue_code varchar(80),
    assigned_to uuid REFERENCES doms.users(id) ON DELETE SET NULL,
    opened_by uuid REFERENCES doms.users(id) ON DELETE SET NULL,
    opened_at timestamptz NOT NULL DEFAULT now(),
    due_at timestamptz,
    closed_by uuid REFERENCES doms.users(id) ON DELETE SET NULL,
    closed_at timestamptz,
    closure_code varchar(80),
    summary_masked text,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, case_no),
    CONSTRAINT ck_fraud_case_type CHECK (case_type IN ('ORDER_REVIEW','PAYMENT_REVIEW','REFUND_ABUSE','ACCOUNT_TAKEOVER','CHARGEBACK','POLICY_ABUSE','OTHER')),
    CONSTRAINT ck_fraud_case_reference CHECK (
        customer_id IS NOT NULL OR sales_order_id IS NOT NULL OR payment_intent_id IS NOT NULL OR
        payment_dispute_id IS NOT NULL OR primary_risk_assessment_id IS NOT NULL
    ),
    CONSTRAINT ck_fraud_case_exposure CHECK (exposure_amount IS NULL OR exposure_amount >= 0),
    CONSTRAINT ck_fraud_case_priority CHECK (priority IN ('LOW','MEDIUM','HIGH','URGENT','CRITICAL')),
    CONSTRAINT ck_fraud_case_status CHECK (status IN ('OPEN','TRIAGE','INVESTIGATING','WAITING_CUSTOMER','WAITING_PROVIDER','ESCALATED','CONFIRMED_FRAUD','FALSE_POSITIVE','RESOLVED','CLOSED')),
    CONSTRAINT ck_fraud_case_dates CHECK (
        (due_at IS NULL OR due_at > opened_at) AND (closed_at IS NULL OR closed_at >= opened_at)
    ),
    CONSTRAINT ck_fraud_case_closed CHECK (
        status NOT IN ('RESOLVED','CLOSED','CONFIRMED_FRAUD','FALSE_POSITIVE') OR closed_at IS NOT NULL
    )
);

CREATE INDEX IF NOT EXISTS ix_fraud_cases_work_queue
    ON doms.fraud_cases (tenant_id, status, priority, due_at, opened_at);

CREATE TABLE IF NOT EXISTS doms.fraud_case_events (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id) ON DELETE RESTRICT,
    fraud_case_id uuid NOT NULL REFERENCES doms.fraud_cases(id) ON DELETE RESTRICT,
    event_type varchar(80) NOT NULL,
    previous_status varchar(30),
    new_status varchar(30),
    actor_user_id uuid REFERENCES doms.users(id) ON DELETE SET NULL,
    detail_masked text,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_fraud_case_event_metadata_secrets CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(metadata)
    )
);

CREATE INDEX IF NOT EXISTS ix_fraud_case_events_time
    ON doms.fraud_case_events (tenant_id, fraud_case_id, occurred_at DESC);

CREATE TABLE IF NOT EXISTS doms.payment_settlement_batches (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id) ON DELETE RESTRICT,
    gateway_account_id uuid NOT NULL REFERENCES doms.payment_gateway_accounts(id) ON DELETE RESTRICT,
    settlement_batch_no varchar(120) NOT NULL,
    provider_batch_reference varchar(300) NOT NULL,
    currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    period_start_at timestamptz NOT NULL,
    period_end_at timestamptz NOT NULL,
    expected_settlement_at timestamptz,
    settled_at timestamptz,
    gross_capture_amount numeric(20,6) NOT NULL DEFAULT 0,
    refund_amount numeric(20,6) NOT NULL DEFAULT 0,
    chargeback_amount numeric(20,6) NOT NULL DEFAULT 0,
    fee_amount numeric(20,6) NOT NULL DEFAULT 0,
    reserve_amount numeric(20,6) NOT NULL DEFAULT 0,
    adjustment_amount numeric(20,6) NOT NULL DEFAULT 0,
    net_settlement_amount numeric(20,6) NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'PENDING',
    statement_file_id uuid REFERENCES doms.files(id) ON DELETE RESTRICT,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, settlement_batch_no),
    UNIQUE (tenant_id, gateway_account_id, provider_batch_reference),
    CONSTRAINT ck_payment_settlement_period CHECK (period_end_at > period_start_at),
    CONSTRAINT ck_payment_settlement_amounts CHECK (
        gross_capture_amount >= 0 AND refund_amount >= 0 AND chargeback_amount >= 0 AND
        fee_amount >= 0 AND reserve_amount >= 0 AND
        net_settlement_amount = gross_capture_amount - refund_amount - chargeback_amount -
            fee_amount - reserve_amount + adjustment_amount
    ),
    CONSTRAINT ck_payment_settlement_status CHECK (status IN ('PENDING','RECEIVED','VALIDATING','READY','SETTLED','RECONCILED','DISPUTED','FAILED','CANCELLED')),
    CONSTRAINT ck_payment_settlement_dates CHECK (
        (expected_settlement_at IS NULL OR expected_settlement_at >= period_end_at) AND
        (settled_at IS NULL OR settled_at >= period_end_at)
    ),
    CONSTRAINT ck_payment_settlement_settled CHECK (
        status NOT IN ('SETTLED','RECONCILED') OR settled_at IS NOT NULL
    )
);

CREATE INDEX IF NOT EXISTS ix_payment_settlement_batches_period
    ON doms.payment_settlement_batches (tenant_id, gateway_account_id, period_end_at DESC);

CREATE TABLE IF NOT EXISTS doms.payment_settlement_entries (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id) ON DELETE RESTRICT,
    settlement_batch_id uuid NOT NULL REFERENCES doms.payment_settlement_batches(id) ON DELETE RESTRICT,
    entry_sequence bigint NOT NULL,
    entry_type varchar(30) NOT NULL,
    provider_entry_reference varchar(300) NOT NULL,
    payment_capture_id uuid REFERENCES doms.payment_captures(id) ON DELETE RESTRICT,
    payment_refund_id uuid REFERENCES doms.payment_refunds(id) ON DELETE RESTRICT,
    payment_dispute_id uuid REFERENCES doms.payment_disputes(id) ON DELETE RESTRICT,
    currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    gross_amount numeric(20,6) NOT NULL DEFAULT 0,
    fee_amount numeric(20,6) NOT NULL DEFAULT 0,
    tax_withheld_amount numeric(20,6) NOT NULL DEFAULT 0,
    reserve_amount numeric(20,6) NOT NULL DEFAULT 0,
    net_amount numeric(20,6) NOT NULL,
    occurred_at timestamptz NOT NULL,
    available_at timestamptz,
    detail_summary jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (settlement_batch_id, entry_sequence),
    UNIQUE (tenant_id, provider_entry_reference),
    CONSTRAINT ck_payment_settlement_entry_sequence CHECK (entry_sequence > 0),
    CONSTRAINT ck_payment_settlement_entry_type CHECK (entry_type IN (
        'CAPTURE','REFUND','CHARGEBACK','CHARGEBACK_REVERSAL','FEE','RESERVE','RESERVE_RELEASE','ADJUSTMENT','PAYOUT'
    )),
    CONSTRAINT ck_payment_settlement_entry_reference CHECK (
        (entry_type = 'CAPTURE' AND payment_capture_id IS NOT NULL AND payment_refund_id IS NULL AND payment_dispute_id IS NULL) OR
        (entry_type = 'REFUND' AND payment_capture_id IS NULL AND payment_refund_id IS NOT NULL AND payment_dispute_id IS NULL) OR
        (entry_type IN ('CHARGEBACK','CHARGEBACK_REVERSAL') AND payment_capture_id IS NULL AND payment_refund_id IS NULL AND payment_dispute_id IS NOT NULL) OR
        (entry_type IN ('FEE','RESERVE','RESERVE_RELEASE','ADJUSTMENT','PAYOUT') AND
            payment_capture_id IS NULL AND payment_refund_id IS NULL AND payment_dispute_id IS NULL)
    ),
    CONSTRAINT ck_payment_settlement_entry_amounts CHECK (
        fee_amount >= 0 AND tax_withheld_amount >= 0 AND reserve_amount >= 0 AND
        net_amount = gross_amount - fee_amount - tax_withheld_amount - reserve_amount
    ),
    CONSTRAINT ck_payment_settlement_entry_dates CHECK (available_at IS NULL OR available_at >= occurred_at),
    CONSTRAINT ck_payment_settlement_entry_detail_secrets CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(detail_summary)
    )
);

CREATE INDEX IF NOT EXISTS ix_payment_settlement_entries_internal
    ON doms.payment_settlement_entries (tenant_id, payment_capture_id, payment_refund_id, payment_dispute_id);

CREATE TABLE IF NOT EXISTS doms.payment_reconciliation_runs (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id) ON DELETE RESTRICT,
    reconciliation_run_no varchar(100) NOT NULL,
    gateway_account_id uuid NOT NULL REFERENCES doms.payment_gateway_accounts(id) ON DELETE RESTRICT,
    period_start_at timestamptz NOT NULL,
    period_end_at timestamptz NOT NULL,
    currency_code char(3) REFERENCES doms.currencies(currency_code),
    matching_tolerance numeric(20,6) NOT NULL DEFAULT 0,
    status varchar(20) NOT NULL DEFAULT 'PENDING',
    total_external_amount numeric(20,6) NOT NULL DEFAULT 0,
    total_internal_amount numeric(20,6) NOT NULL DEFAULT 0,
    matched_amount numeric(20,6) NOT NULL DEFAULT 0,
    unmatched_amount numeric(20,6) NOT NULL DEFAULT 0,
    item_count integer NOT NULL DEFAULT 0,
    matched_count integer NOT NULL DEFAULT 0,
    exception_count integer NOT NULL DEFAULT 0,
    started_by uuid REFERENCES doms.users(id) ON DELETE SET NULL,
    started_at timestamptz,
    completed_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, reconciliation_run_no),
    CONSTRAINT ck_payment_reconciliation_period CHECK (period_end_at > period_start_at),
    CONSTRAINT ck_payment_reconciliation_tolerance CHECK (matching_tolerance >= 0),
    CONSTRAINT ck_payment_reconciliation_status CHECK (status IN ('PENDING','RUNNING','COMPLETED','COMPLETED_WITH_EXCEPTIONS','FAILED','CANCELLED')),
    CONSTRAINT ck_payment_reconciliation_amounts CHECK (
        matched_amount >= 0 AND unmatched_amount >= 0
    ),
    CONSTRAINT ck_payment_reconciliation_counts CHECK (
        item_count >= 0 AND matched_count >= 0 AND exception_count >= 0 AND matched_count <= item_count
    ),
    CONSTRAINT ck_payment_reconciliation_dates CHECK (
        (started_at IS NULL OR started_at >= created_at) AND
        (completed_at IS NULL OR started_at IS NULL OR completed_at >= started_at)
    ),
    CONSTRAINT ck_payment_reconciliation_completed CHECK (
        status NOT IN ('COMPLETED','COMPLETED_WITH_EXCEPTIONS','FAILED','CANCELLED') OR completed_at IS NOT NULL
    )
);

CREATE INDEX IF NOT EXISTS ix_payment_reconciliation_runs_period
    ON doms.payment_reconciliation_runs (tenant_id, gateway_account_id, period_end_at DESC);

CREATE TABLE IF NOT EXISTS doms.payment_reconciliation_items (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id) ON DELETE RESTRICT,
    reconciliation_run_id uuid NOT NULL REFERENCES doms.payment_reconciliation_runs(id) ON DELETE CASCADE,
    settlement_entry_id uuid REFERENCES doms.payment_settlement_entries(id) ON DELETE RESTRICT,
    payment_authorization_id uuid REFERENCES doms.payment_authorizations(id) ON DELETE RESTRICT,
    payment_capture_id uuid REFERENCES doms.payment_captures(id) ON DELETE RESTRICT,
    payment_refund_id uuid REFERENCES doms.payment_refunds(id) ON DELETE RESTRICT,
    payment_dispute_id uuid REFERENCES doms.payment_disputes(id) ON DELETE RESTRICT,
    match_key varchar(300),
    currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    external_amount numeric(20,6) NOT NULL DEFAULT 0,
    internal_amount numeric(20,6) NOT NULL DEFAULT 0,
    difference_amount numeric(20,6) NOT NULL DEFAULT 0,
    tolerance_amount numeric(20,6) NOT NULL DEFAULT 0,
    match_status varchar(30) NOT NULL DEFAULT 'UNMATCHED',
    match_method varchar(30),
    matched_at timestamptz,
    matched_by uuid REFERENCES doms.users(id) ON DELETE SET NULL,
    note text,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_payment_reconciliation_item_reference CHECK (
        settlement_entry_id IS NOT NULL OR payment_authorization_id IS NOT NULL OR payment_capture_id IS NOT NULL OR
        payment_refund_id IS NOT NULL OR payment_dispute_id IS NOT NULL
    ),
    CONSTRAINT ck_payment_reconciliation_item_tolerance CHECK (tolerance_amount >= 0),
    CONSTRAINT ck_payment_reconciliation_item_difference CHECK (
        difference_amount = external_amount - internal_amount
    ),
    CONSTRAINT ck_payment_reconciliation_item_status CHECK (match_status IN (
        'MATCHED','MATCHED_WITH_TOLERANCE','UNMATCHED','MISSING_INTERNAL','MISSING_EXTERNAL','DUPLICATE','IGNORED','MANUAL_REVIEW'
    )),
    CONSTRAINT ck_payment_reconciliation_item_method CHECK (
        match_method IS NULL OR match_method IN ('EXACT_REFERENCE','COMPOSITE_KEY','AMOUNT_DATE','MANUAL','RULE')
    ),
    CONSTRAINT ck_payment_reconciliation_item_matched CHECK (
        match_status NOT IN ('MATCHED','MATCHED_WITH_TOLERANCE') OR matched_at IS NOT NULL
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_payment_reconciliation_settlement_entry
    ON doms.payment_reconciliation_items (reconciliation_run_id, settlement_entry_id)
    WHERE settlement_entry_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_payment_reconciliation_items_status
    ON doms.payment_reconciliation_items (tenant_id, reconciliation_run_id, match_status);

CREATE TABLE IF NOT EXISTS doms.payment_reconciliation_exceptions (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id) ON DELETE RESTRICT,
    reconciliation_run_id uuid NOT NULL REFERENCES doms.payment_reconciliation_runs(id) ON DELETE CASCADE,
    reconciliation_item_id uuid REFERENCES doms.payment_reconciliation_items(id) ON DELETE CASCADE,
    exception_code varchar(100) NOT NULL,
    severity varchar(20) NOT NULL DEFAULT 'MEDIUM',
    description_masked text NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'OPEN',
    assigned_to uuid REFERENCES doms.users(id) ON DELETE SET NULL,
    resolution_code varchar(80),
    resolution_note text,
    resolved_by uuid REFERENCES doms.users(id) ON DELETE SET NULL,
    resolved_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_payment_reconciliation_exception_severity CHECK (severity IN ('LOW','MEDIUM','HIGH','CRITICAL')),
    CONSTRAINT ck_payment_reconciliation_exception_status CHECK (status IN ('OPEN','ASSIGNED','INVESTIGATING','RESOLVED','WAIVED','CLOSED')),
    CONSTRAINT ck_payment_reconciliation_exception_resolution CHECK (
        status NOT IN ('RESOLVED','WAIVED','CLOSED') OR resolved_at IS NOT NULL
    )
);

CREATE INDEX IF NOT EXISTS ix_payment_reconciliation_exception_queue
    ON doms.payment_reconciliation_exceptions (tenant_id, status, severity, created_at);

-- ---------------------------------------------------------------------------
-- Status, amount, currency, idempotency, and append-only protections.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION doms.payment_status_transition_allowed(
    p_entity varchar,
    p_old_status varchar,
    p_new_status varchar
)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
STRICT
AS $function$
BEGIN
    IF p_old_status = p_new_status THEN
        RETURN true;
    END IF;

    IF p_entity = 'OPERATION' THEN
        RETURN CASE p_old_status
            WHEN 'PENDING' THEN p_new_status IN ('PROCESSING','SUCCEEDED','FAILED','CANCELLED')
            WHEN 'PROCESSING' THEN p_new_status IN ('SUCCEEDED','FAILED','CANCELLED')
            ELSE false
        END;
    ELSIF p_entity = 'INTENT' THEN
        RETURN CASE p_old_status
            WHEN 'REQUIRES_PAYMENT_METHOD' THEN p_new_status IN ('REQUIRES_CONFIRMATION','CANCELLED','EXPIRED')
            WHEN 'REQUIRES_CONFIRMATION' THEN p_new_status IN ('REQUIRES_PAYMENT_METHOD','REQUIRES_ACTION','PROCESSING','AUTHORIZED','FAILED','CANCELLED','EXPIRED')
            WHEN 'REQUIRES_ACTION' THEN p_new_status IN ('PROCESSING','AUTHORIZED','FAILED','CANCELLED','EXPIRED')
            WHEN 'PROCESSING' THEN p_new_status IN ('REQUIRES_ACTION','AUTHORIZED','PARTIALLY_CAPTURED','CAPTURED','FAILED','CANCELLED','EXPIRED')
            WHEN 'AUTHORIZED' THEN p_new_status IN ('PARTIALLY_CAPTURED','CAPTURED','PARTIALLY_REFUNDED','REFUNDED','DISPUTED','CANCELLED','EXPIRED')
            WHEN 'PARTIALLY_CAPTURED' THEN p_new_status IN ('CAPTURED','PARTIALLY_REFUNDED','REFUNDED','DISPUTED','CANCELLED')
            WHEN 'CAPTURED' THEN p_new_status IN ('PARTIALLY_REFUNDED','REFUNDED','DISPUTED')
            WHEN 'PARTIALLY_REFUNDED' THEN p_new_status IN ('REFUNDED','DISPUTED')
            WHEN 'REFUNDED' THEN p_new_status = 'DISPUTED'
            WHEN 'DISPUTED' THEN p_new_status IN ('CAPTURED','PARTIALLY_REFUNDED','REFUNDED')
            ELSE false
        END;
    ELSIF p_entity = 'AUTHORIZATION' THEN
        RETURN CASE p_old_status
            WHEN 'PENDING' THEN p_new_status IN ('PROCESSING','REQUIRES_ACTION','AUTHORIZED','DECLINED','FAILED','CANCELLED')
            WHEN 'PROCESSING' THEN p_new_status IN ('REQUIRES_ACTION','AUTHORIZED','DECLINED','FAILED','CANCELLED')
            WHEN 'REQUIRES_ACTION' THEN p_new_status IN ('PROCESSING','AUTHORIZED','DECLINED','FAILED','CANCELLED')
            WHEN 'AUTHORIZED' THEN p_new_status IN ('PARTIALLY_CAPTURED','CAPTURED','PARTIALLY_VOIDED','VOIDED','EXPIRED')
            WHEN 'PARTIALLY_CAPTURED' THEN p_new_status IN ('CAPTURED','PARTIALLY_VOIDED','VOIDED','EXPIRED')
            WHEN 'PARTIALLY_VOIDED' THEN p_new_status IN ('PARTIALLY_CAPTURED','CAPTURED','VOIDED','EXPIRED')
            ELSE false
        END;
    ELSIF p_entity = 'REFUND_REQUEST' THEN
        RETURN CASE p_old_status
            WHEN 'REQUESTED' THEN p_new_status IN ('UNDER_REVIEW','APPROVED','PARTIALLY_APPROVED','REJECTED','CANCELLED','EXPIRED')
            WHEN 'UNDER_REVIEW' THEN p_new_status IN ('APPROVED','PARTIALLY_APPROVED','REJECTED','CANCELLED','EXPIRED')
            WHEN 'APPROVED' THEN p_new_status IN ('PROCESSING','REFUNDED','CANCELLED','EXPIRED')
            WHEN 'PARTIALLY_APPROVED' THEN p_new_status IN ('PROCESSING','PARTIALLY_REFUNDED','REFUNDED','CANCELLED','EXPIRED')
            WHEN 'PROCESSING' THEN p_new_status IN ('PARTIALLY_REFUNDED','REFUNDED','CANCELLED')
            WHEN 'PARTIALLY_REFUNDED' THEN p_new_status IN ('REFUNDED','CANCELLED')
            ELSE false
        END;
    ELSIF p_entity = 'DISPUTE' THEN
        RETURN CASE p_old_status
            WHEN 'OPEN' THEN p_new_status IN ('NEEDS_RESPONSE','EVIDENCE_PREPARING','SUBMITTED','ACCEPTED','CANCELLED','CLOSED')
            WHEN 'NEEDS_RESPONSE' THEN p_new_status IN ('EVIDENCE_PREPARING','SUBMITTED','ACCEPTED','CANCELLED','CLOSED')
            WHEN 'EVIDENCE_PREPARING' THEN p_new_status IN ('SUBMITTED','ACCEPTED','CANCELLED')
            WHEN 'SUBMITTED' THEN p_new_status IN ('UNDER_REVIEW','WON','LOST','ACCEPTED','CLOSED')
            WHEN 'UNDER_REVIEW' THEN p_new_status IN ('WON','LOST','ACCEPTED','CLOSED')
            WHEN 'WON' THEN p_new_status = 'CLOSED'
            WHEN 'LOST' THEN p_new_status = 'CLOSED'
            WHEN 'ACCEPTED' THEN p_new_status = 'CLOSED'
            ELSE false
        END;
    END IF;
    RETURN true;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.enforce_payment_initial_status()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    IF TG_NARGS <> 1 THEN
        RAISE EXCEPTION 'enforce_payment_initial_status requires one expected status';
    END IF;
    IF NEW.status IS DISTINCT FROM TG_ARGV[0] THEN
        RAISE EXCEPTION 'New %.% rows must start in status %, not %',
            TG_TABLE_SCHEMA, TG_TABLE_NAME, TG_ARGV[0], NEW.status
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.validate_tenant_references()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, doms, pg_temp
AS $function$
DECLARE
    argument_index integer;
    reference_value text;
    reference_id uuid;
    reference_tenant_id uuid;
    reference_found boolean;
BEGIN
    IF TG_NARGS = 0 OR mod(TG_NARGS, 2) <> 0 THEN
        RAISE EXCEPTION 'validate_tenant_references requires column/table argument pairs';
    END IF;

    argument_index := 0;
    WHILE argument_index < TG_NARGS LOOP
        reference_value := to_jsonb(NEW) ->> TG_ARGV[argument_index];
        IF reference_value IS NOT NULL THEN
            reference_id := reference_value::uuid;
            EXECUTE format(
                'SELECT tenant_id, true FROM doms.%I WHERE id = $1',
                TG_ARGV[argument_index + 1]
            )
            INTO reference_tenant_id, reference_found
            USING reference_id;

            IF NOT COALESCE(reference_found, false) THEN
                RAISE EXCEPTION 'Referenced %.% row does not exist',
                    TG_ARGV[argument_index + 1], reference_id
                    USING ERRCODE = '23503';
            END IF;
            IF reference_tenant_id IS DISTINCT FROM NEW.tenant_id THEN
                RAISE EXCEPTION 'Cross-tenant reference from %.% to %.% is prohibited',
                    TG_TABLE_NAME, TG_ARGV[argument_index],
                    TG_ARGV[argument_index + 1], reference_id
                    USING ERRCODE = '23514';
            END IF;
        END IF;
        argument_index := argument_index + 2;
    END LOOP;
    RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION doms.validate_tenant_references() FROM PUBLIC;

CREATE OR REPLACE FUNCTION doms.enforce_payment_status_transition()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    IF OLD.status IS DISTINCT FROM NEW.status
       AND NOT doms.payment_status_transition_allowed(TG_ARGV[0], OLD.status, NEW.status) THEN
        RAISE EXCEPTION 'Invalid % status transition: % -> %', TG_ARGV[0], OLD.status, NEW.status
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.validate_payment_intent_ready()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    order_row doms.sales_orders%ROWTYPE;
    totals_row doms.sales_order_totals%ROWTYPE;
    line_count integer;
    line_total numeric(20,6);
    bad_line_count integer;
BEGIN
    IF TG_OP = 'UPDATE' AND (
        OLD.tenant_id IS DISTINCT FROM NEW.tenant_id OR
        OLD.sales_order_id IS DISTINCT FROM NEW.sales_order_id OR
        OLD.customer_id IS DISTINCT FROM NEW.customer_id OR
        OLD.currency_code IS DISTINCT FROM NEW.currency_code OR
        OLD.idempotency_key IS DISTINCT FROM NEW.idempotency_key
    ) THEN
        RAISE EXCEPTION 'Payment intent identity, order, currency, and idempotency key are immutable'
            USING ERRCODE = '23514';
    END IF;

    SELECT * INTO order_row
      FROM doms.sales_orders
     WHERE tenant_id = NEW.tenant_id
       AND id = NEW.sales_order_id
     FOR UPDATE;
    IF NOT FOUND OR order_row.deleted_at IS NOT NULL
       OR order_row.customer_id <> NEW.customer_id
       OR order_row.sales_channel_id <> NEW.sales_channel_id
       OR order_row.currency_code <> NEW.currency_code THEN
        RAISE EXCEPTION 'Payment intent must match an active order customer, channel, tenant, and currency'
            USING ERRCODE = '23514';
    END IF;

    SELECT * INTO totals_row
      FROM doms.sales_order_totals
     WHERE tenant_id = NEW.tenant_id
       AND sales_order_id = NEW.sales_order_id
     FOR UPDATE;
    IF NOT FOUND OR totals_row.currency_code <> NEW.currency_code
       OR totals_row.grand_total_amount <> order_row.grand_total_amount
       OR NEW.amount > totals_row.grand_total_amount THEN
        RAISE EXCEPTION 'Payment intent amount exceeds or differs from the reconciled order payable amount'
            USING ERRCODE = '23514';
    END IF;

    IF NEW.status NOT IN ('REQUIRES_PAYMENT_METHOD','FAILED','CANCELLED','EXPIRED') THEN
        SELECT count(*), COALESCE(sum(line_amount), 0),
               count(*) FILTER (
                   WHERE intent_line.tenant_id <> NEW.tenant_id
                      OR intent_line.currency_code <> NEW.currency_code
                      OR (
                          intent_line.sales_order_line_id IS NOT NULL
                          AND (
                              order_line.id IS NULL
                              OR order_line.sales_order_id <> NEW.sales_order_id
                              OR order_line.tenant_id <> NEW.tenant_id
                              OR order_line.currency_code <> NEW.currency_code
                          )
                      )
               )
          INTO line_count, line_total, bad_line_count
          FROM doms.payment_intent_lines intent_line
          LEFT JOIN doms.sales_order_lines order_line
            ON order_line.id = intent_line.sales_order_line_id
           AND order_line.deleted_at IS NULL
         WHERE intent_line.payment_intent_id = NEW.id;

        IF line_count = 0 OR line_total <> NEW.amount OR bad_line_count <> 0 THEN
            RAISE EXCEPTION 'Payment intent lines must belong to the same order/tenant/currency and total exactly %', NEW.amount
                USING ERRCODE = '23514';
        END IF;
        IF NEW.status IN (
            'REQUIRES_ACTION','PROCESSING','AUTHORIZED','PARTIALLY_CAPTURED','CAPTURED',
            'PARTIALLY_REFUNDED','REFUNDED','DISPUTED'
        ) AND NEW.confirmed_at IS NULL THEN
            RAISE EXCEPTION 'A processing or financially committed payment intent requires confirmed_at'
                USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.guard_payment_intent_line_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    target_line doms.payment_intent_lines%ROWTYPE;
    intent_row doms.payment_intents%ROWTYPE;
    order_line_row doms.sales_order_lines%ROWTYPE;
BEGIN
    target_line := CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
    SELECT * INTO intent_row
      FROM doms.payment_intents
     WHERE id = target_line.payment_intent_id
     FOR UPDATE;
    IF NOT FOUND OR intent_row.tenant_id <> target_line.tenant_id
       OR intent_row.status NOT IN ('REQUIRES_PAYMENT_METHOD','REQUIRES_CONFIRMATION') THEN
        RAISE EXCEPTION 'Payment intent lines are mutable only before payment processing begins'
            USING ERRCODE = '55000';
    END IF;
    IF target_line.currency_code <> intent_row.currency_code THEN
        RAISE EXCEPTION 'Payment intent line currency must match its intent'
            USING ERRCODE = '23514';
    END IF;
    IF target_line.sales_order_line_id IS NOT NULL THEN
        SELECT * INTO order_line_row
          FROM doms.sales_order_lines
         WHERE id = target_line.sales_order_line_id;
        IF NOT FOUND OR order_line_row.deleted_at IS NOT NULL
           OR order_line_row.tenant_id <> target_line.tenant_id
           OR order_line_row.sales_order_id <> intent_row.sales_order_id
           OR order_line_row.currency_code <> target_line.currency_code THEN
            RAISE EXCEPTION 'Payment intent line must reference a line on the same order/tenant/currency'
                USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.enforce_payment_authorization_limit()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    target_order_id uuid;
    order_row doms.sales_orders%ROWTYPE;
    totals_row doms.sales_order_totals%ROWTYPE;
    intent_row doms.payment_intents%ROWTYPE;
    new_capture_total numeric(20,6);
    new_exposure numeric(20,6);
    intent_exposure numeric(20,6);
    order_exposure numeric(20,6);
    entering_authorized boolean;
BEGIN
    IF TG_OP = 'UPDATE' AND (
        OLD.tenant_id IS DISTINCT FROM NEW.tenant_id OR
        OLD.payment_intent_id IS DISTINCT FROM NEW.payment_intent_id OR
        OLD.gateway_account_id IS DISTINCT FROM NEW.gateway_account_id OR
        OLD.currency_code IS DISTINCT FROM NEW.currency_code OR
        OLD.authorized_amount IS DISTINCT FROM NEW.authorized_amount OR
        OLD.idempotency_key IS DISTINCT FROM NEW.idempotency_key
    ) THEN
        RAISE EXCEPTION 'Authorization monetary identity and idempotency key are immutable'
            USING ERRCODE = '23514';
    END IF;

    SELECT sales_order_id INTO target_order_id
      FROM doms.payment_intents
     WHERE id = NEW.payment_intent_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Authorization payment intent does not exist'
            USING ERRCODE = '23503';
    END IF;

    -- Every monetary path locks parents in the same order: order, totals, intent,
    -- then the operation-specific parent.  The order row serializes exposure
    -- across multiple intents and authorizations for one commercial order.
    SELECT * INTO order_row
      FROM doms.sales_orders
     WHERE id = target_order_id
     FOR UPDATE;
    SELECT * INTO totals_row
      FROM doms.sales_order_totals
     WHERE sales_order_id = target_order_id
     FOR UPDATE;
    SELECT * INTO intent_row
      FROM doms.payment_intents
     WHERE id = NEW.payment_intent_id
     FOR UPDATE;

    IF intent_row.id IS NULL OR order_row.id IS NULL OR totals_row.id IS NULL
       OR intent_row.tenant_id <> NEW.tenant_id
       OR order_row.tenant_id <> NEW.tenant_id
       OR totals_row.tenant_id <> NEW.tenant_id
       OR intent_row.sales_order_id <> order_row.id
       OR intent_row.customer_id <> order_row.customer_id
       OR intent_row.sales_channel_id <> order_row.sales_channel_id
       OR intent_row.currency_code <> NEW.currency_code
       OR order_row.currency_code <> NEW.currency_code
       OR totals_row.currency_code <> NEW.currency_code
       OR totals_row.grand_total_amount <> order_row.grand_total_amount
       OR intent_row.amount > totals_row.grand_total_amount THEN
        RAISE EXCEPTION 'Authorization tenant/currency must match its payment intent'
            USING ERRCODE = '23514';
    END IF;
    IF intent_row.gateway_account_id IS NOT NULL
       AND intent_row.gateway_account_id <> NEW.gateway_account_id THEN
        RAISE EXCEPTION 'Authorization gateway account must match its payment intent'
            USING ERRCODE = '23514';
    END IF;

    entering_authorized := TG_OP = 'INSERT' AND NEW.status IN (
        'AUTHORIZED','PARTIALLY_CAPTURED','CAPTURED','PARTIALLY_VOIDED'
    );
    IF TG_OP = 'UPDATE' THEN
        entering_authorized := NEW.status IN (
            'AUTHORIZED','PARTIALLY_CAPTURED','CAPTURED','PARTIALLY_VOIDED'
        ) AND OLD.status NOT IN (
            'AUTHORIZED','PARTIALLY_CAPTURED','CAPTURED','PARTIALLY_VOIDED'
        );
    END IF;
    IF NEW.status IN ('AUTHORIZED','PARTIALLY_CAPTURED','CAPTURED','PARTIALLY_VOIDED') THEN
        IF order_row.deleted_at IS NOT NULL OR order_row.order_status NOT IN (
            'SUBMITTED','CONFIRMED','CHANGE_PENDING','ON_HOLD',
            'PARTIALLY_FULFILLED','FULFILLED','COMPLETED'
        ) OR intent_row.confirmed_at IS NULL
           OR intent_row.status IN (
                'REQUIRES_PAYMENT_METHOD','FAILED','CANCELLED','EXPIRED'
           ) THEN
            RAISE EXCEPTION 'Successful authorization requires a confirmed payable order and prepared payment intent'
                USING ERRCODE = '23514';
        END IF;
        IF entering_authorized AND intent_row.status NOT IN (
            'PROCESSING','REQUIRES_ACTION','AUTHORIZED','PARTIALLY_CAPTURED'
        ) THEN
            RAISE EXCEPTION 'New authorization requires a processing or authorized payment intent'
                USING ERRCODE = '23514';
        END IF;
        PERFORM doms.assert_sales_order_totals(order_row.id);
    END IF;

    SELECT COALESCE(sum(capture_amount), 0)
      INTO new_capture_total
      FROM doms.payment_captures
     WHERE payment_authorization_id = NEW.id
       AND status IN ('PENDING','PROCESSING','SUCCEEDED');
    new_exposure := CASE
        WHEN NEW.status IN ('AUTHORIZED','PARTIALLY_CAPTURED','CAPTURED','PARTIALLY_VOIDED')
            THEN NEW.authorized_amount
        ELSE new_capture_total
    END;

    SELECT COALESCE(sum(
               CASE
                   WHEN auth_fact.status IN (
                       'AUTHORIZED','PARTIALLY_CAPTURED','CAPTURED','PARTIALLY_VOIDED'
                   ) THEN auth_fact.authorized_amount
                   ELSE COALESCE((
                       SELECT sum(capture.capture_amount)
                         FROM doms.payment_captures capture
                        WHERE capture.payment_authorization_id = auth_fact.id
                          AND capture.status IN ('PENDING','PROCESSING','SUCCEEDED')
                   ), 0)
               END
           ), 0)
      INTO intent_exposure
      FROM doms.payment_authorizations auth_fact
     WHERE auth_fact.payment_intent_id = NEW.payment_intent_id
       AND auth_fact.id <> NEW.id
       AND (
           auth_fact.status IN (
               'AUTHORIZED','PARTIALLY_CAPTURED','CAPTURED','PARTIALLY_VOIDED'
           ) OR EXISTS (
               SELECT 1 FROM doms.payment_captures capture
                WHERE capture.payment_authorization_id = auth_fact.id
                  AND capture.status IN ('PENDING','PROCESSING','SUCCEEDED')
           )
       );

    SELECT COALESCE(sum(
               CASE
                   WHEN auth_fact.status IN (
                       'AUTHORIZED','PARTIALLY_CAPTURED','CAPTURED','PARTIALLY_VOIDED'
                   ) THEN auth_fact.authorized_amount
                   ELSE COALESCE((
                       SELECT sum(capture.capture_amount)
                         FROM doms.payment_captures capture
                        WHERE capture.payment_authorization_id = auth_fact.id
                          AND capture.status IN ('PENDING','PROCESSING','SUCCEEDED')
                   ), 0)
               END
           ), 0)
      INTO order_exposure
      FROM doms.payment_authorizations auth_fact
      JOIN doms.payment_intents other_intent
        ON other_intent.id = auth_fact.payment_intent_id
     WHERE other_intent.sales_order_id = order_row.id
       AND auth_fact.id <> NEW.id
       AND (
           auth_fact.status IN (
               'AUTHORIZED','PARTIALLY_CAPTURED','CAPTURED','PARTIALLY_VOIDED'
           ) OR EXISTS (
               SELECT 1 FROM doms.payment_captures capture
                WHERE capture.payment_authorization_id = auth_fact.id
                  AND capture.status IN ('PENDING','PROCESSING','SUCCEEDED')
           )
       );

    IF intent_exposure + new_exposure > intent_row.amount THEN
        RAISE EXCEPTION 'Authorization/capture exposure would exceed payment intent amount'
            USING ERRCODE = '23514';
    END IF;
    IF order_exposure + new_exposure > totals_row.grand_total_amount THEN
        RAISE EXCEPTION 'Authorization/capture exposure would exceed order payable amount'
            USING ERRCODE = '23514';
    END IF;
    IF NEW.status IN ('AUTHORIZED','PARTIALLY_CAPTURED','CAPTURED','PARTIALLY_VOIDED')
       AND NEW.authorized_amount > intent_row.amount THEN
        RAISE EXCEPTION 'Authorized amount would exceed payment intent amount'
                USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.enforce_payment_capture_limit()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    target_order_id uuid;
    order_row doms.sales_orders%ROWTYPE;
    totals_row doms.sales_order_totals%ROWTYPE;
    intent_row doms.payment_intents%ROWTYPE;
    authorization_row doms.payment_authorizations%ROWTYPE;
    capture_total numeric(20,6);
    void_total numeric(20,6);
    intent_capture_total numeric(20,6);
    order_capture_total numeric(20,6);
    entering_succeeded boolean;
    existing_succeeded boolean;
BEGIN
    IF TG_OP = 'UPDATE' AND (
        OLD.tenant_id IS DISTINCT FROM NEW.tenant_id OR
        OLD.payment_authorization_id IS DISTINCT FROM NEW.payment_authorization_id OR
        OLD.payment_intent_id IS DISTINCT FROM NEW.payment_intent_id OR
        OLD.currency_code IS DISTINCT FROM NEW.currency_code OR
        OLD.capture_amount IS DISTINCT FROM NEW.capture_amount OR
        OLD.idempotency_key IS DISTINCT FROM NEW.idempotency_key
    ) THEN
        RAISE EXCEPTION 'Capture monetary identity and idempotency key are immutable'
            USING ERRCODE = '23514';
    END IF;

    SELECT sales_order_id INTO target_order_id
      FROM doms.payment_intents
     WHERE id = NEW.payment_intent_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Capture payment intent does not exist'
            USING ERRCODE = '23503';
    END IF;
    SELECT * INTO order_row
      FROM doms.sales_orders
     WHERE id = target_order_id
     FOR UPDATE;
    SELECT * INTO totals_row
      FROM doms.sales_order_totals
     WHERE sales_order_id = target_order_id
     FOR UPDATE;
    SELECT * INTO intent_row
      FROM doms.payment_intents
     WHERE id = NEW.payment_intent_id
     FOR UPDATE;
    SELECT * INTO authorization_row
      FROM doms.payment_authorizations
     WHERE id = NEW.payment_authorization_id
     FOR UPDATE;

    IF authorization_row.id IS NULL OR intent_row.id IS NULL
       OR order_row.id IS NULL OR totals_row.id IS NULL
       OR authorization_row.tenant_id <> NEW.tenant_id
       OR authorization_row.payment_intent_id <> NEW.payment_intent_id
       OR intent_row.tenant_id <> NEW.tenant_id
       OR intent_row.sales_order_id <> order_row.id
       OR intent_row.customer_id <> order_row.customer_id
       OR intent_row.sales_channel_id <> order_row.sales_channel_id
       OR order_row.tenant_id <> NEW.tenant_id
       OR totals_row.tenant_id <> NEW.tenant_id
       OR authorization_row.currency_code <> NEW.currency_code
       OR intent_row.currency_code <> NEW.currency_code
       OR order_row.currency_code <> NEW.currency_code
       OR totals_row.currency_code <> NEW.currency_code
       OR totals_row.grand_total_amount <> order_row.grand_total_amount
       OR intent_row.amount > totals_row.grand_total_amount THEN
        RAISE EXCEPTION 'Capture tenant, intent, and currency must match its authorization'
            USING ERRCODE = '23514';
    END IF;

    existing_succeeded := false;
    entering_succeeded := false;
    IF TG_OP = 'UPDATE' THEN
        existing_succeeded := OLD.status = 'SUCCEEDED' AND NEW.status = 'SUCCEEDED';
        entering_succeeded := OLD.status <> 'SUCCEEDED' AND NEW.status = 'SUCCEEDED';
    END IF;
    IF NEW.status IN ('PENDING','PROCESSING')
       AND authorization_row.status NOT IN (
           'AUTHORIZED','PARTIALLY_CAPTURED','PARTIALLY_VOIDED'
       ) THEN
        RAISE EXCEPTION 'Capture requires an open successful authorization'
            USING ERRCODE = '23514';
    END IF;
    IF entering_succeeded
       AND authorization_row.status NOT IN (
           'AUTHORIZED','PARTIALLY_CAPTURED','PARTIALLY_VOIDED','CAPTURED'
       ) THEN
        RAISE EXCEPTION 'Successful capture requires a successful authorization'
            USING ERRCODE = '23514';
    END IF;

    IF NEW.status IN ('PENDING','PROCESSING','SUCCEEDED') AND NOT existing_succeeded THEN
        IF order_row.deleted_at IS NOT NULL OR order_row.order_status NOT IN (
            'SUBMITTED','CONFIRMED','CHANGE_PENDING','ON_HOLD',
            'PARTIALLY_FULFILLED','FULFILLED','COMPLETED'
        ) OR intent_row.confirmed_at IS NULL
           OR intent_row.status NOT IN (
               'PROCESSING','AUTHORIZED','PARTIALLY_CAPTURED','CAPTURED'
           ) THEN
            RAISE EXCEPTION 'Capture requires a confirmed payable order and prepared payment intent'
                USING ERRCODE = '23514';
        END IF;
        PERFORM doms.assert_sales_order_totals(order_row.id);
    END IF;

    IF NEW.status IN ('PENDING','PROCESSING','SUCCEEDED') THEN
        SELECT COALESCE(sum(capture_amount), 0)
          INTO capture_total
          FROM doms.payment_captures
         WHERE payment_authorization_id = NEW.payment_authorization_id
           AND id <> NEW.id
           AND status IN ('PENDING','PROCESSING','SUCCEEDED');
        SELECT COALESCE(sum(void_amount), 0)
          INTO void_total
          FROM doms.payment_voids
         WHERE payment_authorization_id = NEW.payment_authorization_id
           AND status IN ('PENDING','PROCESSING','SUCCEEDED');
        IF capture_total + void_total + NEW.capture_amount > authorization_row.authorized_amount THEN
            RAISE EXCEPTION 'Capture plus void reservations would exceed authorized amount'
                USING ERRCODE = '23514';
        END IF;

        SELECT COALESCE(sum(capture_amount), 0)
          INTO intent_capture_total
          FROM doms.payment_captures
         WHERE payment_intent_id = NEW.payment_intent_id
           AND id <> NEW.id
           AND status IN ('PENDING','PROCESSING','SUCCEEDED');
        IF intent_capture_total + NEW.capture_amount > intent_row.amount THEN
            RAISE EXCEPTION 'Capture reservations would exceed payment intent amount'
                USING ERRCODE = '23514';
        END IF;

        SELECT COALESCE(sum(capture.capture_amount), 0)
          INTO order_capture_total
          FROM doms.payment_captures capture
          JOIN doms.payment_intents other_intent
            ON other_intent.id = capture.payment_intent_id
         WHERE other_intent.sales_order_id = order_row.id
           AND capture.id <> NEW.id
           AND capture.status IN ('PENDING','PROCESSING','SUCCEEDED');
        IF order_capture_total + NEW.capture_amount > totals_row.grand_total_amount THEN
            RAISE EXCEPTION 'Capture reservations would exceed order payable amount'
                USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.enforce_payment_void_limit()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    authorization_row doms.payment_authorizations%ROWTYPE;
    capture_total numeric(20,6);
    void_total numeric(20,6);
BEGIN
    IF TG_OP = 'UPDATE' AND (
        OLD.tenant_id IS DISTINCT FROM NEW.tenant_id OR
        OLD.payment_authorization_id IS DISTINCT FROM NEW.payment_authorization_id OR
        OLD.currency_code IS DISTINCT FROM NEW.currency_code OR
        OLD.void_amount IS DISTINCT FROM NEW.void_amount OR
        OLD.idempotency_key IS DISTINCT FROM NEW.idempotency_key
    ) THEN
        RAISE EXCEPTION 'Void monetary identity and idempotency key are immutable'
            USING ERRCODE = '23514';
    END IF;

    SELECT * INTO authorization_row
      FROM doms.payment_authorizations
     WHERE id = NEW.payment_authorization_id
     FOR UPDATE;

    IF NOT FOUND OR authorization_row.tenant_id <> NEW.tenant_id
       OR authorization_row.currency_code <> NEW.currency_code THEN
        RAISE EXCEPTION 'Void tenant/currency must match its authorization'
            USING ERRCODE = '23514';
    END IF;
    IF NEW.status IN ('PENDING','PROCESSING','SUCCEEDED')
       AND authorization_row.status NOT IN ('AUTHORIZED','PARTIALLY_CAPTURED','PARTIALLY_VOIDED') THEN
        RAISE EXCEPTION 'Void requires an open successful authorization'
            USING ERRCODE = '23514';
    END IF;

    IF NEW.status IN ('PENDING','PROCESSING','SUCCEEDED') THEN
        SELECT COALESCE(sum(capture_amount), 0)
          INTO capture_total
          FROM doms.payment_captures
         WHERE payment_authorization_id = NEW.payment_authorization_id
           AND status IN ('PENDING','PROCESSING','SUCCEEDED');
        SELECT COALESCE(sum(void_amount), 0)
          INTO void_total
          FROM doms.payment_voids
         WHERE payment_authorization_id = NEW.payment_authorization_id
           AND id <> NEW.id
           AND status IN ('PENDING','PROCESSING','SUCCEEDED');
        IF capture_total + void_total + NEW.void_amount > authorization_row.authorized_amount THEN
            RAISE EXCEPTION 'Capture plus void reservations would exceed authorized amount'
                USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.validate_payment_refund_request()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    order_row doms.sales_orders%ROWTYPE;
    intent_row doms.payment_intents%ROWTYPE;
    captured_total numeric(20,6);
    approved_total numeric(20,6);
BEGIN
    IF TG_OP = 'UPDATE' AND (
        OLD.tenant_id IS DISTINCT FROM NEW.tenant_id OR
        OLD.sales_order_id IS DISTINCT FROM NEW.sales_order_id OR
        OLD.payment_intent_id IS DISTINCT FROM NEW.payment_intent_id OR
        OLD.customer_id IS DISTINCT FROM NEW.customer_id OR
        OLD.currency_code IS DISTINCT FROM NEW.currency_code OR
        OLD.requested_amount IS DISTINCT FROM NEW.requested_amount
    ) THEN
        RAISE EXCEPTION 'Refund request order, intent, customer, currency, and requested amount are immutable'
            USING ERRCODE = '23514';
    END IF;
    IF TG_OP = 'UPDATE'
       AND OLD.status NOT IN ('REQUESTED','UNDER_REVIEW')
       AND OLD.approved_amount IS DISTINCT FROM NEW.approved_amount THEN
        RAISE EXCEPTION 'Decided refund request approved amount is immutable'
            USING ERRCODE = '23514';
    END IF;

    SELECT * INTO order_row
      FROM doms.sales_orders
     WHERE id = NEW.sales_order_id
     FOR UPDATE;
    SELECT * INTO intent_row
      FROM doms.payment_intents
     WHERE id = NEW.payment_intent_id
     FOR UPDATE;
    IF order_row.id IS NULL OR intent_row.id IS NULL
       OR order_row.deleted_at IS NOT NULL
       OR order_row.tenant_id <> NEW.tenant_id
       OR intent_row.tenant_id <> NEW.tenant_id
       OR intent_row.sales_order_id <> NEW.sales_order_id
       OR order_row.customer_id <> NEW.customer_id
       OR intent_row.customer_id <> NEW.customer_id
       OR intent_row.sales_channel_id <> order_row.sales_channel_id
       OR order_row.currency_code <> NEW.currency_code
       OR intent_row.currency_code <> NEW.currency_code THEN
        RAISE EXCEPTION 'Refund request must match one active order, customer, intent, tenant, and currency'
            USING ERRCODE = '23514';
    END IF;

    SELECT COALESCE(sum(capture_amount), 0)
      INTO captured_total
      FROM doms.payment_captures
     WHERE payment_intent_id = NEW.payment_intent_id
       AND status = 'SUCCEEDED';
    IF NEW.requested_amount > captured_total THEN
        RAISE EXCEPTION 'Refund request amount exceeds succeeded capture amount'
            USING ERRCODE = '23514';
    END IF;

    IF NEW.status IN (
        'APPROVED','PARTIALLY_APPROVED','PROCESSING','PARTIALLY_REFUNDED','REFUNDED'
    ) THEN
        SELECT COALESCE(sum(approved_amount), 0)
          INTO approved_total
          FROM doms.payment_refund_requests
         WHERE payment_intent_id = NEW.payment_intent_id
           AND id <> NEW.id
           AND status IN (
               'APPROVED','PARTIALLY_APPROVED','PROCESSING',
               'PARTIALLY_REFUNDED','REFUNDED'
           );
        IF NEW.approved_amount IS NULL
           OR approved_total + NEW.approved_amount > captured_total THEN
            RAISE EXCEPTION 'Approved refund requests exceed succeeded capture amount'
                USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.enforce_payment_refund_limit()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    target_order_id uuid;
    target_intent_id uuid;
    order_row doms.sales_orders%ROWTYPE;
    intent_row doms.payment_intents%ROWTYPE;
    request_row doms.payment_refund_requests%ROWTYPE;
    capture_row doms.payment_captures%ROWTYPE;
    capture_refund_total numeric(20,6);
    request_refund_total numeric(20,6);
    existing_succeeded boolean;
BEGIN
    IF TG_OP = 'UPDATE' AND (
        OLD.tenant_id IS DISTINCT FROM NEW.tenant_id OR
        OLD.refund_request_id IS DISTINCT FROM NEW.refund_request_id OR
        OLD.payment_capture_id IS DISTINCT FROM NEW.payment_capture_id OR
        OLD.payment_intent_id IS DISTINCT FROM NEW.payment_intent_id OR
        OLD.currency_code IS DISTINCT FROM NEW.currency_code OR
        OLD.refund_amount IS DISTINCT FROM NEW.refund_amount OR
        OLD.idempotency_key IS DISTINCT FROM NEW.idempotency_key
    ) THEN
        RAISE EXCEPTION 'Refund monetary identity and idempotency key are immutable'
            USING ERRCODE = '23514';
    END IF;

    SELECT sales_order_id, payment_intent_id
      INTO target_order_id, target_intent_id
      FROM doms.payment_refund_requests
     WHERE id = NEW.refund_request_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Refund request does not exist'
            USING ERRCODE = '23503';
    END IF;
    SELECT * INTO order_row
      FROM doms.sales_orders
     WHERE id = target_order_id
     FOR UPDATE;
    SELECT * INTO intent_row
      FROM doms.payment_intents
     WHERE id = target_intent_id
     FOR UPDATE;
    SELECT * INTO request_row
      FROM doms.payment_refund_requests
     WHERE id = NEW.refund_request_id
     FOR UPDATE;
    SELECT * INTO capture_row
      FROM doms.payment_captures
     WHERE id = NEW.payment_capture_id
     FOR UPDATE;

    IF request_row.id IS NULL OR capture_row.id IS NULL
       OR intent_row.id IS NULL OR order_row.id IS NULL
       OR capture_row.status <> 'SUCCEEDED'
       OR request_row.tenant_id <> NEW.tenant_id
       OR capture_row.tenant_id <> NEW.tenant_id
       OR intent_row.tenant_id <> NEW.tenant_id
       OR order_row.tenant_id <> NEW.tenant_id
       OR request_row.sales_order_id <> order_row.id
       OR request_row.payment_intent_id <> intent_row.id
       OR request_row.customer_id <> order_row.customer_id
       OR intent_row.sales_order_id <> order_row.id
       OR intent_row.customer_id <> request_row.customer_id
       OR capture_row.payment_intent_id <> NEW.payment_intent_id
       OR NEW.payment_intent_id <> intent_row.id
       OR request_row.currency_code <> NEW.currency_code
       OR capture_row.currency_code <> NEW.currency_code
       OR intent_row.currency_code <> NEW.currency_code
       OR order_row.currency_code <> NEW.currency_code THEN
        RAISE EXCEPTION 'Refund must match one request, order, customer, succeeded capture, intent, tenant, and currency'
            USING ERRCODE = '23514';
    END IF;

    existing_succeeded := false;
    IF TG_OP = 'UPDATE' THEN
        existing_succeeded := OLD.status = 'SUCCEEDED' AND NEW.status = 'SUCCEEDED';
    END IF;
    IF NEW.status IN ('PENDING','PROCESSING','SUCCEEDED') THEN
        IF NOT existing_succeeded AND request_row.status NOT IN (
            'APPROVED','PARTIALLY_APPROVED','PROCESSING','PARTIALLY_REFUNDED'
        ) THEN
            RAISE EXCEPTION 'Refund requires an approved, processing, or partially refunded request'
                USING ERRCODE = '23514';
        END IF;
        SELECT COALESCE(sum(refund_amount), 0)
          INTO capture_refund_total
          FROM doms.payment_refunds
         WHERE payment_capture_id = NEW.payment_capture_id
           AND id <> NEW.id
           AND status IN ('PENDING','PROCESSING','SUCCEEDED');
        IF capture_refund_total + NEW.refund_amount > capture_row.capture_amount THEN
            RAISE EXCEPTION 'Refund reservations would exceed captured amount'
                USING ERRCODE = '23514';
        END IF;

        SELECT COALESCE(sum(refund_amount), 0)
          INTO request_refund_total
          FROM doms.payment_refunds
         WHERE refund_request_id = NEW.refund_request_id
           AND id <> NEW.id
           AND status IN ('PENDING','PROCESSING','SUCCEEDED');
        IF request_row.approved_amount IS NULL
           OR request_refund_total + NEW.refund_amount > request_row.approved_amount THEN
            RAISE EXCEPTION 'Refund reservations would exceed approved refund request amount'
                USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.enforce_payment_allocation_limit()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    capture_row doms.payment_captures%ROWTYPE;
    original_row doms.payment_allocations%ROWTYPE;
    allocated_total numeric(20,6);
    new_effect numeric(20,6);
BEGIN
    SELECT * INTO capture_row
      FROM doms.payment_captures
     WHERE id = NEW.payment_capture_id
     FOR UPDATE;

    IF NOT FOUND OR capture_row.status <> 'SUCCEEDED'
       OR capture_row.tenant_id <> NEW.tenant_id
       OR capture_row.currency_code <> NEW.currency_code THEN
        RAISE EXCEPTION 'Allocation requires a succeeded capture with matching tenant/currency'
            USING ERRCODE = '23514';
    END IF;

    new_effect := NEW.allocated_amount;
    IF NEW.allocation_type = 'REVERSAL' THEN
        SELECT * INTO original_row
          FROM doms.payment_allocations
         WHERE id = NEW.reversal_of_id;
        IF NOT FOUND OR original_row.allocation_type <> 'PAYMENT'
           OR original_row.payment_capture_id <> NEW.payment_capture_id
           OR original_row.sales_order_id <> NEW.sales_order_id
           OR original_row.sales_order_line_id IS DISTINCT FROM NEW.sales_order_line_id
           OR original_row.currency_code <> NEW.currency_code
           OR original_row.allocated_amount <> NEW.allocated_amount THEN
            RAISE EXCEPTION 'Allocation reversal must exactly reverse one payment allocation'
                USING ERRCODE = '23514';
        END IF;
        new_effect := -NEW.allocated_amount;
    END IF;

    SELECT COALESCE(sum(
               CASE WHEN allocation_type = 'PAYMENT' THEN allocated_amount ELSE -allocated_amount END
           ), 0)
      INTO allocated_total
      FROM doms.payment_allocations
     WHERE payment_capture_id = NEW.payment_capture_id;

    IF allocated_total + new_effect < 0 OR allocated_total + new_effect > capture_row.capture_amount THEN
        RAISE EXCEPTION 'Net payment allocations must stay between zero and captured amount'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.enforce_payment_refund_allocation_limit()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    refund_row doms.payment_refunds%ROWTYPE;
    allocated_total numeric(20,6);
BEGIN
    SELECT * INTO refund_row
      FROM doms.payment_refunds
     WHERE id = NEW.payment_refund_id
     FOR UPDATE;

    IF NOT FOUND OR refund_row.status <> 'SUCCEEDED'
       OR refund_row.tenant_id <> NEW.tenant_id
       OR refund_row.currency_code <> NEW.currency_code THEN
        RAISE EXCEPTION 'Refund allocation requires a succeeded refund with matching tenant/currency'
            USING ERRCODE = '23514';
    END IF;

    SELECT COALESCE(sum(allocated_amount), 0)
      INTO allocated_total
      FROM doms.payment_refund_allocations
     WHERE payment_refund_id = NEW.payment_refund_id;
    IF allocated_total + NEW.allocated_amount > refund_row.refund_amount THEN
        RAISE EXCEPTION 'Refund allocations would exceed refunded amount'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.apply_gift_card_ledger_entry()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    card_row doms.gift_cards%ROWTYPE;
    original_row doms.gift_card_ledger_entries%ROWTYPE;
    program_max numeric(20,6);
    current_balance numeric(20,6);
    entry_count bigint;
BEGIN
    SELECT card.* INTO card_row
      FROM doms.gift_cards card
     WHERE card.id = NEW.gift_card_id
     FOR UPDATE;
    IF NOT FOUND OR card_row.tenant_id <> NEW.tenant_id OR card_row.currency_code <> NEW.currency_code THEN
        RAISE EXCEPTION 'Gift-card ledger tenant/currency must match the card'
            USING ERRCODE = '23514';
    END IF;
    IF card_row.status NOT IN ('PENDING','ACTIVE','DEPLETED') THEN
        RAISE EXCEPTION 'Gift card is not available for ledger posting'
            USING ERRCODE = '23514';
    END IF;

    SELECT maximum_balance INTO program_max
      FROM doms.gift_card_programs
     WHERE id = card_row.gift_card_program_id;

    SELECT COALESCE(sum(amount_delta), 0), count(*)
      INTO current_balance, entry_count
      FROM doms.gift_card_ledger_entries
     WHERE gift_card_id = NEW.gift_card_id;

    IF entry_count = 0 AND (NEW.entry_type <> 'ISSUE' OR NEW.amount_delta <> card_row.issued_amount) THEN
        RAISE EXCEPTION 'First gift-card ledger entry must issue the configured issued amount'
            USING ERRCODE = '23514';
    END IF;

    IF NEW.entry_type = 'REVERSAL' THEN
        SELECT * INTO original_row
          FROM doms.gift_card_ledger_entries
         WHERE id = NEW.reversal_of_id;
        IF NOT FOUND OR original_row.gift_card_id <> NEW.gift_card_id
           OR original_row.currency_code <> NEW.currency_code
           OR NEW.amount_delta <> -original_row.amount_delta THEN
            RAISE EXCEPTION 'Gift-card reversal must be the exact opposite of one entry on the same card'
                USING ERRCODE = '23514';
        END IF;
    END IF;

    NEW.balance_after := current_balance + NEW.amount_delta;
    IF NEW.balance_after < 0 OR (program_max IS NOT NULL AND NEW.balance_after > program_max) THEN
        RAISE EXCEPTION 'Gift-card balance would violate zero or program maximum balance'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.apply_store_credit_ledger_entry()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    account_row doms.store_credit_accounts%ROWTYPE;
    original_row doms.store_credit_ledger_entries%ROWTYPE;
    current_balance numeric(20,6);
BEGIN
    SELECT * INTO account_row
      FROM doms.store_credit_accounts
     WHERE id = NEW.store_credit_account_id
     FOR UPDATE;
    IF NOT FOUND OR account_row.status <> 'ACTIVE'
       OR account_row.tenant_id <> NEW.tenant_id OR account_row.currency_code <> NEW.currency_code THEN
        RAISE EXCEPTION 'Store-credit ledger requires an active account with matching tenant/currency'
            USING ERRCODE = '23514';
    END IF;

    SELECT COALESCE(sum(amount_delta), 0)
      INTO current_balance
      FROM doms.store_credit_ledger_entries
     WHERE store_credit_account_id = NEW.store_credit_account_id;

    IF NEW.entry_type = 'REVERSAL' THEN
        SELECT * INTO original_row
          FROM doms.store_credit_ledger_entries
         WHERE id = NEW.reversal_of_id;
        IF NOT FOUND OR original_row.store_credit_account_id <> NEW.store_credit_account_id
           OR original_row.currency_code <> NEW.currency_code
           OR NEW.amount_delta <> -original_row.amount_delta THEN
            RAISE EXCEPTION 'Store-credit reversal must be the exact opposite of one entry on the same account'
                USING ERRCODE = '23514';
        END IF;
    END IF;

    NEW.balance_after := current_balance + NEW.amount_delta;
    IF NEW.balance_after < 0
       OR (account_row.maximum_balance IS NOT NULL AND NEW.balance_after > account_row.maximum_balance) THEN
        RAISE EXCEPTION 'Store-credit balance would violate zero or account maximum balance'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.prevent_append_only_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    RAISE EXCEPTION '% is append-only; post a compensating/reversal entry instead', TG_TABLE_NAME
        USING ERRCODE = '55000';
END;
$function$;

CREATE OR REPLACE FUNCTION doms.validate_tax_request_ready()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    line_count integer;
    line_total numeric(20,6);
    bad_line_count integer;
BEGIN
    IF TG_OP = 'UPDATE' AND (
        OLD.tenant_id IS DISTINCT FROM NEW.tenant_id OR
        OLD.sales_order_id IS DISTINCT FROM NEW.sales_order_id OR
        OLD.customer_id IS DISTINCT FROM NEW.customer_id OR
        OLD.currency_code IS DISTINCT FROM NEW.currency_code OR
        OLD.idempotency_key IS DISTINCT FROM NEW.idempotency_key
    ) THEN
        RAISE EXCEPTION 'Tax request identity, order, currency, and idempotency key are immutable'
            USING ERRCODE = '23514';
    END IF;

    IF NEW.status IN ('PROCESSING','SUCCEEDED') THEN
        SELECT count(*), COALESCE(sum(net_amount), 0),
               count(*) FILTER (WHERE tenant_id <> NEW.tenant_id OR currency_code <> NEW.currency_code)
          INTO line_count, line_total, bad_line_count
          FROM doms.tax_calculation_request_lines
         WHERE tax_calculation_request_id = NEW.id;
        IF line_count = 0 OR line_total <> NEW.requested_total_amount OR bad_line_count <> 0 THEN
            RAISE EXCEPTION 'Tax request lines must share tenant/currency and total exactly %', NEW.requested_total_amount
                USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.guard_tax_request_line_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    parent_status varchar(20);
    parent_id uuid;
BEGIN
    parent_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.tax_calculation_request_id ELSE NEW.tax_calculation_request_id END;
    SELECT status INTO parent_status
      FROM doms.tax_calculation_requests
     WHERE id = parent_id
     FOR UPDATE;
    IF parent_status <> 'PENDING' THEN
        RAISE EXCEPTION 'Tax request lines are mutable only while the request is PENDING'
            USING ERRCODE = '55000';
    END IF;
    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.validate_tax_result_ready()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    line_count integer;
    taxable_total numeric(20,6);
    exempt_total numeric(20,6);
    tax_total numeric(20,6);
    bad_line_count integer;
BEGIN
    IF TG_OP = 'UPDATE' AND (
        OLD.tenant_id IS DISTINCT FROM NEW.tenant_id OR
        OLD.tax_calculation_request_id IS DISTINCT FROM NEW.tax_calculation_request_id OR
        OLD.currency_code IS DISTINCT FROM NEW.currency_code OR
        OLD.result_version IS DISTINCT FROM NEW.result_version
    ) THEN
        RAISE EXCEPTION 'Tax result request, version, tenant, and currency are immutable'
            USING ERRCODE = '23514';
    END IF;

    IF NEW.status IN ('FINALIZED','COMMITTED') THEN
        SELECT count(*), COALESCE(sum(taxable_amount), 0), COALESCE(sum(exempt_amount), 0),
               COALESCE(sum(tax_amount), 0), count(*) FILTER (WHERE tenant_id <> NEW.tenant_id)
          INTO line_count, taxable_total, exempt_total, tax_total, bad_line_count
          FROM doms.tax_calculation_result_lines
         WHERE tax_calculation_result_id = NEW.id;
        IF line_count = 0 OR bad_line_count <> 0 OR taxable_total <> NEW.taxable_amount
           OR exempt_total <> NEW.exempt_amount OR tax_total <> NEW.tax_amount THEN
            RAISE EXCEPTION 'Final tax result totals must exactly equal its result-line totals'
                USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.guard_tax_result_line_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    parent_status varchar(20);
    parent_id uuid;
BEGIN
    parent_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.tax_calculation_result_id ELSE NEW.tax_calculation_result_id END;
    SELECT status INTO parent_status
      FROM doms.tax_calculation_results
     WHERE id = parent_id
     FOR UPDATE;
    IF parent_status <> 'DRAFT' THEN
        RAISE EXCEPTION 'Tax result lines are mutable only while the result is DRAFT'
            USING ERRCODE = '55000';
    END IF;
    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.normalize_reconciliation_item()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    run_row doms.payment_reconciliation_runs%ROWTYPE;
BEGIN
    SELECT * INTO run_row
      FROM doms.payment_reconciliation_runs
     WHERE id = NEW.reconciliation_run_id
     FOR UPDATE;
    IF NOT FOUND OR run_row.tenant_id <> NEW.tenant_id
       OR (run_row.currency_code IS NOT NULL AND run_row.currency_code <> NEW.currency_code) THEN
        RAISE EXCEPTION 'Reconciliation item tenant/currency must match its run'
            USING ERRCODE = '23514';
    END IF;
    NEW.difference_amount := NEW.external_amount - NEW.internal_amount;
    IF NEW.match_status = 'MATCHED' AND NEW.difference_amount <> 0 THEN
        RAISE EXCEPTION 'Exact MATCHED reconciliation item must have zero difference'
            USING ERRCODE = '23514';
    END IF;
    IF NEW.match_status = 'MATCHED_WITH_TOLERANCE'
       AND abs(NEW.difference_amount) > NEW.tolerance_amount THEN
        RAISE EXCEPTION 'Tolerance match exceeds its tolerance amount'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_payment_intent_initial_status ON doms.payment_intents;
CREATE TRIGGER trg_payment_intent_initial_status
    BEFORE INSERT ON doms.payment_intents
    FOR EACH ROW EXECUTE PROCEDURE doms.enforce_payment_initial_status('REQUIRES_PAYMENT_METHOD');

DROP TRIGGER IF EXISTS trg_payment_intent_status_transition ON doms.payment_intents;
CREATE TRIGGER trg_payment_intent_status_transition
    BEFORE UPDATE OF status ON doms.payment_intents
    FOR EACH ROW EXECUTE PROCEDURE doms.enforce_payment_status_transition('INTENT');

DROP TRIGGER IF EXISTS trg_payment_intent_ready ON doms.payment_intents;
CREATE TRIGGER trg_payment_intent_ready
    BEFORE INSERT OR UPDATE ON doms.payment_intents
    FOR EACH ROW EXECUTE PROCEDURE doms.validate_payment_intent_ready();

DROP TRIGGER IF EXISTS trg_payment_intent_line_guard ON doms.payment_intent_lines;
CREATE TRIGGER trg_payment_intent_line_guard
    BEFORE INSERT OR UPDATE OR DELETE ON doms.payment_intent_lines
    FOR EACH ROW EXECUTE PROCEDURE doms.guard_payment_intent_line_mutation();

DROP TRIGGER IF EXISTS trg_payment_authorization_initial_status ON doms.payment_authorizations;
CREATE TRIGGER trg_payment_authorization_initial_status
    BEFORE INSERT ON doms.payment_authorizations
    FOR EACH ROW EXECUTE PROCEDURE doms.enforce_payment_initial_status('PENDING');

DROP TRIGGER IF EXISTS trg_payment_authorization_status_transition ON doms.payment_authorizations;
CREATE TRIGGER trg_payment_authorization_status_transition
    BEFORE UPDATE OF status ON doms.payment_authorizations
    FOR EACH ROW EXECUTE PROCEDURE doms.enforce_payment_status_transition('AUTHORIZATION');

DROP TRIGGER IF EXISTS trg_payment_authorization_limit ON doms.payment_authorizations;
CREATE TRIGGER trg_payment_authorization_limit
    BEFORE INSERT OR UPDATE ON doms.payment_authorizations
    FOR EACH ROW EXECUTE PROCEDURE doms.enforce_payment_authorization_limit();

DROP TRIGGER IF EXISTS trg_payment_capture_initial_status ON doms.payment_captures;
CREATE TRIGGER trg_payment_capture_initial_status
    BEFORE INSERT ON doms.payment_captures
    FOR EACH ROW EXECUTE PROCEDURE doms.enforce_payment_initial_status('PENDING');

DROP TRIGGER IF EXISTS trg_payment_capture_status_transition ON doms.payment_captures;
CREATE TRIGGER trg_payment_capture_status_transition
    BEFORE UPDATE OF status ON doms.payment_captures
    FOR EACH ROW EXECUTE PROCEDURE doms.enforce_payment_status_transition('OPERATION');

DROP TRIGGER IF EXISTS trg_payment_capture_limit ON doms.payment_captures;
CREATE TRIGGER trg_payment_capture_limit
    BEFORE INSERT OR UPDATE ON doms.payment_captures
    FOR EACH ROW EXECUTE PROCEDURE doms.enforce_payment_capture_limit();

DROP TRIGGER IF EXISTS trg_payment_void_initial_status ON doms.payment_voids;
CREATE TRIGGER trg_payment_void_initial_status
    BEFORE INSERT ON doms.payment_voids
    FOR EACH ROW EXECUTE PROCEDURE doms.enforce_payment_initial_status('PENDING');

DROP TRIGGER IF EXISTS trg_payment_void_status_transition ON doms.payment_voids;
CREATE TRIGGER trg_payment_void_status_transition
    BEFORE UPDATE OF status ON doms.payment_voids
    FOR EACH ROW EXECUTE PROCEDURE doms.enforce_payment_status_transition('OPERATION');

DROP TRIGGER IF EXISTS trg_payment_void_limit ON doms.payment_voids;
CREATE TRIGGER trg_payment_void_limit
    BEFORE INSERT OR UPDATE ON doms.payment_voids
    FOR EACH ROW EXECUTE PROCEDURE doms.enforce_payment_void_limit();

DROP TRIGGER IF EXISTS trg_payment_refund_initial_status ON doms.payment_refunds;
CREATE TRIGGER trg_payment_refund_initial_status
    BEFORE INSERT ON doms.payment_refunds
    FOR EACH ROW EXECUTE PROCEDURE doms.enforce_payment_initial_status('PENDING');

DROP TRIGGER IF EXISTS trg_payment_refund_status_transition ON doms.payment_refunds;
CREATE TRIGGER trg_payment_refund_status_transition
    BEFORE UPDATE OF status ON doms.payment_refunds
    FOR EACH ROW EXECUTE PROCEDURE doms.enforce_payment_status_transition('OPERATION');

DROP TRIGGER IF EXISTS trg_payment_refund_limit ON doms.payment_refunds;
CREATE TRIGGER trg_payment_refund_limit
    BEFORE INSERT OR UPDATE ON doms.payment_refunds
    FOR EACH ROW EXECUTE PROCEDURE doms.enforce_payment_refund_limit();

DROP TRIGGER IF EXISTS trg_payment_refund_request_initial_status ON doms.payment_refund_requests;
CREATE TRIGGER trg_payment_refund_request_initial_status
    BEFORE INSERT ON doms.payment_refund_requests
    FOR EACH ROW EXECUTE PROCEDURE doms.enforce_payment_initial_status('REQUESTED');

DROP TRIGGER IF EXISTS trg_payment_refund_request_integrity ON doms.payment_refund_requests;
CREATE TRIGGER trg_payment_refund_request_integrity
    BEFORE INSERT OR UPDATE ON doms.payment_refund_requests
    FOR EACH ROW EXECUTE PROCEDURE doms.validate_payment_refund_request();

DROP TRIGGER IF EXISTS trg_payment_refund_request_status_transition ON doms.payment_refund_requests;
CREATE TRIGGER trg_payment_refund_request_status_transition
    BEFORE UPDATE OF status ON doms.payment_refund_requests
    FOR EACH ROW EXECUTE PROCEDURE doms.enforce_payment_status_transition('REFUND_REQUEST');

DROP TRIGGER IF EXISTS trg_payment_dispute_status_transition ON doms.payment_disputes;
CREATE TRIGGER trg_payment_dispute_status_transition
    BEFORE UPDATE OF status ON doms.payment_disputes
    FOR EACH ROW EXECUTE PROCEDURE doms.enforce_payment_status_transition('DISPUTE');

DROP TRIGGER IF EXISTS trg_payment_allocation_limit ON doms.payment_allocations;
CREATE TRIGGER trg_payment_allocation_limit
    BEFORE INSERT ON doms.payment_allocations
    FOR EACH ROW EXECUTE PROCEDURE doms.enforce_payment_allocation_limit();

DROP TRIGGER IF EXISTS trg_payment_refund_allocation_limit ON doms.payment_refund_allocations;
CREATE TRIGGER trg_payment_refund_allocation_limit
    BEFORE INSERT ON doms.payment_refund_allocations
    FOR EACH ROW EXECUTE PROCEDURE doms.enforce_payment_refund_allocation_limit();

DROP TRIGGER IF EXISTS trg_gift_card_ledger_apply ON doms.gift_card_ledger_entries;
CREATE TRIGGER trg_gift_card_ledger_apply
    BEFORE INSERT ON doms.gift_card_ledger_entries
    FOR EACH ROW EXECUTE PROCEDURE doms.apply_gift_card_ledger_entry();

DROP TRIGGER IF EXISTS trg_store_credit_ledger_apply ON doms.store_credit_ledger_entries;
CREATE TRIGGER trg_store_credit_ledger_apply
    BEFORE INSERT ON doms.store_credit_ledger_entries
    FOR EACH ROW EXECUTE PROCEDURE doms.apply_store_credit_ledger_entry();

DROP TRIGGER IF EXISTS trg_tax_request_ready ON doms.tax_calculation_requests;
CREATE TRIGGER trg_tax_request_ready
    BEFORE INSERT OR UPDATE ON doms.tax_calculation_requests
    FOR EACH ROW EXECUTE PROCEDURE doms.validate_tax_request_ready();

DROP TRIGGER IF EXISTS trg_tax_request_line_guard ON doms.tax_calculation_request_lines;
CREATE TRIGGER trg_tax_request_line_guard
    BEFORE INSERT OR UPDATE OR DELETE ON doms.tax_calculation_request_lines
    FOR EACH ROW EXECUTE PROCEDURE doms.guard_tax_request_line_mutation();

DROP TRIGGER IF EXISTS trg_tax_result_ready ON doms.tax_calculation_results;
CREATE TRIGGER trg_tax_result_ready
    BEFORE INSERT OR UPDATE ON doms.tax_calculation_results
    FOR EACH ROW EXECUTE PROCEDURE doms.validate_tax_result_ready();

DROP TRIGGER IF EXISTS trg_tax_result_line_guard ON doms.tax_calculation_result_lines;
CREATE TRIGGER trg_tax_result_line_guard
    BEFORE INSERT OR UPDATE OR DELETE ON doms.tax_calculation_result_lines
    FOR EACH ROW EXECUTE PROCEDURE doms.guard_tax_result_line_mutation();

DROP TRIGGER IF EXISTS trg_payment_reconciliation_item_normalize ON doms.payment_reconciliation_items;
CREATE TRIGGER trg_payment_reconciliation_item_normalize
    BEFORE INSERT OR UPDATE ON doms.payment_reconciliation_items
    FOR EACH ROW EXECUTE PROCEDURE doms.normalize_reconciliation_item();

DO $block$
DECLARE
    spec record;
    argument_sql text;
BEGIN
    FOR spec IN
        SELECT * FROM (VALUES
            ('payment_gateway_accounts', ARRAY[
                'sales_channel_id','sales_channels','organization_id','organizations'
            ]::text[]),
            ('payment_method_vault_references', ARRAY[
                'gateway_account_id','payment_gateway_accounts','customer_id','customers'
            ]::text[]),
            ('payment_intents', ARRAY[
                'sales_order_id','sales_orders','customer_id','customers',
                'sales_channel_id','sales_channels','gateway_account_id','payment_gateway_accounts',
                'payment_method_vault_id','payment_method_vault_references'
            ]::text[]),
            ('payment_intent_lines', ARRAY[
                'payment_intent_id','payment_intents','sales_order_line_id','sales_order_lines'
            ]::text[]),
            ('payment_authorizations', ARRAY[
                'payment_intent_id','payment_intents','gateway_account_id','payment_gateway_accounts',
                'payment_method_vault_id','payment_method_vault_references'
            ]::text[]),
            ('payment_captures', ARRAY[
                'payment_authorization_id','payment_authorizations','payment_intent_id','payment_intents'
            ]::text[]),
            ('payment_voids', ARRAY['payment_authorization_id','payment_authorizations']::text[]),
            ('payment_refund_requests', ARRAY[
                'sales_order_id','sales_orders','payment_intent_id','payment_intents','customer_id','customers'
            ]::text[]),
            ('payment_refund_request_lines', ARRAY[
                'refund_request_id','payment_refund_requests','sales_order_line_id','sales_order_lines'
            ]::text[]),
            ('payment_refunds', ARRAY[
                'refund_request_id','payment_refund_requests','payment_capture_id','payment_captures',
                'payment_intent_id','payment_intents'
            ]::text[]),
            ('payment_allocations', ARRAY[
                'payment_capture_id','payment_captures','sales_order_id','sales_orders',
                'sales_order_line_id','sales_order_lines','reversal_of_id','payment_allocations'
            ]::text[]),
            ('payment_refund_allocations', ARRAY[
                'payment_refund_id','payment_refunds','refund_request_line_id','payment_refund_request_lines',
                'sales_order_id','sales_orders','sales_order_line_id','sales_order_lines'
            ]::text[]),
            ('payment_events', ARRAY[
                'payment_intent_id','payment_intents','payment_authorization_id','payment_authorizations',
                'payment_capture_id','payment_captures','payment_void_id','payment_voids',
                'payment_refund_id','payment_refunds'
            ]::text[]),
            ('payment_failures', ARRAY[
                'payment_intent_id','payment_intents','payment_authorization_id','payment_authorizations',
                'payment_capture_id','payment_captures','payment_void_id','payment_voids',
                'payment_refund_id','payment_refunds'
            ]::text[]),
            ('payment_disputes', ARRAY[
                'payment_capture_id','payment_captures','payment_intent_id','payment_intents',
                'sales_order_id','sales_orders','customer_id','customers'
            ]::text[]),
            ('payment_dispute_evidence', ARRAY[
                'payment_dispute_id','payment_disputes','file_id','files'
            ]::text[]),
            ('payment_dispute_events', ARRAY['payment_dispute_id','payment_disputes']::text[]),
            ('gift_card_programs', ARRAY['sales_channel_id','sales_channels']::text[]),
            ('gift_cards', ARRAY[
                'gift_card_program_id','gift_card_programs','owner_customer_id','customers',
                'purchaser_customer_id','customers'
            ]::text[]),
            ('gift_card_ledger_entries', ARRAY[
                'gift_card_id','gift_cards','sales_order_id','sales_orders',
                'payment_intent_id','payment_intents','payment_refund_id','payment_refunds',
                'reversal_of_id','gift_card_ledger_entries'
            ]::text[]),
            ('store_credit_accounts', ARRAY['customer_id','customers']::text[]),
            ('store_credit_ledger_entries', ARRAY[
                'store_credit_account_id','store_credit_accounts','sales_order_id','sales_orders',
                'payment_intent_id','payment_intents','payment_refund_id','payment_refunds',
                'reversal_of_id','store_credit_ledger_entries'
            ]::text[]),
            ('tax_registrations', ARRAY['organization_id','organizations']::text[]),
            ('tax_exemptions', ARRAY[
                'customer_id','customers','certificate_file_id','files'
            ]::text[]),
            ('tax_calculation_requests', ARRAY[
                'sales_order_id','sales_orders','customer_id','customers','sales_channel_id','sales_channels',
                'selling_organization_id','selling_organizations'
            ]::text[]),
            ('tax_calculation_request_lines', ARRAY[
                'tax_calculation_request_id','tax_calculation_requests','sales_order_line_id','sales_order_lines'
            ]::text[]),
            ('tax_calculation_results', ARRAY[
                'tax_calculation_request_id','tax_calculation_requests'
            ]::text[]),
            ('tax_calculation_result_lines', ARRAY[
                'tax_calculation_result_id','tax_calculation_results',
                'tax_calculation_request_line_id','tax_calculation_request_lines',
                'sales_order_line_id','sales_order_lines','exemption_id','tax_exemptions'
            ]::text[]),
            ('tax_adjustments', ARRAY[
                'tax_calculation_result_id','tax_calculation_results',
                'tax_calculation_result_line_id','tax_calculation_result_lines',
                'sales_order_id','sales_orders','sales_order_line_id','sales_order_lines'
            ]::text[]),
            ('fraud_rule_versions', ARRAY['fraud_rule_id','fraud_rules']::text[]),
            ('risk_assessments', ARRAY[
                'customer_id','customers','sales_order_id','sales_orders','payment_intent_id','payment_intents',
                'payment_refund_request_id','payment_refund_requests','payment_dispute_id','payment_disputes',
                'sales_channel_id','sales_channels'
            ]::text[]),
            ('risk_signals', ARRAY['risk_assessment_id','risk_assessments']::text[]),
            ('risk_rule_evaluations', ARRAY[
                'risk_assessment_id','risk_assessments','fraud_rule_version_id','fraud_rule_versions'
            ]::text[]),
            ('risk_decisions', ARRAY['risk_assessment_id','risk_assessments']::text[]),
            ('fraud_cases', ARRAY[
                'customer_id','customers','sales_order_id','sales_orders','payment_intent_id','payment_intents',
                'payment_dispute_id','payment_disputes','primary_risk_assessment_id','risk_assessments'
            ]::text[]),
            ('fraud_case_events', ARRAY['fraud_case_id','fraud_cases']::text[]),
            ('payment_settlement_batches', ARRAY[
                'gateway_account_id','payment_gateway_accounts','statement_file_id','files'
            ]::text[]),
            ('payment_settlement_entries', ARRAY[
                'settlement_batch_id','payment_settlement_batches','payment_capture_id','payment_captures',
                'payment_refund_id','payment_refunds','payment_dispute_id','payment_disputes'
            ]::text[]),
            ('payment_reconciliation_runs', ARRAY[
                'gateway_account_id','payment_gateway_accounts'
            ]::text[]),
            ('payment_reconciliation_items', ARRAY[
                'reconciliation_run_id','payment_reconciliation_runs',
                'settlement_entry_id','payment_settlement_entries',
                'payment_authorization_id','payment_authorizations','payment_capture_id','payment_captures',
                'payment_refund_id','payment_refunds','payment_dispute_id','payment_disputes'
            ]::text[]),
            ('payment_reconciliation_exceptions', ARRAY[
                'reconciliation_run_id','payment_reconciliation_runs',
                'reconciliation_item_id','payment_reconciliation_items'
            ]::text[])
        ) AS configured(table_name, arguments)
    LOOP
        SELECT string_agg(quote_literal(argument), ', ' ORDER BY ordinal_position)
          INTO argument_sql
          FROM unnest(spec.arguments) WITH ORDINALITY AS expanded(argument, ordinal_position);
        EXECUTE format('DROP TRIGGER IF EXISTS trg_tenant_references ON doms.%I', spec.table_name);
        EXECUTE format(
            'CREATE TRIGGER trg_tenant_references BEFORE INSERT OR UPDATE ON doms.%I '
            'FOR EACH ROW EXECUTE PROCEDURE doms.validate_tenant_references(%s)',
            spec.table_name,
            argument_sql
        );
    END LOOP;
END;
$block$;

DO $block$
DECLARE
    table_name text;
BEGIN
    FOREACH table_name IN ARRAY ARRAY[
        'payment_events','payment_failures','payment_dispute_events',
        'payment_allocations','payment_refund_allocations',
        'gift_card_ledger_entries','store_credit_ledger_entries',
        'risk_signals','risk_rule_evaluations','risk_decisions','fraud_case_events',
        'payment_settlement_entries'
    ]
    LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS trg_append_only ON doms.%I', table_name);
        EXECUTE format(
            'CREATE TRIGGER trg_append_only BEFORE UPDATE OR DELETE ON doms.%I '
            'FOR EACH ROW EXECUTE PROCEDURE doms.prevent_append_only_mutation()',
            table_name
        );
    END LOOP;
END;
$block$;

DO $block$
DECLARE
    table_name text;
BEGIN
    FOREACH table_name IN ARRAY ARRAY[
        'payment_gateway_accounts','payment_method_vault_references',
        'payment_intents','payment_intent_lines','payment_authorizations','payment_captures',
        'payment_voids','payment_refund_requests','payment_refund_request_lines','payment_refunds',
        'payment_disputes','payment_dispute_evidence','gift_card_programs','gift_cards',
        'store_credit_accounts','tax_registrations','tax_exemptions','tax_calculation_requests',
        'tax_calculation_request_lines','tax_calculation_results','tax_calculation_result_lines',
        'tax_adjustments','fraud_rules','fraud_rule_versions','risk_assessments','fraud_cases',
        'payment_settlement_batches','payment_reconciliation_runs','payment_reconciliation_items',
        'payment_reconciliation_exceptions'
    ]
    LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS trg_touch_row ON doms.%I', table_name);
        EXECUTE format(
            'CREATE TRIGGER trg_touch_row BEFORE UPDATE ON doms.%I '
            'FOR EACH ROW EXECUTE PROCEDURE doms.touch_row()',
            table_name
        );
    END LOOP;
END;
$block$;

COMMENT ON TABLE doms.gift_card_ledger_entries IS
    'Append-only gift-card balance ledger. Balance is serialized by locking the gift-card row and calculated by the database trigger.';
COMMENT ON TABLE doms.store_credit_ledger_entries IS
    'Append-only customer store-credit ledger. Corrections require an explicit reversal entry.';
COMMENT ON TABLE doms.payment_events IS
    'Append-only normalized payment event log; payload summaries must be minimized and secret-free.';
COMMENT ON TABLE doms.payment_failures IS
    'Append-only masked failure diagnostics. Raw gateway requests, responses, and credentials are prohibited.';
COMMENT ON TABLE doms.tax_calculation_results IS
    'Versioned tax calculation outcome. FINALIZED/COMMITTED totals must equal the sum of result lines.';
COMMENT ON TABLE doms.risk_decisions IS
    'Append-only risk decisions. At most one decision per assessment may be marked final.';
