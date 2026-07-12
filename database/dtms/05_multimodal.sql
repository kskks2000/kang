-- DTMS scheduled and multimodal transport, bookings, containers, trade/customs documents.

CREATE TABLE IF NOT EXISTS dtms.transport_schedules (
    id uuid PRIMARY KEY DEFAULT dtms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dtms.tenants(id),
    schedule_code varchar(100) NOT NULL,
    mode_code varchar(20) NOT NULL REFERENCES dtms.transport_modes(mode_code),
    carrier_id uuid NOT NULL REFERENCES dtms.business_partners(id),
    service_name varchar(200),
    voyage_flight_train_no varchar(100),
    origin_location_id uuid NOT NULL REFERENCES dtms.locations(id),
    destination_location_id uuid NOT NULL REFERENCES dtms.locations(id),
    scheduled_departure_at timestamptz NOT NULL,
    scheduled_arrival_at timestamptz NOT NULL,
    estimated_departure_at timestamptz,
    estimated_arrival_at timestamptz,
    capacity_weight_kg numeric(20,6),
    capacity_volume_m3 numeric(20,6),
    status varchar(20) NOT NULL DEFAULT 'SCHEDULED',
    external_schedule_id varchar(200),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, carrier_id, schedule_code, scheduled_departure_at),
    CONSTRAINT ck_transport_schedule_locations CHECK (origin_location_id <> destination_location_id),
    CONSTRAINT ck_transport_schedule_dates CHECK (scheduled_arrival_at > scheduled_departure_at),
    CONSTRAINT ck_transport_schedule_capacity CHECK ((capacity_weight_kg IS NULL OR capacity_weight_kg >= 0) AND (capacity_volume_m3 IS NULL OR capacity_volume_m3 >= 0))
);

CREATE TABLE IF NOT EXISTS dtms.transport_schedule_calls (
    id uuid PRIMARY KEY DEFAULT dtms.generate_uuid(),
    schedule_id uuid NOT NULL REFERENCES dtms.transport_schedules(id) ON DELETE CASCADE,
    sequence_no integer NOT NULL,
    location_id uuid NOT NULL REFERENCES dtms.locations(id),
    scheduled_arrival_at timestamptz,
    scheduled_departure_at timestamptz,
    estimated_arrival_at timestamptz,
    estimated_departure_at timestamptz,
    actual_arrival_at timestamptz,
    actual_departure_at timestamptz,
    terminal_name varchar(200),
    status varchar(20) NOT NULL DEFAULT 'SCHEDULED',
    UNIQUE (schedule_id, sequence_no),
    CONSTRAINT ck_schedule_calls_sequence CHECK (sequence_no > 0),
    CONSTRAINT ck_schedule_calls_planned CHECK (scheduled_departure_at IS NULL OR scheduled_arrival_at IS NULL OR scheduled_departure_at >= scheduled_arrival_at)
);

CREATE TABLE IF NOT EXISTS dtms.carrier_bookings (
    id uuid PRIMARY KEY DEFAULT dtms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dtms.tenants(id),
    booking_no varchar(120) NOT NULL,
    carrier_booking_reference varchar(200),
    carrier_id uuid NOT NULL REFERENCES dtms.business_partners(id),
    schedule_id uuid REFERENCES dtms.transport_schedules(id),
    shipment_leg_id uuid REFERENCES dtms.shipment_legs(id),
    mode_code varchar(20) NOT NULL REFERENCES dtms.transport_modes(mode_code),
    booking_type varchar(30) NOT NULL,
    requested_at timestamptz NOT NULL DEFAULT now(),
    confirmed_at timestamptz,
    cancelled_at timestamptz,
    status varchar(20) NOT NULL DEFAULT 'REQUESTED',
    cutoff_at timestamptz,
    document_cutoff_at timestamptz,
    vgm_cutoff_at timestamptz,
    booked_weight_kg numeric(20,6),
    booked_volume_m3 numeric(20,6),
    currency_code char(3) REFERENCES dtms.currencies(currency_code),
    booked_amount numeric(20,4),
    terms jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, booking_no),
    UNIQUE (tenant_id, carrier_id, carrier_booking_reference),
    CONSTRAINT ck_carrier_booking_values CHECK ((booked_weight_kg IS NULL OR booked_weight_kg >= 0) AND (booked_volume_m3 IS NULL OR booked_volume_m3 >= 0) AND (booked_amount IS NULL OR booked_amount >= 0))
);

