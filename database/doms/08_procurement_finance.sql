-- DOMS enterprise OMS schema - supplier procurement, drop ship, invoicing,
-- channel settlement, payout, and accounting interface.
-- PostgreSQL 11 compatible. Applied after fulfillment and returns modules.

CREATE TABLE IF NOT EXISTS doms.supplier_profiles (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    supplier_partner_id uuid NOT NULL REFERENCES doms.business_partners(id) ON DELETE RESTRICT,
    supplier_code varchar(80) NOT NULL,
    supplier_type varchar(30) NOT NULL DEFAULT 'MERCHANDISE',
    default_currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    default_payment_term_id uuid REFERENCES doms.payment_terms(id),
    default_lead_time_days integer NOT NULL DEFAULT 0,
    supports_dropship boolean NOT NULL DEFAULT false,
    supports_electronic_ack boolean NOT NULL DEFAULT false,
    quality_status varchar(20) NOT NULL DEFAULT 'UNASSESSED',
    status varchar(20) NOT NULL DEFAULT 'ONBOARDING',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    UNIQUE (tenant_id, supplier_partner_id),
    UNIQUE (tenant_id, supplier_code),
    CONSTRAINT ck_supplier_profiles_type CHECK (supplier_type IN ('MERCHANDISE','DROPSHIP','SERVICE','MARKETPLACE','INTERNAL')),
    CONSTRAINT ck_supplier_profiles_lead_time CHECK (default_lead_time_days >= 0),
    CONSTRAINT ck_supplier_profiles_quality CHECK (quality_status IN ('UNASSESSED','APPROVED','CONDITIONAL','BLOCKED')),
    CONSTRAINT ck_supplier_profiles_status CHECK (status IN ('ONBOARDING','ACTIVE','SUSPENDED','TERMINATED'))
);

CREATE TABLE IF NOT EXISTS doms.supplier_items (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    supplier_profile_id uuid NOT NULL REFERENCES doms.supplier_profiles(id) ON DELETE RESTRICT,
    item_id uuid NOT NULL REFERENCES doms.items(id) ON DELETE RESTRICT,
    supplier_item_code varchar(160),
    supplier_item_name varchar(300),
    purchase_uom_code varchar(20) NOT NULL REFERENCES doms.units_of_measure(uom_code),
    purchase_to_base_factor numeric(24,8) NOT NULL DEFAULT 1,
    minimum_order_quantity numeric(24,8) NOT NULL DEFAULT 1,
    order_multiple numeric(24,8) NOT NULL DEFAULT 1,
    lead_time_days integer,
    unit_cost numeric(20,6),
    currency_code char(3) REFERENCES doms.currencies(currency_code),
    country_of_origin char(2) REFERENCES doms.countries(country_code),
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, supplier_profile_id, item_id),
    UNIQUE (tenant_id, supplier_profile_id, supplier_item_code),
    CONSTRAINT ck_supplier_items_quantities CHECK (
        purchase_to_base_factor > 0 AND minimum_order_quantity > 0 AND order_multiple > 0
    ),
    CONSTRAINT ck_supplier_items_lead CHECK (lead_time_days IS NULL OR lead_time_days >= 0),
    CONSTRAINT ck_supplier_items_cost CHECK (
        (unit_cost IS NULL AND currency_code IS NULL) OR
        (unit_cost IS NOT NULL AND unit_cost >= 0 AND currency_code IS NOT NULL)
    ),
    CONSTRAINT ck_supplier_items_status CHECK (status IN ('DRAFT','ACTIVE','BLOCKED','DISCONTINUED')),
    CONSTRAINT ck_supplier_items_attributes_secrets CHECK (NOT doms.jsonb_contains_forbidden_secret_key(attributes))
);

CREATE TABLE IF NOT EXISTS doms.supplier_contracts (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    contract_no varchar(100) NOT NULL,
    supplier_profile_id uuid NOT NULL REFERENCES doms.supplier_profiles(id) ON DELETE RESTRICT,
    organization_id uuid NOT NULL REFERENCES doms.organizations(id) ON DELETE RESTRICT,
    contract_type varchar(30) NOT NULL DEFAULT 'PURCHASE',
    currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    payment_term_id uuid REFERENCES doms.payment_terms(id),
    valid_from date NOT NULL,
    valid_to date,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    UNIQUE (tenant_id, contract_no),
    CONSTRAINT ck_supplier_contracts_type CHECK (contract_type IN ('PURCHASE','DROPSHIP','CONSIGNMENT','SERVICE','FRAME')),
    CONSTRAINT ck_supplier_contracts_status CHECK (status IN ('DRAFT','PENDING_APPROVAL','ACTIVE','SUSPENDED','EXPIRED','TERMINATED')),
    CONSTRAINT ck_supplier_contracts_dates CHECK (valid_to IS NULL OR valid_to >= valid_from)
);

CREATE TABLE IF NOT EXISTS doms.supplier_contract_versions (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    supplier_contract_id uuid NOT NULL REFERENCES doms.supplier_contracts(id) ON DELETE RESTRICT,
    version_no integer NOT NULL,
    effective_from timestamptz NOT NULL,
    effective_to timestamptz,
    terms_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    approved_by uuid REFERENCES doms.users(id),
    approved_at timestamptz,
    published_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, supplier_contract_id, version_no),
    CONSTRAINT ck_supplier_contract_versions_number CHECK (version_no > 0),
    CONSTRAINT ck_supplier_contract_versions_dates CHECK (effective_to IS NULL OR effective_to > effective_from),
    CONSTRAINT ck_supplier_contract_versions_status CHECK (status IN ('DRAFT','APPROVED','PUBLISHED','SUPERSEDED','REVOKED')),
    CONSTRAINT ck_supplier_contract_versions_approval CHECK (
        status NOT IN ('APPROVED','PUBLISHED') OR (approved_by IS NOT NULL AND approved_at IS NOT NULL)
    ),
    CONSTRAINT ck_supplier_contract_versions_publish CHECK (status <> 'PUBLISHED' OR published_at IS NOT NULL),
    CONSTRAINT ck_supplier_contract_versions_secrets CHECK (NOT doms.jsonb_contains_forbidden_secret_key(terms_snapshot))
);

CREATE TABLE IF NOT EXISTS doms.supplier_contract_lines (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    supplier_contract_version_id uuid NOT NULL REFERENCES doms.supplier_contract_versions(id) ON DELETE RESTRICT,
    line_no integer NOT NULL,
    supplier_item_id uuid REFERENCES doms.supplier_items(id),
    item_id uuid NOT NULL REFERENCES doms.items(id) ON DELETE RESTRICT,
    purchase_uom_code varchar(20) NOT NULL REFERENCES doms.units_of_measure(uom_code),
    unit_cost numeric(20,6) NOT NULL,
    minimum_quantity numeric(24,8) NOT NULL DEFAULT 1,
    maximum_quantity numeric(24,8),
    lead_time_days integer,
    valid_from timestamptz,
    valid_to timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, supplier_contract_version_id, line_no),
    CONSTRAINT ck_supplier_contract_lines_number CHECK (line_no > 0),
    CONSTRAINT ck_supplier_contract_lines_cost CHECK (unit_cost >= 0),
    CONSTRAINT ck_supplier_contract_lines_quantity CHECK (
        minimum_quantity > 0 AND (maximum_quantity IS NULL OR maximum_quantity >= minimum_quantity)
    ),
    CONSTRAINT ck_supplier_contract_lines_lead CHECK (lead_time_days IS NULL OR lead_time_days >= 0),
    CONSTRAINT ck_supplier_contract_lines_dates CHECK (valid_to IS NULL OR valid_from IS NULL OR valid_to > valid_from)
);

CREATE TABLE IF NOT EXISTS doms.purchase_orders (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    purchase_order_no varchar(100) NOT NULL,
    purchase_order_type varchar(30) NOT NULL DEFAULT 'STANDARD',
    supplier_profile_id uuid NOT NULL REFERENCES doms.supplier_profiles(id) ON DELETE RESTRICT,
    supplier_contract_version_id uuid REFERENCES doms.supplier_contract_versions(id) ON DELETE RESTRICT,
    organization_id uuid NOT NULL REFERENCES doms.organizations(id) ON DELETE RESTRICT,
    destination_node_id uuid REFERENCES doms.fulfillment_nodes(id) ON DELETE RESTRICT,
    related_sales_order_id uuid REFERENCES doms.sales_orders(id) ON DELETE RESTRICT,
    external_purchase_order_id varchar(200),
    currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    order_date date NOT NULL,
    requested_ship_date date,
    requested_delivery_date date,
    subtotal_amount numeric(20,6) NOT NULL DEFAULT 0,
    charge_amount numeric(20,6) NOT NULL DEFAULT 0,
    tax_amount numeric(20,6) NOT NULL DEFAULT 0,
    total_amount numeric(20,6) NOT NULL DEFAULT 0,
    status varchar(30) NOT NULL DEFAULT 'DRAFT',
    approval_status varchar(20) NOT NULL DEFAULT 'NOT_REQUIRED',
    approved_by uuid REFERENCES doms.users(id),
    approved_at timestamptz,
    submitted_at timestamptz,
    closed_at timestamptz,
    idempotency_key varchar(200),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, purchase_order_no),
    CONSTRAINT ck_purchase_orders_type CHECK (purchase_order_type IN ('STANDARD','DROPSHIP','CONSIGNMENT','SERVICE','EMERGENCY')),
    CONSTRAINT ck_purchase_orders_amounts CHECK (
        subtotal_amount >= 0 AND charge_amount >= 0 AND tax_amount >= 0 AND total_amount >= 0 AND
        total_amount = subtotal_amount + charge_amount + tax_amount
    ),
    CONSTRAINT ck_purchase_orders_status CHECK (status IN ('DRAFT','PENDING_APPROVAL','SUBMITTED','ACKNOWLEDGED','PARTIALLY_SHIPPED','SHIPPED','PARTIALLY_RECEIVED','RECEIVED','CANCELLED','CLOSED')),
    CONSTRAINT ck_purchase_orders_approval CHECK (approval_status IN ('NOT_REQUIRED','PENDING','APPROVED','REJECTED')),
    CONSTRAINT ck_purchase_orders_approved CHECK (
        approval_status <> 'APPROVED' OR (approved_by IS NOT NULL AND approved_at IS NOT NULL)
    ),
    CONSTRAINT ck_purchase_orders_dates CHECK (
        requested_delivery_date IS NULL OR requested_ship_date IS NULL OR requested_delivery_date >= requested_ship_date
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_purchase_orders_external
    ON doms.purchase_orders (tenant_id, supplier_profile_id, external_purchase_order_id)
    WHERE external_purchase_order_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_purchase_orders_idempotency
    ON doms.purchase_orders (tenant_id, idempotency_key)
    WHERE idempotency_key IS NOT NULL;

CREATE TABLE IF NOT EXISTS doms.purchase_order_lines (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    purchase_order_id uuid NOT NULL REFERENCES doms.purchase_orders(id) ON DELETE RESTRICT,
    line_no integer NOT NULL,
    item_id uuid NOT NULL REFERENCES doms.items(id) ON DELETE RESTRICT,
    supplier_item_id uuid REFERENCES doms.supplier_items(id),
    related_sales_order_line_id uuid REFERENCES doms.sales_order_lines(id) ON DELETE RESTRICT,
    uom_code varchar(20) NOT NULL REFERENCES doms.units_of_measure(uom_code),
    ordered_quantity numeric(24,8) NOT NULL,
    acknowledged_quantity numeric(24,8) NOT NULL DEFAULT 0,
    shipped_quantity numeric(24,8) NOT NULL DEFAULT 0,
    received_quantity numeric(24,8) NOT NULL DEFAULT 0,
    cancelled_quantity numeric(24,8) NOT NULL DEFAULT 0,
    unit_cost numeric(20,6) NOT NULL,
    tax_amount numeric(20,6) NOT NULL DEFAULT 0,
    line_total_amount numeric(20,6) NOT NULL,
    requested_delivery_date date,
    promised_delivery_date date,
    status varchar(30) NOT NULL DEFAULT 'OPEN',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, purchase_order_id, line_no),
    CONSTRAINT ck_purchase_order_lines_number CHECK (line_no > 0),
    CONSTRAINT ck_purchase_order_lines_quantities CHECK (
        ordered_quantity > 0 AND acknowledged_quantity >= 0 AND shipped_quantity >= 0 AND
        received_quantity >= 0 AND cancelled_quantity >= 0 AND
        acknowledged_quantity <= ordered_quantity AND shipped_quantity <= ordered_quantity AND
        received_quantity <= shipped_quantity AND cancelled_quantity + received_quantity <= ordered_quantity
    ),
    CONSTRAINT ck_purchase_order_lines_amounts CHECK (
        unit_cost >= 0 AND tax_amount >= 0 AND line_total_amount >= 0 AND
        line_total_amount = ordered_quantity * unit_cost + tax_amount
    ),
    CONSTRAINT ck_purchase_order_lines_status CHECK (status IN ('OPEN','ACKNOWLEDGED','BACKORDERED','PARTIALLY_SHIPPED','SHIPPED','PARTIALLY_RECEIVED','RECEIVED','CANCELLED','CLOSED')),
    CONSTRAINT ck_purchase_order_lines_dates CHECK (
        promised_delivery_date IS NULL OR requested_delivery_date IS NULL OR promised_delivery_date >= requested_delivery_date
    )
);

