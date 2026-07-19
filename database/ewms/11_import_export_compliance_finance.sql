-- EWMS enterprise import/export management extensions.
-- PostgreSQL 11 compatible. Applied after the shared warehouse, trade, customs,
-- bonded, and settlement foundations and before workflow/RLS finalization.

-- -----------------------------------------------------------------------------
-- Trade case, commercial order, import, and export aggregates
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS ewms.trade_cases (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    case_no varchar(120) NOT NULL,
    direction varchar(20) NOT NULL,
    case_type varchar(40) NOT NULL DEFAULT 'STANDARD',
    owner_partner_id uuid NOT NULL REFERENCES ewms.business_partners(id),
    customer_partner_id uuid REFERENCES ewms.business_partners(id),
    organization_id uuid REFERENCES ewms.organizations(id),
    organization_unit_id uuid REFERENCES ewms.organization_units(id),
    transport_mode_code varchar(20) REFERENCES ewms.transport_modes(mode_code),
    incoterm_code char(3) REFERENCES ewms.incoterms(incoterm_code),
    incoterm_named_place varchar(300),
    origin_country_code char(2) REFERENCES ewms.countries(country_code),
    destination_country_code char(2) REFERENCES ewms.countries(country_code),
    origin_port_code varchar(10) REFERENCES ewms.ports(port_code),
    destination_port_code varchar(10) REFERENCES ewms.ports(port_code),
    contract_currency_code char(3) REFERENCES ewms.currencies(currency_code),
    priority smallint NOT NULL DEFAULT 5,
    assigned_user_id uuid REFERENCES ewms.users(id),
    planned_start_at timestamptz,
    planned_complete_at timestamptz,
    actual_start_at timestamptz,
    actual_complete_at timestamptz,
    status varchar(30) NOT NULL DEFAULT 'DRAFT',
    hold_reason text,
    source_system_id uuid REFERENCES ewms.external_systems(id),
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_by uuid REFERENCES ewms.users(id),
    updated_by uuid REFERENCES ewms.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    closed_at timestamptz,
    UNIQUE (tenant_id, case_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_trade_case_direction CHECK (
        direction IN ('IMPORT','EXPORT','TRANSIT','CROSS_TRADE','RETURN')
    ),
    CONSTRAINT ck_ewms_trade_case_priority CHECK (priority BETWEEN 1 AND 9),
    CONSTRAINT ck_ewms_trade_case_status CHECK (status IN (
        'DRAFT','OPEN','IN_PROGRESS','ON_HOLD','COMPLETED','CANCELLED','ARCHIVED'
    )),
    CONSTRAINT ck_ewms_trade_case_plan_dates CHECK (
        planned_complete_at IS NULL OR planned_start_at IS NULL OR planned_complete_at >= planned_start_at
    ),
    CONSTRAINT ck_ewms_trade_case_actual_dates CHECK (
        actual_complete_at IS NULL OR actual_start_at IS NULL OR actual_complete_at >= actual_start_at
    )
);

CREATE TABLE IF NOT EXISTS ewms.trade_case_parties (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    trade_case_id uuid NOT NULL REFERENCES ewms.trade_cases(id) ON DELETE CASCADE,
    party_role varchar(40) NOT NULL,
    partner_id uuid REFERENCES ewms.business_partners(id),
    current_snapshot_no integer NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (trade_case_id, party_role),
    CONSTRAINT ck_ewms_trade_case_party_role CHECK (party_role IN (
        'OWNER','CUSTOMER','SELLER','BUYER','SUPPLIER','IMPORTER','EXPORTER','SHIPPER',
        'CONSIGNEE','NOTIFY','MANUFACTURER','END_USER','CARRIER','FORWARDER',
        'CUSTOMS_BROKER','DECLARANT','BANK','INSURER','OTHER'
    )),
    CONSTRAINT ck_ewms_trade_case_party_snapshot CHECK (current_snapshot_no > 0)
);

CREATE TABLE IF NOT EXISTS ewms.trade_case_party_snapshots (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    trade_case_party_id uuid NOT NULL REFERENCES ewms.trade_case_parties(id) ON DELETE RESTRICT,
    snapshot_no integer NOT NULL,
    party_name varchar(300) NOT NULL,
    business_identifier varchar(150),
    personal_identifier_encrypted text,
    personal_identifier_hash char(64),
    personal_identifier_masked varchar(100),
    address_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
    contact_snapshot_masked jsonb NOT NULL DEFAULT '{}'::jsonb,
    captured_by uuid REFERENCES ewms.users(id),
    captured_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (trade_case_party_id, snapshot_no),
    CONSTRAINT ck_ewms_trade_case_party_snapshot_no CHECK (snapshot_no > 0),
    CONSTRAINT ck_ewms_trade_case_party_person_hash CHECK (
        personal_identifier_hash IS NULL OR personal_identifier_hash ~ '^[0-9A-Fa-f]{64}$'
    ),
    CONSTRAINT ck_ewms_trade_case_party_masked_json CHECK (
        NOT ewms.jsonb_contains_forbidden_secret_key(contact_snapshot_masked)
    )
);

CREATE TABLE IF NOT EXISTS ewms.trade_case_references (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    trade_case_id uuid NOT NULL REFERENCES ewms.trade_cases(id) ON DELETE CASCADE,
    reference_type varchar(80) NOT NULL,
    reference_value varchar(300) NOT NULL,
    issuing_partner_id uuid REFERENCES ewms.business_partners(id),
    issued_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (trade_case_id, reference_type, reference_value)
);

CREATE TABLE IF NOT EXISTS ewms.trade_case_items (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    trade_case_id uuid NOT NULL REFERENCES ewms.trade_cases(id) ON DELETE CASCADE,
    line_no integer NOT NULL,
    item_id uuid REFERENCES ewms.items(id),
    owner_item_code varchar(120),
    goods_description varchar(1000) NOT NULL,
    hs_code varchar(20),
    hs_country_code char(2),
    hs_nomenclature_version varchar(20),
    country_of_origin char(2) REFERENCES ewms.countries(country_code),
    quantity numeric(24,8) NOT NULL,
    uom_code varchar(20) NOT NULL REFERENCES ewms.units_of_measure(uom_code),
    unit_price numeric(24,8),
    currency_code char(3) REFERENCES ewms.currencies(currency_code),
    package_count numeric(20,4),
    package_type_code varchar(50),
    net_weight numeric(24,8),
    gross_weight numeric(24,8),
    weight_uom_code varchar(20) REFERENCES ewms.units_of_measure(uom_code),
    volume_value numeric(24,9),
    volume_uom_code varchar(20) REFERENCES ewms.units_of_measure(uom_code),
    dangerous_goods boolean NOT NULL DEFAULT false,
    temperature_controlled boolean NOT NULL DEFAULT false,
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (trade_case_id, line_no),
    UNIQUE (tenant_id, id),
    FOREIGN KEY (hs_country_code, hs_nomenclature_version, hs_code)
        REFERENCES ewms.hs_codes(country_code, nomenclature_version, hs_code),
    CONSTRAINT ck_ewms_trade_case_item_line CHECK (line_no > 0),
    CONSTRAINT ck_ewms_trade_case_item_quantity CHECK (quantity > 0),
    CONSTRAINT ck_ewms_trade_case_item_amount CHECK (unit_price IS NULL OR unit_price >= 0),
    CONSTRAINT ck_ewms_trade_case_item_package CHECK (package_count IS NULL OR package_count >= 0),
    CONSTRAINT ck_ewms_trade_case_item_weight CHECK (
        (net_weight IS NULL OR net_weight >= 0) AND
        (gross_weight IS NULL OR gross_weight >= 0) AND
        (gross_weight IS NULL OR net_weight IS NULL OR gross_weight >= net_weight)
    ),
    CONSTRAINT ck_ewms_trade_case_item_volume CHECK (volume_value IS NULL OR volume_value >= 0)
);

CREATE TABLE IF NOT EXISTS ewms.trade_case_relations (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    parent_case_id uuid NOT NULL REFERENCES ewms.trade_cases(id) ON DELETE RESTRICT,
    child_case_id uuid NOT NULL REFERENCES ewms.trade_cases(id) ON DELETE RESTRICT,
    relation_type varchar(30) NOT NULL,
    reason text,
    created_by uuid REFERENCES ewms.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (parent_case_id, child_case_id, relation_type),
    CONSTRAINT ck_ewms_trade_case_relation_self CHECK (parent_case_id <> child_case_id),
    CONSTRAINT ck_ewms_trade_case_relation_type CHECK (
        relation_type IN ('SPLIT','CONSOLIDATION','RETURN','REPLACEMENT','AMENDMENT','RELATED')
    )
);

CREATE TABLE IF NOT EXISTS ewms.trade_case_events (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    trade_case_id uuid NOT NULL REFERENCES ewms.trade_cases(id) ON DELETE RESTRICT,
    sequence_no bigint NOT NULL,
    event_type varchar(80) NOT NULL,
    from_status varchar(30),
    to_status varchar(30),
    reason_code varchar(80),
    occurred_at timestamptz NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT now(),
    recorded_by uuid REFERENCES ewms.users(id),
    source_system_id uuid REFERENCES ewms.external_systems(id),
    external_event_id varchar(300),
    correlation_id varchar(100),
    detail_masked jsonb NOT NULL DEFAULT '{}'::jsonb,
    UNIQUE (trade_case_id, sequence_no),
    UNIQUE (source_system_id, external_event_id),
    CONSTRAINT ck_ewms_trade_case_event_sequence CHECK (sequence_no > 0),
    CONSTRAINT ck_ewms_trade_case_event_masked_json CHECK (
        NOT ewms.jsonb_contains_forbidden_secret_key(detail_masked)
    )
);

CREATE TABLE IF NOT EXISTS ewms.trade_orders (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    order_no varchar(120) NOT NULL,
    order_type varchar(20) NOT NULL,
    owner_partner_id uuid NOT NULL REFERENCES ewms.business_partners(id),
    seller_partner_id uuid REFERENCES ewms.business_partners(id),
    buyer_partner_id uuid REFERENCES ewms.business_partners(id),
    ordering_organization_id uuid REFERENCES ewms.organizations(id),
    current_version_id uuid,
    current_version_no integer,
    status varchar(30) NOT NULL DEFAULT 'DRAFT',
    row_version bigint NOT NULL DEFAULT 1,
    created_by uuid REFERENCES ewms.users(id),
    updated_by uuid REFERENCES ewms.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    closed_at timestamptz,
    UNIQUE (tenant_id, order_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_trade_order_type CHECK (order_type IN ('PURCHASE','SALES','TRANSFER','RETURN')),
    CONSTRAINT ck_ewms_trade_order_status CHECK (status IN (
        'DRAFT','APPROVAL_PENDING','CONFIRMED','PARTIALLY_ALLOCATED','ALLOCATED',
        'PARTIALLY_FULFILLED','FULFILLED','CANCELLED','CLOSED'
    )),
    CONSTRAINT ck_ewms_trade_order_current_version CHECK (
        (current_version_id IS NULL AND current_version_no IS NULL) OR
        (current_version_id IS NOT NULL AND current_version_no > 0)
    )
);

CREATE TABLE IF NOT EXISTS ewms.trade_order_versions (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    trade_order_id uuid NOT NULL REFERENCES ewms.trade_orders(id) ON DELETE RESTRICT,
    version_no integer NOT NULL,
    revision_reason text,
    order_date date NOT NULL,
    contract_no varchar(150),
    buyer_reference varchar(150),
    seller_reference varchar(150),
    currency_code char(3) NOT NULL REFERENCES ewms.currencies(currency_code),
    incoterm_code char(3) REFERENCES ewms.incoterms(incoterm_code),
    incoterm_named_place varchar(300),
    payment_term_id uuid REFERENCES ewms.payment_terms(id),
    planned_ship_date date,
    planned_delivery_date date,
    total_goods_amount numeric(24,4) NOT NULL DEFAULT 0,
    total_charge_amount numeric(24,4) NOT NULL DEFAULT 0,
    total_discount_amount numeric(24,4) NOT NULL DEFAULT 0,
    total_order_amount numeric(24,4) NOT NULL DEFAULT 0,
    version_status varchar(20) NOT NULL DEFAULT 'DRAFT',
    sealed_at timestamptz,
    sealed_by uuid REFERENCES ewms.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (trade_order_id, version_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_trade_order_version_no CHECK (version_no > 0),
    CONSTRAINT ck_ewms_trade_order_version_dates CHECK (
        planned_delivery_date IS NULL OR planned_ship_date IS NULL OR planned_delivery_date >= planned_ship_date
    ),
    CONSTRAINT ck_ewms_trade_order_version_amounts CHECK (
        total_goods_amount >= 0 AND total_charge_amount >= 0 AND total_discount_amount >= 0 AND
        total_order_amount = total_goods_amount + total_charge_amount - total_discount_amount
    ),
    CONSTRAINT ck_ewms_trade_order_version_status CHECK (
        version_status IN ('DRAFT','SEALED','SUPERSEDED','CANCELLED')
    ),
    CONSTRAINT ck_ewms_trade_order_version_seal CHECK (
        (version_status = 'DRAFT' AND sealed_at IS NULL AND sealed_by IS NULL) OR
        (version_status <> 'DRAFT' AND sealed_at IS NOT NULL AND sealed_by IS NOT NULL)
    )
);

DO $block$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'ewms.trade_orders'::regclass
          AND conname = 'fk_ewms_trade_order_current_version'
    ) THEN
        ALTER TABLE ewms.trade_orders
            ADD CONSTRAINT fk_ewms_trade_order_current_version
            FOREIGN KEY (tenant_id, current_version_id)
            REFERENCES ewms.trade_order_versions(tenant_id, id) DEFERRABLE INITIALLY DEFERRED;
    END IF;
END;
$block$;

CREATE TABLE IF NOT EXISTS ewms.trade_order_lines (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    trade_order_version_id uuid NOT NULL REFERENCES ewms.trade_order_versions(id) ON DELETE CASCADE,
    line_no integer NOT NULL,
    item_id uuid REFERENCES ewms.items(id),
    goods_description varchar(1000) NOT NULL,
    hs_code varchar(20),
    country_of_origin char(2) REFERENCES ewms.countries(country_code),
    ordered_quantity numeric(24,8) NOT NULL,
    uom_code varchar(20) NOT NULL REFERENCES ewms.units_of_measure(uom_code),
    unit_price numeric(24,8) NOT NULL,
    line_amount numeric(24,4) NOT NULL,
    requested_ship_date date,
    requested_delivery_date date,
    status varchar(20) NOT NULL DEFAULT 'OPEN',
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (trade_order_version_id, line_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_trade_order_line_no CHECK (line_no > 0),
    CONSTRAINT ck_ewms_trade_order_line_qty CHECK (ordered_quantity > 0),
    CONSTRAINT ck_ewms_trade_order_line_amount CHECK (unit_price >= 0 AND line_amount >= 0),
    CONSTRAINT ck_ewms_trade_order_line_dates CHECK (
        requested_delivery_date IS NULL OR requested_ship_date IS NULL OR requested_delivery_date >= requested_ship_date
    ),
    CONSTRAINT ck_ewms_trade_order_line_status CHECK (
        status IN ('OPEN','PARTIALLY_ALLOCATED','ALLOCATED','FULFILLED','CANCELLED','CLOSED')
    )
);

CREATE TABLE IF NOT EXISTS ewms.trade_order_case_allocations (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    trade_order_line_id uuid NOT NULL REFERENCES ewms.trade_order_lines(id) ON DELETE RESTRICT,
    trade_case_item_id uuid NOT NULL REFERENCES ewms.trade_case_items(id) ON DELETE RESTRICT,
    allocated_quantity numeric(24,8) NOT NULL,
    uom_code varchar(20) NOT NULL REFERENCES ewms.units_of_measure(uom_code),
    allocation_status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    allocated_by uuid REFERENCES ewms.users(id),
    allocated_at timestamptz NOT NULL DEFAULT now(),
    reversed_at timestamptz,
    reversal_reason text,
    UNIQUE (trade_order_line_id, trade_case_item_id),
    CONSTRAINT ck_ewms_trade_order_case_alloc_qty CHECK (allocated_quantity > 0),
    CONSTRAINT ck_ewms_trade_order_case_alloc_status CHECK (
        allocation_status IN ('ACTIVE','REVERSED','CANCELLED')
    )
);

CREATE TABLE IF NOT EXISTS ewms.trade_case_shipments (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    trade_case_id uuid NOT NULL REFERENCES ewms.trade_cases(id) ON DELETE RESTRICT,
    trade_shipment_id uuid NOT NULL REFERENCES ewms.trade_shipments(id) ON DELETE RESTRICT,
    allocation_role varchar(20) NOT NULL DEFAULT 'PRIMARY',
    allocated_at timestamptz NOT NULL DEFAULT now(),
    released_at timestamptz,
    UNIQUE (trade_case_id, trade_shipment_id),
    CONSTRAINT ck_ewms_trade_case_shipment_role CHECK (
        allocation_role IN ('PRIMARY','CONSOLIDATED','SPLIT','RETURN','RELATED')
    )
);

CREATE TABLE IF NOT EXISTS ewms.trade_shipment_items (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    trade_shipment_id uuid NOT NULL REFERENCES ewms.trade_shipments(id) ON DELETE CASCADE,
    line_no integer NOT NULL,
    trade_case_item_id uuid REFERENCES ewms.trade_case_items(id) ON DELETE RESTRICT,
    item_id uuid REFERENCES ewms.items(id),
    goods_description varchar(1000) NOT NULL,
    quantity numeric(24,8) NOT NULL,
    uom_code varchar(20) NOT NULL REFERENCES ewms.units_of_measure(uom_code),
    hs_code varchar(20),
    country_of_origin char(2) REFERENCES ewms.countries(country_code),
    package_count numeric(20,4),
    net_weight numeric(24,8),
    gross_weight numeric(24,8),
    weight_uom_code varchar(20) REFERENCES ewms.units_of_measure(uom_code),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (trade_shipment_id, line_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_trade_shipment_item_line CHECK (line_no > 0),
    CONSTRAINT ck_ewms_trade_shipment_item_qty CHECK (quantity > 0),
    CONSTRAINT ck_ewms_trade_shipment_item_package CHECK (package_count IS NULL OR package_count >= 0),
    CONSTRAINT ck_ewms_trade_shipment_item_weight CHECK (
        (net_weight IS NULL OR net_weight >= 0) AND
        (gross_weight IS NULL OR gross_weight >= 0) AND
        (gross_weight IS NULL OR net_weight IS NULL OR gross_weight >= net_weight)
    )
);

CREATE TABLE IF NOT EXISTS ewms.trade_case_document_requirements (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    trade_case_id uuid NOT NULL REFERENCES ewms.trade_cases(id) ON DELETE CASCADE,
    requirement_code varchar(80) NOT NULL,
    document_type varchar(80) NOT NULL,
    is_mandatory boolean NOT NULL DEFAULT true,
    due_at timestamptz,
    status varchar(20) NOT NULL DEFAULT 'OPEN',
    waived_by uuid REFERENCES ewms.users(id),
    waived_at timestamptz,
    waiver_reason text,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (trade_case_id, requirement_code),
    CONSTRAINT ck_ewms_trade_case_doc_req_status CHECK (
        status IN ('OPEN','SUBMITTED','ACCEPTED','REJECTED','EXPIRED','WAIVED')
    ),
    CONSTRAINT ck_ewms_trade_case_doc_req_waiver CHECK (
        (status = 'WAIVED' AND waived_by IS NOT NULL AND waived_at IS NOT NULL AND waiver_reason IS NOT NULL) OR
        (status <> 'WAIVED' AND waived_at IS NULL)
    )
);

CREATE TABLE IF NOT EXISTS ewms.trade_case_document_evidence (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    requirement_id uuid NOT NULL REFERENCES ewms.trade_case_document_requirements(id) ON DELETE RESTRICT,
    trade_document_id uuid REFERENCES ewms.trade_documents(id) ON DELETE RESTRICT,
    file_id uuid REFERENCES ewms.files(id) ON DELETE RESTRICT,
    submitted_by uuid REFERENCES ewms.users(id),
    submitted_at timestamptz NOT NULL DEFAULT now(),
    verified_by uuid REFERENCES ewms.users(id),
    verified_at timestamptz,
    verification_status varchar(20) NOT NULL DEFAULT 'SUBMITTED',
    remarks text,
    CONSTRAINT ck_ewms_trade_case_doc_evidence_source CHECK (
        num_nonnulls(trade_document_id, file_id) = 1
    ),
    CONSTRAINT ck_ewms_trade_case_doc_evidence_status CHECK (
        verification_status IN ('SUBMITTED','ACCEPTED','REJECTED','SUPERSEDED')
    ),
    CONSTRAINT ck_ewms_trade_case_doc_evidence_verify CHECK (
        (verification_status = 'SUBMITTED' AND verified_at IS NULL AND verified_by IS NULL) OR
        (verification_status <> 'SUBMITTED' AND verified_at IS NOT NULL AND verified_by IS NOT NULL)
    )
);

CREATE TABLE IF NOT EXISTS ewms.import_cases (
    trade_case_id uuid PRIMARY KEY REFERENCES ewms.trade_cases(id) ON DELETE RESTRICT,
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    importer_partner_id uuid NOT NULL REFERENCES ewms.business_partners(id),
    supplier_partner_id uuid REFERENCES ewms.business_partners(id),
    declarant_partner_id uuid REFERENCES ewms.business_partners(id),
    procurement_type varchar(30) NOT NULL DEFAULT 'DIRECT',
    clearance_mode varchar(30) NOT NULL DEFAULT 'NORMAL',
    customs_valuation_method varchar(20),
    expected_arrival_at timestamptz,
    actual_arrival_at timestamptz,
    expected_release_at timestamptz,
    actual_release_at timestamptz,
    expected_delivery_at timestamptz,
    actual_delivery_at timestamptz,
    status varchar(30) NOT NULL DEFAULT 'PLANNED',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, trade_case_id),
    CONSTRAINT ck_ewms_import_case_procurement CHECK (
        procurement_type IN ('DIRECT','AGENCY','CONSIGNMENT','LEASE','TOLLING','RETURN','OTHER')
    ),
    CONSTRAINT ck_ewms_import_case_clearance CHECK (
        clearance_mode IN ('NORMAL','PRE_ARRIVAL','IMMEDIATE','TEMPORARY','REIMPORT','BONDED','OTHER')
    ),
    CONSTRAINT ck_ewms_import_case_status CHECK (status IN (
        'PLANNED','BOOKED','IN_TRANSIT','ARRIVED','MANIFESTED','BONDED','DECLARING',
        'INSPECTION','DUTY_PENDING','RELEASED','DELIVERED','CLOSED','CANCELLED'
    )),
    CONSTRAINT ck_ewms_import_case_arrival CHECK (
        actual_arrival_at IS NULL OR expected_arrival_at IS NULL OR actual_arrival_at >= expected_arrival_at - interval '365 days'
    ),
    CONSTRAINT ck_ewms_import_case_actual_dates CHECK (
        (actual_release_at IS NULL OR actual_arrival_at IS NULL OR actual_release_at >= actual_arrival_at) AND
        (actual_delivery_at IS NULL OR actual_release_at IS NULL OR actual_delivery_at >= actual_release_at)
    )
);

CREATE TABLE IF NOT EXISTS ewms.import_case_items (
    trade_case_item_id uuid PRIMARY KEY REFERENCES ewms.trade_case_items(id) ON DELETE RESTRICT,
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    import_purpose varchar(80),
    import_condition varchar(80),
    intended_use text,
    quota_required boolean NOT NULL DEFAULT false,
    permit_required boolean NOT NULL DEFAULT false,
    quarantine_required boolean NOT NULL DEFAULT false,
    inspection_required boolean NOT NULL DEFAULT false,
    temporary_import_due_date date,
    drawback_eligible boolean NOT NULL DEFAULT false,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, trade_case_item_id)
);

CREATE TABLE IF NOT EXISTS ewms.import_arrival_notices (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    import_case_id uuid NOT NULL REFERENCES ewms.import_cases(trade_case_id) ON DELETE RESTRICT,
    trade_shipment_id uuid REFERENCES ewms.trade_shipments(id) ON DELETE RESTRICT,
    notice_no varchar(150) NOT NULL,
    notice_version integer NOT NULL DEFAULT 1,
    carrier_partner_id uuid REFERENCES ewms.business_partners(id),
    notice_received_at timestamptz NOT NULL,
    estimated_arrival_at timestamptz,
    actual_arrival_at timestamptz,
    discharge_completed_at timestamptz,
    free_time_end_at timestamptz,
    delivery_order_required boolean NOT NULL DEFAULT false,
    status varchar(20) NOT NULL DEFAULT 'RECEIVED',
    source_system_id uuid REFERENCES ewms.external_systems(id),
    external_notice_id varchar(300),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, notice_no, notice_version),
    UNIQUE (source_system_id, external_notice_id),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_import_arrival_notice_version CHECK (notice_version > 0),
    CONSTRAINT ck_ewms_import_arrival_notice_status CHECK (
        status IN ('RECEIVED','CONFIRMED','UPDATED','CANCELLED','COMPLETED')
    ),
    CONSTRAINT ck_ewms_import_arrival_notice_dates CHECK (
        (actual_arrival_at IS NULL OR estimated_arrival_at IS NULL OR actual_arrival_at >= estimated_arrival_at - interval '365 days') AND
        (discharge_completed_at IS NULL OR actual_arrival_at IS NULL OR discharge_completed_at >= actual_arrival_at) AND
        (free_time_end_at IS NULL OR actual_arrival_at IS NULL OR free_time_end_at >= actual_arrival_at)
    )
);

CREATE TABLE IF NOT EXISTS ewms.import_arrival_notice_lines (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    arrival_notice_id uuid NOT NULL REFERENCES ewms.import_arrival_notices(id) ON DELETE CASCADE,
    line_no integer NOT NULL,
    trade_case_item_id uuid REFERENCES ewms.trade_case_items(id) ON DELETE RESTRICT,
    container_id uuid REFERENCES ewms.trade_containers(id),
    transport_document_no varchar(200),
    package_count numeric(20,4),
    gross_weight numeric(24,8),
    weight_uom_code varchar(20) REFERENCES ewms.units_of_measure(uom_code),
    cargo_status varchar(30),
    UNIQUE (arrival_notice_id, line_no),
    CONSTRAINT ck_ewms_import_arrival_notice_line_no CHECK (line_no > 0),
    CONSTRAINT ck_ewms_import_arrival_notice_line_qty CHECK (
        (package_count IS NULL OR package_count >= 0) AND (gross_weight IS NULL OR gross_weight >= 0)
    )
);

CREATE TABLE IF NOT EXISTS ewms.import_release_orders (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    import_case_id uuid NOT NULL REFERENCES ewms.import_cases(trade_case_id) ON DELETE RESTRICT,
    release_order_no varchar(150) NOT NULL,
    customs_release_evidence_id uuid NOT NULL REFERENCES ewms.customs_release_evidence(id) ON DELETE RESTRICT,
    issued_by_partner_id uuid REFERENCES ewms.business_partners(id),
    released_to_partner_id uuid REFERENCES ewms.business_partners(id),
    issue_at timestamptz NOT NULL,
    valid_until timestamptz,
    status varchar(20) NOT NULL DEFAULT 'ISSUED',
    row_version bigint NOT NULL DEFAULT 1,
    created_by uuid REFERENCES ewms.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, release_order_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_import_release_order_status CHECK (
        status IN ('ISSUED','PARTIALLY_USED','USED','EXPIRED','REVOKED','CANCELLED')
    ),
    CONSTRAINT ck_ewms_import_release_order_dates CHECK (valid_until IS NULL OR valid_until >= issue_at)
);

CREATE TABLE IF NOT EXISTS ewms.import_release_order_lines (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    release_order_id uuid NOT NULL REFERENCES ewms.import_release_orders(id) ON DELETE RESTRICT,
    line_no integer NOT NULL,
    trade_case_item_id uuid NOT NULL REFERENCES ewms.trade_case_items(id) ON DELETE RESTRICT,
    release_coverage_id uuid NOT NULL REFERENCES ewms.customs_release_line_coverages(id) ON DELETE RESTRICT,
    released_quantity numeric(24,8) NOT NULL,
    uom_code varchar(20) NOT NULL REFERENCES ewms.units_of_measure(uom_code),
    used_quantity numeric(24,8) NOT NULL DEFAULT 0,
    UNIQUE (release_order_id, line_no),
    CONSTRAINT ck_ewms_import_release_order_line_no CHECK (line_no > 0),
    CONSTRAINT ck_ewms_import_release_order_line_qty CHECK (
        released_quantity > 0 AND used_quantity >= 0 AND used_quantity <= released_quantity
    )
);

CREATE TABLE IF NOT EXISTS ewms.import_events (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    import_case_id uuid NOT NULL REFERENCES ewms.import_cases(trade_case_id) ON DELETE RESTRICT,
    sequence_no bigint NOT NULL,
    event_type varchar(80) NOT NULL,
    from_status varchar(30),
    to_status varchar(30),
    occurred_at timestamptz NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT now(),
    recorded_by uuid REFERENCES ewms.users(id),
    source_system_id uuid REFERENCES ewms.external_systems(id),
    external_event_id varchar(300),
    detail_masked jsonb NOT NULL DEFAULT '{}'::jsonb,
    UNIQUE (import_case_id, sequence_no),
    UNIQUE (source_system_id, external_event_id),
    CONSTRAINT ck_ewms_import_event_sequence CHECK (sequence_no > 0),
    CONSTRAINT ck_ewms_import_event_masked_json CHECK (
        NOT ewms.jsonb_contains_forbidden_secret_key(detail_masked)
    )
);

CREATE TABLE IF NOT EXISTS ewms.export_cases (
    trade_case_id uuid PRIMARY KEY REFERENCES ewms.trade_cases(id) ON DELETE RESTRICT,
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    exporter_partner_id uuid NOT NULL REFERENCES ewms.business_partners(id),
    manufacturer_partner_id uuid REFERENCES ewms.business_partners(id),
    consignee_partner_id uuid REFERENCES ewms.business_partners(id),
    end_user_partner_id uuid REFERENCES ewms.business_partners(id),
    export_type varchar(30) NOT NULL DEFAULT 'NORMAL',
    payment_method varchar(50),
    letter_of_credit_reference varchar(150),
    cargo_ready_at timestamptz,
    booking_deadline_at timestamptz,
    documentation_cutoff_at timestamptz,
    customs_cutoff_at timestamptz,
    cargo_cutoff_at timestamptz,
    planned_on_board_at timestamptz,
    actual_on_board_at timestamptz,
    planned_departure_at timestamptz,
    actual_departure_at timestamptz,
    status varchar(30) NOT NULL DEFAULT 'PLANNED',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, trade_case_id),
    CONSTRAINT ck_ewms_export_case_type CHECK (
        export_type IN ('NORMAL','REEXPORT','RETURN','TEMPORARY','SAMPLE','CONSIGNMENT','OTHER')
    ),
    CONSTRAINT ck_ewms_export_case_status CHECK (status IN (
        'PLANNED','ORDERED','READY','BOOKED','DECLARING','ACCEPTED','STUFFED',
        'GATE_IN','LOADED','DEPARTED','DOCS_ISSUED','CLOSED','CANCELLED'
    )),
    CONSTRAINT ck_ewms_export_case_cutoffs CHECK (
        (booking_deadline_at IS NULL OR cargo_ready_at IS NULL OR booking_deadline_at >= cargo_ready_at - interval '365 days') AND
        (actual_departure_at IS NULL OR actual_on_board_at IS NULL OR actual_departure_at >= actual_on_board_at)
    )
);

