-- DWMS enterprise WMS schema - outbound orders, allocation, waves, picking, packing, shipping, and customer returns.

CREATE TABLE IF NOT EXISTS dwms.carrier_services (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    carrier_partner_id uuid NOT NULL REFERENCES dwms.business_partners(id),
    service_code varchar(80) NOT NULL,
    service_name varchar(200) NOT NULL,
    transport_mode_code varchar(20) REFERENCES dwms.transport_modes(mode_code),
    service_level varchar(50),
    tracking_url_template text,
    label_format varchar(30),
    cutoff_time time,
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, carrier_partner_id, service_code)
);

CREATE TABLE IF NOT EXISTS dwms.outbound_orders (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    warehouse_id uuid NOT NULL REFERENCES dwms.warehouses(id),
    owner_partner_id uuid NOT NULL REFERENCES dwms.business_partners(id),
    outbound_order_no varchar(120) NOT NULL,
    order_type varchar(30) NOT NULL DEFAULT 'SALES',
    external_order_no varchar(200),
    customer_partner_id uuid REFERENCES dwms.business_partners(id),
    consignee_partner_id uuid REFERENCES dwms.business_partners(id),
    ship_to_address_id uuid NOT NULL REFERENCES dwms.addresses(id),
    bill_to_partner_id uuid REFERENCES dwms.business_partners(id),
    carrier_service_id uuid REFERENCES dwms.carrier_services(id),
    allocation_strategy_id uuid REFERENCES dwms.allocation_strategies(id),
    priority integer NOT NULL DEFAULT 100,
    requested_ship_at timestamptz,
    ship_not_before timestamptz,
    ship_not_after timestamptz,
    requested_delivery_from timestamptz,
    requested_delivery_to timestamptz,
    incoterm_code char(3) REFERENCES dwms.incoterms(incoterm_code),
    currency_code char(3) NOT NULL DEFAULT 'KRW' REFERENCES dwms.currencies(currency_code),
    declared_value numeric(24,4),
    freight_terms varchar(20) NOT NULL DEFAULT 'PREPAID',
    allow_partial_ship boolean NOT NULL DEFAULT true,
    allow_backorder boolean NOT NULL DEFAULT true,
    allow_substitution boolean NOT NULL DEFAULT false,
    temperature_controlled boolean NOT NULL DEFAULT false,
    dangerous_goods boolean NOT NULL DEFAULT false,
    status varchar(30) NOT NULL DEFAULT 'DRAFT',
    allocation_status varchar(20) NOT NULL DEFAULT 'NOT_ALLOCATED',
    wave_status varchar(20) NOT NULL DEFAULT 'NOT_WAVED',
    shipping_status varchar(20) NOT NULL DEFAULT 'NOT_SHIPPED',
    hold_status varchar(20) NOT NULL DEFAULT 'CLEAR',
    source_system_id uuid REFERENCES dwms.external_systems(id),
    idempotency_key varchar(300),
    instructions text,
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_by uuid REFERENCES dwms.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    cancelled_at timestamptz,
    closed_at timestamptz,
    UNIQUE (tenant_id, outbound_order_no),
    UNIQUE (tenant_id, source_system_id, idempotency_key),
    CONSTRAINT ck_dwms_out_order_type CHECK (order_type IN (
        'SALES','TRANSFER','CUSTOMER_RETURN_REPLACEMENT','SUPPLIER_RETURN','SAMPLE','DISPOSAL','EXPORT','OTHER'
    )),
    CONSTRAINT ck_dwms_out_order_priority CHECK (priority >= 0),
    CONSTRAINT ck_dwms_out_order_ship_window CHECK (ship_not_after IS NULL OR ship_not_before IS NULL OR ship_not_after >= ship_not_before),
    CONSTRAINT ck_dwms_out_order_delivery_window CHECK (requested_delivery_to IS NULL OR requested_delivery_from IS NULL OR requested_delivery_to >= requested_delivery_from),
    CONSTRAINT ck_dwms_out_order_value CHECK (declared_value IS NULL OR declared_value >= 0),
    CONSTRAINT ck_dwms_out_order_freight CHECK (freight_terms IN ('PREPAID','COLLECT','THIRD_PARTY','OTHER')),
    CONSTRAINT ck_dwms_out_order_status CHECK (status IN (
        'DRAFT','RELEASED','ALLOCATING','ALLOCATED','WAVED','PICKING','PICKED','PACKING','PACKED',
        'STAGED','LOADING','SHIPPED','PARTIALLY_SHIPPED','BACKORDERED','CANCELLED','CLOSED'
    )),
    CONSTRAINT ck_dwms_out_allocation_status CHECK (allocation_status IN ('NOT_ALLOCATED','PARTIAL','ALLOCATED','FAILED','RELEASED')),
    CONSTRAINT ck_dwms_out_wave_status CHECK (wave_status IN ('NOT_WAVED','PARTIAL','WAVED','RELEASED')),
    CONSTRAINT ck_dwms_out_shipping_status CHECK (shipping_status IN ('NOT_SHIPPED','PARTIAL','SHIPPED','REVERSED')),
    CONSTRAINT ck_dwms_out_hold_status CHECK (hold_status IN ('CLEAR','ON_HOLD','PARTIAL_HOLD'))
);

CREATE TABLE IF NOT EXISTS dwms.outbound_order_lines (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    outbound_order_id uuid NOT NULL REFERENCES dwms.outbound_orders(id) ON DELETE CASCADE,
    line_no integer NOT NULL,
    item_id uuid NOT NULL REFERENCES dwms.items(id),
    owner_item_code varchar(120),
    ordered_quantity numeric(24,8) NOT NULL,
    uom_code varchar(20) NOT NULL REFERENCES dwms.units_of_measure(uom_code),
    base_quantity numeric(24,8) NOT NULL,
    allocated_quantity numeric(24,8) NOT NULL DEFAULT 0,
    picked_quantity numeric(24,8) NOT NULL DEFAULT 0,
    packed_quantity numeric(24,8) NOT NULL DEFAULT 0,
    shipped_quantity numeric(24,8) NOT NULL DEFAULT 0,
    cancelled_quantity numeric(24,8) NOT NULL DEFAULT 0,
    backordered_quantity numeric(24,8) NOT NULL DEFAULT 0,
    requested_lot_no varchar(150),
    requested_serial_no varchar(200),
    minimum_expiry_date date,
    minimum_shelf_life_days integer,
    requested_country_of_origin char(2) REFERENCES dwms.countries(country_code),
    inventory_status_id uuid REFERENCES dwms.inventory_statuses(id),
    unit_price numeric(24,8),
    line_value numeric(24,4),
    status varchar(30) NOT NULL DEFAULT 'OPEN',
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (outbound_order_id, line_no),
    CONSTRAINT ck_dwms_out_line_no CHECK (line_no > 0),
    CONSTRAINT ck_dwms_out_line_qty CHECK (
        ordered_quantity > 0 AND base_quantity > 0 AND
        allocated_quantity >= 0 AND picked_quantity >= 0 AND packed_quantity >= 0 AND
        shipped_quantity >= 0 AND cancelled_quantity >= 0 AND backordered_quantity >= 0 AND
        allocated_quantity <= base_quantity AND picked_quantity <= allocated_quantity AND
        packed_quantity <= picked_quantity AND shipped_quantity <= packed_quantity AND
        cancelled_quantity + shipped_quantity <= base_quantity AND backordered_quantity <= base_quantity
    ),
    CONSTRAINT ck_dwms_out_line_shelf CHECK (minimum_shelf_life_days IS NULL OR minimum_shelf_life_days >= 0),
    CONSTRAINT ck_dwms_out_line_value CHECK ((unit_price IS NULL OR unit_price >= 0) AND (line_value IS NULL OR line_value >= 0)),
    CONSTRAINT ck_dwms_out_line_status CHECK (status IN (
        'OPEN','ALLOCATED','PARTIALLY_ALLOCATED','PICKING','PICKED','PACKED','PARTIALLY_SHIPPED','SHIPPED','BACKORDERED','CANCELLED','CLOSED'
    ))
);

CREATE TABLE IF NOT EXISTS dwms.outbound_order_parties (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    outbound_order_id uuid NOT NULL REFERENCES dwms.outbound_orders(id) ON DELETE CASCADE,
    party_role varchar(30) NOT NULL,
    partner_id uuid REFERENCES dwms.business_partners(id),
    party_name_snapshot varchar(300) NOT NULL,
    identifier_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
    address_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
    contact_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (outbound_order_id, party_role),
    CONSTRAINT ck_dwms_out_party_role CHECK (party_role IN (
        'OWNER','CUSTOMER','SHIPPER','CONSIGNEE','BILL_TO','CARRIER','FORWARDER','CUSTOMS_BROKER','NOTIFY'
    ))
);

CREATE TABLE IF NOT EXISTS dwms.outbound_order_references (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    outbound_order_id uuid NOT NULL REFERENCES dwms.outbound_orders(id) ON DELETE CASCADE,
    reference_type varchar(50) NOT NULL,
    reference_value varchar(300) NOT NULL,
    line_id uuid REFERENCES dwms.outbound_order_lines(id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (outbound_order_id, reference_type, reference_value)
);

CREATE TABLE IF NOT EXISTS dwms.outbound_order_holds (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    outbound_order_id uuid NOT NULL REFERENCES dwms.outbound_orders(id) ON DELETE CASCADE,
    outbound_order_line_id uuid REFERENCES dwms.outbound_order_lines(id) ON DELETE CASCADE,
    hold_type varchar(40) NOT NULL,
    reason_code_id uuid REFERENCES dwms.reason_codes(id),
    reason_text text,
    placed_by uuid REFERENCES dwms.users(id),
    placed_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz,
    released_by uuid REFERENCES dwms.users(id),
    released_at timestamptz,
    release_reason text,
    CONSTRAINT ck_dwms_out_hold_dates CHECK (
        (expires_at IS NULL OR expires_at > placed_at) AND (released_at IS NULL OR released_at >= placed_at)
    )
);

CREATE TABLE IF NOT EXISTS dwms.outbound_order_status_history (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    outbound_order_id uuid NOT NULL REFERENCES dwms.outbound_orders(id) ON DELETE CASCADE,
    sequence_no integer NOT NULL,
    from_status varchar(30),
    to_status varchar(30) NOT NULL,
    reason_code_id uuid REFERENCES dwms.reason_codes(id),
    reason_text text,
    actor_user_id uuid REFERENCES dwms.users(id),
    source_system_id uuid REFERENCES dwms.external_systems(id),
    correlation_id varchar(100),
    occurred_at timestamptz NOT NULL DEFAULT now(),
    recorded_at timestamptz NOT NULL DEFAULT now(),
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    UNIQUE (outbound_order_id, sequence_no),
    CONSTRAINT ck_dwms_out_status_sequence CHECK (sequence_no > 0)
);

CREATE TABLE IF NOT EXISTS dwms.allocation_runs (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    warehouse_id uuid NOT NULL REFERENCES dwms.warehouses(id),
    owner_partner_id uuid NOT NULL REFERENCES dwms.business_partners(id),
    allocation_run_no varchar(120) NOT NULL,
    strategy_id uuid REFERENCES dwms.allocation_strategies(id),
    run_type varchar(20) NOT NULL DEFAULT 'AUTO',
    requested_by uuid REFERENCES dwms.users(id),
    requested_at timestamptz NOT NULL DEFAULT now(),
    started_at timestamptz,
    completed_at timestamptz,
    status varchar(20) NOT NULL DEFAULT 'QUEUED',
    order_count integer NOT NULL DEFAULT 0,
    success_count integer NOT NULL DEFAULT 0,
    partial_count integer NOT NULL DEFAULT 0,
    failed_count integer NOT NULL DEFAULT 0,
    input_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
    result_summary jsonb NOT NULL DEFAULT '{}'::jsonb,
    UNIQUE (tenant_id, allocation_run_no),
    CONSTRAINT ck_dwms_alloc_run_type CHECK (run_type IN ('AUTO','MANUAL','RETRY','REBALANCE')),
    CONSTRAINT ck_dwms_alloc_run_counts CHECK (
        order_count >= 0 AND success_count >= 0 AND partial_count >= 0 AND failed_count >= 0 AND
        success_count + partial_count + failed_count <= order_count
    ),
    CONSTRAINT ck_dwms_alloc_run_dates CHECK (completed_at IS NULL OR started_at IS NULL OR completed_at >= started_at)
);

CREATE TABLE IF NOT EXISTS dwms.allocation_run_orders (
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    allocation_run_id uuid NOT NULL REFERENCES dwms.allocation_runs(id) ON DELETE CASCADE,
    outbound_order_id uuid NOT NULL REFERENCES dwms.outbound_orders(id),
    status varchar(20) NOT NULL DEFAULT 'PENDING',
    failure_code varchar(80),
    failure_detail text,
    PRIMARY KEY (allocation_run_id, outbound_order_id)
);

CREATE TABLE IF NOT EXISTS dwms.inventory_allocations (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    allocation_run_id uuid REFERENCES dwms.allocation_runs(id),
    outbound_order_id uuid NOT NULL REFERENCES dwms.outbound_orders(id),
    outbound_order_line_id uuid NOT NULL REFERENCES dwms.outbound_order_lines(id),
    stock_bucket_id uuid NOT NULL REFERENCES dwms.stock_buckets(id),
    reservation_id uuid REFERENCES dwms.inventory_reservations(id),
    allocated_quantity numeric(24,8) NOT NULL,
    base_uom_code varchar(20) NOT NULL REFERENCES dwms.units_of_measure(uom_code),
    allocation_sequence integer NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'ALLOCATED',
    allocated_by uuid REFERENCES dwms.users(id),
    allocated_at timestamptz NOT NULL DEFAULT now(),
    released_by uuid REFERENCES dwms.users(id),
    released_at timestamptz,
    release_reason text,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (outbound_order_line_id, allocation_sequence),
    CONSTRAINT ck_dwms_inventory_alloc_qty CHECK (allocated_quantity > 0),
    CONSTRAINT ck_dwms_inventory_alloc_seq CHECK (allocation_sequence > 0),
    CONSTRAINT ck_dwms_inventory_alloc_status CHECK (status IN ('ALLOCATED','PICKING','PICKED','RELEASED','CANCELLED','SHORT')),
    CONSTRAINT ck_dwms_inventory_alloc_release CHECK (released_at IS NULL OR released_at >= allocated_at)
);

CREATE TABLE IF NOT EXISTS dwms.waves (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    warehouse_id uuid NOT NULL REFERENCES dwms.warehouses(id),
    owner_partner_id uuid REFERENCES dwms.business_partners(id),
    wave_no varchar(120) NOT NULL,
    wave_type varchar(30) NOT NULL DEFAULT 'STANDARD',
    planning_method varchar(30) NOT NULL DEFAULT 'RULE_BASED',
    cutoff_at timestamptz,
    planned_start_at timestamptz,
    planned_complete_at timestamptz,
    priority integer NOT NULL DEFAULT 100,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    criteria_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
    released_by uuid REFERENCES dwms.users(id),
    released_at timestamptz,
    completed_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_by uuid REFERENCES dwms.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, wave_no),
    CONSTRAINT ck_dwms_wave_type CHECK (wave_type IN ('STANDARD','BATCH','ZONE','CLUSTER','ORDER','CARRIER','EXPEDITE','REPLENISHMENT')),
    CONSTRAINT ck_dwms_wave_priority CHECK (priority >= 0),
    CONSTRAINT ck_dwms_wave_status CHECK (status IN ('DRAFT','PLANNED','RELEASED','IN_PROGRESS','PAUSED','COMPLETED','CANCELLED')),
    CONSTRAINT ck_dwms_wave_dates CHECK (planned_complete_at IS NULL OR planned_start_at IS NULL OR planned_complete_at >= planned_start_at)
);

