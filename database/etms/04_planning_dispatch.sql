-- ETMS planning scenarios, consolidation, shipment/leg/run planning, tendering, dispatch, and appointments.

CREATE TABLE IF NOT EXISTS etms.planning_scenarios (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    scenario_no varchar(80) NOT NULL,
    scenario_name varchar(250) NOT NULL,
    planning_horizon_from timestamptz NOT NULL,
    planning_horizon_to timestamptz NOT NULL,
    base_scenario_id uuid REFERENCES etms.planning_scenarios(id),
    planning_scope jsonb NOT NULL DEFAULT '{}'::jsonb,
    objective_weights jsonb NOT NULL DEFAULT '{}'::jsonb,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    is_committed boolean NOT NULL DEFAULT false,
    committed_at timestamptz,
    committed_by uuid REFERENCES etms.users(id),
    row_version bigint NOT NULL DEFAULT 1,
    created_by uuid REFERENCES etms.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, scenario_no),
    CONSTRAINT ck_planning_scenario_horizon CHECK (planning_horizon_to > planning_horizon_from),
    CONSTRAINT ck_planning_scenario_base CHECK (base_scenario_id IS NULL OR base_scenario_id <> id),
    CONSTRAINT ck_planning_scenario_status CHECK (status IN ('DRAFT','READY','RUNNING','COMPLETED','FAILED','COMMITTED','SUPERSEDED','CANCELLED'))
);

CREATE TABLE IF NOT EXISTS etms.planning_scenario_orders (
    scenario_id uuid NOT NULL REFERENCES etms.planning_scenarios(id) ON DELETE CASCADE,
    order_id uuid NOT NULL REFERENCES etms.transport_orders(id),
    order_revision_id uuid NOT NULL REFERENCES etms.transport_order_revisions(id),
    inclusion_type varchar(20) NOT NULL DEFAULT 'INCLUDE',
    locked boolean NOT NULL DEFAULT false,
    lock_reason text,
    priority_override integer,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (scenario_id, order_id),
    UNIQUE (scenario_id, order_revision_id),
    CONSTRAINT ck_scenario_orders_include CHECK (inclusion_type IN ('INCLUDE','EXCLUDE','REFERENCE'))
);

CREATE TABLE IF NOT EXISTS etms.planning_constraints (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    scenario_id uuid NOT NULL REFERENCES etms.planning_scenarios(id) ON DELETE CASCADE,
    constraint_code varchar(80) NOT NULL,
    constraint_type varchar(50) NOT NULL,
    severity varchar(10) NOT NULL DEFAULT 'HARD',
    entity_type varchar(30),
    entity_id uuid,
    parameters jsonb NOT NULL DEFAULT '{}'::jsonb,
    penalty_weight numeric(20,6),
    is_active boolean NOT NULL DEFAULT true,
    UNIQUE (scenario_id, constraint_code),
    CONSTRAINT ck_planning_constraints_severity CHECK (severity IN ('HARD','SOFT')),
    CONSTRAINT ck_planning_constraints_penalty CHECK (penalty_weight IS NULL OR penalty_weight >= 0)
);

CREATE TABLE IF NOT EXISTS etms.planning_runs (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    scenario_id uuid NOT NULL REFERENCES etms.planning_scenarios(id) ON DELETE CASCADE,
    run_no integer NOT NULL,
    engine_code varchar(80) NOT NULL,
    engine_version varchar(80),
    algorithm varchar(80),
    input_hash char(64),
    random_seed bigint,
    status varchar(20) NOT NULL DEFAULT 'QUEUED',
    started_at timestamptz,
    completed_at timestamptz,
    objective_value numeric(30,8),
    total_cost numeric(20,4),
    currency_code char(3) REFERENCES etms.currencies(currency_code),
    total_distance_km numeric(20,3),
    total_emissions_kg_co2e numeric(20,6),
    unplanned_order_count integer NOT NULL DEFAULT 0,
    violation_count integer NOT NULL DEFAULT 0,
    result_summary jsonb NOT NULL DEFAULT '{}'::jsonb,
    error_detail_masked text,
    created_by uuid REFERENCES etms.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (scenario_id, run_no),
    CONSTRAINT ck_planning_runs_no CHECK (run_no > 0),
    CONSTRAINT ck_planning_runs_counts CHECK (unplanned_order_count >= 0 AND violation_count >= 0)
);

CREATE TABLE IF NOT EXISTS etms.planning_run_logs (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    planning_run_id uuid NOT NULL REFERENCES etms.planning_runs(id) ON DELETE CASCADE,
    log_level varchar(10) NOT NULL,
    step_code varchar(80),
    message_masked text NOT NULL,
    metrics jsonb NOT NULL DEFAULT '{}'::jsonb,
    logged_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_planning_run_logs_level CHECK (log_level IN ('DEBUG','INFO','WARN','ERROR'))
);

