-- EWMS enterprise WMS schema - warehouses, 3PL clients, location topology, equipment, and execution rules.

CREATE TABLE IF NOT EXISTS ewms.warehouses (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    organization_id uuid NOT NULL REFERENCES ewms.organizations(id),
    warehouse_code varchar(80) NOT NULL,
    warehouse_name varchar(250) NOT NULL,
    warehouse_type varchar(30) NOT NULL DEFAULT 'DISTRIBUTION_CENTER',
    address_id uuid NOT NULL REFERENCES ewms.addresses(id),
    timezone varchar(100) NOT NULL DEFAULT 'Asia/Seoul',
    default_currency_code char(3) NOT NULL DEFAULT 'KRW' REFERENCES ewms.currencies(currency_code),
    bonded_capable boolean NOT NULL DEFAULT false,
    cold_chain_capable boolean NOT NULL DEFAULT false,
    dangerous_goods_capable boolean NOT NULL DEFAULT false,
    gross_area_m2 numeric(20,6),
    storage_area_m2 numeric(20,6),
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    opened_on date,
    closed_on date,
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    UNIQUE (tenant_id, warehouse_code),
    CONSTRAINT ck_ewms_warehouse_type CHECK (warehouse_type IN (
        'DISTRIBUTION_CENTER','FULFILLMENT_CENTER','CROSS_DOCK','BONDED_WAREHOUSE',
        'COLD_STORAGE','DARK_STORE','FACTORY_WAREHOUSE','RETURN_CENTER','OTHER'
    )),
    CONSTRAINT ck_ewms_warehouse_area CHECK (
        (gross_area_m2 IS NULL OR gross_area_m2 >= 0) AND
        (storage_area_m2 IS NULL OR storage_area_m2 >= 0) AND
        (gross_area_m2 IS NULL OR storage_area_m2 IS NULL OR gross_area_m2 >= storage_area_m2)
    ),
    CONSTRAINT ck_ewms_warehouse_status CHECK (status IN ('PLANNED','ACTIVE','SUSPENDED','CLOSED')),
    CONSTRAINT ck_ewms_warehouse_dates CHECK (closed_on IS NULL OR opened_on IS NULL OR closed_on >= opened_on)
);

CREATE TABLE IF NOT EXISTS ewms.warehouse_clients (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    warehouse_id uuid NOT NULL REFERENCES ewms.warehouses(id),
    owner_partner_id uuid NOT NULL REFERENCES ewms.business_partners(id),
    client_code varchar(80) NOT NULL,
    default_inventory_status_id uuid REFERENCES ewms.inventory_statuses(id),
    default_receiving_status_id uuid REFERENCES ewms.inventory_statuses(id),
    allow_negative_inventory boolean NOT NULL DEFAULT false,
    allow_mixed_owner_lpn boolean NOT NULL DEFAULT false,
    allow_mixed_item_lpn boolean NOT NULL DEFAULT true,
    allow_over_receipt boolean NOT NULL DEFAULT false,
    receipt_tolerance_percent numeric(9,6) NOT NULL DEFAULT 0,
    shipping_tolerance_percent numeric(9,6) NOT NULL DEFAULT 0,
    billing_account_code varchar(80),
    valid_from date NOT NULL DEFAULT CURRENT_DATE,
    valid_to date,
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, warehouse_id, owner_partner_id),
    UNIQUE (tenant_id, warehouse_id, client_code),
    CONSTRAINT ck_ewms_wh_client_tolerance CHECK (
        receipt_tolerance_percent BETWEEN 0 AND 100 AND shipping_tolerance_percent BETWEEN 0 AND 100
    ),
    CONSTRAINT ck_ewms_wh_client_dates CHECK (valid_to IS NULL OR valid_to >= valid_from),
    CONSTRAINT ck_ewms_wh_client_status CHECK (status IN ('ONBOARDING','ACTIVE','ON_HOLD','TERMINATED'))
);

