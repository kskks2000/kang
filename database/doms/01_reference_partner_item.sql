-- DOMS enterprise OMS schema - global references, partners, products, packaging, and trade masters.
-- PostgreSQL 11 compatible. Applied after 00_foundation_auth.sql.

CREATE TABLE IF NOT EXISTS doms.countries (
    country_code char(2) PRIMARY KEY,
    country_code3 char(3) NOT NULL UNIQUE,
    numeric_code char(3),
    country_name_en varchar(200) NOT NULL,
    country_name_local varchar(200),
    default_currency_code char(3),
    is_active boolean NOT NULL DEFAULT true
);

CREATE TABLE IF NOT EXISTS doms.currencies (
    currency_code char(3) PRIMARY KEY,
    currency_name varchar(150) NOT NULL,
    numeric_code char(3),
    fraction_digits smallint NOT NULL DEFAULT 2,
    rounding_increment numeric(20,8) NOT NULL DEFAULT 0.01,
    is_active boolean NOT NULL DEFAULT true,
    CONSTRAINT ck_doms_currencies_fraction CHECK (fraction_digits BETWEEN 0 AND 8),
    CONSTRAINT ck_doms_currencies_rounding CHECK (rounding_increment > 0)
);

ALTER TABLE doms.countries
    DROP CONSTRAINT IF EXISTS fk_doms_countries_currency;
ALTER TABLE doms.countries
    ADD CONSTRAINT fk_doms_countries_currency
    FOREIGN KEY (default_currency_code) REFERENCES doms.currencies(currency_code);

CREATE TABLE IF NOT EXISTS doms.units_of_measure (
    uom_code varchar(20) PRIMARY KEY,
    uom_name varchar(100) NOT NULL,
    dimension varchar(30) NOT NULL,
    si_factor numeric(30,12) NOT NULL DEFAULT 1,
    decimal_places smallint NOT NULL DEFAULT 3,
    is_active boolean NOT NULL DEFAULT true,
    CONSTRAINT ck_doms_uom_dimension CHECK (dimension IN (
        'COUNT','MASS','VOLUME','LENGTH','AREA','TIME','TEMPERATURE','ENERGY'
    )),
    CONSTRAINT ck_doms_uom_factor CHECK (si_factor > 0),
    CONSTRAINT ck_doms_uom_decimals CHECK (decimal_places BETWEEN 0 AND 12)
);

CREATE TABLE IF NOT EXISTS doms.unit_conversions (
    from_uom_code varchar(20) NOT NULL REFERENCES doms.units_of_measure(uom_code),
    to_uom_code varchar(20) NOT NULL REFERENCES doms.units_of_measure(uom_code),
    multiplier numeric(30,12) NOT NULL,
    offset_value numeric(30,12) NOT NULL DEFAULT 0,
    valid_from date NOT NULL DEFAULT CURRENT_DATE,
    valid_to date,
    PRIMARY KEY (from_uom_code, to_uom_code, valid_from),
    CONSTRAINT ck_doms_uom_conversion_distinct CHECK (from_uom_code <> to_uom_code),
    CONSTRAINT ck_doms_uom_conversion_factor CHECK (multiplier > 0),
    CONSTRAINT ck_doms_uom_conversion_dates CHECK (valid_to IS NULL OR valid_to >= valid_from)
);

CREATE TABLE IF NOT EXISTS doms.transport_modes (
    mode_code varchar(20) PRIMARY KEY,
    mode_name varchar(100) NOT NULL,
    mode_group varchar(30) NOT NULL,
    is_active boolean NOT NULL DEFAULT true
);

CREATE TABLE IF NOT EXISTS doms.incoterms (
    incoterm_code char(3) PRIMARY KEY,
    incoterm_name varchar(150) NOT NULL,
    version_year smallint NOT NULL DEFAULT 2020,
    is_active boolean NOT NULL DEFAULT true,
    CONSTRAINT ck_doms_incoterm_year CHECK (version_year BETWEEN 1900 AND 2200)
);

