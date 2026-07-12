-- ETMS reference data, organization, partner, location, cargo, and fleet masters.

CREATE TABLE IF NOT EXISTS etms.countries (
    country_code char(2) PRIMARY KEY,
    country_code3 char(3) NOT NULL UNIQUE,
    numeric_code char(3),
    country_name_en varchar(200) NOT NULL,
    country_name_local varchar(200),
    default_currency_code char(3),
    is_active boolean NOT NULL DEFAULT true
);

CREATE TABLE IF NOT EXISTS etms.currencies (
    currency_code char(3) PRIMARY KEY,
    currency_name varchar(150) NOT NULL,
    numeric_code char(3),
    fraction_digits smallint NOT NULL DEFAULT 2,
    rounding_increment numeric(20,8) NOT NULL DEFAULT 0.01,
    is_active boolean NOT NULL DEFAULT true,
    CONSTRAINT ck_currencies_fraction CHECK (fraction_digits BETWEEN 0 AND 8),
    CONSTRAINT ck_currencies_rounding CHECK (rounding_increment > 0)
);

CREATE TABLE IF NOT EXISTS etms.units_of_measure (
    uom_code varchar(20) PRIMARY KEY,
    uom_name varchar(100) NOT NULL,
    dimension varchar(30) NOT NULL,
    si_factor numeric(30,12) NOT NULL DEFAULT 1,
    decimal_places smallint NOT NULL DEFAULT 3,
    is_active boolean NOT NULL DEFAULT true,
    CONSTRAINT ck_uom_dimension CHECK (dimension IN ('COUNT','MASS','VOLUME','LENGTH','AREA','TIME','TEMPERATURE','ENERGY','DISTANCE')),
    CONSTRAINT ck_uom_factor CHECK (si_factor > 0)
);

CREATE TABLE IF NOT EXISTS etms.unit_conversions (
    from_uom_code varchar(20) NOT NULL REFERENCES etms.units_of_measure(uom_code),
    to_uom_code varchar(20) NOT NULL REFERENCES etms.units_of_measure(uom_code),
    multiplier numeric(30,12) NOT NULL,
    offset_value numeric(30,12) NOT NULL DEFAULT 0,
    valid_from date NOT NULL DEFAULT CURRENT_DATE,
    valid_to date,
    PRIMARY KEY (from_uom_code, to_uom_code, valid_from),
    CONSTRAINT ck_unit_conversion_factor CHECK (multiplier > 0),
    CONSTRAINT ck_unit_conversion_dates CHECK (valid_to IS NULL OR valid_to >= valid_from)
);

CREATE TABLE IF NOT EXISTS etms.transport_modes (
    mode_code varchar(20) PRIMARY KEY,
    mode_name varchar(100) NOT NULL,
    mode_group varchar(30) NOT NULL,
    is_scheduled boolean NOT NULL DEFAULT false,
    is_active boolean NOT NULL DEFAULT true
);

CREATE TABLE IF NOT EXISTS etms.service_levels (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid REFERENCES etms.tenants(id) ON DELETE CASCADE,
    service_level_code varchar(50) NOT NULL,
    service_level_name varchar(150) NOT NULL,
    mode_code varchar(20) REFERENCES etms.transport_modes(mode_code),
    target_transit_minutes integer,
    priority integer NOT NULL DEFAULT 100,
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_service_levels_transit CHECK (target_transit_minutes IS NULL OR target_transit_minutes >= 0)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_service_levels_scope
    ON etms.service_levels (
        COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid),
        service_level_code
    );

CREATE TABLE IF NOT EXISTS etms.equipment_types (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid REFERENCES etms.tenants(id) ON DELETE CASCADE,
    equipment_type_code varchar(50) NOT NULL,
    equipment_type_name varchar(150) NOT NULL,
    equipment_class varchar(30) NOT NULL,
    mode_code varchar(20) REFERENCES etms.transport_modes(mode_code),
    max_payload_kg numeric(20,6),
    max_volume_m3 numeric(20,6),
    inner_length_m numeric(12,4),
    inner_width_m numeric(12,4),
    inner_height_m numeric(12,4),
    pallet_capacity numeric(12,3),
    min_temperature_c numeric(8,3),
    max_temperature_c numeric(8,3),
    is_refrigerated boolean NOT NULL DEFAULT false,
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_equipment_type_payload CHECK (max_payload_kg IS NULL OR max_payload_kg >= 0),
    CONSTRAINT ck_equipment_type_volume CHECK (max_volume_m3 IS NULL OR max_volume_m3 >= 0),
    CONSTRAINT ck_equipment_type_temp CHECK (max_temperature_c IS NULL OR min_temperature_c IS NULL OR max_temperature_c >= min_temperature_c)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_equipment_types_scope
    ON etms.equipment_types (
        COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid),
        equipment_type_code
    );

CREATE TABLE IF NOT EXISTS etms.vehicle_types (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid REFERENCES etms.tenants(id) ON DELETE CASCADE,
    vehicle_type_code varchar(50) NOT NULL,
    vehicle_type_name varchar(150) NOT NULL,
    equipment_type_id uuid REFERENCES etms.equipment_types(id),
    axle_count smallint,
    gross_vehicle_weight_kg numeric(20,6),
    max_payload_kg numeric(20,6),
    body_type varchar(50),
    fuel_type varchar(30),
    emission_class varchar(50),
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_vehicle_type_axles CHECK (axle_count IS NULL OR axle_count > 0)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_vehicle_types_scope
    ON etms.vehicle_types (
        COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid),
        vehicle_type_code
    );

