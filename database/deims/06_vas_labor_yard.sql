-- DEIMS enterprise WMS schema - value-added services, labor, yard, dock execution, scans, sensors, and incidents.

CREATE TABLE IF NOT EXISTS deims.vas_service_catalog (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    service_code varchar(80) NOT NULL,
    service_name varchar(200) NOT NULL,
    service_type varchar(40) NOT NULL,
    default_charge_code_id uuid REFERENCES deims.charge_codes(id),
    default_work_area_id uuid REFERENCES deims.work_areas(id),
    requires_bom boolean NOT NULL DEFAULT false,
    requires_quality_check boolean NOT NULL DEFAULT false,
    requires_customer_approval boolean NOT NULL DEFAULT false,
    instructions_template text,
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, service_code),
    CONSTRAINT ck_deims_vas_service_type CHECK (service_type IN (
        'KITTING','ASSEMBLY','DISASSEMBLY','REPACK','RELABEL','MARKING','SORTING','INSPECTION',
        'REPAIR','CUSTOMIZATION','GIFT_WRAP','PALLETIZE','DEPALLETIZE','OTHER'
    ))
);

CREATE TABLE IF NOT EXISTS deims.vas_work_orders (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    warehouse_id uuid NOT NULL REFERENCES deims.warehouses(id),
    owner_partner_id uuid NOT NULL REFERENCES deims.business_partners(id),
    work_order_no varchar(120) NOT NULL,
    service_id uuid NOT NULL REFERENCES deims.vas_service_catalog(id),
    customer_reference varchar(200),
    outbound_order_id uuid REFERENCES deims.outbound_orders(id),
    inbound_order_id uuid REFERENCES deims.inbound_orders(id),
    bom_id uuid REFERENCES deims.bill_of_materials(id),
    work_area_id uuid REFERENCES deims.work_areas(id),
    priority integer NOT NULL DEFAULT 100,
    planned_quantity numeric(24,8),
    completed_quantity numeric(24,8) NOT NULL DEFAULT 0,
    rejected_quantity numeric(24,8) NOT NULL DEFAULT 0,
    uom_code varchar(20) REFERENCES deims.units_of_measure(uom_code),
    scheduled_start_at timestamptz,
    scheduled_complete_at timestamptz,
    actual_start_at timestamptz,
    actual_complete_at timestamptz,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    approval_status varchar(20) NOT NULL DEFAULT 'NOT_REQUIRED',
    instructions text,
    row_version bigint NOT NULL DEFAULT 1,
    created_by uuid REFERENCES deims.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, work_order_no),
    CONSTRAINT ck_deims_vas_order_source CHECK (num_nonnulls(outbound_order_id, inbound_order_id) <= 1),
    CONSTRAINT ck_deims_vas_order_priority CHECK (priority >= 0),
    CONSTRAINT ck_deims_vas_order_qty CHECK (
        (planned_quantity IS NULL OR planned_quantity > 0) AND completed_quantity >= 0 AND rejected_quantity >= 0 AND
        (planned_quantity IS NULL OR completed_quantity + rejected_quantity <= planned_quantity)
    ),
    CONSTRAINT ck_deims_vas_order_schedule CHECK (scheduled_complete_at IS NULL OR scheduled_start_at IS NULL OR scheduled_complete_at >= scheduled_start_at),
    CONSTRAINT ck_deims_vas_order_actual CHECK (actual_complete_at IS NULL OR actual_start_at IS NULL OR actual_complete_at >= actual_start_at),
    CONSTRAINT ck_deims_vas_order_status CHECK (status IN ('DRAFT','APPROVAL_PENDING','RELEASED','IN_PROGRESS','PAUSED','COMPLETED','CANCELLED','CLOSED')),
    CONSTRAINT ck_deims_vas_approval_status CHECK (approval_status IN ('NOT_REQUIRED','PENDING','APPROVED','REJECTED'))
);