CREATE TABLE IF NOT EXISTS ewms.export_case_items (
    trade_case_item_id uuid PRIMARY KEY REFERENCES ewms.trade_case_items(id) ON DELETE RESTRICT,
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    strategic_goods_flag boolean NOT NULL DEFAULT false,
    control_classification_code varchar(100),
    export_license_required boolean NOT NULL DEFAULT false,
    end_use_statement_required boolean NOT NULL DEFAULT false,
    drawback_intended boolean NOT NULL DEFAULT false,
    preferential_origin_intended boolean NOT NULL DEFAULT false,
    temporary_export_due_date date,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, trade_case_item_id)
);

CREATE TABLE IF NOT EXISTS ewms.export_shipping_instructions (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    export_case_id uuid NOT NULL REFERENCES ewms.export_cases(trade_case_id) ON DELETE RESTRICT,
    trade_shipment_id uuid REFERENCES ewms.trade_shipments(id) ON DELETE RESTRICT,
    instruction_no varchar(150) NOT NULL,
    current_version_id uuid,
    current_version_no integer,
    status varchar(30) NOT NULL DEFAULT 'DRAFT',
    row_version bigint NOT NULL DEFAULT 1,
    created_by uuid REFERENCES ewms.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, instruction_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_export_si_status CHECK (
        status IN ('DRAFT','SUBMITTED','CONFIRMED','AMENDMENT_PENDING','AMENDED','CANCELLED')
    ),
    CONSTRAINT ck_ewms_export_si_current_version CHECK (
        (current_version_id IS NULL AND current_version_no IS NULL) OR
        (current_version_id IS NOT NULL AND current_version_no > 0)
    )
);

CREATE TABLE IF NOT EXISTS ewms.export_shipping_instruction_versions (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    shipping_instruction_id uuid NOT NULL REFERENCES ewms.export_shipping_instructions(id) ON DELETE RESTRICT,
    version_no integer NOT NULL,
    filing_action varchar(20) NOT NULL DEFAULT 'ORIGINAL',
    shipper_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
    consignee_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
    notify_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
    freight_term varchar(20),
    bill_type varchar(30) NOT NULL DEFAULT 'ORIGINAL',
    original_bill_count integer NOT NULL DEFAULT 3,
    place_of_receipt varchar(300),
    port_of_loading_code varchar(10) REFERENCES ewms.ports(port_code),
    port_of_discharge_code varchar(10) REFERENCES ewms.ports(port_code),
    place_of_delivery varchar(300),
    marks_and_numbers text,
    cargo_description text,
    declared_at timestamptz,
    sealed_at timestamptz,
    sealed_by uuid REFERENCES ewms.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (shipping_instruction_id, version_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_export_si_version CHECK (version_no > 0),
    CONSTRAINT ck_ewms_export_si_action CHECK (filing_action IN ('ORIGINAL','AMENDMENT','CANCELLATION')),
    CONSTRAINT ck_ewms_export_si_bill_type CHECK (
        bill_type IN ('ORIGINAL','SEAWAY','SURRENDERED','TELEX_RELEASE','EXPRESS','OTHER')
    ),
    CONSTRAINT ck_ewms_export_si_bill_count CHECK (original_bill_count >= 0),
    CONSTRAINT ck_ewms_export_si_masked_json CHECK (
        NOT ewms.jsonb_contains_forbidden_secret_key(shipper_snapshot) AND
        NOT ewms.jsonb_contains_forbidden_secret_key(consignee_snapshot) AND
        NOT ewms.jsonb_contains_forbidden_secret_key(notify_snapshot)
    )
);

DO $block$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'ewms.export_shipping_instructions'::regclass
          AND conname = 'fk_ewms_export_si_current_version'
    ) THEN
        ALTER TABLE ewms.export_shipping_instructions
            ADD CONSTRAINT fk_ewms_export_si_current_version
            FOREIGN KEY (tenant_id, current_version_id)
            REFERENCES ewms.export_shipping_instruction_versions(tenant_id, id)
            DEFERRABLE INITIALLY DEFERRED;
    END IF;
END;
$block$;

CREATE TABLE IF NOT EXISTS ewms.export_shipping_instruction_lines (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    shipping_instruction_version_id uuid NOT NULL
        REFERENCES ewms.export_shipping_instruction_versions(id) ON DELETE CASCADE,
    line_no integer NOT NULL,
    trade_case_item_id uuid REFERENCES ewms.trade_case_items(id) ON DELETE RESTRICT,
    container_id uuid REFERENCES ewms.trade_containers(id),
    marks_and_numbers text,
    goods_description varchar(1000) NOT NULL,
    package_count numeric(20,4),
    package_type_code varchar(50),
    gross_weight numeric(24,8),
    weight_uom_code varchar(20) REFERENCES ewms.units_of_measure(uom_code),
    volume_value numeric(24,9),
    volume_uom_code varchar(20) REFERENCES ewms.units_of_measure(uom_code),
    UNIQUE (shipping_instruction_version_id, line_no),
    CONSTRAINT ck_ewms_export_si_line_no CHECK (line_no > 0),
    CONSTRAINT ck_ewms_export_si_line_qty CHECK (
        (package_count IS NULL OR package_count >= 0) AND
        (gross_weight IS NULL OR gross_weight >= 0) AND
        (volume_value IS NULL OR volume_value >= 0)
    )
);

CREATE TABLE IF NOT EXISTS ewms.export_cargo_receipts (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    export_case_id uuid NOT NULL REFERENCES ewms.export_cases(trade_case_id) ON DELETE RESTRICT,
    trade_shipment_id uuid REFERENCES ewms.trade_shipments(id) ON DELETE RESTRICT,
    receipt_no varchar(150) NOT NULL,
    receiving_partner_id uuid REFERENCES ewms.business_partners(id),
    receiving_location varchar(300),
    received_at timestamptz NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'RECEIVED',
    remarks text,
    row_version bigint NOT NULL DEFAULT 1,
    created_by uuid REFERENCES ewms.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, receipt_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_export_cargo_receipt_status CHECK (
        status IN ('RECEIVED','DISCREPANCY','ACCEPTED','REJECTED','CANCELLED')
    )
);

CREATE TABLE IF NOT EXISTS ewms.export_cargo_receipt_lines (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    cargo_receipt_id uuid NOT NULL REFERENCES ewms.export_cargo_receipts(id) ON DELETE CASCADE,
    line_no integer NOT NULL,
    trade_case_item_id uuid NOT NULL REFERENCES ewms.trade_case_items(id) ON DELETE RESTRICT,
    received_quantity numeric(24,8) NOT NULL,
    accepted_quantity numeric(24,8) NOT NULL DEFAULT 0,
    rejected_quantity numeric(24,8) NOT NULL DEFAULT 0,
    uom_code varchar(20) NOT NULL REFERENCES ewms.units_of_measure(uom_code),
    package_count numeric(20,4),
    gross_weight numeric(24,8),
    weight_uom_code varchar(20) REFERENCES ewms.units_of_measure(uom_code),
    discrepancy_reason text,
    UNIQUE (cargo_receipt_id, line_no),
    CONSTRAINT ck_ewms_export_cargo_receipt_line_no CHECK (line_no > 0),
    CONSTRAINT ck_ewms_export_cargo_receipt_line_qty CHECK (
        received_quantity > 0 AND accepted_quantity >= 0 AND rejected_quantity >= 0 AND
        accepted_quantity + rejected_quantity <= received_quantity AND
        (package_count IS NULL OR package_count >= 0) AND (gross_weight IS NULL OR gross_weight >= 0)
    )
);

CREATE TABLE IF NOT EXISTS ewms.export_fulfillment_evidence (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    export_case_id uuid NOT NULL REFERENCES ewms.export_cases(trade_case_id) ON DELETE RESTRICT,
    trade_case_item_id uuid REFERENCES ewms.trade_case_items(id) ON DELETE RESTRICT,
    customs_declaration_version_id uuid NOT NULL
        REFERENCES ewms.customs_declaration_versions(id) ON DELETE RESTRICT,
    trade_shipment_id uuid NOT NULL REFERENCES ewms.trade_shipments(id) ON DELETE RESTRICT,
    shipment_line_id uuid REFERENCES ewms.shipment_lines(id) ON DELETE RESTRICT,
    evidence_type varchar(30) NOT NULL,
    evidenced_quantity numeric(24,8) NOT NULL,
    uom_code varchar(20) NOT NULL REFERENCES ewms.units_of_measure(uom_code),
    departure_evidence_file_id uuid REFERENCES ewms.files(id) ON DELETE RESTRICT,
    occurred_at timestamptz NOT NULL,
    recorded_by uuid REFERENCES ewms.users(id),
    recorded_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (export_case_id, customs_declaration_version_id, trade_shipment_id, evidence_type, trade_case_item_id),
    CONSTRAINT ck_ewms_export_fulfillment_evidence_type CHECK (
        evidence_type IN ('DECLARATION_ACCEPTANCE','LOADED_ON_BOARD','DEPARTURE','DELIVERY','RETURN')
    ),
    CONSTRAINT ck_ewms_export_fulfillment_evidence_qty CHECK (evidenced_quantity > 0)
);

CREATE TABLE IF NOT EXISTS ewms.export_events (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    export_case_id uuid NOT NULL REFERENCES ewms.export_cases(trade_case_id) ON DELETE RESTRICT,
    sequence_no bigint NOT NULL,
    event_type varchar(80) NOT NULL,
    from_status varchar(30),
    to_status varchar(30),
    occurred_at timestamptz NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT now(),
    recorded_by uuid REFERENCES ewms.users(id),
    source_system_id uuid REFERENCES ewms.external_systems(id),
    external_event_id varchar(300),
    detail_masked jsonb NOT NULL DEFAULT '{}'::jsonb,
    UNIQUE (export_case_id, sequence_no),
    UNIQUE (source_system_id, external_event_id),
    CONSTRAINT ck_ewms_export_event_sequence CHECK (sequence_no > 0),
    CONSTRAINT ck_ewms_export_event_masked_json CHECK (
        NOT ewms.jsonb_contains_forbidden_secret_key(detail_masked)
    )
);

-- -----------------------------------------------------------------------------
-- Transport, carrier, booking, terminal, and equipment extensions
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS ewms.seaport_details (
    port_code varchar(10) PRIMARY KEY REFERENCES ewms.ports(port_code) ON DELETE CASCADE,
    unlocode varchar(10),
    harbor_type varchar(30),
    maximum_draft numeric(12,4),
    draft_uom_code varchar(20) REFERENCES ewms.units_of_measure(uom_code),
    has_container_terminal boolean NOT NULL DEFAULT false,
    has_bonded_area boolean NOT NULL DEFAULT false,
    authority_name varchar(200),
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT ck_ewms_seaport_draft CHECK (maximum_draft IS NULL OR maximum_draft >= 0)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_ewms_seaport_unlocode
    ON ewms.seaport_details (unlocode) WHERE unlocode IS NOT NULL;

CREATE TABLE IF NOT EXISTS ewms.airport_details (
    port_code varchar(10) PRIMARY KEY REFERENCES ewms.ports(port_code) ON DELETE CASCADE,
    iata_code char(3),
    icao_code char(4),
    airport_type varchar(30),
    has_cargo_terminal boolean NOT NULL DEFAULT false,
    has_bonded_area boolean NOT NULL DEFAULT false,
    authority_name varchar(200),
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_ewms_airport_iata
    ON ewms.airport_details (iata_code) WHERE iata_code IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_ewms_airport_icao
    ON ewms.airport_details (icao_code) WHERE icao_code IS NOT NULL;

CREATE TABLE IF NOT EXISTS ewms.port_terminals (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    port_code varchar(10) NOT NULL REFERENCES ewms.ports(port_code),
    terminal_code varchar(50) NOT NULL,
    terminal_name varchar(200) NOT NULL,
    operator_partner_id uuid REFERENCES ewms.business_partners(id),
    terminal_type varchar(30) NOT NULL,
    customs_location_code varchar(100),
    timezone varchar(100),
    address_id uuid REFERENCES ewms.addresses(id),
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, port_code, terminal_code),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_port_terminal_type CHECK (
        terminal_type IN ('CONTAINER','BULK','BREAK_BULK','RO_RO','AIR_CARGO','RAIL','INLAND','OTHER')
    )
);

CREATE TABLE IF NOT EXISTS ewms.partner_sites (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    partner_id uuid NOT NULL REFERENCES ewms.business_partners(id),
    site_code varchar(80) NOT NULL,
    site_name varchar(200) NOT NULL,
    site_type varchar(30) NOT NULL,
    address_id uuid REFERENCES ewms.addresses(id),
    port_code varchar(10) REFERENCES ewms.ports(port_code),
    timezone varchar(100),
    latitude numeric(10,7),
    longitude numeric(10,7),
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, partner_id, site_code),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_partner_site_type CHECK (
        site_type IN ('FACTORY','SUPPLIER','CUSTOMER','PORT','AIRPORT','TERMINAL','WAREHOUSE','OFFICE','OTHER')
    ),
    CONSTRAINT ck_ewms_partner_site_lat CHECK (latitude IS NULL OR latitude BETWEEN -90 AND 90),
    CONSTRAINT ck_ewms_partner_site_lon CHECK (longitude IS NULL OR longitude BETWEEN -180 AND 180)
);

CREATE TABLE IF NOT EXISTS ewms.carrier_profiles (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    carrier_partner_id uuid NOT NULL REFERENCES ewms.business_partners(id),
    carrier_type varchar(30) NOT NULL,
    scac_code varchar(10),
    iata_cargo_code varchar(20),
    icao_airline_code varchar(10),
    customs_carrier_code varchar(50),
    liability_limit numeric(24,4),
    liability_currency_code char(3) REFERENCES ewms.currencies(currency_code),
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, carrier_partner_id, carrier_type),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_carrier_profile_type CHECK (
        carrier_type IN ('OCEAN','AIR','ROAD','RAIL','COURIER','MULTIMODAL','NVOCC')
    ),
    CONSTRAINT ck_ewms_carrier_profile_status CHECK (status IN ('ACTIVE','SUSPENDED','INACTIVE','BLOCKED')),
    CONSTRAINT ck_ewms_carrier_profile_limit CHECK (liability_limit IS NULL OR liability_limit >= 0)
);

CREATE TABLE IF NOT EXISTS ewms.carrier_trade_services (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    carrier_profile_id uuid NOT NULL REFERENCES ewms.carrier_profiles(id) ON DELETE CASCADE,
    service_code varchar(80) NOT NULL,
    service_name varchar(200) NOT NULL,
    transport_mode_code varchar(20) NOT NULL REFERENCES ewms.transport_modes(mode_code),
    origin_port_code varchar(10) REFERENCES ewms.ports(port_code),
    destination_port_code varchar(10) REFERENCES ewms.ports(port_code),
    transit_days integer,
    frequency_code varchar(30),
    valid_from date,
    valid_to date,
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, carrier_profile_id, service_code),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_carrier_service_transit CHECK (transit_days IS NULL OR transit_days >= 0),
    CONSTRAINT ck_ewms_carrier_service_dates CHECK (valid_to IS NULL OR valid_from IS NULL OR valid_to >= valid_from)
);

CREATE TABLE IF NOT EXISTS ewms.vessel_aliases (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    vessel_id uuid NOT NULL REFERENCES ewms.vessels(id) ON DELETE CASCADE,
    alias_type varchar(30) NOT NULL,
    alias_value varchar(200) NOT NULL,
    valid_from date,
    valid_to date,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, alias_type, alias_value),
    CONSTRAINT ck_ewms_vessel_alias_type CHECK (
        alias_type IN ('FORMER_NAME','LOCAL_NAME','CALL_SIGN','MMSI','REGISTRY_NO','OTHER')
    ),
    CONSTRAINT ck_ewms_vessel_alias_dates CHECK (valid_to IS NULL OR valid_from IS NULL OR valid_to >= valid_from)
);

CREATE TABLE IF NOT EXISTS ewms.vessel_partner_roles (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    vessel_id uuid NOT NULL REFERENCES ewms.vessels(id) ON DELETE RESTRICT,
    partner_id uuid NOT NULL REFERENCES ewms.business_partners(id) ON DELETE RESTRICT,
    role_code varchar(30) NOT NULL,
    valid_from date NOT NULL,
    valid_to date,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (vessel_id, partner_id, role_code, valid_from),
    CONSTRAINT ck_ewms_vessel_partner_role CHECK (
        role_code IN ('OWNER','OPERATOR','MANAGER','CHARTERER','AGENT','CARRIER','INSURER','OTHER')
    ),
    CONSTRAINT ck_ewms_vessel_partner_dates CHECK (valid_to IS NULL OR valid_to >= valid_from)
);

CREATE TABLE IF NOT EXISTS ewms.transport_schedules (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    carrier_trade_service_id uuid REFERENCES ewms.carrier_trade_services(id),
    carrier_partner_id uuid NOT NULL REFERENCES ewms.business_partners(id),
    schedule_reference varchar(120) NOT NULL,
    transport_mode_code varchar(20) NOT NULL REFERENCES ewms.transport_modes(mode_code),
    vessel_id uuid REFERENCES ewms.vessels(id),
    voyage_no varchar(100),
    flight_no varchar(50),
    effective_from date,
    effective_to date,
    status varchar(20) NOT NULL DEFAULT 'PUBLISHED',
    source_system_id uuid REFERENCES ewms.external_systems(id),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, carrier_partner_id, schedule_reference),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_transport_schedule_asset CHECK (num_nonnulls(vessel_id, flight_no) <= 1),
    CONSTRAINT ck_ewms_transport_schedule_status CHECK (
        status IN ('DRAFT','PUBLISHED','UPDATED','CANCELLED','EXPIRED')
    ),
    CONSTRAINT ck_ewms_transport_schedule_dates CHECK (
        effective_to IS NULL OR effective_from IS NULL OR effective_to >= effective_from
    )
);

