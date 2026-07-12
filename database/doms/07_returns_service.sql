-- DOMS enterprise OMS schema - returns, RMA, reverse logistics, exchanges,
-- replacements, warranties, and customer service.
-- PostgreSQL 11 compatible. Applied after 06_fulfillment_delivery.sql.

-- Upstream objects without a declared (tenant_id, id) constraint receive a
-- non-partial unique index so tenant-qualified foreign keys can reject a
-- cross-tenant identifier at the database boundary.
CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_return_upstream_address
    ON doms.order_address_snapshots (tenant_id, id);
CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_return_upstream_refund_request
    ON doms.payment_refund_requests (tenant_id, id);
CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_return_upstream_refund
    ON doms.payment_refunds (tenant_id, id);
CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_return_upstream_files
    ON doms.files (tenant_id, id);
CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_return_upstream_carrier_service
    ON doms.carrier_services (tenant_id, id);

-- -----------------------------------------------------------------------------
-- Versioned return policies and eligibility evidence
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS doms.return_policies (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    policy_code varchar(80) NOT NULL,
    policy_name varchar(200) NOT NULL,
    sales_channel_id uuid,
    customer_id uuid,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    current_version_id uuid,
    description text,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    updated_by uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, policy_code),
    CONSTRAINT fk_doms_return_policy_channel
        FOREIGN KEY (tenant_id, sales_channel_id)
        REFERENCES doms.sales_channels(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_return_policy_customer
        FOREIGN KEY (tenant_id, customer_id)
        REFERENCES doms.customers(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_return_policy_code CHECK (btrim(policy_code) <> ''),
    CONSTRAINT ck_doms_return_policy_status CHECK (
        status IN ('DRAFT','ACTIVE','SUSPENDED','RETIRED')
    )
);

CREATE TABLE IF NOT EXISTS doms.return_policy_versions (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    return_policy_id uuid NOT NULL,
    version_no integer NOT NULL,
    version_status varchar(20) NOT NULL DEFAULT 'DRAFT',
    effective_from timestamptz,
    effective_to timestamptz,
    return_window_days integer NOT NULL DEFAULT 30,
    window_start_event varchar(30) NOT NULL DEFAULT 'DELIVERED',
    require_rma boolean NOT NULL DEFAULT true,
    require_receipt boolean NOT NULL DEFAULT false,
    allow_partial_return boolean NOT NULL DEFAULT true,
    allow_exchange boolean NOT NULL DEFAULT true,
    allow_replacement boolean NOT NULL DEFAULT true,
    allow_keep_item_refund boolean NOT NULL DEFAULT false,
    refund_shipping_mode varchar(30) NOT NULL DEFAULT 'POLICY',
    restocking_fee_percent numeric(9,6) NOT NULL DEFAULT 0,
    policy_config jsonb NOT NULL DEFAULT '{}'::jsonb,
    checksum_sha256 char(64),
    published_by uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    published_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, return_policy_id, version_no),
    CONSTRAINT fk_doms_return_policy_version_header
        FOREIGN KEY (tenant_id, return_policy_id)
        REFERENCES doms.return_policies(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_return_policy_version_no CHECK (version_no > 0),
    CONSTRAINT ck_doms_return_policy_version_status CHECK (
        version_status IN ('DRAFT','PUBLISHED','ACTIVE','SUPERSEDED','RETIRED')
    ),
    CONSTRAINT ck_doms_return_policy_version_window CHECK (
        return_window_days >= 0 AND restocking_fee_percent BETWEEN 0 AND 100
    ),
    CONSTRAINT ck_doms_return_policy_version_start CHECK (
        window_start_event IN ('SHIPPED','DELIVERED','ORDERED','FULFILLED')
    ),
    CONSTRAINT ck_doms_return_policy_version_shipping CHECK (
        refund_shipping_mode IN ('NEVER','ORIGINAL_ONLY','RETURN_ONLY','BOTH','POLICY')
    ),
    CONSTRAINT ck_doms_return_policy_version_dates CHECK (
        effective_to IS NULL OR effective_from IS NULL OR effective_to > effective_from
    ),
    CONSTRAINT ck_doms_return_policy_version_publish CHECK (
        version_status = 'DRAFT' OR (published_by IS NOT NULL AND published_at IS NOT NULL)
    ),
    CONSTRAINT ck_doms_return_policy_version_checksum CHECK (
        checksum_sha256 IS NULL OR checksum_sha256 ~ '^[0-9A-Fa-f]{64}$'
    ),
    CONSTRAINT ck_doms_return_policy_version_json CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(policy_config)
    )
);

ALTER TABLE doms.return_policies
    DROP CONSTRAINT IF EXISTS fk_doms_return_policy_current_version;
ALTER TABLE doms.return_policies
    ADD CONSTRAINT fk_doms_return_policy_current_version
    FOREIGN KEY (tenant_id, current_version_id)
    REFERENCES doms.return_policy_versions(tenant_id, id) ON DELETE RESTRICT;

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_return_policy_active_version
    ON doms.return_policy_versions (tenant_id, return_policy_id)
    WHERE version_status = 'ACTIVE';

CREATE TABLE IF NOT EXISTS doms.return_policy_rules (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    return_policy_version_id uuid NOT NULL,
    rule_code varchar(80) NOT NULL,
    rule_name varchar(200) NOT NULL,
    sequence_no integer NOT NULL,
    rule_type varchar(40) NOT NULL,
    condition_config jsonb NOT NULL DEFAULT '{}'::jsonb,
    outcome_config jsonb NOT NULL DEFAULT '{}'::jsonb,
    stop_processing boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, return_policy_version_id, rule_code),
    UNIQUE (tenant_id, return_policy_version_id, sequence_no),
    CONSTRAINT fk_doms_return_policy_rule_version
        FOREIGN KEY (tenant_id, return_policy_version_id)
        REFERENCES doms.return_policy_versions(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_return_policy_rule_values CHECK (
        btrim(rule_code) <> '' AND sequence_no > 0
    ),
    CONSTRAINT ck_doms_return_policy_rule_type CHECK (rule_type IN (
        'WINDOW','ITEM','CATEGORY','CHANNEL','CUSTOMER','REASON','CONDITION','QUANTITY',
        'REFUND','RESTOCKING_FEE','SHIPPING','EXCHANGE','REPLACEMENT','WARRANTY','CUSTOM'
    )),
    CONSTRAINT ck_doms_return_policy_rule_json CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(condition_config) AND
        NOT doms.jsonb_contains_forbidden_secret_key(outcome_config)
    )
);