CREATE TABLE IF NOT EXISTS doms.purchase_order_events (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    purchase_order_id uuid NOT NULL REFERENCES doms.purchase_orders(id) ON DELETE RESTRICT,
    event_type varchar(50) NOT NULL,
    from_status varchar(30),
    to_status varchar(30),
    reason_code varchar(100),
    actor_user_id uuid REFERENCES doms.users(id),
    correlation_id uuid,
    idempotency_key varchar(200),
    payload_masked jsonb NOT NULL DEFAULT '{}'::jsonb,
    occurred_at timestamptz NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_purchase_order_events_status CHECK (from_status IS DISTINCT FROM to_status OR event_type <> 'STATUS_CHANGED'),
    CONSTRAINT ck_purchase_order_events_secrets CHECK (NOT doms.jsonb_contains_forbidden_secret_key(payload_masked))
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_purchase_order_events_idempotency
    ON doms.purchase_order_events (tenant_id, purchase_order_id, idempotency_key)
    WHERE idempotency_key IS NOT NULL;

CREATE TABLE IF NOT EXISTS doms.purchase_order_acknowledgements (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    purchase_order_id uuid NOT NULL REFERENCES doms.purchase_orders(id) ON DELETE RESTRICT,
    acknowledgement_no varchar(120) NOT NULL,
    external_acknowledgement_id varchar(200),
    acknowledgement_type varchar(20) NOT NULL,
    supplier_response_at timestamptz NOT NULL,
    received_at timestamptz NOT NULL DEFAULT now(),
    status varchar(20) NOT NULL DEFAULT 'RECEIVED',
    notes text,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, acknowledgement_no),
    CONSTRAINT ck_purchase_order_ack_type CHECK (acknowledgement_type IN ('ACCEPT','PARTIAL_ACCEPT','REJECT','CHANGE')),
    CONSTRAINT ck_purchase_order_ack_status CHECK (status IN ('RECEIVED','VALIDATED','APPLIED','REJECTED'))
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_purchase_order_ack_external
    ON doms.purchase_order_acknowledgements (tenant_id, purchase_order_id, external_acknowledgement_id)
    WHERE external_acknowledgement_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS doms.purchase_order_acknowledgement_lines (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    purchase_order_acknowledgement_id uuid NOT NULL REFERENCES doms.purchase_order_acknowledgements(id) ON DELETE RESTRICT,
    purchase_order_line_id uuid NOT NULL REFERENCES doms.purchase_order_lines(id) ON DELETE RESTRICT,
    response_code varchar(30) NOT NULL,
    acknowledged_quantity numeric(24,8) NOT NULL DEFAULT 0,
    backordered_quantity numeric(24,8) NOT NULL DEFAULT 0,
    rejected_quantity numeric(24,8) NOT NULL DEFAULT 0,
    promised_ship_date date,
    promised_delivery_date date,
    reason_code varchar(100),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, purchase_order_acknowledgement_id, purchase_order_line_id),
    CONSTRAINT ck_purchase_order_ack_lines_response CHECK (response_code IN ('ACCEPTED','BACKORDERED','REJECTED','SUBSTITUTED','DATE_CHANGED','PRICE_CHANGED')),
    CONSTRAINT ck_purchase_order_ack_lines_quantities CHECK (
        acknowledged_quantity >= 0 AND backordered_quantity >= 0 AND rejected_quantity >= 0
    ),
    CONSTRAINT ck_purchase_order_ack_lines_dates CHECK (
        promised_delivery_date IS NULL OR promised_ship_date IS NULL OR promised_delivery_date >= promised_ship_date
    )
);

CREATE TABLE IF NOT EXISTS doms.supplier_shipments (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    supplier_shipment_no varchar(120) NOT NULL,
    purchase_order_id uuid NOT NULL REFERENCES doms.purchase_orders(id) ON DELETE RESTRICT,
    external_shipment_id varchar(200),
    carrier_id uuid REFERENCES doms.carriers(id),
    tracking_number_masked varchar(200),
    ship_from_country_code char(2) REFERENCES doms.countries(country_code),
    shipped_at timestamptz,
    estimated_arrival_at timestamptz,
    arrived_at timestamptz,
    status varchar(30) NOT NULL DEFAULT 'PLANNED',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, supplier_shipment_no),
    CONSTRAINT ck_supplier_shipments_status CHECK (status IN ('PLANNED','CONFIRMED','IN_TRANSIT','ARRIVED','PARTIALLY_RECEIVED','RECEIVED','CANCELLED')),
    CONSTRAINT ck_supplier_shipments_dates CHECK (
        (estimated_arrival_at IS NULL OR shipped_at IS NULL OR estimated_arrival_at >= shipped_at) AND
        (arrived_at IS NULL OR shipped_at IS NULL OR arrived_at >= shipped_at)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_supplier_shipments_external
    ON doms.supplier_shipments (tenant_id, purchase_order_id, external_shipment_id)
    WHERE external_shipment_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS doms.supplier_shipment_lines (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    supplier_shipment_id uuid NOT NULL REFERENCES doms.supplier_shipments(id) ON DELETE RESTRICT,
    purchase_order_line_id uuid NOT NULL REFERENCES doms.purchase_order_lines(id) ON DELETE RESTRICT,
    line_no integer NOT NULL,
    item_id uuid NOT NULL REFERENCES doms.items(id) ON DELETE RESTRICT,
    uom_code varchar(20) NOT NULL REFERENCES doms.units_of_measure(uom_code),
    shipped_quantity numeric(24,8) NOT NULL,
    lot_reference varchar(150),
    expiry_date date,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, supplier_shipment_id, line_no),
    CONSTRAINT ck_supplier_shipment_lines_number CHECK (line_no > 0),
    CONSTRAINT ck_supplier_shipment_lines_quantity CHECK (shipped_quantity > 0)
);

CREATE TABLE IF NOT EXISTS doms.supplier_receipts (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    supplier_receipt_no varchar(120) NOT NULL,
    supplier_shipment_id uuid REFERENCES doms.supplier_shipments(id) ON DELETE RESTRICT,
    purchase_order_id uuid NOT NULL REFERENCES doms.purchase_orders(id) ON DELETE RESTRICT,
    fulfillment_node_id uuid NOT NULL REFERENCES doms.fulfillment_nodes(id) ON DELETE RESTRICT,
    external_receipt_id varchar(200),
    received_at timestamptz NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'RECEIVED',
    confirmed_by uuid REFERENCES doms.users(id),
    confirmed_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, supplier_receipt_no),
    CONSTRAINT ck_supplier_receipts_status CHECK (status IN ('RECEIVED','VALIDATING','CONFIRMED','REJECTED','REVERSED')),
    CONSTRAINT ck_supplier_receipts_confirmation CHECK (
        status <> 'CONFIRMED' OR (confirmed_by IS NOT NULL AND confirmed_at IS NOT NULL)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_supplier_receipts_external
    ON doms.supplier_receipts (tenant_id, fulfillment_node_id, external_receipt_id)
    WHERE external_receipt_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS doms.supplier_receipt_lines (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    supplier_receipt_id uuid NOT NULL REFERENCES doms.supplier_receipts(id) ON DELETE RESTRICT,
    purchase_order_line_id uuid NOT NULL REFERENCES doms.purchase_order_lines(id) ON DELETE RESTRICT,
    supplier_shipment_line_id uuid REFERENCES doms.supplier_shipment_lines(id) ON DELETE RESTRICT,
    line_no integer NOT NULL,
    item_id uuid NOT NULL REFERENCES doms.items(id) ON DELETE RESTRICT,
    uom_code varchar(20) NOT NULL REFERENCES doms.units_of_measure(uom_code),
    received_quantity numeric(24,8) NOT NULL,
    accepted_quantity numeric(24,8) NOT NULL DEFAULT 0,
    rejected_quantity numeric(24,8) NOT NULL DEFAULT 0,
    rejection_reason_code varchar(100),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, supplier_receipt_id, line_no),
    CONSTRAINT ck_supplier_receipt_lines_number CHECK (line_no > 0),
    CONSTRAINT ck_supplier_receipt_lines_quantities CHECK (
        received_quantity > 0 AND accepted_quantity >= 0 AND rejected_quantity >= 0 AND
        accepted_quantity + rejected_quantity = received_quantity
    )
);

