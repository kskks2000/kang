-- ETMS enterprise TMS schema - foundation, tenancy, Firebase IAM, and platform services.
-- PostgreSQL 11 compatible. Executed by scripts/apply_etms_schema.py in one transaction.

CREATE SCHEMA IF NOT EXISTS etms;

CREATE OR REPLACE FUNCTION etms.generate_uuid()
RETURNS uuid
LANGUAGE sql
VOLATILE
AS $function$
    SELECT md5(
        random()::text || clock_timestamp()::text || txid_current()::text ||
        pg_backend_pid()::text
    )::uuid;
$function$;

CREATE OR REPLACE FUNCTION etms.touch_row()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    NEW.updated_at := now();
    NEW.row_version := OLD.row_version + 1;
    RETURN NEW;
END;
$function$;

CREATE TABLE IF NOT EXISTS etms.schema_migrations (
    version varchar(50) PRIMARY KEY,
    description text NOT NULL,
    checksum_sha256 char(64) NOT NULL,
    catalog_checksum_sha256 char(64),
    baseline_seed_checksum_sha256 char(64),
    applied_at timestamptz NOT NULL DEFAULT now(),
    applied_by text NOT NULL DEFAULT current_user,
    CONSTRAINT ck_schema_migrations_sql_checksum
        CHECK (checksum_sha256 ~ '^[0-9a-f]{64}$'),
    CONSTRAINT ck_schema_migrations_catalog_checksum
        CHECK (catalog_checksum_sha256 IS NULL OR catalog_checksum_sha256 ~ '^[0-9a-f]{64}$'),
    CONSTRAINT ck_schema_migrations_seed_checksum
        CHECK (baseline_seed_checksum_sha256 IS NULL OR baseline_seed_checksum_sha256 ~ '^[0-9a-f]{64}$')
);

CREATE TABLE IF NOT EXISTS etms.tenants (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_code varchar(50) NOT NULL UNIQUE,
    tenant_name varchar(200) NOT NULL,
    legal_name varchar(300),
    business_registration_no varchar(50),
    default_currency_code char(3) NOT NULL DEFAULT 'KRW',
    default_locale varchar(20) NOT NULL DEFAULT 'ko-KR',
    default_timezone varchar(100) NOT NULL DEFAULT 'Asia/Seoul',
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    activated_at timestamptz,
    suspended_at timestamptz,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    CONSTRAINT ck_tenants_status CHECK (status IN ('PENDING','ACTIVE','SUSPENDED','CLOSED'))
);

CREATE TABLE IF NOT EXISTS etms.tenant_settings (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id) ON DELETE CASCADE,
    setting_key varchar(150) NOT NULL,
    setting_value jsonb,
    is_secret boolean NOT NULL DEFAULT false,
    secret_reference varchar(500),
    description text,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, setting_key),
    CONSTRAINT ck_tenant_settings_storage CHECK (
        (NOT is_secret AND setting_value IS NOT NULL AND secret_reference IS NULL)
        OR
        (is_secret AND setting_value IS NULL AND secret_reference IS NOT NULL)
    ),
    CONSTRAINT ck_tenant_settings_secret_reference CHECK (
        secret_reference IS NULL
        OR secret_reference ~ '^(projects/[^/]+/secrets/[^/]+/versions/[^/]+|arn:aws:secretsmanager:|https://[^/]+\.vault\.azure\.net/secrets/)'
    )
);

CREATE TABLE IF NOT EXISTS etms.organizations (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    organization_code varchar(50) NOT NULL,
    organization_name varchar(200) NOT NULL,
    organization_type varchar(30) NOT NULL DEFAULT 'LEGAL_ENTITY',
    country_code char(2) NOT NULL DEFAULT 'KR',
    business_registration_no varchar(50),
    corporate_registration_no varchar(50),
    representative_name varchar(100),
    base_currency_code char(3) NOT NULL DEFAULT 'KRW',
    timezone varchar(100) NOT NULL DEFAULT 'Asia/Seoul',
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    valid_from date,
    valid_to date,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    UNIQUE (tenant_id, organization_code),
    CONSTRAINT ck_organizations_type CHECK (organization_type IN ('LEGAL_ENTITY','BUSINESS_UNIT','BRANCH','OPERATING_COMPANY')),
    CONSTRAINT ck_organizations_dates CHECK (valid_to IS NULL OR valid_from IS NULL OR valid_to >= valid_from)
);