CREATE TABLE IF NOT EXISTS ewms.warehouse_item_policies (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    warehouse_client_id uuid NOT NULL REFERENCES ewms.warehouse_clients(id) ON DELETE CASCADE,
    item_id uuid NOT NULL REFERENCES ewms.items(id),
    min_stock_qty numeric(24,8),
    max_stock_qty numeric(24,8),
    reorder_point_qty numeric(24,8),
    reorder_qty numeric(24,8),
    default_receipt_uom_code varchar(20) REFERENCES ewms.units_of_measure(uom_code),
    default_ship_uom_code varchar(20) REFERENCES ewms.units_of_measure(uom_code),
    cycle_count_class char(1),
    allocation_method varchar(20) NOT NULL DEFAULT 'FIFO',
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, warehouse_client_id, item_id),
    CONSTRAINT ck_ewms_wh_item_qty CHECK (
        (min_stock_qty IS NULL OR min_stock_qty >= 0) AND
        (max_stock_qty IS NULL OR max_stock_qty >= 0) AND
        (reorder_point_qty IS NULL OR reorder_point_qty >= 0) AND
        (reorder_qty IS NULL OR reorder_qty >= 0) AND
        (min_stock_qty IS NULL OR max_stock_qty IS NULL OR max_stock_qty >= min_stock_qty)
    ),
    CONSTRAINT ck_ewms_wh_item_cc_class CHECK (cycle_count_class IS NULL OR cycle_count_class IN ('A','B','C','D')),
    CONSTRAINT ck_ewms_wh_item_alloc CHECK (allocation_method IN ('FIFO','FEFO','LIFO','LOT','SERIAL','MANUAL'))
);

CREATE TABLE IF NOT EXISTS ewms.warehouse_calendars (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    warehouse_id uuid NOT NULL REFERENCES ewms.warehouses(id) ON DELETE CASCADE,
    calendar_code varchar(50) NOT NULL,
    calendar_name varchar(150) NOT NULL,
    timezone varchar(100) NOT NULL DEFAULT 'Asia/Seoul',
    is_default boolean NOT NULL DEFAULT false,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, warehouse_id, calendar_code)
);

CREATE TABLE IF NOT EXISTS ewms.warehouse_operating_hours (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    calendar_id uuid NOT NULL REFERENCES ewms.warehouse_calendars(id) ON DELETE CASCADE,
    day_of_week smallint NOT NULL,
    shift_no smallint NOT NULL DEFAULT 1,
    open_time time NOT NULL,
    close_time time NOT NULL,
    crosses_midnight boolean NOT NULL DEFAULT false,
    receiving_open boolean NOT NULL DEFAULT true,
    shipping_open boolean NOT NULL DEFAULT true,
    UNIQUE (calendar_id, day_of_week, shift_no),
    CONSTRAINT ck_ewms_wh_hours_dow CHECK (day_of_week BETWEEN 0 AND 6),
    CONSTRAINT ck_ewms_wh_hours_shift CHECK (shift_no > 0),
    CONSTRAINT ck_ewms_wh_hours_range CHECK (crosses_midnight OR close_time > open_time)
);

CREATE TABLE IF NOT EXISTS ewms.warehouse_calendar_exceptions (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    calendar_id uuid NOT NULL REFERENCES ewms.warehouse_calendars(id) ON DELETE CASCADE,
    exception_date date NOT NULL,
    exception_type varchar(20) NOT NULL,
    open_time time,
    close_time time,
    reason varchar(300),
    UNIQUE (calendar_id, exception_date),
    CONSTRAINT ck_ewms_wh_calendar_exception CHECK (exception_type IN ('CLOSED','SPECIAL_HOURS','CAPACITY_REDUCTION')),
    CONSTRAINT ck_ewms_wh_calendar_exception_time CHECK (
        exception_type <> 'SPECIAL_HOURS' OR (open_time IS NOT NULL AND close_time IS NOT NULL)
    )
);

CREATE TABLE IF NOT EXISTS ewms.location_types (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid REFERENCES ewms.tenants(id) ON DELETE CASCADE,
    location_type_code varchar(50) NOT NULL,
    location_type_name varchar(150) NOT NULL,
    location_category varchar(30) NOT NULL,
    pickable boolean NOT NULL DEFAULT false,
    putaway_allowed boolean NOT NULL DEFAULT false,
    countable boolean NOT NULL DEFAULT true,
    virtual_location boolean NOT NULL DEFAULT false,
    default_inventory_status_id uuid REFERENCES ewms.inventory_statuses(id),
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_ewms_location_category CHECK (location_category IN (
        'RECEIVING','STORAGE','FORWARD_PICK','STAGING','PACKING','SHIPPING','CROSS_DOCK',
        'QUALITY','QUARANTINE','DAMAGE','VAS','RETURNS','DOCK','YARD','VIRTUAL'
    ))
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_ewms_location_types_scope
    ON ewms.location_types (
        COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), location_type_code
    );

