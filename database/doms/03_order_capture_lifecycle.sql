-- DOMS enterprise OMS schema - quote capture, immutable order snapshots, commercial
-- components, independent lifecycle axes, change/cancellation control, and evidence.
-- PostgreSQL 11 compatible. Applied after 02_customer_channel_pricing.sql.

CREATE TABLE IF NOT EXISTS doms.quotes (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    quote_no varchar(100) NOT NULL,
    customer_id uuid NOT NULL REFERENCES doms.customers(id) ON DELETE RESTRICT,
    sales_channel_id uuid NOT NULL REFERENCES doms.sales_channels(id) ON DELETE RESTRICT,
    channel_account_id uuid REFERENCES doms.channel_accounts(id) ON DELETE RESTRICT,
    channel_store_id uuid REFERENCES doms.channel_stores(id) ON DELETE RESTRICT,
    order_type_id uuid NOT NULL REFERENCES doms.order_types(id) ON DELETE RESTRICT,
    selling_organization_id uuid NOT NULL REFERENCES doms.selling_organizations(id) ON DELETE RESTRICT,
    price_book_id uuid REFERENCES doms.price_books(id) ON DELETE RESTRICT,
    source_system_id uuid REFERENCES doms.external_systems(id) ON DELETE RESTRICT,
    external_quote_id varchar(300),
    idempotency_key varchar(200),
    currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    quote_status varchar(30) NOT NULL DEFAULT 'DRAFT',
    valid_from timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz,
    accepted_at timestamptz,
    converted_at timestamptz,
    gross_amount numeric(24,6) NOT NULL DEFAULT 0,
    discount_amount numeric(24,6) NOT NULL DEFAULT 0,
    charge_amount numeric(24,6) NOT NULL DEFAULT 0,
    tax_amount numeric(24,6) NOT NULL DEFAULT 0,
    rounding_amount numeric(24,6) NOT NULL DEFAULT 0,
    total_amount numeric(24,6) NOT NULL DEFAULT 0,
    created_by uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    updated_by uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    UNIQUE (tenant_id, quote_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_doms_quotes_number CHECK (btrim(quote_no) <> ''),
    CONSTRAINT ck_doms_quotes_status CHECK (quote_status IN (
        'DRAFT','PRICED','PRESENTED','ACCEPTED','REJECTED','EXPIRED','CONVERTED','CANCELLED'
    )),
    CONSTRAINT ck_doms_quotes_dates CHECK (
        (expires_at IS NULL OR expires_at > valid_from) AND
        (accepted_at IS NULL OR accepted_at >= valid_from) AND
        (converted_at IS NULL OR converted_at >= valid_from)
    ),
    CONSTRAINT ck_doms_quotes_amounts CHECK (
        gross_amount >= 0 AND discount_amount >= 0 AND charge_amount >= 0 AND
        tax_amount >= 0 AND total_amount >= 0 AND discount_amount <= gross_amount + charge_amount AND
        abs(total_amount - (gross_amount - discount_amount + charge_amount + tax_amount + rounding_amount)) <= 0.000001
    ),
    CONSTRAINT ck_doms_quotes_external CHECK (
        (external_quote_id IS NULL OR btrim(external_quote_id) <> '') AND
        (idempotency_key IS NULL OR btrim(idempotency_key) <> '')
    ),
    CONSTRAINT ck_doms_quotes_attributes CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(attributes)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_quotes_external
    ON doms.quotes (
        tenant_id, sales_channel_id,
        COALESCE(channel_account_id, '00000000-0000-0000-0000-000000000000'::uuid),
        COALESCE(channel_store_id, '00000000-0000-0000-0000-000000000000'::uuid),
        external_quote_id
    ) WHERE external_quote_id IS NOT NULL AND deleted_at IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_quotes_idempotency
    ON doms.quotes (
        tenant_id,
        COALESCE(source_system_id, '00000000-0000-0000-0000-000000000000'::uuid),
        sales_channel_id, idempotency_key
    ) WHERE idempotency_key IS NOT NULL;

CREATE TABLE IF NOT EXISTS doms.quote_lines (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    quote_id uuid NOT NULL REFERENCES doms.quotes(id) ON DELETE RESTRICT,
    line_no integer NOT NULL,
    item_id uuid NOT NULL REFERENCES doms.items(id) ON DELETE RESTRICT,
    item_packaging_id uuid REFERENCES doms.item_packagings(id) ON DELETE RESTRICT,
    fulfillment_node_id uuid REFERENCES doms.fulfillment_nodes(id) ON DELETE RESTRICT,
    price_book_id uuid REFERENCES doms.price_books(id) ON DELETE RESTRICT,
    item_code_snapshot varchar(120) NOT NULL,
    item_name_snapshot varchar(300) NOT NULL,
    ordered_qty numeric(24,8) NOT NULL,
    uom_code varchar(20) NOT NULL REFERENCES doms.units_of_measure(uom_code),
    currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    unit_list_price numeric(24,6) NOT NULL DEFAULT 0,
    unit_selling_price numeric(24,6) NOT NULL DEFAULT 0,
    gross_amount numeric(24,6) NOT NULL DEFAULT 0,
    discount_amount numeric(24,6) NOT NULL DEFAULT 0,
    charge_amount numeric(24,6) NOT NULL DEFAULT 0,
    tax_amount numeric(24,6) NOT NULL DEFAULT 0,
    net_amount numeric(24,6) NOT NULL DEFAULT 0,
    line_status varchar(20) NOT NULL DEFAULT 'OPEN',
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (quote_id, line_no),
    CONSTRAINT ck_doms_quote_lines_number CHECK (line_no > 0),
    CONSTRAINT ck_doms_quote_lines_qty CHECK (ordered_qty > 0),
    CONSTRAINT ck_doms_quote_lines_status CHECK (line_status IN ('OPEN','PRICED','UNAVAILABLE','ACCEPTED','REJECTED','CANCELLED')),
    CONSTRAINT ck_doms_quote_lines_amounts CHECK (
        unit_list_price >= 0 AND unit_selling_price >= 0 AND
        gross_amount >= 0 AND discount_amount >= 0 AND charge_amount >= 0 AND
        tax_amount >= 0 AND net_amount >= 0 AND
        abs(gross_amount - round(ordered_qty * unit_selling_price, 6)) <= 0.000001 AND
        abs(net_amount - (gross_amount - discount_amount + charge_amount + tax_amount)) <= 0.000001
    ),
    CONSTRAINT ck_doms_quote_lines_attributes CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(attributes)
    )
);

CREATE INDEX IF NOT EXISTS ix_doms_quote_lines_quote
    ON doms.quote_lines (tenant_id, quote_id, line_no);

CREATE TABLE IF NOT EXISTS doms.sales_orders (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    order_no varchar(100) NOT NULL,
    order_source varchar(30) NOT NULL DEFAULT 'DIRECT',
    quote_id uuid REFERENCES doms.quotes(id) ON DELETE RESTRICT,
    customer_id uuid NOT NULL REFERENCES doms.customers(id) ON DELETE RESTRICT,
    sales_channel_id uuid NOT NULL REFERENCES doms.sales_channels(id) ON DELETE RESTRICT,
    channel_account_id uuid REFERENCES doms.channel_accounts(id) ON DELETE RESTRICT,
    channel_store_id uuid REFERENCES doms.channel_stores(id) ON DELETE RESTRICT,
    order_type_id uuid NOT NULL REFERENCES doms.order_types(id) ON DELETE RESTRICT,
    selling_organization_id uuid NOT NULL REFERENCES doms.selling_organizations(id) ON DELETE RESTRICT,
    requested_fulfillment_node_id uuid REFERENCES doms.fulfillment_nodes(id) ON DELETE RESTRICT,
    price_book_id uuid REFERENCES doms.price_books(id) ON DELETE RESTRICT,
    source_system_id uuid REFERENCES doms.external_systems(id) ON DELETE RESTRICT,
    external_order_id varchar(300),
    external_order_no varchar(300),
    idempotency_key varchar(200) NOT NULL,
    currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    order_status varchar(30) NOT NULL DEFAULT 'DRAFT',
    payment_status varchar(30) NOT NULL DEFAULT 'PENDING',
    fulfillment_status varchar(30) NOT NULL DEFAULT 'UNPLANNED',
    return_status varchar(30) NOT NULL DEFAULT 'NONE',
    risk_status varchar(30) NOT NULL DEFAULT 'NOT_ASSESSED',
    current_version_no integer NOT NULL DEFAULT 0,
    current_version_id uuid,
    ordered_at timestamptz,
    submitted_at timestamptz,
    confirmed_at timestamptz,
    completed_at timestamptz,
    cancelled_at timestamptz,
    requested_ship_at timestamptz,
    requested_delivery_at timestamptz,
    grand_total_amount numeric(24,6) NOT NULL DEFAULT 0,
    paid_amount numeric(24,6) NOT NULL DEFAULT 0,
    refunded_amount numeric(24,6) NOT NULL DEFAULT 0,
    status_reason_code_id uuid REFERENCES doms.reason_codes(id) ON DELETE RESTRICT,
    status_reason text,
    created_by uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    updated_by uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    source_metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    UNIQUE (tenant_id, order_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_doms_orders_number CHECK (btrim(order_no) <> ''),
    CONSTRAINT ck_doms_orders_source CHECK (order_source IN (
        'QUOTE','DIRECT','CHANNEL','API','EDI','RECURRING','REPLACEMENT','EXCHANGE','INTERNAL'
    )),
    CONSTRAINT ck_doms_orders_status CHECK (order_status IN (
        'DRAFT','VALIDATING','VALIDATION_FAILED','SUBMITTED','CONFIRMED','CHANGE_PENDING',
        'ON_HOLD','PARTIALLY_FULFILLED','FULFILLED','COMPLETED','CANCELLATION_PENDING',
        'CANCELLED','CLOSED'
    )),
    CONSTRAINT ck_doms_orders_payment_status CHECK (payment_status IN (
        'NOT_REQUIRED','PENDING','AUTHORIZED','PARTIALLY_PAID','PAID','PARTIALLY_REFUNDED',
        'REFUNDED','VOIDED','FAILED'
    )),
    CONSTRAINT ck_doms_orders_fulfillment_status CHECK (fulfillment_status IN (
        'UNPLANNED','PLANNING','PARTIALLY_ALLOCATED','ALLOCATED','RELEASED',
        'PARTIALLY_FULFILLED','FULFILLED','DELIVERY_FAILED','CANCELLED'
    )),
    CONSTRAINT ck_doms_orders_return_status CHECK (return_status IN (
        'NONE','REQUESTED','PARTIALLY_RETURNED','RETURNED','CLOSED'
    )),
    CONSTRAINT ck_doms_orders_risk_status CHECK (risk_status IN (
        'NOT_ASSESSED','PENDING','PASSED','REVIEW','BLOCKED','REJECTED'
    )),
    CONSTRAINT ck_doms_orders_version CHECK (
        (current_version_id IS NULL AND current_version_no = 0) OR
        (current_version_id IS NOT NULL AND current_version_no > 0)
    ),
    CONSTRAINT ck_doms_orders_channel_keys CHECK (
        (channel_account_id IS NULL OR sales_channel_id IS NOT NULL) AND
        (channel_store_id IS NULL OR channel_account_id IS NOT NULL) AND
        (external_order_id IS NULL OR btrim(external_order_id) <> '') AND
        (external_order_no IS NULL OR btrim(external_order_no) <> '') AND
        btrim(idempotency_key) <> '' AND
        (order_source <> 'CHANNEL' OR external_order_id IS NOT NULL)
    ),
    CONSTRAINT ck_doms_orders_dates CHECK (
        (submitted_at IS NULL OR submitted_at >= COALESCE(ordered_at, created_at)) AND
        (confirmed_at IS NULL OR confirmed_at >= COALESCE(submitted_at, ordered_at, created_at)) AND
        (completed_at IS NULL OR completed_at >= COALESCE(confirmed_at, submitted_at, ordered_at, created_at)) AND
        (cancelled_at IS NULL OR cancelled_at >= COALESCE(ordered_at, created_at)) AND
        (requested_delivery_at IS NULL OR requested_ship_at IS NULL OR requested_delivery_at >= requested_ship_at)
    ),
    CONSTRAINT ck_doms_orders_money CHECK (
        grand_total_amount >= 0 AND paid_amount >= 0 AND refunded_amount >= 0 AND
        paid_amount <= grand_total_amount AND refunded_amount <= paid_amount
    ),
    CONSTRAINT ck_doms_orders_metadata CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(source_metadata) AND
        NOT doms.jsonb_contains_forbidden_secret_key(attributes)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_orders_external_key
    ON doms.sales_orders (
        tenant_id, sales_channel_id,
        COALESCE(channel_account_id, '00000000-0000-0000-0000-000000000000'::uuid),
        COALESCE(channel_store_id, '00000000-0000-0000-0000-000000000000'::uuid),
        external_order_id
    ) WHERE external_order_id IS NOT NULL AND deleted_at IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_orders_idempotency
    ON doms.sales_orders (
        tenant_id,
        COALESCE(source_system_id, '00000000-0000-0000-0000-000000000000'::uuid),
        sales_channel_id, idempotency_key
    );

CREATE INDEX IF NOT EXISTS ix_doms_orders_customer_timeline
    ON doms.sales_orders (tenant_id, customer_id, created_at DESC, id);
CREATE INDEX IF NOT EXISTS ix_doms_orders_lifecycle
    ON doms.sales_orders (
        tenant_id, order_status, payment_status, fulfillment_status, risk_status, created_at, id
    ) WHERE deleted_at IS NULL;

CREATE TABLE IF NOT EXISTS doms.sales_order_totals (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    sales_order_id uuid NOT NULL REFERENCES doms.sales_orders(id) ON DELETE RESTRICT,
    currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    line_gross_amount numeric(24,6) NOT NULL DEFAULT 0,
    line_discount_amount numeric(24,6) NOT NULL DEFAULT 0,
    header_discount_amount numeric(24,6) NOT NULL DEFAULT 0,
    charge_amount numeric(24,6) NOT NULL DEFAULT 0,
    tax_amount numeric(24,6) NOT NULL DEFAULT 0,
    rounding_amount numeric(24,6) NOT NULL DEFAULT 0,
    grand_total_amount numeric(24,6) NOT NULL DEFAULT 0,
    authorized_amount numeric(24,6) NOT NULL DEFAULT 0,
    captured_amount numeric(24,6) NOT NULL DEFAULT 0,
    refunded_amount numeric(24,6) NOT NULL DEFAULT 0,
    outstanding_amount numeric(24,6) NOT NULL DEFAULT 0,
    calculation_version integer NOT NULL DEFAULT 1,
    calculated_at timestamptz NOT NULL DEFAULT now(),
    calculated_by uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, sales_order_id),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_doms_order_totals_version CHECK (calculation_version > 0),
    CONSTRAINT ck_doms_order_totals_amounts CHECK (
        line_gross_amount >= 0 AND line_discount_amount >= 0 AND
        header_discount_amount >= 0 AND charge_amount >= 0 AND tax_amount >= 0 AND
        grand_total_amount >= 0 AND authorized_amount >= 0 AND captured_amount >= 0 AND
        refunded_amount >= 0 AND outstanding_amount >= 0 AND
        line_discount_amount + header_discount_amount <= line_gross_amount + charge_amount AND
        refunded_amount <= captured_amount AND captured_amount <= grand_total_amount AND
        abs(grand_total_amount - (
            line_gross_amount - line_discount_amount - header_discount_amount +
            charge_amount + tax_amount + rounding_amount
        )) <= 0.000001 AND
        abs(outstanding_amount - (grand_total_amount - captured_amount + refunded_amount)) <= 0.000001
    )
);

CREATE TABLE IF NOT EXISTS doms.sales_order_lines (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    sales_order_id uuid NOT NULL REFERENCES doms.sales_orders(id) ON DELETE RESTRICT,
    line_no integer NOT NULL,
    external_line_id varchar(300),
    client_line_reference varchar(200),
    item_id uuid NOT NULL REFERENCES doms.items(id) ON DELETE RESTRICT,
    item_packaging_id uuid REFERENCES doms.item_packagings(id) ON DELETE RESTRICT,
    fulfillment_node_id uuid REFERENCES doms.fulfillment_nodes(id) ON DELETE RESTRICT,
    price_book_id uuid REFERENCES doms.price_books(id) ON DELETE RESTRICT,
    item_code_snapshot varchar(120) NOT NULL,
    item_name_snapshot varchar(300) NOT NULL,
    ordered_qty numeric(24,8) NOT NULL,
    cancelled_qty numeric(24,8) NOT NULL DEFAULT 0,
    fulfilled_qty numeric(24,8) NOT NULL DEFAULT 0,
    returned_qty numeric(24,8) NOT NULL DEFAULT 0,
    uom_code varchar(20) NOT NULL REFERENCES doms.units_of_measure(uom_code),
    currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    unit_list_price numeric(24,6) NOT NULL DEFAULT 0,
    unit_selling_price numeric(24,6) NOT NULL DEFAULT 0,
    gross_amount numeric(24,6) NOT NULL DEFAULT 0,
    discount_amount numeric(24,6) NOT NULL DEFAULT 0,
    charge_amount numeric(24,6) NOT NULL DEFAULT 0,
    tax_amount numeric(24,6) NOT NULL DEFAULT 0,
    net_amount numeric(24,6) NOT NULL DEFAULT 0,
    line_status varchar(30) NOT NULL DEFAULT 'OPEN',
    fulfillment_status varchar(30) NOT NULL DEFAULT 'UNPLANNED',
    return_status varchar(30) NOT NULL DEFAULT 'NONE',
    requested_ship_at timestamptz,
    requested_delivery_at timestamptz,
    status_reason_code_id uuid REFERENCES doms.reason_codes(id) ON DELETE RESTRICT,
    status_reason text,
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_by uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    updated_by uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    UNIQUE (tenant_id, id),
    UNIQUE (sales_order_id, line_no),
    CONSTRAINT ck_doms_order_lines_number CHECK (line_no > 0),
    CONSTRAINT ck_doms_order_lines_quantities CHECK (
        ordered_qty > 0 AND cancelled_qty >= 0 AND fulfilled_qty >= 0 AND returned_qty >= 0 AND
        cancelled_qty <= ordered_qty AND fulfilled_qty <= ordered_qty - cancelled_qty AND
        returned_qty <= fulfilled_qty
    ),
    CONSTRAINT ck_doms_order_lines_amounts CHECK (
        unit_list_price >= 0 AND unit_selling_price >= 0 AND gross_amount >= 0 AND
        discount_amount >= 0 AND charge_amount >= 0 AND tax_amount >= 0 AND net_amount >= 0 AND
        abs(gross_amount - round(ordered_qty * unit_selling_price, 6)) <= 0.000001 AND
        abs(net_amount - (gross_amount - discount_amount + charge_amount + tax_amount)) <= 0.000001
    ),
    CONSTRAINT ck_doms_order_lines_status CHECK (line_status IN (
        'OPEN','ON_HOLD','CHANGE_PENDING','CANCELLATION_PENDING','PARTIALLY_CANCELLED',
        'CANCELLED','CLOSED'
    )),
    CONSTRAINT ck_doms_order_lines_fulfillment CHECK (fulfillment_status IN (
        'UNPLANNED','PARTIALLY_ALLOCATED','ALLOCATED','RELEASED','PICKED','PACKED',
        'SHIPPED','DELIVERED','CANCELLED'
    )),
    CONSTRAINT ck_doms_order_lines_return CHECK (return_status IN (
        'NONE','REQUESTED','PARTIALLY_RETURNED','RETURNED','CLOSED'
    )),
    CONSTRAINT ck_doms_order_lines_dates CHECK (
        requested_delivery_at IS NULL OR requested_ship_at IS NULL OR
        requested_delivery_at >= requested_ship_at
    ),
    CONSTRAINT ck_doms_order_lines_attributes CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(attributes)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_order_lines_external
    ON doms.sales_order_lines (tenant_id, sales_order_id, external_line_id)
    WHERE external_line_id IS NOT NULL AND deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS ix_doms_order_lines_item
    ON doms.sales_order_lines (tenant_id, item_id, sales_order_id, line_no)
    WHERE deleted_at IS NULL;

CREATE TABLE IF NOT EXISTS doms.sales_order_line_relations (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    sales_order_id uuid NOT NULL REFERENCES doms.sales_orders(id) ON DELETE RESTRICT,
    parent_line_id uuid NOT NULL REFERENCES doms.sales_order_lines(id) ON DELETE RESTRICT,
    child_line_id uuid NOT NULL REFERENCES doms.sales_order_lines(id) ON DELETE RESTRICT,
    relation_type varchar(30) NOT NULL,
    quantity_factor numeric(24,8) NOT NULL DEFAULT 1,
    price_allocation_amount numeric(24,6) NOT NULL DEFAULT 0,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, parent_line_id, child_line_id, relation_type),
    CONSTRAINT ck_doms_order_line_rel_self CHECK (parent_line_id <> child_line_id),
    CONSTRAINT ck_doms_order_line_rel_type CHECK (relation_type IN (
        'BUNDLE_COMPONENT','KIT_COMPONENT','ADD_ON','GIFT','SUBSTITUTE','UPSELL',
        'CROSS_SELL','REPLACEMENT_FOR','EXCHANGE_FOR'
    )),
    CONSTRAINT ck_doms_order_line_rel_values CHECK (
        quantity_factor > 0 AND price_allocation_amount >= 0
    )
);

CREATE TABLE IF NOT EXISTS doms.sales_order_bundle_components (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    sales_order_id uuid NOT NULL REFERENCES doms.sales_orders(id) ON DELETE RESTRICT,
    bundle_line_id uuid NOT NULL REFERENCES doms.sales_order_lines(id) ON DELETE RESTRICT,
    component_sequence integer NOT NULL,
    component_item_id uuid NOT NULL REFERENCES doms.items(id) ON DELETE RESTRICT,
    component_item_code_snapshot varchar(120) NOT NULL,
    component_item_name_snapshot varchar(300) NOT NULL,
    quantity_per_bundle numeric(24,8) NOT NULL,
    total_component_qty numeric(24,8) NOT NULL,
    uom_code varchar(20) NOT NULL REFERENCES doms.units_of_measure(uom_code),
    allocated_price_amount numeric(24,6) NOT NULL DEFAULT 0,
    fulfillment_required boolean NOT NULL DEFAULT true,
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, bundle_line_id, component_sequence),
    CONSTRAINT ck_doms_bundle_component_seq CHECK (component_sequence > 0),
    CONSTRAINT ck_doms_bundle_component_qty CHECK (
        quantity_per_bundle > 0 AND total_component_qty > 0 AND allocated_price_amount >= 0
    ),
    CONSTRAINT ck_doms_bundle_component_attributes CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(attributes)
    )
);