CREATE TABLE IF NOT EXISTS etms.organization_units (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    organization_id uuid NOT NULL REFERENCES etms.organizations(id),
    parent_unit_id uuid REFERENCES etms.organization_units(id),
    unit_code varchar(50) NOT NULL,
    unit_name varchar(200) NOT NULL,
    unit_type varchar(30) NOT NULL DEFAULT 'DEPARTMENT',
    manager_user_id uuid,
    cost_center_code varchar(50),
    hierarchy_path text,
    hierarchy_level integer NOT NULL DEFAULT 0,
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    valid_from date,
    valid_to date,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    UNIQUE (tenant_id, organization_id, unit_code),
    CONSTRAINT ck_org_units_parent CHECK (parent_unit_id IS NULL OR parent_unit_id <> id),
    CONSTRAINT ck_org_units_dates CHECK (valid_to IS NULL OR valid_from IS NULL OR valid_to >= valid_from)
);

CREATE TABLE IF NOT EXISTS etms.users (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    firebase_project_id varchar(100) NOT NULL DEFAULT 'kang-84cdd',
    firebase_tenant_id varchar(128),
    firebase_uid varchar(128) NOT NULL,
    platform_user_id uuid NOT NULL UNIQUE,
    primary_email varchar(320),
    email_verified boolean NOT NULL DEFAULT false,
    display_name varchar(200),
    photo_url text,
    locale varchar(20) NOT NULL DEFAULT 'ko-KR',
    timezone varchar(100) NOT NULL DEFAULT 'Asia/Seoul',
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    mfa_enabled boolean NOT NULL DEFAULT false,
    last_login_at timestamptz,
    locked_at timestamptz,
    lock_reason text,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    CONSTRAINT ck_users_status CHECK (status IN ('INVITED','ACTIVE','LOCKED','SUSPENDED','DELETED')),
    CONSTRAINT ck_users_firebase_scope CHECK (
        firebase_project_id = 'kang-84cdd' AND firebase_tenant_id IS NULL
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_users_firebase_subject
    ON etms.users (
        firebase_project_id,
        COALESCE(firebase_tenant_id, ''),
        firebase_uid
    );

DO $block$
BEGIN
    IF to_regclass('kang.users') IS NULL THEN
        RAISE EXCEPTION 'Required canonical platform table kang.users is missing';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'etms.users'::regclass
          AND conname = 'fk_etms_users_platform_user'
    ) THEN
        ALTER TABLE etms.users
            ADD CONSTRAINT fk_etms_users_platform_user
            FOREIGN KEY (platform_user_id) REFERENCES kang.users(id) ON DELETE RESTRICT;
    END IF;
END;
$block$;

CREATE UNIQUE INDEX IF NOT EXISTS ux_users_email_active
    ON etms.users (lower(primary_email))
    WHERE primary_email IS NOT NULL AND deleted_at IS NULL;

DO $block$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'etms.organization_units'::regclass
          AND conname = 'fk_org_units_manager'
    ) THEN
        ALTER TABLE etms.organization_units
            ADD CONSTRAINT fk_org_units_manager FOREIGN KEY (manager_user_id)
            REFERENCES etms.users(id) ON DELETE SET NULL;
    END IF;
END;
$block$;