CREATE TABLE IF NOT EXISTS doms.ports (
    port_code varchar(10) PRIMARY KEY,
    country_code char(2) NOT NULL REFERENCES doms.countries(country_code),
    port_name varchar(200) NOT NULL,
    port_type varchar(20) NOT NULL,
    timezone varchar(100),
    latitude numeric(10,7),
    longitude numeric(10,7),
    is_active boolean NOT NULL DEFAULT true,
    CONSTRAINT ck_doms_port_type CHECK (port_type IN ('SEA','AIR','LAND','RAIL','MULTIMODAL')),
    CONSTRAINT ck_doms_port_lat CHECK (latitude IS NULL OR latitude BETWEEN -90 AND 90),
    CONSTRAINT ck_doms_port_lon CHECK (longitude IS NULL OR longitude BETWEEN -180 AND 180)
);

CREATE TABLE IF NOT EXISTS doms.customs_offices (
    customs_office_code varchar(20) PRIMARY KEY,
    customs_office_name varchar(200) NOT NULL,
    country_code char(2) NOT NULL DEFAULT 'KR' REFERENCES doms.countries(country_code),
    parent_office_code varchar(20) REFERENCES doms.customs_offices(customs_office_code),
    address_text text,
    phone varchar(50),
    is_active boolean NOT NULL DEFAULT true
);

CREATE TABLE IF NOT EXISTS doms.hs_codes (
    hs_code varchar(20) NOT NULL,
    country_code char(2) NOT NULL DEFAULT 'KR' REFERENCES doms.countries(country_code),
    nomenclature_version varchar(20) NOT NULL,
    description_ko text,
    description_en text,
    unit_1_code varchar(20) REFERENCES doms.units_of_measure(uom_code),
    unit_2_code varchar(20) REFERENCES doms.units_of_measure(uom_code),
    valid_from date NOT NULL,
    valid_to date,
    is_active boolean NOT NULL DEFAULT true,
    PRIMARY KEY (country_code, nomenclature_version, hs_code),
    CONSTRAINT ck_doms_hs_dates CHECK (valid_to IS NULL OR valid_to >= valid_from)
);

CREATE TABLE IF NOT EXISTS doms.exchange_rates (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid REFERENCES doms.tenants(id) ON DELETE CASCADE,
    rate_type varchar(30) NOT NULL DEFAULT 'ACCOUNTING',
    from_currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    to_currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    effective_date date NOT NULL,
    rate numeric(24,12) NOT NULL,
    source_name varchar(150),
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_doms_exchange_currency CHECK (from_currency_code <> to_currency_code),
    CONSTRAINT ck_doms_exchange_rate CHECK (rate > 0)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_exchange_rates_scope
    ON doms.exchange_rates (
        COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid),
        rate_type, from_currency_code, to_currency_code, effective_date
    );

CREATE TABLE IF NOT EXISTS doms.tax_codes (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid REFERENCES doms.tenants(id) ON DELETE CASCADE,
    tax_code varchar(50) NOT NULL,
    tax_name varchar(150) NOT NULL,
    tax_type varchar(30) NOT NULL,
    country_code char(2) NOT NULL DEFAULT 'KR' REFERENCES doms.countries(country_code),
    recoverable boolean NOT NULL DEFAULT true,
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_tax_codes_scope
    ON doms.tax_codes (
        COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), tax_code
    );

CREATE TABLE IF NOT EXISTS doms.tax_rates (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid REFERENCES doms.tenants(id) ON DELETE CASCADE,
    tax_code_id uuid NOT NULL REFERENCES doms.tax_codes(id),
    rate_percent numeric(9,6) NOT NULL,
    valid_from date NOT NULL,
    valid_to date,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_doms_tax_rate CHECK (rate_percent BETWEEN 0 AND 100),
    CONSTRAINT ck_doms_tax_rate_dates CHECK (valid_to IS NULL OR valid_to >= valid_from),
    UNIQUE (tax_code_id, valid_from)
);