CREATE TABLE IF NOT EXISTS deims.vas_work_order_lines (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    work_order_id uuid NOT NULL REFERENCES deims.vas_work_orders(id) ON DELETE CASCADE,
    line_no integer NOT NULL,
    output_item_id uuid REFERENCES deims.items(id),
    planned_quantity numeric(24,8) NOT NULL,
    completed_quantity numeric(24,8) NOT NULL DEFAULT 0,
    rejected_quantity numeric(24,8) NOT NULL DEFAULT 0,
    uom_code varchar(20) NOT NULL REFERENCES deims.units_of_measure(uom_code),
    quality_specification_id uuid REFERENCES deims.quality_specifications(id),
    status varchar(20) NOT NULL DEFAULT 'OPEN',
    UNIQUE (work_order_id, line_no),
    CONSTRAINT ck_deims_vas_line_no CHECK (line_no > 0),
    CONSTRAINT ck_deims_vas_line_qty CHECK (
        planned_quantity > 0 AND completed_quantity >= 0 AND rejected_quantity >= 0 AND
        completed_quantity + rejected_quantity <= planned_quantity
    )
);

CREATE TABLE IF NOT EXISTS deims.vas_material_requirements (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    work_order_line_id uuid NOT NULL REFERENCES deims.vas_work_order_lines(id) ON DELETE CASCADE,
    sequence_no integer NOT NULL,
    item_id uuid NOT NULL REFERENCES deims.items(id),
    required_quantity numeric(24,8) NOT NULL,
    issued_quantity numeric(24,8) NOT NULL DEFAULT 0,
    consumed_quantity numeric(24,8) NOT NULL DEFAULT 0,
    returned_quantity numeric(24,8) NOT NULL DEFAULT 0,
    scrapped_quantity numeric(24,8) NOT NULL DEFAULT 0,
    uom_code varchar(20) NOT NULL REFERENCES deims.units_of_measure(uom_code),
    substitution_allowed boolean NOT NULL DEFAULT false,
    UNIQUE (work_order_line_id, sequence_no),
    CONSTRAINT ck_deims_vas_material_seq CHECK (sequence_no > 0),
    CONSTRAINT ck_deims_vas_material_qty CHECK (
        required_quantity > 0 AND issued_quantity >= 0 AND consumed_quantity >= 0 AND returned_quantity >= 0 AND
        scrapped_quantity >= 0 AND consumed_quantity + returned_quantity + scrapped_quantity <= issued_quantity
    )
);

CREATE TABLE IF NOT EXISTS deims.vas_material_issues (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    material_requirement_id uuid NOT NULL REFERENCES deims.vas_material_requirements(id),
    stock_bucket_id uuid NOT NULL REFERENCES deims.stock_buckets(id),
    issued_quantity numeric(24,8) NOT NULL,
    uom_code varchar(20) NOT NULL REFERENCES deims.units_of_measure(uom_code),
    inventory_transaction_id uuid REFERENCES deims.inventory_transaction_headers(id),
    issued_by uuid REFERENCES deims.users(id),
    issued_at timestamptz NOT NULL DEFAULT now(),
    reversal_issue_id uuid REFERENCES deims.vas_material_issues(id),
    CONSTRAINT ck_deims_vas_issue_qty CHECK (issued_quantity > 0),
    CONSTRAINT ck_deims_vas_issue_reversal CHECK (reversal_issue_id IS NULL OR reversal_issue_id <> id)
);

CREATE TABLE IF NOT EXISTS deims.vas_output_receipts (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    work_order_line_id uuid NOT NULL REFERENCES deims.vas_work_order_lines(id),
    stock_bucket_id uuid NOT NULL REFERENCES deims.stock_buckets(id),
    completed_quantity numeric(24,8) NOT NULL,
    rejected_quantity numeric(24,8) NOT NULL DEFAULT 0,
    uom_code varchar(20) NOT NULL REFERENCES deims.units_of_measure(uom_code),
    inventory_transaction_id uuid NOT NULL REFERENCES deims.inventory_transaction_headers(id),
    quality_inspection_id uuid REFERENCES deims.quality_inspections(id),
    received_by uuid REFERENCES deims.users(id),
    received_at timestamptz NOT NULL DEFAULT now(),
    idempotency_key varchar(300) NOT NULL,
    UNIQUE (tenant_id, idempotency_key),
    CONSTRAINT ck_deims_vas_output_qty CHECK (completed_quantity > 0 AND rejected_quantity >= 0)
);

CREATE TABLE IF NOT EXISTS deims.vas_work_order_status_history (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    work_order_id uuid NOT NULL REFERENCES deims.vas_work_orders(id) ON DELETE CASCADE,
    sequence_no integer NOT NULL,
    from_status varchar(20),
    to_status varchar(20) NOT NULL,
    reason text,
    actor_user_id uuid REFERENCES deims.users(id),
    occurred_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (work_order_id, sequence_no),
    CONSTRAINT ck_deims_vas_status_seq CHECK (sequence_no > 0)
);