CREATE TABLE IF NOT EXISTS etms.planning_run_results (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    planning_run_id uuid NOT NULL REFERENCES etms.planning_runs(id) ON DELETE CASCADE,
    result_type varchar(30) NOT NULL,
    entity_type varchar(30),
    entity_id uuid,
    sequence_no integer,
    result_data jsonb NOT NULL,
    score numeric(30,8),
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS etms.consolidation_groups (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    group_no varchar(80) NOT NULL,
    group_type varchar(30) NOT NULL,
    planning_scenario_id uuid REFERENCES etms.planning_scenarios(id),
    consolidation_key varchar(300),
    origin_location_id uuid REFERENCES etms.locations(id),
    destination_location_id uuid REFERENCES etms.locations(id),
    mode_code varchar(20) REFERENCES etms.transport_modes(mode_code),
    planned_ship_date date,
    total_weight_kg numeric(20,6) NOT NULL DEFAULT 0,
    total_volume_m3 numeric(20,6) NOT NULL DEFAULT 0,
    status varchar(20) NOT NULL DEFAULT 'OPEN',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, group_no),
    CONSTRAINT ck_consolidation_group_type CHECK (group_type IN ('CONSOLIDATION','POOL','MILK_RUN','MULTI_DROP','CROSS_DOCK','BACKHAUL')),
    CONSTRAINT ck_consolidation_group_values CHECK (total_weight_kg >= 0 AND total_volume_m3 >= 0)
);

CREATE TABLE IF NOT EXISTS etms.consolidation_group_orders (
    group_id uuid NOT NULL REFERENCES etms.consolidation_groups(id) ON DELETE CASCADE,
    order_id uuid NOT NULL REFERENCES etms.transport_orders(id),
    allocation_weight_kg numeric(20,6),
    allocation_volume_m3 numeric(20,6),
    added_at timestamptz NOT NULL DEFAULT now(),
    removed_at timestamptz,
    PRIMARY KEY (group_id, order_id),
    CONSTRAINT ck_consolidation_allocation CHECK ((allocation_weight_kg IS NULL OR allocation_weight_kg >= 0) AND (allocation_volume_m3 IS NULL OR allocation_volume_m3 >= 0))
);

CREATE TABLE IF NOT EXISTS etms.shipments (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    shipment_no varchar(100) NOT NULL,
    shipment_type varchar(30) NOT NULL DEFAULT 'DIRECT',
    planning_scenario_id uuid REFERENCES etms.planning_scenarios(id),
    consolidation_group_id uuid REFERENCES etms.consolidation_groups(id),
    organization_id uuid NOT NULL REFERENCES etms.organizations(id),
    customer_id uuid REFERENCES etms.business_partners(id),
    primary_mode_code varchar(20) REFERENCES etms.transport_modes(mode_code),
    service_level_id uuid REFERENCES etms.service_levels(id),
    origin_location_id uuid REFERENCES etms.locations(id),
    destination_location_id uuid REFERENCES etms.locations(id),
    planned_pickup_at timestamptz,
    planned_delivery_at timestamptz,
    total_quantity numeric(20,6) NOT NULL DEFAULT 0,
    quantity_uom_code varchar(20) REFERENCES etms.units_of_measure(uom_code),
    total_weight_kg numeric(20,6) NOT NULL DEFAULT 0,
    total_volume_m3 numeric(20,6) NOT NULL DEFAULT 0,
    total_pallets numeric(20,3) NOT NULL DEFAULT 0,
    declared_value numeric(20,4),
    value_currency_code char(3) REFERENCES etms.currencies(currency_code),
    estimated_buy_cost numeric(20,4),
    estimated_sell_revenue numeric(20,4),
    cost_currency_code char(3) REFERENCES etms.currencies(currency_code),
    status varchar(30) NOT NULL DEFAULT 'PLANNED',
    tender_status varchar(20) NOT NULL DEFAULT 'NOT_TENDERED',
    dispatch_status varchar(20) NOT NULL DEFAULT 'NOT_DISPATCHED',
    tracking_status varchar(20) NOT NULL DEFAULT 'NOT_STARTED',
    billing_status varchar(20) NOT NULL DEFAULT 'NOT_RATED',
    row_version bigint NOT NULL DEFAULT 1,
    created_by uuid REFERENCES etms.users(id),
    updated_by uuid REFERENCES etms.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    UNIQUE (tenant_id, shipment_no),
    CONSTRAINT ck_shipments_type CHECK (shipment_type IN ('DIRECT','CONSOLIDATED','SPLIT','MULTI_STOP','CROSS_DOCK','INTERMODAL','RETURN','REPOSITION')),
    CONSTRAINT ck_shipments_dates CHECK (planned_delivery_at IS NULL OR planned_pickup_at IS NULL OR planned_delivery_at >= planned_pickup_at),
    CONSTRAINT ck_shipments_values CHECK (total_quantity >= 0 AND total_weight_kg >= 0 AND total_volume_m3 >= 0 AND total_pallets >= 0)
);