CREATE TABLE IF NOT EXISTS doms.dropship_orders (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    dropship_order_no varchar(120) NOT NULL,
    sales_order_id uuid NOT NULL REFERENCES doms.sales_orders(id) ON DELETE RESTRICT,
    purchase_order_id uuid NOT NULL REFERENCES doms.purchase_orders(id) ON DELETE RESTRICT,
    supplier_profile_id uuid NOT NULL REFERENCES doms.supplier_profiles(id) ON DELETE RESTRICT,
    ship_to_address_snapshot_id uuid NOT NULL REFERENCES doms.order_address_snapshots(id) ON DELETE RESTRICT,
    external_dropship_id varchar(200),
    status varchar(30) NOT NULL DEFAULT 'REQUESTED',
    requested_at timestamptz NOT NULL DEFAULT now(),
    accepted_at timestamptz,
    shipped_at timestamptz,
    delivered_at timestamptz,
    cancelled_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, dropship_order_no),
    UNIQUE (tenant_id, purchase_order_id),
    CONSTRAINT ck_dropship_orders_status CHECK (status IN ('REQUESTED','ACCEPTED','PARTIALLY_SHIPPED','SHIPPED','DELIVERED','REJECTED','CANCELLED','FAILED')),
    CONSTRAINT ck_dropship_orders_dates CHECK (
        (accepted_at IS NULL OR accepted_at >= requested_at) AND
        (shipped_at IS NULL OR shipped_at >= requested_at) AND
        (delivered_at IS NULL OR shipped_at IS NULL OR delivered_at >= shipped_at) AND
        (cancelled_at IS NULL OR cancelled_at >= requested_at)
    )
);

CREATE TABLE IF NOT EXISTS doms.dropship_order_lines (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    dropship_order_id uuid NOT NULL REFERENCES doms.dropship_orders(id) ON DELETE RESTRICT,
    sales_order_line_id uuid NOT NULL REFERENCES doms.sales_order_lines(id) ON DELETE RESTRICT,
    purchase_order_line_id uuid NOT NULL REFERENCES doms.purchase_order_lines(id) ON DELETE RESTRICT,
    item_id uuid NOT NULL REFERENCES doms.items(id) ON DELETE RESTRICT,
    uom_code varchar(20) NOT NULL REFERENCES doms.units_of_measure(uom_code),
    requested_quantity numeric(24,8) NOT NULL,
    accepted_quantity numeric(24,8) NOT NULL DEFAULT 0,
    shipped_quantity numeric(24,8) NOT NULL DEFAULT 0,
    delivered_quantity numeric(24,8) NOT NULL DEFAULT 0,
    cancelled_quantity numeric(24,8) NOT NULL DEFAULT 0,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, dropship_order_id, sales_order_line_id),
    CONSTRAINT ck_dropship_order_lines_quantities CHECK (
        requested_quantity > 0 AND accepted_quantity >= 0 AND shipped_quantity >= 0 AND
        delivered_quantity >= 0 AND cancelled_quantity >= 0 AND
        accepted_quantity <= requested_quantity AND shipped_quantity <= accepted_quantity AND
        delivered_quantity <= shipped_quantity AND cancelled_quantity + shipped_quantity <= requested_quantity
    )
);

CREATE TABLE IF NOT EXISTS doms.dropship_events (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    dropship_order_id uuid NOT NULL REFERENCES doms.dropship_orders(id) ON DELETE RESTRICT,
    event_type varchar(50) NOT NULL,
    from_status varchar(30),
    to_status varchar(30),
    external_event_id varchar(200),
    tracking_reference_masked varchar(200),
    payload_masked jsonb NOT NULL DEFAULT '{}'::jsonb,
    occurred_at timestamptz NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_dropship_events_secrets CHECK (NOT doms.jsonb_contains_forbidden_secret_key(payload_masked))
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_dropship_events_external
    ON doms.dropship_events (tenant_id, dropship_order_id, external_event_id)
    WHERE external_event_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS doms.transfer_orders (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    transfer_order_no varchar(120) NOT NULL,
    from_node_id uuid NOT NULL REFERENCES doms.fulfillment_nodes(id) ON DELETE RESTRICT,
    to_node_id uuid NOT NULL REFERENCES doms.fulfillment_nodes(id) ON DELETE RESTRICT,
    reason_code varchar(100),
    requested_ship_date date,
    requested_arrival_date date,
    status varchar(30) NOT NULL DEFAULT 'DRAFT',
    approved_by uuid REFERENCES doms.users(id),
    approved_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, transfer_order_no),
    CONSTRAINT ck_transfer_orders_nodes CHECK (from_node_id <> to_node_id),
    CONSTRAINT ck_transfer_orders_status CHECK (status IN ('DRAFT','APPROVED','RELEASED','IN_TRANSIT','PARTIALLY_RECEIVED','RECEIVED','CANCELLED','CLOSED')),
    CONSTRAINT ck_transfer_orders_approval CHECK (status <> 'APPROVED' OR (approved_by IS NOT NULL AND approved_at IS NOT NULL)),
    CONSTRAINT ck_transfer_orders_dates CHECK (
        requested_arrival_date IS NULL OR requested_ship_date IS NULL OR requested_arrival_date >= requested_ship_date
    )
);

CREATE TABLE IF NOT EXISTS doms.transfer_order_lines (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    transfer_order_id uuid NOT NULL REFERENCES doms.transfer_orders(id) ON DELETE RESTRICT,
    line_no integer NOT NULL,
    item_id uuid NOT NULL REFERENCES doms.items(id) ON DELETE RESTRICT,
    uom_code varchar(20) NOT NULL REFERENCES doms.units_of_measure(uom_code),
    requested_quantity numeric(24,8) NOT NULL,
    shipped_quantity numeric(24,8) NOT NULL DEFAULT 0,
    received_quantity numeric(24,8) NOT NULL DEFAULT 0,
    cancelled_quantity numeric(24,8) NOT NULL DEFAULT 0,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, transfer_order_id, line_no),
    CONSTRAINT ck_transfer_order_lines_number CHECK (line_no > 0),
    CONSTRAINT ck_transfer_order_lines_quantities CHECK (
        requested_quantity > 0 AND shipped_quantity >= 0 AND received_quantity >= 0 AND cancelled_quantity >= 0 AND
        shipped_quantity + cancelled_quantity <= requested_quantity AND received_quantity <= shipped_quantity
    )
);

