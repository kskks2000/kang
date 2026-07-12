-- ETMS execution ledger, control tower, telematics, driver workflow, POD, exceptions, and incidents.

CREATE TABLE IF NOT EXISTS etms.transport_events (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    event_type varchar(100) NOT NULL,
    event_code varchar(100),
    order_id uuid REFERENCES etms.transport_orders(id),
    shipment_id uuid REFERENCES etms.shipments(id),
    shipment_leg_id uuid REFERENCES etms.shipment_legs(id),
    run_id uuid REFERENCES etms.transport_runs(id),
    run_stop_id uuid REFERENCES etms.run_stops(id),
    dispatch_order_id uuid REFERENCES etms.dispatch_orders(id),
    handling_unit_id uuid REFERENCES etms.handling_units(id),
    container_id uuid REFERENCES etms.containers(id),
    driver_id uuid REFERENCES etms.drivers(id),
    vehicle_id uuid REFERENCES etms.vehicles(id),
    location_id uuid REFERENCES etms.locations(id),
    latitude numeric(10,7),
    longitude numeric(11,7),
    accuracy_m numeric(12,3),
    occurred_at timestamptz NOT NULL,
    received_at timestamptz NOT NULL DEFAULT now(),
    source_system_id uuid REFERENCES etms.external_systems(id),
    external_event_id varchar(300),
    correlation_id varchar(100),
    causation_id uuid REFERENCES etms.transport_events(id),
    source_sequence bigint,
    event_quality varchar(20) NOT NULL DEFAULT 'REPORTED',
    is_late boolean NOT NULL DEFAULT false,
    is_duplicate boolean NOT NULL DEFAULT false,
    payload jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (source_system_id, external_event_id),
    CONSTRAINT ck_transport_events_entity CHECK (
        order_id IS NOT NULL OR shipment_id IS NOT NULL OR shipment_leg_id IS NOT NULL OR
        run_id IS NOT NULL OR run_stop_id IS NOT NULL OR handling_unit_id IS NOT NULL OR container_id IS NOT NULL
    ),
    CONSTRAINT ck_transport_events_lat CHECK (latitude IS NULL OR latitude BETWEEN -90 AND 90),
    CONSTRAINT ck_transport_events_lon CHECK (longitude IS NULL OR longitude BETWEEN -180 AND 180),
    CONSTRAINT ck_transport_events_quality CHECK (event_quality IN ('DEVICE','SCANNED','SYSTEM','REPORTED','INFERRED','CORRECTED')),
    CONSTRAINT ck_transport_events_source_sequence CHECK (source_sequence IS NULL OR source_sequence >= 0)
);