CREATE TABLE IF NOT EXISTS ewms.transport_schedule_calls (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    transport_schedule_id uuid NOT NULL REFERENCES ewms.transport_schedules(id) ON DELETE CASCADE,
    call_no integer NOT NULL,
    port_code varchar(10) NOT NULL REFERENCES ewms.ports(port_code),
    terminal_id uuid REFERENCES ewms.port_terminals(id),
    call_type varchar(20) NOT NULL DEFAULT 'PORT_CALL',
    planned_arrival_at timestamptz,
    planned_departure_at timestamptz,
    actual_arrival_at timestamptz,
    actual_departure_at timestamptz,
    status varchar(20) NOT NULL DEFAULT 'PLANNED',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (transport_schedule_id, call_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_transport_schedule_call_no CHECK (call_no > 0),
    CONSTRAINT ck_ewms_transport_schedule_call_status CHECK (
        status IN ('PLANNED','CONFIRMED','ARRIVED','DEPARTED','SKIPPED','CANCELLED')
    ),
    CONSTRAINT ck_ewms_transport_schedule_call_dates CHECK (
        (planned_departure_at IS NULL OR planned_arrival_at IS NULL OR planned_departure_at >= planned_arrival_at) AND
        (actual_departure_at IS NULL OR actual_arrival_at IS NULL OR actual_departure_at >= actual_arrival_at)
    )
);

CREATE TABLE IF NOT EXISTS ewms.carrier_bookings (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    trade_shipment_id uuid NOT NULL REFERENCES ewms.trade_shipments(id) ON DELETE RESTRICT,
    carrier_partner_id uuid NOT NULL REFERENCES ewms.business_partners(id),
    forwarding_partner_id uuid REFERENCES ewms.business_partners(id),
    transport_schedule_id uuid REFERENCES ewms.transport_schedules(id),
    booking_no varchar(150) NOT NULL,
    current_version_id uuid,
    current_version_no integer,
    booking_status varchar(30) NOT NULL DEFAULT 'REQUESTED',
    carrier_confirmation_no varchar(150),
    confirmed_at timestamptz,
    cancelled_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_by uuid REFERENCES ewms.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, carrier_partner_id, booking_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_carrier_booking_status CHECK (booking_status IN (
        'REQUESTED','PENDING','CONFIRMED','AMENDMENT_PENDING','REJECTED','CANCELLED','CLOSED'
    )),
    CONSTRAINT ck_ewms_carrier_booking_current_version CHECK (
        (current_version_id IS NULL AND current_version_no IS NULL) OR
        (current_version_id IS NOT NULL AND current_version_no > 0)
    )
);

CREATE TABLE IF NOT EXISTS ewms.carrier_booking_versions (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    carrier_booking_id uuid NOT NULL REFERENCES ewms.carrier_bookings(id) ON DELETE RESTRICT,
    version_no integer NOT NULL,
    filing_action varchar(20) NOT NULL DEFAULT 'ORIGINAL',
    shipper_reference varchar(150),
    service_contract_reference varchar(150),
    origin_port_code varchar(10) REFERENCES ewms.ports(port_code),
    destination_port_code varchar(10) REFERENCES ewms.ports(port_code),
    receipt_site_id uuid REFERENCES ewms.partner_sites(id),
    delivery_site_id uuid REFERENCES ewms.partner_sites(id),
    cargo_ready_at timestamptz,
    requested_departure_at timestamptz,
    requested_arrival_at timestamptz,
    confirmed_departure_at timestamptz,
    confirmed_arrival_at timestamptz,
    commodity_description text,
    dangerous_goods boolean NOT NULL DEFAULT false,
    temperature_controlled boolean NOT NULL DEFAULT false,
    temperature_min numeric(12,4),
    temperature_max numeric(12,4),
    temperature_uom_code varchar(20) REFERENCES ewms.units_of_measure(uom_code),
    submitted_at timestamptz,
    sealed_at timestamptz,
    sealed_by uuid REFERENCES ewms.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (carrier_booking_id, version_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_carrier_booking_version_no CHECK (version_no > 0),
    CONSTRAINT ck_ewms_carrier_booking_version_action CHECK (
        filing_action IN ('ORIGINAL','AMENDMENT','CANCELLATION')
    ),
    CONSTRAINT ck_ewms_carrier_booking_version_dates CHECK (
        (requested_arrival_at IS NULL OR requested_departure_at IS NULL OR requested_arrival_at >= requested_departure_at) AND
        (confirmed_arrival_at IS NULL OR confirmed_departure_at IS NULL OR confirmed_arrival_at >= confirmed_departure_at)
    ),
    CONSTRAINT ck_ewms_carrier_booking_version_temp CHECK (
        temperature_max IS NULL OR temperature_min IS NULL OR temperature_max >= temperature_min
    )
);

DO $block$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'ewms.carrier_bookings'::regclass
          AND conname = 'fk_ewms_carrier_booking_current_version'
    ) THEN
        ALTER TABLE ewms.carrier_bookings
            ADD CONSTRAINT fk_ewms_carrier_booking_current_version
            FOREIGN KEY (tenant_id, current_version_id)
            REFERENCES ewms.carrier_booking_versions(tenant_id, id)
            DEFERRABLE INITIALLY DEFERRED;
    END IF;
END;
$block$;

CREATE TABLE IF NOT EXISTS ewms.carrier_booking_equipment (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    carrier_booking_version_id uuid NOT NULL REFERENCES ewms.carrier_booking_versions(id) ON DELETE CASCADE,
    equipment_line_no integer NOT NULL,
    equipment_type_code varchar(50) NOT NULL,
    requested_quantity integer NOT NULL,
    confirmed_quantity integer NOT NULL DEFAULT 0,
    shipper_owned boolean NOT NULL DEFAULT false,
    refrigerated boolean NOT NULL DEFAULT false,
    temperature_set_point numeric(12,4),
    temperature_uom_code varchar(20) REFERENCES ewms.units_of_measure(uom_code),
    UNIQUE (carrier_booking_version_id, equipment_line_no),
    CONSTRAINT ck_ewms_carrier_booking_equipment_line CHECK (equipment_line_no > 0),
    CONSTRAINT ck_ewms_carrier_booking_equipment_qty CHECK (
        requested_quantity > 0 AND confirmed_quantity >= 0 AND confirmed_quantity <= requested_quantity
    )
);

CREATE TABLE IF NOT EXISTS ewms.carrier_booking_cargo (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    carrier_booking_version_id uuid NOT NULL REFERENCES ewms.carrier_booking_versions(id) ON DELETE CASCADE,
    cargo_line_no integer NOT NULL,
    trade_shipment_item_id uuid REFERENCES ewms.trade_shipment_items(id) ON DELETE RESTRICT,
    goods_description varchar(1000) NOT NULL,
    package_count numeric(20,4),
    package_type_code varchar(50),
    gross_weight numeric(24,8),
    weight_uom_code varchar(20) REFERENCES ewms.units_of_measure(uom_code),
    volume_value numeric(24,9),
    volume_uom_code varchar(20) REFERENCES ewms.units_of_measure(uom_code),
    dangerous_goods boolean NOT NULL DEFAULT false,
    UNIQUE (carrier_booking_version_id, cargo_line_no),
    CONSTRAINT ck_ewms_carrier_booking_cargo_line CHECK (cargo_line_no > 0),
    CONSTRAINT ck_ewms_carrier_booking_cargo_qty CHECK (
        (package_count IS NULL OR package_count >= 0) AND
        (gross_weight IS NULL OR gross_weight >= 0) AND
        (volume_value IS NULL OR volume_value >= 0)
    )
);

CREATE TABLE IF NOT EXISTS ewms.carrier_booking_events (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    carrier_booking_id uuid NOT NULL REFERENCES ewms.carrier_bookings(id) ON DELETE RESTRICT,
    sequence_no bigint NOT NULL,
    event_type varchar(80) NOT NULL,
    from_status varchar(30),
    to_status varchar(30),
    occurred_at timestamptz NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT now(),
    recorded_by uuid REFERENCES ewms.users(id),
    source_system_id uuid REFERENCES ewms.external_systems(id),
    external_event_id varchar(300),
    detail_masked jsonb NOT NULL DEFAULT '{}'::jsonb,
    UNIQUE (carrier_booking_id, sequence_no),
    UNIQUE (source_system_id, external_event_id),
    CONSTRAINT ck_ewms_carrier_booking_event_seq CHECK (sequence_no > 0),
    CONSTRAINT ck_ewms_carrier_booking_event_masked_json CHECK (
        NOT ewms.jsonb_contains_forbidden_secret_key(detail_masked)
    )
);

CREATE TABLE IF NOT EXISTS ewms.terminal_cutoffs (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    trade_shipment_id uuid REFERENCES ewms.trade_shipments(id) ON DELETE CASCADE,
    carrier_booking_id uuid REFERENCES ewms.carrier_bookings(id) ON DELETE CASCADE,
    terminal_id uuid REFERENCES ewms.port_terminals(id),
    cutoff_type varchar(30) NOT NULL,
    cutoff_at timestamptz NOT NULL,
    source varchar(100),
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_ewms_terminal_cutoff_parent CHECK (
        num_nonnulls(trade_shipment_id, carrier_booking_id) >= 1
    ),
    CONSTRAINT ck_ewms_terminal_cutoff_type CHECK (cutoff_type IN (
        'BOOKING','DOCUMENTATION','VGM','CUSTOMS','REEFER','DANGEROUS_GOODS','CARGO','GATE_IN','OTHER'
    )),
    CONSTRAINT ck_ewms_terminal_cutoff_status CHECK (status IN ('ACTIVE','MET','MISSED','WAIVED','CANCELLED'))
);

CREATE TABLE IF NOT EXISTS ewms.verified_gross_masses (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    trade_shipment_id uuid NOT NULL REFERENCES ewms.trade_shipments(id) ON DELETE RESTRICT,
    container_id uuid NOT NULL REFERENCES ewms.trade_containers(id) ON DELETE RESTRICT,
    measurement_method varchar(20) NOT NULL,
    verified_gross_mass numeric(24,8) NOT NULL,
    weight_uom_code varchar(20) NOT NULL REFERENCES ewms.units_of_measure(uom_code),
    weighing_at timestamptz NOT NULL,
    weighing_place varchar(300),
    responsible_party_id uuid REFERENCES ewms.business_partners(id),
    authorized_person_name varchar(200),
    certificate_file_id uuid REFERENCES ewms.files(id) ON DELETE RESTRICT,
    status varchar(20) NOT NULL DEFAULT 'DECLARED',
    supersedes_id uuid REFERENCES ewms.verified_gross_masses(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (trade_shipment_id, container_id, weighing_at),
    CONSTRAINT ck_ewms_vgm_method CHECK (measurement_method IN ('METHOD_1','METHOD_2')),
    CONSTRAINT ck_ewms_vgm_mass CHECK (verified_gross_mass > 0),
    CONSTRAINT ck_ewms_vgm_status CHECK (status IN ('DRAFT','DECLARED','ACCEPTED','REJECTED','SUPERSEDED','CANCELLED'))
);

CREATE TABLE IF NOT EXISTS ewms.equipment_interchanges (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    container_id uuid NOT NULL REFERENCES ewms.trade_containers(id) ON DELETE RESTRICT,
    trade_shipment_id uuid REFERENCES ewms.trade_shipments(id) ON DELETE RESTRICT,
    interchange_type varchar(20) NOT NULL,
    from_partner_id uuid REFERENCES ewms.business_partners(id),
    to_partner_id uuid REFERENCES ewms.business_partners(id),
    location_text varchar(300),
    port_code varchar(10) REFERENCES ewms.ports(port_code),
    occurred_at timestamptz NOT NULL,
    condition_code varchar(50),
    damage_summary text,
    meter_reading numeric(20,6),
    evidence_file_id uuid REFERENCES ewms.files(id) ON DELETE RESTRICT,
    recorded_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_ewms_equipment_interchange_type CHECK (
        interchange_type IN ('PICKUP','GATE_OUT','GATE_IN','RETURN','TRANSFER','INSPECTION')
    ),
    CONSTRAINT ck_ewms_equipment_interchange_meter CHECK (meter_reading IS NULL OR meter_reading >= 0)
);

CREATE TABLE IF NOT EXISTS ewms.container_free_time_terms (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    carrier_booking_id uuid REFERENCES ewms.carrier_bookings(id) ON DELETE RESTRICT,
    trade_shipment_id uuid REFERENCES ewms.trade_shipments(id) ON DELETE RESTRICT,
    container_id uuid REFERENCES ewms.trade_containers(id) ON DELETE RESTRICT,
    charge_type varchar(20) NOT NULL,
    start_event_type varchar(50) NOT NULL,
    free_days integer NOT NULL,
    calendar_type varchar(20) NOT NULL DEFAULT 'CALENDAR',
    valid_from date,
    valid_to date,
    source_reference varchar(200),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_ewms_container_free_time_parent CHECK (
        num_nonnulls(carrier_booking_id, trade_shipment_id, container_id) >= 1
    ),
    CONSTRAINT ck_ewms_container_free_time_type CHECK (
        charge_type IN ('DEMURRAGE','DETENTION','STORAGE','PLUG_IN','OTHER')
    ),
    CONSTRAINT ck_ewms_container_free_time_days CHECK (free_days >= 0),
    CONSTRAINT ck_ewms_container_free_time_calendar CHECK (calendar_type IN ('CALENDAR','BUSINESS')),
    CONSTRAINT ck_ewms_container_free_time_dates CHECK (valid_to IS NULL OR valid_from IS NULL OR valid_to >= valid_from)
);

CREATE TABLE IF NOT EXISTS ewms.container_free_time_events (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    free_time_term_id uuid NOT NULL REFERENCES ewms.container_free_time_terms(id) ON DELETE RESTRICT,
    event_type varchar(50) NOT NULL,
    occurred_at timestamptz NOT NULL,
    chargeable_days integer NOT NULL DEFAULT 0,
    amount numeric(24,4) NOT NULL DEFAULT 0,
    currency_code char(3) REFERENCES ewms.currencies(currency_code),
    source_event_id uuid,
    recorded_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_ewms_container_free_time_event_days CHECK (chargeable_days >= 0),
    CONSTRAINT ck_ewms_container_free_time_event_amount CHECK (amount >= 0)
);

-- -----------------------------------------------------------------------------
-- Customs valuation, classification, guarantees, and duty drawback
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS ewms.customs_valuations (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    customs_declaration_version_id uuid NOT NULL UNIQUE
        REFERENCES ewms.customs_declaration_versions(id) ON DELETE RESTRICT,
    valuation_method varchar(20) NOT NULL,
    invoice_currency_code char(3) NOT NULL REFERENCES ewms.currencies(currency_code),
    invoice_amount numeric(24,4) NOT NULL DEFAULT 0,
    exchange_rate numeric(24,12) NOT NULL,
    customs_currency_code char(3) NOT NULL REFERENCES ewms.currencies(currency_code),
    freight_amount numeric(24,4) NOT NULL DEFAULT 0,
    insurance_amount numeric(24,4) NOT NULL DEFAULT 0,
    assists_amount numeric(24,4) NOT NULL DEFAULT 0,
    royalty_amount numeric(24,4) NOT NULL DEFAULT 0,
    selling_commission_amount numeric(24,4) NOT NULL DEFAULT 0,
    packing_amount numeric(24,4) NOT NULL DEFAULT 0,
    other_addition_amount numeric(24,4) NOT NULL DEFAULT 0,
    deduction_amount numeric(24,4) NOT NULL DEFAULT 0,
    declared_customs_value numeric(24,4) NOT NULL,
    valuation_basis text,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    sealed_at timestamptz,
    sealed_by uuid REFERENCES ewms.users(id),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_customs_valuation_method CHECK (
        valuation_method IN ('METHOD_1','METHOD_2','METHOD_3','METHOD_4','METHOD_5','METHOD_6')
    ),
    CONSTRAINT ck_ewms_customs_valuation_rate CHECK (exchange_rate > 0),
    CONSTRAINT ck_ewms_customs_valuation_amounts CHECK (
        invoice_amount >= 0 AND freight_amount >= 0 AND insurance_amount >= 0 AND
        assists_amount >= 0 AND royalty_amount >= 0 AND selling_commission_amount >= 0 AND
        packing_amount >= 0 AND other_addition_amount >= 0 AND deduction_amount >= 0 AND
        declared_customs_value >= 0
    ),
    CONSTRAINT ck_ewms_customs_valuation_status CHECK (
        status IN ('DRAFT','SEALED','ASSESSED','SUPERSEDED','CANCELLED')
    ),
    CONSTRAINT ck_ewms_customs_valuation_seal CHECK (
        (status = 'DRAFT' AND sealed_at IS NULL AND sealed_by IS NULL) OR
        (status <> 'DRAFT' AND sealed_at IS NOT NULL AND sealed_by IS NOT NULL)
    )
);

CREATE TABLE IF NOT EXISTS ewms.customs_valuation_adjustments (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    customs_valuation_id uuid NOT NULL REFERENCES ewms.customs_valuations(id) ON DELETE CASCADE,
    customs_declaration_line_id uuid REFERENCES ewms.customs_declaration_lines(id) ON DELETE RESTRICT,
    adjustment_no integer NOT NULL,
    adjustment_type varchar(20) NOT NULL,
    adjustment_code varchar(80) NOT NULL,
    amount numeric(24,4) NOT NULL,
    currency_code char(3) NOT NULL REFERENCES ewms.currencies(currency_code),
    calculation_basis text,
    evidence_file_id uuid REFERENCES ewms.files(id) ON DELETE RESTRICT,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (customs_valuation_id, adjustment_no),
    CONSTRAINT ck_ewms_customs_valuation_adjustment_no CHECK (adjustment_no > 0),
    CONSTRAINT ck_ewms_customs_valuation_adjustment_type CHECK (
        adjustment_type IN ('ADDITION','DEDUCTION')
    ),
    CONSTRAINT ck_ewms_customs_valuation_adjustment_amount CHECK (amount >= 0)
);

CREATE TABLE IF NOT EXISTS ewms.tariff_classification_cases (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    case_no varchar(120) NOT NULL,
    item_id uuid NOT NULL REFERENCES ewms.items(id),
    owner_partner_id uuid REFERENCES ewms.business_partners(id),
    requesting_organization_id uuid REFERENCES ewms.organizations(id),
    country_code char(2) NOT NULL REFERENCES ewms.countries(country_code),
    nomenclature_version varchar(20) NOT NULL,
    goods_description text NOT NULL,
    technical_description text,
    requested_hs_code varchar(20),
    status varchar(30) NOT NULL DEFAULT 'DRAFT',
    assigned_user_id uuid REFERENCES ewms.users(id),
    submitted_at timestamptz,
    closed_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, case_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_tariff_classification_status CHECK (
        status IN ('DRAFT','UNDER_REVIEW','SUBMITTED','DECIDED','REJECTED','WITHDRAWN','EXPIRED')
    )
);

CREATE TABLE IF NOT EXISTS ewms.tariff_classification_decisions (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    classification_case_id uuid NOT NULL REFERENCES ewms.tariff_classification_cases(id) ON DELETE RESTRICT,
    decision_no varchar(150),
    decision_source varchar(30) NOT NULL,
    hs_country_code char(2) NOT NULL,
    hs_nomenclature_version varchar(20) NOT NULL,
    hs_code varchar(20) NOT NULL,
    rationale text NOT NULL,
    issuing_authority varchar(200),
    effective_from date NOT NULL,
    effective_to date,
    decided_at timestamptz NOT NULL,
    decided_by uuid REFERENCES ewms.users(id),
    status varchar(20) NOT NULL DEFAULT 'FINAL',
    supersedes_id uuid REFERENCES ewms.tariff_classification_decisions(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (classification_case_id, decision_no),
    FOREIGN KEY (hs_country_code, hs_nomenclature_version, hs_code)
        REFERENCES ewms.hs_codes(country_code, nomenclature_version, hs_code),
    CONSTRAINT ck_ewms_tariff_classification_source CHECK (
        decision_source IN ('INTERNAL','CUSTOMS_RULING','BROKER_ADVICE','COURT','OTHER')
    ),
    CONSTRAINT ck_ewms_tariff_classification_decision_status CHECK (
        status IN ('FINAL','SUPERSEDED','REVOKED','EXPIRED')
    ),
    CONSTRAINT ck_ewms_tariff_classification_decision_dates CHECK (
        effective_to IS NULL OR effective_to >= effective_from
    )
);

CREATE TABLE IF NOT EXISTS ewms.customs_guarantees (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    guarantee_no varchar(150) NOT NULL,
    guarantee_type varchar(30) NOT NULL,
    principal_partner_id uuid NOT NULL REFERENCES ewms.business_partners(id),
    guarantor_partner_id uuid NOT NULL REFERENCES ewms.business_partners(id),
    beneficiary_partner_id uuid REFERENCES ewms.business_partners(id),
    customs_office_code varchar(20) REFERENCES ewms.customs_offices(customs_office_code),
    currency_code char(3) NOT NULL REFERENCES ewms.currencies(currency_code),
    guarantee_limit numeric(24,4) NOT NULL,
    utilized_amount numeric(24,4) NOT NULL DEFAULT 0,
    valid_from date NOT NULL,
    valid_to date NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    instrument_file_id uuid REFERENCES ewms.files(id) ON DELETE RESTRICT,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, guarantee_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_customs_guarantee_type CHECK (
        guarantee_type IN ('SINGLE','CONTINUOUS','TRANSIT','WAREHOUSE','TEMPORARY_IMPORT','OTHER')
    ),
    CONSTRAINT ck_ewms_customs_guarantee_amount CHECK (
        guarantee_limit > 0 AND utilized_amount >= 0 AND utilized_amount <= guarantee_limit
    ),
    CONSTRAINT ck_ewms_customs_guarantee_dates CHECK (valid_to >= valid_from),
    CONSTRAINT ck_ewms_customs_guarantee_status CHECK (
        status IN ('DRAFT','ACTIVE','SUSPENDED','EXHAUSTED','EXPIRED','RELEASED','CANCELLED')
    )
);

CREATE TABLE IF NOT EXISTS ewms.customs_guarantee_usages (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    customs_guarantee_id uuid NOT NULL REFERENCES ewms.customs_guarantees(id) ON DELETE RESTRICT,
    customs_declaration_id uuid REFERENCES ewms.customs_declarations(id) ON DELETE RESTRICT,
    bonded_transport_order_id uuid REFERENCES ewms.bonded_transport_orders(id) ON DELETE RESTRICT,
    usage_type varchar(20) NOT NULL,
    usage_amount numeric(24,4) NOT NULL,
    currency_code char(3) NOT NULL REFERENCES ewms.currencies(currency_code),
    utilized_at timestamptz NOT NULL,
    released_at timestamptz,
    status varchar(20) NOT NULL DEFAULT 'UTILIZED',
    recorded_by uuid REFERENCES ewms.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_ewms_customs_guarantee_usage_parent CHECK (
        num_nonnulls(customs_declaration_id, bonded_transport_order_id) = 1
    ),
    CONSTRAINT ck_ewms_customs_guarantee_usage_type CHECK (
        usage_type IN ('RESERVE','UTILIZE','RELEASE','FORFEIT','ADJUST')
    ),
    CONSTRAINT ck_ewms_customs_guarantee_usage_amount CHECK (usage_amount > 0),
    CONSTRAINT ck_ewms_customs_guarantee_usage_status CHECK (
        status IN ('RESERVED','UTILIZED','RELEASED','FORFEITED','CANCELLED')
    ),
    CONSTRAINT ck_ewms_customs_guarantee_usage_dates CHECK (
        released_at IS NULL OR released_at >= utilized_at
    )
);

CREATE TABLE IF NOT EXISTS ewms.duty_drawback_claims (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    claim_no varchar(150) NOT NULL,
    claimant_partner_id uuid NOT NULL REFERENCES ewms.business_partners(id),
    claim_type varchar(30) NOT NULL,
    claim_period_from date,
    claim_period_to date,
    currency_code char(3) NOT NULL REFERENCES ewms.currencies(currency_code),
    claimed_amount numeric(24,4) NOT NULL DEFAULT 0,
    approved_amount numeric(24,4) NOT NULL DEFAULT 0,
    paid_amount numeric(24,4) NOT NULL DEFAULT 0,
    customs_office_code varchar(20) REFERENCES ewms.customs_offices(customs_office_code),
    submission_no varchar(150),
    status varchar(30) NOT NULL DEFAULT 'DRAFT',
    submitted_at timestamptz,
    approved_at timestamptz,
    paid_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_by uuid REFERENCES ewms.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, claim_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_duty_drawback_type CHECK (
        claim_type IN ('INDIVIDUAL','FIXED_RATE','REEXPORT','RETURN','OVERPAYMENT','OTHER')
    ),
    CONSTRAINT ck_ewms_duty_drawback_amount CHECK (
        claimed_amount >= 0 AND approved_amount >= 0 AND paid_amount >= 0 AND
        approved_amount <= claimed_amount AND paid_amount <= approved_amount
    ),
    CONSTRAINT ck_ewms_duty_drawback_dates CHECK (
        claim_period_to IS NULL OR claim_period_from IS NULL OR claim_period_to >= claim_period_from
    ),
    CONSTRAINT ck_ewms_duty_drawback_status CHECK (status IN (
        'DRAFT','VALIDATED','SUBMITTED','UNDER_REVIEW','SUPPLEMENT_REQUIRED','APPROVED',
        'PARTIALLY_APPROVED','REJECTED','PAID','CANCELLED','CLOSED'
    ))
);

CREATE TABLE IF NOT EXISTS ewms.duty_drawback_source_imports (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    drawback_claim_id uuid NOT NULL REFERENCES ewms.duty_drawback_claims(id) ON DELETE RESTRICT,
    import_declaration_line_id uuid NOT NULL REFERENCES ewms.customs_declaration_lines(id) ON DELETE RESTRICT,
    duty_payment_allocation_id uuid REFERENCES ewms.customs_duty_payment_allocations(id) ON DELETE RESTRICT,
    eligible_quantity numeric(24,8) NOT NULL,
    allocated_quantity numeric(24,8) NOT NULL,
    uom_code varchar(20) NOT NULL REFERENCES ewms.units_of_measure(uom_code),
    eligible_duty_amount numeric(24,4) NOT NULL,
    allocated_duty_amount numeric(24,4) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (drawback_claim_id, import_declaration_line_id, duty_payment_allocation_id),
    CONSTRAINT ck_ewms_drawback_source_import_qty CHECK (
        eligible_quantity > 0 AND allocated_quantity > 0 AND allocated_quantity <= eligible_quantity
    ),
    CONSTRAINT ck_ewms_drawback_source_import_amount CHECK (
        eligible_duty_amount >= 0 AND allocated_duty_amount >= 0 AND allocated_duty_amount <= eligible_duty_amount
    )
);

CREATE TABLE IF NOT EXISTS ewms.duty_drawback_export_lines (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    drawback_claim_id uuid NOT NULL REFERENCES ewms.duty_drawback_claims(id) ON DELETE RESTRICT,
    export_fulfillment_evidence_id uuid NOT NULL
        REFERENCES ewms.export_fulfillment_evidence(id) ON DELETE RESTRICT,
    exported_quantity numeric(24,8) NOT NULL,
    uom_code varchar(20) NOT NULL REFERENCES ewms.units_of_measure(uom_code),
    claimed_duty_amount numeric(24,4) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (drawback_claim_id, export_fulfillment_evidence_id),
    CONSTRAINT ck_ewms_drawback_export_line_qty CHECK (exported_quantity > 0),
    CONSTRAINT ck_ewms_drawback_export_line_amount CHECK (claimed_duty_amount >= 0)
);

CREATE TABLE IF NOT EXISTS ewms.duty_drawback_events (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    drawback_claim_id uuid NOT NULL REFERENCES ewms.duty_drawback_claims(id) ON DELETE RESTRICT,
    sequence_no bigint NOT NULL,
    event_type varchar(80) NOT NULL,
    from_status varchar(30),
    to_status varchar(30),
    occurred_at timestamptz NOT NULL,
    recorded_by uuid REFERENCES ewms.users(id),
    recorded_at timestamptz NOT NULL DEFAULT now(),
    detail_masked jsonb NOT NULL DEFAULT '{}'::jsonb,
    UNIQUE (drawback_claim_id, sequence_no),
    CONSTRAINT ck_ewms_duty_drawback_event_seq CHECK (sequence_no > 0),
    CONSTRAINT ck_ewms_duty_drawback_event_masked CHECK (
        NOT ewms.jsonb_contains_forbidden_secret_key(detail_masked)
    )
);

-- -----------------------------------------------------------------------------
-- FTA, product origin, origin calculations, certificates, and verification
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS ewms.trade_agreements (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    agreement_code varchar(50) NOT NULL,
    agreement_name varchar(300) NOT NULL,
    agreement_type varchar(30) NOT NULL DEFAULT 'FTA',
    version_code varchar(50) NOT NULL,
    effective_from date NOT NULL,
    effective_to date,
    issuing_basis text,
    cumulation_type varchar(30),
    de_minimis_percent numeric(9,6),
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, agreement_code, version_code),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_trade_agreement_type CHECK (
        agreement_type IN ('FTA','PTA','CUSTOMS_UNION','UNILATERAL','OTHER')
    ),
    CONSTRAINT ck_ewms_trade_agreement_dates CHECK (effective_to IS NULL OR effective_to >= effective_from),
    CONSTRAINT ck_ewms_trade_agreement_de_minimis CHECK (
        de_minimis_percent IS NULL OR de_minimis_percent BETWEEN 0 AND 100
    ),
    CONSTRAINT ck_ewms_trade_agreement_status CHECK (status IN ('DRAFT','ACTIVE','SUSPENDED','EXPIRED','REPEALED'))
);

CREATE TABLE IF NOT EXISTS ewms.trade_agreement_members (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    trade_agreement_id uuid NOT NULL REFERENCES ewms.trade_agreements(id) ON DELETE CASCADE,
    country_code char(2) NOT NULL REFERENCES ewms.countries(country_code),
    member_role varchar(20) NOT NULL DEFAULT 'PARTY',
    effective_from date NOT NULL,
    effective_to date,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (trade_agreement_id, country_code, effective_from),
    CONSTRAINT ck_ewms_trade_agreement_member_role CHECK (
        member_role IN ('PARTY','BENEFICIARY','ASSOCIATE','EXCLUDED')
    ),
    CONSTRAINT ck_ewms_trade_agreement_member_dates CHECK (effective_to IS NULL OR effective_to >= effective_from)
);

CREATE TABLE IF NOT EXISTS ewms.origin_rule_sets (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    trade_agreement_id uuid NOT NULL REFERENCES ewms.trade_agreements(id) ON DELETE RESTRICT,
    rule_set_code varchar(80) NOT NULL,
    version_no integer NOT NULL,
    nomenclature_country_code char(2) NOT NULL REFERENCES ewms.countries(country_code),
    nomenclature_version varchar(20) NOT NULL,
    effective_from date NOT NULL,
    effective_to date,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    published_at timestamptz,
    published_by uuid REFERENCES ewms.users(id),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (trade_agreement_id, rule_set_code, version_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_origin_rule_set_version CHECK (version_no > 0),
    CONSTRAINT ck_ewms_origin_rule_set_dates CHECK (effective_to IS NULL OR effective_to >= effective_from),
    CONSTRAINT ck_ewms_origin_rule_set_status CHECK (
        status IN ('DRAFT','PUBLISHED','SUPERSEDED','EXPIRED','REVOKED')
    ),
    CONSTRAINT ck_ewms_origin_rule_set_publish CHECK (
        (status = 'DRAFT' AND published_at IS NULL AND published_by IS NULL) OR
        (status <> 'DRAFT' AND published_at IS NOT NULL AND published_by IS NOT NULL)
    )
);

CREATE TABLE IF NOT EXISTS ewms.origin_rules (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    origin_rule_set_id uuid NOT NULL REFERENCES ewms.origin_rule_sets(id) ON DELETE CASCADE,
    rule_code varchar(100) NOT NULL,
    hs_prefix varchar(20) NOT NULL,
    hs_digit_length smallint NOT NULL,
    rule_type varchar(30) NOT NULL,
    origin_criterion_code varchar(30),
    rvc_method varchar(30),
    threshold_percent numeric(9,6),
    tariff_shift_level varchar(10),
    specific_process text,
    de_minimis_percent numeric(9,6),
    allows_bilateral_cumulation boolean NOT NULL DEFAULT false,
    allows_diagonal_cumulation boolean NOT NULL DEFAULT false,
    effective_from date NOT NULL,
    effective_to date,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (origin_rule_set_id, rule_code),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_origin_rule_hs_digits CHECK (hs_digit_length BETWEEN 2 AND 20),
    CONSTRAINT ck_ewms_origin_rule_type CHECK (
        rule_type IN ('WO','CC','CTH','CTSH','RVC','SPECIFIC_PROCESS','COMBINATION')
    ),
    CONSTRAINT ck_ewms_origin_rule_threshold CHECK (
        threshold_percent IS NULL OR threshold_percent BETWEEN 0 AND 100
    ),
    CONSTRAINT ck_ewms_origin_rule_de_minimis CHECK (
        de_minimis_percent IS NULL OR de_minimis_percent BETWEEN 0 AND 100
    ),
    CONSTRAINT ck_ewms_origin_rule_dates CHECK (effective_to IS NULL OR effective_to >= effective_from)
);

CREATE TABLE IF NOT EXISTS ewms.origin_rule_conditions (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    origin_rule_id uuid NOT NULL REFERENCES ewms.origin_rules(id) ON DELETE CASCADE,
    condition_no integer NOT NULL,
    condition_type varchar(30) NOT NULL,
    operator_code varchar(20) NOT NULL,
    comparison_value varchar(300),
    numeric_value numeric(24,8),
    percent_value numeric(9,6),
    notes text,
    UNIQUE (origin_rule_id, condition_no),
    CONSTRAINT ck_ewms_origin_rule_condition_no CHECK (condition_no > 0),
    CONSTRAINT ck_ewms_origin_rule_condition_type CHECK (
        condition_type IN ('HS_CHANGE','RVC','VALUE','WEIGHT','PROCESS','ORIGIN','EXCLUSION','OTHER')
    ),
    CONSTRAINT ck_ewms_origin_rule_condition_operator CHECK (
        operator_code IN ('EQ','NE','GT','GE','LT','LE','IN','NOT_IN','MATCH','EXISTS')
    ),
    CONSTRAINT ck_ewms_origin_rule_condition_percent CHECK (
        percent_value IS NULL OR percent_value BETWEEN 0 AND 100
    )
);

CREATE TABLE IF NOT EXISTS ewms.item_hs_classifications (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    item_id uuid NOT NULL REFERENCES ewms.items(id) ON DELETE RESTRICT,
    country_code char(2) NOT NULL,
    nomenclature_version varchar(20) NOT NULL,
    hs_code varchar(20) NOT NULL,
    classification_source varchar(30) NOT NULL,
    tariff_decision_id uuid REFERENCES ewms.tariff_classification_decisions(id),
    confidence_percent numeric(9,6),
    valid_from date NOT NULL,
    valid_to date,
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    approved_by uuid REFERENCES ewms.users(id),
    approved_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, item_id, country_code, nomenclature_version, hs_code, valid_from),
    FOREIGN KEY (country_code, nomenclature_version, hs_code)
        REFERENCES ewms.hs_codes(country_code, nomenclature_version, hs_code),
    CONSTRAINT ck_ewms_item_hs_classification_source CHECK (
        classification_source IN ('INTERNAL','CUSTOMS_RULING','BROKER','SUPPLIER','SYSTEM','OTHER')
    ),
    CONSTRAINT ck_ewms_item_hs_classification_confidence CHECK (
        confidence_percent IS NULL OR confidence_percent BETWEEN 0 AND 100
    ),
    CONSTRAINT ck_ewms_item_hs_classification_dates CHECK (valid_to IS NULL OR valid_to >= valid_from),
    CONSTRAINT ck_ewms_item_hs_classification_status CHECK (
        status IN ('DRAFT','ACTIVE','SUSPENDED','SUPERSEDED','EXPIRED')
    )
);

CREATE TABLE IF NOT EXISTS ewms.item_origins (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    item_id uuid NOT NULL REFERENCES ewms.items(id) ON DELETE RESTRICT,
    owner_partner_id uuid REFERENCES ewms.business_partners(id),
    manufacturer_partner_id uuid REFERENCES ewms.business_partners(id),
    country_of_origin char(2) NOT NULL REFERENCES ewms.countries(country_code),
    origin_basis varchar(30) NOT NULL,
    trade_agreement_id uuid REFERENCES ewms.trade_agreements(id),
    valid_from date NOT NULL,
    valid_to date,
    evidence_file_id uuid REFERENCES ewms.files(id) ON DELETE RESTRICT,
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, item_id, country_of_origin, origin_basis, valid_from),
    CONSTRAINT ck_ewms_item_origin_basis CHECK (
        origin_basis IN ('MANUFACTURED','SUPPLIER_DECLARATION','CALCULATION','CERTIFICATE','DEFAULT','OTHER')
    ),
    CONSTRAINT ck_ewms_item_origin_dates CHECK (valid_to IS NULL OR valid_to >= valid_from),
    CONSTRAINT ck_ewms_item_origin_status CHECK (status IN ('DRAFT','ACTIVE','SUSPENDED','EXPIRED','REVOKED'))
);

CREATE TABLE IF NOT EXISTS ewms.supplier_origin_declarations (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    declaration_no varchar(150) NOT NULL,
    supplier_partner_id uuid NOT NULL REFERENCES ewms.business_partners(id),
    issuing_country_code char(2) REFERENCES ewms.countries(country_code),
    trade_agreement_id uuid REFERENCES ewms.trade_agreements(id),
    declaration_type varchar(30) NOT NULL,
    issue_date date NOT NULL,
    valid_from date NOT NULL,
    valid_to date NOT NULL,
    trade_document_id uuid REFERENCES ewms.trade_documents(id) ON DELETE RESTRICT,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    verified_by uuid REFERENCES ewms.users(id),
    verified_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, supplier_partner_id, declaration_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_supplier_origin_declaration_type CHECK (
        declaration_type IN ('SINGLE','LONG_TERM','MANUFACTURER','AFFIDAVIT','OTHER')
    ),
    CONSTRAINT ck_ewms_supplier_origin_declaration_dates CHECK (valid_to >= valid_from),
    CONSTRAINT ck_ewms_supplier_origin_declaration_status CHECK (
        status IN ('DRAFT','RECEIVED','VERIFIED','REJECTED','EXPIRED','REVOKED')
    )
);

CREATE TABLE IF NOT EXISTS ewms.supplier_origin_declaration_lines (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    supplier_origin_declaration_id uuid NOT NULL
        REFERENCES ewms.supplier_origin_declarations(id) ON DELETE CASCADE,
    line_no integer NOT NULL,
    item_id uuid NOT NULL REFERENCES ewms.items(id),
    supplier_item_code varchar(120),
    hs_code varchar(20),
    origin_country_code char(2) NOT NULL REFERENCES ewms.countries(country_code),
    origin_criterion_code varchar(30),
    producer_flag varchar(20),
    qualifying boolean,
    notes text,
    UNIQUE (supplier_origin_declaration_id, line_no),
    UNIQUE (supplier_origin_declaration_id, item_id),
    CONSTRAINT ck_ewms_supplier_origin_declaration_line_no CHECK (line_no > 0),
    CONSTRAINT ck_ewms_supplier_origin_declaration_producer CHECK (
        producer_flag IS NULL OR producer_flag IN ('PRODUCER','NON_PRODUCER','UNKNOWN')
    )
);

CREATE TABLE IF NOT EXISTS ewms.origin_calculations (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    calculation_no varchar(150) NOT NULL,
    item_id uuid NOT NULL REFERENCES ewms.items(id),
    owner_partner_id uuid REFERENCES ewms.business_partners(id),
    bill_of_material_id uuid REFERENCES ewms.bill_of_materials(id),
    trade_agreement_id uuid NOT NULL REFERENCES ewms.trade_agreements(id),
    origin_rule_id uuid NOT NULL REFERENCES ewms.origin_rules(id),
    calculation_date date NOT NULL,
    production_period_from date,
    production_period_to date,
    currency_code char(3) NOT NULL REFERENCES ewms.currencies(currency_code),
    exw_value numeric(24,4),
    fob_value numeric(24,4),
    net_cost_value numeric(24,4),
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    sealed_at timestamptz,
    sealed_by uuid REFERENCES ewms.users(id),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, calculation_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_origin_calculation_period CHECK (
        production_period_to IS NULL OR production_period_from IS NULL OR production_period_to >= production_period_from
    ),
    CONSTRAINT ck_ewms_origin_calculation_values CHECK (
        (exw_value IS NULL OR exw_value >= 0) AND
        (fob_value IS NULL OR fob_value >= 0) AND
        (net_cost_value IS NULL OR net_cost_value >= 0)
    ),
    CONSTRAINT ck_ewms_origin_calculation_status CHECK (
        status IN ('DRAFT','CALCULATED','REVIEWED','SEALED','SUPERSEDED','CANCELLED')
    ),
    CONSTRAINT ck_ewms_origin_calculation_seal CHECK (
        (status IN ('DRAFT','CALCULATED','REVIEWED') AND sealed_at IS NULL AND sealed_by IS NULL) OR
        (status IN ('SEALED','SUPERSEDED','CANCELLED') AND sealed_at IS NOT NULL AND sealed_by IS NOT NULL)
    )
);

CREATE TABLE IF NOT EXISTS ewms.origin_calculation_materials (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    origin_calculation_id uuid NOT NULL REFERENCES ewms.origin_calculations(id) ON DELETE CASCADE,
    line_no integer NOT NULL,
    component_item_id uuid REFERENCES ewms.items(id),
    material_description varchar(500) NOT NULL,
    hs_code varchar(20),
    origin_country_code char(2) REFERENCES ewms.countries(country_code),
    originating_status varchar(20) NOT NULL DEFAULT 'UNKNOWN',
    quantity numeric(24,8) NOT NULL,
    uom_code varchar(20) NOT NULL REFERENCES ewms.units_of_measure(uom_code),
    unit_value numeric(24,8),
    total_value numeric(24,4) NOT NULL DEFAULT 0,
    supplier_declaration_line_id uuid
        REFERENCES ewms.supplier_origin_declaration_lines(id) ON DELETE RESTRICT,
    UNIQUE (origin_calculation_id, line_no),
    CONSTRAINT ck_ewms_origin_calculation_material_line CHECK (line_no > 0),
    CONSTRAINT ck_ewms_origin_calculation_material_status CHECK (
        originating_status IN ('ORIGINATING','NON_ORIGINATING','UNKNOWN')
    ),
    CONSTRAINT ck_ewms_origin_calculation_material_values CHECK (
        quantity > 0 AND (unit_value IS NULL OR unit_value >= 0) AND total_value >= 0
    )
);

CREATE TABLE IF NOT EXISTS ewms.origin_calculation_results (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    origin_calculation_id uuid NOT NULL REFERENCES ewms.origin_calculations(id) ON DELETE RESTRICT,
    result_no integer NOT NULL DEFAULT 1,
    rule_type varchar(30) NOT NULL,
    originating_material_value numeric(24,4) NOT NULL DEFAULT 0,
    non_originating_material_value numeric(24,4) NOT NULL DEFAULT 0,
    regional_value_content_percent numeric(12,8),
    threshold_percent numeric(9,6),
    tariff_shift_passed boolean,
    specific_process_passed boolean,
    overall_result varchar(20) NOT NULL,
    determination_reason text,
    calculated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (origin_calculation_id, result_no),
    CONSTRAINT ck_ewms_origin_calculation_result_no CHECK (result_no > 0),
    CONSTRAINT ck_ewms_origin_calculation_result_values CHECK (
        originating_material_value >= 0 AND non_originating_material_value >= 0 AND
        (regional_value_content_percent IS NULL OR regional_value_content_percent BETWEEN 0 AND 100) AND
        (threshold_percent IS NULL OR threshold_percent BETWEEN 0 AND 100)
    ),
    CONSTRAINT ck_ewms_origin_calculation_result CHECK (
        overall_result IN ('PASS','FAIL','UNKNOWN','NOT_APPLICABLE')
    )
);

CREATE TABLE IF NOT EXISTS ewms.origin_determinations (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    item_id uuid NOT NULL REFERENCES ewms.items(id),
    lot_id uuid REFERENCES ewms.inventory_lots(id),
    trade_agreement_id uuid NOT NULL REFERENCES ewms.trade_agreements(id),
    origin_calculation_id uuid REFERENCES ewms.origin_calculations(id) ON DELETE RESTRICT,
    country_of_origin char(2) NOT NULL REFERENCES ewms.countries(country_code),
    origin_criterion_code varchar(30),
    determination_result varchar(20) NOT NULL,
    qualifying_quantity numeric(24,8),
    uom_code varchar(20) REFERENCES ewms.units_of_measure(uom_code),
    valid_from date NOT NULL,
    valid_to date,
    determined_by uuid REFERENCES ewms.users(id),
    determined_at timestamptz NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    supersedes_id uuid REFERENCES ewms.origin_determinations(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, item_id, trade_agreement_id, valid_from, lot_id),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_origin_determination_result CHECK (
        determination_result IN ('PASS','FAIL','UNKNOWN')
    ),
    CONSTRAINT ck_ewms_origin_determination_qty CHECK (
        qualifying_quantity IS NULL OR qualifying_quantity > 0
    ),
    CONSTRAINT ck_ewms_origin_determination_dates CHECK (valid_to IS NULL OR valid_to >= valid_from),
    CONSTRAINT ck_ewms_origin_determination_status CHECK (
        status IN ('ACTIVE','SUSPENDED','SUPERSEDED','EXPIRED','REVOKED')
    )
);

CREATE TABLE IF NOT EXISTS ewms.origin_certificates (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    certificate_no varchar(180) NOT NULL,
    certificate_type varchar(30) NOT NULL,
    trade_agreement_id uuid NOT NULL REFERENCES ewms.trade_agreements(id),
    exporter_partner_id uuid NOT NULL REFERENCES ewms.business_partners(id),
    importer_partner_id uuid REFERENCES ewms.business_partners(id),
    producer_partner_id uuid REFERENCES ewms.business_partners(id),
    issuing_authority_partner_id uuid REFERENCES ewms.business_partners(id),
    country_of_export char(2) NOT NULL REFERENCES ewms.countries(country_code),
    country_of_import char(2) NOT NULL REFERENCES ewms.countries(country_code),
    issue_date date NOT NULL,
    valid_from date NOT NULL,
    valid_to date NOT NULL,
    trade_document_id uuid REFERENCES ewms.trade_documents(id) ON DELETE RESTRICT,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    issued_at timestamptz,
    cancelled_at timestamptz,
    cancellation_reason text,
    row_version bigint NOT NULL DEFAULT 1,
    created_by uuid REFERENCES ewms.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, certificate_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_origin_certificate_type CHECK (
        certificate_type IN ('AUTHORITY','APPROVED_EXPORTER','SELF_CERTIFICATION','INVOICE_DECLARATION','OTHER')
    ),
    CONSTRAINT ck_ewms_origin_certificate_dates CHECK (valid_to >= valid_from),
    CONSTRAINT ck_ewms_origin_certificate_status CHECK (
        status IN ('DRAFT','ISSUED','AMENDED','CANCELLED','EXPIRED','REVOKED')
    ),
    CONSTRAINT ck_ewms_origin_certificate_issue CHECK (
        (status = 'DRAFT' AND issued_at IS NULL) OR (status <> 'DRAFT' AND issued_at IS NOT NULL)
    )
);

CREATE TABLE IF NOT EXISTS ewms.origin_certificate_lines (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    origin_certificate_id uuid NOT NULL REFERENCES ewms.origin_certificates(id) ON DELETE RESTRICT,
    line_no integer NOT NULL,
    trade_case_item_id uuid REFERENCES ewms.trade_case_items(id) ON DELETE RESTRICT,
    commercial_invoice_line_id uuid REFERENCES ewms.commercial_invoice_lines(id) ON DELETE RESTRICT,
    origin_determination_id uuid NOT NULL REFERENCES ewms.origin_determinations(id) ON DELETE RESTRICT,
    item_id uuid NOT NULL REFERENCES ewms.items(id),
    goods_description varchar(1000) NOT NULL,
    hs_code varchar(20) NOT NULL,
    origin_country_code char(2) NOT NULL REFERENCES ewms.countries(country_code),
    origin_criterion_code varchar(30),
    certified_quantity numeric(24,8) NOT NULL,
    used_quantity numeric(24,8) NOT NULL DEFAULT 0,
    uom_code varchar(20) NOT NULL REFERENCES ewms.units_of_measure(uom_code),
    gross_weight numeric(24,8),
    weight_uom_code varchar(20) REFERENCES ewms.units_of_measure(uom_code),
    UNIQUE (origin_certificate_id, line_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_origin_certificate_line_no CHECK (line_no > 0),
    CONSTRAINT ck_ewms_origin_certificate_line_qty CHECK (
        certified_quantity > 0 AND used_quantity >= 0 AND used_quantity <= certified_quantity AND
        (gross_weight IS NULL OR gross_weight >= 0)
    )
);

CREATE TABLE IF NOT EXISTS ewms.origin_certificate_uses (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    origin_certificate_line_id uuid NOT NULL REFERENCES ewms.origin_certificate_lines(id) ON DELETE RESTRICT,
    customs_declaration_line_id uuid NOT NULL REFERENCES ewms.customs_declaration_lines(id) ON DELETE RESTRICT,
    used_quantity numeric(24,8) NOT NULL,
    uom_code varchar(20) NOT NULL REFERENCES ewms.units_of_measure(uom_code),
    preference_amount numeric(24,4),
    currency_code char(3) REFERENCES ewms.currencies(currency_code),
    usage_status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    used_at timestamptz NOT NULL,
    reversed_at timestamptz,
    reversal_reason text,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (origin_certificate_line_id, customs_declaration_line_id),
    CONSTRAINT ck_ewms_origin_certificate_use_qty CHECK (used_quantity > 0),
    CONSTRAINT ck_ewms_origin_certificate_use_amount CHECK (preference_amount IS NULL OR preference_amount >= 0),
    CONSTRAINT ck_ewms_origin_certificate_use_status CHECK (
        usage_status IN ('ACTIVE','REVERSED','REJECTED')
    )
);

CREATE TABLE IF NOT EXISTS ewms.origin_certificate_events (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    origin_certificate_id uuid NOT NULL REFERENCES ewms.origin_certificates(id) ON DELETE RESTRICT,
    sequence_no bigint NOT NULL,
    event_type varchar(80) NOT NULL,
    from_status varchar(20),
    to_status varchar(20),
    occurred_at timestamptz NOT NULL,
    recorded_by uuid REFERENCES ewms.users(id),
    recorded_at timestamptz NOT NULL DEFAULT now(),
    detail_masked jsonb NOT NULL DEFAULT '{}'::jsonb,
    UNIQUE (origin_certificate_id, sequence_no),
    CONSTRAINT ck_ewms_origin_certificate_event_seq CHECK (sequence_no > 0),
    CONSTRAINT ck_ewms_origin_certificate_event_masked CHECK (
        NOT ewms.jsonb_contains_forbidden_secret_key(detail_masked)
    )
);

CREATE TABLE IF NOT EXISTS ewms.origin_verification_cases (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    verification_no varchar(150) NOT NULL,
    origin_certificate_id uuid REFERENCES ewms.origin_certificates(id) ON DELETE RESTRICT,
    customs_declaration_id uuid REFERENCES ewms.customs_declarations(id) ON DELETE RESTRICT,
    requesting_authority varchar(200),
    verification_type varchar(30) NOT NULL,
    request_date date NOT NULL,
    response_due_date date,
    status varchar(30) NOT NULL DEFAULT 'OPEN',
    assigned_user_id uuid REFERENCES ewms.users(id),
    result varchar(20),
    closed_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, verification_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_origin_verification_parent CHECK (
        num_nonnulls(origin_certificate_id, customs_declaration_id) >= 1
    ),
    CONSTRAINT ck_ewms_origin_verification_type CHECK (
        verification_type IN ('DOCUMENTARY','DESK_REVIEW','SITE_VISIT','AUTHORITY_REQUEST','RANDOM','OTHER')
    ),
    CONSTRAINT ck_ewms_origin_verification_dates CHECK (
        response_due_date IS NULL OR response_due_date >= request_date
    ),
    CONSTRAINT ck_ewms_origin_verification_status CHECK (
        status IN ('OPEN','EVIDENCE_REQUESTED','EVIDENCE_SUBMITTED','UNDER_REVIEW','SITE_VISIT',
                   'CONFIRMED','DENIED','WITHDRAWN','CLOSED')
    ),
    CONSTRAINT ck_ewms_origin_verification_result CHECK (
        result IS NULL OR result IN ('PASS','FAIL','PARTIAL','INCONCLUSIVE')
    )
);

CREATE TABLE IF NOT EXISTS ewms.origin_verification_findings (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    origin_verification_case_id uuid NOT NULL REFERENCES ewms.origin_verification_cases(id) ON DELETE CASCADE,
    finding_no integer NOT NULL,
    finding_type varchar(30) NOT NULL,
    severity varchar(20) NOT NULL,
    description text NOT NULL,
    corrective_action text,
    due_date date,
    resolved_at timestamptz,
    resolved_by uuid REFERENCES ewms.users(id),
    evidence_file_id uuid REFERENCES ewms.files(id) ON DELETE RESTRICT,
    UNIQUE (origin_verification_case_id, finding_no),
    CONSTRAINT ck_ewms_origin_verification_finding_no CHECK (finding_no > 0),
    CONSTRAINT ck_ewms_origin_verification_finding_type CHECK (
        finding_type IN ('DOCUMENT','CLASSIFICATION','ORIGIN','VALUE','QUANTITY','PROCESS','RECORD_KEEPING','OTHER')
    ),
    CONSTRAINT ck_ewms_origin_verification_finding_severity CHECK (
        severity IN ('LOW','MEDIUM','HIGH','CRITICAL')
    )
);

-- -----------------------------------------------------------------------------
-- Sanctions screening, strategic goods, licenses, quotas, and regulatory permits
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS ewms.compliance_list_sources (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    source_code varchar(80) NOT NULL,
    source_name varchar(300) NOT NULL,
    authority_name varchar(300),
    jurisdiction_country_code char(2) REFERENCES ewms.countries(country_code),
    list_type varchar(30) NOT NULL,
    source_uri text,
    update_frequency varchar(30),
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, source_code),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_compliance_list_source_type CHECK (
        list_type IN ('SANCTIONS','DENIED_PARTY','PEP','VESSEL','BANK','COUNTRY','EXPORT_CONTROL','OTHER')
    )
);

CREATE TABLE IF NOT EXISTS ewms.compliance_list_versions (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    compliance_list_source_id uuid NOT NULL REFERENCES ewms.compliance_list_sources(id) ON DELETE RESTRICT,
    version_code varchar(120) NOT NULL,
    published_at timestamptz,
    effective_at timestamptz NOT NULL,
    imported_at timestamptz NOT NULL DEFAULT now(),
    source_object_uri text,
    source_sha256 char(64) NOT NULL,
    source_byte_size bigint,
    record_count bigint NOT NULL DEFAULT 0,
    status varchar(20) NOT NULL DEFAULT 'LOADED',
    supersedes_id uuid REFERENCES ewms.compliance_list_versions(id),
    created_by uuid REFERENCES ewms.users(id),
    UNIQUE (compliance_list_source_id, version_code),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_compliance_list_version_hash CHECK (
        source_sha256 ~ '^[0-9A-Fa-f]{64}$'
    ),
    CONSTRAINT ck_ewms_compliance_list_version_size CHECK (
        source_byte_size IS NULL OR source_byte_size >= 0
    ),
    CONSTRAINT ck_ewms_compliance_list_version_count CHECK (record_count >= 0),
    CONSTRAINT ck_ewms_compliance_list_version_status CHECK (
        status IN ('LOADING','LOADED','ACTIVE','SUPERSEDED','REJECTED','ARCHIVED')
    )
);

CREATE TABLE IF NOT EXISTS ewms.compliance_list_entries (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    compliance_list_version_id uuid NOT NULL REFERENCES ewms.compliance_list_versions(id) ON DELETE RESTRICT,
    external_entry_id varchar(200) NOT NULL,
    subject_type varchar(20) NOT NULL,
    primary_name varchar(500) NOT NULL,
    normalized_name varchar(500) NOT NULL,
    country_codes char(2)[] NOT NULL DEFAULT '{}'::char(2)[],
    birth_or_registration_date date,
    identifiers_masked jsonb NOT NULL DEFAULT '{}'::jsonb,
    addresses_masked jsonb NOT NULL DEFAULT '[]'::jsonb,
    designation_reason text,
    designated_from date,
    designated_to date,
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    source_record_uri text,
    source_record_sha256 char(64),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (compliance_list_version_id, external_entry_id),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_compliance_list_entry_subject CHECK (
        subject_type IN ('PERSON','ORGANIZATION','VESSEL','AIRCRAFT','BANK','ADDRESS','COUNTRY','OTHER')
    ),
    CONSTRAINT ck_ewms_compliance_list_entry_dates CHECK (
        designated_to IS NULL OR designated_from IS NULL OR designated_to >= designated_from
    ),
    CONSTRAINT ck_ewms_compliance_list_entry_status CHECK (
        status IN ('ACTIVE','REMOVED','SUPERSEDED','UNKNOWN')
    ),
    CONSTRAINT ck_ewms_compliance_list_entry_hash CHECK (
        source_record_sha256 IS NULL OR source_record_sha256 ~ '^[0-9A-Fa-f]{64}$'
    ),
    CONSTRAINT ck_ewms_compliance_list_entry_masked CHECK (
        NOT ewms.jsonb_contains_forbidden_secret_key(identifiers_masked) AND
        NOT ewms.jsonb_contains_forbidden_secret_key(addresses_masked)
    )
);

CREATE TABLE IF NOT EXISTS ewms.compliance_list_aliases (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    compliance_list_entry_id uuid NOT NULL REFERENCES ewms.compliance_list_entries(id) ON DELETE CASCADE,
    alias_type varchar(20) NOT NULL,
    alias_name varchar(500) NOT NULL,
    normalized_alias_name varchar(500) NOT NULL,
    script_code varchar(20),
    language_code varchar(20),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (compliance_list_entry_id, normalized_alias_name),
    CONSTRAINT ck_ewms_compliance_list_alias_type CHECK (
        alias_type IN ('PRIMARY','AKA','FORMER','TRANSLITERATION','LOW_QUALITY','OTHER')
    )
);

CREATE TABLE IF NOT EXISTS ewms.screening_requests (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    screening_no varchar(150) NOT NULL,
    subject_type varchar(20) NOT NULL,
    business_partner_id uuid REFERENCES ewms.business_partners(id),
    vessel_id uuid REFERENCES ewms.vessels(id),
    trade_case_id uuid REFERENCES ewms.trade_cases(id),
    trade_shipment_id uuid REFERENCES ewms.trade_shipments(id),
    customs_declaration_id uuid REFERENCES ewms.customs_declarations(id),
    subject_name_snapshot varchar(500) NOT NULL,
    subject_identifiers_masked jsonb NOT NULL DEFAULT '{}'::jsonb,
    subject_country_codes char(2)[] NOT NULL DEFAULT '{}'::char(2)[],
    requested_list_types text[] NOT NULL DEFAULT '{}'::text[],
    screening_policy_code varchar(100),
    threshold_score numeric(9,6) NOT NULL DEFAULT 80,
    status varchar(30) NOT NULL DEFAULT 'QUEUED',
    requested_by uuid REFERENCES ewms.users(id),
    requested_at timestamptz NOT NULL DEFAULT now(),
    completed_at timestamptz,
    source_system_id uuid REFERENCES ewms.external_systems(id),
    idempotency_key varchar(200),
    row_version bigint NOT NULL DEFAULT 1,
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, screening_no),
    UNIQUE (tenant_id, idempotency_key),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_screening_request_subject CHECK (
        subject_type IN ('PARTY','PERSON','VESSEL','BANK','ADDRESS','COUNTRY','OTHER')
    ),
    CONSTRAINT ck_ewms_screening_request_target CHECK (
        num_nonnulls(business_partner_id, vessel_id) <= 1
    ),
    CONSTRAINT ck_ewms_screening_request_threshold CHECK (threshold_score BETWEEN 0 AND 100),
    CONSTRAINT ck_ewms_screening_request_status CHECK (
        status IN ('QUEUED','RUNNING','MATCH_FOUND','NO_MATCH','REVIEW_REQUIRED','CLEARED','BLOCKED','ERROR','CANCELLED')
    ),
    CONSTRAINT ck_ewms_screening_request_dates CHECK (
        completed_at IS NULL OR completed_at >= requested_at
    ),
    CONSTRAINT ck_ewms_screening_request_masked CHECK (
        NOT ewms.jsonb_contains_forbidden_secret_key(subject_identifiers_masked)
    )
);

