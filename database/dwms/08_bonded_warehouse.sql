-- DWMS enterprise WMS schema - Korea bonded facilities, cargo control, transport, and compliance.
-- PostgreSQL 11 compatible. Applied after 07_global_trade_customs.sql.
-- Legal deadlines are effective-dated data in bonded_storage_rules, not hard-coded constants.

CREATE TABLE IF NOT EXISTS dwms.bonded_facilities (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    warehouse_id uuid NOT NULL REFERENCES dwms.warehouses(id),
    operator_partner_id uuid NOT NULL REFERENCES dwms.business_partners(id),
    facility_code varchar(100) NOT NULL,
    facility_name varchar(250) NOT NULL,
    facility_type_code varchar(100) NOT NULL,
    customs_facility_code varchar(150),
    supervising_customs_office_code varchar(20) REFERENCES dwms.customs_offices(customs_office_code),
    bonded_area_m2 numeric(20,6),
    capacity_weight numeric(24,8),
    weight_uom_code varchar(20) REFERENCES dwms.units_of_measure(uom_code),
    capacity_volume numeric(24,9),
    volume_uom_code varchar(20) REFERENCES dwms.units_of_measure(uom_code),
    security_grade_code varchar(100),
    electronic_inventory_enabled boolean NOT NULL DEFAULT true,
    status varchar(20) NOT NULL DEFAULT 'PLANNED',
    valid_from date,
    valid_to date,
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    UNIQUE (tenant_id, facility_code),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_dwms_bonded_facility_capacity CHECK (
        (bonded_area_m2 IS NULL OR bonded_area_m2 >= 0) AND
        (capacity_weight IS NULL OR capacity_weight >= 0) AND
        (capacity_volume IS NULL OR capacity_volume >= 0)
    ),
    CONSTRAINT ck_dwms_bonded_facility_status CHECK (status IN ('PLANNED','ACTIVE','SUSPENDED','EXPIRED','CLOSED')),
    CONSTRAINT ck_dwms_bonded_facility_dates CHECK (valid_to IS NULL OR valid_from IS NULL OR valid_to >= valid_from)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_dwms_bonded_facility_customs_code
    ON dwms.bonded_facilities (tenant_id, customs_facility_code)
    WHERE customs_facility_code IS NOT NULL AND deleted_at IS NULL;

CREATE TABLE IF NOT EXISTS dwms.bonded_facility_licenses (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL,
    bonded_facility_id uuid NOT NULL,
    license_no_raw varchar(200) NOT NULL,
    license_no_normalized varchar(200),
    license_type_code varchar(100) NOT NULL,
    issuing_customs_office_code varchar(20) REFERENCES dwms.customs_offices(customs_office_code),
    issued_on date NOT NULL,
    effective_from date NOT NULL,
    effective_to date,
    renewal_of_license_id uuid REFERENCES dwms.bonded_facility_licenses(id),
    suspension_from date,
    suspension_to date,
    revocation_on date,
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    license_document_id uuid REFERENCES dwms.files(id),
    terms_and_conditions jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, license_no_raw),
    UNIQUE (tenant_id, id),
    FOREIGN KEY (tenant_id, bonded_facility_id)
        REFERENCES dwms.bonded_facilities(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_dwms_bonded_license_dates CHECK (
        effective_from >= issued_on AND
        (effective_to IS NULL OR effective_to >= effective_from) AND
        (suspension_to IS NULL OR suspension_from IS NULL OR suspension_to >= suspension_from) AND
        (revocation_on IS NULL OR revocation_on >= issued_on)
    ),
    CONSTRAINT ck_dwms_bonded_license_renewal CHECK (renewal_of_license_id IS NULL OR renewal_of_license_id <> id),
    CONSTRAINT ck_dwms_bonded_license_status CHECK (status IN ('PENDING','ACTIVE','SUSPENDED','EXPIRED','REVOKED','SUPERSEDED'))
);

CREATE TABLE IF NOT EXISTS dwms.bonded_zone_controls (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL,
    bonded_facility_id uuid NOT NULL,
    facility_license_id uuid REFERENCES dwms.bonded_facility_licenses(id),
    warehouse_zone_id uuid REFERENCES dwms.warehouse_zones(id),
    warehouse_location_id uuid REFERENCES dwms.warehouse_locations(id),
    control_code varchar(80) NOT NULL,
    control_type varchar(30) NOT NULL,
    physical_access_level varchar(50),
    allowed_legal_status_codes varchar(100)[] NOT NULL DEFAULT ARRAY[]::varchar(100)[],
    mixed_legal_status_allowed boolean NOT NULL DEFAULT false,
    customs_seal_required boolean NOT NULL DEFAULT false,
    camera_required boolean NOT NULL DEFAULT false,
    active_from timestamptz NOT NULL DEFAULT now(),
    active_to timestamptz,
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (bonded_facility_id, control_code),
    FOREIGN KEY (tenant_id, bonded_facility_id)
        REFERENCES dwms.bonded_facilities(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_dwms_bonded_zone_scope CHECK (num_nonnulls(warehouse_zone_id, warehouse_location_id) >= 1),
    CONSTRAINT ck_dwms_bonded_zone_type CHECK (control_type IN ('RECEIVING','STORAGE','INSPECTION','HANDLING','RELEASE','DISPOSAL','TRANSIT','OTHER')),
    CONSTRAINT ck_dwms_bonded_zone_status CHECK (status IN ('ACTIVE','BLOCKED','SUSPENDED','INACTIVE')),
    CONSTRAINT ck_dwms_bonded_zone_dates CHECK (active_to IS NULL OR active_to > active_from)
);

CREATE TABLE IF NOT EXISTS dwms.bonded_staff_assignments (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL,
    bonded_facility_id uuid NOT NULL,
    user_id uuid NOT NULL REFERENCES dwms.users(id),
    staff_role_code varchar(100) NOT NULL,
    authorization_no varchar(200),
    authorization_scope jsonb NOT NULL DEFAULT '{}'::jsonb,
    valid_from date NOT NULL,
    valid_to date,
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    approved_by uuid REFERENCES dwms.users(id),
    approved_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (bonded_facility_id, user_id, staff_role_code, valid_from),
    FOREIGN KEY (tenant_id, bonded_facility_id)
        REFERENCES dwms.bonded_facilities(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_dwms_bonded_staff_dates CHECK (valid_to IS NULL OR valid_to >= valid_from),
    CONSTRAINT ck_dwms_bonded_staff_status CHECK (status IN ('PENDING','ACTIVE','SUSPENDED','EXPIRED','REVOKED'))
);

CREATE TABLE IF NOT EXISTS dwms.bonded_storage_rules (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid REFERENCES dwms.tenants(id) ON DELETE CASCADE,
    bonded_facility_id uuid REFERENCES dwms.bonded_facilities(id),
    jurisdiction_country_code char(2) NOT NULL DEFAULT 'KR' REFERENCES dwms.countries(country_code),
    rule_code varchar(100) NOT NULL,
    rule_name varchar(250) NOT NULL,
    facility_type_code varchar(100),
    cargo_category_code varchar(100),
    legal_status_code varchar(100),
    base_period_days integer NOT NULL,
    maximum_extension_days integer,
    maximum_extension_count integer,
    notice_lead_days integer,
    overdue_action_code varchar(100),
    regulatory_source_uri text,
    authority_reference varchar(300),
    effective_from date NOT NULL,
    effective_to date,
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_dwms_bonded_storage_rule_period CHECK (
        base_period_days > 0 AND (maximum_extension_days IS NULL OR maximum_extension_days >= 0) AND
        (maximum_extension_count IS NULL OR maximum_extension_count >= 0) AND
        (notice_lead_days IS NULL OR notice_lead_days >= 0)
    ),
    CONSTRAINT ck_dwms_bonded_storage_rule_dates CHECK (effective_to IS NULL OR effective_to >= effective_from)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_dwms_bonded_storage_rule_scope
    ON dwms.bonded_storage_rules (
        COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid),
        COALESCE(bonded_facility_id, '00000000-0000-0000-0000-000000000000'::uuid),
        rule_code, effective_from
    );

CREATE TABLE IF NOT EXISTS dwms.bonded_cargo (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    owner_partner_id uuid NOT NULL REFERENCES dwms.business_partners(id),
    bonded_facility_id uuid NOT NULL,
    warehouse_id uuid NOT NULL REFERENCES dwms.warehouses(id),
    bonded_cargo_no varchar(120) NOT NULL,
    cargo_management_no_raw varchar(200),
    cargo_management_no_normalized varchar(200),
    manifest_reference_no varchar(200),
    master_bl_awb_serial varchar(100),
    house_bl_awb_serial varchar(100),
    trade_shipment_id uuid REFERENCES dwms.trade_shipments(id),
    customs_declaration_id uuid REFERENCES dwms.customs_declarations(id),
    receipt_id uuid REFERENCES dwms.receipts(id),
    shipper_partner_id uuid REFERENCES dwms.business_partners(id),
    consignee_partner_id uuid REFERENCES dwms.business_partners(id),
    cargo_category_code varchar(100),
    package_count numeric(20,4),
    package_type_code varchar(50),
    gross_weight numeric(24,8),
    net_weight numeric(24,8),
    weight_uom_code varchar(20) REFERENCES dwms.units_of_measure(uom_code),
    physical_status varchar(30) NOT NULL DEFAULT 'EXPECTED',
    legal_status varchar(40) NOT NULL DEFAULT 'FOREIGN',
    customs_hold_status varchar(30) NOT NULL DEFAULT 'CLEAR',
    current_storage_due_on date,
    first_arrived_at timestamptz,
    physically_received_at timestamptz,
    last_physical_release_at timestamptz,
    closed_at timestamptz,
    retention_until date,
    legal_hold boolean NOT NULL DEFAULT false,
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_by uuid REFERENCES dwms.users(id),
    updated_by uuid REFERENCES dwms.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, bonded_cargo_no),
    UNIQUE (tenant_id, owner_partner_id, id),
    FOREIGN KEY (tenant_id, bonded_facility_id)
        REFERENCES dwms.bonded_facilities(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_dwms_bonded_cargo_physical CHECK (physical_status IN (
        'EXPECTED','ARRIVED','RECEIVING','STORED','HANDLING','STAGED_OUT','PARTIALLY_RELEASED',
        'RELEASED','IN_TRANSIT','MISSING','DESTROYED','CLOSED'
    )),
    CONSTRAINT ck_dwms_bonded_cargo_legal CHECK (legal_status IN (
        'FOREIGN','DOMESTIC','EXPORT','CONDITIONAL_RELEASE','BONDED_TRANSIT','SEIZED','ABANDONED','DISPOSAL_PENDING','DISPOSED'
    )),
    CONSTRAINT ck_dwms_bonded_cargo_hold CHECK (customs_hold_status IN ('CLEAR','HOLD','INSPECTION','SEIZED','RELEASED')),
    CONSTRAINT ck_dwms_bonded_cargo_qty CHECK (
        (package_count IS NULL OR package_count >= 0) AND (gross_weight IS NULL OR gross_weight >= 0) AND
        (net_weight IS NULL OR net_weight >= 0) AND
        (gross_weight IS NULL OR net_weight IS NULL OR gross_weight >= net_weight)
    ),
    CONSTRAINT ck_dwms_bonded_cargo_dates CHECK (
        (physically_received_at IS NULL OR first_arrived_at IS NULL OR physically_received_at >= first_arrived_at) AND
        (last_physical_release_at IS NULL OR physically_received_at IS NULL OR last_physical_release_at >= physically_received_at) AND
        (closed_at IS NULL OR physically_received_at IS NULL OR closed_at >= physically_received_at)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_dwms_bonded_cargo_management_no
    ON dwms.bonded_cargo (tenant_id, owner_partner_id, cargo_management_no_normalized)
    WHERE cargo_management_no_normalized IS NOT NULL;

CREATE INDEX IF NOT EXISTS ix_dwms_bonded_cargo_due
    ON dwms.bonded_cargo (tenant_id, bonded_facility_id, current_storage_due_on)
    WHERE physical_status NOT IN ('RELEASED','DESTROYED','CLOSED');

CREATE TABLE IF NOT EXISTS dwms.bonded_cargo_status_events (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL,
    owner_partner_id uuid NOT NULL,
    bonded_cargo_id uuid NOT NULL,
    sequence_no bigint NOT NULL,
    from_physical_status varchar(30),
    to_physical_status varchar(30),
    from_legal_status varchar(40),
    to_legal_status varchar(40),
    event_type varchar(80) NOT NULL,
    reason_code_id uuid REFERENCES dwms.reason_codes(id),
    reason_text text,
    occurred_at timestamptz NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT now(),
    actor_user_id uuid REFERENCES dwms.users(id),
    customs_reference varchar(300),
    detail_masked jsonb NOT NULL DEFAULT '{}'::jsonb,
    UNIQUE (bonded_cargo_id, sequence_no),
    FOREIGN KEY (tenant_id, owner_partner_id, bonded_cargo_id)
        REFERENCES dwms.bonded_cargo(tenant_id, owner_partner_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_dwms_bonded_cargo_event_seq CHECK (sequence_no > 0),
    CONSTRAINT ck_dwms_bonded_cargo_event_change CHECK (
        to_physical_status IS NOT NULL OR to_legal_status IS NOT NULL OR event_type IS NOT NULL
    )
);

CREATE TABLE IF NOT EXISTS dwms.bonded_cargo_items (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL,
    owner_partner_id uuid NOT NULL,
    bonded_cargo_id uuid NOT NULL,
    line_no integer NOT NULL,
    item_id uuid NOT NULL REFERENCES dwms.items(id),
    customs_declaration_line_id uuid REFERENCES dwms.customs_declaration_lines(id),
    commercial_invoice_line_id uuid REFERENCES dwms.commercial_invoice_lines(id),
    inventory_lot_id uuid REFERENCES dwms.inventory_lots(id),
    serial_number_id uuid REFERENCES dwms.serial_numbers(id),
    hs_code_snapshot varchar(20),
    goods_description varchar(2000),
    country_of_origin char(2) REFERENCES dwms.countries(country_code),
    declared_quantity numeric(24,8) NOT NULL DEFAULT 0,
    received_quantity numeric(24,8) NOT NULL DEFAULT 0,
    current_quantity numeric(24,8) NOT NULL DEFAULT 0,
    released_quantity numeric(24,8) NOT NULL DEFAULT 0,
    damaged_quantity numeric(24,8) NOT NULL DEFAULT 0,
    base_uom_code varchar(20) NOT NULL REFERENCES dwms.units_of_measure(uom_code),
    package_count numeric(20,4),
    gross_weight numeric(24,8),
    net_weight numeric(24,8),
    weight_uom_code varchar(20) REFERENCES dwms.units_of_measure(uom_code),
    status varchar(20) NOT NULL DEFAULT 'EXPECTED',
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (bonded_cargo_id, line_no),
    UNIQUE (bonded_cargo_id, id),
    UNIQUE (tenant_id, owner_partner_id, id),
    FOREIGN KEY (tenant_id, owner_partner_id, bonded_cargo_id)
        REFERENCES dwms.bonded_cargo(tenant_id, owner_partner_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_dwms_bonded_cargo_item_no CHECK (line_no > 0),
    CONSTRAINT ck_dwms_bonded_cargo_item_qty CHECK (
        declared_quantity >= 0 AND received_quantity >= 0 AND current_quantity >= 0 AND
        released_quantity >= 0 AND damaged_quantity >= 0 AND
        current_quantity + released_quantity + damaged_quantity <= received_quantity
    ),
    CONSTRAINT ck_dwms_bonded_cargo_item_weight CHECK (
        (package_count IS NULL OR package_count >= 0) AND (gross_weight IS NULL OR gross_weight >= 0) AND
        (net_weight IS NULL OR net_weight >= 0) AND
        (gross_weight IS NULL OR net_weight IS NULL OR gross_weight >= net_weight)
    ),
    CONSTRAINT ck_dwms_bonded_cargo_item_status CHECK (status IN (
        'EXPECTED','RECEIVED','STORED','PARTIALLY_RELEASED','RELEASED','DAMAGED','MISSING','DESTROYED','CLOSED'
    ))
);

CREATE TABLE IF NOT EXISTS dwms.bonded_cargo_relations (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    owner_partner_id uuid NOT NULL REFERENCES dwms.business_partners(id),
    parent_cargo_id uuid NOT NULL REFERENCES dwms.bonded_cargo(id),
    child_cargo_id uuid NOT NULL REFERENCES dwms.bonded_cargo(id),
    relation_type varchar(30) NOT NULL,
    parent_quantity numeric(24,8),
    child_quantity numeric(24,8),
    uom_code varchar(20) REFERENCES dwms.units_of_measure(uom_code),
    customs_authorization_reference varchar(300),
    effective_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid REFERENCES dwms.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (parent_cargo_id, child_cargo_id, relation_type, effective_at),
    CONSTRAINT ck_dwms_bonded_cargo_relation_self CHECK (parent_cargo_id <> child_cargo_id),
    CONSTRAINT ck_dwms_bonded_cargo_relation_type CHECK (relation_type IN ('SPLIT','MERGE','REPACK','SUCCESSOR','RETURN','RELATED')),
    CONSTRAINT ck_dwms_bonded_cargo_relation_qty CHECK (
        (parent_quantity IS NULL OR parent_quantity > 0) AND (child_quantity IS NULL OR child_quantity > 0)
    )
);

CREATE TABLE IF NOT EXISTS dwms.bonded_cargo_containers (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL,
    owner_partner_id uuid NOT NULL,
    bonded_cargo_id uuid NOT NULL,
    trade_container_id uuid NOT NULL REFERENCES dwms.trade_containers(id),
    package_count numeric(20,4),
    gross_weight numeric(24,8),
    weight_uom_code varchar(20) REFERENCES dwms.units_of_measure(uom_code),
    stuffed_at timestamptz,
    unstuffed_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (bonded_cargo_id, trade_container_id),
    FOREIGN KEY (tenant_id, owner_partner_id, bonded_cargo_id)
        REFERENCES dwms.bonded_cargo(tenant_id, owner_partner_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_dwms_bonded_cargo_container_qty CHECK (
        (package_count IS NULL OR package_count >= 0) AND (gross_weight IS NULL OR gross_weight >= 0)
    ),
    CONSTRAINT ck_dwms_bonded_cargo_container_dates CHECK (unstuffed_at IS NULL OR stuffed_at IS NULL OR unstuffed_at >= stuffed_at)
);

CREATE TABLE IF NOT EXISTS dwms.bonded_inout_reports (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    owner_partner_id uuid NOT NULL REFERENCES dwms.business_partners(id),
    bonded_facility_id uuid NOT NULL REFERENCES dwms.bonded_facilities(id),
    bonded_cargo_id uuid NOT NULL REFERENCES dwms.bonded_cargo(id),
    report_key varchar(120) NOT NULL,
    report_type varchar(30) NOT NULL,
    customs_report_no_raw varchar(200),
    customs_report_no_normalized varchar(200),
    current_version_id uuid,
    current_version_no integer,
    report_status varchar(30) NOT NULL DEFAULT 'DRAFT',
    acceptance_status varchar(30) NOT NULL DEFAULT 'NOT_SUBMITTED',
    submitted_at timestamptz,
    customs_system_recorded_at timestamptz,
    accepted_at timestamptz,
    rejected_at timestamptz,
    accepted_unipass_message_id uuid REFERENCES dwms.unipass_messages(id),
    retention_until date,
    legal_hold boolean NOT NULL DEFAULT false,
    row_version bigint NOT NULL DEFAULT 1,
    created_by uuid REFERENCES dwms.users(id),
    updated_by uuid REFERENCES dwms.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, report_key),
    UNIQUE (tenant_id, owner_partner_id, id),
    FOREIGN KEY (tenant_id, bonded_facility_id)
        REFERENCES dwms.bonded_facilities(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, owner_partner_id, bonded_cargo_id)
        REFERENCES dwms.bonded_cargo(tenant_id, owner_partner_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_dwms_bonded_report_type CHECK (report_type IN ('INBOUND','OUTBOUND','DISCREPANCY','CORRECTION','CANCELLATION')),
    CONSTRAINT ck_dwms_bonded_report_status CHECK (report_status IN (
        'DRAFT','PREPARED','SUBMITTED','ACCEPTED','REJECTED','CORRECTION_REQUIRED','WITHDRAWN','CANCELLED'
    )),
    CONSTRAINT ck_dwms_bonded_report_acceptance CHECK (acceptance_status IN (
        'NOT_SUBMITTED','PENDING','ACCEPTED','REJECTED','ERROR','WITHDRAWN'
    )),
    CONSTRAINT ck_dwms_bonded_report_version CHECK (
        (current_version_id IS NULL AND current_version_no IS NULL) OR
        (current_version_id IS NOT NULL AND current_version_no > 0)
    ),
    CONSTRAINT ck_dwms_bonded_report_acceptance_fields CHECK (
        (acceptance_status <> 'ACCEPTED') OR (accepted_at IS NOT NULL AND accepted_unipass_message_id IS NOT NULL)
    ),
    CONSTRAINT ck_dwms_bonded_report_dates CHECK (
        (customs_system_recorded_at IS NULL OR submitted_at IS NULL OR customs_system_recorded_at >= submitted_at) AND
        (accepted_at IS NULL OR submitted_at IS NULL OR accepted_at >= submitted_at) AND
        (rejected_at IS NULL OR submitted_at IS NULL OR rejected_at >= submitted_at)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_dwms_bonded_customs_report_no
    ON dwms.bonded_inout_reports (tenant_id, customs_report_no_normalized)
    WHERE customs_report_no_normalized IS NOT NULL;

CREATE TABLE IF NOT EXISTS dwms.bonded_inout_report_versions (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL,
    owner_partner_id uuid NOT NULL,
    bonded_inout_report_id uuid NOT NULL,
    version_no integer NOT NULL,
    filing_action varchar(30) NOT NULL DEFAULT 'ORIGINAL',
    correction_reason_code varchar(100),
    correction_reason_text text,
    supersedes_version_id uuid REFERENCES dwms.bonded_inout_report_versions(id),
    submission_no varchar(200),
    cargo_management_no_snapshot varchar(200),
    facility_customs_code_snapshot varchar(150),
    vehicle_no_snapshot varchar(100),
    physical_event_at timestamptz,
    declared_package_count numeric(20,4),
    declared_quantity numeric(24,8),
    declared_base_uom_code varchar(20) REFERENCES dwms.units_of_measure(uom_code),
    declared_gross_weight numeric(24,8),
    weight_uom_code varchar(20) REFERENCES dwms.units_of_measure(uom_code),
    declared_line_count integer,
    payload_summary_masked jsonb NOT NULL DEFAULT '{}'::jsonb,
    prepared_by uuid REFERENCES dwms.users(id),
    prepared_at timestamptz NOT NULL DEFAULT now(),
    sealed_by uuid REFERENCES dwms.users(id),
    sealed_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (bonded_inout_report_id, version_no),
    UNIQUE (bonded_inout_report_id, id),
    UNIQUE (tenant_id, owner_partner_id, id),
    FOREIGN KEY (tenant_id, owner_partner_id, bonded_inout_report_id)
        REFERENCES dwms.bonded_inout_reports(tenant_id, owner_partner_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_dwms_bonded_report_version_no CHECK (version_no > 0),
    CONSTRAINT ck_dwms_bonded_report_version_action CHECK (filing_action IN (
        'ORIGINAL','CORRECTION','CANCELLATION','RESUBMISSION','OFFICIAL_CORRECTION'
    )),
    CONSTRAINT ck_dwms_bonded_report_version_supersedes CHECK (supersedes_version_id IS NULL OR supersedes_version_id <> id),
    CONSTRAINT ck_dwms_bonded_report_version_qty CHECK (
        (declared_package_count IS NULL OR declared_package_count >= 0) AND
        (declared_quantity IS NULL OR (declared_quantity >= 0 AND declared_base_uom_code IS NOT NULL)) AND
        (declared_gross_weight IS NULL OR declared_gross_weight >= 0) AND
        (declared_line_count IS NULL OR declared_line_count >= 0)
    ),
    CONSTRAINT ck_dwms_bonded_report_version_seal CHECK (
        (sealed_at IS NULL AND sealed_by IS NULL) OR (sealed_at IS NOT NULL AND sealed_by IS NOT NULL)
    )
);

DO $block$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'dwms.bonded_inout_reports'::regclass
          AND conname = 'fk_dwms_bonded_report_current_version'
    ) THEN
        ALTER TABLE dwms.bonded_inout_reports
            ADD CONSTRAINT fk_dwms_bonded_report_current_version
            FOREIGN KEY (id, current_version_id)
            REFERENCES dwms.bonded_inout_report_versions(bonded_inout_report_id, id)
            DEFERRABLE INITIALLY DEFERRED;
    END IF;
END;
$block$;

CREATE TABLE IF NOT EXISTS dwms.bonded_inout_report_lines (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL,
    owner_partner_id uuid NOT NULL,
    bonded_inout_report_version_id uuid NOT NULL,
    line_no integer NOT NULL,
    bonded_cargo_item_id uuid NOT NULL REFERENCES dwms.bonded_cargo_items(id),
    warehouse_location_id uuid REFERENCES dwms.warehouse_locations(id),
    trade_container_id uuid REFERENCES dwms.trade_containers(id),
    item_id uuid NOT NULL REFERENCES dwms.items(id),
    hs_code_snapshot varchar(20),
    goods_description_snapshot varchar(2000),
    legal_status_code varchar(100) NOT NULL,
    package_count numeric(20,4),
    reported_quantity numeric(24,8) NOT NULL,
    base_uom_code varchar(20) NOT NULL REFERENCES dwms.units_of_measure(uom_code),
    gross_weight numeric(24,8),
    weight_uom_code varchar(20) REFERENCES dwms.units_of_measure(uom_code),
    discrepancy_code varchar(100),
    physical_event_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (bonded_inout_report_version_id, line_no),
    UNIQUE (tenant_id, owner_partner_id, id),
    FOREIGN KEY (tenant_id, owner_partner_id, bonded_inout_report_version_id)
        REFERENCES dwms.bonded_inout_report_versions(tenant_id, owner_partner_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_dwms_bonded_report_line_no CHECK (line_no > 0),
    CONSTRAINT ck_dwms_bonded_report_line_qty CHECK (
        reported_quantity > 0 AND (package_count IS NULL OR package_count >= 0) AND
        (gross_weight IS NULL OR gross_weight >= 0)
    )
);

-- Structured, append-only parsing evidence for official UNI-PASS result messages.
-- The raw/result payload remains in protected object storage; this row binds the
-- authenticated transport, registered schema, payload hash, legal reference, owner,
-- and official decision that downstream bonded release controls are allowed to trust.
CREATE TABLE IF NOT EXISTS dwms.unipass_message_results (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    owner_partner_id uuid NOT NULL REFERENCES dwms.business_partners(id),
    unipass_message_id uuid NOT NULL REFERENCES dwms.unipass_messages(id) ON DELETE RESTRICT,
    result_sequence integer NOT NULL DEFAULT 1,
    result_purpose varchar(50) NOT NULL,
    decision_code varchar(80) NOT NULL,
    legal_reference_type varchar(50) NOT NULL,
    legal_reference_no_normalized varchar(300) NOT NULL,
    legal_version_no integer NOT NULL,
    subject_owner_partner_id uuid NOT NULL REFERENCES dwms.business_partners(id),
    official_decision_at timestamptz NOT NULL,
    message_schema_id uuid NOT NULL REFERENCES dwms.customs_message_schemas(id) ON DELETE RESTRICT,
    payload_sha256_snapshot char(64) NOT NULL,
    transport_authenticated_at timestamptz NOT NULL,
    schema_validated_at timestamptz NOT NULL,
    parsed_at timestamptz NOT NULL,
    recorded_by uuid REFERENCES dwms.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (unipass_message_id, result_sequence),
    UNIQUE (
        unipass_message_id, result_purpose, legal_reference_type,
        legal_reference_no_normalized, legal_version_no
    ),
    UNIQUE (tenant_id, owner_partner_id, id),
    CONSTRAINT ck_dwms_unipass_result_sequence CHECK (result_sequence > 0),
    CONSTRAINT ck_dwms_unipass_result_purpose CHECK (
        result_purpose IN ('BONDED_INOUT_ACCEPTANCE')
    ),
    CONSTRAINT ck_dwms_unipass_result_reference CHECK (
        legal_reference_type = 'BONDED_INOUT_REPORT' AND
        btrim(legal_reference_no_normalized) <> '' AND legal_version_no > 0
    ),
    CONSTRAINT ck_dwms_unipass_result_decision CHECK (
        decision_code IN ('BONDED_REPORT_ACCEPTED')
    ),
    CONSTRAINT ck_dwms_unipass_result_hash CHECK (
        payload_sha256_snapshot ~ '^[0-9A-Fa-f]{64}$'
    ),
    CONSTRAINT ck_dwms_unipass_result_times CHECK (
        transport_authenticated_at <= schema_validated_at AND
        schema_validated_at <= parsed_at AND official_decision_at <= parsed_at
    )
);

CREATE TABLE IF NOT EXISTS dwms.bonded_discrepancies (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL,
    owner_partner_id uuid NOT NULL,
    bonded_cargo_id uuid NOT NULL,
    bonded_cargo_item_id uuid REFERENCES dwms.bonded_cargo_items(id),
    discrepancy_no varchar(120) NOT NULL,
    discrepancy_type varchar(40) NOT NULL,
    detected_during varchar(40) NOT NULL,
    expected_quantity numeric(24,8),
    actual_quantity numeric(24,8),
    variance_quantity numeric(24,8),
    base_uom_code varchar(20) REFERENCES dwms.units_of_measure(uom_code),
    expected_package_count numeric(20,4),
    actual_package_count numeric(20,4),
    reason_code_id uuid REFERENCES dwms.reason_codes(id),
    description text,
    evidence_file_id uuid REFERENCES dwms.files(id),
    customs_report_id uuid REFERENCES dwms.bonded_inout_reports(id),
    status varchar(30) NOT NULL DEFAULT 'OPEN',
    detected_at timestamptz NOT NULL DEFAULT now(),
    reported_at timestamptz,
    resolved_at timestamptz,
    resolved_by uuid REFERENCES dwms.users(id),
    resolution_text text,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, discrepancy_no),
    FOREIGN KEY (tenant_id, owner_partner_id, bonded_cargo_id)
        REFERENCES dwms.bonded_cargo(tenant_id, owner_partner_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (bonded_cargo_id, bonded_cargo_item_id)
        REFERENCES dwms.bonded_cargo_items(bonded_cargo_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_dwms_bonded_discrepancy_type CHECK (discrepancy_type IN (
        'SHORTAGE','OVERAGE','DAMAGE','MISDESCRIPTION','WRONG_ITEM','SEAL_BROKEN','MISSING','OTHER'
    )),
    CONSTRAINT ck_dwms_bonded_discrepancy_qty CHECK (
        (expected_quantity IS NULL OR expected_quantity >= 0) AND
        (actual_quantity IS NULL OR actual_quantity >= 0) AND
        (expected_package_count IS NULL OR expected_package_count >= 0) AND
        (actual_package_count IS NULL OR actual_package_count >= 0)
    ),
    CONSTRAINT ck_dwms_bonded_discrepancy_status CHECK (status IN (
        'OPEN','REPORTED','UNDER_REVIEW','ADJUSTMENT_APPROVED','RESOLVED','REJECTED','CANCELLED'
    )),
    CONSTRAINT ck_dwms_bonded_discrepancy_dates CHECK (
        (reported_at IS NULL OR reported_at >= detected_at) AND
        (resolved_at IS NULL OR resolved_at >= detected_at)
    )
);

CREATE TABLE IF NOT EXISTS dwms.bonded_movement_groups (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL,
    owner_partner_id uuid NOT NULL,
    bonded_cargo_id uuid NOT NULL,
    movement_group_no varchar(120) NOT NULL,
    group_type varchar(40) NOT NULL,
    requires_zero_sum boolean NOT NULL DEFAULT false,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    source_document_type varchar(80),
    source_document_id uuid,
    authorized_reference varchar(300),
    occurred_at timestamptz NOT NULL,
    posted_at timestamptz,
    posted_by uuid REFERENCES dwms.users(id),
    reversal_of_group_id uuid REFERENCES dwms.bonded_movement_groups(id),
    reason_code_id uuid REFERENCES dwms.reason_codes(id),
    reason_text text,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, movement_group_no),
    UNIQUE (tenant_id, owner_partner_id, id),
    FOREIGN KEY (tenant_id, owner_partner_id, bonded_cargo_id)
        REFERENCES dwms.bonded_cargo(tenant_id, owner_partner_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_dwms_bonded_group_type CHECK (group_type IN (
        'INBOUND','OUTBOUND','TRANSFER','LEGAL_STATUS_CHANGE','ADJUSTMENT','SPLIT','MERGE',
        'HANDLING','SAMPLE','DISPOSAL','COUNT','REVERSAL','OTHER'
    )),
    CONSTRAINT ck_dwms_bonded_group_conservation CHECK (
        group_type NOT IN ('TRANSFER','LEGAL_STATUS_CHANGE','SPLIT','MERGE') OR requires_zero_sum
    ),
    CONSTRAINT ck_dwms_bonded_group_status CHECK (status IN ('DRAFT','VALIDATED','POSTED','REVERSED','CANCELLED')),
    CONSTRAINT ck_dwms_bonded_group_posted CHECK (
        (status IN ('POSTED','REVERSED') AND posted_at IS NOT NULL AND posted_by IS NOT NULL) OR
        status NOT IN ('POSTED','REVERSED')
    ),
    CONSTRAINT ck_dwms_bonded_group_reversal CHECK (
        (group_type = 'REVERSAL' AND reversal_of_group_id IS NOT NULL) OR
        (group_type <> 'REVERSAL' AND reversal_of_group_id IS NULL)
    ),
    CONSTRAINT ck_dwms_bonded_group_reversal_self CHECK (reversal_of_group_id IS NULL OR reversal_of_group_id <> id)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_dwms_bonded_group_reversal
    ON dwms.bonded_movement_groups (reversal_of_group_id)
    WHERE reversal_of_group_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS dwms.bonded_exception_authorizations (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    owner_partner_id uuid NOT NULL REFERENCES dwms.business_partners(id),
    bonded_facility_id uuid NOT NULL,
    bonded_cargo_id uuid NOT NULL,
    bonded_cargo_item_id uuid,
    bonded_inout_report_id uuid,
    authorization_no varchar(200) NOT NULL,
    issuer_authority_code varchar(100) NOT NULL,
    authorization_scope varchar(20) NOT NULL DEFAULT 'CARGO',
    authorized_movement_type varchar(40) NOT NULL,
    authorized_quantity numeric(24,8) NOT NULL,
    base_uom_code varchar(20) NOT NULL REFERENCES dwms.units_of_measure(uom_code),
    valid_from timestamptz NOT NULL,
    valid_until timestamptz NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    request_reason text NOT NULL,
    requested_by uuid NOT NULL REFERENCES dwms.users(id),
    requested_at timestamptz NOT NULL DEFAULT now(),
    approved_by uuid REFERENCES dwms.users(id),
    approved_at timestamptz,
    rejected_by uuid REFERENCES dwms.users(id),
    rejected_at timestamptz,
    decision_reason text,
    cancelled_by uuid REFERENCES dwms.users(id),
    cancelled_at timestamptz,
    cancellation_reason text,
    evidence_file_id uuid REFERENCES dwms.files(id),
    consumed_at timestamptz,
    consumed_by_movement_id uuid,
    revoked_by uuid REFERENCES dwms.users(id),
    revoked_at timestamptz,
    revocation_reason text,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, issuer_authority_code, authorization_no),
    UNIQUE (tenant_id, owner_partner_id, id),
    UNIQUE (consumed_by_movement_id),
    FOREIGN KEY (tenant_id, bonded_facility_id)
        REFERENCES dwms.bonded_facilities(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, owner_partner_id, bonded_cargo_id)
        REFERENCES dwms.bonded_cargo(tenant_id, owner_partner_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, owner_partner_id, bonded_cargo_item_id)
        REFERENCES dwms.bonded_cargo_items(tenant_id, owner_partner_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (bonded_cargo_id, bonded_cargo_item_id)
        REFERENCES dwms.bonded_cargo_items(bonded_cargo_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, owner_partner_id, bonded_inout_report_id)
        REFERENCES dwms.bonded_inout_reports(tenant_id, owner_partner_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_dwms_bonded_exception_scope CHECK (
        (authorization_scope = 'CARGO' AND bonded_inout_report_id IS NULL) OR
        (authorization_scope = 'REPORT' AND bonded_inout_report_id IS NOT NULL)
    ),
    CONSTRAINT ck_dwms_bonded_exception_movement CHECK (
        authorized_movement_type IN ('OUTBOUND','TRANSFER_OUT','SAMPLE_OUT','DISPOSAL_OUT')
    ),
    CONSTRAINT ck_dwms_bonded_exception_quantity CHECK (authorized_quantity > 0),
    CONSTRAINT ck_dwms_bonded_exception_window CHECK (valid_until > valid_from),
    CONSTRAINT ck_dwms_bonded_exception_status CHECK (
        status IN ('DRAFT','PENDING','APPROVED','CONSUMED','REJECTED','REVOKED','CANCELLED')
    ),
    CONSTRAINT ck_dwms_bonded_exception_approval CHECK (
        (status IN ('APPROVED','CONSUMED','REVOKED') AND
            approved_by IS NOT NULL AND approved_at IS NOT NULL AND evidence_file_id IS NOT NULL AND
            approved_by <> requested_by) OR
        (status NOT IN ('APPROVED','CONSUMED','REVOKED') AND approved_by IS NULL AND approved_at IS NULL)
    ),
    CONSTRAINT ck_dwms_bonded_exception_rejection CHECK (
        (status = 'REJECTED' AND
            rejected_by IS NOT NULL AND rejected_at IS NOT NULL AND
            COALESCE(btrim(decision_reason), '') <> '') OR
        (status <> 'REJECTED' AND rejected_by IS NULL AND rejected_at IS NULL AND decision_reason IS NULL)
    ),
    CONSTRAINT ck_dwms_bonded_exception_cancellation CHECK (
        (status = 'CANCELLED' AND cancelled_by IS NOT NULL AND cancelled_at IS NOT NULL AND
            COALESCE(btrim(cancellation_reason), '') <> '') OR
        (status <> 'CANCELLED' AND cancelled_by IS NULL AND cancelled_at IS NULL AND cancellation_reason IS NULL)
    ),
    CONSTRAINT ck_dwms_bonded_exception_consumption CHECK (
        (status = 'CONSUMED' AND consumed_at IS NOT NULL AND consumed_by_movement_id IS NOT NULL) OR
        (status <> 'CONSUMED' AND consumed_at IS NULL AND consumed_by_movement_id IS NULL)
    ),
    CONSTRAINT ck_dwms_bonded_exception_revocation CHECK (
        (status = 'REVOKED' AND revoked_by IS NOT NULL AND revoked_at IS NOT NULL AND
            COALESCE(btrim(revocation_reason), '') <> '') OR
        (status <> 'REVOKED' AND revoked_by IS NULL AND revoked_at IS NULL AND revocation_reason IS NULL)
    ),
    CONSTRAINT ck_dwms_bonded_exception_dates CHECK (
        (approved_at IS NULL OR approved_at >= requested_at) AND
        (approved_at IS NULL OR approved_at < valid_until) AND
        (rejected_at IS NULL OR rejected_at >= requested_at) AND
        (cancelled_at IS NULL OR cancelled_at >= requested_at) AND
        (consumed_at IS NULL OR approved_at IS NULL OR consumed_at >= approved_at) AND
        (revoked_at IS NULL OR approved_at IS NULL OR revoked_at >= approved_at)
    )
);

CREATE TABLE IF NOT EXISTS dwms.bonded_inventory_movements (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL,
    owner_partner_id uuid NOT NULL,
    bonded_movement_group_id uuid NOT NULL REFERENCES dwms.bonded_movement_groups(id),
    bonded_cargo_id uuid NOT NULL,
    bonded_cargo_item_id uuid NOT NULL,
    movement_sequence integer NOT NULL,
    movement_type varchar(40) NOT NULL,
    warehouse_id uuid NOT NULL REFERENCES dwms.warehouses(id),
    warehouse_location_id uuid NOT NULL REFERENCES dwms.warehouse_locations(id),
    legal_status varchar(40) NOT NULL,
    inventory_status_id uuid NOT NULL REFERENCES dwms.inventory_statuses(id),
    stock_bucket_id uuid NOT NULL,
    inventory_lot_id uuid REFERENCES dwms.inventory_lots(id),
    serial_number_id uuid REFERENCES dwms.serial_numbers(id),
    lpn_id uuid REFERENCES dwms.lpns(id),
    quantity_delta numeric(24,8) NOT NULL,
    base_uom_code varchar(20) NOT NULL REFERENCES dwms.units_of_measure(uom_code),
    package_delta numeric(20,4),
    weight_delta numeric(24,8),
    weight_uom_code varchar(20) REFERENCES dwms.units_of_measure(uom_code),
    bonded_inout_report_line_id uuid REFERENCES dwms.bonded_inout_report_lines(id),
    inventory_transaction_id uuid NOT NULL,
    inventory_transaction_entry_id uuid NOT NULL,
    discrepancy_id uuid REFERENCES dwms.bonded_discrepancies(id),
    source_document_type varchar(80),
    source_document_id uuid,
    exception_authorization_id uuid REFERENCES dwms.bonded_exception_authorizations(id),
    exception_authorization_reference varchar(300),
    reversal_of_movement_id uuid REFERENCES dwms.bonded_inventory_movements(id),
    reason_code_id uuid REFERENCES dwms.reason_codes(id),
    reason_text text,
    occurred_at timestamptz NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT now(),
    recorded_by uuid REFERENCES dwms.users(id),
    correlation_id varchar(100),
    UNIQUE (bonded_cargo_id, movement_sequence),
    UNIQUE (inventory_transaction_entry_id),
    UNIQUE (tenant_id, owner_partner_id, id),
    FOREIGN KEY (tenant_id, owner_partner_id, bonded_cargo_id)
        REFERENCES dwms.bonded_cargo(tenant_id, owner_partner_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, owner_partner_id, bonded_movement_group_id)
        REFERENCES dwms.bonded_movement_groups(tenant_id, owner_partner_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, owner_partner_id, bonded_cargo_item_id)
        REFERENCES dwms.bonded_cargo_items(tenant_id, owner_partner_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (bonded_cargo_id, bonded_cargo_item_id)
        REFERENCES dwms.bonded_cargo_items(bonded_cargo_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, owner_partner_id, exception_authorization_id)
        REFERENCES dwms.bonded_exception_authorizations(tenant_id, owner_partner_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, stock_bucket_id)
        REFERENCES dwms.stock_buckets(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, inventory_transaction_id)
        REFERENCES dwms.inventory_transaction_headers(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, inventory_transaction_entry_id)
        REFERENCES dwms.inventory_transaction_entries(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_dwms_bonded_movement_seq CHECK (movement_sequence > 0),
    CONSTRAINT ck_dwms_bonded_movement_type CHECK (movement_type IN (
        'INBOUND','OUTBOUND','TRANSFER_IN','TRANSFER_OUT','LEGAL_STATUS_IN','LEGAL_STATUS_OUT',
        'ADJUSTMENT_IN','ADJUSTMENT_OUT','HANDLING_INPUT','HANDLING_OUTPUT','SAMPLE_OUT','SAMPLE_RETURN',
        'DISPOSAL_OUT','COUNT_GAIN','COUNT_LOSS','SPLIT_IN','SPLIT_OUT','MERGE_IN','MERGE_OUT','REVERSAL'
    )),
    CONSTRAINT ck_dwms_bonded_movement_qty CHECK (
        CASE
            WHEN movement_type IN (
                'INBOUND','TRANSFER_IN','LEGAL_STATUS_IN','ADJUSTMENT_IN','HANDLING_OUTPUT',
                'SAMPLE_RETURN','COUNT_GAIN','SPLIT_IN','MERGE_IN'
            ) THEN quantity_delta > 0
            WHEN movement_type IN (
                'OUTBOUND','TRANSFER_OUT','LEGAL_STATUS_OUT','ADJUSTMENT_OUT','HANDLING_INPUT',
                'SAMPLE_OUT','DISPOSAL_OUT','COUNT_LOSS','SPLIT_OUT','MERGE_OUT'
            ) THEN quantity_delta < 0
            ELSE quantity_delta <> 0
        END AND
        (package_delta IS NULL OR package_delta <> 0) AND (weight_delta IS NULL OR weight_delta <> 0)
    ),
    CONSTRAINT ck_dwms_bonded_movement_exception CHECK (
        (exception_authorization_id IS NULL AND exception_authorization_reference IS NULL) OR
        (exception_authorization_id IS NOT NULL AND exception_authorization_reference IS NOT NULL)
    ),
    CONSTRAINT ck_dwms_bonded_movement_reversal CHECK (
        (movement_type = 'REVERSAL' AND reversal_of_movement_id IS NOT NULL) OR
        (movement_type <> 'REVERSAL' AND reversal_of_movement_id IS NULL)
    ),
    CONSTRAINT ck_dwms_bonded_movement_reversal_self CHECK (reversal_of_movement_id IS NULL OR reversal_of_movement_id <> id)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_dwms_bonded_movement_reversal
    ON dwms.bonded_inventory_movements (reversal_of_movement_id)
    WHERE reversal_of_movement_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS ux_dwms_bonded_exception_single_use
    ON dwms.bonded_inventory_movements (exception_authorization_id)
    WHERE exception_authorization_id IS NOT NULL;

DO $block$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'dwms.bonded_exception_authorizations'::regclass
          AND conname = 'fk_dwms_bonded_exception_consumed_movement'
    ) THEN
        ALTER TABLE dwms.bonded_exception_authorizations
            ADD CONSTRAINT fk_dwms_bonded_exception_consumed_movement
            FOREIGN KEY (consumed_by_movement_id)
            REFERENCES dwms.bonded_inventory_movements(id) ON DELETE RESTRICT;
    END IF;
END;
$block$;

CREATE TABLE IF NOT EXISTS dwms.bonded_exception_authorization_usages (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    owner_partner_id uuid NOT NULL REFERENCES dwms.business_partners(id),
    bonded_exception_authorization_id uuid NOT NULL,
    bonded_inventory_movement_id uuid NOT NULL,
    used_quantity numeric(24,8) NOT NULL,
    base_uom_code varchar(20) NOT NULL REFERENCES dwms.units_of_measure(uom_code),
    used_at timestamptz NOT NULL,
    used_by uuid REFERENCES dwms.users(id),
    authorization_no_snapshot varchar(200) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (bonded_exception_authorization_id),
    UNIQUE (bonded_inventory_movement_id),
    FOREIGN KEY (tenant_id, owner_partner_id, bonded_exception_authorization_id)
        REFERENCES dwms.bonded_exception_authorizations(tenant_id, owner_partner_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, owner_partner_id, bonded_inventory_movement_id)
        REFERENCES dwms.bonded_inventory_movements(tenant_id, owner_partner_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_dwms_bonded_exception_usage_qty CHECK (used_quantity > 0)
);

CREATE TABLE IF NOT EXISTS dwms.bonded_inventory_balances (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    owner_partner_id uuid NOT NULL REFERENCES dwms.business_partners(id),
    bonded_cargo_id uuid NOT NULL REFERENCES dwms.bonded_cargo(id),
    bonded_cargo_item_id uuid NOT NULL REFERENCES dwms.bonded_cargo_items(id),
    warehouse_id uuid NOT NULL REFERENCES dwms.warehouses(id),
    warehouse_location_id uuid NOT NULL REFERENCES dwms.warehouse_locations(id),
    legal_status varchar(40) NOT NULL,
    inventory_status_id uuid NOT NULL REFERENCES dwms.inventory_statuses(id),
    on_hand_quantity numeric(24,8) NOT NULL DEFAULT 0,
    base_uom_code varchar(20) NOT NULL REFERENCES dwms.units_of_measure(uom_code),
    last_movement_id uuid NOT NULL REFERENCES dwms.bonded_inventory_movements(id),
    last_movement_at timestamptz NOT NULL,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_dwms_bonded_balance_dimensions UNIQUE (
        tenant_id, owner_partner_id, bonded_cargo_item_id, warehouse_location_id, legal_status, inventory_status_id
    ),
    CONSTRAINT ck_dwms_bonded_balance_nonnegative CHECK (on_hand_quantity >= 0)
);

CREATE TABLE IF NOT EXISTS dwms.bonded_transport_orders (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    owner_partner_id uuid NOT NULL REFERENCES dwms.business_partners(id),
    transport_order_no varchar(120) NOT NULL,
    transport_type_code varchar(100) NOT NULL,
    source_bonded_facility_id uuid NOT NULL REFERENCES dwms.bonded_facilities(id),
    destination_bonded_facility_id uuid REFERENCES dwms.bonded_facilities(id),
    destination_customs_office_code varchar(20) REFERENCES dwms.customs_offices(customs_office_code),
    destination_address_id uuid REFERENCES dwms.addresses(id),
    carrier_partner_id uuid REFERENCES dwms.business_partners(id),
    transport_authorization_no varchar(300),
    approval_status varchar(30) NOT NULL DEFAULT 'NOT_REQUIRED',
    approved_at timestamptz,
    authorized_start_at timestamptz,
    authorized_arrival_due_at timestamptz,
    planned_departure_at timestamptz,
    actual_departure_at timestamptz,
    actual_arrival_at timestamptz,
    status varchar(30) NOT NULL DEFAULT 'DRAFT',
    unipass_message_id uuid REFERENCES dwms.unipass_messages(id),
    retention_until date,
    legal_hold boolean NOT NULL DEFAULT false,
    row_version bigint NOT NULL DEFAULT 1,
    created_by uuid REFERENCES dwms.users(id),
    updated_by uuid REFERENCES dwms.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, transport_order_no),
    UNIQUE (tenant_id, owner_partner_id, id),
    CONSTRAINT ck_dwms_bonded_transport_destination CHECK (
        num_nonnulls(destination_bonded_facility_id, destination_customs_office_code, destination_address_id) >= 1
    ),
    CONSTRAINT ck_dwms_bonded_transport_approval CHECK (approval_status IN (
        'NOT_REQUIRED','PENDING','APPROVED','REJECTED','EXPIRED','CANCELLED'
    )),
    CONSTRAINT ck_dwms_bonded_transport_status CHECK (status IN (
        'DRAFT','PREPARED','AUTHORIZED','DISPATCHED','IN_TRANSIT','ARRIVED','RECEIVED','EXCEPTION','CANCELLED','CLOSED'
    )),
    CONSTRAINT ck_dwms_bonded_transport_dates CHECK (
        (authorized_arrival_due_at IS NULL OR authorized_start_at IS NULL OR authorized_arrival_due_at >= authorized_start_at) AND
        (actual_arrival_at IS NULL OR actual_departure_at IS NULL OR actual_arrival_at >= actual_departure_at)
    )
);

CREATE TABLE IF NOT EXISTS dwms.bonded_transport_cargo (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL,
    owner_partner_id uuid NOT NULL,
    bonded_transport_order_id uuid NOT NULL,
    bonded_cargo_id uuid NOT NULL,
    line_no integer NOT NULL,
    package_count numeric(20,4),
    quantity numeric(24,8),
    base_uom_code varchar(20) REFERENCES dwms.units_of_measure(uom_code),
    gross_weight numeric(24,8),
    weight_uom_code varchar(20) REFERENCES dwms.units_of_measure(uom_code),
    loaded_at timestamptz,
    received_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (bonded_transport_order_id, line_no),
    UNIQUE (bonded_transport_order_id, bonded_cargo_id),
    FOREIGN KEY (tenant_id, owner_partner_id, bonded_transport_order_id)
        REFERENCES dwms.bonded_transport_orders(tenant_id, owner_partner_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, owner_partner_id, bonded_cargo_id)
        REFERENCES dwms.bonded_cargo(tenant_id, owner_partner_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_dwms_bonded_transport_cargo_no CHECK (line_no > 0),
    CONSTRAINT ck_dwms_bonded_transport_cargo_qty CHECK (
        (package_count IS NULL OR package_count >= 0) AND (quantity IS NULL OR quantity > 0) AND
        (gross_weight IS NULL OR gross_weight >= 0)
    ),
    CONSTRAINT ck_dwms_bonded_transport_cargo_dates CHECK (received_at IS NULL OR loaded_at IS NULL OR received_at >= loaded_at)
);

CREATE TABLE IF NOT EXISTS dwms.bonded_transport_vehicles (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    bonded_transport_order_id uuid NOT NULL REFERENCES dwms.bonded_transport_orders(id),
    assignment_no integer NOT NULL,
    vehicle_registration_no varchar(100) NOT NULL,
    trailer_no varchar(100),
    vehicle_type_code varchar(100),
    driver_name_encrypted text,
    driver_name_masked varchar(150),
    driver_phone_encrypted text,
    driver_phone_masked varchar(80),
    assigned_from timestamptz NOT NULL,
    assigned_to timestamptz,
    change_reason text,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (bonded_transport_order_id, assignment_no),
    CONSTRAINT ck_dwms_bonded_transport_vehicle_no CHECK (assignment_no > 0),
    CONSTRAINT ck_dwms_bonded_transport_vehicle_dates CHECK (assigned_to IS NULL OR assigned_to >= assigned_from)
);

CREATE TABLE IF NOT EXISTS dwms.bonded_transport_events (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    bonded_transport_order_id uuid NOT NULL REFERENCES dwms.bonded_transport_orders(id) ON DELETE RESTRICT,
    bonded_transport_vehicle_id uuid REFERENCES dwms.bonded_transport_vehicles(id),
    sequence_no integer NOT NULL,
    event_type varchar(50) NOT NULL,
    event_location varchar(300),
    customs_office_code varchar(20) REFERENCES dwms.customs_offices(customs_office_code),
    occurred_at timestamptz NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT now(),
    vehicle_registration_snapshot varchar(100),
    recipient_name_encrypted text,
    recipient_name_masked varchar(150),
    recipient_partner_id uuid REFERENCES dwms.business_partners(id),
    exception_code varchar(100),
    detail_masked jsonb NOT NULL DEFAULT '{}'::jsonb,
    retention_until date,
    legal_hold boolean NOT NULL DEFAULT false,
    UNIQUE (bonded_transport_order_id, sequence_no),
    CONSTRAINT ck_dwms_bonded_transport_event_no CHECK (sequence_no > 0),
    CONSTRAINT ck_dwms_bonded_transport_event_type CHECK (event_type IN (
        'AUTHORIZED','VEHICLE_ASSIGNED','VEHICLE_CHANGED','LOADED','DEPARTED','CHECKPOINT',
        'ARRIVED','RECEIVED','SEAL_CHECKED','EXCEPTION','DELAYED','CANCELLED','CLOSED'
    )),
    CONSTRAINT ck_dwms_bonded_transport_arrival_evidence CHECK (
        event_type <> 'RECEIVED' OR
        (vehicle_registration_snapshot IS NOT NULL AND (recipient_name_encrypted IS NOT NULL OR recipient_partner_id IS NOT NULL))
    )
);

CREATE TABLE IF NOT EXISTS dwms.bonded_seals (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    owner_partner_id uuid NOT NULL REFERENCES dwms.business_partners(id),
    bonded_cargo_id uuid REFERENCES dwms.bonded_cargo(id),
    trade_container_id uuid REFERENCES dwms.trade_containers(id),
    bonded_transport_order_id uuid REFERENCES dwms.bonded_transport_orders(id),
    seal_no varchar(150) NOT NULL,
    seal_type_code varchar(100) NOT NULL,
    issuer_code varchar(150),
    applied_at timestamptz NOT NULL,
    applied_location varchar(300),
    applied_by uuid REFERENCES dwms.users(id),
    removed_at timestamptz,
    removal_reason_code varchar(100),
    replacement_seal_id uuid REFERENCES dwms.bonded_seals(id),
    status varchar(20) NOT NULL DEFAULT 'APPLIED',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, seal_no, applied_at),
    CONSTRAINT ck_dwms_bonded_seal_target CHECK (
        num_nonnulls(bonded_cargo_id, trade_container_id, bonded_transport_order_id) >= 1
    ),
    CONSTRAINT ck_dwms_bonded_seal_status CHECK (status IN ('APPLIED','VERIFIED','BROKEN','REMOVED','REPLACED','VOID')),
    CONSTRAINT ck_dwms_bonded_seal_dates CHECK (removed_at IS NULL OR removed_at >= applied_at),
    CONSTRAINT ck_dwms_bonded_seal_replacement CHECK (replacement_seal_id IS NULL OR replacement_seal_id <> id)
);

CREATE TABLE IF NOT EXISTS dwms.bonded_seal_checks (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    bonded_seal_id uuid NOT NULL REFERENCES dwms.bonded_seals(id) ON DELETE RESTRICT,
    check_sequence integer NOT NULL,
    check_type varchar(40) NOT NULL,
    expected_seal_no varchar(150),
    observed_seal_no varchar(150),
    result varchar(30) NOT NULL,
    checked_at timestamptz NOT NULL,
    checked_location varchar(300),
    checked_by uuid REFERENCES dwms.users(id),
    evidence_file_id uuid REFERENCES dwms.files(id),
    discrepancy_id uuid REFERENCES dwms.bonded_discrepancies(id),
    note text,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (bonded_seal_id, check_sequence),
    CONSTRAINT ck_dwms_bonded_seal_check_no CHECK (check_sequence > 0),
    CONSTRAINT ck_dwms_bonded_seal_check_result CHECK (result IN ('MATCH','MISMATCH','BROKEN','MISSING','REPLACED','NOT_CHECKED'))
);

CREATE TABLE IF NOT EXISTS dwms.bonded_storage_periods (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL,
    owner_partner_id uuid NOT NULL,
    bonded_cargo_id uuid NOT NULL,
    storage_rule_id uuid NOT NULL REFERENCES dwms.bonded_storage_rules(id),
    period_sequence integer NOT NULL,
    period_start_on date NOT NULL,
    original_due_on date NOT NULL,
    current_due_on date NOT NULL,
    extension_days_granted integer NOT NULL DEFAULT 0,
    extension_count integer NOT NULL DEFAULT 0,
    status varchar(30) NOT NULL DEFAULT 'ACTIVE',
    closed_on date,
    close_reason_code varchar(100),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (bonded_cargo_id, period_sequence),
    UNIQUE (tenant_id, owner_partner_id, id),
    FOREIGN KEY (tenant_id, owner_partner_id, bonded_cargo_id)
        REFERENCES dwms.bonded_cargo(tenant_id, owner_partner_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_dwms_bonded_storage_period_no CHECK (period_sequence > 0),
    CONSTRAINT ck_dwms_bonded_storage_period_dates CHECK (
        original_due_on >= period_start_on AND current_due_on >= original_due_on AND
        (closed_on IS NULL OR closed_on >= period_start_on)
    ),
    CONSTRAINT ck_dwms_bonded_storage_period_extension CHECK (extension_days_granted >= 0 AND extension_count >= 0),
    CONSTRAINT ck_dwms_bonded_storage_period_status CHECK (status IN (
        'ACTIVE','EXTENSION_PENDING','EXTENDED','DUE_SOON','OVERDUE','RELEASED','DISPOSED','CLOSED','CANCELLED'
    ))
);

CREATE TABLE IF NOT EXISTS dwms.bonded_storage_extension_requests (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    owner_partner_id uuid NOT NULL REFERENCES dwms.business_partners(id),
    bonded_storage_period_id uuid NOT NULL REFERENCES dwms.bonded_storage_periods(id),
    request_no varchar(120) NOT NULL,
    requested_on date NOT NULL,
    requested_due_on date NOT NULL,
    requested_days integer NOT NULL,
    reason_code varchar(100),
    reason_text text NOT NULL,
    supporting_document_id uuid REFERENCES dwms.files(id),
    customs_submission_no varchar(200),
    decision_status varchar(30) NOT NULL DEFAULT 'DRAFT',
    approved_due_on date,
    decision_reference varchar(300),
    decided_at timestamptz,
    decision_reason text,
    unipass_message_id uuid REFERENCES dwms.unipass_messages(id),
    row_version bigint NOT NULL DEFAULT 1,
    created_by uuid REFERENCES dwms.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, request_no),
    CONSTRAINT ck_dwms_bonded_extension_days CHECK (requested_days > 0),
    CONSTRAINT ck_dwms_bonded_extension_status CHECK (decision_status IN (
        'DRAFT','SUBMITTED','UNDER_REVIEW','APPROVED','PARTIALLY_APPROVED','REJECTED','WITHDRAWN','CANCELLED'
    )),
    CONSTRAINT ck_dwms_bonded_extension_decision CHECK (
        (decision_status IN ('APPROVED','PARTIALLY_APPROVED') AND approved_due_on IS NOT NULL AND decided_at IS NOT NULL) OR
        decision_status NOT IN ('APPROVED','PARTIALLY_APPROVED')
    )
);

CREATE TABLE IF NOT EXISTS dwms.bonded_release_notices (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    owner_partner_id uuid NOT NULL REFERENCES dwms.business_partners(id),
    bonded_storage_period_id uuid NOT NULL REFERENCES dwms.bonded_storage_periods(id),
    notice_type varchar(50) NOT NULL,
    notice_due_on date NOT NULL,
    recipient_partner_id uuid REFERENCES dwms.business_partners(id),
    recipient_snapshot_masked jsonb NOT NULL DEFAULT '{}'::jsonb,
    delivery_channel varchar(30),
    notice_document_id uuid REFERENCES dwms.files(id),
    sent_at timestamptz,
    delivery_status varchar(30) NOT NULL DEFAULT 'PENDING',
    delivery_reference varchar(300),
    acknowledged_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (bonded_storage_period_id, notice_type, notice_due_on, recipient_partner_id),
    CONSTRAINT ck_dwms_bonded_notice_status CHECK (delivery_status IN ('PENDING','SENT','DELIVERED','FAILED','ACKNOWLEDGED','WAIVED','CANCELLED')),
    CONSTRAINT ck_dwms_bonded_notice_dates CHECK (acknowledged_at IS NULL OR sent_at IS NULL OR acknowledged_at >= sent_at)
);

CREATE TABLE IF NOT EXISTS dwms.bonded_overdue_cases (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    owner_partner_id uuid NOT NULL REFERENCES dwms.business_partners(id),
    bonded_storage_period_id uuid NOT NULL REFERENCES dwms.bonded_storage_periods(id),
    overdue_case_no varchar(120) NOT NULL,
    overdue_from date NOT NULL,
    overdue_category_code varchar(100),
    cargo_management_no_missing boolean NOT NULL DEFAULT false,
    overdue_card_created_at timestamptz,
    disposition_deadline_on date,
    status varchar(30) NOT NULL DEFAULT 'OPEN',
    assigned_to uuid REFERENCES dwms.users(id),
    customs_case_reference varchar(300),
    resolution_code varchar(100),
    resolved_at timestamptz,
    resolution_text text,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, overdue_case_no),
    CONSTRAINT ck_dwms_bonded_overdue_status CHECK (status IN (
        'OPEN','NOTICE_SENT','UNDER_REVIEW','EXTENSION_PENDING','DISPOSITION_PENDING','RESOLVED','CANCELLED'
    )),
    CONSTRAINT ck_dwms_bonded_overdue_dates CHECK (
        (disposition_deadline_on IS NULL OR disposition_deadline_on >= overdue_from) AND
        (resolved_at IS NULL OR resolved_at::date >= overdue_from)
    )
);

CREATE TABLE IF NOT EXISTS dwms.bonded_overdue_events (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    bonded_overdue_case_id uuid NOT NULL REFERENCES dwms.bonded_overdue_cases(id) ON DELETE RESTRICT,
    sequence_no integer NOT NULL,
    event_type varchar(80) NOT NULL,
    from_status varchar(30),
    to_status varchar(30),
    occurred_at timestamptz NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT now(),
    actor_user_id uuid REFERENCES dwms.users(id),
    reference_no varchar(300),
    detail_masked jsonb NOT NULL DEFAULT '{}'::jsonb,
    UNIQUE (bonded_overdue_case_id, sequence_no),
    CONSTRAINT ck_dwms_bonded_overdue_event_no CHECK (sequence_no > 0)
);

CREATE TABLE IF NOT EXISTS dwms.bonded_handling_operations (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    owner_partner_id uuid NOT NULL REFERENCES dwms.business_partners(id),
    bonded_facility_id uuid NOT NULL REFERENCES dwms.bonded_facilities(id),
    bonded_cargo_id uuid NOT NULL REFERENCES dwms.bonded_cargo(id),
    operation_no varchar(120) NOT NULL,
    operation_type varchar(50) NOT NULL,
    authorization_required boolean NOT NULL DEFAULT false,
    authorization_reference varchar(300),
    authorization_at timestamptz,
    planned_start_at timestamptz,
    planned_end_at timestamptz,
    actual_start_at timestamptz,
    actual_end_at timestamptz,
    work_area_id uuid REFERENCES dwms.work_areas(id),
    before_legal_status varchar(40),
    after_legal_status varchar(40),
    hs_code_changed boolean NOT NULL DEFAULT false,
    before_hs_code varchar(20),
    after_hs_code varchar(20),
    requires_declaration_correction boolean NOT NULL DEFAULT false,
    correction_declaration_id uuid REFERENCES dwms.customs_declarations(id),
    status varchar(30) NOT NULL DEFAULT 'DRAFT',
    inventory_transaction_id uuid REFERENCES dwms.inventory_transaction_headers(id),
    movement_group_id uuid REFERENCES dwms.bonded_movement_groups(id),
    instructions text,
    result_summary text,
    row_version bigint NOT NULL DEFAULT 1,
    created_by uuid REFERENCES dwms.users(id),
    updated_by uuid REFERENCES dwms.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, operation_no),
    FOREIGN KEY (tenant_id, owner_partner_id, bonded_cargo_id)
        REFERENCES dwms.bonded_cargo(tenant_id, owner_partner_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_dwms_bonded_handling_type CHECK (operation_type IN (
        'INSPECTION','SAMPLING','REPACK','RECONDITION','SORT','MARK','LABEL','ASSEMBLE',
        'DISASSEMBLE','REPAIR','PROCESS','MANUFACTURE','DESTROY_PREP','OTHER'
    )),
    CONSTRAINT ck_dwms_bonded_handling_status CHECK (status IN (
        'DRAFT','AUTHORIZATION_PENDING','AUTHORIZED','SCHEDULED','IN_PROGRESS','COMPLETED','REJECTED','CANCELLED','REVERSED'
    )),
    CONSTRAINT ck_dwms_bonded_handling_authorization CHECK (
        NOT authorization_required OR authorization_reference IS NOT NULL
    ),
    CONSTRAINT ck_dwms_bonded_handling_hs_change CHECK (
        NOT hs_code_changed OR (
            before_hs_code IS NOT NULL AND after_hs_code IS NOT NULL AND
            before_hs_code <> after_hs_code AND
            (authorization_reference IS NOT NULL OR correction_declaration_id IS NOT NULL)
        )
    ),
    CONSTRAINT ck_dwms_bonded_handling_correction CHECK (
        NOT requires_declaration_correction OR correction_declaration_id IS NOT NULL
    ),
    CONSTRAINT ck_dwms_bonded_handling_plan_dates CHECK (planned_end_at IS NULL OR planned_start_at IS NULL OR planned_end_at >= planned_start_at),
    CONSTRAINT ck_dwms_bonded_handling_actual_dates CHECK (actual_end_at IS NULL OR actual_start_at IS NULL OR actual_end_at >= actual_start_at)
);

CREATE TABLE IF NOT EXISTS dwms.bonded_handling_inputs (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    owner_partner_id uuid NOT NULL REFERENCES dwms.business_partners(id),
    bonded_handling_operation_id uuid NOT NULL REFERENCES dwms.bonded_handling_operations(id) ON DELETE RESTRICT,
    line_no integer NOT NULL,
    bonded_cargo_item_id uuid NOT NULL REFERENCES dwms.bonded_cargo_items(id),
    inventory_lot_id uuid REFERENCES dwms.inventory_lots(id),
    input_quantity numeric(24,8) NOT NULL,
    base_uom_code varchar(20) NOT NULL REFERENCES dwms.units_of_measure(uom_code),
    bonded_inventory_movement_id uuid REFERENCES dwms.bonded_inventory_movements(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (bonded_handling_operation_id, line_no),
    CONSTRAINT ck_dwms_bonded_handling_input_no CHECK (line_no > 0),
    CONSTRAINT ck_dwms_bonded_handling_input_qty CHECK (input_quantity > 0)
);

CREATE TABLE IF NOT EXISTS dwms.bonded_handling_outputs (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    owner_partner_id uuid NOT NULL REFERENCES dwms.business_partners(id),
    bonded_handling_operation_id uuid NOT NULL REFERENCES dwms.bonded_handling_operations(id) ON DELETE RESTRICT,
    line_no integer NOT NULL,
    bonded_cargo_item_id uuid NOT NULL REFERENCES dwms.bonded_cargo_items(id),
    output_type varchar(30) NOT NULL DEFAULT 'PRODUCT',
    inventory_lot_id uuid REFERENCES dwms.inventory_lots(id),
    output_quantity numeric(24,8) NOT NULL,
    base_uom_code varchar(20) NOT NULL REFERENCES dwms.units_of_measure(uom_code),
    bonded_inventory_movement_id uuid REFERENCES dwms.bonded_inventory_movements(id),
    loss_reason_code varchar(100),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (bonded_handling_operation_id, line_no),
    CONSTRAINT ck_dwms_bonded_handling_output_no CHECK (line_no > 0),
    CONSTRAINT ck_dwms_bonded_handling_output_type CHECK (output_type IN ('PRODUCT','BYPRODUCT','WASTE','LOSS','SAMPLE')),
    CONSTRAINT ck_dwms_bonded_handling_output_qty CHECK (output_quantity > 0)
);

CREATE TABLE IF NOT EXISTS dwms.bonded_sample_movements (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    owner_partner_id uuid NOT NULL REFERENCES dwms.business_partners(id),
    bonded_cargo_id uuid NOT NULL REFERENCES dwms.bonded_cargo(id),
    bonded_cargo_item_id uuid NOT NULL REFERENCES dwms.bonded_cargo_items(id),
    sample_no varchar(120) NOT NULL,
    sample_purpose_code varchar(100) NOT NULL,
    authorization_reference varchar(300),
    sampled_quantity numeric(24,8) NOT NULL,
    returned_quantity numeric(24,8) NOT NULL DEFAULT 0,
    consumed_quantity numeric(24,8) NOT NULL DEFAULT 0,
    lost_quantity numeric(24,8) NOT NULL DEFAULT 0,
    base_uom_code varchar(20) NOT NULL REFERENCES dwms.units_of_measure(uom_code),
    sampled_at timestamptz NOT NULL,
    due_return_at timestamptz,
    returned_at timestamptz,
    destination_partner_id uuid REFERENCES dwms.business_partners(id),
    destination_address_id uuid REFERENCES dwms.addresses(id),
    outbound_movement_id uuid REFERENCES dwms.bonded_inventory_movements(id),
    return_movement_id uuid REFERENCES dwms.bonded_inventory_movements(id),
    status varchar(30) NOT NULL DEFAULT 'OUTSTANDING',
    result_document_id uuid REFERENCES dwms.files(id),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, sample_no),
    FOREIGN KEY (bonded_cargo_id, bonded_cargo_item_id)
        REFERENCES dwms.bonded_cargo_items(bonded_cargo_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_dwms_bonded_sample_qty CHECK (
        sampled_quantity > 0 AND returned_quantity >= 0 AND consumed_quantity >= 0 AND lost_quantity >= 0 AND
        returned_quantity + consumed_quantity + lost_quantity <= sampled_quantity
    ),
    CONSTRAINT ck_dwms_bonded_sample_dates CHECK (
        (due_return_at IS NULL OR due_return_at >= sampled_at) AND
        (returned_at IS NULL OR returned_at >= sampled_at)
    ),
    CONSTRAINT ck_dwms_bonded_sample_status CHECK (status IN (
        'OUTSTANDING','PARTIALLY_RETURNED','RETURNED','CONSUMED','LOST','OVERDUE','CLOSED','CANCELLED'
    ))
);

CREATE TABLE IF NOT EXISTS dwms.bonded_disposal_cases (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    owner_partner_id uuid NOT NULL REFERENCES dwms.business_partners(id),
    bonded_facility_id uuid NOT NULL REFERENCES dwms.bonded_facilities(id),
    disposal_case_no varchar(120) NOT NULL,
    disposal_type varchar(40) NOT NULL,
    reason_code varchar(100),
    reason_text text NOT NULL,
    customs_authorization_reference varchar(300),
    authorization_at timestamptz,
    planned_at timestamptz,
    executed_at timestamptz,
    witness_name_masked varchar(150),
    contractor_partner_id uuid REFERENCES dwms.business_partners(id),
    method_code varchar(100),
    location_text varchar(300),
    status varchar(30) NOT NULL DEFAULT 'DRAFT',
    movement_group_id uuid REFERENCES dwms.bonded_movement_groups(id),
    inventory_transaction_id uuid REFERENCES dwms.inventory_transaction_headers(id),
    certificate_document_id uuid REFERENCES dwms.files(id),
    row_version bigint NOT NULL DEFAULT 1,
    created_by uuid REFERENCES dwms.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, disposal_case_no),
    CONSTRAINT ck_dwms_bonded_disposal_type CHECK (disposal_type IN ('DESTROY','ABANDON','SALE','RETURN','TRANSFER','OTHER')),
    CONSTRAINT ck_dwms_bonded_disposal_status CHECK (status IN (
        'DRAFT','AUTHORIZATION_PENDING','AUTHORIZED','SCHEDULED','IN_PROGRESS','COMPLETED','REJECTED','CANCELLED','REVERSED'
    )),
    CONSTRAINT ck_dwms_bonded_disposal_dates CHECK (executed_at IS NULL OR planned_at IS NULL OR executed_at >= planned_at)
);

CREATE TABLE IF NOT EXISTS dwms.bonded_disposal_lines (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    owner_partner_id uuid NOT NULL REFERENCES dwms.business_partners(id),
    bonded_disposal_case_id uuid NOT NULL REFERENCES dwms.bonded_disposal_cases(id) ON DELETE RESTRICT,
    line_no integer NOT NULL,
    bonded_cargo_id uuid NOT NULL REFERENCES dwms.bonded_cargo(id),
    bonded_cargo_item_id uuid NOT NULL REFERENCES dwms.bonded_cargo_items(id),
    approved_quantity numeric(24,8) NOT NULL,
    actual_quantity numeric(24,8),
    base_uom_code varchar(20) NOT NULL REFERENCES dwms.units_of_measure(uom_code),
    bonded_inventory_movement_id uuid REFERENCES dwms.bonded_inventory_movements(id),
    residue_quantity numeric(24,8),
    residue_disposition_code varchar(100),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (bonded_disposal_case_id, line_no),
    FOREIGN KEY (bonded_cargo_id, bonded_cargo_item_id)
        REFERENCES dwms.bonded_cargo_items(bonded_cargo_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_dwms_bonded_disposal_line_no CHECK (line_no > 0),
    CONSTRAINT ck_dwms_bonded_disposal_line_qty CHECK (
        approved_quantity > 0 AND (actual_quantity IS NULL OR actual_quantity >= 0) AND
        (residue_quantity IS NULL OR residue_quantity >= 0)
    )
);

CREATE TABLE IF NOT EXISTS dwms.bonded_inventory_counts (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    bonded_facility_id uuid NOT NULL REFERENCES dwms.bonded_facilities(id),
    count_no varchar(120) NOT NULL,
    count_type varchar(30) NOT NULL,
    calendar_year integer NOT NULL,
    calendar_quarter smallint,
    period_from date NOT NULL,
    period_to date NOT NULL,
    system_snapshot_at timestamptz NOT NULL,
    freeze_inventory boolean NOT NULL DEFAULT true,
    status varchar(30) NOT NULL DEFAULT 'PLANNED',
    counted_by uuid REFERENCES dwms.users(id),
    supervised_by uuid REFERENCES dwms.users(id),
    started_at timestamptz,
    completed_at timestamptz,
    approved_by uuid REFERENCES dwms.users(id),
    approved_at timestamptz,
    movement_group_id uuid REFERENCES dwms.bonded_movement_groups(id),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, count_no),
    CONSTRAINT ck_dwms_bonded_count_type CHECK (count_type IN ('QUARTERLY','CYCLE','ANNUAL','AD_HOC','CUSTOMS_DIRECTED')),
    CONSTRAINT ck_dwms_bonded_count_year CHECK (calendar_year BETWEEN 2000 AND 2200),
    CONSTRAINT ck_dwms_bonded_count_quarter CHECK (
        (count_type = 'QUARTERLY' AND calendar_quarter BETWEEN 1 AND 4) OR
        (count_type <> 'QUARTERLY' AND (calendar_quarter IS NULL OR calendar_quarter BETWEEN 1 AND 4))
    ),
    CONSTRAINT ck_dwms_bonded_count_period CHECK (period_to >= period_from),
    CONSTRAINT ck_dwms_bonded_count_status CHECK (status IN (
        'PLANNED','FROZEN','COUNTING','RECONCILING','APPROVAL_PENDING','APPROVED','POSTED','CANCELLED'
    )),
    CONSTRAINT ck_dwms_bonded_count_dates CHECK (completed_at IS NULL OR started_at IS NULL OR completed_at >= started_at)
);

CREATE TABLE IF NOT EXISTS dwms.bonded_inventory_count_lines (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    bonded_inventory_count_id uuid NOT NULL REFERENCES dwms.bonded_inventory_counts(id) ON DELETE RESTRICT,
    line_no integer NOT NULL,
    owner_partner_id uuid NOT NULL REFERENCES dwms.business_partners(id),
    bonded_cargo_id uuid NOT NULL REFERENCES dwms.bonded_cargo(id),
    bonded_cargo_item_id uuid NOT NULL REFERENCES dwms.bonded_cargo_items(id),
    warehouse_location_id uuid NOT NULL REFERENCES dwms.warehouse_locations(id),
    legal_status varchar(40) NOT NULL,
    inventory_status_id uuid NOT NULL REFERENCES dwms.inventory_statuses(id),
    expected_quantity numeric(24,8) NOT NULL,
    first_count_quantity numeric(24,8),
    recount_quantity numeric(24,8),
    final_count_quantity numeric(24,8),
    variance_quantity numeric(24,8),
    base_uom_code varchar(20) NOT NULL REFERENCES dwms.units_of_measure(uom_code),
    discrepancy_id uuid REFERENCES dwms.bonded_discrepancies(id),
    adjustment_movement_id uuid REFERENCES dwms.bonded_inventory_movements(id),
    count_status varchar(30) NOT NULL DEFAULT 'NOT_COUNTED',
    counted_by uuid REFERENCES dwms.users(id),
    counted_at timestamptz,
    recounted_by uuid REFERENCES dwms.users(id),
    recounted_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (bonded_inventory_count_id, line_no),
    FOREIGN KEY (bonded_cargo_id, bonded_cargo_item_id)
        REFERENCES dwms.bonded_cargo_items(bonded_cargo_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_dwms_bonded_count_line_no CHECK (line_no > 0),
    CONSTRAINT ck_dwms_bonded_count_line_qty CHECK (
        expected_quantity >= 0 AND (first_count_quantity IS NULL OR first_count_quantity >= 0) AND
        (recount_quantity IS NULL OR recount_quantity >= 0) AND
        (final_count_quantity IS NULL OR final_count_quantity >= 0)
    ),
    CONSTRAINT ck_dwms_bonded_count_line_status CHECK (count_status IN (
        'NOT_COUNTED','COUNTED','RECOUNT_REQUIRED','RECOUNTED','MATCHED','VARIANCE','APPROVED','POSTED'
    )),
    CONSTRAINT ck_dwms_bonded_count_line_dates CHECK (recounted_at IS NULL OR counted_at IS NULL OR recounted_at >= counted_at)
);

CREATE TABLE IF NOT EXISTS dwms.bonded_facility_incidents (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    bonded_facility_id uuid NOT NULL REFERENCES dwms.bonded_facilities(id),
    incident_no varchar(120) NOT NULL,
    incident_type varchar(50) NOT NULL,
    severity varchar(20) NOT NULL,
    occurred_at timestamptz NOT NULL,
    discovered_at timestamptz NOT NULL,
    bonded_cargo_id uuid REFERENCES dwms.bonded_cargo(id),
    warehouse_location_id uuid REFERENCES dwms.warehouse_locations(id),
    description text NOT NULL,
    immediate_action text,
    customs_notification_required boolean NOT NULL DEFAULT false,
    customs_notified_at timestamptz,
    customs_reference varchar(300),
    status varchar(30) NOT NULL DEFAULT 'OPEN',
    root_cause text,
    corrective_action text,
    closed_at timestamptz,
    closed_by uuid REFERENCES dwms.users(id),
    evidence_file_id uuid REFERENCES dwms.files(id),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, incident_no),
    CONSTRAINT ck_dwms_bonded_incident_type CHECK (incident_type IN (
        'LOSS','THEFT','DAMAGE','FIRE','FLOOD','SECURITY_BREACH','SEAL_BREACH','SYSTEM_OUTAGE',
        'REPORTING_DELAY','UNAUTHORIZED_RELEASE','INVENTORY_VARIANCE','OTHER'
    )),
    CONSTRAINT ck_dwms_bonded_incident_severity CHECK (severity IN ('LOW','MEDIUM','HIGH','CRITICAL')),
    CONSTRAINT ck_dwms_bonded_incident_status CHECK (status IN ('OPEN','REPORTED','INVESTIGATING','CORRECTIVE_ACTION','RESOLVED','CLOSED','CANCELLED')),
    CONSTRAINT ck_dwms_bonded_incident_dates CHECK (
        discovered_at >= occurred_at AND (customs_notified_at IS NULL OR customs_notified_at >= discovered_at) AND
        (closed_at IS NULL OR closed_at >= discovered_at)
    ),
    CONSTRAINT ck_dwms_bonded_incident_notice CHECK (
        NOT customs_notification_required OR status = 'OPEN' OR customs_notified_at IS NOT NULL
    )
);

CREATE TABLE IF NOT EXISTS dwms.bonded_compliance_reports (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    bonded_facility_id uuid NOT NULL REFERENCES dwms.bonded_facilities(id),
    report_no varchar(120) NOT NULL,
    report_type varchar(50) NOT NULL,
    reporting_period_from date NOT NULL,
    reporting_period_to date NOT NULL,
    system_snapshot_at timestamptz,
    inventory_count_id uuid REFERENCES dwms.bonded_inventory_counts(id),
    generated_at timestamptz,
    generated_by uuid REFERENCES dwms.users(id),
    report_file_id uuid REFERENCES dwms.files(id),
    submission_status varchar(30) NOT NULL DEFAULT 'DRAFT',
    submitted_at timestamptz,
    accepted_at timestamptz,
    customs_reference varchar(300),
    unipass_message_id uuid REFERENCES dwms.unipass_messages(id),
    retention_until date,
    legal_hold boolean NOT NULL DEFAULT false,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, report_no),
    CONSTRAINT ck_dwms_bonded_compliance_type CHECK (report_type IN (
        'QUARTERLY_RECONCILIATION','ANNUAL_INVENTORY','INOUT_LEDGER','TRANSPORT_LEDGER',
        'OVERDUE_CARGO','INCIDENT','CUSTOMS_DIRECTED','OTHER'
    )),
    CONSTRAINT ck_dwms_bonded_compliance_period CHECK (reporting_period_to >= reporting_period_from),
    CONSTRAINT ck_dwms_bonded_compliance_status CHECK (submission_status IN (
        'DRAFT','GENERATED','APPROVED','SUBMITTED','ACCEPTED','REJECTED','CORRECTION_REQUIRED','SUPERSEDED'
    )),
    CONSTRAINT ck_dwms_bonded_compliance_dates CHECK (
        (submitted_at IS NULL OR generated_at IS NULL OR submitted_at >= generated_at) AND
        (accepted_at IS NULL OR submitted_at IS NULL OR accepted_at >= submitted_at)
    )
);

CREATE TABLE IF NOT EXISTS dwms.bonded_compliance_findings (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    bonded_compliance_report_id uuid NOT NULL REFERENCES dwms.bonded_compliance_reports(id) ON DELETE RESTRICT,
    finding_no integer NOT NULL,
    finding_type varchar(80) NOT NULL,
    severity varchar(20) NOT NULL,
    entity_type varchar(80),
    entity_id uuid,
    description text NOT NULL,
    regulation_reference varchar(300),
    corrective_action_required boolean NOT NULL DEFAULT false,
    corrective_action_due_on date,
    corrective_action_status varchar(30) NOT NULL DEFAULT 'NOT_REQUIRED',
    resolved_at timestamptz,
    evidence_file_id uuid REFERENCES dwms.files(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (bonded_compliance_report_id, finding_no),
    CONSTRAINT ck_dwms_bonded_finding_no CHECK (finding_no > 0),
    CONSTRAINT ck_dwms_bonded_finding_severity CHECK (severity IN ('INFO','LOW','MEDIUM','HIGH','CRITICAL')),
    CONSTRAINT ck_dwms_bonded_finding_action_status CHECK (corrective_action_status IN (
        'NOT_REQUIRED','OPEN','IN_PROGRESS','COMPLETED','VERIFIED','OVERDUE','WAIVED'
    )),
    CONSTRAINT ck_dwms_bonded_finding_action CHECK (
        NOT corrective_action_required OR corrective_action_due_on IS NOT NULL
    )
);

CREATE TABLE IF NOT EXISTS dwms.bonded_inout_report_events (
    id uuid PRIMARY KEY DEFAULT dwms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES dwms.tenants(id),
    owner_partner_id uuid NOT NULL REFERENCES dwms.business_partners(id),
    bonded_inout_report_id uuid NOT NULL REFERENCES dwms.bonded_inout_reports(id) ON DELETE RESTRICT,
    bonded_inout_report_version_id uuid REFERENCES dwms.bonded_inout_report_versions(id),
    sequence_no integer NOT NULL,
    event_type varchar(80) NOT NULL,
    from_status varchar(30),
    to_status varchar(30),
    unipass_message_id uuid REFERENCES dwms.unipass_messages(id),
    customs_reference varchar(300),
    occurred_at timestamptz NOT NULL,
    customs_system_recorded_at timestamptz,
    recorded_at timestamptz NOT NULL DEFAULT now(),
    detail_masked jsonb NOT NULL DEFAULT '{}'::jsonb,
    UNIQUE (bonded_inout_report_id, sequence_no),
    CONSTRAINT ck_dwms_bonded_report_event_no CHECK (sequence_no > 0)
);

CREATE OR REPLACE FUNCTION dwms.validate_unipass_message_result()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, dwms
AS $function$
DECLARE
    source_row record;
BEGIN
    SELECT message.tenant_id AS message_tenant_id,
           message.owner_partner_id AS message_owner_partner_id,
           message.direction AS message_direction,
           message.message_type,
           message.message_purpose,
           message.external_message_id,
           message.payload_sha256,
           message.payload_summary_masked,
           message.recorded_status,
           message.received_at,
           message.customs_system_recorded_at,
           profile.tenant_id AS profile_tenant_id,
           profile.environment AS profile_environment,
           profile.status AS profile_status,
           profile.valid_from AS profile_valid_from,
           profile.valid_to AS profile_valid_to,
           profile.endpoint_uri AS profile_endpoint_uri,
           profile.service_id AS profile_service_id,
           profile.sender_id AS profile_sender_id,
           integration_system.tenant_id AS system_tenant_id,
           integration_system.system_type,
           integration_system.direction AS system_direction,
           integration_system.status AS system_status,
           message_schema.id AS schema_id,
           message_schema.jurisdiction_country_code,
           message_schema.authority_code,
           message_schema.message_type AS schema_message_type,
           message_schema.direction AS schema_direction,
           message_schema.effective_from AS schema_effective_from,
           message_schema.effective_to AS schema_effective_to,
           message_schema.is_active AS schema_is_active
      INTO source_row
      FROM dwms.unipass_messages message
      JOIN dwms.unipass_connection_profiles profile
        ON profile.id = message.connection_profile_id
      JOIN dwms.external_systems integration_system
        ON integration_system.id = profile.external_system_id
      JOIN dwms.customs_message_schemas message_schema
        ON message_schema.id = message.message_schema_id
     WHERE message.id = NEW.unipass_message_id
     FOR SHARE OF message, profile, integration_system, message_schema;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'UNI-PASS result requires a message with profile, system, and registered schema'
            USING ERRCODE = '23514';
    END IF;
    IF source_row.message_tenant_id IS DISTINCT FROM NEW.tenant_id
       OR source_row.message_owner_partner_id IS DISTINCT FROM NEW.owner_partner_id
       OR source_row.profile_tenant_id IS DISTINCT FROM NEW.tenant_id
       OR source_row.system_tenant_id IS DISTINCT FROM NEW.tenant_id
       OR NEW.subject_owner_partner_id IS DISTINCT FROM NEW.owner_partner_id THEN
        RAISE EXCEPTION 'UNI-PASS legal result tenant/owner scope mismatch'
            USING ERRCODE = '23514';
    END IF;
    IF source_row.message_direction <> 'IN'
       OR source_row.message_purpose NOT IN ('STATUS_RESPONSE','QUERY_RESPONSE')
       OR source_row.recorded_status <> 'ACCEPTED'
       OR source_row.external_message_id IS NULL
       OR source_row.received_at IS NULL
       OR source_row.customs_system_recorded_at IS NULL THEN
        RAISE EXCEPTION 'UNI-PASS legal result requires a completed inbound official result envelope'
            USING ERRCODE = '23514';
    END IF;
    IF source_row.profile_environment <> 'PRODUCTION'
       OR source_row.profile_status <> 'ACTIVE'
       OR source_row.profile_valid_from > source_row.received_at
       OR (source_row.profile_valid_to IS NOT NULL
           AND source_row.profile_valid_to < source_row.received_at)
       OR source_row.profile_endpoint_uri !~* '^https://'
       OR COALESCE(btrim(source_row.profile_service_id), '') = ''
       OR COALESCE(btrim(source_row.profile_sender_id), '') = ''
       OR source_row.system_type <> 'UNIPASS'
       OR source_row.system_direction NOT IN ('INBOUND','BIDIRECTIONAL')
       OR source_row.system_status <> 'ACTIVE' THEN
        RAISE EXCEPTION 'UNI-PASS legal result requires an active production inbound UNI-PASS profile'
            USING ERRCODE = '23514';
    END IF;
    IF source_row.schema_id IS DISTINCT FROM NEW.message_schema_id
       OR source_row.jurisdiction_country_code <> 'KR'
       OR source_row.authority_code <> 'KCS'
       OR source_row.schema_direction <> 'IN'
       OR source_row.schema_message_type <> source_row.message_type
       OR NOT source_row.schema_is_active
       OR source_row.schema_effective_from > source_row.received_at::date
       OR (source_row.schema_effective_to IS NOT NULL
           AND source_row.schema_effective_to < source_row.received_at::date) THEN
        RAISE EXCEPTION 'UNI-PASS legal result requires an active Korean Customs inbound result schema'
            USING ERRCODE = '23514';
    END IF;
    IF NEW.payload_sha256_snapshot IS DISTINCT FROM source_row.payload_sha256
       OR NEW.official_decision_at IS DISTINCT FROM source_row.customs_system_recorded_at
       OR NEW.transport_authenticated_at < source_row.received_at
       OR NEW.schema_validated_at < NEW.transport_authenticated_at
       OR NEW.parsed_at < NEW.schema_validated_at THEN
        RAISE EXCEPTION 'UNI-PASS legal result hash or authentication/validation timestamps are inconsistent'
            USING ERRCODE = '23514';
    END IF;
    IF NEW.result_purpose = 'BONDED_INOUT_ACCEPTANCE' AND (
        NEW.decision_code <> 'BONDED_REPORT_ACCEPTED'
        OR source_row.payload_summary_masked ->> 'decision_code' IS DISTINCT FROM NEW.decision_code
        OR source_row.payload_summary_masked ->> 'report_no'
            IS DISTINCT FROM NEW.legal_reference_no_normalized
        OR source_row.payload_summary_masked ->> 'report_version_no'
            IS DISTINCT FROM NEW.legal_version_no::text
        OR source_row.payload_summary_masked ->> 'owner_partner_id'
            IS DISTINCT FROM NEW.subject_owner_partner_id::text
    ) THEN
        RAISE EXCEPTION 'Parsed bonded result does not match the official decision, report, version, or owner'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION dwms.validate_unipass_message_result() FROM PUBLIC;

CREATE OR REPLACE FUNCTION dwms.validate_bonded_report_official_acceptance()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, dwms
AS $function$
DECLARE
    result_row record;
    version_sealed_at timestamptz;
BEGIN
    IF NEW.report_status = 'ACCEPTED' OR NEW.acceptance_status = 'ACCEPTED' THEN
        IF NEW.report_status <> 'ACCEPTED' OR NEW.acceptance_status <> 'ACCEPTED'
           OR NEW.current_version_id IS NULL OR NEW.current_version_no IS NULL
           OR NEW.customs_report_no_normalized IS NULL
           OR NEW.accepted_unipass_message_id IS NULL
           OR NEW.customs_system_recorded_at IS NULL OR NEW.accepted_at IS NULL THEN
            RAISE EXCEPTION 'Accepted bonded report requires one sealed version and complete official result fields'
                USING ERRCODE = '23514';
        END IF;

        SELECT version_row.sealed_at
          INTO version_sealed_at
          FROM dwms.bonded_inout_report_versions version_row
         WHERE version_row.id = NEW.current_version_id
           AND version_row.bonded_inout_report_id = NEW.id
           AND version_row.version_no = NEW.current_version_no
         FOR SHARE;
        IF NOT FOUND OR version_sealed_at IS NULL THEN
            RAISE EXCEPTION 'Accepted bonded report current version must be sealed and belong to the report'
                USING ERRCODE = '23514';
        END IF;

        SELECT result.id, result.official_decision_at
          INTO result_row
          FROM dwms.unipass_message_results result
         WHERE result.tenant_id = NEW.tenant_id
           AND result.owner_partner_id = NEW.owner_partner_id
           AND result.subject_owner_partner_id = NEW.owner_partner_id
           AND result.unipass_message_id = NEW.accepted_unipass_message_id
           AND result.result_purpose = 'BONDED_INOUT_ACCEPTANCE'
           AND result.decision_code = 'BONDED_REPORT_ACCEPTED'
           AND result.legal_reference_type = 'BONDED_INOUT_REPORT'
           AND result.legal_reference_no_normalized = NEW.customs_report_no_normalized
           AND result.legal_version_no = NEW.current_version_no
         ORDER BY result.id
         LIMIT 1
         FOR SHARE;
        IF NOT FOUND
           OR result_row.official_decision_at IS DISTINCT FROM NEW.customs_system_recorded_at
           OR result_row.official_decision_at IS DISTINCT FROM NEW.accepted_at THEN
            RAISE EXCEPTION 'Bonded report acceptance is not bound to its production KCS legal result'
                USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION dwms.validate_bonded_report_official_acceptance() FROM PUBLIC;

CREATE OR REPLACE FUNCTION dwms.protect_bonded_report_version()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    IF current_setting('dwms.immutable_maintenance', true) = 'on' THEN
        IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
        RETURN NEW;
    END IF;
    IF OLD.sealed_at IS NOT NULL THEN
        RAISE EXCEPTION 'Sealed bonded report version % is immutable', OLD.id
            USING ERRCODE = '55000';
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION dwms.validate_bonded_facility_scope()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    v_warehouse_tenant_id uuid;
    v_operator_tenant_id uuid;
BEGIN
    SELECT tenant_id INTO v_warehouse_tenant_id FROM dwms.warehouses WHERE id = NEW.warehouse_id;
    SELECT tenant_id INTO v_operator_tenant_id FROM dwms.business_partners WHERE id = NEW.operator_partner_id;
    IF v_warehouse_tenant_id IS DISTINCT FROM NEW.tenant_id
       OR v_operator_tenant_id IS DISTINCT FROM NEW.tenant_id THEN
        RAISE EXCEPTION 'Bonded facility warehouse/operator must belong to tenant %', NEW.tenant_id
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION dwms.validate_bonded_cargo_facility_scope()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    v_facility_tenant_id uuid;
    v_facility_warehouse_id uuid;
BEGIN
    SELECT tenant_id, warehouse_id
      INTO v_facility_tenant_id, v_facility_warehouse_id
      FROM dwms.bonded_facilities
     WHERE id = NEW.bonded_facility_id;
    IF v_facility_tenant_id IS DISTINCT FROM NEW.tenant_id
       OR v_facility_warehouse_id IS DISTINCT FROM NEW.warehouse_id THEN
        RAISE EXCEPTION 'Bonded cargo facility/warehouse scope does not match tenant %', NEW.tenant_id
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION dwms.validate_bonded_report_version_seal()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    v_line_count integer;
    v_quantity_total numeric(24,8);
    v_scope_mismatch_count integer;
    v_uom_mismatch_count integer;
BEGIN
    IF NEW.sealed_at IS NOT NULL AND OLD.sealed_at IS NULL THEN
        SELECT count(*), COALESCE(sum(reported_quantity), 0)
          INTO v_line_count, v_quantity_total
          FROM dwms.bonded_inout_report_lines
         WHERE bonded_inout_report_version_id = NEW.id;
        SELECT count(*)
          INTO v_scope_mismatch_count
          FROM dwms.bonded_inout_report_lines l
          JOIN dwms.bonded_cargo_items i ON i.id = l.bonded_cargo_item_id
          JOIN dwms.bonded_inout_report_versions v ON v.id = l.bonded_inout_report_version_id
          JOIN dwms.bonded_inout_reports r ON r.id = v.bonded_inout_report_id
         WHERE l.bonded_inout_report_version_id = NEW.id
           AND (i.bonded_cargo_id <> r.bonded_cargo_id
                OR l.tenant_id <> r.tenant_id OR l.owner_partner_id <> r.owner_partner_id);
        IF v_scope_mismatch_count > 0 THEN
            RAISE EXCEPTION 'Bonded report version % contains cargo items outside the report cargo/owner scope', NEW.id
                USING ERRCODE = '23514';
        END IF;
        IF NEW.declared_base_uom_code IS NOT NULL THEN
            SELECT count(*) INTO v_uom_mismatch_count
              FROM dwms.bonded_inout_report_lines
             WHERE bonded_inout_report_version_id = NEW.id
               AND base_uom_code <> NEW.declared_base_uom_code;
            IF v_uom_mismatch_count > 0 THEN
                RAISE EXCEPTION 'Bonded report version % contains mixed/non-header base UOMs', NEW.id
                    USING ERRCODE = '23514';
            END IF;
        END IF;
        IF NEW.declared_line_count IS NOT NULL AND NEW.declared_line_count <> v_line_count THEN
            RAISE EXCEPTION 'Declared line count % differs from stored line count % for bonded report version %',
                NEW.declared_line_count, v_line_count, NEW.id USING ERRCODE = '23514';
        END IF;
        IF NEW.declared_quantity IS NOT NULL AND v_line_count > 0
           AND abs(NEW.declared_quantity - v_quantity_total) > 0.00000001 THEN
            RAISE EXCEPTION 'Declared quantity % differs from line total % for bonded report version %',
                NEW.declared_quantity, v_quantity_total, NEW.id USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION dwms.protect_bonded_report_child()
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
    v_version_id := (v_row ->> 'bonded_inout_report_version_id')::uuid;
    SELECT sealed_at INTO v_sealed_at
      FROM dwms.bonded_inout_report_versions
     WHERE id = v_version_id;
    IF v_sealed_at IS NOT NULL THEN
        RAISE EXCEPTION 'Children of sealed bonded report version % are immutable', v_version_id
            USING ERRCODE = '55000';
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION dwms.prevent_bonded_cargo_relation_cycle()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    v_cycle boolean;
BEGIN
    WITH RECURSIVE descendants(cargo_id) AS (
        SELECT r.child_cargo_id
          FROM dwms.bonded_cargo_relations r
         WHERE r.parent_cargo_id = NEW.child_cargo_id
           AND (TG_OP <> 'UPDATE' OR r.id <> NEW.id)
        UNION
        SELECT r.child_cargo_id
          FROM dwms.bonded_cargo_relations r
          JOIN descendants d ON r.parent_cargo_id = d.cargo_id
         WHERE (TG_OP <> 'UPDATE' OR r.id <> NEW.id)
    )
    SELECT EXISTS (SELECT 1 FROM descendants WHERE cargo_id = NEW.parent_cargo_id)
      INTO v_cycle;
    IF v_cycle THEN
        RAISE EXCEPTION 'Bonded cargo relation would create a lineage cycle (% -> %)',
            NEW.parent_cargo_id, NEW.child_cargo_id USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION dwms.validate_bonded_exception_authorization()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    v_cargo_facility_id uuid;
    v_item_cargo_id uuid;
    v_report record;
BEGIN
    IF TG_OP = 'INSERT' AND NOT EXISTS (
        SELECT 1
          FROM dwms.users principal
          JOIN dwms.tenant_memberships membership
            ON membership.user_id = principal.id
           AND membership.tenant_id = NEW.tenant_id
         WHERE principal.id = NEW.requested_by
           AND principal.status = 'ACTIVE'
           AND membership.status = 'ACTIVE'
           AND membership.valid_from <= now()
           AND (membership.valid_to IS NULL OR membership.valid_to > now())
    ) THEN
        RAISE EXCEPTION 'Bonded exception requester must be an active member of the tenant'
            USING ERRCODE = '23514';
    END IF;

    SELECT cargo.bonded_facility_id
      INTO v_cargo_facility_id
      FROM dwms.bonded_cargo cargo
     WHERE cargo.id = NEW.bonded_cargo_id
       AND cargo.tenant_id = NEW.tenant_id
       AND cargo.owner_partner_id = NEW.owner_partner_id
     FOR SHARE;
    IF NOT FOUND OR v_cargo_facility_id IS DISTINCT FROM NEW.bonded_facility_id THEN
        RAISE EXCEPTION 'Bonded exception authorization cargo/facility scope is inconsistent'
            USING ERRCODE = '23514';
    END IF;

    IF NEW.bonded_cargo_item_id IS NOT NULL THEN
        SELECT item.bonded_cargo_id
          INTO v_item_cargo_id
          FROM dwms.bonded_cargo_items item
         WHERE item.id = NEW.bonded_cargo_item_id
           AND item.tenant_id = NEW.tenant_id
           AND item.owner_partner_id = NEW.owner_partner_id
         FOR SHARE;
        IF NOT FOUND OR v_item_cargo_id IS DISTINCT FROM NEW.bonded_cargo_id THEN
            RAISE EXCEPTION 'Bonded exception authorization item is outside its cargo scope'
                USING ERRCODE = '23514';
        END IF;
    END IF;

    IF NEW.bonded_inout_report_id IS NOT NULL THEN
        SELECT report.bonded_facility_id, report.bonded_cargo_id, report.report_type
          INTO v_report
          FROM dwms.bonded_inout_reports report
         WHERE report.id = NEW.bonded_inout_report_id
           AND report.tenant_id = NEW.tenant_id
           AND report.owner_partner_id = NEW.owner_partner_id
         FOR SHARE;
        IF NOT FOUND
           OR v_report.bonded_facility_id IS DISTINCT FROM NEW.bonded_facility_id
           OR v_report.bonded_cargo_id IS DISTINCT FROM NEW.bonded_cargo_id
           OR v_report.report_type IS DISTINCT FROM 'OUTBOUND' THEN
            RAISE EXCEPTION 'Report-scoped exception authorization requires an OUTBOUND report in the same facility/cargo scope'
                USING ERRCODE = '23514';
        END IF;
    END IF;

    IF COALESCE(btrim(NEW.authorization_no), '') = ''
       OR COALESCE(btrim(NEW.issuer_authority_code), '') = ''
       OR COALESCE(btrim(NEW.request_reason), '') = '' THEN
        RAISE EXCEPTION 'Bonded exception authorization requires authority, authorization number, and reason'
            USING ERRCODE = '23514';
    END IF;

    IF TG_OP = 'UPDATE' AND OLD.status = 'PENDING' AND NEW.status = 'APPROVED' THEN
        IF NOT EXISTS (
            SELECT 1
              FROM dwms.users requester
              JOIN dwms.tenant_memberships membership
                ON membership.user_id = requester.id
               AND membership.tenant_id = NEW.tenant_id
             WHERE requester.id = NEW.requested_by
               AND requester.status = 'ACTIVE'
               AND membership.status = 'ACTIVE'
               AND membership.valid_from <= now()
               AND (membership.valid_to IS NULL OR membership.valid_to > now())
        ) THEN
            RAISE EXCEPTION 'Bonded exception requester is no longer an active tenant member'
                USING ERRCODE = '23514';
        END IF;

        PERFORM 1
          FROM dwms.bonded_staff_assignments staff
          JOIN dwms.users approver
            ON approver.id = staff.user_id
           AND approver.status = 'ACTIVE'
          JOIN dwms.tenant_memberships membership
            ON membership.user_id = approver.id
           AND membership.tenant_id = staff.tenant_id
           AND membership.status = 'ACTIVE'
           AND membership.valid_from <= now()
           AND (membership.valid_to IS NULL OR membership.valid_to > now())
         WHERE staff.tenant_id = NEW.tenant_id
           AND staff.bonded_facility_id = NEW.bonded_facility_id
           AND staff.user_id = NEW.approved_by
           AND staff.staff_role_code IN (
               'BONDED_EXCEPTION_APPROVER','CUSTOMS_COMPLIANCE_MANAGER','BONDED_FACILITY_MANAGER'
           )
           AND staff.status = 'ACTIVE'
           AND staff.authorization_no IS NOT NULL
           AND staff.approved_by IS NOT NULL
           AND staff.approved_at IS NOT NULL
           AND staff.valid_from <= current_date
           AND (staff.valid_to IS NULL OR staff.valid_to >= current_date)
         FOR SHARE OF staff;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Bonded exception approver lacks an active facility approval assignment'
                USING ERRCODE = '42501';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION dwms.protect_bonded_exception_authorization()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    old_core jsonb;
    new_core jsonb;
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.status <> 'DRAFT' THEN
            RAISE EXCEPTION 'Bonded exception authorization must be created in DRAFT status'
                USING ERRCODE = '23514';
        END IF;
        RETURN NEW;
    END IF;

    IF TG_OP = 'DELETE' THEN
        IF OLD.status <> 'DRAFT' THEN
            RAISE EXCEPTION 'Submitted/final bonded exception authorization cannot be deleted'
                USING ERRCODE = '55000';
        END IF;
        RETURN OLD;
    END IF;

    IF NOT (
        (OLD.status = 'DRAFT' AND NEW.status IN ('DRAFT','PENDING','CANCELLED')) OR
        (OLD.status = 'PENDING' AND NEW.status IN ('PENDING','APPROVED','REJECTED','CANCELLED')) OR
        (OLD.status = 'APPROVED' AND NEW.status IN ('APPROVED','CONSUMED','REVOKED'))
    ) THEN
        RAISE EXCEPTION 'Invalid bonded exception authorization transition from % to %', OLD.status, NEW.status
            USING ERRCODE = '23514';
    END IF;

    IF OLD.status = 'PENDING' THEN
        old_core := to_jsonb(OLD)
            - 'status' - 'approved_by' - 'approved_at' - 'evidence_file_id'
            - 'rejected_by' - 'rejected_at' - 'decision_reason'
            - 'cancelled_by' - 'cancelled_at' - 'cancellation_reason'
            - 'row_version' - 'updated_at';
        new_core := to_jsonb(NEW)
            - 'status' - 'approved_by' - 'approved_at' - 'evidence_file_id'
            - 'rejected_by' - 'rejected_at' - 'decision_reason'
            - 'cancelled_by' - 'cancelled_at' - 'cancellation_reason'
            - 'row_version' - 'updated_at';
        IF old_core IS DISTINCT FROM new_core THEN
            RAISE EXCEPTION 'Pending bonded exception authorization scope, quantity, validity, and request evidence are immutable'
                USING ERRCODE = '55000';
        END IF;
    ELSIF OLD.status = 'APPROVED' THEN
        old_core := to_jsonb(OLD)
            - 'status' - 'consumed_at' - 'consumed_by_movement_id'
            - 'revoked_by' - 'revoked_at' - 'revocation_reason'
            - 'row_version' - 'updated_at';
        new_core := to_jsonb(NEW)
            - 'status' - 'consumed_at' - 'consumed_by_movement_id'
            - 'revoked_by' - 'revoked_at' - 'revocation_reason'
            - 'row_version' - 'updated_at';
        IF old_core IS DISTINCT FROM new_core THEN
            RAISE EXCEPTION 'Approved bonded exception authorization core fields are immutable'
                USING ERRCODE = '55000';
        END IF;
        IF NEW.status = 'CONSUMED' AND NOT EXISTS (
            SELECT 1
              FROM dwms.bonded_inventory_movements movement
             WHERE movement.id = NEW.consumed_by_movement_id
               AND movement.exception_authorization_id = OLD.id
               AND movement.tenant_id = OLD.tenant_id
               AND movement.owner_partner_id = OLD.owner_partner_id
        ) THEN
            RAISE EXCEPTION 'Consumed authorization must point to its immutable bonded movement usage'
                USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION dwms.force_bonded_group_policy()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    original_group record;
BEGIN
    IF NEW.group_type IN ('TRANSFER','LEGAL_STATUS_CHANGE','SPLIT','MERGE') THEN
        NEW.requires_zero_sum := true;
    END IF;

    IF NEW.group_type = 'REVERSAL' THEN
        SELECT original.tenant_id, original.owner_partner_id, original.bonded_cargo_id,
               original.requires_zero_sum, original.status
          INTO original_group
          FROM dwms.bonded_movement_groups original
         WHERE original.id = NEW.reversal_of_group_id
         FOR SHARE;
        IF NOT FOUND OR original_group.tenant_id IS DISTINCT FROM NEW.tenant_id
           OR original_group.owner_partner_id IS DISTINCT FROM NEW.owner_partner_id
           OR original_group.bonded_cargo_id IS DISTINCT FROM NEW.bonded_cargo_id
           OR original_group.status NOT IN ('POSTED','REVERSED') THEN
            RAISE EXCEPTION 'Reversal group requires a posted original group in the same tenant/owner/cargo scope'
                USING ERRCODE = '23514';
        END IF;
        NEW.requires_zero_sum := original_group.requires_zero_sum;
    END IF;

    IF TG_OP = 'UPDATE' AND EXISTS (
        SELECT 1 FROM dwms.bonded_inventory_movements movement
         WHERE movement.bonded_movement_group_id = OLD.id
    ) AND (
        NEW.tenant_id IS DISTINCT FROM OLD.tenant_id OR
        NEW.owner_partner_id IS DISTINCT FROM OLD.owner_partner_id OR
        NEW.bonded_cargo_id IS DISTINCT FROM OLD.bonded_cargo_id OR
        NEW.group_type IS DISTINCT FROM OLD.group_type OR
        NEW.requires_zero_sum IS DISTINCT FROM OLD.requires_zero_sum OR
        NEW.reversal_of_group_id IS DISTINCT FROM OLD.reversal_of_group_id
    ) THEN
        RAISE EXCEPTION 'Bonded movement group scope/type/conservation policy is immutable after its first movement'
            USING ERRCODE = '55000';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION dwms.validate_bonded_inventory_movement()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    v_original dwms.bonded_inventory_movements%ROWTYPE;
    v_entry record;
    v_group record;
    v_report record;
    v_authorization record;
    v_source record;
    v_transport record;
    v_cargo_facility_id uuid;
    v_cargo_warehouse_id uuid;
    v_allowed_facility_id uuid;
    v_allowed_warehouse_id uuid;
    v_location record;
    v_used_quantity numeric(24,8);
    v_returned_quantity numeric(24,8);
    v_has_official_report boolean := false;
    v_required_report_type varchar(30);
BEGIN
    SELECT movement_group.tenant_id, movement_group.owner_partner_id,
           movement_group.bonded_cargo_id, movement_group.group_type,
           movement_group.requires_zero_sum, movement_group.status,
           movement_group.source_document_type, movement_group.source_document_id,
           movement_group.reversal_of_group_id
      INTO v_group
      FROM dwms.bonded_movement_groups movement_group
     WHERE movement_group.id = NEW.bonded_movement_group_id
     FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Every bonded movement requires a known movement group'
            USING ERRCODE = '23503';
    END IF;
    IF v_group.tenant_id IS DISTINCT FROM NEW.tenant_id
       OR v_group.owner_partner_id IS DISTINCT FROM NEW.owner_partner_id
       OR v_group.bonded_cargo_id IS DISTINCT FROM NEW.bonded_cargo_id THEN
        RAISE EXCEPTION 'Bonded movement group scope does not match movement scope'
            USING ERRCODE = '23514';
    END IF;
    IF v_group.status NOT IN ('DRAFT','VALIDATED') THEN
        RAISE EXCEPTION 'Cannot append movement to closed bonded movement group %', NEW.bonded_movement_group_id
            USING ERRCODE = '55000';
    END IF;

    IF NOT (
        (v_group.group_type = 'INBOUND' AND NEW.movement_type = 'INBOUND') OR
        (v_group.group_type = 'OUTBOUND' AND NEW.movement_type = 'OUTBOUND') OR
        (v_group.group_type = 'TRANSFER' AND NEW.movement_type IN ('TRANSFER_IN','TRANSFER_OUT')) OR
        (v_group.group_type = 'LEGAL_STATUS_CHANGE' AND NEW.movement_type IN ('LEGAL_STATUS_IN','LEGAL_STATUS_OUT')) OR
        (v_group.group_type = 'ADJUSTMENT' AND NEW.movement_type IN ('ADJUSTMENT_IN','ADJUSTMENT_OUT')) OR
        (v_group.group_type = 'HANDLING' AND NEW.movement_type IN ('HANDLING_INPUT','HANDLING_OUTPUT')) OR
        (v_group.group_type = 'SAMPLE' AND NEW.movement_type IN ('SAMPLE_OUT','SAMPLE_RETURN')) OR
        (v_group.group_type = 'DISPOSAL' AND NEW.movement_type = 'DISPOSAL_OUT') OR
        (v_group.group_type = 'COUNT' AND NEW.movement_type IN ('COUNT_GAIN','COUNT_LOSS')) OR
        (v_group.group_type = 'SPLIT' AND NEW.movement_type IN ('SPLIT_IN','SPLIT_OUT')) OR
        (v_group.group_type = 'MERGE' AND NEW.movement_type IN ('MERGE_IN','MERGE_OUT')) OR
        (v_group.group_type = 'REVERSAL' AND NEW.movement_type = 'REVERSAL')
    ) THEN
        RAISE EXCEPTION 'Movement type % is not allowed in bonded group type %',
            NEW.movement_type, v_group.group_type USING ERRCODE = '23514';
    END IF;
    IF v_group.group_type IN ('TRANSFER','LEGAL_STATUS_CHANGE','SPLIT','MERGE')
       AND NOT v_group.requires_zero_sum THEN
        RAISE EXCEPTION 'Conservation group % must enforce zero-sum quantity', NEW.bonded_movement_group_id
            USING ERRCODE = '23514';
    END IF;

    SELECT cargo.bonded_facility_id, facility.warehouse_id
      INTO v_cargo_facility_id, v_cargo_warehouse_id
      FROM dwms.bonded_cargo cargo
      JOIN dwms.bonded_facilities facility
        ON facility.id = cargo.bonded_facility_id
       AND facility.tenant_id = cargo.tenant_id
     WHERE cargo.id = NEW.bonded_cargo_id
       AND cargo.tenant_id = NEW.tenant_id
       AND cargo.owner_partner_id = NEW.owner_partner_id
       AND facility.status = 'ACTIVE'
     FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Unknown bonded cargo % in movement scope', NEW.bonded_cargo_id
            USING ERRCODE = '23503';
    END IF;

    v_allowed_facility_id := v_cargo_facility_id;
    v_allowed_warehouse_id := v_cargo_warehouse_id;
    IF NEW.warehouse_id IS DISTINCT FROM v_cargo_warehouse_id THEN
        IF v_group.group_type <> 'TRANSFER'
           OR NEW.movement_type <> 'TRANSFER_IN'
           OR v_group.source_document_type IS DISTINCT FROM 'BONDED_TRANSPORT_ORDER'
           OR v_group.source_document_id IS NULL THEN
            RAISE EXCEPTION 'Cross-facility bonded movement requires a typed approved transport order'
                USING ERRCODE = '23514';
        END IF;
        SELECT transport.tenant_id, transport.owner_partner_id,
               transport.source_bonded_facility_id,
               transport.destination_bonded_facility_id,
               destination.warehouse_id AS destination_warehouse_id,
               transport.approval_status, transport.transport_authorization_no,
               transport.authorized_start_at, transport.authorized_arrival_due_at,
               transport.status
          INTO v_transport
          FROM dwms.bonded_transport_orders transport
          JOIN dwms.bonded_transport_cargo transport_cargo
            ON transport_cargo.bonded_transport_order_id = transport.id
           AND transport_cargo.bonded_cargo_id = NEW.bonded_cargo_id
          JOIN dwms.bonded_facilities destination
            ON destination.id = transport.destination_bonded_facility_id
           AND destination.tenant_id = transport.tenant_id
           AND destination.status = 'ACTIVE'
         WHERE transport.id = v_group.source_document_id
         FOR SHARE OF transport, transport_cargo, destination;
        IF NOT FOUND OR v_transport.tenant_id IS DISTINCT FROM NEW.tenant_id
           OR v_transport.owner_partner_id IS DISTINCT FROM NEW.owner_partner_id
           OR v_transport.source_bonded_facility_id IS DISTINCT FROM v_cargo_facility_id
           OR v_transport.destination_bonded_facility_id IS NULL
           OR v_transport.destination_warehouse_id IS DISTINCT FROM NEW.warehouse_id
           OR v_transport.approval_status IS DISTINCT FROM 'APPROVED'
           OR v_transport.transport_authorization_no IS NULL
           OR v_transport.status NOT IN ('AUTHORIZED','DISPATCHED','IN_TRANSIT','ARRIVED','RECEIVED')
           OR v_transport.authorized_start_at IS NULL
           OR NEW.occurred_at < v_transport.authorized_start_at
           OR (v_transport.authorized_arrival_due_at IS NOT NULL AND
               NEW.occurred_at > v_transport.authorized_arrival_due_at) THEN
            RAISE EXCEPTION 'Cross-facility bonded transfer order is not approved, active, or scope/time matched'
                USING ERRCODE = '23514';
        END IF;
        v_allowed_facility_id := v_transport.destination_bonded_facility_id;
        v_allowed_warehouse_id := v_transport.destination_warehouse_id;
    END IF;

    SELECT tenant_id, warehouse_id, zone_id, bonded_controlled
      INTO v_location
      FROM dwms.warehouse_locations
     WHERE id = NEW.warehouse_location_id
     FOR SHARE;
    IF NOT FOUND OR v_location.tenant_id IS DISTINCT FROM NEW.tenant_id
       OR v_location.warehouse_id IS DISTINCT FROM NEW.warehouse_id
       OR NEW.warehouse_id IS DISTINCT FROM v_allowed_warehouse_id
       OR NOT COALESCE(v_location.bonded_controlled, false) THEN
        RAISE EXCEPTION 'Bonded movement location % must be a bonded-controlled location in the same tenant/warehouse',
            NEW.warehouse_location_id USING ERRCODE = '23514';
    END IF;

    PERFORM 1
      FROM dwms.bonded_zone_controls zone_control
     WHERE zone_control.tenant_id = NEW.tenant_id
       AND zone_control.bonded_facility_id = v_allowed_facility_id
       AND zone_control.status = 'ACTIVE'
       AND zone_control.active_from <= NEW.occurred_at
       AND (zone_control.active_to IS NULL OR zone_control.active_to > NEW.occurred_at)
       AND (zone_control.warehouse_location_id = NEW.warehouse_location_id OR
            zone_control.warehouse_zone_id = v_location.zone_id)
       AND (cardinality(zone_control.allowed_legal_status_codes) = 0 OR
            NEW.legal_status = ANY(zone_control.allowed_legal_status_codes))
     LIMIT 1
     FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Bonded movement location lacks an active facility zone control for legal status %', NEW.legal_status
            USING ERRCODE = '23514';
    END IF;

    SELECT header.tenant_id AS header_tenant_id,
           header.owner_partner_id AS header_owner_partner_id,
           header.transaction_type, header.posting_status,
           entry.tenant_id AS entry_tenant_id,
           entry.inventory_transaction_id AS entry_transaction_id,
           entry.stock_bucket_id AS entry_bucket_id,
           entry.item_id AS entry_item_id,
           entry.signed_quantity, entry.base_uom_code AS entry_base_uom_code,
           bucket.tenant_id AS bucket_tenant_id,
           bucket.owner_partner_id AS bucket_owner_partner_id,
           bucket.warehouse_id AS bucket_warehouse_id,
           bucket.location_id AS bucket_location_id,
           bucket.item_id AS bucket_item_id,
           bucket.inventory_status_id AS bucket_inventory_status_id,
           bucket.inventory_lot_id AS bucket_inventory_lot_id,
           bucket.serial_number_id AS bucket_serial_number_id,
           bucket.lpn_id AS bucket_lpn_id,
           bucket.account_type AS bucket_account_type,
           bucket.customs_legal_status_code AS bucket_legal_status,
           cargo_item.item_id AS cargo_item_id,
           cargo_item.base_uom_code AS cargo_item_base_uom_code
      INTO v_entry
      FROM dwms.inventory_transaction_entries entry
      JOIN dwms.inventory_transaction_headers header
        ON header.id = entry.inventory_transaction_id
       AND header.tenant_id = entry.tenant_id
      JOIN dwms.stock_buckets bucket
        ON bucket.id = entry.stock_bucket_id
       AND bucket.tenant_id = entry.tenant_id
      JOIN dwms.bonded_cargo_items cargo_item
        ON cargo_item.id = NEW.bonded_cargo_item_id
       AND cargo_item.tenant_id = NEW.tenant_id
       AND cargo_item.owner_partner_id = NEW.owner_partner_id
       AND cargo_item.bonded_cargo_id = NEW.bonded_cargo_id
     WHERE entry.id = NEW.inventory_transaction_entry_id
     FOR UPDATE OF header, entry
     FOR SHARE OF bucket, cargo_item;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Bonded movement requires a tenant-scoped physical inventory entry and cargo item'
            USING ERRCODE = '23503';
    END IF;
    IF v_entry.header_tenant_id IS DISTINCT FROM NEW.tenant_id
       OR v_entry.header_owner_partner_id IS DISTINCT FROM NEW.owner_partner_id
       OR v_entry.transaction_type <> 'BONDED_MOVE'
       OR v_entry.posting_status NOT IN ('DRAFT','VALIDATED','POSTED')
       OR v_entry.entry_tenant_id IS DISTINCT FROM NEW.tenant_id
       OR v_entry.entry_transaction_id IS DISTINCT FROM NEW.inventory_transaction_id
       OR v_entry.entry_bucket_id IS DISTINCT FROM NEW.stock_bucket_id
       OR v_entry.entry_item_id IS DISTINCT FROM v_entry.cargo_item_id
       OR v_entry.bucket_tenant_id IS DISTINCT FROM NEW.tenant_id
       OR v_entry.bucket_owner_partner_id IS DISTINCT FROM NEW.owner_partner_id
       OR v_entry.bucket_warehouse_id IS DISTINCT FROM NEW.warehouse_id
       OR v_entry.bucket_location_id IS DISTINCT FROM NEW.warehouse_location_id
       OR v_entry.bucket_item_id IS DISTINCT FROM v_entry.cargo_item_id
       OR v_entry.bucket_inventory_status_id IS DISTINCT FROM NEW.inventory_status_id
       OR v_entry.bucket_inventory_lot_id IS DISTINCT FROM NEW.inventory_lot_id
       OR v_entry.bucket_serial_number_id IS DISTINCT FROM NEW.serial_number_id
       OR v_entry.bucket_lpn_id IS DISTINCT FROM NEW.lpn_id
       OR v_entry.bucket_account_type <> 'PHYSICAL'
       OR v_entry.bucket_legal_status IS DISTINCT FROM NEW.legal_status
       OR v_entry.entry_base_uom_code IS DISTINCT FROM NEW.base_uom_code
       OR v_entry.cargo_item_base_uom_code IS DISTINCT FROM NEW.base_uom_code
       OR v_entry.signed_quantity IS DISTINCT FROM NEW.quantity_delta THEN
        RAISE EXCEPTION 'Bonded movement and BONDED_MOVE physical entry dimensions/quantity must match exactly'
            USING ERRCODE = '23514';
    END IF;

    IF NEW.movement_type = 'INBOUND' THEN
        v_required_report_type := 'INBOUND';
    ELSIF NEW.movement_type IN ('OUTBOUND','TRANSFER_OUT','SAMPLE_OUT','DISPOSAL_OUT') THEN
        v_required_report_type := 'OUTBOUND';
    END IF;

    IF v_required_report_type IS NOT NULL AND NEW.bonded_inout_report_line_id IS NOT NULL THEN
        SELECT report.id AS report_id, report.report_type, report.report_status,
               report.acceptance_status, report.accepted_at,
               report.customs_system_recorded_at, report.current_version_id,
               report.current_version_no, report.customs_report_no_normalized,
               report.bonded_facility_id, report.bonded_cargo_id,
               version_row.id AS version_id,
               report_line.bonded_cargo_item_id, report_line.warehouse_location_id,
               report_line.legal_status_code, report_line.reported_quantity,
               report_line.base_uom_code,
               message.tenant_id AS message_tenant_id,
               message.owner_partner_id AS message_owner_partner_id,
               message.direction AS message_direction,
               message.message_type,
               message.message_purpose,
               message.recorded_status AS message_status,
               message.received_at AS message_received_at,
               message.customs_system_recorded_at AS message_customs_recorded_at,
               message.external_message_id,
               acceptance_result.id AS result_id,
               acceptance_result.official_decision_at,
               acceptance_result.legal_reference_no_normalized,
               acceptance_result.legal_version_no,
               acceptance_result.subject_owner_partner_id,
               profile.environment AS profile_environment,
               profile.status AS profile_status,
               profile.valid_from AS profile_valid_from,
               profile.valid_to AS profile_valid_to,
               integration_system.system_type,
               integration_system.direction AS system_direction,
               integration_system.status AS system_status,
               message_schema.jurisdiction_country_code,
               message_schema.authority_code,
               message_schema.direction AS schema_direction,
               message_schema.message_type AS schema_message_type,
               message_schema.effective_from AS schema_effective_from,
               message_schema.effective_to AS schema_effective_to,
               message_schema.is_active AS schema_is_active
          INTO v_report
          FROM dwms.bonded_inout_report_lines report_line
          JOIN dwms.bonded_inout_report_versions version_row
            ON version_row.id = report_line.bonded_inout_report_version_id
          JOIN dwms.bonded_inout_reports report
            ON report.id = version_row.bonded_inout_report_id
          JOIN dwms.unipass_messages message
            ON message.id = report.accepted_unipass_message_id
          JOIN dwms.unipass_message_results acceptance_result
            ON acceptance_result.unipass_message_id = message.id
           AND acceptance_result.tenant_id = report.tenant_id
           AND acceptance_result.owner_partner_id = report.owner_partner_id
           AND acceptance_result.result_purpose = 'BONDED_INOUT_ACCEPTANCE'
           AND acceptance_result.decision_code = 'BONDED_REPORT_ACCEPTED'
           AND acceptance_result.legal_reference_type = 'BONDED_INOUT_REPORT'
           AND acceptance_result.legal_reference_no_normalized = report.customs_report_no_normalized
           AND acceptance_result.legal_version_no = report.current_version_no
          JOIN dwms.unipass_connection_profiles profile
            ON profile.id = message.connection_profile_id
          JOIN dwms.external_systems integration_system
            ON integration_system.id = profile.external_system_id
          JOIN dwms.customs_message_schemas message_schema
            ON message_schema.id = message.message_schema_id
         WHERE report_line.id = NEW.bonded_inout_report_line_id
           AND report.tenant_id = NEW.tenant_id
           AND report.owner_partner_id = NEW.owner_partner_id
         FOR UPDATE OF report_line, report
         FOR SHARE OF version_row, message, acceptance_result, profile,
             integration_system, message_schema;
        v_has_official_report := FOUND
            AND v_report.report_type = v_required_report_type
            AND v_report.report_status = 'ACCEPTED'
             AND v_report.acceptance_status = 'ACCEPTED'
             AND v_report.accepted_at IS NOT NULL
             AND NEW.occurred_at >= v_report.accepted_at
            AND v_report.current_version_id = v_report.version_id
            AND v_report.bonded_facility_id = v_cargo_facility_id
            AND v_report.bonded_cargo_id = NEW.bonded_cargo_id
            AND v_report.bonded_cargo_item_id = NEW.bonded_cargo_item_id
            AND v_report.base_uom_code = NEW.base_uom_code
            AND v_report.legal_status_code = NEW.legal_status
             AND (v_report.warehouse_location_id IS NULL OR
                  v_report.warehouse_location_id = NEW.warehouse_location_id)
             AND v_report.message_tenant_id = NEW.tenant_id
             AND v_report.message_owner_partner_id = NEW.owner_partner_id
             AND v_report.message_direction = 'IN'
             AND v_report.message_purpose IN ('STATUS_RESPONSE','QUERY_RESPONSE')
             AND v_report.message_status = 'ACCEPTED'
             AND v_report.message_received_at IS NOT NULL
             AND v_report.message_customs_recorded_at IS NOT NULL
             AND v_report.external_message_id IS NOT NULL
             AND v_report.result_id IS NOT NULL
             AND v_report.subject_owner_partner_id = NEW.owner_partner_id
             AND v_report.legal_reference_no_normalized = v_report.customs_report_no_normalized
             AND v_report.legal_version_no = v_report.current_version_no
             AND v_report.official_decision_at = v_report.message_customs_recorded_at
             AND v_report.official_decision_at = v_report.customs_system_recorded_at
             AND v_report.official_decision_at = v_report.accepted_at
             AND v_report.profile_environment = 'PRODUCTION'
             AND v_report.profile_status = 'ACTIVE'
             AND v_report.profile_valid_from <= v_report.message_received_at
             AND (v_report.profile_valid_to IS NULL OR
                  v_report.profile_valid_to >= v_report.message_received_at)
             AND v_report.system_type = 'UNIPASS'
             AND v_report.system_direction IN ('INBOUND','BIDIRECTIONAL')
             AND v_report.system_status = 'ACTIVE'
             AND v_report.jurisdiction_country_code = 'KR'
             AND v_report.authority_code = 'KCS'
             AND v_report.schema_direction = 'IN'
             AND v_report.schema_message_type = v_report.message_type
             AND v_report.schema_is_active
             AND v_report.schema_effective_from <= v_report.message_received_at::date
             AND (v_report.schema_effective_to IS NULL OR
                  v_report.schema_effective_to >= v_report.message_received_at::date);

        IF v_has_official_report THEN
            SELECT COALESCE(sum(abs(movement.quantity_delta)), 0)
              INTO v_used_quantity
              FROM dwms.bonded_inventory_movements movement
             WHERE movement.bonded_inout_report_line_id = NEW.bonded_inout_report_line_id
               AND movement.movement_type <> 'REVERSAL'
               AND ((v_required_report_type = 'INBOUND' AND movement.quantity_delta > 0) OR
                    (v_required_report_type = 'OUTBOUND' AND movement.quantity_delta < 0));
            IF v_used_quantity + abs(NEW.quantity_delta) > v_report.reported_quantity THEN
                RAISE EXCEPTION 'Bonded report line % quantity % would be exceeded by movement %',
                    NEW.bonded_inout_report_line_id, v_report.reported_quantity, NEW.id
                    USING ERRCODE = '23514';
            END IF;
        END IF;
    END IF;

    IF v_required_report_type = 'INBOUND' AND NOT v_has_official_report THEN
        RAISE EXCEPTION 'Bonded inbound movement requires a current officially accepted INBOUND report line'
            USING ERRCODE = '23514';
    ELSIF v_required_report_type = 'OUTBOUND' AND NOT v_has_official_report THEN
        SELECT auth.*
          INTO v_authorization
          FROM dwms.bonded_exception_authorizations auth
         WHERE auth.id = NEW.exception_authorization_id
         FOR UPDATE;
        IF NOT FOUND OR v_authorization.tenant_id IS DISTINCT FROM NEW.tenant_id
           OR v_authorization.owner_partner_id IS DISTINCT FROM NEW.owner_partner_id
           OR v_authorization.bonded_facility_id IS DISTINCT FROM v_cargo_facility_id
           OR v_authorization.bonded_cargo_id IS DISTINCT FROM NEW.bonded_cargo_id
           OR (v_authorization.bonded_cargo_item_id IS NOT NULL AND
               v_authorization.bonded_cargo_item_id IS DISTINCT FROM NEW.bonded_cargo_item_id)
           OR v_authorization.authorized_movement_type IS DISTINCT FROM NEW.movement_type
           OR v_authorization.base_uom_code IS DISTINCT FROM NEW.base_uom_code
           OR v_authorization.authorized_quantity < abs(NEW.quantity_delta)
           OR v_authorization.status IS DISTINCT FROM 'APPROVED'
           OR v_authorization.approved_by IS NULL OR v_authorization.approved_at IS NULL
           OR v_authorization.evidence_file_id IS NULL
           OR NEW.occurred_at < v_authorization.valid_from
           OR NEW.occurred_at > v_authorization.valid_until
           OR NEW.occurred_at < v_authorization.approved_at
           OR now() < v_authorization.valid_from
           OR now() > v_authorization.valid_until
           OR NEW.recorded_by IS NULL THEN
            RAISE EXCEPTION 'Physical bonded release requires an approved, valid, unused, scope-matched formal exception authorization'
                USING ERRCODE = '23514';
        END IF;
        IF v_authorization.bonded_inout_report_id IS NOT NULL AND NOT EXISTS (
            SELECT 1
              FROM dwms.bonded_inout_report_lines report_line
              JOIN dwms.bonded_inout_report_versions version_row
                ON version_row.id = report_line.bonded_inout_report_version_id
             WHERE report_line.id = NEW.bonded_inout_report_line_id
               AND version_row.bonded_inout_report_id = v_authorization.bonded_inout_report_id
        ) THEN
            RAISE EXCEPTION 'Report-scoped exception authorization does not match the movement report line'
                USING ERRCODE = '23514';
        END IF;
        NEW.exception_authorization_reference := v_authorization.authorization_no;
    ELSIF v_has_official_report AND NEW.exception_authorization_id IS NOT NULL THEN
        RAISE EXCEPTION 'Official report evidence and exception authorization cannot both authorize one movement'
            USING ERRCODE = '23514';
    ELSIF v_required_report_type IS NULL AND NEW.exception_authorization_id IS NOT NULL THEN
        RAISE EXCEPTION 'Exception authorization is allowed only for customs-controlled physical outbound movement types'
            USING ERRCODE = '23514';
    END IF;

    IF v_group.group_type = 'ADJUSTMENT' THEN
        SELECT discrepancy.tenant_id, discrepancy.owner_partner_id, discrepancy.bonded_cargo_id,
               discrepancy.bonded_cargo_item_id, discrepancy.variance_quantity,
               discrepancy.base_uom_code, discrepancy.status
          INTO v_source
          FROM dwms.bonded_discrepancies discrepancy
         WHERE discrepancy.id = NEW.discrepancy_id
         FOR UPDATE;
        IF NOT FOUND OR v_source.tenant_id IS DISTINCT FROM NEW.tenant_id
           OR v_source.owner_partner_id IS DISTINCT FROM NEW.owner_partner_id
           OR v_source.bonded_cargo_id IS DISTINCT FROM NEW.bonded_cargo_id
           OR (v_source.bonded_cargo_item_id IS NOT NULL AND
               v_source.bonded_cargo_item_id IS DISTINCT FROM NEW.bonded_cargo_item_id)
           OR v_source.base_uom_code IS DISTINCT FROM NEW.base_uom_code
           OR v_source.status IS DISTINCT FROM 'ADJUSTMENT_APPROVED'
           OR v_source.variance_quantity IS NULL
           OR sign(v_source.variance_quantity) IS DISTINCT FROM sign(NEW.quantity_delta) THEN
            RAISE EXCEPTION 'Bonded adjustment requires a matching approved discrepancy and variance direction'
                USING ERRCODE = '23514';
        END IF;
        SELECT COALESCE(sum(abs(movement.quantity_delta)), 0)
          INTO v_used_quantity
          FROM dwms.bonded_inventory_movements movement
         WHERE movement.discrepancy_id = NEW.discrepancy_id
           AND movement.movement_type IN ('ADJUSTMENT_IN','ADJUSTMENT_OUT');
        IF v_used_quantity + abs(NEW.quantity_delta) > abs(v_source.variance_quantity) THEN
            RAISE EXCEPTION 'Bonded discrepancy adjustment exceeds its approved variance'
                USING ERRCODE = '23514';
        END IF;
    END IF;

    IF v_group.group_type = 'COUNT' THEN
        IF NEW.source_document_type IS DISTINCT FROM 'BONDED_INVENTORY_COUNT_LINE'
           OR NEW.source_document_id IS NULL THEN
            RAISE EXCEPTION 'Bonded count movement requires a typed inventory count line source'
                USING ERRCODE = '23514';
        END IF;
        SELECT count_header.tenant_id, count_header.bonded_facility_id,
               count_header.status AS header_status, count_header.movement_group_id,
               count_line.owner_partner_id, count_line.bonded_cargo_id,
               count_line.bonded_cargo_item_id, count_line.warehouse_location_id,
               count_line.legal_status, count_line.inventory_status_id,
               count_line.variance_quantity, count_line.base_uom_code,
               count_line.count_status
          INTO v_source
          FROM dwms.bonded_inventory_count_lines count_line
          JOIN dwms.bonded_inventory_counts count_header
            ON count_header.id = count_line.bonded_inventory_count_id
         WHERE count_line.id = NEW.source_document_id
         FOR UPDATE OF count_line, count_header;
        IF NOT FOUND OR v_source.tenant_id IS DISTINCT FROM NEW.tenant_id
           OR v_source.owner_partner_id IS DISTINCT FROM NEW.owner_partner_id
           OR v_source.bonded_facility_id IS DISTINCT FROM v_cargo_facility_id
           OR v_source.bonded_cargo_id IS DISTINCT FROM NEW.bonded_cargo_id
           OR v_source.bonded_cargo_item_id IS DISTINCT FROM NEW.bonded_cargo_item_id
           OR v_source.warehouse_location_id IS DISTINCT FROM NEW.warehouse_location_id
           OR v_source.legal_status IS DISTINCT FROM NEW.legal_status
           OR v_source.inventory_status_id IS DISTINCT FROM NEW.inventory_status_id
           OR v_source.base_uom_code IS DISTINCT FROM NEW.base_uom_code
           OR v_source.header_status IS DISTINCT FROM 'APPROVED'
           OR v_source.count_status IS DISTINCT FROM 'APPROVED'
           OR v_source.movement_group_id IS DISTINCT FROM NEW.bonded_movement_group_id
           OR v_source.variance_quantity IS NULL
           OR NEW.quantity_delta IS DISTINCT FROM v_source.variance_quantity
           OR EXISTS (
               SELECT 1 FROM dwms.bonded_inventory_movements movement
                WHERE movement.source_document_type = 'BONDED_INVENTORY_COUNT_LINE'
                  AND movement.source_document_id = NEW.source_document_id
           ) THEN
            RAISE EXCEPTION 'Bonded count movement must exactly post one approved count-line variance'
                USING ERRCODE = '23514';
        END IF;
    END IF;

    IF v_group.group_type = 'HANDLING' THEN
        IF NEW.movement_type = 'HANDLING_INPUT' THEN
            IF NEW.source_document_type IS DISTINCT FROM 'BONDED_HANDLING_INPUT'
               OR NEW.source_document_id IS NULL THEN
                RAISE EXCEPTION 'Handling input movement requires a typed handling input line source'
                    USING ERRCODE = '23514';
            END IF;
            SELECT operation.tenant_id, operation.owner_partner_id, operation.bonded_cargo_id,
                   operation.status, operation.movement_group_id,
                   input_line.bonded_cargo_item_id, input_line.input_quantity,
                   input_line.base_uom_code
              INTO v_source
              FROM dwms.bonded_handling_inputs input_line
              JOIN dwms.bonded_handling_operations operation
                ON operation.id = input_line.bonded_handling_operation_id
             WHERE input_line.id = NEW.source_document_id
             FOR UPDATE OF input_line, operation;
            IF NOT FOUND OR v_source.tenant_id IS DISTINCT FROM NEW.tenant_id
               OR v_source.owner_partner_id IS DISTINCT FROM NEW.owner_partner_id
               OR v_source.bonded_cargo_id IS DISTINCT FROM NEW.bonded_cargo_id
               OR v_source.bonded_cargo_item_id IS DISTINCT FROM NEW.bonded_cargo_item_id
               OR v_source.base_uom_code IS DISTINCT FROM NEW.base_uom_code
               OR v_source.status IS DISTINCT FROM 'COMPLETED'
               OR v_source.movement_group_id IS DISTINCT FROM NEW.bonded_movement_group_id
               OR abs(NEW.quantity_delta) IS DISTINCT FROM v_source.input_quantity THEN
                RAISE EXCEPTION 'Handling input movement must exactly match a completed operation input line'
                    USING ERRCODE = '23514';
            END IF;
        ELSE
            IF NEW.source_document_type IS DISTINCT FROM 'BONDED_HANDLING_OUTPUT'
               OR NEW.source_document_id IS NULL THEN
                RAISE EXCEPTION 'Handling output movement requires a typed handling output line source'
                    USING ERRCODE = '23514';
            END IF;
            SELECT operation.tenant_id, operation.owner_partner_id, operation.bonded_cargo_id,
                   operation.status, operation.movement_group_id,
                   output_line.bonded_cargo_item_id, output_line.output_quantity,
                   output_line.base_uom_code
              INTO v_source
              FROM dwms.bonded_handling_outputs output_line
              JOIN dwms.bonded_handling_operations operation
                ON operation.id = output_line.bonded_handling_operation_id
             WHERE output_line.id = NEW.source_document_id
             FOR UPDATE OF output_line, operation;
            IF NOT FOUND OR v_source.tenant_id IS DISTINCT FROM NEW.tenant_id
               OR v_source.owner_partner_id IS DISTINCT FROM NEW.owner_partner_id
               OR v_source.bonded_cargo_id IS DISTINCT FROM NEW.bonded_cargo_id
               OR v_source.bonded_cargo_item_id IS DISTINCT FROM NEW.bonded_cargo_item_id
               OR v_source.base_uom_code IS DISTINCT FROM NEW.base_uom_code
               OR v_source.status IS DISTINCT FROM 'COMPLETED'
               OR v_source.movement_group_id IS DISTINCT FROM NEW.bonded_movement_group_id
               OR NEW.quantity_delta IS DISTINCT FROM v_source.output_quantity THEN
                RAISE EXCEPTION 'Handling output movement must exactly match a completed operation output line'
                    USING ERRCODE = '23514';
            END IF;
        END IF;
        IF EXISTS (
            SELECT 1 FROM dwms.bonded_inventory_movements movement
             WHERE movement.source_document_type = NEW.source_document_type
               AND movement.source_document_id = NEW.source_document_id
        ) THEN
            RAISE EXCEPTION 'Bonded handling source line has already been posted'
                USING ERRCODE = '23514';
        END IF;
    END IF;

    IF v_group.group_type = 'SAMPLE' THEN
        IF NEW.source_document_type IS DISTINCT FROM 'BONDED_SAMPLE'
           OR NEW.source_document_id IS NULL THEN
            RAISE EXCEPTION 'Bonded sample movement requires a typed sample source'
                USING ERRCODE = '23514';
        END IF;
        SELECT sample.tenant_id, sample.owner_partner_id, sample.bonded_cargo_id,
               sample.bonded_cargo_item_id, sample.sampled_quantity,
               sample.base_uom_code, sample.status
          INTO v_source
          FROM dwms.bonded_sample_movements sample
         WHERE sample.id = NEW.source_document_id
         FOR UPDATE;
        IF NOT FOUND OR v_source.tenant_id IS DISTINCT FROM NEW.tenant_id
           OR v_source.owner_partner_id IS DISTINCT FROM NEW.owner_partner_id
           OR v_source.bonded_cargo_id IS DISTINCT FROM NEW.bonded_cargo_id
           OR v_source.bonded_cargo_item_id IS DISTINCT FROM NEW.bonded_cargo_item_id
           OR v_source.base_uom_code IS DISTINCT FROM NEW.base_uom_code
           OR v_source.status IN ('CANCELLED','LOST','CLOSED') THEN
            RAISE EXCEPTION 'Bonded sample movement source is unavailable or outside movement scope'
                USING ERRCODE = '23514';
        END IF;
        IF NEW.movement_type = 'SAMPLE_OUT' THEN
            SELECT COALESCE(sum(abs(movement.quantity_delta)), 0)
              INTO v_used_quantity
              FROM dwms.bonded_inventory_movements movement
             WHERE movement.source_document_type = 'BONDED_SAMPLE'
               AND movement.source_document_id = NEW.source_document_id
               AND movement.movement_type = 'SAMPLE_OUT';
            IF v_used_quantity + abs(NEW.quantity_delta) > v_source.sampled_quantity THEN
                RAISE EXCEPTION 'Bonded sample outbound movement exceeds authorized sample quantity'
                    USING ERRCODE = '23514';
            END IF;
        ELSE
            SELECT COALESCE(sum(abs(movement.quantity_delta)), 0)
              INTO v_used_quantity
              FROM dwms.bonded_inventory_movements movement
             WHERE movement.source_document_type = 'BONDED_SAMPLE'
               AND movement.source_document_id = NEW.source_document_id
               AND movement.movement_type = 'SAMPLE_OUT';
            SELECT COALESCE(sum(movement.quantity_delta), 0)
              INTO v_returned_quantity
              FROM dwms.bonded_inventory_movements movement
             WHERE movement.source_document_type = 'BONDED_SAMPLE'
               AND movement.source_document_id = NEW.source_document_id
               AND movement.movement_type = 'SAMPLE_RETURN';
            IF v_used_quantity = 0 OR v_returned_quantity + NEW.quantity_delta > v_used_quantity THEN
                RAISE EXCEPTION 'Bonded sample return requires an unreconciled prior sample outbound quantity'
                    USING ERRCODE = '23514';
            END IF;
        END IF;
    END IF;

    IF NEW.movement_type = 'REVERSAL' THEN
        SELECT * INTO v_original
          FROM dwms.bonded_inventory_movements
         WHERE id = NEW.reversal_of_movement_id
         FOR SHARE;
        IF NOT FOUND OR NEW.quantity_delta <> -v_original.quantity_delta
           OR NEW.tenant_id <> v_original.tenant_id
           OR NEW.owner_partner_id <> v_original.owner_partner_id
           OR NEW.bonded_cargo_id <> v_original.bonded_cargo_id
           OR NEW.bonded_cargo_item_id <> v_original.bonded_cargo_item_id
           OR NEW.warehouse_id <> v_original.warehouse_id
           OR NEW.warehouse_location_id <> v_original.warehouse_location_id
           OR NEW.legal_status <> v_original.legal_status
           OR NEW.inventory_status_id <> v_original.inventory_status_id
           OR NEW.base_uom_code <> v_original.base_uom_code
           OR NEW.stock_bucket_id IS DISTINCT FROM v_original.stock_bucket_id
           OR NOT EXISTS (
               SELECT 1 FROM dwms.bonded_inventory_movements original_group_movement
                WHERE original_group_movement.id = v_original.id
                  AND original_group_movement.bonded_movement_group_id = v_group.reversal_of_group_id
           ) THEN
            RAISE EXCEPTION 'Bonded reversal must exactly negate the original movement dimensions and quantity'
                USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION dwms.consume_bonded_exception_authorization()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    affected_rows integer;
    authorization_no varchar(200);
BEGIN
    IF NEW.exception_authorization_id IS NULL THEN
        RETURN NEW;
    END IF;

    UPDATE dwms.bonded_exception_authorizations auth
       SET status = 'CONSUMED',
           consumed_at = now(),
           consumed_by_movement_id = NEW.id
     WHERE auth.id = NEW.exception_authorization_id
       AND auth.tenant_id = NEW.tenant_id
       AND auth.owner_partner_id = NEW.owner_partner_id
       AND auth.status = 'APPROVED'
       AND auth.consumed_by_movement_id IS NULL
     RETURNING auth.authorization_no INTO authorization_no;
    GET DIAGNOSTICS affected_rows = ROW_COUNT;
    IF affected_rows <> 1 THEN
        RAISE EXCEPTION 'Bonded exception authorization is no longer available for consumption'
            USING ERRCODE = '23514';
    END IF;

    INSERT INTO dwms.bonded_exception_authorization_usages (
        tenant_id, owner_partner_id, bonded_exception_authorization_id,
        bonded_inventory_movement_id, used_quantity, base_uom_code,
        used_at, used_by, authorization_no_snapshot
    ) VALUES (
        NEW.tenant_id, NEW.owner_partner_id, NEW.exception_authorization_id,
        NEW.id, abs(NEW.quantity_delta), NEW.base_uom_code,
        now(), NEW.recorded_by, authorization_no
    );
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION dwms.apply_bonded_inventory_balance()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    v_rows integer;
BEGIN
    IF NEW.quantity_delta < 0 THEN
        UPDATE dwms.bonded_inventory_balances
           SET on_hand_quantity = on_hand_quantity + NEW.quantity_delta,
               last_movement_id = NEW.id,
               last_movement_at = NEW.occurred_at,
               row_version = row_version + 1,
               updated_at = now()
         WHERE tenant_id = NEW.tenant_id
           AND owner_partner_id = NEW.owner_partner_id
           AND bonded_cargo_item_id = NEW.bonded_cargo_item_id
           AND warehouse_location_id = NEW.warehouse_location_id
           AND legal_status = NEW.legal_status
           AND inventory_status_id = NEW.inventory_status_id
           AND base_uom_code = NEW.base_uom_code
           AND on_hand_quantity + NEW.quantity_delta >= 0;
        GET DIAGNOSTICS v_rows = ROW_COUNT;
        IF v_rows <> 1 THEN
            RAISE EXCEPTION 'Bonded movement would create negative or UOM-mismatched balance for cargo item %',
                NEW.bonded_cargo_item_id USING ERRCODE = '23514';
        END IF;
    ELSE
        INSERT INTO dwms.bonded_inventory_balances (
            tenant_id, owner_partner_id, bonded_cargo_id, bonded_cargo_item_id,
            warehouse_id, warehouse_location_id, legal_status, inventory_status_id,
            on_hand_quantity, base_uom_code, last_movement_id, last_movement_at
        ) VALUES (
            NEW.tenant_id, NEW.owner_partner_id, NEW.bonded_cargo_id, NEW.bonded_cargo_item_id,
            NEW.warehouse_id, NEW.warehouse_location_id, NEW.legal_status, NEW.inventory_status_id,
            NEW.quantity_delta, NEW.base_uom_code, NEW.id, NEW.occurred_at
        )
        ON CONFLICT ON CONSTRAINT uq_dwms_bonded_balance_dimensions
        DO UPDATE SET
            on_hand_quantity = dwms.bonded_inventory_balances.on_hand_quantity + EXCLUDED.on_hand_quantity,
            last_movement_id = EXCLUDED.last_movement_id,
            last_movement_at = EXCLUDED.last_movement_at,
            row_version = dwms.bonded_inventory_balances.row_version + 1,
            updated_at = now()
        WHERE dwms.bonded_inventory_balances.base_uom_code = EXCLUDED.base_uom_code;
        GET DIAGNOSTICS v_rows = ROW_COUNT;
        IF v_rows <> 1 THEN
            RAISE EXCEPTION 'Bonded balance UOM mismatch for cargo item %', NEW.bonded_cargo_item_id
                USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION dwms.validate_bonded_group_posting()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    v_movement_count integer;
    v_unbalanced_count integer;
BEGIN
    IF NEW.status = 'POSTED' THEN
        IF TG_OP = 'UPDATE' AND OLD.status = 'POSTED' THEN
            RETURN NEW;
        END IF;
        SELECT count(*) INTO v_movement_count
          FROM dwms.bonded_inventory_movements
         WHERE bonded_movement_group_id = NEW.id;
        IF v_movement_count = 0 THEN
            RAISE EXCEPTION 'Cannot post bonded movement group % without movements', NEW.id
                USING ERRCODE = '23514';
        END IF;
        IF NEW.group_type IN ('TRANSFER','LEGAL_STATUS_CHANGE','SPLIT','MERGE')
           AND NOT NEW.requires_zero_sum THEN
            RAISE EXCEPTION 'Conservation group type % cannot be posted without zero-sum enforcement', NEW.group_type
                USING ERRCODE = '23514';
        END IF;
        IF NEW.requires_zero_sum THEN
            SELECT count(*) INTO v_unbalanced_count
              FROM (
                    SELECT bonded_cargo_item_id, base_uom_code
                      FROM dwms.bonded_inventory_movements
                     WHERE bonded_movement_group_id = NEW.id
                      GROUP BY bonded_cargo_item_id, base_uom_code
                     HAVING abs(sum(quantity_delta)) > 0.00000001
                   ) q;
            IF v_unbalanced_count > 0 THEN
                RAISE EXCEPTION 'Zero-sum bonded movement group % is not balanced by cargo item/base UOM', NEW.id
                    USING ERRCODE = '23514';
            END IF;
        END IF;

        IF NEW.group_type = 'TRANSFER' AND EXISTS (
            SELECT 1
              FROM dwms.bonded_inventory_movements movement
             WHERE movement.bonded_movement_group_id = NEW.id
             GROUP BY movement.bonded_cargo_item_id, movement.base_uom_code
            HAVING count(*) FILTER (WHERE movement.quantity_delta > 0) = 0
                OR count(*) FILTER (WHERE movement.quantity_delta < 0) = 0
                OR count(DISTINCT movement.legal_status) <> 1
        ) THEN
            RAISE EXCEPTION 'Transfer group requires matched in/out movements with unchanged legal status'
                USING ERRCODE = '23514';
        END IF;

        IF NEW.group_type = 'LEGAL_STATUS_CHANGE' AND EXISTS (
            SELECT 1
              FROM dwms.bonded_inventory_movements movement
             WHERE movement.bonded_movement_group_id = NEW.id
             GROUP BY movement.bonded_cargo_item_id, movement.base_uom_code
            HAVING count(*) FILTER (WHERE movement.quantity_delta > 0) = 0
                OR count(*) FILTER (WHERE movement.quantity_delta < 0) = 0
                OR count(DISTINCT movement.legal_status) < 2
                OR count(DISTINCT movement.warehouse_id) <> 1
                OR count(DISTINCT movement.warehouse_location_id) <> 1
        ) THEN
            RAISE EXCEPTION 'Legal-status change requires matched in/out movements at one physical location with different legal statuses'
                USING ERRCODE = '23514';
        END IF;

        IF NEW.group_type = 'HANDLING' AND EXISTS (
            SELECT 1
              FROM dwms.bonded_inventory_movements movement
             WHERE movement.bonded_movement_group_id = NEW.id
             GROUP BY movement.base_uom_code
            HAVING sum(movement.quantity_delta) > 0.00000001
        ) THEN
            RAISE EXCEPTION 'Handling group output cannot exceed input quantity by base UOM without a modeled conversion authorization'
                USING ERRCODE = '23514';
        END IF;

        IF NEW.group_type = 'REVERSAL' AND EXISTS (
            SELECT 1
              FROM dwms.bonded_inventory_movements original
              LEFT JOIN dwms.bonded_inventory_movements reversal
                ON reversal.reversal_of_movement_id = original.id
               AND reversal.bonded_movement_group_id = NEW.id
             WHERE original.bonded_movement_group_id = NEW.reversal_of_group_id
               AND reversal.id IS NULL
        ) THEN
            RAISE EXCEPTION 'Reversal group must exactly reverse every movement in its original group'
                USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION dwms.protect_posted_bonded_group()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    IF current_setting('dwms.immutable_maintenance', true) = 'on' THEN
        IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
        RETURN NEW;
    END IF;
    IF OLD.status IN ('POSTED','REVERSED') THEN
        RAISE EXCEPTION 'Posted bonded movement group % is immutable', OLD.id USING ERRCODE = '55000';
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION dwms.ensure_bonded_movement_group_posted()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, dwms
AS $function$
DECLARE
    link_row record;
BEGIN
    SELECT movement.tenant_id, movement.owner_partner_id, movement.bonded_cargo_id,
           movement.bonded_cargo_item_id, movement.warehouse_id,
           movement.warehouse_location_id, movement.legal_status,
           movement.inventory_status_id, movement.inventory_lot_id,
           movement.serial_number_id, movement.lpn_id,
           movement.stock_bucket_id, movement.inventory_transaction_id,
           movement.inventory_transaction_entry_id, movement.quantity_delta,
           movement.base_uom_code,
           movement_group.status AS group_status,
           header.tenant_id AS header_tenant_id,
           header.owner_partner_id AS header_owner_partner_id,
           header.transaction_type, header.posting_status,
           entry.tenant_id AS entry_tenant_id,
           entry.inventory_transaction_id AS entry_transaction_id,
           entry.stock_bucket_id AS entry_bucket_id,
           entry.item_id AS entry_item_id,
           entry.signed_quantity, entry.base_uom_code AS entry_base_uom_code,
           bucket.tenant_id AS bucket_tenant_id,
           bucket.owner_partner_id AS bucket_owner_partner_id,
           bucket.warehouse_id AS bucket_warehouse_id,
           bucket.location_id AS bucket_location_id,
           bucket.item_id AS bucket_item_id,
           bucket.inventory_status_id AS bucket_inventory_status_id,
           bucket.inventory_lot_id AS bucket_inventory_lot_id,
           bucket.serial_number_id AS bucket_serial_number_id,
           bucket.lpn_id AS bucket_lpn_id,
           bucket.account_type AS bucket_account_type,
           bucket.customs_legal_status_code AS bucket_legal_status,
           cargo_item.item_id AS cargo_item_id,
           cargo_item.base_uom_code AS cargo_item_base_uom_code
      INTO link_row
      FROM dwms.bonded_inventory_movements movement
      JOIN dwms.bonded_movement_groups movement_group
        ON movement_group.id = movement.bonded_movement_group_id
      JOIN dwms.inventory_transaction_entries entry
        ON entry.id = movement.inventory_transaction_entry_id
      JOIN dwms.inventory_transaction_headers header
        ON header.id = movement.inventory_transaction_id
       AND header.id = entry.inventory_transaction_id
      JOIN dwms.stock_buckets bucket
        ON bucket.id = movement.stock_bucket_id
       AND bucket.id = entry.stock_bucket_id
      JOIN dwms.bonded_cargo_items cargo_item
        ON cargo_item.id = movement.bonded_cargo_item_id
     WHERE movement.id = NEW.id;

    IF NOT FOUND OR link_row.group_status <> 'POSTED'
       OR link_row.header_tenant_id IS DISTINCT FROM link_row.tenant_id
       OR link_row.header_owner_partner_id IS DISTINCT FROM link_row.owner_partner_id
       OR link_row.transaction_type <> 'BONDED_MOVE'
       OR link_row.posting_status <> 'POSTED'
       OR link_row.entry_tenant_id IS DISTINCT FROM link_row.tenant_id
       OR link_row.entry_transaction_id IS DISTINCT FROM link_row.inventory_transaction_id
       OR link_row.entry_bucket_id IS DISTINCT FROM link_row.stock_bucket_id
       OR link_row.entry_item_id IS DISTINCT FROM link_row.cargo_item_id
       OR link_row.bucket_tenant_id IS DISTINCT FROM link_row.tenant_id
       OR link_row.bucket_owner_partner_id IS DISTINCT FROM link_row.owner_partner_id
       OR link_row.bucket_warehouse_id IS DISTINCT FROM link_row.warehouse_id
       OR link_row.bucket_location_id IS DISTINCT FROM link_row.warehouse_location_id
       OR link_row.bucket_item_id IS DISTINCT FROM link_row.cargo_item_id
       OR link_row.bucket_inventory_status_id IS DISTINCT FROM link_row.inventory_status_id
       OR link_row.bucket_inventory_lot_id IS DISTINCT FROM link_row.inventory_lot_id
       OR link_row.bucket_serial_number_id IS DISTINCT FROM link_row.serial_number_id
       OR link_row.bucket_lpn_id IS DISTINCT FROM link_row.lpn_id
       OR link_row.bucket_account_type <> 'PHYSICAL'
       OR link_row.bucket_legal_status IS DISTINCT FROM link_row.legal_status
       OR link_row.entry_base_uom_code IS DISTINCT FROM link_row.base_uom_code
       OR link_row.cargo_item_base_uom_code IS DISTINCT FROM link_row.base_uom_code
       OR link_row.signed_quantity IS DISTINCT FROM link_row.quantity_delta THEN
        RAISE EXCEPTION 'Bonded movement % must commit with one exact POSTED BONDED_MOVE physical entry and POSTED legal group',
            NEW.id USING ERRCODE = '23514';
    END IF;
    RETURN NULL;
END;
$function$;

REVOKE ALL ON FUNCTION dwms.ensure_bonded_movement_group_posted() FROM PUBLIC;

CREATE OR REPLACE FUNCTION dwms.ensure_bonded_inventory_transaction_linked()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, dwms
AS $function$
DECLARE
    header_row record;
BEGIN
    SELECT tenant_id, owner_partner_id, transaction_type, posting_status
      INTO header_row
      FROM dwms.inventory_transaction_headers
     WHERE id = NEW.id;
    IF NOT FOUND OR header_row.transaction_type <> 'BONDED_MOVE'
       OR header_row.posting_status <> 'POSTED' THEN
        RETURN NULL;
    END IF;

    IF NOT EXISTS (
        SELECT 1
          FROM dwms.inventory_transaction_entries entry
          JOIN dwms.stock_buckets bucket ON bucket.id = entry.stock_bucket_id
         WHERE entry.inventory_transaction_id = NEW.id
           AND bucket.account_type = 'PHYSICAL'
    ) THEN
        RAISE EXCEPTION 'POSTED BONDED_MOVE transaction % requires at least one physical entry', NEW.id
            USING ERRCODE = '23514';
    END IF;

    IF EXISTS (
        SELECT 1
          FROM dwms.inventory_transaction_entries entry
          JOIN dwms.stock_buckets bucket ON bucket.id = entry.stock_bucket_id
          LEFT JOIN dwms.bonded_inventory_movements movement
            ON movement.inventory_transaction_entry_id = entry.id
          LEFT JOIN dwms.bonded_movement_groups movement_group
            ON movement_group.id = movement.bonded_movement_group_id
          LEFT JOIN dwms.bonded_cargo_items cargo_item
            ON cargo_item.id = movement.bonded_cargo_item_id
         WHERE entry.inventory_transaction_id = NEW.id
           AND bucket.account_type = 'PHYSICAL'
           AND (
               movement.id IS NULL
               OR movement_group.status <> 'POSTED'
               OR movement.tenant_id IS DISTINCT FROM header_row.tenant_id
               OR movement.owner_partner_id IS DISTINCT FROM header_row.owner_partner_id
               OR movement.inventory_transaction_id IS DISTINCT FROM NEW.id
               OR movement.stock_bucket_id IS DISTINCT FROM entry.stock_bucket_id
               OR movement.quantity_delta IS DISTINCT FROM entry.signed_quantity
               OR movement.base_uom_code IS DISTINCT FROM entry.base_uom_code
               OR cargo_item.item_id IS DISTINCT FROM entry.item_id
               OR bucket.tenant_id IS DISTINCT FROM movement.tenant_id
               OR bucket.owner_partner_id IS DISTINCT FROM movement.owner_partner_id
               OR bucket.warehouse_id IS DISTINCT FROM movement.warehouse_id
               OR bucket.location_id IS DISTINCT FROM movement.warehouse_location_id
               OR bucket.item_id IS DISTINCT FROM cargo_item.item_id
               OR bucket.inventory_status_id IS DISTINCT FROM movement.inventory_status_id
               OR bucket.inventory_lot_id IS DISTINCT FROM movement.inventory_lot_id
               OR bucket.serial_number_id IS DISTINCT FROM movement.serial_number_id
               OR bucket.lpn_id IS DISTINCT FROM movement.lpn_id
               OR bucket.customs_legal_status_code IS DISTINCT FROM movement.legal_status
           )
    ) THEN
        RAISE EXCEPTION 'Every physical entry of POSTED BONDED_MOVE transaction % requires one exact POSTED bonded movement',
            NEW.id USING ERRCODE = '23514';
    END IF;
    RETURN NULL;
END;
$function$;

REVOKE ALL ON FUNCTION dwms.ensure_bonded_inventory_transaction_linked() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_validate_bonded_facility_scope ON dwms.bonded_facilities;
CREATE TRIGGER trg_validate_bonded_facility_scope
    BEFORE INSERT OR UPDATE ON dwms.bonded_facilities
    FOR EACH ROW EXECUTE PROCEDURE dwms.validate_bonded_facility_scope();

DROP TRIGGER IF EXISTS trg_validate_bonded_cargo_facility_scope ON dwms.bonded_cargo;
CREATE TRIGGER trg_validate_bonded_cargo_facility_scope
    BEFORE INSERT OR UPDATE ON dwms.bonded_cargo
    FOR EACH ROW EXECUTE PROCEDURE dwms.validate_bonded_cargo_facility_scope();

DO $block$
DECLARE
    v_table text;
BEGIN
    FOREACH v_table IN ARRAY ARRAY[
        'bonded_cargo','bonded_cargo_status_events','bonded_cargo_items','bonded_cargo_relations',
        'bonded_cargo_containers','bonded_inout_reports','bonded_inout_report_versions',
        'bonded_inout_report_lines','unipass_message_results','bonded_discrepancies','bonded_movement_groups',
        'bonded_exception_authorizations','bonded_exception_authorization_usages',
        'bonded_inventory_movements','bonded_inventory_balances','bonded_transport_orders',
        'bonded_transport_cargo','bonded_seals','bonded_storage_periods',
        'bonded_storage_extension_requests','bonded_release_notices','bonded_overdue_cases',
        'bonded_handling_operations','bonded_handling_inputs','bonded_handling_outputs',
        'bonded_sample_movements','bonded_disposal_cases','bonded_disposal_lines',
        'bonded_inventory_count_lines','bonded_inout_report_events'
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

DROP TRIGGER IF EXISTS trg_10_validate_bonded_report_seal ON dwms.bonded_inout_report_versions;
CREATE TRIGGER trg_10_validate_bonded_report_seal
    BEFORE UPDATE OF sealed_at ON dwms.bonded_inout_report_versions
    FOR EACH ROW EXECUTE PROCEDURE dwms.validate_bonded_report_version_seal();

DROP TRIGGER IF EXISTS trg_20_protect_bonded_report_version ON dwms.bonded_inout_report_versions;
CREATE TRIGGER trg_20_protect_bonded_report_version
    BEFORE UPDATE OR DELETE ON dwms.bonded_inout_report_versions
    FOR EACH ROW EXECUTE PROCEDURE dwms.protect_bonded_report_version();

DROP TRIGGER IF EXISTS trg_validate_unipass_message_result ON dwms.unipass_message_results;
CREATE TRIGGER trg_validate_unipass_message_result
    BEFORE INSERT ON dwms.unipass_message_results
    FOR EACH ROW EXECUTE PROCEDURE dwms.validate_unipass_message_result();

DROP TRIGGER IF EXISTS trg_validate_bonded_report_official_acceptance
    ON dwms.bonded_inout_reports;
CREATE TRIGGER trg_validate_bonded_report_official_acceptance
    BEFORE INSERT OR UPDATE OF report_status, acceptance_status,
        current_version_id, current_version_no, customs_report_no_normalized,
        customs_system_recorded_at, accepted_at, accepted_unipass_message_id
    ON dwms.bonded_inout_reports
    FOR EACH ROW EXECUTE PROCEDURE dwms.validate_bonded_report_official_acceptance();

DROP TRIGGER IF EXISTS trg_protect_bonded_report_line ON dwms.bonded_inout_report_lines;
CREATE TRIGGER trg_protect_bonded_report_line
    BEFORE INSERT OR UPDATE OR DELETE ON dwms.bonded_inout_report_lines
    FOR EACH ROW EXECUTE PROCEDURE dwms.protect_bonded_report_child();

DROP TRIGGER IF EXISTS trg_prevent_bonded_cargo_relation_cycle ON dwms.bonded_cargo_relations;
CREATE TRIGGER trg_prevent_bonded_cargo_relation_cycle
    BEFORE INSERT OR UPDATE ON dwms.bonded_cargo_relations
    FOR EACH ROW EXECUTE PROCEDURE dwms.prevent_bonded_cargo_relation_cycle();

DROP TRIGGER IF EXISTS trg_10_validate_bonded_exception
    ON dwms.bonded_exception_authorizations;
CREATE TRIGGER trg_10_validate_bonded_exception
    BEFORE INSERT OR UPDATE ON dwms.bonded_exception_authorizations
    FOR EACH ROW EXECUTE PROCEDURE dwms.validate_bonded_exception_authorization();

DROP TRIGGER IF EXISTS trg_20_protect_bonded_exception
    ON dwms.bonded_exception_authorizations;
CREATE TRIGGER trg_20_protect_bonded_exception
    BEFORE INSERT OR UPDATE OR DELETE ON dwms.bonded_exception_authorizations
    FOR EACH ROW EXECUTE PROCEDURE dwms.protect_bonded_exception_authorization();

DROP TRIGGER IF EXISTS trg_block_bonded_exception_truncate
    ON dwms.bonded_exception_authorizations;
CREATE TRIGGER trg_block_bonded_exception_truncate
    BEFORE TRUNCATE ON dwms.bonded_exception_authorizations
    FOR EACH STATEMENT EXECUTE PROCEDURE dwms.block_immutable_change();

DROP TRIGGER IF EXISTS trg_05_force_bonded_group_policy ON dwms.bonded_movement_groups;
CREATE TRIGGER trg_05_force_bonded_group_policy
    BEFORE INSERT OR UPDATE OF tenant_id, owner_partner_id, bonded_cargo_id,
        group_type, requires_zero_sum, reversal_of_group_id
    ON dwms.bonded_movement_groups
    FOR EACH ROW EXECUTE PROCEDURE dwms.force_bonded_group_policy();

DROP TRIGGER IF EXISTS trg_10_validate_bonded_movement ON dwms.bonded_inventory_movements;
CREATE TRIGGER trg_10_validate_bonded_movement
    BEFORE INSERT ON dwms.bonded_inventory_movements
    FOR EACH ROW EXECUTE PROCEDURE dwms.validate_bonded_inventory_movement();

DROP TRIGGER IF EXISTS trg_20_consume_bonded_exception ON dwms.bonded_inventory_movements;
CREATE TRIGGER trg_20_consume_bonded_exception
    AFTER INSERT ON dwms.bonded_inventory_movements
    FOR EACH ROW EXECUTE PROCEDURE dwms.consume_bonded_exception_authorization();

DROP TRIGGER IF EXISTS trg_90_apply_bonded_balance ON dwms.bonded_inventory_movements;
CREATE TRIGGER trg_90_apply_bonded_balance
    AFTER INSERT ON dwms.bonded_inventory_movements
    FOR EACH ROW EXECUTE PROCEDURE dwms.apply_bonded_inventory_balance();

DROP TRIGGER IF EXISTS trg_95_require_posted_bonded_group ON dwms.bonded_inventory_movements;
CREATE CONSTRAINT TRIGGER trg_95_require_posted_bonded_group
    AFTER INSERT ON dwms.bonded_inventory_movements
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE PROCEDURE dwms.ensure_bonded_movement_group_posted();

DROP TRIGGER IF EXISTS trg_95_require_bonded_inventory_links
    ON dwms.inventory_transaction_headers;
CREATE CONSTRAINT TRIGGER trg_95_require_bonded_inventory_links
    AFTER INSERT OR UPDATE ON dwms.inventory_transaction_headers
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE PROCEDURE dwms.ensure_bonded_inventory_transaction_linked();

DROP TRIGGER IF EXISTS trg_10_validate_bonded_group_posting ON dwms.bonded_movement_groups;
CREATE TRIGGER trg_10_validate_bonded_group_posting
    BEFORE INSERT OR UPDATE OF status ON dwms.bonded_movement_groups
    FOR EACH ROW EXECUTE PROCEDURE dwms.validate_bonded_group_posting();

DROP TRIGGER IF EXISTS trg_20_protect_posted_bonded_group ON dwms.bonded_movement_groups;
CREATE TRIGGER trg_20_protect_posted_bonded_group
    BEFORE UPDATE OR DELETE ON dwms.bonded_movement_groups
    FOR EACH ROW EXECUTE PROCEDURE dwms.protect_posted_bonded_group();

DO $block$
DECLARE
    v_table text;
BEGIN
    FOREACH v_table IN ARRAY ARRAY[
        'bonded_cargo_status_events','bonded_cargo_relations','bonded_inventory_movements',
        'unipass_message_results',
        'bonded_transport_events','bonded_seal_checks','bonded_overdue_events',
        'bonded_inout_report_events','bonded_exception_authorization_usages'
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

DROP TRIGGER IF EXISTS trg_block_bonded_exception_usage_truncate
    ON dwms.bonded_exception_authorization_usages;
CREATE TRIGGER trg_block_bonded_exception_usage_truncate
    BEFORE TRUNCATE ON dwms.bonded_exception_authorization_usages
    FOR EACH STATEMENT EXECUTE PROCEDURE dwms.block_immutable_change();

CREATE INDEX IF NOT EXISTS ix_dwms_bonded_cargo_owner_status
    ON dwms.bonded_cargo (tenant_id, owner_partner_id, physical_status, legal_status);
CREATE INDEX IF NOT EXISTS ix_dwms_bonded_cargo_item_lookup
    ON dwms.bonded_cargo_items (tenant_id, owner_partner_id, item_id, status);
CREATE INDEX IF NOT EXISTS ix_dwms_bonded_report_acceptance
    ON dwms.bonded_inout_reports (tenant_id, acceptance_status, submitted_at)
    WHERE acceptance_status IN ('PENDING','REJECTED','ERROR');
CREATE INDEX IF NOT EXISTS ix_dwms_bonded_exception_approval_queue
    ON dwms.bonded_exception_authorizations (tenant_id, status, requested_at, id)
    WHERE status IN ('DRAFT','PENDING');
CREATE INDEX IF NOT EXISTS ix_dwms_bonded_exception_validity
    ON dwms.bonded_exception_authorizations (
        tenant_id, owner_partner_id, bonded_cargo_id, authorized_movement_type,
        valid_from, valid_until, id
    ) WHERE status = 'APPROVED';
CREATE INDEX IF NOT EXISTS ix_dwms_bonded_movement_item_time
    ON dwms.bonded_inventory_movements (bonded_cargo_item_id, occurred_at, movement_sequence);
CREATE INDEX IF NOT EXISTS ix_dwms_bonded_movement_report_usage
    ON dwms.bonded_inventory_movements (
        bonded_inout_report_line_id, movement_type, occurred_at, id
    ) WHERE bonded_inout_report_line_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_dwms_bonded_movement_source_usage
    ON dwms.bonded_inventory_movements (
        source_document_type, source_document_id, movement_type, id
    ) WHERE source_document_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_dwms_bonded_balance_location
    ON dwms.bonded_inventory_balances (
        tenant_id, owner_partner_id, warehouse_location_id, legal_status, inventory_status_id
    );
CREATE INDEX IF NOT EXISTS ix_dwms_bonded_transport_due
    ON dwms.bonded_transport_orders (tenant_id, authorized_arrival_due_at, status)
    WHERE status IN ('AUTHORIZED','DISPATCHED','IN_TRANSIT','EXCEPTION');
CREATE INDEX IF NOT EXISTS ix_dwms_bonded_storage_period_due
    ON dwms.bonded_storage_periods (tenant_id, current_due_on, status)
    WHERE status IN ('ACTIVE','EXTENSION_PENDING','EXTENDED','DUE_SOON','OVERDUE');
CREATE INDEX IF NOT EXISTS ix_dwms_bonded_notice_due
    ON dwms.bonded_release_notices (tenant_id, notice_due_on, delivery_status)
    WHERE delivery_status IN ('PENDING','FAILED');
CREATE INDEX IF NOT EXISTS ix_dwms_bonded_overdue_open
    ON dwms.bonded_overdue_cases (tenant_id, overdue_from, status)
    WHERE status NOT IN ('RESOLVED','CANCELLED');
CREATE INDEX IF NOT EXISTS ix_dwms_bonded_count_period
    ON dwms.bonded_inventory_counts (tenant_id, bonded_facility_id, calendar_year, calendar_quarter);

CREATE INDEX IF NOT EXISTS brin_dwms_bonded_movements_occurred
    ON dwms.bonded_inventory_movements USING brin (occurred_at);
CREATE INDEX IF NOT EXISTS brin_dwms_bonded_transport_events_occurred
    ON dwms.bonded_transport_events USING brin (occurred_at);
CREATE INDEX IF NOT EXISTS brin_dwms_bonded_cargo_events_occurred
    ON dwms.bonded_cargo_status_events USING brin (occurred_at);

COMMENT ON TABLE dwms.bonded_cargo IS
    'Bonded cargo case with independent physical_status and legal_status. Stock ownership remains the explicit owner_partner_id 3PL dimension.';
COMMENT ON TABLE dwms.bonded_inventory_movements IS
    'Append-only legal inventory ledger. Every movement belongs to a typed, commit-posted group; regulated one-sided movements require locked legal evidence, and corrections use exact reversals.';
COMMENT ON TABLE dwms.bonded_exception_authorizations IS
    'Formal, scope/quantity/time-bound customs exception approval. Approval requires separation of duties and evidence; a locked movement consumes it exactly once.';
COMMENT ON TABLE dwms.bonded_exception_authorization_usages IS
    'Append-only single-use evidence linking a formal bonded exception authorization to the exact legal inventory movement that consumed it.';
COMMENT ON TABLE dwms.bonded_inventory_balances IS
    'Current projection of the append-only bonded ledger by cargo item, location, legal status, and inventory status.';
COMMENT ON TABLE dwms.bonded_inout_reports IS
    'Logical bonded inbound/outbound report. Physical movement uses the accepted current version/line and official accepted UNI-PASS envelope, or an approved formal outbound exception authorization.';
COMMENT ON TABLE dwms.bonded_storage_rules IS
    'Effective-dated regulatory/operational deadline rules. Do not hard-code storage or notice periods in application logic.';
COMMENT ON TABLE dwms.bonded_transport_events IS
    'Append-only bonded transport evidence including arrival time, receiving identity evidence, and vehicle registration snapshot; retention is policy driven.';
COMMENT ON TABLE dwms.bonded_inventory_counts IS
    'Physical-to-system reconciliation headers, including quarterly counts, with immutable movement-based variance posting.';
COMMENT ON SCHEMA dwms IS
    'DWMS database model. Customs/bonded structures are implementation design references and require validation by responsible customs/legal professionals.';