CREATE TABLE IF NOT EXISTS doms.payment_terms (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid REFERENCES doms.tenants(id) ON DELETE CASCADE,
    payment_term_code varchar(50) NOT NULL,
    payment_term_name varchar(150) NOT NULL,
    due_days integer NOT NULL DEFAULT 0,
    cutoff_day smallint,
    due_day_of_month smallint,
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_doms_payment_due_days CHECK (due_days >= 0),
    CONSTRAINT ck_doms_payment_cutoff CHECK (cutoff_day IS NULL OR cutoff_day BETWEEN 1 AND 31),
    CONSTRAINT ck_doms_payment_due_dom CHECK (due_day_of_month IS NULL OR due_day_of_month BETWEEN 1 AND 31)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_payment_terms_scope
    ON doms.payment_terms (
        COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), payment_term_code
    );

CREATE TABLE IF NOT EXISTS doms.charge_codes (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid REFERENCES doms.tenants(id) ON DELETE CASCADE,
    charge_code varchar(50) NOT NULL,
    charge_name varchar(150) NOT NULL,
    charge_category varchar(30) NOT NULL,
    default_basis varchar(30) NOT NULL DEFAULT 'FLAT',
    taxable boolean NOT NULL DEFAULT true,
    gl_account_code varchar(50),
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_doms_charge_category CHECK (charge_category IN (
        'INBOUND','OUTBOUND','STORAGE','HANDLING','VAS','TRANSPORT','CUSTOMS','DUTY_TAX','OTHER'
    )),
    CONSTRAINT ck_doms_charge_basis CHECK (default_basis IN (
        'FLAT','QUANTITY','WEIGHT','VOLUME','PALLET','LOCATION','DAY','HOUR','PERCENT','ACTUAL'
    ))
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_charge_codes_scope
    ON doms.charge_codes (
        COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), charge_code
    );

CREATE TABLE IF NOT EXISTS doms.reason_codes (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid REFERENCES doms.tenants(id) ON DELETE CASCADE,
    reason_group varchar(50) NOT NULL,
    reason_code varchar(50) NOT NULL,
    reason_name varchar(150) NOT NULL,
    requires_note boolean NOT NULL DEFAULT false,
    requires_approval boolean NOT NULL DEFAULT false,
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_reason_codes_scope
    ON doms.reason_codes (
        COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), reason_group, reason_code
    );

CREATE TABLE IF NOT EXISTS doms.business_partners (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    partner_code varchar(80) NOT NULL,
    partner_name varchar(300) NOT NULL,
    legal_name varchar(300),
    partner_type varchar(30) NOT NULL DEFAULT 'COMPANY',
    country_code char(2) NOT NULL DEFAULT 'KR' REFERENCES doms.countries(country_code),
    business_registration_no varchar(50),
    corporate_registration_no varchar(50),
    representative_name varchar(150),
    customs_clearance_code varchar(50),
    tax_registration_no varchar(80),
    default_currency_code char(3) NOT NULL DEFAULT 'KRW' REFERENCES doms.currencies(currency_code),
    payment_term_id uuid REFERENCES doms.payment_terms(id),
    credit_limit numeric(24,4),
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    valid_from date,
    valid_to date,
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    UNIQUE (tenant_id, partner_code),
    CONSTRAINT ck_doms_partner_type CHECK (partner_type IN ('COMPANY','PERSON','GOVERNMENT','INTERNAL')),
    CONSTRAINT ck_doms_partner_status CHECK (status IN ('PENDING','ACTIVE','ON_HOLD','INACTIVE','BLOCKED')),
    CONSTRAINT ck_doms_partner_credit CHECK (credit_limit IS NULL OR credit_limit >= 0),
    CONSTRAINT ck_doms_partner_dates CHECK (valid_to IS NULL OR valid_from IS NULL OR valid_to >= valid_from),
    CONSTRAINT ck_doms_partner_attributes_secrets CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(attributes)
    )
);