CREATE TABLE IF NOT EXISTS deims.labor_shift_templates (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    warehouse_id uuid NOT NULL REFERENCES deims.warehouses(id),
    shift_code varchar(50) NOT NULL,
    shift_name varchar(150) NOT NULL,
    start_time time NOT NULL,
    end_time time NOT NULL,
    crosses_midnight boolean NOT NULL DEFAULT false,
    break_minutes integer NOT NULL DEFAULT 0,
    paid_break_minutes integer NOT NULL DEFAULT 0,
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, warehouse_id, shift_code),
    CONSTRAINT ck_deims_shift_time CHECK (crosses_midnight OR end_time > start_time),
    CONSTRAINT ck_deims_shift_break CHECK (break_minutes >= 0 AND paid_break_minutes BETWEEN 0 AND break_minutes)
);

CREATE TABLE IF NOT EXISTS deims.labor_shifts (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    warehouse_id uuid NOT NULL REFERENCES deims.warehouses(id),
    shift_template_id uuid REFERENCES deims.labor_shift_templates(id),
    shift_date date NOT NULL,
    planned_start_at timestamptz NOT NULL,
    planned_end_at timestamptz NOT NULL,
    actual_start_at timestamptz,
    actual_end_at timestamptz,
    supervisor_user_id uuid REFERENCES deims.users(id),
    planned_headcount integer,
    status varchar(20) NOT NULL DEFAULT 'PLANNED',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_deims_labor_shift_plan CHECK (planned_end_at > planned_start_at),
    CONSTRAINT ck_deims_labor_shift_actual CHECK (actual_end_at IS NULL OR actual_start_at IS NULL OR actual_end_at >= actual_start_at),
    CONSTRAINT ck_deims_labor_shift_headcount CHECK (planned_headcount IS NULL OR planned_headcount >= 0),
    CONSTRAINT ck_deims_labor_shift_status CHECK (status IN ('PLANNED','OPEN','IN_PROGRESS','COMPLETED','CANCELLED'))
);

CREATE TABLE IF NOT EXISTS deims.worker_profiles (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    user_id uuid REFERENCES deims.users(id),
    warehouse_id uuid NOT NULL REFERENCES deims.warehouses(id),
    employee_no varchar(80) NOT NULL,
    employment_type varchar(30) NOT NULL,
    agency_partner_id uuid REFERENCES deims.business_partners(id),
    hire_date date,
    termination_date date,
    labor_cost_per_hour numeric(20,4),
    currency_code char(3) REFERENCES deims.currencies(currency_code),
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, warehouse_id, employee_no),
    CONSTRAINT ck_deims_worker_type CHECK (employment_type IN ('EMPLOYEE','TEMPORARY','CONTRACTOR','AGENCY','ROBOT')),
    CONSTRAINT ck_deims_worker_dates CHECK (termination_date IS NULL OR hire_date IS NULL OR termination_date >= hire_date),
    CONSTRAINT ck_deims_worker_cost CHECK (labor_cost_per_hour IS NULL OR labor_cost_per_hour >= 0),
    CONSTRAINT ck_deims_worker_status CHECK (status IN ('ACTIVE','LEAVE','SUSPENDED','TERMINATED'))
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_deims_worker_user
    ON deims.worker_profiles (tenant_id, warehouse_id, user_id) WHERE user_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS deims.skill_definitions (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    skill_code varchar(80) NOT NULL,
    skill_name varchar(150) NOT NULL,
    skill_category varchar(40),
    certification_required boolean NOT NULL DEFAULT false,
    is_active boolean NOT NULL DEFAULT true,
    UNIQUE (tenant_id, skill_code)
);

CREATE TABLE IF NOT EXISTS deims.worker_skills (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    worker_id uuid NOT NULL REFERENCES deims.worker_profiles(id) ON DELETE CASCADE,
    skill_id uuid NOT NULL REFERENCES deims.skill_definitions(id),
    proficiency_level smallint NOT NULL DEFAULT 1,
    certified_at date,
    expires_at date,
    certification_no varchar(150),
    evidence_file_id uuid REFERENCES deims.files(id),
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    UNIQUE (worker_id, skill_id),
    CONSTRAINT ck_deims_worker_skill_level CHECK (proficiency_level BETWEEN 1 AND 5),
    CONSTRAINT ck_deims_worker_skill_dates CHECK (expires_at IS NULL OR certified_at IS NULL OR expires_at >= certified_at)
);