CREATE TABLE IF NOT EXISTS ewms.screening_request_lists (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    screening_request_id uuid NOT NULL REFERENCES ewms.screening_requests(id) ON DELETE CASCADE,
    compliance_list_version_id uuid NOT NULL REFERENCES ewms.compliance_list_versions(id) ON DELETE RESTRICT,
    screened_at timestamptz,
    result_status varchar(20) NOT NULL DEFAULT 'PENDING',
    candidate_count integer NOT NULL DEFAULT 0,
    error_masked text,
    UNIQUE (screening_request_id, compliance_list_version_id),
    CONSTRAINT ck_ewms_screening_request_list_status CHECK (
        result_status IN ('PENDING','RUNNING','NO_MATCH','MATCH_FOUND','ERROR','SKIPPED')
    ),
    CONSTRAINT ck_ewms_screening_request_list_count CHECK (candidate_count >= 0)
);

CREATE TABLE IF NOT EXISTS ewms.screening_matches (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    screening_request_id uuid NOT NULL REFERENCES ewms.screening_requests(id) ON DELETE RESTRICT,
    compliance_list_entry_id uuid NOT NULL REFERENCES ewms.compliance_list_entries(id) ON DELETE RESTRICT,
    matched_alias_id uuid REFERENCES ewms.compliance_list_aliases(id) ON DELETE RESTRICT,
    match_score numeric(9,6) NOT NULL,
    name_score numeric(9,6),
    identifier_score numeric(9,6),
    country_score numeric(9,6),
    match_reasons jsonb NOT NULL DEFAULT '[]'::jsonb,
    disposition varchar(30) NOT NULL DEFAULT 'UNREVIEWED',
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (screening_request_id, compliance_list_entry_id),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_screening_match_scores CHECK (
        match_score BETWEEN 0 AND 100 AND
        (name_score IS NULL OR name_score BETWEEN 0 AND 100) AND
        (identifier_score IS NULL OR identifier_score BETWEEN 0 AND 100) AND
        (country_score IS NULL OR country_score BETWEEN 0 AND 100)
    ),
    CONSTRAINT ck_ewms_screening_match_disposition CHECK (
        disposition IN ('UNREVIEWED','CLEAR','FALSE_POSITIVE','CONFIRMED','ESCALATED','IGNORED')
    )
);

