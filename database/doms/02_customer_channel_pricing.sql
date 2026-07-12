-- DOMS enterprise OMS schema - customers, channels, fulfillment sources, pricing, and promotions.
-- PostgreSQL 11 compatible. Applied after 01_reference_partner_item.sql.

CREATE TABLE IF NOT EXISTS doms.customers (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    customer_no varchar(80) NOT NULL,
    customer_type varchar(20) NOT NULL DEFAULT 'INDIVIDUAL',
    partner_id uuid REFERENCES doms.business_partners(id),
    display_name varchar(300) NOT NULL,
    legal_name varchar(300),
    primary_email varchar(320),
    email_search_hash char(64),
    phone_encrypted text,
    phone_search_hash char(64),
    phone_masked varchar(50),
    locale varchar(20) NOT NULL DEFAULT 'ko-KR',
    timezone varchar(100) NOT NULL DEFAULT 'Asia/Seoul',
    default_currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    lifecycle_status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    risk_status varchar(20) NOT NULL DEFAULT 'UNASSESSED',
    registered_at timestamptz,
    anonymized_at timestamptz,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    UNIQUE (tenant_id, customer_no),
    CONSTRAINT ck_customers_type CHECK (customer_type IN ('INDIVIDUAL','BUSINESS','GUEST','INTERNAL')),
    CONSTRAINT ck_customers_lifecycle CHECK (lifecycle_status IN ('PROSPECT','ACTIVE','BLOCKED','DORMANT','CLOSED','ANONYMIZED')),
    CONSTRAINT ck_customers_risk CHECK (risk_status IN ('UNASSESSED','LOW','MEDIUM','HIGH','BLOCKED')),
    CONSTRAINT ck_customers_metadata_secrets CHECK (NOT doms.jsonb_contains_forbidden_secret_key(metadata)),
    CONSTRAINT ck_customers_anonymized CHECK (
        lifecycle_status <> 'ANONYMIZED' OR anonymized_at IS NOT NULL
    )
);

COMMENT ON COLUMN doms.customers.primary_email IS
    'Mutable contact/search value. It is never an authentication, identity-link, or automatic merge key.';

CREATE INDEX IF NOT EXISTS ix_customers_email_search
    ON doms.customers (tenant_id, email_search_hash)
    WHERE email_search_hash IS NOT NULL AND deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS ix_customers_phone_search
    ON doms.customers (tenant_id, phone_search_hash)
    WHERE phone_search_hash IS NOT NULL AND deleted_at IS NULL;

CREATE TABLE IF NOT EXISTS doms.customer_identifiers (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    customer_id uuid NOT NULL REFERENCES doms.customers(id) ON DELETE RESTRICT,
    identifier_type varchar(40) NOT NULL,
    identifier_value_encrypted text,
    identifier_search_hash char(64) NOT NULL,
    masked_value varchar(120),
    issuer varchar(150),
    verified_at timestamptz,
    valid_from date,
    valid_to date,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, identifier_type, identifier_search_hash),
    CONSTRAINT ck_customer_identifiers_type CHECK (identifier_type IN (
        'ERP_CUSTOMER','CRM_CUSTOMER','MEMBERSHIP','BUSINESS_REGISTRATION','TAX_ID','CHANNEL_CUSTOMER','OTHER'
    )),
    CONSTRAINT ck_customer_identifiers_dates CHECK (valid_to IS NULL OR valid_from IS NULL OR valid_to >= valid_from)
);

CREATE TABLE IF NOT EXISTS doms.customer_groups (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    group_code varchar(80) NOT NULL,
    group_name varchar(200) NOT NULL,
    group_type varchar(30) NOT NULL DEFAULT 'SEGMENT',
    description text,
    is_dynamic boolean NOT NULL DEFAULT false,
    rule_expression jsonb,
    priority integer NOT NULL DEFAULT 100,
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, group_code),
    CONSTRAINT ck_customer_groups_type CHECK (group_type IN ('SEGMENT','PRICE_GROUP','SERVICE_LEVEL','RISK_GROUP','LOYALTY_TIER')),
    CONSTRAINT ck_customer_groups_priority CHECK (priority >= 0),
    CONSTRAINT ck_customer_groups_rule CHECK (
        (is_dynamic AND rule_expression IS NOT NULL) OR (NOT is_dynamic AND rule_expression IS NULL)
    ),
    CONSTRAINT ck_customer_groups_rule_secrets CHECK (
        rule_expression IS NULL OR NOT doms.jsonb_contains_forbidden_secret_key(rule_expression)
    )
);

CREATE TABLE IF NOT EXISTS doms.customer_group_members (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    customer_group_id uuid NOT NULL REFERENCES doms.customer_groups(id) ON DELETE RESTRICT,
    customer_id uuid NOT NULL REFERENCES doms.customers(id) ON DELETE RESTRICT,
    source varchar(20) NOT NULL DEFAULT 'MANUAL',
    valid_from timestamptz NOT NULL DEFAULT now(),
    valid_to timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, customer_group_id, customer_id, valid_from),
    CONSTRAINT ck_customer_group_members_source CHECK (source IN ('MANUAL','RULE','IMPORT','INTEGRATION')),
    CONSTRAINT ck_customer_group_members_dates CHECK (valid_to IS NULL OR valid_to > valid_from)
);

CREATE TABLE IF NOT EXISTS doms.customer_addresses (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    customer_id uuid NOT NULL REFERENCES doms.customers(id) ON DELETE RESTRICT,
    address_id uuid NOT NULL REFERENCES doms.addresses(id) ON DELETE RESTRICT,
    address_type varchar(20) NOT NULL,
    recipient_name_encrypted text,
    recipient_phone_encrypted text,
    recipient_phone_masked varchar(50),
    delivery_instructions_encrypted text,
    is_default boolean NOT NULL DEFAULT false,
    is_active boolean NOT NULL DEFAULT true,
    valid_from timestamptz NOT NULL DEFAULT now(),
    valid_to timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_customer_addresses_type CHECK (address_type IN ('BILLING','SHIPPING','PICKUP','SERVICE','OTHER')),
    CONSTRAINT ck_customer_addresses_dates CHECK (valid_to IS NULL OR valid_to > valid_from)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_customer_default_address
    ON doms.customer_addresses (tenant_id, customer_id, address_type)
    WHERE is_default AND is_active AND valid_to IS NULL;

CREATE TABLE IF NOT EXISTS doms.customer_contacts (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    customer_id uuid NOT NULL REFERENCES doms.customers(id) ON DELETE RESTRICT,
    contact_id uuid NOT NULL REFERENCES doms.contacts(id) ON DELETE RESTRICT,
    contact_role varchar(30) NOT NULL DEFAULT 'PRIMARY',
    is_default boolean NOT NULL DEFAULT false,
    is_active boolean NOT NULL DEFAULT true,
    valid_from timestamptz NOT NULL DEFAULT now(),
    valid_to timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, customer_id, contact_id, contact_role),
    CONSTRAINT ck_customer_contacts_role CHECK (contact_role IN ('PRIMARY','BILLING','SHIPPING','PROCUREMENT','RETURNS','SERVICE','OTHER')),
    CONSTRAINT ck_customer_contacts_dates CHECK (valid_to IS NULL OR valid_to > valid_from)
);