CREATE TABLE IF NOT EXISTS ewms.location_profiles (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    profile_code varchar(50) NOT NULL,
    profile_name varchar(150) NOT NULL,
    max_weight numeric(24,6),
    weight_uom_code varchar(20) REFERENCES ewms.units_of_measure(uom_code),
    max_volume numeric(24,9),
    volume_uom_code varchar(20) REFERENCES ewms.units_of_measure(uom_code),
    max_lpn_count integer,
    max_item_count integer,
    max_height numeric(20,6),
    dimension_uom_code varchar(20) REFERENCES ewms.units_of_measure(uom_code),
    allow_mixed_owner boolean NOT NULL DEFAULT false,
    allow_mixed_item boolean NOT NULL DEFAULT true,
    allow_mixed_lot boolean NOT NULL DEFAULT true,
    allow_mixed_status boolean NOT NULL DEFAULT false,
    temperature_min_c numeric(8,3),
    temperature_max_c numeric(8,3),
    humidity_min_percent numeric(8,3),
    humidity_max_percent numeric(8,3),
    dangerous_goods_allowed boolean NOT NULL DEFAULT false,
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, profile_code),
    CONSTRAINT ck_ewms_location_profile_limits CHECK (
        (max_weight IS NULL OR max_weight >= 0) AND (max_volume IS NULL OR max_volume >= 0) AND
        (max_lpn_count IS NULL OR max_lpn_count > 0) AND (max_item_count IS NULL OR max_item_count > 0) AND
        (max_height IS NULL OR max_height >= 0)
    ),
    CONSTRAINT ck_ewms_location_profile_temp CHECK (
        temperature_max_c IS NULL OR temperature_min_c IS NULL OR temperature_max_c >= temperature_min_c
    ),
    CONSTRAINT ck_ewms_location_profile_humidity CHECK (
        (humidity_min_percent IS NULL OR humidity_min_percent BETWEEN 0 AND 100) AND
        (humidity_max_percent IS NULL OR humidity_max_percent BETWEEN 0 AND 100) AND
        (humidity_max_percent IS NULL OR humidity_min_percent IS NULL OR humidity_max_percent >= humidity_min_percent)
    )
);

CREATE TABLE IF NOT EXISTS ewms.warehouse_zones (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    warehouse_id uuid NOT NULL REFERENCES ewms.warehouses(id) ON DELETE CASCADE,
    zone_code varchar(50) NOT NULL,
    zone_name varchar(150) NOT NULL,
    zone_type varchar(30) NOT NULL,
    sequence_no integer NOT NULL DEFAULT 0,
    temperature_min_c numeric(8,3),
    temperature_max_c numeric(8,3),
    bonded_controlled boolean NOT NULL DEFAULT false,
    security_level varchar(30),
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, warehouse_id, zone_code),
    CONSTRAINT ck_ewms_zone_type CHECK (zone_type IN (
        'RECEIVING','RESERVE','PICK','STAGING','PACK','SHIPPING','CROSS_DOCK','QUALITY',
        'QUARANTINE','DAMAGE','VAS','RETURNS','BONDED','YARD','OTHER'
    )),
    CONSTRAINT ck_ewms_zone_temp CHECK (temperature_max_c IS NULL OR temperature_min_c IS NULL OR temperature_max_c >= temperature_min_c)
);

CREATE TABLE IF NOT EXISTS ewms.warehouse_areas (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    warehouse_id uuid NOT NULL REFERENCES ewms.warehouses(id) ON DELETE CASCADE,
    zone_id uuid NOT NULL REFERENCES ewms.warehouse_zones(id) ON DELETE CASCADE,
    area_code varchar(50) NOT NULL,
    area_name varchar(150) NOT NULL,
    floor_no varchar(20),
    sequence_no integer NOT NULL DEFAULT 0,
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, warehouse_id, area_code)
);

CREATE TABLE IF NOT EXISTS ewms.warehouse_aisles (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    warehouse_id uuid NOT NULL REFERENCES ewms.warehouses(id) ON DELETE CASCADE,
    area_id uuid NOT NULL REFERENCES ewms.warehouse_areas(id) ON DELETE CASCADE,
    aisle_code varchar(50) NOT NULL,
    aisle_name varchar(150),
    travel_sequence integer NOT NULL DEFAULT 0,
    direction varchar(20) NOT NULL DEFAULT 'BIDIRECTIONAL',
    is_active boolean NOT NULL DEFAULT true,
    UNIQUE (tenant_id, warehouse_id, aisle_code),
    CONSTRAINT ck_ewms_aisle_direction CHECK (direction IN ('FORWARD','REVERSE','BIDIRECTIONAL'))
);