CREATE TABLE IF NOT EXISTS etms.shipment_status_history (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    shipment_id uuid NOT NULL REFERENCES etms.shipments(id) ON DELETE CASCADE,
    from_status varchar(30),
    to_status varchar(30) NOT NULL,
    reason_code varchar(80),
    reason_text text,
    source_event_id uuid REFERENCES etms.transport_events(id),
    changed_by uuid REFERENCES etms.users(id),
    occurred_at timestamptz NOT NULL,
    received_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS etms.run_status_history (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    run_id uuid NOT NULL REFERENCES etms.transport_runs(id) ON DELETE CASCADE,
    from_status varchar(30),
    to_status varchar(30) NOT NULL,
    reason_code varchar(80),
    reason_text text,
    source_event_id uuid REFERENCES etms.transport_events(id),
    changed_by uuid REFERENCES etms.users(id),
    occurred_at timestamptz NOT NULL,
    received_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS etms.stop_executions (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    run_stop_id uuid NOT NULL REFERENCES etms.run_stops(id),
    dispatch_order_id uuid REFERENCES etms.dispatch_orders(id),
    attempt_no integer NOT NULL DEFAULT 1,
    status varchar(30) NOT NULL DEFAULT 'PENDING',
    geofence_entered_at timestamptz,
    arrived_at timestamptz,
    check_in_at timestamptz,
    service_started_at timestamptz,
    service_completed_at timestamptz,
    check_out_at timestamptz,
    departed_at timestamptz,
    actual_latitude numeric(10,7),
    actual_longitude numeric(11,7),
    odometer_arrival_km numeric(20,3),
    odometer_departure_km numeric(20,3),
    waiting_minutes integer,
    service_minutes integer,
    failure_reason_code varchar(80),
    failure_detail text,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (run_stop_id, attempt_no),
    CONSTRAINT ck_stop_execution_attempt CHECK (attempt_no > 0),
    CONSTRAINT ck_stop_execution_time_order CHECK (
        (check_in_at IS NULL OR arrived_at IS NULL OR check_in_at >= arrived_at) AND
        (service_started_at IS NULL OR check_in_at IS NULL OR service_started_at >= check_in_at) AND
        (service_completed_at IS NULL OR service_started_at IS NULL OR service_completed_at >= service_started_at) AND
        (check_out_at IS NULL OR service_completed_at IS NULL OR check_out_at >= service_completed_at) AND
        (departed_at IS NULL OR check_out_at IS NULL OR departed_at >= check_out_at)
    ),
    CONSTRAINT ck_stop_execution_duration CHECK ((waiting_minutes IS NULL OR waiting_minutes >= 0) AND (service_minutes IS NULL OR service_minutes >= 0)),
    CONSTRAINT ck_stop_execution_odometer CHECK (odometer_departure_km IS NULL OR odometer_arrival_km IS NULL OR odometer_departure_km >= odometer_arrival_km)
);

CREATE TABLE IF NOT EXISTS etms.run_leg_executions (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    run_leg_id uuid NOT NULL REFERENCES etms.run_legs(id),
    attempt_no integer NOT NULL DEFAULT 1,
    dispatch_order_id uuid REFERENCES etms.dispatch_orders(id),
    driver_id uuid REFERENCES etms.drivers(id),
    vehicle_id uuid REFERENCES etms.vehicles(id),
    trailer_id uuid REFERENCES etms.trailers(id),
    actual_departure_at timestamptz,
    actual_arrival_at timestamptz,
    actual_distance_km numeric(20,3),
    odometer_start_km numeric(20,3),
    odometer_end_km numeric(20,3),
    status varchar(20) NOT NULL DEFAULT 'PENDING',
    failure_reason_code varchar(80),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (run_leg_id, attempt_no),
    CONSTRAINT ck_run_leg_execution_attempt CHECK (attempt_no > 0),
    CONSTRAINT ck_run_leg_execution_dates CHECK (actual_arrival_at IS NULL OR actual_departure_at IS NULL OR actual_arrival_at >= actual_departure_at),
    CONSTRAINT ck_run_leg_execution_distance CHECK (actual_distance_km IS NULL OR actual_distance_km >= 0),
    CONSTRAINT ck_run_leg_execution_odometer CHECK (odometer_end_km IS NULL OR odometer_start_km IS NULL OR odometer_end_km >= odometer_start_km)
);

CREATE TABLE IF NOT EXISTS etms.stop_status_history (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    stop_execution_id uuid NOT NULL REFERENCES etms.stop_executions(id) ON DELETE CASCADE,
    from_status varchar(30),
    to_status varchar(30) NOT NULL,
    reason_code varchar(80),
    source_event_id uuid REFERENCES etms.transport_events(id),
    occurred_at timestamptz NOT NULL,
    received_at timestamptz NOT NULL DEFAULT now(),
    changed_by uuid REFERENCES etms.users(id)
);

CREATE TABLE IF NOT EXISTS etms.milestone_events (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    shipment_milestone_id uuid REFERENCES etms.shipment_milestones(id),
    milestone_code varchar(80) NOT NULL,
    order_id uuid REFERENCES etms.transport_orders(id),
    shipment_id uuid REFERENCES etms.shipments(id),
    run_id uuid REFERENCES etms.transport_runs(id),
    run_stop_id uuid REFERENCES etms.run_stops(id),
    status varchar(20) NOT NULL,
    planned_at timestamptz,
    expected_at timestamptz,
    actual_at timestamptz,
    variance_minutes integer,
    source_event_id uuid REFERENCES etms.transport_events(id),
    confidence_percent numeric(7,4),
    is_sla_breach boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_milestone_event_entity CHECK (order_id IS NOT NULL OR shipment_id IS NOT NULL OR run_id IS NOT NULL),
    CONSTRAINT ck_milestone_confidence CHECK (confidence_percent IS NULL OR confidence_percent BETWEEN 0 AND 100)
);

CREATE TABLE IF NOT EXISTS etms.gps_positions (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    device_id uuid REFERENCES etms.telematics_devices(id),
    vehicle_id uuid REFERENCES etms.vehicles(id),
    driver_id uuid REFERENCES etms.drivers(id),
    run_id uuid REFERENCES etms.transport_runs(id),
    latitude numeric(10,7) NOT NULL,
    longitude numeric(11,7) NOT NULL,
    altitude_m numeric(12,3),
    speed_kph numeric(12,3),
    heading_degrees numeric(8,3),
    accuracy_m numeric(12,3),
    odometer_km numeric(20,3),
    ignition_on boolean,
    occurred_at timestamptz NOT NULL,
    received_at timestamptz NOT NULL DEFAULT now(),
    source_sequence bigint,
    raw_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT ck_gps_position_source CHECK (device_id IS NOT NULL OR vehicle_id IS NOT NULL),
    CONSTRAINT ck_gps_position_lat CHECK (latitude BETWEEN -90 AND 90),
    CONSTRAINT ck_gps_position_lon CHECK (longitude BETWEEN -180 AND 180),
    CONSTRAINT ck_gps_position_speed CHECK (speed_kph IS NULL OR speed_kph >= 0),
    CONSTRAINT ck_gps_position_heading CHECK (heading_degrees IS NULL OR heading_degrees BETWEEN 0 AND 360),
    CONSTRAINT ck_gps_position_source_sequence CHECK (source_sequence IS NULL OR source_sequence >= 0)
);

CREATE TABLE IF NOT EXISTS etms.geofence_events (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    geofence_id uuid NOT NULL REFERENCES etms.geofences(id),
    vehicle_id uuid REFERENCES etms.vehicles(id),
    run_id uuid REFERENCES etms.transport_runs(id),
    run_stop_id uuid REFERENCES etms.run_stops(id),
    event_type varchar(20) NOT NULL,
    gps_position_id uuid REFERENCES etms.gps_positions(id),
    occurred_at timestamptz NOT NULL,
    received_at timestamptz NOT NULL DEFAULT now(),
    dwell_minutes integer,
    CONSTRAINT ck_geofence_event_type CHECK (event_type IN ('ENTER','EXIT','DWELL','VIOLATION')),
    CONSTRAINT ck_geofence_event_dwell CHECK (dwell_minutes IS NULL OR dwell_minutes >= 0)
);

CREATE TABLE IF NOT EXISTS etms.eta_predictions (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    shipment_id uuid REFERENCES etms.shipments(id),
    run_id uuid REFERENCES etms.transport_runs(id),
    run_stop_id uuid REFERENCES etms.run_stops(id),
    prediction_type varchar(30) NOT NULL DEFAULT 'ARRIVAL',
    predicted_at timestamptz NOT NULL,
    prediction_generated_at timestamptz NOT NULL DEFAULT now(),
    lower_bound_at timestamptz,
    upper_bound_at timestamptz,
    confidence_percent numeric(7,4),
    model_code varchar(100) NOT NULL,
    model_version varchar(100),
    input_position_id uuid REFERENCES etms.gps_positions(id),
    factors jsonb NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT ck_eta_entity CHECK (shipment_id IS NOT NULL OR run_id IS NOT NULL OR run_stop_id IS NOT NULL),
    CONSTRAINT ck_eta_bounds CHECK (upper_bound_at IS NULL OR lower_bound_at IS NULL OR upper_bound_at >= lower_bound_at),
    CONSTRAINT ck_eta_confidence CHECK (confidence_percent IS NULL OR confidence_percent BETWEEN 0 AND 100)
);

CREATE TABLE IF NOT EXISTS etms.driver_shifts (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    driver_id uuid NOT NULL REFERENCES etms.drivers(id),
    shift_date date NOT NULL,
    home_location_id uuid REFERENCES etms.locations(id),
    planned_start_at timestamptz,
    planned_end_at timestamptz,
    actual_start_at timestamptz,
    actual_end_at timestamptz,
    status varchar(20) NOT NULL DEFAULT 'PLANNED',
    driving_minutes integer NOT NULL DEFAULT 0,
    on_duty_minutes integer NOT NULL DEFAULT 0,
    break_minutes integer NOT NULL DEFAULT 0,
    remaining_drive_minutes integer,
    compliance_status varchar(20) NOT NULL DEFAULT 'UNKNOWN',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (driver_id, shift_date, planned_start_at),
    CONSTRAINT ck_driver_shift_planned CHECK (planned_end_at IS NULL OR planned_start_at IS NULL OR planned_end_at > planned_start_at),
    CONSTRAINT ck_driver_shift_actual CHECK (actual_end_at IS NULL OR actual_start_at IS NULL OR actual_end_at > actual_start_at),
    CONSTRAINT ck_driver_shift_minutes CHECK (driving_minutes >= 0 AND on_duty_minutes >= 0 AND break_minutes >= 0)
);

CREATE TABLE IF NOT EXISTS etms.driver_duty_logs (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    driver_id uuid NOT NULL REFERENCES etms.drivers(id),
    shift_id uuid REFERENCES etms.driver_shifts(id),
    run_id uuid REFERENCES etms.transport_runs(id),
    duty_status varchar(20) NOT NULL,
    starts_at timestamptz NOT NULL,
    ends_at timestamptz,
    location_id uuid REFERENCES etms.locations(id),
    latitude numeric(10,7),
    longitude numeric(11,7),
    odometer_km numeric(20,3),
    source_code varchar(30) NOT NULL,
    certified_at timestamptz,
    correction_of_id uuid REFERENCES etms.driver_duty_logs(id),
    correction_reason text,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_driver_duty_status CHECK (duty_status IN ('OFF_DUTY','SLEEPER','DRIVING','ON_DUTY','BREAK','YARD_MOVE','PERSONAL_USE')),
    CONSTRAINT ck_driver_duty_dates CHECK (ends_at IS NULL OR ends_at > starts_at),
    CONSTRAINT ck_driver_duty_correction CHECK (correction_of_id IS NULL OR correction_of_id <> id)
);

CREATE TABLE IF NOT EXISTS etms.driver_tasks (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    driver_id uuid NOT NULL REFERENCES etms.drivers(id),
    run_id uuid REFERENCES etms.transport_runs(id),
    run_stop_id uuid REFERENCES etms.run_stops(id),
    task_type varchar(50) NOT NULL,
    sequence_no integer NOT NULL,
    title varchar(300) NOT NULL,
    instructions text,
    due_at timestamptz,
    requires_location boolean NOT NULL DEFAULT false,
    requires_photo boolean NOT NULL DEFAULT false,
    requires_signature boolean NOT NULL DEFAULT false,
    status varchar(20) NOT NULL DEFAULT 'PENDING',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (driver_id, run_id, sequence_no)
);

CREATE TABLE IF NOT EXISTS etms.driver_task_events (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    driver_task_id uuid NOT NULL REFERENCES etms.driver_tasks(id) ON DELETE CASCADE,
    event_type varchar(30) NOT NULL,
    occurred_at timestamptz NOT NULL,
    received_at timestamptz NOT NULL DEFAULT now(),
    latitude numeric(10,7),
    longitude numeric(11,7),
    file_id uuid REFERENCES etms.files(id),
    notes text,
    payload jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE TABLE IF NOT EXISTS etms.execution_checklists (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    checklist_code varchar(80) NOT NULL,
    checklist_name varchar(200) NOT NULL,
    applies_to varchar(30) NOT NULL,
    trigger_event varchar(80),
    version_no integer NOT NULL DEFAULT 1,
    valid_from date NOT NULL DEFAULT CURRENT_DATE,
    valid_to date,
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, checklist_code, version_no),
    CONSTRAINT ck_execution_checklist_applies CHECK (applies_to IN ('RUN','STOP','VEHICLE','SHIPMENT','HANDLING_UNIT'))
);

CREATE TABLE IF NOT EXISTS etms.execution_checklist_items (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    checklist_id uuid NOT NULL REFERENCES etms.execution_checklists(id) ON DELETE CASCADE,
    sequence_no integer NOT NULL,
    item_code varchar(80) NOT NULL,
    prompt_text text NOT NULL,
    response_type varchar(20) NOT NULL,
    required boolean NOT NULL DEFAULT true,
    validation_rule jsonb NOT NULL DEFAULT '{}'::jsonb,
    failure_action varchar(30),
    UNIQUE (checklist_id, sequence_no),
    UNIQUE (checklist_id, item_code),
    CONSTRAINT ck_checklist_item_response CHECK (response_type IN ('BOOLEAN','TEXT','NUMBER','PHOTO','SIGNATURE','CODE','DATE','TIMESTAMP'))
);

CREATE TABLE IF NOT EXISTS etms.execution_check_results (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    checklist_item_id uuid NOT NULL REFERENCES etms.execution_checklist_items(id),
    run_id uuid REFERENCES etms.transport_runs(id),
    run_stop_id uuid REFERENCES etms.run_stops(id),
    vehicle_id uuid REFERENCES etms.vehicles(id),
    shipment_id uuid REFERENCES etms.shipments(id),
    handling_unit_id uuid REFERENCES etms.handling_units(id),
    response_json jsonb NOT NULL,
    passed boolean,
    completed_by_driver_id uuid REFERENCES etms.drivers(id),
    completed_by_user_id uuid REFERENCES etms.users(id),
    completed_at timestamptz NOT NULL,
    latitude numeric(10,7),
    longitude numeric(11,7),
    evidence_file_id uuid REFERENCES etms.files(id),
    CONSTRAINT ck_check_result_entity CHECK ((run_id IS NOT NULL)::int + (run_stop_id IS NOT NULL)::int + (vehicle_id IS NOT NULL)::int + (shipment_id IS NOT NULL)::int + (handling_unit_id IS NOT NULL)::int >= 1)
);

CREATE TABLE IF NOT EXISTS etms.scan_events (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    scan_type varchar(30) NOT NULL,
    barcode_type varchar(30),
    barcode_value varchar(300) NOT NULL,
    handling_unit_id uuid REFERENCES etms.handling_units(id),
    order_id uuid REFERENCES etms.transport_orders(id),
    shipment_id uuid REFERENCES etms.shipments(id),
    run_id uuid REFERENCES etms.transport_runs(id),
    run_stop_id uuid REFERENCES etms.run_stops(id),
    location_id uuid REFERENCES etms.locations(id),
    scanned_by_driver_id uuid REFERENCES etms.drivers(id),
    scanned_by_user_id uuid REFERENCES etms.users(id),
    device_id uuid REFERENCES etms.telematics_devices(id),
    source_sequence bigint,
    latitude numeric(10,7),
    longitude numeric(11,7),
    occurred_at timestamptz NOT NULL,
    received_at timestamptz NOT NULL DEFAULT now(),
    result_code varchar(30) NOT NULL DEFAULT 'SUCCESS',
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT ck_scan_events_source_sequence CHECK (source_sequence IS NULL OR source_sequence >= 0)
);

CREATE TABLE IF NOT EXISTS etms.custody_transfers (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    handling_unit_id uuid REFERENCES etms.handling_units(id),
    container_id uuid REFERENCES etms.containers(id),
    shipment_id uuid REFERENCES etms.shipments(id),
    from_custodian_partner_id uuid REFERENCES etms.business_partners(id),
    to_custodian_partner_id uuid REFERENCES etms.business_partners(id),
    location_id uuid REFERENCES etms.locations(id),
    transfer_type varchar(30) NOT NULL,
    transferred_at timestamptz NOT NULL,
    condition_code varchar(30),
    quantity numeric(20,6),
    uom_code varchar(20) REFERENCES etms.units_of_measure(uom_code),
    signature_file_id uuid REFERENCES etms.files(id),
    notes text,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_custody_asset CHECK ((handling_unit_id IS NOT NULL)::int + (container_id IS NOT NULL)::int + (shipment_id IS NOT NULL)::int >= 1),
    CONSTRAINT ck_custody_parties CHECK (from_custodian_partner_id IS NULL OR to_custodian_partner_id IS NULL OR from_custodian_partner_id <> to_custodian_partner_id)
);

CREATE TABLE IF NOT EXISTS etms.sensor_devices (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    sensor_code varchar(100) NOT NULL,
    sensor_type varchar(30) NOT NULL,
    serial_no varchar(150),
    manufacturer varchar(100),
    model varchar(100),
    calibration_date date,
    calibration_due_date date,
    min_range numeric(20,6),
    max_range numeric(20,6),
    uom_code varchar(20) NOT NULL REFERENCES etms.units_of_measure(uom_code),
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, sensor_code),
    CONSTRAINT ck_sensor_range CHECK (max_range IS NULL OR min_range IS NULL OR max_range >= min_range)
);

CREATE TABLE IF NOT EXISTS etms.sensor_assignments (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    sensor_id uuid NOT NULL REFERENCES etms.sensor_devices(id),
    asset_type varchar(20) NOT NULL,
    asset_id uuid NOT NULL,
    assigned_at timestamptz NOT NULL,
    unassigned_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_sensor_assignment_asset CHECK (asset_type IN ('VEHICLE','TRAILER','CONTAINER','HANDLING_UNIT','SHIPMENT')),
    CONSTRAINT ck_sensor_assignment_dates CHECK (unassigned_at IS NULL OR unassigned_at > assigned_at)
);

CREATE TABLE IF NOT EXISTS etms.sensor_readings (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    sensor_id uuid NOT NULL REFERENCES etms.sensor_devices(id),
    assignment_id uuid REFERENCES etms.sensor_assignments(id),
    shipment_id uuid REFERENCES etms.shipments(id),
    run_id uuid REFERENCES etms.transport_runs(id),
    reading_type varchar(30) NOT NULL,
    reading_value numeric(24,8) NOT NULL,
    uom_code varchar(20) NOT NULL REFERENCES etms.units_of_measure(uom_code),
    latitude numeric(10,7),
    longitude numeric(11,7),
    battery_percent numeric(7,4),
    occurred_at timestamptz NOT NULL,
    received_at timestamptz NOT NULL DEFAULT now(),
    source_sequence bigint,
    raw_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT ck_sensor_battery CHECK (battery_percent IS NULL OR battery_percent BETWEEN 0 AND 100),
    CONSTRAINT ck_sensor_readings_source_sequence CHECK (source_sequence IS NULL OR source_sequence >= 0)
);

CREATE TABLE IF NOT EXISTS etms.sensor_alerts (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    sensor_id uuid NOT NULL REFERENCES etms.sensor_devices(id),
    reading_id uuid REFERENCES etms.sensor_readings(id),
    shipment_id uuid REFERENCES etms.shipments(id),
    run_id uuid REFERENCES etms.transport_runs(id),
    alert_type varchar(50) NOT NULL,
    severity varchar(20) NOT NULL,
    threshold_value numeric(24,8),
    actual_value numeric(24,8),
    uom_code varchar(20) REFERENCES etms.units_of_measure(uom_code),
    started_at timestamptz NOT NULL,
    ended_at timestamptz,
    acknowledged_by uuid REFERENCES etms.users(id),
    acknowledged_at timestamptz,
    resolution text,
    status varchar(20) NOT NULL DEFAULT 'OPEN',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_sensor_alert_severity CHECK (severity IN ('INFO','WARNING','CRITICAL')),
    CONSTRAINT ck_sensor_alert_dates CHECK (ended_at IS NULL OR ended_at >= started_at)
);

CREATE TABLE IF NOT EXISTS etms.fuel_transactions (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    run_id uuid REFERENCES etms.transport_runs(id),
    vehicle_id uuid NOT NULL REFERENCES etms.vehicles(id),
    driver_id uuid REFERENCES etms.drivers(id),
    transaction_no varchar(150),
    transaction_at timestamptz NOT NULL,
    location_id uuid REFERENCES etms.locations(id),
    merchant_name varchar(200),
    fuel_type varchar(30) NOT NULL,
    fuel_quantity numeric(20,6) NOT NULL,
    fuel_uom_code varchar(20) NOT NULL REFERENCES etms.units_of_measure(uom_code),
    unit_price numeric(20,8),
    net_amount numeric(20,4) NOT NULL,
    tax_amount numeric(20,4) NOT NULL DEFAULT 0,
    gross_amount numeric(20,4) NOT NULL,
    currency_code char(3) NOT NULL REFERENCES etms.currencies(currency_code),
    odometer_km numeric(20,3),
    card_token_hash char(64),
    receipt_file_id uuid REFERENCES etms.files(id),
    status varchar(20) NOT NULL DEFAULT 'POSTED',
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_fuel_transaction_values CHECK (
        fuel_quantity > 0 AND net_amount >= 0 AND tax_amount >= 0
        AND gross_amount = net_amount + tax_amount
    )
);

CREATE TABLE IF NOT EXISTS etms.toll_transactions (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    run_id uuid REFERENCES etms.transport_runs(id),
    vehicle_id uuid NOT NULL REFERENCES etms.vehicles(id),
    toll_operator varchar(200),
    toll_station_entry varchar(150),
    toll_station_exit varchar(150),
    entered_at timestamptz,
    exited_at timestamptz,
    amount numeric(20,4) NOT NULL,
    currency_code char(3) NOT NULL REFERENCES etms.currencies(currency_code),
    external_transaction_id varchar(200),
    status varchar(20) NOT NULL DEFAULT 'POSTED',
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_toll_amount CHECK (amount >= 0),
    CONSTRAINT ck_toll_dates CHECK (exited_at IS NULL OR entered_at IS NULL OR exited_at >= entered_at)
);

CREATE TABLE IF NOT EXISTS etms.run_expenses (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    run_id uuid NOT NULL REFERENCES etms.transport_runs(id),
    expense_type varchar(50) NOT NULL,
    incurred_at timestamptz NOT NULL,
    partner_id uuid REFERENCES etms.business_partners(id),
    net_amount numeric(20,4) NOT NULL,
    tax_amount numeric(20,4) NOT NULL DEFAULT 0,
    gross_amount numeric(20,4) NOT NULL,
    currency_code char(3) NOT NULL REFERENCES etms.currencies(currency_code),
    receipt_file_id uuid REFERENCES etms.files(id),
    approval_status varchar(20) NOT NULL DEFAULT 'PENDING',
    description text,
    created_by uuid REFERENCES etms.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_run_expense_amounts CHECK (
        net_amount >= 0 AND tax_amount >= 0
        AND gross_amount = net_amount + tax_amount
    )
);

CREATE TABLE IF NOT EXISTS etms.execution_exceptions (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    exception_no varchar(100) NOT NULL,
    exception_type varchar(80) NOT NULL,
    severity varchar(20) NOT NULL,
    order_id uuid REFERENCES etms.transport_orders(id),
    shipment_id uuid REFERENCES etms.shipments(id),
    shipment_leg_id uuid REFERENCES etms.shipment_legs(id),
    run_id uuid REFERENCES etms.transport_runs(id),
    run_stop_id uuid REFERENCES etms.run_stops(id),
    handling_unit_id uuid REFERENCES etms.handling_units(id),
    source_event_id uuid REFERENCES etms.transport_events(id),
    detected_at timestamptz NOT NULL,
    due_at timestamptz,
    impact_type varchar(30),
    impact_amount numeric(20,4),
    currency_code char(3) REFERENCES etms.currencies(currency_code),
    assigned_to_user_id uuid REFERENCES etms.users(id),
    assigned_to_org_unit_id uuid REFERENCES etms.organization_units(id),
    root_cause_code varchar(80),
    description text NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'OPEN',
    resolved_at timestamptz,
    resolution text,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, exception_no),
    CONSTRAINT ck_execution_exception_entity CHECK (order_id IS NOT NULL OR shipment_id IS NOT NULL OR run_id IS NOT NULL OR handling_unit_id IS NOT NULL),
    CONSTRAINT ck_execution_exception_severity CHECK (severity IN ('LOW','MEDIUM','HIGH','CRITICAL')),
    CONSTRAINT ck_execution_exception_resolution CHECK (resolved_at IS NULL OR resolved_at >= detected_at)
);