CREATE TABLE IF NOT EXISTS doms.customer_preferences (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    customer_id uuid NOT NULL REFERENCES doms.customers(id) ON DELETE RESTRICT,
    preference_key varchar(120) NOT NULL,
    preference_value jsonb NOT NULL,
    source varchar(30) NOT NULL DEFAULT 'CUSTOMER',
    valid_from timestamptz NOT NULL DEFAULT now(),
    valid_to timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, customer_id, preference_key, valid_from),
    CONSTRAINT ck_customer_preferences_source CHECK (source IN ('CUSTOMER','AGENT','IMPORT','INTEGRATION','POLICY')),
    CONSTRAINT ck_customer_preferences_dates CHECK (valid_to IS NULL OR valid_to > valid_from),
    CONSTRAINT ck_customer_preferences_secrets CHECK (NOT doms.jsonb_contains_forbidden_secret_key(preference_value))
);

CREATE TABLE IF NOT EXISTS doms.customer_consents (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    customer_id uuid NOT NULL REFERENCES doms.customers(id) ON DELETE RESTRICT,
    consent_type varchar(40) NOT NULL,
    purpose_code varchar(80) NOT NULL,
    policy_version varchar(50) NOT NULL,
    status varchar(20) NOT NULL,
    capture_channel varchar(40),
    captured_at timestamptz NOT NULL,
    expires_at timestamptz,
    withdrawn_at timestamptz,
    evidence_file_id uuid REFERENCES doms.files(id),
    correlation_id uuid,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_customer_consents_status CHECK (status IN ('GRANTED','DENIED','WITHDRAWN','EXPIRED')),
    CONSTRAINT ck_customer_consents_dates CHECK (
        (expires_at IS NULL OR expires_at > captured_at) AND
        (withdrawn_at IS NULL OR withdrawn_at >= captured_at) AND
        (status <> 'WITHDRAWN' OR withdrawn_at IS NOT NULL)
    )
);

CREATE INDEX IF NOT EXISTS ix_customer_consents_current
    ON doms.customer_consents (tenant_id, customer_id, consent_type, purpose_code, captured_at DESC);

CREATE TABLE IF NOT EXISTS doms.customer_tax_profiles (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    customer_id uuid NOT NULL REFERENCES doms.customers(id) ON DELETE RESTRICT,
    country_code char(2) NOT NULL REFERENCES doms.countries(country_code),
    tax_identifier_encrypted text,
    tax_identifier_hash char(64),
    tax_identifier_masked varchar(100),
    tax_exempt boolean NOT NULL DEFAULT false,
    exemption_reason varchar(200),
    exemption_certificate_file_id uuid REFERENCES doms.files(id),
    valid_from date NOT NULL,
    valid_to date,
    verification_status varchar(20) NOT NULL DEFAULT 'UNVERIFIED',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, customer_id, country_code, valid_from),
    CONSTRAINT ck_customer_tax_profiles_status CHECK (verification_status IN ('UNVERIFIED','PENDING','VERIFIED','REJECTED','EXPIRED')),
    CONSTRAINT ck_customer_tax_profiles_dates CHECK (valid_to IS NULL OR valid_to >= valid_from),
    CONSTRAINT ck_customer_tax_profiles_exemption CHECK (
        NOT tax_exempt OR exemption_reason IS NOT NULL
    )
);

CREATE TABLE IF NOT EXISTS doms.customer_credit_profiles (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    customer_id uuid NOT NULL REFERENCES doms.customers(id) ON DELETE RESTRICT,
    organization_id uuid NOT NULL REFERENCES doms.organizations(id) ON DELETE RESTRICT,
    currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    credit_limit numeric(20,6) NOT NULL DEFAULT 0,
    current_exposure numeric(20,6) NOT NULL DEFAULT 0,
    payment_term_id uuid REFERENCES doms.payment_terms(id),
    credit_rating varchar(30),
    review_status varchar(20) NOT NULL DEFAULT 'PENDING',
    last_reviewed_at timestamptz,
    next_review_at timestamptz,
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, customer_id, organization_id, currency_code),
    CONSTRAINT ck_customer_credit_profiles_amounts CHECK (
        credit_limit >= 0 AND current_exposure >= 0
    ),
    CONSTRAINT ck_customer_credit_profiles_status CHECK (review_status IN ('PENDING','APPROVED','REVIEW_REQUIRED','SUSPENDED','REJECTED')),
    CONSTRAINT ck_customer_credit_profiles_review CHECK (next_review_at IS NULL OR last_reviewed_at IS NULL OR next_review_at > last_reviewed_at)
);

CREATE TABLE IF NOT EXISTS doms.customer_credit_holds (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    customer_credit_profile_id uuid NOT NULL REFERENCES doms.customer_credit_profiles(id) ON DELETE RESTRICT,
    hold_type varchar(30) NOT NULL,
    reason_code varchar(80),
    reason_detail text,
    placed_by uuid REFERENCES doms.users(id),
    placed_at timestamptz NOT NULL DEFAULT now(),
    released_by uuid REFERENCES doms.users(id),
    released_at timestamptz,
    release_reason text,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_customer_credit_holds_type CHECK (hold_type IN ('CREDIT_LIMIT','DELINQUENCY','RISK','COMPLIANCE','MANUAL')),
    CONSTRAINT ck_customer_credit_holds_release CHECK (
        (released_at IS NULL AND released_by IS NULL) OR
        (released_at IS NOT NULL AND released_by IS NOT NULL AND released_at >= placed_at)
    )
);

CREATE TABLE IF NOT EXISTS doms.customer_relationships (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    parent_customer_id uuid NOT NULL REFERENCES doms.customers(id) ON DELETE RESTRICT,
    child_customer_id uuid NOT NULL REFERENCES doms.customers(id) ON DELETE RESTRICT,
    relationship_type varchar(30) NOT NULL,
    valid_from date NOT NULL DEFAULT CURRENT_DATE,
    valid_to date,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, parent_customer_id, child_customer_id, relationship_type, valid_from),
    CONSTRAINT ck_customer_relationships_self CHECK (parent_customer_id <> child_customer_id),
    CONSTRAINT ck_customer_relationships_type CHECK (relationship_type IN ('PARENT','AFFILIATE','BILL_TO','SHIP_TO','BUYER','BENEFICIARY')),
    CONSTRAINT ck_customer_relationships_dates CHECK (valid_to IS NULL OR valid_to >= valid_from)
);