CREATE TABLE IF NOT EXISTS etms.payment_terms (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid REFERENCES etms.tenants(id) ON DELETE CASCADE,
    payment_term_code varchar(50) NOT NULL,
    payment_term_name varchar(150) NOT NULL,
    due_days integer NOT NULL DEFAULT 0,
    due_day_of_month smallint,
    cutoff_day smallint,
    settlement_frequency varchar(20) NOT NULL DEFAULT 'INVOICE',
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_payment_terms_days CHECK (due_days >= 0),
    CONSTRAINT ck_payment_terms_dom CHECK (due_day_of_month IS NULL OR due_day_of_month BETWEEN 1 AND 31),
    CONSTRAINT ck_payment_terms_cutoff CHECK (cutoff_day IS NULL OR cutoff_day BETWEEN 1 AND 31)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_payment_terms_scope
    ON etms.payment_terms (
        COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid),
        payment_term_code
    );

CREATE TABLE IF NOT EXISTS etms.charge_codes (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid REFERENCES etms.tenants(id) ON DELETE CASCADE,
    charge_code varchar(50) NOT NULL,
    charge_name varchar(150) NOT NULL,
    charge_category varchar(30) NOT NULL,
    default_basis varchar(30) NOT NULL DEFAULT 'FLAT',
    taxable boolean NOT NULL DEFAULT true,
    recoverable boolean NOT NULL DEFAULT true,
    gl_account_code varchar(50),
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_charge_codes_category CHECK (charge_category IN ('FREIGHT','FUEL','ACCESSORIAL','TOLL','CUSTOMS','INSURANCE','TAX','DISCOUNT','PENALTY','OTHER'))
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_charge_codes_scope
    ON etms.charge_codes (
        COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid),
        charge_code
    );

CREATE TABLE IF NOT EXISTS etms.tax_codes (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid REFERENCES etms.tenants(id) ON DELETE CASCADE,
    tax_code varchar(50) NOT NULL,
    tax_name varchar(150) NOT NULL,
    country_code char(2) REFERENCES etms.countries(country_code),
    tax_type varchar(30) NOT NULL,
    recoverable_percent numeric(7,4) NOT NULL DEFAULT 100,
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_tax_codes_recoverable CHECK (recoverable_percent BETWEEN 0 AND 100)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_tax_codes_scope
    ON etms.tax_codes (
        COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid),
        tax_code
    );

CREATE TABLE IF NOT EXISTS etms.tax_rates (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tax_code_id uuid NOT NULL REFERENCES etms.tax_codes(id),
    jurisdiction_code varchar(80),
    rate_percent numeric(9,6) NOT NULL,
    valid_from date NOT NULL,
    valid_to date,
    source_reference varchar(300),
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_tax_rates_rate CHECK (rate_percent >= 0 AND rate_percent <= 100),
    CONSTRAINT ck_tax_rates_dates CHECK (valid_to IS NULL OR valid_to >= valid_from)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_tax_rates_scope_date
    ON etms.tax_rates (tax_code_id, COALESCE(jurisdiction_code, ''), valid_from);

CREATE TABLE IF NOT EXISTS etms.exchange_rates (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid REFERENCES etms.tenants(id) ON DELETE CASCADE,
    rate_date date NOT NULL,
    from_currency_code char(3) NOT NULL REFERENCES etms.currencies(currency_code),
    to_currency_code char(3) NOT NULL REFERENCES etms.currencies(currency_code),
    rate_type varchar(30) NOT NULL DEFAULT 'SPOT',
    exchange_rate numeric(24,12) NOT NULL,
    source_code varchar(80) NOT NULL,
    published_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_exchange_rates_positive CHECK (exchange_rate > 0),
    CONSTRAINT ck_exchange_rates_pair CHECK (from_currency_code <> to_currency_code)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_exchange_rates_scope
    ON etms.exchange_rates (
        COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid),
        rate_date, from_currency_code, to_currency_code, rate_type, source_code
    );

-- Foundation tables are created before ISO masters to break the bootstrap cycle;
-- add their reference constraints after the ISO tables exist.
ALTER TABLE etms.countries
    DROP CONSTRAINT IF EXISTS fk_countries_default_currency;
ALTER TABLE etms.countries
    ADD CONSTRAINT fk_countries_default_currency FOREIGN KEY (default_currency_code)
    REFERENCES etms.currencies(currency_code);

ALTER TABLE etms.tenants
    DROP CONSTRAINT IF EXISTS fk_tenants_default_currency;
ALTER TABLE etms.tenants
    ADD CONSTRAINT fk_tenants_default_currency FOREIGN KEY (default_currency_code)
    REFERENCES etms.currencies(currency_code);

ALTER TABLE etms.organizations
    DROP CONSTRAINT IF EXISTS fk_organizations_country;
ALTER TABLE etms.organizations
    ADD CONSTRAINT fk_organizations_country FOREIGN KEY (country_code)
    REFERENCES etms.countries(country_code);

ALTER TABLE etms.organizations
    DROP CONSTRAINT IF EXISTS fk_organizations_base_currency;
ALTER TABLE etms.organizations
    ADD CONSTRAINT fk_organizations_base_currency FOREIGN KEY (base_currency_code)
    REFERENCES etms.currencies(currency_code);

CREATE TABLE IF NOT EXISTS etms.cost_centers (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    organization_id uuid NOT NULL REFERENCES etms.organizations(id),
    org_unit_id uuid REFERENCES etms.organization_units(id),
    cost_center_code varchar(50) NOT NULL,
    cost_center_name varchar(150) NOT NULL,
    profit_center_code varchar(50),
    valid_from date,
    valid_to date,
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, organization_id, cost_center_code),
    CONSTRAINT ck_cost_centers_dates CHECK (valid_to IS NULL OR valid_from IS NULL OR valid_to >= valid_from)
);