CREATE TABLE IF NOT EXISTS doms.partner_roles (
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    partner_id uuid NOT NULL REFERENCES doms.business_partners(id) ON DELETE CASCADE,
    role_code varchar(30) NOT NULL,
    valid_from date NOT NULL DEFAULT CURRENT_DATE,
    valid_to date,
    is_primary boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (partner_id, role_code, valid_from),
    CONSTRAINT ck_doms_partner_role CHECK (role_code IN (
        'INVENTORY_OWNER','CUSTOMER','SUPPLIER','CONSIGNEE','SHIPPER','CARRIER','FORWARDER',
        'CUSTOMS_BROKER','DECLARANT','BONDED_OPERATOR','BILL_TO','PAY_TO','INSURER','OTHER'
    )),
    CONSTRAINT ck_doms_partner_role_dates CHECK (valid_to IS NULL OR valid_to >= valid_from)
);

CREATE TABLE IF NOT EXISTS doms.partner_identifiers (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    partner_id uuid NOT NULL REFERENCES doms.business_partners(id) ON DELETE CASCADE,
    identifier_type varchar(50) NOT NULL,
    identifier_value varchar(300),
    identifier_value_encrypted text,
    identifier_search_hash char(64),
    masked_value varchar(100),
    issuing_country_code char(2) REFERENCES doms.countries(country_code),
    valid_from date,
    valid_to date,
    is_verified boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_doms_partner_identifier_value CHECK (
        num_nonnulls(identifier_value, identifier_value_encrypted) = 1
    ),
    CONSTRAINT ck_doms_partner_identifier_dates CHECK (valid_to IS NULL OR valid_from IS NULL OR valid_to >= valid_from)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_partner_identifier_hash
    ON doms.partner_identifiers (tenant_id, identifier_type, identifier_search_hash)
    WHERE identifier_search_hash IS NOT NULL;

CREATE TABLE IF NOT EXISTS doms.addresses (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    address_name varchar(150),
    country_code char(2) NOT NULL REFERENCES doms.countries(country_code),
    postal_code varchar(30),
    state_province varchar(150),
    city varchar(150),
    district varchar(150),
    address_line1 varchar(500) NOT NULL,
    address_line2 varchar(500),
    road_address varchar(500),
    lot_address varchar(500),
    latitude numeric(10,7),
    longitude numeric(10,7),
    timezone varchar(100),
    is_validated boolean NOT NULL DEFAULT false,
    validation_provider varchar(80),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_doms_address_lat CHECK (latitude IS NULL OR latitude BETWEEN -90 AND 90),
    CONSTRAINT ck_doms_address_lon CHECK (longitude IS NULL OR longitude BETWEEN -180 AND 180)
);

CREATE TABLE IF NOT EXISTS doms.partner_addresses (
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    partner_id uuid NOT NULL REFERENCES doms.business_partners(id) ON DELETE CASCADE,
    address_id uuid NOT NULL REFERENCES doms.addresses(id),
    address_type varchar(30) NOT NULL,
    is_primary boolean NOT NULL DEFAULT false,
    valid_from date NOT NULL DEFAULT CURRENT_DATE,
    valid_to date,
    PRIMARY KEY (partner_id, address_id, address_type, valid_from),
    CONSTRAINT ck_doms_partner_address_type CHECK (address_type IN (
        'REGISTERED','BILLING','SHIPPING','REMIT_TO','PICKUP','DELIVERY','CUSTOMS','OTHER'
    )),
    CONSTRAINT ck_doms_partner_address_dates CHECK (valid_to IS NULL OR valid_to >= valid_from)
);

CREATE TABLE IF NOT EXISTS doms.contacts (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    contact_name varchar(200) NOT NULL,
    department varchar(150),
    title varchar(100),
    email varchar(320),
    phone_encrypted text,
    phone_search_hash char(64),
    phone_masked varchar(50),
    preferred_language varchar(20) NOT NULL DEFAULT 'ko',
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS doms.partner_contacts (
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    partner_id uuid NOT NULL REFERENCES doms.business_partners(id) ON DELETE CASCADE,
    contact_id uuid NOT NULL REFERENCES doms.contacts(id) ON DELETE CASCADE,
    contact_role varchar(30) NOT NULL,
    is_primary boolean NOT NULL DEFAULT false,
    PRIMARY KEY (partner_id, contact_id, contact_role)
);

CREATE TABLE IF NOT EXISTS doms.partner_bank_accounts (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    partner_id uuid NOT NULL REFERENCES doms.business_partners(id) ON DELETE CASCADE,
    bank_country_code char(2) REFERENCES doms.countries(country_code),
    bank_code varchar(50),
    bank_name varchar(200),
    account_no_encrypted text NOT NULL,
    account_no_search_hash char(64) NOT NULL,
    account_no_masked varchar(100) NOT NULL,
    account_holder_encrypted text,
    currency_code char(3) REFERENCES doms.currencies(currency_code),
    is_primary boolean NOT NULL DEFAULT false,
    verification_status varchar(20) NOT NULL DEFAULT 'UNVERIFIED',
    verified_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, partner_id, account_no_search_hash),
    CONSTRAINT ck_doms_bank_verify CHECK (verification_status IN ('UNVERIFIED','PENDING','VERIFIED','FAILED','EXPIRED'))
);

CREATE TABLE IF NOT EXISTS doms.partner_certifications (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    partner_id uuid NOT NULL REFERENCES doms.business_partners(id) ON DELETE CASCADE,
    certification_type varchar(50) NOT NULL,
    certification_no varchar(150),
    issuer varchar(200),
    valid_from date,
    valid_to date,
    file_id uuid REFERENCES doms.files(id),
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_doms_partner_cert_dates CHECK (valid_to IS NULL OR valid_from IS NULL OR valid_to >= valid_from)
);

CREATE TABLE IF NOT EXISTS doms.item_categories (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    parent_category_id uuid REFERENCES doms.item_categories(id),
    category_code varchar(80) NOT NULL,
    category_name varchar(200) NOT NULL,
    hierarchy_path text,
    hierarchy_level integer NOT NULL DEFAULT 0,
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, category_code),
    CONSTRAINT ck_doms_item_category_parent CHECK (parent_category_id IS NULL OR parent_category_id <> id),
    CONSTRAINT ck_doms_item_category_level CHECK (hierarchy_level >= 0)
);