CREATE TABLE IF NOT EXISTS doms.sales_channels (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    channel_code varchar(60) NOT NULL,
    channel_name varchar(200) NOT NULL,
    channel_type varchar(30) NOT NULL,
    external_system_id uuid REFERENCES doms.external_systems(id),
    default_currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    default_locale varchar(20) NOT NULL DEFAULT 'ko-KR',
    default_timezone varchar(100) NOT NULL DEFAULT 'Asia/Seoul',
    supports_backorder boolean NOT NULL DEFAULT false,
    supports_preorder boolean NOT NULL DEFAULT false,
    supports_partial_fulfillment boolean NOT NULL DEFAULT true,
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    UNIQUE (tenant_id, channel_code),
    CONSTRAINT ck_sales_channels_type CHECK (channel_type IN ('WEB','MOBILE','MARKETPLACE','STORE','POS','CALL_CENTER','EDI','B2B','SOCIAL','SUBSCRIPTION','OTHER')),
    CONSTRAINT ck_sales_channels_status CHECK (status IN ('DRAFT','ACTIVE','SUSPENDED','CLOSED')),
    CONSTRAINT ck_sales_channels_metadata_secrets CHECK (NOT doms.jsonb_contains_forbidden_secret_key(metadata))
);

CREATE TABLE IF NOT EXISTS doms.channel_accounts (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    sales_channel_id uuid NOT NULL REFERENCES doms.sales_channels(id) ON DELETE RESTRICT,
    account_code varchar(80) NOT NULL,
    account_name varchar(200) NOT NULL,
    external_account_id varchar(200),
    organization_id uuid REFERENCES doms.organizations(id),
    secret_reference varchar(500),
    connection_status varchar(20) NOT NULL DEFAULT 'NOT_CONFIGURED',
    last_connected_at timestamptz,
    is_active boolean NOT NULL DEFAULT true,
    settings jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, sales_channel_id, account_code),
    CONSTRAINT ck_channel_accounts_status CHECK (connection_status IN ('NOT_CONFIGURED','ACTIVE','DEGRADED','SUSPENDED','REVOKED')),
    CONSTRAINT ck_channel_accounts_settings_secrets CHECK (NOT doms.jsonb_contains_forbidden_secret_key(settings))
);

COMMENT ON COLUMN doms.channel_accounts.secret_reference IS
    'Opaque external secret-manager reference only; channel credentials and access tokens are never stored in DOMS.';

CREATE TABLE IF NOT EXISTS doms.channel_stores (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    channel_account_id uuid NOT NULL REFERENCES doms.channel_accounts(id) ON DELETE RESTRICT,
    store_code varchar(80) NOT NULL,
    store_name varchar(200) NOT NULL,
    external_store_id varchar(200),
    country_code char(2) REFERENCES doms.countries(country_code),
    currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    locale varchar(20) NOT NULL DEFAULT 'ko-KR',
    timezone varchar(100) NOT NULL DEFAULT 'Asia/Seoul',
    order_prefix varchar(30),
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, channel_account_id, store_code),
    UNIQUE (tenant_id, channel_account_id, external_store_id)
);

CREATE TABLE IF NOT EXISTS doms.channel_catalogs (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    sales_channel_id uuid NOT NULL REFERENCES doms.sales_channels(id) ON DELETE RESTRICT,
    catalog_code varchar(80) NOT NULL,
    catalog_name varchar(200) NOT NULL,
    currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    valid_from timestamptz,
    valid_to timestamptz,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, sales_channel_id, catalog_code),
    CONSTRAINT ck_channel_catalogs_status CHECK (status IN ('DRAFT','ACTIVE','SUSPENDED','EXPIRED')),
    CONSTRAINT ck_channel_catalogs_dates CHECK (valid_to IS NULL OR valid_from IS NULL OR valid_to > valid_from)
);

CREATE TABLE IF NOT EXISTS doms.channel_catalog_items (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    channel_catalog_id uuid NOT NULL REFERENCES doms.channel_catalogs(id) ON DELETE RESTRICT,
    item_id uuid NOT NULL REFERENCES doms.items(id) ON DELETE RESTRICT,
    external_listing_id varchar(200),
    external_sku varchar(200),
    display_name varchar(300),
    listing_status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    allow_backorder boolean,
    allow_preorder boolean,
    min_order_quantity numeric(20,6) NOT NULL DEFAULT 1,
    max_order_quantity numeric(20,6),
    quantity_increment numeric(20,6) NOT NULL DEFAULT 1,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, channel_catalog_id, item_id),
    UNIQUE (tenant_id, channel_catalog_id, external_listing_id),
    CONSTRAINT ck_channel_catalog_items_status CHECK (listing_status IN ('DRAFT','ACTIVE','OUT_OF_STOCK','SUSPENDED','DELISTED')),
    CONSTRAINT ck_channel_catalog_items_quantities CHECK (
        min_order_quantity > 0 AND quantity_increment > 0 AND
        (max_order_quantity IS NULL OR max_order_quantity >= min_order_quantity)
    ),
    CONSTRAINT ck_channel_catalog_items_metadata_secrets CHECK (NOT doms.jsonb_contains_forbidden_secret_key(metadata))
);

CREATE TABLE IF NOT EXISTS doms.channel_status_mappings (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    sales_channel_id uuid NOT NULL REFERENCES doms.sales_channels(id) ON DELETE RESTRICT,
    entity_type varchar(40) NOT NULL,
    direction varchar(10) NOT NULL,
    external_status varchar(100) NOT NULL,
    internal_status varchar(100) NOT NULL,
    is_terminal boolean NOT NULL DEFAULT false,
    priority integer NOT NULL DEFAULT 100,
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, sales_channel_id, entity_type, direction, external_status),
    CONSTRAINT ck_channel_status_mappings_direction CHECK (direction IN ('INBOUND','OUTBOUND')),
    CONSTRAINT ck_channel_status_mappings_priority CHECK (priority >= 0)
);

CREATE TABLE IF NOT EXISTS doms.channel_value_mappings (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    sales_channel_id uuid NOT NULL REFERENCES doms.sales_channels(id) ON DELETE RESTRICT,
    mapping_type varchar(60) NOT NULL,
    direction varchar(10) NOT NULL,
    external_value varchar(300) NOT NULL,
    internal_value varchar(300) NOT NULL,
    valid_from timestamptz,
    valid_to timestamptz,
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, sales_channel_id, mapping_type, direction, external_value),
    CONSTRAINT ck_channel_value_mappings_direction CHECK (direction IN ('INBOUND','OUTBOUND')),
    CONSTRAINT ck_channel_value_mappings_dates CHECK (valid_to IS NULL OR valid_from IS NULL OR valid_to > valid_from)
);

CREATE TABLE IF NOT EXISTS doms.order_types (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid REFERENCES doms.tenants(id),
    order_type_code varchar(50) NOT NULL,
    order_type_name varchar(150) NOT NULL,
    lifecycle_model varchar(30) NOT NULL DEFAULT 'STANDARD',
    requires_payment boolean NOT NULL DEFAULT true,
    requires_fulfillment boolean NOT NULL DEFAULT true,
    allows_partial_fulfillment boolean NOT NULL DEFAULT true,
    allows_backorder boolean NOT NULL DEFAULT false,
    allows_preorder boolean NOT NULL DEFAULT false,
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_order_types_lifecycle CHECK (lifecycle_model IN ('STANDARD','SUBSCRIPTION','PREORDER','EXCHANGE','REPLACEMENT','INTERNAL','QUOTE_CONVERSION'))
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_order_types_scope
    ON doms.order_types (
        COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), order_type_code
    );