CREATE TABLE IF NOT EXISTS ewms.warehouse_racks (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    warehouse_id uuid NOT NULL REFERENCES ewms.warehouses(id) ON DELETE CASCADE,
    aisle_id uuid REFERENCES ewms.warehouse_aisles(id) ON DELETE CASCADE,
    rack_code varchar(50) NOT NULL,
    rack_name varchar(150),
    rack_type varchar(30),
    bay_count integer,
    level_count integer,
    is_active boolean NOT NULL DEFAULT true,
    UNIQUE (tenant_id, warehouse_id, rack_code),
    CONSTRAINT ck_ewms_rack_counts CHECK ((bay_count IS NULL OR bay_count > 0) AND (level_count IS NULL OR level_count > 0))
);

CREATE TABLE IF NOT EXISTS ewms.warehouse_locations (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    warehouse_id uuid NOT NULL REFERENCES ewms.warehouses(id) ON DELETE CASCADE,
    zone_id uuid NOT NULL REFERENCES ewms.warehouse_zones(id),
    area_id uuid REFERENCES ewms.warehouse_areas(id),
    aisle_id uuid REFERENCES ewms.warehouse_aisles(id),
    rack_id uuid REFERENCES ewms.warehouse_racks(id),
    parent_location_id uuid REFERENCES ewms.warehouse_locations(id),
    location_type_id uuid NOT NULL REFERENCES ewms.location_types(id),
    location_profile_id uuid REFERENCES ewms.location_profiles(id),
    location_code varchar(100) NOT NULL,
    location_barcode varchar(200),
    location_name varchar(150),
    bay_no varchar(20),
    level_no varchar(20),
    position_no varchar(20),
    hierarchy_path text,
    pick_sequence integer NOT NULL DEFAULT 0,
    putaway_sequence integer NOT NULL DEFAULT 0,
    x_coordinate numeric(20,6),
    y_coordinate numeric(20,6),
    z_coordinate numeric(20,6),
    coordinate_uom_code varchar(20) REFERENCES ewms.units_of_measure(uom_code),
    check_digit varchar(20),
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    locked_for_putaway boolean NOT NULL DEFAULT false,
    locked_for_pick boolean NOT NULL DEFAULT false,
    bonded_controlled boolean NOT NULL DEFAULT false,
    is_count_location boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    UNIQUE (tenant_id, warehouse_id, location_code),
    CONSTRAINT ck_ewms_location_parent CHECK (parent_location_id IS NULL OR parent_location_id <> id),
    CONSTRAINT ck_ewms_location_status CHECK (status IN ('PLANNED','ACTIVE','BLOCKED','MAINTENANCE','INACTIVE'))
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_ewms_location_barcode
    ON ewms.warehouse_locations (tenant_id, warehouse_id, location_barcode)
    WHERE location_barcode IS NOT NULL AND deleted_at IS NULL;

CREATE TABLE IF NOT EXISTS ewms.location_capacity_overrides (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    location_id uuid NOT NULL REFERENCES ewms.warehouse_locations(id) ON DELETE CASCADE,
    owner_partner_id uuid REFERENCES ewms.business_partners(id),
    item_id uuid REFERENCES ewms.items(id),
    max_quantity numeric(24,8),
    uom_code varchar(20) REFERENCES ewms.units_of_measure(uom_code),
    max_weight numeric(24,6),
    max_volume numeric(24,9),
    valid_from timestamptz NOT NULL DEFAULT now(),
    valid_to timestamptz,
    reason text,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_ewms_location_capacity_scope CHECK (owner_partner_id IS NOT NULL OR item_id IS NOT NULL),
    CONSTRAINT ck_ewms_location_capacity_value CHECK (
        (max_quantity IS NULL OR max_quantity >= 0) AND (max_weight IS NULL OR max_weight >= 0) AND
        (max_volume IS NULL OR max_volume >= 0) AND num_nonnulls(max_quantity,max_weight,max_volume) >= 1
    ),
    CONSTRAINT ck_ewms_location_capacity_dates CHECK (valid_to IS NULL OR valid_to > valid_from)
);

CREATE TABLE IF NOT EXISTS ewms.location_status_history (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    location_id uuid NOT NULL REFERENCES ewms.warehouse_locations(id) ON DELETE CASCADE,
    from_status varchar(20),
    to_status varchar(20) NOT NULL,
    reason_code_id uuid REFERENCES ewms.reason_codes(id),
    reason_text text,
    changed_by uuid REFERENCES ewms.users(id),
    changed_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS ewms.location_inventory_status_rules (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    location_type_id uuid REFERENCES ewms.location_types(id),
    zone_id uuid REFERENCES ewms.warehouse_zones(id),
    inventory_status_id uuid NOT NULL REFERENCES ewms.inventory_statuses(id),
    operation_type varchar(30) NOT NULL,
    allowed boolean NOT NULL DEFAULT true,
    priority integer NOT NULL DEFAULT 100,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_ewms_location_status_rule_scope CHECK (num_nonnulls(location_type_id, zone_id) = 1),
    CONSTRAINT ck_ewms_location_status_rule_op CHECK (operation_type IN ('RECEIPT','PUTAWAY','MOVE','PICK','PACK','SHIP','COUNT','ADJUST'))
);

CREATE TABLE IF NOT EXISTS ewms.docks (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    warehouse_id uuid NOT NULL REFERENCES ewms.warehouses(id) ON DELETE CASCADE,
    dock_code varchar(50) NOT NULL,
    dock_name varchar(150),
    dock_type varchar(20) NOT NULL DEFAULT 'BOTH',
    zone_id uuid REFERENCES ewms.warehouse_zones(id),
    staging_location_id uuid REFERENCES ewms.warehouse_locations(id),
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    UNIQUE (tenant_id, warehouse_id, dock_code),
    CONSTRAINT ck_ewms_dock_type CHECK (dock_type IN ('INBOUND','OUTBOUND','BOTH','RAIL','CONTAINER')),
    CONSTRAINT ck_ewms_dock_status CHECK (status IN ('ACTIVE','BLOCKED','MAINTENANCE','INACTIVE'))
);

CREATE TABLE IF NOT EXISTS ewms.dock_doors (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    dock_id uuid NOT NULL REFERENCES ewms.docks(id) ON DELETE CASCADE,
    door_code varchar(50) NOT NULL,
    door_name varchar(150),
    max_vehicle_height numeric(20,6),
    max_vehicle_length numeric(20,6),
    reefer_power_available boolean NOT NULL DEFAULT false,
    status varchar(20) NOT NULL DEFAULT 'AVAILABLE',
    UNIQUE (dock_id, door_code),
    CONSTRAINT ck_ewms_dock_door_status CHECK (status IN ('AVAILABLE','OCCUPIED','RESERVED','BLOCKED','MAINTENANCE'))
);

CREATE TABLE IF NOT EXISTS ewms.yards (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    warehouse_id uuid NOT NULL REFERENCES ewms.warehouses(id) ON DELETE CASCADE,
    yard_code varchar(50) NOT NULL,
    yard_name varchar(150) NOT NULL,
    capacity integer,
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    UNIQUE (tenant_id, warehouse_id, yard_code),
    CONSTRAINT ck_ewms_yard_capacity CHECK (capacity IS NULL OR capacity >= 0)
);

CREATE TABLE IF NOT EXISTS ewms.yard_slots (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    yard_id uuid NOT NULL REFERENCES ewms.yards(id) ON DELETE CASCADE,
    slot_code varchar(50) NOT NULL,
    slot_type varchar(30) NOT NULL,
    reefer_power_available boolean NOT NULL DEFAULT false,
    max_length numeric(20,6),
    status varchar(20) NOT NULL DEFAULT 'AVAILABLE',
    UNIQUE (yard_id, slot_code),
    CONSTRAINT ck_ewms_yard_slot_type CHECK (slot_type IN ('TRUCK','TRAILER','CONTAINER','REEFER','HAZMAT','OTHER')),
    CONSTRAINT ck_ewms_yard_slot_status CHECK (status IN ('AVAILABLE','OCCUPIED','RESERVED','BLOCKED','MAINTENANCE'))
);

CREATE TABLE IF NOT EXISTS ewms.warehouse_gates (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    warehouse_id uuid NOT NULL REFERENCES ewms.warehouses(id) ON DELETE CASCADE,
    gate_code varchar(50) NOT NULL,
    gate_name varchar(150),
    gate_type varchar(20) NOT NULL DEFAULT 'BOTH',
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    UNIQUE (tenant_id, warehouse_id, gate_code),
    CONSTRAINT ck_ewms_gate_type CHECK (gate_type IN ('ENTRY','EXIT','BOTH','PEDESTRIAN'))
);

CREATE TABLE IF NOT EXISTS ewms.work_areas (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    warehouse_id uuid NOT NULL REFERENCES ewms.warehouses(id) ON DELETE CASCADE,
    zone_id uuid REFERENCES ewms.warehouse_zones(id),
    work_area_code varchar(50) NOT NULL,
    work_area_name varchar(150) NOT NULL,
    work_area_type varchar(30) NOT NULL,
    default_location_id uuid REFERENCES ewms.warehouse_locations(id),
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    UNIQUE (tenant_id, warehouse_id, work_area_code),
    CONSTRAINT ck_ewms_work_area_type CHECK (work_area_type IN (
        'RECEIVING','QUALITY','PUTAWAY','PICKING','SORTING','PACKING','SHIPPING','RETURNS','VAS','COUNTING'
    ))
);

CREATE TABLE IF NOT EXISTS ewms.workstations (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    work_area_id uuid NOT NULL REFERENCES ewms.work_areas(id) ON DELETE CASCADE,
    workstation_code varchar(50) NOT NULL,
    workstation_name varchar(150),
    workstation_type varchar(30) NOT NULL,
    location_id uuid REFERENCES ewms.warehouse_locations(id),
    ip_address inet,
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    capabilities jsonb NOT NULL DEFAULT '{}'::jsonb,
    UNIQUE (work_area_id, workstation_code),
    CONSTRAINT ck_ewms_workstation_status CHECK (status IN ('ACTIVE','BUSY','BLOCKED','MAINTENANCE','INACTIVE'))
);

CREATE TABLE IF NOT EXISTS ewms.printers (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    warehouse_id uuid NOT NULL REFERENCES ewms.warehouses(id) ON DELETE CASCADE,
    workstation_id uuid REFERENCES ewms.workstations(id),
    printer_code varchar(50) NOT NULL,
    printer_name varchar(150),
    printer_type varchar(30) NOT NULL,
    connection_uri text,
    credential_secret_ref varchar(300),
    dpi integer,
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    UNIQUE (tenant_id, warehouse_id, printer_code),
    CONSTRAINT ck_ewms_printer_type CHECK (printer_type IN ('LABEL','DOCUMENT','MOBILE','RFID')),
    CONSTRAINT ck_ewms_printer_dpi CHECK (dpi IS NULL OR dpi > 0)
);

CREATE TABLE IF NOT EXISTS ewms.material_handling_equipment_types (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid REFERENCES ewms.tenants(id) ON DELETE CASCADE,
    equipment_type_code varchar(50) NOT NULL,
    equipment_type_name varchar(150) NOT NULL,
    equipment_class varchar(30) NOT NULL,
    max_load_weight numeric(24,6),
    weight_uom_code varchar(20) REFERENCES ewms.units_of_measure(uom_code),
    requires_license boolean NOT NULL DEFAULT false,
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_ewms_mhe_class CHECK (equipment_class IN ('FORKLIFT','REACH_TRUCK','PALLET_JACK','CONVEYOR','AGV','AMR','CRANE','SORTER','OTHER'))
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_ewms_mhe_type_scope
    ON ewms.material_handling_equipment_types (
        COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), equipment_type_code
    );

CREATE TABLE IF NOT EXISTS ewms.material_handling_equipment (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    warehouse_id uuid NOT NULL REFERENCES ewms.warehouses(id),
    equipment_type_id uuid NOT NULL REFERENCES ewms.material_handling_equipment_types(id),
    equipment_code varchar(80) NOT NULL,
    serial_no varchar(150),
    manufacturer varchar(150),
    model_name varchar(150),
    commissioned_on date,
    last_inspection_on date,
    next_inspection_on date,
    status varchar(20) NOT NULL DEFAULT 'AVAILABLE',
    telemetry_device_ref varchar(200),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, warehouse_id, equipment_code),
    CONSTRAINT ck_ewms_mhe_status CHECK (status IN ('AVAILABLE','IN_USE','CHARGING','MAINTENANCE','BLOCKED','RETIRED')),
    CONSTRAINT ck_ewms_mhe_inspection_dates CHECK (next_inspection_on IS NULL OR last_inspection_on IS NULL OR next_inspection_on >= last_inspection_on)
);

CREATE TABLE IF NOT EXISTS ewms.equipment_inspections (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    equipment_id uuid NOT NULL REFERENCES ewms.material_handling_equipment(id),
    inspection_type varchar(30) NOT NULL,
    inspected_at timestamptz NOT NULL,
    inspector_user_id uuid REFERENCES ewms.users(id),
    result varchar(20) NOT NULL,
    checklist_result jsonb NOT NULL DEFAULT '{}'::jsonb,
    file_id uuid REFERENCES ewms.files(id),
    next_due_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_ewms_equipment_inspection_result CHECK (result IN ('PASS','PASS_WITH_NOTE','FAIL')),
    CONSTRAINT ck_ewms_equipment_inspection_due CHECK (next_due_at IS NULL OR next_due_at > inspected_at)
);

CREATE TABLE IF NOT EXISTS ewms.rf_devices (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    warehouse_id uuid NOT NULL REFERENCES ewms.warehouses(id),
    device_code varchar(80) NOT NULL,
    device_type varchar(30) NOT NULL,
    hardware_identifier_hash char(64),
    platform varchar(50),
    app_version varchar(50),
    assigned_user_id uuid REFERENCES ewms.users(id),
    last_seen_at timestamptz,
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, warehouse_id, device_code),
    CONSTRAINT ck_ewms_rf_device_type CHECK (device_type IN ('HANDHELD','VEHICLE_MOUNT','TABLET','WEARABLE','VOICE','RFID_READER','KIOSK')),
    CONSTRAINT ck_ewms_rf_device_status CHECK (status IN ('ACTIVE','ASSIGNED','LOST','BLOCKED','RETIRED'))
);

