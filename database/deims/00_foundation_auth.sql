-- DEIMS enterprise WMS schema - foundation, tenancy, Firebase IAM, and platform services.
-- PostgreSQL 11 compatible. Executed by scripts/apply_deims_schema.py in one transaction.

CREATE SCHEMA IF NOT EXISTS deims;

CREATE OR REPLACE FUNCTION deims.generate_uuid()
RETURNS uuid
LANGUAGE sql
VOLATILE
AS $function$
    SELECT md5(
        random()::text || clock_timestamp()::text || txid_current()::text ||
        pg_backend_pid()::text
    )::uuid;
$function$;

-- JSON configuration and masked-summary columns must never become an alternate
-- credential store.  Normalize key spelling and walk nested arrays/objects so
-- camelCase, kebab-case, and nested secret fields cannot bypass a shallow ?|
-- check.  Secret *references* remain permitted because they are opaque handles.
CREATE OR REPLACE FUNCTION deims.jsonb_contains_forbidden_secret_key(p_value jsonb)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
STRICT
PARALLEL SAFE
AS $function$
DECLARE
    object_entry record;
    array_value jsonb;
    normalized_key text;
BEGIN
    IF jsonb_typeof(p_value) = 'object' THEN
        FOR object_entry IN SELECT key, value FROM jsonb_each(p_value)
        LOOP
            normalized_key := lower(regexp_replace(object_entry.key, '[^a-zA-Z0-9]', '', 'g'));
            IF normalized_key = ANY (ARRAY[
                'password','passwordhash','hashedpassword','rawpassword',
                'secret','secretkey','clientsecret','accesstoken','refreshtoken',
                'idtoken','firebasetoken','googletoken','sessiontoken','sessionhandle',
                'apikey','privatekey','bearertoken','authorization','authorizationheader',
                'credential','credentials','personalcustomscode',
                'residentregistrationno','passportno','rawnonce'
            ]::text[]) THEN
                RETURN true;
            END IF;
            IF jsonb_typeof(object_entry.value) IN ('object','array')
               AND deims.jsonb_contains_forbidden_secret_key(object_entry.value) THEN
                RETURN true;
            END IF;
        END LOOP;
    ELSIF jsonb_typeof(p_value) = 'array' THEN
        FOR array_value IN SELECT value FROM jsonb_array_elements(p_value)
        LOOP
            IF jsonb_typeof(array_value) IN ('object','array')
               AND deims.jsonb_contains_forbidden_secret_key(array_value) THEN
                RETURN true;
            END IF;
        END LOOP;
    END IF;
    RETURN false;
END;
$function$;

CREATE OR REPLACE FUNCTION deims.touch_row()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    NEW.updated_at := now();
    NEW.row_version := OLD.row_version + 1;
    RETURN NEW;
END;
$function$;

CREATE TABLE IF NOT EXISTS deims.schema_migrations (
    version varchar(50) PRIMARY KEY,
    description text NOT NULL,
    checksum_sha256 char(64) NOT NULL,
    catalog_checksum_sha256 char(64) NOT NULL,
    baseline_seed_checksum_sha256 char(64) NOT NULL,
    applied_at timestamptz NOT NULL DEFAULT now(),
    applied_by text NOT NULL DEFAULT current_user,
    CONSTRAINT ck_schema_migrations_checksum_sha256 CHECK (
        checksum_sha256 ~ '^[0-9A-Fa-f]{64}$'
    ),
    CONSTRAINT ck_schema_migrations_catalog_checksum_sha256 CHECK (
        catalog_checksum_sha256 ~ '^[0-9A-Fa-f]{64}$'
    ),
    CONSTRAINT ck_schema_migrations_seed_checksum_sha256 CHECK (
        baseline_seed_checksum_sha256 ~ '^[0-9A-Fa-f]{64}$'
    )
);

CREATE TABLE IF NOT EXISTS deims.tenants (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
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

CREATE TABLE IF NOT EXISTS deims.tenant_settings (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id) ON DELETE CASCADE,
    setting_key varchar(150) NOT NULL,
    setting_value jsonb,
    secret_reference varchar(500),
    value_class varchar(20) NOT NULL DEFAULT 'INTERNAL',
    description text,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, setting_key),
    CONSTRAINT ck_tenant_settings_value_class CHECK (
        value_class IN ('PUBLIC','INTERNAL','CONFIDENTIAL','SECRET_REFERENCE')
    ),
    CONSTRAINT ck_tenant_settings_value_source CHECK (
        (value_class = 'SECRET_REFERENCE' AND setting_value IS NULL AND secret_reference IS NOT NULL) OR
        (value_class <> 'SECRET_REFERENCE' AND setting_value IS NOT NULL AND secret_reference IS NULL)
    ),
    CONSTRAINT ck_tenant_settings_no_inline_secrets CHECK (
        setting_value IS NULL OR NOT deims.jsonb_contains_forbidden_secret_key(setting_value)
    )
);

COMMENT ON TABLE deims.tenant_settings IS
    'Tenant configuration. Secret values stay in an external secret manager; this table stores only an opaque secret_reference.';