CREATE TABLE IF NOT EXISTS doms.sales_order_versions (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    sales_order_id uuid NOT NULL REFERENCES doms.sales_orders(id) ON DELETE RESTRICT,
    version_no integer NOT NULL,
    version_type varchar(30) NOT NULL DEFAULT 'INITIAL',
    version_status varchar(20) NOT NULL DEFAULT 'DRAFT',
    source_entity_type varchar(40),
    source_entity_id uuid,
    order_status varchar(30) NOT NULL,
    payment_status varchar(30) NOT NULL,
    fulfillment_status varchar(30) NOT NULL,
    return_status varchar(30) NOT NULL,
    risk_status varchar(30) NOT NULL,
    currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    line_gross_amount numeric(24,6) NOT NULL DEFAULT 0,
    line_discount_amount numeric(24,6) NOT NULL DEFAULT 0,
    header_discount_amount numeric(24,6) NOT NULL DEFAULT 0,
    charge_amount numeric(24,6) NOT NULL DEFAULT 0,
    tax_amount numeric(24,6) NOT NULL DEFAULT 0,
    rounding_amount numeric(24,6) NOT NULL DEFAULT 0,
    grand_total_amount numeric(24,6) NOT NULL DEFAULT 0,
    snapshot_sha256 char(64),
    snapshot_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
    change_summary text,
    sealed_at timestamptz,
    sealed_by uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, sales_order_id, version_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_doms_order_versions_number CHECK (version_no > 0),
    CONSTRAINT ck_doms_order_versions_type CHECK (version_type IN (
        'INITIAL','CUSTOMER_CHANGE','OPERATIONS_CHANGE','CANCELLATION','REPLACEMENT','EXCHANGE','CORRECTION'
    )),
    CONSTRAINT ck_doms_order_versions_status CHECK (version_status IN ('DRAFT','SEALED','SUPERSEDED')),
    CONSTRAINT ck_doms_order_versions_order_status CHECK (order_status IN (
        'DRAFT','VALIDATING','VALIDATION_FAILED','SUBMITTED','CONFIRMED','CHANGE_PENDING',
        'ON_HOLD','PARTIALLY_FULFILLED','FULFILLED','COMPLETED','CANCELLATION_PENDING',
        'CANCELLED','CLOSED'
    )),
    CONSTRAINT ck_doms_order_versions_payment CHECK (payment_status IN (
        'NOT_REQUIRED','PENDING','AUTHORIZED','PARTIALLY_PAID','PAID','PARTIALLY_REFUNDED',
        'REFUNDED','VOIDED','FAILED'
    )),
    CONSTRAINT ck_doms_order_versions_fulfillment CHECK (fulfillment_status IN (
        'UNPLANNED','PLANNING','PARTIALLY_ALLOCATED','ALLOCATED','RELEASED',
        'PARTIALLY_FULFILLED','FULFILLED','DELIVERY_FAILED','CANCELLED'
    )),
    CONSTRAINT ck_doms_order_versions_return CHECK (return_status IN (
        'NONE','REQUESTED','PARTIALLY_RETURNED','RETURNED','CLOSED'
    )),
    CONSTRAINT ck_doms_order_versions_risk CHECK (risk_status IN (
        'NOT_ASSESSED','PENDING','PASSED','REVIEW','BLOCKED','REJECTED'
    )),
    CONSTRAINT ck_doms_order_versions_source CHECK (
        (source_entity_type IS NULL AND source_entity_id IS NULL) OR
        (source_entity_type IS NOT NULL AND source_entity_id IS NOT NULL)
    ),
    CONSTRAINT ck_doms_order_versions_amounts CHECK (
        line_gross_amount >= 0 AND line_discount_amount >= 0 AND header_discount_amount >= 0 AND
        charge_amount >= 0 AND tax_amount >= 0 AND grand_total_amount >= 0 AND
        abs(grand_total_amount - (
            line_gross_amount - line_discount_amount - header_discount_amount +
            charge_amount + tax_amount + rounding_amount
        )) <= 0.000001
    ),
    CONSTRAINT ck_doms_order_versions_sealed CHECK (
        (version_status = 'DRAFT' AND sealed_at IS NULL AND sealed_by IS NULL AND snapshot_sha256 IS NULL) OR
        (version_status IN ('SEALED','SUPERSEDED') AND sealed_at IS NOT NULL AND sealed_by IS NOT NULL AND
         snapshot_sha256 ~ '^[0-9A-Fa-f]{64}$')
    ),
    CONSTRAINT ck_doms_order_versions_payload CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(snapshot_payload)
    )
);

CREATE TABLE IF NOT EXISTS doms.sales_order_version_lines (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    sales_order_id uuid NOT NULL REFERENCES doms.sales_orders(id) ON DELETE RESTRICT,
    sales_order_version_id uuid NOT NULL REFERENCES doms.sales_order_versions(id) ON DELETE RESTRICT,
    sales_order_line_id uuid NOT NULL REFERENCES doms.sales_order_lines(id) ON DELETE RESTRICT,
    line_no integer NOT NULL,
    item_id uuid NOT NULL REFERENCES doms.items(id) ON DELETE RESTRICT,
    item_code_snapshot varchar(120) NOT NULL,
    item_name_snapshot varchar(300) NOT NULL,
    ordered_qty numeric(24,8) NOT NULL,
    cancelled_qty numeric(24,8) NOT NULL DEFAULT 0,
    uom_code varchar(20) NOT NULL REFERENCES doms.units_of_measure(uom_code),
    currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    unit_selling_price numeric(24,6) NOT NULL,
    gross_amount numeric(24,6) NOT NULL,
    discount_amount numeric(24,6) NOT NULL DEFAULT 0,
    charge_amount numeric(24,6) NOT NULL DEFAULT 0,
    tax_amount numeric(24,6) NOT NULL DEFAULT 0,
    net_amount numeric(24,6) NOT NULL,
    line_status varchar(30) NOT NULL,
    fulfillment_status varchar(30) NOT NULL,
    return_status varchar(30) NOT NULL,
    snapshot_attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, sales_order_version_id, line_no),
    UNIQUE (sales_order_version_id, sales_order_line_id),
    CONSTRAINT ck_doms_order_version_lines_number CHECK (line_no > 0),
    CONSTRAINT ck_doms_order_version_lines_qty CHECK (
        ordered_qty > 0 AND cancelled_qty >= 0 AND cancelled_qty <= ordered_qty
    ),
    CONSTRAINT ck_doms_order_version_lines_amounts CHECK (
        unit_selling_price >= 0 AND gross_amount >= 0 AND discount_amount >= 0 AND
        charge_amount >= 0 AND tax_amount >= 0 AND net_amount >= 0 AND
        abs(gross_amount - round(ordered_qty * unit_selling_price, 6)) <= 0.000001 AND
        abs(net_amount - (gross_amount - discount_amount + charge_amount + tax_amount)) <= 0.000001
    ),
    CONSTRAINT ck_doms_order_version_lines_payload CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(snapshot_attributes)
    )
);

DO $block$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'doms.sales_orders'::regclass
          AND conname = 'fk_doms_orders_current_version'
    ) THEN
        ALTER TABLE doms.sales_orders
            ADD CONSTRAINT fk_doms_orders_current_version
            FOREIGN KEY (current_version_id) REFERENCES doms.sales_order_versions(id) ON DELETE RESTRICT;
    END IF;
END;
$block$;

-- Version-bound party, address, and contact snapshots. PII is encrypted or masked;
-- searchable hashes are evidence/lookup aids and are never customer identity or merge keys.
CREATE TABLE IF NOT EXISTS doms.order_parties (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    sales_order_id uuid NOT NULL REFERENCES doms.sales_orders(id) ON DELETE RESTRICT,
    sales_order_version_id uuid NOT NULL REFERENCES doms.sales_order_versions(id) ON DELETE RESTRICT,
    party_role varchar(30) NOT NULL,
    sequence_no integer NOT NULL DEFAULT 1,
    customer_id uuid REFERENCES doms.customers(id) ON DELETE RESTRICT,
    business_partner_id uuid REFERENCES doms.business_partners(id) ON DELETE RESTRICT,
    party_no_snapshot varchar(120),
    party_name_encrypted text,
    party_name_masked varchar(300),
    tax_identifier_encrypted text,
    tax_identifier_hash char(64),
    tax_identifier_masked varchar(120),
    country_code char(2) REFERENCES doms.countries(country_code),
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, sales_order_version_id, party_role, sequence_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_doms_order_parties_role CHECK (party_role IN (
        'CUSTOMER','BUYER','SELLER','BILL_TO','SHIP_TO','PAYER','RECIPIENT','BENEFICIARY','AGENT'
    )),
    CONSTRAINT ck_doms_order_parties_sequence CHECK (sequence_no > 0),
    CONSTRAINT ck_doms_order_parties_identity CHECK (
        customer_id IS NOT NULL OR business_partner_id IS NOT NULL OR
        party_name_encrypted IS NOT NULL OR party_name_masked IS NOT NULL
    ),
    CONSTRAINT ck_doms_order_parties_tax_hash CHECK (
        tax_identifier_hash IS NULL OR tax_identifier_hash ~ '^[0-9A-Fa-f]{64}$'
    ),
    CONSTRAINT ck_doms_order_parties_attributes CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(attributes)
    )
);

CREATE TABLE IF NOT EXISTS doms.order_address_snapshots (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    sales_order_id uuid NOT NULL REFERENCES doms.sales_orders(id) ON DELETE RESTRICT,
    sales_order_version_id uuid NOT NULL REFERENCES doms.sales_order_versions(id) ON DELETE RESTRICT,
    order_party_id uuid NOT NULL REFERENCES doms.order_parties(id) ON DELETE RESTRICT,
    address_type varchar(30) NOT NULL,
    sequence_no integer NOT NULL DEFAULT 1,
    recipient_name_encrypted text,
    recipient_name_masked varchar(200),
    address_line1_encrypted text NOT NULL,
    address_line2_encrypted text,
    city_encrypted text,
    city_masked varchar(120),
    province_encrypted text,
    province_masked varchar(120),
    postal_code_encrypted text,
    postal_code_hash char(64),
    postal_code_masked varchar(40),
    country_code char(2) NOT NULL REFERENCES doms.countries(country_code),
    delivery_instructions_encrypted text,
    address_fingerprint_hash char(64),
    validation_status varchar(20) NOT NULL DEFAULT 'UNVALIDATED',
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, sales_order_version_id, order_party_id, address_type, sequence_no),
    CONSTRAINT ck_doms_order_addresses_type CHECK (address_type IN (
        'BILLING','SHIPPING','PICKUP','RETURN','SOLD_TO','SERVICE'
    )),
    CONSTRAINT ck_doms_order_addresses_sequence CHECK (sequence_no > 0),
    CONSTRAINT ck_doms_order_addresses_status CHECK (validation_status IN (
        'UNVALIDATED','VALID','CORRECTED','AMBIGUOUS','INVALID','OVERRIDDEN'
    )),
    CONSTRAINT ck_doms_order_addresses_hashes CHECK (
        (postal_code_hash IS NULL OR postal_code_hash ~ '^[0-9A-Fa-f]{64}$') AND
        (address_fingerprint_hash IS NULL OR address_fingerprint_hash ~ '^[0-9A-Fa-f]{64}$')
    ),
    CONSTRAINT ck_doms_order_addresses_metadata CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(metadata)
    )
);