CREATE TABLE IF NOT EXISTS doms.brands (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    brand_code varchar(80) NOT NULL,
    brand_name varchar(200) NOT NULL,
    owner_partner_id uuid REFERENCES doms.business_partners(id),
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, brand_code)
);

CREATE TABLE IF NOT EXISTS doms.items (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    item_code varchar(120) NOT NULL,
    item_name varchar(300) NOT NULL,
    item_name_en varchar(300),
    item_type varchar(30) NOT NULL DEFAULT 'STOCK',
    category_id uuid REFERENCES doms.item_categories(id),
    brand_id uuid REFERENCES doms.brands(id),
    base_uom_code varchar(20) NOT NULL REFERENCES doms.units_of_measure(uom_code),
    weight_uom_code varchar(20) REFERENCES doms.units_of_measure(uom_code),
    gross_weight numeric(24,8),
    net_weight numeric(24,8),
    dimension_uom_code varchar(20) REFERENCES doms.units_of_measure(uom_code),
    length_value numeric(20,6),
    width_value numeric(20,6),
    height_value numeric(20,6),
    volume_uom_code varchar(20) REFERENCES doms.units_of_measure(uom_code),
    volume_value numeric(24,9),
    default_country_of_origin char(2) REFERENCES doms.countries(country_code),
    default_hs_code varchar(20),
    lot_controlled boolean NOT NULL DEFAULT false,
    serial_controlled boolean NOT NULL DEFAULT false,
    expiry_controlled boolean NOT NULL DEFAULT false,
    catch_weight_controlled boolean NOT NULL DEFAULT false,
    temperature_controlled boolean NOT NULL DEFAULT false,
    dangerous_goods boolean NOT NULL DEFAULT false,
    shelf_life_days integer,
    min_receiving_shelf_life_days integer,
    abc_class char(1),
    valuation_method varchar(20) NOT NULL DEFAULT 'MOVING_AVERAGE',
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    UNIQUE (tenant_id, item_code),
    CONSTRAINT ck_doms_item_type CHECK (item_type IN ('STOCK','NON_STOCK','SERVICE','PACKAGING','KIT','RAW_MATERIAL','FINISHED_GOOD')),
    CONSTRAINT ck_doms_item_weights CHECK (
        (gross_weight IS NULL OR gross_weight >= 0) AND
        (net_weight IS NULL OR net_weight >= 0) AND
        (gross_weight IS NULL OR net_weight IS NULL OR gross_weight >= net_weight)
    ),
    CONSTRAINT ck_doms_item_dimensions CHECK (
        (length_value IS NULL OR length_value >= 0) AND
        (width_value IS NULL OR width_value >= 0) AND
        (height_value IS NULL OR height_value >= 0) AND
        (volume_value IS NULL OR volume_value >= 0)
    ),
    CONSTRAINT ck_doms_item_shelf_life CHECK (
        (shelf_life_days IS NULL OR shelf_life_days >= 0) AND
        (min_receiving_shelf_life_days IS NULL OR min_receiving_shelf_life_days >= 0) AND
        (shelf_life_days IS NULL OR min_receiving_shelf_life_days IS NULL OR min_receiving_shelf_life_days <= shelf_life_days)
    ),
    CONSTRAINT ck_doms_item_abc CHECK (abc_class IS NULL OR abc_class IN ('A','B','C','D')),
    CONSTRAINT ck_doms_item_valuation CHECK (valuation_method IN ('STANDARD','MOVING_AVERAGE','FIFO','LIFO','SPECIFIC')),
    CONSTRAINT ck_doms_item_status CHECK (status IN ('DRAFT','ACTIVE','BLOCKED','DISCONTINUED','INACTIVE')),
    CONSTRAINT ck_doms_item_attributes_secrets CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(attributes)
    )
);