CREATE TABLE IF NOT EXISTS etms.shipment_orders (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    shipment_id uuid NOT NULL REFERENCES etms.shipments(id) ON DELETE CASCADE,
    order_id uuid NOT NULL REFERENCES etms.transport_orders(id),
    allocation_quantity numeric(20,6),
    allocation_weight_kg numeric(20,6),
    allocation_volume_m3 numeric(20,6),
    allocation_percent numeric(9,6),
    included_at timestamptz NOT NULL DEFAULT now(),
    removed_at timestamptz,
    UNIQUE (shipment_id, order_id),
    CONSTRAINT ck_shipment_order_allocations CHECK (
        (allocation_quantity IS NULL OR allocation_quantity >= 0) AND
        (allocation_weight_kg IS NULL OR allocation_weight_kg >= 0) AND
        (allocation_volume_m3 IS NULL OR allocation_volume_m3 >= 0) AND
        (allocation_percent IS NULL OR allocation_percent BETWEEN 0 AND 100)
    )
);

CREATE TABLE IF NOT EXISTS etms.shipment_stops (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    shipment_id uuid NOT NULL REFERENCES etms.shipments(id) ON DELETE CASCADE,
    sequence_no integer NOT NULL,
    stop_type varchar(30) NOT NULL,
    location_id uuid REFERENCES etms.locations(id),
    address_snapshot_id uuid NOT NULL REFERENCES etms.address_snapshots(id),
    party_snapshot_id uuid REFERENCES etms.party_snapshots(id),
    planned_arrival_at timestamptz,
    planned_departure_at timestamptz,
    earliest_arrival_at timestamptz,
    latest_arrival_at timestamptz,
    service_duration_minutes integer NOT NULL DEFAULT 0,
    distance_from_previous_km numeric(16,3),
    status varchar(20) NOT NULL DEFAULT 'PLANNED',
    instructions text,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (shipment_id, sequence_no),
    CONSTRAINT ck_shipment_stops_sequence CHECK (sequence_no > 0),
    CONSTRAINT ck_shipment_stops_plan CHECK (planned_departure_at IS NULL OR planned_arrival_at IS NULL OR planned_departure_at >= planned_arrival_at),
    CONSTRAINT ck_shipment_stops_window CHECK (latest_arrival_at IS NULL OR earliest_arrival_at IS NULL OR latest_arrival_at >= earliest_arrival_at),
    CONSTRAINT ck_shipment_stops_duration CHECK (service_duration_minutes >= 0)
);