CREATE TABLE IF NOT EXISTS dwms.wave_orders (
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    wave_id uuid NOT NULL REFERENCES dwms.waves(id) ON DELETE CASCADE,
    outbound_order_id uuid NOT NULL REFERENCES dwms.outbound_orders(id),
    sequence_no integer NOT NULL DEFAULT 1,
    added_at timestamptz NOT NULL DEFAULT now(),
    removed_at timestamptz,
    PRIMARY KEY (wave_id, outbound_order_id),
    CONSTRAINT ck_dwms_wave_order_seq CHECK (sequence_no > 0)
);

CREATE TABLE IF NOT EXISTS dwms.wave_status_history (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    wave_id uuid NOT NULL REFERENCES dwms.waves(id) ON DELETE CASCADE,
    sequence_no integer NOT NULL,
    from_status varchar(20),
    to_status varchar(20) NOT NULL,
    actor_user_id uuid REFERENCES dwms.users(id),
    reason text,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (wave_id, sequence_no),
    CONSTRAINT ck_dwms_wave_status_seq CHECK (sequence_no > 0)
);

CREATE TABLE IF NOT EXISTS dwms.pick_tasks (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    warehouse_id uuid NOT NULL REFERENCES dwms.warehouses(id),
    owner_partner_id uuid NOT NULL REFERENCES dwms.business_partners(id),
    task_no varchar(120) NOT NULL,
    wave_id uuid REFERENCES dwms.waves(id),
    outbound_order_id uuid NOT NULL REFERENCES dwms.outbound_orders(id),
    pick_method varchar(30) NOT NULL DEFAULT 'DISCRETE',
    source_zone_id uuid REFERENCES dwms.warehouse_zones(id),
    destination_location_id uuid REFERENCES dwms.warehouse_locations(id),
    priority integer NOT NULL DEFAULT 100,
    sequence_no integer NOT NULL DEFAULT 1,
    status varchar(20) NOT NULL DEFAULT 'OPEN',
    assigned_user_id uuid REFERENCES dwms.users(id),
    assigned_equipment_id uuid REFERENCES dwms.material_handling_equipment(id),
    scheduled_at timestamptz,
    started_at timestamptz,
    completed_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, task_no),
    CONSTRAINT ck_dwms_pick_method CHECK (pick_method IN ('DISCRETE','BATCH','ZONE','CLUSTER','WAVE','CARTON','PALLET','VOICE','ROBOT')),
    CONSTRAINT ck_dwms_pick_task_priority CHECK (priority >= 0),
    CONSTRAINT ck_dwms_pick_task_status CHECK (status IN ('OPEN','ASSIGNED','IN_PROGRESS','PAUSED','COMPLETED','SHORT','CANCELLED')),
    CONSTRAINT ck_dwms_pick_task_dates CHECK (completed_at IS NULL OR started_at IS NULL OR completed_at >= started_at)
);

CREATE TABLE IF NOT EXISTS dwms.pick_task_lines (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    pick_task_id uuid NOT NULL REFERENCES dwms.pick_tasks(id) ON DELETE CASCADE,
    line_no integer NOT NULL,
    allocation_id uuid NOT NULL REFERENCES dwms.inventory_allocations(id),
    outbound_order_line_id uuid NOT NULL REFERENCES dwms.outbound_order_lines(id),
    stock_bucket_id uuid NOT NULL REFERENCES dwms.stock_buckets(id),
    source_location_id uuid NOT NULL REFERENCES dwms.warehouse_locations(id),
    destination_location_id uuid REFERENCES dwms.warehouse_locations(id),
    requested_quantity numeric(24,8) NOT NULL,
    picked_quantity numeric(24,8) NOT NULL DEFAULT 0,
    short_quantity numeric(24,8) NOT NULL DEFAULT 0,
    uom_code varchar(20) NOT NULL REFERENCES dwms.units_of_measure(uom_code),
    status varchar(20) NOT NULL DEFAULT 'OPEN',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (pick_task_id, line_no),
    CONSTRAINT ck_dwms_pick_line_no CHECK (line_no > 0),
    CONSTRAINT ck_dwms_pick_line_qty CHECK (
        requested_quantity > 0 AND picked_quantity >= 0 AND short_quantity >= 0 AND
        picked_quantity + short_quantity <= requested_quantity
    ),
    CONSTRAINT ck_dwms_pick_line_status CHECK (status IN ('OPEN','IN_PROGRESS','PICKED','SHORT','SKIPPED','CANCELLED'))
);

CREATE TABLE IF NOT EXISTS dwms.pick_task_assignments (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    pick_task_id uuid NOT NULL REFERENCES dwms.pick_tasks(id) ON DELETE CASCADE,
    user_id uuid REFERENCES dwms.users(id),
    equipment_id uuid REFERENCES dwms.material_handling_equipment(id),
    assigned_by uuid REFERENCES dwms.users(id),
    assigned_at timestamptz NOT NULL DEFAULT now(),
    accepted_at timestamptz,
    released_at timestamptz,
    status varchar(20) NOT NULL DEFAULT 'ASSIGNED',
    CONSTRAINT ck_dwms_pick_assignment_target CHECK (user_id IS NOT NULL OR equipment_id IS NOT NULL),
    CONSTRAINT ck_dwms_pick_assignment_dates CHECK (
        (accepted_at IS NULL OR accepted_at >= assigned_at) AND (released_at IS NULL OR released_at >= assigned_at)
    )
);

CREATE TABLE IF NOT EXISTS dwms.pick_confirmations (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    pick_task_line_id uuid NOT NULL REFERENCES dwms.pick_task_lines(id),
    confirmation_no integer NOT NULL,
    source_stock_bucket_id uuid NOT NULL REFERENCES dwms.stock_buckets(id),
    destination_stock_bucket_id uuid REFERENCES dwms.stock_buckets(id),
    picked_quantity numeric(24,8) NOT NULL,
    uom_code varchar(20) NOT NULL REFERENCES dwms.units_of_measure(uom_code),
    inventory_transaction_id uuid REFERENCES dwms.inventory_transaction_headers(id),
    scanned_item_barcode varchar(200),
    scanned_location_barcode varchar(200),
    scanned_lpn_barcode varchar(200),
    confirmed_by uuid REFERENCES dwms.users(id),
    confirmed_at timestamptz NOT NULL DEFAULT now(),
    source_device_id uuid REFERENCES dwms.rf_devices(id),
    idempotency_key varchar(300) NOT NULL,
    reversed_confirmation_id uuid REFERENCES dwms.pick_confirmations(id),
    UNIQUE (pick_task_line_id, confirmation_no),
    UNIQUE (tenant_id, idempotency_key),
    CONSTRAINT ck_dwms_pick_confirmation_no CHECK (confirmation_no > 0),
    CONSTRAINT ck_dwms_pick_confirmation_qty CHECK (picked_quantity > 0),
    CONSTRAINT ck_dwms_pick_confirmation_reversal CHECK (reversed_confirmation_id IS NULL OR reversed_confirmation_id <> id)
);

CREATE TABLE IF NOT EXISTS dwms.pick_exceptions (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    pick_task_line_id uuid NOT NULL REFERENCES dwms.pick_task_lines(id),
    exception_type varchar(40) NOT NULL,
    exception_quantity numeric(24,8),
    reason_code_id uuid REFERENCES dwms.reason_codes(id),
    detail text,
    reported_by uuid REFERENCES dwms.users(id),
    reported_at timestamptz NOT NULL DEFAULT now(),
    resolution_status varchar(20) NOT NULL DEFAULT 'OPEN',
    resolved_by uuid REFERENCES dwms.users(id),
    resolved_at timestamptz,
    resolution_action varchar(50),
    CONSTRAINT ck_dwms_pick_exception_qty CHECK (exception_quantity IS NULL OR exception_quantity > 0),
    CONSTRAINT ck_dwms_pick_exception_status CHECK (resolution_status IN ('OPEN','INVESTIGATING','RESOLVED','WAIVED')),
    CONSTRAINT ck_dwms_pick_exception_dates CHECK (resolved_at IS NULL OR resolved_at >= reported_at)
);

CREATE TABLE IF NOT EXISTS dwms.packing_sessions (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    warehouse_id uuid NOT NULL REFERENCES dwms.warehouses(id),
    owner_partner_id uuid NOT NULL REFERENCES dwms.business_partners(id),
    session_no varchar(120) NOT NULL,
    workstation_id uuid REFERENCES dwms.workstations(id),
    outbound_order_id uuid REFERENCES dwms.outbound_orders(id),
    wave_id uuid REFERENCES dwms.waves(id),
    operator_user_id uuid REFERENCES dwms.users(id),
    status varchar(20) NOT NULL DEFAULT 'OPEN',
    started_at timestamptz NOT NULL DEFAULT now(),
    completed_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, session_no),
    CONSTRAINT ck_dwms_packing_session_scope CHECK (outbound_order_id IS NOT NULL OR wave_id IS NOT NULL),
    CONSTRAINT ck_dwms_packing_session_status CHECK (status IN ('OPEN','IN_PROGRESS','PAUSED','COMPLETED','CANCELLED')),
    CONSTRAINT ck_dwms_packing_session_dates CHECK (completed_at IS NULL OR completed_at >= started_at)
);