CREATE TABLE IF NOT EXISTS doms.item_owner_profiles (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    owner_partner_id uuid NOT NULL REFERENCES doms.business_partners(id),
    item_id uuid NOT NULL REFERENCES doms.items(id),
    owner_item_code varchar(120),
    owner_item_name varchar(300),
    replenishment_class varchar(30),
    costing_group varchar(50),
    billing_group varchar(50),
    allocation_priority integer NOT NULL DEFAULT 100,
    is_active boolean NOT NULL DEFAULT true,
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, owner_partner_id, item_id),
    UNIQUE (tenant_id, owner_partner_id, owner_item_code),
    CONSTRAINT ck_doms_item_owner_priority CHECK (allocation_priority >= 0),
    CONSTRAINT ck_doms_item_owner_attributes_secrets CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(attributes)
    )
);

CREATE TABLE IF NOT EXISTS doms.item_aliases (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    item_id uuid NOT NULL REFERENCES doms.items(id) ON DELETE CASCADE,
    partner_id uuid REFERENCES doms.business_partners(id),
    alias_type varchar(30) NOT NULL,
    alias_value varchar(300) NOT NULL,
    valid_from date,
    valid_to date,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_doms_item_alias_dates CHECK (valid_to IS NULL OR valid_from IS NULL OR valid_to >= valid_from)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_item_alias_scope
    ON doms.item_aliases (
        tenant_id, COALESCE(partner_id, '00000000-0000-0000-0000-000000000000'::uuid), alias_type, alias_value
    ) WHERE is_active;

CREATE TABLE IF NOT EXISTS doms.item_barcodes (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    item_id uuid NOT NULL REFERENCES doms.items(id) ON DELETE CASCADE,
    barcode_type varchar(30) NOT NULL,
    barcode_value varchar(200) NOT NULL,
    uom_code varchar(20) NOT NULL REFERENCES doms.units_of_measure(uom_code),
    quantity_per_barcode numeric(24,8) NOT NULL DEFAULT 1,
    is_primary boolean NOT NULL DEFAULT false,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, barcode_type, barcode_value),
    CONSTRAINT ck_doms_item_barcode_qty CHECK (quantity_per_barcode > 0)
);