CREATE TABLE IF NOT EXISTS doms.order_contact_snapshots (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    sales_order_id uuid NOT NULL REFERENCES doms.sales_orders(id) ON DELETE RESTRICT,
    sales_order_version_id uuid NOT NULL REFERENCES doms.sales_order_versions(id) ON DELETE RESTRICT,
    order_party_id uuid NOT NULL REFERENCES doms.order_parties(id) ON DELETE RESTRICT,
    contact_type varchar(30) NOT NULL,
    sequence_no integer NOT NULL DEFAULT 1,
    contact_name_encrypted text,
    contact_name_masked varchar(200),
    email_encrypted text,
    email_search_hash char(64),
    email_masked varchar(320),
    phone_encrypted text,
    phone_search_hash char(64),
    phone_masked varchar(50),
    preferred_language varchar(20),
    preferred_contact_method varchar(20),
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, sales_order_version_id, order_party_id, contact_type, sequence_no),
    CONSTRAINT ck_doms_order_contacts_type CHECK (contact_type IN (
        'PRIMARY','BILLING','SHIPPING','DELIVERY','PICKUP','RETURN','SERVICE'
    )),
    CONSTRAINT ck_doms_order_contacts_sequence CHECK (sequence_no > 0),
    CONSTRAINT ck_doms_order_contacts_method CHECK (
        preferred_contact_method IS NULL OR preferred_contact_method IN ('EMAIL','PHONE','SMS','PUSH','NONE')
    ),
    CONSTRAINT ck_doms_order_contacts_hashes CHECK (
        (email_search_hash IS NULL OR email_search_hash ~ '^[0-9A-Fa-f]{64}$') AND
        (phone_search_hash IS NULL OR phone_search_hash ~ '^[0-9A-Fa-f]{64}$')
    ),
    CONSTRAINT ck_doms_order_contacts_metadata CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(metadata)
    )
);

COMMENT ON COLUMN doms.order_contact_snapshots.email_search_hash IS
    'Order-version contact lookup aid only. It must never identify, link, or merge customers or Firebase accounts.';
COMMENT ON COLUMN doms.order_contact_snapshots.email_encrypted IS
    'Encrypted point-in-time order contact. Encryption keys remain outside PostgreSQL.';

CREATE TABLE IF NOT EXISTS doms.order_charges (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    sales_order_id uuid NOT NULL REFERENCES doms.sales_orders(id) ON DELETE RESTRICT,
    sales_order_line_id uuid REFERENCES doms.sales_order_lines(id) ON DELETE RESTRICT,
    sequence_no integer NOT NULL,
    charge_code_id uuid REFERENCES doms.charge_codes(id) ON DELETE RESTRICT,
    charge_type varchar(30) NOT NULL,
    charge_code_snapshot varchar(80) NOT NULL,
    charge_name_snapshot varchar(200) NOT NULL,
    calculation_basis varchar(30) NOT NULL DEFAULT 'FLAT',
    basis_quantity numeric(24,8),
    rate_value numeric(24,8),
    currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    amount numeric(24,6) NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'APPLIED',
    reversed_at timestamptz,
    reversal_reason text,
    calculation_details jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, sales_order_id, sequence_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_doms_order_charges_sequence CHECK (sequence_no > 0),
    CONSTRAINT ck_doms_order_charges_type CHECK (charge_type IN (
        'SHIPPING','HANDLING','SERVICE','GIFT_WRAP','SURCHARGE','DUTY','CUSTOMS','ENVIRONMENTAL','OTHER'
    )),
    CONSTRAINT ck_doms_order_charges_basis CHECK (calculation_basis IN (
        'FLAT','QUANTITY','WEIGHT','VOLUME','PERCENT','ACTUAL'
    )),
    CONSTRAINT ck_doms_order_charges_values CHECK (
        amount >= 0 AND (basis_quantity IS NULL OR basis_quantity >= 0) AND
        (rate_value IS NULL OR rate_value >= 0)
    ),
    CONSTRAINT ck_doms_order_charges_status CHECK (status IN ('ESTIMATED','APPLIED','WAIVED','REVERSED')),
    CONSTRAINT ck_doms_order_charges_reversal CHECK (
        (status = 'REVERSED' AND reversed_at IS NOT NULL AND reversal_reason IS NOT NULL AND btrim(reversal_reason) <> '') OR
        (status <> 'REVERSED' AND reversed_at IS NULL)
    ),
    CONSTRAINT ck_doms_order_charges_details CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(calculation_details)
    )
);

CREATE INDEX IF NOT EXISTS ix_doms_order_charges_order_line
    ON doms.order_charges (tenant_id, sales_order_id, sales_order_line_id, status);

CREATE TABLE IF NOT EXISTS doms.order_discount_adjustments (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    sales_order_id uuid NOT NULL REFERENCES doms.sales_orders(id) ON DELETE RESTRICT,
    sales_order_line_id uuid REFERENCES doms.sales_order_lines(id) ON DELETE RESTRICT,
    sequence_no integer NOT NULL,
    promotion_id uuid REFERENCES doms.promotions(id) ON DELETE RESTRICT,
    adjustment_type varchar(30) NOT NULL,
    adjustment_code varchar(100),
    description varchar(500),
    currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    amount numeric(24,6) NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'APPLIED',
    manual_approval_required boolean NOT NULL DEFAULT false,
    approved_by uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    approved_at timestamptz,
    reversed_at timestamptz,
    reversal_reason text,
    calculation_details jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, sales_order_id, sequence_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_doms_order_discounts_sequence CHECK (sequence_no > 0),
    CONSTRAINT ck_doms_order_discounts_type CHECK (adjustment_type IN (
        'PROMOTION','COUPON','CUSTOMER_GROUP','CONTRACT','MANUAL','PRICE_MATCH','GOODWILL','ROUNDING'
    )),
    CONSTRAINT ck_doms_order_discounts_amount CHECK (amount >= 0),
    CONSTRAINT ck_doms_order_discounts_status CHECK (status IN ('PENDING','APPLIED','REJECTED','REVERSED')),
    CONSTRAINT ck_doms_order_discounts_approval CHECK (
        NOT manual_approval_required OR status <> 'APPLIED' OR
        (approved_by IS NOT NULL AND approved_at IS NOT NULL)
    ),
    CONSTRAINT ck_doms_order_discounts_reversal CHECK (
        (status = 'REVERSED' AND reversed_at IS NOT NULL AND reversal_reason IS NOT NULL AND btrim(reversal_reason) <> '') OR
        (status <> 'REVERSED' AND reversed_at IS NULL)
    ),
    CONSTRAINT ck_doms_order_discounts_details CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(calculation_details)
    )
);

CREATE INDEX IF NOT EXISTS ix_doms_order_discounts_order_line
    ON doms.order_discount_adjustments (tenant_id, sales_order_id, sales_order_line_id, status);

CREATE TABLE IF NOT EXISTS doms.order_taxes (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    sales_order_id uuid NOT NULL REFERENCES doms.sales_orders(id) ON DELETE RESTRICT,
    sales_order_line_id uuid REFERENCES doms.sales_order_lines(id) ON DELETE RESTRICT,
    sequence_no integer NOT NULL,
    tax_code_id uuid REFERENCES doms.tax_codes(id) ON DELETE RESTRICT,
    tax_code_snapshot varchar(80) NOT NULL,
    tax_name_snapshot varchar(200) NOT NULL,
    jurisdiction_country_code char(2) REFERENCES doms.countries(country_code),
    jurisdiction_code varchar(100),
    taxable_amount numeric(24,6) NOT NULL,
    tax_rate_percent numeric(12,8) NOT NULL,
    tax_amount numeric(24,6) NOT NULL,
    currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    price_includes_tax boolean NOT NULL DEFAULT false,
    status varchar(20) NOT NULL DEFAULT 'APPLIED',
    reversed_at timestamptz,
    reversal_reason text,
    calculation_details jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, sales_order_id, sequence_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_doms_order_taxes_sequence CHECK (sequence_no > 0),
    CONSTRAINT ck_doms_order_taxes_values CHECK (
        taxable_amount >= 0 AND tax_rate_percent BETWEEN 0 AND 100 AND tax_amount >= 0
    ),
    CONSTRAINT ck_doms_order_taxes_status CHECK (status IN ('ESTIMATED','APPLIED','EXEMPT','REVERSED')),
    CONSTRAINT ck_doms_order_taxes_reversal CHECK (
        (status = 'REVERSED' AND reversed_at IS NOT NULL AND reversal_reason IS NOT NULL AND btrim(reversal_reason) <> '') OR
        (status <> 'REVERSED' AND reversed_at IS NULL)
    ),
    CONSTRAINT ck_doms_order_taxes_details CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(calculation_details)
    )
);

CREATE INDEX IF NOT EXISTS ix_doms_order_taxes_order_line
    ON doms.order_taxes (tenant_id, sales_order_id, sales_order_line_id, status);

CREATE TABLE IF NOT EXISTS doms.order_promotions (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    sales_order_id uuid NOT NULL REFERENCES doms.sales_orders(id) ON DELETE RESTRICT,
    promotion_id uuid NOT NULL REFERENCES doms.promotions(id) ON DELETE RESTRICT,
    promotion_version_id uuid REFERENCES doms.promotion_versions(id) ON DELETE RESTRICT,
    discount_adjustment_id uuid REFERENCES doms.order_discount_adjustments(id) ON DELETE RESTRICT,
    evaluation_sequence integer NOT NULL,
    promotion_code_snapshot varchar(80) NOT NULL,
    promotion_name_snapshot varchar(200) NOT NULL,
    currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    applied_discount_amount numeric(24,6) NOT NULL DEFAULT 0,
    status varchar(20) NOT NULL DEFAULT 'APPLIED',
    eligibility_result varchar(20) NOT NULL DEFAULT 'ELIGIBLE',
    evaluation_details jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, sales_order_id, promotion_id, evaluation_sequence),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_doms_order_promotions_sequence CHECK (evaluation_sequence > 0),
    CONSTRAINT ck_doms_order_promotions_amount CHECK (applied_discount_amount >= 0),
    CONSTRAINT ck_doms_order_promotions_status CHECK (status IN ('CANDIDATE','APPLIED','REJECTED','REVERSED')),
    CONSTRAINT ck_doms_order_promotions_eligibility CHECK (eligibility_result IN (
        'ELIGIBLE','INELIGIBLE','LIMIT_EXCEEDED','CONFLICT','EXPIRED','MANUAL_REVIEW'
    )),
    CONSTRAINT ck_doms_order_promotions_details CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(evaluation_details)
    )
);

CREATE TABLE IF NOT EXISTS doms.order_promotion_lines (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    order_promotion_id uuid NOT NULL REFERENCES doms.order_promotions(id) ON DELETE RESTRICT,
    sales_order_id uuid NOT NULL REFERENCES doms.sales_orders(id) ON DELETE RESTRICT,
    sales_order_line_id uuid NOT NULL REFERENCES doms.sales_order_lines(id) ON DELETE RESTRICT,
    currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    allocated_discount_amount numeric(24,6) NOT NULL DEFAULT 0,
    reward_quantity numeric(24,8),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, order_promotion_id, sales_order_line_id),
    CONSTRAINT ck_doms_order_promotion_lines_values CHECK (
        allocated_discount_amount >= 0 AND (reward_quantity IS NULL OR reward_quantity > 0)
    )
);

CREATE TABLE IF NOT EXISTS doms.order_coupon_redemptions (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    sales_order_id uuid NOT NULL REFERENCES doms.sales_orders(id) ON DELETE RESTRICT,
    customer_id uuid NOT NULL REFERENCES doms.customers(id) ON DELETE RESTRICT,
    coupon_id uuid NOT NULL REFERENCES doms.coupons(id) ON DELETE RESTRICT,
    order_promotion_id uuid REFERENCES doms.order_promotions(id) ON DELETE RESTRICT,
    discount_adjustment_id uuid REFERENCES doms.order_discount_adjustments(id) ON DELETE RESTRICT,
    coupon_code_hash char(64) NOT NULL,
    coupon_code_masked varchar(80) NOT NULL,
    currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    redeemed_amount numeric(24,6) NOT NULL DEFAULT 0,
    redemption_status varchar(20) NOT NULL DEFAULT 'RESERVED',
    idempotency_key varchar(200) NOT NULL,
    reserved_at timestamptz NOT NULL DEFAULT now(),
    redeemed_at timestamptz,
    released_at timestamptz,
    reversed_at timestamptz,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, idempotency_key),
    CONSTRAINT ck_doms_order_coupon_hash CHECK (coupon_code_hash ~ '^[0-9A-Fa-f]{64}$'),
    CONSTRAINT ck_doms_order_coupon_amount CHECK (redeemed_amount >= 0),
    CONSTRAINT ck_doms_order_coupon_status CHECK (redemption_status IN (
        'RESERVED','REDEEMED','RELEASED','REJECTED','REVERSED'
    )),
    CONSTRAINT ck_doms_order_coupon_dates CHECK (
        (redeemed_at IS NULL OR redeemed_at >= reserved_at) AND
        (released_at IS NULL OR released_at >= reserved_at) AND
        (reversed_at IS NULL OR reversed_at >= COALESCE(redeemed_at, reserved_at))
    ),
    CONSTRAINT ck_doms_order_coupon_metadata CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(metadata)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_order_coupon_active
    ON doms.order_coupon_redemptions (tenant_id, sales_order_id, coupon_code_hash)
    WHERE redemption_status IN ('RESERVED','REDEEMED');

CREATE TABLE IF NOT EXISTS doms.sales_order_status_events (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    sales_order_id uuid NOT NULL REFERENCES doms.sales_orders(id) ON DELETE RESTRICT,
    status_axis varchar(20) NOT NULL,
    from_status varchar(40),
    to_status varchar(40) NOT NULL,
    reason_code_id uuid REFERENCES doms.reason_codes(id) ON DELETE RESTRICT,
    reason_text text,
    changed_by uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    correlation_id varchar(100),
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_doms_order_status_event_axis CHECK (status_axis IN (
        'ORDER','PAYMENT','FULFILLMENT','RETURN','RISK'
    )),
    CONSTRAINT ck_doms_order_status_event_values CHECK (
        btrim(to_status) <> '' AND (from_status IS NULL OR btrim(from_status) <> '') AND
        from_status IS DISTINCT FROM to_status
    ),
    CONSTRAINT ck_doms_order_status_event_metadata CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(metadata)
    )
);

CREATE INDEX IF NOT EXISTS ix_doms_order_status_events_timeline
    ON doms.sales_order_status_events (tenant_id, sales_order_id, occurred_at, id);

CREATE TABLE IF NOT EXISTS doms.sales_order_line_status_events (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    sales_order_id uuid NOT NULL REFERENCES doms.sales_orders(id) ON DELETE RESTRICT,
    sales_order_line_id uuid NOT NULL REFERENCES doms.sales_order_lines(id) ON DELETE RESTRICT,
    status_axis varchar(20) NOT NULL,
    from_status varchar(40),
    to_status varchar(40) NOT NULL,
    reason_code_id uuid REFERENCES doms.reason_codes(id) ON DELETE RESTRICT,
    reason_text text,
    changed_by uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    correlation_id varchar(100),
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_doms_order_line_event_axis CHECK (status_axis IN (
        'LINE','FULFILLMENT','RETURN'
    )),
    CONSTRAINT ck_doms_order_line_event_values CHECK (
        btrim(to_status) <> '' AND (from_status IS NULL OR btrim(from_status) <> '') AND
        from_status IS DISTINCT FROM to_status
    ),
    CONSTRAINT ck_doms_order_line_event_metadata CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(metadata)
    )
);

CREATE INDEX IF NOT EXISTS ix_doms_order_line_events_timeline
    ON doms.sales_order_line_status_events (
        tenant_id, sales_order_id, sales_order_line_id, occurred_at, id
    );

CREATE TABLE IF NOT EXISTS doms.order_holds (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    sales_order_id uuid NOT NULL REFERENCES doms.sales_orders(id) ON DELETE RESTRICT,
    sales_order_line_id uuid REFERENCES doms.sales_order_lines(id) ON DELETE RESTRICT,
    hold_code varchar(80) NOT NULL,
    hold_type varchar(30) NOT NULL,
    hold_status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    severity varchar(20) NOT NULL DEFAULT 'BLOCKING',
    source_type varchar(30) NOT NULL DEFAULT 'SYSTEM',
    source_reference varchar(200),
    reason_code_id uuid REFERENCES doms.reason_codes(id) ON DELETE RESTRICT,
    reason_text text,
    blocks_submission boolean NOT NULL DEFAULT false,
    blocks_confirmation boolean NOT NULL DEFAULT true,
    blocks_payment boolean NOT NULL DEFAULT false,
    blocks_fulfillment boolean NOT NULL DEFAULT true,
    blocks_cancellation boolean NOT NULL DEFAULT false,
    placed_by uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    placed_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz,
    released_by uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    released_at timestamptz,
    release_reason text,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_doms_order_holds_code CHECK (btrim(hold_code) <> ''),
    CONSTRAINT ck_doms_order_holds_type CHECK (hold_type IN (
        'VALIDATION','PAYMENT','RISK','FRAUD','INVENTORY','PRICING','TAX','COMPLIANCE',
        'CUSTOMER_SERVICE','ADDRESS','MANUAL','OTHER'
    )),
    CONSTRAINT ck_doms_order_holds_status CHECK (hold_status IN (
        'ACTIVE','RELEASE_PENDING','RELEASED','EXPIRED','CANCELLED'
    )),
    CONSTRAINT ck_doms_order_holds_severity CHECK (severity IN ('INFO','WARNING','BLOCKING','CRITICAL')),
    CONSTRAINT ck_doms_order_holds_source CHECK (source_type IN ('SYSTEM','RULE','USER','INTEGRATION','WORKFLOW')),
    CONSTRAINT ck_doms_order_holds_dates CHECK (
        (expires_at IS NULL OR expires_at > placed_at) AND
        (released_at IS NULL OR released_at >= placed_at)
    ),
    CONSTRAINT ck_doms_order_holds_release CHECK (
        hold_status NOT IN ('RELEASED','EXPIRED','CANCELLED') OR released_at IS NOT NULL
    ),
    CONSTRAINT ck_doms_order_holds_metadata CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(metadata)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_order_holds_active
    ON doms.order_holds (
        tenant_id, sales_order_id,
        COALESCE(sales_order_line_id, '00000000-0000-0000-0000-000000000000'::uuid),
        hold_code
    ) WHERE hold_status IN ('ACTIVE','RELEASE_PENDING');

CREATE INDEX IF NOT EXISTS ix_doms_order_holds_queue
    ON doms.order_holds (tenant_id, hold_status, severity, placed_at, id)
    WHERE hold_status IN ('ACTIVE','RELEASE_PENDING');

CREATE TABLE IF NOT EXISTS doms.order_hold_events (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    sales_order_id uuid NOT NULL REFERENCES doms.sales_orders(id) ON DELETE RESTRICT,
    order_hold_id uuid NOT NULL REFERENCES doms.order_holds(id) ON DELETE RESTRICT,
    event_type varchar(30) NOT NULL,
    from_status varchar(20),
    to_status varchar(20) NOT NULL,
    actor_user_id uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    reason_text text,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_doms_order_hold_events_type CHECK (event_type IN (
        'PLACED','ESCALATED','RELEASE_REQUESTED','RELEASED','EXPIRED','CANCELLED','COMMENTED'
    )),
    CONSTRAINT ck_doms_order_hold_events_metadata CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(metadata)
    )
);