CREATE TABLE IF NOT EXISTS ewms.warehouse_user_scopes (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    user_id uuid NOT NULL REFERENCES ewms.users(id) ON DELETE CASCADE,
    warehouse_id uuid NOT NULL REFERENCES ewms.warehouses(id) ON DELETE CASCADE,
    owner_partner_id uuid REFERENCES ewms.business_partners(id),
    zone_id uuid REFERENCES ewms.warehouse_zones(id),
    access_level varchar(20) NOT NULL DEFAULT 'OPERATE',
    valid_from timestamptz NOT NULL DEFAULT now(),
    valid_to timestamptz,
    granted_by uuid REFERENCES ewms.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_ewms_wh_user_access CHECK (access_level IN ('VIEW','OPERATE','SUPERVISE','ADMIN')),
    CONSTRAINT ck_ewms_wh_user_scope_dates CHECK (valid_to IS NULL OR valid_to > valid_from)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_ewms_wh_user_scope
    ON ewms.warehouse_user_scopes (
        tenant_id, user_id, warehouse_id,
        COALESCE(owner_partner_id, '00000000-0000-0000-0000-000000000000'::uuid),
        COALESCE(zone_id, '00000000-0000-0000-0000-000000000000'::uuid)
    ) WHERE valid_to IS NULL;

CREATE TABLE IF NOT EXISTS ewms.putaway_strategies (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    warehouse_id uuid NOT NULL REFERENCES ewms.warehouses(id),
    owner_partner_id uuid REFERENCES ewms.business_partners(id),
    strategy_code varchar(50) NOT NULL,
    strategy_name varchar(150) NOT NULL,
    strategy_method varchar(30) NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, warehouse_id, strategy_code),
    CONSTRAINT ck_ewms_putaway_method CHECK (strategy_method IN ('FIXED','RANDOM','ZONE','EMPTY_LOCATION','CONSOLIDATE','VELOCITY','RULE_BASED'))
);