CREATE TABLE IF NOT EXISTS etms.user_profiles (
    user_id uuid PRIMARY KEY REFERENCES etms.users(id) ON DELETE CASCADE,
    employee_no varchar(50),
    full_name varchar(200),
    phone_encrypted text,
    phone_search_hash char(64),
    job_title varchar(100),
    department_name varchar(200),
    preferred_language varchar(20) NOT NULL DEFAULT 'ko',
    personal_data_consent_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS etms.auth_identities (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    user_id uuid NOT NULL REFERENCES etms.users(id) ON DELETE CASCADE,
    issuer varchar(500) NOT NULL DEFAULT 'https://securetoken.google.com/kang-84cdd',
    audience varchar(200) NOT NULL DEFAULT 'kang-84cdd',
    firebase_tenant_id varchar(128),
    provider_code varchar(30) NOT NULL,
    provider_subject varchar(255) NOT NULL,
    provider_email varchar(320),
    email_verified boolean NOT NULL DEFAULT false,
    linked_at timestamptz NOT NULL DEFAULT now(),
    last_authenticated_at timestamptz,
    disabled_at timestamptz,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (issuer, audience, provider_code, provider_subject),
    UNIQUE (user_id, provider_code, provider_subject),
    UNIQUE (id, user_id),
    CONSTRAINT ck_auth_identities_provider CHECK (provider_code IN ('password','google.com')),
    CONSTRAINT ck_auth_identities_firebase_scope CHECK (
        issuer = 'https://securetoken.google.com/kang-84cdd'
        AND audience = 'kang-84cdd'
        AND firebase_tenant_id IS NULL
    )
);

COMMENT ON TABLE etms.auth_identities IS
    'Firebase authentication identity links. Password hashes and Firebase/Google tokens must never be stored here.';

CREATE TABLE IF NOT EXISTS etms.user_invitations (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    email varchar(320) NOT NULL,
    invitation_token_hash char(64) NOT NULL UNIQUE,
    invited_by uuid REFERENCES etms.users(id),
    expires_at timestamptz NOT NULL,
    accepted_by uuid REFERENCES etms.users(id),
    accepted_at timestamptz,
    revoked_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_user_invitations_expiry CHECK (expires_at > created_at)
);

CREATE TABLE IF NOT EXISTS etms.tenant_memberships (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES etms.users(id) ON DELETE CASCADE,
    organization_id uuid REFERENCES etms.organizations(id),
    default_org_unit_id uuid REFERENCES etms.organization_units(id),
    employee_no varchar(50),
    membership_type varchar(30) NOT NULL DEFAULT 'EMPLOYEE',
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    valid_from timestamptz NOT NULL DEFAULT now(),
    valid_to timestamptz,
    last_accessed_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, user_id),
    UNIQUE (id, user_id, tenant_id),
    CONSTRAINT ck_memberships_status CHECK (status IN ('INVITED','ACTIVE','SUSPENDED','EXPIRED','REVOKED')),
    CONSTRAINT ck_memberships_dates CHECK (valid_to IS NULL OR valid_to > valid_from)
);

CREATE TABLE IF NOT EXISTS etms.user_groups (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    group_code varchar(50) NOT NULL,
    group_name varchar(150) NOT NULL,
    description text,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, group_code)
);

CREATE TABLE IF NOT EXISTS etms.user_group_members (
    group_id uuid NOT NULL REFERENCES etms.user_groups(id) ON DELETE CASCADE,
    membership_id uuid NOT NULL REFERENCES etms.tenant_memberships(id) ON DELETE CASCADE,
    joined_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (group_id, membership_id)
);

CREATE TABLE IF NOT EXISTS etms.permissions (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    permission_code varchar(150) NOT NULL UNIQUE,
    permission_name varchar(200) NOT NULL,
    module_code varchar(50) NOT NULL,
    action_code varchar(30) NOT NULL,
    description text,
    is_sensitive boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS etms.roles (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid REFERENCES etms.tenants(id) ON DELETE CASCADE,
    role_code varchar(80) NOT NULL,
    role_name varchar(150) NOT NULL,
    description text,
    is_system_role boolean NOT NULL DEFAULT false,
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_roles_tenant_code
    ON etms.roles (COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), role_code);

CREATE TABLE IF NOT EXISTS etms.role_permissions (
    role_id uuid NOT NULL REFERENCES etms.roles(id) ON DELETE CASCADE,
    permission_id uuid NOT NULL REFERENCES etms.permissions(id) ON DELETE CASCADE,
    granted_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (role_id, permission_id)
);

CREATE TABLE IF NOT EXISTS etms.role_assignments (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id) ON DELETE CASCADE,
    membership_id uuid REFERENCES etms.tenant_memberships(id) ON DELETE CASCADE,
    group_id uuid REFERENCES etms.user_groups(id) ON DELETE CASCADE,
    role_id uuid NOT NULL REFERENCES etms.roles(id) ON DELETE CASCADE,
    scope_type varchar(30) NOT NULL DEFAULT 'TENANT',
    scope_id uuid,
    granted_by uuid REFERENCES etms.users(id),
    granted_at timestamptz NOT NULL DEFAULT now(),
    valid_until timestamptz,
    revoked_at timestamptz,
    CONSTRAINT ck_role_assignments_principal CHECK (
        (membership_id IS NOT NULL AND group_id IS NULL) OR
        (membership_id IS NULL AND group_id IS NOT NULL)
    ),
    CONSTRAINT ck_role_assignments_scope CHECK (scope_type IN ('TENANT','ORGANIZATION','ORG_UNIT','LOCATION','PARTNER'))
);