CREATE TABLE IF NOT EXISTS etms.exception_actions (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    exception_id uuid NOT NULL REFERENCES etms.execution_exceptions(id) ON DELETE CASCADE,
    action_type varchar(50) NOT NULL,
    action_description text NOT NULL,
    owner_user_id uuid REFERENCES etms.users(id),
    owner_partner_id uuid REFERENCES etms.business_partners(id),
    due_at timestamptz,
    completed_at timestamptz,
    outcome text,
    status varchar(20) NOT NULL DEFAULT 'OPEN',
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_exception_action_owner CHECK (owner_user_id IS NOT NULL OR owner_partner_id IS NOT NULL)
);

CREATE TABLE IF NOT EXISTS etms.incidents (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    incident_no varchar(100) NOT NULL,
    incident_type varchar(50) NOT NULL,
    severity varchar(20) NOT NULL,
    run_id uuid REFERENCES etms.transport_runs(id),
    shipment_id uuid REFERENCES etms.shipments(id),
    vehicle_id uuid REFERENCES etms.vehicles(id),
    driver_id uuid REFERENCES etms.drivers(id),
    location_id uuid REFERENCES etms.locations(id),
    latitude numeric(10,7),
    longitude numeric(11,7),
    occurred_at timestamptz NOT NULL,
    reported_at timestamptz NOT NULL DEFAULT now(),
    description text NOT NULL,
    injury_count integer NOT NULL DEFAULT 0,
    fatality_count integer NOT NULL DEFAULT 0,
    estimated_damage_amount numeric(20,4),
    currency_code char(3) REFERENCES etms.currencies(currency_code),
    police_report_no varchar(150),
    status varchar(20) NOT NULL DEFAULT 'OPEN',
    closed_at timestamptz,
    root_cause text,
    corrective_action text,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, incident_no),
    CONSTRAINT ck_incident_counts CHECK (injury_count >= 0 AND fatality_count >= 0),
    CONSTRAINT ck_incident_close CHECK (closed_at IS NULL OR closed_at >= occurred_at)
);