CREATE INDEX IF NOT EXISTS ix_doms_order_hold_events_timeline
    ON doms.order_hold_events (tenant_id, order_hold_id, occurred_at, id);

CREATE TABLE IF NOT EXISTS doms.order_events (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    sales_order_id uuid NOT NULL REFERENCES doms.sales_orders(id) ON DELETE RESTRICT,
    sales_order_line_id uuid REFERENCES doms.sales_order_lines(id) ON DELETE RESTRICT,
    event_type varchar(80) NOT NULL,
    event_source varchar(30) NOT NULL DEFAULT 'DOMS',
    source_system_id uuid REFERENCES doms.external_systems(id) ON DELETE RESTRICT,
    external_event_id varchar(300),
    idempotency_key varchar(200),
    correlation_id varchar(100),
    causation_id varchar(100),
    actor_user_id uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    payload jsonb NOT NULL DEFAULT '{}'::jsonb,
    occurred_at timestamptz NOT NULL,
    received_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_doms_order_events_type CHECK (btrim(event_type) <> ''),
    CONSTRAINT ck_doms_order_events_source CHECK (event_source IN (
        'DOMS','CHANNEL','CUSTOMER','PAYMENT','FULFILLMENT','RISK','WORKFLOW','INTEGRATION'
    )),
    CONSTRAINT ck_doms_order_events_dates CHECK (received_at >= occurred_at),
    CONSTRAINT ck_doms_order_events_payload CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(payload)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_order_events_external
    ON doms.order_events (
        tenant_id,
        COALESCE(source_system_id, '00000000-0000-0000-0000-000000000000'::uuid),
        external_event_id
    ) WHERE external_event_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_order_events_idempotency
    ON doms.order_events (tenant_id, idempotency_key)
    WHERE idempotency_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_doms_order_events_timeline
    ON doms.order_events (tenant_id, sales_order_id, occurred_at, id);

CREATE TABLE IF NOT EXISTS doms.order_validation_runs (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    sales_order_id uuid NOT NULL REFERENCES doms.sales_orders(id) ON DELETE RESTRICT,
    sales_order_version_id uuid REFERENCES doms.sales_order_versions(id) ON DELETE RESTRICT,
    run_no integer NOT NULL,
    validation_scope varchar(30) NOT NULL DEFAULT 'FULL',
    validation_status varchar(20) NOT NULL DEFAULT 'PENDING',
    ruleset_version varchar(100),
    requested_by uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    started_at timestamptz,
    completed_at timestamptz,
    blocking_error_count integer NOT NULL DEFAULT 0,
    warning_count integer NOT NULL DEFAULT 0,
    context_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, sales_order_id, run_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_doms_order_validation_run_no CHECK (run_no > 0),
    CONSTRAINT ck_doms_order_validation_scope CHECK (validation_scope IN (
        'FULL','PRICING','TAX','PAYMENT','RISK','INVENTORY','ADDRESS','CHANNEL','CHANGE','CANCELLATION'
    )),
    CONSTRAINT ck_doms_order_validation_status CHECK (validation_status IN (
        'PENDING','RUNNING','PASSED','PASSED_WITH_WARNINGS','FAILED','CANCELLED'
    )),
    CONSTRAINT ck_doms_order_validation_counts CHECK (
        blocking_error_count >= 0 AND warning_count >= 0
    ),
    CONSTRAINT ck_doms_order_validation_dates CHECK (
        (started_at IS NULL OR started_at >= created_at) AND
        (completed_at IS NULL OR completed_at >= COALESCE(started_at, created_at))
    ),
    CONSTRAINT ck_doms_order_validation_context CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(context_snapshot)
    )
);

CREATE TABLE IF NOT EXISTS doms.order_validation_results (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    order_validation_run_id uuid NOT NULL REFERENCES doms.order_validation_runs(id) ON DELETE RESTRICT,
    sales_order_id uuid NOT NULL REFERENCES doms.sales_orders(id) ON DELETE RESTRICT,
    sales_order_line_id uuid REFERENCES doms.sales_order_lines(id) ON DELETE RESTRICT,
    rule_code varchar(120) NOT NULL,
    severity varchar(20) NOT NULL,
    result_status varchar(20) NOT NULL,
    field_path varchar(500),
    message_code varchar(120),
    message_masked text,
    remediation_code varchar(120),
    evidence jsonb NOT NULL DEFAULT '{}'::jsonb,
    evaluated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, order_validation_run_id, rule_code, sales_order_line_id, field_path),
    CONSTRAINT ck_doms_order_validation_severity CHECK (severity IN ('INFO','WARNING','ERROR','BLOCKING')),
    CONSTRAINT ck_doms_order_validation_result CHECK (result_status IN ('PASSED','FAILED','SKIPPED','OVERRIDDEN')),
    CONSTRAINT ck_doms_order_validation_evidence CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(evidence)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_order_validation_result_scope
    ON doms.order_validation_results (
        tenant_id, order_validation_run_id, rule_code,
        COALESCE(sales_order_line_id, '00000000-0000-0000-0000-000000000000'::uuid),
        COALESCE(field_path, '')
    );

CREATE TABLE IF NOT EXISTS doms.order_change_requests (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    change_request_no varchar(100) NOT NULL,
    sales_order_id uuid NOT NULL REFERENCES doms.sales_orders(id) ON DELETE RESTRICT,
    base_version_id uuid NOT NULL REFERENCES doms.sales_order_versions(id) ON DELETE RESTRICT,
    result_version_id uuid REFERENCES doms.sales_order_versions(id) ON DELETE RESTRICT,
    request_type varchar(30) NOT NULL,
    request_status varchar(30) NOT NULL DEFAULT 'REQUESTED',
    idempotency_key varchar(200) NOT NULL,
    requested_by_customer boolean NOT NULL DEFAULT false,
    requested_by uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    requested_at timestamptz NOT NULL DEFAULT now(),
    reason_code_id uuid REFERENCES doms.reason_codes(id) ON DELETE RESTRICT,
    reason_text text,
    approved_by uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    approved_at timestamptz,
    applied_by uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    applied_at timestamptz,
    rejected_at timestamptz,
    rejection_reason text,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, change_request_no),
    UNIQUE (tenant_id, idempotency_key),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_doms_order_changes_type CHECK (request_type IN (
        'LINE_CHANGE','ADDRESS_CHANGE','CONTACT_CHANGE','DELIVERY_CHANGE','PAYMENT_CHANGE',
        'PROMOTION_CHANGE','CUSTOMER_CHANGE','MIXED'
    )),
    CONSTRAINT ck_doms_order_changes_status CHECK (request_status IN (
        'REQUESTED','VALIDATING','APPROVAL_PENDING','APPROVED','REJECTED','APPLYING',
        'APPLIED','FAILED','CANCELLED'
    )),
    CONSTRAINT ck_doms_order_changes_result CHECK (
        request_status <> 'APPLIED' OR (result_version_id IS NOT NULL AND applied_at IS NOT NULL)
    ),
    CONSTRAINT ck_doms_order_changes_approval CHECK (
        request_status NOT IN ('APPROVED','APPLYING','APPLIED') OR
        (approved_by IS NOT NULL AND approved_at IS NOT NULL)
    ),
    CONSTRAINT ck_doms_order_changes_metadata CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(metadata)
    )
);

CREATE TABLE IF NOT EXISTS doms.order_change_request_lines (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    order_change_request_id uuid NOT NULL REFERENCES doms.order_change_requests(id) ON DELETE RESTRICT,
    sales_order_id uuid NOT NULL REFERENCES doms.sales_orders(id) ON DELETE RESTRICT,
    sales_order_line_id uuid REFERENCES doms.sales_order_lines(id) ON DELETE RESTRICT,
    sequence_no integer NOT NULL,
    change_action varchar(30) NOT NULL,
    requested_item_id uuid REFERENCES doms.items(id) ON DELETE RESTRICT,
    requested_quantity numeric(24,8),
    requested_unit_price numeric(24,6),
    currency_code char(3) REFERENCES doms.currencies(currency_code),
    change_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
    validation_status varchar(20) NOT NULL DEFAULT 'PENDING',
    result_message_masked text,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, order_change_request_id, sequence_no),
    CONSTRAINT ck_doms_order_change_lines_sequence CHECK (sequence_no > 0),
    CONSTRAINT ck_doms_order_change_lines_action CHECK (change_action IN (
        'ADD_LINE','UPDATE_QUANTITY','UPDATE_PRICE','REPLACE_ITEM','REMOVE_LINE',
        'UPDATE_ADDRESS','UPDATE_CONTACT','UPDATE_DELIVERY','UPDATE_PROMOTION','OTHER'
    )),
    CONSTRAINT ck_doms_order_change_lines_values CHECK (
        (requested_quantity IS NULL OR requested_quantity > 0) AND
        (requested_unit_price IS NULL OR requested_unit_price >= 0)
    ),
    CONSTRAINT ck_doms_order_change_lines_status CHECK (validation_status IN (
        'PENDING','VALID','INVALID','OVERRIDDEN'
    )),
    CONSTRAINT ck_doms_order_change_lines_payload CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(change_payload)
    )
);

CREATE TABLE IF NOT EXISTS doms.order_change_request_events (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    order_change_request_id uuid NOT NULL REFERENCES doms.order_change_requests(id) ON DELETE RESTRICT,
    sales_order_id uuid NOT NULL REFERENCES doms.sales_orders(id) ON DELETE RESTRICT,
    event_type varchar(30) NOT NULL,
    from_status varchar(30),
    to_status varchar(30),
    actor_user_id uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    detail_masked text,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_doms_order_change_events_type CHECK (event_type IN (
        'REQUESTED','VALIDATED','APPROVAL_REQUESTED','APPROVED','REJECTED','APPLY_STARTED',
        'APPLIED','FAILED','CANCELLED','COMMENTED'
    )),
    CONSTRAINT ck_doms_order_change_events_metadata CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(metadata)
    )
);

CREATE TABLE IF NOT EXISTS doms.order_cancellation_requests (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    cancellation_request_no varchar(100) NOT NULL,
    sales_order_id uuid NOT NULL REFERENCES doms.sales_orders(id) ON DELETE RESTRICT,
    request_scope varchar(20) NOT NULL DEFAULT 'ORDER',
    request_status varchar(30) NOT NULL DEFAULT 'REQUESTED',
    idempotency_key varchar(200) NOT NULL,
    requested_by_customer boolean NOT NULL DEFAULT false,
    requested_by uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    requested_at timestamptz NOT NULL DEFAULT now(),
    reason_code_id uuid REFERENCES doms.reason_codes(id) ON DELETE RESTRICT,
    reason_text text,
    approved_by uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    approved_at timestamptz,
    completed_at timestamptz,
    rejected_at timestamptz,
    rejection_reason text,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, cancellation_request_no),
    UNIQUE (tenant_id, idempotency_key),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_doms_order_cancel_scope CHECK (request_scope IN ('ORDER','SELECTED_LINES','REMAINDER')),
    CONSTRAINT ck_doms_order_cancel_status CHECK (request_status IN (
        'REQUESTED','VALIDATING','APPROVAL_PENDING','APPROVED','REJECTED','PROCESSING',
        'PARTIALLY_COMPLETED','COMPLETED','FAILED','CANCELLED'
    )),
    CONSTRAINT ck_doms_order_cancel_approval CHECK (
        request_status NOT IN ('APPROVED','PROCESSING','PARTIALLY_COMPLETED','COMPLETED') OR
        (approved_by IS NOT NULL AND approved_at IS NOT NULL)
    ),
    CONSTRAINT ck_doms_order_cancel_complete CHECK (
        request_status NOT IN ('PARTIALLY_COMPLETED','COMPLETED') OR completed_at IS NOT NULL
    ),
    CONSTRAINT ck_doms_order_cancel_metadata CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(metadata)
    )
);

CREATE TABLE IF NOT EXISTS doms.order_cancellation_request_lines (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    order_cancellation_request_id uuid NOT NULL REFERENCES doms.order_cancellation_requests(id) ON DELETE RESTRICT,
    sales_order_id uuid NOT NULL REFERENCES doms.sales_orders(id) ON DELETE RESTRICT,
    sales_order_line_id uuid NOT NULL REFERENCES doms.sales_order_lines(id) ON DELETE RESTRICT,
    requested_cancel_qty numeric(24,8) NOT NULL,
    approved_cancel_qty numeric(24,8) NOT NULL DEFAULT 0,
    completed_cancel_qty numeric(24,8) NOT NULL DEFAULT 0,
    line_status varchar(20) NOT NULL DEFAULT 'REQUESTED',
    reason_code_id uuid REFERENCES doms.reason_codes(id) ON DELETE RESTRICT,
    reason_text text,
    result_message_masked text,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, order_cancellation_request_id, sales_order_line_id),
    CONSTRAINT ck_doms_order_cancel_lines_qty CHECK (
        requested_cancel_qty > 0 AND approved_cancel_qty >= 0 AND completed_cancel_qty >= 0 AND
        approved_cancel_qty <= requested_cancel_qty AND completed_cancel_qty <= approved_cancel_qty
    ),
    CONSTRAINT ck_doms_order_cancel_lines_status CHECK (line_status IN (
        'REQUESTED','APPROVED','REJECTED','PROCESSING','COMPLETED','FAILED','CANCELLED'
    ))
);

CREATE TABLE IF NOT EXISTS doms.order_cancellation_events (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    order_cancellation_request_id uuid NOT NULL REFERENCES doms.order_cancellation_requests(id) ON DELETE RESTRICT,
    sales_order_id uuid NOT NULL REFERENCES doms.sales_orders(id) ON DELETE RESTRICT,
    event_type varchar(30) NOT NULL,
    from_status varchar(30),
    to_status varchar(30),
    actor_user_id uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    detail_masked text,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_doms_order_cancel_events_type CHECK (event_type IN (
        'REQUESTED','VALIDATED','APPROVAL_REQUESTED','APPROVED','REJECTED','PROCESSING',
        'PARTIALLY_COMPLETED','COMPLETED','FAILED','CANCELLED','COMMENTED'
    )),
    CONSTRAINT ck_doms_order_cancel_events_metadata CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(metadata)
    )
);

CREATE TABLE IF NOT EXISTS doms.order_relations (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    source_order_id uuid NOT NULL REFERENCES doms.sales_orders(id) ON DELETE RESTRICT,
    target_order_id uuid NOT NULL REFERENCES doms.sales_orders(id) ON DELETE RESTRICT,
    relation_type varchar(30) NOT NULL,
    source_line_id uuid REFERENCES doms.sales_order_lines(id) ON DELETE RESTRICT,
    target_line_id uuid REFERENCES doms.sales_order_lines(id) ON DELETE RESTRICT,
    relation_reason text,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_by uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, source_order_id, target_order_id, relation_type, source_line_id, target_line_id),
    CONSTRAINT ck_doms_order_relations_self CHECK (source_order_id <> target_order_id),
    CONSTRAINT ck_doms_order_relations_type CHECK (relation_type IN (
        'REPLACEMENT','EXCHANGE','RETURN_FOR','REORDER_OF','SPLIT_FROM','MERGED_INTO',
        'CHILD_OF','SUBSCRIPTION_RENEWAL','CORRECTION_OF','RELATED'
    )),
    CONSTRAINT ck_doms_order_relations_lines CHECK (
        (source_line_id IS NULL AND target_line_id IS NULL) OR
        (source_line_id IS NOT NULL AND target_line_id IS NOT NULL)
    ),
    CONSTRAINT ck_doms_order_relations_metadata CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(metadata)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_order_relations_scope
    ON doms.order_relations (
        tenant_id, source_order_id, target_order_id, relation_type,
        COALESCE(source_line_id, '00000000-0000-0000-0000-000000000000'::uuid),
        COALESCE(target_line_id, '00000000-0000-0000-0000-000000000000'::uuid)
    );

