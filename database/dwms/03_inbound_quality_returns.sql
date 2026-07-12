-- DWMS enterprise WMS schema - inbound orders, receiving, quality, putaway/cross-dock requests, and supplier returns.
-- PostgreSQL 11 compatible. Applied after 00_foundation_auth.sql, 01_reference_partner_item.sql,
-- and 02_warehouse_facility.sql. Canonical inventory lots, serials, LPNs, and postings are created in 04.

CREATE TABLE IF NOT EXISTS dwms.inbound_orders (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    inbound_order_no varchar(80) NOT NULL,
    order_type varchar(30) NOT NULL DEFAULT 'PURCHASE_RECEIPT',
    warehouse_id uuid NOT NULL REFERENCES dwms.warehouses(id),
    owner_partner_id uuid NOT NULL REFERENCES dwms.business_partners(id),
    supplier_partner_id uuid REFERENCES dwms.business_partners(id),
    ship_from_partner_id uuid REFERENCES dwms.business_partners(id),
    carrier_partner_id uuid REFERENCES dwms.business_partners(id),
    purchase_order_no varchar(120),
    supplier_reference varchar(200),
    transport_mode_code varchar(20) REFERENCES dwms.transport_modes(mode_code),
    expected_arrival_from timestamptz,
    expected_arrival_to timestamptz,
    required_receipt_date date,
    priority integer NOT NULL DEFAULT 100,
    receipt_tolerance_percent numeric(9,6),
    allow_partial_receipt boolean NOT NULL DEFAULT true,
    allow_over_receipt boolean NOT NULL DEFAULT false,
    requires_quality_inspection boolean NOT NULL DEFAULT false,
    bonded_goods_expected boolean NOT NULL DEFAULT false,
    customs_cargo_reference varchar(200),
    status varchar(30) NOT NULL DEFAULT 'DRAFT',
    source_system_id uuid REFERENCES dwms.external_systems(id),
    source_document_id varchar(300),
    correlation_id varchar(100),
    instructions text,
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_by uuid REFERENCES dwms.users(id),
    updated_by uuid REFERENCES dwms.users(id),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    cancelled_at timestamptz,
    closed_at timestamptz,
    UNIQUE (tenant_id, inbound_order_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_inbound_order_type CHECK (order_type IN (
        'PURCHASE_RECEIPT','ASN','TRANSFER_IN','CUSTOMER_RETURN','IMPORT_RECEIPT',
        'BONDED_RECEIPT','PRODUCTION_RECEIPT','CONSIGNMENT','OTHER'
    )),
    CONSTRAINT ck_inbound_order_status CHECK (status IN (
        'DRAFT','CONFIRMED','SCHEDULED','IN_TRANSIT','ARRIVED','RECEIVING',
        'PARTIALLY_RECEIVED','RECEIVED','CLOSED','ON_HOLD','CANCELLED'
    )),
    CONSTRAINT ck_inbound_order_window CHECK (
        expected_arrival_to IS NULL OR expected_arrival_from IS NULL OR
        expected_arrival_to >= expected_arrival_from
    ),
    CONSTRAINT ck_inbound_order_tolerance CHECK (
        receipt_tolerance_percent IS NULL OR receipt_tolerance_percent BETWEEN 0 AND 100
    ),
    CONSTRAINT ck_inbound_order_priority CHECK (priority >= 0),
    CONSTRAINT ck_inbound_order_source CHECK (
        source_document_id IS NULL OR source_system_id IS NOT NULL
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_inbound_order_external
    ON dwms.inbound_orders (tenant_id, source_system_id, source_document_id)
    WHERE source_system_id IS NOT NULL AND source_document_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS dwms.inbound_order_lines (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    inbound_order_id uuid NOT NULL,
    line_no integer NOT NULL,
    owner_partner_id uuid NOT NULL REFERENCES dwms.business_partners(id),
    item_id uuid NOT NULL REFERENCES dwms.items(id),
    item_packaging_id uuid REFERENCES dwms.item_packagings(id),
    expected_quantity numeric(24,8) NOT NULL,
    received_quantity numeric(24,8) NOT NULL DEFAULT 0,
    cancelled_quantity numeric(24,8) NOT NULL DEFAULT 0,
    uom_code varchar(20) NOT NULL REFERENCES dwms.units_of_measure(uom_code),
    expected_base_quantity numeric(24,8) NOT NULL,
    received_base_quantity numeric(24,8) NOT NULL DEFAULT 0,
    base_uom_code varchar(20) NOT NULL REFERENCES dwms.units_of_measure(uom_code),
    supplier_item_code varchar(120),
    expected_supplier_lot_no varchar(150),
    expected_manufactured_on date,
    expected_expires_on date,
    expected_country_of_origin char(2) REFERENCES dwms.countries(country_code),
    declared_unit_cost numeric(24,8),
    currency_code char(3) REFERENCES dwms.currencies(currency_code),
    quality_specification_id uuid,
    requires_quality_inspection boolean NOT NULL DEFAULT false,
    status varchar(30) NOT NULL DEFAULT 'OPEN',
    posting_status varchar(20) NOT NULL DEFAULT 'NOT_POSTED',
    instructions text,
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_by uuid REFERENCES dwms.users(id),
    updated_by uuid REFERENCES dwms.users(id),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (inbound_order_id, line_no),
    UNIQUE (tenant_id, id),
    FOREIGN KEY (tenant_id, inbound_order_id)
        REFERENCES dwms.inbound_orders(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_inbound_line_no CHECK (line_no > 0),
    CONSTRAINT ck_inbound_line_qty CHECK (
        expected_quantity > 0 AND expected_base_quantity > 0 AND
        received_quantity >= 0 AND received_base_quantity >= 0 AND
        cancelled_quantity >= 0 AND cancelled_quantity <= expected_quantity
    ),
    CONSTRAINT ck_inbound_line_cost CHECK (declared_unit_cost IS NULL OR declared_unit_cost >= 0),
    CONSTRAINT ck_inbound_line_dates CHECK (
        expected_expires_on IS NULL OR expected_manufactured_on IS NULL OR
        expected_expires_on >= expected_manufactured_on
    ),
    CONSTRAINT ck_inbound_line_status CHECK (status IN (
        'OPEN','SCHEDULED','RECEIVING','PARTIALLY_RECEIVED','RECEIVED','CLOSED','ON_HOLD','CANCELLED'
    )),
    CONSTRAINT ck_inbound_line_posting CHECK (posting_status IN (
        'NOT_POSTED','PARTIAL','POSTED','REVERSED','FAILED'
    ))
);

CREATE TABLE IF NOT EXISTS dwms.inbound_order_parties (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    inbound_order_id uuid NOT NULL,
    party_role varchar(30) NOT NULL,
    partner_id uuid REFERENCES dwms.business_partners(id),
    party_name_snapshot varchar(300) NOT NULL,
    business_no_snapshot varchar(80),
    contact_name_snapshot varchar(200),
    email_snapshot varchar(320),
    phone_masked_snapshot varchar(50),
    address_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (tenant_id, inbound_order_id)
        REFERENCES dwms.inbound_orders(tenant_id, id) ON DELETE RESTRICT,
    UNIQUE (inbound_order_id, party_role, partner_id),
    CONSTRAINT ck_inbound_party_role CHECK (party_role IN (
        'OWNER','SUPPLIER','SHIP_FROM','CARRIER','FORWARDER','CUSTOMS_BROKER',
        'BILL_TO','NOTIFY','OTHER'
    ))
);

CREATE TABLE IF NOT EXISTS dwms.inbound_order_references (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    inbound_order_id uuid NOT NULL,
    reference_type varchar(50) NOT NULL,
    reference_value varchar(300) NOT NULL,
    reference_line_no varchar(50),
    source_system_id uuid REFERENCES dwms.external_systems(id),
    is_primary boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (tenant_id, inbound_order_id)
        REFERENCES dwms.inbound_orders(tenant_id, id) ON DELETE RESTRICT,
    UNIQUE (inbound_order_id, reference_type, reference_value, reference_line_no)
);

CREATE TABLE IF NOT EXISTS dwms.inbound_order_status_history (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    inbound_order_id uuid NOT NULL,
    event_sequence integer NOT NULL,
    from_status varchar(30),
    to_status varchar(30) NOT NULL,
    reason_code_id uuid REFERENCES dwms.reason_codes(id),
    reason_text text,
    actor_user_id uuid REFERENCES dwms.users(id) ON DELETE SET NULL,
    source_system_id uuid REFERENCES dwms.external_systems(id),
    correlation_id varchar(100),
    occurred_at timestamptz NOT NULL DEFAULT now(),
    recorded_at timestamptz NOT NULL DEFAULT now(),
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    FOREIGN KEY (tenant_id, inbound_order_id)
        REFERENCES dwms.inbound_orders(tenant_id, id) ON DELETE RESTRICT,
    UNIQUE (inbound_order_id, event_sequence),
    CONSTRAINT ck_inbound_status_sequence CHECK (event_sequence > 0)
);

CREATE TABLE IF NOT EXISTS dwms.dock_appointments (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    appointment_no varchar(80) NOT NULL,
    warehouse_id uuid NOT NULL REFERENCES dwms.warehouses(id),
    appointment_type varchar(20) NOT NULL DEFAULT 'INBOUND',
    carrier_partner_id uuid REFERENCES dwms.business_partners(id),
    vehicle_registration_no varchar(80),
    trailer_no varchar(100),
    container_no varchar(50),
    driver_name varchar(150),
    driver_phone_masked varchar(50),
    scheduled_start_at timestamptz NOT NULL,
    scheduled_end_at timestamptz NOT NULL,
    check_in_at timestamptz,
    dock_door_id uuid REFERENCES dwms.dock_doors(id),
    dock_assigned_at timestamptz,
    service_started_at timestamptz,
    service_completed_at timestamptz,
    check_out_at timestamptz,
    pallet_count integer,
    package_count integer,
    estimated_weight numeric(24,6),
    weight_uom_code varchar(20) REFERENCES dwms.units_of_measure(uom_code),
    status varchar(30) NOT NULL DEFAULT 'REQUESTED',
    instructions text,
    created_by uuid REFERENCES dwms.users(id),
    updated_by uuid REFERENCES dwms.users(id),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, appointment_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_dock_appointment_type CHECK (appointment_type IN ('INBOUND','OUTBOUND','BOTH')),
    CONSTRAINT ck_dock_appointment_status CHECK (status IN (
        'REQUESTED','CONFIRMED','ARRIVED','CHECKED_IN','DOCK_ASSIGNED','IN_SERVICE',
        'COMPLETED','CHECKED_OUT','NO_SHOW','CANCELLED'
    )),
    CONSTRAINT ck_dock_appointment_window CHECK (scheduled_end_at > scheduled_start_at),
    CONSTRAINT ck_dock_appointment_counts CHECK (
        (pallet_count IS NULL OR pallet_count >= 0) AND
        (package_count IS NULL OR package_count >= 0) AND
        (estimated_weight IS NULL OR estimated_weight >= 0)
    ),
    CONSTRAINT ck_dock_appointment_actual_dates CHECK (
        (service_completed_at IS NULL OR service_started_at IS NULL OR service_completed_at >= service_started_at) AND
        (check_out_at IS NULL OR check_in_at IS NULL OR check_out_at >= check_in_at)
    )
);

CREATE TABLE IF NOT EXISTS dwms.dock_appointment_inbound_orders (
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    appointment_id uuid NOT NULL,
    inbound_order_id uuid NOT NULL,
    sequence_no integer NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (appointment_id, inbound_order_id),
    FOREIGN KEY (tenant_id, appointment_id)
        REFERENCES dwms.dock_appointments(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, inbound_order_id)
        REFERENCES dwms.inbound_orders(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_dock_appt_order_sequence CHECK (sequence_no > 0)
);

CREATE TABLE IF NOT EXISTS dwms.dock_appointment_history (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    appointment_id uuid NOT NULL,
    event_sequence integer NOT NULL,
    event_type varchar(40) NOT NULL,
    from_status varchar(30),
    to_status varchar(30),
    previous_dock_door_id uuid REFERENCES dwms.dock_doors(id),
    new_dock_door_id uuid REFERENCES dwms.dock_doors(id),
    reason_code_id uuid REFERENCES dwms.reason_codes(id),
    reason_text text,
    actor_user_id uuid REFERENCES dwms.users(id) ON DELETE SET NULL,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    recorded_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (tenant_id, appointment_id)
        REFERENCES dwms.dock_appointments(tenant_id, id) ON DELETE RESTRICT,
    UNIQUE (appointment_id, event_sequence),
    CONSTRAINT ck_dock_appt_history_sequence CHECK (event_sequence > 0)
);

CREATE TABLE IF NOT EXISTS dwms.receipts (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    receipt_no varchar(80) NOT NULL,
    receipt_type varchar(30) NOT NULL DEFAULT 'STANDARD',
    warehouse_id uuid NOT NULL REFERENCES dwms.warehouses(id),
    owner_partner_id uuid NOT NULL REFERENCES dwms.business_partners(id),
    inbound_order_id uuid,
    appointment_id uuid,
    receiving_location_id uuid REFERENCES dwms.warehouse_locations(id),
    receiving_inventory_status_id uuid REFERENCES dwms.inventory_statuses(id),
    supplier_partner_id uuid REFERENCES dwms.business_partners(id),
    carrier_partner_id uuid REFERENCES dwms.business_partners(id),
    vehicle_registration_no varchar(80),
    trailer_no varchar(100),
    container_no varchar(50),
    seal_no varchar(100),
    arrived_at timestamptz,
    receiving_started_at timestamptz,
    receiving_completed_at timestamptz,
    closed_at timestamptz,
    status varchar(30) NOT NULL DEFAULT 'DRAFT',
    posting_status varchar(20) NOT NULL DEFAULT 'NOT_POSTED',
    last_posted_at timestamptz,
    reversed_at timestamptz,
    is_blind_receipt boolean NOT NULL DEFAULT false,
    requires_quality_inspection boolean NOT NULL DEFAULT false,
    bonded_goods_received boolean NOT NULL DEFAULT false,
    customs_cargo_reference varchar(200),
    source_system_id uuid REFERENCES dwms.external_systems(id),
    source_document_id varchar(300),
    correlation_id varchar(100),
    remarks text,
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_by uuid REFERENCES dwms.users(id),
    updated_by uuid REFERENCES dwms.users(id),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, receipt_no),
    UNIQUE (tenant_id, id),
    FOREIGN KEY (tenant_id, inbound_order_id)
        REFERENCES dwms.inbound_orders(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, appointment_id)
        REFERENCES dwms.dock_appointments(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_receipt_type CHECK (receipt_type IN (
        'STANDARD','IMPORT','BONDED','TRANSFER','RETURN','PRODUCTION','CROSS_DOCK','UNPLANNED'
    )),
    CONSTRAINT ck_receipt_status CHECK (status IN (
        'DRAFT','OPEN','RECEIVING','PARTIALLY_RECEIVED','RECEIVED','INSPECTION',
        'COMPLETED','CLOSED','ON_HOLD','CANCELLED'
    )),
    CONSTRAINT ck_receipt_posting_status CHECK (posting_status IN (
        'NOT_POSTED','PARTIAL','POSTED','REVERSED','FAILED'
    )),
    CONSTRAINT ck_receipt_dates CHECK (
        (receiving_started_at IS NULL OR arrived_at IS NULL OR receiving_started_at >= arrived_at) AND
        (receiving_completed_at IS NULL OR receiving_started_at IS NULL OR receiving_completed_at >= receiving_started_at) AND
        (closed_at IS NULL OR receiving_completed_at IS NULL OR closed_at >= receiving_completed_at)
    ),
    CONSTRAINT ck_receipt_post_dates CHECK (
        (posting_status NOT IN ('POSTED','PARTIAL') OR last_posted_at IS NOT NULL) AND
        (posting_status <> 'REVERSED' OR reversed_at IS NOT NULL)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_receipt_external
    ON dwms.receipts (tenant_id, source_system_id, source_document_id)
    WHERE source_system_id IS NOT NULL AND source_document_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS dwms.receipt_lines (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    receipt_id uuid NOT NULL,
    line_no integer NOT NULL,
    inbound_order_line_id uuid,
    owner_partner_id uuid NOT NULL REFERENCES dwms.business_partners(id),
    item_id uuid NOT NULL REFERENCES dwms.items(id),
    item_packaging_id uuid REFERENCES dwms.item_packagings(id),
    expected_quantity numeric(24,8) NOT NULL DEFAULT 0,
    received_quantity numeric(24,8) NOT NULL DEFAULT 0,
    accepted_quantity numeric(24,8) NOT NULL DEFAULT 0,
    rejected_quantity numeric(24,8) NOT NULL DEFAULT 0,
    damaged_quantity numeric(24,8) NOT NULL DEFAULT 0,
    pending_inspection_quantity numeric(24,8) NOT NULL DEFAULT 0,
    uom_code varchar(20) NOT NULL REFERENCES dwms.units_of_measure(uom_code),
    expected_base_quantity numeric(24,8) NOT NULL DEFAULT 0,
    received_base_quantity numeric(24,8) NOT NULL DEFAULT 0,
    base_uom_code varchar(20) NOT NULL REFERENCES dwms.units_of_measure(uom_code),
    catch_weight numeric(24,8),
    catch_weight_uom_code varchar(20) REFERENCES dwms.units_of_measure(uom_code),
    receiving_location_id uuid REFERENCES dwms.warehouse_locations(id),
    target_inventory_status_id uuid REFERENCES dwms.inventory_statuses(id),
    quality_specification_id uuid,
    inspection_required boolean NOT NULL DEFAULT false,
    status varchar(30) NOT NULL DEFAULT 'OPEN',
    posting_status varchar(20) NOT NULL DEFAULT 'NOT_POSTED',
    first_received_at timestamptz,
    last_received_at timestamptz,
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_by uuid REFERENCES dwms.users(id),
    updated_by uuid REFERENCES dwms.users(id),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (receipt_id, line_no),
    UNIQUE (tenant_id, id),
    FOREIGN KEY (tenant_id, receipt_id)
        REFERENCES dwms.receipts(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, inbound_order_line_id)
        REFERENCES dwms.inbound_order_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_receipt_line_no CHECK (line_no > 0),
    CONSTRAINT ck_receipt_line_quantities CHECK (
        expected_quantity >= 0 AND received_quantity >= 0 AND
        accepted_quantity >= 0 AND rejected_quantity >= 0 AND
        damaged_quantity >= 0 AND pending_inspection_quantity >= 0 AND
        expected_base_quantity >= 0 AND received_base_quantity >= 0 AND
        received_quantity = accepted_quantity + rejected_quantity + damaged_quantity + pending_inspection_quantity
    ),
    CONSTRAINT ck_receipt_line_catch_weight CHECK (catch_weight IS NULL OR catch_weight >= 0),
    CONSTRAINT ck_receipt_line_status CHECK (status IN (
        'OPEN','RECEIVING','RECEIVED','INSPECTION','ACCEPTED','PARTIALLY_ACCEPTED',
        'REJECTED','CLOSED','ON_HOLD','CANCELLED'
    )),
    CONSTRAINT ck_receipt_line_posting CHECK (posting_status IN (
        'NOT_POSTED','PARTIAL','POSTED','REVERSED','FAILED'
    )),
    CONSTRAINT ck_receipt_line_times CHECK (
        last_received_at IS NULL OR first_received_at IS NULL OR last_received_at >= first_received_at
    )
);

CREATE TABLE IF NOT EXISTS dwms.receipt_lot_observations (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    receipt_line_id uuid NOT NULL,
    observation_no integer NOT NULL,
    supplier_lot_no varchar(150),
    manufacturer_lot_no varchar(150),
    manufactured_on date,
    expires_on date,
    best_before_on date,
    retest_on date,
    country_of_origin char(2) REFERENCES dwms.countries(country_code),
    received_quantity numeric(24,8) NOT NULL,
    accepted_quantity numeric(24,8) NOT NULL DEFAULT 0,
    rejected_quantity numeric(24,8) NOT NULL DEFAULT 0,
    damaged_quantity numeric(24,8) NOT NULL DEFAULT 0,
    pending_inspection_quantity numeric(24,8) NOT NULL DEFAULT 0,
    uom_code varchar(20) NOT NULL REFERENCES dwms.units_of_measure(uom_code),
    catch_weight numeric(24,8),
    catch_weight_uom_code varchar(20) REFERENCES dwms.units_of_measure(uom_code),
    observed_attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    barcode_value varchar(300),
    observed_by uuid REFERENCES dwms.users(id),
    observed_at timestamptz NOT NULL DEFAULT now(),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (receipt_line_id, observation_no),
    UNIQUE (tenant_id, id),
    FOREIGN KEY (tenant_id, receipt_line_id)
        REFERENCES dwms.receipt_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_receipt_lot_obs_qty CHECK (
        received_quantity > 0 AND accepted_quantity >= 0 AND rejected_quantity >= 0 AND
        damaged_quantity >= 0 AND pending_inspection_quantity >= 0 AND
        received_quantity = accepted_quantity + rejected_quantity + damaged_quantity + pending_inspection_quantity
    ),
    CONSTRAINT ck_receipt_lot_obs_dates CHECK (
        (expires_on IS NULL OR manufactured_on IS NULL OR expires_on >= manufactured_on) AND
        (best_before_on IS NULL OR manufactured_on IS NULL OR best_before_on >= manufactured_on) AND
        (retest_on IS NULL OR manufactured_on IS NULL OR retest_on >= manufactured_on)
    ),
    CONSTRAINT ck_receipt_lot_obs_weight CHECK (catch_weight IS NULL OR catch_weight >= 0)
);

CREATE TABLE IF NOT EXISTS dwms.receipt_serial_observations (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    receipt_line_id uuid NOT NULL,
    lot_observation_id uuid,
    serial_no varchar(300) NOT NULL,
    manufacturer_serial_no varchar(300),
    status varchar(20) NOT NULL DEFAULT 'RECEIVED',
    accepted boolean,
    rejection_reason_code_id uuid REFERENCES dwms.reason_codes(id),
    observed_attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    observed_by uuid REFERENCES dwms.users(id),
    observed_at timestamptz NOT NULL DEFAULT now(),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (tenant_id, receipt_line_id)
        REFERENCES dwms.receipt_lines(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, lot_observation_id)
        REFERENCES dwms.receipt_lot_observations(tenant_id, id) ON DELETE RESTRICT,
    UNIQUE (receipt_line_id, serial_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_receipt_serial_obs_status CHECK (status IN (
        'RECEIVED','PENDING_INSPECTION','ACCEPTED','REJECTED','DAMAGED','DUPLICATE','CANCELLED'
    ))
);

CREATE TABLE IF NOT EXISTS dwms.receipt_discrepancies (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    receipt_id uuid NOT NULL,
    receipt_line_id uuid,
    discrepancy_no integer NOT NULL,
    discrepancy_type varchar(40) NOT NULL,
    expected_quantity numeric(24,8),
    actual_quantity numeric(24,8),
    variance_quantity numeric(24,8),
    uom_code varchar(20) REFERENCES dwms.units_of_measure(uom_code),
    severity varchar(20) NOT NULL DEFAULT 'MEDIUM',
    status varchar(20) NOT NULL DEFAULT 'OPEN',
    reason_code_id uuid REFERENCES dwms.reason_codes(id),
    description text,
    resolution_code varchar(40),
    resolution_note text,
    reported_by uuid REFERENCES dwms.users(id),
    reported_at timestamptz NOT NULL DEFAULT now(),
    resolved_by uuid REFERENCES dwms.users(id),
    resolved_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (tenant_id, receipt_id)
        REFERENCES dwms.receipts(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, receipt_line_id)
        REFERENCES dwms.receipt_lines(tenant_id, id) ON DELETE RESTRICT,
    UNIQUE (receipt_id, discrepancy_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_receipt_discrepancy_type CHECK (discrepancy_type IN (
        'OVER','SHORT','DAMAGED','WRONG_ITEM','WRONG_LOT','DUPLICATE_SERIAL',
        'EXPIRED','SHELF_LIFE','PACKAGING','TEMPERATURE','DOCUMENT','CUSTOMS','OTHER'
    )),
    CONSTRAINT ck_receipt_discrepancy_severity CHECK (severity IN ('LOW','MEDIUM','HIGH','CRITICAL')),
    CONSTRAINT ck_receipt_discrepancy_status CHECK (status IN ('OPEN','UNDER_REVIEW','APPROVED','REJECTED','RESOLVED','CANCELLED')),
    CONSTRAINT ck_receipt_discrepancy_resolution CHECK (
        resolved_at IS NULL OR resolved_at >= reported_at
    )
);

CREATE TABLE IF NOT EXISTS dwms.receipt_status_history (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    receipt_id uuid NOT NULL,
    event_sequence integer NOT NULL,
    from_status varchar(30),
    to_status varchar(30) NOT NULL,
    from_posting_status varchar(20),
    to_posting_status varchar(20),
    reason_code_id uuid REFERENCES dwms.reason_codes(id),
    reason_text text,
    actor_user_id uuid REFERENCES dwms.users(id) ON DELETE SET NULL,
    source_system_id uuid REFERENCES dwms.external_systems(id),
    correlation_id varchar(100),
    occurred_at timestamptz NOT NULL DEFAULT now(),
    recorded_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (tenant_id, receipt_id)
        REFERENCES dwms.receipts(tenant_id, id) ON DELETE RESTRICT,
    UNIQUE (receipt_id, event_sequence),
    CONSTRAINT ck_receipt_status_sequence CHECK (event_sequence > 0)
);

CREATE TABLE IF NOT EXISTS dwms.unloading_tasks (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    task_no varchar(80) NOT NULL,
    receipt_id uuid NOT NULL,
    appointment_id uuid,
    dock_door_id uuid REFERENCES dwms.dock_doors(id),
    work_area_id uuid REFERENCES dwms.work_areas(id),
    equipment_id uuid REFERENCES dwms.material_handling_equipment(id),
    assigned_user_id uuid REFERENCES dwms.users(id),
    priority integer NOT NULL DEFAULT 100,
    expected_handling_units integer,
    completed_handling_units integer NOT NULL DEFAULT 0,
    planned_start_at timestamptz,
    planned_end_at timestamptz,
    started_at timestamptz,
    completed_at timestamptz,
    status varchar(20) NOT NULL DEFAULT 'OPEN',
    instructions text,
    created_by uuid REFERENCES dwms.users(id),
    updated_by uuid REFERENCES dwms.users(id),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, task_no),
    UNIQUE (tenant_id, id),
    FOREIGN KEY (tenant_id, receipt_id)
        REFERENCES dwms.receipts(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, appointment_id)
        REFERENCES dwms.dock_appointments(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_unloading_task_status CHECK (status IN (
        'OPEN','ASSIGNED','IN_PROGRESS','PAUSED','COMPLETED','EXCEPTION','CANCELLED'
    )),
    CONSTRAINT ck_unloading_task_counts CHECK (
        (expected_handling_units IS NULL OR expected_handling_units >= 0) AND completed_handling_units >= 0
    ),
    CONSTRAINT ck_unloading_task_dates CHECK (
        (planned_end_at IS NULL OR planned_start_at IS NULL OR planned_end_at >= planned_start_at) AND
        (completed_at IS NULL OR started_at IS NULL OR completed_at >= started_at)
    )
);

CREATE TABLE IF NOT EXISTS dwms.unloading_events (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    unloading_task_id uuid NOT NULL,
    event_sequence integer NOT NULL,
    event_type varchar(40) NOT NULL,
    receipt_line_id uuid,
    quantity numeric(24,8),
    uom_code varchar(20) REFERENCES dwms.units_of_measure(uom_code),
    equipment_id uuid REFERENCES dwms.material_handling_equipment(id),
    actor_user_id uuid REFERENCES dwms.users(id) ON DELETE SET NULL,
    source_location_text varchar(200),
    destination_location_id uuid REFERENCES dwms.warehouse_locations(id),
    exception_code varchar(80),
    note text,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    recorded_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (tenant_id, unloading_task_id)
        REFERENCES dwms.unloading_tasks(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, receipt_line_id)
        REFERENCES dwms.receipt_lines(tenant_id, id) ON DELETE RESTRICT,
    UNIQUE (unloading_task_id, event_sequence),
    CONSTRAINT ck_unloading_event_sequence CHECK (event_sequence > 0),
    CONSTRAINT ck_unloading_event_qty CHECK (quantity IS NULL OR quantity > 0)
);

CREATE TABLE IF NOT EXISTS dwms.quality_specifications (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    specification_code varchar(80) NOT NULL,
    specification_name varchar(200) NOT NULL,
    version_no integer NOT NULL DEFAULT 1,
    owner_partner_id uuid REFERENCES dwms.business_partners(id),
    item_id uuid REFERENCES dwms.items(id),
    item_category_id uuid REFERENCES dwms.item_categories(id),
    inspection_type varchar(30) NOT NULL DEFAULT 'RECEIPT',
    sampling_method varchar(30) NOT NULL DEFAULT 'FIXED',
    sample_size numeric(24,8),
    sample_percent numeric(9,6),
    acceptance_quality_limit numeric(9,6),
    valid_from date NOT NULL DEFAULT CURRENT_DATE,
    valid_to date,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    approved_by uuid REFERENCES dwms.users(id),
    approved_at timestamptz,
    created_by uuid REFERENCES dwms.users(id),
    updated_by uuid REFERENCES dwms.users(id),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, specification_code, version_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_quality_spec_scope CHECK (item_id IS NOT NULL OR item_category_id IS NOT NULL),
    CONSTRAINT ck_quality_spec_version CHECK (version_no > 0),
    CONSTRAINT ck_quality_spec_sampling CHECK (sampling_method IN ('FIXED','PERCENT','AQL','FULL','RULE_BASED')),
    CONSTRAINT ck_quality_spec_sample_values CHECK (
        (sample_size IS NULL OR sample_size > 0) AND
        (sample_percent IS NULL OR sample_percent BETWEEN 0 AND 100) AND
        (acceptance_quality_limit IS NULL OR acceptance_quality_limit BETWEEN 0 AND 100)
    ),
    CONSTRAINT ck_quality_spec_dates CHECK (valid_to IS NULL OR valid_to >= valid_from),
    CONSTRAINT ck_quality_spec_status CHECK (status IN ('DRAFT','ACTIVE','SUSPENDED','OBSOLETE')),
    CONSTRAINT ck_quality_spec_approval CHECK (status <> 'ACTIVE' OR approved_at IS NOT NULL)
);

ALTER TABLE dwms.inbound_order_lines
    DROP CONSTRAINT IF EXISTS fk_inbound_line_quality_spec;
ALTER TABLE dwms.inbound_order_lines
    ADD CONSTRAINT fk_inbound_line_quality_spec
    FOREIGN KEY (quality_specification_id) REFERENCES dwms.quality_specifications(id);

ALTER TABLE dwms.receipt_lines
    DROP CONSTRAINT IF EXISTS fk_receipt_line_quality_spec;
ALTER TABLE dwms.receipt_lines
    ADD CONSTRAINT fk_receipt_line_quality_spec
    FOREIGN KEY (quality_specification_id) REFERENCES dwms.quality_specifications(id);

CREATE TABLE IF NOT EXISTS dwms.quality_specification_tests (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    quality_specification_id uuid NOT NULL,
    test_sequence integer NOT NULL,
    test_code varchar(80) NOT NULL,
    test_name varchar(200) NOT NULL,
    result_data_type varchar(20) NOT NULL,
    min_value numeric(24,10),
    max_value numeric(24,10),
    target_value numeric(24,10),
    uom_code varchar(20) REFERENCES dwms.units_of_measure(uom_code),
    expected_code varchar(100),
    pass_values jsonb NOT NULL DEFAULT '[]'::jsonb,
    destructive_test boolean NOT NULL DEFAULT false,
    required boolean NOT NULL DEFAULT true,
    instructions text,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (tenant_id, quality_specification_id)
        REFERENCES dwms.quality_specifications(tenant_id, id) ON DELETE RESTRICT,
    UNIQUE (quality_specification_id, test_sequence),
    UNIQUE (quality_specification_id, test_code),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_quality_spec_test_sequence CHECK (test_sequence > 0),
    CONSTRAINT ck_quality_spec_test_type CHECK (result_data_type IN (
        'NUMBER','TEXT','BOOLEAN','CODE','DATE','TIMESTAMP','IMAGE','DOCUMENT'
    )),
    CONSTRAINT ck_quality_spec_test_range CHECK (max_value IS NULL OR min_value IS NULL OR max_value >= min_value)
);

CREATE TABLE IF NOT EXISTS dwms.quality_inspections (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    inspection_no varchar(80) NOT NULL,
    inspection_type varchar(30) NOT NULL DEFAULT 'RECEIPT',
    warehouse_id uuid NOT NULL REFERENCES dwms.warehouses(id),
    owner_partner_id uuid NOT NULL REFERENCES dwms.business_partners(id),
    item_id uuid NOT NULL REFERENCES dwms.items(id),
    receipt_id uuid,
    receipt_line_id uuid,
    quality_specification_id uuid NOT NULL,
    inspector_user_id uuid REFERENCES dwms.users(id),
    assigned_at timestamptz,
    started_at timestamptz,
    completed_at timestamptz,
    inspected_quantity numeric(24,8) NOT NULL DEFAULT 0,
    accepted_quantity numeric(24,8) NOT NULL DEFAULT 0,
    rejected_quantity numeric(24,8) NOT NULL DEFAULT 0,
    uom_code varchar(20) NOT NULL REFERENCES dwms.units_of_measure(uom_code),
    result varchar(30) NOT NULL DEFAULT 'PENDING',
    status varchar(20) NOT NULL DEFAULT 'OPEN',
    conclusion text,
    approved_by uuid REFERENCES dwms.users(id),
    approved_at timestamptz,
    created_by uuid REFERENCES dwms.users(id),
    updated_by uuid REFERENCES dwms.users(id),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, inspection_no),
    UNIQUE (tenant_id, id),
    FOREIGN KEY (tenant_id, receipt_id)
        REFERENCES dwms.receipts(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, receipt_line_id)
        REFERENCES dwms.receipt_lines(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, quality_specification_id)
        REFERENCES dwms.quality_specifications(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_quality_inspection_source CHECK (receipt_id IS NOT NULL OR receipt_line_id IS NOT NULL),
    CONSTRAINT ck_quality_inspection_qty CHECK (
        inspected_quantity >= 0 AND accepted_quantity >= 0 AND rejected_quantity >= 0 AND
        accepted_quantity + rejected_quantity <= inspected_quantity
    ),
    CONSTRAINT ck_quality_inspection_result CHECK (result IN (
        'PENDING','PASS','CONDITIONAL_PASS','PARTIAL_PASS','FAIL','NOT_APPLICABLE'
    )),
    CONSTRAINT ck_quality_inspection_status CHECK (status IN (
        'OPEN','ASSIGNED','IN_PROGRESS','AWAITING_RESULT','COMPLETED','APPROVED','CANCELLED'
    )),
    CONSTRAINT ck_quality_inspection_dates CHECK (
        completed_at IS NULL OR started_at IS NULL OR completed_at >= started_at
    )
);

CREATE TABLE IF NOT EXISTS dwms.quality_inspection_samples (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    quality_inspection_id uuid NOT NULL,
    sample_no integer NOT NULL,
    receipt_lot_observation_id uuid,
    receipt_serial_observation_id uuid,
    sample_quantity numeric(24,8) NOT NULL,
    uom_code varchar(20) NOT NULL REFERENCES dwms.units_of_measure(uom_code),
    destructive_quantity numeric(24,8) NOT NULL DEFAULT 0,
    sampled_by uuid REFERENCES dwms.users(id),
    sampled_at timestamptz NOT NULL DEFAULT now(),
    chain_of_custody_ref varchar(150),
    sample_location_id uuid REFERENCES dwms.warehouse_locations(id),
    status varchar(20) NOT NULL DEFAULT 'COLLECTED',
    notes text,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (tenant_id, quality_inspection_id)
        REFERENCES dwms.quality_inspections(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, receipt_lot_observation_id)
        REFERENCES dwms.receipt_lot_observations(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, receipt_serial_observation_id)
        REFERENCES dwms.receipt_serial_observations(tenant_id, id) ON DELETE RESTRICT,
    UNIQUE (quality_inspection_id, sample_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_quality_sample_no CHECK (sample_no > 0),
    CONSTRAINT ck_quality_sample_qty CHECK (
        sample_quantity > 0 AND destructive_quantity >= 0 AND destructive_quantity <= sample_quantity
    ),
    CONSTRAINT ck_quality_sample_status CHECK (status IN (
        'COLLECTED','IN_TEST','CONSUMED','RETAINED','RETURNED','DISPOSED','CANCELLED'
    ))
);

CREATE TABLE IF NOT EXISTS dwms.quality_inspection_tests (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    quality_inspection_id uuid NOT NULL,
    specification_test_id uuid NOT NULL,
    sample_id uuid,
    execution_sequence integer NOT NULL,
    assigned_user_id uuid REFERENCES dwms.users(id),
    laboratory_partner_id uuid REFERENCES dwms.business_partners(id),
    started_at timestamptz,
    completed_at timestamptz,
    status varchar(20) NOT NULL DEFAULT 'PENDING',
    final_result varchar(20) NOT NULL DEFAULT 'PENDING',
    equipment_reference varchar(150),
    method_reference varchar(200),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (tenant_id, quality_inspection_id)
        REFERENCES dwms.quality_inspections(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, specification_test_id)
        REFERENCES dwms.quality_specification_tests(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, sample_id)
        REFERENCES dwms.quality_inspection_samples(tenant_id, id) ON DELETE RESTRICT,
    UNIQUE (quality_inspection_id, execution_sequence),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_quality_test_execution_sequence CHECK (execution_sequence > 0),
    CONSTRAINT ck_quality_test_status CHECK (status IN (
        'PENDING','ASSIGNED','IN_PROGRESS','AWAITING_EXTERNAL','COMPLETED','CANCELLED'
    )),
    CONSTRAINT ck_quality_test_result CHECK (final_result IN (
        'PENDING','PASS','FAIL','INCONCLUSIVE','NOT_APPLICABLE'
    )),
    CONSTRAINT ck_quality_test_dates CHECK (completed_at IS NULL OR started_at IS NULL OR completed_at >= started_at)
);

CREATE TABLE IF NOT EXISTS dwms.quality_inspection_results (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    inspection_test_id uuid NOT NULL,
    result_sequence integer NOT NULL DEFAULT 1,
    numeric_value numeric(30,12),
    text_value text,
    boolean_value boolean,
    code_value varchar(200),
    date_value date,
    timestamp_value timestamptz,
    uom_code varchar(20) REFERENCES dwms.units_of_measure(uom_code),
    pass_flag boolean,
    out_of_spec boolean NOT NULL DEFAULT false,
    result_note text,
    file_id uuid REFERENCES dwms.files(id),
    measured_by uuid REFERENCES dwms.users(id),
    measured_at timestamptz NOT NULL DEFAULT now(),
    verified_by uuid REFERENCES dwms.users(id),
    verified_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (tenant_id, inspection_test_id)
        REFERENCES dwms.quality_inspection_tests(tenant_id, id) ON DELETE RESTRICT,
    UNIQUE (inspection_test_id, result_sequence),
    CONSTRAINT ck_quality_result_sequence CHECK (result_sequence > 0),
    CONSTRAINT ck_quality_result_value CHECK (
        num_nonnulls(numeric_value, text_value, boolean_value, code_value, date_value, timestamp_value, file_id) >= 1
    ),
    CONSTRAINT ck_quality_result_verify_date CHECK (verified_at IS NULL OR verified_at >= measured_at)
);

CREATE TABLE IF NOT EXISTS dwms.quality_holds (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    hold_no varchar(80) NOT NULL,
    warehouse_id uuid NOT NULL REFERENCES dwms.warehouses(id),
    owner_partner_id uuid NOT NULL REFERENCES dwms.business_partners(id),
    receipt_id uuid,
    receipt_line_id uuid,
    receipt_lot_observation_id uuid,
    quality_inspection_id uuid,
    hold_type varchar(30) NOT NULL DEFAULT 'QUALITY',
    held_quantity numeric(24,8),
    uom_code varchar(20) REFERENCES dwms.units_of_measure(uom_code),
    reason_code_id uuid REFERENCES dwms.reason_codes(id),
    reason_text text NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    placed_by uuid REFERENCES dwms.users(id),
    placed_at timestamptz NOT NULL DEFAULT now(),
    review_due_at timestamptz,
    released_by uuid REFERENCES dwms.users(id),
    released_at timestamptz,
    release_reason text,
    created_by uuid REFERENCES dwms.users(id),
    updated_by uuid REFERENCES dwms.users(id),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, hold_no),
    UNIQUE (tenant_id, id),
    FOREIGN KEY (tenant_id, receipt_id)
        REFERENCES dwms.receipts(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, receipt_line_id)
        REFERENCES dwms.receipt_lines(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, receipt_lot_observation_id)
        REFERENCES dwms.receipt_lot_observations(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, quality_inspection_id)
        REFERENCES dwms.quality_inspections(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_quality_hold_scope CHECK (
        num_nonnulls(receipt_id, receipt_line_id, receipt_lot_observation_id, quality_inspection_id) >= 1
    ),
    CONSTRAINT ck_quality_hold_qty CHECK (held_quantity IS NULL OR held_quantity > 0),
    CONSTRAINT ck_quality_hold_type CHECK (hold_type IN (
        'QUALITY','QUARANTINE','REGULATORY','CUSTOMER','SAFETY','DAMAGE','EXPIRY','RECALL','OTHER'
    )),
    CONSTRAINT ck_quality_hold_status CHECK (status IN ('ACTIVE','UNDER_REVIEW','PARTIALLY_RELEASED','RELEASED','CANCELLED')),
    CONSTRAINT ck_quality_hold_release CHECK (
        (status IN ('RELEASED','PARTIALLY_RELEASED') AND released_at IS NOT NULL) OR
        status NOT IN ('RELEASED','PARTIALLY_RELEASED')
    ),
    CONSTRAINT ck_quality_hold_dates CHECK (released_at IS NULL OR released_at >= placed_at)
);

CREATE TABLE IF NOT EXISTS dwms.quality_hold_status_history (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    quality_hold_id uuid NOT NULL,
    event_sequence integer NOT NULL,
    from_status varchar(20),
    to_status varchar(20) NOT NULL,
    changed_quantity numeric(24,8),
    reason_code_id uuid REFERENCES dwms.reason_codes(id),
    reason_text text,
    actor_user_id uuid REFERENCES dwms.users(id) ON DELETE SET NULL,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    recorded_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (tenant_id, quality_hold_id)
        REFERENCES dwms.quality_holds(tenant_id, id) ON DELETE RESTRICT,
    UNIQUE (quality_hold_id, event_sequence),
    CONSTRAINT ck_quality_hold_history_sequence CHECK (event_sequence > 0),
    CONSTRAINT ck_quality_hold_history_qty CHECK (changed_quantity IS NULL OR changed_quantity > 0)
);

CREATE TABLE IF NOT EXISTS dwms.quality_dispositions (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    quality_inspection_id uuid,
    quality_hold_id uuid,
    receipt_line_id uuid,
    disposition_sequence integer NOT NULL DEFAULT 1,
    disposition_code varchar(30) NOT NULL,
    disposition_quantity numeric(24,8) NOT NULL,
    uom_code varchar(20) NOT NULL REFERENCES dwms.units_of_measure(uom_code),
    target_inventory_status_id uuid REFERENCES dwms.inventory_statuses(id),
    target_location_id uuid REFERENCES dwms.warehouse_locations(id),
    supplier_return_required boolean NOT NULL DEFAULT false,
    rework_instructions text,
    reason_code_id uuid REFERENCES dwms.reason_codes(id),
    approved_by uuid REFERENCES dwms.users(id),
    approved_at timestamptz,
    executed_by uuid REFERENCES dwms.users(id),
    executed_at timestamptz,
    status varchar(20) NOT NULL DEFAULT 'PROPOSED',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (tenant_id, quality_inspection_id)
        REFERENCES dwms.quality_inspections(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, quality_hold_id)
        REFERENCES dwms.quality_holds(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, receipt_line_id)
        REFERENCES dwms.receipt_lines(tenant_id, id) ON DELETE RESTRICT,
    UNIQUE (quality_inspection_id, disposition_sequence),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_quality_disposition_scope CHECK (
        quality_inspection_id IS NOT NULL OR quality_hold_id IS NOT NULL OR receipt_line_id IS NOT NULL
    ),
    CONSTRAINT ck_quality_disposition_code CHECK (disposition_code IN (
        'ACCEPT','CONDITIONAL_ACCEPT','RELEASE','HOLD','REJECT','RETURN_TO_SUPPLIER',
        'REWORK','REPACK','RELABEL','SCRAP','DESTROY','DOWNGRADE','OTHER'
    )),
    CONSTRAINT ck_quality_disposition_qty CHECK (disposition_quantity > 0),
    CONSTRAINT ck_quality_disposition_status CHECK (status IN (
        'PROPOSED','APPROVED','REJECTED','IN_PROGRESS','EXECUTED','CANCELLED'
    )),
    CONSTRAINT ck_quality_disposition_dates CHECK (
        executed_at IS NULL OR approved_at IS NULL OR executed_at >= approved_at
    )
);

CREATE TABLE IF NOT EXISTS dwms.putaway_requests (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    request_no varchar(80) NOT NULL,
    warehouse_id uuid NOT NULL REFERENCES dwms.warehouses(id),
    owner_partner_id uuid NOT NULL REFERENCES dwms.business_partners(id),
    receipt_id uuid NOT NULL,
    receipt_line_id uuid NOT NULL,
    receipt_lot_observation_id uuid,
    requested_quantity numeric(24,8) NOT NULL,
    completed_quantity numeric(24,8) NOT NULL DEFAULT 0,
    cancelled_quantity numeric(24,8) NOT NULL DEFAULT 0,
    uom_code varchar(20) NOT NULL REFERENCES dwms.units_of_measure(uom_code),
    source_location_id uuid NOT NULL REFERENCES dwms.warehouse_locations(id),
    preferred_zone_id uuid REFERENCES dwms.warehouse_zones(id),
    preferred_location_id uuid REFERENCES dwms.warehouse_locations(id),
    target_inventory_status_id uuid REFERENCES dwms.inventory_statuses(id),
    putaway_strategy_id uuid REFERENCES dwms.putaway_strategies(id),
    priority integer NOT NULL DEFAULT 100,
    status varchar(20) NOT NULL DEFAULT 'OPEN',
    requested_by uuid REFERENCES dwms.users(id),
    requested_at timestamptz NOT NULL DEFAULT now(),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, request_no),
    UNIQUE (tenant_id, id),
    FOREIGN KEY (tenant_id, receipt_id)
        REFERENCES dwms.receipts(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, receipt_line_id)
        REFERENCES dwms.receipt_lines(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, receipt_lot_observation_id)
        REFERENCES dwms.receipt_lot_observations(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_putaway_request_qty CHECK (
        requested_quantity > 0 AND completed_quantity >= 0 AND cancelled_quantity >= 0 AND
        completed_quantity + cancelled_quantity <= requested_quantity
    ),
    CONSTRAINT ck_putaway_request_priority CHECK (priority >= 0),
    CONSTRAINT ck_putaway_request_status CHECK (status IN (
        'OPEN','PLANNED','RELEASED','IN_PROGRESS','PARTIALLY_COMPLETED','COMPLETED','ON_HOLD','CANCELLED'
    ))
);

CREATE TABLE IF NOT EXISTS dwms.crossdock_requests (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    request_no varchar(80) NOT NULL,
    warehouse_id uuid NOT NULL REFERENCES dwms.warehouses(id),
    owner_partner_id uuid NOT NULL REFERENCES dwms.business_partners(id),
    receipt_id uuid NOT NULL,
    receipt_line_id uuid NOT NULL,
    receipt_lot_observation_id uuid,
    outbound_reference_type varchar(50) NOT NULL,
    outbound_reference_id uuid,
    outbound_reference_no varchar(150),
    requested_quantity numeric(24,8) NOT NULL,
    allocated_quantity numeric(24,8) NOT NULL DEFAULT 0,
    completed_quantity numeric(24,8) NOT NULL DEFAULT 0,
    cancelled_quantity numeric(24,8) NOT NULL DEFAULT 0,
    uom_code varchar(20) NOT NULL REFERENCES dwms.units_of_measure(uom_code),
    staging_location_id uuid REFERENCES dwms.warehouse_locations(id),
    required_ship_at timestamptz,
    priority integer NOT NULL DEFAULT 100,
    status varchar(20) NOT NULL DEFAULT 'OPEN',
    requested_by uuid REFERENCES dwms.users(id),
    requested_at timestamptz NOT NULL DEFAULT now(),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, request_no),
    UNIQUE (tenant_id, id),
    FOREIGN KEY (tenant_id, receipt_id)
        REFERENCES dwms.receipts(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, receipt_line_id)
        REFERENCES dwms.receipt_lines(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, receipt_lot_observation_id)
        REFERENCES dwms.receipt_lot_observations(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_crossdock_request_qty CHECK (
        requested_quantity > 0 AND allocated_quantity >= 0 AND completed_quantity >= 0 AND cancelled_quantity >= 0 AND
        allocated_quantity <= requested_quantity AND completed_quantity + cancelled_quantity <= requested_quantity
    ),
    CONSTRAINT ck_crossdock_request_priority CHECK (priority >= 0),
    CONSTRAINT ck_crossdock_request_status CHECK (status IN (
        'OPEN','ALLOCATED','STAGED','LOADED','COMPLETED','ON_HOLD','CANCELLED'
    ))
);

CREATE TABLE IF NOT EXISTS dwms.supplier_return_orders (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    return_order_no varchar(80) NOT NULL,
    return_type varchar(30) NOT NULL DEFAULT 'RETURN_TO_SUPPLIER',
    warehouse_id uuid NOT NULL REFERENCES dwms.warehouses(id),
    owner_partner_id uuid NOT NULL REFERENCES dwms.business_partners(id),
    supplier_partner_id uuid NOT NULL REFERENCES dwms.business_partners(id),
    original_inbound_order_id uuid,
    original_receipt_id uuid,
    quality_hold_id uuid,
    supplier_authorization_no varchar(150),
    return_reason_code_id uuid REFERENCES dwms.reason_codes(id),
    return_reason_text text,
    requested_ship_date date,
    carrier_partner_id uuid REFERENCES dwms.business_partners(id),
    ship_to_address_id uuid REFERENCES dwms.addresses(id),
    status varchar(30) NOT NULL DEFAULT 'DRAFT',
    posting_status varchar(20) NOT NULL DEFAULT 'NOT_POSTED',
    approved_by uuid REFERENCES dwms.users(id),
    approved_at timestamptz,
    shipped_at timestamptz,
    closed_at timestamptz,
    source_system_id uuid REFERENCES dwms.external_systems(id),
    source_document_id varchar(300),
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_by uuid REFERENCES dwms.users(id),
    updated_by uuid REFERENCES dwms.users(id),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, return_order_no),
    UNIQUE (tenant_id, id),
    FOREIGN KEY (tenant_id, original_inbound_order_id)
        REFERENCES dwms.inbound_orders(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, original_receipt_id)
        REFERENCES dwms.receipts(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, quality_hold_id)
        REFERENCES dwms.quality_holds(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_supplier_return_type CHECK (return_type IN (
        'RETURN_TO_SUPPLIER','RECALL_RETURN','REJECT_AT_RECEIPT','REPAIR_RETURN','EXCHANGE_RETURN'
    )),
    CONSTRAINT ck_supplier_return_status CHECK (status IN (
        'DRAFT','REQUESTED','APPROVED','RELEASED','PICKING','PACKED','SHIPPED','CLOSED','REJECTED','CANCELLED'
    )),
    CONSTRAINT ck_supplier_return_posting CHECK (posting_status IN (
        'NOT_POSTED','PARTIAL','POSTED','REVERSED','FAILED'
    )),
    CONSTRAINT ck_supplier_return_dates CHECK (
        (shipped_at IS NULL OR approved_at IS NULL OR shipped_at >= approved_at) AND
        (closed_at IS NULL OR shipped_at IS NULL OR closed_at >= shipped_at)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_supplier_return_external
    ON dwms.supplier_return_orders (tenant_id, source_system_id, source_document_id)
    WHERE source_system_id IS NOT NULL AND source_document_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS dwms.supplier_return_order_lines (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    supplier_return_order_id uuid NOT NULL,
    line_no integer NOT NULL,
    original_receipt_line_id uuid,
    quality_disposition_id uuid,
    owner_partner_id uuid NOT NULL REFERENCES dwms.business_partners(id),
    item_id uuid NOT NULL REFERENCES dwms.items(id),
    requested_quantity numeric(24,8) NOT NULL,
    approved_quantity numeric(24,8) NOT NULL DEFAULT 0,
    shipped_quantity numeric(24,8) NOT NULL DEFAULT 0,
    cancelled_quantity numeric(24,8) NOT NULL DEFAULT 0,
    uom_code varchar(20) NOT NULL REFERENCES dwms.units_of_measure(uom_code),
    reason_code_id uuid REFERENCES dwms.reason_codes(id),
    supplier_lot_no varchar(150),
    country_of_origin char(2) REFERENCES dwms.countries(country_code),
    target_inventory_status_id uuid REFERENCES dwms.inventory_statuses(id),
    status varchar(20) NOT NULL DEFAULT 'OPEN',
    posting_status varchar(20) NOT NULL DEFAULT 'NOT_POSTED',
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_by uuid REFERENCES dwms.users(id),
    updated_by uuid REFERENCES dwms.users(id),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (tenant_id, supplier_return_order_id)
        REFERENCES dwms.supplier_return_orders(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, original_receipt_line_id)
        REFERENCES dwms.receipt_lines(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, quality_disposition_id)
        REFERENCES dwms.quality_dispositions(tenant_id, id) ON DELETE RESTRICT,
    UNIQUE (supplier_return_order_id, line_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_supplier_return_line_no CHECK (line_no > 0),
    CONSTRAINT ck_supplier_return_line_qty CHECK (
        requested_quantity > 0 AND approved_quantity >= 0 AND shipped_quantity >= 0 AND cancelled_quantity >= 0 AND
        approved_quantity <= requested_quantity AND shipped_quantity + cancelled_quantity <= approved_quantity
    ),
    CONSTRAINT ck_supplier_return_line_status CHECK (status IN (
        'OPEN','APPROVED','RELEASED','PICKING','PACKED','SHIPPED','CLOSED','CANCELLED'
    )),
    CONSTRAINT ck_supplier_return_line_posting CHECK (posting_status IN (
        'NOT_POSTED','PARTIAL','POSTED','REVERSED','FAILED'
    ))
);

CREATE TABLE IF NOT EXISTS dwms.supplier_return_status_history (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    supplier_return_order_id uuid NOT NULL,
    event_sequence integer NOT NULL,
    from_status varchar(30),
    to_status varchar(30) NOT NULL,
    from_posting_status varchar(20),
    to_posting_status varchar(20),
    reason_code_id uuid REFERENCES dwms.reason_codes(id),
    reason_text text,
    actor_user_id uuid REFERENCES dwms.users(id) ON DELETE SET NULL,
    correlation_id varchar(100),
    occurred_at timestamptz NOT NULL DEFAULT now(),
    recorded_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (tenant_id, supplier_return_order_id)
        REFERENCES dwms.supplier_return_orders(tenant_id, id) ON DELETE RESTRICT,
    UNIQUE (supplier_return_order_id, event_sequence),
    CONSTRAINT ck_supplier_return_history_seq CHECK (event_sequence > 0)
);

-- Finalized document children share-lock their parent.  This serializes child writes
-- with the parent's status update and prevents post-close quantity/master rewrites.
CREATE OR REPLACE FUNCTION dwms.guard_finalized_document_child()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, dwms
AS $function$
DECLARE
    parent_id uuid;
    parent_status text;
BEGIN
    FOR parent_id IN
        SELECT DISTINCT candidate_id
          FROM (VALUES
              (CASE WHEN TG_OP <> 'INSERT' THEN NULLIF(to_jsonb(OLD) ->> TG_ARGV[1], '')::uuid END),
              (CASE WHEN TG_OP <> 'DELETE' THEN NULLIF(to_jsonb(NEW) ->> TG_ARGV[1], '')::uuid END)
          ) AS candidate(candidate_id)
         WHERE candidate_id IS NOT NULL
         ORDER BY candidate_id
    LOOP
        parent_status := NULL;
        EXECUTE format('SELECT %I::text FROM dwms.%I WHERE id = $1 FOR SHARE',
                       TG_ARGV[2], TG_ARGV[0])
           INTO parent_status
           USING parent_id;
        IF parent_status IS NULL THEN
            RAISE EXCEPTION 'Referenced parent dwms.% % is unavailable', TG_ARGV[0], parent_id
                USING ERRCODE = '23503';
        END IF;
        IF parent_status = ANY (string_to_array(TG_ARGV[3], ',')) THEN
            RAISE EXCEPTION 'Core child rows of finalized dwms.% parent % (status %) are immutable',
                TG_ARGV[0], parent_id, parent_status USING ERRCODE = '55000';
        END IF;
    END LOOP;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION dwms.prevent_core_document_truncate()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    RAISE EXCEPTION 'Core document table %.% cannot be truncated', TG_TABLE_SCHEMA, TG_TABLE_NAME
        USING ERRCODE = '55000';
END;
$function$;

CREATE OR REPLACE FUNCTION dwms.protect_inbound_document_header()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    old_core jsonb;
    new_core jsonb;
BEGIN
    IF TG_TABLE_NAME = 'inbound_orders' THEN
        IF OLD.status IN ('CLOSED','CANCELLED') THEN
            RAISE EXCEPTION 'Finalized inbound order % is immutable', OLD.id
                USING ERRCODE = '55000';
        END IF;
    ELSE
        IF OLD.status IN ('CLOSED','CANCELLED') THEN
            RAISE EXCEPTION 'Finalized receipt % is immutable', OLD.id
                USING ERRCODE = '55000';
        END IF;
        IF OLD.status = 'COMPLETED' THEN
            IF TG_OP = 'DELETE' OR NEW.status NOT IN ('COMPLETED','CLOSED') THEN
                RAISE EXCEPTION 'Completed receipt % may only progress to CLOSED', OLD.id
                    USING ERRCODE = '55000';
            END IF;
            old_core := to_jsonb(OLD) - ARRAY[
                'status','posting_status','last_posted_at','reversed_at','closed_at',
                'updated_by','row_version','updated_at'
            ]::text[];
            new_core := to_jsonb(NEW) - ARRAY[
                'status','posting_status','last_posted_at','reversed_at','closed_at',
                'updated_by','row_version','updated_at'
            ]::text[];
            IF old_core IS DISTINCT FROM new_core THEN
                RAISE EXCEPTION 'Completed receipt % core fields are immutable', OLD.id
                    USING ERRCODE = '55000';
            END IF;
        END IF;
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_protect_inbound_document_header ON dwms.inbound_orders;
CREATE TRIGGER trg_protect_inbound_document_header
    BEFORE UPDATE OR DELETE ON dwms.inbound_orders
    FOR EACH ROW EXECUTE PROCEDURE dwms.protect_inbound_document_header();

DROP TRIGGER IF EXISTS trg_protect_receipt_header ON dwms.receipts;
CREATE TRIGGER trg_protect_receipt_header
    BEFORE UPDATE OR DELETE ON dwms.receipts
    FOR EACH ROW EXECUTE PROCEDURE dwms.protect_inbound_document_header();

DO $block$
DECLARE
    target record;
BEGIN
    FOR target IN
        SELECT * FROM (VALUES
            ('inbound_order_lines','inbound_order_id','inbound_orders','CLOSED,CANCELLED'),
            ('inbound_order_parties','inbound_order_id','inbound_orders','CLOSED,CANCELLED'),
            ('inbound_order_references','inbound_order_id','inbound_orders','CLOSED,CANCELLED'),
            ('dock_appointment_inbound_orders','inbound_order_id','inbound_orders','CLOSED,CANCELLED'),
            ('receipts','inbound_order_id','inbound_orders','CLOSED,CANCELLED'),
            ('receipt_lines','receipt_id','receipts','COMPLETED,CLOSED,CANCELLED'),
            ('receipt_discrepancies','receipt_id','receipts','COMPLETED,CLOSED,CANCELLED'),
            ('unloading_tasks','receipt_id','receipts','COMPLETED,CLOSED,CANCELLED'),
            ('quality_inspections','receipt_id','receipts','COMPLETED,CLOSED,CANCELLED'),
            ('quality_holds','receipt_id','receipts','COMPLETED,CLOSED,CANCELLED'),
            ('putaway_requests','receipt_id','receipts','COMPLETED,CLOSED,CANCELLED'),
            ('crossdock_requests','receipt_id','receipts','COMPLETED,CLOSED,CANCELLED')
        ) AS configured(table_name, parent_column, parent_table, frozen_statuses)
    LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS trg_guard_finalized_parent ON dwms.%I', target.table_name);
        EXECUTE format(
            'CREATE TRIGGER trg_guard_finalized_parent BEFORE INSERT OR UPDATE OR DELETE ON dwms.%I '
            'FOR EACH ROW EXECUTE PROCEDURE dwms.guard_finalized_document_child(%L,%L,%L,%L)',
            target.table_name, target.parent_table, target.parent_column, 'status', target.frozen_statuses
        );
        EXECUTE format('DROP TRIGGER IF EXISTS trg_prevent_core_truncate ON dwms.%I', target.table_name);
        EXECUTE format(
            'CREATE TRIGGER trg_prevent_core_truncate BEFORE TRUNCATE ON dwms.%I '
            'FOR EACH STATEMENT EXECUTE PROCEDURE dwms.prevent_core_document_truncate()',
            target.table_name
        );
    END LOOP;
END;
$block$;

-- Operational lookup and FK indexes.
CREATE INDEX IF NOT EXISTS ix_inbound_orders_worklist
    ON dwms.inbound_orders (tenant_id, warehouse_id, owner_partner_id, status, expected_arrival_from, id);
CREATE INDEX IF NOT EXISTS ix_inbound_orders_supplier
    ON dwms.inbound_orders (tenant_id, supplier_partner_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS ix_inbound_lines_item
    ON dwms.inbound_order_lines (tenant_id, owner_partner_id, item_id, status);
CREATE INDEX IF NOT EXISTS ix_inbound_parties_partner
    ON dwms.inbound_order_parties (tenant_id, partner_id, party_role);
CREATE INDEX IF NOT EXISTS ix_inbound_references_search
    ON dwms.inbound_order_references (tenant_id, reference_type, reference_value);
CREATE INDEX IF NOT EXISTS ix_inbound_status_history_order
    ON dwms.inbound_order_status_history (tenant_id, inbound_order_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS ix_dock_appointments_schedule
    ON dwms.dock_appointments (tenant_id, warehouse_id, status, scheduled_start_at, scheduled_end_at);
CREATE INDEX IF NOT EXISTS ix_dock_appointments_door
    ON dwms.dock_appointments (tenant_id, dock_door_id, scheduled_start_at)
    WHERE status NOT IN ('COMPLETED','CHECKED_OUT','NO_SHOW','CANCELLED');
CREATE INDEX IF NOT EXISTS ix_receipts_worklist
    ON dwms.receipts (tenant_id, warehouse_id, owner_partner_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS ix_receipts_inbound_order
    ON dwms.receipts (tenant_id, inbound_order_id, status);
CREATE INDEX IF NOT EXISTS ix_receipts_posting_pending
    ON dwms.receipts (tenant_id, warehouse_id, posting_status, receiving_completed_at)
    WHERE posting_status IN ('NOT_POSTED','PARTIAL','FAILED');
CREATE INDEX IF NOT EXISTS ix_receipt_lines_item
    ON dwms.receipt_lines (tenant_id, owner_partner_id, item_id, posting_status);
CREATE INDEX IF NOT EXISTS ix_receipt_lines_inbound_line
    ON dwms.receipt_lines (tenant_id, inbound_order_line_id);
CREATE INDEX IF NOT EXISTS ix_receipt_lot_observations_lot
    ON dwms.receipt_lot_observations (tenant_id, supplier_lot_no, expires_on);
CREATE INDEX IF NOT EXISTS ix_receipt_serial_observations_serial
    ON dwms.receipt_serial_observations (tenant_id, serial_no);
CREATE INDEX IF NOT EXISTS ix_receipt_discrepancies_open
    ON dwms.receipt_discrepancies (tenant_id, receipt_id, severity, reported_at)
    WHERE status IN ('OPEN','UNDER_REVIEW');
CREATE INDEX IF NOT EXISTS ix_receipt_status_history_receipt
    ON dwms.receipt_status_history (tenant_id, receipt_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS ix_unloading_tasks_queue
    ON dwms.unloading_tasks (tenant_id, status, priority, planned_start_at, id);
CREATE INDEX IF NOT EXISTS ix_quality_specs_item
    ON dwms.quality_specifications (tenant_id, owner_partner_id, item_id, status, valid_from);
CREATE INDEX IF NOT EXISTS ix_quality_inspections_queue
    ON dwms.quality_inspections (tenant_id, warehouse_id, status, assigned_at, id);
CREATE INDEX IF NOT EXISTS ix_quality_inspections_receipt_line
    ON dwms.quality_inspections (tenant_id, receipt_line_id, status);
CREATE INDEX IF NOT EXISTS ix_quality_holds_active
    ON dwms.quality_holds (tenant_id, warehouse_id, owner_partner_id, review_due_at)
    WHERE status IN ('ACTIVE','UNDER_REVIEW','PARTIALLY_RELEASED');
CREATE INDEX IF NOT EXISTS ix_quality_dispositions_pending
    ON dwms.quality_dispositions (tenant_id, status, approved_at)
    WHERE status IN ('PROPOSED','APPROVED','IN_PROGRESS');
CREATE INDEX IF NOT EXISTS ix_putaway_requests_queue
    ON dwms.putaway_requests (tenant_id, warehouse_id, status, priority, requested_at, id);
CREATE INDEX IF NOT EXISTS ix_crossdock_requests_queue
    ON dwms.crossdock_requests (tenant_id, warehouse_id, status, priority, required_ship_at, id);
CREATE INDEX IF NOT EXISTS ix_supplier_returns_worklist
    ON dwms.supplier_return_orders (tenant_id, warehouse_id, owner_partner_id, status, requested_ship_date, id);
CREATE INDEX IF NOT EXISTS ix_supplier_return_lines_item
    ON dwms.supplier_return_order_lines (tenant_id, owner_partner_id, item_id, status);

CREATE OR REPLACE FUNCTION dwms.reject_append_only_change()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    RAISE EXCEPTION '%.% is append-only; corrections require a new event row', TG_TABLE_SCHEMA, TG_TABLE_NAME;
END;
$function$;

DO $block$
DECLARE
    table_name text;
BEGIN
    FOREACH table_name IN ARRAY ARRAY[
        'inbound_orders','inbound_order_lines','dock_appointments','receipts','receipt_lines',
        'receipt_lot_observations','receipt_serial_observations','receipt_discrepancies',
        'unloading_tasks','quality_specifications','quality_specification_tests',
        'quality_inspections','quality_inspection_samples','quality_inspection_tests',
        'quality_inspection_results','quality_holds','quality_dispositions','putaway_requests',
        'crossdock_requests','supplier_return_orders','supplier_return_order_lines'
    ] LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS trg_touch_row ON dwms.%I', table_name);
        EXECUTE format(
            'CREATE TRIGGER trg_touch_row BEFORE UPDATE ON dwms.%I '
            'FOR EACH ROW EXECUTE PROCEDURE dwms.touch_row()', table_name
        );
    END LOOP;

    FOREACH table_name IN ARRAY ARRAY[
        'inbound_order_status_history','dock_appointment_history','receipt_status_history',
        'unloading_events','quality_hold_status_history','supplier_return_status_history'
    ] LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS trg_append_only ON dwms.%I', table_name);
        EXECUTE format(
            'CREATE TRIGGER trg_append_only BEFORE UPDATE OR DELETE ON dwms.%I '
            'FOR EACH ROW EXECUTE PROCEDURE dwms.reject_append_only_change()', table_name
        );
    END LOOP;
END;
$block$;

COMMENT ON TABLE dwms.receipt_lot_observations IS
    'Pre-inventory receiving observations. Canonical inventory_lots are created only by validated posting in 04_inventory_control.sql.';
COMMENT ON TABLE dwms.receipt_serial_observations IS
    'Pre-inventory serial scans. Duplicate and tracking checks are repeated when canonical serial_numbers are posted.';
COMMENT ON TABLE dwms.receipts IS
    'Physical receipt lifecycle. Operational status and inventory posting_status are deliberately separate for retry-safe processing.';
COMMENT ON TABLE dwms.quality_holds IS
    'Quality/regulatory hold intent before or after receipt. 04 maps it to concrete stock buckets without conflating physical and customs legal status.';