CREATE TABLE IF NOT EXISTS doms.selling_organizations (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    organization_id uuid NOT NULL REFERENCES doms.organizations(id) ON DELETE RESTRICT,
    sales_channel_id uuid REFERENCES doms.sales_channels(id) ON DELETE RESTRICT,
    seller_partner_id uuid REFERENCES doms.business_partners(id) ON DELETE RESTRICT,
    seller_code varchar(80) NOT NULL,
    default_price_book_id uuid,
    default_payment_term_id uuid REFERENCES doms.payment_terms(id),
    default_currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    tax_registration_country char(2) REFERENCES doms.countries(country_code),
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, seller_code)
);

CREATE TABLE IF NOT EXISTS doms.fulfillment_nodes (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    node_code varchar(80) NOT NULL,
    node_name varchar(200) NOT NULL,
    node_type varchar(30) NOT NULL,
    organization_id uuid REFERENCES doms.organizations(id) ON DELETE RESTRICT,
    operator_partner_id uuid REFERENCES doms.business_partners(id) ON DELETE RESTRICT,
    external_node_id varchar(200),
    country_code char(2) NOT NULL REFERENCES doms.countries(country_code),
    timezone varchar(100) NOT NULL DEFAULT 'Asia/Seoul',
    priority integer NOT NULL DEFAULT 100,
    supports_ship_from_node boolean NOT NULL DEFAULT true,
    supports_pickup boolean NOT NULL DEFAULT false,
    supports_returns boolean NOT NULL DEFAULT false,
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    capacity_metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    UNIQUE (tenant_id, node_code),
    CONSTRAINT ck_fulfillment_nodes_type CHECK (node_type IN ('DISTRIBUTION_CENTER','WAREHOUSE','STORE','DARK_STORE','SUPPLIER','THIRD_PARTY','DIGITAL','SERVICE_CENTER')),
    CONSTRAINT ck_fulfillment_nodes_status CHECK (status IN ('PLANNED','ACTIVE','CONSTRAINED','SUSPENDED','CLOSED')),
    CONSTRAINT ck_fulfillment_nodes_priority CHECK (priority >= 0),
    CONSTRAINT ck_fulfillment_nodes_metadata_secrets CHECK (NOT doms.jsonb_contains_forbidden_secret_key(capacity_metadata))
);

CREATE TABLE IF NOT EXISTS doms.fulfillment_node_addresses (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    fulfillment_node_id uuid NOT NULL REFERENCES doms.fulfillment_nodes(id) ON DELETE RESTRICT,
    address_id uuid NOT NULL REFERENCES doms.addresses(id) ON DELETE RESTRICT,
    address_type varchar(20) NOT NULL DEFAULT 'PHYSICAL',
    is_primary boolean NOT NULL DEFAULT false,
    valid_from date NOT NULL DEFAULT CURRENT_DATE,
    valid_to date,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, fulfillment_node_id, address_id, address_type, valid_from),
    CONSTRAINT ck_fulfillment_node_addresses_type CHECK (address_type IN ('PHYSICAL','RETURN','PICKUP','BILLING')),
    CONSTRAINT ck_fulfillment_node_addresses_dates CHECK (valid_to IS NULL OR valid_to >= valid_from)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_fulfillment_node_primary_address
    ON doms.fulfillment_node_addresses (tenant_id, fulfillment_node_id, address_type)
    WHERE is_primary AND valid_to IS NULL;

CREATE TABLE IF NOT EXISTS doms.fulfillment_node_capabilities (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    fulfillment_node_id uuid NOT NULL REFERENCES doms.fulfillment_nodes(id) ON DELETE RESTRICT,
    capability_code varchar(60) NOT NULL,
    item_id uuid REFERENCES doms.items(id) ON DELETE RESTRICT,
    item_category_id uuid REFERENCES doms.item_categories(id) ON DELETE RESTRICT,
    effective_from timestamptz NOT NULL DEFAULT now(),
    effective_to timestamptz,
    capacity_value numeric(20,6),
    capacity_uom varchar(30),
    priority integer NOT NULL DEFAULT 100,
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_fulfillment_node_capabilities_code CHECK (capability_code IN (
        'SHIP','PICKUP','RETURN','DROP_SHIP','DIGITAL','INSTALL','ASSEMBLY','COLD_CHAIN','HAZMAT','PERSONALIZATION'
    )),
    CONSTRAINT ck_fulfillment_node_capabilities_scope CHECK (num_nonnulls(item_id, item_category_id) <= 1),
    CONSTRAINT ck_fulfillment_node_capabilities_dates CHECK (effective_to IS NULL OR effective_to > effective_from),
    CONSTRAINT ck_fulfillment_node_capabilities_capacity CHECK (capacity_value IS NULL OR capacity_value >= 0),
    CONSTRAINT ck_fulfillment_node_capabilities_priority CHECK (priority >= 0)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_fulfillment_node_capability_scope
    ON doms.fulfillment_node_capabilities (
        tenant_id,
        fulfillment_node_id,
        capability_code,
        COALESCE(item_id, '00000000-0000-0000-0000-000000000000'::uuid),
        COALESCE(item_category_id, '00000000-0000-0000-0000-000000000000'::uuid),
        effective_from
    );

CREATE TABLE IF NOT EXISTS doms.fulfillment_service_areas (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    fulfillment_node_id uuid NOT NULL REFERENCES doms.fulfillment_nodes(id) ON DELETE RESTRICT,
    area_code varchar(80) NOT NULL,
    country_code char(2) NOT NULL REFERENCES doms.countries(country_code),
    postal_code_pattern varchar(120),
    state_province varchar(150),
    city varchar(150),
    service_level_code varchar(80),
    priority integer NOT NULL DEFAULT 100,
    max_distance_km numeric(12,3),
    valid_from date NOT NULL DEFAULT CURRENT_DATE,
    valid_to date,
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, fulfillment_node_id, area_code),
    CONSTRAINT ck_fulfillment_service_areas_priority CHECK (priority >= 0),
    CONSTRAINT ck_fulfillment_service_areas_distance CHECK (max_distance_km IS NULL OR max_distance_km >= 0),
    CONSTRAINT ck_fulfillment_service_areas_dates CHECK (valid_to IS NULL OR valid_to >= valid_from)
);

