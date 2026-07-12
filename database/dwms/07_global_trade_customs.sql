-- DWMS enterprise WMS schema - global trade, customs declarations, and Korea UNI-PASS integration.
-- PostgreSQL 11 compatible. Applied after 00-06. External customs code formats are intentionally data-driven.

CREATE OR REPLACE FUNCTION dwms.block_immutable_change()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    IF current_setting('dwms.immutable_maintenance', true) = 'on' THEN
        IF TG_OP = 'DELETE' THEN
            RETURN OLD;
        END IF;
        RETURN NEW;
    END IF;
    RAISE EXCEPTION '% is append-only; create a reversal/new version instead of %', TG_TABLE_NAME, TG_OP
        USING ERRCODE = '55000';
END;
$function$;

CREATE OR REPLACE FUNCTION dwms.validate_tenant_owner_scope()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    v_row jsonb := to_jsonb(NEW);
    v_tenant_id uuid;
    v_owner_partner_id uuid;
    v_warehouse_id uuid;
    v_parent_tenant_id uuid;
BEGIN
    v_tenant_id := (v_row ->> 'tenant_id')::uuid;
    v_owner_partner_id := NULLIF(v_row ->> 'owner_partner_id', '')::uuid;
    v_warehouse_id := NULLIF(v_row ->> 'warehouse_id', '')::uuid;

    IF v_owner_partner_id IS NOT NULL THEN
        SELECT tenant_id INTO v_parent_tenant_id
          FROM dwms.business_partners
         WHERE id = v_owner_partner_id;
        IF NOT FOUND OR v_parent_tenant_id IS DISTINCT FROM v_tenant_id THEN
            RAISE EXCEPTION 'owner_partner_id % is outside tenant %', v_owner_partner_id, v_tenant_id
                USING ERRCODE = '23514';
        END IF;
    END IF;

    IF v_warehouse_id IS NOT NULL THEN
        SELECT tenant_id INTO v_parent_tenant_id
          FROM dwms.warehouses
         WHERE id = v_warehouse_id;
        IF NOT FOUND OR v_parent_tenant_id IS DISTINCT FROM v_tenant_id THEN
            RAISE EXCEPTION 'warehouse_id % is outside tenant %', v_warehouse_id, v_tenant_id
                USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE TABLE IF NOT EXISTS dwms.customs_code_sets (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    jurisdiction_country_code char(2) NOT NULL DEFAULT 'KR' REFERENCES dwms.countries(country_code),
    authority_code varchar(50) NOT NULL DEFAULT 'KCS',
    code_set_code varchar(100) NOT NULL,
    code_set_name varchar(250) NOT NULL,
    source_uri text,
    source_version varchar(100),
    valid_from date NOT NULL,
    valid_to date,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (jurisdiction_country_code, authority_code, code_set_code, valid_from),
    CONSTRAINT ck_dwms_customs_code_set_dates CHECK (valid_to IS NULL OR valid_to >= valid_from)
);

CREATE TABLE IF NOT EXISTS dwms.customs_codes (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    code_set_id uuid NOT NULL REFERENCES dwms.customs_code_sets(id) ON DELETE CASCADE,
    code_value varchar(150) NOT NULL,
    code_name_ko varchar(300),
    code_name_en varchar(300),
    parent_code_id uuid REFERENCES dwms.customs_codes(id),
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    valid_from date NOT NULL,
    valid_to date,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (code_set_id, code_value, valid_from),
    CONSTRAINT ck_dwms_customs_code_parent CHECK (parent_code_id IS NULL OR parent_code_id <> id),
    CONSTRAINT ck_dwms_customs_code_dates CHECK (valid_to IS NULL OR valid_to >= valid_from)
);

CREATE INDEX IF NOT EXISTS ix_dwms_customs_codes_lookup
    ON dwms.customs_codes (code_set_id, code_value, valid_from DESC);

CREATE TABLE IF NOT EXISTS dwms.vessels (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    vessel_name varchar(250) NOT NULL,
    imo_no varchar(50),
    call_sign varchar(80),
    mmsi_no varchar(50),
    flag_country_code char(2) REFERENCES dwms.countries(country_code),
    vessel_type_code varchar(80),
    gross_tonnage numeric(20,4),
    operator_partner_id uuid REFERENCES dwms.business_partners(id),
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    CONSTRAINT ck_dwms_vessel_tonnage CHECK (gross_tonnage IS NULL OR gross_tonnage >= 0),
    CONSTRAINT ck_dwms_vessel_status CHECK (status IN ('ACTIVE','INACTIVE','RETIRED','BLOCKED'))
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_dwms_vessel_imo
    ON dwms.vessels (tenant_id, imo_no)
    WHERE imo_no IS NOT NULL AND deleted_at IS NULL;

CREATE TABLE IF NOT EXISTS dwms.vessel_voyages (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    vessel_id uuid NOT NULL REFERENCES dwms.vessels(id),
    carrier_partner_id uuid REFERENCES dwms.business_partners(id),
    voyage_no varchar(100) NOT NULL,
    service_name varchar(150),
    origin_port_code varchar(10) REFERENCES dwms.ports(port_code),
    destination_port_code varchar(10) REFERENCES dwms.ports(port_code),
    scheduled_departure_at timestamptz,
    actual_departure_at timestamptz,
    scheduled_arrival_at timestamptz,
    actual_arrival_at timestamptz,
    status varchar(20) NOT NULL DEFAULT 'PLANNED',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, vessel_id, voyage_no, scheduled_departure_at),
    CONSTRAINT ck_dwms_voyage_status CHECK (status IN ('PLANNED','SAILED','ARRIVED','COMPLETED','CANCELLED')),
    CONSTRAINT ck_dwms_voyage_schedule CHECK (
        scheduled_arrival_at IS NULL OR scheduled_departure_at IS NULL OR scheduled_arrival_at >= scheduled_departure_at
    ),
    CONSTRAINT ck_dwms_voyage_actual CHECK (
        actual_arrival_at IS NULL OR actual_departure_at IS NULL OR actual_arrival_at >= actual_departure_at
    )
);

CREATE TABLE IF NOT EXISTS dwms.flights (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    carrier_partner_id uuid NOT NULL REFERENCES dwms.business_partners(id),
    flight_no varchar(100) NOT NULL,
    aircraft_registration_no varchar(100),
    aircraft_type_code varchar(80),
    origin_port_code varchar(10) REFERENCES dwms.ports(port_code),
    destination_port_code varchar(10) REFERENCES dwms.ports(port_code),
    scheduled_departure_at timestamptz NOT NULL,
    actual_departure_at timestamptz,
    scheduled_arrival_at timestamptz,
    actual_arrival_at timestamptz,
    status varchar(20) NOT NULL DEFAULT 'PLANNED',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, carrier_partner_id, flight_no, scheduled_departure_at),
    CONSTRAINT ck_dwms_flight_status CHECK (status IN ('PLANNED','DEPARTED','ARRIVED','COMPLETED','CANCELLED','DIVERTED')),
    CONSTRAINT ck_dwms_flight_schedule CHECK (
        scheduled_arrival_at IS NULL OR scheduled_arrival_at >= scheduled_departure_at
    ),
    CONSTRAINT ck_dwms_flight_actual CHECK (
        actual_arrival_at IS NULL OR actual_departure_at IS NULL OR actual_arrival_at >= actual_departure_at
    )
);