CREATE TABLE IF NOT EXISTS doms.order_tags (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    tag_code varchar(80) NOT NULL,
    tag_name varchar(150) NOT NULL,
    tag_category varchar(50),
    color_code varchar(20),
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, tag_code)
);

CREATE TABLE IF NOT EXISTS doms.order_tag_assignments (
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    sales_order_id uuid NOT NULL REFERENCES doms.sales_orders(id) ON DELETE RESTRICT,
    order_tag_id uuid NOT NULL REFERENCES doms.order_tags(id) ON DELETE RESTRICT,
    assigned_by uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    assigned_at timestamptz NOT NULL DEFAULT now(),
    removed_by uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    removed_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, sales_order_id, order_tag_id),
    CONSTRAINT ck_doms_order_tag_assignment_dates CHECK (
        removed_at IS NULL OR removed_at >= assigned_at
    )
);

CREATE TABLE IF NOT EXISTS doms.order_notes (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    sales_order_id uuid NOT NULL REFERENCES doms.sales_orders(id) ON DELETE RESTRICT,
    sales_order_line_id uuid REFERENCES doms.sales_order_lines(id) ON DELETE RESTRICT,
    note_type varchar(30) NOT NULL DEFAULT 'INTERNAL',
    visibility varchar(20) NOT NULL DEFAULT 'INTERNAL',
    note_text_encrypted text NOT NULL,
    note_preview_masked varchar(500),
    author_user_id uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    pinned boolean NOT NULL DEFAULT false,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    CONSTRAINT ck_doms_order_notes_type CHECK (note_type IN (
        'INTERNAL','CUSTOMER_REQUEST','DELIVERY','PAYMENT','RISK','CHANGE','CANCELLATION','OTHER'
    )),
    CONSTRAINT ck_doms_order_notes_visibility CHECK (visibility IN (
        'INTERNAL','CUSTOMER_SERVICE','FULFILLMENT','CUSTOMER_VISIBLE','RESTRICTED'
    ))
);

COMMENT ON COLUMN doms.order_notes.note_text_encrypted IS
    'Encrypted note body because operational notes can contain PII. Only a masked preview may be logged or indexed.';

CREATE OR REPLACE FUNCTION doms.order_status_transition_allowed(
    p_axis text,
    p_from_status text,
    p_to_status text
)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
AS $function$
BEGIN
    IF p_from_status IS NULL OR p_from_status = p_to_status THEN
        RETURN true;
    END IF;

    IF p_axis = 'ORDER' THEN
        RETURN CASE p_from_status
            WHEN 'DRAFT' THEN p_to_status = ANY (ARRAY['VALIDATING','CANCELLED']::text[])
            WHEN 'VALIDATING' THEN p_to_status = ANY (ARRAY['DRAFT','VALIDATION_FAILED','SUBMITTED','CANCELLED']::text[])
            WHEN 'VALIDATION_FAILED' THEN p_to_status = ANY (ARRAY['DRAFT','VALIDATING','CANCELLED']::text[])
            WHEN 'SUBMITTED' THEN p_to_status = ANY (ARRAY['CONFIRMED','CHANGE_PENDING','ON_HOLD','CANCELLATION_PENDING','CANCELLED']::text[])
            WHEN 'CONFIRMED' THEN p_to_status = ANY (ARRAY['CHANGE_PENDING','ON_HOLD','PARTIALLY_FULFILLED','FULFILLED','CANCELLATION_PENDING','CANCELLED']::text[])
            WHEN 'CHANGE_PENDING' THEN p_to_status = ANY (ARRAY['CONFIRMED','ON_HOLD','CANCELLATION_PENDING','CANCELLED']::text[])
            WHEN 'ON_HOLD' THEN p_to_status = ANY (ARRAY['SUBMITTED','CONFIRMED','CHANGE_PENDING','CANCELLATION_PENDING','CANCELLED']::text[])
            WHEN 'PARTIALLY_FULFILLED' THEN p_to_status = ANY (ARRAY['FULFILLED','ON_HOLD','CANCELLATION_PENDING','COMPLETED']::text[])
            WHEN 'FULFILLED' THEN p_to_status = ANY (ARRAY['COMPLETED','ON_HOLD']::text[])
            WHEN 'COMPLETED' THEN p_to_status = 'CLOSED'
            WHEN 'CANCELLATION_PENDING' THEN p_to_status = ANY (ARRAY['CONFIRMED','PARTIALLY_FULFILLED','ON_HOLD','CANCELLED']::text[])
            WHEN 'CANCELLED' THEN p_to_status = 'CLOSED'
            ELSE false
        END;
    ELSIF p_axis = 'PAYMENT' THEN
        RETURN CASE p_from_status
            WHEN 'NOT_REQUIRED' THEN p_to_status = 'PENDING'
            WHEN 'PENDING' THEN p_to_status = ANY (ARRAY['NOT_REQUIRED','AUTHORIZED','PARTIALLY_PAID','PAID','VOIDED','FAILED']::text[])
            WHEN 'AUTHORIZED' THEN p_to_status = ANY (ARRAY['PARTIALLY_PAID','PAID','VOIDED','FAILED']::text[])
            WHEN 'PARTIALLY_PAID' THEN p_to_status = ANY (ARRAY['PAID','PARTIALLY_REFUNDED','REFUNDED','VOIDED','FAILED']::text[])
            WHEN 'PAID' THEN p_to_status = ANY (ARRAY['PARTIALLY_REFUNDED','REFUNDED']::text[])
            WHEN 'PARTIALLY_REFUNDED' THEN p_to_status = 'REFUNDED'
            WHEN 'FAILED' THEN p_to_status = ANY (ARRAY['PENDING','VOIDED']::text[])
            ELSE false
        END;
    ELSIF p_axis = 'FULFILLMENT' THEN
        RETURN CASE p_from_status
            WHEN 'UNPLANNED' THEN p_to_status = ANY (ARRAY['PLANNING','PARTIALLY_ALLOCATED','ALLOCATED','CANCELLED']::text[])
            WHEN 'PLANNING' THEN p_to_status = ANY (ARRAY['UNPLANNED','PARTIALLY_ALLOCATED','ALLOCATED','CANCELLED']::text[])
            WHEN 'PARTIALLY_ALLOCATED' THEN p_to_status = ANY (ARRAY['PLANNING','ALLOCATED','RELEASED','CANCELLED']::text[])
            WHEN 'ALLOCATED' THEN p_to_status = ANY (ARRAY['PLANNING','RELEASED','CANCELLED']::text[])
            WHEN 'RELEASED' THEN p_to_status = ANY (ARRAY['PARTIALLY_FULFILLED','FULFILLED','DELIVERY_FAILED','CANCELLED']::text[])
            WHEN 'PARTIALLY_FULFILLED' THEN p_to_status = ANY (ARRAY['FULFILLED','DELIVERY_FAILED','CANCELLED']::text[])
            WHEN 'DELIVERY_FAILED' THEN p_to_status = ANY (ARRAY['RELEASED','PARTIALLY_FULFILLED','FULFILLED','CANCELLED']::text[])
            ELSE false
        END;
    ELSIF p_axis = 'RETURN' THEN
        RETURN CASE p_from_status
            WHEN 'NONE' THEN p_to_status = 'REQUESTED'
            WHEN 'REQUESTED' THEN p_to_status = ANY (ARRAY['PARTIALLY_RETURNED','RETURNED','CLOSED']::text[])
            WHEN 'PARTIALLY_RETURNED' THEN p_to_status = ANY (ARRAY['RETURNED','CLOSED']::text[])
            WHEN 'RETURNED' THEN p_to_status = 'CLOSED'
            ELSE false
        END;
    ELSIF p_axis = 'RISK' THEN
        RETURN CASE p_from_status
            WHEN 'NOT_ASSESSED' THEN p_to_status = ANY (ARRAY['PENDING','PASSED','REVIEW','BLOCKED','REJECTED']::text[])
            WHEN 'PENDING' THEN p_to_status = ANY (ARRAY['PASSED','REVIEW','BLOCKED','REJECTED']::text[])
            WHEN 'PASSED' THEN p_to_status = ANY (ARRAY['PENDING','REVIEW','BLOCKED']::text[])
            WHEN 'REVIEW' THEN p_to_status = ANY (ARRAY['PENDING','PASSED','BLOCKED','REJECTED']::text[])
            WHEN 'BLOCKED' THEN p_to_status = ANY (ARRAY['REVIEW','PASSED','REJECTED']::text[])
            WHEN 'REJECTED' THEN p_to_status = 'REVIEW'
            ELSE false
        END;
    END IF;
    RETURN false;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.order_line_status_transition_allowed(
    p_axis text,
    p_from_status text,
    p_to_status text
)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
AS $function$
BEGIN
    IF p_from_status IS NULL OR p_from_status = p_to_status THEN
        RETURN true;
    END IF;
    IF p_axis = 'LINE' THEN
        RETURN CASE p_from_status
            WHEN 'OPEN' THEN p_to_status = ANY (ARRAY['ON_HOLD','CHANGE_PENDING','CANCELLATION_PENDING','PARTIALLY_CANCELLED','CANCELLED','CLOSED']::text[])
            WHEN 'ON_HOLD' THEN p_to_status = ANY (ARRAY['OPEN','CHANGE_PENDING','CANCELLATION_PENDING','CANCELLED']::text[])
            WHEN 'CHANGE_PENDING' THEN p_to_status = ANY (ARRAY['OPEN','ON_HOLD','CANCELLATION_PENDING','PARTIALLY_CANCELLED','CANCELLED']::text[])
            WHEN 'CANCELLATION_PENDING' THEN p_to_status = ANY (ARRAY['OPEN','PARTIALLY_CANCELLED','CANCELLED']::text[])
            WHEN 'PARTIALLY_CANCELLED' THEN p_to_status = ANY (ARRAY['CANCELLATION_PENDING','CANCELLED','CLOSED']::text[])
            WHEN 'CANCELLED' THEN p_to_status = 'CLOSED'
            ELSE false
        END;
    ELSIF p_axis = 'FULFILLMENT' THEN
        RETURN CASE p_from_status
            WHEN 'UNPLANNED' THEN p_to_status = ANY (ARRAY['PARTIALLY_ALLOCATED','ALLOCATED','CANCELLED']::text[])
            WHEN 'PARTIALLY_ALLOCATED' THEN p_to_status = ANY (ARRAY['ALLOCATED','RELEASED','CANCELLED']::text[])
            WHEN 'ALLOCATED' THEN p_to_status = ANY (ARRAY['RELEASED','CANCELLED']::text[])
            WHEN 'RELEASED' THEN p_to_status = ANY (ARRAY['PICKED','PACKED','SHIPPED','CANCELLED']::text[])
            WHEN 'PICKED' THEN p_to_status = ANY (ARRAY['PACKED','SHIPPED','CANCELLED']::text[])
            WHEN 'PACKED' THEN p_to_status = ANY (ARRAY['SHIPPED','CANCELLED']::text[])
            WHEN 'SHIPPED' THEN p_to_status = 'DELIVERED'
            ELSE false
        END;
    ELSIF p_axis = 'RETURN' THEN
        RETURN CASE p_from_status
            WHEN 'NONE' THEN p_to_status = 'REQUESTED'
            WHEN 'REQUESTED' THEN p_to_status = ANY (ARRAY['PARTIALLY_RETURNED','RETURNED','CLOSED']::text[])
            WHEN 'PARTIALLY_RETURNED' THEN p_to_status = ANY (ARRAY['RETURNED','CLOSED']::text[])
            WHEN 'RETURNED' THEN p_to_status = 'CLOSED'
            ELSE false
        END;
    END IF;
    RETURN false;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.prevent_order_append_only_change()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    RAISE EXCEPTION '% is append-only; corrections require a new event or version', TG_TABLE_NAME
        USING ERRCODE = '55000';
END;
$function$;

CREATE OR REPLACE FUNCTION doms.validate_sales_order_scope()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM doms.sales_channels channel_row
        WHERE channel_row.id = NEW.sales_channel_id
          AND channel_row.tenant_id = NEW.tenant_id
    ) THEN
        RAISE EXCEPTION 'Sales order channel must belong to the active tenant'
            USING ERRCODE = '23514';
    END IF;
    IF NEW.channel_account_id IS NOT NULL AND NOT EXISTS (
        SELECT 1
        FROM doms.channel_accounts account_row
        WHERE account_row.id = NEW.channel_account_id
          AND account_row.tenant_id = NEW.tenant_id
          AND account_row.sales_channel_id = NEW.sales_channel_id
    ) THEN
        RAISE EXCEPTION 'Sales order channel account does not belong to the selected channel'
            USING ERRCODE = '23514';
    END IF;
    IF NEW.channel_store_id IS NOT NULL AND NOT EXISTS (
        SELECT 1
        FROM doms.channel_stores store_row
        WHERE store_row.id = NEW.channel_store_id
          AND store_row.tenant_id = NEW.tenant_id
          AND store_row.channel_account_id = NEW.channel_account_id
    ) THEN
        RAISE EXCEPTION 'Sales order channel store does not belong to the selected account'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.validate_sales_order_line_scope()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    order_row doms.sales_orders%ROWTYPE;
BEGIN
    SELECT * INTO order_row FROM doms.sales_orders WHERE id = NEW.sales_order_id;
    IF NOT FOUND OR order_row.tenant_id IS DISTINCT FROM NEW.tenant_id THEN
        RAISE EXCEPTION 'Order line must belong to an order in the same tenant'
            USING ERRCODE = '23514';
    END IF;
    IF order_row.currency_code IS DISTINCT FROM NEW.currency_code THEN
        RAISE EXCEPTION 'Order line currency must match the order currency'
            USING ERRCODE = '23514';
    END IF;
    IF TG_OP = 'UPDATE' AND (
        OLD.tenant_id IS DISTINCT FROM NEW.tenant_id OR
        OLD.sales_order_id IS DISTINCT FROM NEW.sales_order_id OR
        OLD.line_no IS DISTINCT FROM NEW.line_no OR
        OLD.external_line_id IS DISTINCT FROM NEW.external_line_id
    ) THEN
        RAISE EXCEPTION 'Order line tenant, order, line number, and external identity are immutable'
            USING ERRCODE = '55000';
    END IF;
    IF TG_OP = 'UPDATE'
       AND order_row.order_status NOT IN ('DRAFT','VALIDATING','VALIDATION_FAILED','CHANGE_PENDING')
       AND (
           OLD.item_id IS DISTINCT FROM NEW.item_id OR
           OLD.item_packaging_id IS DISTINCT FROM NEW.item_packaging_id OR
           OLD.price_book_id IS DISTINCT FROM NEW.price_book_id OR
           OLD.item_code_snapshot IS DISTINCT FROM NEW.item_code_snapshot OR
           OLD.item_name_snapshot IS DISTINCT FROM NEW.item_name_snapshot OR
           OLD.ordered_qty IS DISTINCT FROM NEW.ordered_qty OR
           OLD.uom_code IS DISTINCT FROM NEW.uom_code OR
           OLD.currency_code IS DISTINCT FROM NEW.currency_code OR
           OLD.unit_list_price IS DISTINCT FROM NEW.unit_list_price OR
           OLD.unit_selling_price IS DISTINCT FROM NEW.unit_selling_price OR
           OLD.gross_amount IS DISTINCT FROM NEW.gross_amount OR
           OLD.discount_amount IS DISTINCT FROM NEW.discount_amount OR
           OLD.charge_amount IS DISTINCT FROM NEW.charge_amount OR
           OLD.tax_amount IS DISTINCT FROM NEW.tax_amount OR
           OLD.net_amount IS DISTINCT FROM NEW.net_amount OR
           OLD.deleted_at IS DISTINCT FROM NEW.deleted_at
       ) THEN
        RAISE EXCEPTION 'Committed order line commercial fields require an approved change version'
            USING ERRCODE = '55000';
    END IF;
    IF TG_OP = 'UPDATE' THEN
        IF NOT doms.order_line_status_transition_allowed('LINE', OLD.line_status, NEW.line_status) THEN
            RAISE EXCEPTION 'Invalid order-line status transition: % -> %', OLD.line_status, NEW.line_status
                USING ERRCODE = '23514';
        END IF;
        IF NOT doms.order_line_status_transition_allowed('FULFILLMENT', OLD.fulfillment_status, NEW.fulfillment_status) THEN
            RAISE EXCEPTION 'Invalid order-line fulfillment transition: % -> %', OLD.fulfillment_status, NEW.fulfillment_status
                USING ERRCODE = '23514';
        END IF;
        IF NOT doms.order_line_status_transition_allowed('RETURN', OLD.return_status, NEW.return_status) THEN
            RAISE EXCEPTION 'Invalid order-line return transition: % -> %', OLD.return_status, NEW.return_status
                USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.validate_order_monetary_component()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    order_row doms.sales_orders%ROWTYPE;