CREATE TABLE IF NOT EXISTS ewms.screening_decisions (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    screening_request_id uuid NOT NULL REFERENCES ewms.screening_requests(id) ON DELETE RESTRICT,
    screening_match_id uuid REFERENCES ewms.screening_matches(id) ON DELETE RESTRICT,
    decision varchar(30) NOT NULL,
    reason_code varchar(80),
    rationale text NOT NULL,
    decided_by uuid NOT NULL REFERENCES ewms.users(id),
    decided_at timestamptz NOT NULL DEFAULT now(),
    approval_request_id uuid REFERENCES ewms.approval_requests(id) ON DELETE RESTRICT,
    valid_until timestamptz,
    supersedes_id uuid REFERENCES ewms.screening_decisions(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_ewms_screening_decision CHECK (
        decision IN ('CLEAR','FALSE_POSITIVE','CONFIRMED','ESCALATE','BLOCK','ALLOW_WITH_CONDITIONS')
    ),
    CONSTRAINT ck_ewms_screening_decision_dates CHECK (
        valid_until IS NULL OR valid_until >= decided_at
    )
);

CREATE TABLE IF NOT EXISTS ewms.compliance_holds (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    hold_no varchar(150) NOT NULL,
    hold_type varchar(30) NOT NULL,
    severity varchar(20) NOT NULL,
    trade_case_id uuid REFERENCES ewms.trade_cases(id),
    trade_shipment_id uuid REFERENCES ewms.trade_shipments(id),
    customs_declaration_id uuid REFERENCES ewms.customs_declarations(id),
    business_partner_id uuid REFERENCES ewms.business_partners(id),
    item_id uuid REFERENCES ewms.items(id),
    screening_request_id uuid REFERENCES ewms.screening_requests(id),
    reason_code varchar(80) NOT NULL,
    reason_text text NOT NULL,
    opened_by uuid REFERENCES ewms.users(id),
    opened_at timestamptz NOT NULL DEFAULT now(),
    due_at timestamptz,
    status varchar(20) NOT NULL DEFAULT 'OPEN',
    released_by uuid REFERENCES ewms.users(id),
    released_at timestamptz,
    release_reason text,
    approval_request_id uuid REFERENCES ewms.approval_requests(id) ON DELETE RESTRICT,
    row_version bigint NOT NULL DEFAULT 1,
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, hold_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_compliance_hold_target CHECK (
        num_nonnulls(trade_case_id, trade_shipment_id, customs_declaration_id, business_partner_id, item_id) >= 1
    ),
    CONSTRAINT ck_ewms_compliance_hold_type CHECK (
        hold_type IN ('SANCTIONS','EXPORT_CONTROL','LICENSE','QUOTA','ORIGIN','CUSTOMS','DOCUMENT','FRAUD','OTHER')
    ),
    CONSTRAINT ck_ewms_compliance_hold_severity CHECK (severity IN ('WARNING','BLOCKING')),
    CONSTRAINT ck_ewms_compliance_hold_status CHECK (
        status IN ('OPEN','UNDER_REVIEW','RELEASED','EXPIRED','CANCELLED')
    ),
    CONSTRAINT ck_ewms_compliance_hold_release CHECK (
        (status IN ('OPEN','UNDER_REVIEW') AND released_at IS NULL AND released_by IS NULL) OR
        (status IN ('RELEASED','EXPIRED','CANCELLED') AND released_at IS NOT NULL)
    )
);

CREATE TABLE IF NOT EXISTS ewms.compliance_events (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    compliance_hold_id uuid REFERENCES ewms.compliance_holds(id) ON DELETE RESTRICT,
    screening_request_id uuid REFERENCES ewms.screening_requests(id) ON DELETE RESTRICT,
    sequence_no bigint NOT NULL,
    event_type varchar(80) NOT NULL,
    from_status varchar(30),
    to_status varchar(30),
    occurred_at timestamptz NOT NULL,
    recorded_by uuid REFERENCES ewms.users(id),
    recorded_at timestamptz NOT NULL DEFAULT now(),
    detail_masked jsonb NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT ck_ewms_compliance_event_parent CHECK (
        num_nonnulls(compliance_hold_id, screening_request_id) = 1
    ),
    CONSTRAINT ck_ewms_compliance_event_sequence CHECK (sequence_no > 0),
    CONSTRAINT ck_ewms_compliance_event_masked CHECK (
        NOT ewms.jsonb_contains_forbidden_secret_key(detail_masked)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_ewms_compliance_event_hold_seq
    ON ewms.compliance_events (compliance_hold_id, sequence_no)
    WHERE compliance_hold_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_ewms_compliance_event_screen_seq
    ON ewms.compliance_events (screening_request_id, sequence_no)
    WHERE screening_request_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS ewms.control_classification_schemes (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    scheme_code varchar(80) NOT NULL,
    scheme_name varchar(250) NOT NULL,
    jurisdiction_country_code char(2) REFERENCES ewms.countries(country_code),
    authority_name varchar(250),
    version_code varchar(80) NOT NULL,
    effective_from date NOT NULL,
    effective_to date,
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, scheme_code, version_code),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_control_scheme_dates CHECK (effective_to IS NULL OR effective_to >= effective_from),
    CONSTRAINT ck_ewms_control_scheme_status CHECK (
        status IN ('DRAFT','ACTIVE','SUPERSEDED','EXPIRED','REVOKED')
    )
);

CREATE TABLE IF NOT EXISTS ewms.item_control_classifications (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    item_id uuid NOT NULL REFERENCES ewms.items(id) ON DELETE RESTRICT,
    control_classification_scheme_id uuid NOT NULL
        REFERENCES ewms.control_classification_schemes(id) ON DELETE RESTRICT,
    classification_code varchar(100) NOT NULL,
    classification_result varchar(30) NOT NULL,
    strategic_goods_flag boolean NOT NULL DEFAULT false,
    self_classification_no varchar(150),
    authority_ruling_no varchar(150),
    valid_from date NOT NULL,
    valid_to date,
    approved_by uuid REFERENCES ewms.users(id),
    approved_at timestamptz,
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    evidence_file_id uuid REFERENCES ewms.files(id) ON DELETE RESTRICT,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, item_id, control_classification_scheme_id, classification_code, valid_from),
    CONSTRAINT ck_ewms_item_control_classification_result CHECK (
        classification_result IN ('CONTROLLED','NOT_CONTROLLED','UNCERTAIN','OUT_OF_SCOPE')
    ),
    CONSTRAINT ck_ewms_item_control_classification_dates CHECK (valid_to IS NULL OR valid_to >= valid_from),
    CONSTRAINT ck_ewms_item_control_classification_status CHECK (
        status IN ('DRAFT','ACTIVE','SUSPENDED','SUPERSEDED','EXPIRED')
    )
);

CREATE TABLE IF NOT EXISTS ewms.trade_control_rules (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    rule_code varchar(100) NOT NULL,
    rule_name varchar(300) NOT NULL,
    jurisdiction_country_code char(2) REFERENCES ewms.countries(country_code),
    direction varchar(20),
    destination_country_code char(2) REFERENCES ewms.countries(country_code),
    origin_country_code char(2) REFERENCES ewms.countries(country_code),
    control_classification_scheme_id uuid REFERENCES ewms.control_classification_schemes(id),
    classification_prefix varchar(100),
    hs_prefix varchar(20),
    end_use_category varchar(100),
    end_user_category varchar(100),
    action varchar(30) NOT NULL,
    license_type_required varchar(50),
    effective_from date NOT NULL,
    effective_to date,
    priority integer NOT NULL DEFAULT 100,
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, rule_code),
    CONSTRAINT ck_ewms_trade_control_rule_direction CHECK (
        direction IS NULL OR direction IN ('IMPORT','EXPORT','TRANSIT','CROSS_TRADE','RETURN')
    ),
    CONSTRAINT ck_ewms_trade_control_rule_action CHECK (
        action IN ('ALLOW','DENY','LICENSE_REQUIRED','REVIEW_REQUIRED','DOCUMENT_REQUIRED','HOLD')
    ),
    CONSTRAINT ck_ewms_trade_control_rule_dates CHECK (effective_to IS NULL OR effective_to >= effective_from),
    CONSTRAINT ck_ewms_trade_control_rule_priority CHECK (priority >= 0)
);

CREATE TABLE IF NOT EXISTS ewms.trade_licenses (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    license_no varchar(180) NOT NULL,
    license_type varchar(40) NOT NULL,
    direction varchar(20) NOT NULL,
    holder_partner_id uuid NOT NULL REFERENCES ewms.business_partners(id),
    issuing_authority varchar(300),
    issuing_country_code char(2) REFERENCES ewms.countries(country_code),
    valid_from date NOT NULL,
    valid_to date NOT NULL,
    currency_code char(3) REFERENCES ewms.currencies(currency_code),
    licensed_value numeric(24,4),
    used_value numeric(24,4) NOT NULL DEFAULT 0,
    licensed_quantity numeric(24,8),
    used_quantity numeric(24,8) NOT NULL DEFAULT 0,
    uom_code varchar(20) REFERENCES ewms.units_of_measure(uom_code),
    reusable boolean NOT NULL DEFAULT false,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    license_file_id uuid REFERENCES ewms.files(id) ON DELETE RESTRICT,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, license_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_trade_license_type CHECK (
        license_type IN ('IMPORT','EXPORT','QUOTA','STRATEGIC_GOODS','END_USE','SANCTIONS_EXCEPTION','TEMPORARY','OTHER')
    ),
    CONSTRAINT ck_ewms_trade_license_direction CHECK (
        direction IN ('IMPORT','EXPORT','BOTH','TRANSIT')
    ),
    CONSTRAINT ck_ewms_trade_license_dates CHECK (valid_to >= valid_from),
    CONSTRAINT ck_ewms_trade_license_amount CHECK (
        (licensed_value IS NULL OR licensed_value >= 0) AND used_value >= 0 AND
        (licensed_value IS NULL OR used_value <= licensed_value)
    ),
    CONSTRAINT ck_ewms_trade_license_qty CHECK (
        (licensed_quantity IS NULL OR licensed_quantity >= 0) AND used_quantity >= 0 AND
        (licensed_quantity IS NULL OR used_quantity <= licensed_quantity)
    ),
    CONSTRAINT ck_ewms_trade_license_status CHECK (
        status IN ('DRAFT','APPLIED','ACTIVE','SUSPENDED','EXHAUSTED','EXPIRED','REVOKED','CANCELLED')
    )
);

CREATE TABLE IF NOT EXISTS ewms.trade_license_lines (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    trade_license_id uuid NOT NULL REFERENCES ewms.trade_licenses(id) ON DELETE RESTRICT,
    line_no integer NOT NULL,
    item_id uuid REFERENCES ewms.items(id),
    hs_code varchar(20),
    control_classification_code varchar(100),
    origin_country_code char(2) REFERENCES ewms.countries(country_code),
    destination_country_code char(2) REFERENCES ewms.countries(country_code),
    end_user_partner_id uuid REFERENCES ewms.business_partners(id),
    end_use_description text,
    licensed_quantity numeric(24,8),
    used_quantity numeric(24,8) NOT NULL DEFAULT 0,
    uom_code varchar(20) REFERENCES ewms.units_of_measure(uom_code),
    licensed_value numeric(24,4),
    used_value numeric(24,4) NOT NULL DEFAULT 0,
    currency_code char(3) REFERENCES ewms.currencies(currency_code),
    UNIQUE (trade_license_id, line_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_trade_license_line_no CHECK (line_no > 0),
    CONSTRAINT ck_ewms_trade_license_line_qty CHECK (
        (licensed_quantity IS NULL OR licensed_quantity >= 0) AND used_quantity >= 0 AND
        (licensed_quantity IS NULL OR used_quantity <= licensed_quantity)
    ),
    CONSTRAINT ck_ewms_trade_license_line_value CHECK (
        (licensed_value IS NULL OR licensed_value >= 0) AND used_value >= 0 AND
        (licensed_value IS NULL OR used_value <= licensed_value)
    )
);

CREATE TABLE IF NOT EXISTS ewms.trade_license_usages (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    trade_license_line_id uuid NOT NULL REFERENCES ewms.trade_license_lines(id) ON DELETE RESTRICT,
    trade_case_item_id uuid REFERENCES ewms.trade_case_items(id) ON DELETE RESTRICT,
    customs_declaration_line_id uuid REFERENCES ewms.customs_declaration_lines(id) ON DELETE RESTRICT,
    usage_type varchar(20) NOT NULL DEFAULT 'UTILIZE',
    used_quantity numeric(24,8),
    uom_code varchar(20) REFERENCES ewms.units_of_measure(uom_code),
    used_value numeric(24,4),
    currency_code char(3) REFERENCES ewms.currencies(currency_code),
    status varchar(20) NOT NULL DEFAULT 'POSTED',
    posted_by uuid REFERENCES ewms.users(id),
    posted_at timestamptz NOT NULL DEFAULT now(),
    reversal_of_id uuid REFERENCES ewms.trade_license_usages(id),
    reason text,
    CONSTRAINT ck_ewms_trade_license_usage_target CHECK (
        num_nonnulls(trade_case_item_id, customs_declaration_line_id) >= 1
    ),
    CONSTRAINT ck_ewms_trade_license_usage_type CHECK (
        usage_type IN ('RESERVE','UTILIZE','RELEASE','REVERSE','ADJUST')
    ),
    CONSTRAINT ck_ewms_trade_license_usage_measure CHECK (
        (used_quantity IS NOT NULL AND used_quantity > 0) OR (used_value IS NOT NULL AND used_value > 0)
    ),
    CONSTRAINT ck_ewms_trade_license_usage_status CHECK (
        status IN ('DRAFT','POSTED','REVERSED','CANCELLED')
    )
);

CREATE TABLE IF NOT EXISTS ewms.quota_allocations (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    quota_no varchar(150) NOT NULL,
    holder_partner_id uuid NOT NULL REFERENCES ewms.business_partners(id),
    item_id uuid REFERENCES ewms.items(id),
    hs_code varchar(20),
    origin_country_code char(2) REFERENCES ewms.countries(country_code),
    destination_country_code char(2) REFERENCES ewms.countries(country_code),
    allocated_quantity numeric(24,8) NOT NULL,
    used_quantity numeric(24,8) NOT NULL DEFAULT 0,
    uom_code varchar(20) NOT NULL REFERENCES ewms.units_of_measure(uom_code),
    valid_from date NOT NULL,
    valid_to date NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    allocation_file_id uuid REFERENCES ewms.files(id) ON DELETE RESTRICT,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, quota_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_quota_allocation_qty CHECK (
        allocated_quantity > 0 AND used_quantity >= 0 AND used_quantity <= allocated_quantity
    ),
    CONSTRAINT ck_ewms_quota_allocation_dates CHECK (valid_to >= valid_from),
    CONSTRAINT ck_ewms_quota_allocation_status CHECK (
        status IN ('ACTIVE','SUSPENDED','EXHAUSTED','EXPIRED','REVOKED')
    )
);

CREATE TABLE IF NOT EXISTS ewms.quota_usages (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    quota_allocation_id uuid NOT NULL REFERENCES ewms.quota_allocations(id) ON DELETE RESTRICT,
    customs_declaration_line_id uuid NOT NULL REFERENCES ewms.customs_declaration_lines(id) ON DELETE RESTRICT,
    usage_type varchar(20) NOT NULL DEFAULT 'UTILIZE',
    used_quantity numeric(24,8) NOT NULL,
    uom_code varchar(20) NOT NULL REFERENCES ewms.units_of_measure(uom_code),
    status varchar(20) NOT NULL DEFAULT 'POSTED',
    posted_by uuid REFERENCES ewms.users(id),
    posted_at timestamptz NOT NULL DEFAULT now(),
    reversal_of_id uuid REFERENCES ewms.quota_usages(id),
    reason text,
    CONSTRAINT ck_ewms_quota_usage_type CHECK (
        usage_type IN ('RESERVE','UTILIZE','RELEASE','REVERSE','ADJUST')
    ),
    CONSTRAINT ck_ewms_quota_usage_qty CHECK (used_quantity > 0),
    CONSTRAINT ck_ewms_quota_usage_status CHECK (status IN ('DRAFT','POSTED','REVERSED','CANCELLED'))
);

CREATE TABLE IF NOT EXISTS ewms.end_use_statements (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    statement_no varchar(150) NOT NULL,
    end_user_partner_id uuid NOT NULL REFERENCES ewms.business_partners(id),
    consignee_partner_id uuid REFERENCES ewms.business_partners(id),
    trade_case_id uuid REFERENCES ewms.trade_cases(id),
    destination_country_code char(2) NOT NULL REFERENCES ewms.countries(country_code),
    end_use_description text NOT NULL,
    prohibited_use_acknowledged boolean NOT NULL DEFAULT false,
    issue_date date NOT NULL,
    valid_to date,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    trade_document_id uuid REFERENCES ewms.trade_documents(id) ON DELETE RESTRICT,
    verified_by uuid REFERENCES ewms.users(id),
    verified_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, statement_no),
    CONSTRAINT ck_ewms_end_use_statement_dates CHECK (valid_to IS NULL OR valid_to >= issue_date),
    CONSTRAINT ck_ewms_end_use_statement_status CHECK (
        status IN ('DRAFT','RECEIVED','VERIFIED','REJECTED','EXPIRED','REVOKED')
    )
);

CREATE TABLE IF NOT EXISTS ewms.regulatory_cases (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    regulatory_case_no varchar(150) NOT NULL,
    trade_case_id uuid NOT NULL REFERENCES ewms.trade_cases(id) ON DELETE RESTRICT,
    authority_type varchar(50) NOT NULL,
    procedure_code varchar(100),
    jurisdiction_country_code char(2) NOT NULL REFERENCES ewms.countries(country_code),
    authority_name varchar(300),
    status varchar(30) NOT NULL DEFAULT 'DRAFT',
    submitted_at timestamptz,
    decided_at timestamptz,
    assigned_user_id uuid REFERENCES ewms.users(id),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, regulatory_case_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_regulatory_case_authority CHECK (
        authority_type IN ('QUARANTINE','FOOD','DRUG','PLANT','ANIMAL','ENVIRONMENT','RADIO','SAFETY','STRATEGIC_GOODS','OTHER')
    ),
    CONSTRAINT ck_ewms_regulatory_case_status CHECK (
        status IN ('DRAFT','PREPARED','SUBMITTED','UNDER_REVIEW','INSPECTION','SUPPLEMENT_REQUIRED',
                   'APPROVED','REJECTED','WITHDRAWN','CANCELLED','CLOSED')
    )
);

CREATE TABLE IF NOT EXISTS ewms.regulatory_permits (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    regulatory_case_id uuid NOT NULL REFERENCES ewms.regulatory_cases(id) ON DELETE RESTRICT,
    permit_no varchar(180) NOT NULL,
    permit_type varchar(50) NOT NULL,
    holder_partner_id uuid NOT NULL REFERENCES ewms.business_partners(id),
    issuing_authority varchar(300),
    issue_date date NOT NULL,
    valid_from date NOT NULL,
    valid_to date NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    permit_file_id uuid REFERENCES ewms.files(id) ON DELETE RESTRICT,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, permit_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_regulatory_permit_dates CHECK (valid_to >= valid_from),
    CONSTRAINT ck_ewms_regulatory_permit_status CHECK (
        status IN ('DRAFT','ACTIVE','SUSPENDED','EXPIRED','REVOKED','CANCELLED')
    )
);

CREATE TABLE IF NOT EXISTS ewms.regulatory_permit_lines (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    regulatory_permit_id uuid NOT NULL REFERENCES ewms.regulatory_permits(id) ON DELETE RESTRICT,
    line_no integer NOT NULL,
    item_id uuid REFERENCES ewms.items(id),
    hs_code varchar(20),
    goods_description varchar(1000),
    permitted_quantity numeric(24,8),
    used_quantity numeric(24,8) NOT NULL DEFAULT 0,
    uom_code varchar(20) REFERENCES ewms.units_of_measure(uom_code),
    conditions text,
    UNIQUE (regulatory_permit_id, line_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_regulatory_permit_line_no CHECK (line_no > 0),
    CONSTRAINT ck_ewms_regulatory_permit_line_qty CHECK (
        (permitted_quantity IS NULL OR permitted_quantity >= 0) AND used_quantity >= 0 AND
        (permitted_quantity IS NULL OR used_quantity <= permitted_quantity)
    )
);

CREATE TABLE IF NOT EXISTS ewms.regulatory_permit_usages (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    regulatory_permit_line_id uuid NOT NULL REFERENCES ewms.regulatory_permit_lines(id) ON DELETE RESTRICT,
    customs_declaration_line_id uuid NOT NULL REFERENCES ewms.customs_declaration_lines(id) ON DELETE RESTRICT,
    usage_type varchar(20) NOT NULL DEFAULT 'UTILIZE',
    used_quantity numeric(24,8),
    uom_code varchar(20) REFERENCES ewms.units_of_measure(uom_code),
    status varchar(20) NOT NULL DEFAULT 'POSTED',
    posted_by uuid REFERENCES ewms.users(id),
    posted_at timestamptz NOT NULL DEFAULT now(),
    reversal_of_id uuid REFERENCES ewms.regulatory_permit_usages(id),
    CONSTRAINT ck_ewms_regulatory_permit_usage_type CHECK (
        usage_type IN ('RESERVE','UTILIZE','RELEASE','REVERSE','ADJUST')
    ),
    CONSTRAINT ck_ewms_regulatory_permit_usage_qty CHECK (
        used_quantity IS NULL OR used_quantity > 0
    ),
    CONSTRAINT ck_ewms_regulatory_permit_usage_status CHECK (
        status IN ('DRAFT','POSTED','REVERSED','CANCELLED')
    )
);

-- -----------------------------------------------------------------------------
-- Exchange-rate evidence, trade finance, cash reconciliation, and FX hedging
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS ewms.exchange_rate_sources (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    source_code varchar(80) NOT NULL,
    source_name varchar(250) NOT NULL,
    authority_name varchar(250),
    source_uri text,
    timezone varchar(100),
    publication_frequency varchar(30),
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, source_code),
    UNIQUE (tenant_id, id)
);

CREATE TABLE IF NOT EXISTS ewms.exchange_rate_snapshots (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    exchange_rate_source_id uuid REFERENCES ewms.exchange_rate_sources(id),
    exchange_rate_id uuid REFERENCES ewms.exchange_rates(id),
    rate_type varchar(30) NOT NULL,
    from_currency_code char(3) NOT NULL REFERENCES ewms.currencies(currency_code),
    to_currency_code char(3) NOT NULL REFERENCES ewms.currencies(currency_code),
    effective_at timestamptz NOT NULL,
    published_at timestamptz,
    captured_at timestamptz NOT NULL DEFAULT now(),
    rate numeric(24,12) NOT NULL,
    source_reference varchar(300),
    source_file_id uuid REFERENCES ewms.files(id) ON DELETE RESTRICT,
    created_by uuid REFERENCES ewms.users(id),
    UNIQUE (tenant_id, exchange_rate_source_id, rate_type, from_currency_code, to_currency_code, effective_at),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_exchange_rate_snapshot_currency CHECK (from_currency_code <> to_currency_code),
    CONSTRAINT ck_ewms_exchange_rate_snapshot_rate CHECK (rate > 0)
);

CREATE TABLE IF NOT EXISTS ewms.letters_of_credit (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    lc_no varchar(180) NOT NULL,
    lc_type varchar(30) NOT NULL,
    applicant_partner_id uuid NOT NULL REFERENCES ewms.business_partners(id),
    beneficiary_partner_id uuid NOT NULL REFERENCES ewms.business_partners(id),
    issuing_bank_partner_id uuid NOT NULL REFERENCES ewms.business_partners(id),
    advising_bank_partner_id uuid REFERENCES ewms.business_partners(id),
    confirming_bank_partner_id uuid REFERENCES ewms.business_partners(id),
    currency_code char(3) NOT NULL REFERENCES ewms.currencies(currency_code),
    original_amount numeric(24,4) NOT NULL,
    current_amount numeric(24,4) NOT NULL,
    utilized_amount numeric(24,4) NOT NULL DEFAULT 0,
    tolerance_plus_percent numeric(9,6) NOT NULL DEFAULT 0,
    tolerance_minus_percent numeric(9,6) NOT NULL DEFAULT 0,
    issue_date date NOT NULL,
    expiry_date date NOT NULL,
    expiry_place varchar(300),
    latest_shipment_date date,
    presentation_period_days integer,
    partial_shipment_allowed boolean NOT NULL DEFAULT true,
    transshipment_allowed boolean NOT NULL DEFAULT true,
    available_by varchar(50),
    governing_rules varchar(50) NOT NULL DEFAULT 'UCP600',
    status varchar(30) NOT NULL DEFAULT 'DRAFT',
    trade_document_id uuid REFERENCES ewms.trade_documents(id) ON DELETE RESTRICT,
    row_version bigint NOT NULL DEFAULT 1,
    created_by uuid REFERENCES ewms.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, issuing_bank_partner_id, lc_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_lc_type CHECK (
        lc_type IN ('IRREVOCABLE','CONFIRMED','TRANSFERABLE','BACK_TO_BACK','REVOLVING','STANDBY','OTHER')
    ),
    CONSTRAINT ck_ewms_lc_amount CHECK (
        original_amount > 0 AND current_amount > 0 AND utilized_amount >= 0 AND utilized_amount <= current_amount
    ),
    CONSTRAINT ck_ewms_lc_tolerance CHECK (
        tolerance_plus_percent BETWEEN 0 AND 100 AND tolerance_minus_percent BETWEEN 0 AND 100
    ),
    CONSTRAINT ck_ewms_lc_dates CHECK (
        expiry_date >= issue_date AND (latest_shipment_date IS NULL OR latest_shipment_date <= expiry_date)
    ),
    CONSTRAINT ck_ewms_lc_presentation_days CHECK (
        presentation_period_days IS NULL OR presentation_period_days >= 0
    ),
    CONSTRAINT ck_ewms_lc_status CHECK (
        status IN ('DRAFT','ISSUED','ADVISED','CONFIRMED','AMENDED','PARTIALLY_UTILIZED',
                   'FULLY_UTILIZED','EXPIRED','CANCELLED','CLOSED')
    )
);

CREATE TABLE IF NOT EXISTS ewms.letter_of_credit_amendments (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    letter_of_credit_id uuid NOT NULL REFERENCES ewms.letters_of_credit(id) ON DELETE RESTRICT,
    amendment_no integer NOT NULL,
    amendment_reference varchar(150),
    amendment_date date NOT NULL,
    amount_change numeric(24,4) NOT NULL DEFAULT 0,
    new_current_amount numeric(24,4) NOT NULL,
    new_expiry_date date,
    new_latest_shipment_date date,
    amendment_text text,
    trade_document_id uuid REFERENCES ewms.trade_documents(id) ON DELETE RESTRICT,
    status varchar(20) NOT NULL DEFAULT 'ISSUED',
    accepted_by_beneficiary_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (letter_of_credit_id, amendment_no),
    CONSTRAINT ck_ewms_lc_amendment_no CHECK (amendment_no > 0),
    CONSTRAINT ck_ewms_lc_amendment_amount CHECK (new_current_amount > 0),
    CONSTRAINT ck_ewms_lc_amendment_status CHECK (
        status IN ('DRAFT','ISSUED','ACCEPTED','REJECTED','WITHDRAWN')
    )
);

CREATE TABLE IF NOT EXISTS ewms.letter_of_credit_terms (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    letter_of_credit_id uuid NOT NULL REFERENCES ewms.letters_of_credit(id) ON DELETE CASCADE,
    amendment_id uuid REFERENCES ewms.letter_of_credit_amendments(id) ON DELETE CASCADE,
    term_no integer NOT NULL,
    term_type varchar(30) NOT NULL,
    term_code varchar(80),
    term_text text NOT NULL,
    is_document_requirement boolean NOT NULL DEFAULT false,
    is_mandatory boolean NOT NULL DEFAULT true,
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    UNIQUE (letter_of_credit_id, amendment_id, term_no),
    CONSTRAINT ck_ewms_lc_term_no CHECK (term_no > 0),
    CONSTRAINT ck_ewms_lc_term_type CHECK (
        term_type IN ('GOODS','SHIPMENT','DOCUMENT','PAYMENT','BANKING','SPECIAL_CONDITION','OTHER')
    ),
    CONSTRAINT ck_ewms_lc_term_status CHECK (status IN ('ACTIVE','SUPERSEDED','WAIVED','CANCELLED'))
);

CREATE TABLE IF NOT EXISTS ewms.document_presentations (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    presentation_no varchar(150) NOT NULL,
    letter_of_credit_id uuid REFERENCES ewms.letters_of_credit(id) ON DELETE RESTRICT,
    documentary_collection_id uuid,
    presenting_bank_partner_id uuid REFERENCES ewms.business_partners(id),
    receiving_bank_partner_id uuid REFERENCES ewms.business_partners(id),
    presented_amount numeric(24,4) NOT NULL,
    currency_code char(3) NOT NULL REFERENCES ewms.currencies(currency_code),
    presented_at timestamptz NOT NULL,
    due_at timestamptz,
    status varchar(30) NOT NULL DEFAULT 'PREPARED',
    accepted_at timestamptz,
    paid_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, presentation_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_document_presentation_source CHECK (
        num_nonnulls(letter_of_credit_id, documentary_collection_id) = 1
    ),
    CONSTRAINT ck_ewms_document_presentation_amount CHECK (presented_amount > 0),
    CONSTRAINT ck_ewms_document_presentation_dates CHECK (due_at IS NULL OR due_at >= presented_at),
    CONSTRAINT ck_ewms_document_presentation_status CHECK (
        status IN ('PREPARED','PRESENTED','UNDER_EXAMINATION','DISCREPANT','ACCEPTED','REFUSED',
                   'PAYMENT_PENDING','PAID','RETURNED','CLOSED')
    )
);