CREATE TABLE IF NOT EXISTS doms.item_packagings (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    item_id uuid NOT NULL REFERENCES doms.items(id) ON DELETE CASCADE,
    packaging_code varchar(50) NOT NULL,
    uom_code varchar(20) NOT NULL REFERENCES doms.units_of_measure(uom_code),
    base_quantity numeric(24,8) NOT NULL,
    parent_packaging_id uuid REFERENCES doms.item_packagings(id),
    gross_weight numeric(24,8),
    weight_uom_code varchar(20) REFERENCES doms.units_of_measure(uom_code),
    length_value numeric(20,6),
    width_value numeric(20,6),
    height_value numeric(20,6),
    dimension_uom_code varchar(20) REFERENCES doms.units_of_measure(uom_code),
    ti_count integer,
    hi_count integer,
    stackable boolean NOT NULL DEFAULT true,
    is_default_receiving boolean NOT NULL DEFAULT false,
    is_default_shipping boolean NOT NULL DEFAULT false,
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, item_id, packaging_code),
    CONSTRAINT ck_doms_item_pack_base_qty CHECK (base_quantity > 0),
    CONSTRAINT ck_doms_item_pack_counts CHECK ((ti_count IS NULL OR ti_count > 0) AND (hi_count IS NULL OR hi_count > 0)),
    CONSTRAINT ck_doms_item_pack_parent CHECK (parent_packaging_id IS NULL OR parent_packaging_id <> id)
);

CREATE TABLE IF NOT EXISTS doms.item_lot_attribute_definitions (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    item_id uuid REFERENCES doms.items(id) ON DELETE CASCADE,
    attribute_code varchar(80) NOT NULL,
    attribute_name varchar(150) NOT NULL,
    data_type varchar(20) NOT NULL,
    required_on_receipt boolean NOT NULL DEFAULT false,
    validation_rule jsonb NOT NULL DEFAULT '{}'::jsonb,
    sort_order integer NOT NULL DEFAULT 0,
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_doms_lot_attr_type CHECK (data_type IN ('TEXT','NUMBER','DATE','TIMESTAMP','BOOLEAN','CODE')),
    CONSTRAINT ck_doms_lot_attr_rule_secrets CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(validation_rule)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_lot_attr_scope
    ON doms.item_lot_attribute_definitions (
        tenant_id, COALESCE(item_id, '00000000-0000-0000-0000-000000000000'::uuid), attribute_code
    );

CREATE TABLE IF NOT EXISTS doms.item_storage_requirements (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    item_id uuid NOT NULL REFERENCES doms.items(id) ON DELETE CASCADE,
    requirement_type varchar(40) NOT NULL,
    min_value numeric(20,6),
    max_value numeric(20,6),
    uom_code varchar(20) REFERENCES doms.units_of_measure(uom_code),
    code_value varchar(100),
    mandatory boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, item_id, requirement_type, code_value),
    CONSTRAINT ck_doms_storage_req_range CHECK (max_value IS NULL OR min_value IS NULL OR max_value >= min_value)
);

CREATE TABLE IF NOT EXISTS doms.dangerous_goods_profiles (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    item_id uuid NOT NULL REFERENCES doms.items(id) ON DELETE CASCADE,
    un_number varchar(10) NOT NULL,
    proper_shipping_name varchar(300),
    hazard_class varchar(20),
    subsidiary_risk varchar(30),
    packing_group varchar(10),
    flash_point_c numeric(8,3),
    marine_pollutant boolean NOT NULL DEFAULT false,
    limited_quantity boolean NOT NULL DEFAULT false,
    emergency_contact text,
    sds_file_id uuid REFERENCES doms.files(id),
    valid_from date,
    valid_to date,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_doms_dg_dates CHECK (valid_to IS NULL OR valid_from IS NULL OR valid_to >= valid_from)
);