CREATE TABLE IF NOT EXISTS doms.transfer_order_events (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    transfer_order_id uuid NOT NULL REFERENCES doms.transfer_orders(id) ON DELETE RESTRICT,
    event_type varchar(50) NOT NULL,
    from_status varchar(30),
    to_status varchar(30),
    reason_code varchar(100),
    actor_user_id uuid REFERENCES doms.users(id),
    external_event_id varchar(200),
    payload_masked jsonb NOT NULL DEFAULT '{}'::jsonb,
    occurred_at timestamptz NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_transfer_order_events_secrets CHECK (NOT doms.jsonb_contains_forbidden_secret_key(payload_masked))
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_transfer_order_events_external
    ON doms.transfer_order_events (tenant_id, transfer_order_id, external_event_id)
    WHERE external_event_id IS NOT NULL;

CREATE OR REPLACE FUNCTION doms.validate_purchase_order_finalization()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    line_count bigint;
    detail_subtotal numeric(20,6);
    detail_tax numeric(20,6);
BEGIN
    IF NEW.status IN ('DRAFT','PENDING_APPROVAL','CANCELLED') THEN
        RETURN NEW;
    END IF;
    SELECT count(*), COALESCE(sum(ordered_quantity * unit_cost), 0),
           COALESCE(sum(tax_amount), 0)
      INTO line_count, detail_subtotal, detail_tax
      FROM doms.purchase_order_lines
     WHERE tenant_id = NEW.tenant_id AND purchase_order_id = NEW.id;
    IF line_count = 0 OR NEW.subtotal_amount IS DISTINCT FROM detail_subtotal
       OR NEW.tax_amount IS DISTINCT FROM detail_tax
       OR NEW.total_amount IS DISTINCT FROM detail_subtotal + NEW.charge_amount + detail_tax THEN
        RAISE EXCEPTION 'Purchase order totals do not reconcile to order lines'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.protect_submitted_purchase_order_core()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    old_core jsonb;
    new_core jsonb;
BEGIN
    IF OLD.status IN ('DRAFT','PENDING_APPROVAL') THEN
        RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
    END IF;
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'Submitted purchase orders cannot be deleted'
            USING ERRCODE = '55000';
    END IF;
    old_core := to_jsonb(OLD) - 'status' - 'closed_at' - 'row_version' - 'updated_at';
    new_core := to_jsonb(NEW) - 'status' - 'closed_at' - 'row_version' - 'updated_at';
    IF old_core IS DISTINCT FROM new_core THEN
        RAISE EXCEPTION 'Submitted purchase order commercial terms are immutable'
            USING ERRCODE = '55000';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.protect_submitted_purchase_order_line_core()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    parent_status varchar(30);
    old_core jsonb;
    new_core jsonb;
BEGIN
    SELECT status INTO parent_status
      FROM doms.purchase_orders
     WHERE id = CASE WHEN TG_OP = 'DELETE' THEN OLD.purchase_order_id ELSE NEW.purchase_order_id END;
    IF parent_status IN ('DRAFT','PENDING_APPROVAL') THEN
        RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
    END IF;
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'Lines of a submitted purchase order cannot be deleted'
            USING ERRCODE = '55000';
    END IF;
    old_core := to_jsonb(OLD)
        - 'acknowledged_quantity' - 'shipped_quantity' - 'received_quantity'
        - 'cancelled_quantity' - 'status' - 'row_version' - 'updated_at';
    new_core := to_jsonb(NEW)
        - 'acknowledged_quantity' - 'shipped_quantity' - 'received_quantity'
        - 'cancelled_quantity' - 'status' - 'row_version' - 'updated_at';
    IF old_core IS DISTINCT FROM new_core THEN
        RAISE EXCEPTION 'Submitted purchase order line commercial terms are immutable'
            USING ERRCODE = '55000';
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_validate_purchase_order_finalization ON doms.purchase_orders;
CREATE TRIGGER trg_validate_purchase_order_finalization
    BEFORE INSERT OR UPDATE OF status, subtotal_amount, charge_amount, tax_amount, total_amount
    ON doms.purchase_orders
    FOR EACH ROW EXECUTE PROCEDURE doms.validate_purchase_order_finalization();

DROP TRIGGER IF EXISTS trg_protect_submitted_purchase_order_core ON doms.purchase_orders;
CREATE TRIGGER trg_protect_submitted_purchase_order_core
    BEFORE UPDATE OR DELETE ON doms.purchase_orders
    FOR EACH ROW EXECUTE PROCEDURE doms.protect_submitted_purchase_order_core();

DROP TRIGGER IF EXISTS trg_protect_submitted_purchase_order_line_core ON doms.purchase_order_lines;
CREATE TRIGGER trg_protect_submitted_purchase_order_line_core
    BEFORE UPDATE OR DELETE ON doms.purchase_order_lines
    FOR EACH ROW EXECUTE PROCEDURE doms.protect_submitted_purchase_order_line_core();

CREATE OR REPLACE FUNCTION doms.validate_procurement_lineage()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    document_purchase_order_id uuid;
    line_purchase_order_id uuid;
    line_sales_order_id uuid;
    linked_sales_order_id uuid;
    line_item_id uuid;
    sales_item_id uuid;
    purchase_item_id uuid;
    linked_sales_order_line_id uuid;
    cumulative_quantity numeric(24,8);
    shipped_total numeric(24,8);
BEGIN
    IF TG_TABLE_NAME = 'supplier_shipment_lines' THEN
        SELECT purchase_order_id INTO document_purchase_order_id
          FROM doms.supplier_shipments WHERE id = NEW.supplier_shipment_id;
        SELECT purchase_order_id, item_id
          INTO line_purchase_order_id, line_item_id
          FROM doms.purchase_order_lines
         WHERE id = NEW.purchase_order_line_id
         FOR UPDATE;
        IF document_purchase_order_id IS DISTINCT FROM line_purchase_order_id
           OR line_item_id IS DISTINCT FROM NEW.item_id THEN
            RAISE EXCEPTION 'Supplier shipment line must match its purchase order and item'
                USING ERRCODE = '23514';
        END IF;
        SELECT COALESCE(sum(shipped_quantity), 0)
          INTO cumulative_quantity
          FROM doms.supplier_shipment_lines
         WHERE purchase_order_line_id = NEW.purchase_order_line_id
           AND id <> NEW.id;
        IF cumulative_quantity + NEW.shipped_quantity > (
            SELECT ordered_quantity - cancelled_quantity
            FROM doms.purchase_order_lines WHERE id = NEW.purchase_order_line_id
        ) THEN
            RAISE EXCEPTION 'Supplier shipments exceed the open purchase order quantity'
                USING ERRCODE = '23514';
        END IF;
    ELSIF TG_TABLE_NAME = 'supplier_receipt_lines' THEN
        SELECT purchase_order_id INTO document_purchase_order_id
          FROM doms.supplier_receipts WHERE id = NEW.supplier_receipt_id;
        SELECT purchase_order_id, item_id
          INTO line_purchase_order_id, line_item_id
          FROM doms.purchase_order_lines
         WHERE id = NEW.purchase_order_line_id
         FOR UPDATE;
        IF document_purchase_order_id IS DISTINCT FROM line_purchase_order_id
           OR line_item_id IS DISTINCT FROM NEW.item_id THEN
            RAISE EXCEPTION 'Supplier receipt line must match its purchase order and item'
                USING ERRCODE = '23514';
        END IF;
        IF NEW.supplier_shipment_line_id IS NOT NULL AND NOT EXISTS (
            SELECT 1 FROM doms.supplier_shipment_lines shipment_line
            WHERE shipment_line.id = NEW.supplier_shipment_line_id
              AND shipment_line.purchase_order_line_id = NEW.purchase_order_line_id
              AND shipment_line.item_id = NEW.item_id
        ) THEN
            RAISE EXCEPTION 'Supplier receipt line shipment evidence does not match the purchase order line'
                USING ERRCODE = '23514';
        END IF;
        SELECT COALESCE(sum(received_quantity), 0)
          INTO cumulative_quantity
          FROM doms.supplier_receipt_lines
         WHERE purchase_order_line_id = NEW.purchase_order_line_id
           AND id <> NEW.id;
        SELECT COALESCE(sum(shipped_quantity), 0)
          INTO shipped_total
          FROM doms.supplier_shipment_lines
         WHERE purchase_order_line_id = NEW.purchase_order_line_id;
        IF cumulative_quantity + NEW.received_quantity > shipped_total THEN
            RAISE EXCEPTION 'Supplier receipts exceed evidenced shipped quantity'
                USING ERRCODE = '23514';
        END IF;
    ELSIF TG_TABLE_NAME = 'dropship_order_lines' THEN
        SELECT sales_order_id, purchase_order_id
          INTO line_sales_order_id, document_purchase_order_id
          FROM doms.dropship_orders WHERE id = NEW.dropship_order_id;
        SELECT sales_order_id, item_id
          INTO linked_sales_order_id, sales_item_id
          FROM doms.sales_order_lines WHERE id = NEW.sales_order_line_id;
        SELECT purchase_order_id, related_sales_order_line_id, item_id
          INTO line_purchase_order_id, linked_sales_order_line_id, purchase_item_id
          FROM doms.purchase_order_lines WHERE id = NEW.purchase_order_line_id;
        IF line_sales_order_id IS DISTINCT FROM linked_sales_order_id
           OR document_purchase_order_id IS DISTINCT FROM line_purchase_order_id
           OR linked_sales_order_line_id IS DISTINCT FROM NEW.sales_order_line_id
           OR sales_item_id IS DISTINCT FROM NEW.item_id
           OR purchase_item_id IS DISTINCT FROM NEW.item_id THEN
            RAISE EXCEPTION 'Drop-ship line must join the same sales order, purchase order, and item'
                USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_validate_supplier_shipment_line ON doms.supplier_shipment_lines;
CREATE TRIGGER trg_validate_supplier_shipment_line
    BEFORE INSERT OR UPDATE ON doms.supplier_shipment_lines
    FOR EACH ROW EXECUTE PROCEDURE doms.validate_procurement_lineage();

DROP TRIGGER IF EXISTS trg_validate_supplier_receipt_line ON doms.supplier_receipt_lines;
CREATE TRIGGER trg_validate_supplier_receipt_line
    BEFORE INSERT OR UPDATE ON doms.supplier_receipt_lines
    FOR EACH ROW EXECUTE PROCEDURE doms.validate_procurement_lineage();

DROP TRIGGER IF EXISTS trg_validate_dropship_order_line ON doms.dropship_order_lines;
CREATE TRIGGER trg_validate_dropship_order_line
    BEFORE INSERT OR UPDATE ON doms.dropship_order_lines
    FOR EACH ROW EXECUTE PROCEDURE doms.validate_procurement_lineage();

CREATE TABLE IF NOT EXISTS doms.invoices (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    invoice_no varchar(120) NOT NULL,
    invoice_type varchar(20) NOT NULL DEFAULT 'CUSTOMER',
    sales_order_id uuid REFERENCES doms.sales_orders(id) ON DELETE RESTRICT,
    purchase_order_id uuid REFERENCES doms.purchase_orders(id) ON DELETE RESTRICT,
    customer_id uuid REFERENCES doms.customers(id) ON DELETE RESTRICT,
    supplier_profile_id uuid REFERENCES doms.supplier_profiles(id) ON DELETE RESTRICT,
    organization_id uuid NOT NULL REFERENCES doms.organizations(id) ON DELETE RESTRICT,
    billing_address_snapshot_id uuid REFERENCES doms.order_address_snapshots(id) ON DELETE RESTRICT,
    currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    invoice_date date NOT NULL,
    due_date date,
    subtotal_amount numeric(20,6) NOT NULL DEFAULT 0,
    discount_amount numeric(20,6) NOT NULL DEFAULT 0,
    charge_amount numeric(20,6) NOT NULL DEFAULT 0,
    tax_amount numeric(20,6) NOT NULL DEFAULT 0,
    total_amount numeric(20,6) NOT NULL DEFAULT 0,
    paid_amount numeric(20,6) NOT NULL DEFAULT 0,
    credited_amount numeric(20,6) NOT NULL DEFAULT 0,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    external_invoice_id varchar(200),
    posted_by uuid REFERENCES doms.users(id),
    posted_at timestamptz,
    voided_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, invoice_no),
    CONSTRAINT ck_invoices_type CHECK (invoice_type IN ('CUSTOMER','SUPPLIER','PROFORMA','DEBIT_NOTE')),
    CONSTRAINT ck_invoices_party CHECK (
        (invoice_type IN ('CUSTOMER','PROFORMA','DEBIT_NOTE') AND customer_id IS NOT NULL) OR
        (invoice_type = 'SUPPLIER' AND supplier_profile_id IS NOT NULL)
    ),
    CONSTRAINT ck_invoices_amounts CHECK (
        subtotal_amount >= 0 AND discount_amount >= 0 AND charge_amount >= 0 AND
        tax_amount >= 0 AND total_amount >= 0 AND paid_amount >= 0 AND credited_amount >= 0 AND
        total_amount = subtotal_amount - discount_amount + charge_amount + tax_amount AND
        paid_amount + credited_amount <= total_amount
    ),
    CONSTRAINT ck_invoices_status CHECK (status IN ('DRAFT','PENDING','POSTED','PARTIALLY_PAID','PAID','PARTIALLY_CREDITED','CREDITED','VOID')),
    CONSTRAINT ck_invoices_posted CHECK (status NOT IN ('POSTED','PARTIALLY_PAID','PAID','PARTIALLY_CREDITED','CREDITED') OR (posted_by IS NOT NULL AND posted_at IS NOT NULL)),
    CONSTRAINT ck_invoices_voided CHECK (status <> 'VOID' OR voided_at IS NOT NULL),
    CONSTRAINT ck_invoices_dates CHECK (due_date IS NULL OR due_date >= invoice_date)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_invoices_external
    ON doms.invoices (tenant_id, organization_id, external_invoice_id)
    WHERE external_invoice_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS doms.invoice_lines (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    invoice_id uuid NOT NULL REFERENCES doms.invoices(id) ON DELETE RESTRICT,
    line_no integer NOT NULL,
    line_type varchar(20) NOT NULL DEFAULT 'ITEM',
    sales_order_line_id uuid REFERENCES doms.sales_order_lines(id) ON DELETE RESTRICT,
    purchase_order_line_id uuid REFERENCES doms.purchase_order_lines(id) ON DELETE RESTRICT,
    item_id uuid REFERENCES doms.items(id) ON DELETE RESTRICT,
    description varchar(500) NOT NULL,
    uom_code varchar(20) REFERENCES doms.units_of_measure(uom_code),
    quantity numeric(24,8) NOT NULL DEFAULT 1,
    unit_amount numeric(20,6) NOT NULL DEFAULT 0,
    discount_amount numeric(20,6) NOT NULL DEFAULT 0,
    charge_amount numeric(20,6) NOT NULL DEFAULT 0,
    tax_amount numeric(20,6) NOT NULL DEFAULT 0,
    line_total_amount numeric(20,6) NOT NULL DEFAULT 0,
    revenue_account_code varchar(80),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, invoice_id, line_no),
    CONSTRAINT ck_invoice_lines_number CHECK (line_no > 0),
    CONSTRAINT ck_invoice_lines_type CHECK (line_type IN ('ITEM','SHIPPING','SERVICE','FEE','DISCOUNT','TAX','OTHER')),
    CONSTRAINT ck_invoice_lines_values CHECK (
        quantity > 0 AND unit_amount >= 0 AND discount_amount >= 0 AND
        charge_amount >= 0 AND tax_amount >= 0 AND line_total_amount >= 0 AND
        line_total_amount = quantity * unit_amount - discount_amount + charge_amount + tax_amount
    )
);

CREATE TABLE IF NOT EXISTS doms.invoice_taxes (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    invoice_id uuid NOT NULL REFERENCES doms.invoices(id) ON DELETE RESTRICT,
    invoice_line_id uuid REFERENCES doms.invoice_lines(id) ON DELETE RESTRICT,
    tax_code_id uuid REFERENCES doms.tax_codes(id),
    jurisdiction_code varchar(100),
    taxable_amount numeric(20,6) NOT NULL,
    tax_rate numeric(12,8) NOT NULL,
    tax_amount numeric(20,6) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_invoice_taxes_values CHECK (
        taxable_amount >= 0 AND tax_rate >= 0 AND tax_amount >= 0
    )
);