CREATE TABLE IF NOT EXISTS dtms.carrier_booking_items (
    id uuid PRIMARY KEY DEFAULT dtms.generate_uuid(),
    booking_id uuid NOT NULL REFERENCES dtms.carrier_bookings(id) ON DELETE CASCADE,
    sequence_no integer NOT NULL,
    shipment_id uuid REFERENCES dtms.shipments(id),
    container_id uuid REFERENCES dtms.containers(id),
    equipment_type_id uuid REFERENCES dtms.equipment_types(id),
    equipment_count integer NOT NULL DEFAULT 1,
    weight_kg numeric(20,6),
    volume_m3 numeric(20,6),
    commodity_description varchar(500),
    dangerous_goods boolean NOT NULL DEFAULT false,
    status varchar(20) NOT NULL DEFAULT 'BOOKED',
    UNIQUE (booking_id, sequence_no),
    CONSTRAINT ck_booking_items_sequence CHECK (sequence_no > 0),
    CONSTRAINT ck_booking_items_count CHECK (equipment_count > 0)
);

CREATE TABLE IF NOT EXISTS dtms.container_seals (
    id uuid PRIMARY KEY DEFAULT dtms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dtms.tenants(id),
    container_id uuid NOT NULL REFERENCES dtms.containers(id),
    shipment_id uuid REFERENCES dtms.shipments(id),
    seal_no varchar(100) NOT NULL,
    seal_type varchar(30) NOT NULL DEFAULT 'CARRIER',
    applied_at timestamptz,
    applied_location_id uuid REFERENCES dtms.locations(id),
    applied_by varchar(200),
    removed_at timestamptz,
    removed_location_id uuid REFERENCES dtms.locations(id),
    removal_reason text,
    status varchar(20) NOT NULL DEFAULT 'APPLIED',
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, seal_no),
    CONSTRAINT ck_container_seals_dates CHECK (removed_at IS NULL OR applied_at IS NULL OR removed_at >= applied_at)
);

CREATE TABLE IF NOT EXISTS dtms.container_events (
    id uuid PRIMARY KEY DEFAULT dtms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dtms.tenants(id),
    container_id uuid NOT NULL REFERENCES dtms.containers(id),
    shipment_id uuid REFERENCES dtms.shipments(id),
    booking_id uuid REFERENCES dtms.carrier_bookings(id),
    event_type varchar(50) NOT NULL,
    location_id uuid REFERENCES dtms.locations(id),
    occurred_at timestamptz NOT NULL,
    received_at timestamptz NOT NULL DEFAULT now(),
    source_system_id uuid REFERENCES dtms.external_systems(id),
    external_event_id varchar(300),
    status_detail varchar(300),
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    UNIQUE (source_system_id, external_event_id)
);

CREATE TABLE IF NOT EXISTS dtms.container_load_items (
    id uuid PRIMARY KEY DEFAULT dtms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dtms.tenants(id),
    container_id uuid NOT NULL REFERENCES dtms.containers(id),
    shipment_id uuid NOT NULL REFERENCES dtms.shipments(id),
    order_line_id uuid REFERENCES dtms.transport_order_lines(id),
    handling_unit_id uuid REFERENCES dtms.handling_units(id),
    load_shipment_stop_id uuid REFERENCES dtms.shipment_stops(id),
    unload_shipment_stop_id uuid REFERENCES dtms.shipment_stops(id),
    quantity numeric(20,6),
    quantity_uom_code varchar(20) REFERENCES dtms.units_of_measure(uom_code),
    gross_weight_kg numeric(20,6),
    volume_m3 numeric(20,6),
    stowage_position varchar(80),
    load_status varchar(20) NOT NULL DEFAULT 'PLANNED',
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_container_load_item_source CHECK (order_line_id IS NOT NULL OR handling_unit_id IS NOT NULL),
    CONSTRAINT ck_container_load_item_stops CHECK (load_shipment_stop_id IS NULL OR unload_shipment_stop_id IS NULL OR load_shipment_stop_id <> unload_shipment_stop_id),
    CONSTRAINT ck_container_load_item_values CHECK ((quantity IS NULL OR quantity >= 0) AND (gross_weight_kg IS NULL OR gross_weight_kg >= 0) AND (volume_m3 IS NULL OR volume_m3 >= 0))
);