CREATE TABLE IF NOT EXISTS etms.business_partners (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    partner_code varchar(80) NOT NULL,
    partner_name varchar(300) NOT NULL,
    legal_name varchar(300),
    partner_type varchar(30) NOT NULL DEFAULT 'COMPANY',
    country_code char(2) REFERENCES etms.countries(country_code),
    business_registration_no varchar(50),
    corporate_registration_no varchar(50),
    duns_no varchar(20),
    scac_code varchar(10),
    iata_code varchar(20),
    default_currency_code char(3) REFERENCES etms.currencies(currency_code),
    payment_term_id uuid REFERENCES etms.payment_terms(id),
    credit_limit numeric(20,4),
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    risk_grade varchar(20),
    external_reference varchar(150),
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    UNIQUE (tenant_id, partner_code),
    CONSTRAINT ck_partners_type CHECK (partner_type IN ('COMPANY','INDIVIDUAL','GOVERNMENT','INTERNAL')),
    CONSTRAINT ck_partners_credit CHECK (credit_limit IS NULL OR credit_limit >= 0)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_partners_registration_active
    ON etms.business_partners (tenant_id, country_code, business_registration_no)
    WHERE business_registration_no IS NOT NULL AND deleted_at IS NULL;

CREATE TABLE IF NOT EXISTS etms.partner_roles (
    partner_id uuid NOT NULL REFERENCES etms.business_partners(id) ON DELETE CASCADE,
    role_code varchar(30) NOT NULL,
    valid_from date NOT NULL DEFAULT CURRENT_DATE,
    valid_to date,
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    PRIMARY KEY (partner_id, role_code, valid_from),
    CONSTRAINT ck_partner_roles_code CHECK (role_code IN ('CUSTOMER','SHIPPER','CONSIGNEE','CARRIER','SUBCONTRACTOR','BROKER','FORWARDER','CUSTOMS_BROKER','SUPPLIER','VENDOR','AGENT','TERMINAL','WAREHOUSE','BILL_TO','PAY_TO')),
    CONSTRAINT ck_partner_roles_dates CHECK (valid_to IS NULL OR valid_to >= valid_from)
);

CREATE TABLE IF NOT EXISTS etms.partner_identifiers (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    partner_id uuid NOT NULL REFERENCES etms.business_partners(id) ON DELETE CASCADE,
    identifier_type varchar(50) NOT NULL,
    identifier_value varchar(200) NOT NULL,
    issuer varchar(150),
    country_code char(2) REFERENCES etms.countries(country_code),
    valid_from date,
    valid_to date,
    is_primary boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (partner_id, identifier_type, identifier_value)
);

CREATE TABLE IF NOT EXISTS etms.partner_relationships (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    parent_partner_id uuid NOT NULL REFERENCES etms.business_partners(id),
    child_partner_id uuid NOT NULL REFERENCES etms.business_partners(id),
    relationship_type varchar(30) NOT NULL,
    valid_from date NOT NULL DEFAULT CURRENT_DATE,
    valid_to date,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (parent_partner_id, child_partner_id, relationship_type, valid_from),
    CONSTRAINT ck_partner_relationship_self CHECK (parent_partner_id <> child_partner_id),
    CONSTRAINT ck_partner_relationship_dates CHECK (valid_to IS NULL OR valid_to >= valid_from)
);

CREATE TABLE IF NOT EXISTS etms.addresses (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    country_code char(2) NOT NULL REFERENCES etms.countries(country_code),
    postal_code varchar(30),
    region varchar(150),
    city varchar(150),
    district varchar(150),
    line1 varchar(300) NOT NULL,
    line2 varchar(300),
    building_name varchar(200),
    latitude numeric(10,7),
    longitude numeric(11,7),
    geocode_precision varchar(30),
    standardized_address text,
    timezone varchar(100),
    valid_from timestamptz NOT NULL DEFAULT now(),
    valid_to timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_addresses_lat CHECK (latitude IS NULL OR latitude BETWEEN -90 AND 90),
    CONSTRAINT ck_addresses_lon CHECK (longitude IS NULL OR longitude BETWEEN -180 AND 180),
    CONSTRAINT ck_addresses_dates CHECK (valid_to IS NULL OR valid_to > valid_from)
);

CREATE TABLE IF NOT EXISTS etms.partner_addresses (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    partner_id uuid NOT NULL REFERENCES etms.business_partners(id) ON DELETE CASCADE,
    address_id uuid NOT NULL REFERENCES etms.addresses(id),
    address_type varchar(30) NOT NULL,
    is_primary boolean NOT NULL DEFAULT false,
    valid_from date NOT NULL DEFAULT CURRENT_DATE,
    valid_to date,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (partner_id, address_id, address_type, valid_from),
    CONSTRAINT ck_partner_addresses_dates CHECK (valid_to IS NULL OR valid_to >= valid_from)
);

CREATE TABLE IF NOT EXISTS etms.contacts (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    contact_name varchar(200) NOT NULL,
    department varchar(150),
    job_title varchar(100),
    email varchar(320),
    phone_encrypted text,
    phone_search_hash char(64),
    mobile_encrypted text,
    preferred_channel varchar(20),
    preferred_language varchar(20) DEFAULT 'ko',
    timezone varchar(100),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz
);

CREATE TABLE IF NOT EXISTS etms.partner_contacts (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    partner_id uuid NOT NULL REFERENCES etms.business_partners(id) ON DELETE CASCADE,
    contact_id uuid NOT NULL REFERENCES etms.contacts(id),
    contact_role varchar(50) NOT NULL,
    is_primary boolean NOT NULL DEFAULT false,
    valid_from date NOT NULL DEFAULT CURRENT_DATE,
    valid_to date,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (partner_id, contact_id, contact_role, valid_from)
);

CREATE TABLE IF NOT EXISTS etms.partner_bank_accounts (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    partner_id uuid NOT NULL REFERENCES etms.business_partners(id) ON DELETE CASCADE,
    bank_country_code char(2) REFERENCES etms.countries(country_code),
    bank_name varchar(200) NOT NULL,
    account_holder varchar(200) NOT NULL,
    account_no_encrypted text NOT NULL,
    account_no_search_hash char(64) NOT NULL,
    iban_encrypted text,
    swift_bic varchar(20),
    currency_code char(3) REFERENCES etms.currencies(currency_code),
    verification_status varchar(20) NOT NULL DEFAULT 'PENDING',
    verified_at timestamptz,
    valid_from date NOT NULL DEFAULT CURRENT_DATE,
    valid_to date,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (partner_id, account_no_search_hash)
);

CREATE TABLE IF NOT EXISTS etms.partner_tax_profiles (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    partner_id uuid NOT NULL REFERENCES etms.business_partners(id) ON DELETE CASCADE,
    country_code char(2) NOT NULL REFERENCES etms.countries(country_code),
    tax_registration_no varchar(80) NOT NULL,
    tax_classification varchar(50),
    default_tax_code_id uuid REFERENCES etms.tax_codes(id),
    e_invoice_email varchar(320),
    valid_from date NOT NULL DEFAULT CURRENT_DATE,
    valid_to date,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (partner_id, country_code, tax_registration_no)
);

CREATE TABLE IF NOT EXISTS etms.partner_certifications (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    partner_id uuid NOT NULL REFERENCES etms.business_partners(id) ON DELETE CASCADE,
    certification_type varchar(80) NOT NULL,
    certificate_no varchar(150),
    issuer varchar(200),
    issued_at date,
    expires_at date,
    verification_status varchar(20) NOT NULL DEFAULT 'PENDING',
    file_id uuid REFERENCES etms.files(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (partner_id, certification_type, certificate_no),
    CONSTRAINT ck_partner_cert_dates CHECK (expires_at IS NULL OR issued_at IS NULL OR expires_at >= issued_at)
);

CREATE TABLE IF NOT EXISTS etms.carrier_profiles (
    partner_id uuid PRIMARY KEY REFERENCES etms.business_partners(id) ON DELETE CASCADE,
    carrier_class varchar(30) NOT NULL DEFAULT 'CONTRACT',
    operating_license_no varchar(100),
    safety_rating varchar(30),
    liability_limit numeric(20,4),
    cargo_insurance_limit numeric(20,4),
    currency_code char(3) REFERENCES etms.currencies(currency_code),
    allows_subcontracting boolean NOT NULL DEFAULT false,
    tender_priority integer NOT NULL DEFAULT 100,
    on_time_score numeric(7,4),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS etms.carrier_insurance_policies (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    carrier_id uuid NOT NULL REFERENCES etms.carrier_profiles(partner_id) ON DELETE CASCADE,
    policy_type varchar(50) NOT NULL,
    policy_no varchar(150) NOT NULL,
    insurer_name varchar(200) NOT NULL,
    coverage_amount numeric(20,4) NOT NULL,
    currency_code char(3) NOT NULL REFERENCES etms.currencies(currency_code),
    valid_from date NOT NULL,
    valid_to date NOT NULL,
    file_id uuid REFERENCES etms.files(id),
    verification_status varchar(20) NOT NULL DEFAULT 'PENDING',
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (carrier_id, policy_no),
    CONSTRAINT ck_carrier_insurance_amount CHECK (coverage_amount >= 0),
    CONSTRAINT ck_carrier_insurance_dates CHECK (valid_to >= valid_from)
);

CREATE TABLE IF NOT EXISTS etms.locations (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    location_code varchar(80) NOT NULL,
    location_name varchar(300) NOT NULL,
    location_type varchar(40) NOT NULL,
    owner_partner_id uuid REFERENCES etms.business_partners(id),
    address_id uuid NOT NULL REFERENCES etms.addresses(id),
    timezone varchar(100) NOT NULL DEFAULT 'Asia/Seoul',
    unlocode varchar(10),
    airport_code varchar(10),
    port_code varchar(10),
    calendar_id uuid REFERENCES etms.business_calendars(id),
    appointment_required boolean NOT NULL DEFAULT false,
    allow_overnight boolean NOT NULL DEFAULT true,
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    capabilities jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    UNIQUE (tenant_id, location_code),
    CONSTRAINT ck_locations_type CHECK (location_type IN ('PLANT','WAREHOUSE','DC','CUSTOMER','SUPPLIER','CROSS_DOCK','PORT','AIRPORT','RAIL_TERMINAL','YARD','DEPOT','BORDER','OTHER'))
);

CREATE TABLE IF NOT EXISTS etms.location_contacts (
    location_id uuid NOT NULL REFERENCES etms.locations(id) ON DELETE CASCADE,
    contact_id uuid NOT NULL REFERENCES etms.contacts(id),
    contact_role varchar(50) NOT NULL,
    is_primary boolean NOT NULL DEFAULT false,
    PRIMARY KEY (location_id, contact_id, contact_role)
);

CREATE TABLE IF NOT EXISTS etms.location_operating_hours (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    location_id uuid NOT NULL REFERENCES etms.locations(id) ON DELETE CASCADE,
    weekday smallint NOT NULL,
    open_time time NOT NULL,
    close_time time NOT NULL,
    operation_type varchar(30) NOT NULL DEFAULT 'GENERAL',
    effective_from date NOT NULL DEFAULT CURRENT_DATE,
    effective_to date,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (location_id, weekday, operation_type, effective_from, open_time),
    CONSTRAINT ck_location_hours_weekday CHECK (weekday BETWEEN 0 AND 6),
    CONSTRAINT ck_location_hours_dates CHECK (effective_to IS NULL OR effective_to >= effective_from)
);

CREATE TABLE IF NOT EXISTS etms.location_docks (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    location_id uuid NOT NULL REFERENCES etms.locations(id) ON DELETE CASCADE,
    dock_code varchar(50) NOT NULL,
    dock_name varchar(150),
    dock_type varchar(30) NOT NULL DEFAULT 'GENERAL',
    equipment_type_id uuid REFERENCES etms.equipment_types(id),
    max_vehicle_length_m numeric(12,4),
    max_weight_kg numeric(20,6),
    supports_refrigerated boolean NOT NULL DEFAULT false,
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (location_id, dock_code)
);

CREATE TABLE IF NOT EXISTS etms.geofences (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    location_id uuid REFERENCES etms.locations(id) ON DELETE CASCADE,
    geofence_code varchar(80) NOT NULL,
    geofence_name varchar(200) NOT NULL,
    shape_type varchar(20) NOT NULL,
    center_latitude numeric(10,7),
    center_longitude numeric(11,7),
    radius_m numeric(16,3),
    polygon_geojson jsonb,
    dwell_threshold_minutes integer,
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, geofence_code),
    CONSTRAINT ck_geofences_shape CHECK (shape_type IN ('CIRCLE','POLYGON')),
    CONSTRAINT ck_geofences_geometry CHECK (
        (shape_type = 'CIRCLE' AND center_latitude IS NOT NULL AND center_longitude IS NOT NULL AND radius_m > 0) OR
        (shape_type = 'POLYGON' AND polygon_geojson IS NOT NULL)
    )
);

CREATE TABLE IF NOT EXISTS etms.location_blackouts (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    location_id uuid NOT NULL REFERENCES etms.locations(id) ON DELETE CASCADE,
    blackout_type varchar(30) NOT NULL DEFAULT 'CLOSED',
    starts_at timestamptz NOT NULL,
    ends_at timestamptz NOT NULL,
    reason text,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_location_blackouts_dates CHECK (ends_at > starts_at)
);

CREATE TABLE IF NOT EXISTS etms.commodity_classes (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid REFERENCES etms.tenants(id) ON DELETE CASCADE,
    commodity_code varchar(50) NOT NULL,
    commodity_name varchar(150) NOT NULL,
    hs_code_prefix varchar(20),
    freight_class varchar(30),
    stowage_category varchar(30),
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_commodity_classes_scope
    ON etms.commodity_classes (
        COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), commodity_code
    );

CREATE TABLE IF NOT EXISTS etms.items (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    owner_partner_id uuid REFERENCES etms.business_partners(id),
    item_code varchar(100) NOT NULL,
    item_name varchar(300) NOT NULL,
    commodity_class_id uuid REFERENCES etms.commodity_classes(id),
    hs_code varchar(20),
    country_of_origin char(2) REFERENCES etms.countries(country_code),
    base_uom_code varchar(20) NOT NULL REFERENCES etms.units_of_measure(uom_code),
    unit_weight_kg numeric(20,6),
    unit_volume_m3 numeric(20,6),
    length_m numeric(12,6),
    width_m numeric(12,6),
    height_m numeric(12,6),
    declared_value numeric(20,4),
    value_currency_code char(3) REFERENCES etms.currencies(currency_code),
    shelf_life_days integer,
    serial_controlled boolean NOT NULL DEFAULT false,
    lot_controlled boolean NOT NULL DEFAULT false,
    is_active boolean NOT NULL DEFAULT true,
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    CONSTRAINT ck_items_weight CHECK (unit_weight_kg IS NULL OR unit_weight_kg >= 0),
    CONSTRAINT ck_items_volume CHECK (unit_volume_m3 IS NULL OR unit_volume_m3 >= 0),
    CONSTRAINT ck_items_shelf_life CHECK (shelf_life_days IS NULL OR shelf_life_days >= 0)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_items_owner_code_active
    ON etms.items (
        tenant_id,
        COALESCE(owner_partner_id, '00000000-0000-0000-0000-000000000000'::uuid),
        item_code
    )
    WHERE deleted_at IS NULL;

CREATE TABLE IF NOT EXISTS etms.item_packagings (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    item_id uuid NOT NULL REFERENCES etms.items(id) ON DELETE CASCADE,
    packaging_code varchar(50) NOT NULL,
    packaging_level varchar(30) NOT NULL,
    units_per_package numeric(20,6) NOT NULL,
    package_uom_code varchar(20) NOT NULL REFERENCES etms.units_of_measure(uom_code),
    gross_weight_kg numeric(20,6),
    volume_m3 numeric(20,6),
    length_m numeric(12,6),
    width_m numeric(12,6),
    height_m numeric(12,6),
    barcode varchar(100),
    stackable boolean NOT NULL DEFAULT true,
    max_stack_layers integer,
    is_default boolean NOT NULL DEFAULT false,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (item_id, packaging_code),
    CONSTRAINT ck_item_packagings_qty CHECK (units_per_package > 0)
);

CREATE TABLE IF NOT EXISTS etms.dangerous_goods_profiles (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    item_id uuid NOT NULL REFERENCES etms.items(id) ON DELETE CASCADE,
    un_number varchar(10) NOT NULL,
    proper_shipping_name varchar(300) NOT NULL,
    hazard_class varchar(20) NOT NULL,
    subsidiary_risk varchar(50),
    packing_group varchar(10),
    tunnel_restriction_code varchar(10),
    marine_pollutant boolean NOT NULL DEFAULT false,
    limited_quantity boolean NOT NULL DEFAULT false,
    emergency_contact text,
    sds_file_id uuid REFERENCES etms.files(id),
    valid_from date NOT NULL DEFAULT CURRENT_DATE,
    valid_to date,
    UNIQUE (item_id, un_number, valid_from)
);

CREATE TABLE IF NOT EXISTS etms.transport_requirement_profiles (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    item_id uuid NOT NULL REFERENCES etms.items(id) ON DELETE CASCADE,
    min_temperature_c numeric(8,3),
    max_temperature_c numeric(8,3),
    max_humidity_percent numeric(7,3),
    shock_limit_g numeric(12,4),
    tilt_limit_degrees numeric(8,3),
    requires_food_grade boolean NOT NULL DEFAULT false,
    requires_pharma_gdp boolean NOT NULL DEFAULT false,
    requires_security_escort boolean NOT NULL DEFAULT false,
    prohibited_mode_codes varchar(20)[] NOT NULL DEFAULT ARRAY[]::varchar(20)[],
    special_instructions text,
    valid_from date NOT NULL DEFAULT CURRENT_DATE,
    valid_to date,
    CONSTRAINT ck_requirement_temp CHECK (max_temperature_c IS NULL OR min_temperature_c IS NULL OR max_temperature_c >= min_temperature_c),
    CONSTRAINT ck_requirement_humidity CHECK (max_humidity_percent IS NULL OR max_humidity_percent BETWEEN 0 AND 100)
);

CREATE TABLE IF NOT EXISTS etms.drivers (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    carrier_id uuid REFERENCES etms.business_partners(id),
    driver_code varchar(80) NOT NULL,
    driver_name varchar(200) NOT NULL,
    employee_no varchar(50),
    phone_encrypted text,
    phone_search_hash char(64),
    date_of_birth_encrypted text,
    hire_date date,
    termination_date date,
    home_location_id uuid REFERENCES etms.locations(id),
    preferred_language varchar(20) DEFAULT 'ko',
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    firebase_user_id uuid REFERENCES etms.users(id),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    CONSTRAINT ck_drivers_dates CHECK (termination_date IS NULL OR hire_date IS NULL OR termination_date >= hire_date)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_drivers_carrier_code_active
    ON etms.drivers (
        tenant_id,
        COALESCE(carrier_id, '00000000-0000-0000-0000-000000000000'::uuid),
        driver_code
    ) WHERE deleted_at IS NULL;

CREATE TABLE IF NOT EXISTS etms.driver_licenses (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    driver_id uuid NOT NULL REFERENCES etms.drivers(id) ON DELETE CASCADE,
    license_type varchar(50) NOT NULL,
    license_no_encrypted text NOT NULL,
    license_no_search_hash char(64) NOT NULL,
    issuing_country_code char(2) REFERENCES etms.countries(country_code),
    issued_at date,
    expires_at date NOT NULL,
    restrictions varchar(300),
    verification_status varchar(20) NOT NULL DEFAULT 'PENDING',
    file_id uuid REFERENCES etms.files(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (driver_id, license_type, license_no_search_hash)
);

CREATE TABLE IF NOT EXISTS etms.driver_certifications (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    driver_id uuid NOT NULL REFERENCES etms.drivers(id) ON DELETE CASCADE,
    certification_type varchar(80) NOT NULL,
    certificate_no varchar(150),
    issued_at date,
    expires_at date,
    verification_status varchar(20) NOT NULL DEFAULT 'PENDING',
    file_id uuid REFERENCES etms.files(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (driver_id, certification_type, certificate_no)
);

CREATE TABLE IF NOT EXISTS etms.driver_availability (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    driver_id uuid NOT NULL REFERENCES etms.drivers(id) ON DELETE CASCADE,
    availability_type varchar(30) NOT NULL,
    starts_at timestamptz NOT NULL,
    ends_at timestamptz NOT NULL,
    location_id uuid REFERENCES etms.locations(id),
    reason text,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_driver_availability_dates CHECK (ends_at > starts_at)
);

CREATE TABLE IF NOT EXISTS etms.vehicles (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    owner_partner_id uuid REFERENCES etms.business_partners(id),
    operating_carrier_id uuid REFERENCES etms.business_partners(id),
    vehicle_code varchar(80) NOT NULL,
    registration_no varchar(50) NOT NULL,
    vin_encrypted text,
    vin_search_hash char(64),
    vehicle_type_id uuid NOT NULL REFERENCES etms.vehicle_types(id),
    manufacture_year smallint,
    make varchar(100),
    model varchar(100),
    fuel_type varchar(30),
    fuel_capacity_l numeric(12,3),
    max_payload_kg numeric(20,6),
    max_volume_m3 numeric(20,6),
    home_location_id uuid REFERENCES etms.locations(id),
    odometer_km numeric(20,3),
    status varchar(20) NOT NULL DEFAULT 'AVAILABLE',
    in_service_date date,
    out_of_service_date date,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    UNIQUE (tenant_id, vehicle_code),
    UNIQUE (tenant_id, registration_no),
    CONSTRAINT ck_vehicles_payload CHECK (max_payload_kg IS NULL OR max_payload_kg >= 0),
    CONSTRAINT ck_vehicles_volume CHECK (max_volume_m3 IS NULL OR max_volume_m3 >= 0)
);

CREATE TABLE IF NOT EXISTS etms.trailers (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    owner_partner_id uuid REFERENCES etms.business_partners(id),
    trailer_code varchar(80) NOT NULL,
    registration_no varchar(50),
    equipment_type_id uuid NOT NULL REFERENCES etms.equipment_types(id),
    max_payload_kg numeric(20,6),
    max_volume_m3 numeric(20,6),
    home_location_id uuid REFERENCES etms.locations(id),
    status varchar(20) NOT NULL DEFAULT 'AVAILABLE',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    UNIQUE (tenant_id, trailer_code)
);

CREATE TABLE IF NOT EXISTS etms.containers (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    owner_partner_id uuid REFERENCES etms.business_partners(id),
    container_no varchar(20) NOT NULL,
    iso_type_code varchar(10),
    equipment_type_id uuid REFERENCES etms.equipment_types(id),
    tare_weight_kg numeric(20,6),
    max_gross_weight_kg numeric(20,6),
    current_location_id uuid REFERENCES etms.locations(id),
    status varchar(20) NOT NULL DEFAULT 'AVAILABLE',
    inspection_due_date date,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, container_no)
);

CREATE TABLE IF NOT EXISTS etms.equipment_documents (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    equipment_kind varchar(20) NOT NULL,
    equipment_id uuid NOT NULL,
    document_type varchar(80) NOT NULL,
    document_no varchar(150),
    issued_at date,
    expires_at date,
    file_id uuid REFERENCES etms.files(id),
    verification_status varchar(20) NOT NULL DEFAULT 'PENDING',
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, equipment_kind, equipment_id, document_type, document_no),
    CONSTRAINT ck_equipment_documents_kind CHECK (equipment_kind IN ('VEHICLE','TRAILER','CONTAINER'))
);

CREATE TABLE IF NOT EXISTS etms.equipment_availability (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    equipment_kind varchar(20) NOT NULL,
    equipment_id uuid NOT NULL,
    availability_type varchar(30) NOT NULL,
    starts_at timestamptz NOT NULL,
    ends_at timestamptz NOT NULL,
    location_id uuid REFERENCES etms.locations(id),
    reason text,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_equipment_availability_kind CHECK (equipment_kind IN ('VEHICLE','TRAILER','CONTAINER')),
    CONSTRAINT ck_equipment_availability_dates CHECK (ends_at > starts_at)
);

CREATE TABLE IF NOT EXISTS etms.odometer_readings (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    vehicle_id uuid NOT NULL REFERENCES etms.vehicles(id) ON DELETE CASCADE,
    reading_km numeric(20,3) NOT NULL,
    reading_at timestamptz NOT NULL,
    source_code varchar(30) NOT NULL,
    source_reference varchar(150),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (vehicle_id, reading_at, source_code),
    CONSTRAINT ck_odometer_reading CHECK (reading_km >= 0)
);

CREATE TABLE IF NOT EXISTS etms.maintenance_work_orders (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    work_order_no varchar(80) NOT NULL,
    vehicle_id uuid REFERENCES etms.vehicles(id),
    trailer_id uuid REFERENCES etms.trailers(id),
    maintenance_type varchar(50) NOT NULL,
    scheduled_at timestamptz,
    started_at timestamptz,
    completed_at timestamptz,
    odometer_km numeric(20,3),
    vendor_partner_id uuid REFERENCES etms.business_partners(id),
    estimated_cost numeric(20,4),
    actual_cost numeric(20,4),
    currency_code char(3) REFERENCES etms.currencies(currency_code),
    status varchar(20) NOT NULL DEFAULT 'PLANNED',
    description text,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, work_order_no),
    CONSTRAINT ck_maintenance_equipment CHECK ((vehicle_id IS NOT NULL)::int + (trailer_id IS NOT NULL)::int = 1)
);

CREATE TABLE IF NOT EXISTS etms.telematics_devices (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    device_code varchar(100) NOT NULL,
    device_type varchar(30) NOT NULL,
    manufacturer varchar(100),
    model varchar(100),
    serial_no varchar(150),
    imei_encrypted text,
    imei_search_hash char(64),
    provider_partner_id uuid REFERENCES etms.business_partners(id),
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    activated_at timestamptz,
    deactivated_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, device_code)
);

CREATE TABLE IF NOT EXISTS etms.device_assignments (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    device_id uuid NOT NULL REFERENCES etms.telematics_devices(id),
    asset_type varchar(20) NOT NULL,
    asset_id uuid NOT NULL,
    assigned_at timestamptz NOT NULL,
    unassigned_at timestamptz,
    is_primary boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_device_assignments_asset CHECK (asset_type IN ('VEHICLE','TRAILER','CONTAINER','HANDLING_UNIT')),
    CONSTRAINT ck_device_assignments_dates CHECK (unassigned_at IS NULL OR unassigned_at > assigned_at)
);

CREATE TABLE IF NOT EXISTS etms.service_regions (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    region_code varchar(80) NOT NULL,
    region_name varchar(200) NOT NULL,
    country_code char(2) REFERENCES etms.countries(country_code),
    postal_code_patterns text[],
    polygon_geojson jsonb,
    timezone varchar(100),
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, region_code)
);

CREATE TABLE IF NOT EXISTS etms.carrier_service_regions (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    carrier_id uuid NOT NULL REFERENCES etms.carrier_profiles(partner_id) ON DELETE CASCADE,
    service_region_id uuid NOT NULL REFERENCES etms.service_regions(id),
    mode_code varchar(20) NOT NULL REFERENCES etms.transport_modes(mode_code),
    service_level_id uuid REFERENCES etms.service_levels(id),
    valid_from date NOT NULL DEFAULT CURRENT_DATE,
    valid_to date,
    capacity_per_day numeric(20,6),
    capacity_uom_code varchar(20) REFERENCES etms.units_of_measure(uom_code)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_carrier_service_regions_scope
    ON etms.carrier_service_regions (
        carrier_id, service_region_id, mode_code,
        COALESCE(service_level_id, '00000000-0000-0000-0000-000000000000'::uuid),
        valid_from
    );

CREATE TABLE IF NOT EXISTS etms.lanes (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    lane_code varchar(80) NOT NULL,
    lane_name varchar(200) NOT NULL,
    origin_location_id uuid REFERENCES etms.locations(id),
    origin_region_id uuid REFERENCES etms.service_regions(id),
    destination_location_id uuid REFERENCES etms.locations(id),
    destination_region_id uuid REFERENCES etms.service_regions(id),
    mode_code varchar(20) NOT NULL REFERENCES etms.transport_modes(mode_code),
    standard_distance_km numeric(16,3),
    standard_transit_minutes integer,
    toll_estimate numeric(20,4),
    toll_currency_code char(3) REFERENCES etms.currencies(currency_code),
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, lane_code),
    CONSTRAINT ck_lanes_origin CHECK ((origin_location_id IS NOT NULL)::int + (origin_region_id IS NOT NULL)::int = 1),
    CONSTRAINT ck_lanes_destination CHECK ((destination_location_id IS NOT NULL)::int + (destination_region_id IS NOT NULL)::int = 1),
    CONSTRAINT ck_lanes_distance CHECK (standard_distance_km IS NULL OR standard_distance_km >= 0),
    CONSTRAINT ck_lanes_transit CHECK (standard_transit_minutes IS NULL OR standard_transit_minutes >= 0)
);

CREATE TABLE IF NOT EXISTS etms.lane_points (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    lane_id uuid NOT NULL REFERENCES etms.lanes(id) ON DELETE CASCADE,
    sequence_no integer NOT NULL,
    location_id uuid REFERENCES etms.locations(id),
    latitude numeric(10,7),
    longitude numeric(11,7),
    point_type varchar(30) NOT NULL DEFAULT 'VIA',
    cumulative_distance_km numeric(16,3),
    planned_dwell_minutes integer,
    UNIQUE (lane_id, sequence_no),
    CONSTRAINT ck_lane_points_sequence CHECK (sequence_no > 0)
);

CREATE TABLE IF NOT EXISTS etms.routes (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    route_code varchar(80) NOT NULL,
    route_name varchar(200) NOT NULL,
    route_type varchar(30) NOT NULL DEFAULT 'STANDARD',
    mode_code varchar(20) NOT NULL REFERENCES etms.transport_modes(mode_code),
    total_distance_km numeric(16,3),
    total_transit_minutes integer,
    version_no integer NOT NULL DEFAULT 1,
    valid_from date,
    valid_to date,
    is_active boolean NOT NULL DEFAULT true,
    geometry_geojson jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, route_code, version_no),
    CONSTRAINT ck_routes_distance CHECK (total_distance_km IS NULL OR total_distance_km >= 0),
    CONSTRAINT ck_routes_dates CHECK (valid_to IS NULL OR valid_from IS NULL OR valid_to >= valid_from)
);