CREATE TABLE IF NOT EXISTS deims.shift_worker_assignments (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    labor_shift_id uuid NOT NULL REFERENCES deims.labor_shifts(id) ON DELETE CASCADE,
    worker_id uuid NOT NULL REFERENCES deims.worker_profiles(id),
    work_area_id uuid REFERENCES deims.work_areas(id),
    role_code varchar(50),
    planned_start_at timestamptz,
    planned_end_at timestamptz,
    status varchar(20) NOT NULL DEFAULT 'ASSIGNED',
    UNIQUE (labor_shift_id, worker_id),
    CONSTRAINT ck_deims_shift_worker_dates CHECK (planned_end_at IS NULL OR planned_start_at IS NULL OR planned_end_at >= planned_start_at)
);

CREATE TABLE IF NOT EXISTS deims.attendance_events (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    worker_id uuid NOT NULL REFERENCES deims.worker_profiles(id),
    labor_shift_id uuid REFERENCES deims.labor_shifts(id),
    event_type varchar(20) NOT NULL,
    occurred_at timestamptz NOT NULL,
    source varchar(30) NOT NULL,
    source_device_id uuid REFERENCES deims.rf_devices(id),
    recorded_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_deims_attendance_type CHECK (event_type IN ('CLOCK_IN','CLOCK_OUT','BREAK_START','BREAK_END','AREA_IN','AREA_OUT'))
);

CREATE TABLE IF NOT EXISTS deims.labor_tasks (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    warehouse_id uuid NOT NULL REFERENCES deims.warehouses(id),
    task_no varchar(120) NOT NULL,
    task_type varchar(40) NOT NULL,
    source_entity_type varchar(80),
    source_entity_id uuid,
    work_area_id uuid REFERENCES deims.work_areas(id),
    required_skill_id uuid REFERENCES deims.skill_definitions(id),
    priority integer NOT NULL DEFAULT 100,
    estimated_minutes numeric(12,3),
    planned_quantity numeric(24,8),
    uom_code varchar(20) REFERENCES deims.units_of_measure(uom_code),
    status varchar(20) NOT NULL DEFAULT 'OPEN',
    scheduled_at timestamptz,
    due_at timestamptz,
    started_at timestamptz,
    completed_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, task_no),
    CONSTRAINT ck_deims_labor_task_priority CHECK (priority >= 0),
    CONSTRAINT ck_deims_labor_task_estimate CHECK (estimated_minutes IS NULL OR estimated_minutes >= 0),
    CONSTRAINT ck_deims_labor_task_qty CHECK (planned_quantity IS NULL OR planned_quantity >= 0),
    CONSTRAINT ck_deims_labor_task_status CHECK (status IN ('OPEN','ASSIGNED','ACCEPTED','IN_PROGRESS','PAUSED','COMPLETED','EXCEPTION','CANCELLED')),
    CONSTRAINT ck_deims_labor_task_due CHECK (due_at IS NULL OR scheduled_at IS NULL OR due_at >= scheduled_at),
    CONSTRAINT ck_deims_labor_task_actual CHECK (completed_at IS NULL OR started_at IS NULL OR completed_at >= started_at)
);