CREATE TABLE IF NOT EXISTS dtms.container_leg_assignments (
    id uuid PRIMARY KEY DEFAULT dtms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dtms.tenants(id),
    container_id uuid NOT NULL REFERENCES dtms.containers(id),
    shipment_leg_id uuid NOT NULL REFERENCES dtms.shipment_legs(id),
    run_leg_id uuid REFERENCES dtms.run_legs(id),
    booking_id uuid REFERENCES dtms.carrier_bookings(id),
    assignment_status varchar(20) NOT NULL DEFAULT 'PLANNED',
    loaded_at timestamptz,
    discharged_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_container_leg_assignment_dates CHECK (discharged_at IS NULL OR loaded_at IS NULL OR discharged_at >= loaded_at)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_container_leg_assignments_scope
    ON dtms.container_leg_assignments (
        container_id, shipment_leg_id,
        COALESCE(run_leg_id, '00000000-0000-0000-0000-000000000000'::uuid)
    );

CREATE TABLE IF NOT EXISTS dtms.equipment_interchanges (
    id uuid PRIMARY KEY DEFAULT dtms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dtms.tenants(id),
    interchange_no varchar(100) NOT NULL,
    container_id uuid REFERENCES dtms.containers(id),
    trailer_id uuid REFERENCES dtms.trailers(id),
    from_partner_id uuid REFERENCES dtms.business_partners(id),
    to_partner_id uuid REFERENCES dtms.business_partners(id),
    location_id uuid NOT NULL REFERENCES dtms.locations(id),
    interchange_type varchar(20) NOT NULL,
    condition_code varchar(30),
    damage_notes text,
    odometer_or_hours numeric(20,3),
    occurred_at timestamptz NOT NULL,
    signed_by_from varchar(200),
    signed_by_to varchar(200),
    file_id uuid REFERENCES dtms.files(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, interchange_no),
    CONSTRAINT ck_equipment_interchange_asset CHECK ((container_id IS NOT NULL)::int + (trailer_id IS NOT NULL)::int = 1),
    CONSTRAINT ck_equipment_interchange_parties CHECK (from_partner_id IS NOT NULL AND to_partner_id IS NOT NULL AND from_partner_id <> to_partner_id)
);

CREATE TABLE IF NOT EXISTS dtms.transport_documents (
    id uuid PRIMARY KEY DEFAULT dtms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dtms.tenants(id),
    document_no varchar(150) NOT NULL,
    document_type varchar(50) NOT NULL,
    revision_no integer NOT NULL DEFAULT 1,
    shipment_id uuid REFERENCES dtms.shipments(id),
    shipment_leg_id uuid REFERENCES dtms.shipment_legs(id),
    booking_id uuid REFERENCES dtms.carrier_bookings(id),
    issuer_partner_id uuid REFERENCES dtms.business_partners(id),
    carrier_id uuid REFERENCES dtms.business_partners(id),
    shipper_snapshot_id uuid REFERENCES dtms.party_snapshots(id),
    consignee_snapshot_id uuid REFERENCES dtms.party_snapshots(id),
    notify_party_snapshot_id uuid REFERENCES dtms.party_snapshots(id),
    issue_place varchar(200),
    issued_at timestamptz,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    original_count integer NOT NULL DEFAULT 0,
    copy_count integer NOT NULL DEFAULT 0,
    file_id uuid REFERENCES dtms.files(id),
    supersedes_document_id uuid REFERENCES dtms.transport_documents(id),
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, document_type, document_no, revision_no),
    CONSTRAINT ck_transport_document_revision CHECK (revision_no > 0),
    CONSTRAINT ck_transport_document_counts CHECK (original_count >= 0 AND copy_count >= 0),
    CONSTRAINT ck_transport_document_supersedes CHECK (supersedes_document_id IS NULL OR supersedes_document_id <> id)
);

CREATE TABLE IF NOT EXISTS dtms.transport_document_lines (
    id uuid PRIMARY KEY DEFAULT dtms.generate_uuid(),
    transport_document_id uuid NOT NULL REFERENCES dtms.transport_documents(id) ON DELETE CASCADE,
    line_no integer NOT NULL,
    order_line_id uuid REFERENCES dtms.transport_order_lines(id),
    marks_and_numbers varchar(500),
    package_count numeric(20,6),
    package_type varchar(50),
    goods_description text NOT NULL,
    hs_code varchar(20),
    gross_weight_kg numeric(20,6),
    volume_m3 numeric(20,6),
    dangerous_goods_detail jsonb NOT NULL DEFAULT '{}'::jsonb,
    UNIQUE (transport_document_id, line_no),
    CONSTRAINT ck_transport_document_line_no CHECK (line_no > 0)
);