CREATE TABLE IF NOT EXISTS etms.delegations (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    delegator_membership_id uuid NOT NULL REFERENCES etms.tenant_memberships(id),
    delegate_membership_id uuid NOT NULL REFERENCES etms.tenant_memberships(id),
    scope_type varchar(30) NOT NULL DEFAULT 'APPROVAL',
    scope_id uuid,
    valid_from timestamptz NOT NULL,
    valid_to timestamptz NOT NULL,
    reason text,
    revoked_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_delegations_users CHECK (delegator_membership_id <> delegate_membership_id),
    CONSTRAINT ck_delegations_dates CHECK (valid_to > valid_from)
);

CREATE TABLE IF NOT EXISTS etms.auth_sessions (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    user_id uuid NOT NULL REFERENCES etms.users(id) ON DELETE CASCADE,
    auth_identity_id uuid NOT NULL REFERENCES etms.auth_identities(id) ON DELETE RESTRICT,
    active_tenant_id uuid NOT NULL REFERENCES etms.tenants(id) ON DELETE CASCADE,
    active_membership_id uuid NOT NULL REFERENCES etms.tenant_memberships(id) ON DELETE CASCADE,
    firebase_session_id_hash char(64) NOT NULL UNIQUE,
    firebase_auth_time timestamptz,
    assurance_level varchar(30) NOT NULL DEFAULT 'SINGLE_FACTOR',
    issued_at timestamptz NOT NULL,
    expires_at timestamptz NOT NULL,
    last_seen_at timestamptz,
    ip_address inet,
    user_agent text,
    session_status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    revoked_at timestamptz,
    revoke_reason text,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (id, user_id, active_tenant_id, active_membership_id),
    FOREIGN KEY (auth_identity_id, user_id)
        REFERENCES etms.auth_identities(id, user_id) ON DELETE RESTRICT,
    FOREIGN KEY (active_membership_id, user_id, active_tenant_id)
        REFERENCES etms.tenant_memberships(id, user_id, tenant_id) ON DELETE CASCADE,
    CONSTRAINT ck_auth_sessions_dates CHECK (expires_at > issued_at),
    CONSTRAINT ck_auth_sessions_assurance CHECK (assurance_level IN ('SINGLE_FACTOR','MULTI_FACTOR','HARDWARE_BACKED')),
    CONSTRAINT ck_auth_sessions_status CHECK (session_status IN ('ACTIVE','EXPIRED','REVOKED')),
    CONSTRAINT ck_auth_sessions_status_projection CHECK (
        (session_status = 'ACTIVE' AND revoked_at IS NULL)
        OR (session_status = 'EXPIRED' AND revoked_at IS NULL)
        OR (session_status = 'REVOKED' AND revoked_at IS NOT NULL)
    ),
    CONSTRAINT ck_auth_sessions_hash CHECK (firebase_session_id_hash ~ '^[0-9a-f]{64}$')
);

COMMENT ON COLUMN etms.auth_sessions.firebase_session_id_hash IS
    'One-way hash of a server-side session identifier; never store Firebase ID or refresh tokens.';