CREATE TABLE IF NOT EXISTS ewms.putaway_strategy_rules (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    strategy_id uuid NOT NULL REFERENCES ewms.putaway_strategies(id) ON DELETE CASCADE,
    priority integer NOT NULL,
    item_id uuid REFERENCES ewms.items(id),
    item_category_id uuid REFERENCES ewms.item_categories(id),
    inventory_status_id uuid REFERENCES ewms.inventory_statuses(id),
    source_zone_id uuid REFERENCES ewms.warehouse_zones(id),
    destination_zone_id uuid REFERENCES ewms.warehouse_zones(id),
    destination_location_type_id uuid REFERENCES ewms.location_types(id),
    condition_expression jsonb NOT NULL DEFAULT '{}'::jsonb,
    allow_partial_capacity boolean NOT NULL DEFAULT false,
    is_active boolean NOT NULL DEFAULT true,
    UNIQUE (strategy_id, priority),
    CONSTRAINT ck_ewms_putaway_rule_priority CHECK (priority >= 0)
);

CREATE TABLE IF NOT EXISTS ewms.allocation_strategies (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    warehouse_id uuid NOT NULL REFERENCES ewms.warehouses(id),
    owner_partner_id uuid REFERENCES ewms.business_partners(id),
    strategy_code varchar(50) NOT NULL,
    strategy_name varchar(150) NOT NULL,
    primary_method varchar(20) NOT NULL DEFAULT 'FIFO',
    allow_partial_allocation boolean NOT NULL DEFAULT true,
    allow_split_lpn boolean NOT NULL DEFAULT true,
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, warehouse_id, strategy_code),
    CONSTRAINT ck_ewms_allocation_method CHECK (primary_method IN ('FIFO','FEFO','LIFO','LOT','SERIAL','NEAREST','RULE_BASED'))
);