CREATE TABLE IF NOT EXISTS etms.shipment_stop_orders (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    shipment_stop_id uuid NOT NULL REFERENCES etms.shipment_stops(id) ON DELETE CASCADE,
    order_id uuid NOT NULL REFERENCES etms.transport_orders(id),
    order_stop_id uuid REFERENCES etms.transport_order_stops(id),
    activity_type varchar(20) NOT NULL,
    planned_quantity numeric(20,6),
    uom_code varchar(20) REFERENCES etms.units_of_measure(uom_code),
    CONSTRAINT ck_shipment_stop_orders_activity CHECK (activity_type IN ('LOAD','UNLOAD','TRANSFER','INSPECT','CUSTOMS','RETURN')),
    CONSTRAINT ck_shipment_stop_orders_qty CHECK (planned_quantity IS NULL OR planned_quantity >= 0)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_shipment_stop_orders_activity
    ON etms.shipment_stop_orders (
        shipment_stop_id, order_id,
        COALESCE(order_stop_id, '00000000-0000-0000-0000-000000000000'::uuid),
        activity_type
    );

CREATE TABLE IF NOT EXISTS etms.shipment_legs (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    shipment_id uuid NOT NULL REFERENCES etms.shipments(id) ON DELETE CASCADE,
    leg_no integer NOT NULL,
    from_stop_id uuid NOT NULL REFERENCES etms.shipment_stops(id),
    to_stop_id uuid NOT NULL REFERENCES etms.shipment_stops(id),
    mode_code varchar(20) NOT NULL REFERENCES etms.transport_modes(mode_code),
    service_level_id uuid REFERENCES etms.service_levels(id),
    route_id uuid REFERENCES etms.routes(id),
    planned_departure_at timestamptz,
    planned_arrival_at timestamptz,
    planned_distance_km numeric(16,3),
    planned_duration_minutes integer,
    carrier_id uuid REFERENCES etms.business_partners(id),
    subcontract_carrier_id uuid REFERENCES etms.business_partners(id),
    equipment_type_id uuid REFERENCES etms.equipment_types(id),
    booking_required boolean NOT NULL DEFAULT false,
    status varchar(20) NOT NULL DEFAULT 'PLANNED',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (shipment_id, leg_no),
    CONSTRAINT ck_shipment_legs_no CHECK (leg_no > 0),
    CONSTRAINT ck_shipment_legs_stops CHECK (from_stop_id <> to_stop_id),
    CONSTRAINT ck_shipment_legs_dates CHECK (planned_arrival_at IS NULL OR planned_departure_at IS NULL OR planned_arrival_at >= planned_departure_at),
    CONSTRAINT ck_shipment_legs_distance CHECK (planned_distance_km IS NULL OR planned_distance_km >= 0)
);

CREATE TABLE IF NOT EXISTS etms.shipment_leg_allocations (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    shipment_leg_id uuid NOT NULL REFERENCES etms.shipment_legs(id) ON DELETE CASCADE,
    order_line_id uuid NOT NULL REFERENCES etms.transport_order_lines(id),
    allocated_quantity numeric(20,6),
    quantity_uom_code varchar(20) REFERENCES etms.units_of_measure(uom_code),
    allocated_weight_kg numeric(20,6),
    allocated_volume_m3 numeric(20,6),
    handling_unit_id uuid REFERENCES etms.handling_units(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_leg_allocations_values CHECK (
        (allocated_quantity IS NULL OR allocated_quantity >= 0) AND
        (allocated_weight_kg IS NULL OR allocated_weight_kg >= 0) AND
        (allocated_volume_m3 IS NULL OR allocated_volume_m3 >= 0)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_shipment_leg_allocations_scope
    ON etms.shipment_leg_allocations (
        shipment_leg_id, order_line_id,
        COALESCE(handling_unit_id, '00000000-0000-0000-0000-000000000000'::uuid)
    );

CREATE TABLE IF NOT EXISTS etms.shipment_services (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    shipment_id uuid NOT NULL REFERENCES etms.shipments(id) ON DELETE CASCADE,
    shipment_stop_id uuid REFERENCES etms.shipment_stops(id) ON DELETE CASCADE,
    service_code varchar(80) NOT NULL,
    provider_partner_id uuid REFERENCES etms.business_partners(id),
    planned_start_at timestamptz,
    planned_end_at timestamptz,
    status varchar(20) NOT NULL DEFAULT 'PLANNED',
    instructions text,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS etms.shipment_milestones (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    shipment_id uuid NOT NULL REFERENCES etms.shipments(id) ON DELETE CASCADE,
    shipment_leg_id uuid REFERENCES etms.shipment_legs(id) ON DELETE CASCADE,
    shipment_stop_id uuid REFERENCES etms.shipment_stops(id) ON DELETE CASCADE,
    milestone_code varchar(80) NOT NULL,
    planned_at timestamptz,
    expected_at timestamptz,
    actual_at timestamptz,
    status varchar(20) NOT NULL DEFAULT 'PENDING',
    source_event_id uuid,
    is_customer_visible boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_shipment_milestones_scope
    ON etms.shipment_milestones (
        shipment_id,
        COALESCE(shipment_leg_id, '00000000-0000-0000-0000-000000000000'::uuid),
        COALESCE(shipment_stop_id, '00000000-0000-0000-0000-000000000000'::uuid),
        milestone_code
    );

CREATE TABLE IF NOT EXISTS etms.transport_runs (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    run_no varchar(100) NOT NULL,
    run_type varchar(30) NOT NULL DEFAULT 'LINEHAUL',
    planning_scenario_id uuid REFERENCES etms.planning_scenarios(id),
    organization_id uuid NOT NULL REFERENCES etms.organizations(id),
    service_date date NOT NULL,
    mode_code varchar(20) NOT NULL REFERENCES etms.transport_modes(mode_code),
    start_location_id uuid REFERENCES etms.locations(id),
    end_location_id uuid REFERENCES etms.locations(id),
    planned_start_at timestamptz,
    planned_end_at timestamptz,
    planned_distance_km numeric(16,3),
    planned_drive_minutes integer,
    planned_duty_minutes integer,
    total_weight_kg numeric(20,6) NOT NULL DEFAULT 0,
    total_volume_m3 numeric(20,6) NOT NULL DEFAULT 0,
    total_pallets numeric(20,3) NOT NULL DEFAULT 0,
    equipment_type_id uuid REFERENCES etms.equipment_types(id),
    capacity_weight_kg numeric(20,6),
    capacity_volume_m3 numeric(20,6),
    status varchar(30) NOT NULL DEFAULT 'PLANNED',
    assignment_status varchar(20) NOT NULL DEFAULT 'UNASSIGNED',
    dispatch_status varchar(20) NOT NULL DEFAULT 'NOT_DISPATCHED',
    row_version bigint NOT NULL DEFAULT 1,
    created_by uuid REFERENCES etms.users(id),
    updated_by uuid REFERENCES etms.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    UNIQUE (tenant_id, run_no),
    CONSTRAINT ck_transport_runs_type CHECK (run_type IN ('PICKUP','DELIVERY','LINEHAUL','MILK_RUN','MULTI_DROP','SHUTTLE','RELAY','BACKHAUL','REPOSITION','INTERMODAL')),
    CONSTRAINT ck_transport_runs_dates CHECK (planned_end_at IS NULL OR planned_start_at IS NULL OR planned_end_at >= planned_start_at),
    CONSTRAINT ck_transport_runs_values CHECK (total_weight_kg >= 0 AND total_volume_m3 >= 0 AND total_pallets >= 0 AND (planned_distance_km IS NULL OR planned_distance_km >= 0))
);

CREATE TABLE IF NOT EXISTS etms.run_legs (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    run_id uuid NOT NULL REFERENCES etms.transport_runs(id) ON DELETE CASCADE,
    sequence_no integer NOT NULL,
    shipment_leg_id uuid REFERENCES etms.shipment_legs(id),
    from_location_id uuid REFERENCES etms.locations(id),
    to_location_id uuid REFERENCES etms.locations(id),
    planned_departure_at timestamptz,
    planned_arrival_at timestamptz,
    planned_distance_km numeric(16,3),
    status varchar(20) NOT NULL DEFAULT 'PLANNED',
    UNIQUE (run_id, sequence_no),
    CONSTRAINT ck_run_legs_sequence CHECK (sequence_no > 0),
    CONSTRAINT ck_run_legs_locations CHECK (from_location_id IS NULL OR to_location_id IS NULL OR from_location_id <> to_location_id)
);

CREATE TABLE IF NOT EXISTS etms.run_leg_allocations (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    run_leg_id uuid NOT NULL REFERENCES etms.run_legs(id) ON DELETE CASCADE,
    shipment_leg_allocation_id uuid REFERENCES etms.shipment_leg_allocations(id),
    order_line_id uuid NOT NULL REFERENCES etms.transport_order_lines(id),
    handling_unit_id uuid REFERENCES etms.handling_units(id),
    allocated_quantity numeric(20,6),
    quantity_uom_code varchar(20) REFERENCES etms.units_of_measure(uom_code),
    allocated_weight_kg numeric(20,6),
    allocated_volume_m3 numeric(20,6),
    allocation_status varchar(20) NOT NULL DEFAULT 'PLANNED',
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_run_leg_allocation_values CHECK (
        (allocated_quantity IS NULL OR allocated_quantity >= 0) AND
        (allocated_weight_kg IS NULL OR allocated_weight_kg >= 0) AND
        (allocated_volume_m3 IS NULL OR allocated_volume_m3 >= 0)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_run_leg_allocations_scope
    ON etms.run_leg_allocations (
        run_leg_id, order_line_id,
        COALESCE(handling_unit_id, '00000000-0000-0000-0000-000000000000'::uuid)
    );

CREATE TABLE IF NOT EXISTS etms.run_stops (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    run_id uuid NOT NULL REFERENCES etms.transport_runs(id) ON DELETE CASCADE,
    sequence_no integer NOT NULL,
    stop_type varchar(30) NOT NULL,
    location_id uuid REFERENCES etms.locations(id),
    address_snapshot_id uuid REFERENCES etms.address_snapshots(id),
    planned_arrival_at timestamptz,
    planned_departure_at timestamptz,
    service_duration_minutes integer NOT NULL DEFAULT 0,
    distance_from_previous_km numeric(16,3),
    status varchar(20) NOT NULL DEFAULT 'PLANNED',
    instructions text,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (run_id, sequence_no),
    CONSTRAINT ck_run_stops_sequence CHECK (sequence_no > 0),
    CONSTRAINT ck_run_stops_dates CHECK (planned_departure_at IS NULL OR planned_arrival_at IS NULL OR planned_departure_at >= planned_arrival_at),
    CONSTRAINT ck_run_stops_duration CHECK (service_duration_minutes >= 0)
);

CREATE TABLE IF NOT EXISTS etms.run_stop_activities (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    run_stop_id uuid NOT NULL REFERENCES etms.run_stops(id) ON DELETE CASCADE,
    shipment_stop_id uuid REFERENCES etms.shipment_stops(id),
    order_id uuid REFERENCES etms.transport_orders(id),
    activity_type varchar(30) NOT NULL,
    sequence_no integer NOT NULL,
    planned_quantity numeric(20,6),
    uom_code varchar(20) REFERENCES etms.units_of_measure(uom_code),
    status varchar(20) NOT NULL DEFAULT 'PLANNED',
    instructions text,
    UNIQUE (run_stop_id, sequence_no),
    CONSTRAINT ck_run_stop_activities_sequence CHECK (sequence_no > 0),
    CONSTRAINT ck_run_stop_activities_type CHECK (activity_type IN ('CHECK_IN','LOAD','UNLOAD','TRANSFER','INSPECT','DOCUMENT','REFUEL','BREAK','CHECK_OUT','CUSTOMS','SEAL','UNSEAL'))
);

CREATE TABLE IF NOT EXISTS etms.capacity_reservations (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    run_id uuid NOT NULL REFERENCES etms.transport_runs(id) ON DELETE CASCADE,
    shipment_id uuid REFERENCES etms.shipments(id),
    order_id uuid REFERENCES etms.transport_orders(id),
    reserved_weight_kg numeric(20,6) NOT NULL DEFAULT 0,
    reserved_volume_m3 numeric(20,6) NOT NULL DEFAULT 0,
    reserved_pallets numeric(20,3) NOT NULL DEFAULT 0,
    status varchar(20) NOT NULL DEFAULT 'RESERVED',
    expires_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_capacity_reservation_entity CHECK ((shipment_id IS NOT NULL)::int + (order_id IS NOT NULL)::int = 1),
    CONSTRAINT ck_capacity_reservation_values CHECK (reserved_weight_kg >= 0 AND reserved_volume_m3 >= 0 AND reserved_pallets >= 0)
);

CREATE TABLE IF NOT EXISTS etms.run_carrier_assignments (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    run_id uuid NOT NULL REFERENCES etms.transport_runs(id) ON DELETE CASCADE,
    carrier_id uuid NOT NULL REFERENCES etms.business_partners(id),
    subcontract_carrier_id uuid REFERENCES etms.business_partners(id),
    assignment_role varchar(20) NOT NULL DEFAULT 'PRIMARY',
    valid_from timestamptz NOT NULL,
    valid_to timestamptz,
    status varchar(20) NOT NULL DEFAULT 'PROPOSED',
    source_type varchar(20) NOT NULL DEFAULT 'MANUAL',
    awarded_tender_id uuid,
    accepted_at timestamptz,
    rejected_at timestamptz,
    reason text,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_run_carrier_dates CHECK (valid_to IS NULL OR valid_to > valid_from),
    CONSTRAINT ck_run_carrier_role CHECK (assignment_role IN ('PRIMARY','SUBCONTRACTOR','BROKER'))
);

CREATE TABLE IF NOT EXISTS etms.run_driver_assignments (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    run_id uuid NOT NULL REFERENCES etms.transport_runs(id) ON DELETE CASCADE,
    driver_id uuid NOT NULL REFERENCES etms.drivers(id),
    assignment_role varchar(20) NOT NULL DEFAULT 'PRIMARY',
    valid_from timestamptz NOT NULL,
    valid_to timestamptz,
    status varchar(20) NOT NULL DEFAULT 'ASSIGNED',
    assigned_by uuid REFERENCES etms.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_run_driver_dates CHECK (valid_to IS NULL OR valid_to > valid_from),
    CONSTRAINT ck_run_driver_role CHECK (assignment_role IN ('PRIMARY','CO_DRIVER','RELIEF'))
);

CREATE TABLE IF NOT EXISTS etms.run_equipment_assignments (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    run_id uuid NOT NULL REFERENCES etms.transport_runs(id) ON DELETE CASCADE,
    equipment_kind varchar(20) NOT NULL,
    equipment_id uuid NOT NULL,
    assignment_role varchar(20) NOT NULL DEFAULT 'PRIMARY',
    valid_from timestamptz NOT NULL,
    valid_to timestamptz,
    status varchar(20) NOT NULL DEFAULT 'ASSIGNED',
    assigned_by uuid REFERENCES etms.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_run_equipment_kind CHECK (equipment_kind IN ('VEHICLE','TRAILER','CONTAINER')),
    CONSTRAINT ck_run_equipment_dates CHECK (valid_to IS NULL OR valid_to > valid_from)
);

CREATE TABLE IF NOT EXISTS etms.assignment_status_history (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    assignment_type varchar(20) NOT NULL,
    assignment_id uuid NOT NULL,
    from_status varchar(20),
    to_status varchar(20) NOT NULL,
    reason text,
    changed_by uuid REFERENCES etms.users(id),
    occurred_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_assignment_history_type CHECK (assignment_type IN ('CARRIER','DRIVER','EQUIPMENT'))
);

CREATE TABLE IF NOT EXISTS etms.route_plan_versions (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    run_id uuid NOT NULL REFERENCES etms.transport_runs(id) ON DELETE CASCADE,
    version_no integer NOT NULL,
    route_source varchar(30) NOT NULL,
    total_distance_km numeric(16,3),
    total_duration_minutes integer,
    geometry_geojson jsonb,
    is_current boolean NOT NULL DEFAULT false,
    reason text,
    created_by uuid REFERENCES etms.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (run_id, version_no),
    CONSTRAINT ck_route_plan_version CHECK (version_no > 0)
);

CREATE TABLE IF NOT EXISTS etms.route_plan_segments (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    route_plan_version_id uuid NOT NULL REFERENCES etms.route_plan_versions(id) ON DELETE CASCADE,
    sequence_no integer NOT NULL,
    from_run_stop_id uuid REFERENCES etms.run_stops(id),
    to_run_stop_id uuid REFERENCES etms.run_stops(id),
    distance_km numeric(16,3),
    duration_minutes integer,
    road_class varchar(50),
    toll_amount numeric(20,4),
    currency_code char(3) REFERENCES etms.currencies(currency_code),
    geometry_geojson jsonb,
    restrictions jsonb NOT NULL DEFAULT '{}'::jsonb,
    UNIQUE (route_plan_version_id, sequence_no),
    CONSTRAINT ck_route_plan_segment_sequence CHECK (sequence_no > 0)
);

CREATE TABLE IF NOT EXISTS etms.tenders (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    tender_no varchar(100) NOT NULL,
    tender_type varchar(30) NOT NULL DEFAULT 'SEQUENTIAL',
    shipment_id uuid REFERENCES etms.shipments(id),
    run_id uuid REFERENCES etms.transport_runs(id),
    contract_version_id uuid REFERENCES etms.rate_contract_versions(id),
    currency_code char(3) REFERENCES etms.currencies(currency_code),
    target_amount numeric(20,4),
    response_deadline timestamptz NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    awarded_carrier_id uuid REFERENCES etms.business_partners(id),
    awarded_amount numeric(20,4),
    awarded_at timestamptz,
    created_by uuid REFERENCES etms.users(id),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, tender_no),
    CONSTRAINT ck_tenders_entity CHECK ((shipment_id IS NOT NULL)::int + (run_id IS NOT NULL)::int = 1),
    CONSTRAINT ck_tenders_type CHECK (tender_type IN ('SEQUENTIAL','BROADCAST','AUCTION','SPOT','AUTO_ACCEPT')),
    CONSTRAINT ck_tenders_amount CHECK ((target_amount IS NULL OR target_amount >= 0) AND (awarded_amount IS NULL OR awarded_amount >= 0))
);

DO $block$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'etms.run_carrier_assignments'::regclass
          AND conname = 'fk_run_carrier_awarded_tender'
    ) THEN
        ALTER TABLE etms.run_carrier_assignments
            ADD CONSTRAINT fk_run_carrier_awarded_tender FOREIGN KEY (awarded_tender_id)
            REFERENCES etms.tenders(id) ON DELETE SET NULL;
    END IF;
END;
$block$;

CREATE TABLE IF NOT EXISTS etms.tender_rounds (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tender_id uuid NOT NULL REFERENCES etms.tenders(id) ON DELETE CASCADE,
    round_no integer NOT NULL,
    starts_at timestamptz NOT NULL,
    ends_at timestamptz NOT NULL,
    reserve_amount numeric(20,4),
    status varchar(20) NOT NULL DEFAULT 'PLANNED',
    UNIQUE (tender_id, round_no),
    CONSTRAINT ck_tender_round_no CHECK (round_no > 0),
    CONSTRAINT ck_tender_round_dates CHECK (ends_at > starts_at)
);

CREATE TABLE IF NOT EXISTS etms.tender_offers (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    tender_round_id uuid NOT NULL REFERENCES etms.tender_rounds(id) ON DELETE CASCADE,
    carrier_id uuid NOT NULL REFERENCES etms.business_partners(id),
    offered_at timestamptz NOT NULL DEFAULT now(),
    offer_expires_at timestamptz NOT NULL,
    offered_amount numeric(20,4),
    currency_code char(3) REFERENCES etms.currencies(currency_code),
    status varchar(20) NOT NULL DEFAULT 'SENT',
    delivery_channel varchar(20) NOT NULL DEFAULT 'PORTAL',
    external_reference varchar(200),
    UNIQUE (tender_round_id, carrier_id),
    CONSTRAINT ck_tender_offer_amount CHECK (offered_amount IS NULL OR offered_amount >= 0)
);

CREATE TABLE IF NOT EXISTS etms.tender_responses (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tender_offer_id uuid NOT NULL REFERENCES etms.tender_offers(id) ON DELETE CASCADE,
    response_type varchar(20) NOT NULL,
    quoted_amount numeric(20,4),
    currency_code char(3) REFERENCES etms.currencies(currency_code),
    available_equipment_count integer,
    proposed_pickup_at timestamptz,
    proposed_delivery_at timestamptz,
    conditions text,
    decline_reason_code varchar(80),
    responded_at timestamptz NOT NULL DEFAULT now(),
    created_by_user_id uuid REFERENCES etms.users(id),
    CONSTRAINT ck_tender_response_type CHECK (response_type IN ('ACCEPT','DECLINE','COUNTER','EXPIRE')),
    CONSTRAINT ck_tender_response_amount CHECK (quoted_amount IS NULL OR quoted_amount >= 0)
);

CREATE TABLE IF NOT EXISTS etms.tender_awards (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    tender_id uuid NOT NULL REFERENCES etms.tenders(id) ON DELETE CASCADE,
    tender_response_id uuid REFERENCES etms.tender_responses(id),
    carrier_id uuid NOT NULL REFERENCES etms.business_partners(id),
    award_amount numeric(20,4) NOT NULL,
    currency_code char(3) NOT NULL REFERENCES etms.currencies(currency_code),
    awarded_by uuid REFERENCES etms.users(id),
    awarded_at timestamptz NOT NULL DEFAULT now(),
    status varchar(20) NOT NULL DEFAULT 'AWARDED',
    withdrawn_at timestamptz,
    withdrawal_reason text,
    CONSTRAINT ck_tender_award_amount CHECK (award_amount >= 0)
);

CREATE TABLE IF NOT EXISTS etms.dispatch_orders (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    dispatch_no varchar(100) NOT NULL,
    revision_no integer NOT NULL DEFAULT 1,
    carrier_id uuid NOT NULL REFERENCES etms.business_partners(id),
    run_id uuid NOT NULL REFERENCES etms.transport_runs(id),
    tender_award_id uuid REFERENCES etms.tender_awards(id),
    issued_at timestamptz,
    effective_at timestamptz,
    expires_at timestamptz,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    instructions text,
    terms_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
    accepted_at timestamptz,
    rejected_at timestamptz,
    rejection_reason text,
    cancelled_at timestamptz,
    cancellation_reason text,
    row_version bigint NOT NULL DEFAULT 1,
    created_by uuid REFERENCES etms.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, dispatch_no, revision_no),
    CONSTRAINT ck_dispatch_revision CHECK (revision_no > 0),
    CONSTRAINT ck_dispatch_dates CHECK (expires_at IS NULL OR effective_at IS NULL OR expires_at > effective_at)
);

CREATE TABLE IF NOT EXISTS etms.dispatch_instructions (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    dispatch_order_id uuid NOT NULL REFERENCES etms.dispatch_orders(id) ON DELETE CASCADE,
    sequence_no integer NOT NULL,
    instruction_type varchar(50) NOT NULL,
    instruction_text text NOT NULL,
    requires_acknowledgement boolean NOT NULL DEFAULT false,
    due_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (dispatch_order_id, sequence_no)
);

CREATE TABLE IF NOT EXISTS etms.dispatch_acknowledgements (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    dispatch_order_id uuid NOT NULL REFERENCES etms.dispatch_orders(id) ON DELETE CASCADE,
    instruction_id uuid REFERENCES etms.dispatch_instructions(id),
    acknowledged_by_type varchar(20) NOT NULL,
    acknowledged_by_id uuid,
    acknowledgement_type varchar(20) NOT NULL,
    comments text,
    ip_address inet,
    acknowledged_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_dispatch_ack_type CHECK (acknowledgement_type IN ('RECEIVED','ACCEPTED','REJECTED','COMPLETED'))
);

CREATE TABLE IF NOT EXISTS etms.dispatch_status_history (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    dispatch_order_id uuid NOT NULL REFERENCES etms.dispatch_orders(id) ON DELETE CASCADE,
    from_status varchar(20),
    to_status varchar(20) NOT NULL,
    reason text,
    changed_by uuid REFERENCES etms.users(id),
    occurred_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS etms.dock_appointments (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    appointment_no varchar(100) NOT NULL,
    location_id uuid NOT NULL REFERENCES etms.locations(id),
    dock_id uuid REFERENCES etms.location_docks(id),
    order_stop_id uuid REFERENCES etms.transport_order_stops(id),
    shipment_stop_id uuid REFERENCES etms.shipment_stops(id),
    run_stop_id uuid REFERENCES etms.run_stops(id),
    appointment_type varchar(20) NOT NULL,
    scheduled_start_at timestamptz NOT NULL,
    scheduled_end_at timestamptz NOT NULL,
    carrier_id uuid REFERENCES etms.business_partners(id),
    vehicle_id uuid REFERENCES etms.vehicles(id),
    driver_id uuid REFERENCES etms.drivers(id),
    confirmation_code varchar(100),
    status varchar(20) NOT NULL DEFAULT 'REQUESTED',
    checked_in_at timestamptz,
    checked_out_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, appointment_no),
    CONSTRAINT ck_dock_appointment_entity CHECK ((order_stop_id IS NOT NULL)::int + (shipment_stop_id IS NOT NULL)::int + (run_stop_id IS NOT NULL)::int >= 1),
    CONSTRAINT ck_dock_appointment_dates CHECK (scheduled_end_at > scheduled_start_at)
);

CREATE TABLE IF NOT EXISTS etms.dock_appointment_history (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    appointment_id uuid NOT NULL REFERENCES etms.dock_appointments(id) ON DELETE CASCADE,
    from_status varchar(20),
    to_status varchar(20) NOT NULL,
    previous_start_at timestamptz,
    new_start_at timestamptz,
    reason text,
    changed_by uuid REFERENCES etms.users(id),
    occurred_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS etms.manifests (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    manifest_no varchar(100) NOT NULL,
    manifest_type varchar(30) NOT NULL,
    run_id uuid REFERENCES etms.transport_runs(id),
    shipment_id uuid REFERENCES etms.shipments(id),
    carrier_id uuid REFERENCES etms.business_partners(id),
    issued_at timestamptz,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    total_items integer NOT NULL DEFAULT 0,
    total_weight_kg numeric(20,6) NOT NULL DEFAULT 0,
    file_id uuid REFERENCES etms.files(id),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, manifest_no),
    CONSTRAINT ck_manifest_entity CHECK ((run_id IS NOT NULL)::int + (shipment_id IS NOT NULL)::int >= 1),
    CONSTRAINT ck_manifest_totals CHECK (total_items >= 0 AND total_weight_kg >= 0)
);

CREATE TABLE IF NOT EXISTS etms.manifest_items (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    manifest_id uuid NOT NULL REFERENCES etms.manifests(id) ON DELETE CASCADE,
    sequence_no integer NOT NULL,
    order_id uuid REFERENCES etms.transport_orders(id),
    shipment_id uuid REFERENCES etms.shipments(id),
    handling_unit_id uuid REFERENCES etms.handling_units(id),
    description varchar(500),
    quantity numeric(20,6),
    uom_code varchar(20) REFERENCES etms.units_of_measure(uom_code),
    gross_weight_kg numeric(20,6),
    status varchar(20) NOT NULL DEFAULT 'LISTED',
    UNIQUE (manifest_id, sequence_no),
    CONSTRAINT ck_manifest_item_sequence CHECK (sequence_no > 0)
);