CREATE TABLE IF NOT EXISTS deims.labor_task_assignments (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    labor_task_id uuid NOT NULL REFERENCES deims.labor_tasks(id) ON DELETE CASCADE,
    worker_id uuid NOT NULL REFERENCES deims.worker_profiles(id),
    assigned_by uuid REFERENCES deims.users(id),
    assigned_at timestamptz NOT NULL DEFAULT now(),
    accepted_at timestamptz,
    released_at timestamptz,
    release_reason text,
    status varchar(20) NOT NULL DEFAULT 'ASSIGNED',
    CONSTRAINT ck_deims_labor_assignment_dates CHECK (
        (accepted_at IS NULL OR accepted_at >= assigned_at) AND (released_at IS NULL OR released_at >= assigned_at)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_deims_active_labor_assignment
    ON deims.labor_task_assignments (labor_task_id)
    WHERE released_at IS NULL AND status IN ('ASSIGNED','ACCEPTED','IN_PROGRESS');

CREATE TABLE IF NOT EXISTS deims.labor_time_entries (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    worker_id uuid NOT NULL REFERENCES deims.worker_profiles(id),
    labor_task_id uuid REFERENCES deims.labor_tasks(id),
    work_area_id uuid REFERENCES deims.work_areas(id),
    time_type varchar(30) NOT NULL,
    started_at timestamptz NOT NULL,
    ended_at timestamptz,
    duration_minutes numeric(12,3),
    approved_by uuid REFERENCES deims.users(id),
    approved_at timestamptz,
    source varchar(30) NOT NULL DEFAULT 'SYSTEM',
    CONSTRAINT ck_deims_labor_time_dates CHECK (ended_at IS NULL OR ended_at >= started_at),
    CONSTRAINT ck_deims_labor_duration CHECK (duration_minutes IS NULL OR duration_minutes >= 0),
    CONSTRAINT ck_deims_labor_time_type CHECK (time_type IN ('PRODUCTIVE','INDIRECT','BREAK','TRAINING','MEETING','DOWNTIME','OVERTIME'))
);

CREATE TABLE IF NOT EXISTS deims.labor_productivity_events (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    warehouse_id uuid NOT NULL REFERENCES deims.warehouses(id),
    worker_id uuid REFERENCES deims.worker_profiles(id),
    labor_task_id uuid REFERENCES deims.labor_tasks(id),
    activity_type varchar(40) NOT NULL,
    quantity numeric(24,8) NOT NULL,
    uom_code varchar(20) NOT NULL REFERENCES deims.units_of_measure(uom_code),
    standard_minutes numeric(12,3),
    actual_minutes numeric(12,3),
    occurred_at timestamptz NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_deims_labor_productivity_qty CHECK (quantity >= 0),
    CONSTRAINT ck_deims_labor_productivity_minutes CHECK (
        (standard_minutes IS NULL OR standard_minutes >= 0) AND (actual_minutes IS NULL OR actual_minutes >= 0)
    )
);

CREATE TABLE IF NOT EXISTS deims.drivers (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    carrier_partner_id uuid NOT NULL REFERENCES deims.business_partners(id),
    driver_code varchar(80) NOT NULL,
    driver_name_encrypted text NOT NULL,
    driver_name_masked varchar(150),
    phone_encrypted text,
    phone_search_hash char(64),
    license_no_encrypted text,
    license_no_search_hash char(64),
    license_class varchar(50),
    license_expiry date,
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, carrier_partner_id, driver_code),
    CONSTRAINT ck_deims_driver_status CHECK (status IN ('ACTIVE','SUSPENDED','EXPIRED','INACTIVE'))
);

CREATE TABLE IF NOT EXISTS deims.vehicles (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    carrier_partner_id uuid NOT NULL REFERENCES deims.business_partners(id),
    vehicle_code varchar(80) NOT NULL,
    license_plate varchar(50) NOT NULL,
    vehicle_type varchar(50),
    max_payload_weight numeric(24,6),
    max_volume numeric(24,9),
    refrigerated boolean NOT NULL DEFAULT false,
    dangerous_goods_capable boolean NOT NULL DEFAULT false,
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, vehicle_code),
    UNIQUE (tenant_id, license_plate),
    CONSTRAINT ck_deims_vehicle_capacity CHECK (
        (max_payload_weight IS NULL OR max_payload_weight >= 0) AND (max_volume IS NULL OR max_volume >= 0)
    )
);

CREATE TABLE IF NOT EXISTS deims.trailers (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    carrier_partner_id uuid REFERENCES deims.business_partners(id),
    trailer_code varchar(80) NOT NULL,
    license_plate varchar(50),
    trailer_type varchar(50),
    refrigerated boolean NOT NULL DEFAULT false,
    status varchar(20) NOT NULL DEFAULT 'AVAILABLE',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, trailer_code)
);