CREATE TABLE IF NOT EXISTS doms.fulfillment_cutoffs (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    fulfillment_node_id uuid NOT NULL REFERENCES doms.fulfillment_nodes(id) ON DELETE RESTRICT,
    service_level_code varchar(80),
    day_of_week smallint NOT NULL,
    cutoff_local_time time NOT NULL,
    processing_days integer NOT NULL DEFAULT 0,
    business_calendar_id uuid REFERENCES doms.business_calendars(id),
    valid_from date NOT NULL DEFAULT CURRENT_DATE,
    valid_to date,
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_fulfillment_cutoffs_day CHECK (day_of_week BETWEEN 0 AND 6),
    CONSTRAINT ck_fulfillment_cutoffs_processing CHECK (processing_days >= 0),
    CONSTRAINT ck_fulfillment_cutoffs_dates CHECK (valid_to IS NULL OR valid_to >= valid_from)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_fulfillment_cutoff_scope
    ON doms.fulfillment_cutoffs (
        tenant_id, fulfillment_node_id,
        COALESCE(service_level_code, ''), day_of_week, valid_from
    );

CREATE TABLE IF NOT EXISTS doms.carriers (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    carrier_code varchar(80) NOT NULL,
    carrier_name varchar(200) NOT NULL,
    partner_id uuid REFERENCES doms.business_partners(id) ON DELETE RESTRICT,
    scac_code varchar(10),
    tracking_url_template text,
    support_contact_id uuid REFERENCES doms.contacts(id),
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    UNIQUE (tenant_id, carrier_code),
    CONSTRAINT ck_carriers_status CHECK (status IN ('ONBOARDING','ACTIVE','SUSPENDED','TERMINATED'))
);

CREATE TABLE IF NOT EXISTS doms.carrier_services (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    carrier_id uuid NOT NULL REFERENCES doms.carriers(id) ON DELETE RESTRICT,
    service_code varchar(80) NOT NULL,
    service_name varchar(200) NOT NULL,
    transport_mode varchar(20) NOT NULL DEFAULT 'PARCEL',
    service_level varchar(40) NOT NULL,
    min_transit_days integer,
    max_transit_days integer,
    supports_tracking boolean NOT NULL DEFAULT true,
    supports_signature boolean NOT NULL DEFAULT false,
    supports_cod boolean NOT NULL DEFAULT false,
    supports_returns boolean NOT NULL DEFAULT false,
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, carrier_id, service_code),
    CONSTRAINT ck_carrier_services_mode CHECK (transport_mode IN ('PARCEL','COURIER','TRUCK','AIR','OCEAN','RAIL','POST','DIGITAL','PICKUP')),
    CONSTRAINT ck_carrier_services_transit CHECK (
        (min_transit_days IS NULL OR min_transit_days >= 0) AND
        (max_transit_days IS NULL OR max_transit_days >= 0) AND
        (min_transit_days IS NULL OR max_transit_days IS NULL OR max_transit_days >= min_transit_days)
    )
);

CREATE TABLE IF NOT EXISTS doms.node_carrier_services (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    fulfillment_node_id uuid NOT NULL REFERENCES doms.fulfillment_nodes(id) ON DELETE RESTRICT,
    carrier_service_id uuid NOT NULL REFERENCES doms.carrier_services(id) ON DELETE RESTRICT,
    external_account_reference varchar(300),
    secret_reference varchar(500),
    pickup_cutoff_local_time time,
    priority integer NOT NULL DEFAULT 100,
    is_default boolean NOT NULL DEFAULT false,
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, fulfillment_node_id, carrier_service_id),
    CONSTRAINT ck_node_carrier_services_priority CHECK (priority >= 0)
);

COMMENT ON COLUMN doms.node_carrier_services.secret_reference IS
    'Opaque reference to carrier credentials in an approved secret manager.';

CREATE TABLE IF NOT EXISTS doms.delivery_methods (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid REFERENCES doms.tenants(id),
    method_code varchar(50) NOT NULL,
    method_name varchar(150) NOT NULL,
    method_type varchar(30) NOT NULL,
    requires_address boolean NOT NULL DEFAULT true,
    requires_appointment boolean NOT NULL DEFAULT false,
    requires_recipient_confirmation boolean NOT NULL DEFAULT false,
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_delivery_methods_type CHECK (method_type IN ('SHIP','PICKUP','CURBSIDE','LOCKER','DIGITAL','SERVICE','FREIGHT'))
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_delivery_methods_scope
    ON doms.delivery_methods (
        COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), method_code
    );

CREATE TABLE IF NOT EXISTS doms.shipping_zones (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    zone_code varchar(60) NOT NULL,
    zone_name varchar(150) NOT NULL,
    priority integer NOT NULL DEFAULT 100,
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, zone_code),
    CONSTRAINT ck_shipping_zones_priority CHECK (priority >= 0)
);

CREATE TABLE IF NOT EXISTS doms.shipping_zone_rules (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    shipping_zone_id uuid NOT NULL REFERENCES doms.shipping_zones(id) ON DELETE RESTRICT,
    country_code char(2) NOT NULL REFERENCES doms.countries(country_code),
    state_province varchar(150),
    city varchar(150),
    postal_code_from varchar(30),
    postal_code_to varchar(30),
    postal_code_pattern varchar(120),
    include_exclude varchar(10) NOT NULL DEFAULT 'INCLUDE',
    priority integer NOT NULL DEFAULT 100,
    valid_from date NOT NULL DEFAULT CURRENT_DATE,
    valid_to date,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_shipping_zone_rules_mode CHECK (include_exclude IN ('INCLUDE','EXCLUDE')),
    CONSTRAINT ck_shipping_zone_rules_priority CHECK (priority >= 0),
    CONSTRAINT ck_shipping_zone_rules_dates CHECK (valid_to IS NULL OR valid_to >= valid_from),
    CONSTRAINT ck_shipping_zone_rules_postal CHECK (
        postal_code_pattern IS NOT NULL OR postal_code_from IS NOT NULL OR
        state_province IS NOT NULL OR city IS NOT NULL
    )
);

CREATE TABLE IF NOT EXISTS doms.shipping_rate_cards (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    rate_card_code varchar(80) NOT NULL,
    rate_card_name varchar(200) NOT NULL,
    currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    sales_channel_id uuid REFERENCES doms.sales_channels(id),
    customer_group_id uuid REFERENCES doms.customer_groups(id),
    valid_from timestamptz NOT NULL,
    valid_to timestamptz,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, rate_card_code),
    CONSTRAINT ck_shipping_rate_cards_status CHECK (status IN ('DRAFT','ACTIVE','SUSPENDED','EXPIRED')),
    CONSTRAINT ck_shipping_rate_cards_dates CHECK (valid_to IS NULL OR valid_to > valid_from)
);

CREATE TABLE IF NOT EXISTS doms.shipping_rate_card_lines (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    shipping_rate_card_id uuid NOT NULL REFERENCES doms.shipping_rate_cards(id) ON DELETE RESTRICT,
    shipping_zone_id uuid REFERENCES doms.shipping_zones(id),
    carrier_service_id uuid REFERENCES doms.carrier_services(id),
    delivery_method_id uuid REFERENCES doms.delivery_methods(id),
    min_order_amount numeric(20,6),
    max_order_amount numeric(20,6),
    min_weight numeric(20,6),
    max_weight numeric(20,6),
    flat_amount numeric(20,6) NOT NULL DEFAULT 0,
    per_weight_amount numeric(20,6) NOT NULL DEFAULT 0,
    free_shipping_threshold numeric(20,6),
    priority integer NOT NULL DEFAULT 100,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_shipping_rate_card_lines_amounts CHECK (
        (min_order_amount IS NULL OR min_order_amount >= 0) AND
        (max_order_amount IS NULL OR max_order_amount >= min_order_amount) AND
        flat_amount >= 0 AND per_weight_amount >= 0 AND
        (free_shipping_threshold IS NULL OR free_shipping_threshold >= 0)
    ),
    CONSTRAINT ck_shipping_rate_card_lines_weights CHECK (
        (min_weight IS NULL OR min_weight >= 0) AND
        (max_weight IS NULL OR max_weight >= min_weight)
    ),
    CONSTRAINT ck_shipping_rate_card_lines_priority CHECK (priority >= 0)
);