CREATE TABLE IF NOT EXISTS etms.incident_parties (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    incident_id uuid NOT NULL REFERENCES etms.incidents(id) ON DELETE CASCADE,
    party_role varchar(30) NOT NULL,
    partner_id uuid REFERENCES etms.business_partners(id),
    person_name_encrypted text,
    contact_encrypted text,
    insurance_policy_no_encrypted text,
    statement text,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS etms.incident_items (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    incident_id uuid NOT NULL REFERENCES etms.incidents(id) ON DELETE CASCADE,
    item_type varchar(30) NOT NULL,
    item_id uuid,
    damage_type varchar(50),
    damage_severity varchar(20),
    estimated_amount numeric(20,4),
    currency_code char(3) REFERENCES etms.currencies(currency_code),
    notes text,
    file_id uuid REFERENCES etms.files(id)
);

CREATE TABLE IF NOT EXISTS etms.communications (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    thread_id uuid,
    entity_type varchar(30) NOT NULL,
    entity_id uuid NOT NULL,
    channel varchar(20) NOT NULL,
    direction varchar(10) NOT NULL,
    sender_user_id uuid REFERENCES etms.users(id),
    sender_partner_id uuid REFERENCES etms.business_partners(id),
    recipient_address_masked varchar(500),
    subject varchar(500),
    body_masked text,
    template_code varchar(80),
    status varchar(20) NOT NULL DEFAULT 'QUEUED',
    external_message_id varchar(300),
    sent_at timestamptz,
    delivered_at timestamptz,
    read_at timestamptz,
    failed_at timestamptz,
    failure_detail_masked text,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_communications_channel CHECK (channel IN ('APP','EMAIL','SMS','PUSH','KAKAO','PHONE','EDI','WEBHOOK')),
    CONSTRAINT ck_communications_direction CHECK (direction IN ('IN','OUT'))
);

CREATE TABLE IF NOT EXISTS etms.tracking_share_links (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    shipment_id uuid NOT NULL REFERENCES etms.shipments(id),
    token_hash char(64) NOT NULL UNIQUE,
    audience_type varchar(30) NOT NULL DEFAULT 'CUSTOMER',
    allowed_fields jsonb NOT NULL DEFAULT '{}'::jsonb,
    expires_at timestamptz NOT NULL,
    max_views integer,
    view_count integer NOT NULL DEFAULT 0,
    revoked_at timestamptz,
    created_by uuid REFERENCES etms.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_tracking_link_views CHECK ((max_views IS NULL OR max_views > 0) AND view_count >= 0)
);

CREATE TABLE IF NOT EXISTS etms.yard_visits (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    visit_no varchar(100) NOT NULL,
    yard_location_id uuid NOT NULL REFERENCES etms.locations(id),
    run_id uuid REFERENCES etms.transport_runs(id),
    appointment_id uuid REFERENCES etms.dock_appointments(id),
    vehicle_id uuid REFERENCES etms.vehicles(id),
    trailer_id uuid REFERENCES etms.trailers(id),
    driver_id uuid REFERENCES etms.drivers(id),
    carrier_id uuid REFERENCES etms.business_partners(id),
    gate_in_at timestamptz,
    assigned_dock_id uuid REFERENCES etms.location_docks(id),
    dock_in_at timestamptz,
    dock_out_at timestamptz,
    gate_out_at timestamptz,
    status varchar(20) NOT NULL DEFAULT 'EXPECTED',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, visit_no)
);