CREATE TABLE IF NOT EXISTS ewms.document_presentation_documents (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    document_presentation_id uuid NOT NULL REFERENCES ewms.document_presentations(id) ON DELETE CASCADE,
    line_no integer NOT NULL,
    trade_document_id uuid NOT NULL REFERENCES ewms.trade_documents(id) ON DELETE RESTRICT,
    trade_document_version_id uuid REFERENCES ewms.trade_document_versions(id) ON DELETE RESTRICT,
    required_original_count integer NOT NULL DEFAULT 0,
    presented_original_count integer NOT NULL DEFAULT 0,
    required_copy_count integer NOT NULL DEFAULT 0,
    presented_copy_count integer NOT NULL DEFAULT 0,
    examination_status varchar(20) NOT NULL DEFAULT 'PENDING',
    UNIQUE (document_presentation_id, line_no),
    UNIQUE (document_presentation_id, trade_document_id),
    CONSTRAINT ck_ewms_presentation_document_line CHECK (line_no > 0),
    CONSTRAINT ck_ewms_presentation_document_counts CHECK (
        required_original_count >= 0 AND presented_original_count >= 0 AND
        required_copy_count >= 0 AND presented_copy_count >= 0
    ),
    CONSTRAINT ck_ewms_presentation_document_status CHECK (
        examination_status IN ('PENDING','COMPLIANT','DISCREPANT','WAIVED','REJECTED')
    )
);

CREATE TABLE IF NOT EXISTS ewms.document_discrepancies (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    document_presentation_id uuid NOT NULL REFERENCES ewms.document_presentations(id) ON DELETE RESTRICT,
    presentation_document_id uuid REFERENCES ewms.document_presentation_documents(id) ON DELETE RESTRICT,
    discrepancy_no integer NOT NULL,
    discrepancy_code varchar(80),
    description text NOT NULL,
    severity varchar(20) NOT NULL DEFAULT 'MAJOR',
    status varchar(20) NOT NULL DEFAULT 'OPEN',
    waiver_requested_at timestamptz,
    waiver_decision varchar(20),
    waiver_decided_by uuid REFERENCES ewms.users(id),
    waiver_decided_at timestamptz,
    resolution text,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (document_presentation_id, discrepancy_no),
    CONSTRAINT ck_ewms_document_discrepancy_no CHECK (discrepancy_no > 0),
    CONSTRAINT ck_ewms_document_discrepancy_severity CHECK (severity IN ('MINOR','MAJOR','CRITICAL')),
    CONSTRAINT ck_ewms_document_discrepancy_status CHECK (
        status IN ('OPEN','WAIVER_REQUESTED','WAIVED','CORRECTED','REJECTED','CLOSED')
    ),
    CONSTRAINT ck_ewms_document_discrepancy_waiver CHECK (
        waiver_decision IS NULL OR waiver_decision IN ('APPROVED','REJECTED')
    )
);

CREATE TABLE IF NOT EXISTS ewms.documentary_collections (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    collection_no varchar(150) NOT NULL,
    collection_type varchar(20) NOT NULL,
    drawer_partner_id uuid NOT NULL REFERENCES ewms.business_partners(id),
    drawee_partner_id uuid NOT NULL REFERENCES ewms.business_partners(id),
    remitting_bank_partner_id uuid REFERENCES ewms.business_partners(id),
    collecting_bank_partner_id uuid REFERENCES ewms.business_partners(id),
    currency_code char(3) NOT NULL REFERENCES ewms.currencies(currency_code),
    collection_amount numeric(24,4) NOT NULL,
    instructions text,
    sent_at timestamptz,
    received_at timestamptz,
    maturity_date date,
    status varchar(30) NOT NULL DEFAULT 'DRAFT',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, collection_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_documentary_collection_type CHECK (
        collection_type IN ('D_P','D_A','CLEAN','DIRECT','OTHER')
    ),
    CONSTRAINT ck_ewms_documentary_collection_amount CHECK (collection_amount > 0),
    CONSTRAINT ck_ewms_documentary_collection_dates CHECK (
        received_at IS NULL OR sent_at IS NULL OR received_at >= sent_at
    ),
    CONSTRAINT ck_ewms_documentary_collection_status CHECK (
        status IN ('DRAFT','SENT','RECEIVED','PRESENTED','ACCEPTED','PAID','PROTESTED','RETURNED','CLOSED','CANCELLED')
    )
);

DO $block$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'ewms.document_presentations'::regclass
          AND conname = 'fk_ewms_document_presentation_collection'
    ) THEN
        ALTER TABLE ewms.document_presentations
            ADD CONSTRAINT fk_ewms_document_presentation_collection
            FOREIGN KEY (documentary_collection_id)
            REFERENCES ewms.documentary_collections(id) ON DELETE RESTRICT;
    END IF;
END;
$block$;

CREATE TABLE IF NOT EXISTS ewms.trade_finance_events (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    letter_of_credit_id uuid REFERENCES ewms.letters_of_credit(id) ON DELETE RESTRICT,
    documentary_collection_id uuid REFERENCES ewms.documentary_collections(id) ON DELETE RESTRICT,
    document_presentation_id uuid REFERENCES ewms.document_presentations(id) ON DELETE RESTRICT,
    sequence_no bigint NOT NULL,
    event_type varchar(80) NOT NULL,
    from_status varchar(30),
    to_status varchar(30),
    occurred_at timestamptz NOT NULL,
    recorded_by uuid REFERENCES ewms.users(id),
    recorded_at timestamptz NOT NULL DEFAULT now(),
    detail_masked jsonb NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT ck_ewms_trade_finance_event_parent CHECK (
        num_nonnulls(letter_of_credit_id, documentary_collection_id, document_presentation_id) = 1
    ),
    CONSTRAINT ck_ewms_trade_finance_event_sequence CHECK (sequence_no > 0),
    CONSTRAINT ck_ewms_trade_finance_event_masked CHECK (
        NOT ewms.jsonb_contains_forbidden_secret_key(detail_masked)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_ewms_trade_finance_event_lc_seq
    ON ewms.trade_finance_events (letter_of_credit_id, sequence_no)
    WHERE letter_of_credit_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_ewms_trade_finance_event_collection_seq
    ON ewms.trade_finance_events (documentary_collection_id, sequence_no)
    WHERE documentary_collection_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_ewms_trade_finance_event_presentation_seq
    ON ewms.trade_finance_events (document_presentation_id, sequence_no)
    WHERE document_presentation_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS ewms.payment_requests (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    payment_request_no varchar(150) NOT NULL,
    payer_organization_id uuid NOT NULL REFERENCES ewms.organizations(id),
    payee_partner_id uuid NOT NULL REFERENCES ewms.business_partners(id),
    currency_code char(3) NOT NULL REFERENCES ewms.currencies(currency_code),
    requested_amount numeric(24,4) NOT NULL,
    requested_payment_date date NOT NULL,
    payment_reason varchar(300) NOT NULL,
    approval_request_id uuid REFERENCES ewms.approval_requests(id) ON DELETE RESTRICT,
    status varchar(30) NOT NULL DEFAULT 'DRAFT',
    requested_by uuid REFERENCES ewms.users(id),
    requested_at timestamptz,
    approved_at timestamptz,
    paid_at timestamptz,
    payment_id uuid REFERENCES ewms.payments(id) ON DELETE RESTRICT,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, payment_request_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_payment_request_amount CHECK (requested_amount > 0),
    CONSTRAINT ck_ewms_payment_request_status CHECK (
        status IN ('DRAFT','SUBMITTED','APPROVAL_PENDING','APPROVED','REJECTED','PAYMENT_PENDING','PAID','CANCELLED')
    )
);

CREATE TABLE IF NOT EXISTS ewms.payment_request_lines (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    payment_request_id uuid NOT NULL REFERENCES ewms.payment_requests(id) ON DELETE CASCADE,
    line_no integer NOT NULL,
    invoice_id uuid REFERENCES ewms.invoices(id) ON DELETE RESTRICT,
    customs_duty_payment_id uuid REFERENCES ewms.customs_duty_payments(id) ON DELETE RESTRICT,
    settlement_id uuid REFERENCES ewms.settlements(id) ON DELETE RESTRICT,
    line_description varchar(500) NOT NULL,
    amount numeric(24,4) NOT NULL,
    cost_center_code varchar(50),
    gl_account_id uuid REFERENCES ewms.gl_accounts(id),
    UNIQUE (payment_request_id, line_no),
    CONSTRAINT ck_ewms_payment_request_line_source CHECK (
        num_nonnulls(invoice_id, customs_duty_payment_id, settlement_id) <= 1
    ),
    CONSTRAINT ck_ewms_payment_request_line_no CHECK (line_no > 0),
    CONSTRAINT ck_ewms_payment_request_line_amount CHECK (amount > 0)
);

CREATE TABLE IF NOT EXISTS ewms.bank_statement_imports (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    partner_bank_account_id uuid NOT NULL REFERENCES ewms.partner_bank_accounts(id),
    statement_reference varchar(180) NOT NULL,
    statement_date date NOT NULL,
    currency_code char(3) NOT NULL REFERENCES ewms.currencies(currency_code),
    opening_balance numeric(24,4),
    closing_balance numeric(24,4),
    source_file_id uuid NOT NULL REFERENCES ewms.files(id) ON DELETE RESTRICT,
    source_sha256 char(64) NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'IMPORTED',
    imported_by uuid REFERENCES ewms.users(id),
    imported_at timestamptz NOT NULL DEFAULT now(),
    row_version bigint NOT NULL DEFAULT 1,
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, partner_bank_account_id, statement_reference),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_bank_statement_hash CHECK (source_sha256 ~ '^[0-9A-Fa-f]{64}$'),
    CONSTRAINT ck_ewms_bank_statement_status CHECK (
        status IN ('IMPORTED','VALIDATED','RECONCILING','RECONCILED','ERROR','ARCHIVED')
    )
);

CREATE TABLE IF NOT EXISTS ewms.bank_statement_lines (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    bank_statement_import_id uuid NOT NULL REFERENCES ewms.bank_statement_imports(id) ON DELETE RESTRICT,
    line_no integer NOT NULL,
    bank_transaction_id varchar(200),
    value_date date NOT NULL,
    booking_date date,
    amount numeric(24,4) NOT NULL,
    transaction_type varchar(30) NOT NULL,
    counterparty_name_masked varchar(300),
    counterparty_account_encrypted text,
    counterparty_account_hash char(64),
    counterparty_account_masked varchar(100),
    remittance_information text,
    reconciliation_status varchar(20) NOT NULL DEFAULT 'UNMATCHED',
    UNIQUE (bank_statement_import_id, line_no),
    UNIQUE (tenant_id, bank_transaction_id),
    CONSTRAINT ck_ewms_bank_statement_line_no CHECK (line_no > 0),
    CONSTRAINT ck_ewms_bank_statement_transaction_type CHECK (
        transaction_type IN ('DEBIT','CREDIT','FEE','INTEREST','REVERSAL','OTHER')
    ),
    CONSTRAINT ck_ewms_bank_statement_reconciliation CHECK (
        reconciliation_status IN ('UNMATCHED','PARTIALLY_MATCHED','MATCHED','IGNORED','DISPUTED')
    ),
    CONSTRAINT ck_ewms_bank_statement_counterparty_hash CHECK (
        counterparty_account_hash IS NULL OR counterparty_account_hash ~ '^[0-9A-Fa-f]{64}$'
    )
);

CREATE TABLE IF NOT EXISTS ewms.cash_reconciliation_matches (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    bank_statement_line_id uuid NOT NULL REFERENCES ewms.bank_statement_lines(id) ON DELETE RESTRICT,
    payment_id uuid REFERENCES ewms.payments(id) ON DELETE RESTRICT,
    payment_request_id uuid REFERENCES ewms.payment_requests(id) ON DELETE RESTRICT,
    matched_amount numeric(24,4) NOT NULL,
    match_method varchar(20) NOT NULL,
    match_score numeric(9,6),
    status varchar(20) NOT NULL DEFAULT 'PROPOSED',
    matched_by uuid REFERENCES ewms.users(id),
    matched_at timestamptz NOT NULL DEFAULT now(),
    approved_by uuid REFERENCES ewms.users(id),
    approved_at timestamptz,
    reversed_at timestamptz,
    reversal_reason text,
    CONSTRAINT ck_ewms_cash_reconciliation_target CHECK (
        num_nonnulls(payment_id, payment_request_id) = 1
    ),
    CONSTRAINT ck_ewms_cash_reconciliation_amount CHECK (matched_amount > 0),
    CONSTRAINT ck_ewms_cash_reconciliation_method CHECK (
        match_method IN ('AUTO','RULE','MANUAL')
    ),
    CONSTRAINT ck_ewms_cash_reconciliation_score CHECK (
        match_score IS NULL OR match_score BETWEEN 0 AND 100
    ),
    CONSTRAINT ck_ewms_cash_reconciliation_status CHECK (
        status IN ('PROPOSED','APPROVED','REJECTED','REVERSED')
    )
);

CREATE TABLE IF NOT EXISTS ewms.foreign_exchange_contracts (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    contract_no varchar(150) NOT NULL,
    organization_id uuid NOT NULL REFERENCES ewms.organizations(id),
    bank_partner_id uuid NOT NULL REFERENCES ewms.business_partners(id),
    contract_type varchar(30) NOT NULL,
    buy_currency_code char(3) NOT NULL REFERENCES ewms.currencies(currency_code),
    sell_currency_code char(3) NOT NULL REFERENCES ewms.currencies(currency_code),
    contracted_buy_amount numeric(24,4) NOT NULL,
    allocated_buy_amount numeric(24,4) NOT NULL DEFAULT 0,
    contracted_sell_amount numeric(24,4) NOT NULL,
    allocated_sell_amount numeric(24,4) NOT NULL DEFAULT 0,
    contract_rate numeric(24,12) NOT NULL,
    contract_date date NOT NULL,
    maturity_date date NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    confirmation_file_id uuid REFERENCES ewms.files(id) ON DELETE RESTRICT,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, bank_partner_id, contract_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_fx_contract_currency CHECK (buy_currency_code <> sell_currency_code),
    CONSTRAINT ck_ewms_fx_contract_amounts CHECK (
        contracted_buy_amount > 0 AND allocated_buy_amount >= 0 AND allocated_buy_amount <= contracted_buy_amount AND
        contracted_sell_amount > 0 AND allocated_sell_amount >= 0 AND allocated_sell_amount <= contracted_sell_amount AND
        contract_rate > 0
    ),
    CONSTRAINT ck_ewms_fx_contract_dates CHECK (maturity_date >= contract_date),
    CONSTRAINT ck_ewms_fx_contract_type CHECK (
        contract_type IN ('FORWARD','SPOT','SWAP','OPTION','NDF','OTHER')
    ),
    CONSTRAINT ck_ewms_fx_contract_status CHECK (
        status IN ('DRAFT','ACTIVE','PARTIALLY_ALLOCATED','FULLY_ALLOCATED','SETTLED','CANCELLED','EXPIRED')
    )
);

CREATE TABLE IF NOT EXISTS ewms.foreign_exchange_allocations (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    foreign_exchange_contract_id uuid NOT NULL REFERENCES ewms.foreign_exchange_contracts(id) ON DELETE RESTRICT,
    invoice_id uuid REFERENCES ewms.invoices(id) ON DELETE RESTRICT,
    payment_request_id uuid REFERENCES ewms.payment_requests(id) ON DELETE RESTRICT,
    letter_of_credit_id uuid REFERENCES ewms.letters_of_credit(id) ON DELETE RESTRICT,
    allocated_buy_amount numeric(24,4) NOT NULL,
    allocated_sell_amount numeric(24,4) NOT NULL,
    allocation_status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    allocated_by uuid REFERENCES ewms.users(id),
    allocated_at timestamptz NOT NULL DEFAULT now(),
    reversed_at timestamptz,
    reversal_reason text,
    CONSTRAINT ck_ewms_fx_allocation_target CHECK (
        num_nonnulls(invoice_id, payment_request_id, letter_of_credit_id) = 1
    ),
    CONSTRAINT ck_ewms_fx_allocation_amount CHECK (
        allocated_buy_amount > 0 AND allocated_sell_amount > 0
    ),
    CONSTRAINT ck_ewms_fx_allocation_status CHECK (
        allocation_status IN ('ACTIVE','SETTLED','REVERSED','CANCELLED')
    )
);

-- -----------------------------------------------------------------------------
-- Cargo insurance, incidents, surveys, claims, reserves, and recoveries
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS ewms.insurance_policies (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    policy_no varchar(180) NOT NULL,
    policy_type varchar(30) NOT NULL,
    insurer_partner_id uuid NOT NULL REFERENCES ewms.business_partners(id),
    policyholder_partner_id uuid NOT NULL REFERENCES ewms.business_partners(id),
    broker_partner_id uuid REFERENCES ewms.business_partners(id),
    current_version_id uuid,
    current_version_no integer,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    row_version bigint NOT NULL DEFAULT 1,
    created_by uuid REFERENCES ewms.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, insurer_partner_id, policy_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_insurance_policy_type CHECK (
        policy_type IN ('OPEN_CARGO','SINGLE_SHIPMENT','WAREHOUSE','LIABILITY','STOCK_THROUGHPUT','OTHER')
    ),
    CONSTRAINT ck_ewms_insurance_policy_status CHECK (
        status IN ('DRAFT','ACTIVE','SUSPENDED','EXPIRED','CANCELLED','CLOSED')
    ),
    CONSTRAINT ck_ewms_insurance_policy_current_version CHECK (
        (current_version_id IS NULL AND current_version_no IS NULL) OR
        (current_version_id IS NOT NULL AND current_version_no > 0)
    )
);

CREATE TABLE IF NOT EXISTS ewms.insurance_policy_versions (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    insurance_policy_id uuid NOT NULL REFERENCES ewms.insurance_policies(id) ON DELETE RESTRICT,
    version_no integer NOT NULL,
    endorsement_no varchar(100),
    effective_from timestamptz NOT NULL,
    effective_to timestamptz NOT NULL,
    currency_code char(3) NOT NULL REFERENCES ewms.currencies(currency_code),
    policy_limit numeric(24,4) NOT NULL,
    aggregate_limit numeric(24,4),
    deductible_amount numeric(24,4) NOT NULL DEFAULT 0,
    deductible_percent numeric(9,6),
    valuation_basis varchar(50),
    insured_value_percent numeric(9,6) NOT NULL DEFAULT 110,
    governing_law varchar(150),
    institute_clause varchar(150),
    excluded_risks text,
    version_status varchar(20) NOT NULL DEFAULT 'DRAFT',
    issued_at timestamptz,
    policy_file_id uuid REFERENCES ewms.files(id) ON DELETE RESTRICT,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (insurance_policy_id, version_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_insurance_policy_version_no CHECK (version_no > 0),
    CONSTRAINT ck_ewms_insurance_policy_version_dates CHECK (effective_to > effective_from),
    CONSTRAINT ck_ewms_insurance_policy_version_amount CHECK (
        policy_limit > 0 AND (aggregate_limit IS NULL OR aggregate_limit > 0) AND deductible_amount >= 0 AND
        (deductible_percent IS NULL OR deductible_percent BETWEEN 0 AND 100) AND
        insured_value_percent > 0
    ),
    CONSTRAINT ck_ewms_insurance_policy_version_status CHECK (
        version_status IN ('DRAFT','ISSUED','SUPERSEDED','CANCELLED')
    ),
    CONSTRAINT ck_ewms_insurance_policy_version_issue CHECK (
        (version_status = 'DRAFT' AND issued_at IS NULL) OR
        (version_status <> 'DRAFT' AND issued_at IS NOT NULL)
    )
);

DO $block$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'ewms.insurance_policies'::regclass
          AND conname = 'fk_ewms_insurance_policy_current_version'
    ) THEN
        ALTER TABLE ewms.insurance_policies
            ADD CONSTRAINT fk_ewms_insurance_policy_current_version
            FOREIGN KEY (tenant_id, current_version_id)
            REFERENCES ewms.insurance_policy_versions(tenant_id, id)
            DEFERRABLE INITIALLY DEFERRED;
    END IF;
END;
$block$;

CREATE TABLE IF NOT EXISTS ewms.insurance_policy_coverages (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    insurance_policy_version_id uuid NOT NULL REFERENCES ewms.insurance_policy_versions(id) ON DELETE CASCADE,
    coverage_code varchar(80) NOT NULL,
    coverage_name varchar(250) NOT NULL,
    coverage_type varchar(30) NOT NULL,
    covered_transport_modes text[] NOT NULL DEFAULT '{}'::text[],
    covered_country_codes char(2)[] NOT NULL DEFAULT '{}'::char(2)[],
    per_occurrence_limit numeric(24,4),
    deductible_amount numeric(24,4),
    waiting_period_days integer,
    conditions text,
    exclusions text,
    UNIQUE (insurance_policy_version_id, coverage_code),
    CONSTRAINT ck_ewms_insurance_coverage_type CHECK (
        coverage_type IN ('ALL_RISKS','NAMED_PERILS','WAR','STRIKES','THEFT','TEMPERATURE','DELAY','LIABILITY','OTHER')
    ),
    CONSTRAINT ck_ewms_insurance_coverage_amount CHECK (
        (per_occurrence_limit IS NULL OR per_occurrence_limit >= 0) AND
        (deductible_amount IS NULL OR deductible_amount >= 0) AND
        (waiting_period_days IS NULL OR waiting_period_days >= 0)
    )
);

CREATE TABLE IF NOT EXISTS ewms.insurance_policy_insured_parties (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    insurance_policy_version_id uuid NOT NULL REFERENCES ewms.insurance_policy_versions(id) ON DELETE CASCADE,
    partner_id uuid NOT NULL REFERENCES ewms.business_partners(id),
    insured_role varchar(30) NOT NULL,
    valid_from timestamptz NOT NULL,
    valid_to timestamptz,
    UNIQUE (insurance_policy_version_id, partner_id, insured_role, valid_from),
    CONSTRAINT ck_ewms_insurance_insured_role CHECK (
        insured_role IN ('POLICYHOLDER','NAMED_INSURED','ADDITIONAL_INSURED','LOSS_PAYEE','BENEFICIARY','OTHER')
    ),
    CONSTRAINT ck_ewms_insurance_insured_party_dates CHECK (valid_to IS NULL OR valid_to > valid_from)
);

CREATE TABLE IF NOT EXISTS ewms.insurance_certificates (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    certificate_no varchar(180) NOT NULL,
    insurance_policy_version_id uuid NOT NULL REFERENCES ewms.insurance_policy_versions(id) ON DELETE RESTRICT,
    trade_case_id uuid REFERENCES ewms.trade_cases(id) ON DELETE RESTRICT,
    trade_shipment_id uuid REFERENCES ewms.trade_shipments(id) ON DELETE RESTRICT,
    assured_partner_id uuid NOT NULL REFERENCES ewms.business_partners(id),
    beneficiary_partner_id uuid REFERENCES ewms.business_partners(id),
    currency_code char(3) NOT NULL REFERENCES ewms.currencies(currency_code),
    insured_value numeric(24,4) NOT NULL,
    premium_amount numeric(24,4) NOT NULL DEFAULT 0,
    voyage_from varchar(300),
    voyage_to varchar(300),
    attachment_from varchar(300),
    attachment_to varchar(300),
    issue_date date NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    issued_at timestamptz,
    certificate_file_id uuid REFERENCES ewms.files(id) ON DELETE RESTRICT,
    row_version bigint NOT NULL DEFAULT 1,
    created_by uuid REFERENCES ewms.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, certificate_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_insurance_certificate_target CHECK (
        num_nonnulls(trade_case_id, trade_shipment_id) >= 1
    ),
    CONSTRAINT ck_ewms_insurance_certificate_amount CHECK (
        insured_value > 0 AND premium_amount >= 0
    ),
    CONSTRAINT ck_ewms_insurance_certificate_status CHECK (
        status IN ('DRAFT','ISSUED','AMENDED','CANCELLED','EXPIRED','CLAIMED')
    ),
    CONSTRAINT ck_ewms_insurance_certificate_issue CHECK (
        (status = 'DRAFT' AND issued_at IS NULL) OR (status <> 'DRAFT' AND issued_at IS NOT NULL)
    )
);

CREATE TABLE IF NOT EXISTS ewms.insurance_certificate_cargo (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    insurance_certificate_id uuid NOT NULL REFERENCES ewms.insurance_certificates(id) ON DELETE RESTRICT,
    line_no integer NOT NULL,
    trade_case_item_id uuid REFERENCES ewms.trade_case_items(id) ON DELETE RESTRICT,
    trade_shipment_item_id uuid REFERENCES ewms.trade_shipment_items(id) ON DELETE RESTRICT,
    goods_description varchar(1000) NOT NULL,
    quantity numeric(24,8),
    uom_code varchar(20) REFERENCES ewms.units_of_measure(uom_code),
    insured_value numeric(24,4) NOT NULL,
    marks_and_numbers text,
    package_count numeric(20,4),
    UNIQUE (insurance_certificate_id, line_no),
    CONSTRAINT ck_ewms_insurance_certificate_cargo_line CHECK (line_no > 0),
    CONSTRAINT ck_ewms_insurance_certificate_cargo_amount CHECK (
        (quantity IS NULL OR quantity > 0) AND insured_value > 0 AND
        (package_count IS NULL OR package_count >= 0)
    )
);

CREATE TABLE IF NOT EXISTS ewms.insurance_declarations (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    insurance_policy_version_id uuid NOT NULL REFERENCES ewms.insurance_policy_versions(id) ON DELETE RESTRICT,
    insurance_certificate_id uuid REFERENCES ewms.insurance_certificates(id) ON DELETE RESTRICT,
    declaration_no varchar(150) NOT NULL,
    declaration_period date NOT NULL,
    declared_shipments integer NOT NULL DEFAULT 0,
    declared_value numeric(24,4) NOT NULL DEFAULT 0,
    premium_amount numeric(24,4) NOT NULL DEFAULT 0,
    currency_code char(3) NOT NULL REFERENCES ewms.currencies(currency_code),
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    submitted_at timestamptz,
    accepted_at timestamptz,
    source_file_id uuid REFERENCES ewms.files(id) ON DELETE RESTRICT,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, declaration_no),
    CONSTRAINT ck_ewms_insurance_declaration_counts CHECK (
        declared_shipments >= 0 AND declared_value >= 0 AND premium_amount >= 0
    ),
    CONSTRAINT ck_ewms_insurance_declaration_status CHECK (
        status IN ('DRAFT','SUBMITTED','ACCEPTED','REJECTED','RECONCILED','CANCELLED')
    )
);

CREATE TABLE IF NOT EXISTS ewms.insurance_premiums (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    insurance_policy_version_id uuid NOT NULL REFERENCES ewms.insurance_policy_versions(id) ON DELETE RESTRICT,
    insurance_certificate_id uuid REFERENCES ewms.insurance_certificates(id) ON DELETE RESTRICT,
    insurance_declaration_id uuid REFERENCES ewms.insurance_declarations(id) ON DELETE RESTRICT,
    premium_type varchar(20) NOT NULL,
    premium_amount numeric(24,4) NOT NULL,
    tax_amount numeric(24,4) NOT NULL DEFAULT 0,
    currency_code char(3) NOT NULL REFERENCES ewms.currencies(currency_code),
    due_date date,
    invoice_id uuid REFERENCES ewms.invoices(id) ON DELETE RESTRICT,
    payment_id uuid REFERENCES ewms.payments(id) ON DELETE RESTRICT,
    status varchar(20) NOT NULL DEFAULT 'ACCRUED',
    posted_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_ewms_insurance_premium_source CHECK (
        num_nonnulls(insurance_certificate_id, insurance_declaration_id) >= 1
    ),
    CONSTRAINT ck_ewms_insurance_premium_type CHECK (
        premium_type IN ('BASE','ADDITIONAL','RETURN','ADJUSTMENT','TAX','FEE')
    ),
    CONSTRAINT ck_ewms_insurance_premium_amount CHECK (premium_amount >= 0 AND tax_amount >= 0),
    CONSTRAINT ck_ewms_insurance_premium_status CHECK (
        status IN ('ACCRUED','INVOICED','PAID','REVERSED','CANCELLED')
    )
);

