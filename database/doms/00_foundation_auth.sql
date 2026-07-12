-- DOMS enterprise OMS schema - foundation, tenancy, Firebase IAM, and platform services.
-- PostgreSQL 11 compatible. Executed by scripts/apply_doms_schema.py in one transaction.

CREATE SCHEMA IF NOT EXISTS doms;

CREATE OR REPLACE FUNCTION doms.generate_uuid()
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
CREATE OR REPLACE FUNCTION doms.text_contains_luhn_pan(p_value text)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
STRICT
PARALLEL SAFE
AS $function$
DECLARE
    candidate_match text[];
    digits text;
    digit_count integer;
    position integer;
    digit integer;
    checksum integer;
BEGIN
    FOR candidate_match IN
        SELECT regexp_matches(p_value, '([0-9][0-9 -]{11,35}[0-9])', 'g')
    LOOP
        digits := regexp_replace(candidate_match[1], '[ -]', '', 'g');
        digit_count := length(digits);
        IF digit_count < 13 OR digit_count > 19 THEN
            CONTINUE;
        END IF;
        checksum := 0;
        FOR position IN 1 .. digit_count LOOP
            digit := substr(digits, position, 1)::integer;
            IF mod(digit_count - position, 2) = 1 THEN
                digit := digit * 2;
                IF digit > 9 THEN
                    digit := digit - 9;
                END IF;
            END IF;
            checksum := checksum + digit;
        END LOOP;
        IF mod(checksum, 10) = 0 THEN
            RETURN true;
        END IF;
    END LOOP;
    RETURN false;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.text_contains_forbidden_secret(p_value text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
STRICT
PARALLEL SAFE
AS $function$
    SELECT
        p_value ~* '(^|[[:space:][:punct:]])bearer[[:space:]]+[A-Za-z0-9._~+/-]{8,}=*'
        OR p_value ~ '(^|[^A-Za-z0-9_-])[A-Za-z0-9_-]{3,}\.[A-Za-z0-9_-]{3,}\.[A-Za-z0-9_-]{3,}($|[^A-Za-z0-9_-])'
        OR p_value ~ '-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----'
        OR doms.text_contains_luhn_pan(p_value);
$function$;

CREATE OR REPLACE FUNCTION doms.jsonb_contains_forbidden_secret_key(
    p_value jsonb,
    p_path text[]
)
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
    normalized_parent text;
    next_path text[];
    is_reference_key boolean;
    scalar_value text;
BEGIN
    IF jsonb_typeof(p_value) = 'object' THEN
        FOR object_entry IN SELECT key, value FROM jsonb_each(p_value)
        LOOP
            normalized_key := lower(regexp_replace(object_entry.key, '[^a-zA-Z0-9]', '', 'g'));
            normalized_parent := CASE
                WHEN COALESCE(array_length(p_path, 1), 0) = 0 THEN NULL
                ELSE p_path[array_length(p_path, 1)]
            END;
            next_path := array_append(p_path, normalized_key);
            is_reference_key :=
                normalized_key ~ '(secret|vault|kms|privatekey|credential).*(reference|ref|uri|arn|id)$'
                OR normalized_key ~ '^(secret|vault|kms|privatekey|credential)(reference|ref|uri|arn|id)$';

            IF NOT is_reference_key AND (
                normalized_key = ANY (ARRAY[
                    'password','passwordhash','hashedpassword','rawpassword',
                    'secret','secretkey','clientsecret','accesstoken','refreshtoken',
                    'idtoken','firebasetoken','googletoken','sessiontoken','sessionhandle',
                    'apikey','privatekey','bearertoken','authorization','authorizationheader',
                    'credential','credentials','personalcustomscode',
                    'residentregistrationno','passportno','rawnonce',
                    'pan','primaryaccountnumber','cardnumber','paymentcardnumber',
                    'cvv','cvc','cid','securitycode','trackdata','track1','track2',
                    'pin','pinblock','cryptogram','magstripe','oauthcode','authorizationcode'
                ]::text[])
                OR (
                    normalized_parent = ANY (ARRAY[
                        'card','paymentcard','creditcard','debitcard','paymentmethod'
                    ]::text[])
                    AND normalized_key = ANY (ARRAY[
                        'number','accountnumber','cardnumber','pan'
                    ]::text[])
                )
            ) THEN
                RETURN true;
            END IF;

            IF doms.jsonb_contains_forbidden_secret_key(object_entry.value, next_path) THEN
                RETURN true;
            END IF;
        END LOOP;
    ELSIF jsonb_typeof(p_value) = 'array' THEN
        FOR array_value IN SELECT value FROM jsonb_array_elements(p_value)
        LOOP
            IF doms.jsonb_contains_forbidden_secret_key(array_value, p_path) THEN
                RETURN true;
            END IF;
        END LOOP;
    ELSIF jsonb_typeof(p_value) IN ('string','number') THEN
        scalar_value := p_value #>> '{}';
        IF scalar_value IS NOT NULL
           AND doms.text_contains_forbidden_secret(scalar_value) THEN
            RETURN true;
        END IF;
    END IF;
    RETURN false;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.jsonb_contains_forbidden_secret_key(p_value jsonb)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
STRICT
PARALLEL SAFE
AS $function$
    SELECT doms.jsonb_contains_forbidden_secret_key(p_value, ARRAY[]::text[]);
$function$;

REVOKE ALL ON FUNCTION doms.text_contains_luhn_pan(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION doms.text_contains_forbidden_secret(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION doms.jsonb_contains_forbidden_secret_key(jsonb, text[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION doms.jsonb_contains_forbidden_secret_key(jsonb) FROM PUBLIC;

CREATE OR REPLACE FUNCTION doms.touch_row()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    NEW.updated_at := now();
    NEW.row_version := OLD.row_version + 1;
    RETURN NEW;
END;
$function$;

CREATE TABLE IF NOT EXISTS doms.schema_migrations (
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

CREATE TABLE IF NOT EXISTS doms.tenants (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
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
    CONSTRAINT ck_tenants_status CHECK (status IN ('PENDING','ACTIVE','SUSPENDED','CLOSED')),
    CONSTRAINT ck_tenants_metadata_secrets CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(metadata)
    )
);

CREATE TABLE IF NOT EXISTS doms.tenant_settings (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id) ON DELETE CASCADE,
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
        setting_value IS NULL OR NOT doms.jsonb_contains_forbidden_secret_key(setting_value)
    )
);

COMMENT ON TABLE doms.tenant_settings IS
    'Tenant configuration. Secret values stay in an external secret manager; this table stores only an opaque secret_reference.';

CREATE TABLE IF NOT EXISTS doms.organizations (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
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

CREATE TABLE IF NOT EXISTS doms.organization_units (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    organization_id uuid NOT NULL REFERENCES doms.organizations(id),
    parent_unit_id uuid REFERENCES doms.organization_units(id),
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

CREATE TABLE IF NOT EXISTS doms.users (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
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
    ON doms.users (
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
        WHERE conrelid = 'doms.users'::regclass
          AND conname = 'fk_doms_users_platform_user'
    ) THEN
        ALTER TABLE doms.users
            ADD CONSTRAINT fk_doms_users_platform_user
            FOREIGN KEY (platform_user_id) REFERENCES kang.users(id) ON DELETE RESTRICT;
    END IF;
END;
$block$;

CREATE INDEX IF NOT EXISTS ix_users_email_search
    ON doms.users (lower(primary_email))
    WHERE primary_email IS NOT NULL AND deleted_at IS NULL;

COMMENT ON TABLE doms.users IS
    'DOMS principals mapped to canonical kang.users and Firebase token subjects. Tenant access is granted only through tenant_memberships.';
COMMENT ON COLUMN doms.users.firebase_uid IS
    'Canonical Firebase token subject. The unique identity key is firebase_project_id, COALESCE(firebase_tenant_id, ''''), firebase_uid.';
COMMENT ON COLUMN doms.users.primary_email IS
    'Mutable display/search attribute only. Email equality must never trigger automatic account creation, identity matching, or account merging.';
COMMENT ON COLUMN doms.users.platform_user_id IS
    'Required canonical platform principal in kang.users; DOMS must not maintain an independent password database.';

CREATE OR REPLACE FUNCTION doms.validate_user_platform_subject()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, doms, pg_temp
AS $function$
BEGIN
    IF NOT EXISTS (
        SELECT 1
          FROM kang.users platform_user
         WHERE platform_user.id = NEW.platform_user_id
           AND platform_user.firebase_uid = NEW.firebase_uid
           AND platform_user.status::text = 'active'
           AND platform_user.is_active
           AND platform_user.deleted_at IS NULL
           AND platform_user.locked_at IS NULL
    ) THEN
        RAISE EXCEPTION 'DOMS platform_user_id and Firebase uid must identify the same canonical kang.users row'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION doms.validate_user_platform_subject() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_validate_user_platform_subject ON doms.users;
CREATE TRIGGER trg_validate_user_platform_subject
    BEFORE INSERT OR UPDATE OF platform_user_id, firebase_project_id,
        firebase_tenant_id, firebase_uid ON doms.users
    FOR EACH ROW EXECUTE PROCEDURE doms.validate_user_platform_subject();

CREATE OR REPLACE FUNCTION doms.prevent_user_identity_rekey()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    IF OLD.firebase_project_id IS DISTINCT FROM NEW.firebase_project_id
       OR OLD.firebase_tenant_id IS DISTINCT FROM NEW.firebase_tenant_id
       OR OLD.firebase_uid IS DISTINCT FROM NEW.firebase_uid
       OR OLD.platform_user_id IS DISTINCT FROM NEW.platform_user_id THEN
        RAISE EXCEPTION
            'DOMS canonical user identity keys are immutable; use an explicit audited account-link/migration workflow';
    END IF;
    RETURN NEW;
END;
$function$;

DO $block$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_trigger
        WHERE tgrelid = 'doms.users'::regclass
          AND tgname = 'trg_prevent_user_identity_rekey'
          AND NOT tgisinternal
    ) THEN
        CREATE TRIGGER trg_prevent_user_identity_rekey
        BEFORE UPDATE OF firebase_project_id, firebase_tenant_id, firebase_uid, platform_user_id
        ON doms.users
        FOR EACH ROW EXECUTE PROCEDURE doms.prevent_user_identity_rekey();
    END IF;
END;
$block$;

DO $block$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'doms.organization_units'::regclass
          AND conname = 'fk_org_units_manager'
    ) THEN
        ALTER TABLE doms.organization_units
            ADD CONSTRAINT fk_org_units_manager FOREIGN KEY (manager_user_id)
            REFERENCES doms.users(id) ON DELETE SET NULL;
    END IF;
END;
$block$;

CREATE TABLE IF NOT EXISTS doms.user_profiles (
    user_id uuid PRIMARY KEY REFERENCES doms.users(id) ON DELETE CASCADE,
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

COMMENT ON COLUMN doms.user_profiles.phone_encrypted IS
    'Encrypted personal data only; the encryption key must remain in an external KMS/secret manager.';

-- Ephemeral authorization for the one-time Firebase bootstrap command. Runtime
-- roles receive no table privileges; the key is scoped to one backend transaction.
CREATE TABLE IF NOT EXISTS doms.identity_command_contexts (
    backend_pid integer NOT NULL,
    transaction_id bigint NOT NULL,
    operation varchar(30) NOT NULL,
    user_id uuid NOT NULL REFERENCES doms.users(id) ON DELETE CASCADE,
    firebase_project_id varchar(100) NOT NULL,
    firebase_tenant_id varchar(128),
    firebase_uid varchar(128) NOT NULL,
    provider_code varchar(30) NOT NULL,
    provider_subject varchar(255) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    expires_at timestamptz NOT NULL DEFAULT (clock_timestamp() + interval '5 minutes'),
    PRIMARY KEY (backend_pid, transaction_id),
    CONSTRAINT ck_identity_command_operation CHECK (operation = 'BOOTSTRAP_IDENTITY'),
    CONSTRAINT ck_identity_command_scope CHECK (
        firebase_project_id = 'kang-84cdd' AND firebase_tenant_id IS NULL
    ),
    CONSTRAINT ck_identity_command_provider CHECK (
        provider_code IN ('password','google.com') AND
        (provider_code <> 'password' OR provider_subject = firebase_uid)
    ),
    CONSTRAINT ck_identity_command_expiry CHECK (expires_at > created_at)
);

CREATE INDEX IF NOT EXISTS ix_identity_command_contexts_expiry
    ON doms.identity_command_contexts (expires_at);

REVOKE ALL ON TABLE doms.identity_command_contexts FROM PUBLIC;

CREATE TABLE IF NOT EXISTS doms.auth_identities (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    user_id uuid NOT NULL REFERENCES doms.users(id) ON DELETE CASCADE,
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
    UNIQUE (id, user_id),
    CONSTRAINT ck_auth_identities_provider CHECK (provider_code IN ('password','google.com')),
    CONSTRAINT ck_auth_identities_subjects CHECK (
        btrim(firebase_uid) <> '' AND btrim(provider_subject) <> ''
    ),
    CONSTRAINT ck_auth_identities_firebase_scope CHECK (
        firebase_project_id = 'kang-84cdd' AND firebase_tenant_id IS NULL
    ),
    CONSTRAINT ck_auth_identities_password_subject CHECK (
        provider_code <> 'password' OR provider_subject = firebase_uid
    ),
    CONSTRAINT ck_auth_identities_no_secret_metadata CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(metadata)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_auth_identities_provider_subject
    ON doms.auth_identities (
        firebase_project_id,
        COALESCE(firebase_tenant_id, ''),
        provider_code,
        provider_subject
    );

CREATE UNIQUE INDEX IF NOT EXISTS ux_auth_identities_active_user_provider
    ON doms.auth_identities (user_id, provider_code)
    WHERE disabled_at IS NULL;

COMMENT ON TABLE doms.auth_identities IS
    'Links Firebase email/password or Google provider subjects to one Firebase account. Password hashes and Firebase/Google ID, access, refresh, or session tokens must never be stored here.';
COMMENT ON COLUMN doms.auth_identities.firebase_uid IS
    'Firebase account subject from the verified ID token; deliberately separate from the provider-specific subject.';
COMMENT ON COLUMN doms.auth_identities.provider_subject IS
    'Stable provider subject verified by Firebase. For password auth, use the verified provider-data UID or Firebase UID when no separate subject exists; never substitute or match this key using an email address.';
COMMENT ON COLUMN doms.auth_identities.provider_email IS
    'Mutable display/search attribute only; it is not an identity key and must never drive automatic account linking or merging.';
COMMENT ON COLUMN doms.auth_identities.metadata IS
    'Non-secret provider metadata only. Password material and raw Firebase/Google tokens are prohibited.';

CREATE OR REPLACE FUNCTION doms.validate_auth_identity_owner()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, doms, pg_temp
AS $function$
DECLARE
    owner_row doms.users%ROWTYPE;
    bootstrap_authorized boolean;
    approved_link_exists boolean;
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
            'DOMS authentication identity keys are immutable; disable the identity and complete a new explicit link request';
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
            'DOMS account-link identity keys are immutable; cancel the request and create a new one';
    END IF;

    SELECT * INTO owner_row
      FROM doms.users
     WHERE id = NEW.user_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'DOMS auth identity user does not exist';
    END IF;
    IF owner_row.firebase_project_id IS DISTINCT FROM NEW.firebase_project_id
       OR owner_row.firebase_tenant_id IS DISTINCT FROM NEW.firebase_tenant_id
       OR owner_row.firebase_uid IS DISTINCT FROM NEW.firebase_uid THEN
        RAISE EXCEPTION 'DOMS auth identity Firebase subject must match its user';
    END IF;

    IF TG_TABLE_NAME = 'auth_identities' AND TG_OP = 'INSERT' THEN
        SELECT EXISTS (
            SELECT 1
            FROM doms.identity_command_contexts command_context
            WHERE command_context.backend_pid = pg_backend_pid()
              AND command_context.transaction_id = txid_current()
              AND command_context.operation = 'BOOTSTRAP_IDENTITY'
              AND command_context.user_id = NEW.user_id
              AND command_context.firebase_project_id = NEW.firebase_project_id
              AND command_context.firebase_tenant_id IS NOT DISTINCT FROM NEW.firebase_tenant_id
              AND command_context.firebase_uid = NEW.firebase_uid
              AND command_context.provider_code = NEW.provider_code
              AND command_context.provider_subject = NEW.provider_subject
              AND command_context.expires_at > clock_timestamp()
        ) INTO bootstrap_authorized;

        SELECT EXISTS (
            SELECT 1
            FROM doms.account_link_requests link_request
            WHERE link_request.user_id = NEW.user_id
              AND link_request.firebase_project_id = NEW.firebase_project_id
              AND link_request.firebase_tenant_id IS NOT DISTINCT FROM NEW.firebase_tenant_id
              AND link_request.firebase_uid = NEW.firebase_uid
              AND link_request.provider_code = NEW.provider_code
              AND link_request.provider_subject = NEW.provider_subject
              AND link_request.status = 'APPROVED'
              AND link_request.decided_by IS NOT NULL
              AND link_request.decided_at IS NOT NULL
              AND link_request.expires_at > clock_timestamp()
              AND link_request.completed_identity_id IS NULL
        ) INTO approved_link_exists;

        IF NOT COALESCE(bootstrap_authorized, false)
           AND NOT COALESCE(approved_link_exists, false) THEN
            RAISE EXCEPTION
                'A new authentication identity requires an approved account link or verified bootstrap command'
                USING ERRCODE = '42501';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION doms.validate_auth_identity_owner() FROM PUBLIC;

DO $block$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_trigger
        WHERE tgrelid = 'doms.auth_identities'::regclass
          AND tgname = 'trg_validate_auth_identity_owner'
          AND NOT tgisinternal
    ) THEN
        CREATE TRIGGER trg_validate_auth_identity_owner
        BEFORE INSERT OR UPDATE OF user_id, firebase_project_id, firebase_tenant_id, firebase_uid, provider_code, provider_subject
        ON doms.auth_identities
        FOR EACH ROW EXECUTE PROCEDURE doms.validate_auth_identity_owner();
    END IF;
END;
$block$;

CREATE TABLE IF NOT EXISTS doms.account_link_requests (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    user_id uuid NOT NULL REFERENCES doms.users(id) ON DELETE CASCADE,
    firebase_project_id varchar(100) NOT NULL,
    firebase_tenant_id varchar(128),
    firebase_uid varchar(128) NOT NULL,
    provider_code varchar(30) NOT NULL,
    provider_subject varchar(255) NOT NULL,
    provider_email varchar(320),
    request_nonce_hash char(64) NOT NULL UNIQUE,
    status varchar(20) NOT NULL DEFAULT 'PENDING',
    verification_method varchar(30) NOT NULL,
    requested_by uuid REFERENCES doms.users(id),
    requested_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL,
    decided_by uuid REFERENCES doms.users(id),
    decided_at timestamptz,
    decision_reason text,
    completed_identity_id uuid REFERENCES doms.auth_identities(id) ON DELETE SET NULL,
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
    CONSTRAINT ck_account_link_firebase_scope CHECK (
        firebase_project_id = 'kang-84cdd' AND firebase_tenant_id IS NULL
    ),
    CONSTRAINT ck_account_link_password_subject CHECK (
        provider_code <> 'password' OR provider_subject = firebase_uid
    ),
    CONSTRAINT ck_account_link_completion CHECK (
        (status = 'COMPLETED' AND completed_identity_id IS NOT NULL) OR
        (status <> 'COMPLETED' AND completed_identity_id IS NULL)
    ),
    CONSTRAINT ck_account_link_decision CHECK (
        status NOT IN ('APPROVED','REJECTED','COMPLETED') OR
        (decided_by IS NOT NULL AND decided_at IS NOT NULL)
    )
);

CREATE INDEX IF NOT EXISTS ix_account_link_requests_user_status
    ON doms.account_link_requests (user_id, status, requested_at DESC);

COMMENT ON TABLE doms.account_link_requests IS
    'Explicit identity-link workflow. Matching emails never creates, approves, or completes a link; the nonce is stored only as a one-way hash.';
COMMENT ON COLUMN doms.account_link_requests.provider_email IS
    'Display/search evidence only, never an identity or merge key.';

DO $block$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_trigger
        WHERE tgrelid = 'doms.account_link_requests'::regclass
          AND tgname = 'trg_validate_account_link_owner'
          AND NOT tgisinternal
    ) THEN
CREATE TRIGGER trg_validate_account_link_owner
        BEFORE INSERT OR UPDATE OF user_id, firebase_project_id, firebase_tenant_id, firebase_uid, provider_code, provider_subject
        ON doms.account_link_requests
        FOR EACH ROW EXECUTE PROCEDURE doms.validate_auth_identity_owner();
    END IF;
END;
$block$;

CREATE OR REPLACE FUNCTION doms.validate_account_link_completion()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    identity_row doms.auth_identities%ROWTYPE;
BEGIN
    IF NEW.completed_identity_id IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT * INTO identity_row
      FROM doms.auth_identities
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

CREATE OR REPLACE FUNCTION doms.validate_account_link_transition()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.status <> 'PENDING'
           OR NEW.decided_by IS NOT NULL
           OR NEW.decided_at IS NOT NULL
           OR NEW.completed_identity_id IS NOT NULL THEN
            RAISE EXCEPTION 'Account-link requests must be inserted in PENDING state'
                USING ERRCODE = '23514';
        END IF;
        RETURN NEW;
    END IF;

    IF NEW.status = OLD.status THEN
        IF OLD.status IN ('APPROVED','REJECTED','COMPLETED') AND (
            OLD.decided_by IS DISTINCT FROM NEW.decided_by
            OR OLD.decided_at IS DISTINCT FROM NEW.decided_at
            OR OLD.decision_reason IS DISTINCT FROM NEW.decision_reason
        ) THEN
            RAISE EXCEPTION 'Account-link decision evidence is immutable after decision'
                USING ERRCODE = '55000';
        END IF;
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
        RAISE EXCEPTION 'Invalid DOMS account-link status transition: % -> %',
            OLD.status, NEW.status;
    END IF;
    IF NEW.status IN ('APPROVED','REJECTED','COMPLETED')
       AND (NEW.decided_by IS NULL OR NEW.decided_at IS NULL) THEN
        RAISE EXCEPTION 'Account-link decisions require decided_by and decided_at'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

DO $block$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_trigger
        WHERE tgrelid = 'doms.account_link_requests'::regclass
          AND tgname = 'trg_validate_account_link_completion'
          AND NOT tgisinternal
    ) THEN
        CREATE TRIGGER trg_validate_account_link_completion
        BEFORE INSERT OR UPDATE OF completed_identity_id, status
        ON doms.account_link_requests
        FOR EACH ROW EXECUTE PROCEDURE doms.validate_account_link_completion();
    END IF;
END;
$block$;

DO $block$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_trigger
        WHERE tgrelid = 'doms.account_link_requests'::regclass
          AND tgname = 'trg_validate_account_link_transition'
          AND NOT tgisinternal
    ) THEN
        CREATE TRIGGER trg_validate_account_link_transition
        BEFORE INSERT OR UPDATE
        ON doms.account_link_requests
        FOR EACH ROW EXECUTE PROCEDURE doms.validate_account_link_transition();
    END IF;
END;
$block$;

CREATE OR REPLACE FUNCTION doms.bootstrap_firebase_identity(
    p_platform_user_id uuid,
    p_firebase_uid text,
    p_provider_code text,
    p_provider_subject text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, doms, pg_temp
AS $function$
DECLARE
    platform_user record;
    doms_user_id uuid;
    existing_identity_id uuid;
BEGIN
    IF p_provider_code NOT IN ('password','google.com')
       OR btrim(COALESCE(p_firebase_uid, '')) = ''
       OR btrim(COALESCE(p_provider_subject, '')) = ''
       OR (p_provider_code = 'password' AND p_provider_subject <> p_firebase_uid) THEN
        RAISE EXCEPTION 'Invalid Firebase bootstrap provider subject'
            USING ERRCODE = '22023';
    END IF;

    SELECT platform_row.id, platform_row.firebase_uid, platform_row.email,
           platform_row.email_verified, platform_row.display_name
      INTO platform_user
      FROM kang.users platform_row
     WHERE platform_row.id = p_platform_user_id
       AND platform_row.firebase_uid = p_firebase_uid
       AND platform_row.status::text = 'active'
       AND platform_row.is_active
       AND platform_row.deleted_at IS NULL
       AND platform_row.locked_at IS NULL
     FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Canonical Firebase user is inactive, deleted, locked, or mismatched'
            USING ERRCODE = '28000';
    END IF;

    SELECT user_row.id INTO doms_user_id
      FROM doms.users user_row
     WHERE user_row.platform_user_id = p_platform_user_id
     FOR UPDATE;
    IF NOT FOUND THEN
        INSERT INTO doms.users (
            firebase_project_id, firebase_tenant_id, firebase_uid,
            platform_user_id, primary_email, email_verified, display_name, status
        ) VALUES (
            'kang-84cdd', NULL, p_firebase_uid, p_platform_user_id,
            platform_user.email, platform_user.email_verified,
            platform_user.display_name, 'ACTIVE'
        )
        RETURNING id INTO doms_user_id;
    ELSIF NOT EXISTS (
        SELECT 1 FROM doms.users user_row
        WHERE user_row.id = doms_user_id
          AND user_row.firebase_project_id = 'kang-84cdd'
          AND user_row.firebase_tenant_id IS NULL
          AND user_row.firebase_uid = p_firebase_uid
          AND user_row.status = 'ACTIVE'
          AND user_row.deleted_at IS NULL
    ) THEN
        RAISE EXCEPTION 'Existing DOMS user is inactive or has a different Firebase subject'
            USING ERRCODE = '28000';
    END IF;

    SELECT identity_row.id INTO existing_identity_id
      FROM doms.auth_identities identity_row
     WHERE identity_row.user_id = doms_user_id
       AND identity_row.firebase_project_id = 'kang-84cdd'
       AND identity_row.firebase_tenant_id IS NULL
       AND identity_row.firebase_uid = p_firebase_uid
       AND identity_row.provider_code = p_provider_code
       AND identity_row.provider_subject = p_provider_subject
       AND identity_row.disabled_at IS NULL;
    IF FOUND THEN
        RETURN doms_user_id;
    END IF;
    IF EXISTS (SELECT 1 FROM doms.auth_identities WHERE user_id = doms_user_id) THEN
        RAISE EXCEPTION 'Bootstrap is permitted only before the first DOMS identity; use account linking'
            USING ERRCODE = '42501';
    END IF;

    DELETE FROM doms.identity_command_contexts
     WHERE backend_pid = pg_backend_pid()
       AND transaction_id = txid_current();
    DELETE FROM doms.identity_command_contexts
     WHERE expires_at <= statement_timestamp();
    INSERT INTO doms.identity_command_contexts (
        backend_pid, transaction_id, operation, user_id,
        firebase_project_id, firebase_tenant_id, firebase_uid,
        provider_code, provider_subject
    ) VALUES (
        pg_backend_pid(), txid_current(), 'BOOTSTRAP_IDENTITY', doms_user_id,
        'kang-84cdd', NULL, p_firebase_uid, p_provider_code, p_provider_subject
    );

    INSERT INTO doms.auth_identities (
        user_id, firebase_project_id, firebase_tenant_id, firebase_uid,
        provider_code, provider_subject, provider_email, email_verified,
        last_authenticated_at, metadata
    ) VALUES (
        doms_user_id, 'kang-84cdd', NULL, p_firebase_uid,
        p_provider_code, p_provider_subject, platform_user.email,
        platform_user.email_verified, statement_timestamp(),
        '{"bootstrap":"verified_authenticator"}'::jsonb
    );
    DELETE FROM doms.identity_command_contexts
     WHERE backend_pid = pg_backend_pid()
       AND transaction_id = txid_current();
    RETURN doms_user_id;
END;
$function$;

REVOKE ALL ON FUNCTION doms.bootstrap_firebase_identity(uuid, text, text, text) FROM PUBLIC;

CREATE OR REPLACE FUNCTION doms.complete_account_link_identity(p_request_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, doms, pg_temp
AS $function$
DECLARE
    link_request doms.account_link_requests%ROWTYPE;
    identity_id uuid;
BEGIN
    SELECT * INTO link_request
      FROM doms.account_link_requests
     WHERE id = p_request_id
     FOR UPDATE;
    IF NOT FOUND OR link_request.status <> 'APPROVED'
       OR link_request.decided_by IS NULL OR link_request.decided_at IS NULL
       OR link_request.expires_at <= statement_timestamp()
       OR link_request.completed_identity_id IS NOT NULL THEN
        RAISE EXCEPTION 'Account-link request is not approved and completable'
            USING ERRCODE = '23514';
    END IF;

    INSERT INTO doms.auth_identities (
        user_id, firebase_project_id, firebase_tenant_id, firebase_uid,
        provider_code, provider_subject, provider_email, email_verified,
        last_authenticated_at, metadata
    ) VALUES (
        link_request.user_id, link_request.firebase_project_id,
        link_request.firebase_tenant_id, link_request.firebase_uid,
        link_request.provider_code, link_request.provider_subject,
        link_request.provider_email, true, statement_timestamp(),
        jsonb_build_object('account_link_request_id', link_request.id::text)
    )
    RETURNING id INTO identity_id;

    UPDATE doms.account_link_requests
       SET status = 'COMPLETED', completed_identity_id = identity_id
     WHERE id = link_request.id;
    RETURN identity_id;
END;
$function$;

REVOKE ALL ON FUNCTION doms.complete_account_link_identity(uuid) FROM PUBLIC;

CREATE TABLE IF NOT EXISTS doms.account_link_events (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    request_id uuid NOT NULL REFERENCES doms.account_link_requests(id) ON DELETE RESTRICT,
    event_sequence integer NOT NULL,
    event_type varchar(40) NOT NULL,
    from_status varchar(20),
    to_status varchar(20),
    actor_user_id uuid REFERENCES doms.users(id) ON DELETE SET NULL,
    evidence_masked jsonb NOT NULL DEFAULT '{}'::jsonb,
    ip_address inet,
    user_agent text,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (request_id, event_sequence),
    CONSTRAINT ck_account_link_event_sequence CHECK (event_sequence > 0),
    CONSTRAINT ck_account_link_event_no_secrets CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(evidence_masked)
    )
);

COMMENT ON TABLE doms.account_link_events IS
    'Append-oriented audit trail for explicit account-link decisions; raw credentials, tokens, and nonces are prohibited.';

CREATE TABLE IF NOT EXISTS doms.user_invitations (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    email varchar(320) NOT NULL,
    invitation_token_hash char(64) NOT NULL UNIQUE,
    invited_by uuid REFERENCES doms.users(id),
    expires_at timestamptz NOT NULL,
    accepted_by uuid REFERENCES doms.users(id),
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

COMMENT ON TABLE doms.user_invitations IS
    'Tenant invitation workflow. Only a one-way token hash is stored; invitation email is a destination/display value and never an automatic account-merge key.';

CREATE TABLE IF NOT EXISTS doms.tenant_memberships (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES doms.users(id) ON DELETE CASCADE,
    organization_id uuid REFERENCES doms.organizations(id),
    default_org_unit_id uuid REFERENCES doms.organization_units(id),
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
    UNIQUE (id, user_id, tenant_id),
    CONSTRAINT ck_memberships_status CHECK (status IN ('INVITED','ACTIVE','SUSPENDED','EXPIRED','REVOKED')),
    CONSTRAINT ck_memberships_dates CHECK (valid_to IS NULL OR valid_to > valid_from)
);

-- First-membership onboarding happens before a tenant request context exists.
-- This marker is writable only by SECURITY DEFINER commands and binds one
-- pre-generated membership id to exactly one DOMS user and tenant transaction.
CREATE TABLE IF NOT EXISTS doms.membership_provision_contexts (
    backend_pid integer NOT NULL,
    transaction_id bigint NOT NULL,
    candidate_membership_id uuid NOT NULL UNIQUE,
    bound_user_id uuid NOT NULL REFERENCES doms.users(id) ON DELETE CASCADE,
    bound_tenant_id uuid NOT NULL REFERENCES doms.tenants(id) ON DELETE CASCADE,
    actor_user_id uuid REFERENCES doms.users(id) ON DELETE SET NULL,
    actor_service varchar(100) NOT NULL,
    correlation_id varchar(100) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    expires_at timestamptz NOT NULL DEFAULT (clock_timestamp() + interval '1 minute'),
    PRIMARY KEY (backend_pid, transaction_id),
    CONSTRAINT ck_membership_provision_context_pid CHECK (backend_pid > 0),
    CONSTRAINT ck_membership_provision_context_actor CHECK (
        actor_service ~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,99}$'
    ),
    CONSTRAINT ck_membership_provision_context_correlation CHECK (
        correlation_id ~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,99}$'
    ),
    CONSTRAINT ck_membership_provision_context_expiry CHECK (expires_at > created_at)
);

CREATE INDEX IF NOT EXISTS ix_membership_provision_contexts_expiry
    ON doms.membership_provision_contexts (expires_at);

REVOKE ALL ON TABLE doms.membership_provision_contexts FROM PUBLIC;

CREATE OR REPLACE FUNCTION doms.has_active_membership_provision_context(
    p_user_id uuid,
    p_tenant_id uuid
)
RETURNS boolean
LANGUAGE sql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, doms, pg_temp
AS $function$
    SELECT EXISTS (
        SELECT 1
        FROM doms.membership_provision_contexts provision_context
        WHERE provision_context.backend_pid = pg_backend_pid()
          AND provision_context.transaction_id = txid_current()
          AND provision_context.bound_user_id = p_user_id
          AND provision_context.bound_tenant_id = p_tenant_id
          AND provision_context.expires_at > statement_timestamp()
    )
$function$;

CREATE OR REPLACE FUNCTION doms.is_membership_provision_candidate(
    p_membership_id uuid,
    p_user_id uuid,
    p_tenant_id uuid
)
RETURNS boolean
LANGUAGE sql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, doms, pg_temp
AS $function$
    SELECT EXISTS (
        SELECT 1
        FROM doms.membership_provision_contexts provision_context
        WHERE provision_context.backend_pid = pg_backend_pid()
          AND provision_context.transaction_id = txid_current()
          AND provision_context.candidate_membership_id = p_membership_id
          AND provision_context.bound_user_id = p_user_id
          AND provision_context.bound_tenant_id = p_tenant_id
          AND provision_context.expires_at > statement_timestamp()
    )
$function$;

CREATE OR REPLACE FUNCTION doms.has_membership_provision_audit_context(
    p_membership_id uuid,
    p_tenant_id uuid
)
RETURNS boolean
LANGUAGE sql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, doms, pg_temp
AS $function$
    SELECT EXISTS (
        SELECT 1
        FROM doms.membership_provision_contexts provision_context
        WHERE provision_context.backend_pid = pg_backend_pid()
          AND provision_context.transaction_id = txid_current()
          AND provision_context.candidate_membership_id = p_membership_id
          AND provision_context.bound_tenant_id = p_tenant_id
          AND provision_context.expires_at > statement_timestamp()
    )
$function$;

REVOKE ALL ON FUNCTION doms.has_active_membership_provision_context(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION doms.is_membership_provision_candidate(uuid, uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION doms.has_membership_provision_audit_context(uuid, uuid) FROM PUBLIC;

CREATE TABLE IF NOT EXISTS doms.user_groups (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    group_code varchar(50) NOT NULL,
    group_name varchar(150) NOT NULL,
    description text,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, group_code)
);

CREATE TABLE IF NOT EXISTS doms.user_group_members (
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id) ON DELETE CASCADE,
    group_id uuid NOT NULL REFERENCES doms.user_groups(id) ON DELETE CASCADE,
    membership_id uuid NOT NULL REFERENCES doms.tenant_memberships(id) ON DELETE CASCADE,
    joined_by uuid REFERENCES doms.users(id),
    joined_at timestamptz NOT NULL DEFAULT now(),
    removed_by uuid REFERENCES doms.users(id),
    removed_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, group_id, membership_id),
    CONSTRAINT ck_user_group_members_dates CHECK (
        removed_at IS NULL OR removed_at >= joined_at
    )
);

CREATE TABLE IF NOT EXISTS doms.permissions (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
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

CREATE TABLE IF NOT EXISTS doms.roles (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid REFERENCES doms.tenants(id) ON DELETE CASCADE,
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
    ON doms.roles (COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), role_code);

CREATE TABLE IF NOT EXISTS doms.role_permissions (
    tenant_id uuid REFERENCES doms.tenants(id) ON DELETE CASCADE,
    role_id uuid NOT NULL REFERENCES doms.roles(id) ON DELETE CASCADE,
    permission_id uuid NOT NULL REFERENCES doms.permissions(id) ON DELETE CASCADE,
    granted_by uuid REFERENCES doms.users(id),
    granted_at timestamptz NOT NULL DEFAULT now(),
    revoked_by uuid REFERENCES doms.users(id),
    revoked_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (role_id, permission_id),
    CONSTRAINT ck_role_permissions_dates CHECK (
        revoked_at IS NULL OR revoked_at >= granted_at
    )
);

CREATE TABLE IF NOT EXISTS doms.role_assignments (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id) ON DELETE CASCADE,
    membership_id uuid REFERENCES doms.tenant_memberships(id) ON DELETE CASCADE,
    group_id uuid REFERENCES doms.user_groups(id) ON DELETE CASCADE,
    role_id uuid NOT NULL REFERENCES doms.roles(id) ON DELETE CASCADE,
    scope_type varchar(30) NOT NULL DEFAULT 'TENANT',
    scope_id uuid,
    granted_by uuid REFERENCES doms.users(id),
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

CREATE TABLE IF NOT EXISTS doms.delegations (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    delegator_membership_id uuid NOT NULL REFERENCES doms.tenant_memberships(id),
    delegate_membership_id uuid NOT NULL REFERENCES doms.tenant_memberships(id),
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

CREATE TABLE IF NOT EXISTS doms.user_sessions (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    user_id uuid NOT NULL REFERENCES doms.users(id) ON DELETE RESTRICT,
    auth_identity_id uuid NOT NULL,
    active_membership_id uuid NOT NULL,
    active_tenant_id uuid NOT NULL REFERENCES doms.tenants(id) ON DELETE RESTRICT,
    session_handle_hash char(64) NOT NULL UNIQUE,
    session_status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    firebase_auth_time timestamptz NOT NULL,
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
    UNIQUE (id, user_id, active_tenant_id, active_membership_id),
    FOREIGN KEY (auth_identity_id, user_id)
        REFERENCES doms.auth_identities(id, user_id) ON DELETE RESTRICT,
    FOREIGN KEY (active_membership_id, user_id, active_tenant_id)
        REFERENCES doms.tenant_memberships(id, user_id, tenant_id) ON DELETE RESTRICT,
    CONSTRAINT ck_user_sessions_dates CHECK (
        expires_at > issued_at AND firebase_auth_time <= issued_at + interval '5 minutes'
    ),
    CONSTRAINT ck_user_sessions_assurance CHECK (assurance_level IN ('SINGLE_FACTOR','MULTI_FACTOR','HARDWARE_BACKED')),
    CONSTRAINT ck_user_sessions_handle_hash CHECK (session_handle_hash ~ '^[0-9A-Fa-f]{64}$'),
    CONSTRAINT ck_user_sessions_status CHECK (
        session_status IN ('ACTIVE','REVOKED','EXPIRED')
    ),
    CONSTRAINT ck_user_sessions_status_projection CHECK (
        (session_status = 'ACTIVE' AND revoked_at IS NULL) OR
        (session_status = 'REVOKED' AND revoked_at IS NOT NULL) OR
        (session_status = 'EXPIRED' AND revoked_at IS NULL)
    )
);

COMMENT ON TABLE doms.user_sessions IS
    'Server-side session metadata only. Raw session cookies and Firebase/Google ID, access, or refresh tokens are prohibited.';
COMMENT ON COLUMN doms.user_sessions.session_handle_hash IS
    'One-way SHA-256 hash of a high-entropy server-issued session handle; never store the raw handle or Firebase token.';

CREATE OR REPLACE FUNCTION doms.validate_user_session_state()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, doms, pg_temp
AS $function$
DECLARE
    source_is_active boolean;
BEGIN
    IF TG_OP = 'UPDATE' AND (
        OLD.user_id IS DISTINCT FROM NEW.user_id
        OR OLD.auth_identity_id IS DISTINCT FROM NEW.auth_identity_id
        OR OLD.active_membership_id IS DISTINCT FROM NEW.active_membership_id
        OR OLD.active_tenant_id IS DISTINCT FROM NEW.active_tenant_id
        OR OLD.session_handle_hash IS DISTINCT FROM NEW.session_handle_hash
        OR OLD.firebase_auth_time IS DISTINCT FROM NEW.firebase_auth_time
        OR OLD.issued_at IS DISTINCT FROM NEW.issued_at
        OR OLD.expires_at IS DISTINCT FROM NEW.expires_at
    ) THEN
        RAISE EXCEPTION 'Session identity, tenant binding, handle, and validity window are immutable'
            USING ERRCODE = '55000';
    END IF;

    IF TG_OP = 'UPDATE' AND OLD.session_status IN ('REVOKED','EXPIRED')
       AND NEW.session_status IS DISTINCT FROM OLD.session_status THEN
        RAISE EXCEPTION 'A terminal session cannot be reactivated or reclassified'
            USING ERRCODE = '55000';
    END IF;

    IF NEW.session_status = 'ACTIVE' THEN
        SELECT EXISTS (
            SELECT 1
            FROM doms.users doms_user
            JOIN kang.users platform_user
              ON platform_user.id = doms_user.platform_user_id
            JOIN doms.auth_identities identity_row
              ON identity_row.id = NEW.auth_identity_id
             AND identity_row.user_id = doms_user.id
            JOIN doms.tenant_memberships membership
              ON membership.id = NEW.active_membership_id
             AND membership.user_id = doms_user.id
             AND membership.tenant_id = NEW.active_tenant_id
            JOIN doms.tenants tenant_row
              ON tenant_row.id = membership.tenant_id
            WHERE doms_user.id = NEW.user_id
              AND doms_user.status = 'ACTIVE'
              AND doms_user.deleted_at IS NULL
              AND identity_row.disabled_at IS NULL
              AND identity_row.firebase_project_id = 'kang-84cdd'
              AND identity_row.firebase_tenant_id IS NULL
              AND membership.status = 'ACTIVE'
              AND membership.valid_from <= statement_timestamp()
              AND (membership.valid_to IS NULL OR membership.valid_to > statement_timestamp())
              AND (membership.valid_to IS NULL OR NEW.expires_at <= membership.valid_to)
              AND tenant_row.status = 'ACTIVE'
              AND tenant_row.deleted_at IS NULL
              AND platform_user.firebase_uid = doms_user.firebase_uid
              AND platform_user.status::text = 'active'
              AND platform_user.is_active
              AND platform_user.deleted_at IS NULL
              AND platform_user.locked_at IS NULL
        ) INTO source_is_active;

        IF NOT COALESCE(source_is_active, false) THEN
            RAISE EXCEPTION 'Active session requires active Firebase identity, user, tenant, and membership'
                USING ERRCODE = '28000';
        END IF;
        IF NEW.revoked_at IS NOT NULL OR NEW.expires_at <= statement_timestamp() THEN
            RAISE EXCEPTION 'Active session must be unrevoked and unexpired'
                USING ERRCODE = '23514';
        END IF;
    ELSIF NEW.session_status = 'REVOKED' THEN
        IF NEW.revoked_at IS NULL OR btrim(COALESCE(NEW.revoke_reason, '')) = '' THEN
            RAISE EXCEPTION 'Revoked session requires revoked_at and revoke_reason'
                USING ERRCODE = '23514';
        END IF;
    ELSIF NEW.session_status = 'EXPIRED' THEN
        IF NEW.expires_at > statement_timestamp() OR NEW.revoked_at IS NOT NULL THEN
            RAISE EXCEPTION 'Expired session projection requires an elapsed expiry and no revocation timestamp'
                USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION doms.validate_user_session_state() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_validate_user_session_state ON doms.user_sessions;
CREATE TRIGGER trg_validate_user_session_state
    BEFORE INSERT OR UPDATE ON doms.user_sessions
    FOR EACH ROW EXECUTE PROCEDURE doms.validate_user_session_state();

CREATE OR REPLACE FUNCTION doms.revoke_sessions_after_principal_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, doms, pg_temp
AS $function$
DECLARE
    revoke_text text;
BEGIN
    IF TG_TABLE_NAME = 'users' THEN
        IF NEW.status = 'ACTIVE' AND NEW.deleted_at IS NULL THEN
            RETURN NEW;
        END IF;
        revoke_text := 'DOMS_USER_' || NEW.status;
        UPDATE doms.user_sessions
           SET session_status = 'REVOKED',
               revoked_at = COALESCE(revoked_at, statement_timestamp()),
               revoke_reason = COALESCE(revoke_reason, revoke_text)
         WHERE user_id = NEW.id AND session_status = 'ACTIVE';
    ELSIF TG_TABLE_NAME = 'tenant_memberships' THEN
        IF NEW.status = 'ACTIVE'
           AND NEW.valid_from <= statement_timestamp()
           AND (NEW.valid_to IS NULL OR NEW.valid_to > statement_timestamp())
           AND OLD.status IS NOT DISTINCT FROM NEW.status
           AND OLD.valid_from IS NOT DISTINCT FROM NEW.valid_from
           AND OLD.valid_to IS NOT DISTINCT FROM NEW.valid_to THEN
            RETURN NEW;
        END IF;
        revoke_text := 'MEMBERSHIP_' || NEW.status;
        UPDATE doms.user_sessions
           SET session_status = 'REVOKED',
               revoked_at = COALESCE(revoked_at, statement_timestamp()),
               revoke_reason = COALESCE(revoke_reason, revoke_text)
         WHERE active_membership_id = NEW.id AND session_status = 'ACTIVE';
    ELSIF TG_TABLE_NAME = 'auth_identities' THEN
        IF NEW.disabled_at IS NULL THEN
            RETURN NEW;
        END IF;
        revoke_text := 'IDENTITY_DISABLED';
        UPDATE doms.user_sessions
           SET session_status = 'REVOKED',
               revoked_at = COALESCE(revoked_at, statement_timestamp()),
               revoke_reason = COALESCE(revoke_reason, revoke_text)
         WHERE auth_identity_id = NEW.id AND session_status = 'ACTIVE';
    ELSIF TG_TABLE_NAME = 'tenants' THEN
        IF NEW.status = 'ACTIVE' AND NEW.deleted_at IS NULL THEN
            RETURN NEW;
        END IF;
        revoke_text := 'TENANT_' || NEW.status;
        UPDATE doms.user_sessions
           SET session_status = 'REVOKED',
               revoked_at = COALESCE(revoked_at, statement_timestamp()),
               revoke_reason = COALESCE(revoke_reason, revoke_text)
         WHERE active_tenant_id = NEW.id AND session_status = 'ACTIVE';
    END IF;
    RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION doms.revoke_sessions_after_principal_change() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_revoke_sessions_after_user_change ON doms.users;
CREATE TRIGGER trg_revoke_sessions_after_user_change
    AFTER UPDATE OF status, deleted_at ON doms.users
    FOR EACH ROW EXECUTE PROCEDURE doms.revoke_sessions_after_principal_change();

DROP TRIGGER IF EXISTS trg_revoke_sessions_after_membership_change ON doms.tenant_memberships;
CREATE TRIGGER trg_revoke_sessions_after_membership_change
    AFTER UPDATE OF status, valid_from, valid_to ON doms.tenant_memberships
    FOR EACH ROW EXECUTE PROCEDURE doms.revoke_sessions_after_principal_change();

DROP TRIGGER IF EXISTS trg_revoke_sessions_after_identity_change ON doms.auth_identities;
CREATE TRIGGER trg_revoke_sessions_after_identity_change
    AFTER UPDATE OF disabled_at ON doms.auth_identities
    FOR EACH ROW EXECUTE PROCEDURE doms.revoke_sessions_after_principal_change();

DROP TRIGGER IF EXISTS trg_revoke_sessions_after_tenant_change ON doms.tenants;
CREATE TRIGGER trg_revoke_sessions_after_tenant_change
    AFTER UPDATE OF status, deleted_at ON doms.tenants
    FOR EACH ROW EXECUTE PROCEDURE doms.revoke_sessions_after_principal_change();

-- Transaction-scoped request authorization. The bound_* names intentionally avoid
-- the tenant_id convention so schema-wide tenant RLS cannot recurse into this table.
CREATE TABLE IF NOT EXISTS doms.request_contexts (
    backend_pid integer NOT NULL,
    transaction_id bigint NOT NULL,
    session_id uuid NOT NULL,
    bound_user_id uuid NOT NULL,
    bound_tenant_id uuid NOT NULL,
    bound_membership_id uuid NOT NULL,
    bound_at timestamptz NOT NULL DEFAULT statement_timestamp(),
    context_expires_at timestamptz NOT NULL,
    PRIMARY KEY (backend_pid, transaction_id),
    FOREIGN KEY (session_id, bound_user_id, bound_tenant_id, bound_membership_id)
        REFERENCES doms.user_sessions(id, user_id, active_tenant_id, active_membership_id)
        ON DELETE CASCADE,
    CONSTRAINT ck_request_context_pid CHECK (backend_pid > 0),
    CONSTRAINT ck_request_context_expiry CHECK (context_expires_at > bound_at)
);

CREATE INDEX IF NOT EXISTS ix_request_contexts_expiry
    ON doms.request_contexts (context_expires_at);

REVOKE ALL ON TABLE doms.request_contexts FROM PUBLIC;

CREATE OR REPLACE FUNCTION doms.bind_request_context(p_session_handle_hash text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, doms, pg_temp
AS $function$
DECLARE
    current_transaction_id bigint := txid_current();
    session_row record;
    existing_context record;
BEGIN
    IF p_session_handle_hash IS NULL
       OR p_session_handle_hash !~ '^[0-9A-Fa-f]{64}$' THEN
        RAISE EXCEPTION 'A SHA-256 session handle hash is required'
            USING ERRCODE = '22023';
    END IF;

    DELETE FROM doms.request_contexts
     WHERE backend_pid = pg_backend_pid()
       AND transaction_id <> current_transaction_id;
    DELETE FROM doms.request_contexts
     WHERE context_expires_at <= statement_timestamp()
        OR bound_at < statement_timestamp() - interval '1 day';

    UPDATE doms.user_sessions
       SET session_status = 'EXPIRED'
     WHERE session_handle_hash = lower(p_session_handle_hash)
       AND session_status = 'ACTIVE'
       AND expires_at <= statement_timestamp();

    SELECT session_data.id AS session_id,
           session_data.user_id,
           session_data.active_tenant_id,
           session_data.active_membership_id,
           session_data.expires_at
      INTO session_row
      FROM doms.user_sessions session_data
      JOIN doms.users doms_user ON doms_user.id = session_data.user_id
      JOIN doms.auth_identities identity_row
        ON identity_row.id = session_data.auth_identity_id
       AND identity_row.user_id = session_data.user_id
      JOIN doms.tenants tenant_row ON tenant_row.id = session_data.active_tenant_id
      JOIN kang.users platform_user ON platform_user.id = doms_user.platform_user_id
     WHERE session_data.session_handle_hash = lower(p_session_handle_hash)
       AND session_data.session_status = 'ACTIVE'
       AND session_data.revoked_at IS NULL
       AND session_data.issued_at <= statement_timestamp()
       AND session_data.expires_at > statement_timestamp()
       AND doms_user.status = 'ACTIVE'
       AND doms_user.deleted_at IS NULL
       AND identity_row.disabled_at IS NULL
       AND identity_row.firebase_project_id = 'kang-84cdd'
       AND identity_row.firebase_tenant_id IS NULL
       AND tenant_row.status = 'ACTIVE'
       AND tenant_row.deleted_at IS NULL
       AND platform_user.firebase_uid = doms_user.firebase_uid
       AND platform_user.status::text = 'active'
       AND platform_user.is_active
       AND platform_user.deleted_at IS NULL
       AND platform_user.locked_at IS NULL
     FOR SHARE OF session_data, doms_user, identity_row, tenant_row, platform_user;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Session is unavailable, expired, revoked, or outside an active membership'
            USING ERRCODE = '28000';
    END IF;

    SELECT * INTO existing_context
      FROM doms.request_contexts request_context
     WHERE request_context.backend_pid = pg_backend_pid()
       AND request_context.transaction_id = current_transaction_id;
    IF FOUND THEN
        IF existing_context.session_id IS DISTINCT FROM session_row.session_id THEN
            RAISE EXCEPTION 'A transaction cannot switch its bound DOMS session'
                USING ERRCODE = '25001';
        END IF;
        RETURN existing_context.bound_tenant_id;
    END IF;

    INSERT INTO doms.request_contexts (
        backend_pid, transaction_id, session_id, bound_user_id,
        bound_tenant_id, bound_membership_id, context_expires_at
    ) VALUES (
        pg_backend_pid(), current_transaction_id, session_row.session_id,
        session_row.user_id, session_row.active_tenant_id,
        session_row.active_membership_id,
        LEAST(session_row.expires_at, statement_timestamp() + interval '15 minutes')
    );

    UPDATE doms.user_sessions
       SET last_seen_at = statement_timestamp()
     WHERE id = session_row.session_id;
    RETURN session_row.active_tenant_id;
END;
$function$;

REVOKE ALL ON FUNCTION doms.bind_request_context(text) FROM PUBLIC;

CREATE OR REPLACE FUNCTION doms.cleanup_request_contexts(p_older_than interval DEFAULT interval '1 day')
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, doms, pg_temp
AS $function$
DECLARE
    deleted_count bigint;
BEGIN
    IF p_older_than < interval '1 hour' THEN
        RAISE EXCEPTION 'Request-context cleanup window must be at least one hour'
            USING ERRCODE = '22023';
    END IF;
    DELETE FROM doms.request_contexts
     WHERE context_expires_at <= statement_timestamp()
        OR bound_at < statement_timestamp() - p_older_than;
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$function$;

REVOKE ALL ON FUNCTION doms.cleanup_request_contexts(interval) FROM PUBLIC;

-- A session is issued before a normal request context can exist. This protected,
-- transaction-local marker lets only the SECURITY DEFINER issuance command read
-- the one candidate membership through FORCE RLS. Runtime roles receive neither
-- SELECT nor DML privileges on this table.
CREATE TABLE IF NOT EXISTS doms.session_issue_contexts (
    backend_pid integer NOT NULL,
    transaction_id bigint NOT NULL,
    bound_user_id uuid NOT NULL REFERENCES doms.users(id) ON DELETE CASCADE,
    bound_tenant_id uuid NOT NULL REFERENCES doms.tenants(id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    expires_at timestamptz NOT NULL DEFAULT (clock_timestamp() + interval '1 minute'),
    PRIMARY KEY (backend_pid, transaction_id),
    CONSTRAINT ck_session_issue_context_pid CHECK (backend_pid > 0),
    CONSTRAINT ck_session_issue_context_expiry CHECK (expires_at > created_at)
);

CREATE INDEX IF NOT EXISTS ix_session_issue_contexts_expiry
    ON doms.session_issue_contexts (expires_at);

REVOKE ALL ON TABLE doms.session_issue_contexts FROM PUBLIC;

CREATE OR REPLACE FUNCTION doms.has_active_session_issue_context(
    p_user_id uuid,
    p_tenant_id uuid
)
RETURNS boolean
LANGUAGE sql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, doms, pg_temp
AS $function$
    SELECT EXISTS (
        SELECT 1
        FROM doms.session_issue_contexts issue_context
        WHERE issue_context.backend_pid = pg_backend_pid()
          AND issue_context.transaction_id = txid_current()
          AND issue_context.bound_user_id = p_user_id
          AND issue_context.bound_tenant_id = p_tenant_id
          AND issue_context.expires_at > statement_timestamp()
    )
$function$;

REVOKE ALL ON FUNCTION doms.has_active_session_issue_context(uuid, uuid) FROM PUBLIC;

CREATE OR REPLACE FUNCTION doms.issue_user_session(
    p_platform_user_id uuid,
    p_firebase_uid text,
    p_provider_code text,
    p_provider_subject text,
    p_session_handle_hash text,
    p_active_tenant_id uuid,
    p_firebase_auth_time timestamptz,
    p_expires_at timestamptz,
    p_assurance_level text DEFAULT 'SINGLE_FACTOR',
    p_ip_address inet DEFAULT NULL,
    p_user_agent text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, doms, pg_temp
AS $function$
DECLARE
    source_row record;
    candidate_user_id uuid;
    new_session_id uuid;
BEGIN
    IF p_session_handle_hash IS NULL
       OR p_session_handle_hash !~ '^[0-9A-Fa-f]{64}$' THEN
        RAISE EXCEPTION 'A SHA-256 session handle hash is required'
            USING ERRCODE = '22023';
    END IF;
    IF p_provider_code NOT IN ('password','google.com')
       OR btrim(COALESCE(p_provider_subject, '')) = ''
       OR (p_provider_code = 'password' AND p_provider_subject <> p_firebase_uid) THEN
        RAISE EXCEPTION 'Invalid Firebase provider subject for session issuance'
            USING ERRCODE = '22023';
    END IF;
    IF p_firebase_auth_time IS NULL
       OR p_firebase_auth_time > statement_timestamp() + interval '5 minutes'
       OR p_expires_at IS NULL
       OR p_expires_at <= statement_timestamp()
       OR p_expires_at > statement_timestamp() + interval '14 days' THEN
        RAISE EXCEPTION 'Session authentication/expiry window is invalid'
            USING ERRCODE = '22023';
    END IF;
    IF p_assurance_level NOT IN ('SINGLE_FACTOR','MULTI_FACTOR','HARDWARE_BACKED') THEN
        RAISE EXCEPTION 'Unsupported session assurance level'
            USING ERRCODE = '22023';
    END IF;

    SELECT doms_user.id
      INTO candidate_user_id
      FROM doms.users doms_user
      JOIN kang.users platform_user
        ON platform_user.id = doms_user.platform_user_id
     WHERE doms_user.platform_user_id = p_platform_user_id
       AND doms_user.firebase_project_id = 'kang-84cdd'
       AND doms_user.firebase_tenant_id IS NULL
       AND doms_user.firebase_uid = p_firebase_uid
       AND doms_user.status = 'ACTIVE'
       AND doms_user.deleted_at IS NULL
       AND platform_user.firebase_uid = p_firebase_uid
       AND platform_user.status::text = 'active'
       AND platform_user.is_active
       AND platform_user.deleted_at IS NULL
       AND platform_user.locked_at IS NULL
     FOR SHARE OF doms_user, platform_user;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Active canonical and DOMS user are required'
            USING ERRCODE = '28000';
    END IF;

    DELETE FROM doms.session_issue_contexts
     WHERE backend_pid = pg_backend_pid();
    DELETE FROM doms.session_issue_contexts
     WHERE expires_at <= statement_timestamp();
    INSERT INTO doms.session_issue_contexts (
        backend_pid, transaction_id, bound_user_id, bound_tenant_id
    ) VALUES (
        pg_backend_pid(), txid_current(), candidate_user_id, p_active_tenant_id
    );

    SELECT doms_user.id AS user_id,
           identity_row.id AS auth_identity_id,
           membership.id AS membership_id
      INTO source_row
      FROM doms.users doms_user
      JOIN kang.users platform_user
        ON platform_user.id = doms_user.platform_user_id
      JOIN doms.auth_identities identity_row
        ON identity_row.user_id = doms_user.id
       AND identity_row.firebase_project_id = 'kang-84cdd'
       AND identity_row.firebase_tenant_id IS NULL
       AND identity_row.firebase_uid = p_firebase_uid
       AND identity_row.provider_code = p_provider_code
       AND identity_row.provider_subject = p_provider_subject
       AND identity_row.disabled_at IS NULL
      JOIN doms.tenant_memberships membership
        ON membership.user_id = doms_user.id
       AND membership.tenant_id = p_active_tenant_id
      JOIN doms.tenants tenant_row ON tenant_row.id = membership.tenant_id
     WHERE doms_user.platform_user_id = p_platform_user_id
       AND doms_user.firebase_project_id = 'kang-84cdd'
       AND doms_user.firebase_tenant_id IS NULL
       AND doms_user.firebase_uid = p_firebase_uid
       AND doms_user.status = 'ACTIVE'
       AND doms_user.deleted_at IS NULL
       AND membership.status = 'ACTIVE'
       AND membership.valid_from <= statement_timestamp()
       AND (membership.valid_to IS NULL OR membership.valid_to > statement_timestamp())
       AND (membership.valid_to IS NULL OR p_expires_at <= membership.valid_to)
       AND tenant_row.status = 'ACTIVE'
       AND tenant_row.deleted_at IS NULL
       AND platform_user.firebase_uid = p_firebase_uid
       AND platform_user.status::text = 'active'
       AND platform_user.is_active
       AND platform_user.deleted_at IS NULL
       AND platform_user.locked_at IS NULL
     FOR SHARE OF doms_user, platform_user, identity_row, membership, tenant_row;
    IF NOT FOUND THEN
        DELETE FROM doms.session_issue_contexts
         WHERE backend_pid = pg_backend_pid()
           AND transaction_id = txid_current();
        RAISE EXCEPTION 'Active canonical user, identity, tenant, and membership are required'
            USING ERRCODE = '28000';
    END IF;

    INSERT INTO doms.user_sessions (
        user_id, auth_identity_id, active_membership_id, active_tenant_id,
        session_handle_hash, session_status, firebase_auth_time,
        assurance_level, issued_at, expires_at, last_seen_at,
        ip_address, user_agent
    ) VALUES (
        source_row.user_id, source_row.auth_identity_id,
        source_row.membership_id, p_active_tenant_id,
        lower(p_session_handle_hash), 'ACTIVE', p_firebase_auth_time,
        p_assurance_level, statement_timestamp(), p_expires_at,
        statement_timestamp(), p_ip_address, p_user_agent
    )
    RETURNING id INTO new_session_id;
    DELETE FROM doms.session_issue_contexts
     WHERE backend_pid = pg_backend_pid()
       AND transaction_id = txid_current();
    RETURN new_session_id;
END;
$function$;

REVOKE ALL ON FUNCTION doms.issue_user_session(
    uuid, text, text, text, text, uuid, timestamptz, timestamptz, text, inet, text
) FROM PUBLIC;

CREATE OR REPLACE FUNCTION doms.revoke_user_session(
    p_session_handle_hash text,
    p_revoke_reason text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, doms, pg_temp
AS $function$
DECLARE
    affected_count integer;
BEGIN
    IF p_session_handle_hash IS NULL
       OR p_session_handle_hash !~ '^[0-9A-Fa-f]{64}$'
       OR btrim(COALESCE(p_revoke_reason, '')) = '' THEN
        RAISE EXCEPTION 'Session hash and revocation reason are required'
            USING ERRCODE = '22023';
    END IF;
    UPDATE doms.user_sessions
       SET session_status = 'REVOKED',
           revoked_at = statement_timestamp(),
           revoke_reason = p_revoke_reason
     WHERE session_handle_hash = lower(p_session_handle_hash)
       AND session_status = 'ACTIVE';
    GET DIAGNOSTICS affected_count = ROW_COUNT;
    RETURN affected_count = 1;
END;
$function$;

REVOKE ALL ON FUNCTION doms.revoke_user_session(text, text) FROM PUBLIC;

CREATE TABLE IF NOT EXISTS doms.login_events (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid REFERENCES doms.tenants(id),
    user_id uuid REFERENCES doms.users(id) ON DELETE SET NULL,
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

COMMENT ON TABLE doms.login_events IS
    'Append-oriented authentication outcome log. Failure detail must be masked and raw Firebase/Google tokens must never be recorded.';

CREATE TABLE IF NOT EXISTS doms.user_devices (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    user_id uuid NOT NULL REFERENCES doms.users(id) ON DELETE CASCADE,
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

COMMENT ON COLUMN doms.user_devices.push_token_encrypted IS
    'Push token ciphertext only; encryption keys must remain in the external secret manager.';

CREATE TABLE IF NOT EXISTS doms.terms_versions (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
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

CREATE TABLE IF NOT EXISTS doms.user_terms_agreements (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    user_id uuid NOT NULL REFERENCES doms.users(id) ON DELETE CASCADE,
    terms_version_id uuid NOT NULL REFERENCES doms.terms_versions(id),
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

CREATE TABLE IF NOT EXISTS doms.api_clients (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
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

CREATE TABLE IF NOT EXISTS doms.api_client_permissions (
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id) ON DELETE CASCADE,
    api_client_id uuid NOT NULL REFERENCES doms.api_clients(id) ON DELETE CASCADE,
    permission_id uuid NOT NULL REFERENCES doms.permissions(id) ON DELETE CASCADE,
    granted_by uuid REFERENCES doms.users(id),
    granted_at timestamptz NOT NULL DEFAULT now(),
    revoked_by uuid REFERENCES doms.users(id),
    revoked_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, api_client_id, permission_id),
    CONSTRAINT ck_api_client_permissions_dates CHECK (
        revoked_at IS NULL OR revoked_at >= granted_at
    )
);

COMMENT ON COLUMN doms.api_clients.secret_hash IS
    'One-way SHA-256 or stronger derived client-secret verifier only; raw client secrets are prohibited.';

CREATE TABLE IF NOT EXISTS doms.code_sets (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid REFERENCES doms.tenants(id) ON DELETE CASCADE,
    code_set varchar(80) NOT NULL,
    code_set_name varchar(200) NOT NULL,
    description text,
    is_system boolean NOT NULL DEFAULT false,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_code_sets_scope
    ON doms.code_sets (COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), code_set);

CREATE TABLE IF NOT EXISTS doms.code_values (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid REFERENCES doms.tenants(id) ON DELETE CASCADE,
    code_set_id uuid NOT NULL REFERENCES doms.code_sets(id) ON DELETE CASCADE,
    code varchar(80) NOT NULL,
    code_name varchar(200) NOT NULL,
    description text,
    sort_order integer NOT NULL DEFAULT 0,
    parent_code_value_id uuid REFERENCES doms.code_values(id),
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    valid_from timestamptz,
    valid_to timestamptz,
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (code_set_id, code),
    CONSTRAINT ck_code_values_dates CHECK (valid_to IS NULL OR valid_from IS NULL OR valid_to > valid_from),
    CONSTRAINT ck_code_values_attributes_secrets CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(attributes)
    )
);

CREATE TABLE IF NOT EXISTS doms.number_sequences (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id) ON DELETE CASCADE,
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

CREATE TABLE IF NOT EXISTS doms.business_calendars (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
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

CREATE TABLE IF NOT EXISTS doms.calendar_dates (
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id) ON DELETE CASCADE,
    calendar_id uuid NOT NULL REFERENCES doms.business_calendars(id) ON DELETE CASCADE,
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

CREATE TABLE IF NOT EXISTS doms.files (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
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
    uploaded_by uuid REFERENCES doms.users(id),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    UNIQUE (tenant_id, storage_provider, storage_bucket, object_key),
    CONSTRAINT ck_files_size CHECK (byte_size >= 0),
    CONSTRAINT ck_files_scan CHECK (malware_scan_status IN ('PENDING','CLEAN','INFECTED','FAILED')),
    CONSTRAINT ck_files_sha256 CHECK (sha256 ~ '^[0-9A-Fa-f]{64}$')
);

COMMENT ON TABLE doms.files IS
    'Object-storage metadata only. File bytes, credentials, and encryption keys are never stored in PostgreSQL.';

CREATE TABLE IF NOT EXISTS doms.entity_files (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    entity_type varchar(80) NOT NULL,
    entity_id uuid NOT NULL,
    file_id uuid NOT NULL REFERENCES doms.files(id),
    document_type varchar(80),
    revision_no integer NOT NULL DEFAULT 1,
    is_primary boolean NOT NULL DEFAULT false,
    effective_at timestamptz,
    expires_at timestamptz,
    created_by uuid REFERENCES doms.users(id),
    updated_by uuid REFERENCES doms.users(id),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, entity_type, entity_id, file_id, revision_no),
    CONSTRAINT ck_entity_files_dates CHECK (
        expires_at IS NULL OR effective_at IS NULL OR expires_at > effective_at
    )
);

CREATE TABLE IF NOT EXISTS doms.entity_notes (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    entity_type varchar(80) NOT NULL,
    entity_id uuid NOT NULL,
    note_type varchar(30) NOT NULL DEFAULT 'INTERNAL',
    note_text text NOT NULL,
    visibility varchar(30) NOT NULL DEFAULT 'INTERNAL',
    created_by uuid REFERENCES doms.users(id),
    updated_by uuid REFERENCES doms.users(id),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    CONSTRAINT ck_entity_notes_visibility CHECK (visibility IN ('INTERNAL','CUSTOMER','CARRIER','PUBLIC'))
);

CREATE TABLE IF NOT EXISTS doms.custom_field_definitions (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
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
    CONSTRAINT ck_custom_field_type CHECK (data_type IN ('TEXT','NUMBER','BOOLEAN','DATE','TIMESTAMP','CODE','JSON')),
    CONSTRAINT ck_custom_field_validation_secrets CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(validation_rule)
    )
);

CREATE TABLE IF NOT EXISTS doms.custom_field_values (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    definition_id uuid NOT NULL REFERENCES doms.custom_field_definitions(id) ON DELETE CASCADE,
    entity_id uuid NOT NULL,
    value_json jsonb NOT NULL,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (definition_id, entity_id),
    CONSTRAINT ck_custom_field_value_secrets CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(value_json)
    )
);

CREATE TABLE IF NOT EXISTS doms.idempotency_keys (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
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
    CONSTRAINT ck_idempotency_expiry CHECK (expires_at > created_at),
    CONSTRAINT ck_idempotency_response_secrets CHECK (
        response_body IS NULL OR NOT doms.jsonb_contains_forbidden_secret_key(response_body)
    )
);

COMMENT ON COLUMN doms.idempotency_keys.response_body IS
    'Optional masked/minimized response snapshot; credentials, tokens, and regulated document payloads are prohibited.';

CREATE TABLE IF NOT EXISTS doms.outbox_events (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
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
    CONSTRAINT ck_outbox_retry CHECK (retry_count >= 0),
    CONSTRAINT ck_outbox_payload_secrets CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(payload)
    )
);

COMMENT ON COLUMN doms.outbox_events.payload IS
    'Business event payload with secrets and authentication tokens removed.';

CREATE TABLE IF NOT EXISTS doms.external_systems (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
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
        NOT doms.jsonb_contains_forbidden_secret_key(config)
    )
);

COMMENT ON COLUMN doms.external_systems.credential_secret_ref IS
    'Opaque external secret-manager reference; never store a credential value here or in config.';

CREATE TABLE IF NOT EXISTS doms.external_id_mappings (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    external_system_id uuid NOT NULL REFERENCES doms.external_systems(id),
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

CREATE TABLE IF NOT EXISTS doms.integration_messages (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    external_system_id uuid REFERENCES doms.external_systems(id),
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

COMMENT ON TABLE doms.integration_messages IS
    'Integration envelope and masked diagnostics. Large or regulated payloads belong in protected object storage and are referenced by URI/hash.';

CREATE TABLE IF NOT EXISTS doms.audit_events (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid REFERENCES doms.tenants(id),
    actor_user_id uuid REFERENCES doms.users(id) ON DELETE SET NULL,
    actor_api_client_id uuid REFERENCES doms.api_clients(id) ON DELETE SET NULL,
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
    CONSTRAINT ck_audit_actor CHECK (NOT (actor_user_id IS NOT NULL AND actor_api_client_id IS NOT NULL)),
    CONSTRAINT ck_audit_before_secrets CHECK (
        before_data_masked IS NULL OR NOT doms.jsonb_contains_forbidden_secret_key(before_data_masked)
    ),
    CONSTRAINT ck_audit_after_secrets CHECK (
        after_data_masked IS NULL OR NOT doms.jsonb_contains_forbidden_secret_key(after_data_masked)
    )
);

COMMENT ON TABLE doms.audit_events IS
    'Append-oriented security and business audit ledger. Before/after documents must be minimized and masked; secrets and authentication tokens are prohibited.';

CREATE OR REPLACE FUNCTION doms.provision_tenant_membership(
    p_platform_user_id uuid,
    p_tenant_id uuid,
    p_actor_service text,
    p_correlation_id text,
    p_actor_user_id uuid DEFAULT NULL,
    p_membership_type text DEFAULT 'EMPLOYEE',
    p_valid_from timestamptz DEFAULT statement_timestamp(),
    p_valid_to timestamptz DEFAULT NULL,
    p_employee_no text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, doms, pg_temp
AS $function$
DECLARE
    target_user_id uuid;
    membership_id uuid := doms.generate_uuid();
BEGIN
    IF p_actor_service IS NULL
       OR p_actor_service !~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,99}$'
       OR doms.text_contains_forbidden_secret(p_actor_service)
       OR p_correlation_id IS NULL
       OR p_correlation_id !~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,99}$'
       OR doms.text_contains_forbidden_secret(p_correlation_id) THEN
        RAISE EXCEPTION 'A non-secret actor service and correlation id are required'
            USING ERRCODE = '22023';
    END IF;
    IF p_membership_type IS NULL
       OR p_membership_type !~ '^[A-Z][A-Z0-9_]{0,29}$' THEN
        RAISE EXCEPTION 'Membership type must be an uppercase enterprise code'
            USING ERRCODE = '22023';
    END IF;
    IF p_valid_from IS NULL
       OR p_valid_from > statement_timestamp()
       OR (p_valid_to IS NOT NULL AND (
            p_valid_to <= p_valid_from OR p_valid_to <= statement_timestamp()
       )) THEN
        RAISE EXCEPTION 'Provisioned ACTIVE membership dates must be currently valid'
            USING ERRCODE = '22023';
    END IF;
    IF p_employee_no IS NOT NULL AND length(btrim(p_employee_no)) > 50 THEN
        RAISE EXCEPTION 'Employee number exceeds 50 characters'
            USING ERRCODE = '22001';
    END IF;

    SELECT doms_user.id
      INTO target_user_id
      FROM doms.users doms_user
      JOIN kang.users platform_user
        ON platform_user.id = doms_user.platform_user_id
      JOIN doms.tenants tenant_row
        ON tenant_row.id = p_tenant_id
       AND tenant_row.status = 'ACTIVE'
       AND tenant_row.deleted_at IS NULL
     WHERE doms_user.platform_user_id = p_platform_user_id
       AND doms_user.firebase_project_id = 'kang-84cdd'
       AND doms_user.firebase_tenant_id IS NULL
       AND doms_user.status = 'ACTIVE'
       AND doms_user.deleted_at IS NULL
       AND platform_user.firebase_uid = doms_user.firebase_uid
       AND platform_user.status::text = 'active'
       AND platform_user.is_active
       AND platform_user.deleted_at IS NULL
       AND platform_user.locked_at IS NULL
     FOR SHARE OF doms_user, platform_user, tenant_row;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Active canonical user, DOMS user, and tenant are required'
            USING ERRCODE = '28000';
    END IF;

    IF p_actor_user_id IS NOT NULL AND NOT EXISTS (
        SELECT 1
        FROM doms.users actor_user
        JOIN kang.users actor_platform
          ON actor_platform.id = actor_user.platform_user_id
        WHERE actor_user.id = p_actor_user_id
          AND actor_user.status = 'ACTIVE'
          AND actor_user.deleted_at IS NULL
          AND actor_platform.firebase_uid = actor_user.firebase_uid
          AND actor_platform.status::text = 'active'
          AND actor_platform.is_active
          AND actor_platform.deleted_at IS NULL
          AND actor_platform.locked_at IS NULL
    ) THEN
        RAISE EXCEPTION 'Actor user must be an active canonical DOMS principal'
            USING ERRCODE = '28000';
    END IF;

    DELETE FROM doms.membership_provision_contexts
     WHERE backend_pid = pg_backend_pid();
    DELETE FROM doms.membership_provision_contexts
     WHERE expires_at <= statement_timestamp();
    INSERT INTO doms.membership_provision_contexts (
        backend_pid, transaction_id, candidate_membership_id,
        bound_user_id, bound_tenant_id, actor_user_id,
        actor_service, correlation_id
    ) VALUES (
        pg_backend_pid(), txid_current(), membership_id,
        target_user_id, p_tenant_id, p_actor_user_id,
        p_actor_service, p_correlation_id
    );

    IF EXISTS (
        SELECT 1
        FROM doms.tenant_memberships membership
        WHERE membership.tenant_id = p_tenant_id
          AND membership.user_id = target_user_id
    ) THEN
        DELETE FROM doms.membership_provision_contexts
         WHERE backend_pid = pg_backend_pid()
           AND transaction_id = txid_current();
        RAISE EXCEPTION 'A membership already exists for this tenant and user'
            USING ERRCODE = '23505';
    END IF;

    INSERT INTO doms.tenant_memberships (
        id, tenant_id, user_id, employee_no, membership_type,
        status, valid_from, valid_to
    ) VALUES (
        membership_id, p_tenant_id, target_user_id,
        NULLIF(btrim(p_employee_no), ''), p_membership_type,
        'ACTIVE', p_valid_from, p_valid_to
    );

    INSERT INTO doms.audit_events (
        tenant_id, actor_user_id, action_code, entity_type, entity_id,
        after_data_masked, reason, correlation_id
    ) VALUES (
        p_tenant_id, p_actor_user_id, 'TENANT_MEMBERSHIP_PROVISIONED',
        'TENANT_MEMBERSHIP', membership_id,
        jsonb_build_object(
            'membership_id', membership_id,
            'user_id', target_user_id,
            'tenant_id', p_tenant_id,
            'membership_type', p_membership_type,
            'actor_service', p_actor_service,
            'valid_from', p_valid_from,
            'valid_to', p_valid_to
        ),
        'Protected tenant membership provisioning command', p_correlation_id
    );

    DELETE FROM doms.membership_provision_contexts
     WHERE backend_pid = pg_backend_pid()
       AND transaction_id = txid_current();
    RETURN membership_id;
END;
$function$;

COMMENT ON FUNCTION doms.provision_tenant_membership(
    uuid, uuid, text, text, uuid, text, timestamptz, timestamptz, text
) IS
    'Creates one currently-active tenant membership through a protected transaction context and appends a correlated audit event; callable only by the tenant provisioner role.';

REVOKE ALL ON FUNCTION doms.provision_tenant_membership(
    uuid, uuid, text, text, uuid, text, timestamptz, timestamptz, text
) FROM PUBLIC;

CREATE TABLE IF NOT EXISTS doms.data_retention_policies (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid REFERENCES doms.tenants(id) ON DELETE CASCADE,
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

CREATE TABLE IF NOT EXISTS doms.legal_holds (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    hold_no varchar(80) NOT NULL,
    hold_name varchar(300) NOT NULL,
    reason text NOT NULL,
    authority_reference varchar(300),
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    effective_at timestamptz NOT NULL,
    released_at timestamptz,
    created_by uuid REFERENCES doms.users(id),
    released_by uuid REFERENCES doms.users(id),
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

CREATE TABLE IF NOT EXISTS doms.legal_hold_entities (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id) ON DELETE CASCADE,
    legal_hold_id uuid NOT NULL REFERENCES doms.legal_holds(id) ON DELETE RESTRICT,
    entity_type varchar(80) NOT NULL,
    entity_id uuid NOT NULL,
    applied_by uuid REFERENCES doms.users(id),
    applied_at timestamptz NOT NULL DEFAULT now(),
    released_by uuid REFERENCES doms.users(id),
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

COMMENT ON TABLE doms.legal_hold_entities IS
    'Entities exempted from retention purge while a legal hold is active; purge jobs must check both active holds and unreleased entity links.';