CREATE TABLE IF NOT EXISTS dwms.trade_shipments (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    owner_partner_id uuid NOT NULL REFERENCES dwms.business_partners(id),
    warehouse_id uuid REFERENCES dwms.warehouses(id),
    trade_shipment_no varchar(120) NOT NULL,
    direction varchar(20) NOT NULL,
    shipment_scope varchar(20) NOT NULL DEFAULT 'INTERNATIONAL',
    transport_mode_code varchar(20) REFERENCES dwms.transport_modes(mode_code),
    forwarding_partner_id uuid REFERENCES dwms.business_partners(id),
    carrier_partner_id uuid REFERENCES dwms.business_partners(id),
    origin_country_code char(2) REFERENCES dwms.countries(country_code),
    destination_country_code char(2) REFERENCES dwms.countries(country_code),
    port_of_loading_code varchar(10) REFERENCES dwms.ports(port_code),
    port_of_discharge_code varchar(10) REFERENCES dwms.ports(port_code),
    place_of_receipt varchar(300),
    place_of_delivery varchar(300),
    incoterm_code char(3) REFERENCES dwms.incoterms(incoterm_code),
    cargo_management_no_raw varchar(200),
    cargo_management_no_normalized varchar(200),
    booking_no varchar(150),
    planned_departure_at timestamptz,
    actual_departure_at timestamptz,
    planned_arrival_at timestamptz,
    actual_arrival_at timestamptz,
    package_count numeric(20,4),
    package_type_code varchar(50),
    gross_weight numeric(24,8),
    net_weight numeric(24,8),
    weight_uom_code varchar(20) REFERENCES dwms.units_of_measure(uom_code),
    volume_value numeric(24,9),
    volume_uom_code varchar(20) REFERENCES dwms.units_of_measure(uom_code),
    dangerous_goods boolean NOT NULL DEFAULT false,
    temperature_controlled boolean NOT NULL DEFAULT false,
    customs_status_code varchar(80),
    status varchar(30) NOT NULL DEFAULT 'PLANNED',
    source_system_id uuid REFERENCES dwms.external_systems(id),
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_by uuid REFERENCES dwms.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    closed_at timestamptz,
    UNIQUE (tenant_id, trade_shipment_no),
    UNIQUE (tenant_id, owner_partner_id, id),
    CONSTRAINT ck_dwms_trade_shipment_direction CHECK (direction IN ('IMPORT','EXPORT','TRANSIT','CROSS_TRADE')),
    CONSTRAINT ck_dwms_trade_shipment_scope CHECK (shipment_scope IN ('INTERNATIONAL','BONDED_TRANSFER','COASTAL','OTHER')),
    CONSTRAINT ck_dwms_trade_shipment_status CHECK (status IN (
        'PLANNED','BOOKED','IN_TRANSIT','ARRIVED','CUSTOMS_HOLD','CUSTOMS_RELEASED','DELIVERED','CANCELLED','CLOSED'
    )),
    CONSTRAINT ck_dwms_trade_shipment_quantities CHECK (
        (package_count IS NULL OR package_count >= 0) AND
        (gross_weight IS NULL OR gross_weight >= 0) AND
        (net_weight IS NULL OR net_weight >= 0) AND
        (gross_weight IS NULL OR net_weight IS NULL OR gross_weight >= net_weight) AND
        (volume_value IS NULL OR volume_value >= 0)
    ),
    CONSTRAINT ck_dwms_trade_shipment_dates CHECK (
        (planned_arrival_at IS NULL OR planned_departure_at IS NULL OR planned_arrival_at >= planned_departure_at) AND
        (actual_arrival_at IS NULL OR actual_departure_at IS NULL OR actual_arrival_at >= actual_departure_at)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_dwms_trade_cargo_management_no
    ON dwms.trade_shipments (tenant_id, cargo_management_no_normalized)
    WHERE cargo_management_no_normalized IS NOT NULL;

CREATE TABLE IF NOT EXISTS dwms.trade_shipment_parties (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL,
    owner_partner_id uuid NOT NULL,
    trade_shipment_id uuid NOT NULL,
    party_role varchar(40) NOT NULL,
    partner_id uuid REFERENCES dwms.business_partners(id),
    current_snapshot_no integer NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (trade_shipment_id, party_role),
    FOREIGN KEY (tenant_id, owner_partner_id, trade_shipment_id)
        REFERENCES dwms.trade_shipments(tenant_id, owner_partner_id, id) ON DELETE CASCADE,
    CONSTRAINT ck_dwms_trade_party_snapshot_no CHECK (current_snapshot_no > 0),
    CONSTRAINT ck_dwms_trade_party_role CHECK (party_role IN (
        'OWNER','SELLER','BUYER','SHIPPER','CONSIGNEE','NOTIFY','CARRIER','FORWARDER',
        'CUSTOMS_BROKER','DECLARANT','MANUFACTURER','INSURER','BANK','OTHER'
    ))
);

CREATE TABLE IF NOT EXISTS dwms.trade_party_snapshots (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    trade_shipment_party_id uuid NOT NULL REFERENCES dwms.trade_shipment_parties(id) ON DELETE RESTRICT,
    snapshot_no integer NOT NULL,
    party_name varchar(300) NOT NULL,
    business_identifier varchar(150),
    personal_identifier_encrypted text,
    personal_identifier_hash char(64),
    personal_identifier_masked varchar(100),
    address_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
    contact_snapshot_masked jsonb NOT NULL DEFAULT '{}'::jsonb,
    captured_at timestamptz NOT NULL DEFAULT now(),
    captured_by uuid REFERENCES dwms.users(id),
    UNIQUE (trade_shipment_party_id, snapshot_no),
    CONSTRAINT ck_dwms_trade_party_snapshot_no_positive CHECK (snapshot_no > 0),
    CONSTRAINT ck_dwms_trade_party_person_hash CHECK (
        personal_identifier_hash IS NULL OR personal_identifier_hash ~ '^[0-9A-Fa-f]{64}$'
    )
);

CREATE TABLE IF NOT EXISTS dwms.trade_shipment_references (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL,
    owner_partner_id uuid NOT NULL,
    trade_shipment_id uuid NOT NULL,
    reference_type varchar(80) NOT NULL,
    reference_value varchar(300) NOT NULL,
    issuing_party_id uuid REFERENCES dwms.business_partners(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (trade_shipment_id, reference_type, reference_value),
    FOREIGN KEY (tenant_id, owner_partner_id, trade_shipment_id)
        REFERENCES dwms.trade_shipments(tenant_id, owner_partner_id, id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS dwms.trade_shipment_legs (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL,
    owner_partner_id uuid NOT NULL,
    trade_shipment_id uuid NOT NULL,
    leg_no integer NOT NULL,
    transport_mode_code varchar(20) NOT NULL REFERENCES dwms.transport_modes(mode_code),
    carrier_partner_id uuid REFERENCES dwms.business_partners(id),
    vessel_voyage_id uuid REFERENCES dwms.vessel_voyages(id),
    flight_id uuid REFERENCES dwms.flights(id),
    vehicle_no varchar(100),
    origin_port_code varchar(10) REFERENCES dwms.ports(port_code),
    destination_port_code varchar(10) REFERENCES dwms.ports(port_code),
    origin_place varchar(300),
    destination_place varchar(300),
    booking_reference varchar(150),
    planned_departure_at timestamptz,
    actual_departure_at timestamptz,
    planned_arrival_at timestamptz,
    actual_arrival_at timestamptz,
    status varchar(20) NOT NULL DEFAULT 'PLANNED',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (trade_shipment_id, leg_no),
    FOREIGN KEY (tenant_id, owner_partner_id, trade_shipment_id)
        REFERENCES dwms.trade_shipments(tenant_id, owner_partner_id, id) ON DELETE CASCADE,
    CONSTRAINT ck_dwms_trade_leg_no CHECK (leg_no > 0),
    CONSTRAINT ck_dwms_trade_leg_asset CHECK (num_nonnulls(vessel_voyage_id, flight_id, vehicle_no) <= 1),
    CONSTRAINT ck_dwms_trade_leg_status CHECK (status IN ('PLANNED','BOOKED','DEPARTED','ARRIVED','COMPLETED','CANCELLED','EXCEPTION')),
    CONSTRAINT ck_dwms_trade_leg_plan_dates CHECK (
        planned_arrival_at IS NULL OR planned_departure_at IS NULL OR planned_arrival_at >= planned_departure_at
    ),
    CONSTRAINT ck_dwms_trade_leg_actual_dates CHECK (
        actual_arrival_at IS NULL OR actual_departure_at IS NULL OR actual_arrival_at >= actual_departure_at
    )
);

CREATE TABLE IF NOT EXISTS dwms.trade_shipment_events (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL,
    owner_partner_id uuid NOT NULL,
    trade_shipment_id uuid NOT NULL,
    trade_shipment_leg_id uuid REFERENCES dwms.trade_shipment_legs(id),
    sequence_no bigint NOT NULL,
    event_type varchar(80) NOT NULL,
    event_code varchar(100),
    from_status varchar(30),
    to_status varchar(30),
    location_text varchar(300),
    port_code varchar(10) REFERENCES dwms.ports(port_code),
    occurred_at timestamptz NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT now(),
    source_system_id uuid REFERENCES dwms.external_systems(id),
    external_event_id varchar(300),
    correlation_id varchar(100),
    detail_masked jsonb NOT NULL DEFAULT '{}'::jsonb,
    UNIQUE (trade_shipment_id, sequence_no),
    UNIQUE (source_system_id, external_event_id),
    FOREIGN KEY (tenant_id, owner_partner_id, trade_shipment_id)
        REFERENCES dwms.trade_shipments(tenant_id, owner_partner_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_dwms_trade_event_sequence CHECK (sequence_no > 0)
);

CREATE TABLE IF NOT EXISTS dwms.trade_containers (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    container_no_raw varchar(100) NOT NULL,
    container_no_normalized varchar(100) NOT NULL,
    iso_size_type_code varchar(30),
    equipment_type_code varchar(50),
    owner_partner_id uuid REFERENCES dwms.business_partners(id),
    operator_partner_id uuid REFERENCES dwms.business_partners(id),
    tare_weight numeric(24,8),
    max_gross_weight numeric(24,8),
    weight_uom_code varchar(20) REFERENCES dwms.units_of_measure(uom_code),
    refrigerated boolean NOT NULL DEFAULT false,
    status varchar(20) NOT NULL DEFAULT 'AVAILABLE',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, container_no_normalized),
    CONSTRAINT ck_dwms_trade_container_weight CHECK (
        (tare_weight IS NULL OR tare_weight >= 0) AND
        (max_gross_weight IS NULL OR max_gross_weight >= 0) AND
        (tare_weight IS NULL OR max_gross_weight IS NULL OR max_gross_weight >= tare_weight)
    ),
    CONSTRAINT ck_dwms_trade_container_status CHECK (status IN ('AVAILABLE','BOOKED','STUFFED','SEALED','IN_TRANSIT','EMPTY','DAMAGED','RETIRED'))
);

CREATE TABLE IF NOT EXISTS dwms.trade_container_shipments (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL,
    owner_partner_id uuid NOT NULL,
    trade_container_id uuid NOT NULL REFERENCES dwms.trade_containers(id),
    trade_shipment_id uuid NOT NULL,
    load_type varchar(20) NOT NULL DEFAULT 'FCL',
    package_count numeric(20,4),
    gross_weight numeric(24,8),
    weight_uom_code varchar(20) REFERENCES dwms.units_of_measure(uom_code),
    loaded_at timestamptz,
    unloaded_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (trade_container_id, trade_shipment_id),
    FOREIGN KEY (tenant_id, owner_partner_id, trade_shipment_id)
        REFERENCES dwms.trade_shipments(tenant_id, owner_partner_id, id) ON DELETE CASCADE,
    CONSTRAINT ck_dwms_container_shipment_load CHECK (load_type IN ('FCL','LCL','BULK','AIR_ULD','OTHER')),
    CONSTRAINT ck_dwms_container_shipment_qty CHECK (
        (package_count IS NULL OR package_count >= 0) AND (gross_weight IS NULL OR gross_weight >= 0)
    ),
    CONSTRAINT ck_dwms_container_shipment_dates CHECK (unloaded_at IS NULL OR loaded_at IS NULL OR unloaded_at >= loaded_at)
);

CREATE TABLE IF NOT EXISTS dwms.trade_container_seals (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    trade_container_id uuid NOT NULL REFERENCES dwms.trade_containers(id),
    seal_no varchar(150) NOT NULL,
    seal_type varchar(40) NOT NULL DEFAULT 'CARRIER',
    issuer_partner_id uuid REFERENCES dwms.business_partners(id),
    applied_at timestamptz NOT NULL,
    applied_location varchar(300),
    removed_at timestamptz,
    removed_location varchar(300),
    removal_reason varchar(300),
    status varchar(20) NOT NULL DEFAULT 'APPLIED',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (trade_container_id, seal_no, applied_at),
    CONSTRAINT ck_dwms_trade_seal_status CHECK (status IN ('APPLIED','VERIFIED','BROKEN','REMOVED','REPLACED','VOID')),
    CONSTRAINT ck_dwms_trade_seal_dates CHECK (removed_at IS NULL OR removed_at >= applied_at)
);

CREATE TABLE IF NOT EXISTS dwms.trade_container_events (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    trade_container_id uuid NOT NULL REFERENCES dwms.trade_containers(id),
    trade_shipment_id uuid REFERENCES dwms.trade_shipments(id),
    sequence_no bigint NOT NULL,
    event_type varchar(80) NOT NULL,
    seal_id uuid REFERENCES dwms.trade_container_seals(id),
    event_location varchar(300),
    port_code varchar(10) REFERENCES dwms.ports(port_code),
    occurred_at timestamptz NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT now(),
    source_system_id uuid REFERENCES dwms.external_systems(id),
    external_event_id varchar(300),
    detail_masked jsonb NOT NULL DEFAULT '{}'::jsonb,
    UNIQUE (trade_container_id, sequence_no),
    UNIQUE (source_system_id, external_event_id),
    CONSTRAINT ck_dwms_trade_container_event_seq CHECK (sequence_no > 0)
);

CREATE TABLE IF NOT EXISTS dwms.trade_documents (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL,
    owner_partner_id uuid NOT NULL,
    trade_shipment_id uuid REFERENCES dwms.trade_shipments(id),
    document_kind varchar(50) NOT NULL,
    document_no_raw varchar(200),
    document_no_normalized varchar(200),
    issuing_partner_id uuid REFERENCES dwms.business_partners(id),
    issued_on date,
    expiry_on date,
    current_revision_no integer NOT NULL DEFAULT 1,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    row_version bigint NOT NULL DEFAULT 1,
    created_by uuid REFERENCES dwms.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, owner_partner_id, id),
    CONSTRAINT ck_dwms_trade_document_revision CHECK (current_revision_no > 0),
    CONSTRAINT ck_dwms_trade_document_dates CHECK (expiry_on IS NULL OR issued_on IS NULL OR expiry_on >= issued_on),
    CONSTRAINT ck_dwms_trade_document_status CHECK (status IN ('DRAFT','ISSUED','PRESENTED','ACCEPTED','REJECTED','SUPERSEDED','VOID'))
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_dwms_trade_document_number
    ON dwms.trade_documents (tenant_id, owner_partner_id, document_kind, document_no_normalized)
    WHERE document_no_normalized IS NOT NULL AND status <> 'VOID';

CREATE TABLE IF NOT EXISTS dwms.trade_document_versions (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL,
    owner_partner_id uuid NOT NULL,
    trade_document_id uuid NOT NULL,
    revision_no integer NOT NULL,
    file_id uuid REFERENCES dwms.files(id),
    object_uri text,
    object_sha256 char(64),
    byte_size bigint,
    media_type varchar(150),
    schema_name varchar(150),
    schema_version varchar(80),
    summary_masked jsonb NOT NULL DEFAULT '{}'::jsonb,
    supersedes_version_id uuid REFERENCES dwms.trade_document_versions(id),
    created_by uuid REFERENCES dwms.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (trade_document_id, revision_no),
    FOREIGN KEY (tenant_id, owner_partner_id, trade_document_id)
        REFERENCES dwms.trade_documents(tenant_id, owner_partner_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_dwms_trade_doc_version_no CHECK (revision_no > 0),
    CONSTRAINT ck_dwms_trade_doc_version_source CHECK (file_id IS NOT NULL OR object_uri IS NOT NULL),
    CONSTRAINT ck_dwms_trade_doc_version_hash CHECK (object_sha256 IS NULL OR object_sha256 ~ '^[0-9A-Fa-f]{64}$'),
    CONSTRAINT ck_dwms_trade_doc_version_size CHECK (byte_size IS NULL OR byte_size >= 0),
    CONSTRAINT ck_dwms_trade_doc_version_supersede CHECK (supersedes_version_id IS NULL OR supersedes_version_id <> id)
);

CREATE TABLE IF NOT EXISTS dwms.trade_document_parties (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    trade_document_version_id uuid NOT NULL REFERENCES dwms.trade_document_versions(id) ON DELETE RESTRICT,
    party_role varchar(50) NOT NULL,
    partner_id uuid REFERENCES dwms.business_partners(id),
    party_name_snapshot varchar(300) NOT NULL,
    business_identifier_snapshot varchar(150),
    personal_identifier_encrypted text,
    personal_identifier_hash char(64),
    personal_identifier_masked varchar(100),
    address_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
    contact_snapshot_masked jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (trade_document_version_id, party_role),
    CONSTRAINT ck_dwms_trade_doc_party_hash CHECK (
        personal_identifier_hash IS NULL OR personal_identifier_hash ~ '^[0-9A-Fa-f]{64}$'
    )
);

CREATE TABLE IF NOT EXISTS dwms.trade_document_links (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    source_document_id uuid NOT NULL REFERENCES dwms.trade_documents(id) ON DELETE RESTRICT,
    target_document_id uuid NOT NULL REFERENCES dwms.trade_documents(id) ON DELETE RESTRICT,
    relation_type varchar(50) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (source_document_id, target_document_id, relation_type),
    CONSTRAINT ck_dwms_trade_doc_link_self CHECK (source_document_id <> target_document_id)
);

CREATE TABLE IF NOT EXISTS dwms.commercial_invoices (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL,
    owner_partner_id uuid NOT NULL,
    trade_document_id uuid NOT NULL,
    trade_shipment_id uuid REFERENCES dwms.trade_shipments(id),
    invoice_no varchar(200) NOT NULL,
    invoice_date date NOT NULL,
    seller_partner_id uuid REFERENCES dwms.business_partners(id),
    buyer_partner_id uuid REFERENCES dwms.business_partners(id),
    ship_to_partner_id uuid REFERENCES dwms.business_partners(id),
    currency_code char(3) NOT NULL REFERENCES dwms.currencies(currency_code),
    incoterm_code char(3) REFERENCES dwms.incoterms(incoterm_code),
    payment_term_id uuid REFERENCES dwms.payment_terms(id),
    goods_amount numeric(24,4) NOT NULL DEFAULT 0,
    freight_amount numeric(24,4) NOT NULL DEFAULT 0,
    insurance_amount numeric(24,4) NOT NULL DEFAULT 0,
    other_charge_amount numeric(24,4) NOT NULL DEFAULT 0,
    discount_amount numeric(24,4) NOT NULL DEFAULT 0,
    total_amount numeric(24,4) NOT NULL,
    country_of_export char(2) REFERENCES dwms.countries(country_code),
    destination_country_code char(2) REFERENCES dwms.countries(country_code),
    status varchar(20) NOT NULL DEFAULT 'ISSUED',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, owner_partner_id, invoice_no, invoice_date),
    UNIQUE (tenant_id, owner_partner_id, id),
    FOREIGN KEY (tenant_id, owner_partner_id, trade_document_id)
        REFERENCES dwms.trade_documents(tenant_id, owner_partner_id, id),
    CONSTRAINT ck_dwms_commercial_invoice_amount CHECK (
        goods_amount >= 0 AND freight_amount >= 0 AND insurance_amount >= 0 AND
        other_charge_amount >= 0 AND discount_amount >= 0 AND total_amount >= 0
    ),
    CONSTRAINT ck_dwms_commercial_invoice_total CHECK (
        total_amount = goods_amount + freight_amount + insurance_amount + other_charge_amount - discount_amount
    ),
    CONSTRAINT ck_dwms_commercial_invoice_status CHECK (status IN ('DRAFT','ISSUED','REVISED','CANCELLED','ACCEPTED'))
);

CREATE TABLE IF NOT EXISTS dwms.commercial_invoice_lines (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL,
    owner_partner_id uuid NOT NULL,
    commercial_invoice_id uuid NOT NULL,
    line_no integer NOT NULL,
    item_id uuid REFERENCES dwms.items(id),
    seller_item_code varchar(120),
    buyer_item_code varchar(120),
    goods_description varchar(1000) NOT NULL,
    hs_code varchar(20),
    hs_country_code char(2),
    hs_nomenclature_version varchar(20),
    country_of_origin char(2) REFERENCES dwms.countries(country_code),
    quantity numeric(24,8) NOT NULL,
    uom_code varchar(20) NOT NULL REFERENCES dwms.units_of_measure(uom_code),
    unit_price numeric(24,8) NOT NULL,
    line_amount numeric(24,4) NOT NULL,
    net_weight numeric(24,8),
    gross_weight numeric(24,8),
    weight_uom_code varchar(20) REFERENCES dwms.units_of_measure(uom_code),
    preference_code varchar(80),
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (commercial_invoice_id, line_no),
    UNIQUE (tenant_id, owner_partner_id, id),
    FOREIGN KEY (tenant_id, owner_partner_id, commercial_invoice_id)
        REFERENCES dwms.commercial_invoices(tenant_id, owner_partner_id, id) ON DELETE CASCADE,
    FOREIGN KEY (hs_country_code, hs_nomenclature_version, hs_code)
        REFERENCES dwms.hs_codes(country_code, nomenclature_version, hs_code),
    CONSTRAINT ck_dwms_commercial_invoice_line_no CHECK (line_no > 0),
    CONSTRAINT ck_dwms_commercial_invoice_line_qty CHECK (quantity > 0),
    CONSTRAINT ck_dwms_commercial_invoice_line_amount CHECK (unit_price >= 0 AND line_amount >= 0),
    CONSTRAINT ck_dwms_commercial_invoice_line_weight CHECK (
        (net_weight IS NULL OR net_weight >= 0) AND (gross_weight IS NULL OR gross_weight >= 0) AND
        (gross_weight IS NULL OR net_weight IS NULL OR gross_weight >= net_weight)
    )
);

CREATE TABLE IF NOT EXISTS dwms.packing_lists (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL,
    owner_partner_id uuid NOT NULL,
    trade_document_id uuid NOT NULL,
    trade_shipment_id uuid REFERENCES dwms.trade_shipments(id),
    packing_list_no varchar(200) NOT NULL,
    packing_date date NOT NULL,
    commercial_invoice_id uuid REFERENCES dwms.commercial_invoices(id),
    package_count numeric(20,4) NOT NULL DEFAULT 0,
    package_type_code varchar(50),
    gross_weight numeric(24,8),
    net_weight numeric(24,8),
    weight_uom_code varchar(20) REFERENCES dwms.units_of_measure(uom_code),
    volume_value numeric(24,9),
    volume_uom_code varchar(20) REFERENCES dwms.units_of_measure(uom_code),
    status varchar(20) NOT NULL DEFAULT 'ISSUED',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, owner_partner_id, packing_list_no, packing_date),
    UNIQUE (tenant_id, owner_partner_id, id),
    FOREIGN KEY (tenant_id, owner_partner_id, trade_document_id)
        REFERENCES dwms.trade_documents(tenant_id, owner_partner_id, id),
    CONSTRAINT ck_dwms_packing_list_qty CHECK (
        package_count >= 0 AND (gross_weight IS NULL OR gross_weight >= 0) AND
        (net_weight IS NULL OR net_weight >= 0) AND
        (gross_weight IS NULL OR net_weight IS NULL OR gross_weight >= net_weight) AND
        (volume_value IS NULL OR volume_value >= 0)
    ),
    CONSTRAINT ck_dwms_packing_list_status CHECK (status IN ('DRAFT','ISSUED','REVISED','CANCELLED','ACCEPTED'))
);

CREATE TABLE IF NOT EXISTS dwms.packing_list_lines (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL,
    owner_partner_id uuid NOT NULL,
    packing_list_id uuid NOT NULL,
    line_no integer NOT NULL,
    commercial_invoice_line_id uuid REFERENCES dwms.commercial_invoice_lines(id),
    trade_container_id uuid REFERENCES dwms.trade_containers(id),
    package_no_from varchar(100),
    package_no_to varchar(100),
    package_count numeric(20,4) NOT NULL,
    package_type_code varchar(50),
    item_id uuid REFERENCES dwms.items(id),
    goods_description varchar(1000),
    quantity numeric(24,8),
    uom_code varchar(20) REFERENCES dwms.units_of_measure(uom_code),
    gross_weight numeric(24,8),
    net_weight numeric(24,8),
    weight_uom_code varchar(20) REFERENCES dwms.units_of_measure(uom_code),
    marks_and_numbers text,
    lot_no_snapshot varchar(150),
    serial_snapshot_masked jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (packing_list_id, line_no),
    UNIQUE (tenant_id, owner_partner_id, id),
    FOREIGN KEY (tenant_id, owner_partner_id, packing_list_id)
        REFERENCES dwms.packing_lists(tenant_id, owner_partner_id, id) ON DELETE CASCADE,
    CONSTRAINT ck_dwms_packing_list_line_no CHECK (line_no > 0),
    CONSTRAINT ck_dwms_packing_list_line_qty CHECK (
        package_count >= 0 AND (quantity IS NULL OR quantity > 0) AND
        (gross_weight IS NULL OR gross_weight >= 0) AND (net_weight IS NULL OR net_weight >= 0) AND
        (gross_weight IS NULL OR net_weight IS NULL OR gross_weight >= net_weight)
    )
);

CREATE TABLE IF NOT EXISTS dwms.bills_of_lading (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL,
    owner_partner_id uuid NOT NULL,
    trade_document_id uuid NOT NULL,
    trade_shipment_id uuid NOT NULL,
    bill_type varchar(20) NOT NULL,
    parent_master_bill_id uuid REFERENCES dwms.bills_of_lading(id),
    bill_no_raw varchar(200) NOT NULL,
    bill_no_normalized varchar(200) NOT NULL,
    master_bill_serial varchar(80),
    house_bill_serial varchar(80),
    carrier_partner_id uuid REFERENCES dwms.business_partners(id),
    forwarder_partner_id uuid REFERENCES dwms.business_partners(id),
    vessel_voyage_id uuid REFERENCES dwms.vessel_voyages(id),
    port_of_loading_code varchar(10) REFERENCES dwms.ports(port_code),
    port_of_discharge_code varchar(10) REFERENCES dwms.ports(port_code),
    place_of_receipt varchar(300),
    place_of_delivery varchar(300),
    on_board_at timestamptz,
    issued_on date,
    original_count integer,
    freight_payment_term varchar(30),
    package_count numeric(20,4),
    gross_weight numeric(24,8),
    weight_uom_code varchar(20) REFERENCES dwms.units_of_measure(uom_code),
    measurement_value numeric(24,9),
    measurement_uom_code varchar(20) REFERENCES dwms.units_of_measure(uom_code),
    goods_description text,
    marks_and_numbers text,
    status varchar(20) NOT NULL DEFAULT 'ISSUED',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, owner_partner_id, bill_no_normalized),
    UNIQUE (tenant_id, owner_partner_id, id),
    FOREIGN KEY (tenant_id, owner_partner_id, trade_document_id)
        REFERENCES dwms.trade_documents(tenant_id, owner_partner_id, id),
    FOREIGN KEY (tenant_id, owner_partner_id, trade_shipment_id)
        REFERENCES dwms.trade_shipments(tenant_id, owner_partner_id, id),
    CONSTRAINT ck_dwms_bl_type CHECK (bill_type IN ('MASTER','HOUSE','DIRECT')),
    CONSTRAINT ck_dwms_bl_parent CHECK (
        parent_master_bill_id IS NULL OR (parent_master_bill_id <> id AND bill_type = 'HOUSE')
    ),
    CONSTRAINT ck_dwms_bl_qty CHECK (
        (original_count IS NULL OR original_count >= 0) AND (package_count IS NULL OR package_count >= 0) AND
        (gross_weight IS NULL OR gross_weight >= 0) AND (measurement_value IS NULL OR measurement_value >= 0)
    ),
    CONSTRAINT ck_dwms_bl_status CHECK (status IN ('DRAFT','ISSUED','SURRENDERED','RELEASED','AMENDED','CANCELLED'))
);

CREATE TABLE IF NOT EXISTS dwms.bill_of_lading_lines (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL,
    owner_partner_id uuid NOT NULL,
    bill_of_lading_id uuid NOT NULL,
    line_no integer NOT NULL,
    commercial_invoice_line_id uuid REFERENCES dwms.commercial_invoice_lines(id),
    packing_list_line_id uuid REFERENCES dwms.packing_list_lines(id),
    item_id uuid REFERENCES dwms.items(id),
    trade_container_id uuid REFERENCES dwms.trade_containers(id),
    goods_description varchar(1000) NOT NULL,
    package_count numeric(20,4),
    package_type_code varchar(50),
    quantity numeric(24,8),
    uom_code varchar(20) REFERENCES dwms.units_of_measure(uom_code),
    gross_weight numeric(24,8),
    weight_uom_code varchar(20) REFERENCES dwms.units_of_measure(uom_code),
    measurement_value numeric(24,9),
    measurement_uom_code varchar(20) REFERENCES dwms.units_of_measure(uom_code),
    marks_and_numbers text,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (bill_of_lading_id, line_no),
    FOREIGN KEY (tenant_id, owner_partner_id, bill_of_lading_id)
        REFERENCES dwms.bills_of_lading(tenant_id, owner_partner_id, id) ON DELETE CASCADE,
    CONSTRAINT ck_dwms_bl_line_no CHECK (line_no > 0),
    CONSTRAINT ck_dwms_bl_line_qty CHECK (
        (package_count IS NULL OR package_count >= 0) AND (quantity IS NULL OR quantity > 0) AND
        (gross_weight IS NULL OR gross_weight >= 0) AND (measurement_value IS NULL OR measurement_value >= 0)
    )
);

CREATE TABLE IF NOT EXISTS dwms.air_waybills (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL,
    owner_partner_id uuid NOT NULL,
    trade_document_id uuid NOT NULL,
    trade_shipment_id uuid NOT NULL,
    airwaybill_type varchar(20) NOT NULL,
    parent_master_airwaybill_id uuid REFERENCES dwms.air_waybills(id),
    airwaybill_no_raw varchar(200) NOT NULL,
    airwaybill_no_normalized varchar(200) NOT NULL,
    master_awb_serial varchar(80),
    house_awb_serial varchar(80),
    carrier_partner_id uuid REFERENCES dwms.business_partners(id),
    forwarder_partner_id uuid REFERENCES dwms.business_partners(id),
    flight_id uuid REFERENCES dwms.flights(id),
    airport_of_departure_code varchar(10) REFERENCES dwms.ports(port_code),
    airport_of_destination_code varchar(10) REFERENCES dwms.ports(port_code),
    issued_on date,
    package_count numeric(20,4),
    gross_weight numeric(24,8),
    chargeable_weight numeric(24,8),
    weight_uom_code varchar(20) REFERENCES dwms.units_of_measure(uom_code),
    declared_value_for_carriage numeric(24,4),
    declared_value_for_customs numeric(24,4),
    currency_code char(3) REFERENCES dwms.currencies(currency_code),
    goods_description text,
    handling_information text,
    status varchar(20) NOT NULL DEFAULT 'ISSUED',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, owner_partner_id, airwaybill_no_normalized),
    UNIQUE (tenant_id, owner_partner_id, id),
    FOREIGN KEY (tenant_id, owner_partner_id, trade_document_id)
        REFERENCES dwms.trade_documents(tenant_id, owner_partner_id, id),
    FOREIGN KEY (tenant_id, owner_partner_id, trade_shipment_id)
        REFERENCES dwms.trade_shipments(tenant_id, owner_partner_id, id),
    CONSTRAINT ck_dwms_awb_type CHECK (airwaybill_type IN ('MASTER','HOUSE','DIRECT')),
    CONSTRAINT ck_dwms_awb_parent CHECK (
        parent_master_airwaybill_id IS NULL OR (parent_master_airwaybill_id <> id AND airwaybill_type = 'HOUSE')
    ),
    CONSTRAINT ck_dwms_awb_qty CHECK (
        (package_count IS NULL OR package_count >= 0) AND (gross_weight IS NULL OR gross_weight >= 0) AND
        (chargeable_weight IS NULL OR chargeable_weight >= 0) AND
        (declared_value_for_carriage IS NULL OR declared_value_for_carriage >= 0) AND
        (declared_value_for_customs IS NULL OR declared_value_for_customs >= 0)
    ),
    CONSTRAINT ck_dwms_awb_status CHECK (status IN ('DRAFT','ISSUED','ACCEPTED','RELEASED','AMENDED','CANCELLED'))
);

CREATE TABLE IF NOT EXISTS dwms.air_waybill_lines (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL,
    owner_partner_id uuid NOT NULL,
    air_waybill_id uuid NOT NULL,
    line_no integer NOT NULL,
    commercial_invoice_line_id uuid REFERENCES dwms.commercial_invoice_lines(id),
    packing_list_line_id uuid REFERENCES dwms.packing_list_lines(id),
    item_id uuid REFERENCES dwms.items(id),
    goods_description varchar(1000) NOT NULL,
    package_count numeric(20,4),
    quantity numeric(24,8),
    uom_code varchar(20) REFERENCES dwms.units_of_measure(uom_code),
    gross_weight numeric(24,8),
    chargeable_weight numeric(24,8),
    weight_uom_code varchar(20) REFERENCES dwms.units_of_measure(uom_code),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (air_waybill_id, line_no),
    FOREIGN KEY (tenant_id, owner_partner_id, air_waybill_id)
        REFERENCES dwms.air_waybills(tenant_id, owner_partner_id, id) ON DELETE CASCADE,
    CONSTRAINT ck_dwms_awb_line_no CHECK (line_no > 0),
    CONSTRAINT ck_dwms_awb_line_qty CHECK (
        (package_count IS NULL OR package_count >= 0) AND (quantity IS NULL OR quantity > 0) AND
        (gross_weight IS NULL OR gross_weight >= 0) AND (chargeable_weight IS NULL OR chargeable_weight >= 0)
    )
);

CREATE TABLE IF NOT EXISTS dwms.receipt_trade_allocations (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    owner_partner_id uuid NOT NULL REFERENCES dwms.business_partners(id),
    receipt_id uuid NOT NULL,
    receipt_line_id uuid NOT NULL,
    trade_shipment_id uuid NOT NULL,
    commercial_invoice_line_id uuid REFERENCES dwms.commercial_invoice_lines(id),
    packing_list_line_id uuid REFERENCES dwms.packing_list_lines(id),
    bill_of_lading_line_id uuid REFERENCES dwms.bill_of_lading_lines(id),
    air_waybill_line_id uuid REFERENCES dwms.air_waybill_lines(id),
    trade_container_id uuid REFERENCES dwms.trade_containers(id),
    allocated_quantity numeric(24,8) NOT NULL,
    uom_code varchar(20) NOT NULL REFERENCES dwms.units_of_measure(uom_code),
    allocated_base_quantity numeric(24,8) NOT NULL,
    base_uom_code varchar(20) NOT NULL REFERENCES dwms.units_of_measure(uom_code),
    created_by uuid REFERENCES dwms.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (receipt_line_id, trade_shipment_id, commercial_invoice_line_id, packing_list_line_id),
    FOREIGN KEY (tenant_id, receipt_id) REFERENCES dwms.receipts(tenant_id, id),
    FOREIGN KEY (tenant_id, receipt_line_id) REFERENCES dwms.receipt_lines(tenant_id, id),
    FOREIGN KEY (tenant_id, owner_partner_id, trade_shipment_id)
        REFERENCES dwms.trade_shipments(tenant_id, owner_partner_id, id),
    CONSTRAINT ck_dwms_receipt_trade_allocation_qty CHECK (
        allocated_quantity > 0 AND allocated_base_quantity > 0
    )
);

CREATE TABLE IF NOT EXISTS dwms.shipment_trade_allocations (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    owner_partner_id uuid NOT NULL REFERENCES dwms.business_partners(id),
    shipment_id uuid NOT NULL REFERENCES dwms.shipments(id),
    shipment_line_id uuid NOT NULL REFERENCES dwms.shipment_lines(id),
    trade_shipment_id uuid NOT NULL,
    commercial_invoice_line_id uuid REFERENCES dwms.commercial_invoice_lines(id),
    packing_list_line_id uuid REFERENCES dwms.packing_list_lines(id),
    bill_of_lading_line_id uuid REFERENCES dwms.bill_of_lading_lines(id),
    air_waybill_line_id uuid REFERENCES dwms.air_waybill_lines(id),
    trade_container_id uuid REFERENCES dwms.trade_containers(id),
    allocated_quantity numeric(24,8) NOT NULL,
    uom_code varchar(20) NOT NULL REFERENCES dwms.units_of_measure(uom_code),
    allocated_base_quantity numeric(24,8) NOT NULL,
    base_uom_code varchar(20) NOT NULL REFERENCES dwms.units_of_measure(uom_code),
    created_by uuid REFERENCES dwms.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (shipment_line_id, trade_shipment_id, commercial_invoice_line_id, packing_list_line_id),
    FOREIGN KEY (tenant_id, owner_partner_id, trade_shipment_id)
        REFERENCES dwms.trade_shipments(tenant_id, owner_partner_id, id),
    CONSTRAINT ck_dwms_shipment_trade_allocation_qty CHECK (
        allocated_quantity > 0 AND allocated_base_quantity > 0
    )
);

CREATE TABLE IF NOT EXISTS dwms.customs_message_schemas (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    jurisdiction_country_code char(2) NOT NULL DEFAULT 'KR' REFERENCES dwms.countries(country_code),
    authority_code varchar(50) NOT NULL DEFAULT 'KCS',
    message_type varchar(120) NOT NULL,
    direction varchar(10) NOT NULL,
    schema_version varchar(100) NOT NULL,
    schema_format varchar(30) NOT NULL,
    schema_object_uri text NOT NULL,
    schema_sha256 char(64) NOT NULL,
    mapping_version varchar(100),
    effective_from date NOT NULL,
    effective_to date,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (jurisdiction_country_code, authority_code, message_type, direction, schema_version),
    CONSTRAINT ck_dwms_customs_schema_direction CHECK (direction IN ('IN','OUT')),
    CONSTRAINT ck_dwms_customs_schema_format CHECK (schema_format IN ('XML_XSD','JSON_SCHEMA','FIXED_WIDTH','CSV','OTHER')),
    CONSTRAINT ck_dwms_customs_schema_hash CHECK (schema_sha256 ~ '^[0-9A-Fa-f]{64}$'),
    CONSTRAINT ck_dwms_customs_schema_dates CHECK (effective_to IS NULL OR effective_to >= effective_from)
);

CREATE TABLE IF NOT EXISTS dwms.unipass_connection_profiles (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    organization_id uuid NOT NULL REFERENCES dwms.organizations(id),
    declarant_partner_id uuid REFERENCES dwms.business_partners(id),
    external_system_id uuid REFERENCES dwms.external_systems(id),
    profile_code varchar(80) NOT NULL,
    profile_name varchar(200) NOT NULL,
    environment varchar(20) NOT NULL DEFAULT 'PRODUCTION',
    endpoint_uri text NOT NULL,
    service_id varchar(150),
    sender_id varchar(150),
    credential_secret_ref varchar(500),
    certificate_secret_ref varchar(500),
    network_profile_ref varchar(500),
    config_non_secret jsonb NOT NULL DEFAULT '{}'::jsonb,
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    valid_from timestamptz NOT NULL DEFAULT now(),
    valid_to timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, profile_code),
    CONSTRAINT ck_dwms_unipass_profile_environment CHECK (environment IN ('SANDBOX','TEST','PRODUCTION')),
    CONSTRAINT ck_dwms_unipass_profile_status CHECK (status IN ('ACTIVE','INACTIVE','SUSPENDED','EXPIRED')),
    CONSTRAINT ck_dwms_unipass_profile_dates CHECK (valid_to IS NULL OR valid_to > valid_from),
    CONSTRAINT ck_dwms_unipass_profile_secret_ref CHECK (
        credential_secret_ref IS NOT NULL OR certificate_secret_ref IS NOT NULL
    ),
    CONSTRAINT ck_dwms_unipass_profile_no_inline_secrets CHECK (
        NOT dwms.jsonb_contains_forbidden_secret_key(config_non_secret)
    )
);

COMMENT ON TABLE dwms.unipass_connection_profiles IS
    'UNI-PASS connectivity metadata. Credentials, private keys, and certificates are external secret references only.';

CREATE TABLE IF NOT EXISTS dwms.customs_declarations (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    owner_partner_id uuid NOT NULL REFERENCES dwms.business_partners(id),
    warehouse_id uuid REFERENCES dwms.warehouses(id),
    declaration_key varchar(120) NOT NULL,
    declaration_kind varchar(30) NOT NULL,
    declaration_no_raw varchar(200),
    declaration_no_normalized varchar(200),
    submission_no varchar(200),
    customs_office_code varchar(20) REFERENCES dwms.customs_offices(customs_office_code),
    trade_shipment_id uuid REFERENCES dwms.trade_shipments(id),
    receipt_id uuid REFERENCES dwms.receipts(id),
    shipment_id uuid REFERENCES dwms.shipments(id),
    current_version_id uuid,
    current_version_no integer,
    workflow_status varchar(30) NOT NULL DEFAULT 'DRAFT',
    customs_system_recorded_at timestamptz,
    accepted_at timestamptz,
    assessed_at timestamptz,
    released_at timestamptz,
    cleared_at timestamptz,
    rejected_at timestamptz,
    withdrawn_at timestamptz,
    retention_until date,
    legal_hold boolean NOT NULL DEFAULT false,
    source_system_id uuid REFERENCES dwms.external_systems(id),
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_by uuid REFERENCES dwms.users(id),
    updated_by uuid REFERENCES dwms.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, declaration_key),
    UNIQUE (tenant_id, owner_partner_id, id),
    CONSTRAINT ck_dwms_customs_declaration_kind CHECK (declaration_kind IN (
        'IMPORT','EXPORT','RETURN_EXPORT','RETURN_IMPORT','TRANSIT','BONDED','OTHER'
    )),
    CONSTRAINT ck_dwms_customs_declaration_status CHECK (workflow_status IN (
        'DRAFT','PREPARED','SUBMITTED','ACCEPTED','UNDER_REVIEW','INSPECTION','ASSESSED','PAID',
        'RELEASED','CLEARED','CORRECTION_REQUIRED','REJECTED','WITHDRAWN','CANCELLED'
    )),
    CONSTRAINT ck_dwms_customs_declaration_version CHECK (
        (current_version_id IS NULL AND current_version_no IS NULL) OR
        (current_version_id IS NOT NULL AND current_version_no > 0)
    ),
    CONSTRAINT ck_dwms_customs_declaration_dates CHECK (
        (accepted_at IS NULL OR customs_system_recorded_at IS NULL OR accepted_at >= customs_system_recorded_at) AND
        (released_at IS NULL OR accepted_at IS NULL OR released_at >= accepted_at) AND
        (cleared_at IS NULL OR accepted_at IS NULL OR cleared_at >= accepted_at)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_dwms_customs_declaration_no
    ON dwms.customs_declarations (tenant_id, customs_office_code, declaration_no_normalized)
    WHERE declaration_no_normalized IS NOT NULL;

CREATE INDEX IF NOT EXISTS ix_dwms_customs_declaration_owner_status
    ON dwms.customs_declarations (tenant_id, owner_partner_id, workflow_status, created_at DESC);

CREATE TABLE IF NOT EXISTS dwms.customs_declaration_versions (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL,
    owner_partner_id uuid NOT NULL,
    declaration_id uuid NOT NULL,
    version_no integer NOT NULL,
    filing_action varchar(30) NOT NULL DEFAULT 'ORIGINAL',
    correction_reason_code varchar(100),
    correction_reason_text text,
    supersedes_version_id uuid REFERENCES dwms.customs_declaration_versions(id),
    submission_no varchar(200),
    original_submission_no varchar(200),
    client_reference_no varchar(200),
    declaration_date date,
    planned_submission_at timestamptz,
    declarant_partner_id uuid REFERENCES dwms.business_partners(id),
    customs_broker_partner_id uuid REFERENCES dwms.business_partners(id),
    importer_exporter_partner_id uuid REFERENCES dwms.business_partners(id),
    procedure_code varchar(100),
    transaction_type_code varchar(100),
    payment_method_code varchar(100),
    cargo_management_no_raw varchar(200),
    cargo_management_no_normalized varchar(200),
    master_transport_document_no varchar(200),
    house_transport_document_no varchar(200),
    vessel_name_snapshot varchar(250),
    voyage_no_snapshot varchar(100),
    flight_no_snapshot varchar(100),
    port_of_loading_code varchar(10) REFERENCES dwms.ports(port_code),
    port_of_discharge_code varchar(10) REFERENCES dwms.ports(port_code),
    arrival_departure_at timestamptz,
    warehouse_customs_code varchar(100),
    incoterm_code char(3) REFERENCES dwms.incoterms(incoterm_code),
    invoice_currency_code char(3) REFERENCES dwms.currencies(currency_code),
    exchange_rate numeric(24,12),
    total_invoice_amount numeric(24,4),
    customs_value_currency_code char(3) REFERENCES dwms.currencies(currency_code),
    total_customs_value numeric(24,4),
    total_duty_amount numeric(24,4),
    total_tax_amount numeric(24,4),
    package_count numeric(20,4),
    package_type_code varchar(50),
    gross_weight numeric(24,8),
    net_weight numeric(24,8),
    weight_uom_code varchar(20) REFERENCES dwms.units_of_measure(uom_code),
    declared_line_count integer,
    declaration_note text,
    payload_summary_masked jsonb NOT NULL DEFAULT '{}'::jsonb,
    prepared_by uuid REFERENCES dwms.users(id),
    prepared_at timestamptz NOT NULL DEFAULT now(),
    sealed_by uuid REFERENCES dwms.users(id),
    sealed_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (declaration_id, version_no),
    UNIQUE (declaration_id, id),
    UNIQUE (tenant_id, owner_partner_id, id),
    FOREIGN KEY (tenant_id, owner_partner_id, declaration_id)
        REFERENCES dwms.customs_declarations(tenant_id, owner_partner_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_dwms_customs_version_no CHECK (version_no > 0),
    CONSTRAINT ck_dwms_customs_version_action CHECK (filing_action IN (
        'ORIGINAL','CORRECTION','WITHDRAWAL','CANCELLATION','OFFICIAL_CORRECTION','RESUBMISSION'
    )),
    CONSTRAINT ck_dwms_customs_version_supersedes CHECK (supersedes_version_id IS NULL OR supersedes_version_id <> id),
    CONSTRAINT ck_dwms_customs_version_exchange CHECK (exchange_rate IS NULL OR exchange_rate > 0),
    CONSTRAINT ck_dwms_customs_version_amounts CHECK (
        (total_invoice_amount IS NULL OR total_invoice_amount >= 0) AND
        (total_customs_value IS NULL OR total_customs_value >= 0) AND
        (total_duty_amount IS NULL OR total_duty_amount >= 0) AND
        (total_tax_amount IS NULL OR total_tax_amount >= 0)
    ),
    CONSTRAINT ck_dwms_customs_version_quantities CHECK (
        (package_count IS NULL OR package_count >= 0) AND
        (gross_weight IS NULL OR gross_weight >= 0) AND
        (net_weight IS NULL OR net_weight >= 0) AND
        (gross_weight IS NULL OR net_weight IS NULL OR gross_weight >= net_weight) AND
        (declared_line_count IS NULL OR declared_line_count >= 0)
    ),
    CONSTRAINT ck_dwms_customs_version_seal CHECK (
        (sealed_at IS NULL AND sealed_by IS NULL) OR (sealed_at IS NOT NULL AND sealed_by IS NOT NULL)
    )
);

DO $block$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'dwms.customs_declarations'::regclass
          AND conname = 'fk_dwms_customs_current_version'
    ) THEN
        ALTER TABLE dwms.customs_declarations
            ADD CONSTRAINT fk_dwms_customs_current_version
            FOREIGN KEY (id, current_version_id)
            REFERENCES dwms.customs_declaration_versions(declaration_id, id)
            DEFERRABLE INITIALLY DEFERRED;
    END IF;
END;
$block$;

-- A customs-required shipment may leave inventory or the yard only after every allocated
-- trade shipment (or the shipment itself when no trade allocation exists) has an official
-- RELEASED/CLEARED declaration. The evidence row is locked so a concurrent status change
-- cannot race a physical dispatch.
CREATE OR REPLACE FUNCTION dwms.require_shipment_customs_release(
    p_tenant_id uuid,
    p_owner_partner_id uuid,
    p_shipment_id uuid,
    p_shipment_type varchar,
    p_physical_event_at timestamptz
)
RETURNS timestamptz
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, dwms
AS $function$
DECLARE
    trade_row record;
    official_evidence_row record;
    allocation_row record;
    evidence_release_at timestamptz;
    latest_required_release_at timestamptz;
    allocation_count integer := 0;
    evidence_count integer;
    allowed_evidence_types text[];
    line_row record;
    covered_base_quantity numeric(24,8);
    shipment_line_count integer := 0;
BEGIN
    IF p_physical_event_at IS NULL THEN
        RAISE EXCEPTION 'A customs-controlled physical shipment event requires its actual timestamp'
            USING ERRCODE = '23514';
    END IF;

    allowed_evidence_types := CASE
        WHEN p_shipment_type = 'EXPORT' THEN ARRAY['EXPORT_CLEARANCE','RETURN_RELEASE']::text[]
        WHEN p_shipment_type = 'RETURN' THEN ARRAY['RETURN_RELEASE','IMPORT_RELEASE','EXPORT_CLEARANCE']::text[]
        ELSE ARRAY['IMPORT_RELEASE','EXPORT_CLEARANCE','BONDED_RELEASE','TRANSIT_RELEASE','RETURN_RELEASE']::text[]
    END;

    FOR trade_row IN
        SELECT DISTINCT allocation.trade_shipment_id
        FROM dwms.shipment_trade_allocations allocation
        WHERE allocation.tenant_id = p_tenant_id
          AND allocation.owner_partner_id = p_owner_partner_id
          AND allocation.shipment_id = p_shipment_id
        ORDER BY allocation.trade_shipment_id
    LOOP
        allocation_count := allocation_count + 1;
        evidence_count := 0;
        FOR official_evidence_row IN
            SELECT evidence.id, evidence.official_release_at
              FROM dwms.customs_release_evidence evidence
              JOIN dwms.customs_declarations declaration
                ON declaration.id = evidence.declaration_id
              JOIN dwms.unipass_messages official_message
                ON official_message.id = evidence.unipass_message_id
             WHERE evidence.tenant_id = p_tenant_id
               AND evidence.owner_partner_id = p_owner_partner_id
               AND evidence.shipment_id = p_shipment_id
               AND evidence.trade_shipment_id = trade_row.trade_shipment_id
               AND dwms.customs_release_evidence_is_current(evidence.id)
               AND evidence.evidence_type = ANY (allowed_evidence_types)
               AND declaration.workflow_status IN ('RELEASED','CLEARED')
               AND declaration.current_version_id = evidence.declaration_version_id
               AND official_message.direction = 'IN'
               AND official_message.recorded_status = 'ACCEPTED'
               AND official_message.customs_system_recorded_at IS NOT NULL
               AND EXISTS (
                   SELECT 1
                     FROM dwms.customs_release_line_coverages coverage
                     JOIN dwms.shipment_trade_allocations allocation
                       ON allocation.id = coverage.shipment_trade_allocation_id
                    WHERE coverage.customs_release_evidence_id = evidence.id
                      AND allocation.shipment_id = p_shipment_id
                      AND allocation.trade_shipment_id = trade_row.trade_shipment_id
               )
             ORDER BY evidence.id
             FOR SHARE OF evidence, declaration, official_message
        LOOP
            evidence_count := evidence_count + 1;
            evidence_release_at := official_evidence_row.official_release_at;
            IF evidence_release_at > p_physical_event_at THEN
                RAISE EXCEPTION
                    'Shipment % physical event % precedes customs release %',
                    p_shipment_id, p_physical_event_at, evidence_release_at
                    USING ERRCODE = '23514';
            END IF;
            latest_required_release_at := GREATEST(
                COALESCE(latest_required_release_at, evidence_release_at), evidence_release_at
            );
        END LOOP;
        IF evidence_count = 0 THEN
            RAISE EXCEPTION
                'Shipment % trade shipment % has no line-covered verified UNI-PASS release evidence',
                p_shipment_id, trade_row.trade_shipment_id
                USING ERRCODE = '23514';
        END IF;
    END LOOP;

    FOR line_row IN
        SELECT line.id, line.base_quantity
          FROM dwms.shipment_lines line
         WHERE line.tenant_id = p_tenant_id
           AND line.shipment_id = p_shipment_id
         ORDER BY line.id
         FOR SHARE
    LOOP
        shipment_line_count := shipment_line_count + 1;
        IF allocation_count > 0 THEN
            SELECT COALESCE(sum(allocation.allocated_base_quantity), 0)
              INTO covered_base_quantity
              FROM dwms.shipment_trade_allocations allocation
             WHERE allocation.tenant_id = p_tenant_id
               AND allocation.owner_partner_id = p_owner_partner_id
               AND allocation.shipment_id = p_shipment_id
               AND allocation.shipment_line_id = line_row.id;
            IF covered_base_quantity <> line_row.base_quantity THEN
                RAISE EXCEPTION
                    'Customs shipment line % coverage % must equal shipped base quantity %',
                    line_row.id, covered_base_quantity, line_row.base_quantity
                    USING ERRCODE = '23514';
            END IF;
        END IF;
    END LOOP;
    IF shipment_line_count = 0 THEN
        RAISE EXCEPTION 'Customs-controlled shipment % has no shipment lines', p_shipment_id
            USING ERRCODE = '23514';
    END IF;

    IF allocation_count > 0 THEN
        FOR allocation_row IN
            SELECT allocation.id, allocation.shipment_line_id, allocation.trade_shipment_id,
                   allocation.commercial_invoice_line_id, allocation.allocated_base_quantity,
                   allocation.base_uom_code
              FROM dwms.shipment_trade_allocations allocation
             WHERE allocation.tenant_id = p_tenant_id
               AND allocation.owner_partner_id = p_owner_partner_id
               AND allocation.shipment_id = p_shipment_id
             ORDER BY allocation.id
             FOR SHARE
        LOOP
            SELECT COALESCE(sum(coverage.covered_base_quantity), 0)
              INTO covered_base_quantity
              FROM dwms.customs_release_line_coverages coverage
              JOIN dwms.customs_release_evidence evidence
                ON evidence.id = coverage.customs_release_evidence_id
              JOIN dwms.customs_declaration_lines declaration_line
                ON declaration_line.id = coverage.declaration_line_id
              JOIN dwms.shipment_lines shipment_line
                ON shipment_line.id = coverage.shipment_line_id
              JOIN dwms.customs_declarations declaration
                ON declaration.id = evidence.declaration_id
              JOIN dwms.unipass_messages official_message
                ON official_message.id = evidence.unipass_message_id
             WHERE coverage.shipment_trade_allocation_id = allocation_row.id
               AND dwms.customs_release_evidence_is_current(evidence.id)
               AND coverage.shipment_line_id = allocation_row.shipment_line_id
               AND evidence.trade_shipment_id = allocation_row.trade_shipment_id
               AND coverage.base_uom_code = allocation_row.base_uom_code
               AND (allocation_row.commercial_invoice_line_id IS NULL OR
                    declaration_line.commercial_invoice_line_id = allocation_row.commercial_invoice_line_id)
               AND coverage.item_id_snapshot = shipment_line.item_id
               AND coverage.country_of_origin_snapshot = shipment_line.country_of_origin
               AND coverage.hs_country_code_snapshot = shipment_line.hs_country_code
               AND coverage.hs_nomenclature_version_snapshot = shipment_line.hs_nomenclature_version
               AND coverage.hs_code_snapshot = shipment_line.hs_code
               AND coverage.base_uom_code = shipment_line.base_uom_code
               AND declaration_line.declaration_version_id = evidence.declaration_version_id
               AND declaration_line.item_id = shipment_line.item_id
               AND declaration_line.country_of_origin = shipment_line.country_of_origin
               AND declaration_line.hs_country_code = shipment_line.hs_country_code
               AND declaration_line.hs_nomenclature_version = shipment_line.hs_nomenclature_version
               AND declaration_line.hs_code = shipment_line.hs_code
               AND declaration_line.base_uom_code = shipment_line.base_uom_code
               AND evidence.evidence_type = ANY (allowed_evidence_types)
               AND declaration.workflow_status IN ('RELEASED','CLEARED')
               AND declaration.current_version_id = evidence.declaration_version_id
               AND official_message.direction = 'IN'
               AND official_message.recorded_status = 'ACCEPTED'
               AND official_message.customs_system_recorded_at IS NOT NULL;
            IF covered_base_quantity <> allocation_row.allocated_base_quantity THEN
                RAISE EXCEPTION 'Shipment trade allocation % declaration coverage % must equal allocated base quantity %',
                    allocation_row.id, covered_base_quantity, allocation_row.allocated_base_quantity
                    USING ERRCODE = '23514';
            END IF;
        END LOOP;
    END IF;

    IF allocation_count = 0 THEN
        evidence_count := 0;
        FOR official_evidence_row IN
            SELECT evidence.id, evidence.official_release_at
              FROM dwms.customs_release_evidence evidence
              JOIN dwms.customs_declarations declaration
                ON declaration.id = evidence.declaration_id
              JOIN dwms.unipass_messages official_message
                ON official_message.id = evidence.unipass_message_id
             WHERE evidence.tenant_id = p_tenant_id
               AND evidence.owner_partner_id = p_owner_partner_id
               AND evidence.shipment_id = p_shipment_id
               AND evidence.trade_shipment_id IS NULL
               AND dwms.customs_release_evidence_is_current(evidence.id)
               AND evidence.evidence_type = ANY (allowed_evidence_types)
               AND declaration.workflow_status IN ('RELEASED','CLEARED')
               AND declaration.current_version_id = evidence.declaration_version_id
               AND official_message.direction = 'IN'
               AND official_message.recorded_status = 'ACCEPTED'
               AND official_message.customs_system_recorded_at IS NOT NULL
               AND EXISTS (
                   SELECT 1 FROM dwms.customs_release_line_coverages coverage
                    WHERE coverage.customs_release_evidence_id = evidence.id
                      AND coverage.shipment_trade_allocation_id IS NULL
               )
             ORDER BY evidence.id
             FOR SHARE OF evidence, declaration, official_message
        LOOP
            evidence_count := evidence_count + 1;
            IF official_evidence_row.official_release_at > p_physical_event_at THEN
                RAISE EXCEPTION 'Shipment % physical event % precedes customs release %',
                    p_shipment_id, p_physical_event_at, official_evidence_row.official_release_at
                    USING ERRCODE = '23514';
            END IF;
            latest_required_release_at := GREATEST(
                COALESCE(latest_required_release_at, official_evidence_row.official_release_at),
                official_evidence_row.official_release_at
            );
        END LOOP;
        IF evidence_count = 0 THEN
            RAISE EXCEPTION 'Shipment % has no line-covered verified UNI-PASS release evidence',
                p_shipment_id USING ERRCODE = '23514';
        END IF;
        FOR line_row IN
            SELECT line.id, line.base_quantity
              FROM dwms.shipment_lines line
             WHERE line.tenant_id = p_tenant_id
               AND line.shipment_id = p_shipment_id
             ORDER BY line.id
             FOR SHARE
        LOOP
            SELECT COALESCE(sum(coverage.covered_base_quantity), 0)
              INTO covered_base_quantity
              FROM dwms.customs_release_line_coverages coverage
              JOIN dwms.customs_release_evidence evidence
                ON evidence.id = coverage.customs_release_evidence_id
              JOIN dwms.customs_declaration_lines declaration_line
                ON declaration_line.id = coverage.declaration_line_id
              JOIN dwms.shipment_lines current_shipment_line
                ON current_shipment_line.id = coverage.shipment_line_id
              JOIN dwms.customs_declarations declaration
                ON declaration.id = evidence.declaration_id
              JOIN dwms.unipass_messages official_message
                ON official_message.id = evidence.unipass_message_id
             WHERE coverage.shipment_line_id = line_row.id
               AND coverage.shipment_trade_allocation_id IS NULL
               AND coverage.item_id_snapshot = current_shipment_line.item_id
               AND coverage.country_of_origin_snapshot = current_shipment_line.country_of_origin
               AND coverage.hs_country_code_snapshot = current_shipment_line.hs_country_code
               AND coverage.hs_nomenclature_version_snapshot = current_shipment_line.hs_nomenclature_version
               AND coverage.hs_code_snapshot = current_shipment_line.hs_code
               AND coverage.base_uom_code = current_shipment_line.base_uom_code
               AND declaration_line.declaration_version_id = evidence.declaration_version_id
               AND declaration_line.item_id = current_shipment_line.item_id
               AND declaration_line.country_of_origin = current_shipment_line.country_of_origin
               AND declaration_line.hs_country_code = current_shipment_line.hs_country_code
               AND declaration_line.hs_nomenclature_version = current_shipment_line.hs_nomenclature_version
               AND declaration_line.hs_code = current_shipment_line.hs_code
               AND declaration_line.base_uom_code = current_shipment_line.base_uom_code
               AND evidence.shipment_id = p_shipment_id
               AND evidence.trade_shipment_id IS NULL
               AND dwms.customs_release_evidence_is_current(evidence.id)
               AND evidence.evidence_type = ANY (allowed_evidence_types)
               AND declaration.workflow_status IN ('RELEASED','CLEARED')
               AND declaration.current_version_id = evidence.declaration_version_id
               AND official_message.direction = 'IN'
               AND official_message.recorded_status = 'ACCEPTED'
               AND official_message.customs_system_recorded_at IS NOT NULL;
            IF covered_base_quantity <> line_row.base_quantity THEN
                RAISE EXCEPTION 'Direct declaration coverage % must equal shipment line % base quantity %',
                    covered_base_quantity, line_row.id, line_row.base_quantity
                    USING ERRCODE = '23514';
            END IF;
        END LOOP;
    END IF;

    RETURN latest_required_release_at;
END;
$function$;

REVOKE ALL ON FUNCTION dwms.require_shipment_customs_release(uuid,uuid,uuid,varchar,timestamptz)
    FROM PUBLIC;

CREATE OR REPLACE FUNCTION dwms.enforce_shipment_customs_release()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, dwms
AS $function$
DECLARE
    release_is_required boolean;
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF OLD.customs_release_required AND NOT NEW.customs_release_required THEN
            RAISE EXCEPTION 'Customs release requirement cannot be removed from shipment %', NEW.id
                USING ERRCODE = '23514';
        END IF;
        IF (OLD.status IN ('DISPATCHED','IN_TRANSIT','DELIVERED','PARTIALLY_DELIVERED','CLOSED')
            OR (OLD.status = 'EXCEPTION' AND OLD.actual_ship_at IS NOT NULL))
           AND (
               OLD.shipment_type IS DISTINCT FROM NEW.shipment_type
               OR OLD.customs_release_required IS DISTINCT FROM NEW.customs_release_required
           ) THEN
            RAISE EXCEPTION 'Customs classification is immutable after shipment % dispatch', NEW.id
                USING ERRCODE = '55000';
        END IF;
        IF OLD.customs_released_at IS DISTINCT FROM NEW.customs_released_at THEN
            RAISE EXCEPTION 'customs_released_at is system-maintained for shipment %', NEW.id
                USING ERRCODE = '55000';
        END IF;
    ELSIF NEW.customs_released_at IS NOT NULL THEN
        RAISE EXCEPTION 'customs_released_at is system-maintained for shipment %', NEW.id
            USING ERRCODE = '55000';
    END IF;

    release_is_required := NEW.customs_release_required OR NEW.shipment_type = 'EXPORT' OR EXISTS (
        SELECT 1
          FROM dwms.shipment_trade_allocations allocation
         WHERE allocation.tenant_id = NEW.tenant_id
           AND allocation.owner_partner_id = NEW.owner_partner_id
           AND allocation.shipment_id = NEW.id
    );
    IF release_is_required THEN
        NEW.customs_release_required := true;
    END IF;
    IF release_is_required
       AND (NEW.status IN ('DISPATCHED','IN_TRANSIT','DELIVERED','PARTIALLY_DELIVERED','CLOSED')
            OR (NEW.status = 'EXCEPTION' AND NEW.actual_ship_at IS NOT NULL)) THEN
        IF NEW.actual_ship_at IS NULL THEN
            RAISE EXCEPTION 'Customs-controlled shipment % requires actual_ship_at before dispatch', NEW.id
                USING ERRCODE = '23514';
        END IF;
        NEW.customs_released_at := dwms.require_shipment_customs_release(
            NEW.tenant_id, NEW.owner_partner_id, NEW.id, NEW.shipment_type, NEW.actual_ship_at
        );
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION dwms.enforce_shipping_confirmation_customs_release()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, dwms
AS $function$
DECLARE
    shipment_row dwms.shipments%ROWTYPE;
    release_is_required boolean;
BEGIN
    SELECT * INTO shipment_row
      FROM dwms.shipments
     WHERE id = NEW.shipment_id
     FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Shipping confirmation references unknown shipment %', NEW.shipment_id
            USING ERRCODE = '23503';
    END IF;
    release_is_required := shipment_row.customs_release_required
        OR shipment_row.shipment_type = 'EXPORT'
        OR EXISTS (
            SELECT 1
              FROM dwms.shipment_trade_allocations allocation
             WHERE allocation.tenant_id = shipment_row.tenant_id
               AND allocation.owner_partner_id = shipment_row.owner_partner_id
               AND allocation.shipment_id = shipment_row.id
        );
    IF release_is_required THEN
        PERFORM dwms.require_shipment_customs_release(
            shipment_row.tenant_id, shipment_row.owner_partner_id,
            shipment_row.id, shipment_row.shipment_type, NEW.confirmed_at
        );
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION dwms.enforce_load_customs_release()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, dwms
AS $function$
DECLARE
    shipment_row record;
BEGIN
    IF NEW.status IN ('DISPATCHED','CLOSED')
       AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM NEW.status) THEN
        IF NEW.actual_departure_at IS NULL THEN
            RAISE EXCEPTION 'Dispatched load % requires actual_departure_at', NEW.id
                USING ERRCODE = '23514';
        END IF;
        FOR shipment_row IN
            SELECT shipment.tenant_id, shipment.owner_partner_id, shipment.id, shipment.shipment_type
              FROM dwms.load_shipments allocation
              JOIN dwms.shipments shipment ON shipment.id = allocation.shipment_id
             WHERE allocation.load_id = NEW.id
               AND (
                   shipment.customs_release_required
                   OR shipment.shipment_type = 'EXPORT'
                   OR EXISTS (
                       SELECT 1
                         FROM dwms.shipment_trade_allocations trade_allocation
                        WHERE trade_allocation.tenant_id = shipment.tenant_id
                          AND trade_allocation.owner_partner_id = shipment.owner_partner_id
                          AND trade_allocation.shipment_id = shipment.id
                   )
               )
             ORDER BY shipment.id
             FOR SHARE OF shipment
        LOOP
            PERFORM dwms.require_shipment_customs_release(
                shipment_row.tenant_id, shipment_row.owner_partner_id,
                shipment_row.id, shipment_row.shipment_type, NEW.actual_departure_at
            );
        END LOOP;
    END IF;
    RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION dwms.enforce_shipment_customs_release() FROM PUBLIC;
REVOKE ALL ON FUNCTION dwms.enforce_shipping_confirmation_customs_release() FROM PUBLIC;
REVOKE ALL ON FUNCTION dwms.enforce_load_customs_release() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_enforce_shipment_customs_release ON dwms.shipments;
CREATE TRIGGER trg_enforce_shipment_customs_release
    BEFORE INSERT OR UPDATE OF status, shipment_type, customs_release_required,
        customs_released_at, actual_ship_at
    ON dwms.shipments
    FOR EACH ROW EXECUTE PROCEDURE dwms.enforce_shipment_customs_release();

DROP TRIGGER IF EXISTS trg_enforce_shipping_confirmation_customs_release
    ON dwms.shipping_confirmations;
CREATE TRIGGER trg_enforce_shipping_confirmation_customs_release
    BEFORE INSERT OR UPDATE OF shipment_id, confirmed_at
    ON dwms.shipping_confirmations
    FOR EACH ROW EXECUTE PROCEDURE dwms.enforce_shipping_confirmation_customs_release();

DROP TRIGGER IF EXISTS trg_enforce_load_customs_release ON dwms.loads;
CREATE TRIGGER trg_enforce_load_customs_release
    BEFORE INSERT OR UPDATE OF status, actual_departure_at
    ON dwms.loads
    FOR EACH ROW EXECUTE PROCEDURE dwms.enforce_load_customs_release();

CREATE OR REPLACE FUNCTION dwms.guard_shipment_trade_allocation_lifecycle()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, dwms
AS $function$
DECLARE
    target_shipment_id uuid;
    shipment_row record;
    shipment_line_row record;
    excluded_allocation_id uuid;
    allocated_quantity_total numeric(24,8);
    allocated_base_total numeric(24,8);
    item_base_uom_code varchar(20);
BEGIN
    IF TG_OP <> 'INSERT' AND EXISTS (
        SELECT 1
          FROM dwms.customs_release_line_coverages coverage
         WHERE coverage.shipment_trade_allocation_id = OLD.id
    ) THEN
        RAISE EXCEPTION 'Customs-covered shipment trade allocation % is immutable', OLD.id
            USING ERRCODE = '55000';
    END IF;
    FOR target_shipment_id IN
        SELECT DISTINCT shipment_id
          FROM (VALUES
              (CASE WHEN TG_OP <> 'INSERT' THEN OLD.shipment_id END),
              (CASE WHEN TG_OP <> 'DELETE' THEN NEW.shipment_id END)
          ) AS target(shipment_id)
         WHERE shipment_id IS NOT NULL
         ORDER BY shipment_id
    LOOP
        SELECT id, tenant_id, owner_partner_id, status
          INTO shipment_row
          FROM dwms.shipments
         WHERE id = target_shipment_id
         FOR UPDATE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Unknown shipment % for trade allocation', target_shipment_id
                USING ERRCODE = '23503';
        END IF;
        IF shipment_row.status IN ('DISPATCHED','IN_TRANSIT','DELIVERED','PARTIALLY_DELIVERED','EXCEPTION','CLOSED')
           OR EXISTS (
               SELECT 1 FROM dwms.shipping_confirmations confirmation
                WHERE confirmation.shipment_id = target_shipment_id
           )
           OR EXISTS (
               SELECT 1
                 FROM dwms.load_shipments load_allocation
                 JOIN dwms.loads load ON load.id = load_allocation.load_id
                WHERE load_allocation.shipment_id = target_shipment_id
                  AND (load.status IN ('LOADED','SEALED','DISPATCHED','CLOSED')
                       OR load.actual_departure_at IS NOT NULL)
           ) THEN
            RAISE EXCEPTION 'Trade allocations are frozen after physical processing starts for shipment %',
                target_shipment_id USING ERRCODE = '55000';
        END IF;
    END LOOP;

    IF TG_OP <> 'DELETE' THEN
        SELECT id, tenant_id, owner_partner_id, status
          INTO shipment_row
          FROM dwms.shipments
         WHERE id = NEW.shipment_id;
        IF shipment_row.tenant_id <> NEW.tenant_id
           OR shipment_row.owner_partner_id <> NEW.owner_partner_id THEN
            RAISE EXCEPTION 'Shipment trade allocation tenant/owner scope mismatch'
                USING ERRCODE = '23514';
        END IF;
        SELECT tenant_id, shipment_id, item_id, shipped_quantity, base_quantity,
               uom_code, base_uom_code
          INTO shipment_line_row
          FROM dwms.shipment_lines
         WHERE id = NEW.shipment_line_id
         FOR UPDATE;
        IF NOT FOUND OR shipment_line_row.tenant_id <> NEW.tenant_id
           OR shipment_line_row.shipment_id <> NEW.shipment_id THEN
            RAISE EXCEPTION 'Shipment line % does not belong to shipment %',
                NEW.shipment_line_id, NEW.shipment_id USING ERRCODE = '23514';
        END IF;
        SELECT base_uom_code INTO item_base_uom_code
          FROM dwms.items
         WHERE id = shipment_line_row.item_id
         FOR SHARE;
        IF NEW.uom_code <> shipment_line_row.uom_code
           OR NEW.base_uom_code <> shipment_line_row.base_uom_code
           OR NEW.base_uom_code <> item_base_uom_code THEN
            RAISE EXCEPTION 'Shipment trade allocation units do not match shipment line/item base units'
                USING ERRCODE = '23514';
        END IF;
        excluded_allocation_id := NULL;
        IF TG_OP = 'UPDATE' THEN
            excluded_allocation_id := OLD.id;
        END IF;
        SELECT COALESCE(sum(allocated_quantity), 0),
               COALESCE(sum(allocated_base_quantity), 0)
          INTO allocated_quantity_total, allocated_base_total
          FROM dwms.shipment_trade_allocations allocation
         WHERE allocation.shipment_line_id = NEW.shipment_line_id
           AND (excluded_allocation_id IS NULL OR allocation.id <> excluded_allocation_id);
        IF allocated_quantity_total + NEW.allocated_quantity > shipment_line_row.shipped_quantity
           OR allocated_base_total + NEW.allocated_base_quantity > shipment_line_row.base_quantity THEN
            RAISE EXCEPTION 'Trade allocations exceed shipment line % quantity', NEW.shipment_line_id
                USING ERRCODE = '23514';
        END IF;
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION dwms.guard_load_shipment_lifecycle()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, dwms
AS $function$
DECLARE
    target_load_id uuid;
    target_shipment_id uuid;
    load_row record;
    shipment_row record;
BEGIN
    FOR target_load_id IN
        SELECT DISTINCT load_id
          FROM (VALUES
              (CASE WHEN TG_OP <> 'INSERT' THEN OLD.load_id END),
              (CASE WHEN TG_OP <> 'DELETE' THEN NEW.load_id END)
          ) AS target(load_id)
         WHERE load_id IS NOT NULL
         ORDER BY load_id
    LOOP
        SELECT id, tenant_id, status, actual_departure_at
          INTO load_row FROM dwms.loads WHERE id = target_load_id FOR UPDATE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Unknown load % for shipment allocation', target_load_id
                USING ERRCODE = '23503';
        END IF;
        IF load_row.status IN ('LOADED','SEALED','DISPATCHED','CLOSED')
           OR load_row.actual_departure_at IS NOT NULL THEN
            RAISE EXCEPTION 'Load shipment allocation is frozen for load % in status %',
                target_load_id, load_row.status USING ERRCODE = '55000';
        END IF;
    END LOOP;

    FOR target_shipment_id IN
        SELECT DISTINCT shipment_id
          FROM (VALUES
              (CASE WHEN TG_OP <> 'INSERT' THEN OLD.shipment_id END),
              (CASE WHEN TG_OP <> 'DELETE' THEN NEW.shipment_id END)
          ) AS target(shipment_id)
         WHERE shipment_id IS NOT NULL
         ORDER BY shipment_id
    LOOP
        SELECT id, tenant_id, status
          INTO shipment_row FROM dwms.shipments WHERE id = target_shipment_id FOR UPDATE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Unknown shipment % for load allocation', target_shipment_id
                USING ERRCODE = '23503';
        END IF;
        IF shipment_row.status IN ('DISPATCHED','IN_TRANSIT','DELIVERED','PARTIALLY_DELIVERED','EXCEPTION','CLOSED') THEN
            RAISE EXCEPTION 'Load allocation is frozen after shipment % dispatch', target_shipment_id
                USING ERRCODE = '55000';
        END IF;
    END LOOP;

    IF TG_OP <> 'DELETE' THEN
        SELECT id, tenant_id, status, actual_departure_at
          INTO load_row FROM dwms.loads WHERE id = NEW.load_id;
        SELECT id, tenant_id, status
          INTO shipment_row FROM dwms.shipments WHERE id = NEW.shipment_id;
        IF load_row.tenant_id <> NEW.tenant_id OR shipment_row.tenant_id <> NEW.tenant_id THEN
            RAISE EXCEPTION 'Load shipment allocation tenant scope mismatch'
                USING ERRCODE = '23514';
        END IF;
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION dwms.guard_shipment_trade_allocation_lifecycle() FROM PUBLIC;
REVOKE ALL ON FUNCTION dwms.guard_load_shipment_lifecycle() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_guard_shipment_trade_allocation_lifecycle
    ON dwms.shipment_trade_allocations;
CREATE TRIGGER trg_guard_shipment_trade_allocation_lifecycle
    BEFORE INSERT OR UPDATE OR DELETE ON dwms.shipment_trade_allocations
    FOR EACH ROW EXECUTE PROCEDURE dwms.guard_shipment_trade_allocation_lifecycle();

DROP TRIGGER IF EXISTS trg_guard_load_shipment_lifecycle ON dwms.load_shipments;
CREATE TRIGGER trg_guard_load_shipment_lifecycle
    BEFORE INSERT OR UPDATE OR DELETE ON dwms.load_shipments
    FOR EACH ROW EXECUTE PROCEDURE dwms.guard_load_shipment_lifecycle();

COMMENT ON FUNCTION dwms.require_shipment_customs_release(uuid,uuid,uuid,varchar,timestamptz) IS
    'Locks and verifies official RELEASED/CLEARED declaration evidence before a customs-controlled physical shipment event.';

CREATE TABLE IF NOT EXISTS dwms.customs_declaration_parties (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL,
    owner_partner_id uuid NOT NULL,
    declaration_version_id uuid NOT NULL,
    party_role varchar(50) NOT NULL,
    partner_id uuid REFERENCES dwms.business_partners(id),
    party_name_snapshot varchar(300) NOT NULL,
    business_identifier_type varchar(80),
    business_identifier_snapshot varchar(200),
    personal_identifier_encrypted text,
    personal_identifier_hash char(64),
    personal_identifier_masked varchar(100),
    country_code char(2) REFERENCES dwms.countries(country_code),
    address_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
    contact_snapshot_masked jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (declaration_version_id, party_role),
    FOREIGN KEY (tenant_id, owner_partner_id, declaration_version_id)
        REFERENCES dwms.customs_declaration_versions(tenant_id, owner_partner_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_dwms_customs_party_hash CHECK (
        personal_identifier_hash IS NULL OR personal_identifier_hash ~ '^[0-9A-Fa-f]{64}$'
    )
);

CREATE TABLE IF NOT EXISTS dwms.customs_declaration_references (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL,
    owner_partner_id uuid NOT NULL,
    declaration_version_id uuid NOT NULL,
    reference_type varchar(100) NOT NULL,
    reference_value_raw varchar(500) NOT NULL,
    reference_value_normalized varchar(500),
    issuing_authority varchar(200),
    issued_on date,
    expires_on date,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (declaration_version_id, reference_type, reference_value_raw),
    FOREIGN KEY (tenant_id, owner_partner_id, declaration_version_id)
        REFERENCES dwms.customs_declaration_versions(tenant_id, owner_partner_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_dwms_customs_reference_dates CHECK (expires_on IS NULL OR issued_on IS NULL OR expires_on >= issued_on)
);

CREATE TABLE IF NOT EXISTS dwms.customs_declaration_lines (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL,
    owner_partner_id uuid NOT NULL,
    declaration_version_id uuid NOT NULL,
    line_no integer NOT NULL,
    item_id uuid REFERENCES dwms.items(id),
    commercial_invoice_line_id uuid REFERENCES dwms.commercial_invoice_lines(id),
    goods_description varchar(2000) NOT NULL,
    model_specification varchar(1000),
    hs_country_code char(2),
    hs_nomenclature_version varchar(20),
    hs_code varchar(20),
    country_of_origin char(2) REFERENCES dwms.countries(country_code),
    origin_criterion_code varchar(100),
    quantity_1 numeric(24,8),
    uom_1_code varchar(20) REFERENCES dwms.units_of_measure(uom_code),
    quantity_2 numeric(24,8),
    uom_2_code varchar(20) REFERENCES dwms.units_of_measure(uom_code),
    declared_base_quantity numeric(24,8),
    base_uom_code varchar(20) REFERENCES dwms.units_of_measure(uom_code),
    package_count numeric(20,4),
    package_type_code varchar(50),
    net_weight numeric(24,8),
    gross_weight numeric(24,8),
    weight_uom_code varchar(20) REFERENCES dwms.units_of_measure(uom_code),
    invoice_unit_price numeric(24,8),
    invoice_amount numeric(24,4),
    invoice_currency_code char(3) REFERENCES dwms.currencies(currency_code),
    customs_value numeric(24,4),
    customs_value_currency_code char(3) REFERENCES dwms.currencies(currency_code),
    valuation_method_code varchar(100),
    tariff_rate numeric(12,8),
    preference_code varchar(100),
    duty_relief_code varchar(100),
    customs_status_code varchar(100),
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (declaration_version_id, line_no),
    UNIQUE (declaration_version_id, id),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, owner_partner_id, id),
    FOREIGN KEY (tenant_id, owner_partner_id, declaration_version_id)
        REFERENCES dwms.customs_declaration_versions(tenant_id, owner_partner_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (hs_country_code, hs_nomenclature_version, hs_code)
        REFERENCES dwms.hs_codes(country_code, nomenclature_version, hs_code),
    CONSTRAINT ck_dwms_customs_line_no CHECK (line_no > 0),
    CONSTRAINT ck_dwms_customs_line_quantities CHECK (
        (quantity_1 IS NULL OR quantity_1 >= 0) AND (quantity_2 IS NULL OR quantity_2 >= 0) AND
        (declared_base_quantity IS NULL OR declared_base_quantity > 0) AND
        (package_count IS NULL OR package_count >= 0) AND (net_weight IS NULL OR net_weight >= 0) AND
        (gross_weight IS NULL OR gross_weight >= 0) AND
        (gross_weight IS NULL OR net_weight IS NULL OR gross_weight >= net_weight)
    ),
    CONSTRAINT ck_dwms_customs_line_base_quantity CHECK (
        (declared_base_quantity IS NULL AND base_uom_code IS NULL) OR
        (declared_base_quantity IS NOT NULL AND base_uom_code IS NOT NULL)
    ),
    CONSTRAINT ck_dwms_customs_line_amounts CHECK (
        (invoice_unit_price IS NULL OR invoice_unit_price >= 0) AND
        (invoice_amount IS NULL OR invoice_amount >= 0) AND
        (customs_value IS NULL OR customs_value >= 0) AND
        (tariff_rate IS NULL OR tariff_rate >= 0)
    )
);

CREATE TABLE IF NOT EXISTS dwms.customs_declaration_line_details (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL,
    owner_partner_id uuid NOT NULL,
    declaration_version_id uuid NOT NULL,
    declaration_line_id uuid NOT NULL,
    detail_group varchar(100) NOT NULL,
    detail_code varchar(150) NOT NULL,
    detail_value_text text,
    detail_value_number numeric(30,12),
    detail_value_date date,
    detail_value_json jsonb,
    sequence_no integer NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (declaration_line_id, detail_group, detail_code, sequence_no),
    FOREIGN KEY (tenant_id, owner_partner_id, declaration_version_id)
        REFERENCES dwms.customs_declaration_versions(tenant_id, owner_partner_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, owner_partner_id, declaration_line_id)
        REFERENCES dwms.customs_declaration_lines(tenant_id, owner_partner_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (declaration_version_id, declaration_line_id)
        REFERENCES dwms.customs_declaration_lines(declaration_version_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_dwms_customs_line_detail_value CHECK (
        num_nonnulls(detail_value_text, detail_value_number, detail_value_date, detail_value_json) = 1
    ),
    CONSTRAINT ck_dwms_customs_line_detail_seq CHECK (sequence_no > 0)
);

CREATE TABLE IF NOT EXISTS dwms.customs_declaration_requirements (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL,
    owner_partner_id uuid NOT NULL,
    declaration_version_id uuid NOT NULL,
    declaration_line_id uuid REFERENCES dwms.customs_declaration_lines(id),
    requirement_type varchar(100) NOT NULL,
    requirement_code varchar(150),
    permit_license_no varchar(300),
    issuing_authority varchar(250),
    issued_on date,
    expires_on date,
    required_status varchar(30) NOT NULL DEFAULT 'REQUIRED',
    waiver_reason text,
    created_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (tenant_id, owner_partner_id, declaration_version_id)
        REFERENCES dwms.customs_declaration_versions(tenant_id, owner_partner_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (declaration_version_id, declaration_line_id)
        REFERENCES dwms.customs_declaration_lines(declaration_version_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_dwms_customs_requirement_status CHECK (required_status IN (
        'REQUIRED','SUBMITTED','ACCEPTED','REJECTED','WAIVED','NOT_APPLICABLE'
    )),
    CONSTRAINT ck_dwms_customs_requirement_dates CHECK (expires_on IS NULL OR issued_on IS NULL OR expires_on >= issued_on)
);

CREATE TABLE IF NOT EXISTS dwms.customs_declaration_taxes (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL,
    owner_partner_id uuid NOT NULL,
    declaration_version_id uuid NOT NULL,
    declaration_line_id uuid REFERENCES dwms.customs_declaration_lines(id),
    tax_sequence integer NOT NULL,
    tax_type_code varchar(100) NOT NULL,
    tax_base_amount numeric(24,4) NOT NULL DEFAULT 0,
    tax_rate numeric(12,8),
    assessed_amount numeric(24,4) NOT NULL DEFAULT 0,
    relieved_amount numeric(24,4) NOT NULL DEFAULT 0,
    payable_amount numeric(24,4) NOT NULL DEFAULT 0,
    currency_code char(3) NOT NULL REFERENCES dwms.currencies(currency_code),
    relief_code varchar(100),
    assessment_reference varchar(300),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (declaration_version_id, declaration_line_id, tax_sequence),
    UNIQUE (tenant_id, owner_partner_id, id),
    FOREIGN KEY (tenant_id, owner_partner_id, declaration_version_id)
        REFERENCES dwms.customs_declaration_versions(tenant_id, owner_partner_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (declaration_version_id, declaration_line_id)
        REFERENCES dwms.customs_declaration_lines(declaration_version_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_dwms_customs_tax_seq CHECK (tax_sequence > 0),
    CONSTRAINT ck_dwms_customs_tax_amount CHECK (
        tax_base_amount >= 0 AND (tax_rate IS NULL OR tax_rate >= 0) AND
        assessed_amount >= 0 AND relieved_amount >= 0 AND payable_amount >= 0 AND
        relieved_amount <= assessed_amount AND payable_amount <= assessed_amount
    )
);

CREATE TABLE IF NOT EXISTS dwms.customs_declaration_containers (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL,
    owner_partner_id uuid NOT NULL,
    declaration_version_id uuid NOT NULL,
    trade_container_id uuid NOT NULL REFERENCES dwms.trade_containers(id),
    declaration_line_id uuid REFERENCES dwms.customs_declaration_lines(id),
    package_count numeric(20,4),
    gross_weight numeric(24,8),
    weight_uom_code varchar(20) REFERENCES dwms.units_of_measure(uom_code),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (declaration_version_id, trade_container_id, declaration_line_id),
    FOREIGN KEY (tenant_id, owner_partner_id, declaration_version_id)
        REFERENCES dwms.customs_declaration_versions(tenant_id, owner_partner_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (declaration_version_id, declaration_line_id)
        REFERENCES dwms.customs_declaration_lines(declaration_version_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_dwms_customs_container_qty CHECK (
        (package_count IS NULL OR package_count >= 0) AND (gross_weight IS NULL OR gross_weight >= 0)
    )
);

CREATE TABLE IF NOT EXISTS dwms.customs_declaration_inspections (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL,
    owner_partner_id uuid NOT NULL,
    declaration_id uuid NOT NULL,
    declaration_version_id uuid,
    inspection_no varchar(200),
    inspection_type_code varchar(100) NOT NULL,
    selection_reason_code varchar(100),
    scheduled_at timestamptz,
    started_at timestamptz,
    completed_at timestamptz,
    location_text varchar(300),
    result_code varchar(100),
    result_summary_masked text,
    inspector_name_masked varchar(150),
    status varchar(20) NOT NULL DEFAULT 'SELECTED',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, inspection_no),
    FOREIGN KEY (tenant_id, owner_partner_id, declaration_id)
        REFERENCES dwms.customs_declarations(tenant_id, owner_partner_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (declaration_id, declaration_version_id)
        REFERENCES dwms.customs_declaration_versions(declaration_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_dwms_customs_inspection_status CHECK (status IN (
        'SELECTED','SCHEDULED','IN_PROGRESS','COMPLETED','WAIVED','CANCELLED'
    )),
    CONSTRAINT ck_dwms_customs_inspection_dates CHECK (
        (started_at IS NULL OR scheduled_at IS NULL OR started_at >= scheduled_at) AND
        (completed_at IS NULL OR started_at IS NULL OR completed_at >= started_at)
    )
);

CREATE TABLE IF NOT EXISTS dwms.customs_declaration_relations (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    owner_partner_id uuid NOT NULL REFERENCES dwms.business_partners(id),
    source_declaration_id uuid NOT NULL REFERENCES dwms.customs_declarations(id),
    target_declaration_id uuid NOT NULL REFERENCES dwms.customs_declarations(id),
    relation_type varchar(50) NOT NULL,
    relation_reference varchar(300),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (source_declaration_id, target_declaration_id, relation_type),
    FOREIGN KEY (tenant_id, owner_partner_id, source_declaration_id)
        REFERENCES dwms.customs_declarations(tenant_id, owner_partner_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, owner_partner_id, target_declaration_id)
        REFERENCES dwms.customs_declarations(tenant_id, owner_partner_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_dwms_customs_relation_self CHECK (source_declaration_id <> target_declaration_id),
    CONSTRAINT ck_dwms_customs_relation_type CHECK (relation_type IN (
        'CORRECTS','WITHDRAWS','REPLACES','RETURNS','SPLITS','MERGES','PRECEDES','RELATED'
    ))
);

CREATE TABLE IF NOT EXISTS dwms.customs_declaration_events (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL,
    owner_partner_id uuid NOT NULL,
    declaration_id uuid NOT NULL,
    declaration_version_id uuid,
    sequence_no bigint NOT NULL,
    event_type varchar(100) NOT NULL,
    from_status varchar(30),
    to_status varchar(30),
    event_code varchar(150),
    event_reference varchar(300),
    occurred_at timestamptz NOT NULL,
    customs_system_recorded_at timestamptz,
    recorded_at timestamptz NOT NULL DEFAULT now(),
    actor_user_id uuid REFERENCES dwms.users(id),
    source_system_id uuid REFERENCES dwms.external_systems(id),
    detail_masked jsonb NOT NULL DEFAULT '{}'::jsonb,
    UNIQUE (declaration_id, sequence_no),
    FOREIGN KEY (tenant_id, owner_partner_id, declaration_id)
        REFERENCES dwms.customs_declarations(tenant_id, owner_partner_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (declaration_id, declaration_version_id)
        REFERENCES dwms.customs_declaration_versions(declaration_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_dwms_customs_event_seq CHECK (sequence_no > 0)
);

CREATE TABLE IF NOT EXISTS dwms.customs_documents (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL,
    owner_partner_id uuid NOT NULL,
    declaration_id uuid NOT NULL,
    declaration_version_id uuid,
    document_type_code varchar(120) NOT NULL,
    document_no varchar(300),
    revision_no integer NOT NULL DEFAULT 1,
    issuing_authority varchar(250),
    issued_on date,
    expires_on date,
    trade_document_id uuid REFERENCES dwms.trade_documents(id),
    file_id uuid REFERENCES dwms.files(id),
    object_uri text,
    object_sha256 char(64),
    byte_size bigint,
    media_type varchar(150),
    submission_status varchar(30) NOT NULL DEFAULT 'PREPARED',
    retention_until date,
    legal_hold boolean NOT NULL DEFAULT false,
    created_by uuid REFERENCES dwms.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (declaration_id, document_type_code, document_no, revision_no),
    UNIQUE (tenant_id, owner_partner_id, id),
    FOREIGN KEY (tenant_id, owner_partner_id, declaration_id)
        REFERENCES dwms.customs_declarations(tenant_id, owner_partner_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (declaration_id, declaration_version_id)
        REFERENCES dwms.customs_declaration_versions(declaration_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_dwms_customs_document_revision CHECK (revision_no > 0),
    CONSTRAINT ck_dwms_customs_document_source CHECK (
        trade_document_id IS NOT NULL OR file_id IS NOT NULL OR object_uri IS NOT NULL
    ),
    CONSTRAINT ck_dwms_customs_document_hash CHECK (object_sha256 IS NULL OR object_sha256 ~ '^[0-9A-Fa-f]{64}$'),
    CONSTRAINT ck_dwms_customs_document_size CHECK (byte_size IS NULL OR byte_size >= 0),
    CONSTRAINT ck_dwms_customs_document_dates CHECK (expires_on IS NULL OR issued_on IS NULL OR expires_on >= issued_on),
    CONSTRAINT ck_dwms_customs_document_status CHECK (submission_status IN (
        'PREPARED','SUBMITTED','ACCEPTED','REJECTED','SUPERSEDED','WITHDRAWN'
    ))
);

CREATE TABLE IF NOT EXISTS dwms.customs_document_links (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    customs_document_id uuid NOT NULL REFERENCES dwms.customs_documents(id) ON DELETE RESTRICT,
    declaration_version_id uuid,
    declaration_line_id uuid REFERENCES dwms.customs_declaration_lines(id),
    requirement_id uuid REFERENCES dwms.customs_declaration_requirements(id),
    relation_type varchar(50) NOT NULL DEFAULT 'SUPPORTS',
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_dwms_customs_document_link_target CHECK (
        num_nonnulls(declaration_version_id, declaration_line_id, requirement_id) = 1
    )
);

CREATE TABLE IF NOT EXISTS dwms.customs_duty_payments (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL,
    owner_partner_id uuid NOT NULL,
    declaration_id uuid NOT NULL,
    payment_notice_no varchar(300),
    assessment_reference varchar(300),
    payer_partner_id uuid REFERENCES dwms.business_partners(id),
    payment_method_code varchar(100),
    bank_reference_masked varchar(200),
    currency_code char(3) NOT NULL REFERENCES dwms.currencies(currency_code),
    assessed_amount numeric(24,4) NOT NULL,
    paid_amount numeric(24,4) NOT NULL DEFAULT 0,
    refunded_amount numeric(24,4) NOT NULL DEFAULT 0,
    due_on date,
    paid_at timestamptz,
    status varchar(20) NOT NULL DEFAULT 'ASSESSED',
    receipt_document_id uuid REFERENCES dwms.customs_documents(id),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, payment_notice_no),
    UNIQUE (tenant_id, owner_partner_id, id),
    FOREIGN KEY (tenant_id, owner_partner_id, declaration_id)
        REFERENCES dwms.customs_declarations(tenant_id, owner_partner_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_dwms_customs_payment_amount CHECK (
        assessed_amount >= 0 AND paid_amount >= 0 AND refunded_amount >= 0 AND
        paid_amount <= assessed_amount AND refunded_amount <= paid_amount
    ),
    CONSTRAINT ck_dwms_customs_payment_status CHECK (status IN (
        'ASSESSED','PARTIALLY_PAID','PAID','OVERDUE','REFUND_PENDING','PARTIALLY_REFUNDED','REFUNDED','VOID'
    ))
);

CREATE TABLE IF NOT EXISTS dwms.customs_duty_payment_allocations (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    owner_partner_id uuid NOT NULL REFERENCES dwms.business_partners(id),
    declaration_id uuid NOT NULL,
    declaration_version_id uuid NOT NULL,
    customs_duty_payment_id uuid NOT NULL,
    declaration_tax_id uuid NOT NULL,
    currency_code char(3) NOT NULL REFERENCES dwms.currencies(currency_code),
    allocated_amount numeric(24,4) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (customs_duty_payment_id, declaration_tax_id),
    UNIQUE (tenant_id, owner_partner_id, id),
    FOREIGN KEY (tenant_id, owner_partner_id, declaration_id)
        REFERENCES dwms.customs_declarations(tenant_id, owner_partner_id, id),
    FOREIGN KEY (declaration_id, declaration_version_id)
        REFERENCES dwms.customs_declaration_versions(declaration_id, id),
    FOREIGN KEY (tenant_id, owner_partner_id, customs_duty_payment_id)
        REFERENCES dwms.customs_duty_payments(tenant_id, owner_partner_id, id),
    FOREIGN KEY (tenant_id, owner_partner_id, declaration_tax_id)
        REFERENCES dwms.customs_declaration_taxes(tenant_id, owner_partner_id, id),
    CONSTRAINT ck_dwms_customs_payment_allocation_amount CHECK (allocated_amount > 0)
);

CREATE TABLE IF NOT EXISTS dwms.customs_refund_claims (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL,
    owner_partner_id uuid NOT NULL,
    declaration_id uuid NOT NULL,
    refund_claim_no varchar(200) NOT NULL,
    claim_type_code varchar(100) NOT NULL,
    claimant_partner_id uuid REFERENCES dwms.business_partners(id),
    currency_code char(3) NOT NULL REFERENCES dwms.currencies(currency_code),
    claimed_amount numeric(24,4) NOT NULL,
    approved_amount numeric(24,4) NOT NULL DEFAULT 0,
    paid_amount numeric(24,4) NOT NULL DEFAULT 0,
    filed_at timestamptz,
    decided_at timestamptz,
    paid_at timestamptz,
    status varchar(30) NOT NULL DEFAULT 'DRAFT',
    decision_reason_masked text,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, refund_claim_no),
    UNIQUE (tenant_id, owner_partner_id, id),
    FOREIGN KEY (tenant_id, owner_partner_id, declaration_id)
        REFERENCES dwms.customs_declarations(tenant_id, owner_partner_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_dwms_customs_refund_amount CHECK (
        claimed_amount > 0 AND approved_amount >= 0 AND paid_amount >= 0 AND
        approved_amount <= claimed_amount AND paid_amount <= approved_amount
    ),
    CONSTRAINT ck_dwms_customs_refund_status CHECK (status IN (
        'DRAFT','FILED','UNDER_REVIEW','APPROVED','PARTIALLY_APPROVED','REJECTED',
        'PARTIALLY_PAID','PAID','CANCELLED'
    )),
    CONSTRAINT ck_dwms_customs_refund_dates CHECK (
        (decided_at IS NULL OR filed_at IS NULL OR decided_at >= filed_at) AND
        (paid_at IS NULL OR decided_at IS NULL OR paid_at >= decided_at)
    )
);

CREATE TABLE IF NOT EXISTS dwms.customs_refund_allocations (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    owner_partner_id uuid NOT NULL REFERENCES dwms.business_partners(id),
    declaration_id uuid NOT NULL,
    declaration_version_id uuid,
    refund_claim_id uuid NOT NULL,
    customs_duty_payment_id uuid,
    declaration_tax_id uuid,
    currency_code char(3) NOT NULL REFERENCES dwms.currencies(currency_code),
    allocated_amount numeric(24,4) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, owner_partner_id, id),
    FOREIGN KEY (tenant_id, owner_partner_id, declaration_id)
        REFERENCES dwms.customs_declarations(tenant_id, owner_partner_id, id),
    FOREIGN KEY (declaration_id, declaration_version_id)
        REFERENCES dwms.customs_declaration_versions(declaration_id, id),
    FOREIGN KEY (tenant_id, owner_partner_id, refund_claim_id)
        REFERENCES dwms.customs_refund_claims(tenant_id, owner_partner_id, id),
    FOREIGN KEY (tenant_id, owner_partner_id, customs_duty_payment_id)
        REFERENCES dwms.customs_duty_payments(tenant_id, owner_partner_id, id),
    FOREIGN KEY (tenant_id, owner_partner_id, declaration_tax_id)
        REFERENCES dwms.customs_declaration_taxes(tenant_id, owner_partner_id, id),
    CONSTRAINT ck_dwms_customs_refund_allocation_target CHECK (
        (customs_duty_payment_id IS NOT NULL AND declaration_tax_id IS NULL
            AND declaration_version_id IS NULL) OR
        (customs_duty_payment_id IS NULL AND declaration_tax_id IS NOT NULL
            AND declaration_version_id IS NOT NULL)
    ),
    CONSTRAINT ck_dwms_customs_refund_allocation_amount CHECK (allocated_amount > 0)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_dwms_customs_refund_claim_payment
    ON dwms.customs_refund_allocations (refund_claim_id, customs_duty_payment_id)
    WHERE customs_duty_payment_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS ux_dwms_customs_refund_claim_tax
    ON dwms.customs_refund_allocations (refund_claim_id, declaration_tax_id)
    WHERE declaration_tax_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS ix_dwms_customs_payment_allocation_tax
    ON dwms.customs_duty_payment_allocations (declaration_tax_id, customs_duty_payment_id);

CREATE INDEX IF NOT EXISTS ix_dwms_customs_refund_allocation_target
    ON dwms.customs_refund_allocations (customs_duty_payment_id, declaration_tax_id, refund_claim_id);

CREATE OR REPLACE FUNCTION dwms.validate_customs_duty_payment_allocation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, dwms
AS $function$
DECLARE
    payment_row dwms.customs_duty_payments%ROWTYPE;
    tax_row dwms.customs_declaration_taxes%ROWTYPE;
    version_declaration_id uuid;
    declaration_current_version_id uuid;
    declaration_status varchar(30);
    version_sealed_at timestamptz;
    payment_allocated numeric(24,4);
    tax_allocated numeric(24,4);
BEGIN
    PERFORM pg_advisory_xact_lock(hashtext('dwms-customs-finance:' || NEW.declaration_id::text));
    SELECT * INTO payment_row
      FROM dwms.customs_duty_payments
     WHERE id = NEW.customs_duty_payment_id
     FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Unknown customs duty payment %', NEW.customs_duty_payment_id
            USING ERRCODE = '23503';
    END IF;
    SELECT * INTO tax_row
      FROM dwms.customs_declaration_taxes
     WHERE id = NEW.declaration_tax_id
     FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Unknown customs declaration tax %', NEW.declaration_tax_id
            USING ERRCODE = '23503';
    END IF;
    SELECT version.declaration_id, declaration.current_version_id,
           declaration.workflow_status, version.sealed_at
      INTO version_declaration_id, declaration_current_version_id,
           declaration_status, version_sealed_at
      FROM dwms.customs_declaration_versions version
      JOIN dwms.customs_declarations declaration ON declaration.id = version.declaration_id
     WHERE version.id = tax_row.declaration_version_id
     FOR SHARE OF version, declaration;

    IF payment_row.tenant_id <> NEW.tenant_id
       OR payment_row.owner_partner_id <> NEW.owner_partner_id
       OR tax_row.tenant_id <> NEW.tenant_id
       OR tax_row.owner_partner_id <> NEW.owner_partner_id
       OR payment_row.declaration_id <> NEW.declaration_id
       OR version_declaration_id IS DISTINCT FROM NEW.declaration_id
       OR tax_row.declaration_version_id <> NEW.declaration_version_id
       OR declaration_current_version_id IS DISTINCT FROM NEW.declaration_version_id THEN
        RAISE EXCEPTION 'Customs duty allocation must stay within one tenant, owner, declaration and current version'
            USING ERRCODE = '23514';
    END IF;
    IF version_sealed_at IS NULL
       OR declaration_status NOT IN ('ASSESSED','PAID','RELEASED','CLEARED') THEN
        RAISE EXCEPTION 'Duty may only be allocated against the sealed current assessed declaration version'
            USING ERRCODE = '23514';
    END IF;
    IF payment_row.currency_code <> NEW.currency_code
       OR tax_row.currency_code <> NEW.currency_code THEN
        RAISE EXCEPTION 'Customs duty allocation currency mismatch'
            USING ERRCODE = '23514';
    END IF;
    IF payment_row.status NOT IN (
        'PARTIALLY_PAID','PAID','REFUND_PENDING','PARTIALLY_REFUNDED','REFUNDED'
    ) THEN
        RAISE EXCEPTION 'Customs duty payment % is not in an allocatable paid status', payment_row.id
            USING ERRCODE = '23514';
    END IF;

    SELECT COALESCE(sum(allocated_amount), 0)
      INTO payment_allocated
      FROM dwms.customs_duty_payment_allocations
     WHERE customs_duty_payment_id = NEW.customs_duty_payment_id;
    SELECT COALESCE(sum(allocated_amount), 0)
      INTO tax_allocated
      FROM dwms.customs_duty_payment_allocations
     WHERE declaration_tax_id = NEW.declaration_tax_id;
    IF payment_allocated + NEW.allocated_amount > payment_row.paid_amount THEN
        RAISE EXCEPTION 'Duty allocation exceeds paid amount for payment %', payment_row.id
            USING ERRCODE = '23514';
    END IF;
    IF tax_allocated + NEW.allocated_amount > tax_row.payable_amount THEN
        RAISE EXCEPTION 'Duty allocation exceeds payable amount for declaration tax %', tax_row.id
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION dwms.validate_customs_refund_allocation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, dwms
AS $function$
DECLARE
    claim_row dwms.customs_refund_claims%ROWTYPE;
    payment_row dwms.customs_duty_payments%ROWTYPE;
    tax_row dwms.customs_declaration_taxes%ROWTYPE;
    target_declaration_id uuid;
    claim_allocated numeric(24,4);
    target_allocated numeric(24,4);
    tax_paid numeric(24,4);
BEGIN
    PERFORM pg_advisory_xact_lock(hashtext('dwms-customs-finance:' || NEW.declaration_id::text));
    SELECT * INTO claim_row
      FROM dwms.customs_refund_claims
     WHERE id = NEW.refund_claim_id
     FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Unknown customs refund claim %', NEW.refund_claim_id
            USING ERRCODE = '23503';
    END IF;

    IF NEW.customs_duty_payment_id IS NOT NULL THEN
        SELECT * INTO payment_row
          FROM dwms.customs_duty_payments
         WHERE id = NEW.customs_duty_payment_id
         FOR UPDATE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Unknown customs duty payment %', NEW.customs_duty_payment_id
                USING ERRCODE = '23503';
        END IF;
        target_declaration_id := payment_row.declaration_id;
        IF payment_row.tenant_id <> NEW.tenant_id
           OR payment_row.owner_partner_id <> NEW.owner_partner_id
           OR payment_row.currency_code <> NEW.currency_code THEN
            RAISE EXCEPTION 'Customs refund payment target scope/currency mismatch'
                USING ERRCODE = '23514';
        END IF;
        SELECT COALESCE(sum(allocated_amount), 0)
          INTO target_allocated
          FROM dwms.customs_refund_allocations
         WHERE customs_duty_payment_id = NEW.customs_duty_payment_id;
        IF target_allocated + NEW.allocated_amount > payment_row.refunded_amount THEN
            RAISE EXCEPTION 'Refund allocation exceeds recorded refund for duty payment %', payment_row.id
                USING ERRCODE = '23514';
        END IF;
    ELSE
        SELECT * INTO tax_row
          FROM dwms.customs_declaration_taxes
         WHERE id = NEW.declaration_tax_id
         FOR UPDATE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Unknown customs declaration tax %', NEW.declaration_tax_id
                USING ERRCODE = '23503';
        END IF;
        SELECT version.declaration_id
          INTO target_declaration_id
          FROM dwms.customs_declaration_versions version
         WHERE version.id = tax_row.declaration_version_id
         FOR SHARE;
        IF tax_row.tenant_id <> NEW.tenant_id
           OR tax_row.owner_partner_id <> NEW.owner_partner_id
           OR tax_row.currency_code <> NEW.currency_code
           OR tax_row.declaration_version_id IS DISTINCT FROM NEW.declaration_version_id THEN
            RAISE EXCEPTION 'Customs refund tax target scope/version/currency mismatch'
                USING ERRCODE = '23514';
        END IF;
        SELECT COALESCE(sum(allocated_amount), 0)
          INTO tax_paid
          FROM dwms.customs_duty_payment_allocations
         WHERE declaration_tax_id = NEW.declaration_tax_id;
        SELECT COALESCE(sum(allocated_amount), 0)
          INTO target_allocated
          FROM dwms.customs_refund_allocations
         WHERE declaration_tax_id = NEW.declaration_tax_id;
        IF target_allocated + NEW.allocated_amount > LEAST(tax_row.payable_amount, tax_paid) THEN
            RAISE EXCEPTION 'Refund allocation exceeds paid tax amount for declaration tax %', tax_row.id
                USING ERRCODE = '23514';
        END IF;
    END IF;

    IF claim_row.tenant_id <> NEW.tenant_id
       OR claim_row.owner_partner_id <> NEW.owner_partner_id
       OR claim_row.declaration_id <> NEW.declaration_id
       OR target_declaration_id IS DISTINCT FROM NEW.declaration_id
       OR claim_row.currency_code <> NEW.currency_code THEN
        RAISE EXCEPTION 'Customs refund allocation must stay within one tenant, owner, declaration and currency'
            USING ERRCODE = '23514';
    END IF;
    IF claim_row.status NOT IN ('PARTIALLY_PAID','PAID') THEN
        RAISE EXCEPTION 'Refund claim % must be paid before its refund is allocated', claim_row.id
            USING ERRCODE = '23514';
    END IF;
    SELECT COALESCE(sum(allocated_amount), 0)
      INTO claim_allocated
      FROM dwms.customs_refund_allocations
     WHERE refund_claim_id = NEW.refund_claim_id;
    IF claim_allocated + NEW.allocated_amount > claim_row.paid_amount THEN
        RAISE EXCEPTION 'Refund allocation exceeds paid amount for claim %', claim_row.id
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION dwms.guard_customs_financial_header_projection()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, dwms
AS $function$
DECLARE
    allocated_amount numeric(24,4);
BEGIN
    IF TG_TABLE_NAME = 'customs_duty_payments' THEN
        SELECT COALESCE(sum(allocation.allocated_amount), 0)
          INTO allocated_amount
          FROM dwms.customs_duty_payment_allocations allocation
         WHERE allocation.customs_duty_payment_id = OLD.id;
        IF NEW.paid_amount < allocated_amount THEN
            RAISE EXCEPTION 'Duty payment paid amount cannot fall below allocated amount %', allocated_amount
                USING ERRCODE = '23514';
        END IF;
        SELECT COALESCE(sum(allocation.allocated_amount), 0)
          INTO allocated_amount
          FROM dwms.customs_refund_allocations allocation
         WHERE allocation.customs_duty_payment_id = OLD.id;
        IF NEW.refunded_amount < allocated_amount THEN
            RAISE EXCEPTION 'Duty payment refunded amount cannot fall below allocated refunds %', allocated_amount
                USING ERRCODE = '23514';
        END IF;
        IF (
            EXISTS (
                SELECT 1 FROM dwms.customs_duty_payment_allocations allocation
                 WHERE allocation.customs_duty_payment_id = OLD.id
            ) OR EXISTS (
                SELECT 1 FROM dwms.customs_refund_allocations allocation
                 WHERE allocation.customs_duty_payment_id = OLD.id
            )
        ) AND (
            NEW.tenant_id IS DISTINCT FROM OLD.tenant_id
            OR NEW.owner_partner_id IS DISTINCT FROM OLD.owner_partner_id
            OR NEW.declaration_id IS DISTINCT FROM OLD.declaration_id
            OR NEW.currency_code IS DISTINCT FROM OLD.currency_code
        ) THEN
            RAISE EXCEPTION 'Allocated customs duty payment scope and currency are immutable'
                USING ERRCODE = '55000';
        END IF;
    ELSE
        SELECT COALESCE(sum(allocation.allocated_amount), 0)
          INTO allocated_amount
          FROM dwms.customs_refund_allocations allocation
         WHERE allocation.refund_claim_id = OLD.id;
        IF NEW.paid_amount < allocated_amount THEN
            RAISE EXCEPTION 'Refund claim paid amount cannot fall below allocated amount %', allocated_amount
                USING ERRCODE = '23514';
        END IF;
        IF allocated_amount > 0 AND (
            NEW.tenant_id IS DISTINCT FROM OLD.tenant_id
            OR NEW.owner_partner_id IS DISTINCT FROM OLD.owner_partner_id
            OR NEW.declaration_id IS DISTINCT FROM OLD.declaration_id
            OR NEW.currency_code IS DISTINCT FROM OLD.currency_code
        ) THEN
            RAISE EXCEPTION 'Allocated customs refund claim scope and currency are immutable'
                USING ERRCODE = '55000';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION dwms.validate_customs_duty_payment_allocation() FROM PUBLIC;
REVOKE ALL ON FUNCTION dwms.validate_customs_refund_allocation() FROM PUBLIC;
REVOKE ALL ON FUNCTION dwms.guard_customs_financial_header_projection() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_validate_customs_duty_payment_allocation
    ON dwms.customs_duty_payment_allocations;
CREATE TRIGGER trg_validate_customs_duty_payment_allocation
    BEFORE INSERT ON dwms.customs_duty_payment_allocations
    FOR EACH ROW EXECUTE PROCEDURE dwms.validate_customs_duty_payment_allocation();

DROP TRIGGER IF EXISTS trg_validate_customs_refund_allocation
    ON dwms.customs_refund_allocations;
CREATE TRIGGER trg_validate_customs_refund_allocation
    BEFORE INSERT ON dwms.customs_refund_allocations
    FOR EACH ROW EXECUTE PROCEDURE dwms.validate_customs_refund_allocation();

DROP TRIGGER IF EXISTS trg_guard_customs_duty_payment_projection
    ON dwms.customs_duty_payments;
CREATE TRIGGER trg_guard_customs_duty_payment_projection
    BEFORE UPDATE OF tenant_id, owner_partner_id, declaration_id, currency_code,
        paid_amount, refunded_amount
    ON dwms.customs_duty_payments
    FOR EACH ROW EXECUTE PROCEDURE dwms.guard_customs_financial_header_projection();

DROP TRIGGER IF EXISTS trg_guard_customs_refund_claim_projection
    ON dwms.customs_refund_claims;
CREATE TRIGGER trg_guard_customs_refund_claim_projection
    BEFORE UPDATE OF tenant_id, owner_partner_id, declaration_id, currency_code, paid_amount
    ON dwms.customs_refund_claims
    FOR EACH ROW EXECUTE PROCEDURE dwms.guard_customs_financial_header_projection();

CREATE TABLE IF NOT EXISTS dwms.unipass_messages (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    owner_partner_id uuid REFERENCES dwms.business_partners(id),
    connection_profile_id uuid NOT NULL REFERENCES dwms.unipass_connection_profiles(id),
    message_schema_id uuid REFERENCES dwms.customs_message_schemas(id),
    declaration_id uuid REFERENCES dwms.customs_declarations(id),
    declaration_version_id uuid REFERENCES dwms.customs_declaration_versions(id),
    direction varchar(10) NOT NULL,
    message_type varchar(120) NOT NULL,
    message_purpose varchar(50) NOT NULL,
    attempt_no integer NOT NULL DEFAULT 1,
    submission_no varchar(200),
    original_submission_no varchar(200),
    external_message_id varchar(300),
    correlation_id varchar(150),
    causation_message_id uuid REFERENCES dwms.unipass_messages(id),
    transport_protocol varchar(30),
    payload_object_uri text NOT NULL,
    payload_sha256 char(64) NOT NULL,
    payload_byte_size bigint NOT NULL,
    payload_media_type varchar(150),
    payload_encoding varchar(50),
    data_classification varchar(30) NOT NULL DEFAULT 'REGULATED',
    payload_summary_masked jsonb NOT NULL DEFAULT '{}'::jsonb,
    recorded_status varchar(30) NOT NULL DEFAULT 'CREATED',
    sent_at timestamptz,
    received_at timestamptz,
    customs_system_recorded_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    retention_until date,
    legal_hold boolean NOT NULL DEFAULT false,
    CONSTRAINT ck_dwms_unipass_message_direction CHECK (direction IN ('IN','OUT')),
    FOREIGN KEY (declaration_id, declaration_version_id)
        REFERENCES dwms.customs_declaration_versions(declaration_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_dwms_unipass_message_declaration_version CHECK (
        declaration_version_id IS NULL OR declaration_id IS NOT NULL
    ),
    CONSTRAINT ck_dwms_unipass_message_purpose CHECK (message_purpose IN (
        'SUBMISSION','RESUBMISSION','CORRECTION','WITHDRAWAL','ACKNOWLEDGEMENT',
        'STATUS_RESPONSE','ERROR_RESPONSE','QUERY','QUERY_RESPONSE','MASTER_SYNC','OTHER'
    )),
    CONSTRAINT ck_dwms_unipass_message_attempt CHECK (attempt_no > 0),
    CONSTRAINT ck_dwms_unipass_message_hash CHECK (payload_sha256 ~ '^[0-9A-Fa-f]{64}$'),
    CONSTRAINT ck_dwms_unipass_message_size CHECK (payload_byte_size >= 0),
    CONSTRAINT ck_dwms_unipass_message_status CHECK (recorded_status IN (
        'CREATED','QUEUED','SENT','RECEIVED','ACKNOWLEDGED','ACCEPTED','REJECTED','ERROR'
    )),
    CONSTRAINT ck_dwms_unipass_message_causation CHECK (causation_message_id IS NULL OR causation_message_id <> id),
    CONSTRAINT ck_dwms_unipass_message_no_inline_secrets CHECK (
        NOT dwms.jsonb_contains_forbidden_secret_key(payload_summary_masked)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_dwms_unipass_message_attempt
    ON dwms.unipass_messages (
        connection_profile_id, direction, message_type, submission_no, attempt_no
    ) WHERE submission_no IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS ux_dwms_unipass_external_message
    ON dwms.unipass_messages (connection_profile_id, direction, external_message_id)
    WHERE external_message_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS ix_dwms_unipass_correlation
    ON dwms.unipass_messages (tenant_id, correlation_id, created_at DESC)
    WHERE correlation_id IS NOT NULL;

COMMENT ON TABLE dwms.unipass_messages IS
    'Immutable-core UNI-PASS envelopes with a forward-only delivery lifecycle. Regulated payload bytes remain in protected object storage; PostgreSQL keeps URI, SHA-256, size, and a minimized masked summary.';

CREATE OR REPLACE FUNCTION dwms.validate_unipass_message_lifecycle()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    transition_is_valid boolean;
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF OLD.sent_at IS NOT NULL AND OLD.sent_at IS DISTINCT FROM NEW.sent_at THEN
            RAISE EXCEPTION 'UNI-PASS sent_at is immutable once recorded for message %', NEW.id
                USING ERRCODE = '55000';
        END IF;
        IF OLD.received_at IS NOT NULL AND OLD.received_at IS DISTINCT FROM NEW.received_at THEN
            RAISE EXCEPTION 'UNI-PASS received_at is immutable once recorded for message %', NEW.id
                USING ERRCODE = '55000';
        END IF;
        IF OLD.customs_system_recorded_at IS NOT NULL
           AND OLD.customs_system_recorded_at IS DISTINCT FROM NEW.customs_system_recorded_at THEN
            RAISE EXCEPTION 'UNI-PASS customs-system time is immutable once recorded for message %', NEW.id
                USING ERRCODE = '55000';
        END IF;
        IF OLD.retention_until IS NOT NULL AND (
            NEW.retention_until IS NULL OR NEW.retention_until < OLD.retention_until
        ) THEN
            RAISE EXCEPTION 'UNI-PASS retention period may only be extended for message %', NEW.id
                USING ERRCODE = '23514';
        END IF;

        transition_is_valid := OLD.recorded_status = NEW.recorded_status OR
            (OLD.recorded_status = 'CREATED' AND NEW.recorded_status IN ('QUEUED','RECEIVED','ERROR')) OR
            (OLD.recorded_status = 'QUEUED' AND NEW.recorded_status IN ('SENT','ERROR')) OR
            (OLD.recorded_status = 'SENT' AND NEW.recorded_status IN ('ACKNOWLEDGED','ACCEPTED','REJECTED','ERROR')) OR
            (OLD.recorded_status = 'RECEIVED' AND NEW.recorded_status IN ('ACKNOWLEDGED','ACCEPTED','REJECTED','ERROR')) OR
            (OLD.recorded_status = 'ACKNOWLEDGED' AND NEW.recorded_status IN ('ACCEPTED','REJECTED','ERROR'));
        IF NOT transition_is_valid THEN
            RAISE EXCEPTION 'Invalid UNI-PASS message status transition % -> % for message %',
                OLD.recorded_status, NEW.recorded_status, NEW.id USING ERRCODE = '23514';
        END IF;
    END IF;

    IF NEW.direction = 'OUT' THEN
        IF NEW.recorded_status = 'RECEIVED' OR NEW.received_at IS NOT NULL
           OR NEW.customs_system_recorded_at IS NOT NULL THEN
            RAISE EXCEPTION 'Outbound UNI-PASS envelope cannot use inbound receipt fields'
                USING ERRCODE = '23514';
        END IF;
        IF NEW.recorded_status IN ('SENT','ACKNOWLEDGED','ACCEPTED','REJECTED')
           AND NEW.sent_at IS NULL THEN
            RAISE EXCEPTION 'Sent or acknowledged outbound UNI-PASS message requires sent_at'
                USING ERRCODE = '23514';
        END IF;
    ELSE
        IF NEW.recorded_status IN ('QUEUED','SENT') OR NEW.sent_at IS NOT NULL THEN
            RAISE EXCEPTION 'Inbound UNI-PASS envelope cannot use outbound queue/send fields'
                USING ERRCODE = '23514';
        END IF;
        IF NEW.recorded_status IN ('RECEIVED','ACKNOWLEDGED','ACCEPTED','REJECTED')
           AND NEW.received_at IS NULL THEN
            RAISE EXCEPTION 'Processed inbound UNI-PASS message requires received_at'
                USING ERRCODE = '23514';
        END IF;
    END IF;

    IF NEW.sent_at IS NOT NULL AND NEW.sent_at < NEW.created_at
       OR NEW.received_at IS NOT NULL AND NEW.received_at > clock_timestamp() + interval '5 minutes'
       OR NEW.customs_system_recorded_at IS NOT NULL
          AND NEW.received_at IS NOT NULL
          AND NEW.customs_system_recorded_at > NEW.received_at + interval '1 day' THEN
        RAISE EXCEPTION 'UNI-PASS message timestamps are inconsistent for message %', NEW.id
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_validate_unipass_message_lifecycle ON dwms.unipass_messages;
CREATE TRIGGER trg_validate_unipass_message_lifecycle
    BEFORE INSERT OR UPDATE OF recorded_status, sent_at, received_at,
        customs_system_recorded_at, retention_until, legal_hold
    ON dwms.unipass_messages
    FOR EACH ROW EXECUTE PROCEDURE dwms.validate_unipass_message_lifecycle();

CREATE TABLE IF NOT EXISTS dwms.unipass_message_events (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    unipass_message_id uuid NOT NULL REFERENCES dwms.unipass_messages(id) ON DELETE RESTRICT,
    sequence_no integer NOT NULL,
    event_type varchar(80) NOT NULL,
    from_status varchar(30),
    to_status varchar(30),
    occurred_at timestamptz NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT now(),
    event_reference varchar(300),
    detail_masked jsonb NOT NULL DEFAULT '{}'::jsonb,
    UNIQUE (unipass_message_id, sequence_no),
    CONSTRAINT ck_dwms_unipass_message_event_seq CHECK (sequence_no > 0)
);

CREATE TABLE IF NOT EXISTS dwms.unipass_message_errors (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    unipass_message_id uuid NOT NULL REFERENCES dwms.unipass_messages(id) ON DELETE RESTRICT,
    error_sequence integer NOT NULL,
    error_code varchar(150) NOT NULL,
    severity varchar(20) NOT NULL DEFAULT 'ERROR',
    field_path varchar(500),
    line_no integer,
    rejected_value_masked varchar(500),
    error_message_masked text,
    retryable boolean NOT NULL DEFAULT false,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (unipass_message_id, error_sequence),
    CONSTRAINT ck_dwms_unipass_error_seq CHECK (error_sequence > 0),
    CONSTRAINT ck_dwms_unipass_error_line CHECK (line_no IS NULL OR line_no > 0),
    CONSTRAINT ck_dwms_unipass_error_severity CHECK (severity IN ('INFO','WARNING','ERROR','FATAL'))
);

CREATE TABLE IF NOT EXISTS dwms.unipass_message_attachments (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    unipass_message_id uuid NOT NULL REFERENCES dwms.unipass_messages(id) ON DELETE RESTRICT,
    attachment_sequence integer NOT NULL,
    document_type_code varchar(120),
    file_id uuid REFERENCES dwms.files(id),
    object_uri text,
    object_sha256 char(64),
    byte_size bigint,
    media_type varchar(150),
    original_file_name_masked varchar(500),
    retention_until date,
    legal_hold boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (unipass_message_id, attachment_sequence),
    CONSTRAINT ck_dwms_unipass_attachment_seq CHECK (attachment_sequence > 0),
    CONSTRAINT ck_dwms_unipass_attachment_source CHECK (file_id IS NOT NULL OR object_uri IS NOT NULL),
    CONSTRAINT ck_dwms_unipass_attachment_hash CHECK (object_sha256 IS NULL OR object_sha256 ~ '^[0-9A-Fa-f]{64}$'),
    CONSTRAINT ck_dwms_unipass_attachment_size CHECK (byte_size IS NULL OR byte_size >= 0)
);

-- Materialized legal evidence used by the physical-dispatch guard.  A declaration
-- status alone is not sufficient: the evidence must point to the exact current
-- sealed declaration version and an authenticated inbound UNI-PASS envelope.
CREATE TABLE IF NOT EXISTS dwms.customs_release_evidence (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    owner_partner_id uuid NOT NULL REFERENCES dwms.business_partners(id),
    shipment_id uuid NOT NULL REFERENCES dwms.shipments(id),
    trade_shipment_id uuid REFERENCES dwms.trade_shipments(id),
    declaration_id uuid NOT NULL,
    declaration_version_id uuid NOT NULL,
    unipass_message_id uuid NOT NULL REFERENCES dwms.unipass_messages(id),
    evidence_type varchar(30) NOT NULL,
    official_decision_code varchar(50) NOT NULL,
    declaration_kind_snapshot varchar(30) NOT NULL,
    official_release_at timestamptz NOT NULL,
    external_release_reference varchar(300) NOT NULL,
    verification_method varchar(30) NOT NULL DEFAULT 'UNIPASS_INBOUND',
    verified_by uuid REFERENCES dwms.users(id),
    verified_at timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, owner_partner_id, id),
    FOREIGN KEY (tenant_id, owner_partner_id, declaration_id)
        REFERENCES dwms.customs_declarations(tenant_id, owner_partner_id, id),
    FOREIGN KEY (declaration_id, declaration_version_id)
        REFERENCES dwms.customs_declaration_versions(declaration_id, id),
    CONSTRAINT ck_dwms_customs_release_evidence_type CHECK (evidence_type IN (
        'IMPORT_RELEASE','EXPORT_CLEARANCE','BONDED_RELEASE','TRANSIT_RELEASE','RETURN_RELEASE'
    )),
    CONSTRAINT ck_dwms_customs_release_decision CHECK (official_decision_code IN (
        'IMPORT_RELEASED','EXPORT_CLEARED','BONDED_RELEASED','TRANSIT_RELEASED',
        'RETURN_IMPORT_RELEASED','RETURN_EXPORT_CLEARED'
    )),
    CONSTRAINT ck_dwms_customs_release_verification CHECK (
        verification_method = 'UNIPASS_INBOUND' AND btrim(external_release_reference) <> ''
    ),
    CONSTRAINT ck_dwms_customs_release_times CHECK (
        official_release_at <= verified_at AND created_at >= official_release_at
    )
);

CREATE OR REPLACE FUNCTION dwms.customs_release_evidence_is_current(p_evidence_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, dwms
AS $function$
    SELECT EXISTS (
        SELECT 1
          FROM dwms.customs_release_evidence evidence
          JOIN dwms.customs_declarations declaration
            ON declaration.id = evidence.declaration_id
          JOIN dwms.unipass_messages official_message
            ON official_message.id = evidence.unipass_message_id
          JOIN dwms.unipass_connection_profiles connection_profile
            ON connection_profile.id = official_message.connection_profile_id
          JOIN dwms.external_systems integration_system
            ON integration_system.id = connection_profile.external_system_id
          JOIN dwms.customs_message_schemas message_schema
            ON message_schema.id = official_message.message_schema_id
         WHERE evidence.id = p_evidence_id
           AND declaration.tenant_id = evidence.tenant_id
           AND declaration.owner_partner_id = evidence.owner_partner_id
           AND declaration.current_version_id = evidence.declaration_version_id
           AND declaration.declaration_kind = evidence.declaration_kind_snapshot
           AND (
               (evidence.trade_shipment_id IS NULL
                    AND declaration.shipment_id = evidence.shipment_id) OR
               (evidence.trade_shipment_id IS NOT NULL
                    AND declaration.trade_shipment_id = evidence.trade_shipment_id)
           )
           AND official_message.tenant_id = evidence.tenant_id
           AND official_message.owner_partner_id = evidence.owner_partner_id
           AND official_message.declaration_id = evidence.declaration_id
           AND official_message.declaration_version_id = evidence.declaration_version_id
           AND official_message.direction = 'IN'
           AND official_message.message_purpose IN ('STATUS_RESPONSE','QUERY_RESPONSE')
           AND official_message.recorded_status = 'ACCEPTED'
           AND official_message.external_message_id = evidence.external_release_reference
           AND official_message.received_at IS NOT NULL
           AND official_message.customs_system_recorded_at IS NOT NULL
           AND official_message.payload_summary_masked ->> 'decision_code'
                = evidence.official_decision_code
           AND official_message.payload_summary_masked ->> 'declaration_no'
                = declaration.declaration_no_normalized
           AND connection_profile.tenant_id = evidence.tenant_id
           AND connection_profile.environment = 'PRODUCTION'
           AND connection_profile.status = 'ACTIVE'
           AND connection_profile.valid_from <= official_message.received_at
           AND (connection_profile.valid_to IS NULL
                OR connection_profile.valid_to >= official_message.received_at)
           AND connection_profile.endpoint_uri ~* '^https://'
           AND COALESCE(btrim(connection_profile.service_id), '') <> ''
           AND COALESCE(btrim(connection_profile.sender_id), '') <> ''
           AND integration_system.tenant_id = evidence.tenant_id
           AND integration_system.system_type = 'UNIPASS'
           AND integration_system.direction IN ('INBOUND','BIDIRECTIONAL')
           AND integration_system.status = 'ACTIVE'
           AND message_schema.jurisdiction_country_code = 'KR'
           AND message_schema.authority_code = 'KCS'
           AND message_schema.direction = 'IN'
           AND message_schema.message_type = official_message.message_type
           AND message_schema.effective_from <= official_message.received_at::date
           AND (message_schema.effective_to IS NULL
                OR message_schema.effective_to >= official_message.received_at::date)
           AND (
               (evidence.evidence_type = 'IMPORT_RELEASE'
                    AND declaration.declaration_kind IN ('IMPORT','RETURN_IMPORT')
                    AND evidence.official_decision_code = 'IMPORT_RELEASED') OR
               (evidence.evidence_type = 'EXPORT_CLEARANCE'
                    AND declaration.declaration_kind IN ('EXPORT','RETURN_EXPORT')
                    AND evidence.official_decision_code = 'EXPORT_CLEARED') OR
               (evidence.evidence_type = 'BONDED_RELEASE'
                    AND declaration.declaration_kind = 'BONDED'
                    AND evidence.official_decision_code = 'BONDED_RELEASED') OR
               (evidence.evidence_type = 'TRANSIT_RELEASE'
                    AND declaration.declaration_kind = 'TRANSIT'
                    AND evidence.official_decision_code = 'TRANSIT_RELEASED') OR
               (evidence.evidence_type = 'RETURN_RELEASE'
                    AND declaration.declaration_kind = 'RETURN_IMPORT'
                    AND evidence.official_decision_code = 'RETURN_IMPORT_RELEASED') OR
               (evidence.evidence_type = 'RETURN_RELEASE'
                    AND declaration.declaration_kind = 'RETURN_EXPORT'
                    AND evidence.official_decision_code = 'RETURN_EXPORT_CLEARED')
           )
           AND (
               (evidence.official_decision_code IN ('EXPORT_CLEARED','RETURN_EXPORT_CLEARED')
                    AND declaration.workflow_status = 'CLEARED'
                    AND declaration.cleared_at = evidence.official_release_at) OR
               (evidence.official_decision_code NOT IN ('EXPORT_CLEARED','RETURN_EXPORT_CLEARED')
                    AND declaration.workflow_status IN ('RELEASED','CLEARED')
                    AND declaration.released_at = evidence.official_release_at)
           )
           AND official_message.customs_system_recorded_at >= evidence.official_release_at
           AND evidence.verified_at >= official_message.received_at
    );
$function$;

REVOKE ALL ON FUNCTION dwms.customs_release_evidence_is_current(uuid) FROM PUBLIC;

CREATE UNIQUE INDEX IF NOT EXISTS ux_dwms_customs_release_evidence_scope
    ON dwms.customs_release_evidence (
        tenant_id, owner_partner_id, shipment_id,
        COALESCE(trade_shipment_id, '00000000-0000-0000-0000-000000000000'::uuid),
        declaration_id, declaration_version_id, unipass_message_id
    );

CREATE INDEX IF NOT EXISTS ix_dwms_customs_release_evidence_lookup
    ON dwms.customs_release_evidence (
        tenant_id, owner_partner_id, shipment_id, trade_shipment_id, official_release_at DESC
    );

CREATE OR REPLACE FUNCTION dwms.validate_customs_release_evidence()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, dwms
AS $function$
DECLARE
    shipment_row dwms.shipments%ROWTYPE;
    declaration_row dwms.customs_declarations%ROWTYPE;
    message_row dwms.unipass_messages%ROWTYPE;
    connection_profile_row dwms.unipass_connection_profiles%ROWTYPE;
    integration_system_row dwms.external_systems%ROWTYPE;
    message_schema_row dwms.customs_message_schemas%ROWTYPE;
    expected_release_at timestamptz;
    expected_decision_code varchar(50);
BEGIN
    SELECT * INTO shipment_row
      FROM dwms.shipments
     WHERE id = NEW.shipment_id
     FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Unknown shipment % for customs release evidence', NEW.shipment_id
            USING ERRCODE = '23503';
    END IF;

    SELECT * INTO declaration_row
      FROM dwms.customs_declarations
     WHERE id = NEW.declaration_id
     FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Unknown customs declaration % for release evidence', NEW.declaration_id
            USING ERRCODE = '23503';
    END IF;

    SELECT * INTO message_row
      FROM dwms.unipass_messages
     WHERE id = NEW.unipass_message_id
     FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Unknown UNI-PASS message % for release evidence', NEW.unipass_message_id
            USING ERRCODE = '23503';
    END IF;

    SELECT * INTO connection_profile_row
      FROM dwms.unipass_connection_profiles
     WHERE id = message_row.connection_profile_id
     FOR SHARE;
    IF NOT FOUND
       OR connection_profile_row.tenant_id <> NEW.tenant_id
       OR connection_profile_row.environment <> 'PRODUCTION'
       OR connection_profile_row.status <> 'ACTIVE'
       OR connection_profile_row.valid_from > message_row.received_at
       OR (connection_profile_row.valid_to IS NOT NULL
           AND connection_profile_row.valid_to < message_row.received_at)
       OR connection_profile_row.endpoint_uri !~* '^https://'
       OR COALESCE(btrim(connection_profile_row.service_id), '') = ''
       OR COALESCE(btrim(connection_profile_row.sender_id), '') = ''
       OR connection_profile_row.external_system_id IS NULL THEN
        RAISE EXCEPTION 'Release evidence requires an active production UNI-PASS connection profile valid at receipt time'
            USING ERRCODE = '23514';
    END IF;
    SELECT * INTO integration_system_row
      FROM dwms.external_systems
     WHERE id = connection_profile_row.external_system_id
     FOR SHARE;
    IF NOT FOUND
       OR integration_system_row.tenant_id <> NEW.tenant_id
       OR integration_system_row.system_type <> 'UNIPASS'
       OR integration_system_row.direction NOT IN ('INBOUND','BIDIRECTIONAL')
       OR integration_system_row.status <> 'ACTIVE' THEN
        RAISE EXCEPTION 'Release evidence connection profile is not bound to an active inbound UNI-PASS system'
            USING ERRCODE = '23514';
    END IF;

    IF message_row.message_schema_id IS NULL THEN
        RAISE EXCEPTION 'Release evidence UNI-PASS response requires a registered message schema'
            USING ERRCODE = '23514';
    END IF;
    SELECT * INTO message_schema_row
      FROM dwms.customs_message_schemas
     WHERE id = message_row.message_schema_id
     FOR SHARE;
    IF NOT FOUND
       OR message_schema_row.jurisdiction_country_code <> 'KR'
       OR message_schema_row.authority_code <> 'KCS'
       OR message_schema_row.direction <> 'IN'
       OR message_schema_row.message_type <> message_row.message_type
       OR NOT message_schema_row.is_active
       OR message_row.received_at IS NULL
       OR message_schema_row.effective_from > message_row.received_at::date
       OR (message_schema_row.effective_to IS NOT NULL
           AND message_schema_row.effective_to < message_row.received_at::date) THEN
        RAISE EXCEPTION 'Release response does not use an active Korean Customs inbound result schema'
            USING ERRCODE = '23514';
    END IF;

    IF shipment_row.tenant_id <> NEW.tenant_id
       OR shipment_row.owner_partner_id <> NEW.owner_partner_id
       OR declaration_row.tenant_id <> NEW.tenant_id
       OR declaration_row.owner_partner_id <> NEW.owner_partner_id
       OR message_row.tenant_id <> NEW.tenant_id
       OR message_row.owner_partner_id IS DISTINCT FROM NEW.owner_partner_id THEN
        RAISE EXCEPTION 'Customs release evidence tenant/owner scope mismatch'
            USING ERRCODE = '23514';
    END IF;

    IF declaration_row.current_version_id IS DISTINCT FROM NEW.declaration_version_id
       OR message_row.declaration_id IS DISTINCT FROM NEW.declaration_id
       OR message_row.declaration_version_id IS DISTINCT FROM NEW.declaration_version_id THEN
        RAISE EXCEPTION 'Customs release evidence must use the current declaration version and matching UNI-PASS message'
            USING ERRCODE = '23514';
    END IF;

    IF declaration_row.workflow_status NOT IN ('RELEASED','CLEARED') THEN
        RAISE EXCEPTION 'Declaration % is not released or cleared', NEW.declaration_id
            USING ERRCODE = '23514';
    END IF;

    IF message_row.direction <> 'IN'
       OR message_row.message_purpose NOT IN ('STATUS_RESPONSE','QUERY_RESPONSE')
       OR message_row.recorded_status <> 'ACCEPTED'
       OR message_row.external_message_id IS NULL
       OR btrim(message_row.external_message_id) = ''
       OR message_row.received_at IS NULL
       OR message_row.customs_system_recorded_at IS NULL THEN
        RAISE EXCEPTION 'Release evidence requires a completed official inbound UNI-PASS response'
            USING ERRCODE = '23514';
    END IF;
    IF NEW.external_release_reference IS DISTINCT FROM message_row.external_message_id THEN
        RAISE EXCEPTION 'Release evidence external reference must match the UNI-PASS message identifier'
            USING ERRCODE = '23514';
    END IF;

    IF (NEW.evidence_type = 'IMPORT_RELEASE' AND declaration_row.declaration_kind NOT IN ('IMPORT','RETURN_IMPORT'))
       OR (NEW.evidence_type = 'EXPORT_CLEARANCE' AND declaration_row.declaration_kind NOT IN ('EXPORT','RETURN_EXPORT'))
       OR (NEW.evidence_type = 'BONDED_RELEASE' AND declaration_row.declaration_kind <> 'BONDED')
       OR (NEW.evidence_type = 'TRANSIT_RELEASE' AND declaration_row.declaration_kind <> 'TRANSIT')
       OR (NEW.evidence_type = 'RETURN_RELEASE' AND declaration_row.declaration_kind NOT IN ('RETURN_EXPORT','RETURN_IMPORT')) THEN
        RAISE EXCEPTION 'Evidence type % is incompatible with declaration kind %',
            NEW.evidence_type, declaration_row.declaration_kind USING ERRCODE = '23514';
    END IF;

    expected_decision_code := CASE
        WHEN NEW.evidence_type = 'IMPORT_RELEASE' THEN 'IMPORT_RELEASED'
        WHEN NEW.evidence_type = 'EXPORT_CLEARANCE' THEN 'EXPORT_CLEARED'
        WHEN NEW.evidence_type = 'BONDED_RELEASE' THEN 'BONDED_RELEASED'
        WHEN NEW.evidence_type = 'TRANSIT_RELEASE' THEN 'TRANSIT_RELEASED'
        WHEN declaration_row.declaration_kind = 'RETURN_IMPORT' THEN 'RETURN_IMPORT_RELEASED'
        ELSE 'RETURN_EXPORT_CLEARED'
    END;
    IF NEW.official_decision_code <> expected_decision_code
       OR message_row.payload_summary_masked ->> 'decision_code' IS DISTINCT FROM expected_decision_code
       OR declaration_row.declaration_no_normalized IS NULL
       OR message_row.payload_summary_masked ->> 'declaration_no'
          IS DISTINCT FROM declaration_row.declaration_no_normalized THEN
        RAISE EXCEPTION 'Release evidence decision/declaration identity does not match the parsed official result payload'
            USING ERRCODE = '23514';
    END IF;

    IF shipment_row.shipment_type = 'EXPORT'
       AND NEW.evidence_type NOT IN ('EXPORT_CLEARANCE','RETURN_RELEASE') THEN
        RAISE EXCEPTION 'Export shipment % requires export clearance evidence', NEW.shipment_id
            USING ERRCODE = '23514';
    END IF;

    IF NEW.trade_shipment_id IS NULL THEN
        IF declaration_row.shipment_id IS DISTINCT FROM NEW.shipment_id THEN
            RAISE EXCEPTION 'Direct release evidence declaration does not reference shipment %', NEW.shipment_id
                USING ERRCODE = '23514';
        END IF;
        IF EXISTS (
            SELECT 1 FROM dwms.shipment_trade_allocations allocation
             WHERE allocation.shipment_id = NEW.shipment_id
        ) THEN
            RAISE EXCEPTION 'Trade-allocated shipment % requires evidence for each trade shipment', NEW.shipment_id
                USING ERRCODE = '23514';
        END IF;
    ELSE
        IF declaration_row.trade_shipment_id IS DISTINCT FROM NEW.trade_shipment_id
           OR NOT EXISTS (
               SELECT 1 FROM dwms.shipment_trade_allocations allocation
                WHERE allocation.tenant_id = NEW.tenant_id
                  AND allocation.owner_partner_id = NEW.owner_partner_id
                  AND allocation.shipment_id = NEW.shipment_id
                  AND allocation.trade_shipment_id = NEW.trade_shipment_id
           ) THEN
            RAISE EXCEPTION 'Release evidence trade shipment is not allocated to shipment %', NEW.shipment_id
                USING ERRCODE = '23514';
        END IF;
    END IF;

    IF expected_decision_code IN ('EXPORT_CLEARED','RETURN_EXPORT_CLEARED') THEN
        IF declaration_row.workflow_status <> 'CLEARED' OR declaration_row.cleared_at IS NULL THEN
            RAISE EXCEPTION 'Export clearance evidence requires a CLEARED declaration and cleared_at'
                USING ERRCODE = '23514';
        END IF;
        expected_release_at := declaration_row.cleared_at;
    ELSE
        IF declaration_row.workflow_status NOT IN ('RELEASED','CLEARED')
           OR declaration_row.released_at IS NULL THEN
            RAISE EXCEPTION 'Release evidence requires a released declaration and released_at'
                USING ERRCODE = '23514';
        END IF;
        expected_release_at := declaration_row.released_at;
    END IF;
    IF expected_release_at IS NULL
       OR expected_release_at > message_row.customs_system_recorded_at THEN
        RAISE EXCEPTION 'Declaration release time is missing or later than the official UNI-PASS response time'
            USING ERRCODE = '23514';
    END IF;

    IF NEW.official_release_at IS DISTINCT FROM expected_release_at
       OR NEW.declaration_kind_snapshot IS DISTINCT FROM declaration_row.declaration_kind THEN
        RAISE EXCEPTION 'Release timestamp and declaration-kind snapshot must match the verified declaration'
            USING ERRCODE = '23514';
    END IF;
    IF NEW.verified_at < message_row.received_at THEN
        RAISE EXCEPTION 'Release evidence cannot be verified before the UNI-PASS response was received'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION dwms.validate_customs_release_evidence() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_validate_customs_release_evidence ON dwms.customs_release_evidence;
CREATE TRIGGER trg_validate_customs_release_evidence
    BEFORE INSERT ON dwms.customs_release_evidence
    FOR EACH ROW EXECUTE PROCEDURE dwms.validate_customs_release_evidence();

CREATE OR REPLACE FUNCTION dwms.guard_customs_release_legal_header()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, dwms
AS $function$
BEGIN
    IF EXISTS (
        SELECT 1
          FROM dwms.customs_release_evidence evidence
         WHERE evidence.declaration_id = OLD.id
    ) THEN
        IF TG_OP = 'DELETE' THEN
            RAISE EXCEPTION 'Customs declaration % with release evidence cannot be deleted', OLD.id
                USING ERRCODE = '55000';
        END IF;
        IF NEW.declaration_kind IS DISTINCT FROM OLD.declaration_kind
           OR NEW.declaration_no_raw IS DISTINCT FROM OLD.declaration_no_raw
           OR NEW.declaration_no_normalized IS DISTINCT FROM OLD.declaration_no_normalized
           OR NEW.customs_office_code IS DISTINCT FROM OLD.customs_office_code
           OR NEW.trade_shipment_id IS DISTINCT FROM OLD.trade_shipment_id
           OR NEW.shipment_id IS DISTINCT FROM OLD.shipment_id
           OR NEW.customs_system_recorded_at IS DISTINCT FROM OLD.customs_system_recorded_at
           OR NEW.accepted_at IS DISTINCT FROM OLD.accepted_at
           OR NEW.released_at IS DISTINCT FROM OLD.released_at
           OR NEW.cleared_at IS DISTINCT FROM OLD.cleared_at THEN
            RAISE EXCEPTION 'Legal identity/release fields of evidenced declaration % are immutable', OLD.id
                USING ERRCODE = '55000';
        END IF;
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION dwms.guard_customs_release_legal_header() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_guard_customs_release_legal_header ON dwms.customs_declarations;
CREATE TRIGGER trg_guard_customs_release_legal_header
    BEFORE UPDATE OR DELETE ON dwms.customs_declarations
    FOR EACH ROW EXECUTE PROCEDURE dwms.guard_customs_release_legal_header();

DROP TRIGGER IF EXISTS trg_block_immutable_change ON dwms.customs_release_evidence;
CREATE TRIGGER trg_block_immutable_change
    BEFORE UPDATE OR DELETE ON dwms.customs_release_evidence
    FOR EACH ROW EXECUTE PROCEDURE dwms.block_immutable_change();

COMMENT ON TABLE dwms.customs_release_evidence IS
    'Append-only bridge from a physical shipment to its current declaration version and authenticated inbound UNI-PASS release/clearance response.';

CREATE TABLE IF NOT EXISTS dwms.customs_release_line_coverages (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    owner_partner_id uuid NOT NULL REFERENCES dwms.business_partners(id),
    customs_release_evidence_id uuid NOT NULL REFERENCES dwms.customs_release_evidence(id),
    shipment_line_id uuid NOT NULL REFERENCES dwms.shipment_lines(id),
    shipment_trade_allocation_id uuid REFERENCES dwms.shipment_trade_allocations(id),
    declaration_line_id uuid NOT NULL,
    item_id_snapshot uuid NOT NULL REFERENCES dwms.items(id),
    country_of_origin_snapshot char(2) NOT NULL REFERENCES dwms.countries(country_code),
    hs_country_code_snapshot char(2) NOT NULL,
    hs_nomenclature_version_snapshot varchar(20) NOT NULL,
    hs_code_snapshot varchar(20) NOT NULL,
    covered_base_quantity numeric(24,8) NOT NULL,
    base_uom_code varchar(20) NOT NULL REFERENCES dwms.units_of_measure(uom_code),
    created_by uuid REFERENCES dwms.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, owner_partner_id, id),
    FOREIGN KEY (tenant_id, owner_partner_id, customs_release_evidence_id)
        REFERENCES dwms.customs_release_evidence(tenant_id, owner_partner_id, id),
    FOREIGN KEY (tenant_id, owner_partner_id, declaration_line_id)
        REFERENCES dwms.customs_declaration_lines(tenant_id, owner_partner_id, id),
    FOREIGN KEY (hs_country_code_snapshot, hs_nomenclature_version_snapshot, hs_code_snapshot)
        REFERENCES dwms.hs_codes(country_code, nomenclature_version, hs_code),
    CONSTRAINT ck_dwms_customs_release_line_coverage_qty CHECK (covered_base_quantity > 0)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_dwms_customs_release_line_coverage
    ON dwms.customs_release_line_coverages (
        customs_release_evidence_id, shipment_line_id,
        COALESCE(shipment_trade_allocation_id, '00000000-0000-0000-0000-000000000000'::uuid),
        declaration_line_id
    );

CREATE INDEX IF NOT EXISTS ix_dwms_customs_release_coverage_allocation
    ON dwms.customs_release_line_coverages (
        shipment_trade_allocation_id, shipment_line_id, customs_release_evidence_id
    );

CREATE INDEX IF NOT EXISTS ix_dwms_customs_release_coverage_declaration_line
    ON dwms.customs_release_line_coverages (declaration_line_id, created_at, id);

CREATE OR REPLACE FUNCTION dwms.validate_customs_release_line_coverage()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, dwms
AS $function$
DECLARE
    evidence_row dwms.customs_release_evidence%ROWTYPE;
    shipment_line_row dwms.shipment_lines%ROWTYPE;
    allocation_row dwms.shipment_trade_allocations%ROWTYPE;
    declaration_line_row dwms.customs_declaration_lines%ROWTYPE;
    version_sealed_at timestamptz;
    allocation_covered numeric(24,8);
    shipment_line_covered numeric(24,8);
    declaration_line_covered numeric(24,8);
BEGIN
    SELECT * INTO evidence_row
      FROM dwms.customs_release_evidence
     WHERE id = NEW.customs_release_evidence_id
     FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Unknown customs release evidence %', NEW.customs_release_evidence_id
            USING ERRCODE = '23503';
    END IF;
    SELECT * INTO shipment_line_row
      FROM dwms.shipment_lines
     WHERE id = NEW.shipment_line_id
     FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Unknown shipment line %', NEW.shipment_line_id
            USING ERRCODE = '23503';
    END IF;
    SELECT * INTO declaration_line_row
      FROM dwms.customs_declaration_lines
     WHERE id = NEW.declaration_line_id
     FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Unknown customs declaration line %', NEW.declaration_line_id
            USING ERRCODE = '23503';
    END IF;
    SELECT sealed_at INTO version_sealed_at
      FROM dwms.customs_declaration_versions
     WHERE id = evidence_row.declaration_version_id
     FOR SHARE;

    IF evidence_row.tenant_id <> NEW.tenant_id
       OR evidence_row.owner_partner_id <> NEW.owner_partner_id
       OR shipment_line_row.tenant_id <> NEW.tenant_id
       OR declaration_line_row.tenant_id <> NEW.tenant_id
       OR declaration_line_row.owner_partner_id <> NEW.owner_partner_id
       OR shipment_line_row.shipment_id <> evidence_row.shipment_id
       OR declaration_line_row.declaration_version_id <> evidence_row.declaration_version_id
       OR version_sealed_at IS NULL THEN
        RAISE EXCEPTION 'Release line coverage scope/version mismatch or declaration version is unsealed'
            USING ERRCODE = '23514';
    END IF;

    IF evidence_row.trade_shipment_id IS NULL THEN
        IF NEW.shipment_trade_allocation_id IS NOT NULL THEN
            RAISE EXCEPTION 'Direct shipment release coverage cannot reference a trade allocation'
                USING ERRCODE = '23514';
        END IF;
    ELSE
        IF NEW.shipment_trade_allocation_id IS NULL THEN
            RAISE EXCEPTION 'Trade-shipment release coverage requires a shipment trade allocation'
                USING ERRCODE = '23514';
        END IF;
        SELECT * INTO allocation_row
          FROM dwms.shipment_trade_allocations
         WHERE id = NEW.shipment_trade_allocation_id
         FOR UPDATE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Unknown shipment trade allocation %', NEW.shipment_trade_allocation_id
                USING ERRCODE = '23503';
        END IF;
        IF allocation_row.tenant_id <> NEW.tenant_id
           OR allocation_row.owner_partner_id <> NEW.owner_partner_id
           OR allocation_row.shipment_id <> evidence_row.shipment_id
           OR allocation_row.shipment_line_id <> NEW.shipment_line_id
           OR allocation_row.trade_shipment_id <> evidence_row.trade_shipment_id
           OR (allocation_row.commercial_invoice_line_id IS NOT NULL
               AND declaration_line_row.commercial_invoice_line_id
                   IS DISTINCT FROM allocation_row.commercial_invoice_line_id) THEN
            RAISE EXCEPTION 'Release coverage does not match its shipment/trade/invoice allocation'
                USING ERRCODE = '23514';
        END IF;
    END IF;

    IF declaration_line_row.item_id IS NULL
       OR declaration_line_row.item_id <> shipment_line_row.item_id
       OR declaration_line_row.item_id <> NEW.item_id_snapshot
       OR declaration_line_row.declared_base_quantity IS NULL
       OR declaration_line_row.base_uom_code IS NULL
       OR declaration_line_row.base_uom_code <> shipment_line_row.base_uom_code
       OR declaration_line_row.base_uom_code <> NEW.base_uom_code
       OR declaration_line_row.country_of_origin IS NULL
       OR shipment_line_row.country_of_origin IS NULL
       OR declaration_line_row.country_of_origin <> shipment_line_row.country_of_origin
       OR declaration_line_row.country_of_origin <> NEW.country_of_origin_snapshot
       OR declaration_line_row.hs_country_code IS NULL
       OR declaration_line_row.hs_nomenclature_version IS NULL
       OR declaration_line_row.hs_code IS NULL
       OR shipment_line_row.hs_country_code IS DISTINCT FROM declaration_line_row.hs_country_code
       OR shipment_line_row.hs_nomenclature_version IS DISTINCT FROM declaration_line_row.hs_nomenclature_version
       OR shipment_line_row.hs_code IS DISTINCT FROM declaration_line_row.hs_code
       OR NEW.hs_country_code_snapshot <> declaration_line_row.hs_country_code
       OR NEW.hs_nomenclature_version_snapshot <> declaration_line_row.hs_nomenclature_version
       OR NEW.hs_code_snapshot <> declaration_line_row.hs_code THEN
        RAISE EXCEPTION 'Release coverage item, origin, HS code, or base unit differs from declaration line %',
            NEW.declaration_line_id USING ERRCODE = '23514';
    END IF;

    SELECT COALESCE(sum(covered_base_quantity), 0)
      INTO declaration_line_covered
      FROM dwms.customs_release_line_coverages
     WHERE declaration_line_id = NEW.declaration_line_id;
    IF declaration_line_covered + NEW.covered_base_quantity
       > declaration_line_row.declared_base_quantity THEN
        RAISE EXCEPTION 'Release coverage exceeds declared base quantity for declaration line %',
            NEW.declaration_line_id USING ERRCODE = '23514';
    END IF;

    IF NEW.shipment_trade_allocation_id IS NOT NULL THEN
        SELECT COALESCE(sum(covered_base_quantity), 0)
          INTO allocation_covered
          FROM dwms.customs_release_line_coverages
         WHERE shipment_trade_allocation_id = NEW.shipment_trade_allocation_id;
        IF allocation_covered + NEW.covered_base_quantity > allocation_row.allocated_base_quantity THEN
            RAISE EXCEPTION 'Release coverage exceeds shipment trade allocation %',
                NEW.shipment_trade_allocation_id USING ERRCODE = '23514';
        END IF;
    ELSE
        SELECT COALESCE(sum(coverage.covered_base_quantity), 0)
          INTO shipment_line_covered
          FROM dwms.customs_release_line_coverages coverage
          JOIN dwms.customs_release_evidence evidence
            ON evidence.id = coverage.customs_release_evidence_id
         WHERE coverage.shipment_line_id = NEW.shipment_line_id
           AND coverage.shipment_trade_allocation_id IS NULL
           AND evidence.shipment_id = evidence_row.shipment_id;
        IF shipment_line_covered + NEW.covered_base_quantity > shipment_line_row.base_quantity THEN
            RAISE EXCEPTION 'Direct release coverage exceeds shipment line %', NEW.shipment_line_id
                USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION dwms.validate_customs_release_line_coverage() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_validate_customs_release_line_coverage
    ON dwms.customs_release_line_coverages;
CREATE TRIGGER trg_validate_customs_release_line_coverage
    BEFORE INSERT ON dwms.customs_release_line_coverages
    FOR EACH ROW EXECUTE PROCEDURE dwms.validate_customs_release_line_coverage();

DROP TRIGGER IF EXISTS trg_block_immutable_change ON dwms.customs_release_line_coverages;
CREATE TRIGGER trg_block_immutable_change
    BEFORE UPDATE OR DELETE ON dwms.customs_release_line_coverages
    FOR EACH ROW EXECUTE PROCEDURE dwms.block_immutable_change();

CREATE OR REPLACE FUNCTION dwms.guard_customs_covered_shipment_line()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, dwms
AS $function$
BEGIN
    IF EXISTS (
        SELECT 1
          FROM dwms.customs_release_line_coverages coverage
         WHERE coverage.shipment_line_id = OLD.id
    ) THEN
        RAISE EXCEPTION 'Customs-covered shipment line % is immutable; create a corrected shipment/declaration version',
            OLD.id USING ERRCODE = '55000';
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION dwms.guard_customs_covered_shipment_line() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_guard_customs_covered_shipment_line ON dwms.shipment_lines;
CREATE TRIGGER trg_guard_customs_covered_shipment_line
    BEFORE UPDATE OR DELETE ON dwms.shipment_lines
    FOR EACH ROW EXECUTE PROCEDURE dwms.guard_customs_covered_shipment_line();

COMMENT ON TABLE dwms.customs_release_line_coverages IS
    'Append-only quantity bridge proving that every dispatched base unit is covered by a matching sealed declaration line without reusing declared quantity.';

CREATE TABLE IF NOT EXISTS dwms.unipass_sync_runs (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    connection_profile_id uuid NOT NULL REFERENCES dwms.unipass_connection_profiles(id),
    sync_type varchar(80) NOT NULL,
    window_from timestamptz,
    window_to timestamptz,
    cursor_in_masked varchar(500),
    cursor_out_masked varchar(500),
    requested_by uuid REFERENCES dwms.users(id),
    started_at timestamptz,
    completed_at timestamptz,
    status varchar(20) NOT NULL DEFAULT 'QUEUED',
    item_count integer NOT NULL DEFAULT 0,
    success_count integer NOT NULL DEFAULT 0,
    error_count integer NOT NULL DEFAULT 0,
    error_summary_masked text,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_dwms_unipass_sync_status CHECK (status IN ('QUEUED','RUNNING','COMPLETED','PARTIAL','FAILED','CANCELLED')),
    CONSTRAINT ck_dwms_unipass_sync_counts CHECK (
        item_count >= 0 AND success_count >= 0 AND error_count >= 0 AND success_count + error_count <= item_count
    ),
    CONSTRAINT ck_dwms_unipass_sync_window CHECK (window_to IS NULL OR window_from IS NULL OR window_to >= window_from),
    CONSTRAINT ck_dwms_unipass_sync_dates CHECK (completed_at IS NULL OR started_at IS NULL OR completed_at >= started_at)
);

CREATE TABLE IF NOT EXISTS dwms.unipass_sync_items (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    sync_run_id uuid NOT NULL REFERENCES dwms.unipass_sync_runs(id) ON DELETE CASCADE,
    item_sequence integer NOT NULL,
    entity_type varchar(80),
    entity_id uuid,
    external_reference varchar(300),
    unipass_message_id uuid REFERENCES dwms.unipass_messages(id),
    status varchar(20) NOT NULL DEFAULT 'PENDING',
    error_code varchar(150),
    error_detail_masked text,
    processed_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (sync_run_id, item_sequence),
    CONSTRAINT ck_dwms_unipass_sync_item_seq CHECK (item_sequence > 0),
    CONSTRAINT ck_dwms_unipass_sync_item_status CHECK (status IN ('PENDING','PROCESSED','SKIPPED','ERROR'))
);

CREATE OR REPLACE FUNCTION dwms.protect_customs_declaration_version()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    IF current_setting('dwms.immutable_maintenance', true) = 'on' THEN
        IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
        RETURN NEW;
    END IF;
    IF OLD.sealed_at IS NOT NULL THEN
        RAISE EXCEPTION 'Sealed customs declaration version % is immutable', OLD.id
            USING ERRCODE = '55000';
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION dwms.validate_customs_version_seal()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    v_line_count integer;
    v_amount_count integer;
    v_invoice_total numeric(24,4);
BEGIN
    IF TG_OP = 'INSERT' AND NEW.sealed_at IS NOT NULL THEN
        RAISE EXCEPTION 'Customs declaration version must be inserted unsealed and sealed after its child rows are stored'
            USING ERRCODE = '23514';
    END IF;
    IF TG_OP = 'UPDATE' AND NEW.sealed_at IS NOT NULL AND OLD.sealed_at IS NULL THEN
        SELECT count(*), count(invoice_amount), COALESCE(sum(invoice_amount), 0)
          INTO v_line_count, v_amount_count, v_invoice_total
          FROM dwms.customs_declaration_lines
         WHERE declaration_version_id = NEW.id;

        IF NEW.declared_line_count IS NOT NULL AND NEW.declared_line_count <> v_line_count THEN
            RAISE EXCEPTION 'Declared line count % differs from stored line count % for customs version %',
                NEW.declared_line_count, v_line_count, NEW.id USING ERRCODE = '23514';
        END IF;
        IF NEW.total_invoice_amount IS NOT NULL AND v_line_count > 0 AND v_amount_count = v_line_count
           AND abs(NEW.total_invoice_amount - v_invoice_total) > 0.01 THEN
            RAISE EXCEPTION 'Invoice total % differs from line total % for customs version %',
                NEW.total_invoice_amount, v_invoice_total, NEW.id USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION dwms.protect_customs_version_child()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    v_row jsonb;
    v_version_id uuid;
    v_sealed_at timestamptz;
BEGIN
    IF current_setting('dwms.immutable_maintenance', true) = 'on' THEN
        IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
        RETURN NEW;
    END IF;
    IF TG_OP = 'DELETE' THEN v_row := to_jsonb(OLD); ELSE v_row := to_jsonb(NEW); END IF;
    v_version_id := (v_row ->> 'declaration_version_id')::uuid;
    SELECT sealed_at INTO v_sealed_at
      FROM dwms.customs_declaration_versions
     WHERE id = v_version_id;
    IF v_sealed_at IS NOT NULL THEN
        RAISE EXCEPTION 'Children of sealed customs declaration version % are immutable', v_version_id
            USING ERRCODE = '55000';
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_10_validate_customs_version_seal ON dwms.customs_declaration_versions;
CREATE TRIGGER trg_10_validate_customs_version_seal
    BEFORE INSERT OR UPDATE OF sealed_at ON dwms.customs_declaration_versions
    FOR EACH ROW EXECUTE PROCEDURE dwms.validate_customs_version_seal();

DROP TRIGGER IF EXISTS trg_20_protect_customs_version ON dwms.customs_declaration_versions;
CREATE TRIGGER trg_20_protect_customs_version
    BEFORE UPDATE OR DELETE ON dwms.customs_declaration_versions
    FOR EACH ROW EXECUTE PROCEDURE dwms.protect_customs_declaration_version();

DO $block$
DECLARE
    v_table text;
BEGIN
    FOREACH v_table IN ARRAY ARRAY[
        'customs_declaration_parties','customs_declaration_references','customs_declaration_lines',
        'customs_declaration_line_details','customs_declaration_requirements','customs_declaration_taxes',
        'customs_declaration_containers'
    ]
    LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS trg_protect_sealed_customs_version ON dwms.%I', v_table);
        EXECUTE format(
            'CREATE TRIGGER trg_protect_sealed_customs_version BEFORE INSERT OR UPDATE OR DELETE ON dwms.%I '
            'FOR EACH ROW EXECUTE PROCEDURE dwms.protect_customs_version_child()', v_table
        );
    END LOOP;
END;
$block$;

DO $block$
DECLARE
    v_table text;
BEGIN
    FOREACH v_table IN ARRAY ARRAY[
        'trade_shipments','trade_shipment_parties','trade_shipment_references','trade_shipment_legs',
        'trade_shipment_events','trade_container_shipments','trade_documents','trade_document_versions',
        'commercial_invoices','commercial_invoice_lines','packing_lists','packing_list_lines',
        'bills_of_lading','bill_of_lading_lines','air_waybills','air_waybill_lines',
        'receipt_trade_allocations','shipment_trade_allocations','customs_declarations',
        'customs_declaration_versions','customs_declaration_parties','customs_declaration_references',
        'customs_declaration_lines','customs_declaration_line_details','customs_declaration_requirements',
        'customs_declaration_taxes','customs_declaration_containers','customs_declaration_inspections',
        'customs_declaration_relations','customs_declaration_events','customs_documents',
        'customs_duty_payments','customs_refund_claims','unipass_messages'
    ]
    LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS trg_validate_tenant_owner_scope ON dwms.%I', v_table);
        EXECUTE format(
            'CREATE TRIGGER trg_validate_tenant_owner_scope BEFORE INSERT OR UPDATE ON dwms.%I '
            'FOR EACH ROW EXECUTE PROCEDURE dwms.validate_tenant_owner_scope()', v_table
        );
    END LOOP;
END;
$block$;

DO $block$
DECLARE
    v_table text;
BEGIN
    FOREACH v_table IN ARRAY ARRAY[
        'trade_party_snapshots','trade_shipment_events','trade_container_events',
        'trade_document_versions','trade_document_parties','trade_document_links',
        'customs_declaration_events','customs_documents','customs_document_links',
        'customs_duty_payment_allocations','customs_refund_allocations',
        'customs_release_evidence','customs_release_line_coverages',
        'unipass_message_events','unipass_message_errors',
        'unipass_message_attachments'
    ]
    LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS trg_block_immutable_change ON dwms.%I', v_table);
        EXECUTE format(
            'CREATE TRIGGER trg_block_immutable_change BEFORE UPDATE OR DELETE ON dwms.%I '
            'FOR EACH ROW EXECUTE PROCEDURE dwms.block_immutable_change()', v_table
        );
    END LOOP;
END;
$block$;

-- Message envelope payload/routing is immutable, but its delivery state must advance.
-- Module 11 installs the column-level core protection and TRUNCATE guard.
DROP TRIGGER IF EXISTS trg_block_immutable_change ON dwms.unipass_messages;

CREATE INDEX IF NOT EXISTS ix_dwms_trade_shipment_schedule
    ON dwms.trade_shipments (tenant_id, owner_partner_id, planned_arrival_at)
    WHERE status NOT IN ('CANCELLED','CLOSED');
CREATE INDEX IF NOT EXISTS ix_dwms_trade_leg_schedule
    ON dwms.trade_shipment_legs (tenant_id, planned_departure_at, planned_arrival_at);
CREATE INDEX IF NOT EXISTS ix_dwms_customs_version_declaration
    ON dwms.customs_declaration_versions (declaration_id, version_no DESC);
CREATE INDEX IF NOT EXISTS ix_dwms_customs_line_hs
    ON dwms.customs_declaration_lines (hs_country_code, hs_nomenclature_version, hs_code);
CREATE INDEX IF NOT EXISTS ix_dwms_customs_event_timeline
    ON dwms.customs_declaration_events (declaration_id, occurred_at, sequence_no);
CREATE INDEX IF NOT EXISTS ix_dwms_unipass_message_declaration
    ON dwms.unipass_messages (declaration_id, created_at DESC)
    WHERE declaration_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_dwms_unipass_sync_status
    ON dwms.unipass_sync_runs (tenant_id, status, created_at DESC);

CREATE INDEX IF NOT EXISTS brin_dwms_trade_shipment_events_occurred
    ON dwms.trade_shipment_events USING brin (occurred_at);
CREATE INDEX IF NOT EXISTS brin_dwms_customs_events_occurred
    ON dwms.customs_declaration_events USING brin (occurred_at);
CREATE INDEX IF NOT EXISTS brin_dwms_unipass_messages_created
    ON dwms.unipass_messages USING brin (created_at);

COMMENT ON TABLE dwms.customs_declarations IS
    'Logical customs case. Current workflow state is mutable; every filed/corrected payload is preserved in customs_declaration_versions.';
COMMENT ON TABLE dwms.customs_declaration_versions IS
    'Version aggregate becomes immutable when sealed_at is set. Corrections and resubmissions create a new version.';
COMMENT ON TABLE dwms.customs_declaration_events IS
    'Append-only customs timeline. sent_at/received_at and customs-system-recorded time remain distinct in message and event records.';
COMMENT ON COLUMN dwms.customs_declaration_parties.personal_identifier_encrypted IS
    'Encrypted personal identifier only; plaintext resident/customs identifiers are prohibited.';
COMMENT ON TABLE dwms.customs_code_sets IS
    'Effective-dated external code catalogs. Code format and meaning are not frozen in application CHECK constraints.';

DO $block$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'dwms.stock_buckets'::regclass
          AND conname = 'fk_dwms_stock_bucket_customs_line'
    ) THEN
        ALTER TABLE dwms.stock_buckets
            ADD CONSTRAINT fk_dwms_stock_bucket_customs_line
            FOREIGN KEY (tenant_id, customs_declaration_line_id)
            REFERENCES dwms.customs_declaration_lines(tenant_id, id) ON DELETE RESTRICT;
    END IF;
END;
$block$;