CREATE TABLE IF NOT EXISTS doms.price_books (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    price_book_code varchar(80) NOT NULL,
    price_book_name varchar(200) NOT NULL,
    currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    price_includes_tax boolean NOT NULL DEFAULT false,
    rounding_scale smallint NOT NULL DEFAULT 2,
    rounding_mode varchar(20) NOT NULL DEFAULT 'HALF_UP',
    parent_price_book_id uuid REFERENCES doms.price_books(id),
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    UNIQUE (tenant_id, price_book_code),
    CONSTRAINT ck_price_books_rounding_scale CHECK (rounding_scale BETWEEN 0 AND 8),
    CONSTRAINT ck_price_books_rounding_mode CHECK (rounding_mode IN ('HALF_UP','HALF_EVEN','UP','DOWN')),
    CONSTRAINT ck_price_books_status CHECK (status IN ('DRAFT','ACTIVE','SUSPENDED','RETIRED')),
    CONSTRAINT ck_price_books_parent CHECK (parent_price_book_id IS NULL OR parent_price_book_id <> id)
);

CREATE TABLE IF NOT EXISTS doms.price_book_versions (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    price_book_id uuid NOT NULL REFERENCES doms.price_books(id) ON DELETE RESTRICT,
    version_no integer NOT NULL,
    valid_from timestamptz NOT NULL,
    valid_to timestamptz,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    change_summary text,
    approved_by uuid REFERENCES doms.users(id),
    approved_at timestamptz,
    published_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, price_book_id, version_no),
    CONSTRAINT ck_price_book_versions_number CHECK (version_no > 0),
    CONSTRAINT ck_price_book_versions_status CHECK (status IN ('DRAFT','APPROVED','PUBLISHED','EXPIRED','REVOKED')),
    CONSTRAINT ck_price_book_versions_dates CHECK (valid_to IS NULL OR valid_to > valid_from),
    CONSTRAINT ck_price_book_versions_approval CHECK (
        status NOT IN ('APPROVED','PUBLISHED') OR (approved_by IS NOT NULL AND approved_at IS NOT NULL)
    ),
    CONSTRAINT ck_price_book_versions_publish CHECK (
        status <> 'PUBLISHED' OR published_at IS NOT NULL
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_price_book_published_effective
    ON doms.price_book_versions (tenant_id, price_book_id, valid_from)
    WHERE status = 'PUBLISHED';

CREATE TABLE IF NOT EXISTS doms.price_book_assignments (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    price_book_id uuid NOT NULL REFERENCES doms.price_books(id) ON DELETE RESTRICT,
    organization_id uuid REFERENCES doms.organizations(id),
    sales_channel_id uuid REFERENCES doms.sales_channels(id),
    channel_store_id uuid REFERENCES doms.channel_stores(id),
    customer_group_id uuid REFERENCES doms.customer_groups(id),
    customer_id uuid REFERENCES doms.customers(id),
    country_code char(2) REFERENCES doms.countries(country_code),
    priority integer NOT NULL DEFAULT 100,
    valid_from timestamptz NOT NULL DEFAULT now(),
    valid_to timestamptz,
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_price_book_assignments_priority CHECK (priority >= 0),
    CONSTRAINT ck_price_book_assignments_dates CHECK (valid_to IS NULL OR valid_to > valid_from),
    CONSTRAINT ck_price_book_assignments_scope CHECK (
        num_nonnulls(organization_id, sales_channel_id, channel_store_id, customer_group_id, customer_id, country_code) >= 1
    )
);

CREATE TABLE IF NOT EXISTS doms.price_book_entries (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    price_book_version_id uuid NOT NULL REFERENCES doms.price_book_versions(id) ON DELETE RESTRICT,
    item_id uuid NOT NULL REFERENCES doms.items(id) ON DELETE RESTRICT,
    uom_code varchar(20) NOT NULL REFERENCES doms.units_of_measure(uom_code),
    item_packaging_id uuid REFERENCES doms.item_packagings(id),
    price_type varchar(20) NOT NULL DEFAULT 'REGULAR',
    list_amount numeric(20,6),
    unit_amount numeric(20,6) NOT NULL,
    cost_amount numeric(20,6),
    minimum_quantity numeric(20,6) NOT NULL DEFAULT 1,
    maximum_quantity numeric(20,6),
    quantity_increment numeric(20,6) NOT NULL DEFAULT 1,
    tax_code_id uuid REFERENCES doms.tax_codes(id),
    valid_from timestamptz,
    valid_to timestamptz,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_price_book_entries_type CHECK (price_type IN ('REGULAR','SALE','CLEARANCE','CONTRACT','MAP')),
    CONSTRAINT ck_price_book_entries_amounts CHECK (
        unit_amount >= 0 AND (list_amount IS NULL OR list_amount >= 0) AND
        (cost_amount IS NULL OR cost_amount >= 0)
    ),
    CONSTRAINT ck_price_book_entries_quantities CHECK (
        minimum_quantity > 0 AND quantity_increment > 0 AND
        (maximum_quantity IS NULL OR maximum_quantity >= minimum_quantity)
    ),
    CONSTRAINT ck_price_book_entries_dates CHECK (valid_to IS NULL OR valid_from IS NULL OR valid_to > valid_from),
    CONSTRAINT ck_price_book_entries_metadata_secrets CHECK (NOT doms.jsonb_contains_forbidden_secret_key(metadata))
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_price_book_entry_scope
    ON doms.price_book_entries (
        tenant_id, price_book_version_id, item_id, uom_code,
        COALESCE(item_packaging_id, '00000000-0000-0000-0000-000000000000'::uuid),
        price_type, minimum_quantity,
        COALESCE(valid_from, '-infinity'::timestamptz)
    );

CREATE TABLE IF NOT EXISTS doms.price_book_tiers (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    price_book_entry_id uuid NOT NULL REFERENCES doms.price_book_entries(id) ON DELETE RESTRICT,
    min_quantity numeric(20,6) NOT NULL,
    max_quantity numeric(20,6),
    unit_amount numeric(20,6) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, price_book_entry_id, min_quantity),
    CONSTRAINT ck_price_book_tiers_quantities CHECK (
        min_quantity > 0 AND (max_quantity IS NULL OR max_quantity >= min_quantity)
    ),
    CONSTRAINT ck_price_book_tiers_amount CHECK (unit_amount >= 0)
);

CREATE TABLE IF NOT EXISTS doms.customer_price_agreements (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    agreement_no varchar(80) NOT NULL,
    customer_id uuid NOT NULL REFERENCES doms.customers(id) ON DELETE RESTRICT,
    organization_id uuid NOT NULL REFERENCES doms.organizations(id) ON DELETE RESTRICT,
    currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    valid_from timestamptz NOT NULL,
    valid_to timestamptz,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    priority integer NOT NULL DEFAULT 100,
    approved_by uuid REFERENCES doms.users(id),
    approved_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, agreement_no),
    CONSTRAINT ck_customer_price_agreements_status CHECK (status IN ('DRAFT','PENDING_APPROVAL','ACTIVE','SUSPENDED','EXPIRED','TERMINATED')),
    CONSTRAINT ck_customer_price_agreements_priority CHECK (priority >= 0),
    CONSTRAINT ck_customer_price_agreements_dates CHECK (valid_to IS NULL OR valid_to > valid_from),
    CONSTRAINT ck_customer_price_agreements_approval CHECK (
        status <> 'ACTIVE' OR (approved_by IS NOT NULL AND approved_at IS NOT NULL)
    )
);