CREATE TABLE IF NOT EXISTS doms.bill_of_materials (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    parent_item_id uuid NOT NULL REFERENCES doms.items(id),
    bom_code varchar(80) NOT NULL,
    version_no integer NOT NULL DEFAULT 1,
    valid_from date NOT NULL DEFAULT CURRENT_DATE,
    valid_to date,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, bom_code, version_no),
    CONSTRAINT ck_doms_bom_version CHECK (version_no > 0),
    CONSTRAINT ck_doms_bom_dates CHECK (valid_to IS NULL OR valid_to >= valid_from),
    CONSTRAINT ck_doms_bom_status CHECK (status IN ('DRAFT','ACTIVE','OBSOLETE'))
);

CREATE TABLE IF NOT EXISTS doms.bill_of_material_lines (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    bom_id uuid NOT NULL REFERENCES doms.bill_of_materials(id) ON DELETE CASCADE,
    line_no integer NOT NULL,
    component_item_id uuid NOT NULL REFERENCES doms.items(id),
    component_quantity numeric(24,8) NOT NULL,
    uom_code varchar(20) NOT NULL REFERENCES doms.units_of_measure(uom_code),
    scrap_percent numeric(9,6) NOT NULL DEFAULT 0,
    optional_component boolean NOT NULL DEFAULT false,
    UNIQUE (bom_id, line_no),
    CONSTRAINT ck_doms_bom_line_no CHECK (line_no > 0),
    CONSTRAINT ck_doms_bom_component_qty CHECK (component_quantity > 0),
    CONSTRAINT ck_doms_bom_scrap CHECK (scrap_percent BETWEEN 0 AND 100)
);

CREATE TABLE IF NOT EXISTS doms.inventory_statuses (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid REFERENCES doms.tenants(id) ON DELETE CASCADE,
    status_code varchar(50) NOT NULL,
    status_name varchar(150) NOT NULL,
    status_category varchar(30) NOT NULL,
    available_for_allocation boolean NOT NULL DEFAULT false,
    available_for_shipping boolean NOT NULL DEFAULT false,
    requires_hold boolean NOT NULL DEFAULT false,
    is_system_status boolean NOT NULL DEFAULT false,
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_doms_inv_status_category CHECK (status_category IN (
        'AVAILABLE','RECEIVING','QUALITY','HOLD','DAMAGED','EXPIRED','IN_TRANSIT','SHIPPED','VIRTUAL'
    ))
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_inventory_status_scope
    ON doms.inventory_statuses (
        COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), status_code
    );

CREATE TABLE IF NOT EXISTS doms.packaging_materials (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    material_code varchar(80) NOT NULL,
    material_name varchar(200) NOT NULL,
    item_id uuid REFERENCES doms.items(id),
    material_type varchar(30) NOT NULL,
    tare_weight numeric(20,6),
    weight_uom_code varchar(20) REFERENCES doms.units_of_measure(uom_code),
    reusable boolean NOT NULL DEFAULT false,
    returnable boolean NOT NULL DEFAULT false,
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, material_code),
    CONSTRAINT ck_doms_pack_material_type CHECK (material_type IN ('PALLET','CARTON','TOTE','CRATE','BAG','DRUM','WRAP','LABEL','DUNNAGE','OTHER')),
    CONSTRAINT ck_doms_pack_material_tare CHECK (tare_weight IS NULL OR tare_weight >= 0)
);

COMMENT ON TABLE doms.business_partners IS
    'Tenant business-party master. The INVENTORY_OWNER role is the mandatory 3PL client/stock-owner dimension.';
COMMENT ON TABLE doms.partner_identifiers IS
    'Personal customs identifiers must use encrypted/hash/masked fields; plaintext is reserved for non-personal business identifiers.';
COMMENT ON TABLE doms.items IS
    'Tenant SKU master. Lot, serial, expiry, catch-weight, dangerous-goods and temperature controls drive receiving and inventory validation.';
COMMENT ON TABLE doms.item_owner_profiles IS
    'Owner-specific SKU code and operational/billing attributes; ownership is never inferred from the warehouse.';