CREATE TABLE IF NOT EXISTS dwms.packages (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    warehouse_id uuid NOT NULL REFERENCES dwms.warehouses(id),
    owner_partner_id uuid NOT NULL REFERENCES dwms.business_partners(id),
    packing_session_id uuid REFERENCES dwms.packing_sessions(id),
    outbound_order_id uuid REFERENCES dwms.outbound_orders(id),
    lpn_id uuid REFERENCES dwms.lpns(id),
    parent_package_id uuid REFERENCES dwms.packages(id),
    package_no varchar(150) NOT NULL,
    package_type varchar(30) NOT NULL,
    packaging_material_id uuid REFERENCES dwms.packaging_materials(id),
    sscc varchar(30),
    gross_weight numeric(24,8),
    net_weight numeric(24,8),
    weight_uom_code varchar(20) REFERENCES dwms.units_of_measure(uom_code),
    length_value numeric(20,6),
    width_value numeric(20,6),
    height_value numeric(20,6),
    dimension_uom_code varchar(20) REFERENCES dwms.units_of_measure(uom_code),
    declared_value numeric(24,4),
    currency_code char(3) REFERENCES dwms.currencies(currency_code),
    sealed boolean NOT NULL DEFAULT false,
    sealed_at timestamptz,
    status varchar(20) NOT NULL DEFAULT 'OPEN',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, package_no),
    CONSTRAINT ck_dwms_package_parent CHECK (parent_package_id IS NULL OR parent_package_id <> id),
    CONSTRAINT ck_dwms_package_type CHECK (package_type IN ('CARTON','PALLET','TOTE','BAG','CRATE','DRUM','ENVELOPE','OTHER')),
    CONSTRAINT ck_dwms_package_weight CHECK (
        (gross_weight IS NULL OR gross_weight >= 0) AND (net_weight IS NULL OR net_weight >= 0) AND
        (gross_weight IS NULL OR net_weight IS NULL OR gross_weight >= net_weight)
    ),
    CONSTRAINT ck_dwms_package_dimensions CHECK (
        (length_value IS NULL OR length_value >= 0) AND (width_value IS NULL OR width_value >= 0) AND
        (height_value IS NULL OR height_value >= 0)
    ),
    CONSTRAINT ck_dwms_package_value CHECK (declared_value IS NULL OR declared_value >= 0),
    CONSTRAINT ck_dwms_package_seal CHECK (NOT sealed OR sealed_at IS NOT NULL),
    CONSTRAINT ck_dwms_package_status CHECK (status IN ('OPEN','PACKED','SEALED','STAGED','LOADED','SHIPPED','VOID'))
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_dwms_package_sscc
    ON dwms.packages (tenant_id, sscc) WHERE sscc IS NOT NULL;