BEGIN
    SELECT * INTO order_row FROM doms.sales_orders WHERE id = NEW.sales_order_id;
    IF NOT FOUND OR order_row.tenant_id IS DISTINCT FROM NEW.tenant_id THEN
        RAISE EXCEPTION '% must belong to an order in the same tenant', TG_TABLE_NAME
            USING ERRCODE = '23514';
    END IF;
    IF order_row.currency_code IS DISTINCT FROM NEW.currency_code THEN
        RAISE EXCEPTION '% currency must match the order currency', TG_TABLE_NAME
            USING ERRCODE = '23514';
    END IF;
    IF NEW.sales_order_line_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM doms.sales_order_lines line_row
        WHERE line_row.id = NEW.sales_order_line_id
          AND line_row.sales_order_id = NEW.sales_order_id
          AND line_row.tenant_id = NEW.tenant_id
    ) THEN
        RAISE EXCEPTION '% line must belong to the same order and tenant', TG_TABLE_NAME
            USING ERRCODE = '23514';
    END IF;
    IF TG_OP = 'UPDATE' AND (
        OLD.tenant_id IS DISTINCT FROM NEW.tenant_id OR
        OLD.sales_order_id IS DISTINCT FROM NEW.sales_order_id OR
        OLD.sales_order_line_id IS DISTINCT FROM NEW.sales_order_line_id
    ) THEN
        RAISE EXCEPTION '% order scope is immutable', TG_TABLE_NAME
            USING ERRCODE = '55000';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.guard_order_commercial_component()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    target_order_id uuid;
    target_status text;
BEGIN
    target_order_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.sales_order_id ELSE NEW.sales_order_id END;
    SELECT order_status INTO target_status FROM doms.sales_orders WHERE id = target_order_id;
    IF target_status IS NULL THEN
        RAISE EXCEPTION 'Order for % is missing', TG_TABLE_NAME USING ERRCODE = '23503';
    END IF;
    IF target_status NOT IN ('DRAFT','VALIDATING','VALIDATION_FAILED','CHANGE_PENDING') THEN
        RAISE EXCEPTION '% cannot change outside a draft or approved change window', TG_TABLE_NAME
            USING ERRCODE = '55000';
    END IF;
    IF TG_OP = 'UPDATE' AND OLD.sales_order_id IS DISTINCT FROM NEW.sales_order_id THEN
        RAISE EXCEPTION '% cannot be moved between orders', TG_TABLE_NAME USING ERRCODE = '55000';
    END IF;
    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.validate_sales_order_totals_scope()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    order_row doms.sales_orders%ROWTYPE;
BEGIN
    SELECT * INTO order_row FROM doms.sales_orders WHERE id = NEW.sales_order_id;
    IF NOT FOUND OR order_row.tenant_id IS DISTINCT FROM NEW.tenant_id THEN
        RAISE EXCEPTION 'Order totals must belong to an order in the same tenant'
            USING ERRCODE = '23514';
    END IF;
    IF order_row.currency_code IS DISTINCT FROM NEW.currency_code THEN
        RAISE EXCEPTION 'Order totals currency must match the order currency'
            USING ERRCODE = '23514';
    END IF;
    IF TG_OP = 'UPDATE' AND (
        OLD.tenant_id IS DISTINCT FROM NEW.tenant_id OR
        OLD.sales_order_id IS DISTINCT FROM NEW.sales_order_id OR
        OLD.currency_code IS DISTINCT FROM NEW.currency_code
    ) THEN
        RAISE EXCEPTION 'Order totals tenant, order, and currency are immutable'
            USING ERRCODE = '55000';
    END IF;
    IF TG_OP = 'UPDATE'
       AND order_row.order_status NOT IN ('DRAFT','VALIDATING','VALIDATION_FAILED','CHANGE_PENDING')
       AND (
           OLD.line_gross_amount IS DISTINCT FROM NEW.line_gross_amount OR
           OLD.line_discount_amount IS DISTINCT FROM NEW.line_discount_amount OR
           OLD.header_discount_amount IS DISTINCT FROM NEW.header_discount_amount OR
           OLD.charge_amount IS DISTINCT FROM NEW.charge_amount OR
           OLD.tax_amount IS DISTINCT FROM NEW.tax_amount OR
           OLD.rounding_amount IS DISTINCT FROM NEW.rounding_amount OR
           OLD.grand_total_amount IS DISTINCT FROM NEW.grand_total_amount
       ) THEN
        RAISE EXCEPTION 'Committed commercial totals require an approved change version'
            USING ERRCODE = '55000';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.assert_sales_order_totals(p_sales_order_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, doms, pg_temp
AS $function$
DECLARE
    order_row doms.sales_orders%ROWTYPE;
    totals_row doms.sales_order_totals%ROWTYPE;
    calc_line_gross numeric(24,6);
    calc_line_discount numeric(24,6);
    calc_header_discount numeric(24,6);
    calc_charge numeric(24,6);
    calc_tax numeric(24,6);
BEGIN
    SELECT * INTO order_row FROM doms.sales_orders WHERE id = p_sales_order_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Sales order is unavailable' USING ERRCODE = '23503';
    END IF;
    SELECT * INTO totals_row
    FROM doms.sales_order_totals
    WHERE sales_order_id = p_sales_order_id AND tenant_id = order_row.tenant_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Sales order % has no header totals row', p_sales_order_id
            USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM doms.sales_order_lines
        WHERE sales_order_id = p_sales_order_id AND deleted_at IS NULL
    ) THEN
        RAISE EXCEPTION 'Sales order % must contain at least one active line', p_sales_order_id
            USING ERRCODE = '23514';
    END IF;

    SELECT COALESCE(sum(gross_amount),0), COALESCE(sum(discount_amount),0)
      INTO calc_line_gross, calc_line_discount
      FROM doms.sales_order_lines
     WHERE sales_order_id = p_sales_order_id AND deleted_at IS NULL;
    SELECT COALESCE(sum(amount),0) INTO calc_header_discount
      FROM doms.order_discount_adjustments
     WHERE sales_order_id = p_sales_order_id
       AND sales_order_line_id IS NULL AND status = 'APPLIED';
    SELECT COALESCE(sum(amount),0) INTO calc_charge
      FROM doms.order_charges
     WHERE sales_order_id = p_sales_order_id AND status = 'APPLIED';
    SELECT COALESCE(sum(tax_amount),0) INTO calc_tax
      FROM doms.order_taxes
     WHERE sales_order_id = p_sales_order_id AND status = 'APPLIED';

    IF abs(totals_row.line_gross_amount - calc_line_gross) > 0.000001
       OR abs(totals_row.line_discount_amount - calc_line_discount) > 0.000001
       OR abs(totals_row.header_discount_amount - calc_header_discount) > 0.000001
       OR abs(totals_row.charge_amount - calc_charge) > 0.000001
       OR abs(totals_row.tax_amount - calc_tax) > 0.000001 THEN
        RAISE EXCEPTION 'Sales order % header totals do not reconcile to active detail', p_sales_order_id
            USING ERRCODE = '23514';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM doms.sales_order_lines line_row
        WHERE line_row.sales_order_id = p_sales_order_id
          AND line_row.deleted_at IS NULL
          AND (
              abs(line_row.discount_amount - COALESCE((
                  SELECT sum(adjustment.amount)
                  FROM doms.order_discount_adjustments adjustment
                  WHERE adjustment.sales_order_id = p_sales_order_id
                    AND adjustment.sales_order_line_id = line_row.id
                    AND adjustment.status = 'APPLIED'
              ),0)) > 0.000001
              OR abs(line_row.charge_amount - COALESCE((
                  SELECT sum(charge.amount)
                  FROM doms.order_charges charge
                  WHERE charge.sales_order_id = p_sales_order_id
                    AND charge.sales_order_line_id = line_row.id
                    AND charge.status = 'APPLIED'
              ),0)) > 0.000001
              OR abs(line_row.tax_amount - COALESCE((
                  SELECT sum(tax.tax_amount)
                  FROM doms.order_taxes tax
                  WHERE tax.sales_order_id = p_sales_order_id
                    AND tax.sales_order_line_id = line_row.id
                    AND tax.status = 'APPLIED'
              ),0)) > 0.000001
          )
    ) THEN
        RAISE EXCEPTION 'Sales order % line amounts do not reconcile to adjustments, charges, and taxes', p_sales_order_id
            USING ERRCODE = '23514';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM doms.order_promotions promotion_row
        WHERE promotion_row.sales_order_id = p_sales_order_id
          AND promotion_row.status = 'APPLIED'
          AND COALESCE((
              SELECT sum(allocation.allocated_discount_amount)
              FROM doms.order_promotion_lines allocation
              WHERE allocation.order_promotion_id = promotion_row.id
          ),0) > promotion_row.applied_discount_amount + 0.000001
    ) THEN
        RAISE EXCEPTION 'Sales order % promotion allocations exceed the applied reward', p_sales_order_id
            USING ERRCODE = '23514';
    END IF;
END;
$function$;

REVOKE ALL ON FUNCTION doms.assert_sales_order_totals(uuid) FROM PUBLIC;

CREATE OR REPLACE FUNCTION doms.guard_order_version_child()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    target_version_id uuid;
    target_order_id uuid;
    target_tenant_id uuid;
    target_party_id uuid;
    version_row doms.sales_order_versions%ROWTYPE;
BEGIN
    IF TG_OP = 'DELETE' THEN
        target_version_id := OLD.sales_order_version_id;
        target_order_id := OLD.sales_order_id;
        target_tenant_id := OLD.tenant_id;
        IF TG_TABLE_NAME IN ('order_address_snapshots','order_contact_snapshots') THEN
            target_party_id := OLD.order_party_id;
        END IF;
    ELSE
        target_version_id := NEW.sales_order_version_id;
        target_order_id := NEW.sales_order_id;
        target_tenant_id := NEW.tenant_id;
        IF TG_TABLE_NAME IN ('order_address_snapshots','order_contact_snapshots') THEN
            target_party_id := NEW.order_party_id;
        END IF;
    END IF;

    SELECT * INTO version_row FROM doms.sales_order_versions WHERE id = target_version_id;
    IF NOT FOUND OR version_row.sales_order_id IS DISTINCT FROM target_order_id
       OR version_row.tenant_id IS DISTINCT FROM target_tenant_id THEN
        RAISE EXCEPTION '% must belong to the same order version and tenant', TG_TABLE_NAME
            USING ERRCODE = '23514';
    END IF;
    IF version_row.version_status <> 'DRAFT' THEN
        RAISE EXCEPTION 'Sealed order-version children are immutable: %', TG_TABLE_NAME
            USING ERRCODE = '55000';
    END IF;
    IF TG_OP = 'UPDATE' AND (
        OLD.tenant_id IS DISTINCT FROM NEW.tenant_id OR
        OLD.sales_order_id IS DISTINCT FROM NEW.sales_order_id OR
        OLD.sales_order_version_id IS DISTINCT FROM NEW.sales_order_version_id
    ) THEN
        RAISE EXCEPTION '% cannot be moved to another version, order, or tenant', TG_TABLE_NAME
            USING ERRCODE = '55000';
    END IF;
    IF TG_TABLE_NAME IN ('order_address_snapshots','order_contact_snapshots')
       AND NOT EXISTS (
           SELECT 1 FROM doms.order_parties party_row
           WHERE party_row.id = target_party_id
             AND party_row.tenant_id = target_tenant_id
             AND party_row.sales_order_id = target_order_id
             AND party_row.sales_order_version_id = target_version_id
       ) THEN
        RAISE EXCEPTION '% party must belong to the same order version', TG_TABLE_NAME
            USING ERRCODE = '23514';
    END IF;
    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.validate_sales_order_version_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    order_row doms.sales_orders%ROWTYPE;
    totals_row doms.sales_order_totals%ROWTYPE;
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'Order versions are immutable and cannot be deleted'
            USING ERRCODE = '55000';
    END IF;
    IF TG_OP = 'UPDATE' AND (
        OLD.tenant_id IS DISTINCT FROM NEW.tenant_id OR
        OLD.sales_order_id IS DISTINCT FROM NEW.sales_order_id OR
        OLD.version_no IS DISTINCT FROM NEW.version_no
    ) THEN
        RAISE EXCEPTION 'Order version tenant, order, and version number are immutable'
            USING ERRCODE = '55000';
    END IF;
    IF TG_OP = 'UPDATE' AND OLD.version_status IN ('SEALED','SUPERSEDED') THEN
        IF NOT (OLD.version_status = 'SEALED' AND NEW.version_status = 'SUPERSEDED')
           OR (to_jsonb(OLD) - 'version_status') IS DISTINCT FROM
              (to_jsonb(NEW) - 'version_status') THEN
            RAISE EXCEPTION 'Sealed order version % is immutable', OLD.id
                USING ERRCODE = '55000';
        END IF;
        RETURN NEW;
    END IF;
    IF NEW.version_status = 'SEALED'
       AND (TG_OP = 'INSERT' OR OLD.version_status IS DISTINCT FROM NEW.version_status) THEN
        SELECT * INTO order_row
        FROM doms.sales_orders
        WHERE id = NEW.sales_order_id AND tenant_id = NEW.tenant_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Order version order is unavailable' USING ERRCODE = '23503';
        END IF;
        SELECT * INTO totals_row
        FROM doms.sales_order_totals
        WHERE sales_order_id = NEW.sales_order_id AND tenant_id = NEW.tenant_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Order version cannot be sealed without header totals'
                USING ERRCODE = '23514';
        END IF;
        PERFORM doms.assert_sales_order_totals(NEW.sales_order_id);
        IF NEW.currency_code IS DISTINCT FROM order_row.currency_code
           OR NEW.order_status IS DISTINCT FROM order_row.order_status
           OR NEW.payment_status IS DISTINCT FROM order_row.payment_status
           OR NEW.fulfillment_status IS DISTINCT FROM order_row.fulfillment_status
           OR NEW.return_status IS DISTINCT FROM order_row.return_status
           OR NEW.risk_status IS DISTINCT FROM order_row.risk_status
           OR abs(NEW.line_gross_amount - totals_row.line_gross_amount) > 0.000001
           OR abs(NEW.line_discount_amount - totals_row.line_discount_amount) > 0.000001
           OR abs(NEW.header_discount_amount - totals_row.header_discount_amount) > 0.000001
           OR abs(NEW.charge_amount - totals_row.charge_amount) > 0.000001
           OR abs(NEW.tax_amount - totals_row.tax_amount) > 0.000001
           OR abs(NEW.rounding_amount - totals_row.rounding_amount) > 0.000001
           OR abs(NEW.grand_total_amount - totals_row.grand_total_amount) > 0.000001 THEN
            RAISE EXCEPTION 'Order version header snapshot does not match the current order and totals'
                USING ERRCODE = '23514';
        END IF;
        IF EXISTS (
            SELECT 1
            FROM doms.sales_order_lines current_line
            LEFT JOIN doms.sales_order_version_lines snapshot_line
              ON snapshot_line.sales_order_version_id = NEW.id
             AND snapshot_line.sales_order_line_id = current_line.id
            WHERE current_line.sales_order_id = NEW.sales_order_id
              AND current_line.deleted_at IS NULL
              AND (
                  snapshot_line.id IS NULL OR
                  snapshot_line.tenant_id IS DISTINCT FROM current_line.tenant_id OR
                  snapshot_line.sales_order_id IS DISTINCT FROM current_line.sales_order_id OR
                  snapshot_line.line_no IS DISTINCT FROM current_line.line_no OR
                  snapshot_line.item_id IS DISTINCT FROM current_line.item_id OR
                  snapshot_line.item_code_snapshot IS DISTINCT FROM current_line.item_code_snapshot OR
                  snapshot_line.item_name_snapshot IS DISTINCT FROM current_line.item_name_snapshot OR
                  snapshot_line.ordered_qty IS DISTINCT FROM current_line.ordered_qty OR
                  snapshot_line.cancelled_qty IS DISTINCT FROM current_line.cancelled_qty OR
                  snapshot_line.uom_code IS DISTINCT FROM current_line.uom_code OR
                  snapshot_line.currency_code IS DISTINCT FROM current_line.currency_code OR
                  abs(snapshot_line.unit_selling_price - current_line.unit_selling_price) > 0.000001 OR
                  abs(snapshot_line.gross_amount - current_line.gross_amount) > 0.000001 OR
                  abs(snapshot_line.discount_amount - current_line.discount_amount) > 0.000001 OR
                  abs(snapshot_line.charge_amount - current_line.charge_amount) > 0.000001 OR
                  abs(snapshot_line.tax_amount - current_line.tax_amount) > 0.000001 OR
                  abs(snapshot_line.net_amount - current_line.net_amount) > 0.000001
              )
        ) OR EXISTS (
            SELECT 1
            FROM doms.sales_order_version_lines snapshot_line
            LEFT JOIN doms.sales_order_lines current_line
              ON current_line.id = snapshot_line.sales_order_line_id
             AND current_line.sales_order_id = NEW.sales_order_id
             AND current_line.deleted_at IS NULL
            WHERE snapshot_line.sales_order_version_id = NEW.id
              AND current_line.id IS NULL
        ) THEN
            RAISE EXCEPTION 'Order version lines are incomplete or differ from current order lines'
                USING ERRCODE = '23514';
        END IF;
        IF NOT EXISTS (
            SELECT 1 FROM doms.order_parties
            WHERE sales_order_version_id = NEW.id AND party_role = 'CUSTOMER'
        ) OR NOT EXISTS (
            SELECT 1 FROM doms.order_parties
            WHERE sales_order_version_id = NEW.id AND party_role = 'BILL_TO'
        ) THEN
            RAISE EXCEPTION 'A sealed order version requires CUSTOMER and BILL_TO party snapshots'
                USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.validate_sales_order_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    version_row doms.sales_order_versions%ROWTYPE;
    totals_row doms.sales_order_totals%ROWTYPE;
    latest_validation_status text;
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF OLD.tenant_id IS DISTINCT FROM NEW.tenant_id
           OR OLD.order_no IS DISTINCT FROM NEW.order_no
           OR OLD.sales_channel_id IS DISTINCT FROM NEW.sales_channel_id
           OR OLD.channel_account_id IS DISTINCT FROM NEW.channel_account_id
           OR OLD.channel_store_id IS DISTINCT FROM NEW.channel_store_id
           OR OLD.source_system_id IS DISTINCT FROM NEW.source_system_id
           OR OLD.external_order_id IS DISTINCT FROM NEW.external_order_id
           OR OLD.idempotency_key IS DISTINCT FROM NEW.idempotency_key THEN
            RAISE EXCEPTION 'Order number, tenant, channel external identity, and idempotency key are immutable'
                USING ERRCODE = '55000';
        END IF;
        IF OLD.order_status NOT IN ('DRAFT','VALIDATING','VALIDATION_FAILED','CHANGE_PENDING')
           AND NEW.order_status <> 'CHANGE_PENDING'
           AND (
               OLD.customer_id IS DISTINCT FROM NEW.customer_id OR
               OLD.order_type_id IS DISTINCT FROM NEW.order_type_id OR
               OLD.selling_organization_id IS DISTINCT FROM NEW.selling_organization_id OR
               OLD.price_book_id IS DISTINCT FROM NEW.price_book_id OR
               OLD.currency_code IS DISTINCT FROM NEW.currency_code OR
               OLD.grand_total_amount IS DISTINCT FROM NEW.grand_total_amount
           ) THEN
            RAISE EXCEPTION 'Committed order commercial header requires an approved change version'
                USING ERRCODE = '55000';
        END IF;
        IF NOT doms.order_status_transition_allowed('ORDER', OLD.order_status, NEW.order_status) THEN
            RAISE EXCEPTION 'Invalid order status transition: % -> %', OLD.order_status, NEW.order_status
                USING ERRCODE = '23514';
        END IF;
        IF NOT doms.order_status_transition_allowed('PAYMENT', OLD.payment_status, NEW.payment_status) THEN
            RAISE EXCEPTION 'Invalid payment status transition: % -> %', OLD.payment_status, NEW.payment_status
                USING ERRCODE = '23514';
        END IF;
        IF NOT doms.order_status_transition_allowed('FULFILLMENT', OLD.fulfillment_status, NEW.fulfillment_status) THEN
            RAISE EXCEPTION 'Invalid fulfillment status transition: % -> %', OLD.fulfillment_status, NEW.fulfillment_status
                USING ERRCODE = '23514';
        END IF;
        IF NOT doms.order_status_transition_allowed('RETURN', OLD.return_status, NEW.return_status) THEN
            RAISE EXCEPTION 'Invalid return status transition: % -> %', OLD.return_status, NEW.return_status
                USING ERRCODE = '23514';
        END IF;
        IF NOT doms.order_status_transition_allowed('RISK', OLD.risk_status, NEW.risk_status) THEN
            RAISE EXCEPTION 'Invalid risk status transition: % -> %', OLD.risk_status, NEW.risk_status
                USING ERRCODE = '23514';
        END IF;
    END IF;

    IF NEW.current_version_id IS NOT NULL THEN
        SELECT * INTO version_row
        FROM doms.sales_order_versions
        WHERE id = NEW.current_version_id;
        IF NOT FOUND OR version_row.tenant_id IS DISTINCT FROM NEW.tenant_id
           OR version_row.sales_order_id IS DISTINCT FROM NEW.id
           OR version_row.version_no IS DISTINCT FROM NEW.current_version_no
           OR version_row.version_status <> 'SEALED' THEN
            RAISE EXCEPTION 'Current order version must be a sealed version of the same order and number'
                USING ERRCODE = '23514';
        END IF;
    END IF;

    IF NEW.order_status NOT IN ('DRAFT','VALIDATING','VALIDATION_FAILED') THEN
        IF NEW.ordered_at IS NULL OR NEW.submitted_at IS NULL OR NEW.current_version_id IS NULL THEN
            RAISE EXCEPTION 'Submitted orders require ordered_at, submitted_at, and a sealed current version'
                USING ERRCODE = '23514';
        END IF;
        SELECT * INTO totals_row
        FROM doms.sales_order_totals
        WHERE sales_order_id = NEW.id AND tenant_id = NEW.tenant_id;
        IF NOT FOUND OR totals_row.currency_code IS DISTINCT FROM NEW.currency_code
           OR abs(totals_row.grand_total_amount - NEW.grand_total_amount) > 0.000001
           OR abs(totals_row.captured_amount - NEW.paid_amount) > 0.000001
           OR abs(totals_row.refunded_amount - NEW.refunded_amount) > 0.000001 THEN
            RAISE EXCEPTION 'Submitted order header must match its reconciled totals projection'
                USING ERRCODE = '23514';
        END IF;
        PERFORM doms.assert_sales_order_totals(NEW.id);
    END IF;

    IF TG_OP = 'UPDATE' AND NEW.order_status = 'SUBMITTED'
       AND OLD.order_status IS DISTINCT FROM NEW.order_status THEN
        SELECT validation_status INTO latest_validation_status
        FROM doms.order_validation_runs
        WHERE sales_order_id = NEW.id AND validation_scope = 'FULL'
        ORDER BY run_no DESC
        LIMIT 1;
        IF latest_validation_status IS NULL
           OR latest_validation_status NOT IN ('PASSED','PASSED_WITH_WARNINGS') THEN
            RAISE EXCEPTION 'Submitting an order requires the latest FULL validation run to pass'
                USING ERRCODE = '23514';
        END IF;
        IF EXISTS (
            SELECT 1 FROM doms.order_holds
            WHERE sales_order_id = NEW.id
              AND hold_status IN ('ACTIVE','RELEASE_PENDING')
              AND blocks_submission
        ) THEN
            RAISE EXCEPTION 'Active order hold blocks submission' USING ERRCODE = '23514';
        END IF;
    END IF;
    IF NEW.order_status IN ('CONFIRMED','PARTIALLY_FULFILLED','FULFILLED','COMPLETED') THEN
        IF NEW.confirmed_at IS NULL OR NEW.risk_status IN ('BLOCKED','REJECTED') THEN
            RAISE EXCEPTION 'Confirmed processing requires confirmed_at and a non-blocked risk decision'
                USING ERRCODE = '23514';
        END IF;
        IF EXISTS (
            SELECT 1 FROM doms.order_holds
            WHERE sales_order_id = NEW.id
              AND hold_status IN ('ACTIVE','RELEASE_PENDING')
              AND blocks_confirmation
        ) THEN
            RAISE EXCEPTION 'Active order hold blocks confirmation' USING ERRCODE = '23514';
        END IF;
    END IF;
    IF NEW.order_status = 'COMPLETED' AND NEW.completed_at IS NULL THEN
        RAISE EXCEPTION 'Completed order requires completed_at' USING ERRCODE = '23514';
    END IF;
    IF NEW.order_status = 'CANCELLED' AND NEW.cancelled_at IS NULL THEN
        RAISE EXCEPTION 'Cancelled order requires cancelled_at' USING ERRCODE = '23514';
    END IF;
    IF NEW.payment_status = 'REFUNDED'
       AND (NEW.paid_amount <= 0 OR abs(NEW.paid_amount - NEW.refunded_amount) > 0.000001) THEN
        RAISE EXCEPTION 'REFUNDED status requires the captured amount to be fully refunded'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.record_sales_order_status_events()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    actor_id uuid;