CREATE TABLE IF NOT EXISTS deims.yard_visits (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    warehouse_id uuid NOT NULL REFERENCES deims.warehouses(id),
    visit_no varchar(120) NOT NULL,
    visit_type varchar(30) NOT NULL,
    dock_appointment_id uuid REFERENCES deims.dock_appointments(id),
    carrier_partner_id uuid REFERENCES deims.business_partners(id),
    driver_id uuid REFERENCES deims.drivers(id),
    vehicle_id uuid REFERENCES deims.vehicles(id),
    trailer_id uuid REFERENCES deims.trailers(id),
    external_vehicle_plate varchar(50),
    gate_in_id uuid REFERENCES deims.warehouse_gates(id),
    gate_out_id uuid REFERENCES deims.warehouse_gates(id),
    yard_slot_id uuid REFERENCES deims.yard_slots(id),
    dock_door_id uuid REFERENCES deims.dock_doors(id),
    planned_arrival_at timestamptz,
    gate_in_at timestamptz,
    dock_in_at timestamptz,
    dock_out_at timestamptz,
    gate_out_at timestamptz,
    status varchar(20) NOT NULL DEFAULT 'EXPECTED',
    security_clearance_status varchar(20) NOT NULL DEFAULT 'PENDING',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, visit_no),
    CONSTRAINT ck_deims_yard_visit_type CHECK (visit_type IN ('INBOUND','OUTBOUND','BOTH','DROP','PICKUP','SERVICE','OTHER')),
    CONSTRAINT ck_deims_yard_visit_vehicle CHECK (vehicle_id IS NOT NULL OR external_vehicle_plate IS NOT NULL),
    CONSTRAINT ck_deims_yard_visit_status CHECK (status IN ('EXPECTED','ARRIVED','GATE_IN','IN_YARD','AT_DOCK','PROCESSING','DOCK_OUT','GATE_OUT','CANCELLED')),
    CONSTRAINT ck_deims_yard_visit_timeline CHECK (
        (dock_in_at IS NULL OR gate_in_at IS NULL OR dock_in_at >= gate_in_at) AND
        (dock_out_at IS NULL OR dock_in_at IS NULL OR dock_out_at >= dock_in_at) AND
        (gate_out_at IS NULL OR gate_in_at IS NULL OR gate_out_at >= gate_in_at)
    )
);

CREATE TABLE IF NOT EXISTS deims.yard_visit_events (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    yard_visit_id uuid NOT NULL REFERENCES deims.yard_visits(id) ON DELETE CASCADE,
    sequence_no integer NOT NULL,
    event_type varchar(40) NOT NULL,
    from_status varchar(20),
    to_status varchar(20),
    gate_id uuid REFERENCES deims.warehouse_gates(id),
    yard_slot_id uuid REFERENCES deims.yard_slots(id),
    dock_door_id uuid REFERENCES deims.dock_doors(id),
    actor_user_id uuid REFERENCES deims.users(id),
    occurred_at timestamptz NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT now(),
    details jsonb NOT NULL DEFAULT '{}'::jsonb,
    UNIQUE (yard_visit_id, sequence_no),
    CONSTRAINT ck_deims_yard_event_seq CHECK (sequence_no > 0)
);

CREATE TABLE IF NOT EXISTS deims.dock_operations (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    warehouse_id uuid NOT NULL REFERENCES deims.warehouses(id),
    dock_door_id uuid NOT NULL REFERENCES deims.dock_doors(id),
    yard_visit_id uuid REFERENCES deims.yard_visits(id),
    receipt_id uuid REFERENCES deims.receipts(id),
    shipment_id uuid REFERENCES deims.shipments(id),
    operation_type varchar(20) NOT NULL,
    planned_start_at timestamptz,
    actual_start_at timestamptz,
    actual_end_at timestamptz,
    status varchar(20) NOT NULL DEFAULT 'PLANNED',
    supervisor_user_id uuid REFERENCES deims.users(id),
    CONSTRAINT ck_deims_dock_operation_document CHECK (receipt_id IS NOT NULL OR shipment_id IS NOT NULL),
    CONSTRAINT ck_deims_dock_operation_type CHECK (operation_type IN ('UNLOAD','LOAD','CROSS_DOCK','INSPECTION','OTHER')),
    CONSTRAINT ck_deims_dock_operation_dates CHECK (actual_end_at IS NULL OR actual_start_at IS NULL OR actual_end_at >= actual_start_at)
);

CREATE TABLE IF NOT EXISTS deims.scan_events (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    warehouse_id uuid NOT NULL REFERENCES deims.warehouses(id),
    scan_type varchar(40) NOT NULL,
    barcode_type varchar(30),
    barcode_value_masked varchar(300) NOT NULL,
    entity_type varchar(80),
    entity_id uuid,
    user_id uuid REFERENCES deims.users(id),
    device_id uuid REFERENCES deims.rf_devices(id),
    location_id uuid REFERENCES deims.warehouse_locations(id),
    result varchar(20) NOT NULL,
    error_code varchar(80),
    error_detail_masked text,
    occurred_at timestamptz NOT NULL,
    received_at timestamptz NOT NULL DEFAULT now(),
    correlation_id varchar(100),
    CONSTRAINT ck_deims_scan_result CHECK (result IN ('ACCEPTED','REJECTED','WARNING'))
);