CREATE TABLE IF NOT EXISTS etms.yard_events (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    yard_visit_id uuid NOT NULL REFERENCES etms.yard_visits(id) ON DELETE CASCADE,
    event_type varchar(40) NOT NULL,
    from_zone varchar(80),
    to_zone varchar(80),
    occurred_at timestamptz NOT NULL,
    source_code varchar(30) NOT NULL,
    user_id uuid REFERENCES etms.users(id),
    notes text,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS etms.proof_of_deliveries (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    pod_no varchar(100) NOT NULL,
    order_id uuid REFERENCES etms.transport_orders(id),
    shipment_id uuid NOT NULL REFERENCES etms.shipments(id),
    run_stop_id uuid REFERENCES etms.run_stops(id),
    delivery_attempt_no integer NOT NULL DEFAULT 1,
    delivery_result varchar(30) NOT NULL,
    delivered_at timestamptz NOT NULL,
    received_by_name_encrypted text,
    received_by_role varchar(100),
    receiver_contact_encrypted text,
    latitude numeric(10,7),
    longitude numeric(11,7),
    location_accuracy_m numeric(12,3),
    signature_file_id uuid REFERENCES etms.files(id),
    primary_photo_file_id uuid REFERENCES etms.files(id),
    document_file_id uuid REFERENCES etms.files(id),
    driver_id uuid REFERENCES etms.drivers(id),
    notes text,
    verification_status varchar(20) NOT NULL DEFAULT 'PENDING',
    verified_by uuid REFERENCES etms.users(id),
    verified_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, pod_no),
    CONSTRAINT ck_pod_attempt CHECK (delivery_attempt_no > 0),
    CONSTRAINT ck_pod_result CHECK (delivery_result IN ('DELIVERED','PARTIAL','REFUSED','FAILED','DAMAGED','SHORT','LEFT_AT_LOCATION')),
    CONSTRAINT ck_pod_lat CHECK (latitude IS NULL OR latitude BETWEEN -90 AND 90),
    CONSTRAINT ck_pod_lon CHECK (longitude IS NULL OR longitude BETWEEN -180 AND 180)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_pod_delivery_attempt
    ON etms.proof_of_deliveries (
        shipment_id,
        COALESCE(run_stop_id, '00000000-0000-0000-0000-000000000000'::uuid),
        delivery_attempt_no
    );

CREATE TABLE IF NOT EXISTS etms.pod_signatures (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    pod_id uuid NOT NULL REFERENCES etms.proof_of_deliveries(id) ON DELETE CASCADE,
    signer_role varchar(30) NOT NULL,
    signer_name_encrypted text,
    signature_file_id uuid NOT NULL REFERENCES etms.files(id),
    signed_at timestamptz NOT NULL,
    ip_address inet,
    device_fingerprint_hash char(64),
    signature_sha256 char(64) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS etms.pod_items (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    pod_id uuid NOT NULL REFERENCES etms.proof_of_deliveries(id) ON DELETE CASCADE,
    order_line_id uuid REFERENCES etms.transport_order_lines(id),
    handling_unit_id uuid REFERENCES etms.handling_units(id),
    expected_quantity numeric(20,6) NOT NULL,
    delivered_quantity numeric(20,6) NOT NULL,
    refused_quantity numeric(20,6) NOT NULL DEFAULT 0,
    damaged_quantity numeric(20,6) NOT NULL DEFAULT 0,
    uom_code varchar(20) NOT NULL REFERENCES etms.units_of_measure(uom_code),
    condition_code varchar(30),
    notes text,
    CONSTRAINT ck_pod_item_entity CHECK (order_line_id IS NOT NULL OR handling_unit_id IS NOT NULL),
    CONSTRAINT ck_pod_item_quantities CHECK (
        expected_quantity >= 0 AND delivered_quantity >= 0
        AND refused_quantity >= 0 AND damaged_quantity >= 0
        AND delivered_quantity + refused_quantity + damaged_quantity <= expected_quantity
    )
);

CREATE TABLE IF NOT EXISTS etms.delivery_discrepancies (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    pod_id uuid NOT NULL REFERENCES etms.proof_of_deliveries(id) ON DELETE CASCADE,
    pod_item_id uuid REFERENCES etms.pod_items(id),
    discrepancy_type varchar(30) NOT NULL,
    quantity numeric(20,6),
    uom_code varchar(20) REFERENCES etms.units_of_measure(uom_code),
    severity varchar(20) NOT NULL DEFAULT 'MEDIUM',
    description text NOT NULL,
    photo_file_id uuid REFERENCES etms.files(id),
    customer_acknowledged boolean NOT NULL DEFAULT false,
    acknowledged_at timestamptz,
    status varchar(20) NOT NULL DEFAULT 'OPEN',
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_delivery_discrepancy_type CHECK (discrepancy_type IN ('SHORT','OVER','DAMAGE','REFUSAL','WRONG_ITEM','TEMPERATURE','SEAL','LATE','OTHER')),
    CONSTRAINT ck_delivery_discrepancy_qty CHECK (quantity IS NULL OR quantity >= 0)
);

CREATE TABLE IF NOT EXISTS etms.damage_reports (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    report_no varchar(100) NOT NULL,
    shipment_id uuid REFERENCES etms.shipments(id),
    handling_unit_id uuid REFERENCES etms.handling_units(id),
    order_line_id uuid REFERENCES etms.transport_order_lines(id),
    incident_id uuid REFERENCES etms.incidents(id),
    pod_id uuid REFERENCES etms.proof_of_deliveries(id),
    damage_type varchar(50) NOT NULL,
    damage_extent varchar(30),
    discovered_at timestamptz NOT NULL,
    discovered_location_id uuid REFERENCES etms.locations(id),
    estimated_loss_amount numeric(20,4),
    currency_code char(3) REFERENCES etms.currencies(currency_code),
    description text NOT NULL,
    disposition varchar(30),
    status varchar(20) NOT NULL DEFAULT 'OPEN',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, report_no),
    CONSTRAINT ck_damage_report_entity CHECK (shipment_id IS NOT NULL OR handling_unit_id IS NOT NULL OR order_line_id IS NOT NULL),
    CONSTRAINT ck_damage_report_loss CHECK (estimated_loss_amount IS NULL OR estimated_loss_amount >= 0)
);