CREATE TABLE IF NOT EXISTS etms.route_legs (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    route_id uuid NOT NULL REFERENCES etms.routes(id) ON DELETE CASCADE,
    sequence_no integer NOT NULL,
    from_location_id uuid NOT NULL REFERENCES etms.locations(id),
    to_location_id uuid NOT NULL REFERENCES etms.locations(id),
    lane_id uuid REFERENCES etms.lanes(id),
    distance_km numeric(16,3),
    transit_minutes integer,
    toll_amount numeric(20,4),
    toll_currency_code char(3) REFERENCES etms.currencies(currency_code),
    restrictions jsonb NOT NULL DEFAULT '{}'::jsonb,
    UNIQUE (route_id, sequence_no),
    CONSTRAINT ck_route_legs_locations CHECK (from_location_id <> to_location_id),
    CONSTRAINT ck_route_legs_distance CHECK (distance_km IS NULL OR distance_km >= 0)
);

CREATE TABLE IF NOT EXISTS etms.location_distance_matrix (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    from_location_id uuid NOT NULL REFERENCES etms.locations(id),
    to_location_id uuid NOT NULL REFERENCES etms.locations(id),
    mode_code varchar(20) NOT NULL REFERENCES etms.transport_modes(mode_code),
    distance_km numeric(16,3) NOT NULL,
    duration_minutes integer NOT NULL,
    source_code varchar(50) NOT NULL,
    calculated_at timestamptz NOT NULL,
    valid_until timestamptz,
    route_geometry_geojson jsonb,
    UNIQUE (tenant_id, from_location_id, to_location_id, mode_code, source_code),
    CONSTRAINT ck_distance_matrix_locations CHECK (from_location_id <> to_location_id),
    CONSTRAINT ck_distance_matrix_values CHECK (distance_km >= 0 AND duration_minutes >= 0)
);