CREATE TABLE IF NOT EXISTS doms.invoice_adjustments (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    invoice_id uuid NOT NULL REFERENCES doms.invoices(id) ON DELETE RESTRICT,
    invoice_line_id uuid REFERENCES doms.invoice_lines(id) ON DELETE RESTRICT,
    adjustment_type varchar(30) NOT NULL,
    direction varchar(10) NOT NULL,
    amount numeric(20,6) NOT NULL,
    reason_code varchar(100),
    description text,
    approved_by uuid REFERENCES doms.users(id),
    approved_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_invoice_adjustments_type CHECK (adjustment_type IN ('ROUNDING','PRICE_CORRECTION','GOODWILL','LATE_FEE','WRITE_OFF','OTHER')),
    CONSTRAINT ck_invoice_adjustments_direction CHECK (direction IN ('DEBIT','CREDIT')),
    CONSTRAINT ck_invoice_adjustments_amount CHECK (amount > 0)
);

CREATE TABLE IF NOT EXISTS doms.invoice_events (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    invoice_id uuid NOT NULL REFERENCES doms.invoices(id) ON DELETE RESTRICT,
    event_type varchar(50) NOT NULL,
    from_status varchar(20),
    to_status varchar(20),
    actor_user_id uuid REFERENCES doms.users(id),
    correlation_id uuid,
    reason_code varchar(100),
    payload_masked jsonb NOT NULL DEFAULT '{}'::jsonb,
    occurred_at timestamptz NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_invoice_events_secrets CHECK (NOT doms.jsonb_contains_forbidden_secret_key(payload_masked))
);

CREATE TABLE IF NOT EXISTS doms.credit_memos (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    credit_memo_no varchar(120) NOT NULL,
    invoice_id uuid NOT NULL REFERENCES doms.invoices(id) ON DELETE RESTRICT,
    sales_order_id uuid REFERENCES doms.sales_orders(id) ON DELETE RESTRICT,
    customer_id uuid REFERENCES doms.customers(id) ON DELETE RESTRICT,
    currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    memo_date date NOT NULL,
    reason_code varchar(100),
    subtotal_amount numeric(20,6) NOT NULL DEFAULT 0,
    tax_amount numeric(20,6) NOT NULL DEFAULT 0,
    total_amount numeric(20,6) NOT NULL DEFAULT 0,
    applied_amount numeric(20,6) NOT NULL DEFAULT 0,
    refunded_amount numeric(20,6) NOT NULL DEFAULT 0,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    posted_by uuid REFERENCES doms.users(id),
    posted_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, credit_memo_no),
    CONSTRAINT ck_credit_memos_amounts CHECK (
        subtotal_amount >= 0 AND tax_amount >= 0 AND total_amount = subtotal_amount + tax_amount AND
        applied_amount >= 0 AND refunded_amount >= 0 AND applied_amount + refunded_amount <= total_amount
    ),
    CONSTRAINT ck_credit_memos_status CHECK (status IN ('DRAFT','PENDING','POSTED','PARTIALLY_APPLIED','APPLIED','VOID')),
    CONSTRAINT ck_credit_memos_posted CHECK (status NOT IN ('POSTED','PARTIALLY_APPLIED','APPLIED') OR (posted_by IS NOT NULL AND posted_at IS NOT NULL))
);

CREATE TABLE IF NOT EXISTS doms.credit_memo_lines (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    credit_memo_id uuid NOT NULL REFERENCES doms.credit_memos(id) ON DELETE RESTRICT,
    invoice_line_id uuid REFERENCES doms.invoice_lines(id) ON DELETE RESTRICT,
    sales_order_line_id uuid REFERENCES doms.sales_order_lines(id) ON DELETE RESTRICT,
    line_no integer NOT NULL,
    item_id uuid REFERENCES doms.items(id) ON DELETE RESTRICT,
    description varchar(500) NOT NULL,
    quantity numeric(24,8) NOT NULL DEFAULT 1,
    unit_amount numeric(20,6) NOT NULL DEFAULT 0,
    tax_amount numeric(20,6) NOT NULL DEFAULT 0,
    line_total_amount numeric(20,6) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, credit_memo_id, line_no),
    CONSTRAINT ck_credit_memo_lines_number CHECK (line_no > 0),
    CONSTRAINT ck_credit_memo_lines_values CHECK (
        quantity > 0 AND unit_amount >= 0 AND tax_amount >= 0 AND
        line_total_amount = quantity * unit_amount + tax_amount
    )
);

CREATE TABLE IF NOT EXISTS doms.credit_memo_applications (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    credit_memo_id uuid NOT NULL REFERENCES doms.credit_memos(id) ON DELETE RESTRICT,
    target_invoice_id uuid REFERENCES doms.invoices(id) ON DELETE RESTRICT,
    payment_refund_id uuid REFERENCES doms.payment_refunds(id) ON DELETE RESTRICT,
    application_type varchar(20) NOT NULL,
    amount numeric(20,6) NOT NULL,
    idempotency_key varchar(200) NOT NULL,
    applied_by uuid REFERENCES doms.users(id),
    applied_at timestamptz NOT NULL DEFAULT now(),
    reversed_at timestamptz,
    reversal_reason text,
    UNIQUE (tenant_id, credit_memo_id, idempotency_key),
    CONSTRAINT ck_credit_memo_applications_target CHECK (
        (application_type = 'INVOICE' AND target_invoice_id IS NOT NULL AND payment_refund_id IS NULL) OR
        (application_type = 'REFUND' AND target_invoice_id IS NULL AND payment_refund_id IS NOT NULL) OR
        (application_type = 'STORE_CREDIT' AND target_invoice_id IS NULL AND payment_refund_id IS NULL)
    ),
    CONSTRAINT ck_credit_memo_applications_amount CHECK (amount > 0),
    CONSTRAINT ck_credit_memo_applications_reversal CHECK (reversed_at IS NULL OR reversed_at >= applied_at)
);

CREATE TABLE IF NOT EXISTS doms.credit_memo_events (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    credit_memo_id uuid NOT NULL REFERENCES doms.credit_memos(id) ON DELETE RESTRICT,
    event_type varchar(50) NOT NULL,
    from_status varchar(20),
    to_status varchar(20),
    actor_user_id uuid REFERENCES doms.users(id),
    reason_code varchar(100),
    occurred_at timestamptz NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS doms.channel_fee_rules (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    channel_account_id uuid NOT NULL REFERENCES doms.channel_accounts(id) ON DELETE RESTRICT,
    fee_code varchar(80) NOT NULL,
    fee_name varchar(200) NOT NULL,
    fee_type varchar(30) NOT NULL,
    calculation_method varchar(20) NOT NULL,
    fixed_amount numeric(20,6),
    percentage_rate numeric(12,8),
    currency_code char(3) REFERENCES doms.currencies(currency_code),
    applies_to varchar(30) NOT NULL DEFAULT 'ORDER_TOTAL',
    valid_from timestamptz NOT NULL,
    valid_to timestamptz,
    priority integer NOT NULL DEFAULT 100,
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, channel_account_id, fee_code, valid_from),
    CONSTRAINT ck_channel_fee_rules_type CHECK (fee_type IN ('COMMISSION','PAYMENT','LISTING','FULFILLMENT','SHIPPING','RETURN','ADVERTISING','OTHER')),
    CONSTRAINT ck_channel_fee_rules_method CHECK (calculation_method IN ('FIXED','PERCENT','TIERED','EXTERNAL')),
    CONSTRAINT ck_channel_fee_rules_value CHECK (
        (calculation_method = 'FIXED' AND fixed_amount IS NOT NULL AND fixed_amount >= 0 AND currency_code IS NOT NULL) OR
        (calculation_method = 'PERCENT' AND percentage_rate IS NOT NULL AND percentage_rate >= 0) OR
        calculation_method IN ('TIERED','EXTERNAL')
    ),
    CONSTRAINT ck_channel_fee_rules_dates CHECK (valid_to IS NULL OR valid_to > valid_from),
    CONSTRAINT ck_channel_fee_rules_priority CHECK (priority >= 0)
);

CREATE TABLE IF NOT EXISTS doms.channel_fee_events (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    channel_fee_rule_id uuid REFERENCES doms.channel_fee_rules(id) ON DELETE RESTRICT,
    channel_account_id uuid NOT NULL REFERENCES doms.channel_accounts(id) ON DELETE RESTRICT,
    sales_order_id uuid REFERENCES doms.sales_orders(id) ON DELETE RESTRICT,
    payment_capture_id uuid REFERENCES doms.payment_captures(id) ON DELETE RESTRICT,
    payment_refund_id uuid REFERENCES doms.payment_refunds(id) ON DELETE RESTRICT,
    fee_event_type varchar(30) NOT NULL,
    source_reference varchar(200),
    currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    basis_amount numeric(20,6) NOT NULL DEFAULT 0,
    fee_amount numeric(20,6) NOT NULL,
    tax_amount numeric(20,6) NOT NULL DEFAULT 0,
    occurred_at timestamptz NOT NULL,
    external_event_id varchar(200),
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_channel_fee_events_type CHECK (fee_event_type IN ('ACCRUAL','REVERSAL','ADJUSTMENT')),
    CONSTRAINT ck_channel_fee_events_amounts CHECK (basis_amount >= 0 AND fee_amount >= 0 AND tax_amount >= 0)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_channel_fee_events_external
    ON doms.channel_fee_events (tenant_id, channel_account_id, external_event_id)
    WHERE external_event_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS doms.channel_settlement_periods (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    channel_account_id uuid NOT NULL REFERENCES doms.channel_accounts(id) ON DELETE RESTRICT,
    period_start date NOT NULL,
    period_end date NOT NULL,
    cutoff_at timestamptz,
    status varchar(20) NOT NULL DEFAULT 'OPEN',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, channel_account_id, period_start, period_end),
    CONSTRAINT ck_channel_settlement_periods_dates CHECK (period_end >= period_start),
    CONSTRAINT ck_channel_settlement_periods_status CHECK (status IN ('OPEN','CLOSED','PROCESSING','SETTLED','REOPENED'))
);