BEGIN
    actor_id := COALESCE(NEW.updated_by, NEW.created_by);
    IF TG_OP = 'INSERT' OR OLD.order_status IS DISTINCT FROM NEW.order_status THEN
        INSERT INTO doms.sales_order_status_events (
            tenant_id, sales_order_id, status_axis, from_status, to_status,
            reason_code_id, reason_text, changed_by
        ) VALUES (
            NEW.tenant_id, NEW.id, 'ORDER',
            CASE WHEN TG_OP = 'INSERT' THEN NULL ELSE OLD.order_status END,
            NEW.order_status, NEW.status_reason_code_id, NEW.status_reason, actor_id
        );
    END IF;
    IF TG_OP = 'INSERT' OR OLD.payment_status IS DISTINCT FROM NEW.payment_status THEN
        INSERT INTO doms.sales_order_status_events (
            tenant_id, sales_order_id, status_axis, from_status, to_status, changed_by
        ) VALUES (
            NEW.tenant_id, NEW.id, 'PAYMENT',
            CASE WHEN TG_OP = 'INSERT' THEN NULL ELSE OLD.payment_status END,
            NEW.payment_status, actor_id
        );
    END IF;
    IF TG_OP = 'INSERT' OR OLD.fulfillment_status IS DISTINCT FROM NEW.fulfillment_status THEN
        INSERT INTO doms.sales_order_status_events (
            tenant_id, sales_order_id, status_axis, from_status, to_status, changed_by
        ) VALUES (
            NEW.tenant_id, NEW.id, 'FULFILLMENT',
            CASE WHEN TG_OP = 'INSERT' THEN NULL ELSE OLD.fulfillment_status END,
            NEW.fulfillment_status, actor_id
        );
    END IF;
    IF TG_OP = 'INSERT' OR OLD.return_status IS DISTINCT FROM NEW.return_status THEN
        INSERT INTO doms.sales_order_status_events (
            tenant_id, sales_order_id, status_axis, from_status, to_status, changed_by
        ) VALUES (
            NEW.tenant_id, NEW.id, 'RETURN',
            CASE WHEN TG_OP = 'INSERT' THEN NULL ELSE OLD.return_status END,
            NEW.return_status, actor_id
        );
    END IF;
    IF TG_OP = 'INSERT' OR OLD.risk_status IS DISTINCT FROM NEW.risk_status THEN
        INSERT INTO doms.sales_order_status_events (
            tenant_id, sales_order_id, status_axis, from_status, to_status, changed_by
        ) VALUES (
            NEW.tenant_id, NEW.id, 'RISK',
            CASE WHEN TG_OP = 'INSERT' THEN NULL ELSE OLD.risk_status END,
            NEW.risk_status, actor_id
        );
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.record_sales_order_line_status_events()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    actor_id uuid;
BEGIN
    actor_id := COALESCE(NEW.updated_by, NEW.created_by);
    IF TG_OP = 'INSERT' OR OLD.line_status IS DISTINCT FROM NEW.line_status THEN
        INSERT INTO doms.sales_order_line_status_events (
            tenant_id, sales_order_id, sales_order_line_id, status_axis,
            from_status, to_status, reason_code_id, reason_text, changed_by
        ) VALUES (
            NEW.tenant_id, NEW.sales_order_id, NEW.id, 'LINE',
            CASE WHEN TG_OP = 'INSERT' THEN NULL ELSE OLD.line_status END,
            NEW.line_status, NEW.status_reason_code_id, NEW.status_reason, actor_id
        );
    END IF;
    IF TG_OP = 'INSERT' OR OLD.fulfillment_status IS DISTINCT FROM NEW.fulfillment_status THEN
        INSERT INTO doms.sales_order_line_status_events (
            tenant_id, sales_order_id, sales_order_line_id, status_axis,
            from_status, to_status, changed_by
        ) VALUES (
            NEW.tenant_id, NEW.sales_order_id, NEW.id, 'FULFILLMENT',
            CASE WHEN TG_OP = 'INSERT' THEN NULL ELSE OLD.fulfillment_status END,
            NEW.fulfillment_status, actor_id
        );
    END IF;
    IF TG_OP = 'INSERT' OR OLD.return_status IS DISTINCT FROM NEW.return_status THEN
        INSERT INTO doms.sales_order_line_status_events (
            tenant_id, sales_order_id, sales_order_line_id, status_axis,
            from_status, to_status, changed_by
        ) VALUES (
            NEW.tenant_id, NEW.sales_order_id, NEW.id, 'RETURN',
            CASE WHEN TG_OP = 'INSERT' THEN NULL ELSE OLD.return_status END,
            NEW.return_status, actor_id
        );
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.validate_quote_scope_and_totals()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    line_gross numeric(24,6);
    line_discount numeric(24,6);
    line_charge numeric(24,6);
    line_tax numeric(24,6);
BEGIN
    IF NEW.channel_account_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM doms.channel_accounts account_row
        WHERE account_row.id = NEW.channel_account_id
          AND account_row.tenant_id = NEW.tenant_id
          AND account_row.sales_channel_id = NEW.sales_channel_id
    ) THEN
        RAISE EXCEPTION 'Quote account must belong to its channel and tenant'
            USING ERRCODE = '23514';
    END IF;
    IF NEW.channel_store_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM doms.channel_stores store_row
        WHERE store_row.id = NEW.channel_store_id
          AND store_row.tenant_id = NEW.tenant_id
          AND store_row.channel_account_id = NEW.channel_account_id
    ) THEN
        RAISE EXCEPTION 'Quote store must belong to its channel account and tenant'
            USING ERRCODE = '23514';
    END IF;
    IF TG_OP = 'UPDATE' AND (
        OLD.tenant_id IS DISTINCT FROM NEW.tenant_id OR
        OLD.quote_no IS DISTINCT FROM NEW.quote_no OR
        OLD.external_quote_id IS DISTINCT FROM NEW.external_quote_id OR
        OLD.idempotency_key IS DISTINCT FROM NEW.idempotency_key
    ) THEN
        RAISE EXCEPTION 'Quote number and external identity are immutable'
            USING ERRCODE = '55000';
    END IF;
    IF NEW.quote_status IN ('PRICED','PRESENTED','ACCEPTED','CONVERTED') THEN
        SELECT COALESCE(sum(gross_amount),0), COALESCE(sum(discount_amount),0),
               COALESCE(sum(charge_amount),0), COALESCE(sum(tax_amount),0)
          INTO line_gross, line_discount, line_charge, line_tax
          FROM doms.quote_lines
         WHERE quote_id = NEW.id;
        IF line_gross = 0 AND NOT EXISTS (SELECT 1 FROM doms.quote_lines WHERE quote_id = NEW.id) THEN
            RAISE EXCEPTION 'Priced quote requires at least one line' USING ERRCODE = '23514';
        END IF;
        IF abs(NEW.gross_amount - line_gross) > 0.000001
           OR abs(NEW.discount_amount - line_discount) > 0.000001
           OR abs(NEW.charge_amount - line_charge) > 0.000001
           OR abs(NEW.tax_amount - line_tax) > 0.000001 THEN
            RAISE EXCEPTION 'Quote header totals do not reconcile to quote lines'
                USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.validate_quote_line_scope()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    quote_row doms.quotes%ROWTYPE;
BEGIN
    SELECT * INTO quote_row FROM doms.quotes WHERE id = NEW.quote_id;
    IF NOT FOUND OR quote_row.tenant_id IS DISTINCT FROM NEW.tenant_id
       OR quote_row.currency_code IS DISTINCT FROM NEW.currency_code THEN
        RAISE EXCEPTION 'Quote line tenant and currency must match its quote'
            USING ERRCODE = '23514';
    END IF;
    IF quote_row.quote_status NOT IN ('DRAFT','PRICED') THEN
        RAISE EXCEPTION 'Quote lines cannot change after the quote is presented'
            USING ERRCODE = '55000';
    END IF;
    IF TG_OP = 'UPDATE' AND (
        OLD.tenant_id IS DISTINCT FROM NEW.tenant_id OR
        OLD.quote_id IS DISTINCT FROM NEW.quote_id OR OLD.line_no IS DISTINCT FROM NEW.line_no
    ) THEN
        RAISE EXCEPTION 'Quote line scope and number are immutable' USING ERRCODE = '55000';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.validate_order_line_relation_scope()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM doms.sales_order_lines parent_line
        JOIN doms.sales_order_lines child_line ON child_line.id = NEW.child_line_id
        WHERE parent_line.id = NEW.parent_line_id
          AND parent_line.sales_order_id = NEW.sales_order_id
          AND child_line.sales_order_id = NEW.sales_order_id
          AND parent_line.tenant_id = NEW.tenant_id
          AND child_line.tenant_id = NEW.tenant_id
    ) THEN
        RAISE EXCEPTION 'Related order lines must belong to the same order and tenant'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.validate_order_bundle_component()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    parent_qty numeric(24,8);
BEGIN
    SELECT ordered_qty INTO parent_qty
    FROM doms.sales_order_lines
    WHERE id = NEW.bundle_line_id
      AND sales_order_id = NEW.sales_order_id
      AND tenant_id = NEW.tenant_id;
    IF parent_qty IS NULL THEN
        RAISE EXCEPTION 'Bundle component parent must belong to the same order and tenant'
            USING ERRCODE = '23514';
    END IF;
    IF abs(NEW.total_component_qty - (parent_qty * NEW.quantity_per_bundle)) > 0.00000001 THEN
        RAISE EXCEPTION 'Bundle component total quantity must equal order quantity times component quantity'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.validate_order_promotion_scope()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    order_row doms.sales_orders%ROWTYPE;