CREATE TABLE IF NOT EXISTS doms.customer_price_agreement_lines (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    customer_price_agreement_id uuid NOT NULL REFERENCES doms.customer_price_agreements(id) ON DELETE RESTRICT,
    item_id uuid REFERENCES doms.items(id),
    item_category_id uuid REFERENCES doms.item_categories(id),
    uom_code varchar(20) REFERENCES doms.units_of_measure(uom_code),
    pricing_method varchar(20) NOT NULL,
    fixed_unit_amount numeric(20,6),
    discount_percent numeric(9,6),
    markup_percent numeric(9,6),
    minimum_quantity numeric(20,6) NOT NULL DEFAULT 1,
    maximum_quantity numeric(20,6),
    valid_from timestamptz,
    valid_to timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_customer_price_agreement_lines_scope CHECK (num_nonnulls(item_id, item_category_id) = 1),
    CONSTRAINT ck_customer_price_agreement_lines_method CHECK (pricing_method IN ('FIXED','DISCOUNT_PERCENT','MARKUP_PERCENT')),
    CONSTRAINT ck_customer_price_agreement_lines_value CHECK (
        (pricing_method = 'FIXED' AND fixed_unit_amount IS NOT NULL AND fixed_unit_amount >= 0 AND discount_percent IS NULL AND markup_percent IS NULL) OR
        (pricing_method = 'DISCOUNT_PERCENT' AND fixed_unit_amount IS NULL AND discount_percent BETWEEN 0 AND 100 AND markup_percent IS NULL) OR
        (pricing_method = 'MARKUP_PERCENT' AND fixed_unit_amount IS NULL AND discount_percent IS NULL AND markup_percent >= 0)
    ),
    CONSTRAINT ck_customer_price_agreement_lines_qty CHECK (
        minimum_quantity > 0 AND (maximum_quantity IS NULL OR maximum_quantity >= minimum_quantity)
    ),
    CONSTRAINT ck_customer_price_agreement_lines_dates CHECK (valid_to IS NULL OR valid_from IS NULL OR valid_to > valid_from)
);

CREATE TABLE IF NOT EXISTS doms.promotion_campaigns (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    campaign_code varchar(80) NOT NULL,
    campaign_name varchar(200) NOT NULL,
    objective varchar(200),
    budget_currency_code char(3) REFERENCES doms.currencies(currency_code),
    budget_amount numeric(20,6),
    consumed_amount numeric(20,6) NOT NULL DEFAULT 0,
    valid_from timestamptz NOT NULL,
    valid_to timestamptz NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, campaign_code),
    CONSTRAINT ck_promotion_campaigns_amounts CHECK (
        (budget_amount IS NULL OR budget_amount >= 0) AND consumed_amount >= 0 AND
        (budget_amount IS NULL OR consumed_amount <= budget_amount)
    ),
    CONSTRAINT ck_promotion_campaigns_dates CHECK (valid_to > valid_from),
    CONSTRAINT ck_promotion_campaigns_status CHECK (status IN ('DRAFT','APPROVED','ACTIVE','PAUSED','EXPIRED','CANCELLED'))
);

CREATE TABLE IF NOT EXISTS doms.promotions (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    promotion_campaign_id uuid REFERENCES doms.promotion_campaigns(id),
    promotion_code varchar(80) NOT NULL,
    promotion_name varchar(200) NOT NULL,
    promotion_type varchar(30) NOT NULL,
    evaluation_priority integer NOT NULL DEFAULT 100,
    stacking_group varchar(80),
    can_stack boolean NOT NULL DEFAULT false,
    coupon_required boolean NOT NULL DEFAULT false,
    usage_limit_total bigint,
    usage_limit_per_customer integer,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    UNIQUE (tenant_id, promotion_code),
    CONSTRAINT ck_promotions_type CHECK (promotion_type IN ('ORDER_DISCOUNT','LINE_DISCOUNT','SHIPPING_DISCOUNT','BUY_X_GET_Y','FIXED_PRICE','GIFT','LOYALTY')),
    CONSTRAINT ck_promotions_priority CHECK (evaluation_priority >= 0),
    CONSTRAINT ck_promotions_limits CHECK (
        (usage_limit_total IS NULL OR usage_limit_total > 0) AND
        (usage_limit_per_customer IS NULL OR usage_limit_per_customer > 0)
    ),
    CONSTRAINT ck_promotions_status CHECK (status IN ('DRAFT','APPROVED','ACTIVE','PAUSED','EXPIRED','CANCELLED'))
);

CREATE TABLE IF NOT EXISTS doms.promotion_versions (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    promotion_id uuid NOT NULL REFERENCES doms.promotions(id) ON DELETE RESTRICT,
    version_no integer NOT NULL,
    valid_from timestamptz NOT NULL,
    valid_to timestamptz NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    rule_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
    approved_by uuid REFERENCES doms.users(id),
    approved_at timestamptz,
    published_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, promotion_id, version_no),
    CONSTRAINT ck_promotion_versions_number CHECK (version_no > 0),
    CONSTRAINT ck_promotion_versions_dates CHECK (valid_to > valid_from),
    CONSTRAINT ck_promotion_versions_status CHECK (status IN ('DRAFT','APPROVED','PUBLISHED','REVOKED','EXPIRED')),
    CONSTRAINT ck_promotion_versions_approval CHECK (
        status NOT IN ('APPROVED','PUBLISHED') OR (approved_by IS NOT NULL AND approved_at IS NOT NULL)
    ),
    CONSTRAINT ck_promotion_versions_publish CHECK (status <> 'PUBLISHED' OR published_at IS NOT NULL),
    CONSTRAINT ck_promotion_versions_rule_secrets CHECK (NOT doms.jsonb_contains_forbidden_secret_key(rule_snapshot))
);