CREATE TABLE IF NOT EXISTS ewms.loss_incidents (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    incident_no varchar(150) NOT NULL,
    incident_type varchar(30) NOT NULL,
    trade_case_id uuid REFERENCES ewms.trade_cases(id) ON DELETE RESTRICT,
    trade_shipment_id uuid REFERENCES ewms.trade_shipments(id) ON DELETE RESTRICT,
    container_id uuid REFERENCES ewms.trade_containers(id) ON DELETE RESTRICT,
    warehouse_id uuid REFERENCES ewms.warehouses(id) ON DELETE RESTRICT,
    occurred_at timestamptz NOT NULL,
    discovered_at timestamptz NOT NULL,
    location_text varchar(300),
    port_code varchar(10) REFERENCES ewms.ports(port_code),
    cause_code varchar(80),
    description text NOT NULL,
    immediate_action text,
    status varchar(20) NOT NULL DEFAULT 'OPEN',
    reported_by uuid REFERENCES ewms.users(id),
    closed_by uuid REFERENCES ewms.users(id),
    closed_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, incident_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_loss_incident_target CHECK (
        num_nonnulls(trade_case_id, trade_shipment_id, container_id, warehouse_id) >= 1
    ),
    CONSTRAINT ck_ewms_loss_incident_type CHECK (
        incident_type IN ('LOSS','DAMAGE','SHORTAGE','CONTAMINATION','TEMPERATURE','DELAY','THEFT','ACCIDENT','GENERAL_AVERAGE','OTHER')
    ),
    CONSTRAINT ck_ewms_loss_incident_dates CHECK (
        discovered_at >= occurred_at AND (closed_at IS NULL OR closed_at >= discovered_at)
    ),
    CONSTRAINT ck_ewms_loss_incident_status CHECK (
        status IN ('OPEN','INVESTIGATING','CONTAINED','CLAIM_PENDING','CLOSED','CANCELLED')
    )
);

CREATE TABLE IF NOT EXISTS ewms.loss_incident_parties (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    loss_incident_id uuid NOT NULL REFERENCES ewms.loss_incidents(id) ON DELETE CASCADE,
    partner_id uuid REFERENCES ewms.business_partners(id),
    party_role varchar(30) NOT NULL,
    responsibility_percent numeric(9,6),
    notified_at timestamptz,
    response_due_at timestamptz,
    UNIQUE (loss_incident_id, party_role, partner_id),
    CONSTRAINT ck_ewms_loss_incident_party_role CHECK (
        party_role IN ('CLAIMANT','CARRIER','FORWARDER','WAREHOUSE','TERMINAL','SURVEYOR','INSURER','RESPONSIBLE_PARTY','WITNESS','OTHER')
    ),
    CONSTRAINT ck_ewms_loss_incident_responsibility CHECK (
        responsibility_percent IS NULL OR responsibility_percent BETWEEN 0 AND 100
    )
);

CREATE TABLE IF NOT EXISTS ewms.loss_incident_items (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    loss_incident_id uuid NOT NULL REFERENCES ewms.loss_incidents(id) ON DELETE CASCADE,
    line_no integer NOT NULL,
    trade_case_item_id uuid REFERENCES ewms.trade_case_items(id) ON DELETE RESTRICT,
    trade_shipment_item_id uuid REFERENCES ewms.trade_shipment_items(id) ON DELETE RESTRICT,
    shipment_line_id uuid REFERENCES ewms.shipment_lines(id) ON DELETE RESTRICT,
    item_id uuid REFERENCES ewms.items(id),
    lot_id uuid REFERENCES ewms.inventory_lots(id),
    affected_quantity numeric(24,8) NOT NULL,
    damaged_quantity numeric(24,8) NOT NULL DEFAULT 0,
    lost_quantity numeric(24,8) NOT NULL DEFAULT 0,
    salvage_quantity numeric(24,8) NOT NULL DEFAULT 0,
    uom_code varchar(20) NOT NULL REFERENCES ewms.units_of_measure(uom_code),
    affected_value numeric(24,4),
    currency_code char(3) REFERENCES ewms.currencies(currency_code),
    damage_description text,
    UNIQUE (loss_incident_id, line_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_loss_incident_item_line CHECK (line_no > 0),
    CONSTRAINT ck_ewms_loss_incident_item_qty CHECK (
        affected_quantity > 0 AND damaged_quantity >= 0 AND lost_quantity >= 0 AND salvage_quantity >= 0 AND
        damaged_quantity + lost_quantity <= affected_quantity AND salvage_quantity <= affected_quantity
    ),
    CONSTRAINT ck_ewms_loss_incident_item_value CHECK (affected_value IS NULL OR affected_value >= 0)
);

CREATE TABLE IF NOT EXISTS ewms.claims (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    claim_no varchar(150) NOT NULL,
    loss_incident_id uuid NOT NULL REFERENCES ewms.loss_incidents(id) ON DELETE RESTRICT,
    insurance_policy_version_id uuid REFERENCES ewms.insurance_policy_versions(id) ON DELETE RESTRICT,
    insurance_certificate_id uuid REFERENCES ewms.insurance_certificates(id) ON DELETE RESTRICT,
    claimant_partner_id uuid NOT NULL REFERENCES ewms.business_partners(id),
    respondent_partner_id uuid REFERENCES ewms.business_partners(id),
    claim_type varchar(30) NOT NULL,
    currency_code char(3) NOT NULL REFERENCES ewms.currencies(currency_code),
    claimed_amount numeric(24,4) NOT NULL,
    approved_amount numeric(24,4) NOT NULL DEFAULT 0,
    paid_amount numeric(24,4) NOT NULL DEFAULT 0,
    recovered_amount numeric(24,4) NOT NULL DEFAULT 0,
    current_reserve_amount numeric(24,4) NOT NULL DEFAULT 0,
    notice_date date,
    filing_deadline date,
    status varchar(30) NOT NULL DEFAULT 'DRAFT',
    assigned_user_id uuid REFERENCES ewms.users(id),
    submitted_at timestamptz,
    decided_at timestamptz,
    closed_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_by uuid REFERENCES ewms.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, claim_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_claim_type CHECK (
        claim_type IN ('CARGO_INSURANCE','CARRIER_LIABILITY','WAREHOUSE_LIABILITY','TERMINAL_LIABILITY','GENERAL_AVERAGE','OTHER')
    ),
    CONSTRAINT ck_ewms_claim_amounts CHECK (
        claimed_amount > 0 AND approved_amount >= 0 AND paid_amount >= 0 AND recovered_amount >= 0 AND
        current_reserve_amount >= 0 AND approved_amount <= claimed_amount AND paid_amount <= approved_amount
    ),
    CONSTRAINT ck_ewms_claim_dates CHECK (
        filing_deadline IS NULL OR notice_date IS NULL OR filing_deadline >= notice_date
    ),
    CONSTRAINT ck_ewms_claim_status CHECK (
        status IN ('DRAFT','NOTIFIED','UNDER_REVIEW','SURVEY','DOCUMENT_PENDING','APPROVED',
                   'PARTIAL','REJECTED','SETTLED','RECOVERED','CLOSED','WITHDRAWN','REOPENED')
    )
);

CREATE TABLE IF NOT EXISTS ewms.claim_items (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    claim_id uuid NOT NULL REFERENCES ewms.claims(id) ON DELETE RESTRICT,
    line_no integer NOT NULL,
    loss_incident_item_id uuid NOT NULL REFERENCES ewms.loss_incident_items(id) ON DELETE RESTRICT,
    claimed_quantity numeric(24,8) NOT NULL,
    approved_quantity numeric(24,8) NOT NULL DEFAULT 0,
    uom_code varchar(20) NOT NULL REFERENCES ewms.units_of_measure(uom_code),
    claimed_amount numeric(24,4) NOT NULL,
    approved_amount numeric(24,4) NOT NULL DEFAULT 0,
    deductible_amount numeric(24,4) NOT NULL DEFAULT 0,
    salvage_value numeric(24,4) NOT NULL DEFAULT 0,
    status varchar(20) NOT NULL DEFAULT 'OPEN',
    UNIQUE (claim_id, line_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_claim_item_line CHECK (line_no > 0),
    CONSTRAINT ck_ewms_claim_item_qty CHECK (
        claimed_quantity > 0 AND approved_quantity >= 0 AND approved_quantity <= claimed_quantity
    ),
    CONSTRAINT ck_ewms_claim_item_amount CHECK (
        claimed_amount > 0 AND approved_amount >= 0 AND approved_amount <= claimed_amount AND
        deductible_amount >= 0 AND salvage_value >= 0
    ),
    CONSTRAINT ck_ewms_claim_item_status CHECK (
        status IN ('OPEN','UNDER_REVIEW','APPROVED','PARTIAL','REJECTED','SETTLED','CLOSED')
    )
);

CREATE TABLE IF NOT EXISTS ewms.claim_events (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    claim_id uuid NOT NULL REFERENCES ewms.claims(id) ON DELETE RESTRICT,
    sequence_no bigint NOT NULL,
    event_type varchar(80) NOT NULL,
    from_status varchar(30),
    to_status varchar(30),
    occurred_at timestamptz NOT NULL,
    recorded_by uuid REFERENCES ewms.users(id),
    recorded_at timestamptz NOT NULL DEFAULT now(),
    detail_masked jsonb NOT NULL DEFAULT '{}'::jsonb,
    UNIQUE (claim_id, sequence_no),
    CONSTRAINT ck_ewms_claim_event_sequence CHECK (sequence_no > 0),
    CONSTRAINT ck_ewms_claim_event_masked CHECK (
        NOT ewms.jsonb_contains_forbidden_secret_key(detail_masked)
    )
);

CREATE TABLE IF NOT EXISTS ewms.claim_documents (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    claim_id uuid NOT NULL REFERENCES ewms.claims(id) ON DELETE RESTRICT,
    document_type varchar(80) NOT NULL,
    trade_document_id uuid REFERENCES ewms.trade_documents(id) ON DELETE RESTRICT,
    file_id uuid REFERENCES ewms.files(id) ON DELETE RESTRICT,
    submitted_by uuid REFERENCES ewms.users(id),
    submitted_at timestamptz NOT NULL DEFAULT now(),
    verification_status varchar(20) NOT NULL DEFAULT 'SUBMITTED',
    verified_by uuid REFERENCES ewms.users(id),
    verified_at timestamptz,
    remarks text,
    CONSTRAINT ck_ewms_claim_document_source CHECK (
        num_nonnulls(trade_document_id, file_id) = 1
    ),
    CONSTRAINT ck_ewms_claim_document_status CHECK (
        verification_status IN ('SUBMITTED','ACCEPTED','REJECTED','SUPERSEDED')
    )
);

CREATE TABLE IF NOT EXISTS ewms.cargo_surveys (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    survey_no varchar(150) NOT NULL,
    claim_id uuid NOT NULL REFERENCES ewms.claims(id) ON DELETE RESTRICT,
    surveyor_partner_id uuid NOT NULL REFERENCES ewms.business_partners(id),
    appointed_by_partner_id uuid REFERENCES ewms.business_partners(id),
    survey_type varchar(30) NOT NULL,
    scheduled_at timestamptz,
    started_at timestamptz,
    completed_at timestamptz,
    survey_location varchar(300),
    status varchar(20) NOT NULL DEFAULT 'APPOINTED',
    report_file_id uuid REFERENCES ewms.files(id) ON DELETE RESTRICT,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, survey_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_cargo_survey_type CHECK (
        survey_type IN ('DAMAGE','QUANTITY','CONDITION','TEMPERATURE','PRE_SHIPMENT','JOINT','OTHER')
    ),
    CONSTRAINT ck_ewms_cargo_survey_dates CHECK (
        (started_at IS NULL OR scheduled_at IS NULL OR started_at >= scheduled_at - interval '30 days') AND
        (completed_at IS NULL OR started_at IS NULL OR completed_at >= started_at)
    ),
    CONSTRAINT ck_ewms_cargo_survey_status CHECK (
        status IN ('APPOINTED','SCHEDULED','IN_PROGRESS','REPORT_PENDING','COMPLETED','CANCELLED')
    )
);

CREATE TABLE IF NOT EXISTS ewms.survey_findings (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    cargo_survey_id uuid NOT NULL REFERENCES ewms.cargo_surveys(id) ON DELETE CASCADE,
    finding_no integer NOT NULL,
    claim_item_id uuid REFERENCES ewms.claim_items(id) ON DELETE RESTRICT,
    finding_type varchar(30) NOT NULL,
    severity varchar(20),
    description text NOT NULL,
    probable_cause text,
    estimated_loss_amount numeric(24,4),
    currency_code char(3) REFERENCES ewms.currencies(currency_code),
    recommended_action text,
    evidence_file_id uuid REFERENCES ewms.files(id) ON DELETE RESTRICT,
    UNIQUE (cargo_survey_id, finding_no),
    CONSTRAINT ck_ewms_survey_finding_no CHECK (finding_no > 0),
    CONSTRAINT ck_ewms_survey_finding_type CHECK (
        finding_type IN ('DAMAGE','SHORTAGE','CONTAMINATION','TEMPERATURE','PACKAGING','HANDLING','DOCUMENT','CAUSE','OTHER')
    ),
    CONSTRAINT ck_ewms_survey_finding_severity CHECK (
        severity IS NULL OR severity IN ('LOW','MEDIUM','HIGH','CRITICAL')
    ),
    CONSTRAINT ck_ewms_survey_finding_amount CHECK (
        estimated_loss_amount IS NULL OR estimated_loss_amount >= 0
    )
);

CREATE TABLE IF NOT EXISTS ewms.claim_reserve_movements (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    claim_id uuid NOT NULL REFERENCES ewms.claims(id) ON DELETE RESTRICT,
    movement_no bigint NOT NULL,
    movement_type varchar(20) NOT NULL,
    amount numeric(24,4) NOT NULL,
    currency_code char(3) NOT NULL REFERENCES ewms.currencies(currency_code),
    reason text NOT NULL,
    approval_request_id uuid REFERENCES ewms.approval_requests(id) ON DELETE RESTRICT,
    posted_by uuid REFERENCES ewms.users(id),
    posted_at timestamptz NOT NULL DEFAULT now(),
    reversal_of_id uuid REFERENCES ewms.claim_reserve_movements(id),
    UNIQUE (claim_id, movement_no),
    CONSTRAINT ck_ewms_claim_reserve_movement_no CHECK (movement_no > 0),
    CONSTRAINT ck_ewms_claim_reserve_movement_type CHECK (
        movement_type IN ('INITIAL','INCREASE','DECREASE','PAYMENT','RELEASE','RECOVERY','REVERSAL')
    ),
    CONSTRAINT ck_ewms_claim_reserve_movement_amount CHECK (amount > 0)
);

CREATE TABLE IF NOT EXISTS ewms.claim_settlements (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    claim_id uuid NOT NULL REFERENCES ewms.claims(id) ON DELETE RESTRICT,
    settlement_no varchar(150) NOT NULL,
    settlement_type varchar(30) NOT NULL,
    payer_partner_id uuid NOT NULL REFERENCES ewms.business_partners(id),
    payee_partner_id uuid NOT NULL REFERENCES ewms.business_partners(id),
    currency_code char(3) NOT NULL REFERENCES ewms.currencies(currency_code),
    gross_amount numeric(24,4) NOT NULL,
    deductible_amount numeric(24,4) NOT NULL DEFAULT 0,
    salvage_deduction numeric(24,4) NOT NULL DEFAULT 0,
    other_deduction numeric(24,4) NOT NULL DEFAULT 0,
    net_amount numeric(24,4) NOT NULL,
    settlement_date date NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    approval_request_id uuid REFERENCES ewms.approval_requests(id) ON DELETE RESTRICT,
    payment_id uuid REFERENCES ewms.payments(id) ON DELETE RESTRICT,
    posted_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, settlement_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_claim_settlement_type CHECK (
        settlement_type IN ('INTERIM','FINAL','EX_GRATIA','RECOVERY','SALVAGE','OTHER')
    ),
    CONSTRAINT ck_ewms_claim_settlement_amount CHECK (
        gross_amount > 0 AND deductible_amount >= 0 AND salvage_deduction >= 0 AND other_deduction >= 0 AND
        net_amount = gross_amount - deductible_amount - salvage_deduction - other_deduction AND net_amount >= 0
    ),
    CONSTRAINT ck_ewms_claim_settlement_status CHECK (
        status IN ('DRAFT','APPROVAL_PENDING','APPROVED','POSTED','PAID','REVERSED','CANCELLED')
    )
);

CREATE TABLE IF NOT EXISTS ewms.claim_settlement_lines (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    claim_settlement_id uuid NOT NULL REFERENCES ewms.claim_settlements(id) ON DELETE RESTRICT,
    line_no integer NOT NULL,
    claim_item_id uuid REFERENCES ewms.claim_items(id) ON DELETE RESTRICT,
    line_type varchar(30) NOT NULL,
    description varchar(500) NOT NULL,
    amount numeric(24,4) NOT NULL,
    UNIQUE (claim_settlement_id, line_no),
    CONSTRAINT ck_ewms_claim_settlement_line_no CHECK (line_no > 0),
    CONSTRAINT ck_ewms_claim_settlement_line_type CHECK (
        line_type IN ('LOSS','EXPENSE','SURVEY_FEE','DEDUCTIBLE','SALVAGE','RECOVERY','ADJUSTMENT','OTHER')
    )
);

CREATE TABLE IF NOT EXISTS ewms.claim_recoveries (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    claim_id uuid NOT NULL REFERENCES ewms.claims(id) ON DELETE RESTRICT,
    recovery_no varchar(150) NOT NULL,
    recovery_type varchar(30) NOT NULL,
    recover_from_partner_id uuid REFERENCES ewms.business_partners(id),
    currency_code char(3) NOT NULL REFERENCES ewms.currencies(currency_code),
    claimed_recovery_amount numeric(24,4) NOT NULL,
    recovered_amount numeric(24,4) NOT NULL DEFAULT 0,
    recovery_date date,
    payment_id uuid REFERENCES ewms.payments(id) ON DELETE RESTRICT,
    status varchar(20) NOT NULL DEFAULT 'OPEN',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, recovery_no),
    CONSTRAINT ck_ewms_claim_recovery_type CHECK (
        recovery_type IN ('CARRIER','SUBROGATION','SALVAGE','THIRD_PARTY','REFUND','OTHER')
    ),
    CONSTRAINT ck_ewms_claim_recovery_amount CHECK (
        claimed_recovery_amount > 0 AND recovered_amount >= 0 AND recovered_amount <= claimed_recovery_amount
    ),
    CONSTRAINT ck_ewms_claim_recovery_status CHECK (
        status IN ('OPEN','DEMANDED','NEGOTIATING','PARTIALLY_RECOVERED','RECOVERED','WRITTEN_OFF','CLOSED','CANCELLED')
    )
);

-- -----------------------------------------------------------------------------
-- Trade-document controls, checklists, workflow and integration event evidence
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS ewms.trade_document_types (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    document_kind varchar(50) NOT NULL,
    document_name varchar(200) NOT NULL,
    module_code varchar(30) NOT NULL,
    direction varchar(20),
    category varchar(30) NOT NULL,
    issuer_role varchar(40),
    retention_class varchar(50),
    requires_signature boolean NOT NULL DEFAULT false,
    requires_original boolean NOT NULL DEFAULT false,
    schema_name varchar(150),
    minimum_schema_version varchar(80),
    valid_from date NOT NULL DEFAULT CURRENT_DATE,
    valid_to date,
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, document_kind, valid_from),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_trade_document_type_module CHECK (
        module_code IN ('CASE','IMPORT','EXPORT','LOGISTICS','CUSTOMS','FTA','COMPLIANCE','FINANCE','INSURANCE','OTHER')
    ),
    CONSTRAINT ck_ewms_trade_document_type_direction CHECK (
        direction IS NULL OR direction IN ('IMPORT','EXPORT','BOTH','TRANSIT','CROSS_TRADE','RETURN')
    ),
    CONSTRAINT ck_ewms_trade_document_type_category CHECK (
        category IN ('COMMERCIAL','TRANSPORT','CUSTOMS','ORIGIN','REGULATORY','FINANCE','INSURANCE','INTERNAL','OTHER')
    ),
    CONSTRAINT ck_ewms_trade_document_type_dates CHECK (valid_to IS NULL OR valid_to >= valid_from)
);

CREATE TABLE IF NOT EXISTS ewms.trade_document_status_events (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    trade_document_id uuid NOT NULL REFERENCES ewms.trade_documents(id) ON DELETE RESTRICT,
    trade_document_version_id uuid REFERENCES ewms.trade_document_versions(id) ON DELETE RESTRICT,
    sequence_no bigint NOT NULL,
    event_type varchar(80) NOT NULL,
    from_status varchar(20),
    to_status varchar(20),
    reason_code varchar(80),
    reason_text text,
    actor_user_id uuid REFERENCES ewms.users(id),
    occurred_at timestamptz NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT now(),
    correlation_id varchar(100),
    UNIQUE (trade_document_id, sequence_no),
    CONSTRAINT ck_ewms_trade_document_status_event_seq CHECK (sequence_no > 0)
);

CREATE TABLE IF NOT EXISTS ewms.trade_document_signatures (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    trade_document_version_id uuid NOT NULL REFERENCES ewms.trade_document_versions(id) ON DELETE RESTRICT,
    signature_no integer NOT NULL,
    signature_type varchar(30) NOT NULL,
    signer_user_id uuid REFERENCES ewms.users(id),
    signer_partner_id uuid REFERENCES ewms.business_partners(id),
    signer_name_snapshot varchar(300) NOT NULL,
    signer_role varchar(80),
    signed_at timestamptz NOT NULL,
    certificate_thumbprint varchar(200),
    signature_algorithm varchar(100),
    signature_evidence_uri text NOT NULL,
    signature_evidence_sha256 char(64) NOT NULL,
    verification_status varchar(20) NOT NULL DEFAULT 'PENDING',
    verified_at timestamptz,
    verification_detail_masked jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (trade_document_version_id, signature_no),
    CONSTRAINT ck_ewms_trade_document_signature_actor CHECK (
        num_nonnulls(signer_user_id, signer_partner_id) <= 1
    ),
    CONSTRAINT ck_ewms_trade_document_signature_type CHECK (
        signature_type IN ('ELECTRONIC','DIGITAL','SEAL','ATTESTATION','MANUAL_SCAN','OTHER')
    ),
    CONSTRAINT ck_ewms_trade_document_signature_hash CHECK (
        signature_evidence_sha256 ~ '^[0-9A-Fa-f]{64}$'
    ),
    CONSTRAINT ck_ewms_trade_document_signature_status CHECK (
        verification_status IN ('PENDING','VALID','INVALID','EXPIRED','REVOKED','ERROR')
    ),
    CONSTRAINT ck_ewms_trade_document_signature_masked CHECK (
        NOT ewms.jsonb_contains_forbidden_secret_key(verification_detail_masked)
    )
);

CREATE TABLE IF NOT EXISTS ewms.trade_document_extractions (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    trade_document_version_id uuid NOT NULL REFERENCES ewms.trade_document_versions(id) ON DELETE RESTRICT,
    extraction_no integer NOT NULL,
    engine_name varchar(150) NOT NULL,
    engine_version varchar(80),
    extraction_schema_name varchar(150),
    extraction_schema_version varchar(80),
    status varchar(20) NOT NULL DEFAULT 'QUEUED',
    extracted_data_uri text,
    extracted_data_sha256 char(64),
    confidence_summary jsonb NOT NULL DEFAULT '{}'::jsonb,
    error_detail_masked text,
    started_at timestamptz,
    completed_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (trade_document_version_id, extraction_no),
    CONSTRAINT ck_ewms_trade_document_extraction_no CHECK (extraction_no > 0),
    CONSTRAINT ck_ewms_trade_document_extraction_status CHECK (
        status IN ('QUEUED','RUNNING','SUCCEEDED','PARTIAL','FAILED','CANCELLED')
    ),
    CONSTRAINT ck_ewms_trade_document_extraction_hash CHECK (
        extracted_data_sha256 IS NULL OR extracted_data_sha256 ~ '^[0-9A-Fa-f]{64}$'
    ),
    CONSTRAINT ck_ewms_trade_document_extraction_source CHECK (
        (status NOT IN ('SUCCEEDED','PARTIAL')) OR
        (extracted_data_uri IS NOT NULL AND extracted_data_sha256 IS NOT NULL)
    ),
    CONSTRAINT ck_ewms_trade_document_extraction_dates CHECK (
        completed_at IS NULL OR started_at IS NULL OR completed_at >= started_at
    )
);

CREATE TABLE IF NOT EXISTS ewms.document_checklist_templates (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    template_code varchar(100) NOT NULL,
    template_name varchar(250) NOT NULL,
    module_code varchar(30) NOT NULL,
    direction varchar(20),
    country_code char(2) REFERENCES ewms.countries(country_code),
    transport_mode_code varchar(20) REFERENCES ewms.transport_modes(mode_code),
    current_version_id uuid,
    current_version_no integer,
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, template_code),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_document_checklist_template_direction CHECK (
        direction IS NULL OR direction IN ('IMPORT','EXPORT','BOTH','TRANSIT','CROSS_TRADE','RETURN')
    ),
    CONSTRAINT ck_ewms_document_checklist_template_current CHECK (
        (current_version_id IS NULL AND current_version_no IS NULL) OR
        (current_version_id IS NOT NULL AND current_version_no > 0)
    )
);

CREATE TABLE IF NOT EXISTS ewms.document_checklist_versions (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    document_checklist_template_id uuid NOT NULL
        REFERENCES ewms.document_checklist_templates(id) ON DELETE RESTRICT,
    version_no integer NOT NULL,
    effective_from date NOT NULL,
    effective_to date,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    published_by uuid REFERENCES ewms.users(id),
    published_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (document_checklist_template_id, version_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_document_checklist_version_no CHECK (version_no > 0),
    CONSTRAINT ck_ewms_document_checklist_version_dates CHECK (effective_to IS NULL OR effective_to >= effective_from),
    CONSTRAINT ck_ewms_document_checklist_version_status CHECK (
        status IN ('DRAFT','PUBLISHED','SUPERSEDED','RETIRED')
    ),
    CONSTRAINT ck_ewms_document_checklist_version_publish CHECK (
        (status = 'DRAFT' AND published_at IS NULL AND published_by IS NULL) OR
        (status <> 'DRAFT' AND published_at IS NOT NULL AND published_by IS NOT NULL)
    )
);

DO $block$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'ewms.document_checklist_templates'::regclass
          AND conname = 'fk_ewms_document_checklist_current_version'
    ) THEN
        ALTER TABLE ewms.document_checklist_templates
            ADD CONSTRAINT fk_ewms_document_checklist_current_version
            FOREIGN KEY (tenant_id, current_version_id)
            REFERENCES ewms.document_checklist_versions(tenant_id, id)
            DEFERRABLE INITIALLY DEFERRED;
    END IF;
END;
$block$;

CREATE TABLE IF NOT EXISTS ewms.document_checklist_items (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    document_checklist_version_id uuid NOT NULL
        REFERENCES ewms.document_checklist_versions(id) ON DELETE CASCADE,
    item_no integer NOT NULL,
    item_code varchar(100) NOT NULL,
    item_name varchar(300) NOT NULL,
    document_kind varchar(50),
    requirement_type varchar(30) NOT NULL DEFAULT 'DOCUMENT',
    is_required boolean NOT NULL DEFAULT true,
    minimum_count integer NOT NULL DEFAULT 1,
    condition_rule jsonb NOT NULL DEFAULT '{}'::jsonb,
    verification_rule jsonb NOT NULL DEFAULT '{}'::jsonb,
    sequence_no integer NOT NULL,
    UNIQUE (document_checklist_version_id, item_no),
    UNIQUE (document_checklist_version_id, item_code),
    CONSTRAINT ck_ewms_document_checklist_item_no CHECK (item_no > 0 AND sequence_no > 0),
    CONSTRAINT ck_ewms_document_checklist_item_type CHECK (
        requirement_type IN ('DOCUMENT','DATA','APPROVAL','SCREENING','PERMIT','INSPECTION','EVIDENCE','OTHER')
    ),
    CONSTRAINT ck_ewms_document_checklist_item_count CHECK (minimum_count >= 0),
    CONSTRAINT ck_ewms_document_checklist_item_secret CHECK (
        NOT ewms.jsonb_contains_forbidden_secret_key(condition_rule) AND
        NOT ewms.jsonb_contains_forbidden_secret_key(verification_rule)
    )
);