CREATE TABLE IF NOT EXISTS doms.channel_settlements (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    settlement_no varchar(120) NOT NULL,
    channel_settlement_period_id uuid NOT NULL REFERENCES doms.channel_settlement_periods(id) ON DELETE RESTRICT,
    channel_account_id uuid NOT NULL REFERENCES doms.channel_accounts(id) ON DELETE RESTRICT,
    currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    gross_sales_amount numeric(20,6) NOT NULL DEFAULT 0,
    refund_amount numeric(20,6) NOT NULL DEFAULT 0,
    fee_amount numeric(20,6) NOT NULL DEFAULT 0,
    tax_amount numeric(20,6) NOT NULL DEFAULT 0,
    adjustment_amount numeric(20,6) NOT NULL DEFAULT 0,
    net_settlement_amount numeric(20,6) NOT NULL DEFAULT 0,
    external_settlement_id varchar(200),
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    expected_payout_at timestamptz,
    settled_at timestamptz,
    approved_by uuid REFERENCES doms.users(id),
    approved_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, settlement_no),
    CONSTRAINT ck_channel_settlements_amounts CHECK (
        gross_sales_amount >= 0 AND refund_amount >= 0 AND fee_amount >= 0 AND tax_amount >= 0 AND
        net_settlement_amount = gross_sales_amount - refund_amount - fee_amount - tax_amount + adjustment_amount
    ),
    CONSTRAINT ck_channel_settlements_status CHECK (status IN ('DRAFT','RECONCILING','PENDING_APPROVAL','APPROVED','PAID','DISPUTED','VOID')),
    CONSTRAINT ck_channel_settlements_approval CHECK (status NOT IN ('APPROVED','PAID') OR (approved_by IS NOT NULL AND approved_at IS NOT NULL)),
    CONSTRAINT ck_channel_settlements_paid CHECK (status <> 'PAID' OR settled_at IS NOT NULL)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_channel_settlements_external
    ON doms.channel_settlements (tenant_id, channel_account_id, external_settlement_id)
    WHERE external_settlement_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS doms.channel_settlement_lines (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    channel_settlement_id uuid NOT NULL REFERENCES doms.channel_settlements(id) ON DELETE RESTRICT,
    line_no integer NOT NULL,
    line_type varchar(30) NOT NULL,
    direction varchar(10) NOT NULL DEFAULT 'CREDIT',
    sales_order_id uuid REFERENCES doms.sales_orders(id) ON DELETE RESTRICT,
    payment_capture_id uuid REFERENCES doms.payment_captures(id) ON DELETE RESTRICT,
    payment_refund_id uuid REFERENCES doms.payment_refunds(id) ON DELETE RESTRICT,
    channel_fee_event_id uuid REFERENCES doms.channel_fee_events(id) ON DELETE RESTRICT,
    external_line_id varchar(200),
    gross_amount numeric(20,6) NOT NULL DEFAULT 0,
    fee_amount numeric(20,6) NOT NULL DEFAULT 0,
    tax_amount numeric(20,6) NOT NULL DEFAULT 0,
    net_amount numeric(20,6) NOT NULL DEFAULT 0,
    occurred_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, channel_settlement_id, line_no),
    CONSTRAINT ck_channel_settlement_lines_number CHECK (line_no > 0),
    CONSTRAINT ck_channel_settlement_lines_type CHECK (line_type IN ('SALE','REFUND','FEE','ADJUSTMENT','CHARGEBACK','RESERVE','RELEASE')),
    CONSTRAINT ck_channel_settlement_lines_direction CHECK (direction IN ('CREDIT','DEBIT')),
    CONSTRAINT ck_channel_settlement_lines_amounts CHECK (
        gross_amount >= 0 AND fee_amount >= 0 AND tax_amount >= 0 AND
        net_amount = gross_amount - fee_amount - tax_amount
    )
);

CREATE TABLE IF NOT EXISTS doms.payouts (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    payout_no varchar(120) NOT NULL,
    payout_type varchar(30) NOT NULL,
    payee_partner_id uuid NOT NULL REFERENCES doms.business_partners(id) ON DELETE RESTRICT,
    partner_bank_account_id uuid REFERENCES doms.partner_bank_accounts(id) ON DELETE RESTRICT,
    currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    payout_amount numeric(20,6) NOT NULL,
    allocated_amount numeric(20,6) NOT NULL DEFAULT 0,
    external_payout_id varchar(200),
    status varchar(20) NOT NULL DEFAULT 'PENDING',
    requested_at timestamptz NOT NULL DEFAULT now(),
    processed_at timestamptz,
    failed_at timestamptz,
    failure_code varchar(100),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, payout_no),
    CONSTRAINT ck_payouts_type CHECK (payout_type IN ('CHANNEL','SUPPLIER','MARKETPLACE_SELLER','CUSTOMER_REFUND','OTHER')),
    CONSTRAINT ck_payouts_amounts CHECK (payout_amount > 0 AND allocated_amount >= 0 AND allocated_amount <= payout_amount),
    CONSTRAINT ck_payouts_status CHECK (status IN ('PENDING','APPROVED','PROCESSING','PAID','FAILED','CANCELLED','REVERSED')),
    CONSTRAINT ck_payouts_processed CHECK (status NOT IN ('PAID','REVERSED') OR processed_at IS NOT NULL),
    CONSTRAINT ck_payouts_failed CHECK (status <> 'FAILED' OR (failed_at IS NOT NULL AND failure_code IS NOT NULL))
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_payouts_external
    ON doms.payouts (tenant_id, external_payout_id)
    WHERE external_payout_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS doms.payout_allocations (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    payout_id uuid NOT NULL REFERENCES doms.payouts(id) ON DELETE RESTRICT,
    channel_settlement_id uuid REFERENCES doms.channel_settlements(id) ON DELETE RESTRICT,
    invoice_id uuid REFERENCES doms.invoices(id) ON DELETE RESTRICT,
    credit_memo_id uuid REFERENCES doms.credit_memos(id) ON DELETE RESTRICT,
    allocation_type varchar(30) NOT NULL,
    amount numeric(20,6) NOT NULL,
    idempotency_key varchar(200) NOT NULL,
    allocated_at timestamptz NOT NULL DEFAULT now(),
    reversed_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, payout_id, idempotency_key),
    CONSTRAINT ck_payout_allocations_target CHECK (num_nonnulls(channel_settlement_id, invoice_id, credit_memo_id) = 1),
    CONSTRAINT ck_payout_allocations_type CHECK (allocation_type IN ('SETTLEMENT','INVOICE','CREDIT_MEMO','ADJUSTMENT')),
    CONSTRAINT ck_payout_allocations_amount CHECK (amount > 0),
    CONSTRAINT ck_payout_allocations_reversal CHECK (reversed_at IS NULL OR reversed_at >= allocated_at)
);

CREATE TABLE IF NOT EXISTS doms.accounting_periods (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    organization_id uuid NOT NULL REFERENCES doms.organizations(id) ON DELETE RESTRICT,
    fiscal_year integer NOT NULL,
    period_no smallint NOT NULL,
    period_name varchar(100) NOT NULL,
    start_date date NOT NULL,
    end_date date NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'OPEN',
    closed_by uuid REFERENCES doms.users(id),
    closed_at timestamptz,
    reopened_by uuid REFERENCES doms.users(id),
    reopened_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, organization_id, fiscal_year, period_no),
    CONSTRAINT ck_accounting_periods_year CHECK (fiscal_year BETWEEN 1900 AND 9999),
    CONSTRAINT ck_accounting_periods_number CHECK (period_no BETWEEN 1 AND 99),
    CONSTRAINT ck_accounting_periods_dates CHECK (end_date >= start_date),
    CONSTRAINT ck_accounting_periods_status CHECK (status IN ('FUTURE','OPEN','SOFT_CLOSED','CLOSED','REOPENED')),
    CONSTRAINT ck_accounting_periods_close CHECK (status <> 'CLOSED' OR (closed_by IS NOT NULL AND closed_at IS NOT NULL)),
    CONSTRAINT ck_accounting_periods_reopen CHECK (status <> 'REOPENED' OR (reopened_by IS NOT NULL AND reopened_at IS NOT NULL))
);

CREATE TABLE IF NOT EXISTS doms.gl_accounts (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    organization_id uuid NOT NULL REFERENCES doms.organizations(id) ON DELETE RESTRICT,
    account_code varchar(80) NOT NULL,
    account_name varchar(200) NOT NULL,
    account_type varchar(30) NOT NULL,
    normal_balance varchar(10) NOT NULL,
    parent_account_id uuid REFERENCES doms.gl_accounts(id),
    currency_code char(3) REFERENCES doms.currencies(currency_code),
    control_account boolean NOT NULL DEFAULT false,
    allow_manual_posting boolean NOT NULL DEFAULT true,
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    UNIQUE (tenant_id, organization_id, account_code),
    CONSTRAINT ck_gl_accounts_type CHECK (account_type IN ('ASSET','LIABILITY','EQUITY','REVENUE','EXPENSE','CONTRA_ASSET','CONTRA_REVENUE','MEMO')),
    CONSTRAINT ck_gl_accounts_balance CHECK (normal_balance IN ('DEBIT','CREDIT')),
    CONSTRAINT ck_gl_accounts_parent CHECK (parent_account_id IS NULL OR parent_account_id <> id),
    CONSTRAINT ck_gl_accounts_status CHECK (status IN ('ACTIVE','BLOCKED','CLOSED'))
);

CREATE TABLE IF NOT EXISTS doms.journal_batches (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    batch_no varchar(120) NOT NULL,
    organization_id uuid NOT NULL REFERENCES doms.organizations(id) ON DELETE RESTRICT,
    accounting_period_id uuid NOT NULL REFERENCES doms.accounting_periods(id) ON DELETE RESTRICT,
    source_module varchar(50) NOT NULL,
    source_reference varchar(200),
    description text,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    approved_by uuid REFERENCES doms.users(id),
    approved_at timestamptz,
    posted_by uuid REFERENCES doms.users(id),
    posted_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, batch_no),
    CONSTRAINT ck_journal_batches_status CHECK (status IN ('DRAFT','READY','APPROVED','POSTED','VOID')),
    CONSTRAINT ck_journal_batches_approval CHECK (status NOT IN ('APPROVED','POSTED') OR (approved_by IS NOT NULL AND approved_at IS NOT NULL)),
    CONSTRAINT ck_journal_batches_posted CHECK (status <> 'POSTED' OR (posted_by IS NOT NULL AND posted_at IS NOT NULL))
);

CREATE TABLE IF NOT EXISTS doms.journal_entries (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    journal_batch_id uuid NOT NULL REFERENCES doms.journal_batches(id) ON DELETE RESTRICT,
    entry_no integer NOT NULL,
    entry_date date NOT NULL,
    currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    exchange_rate numeric(24,12) NOT NULL DEFAULT 1,
    reference_type varchar(50),
    reference_id uuid,
    description text,
    reversal_of_entry_id uuid REFERENCES doms.journal_entries(id) ON DELETE RESTRICT,
    total_debit numeric(20,6) NOT NULL DEFAULT 0,
    total_credit numeric(20,6) NOT NULL DEFAULT 0,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    posted_by uuid REFERENCES doms.users(id),
    posted_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, journal_batch_id, entry_no),
    UNIQUE (tenant_id, reversal_of_entry_id),
    CONSTRAINT ck_journal_entries_number CHECK (entry_no > 0),
    CONSTRAINT ck_journal_entries_rate CHECK (exchange_rate > 0),
    CONSTRAINT ck_journal_entries_totals CHECK (total_debit >= 0 AND total_credit >= 0),
    CONSTRAINT ck_journal_entries_status CHECK (status IN ('DRAFT','READY','POSTED','VOID')),
    CONSTRAINT ck_journal_entries_posted CHECK (status <> 'POSTED' OR (posted_by IS NOT NULL AND posted_at IS NOT NULL)),
    CONSTRAINT ck_journal_entries_reversal CHECK (reversal_of_entry_id IS NULL OR reversal_of_entry_id <> id)
);

CREATE TABLE IF NOT EXISTS doms.journal_lines (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    journal_entry_id uuid NOT NULL REFERENCES doms.journal_entries(id) ON DELETE RESTRICT,
    line_no integer NOT NULL,
    gl_account_id uuid NOT NULL REFERENCES doms.gl_accounts(id) ON DELETE RESTRICT,
    description text,
    debit_amount numeric(20,6) NOT NULL DEFAULT 0,
    credit_amount numeric(20,6) NOT NULL DEFAULT 0,
    currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    exchange_rate numeric(24,12) NOT NULL DEFAULT 1,
    source_type varchar(50),
    source_id uuid,
    dimensions jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, journal_entry_id, line_no),
    CONSTRAINT ck_journal_lines_number CHECK (line_no > 0),
    CONSTRAINT ck_journal_lines_side CHECK (
        (debit_amount > 0 AND credit_amount = 0) OR
        (credit_amount > 0 AND debit_amount = 0)
    ),
    CONSTRAINT ck_journal_lines_rate CHECK (exchange_rate > 0),
    CONSTRAINT ck_journal_lines_dimensions_secrets CHECK (NOT doms.jsonb_contains_forbidden_secret_key(dimensions))
);