CREATE TABLE IF NOT EXISTS etms.login_events (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid REFERENCES etms.tenants(id),
    user_id uuid REFERENCES etms.users(id) ON DELETE SET NULL,
    firebase_uid varchar(128),
    provider_code varchar(30),
    success boolean NOT NULL,
    failure_code varchar(80),
    failure_detail_masked text,
    ip_address inet,
    user_agent text,
    correlation_id varchar(100),
    occurred_at timestamptz NOT NULL DEFAULT now(),
    received_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS etms.user_devices (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    user_id uuid NOT NULL REFERENCES etms.users(id) ON DELETE CASCADE,
    device_fingerprint_hash char(64),
    platform varchar(30) NOT NULL,
    device_name varchar(150),
    app_version varchar(50),
    push_token_encrypted text,
    first_seen_at timestamptz NOT NULL DEFAULT now(),
    last_seen_at timestamptz,
    trusted_at timestamptz,
    revoked_at timestamptz,
    UNIQUE (user_id, device_fingerprint_hash)
);

CREATE TABLE IF NOT EXISTS etms.terms_versions (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    terms_code varchar(80) NOT NULL,
    version varchar(30) NOT NULL,
    title varchar(300) NOT NULL,
    content_uri text NOT NULL,
    content_sha256 char(64) NOT NULL,
    required boolean NOT NULL DEFAULT true,
    effective_at timestamptz NOT NULL,
    retired_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (terms_code, version)
);

CREATE TABLE IF NOT EXISTS etms.user_terms_agreements (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    user_id uuid NOT NULL REFERENCES etms.users(id) ON DELETE CASCADE,
    terms_version_id uuid NOT NULL REFERENCES etms.terms_versions(id),
    agreed boolean NOT NULL,
    ip_address inet,
    user_agent text,
    agreed_at timestamptz NOT NULL DEFAULT now(),
    withdrawn_at timestamptz,
    UNIQUE (user_id, terms_version_id)
);

CREATE TABLE IF NOT EXISTS etms.api_clients (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    client_code varchar(80) NOT NULL,
    client_name varchar(200) NOT NULL,
    client_id varchar(150) NOT NULL UNIQUE,
    secret_hash char(64),
    auth_method varchar(30) NOT NULL DEFAULT 'PRIVATE_KEY_JWT',
    allowed_cidrs cidr[],
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    expires_at timestamptz,
    last_used_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, client_code),
    CONSTRAINT ck_api_clients_auth CHECK (auth_method IN ('PRIVATE_KEY_JWT','MTLS','CLIENT_SECRET_HASH'))
);

CREATE TABLE IF NOT EXISTS etms.api_client_permissions (
    api_client_id uuid NOT NULL REFERENCES etms.api_clients(id) ON DELETE CASCADE,
    permission_id uuid NOT NULL REFERENCES etms.permissions(id) ON DELETE CASCADE,
    granted_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (api_client_id, permission_id)
);

CREATE TABLE IF NOT EXISTS etms.code_sets (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid REFERENCES etms.tenants(id) ON DELETE CASCADE,
    code_set varchar(80) NOT NULL,
    code_set_name varchar(200) NOT NULL,
    description text,
    is_system boolean NOT NULL DEFAULT false,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_code_sets_scope
    ON etms.code_sets (COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), code_set);

CREATE TABLE IF NOT EXISTS etms.code_values (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    code_set_id uuid NOT NULL REFERENCES etms.code_sets(id) ON DELETE CASCADE,
    code varchar(80) NOT NULL,
    code_name varchar(200) NOT NULL,
    description text,
    sort_order integer NOT NULL DEFAULT 0,
    parent_code_value_id uuid REFERENCES etms.code_values(id),
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    valid_from timestamptz,
    valid_to timestamptz,
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (code_set_id, code),
    CONSTRAINT ck_code_values_dates CHECK (valid_to IS NULL OR valid_from IS NULL OR valid_to > valid_from)
);

CREATE TABLE IF NOT EXISTS etms.number_sequences (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id) ON DELETE CASCADE,
    sequence_code varchar(80) NOT NULL,
    prefix_pattern varchar(100) NOT NULL DEFAULT '',
    date_pattern varchar(30),
    current_value bigint NOT NULL DEFAULT 0,
    increment_by integer NOT NULL DEFAULT 1,
    padding_length integer NOT NULL DEFAULT 8,
    reset_period varchar(20) NOT NULL DEFAULT 'NEVER',
    last_reset_date date,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, sequence_code),
    CONSTRAINT ck_number_sequences_positive CHECK (increment_by > 0 AND padding_length BETWEEN 1 AND 30),
    CONSTRAINT ck_number_sequences_reset CHECK (reset_period IN ('NEVER','DAILY','MONTHLY','YEARLY'))
);

CREATE TABLE IF NOT EXISTS etms.business_calendars (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    calendar_code varchar(50) NOT NULL,
    calendar_name varchar(200) NOT NULL,
    timezone varchar(100) NOT NULL DEFAULT 'Asia/Seoul',
    week_start smallint NOT NULL DEFAULT 1,
    working_weekdays smallint[] NOT NULL DEFAULT ARRAY[1,2,3,4,5]::smallint[],
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, calendar_code),
    CONSTRAINT ck_business_calendars_week CHECK (week_start BETWEEN 0 AND 6)
);