CREATE TABLE IF NOT EXISTS ewms.allocation_strategy_rules (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    strategy_id uuid NOT NULL REFERENCES ewms.allocation_strategies(id) ON DELETE CASCADE,
    priority integer NOT NULL,
    zone_id uuid REFERENCES ewms.warehouse_zones(id),
    location_type_id uuid REFERENCES ewms.location_types(id),
    inventory_status_id uuid REFERENCES ewms.inventory_statuses(id),
    minimum_shelf_life_days integer,
    sort_expression jsonb NOT NULL DEFAULT '[]'::jsonb,
    condition_expression jsonb NOT NULL DEFAULT '{}'::jsonb,
    is_active boolean NOT NULL DEFAULT true,
    UNIQUE (strategy_id, priority),
    CONSTRAINT ck_ewms_allocation_rule_priority CHECK (priority >= 0),
    CONSTRAINT ck_ewms_allocation_rule_shelf CHECK (minimum_shelf_life_days IS NULL OR minimum_shelf_life_days >= 0)
);

CREATE TABLE IF NOT EXISTS ewms.replenishment_policies (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    warehouse_id uuid NOT NULL REFERENCES ewms.warehouses(id),
    owner_partner_id uuid NOT NULL REFERENCES ewms.business_partners(id),
    item_id uuid REFERENCES ewms.items(id),
    item_category_id uuid REFERENCES ewms.item_categories(id),
    forward_pick_location_id uuid REFERENCES ewms.warehouse_locations(id),
    source_zone_id uuid REFERENCES ewms.warehouse_zones(id),
    trigger_method varchar(30) NOT NULL,
    min_quantity numeric(24,8),
    max_quantity numeric(24,8),
    replenish_quantity numeric(24,8),
    uom_code varchar(20) REFERENCES ewms.units_of_measure(uom_code),
    priority integer NOT NULL DEFAULT 100,
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_ewms_replenishment_scope CHECK (item_id IS NOT NULL OR item_category_id IS NOT NULL),
    CONSTRAINT ck_ewms_replenishment_method CHECK (trigger_method IN ('MIN_MAX','DEMAND','SCHEDULED','EMPTY','MANUAL')),
    CONSTRAINT ck_ewms_replenishment_qty CHECK (
        (min_quantity IS NULL OR min_quantity >= 0) AND (max_quantity IS NULL OR max_quantity >= 0) AND
        (replenish_quantity IS NULL OR replenish_quantity > 0) AND
        (min_quantity IS NULL OR max_quantity IS NULL OR max_quantity >= min_quantity)
    )
);

COMMENT ON TABLE ewms.warehouse_clients IS
    '3PL onboarding and control policy per warehouse and inventory owner. Every inventory/order/charge keeps owner_partner_id explicitly.';
COMMENT ON TABLE ewms.warehouse_locations IS
    'Smallest addressable physical or virtual warehouse bin. Physical inventory status and customs legal status are stored elsewhere.';
COMMENT ON COLUMN ewms.printers.credential_secret_ref IS
    'Reference to an external secret manager; printer credentials must not be stored in this schema.';