CREATE TABLE IF NOT EXISTS doms.promotion_conditions (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    promotion_version_id uuid NOT NULL REFERENCES doms.promotion_versions(id) ON DELETE RESTRICT,
    condition_group integer NOT NULL DEFAULT 1,
    sequence_no integer NOT NULL,
    condition_type varchar(40) NOT NULL,
    operator varchar(20) NOT NULL,
    condition_value jsonb NOT NULL,
    negate boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, promotion_version_id, condition_group, sequence_no),
    CONSTRAINT ck_promotion_conditions_group CHECK (condition_group > 0 AND sequence_no > 0),
    CONSTRAINT ck_promotion_conditions_operator CHECK (operator IN ('EQ','NE','IN','NOT_IN','GT','GTE','LT','LTE','BETWEEN','MATCHES','EXISTS')),
    CONSTRAINT ck_promotion_conditions_value_secrets CHECK (NOT doms.jsonb_contains_forbidden_secret_key(condition_value))
);

CREATE TABLE IF NOT EXISTS doms.promotion_rewards (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    promotion_version_id uuid NOT NULL REFERENCES doms.promotion_versions(id) ON DELETE RESTRICT,
    sequence_no integer NOT NULL,
    reward_type varchar(40) NOT NULL,
    amount numeric(20,6),
    percent_value numeric(9,6),
    quantity numeric(20,6),
    item_id uuid REFERENCES doms.items(id),
    max_reward_amount numeric(20,6),
    allocation_method varchar(20) NOT NULL DEFAULT 'PROPORTIONAL',
    reward_config jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, promotion_version_id, sequence_no),
    CONSTRAINT ck_promotion_rewards_sequence CHECK (sequence_no > 0),
    CONSTRAINT ck_promotion_rewards_type CHECK (reward_type IN ('FIXED_AMOUNT','PERCENT','FREE_SHIPPING','FIXED_PRICE','FREE_ITEM','POINTS')),
    CONSTRAINT ck_promotion_rewards_values CHECK (
        (amount IS NULL OR amount >= 0) AND
        (percent_value IS NULL OR percent_value BETWEEN 0 AND 100) AND
        (quantity IS NULL OR quantity > 0) AND
        (max_reward_amount IS NULL OR max_reward_amount >= 0)
    ),
    CONSTRAINT ck_promotion_rewards_allocation CHECK (allocation_method IN ('PROPORTIONAL','EQUAL','CHEAPEST_FIRST','MOST_EXPENSIVE_FIRST','TARGET_ONLY')),
    CONSTRAINT ck_promotion_rewards_config_secrets CHECK (NOT doms.jsonb_contains_forbidden_secret_key(reward_config))
);

CREATE TABLE IF NOT EXISTS doms.promotion_product_scopes (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    promotion_version_id uuid NOT NULL REFERENCES doms.promotion_versions(id) ON DELETE RESTRICT,
    scope_mode varchar(10) NOT NULL DEFAULT 'INCLUDE',
    item_id uuid REFERENCES doms.items(id),
    item_category_id uuid REFERENCES doms.item_categories(id),
    brand_id uuid REFERENCES doms.brands(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_promotion_product_scopes_mode CHECK (scope_mode IN ('INCLUDE','EXCLUDE')),
    CONSTRAINT ck_promotion_product_scopes_target CHECK (num_nonnulls(item_id, item_category_id, brand_id) = 1)
);

CREATE TABLE IF NOT EXISTS doms.promotion_customer_scopes (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    promotion_version_id uuid NOT NULL REFERENCES doms.promotion_versions(id) ON DELETE RESTRICT,
    scope_mode varchar(10) NOT NULL DEFAULT 'INCLUDE',
    customer_id uuid REFERENCES doms.customers(id),
    customer_group_id uuid REFERENCES doms.customer_groups(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_promotion_customer_scopes_mode CHECK (scope_mode IN ('INCLUDE','EXCLUDE')),
    CONSTRAINT ck_promotion_customer_scopes_target CHECK (num_nonnulls(customer_id, customer_group_id) = 1)
);

CREATE TABLE IF NOT EXISTS doms.promotion_channel_scopes (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    promotion_version_id uuid NOT NULL REFERENCES doms.promotion_versions(id) ON DELETE RESTRICT,
    scope_mode varchar(10) NOT NULL DEFAULT 'INCLUDE',
    sales_channel_id uuid REFERENCES doms.sales_channels(id),
    channel_store_id uuid REFERENCES doms.channel_stores(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_promotion_channel_scopes_mode CHECK (scope_mode IN ('INCLUDE','EXCLUDE')),
    CONSTRAINT ck_promotion_channel_scopes_target CHECK (num_nonnulls(sales_channel_id, channel_store_id) = 1)
);

CREATE TABLE IF NOT EXISTS doms.coupon_series (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    promotion_id uuid NOT NULL REFERENCES doms.promotions(id) ON DELETE RESTRICT,
    series_code varchar(80) NOT NULL,
    issue_mode varchar(20) NOT NULL,
    max_issues bigint,
    max_redemptions_per_coupon integer NOT NULL DEFAULT 1,
    valid_from timestamptz NOT NULL,
    valid_to timestamptz NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, series_code),
    CONSTRAINT ck_coupon_series_mode CHECK (issue_mode IN ('SHARED','UNIQUE','CUSTOMER_ASSIGNED','GENERATED')),
    CONSTRAINT ck_coupon_series_limits CHECK (
        (max_issues IS NULL OR max_issues > 0) AND max_redemptions_per_coupon > 0
    ),
    CONSTRAINT ck_coupon_series_dates CHECK (valid_to > valid_from),
    CONSTRAINT ck_coupon_series_status CHECK (status IN ('DRAFT','ACTIVE','PAUSED','EXPIRED','CANCELLED'))
);

CREATE TABLE IF NOT EXISTS doms.coupons (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    coupon_series_id uuid NOT NULL REFERENCES doms.coupon_series(id) ON DELETE RESTRICT,
    coupon_code_encrypted text NOT NULL,
    coupon_code_hash char(64) NOT NULL,
    coupon_code_masked varchar(80) NOT NULL,
    assigned_customer_id uuid REFERENCES doms.customers(id) ON DELETE RESTRICT,
    issued_at timestamptz NOT NULL DEFAULT now(),
    valid_from timestamptz,
    valid_to timestamptz,
    redemption_count integer NOT NULL DEFAULT 0,
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    revoked_at timestamptz,
    revoke_reason text,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, coupon_code_hash),
    CONSTRAINT ck_coupons_redemptions CHECK (redemption_count >= 0),
    CONSTRAINT ck_coupons_dates CHECK (
        (valid_to IS NULL OR valid_from IS NULL OR valid_to > valid_from) AND
        (valid_from IS NULL OR valid_from >= issued_at)
    ),
    CONSTRAINT ck_coupons_status CHECK (status IN ('ACTIVE','RESERVED','REDEEMED','EXPIRED','REVOKED')),
    CONSTRAINT ck_coupons_revoked CHECK (status <> 'REVOKED' OR revoked_at IS NOT NULL)
);

DO $block$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'doms.selling_organizations'::regclass
          AND conname = 'fk_selling_org_default_price_book'
    ) THEN
        ALTER TABLE doms.selling_organizations
            ADD CONSTRAINT fk_selling_org_default_price_book
            FOREIGN KEY (default_price_book_id) REFERENCES doms.price_books(id) ON DELETE RESTRICT;
    END IF;
END;
$block$;