CREATE TABLE IF NOT EXISTS doms.accounting_exports (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    export_no varchar(120) NOT NULL,
    organization_id uuid NOT NULL REFERENCES doms.organizations(id) ON DELETE RESTRICT,
    accounting_period_id uuid REFERENCES doms.accounting_periods(id) ON DELETE RESTRICT,
    external_system_id uuid NOT NULL REFERENCES doms.external_systems(id) ON DELETE RESTRICT,
    export_format varchar(30) NOT NULL,
    object_uri text,
    object_sha256 char(64),
    object_size_bytes bigint,
    status varchar(20) NOT NULL DEFAULT 'QUEUED',
    requested_by uuid REFERENCES doms.users(id),
    requested_at timestamptz NOT NULL DEFAULT now(),
    completed_at timestamptz,
    failed_at timestamptz,
    failure_code varchar(100),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, export_no),
    CONSTRAINT ck_accounting_exports_format CHECK (export_format IN ('CSV','JSON','XML','FIXED_WIDTH','API')),
    CONSTRAINT ck_accounting_exports_object CHECK (
        (object_uri IS NULL AND object_sha256 IS NULL AND object_size_bytes IS NULL) OR
        (object_uri IS NOT NULL AND object_sha256 ~ '^[0-9A-Fa-f]{64}$' AND object_size_bytes >= 0)
    ),
    CONSTRAINT ck_accounting_exports_status CHECK (status IN ('QUEUED','RUNNING','COMPLETED','FAILED','CANCELLED')),
    CONSTRAINT ck_accounting_exports_completed CHECK (status <> 'COMPLETED' OR completed_at IS NOT NULL),
    CONSTRAINT ck_accounting_exports_failed CHECK (status <> 'FAILED' OR (failed_at IS NOT NULL AND failure_code IS NOT NULL))
);

CREATE TABLE IF NOT EXISTS doms.accounting_export_lines (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    accounting_export_id uuid NOT NULL REFERENCES doms.accounting_exports(id) ON DELETE RESTRICT,
    journal_entry_id uuid NOT NULL REFERENCES doms.journal_entries(id) ON DELETE RESTRICT,
    sequence_no integer NOT NULL,
    external_reference varchar(200),
    export_status varchar(20) NOT NULL DEFAULT 'PENDING',
    error_code varchar(100),
    error_message_masked text,
    exported_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, accounting_export_id, sequence_no),
    UNIQUE (tenant_id, accounting_export_id, journal_entry_id),
    CONSTRAINT ck_accounting_export_lines_sequence CHECK (sequence_no > 0),
    CONSTRAINT ck_accounting_export_lines_status CHECK (export_status IN ('PENDING','EXPORTED','ACCEPTED','REJECTED','RETRY')),
    CONSTRAINT ck_accounting_export_lines_error CHECK (export_status <> 'REJECTED' OR error_code IS NOT NULL)
);

CREATE OR REPLACE FUNCTION doms.validate_invoice_finalization()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    line_count bigint;
    line_subtotal numeric(20,6);
    line_discount numeric(20,6);
    line_charge numeric(20,6);
    line_tax numeric(20,6);
    line_total numeric(20,6);
    debit_adjustment numeric(20,6);
    credit_adjustment numeric(20,6);
    detail_tax numeric(20,6);
BEGIN
    IF NEW.status NOT IN ('POSTED','PARTIALLY_PAID','PAID','PARTIALLY_CREDITED','CREDITED') THEN
        RETURN NEW;
    END IF;

    SELECT count(*),
           COALESCE(sum(quantity * unit_amount), 0),
           COALESCE(sum(discount_amount), 0),
           COALESCE(sum(charge_amount), 0),
           COALESCE(sum(tax_amount), 0),
           COALESCE(sum(line_total_amount), 0)
      INTO line_count, line_subtotal, line_discount, line_charge, line_tax, line_total
      FROM doms.invoice_lines
     WHERE tenant_id = NEW.tenant_id AND invoice_id = NEW.id;

    SELECT COALESCE(sum(amount) FILTER (WHERE direction = 'DEBIT'), 0),
           COALESCE(sum(amount) FILTER (WHERE direction = 'CREDIT'), 0)
      INTO debit_adjustment, credit_adjustment
      FROM doms.invoice_adjustments
     WHERE tenant_id = NEW.tenant_id AND invoice_id = NEW.id;

    SELECT COALESCE(sum(tax_amount), 0)
      INTO detail_tax
      FROM doms.invoice_taxes
     WHERE tenant_id = NEW.tenant_id AND invoice_id = NEW.id;

    IF line_count = 0 THEN
        RAISE EXCEPTION 'An invoice cannot be posted without invoice lines'
            USING ERRCODE = '23514';
    END IF;
    IF NEW.subtotal_amount IS DISTINCT FROM line_subtotal
       OR NEW.discount_amount IS DISTINCT FROM line_discount + credit_adjustment
       OR NEW.charge_amount IS DISTINCT FROM line_charge + debit_adjustment
       OR NEW.tax_amount IS DISTINCT FROM line_tax
       OR NEW.total_amount IS DISTINCT FROM line_total + debit_adjustment - credit_adjustment THEN
        RAISE EXCEPTION 'Invoice header totals do not reconcile to lines and adjustments'
            USING ERRCODE = '23514';
    END IF;
    IF EXISTS (
        SELECT 1 FROM doms.invoice_taxes
        WHERE tenant_id = NEW.tenant_id AND invoice_id = NEW.id
    ) AND detail_tax IS DISTINCT FROM NEW.tax_amount THEN
        RAISE EXCEPTION 'Invoice tax detail does not reconcile to the invoice tax total'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.protect_posted_invoice_core()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    old_core jsonb;
    new_core jsonb;
BEGIN
    IF OLD.posted_at IS NULL THEN
        RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
    END IF;
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'Posted invoices cannot be deleted; issue a credit memo or reversal'
            USING ERRCODE = '55000';
    END IF;
    old_core := to_jsonb(OLD) - 'status' - 'paid_amount' - 'credited_amount' - 'row_version' - 'updated_at';
    new_core := to_jsonb(NEW) - 'status' - 'paid_amount' - 'credited_amount' - 'row_version' - 'updated_at';
    IF old_core IS DISTINCT FROM new_core THEN
        RAISE EXCEPTION 'Posted invoice core is immutable; use a credit memo or reversal'
            USING ERRCODE = '55000';
    END IF;
    IF NEW.status IN ('DRAFT','PENDING','VOID') THEN
        RAISE EXCEPTION 'Posted invoice status cannot regress to %', NEW.status
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_validate_invoice_finalization ON doms.invoices;
CREATE TRIGGER trg_validate_invoice_finalization
    BEFORE INSERT OR UPDATE OF status, subtotal_amount, discount_amount, charge_amount,
        tax_amount, total_amount ON doms.invoices
    FOR EACH ROW EXECUTE PROCEDURE doms.validate_invoice_finalization();

DROP TRIGGER IF EXISTS trg_protect_posted_invoice_core ON doms.invoices;
CREATE TRIGGER trg_protect_posted_invoice_core
    BEFORE UPDATE OR DELETE ON doms.invoices
    FOR EACH ROW EXECUTE PROCEDURE doms.protect_posted_invoice_core();

CREATE OR REPLACE FUNCTION doms.validate_credit_memo_finalization()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    line_count bigint;
    line_subtotal numeric(20,6);
    line_tax numeric(20,6);
    line_total numeric(20,6);
    invoice_currency char(3);
    invoice_total numeric(20,6);
BEGIN
    IF NEW.status NOT IN ('POSTED','PARTIALLY_APPLIED','APPLIED') THEN
        RETURN NEW;
    END IF;
    SELECT currency_code, total_amount
      INTO invoice_currency, invoice_total
      FROM doms.invoices
     WHERE id = NEW.invoice_id AND tenant_id = NEW.tenant_id
     FOR UPDATE;
    IF NOT FOUND OR invoice_currency IS DISTINCT FROM NEW.currency_code THEN
        RAISE EXCEPTION 'Credit memo invoice is unavailable or has a different currency'
            USING ERRCODE = '23503';
    END IF;
    SELECT count(*), COALESCE(sum(quantity * unit_amount), 0),
           COALESCE(sum(tax_amount), 0), COALESCE(sum(line_total_amount), 0)
      INTO line_count, line_subtotal, line_tax, line_total
      FROM doms.credit_memo_lines
     WHERE tenant_id = NEW.tenant_id AND credit_memo_id = NEW.id;
    IF line_count = 0 OR NEW.subtotal_amount IS DISTINCT FROM line_subtotal
       OR NEW.tax_amount IS DISTINCT FROM line_tax
       OR NEW.total_amount IS DISTINCT FROM line_total
       OR NEW.total_amount > invoice_total THEN
        RAISE EXCEPTION 'Credit memo totals do not reconcile or exceed the source invoice'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.protect_posted_credit_memo_core()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    old_core jsonb;
    new_core jsonb;
BEGIN
    IF OLD.posted_at IS NULL THEN
        RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
    END IF;
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'Posted credit memos cannot be deleted'
            USING ERRCODE = '55000';
    END IF;
    old_core := to_jsonb(OLD) - 'status' - 'applied_amount' - 'refunded_amount' - 'row_version' - 'updated_at';
    new_core := to_jsonb(NEW) - 'status' - 'applied_amount' - 'refunded_amount' - 'row_version' - 'updated_at';
    IF old_core IS DISTINCT FROM new_core OR NEW.status IN ('DRAFT','PENDING','VOID') THEN
        RAISE EXCEPTION 'Posted credit memo core is immutable'
            USING ERRCODE = '55000';
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_validate_credit_memo_finalization ON doms.credit_memos;
CREATE TRIGGER trg_validate_credit_memo_finalization
    BEFORE INSERT OR UPDATE OF status, subtotal_amount, tax_amount, total_amount ON doms.credit_memos
    FOR EACH ROW EXECUTE PROCEDURE doms.validate_credit_memo_finalization();

DROP TRIGGER IF EXISTS trg_protect_posted_credit_memo_core ON doms.credit_memos;
CREATE TRIGGER trg_protect_posted_credit_memo_core
    BEFORE UPDATE OR DELETE ON doms.credit_memos
    FOR EACH ROW EXECUTE PROCEDURE doms.protect_posted_credit_memo_core();

CREATE OR REPLACE FUNCTION doms.project_credit_memo_applications()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, doms, pg_temp
AS $function$
DECLARE
    target_id uuid;
    memo_total numeric(20,6);
    applied_total numeric(20,6);
    refunded_total numeric(20,6);