CREATE TABLE IF NOT EXISTS doms.return_eligibility_checks (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    check_no varchar(100) NOT NULL,
    sales_order_id uuid NOT NULL,
    customer_id uuid NOT NULL,
    return_policy_version_id uuid NOT NULL,
    check_status varchar(20) NOT NULL DEFAULT 'PENDING',
    idempotency_key varchar(200) NOT NULL,
    requested_at timestamptz NOT NULL DEFAULT now(),
    completed_at timestamptz,
    request_context jsonb NOT NULL DEFAULT '{}'::jsonb,
    requested_by uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, check_no),
    UNIQUE (tenant_id, sales_order_id, idempotency_key),
    CONSTRAINT fk_doms_return_eligibility_order
        FOREIGN KEY (tenant_id, sales_order_id)
        REFERENCES doms.sales_orders(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_return_eligibility_customer
        FOREIGN KEY (tenant_id, customer_id)
        REFERENCES doms.customers(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_return_eligibility_policy
        FOREIGN KEY (tenant_id, return_policy_version_id)
        REFERENCES doms.return_policy_versions(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_return_eligibility_values CHECK (
        btrim(check_no) <> '' AND btrim(idempotency_key) <> ''
    ),
    CONSTRAINT ck_doms_return_eligibility_status CHECK (
        check_status IN ('PENDING','RUNNING','ELIGIBLE','PARTIAL','INELIGIBLE','FAILED','EXPIRED')
    ),
    CONSTRAINT ck_doms_return_eligibility_dates CHECK (
        completed_at IS NULL OR completed_at >= requested_at
    ),
    CONSTRAINT ck_doms_return_eligibility_context CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(request_context)
    )
);

CREATE TABLE IF NOT EXISTS doms.return_eligibility_check_lines (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    return_eligibility_check_id uuid NOT NULL,
    line_no integer NOT NULL,
    sales_order_line_id uuid NOT NULL,
    shipment_line_id uuid NOT NULL,
    package_item_id uuid NOT NULL,
    item_id uuid NOT NULL,
    requested_quantity numeric(24,8) NOT NULL,
    uom_code varchar(20) NOT NULL REFERENCES doms.units_of_measure(uom_code),
    reason_code varchar(80) NOT NULL,
    condition_code varchar(80),
    line_context jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, return_eligibility_check_id, line_no),
    CONSTRAINT fk_doms_return_eligibility_line_header
        FOREIGN KEY (tenant_id, return_eligibility_check_id)
        REFERENCES doms.return_eligibility_checks(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_return_eligibility_line_order_line
        FOREIGN KEY (tenant_id, sales_order_line_id)
        REFERENCES doms.sales_order_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_return_eligibility_line_shipment_line
        FOREIGN KEY (tenant_id, shipment_line_id)
        REFERENCES doms.shipment_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_return_eligibility_line_package_item
        FOREIGN KEY (tenant_id, package_item_id)
        REFERENCES doms.package_items(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_return_eligibility_line_item
        FOREIGN KEY (tenant_id, item_id)
        REFERENCES doms.items(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_return_eligibility_line_values CHECK (
        line_no > 0 AND requested_quantity > 0 AND btrim(reason_code) <> ''
    ),
    CONSTRAINT ck_doms_return_eligibility_line_json CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(line_context)
    )
);

CREATE TABLE IF NOT EXISTS doms.return_eligibility_results (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    return_eligibility_check_line_id uuid NOT NULL,
    return_policy_rule_id uuid,
    result_sequence integer NOT NULL,
    result_code varchar(40) NOT NULL,
    eligible_quantity numeric(24,8) NOT NULL DEFAULT 0,
    maximum_refund_amount numeric(24,6) NOT NULL DEFAULT 0,
    currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    is_final boolean NOT NULL DEFAULT false,
    reason_code varchar(100),
    result_data jsonb NOT NULL DEFAULT '{}'::jsonb,
    evaluated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, return_eligibility_check_line_id, result_sequence),
    CONSTRAINT fk_doms_return_eligibility_result_line
        FOREIGN KEY (tenant_id, return_eligibility_check_line_id)
        REFERENCES doms.return_eligibility_check_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_return_eligibility_result_rule
        FOREIGN KEY (tenant_id, return_policy_rule_id)
        REFERENCES doms.return_policy_rules(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_return_eligibility_result_values CHECK (
        result_sequence > 0 AND eligible_quantity >= 0 AND maximum_refund_amount >= 0
    ),
    CONSTRAINT ck_doms_return_eligibility_result_code CHECK (
        result_code IN ('ELIGIBLE','PARTIAL','INELIGIBLE','REQUIRES_REVIEW','EXCEPTION')
    ),
    CONSTRAINT ck_doms_return_eligibility_result_json CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(result_data)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_return_eligibility_final
    ON doms.return_eligibility_results (tenant_id, return_eligibility_check_line_id)
    WHERE is_final;

-- -----------------------------------------------------------------------------
-- Return requests, RMA authorization, and exception evidence
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS doms.return_requests (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    return_request_no varchar(100) NOT NULL,
    sales_order_id uuid NOT NULL,
    customer_id uuid NOT NULL,
    return_policy_version_id uuid NOT NULL,
    return_eligibility_check_id uuid,
    return_method varchar(30) NOT NULL DEFAULT 'SHIP',
    return_status varchar(30) NOT NULL DEFAULT 'REQUESTED',
    requested_pickup_address_snapshot_id uuid,
    contact_name_encrypted text,
    contact_name_masked varchar(200),
    contact_email_encrypted text,
    contact_email_hash char(64),
    contact_email_masked varchar(320),
    contact_phone_encrypted text,
    contact_phone_hash char(64),
    contact_phone_masked varchar(50),
    idempotency_key varchar(200) NOT NULL,
    requested_at timestamptz NOT NULL DEFAULT now(),
    approved_at timestamptz,
    closed_at timestamptz,
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    requested_by uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, return_request_no),
    UNIQUE (tenant_id, sales_order_id, idempotency_key),
    CONSTRAINT fk_doms_return_request_order
        FOREIGN KEY (tenant_id, sales_order_id)
        REFERENCES doms.sales_orders(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_return_request_customer
        FOREIGN KEY (tenant_id, customer_id)
        REFERENCES doms.customers(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_return_request_policy
        FOREIGN KEY (tenant_id, return_policy_version_id)
        REFERENCES doms.return_policy_versions(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_return_request_eligibility
        FOREIGN KEY (tenant_id, return_eligibility_check_id)
        REFERENCES doms.return_eligibility_checks(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_return_request_pickup_address
        FOREIGN KEY (tenant_id, requested_pickup_address_snapshot_id)
        REFERENCES doms.order_address_snapshots(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_return_request_values CHECK (
        btrim(return_request_no) <> '' AND btrim(idempotency_key) <> ''
    ),
    CONSTRAINT ck_doms_return_request_method CHECK (
        return_method IN ('SHIP','PICKUP','STORE','KEEP_ITEM','DIGITAL','SERVICE')
    ),
    CONSTRAINT ck_doms_return_request_status CHECK (return_status IN (
        'REQUESTED','ELIGIBILITY_REVIEW','APPROVAL_PENDING','APPROVED','PARTIALLY_AUTHORIZED',
        'AUTHORIZED','IN_TRANSIT','PARTIALLY_RECEIVED','RECEIVED','INSPECTING',
        'DISPOSITIONED','REFUND_PENDING','PARTIALLY_REFUNDED','REFUNDED','EXCHANGED',
        'REPLACED','REJECTED','CANCELLED','EXPIRED','CLOSED'
    )),
    CONSTRAINT ck_doms_return_request_dates CHECK (
        (approved_at IS NULL OR approved_at >= requested_at) AND
        (closed_at IS NULL OR closed_at >= requested_at)
    ),
    CONSTRAINT ck_doms_return_request_hashes CHECK (
        (contact_email_hash IS NULL OR contact_email_hash ~ '^[0-9A-Fa-f]{64}$') AND
        (contact_phone_hash IS NULL OR contact_phone_hash ~ '^[0-9A-Fa-f]{64}$')
    ),
    CONSTRAINT ck_doms_return_request_json CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(attributes)
    )
);

CREATE TABLE IF NOT EXISTS doms.return_request_lines (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    return_request_id uuid NOT NULL,
    line_no integer NOT NULL,
    return_eligibility_result_id uuid,
    sales_order_line_id uuid NOT NULL,
    shipment_line_id uuid NOT NULL,
    package_item_id uuid NOT NULL,
    item_id uuid NOT NULL,
    requested_quantity numeric(24,8) NOT NULL,
    eligible_quantity numeric(24,8) NOT NULL DEFAULT 0,
    authorized_quantity numeric(24,8) NOT NULL DEFAULT 0,
    received_quantity numeric(24,8) NOT NULL DEFAULT 0,
    inspected_quantity numeric(24,8) NOT NULL DEFAULT 0,
    dispositioned_quantity numeric(24,8) NOT NULL DEFAULT 0,
    refund_eligible_quantity numeric(24,8) NOT NULL DEFAULT 0,
    refunded_quantity numeric(24,8) NOT NULL DEFAULT 0,
    refund_eligible_amount numeric(24,6) NOT NULL DEFAULT 0,
    refunded_amount numeric(24,6) NOT NULL DEFAULT 0,
    currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    uom_code varchar(20) NOT NULL REFERENCES doms.units_of_measure(uom_code),
    reason_code varchar(80) NOT NULL,
    condition_code varchar(80),
    line_status varchar(30) NOT NULL DEFAULT 'REQUESTED',
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, return_request_id, line_no),
    CONSTRAINT fk_doms_return_request_line_header
        FOREIGN KEY (tenant_id, return_request_id)
        REFERENCES doms.return_requests(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_return_request_line_eligibility
        FOREIGN KEY (tenant_id, return_eligibility_result_id)
        REFERENCES doms.return_eligibility_results(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_return_request_line_order_line
        FOREIGN KEY (tenant_id, sales_order_line_id)
        REFERENCES doms.sales_order_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_return_request_line_shipment_line
        FOREIGN KEY (tenant_id, shipment_line_id)
        REFERENCES doms.shipment_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_return_request_line_package_item
        FOREIGN KEY (tenant_id, package_item_id)
        REFERENCES doms.package_items(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_return_request_line_item
        FOREIGN KEY (tenant_id, item_id)
        REFERENCES doms.items(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_return_request_line_values CHECK (
        line_no > 0 AND requested_quantity > 0 AND eligible_quantity >= 0 AND
        authorized_quantity >= 0 AND received_quantity >= 0 AND inspected_quantity >= 0 AND
        dispositioned_quantity >= 0 AND refund_eligible_quantity >= 0 AND
        refunded_quantity >= 0 AND refund_eligible_amount >= 0 AND refunded_amount >= 0 AND
        eligible_quantity <= requested_quantity AND authorized_quantity <= requested_quantity AND
        received_quantity <= authorized_quantity AND inspected_quantity <= received_quantity AND
        dispositioned_quantity <= inspected_quantity AND
        refund_eligible_quantity <= dispositioned_quantity AND
        refunded_quantity <= refund_eligible_quantity AND refunded_amount <= refund_eligible_amount
    ),
    CONSTRAINT ck_doms_return_request_line_status CHECK (line_status IN (
        'REQUESTED','ELIGIBLE','INELIGIBLE','REVIEW','AUTHORIZED','PARTIALLY_RECEIVED',
        'RECEIVED','INSPECTED','DISPOSITIONED','REFUND_PENDING','PARTIALLY_REFUNDED',
        'REFUNDED','EXCHANGED','REPLACED','REJECTED','CANCELLED','CLOSED'
    )),
    CONSTRAINT ck_doms_return_request_line_json CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(attributes)
    )
);

CREATE TABLE IF NOT EXISTS doms.return_request_status_events (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    return_request_id uuid NOT NULL,
    return_request_line_id uuid,
    event_sequence bigint NOT NULL,
    event_type varchar(40) NOT NULL,
    from_status varchar(30),
    to_status varchar(30) NOT NULL,
    quantity numeric(24,8) NOT NULL DEFAULT 0,
    idempotency_key varchar(200),
    reason_code varchar(100),
    detail_masked text,
    actor_user_id uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, return_request_id, event_sequence),
    CONSTRAINT fk_doms_return_request_event_header
        FOREIGN KEY (tenant_id, return_request_id)
        REFERENCES doms.return_requests(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_return_request_event_line
        FOREIGN KEY (tenant_id, return_request_line_id)
        REFERENCES doms.return_request_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_return_request_event_values CHECK (
        event_sequence > 0 AND quantity >= 0 AND btrim(event_type) <> ''
    ),
    CONSTRAINT ck_doms_return_request_event_json CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(metadata)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_return_request_event_idempotency
    ON doms.return_request_status_events (tenant_id, return_request_id, idempotency_key)
    WHERE idempotency_key IS NOT NULL;

CREATE TABLE IF NOT EXISTS doms.return_exceptions (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    return_request_id uuid NOT NULL,
    return_request_line_id uuid,
    exception_code varchar(100) NOT NULL,
    severity varchar(20) NOT NULL DEFAULT 'ERROR',
    exception_status varchar(20) NOT NULL DEFAULT 'OPEN',
    detail_masked text NOT NULL,
    resolution_masked text,
    raised_at timestamptz NOT NULL DEFAULT now(),
    resolved_at timestamptz,
    resolved_by uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    CONSTRAINT fk_doms_return_exception_header
        FOREIGN KEY (tenant_id, return_request_id)
        REFERENCES doms.return_requests(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_return_exception_line
        FOREIGN KEY (tenant_id, return_request_line_id)
        REFERENCES doms.return_request_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_return_exception_code CHECK (btrim(exception_code) <> ''),
    CONSTRAINT ck_doms_return_exception_severity CHECK (
        severity IN ('INFO','WARNING','ERROR','CRITICAL')
    ),
    CONSTRAINT ck_doms_return_exception_status CHECK (
        exception_status IN ('OPEN','ACKNOWLEDGED','RESOLVED','WAIVED','CANCELLED')
    ),
    CONSTRAINT ck_doms_return_exception_dates CHECK (
        resolved_at IS NULL OR resolved_at >= raised_at
    ),
    CONSTRAINT ck_doms_return_exception_json CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(metadata)
    )
);

CREATE TABLE IF NOT EXISTS doms.rma_authorizations (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    rma_no varchar(100) NOT NULL,
    return_request_id uuid NOT NULL,
    authorization_status varchar(30) NOT NULL DEFAULT 'DRAFT',
    authorized_at timestamptz,
    expires_at timestamptz NOT NULL,
    closed_at timestamptz,
    idempotency_key varchar(200) NOT NULL,
    authorization_note text,
    authorized_by uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, rma_no),
    UNIQUE (tenant_id, return_request_id, idempotency_key),
    CONSTRAINT fk_doms_rma_header_return
        FOREIGN KEY (tenant_id, return_request_id)
        REFERENCES doms.return_requests(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_rma_header_values CHECK (
        btrim(rma_no) <> '' AND btrim(idempotency_key) <> ''
    ),
    CONSTRAINT ck_doms_rma_header_status CHECK (authorization_status IN (
        'DRAFT','PENDING','AUTHORIZED','PARTIALLY_RECEIVED','RECEIVED','INSPECTED',
        'DISPOSITIONED','REFUND_PENDING','REFUNDED','REJECTED','CANCELLED','EXPIRED','CLOSED'
    )),
    CONSTRAINT ck_doms_rma_header_dates CHECK (
        expires_at > created_at AND
        (authorized_at IS NULL OR authorized_at >= created_at) AND
        (closed_at IS NULL OR closed_at >= COALESCE(authorized_at, created_at))
    ),
    CONSTRAINT ck_doms_rma_header_authorized CHECK (
        authorization_status NOT IN ('AUTHORIZED','PARTIALLY_RECEIVED','RECEIVED','INSPECTED',
            'DISPOSITIONED','REFUND_PENDING','REFUNDED','CLOSED') OR
        (authorized_at IS NOT NULL AND authorized_by IS NOT NULL)
    )
);

CREATE TABLE IF NOT EXISTS doms.rma_authorization_lines (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    rma_authorization_id uuid NOT NULL,
    return_request_line_id uuid NOT NULL,
    line_no integer NOT NULL,
    sales_order_line_id uuid NOT NULL,
    shipment_line_id uuid NOT NULL,
    package_item_id uuid NOT NULL,
    item_id uuid NOT NULL,
    authorized_quantity numeric(24,8) NOT NULL,
    received_quantity numeric(24,8) NOT NULL DEFAULT 0,
    inspected_quantity numeric(24,8) NOT NULL DEFAULT 0,
    dispositioned_quantity numeric(24,8) NOT NULL DEFAULT 0,
    refund_eligible_quantity numeric(24,8) NOT NULL DEFAULT 0,
    refunded_quantity numeric(24,8) NOT NULL DEFAULT 0,
    uom_code varchar(20) NOT NULL REFERENCES doms.units_of_measure(uom_code),
    line_status varchar(30) NOT NULL DEFAULT 'AUTHORIZED',
    override_approved_by uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    override_approved_at timestamptz,
    override_reason text,
    idempotency_key varchar(200) NOT NULL,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, rma_authorization_id, line_no),
    UNIQUE (tenant_id, return_request_line_id, rma_authorization_id),
    UNIQUE (tenant_id, rma_authorization_id, idempotency_key),
    CONSTRAINT fk_doms_rma_line_header
        FOREIGN KEY (tenant_id, rma_authorization_id)
        REFERENCES doms.rma_authorizations(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_rma_line_return_line
        FOREIGN KEY (tenant_id, return_request_line_id)
        REFERENCES doms.return_request_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_rma_line_order_line
        FOREIGN KEY (tenant_id, sales_order_line_id)
        REFERENCES doms.sales_order_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_rma_line_shipment_line
        FOREIGN KEY (tenant_id, shipment_line_id)
        REFERENCES doms.shipment_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_rma_line_package_item
        FOREIGN KEY (tenant_id, package_item_id)
        REFERENCES doms.package_items(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_rma_line_item
        FOREIGN KEY (tenant_id, item_id)
        REFERENCES doms.items(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_rma_line_values CHECK (
        line_no > 0 AND authorized_quantity > 0 AND received_quantity >= 0 AND
        inspected_quantity >= 0 AND dispositioned_quantity >= 0 AND
        refund_eligible_quantity >= 0 AND refunded_quantity >= 0 AND
        received_quantity <= authorized_quantity AND inspected_quantity <= received_quantity AND
        dispositioned_quantity <= inspected_quantity AND
        refund_eligible_quantity <= dispositioned_quantity AND
        refunded_quantity <= refund_eligible_quantity AND btrim(idempotency_key) <> ''
    ),
    CONSTRAINT ck_doms_rma_line_status CHECK (line_status IN (
        'AUTHORIZED','IN_TRANSIT','PARTIALLY_RECEIVED','RECEIVED','INSPECTED',
        'DISPOSITIONED','REFUND_PENDING','PARTIALLY_REFUNDED','REFUNDED',
        'REJECTED','CANCELLED','EXPIRED','CLOSED'
    )),
    CONSTRAINT ck_doms_rma_line_override CHECK (
        (override_approved_by IS NULL AND override_approved_at IS NULL AND override_reason IS NULL) OR
        (override_approved_by IS NOT NULL AND override_approved_at IS NOT NULL AND
            btrim(COALESCE(override_reason, '')) <> '')
    )
);

CREATE TABLE IF NOT EXISTS doms.rma_authorization_events (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    rma_authorization_id uuid NOT NULL,
    rma_authorization_line_id uuid,
    event_sequence bigint NOT NULL,
    event_type varchar(40) NOT NULL,
    from_status varchar(30),
    to_status varchar(30) NOT NULL,
    quantity numeric(24,8) NOT NULL DEFAULT 0,
    idempotency_key varchar(200),
    actor_user_id uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    detail_masked text,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, rma_authorization_id, event_sequence),
    CONSTRAINT fk_doms_rma_event_header
        FOREIGN KEY (tenant_id, rma_authorization_id)
        REFERENCES doms.rma_authorizations(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_rma_event_line
        FOREIGN KEY (tenant_id, rma_authorization_line_id)
        REFERENCES doms.rma_authorization_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_rma_event_values CHECK (
        event_sequence > 0 AND quantity >= 0 AND btrim(event_type) <> ''
    ),
    CONSTRAINT ck_doms_rma_event_json CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(metadata)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_rma_event_idempotency
    ON doms.rma_authorization_events (tenant_id, rma_authorization_id, idempotency_key)
    WHERE idempotency_key IS NOT NULL;

-- -----------------------------------------------------------------------------
-- Reverse logistics, receipt, inspection, and disposition facts
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS doms.return_labels (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    label_no varchar(120) NOT NULL,
    rma_authorization_id uuid NOT NULL,
    carrier_service_id uuid,
    label_file_id uuid,
    return_to_fulfillment_node_id uuid NOT NULL,
    label_status varchar(20) NOT NULL DEFAULT 'REQUESTED',
    provider_label_reference varchar(300),
    tracking_number_encrypted text,
    tracking_number_hash char(64),
    tracking_number_masked varchar(300),
    idempotency_key varchar(200) NOT NULL,
    generated_at timestamptz,
    voided_at timestamptz,
    label_summary jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, label_no),
    UNIQUE (tenant_id, rma_authorization_id, idempotency_key),
    CONSTRAINT fk_doms_return_label_rma
        FOREIGN KEY (tenant_id, rma_authorization_id)
        REFERENCES doms.rma_authorizations(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_return_label_carrier
        FOREIGN KEY (tenant_id, carrier_service_id)
        REFERENCES doms.carrier_services(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_return_label_file
        FOREIGN KEY (tenant_id, label_file_id)
        REFERENCES doms.files(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_return_label_node
        FOREIGN KEY (tenant_id, return_to_fulfillment_node_id)
        REFERENCES doms.fulfillment_nodes(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_return_label_values CHECK (
        btrim(label_no) <> '' AND btrim(idempotency_key) <> ''
    ),
    CONSTRAINT ck_doms_return_label_status CHECK (
        label_status IN ('REQUESTED','GENERATED','ACTIVE','USED','VOID','FAILED','EXPIRED')
    ),
    CONSTRAINT ck_doms_return_label_dates CHECK (
        (generated_at IS NULL OR generated_at >= created_at) AND
        (voided_at IS NULL OR voided_at >= COALESCE(generated_at, created_at))
    ),
    CONSTRAINT ck_doms_return_label_hash CHECK (
        tracking_number_hash IS NULL OR tracking_number_hash ~ '^[0-9A-Fa-f]{64}$'
    ),
    CONSTRAINT ck_doms_return_label_json CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(label_summary)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_return_label_provider
    ON doms.return_labels (tenant_id, provider_label_reference)
    WHERE provider_label_reference IS NOT NULL;

CREATE TABLE IF NOT EXISTS doms.return_shipments (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    return_shipment_no varchar(120) NOT NULL,
    rma_authorization_id uuid NOT NULL,
    return_label_id uuid,
    original_shipment_id uuid,
    original_tracking_number_id uuid,
    return_to_fulfillment_node_id uuid NOT NULL,
    carrier_service_id uuid,
    shipment_status varchar(30) NOT NULL DEFAULT 'PLANNED',
    tracking_number_encrypted text,
    tracking_number_hash char(64),
    tracking_number_masked varchar(300),
    external_shipment_reference varchar(300),
    idempotency_key varchar(200) NOT NULL,
    tendered_at timestamptz,
    shipped_at timestamptz,
    delivered_at timestamptz,
    received_at timestamptz,
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, return_shipment_no),
    UNIQUE (tenant_id, rma_authorization_id, idempotency_key),
    CONSTRAINT fk_doms_return_shipment_rma
        FOREIGN KEY (tenant_id, rma_authorization_id)
        REFERENCES doms.rma_authorizations(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_return_shipment_label
        FOREIGN KEY (tenant_id, return_label_id)
        REFERENCES doms.return_labels(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_return_shipment_original
        FOREIGN KEY (tenant_id, original_shipment_id)
        REFERENCES doms.shipments(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_return_shipment_original_tracking
        FOREIGN KEY (tenant_id, original_tracking_number_id)
        REFERENCES doms.shipment_tracking_numbers(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_return_shipment_node
        FOREIGN KEY (tenant_id, return_to_fulfillment_node_id)
        REFERENCES doms.fulfillment_nodes(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_return_shipment_carrier
        FOREIGN KEY (tenant_id, carrier_service_id)
        REFERENCES doms.carrier_services(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_return_shipment_values CHECK (
        btrim(return_shipment_no) <> '' AND btrim(idempotency_key) <> ''
    ),
    CONSTRAINT ck_doms_return_shipment_status CHECK (shipment_status IN (
        'PLANNED','LABELLED','TENDERED','SHIPPED','IN_TRANSIT','DELIVERED',
        'PARTIALLY_RECEIVED','RECEIVED','EXCEPTION','LOST','CANCELLED','CLOSED'
    )),
    CONSTRAINT ck_doms_return_shipment_dates CHECK (
        (tendered_at IS NULL OR tendered_at >= created_at) AND
        (shipped_at IS NULL OR shipped_at >= COALESCE(tendered_at, created_at)) AND
        (delivered_at IS NULL OR delivered_at >= COALESCE(shipped_at, created_at)) AND
        (received_at IS NULL OR received_at >= COALESCE(delivered_at, shipped_at, created_at))
    ),
    CONSTRAINT ck_doms_return_shipment_hash CHECK (
        tracking_number_hash IS NULL OR tracking_number_hash ~ '^[0-9A-Fa-f]{64}$'
    ),
    CONSTRAINT ck_doms_return_shipment_json CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(attributes)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_return_shipment_external
    ON doms.return_shipments (tenant_id, external_shipment_reference)
    WHERE external_shipment_reference IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_return_shipment_tracking
    ON doms.return_shipments (tenant_id, tracking_number_hash)
    WHERE tracking_number_hash IS NOT NULL;

CREATE TABLE IF NOT EXISTS doms.return_shipment_lines (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    return_shipment_id uuid NOT NULL,
    rma_authorization_line_id uuid NOT NULL,
    line_no integer NOT NULL,
    original_shipment_line_id uuid NOT NULL,
    original_package_item_id uuid NOT NULL,
    item_id uuid NOT NULL,
    shipped_quantity numeric(24,8) NOT NULL,
    received_quantity numeric(24,8) NOT NULL DEFAULT 0,
    uom_code varchar(20) NOT NULL REFERENCES doms.units_of_measure(uom_code),
    line_status varchar(20) NOT NULL DEFAULT 'PLANNED',
    idempotency_key varchar(200) NOT NULL,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, return_shipment_id, line_no),
    UNIQUE (tenant_id, return_shipment_id, idempotency_key),
    CONSTRAINT fk_doms_return_shipment_line_header
        FOREIGN KEY (tenant_id, return_shipment_id)
        REFERENCES doms.return_shipments(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_return_shipment_line_rma
        FOREIGN KEY (tenant_id, rma_authorization_line_id)
        REFERENCES doms.rma_authorization_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_return_shipment_line_original
        FOREIGN KEY (tenant_id, original_shipment_line_id)
        REFERENCES doms.shipment_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_return_shipment_line_package
        FOREIGN KEY (tenant_id, original_package_item_id)
        REFERENCES doms.package_items(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_return_shipment_line_item
        FOREIGN KEY (tenant_id, item_id)
        REFERENCES doms.items(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_return_shipment_line_values CHECK (
        line_no > 0 AND shipped_quantity > 0 AND received_quantity >= 0 AND
        received_quantity <= shipped_quantity AND btrim(idempotency_key) <> ''
    ),
    CONSTRAINT ck_doms_return_shipment_line_status CHECK (line_status IN (
        'PLANNED','SHIPPED','IN_TRANSIT','DELIVERED','PARTIALLY_RECEIVED','RECEIVED',
        'EXCEPTION','LOST','CANCELLED','CLOSED'
    ))
);

CREATE TABLE IF NOT EXISTS doms.return_tracking_events (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    return_shipment_id uuid NOT NULL,
    event_sequence bigint NOT NULL,
    event_code varchar(100) NOT NULL,
    event_status varchar(40) NOT NULL,
    event_description_masked text,
    location_encrypted text,
    location_masked varchar(300),
    external_event_reference varchar(300),
    idempotency_key varchar(200),
    payload_summary jsonb NOT NULL DEFAULT '{}'::jsonb,
    occurred_at timestamptz NOT NULL,
    received_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, return_shipment_id, event_sequence),
    CONSTRAINT fk_doms_return_tracking_shipment
        FOREIGN KEY (tenant_id, return_shipment_id)
        REFERENCES doms.return_shipments(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_return_tracking_values CHECK (
        event_sequence > 0 AND btrim(event_code) <> '' AND received_at >= occurred_at
    ),
    CONSTRAINT ck_doms_return_tracking_json CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(payload_summary)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_return_tracking_external
    ON doms.return_tracking_events (tenant_id, external_event_reference)
    WHERE external_event_reference IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_return_tracking_idempotency
    ON doms.return_tracking_events (tenant_id, return_shipment_id, idempotency_key)
    WHERE idempotency_key IS NOT NULL;

CREATE TABLE IF NOT EXISTS doms.return_receipts (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    receipt_no varchar(100) NOT NULL,
    rma_authorization_id uuid NOT NULL,
    return_shipment_id uuid,
    fulfillment_node_id uuid NOT NULL,
    receipt_status varchar(20) NOT NULL DEFAULT 'OPEN',
    received_at timestamptz NOT NULL,
    completed_at timestamptz,
    idempotency_key varchar(200) NOT NULL,
    received_by uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, receipt_no),
    UNIQUE (tenant_id, rma_authorization_id, idempotency_key),
    CONSTRAINT fk_doms_return_receipt_rma
        FOREIGN KEY (tenant_id, rma_authorization_id)
        REFERENCES doms.rma_authorizations(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_return_receipt_shipment
        FOREIGN KEY (tenant_id, return_shipment_id)
        REFERENCES doms.return_shipments(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_return_receipt_node
        FOREIGN KEY (tenant_id, fulfillment_node_id)
        REFERENCES doms.fulfillment_nodes(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_return_receipt_values CHECK (
        btrim(receipt_no) <> '' AND btrim(idempotency_key) <> ''
    ),
    CONSTRAINT ck_doms_return_receipt_status CHECK (
        receipt_status IN ('OPEN','RECEIVING','PARTIAL','COMPLETED','EXCEPTION','VOID')
    ),
    CONSTRAINT ck_doms_return_receipt_dates CHECK (
        received_at >= created_at AND (completed_at IS NULL OR completed_at >= received_at)
    ),
    CONSTRAINT ck_doms_return_receipt_json CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(attributes)
    )
);

CREATE TABLE IF NOT EXISTS doms.return_receipt_lines (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    return_receipt_id uuid NOT NULL,
    rma_authorization_line_id uuid NOT NULL,
    return_shipment_line_id uuid,
    line_no integer NOT NULL,
    item_id uuid NOT NULL,
    received_quantity numeric(24,8) NOT NULL,
    uom_code varchar(20) NOT NULL REFERENCES doms.units_of_measure(uom_code),
    unexpected_quantity boolean NOT NULL DEFAULT false,
    exception_approved_by uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    exception_approved_at timestamptz,
    exception_reason text,
    idempotency_key varchar(200) NOT NULL,
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, return_receipt_id, line_no),
    UNIQUE (tenant_id, return_receipt_id, idempotency_key),
    CONSTRAINT fk_doms_return_receipt_line_header
        FOREIGN KEY (tenant_id, return_receipt_id)
        REFERENCES doms.return_receipts(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_return_receipt_line_rma
        FOREIGN KEY (tenant_id, rma_authorization_line_id)
        REFERENCES doms.rma_authorization_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_return_receipt_line_shipment_line
        FOREIGN KEY (tenant_id, return_shipment_line_id)
        REFERENCES doms.return_shipment_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_return_receipt_line_item
        FOREIGN KEY (tenant_id, item_id)
        REFERENCES doms.items(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_return_receipt_line_values CHECK (
        line_no > 0 AND received_quantity > 0 AND btrim(idempotency_key) <> ''
    ),
    CONSTRAINT ck_doms_return_receipt_line_exception CHECK (
        (NOT unexpected_quantity AND exception_approved_by IS NULL AND
            exception_approved_at IS NULL AND exception_reason IS NULL) OR
        (unexpected_quantity AND exception_approved_by IS NOT NULL AND
            exception_approved_at IS NOT NULL AND btrim(COALESCE(exception_reason, '')) <> '')
    ),
    CONSTRAINT ck_doms_return_receipt_line_json CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(attributes)
    )
);

CREATE TABLE IF NOT EXISTS doms.return_receipt_events (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    return_receipt_id uuid NOT NULL,
    return_receipt_line_id uuid,
    event_sequence bigint NOT NULL,
    event_type varchar(40) NOT NULL,
    quantity numeric(24,8) NOT NULL DEFAULT 0,
    idempotency_key varchar(200),
    actor_user_id uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    detail_masked text,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, return_receipt_id, event_sequence),
    CONSTRAINT fk_doms_return_receipt_event_header
        FOREIGN KEY (tenant_id, return_receipt_id)
        REFERENCES doms.return_receipts(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_return_receipt_event_line
        FOREIGN KEY (tenant_id, return_receipt_line_id)
        REFERENCES doms.return_receipt_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_return_receipt_event_values CHECK (
        event_sequence > 0 AND quantity >= 0 AND btrim(event_type) <> ''
    ),
    CONSTRAINT ck_doms_return_receipt_event_json CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(metadata)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_return_receipt_event_idempotency
    ON doms.return_receipt_events (tenant_id, return_receipt_id, idempotency_key)
    WHERE idempotency_key IS NOT NULL;

CREATE TABLE IF NOT EXISTS doms.return_inspections (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    inspection_no varchar(100) NOT NULL,
    return_receipt_line_id uuid NOT NULL,
    rma_authorization_line_id uuid NOT NULL,
    inspection_sequence integer NOT NULL,
    inspection_status varchar(20) NOT NULL DEFAULT 'COMPLETED',
    inspected_quantity numeric(24,8) NOT NULL,
    accepted_quantity numeric(24,8) NOT NULL DEFAULT 0,
    rejected_quantity numeric(24,8) NOT NULL DEFAULT 0,
    condition_grade varchar(30),
    functional_result varchar(30),
    inspection_result varchar(30) NOT NULL,
    idempotency_key varchar(200) NOT NULL,
    inspector_user_id uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    inspected_at timestamptz NOT NULL DEFAULT now(),
    findings jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, inspection_no),
    UNIQUE (tenant_id, return_receipt_line_id, inspection_sequence),
    UNIQUE (tenant_id, return_receipt_line_id, idempotency_key),
    CONSTRAINT fk_doms_return_inspection_receipt_line
        FOREIGN KEY (tenant_id, return_receipt_line_id)
        REFERENCES doms.return_receipt_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_return_inspection_rma_line
        FOREIGN KEY (tenant_id, rma_authorization_line_id)
        REFERENCES doms.rma_authorization_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_return_inspection_values CHECK (
        btrim(inspection_no) <> '' AND inspection_sequence > 0 AND inspected_quantity > 0 AND
        accepted_quantity >= 0 AND rejected_quantity >= 0 AND
        accepted_quantity + rejected_quantity = inspected_quantity AND
        btrim(idempotency_key) <> ''
    ),
    CONSTRAINT ck_doms_return_inspection_status CHECK (
        inspection_status IN ('COMPLETED','VOID')
    ),
    CONSTRAINT ck_doms_return_inspection_condition CHECK (
        condition_grade IS NULL OR condition_grade IN ('NEW','A','B','C','DAMAGED','DEFECTIVE','UNKNOWN')
    ),
    CONSTRAINT ck_doms_return_inspection_functional CHECK (
        functional_result IS NULL OR functional_result IN ('PASS','FAIL','NOT_TESTED','INCONCLUSIVE')
    ),
    CONSTRAINT ck_doms_return_inspection_result CHECK (
        inspection_result IN ('ACCEPT','PARTIAL','REJECT','REVIEW','HAZARDOUS','COUNTERFEIT')
    ),
    CONSTRAINT ck_doms_return_inspection_json CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(findings)
    )
);

CREATE TABLE IF NOT EXISTS doms.return_inspection_events (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    return_inspection_id uuid NOT NULL,
    event_sequence bigint NOT NULL,
    event_type varchar(40) NOT NULL,
    idempotency_key varchar(200),
    actor_user_id uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    detail_masked text,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, return_inspection_id, event_sequence),
    CONSTRAINT fk_doms_return_inspection_event
        FOREIGN KEY (tenant_id, return_inspection_id)
        REFERENCES doms.return_inspections(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_return_inspection_event_values CHECK (
        event_sequence > 0 AND btrim(event_type) <> ''
    ),
    CONSTRAINT ck_doms_return_inspection_event_json CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(metadata)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_return_inspection_event_idempotency
    ON doms.return_inspection_events (tenant_id, return_inspection_id, idempotency_key)
    WHERE idempotency_key IS NOT NULL;

CREATE TABLE IF NOT EXISTS doms.return_dispositions (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    disposition_no varchar(100) NOT NULL,
    return_inspection_id uuid NOT NULL,
    rma_authorization_line_id uuid NOT NULL,
    disposition_sequence integer NOT NULL,
    disposition_type varchar(30) NOT NULL,
    disposition_quantity numeric(24,8) NOT NULL,
    refund_eligible_quantity numeric(24,8) NOT NULL DEFAULT 0,
    refund_eligible_amount numeric(24,6) NOT NULL DEFAULT 0,
    currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    inventory_outcome varchar(30) NOT NULL,
    target_fulfillment_node_id uuid,
    idempotency_key varchar(200) NOT NULL,
    reason_code varchar(100),
    decided_by uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    decided_at timestamptz NOT NULL DEFAULT now(),
    evidence jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, disposition_no),
    UNIQUE (tenant_id, return_inspection_id, disposition_sequence),
    UNIQUE (tenant_id, return_inspection_id, idempotency_key),
    CONSTRAINT fk_doms_return_disposition_inspection
        FOREIGN KEY (tenant_id, return_inspection_id)
        REFERENCES doms.return_inspections(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_return_disposition_rma_line
        FOREIGN KEY (tenant_id, rma_authorization_line_id)
        REFERENCES doms.rma_authorization_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_return_disposition_node
        FOREIGN KEY (tenant_id, target_fulfillment_node_id)
        REFERENCES doms.fulfillment_nodes(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_return_disposition_values CHECK (
        btrim(disposition_no) <> '' AND disposition_sequence > 0 AND
        disposition_quantity > 0 AND refund_eligible_quantity >= 0 AND
        refund_eligible_quantity <= disposition_quantity AND refund_eligible_amount >= 0 AND
        btrim(idempotency_key) <> ''
    ),
    CONSTRAINT ck_doms_return_disposition_type CHECK (disposition_type IN (
        'RESTOCK','QUARANTINE','REFURBISH','REPAIR','SCRAP','RETURN_TO_VENDOR',
        'DONATE','KEEP_ITEM','DESTROY','OTHER'
    )),
    CONSTRAINT ck_doms_return_disposition_outcome CHECK (inventory_outcome IN (
        'AVAILABLE','HOLD','DAMAGED','NO_STOCK','VENDOR_RETURN','SCRAPPED','SERVICE'
    )),
    CONSTRAINT ck_doms_return_disposition_json CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(evidence)
    )
);

CREATE TABLE IF NOT EXISTS doms.return_disposition_events (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    return_disposition_id uuid NOT NULL,
    event_sequence bigint NOT NULL,
    event_type varchar(40) NOT NULL,
    idempotency_key varchar(200),
    actor_user_id uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    detail_masked text,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, return_disposition_id, event_sequence),
    CONSTRAINT fk_doms_return_disposition_event
        FOREIGN KEY (tenant_id, return_disposition_id)
        REFERENCES doms.return_dispositions(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_return_disposition_event_values CHECK (
        event_sequence > 0 AND btrim(event_type) <> ''
    ),
    CONSTRAINT ck_doms_return_disposition_event_json CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(metadata)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_return_disposition_event_idempotency
    ON doms.return_disposition_events (tenant_id, return_disposition_id, idempotency_key)
    WHERE idempotency_key IS NOT NULL;

-- -----------------------------------------------------------------------------
-- Return refund calculation and payment-refund linkage
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS doms.return_refund_calculations (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    calculation_no varchar(100) NOT NULL,
    return_request_id uuid NOT NULL,
    return_policy_version_id uuid NOT NULL,
    calculation_status varchar(20) NOT NULL DEFAULT 'DRAFT',
    currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    principal_amount numeric(24,6) NOT NULL DEFAULT 0,
    tax_amount numeric(24,6) NOT NULL DEFAULT 0,
    shipping_amount numeric(24,6) NOT NULL DEFAULT 0,
    fee_deduction_amount numeric(24,6) NOT NULL DEFAULT 0,
    refund_amount numeric(24,6) NOT NULL DEFAULT 0,
    reserved_refund_amount numeric(24,6) NOT NULL DEFAULT 0,
    succeeded_refund_amount numeric(24,6) NOT NULL DEFAULT 0,
    idempotency_key varchar(200) NOT NULL,
    calculated_at timestamptz,
    approved_at timestamptz,
    approved_by uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    calculation_data jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, calculation_no),
    UNIQUE (tenant_id, return_request_id, idempotency_key),
    CONSTRAINT fk_doms_return_refund_calc_request
        FOREIGN KEY (tenant_id, return_request_id)
        REFERENCES doms.return_requests(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_return_refund_calc_policy
        FOREIGN KEY (tenant_id, return_policy_version_id)
        REFERENCES doms.return_policy_versions(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_return_refund_calc_values CHECK (
        btrim(calculation_no) <> '' AND btrim(idempotency_key) <> '' AND
        principal_amount >= 0 AND tax_amount >= 0 AND shipping_amount >= 0 AND
        fee_deduction_amount >= 0 AND refund_amount >= 0 AND reserved_refund_amount >= 0 AND
        succeeded_refund_amount >= 0 AND
        refund_amount = principal_amount + tax_amount + shipping_amount - fee_deduction_amount AND
        succeeded_refund_amount <= reserved_refund_amount AND reserved_refund_amount <= refund_amount
    ),
    CONSTRAINT ck_doms_return_refund_calc_status CHECK (calculation_status IN (
        'DRAFT','CALCULATED','APPROVAL_PENDING','APPROVED','REFUND_PENDING',
        'PARTIALLY_REFUNDED','REFUNDED','REJECTED','CANCELLED','SUPERSEDED'
    )),
    CONSTRAINT ck_doms_return_refund_calc_dates CHECK (
        (calculated_at IS NULL OR calculated_at >= created_at) AND
        (approved_at IS NULL OR approved_at >= COALESCE(calculated_at, created_at))
    ),
    CONSTRAINT ck_doms_return_refund_calc_approval CHECK (
        calculation_status NOT IN ('APPROVED','REFUND_PENDING','PARTIALLY_REFUNDED','REFUNDED') OR
        (approved_at IS NOT NULL AND approved_by IS NOT NULL)
    ),
    CONSTRAINT ck_doms_return_refund_calc_json CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(calculation_data)
    )
);

CREATE TABLE IF NOT EXISTS doms.return_refund_calculation_lines (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    return_refund_calculation_id uuid NOT NULL,
    line_no integer NOT NULL,
    return_request_line_id uuid NOT NULL,
    rma_authorization_line_id uuid NOT NULL,
    return_disposition_id uuid NOT NULL,
    eligible_quantity numeric(24,8) NOT NULL,
    requested_refund_quantity numeric(24,8) NOT NULL,
    reserved_refund_quantity numeric(24,8) NOT NULL DEFAULT 0,
    succeeded_refund_quantity numeric(24,8) NOT NULL DEFAULT 0,
    unit_refund_amount numeric(24,6) NOT NULL,
    principal_amount numeric(24,6) NOT NULL DEFAULT 0,
    tax_amount numeric(24,6) NOT NULL DEFAULT 0,
    shipping_amount numeric(24,6) NOT NULL DEFAULT 0,
    fee_deduction_amount numeric(24,6) NOT NULL DEFAULT 0,
    total_refund_amount numeric(24,6) NOT NULL,
    reserved_refund_amount numeric(24,6) NOT NULL DEFAULT 0,
    succeeded_refund_amount numeric(24,6) NOT NULL DEFAULT 0,
    currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    calculation_detail jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, return_refund_calculation_id, line_no),
    UNIQUE (tenant_id, return_refund_calculation_id, return_disposition_id),
    CONSTRAINT fk_doms_return_refund_calc_line_header
        FOREIGN KEY (tenant_id, return_refund_calculation_id)
        REFERENCES doms.return_refund_calculations(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_return_refund_calc_line_request
        FOREIGN KEY (tenant_id, return_request_line_id)
        REFERENCES doms.return_request_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_return_refund_calc_line_rma
        FOREIGN KEY (tenant_id, rma_authorization_line_id)
        REFERENCES doms.rma_authorization_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_return_refund_calc_line_disposition
        FOREIGN KEY (tenant_id, return_disposition_id)
        REFERENCES doms.return_dispositions(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_return_refund_calc_line_values CHECK (
        line_no > 0 AND eligible_quantity > 0 AND requested_refund_quantity > 0 AND
        requested_refund_quantity <= eligible_quantity AND reserved_refund_quantity >= 0 AND
        succeeded_refund_quantity >= 0 AND succeeded_refund_quantity <= reserved_refund_quantity AND
        reserved_refund_quantity <= requested_refund_quantity AND unit_refund_amount >= 0 AND
        principal_amount >= 0 AND tax_amount >= 0 AND shipping_amount >= 0 AND
        fee_deduction_amount >= 0 AND total_refund_amount >= 0 AND
        total_refund_amount = principal_amount + tax_amount + shipping_amount - fee_deduction_amount AND
        reserved_refund_amount >= 0 AND succeeded_refund_amount >= 0 AND
        succeeded_refund_amount <= reserved_refund_amount AND
        reserved_refund_amount <= total_refund_amount
    ),
    CONSTRAINT ck_doms_return_refund_calc_line_json CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(calculation_detail)
    )
);

CREATE TABLE IF NOT EXISTS doms.return_payment_refund_links (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    return_refund_calculation_id uuid NOT NULL,
    return_refund_calculation_line_id uuid NOT NULL,
    payment_refund_request_id uuid NOT NULL,
    payment_refund_id uuid,
    linked_quantity numeric(24,8) NOT NULL,
    linked_amount numeric(24,6) NOT NULL,
    currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    link_status varchar(20) NOT NULL DEFAULT 'PLANNED',
    idempotency_key varchar(200) NOT NULL,
    linked_at timestamptz NOT NULL DEFAULT now(),
    succeeded_at timestamptz,
    failure_reason_masked text,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, return_refund_calculation_id, idempotency_key),
    UNIQUE (tenant_id, payment_refund_id),
    CONSTRAINT fk_doms_return_payment_link_calc
        FOREIGN KEY (tenant_id, return_refund_calculation_id)
        REFERENCES doms.return_refund_calculations(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_return_payment_link_calc_line
        FOREIGN KEY (tenant_id, return_refund_calculation_line_id)
        REFERENCES doms.return_refund_calculation_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_return_payment_link_request
        FOREIGN KEY (tenant_id, payment_refund_request_id)
        REFERENCES doms.payment_refund_requests(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_return_payment_link_refund
        FOREIGN KEY (tenant_id, payment_refund_id)
        REFERENCES doms.payment_refunds(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_return_payment_link_values CHECK (
        linked_quantity > 0 AND linked_amount > 0 AND btrim(idempotency_key) <> ''
    ),
    CONSTRAINT ck_doms_return_payment_link_status CHECK (
        link_status IN ('PLANNED','SUBMITTED','PROCESSING','SUCCEEDED','FAILED','CANCELLED')
    ),
    CONSTRAINT ck_doms_return_payment_link_success CHECK (
        (link_status = 'SUCCEEDED' AND payment_refund_id IS NOT NULL AND succeeded_at IS NOT NULL) OR
        (link_status <> 'SUCCEEDED' AND succeeded_at IS NULL)
    )
);

-- -----------------------------------------------------------------------------
-- Exchanges and replacements link to newly created normal sales orders.
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS doms.exchange_requests (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    exchange_request_no varchar(100) NOT NULL,
    return_request_id uuid NOT NULL,
    original_sales_order_id uuid NOT NULL,
    customer_id uuid NOT NULL,
    exchange_status varchar(30) NOT NULL DEFAULT 'REQUESTED',
    settlement_currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    additional_charge_amount numeric(24,6) NOT NULL DEFAULT 0,
    refund_difference_amount numeric(24,6) NOT NULL DEFAULT 0,
    idempotency_key varchar(200) NOT NULL,
    requested_at timestamptz NOT NULL DEFAULT now(),
    approved_at timestamptz,
    approved_by uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, exchange_request_no),
    UNIQUE (tenant_id, return_request_id, idempotency_key),
    CONSTRAINT fk_doms_exchange_request_return
        FOREIGN KEY (tenant_id, return_request_id)
        REFERENCES doms.return_requests(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_exchange_request_order
        FOREIGN KEY (tenant_id, original_sales_order_id)
        REFERENCES doms.sales_orders(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_exchange_request_customer
        FOREIGN KEY (tenant_id, customer_id)
        REFERENCES doms.customers(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_exchange_request_values CHECK (
        btrim(exchange_request_no) <> '' AND btrim(idempotency_key) <> '' AND
        additional_charge_amount >= 0 AND refund_difference_amount >= 0 AND
        NOT (additional_charge_amount > 0 AND refund_difference_amount > 0)
    ),
    CONSTRAINT ck_doms_exchange_request_status CHECK (exchange_status IN (
        'REQUESTED','REVIEW','APPROVED','ORDER_PENDING','ORDER_CREATED','FULFILLING',
        'COMPLETED','REJECTED','CANCELLED','EXPIRED'
    )),
    CONSTRAINT ck_doms_exchange_request_approval CHECK (
        exchange_status NOT IN ('APPROVED','ORDER_PENDING','ORDER_CREATED','FULFILLING','COMPLETED') OR
        (approved_at IS NOT NULL AND approved_by IS NOT NULL)
    ),
    CONSTRAINT ck_doms_exchange_request_json CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(attributes)
    )
);

CREATE TABLE IF NOT EXISTS doms.exchange_request_lines (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    exchange_request_id uuid NOT NULL,
    line_no integer NOT NULL,
    return_request_line_id uuid NOT NULL,
    original_item_id uuid NOT NULL,
    replacement_item_id uuid NOT NULL,
    return_quantity numeric(24,8) NOT NULL,
    replacement_quantity numeric(24,8) NOT NULL,
    uom_code varchar(20) NOT NULL REFERENCES doms.units_of_measure(uom_code),
    unit_price_difference numeric(24,6) NOT NULL DEFAULT 0,
    line_status varchar(20) NOT NULL DEFAULT 'REQUESTED',
    idempotency_key varchar(200) NOT NULL,
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, exchange_request_id, line_no),
    UNIQUE (tenant_id, exchange_request_id, idempotency_key),
    CONSTRAINT fk_doms_exchange_line_header
        FOREIGN KEY (tenant_id, exchange_request_id)
        REFERENCES doms.exchange_requests(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_exchange_line_return_line
        FOREIGN KEY (tenant_id, return_request_line_id)
        REFERENCES doms.return_request_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_exchange_line_original_item
        FOREIGN KEY (tenant_id, original_item_id)
        REFERENCES doms.items(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_exchange_line_replacement_item
        FOREIGN KEY (tenant_id, replacement_item_id)
        REFERENCES doms.items(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_exchange_line_values CHECK (
        line_no > 0 AND return_quantity > 0 AND replacement_quantity > 0 AND
        btrim(idempotency_key) <> ''
    ),
    CONSTRAINT ck_doms_exchange_line_status CHECK (
        line_status IN ('REQUESTED','APPROVED','ORDERED','FULFILLED','REJECTED','CANCELLED')
    ),
    CONSTRAINT ck_doms_exchange_line_json CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(attributes)
    )
);

CREATE TABLE IF NOT EXISTS doms.exchange_order_links (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    exchange_request_id uuid NOT NULL,
    exchange_request_line_id uuid NOT NULL,
    original_sales_order_id uuid NOT NULL,
    replacement_sales_order_id uuid NOT NULL,
    replacement_sales_order_line_id uuid NOT NULL,
    link_status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    idempotency_key varchar(200) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, exchange_request_line_id),
    UNIQUE (tenant_id, exchange_request_id, idempotency_key),
    CONSTRAINT fk_doms_exchange_order_link_header
        FOREIGN KEY (tenant_id, exchange_request_id)
        REFERENCES doms.exchange_requests(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_exchange_order_link_line
        FOREIGN KEY (tenant_id, exchange_request_line_id)
        REFERENCES doms.exchange_request_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_exchange_order_link_original
        FOREIGN KEY (tenant_id, original_sales_order_id)
        REFERENCES doms.sales_orders(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_exchange_order_link_replacement
        FOREIGN KEY (tenant_id, replacement_sales_order_id)
        REFERENCES doms.sales_orders(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_exchange_order_link_replacement_line
        FOREIGN KEY (tenant_id, replacement_sales_order_line_id)
        REFERENCES doms.sales_order_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_exchange_order_link_distinct CHECK (
        original_sales_order_id <> replacement_sales_order_id
    ),
    CONSTRAINT ck_doms_exchange_order_link_status CHECK (
        link_status IN ('ACTIVE','FULFILLED','CANCELLED','SUPERSEDED')
    ),
    CONSTRAINT ck_doms_exchange_order_link_key CHECK (btrim(idempotency_key) <> '')
);

CREATE TABLE IF NOT EXISTS doms.replacement_requests (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    replacement_request_no varchar(100) NOT NULL,
    return_request_id uuid,
    original_sales_order_id uuid NOT NULL,
    customer_id uuid NOT NULL,
    replacement_reason varchar(80) NOT NULL,
    replacement_status varchar(30) NOT NULL DEFAULT 'REQUESTED',
    no_return_required boolean NOT NULL DEFAULT false,
    idempotency_key varchar(200) NOT NULL,
    requested_at timestamptz NOT NULL DEFAULT now(),
    approved_at timestamptz,
    approved_by uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, replacement_request_no),
    UNIQUE (tenant_id, original_sales_order_id, idempotency_key),
    CONSTRAINT fk_doms_replacement_request_return
        FOREIGN KEY (tenant_id, return_request_id)
        REFERENCES doms.return_requests(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_replacement_request_order
        FOREIGN KEY (tenant_id, original_sales_order_id)
        REFERENCES doms.sales_orders(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_replacement_request_customer
        FOREIGN KEY (tenant_id, customer_id)
        REFERENCES doms.customers(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_replacement_request_values CHECK (
        btrim(replacement_request_no) <> '' AND btrim(replacement_reason) <> '' AND
        btrim(idempotency_key) <> ''
    ),
    CONSTRAINT ck_doms_replacement_request_status CHECK (replacement_status IN (
        'REQUESTED','REVIEW','APPROVED','ORDER_PENDING','ORDER_CREATED','FULFILLING',
        'COMPLETED','REJECTED','CANCELLED','EXPIRED'
    )),
    CONSTRAINT ck_doms_replacement_request_return CHECK (
        no_return_required OR return_request_id IS NOT NULL
    ),
    CONSTRAINT ck_doms_replacement_request_approval CHECK (
        replacement_status NOT IN ('APPROVED','ORDER_PENDING','ORDER_CREATED','FULFILLING','COMPLETED') OR
        (approved_at IS NOT NULL AND approved_by IS NOT NULL)
    ),
    CONSTRAINT ck_doms_replacement_request_json CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(attributes)
    )
);

CREATE TABLE IF NOT EXISTS doms.replacement_request_lines (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    replacement_request_id uuid NOT NULL,
    line_no integer NOT NULL,
    original_sales_order_line_id uuid NOT NULL,
    original_shipment_line_id uuid NOT NULL,
    original_package_item_id uuid NOT NULL,
    replacement_item_id uuid NOT NULL,
    replacement_quantity numeric(24,8) NOT NULL,
    uom_code varchar(20) NOT NULL REFERENCES doms.units_of_measure(uom_code),
    line_status varchar(20) NOT NULL DEFAULT 'REQUESTED',
    idempotency_key varchar(200) NOT NULL,
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, replacement_request_id, line_no),
    UNIQUE (tenant_id, replacement_request_id, idempotency_key),
    CONSTRAINT fk_doms_replacement_line_header
        FOREIGN KEY (tenant_id, replacement_request_id)
        REFERENCES doms.replacement_requests(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_replacement_line_order_line
        FOREIGN KEY (tenant_id, original_sales_order_line_id)
        REFERENCES doms.sales_order_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_replacement_line_shipment_line
        FOREIGN KEY (tenant_id, original_shipment_line_id)
        REFERENCES doms.shipment_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_replacement_line_package
        FOREIGN KEY (tenant_id, original_package_item_id)
        REFERENCES doms.package_items(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_replacement_line_item
        FOREIGN KEY (tenant_id, replacement_item_id)
        REFERENCES doms.items(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_replacement_line_values CHECK (
        line_no > 0 AND replacement_quantity > 0 AND btrim(idempotency_key) <> ''
    ),
    CONSTRAINT ck_doms_replacement_line_status CHECK (
        line_status IN ('REQUESTED','APPROVED','ORDERED','FULFILLED','REJECTED','CANCELLED')
    ),
    CONSTRAINT ck_doms_replacement_line_json CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(attributes)
    )
);

CREATE TABLE IF NOT EXISTS doms.replacement_order_links (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    replacement_request_id uuid NOT NULL,
    replacement_request_line_id uuid NOT NULL,
    original_sales_order_id uuid NOT NULL,
    replacement_sales_order_id uuid NOT NULL,
    replacement_sales_order_line_id uuid NOT NULL,
    link_status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    idempotency_key varchar(200) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, replacement_request_line_id),
    UNIQUE (tenant_id, replacement_request_id, idempotency_key),
    CONSTRAINT fk_doms_replacement_order_link_header
        FOREIGN KEY (tenant_id, replacement_request_id)
        REFERENCES doms.replacement_requests(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_replacement_order_link_line
        FOREIGN KEY (tenant_id, replacement_request_line_id)
        REFERENCES doms.replacement_request_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_replacement_order_link_original
        FOREIGN KEY (tenant_id, original_sales_order_id)
        REFERENCES doms.sales_orders(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_replacement_order_link_replacement
        FOREIGN KEY (tenant_id, replacement_sales_order_id)
        REFERENCES doms.sales_orders(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_replacement_order_link_replacement_line
        FOREIGN KEY (tenant_id, replacement_sales_order_line_id)
        REFERENCES doms.sales_order_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_replacement_order_link_distinct CHECK (
        original_sales_order_id <> replacement_sales_order_id
    ),
    CONSTRAINT ck_doms_replacement_order_link_status CHECK (
        link_status IN ('ACTIVE','FULFILLED','CANCELLED','SUPERSEDED')
    ),
    CONSTRAINT ck_doms_replacement_order_link_key CHECK (btrim(idempotency_key) <> '')
);

-- -----------------------------------------------------------------------------
-- Warranty policies, registrations, and claims
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS doms.warranty_policies (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    warranty_policy_code varchar(80) NOT NULL,
    warranty_policy_name varchar(200) NOT NULL,
    item_id uuid,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    current_version_id uuid,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, warranty_policy_code),
    CONSTRAINT fk_doms_warranty_policy_item
        FOREIGN KEY (tenant_id, item_id)
        REFERENCES doms.items(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_warranty_policy_code CHECK (btrim(warranty_policy_code) <> ''),
    CONSTRAINT ck_doms_warranty_policy_status CHECK (
        status IN ('DRAFT','ACTIVE','SUSPENDED','RETIRED')
    )
);

CREATE TABLE IF NOT EXISTS doms.warranty_policy_versions (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    warranty_policy_id uuid NOT NULL,
    version_no integer NOT NULL,
    version_status varchar(20) NOT NULL DEFAULT 'DRAFT',
    warranty_duration_months integer NOT NULL,
    duration_start_event varchar(30) NOT NULL DEFAULT 'DELIVERED',
    require_registration boolean NOT NULL DEFAULT false,
    require_serial boolean NOT NULL DEFAULT false,
    allow_repair boolean NOT NULL DEFAULT true,
    allow_replacement boolean NOT NULL DEFAULT true,
    allow_refund boolean NOT NULL DEFAULT false,
    effective_from timestamptz,
    effective_to timestamptz,
    coverage_config jsonb NOT NULL DEFAULT '{}'::jsonb,
    checksum_sha256 char(64),
    published_by uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    published_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, warranty_policy_id, version_no),
    CONSTRAINT fk_doms_warranty_policy_version_header
        FOREIGN KEY (tenant_id, warranty_policy_id)
        REFERENCES doms.warranty_policies(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_warranty_policy_version_values CHECK (
        version_no > 0 AND warranty_duration_months >= 0
    ),
    CONSTRAINT ck_doms_warranty_policy_version_status CHECK (
        version_status IN ('DRAFT','PUBLISHED','ACTIVE','SUPERSEDED','RETIRED')
    ),
    CONSTRAINT ck_doms_warranty_policy_version_start CHECK (
        duration_start_event IN ('ORDERED','SHIPPED','DELIVERED','REGISTERED','ACTIVATED')
    ),
    CONSTRAINT ck_doms_warranty_policy_version_dates CHECK (
        effective_to IS NULL OR effective_from IS NULL OR effective_to > effective_from
    ),
    CONSTRAINT ck_doms_warranty_policy_version_checksum CHECK (
        checksum_sha256 IS NULL OR checksum_sha256 ~ '^[0-9A-Fa-f]{64}$'
    ),
    CONSTRAINT ck_doms_warranty_policy_version_json CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(coverage_config)
    )
);

ALTER TABLE doms.warranty_policies
    DROP CONSTRAINT IF EXISTS fk_doms_warranty_policy_current_version;
ALTER TABLE doms.warranty_policies
    ADD CONSTRAINT fk_doms_warranty_policy_current_version
    FOREIGN KEY (tenant_id, current_version_id)
    REFERENCES doms.warranty_policy_versions(tenant_id, id) ON DELETE RESTRICT;

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_warranty_policy_active_version
    ON doms.warranty_policy_versions (tenant_id, warranty_policy_id)
    WHERE version_status = 'ACTIVE';

CREATE TABLE IF NOT EXISTS doms.warranty_registrations (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    registration_no varchar(100) NOT NULL,
    warranty_policy_version_id uuid NOT NULL,
    customer_id uuid NOT NULL,
    sales_order_id uuid NOT NULL,
    sales_order_line_id uuid NOT NULL,
    package_item_id uuid,
    item_id uuid NOT NULL,
    serial_number_encrypted text,
    serial_number_hash char(64),
    serial_number_masked varchar(150),
    purchase_date date NOT NULL,
    warranty_start_date date NOT NULL,
    warranty_end_date date NOT NULL,
    registration_status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    idempotency_key varchar(200) NOT NULL,
    registered_at timestamptz NOT NULL DEFAULT now(),
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, registration_no),
    UNIQUE (tenant_id, sales_order_line_id, idempotency_key),
    CONSTRAINT fk_doms_warranty_registration_policy
        FOREIGN KEY (tenant_id, warranty_policy_version_id)
        REFERENCES doms.warranty_policy_versions(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_warranty_registration_customer
        FOREIGN KEY (tenant_id, customer_id)
        REFERENCES doms.customers(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_warranty_registration_order
        FOREIGN KEY (tenant_id, sales_order_id)
        REFERENCES doms.sales_orders(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_warranty_registration_order_line
        FOREIGN KEY (tenant_id, sales_order_line_id)
        REFERENCES doms.sales_order_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_warranty_registration_package
        FOREIGN KEY (tenant_id, package_item_id)
        REFERENCES doms.package_items(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_warranty_registration_item
        FOREIGN KEY (tenant_id, item_id)
        REFERENCES doms.items(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_warranty_registration_values CHECK (
        btrim(registration_no) <> '' AND btrim(idempotency_key) <> '' AND
        warranty_start_date >= purchase_date AND warranty_end_date >= warranty_start_date
    ),
    CONSTRAINT ck_doms_warranty_registration_status CHECK (
        registration_status IN ('PENDING','ACTIVE','SUSPENDED','EXPIRED','VOID')
    ),
    CONSTRAINT ck_doms_warranty_registration_serial_hash CHECK (
        serial_number_hash IS NULL OR serial_number_hash ~ '^[0-9A-Fa-f]{64}$'
    ),
    CONSTRAINT ck_doms_warranty_registration_json CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(attributes)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_warranty_registration_serial
    ON doms.warranty_registrations (tenant_id, item_id, serial_number_hash)
    WHERE serial_number_hash IS NOT NULL AND registration_status <> 'VOID';

CREATE TABLE IF NOT EXISTS doms.warranty_claims (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    warranty_claim_no varchar(100) NOT NULL,
    warranty_registration_id uuid,
    warranty_policy_version_id uuid NOT NULL,
    customer_id uuid NOT NULL,
    sales_order_id uuid NOT NULL,
    claim_status varchar(30) NOT NULL DEFAULT 'SUBMITTED',
    claim_type varchar(30) NOT NULL,
    reported_issue_encrypted text,
    reported_issue_masked text,
    idempotency_key varchar(200) NOT NULL,
    submitted_at timestamptz NOT NULL DEFAULT now(),
    decided_at timestamptz,
    closed_at timestamptz,
    assigned_to uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    decision_by uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, warranty_claim_no),
    UNIQUE (tenant_id, sales_order_id, idempotency_key),
    CONSTRAINT fk_doms_warranty_claim_registration
        FOREIGN KEY (tenant_id, warranty_registration_id)
        REFERENCES doms.warranty_registrations(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_warranty_claim_policy
        FOREIGN KEY (tenant_id, warranty_policy_version_id)
        REFERENCES doms.warranty_policy_versions(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_warranty_claim_customer
        FOREIGN KEY (tenant_id, customer_id)
        REFERENCES doms.customers(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_warranty_claim_order
        FOREIGN KEY (tenant_id, sales_order_id)
        REFERENCES doms.sales_orders(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_warranty_claim_values CHECK (
        btrim(warranty_claim_no) <> '' AND btrim(idempotency_key) <> ''
    ),
    CONSTRAINT ck_doms_warranty_claim_status CHECK (claim_status IN (
        'SUBMITTED','TRIAGE','EVIDENCE_PENDING','INSPECTION_PENDING','UNDER_REVIEW',
        'APPROVED','PARTIALLY_APPROVED','REJECTED','REPAIR_PENDING','REPLACEMENT_PENDING',
        'REFUND_PENDING','RESOLVED','CANCELLED','EXPIRED','CLOSED'
    )),
    CONSTRAINT ck_doms_warranty_claim_type CHECK (
        claim_type IN ('REPAIR','REPLACEMENT','REFUND','SERVICE','PARTS','DIAGNOSIS','OTHER')
    ),
    CONSTRAINT ck_doms_warranty_claim_dates CHECK (
        (decided_at IS NULL OR decided_at >= submitted_at) AND
        (closed_at IS NULL OR closed_at >= COALESCE(decided_at, submitted_at))
    ),
    CONSTRAINT ck_doms_warranty_claim_json CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(metadata)
    )
);

CREATE TABLE IF NOT EXISTS doms.warranty_claim_lines (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    warranty_claim_id uuid NOT NULL,
    line_no integer NOT NULL,
    sales_order_line_id uuid NOT NULL,
    shipment_line_id uuid,
    package_item_id uuid,
    item_id uuid NOT NULL,
    claim_quantity numeric(24,8) NOT NULL,
    uom_code varchar(20) NOT NULL REFERENCES doms.units_of_measure(uom_code),
    requested_resolution varchar(30) NOT NULL,
    approved_resolution varchar(30),
    approved_quantity numeric(24,8) NOT NULL DEFAULT 0,
    line_status varchar(20) NOT NULL DEFAULT 'SUBMITTED',
    idempotency_key varchar(200) NOT NULL,
    evidence jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, warranty_claim_id, line_no),
    UNIQUE (tenant_id, warranty_claim_id, idempotency_key),
    CONSTRAINT fk_doms_warranty_claim_line_header
        FOREIGN KEY (tenant_id, warranty_claim_id)
        REFERENCES doms.warranty_claims(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_warranty_claim_line_order_line
        FOREIGN KEY (tenant_id, sales_order_line_id)
        REFERENCES doms.sales_order_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_warranty_claim_line_shipment_line
        FOREIGN KEY (tenant_id, shipment_line_id)
        REFERENCES doms.shipment_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_warranty_claim_line_package
        FOREIGN KEY (tenant_id, package_item_id)
        REFERENCES doms.package_items(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_warranty_claim_line_item
        FOREIGN KEY (tenant_id, item_id)
        REFERENCES doms.items(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_warranty_claim_line_values CHECK (
        line_no > 0 AND claim_quantity > 0 AND approved_quantity >= 0 AND
        approved_quantity <= claim_quantity AND btrim(idempotency_key) <> ''
    ),
    CONSTRAINT ck_doms_warranty_claim_line_resolution CHECK (
        requested_resolution IN ('REPAIR','REPLACEMENT','REFUND','SERVICE','PARTS','DIAGNOSIS','OTHER') AND
        (approved_resolution IS NULL OR approved_resolution IN (
            'REPAIR','REPLACEMENT','REFUND','SERVICE','PARTS','DIAGNOSIS','REJECTED'
        ))
    ),
    CONSTRAINT ck_doms_warranty_claim_line_status CHECK (
        line_status IN ('SUBMITTED','REVIEW','APPROVED','PARTIALLY_APPROVED','REJECTED','RESOLVED','CANCELLED')
    ),
    CONSTRAINT ck_doms_warranty_claim_line_json CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(evidence)
    )
);

CREATE TABLE IF NOT EXISTS doms.warranty_claim_events (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    warranty_claim_id uuid NOT NULL,
    warranty_claim_line_id uuid,
    event_sequence bigint NOT NULL,
    event_type varchar(40) NOT NULL,
    from_status varchar(30),
    to_status varchar(30) NOT NULL,
    idempotency_key varchar(200),
    actor_user_id uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    detail_masked text,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, warranty_claim_id, event_sequence),
    CONSTRAINT fk_doms_warranty_claim_event_header
        FOREIGN KEY (tenant_id, warranty_claim_id)
        REFERENCES doms.warranty_claims(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_warranty_claim_event_line
        FOREIGN KEY (tenant_id, warranty_claim_line_id)
        REFERENCES doms.warranty_claim_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_warranty_claim_event_values CHECK (
        event_sequence > 0 AND btrim(event_type) <> ''
    ),
    CONSTRAINT ck_doms_warranty_claim_event_json CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(metadata)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_warranty_claim_event_idempotency
    ON doms.warranty_claim_events (tenant_id, warranty_claim_id, idempotency_key)
    WHERE idempotency_key IS NOT NULL;

-- -----------------------------------------------------------------------------
-- Customer service cases, interactions, tasks, SLA, and adjustment approvals
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS doms.customer_service_cases (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    case_no varchar(100) NOT NULL,
    customer_id uuid,
    case_type varchar(40) NOT NULL,
    case_status varchar(30) NOT NULL DEFAULT 'OPEN',
    priority varchar(20) NOT NULL DEFAULT 'NORMAL',
    subject_encrypted text,
    subject_masked varchar(300) NOT NULL,
    contact_name_encrypted text,
    contact_name_masked varchar(200),
    contact_email_encrypted text,
    contact_email_hash char(64),
    contact_email_masked varchar(320),
    contact_phone_encrypted text,
    contact_phone_hash char(64),
    contact_phone_masked varchar(50),
    assigned_to uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    assigned_group_id uuid REFERENCES doms.user_groups(id) ON DELETE RESTRICT,
    opened_at timestamptz NOT NULL DEFAULT now(),
    first_response_due_at timestamptz,
    resolution_due_at timestamptz,
    resolved_at timestamptz,
    closed_at timestamptz,
    idempotency_key varchar(200) NOT NULL,
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, case_no),
    UNIQUE (tenant_id, idempotency_key),
    CONSTRAINT fk_doms_service_case_customer
        FOREIGN KEY (tenant_id, customer_id)
        REFERENCES doms.customers(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_service_case_values CHECK (
        btrim(case_no) <> '' AND btrim(subject_masked) <> '' AND btrim(idempotency_key) <> ''
    ),
    CONSTRAINT ck_doms_service_case_type CHECK (case_type IN (
        'ORDER','DELIVERY','RETURN','REFUND','EXCHANGE','REPLACEMENT','WARRANTY',
        'PAYMENT','PRODUCT','COMPLAINT','INQUIRY','OTHER'
    )),
    CONSTRAINT ck_doms_service_case_status CHECK (case_status IN (
        'OPEN','ASSIGNED','IN_PROGRESS','WAITING_CUSTOMER','WAITING_INTERNAL','ESCALATED',
        'RESOLVED','CLOSED','CANCELLED','REOPENED'
    )),
    CONSTRAINT ck_doms_service_case_priority CHECK (
        priority IN ('LOW','NORMAL','HIGH','URGENT','CRITICAL')
    ),
    CONSTRAINT ck_doms_service_case_dates CHECK (
        (first_response_due_at IS NULL OR first_response_due_at >= opened_at) AND
        (resolution_due_at IS NULL OR resolution_due_at >= opened_at) AND
        (resolved_at IS NULL OR resolved_at >= opened_at) AND
        (closed_at IS NULL OR closed_at >= COALESCE(resolved_at, opened_at))
    ),
    CONSTRAINT ck_doms_service_case_hashes CHECK (
        (contact_email_hash IS NULL OR contact_email_hash ~ '^[0-9A-Fa-f]{64}$') AND
        (contact_phone_hash IS NULL OR contact_phone_hash ~ '^[0-9A-Fa-f]{64}$')
    ),
    CONSTRAINT ck_doms_service_case_json CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(attributes)
    )
);

CREATE TABLE IF NOT EXISTS doms.customer_service_case_order_links (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    customer_service_case_id uuid NOT NULL,
    sales_order_id uuid NOT NULL,
    sales_order_line_id uuid,
    return_request_id uuid,
    rma_authorization_id uuid,
    exchange_request_id uuid,
    replacement_request_id uuid,
    warranty_claim_id uuid,
    link_type varchar(30) NOT NULL DEFAULT 'PRIMARY',
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, customer_service_case_id, sales_order_id, link_type),
    CONSTRAINT fk_doms_service_case_link_case
        FOREIGN KEY (tenant_id, customer_service_case_id)
        REFERENCES doms.customer_service_cases(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_service_case_link_order
        FOREIGN KEY (tenant_id, sales_order_id)
        REFERENCES doms.sales_orders(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_service_case_link_order_line
        FOREIGN KEY (tenant_id, sales_order_line_id)
        REFERENCES doms.sales_order_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_service_case_link_return
        FOREIGN KEY (tenant_id, return_request_id)
        REFERENCES doms.return_requests(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_service_case_link_rma
        FOREIGN KEY (tenant_id, rma_authorization_id)
        REFERENCES doms.rma_authorizations(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_service_case_link_exchange
        FOREIGN KEY (tenant_id, exchange_request_id)
        REFERENCES doms.exchange_requests(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_service_case_link_replacement
        FOREIGN KEY (tenant_id, replacement_request_id)
        REFERENCES doms.replacement_requests(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_service_case_link_warranty
        FOREIGN KEY (tenant_id, warranty_claim_id)
        REFERENCES doms.warranty_claims(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_service_case_link_type CHECK (
        link_type IN ('PRIMARY','RELATED','DUPLICATE','FOLLOW_UP','ESCALATION')
    )
);

CREATE TABLE IF NOT EXISTS doms.customer_service_interactions (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    customer_service_case_id uuid NOT NULL,
    interaction_sequence bigint NOT NULL,
    interaction_type varchar(30) NOT NULL,
    direction varchar(20) NOT NULL,
    channel varchar(20) NOT NULL,
    body_encrypted text,
    body_masked text NOT NULL,
    external_interaction_reference varchar(300),
    idempotency_key varchar(200) NOT NULL,
    actor_user_id uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, customer_service_case_id, interaction_sequence),
    UNIQUE (tenant_id, customer_service_case_id, idempotency_key),
    CONSTRAINT fk_doms_service_interaction_case
        FOREIGN KEY (tenant_id, customer_service_case_id)
        REFERENCES doms.customer_service_cases(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_service_interaction_values CHECK (
        interaction_sequence > 0 AND btrim(body_masked) <> '' AND btrim(idempotency_key) <> ''
    ),
    CONSTRAINT ck_doms_service_interaction_type CHECK (interaction_type IN (
        'MESSAGE','NOTE','CALL','EMAIL','CHAT','SMS','STATUS_CHANGE','ESCALATION','SYSTEM'
    )),
    CONSTRAINT ck_doms_service_interaction_direction CHECK (
        direction IN ('INBOUND','OUTBOUND','INTERNAL','SYSTEM')
    ),
    CONSTRAINT ck_doms_service_interaction_channel CHECK (
        channel IN ('PHONE','EMAIL','CHAT','SMS','WEB','APP','SOCIAL','INTERNAL','SYSTEM')
    ),
    CONSTRAINT ck_doms_service_interaction_json CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(metadata)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_service_interaction_external
    ON doms.customer_service_interactions (tenant_id, external_interaction_reference)
    WHERE external_interaction_reference IS NOT NULL;

CREATE TABLE IF NOT EXISTS doms.customer_service_tasks (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    customer_service_case_id uuid NOT NULL,
    task_no varchar(100) NOT NULL,
    task_type varchar(40) NOT NULL,
    task_status varchar(20) NOT NULL DEFAULT 'OPEN',
    priority varchar(20) NOT NULL DEFAULT 'NORMAL',
    assigned_to uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    due_at timestamptz,
    completed_at timestamptz,
    description_encrypted text,
    description_masked text NOT NULL,
    idempotency_key varchar(200) NOT NULL,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, task_no),
    UNIQUE (tenant_id, customer_service_case_id, idempotency_key),
    CONSTRAINT fk_doms_service_task_case
        FOREIGN KEY (tenant_id, customer_service_case_id)
        REFERENCES doms.customer_service_cases(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_service_task_values CHECK (
        btrim(task_no) <> '' AND btrim(description_masked) <> '' AND btrim(idempotency_key) <> ''
    ),
    CONSTRAINT ck_doms_service_task_type CHECK (task_type IN (
        'FOLLOW_UP','CONTACT_CUSTOMER','INVESTIGATE','APPROVE','REFUND','REPLACE',
        'EXCHANGE','WARRANTY','ESCALATE','OTHER'
    )),
    CONSTRAINT ck_doms_service_task_status CHECK (
        task_status IN ('OPEN','ASSIGNED','IN_PROGRESS','BLOCKED','COMPLETED','CANCELLED','EXPIRED')
    ),
    CONSTRAINT ck_doms_service_task_priority CHECK (
        priority IN ('LOW','NORMAL','HIGH','URGENT','CRITICAL')
    ),
    CONSTRAINT ck_doms_service_task_dates CHECK (
        (due_at IS NULL OR due_at >= created_at) AND
        (completed_at IS NULL OR completed_at >= created_at)
    )
);

CREATE TABLE IF NOT EXISTS doms.customer_service_sla_events (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    customer_service_case_id uuid NOT NULL,
    event_sequence bigint NOT NULL,
    sla_type varchar(30) NOT NULL,
    event_type varchar(30) NOT NULL,
    target_at timestamptz,
    achieved_at timestamptz,
    breached_at timestamptz,
    pause_seconds integer NOT NULL DEFAULT 0,
    reason_code varchar(100),
    idempotency_key varchar(200),
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, customer_service_case_id, event_sequence),
    CONSTRAINT fk_doms_service_sla_case
        FOREIGN KEY (tenant_id, customer_service_case_id)
        REFERENCES doms.customer_service_cases(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_service_sla_values CHECK (
        event_sequence > 0 AND pause_seconds >= 0
    ),
    CONSTRAINT ck_doms_service_sla_type CHECK (
        sla_type IN ('FIRST_RESPONSE','NEXT_RESPONSE','RESOLUTION','TASK','CUSTOM')
    ),
    CONSTRAINT ck_doms_service_sla_event_type CHECK (
        event_type IN ('STARTED','PAUSED','RESUMED','ACHIEVED','BREACHED','RESET','CANCELLED')
    ),
    CONSTRAINT ck_doms_service_sla_outcome CHECK (
        NOT (achieved_at IS NOT NULL AND breached_at IS NOT NULL)
    ),
    CONSTRAINT ck_doms_service_sla_json CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(metadata)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_service_sla_idempotency
    ON doms.customer_service_sla_events (tenant_id, customer_service_case_id, idempotency_key)
    WHERE idempotency_key IS NOT NULL;

CREATE TABLE IF NOT EXISTS doms.customer_service_adjustment_requests (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    adjustment_request_no varchar(100) NOT NULL,
    customer_service_case_id uuid NOT NULL,
    sales_order_id uuid NOT NULL,
    sales_order_line_id uuid,
    return_request_id uuid,
    adjustment_type varchar(30) NOT NULL,
    requested_amount numeric(24,6) NOT NULL DEFAULT 0,
    approved_amount numeric(24,6) NOT NULL DEFAULT 0,
    currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    adjustment_status varchar(20) NOT NULL DEFAULT 'REQUESTED',
    payment_refund_request_id uuid,
    requested_by uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    approved_by uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    requested_at timestamptz NOT NULL DEFAULT now(),
    approved_at timestamptz,
    completed_at timestamptz,
    reason_encrypted text,
    reason_masked text NOT NULL,
    idempotency_key varchar(200) NOT NULL,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, adjustment_request_no),
    UNIQUE (tenant_id, customer_service_case_id, idempotency_key),
    CONSTRAINT fk_doms_service_adjustment_case
        FOREIGN KEY (tenant_id, customer_service_case_id)
        REFERENCES doms.customer_service_cases(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_service_adjustment_order
        FOREIGN KEY (tenant_id, sales_order_id)
        REFERENCES doms.sales_orders(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_service_adjustment_order_line
        FOREIGN KEY (tenant_id, sales_order_line_id)
        REFERENCES doms.sales_order_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_service_adjustment_return
        FOREIGN KEY (tenant_id, return_request_id)
        REFERENCES doms.return_requests(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_service_adjustment_refund_request
        FOREIGN KEY (tenant_id, payment_refund_request_id)
        REFERENCES doms.payment_refund_requests(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_service_adjustment_values CHECK (
        btrim(adjustment_request_no) <> '' AND requested_amount >= 0 AND approved_amount >= 0 AND
        approved_amount <= requested_amount AND btrim(reason_masked) <> '' AND
        btrim(idempotency_key) <> ''
    ),
    CONSTRAINT ck_doms_service_adjustment_type CHECK (adjustment_type IN (
        'REFUND','PRICE_ADJUSTMENT','SHIPPING_REFUND','FEE_WAIVER','STORE_CREDIT',
        'GOODWILL','REPLACEMENT','EXCHANGE','OTHER'
    )),
    CONSTRAINT ck_doms_service_adjustment_status CHECK (adjustment_status IN (
        'REQUESTED','REVIEW','APPROVED','PARTIALLY_APPROVED','REJECTED','PROCESSING',
        'COMPLETED','FAILED','CANCELLED','EXPIRED'
    )),
    CONSTRAINT ck_doms_service_adjustment_approval CHECK (
        adjustment_status NOT IN ('APPROVED','PARTIALLY_APPROVED','PROCESSING','COMPLETED') OR
        (approved_by IS NOT NULL AND approved_at IS NOT NULL)
    ),
    CONSTRAINT ck_doms_service_adjustment_dates CHECK (
        (approved_at IS NULL OR approved_at >= requested_at) AND
        (completed_at IS NULL OR completed_at >= COALESCE(approved_at, requested_at))
    ),
    CONSTRAINT ck_doms_service_adjustment_json CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(metadata)
    )
);

-- -----------------------------------------------------------------------------
-- Core integrity and projection functions
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION doms.prevent_return_append_only_change()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    RAISE EXCEPTION '% is append-only; % is not permitted', TG_TABLE_NAME, TG_OP
        USING ERRCODE = '55000';
END;
$function$;

CREATE OR REPLACE FUNCTION doms.prevent_return_delete()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    RAISE EXCEPTION '% uses status/event transitions; % is not permitted', TG_TABLE_NAME, TG_OP
        USING ERRCODE = '55000';
END;
$function$;

CREATE OR REPLACE FUNCTION doms.enforce_policy_version_lifecycle()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    core_changed boolean := false;
    identity_changed boolean := false;
    transition_allowed boolean := false;
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.version_status <> 'DRAFT' THEN
            RAISE EXCEPTION '% must be created as DRAFT', TG_TABLE_NAME
                USING ERRCODE = '23514';
        END IF;
        RETURN NEW;
    END IF;

    IF TG_TABLE_NAME = 'return_policy_versions' THEN
        identity_changed :=
            OLD.id IS DISTINCT FROM NEW.id OR
            OLD.tenant_id IS DISTINCT FROM NEW.tenant_id OR
            OLD.return_policy_id IS DISTINCT FROM NEW.return_policy_id OR
            OLD.version_no IS DISTINCT FROM NEW.version_no OR
            OLD.created_at IS DISTINCT FROM NEW.created_at;
        core_changed :=
            OLD.tenant_id IS DISTINCT FROM NEW.tenant_id OR
            OLD.return_policy_id IS DISTINCT FROM NEW.return_policy_id OR
            OLD.version_no IS DISTINCT FROM NEW.version_no OR
            OLD.effective_from IS DISTINCT FROM NEW.effective_from OR
            OLD.effective_to IS DISTINCT FROM NEW.effective_to OR
            OLD.return_window_days IS DISTINCT FROM NEW.return_window_days OR
            OLD.window_start_event IS DISTINCT FROM NEW.window_start_event OR
            OLD.require_rma IS DISTINCT FROM NEW.require_rma OR
            OLD.require_receipt IS DISTINCT FROM NEW.require_receipt OR
            OLD.allow_partial_return IS DISTINCT FROM NEW.allow_partial_return OR
            OLD.allow_exchange IS DISTINCT FROM NEW.allow_exchange OR
            OLD.allow_replacement IS DISTINCT FROM NEW.allow_replacement OR
            OLD.allow_keep_item_refund IS DISTINCT FROM NEW.allow_keep_item_refund OR
            OLD.refund_shipping_mode IS DISTINCT FROM NEW.refund_shipping_mode OR
            OLD.restocking_fee_percent IS DISTINCT FROM NEW.restocking_fee_percent OR
            OLD.policy_config IS DISTINCT FROM NEW.policy_config OR
            OLD.checksum_sha256 IS DISTINCT FROM NEW.checksum_sha256 OR
            OLD.published_by IS DISTINCT FROM NEW.published_by OR
            OLD.published_at IS DISTINCT FROM NEW.published_at;
    ELSE
        identity_changed :=
            OLD.id IS DISTINCT FROM NEW.id OR
            OLD.tenant_id IS DISTINCT FROM NEW.tenant_id OR
            OLD.warranty_policy_id IS DISTINCT FROM NEW.warranty_policy_id OR
            OLD.version_no IS DISTINCT FROM NEW.version_no OR
            OLD.created_at IS DISTINCT FROM NEW.created_at;
        core_changed :=
            OLD.tenant_id IS DISTINCT FROM NEW.tenant_id OR
            OLD.warranty_policy_id IS DISTINCT FROM NEW.warranty_policy_id OR
            OLD.version_no IS DISTINCT FROM NEW.version_no OR
            OLD.effective_from IS DISTINCT FROM NEW.effective_from OR
            OLD.effective_to IS DISTINCT FROM NEW.effective_to OR
            OLD.warranty_duration_months IS DISTINCT FROM NEW.warranty_duration_months OR
            OLD.duration_start_event IS DISTINCT FROM NEW.duration_start_event OR
            OLD.require_registration IS DISTINCT FROM NEW.require_registration OR
            OLD.require_serial IS DISTINCT FROM NEW.require_serial OR
            OLD.allow_repair IS DISTINCT FROM NEW.allow_repair OR
            OLD.allow_replacement IS DISTINCT FROM NEW.allow_replacement OR
            OLD.allow_refund IS DISTINCT FROM NEW.allow_refund OR
            OLD.coverage_config IS DISTINCT FROM NEW.coverage_config OR
            OLD.checksum_sha256 IS DISTINCT FROM NEW.checksum_sha256 OR
            OLD.published_by IS DISTINCT FROM NEW.published_by OR
            OLD.published_at IS DISTINCT FROM NEW.published_at;
    END IF;

    IF identity_changed THEN
        RAISE EXCEPTION '% identity, ownership, version number, and creation time are immutable',
            TG_TABLE_NAME USING ERRCODE = '55000';
    END IF;

    IF OLD.version_status <> 'DRAFT' AND core_changed THEN
        RAISE EXCEPTION '% core fields are immutable after publication', TG_TABLE_NAME
            USING ERRCODE = '55000';
    END IF;

    IF OLD.version_status = NEW.version_status THEN
        RETURN NEW;
    END IF;
    transition_allowed :=
        (OLD.version_status = 'DRAFT' AND NEW.version_status IN ('PUBLISHED','ACTIVE')) OR
        (OLD.version_status = 'PUBLISHED' AND
            NEW.version_status IN ('ACTIVE','SUPERSEDED','RETIRED')) OR
        (OLD.version_status = 'ACTIVE' AND
            NEW.version_status IN ('SUPERSEDED','RETIRED'));
    IF NOT transition_allowed THEN
        RAISE EXCEPTION 'Illegal % lifecycle transition: % -> %',
            TG_TABLE_NAME, OLD.version_status, NEW.version_status
            USING ERRCODE = '23514';
    END IF;
    IF NEW.version_status <> 'DRAFT' AND (
        NEW.published_by IS NULL OR NEW.published_at IS NULL
    ) THEN
        RAISE EXCEPTION 'Published policy version requires publisher and publication time'
            USING ERRCODE = '23514';
    END IF;
    IF NEW.published_at IS NOT NULL AND NEW.published_at > now() THEN
        RAISE EXCEPTION 'Policy publication time cannot be in the future'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.guard_policy_version_delete()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    IF OLD.version_status <> 'DRAFT' THEN
        RAISE EXCEPTION '% is immutable after publication and cannot be deleted',
            TG_TABLE_NAME USING ERRCODE = '55000';
    END IF;
    RETURN OLD;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.enforce_return_policy_rule_draft()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    target_tenant_id uuid;
    target_version_id uuid;
    parent_status varchar(20);
BEGIN
    IF TG_OP = 'UPDATE' AND (
        OLD.id IS DISTINCT FROM NEW.id OR
        OLD.tenant_id IS DISTINCT FROM NEW.tenant_id OR
        OLD.return_policy_version_id IS DISTINCT FROM NEW.return_policy_version_id
    ) THEN
        RAISE EXCEPTION 'Policy rule identity and owning version are immutable'
            USING ERRCODE = '55000';
    END IF;
    target_tenant_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.tenant_id ELSE NEW.tenant_id END;
    target_version_id := CASE WHEN TG_OP = 'DELETE'
        THEN OLD.return_policy_version_id ELSE NEW.return_policy_version_id END;
    SELECT version_status INTO parent_status
      FROM doms.return_policy_versions
     WHERE tenant_id = target_tenant_id
       AND id = target_version_id
     FOR UPDATE;
    IF parent_status IS NULL OR parent_status <> 'DRAFT' THEN
        RAISE EXCEPTION 'Return policy rules are mutable only while their version is DRAFT'
            USING ERRCODE = '55000';
    END IF;
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.validate_return_source_scope()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    header_order_id uuid;
    source_row record;
    eligibility_row record;
BEGIN
    IF TG_TABLE_NAME = 'return_eligibility_check_lines' THEN
        SELECT sales_order_id INTO header_order_id
          FROM doms.return_eligibility_checks
         WHERE tenant_id = NEW.tenant_id
           AND id = NEW.return_eligibility_check_id;
    ELSE
        SELECT sales_order_id INTO header_order_id
          FROM doms.return_requests
         WHERE tenant_id = NEW.tenant_id
           AND id = NEW.return_request_id;
    END IF;

    SELECT fulfillment_order.sales_order_id,
           fulfillment_line.sales_order_line_id,
           shipment_line.id AS shipment_line_id,
           shipment_line.item_id,
           shipment_line.uom_code,
           shipment_line.shipped_quantity,
           package_item.id AS package_item_id,
           package_item.packed_quantity
      INTO source_row
      FROM doms.package_items package_item
      JOIN doms.shipment_lines shipment_line
        ON shipment_line.tenant_id = package_item.tenant_id
       AND shipment_line.id = package_item.shipment_line_id
      JOIN doms.fulfillment_order_lines fulfillment_line
        ON fulfillment_line.tenant_id = shipment_line.tenant_id
       AND fulfillment_line.id = shipment_line.fulfillment_order_line_id
      JOIN doms.fulfillment_orders fulfillment_order
        ON fulfillment_order.tenant_id = fulfillment_line.tenant_id
       AND fulfillment_order.id = fulfillment_line.fulfillment_order_id
     WHERE package_item.tenant_id = NEW.tenant_id
       AND package_item.id = NEW.package_item_id
     FOR UPDATE OF package_item, shipment_line;

    IF NOT FOUND OR header_order_id IS NULL
       OR source_row.sales_order_id <> header_order_id
       OR source_row.sales_order_line_id <> NEW.sales_order_line_id
       OR source_row.shipment_line_id <> NEW.shipment_line_id
       OR source_row.package_item_id <> NEW.package_item_id
       OR source_row.item_id <> NEW.item_id
       OR source_row.uom_code <> NEW.uom_code THEN
        RAISE EXCEPTION 'Return source order line, shipment line, package item, item, or UOM mismatch'
            USING ERRCODE = '23514';
    END IF;

    IF NEW.requested_quantity > LEAST(
        source_row.shipped_quantity, source_row.packed_quantity
    ) THEN
        RAISE EXCEPTION 'Requested return quantity exceeds the shipped package-item quantity'
            USING ERRCODE = '23514';
    END IF;

    IF TG_TABLE_NAME = 'return_request_lines' THEN
        IF NEW.return_eligibility_result_id IS NOT NULL THEN
            SELECT result.eligible_quantity,
                   check_line.sales_order_line_id,
                   check_line.shipment_line_id,
                   check_line.package_item_id,
                   check_line.item_id,
                   check_line.uom_code,
                   result.is_final
              INTO eligibility_row
              FROM doms.return_eligibility_results result
              JOIN doms.return_eligibility_check_lines check_line
                ON check_line.tenant_id = result.tenant_id
               AND check_line.id = result.return_eligibility_check_line_id
             WHERE result.tenant_id = NEW.tenant_id
               AND result.id = NEW.return_eligibility_result_id;
            IF NOT FOUND OR NOT eligibility_row.is_final
               OR eligibility_row.sales_order_line_id <> NEW.sales_order_line_id
               OR eligibility_row.shipment_line_id <> NEW.shipment_line_id
               OR eligibility_row.package_item_id <> NEW.package_item_id
               OR eligibility_row.item_id <> NEW.item_id
               OR eligibility_row.uom_code <> NEW.uom_code
               OR NEW.eligible_quantity > eligibility_row.eligible_quantity THEN
                RAISE EXCEPTION 'Return request line differs from its final eligibility result'
                    USING ERRCODE = '23514';
            END IF;
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.validate_return_eligibility_result()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    requested_qty numeric(24,8);
BEGIN
    SELECT requested_quantity INTO requested_qty
      FROM doms.return_eligibility_check_lines
     WHERE tenant_id = NEW.tenant_id
       AND id = NEW.return_eligibility_check_line_id;
    IF requested_qty IS NULL OR NEW.eligible_quantity > requested_qty THEN
        RAISE EXCEPTION 'Eligibility result exceeds requested return quantity'
            USING ERRCODE = '23514';
    END IF;
    IF NEW.result_code = 'INELIGIBLE' AND NEW.eligible_quantity <> 0 THEN
        RAISE EXCEPTION 'Ineligible result must have zero eligible quantity'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.validate_rma_authorization_line()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    source_row record;
    request_line_row doms.return_request_lines%ROWTYPE;
    rma_return_request_id uuid;
    rma_authorization_status varchar(30);
    other_authorized numeric(24,8);
    line_authorized numeric(24,8);
    candidate_authorized numeric(24,8);
    shipped_capacity numeric(24,8);
    override_complete boolean;
BEGIN
    IF TG_OP = 'UPDATE' AND (
        OLD.tenant_id IS DISTINCT FROM NEW.tenant_id OR
        OLD.rma_authorization_id IS DISTINCT FROM NEW.rma_authorization_id OR
        OLD.return_request_line_id IS DISTINCT FROM NEW.return_request_line_id OR
        OLD.sales_order_line_id IS DISTINCT FROM NEW.sales_order_line_id OR
        OLD.shipment_line_id IS DISTINCT FROM NEW.shipment_line_id OR
        OLD.package_item_id IS DISTINCT FROM NEW.package_item_id OR
        OLD.item_id IS DISTINCT FROM NEW.item_id OR
        OLD.authorized_quantity IS DISTINCT FROM NEW.authorized_quantity OR
        OLD.uom_code IS DISTINCT FROM NEW.uom_code OR
        OLD.idempotency_key IS DISTINCT FROM NEW.idempotency_key
    ) THEN
        RAISE EXCEPTION 'RMA source identity and authorized quantity are immutable'
            USING ERRCODE = '55000';
    END IF;

    SELECT return_request_id, authorization_status
      INTO rma_return_request_id, rma_authorization_status
      FROM doms.rma_authorizations
     WHERE tenant_id = NEW.tenant_id
       AND id = NEW.rma_authorization_id;
    SELECT * INTO request_line_row
      FROM doms.return_request_lines
     WHERE tenant_id = NEW.tenant_id
       AND id = NEW.return_request_line_id
     FOR UPDATE;

    SELECT shipment_line.id AS shipment_line_id,
           shipment_line.item_id,
           shipment_line.uom_code,
           shipment_line.shipped_quantity,
           fulfillment_line.sales_order_line_id,
           package_item.id AS package_item_id,
           package_item.packed_quantity
      INTO source_row
      FROM doms.package_items package_item
      JOIN doms.shipment_lines shipment_line
        ON shipment_line.tenant_id = package_item.tenant_id
       AND shipment_line.id = package_item.shipment_line_id
      JOIN doms.fulfillment_order_lines fulfillment_line
        ON fulfillment_line.tenant_id = shipment_line.tenant_id
       AND fulfillment_line.id = shipment_line.fulfillment_order_line_id
     WHERE package_item.tenant_id = NEW.tenant_id
       AND package_item.id = NEW.package_item_id
     FOR UPDATE OF package_item, shipment_line;

    IF rma_return_request_id IS NULL OR request_line_row.id IS NULL OR NOT FOUND
       OR request_line_row.return_request_id <> rma_return_request_id
       OR request_line_row.sales_order_line_id <> NEW.sales_order_line_id
       OR request_line_row.shipment_line_id <> NEW.shipment_line_id
       OR request_line_row.package_item_id <> NEW.package_item_id
       OR request_line_row.item_id <> NEW.item_id
       OR request_line_row.uom_code <> NEW.uom_code
       OR source_row.sales_order_line_id <> NEW.sales_order_line_id
       OR source_row.shipment_line_id <> NEW.shipment_line_id
       OR source_row.package_item_id <> NEW.package_item_id
       OR source_row.item_id <> NEW.item_id
       OR source_row.uom_code <> NEW.uom_code THEN
        RAISE EXCEPTION 'RMA line differs from its return request or shipped package item'
            USING ERRCODE = '23514';
    END IF;

    override_complete := NEW.override_approved_by IS NOT NULL
                         AND NEW.override_approved_at IS NOT NULL
                         AND btrim(COALESCE(NEW.override_reason, '')) <> '';
    IF override_complete AND NEW.override_approved_at > now() THEN
        RAISE EXCEPTION 'RMA override approval cannot be in the future'
            USING ERRCODE = '23514';
    END IF;
    IF NEW.authorized_quantity > request_line_row.eligible_quantity
       AND NOT override_complete THEN
        RAISE EXCEPTION 'RMA authorization exceeds policy-eligible quantity without approval'
            USING ERRCODE = '23514';
    END IF;
    IF NEW.authorized_quantity > request_line_row.requested_quantity THEN
        RAISE EXCEPTION 'RMA authorization exceeds requested return quantity'
            USING ERRCODE = '23514';
    END IF;

    shipped_capacity := LEAST(source_row.shipped_quantity, source_row.packed_quantity);
    candidate_authorized := CASE
        WHEN NEW.line_status IN ('REJECTED','CANCELLED','EXPIRED')
          OR rma_authorization_status IN ('REJECTED','CANCELLED','EXPIRED') THEN 0
        ELSE NEW.authorized_quantity
    END;
    SELECT COALESCE(sum(line.authorized_quantity), 0)
      INTO other_authorized
      FROM doms.rma_authorization_lines line
      JOIN doms.rma_authorizations header
        ON header.tenant_id = line.tenant_id
       AND header.id = line.rma_authorization_id
     WHERE line.tenant_id = NEW.tenant_id
       AND line.package_item_id = NEW.package_item_id
       AND line.id <> NEW.id
       AND line.line_status NOT IN ('REJECTED','CANCELLED','EXPIRED')
       AND header.authorization_status NOT IN ('REJECTED','CANCELLED','EXPIRED');
    IF other_authorized + candidate_authorized > shipped_capacity THEN
        RAISE EXCEPTION 'RMA authorized quantity % exceeds shipped package capacity %',
            other_authorized + candidate_authorized, shipped_capacity
            USING ERRCODE = '23514';
    END IF;

    SELECT COALESCE(sum(line.authorized_quantity), 0)
      INTO line_authorized
      FROM doms.rma_authorization_lines line
      JOIN doms.rma_authorizations header
        ON header.tenant_id = line.tenant_id
       AND header.id = line.rma_authorization_id
     WHERE line.tenant_id = NEW.tenant_id
       AND line.return_request_line_id = NEW.return_request_line_id
       AND line.id <> NEW.id
       AND line.line_status NOT IN ('REJECTED','CANCELLED','EXPIRED')
       AND header.authorization_status NOT IN ('REJECTED','CANCELLED','EXPIRED');
    IF line_authorized + candidate_authorized > request_line_row.requested_quantity THEN
        RAISE EXCEPTION 'RMA authorizations exceed return-request line quantity'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.project_rma_authorization_line()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    authorized_total numeric(24,8);
BEGIN
    SELECT COALESCE(sum(line.authorized_quantity), 0)
      INTO authorized_total
      FROM doms.rma_authorization_lines line
      JOIN doms.rma_authorizations header
        ON header.tenant_id = line.tenant_id
       AND header.id = line.rma_authorization_id
     WHERE line.tenant_id = NEW.tenant_id
       AND line.return_request_line_id = NEW.return_request_line_id
       AND line.line_status NOT IN ('REJECTED','CANCELLED','EXPIRED')
       AND header.authorization_status NOT IN ('REJECTED','CANCELLED','EXPIRED');

    UPDATE doms.return_request_lines
       SET authorized_quantity = authorized_total,
           line_status = CASE WHEN authorized_total > 0 THEN 'AUTHORIZED' ELSE line_status END,
           row_version = row_version + 1,
           updated_at = now()
     WHERE tenant_id = NEW.tenant_id
       AND id = NEW.return_request_line_id;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.validate_return_receipt_line()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    rma_line doms.rma_authorization_lines%ROWTYPE;
    receipt_rma_id uuid;
    shipment_line_rma_id uuid;
    other_received numeric(24,8);
BEGIN
    SELECT rma_authorization_id INTO receipt_rma_id
      FROM doms.return_receipts
     WHERE tenant_id = NEW.tenant_id
       AND id = NEW.return_receipt_id;
    SELECT * INTO rma_line
      FROM doms.rma_authorization_lines
     WHERE tenant_id = NEW.tenant_id
       AND id = NEW.rma_authorization_line_id
     FOR UPDATE;
    IF receipt_rma_id IS NULL OR rma_line.id IS NULL
       OR receipt_rma_id <> rma_line.rma_authorization_id
       OR NEW.item_id <> rma_line.item_id
       OR NEW.uom_code <> rma_line.uom_code THEN
        RAISE EXCEPTION 'Return receipt line differs from its RMA authorization'
            USING ERRCODE = '23514';
    END IF;

    IF NEW.return_shipment_line_id IS NOT NULL THEN
        SELECT shipment.rma_authorization_id
          INTO shipment_line_rma_id
          FROM doms.return_shipment_lines shipment_line
          JOIN doms.return_shipments shipment
            ON shipment.tenant_id = shipment_line.tenant_id
           AND shipment.id = shipment_line.return_shipment_id
         WHERE shipment_line.tenant_id = NEW.tenant_id
           AND shipment_line.id = NEW.return_shipment_line_id
           AND shipment_line.rma_authorization_line_id = NEW.rma_authorization_line_id
           AND shipment_line.item_id = NEW.item_id
           AND shipment_line.uom_code = NEW.uom_code;
        IF shipment_line_rma_id IS NULL OR shipment_line_rma_id <> receipt_rma_id THEN
            RAISE EXCEPTION 'Return receipt line differs from its return shipment line'
                USING ERRCODE = '23514';
        END IF;
    END IF;

    SELECT COALESCE(sum(line.received_quantity), 0)
      INTO other_received
      FROM doms.return_receipt_lines line
      JOIN doms.return_receipts receipt
        ON receipt.tenant_id = line.tenant_id
       AND receipt.id = line.return_receipt_id
     WHERE line.tenant_id = NEW.tenant_id
       AND line.rma_authorization_line_id = NEW.rma_authorization_line_id
       AND line.id <> NEW.id
       AND receipt.receipt_status <> 'VOID';
    IF other_received + NEW.received_quantity > rma_line.authorized_quantity THEN
        RAISE EXCEPTION 'Received quantity % exceeds RMA authorized quantity %',
            other_received + NEW.received_quantity, rma_line.authorized_quantity
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.project_return_receipt_line()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    received_total numeric(24,8);
    request_received_total numeric(24,8);
    request_line_id uuid;
BEGIN
    SELECT COALESCE(sum(line.received_quantity), 0)
      INTO received_total
      FROM doms.return_receipt_lines line
      JOIN doms.return_receipts receipt
        ON receipt.tenant_id = line.tenant_id
       AND receipt.id = line.return_receipt_id
     WHERE line.tenant_id = NEW.tenant_id
       AND line.rma_authorization_line_id = NEW.rma_authorization_line_id
       AND receipt.receipt_status <> 'VOID';

    UPDATE doms.rma_authorization_lines
       SET received_quantity = received_total,
           line_status = CASE WHEN received_total = authorized_quantity THEN 'RECEIVED'
                              WHEN received_total > 0 THEN 'PARTIALLY_RECEIVED'
                              ELSE line_status END,
           row_version = row_version + 1,
           updated_at = now()
     WHERE tenant_id = NEW.tenant_id
       AND id = NEW.rma_authorization_line_id
     RETURNING return_request_line_id INTO request_line_id;

    SELECT COALESCE(sum(receipt_line.received_quantity), 0)
      INTO request_received_total
      FROM doms.return_receipt_lines receipt_line
      JOIN doms.return_receipts receipt
        ON receipt.tenant_id = receipt_line.tenant_id
       AND receipt.id = receipt_line.return_receipt_id
      JOIN doms.rma_authorization_lines authorized_line
        ON authorized_line.tenant_id = receipt_line.tenant_id
       AND authorized_line.id = receipt_line.rma_authorization_line_id
     WHERE receipt_line.tenant_id = NEW.tenant_id
       AND authorized_line.return_request_line_id = request_line_id
       AND receipt.receipt_status <> 'VOID';
    UPDATE doms.return_request_lines
       SET received_quantity = request_received_total,
           line_status = CASE WHEN request_received_total = authorized_quantity THEN 'RECEIVED'
                              WHEN request_received_total > 0 THEN 'PARTIALLY_RECEIVED'
                              ELSE line_status END,
           row_version = row_version + 1,
           updated_at = now()
     WHERE tenant_id = NEW.tenant_id
       AND id = request_line_id;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.validate_return_inspection()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    receipt_line doms.return_receipt_lines%ROWTYPE;
    rma_line doms.rma_authorization_lines%ROWTYPE;
    other_inspected numeric(24,8);
BEGIN
    SELECT * INTO receipt_line
      FROM doms.return_receipt_lines
     WHERE tenant_id = NEW.tenant_id
       AND id = NEW.return_receipt_line_id
     FOR UPDATE;
    SELECT * INTO rma_line
      FROM doms.rma_authorization_lines
     WHERE tenant_id = NEW.tenant_id
       AND id = NEW.rma_authorization_line_id
     FOR UPDATE;

    IF receipt_line.id IS NULL OR rma_line.id IS NULL
       OR receipt_line.rma_authorization_line_id <> NEW.rma_authorization_line_id
       OR receipt_line.item_id <> rma_line.item_id
       OR receipt_line.uom_code <> rma_line.uom_code THEN
        RAISE EXCEPTION 'Return inspection differs from its receipt or RMA line'
            USING ERRCODE = '23514';
    END IF;

    SELECT COALESCE(sum(inspected_quantity), 0)
      INTO other_inspected
      FROM doms.return_inspections
     WHERE tenant_id = NEW.tenant_id
       AND return_receipt_line_id = NEW.return_receipt_line_id
       AND id <> NEW.id
       AND inspection_status <> 'VOID';
    IF NEW.inspection_status <> 'VOID'
       AND other_inspected + NEW.inspected_quantity > receipt_line.received_quantity THEN
        RAISE EXCEPTION 'Inspected quantity % exceeds received quantity %',
            other_inspected + NEW.inspected_quantity, receipt_line.received_quantity
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.project_return_inspection()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    inspected_total numeric(24,8);
    request_inspected_total numeric(24,8);
    request_line_id uuid;
BEGIN
    SELECT COALESCE(sum(inspection.inspected_quantity), 0)
      INTO inspected_total
      FROM doms.return_inspections inspection
     WHERE inspection.tenant_id = NEW.tenant_id
       AND inspection.rma_authorization_line_id = NEW.rma_authorization_line_id
       AND inspection.inspection_status <> 'VOID';

    UPDATE doms.rma_authorization_lines
       SET inspected_quantity = inspected_total,
           line_status = CASE WHEN inspected_total = received_quantity AND inspected_total > 0
                                  THEN 'INSPECTED'
                              ELSE line_status END,
           row_version = row_version + 1,
           updated_at = now()
     WHERE tenant_id = NEW.tenant_id
       AND id = NEW.rma_authorization_line_id
     RETURNING return_request_line_id INTO request_line_id;

    SELECT COALESCE(sum(inspection.inspected_quantity), 0)
      INTO request_inspected_total
      FROM doms.return_inspections inspection
      JOIN doms.rma_authorization_lines authorized_line
        ON authorized_line.tenant_id = inspection.tenant_id
       AND authorized_line.id = inspection.rma_authorization_line_id
     WHERE inspection.tenant_id = NEW.tenant_id
       AND authorized_line.return_request_line_id = request_line_id
       AND inspection.inspection_status <> 'VOID';
    UPDATE doms.return_request_lines
       SET inspected_quantity = request_inspected_total,
           line_status = CASE WHEN request_inspected_total = received_quantity
                                   AND request_inspected_total > 0
                                  THEN 'INSPECTED'
                              ELSE line_status END,
           row_version = row_version + 1,
           updated_at = now()
     WHERE tenant_id = NEW.tenant_id
       AND id = request_line_id;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.validate_return_disposition()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    inspection doms.return_inspections%ROWTYPE;
    rma_line doms.rma_authorization_lines%ROWTYPE;
    request_line doms.return_request_lines%ROWTYPE;
    result_row doms.return_eligibility_results%ROWTYPE;
    other_dispositioned numeric(24,8);
    other_eligible_quantity numeric(24,8);
    other_eligible_amount numeric(24,6);
BEGIN
    SELECT * INTO inspection
      FROM doms.return_inspections
     WHERE tenant_id = NEW.tenant_id
       AND id = NEW.return_inspection_id
     FOR UPDATE;
    SELECT * INTO rma_line
      FROM doms.rma_authorization_lines
     WHERE tenant_id = NEW.tenant_id
       AND id = NEW.rma_authorization_line_id
     FOR UPDATE;
    IF inspection.id IS NULL OR rma_line.id IS NULL
       OR inspection.inspection_status = 'VOID'
       OR inspection.rma_authorization_line_id <> NEW.rma_authorization_line_id THEN
        RAISE EXCEPTION 'Return disposition differs from an active inspection or RMA line'
            USING ERRCODE = '23514';
    END IF;

    SELECT COALESCE(sum(disposition_quantity), 0)
      INTO other_dispositioned
      FROM doms.return_dispositions
     WHERE tenant_id = NEW.tenant_id
       AND return_inspection_id = NEW.return_inspection_id
       AND id <> NEW.id;
    IF other_dispositioned + NEW.disposition_quantity > inspection.inspected_quantity THEN
        RAISE EXCEPTION 'Dispositioned quantity % exceeds inspected quantity %',
            other_dispositioned + NEW.disposition_quantity, inspection.inspected_quantity
            USING ERRCODE = '23514';
    END IF;

    SELECT * INTO request_line
      FROM doms.return_request_lines
     WHERE tenant_id = NEW.tenant_id
       AND id = rma_line.return_request_line_id
     FOR UPDATE;
    IF NEW.currency_code <> request_line.currency_code THEN
        RAISE EXCEPTION 'Disposition currency differs from the return-request line'
            USING ERRCODE = '23514';
    END IF;

    IF NEW.refund_eligible_quantity > 0 OR NEW.refund_eligible_amount > 0 THEN
        IF request_line.return_eligibility_result_id IS NULL THEN
            RAISE EXCEPTION 'Refund eligibility requires a final policy-eligibility result'
                USING ERRCODE = '23514';
        END IF;
        SELECT * INTO result_row
          FROM doms.return_eligibility_results
         WHERE tenant_id = NEW.tenant_id
           AND id = request_line.return_eligibility_result_id;
        IF result_row.id IS NULL OR NOT result_row.is_final
           OR result_row.result_code NOT IN ('ELIGIBLE','PARTIAL','EXCEPTION')
           OR result_row.currency_code <> NEW.currency_code THEN
            RAISE EXCEPTION 'Disposition does not have a compatible final policy result'
                USING ERRCODE = '23514';
        END IF;

        SELECT COALESCE(sum(disposition.refund_eligible_quantity), 0),
               COALESCE(sum(disposition.refund_eligible_amount), 0)
          INTO other_eligible_quantity, other_eligible_amount
          FROM doms.return_dispositions disposition
          JOIN doms.rma_authorization_lines authorized_line
            ON authorized_line.tenant_id = disposition.tenant_id
           AND authorized_line.id = disposition.rma_authorization_line_id
         WHERE disposition.tenant_id = NEW.tenant_id
           AND authorized_line.return_request_line_id = request_line.id
           AND disposition.id <> NEW.id;
        IF other_eligible_quantity + NEW.refund_eligible_quantity > result_row.eligible_quantity
           OR other_eligible_amount + NEW.refund_eligible_amount > result_row.maximum_refund_amount THEN
            RAISE EXCEPTION 'Disposition refund eligibility exceeds policy quantity or amount'
                USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.project_return_disposition()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    rma_dispositioned numeric(24,8);
    rma_refund_eligible numeric(24,8);
    request_line_id uuid;
    request_dispositioned numeric(24,8);
    request_refund_eligible numeric(24,8);
    request_refund_amount numeric(24,6);
BEGIN
    SELECT COALESCE(sum(disposition_quantity), 0),
           COALESCE(sum(refund_eligible_quantity), 0)
      INTO rma_dispositioned, rma_refund_eligible
      FROM doms.return_dispositions
     WHERE tenant_id = NEW.tenant_id
       AND rma_authorization_line_id = NEW.rma_authorization_line_id;

    UPDATE doms.rma_authorization_lines
       SET dispositioned_quantity = rma_dispositioned,
           refund_eligible_quantity = rma_refund_eligible,
           line_status = CASE WHEN rma_dispositioned = inspected_quantity AND rma_dispositioned > 0
                                  THEN 'DISPOSITIONED'
                              ELSE line_status END,
           row_version = row_version + 1,
           updated_at = now()
     WHERE tenant_id = NEW.tenant_id
       AND id = NEW.rma_authorization_line_id
     RETURNING return_request_line_id INTO request_line_id;

    SELECT COALESCE(sum(disposition.disposition_quantity), 0),
           COALESCE(sum(disposition.refund_eligible_quantity), 0),
           COALESCE(sum(disposition.refund_eligible_amount), 0)
      INTO request_dispositioned, request_refund_eligible, request_refund_amount
      FROM doms.return_dispositions disposition
      JOIN doms.rma_authorization_lines authorized_line
        ON authorized_line.tenant_id = disposition.tenant_id
       AND authorized_line.id = disposition.rma_authorization_line_id
     WHERE disposition.tenant_id = NEW.tenant_id
       AND authorized_line.return_request_line_id = request_line_id;

    UPDATE doms.return_request_lines
       SET dispositioned_quantity = request_dispositioned,
           refund_eligible_quantity = request_refund_eligible,
           refund_eligible_amount = request_refund_amount,
           line_status = CASE WHEN request_dispositioned = inspected_quantity
                                   AND request_dispositioned > 0 THEN 'DISPOSITIONED'
                              ELSE line_status END,
           row_version = row_version + 1,
           updated_at = now()
     WHERE tenant_id = NEW.tenant_id
       AND id = request_line_id;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.validate_return_refund_calculation_line()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    calculation doms.return_refund_calculations%ROWTYPE;
    disposition doms.return_dispositions%ROWTYPE;
    rma_line doms.rma_authorization_lines%ROWTYPE;
    request_line doms.return_request_lines%ROWTYPE;
    request_policy_version_id uuid;
    other_quantity numeric(24,8);
    other_amount numeric(24,6);
BEGIN
    IF TG_OP = 'UPDATE' AND (
        OLD.tenant_id IS DISTINCT FROM NEW.tenant_id OR
        OLD.return_refund_calculation_id IS DISTINCT FROM NEW.return_refund_calculation_id OR
        OLD.return_request_line_id IS DISTINCT FROM NEW.return_request_line_id OR
        OLD.rma_authorization_line_id IS DISTINCT FROM NEW.rma_authorization_line_id OR
        OLD.return_disposition_id IS DISTINCT FROM NEW.return_disposition_id OR
        OLD.eligible_quantity IS DISTINCT FROM NEW.eligible_quantity OR
        OLD.requested_refund_quantity IS DISTINCT FROM NEW.requested_refund_quantity OR
        OLD.unit_refund_amount IS DISTINCT FROM NEW.unit_refund_amount OR
        OLD.principal_amount IS DISTINCT FROM NEW.principal_amount OR
        OLD.tax_amount IS DISTINCT FROM NEW.tax_amount OR
        OLD.shipping_amount IS DISTINCT FROM NEW.shipping_amount OR
        OLD.fee_deduction_amount IS DISTINCT FROM NEW.fee_deduction_amount OR
        OLD.total_refund_amount IS DISTINCT FROM NEW.total_refund_amount OR
        OLD.currency_code IS DISTINCT FROM NEW.currency_code
    ) THEN
        RAISE EXCEPTION 'Approved refund entitlement fields are immutable; supersede the calculation instead'
            USING ERRCODE = '55000';
    END IF;

    SELECT * INTO calculation
      FROM doms.return_refund_calculations
     WHERE tenant_id = NEW.tenant_id
       AND id = NEW.return_refund_calculation_id
     FOR UPDATE;
    SELECT * INTO disposition
      FROM doms.return_dispositions
     WHERE tenant_id = NEW.tenant_id
       AND id = NEW.return_disposition_id
     FOR UPDATE;
    SELECT * INTO rma_line
      FROM doms.rma_authorization_lines
     WHERE tenant_id = NEW.tenant_id
       AND id = NEW.rma_authorization_line_id
     FOR UPDATE;
    SELECT * INTO request_line
      FROM doms.return_request_lines
     WHERE tenant_id = NEW.tenant_id
       AND id = NEW.return_request_line_id
     FOR UPDATE;

    SELECT return_policy_version_id INTO request_policy_version_id
      FROM doms.return_requests
     WHERE tenant_id = NEW.tenant_id
       AND id = request_line.return_request_id;
    IF calculation.id IS NULL OR disposition.id IS NULL OR rma_line.id IS NULL
       OR request_line.id IS NULL
       OR calculation.return_request_id <> request_line.return_request_id
       OR calculation.return_policy_version_id <> request_policy_version_id
       OR disposition.rma_authorization_line_id <> NEW.rma_authorization_line_id
       OR rma_line.return_request_line_id <> NEW.return_request_line_id
       OR calculation.currency_code <> NEW.currency_code
       OR disposition.currency_code <> NEW.currency_code
       OR request_line.currency_code <> NEW.currency_code THEN
        RAISE EXCEPTION 'Refund calculation line differs from its return, RMA, disposition, policy, or currency'
            USING ERRCODE = '23514';
    END IF;
    IF NEW.eligible_quantity <> disposition.refund_eligible_quantity
       OR NEW.requested_refund_quantity > disposition.refund_eligible_quantity
       OR NEW.total_refund_amount > disposition.refund_eligible_amount THEN
        RAISE EXCEPTION 'Refund calculation exceeds disposition entitlement'
            USING ERRCODE = '23514';
    END IF;

    SELECT COALESCE(sum(requested_refund_quantity), 0),
           COALESCE(sum(total_refund_amount), 0)
      INTO other_quantity, other_amount
      FROM doms.return_refund_calculation_lines
     WHERE tenant_id = NEW.tenant_id
       AND return_refund_calculation_id = NEW.return_refund_calculation_id
       AND return_request_line_id = NEW.return_request_line_id
       AND id <> NEW.id;
    IF other_quantity + NEW.requested_refund_quantity > request_line.refund_eligible_quantity
       OR other_amount + NEW.total_refund_amount > request_line.refund_eligible_amount THEN
        RAISE EXCEPTION 'Refund calculation exceeds policy entitlement for the return line'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.validate_return_refund_calculation_total()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    calculation_id uuid;
    calculation doms.return_refund_calculations%ROWTYPE;
    line_count bigint;
    line_principal numeric(24,6);
    line_tax numeric(24,6);
    line_shipping numeric(24,6);
    line_fee numeric(24,6);
    line_total numeric(24,6);
BEGIN
    IF TG_TABLE_NAME = 'return_refund_calculations' THEN
        calculation_id := COALESCE(NEW.id, OLD.id);
    ELSE
        calculation_id := COALESCE(NEW.return_refund_calculation_id,
                                   OLD.return_refund_calculation_id);
    END IF;
    SELECT * INTO calculation
      FROM doms.return_refund_calculations
     WHERE tenant_id = COALESCE(NEW.tenant_id, OLD.tenant_id)
       AND id = calculation_id
     FOR UPDATE;
    IF calculation.id IS NULL OR calculation.calculation_status = 'DRAFT' THEN
        RETURN NULL;
    END IF;

    SELECT count(*), COALESCE(sum(principal_amount), 0), COALESCE(sum(tax_amount), 0),
           COALESCE(sum(shipping_amount), 0), COALESCE(sum(fee_deduction_amount), 0),
           COALESCE(sum(total_refund_amount), 0)
      INTO line_count, line_principal, line_tax, line_shipping, line_fee, line_total
      FROM doms.return_refund_calculation_lines
     WHERE tenant_id = calculation.tenant_id
       AND return_refund_calculation_id = calculation.id;
    IF line_count = 0
       OR calculation.principal_amount <> line_principal
       OR calculation.tax_amount <> line_tax
       OR calculation.shipping_amount <> line_shipping
       OR calculation.fee_deduction_amount <> line_fee
       OR calculation.refund_amount <> line_total THEN
        RAISE EXCEPTION 'Refund calculation header totals do not equal immutable line totals'
            USING ERRCODE = '23514';
    END IF;
    RETURN NULL;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.validate_return_payment_refund_link()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    calculation doms.return_refund_calculations%ROWTYPE;
    calculation_line doms.return_refund_calculation_lines%ROWTYPE;
    disposition doms.return_dispositions%ROWTYPE;
    return_request doms.return_requests%ROWTYPE;
    refund_request doms.payment_refund_requests%ROWTYPE;
    payment_refund doms.payment_refunds%ROWTYPE;
    reserve_new boolean;
    other_line_quantity numeric(24,8);
    other_line_amount numeric(24,6);
    other_disposition_quantity numeric(24,8);
    other_disposition_amount numeric(24,6);
    other_request_amount numeric(24,6);
    other_calculation_amount numeric(24,6);
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF OLD.tenant_id IS DISTINCT FROM NEW.tenant_id OR
           OLD.return_refund_calculation_id IS DISTINCT FROM NEW.return_refund_calculation_id OR
           OLD.return_refund_calculation_line_id IS DISTINCT FROM NEW.return_refund_calculation_line_id OR
           OLD.payment_refund_request_id IS DISTINCT FROM NEW.payment_refund_request_id OR
           OLD.linked_quantity IS DISTINCT FROM NEW.linked_quantity OR
           OLD.linked_amount IS DISTINCT FROM NEW.linked_amount OR
           OLD.currency_code IS DISTINCT FROM NEW.currency_code OR
           OLD.idempotency_key IS DISTINCT FROM NEW.idempotency_key THEN
            RAISE EXCEPTION 'Refund-link identity, quantity, amount, currency, and idempotency are immutable'
                USING ERRCODE = '55000';
        END IF;
        IF OLD.payment_refund_id IS NOT NULL
           AND OLD.payment_refund_id IS DISTINCT FROM NEW.payment_refund_id THEN
            RAISE EXCEPTION 'A linked payment refund cannot be replaced'
                USING ERRCODE = '55000';
        END IF;
        IF OLD.link_status IN ('SUCCEEDED','FAILED','CANCELLED')
           AND OLD.link_status IS DISTINCT FROM NEW.link_status THEN
            RAISE EXCEPTION 'Terminal refund-link status is immutable'
                USING ERRCODE = '55000';
        END IF;
    END IF;

    SELECT * INTO calculation
      FROM doms.return_refund_calculations
     WHERE tenant_id = NEW.tenant_id
       AND id = NEW.return_refund_calculation_id
     FOR UPDATE;
    SELECT * INTO calculation_line
      FROM doms.return_refund_calculation_lines
     WHERE tenant_id = NEW.tenant_id
       AND id = NEW.return_refund_calculation_line_id
     FOR UPDATE;
    SELECT * INTO disposition
      FROM doms.return_dispositions
     WHERE tenant_id = NEW.tenant_id
       AND id = calculation_line.return_disposition_id
     FOR UPDATE;
    SELECT * INTO return_request
      FROM doms.return_requests
     WHERE tenant_id = NEW.tenant_id
       AND id = calculation.return_request_id
     FOR UPDATE;
    SELECT * INTO refund_request
      FROM doms.payment_refund_requests
     WHERE tenant_id = NEW.tenant_id
       AND id = NEW.payment_refund_request_id
     FOR UPDATE;

    IF calculation.id IS NULL OR calculation_line.id IS NULL OR disposition.id IS NULL
       OR return_request.id IS NULL OR refund_request.id IS NULL
       OR calculation_line.return_refund_calculation_id <> calculation.id
       OR calculation.calculation_status NOT IN (
            'APPROVED','REFUND_PENDING','PARTIALLY_REFUNDED','REFUNDED')
       OR refund_request.sales_order_id <> return_request.sales_order_id
       OR refund_request.customer_id <> return_request.customer_id
       OR calculation.currency_code <> NEW.currency_code
       OR calculation_line.currency_code <> NEW.currency_code
       OR disposition.currency_code <> NEW.currency_code
       OR refund_request.currency_code <> NEW.currency_code THEN
        RAISE EXCEPTION 'Payment refund link differs from its approved return calculation or payment request'
            USING ERRCODE = '23514';
    END IF;
    IF NEW.link_status IN ('SUBMITTED','PROCESSING','SUCCEEDED')
       AND refund_request.status IN ('REJECTED','CANCELLED','EXPIRED') THEN
        RAISE EXCEPTION 'Rejected, cancelled, or expired payment refund request cannot be processed'
            USING ERRCODE = '23514';
    END IF;

    IF NEW.payment_refund_id IS NOT NULL THEN
        SELECT * INTO payment_refund
          FROM doms.payment_refunds
         WHERE tenant_id = NEW.tenant_id
           AND id = NEW.payment_refund_id
         FOR UPDATE;
        IF payment_refund.id IS NULL
           OR payment_refund.refund_request_id <> NEW.payment_refund_request_id
           OR payment_refund.currency_code <> NEW.currency_code
           OR payment_refund.refund_amount <> NEW.linked_amount THEN
            RAISE EXCEPTION 'Linked payment refund differs from the refund request, currency, or amount'
                USING ERRCODE = '23514';
        END IF;
    END IF;
    IF NEW.link_status = 'SUCCEEDED'
       AND (NEW.payment_refund_id IS NULL OR payment_refund.status <> 'SUCCEEDED') THEN
        RAISE EXCEPTION 'Successful return refund requires a successful payment refund fact'
            USING ERRCODE = '23514';
    END IF;
    IF NEW.succeeded_at IS NOT NULL AND NEW.succeeded_at > now() THEN
        RAISE EXCEPTION 'Refund-link success time cannot be in the future'
            USING ERRCODE = '23514';
    END IF;

    reserve_new := NEW.link_status IN ('PLANNED','SUBMITTED','PROCESSING','SUCCEEDED');
    IF reserve_new THEN
        SELECT COALESCE(sum(linked_quantity), 0), COALESCE(sum(linked_amount), 0)
          INTO other_line_quantity, other_line_amount
          FROM doms.return_payment_refund_links
         WHERE tenant_id = NEW.tenant_id
           AND return_refund_calculation_line_id = NEW.return_refund_calculation_line_id
           AND id <> NEW.id
           AND link_status IN ('PLANNED','SUBMITTED','PROCESSING','SUCCEEDED');
        IF other_line_quantity + NEW.linked_quantity > calculation_line.requested_refund_quantity
           OR other_line_amount + NEW.linked_amount > calculation_line.total_refund_amount THEN
            RAISE EXCEPTION 'Refund link exceeds calculated line quantity or amount'
                USING ERRCODE = '23514';
        END IF;

        SELECT COALESCE(sum(link.linked_quantity), 0), COALESCE(sum(link.linked_amount), 0)
          INTO other_disposition_quantity, other_disposition_amount
          FROM doms.return_payment_refund_links link
          JOIN doms.return_refund_calculation_lines line
            ON line.tenant_id = link.tenant_id
           AND line.id = link.return_refund_calculation_line_id
         WHERE link.tenant_id = NEW.tenant_id
           AND line.return_disposition_id = calculation_line.return_disposition_id
           AND link.id <> NEW.id
           AND link.link_status IN ('PLANNED','SUBMITTED','PROCESSING','SUCCEEDED');
        IF other_disposition_quantity + NEW.linked_quantity > disposition.refund_eligible_quantity
           OR other_disposition_amount + NEW.linked_amount > disposition.refund_eligible_amount THEN
            RAISE EXCEPTION 'Refund links exceed the disposition policy entitlement'
                USING ERRCODE = '23514';
        END IF;

        SELECT COALESCE(sum(linked_amount), 0)
          INTO other_request_amount
          FROM doms.return_payment_refund_links
         WHERE tenant_id = NEW.tenant_id
           AND payment_refund_request_id = NEW.payment_refund_request_id
           AND id <> NEW.id
           AND link_status IN ('PLANNED','SUBMITTED','PROCESSING','SUCCEEDED');
        IF other_request_amount + NEW.linked_amount > refund_request.requested_amount THEN
            RAISE EXCEPTION 'Return refund links exceed payment refund request amount'
                USING ERRCODE = '23514';
        END IF;

        SELECT COALESCE(sum(linked_amount), 0)
          INTO other_calculation_amount
          FROM doms.return_payment_refund_links
         WHERE tenant_id = NEW.tenant_id
           AND return_refund_calculation_id = NEW.return_refund_calculation_id
           AND id <> NEW.id
           AND link_status IN ('PLANNED','SUBMITTED','PROCESSING','SUCCEEDED');
        IF other_calculation_amount + NEW.linked_amount > calculation.refund_amount THEN
            RAISE EXCEPTION 'Return refund links exceed approved calculation amount'
                USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.project_return_payment_refund_link()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    calculation_line doms.return_refund_calculation_lines%ROWTYPE;
    line_reserved_quantity numeric(24,8);
    line_succeeded_quantity numeric(24,8);
    line_reserved_amount numeric(24,6);
    line_succeeded_amount numeric(24,6);
    calculation_reserved numeric(24,6);
    calculation_succeeded numeric(24,6);
    rma_refunded_quantity numeric(24,8);
    request_refunded_quantity numeric(24,8);
    request_refunded_amount numeric(24,6);
BEGIN
    SELECT * INTO calculation_line
      FROM doms.return_refund_calculation_lines
     WHERE tenant_id = NEW.tenant_id
       AND id = NEW.return_refund_calculation_line_id;

    SELECT COALESCE(sum(linked_quantity) FILTER (
               WHERE link_status IN ('PLANNED','SUBMITTED','PROCESSING','SUCCEEDED')), 0),
           COALESCE(sum(linked_quantity) FILTER (WHERE link_status = 'SUCCEEDED'), 0),
           COALESCE(sum(linked_amount) FILTER (
               WHERE link_status IN ('PLANNED','SUBMITTED','PROCESSING','SUCCEEDED')), 0),
           COALESCE(sum(linked_amount) FILTER (WHERE link_status = 'SUCCEEDED'), 0)
      INTO line_reserved_quantity, line_succeeded_quantity,
           line_reserved_amount, line_succeeded_amount
      FROM doms.return_payment_refund_links
     WHERE tenant_id = NEW.tenant_id
       AND return_refund_calculation_line_id = NEW.return_refund_calculation_line_id;
    UPDATE doms.return_refund_calculation_lines
       SET reserved_refund_quantity = line_reserved_quantity,
           succeeded_refund_quantity = line_succeeded_quantity,
           reserved_refund_amount = line_reserved_amount,
           succeeded_refund_amount = line_succeeded_amount
     WHERE tenant_id = NEW.tenant_id
       AND id = NEW.return_refund_calculation_line_id;

    SELECT COALESCE(sum(linked_amount) FILTER (
               WHERE link_status IN ('PLANNED','SUBMITTED','PROCESSING','SUCCEEDED')), 0),
           COALESCE(sum(linked_amount) FILTER (WHERE link_status = 'SUCCEEDED'), 0)
      INTO calculation_reserved, calculation_succeeded
      FROM doms.return_payment_refund_links
     WHERE tenant_id = NEW.tenant_id
       AND return_refund_calculation_id = NEW.return_refund_calculation_id;
    UPDATE doms.return_refund_calculations
       SET reserved_refund_amount = calculation_reserved,
           succeeded_refund_amount = calculation_succeeded,
           calculation_status = CASE
               WHEN calculation_succeeded = refund_amount AND calculation_succeeded > 0
                   THEN 'REFUNDED'
               WHEN calculation_succeeded > 0 THEN 'PARTIALLY_REFUNDED'
               WHEN calculation_reserved > 0 THEN 'REFUND_PENDING'
               ELSE calculation_status
           END,
           row_version = row_version + 1,
           updated_at = now()
     WHERE tenant_id = NEW.tenant_id
       AND id = NEW.return_refund_calculation_id;

    SELECT COALESCE(sum(link.linked_quantity), 0)
      INTO rma_refunded_quantity
      FROM doms.return_payment_refund_links link
      JOIN doms.return_refund_calculation_lines line
        ON line.tenant_id = link.tenant_id
       AND line.id = link.return_refund_calculation_line_id
     WHERE link.tenant_id = NEW.tenant_id
       AND line.rma_authorization_line_id = calculation_line.rma_authorization_line_id
       AND link.link_status = 'SUCCEEDED';
    UPDATE doms.rma_authorization_lines
       SET refunded_quantity = rma_refunded_quantity,
           line_status = CASE
               WHEN rma_refunded_quantity = refund_eligible_quantity AND rma_refunded_quantity > 0
                   THEN 'REFUNDED'
               WHEN rma_refunded_quantity > 0 THEN 'PARTIALLY_REFUNDED'
               ELSE line_status
           END,
           row_version = row_version + 1,
           updated_at = now()
     WHERE tenant_id = NEW.tenant_id
       AND id = calculation_line.rma_authorization_line_id;

    SELECT COALESCE(sum(link.linked_quantity), 0), COALESCE(sum(link.linked_amount), 0)
      INTO request_refunded_quantity, request_refunded_amount
      FROM doms.return_payment_refund_links link
      JOIN doms.return_refund_calculation_lines line
        ON line.tenant_id = link.tenant_id
       AND line.id = link.return_refund_calculation_line_id
     WHERE link.tenant_id = NEW.tenant_id
       AND line.return_request_line_id = calculation_line.return_request_line_id
       AND link.link_status = 'SUCCEEDED';
    UPDATE doms.return_request_lines
       SET refunded_quantity = request_refunded_quantity,
           refunded_amount = request_refunded_amount,
           line_status = CASE
               WHEN request_refunded_quantity = refund_eligible_quantity
                    AND request_refunded_quantity > 0 THEN 'REFUNDED'
               WHEN request_refunded_quantity > 0 THEN 'PARTIALLY_REFUNDED'
               ELSE line_status
           END,
           row_version = row_version + 1,
           updated_at = now()
     WHERE tenant_id = NEW.tenant_id
       AND id = calculation_line.return_request_line_id;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.validate_exchange_request_line()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    exchange_header doms.exchange_requests%ROWTYPE;
    request_line doms.return_request_lines%ROWTYPE;
    return_header doms.return_requests%ROWTYPE;
    other_exchange_quantity numeric(24,8);
BEGIN
    SELECT * INTO exchange_header
      FROM doms.exchange_requests
     WHERE tenant_id = NEW.tenant_id
       AND id = NEW.exchange_request_id
     FOR UPDATE;
    SELECT * INTO request_line
      FROM doms.return_request_lines
     WHERE tenant_id = NEW.tenant_id
       AND id = NEW.return_request_line_id
     FOR UPDATE;
    SELECT * INTO return_header
      FROM doms.return_requests
     WHERE tenant_id = NEW.tenant_id
       AND id = request_line.return_request_id;
    IF exchange_header.id IS NULL OR request_line.id IS NULL OR return_header.id IS NULL
       OR exchange_header.return_request_id <> request_line.return_request_id
       OR exchange_header.original_sales_order_id <> return_header.sales_order_id
       OR exchange_header.customer_id <> return_header.customer_id
       OR NEW.original_item_id <> request_line.item_id
       OR NEW.uom_code <> request_line.uom_code THEN
        RAISE EXCEPTION 'Exchange line differs from the original return, order, customer, item, or UOM'
            USING ERRCODE = '23514';
    END IF;

    SELECT COALESCE(sum(return_quantity), 0)
      INTO other_exchange_quantity
      FROM doms.exchange_request_lines
     WHERE tenant_id = NEW.tenant_id
       AND return_request_line_id = NEW.return_request_line_id
       AND id <> NEW.id
       AND line_status NOT IN ('REJECTED','CANCELLED');
    IF other_exchange_quantity + NEW.return_quantity > request_line.refund_eligible_quantity THEN
        RAISE EXCEPTION 'Exchange quantity exceeds disposition-approved return quantity'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.validate_replacement_request_line()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    replacement_header doms.replacement_requests%ROWTYPE;
    source_row record;
    other_replacement_quantity numeric(24,8);
BEGIN
    SELECT * INTO replacement_header
      FROM doms.replacement_requests
     WHERE tenant_id = NEW.tenant_id
       AND id = NEW.replacement_request_id
     FOR UPDATE;
    SELECT order_line.id AS sales_order_line_id,
           order_line.sales_order_id,
           order_header.customer_id,
           order_line.uom_code,
           shipment_line.id AS shipment_line_id,
           shipment_line.shipped_quantity,
           package_item.id AS package_item_id,
           package_item.packed_quantity
      INTO source_row
      FROM doms.package_items package_item
      JOIN doms.shipment_lines shipment_line
        ON shipment_line.tenant_id = package_item.tenant_id
       AND shipment_line.id = package_item.shipment_line_id
      JOIN doms.fulfillment_order_lines fulfillment_line
        ON fulfillment_line.tenant_id = shipment_line.tenant_id
       AND fulfillment_line.id = shipment_line.fulfillment_order_line_id
      JOIN doms.sales_order_lines order_line
        ON order_line.tenant_id = fulfillment_line.tenant_id
       AND order_line.id = fulfillment_line.sales_order_line_id
      JOIN doms.sales_orders order_header
        ON order_header.tenant_id = order_line.tenant_id
       AND order_header.id = order_line.sales_order_id
     WHERE package_item.tenant_id = NEW.tenant_id
       AND package_item.id = NEW.original_package_item_id
     FOR UPDATE OF package_item, shipment_line, order_line;
    IF replacement_header.id IS NULL OR NOT FOUND
       OR NEW.original_sales_order_line_id IS DISTINCT FROM source_row.sales_order_line_id
       OR NEW.original_shipment_line_id IS DISTINCT FROM source_row.shipment_line_id
       OR replacement_header.original_sales_order_id <> source_row.sales_order_id
       OR replacement_header.customer_id <> source_row.customer_id
       OR NEW.uom_code <> source_row.uom_code THEN
        RAISE EXCEPTION 'Replacement line differs from the shipped package, original order, or customer'
            USING ERRCODE = '23514';
    END IF;

    SELECT COALESCE(sum(replacement_quantity), 0)
      INTO other_replacement_quantity
      FROM doms.replacement_request_lines
     WHERE tenant_id = NEW.tenant_id
       AND original_package_item_id = NEW.original_package_item_id
       AND id <> NEW.id
       AND line_status NOT IN ('REJECTED','CANCELLED');
    IF other_replacement_quantity + NEW.replacement_quantity >
       LEAST(source_row.shipped_quantity, source_row.packed_quantity) THEN
        RAISE EXCEPTION 'Replacement quantity exceeds the shipped package quantity'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.validate_return_output_order_link()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    header_original_order_id uuid;
    header_customer_id uuid;
    expected_line_id uuid;
    expected_item_id uuid;
    expected_quantity numeric(24,8);
    expected_uom_code varchar(20);
    replacement_order doms.sales_orders%ROWTYPE;
    replacement_line doms.sales_order_lines%ROWTYPE;
    expected_source varchar(30);
BEGIN
    IF TG_TABLE_NAME = 'exchange_order_links' THEN
        SELECT original_sales_order_id, customer_id
          INTO header_original_order_id, header_customer_id
          FROM doms.exchange_requests
         WHERE tenant_id = NEW.tenant_id
           AND id = NEW.exchange_request_id
         FOR UPDATE;
        SELECT exchange_request_id, replacement_item_id, replacement_quantity, uom_code
          INTO expected_line_id, expected_item_id, expected_quantity, expected_uom_code
          FROM doms.exchange_request_lines
         WHERE tenant_id = NEW.tenant_id
           AND id = NEW.exchange_request_line_id
         FOR UPDATE;
        IF expected_line_id IS DISTINCT FROM NEW.exchange_request_id THEN
            RAISE EXCEPTION 'Exchange order link header and line differ'
                USING ERRCODE = '23514';
        END IF;
        expected_source := 'EXCHANGE';
    ELSE
        SELECT original_sales_order_id, customer_id
          INTO header_original_order_id, header_customer_id
          FROM doms.replacement_requests
         WHERE tenant_id = NEW.tenant_id
           AND id = NEW.replacement_request_id
         FOR UPDATE;
        SELECT replacement_request_id, replacement_item_id, replacement_quantity, uom_code
          INTO expected_line_id, expected_item_id, expected_quantity, expected_uom_code
          FROM doms.replacement_request_lines
         WHERE tenant_id = NEW.tenant_id
           AND id = NEW.replacement_request_line_id
         FOR UPDATE;
        IF expected_line_id IS DISTINCT FROM NEW.replacement_request_id THEN
            RAISE EXCEPTION 'Replacement order link header and line differ'
                USING ERRCODE = '23514';
        END IF;
        expected_source := 'REPLACEMENT';
    END IF;

    SELECT * INTO replacement_order
      FROM doms.sales_orders
     WHERE tenant_id = NEW.tenant_id
       AND id = NEW.replacement_sales_order_id
     FOR UPDATE;
    SELECT * INTO replacement_line
      FROM doms.sales_order_lines
     WHERE tenant_id = NEW.tenant_id
       AND id = NEW.replacement_sales_order_line_id
     FOR UPDATE;
    IF header_original_order_id IS NULL OR expected_line_id IS NULL
       OR NEW.original_sales_order_id <> header_original_order_id
       OR replacement_order.id IS NULL OR replacement_line.id IS NULL
       OR replacement_order.customer_id <> header_customer_id
       OR replacement_order.order_source <> expected_source
       OR replacement_line.sales_order_id <> NEW.replacement_sales_order_id
       OR replacement_line.item_id <> expected_item_id
       OR replacement_line.uom_code <> expected_uom_code
       OR replacement_line.ordered_qty <> expected_quantity THEN
        RAISE EXCEPTION 'Output link must reference a matching normal % sales order and line',
            expected_source USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.validate_warranty_claim_line()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    claim doms.warranty_claims%ROWTYPE;
    order_line doms.sales_order_lines%ROWTYPE;
    registration doms.warranty_registrations%ROWTYPE;
    policy_item_id uuid;
    source_shipment_quantity numeric(24,8);
    source_shipment_line_id uuid;
    source_package_item_id uuid;
    source_item_id uuid;
    other_claimed numeric(24,8);
    claim_capacity numeric(24,8);
BEGIN
    SELECT * INTO claim
      FROM doms.warranty_claims
     WHERE tenant_id = NEW.tenant_id
       AND id = NEW.warranty_claim_id
     FOR UPDATE;
    SELECT * INTO order_line
      FROM doms.sales_order_lines
     WHERE tenant_id = NEW.tenant_id
       AND id = NEW.sales_order_line_id
     FOR UPDATE;
    SELECT policy.item_id INTO policy_item_id
      FROM doms.warranty_policy_versions version
      JOIN doms.warranty_policies policy
        ON policy.tenant_id = version.tenant_id
       AND policy.id = version.warranty_policy_id
     WHERE version.tenant_id = NEW.tenant_id
       AND version.id = claim.warranty_policy_version_id;
    IF claim.id IS NULL OR order_line.id IS NULL
       OR order_line.sales_order_id <> claim.sales_order_id
       OR order_line.item_id <> NEW.item_id
       OR order_line.uom_code <> NEW.uom_code
       OR (policy_item_id IS NOT NULL AND policy_item_id <> NEW.item_id) THEN
        RAISE EXCEPTION 'Warranty claim line differs from its order, item, UOM, or policy'
            USING ERRCODE = '23514';
    END IF;

    IF claim.warranty_registration_id IS NOT NULL THEN
        SELECT * INTO registration
          FROM doms.warranty_registrations
         WHERE tenant_id = NEW.tenant_id
           AND id = claim.warranty_registration_id;
        IF registration.id IS NULL
           OR registration.sales_order_id <> claim.sales_order_id
           OR registration.customer_id <> claim.customer_id
           OR registration.sales_order_line_id <> NEW.sales_order_line_id
           OR registration.item_id <> NEW.item_id
           OR registration.warranty_policy_version_id <> claim.warranty_policy_version_id THEN
            RAISE EXCEPTION 'Warranty claim differs from its registration'
                USING ERRCODE = '23514';
        END IF;
    END IF;

    IF NEW.package_item_id IS NOT NULL THEN
        SELECT shipment_line.id, package_item.id, shipment_line.item_id,
               LEAST(shipment_line.shipped_quantity, package_item.packed_quantity)
          INTO source_shipment_line_id, source_package_item_id, source_item_id,
               source_shipment_quantity
          FROM doms.package_items package_item
          JOIN doms.shipment_lines shipment_line
            ON shipment_line.tenant_id = package_item.tenant_id
           AND shipment_line.id = package_item.shipment_line_id
          JOIN doms.fulfillment_order_lines fulfillment_line
            ON fulfillment_line.tenant_id = shipment_line.tenant_id
           AND fulfillment_line.id = shipment_line.fulfillment_order_line_id
         WHERE package_item.tenant_id = NEW.tenant_id
           AND package_item.id = NEW.package_item_id
           AND fulfillment_line.sales_order_line_id = NEW.sales_order_line_id
         FOR UPDATE OF package_item, shipment_line;
        IF source_package_item_id IS NULL
           OR NEW.shipment_line_id IS DISTINCT FROM source_shipment_line_id
           OR NEW.item_id <> source_item_id THEN
            RAISE EXCEPTION 'Warranty claim package item does not match its shipment and order line'
                USING ERRCODE = '23514';
        END IF;
        claim_capacity := source_shipment_quantity;
    ELSIF NEW.shipment_line_id IS NOT NULL THEN
        SELECT shipment_line.item_id, shipment_line.shipped_quantity
          INTO source_item_id, source_shipment_quantity
          FROM doms.shipment_lines shipment_line
          JOIN doms.fulfillment_order_lines fulfillment_line
            ON fulfillment_line.tenant_id = shipment_line.tenant_id
           AND fulfillment_line.id = shipment_line.fulfillment_order_line_id
         WHERE shipment_line.tenant_id = NEW.tenant_id
           AND shipment_line.id = NEW.shipment_line_id
           AND fulfillment_line.sales_order_line_id = NEW.sales_order_line_id
         FOR UPDATE OF shipment_line;
        IF source_item_id IS NULL OR source_item_id <> NEW.item_id THEN
            RAISE EXCEPTION 'Warranty claim shipment line does not match its order line and item'
                USING ERRCODE = '23514';
        END IF;
        claim_capacity := source_shipment_quantity;
    ELSE
        claim_capacity := order_line.fulfilled_qty;
    END IF;

    SELECT COALESCE(sum(line.claim_quantity), 0)
      INTO other_claimed
      FROM doms.warranty_claim_lines line
      JOIN doms.warranty_claims header
        ON header.tenant_id = line.tenant_id
       AND header.id = line.warranty_claim_id
     WHERE line.tenant_id = NEW.tenant_id
       AND line.sales_order_line_id = NEW.sales_order_line_id
       AND line.package_item_id IS NOT DISTINCT FROM NEW.package_item_id
       AND line.id <> NEW.id
       AND line.line_status NOT IN ('REJECTED','CANCELLED')
       AND header.claim_status NOT IN ('REJECTED','CANCELLED','EXPIRED');
    IF other_claimed + NEW.claim_quantity > claim_capacity THEN
        RAISE EXCEPTION 'Warranty claim quantity exceeds delivered source quantity'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

-- -----------------------------------------------------------------------------
-- Trigger wiring: concurrency guards, projections, and immutable facts
-- -----------------------------------------------------------------------------

-- Policy versions and rules remain editable while DRAFT. Publication freezes
-- core content; only the forward lifecycle transitions validated above remain.
DROP TRIGGER IF EXISTS trg_doms_return_append_only
    ON doms.return_policy_versions;
DROP TRIGGER IF EXISTS trg_doms_return_policy_version_lifecycle
    ON doms.return_policy_versions;
CREATE TRIGGER trg_doms_return_policy_version_lifecycle
BEFORE INSERT OR UPDATE ON doms.return_policy_versions
FOR EACH ROW EXECUTE FUNCTION doms.enforce_policy_version_lifecycle();
DROP TRIGGER IF EXISTS trg_doms_return_policy_version_delete
    ON doms.return_policy_versions;
CREATE TRIGGER trg_doms_return_policy_version_delete
BEFORE DELETE ON doms.return_policy_versions
FOR EACH ROW EXECUTE FUNCTION doms.guard_policy_version_delete();
DROP TRIGGER IF EXISTS trg_doms_return_policy_version_truncate
    ON doms.return_policy_versions;
CREATE TRIGGER trg_doms_return_policy_version_truncate
BEFORE TRUNCATE ON doms.return_policy_versions
FOR EACH STATEMENT EXECUTE FUNCTION doms.prevent_return_append_only_change();

DROP TRIGGER IF EXISTS trg_doms_return_append_only
    ON doms.return_policy_rules;
DROP TRIGGER IF EXISTS trg_doms_return_policy_rule_draft
    ON doms.return_policy_rules;
CREATE TRIGGER trg_doms_return_policy_rule_draft
BEFORE INSERT OR UPDATE OR DELETE ON doms.return_policy_rules
FOR EACH ROW EXECUTE FUNCTION doms.enforce_return_policy_rule_draft();
DROP TRIGGER IF EXISTS trg_doms_return_policy_rule_truncate
    ON doms.return_policy_rules;
CREATE TRIGGER trg_doms_return_policy_rule_truncate
BEFORE TRUNCATE ON doms.return_policy_rules
FOR EACH STATEMENT EXECUTE FUNCTION doms.prevent_return_append_only_change();

DROP TRIGGER IF EXISTS trg_doms_return_append_only
    ON doms.warranty_policy_versions;
DROP TRIGGER IF EXISTS trg_doms_warranty_policy_version_lifecycle
    ON doms.warranty_policy_versions;
CREATE TRIGGER trg_doms_warranty_policy_version_lifecycle
BEFORE INSERT OR UPDATE ON doms.warranty_policy_versions
FOR EACH ROW EXECUTE FUNCTION doms.enforce_policy_version_lifecycle();
DROP TRIGGER IF EXISTS trg_doms_warranty_policy_version_delete
    ON doms.warranty_policy_versions;
CREATE TRIGGER trg_doms_warranty_policy_version_delete
BEFORE DELETE ON doms.warranty_policy_versions
FOR EACH ROW EXECUTE FUNCTION doms.guard_policy_version_delete();
DROP TRIGGER IF EXISTS trg_doms_warranty_policy_version_truncate
    ON doms.warranty_policy_versions;
CREATE TRIGGER trg_doms_warranty_policy_version_truncate
BEFORE TRUNCATE ON doms.warranty_policy_versions
FOR EACH STATEMENT EXECUTE FUNCTION doms.prevent_return_append_only_change();

DROP TRIGGER IF EXISTS trg_doms_return_eligibility_source_scope
    ON doms.return_eligibility_check_lines;
CREATE TRIGGER trg_doms_return_eligibility_source_scope
BEFORE INSERT OR UPDATE OF return_eligibility_check_id, sales_order_line_id,
    shipment_line_id, package_item_id, item_id, requested_quantity, uom_code
ON doms.return_eligibility_check_lines
FOR EACH ROW EXECUTE FUNCTION doms.validate_return_source_scope();

DROP TRIGGER IF EXISTS trg_doms_return_request_source_scope
    ON doms.return_request_lines;
CREATE TRIGGER trg_doms_return_request_source_scope
BEFORE INSERT OR UPDATE OF return_request_id, return_eligibility_result_id,
    sales_order_line_id, shipment_line_id, package_item_id, item_id,
    requested_quantity, eligible_quantity, currency_code, uom_code
ON doms.return_request_lines
FOR EACH ROW EXECUTE FUNCTION doms.validate_return_source_scope();

DROP TRIGGER IF EXISTS trg_doms_return_eligibility_result_validate
    ON doms.return_eligibility_results;
CREATE TRIGGER trg_doms_return_eligibility_result_validate
BEFORE INSERT ON doms.return_eligibility_results
FOR EACH ROW EXECUTE FUNCTION doms.validate_return_eligibility_result();

DROP TRIGGER IF EXISTS trg_doms_rma_line_validate
    ON doms.rma_authorization_lines;
CREATE TRIGGER trg_doms_rma_line_validate
BEFORE INSERT OR UPDATE OF rma_authorization_id, return_request_line_id,
    sales_order_line_id, shipment_line_id, package_item_id, item_id,
    authorized_quantity, uom_code, line_status, idempotency_key
ON doms.rma_authorization_lines
FOR EACH ROW EXECUTE FUNCTION doms.validate_rma_authorization_line();

DROP TRIGGER IF EXISTS trg_doms_rma_line_project
    ON doms.rma_authorization_lines;
CREATE TRIGGER trg_doms_rma_line_project
AFTER INSERT OR UPDATE OF authorized_quantity, line_status
ON doms.rma_authorization_lines
FOR EACH ROW EXECUTE FUNCTION doms.project_rma_authorization_line();

DROP TRIGGER IF EXISTS trg_doms_return_receipt_line_validate
    ON doms.return_receipt_lines;
CREATE TRIGGER trg_doms_return_receipt_line_validate
BEFORE INSERT ON doms.return_receipt_lines
FOR EACH ROW EXECUTE FUNCTION doms.validate_return_receipt_line();

DROP TRIGGER IF EXISTS trg_doms_return_receipt_line_project
    ON doms.return_receipt_lines;
CREATE TRIGGER trg_doms_return_receipt_line_project
AFTER INSERT ON doms.return_receipt_lines
FOR EACH ROW EXECUTE FUNCTION doms.project_return_receipt_line();

DROP TRIGGER IF EXISTS trg_doms_return_inspection_validate
    ON doms.return_inspections;
CREATE TRIGGER trg_doms_return_inspection_validate
BEFORE INSERT ON doms.return_inspections
FOR EACH ROW EXECUTE FUNCTION doms.validate_return_inspection();

DROP TRIGGER IF EXISTS trg_doms_return_inspection_project
    ON doms.return_inspections;
CREATE TRIGGER trg_doms_return_inspection_project
AFTER INSERT ON doms.return_inspections
FOR EACH ROW EXECUTE FUNCTION doms.project_return_inspection();

DROP TRIGGER IF EXISTS trg_doms_return_disposition_validate
    ON doms.return_dispositions;
CREATE TRIGGER trg_doms_return_disposition_validate
BEFORE INSERT ON doms.return_dispositions
FOR EACH ROW EXECUTE FUNCTION doms.validate_return_disposition();

DROP TRIGGER IF EXISTS trg_doms_return_disposition_project
    ON doms.return_dispositions;
CREATE TRIGGER trg_doms_return_disposition_project
AFTER INSERT ON doms.return_dispositions
FOR EACH ROW EXECUTE FUNCTION doms.project_return_disposition();

DROP TRIGGER IF EXISTS trg_doms_return_refund_line_validate
    ON doms.return_refund_calculation_lines;
CREATE TRIGGER trg_doms_return_refund_line_validate
BEFORE INSERT OR UPDATE OF return_refund_calculation_id, return_request_line_id,
    rma_authorization_line_id, return_disposition_id, eligible_quantity,
    requested_refund_quantity, unit_refund_amount, principal_amount, tax_amount,
    shipping_amount, fee_deduction_amount, total_refund_amount, currency_code
ON doms.return_refund_calculation_lines
FOR EACH ROW EXECUTE FUNCTION doms.validate_return_refund_calculation_line();

DROP TRIGGER IF EXISTS trg_doms_return_refund_header_totals
    ON doms.return_refund_calculations;
CREATE CONSTRAINT TRIGGER trg_doms_return_refund_header_totals
AFTER INSERT OR UPDATE ON doms.return_refund_calculations
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION doms.validate_return_refund_calculation_total();

DROP TRIGGER IF EXISTS trg_doms_return_refund_line_totals
    ON doms.return_refund_calculation_lines;
CREATE CONSTRAINT TRIGGER trg_doms_return_refund_line_totals
AFTER INSERT OR UPDATE OR DELETE ON doms.return_refund_calculation_lines
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION doms.validate_return_refund_calculation_total();

DROP TRIGGER IF EXISTS trg_doms_return_payment_link_validate
    ON doms.return_payment_refund_links;
CREATE TRIGGER trg_doms_return_payment_link_validate
BEFORE INSERT OR UPDATE ON doms.return_payment_refund_links
FOR EACH ROW EXECUTE FUNCTION doms.validate_return_payment_refund_link();

DROP TRIGGER IF EXISTS trg_doms_return_payment_link_project
    ON doms.return_payment_refund_links;
CREATE TRIGGER trg_doms_return_payment_link_project
AFTER INSERT OR UPDATE OF payment_refund_id, link_status, succeeded_at
ON doms.return_payment_refund_links
FOR EACH ROW EXECUTE FUNCTION doms.project_return_payment_refund_link();

DROP TRIGGER IF EXISTS trg_doms_exchange_line_validate
    ON doms.exchange_request_lines;
CREATE TRIGGER trg_doms_exchange_line_validate
BEFORE INSERT OR UPDATE ON doms.exchange_request_lines
FOR EACH ROW EXECUTE FUNCTION doms.validate_exchange_request_line();

DROP TRIGGER IF EXISTS trg_doms_replacement_line_validate
    ON doms.replacement_request_lines;
CREATE TRIGGER trg_doms_replacement_line_validate
BEFORE INSERT OR UPDATE ON doms.replacement_request_lines
FOR EACH ROW EXECUTE FUNCTION doms.validate_replacement_request_line();

DROP TRIGGER IF EXISTS trg_doms_exchange_output_order_validate
    ON doms.exchange_order_links;
CREATE TRIGGER trg_doms_exchange_output_order_validate
BEFORE INSERT OR UPDATE ON doms.exchange_order_links
FOR EACH ROW EXECUTE FUNCTION doms.validate_return_output_order_link();

DROP TRIGGER IF EXISTS trg_doms_replacement_output_order_validate
    ON doms.replacement_order_links;
CREATE TRIGGER trg_doms_replacement_output_order_validate
BEFORE INSERT OR UPDATE ON doms.replacement_order_links
FOR EACH ROW EXECUTE FUNCTION doms.validate_return_output_order_link();

DROP TRIGGER IF EXISTS trg_doms_warranty_claim_line_validate
    ON doms.warranty_claim_lines;
CREATE TRIGGER trg_doms_warranty_claim_line_validate
BEFORE INSERT OR UPDATE ON doms.warranty_claim_lines
FOR EACH ROW EXECUTE FUNCTION doms.validate_warranty_claim_line();

DO $block$
DECLARE
    target_table text;
BEGIN
    FOREACH target_table IN ARRAY ARRAY[
        'return_eligibility_results',
        'return_request_status_events',
        'rma_authorization_events',
        'return_tracking_events',
        'return_receipt_lines',
        'return_receipt_events',
        'return_inspections',
        'return_inspection_events',
        'return_dispositions',
        'return_disposition_events',
        'warranty_claim_events',
        'customer_service_interactions',
        'customer_service_sla_events'
    ]
    LOOP
        EXECUTE format(
            'DROP TRIGGER IF EXISTS trg_doms_return_append_only ON doms.%I',
            target_table
        );
        EXECUTE format(
            'CREATE TRIGGER trg_doms_return_append_only '
            'BEFORE UPDATE OR DELETE OR TRUNCATE ON doms.%I '
            'FOR EACH STATEMENT EXECUTE FUNCTION doms.prevent_return_append_only_change()',
            target_table
        );
    END LOOP;
END;
$block$;

DO $block$
DECLARE
    target_table text;
BEGIN
    FOREACH target_table IN ARRAY ARRAY[
        'return_policies',
        'return_eligibility_checks',
        'return_eligibility_check_lines',
        'return_requests',
        'return_request_lines',
        'return_exceptions',
        'rma_authorizations',
        'rma_authorization_lines',
        'return_labels',
        'return_shipments',
        'return_shipment_lines',
        'return_receipts',
        'return_refund_calculations',
        'return_refund_calculation_lines',
        'return_payment_refund_links',
        'exchange_requests',
        'exchange_request_lines',
        'exchange_order_links',
        'replacement_requests',
        'replacement_request_lines',
        'replacement_order_links',
        'warranty_policies',
        'warranty_registrations',
        'warranty_claims',
        'warranty_claim_lines',
        'customer_service_cases',
        'customer_service_case_order_links',
        'customer_service_tasks',
        'customer_service_adjustment_requests'
    ]
    LOOP
        EXECUTE format(
            'DROP TRIGGER IF EXISTS trg_doms_return_prevent_delete ON doms.%I',
            target_table
        );
        EXECUTE format(
            'CREATE TRIGGER trg_doms_return_prevent_delete '
            'BEFORE DELETE OR TRUNCATE ON doms.%I '
            'FOR EACH STATEMENT EXECUTE FUNCTION doms.prevent_return_delete()',
            target_table
        );
    END LOOP;
END;
$block$;

-- Operational access paths used by service queues, entitlement locking, and audit.
CREATE INDEX IF NOT EXISTS ix_doms_return_request_queue
    ON doms.return_requests (tenant_id, return_status, requested_at, id);
CREATE INDEX IF NOT EXISTS ix_doms_return_request_customer
    ON doms.return_requests (tenant_id, customer_id, requested_at DESC);
CREATE INDEX IF NOT EXISTS ix_doms_return_line_source
    ON doms.return_request_lines (tenant_id, package_item_id, sales_order_line_id);
CREATE INDEX IF NOT EXISTS ix_doms_rma_line_active_package
    ON doms.rma_authorization_lines (tenant_id, package_item_id, rma_authorization_id)
    WHERE line_status NOT IN ('REJECTED','CANCELLED','EXPIRED');
CREATE INDEX IF NOT EXISTS ix_doms_return_shipment_queue
    ON doms.return_shipments (tenant_id, shipment_status, shipped_at, id);
CREATE INDEX IF NOT EXISTS ix_doms_return_tracking_timeline
    ON doms.return_tracking_events (tenant_id, return_shipment_id, occurred_at, event_sequence);
CREATE INDEX IF NOT EXISTS ix_doms_return_receipt_rma
    ON doms.return_receipts (tenant_id, rma_authorization_id, received_at DESC);
CREATE INDEX IF NOT EXISTS ix_doms_return_receipt_line_rma
    ON doms.return_receipt_lines (tenant_id, rma_authorization_line_id, created_at);
CREATE INDEX IF NOT EXISTS ix_doms_return_inspection_rma
    ON doms.return_inspections (tenant_id, rma_authorization_line_id, inspected_at);
CREATE INDEX IF NOT EXISTS ix_doms_return_disposition_rma
    ON doms.return_dispositions (tenant_id, rma_authorization_line_id, decided_at);
CREATE INDEX IF NOT EXISTS ix_doms_return_refund_calc_queue
    ON doms.return_refund_calculations (tenant_id, calculation_status, updated_at, id);
CREATE INDEX IF NOT EXISTS ix_doms_return_refund_link_active_line
    ON doms.return_payment_refund_links (
        tenant_id, return_refund_calculation_line_id, link_status, created_at
    );
CREATE INDEX IF NOT EXISTS ix_doms_warranty_claim_queue
    ON doms.warranty_claims (tenant_id, claim_status, submitted_at, id);
CREATE INDEX IF NOT EXISTS ix_doms_service_case_queue
    ON doms.customer_service_cases (
        tenant_id, case_status, priority, first_response_due_at, resolution_due_at, id
    );
CREATE INDEX IF NOT EXISTS ix_doms_service_task_queue
    ON doms.customer_service_tasks (
        tenant_id, task_status, due_at, assigned_to, id
    );

COMMENT ON TABLE doms.return_request_lines IS
    'Tenant-scoped return entitlement projection tied to original order, shipment, and package-item facts.';
COMMENT ON TABLE doms.rma_authorization_lines IS
    'Concurrency-guarded RMA authorization facts; aggregate active quantity cannot exceed shipped package capacity.';
COMMENT ON TABLE doms.return_payment_refund_links IS
    'Idempotent bridge from return entitlement to payment refund request/refund facts; successful links drive refunded projections.';
COMMENT ON TABLE doms.exchange_order_links IS
    'Maps an exchange request line to a normal sales order whose order_source is EXCHANGE.';
COMMENT ON TABLE doms.replacement_order_links IS
    'Maps a replacement request line to a normal sales order whose order_source is REPLACEMENT.';