BEGIN
    SELECT * INTO order_row FROM doms.sales_orders WHERE id = NEW.sales_order_id;
    IF NOT FOUND OR order_row.tenant_id IS DISTINCT FROM NEW.tenant_id
       OR order_row.currency_code IS DISTINCT FROM NEW.currency_code THEN
        RAISE EXCEPTION 'Applied promotion must match its order tenant and currency'
            USING ERRCODE = '23514';
    END IF;
    IF NEW.discount_adjustment_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM doms.order_discount_adjustments adjustment
        WHERE adjustment.id = NEW.discount_adjustment_id
          AND adjustment.sales_order_id = NEW.sales_order_id
          AND adjustment.tenant_id = NEW.tenant_id
          AND adjustment.promotion_id = NEW.promotion_id
    ) THEN
        RAISE EXCEPTION 'Promotion discount adjustment must belong to the same order and promotion'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.validate_order_promotion_line_scope()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM doms.order_promotions promotion_row
        JOIN doms.sales_order_lines line_row ON line_row.id = NEW.sales_order_line_id
        WHERE promotion_row.id = NEW.order_promotion_id
          AND promotion_row.sales_order_id = NEW.sales_order_id
          AND promotion_row.tenant_id = NEW.tenant_id
          AND promotion_row.currency_code = NEW.currency_code
          AND line_row.sales_order_id = NEW.sales_order_id
          AND line_row.tenant_id = NEW.tenant_id
    ) THEN
        RAISE EXCEPTION 'Promotion allocation must match its order, promotion, line, tenant, and currency'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.validate_order_coupon_scope()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM doms.sales_orders order_row
        WHERE order_row.id = NEW.sales_order_id
          AND order_row.tenant_id = NEW.tenant_id
          AND order_row.customer_id = NEW.customer_id
          AND order_row.currency_code = NEW.currency_code
    ) THEN
        RAISE EXCEPTION 'Coupon redemption must match the order customer, tenant, and currency'
            USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM doms.coupons coupon_row
        WHERE coupon_row.id = NEW.coupon_id
          AND coupon_row.tenant_id = NEW.tenant_id
          AND coupon_row.coupon_code_hash = NEW.coupon_code_hash
          AND (coupon_row.assigned_customer_id IS NULL OR coupon_row.assigned_customer_id = NEW.customer_id)
    ) THEN
        RAISE EXCEPTION 'Coupon snapshot or assigned customer does not match the coupon master'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.validate_order_cancellation_line()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    line_row doms.sales_order_lines%ROWTYPE;
    request_order_id uuid;
    other_pending_qty numeric(24,8);
    cancellable_qty numeric(24,8);
BEGIN
    SELECT sales_order_id INTO request_order_id
    FROM doms.order_cancellation_requests
    WHERE id = NEW.order_cancellation_request_id AND tenant_id = NEW.tenant_id;
    SELECT * INTO line_row
    FROM doms.sales_order_lines
    WHERE id = NEW.sales_order_line_id AND tenant_id = NEW.tenant_id;
    IF request_order_id IS NULL OR NOT FOUND
       OR request_order_id IS DISTINCT FROM NEW.sales_order_id
       OR line_row.sales_order_id IS DISTINCT FROM NEW.sales_order_id THEN
        RAISE EXCEPTION 'Cancellation line must match its request, order line, and tenant'
            USING ERRCODE = '23514';
    END IF;
    cancellable_qty := line_row.ordered_qty - line_row.cancelled_qty - line_row.fulfilled_qty;
    SELECT COALESCE(sum(existing.requested_cancel_qty),0)
      INTO other_pending_qty
      FROM doms.order_cancellation_request_lines existing
      JOIN doms.order_cancellation_requests request_row
        ON request_row.id = existing.order_cancellation_request_id
     WHERE existing.sales_order_line_id = NEW.sales_order_line_id
       AND existing.id IS DISTINCT FROM NEW.id
       AND request_row.request_status IN (
           'REQUESTED','VALIDATING','APPROVAL_PENDING','APPROVED','PROCESSING','PARTIALLY_COMPLETED'
       );
    IF NEW.requested_cancel_qty + other_pending_qty > cancellable_qty + 0.00000001 THEN
        RAISE EXCEPTION 'Cancellation requests exceed the unfulfilled cancellable quantity'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.validate_order_relation_scope()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM doms.sales_orders source_order
        JOIN doms.sales_orders target_order ON target_order.id = NEW.target_order_id
        WHERE source_order.id = NEW.source_order_id
          AND source_order.tenant_id = NEW.tenant_id
          AND target_order.tenant_id = NEW.tenant_id
    ) THEN
        RAISE EXCEPTION 'Related orders must belong to the same tenant'
            USING ERRCODE = '23514';
    END IF;
    IF NEW.source_line_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM doms.sales_order_lines source_line
        JOIN doms.sales_order_lines target_line ON target_line.id = NEW.target_line_id
        WHERE source_line.id = NEW.source_line_id
          AND source_line.sales_order_id = NEW.source_order_id
          AND target_line.sales_order_id = NEW.target_order_id
          AND source_line.tenant_id = NEW.tenant_id
          AND target_line.tenant_id = NEW.tenant_id
    ) THEN
        RAISE EXCEPTION 'Related lines must belong to their respective related orders'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.record_order_hold_event()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    event_name text;
BEGIN
    IF TG_OP = 'INSERT' THEN
        event_name := 'PLACED';
    ELSIF OLD.hold_status IS NOT DISTINCT FROM NEW.hold_status THEN
        RETURN NEW;
    ELSE
        event_name := CASE NEW.hold_status
            WHEN 'RELEASE_PENDING' THEN 'RELEASE_REQUESTED'
            WHEN 'RELEASED' THEN 'RELEASED'
            WHEN 'EXPIRED' THEN 'EXPIRED'
            WHEN 'CANCELLED' THEN 'CANCELLED'
            ELSE 'ESCALATED'
        END;
    END IF;
    INSERT INTO doms.order_hold_events (
        tenant_id, sales_order_id, order_hold_id, event_type,
        from_status, to_status, actor_user_id, reason_text
    ) VALUES (
        NEW.tenant_id, NEW.sales_order_id, NEW.id, event_name,
        CASE WHEN TG_OP = 'INSERT' THEN NULL ELSE OLD.hold_status END,
        NEW.hold_status, COALESCE(NEW.released_by, NEW.placed_by),
        COALESCE(NEW.release_reason, NEW.reason_text)
    );
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_10_validate_quote_scope ON doms.quotes;
CREATE TRIGGER trg_10_validate_quote_scope
    BEFORE INSERT OR UPDATE ON doms.quotes
    FOR EACH ROW EXECUTE PROCEDURE doms.validate_quote_scope_and_totals();

DROP TRIGGER IF EXISTS trg_10_validate_quote_line_scope ON doms.quote_lines;
CREATE TRIGGER trg_10_validate_quote_line_scope
    BEFORE INSERT OR UPDATE ON doms.quote_lines
    FOR EACH ROW EXECUTE PROCEDURE doms.validate_quote_line_scope();

DROP TRIGGER IF EXISTS trg_10_validate_order_scope ON doms.sales_orders;
CREATE TRIGGER trg_10_validate_order_scope
    BEFORE INSERT OR UPDATE ON doms.sales_orders
    FOR EACH ROW EXECUTE PROCEDURE doms.validate_sales_order_scope();

DROP TRIGGER IF EXISTS trg_20_validate_order_mutation ON doms.sales_orders;
CREATE TRIGGER trg_20_validate_order_mutation
    BEFORE INSERT OR UPDATE ON doms.sales_orders
    FOR EACH ROW EXECUTE PROCEDURE doms.validate_sales_order_mutation();

DROP TRIGGER IF EXISTS trg_90_record_order_status ON doms.sales_orders;
CREATE TRIGGER trg_90_record_order_status
    AFTER INSERT OR UPDATE ON doms.sales_orders
    FOR EACH ROW EXECUTE PROCEDURE doms.record_sales_order_status_events();

DROP TRIGGER IF EXISTS trg_10_validate_order_totals ON doms.sales_order_totals;
CREATE TRIGGER trg_10_validate_order_totals
    BEFORE INSERT OR UPDATE ON doms.sales_order_totals
    FOR EACH ROW EXECUTE PROCEDURE doms.validate_sales_order_totals_scope();

DROP TRIGGER IF EXISTS trg_20_guard_order_totals_insert_delete ON doms.sales_order_totals;
CREATE TRIGGER trg_20_guard_order_totals_insert_delete
    BEFORE INSERT OR DELETE ON doms.sales_order_totals
    FOR EACH ROW EXECUTE PROCEDURE doms.guard_order_commercial_component();

DROP TRIGGER IF EXISTS trg_10_validate_order_line ON doms.sales_order_lines;
CREATE TRIGGER trg_10_validate_order_line
    BEFORE INSERT OR UPDATE ON doms.sales_order_lines
    FOR EACH ROW EXECUTE PROCEDURE doms.validate_sales_order_line_scope();

DROP TRIGGER IF EXISTS trg_20_guard_order_line_delete ON doms.sales_order_lines;
CREATE TRIGGER trg_20_guard_order_line_delete
    BEFORE DELETE ON doms.sales_order_lines
    FOR EACH ROW EXECUTE PROCEDURE doms.guard_order_commercial_component();

DROP TRIGGER IF EXISTS trg_90_record_order_line_status ON doms.sales_order_lines;
CREATE TRIGGER trg_90_record_order_line_status
    AFTER INSERT OR UPDATE ON doms.sales_order_lines
    FOR EACH ROW EXECUTE PROCEDURE doms.record_sales_order_line_status_events();

DROP TRIGGER IF EXISTS trg_10_validate_line_relation ON doms.sales_order_line_relations;
CREATE TRIGGER trg_10_validate_line_relation
    BEFORE INSERT OR UPDATE ON doms.sales_order_line_relations
    FOR EACH ROW EXECUTE PROCEDURE doms.validate_order_line_relation_scope();
DROP TRIGGER IF EXISTS trg_20_guard_line_relation ON doms.sales_order_line_relations;
CREATE TRIGGER trg_20_guard_line_relation
    BEFORE INSERT OR UPDATE OR DELETE ON doms.sales_order_line_relations
    FOR EACH ROW EXECUTE PROCEDURE doms.guard_order_commercial_component();

DROP TRIGGER IF EXISTS trg_10_validate_bundle_component ON doms.sales_order_bundle_components;
CREATE TRIGGER trg_10_validate_bundle_component
    BEFORE INSERT OR UPDATE ON doms.sales_order_bundle_components
    FOR EACH ROW EXECUTE PROCEDURE doms.validate_order_bundle_component();
DROP TRIGGER IF EXISTS trg_20_guard_bundle_component ON doms.sales_order_bundle_components;
CREATE TRIGGER trg_20_guard_bundle_component
    BEFORE INSERT OR UPDATE OR DELETE ON doms.sales_order_bundle_components
    FOR EACH ROW EXECUTE PROCEDURE doms.guard_order_commercial_component();

DROP TRIGGER IF EXISTS trg_10_validate_order_version ON doms.sales_order_versions;
CREATE TRIGGER trg_10_validate_order_version
    BEFORE INSERT OR UPDATE OR DELETE ON doms.sales_order_versions
    FOR EACH ROW EXECUTE PROCEDURE doms.validate_sales_order_version_mutation();

DO $block$
DECLARE
    table_name text;
BEGIN
    FOREACH table_name IN ARRAY ARRAY[
        'sales_order_version_lines','order_parties',
        'order_address_snapshots','order_contact_snapshots'
    ]::text[]
    LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS trg_10_guard_order_version_child ON doms.%I', table_name);
        EXECUTE format(
            'CREATE TRIGGER trg_10_guard_order_version_child '
            'BEFORE INSERT OR UPDATE OR DELETE ON doms.%I '
            'FOR EACH ROW EXECUTE PROCEDURE doms.guard_order_version_child()',
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
        'order_charges','order_discount_adjustments','order_taxes'
    ]::text[]
    LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS trg_10_validate_order_money ON doms.%I', table_name);
        EXECUTE format(
            'CREATE TRIGGER trg_10_validate_order_money '
            'BEFORE INSERT OR UPDATE ON doms.%I '
            'FOR EACH ROW EXECUTE PROCEDURE doms.validate_order_monetary_component()',
            table_name
        );
        EXECUTE format('DROP TRIGGER IF EXISTS trg_20_guard_order_commercial ON doms.%I', table_name);
        EXECUTE format(
            'CREATE TRIGGER trg_20_guard_order_commercial '
            'BEFORE INSERT OR UPDATE OR DELETE ON doms.%I '
            'FOR EACH ROW EXECUTE PROCEDURE doms.guard_order_commercial_component()',
            table_name
        );
    END LOOP;
END;
$block$;

DROP TRIGGER IF EXISTS trg_10_validate_order_promotion ON doms.order_promotions;
CREATE TRIGGER trg_10_validate_order_promotion
    BEFORE INSERT OR UPDATE ON doms.order_promotions
    FOR EACH ROW EXECUTE PROCEDURE doms.validate_order_promotion_scope();
DROP TRIGGER IF EXISTS trg_20_guard_order_promotion ON doms.order_promotions;
CREATE TRIGGER trg_20_guard_order_promotion
    BEFORE INSERT OR UPDATE OR DELETE ON doms.order_promotions
    FOR EACH ROW EXECUTE PROCEDURE doms.guard_order_commercial_component();

DROP TRIGGER IF EXISTS trg_10_validate_order_promo_line ON doms.order_promotion_lines;
CREATE TRIGGER trg_10_validate_order_promo_line
    BEFORE INSERT OR UPDATE ON doms.order_promotion_lines
    FOR EACH ROW EXECUTE PROCEDURE doms.validate_order_promotion_line_scope();
DROP TRIGGER IF EXISTS trg_20_guard_order_promo_line ON doms.order_promotion_lines;
CREATE TRIGGER trg_20_guard_order_promo_line
    BEFORE INSERT OR UPDATE OR DELETE ON doms.order_promotion_lines
    FOR EACH ROW EXECUTE PROCEDURE doms.guard_order_commercial_component();

DROP TRIGGER IF EXISTS trg_10_validate_order_coupon ON doms.order_coupon_redemptions;
CREATE TRIGGER trg_10_validate_order_coupon
    BEFORE INSERT OR UPDATE ON doms.order_coupon_redemptions
    FOR EACH ROW EXECUTE PROCEDURE doms.validate_order_coupon_scope();
DROP TRIGGER IF EXISTS trg_20_guard_order_coupon ON doms.order_coupon_redemptions;
CREATE TRIGGER trg_20_guard_order_coupon
    BEFORE INSERT OR UPDATE OR DELETE ON doms.order_coupon_redemptions
    FOR EACH ROW EXECUTE PROCEDURE doms.guard_order_commercial_component();

DROP TRIGGER IF EXISTS trg_10_validate_cancel_line ON doms.order_cancellation_request_lines;
CREATE TRIGGER trg_10_validate_cancel_line
    BEFORE INSERT OR UPDATE ON doms.order_cancellation_request_lines
    FOR EACH ROW EXECUTE PROCEDURE doms.validate_order_cancellation_line();

DROP TRIGGER IF EXISTS trg_10_validate_order_relation ON doms.order_relations;
CREATE TRIGGER trg_10_validate_order_relation
    BEFORE INSERT OR UPDATE ON doms.order_relations
    FOR EACH ROW EXECUTE PROCEDURE doms.validate_order_relation_scope();

DROP TRIGGER IF EXISTS trg_90_record_order_hold_event ON doms.order_holds;
CREATE TRIGGER trg_90_record_order_hold_event
    AFTER INSERT OR UPDATE OF hold_status ON doms.order_holds
    FOR EACH ROW EXECUTE PROCEDURE doms.record_order_hold_event();

-- Strict append-only order records. These local guards make the evidence safe even
-- before the final operations module installs its schema-wide append-only catalog.
DO $block$
DECLARE
    table_name text;
BEGIN
    FOREACH table_name IN ARRAY ARRAY[
        'sales_order_status_events','sales_order_line_status_events',
        'order_hold_events','order_events','order_validation_results',
        'order_change_request_events','order_cancellation_events'
    ]::text[]
    LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS trg_doms_order_append_only ON doms.%I', table_name);
        EXECUTE format(
            'CREATE TRIGGER trg_doms_order_append_only '
            'BEFORE UPDATE OR DELETE ON doms.%I '
            'FOR EACH ROW EXECUTE PROCEDURE doms.prevent_order_append_only_change()',
            table_name
        );
        EXECUTE format('DROP TRIGGER IF EXISTS trg_doms_order_append_only_truncate ON doms.%I', table_name);
        EXECUTE format(
            'CREATE TRIGGER trg_doms_order_append_only_truncate '
            'BEFORE TRUNCATE ON doms.%I '
            'FOR EACH STATEMENT EXECUTE PROCEDURE doms.prevent_order_append_only_change()',
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
        'sales_order_versions','sales_order_version_lines','order_parties',
        'order_address_snapshots','order_contact_snapshots'
    ]::text[]
    LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS trg_doms_order_version_truncate ON doms.%I', table_name);
        EXECUTE format(
            'CREATE TRIGGER trg_doms_order_version_truncate '
            'BEFORE TRUNCATE ON doms.%I '
            'FOR EACH STATEMENT EXECUTE PROCEDURE doms.prevent_order_append_only_change()',
            table_name
        );
    END LOOP;
END;
$block$;

REVOKE EXECUTE ON FUNCTION doms.prevent_order_append_only_change() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION doms.validate_sales_order_version_mutation() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION doms.guard_order_version_child() FROM PUBLIC;