CREATE TABLE IF NOT EXISTS dtms.customs_declarations (
    id uuid PRIMARY KEY DEFAULT dtms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dtms.tenants(id),
    declaration_no varchar(150) NOT NULL,
    declaration_type varchar(30) NOT NULL,
    shipment_id uuid NOT NULL REFERENCES dtms.shipments(id),
    customs_broker_id uuid REFERENCES dtms.business_partners(id),
    declarant_partner_id uuid REFERENCES dtms.business_partners(id),
    export_country_code char(2) REFERENCES dtms.countries(country_code),
    import_country_code char(2) REFERENCES dtms.countries(country_code),
    customs_office_code varchar(50),
    declaration_date date,
    clearance_status varchar(30) NOT NULL DEFAULT 'DRAFT',
    cleared_at timestamptz,
    total_customs_value numeric(20,4),
    currency_code char(3) REFERENCES dtms.currencies(currency_code),
    duty_amount numeric(20,4) NOT NULL DEFAULT 0,
    tax_amount numeric(20,4) NOT NULL DEFAULT 0,
    hold_reason text,
    external_reference varchar(200),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, declaration_no),
    CONSTRAINT ck_customs_declaration_countries CHECK (export_country_code IS NULL OR import_country_code IS NULL OR export_country_code <> import_country_code),
    CONSTRAINT ck_customs_declaration_amounts CHECK ((total_customs_value IS NULL OR total_customs_value >= 0) AND duty_amount >= 0 AND tax_amount >= 0)
);

CREATE TABLE IF NOT EXISTS dtms.customs_declaration_items (
    id uuid PRIMARY KEY DEFAULT dtms.generate_uuid(),
    customs_declaration_id uuid NOT NULL REFERENCES dtms.customs_declarations(id) ON DELETE CASCADE,
    line_no integer NOT NULL,
    order_line_id uuid REFERENCES dtms.transport_order_lines(id),
    hs_code varchar(20) NOT NULL,
    goods_description text NOT NULL,
    country_of_origin char(2) REFERENCES dtms.countries(country_code),
    quantity numeric(20,6),
    uom_code varchar(20) REFERENCES dtms.units_of_measure(uom_code),
    gross_weight_kg numeric(20,6),
    customs_value numeric(20,4) NOT NULL,
    duty_rate_percent numeric(9,6),
    duty_amount numeric(20,4) NOT NULL DEFAULT 0,
    tax_amount numeric(20,4) NOT NULL DEFAULT 0,
    preference_code varchar(50),
    UNIQUE (customs_declaration_id, line_no),
    CONSTRAINT ck_customs_item_line CHECK (line_no > 0),
    CONSTRAINT ck_customs_item_amounts CHECK (customs_value >= 0 AND duty_amount >= 0 AND tax_amount >= 0)
);

CREATE TABLE IF NOT EXISTS dtms.terminal_cutoffs (
    id uuid PRIMARY KEY DEFAULT dtms.generate_uuid(),
    schedule_call_id uuid NOT NULL REFERENCES dtms.transport_schedule_calls(id) ON DELETE CASCADE,
    cutoff_type varchar(30) NOT NULL,
    cutoff_at timestamptz NOT NULL,
    timezone varchar(100) NOT NULL,
    source_reference varchar(300),
    received_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (schedule_call_id, cutoff_type, cutoff_at)
);

CREATE TABLE IF NOT EXISTS dtms.verified_gross_masses (
    id uuid PRIMARY KEY DEFAULT dtms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dtms.tenants(id),
    container_id uuid NOT NULL REFERENCES dtms.containers(id),
    booking_id uuid REFERENCES dtms.carrier_bookings(id),
    vgm_weight_kg numeric(20,6) NOT NULL,
    weighing_method varchar(20) NOT NULL,
    weighing_date date NOT NULL,
    weighing_location varchar(300),
    responsible_party_id uuid REFERENCES dtms.business_partners(id),
    authorized_person varchar(200),
    certificate_no varchar(150),
    submitted_at timestamptz,
    accepted_at timestamptz,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    file_id uuid REFERENCES dtms.files(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_vgm_weight CHECK (vgm_weight_kg > 0)
);

CREATE TABLE IF NOT EXISTS dtms.transport_permits (
    id uuid PRIMARY KEY DEFAULT dtms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dtms.tenants(id),
    permit_no varchar(150) NOT NULL,
    permit_type varchar(50) NOT NULL,
    run_id uuid REFERENCES dtms.transport_runs(id),
    shipment_id uuid REFERENCES dtms.shipments(id),
    issuing_authority varchar(300) NOT NULL,
    jurisdiction varchar(200),
    valid_from timestamptz NOT NULL,
    valid_to timestamptz NOT NULL,
    route_restrictions jsonb NOT NULL DEFAULT '{}'::jsonb,
    weight_limit_kg numeric(20,6),
    dimension_limits jsonb NOT NULL DEFAULT '{}'::jsonb,
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    file_id uuid REFERENCES dtms.files(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, permit_no),
    CONSTRAINT ck_transport_permit_entity CHECK (run_id IS NOT NULL OR shipment_id IS NOT NULL),
    CONSTRAINT ck_transport_permit_dates CHECK (valid_to > valid_from)
);