CREATE TABLE IF NOT EXISTS etms.calendar_dates (
    calendar_id uuid NOT NULL REFERENCES etms.business_calendars(id) ON DELETE CASCADE,
    calendar_date date NOT NULL,
    day_type varchar(20) NOT NULL,
    working_from time,
    working_to time,
    description varchar(300),
    PRIMARY KEY (calendar_id, calendar_date),
    CONSTRAINT ck_calendar_dates_type CHECK (day_type IN ('WORKING','HOLIDAY','PARTIAL','BLACKOUT')),
    CONSTRAINT ck_calendar_dates_time CHECK (working_to IS NULL OR working_from IS NULL OR working_to > working_from)
);

CREATE TABLE IF NOT EXISTS etms.files (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    storage_provider varchar(30) NOT NULL,
    storage_bucket varchar(200) NOT NULL,
    object_key text NOT NULL,
    original_file_name varchar(500) NOT NULL,
    media_type varchar(200),
    byte_size bigint NOT NULL,
    sha256 char(64) NOT NULL,
    encryption_key_ref varchar(300),
    malware_scan_status varchar(20) NOT NULL DEFAULT 'PENDING',
    retention_until date,
    legal_hold boolean NOT NULL DEFAULT false,
    uploaded_by uuid REFERENCES etms.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    UNIQUE (tenant_id, storage_provider, storage_bucket, object_key),
    CONSTRAINT ck_files_size CHECK (byte_size >= 0),
    CONSTRAINT ck_files_scan CHECK (malware_scan_status IN ('PENDING','CLEAN','INFECTED','FAILED'))
);

CREATE TABLE IF NOT EXISTS etms.entity_files (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    entity_type varchar(80) NOT NULL,
    entity_id uuid NOT NULL,
    file_id uuid NOT NULL REFERENCES etms.files(id),
    document_type varchar(80),
    revision_no integer NOT NULL DEFAULT 1,
    is_primary boolean NOT NULL DEFAULT false,
    effective_at timestamptz,
    expires_at timestamptz,
    created_by uuid REFERENCES etms.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, entity_type, entity_id, file_id, revision_no)
);

CREATE TABLE IF NOT EXISTS etms.entity_notes (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    entity_type varchar(80) NOT NULL,
    entity_id uuid NOT NULL,
    note_type varchar(30) NOT NULL DEFAULT 'INTERNAL',
    note_text text NOT NULL,
    visibility varchar(30) NOT NULL DEFAULT 'INTERNAL',
    created_by uuid REFERENCES etms.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    CONSTRAINT ck_entity_notes_visibility CHECK (visibility IN ('INTERNAL','CUSTOMER','CARRIER','PUBLIC'))
);

CREATE TABLE IF NOT EXISTS etms.custom_field_definitions (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    entity_type varchar(80) NOT NULL,
    field_code varchar(80) NOT NULL,
    field_name varchar(200) NOT NULL,
    data_type varchar(20) NOT NULL,
    is_required boolean NOT NULL DEFAULT false,
    validation_rule jsonb NOT NULL DEFAULT '{}'::jsonb,
    sort_order integer NOT NULL DEFAULT 0,
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, entity_type, field_code),
    CONSTRAINT ck_custom_field_type CHECK (data_type IN ('TEXT','NUMBER','BOOLEAN','DATE','TIMESTAMP','CODE','JSON'))
);

CREATE TABLE IF NOT EXISTS etms.custom_field_values (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    definition_id uuid NOT NULL REFERENCES etms.custom_field_definitions(id) ON DELETE CASCADE,
    entity_id uuid NOT NULL,
    value_json jsonb NOT NULL,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (definition_id, entity_id)
);

CREATE TABLE IF NOT EXISTS etms.idempotency_keys (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    idempotency_key varchar(200) NOT NULL,
    operation_code varchar(100) NOT NULL,
    request_hash char(64) NOT NULL,
    response_status integer,
    response_body jsonb,
    resource_type varchar(80),
    resource_id uuid,
    locked_until timestamptz,
    expires_at timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    completed_at timestamptz,
    UNIQUE (tenant_id, operation_code, idempotency_key)
);