CREATE TABLE IF NOT EXISTS ewms.document_checklist_instances (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    document_checklist_version_id uuid NOT NULL
        REFERENCES ewms.document_checklist_versions(id) ON DELETE RESTRICT,
    entity_type varchar(80) NOT NULL,
    entity_id uuid NOT NULL,
    trade_case_id uuid REFERENCES ewms.trade_cases(id) ON DELETE RESTRICT,
    status varchar(20) NOT NULL DEFAULT 'OPEN',
    assigned_user_id uuid REFERENCES ewms.users(id),
    due_at timestamptz,
    started_at timestamptz NOT NULL DEFAULT now(),
    completed_at timestamptz,
    completed_by uuid REFERENCES ewms.users(id),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, document_checklist_version_id, entity_type, entity_id),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_document_checklist_instance_status CHECK (
        status IN ('OPEN','IN_PROGRESS','BLOCKED','COMPLETED','CANCELLED','EXPIRED')
    ),
    CONSTRAINT ck_ewms_document_checklist_instance_dates CHECK (
        completed_at IS NULL OR completed_at >= started_at
    )
);

CREATE TABLE IF NOT EXISTS ewms.document_checklist_results (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    document_checklist_instance_id uuid NOT NULL
        REFERENCES ewms.document_checklist_instances(id) ON DELETE CASCADE,
    document_checklist_item_id uuid NOT NULL
        REFERENCES ewms.document_checklist_items(id) ON DELETE RESTRICT,
    result_status varchar(20) NOT NULL DEFAULT 'PENDING',
    result_value_masked jsonb NOT NULL DEFAULT '{}'::jsonb,
    remarks text,
    verified_by uuid REFERENCES ewms.users(id),
    verified_at timestamptz,
    waived_by uuid REFERENCES ewms.users(id),
    waived_at timestamptz,
    waiver_reason text,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (document_checklist_instance_id, document_checklist_item_id),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_document_checklist_result_status CHECK (
        result_status IN ('PENDING','SATISFIED','FAILED','NOT_APPLICABLE','WAIVED')
    ),
    CONSTRAINT ck_ewms_document_checklist_result_waiver CHECK (
        (result_status = 'WAIVED' AND waived_by IS NOT NULL AND waived_at IS NOT NULL AND waiver_reason IS NOT NULL) OR
        (result_status <> 'WAIVED' AND waived_at IS NULL)
    ),
    CONSTRAINT ck_ewms_document_checklist_result_masked CHECK (
        NOT ewms.jsonb_contains_forbidden_secret_key(result_value_masked)
    )
);

CREATE TABLE IF NOT EXISTS ewms.document_checklist_evidence (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    document_checklist_result_id uuid NOT NULL
        REFERENCES ewms.document_checklist_results(id) ON DELETE RESTRICT,
    trade_document_id uuid REFERENCES ewms.trade_documents(id) ON DELETE RESTRICT,
    trade_document_version_id uuid REFERENCES ewms.trade_document_versions(id) ON DELETE RESTRICT,
    file_id uuid REFERENCES ewms.files(id) ON DELETE RESTRICT,
    screening_request_id uuid REFERENCES ewms.screening_requests(id) ON DELETE RESTRICT,
    regulatory_permit_id uuid REFERENCES ewms.regulatory_permits(id) ON DELETE RESTRICT,
    evidence_type varchar(30) NOT NULL,
    evidence_reference varchar(300),
    added_by uuid REFERENCES ewms.users(id),
    added_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_ewms_document_checklist_evidence_source CHECK (
        num_nonnulls(trade_document_id, trade_document_version_id, file_id, screening_request_id, regulatory_permit_id) = 1
    ),
    CONSTRAINT ck_ewms_document_checklist_evidence_type CHECK (
        evidence_type IN ('DOCUMENT','FILE','SCREENING','PERMIT','APPROVAL','SYSTEM_CHECK','OTHER')
    )
);

CREATE TABLE IF NOT EXISTS ewms.workflow_events (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    workflow_instance_id uuid NOT NULL REFERENCES ewms.workflow_instances(id) ON DELETE RESTRICT,
    sequence_no bigint NOT NULL,
    workflow_step_id uuid REFERENCES ewms.workflow_steps(id) ON DELETE RESTRICT,
    workflow_task_id uuid REFERENCES ewms.workflow_tasks(id) ON DELETE RESTRICT,
    event_type varchar(80) NOT NULL,
    from_status varchar(20),
    to_status varchar(20),
    actor_user_id uuid REFERENCES ewms.users(id),
    occurred_at timestamptz NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT now(),
    correlation_id varchar(100),
    outcome_masked jsonb NOT NULL DEFAULT '{}'::jsonb,
    UNIQUE (workflow_instance_id, sequence_no),
    CONSTRAINT ck_ewms_workflow_event_sequence CHECK (sequence_no > 0),
    CONSTRAINT ck_ewms_workflow_event_masked CHECK (
        NOT ewms.jsonb_contains_forbidden_secret_key(outcome_masked)
    )
);

CREATE TABLE IF NOT EXISTS ewms.integration_message_attempts (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    integration_message_id uuid NOT NULL REFERENCES ewms.integration_messages(id) ON DELETE RESTRICT,
    attempt_no integer NOT NULL,
    attempt_type varchar(30) NOT NULL,
    status varchar(20) NOT NULL,
    worker_reference varchar(150),
    started_at timestamptz NOT NULL,
    completed_at timestamptz,
    response_code varchar(100),
    error_code varchar(100),
    error_detail_masked text,
    next_retry_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (integration_message_id, attempt_no),
    CONSTRAINT ck_ewms_integration_attempt_no CHECK (attempt_no > 0),
    CONSTRAINT ck_ewms_integration_attempt_type CHECK (
        attempt_type IN ('RECEIVE','SEND','VALIDATE','PROCESS','RETRY','ACKNOWLEDGE')
    ),
    CONSTRAINT ck_ewms_integration_attempt_status CHECK (
        status IN ('RUNNING','SUCCEEDED','FAILED','RETRY_PENDING','CANCELLED')
    ),
    CONSTRAINT ck_ewms_integration_attempt_dates CHECK (
        completed_at IS NULL OR completed_at >= started_at
    )
);

CREATE TABLE IF NOT EXISTS ewms.job_run_events (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid REFERENCES ewms.tenants(id),
    job_run_id uuid NOT NULL REFERENCES ewms.job_runs(id) ON DELETE RESTRICT,
    sequence_no bigint NOT NULL,
    event_type varchar(80) NOT NULL,
    from_status varchar(20),
    to_status varchar(20),
    worker_reference varchar(150),
    occurred_at timestamptz NOT NULL,
    detail_masked jsonb NOT NULL DEFAULT '{}'::jsonb,
    UNIQUE (job_run_id, sequence_no),
    CONSTRAINT ck_ewms_job_run_event_sequence CHECK (sequence_no > 0),
    CONSTRAINT ck_ewms_job_run_event_masked CHECK (
        NOT ewms.jsonb_contains_forbidden_secret_key(detail_masked)
    )
);

-- -----------------------------------------------------------------------------
-- High-value EIMS integrity guards (PostgreSQL 11 compatible)
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION ewms.protect_eims_final_row()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    old_status text;
    argument_no integer;
BEGIN
    old_status := to_jsonb(OLD) ->> TG_ARGV[0];
    IF TG_NARGS > 1 THEN
        FOR argument_no IN 1 .. TG_NARGS - 1 LOOP
            IF old_status = TG_ARGV[argument_no] THEN
                RAISE EXCEPTION 'Finalized %.% row is immutable; create a new version, reversal, or event',
                    TG_TABLE_SCHEMA, TG_TABLE_NAME
                    USING ERRCODE = '55000';
            END IF;
        END LOOP;
    END IF;
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION ewms.protect_eims_sealed_row()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    IF (to_jsonb(OLD) ->> TG_ARGV[0]) IS NOT NULL THEN
        RAISE EXCEPTION 'Sealed %.% row is immutable; create a new version or reversal',
            TG_TABLE_SCHEMA, TG_TABLE_NAME
            USING ERRCODE = '55000';
    END IF;
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE TRIGGER trg_protect_trade_order_version
BEFORE UPDATE OR DELETE ON ewms.trade_order_versions
FOR EACH ROW EXECUTE PROCEDURE ewms.protect_eims_final_row(
    'version_status','SEALED','SUPERSEDED','CANCELLED'
);

CREATE TRIGGER trg_protect_origin_rule_set
BEFORE UPDATE OR DELETE ON ewms.origin_rule_sets
FOR EACH ROW EXECUTE PROCEDURE ewms.protect_eims_final_row(
    'status','PUBLISHED','SUPERSEDED','EXPIRED','REVOKED'
);

CREATE TRIGGER trg_protect_origin_calculation
BEFORE UPDATE OR DELETE ON ewms.origin_calculations
FOR EACH ROW EXECUTE PROCEDURE ewms.protect_eims_final_row(
    'status','SEALED','SUPERSEDED','CANCELLED'
);

CREATE TRIGGER trg_protect_insurance_policy_version
BEFORE UPDATE OR DELETE ON ewms.insurance_policy_versions
FOR EACH ROW EXECUTE PROCEDURE ewms.protect_eims_final_row(
    'version_status','ISSUED','SUPERSEDED','CANCELLED'
);

CREATE TRIGGER trg_protect_checklist_version
BEFORE UPDATE OR DELETE ON ewms.document_checklist_versions
FOR EACH ROW EXECUTE PROCEDURE ewms.protect_eims_final_row(
    'status','PUBLISHED','SUPERSEDED','RETIRED'
);

CREATE TRIGGER trg_protect_export_si_version
BEFORE UPDATE OR DELETE ON ewms.export_shipping_instruction_versions
FOR EACH ROW EXECUTE PROCEDURE ewms.protect_eims_sealed_row('sealed_at');

CREATE TRIGGER trg_protect_carrier_booking_version
BEFORE UPDATE OR DELETE ON ewms.carrier_booking_versions
FOR EACH ROW EXECUTE PROCEDURE ewms.protect_eims_sealed_row('sealed_at');

CREATE OR REPLACE FUNCTION ewms.validate_origin_certificate_line()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    certificate_row record;
    determination_row record;
BEGIN
    SELECT trade_agreement_id, issue_date, valid_from, valid_to
      INTO certificate_row
      FROM ewms.origin_certificates
     WHERE id = NEW.origin_certificate_id;

    SELECT item_id, trade_agreement_id, country_of_origin, determination_result,
           qualifying_quantity, uom_code, valid_from, valid_to, status
      INTO determination_row
      FROM ewms.origin_determinations
     WHERE id = NEW.origin_determination_id;

    IF determination_row.item_id IS DISTINCT FROM NEW.item_id
       OR determination_row.trade_agreement_id IS DISTINCT FROM certificate_row.trade_agreement_id
       OR determination_row.country_of_origin IS DISTINCT FROM NEW.origin_country_code
       OR determination_row.determination_result <> 'PASS'
       OR determination_row.status <> 'ACTIVE'
       OR certificate_row.issue_date < determination_row.valid_from
       OR (determination_row.valid_to IS NOT NULL AND certificate_row.issue_date > determination_row.valid_to)
       OR (determination_row.qualifying_quantity IS NOT NULL
           AND determination_row.uom_code = NEW.uom_code
           AND NEW.certified_quantity > determination_row.qualifying_quantity) THEN
        RAISE EXCEPTION 'Origin certificate line requires a matching, active PASS determination with sufficient quantity'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE TRIGGER trg_validate_origin_certificate_line
BEFORE INSERT OR UPDATE ON ewms.origin_certificate_lines
FOR EACH ROW EXECUTE PROCEDURE ewms.validate_origin_certificate_line();

CREATE OR REPLACE FUNCTION ewms.validate_origin_certificate_usage()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    target_line_id uuid;
    certified_qty numeric(24,8);
    projected_qty numeric(24,8);
    calculated_qty numeric(24,8);
BEGIN
    IF TG_OP = 'DELETE' THEN
        target_line_id := OLD.origin_certificate_line_id;
    ELSE
        IF TG_OP = 'UPDATE'
           AND NEW.origin_certificate_line_id IS DISTINCT FROM OLD.origin_certificate_line_id THEN
            RAISE EXCEPTION 'origin_certificate_line_id is immutable on usage rows'
                USING ERRCODE = '23514';
        END IF;
        target_line_id := NEW.origin_certificate_line_id;
    END IF;
    SELECT certified_quantity, used_quantity
      INTO certified_qty, projected_qty
      FROM ewms.origin_certificate_lines
     WHERE id = target_line_id
     FOR UPDATE;

    SELECT COALESCE(sum(CASE WHEN usage_status = 'ACTIVE' THEN used_quantity ELSE 0 END), 0)
      INTO calculated_qty
      FROM ewms.origin_certificate_uses
     WHERE origin_certificate_line_id = target_line_id;

    IF calculated_qty > certified_qty OR projected_qty IS DISTINCT FROM calculated_qty THEN
        RAISE EXCEPTION 'Origin certificate usage projection must equal active uses and cannot exceed certified quantity'
            USING ERRCODE = '23514';
    END IF;
    RETURN NULL;
END;
$function$;

CREATE CONSTRAINT TRIGGER trg_validate_origin_certificate_usage
AFTER INSERT OR UPDATE OR DELETE ON ewms.origin_certificate_uses
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE PROCEDURE ewms.validate_origin_certificate_usage();

CREATE OR REPLACE FUNCTION ewms.validate_license_usage()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    target_line_id uuid;
    line_row record;
    quantity_total numeric(24,8);
    value_total numeric(24,4);
BEGIN
    IF TG_OP = 'DELETE' THEN
        target_line_id := OLD.trade_license_line_id;
    ELSE
        IF TG_OP = 'UPDATE'
           AND NEW.trade_license_line_id IS DISTINCT FROM OLD.trade_license_line_id THEN
            RAISE EXCEPTION 'trade_license_line_id is immutable on usage rows'
                USING ERRCODE = '23514';
        END IF;
        target_line_id := NEW.trade_license_line_id;
    END IF;
    SELECT licensed_quantity, used_quantity, licensed_value, used_value
      INTO line_row
      FROM ewms.trade_license_lines
     WHERE id = target_line_id
     FOR UPDATE;

    SELECT
        COALESCE(sum(CASE
            WHEN status = 'POSTED' AND usage_type IN ('RESERVE','UTILIZE','ADJUST') THEN COALESCE(used_quantity, 0)
            WHEN status = 'POSTED' AND usage_type IN ('RELEASE','REVERSE') THEN -COALESCE(used_quantity, 0)
            ELSE 0 END), 0),
        COALESCE(sum(CASE
            WHEN status = 'POSTED' AND usage_type IN ('RESERVE','UTILIZE','ADJUST') THEN COALESCE(used_value, 0)
            WHEN status = 'POSTED' AND usage_type IN ('RELEASE','REVERSE') THEN -COALESCE(used_value, 0)
            ELSE 0 END), 0)
      INTO quantity_total, value_total
      FROM ewms.trade_license_usages
     WHERE trade_license_line_id = target_line_id;

    IF quantity_total < 0 OR value_total < 0
       OR (line_row.licensed_quantity IS NOT NULL AND quantity_total > line_row.licensed_quantity)
       OR (line_row.licensed_value IS NOT NULL AND value_total > line_row.licensed_value)
       OR line_row.used_quantity IS DISTINCT FROM quantity_total
       OR line_row.used_value IS DISTINCT FROM value_total THEN
        RAISE EXCEPTION 'Trade-license usage projection is inconsistent or exceeds the licensed limit'
            USING ERRCODE = '23514';
    END IF;
    RETURN NULL;
END;
$function$;

CREATE CONSTRAINT TRIGGER trg_validate_license_usage
AFTER INSERT OR UPDATE OR DELETE ON ewms.trade_license_usages
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE PROCEDURE ewms.validate_license_usage();

CREATE OR REPLACE FUNCTION ewms.validate_quota_usage()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    target_id uuid;
    allocation_row record;
    calculated_qty numeric(24,8);
BEGIN
    IF TG_OP = 'DELETE' THEN
        target_id := OLD.quota_allocation_id;
    ELSE
        IF TG_OP = 'UPDATE'
           AND NEW.quota_allocation_id IS DISTINCT FROM OLD.quota_allocation_id THEN
            RAISE EXCEPTION 'quota_allocation_id is immutable on usage rows'
                USING ERRCODE = '23514';
        END IF;
        target_id := NEW.quota_allocation_id;
    END IF;
    SELECT allocated_quantity, used_quantity
      INTO allocation_row
      FROM ewms.quota_allocations
     WHERE id = target_id
     FOR UPDATE;

    SELECT COALESCE(sum(CASE
        WHEN status = 'POSTED' AND usage_type IN ('RESERVE','UTILIZE','ADJUST') THEN used_quantity
        WHEN status = 'POSTED' AND usage_type IN ('RELEASE','REVERSE') THEN -used_quantity
        ELSE 0 END), 0)
      INTO calculated_qty
      FROM ewms.quota_usages
     WHERE quota_allocation_id = target_id;

    IF calculated_qty < 0 OR calculated_qty > allocation_row.allocated_quantity
       OR allocation_row.used_quantity IS DISTINCT FROM calculated_qty THEN
        RAISE EXCEPTION 'Quota usage projection is inconsistent or exceeds the allocation'
            USING ERRCODE = '23514';
    END IF;
    RETURN NULL;
END;
$function$;

CREATE CONSTRAINT TRIGGER trg_validate_quota_usage
AFTER INSERT OR UPDATE OR DELETE ON ewms.quota_usages
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE PROCEDURE ewms.validate_quota_usage();

CREATE OR REPLACE FUNCTION ewms.validate_payment_request_total()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    target_id uuid;
    header_amount numeric(24,4);
    line_amount numeric(24,4);
BEGIN
    IF TG_OP = 'DELETE' THEN
        target_id := OLD.payment_request_id;
    ELSE
        IF TG_OP = 'UPDATE'
           AND NEW.payment_request_id IS DISTINCT FROM OLD.payment_request_id THEN
            RAISE EXCEPTION 'payment_request_id is immutable on payment-request lines'
                USING ERRCODE = '23514';
        END IF;
        target_id := NEW.payment_request_id;
    END IF;
    SELECT requested_amount INTO header_amount
      FROM ewms.payment_requests
     WHERE id = target_id
     FOR UPDATE;
    SELECT COALESCE(sum(amount), 0) INTO line_amount
      FROM ewms.payment_request_lines
     WHERE payment_request_id = target_id;
    IF line_amount <> header_amount THEN
        RAISE EXCEPTION 'Payment-request line amount must equal the requested header amount'
            USING ERRCODE = '23514';
    END IF;
    RETURN NULL;
END;
$function$;

CREATE CONSTRAINT TRIGGER trg_validate_payment_request_total
AFTER INSERT OR UPDATE OR DELETE ON ewms.payment_request_lines
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE PROCEDURE ewms.validate_payment_request_total();

CREATE OR REPLACE FUNCTION ewms.validate_checklist_completion()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    IF NEW.status = 'COMPLETED' AND OLD.status IS DISTINCT FROM NEW.status THEN
        IF EXISTS (
            SELECT 1
              FROM ewms.document_checklist_items item
              LEFT JOIN ewms.document_checklist_results result
                ON result.document_checklist_instance_id = NEW.id
               AND result.document_checklist_item_id = item.id
             WHERE item.document_checklist_version_id = NEW.document_checklist_version_id
               AND item.is_required
               AND COALESCE(result.result_status, 'PENDING') NOT IN ('SATISFIED','NOT_APPLICABLE','WAIVED')
        ) THEN
            RAISE EXCEPTION 'Required checklist items must be satisfied, not applicable, or explicitly waived'
                USING ERRCODE = '23514';
        END IF;
        IF NEW.completed_at IS NULL OR NEW.completed_by IS NULL THEN
            RAISE EXCEPTION 'Checklist completion requires completed_at and completed_by'
                USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE TRIGGER trg_validate_checklist_completion
BEFORE UPDATE OF status ON ewms.document_checklist_instances
FOR EACH ROW EXECUTE PROCEDURE ewms.validate_checklist_completion();

CREATE OR REPLACE FUNCTION ewms.enforce_no_blocking_compliance_hold()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    row_data jsonb := to_jsonb(NEW);
    target_tenant uuid := (row_data ->> 'tenant_id')::uuid;
    target_shipment uuid;
    target_declaration uuid;
    new_status text;
BEGIN
    IF TG_TABLE_NAME = 'carrier_bookings' THEN
        target_shipment := NEW.trade_shipment_id;
        new_status := NEW.booking_status;
        IF new_status NOT IN ('CONFIRMED','CLOSED') THEN
            RETURN NEW;
        END IF;
    ELSIF TG_TABLE_NAME = 'trade_shipments' THEN
        target_shipment := NEW.id;
        new_status := NEW.status;
        IF new_status NOT IN ('BOOKED','IN_TRANSIT','ARRIVED','CUSTOMS_RELEASED','DELIVERED','CLOSED') THEN
            RETURN NEW;
        END IF;
    ELSIF TG_TABLE_NAME = 'customs_declarations' THEN
        target_declaration := NEW.id;
        target_shipment := NEW.trade_shipment_id;
        new_status := NEW.workflow_status;
        IF new_status NOT IN ('SUBMITTED','ACCEPTED','UNDER_REVIEW','INSPECTION','ASSESSED','PAID','RELEASED','CLEARED') THEN
            RETURN NEW;
        END IF;
    ELSE
        RETURN NEW;
    END IF;

    IF EXISTS (
        SELECT 1
          FROM ewms.compliance_holds hold_row
         WHERE hold_row.tenant_id = target_tenant
           AND hold_row.severity = 'BLOCKING'
           AND hold_row.status IN ('OPEN','UNDER_REVIEW')
           AND (
               (target_declaration IS NOT NULL AND hold_row.customs_declaration_id = target_declaration) OR
               (target_shipment IS NOT NULL AND hold_row.trade_shipment_id = target_shipment) OR
               (
                   target_shipment IS NOT NULL AND hold_row.trade_case_id IN (
                       SELECT allocation.trade_case_id
                         FROM ewms.trade_case_shipments allocation
                        WHERE allocation.trade_shipment_id = target_shipment
                          AND allocation.released_at IS NULL
                   )
               )
           )
    ) THEN
        RAISE EXCEPTION 'Blocking trade-compliance hold prevents this operation'
            USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE TRIGGER trg_booking_blocking_compliance_hold
BEFORE INSERT OR UPDATE OF booking_status ON ewms.carrier_bookings
FOR EACH ROW EXECUTE PROCEDURE ewms.enforce_no_blocking_compliance_hold();

CREATE TRIGGER trg_trade_shipment_blocking_compliance_hold
BEFORE INSERT OR UPDATE OF status ON ewms.trade_shipments
FOR EACH ROW EXECUTE PROCEDURE ewms.enforce_no_blocking_compliance_hold();

CREATE TRIGGER trg_customs_declaration_blocking_compliance_hold
BEFORE INSERT OR UPDATE OF workflow_status ON ewms.customs_declarations
FOR EACH ROW EXECUTE PROCEDURE ewms.enforce_no_blocking_compliance_hold();

-- Operational indexes for EIMS queues, business lookups, and high-volume timelines.
CREATE INDEX IF NOT EXISTS ix_ewms_trade_case_work_queue
    ON ewms.trade_cases (tenant_id, status, priority, planned_complete_at, assigned_user_id)
    WHERE status IN ('OPEN','IN_PROGRESS','ON_HOLD');
CREATE INDEX IF NOT EXISTS ix_ewms_trade_case_owner_direction
    ON ewms.trade_cases (tenant_id, owner_partner_id, direction, created_at DESC);
CREATE INDEX IF NOT EXISTS ix_ewms_import_case_work_queue
    ON ewms.import_cases (tenant_id, status, expected_arrival_at, expected_release_at)
    WHERE status NOT IN ('CLOSED','CANCELLED');
CREATE INDEX IF NOT EXISTS ix_ewms_export_case_work_queue
    ON ewms.export_cases (tenant_id, status, cargo_ready_at, planned_departure_at)
    WHERE status NOT IN ('CLOSED','CANCELLED');
CREATE INDEX IF NOT EXISTS ix_ewms_booking_work_queue
    ON ewms.carrier_bookings (tenant_id, booking_status, updated_at, carrier_partner_id)
    WHERE booking_status IN ('REQUESTED','PENDING','AMENDMENT_PENDING');
CREATE INDEX IF NOT EXISTS ix_ewms_screening_queue
    ON ewms.screening_requests (tenant_id, status, requested_at, id)
    WHERE status IN ('QUEUED','RUNNING','REVIEW_REQUIRED','MATCH_FOUND','ERROR');
CREATE INDEX IF NOT EXISTS ix_ewms_screening_subject_name
    ON ewms.screening_requests (tenant_id, lower(subject_name_snapshot));
CREATE INDEX IF NOT EXISTS ix_ewms_compliance_entry_name
    ON ewms.compliance_list_entries (tenant_id, normalized_name);
CREATE INDEX IF NOT EXISTS ix_ewms_compliance_alias_name
    ON ewms.compliance_list_aliases (tenant_id, normalized_alias_name);
CREATE INDEX IF NOT EXISTS ix_ewms_blocking_hold_lookup
    ON ewms.compliance_holds (
        tenant_id, severity, status, trade_case_id, trade_shipment_id, customs_declaration_id
    ) WHERE severity = 'BLOCKING' AND status IN ('OPEN','UNDER_REVIEW');
CREATE INDEX IF NOT EXISTS ix_ewms_origin_certificate_active
    ON ewms.origin_certificates (tenant_id, trade_agreement_id, status, valid_to, certificate_no)
    WHERE status IN ('ISSUED','AMENDED');
CREATE INDEX IF NOT EXISTS ix_ewms_license_active
    ON ewms.trade_licenses (tenant_id, holder_partner_id, status, valid_to, license_type)
    WHERE status IN ('ACTIVE','SUSPENDED');
CREATE INDEX IF NOT EXISTS ix_ewms_claim_work_queue
    ON ewms.claims (tenant_id, status, filing_deadline, assigned_user_id)
    WHERE status NOT IN ('CLOSED','WITHDRAWN','REJECTED');
CREATE INDEX IF NOT EXISTS ix_ewms_checklist_work_queue
    ON ewms.document_checklist_instances (tenant_id, status, due_at, assigned_user_id)
    WHERE status IN ('OPEN','IN_PROGRESS','BLOCKED');
CREATE INDEX IF NOT EXISTS ix_ewms_integration_attempt_retry
    ON ewms.integration_message_attempts (tenant_id, next_retry_at, integration_message_id)
    WHERE status = 'RETRY_PENDING';
CREATE INDEX IF NOT EXISTS ix_ewms_trade_case_event_brin
    ON ewms.trade_case_events USING brin (occurred_at);
CREATE INDEX IF NOT EXISTS ix_ewms_screening_request_brin
    ON ewms.screening_requests USING brin (requested_at);
CREATE INDEX IF NOT EXISTS ix_ewms_compliance_event_brin
    ON ewms.compliance_events USING brin (occurred_at);
CREATE INDEX IF NOT EXISTS ix_ewms_claim_event_brin
    ON ewms.claim_events USING brin (occurred_at);
CREATE INDEX IF NOT EXISTS ix_ewms_workflow_event_brin
    ON ewms.workflow_events USING brin (occurred_at);

COMMENT ON TABLE ewms.trade_cases IS
    'EIMS business aggregate spanning commercial order, international shipment, customs, settlement, and evidence without conflating their legal or physical states.';
COMMENT ON TABLE ewms.import_cases IS
    'Import-specific lifecycle extension of trade_cases. Customs release is evidenced separately and is never inferred from warehouse receipt state.';
COMMENT ON TABLE ewms.export_cases IS
    'Export-specific lifecycle extension of trade_cases. Departure and declaration acceptance remain separately evidenced.';
COMMENT ON TABLE ewms.screening_requests IS
    'Immutable subject snapshot screened against explicitly pinned compliance-list versions; email or partner-master updates cannot rewrite screening history.';
COMMENT ON TABLE ewms.origin_calculations IS
    'FTA origin calculation pinned to an agreement/rule/BOM snapshot. Sealed calculations are immutable.';
COMMENT ON TABLE ewms.trade_license_usages IS
    'License reservation/utilization ledger. Posted rows are corrected by release/reversal rows, never by destructive edits.';
COMMENT ON TABLE ewms.claim_reserve_movements IS
    'Append-only insurance claim reserve ledger; current reserve on claims is a controlled projection.';