CREATE TABLE IF NOT EXISTS dwms.package_items (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    package_id uuid NOT NULL REFERENCES dwms.packages(id) ON DELETE CASCADE,
    outbound_order_line_id uuid NOT NULL REFERENCES dwms.outbound_order_lines(id),
    pick_confirmation_id uuid REFERENCES dwms.pick_confirmations(id),
    stock_bucket_id uuid REFERENCES dwms.stock_buckets(id),
    item_id uuid NOT NULL REFERENCES dwms.items(id),
    packed_quantity numeric(24,8) NOT NULL,
    uom_code varchar(20) NOT NULL REFERENCES dwms.units_of_measure(uom_code),
    serial_number_id uuid REFERENCES dwms.serial_numbers(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_dwms_package_item_qty CHECK (packed_quantity > 0)
);

CREATE TABLE IF NOT EXISTS dwms.shipping_labels (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    package_id uuid NOT NULL REFERENCES dwms.packages(id) ON DELETE CASCADE,
    carrier_service_id uuid REFERENCES dwms.carrier_services(id),
    tracking_no varchar(200),
    label_type varchar(30) NOT NULL DEFAULT 'CARRIER',
    label_format varchar(30),
    label_file_id uuid REFERENCES dwms.files(id),
    label_payload_uri text,
    label_payload_sha256 char(64),
    generated_at timestamptz NOT NULL DEFAULT now(),
    voided_at timestamptz,
    void_reason text,
    UNIQUE (package_id, label_type, generated_at)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_dwms_shipping_tracking
    ON dwms.shipping_labels (tenant_id, carrier_service_id, tracking_no)
    WHERE tracking_no IS NOT NULL AND voided_at IS NULL;

CREATE TABLE IF NOT EXISTS dwms.shipments (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    warehouse_id uuid NOT NULL REFERENCES dwms.warehouses(id),
    owner_partner_id uuid NOT NULL REFERENCES dwms.business_partners(id),
    shipment_no varchar(120) NOT NULL,
    shipment_type varchar(30) NOT NULL DEFAULT 'OUTBOUND',
    carrier_partner_id uuid REFERENCES dwms.business_partners(id),
    carrier_service_id uuid REFERENCES dwms.carrier_services(id),
    transport_mode_code varchar(20) REFERENCES dwms.transport_modes(mode_code),
    master_tracking_no varchar(200),
    ship_to_partner_id uuid REFERENCES dwms.business_partners(id),
    ship_to_address_id uuid REFERENCES dwms.addresses(id),
    planned_ship_at timestamptz,
    actual_ship_at timestamptz,
    estimated_delivery_at timestamptz,
    actual_delivery_at timestamptz,
    status varchar(30) NOT NULL DEFAULT 'PLANNED',
    customs_release_required boolean NOT NULL DEFAULT false,
    customs_released_at timestamptz,
    total_packages integer NOT NULL DEFAULT 0,
    total_weight numeric(24,8),
    weight_uom_code varchar(20) REFERENCES dwms.units_of_measure(uom_code),
    total_volume numeric(24,9),
    volume_uom_code varchar(20) REFERENCES dwms.units_of_measure(uom_code),
    row_version bigint NOT NULL DEFAULT 1,
    created_by uuid REFERENCES dwms.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, shipment_no),
    CONSTRAINT ck_dwms_shipment_type CHECK (shipment_type IN ('OUTBOUND','TRANSFER','RETURN','EXPORT','PARCEL','LTL','FTL','OTHER')),
    CONSTRAINT ck_dwms_shipment_status CHECK (status IN (
        'PLANNED','PICKING','PACKED','STAGED','LOADING','LOADED','TENDERED','DISPATCHED','IN_TRANSIT',
        'DELIVERED','PARTIALLY_DELIVERED','EXCEPTION','CANCELLED','CLOSED'
    )),
    CONSTRAINT ck_dwms_shipment_totals CHECK (
        total_packages >= 0 AND (total_weight IS NULL OR total_weight >= 0) AND (total_volume IS NULL OR total_volume >= 0)
    ),
    CONSTRAINT ck_dwms_shipment_customs_release CHECK (customs_released_at IS NULL OR customs_release_required),
    CONSTRAINT ck_dwms_shipment_dates CHECK (
        (actual_ship_at IS NULL OR planned_ship_at IS NULL OR actual_ship_at >= planned_ship_at - interval '30 days') AND
        (actual_delivery_at IS NULL OR actual_ship_at IS NULL OR actual_delivery_at >= actual_ship_at)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_dwms_shipments_tenant_id
    ON dwms.shipments (tenant_id, id);

CREATE TABLE IF NOT EXISTS dwms.shipment_orders (
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    shipment_id uuid NOT NULL REFERENCES dwms.shipments(id) ON DELETE CASCADE,
    outbound_order_id uuid NOT NULL REFERENCES dwms.outbound_orders(id),
    sequence_no integer NOT NULL DEFAULT 1,
    PRIMARY KEY (shipment_id, outbound_order_id),
    CONSTRAINT ck_dwms_shipment_order_seq CHECK (sequence_no > 0)
);

CREATE TABLE IF NOT EXISTS dwms.shipment_lines (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    shipment_id uuid NOT NULL REFERENCES dwms.shipments(id) ON DELETE CASCADE,
    line_no integer NOT NULL,
    outbound_order_line_id uuid NOT NULL REFERENCES dwms.outbound_order_lines(id),
    item_id uuid NOT NULL REFERENCES dwms.items(id),
    shipped_quantity numeric(24,8) NOT NULL,
    uom_code varchar(20) NOT NULL REFERENCES dwms.units_of_measure(uom_code),
    base_quantity numeric(24,8) NOT NULL,
    base_uom_code varchar(20) NOT NULL REFERENCES dwms.units_of_measure(uom_code),
    country_of_origin char(2) REFERENCES dwms.countries(country_code),
    hs_country_code char(2),
    hs_nomenclature_version varchar(20),
    hs_code varchar(20),
    lot_no_snapshot varchar(150),
    serial_range_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
    declared_value numeric(24,4),
    currency_code char(3) REFERENCES dwms.currencies(currency_code),
    UNIQUE (shipment_id, line_no),
    FOREIGN KEY (hs_country_code, hs_nomenclature_version, hs_code)
        REFERENCES dwms.hs_codes(country_code, nomenclature_version, hs_code),
    CONSTRAINT ck_dwms_shipment_line_no CHECK (line_no > 0),
    CONSTRAINT ck_dwms_shipment_line_qty CHECK (shipped_quantity > 0 AND base_quantity > 0),
    CONSTRAINT ck_dwms_shipment_line_hs CHECK (
        num_nonnulls(hs_country_code, hs_nomenclature_version, hs_code) IN (0, 3)
    ),
    CONSTRAINT ck_dwms_shipment_line_value CHECK (declared_value IS NULL OR declared_value >= 0)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_dwms_shipment_lines_tenant_id
    ON dwms.shipment_lines (tenant_id, id);

CREATE TABLE IF NOT EXISTS dwms.shipment_packages (
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    shipment_id uuid NOT NULL REFERENCES dwms.shipments(id) ON DELETE CASCADE,
    package_id uuid NOT NULL REFERENCES dwms.packages(id),
    loaded_at timestamptz,
    unloaded_at timestamptz,
    PRIMARY KEY (shipment_id, package_id),
    CONSTRAINT ck_dwms_shipment_package_dates CHECK (unloaded_at IS NULL OR loaded_at IS NULL OR unloaded_at >= loaded_at)
);

CREATE TABLE IF NOT EXISTS dwms.shipment_stops (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    shipment_id uuid NOT NULL REFERENCES dwms.shipments(id) ON DELETE CASCADE,
    stop_sequence integer NOT NULL,
    stop_type varchar(20) NOT NULL,
    partner_id uuid REFERENCES dwms.business_partners(id),
    address_id uuid NOT NULL REFERENCES dwms.addresses(id),
    planned_arrival_at timestamptz,
    planned_departure_at timestamptz,
    actual_arrival_at timestamptz,
    actual_departure_at timestamptz,
    status varchar(20) NOT NULL DEFAULT 'PLANNED',
    instructions text,
    UNIQUE (shipment_id, stop_sequence),
    CONSTRAINT ck_dwms_shipment_stop_seq CHECK (stop_sequence > 0),
    CONSTRAINT ck_dwms_shipment_stop_type CHECK (stop_type IN ('PICKUP','DELIVERY','CROSS_DOCK','CUSTOMS','OTHER')),
    CONSTRAINT ck_dwms_shipment_stop_plan_dates CHECK (planned_departure_at IS NULL OR planned_arrival_at IS NULL OR planned_departure_at >= planned_arrival_at),
    CONSTRAINT ck_dwms_shipment_stop_actual_dates CHECK (actual_departure_at IS NULL OR actual_arrival_at IS NULL OR actual_departure_at >= actual_arrival_at)
);

CREATE TABLE IF NOT EXISTS dwms.shipment_status_history (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    shipment_id uuid NOT NULL REFERENCES dwms.shipments(id) ON DELETE CASCADE,
    sequence_no integer NOT NULL,
    from_status varchar(30),
    to_status varchar(30) NOT NULL,
    event_location text,
    reason_code_id uuid REFERENCES dwms.reason_codes(id),
    reason_text text,
    actor_user_id uuid REFERENCES dwms.users(id),
    source_system_id uuid REFERENCES dwms.external_systems(id),
    occurred_at timestamptz NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT now(),
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    UNIQUE (shipment_id, sequence_no),
    CONSTRAINT ck_dwms_shipment_status_seq CHECK (sequence_no > 0)
);

CREATE TABLE IF NOT EXISTS dwms.loads (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    warehouse_id uuid NOT NULL REFERENCES dwms.warehouses(id),
    load_no varchar(120) NOT NULL,
    carrier_partner_id uuid REFERENCES dwms.business_partners(id),
    trailer_no varchar(100),
    vehicle_no varchar(100),
    driver_name_masked varchar(150),
    driver_phone_encrypted text,
    dock_door_id uuid REFERENCES dwms.dock_doors(id),
    planned_departure_at timestamptz,
    actual_departure_at timestamptz,
    seal_no varchar(100),
    status varchar(20) NOT NULL DEFAULT 'PLANNED',
    total_weight numeric(24,8),
    weight_uom_code varchar(20) REFERENCES dwms.units_of_measure(uom_code),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, load_no),
    CONSTRAINT ck_dwms_load_status CHECK (status IN ('PLANNED','ASSIGNED','AT_DOCK','LOADING','LOADED','SEALED','DISPATCHED','CANCELLED','CLOSED')),
    CONSTRAINT ck_dwms_load_weight CHECK (total_weight IS NULL OR total_weight >= 0)
);

CREATE TABLE IF NOT EXISTS dwms.load_shipments (
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    load_id uuid NOT NULL REFERENCES dwms.loads(id) ON DELETE CASCADE,
    shipment_id uuid NOT NULL REFERENCES dwms.shipments(id),
    sequence_no integer NOT NULL DEFAULT 1,
    loaded_at timestamptz,
    PRIMARY KEY (load_id, shipment_id),
    UNIQUE (shipment_id),
    CONSTRAINT ck_dwms_load_shipment_seq CHECK (sequence_no > 0)
);

CREATE TABLE IF NOT EXISTS dwms.manifests (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    warehouse_id uuid NOT NULL REFERENCES dwms.warehouses(id),
    manifest_no varchar(120) NOT NULL,
    manifest_type varchar(30) NOT NULL,
    load_id uuid REFERENCES dwms.loads(id),
    carrier_partner_id uuid REFERENCES dwms.business_partners(id),
    document_file_id uuid REFERENCES dwms.files(id),
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    closed_at timestamptz,
    created_by uuid REFERENCES dwms.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, manifest_no),
    CONSTRAINT ck_dwms_manifest_type CHECK (manifest_type IN ('PARCEL','LTL','FTL','EXPORT','CUSTOMS','OTHER')),
    CONSTRAINT ck_dwms_manifest_status CHECK (status IN ('DRAFT','FINAL','TRANSMITTED','ACCEPTED','REJECTED','VOID'))
);

CREATE TABLE IF NOT EXISTS dwms.manifest_items (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    manifest_id uuid NOT NULL REFERENCES dwms.manifests(id) ON DELETE CASCADE,
    line_no integer NOT NULL,
    shipment_id uuid REFERENCES dwms.shipments(id),
    package_id uuid REFERENCES dwms.packages(id),
    tracking_no varchar(200),
    status varchar(20) NOT NULL DEFAULT 'INCLUDED',
    UNIQUE (manifest_id, line_no),
    CONSTRAINT ck_dwms_manifest_item_no CHECK (line_no > 0),
    CONSTRAINT ck_dwms_manifest_item_target CHECK (shipment_id IS NOT NULL OR package_id IS NOT NULL)
);

CREATE TABLE IF NOT EXISTS dwms.shipping_confirmations (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    shipment_id uuid NOT NULL REFERENCES dwms.shipments(id),
    confirmation_no integer NOT NULL,
    inventory_transaction_id uuid NOT NULL REFERENCES dwms.inventory_transaction_headers(id),
    confirmed_by uuid REFERENCES dwms.users(id),
    confirmed_at timestamptz NOT NULL DEFAULT now(),
    idempotency_key varchar(300) NOT NULL,
    reversal_confirmation_id uuid REFERENCES dwms.shipping_confirmations(id),
    note text,
    UNIQUE (shipment_id, confirmation_no),
    UNIQUE (tenant_id, idempotency_key),
    FOREIGN KEY (tenant_id, shipment_id)
        REFERENCES dwms.shipments(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, inventory_transaction_id)
        REFERENCES dwms.inventory_transaction_headers(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_dwms_shipping_confirmation_no CHECK (confirmation_no > 0),
    CONSTRAINT ck_dwms_shipping_confirmation_reversal CHECK (reversal_confirmation_id IS NULL OR reversal_confirmation_id <> id)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_dwms_shipping_confirmations_tenant_id
    ON dwms.shipping_confirmations (tenant_id, id);
CREATE UNIQUE INDEX IF NOT EXISTS ux_dwms_shipping_confirmation_transaction
    ON dwms.shipping_confirmations (inventory_transaction_id);

CREATE TABLE IF NOT EXISTS dwms.shipping_inventory_allocations (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    shipping_confirmation_id uuid NOT NULL,
    shipment_line_id uuid NOT NULL,
    inventory_transaction_entry_id uuid NOT NULL,
    source_stock_bucket_id uuid NOT NULL,
    allocated_quantity numeric(24,8) NOT NULL,
    base_uom_code varchar(20) NOT NULL REFERENCES dwms.units_of_measure(uom_code),
    created_by uuid REFERENCES dwms.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (tenant_id, shipping_confirmation_id)
        REFERENCES dwms.shipping_confirmations(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, shipment_line_id)
        REFERENCES dwms.shipment_lines(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, inventory_transaction_entry_id)
        REFERENCES dwms.inventory_transaction_entries(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, source_stock_bucket_id)
        REFERENCES dwms.stock_buckets(tenant_id, id) ON DELETE RESTRICT,
    UNIQUE (shipping_confirmation_id, shipment_line_id, inventory_transaction_entry_id),
    CONSTRAINT ck_dwms_shipping_inventory_alloc_qty CHECK (allocated_quantity > 0)
);

CREATE INDEX IF NOT EXISTS ix_dwms_shipping_inventory_alloc_entry
    ON dwms.shipping_inventory_allocations (
        inventory_transaction_entry_id, shipping_confirmation_id, shipment_line_id
    );
CREATE INDEX IF NOT EXISTS ix_dwms_shipping_inventory_alloc_line
    ON dwms.shipping_inventory_allocations (shipment_line_id, shipping_confirmation_id);

CREATE TABLE IF NOT EXISTS dwms.delivery_events (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    shipment_id uuid NOT NULL REFERENCES dwms.shipments(id),
    stop_id uuid REFERENCES dwms.shipment_stops(id),
    event_type varchar(40) NOT NULL,
    event_code varchar(80),
    latitude numeric(10,7),
    longitude numeric(10,7),
    occurred_at timestamptz NOT NULL,
    received_at timestamptz NOT NULL DEFAULT now(),
    source_system_id uuid REFERENCES dwms.external_systems(id),
    external_event_id varchar(300),
    payload_uri text,
    payload_sha256 char(64),
    UNIQUE (source_system_id, external_event_id),
    CONSTRAINT ck_dwms_delivery_lat CHECK (latitude IS NULL OR latitude BETWEEN -90 AND 90),
    CONSTRAINT ck_dwms_delivery_lon CHECK (longitude IS NULL OR longitude BETWEEN -180 AND 180)
);

CREATE TABLE IF NOT EXISTS dwms.proof_of_deliveries (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    shipment_id uuid NOT NULL REFERENCES dwms.shipments(id),
    delivery_stop_id uuid REFERENCES dwms.shipment_stops(id),
    delivered_at timestamptz NOT NULL,
    receiver_name_encrypted text,
    receiver_name_masked varchar(150),
    receiver_relationship varchar(80),
    signature_file_id uuid REFERENCES dwms.files(id),
    photo_file_id uuid REFERENCES dwms.files(id),
    geolocation jsonb NOT NULL DEFAULT '{}'::jsonb,
    condition_code varchar(50),
    note text,
    recorded_by uuid REFERENCES dwms.users(id),
    recorded_at timestamptz NOT NULL DEFAULT now(),
    status varchar(20) NOT NULL DEFAULT 'CAPTURED',
    CONSTRAINT ck_dwms_pod_evidence CHECK (
        signature_file_id IS NOT NULL OR photo_file_id IS NOT NULL OR receiver_name_encrypted IS NOT NULL
    ),
    CONSTRAINT ck_dwms_pod_status CHECK (status IN ('CAPTURED','VERIFIED','DISPUTED','VOID'))
);

CREATE TABLE IF NOT EXISTS dwms.delivery_discrepancies (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    shipment_id uuid NOT NULL REFERENCES dwms.shipments(id),
    shipment_line_id uuid REFERENCES dwms.shipment_lines(id),
    package_id uuid REFERENCES dwms.packages(id),
    discrepancy_type varchar(40) NOT NULL,
    expected_quantity numeric(24,8),
    actual_quantity numeric(24,8),
    uom_code varchar(20) REFERENCES dwms.units_of_measure(uom_code),
    reason_code_id uuid REFERENCES dwms.reason_codes(id),
    description text,
    evidence_file_id uuid REFERENCES dwms.files(id),
    status varchar(20) NOT NULL DEFAULT 'OPEN',
    reported_at timestamptz NOT NULL DEFAULT now(),
    resolved_at timestamptz,
    CONSTRAINT ck_dwms_delivery_discrepancy_qty CHECK (
        (expected_quantity IS NULL OR expected_quantity >= 0) AND (actual_quantity IS NULL OR actual_quantity >= 0)
    )
);

CREATE TABLE IF NOT EXISTS dwms.customer_return_orders (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    warehouse_id uuid NOT NULL REFERENCES dwms.warehouses(id),
    owner_partner_id uuid NOT NULL REFERENCES dwms.business_partners(id),
    return_order_no varchar(120) NOT NULL,
    customer_partner_id uuid REFERENCES dwms.business_partners(id),
    original_outbound_order_id uuid REFERENCES dwms.outbound_orders(id),
    original_shipment_id uuid REFERENCES dwms.shipments(id),
    return_type varchar(30) NOT NULL DEFAULT 'CUSTOMER_RETURN',
    authorization_no varchar(150),
    expected_return_at timestamptz,
    disposition_policy varchar(30),
    status varchar(30) NOT NULL DEFAULT 'REQUESTED',
    reason_code_id uuid REFERENCES dwms.reason_codes(id),
    notes text,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, return_order_no),
    CONSTRAINT ck_dwms_customer_return_type CHECK (return_type IN ('CUSTOMER_RETURN','RECALL','REFUSED_DELIVERY','WARRANTY','EXCHANGE')),
    CONSTRAINT ck_dwms_customer_return_status CHECK (status IN (
        'REQUESTED','AUTHORIZED','IN_TRANSIT','RECEIVING','RECEIVED','INSPECTING','DISPOSITIONED','CLOSED','REJECTED','CANCELLED'
    ))
);

CREATE TABLE IF NOT EXISTS dwms.customer_return_lines (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    customer_return_order_id uuid NOT NULL REFERENCES dwms.customer_return_orders(id) ON DELETE CASCADE,
    line_no integer NOT NULL,
    original_outbound_line_id uuid REFERENCES dwms.outbound_order_lines(id),
    item_id uuid NOT NULL REFERENCES dwms.items(id),
    authorized_quantity numeric(24,8) NOT NULL,
    received_quantity numeric(24,8) NOT NULL DEFAULT 0,
    accepted_quantity numeric(24,8) NOT NULL DEFAULT 0,
    rejected_quantity numeric(24,8) NOT NULL DEFAULT 0,
    uom_code varchar(20) NOT NULL REFERENCES dwms.units_of_measure(uom_code),
    reason_code_id uuid REFERENCES dwms.reason_codes(id),
    requested_disposition varchar(30),
    final_disposition varchar(30),
    status varchar(20) NOT NULL DEFAULT 'AUTHORIZED',
    UNIQUE (customer_return_order_id, line_no),
    CONSTRAINT ck_dwms_customer_return_line_no CHECK (line_no > 0),
    CONSTRAINT ck_dwms_customer_return_line_qty CHECK (
        authorized_quantity > 0 AND received_quantity >= 0 AND accepted_quantity >= 0 AND rejected_quantity >= 0 AND
        accepted_quantity + rejected_quantity <= received_quantity
    )
);

COMMENT ON TABLE dwms.inventory_allocations IS
    'Immutable allocation intent from an outbound line to a concrete stock bucket; release creates state history rather than deleting the row.';
COMMENT ON TABLE dwms.shipping_confirmations IS
    'Idempotent inventory-posting link for physical shipment. Customs-required shipments must be released before confirmation.';
COMMENT ON TABLE dwms.outbound_order_parties IS
    'Order-time party snapshots preserve names, identifiers and addresses even when the partner master later changes.';

CREATE OR REPLACE FUNCTION dwms.validate_shipment_line_dimensions()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    item_tenant_id uuid;
    item_base_uom_code varchar(20);
BEGIN
    SELECT tenant_id, base_uom_code
      INTO item_tenant_id, item_base_uom_code
      FROM dwms.items
     WHERE id = NEW.item_id;
    IF NOT FOUND OR item_tenant_id <> NEW.tenant_id THEN
        RAISE EXCEPTION 'Shipment line item % is unavailable in tenant %', NEW.item_id, NEW.tenant_id
            USING ERRCODE = '23514';
    END IF;
    IF NEW.base_uom_code <> item_base_uom_code THEN
        RAISE EXCEPTION 'Shipment line base unit % differs from item base unit %',
            NEW.base_uom_code, item_base_uom_code USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION dwms.assert_shipping_inventory_transaction(
    p_inventory_transaction_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, dwms
AS $function$
DECLARE
    transaction_row dwms.inventory_transaction_headers%ROWTYPE;
    original_type varchar(40);
    confirmation_id uuid;
    confirmation_count bigint;
BEGIN
    IF p_inventory_transaction_id IS NULL THEN RETURN; END IF;
    SELECT * INTO transaction_row
      FROM dwms.inventory_transaction_headers
     WHERE id = p_inventory_transaction_id
     FOR SHARE;
    IF NOT FOUND OR transaction_row.posting_status <> 'POSTED' THEN RETURN; END IF;
    IF transaction_row.transaction_type = 'SHIPMENT' THEN
        SELECT count(*), min(confirmation.id::text)::uuid
          INTO confirmation_count, confirmation_id
          FROM dwms.shipping_confirmations confirmation
         WHERE confirmation.inventory_transaction_id = transaction_row.id
           AND confirmation.tenant_id = transaction_row.tenant_id;
        IF confirmation_count <> 1 THEN
            RAISE EXCEPTION 'POSTED SHIPMENT transaction % requires exactly one shipping confirmation',
                transaction_row.id USING ERRCODE = '23514';
        END IF;
        PERFORM dwms.assert_shipping_confirmation_inventory(confirmation_id);
    ELSIF transaction_row.transaction_type = 'REVERSAL' THEN
        SELECT transaction_type INTO original_type
          FROM dwms.inventory_transaction_headers
         WHERE id = transaction_row.reversal_of_transaction_id
         FOR SHARE;
        IF original_type = 'SHIPMENT' THEN
            SELECT count(*), min(confirmation.id::text)::uuid
              INTO confirmation_count, confirmation_id
              FROM dwms.shipping_confirmations confirmation
             WHERE confirmation.inventory_transaction_id = transaction_row.id
               AND confirmation.tenant_id = transaction_row.tenant_id;
            IF confirmation_count <> 1 THEN
                RAISE EXCEPTION 'POSTED reversal of SHIPMENT transaction % requires one reversal confirmation',
                    transaction_row.id USING ERRCODE = '23514';
            END IF;
            PERFORM dwms.assert_shipping_confirmation_inventory(confirmation_id);
        END IF;
    END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION dwms.assert_shipment_inventory_coverage(
    p_shipment_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, dwms
AS $function$
DECLARE
    shipment_row dwms.shipments%ROWTYPE;
    confirmation_row record;
    line_row record;
    covered_quantity numeric(24,8);
    line_count bigint := 0;
    physical_status boolean;
BEGIN
    IF p_shipment_id IS NULL THEN RETURN; END IF;
    SELECT * INTO shipment_row
      FROM dwms.shipments
     WHERE id = p_shipment_id
     FOR SHARE;
    IF NOT FOUND THEN RETURN; END IF;
    FOR confirmation_row IN
        SELECT id FROM dwms.shipping_confirmations
         WHERE shipment_id = shipment_row.id
         ORDER BY id
    LOOP
        PERFORM dwms.assert_shipping_confirmation_inventory(confirmation_row.id);
    END LOOP;
    physical_status := shipment_row.status IN (
        'DISPATCHED','IN_TRANSIT','DELIVERED','PARTIALLY_DELIVERED','CLOSED'
    ) OR (shipment_row.status = 'EXCEPTION' AND shipment_row.actual_ship_at IS NOT NULL);
    FOR line_row IN
        SELECT id, base_quantity
          FROM dwms.shipment_lines
         WHERE shipment_id = shipment_row.id
         ORDER BY id
         FOR SHARE
    LOOP
        line_count := line_count + 1;
        SELECT COALESCE(sum(allocation.allocated_quantity), 0)
          INTO covered_quantity
          FROM dwms.shipping_inventory_allocations allocation
          JOIN dwms.shipping_confirmations confirmation
            ON confirmation.id = allocation.shipping_confirmation_id
          JOIN dwms.inventory_transaction_headers transaction
            ON transaction.id = confirmation.inventory_transaction_id
         WHERE allocation.shipment_line_id = line_row.id
           AND confirmation.shipment_id = shipment_row.id
           AND confirmation.reversal_confirmation_id IS NULL
           AND transaction.transaction_type = 'SHIPMENT'
           AND transaction.posting_status = 'POSTED';
        IF covered_quantity > line_row.base_quantity THEN
            RAISE EXCEPTION 'Shipment line % inventory coverage exceeds base quantity', line_row.id
                USING ERRCODE = '23514';
        END IF;
        IF physical_status AND covered_quantity IS DISTINCT FROM line_row.base_quantity THEN
            RAISE EXCEPTION 'Physically dispatched shipment line % coverage % must equal base quantity %',
                line_row.id, covered_quantity, line_row.base_quantity USING ERRCODE = '23514';
        END IF;
    END LOOP;
    IF physical_status AND line_count = 0 THEN
        RAISE EXCEPTION 'Physically dispatched shipment % has no shipment lines', shipment_row.id
            USING ERRCODE = '23514';
    END IF;
    IF EXISTS (
        SELECT 1
          FROM dwms.outbound_order_lines outbound_line
         WHERE EXISTS (
             SELECT 1 FROM dwms.shipment_lines shipment_line
              WHERE shipment_line.shipment_id = shipment_row.id
                AND shipment_line.outbound_order_line_id = outbound_line.id
         )
           AND (SELECT COALESCE(sum(allocation.allocated_quantity), 0)
                  FROM dwms.shipping_inventory_allocations allocation
                  JOIN dwms.shipping_confirmations confirmation
                    ON confirmation.id = allocation.shipping_confirmation_id
                  JOIN dwms.shipment_lines allocated_shipment_line
                    ON allocated_shipment_line.id = allocation.shipment_line_id
                  JOIN dwms.inventory_transaction_headers transaction
                    ON transaction.id = confirmation.inventory_transaction_id
                 WHERE allocated_shipment_line.outbound_order_line_id = outbound_line.id
                   AND confirmation.reversal_confirmation_id IS NULL
                   AND transaction.transaction_type = 'SHIPMENT'
                   AND transaction.posting_status = 'POSTED')
               > outbound_line.base_quantity
    ) THEN
        RAISE EXCEPTION 'Shipment % causes cumulative shipping allocations to exceed an outbound order line',
            shipment_row.id USING ERRCODE = '23514';
    END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION dwms.guard_shipping_confirmation_mutation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, dwms
AS $function$
DECLARE
    transaction_status varchar(20);
    old_core jsonb;
    new_core jsonb;
BEGIN
    SELECT posting_status INTO transaction_status
      FROM dwms.inventory_transaction_headers
     WHERE id = OLD.inventory_transaction_id
     FOR SHARE;
    IF TG_OP = 'DELETE' THEN
        IF transaction_status = 'POSTED' THEN
            RAISE EXCEPTION 'Posted shipping confirmation % cannot be deleted; create an exact reversal confirmation',
                OLD.id USING ERRCODE = '55000';
        END IF;
        RETURN OLD;
    END IF;
    IF transaction_status = 'POSTED' THEN
        old_core := to_jsonb(OLD) - 'reversal_confirmation_id';
        new_core := to_jsonb(NEW) - 'reversal_confirmation_id';
        IF old_core IS DISTINCT FROM new_core THEN
            RAISE EXCEPTION 'Posted shipping confirmation % core fields are immutable', OLD.id
                USING ERRCODE = '55000';
        END IF;
        IF OLD.reversal_confirmation_id IS NOT NULL
           AND NEW.reversal_confirmation_id IS DISTINCT FROM OLD.reversal_confirmation_id THEN
            RAISE EXCEPTION 'Shipping confirmation % reversal link is immutable once recorded', OLD.id
                USING ERRCODE = '55000';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION dwms.guard_shipping_inventory_allocation_mutation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, dwms
AS $function$
DECLARE
    target_confirmation_id uuid;
    transaction_status varchar(20);
BEGIN
    FOR target_confirmation_id IN
        SELECT DISTINCT confirmation_id
          FROM (VALUES
              (CASE WHEN TG_OP <> 'INSERT' THEN OLD.shipping_confirmation_id END),
              (CASE WHEN TG_OP <> 'DELETE' THEN NEW.shipping_confirmation_id END)
          ) AS candidate(confirmation_id)
         WHERE confirmation_id IS NOT NULL
         ORDER BY confirmation_id
    LOOP
        SELECT transaction.posting_status INTO transaction_status
          FROM dwms.shipping_confirmations confirmation
          JOIN dwms.inventory_transaction_headers transaction
            ON transaction.id = confirmation.inventory_transaction_id
         WHERE confirmation.id = target_confirmation_id
         FOR SHARE OF confirmation, transaction;
        IF transaction_status = 'POSTED' THEN
            RAISE EXCEPTION 'Shipping inventory allocations are append-only after confirmation % posts',
                target_confirmation_id USING ERRCODE = '55000';
        END IF;
    END LOOP;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION dwms.deferred_check_shipping_inventory_integrity()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, dwms
AS $function$
DECLARE
    old_data jsonb := '{}'::jsonb;
    new_data jsonb := '{}'::jsonb;
    old_confirmation_id uuid;
    new_confirmation_id uuid;
    old_transaction_id uuid;
    new_transaction_id uuid;
    old_shipment_id uuid;
    new_shipment_id uuid;
    old_shipment_line_id uuid;
    new_shipment_line_id uuid;
    old_outbound_line_id uuid;
    new_outbound_line_id uuid;
    old_outbound_order_id uuid;
    new_outbound_order_id uuid;
    target_shipment_id uuid;
BEGIN
    IF TG_OP <> 'INSERT' THEN old_data := to_jsonb(OLD); END IF;
    IF TG_OP <> 'DELETE' THEN new_data := to_jsonb(NEW); END IF;
    IF TG_TABLE_NAME = 'shipping_confirmations' THEN
        old_confirmation_id := NULLIF(old_data ->> 'id', '')::uuid;
        new_confirmation_id := NULLIF(new_data ->> 'id', '')::uuid;
        old_transaction_id := NULLIF(old_data ->> 'inventory_transaction_id', '')::uuid;
        new_transaction_id := NULLIF(new_data ->> 'inventory_transaction_id', '')::uuid;
        old_shipment_id := NULLIF(old_data ->> 'shipment_id', '')::uuid;
        new_shipment_id := NULLIF(new_data ->> 'shipment_id', '')::uuid;
    ELSIF TG_TABLE_NAME = 'shipping_inventory_allocations' THEN
        old_confirmation_id := NULLIF(old_data ->> 'shipping_confirmation_id', '')::uuid;
        new_confirmation_id := NULLIF(new_data ->> 'shipping_confirmation_id', '')::uuid;
    ELSIF TG_TABLE_NAME = 'inventory_transaction_headers' THEN
        old_transaction_id := NULLIF(old_data ->> 'id', '')::uuid;
        new_transaction_id := NULLIF(new_data ->> 'id', '')::uuid;
    ELSIF TG_TABLE_NAME = 'inventory_transaction_entries' THEN
        old_transaction_id := NULLIF(old_data ->> 'inventory_transaction_id', '')::uuid;
        new_transaction_id := NULLIF(new_data ->> 'inventory_transaction_id', '')::uuid;
    ELSIF TG_TABLE_NAME = 'shipments' THEN
        old_shipment_id := NULLIF(old_data ->> 'id', '')::uuid;
        new_shipment_id := NULLIF(new_data ->> 'id', '')::uuid;
    ELSIF TG_TABLE_NAME = 'shipment_lines' THEN
        old_shipment_line_id := NULLIF(old_data ->> 'id', '')::uuid;
        new_shipment_line_id := NULLIF(new_data ->> 'id', '')::uuid;
        old_shipment_id := NULLIF(old_data ->> 'shipment_id', '')::uuid;
        new_shipment_id := NULLIF(new_data ->> 'shipment_id', '')::uuid;
    ELSIF TG_TABLE_NAME = 'shipment_orders' THEN
        old_shipment_id := NULLIF(old_data ->> 'shipment_id', '')::uuid;
        new_shipment_id := NULLIF(new_data ->> 'shipment_id', '')::uuid;
        old_outbound_order_id := NULLIF(old_data ->> 'outbound_order_id', '')::uuid;
        new_outbound_order_id := NULLIF(new_data ->> 'outbound_order_id', '')::uuid;
    ELSIF TG_TABLE_NAME = 'outbound_order_lines' THEN
        old_outbound_line_id := NULLIF(old_data ->> 'id', '')::uuid;
        new_outbound_line_id := NULLIF(new_data ->> 'id', '')::uuid;
        old_outbound_order_id := NULLIF(old_data ->> 'outbound_order_id', '')::uuid;
        new_outbound_order_id := NULLIF(new_data ->> 'outbound_order_id', '')::uuid;
    ELSIF TG_TABLE_NAME = 'outbound_orders' THEN
        old_outbound_order_id := NULLIF(old_data ->> 'id', '')::uuid;
        new_outbound_order_id := NULLIF(new_data ->> 'id', '')::uuid;
    END IF;

    PERFORM dwms.assert_shipping_confirmation_inventory(old_confirmation_id);
    IF new_confirmation_id IS DISTINCT FROM old_confirmation_id THEN
        PERFORM dwms.assert_shipping_confirmation_inventory(new_confirmation_id);
    END IF;
    PERFORM dwms.assert_shipping_inventory_transaction(old_transaction_id);
    IF new_transaction_id IS DISTINCT FROM old_transaction_id THEN
        PERFORM dwms.assert_shipping_inventory_transaction(new_transaction_id);
    END IF;

    FOR target_shipment_id IN
        SELECT DISTINCT candidate.shipment_id
          FROM (
              SELECT old_shipment_id AS shipment_id
              UNION SELECT new_shipment_id
              UNION
              SELECT confirmation.shipment_id
                FROM dwms.shipping_confirmations confirmation
               WHERE confirmation.id = old_confirmation_id OR confirmation.id = new_confirmation_id
              UNION
              SELECT confirmation.shipment_id
                FROM dwms.shipping_confirmations confirmation
               WHERE confirmation.inventory_transaction_id = old_transaction_id
                  OR confirmation.inventory_transaction_id = new_transaction_id
              UNION
              SELECT shipment_line.shipment_id
                FROM dwms.shipment_lines shipment_line
               WHERE shipment_line.id = old_shipment_line_id OR shipment_line.id = new_shipment_line_id
              UNION
              SELECT shipment_line.shipment_id
                FROM dwms.shipment_lines shipment_line
               WHERE shipment_line.outbound_order_line_id = old_outbound_line_id
                  OR shipment_line.outbound_order_line_id = new_outbound_line_id
              UNION
              SELECT shipment_order.shipment_id
                FROM dwms.shipment_orders shipment_order
               WHERE shipment_order.outbound_order_id = old_outbound_order_id
                  OR shipment_order.outbound_order_id = new_outbound_order_id
          ) candidate
         WHERE candidate.shipment_id IS NOT NULL
         ORDER BY candidate.shipment_id
    LOOP
        PERFORM dwms.assert_shipment_inventory_coverage(target_shipment_id);
    END LOOP;
    RETURN NULL;
END;
$function$;

DROP TRIGGER IF EXISTS trg_validate_shipment_line_dimensions ON dwms.shipment_lines;
CREATE TRIGGER trg_validate_shipment_line_dimensions
    BEFORE INSERT OR UPDATE OF tenant_id, item_id, base_uom_code
    ON dwms.shipment_lines
    FOR EACH ROW EXECUTE PROCEDURE dwms.validate_shipment_line_dimensions();

CREATE OR REPLACE FUNCTION dwms.protect_outbound_document_header()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    old_core jsonb;
    new_core jsonb;
    transition_is_valid boolean;
BEGIN
    IF TG_TABLE_NAME = 'outbound_orders' THEN
        IF OLD.status IN ('CLOSED','CANCELLED') THEN
            RAISE EXCEPTION 'Finalized outbound order % is immutable', OLD.id
                USING ERRCODE = '55000';
        END IF;
        IF OLD.status = 'SHIPPED' THEN
            IF TG_OP = 'DELETE' OR NEW.status NOT IN ('SHIPPED','CLOSED') THEN
                RAISE EXCEPTION 'Shipped outbound order % may only progress to CLOSED', OLD.id
                    USING ERRCODE = '55000';
            END IF;
            old_core := to_jsonb(OLD) - ARRAY[
                'status','shipping_status','closed_at','row_version','updated_at'
            ]::text[];
            new_core := to_jsonb(NEW) - ARRAY[
                'status','shipping_status','closed_at','row_version','updated_at'
            ]::text[];
            IF old_core IS DISTINCT FROM new_core THEN
                RAISE EXCEPTION 'Shipped outbound order % core fields are immutable', OLD.id
                    USING ERRCODE = '55000';
            END IF;
        END IF;
    ELSE
        IF OLD.status = 'CANCELLED' OR OLD.status = 'CLOSED' THEN
            RAISE EXCEPTION 'Finalized shipment % is immutable', OLD.id
                USING ERRCODE = '55000';
        END IF;
        IF OLD.status IN ('DISPATCHED','IN_TRANSIT','DELIVERED','PARTIALLY_DELIVERED')
           OR (OLD.status = 'EXCEPTION' AND OLD.actual_ship_at IS NOT NULL) THEN
            IF TG_OP = 'DELETE' THEN
                RAISE EXCEPTION 'Dispatched shipment % cannot be deleted', OLD.id
                    USING ERRCODE = '55000';
            END IF;
            transition_is_valid :=
                (OLD.status = NEW.status) OR
                (OLD.status = 'DISPATCHED' AND NEW.status IN (
                    'IN_TRANSIT','PARTIALLY_DELIVERED','DELIVERED','EXCEPTION','CLOSED'
                )) OR
                (OLD.status = 'IN_TRANSIT' AND NEW.status IN (
                    'PARTIALLY_DELIVERED','DELIVERED','EXCEPTION','CLOSED'
                )) OR
                (OLD.status = 'PARTIALLY_DELIVERED' AND NEW.status IN (
                    'DELIVERED','EXCEPTION','CLOSED'
                )) OR
                (OLD.status = 'DELIVERED' AND NEW.status IN ('EXCEPTION','CLOSED')) OR
                (OLD.status = 'EXCEPTION' AND NEW.status IN (
                    'IN_TRANSIT','PARTIALLY_DELIVERED','DELIVERED','CLOSED'
                ));
            IF NOT transition_is_valid THEN
                RAISE EXCEPTION 'Invalid physical shipment transition % -> % for shipment %',
                    OLD.status, NEW.status, OLD.id USING ERRCODE = '23514';
            END IF;
            IF OLD.actual_delivery_at IS NOT NULL
               AND OLD.actual_delivery_at IS DISTINCT FROM NEW.actual_delivery_at THEN
                RAISE EXCEPTION 'Shipment actual_delivery_at is immutable once recorded for %', OLD.id
                    USING ERRCODE = '55000';
            END IF;
            old_core := to_jsonb(OLD) - ARRAY[
                'status','actual_delivery_at','row_version','updated_at'
            ]::text[];
            new_core := to_jsonb(NEW) - ARRAY[
                'status','actual_delivery_at','row_version','updated_at'
            ]::text[];
            IF old_core IS DISTINCT FROM new_core THEN
                RAISE EXCEPTION 'Dispatched shipment % core fields are immutable', OLD.id
                    USING ERRCODE = '55000';
            END IF;
        END IF;
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_protect_outbound_order_header ON dwms.outbound_orders;
CREATE TRIGGER trg_protect_outbound_order_header
    BEFORE UPDATE OR DELETE ON dwms.outbound_orders
    FOR EACH ROW EXECUTE PROCEDURE dwms.protect_outbound_document_header();

DROP TRIGGER IF EXISTS trg_protect_shipment_header ON dwms.shipments;
CREATE TRIGGER trg_protect_shipment_header
    BEFORE UPDATE OR DELETE ON dwms.shipments
    FOR EACH ROW EXECUTE PROCEDURE dwms.protect_outbound_document_header();

DO $block$
DECLARE
    target record;
    trigger_suffix text;
BEGIN
    FOR target IN
        SELECT * FROM (VALUES
            ('outbound_order_lines','outbound_order_id','outbound_orders','SHIPPED,CLOSED,CANCELLED'),
            ('outbound_order_parties','outbound_order_id','outbound_orders','SHIPPED,CLOSED,CANCELLED'),
            ('outbound_order_references','outbound_order_id','outbound_orders','SHIPPED,CLOSED,CANCELLED'),
            ('outbound_order_holds','outbound_order_id','outbound_orders','SHIPPED,CLOSED,CANCELLED'),
            ('allocation_run_orders','outbound_order_id','outbound_orders','SHIPPED,CLOSED,CANCELLED'),
            ('inventory_allocations','outbound_order_id','outbound_orders','SHIPPED,CLOSED,CANCELLED'),
            ('wave_orders','outbound_order_id','outbound_orders','SHIPPED,CLOSED,CANCELLED'),
            ('pick_tasks','outbound_order_id','outbound_orders','SHIPPED,CLOSED,CANCELLED'),
            ('packing_sessions','outbound_order_id','outbound_orders','SHIPPED,CLOSED,CANCELLED'),
            ('packages','outbound_order_id','outbound_orders','SHIPPED,CLOSED,CANCELLED'),
            ('shipment_orders','outbound_order_id','outbound_orders','SHIPPED,CLOSED,CANCELLED'),
            ('shipment_orders','shipment_id','shipments','DISPATCHED,IN_TRANSIT,DELIVERED,PARTIALLY_DELIVERED,EXCEPTION,CLOSED,CANCELLED'),
            ('shipment_lines','shipment_id','shipments','DISPATCHED,IN_TRANSIT,DELIVERED,PARTIALLY_DELIVERED,EXCEPTION,CLOSED,CANCELLED')
        ) AS configured(table_name, parent_column, parent_table, frozen_statuses)
    LOOP
        trigger_suffix := substr(md5(target.parent_table || ':' || target.parent_column), 1, 10);
        EXECUTE format('DROP TRIGGER IF EXISTS %I ON dwms.%I',
                       'trg_guard_finalized_' || trigger_suffix, target.table_name);
        EXECUTE format(
            'CREATE TRIGGER %I BEFORE INSERT OR UPDATE OR DELETE ON dwms.%I '
            'FOR EACH ROW EXECUTE PROCEDURE dwms.guard_finalized_document_child(%L,%L,%L,%L)',
            'trg_guard_finalized_' || trigger_suffix, target.table_name,
            target.parent_table, target.parent_column, 'status', target.frozen_statuses
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

CREATE OR REPLACE FUNCTION dwms.validate_shipping_inventory_allocation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, dwms
AS $function$
DECLARE
    confirmation_row dwms.shipping_confirmations%ROWTYPE;
    transaction_row dwms.inventory_transaction_headers%ROWTYPE;
    shipment_row dwms.shipments%ROWTYPE;
    shipment_line_row dwms.shipment_lines%ROWTYPE;
    outbound_line_row dwms.outbound_order_lines%ROWTYPE;
    outbound_order_row dwms.outbound_orders%ROWTYPE;
    entry_row dwms.inventory_transaction_entries%ROWTYPE;
    bucket_row dwms.stock_buckets%ROWTYPE;
    item_base_uom varchar(20);
    existing_line_quantity numeric(24,8);
    existing_order_line_quantity numeric(24,8);
    existing_entry_quantity numeric(24,8);
    excluded_id uuid;
BEGIN
    excluded_id := CASE WHEN TG_OP = 'UPDATE' THEN OLD.id ELSE NULL END;
    SELECT * INTO confirmation_row
      FROM dwms.shipping_confirmations
     WHERE tenant_id = NEW.tenant_id AND id = NEW.shipping_confirmation_id
     FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Shipping inventory allocation references an invalid tenant-scoped confirmation'
            USING ERRCODE = '23503';
    END IF;
    SELECT * INTO transaction_row
      FROM dwms.inventory_transaction_headers
     WHERE tenant_id = NEW.tenant_id AND id = confirmation_row.inventory_transaction_id
     FOR UPDATE;
    SELECT * INTO shipment_row
      FROM dwms.shipments
     WHERE tenant_id = NEW.tenant_id AND id = confirmation_row.shipment_id
     FOR SHARE;
    SELECT * INTO shipment_line_row
      FROM dwms.shipment_lines
     WHERE tenant_id = NEW.tenant_id AND id = NEW.shipment_line_id
     FOR UPDATE;
    SELECT * INTO outbound_line_row
      FROM dwms.outbound_order_lines
     WHERE id = shipment_line_row.outbound_order_line_id
     FOR UPDATE;
    SELECT * INTO outbound_order_row
      FROM dwms.outbound_orders
     WHERE id = outbound_line_row.outbound_order_id
     FOR SHARE;
    SELECT * INTO entry_row
      FROM dwms.inventory_transaction_entries
     WHERE tenant_id = NEW.tenant_id AND id = NEW.inventory_transaction_entry_id
     FOR UPDATE;
    SELECT * INTO bucket_row
      FROM dwms.stock_buckets
     WHERE tenant_id = NEW.tenant_id AND id = NEW.source_stock_bucket_id
     FOR SHARE;
    SELECT base_uom_code INTO item_base_uom
      FROM dwms.items
     WHERE tenant_id = NEW.tenant_id AND id = shipment_line_row.item_id
     FOR SHARE;
    IF transaction_row.id IS NULL OR shipment_row.id IS NULL OR shipment_line_row.id IS NULL
       OR outbound_line_row.id IS NULL OR outbound_order_row.id IS NULL
       OR entry_row.id IS NULL OR bucket_row.id IS NULL OR item_base_uom IS NULL THEN
        RAISE EXCEPTION 'Shipping inventory allocation references an invalid tenant-scoped document or inventory object'
            USING ERRCODE = '23503';
    END IF;
    IF confirmation_row.reversal_confirmation_id IS NOT NULL THEN
        RAISE EXCEPTION 'A reversed shipping confirmation cannot receive inventory allocations'
            USING ERRCODE = '23514';
    END IF;
    IF transaction_row.transaction_type <> 'SHIPMENT'
       OR transaction_row.posting_status NOT IN ('DRAFT','VALIDATED') THEN
        RAISE EXCEPTION 'Shipping allocations require a DRAFT or VALIDATED SHIPMENT transaction'
            USING ERRCODE = '23514';
    END IF;
    IF shipment_line_row.shipment_id <> shipment_row.id
       OR outbound_line_row.item_id <> shipment_line_row.item_id
       OR outbound_line_row.uom_code <> shipment_line_row.uom_code
       OR shipment_line_row.base_quantity > outbound_line_row.base_quantity
       OR outbound_order_row.tenant_id <> NEW.tenant_id
       OR outbound_order_row.warehouse_id <> shipment_row.warehouse_id
       OR outbound_order_row.owner_partner_id <> shipment_row.owner_partner_id
       OR NOT EXISTS (
           SELECT 1 FROM dwms.shipment_orders shipment_order
            WHERE shipment_order.tenant_id = NEW.tenant_id
              AND shipment_order.shipment_id = shipment_row.id
              AND shipment_order.outbound_order_id = outbound_order_row.id
       ) THEN
        RAISE EXCEPTION 'Shipment line does not match its linked outbound order line/header'
            USING ERRCODE = '23514';
    END IF;
    IF transaction_row.warehouse_id <> shipment_row.warehouse_id
       OR transaction_row.owner_partner_id <> shipment_row.owner_partner_id
       OR transaction_row.tenant_id <> shipment_row.tenant_id THEN
        RAISE EXCEPTION 'SHIPMENT transaction tenant, warehouse, or owner differs from shipment'
            USING ERRCODE = '23514';
    END IF;
    IF entry_row.inventory_transaction_id <> transaction_row.id
       OR entry_row.stock_bucket_id <> NEW.source_stock_bucket_id
       OR entry_row.signed_quantity >= 0
       OR entry_row.entry_role <> 'SOURCE'
       OR bucket_row.account_type <> 'PHYSICAL'
       OR bucket_row.warehouse_id <> shipment_row.warehouse_id
       OR bucket_row.owner_partner_id <> shipment_row.owner_partner_id
       OR bucket_row.item_id <> shipment_line_row.item_id
       OR entry_row.item_id <> shipment_line_row.item_id
       OR entry_row.base_uom_code <> shipment_line_row.base_uom_code
       OR NEW.base_uom_code <> shipment_line_row.base_uom_code
       OR item_base_uom <> shipment_line_row.base_uom_code THEN
        RAISE EXCEPTION 'Shipping allocation source entry/bucket item, owner, warehouse, or base UOM mismatch'
            USING ERRCODE = '23514';
    END IF;
    IF shipment_line_row.lot_no_snapshot IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM dwms.inventory_lots inventory_lot
         WHERE inventory_lot.id = bucket_row.inventory_lot_id
           AND inventory_lot.tenant_id = NEW.tenant_id
           AND inventory_lot.owner_partner_id = shipment_row.owner_partner_id
           AND inventory_lot.item_id = shipment_line_row.item_id
           AND inventory_lot.lot_no = shipment_line_row.lot_no_snapshot
    ) THEN
        RAISE EXCEPTION 'Shipping allocation source lot differs from shipment lot snapshot'
            USING ERRCODE = '23514';
    END IF;
    SELECT COALESCE(sum(allocation.allocated_quantity), 0)
      INTO existing_line_quantity
      FROM dwms.shipping_inventory_allocations allocation
      JOIN dwms.shipping_confirmations allocated_confirmation
        ON allocated_confirmation.id = allocation.shipping_confirmation_id
     WHERE allocation.shipment_line_id = NEW.shipment_line_id
       AND allocated_confirmation.reversal_confirmation_id IS NULL
       AND (excluded_id IS NULL OR allocation.id <> excluded_id);
    IF existing_line_quantity + NEW.allocated_quantity > shipment_line_row.base_quantity THEN
        RAISE EXCEPTION 'Shipping allocations exceed shipment line % base quantity', NEW.shipment_line_id
            USING ERRCODE = '23514';
    END IF;
    SELECT COALESCE(sum(allocation.allocated_quantity), 0)
      INTO existing_order_line_quantity
      FROM dwms.shipping_inventory_allocations allocation
      JOIN dwms.shipping_confirmations allocated_confirmation
        ON allocated_confirmation.id = allocation.shipping_confirmation_id
      JOIN dwms.shipment_lines allocated_shipment_line
        ON allocated_shipment_line.id = allocation.shipment_line_id
     WHERE allocated_shipment_line.outbound_order_line_id = outbound_line_row.id
       AND allocated_confirmation.reversal_confirmation_id IS NULL
       AND (excluded_id IS NULL OR allocation.id <> excluded_id);
    IF existing_order_line_quantity + NEW.allocated_quantity > outbound_line_row.base_quantity THEN
        RAISE EXCEPTION 'Shipping allocations exceed outbound order line % base quantity',
            outbound_line_row.id USING ERRCODE = '23514';
    END IF;
    SELECT COALESCE(sum(allocation.allocated_quantity), 0)
      INTO existing_entry_quantity
      FROM dwms.shipping_inventory_allocations allocation
     WHERE allocation.inventory_transaction_entry_id = NEW.inventory_transaction_entry_id
       AND (excluded_id IS NULL OR allocation.id <> excluded_id);
    IF existing_entry_quantity + NEW.allocated_quantity > abs(entry_row.signed_quantity) THEN
        RAISE EXCEPTION 'Shipping allocations exceed linked negative source entry'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION dwms.assert_shipping_confirmation_inventory(
    p_shipping_confirmation_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, dwms
AS $function$
DECLARE
    confirmation_row dwms.shipping_confirmations%ROWTYPE;
    transaction_row dwms.inventory_transaction_headers%ROWTYPE;
    shipment_row dwms.shipments%ROWTYPE;
    negative_entry_count bigint;
BEGIN
    IF p_shipping_confirmation_id IS NULL THEN RETURN; END IF;
    SELECT * INTO confirmation_row
      FROM dwms.shipping_confirmations
     WHERE id = p_shipping_confirmation_id
     FOR SHARE;
    IF NOT FOUND THEN RETURN; END IF;
    SELECT * INTO transaction_row
      FROM dwms.inventory_transaction_headers
     WHERE id = confirmation_row.inventory_transaction_id
     FOR SHARE;
    SELECT * INTO shipment_row
      FROM dwms.shipments
     WHERE id = confirmation_row.shipment_id
     FOR SHARE;
    IF transaction_row.id IS NULL OR shipment_row.id IS NULL
       OR confirmation_row.tenant_id <> transaction_row.tenant_id
       OR confirmation_row.tenant_id <> shipment_row.tenant_id
       OR transaction_row.warehouse_id <> shipment_row.warehouse_id
       OR transaction_row.owner_partner_id <> shipment_row.owner_partner_id THEN
        RAISE EXCEPTION 'Shipping confirmation % crosses tenant, warehouse, owner, or shipment scope',
            confirmation_row.id USING ERRCODE = '23514';
    END IF;
    IF transaction_row.posting_status <> 'POSTED' THEN
        RAISE EXCEPTION 'Shipping confirmation % requires its inventory transaction to be POSTED',
            confirmation_row.id USING ERRCODE = '23514';
    END IF;

    IF transaction_row.transaction_type = 'REVERSAL' THEN
        IF confirmation_row.reversal_confirmation_id IS NOT NULL OR EXISTS (
            SELECT 1 FROM dwms.shipping_inventory_allocations allocation
             WHERE allocation.shipping_confirmation_id = confirmation_row.id
        ) THEN
            RAISE EXCEPTION 'Shipping reversal confirmation % cannot carry shipment source allocations',
                confirmation_row.id USING ERRCODE = '23514';
        END IF;
        PERFORM 1
          FROM dwms.inventory_transaction_headers original_transaction
          JOIN dwms.shipping_confirmations original_confirmation
            ON original_confirmation.inventory_transaction_id = original_transaction.id
         WHERE original_transaction.id = transaction_row.reversal_of_transaction_id
           AND original_transaction.transaction_type = 'SHIPMENT'
           AND original_transaction.posting_status = 'POSTED'
           AND original_transaction.tenant_id = confirmation_row.tenant_id
           AND original_transaction.warehouse_id = shipment_row.warehouse_id
           AND original_transaction.owner_partner_id = shipment_row.owner_partner_id
           AND original_confirmation.shipment_id = confirmation_row.shipment_id
           AND original_confirmation.reversal_confirmation_id = confirmation_row.id
         FOR SHARE OF original_transaction, original_confirmation;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Shipping reversal confirmation % is not paired to its original SHIPMENT transaction',
                confirmation_row.id USING ERRCODE = '23514';
        END IF;
        RETURN;
    ELSIF transaction_row.transaction_type <> 'SHIPMENT' THEN
        RAISE EXCEPTION 'Shipping confirmation % must link a SHIPMENT or its exact REVERSAL transaction',
            confirmation_row.id USING ERRCODE = '23514';
    END IF;

    IF confirmation_row.reversal_confirmation_id IS NOT NULL THEN
        PERFORM 1
          FROM dwms.shipping_confirmations reversal_confirmation
          JOIN dwms.inventory_transaction_headers reversal_transaction
            ON reversal_transaction.id = reversal_confirmation.inventory_transaction_id
         WHERE reversal_confirmation.id = confirmation_row.reversal_confirmation_id
           AND reversal_confirmation.tenant_id = confirmation_row.tenant_id
           AND reversal_confirmation.shipment_id = confirmation_row.shipment_id
           AND reversal_transaction.transaction_type = 'REVERSAL'
           AND reversal_transaction.posting_status = 'POSTED'
           AND reversal_transaction.reversal_of_transaction_id = transaction_row.id
         FOR SHARE OF reversal_confirmation, reversal_transaction;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Shipping confirmation % references an invalid reversal confirmation',
                confirmation_row.id USING ERRCODE = '23514';
        END IF;
    END IF;

    IF EXISTS (
        SELECT 1
          FROM dwms.inventory_transaction_entries entry
          JOIN dwms.stock_buckets bucket ON bucket.id = entry.stock_bucket_id
         WHERE entry.inventory_transaction_id = transaction_row.id
           AND NOT (
               (bucket.account_type = 'PHYSICAL'
                    AND entry.signed_quantity < 0
                    AND entry.entry_role = 'SOURCE')
               OR
               (bucket.account_type = 'OUTBOUND_SINK'
                    AND entry.signed_quantity > 0
                    AND entry.entry_role IN ('DESTINATION','STOCK'))
           )
    ) THEN
        RAISE EXCEPTION 'SHIPMENT transaction % must move only from negative physical sources to a positive nonphysical OUTBOUND_SINK; corrections require REVERSAL plus a new shipment',
            transaction_row.id USING ERRCODE = '23514';
    END IF;
    SELECT count(*) INTO negative_entry_count
      FROM dwms.inventory_transaction_entries entry
     WHERE entry.inventory_transaction_id = transaction_row.id
       AND entry.signed_quantity < 0;
    IF negative_entry_count = 0 THEN
        RAISE EXCEPTION 'POSTED SHIPMENT transaction % has no negative source entries', transaction_row.id
            USING ERRCODE = '23514';
    END IF;
    IF EXISTS (
        SELECT 1
          FROM dwms.inventory_transaction_entries entry
          JOIN dwms.stock_buckets bucket ON bucket.id = entry.stock_bucket_id
         WHERE entry.inventory_transaction_id = transaction_row.id
           AND entry.signed_quantity < 0
           AND (
               entry.tenant_id <> confirmation_row.tenant_id
               OR entry.entry_role <> 'SOURCE'
               OR bucket.account_type <> 'PHYSICAL'
               OR bucket.tenant_id <> confirmation_row.tenant_id
               OR bucket.warehouse_id <> shipment_row.warehouse_id
               OR bucket.owner_partner_id <> shipment_row.owner_partner_id
               OR (SELECT COALESCE(sum(allocation.allocated_quantity), 0)
                     FROM dwms.shipping_inventory_allocations allocation
                    WHERE allocation.shipping_confirmation_id = confirmation_row.id
                      AND allocation.inventory_transaction_entry_id = entry.id)
                    IS DISTINCT FROM abs(entry.signed_quantity)
           )
    ) THEN
        RAISE EXCEPTION 'POSTED SHIPMENT transaction % negative physical source entries are not exactly allocated',
            transaction_row.id USING ERRCODE = '23514';
    END IF;
    IF EXISTS (
        SELECT 1
          FROM dwms.shipping_inventory_allocations allocation
          JOIN dwms.shipment_lines shipment_line ON shipment_line.id = allocation.shipment_line_id
          JOIN dwms.outbound_order_lines outbound_line
            ON outbound_line.id = shipment_line.outbound_order_line_id
          JOIN dwms.outbound_orders outbound_order ON outbound_order.id = outbound_line.outbound_order_id
          JOIN dwms.inventory_transaction_entries entry
            ON entry.id = allocation.inventory_transaction_entry_id
          JOIN dwms.stock_buckets bucket ON bucket.id = allocation.source_stock_bucket_id
          JOIN dwms.items item ON item.id = shipment_line.item_id
         WHERE allocation.shipping_confirmation_id = confirmation_row.id
           AND (
               allocation.tenant_id <> confirmation_row.tenant_id
               OR shipment_line.tenant_id <> confirmation_row.tenant_id
               OR shipment_line.shipment_id <> confirmation_row.shipment_id
               OR outbound_order.tenant_id <> confirmation_row.tenant_id
               OR outbound_order.warehouse_id <> shipment_row.warehouse_id
               OR outbound_order.owner_partner_id <> shipment_row.owner_partner_id
               OR outbound_line.item_id <> shipment_line.item_id
               OR outbound_line.uom_code <> shipment_line.uom_code
               OR NOT EXISTS (
                   SELECT 1 FROM dwms.shipment_orders shipment_order
                    WHERE shipment_order.tenant_id = confirmation_row.tenant_id
                      AND shipment_order.shipment_id = confirmation_row.shipment_id
                      AND shipment_order.outbound_order_id = outbound_order.id
               )
               OR entry.tenant_id <> confirmation_row.tenant_id
               OR entry.inventory_transaction_id <> transaction_row.id
               OR entry.stock_bucket_id <> allocation.source_stock_bucket_id
               OR entry.signed_quantity >= 0
               OR entry.entry_role <> 'SOURCE'
               OR entry.item_id <> shipment_line.item_id
               OR entry.base_uom_code <> shipment_line.base_uom_code
               OR bucket.tenant_id <> confirmation_row.tenant_id
               OR bucket.account_type <> 'PHYSICAL'
               OR bucket.warehouse_id <> shipment_row.warehouse_id
               OR bucket.owner_partner_id <> shipment_row.owner_partner_id
               OR bucket.item_id <> shipment_line.item_id
               OR allocation.base_uom_code <> shipment_line.base_uom_code
               OR item.base_uom_code <> shipment_line.base_uom_code
               OR (shipment_line.lot_no_snapshot IS NOT NULL AND NOT EXISTS (
                   SELECT 1 FROM dwms.inventory_lots inventory_lot
                    WHERE inventory_lot.id = bucket.inventory_lot_id
                      AND inventory_lot.tenant_id = confirmation_row.tenant_id
                      AND inventory_lot.owner_partner_id = shipment_row.owner_partner_id
                      AND inventory_lot.item_id = shipment_line.item_id
                      AND inventory_lot.lot_no = shipment_line.lot_no_snapshot
               ))
           )
    ) THEN
        RAISE EXCEPTION 'Shipping confirmation % contains a shipment/order/entry/bucket dimension mismatch',
            confirmation_row.id USING ERRCODE = '23514';
    END IF;
END;
$function$;

REVOKE ALL ON FUNCTION dwms.validate_shipping_inventory_allocation() FROM PUBLIC;
REVOKE ALL ON FUNCTION dwms.assert_shipping_confirmation_inventory(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION dwms.assert_shipping_inventory_transaction(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION dwms.assert_shipment_inventory_coverage(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION dwms.guard_shipping_confirmation_mutation() FROM PUBLIC;
REVOKE ALL ON FUNCTION dwms.guard_shipping_inventory_allocation_mutation() FROM PUBLIC;
REVOKE ALL ON FUNCTION dwms.deferred_check_shipping_inventory_integrity() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_validate_shipping_inventory_allocation
ON dwms.shipping_inventory_allocations;
CREATE TRIGGER trg_validate_shipping_inventory_allocation
BEFORE INSERT OR UPDATE ON dwms.shipping_inventory_allocations
FOR EACH ROW EXECUTE PROCEDURE dwms.validate_shipping_inventory_allocation();

DROP TRIGGER IF EXISTS trg_guard_shipping_inventory_allocation
ON dwms.shipping_inventory_allocations;
CREATE TRIGGER trg_guard_shipping_inventory_allocation
BEFORE UPDATE OR DELETE ON dwms.shipping_inventory_allocations
FOR EACH ROW EXECUTE PROCEDURE dwms.guard_shipping_inventory_allocation_mutation();

DROP TRIGGER IF EXISTS trg_guard_shipping_confirmation ON dwms.shipping_confirmations;
CREATE TRIGGER trg_guard_shipping_confirmation
BEFORE UPDATE OR DELETE ON dwms.shipping_confirmations
FOR EACH ROW EXECUTE PROCEDURE dwms.guard_shipping_confirmation_mutation();

DROP TRIGGER IF EXISTS trg_shipping_confirmation_inventory_integrity
ON dwms.shipping_confirmations;
CREATE CONSTRAINT TRIGGER trg_shipping_confirmation_inventory_integrity
AFTER INSERT OR UPDATE OR DELETE ON dwms.shipping_confirmations
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE PROCEDURE dwms.deferred_check_shipping_inventory_integrity();

DROP TRIGGER IF EXISTS trg_shipping_allocation_inventory_integrity
ON dwms.shipping_inventory_allocations;
CREATE CONSTRAINT TRIGGER trg_shipping_allocation_inventory_integrity
AFTER INSERT OR UPDATE OR DELETE ON dwms.shipping_inventory_allocations
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE PROCEDURE dwms.deferred_check_shipping_inventory_integrity();

DROP TRIGGER IF EXISTS trg_shipping_transaction_inventory_integrity
ON dwms.inventory_transaction_headers;
CREATE CONSTRAINT TRIGGER trg_shipping_transaction_inventory_integrity
AFTER INSERT OR UPDATE OR DELETE ON dwms.inventory_transaction_headers
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE PROCEDURE dwms.deferred_check_shipping_inventory_integrity();

DROP TRIGGER IF EXISTS trg_shipping_entry_inventory_integrity
ON dwms.inventory_transaction_entries;
CREATE CONSTRAINT TRIGGER trg_shipping_entry_inventory_integrity
AFTER INSERT OR UPDATE OR DELETE ON dwms.inventory_transaction_entries
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE PROCEDURE dwms.deferred_check_shipping_inventory_integrity();

DROP TRIGGER IF EXISTS trg_shipment_document_inventory_integrity ON dwms.shipments;
CREATE CONSTRAINT TRIGGER trg_shipment_document_inventory_integrity
AFTER INSERT OR UPDATE OR DELETE ON dwms.shipments
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE PROCEDURE dwms.deferred_check_shipping_inventory_integrity();

DROP TRIGGER IF EXISTS trg_shipment_line_inventory_integrity ON dwms.shipment_lines;
CREATE CONSTRAINT TRIGGER trg_shipment_line_inventory_integrity
AFTER INSERT OR UPDATE OR DELETE ON dwms.shipment_lines
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE PROCEDURE dwms.deferred_check_shipping_inventory_integrity();

DROP TRIGGER IF EXISTS trg_shipment_order_inventory_integrity ON dwms.shipment_orders;
CREATE CONSTRAINT TRIGGER trg_shipment_order_inventory_integrity
AFTER INSERT OR UPDATE OR DELETE ON dwms.shipment_orders
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE PROCEDURE dwms.deferred_check_shipping_inventory_integrity();

DROP TRIGGER IF EXISTS trg_outbound_line_shipping_inventory_integrity
ON dwms.outbound_order_lines;
CREATE CONSTRAINT TRIGGER trg_outbound_line_shipping_inventory_integrity
AFTER INSERT OR UPDATE OR DELETE ON dwms.outbound_order_lines
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE PROCEDURE dwms.deferred_check_shipping_inventory_integrity();

DROP TRIGGER IF EXISTS trg_outbound_order_shipping_inventory_integrity
ON dwms.outbound_orders;
CREATE CONSTRAINT TRIGGER trg_outbound_order_shipping_inventory_integrity
AFTER INSERT OR UPDATE OR DELETE ON dwms.outbound_orders
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE PROCEDURE dwms.deferred_check_shipping_inventory_integrity();

DROP TRIGGER IF EXISTS trg_prevent_core_truncate ON dwms.shipping_inventory_allocations;
CREATE TRIGGER trg_prevent_core_truncate
BEFORE TRUNCATE ON dwms.shipping_inventory_allocations
FOR EACH STATEMENT EXECUTE PROCEDURE dwms.prevent_core_document_truncate();

COMMENT ON TABLE dwms.shipping_inventory_allocations IS
    'Append-only shipment-line evidence that exactly covers every negative PHYSICAL/SOURCE entry of one POSTED SHIPMENT transaction; reversals are separate exact-inverse REVERSAL transactions without duplicate allocations.';