CREATE TABLE IF NOT EXISTS deims.sensor_devices (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    warehouse_id uuid NOT NULL REFERENCES deims.warehouses(id),
    sensor_code varchar(80) NOT NULL,
    sensor_type varchar(30) NOT NULL,
    manufacturer varchar(150),
    model_name varchar(150),
    external_device_id varchar(200),
    calibration_due_at timestamptz,
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, warehouse_id, sensor_code),
    CONSTRAINT ck_deims_sensor_type CHECK (sensor_type IN ('TEMPERATURE','HUMIDITY','SHOCK','LIGHT','DOOR','WEIGHT','ENERGY','OTHER'))
);

CREATE TABLE IF NOT EXISTS deims.sensor_assignments (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    sensor_id uuid NOT NULL REFERENCES deims.sensor_devices(id),
    warehouse_location_id uuid REFERENCES deims.warehouse_locations(id),
    lpn_id uuid REFERENCES deims.lpns(id),
    equipment_id uuid REFERENCES deims.material_handling_equipment(id),
    vehicle_id uuid REFERENCES deims.vehicles(id),
    assigned_at timestamptz NOT NULL,
    unassigned_at timestamptz,
    CONSTRAINT ck_deims_sensor_assignment_target CHECK (
        num_nonnulls(warehouse_location_id,lpn_id,equipment_id,vehicle_id) = 1
    ),
    CONSTRAINT ck_deims_sensor_assignment_dates CHECK (unassigned_at IS NULL OR unassigned_at >= assigned_at)
);

CREATE TABLE IF NOT EXISTS deims.sensor_readings (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    sensor_id uuid NOT NULL REFERENCES deims.sensor_devices(id),
    assignment_id uuid REFERENCES deims.sensor_assignments(id),
    measurement_type varchar(30) NOT NULL,
    measured_value numeric(24,9) NOT NULL,
    uom_code varchar(20) REFERENCES deims.units_of_measure(uom_code),
    quality_code varchar(20) NOT NULL DEFAULT 'GOOD',
    occurred_at timestamptz NOT NULL,
    received_at timestamptz NOT NULL DEFAULT now(),
    source_message_id varchar(300),
    UNIQUE (sensor_id, source_message_id)
);

CREATE TABLE IF NOT EXISTS deims.sensor_alerts (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    sensor_id uuid NOT NULL REFERENCES deims.sensor_devices(id),
    assignment_id uuid REFERENCES deims.sensor_assignments(id),
    alert_type varchar(40) NOT NULL,
    severity varchar(20) NOT NULL,
    threshold_min numeric(24,9),
    threshold_max numeric(24,9),
    observed_value numeric(24,9),
    triggered_at timestamptz NOT NULL,
    acknowledged_by uuid REFERENCES deims.users(id),
    acknowledged_at timestamptz,
    resolved_by uuid REFERENCES deims.users(id),
    resolved_at timestamptz,
    resolution_note text,
    status varchar(20) NOT NULL DEFAULT 'OPEN',
    CONSTRAINT ck_deims_sensor_alert_severity CHECK (severity IN ('INFO','WARNING','HIGH','CRITICAL')),
    CONSTRAINT ck_deims_sensor_alert_status CHECK (status IN ('OPEN','ACKNOWLEDGED','RESOLVED','FALSE_POSITIVE')),
    CONSTRAINT ck_deims_sensor_alert_dates CHECK (
        (acknowledged_at IS NULL OR acknowledged_at >= triggered_at) AND
        (resolved_at IS NULL OR resolved_at >= triggered_at)
    )
);