CREATE TABLE IF NOT EXISTS etms.outbox_events (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    aggregate_type varchar(80) NOT NULL,
    aggregate_id uuid NOT NULL,
    event_type varchar(120) NOT NULL,
    event_version integer NOT NULL DEFAULT 1,
    payload jsonb NOT NULL,
    correlation_id varchar(100),
    occurred_at timestamptz NOT NULL DEFAULT now(),
    available_at timestamptz NOT NULL DEFAULT now(),
    published_at timestamptz,
    retry_count integer NOT NULL DEFAULT 0,
    last_error_masked text,
    CONSTRAINT ck_outbox_retry CHECK (retry_count >= 0)
);

CREATE TABLE IF NOT EXISTS etms.external_systems (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    system_code varchar(80) NOT NULL,
    system_name varchar(200) NOT NULL,
    system_type varchar(40) NOT NULL,
    direction varchar(20) NOT NULL DEFAULT 'BIDIRECTIONAL',
    endpoint_uri text,
    credential_secret_ref varchar(300),
    config jsonb NOT NULL DEFAULT '{}'::jsonb,
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, system_code),
    CONSTRAINT ck_external_systems_direction CHECK (direction IN ('INBOUND','OUTBOUND','BIDIRECTIONAL'))
);

CREATE TABLE IF NOT EXISTS etms.external_id_mappings (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    external_system_id uuid NOT NULL REFERENCES etms.external_systems(id),
    entity_type varchar(80) NOT NULL,
    internal_id uuid NOT NULL,
    external_id varchar(300) NOT NULL,
    external_version varchar(100),
    last_synced_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (external_system_id, entity_type, external_id),
    UNIQUE (external_system_id, entity_type, internal_id)
);

CREATE TABLE IF NOT EXISTS etms.integration_messages (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    external_system_id uuid REFERENCES etms.external_systems(id),
    direction varchar(10) NOT NULL,
    message_type varchar(100) NOT NULL,
    external_message_id varchar(300),
    correlation_id varchar(100),
    payload_uri text,
    payload_sha256 char(64),
    status varchar(20) NOT NULL DEFAULT 'RECEIVED',
    attempt_count integer NOT NULL DEFAULT 0,
    occurred_at timestamptz,
    received_at timestamptz NOT NULL DEFAULT now(),
    processed_at timestamptz,
    error_code varchar(100),
    error_detail_masked text,
    UNIQUE (external_system_id, direction, external_message_id),
    CONSTRAINT ck_integration_messages_direction CHECK (direction IN ('IN','OUT')),
    CONSTRAINT ck_integration_messages_attempt CHECK (attempt_count >= 0)
);

CREATE TABLE IF NOT EXISTS etms.audit_events (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid REFERENCES etms.tenants(id),
    actor_user_id uuid REFERENCES etms.users(id) ON DELETE SET NULL,
    actor_api_client_id uuid REFERENCES etms.api_clients(id) ON DELETE SET NULL,
    action_code varchar(100) NOT NULL,
    entity_type varchar(80),
    entity_id uuid,
    before_data_masked jsonb,
    after_data_masked jsonb,
    reason text,
    ip_address inet,
    user_agent text,
    correlation_id varchar(100),
    occurred_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_audit_actor CHECK (NOT (actor_user_id IS NOT NULL AND actor_api_client_id IS NOT NULL))
);

CREATE TABLE IF NOT EXISTS etms.data_retention_policies (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid REFERENCES etms.tenants(id) ON DELETE CASCADE,
    entity_type varchar(80) NOT NULL,
    retention_days integer NOT NULL,
    anonymize_after_days integer,
    purge_strategy varchar(20) NOT NULL DEFAULT 'DELETE',
    legal_basis varchar(300),
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_retention_days CHECK (retention_days > 0 AND (anonymize_after_days IS NULL OR anonymize_after_days > 0)),
    CONSTRAINT ck_retention_strategy CHECK (purge_strategy IN ('DELETE','ANONYMIZE','ARCHIVE'))
);

CREATE TABLE IF NOT EXISTS etms.legal_holds (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    hold_no varchar(80) NOT NULL,
    entity_type varchar(80),
    entity_id uuid,
    reason text NOT NULL,
    effective_at timestamptz NOT NULL,
    released_at timestamptz,
    created_by uuid REFERENCES etms.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, hold_no),
    CONSTRAINT ck_legal_holds_dates CHECK (released_at IS NULL OR released_at >= effective_at)
);