BEGIN
    target_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.credit_memo_id ELSE NEW.credit_memo_id END;
    IF TG_OP = 'UPDATE' AND OLD.credit_memo_id IS DISTINCT FROM NEW.credit_memo_id THEN
        RAISE EXCEPTION 'credit_memo_id is immutable on applications'
            USING ERRCODE = '23514';
    END IF;
    SELECT total_amount INTO memo_total
      FROM doms.credit_memos
     WHERE id = target_id
     FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Credit memo is unavailable' USING ERRCODE = '23503';
    END IF;
    SELECT COALESCE(sum(amount) FILTER (
               WHERE reversed_at IS NULL AND application_type IN ('INVOICE','STORE_CREDIT')
           ), 0),
           COALESCE(sum(amount) FILTER (
               WHERE reversed_at IS NULL AND application_type = 'REFUND'
           ), 0)
      INTO applied_total, refunded_total
      FROM doms.credit_memo_applications
     WHERE credit_memo_id = target_id;
    IF applied_total + refunded_total > memo_total THEN
        RAISE EXCEPTION 'Credit memo applications exceed the posted credit amount'
            USING ERRCODE = '23514';
    END IF;
    UPDATE doms.credit_memos
       SET applied_amount = applied_total,
           refunded_amount = refunded_total,
           status = CASE
               WHEN applied_total + refunded_total = memo_total THEN 'APPLIED'
               WHEN applied_total + refunded_total > 0 THEN 'PARTIALLY_APPLIED'
               ELSE status
           END
     WHERE id = target_id;
    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$function$;

REVOKE ALL ON FUNCTION doms.project_credit_memo_applications() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_project_credit_memo_applications ON doms.credit_memo_applications;
CREATE TRIGGER trg_project_credit_memo_applications
    AFTER INSERT OR UPDATE OR DELETE ON doms.credit_memo_applications
    FOR EACH ROW EXECUTE PROCEDURE doms.project_credit_memo_applications();

CREATE OR REPLACE FUNCTION doms.validate_channel_settlement_finalization()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    signed_line_total numeric(20,6);
    line_count bigint;
BEGIN
    IF NEW.status NOT IN ('APPROVED','PAID') THEN
        RETURN NEW;
    END IF;
    SELECT count(*), COALESCE(sum(
               CASE WHEN direction = 'CREDIT' THEN net_amount ELSE -net_amount END
           ), 0)
      INTO line_count, signed_line_total
      FROM doms.channel_settlement_lines
     WHERE tenant_id = NEW.tenant_id AND channel_settlement_id = NEW.id;
    IF line_count = 0 OR signed_line_total IS DISTINCT FROM NEW.net_settlement_amount THEN
        RAISE EXCEPTION 'Channel settlement line total does not equal the net settlement amount'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_validate_channel_settlement_finalization ON doms.channel_settlements;
CREATE TRIGGER trg_validate_channel_settlement_finalization
    BEFORE INSERT OR UPDATE OF status, net_settlement_amount ON doms.channel_settlements
    FOR EACH ROW EXECUTE PROCEDURE doms.validate_channel_settlement_finalization();

CREATE OR REPLACE FUNCTION doms.project_payout_allocations()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, doms, pg_temp
AS $function$
DECLARE
    target_id uuid;
    payout_total numeric(20,6);
    allocation_total numeric(20,6);
BEGIN
    target_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.payout_id ELSE NEW.payout_id END;
    IF TG_OP = 'UPDATE' AND OLD.payout_id IS DISTINCT FROM NEW.payout_id THEN
        RAISE EXCEPTION 'payout_id is immutable on payout allocations'
            USING ERRCODE = '23514';
    END IF;
    SELECT payout_amount INTO payout_total
      FROM doms.payouts
     WHERE id = target_id
     FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Payout is unavailable' USING ERRCODE = '23503';
    END IF;
    SELECT COALESCE(sum(amount) FILTER (WHERE reversed_at IS NULL), 0)
      INTO allocation_total
      FROM doms.payout_allocations
     WHERE payout_id = target_id;
    IF allocation_total > payout_total THEN
        RAISE EXCEPTION 'Payout allocations exceed the payout amount'
            USING ERRCODE = '23514';
    END IF;
    UPDATE doms.payouts
       SET allocated_amount = allocation_total
     WHERE id = target_id;
    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$function$;

REVOKE ALL ON FUNCTION doms.project_payout_allocations() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_project_payout_allocations ON doms.payout_allocations;
CREATE TRIGGER trg_project_payout_allocations
    AFTER INSERT OR UPDATE OR DELETE ON doms.payout_allocations
    FOR EACH ROW EXECUTE PROCEDURE doms.project_payout_allocations();

CREATE OR REPLACE FUNCTION doms.validate_journal_entry_posting()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    entry_count bigint;
    debit_total numeric(20,6);
    credit_total numeric(20,6);
    currency_count integer;
    period_status varchar(20);
    batch_status varchar(20);
    period_start date;
    period_end date;
    original_status varchar(20);
    original_currency char(3);
    original_debit numeric(20,6);
    original_credit numeric(20,6);
BEGIN
    IF NEW.status <> 'POSTED' THEN
        RETURN NEW;
    END IF;
    SELECT period.status, batch.status, period.start_date, period.end_date
      INTO period_status, batch_status, period_start, period_end
      FROM doms.journal_batches batch
      JOIN doms.accounting_periods period ON period.id = batch.accounting_period_id
     WHERE batch.id = NEW.journal_batch_id
       AND batch.tenant_id = NEW.tenant_id
     FOR UPDATE OF period;
    IF period_status NOT IN ('OPEN','REOPENED')
       OR batch_status NOT IN ('APPROVED','POSTED')
       OR NEW.entry_date NOT BETWEEN period_start AND period_end THEN
        RAISE EXCEPTION 'Journal posting requires an approved batch and open matching accounting period'
            USING ERRCODE = '23514';
    END IF;
    SELECT count(*), COALESCE(sum(debit_amount), 0),
           COALESCE(sum(credit_amount), 0), count(DISTINCT currency_code)
      INTO entry_count, debit_total, credit_total, currency_count
      FROM doms.journal_lines
     WHERE tenant_id = NEW.tenant_id AND journal_entry_id = NEW.id;
    IF entry_count < 2 OR debit_total <= 0 OR debit_total IS DISTINCT FROM credit_total
       OR currency_count <> 1 OR EXISTS (
           SELECT 1 FROM doms.journal_lines
           WHERE tenant_id = NEW.tenant_id AND journal_entry_id = NEW.id
             AND currency_code IS DISTINCT FROM NEW.currency_code
       ) THEN
        RAISE EXCEPTION 'Posted journal entry must have balanced lines in one currency'
            USING ERRCODE = '23514';
    END IF;
    IF NEW.reversal_of_entry_id IS NOT NULL THEN
        SELECT status, currency_code, total_debit, total_credit
          INTO original_status, original_currency, original_debit, original_credit
          FROM doms.journal_entries
         WHERE id = NEW.reversal_of_entry_id AND tenant_id = NEW.tenant_id
         FOR UPDATE;
        IF original_status <> 'POSTED' OR original_currency IS DISTINCT FROM NEW.currency_code
           OR original_debit IS DISTINCT FROM credit_total
           OR original_credit IS DISTINCT FROM debit_total THEN
            RAISE EXCEPTION 'Journal reversal must offset one posted entry in the same currency'
                USING ERRCODE = '23514';
        END IF;
        IF EXISTS (
            WITH original_lines AS (
                SELECT gl_account_id, sum(debit_amount) AS debit_amount,
                       sum(credit_amount) AS credit_amount
                FROM doms.journal_lines
                WHERE journal_entry_id = NEW.reversal_of_entry_id
                GROUP BY gl_account_id
            ), reversal_lines AS (
                SELECT gl_account_id, sum(debit_amount) AS debit_amount,
                       sum(credit_amount) AS credit_amount
                FROM doms.journal_lines
                WHERE journal_entry_id = NEW.id
                GROUP BY gl_account_id
            )
            SELECT 1
            FROM original_lines original
            FULL JOIN reversal_lines reversal USING (gl_account_id)
            WHERE COALESCE(original.debit_amount, 0) IS DISTINCT FROM COALESCE(reversal.credit_amount, 0)
               OR COALESCE(original.credit_amount, 0) IS DISTINCT FROM COALESCE(reversal.debit_amount, 0)
        ) THEN
            RAISE EXCEPTION 'Journal reversal lines must exactly reverse each source GL account'
                USING ERRCODE = '23514';
        END IF;
    END IF;
    NEW.total_debit := debit_total;
    NEW.total_credit := credit_total;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.protect_posted_journal_entry()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    IF OLD.status = 'POSTED' THEN
        RAISE EXCEPTION 'Posted journal entries are immutable; create a reversing entry'
            USING ERRCODE = '55000';
    END IF;
    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.protect_posted_journal_lines()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    target_entry_id uuid;
    entry_status varchar(20);
    entry_currency char(3);
    batch_organization_id uuid;
    batch_source_module varchar(50);
    account_organization_id uuid;
    account_status varchar(20);
    account_allows_manual boolean;
BEGIN
    target_entry_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.journal_entry_id ELSE NEW.journal_entry_id END;
    SELECT entry.status, entry.currency_code, batch.organization_id, batch.source_module
      INTO entry_status, entry_currency, batch_organization_id, batch_source_module
      FROM doms.journal_entries entry
      JOIN doms.journal_batches batch ON batch.id = entry.journal_batch_id
     WHERE entry.id = target_entry_id;
    IF entry_status = 'POSTED' THEN
        RAISE EXCEPTION 'Lines of a posted journal entry are immutable'
            USING ERRCODE = '55000';
    END IF;
    IF TG_OP <> 'DELETE' THEN
        SELECT organization_id, status, allow_manual_posting
          INTO account_organization_id, account_status, account_allows_manual
          FROM doms.gl_accounts
         WHERE id = NEW.gl_account_id;
        IF account_organization_id IS DISTINCT FROM batch_organization_id
           OR account_status <> 'ACTIVE'
           OR (NOT account_allows_manual AND batch_source_module = 'MANUAL')
           OR NEW.currency_code IS DISTINCT FROM entry_currency THEN
            RAISE EXCEPTION 'Journal line account/currency is not eligible for this batch'
                USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$function$;

DROP TRIGGER IF EXISTS trg_validate_journal_entry_posting ON doms.journal_entries;
CREATE TRIGGER trg_validate_journal_entry_posting
    BEFORE INSERT OR UPDATE OF status ON doms.journal_entries
    FOR EACH ROW EXECUTE PROCEDURE doms.validate_journal_entry_posting();

DROP TRIGGER IF EXISTS trg_protect_posted_journal_entry ON doms.journal_entries;
CREATE TRIGGER trg_protect_posted_journal_entry
    BEFORE UPDATE OR DELETE ON doms.journal_entries
    FOR EACH ROW EXECUTE PROCEDURE doms.protect_posted_journal_entry();

DROP TRIGGER IF EXISTS trg_protect_posted_journal_lines ON doms.journal_lines;
CREATE TRIGGER trg_protect_posted_journal_lines
    BEFORE INSERT OR UPDATE OR DELETE ON doms.journal_lines
    FOR EACH ROW EXECUTE PROCEDURE doms.protect_posted_journal_lines();