CREATE TABLE IF NOT EXISTS deims.operational_exceptions (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    warehouse_id uuid NOT NULL REFERENCES deims.warehouses(id),
    exception_no varchar(120) NOT NULL,
    exception_type varchar(50) NOT NULL,
    severity varchar(20) NOT NULL,
    entity_type varchar(80),
    entity_id uuid,
    owner_partner_id uuid REFERENCES deims.business_partners(id),
    location_id uuid REFERENCES deims.warehouse_locations(id),
    detected_at timestamptz NOT NULL,
    detected_by uuid REFERENCES deims.users(id),
    description text NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'OPEN',
    assigned_to uuid REFERENCES deims.users(id),
    due_at timestamptz,
    resolved_at timestamptz,
    resolution text,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, exception_no),
    CONSTRAINT ck_deims_operational_exception_severity CHECK (severity IN ('LOW','MEDIUM','HIGH','CRITICAL')),
    CONSTRAINT ck_deims_operational_exception_status CHECK (status IN ('OPEN','ASSIGNED','INVESTIGATING','RESOLVED','CLOSED','CANCELLED')),
    CONSTRAINT ck_deims_operational_exception_dates CHECK (resolved_at IS NULL OR resolved_at >= detected_at)
);

CREATE TABLE IF NOT EXISTS deims.safety_incidents (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    warehouse_id uuid NOT NULL REFERENCES deims.warehouses(id),
    incident_no varchar(120) NOT NULL,
    incident_type varchar(40) NOT NULL,
    severity varchar(20) NOT NULL,
    location_id uuid REFERENCES deims.warehouse_locations(id),
    occurred_at timestamptz NOT NULL,
    reported_at timestamptz NOT NULL DEFAULT now(),
    reported_by uuid REFERENCES deims.users(id),
    description text NOT NULL,
    immediate_action text,
    regulatory_report_required boolean NOT NULL DEFAULT false,
    regulatory_reported_at timestamptz,
    status varchar(20) NOT NULL DEFAULT 'OPEN',
    root_cause text,
    corrective_action text,
    closed_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, incident_no),
    CONSTRAINT ck_deims_safety_severity CHECK (severity IN ('NEAR_MISS','MINOR','MODERATE','MAJOR','FATAL')),
    CONSTRAINT ck_deims_safety_report CHECK (regulatory_reported_at IS NULL OR regulatory_report_required),
    CONSTRAINT ck_deims_safety_dates CHECK (closed_at IS NULL OR closed_at >= occurred_at)
);

CREATE TABLE IF NOT EXISTS deims.incident_people (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    incident_id uuid NOT NULL REFERENCES deims.safety_incidents(id) ON DELETE CASCADE,
    worker_id uuid REFERENCES deims.worker_profiles(id),
    external_person_name_encrypted text,
    person_role varchar(30) NOT NULL,
    injury_type varchar(100),
    medical_treatment boolean NOT NULL DEFAULT false,
    CONSTRAINT ck_deims_incident_person CHECK (worker_id IS NOT NULL OR external_person_name_encrypted IS NOT NULL)
);

CREATE TABLE IF NOT EXISTS deims.equipment_maintenance_orders (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    warehouse_id uuid NOT NULL REFERENCES deims.warehouses(id),
    equipment_id uuid NOT NULL REFERENCES deims.material_handling_equipment(id),
    maintenance_order_no varchar(120) NOT NULL,
    maintenance_type varchar(30) NOT NULL,
    priority varchar(20) NOT NULL DEFAULT 'NORMAL',
    requested_at timestamptz NOT NULL DEFAULT now(),
    scheduled_start_at timestamptz,
    started_at timestamptz,
    completed_at timestamptz,
    vendor_partner_id uuid REFERENCES deims.business_partners(id),
    description text NOT NULL,
    result text,
    cost_amount numeric(20,4),
    currency_code char(3) REFERENCES deims.currencies(currency_code),
    status varchar(20) NOT NULL DEFAULT 'REQUESTED',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, maintenance_order_no),
    CONSTRAINT ck_deims_maintenance_type CHECK (maintenance_type IN ('PREVENTIVE','CORRECTIVE','INSPECTION','CALIBRATION','EMERGENCY')),
    CONSTRAINT ck_deims_maintenance_cost CHECK (cost_amount IS NULL OR cost_amount >= 0),
    CONSTRAINT ck_deims_maintenance_dates CHECK (completed_at IS NULL OR started_at IS NULL OR completed_at >= started_at)
);

COMMENT ON TABLE deims.vas_material_issues IS
    'VAS material consumption is linked to immutable inventory transactions; corrections use reversal_issue_id.';
COMMENT ON TABLE deims.scan_events IS
    'Append-only operational scan evidence. Sensitive barcode/error content should be masked before insertion.';
COMMENT ON TABLE deims.sensor_readings IS
    'High-volume time-series readings; production operations should apply retention/partition policies appropriate for PostgreSQL 11.';