CREATE TABLE IF NOT EXISTS deims.organizations (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
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

CREATE TABLE IF NOT EXISTS deims.organization_units (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    organization_id uuid NOT NULL REFERENCES deims.organizations(id),
    parent_unit_id uuid REFERENCES deims.organization_units(id),
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

CREATE TABLE IF NOT EXISTS deims.users (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
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
    CONSTRAINT ck_users_status CHECK (status IN ('INVITED','ACTIVE','LOCKED','SUSPENDED','DELETED'))
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_users_firebase_subject
    ON deims.users (
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
        WHERE conrelid = 'deims.users'::regclass
          AND conname = 'fk_deims_users_platform_user'
    ) THEN
        ALTER TABLE deims.users
            ADD CONSTRAINT fk_deims_users_platform_user
            FOREIGN KEY (platform_user_id) REFERENCES kang.users(id) ON DELETE RESTRICT;
    END IF;
END;
$block$;

CREATE INDEX IF NOT EXISTS ix_users_email_search
    ON deims.users (lower(primary_email))
    WHERE primary_email IS NOT NULL AND deleted_at IS NULL;

COMMENT ON TABLE deims.users IS
    'DEIMS principals mapped to canonical kang.users and Firebase token subjects. Tenant access is granted only through tenant_memberships.';
COMMENT ON COLUMN deims.users.firebase_uid IS
    'Canonical Firebase token subject. The unique identity key is firebase_project_id, COALESCE(firebase_tenant_id, ''''), firebase_uid.';
COMMENT ON COLUMN deims.users.primary_email IS
    'Mutable display/search attribute only. Email equality must never trigger automatic account creation, identity matching, or account merging.';
COMMENT ON COLUMN deims.users.platform_user_id IS
    'Required canonical platform principal in kang.users; DEIMS must not maintain an independent password database.';

CREATE OR REPLACE FUNCTION deims.validate_user_platform_subject()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, deims
AS $function$
BEGIN
    IF NOT EXISTS (
        SELECT 1
          FROM kang.users platform_user
         WHERE platform_user.id = NEW.platform_user_id
           AND platform_user.firebase_uid = NEW.firebase_uid
    ) THEN
        RAISE EXCEPTION 'DEIMS platform_user_id and Firebase uid must identify the same canonical kang.users row'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION deims.validate_user_platform_subject() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_validate_user_platform_subject ON deims.users;
CREATE TRIGGER trg_validate_user_platform_subject
    BEFORE INSERT OR UPDATE OF platform_user_id, firebase_uid ON deims.users
    FOR EACH ROW EXECUTE PROCEDURE deims.validate_user_platform_subject();

CREATE OR REPLACE FUNCTION deims.prevent_user_identity_rekey()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    IF OLD.firebase_project_id IS DISTINCT FROM NEW.firebase_project_id
       OR OLD.firebase_tenant_id IS DISTINCT FROM NEW.firebase_tenant_id
       OR OLD.firebase_uid IS DISTINCT FROM NEW.firebase_uid
       OR OLD.platform_user_id IS DISTINCT FROM NEW.platform_user_id THEN
        RAISE EXCEPTION
            'DEIMS canonical user identity keys are immutable; use an explicit audited account-link/migration workflow';
    END IF;
    RETURN NEW;
END;
$function$;

DO $block$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_trigger
        WHERE tgrelid = 'deims.users'::regclass
          AND tgname = 'trg_prevent_user_identity_rekey'
          AND NOT tgisinternal
    ) THEN
        CREATE TRIGGER trg_prevent_user_identity_rekey
        BEFORE UPDATE OF firebase_project_id, firebase_tenant_id, firebase_uid, platform_user_id
        ON deims.users
        FOR EACH ROW EXECUTE PROCEDURE deims.prevent_user_identity_rekey();
    END IF;
END;
$block$;

DO $block$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'deims.organization_units'::regclass
          AND conname = 'fk_org_units_manager'
    ) THEN
        ALTER TABLE deims.organization_units
            ADD CONSTRAINT fk_org_units_manager FOREIGN KEY (manager_user_id)
            REFERENCES deims.users(id) ON DELETE SET NULL;
    END IF;
END;
$block$;

CREATE TABLE IF NOT EXISTS deims.user_profiles (
    user_id uuid PRIMARY KEY REFERENCES deims.users(id) ON DELETE CASCADE,
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
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_user_profiles_phone_hash CHECK (
        phone_search_hash IS NULL OR phone_search_hash ~ '^[0-9A-Fa-f]{64}$'
    )
);

COMMENT ON COLUMN deims.user_profiles.phone_encrypted IS
    'Encrypted personal data only; the encryption key must remain in an external KMS/secret manager.';

CREATE TABLE IF NOT EXISTS deims.auth_identities (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    user_id uuid NOT NULL REFERENCES deims.users(id) ON DELETE CASCADE,
    firebase_project_id varchar(100) NOT NULL DEFAULT 'kang-84cdd',
    firebase_tenant_id varchar(128),
    firebase_uid varchar(128) NOT NULL,
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
    UNIQUE (user_id, provider_code, provider_subject),
    CONSTRAINT ck_auth_identities_provider CHECK (provider_code IN ('password','google.com')),
    CONSTRAINT ck_auth_identities_subjects CHECK (
        btrim(firebase_uid) <> '' AND btrim(provider_subject) <> ''
    ),
    CONSTRAINT ck_auth_identities_no_secret_metadata CHECK (
        NOT deims.jsonb_contains_forbidden_secret_key(metadata)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_auth_identities_provider_subject
    ON deims.auth_identities (
        firebase_project_id,
        COALESCE(firebase_tenant_id, ''),
        provider_code,
        provider_subject
    );

CREATE UNIQUE INDEX IF NOT EXISTS ux_auth_identities_active_user_provider
    ON deims.auth_identities (user_id, provider_code)
    WHERE disabled_at IS NULL;

COMMENT ON TABLE deims.auth_identities IS
    'Links Firebase email/password or Google provider subjects to one Firebase account. Password hashes and Firebase/Google ID, access, refresh, or session tokens must never be stored here.';
COMMENT ON COLUMN deims.auth_identities.firebase_uid IS
    'Firebase account subject from the verified ID token; deliberately separate from the provider-specific subject.';
COMMENT ON COLUMN deims.auth_identities.provider_subject IS
    'Stable provider subject verified by Firebase. For password auth, use the verified provider-data UID or Firebase UID when no separate subject exists; never substitute or match this key using an email address.';
COMMENT ON COLUMN deims.auth_identities.provider_email IS
    'Mutable display/search attribute only; it is not an identity key and must never drive automatic account linking or merging.';
COMMENT ON COLUMN deims.auth_identities.metadata IS
    'Non-secret provider metadata only. Password material and raw Firebase/Google tokens are prohibited.';

CREATE OR REPLACE FUNCTION deims.validate_auth_identity_owner()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    owner_row deims.users%ROWTYPE;
BEGIN
    IF TG_OP = 'UPDATE' AND TG_TABLE_NAME = 'auth_identities' AND (
        OLD.user_id IS DISTINCT FROM NEW.user_id
        OR OLD.firebase_project_id IS DISTINCT FROM NEW.firebase_project_id
        OR OLD.firebase_tenant_id IS DISTINCT FROM NEW.firebase_tenant_id
        OR OLD.firebase_uid IS DISTINCT FROM NEW.firebase_uid
        OR OLD.provider_code IS DISTINCT FROM NEW.provider_code
        OR OLD.provider_subject IS DISTINCT FROM NEW.provider_subject
    ) THEN
        RAISE EXCEPTION
            'DEIMS authentication identity keys are immutable; disable the identity and complete a new explicit link request';
    END IF;

    IF TG_OP = 'UPDATE' AND TG_TABLE_NAME = 'account_link_requests' AND (
        OLD.user_id IS DISTINCT FROM NEW.user_id
        OR OLD.firebase_project_id IS DISTINCT FROM NEW.firebase_project_id
        OR OLD.firebase_tenant_id IS DISTINCT FROM NEW.firebase_tenant_id
        OR OLD.firebase_uid IS DISTINCT FROM NEW.firebase_uid
        OR OLD.provider_code IS DISTINCT FROM NEW.provider_code
        OR OLD.provider_subject IS DISTINCT FROM NEW.provider_subject
    ) THEN
        RAISE EXCEPTION
            'DEIMS account-link identity keys are immutable; cancel the request and create a new one';
    END IF;

    SELECT * INTO owner_row
      FROM deims.users
     WHERE id = NEW.user_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'DEIMS auth identity user does not exist';
    END IF;
    IF owner_row.firebase_project_id IS DISTINCT FROM NEW.firebase_project_id
       OR owner_row.firebase_tenant_id IS DISTINCT FROM NEW.firebase_tenant_id
       OR owner_row.firebase_uid IS DISTINCT FROM NEW.firebase_uid THEN
        RAISE EXCEPTION 'DEIMS auth identity Firebase subject must match its user';
    END IF;
    RETURN NEW;
END;
$function$;

DO $block$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_trigger
        WHERE tgrelid = 'deims.auth_identities'::regclass
          AND tgname = 'trg_validate_auth_identity_owner'
          AND NOT tgisinternal
    ) THEN
        CREATE TRIGGER trg_validate_auth_identity_owner
        BEFORE INSERT OR UPDATE OF user_id, firebase_project_id, firebase_tenant_id, firebase_uid, provider_code, provider_subject
        ON deims.auth_identities
        FOR EACH ROW EXECUTE PROCEDURE deims.validate_auth_identity_owner();
    END IF;
END;
$block$;

CREATE TABLE IF NOT EXISTS deims.account_link_requests (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    user_id uuid NOT NULL REFERENCES deims.users(id) ON DELETE CASCADE,
    firebase_project_id varchar(100) NOT NULL,
    firebase_tenant_id varchar(128),
    firebase_uid varchar(128) NOT NULL,
    provider_code varchar(30) NOT NULL,
    provider_subject varchar(255) NOT NULL,
    provider_email varchar(320),
    request_nonce_hash char(64) NOT NULL UNIQUE,
    status varchar(20) NOT NULL DEFAULT 'PENDING',
    verification_method varchar(30) NOT NULL,
    requested_by uuid REFERENCES deims.users(id),
    requested_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL,
    decided_by uuid REFERENCES deims.users(id),
    decided_at timestamptz,
    decision_reason text,
    completed_identity_id uuid REFERENCES deims.auth_identities(id) ON DELETE SET NULL,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_account_link_provider CHECK (provider_code IN ('password','google.com')),
    CONSTRAINT ck_account_link_status CHECK (
        status IN ('PENDING','VERIFIED','APPROVED','REJECTED','EXPIRED','CANCELLED','COMPLETED')
    ),
    CONSTRAINT ck_account_link_verification CHECK (
        verification_method IN ('RECENT_REAUTH','ADMIN_APPROVAL','MFA_CHALLENGE','RECOVERY_CODE')
    ),
    CONSTRAINT ck_account_link_expiry CHECK (expires_at > requested_at),
    CONSTRAINT ck_account_link_nonce_hash CHECK (request_nonce_hash ~ '^[0-9A-Fa-f]{64}$'),
    CONSTRAINT ck_account_link_subjects CHECK (
        btrim(firebase_uid) <> '' AND btrim(provider_subject) <> ''
    ),
    CONSTRAINT ck_account_link_completion CHECK (
        (status = 'COMPLETED' AND completed_identity_id IS NOT NULL) OR
        (status <> 'COMPLETED' AND completed_identity_id IS NULL)
    ),
    CONSTRAINT ck_account_link_decision CHECK (
        status NOT IN ('APPROVED','REJECTED','COMPLETED') OR decided_at IS NOT NULL
    )
);

CREATE INDEX IF NOT EXISTS ix_account_link_requests_user_status
    ON deims.account_link_requests (user_id, status, requested_at DESC);

COMMENT ON TABLE deims.account_link_requests IS
    'Explicit identity-link workflow. Matching emails never creates, approves, or completes a link; the nonce is stored only as a one-way hash.';
COMMENT ON COLUMN deims.account_link_requests.provider_email IS
    'Display/search evidence only, never an identity or merge key.';

DO $block$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_trigger
        WHERE tgrelid = 'deims.account_link_requests'::regclass
          AND tgname = 'trg_validate_account_link_owner'
          AND NOT tgisinternal
    ) THEN
CREATE TRIGGER trg_validate_account_link_owner
        BEFORE INSERT OR UPDATE OF user_id, firebase_project_id, firebase_tenant_id, firebase_uid, provider_code, provider_subject
        ON deims.account_link_requests
        FOR EACH ROW EXECUTE PROCEDURE deims.validate_auth_identity_owner();
    END IF;
END;
$block$;

CREATE OR REPLACE FUNCTION deims.validate_account_link_completion()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    identity_row deims.auth_identities%ROWTYPE;
BEGIN
    IF NEW.completed_identity_id IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT * INTO identity_row
      FROM deims.auth_identities
     WHERE id = NEW.completed_identity_id;

    IF NOT FOUND OR identity_row.disabled_at IS NOT NULL THEN
        RAISE EXCEPTION 'Completed account link must reference an active identity';
    END IF;
    IF identity_row.user_id IS DISTINCT FROM NEW.user_id
       OR identity_row.firebase_project_id IS DISTINCT FROM NEW.firebase_project_id
       OR identity_row.firebase_tenant_id IS DISTINCT FROM NEW.firebase_tenant_id
       OR identity_row.firebase_uid IS DISTINCT FROM NEW.firebase_uid
       OR identity_row.provider_code IS DISTINCT FROM NEW.provider_code
       OR identity_row.provider_subject IS DISTINCT FROM NEW.provider_subject THEN
        RAISE EXCEPTION 'Completed identity does not match the approved account link request';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION deims.validate_account_link_transition()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    IF NEW.status = OLD.status THEN
        RETURN NEW;
    END IF;

    IF NOT (
        (OLD.status = 'PENDING' AND NEW.status IN (
            'VERIFIED','APPROVED','REJECTED','EXPIRED','CANCELLED'
        ))
        OR (OLD.status = 'VERIFIED' AND NEW.status IN (
            'APPROVED','REJECTED','EXPIRED','CANCELLED'
        ))
        OR (OLD.status = 'APPROVED' AND NEW.status IN (
            'COMPLETED','EXPIRED','CANCELLED'
        ))
    ) THEN
        RAISE EXCEPTION 'Invalid DEIMS account-link status transition: % -> %',
            OLD.status, NEW.status;
    END IF;
    RETURN NEW;
END;
$function$;

DO $block$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_trigger
        WHERE tgrelid = 'deims.account_link_requests'::regclass
          AND tgname = 'trg_validate_account_link_completion'
          AND NOT tgisinternal
    ) THEN
        CREATE TRIGGER trg_validate_account_link_completion
        BEFORE INSERT OR UPDATE OF completed_identity_id, status
        ON deims.account_link_requests
        FOR EACH ROW EXECUTE PROCEDURE deims.validate_account_link_completion();
    END IF;
END;
$block$;

DO $block$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_trigger
        WHERE tgrelid = 'deims.account_link_requests'::regclass
          AND tgname = 'trg_validate_account_link_transition'
          AND NOT tgisinternal
    ) THEN
        CREATE TRIGGER trg_validate_account_link_transition
        BEFORE UPDATE OF status
        ON deims.account_link_requests
        FOR EACH ROW EXECUTE PROCEDURE deims.validate_account_link_transition();
    END IF;
END;
$block$;

CREATE TABLE IF NOT EXISTS deims.account_link_events (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    request_id uuid NOT NULL REFERENCES deims.account_link_requests(id) ON DELETE RESTRICT,
    event_sequence integer NOT NULL,
    event_type varchar(40) NOT NULL,
    from_status varchar(20),
    to_status varchar(20),
    actor_user_id uuid REFERENCES deims.users(id) ON DELETE SET NULL,
    evidence_masked jsonb NOT NULL DEFAULT '{}'::jsonb,
    ip_address inet,
    user_agent text,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (request_id, event_sequence),
    CONSTRAINT ck_account_link_event_sequence CHECK (event_sequence > 0),
    CONSTRAINT ck_account_link_event_no_secrets CHECK (
        NOT deims.jsonb_contains_forbidden_secret_key(evidence_masked)
    )
);

COMMENT ON TABLE deims.account_link_events IS
    'Append-oriented audit trail for explicit account-link decisions; raw credentials, tokens, and nonces are prohibited.';

CREATE TABLE IF NOT EXISTS deims.user_invitations (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    email varchar(320) NOT NULL,
    invitation_token_hash char(64) NOT NULL UNIQUE,
    invited_by uuid REFERENCES deims.users(id),
    expires_at timestamptz NOT NULL,
    accepted_by uuid REFERENCES deims.users(id),
    accepted_at timestamptz,
    revoked_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_user_invitations_expiry CHECK (expires_at > created_at),
    CONSTRAINT ck_user_invitations_token_hash CHECK (
        invitation_token_hash ~ '^[0-9A-Fa-f]{64}$'
    )
);

COMMENT ON TABLE deims.user_invitations IS
    'Tenant invitation workflow. Only a one-way token hash is stored; invitation email is a destination/display value and never an automatic account-merge key.';

CREATE TABLE IF NOT EXISTS deims.tenant_memberships (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES deims.users(id) ON DELETE CASCADE,
    organization_id uuid REFERENCES deims.organizations(id),
    default_org_unit_id uuid REFERENCES deims.organization_units(id),
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
    UNIQUE (id, user_id),
    CONSTRAINT ck_memberships_status CHECK (status IN ('INVITED','ACTIVE','SUSPENDED','EXPIRED','REVOKED')),
    CONSTRAINT ck_memberships_dates CHECK (valid_to IS NULL OR valid_to > valid_from)
);

CREATE TABLE IF NOT EXISTS deims.user_groups (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    group_code varchar(50) NOT NULL,
    group_name varchar(150) NOT NULL,
    description text,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, group_code)
);

CREATE TABLE IF NOT EXISTS deims.user_group_members (
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id) ON DELETE CASCADE,
    group_id uuid NOT NULL REFERENCES deims.user_groups(id) ON DELETE CASCADE,
    membership_id uuid NOT NULL REFERENCES deims.tenant_memberships(id) ON DELETE CASCADE,
    joined_by uuid REFERENCES deims.users(id),
    joined_at timestamptz NOT NULL DEFAULT now(),
    removed_by uuid REFERENCES deims.users(id),
    removed_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, group_id, membership_id),
    CONSTRAINT ck_user_group_members_dates CHECK (
        removed_at IS NULL OR removed_at >= joined_at
    )
);

CREATE TABLE IF NOT EXISTS deims.permissions (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    permission_code varchar(150) NOT NULL UNIQUE,
    permission_name varchar(200) NOT NULL,
    module_code varchar(50) NOT NULL,
    action_code varchar(30) NOT NULL,
    description text,
    is_sensitive boolean NOT NULL DEFAULT false,
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS deims.roles (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid REFERENCES deims.tenants(id) ON DELETE CASCADE,
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
    ON deims.roles (COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), role_code);

CREATE TABLE IF NOT EXISTS deims.role_permissions (
    tenant_id uuid REFERENCES deims.tenants(id) ON DELETE CASCADE,
    role_id uuid NOT NULL REFERENCES deims.roles(id) ON DELETE CASCADE,
    permission_id uuid NOT NULL REFERENCES deims.permissions(id) ON DELETE CASCADE,
    granted_by uuid REFERENCES deims.users(id),
    granted_at timestamptz NOT NULL DEFAULT now(),
    revoked_by uuid REFERENCES deims.users(id),
    revoked_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (role_id, permission_id),
    CONSTRAINT ck_role_permissions_dates CHECK (
        revoked_at IS NULL OR revoked_at >= granted_at
    )
);

CREATE TABLE IF NOT EXISTS deims.role_assignments (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id) ON DELETE CASCADE,
    membership_id uuid REFERENCES deims.tenant_memberships(id) ON DELETE CASCADE,
    group_id uuid REFERENCES deims.user_groups(id) ON DELETE CASCADE,
    role_id uuid NOT NULL REFERENCES deims.roles(id) ON DELETE CASCADE,
    scope_type varchar(30) NOT NULL DEFAULT 'TENANT',
    scope_id uuid,
    granted_by uuid REFERENCES deims.users(id),
    granted_at timestamptz NOT NULL DEFAULT now(),
    valid_until timestamptz,
    revoked_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_role_assignments_principal CHECK (
        (membership_id IS NOT NULL AND group_id IS NULL) OR
        (membership_id IS NULL AND group_id IS NOT NULL)
    ),
    CONSTRAINT ck_role_assignments_scope CHECK (scope_type IN ('TENANT','ORGANIZATION','ORG_UNIT','LOCATION','PARTNER'))
);

CREATE TABLE IF NOT EXISTS deims.delegations (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    delegator_membership_id uuid NOT NULL REFERENCES deims.tenant_memberships(id),
    delegate_membership_id uuid NOT NULL REFERENCES deims.tenant_memberships(id),
    scope_type varchar(30) NOT NULL DEFAULT 'APPROVAL',
    scope_id uuid,
    valid_from timestamptz NOT NULL,
    valid_to timestamptz NOT NULL,
    reason text,
    revoked_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_delegations_users CHECK (delegator_membership_id <> delegate_membership_id),
    CONSTRAINT ck_delegations_dates CHECK (valid_to > valid_from)
);

CREATE TABLE IF NOT EXISTS deims.user_sessions (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    user_id uuid NOT NULL REFERENCES deims.users(id) ON DELETE CASCADE,
    active_membership_id uuid,
    session_handle_hash char(64) NOT NULL UNIQUE,
    firebase_auth_time timestamptz,
    assurance_level varchar(30) NOT NULL DEFAULT 'SINGLE_FACTOR',
    issued_at timestamptz NOT NULL,
    expires_at timestamptz NOT NULL,
    last_seen_at timestamptz,
    ip_address inet,
    user_agent text,
    revoked_at timestamptz,
    revoke_reason text,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (active_membership_id, user_id)
        REFERENCES deims.tenant_memberships(id, user_id) ON DELETE CASCADE,
    CONSTRAINT ck_user_sessions_dates CHECK (expires_at > issued_at),
    CONSTRAINT ck_user_sessions_assurance CHECK (assurance_level IN ('SINGLE_FACTOR','MULTI_FACTOR','HARDWARE_BACKED')),
    CONSTRAINT ck_user_sessions_handle_hash CHECK (session_handle_hash ~ '^[0-9A-Fa-f]{64}$')
);

COMMENT ON TABLE deims.user_sessions IS
    'Server-side session metadata only. Raw session cookies and Firebase/Google ID, access, or refresh tokens are prohibited.';
COMMENT ON COLUMN deims.user_sessions.session_handle_hash IS
    'One-way SHA-256 hash of a high-entropy server-issued session handle; never store the raw handle or Firebase token.';

CREATE TABLE IF NOT EXISTS deims.login_events (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid REFERENCES deims.tenants(id),
    user_id uuid REFERENCES deims.users(id) ON DELETE SET NULL,
    firebase_uid varchar(128),
    provider_code varchar(30),
    success boolean NOT NULL,
    failure_code varchar(80),
    failure_detail_masked text,
    ip_address inet,
    user_agent text,
    correlation_id varchar(100),
    occurred_at timestamptz NOT NULL DEFAULT now(),
    received_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_login_events_provider CHECK (
        provider_code IS NULL OR provider_code IN ('password','google.com')
    )
);

COMMENT ON TABLE deims.login_events IS
    'Append-oriented authentication outcome log. Failure detail must be masked and raw Firebase/Google tokens must never be recorded.';

CREATE TABLE IF NOT EXISTS deims.user_devices (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    user_id uuid NOT NULL REFERENCES deims.users(id) ON DELETE CASCADE,
    device_fingerprint_hash char(64),
    platform varchar(30) NOT NULL,
    device_name varchar(150),
    app_version varchar(50),
    push_token_encrypted text,
    first_seen_at timestamptz NOT NULL DEFAULT now(),
    last_seen_at timestamptz,
    trusted_at timestamptz,
    revoked_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (user_id, device_fingerprint_hash),
    CONSTRAINT ck_user_devices_fingerprint_hash CHECK (
        device_fingerprint_hash IS NULL OR device_fingerprint_hash ~ '^[0-9A-Fa-f]{64}$'
    )
);

COMMENT ON COLUMN deims.user_devices.push_token_encrypted IS
    'Push token ciphertext only; encryption keys must remain in the external secret manager.';

CREATE TABLE IF NOT EXISTS deims.terms_versions (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    terms_code varchar(80) NOT NULL,
    version varchar(30) NOT NULL,
    title varchar(300) NOT NULL,
    content_uri text NOT NULL,
    content_sha256 char(64) NOT NULL,
    required boolean NOT NULL DEFAULT true,
    effective_at timestamptz NOT NULL,
    retired_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (terms_code, version),
    CONSTRAINT ck_terms_versions_hash CHECK (
        content_sha256 ~ '^[0-9A-Fa-f]{64}$'
    )
);

CREATE TABLE IF NOT EXISTS deims.user_terms_agreements (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    user_id uuid NOT NULL REFERENCES deims.users(id) ON DELETE CASCADE,
    terms_version_id uuid NOT NULL REFERENCES deims.terms_versions(id),
    agreed boolean NOT NULL,
    ip_address inet,
    user_agent text,
    agreed_at timestamptz NOT NULL DEFAULT now(),
    withdrawn_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (user_id, terms_version_id),
    CONSTRAINT ck_user_terms_agreement_dates CHECK (
        withdrawn_at IS NULL OR withdrawn_at >= agreed_at
    )
);

CREATE TABLE IF NOT EXISTS deims.api_clients (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
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
    CONSTRAINT ck_api_clients_auth CHECK (auth_method IN ('PRIVATE_KEY_JWT','MTLS','CLIENT_SECRET_HASH')),
    CONSTRAINT ck_api_clients_secret_hash CHECK (
        secret_hash IS NULL OR secret_hash ~ '^[0-9A-Fa-f]{64}$'
    ),
    CONSTRAINT ck_api_clients_secret_method CHECK (
        auth_method <> 'CLIENT_SECRET_HASH' OR secret_hash IS NOT NULL
    )
);

CREATE TABLE IF NOT EXISTS deims.api_client_permissions (
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id) ON DELETE CASCADE,
    api_client_id uuid NOT NULL REFERENCES deims.api_clients(id) ON DELETE CASCADE,
    permission_id uuid NOT NULL REFERENCES deims.permissions(id) ON DELETE CASCADE,
    granted_by uuid REFERENCES deims.users(id),
    granted_at timestamptz NOT NULL DEFAULT now(),
    revoked_by uuid REFERENCES deims.users(id),
    revoked_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, api_client_id, permission_id),
    CONSTRAINT ck_api_client_permissions_dates CHECK (
        revoked_at IS NULL OR revoked_at >= granted_at
    )
);

COMMENT ON COLUMN deims.api_clients.secret_hash IS
    'One-way SHA-256 or stronger derived client-secret verifier only; raw client secrets are prohibited.';

CREATE TABLE IF NOT EXISTS deims.code_sets (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid REFERENCES deims.tenants(id) ON DELETE CASCADE,
    code_set varchar(80) NOT NULL,
    code_set_name varchar(200) NOT NULL,
    description text,
    is_system boolean NOT NULL DEFAULT false,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_code_sets_scope
    ON deims.code_sets (COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), code_set);

CREATE TABLE IF NOT EXISTS deims.code_values (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid REFERENCES deims.tenants(id) ON DELETE CASCADE,
    code_set_id uuid NOT NULL REFERENCES deims.code_sets(id) ON DELETE CASCADE,
    code varchar(80) NOT NULL,
    code_name varchar(200) NOT NULL,
    description text,
    sort_order integer NOT NULL DEFAULT 0,
    parent_code_value_id uuid REFERENCES deims.code_values(id),
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

CREATE TABLE IF NOT EXISTS deims.number_sequences (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id) ON DELETE CASCADE,
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

CREATE TABLE IF NOT EXISTS deims.business_calendars (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
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

CREATE TABLE IF NOT EXISTS deims.calendar_dates (
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id) ON DELETE CASCADE,
    calendar_id uuid NOT NULL REFERENCES deims.business_calendars(id) ON DELETE CASCADE,
    calendar_date date NOT NULL,
    day_type varchar(20) NOT NULL,
    working_from time,
    working_to time,
    description varchar(300),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (calendar_id, calendar_date),
    CONSTRAINT ck_calendar_dates_type CHECK (day_type IN ('WORKING','HOLIDAY','PARTIAL','BLACKOUT')),
    CONSTRAINT ck_calendar_dates_time CHECK (working_to IS NULL OR working_from IS NULL OR working_to > working_from)
);

CREATE TABLE IF NOT EXISTS deims.files (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
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
    uploaded_by uuid REFERENCES deims.users(id),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    UNIQUE (tenant_id, storage_provider, storage_bucket, object_key),
    CONSTRAINT ck_files_size CHECK (byte_size >= 0),
    CONSTRAINT ck_files_scan CHECK (malware_scan_status IN ('PENDING','CLEAN','INFECTED','FAILED')),
    CONSTRAINT ck_files_sha256 CHECK (sha256 ~ '^[0-9A-Fa-f]{64}$')
);

COMMENT ON TABLE deims.files IS
    'Object-storage metadata only. File bytes, credentials, and encryption keys are never stored in PostgreSQL.';

CREATE TABLE IF NOT EXISTS deims.entity_files (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    entity_type varchar(80) NOT NULL,
    entity_id uuid NOT NULL,
    file_id uuid NOT NULL REFERENCES deims.files(id),
    document_type varchar(80),
    revision_no integer NOT NULL DEFAULT 1,
    is_primary boolean NOT NULL DEFAULT false,
    effective_at timestamptz,
    expires_at timestamptz,
    created_by uuid REFERENCES deims.users(id),
    updated_by uuid REFERENCES deims.users(id),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, entity_type, entity_id, file_id, revision_no),
    CONSTRAINT ck_entity_files_dates CHECK (
        expires_at IS NULL OR effective_at IS NULL OR expires_at > effective_at
    )
);

CREATE TABLE IF NOT EXISTS deims.entity_notes (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    entity_type varchar(80) NOT NULL,
    entity_id uuid NOT NULL,
    note_type varchar(30) NOT NULL DEFAULT 'INTERNAL',
    note_text text NOT NULL,
    visibility varchar(30) NOT NULL DEFAULT 'INTERNAL',
    created_by uuid REFERENCES deims.users(id),
    updated_by uuid REFERENCES deims.users(id),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    CONSTRAINT ck_entity_notes_visibility CHECK (visibility IN ('INTERNAL','CUSTOMER','CARRIER','PUBLIC'))
);

CREATE TABLE IF NOT EXISTS deims.custom_field_definitions (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
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

CREATE TABLE IF NOT EXISTS deims.custom_field_values (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    definition_id uuid NOT NULL REFERENCES deims.custom_field_definitions(id) ON DELETE CASCADE,
    entity_id uuid NOT NULL,
    value_json jsonb NOT NULL,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (definition_id, entity_id)
);

CREATE TABLE IF NOT EXISTS deims.idempotency_keys (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    idempotency_key varchar(200) NOT NULL,
    operation_code varchar(100) NOT NULL,
    request_hash char(64) NOT NULL,
    response_status integer,
    response_body jsonb,
    resource_type varchar(80),
    resource_id uuid,
    locked_until timestamptz,
    expires_at timestamptz NOT NULL,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    completed_at timestamptz,
    UNIQUE (tenant_id, operation_code, idempotency_key),
    CONSTRAINT ck_idempotency_request_hash CHECK (request_hash ~ '^[0-9A-Fa-f]{64}$'),
    CONSTRAINT ck_idempotency_expiry CHECK (expires_at > created_at)
);

COMMENT ON COLUMN deims.idempotency_keys.response_body IS
    'Optional masked/minimized response snapshot; credentials, tokens, and regulated document payloads are prohibited.';

CREATE TABLE IF NOT EXISTS deims.outbox_events (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
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
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_outbox_retry CHECK (retry_count >= 0)
);

COMMENT ON COLUMN deims.outbox_events.payload IS
    'Business event payload with secrets and authentication tokens removed.';

CREATE TABLE IF NOT EXISTS deims.external_systems (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
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
    CONSTRAINT ck_external_systems_direction CHECK (direction IN ('INBOUND','OUTBOUND','BIDIRECTIONAL')),
    CONSTRAINT ck_external_systems_no_inline_secrets CHECK (
        NOT deims.jsonb_contains_forbidden_secret_key(config)
    )
);

COMMENT ON COLUMN deims.external_systems.credential_secret_ref IS
    'Opaque external secret-manager reference; never store a credential value here or in config.';

CREATE TABLE IF NOT EXISTS deims.external_id_mappings (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    external_system_id uuid NOT NULL REFERENCES deims.external_systems(id),
    entity_type varchar(80) NOT NULL,
    internal_id uuid NOT NULL,
    external_id varchar(300) NOT NULL,
    external_version varchar(100),
    last_synced_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (external_system_id, entity_type, external_id),
    UNIQUE (external_system_id, entity_type, internal_id)
);

CREATE TABLE IF NOT EXISTS deims.integration_messages (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    external_system_id uuid REFERENCES deims.external_systems(id),
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
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (external_system_id, direction, external_message_id),
    CONSTRAINT ck_integration_messages_direction CHECK (direction IN ('IN','OUT')),
    CONSTRAINT ck_integration_messages_attempt CHECK (attempt_count >= 0),
    CONSTRAINT ck_integration_messages_payload_hash CHECK (
        payload_sha256 IS NULL OR payload_sha256 ~ '^[0-9A-Fa-f]{64}$'
    )
);

COMMENT ON TABLE deims.integration_messages IS
    'Integration envelope and masked diagnostics. Large or regulated payloads belong in protected object storage and are referenced by URI/hash.';

CREATE TABLE IF NOT EXISTS deims.audit_events (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid REFERENCES deims.tenants(id),
    actor_user_id uuid REFERENCES deims.users(id) ON DELETE SET NULL,
    actor_api_client_id uuid REFERENCES deims.api_clients(id) ON DELETE SET NULL,
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

COMMENT ON TABLE deims.audit_events IS
    'Append-oriented security and business audit ledger. Before/after documents must be minimized and masked; secrets and authentication tokens are prohibited.';

CREATE TABLE IF NOT EXISTS deims.data_retention_policies (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid REFERENCES deims.tenants(id) ON DELETE CASCADE,
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

CREATE TABLE IF NOT EXISTS deims.legal_holds (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    hold_no varchar(80) NOT NULL,
    hold_name varchar(300) NOT NULL,
    reason text NOT NULL,
    authority_reference varchar(300),
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    effective_at timestamptz NOT NULL,
    released_at timestamptz,
    created_by uuid REFERENCES deims.users(id),
    released_by uuid REFERENCES deims.users(id),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, hold_no),
    CONSTRAINT ck_legal_holds_status CHECK (status IN ('ACTIVE','RELEASED','CANCELLED')),
    CONSTRAINT ck_legal_holds_dates CHECK (released_at IS NULL OR released_at >= effective_at),
    CONSTRAINT ck_legal_holds_release CHECK (
        (status = 'RELEASED' AND released_at IS NOT NULL) OR
        (status <> 'RELEASED')
    )
);

CREATE TABLE IF NOT EXISTS deims.legal_hold_entities (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id) ON DELETE CASCADE,
    legal_hold_id uuid NOT NULL REFERENCES deims.legal_holds(id) ON DELETE RESTRICT,
    entity_type varchar(80) NOT NULL,
    entity_id uuid NOT NULL,
    applied_by uuid REFERENCES deims.users(id),
    applied_at timestamptz NOT NULL DEFAULT now(),
    released_by uuid REFERENCES deims.users(id),
    released_at timestamptz,
    note text,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, legal_hold_id, entity_type, entity_id),
    CONSTRAINT ck_legal_hold_entities_dates CHECK (
        released_at IS NULL OR released_at >= applied_at
    )
);

COMMENT ON TABLE deims.legal_hold_entities IS
    'Entities exempted from retention purge while a legal hold is active; purge jobs must check both active holds and unreleased entity links.';
