-- ETMS final integrity, security, RLS, indexing, and immutable-ledger hardening.
-- PostgreSQL 11 compatible. Applied last after all tables and reference seeds.
-- This module intentionally creates no tables.

CREATE OR REPLACE FUNCTION etms.jsonb_contains_forbidden_secret_key(p_value jsonb)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
AS $function$
DECLARE
    item record;
    element jsonb;
    normalized_key text;
    forbidden_keys constant text[] := ARRAY[
        'password','passwordhash','hashedpassword','rawpassword',
        'idtoken','accesstoken','refreshtoken','firebasetoken','googletoken',
        'rawtoken','sessiontoken','sessionhandle','clientsecret','privatekey',
        'cvv','cvc','pannumber','cardnumber','trackdata','pinblock'
    ]::text[];
BEGIN
    IF p_value IS NULL THEN
        RETURN false;
    END IF;
    IF jsonb_typeof(p_value) = 'object' THEN
        FOR item IN SELECT key, value FROM jsonb_each(p_value)
        LOOP
            normalized_key := lower(regexp_replace(item.key, '[^a-zA-Z0-9]', '', 'g'));
            IF normalized_key = ANY (forbidden_keys)
               OR etms.jsonb_contains_forbidden_secret_key(item.value) THEN
                RETURN true;
            END IF;
        END LOOP;
    ELSIF jsonb_typeof(p_value) = 'array' THEN
        FOR element IN SELECT value FROM jsonb_array_elements(p_value)
        LOOP
            IF etms.jsonb_contains_forbidden_secret_key(element) THEN
                RETURN true;
            END IF;
        END LOOP;
    END IF;
    RETURN false;
END;
$function$;

CREATE OR REPLACE FUNCTION etms.reject_forbidden_json_secrets()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    IF etms.jsonb_contains_forbidden_secret_key(to_jsonb(NEW)) THEN
        RAISE EXCEPTION 'Raw credential/payment secret keys are forbidden in %.%',
            TG_TABLE_SCHEMA, TG_TABLE_NAME USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION etms.is_valid_ciphertext_envelope(p_value text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $function$
    SELECT p_value IS NULL OR p_value ~
        '^enc:v[0-9]+:(gcp-kms|aws-kms|azure-kv):[A-Za-z0-9_./:+@=-]{16,}$';
$function$;

CREATE OR REPLACE FUNCTION etms.is_valid_secret_reference(p_value text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $function$
    SELECT p_value IS NULL OR p_value ~
        '^(projects/[^/]+/secrets/[^/]+/versions/[^/]+|arn:aws:secretsmanager:[A-Za-z0-9_./:+@=-]+|https://[^/]+[.]vault[.]azure[.]net/secrets/[^/]+/[^/]+)$';
$function$;

DO $block$
DECLARE
    target record;
    constraint_name text;
BEGIN
    FOR target IN
        SELECT relation.oid AS table_oid, namespace_row.nspname AS schema_name,
               relation.relname AS table_name, attribute.attname AS column_name
        FROM pg_attribute attribute
        JOIN pg_class relation ON relation.oid = attribute.attrelid
        JOIN pg_namespace namespace_row ON namespace_row.oid = relation.relnamespace
        WHERE namespace_row.nspname = 'etms'
          AND relation.relkind = 'r'
          AND attribute.attnum > 0
          AND NOT attribute.attisdropped
          AND attribute.atttypid IN ('text'::regtype, 'varchar'::regtype, 'bpchar'::regtype)
          AND attribute.attname LIKE '%\_encrypted' ESCAPE '\'
    LOOP
        constraint_name := 'ck_cipher_' || substr(
            md5(target.table_name || '.' || target.column_name), 1, 20
        );
        IF NOT EXISTS (
            SELECT 1 FROM pg_constraint constraint_row
            WHERE constraint_row.conrelid = target.table_oid
              AND constraint_row.conname = constraint_name
        ) THEN
            EXECUTE format(
                'ALTER TABLE %I.%I ADD CONSTRAINT %I CHECK (%I IS NULL OR etms.is_valid_ciphertext_envelope(%I))',
                target.schema_name, target.table_name, constraint_name,
                target.column_name, target.column_name
            );
        END IF;
    END LOOP;

    FOR target IN
        SELECT relation.oid AS table_oid, namespace_row.nspname AS schema_name,
               relation.relname AS table_name, attribute.attname AS column_name
        FROM pg_attribute attribute
        JOIN pg_class relation ON relation.oid = attribute.attrelid
        JOIN pg_namespace namespace_row ON namespace_row.oid = relation.relnamespace
        WHERE namespace_row.nspname = 'etms'
          AND relation.relkind = 'r'
          AND attribute.attnum > 0
          AND NOT attribute.attisdropped
          AND attribute.atttypid IN ('text'::regtype, 'varchar'::regtype, 'bpchar'::regtype)
          AND (
              attribute.attname LIKE '%\_secret\_ref' ESCAPE '\'
              OR attribute.attname LIKE '%\_secret\_reference' ESCAPE '\'
              OR attribute.attname = 'secret_reference'
          )
    LOOP
        constraint_name := 'ck_secret_ref_' || substr(
            md5(target.table_name || '.' || target.column_name), 1, 20
        );
        IF NOT EXISTS (
            SELECT 1 FROM pg_constraint constraint_row
            WHERE constraint_row.conrelid = target.table_oid
              AND constraint_row.conname = constraint_name
        ) THEN
            EXECUTE format(
                'ALTER TABLE %I.%I ADD CONSTRAINT %I CHECK (%I IS NULL OR etms.is_valid_secret_reference(%I))',
                target.schema_name, target.table_name, constraint_name,
                target.column_name, target.column_name
            );
        END IF;
    END LOOP;
END;
$block$;

-- Protected transaction-scoped authentication and tenant authorization context.
CREATE OR REPLACE FUNCTION etms.has_active_session_issue_context(
    p_user_id uuid,
    p_tenant_id uuid
)
RETURNS boolean
LANGUAGE sql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
    SELECT EXISTS (
        SELECT 1 FROM etms.session_issue_contexts context_row
        WHERE context_row.backend_pid = pg_backend_pid()
          AND context_row.transaction_id = txid_current()
          AND context_row.bound_user_id = p_user_id
          AND context_row.bound_tenant_id = p_tenant_id
          AND context_row.expires_at > statement_timestamp()
          AND context_row.consumed_at IS NULL
    );
$function$;

CREATE OR REPLACE FUNCTION etms.has_active_membership_provision_context(
    p_user_id uuid,
    p_tenant_id uuid
)
RETURNS boolean
LANGUAGE sql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
    SELECT EXISTS (
        SELECT 1 FROM etms.membership_provision_contexts context_row
        WHERE context_row.backend_pid = pg_backend_pid()
          AND context_row.transaction_id = txid_current()
          AND context_row.bound_user_id = p_user_id
          AND context_row.bound_tenant_id = p_tenant_id
          AND context_row.expires_at > statement_timestamp()
          AND context_row.consumed_at IS NULL
    );
$function$;

CREATE OR REPLACE FUNCTION etms.current_tenant_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
    SELECT context_row.bound_tenant_id
    FROM etms.request_contexts context_row
    JOIN etms.auth_sessions session_row
      ON session_row.id = context_row.bound_session_id
     AND session_row.user_id = context_row.bound_user_id
     AND session_row.active_tenant_id = context_row.bound_tenant_id
     AND session_row.active_membership_id = context_row.bound_membership_id
    JOIN etms.users user_row ON user_row.id = session_row.user_id
    JOIN etms.auth_identities identity_row
      ON identity_row.id = session_row.auth_identity_id
     AND identity_row.user_id = session_row.user_id
    JOIN etms.tenants tenant_row ON tenant_row.id = session_row.active_tenant_id
    JOIN kang.users platform_user ON platform_user.id = user_row.platform_user_id
    WHERE context_row.backend_pid = pg_backend_pid()
      AND context_row.transaction_id = txid_current()
      AND context_row.expires_at > statement_timestamp()
      AND session_row.session_status = 'ACTIVE'
      AND session_row.revoked_at IS NULL
      AND session_row.expires_at > statement_timestamp()
      AND user_row.status = 'ACTIVE' AND user_row.deleted_at IS NULL
      AND identity_row.disabled_at IS NULL
      AND tenant_row.status = 'ACTIVE' AND tenant_row.deleted_at IS NULL
      AND platform_user.firebase_uid = user_row.firebase_uid
      AND platform_user.status::text = 'active'
      AND platform_user.is_active
      AND platform_user.deleted_at IS NULL
      AND platform_user.locked_at IS NULL;
$function$;

CREATE OR REPLACE FUNCTION etms.current_etms_user_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
    SELECT context_row.bound_user_id
    FROM etms.request_contexts context_row
    JOIN etms.auth_sessions session_row
      ON session_row.id = context_row.bound_session_id
     AND session_row.user_id = context_row.bound_user_id
     AND session_row.active_tenant_id = context_row.bound_tenant_id
     AND session_row.active_membership_id = context_row.bound_membership_id
    JOIN etms.users user_row ON user_row.id = session_row.user_id
    JOIN etms.auth_identities identity_row
      ON identity_row.id = session_row.auth_identity_id
     AND identity_row.user_id = session_row.user_id
    JOIN etms.tenants tenant_row ON tenant_row.id = session_row.active_tenant_id
    JOIN kang.users platform_user ON platform_user.id = user_row.platform_user_id
    WHERE context_row.backend_pid = pg_backend_pid()
      AND context_row.transaction_id = txid_current()
      AND context_row.expires_at > statement_timestamp()
      AND session_row.session_status = 'ACTIVE'
      AND session_row.revoked_at IS NULL
      AND session_row.expires_at > statement_timestamp()
      AND user_row.status = 'ACTIVE' AND user_row.deleted_at IS NULL
      AND identity_row.disabled_at IS NULL
      AND tenant_row.status = 'ACTIVE' AND tenant_row.deleted_at IS NULL
      AND platform_user.firebase_uid = user_row.firebase_uid
      AND platform_user.status::text = 'active'
      AND platform_user.is_active
      AND platform_user.deleted_at IS NULL
      AND platform_user.locked_at IS NULL;
$function$;

COMMENT ON FUNCTION etms.current_tenant_id() IS
    'Fail-closed tenant identity derived from a validated session bound to backend_pid and transaction_id; custom GUC values are ignored.';

CREATE OR REPLACE FUNCTION etms.bind_request_context(p_session_handle_hash text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    transaction_value bigint := txid_current();
    session_data record;
    existing_context record;
    assurance_value smallint;
BEGIN
    IF p_session_handle_hash IS NULL OR p_session_handle_hash !~ '^[0-9A-Fa-f]{64}$' THEN
        RAISE EXCEPTION 'A SHA-256 server-session handle hash is required'
            USING ERRCODE = '22023';
    END IF;
    DELETE FROM etms.request_contexts
     WHERE backend_pid = pg_backend_pid()
       AND (transaction_id <> transaction_value OR expires_at <= statement_timestamp());
    UPDATE etms.auth_sessions SET session_status = 'EXPIRED'
     WHERE firebase_session_id_hash = lower(p_session_handle_hash)
       AND session_status = 'ACTIVE' AND expires_at <= statement_timestamp();

    SELECT session_row.id AS session_id, session_row.user_id,
           session_row.active_tenant_id, session_row.active_membership_id,
           session_row.expires_at, session_row.assurance_level
      INTO session_data
      FROM etms.auth_sessions session_row
      JOIN etms.users user_row ON user_row.id = session_row.user_id
      JOIN etms.auth_identities identity_row
        ON identity_row.id = session_row.auth_identity_id AND identity_row.user_id = session_row.user_id
      JOIN etms.tenants tenant_row ON tenant_row.id = session_row.active_tenant_id
      JOIN kang.users platform_user ON platform_user.id = user_row.platform_user_id
     WHERE session_row.firebase_session_id_hash = lower(p_session_handle_hash)
       AND session_row.session_status = 'ACTIVE' AND session_row.revoked_at IS NULL
       AND session_row.expires_at > statement_timestamp()
       AND user_row.status = 'ACTIVE' AND user_row.deleted_at IS NULL
       AND identity_row.disabled_at IS NULL
       AND tenant_row.status = 'ACTIVE' AND tenant_row.deleted_at IS NULL
       AND platform_user.firebase_uid = user_row.firebase_uid
       AND platform_user.status::text = 'active' AND platform_user.is_active
       AND platform_user.deleted_at IS NULL AND platform_user.locked_at IS NULL
     FOR SHARE OF session_row, user_row, identity_row, tenant_row, platform_user;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Session is expired, revoked, or unavailable'
            USING ERRCODE = '28000';
    END IF;

    SELECT * INTO existing_context FROM etms.request_contexts context_row
     WHERE context_row.backend_pid = pg_backend_pid()
       AND context_row.transaction_id = transaction_value;
    IF FOUND THEN
        IF existing_context.bound_session_id IS DISTINCT FROM session_data.session_id THEN
            RAISE EXCEPTION 'A transaction cannot switch its bound ETMS session'
                USING ERRCODE = '25001';
        END IF;
        RETURN existing_context.bound_tenant_id;
    END IF;
    assurance_value := CASE session_data.assurance_level
        WHEN 'HARDWARE_BACKED' THEN 3 WHEN 'MULTI_FACTOR' THEN 2 ELSE 1 END;
    INSERT INTO etms.request_contexts (
        backend_pid, transaction_id, bound_tenant_id, bound_user_id,
        bound_membership_id, bound_session_id, request_id, assurance_level,
        established_at, expires_at, context_digest
    ) VALUES (
        pg_backend_pid(), transaction_value, session_data.active_tenant_id,
        session_data.user_id, session_data.active_membership_id, session_data.session_id,
        etms.generate_uuid(), assurance_value, statement_timestamp(),
        LEAST(session_data.expires_at, statement_timestamp() + interval '15 minutes'),
        lower(p_session_handle_hash)
    );
    UPDATE etms.auth_sessions SET last_seen_at = statement_timestamp()
     WHERE id = session_data.session_id;
    RETURN session_data.active_tenant_id;
END;
$function$;

CREATE OR REPLACE FUNCTION etms.cleanup_request_contexts(
    p_older_than interval DEFAULT interval '1 day'
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE deleted_count bigint;
BEGIN
    IF p_older_than < interval '1 hour' THEN
        RAISE EXCEPTION 'Context cleanup window must be at least one hour'
            USING ERRCODE = '22023';
    END IF;
    DELETE FROM etms.request_contexts
     WHERE expires_at <= statement_timestamp()
        OR established_at < statement_timestamp() - p_older_than;
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$function$;

CREATE OR REPLACE FUNCTION etms.provision_tenant_membership(
    p_tenant_id uuid,
    p_user_id uuid,
    p_actor_user_id uuid,
    p_membership_type text,
    p_employee_no text,
    p_valid_from timestamptz,
    p_valid_to timestamptz
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    membership_id_value uuid;
    context_user_id uuid;
    digest_value text;
BEGIN
    IF p_membership_type NOT IN ('EMPLOYEE','CONTRACTOR','CARRIER','CUSTOMER','SYSTEM','AUDITOR')
       OR p_valid_from IS NULL
       OR (p_valid_to IS NOT NULL AND p_valid_to <= p_valid_from) THEN
        RAISE EXCEPTION 'Membership type or validity window is invalid'
            USING ERRCODE = '22023';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM etms.tenants
        WHERE id = p_tenant_id AND status = 'ACTIVE' AND deleted_at IS NULL
    ) OR NOT EXISTS (
        SELECT 1 FROM etms.users
        WHERE id = p_user_id AND status = 'ACTIVE' AND deleted_at IS NULL
    ) OR NOT EXISTS (
        SELECT 1 FROM etms.users
        WHERE id = p_actor_user_id AND status = 'ACTIVE' AND deleted_at IS NULL
    ) THEN
        RAISE EXCEPTION 'Tenant, subject user, or actor is unavailable'
            USING ERRCODE = '23503';
    END IF;

    context_user_id := etms.current_etms_user_id();
    IF context_user_id IS NULL THEN
        IF session_user <> current_user THEN
            RAISE EXCEPTION 'An authenticated ETMS request context is required'
                USING ERRCODE = '28000';
        END IF;
    ELSIF etms.current_tenant_id() IS DISTINCT FROM p_tenant_id
          OR context_user_id IS DISTINCT FROM p_actor_user_id THEN
        RAISE EXCEPTION 'Provisioning actor/tenant does not match the request context'
            USING ERRCODE = '42501';
    END IF;

    digest_value := md5(random()::text || clock_timestamp()::text) ||
                    md5(txid_current()::text || p_user_id::text);
    INSERT INTO etms.membership_provision_contexts (
        backend_pid, transaction_id, bound_tenant_id, bound_user_id,
        actor_user_id, provision_action, justification,
        established_at, expires_at, context_digest
    ) VALUES (
        pg_backend_pid(), txid_current(), p_tenant_id, p_user_id,
        p_actor_user_id, 'CREATE', 'Authorized ETMS membership provisioning',
        statement_timestamp(), statement_timestamp() + interval '1 minute', digest_value
    )
    ON CONFLICT (backend_pid, transaction_id) DO UPDATE
    SET bound_tenant_id = EXCLUDED.bound_tenant_id,
        bound_user_id = EXCLUDED.bound_user_id,
        actor_user_id = EXCLUDED.actor_user_id,
        provision_action = EXCLUDED.provision_action,
        justification = EXCLUDED.justification,
        established_at = EXCLUDED.established_at,
        expires_at = EXCLUDED.expires_at,
        consumed_at = NULL,
        context_digest = EXCLUDED.context_digest;

    SELECT id INTO membership_id_value
    FROM etms.tenant_memberships
    WHERE tenant_id = p_tenant_id AND user_id = p_user_id
    FOR UPDATE;
    IF FOUND THEN
        UPDATE etms.tenant_memberships
           SET membership_type = p_membership_type,
               employee_no = p_employee_no,
               status = 'ACTIVE', valid_from = p_valid_from, valid_to = p_valid_to
         WHERE id = membership_id_value;
    ELSE
        INSERT INTO etms.tenant_memberships (
            tenant_id, user_id, employee_no, membership_type,
            status, valid_from, valid_to
        ) VALUES (
            p_tenant_id, p_user_id, p_employee_no, p_membership_type,
            'ACTIVE', p_valid_from, p_valid_to
        ) RETURNING id INTO membership_id_value;
    END IF;
    UPDATE etms.membership_provision_contexts
       SET bound_membership_id = membership_id_value, consumed_at = statement_timestamp()
     WHERE backend_pid = pg_backend_pid() AND transaction_id = txid_current();
    RETURN membership_id_value;
END;
$function$;

CREATE OR REPLACE FUNCTION etms.issue_auth_session(
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
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    user_id_value uuid;
    membership_row record;
    identity_id_value uuid;
    session_id_value uuid;
    assurance_value smallint;
BEGIN
    IF p_session_handle_hash IS NULL OR p_session_handle_hash !~ '^[0-9A-Fa-f]{64}$'
       OR p_provider_code NOT IN ('password','google.com')
       OR btrim(COALESCE(p_provider_subject, '')) = ''
       OR (p_provider_code = 'password' AND p_provider_subject <> p_firebase_uid) THEN
        RAISE EXCEPTION 'Invalid Firebase provider/session subject'
            USING ERRCODE = '22023';
    END IF;
    IF p_firebase_auth_time IS NULL
       OR p_firebase_auth_time > statement_timestamp() + interval '5 minutes'
       OR p_expires_at IS NULL OR p_expires_at <= statement_timestamp()
       OR p_expires_at > statement_timestamp() + interval '14 days'
       OR p_assurance_level NOT IN ('SINGLE_FACTOR','MULTI_FACTOR','HARDWARE_BACKED') THEN
        RAISE EXCEPTION 'Invalid authentication/session validity window'
            USING ERRCODE = '22023';
    END IF;
    SELECT user_row.id INTO user_id_value
    FROM etms.users user_row
    JOIN kang.users platform_user ON platform_user.id = user_row.platform_user_id
    WHERE user_row.platform_user_id = p_platform_user_id
      AND user_row.firebase_project_id = 'kang-84cdd'
      AND user_row.firebase_tenant_id IS NULL
      AND user_row.firebase_uid = p_firebase_uid
      AND user_row.status = 'ACTIVE' AND user_row.deleted_at IS NULL
      AND platform_user.firebase_uid = p_firebase_uid
      AND platform_user.status::text = 'active'
      AND platform_user.is_active AND platform_user.deleted_at IS NULL
      AND platform_user.locked_at IS NULL;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Canonical ETMS/Firebase user mapping is unavailable'
            USING ERRCODE = '28000';
    END IF;
    SELECT identity_row.id INTO identity_id_value
    FROM etms.auth_identities identity_row
    WHERE identity_row.user_id = user_id_value
      AND identity_row.provider_code = p_provider_code
      AND identity_row.provider_subject = p_provider_subject
      AND identity_row.issuer = 'https://securetoken.google.com/kang-84cdd'
      AND identity_row.audience = 'kang-84cdd'
      AND identity_row.firebase_tenant_id IS NULL
      AND identity_row.disabled_at IS NULL;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Linked Firebase identity is unavailable'
            USING ERRCODE = '28000';
    END IF;

    assurance_value := CASE p_assurance_level
        WHEN 'HARDWARE_BACKED' THEN 3 WHEN 'MULTI_FACTOR' THEN 2 ELSE 1 END;
    INSERT INTO etms.session_issue_contexts (
        backend_pid, transaction_id, bound_tenant_id, bound_user_id,
        bound_membership_id, issue_purpose, token_fingerprint,
        assurance_level, established_at, expires_at, context_digest
    ) VALUES (
        pg_backend_pid(), txid_current(), p_active_tenant_id, user_id_value,
        NULL, 'LOGIN', lower(p_session_handle_hash), assurance_value,
        statement_timestamp(), statement_timestamp() + interval '1 minute',
        lower(p_session_handle_hash)
    );
    SELECT membership_data.id, membership_data.valid_to INTO membership_row
    FROM etms.tenant_memberships membership_data
    JOIN etms.tenants tenant_row ON tenant_row.id = membership_data.tenant_id
    WHERE membership_data.user_id = user_id_value
      AND membership_data.tenant_id = p_active_tenant_id
      AND membership_data.status = 'ACTIVE'
      AND membership_data.valid_from <= statement_timestamp()
      AND (membership_data.valid_to IS NULL OR membership_data.valid_to > statement_timestamp())
      AND tenant_row.status = 'ACTIVE' AND tenant_row.deleted_at IS NULL
    FOR SHARE OF membership_data, tenant_row;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Active tenant membership is unavailable'
            USING ERRCODE = '28000';
    END IF;
    IF membership_row.valid_to IS NOT NULL THEN
        p_expires_at := LEAST(p_expires_at, membership_row.valid_to);
    END IF;
    INSERT INTO etms.auth_sessions (
        user_id, auth_identity_id, active_tenant_id, active_membership_id,
        firebase_session_id_hash, firebase_auth_time, assurance_level,
        issued_at, expires_at, last_seen_at, ip_address, user_agent, session_status
    ) VALUES (
        user_id_value, identity_id_value, p_active_tenant_id, membership_row.id,
        lower(p_session_handle_hash), p_firebase_auth_time, p_assurance_level,
        statement_timestamp(), p_expires_at, statement_timestamp(),
        p_ip_address, p_user_agent, 'ACTIVE'
    ) RETURNING id INTO session_id_value;
    UPDATE etms.session_issue_contexts
       SET bound_membership_id = membership_row.id,
           issued_session_id = session_id_value,
           consumed_at = statement_timestamp()
     WHERE backend_pid = pg_backend_pid() AND transaction_id = txid_current();
    RETURN session_id_value;
END;
$function$;

DO $block$
DECLARE
    target record;
BEGIN
    FOR target IN
        SELECT DISTINCT namespace_row.nspname AS schema_name, relation.relname AS table_name
        FROM pg_attribute attribute
        JOIN pg_class relation ON relation.oid = attribute.attrelid
        JOIN pg_namespace namespace_row ON namespace_row.oid = relation.relnamespace
        WHERE namespace_row.nspname = 'etms'
          AND relation.relkind = 'r'
          AND attribute.attnum > 0
          AND NOT attribute.attisdropped
          AND attribute.atttypid = 'jsonb'::regtype
    LOOP
        EXECUTE format(
            'DROP TRIGGER IF EXISTS trg_reject_json_secrets ON %I.%I',
            target.schema_name, target.table_name
        );
        EXECUTE format(
            'CREATE TRIGGER trg_reject_json_secrets BEFORE INSERT OR UPDATE ON %I.%I '
            'FOR EACH ROW EXECUTE PROCEDURE etms.reject_forbidden_json_secrets()',
            target.schema_name, target.table_name
        );
    END LOOP;
END;
$block$;

CREATE OR REPLACE FUNCTION etms.validate_auth_identity_owner()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    owner_row record;
BEGIN
    SELECT firebase_uid, firebase_project_id, firebase_tenant_id
      INTO owner_row
      FROM etms.users
     WHERE id = NEW.user_id AND deleted_at IS NULL;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Authentication identity owner is unavailable'
            USING ERRCODE = '23503';
    END IF;
    IF owner_row.firebase_project_id <> 'kang-84cdd'
       OR owner_row.firebase_tenant_id IS NOT NULL
       OR NEW.issuer <> 'https://securetoken.google.com/kang-84cdd'
       OR NEW.audience <> 'kang-84cdd'
       OR NEW.firebase_tenant_id IS NOT NULL THEN
        RAISE EXCEPTION 'Authentication identity is outside the canonical Firebase scope'
            USING ERRCODE = '23514';
    END IF;
    IF NEW.provider_code = 'password' AND NEW.provider_subject <> owner_row.firebase_uid THEN
        RAISE EXCEPTION 'Password provider subject must equal the canonical Firebase UID'
            USING ERRCODE = '23514';
    END IF;
    IF TG_OP = 'UPDATE' AND (
        NEW.user_id IS DISTINCT FROM OLD.user_id
        OR NEW.issuer IS DISTINCT FROM OLD.issuer
        OR NEW.audience IS DISTINCT FROM OLD.audience
        OR NEW.firebase_tenant_id IS DISTINCT FROM OLD.firebase_tenant_id
        OR NEW.provider_code IS DISTINCT FROM OLD.provider_code
        OR NEW.provider_subject IS DISTINCT FROM OLD.provider_subject
    ) THEN
        RAISE EXCEPTION 'Authentication identity ownership and subject are immutable'
            USING ERRCODE = '55000';
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_validate_auth_identity_owner ON etms.auth_identities;
CREATE TRIGGER trg_validate_auth_identity_owner
    BEFORE INSERT OR UPDATE ON etms.auth_identities
    FOR EACH ROW EXECUTE PROCEDURE etms.validate_auth_identity_owner();

CREATE OR REPLACE FUNCTION etms.protect_user_subject()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    IF NEW.platform_user_id IS DISTINCT FROM OLD.platform_user_id
       OR NEW.firebase_project_id IS DISTINCT FROM OLD.firebase_project_id
       OR NEW.firebase_tenant_id IS DISTINCT FROM OLD.firebase_tenant_id
       OR NEW.firebase_uid IS DISTINCT FROM OLD.firebase_uid THEN
        RAISE EXCEPTION 'Canonical platform/Firebase user subject is immutable'
            USING ERRCODE = '55000';
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_protect_user_subject ON etms.users;
CREATE TRIGGER trg_protect_user_subject
    BEFORE UPDATE ON etms.users
    FOR EACH ROW EXECUTE PROCEDURE etms.protect_user_subject();

CREATE OR REPLACE FUNCTION etms.protect_membership_subject()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    IF NEW.tenant_id IS DISTINCT FROM OLD.tenant_id
       OR NEW.user_id IS DISTINCT FROM OLD.user_id THEN
        RAISE EXCEPTION 'Membership tenant/user subject is immutable'
            USING ERRCODE = '55000';
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_protect_membership_subject ON etms.tenant_memberships;
CREATE TRIGGER trg_protect_membership_subject
    BEFORE UPDATE ON etms.tenant_memberships
    FOR EACH ROW EXECUTE PROCEDURE etms.protect_membership_subject();

CREATE OR REPLACE FUNCTION etms.revoke_sessions_after_principal_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
BEGIN
    IF TG_TABLE_NAME = 'users' THEN
        IF NEW.status <> 'ACTIVE' OR NEW.deleted_at IS NOT NULL THEN
            UPDATE etms.auth_sessions
               SET session_status = 'REVOKED',
                   revoked_at = COALESCE(revoked_at, statement_timestamp()),
                   revoke_reason = COALESCE(revoke_reason, 'USER_DISABLED')
             WHERE user_id = NEW.id AND session_status = 'ACTIVE';
        END IF;
    ELSIF TG_TABLE_NAME = 'tenant_memberships' THEN
        IF NEW.status <> 'ACTIVE'
           OR NEW.valid_from > statement_timestamp()
           OR (NEW.valid_to IS NOT NULL AND NEW.valid_to <= statement_timestamp()) THEN
            UPDATE etms.auth_sessions
               SET session_status = 'REVOKED',
                   revoked_at = COALESCE(revoked_at, statement_timestamp()),
                   revoke_reason = COALESCE(revoke_reason, 'MEMBERSHIP_DISABLED')
             WHERE active_membership_id = NEW.id AND session_status = 'ACTIVE';
        END IF;
    ELSIF TG_TABLE_NAME = 'auth_identities' THEN
        IF NEW.disabled_at IS NOT NULL THEN
            UPDATE etms.auth_sessions
               SET session_status = 'REVOKED',
                   revoked_at = COALESCE(revoked_at, statement_timestamp()),
                   revoke_reason = COALESCE(revoke_reason, 'IDENTITY_DISABLED')
             WHERE auth_identity_id = NEW.id AND session_status = 'ACTIVE';
        END IF;
    ELSIF TG_TABLE_NAME = 'tenants' THEN
        IF NEW.status <> 'ACTIVE' OR NEW.deleted_at IS NOT NULL THEN
            UPDATE etms.auth_sessions
               SET session_status = 'REVOKED',
                   revoked_at = COALESCE(revoked_at, statement_timestamp()),
                   revoke_reason = COALESCE(revoke_reason, 'TENANT_DISABLED')
             WHERE active_tenant_id = NEW.id AND session_status = 'ACTIVE';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_revoke_sessions_after_user_change ON etms.users;
CREATE TRIGGER trg_revoke_sessions_after_user_change
    AFTER UPDATE OF status, deleted_at ON etms.users
    FOR EACH ROW EXECUTE PROCEDURE etms.revoke_sessions_after_principal_change();

DROP TRIGGER IF EXISTS trg_revoke_sessions_after_membership_change ON etms.tenant_memberships;
CREATE TRIGGER trg_revoke_sessions_after_membership_change
    AFTER UPDATE OF status, valid_from, valid_to ON etms.tenant_memberships
    FOR EACH ROW EXECUTE PROCEDURE etms.revoke_sessions_after_principal_change();

DROP TRIGGER IF EXISTS trg_revoke_sessions_after_identity_change ON etms.auth_identities;
CREATE TRIGGER trg_revoke_sessions_after_identity_change
    AFTER UPDATE OF disabled_at ON etms.auth_identities
    FOR EACH ROW EXECUTE PROCEDURE etms.revoke_sessions_after_principal_change();

DROP TRIGGER IF EXISTS trg_revoke_sessions_after_tenant_change ON etms.tenants;
CREATE TRIGGER trg_revoke_sessions_after_tenant_change
    AFTER UPDATE OF status, deleted_at ON etms.tenants
    FOR EACH ROW EXECUTE PROCEDURE etms.revoke_sessions_after_principal_change();

-- Planning, rating, assignment, capacity, and appointment invariants.
CREATE OR REPLACE FUNCTION etms.validate_scenario_order_revision()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM etms.transport_order_revisions revision_row
        WHERE revision_row.id = NEW.order_revision_id
          AND revision_row.order_id = NEW.order_id
          AND revision_row.tenant_id = NEW.tenant_id
    ) THEN
        RAISE EXCEPTION 'Planning scenario order revision must belong to the same order and tenant'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_validate_scenario_order_revision ON etms.planning_scenario_orders;
CREATE TRIGGER trg_validate_scenario_order_revision
    BEFORE INSERT OR UPDATE OF tenant_id, order_id, order_revision_id
    ON etms.planning_scenario_orders
    FOR EACH ROW EXECUTE PROCEDURE etms.validate_scenario_order_revision();

CREATE OR REPLACE FUNCTION etms.protect_committed_scenario_input()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    scenario_id_value uuid;
    source_row jsonb;
BEGIN
    source_row := CASE WHEN TG_OP = 'DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
    scenario_id_value := NULLIF(source_row ->> TG_ARGV[0], '')::uuid;
    IF EXISTS (
        SELECT 1 FROM etms.planning_scenarios scenario_row
        WHERE scenario_row.id = scenario_id_value
          AND (scenario_row.is_committed OR scenario_row.status IN ('COMMITTED','SUPERSEDED'))
    ) THEN
        RAISE EXCEPTION 'Committed planning scenario inputs are immutable; create a new scenario'
            USING ERRCODE = '55000';
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_protect_scenario_orders ON etms.planning_scenario_orders;
CREATE TRIGGER trg_protect_scenario_orders
    BEFORE INSERT OR UPDATE OR DELETE ON etms.planning_scenario_orders
    FOR EACH ROW EXECUTE PROCEDURE etms.protect_committed_scenario_input('scenario_id');

DROP TRIGGER IF EXISTS trg_protect_scenario_constraints ON etms.planning_constraints;
CREATE TRIGGER trg_protect_scenario_constraints
    BEFORE INSERT OR UPDATE OR DELETE ON etms.planning_constraints
    FOR EACH ROW EXECUTE PROCEDURE etms.protect_committed_scenario_input('scenario_id');

CREATE OR REPLACE FUNCTION etms.protect_committed_scenario_header()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    IF (OLD.is_committed OR OLD.status IN ('COMMITTED','SUPERSEDED')) AND (
        NEW.planning_horizon_from IS DISTINCT FROM OLD.planning_horizon_from
        OR NEW.planning_horizon_to IS DISTINCT FROM OLD.planning_horizon_to
        OR NEW.planning_scope IS DISTINCT FROM OLD.planning_scope
        OR NEW.objective_weights IS DISTINCT FROM OLD.objective_weights
        OR NEW.base_scenario_id IS DISTINCT FROM OLD.base_scenario_id
        OR (OLD.is_committed AND NOT NEW.is_committed)
    ) THEN
        RAISE EXCEPTION 'Committed planning scenario definition is immutable'
            USING ERRCODE = '55000';
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_protect_committed_scenario_header ON etms.planning_scenarios;
CREATE TRIGGER trg_protect_committed_scenario_header
    BEFORE UPDATE ON etms.planning_scenarios
    FOR EACH ROW EXECUTE PROCEDURE etms.protect_committed_scenario_header();

CREATE OR REPLACE FUNCTION etms.prevent_used_revision_mutation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
BEGIN
    IF EXISTS (
        SELECT 1 FROM etms.planning_scenario_orders scenario_order
        JOIN etms.planning_scenarios scenario_row ON scenario_row.id = scenario_order.scenario_id
        WHERE scenario_order.order_revision_id = OLD.id
          AND (scenario_row.is_committed OR scenario_row.status IN ('COMMITTED','SUPERSEDED'))
    ) THEN
        RAISE EXCEPTION 'Order revision used by a committed plan is immutable'
            USING ERRCODE = '55000';
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_prevent_used_revision_mutation ON etms.transport_order_revisions;
CREATE TRIGGER trg_prevent_used_revision_mutation
    BEFORE UPDATE OR DELETE ON etms.transport_order_revisions
    FOR EACH ROW EXECUTE PROCEDURE etms.prevent_used_revision_mutation();

CREATE OR REPLACE FUNCTION etms.prevent_contract_version_overlap()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
BEGIN
    IF NEW.status NOT IN ('APPROVED','ACTIVE') THEN
        RETURN NEW;
    END IF;
    PERFORM pg_advisory_xact_lock(hashtext('contract-version:' || NEW.contract_id::text));
    IF EXISTS (
        SELECT 1 FROM etms.rate_contract_versions existing_row
        WHERE existing_row.contract_id = NEW.contract_id
          AND existing_row.id <> NEW.id
          AND existing_row.status IN ('APPROVED','ACTIVE')
          AND existing_row.effective_from <= COALESCE(NEW.effective_to, 'infinity'::date)
          AND NEW.effective_from <= COALESCE(existing_row.effective_to, 'infinity'::date)
    ) THEN
        RAISE EXCEPTION 'Approved/active contract version effective periods may not overlap'
            USING ERRCODE = '23P01';
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_prevent_contract_version_overlap ON etms.rate_contract_versions;
CREATE TRIGGER trg_prevent_contract_version_overlap
    BEFORE INSERT OR UPDATE OF contract_id, effective_from, effective_to, status
    ON etms.rate_contract_versions
    FOR EACH ROW EXECUTE PROCEDURE etms.prevent_contract_version_overlap();

CREATE OR REPLACE FUNCTION etms.prevent_rate_lane_overlap()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
BEGIN
    PERFORM pg_advisory_xact_lock(hashtext('rate-lane:' || NEW.contract_version_id::text));
    IF EXISTS (
        SELECT 1 FROM etms.rate_lanes existing_row
        WHERE existing_row.contract_version_id = NEW.contract_version_id
          AND existing_row.id <> NEW.id
          AND existing_row.lane_id IS NOT DISTINCT FROM NEW.lane_id
          AND existing_row.origin_location_id IS NOT DISTINCT FROM NEW.origin_location_id
          AND existing_row.origin_region_id IS NOT DISTINCT FROM NEW.origin_region_id
          AND existing_row.destination_location_id IS NOT DISTINCT FROM NEW.destination_location_id
          AND existing_row.destination_region_id IS NOT DISTINCT FROM NEW.destination_region_id
          AND existing_row.mode_code = NEW.mode_code
          AND existing_row.service_level_id IS NOT DISTINCT FROM NEW.service_level_id
          AND existing_row.equipment_type_id IS NOT DISTINCT FROM NEW.equipment_type_id
          AND existing_row.valid_from <= COALESCE(NEW.valid_to, 'infinity'::date)
          AND NEW.valid_from <= COALESCE(existing_row.valid_to, 'infinity'::date)
    ) THEN
        RAISE EXCEPTION 'Rate lane periods may not overlap for the same commercial scope'
            USING ERRCODE = '23P01';
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_prevent_rate_lane_overlap ON etms.rate_lanes;
CREATE TRIGGER trg_prevent_rate_lane_overlap
    BEFORE INSERT OR UPDATE ON etms.rate_lanes
    FOR EACH ROW EXECUTE PROCEDURE etms.prevent_rate_lane_overlap();

CREATE OR REPLACE FUNCTION etms.prevent_rate_tier_overlap()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
BEGIN
    PERFORM pg_advisory_xact_lock(hashtext('rate-tier:' || NEW.rate_rule_id::text));
    IF EXISTS (
        SELECT 1 FROM etms.rate_rule_tiers existing_row
        WHERE existing_row.rate_rule_id = NEW.rate_rule_id
          AND existing_row.id <> NEW.id
          AND (existing_row.to_value IS NULL OR NEW.from_value < existing_row.to_value)
          AND (NEW.to_value IS NULL OR existing_row.from_value < NEW.to_value)
    ) THEN
        RAISE EXCEPTION 'Rate tier numeric ranges may not overlap'
            USING ERRCODE = '23P01';
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_prevent_rate_tier_overlap ON etms.rate_rule_tiers;
CREATE TRIGGER trg_prevent_rate_tier_overlap
    BEFORE INSERT OR UPDATE ON etms.rate_rule_tiers
    FOR EACH ROW EXECUTE PROCEDURE etms.prevent_rate_tier_overlap();

CREATE OR REPLACE FUNCTION etms.validate_capacity_reservation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    run_row record;
    used_weight numeric(20,6);
    used_volume numeric(20,6);
BEGIN
    IF NEW.status IN ('RELEASED','CANCELLED','EXPIRED') THEN RETURN NEW; END IF;
    PERFORM pg_advisory_xact_lock(hashtext('run-capacity:' || NEW.run_id::text));
    SELECT capacity_weight_kg, capacity_volume_m3
      INTO run_row
      FROM etms.transport_runs
     WHERE id = NEW.run_id AND tenant_id = NEW.tenant_id
     FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Capacity reservation run is unavailable in the tenant'
            USING ERRCODE = '23503';
    END IF;
    SELECT COALESCE(sum(reserved_weight_kg), 0), COALESCE(sum(reserved_volume_m3), 0)
      INTO used_weight, used_volume
      FROM etms.capacity_reservations existing_row
     WHERE existing_row.run_id = NEW.run_id
       AND existing_row.id <> NEW.id
       AND existing_row.status NOT IN ('RELEASED','CANCELLED','EXPIRED');
    IF run_row.capacity_weight_kg IS NOT NULL
       AND used_weight + NEW.reserved_weight_kg > run_row.capacity_weight_kg THEN
        RAISE EXCEPTION 'Run weight capacity exceeded'
            USING ERRCODE = '23514';
    END IF;
    IF run_row.capacity_volume_m3 IS NOT NULL
       AND used_volume + NEW.reserved_volume_m3 > run_row.capacity_volume_m3 THEN
        RAISE EXCEPTION 'Run volume capacity exceeded'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_validate_capacity_reservation ON etms.capacity_reservations;
CREATE TRIGGER trg_validate_capacity_reservation
    BEFORE INSERT OR UPDATE ON etms.capacity_reservations
    FOR EACH ROW EXECUTE PROCEDURE etms.validate_capacity_reservation();

CREATE OR REPLACE FUNCTION etms.prevent_dock_appointment_overlap()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
BEGIN
    IF NEW.status IN ('CANCELLED','REJECTED') THEN RETURN NEW; END IF;
    IF NEW.dock_id IS NOT NULL THEN
        PERFORM pg_advisory_xact_lock(hashtext('dock-slot:' || NEW.dock_id::text));
    ELSIF NEW.vehicle_id IS NOT NULL THEN
        PERFORM pg_advisory_xact_lock(hashtext('vehicle-slot:' || NEW.vehicle_id::text));
    END IF;
    IF EXISTS (
        SELECT 1 FROM etms.dock_appointments existing_row
        WHERE existing_row.tenant_id = NEW.tenant_id
          AND existing_row.id <> NEW.id
          AND existing_row.status NOT IN ('CANCELLED','REJECTED')
          AND (
              (NEW.dock_id IS NOT NULL AND existing_row.dock_id = NEW.dock_id)
              OR (NEW.vehicle_id IS NOT NULL AND existing_row.vehicle_id = NEW.vehicle_id)
          )
          AND existing_row.scheduled_start_at < NEW.scheduled_end_at
          AND NEW.scheduled_start_at < existing_row.scheduled_end_at
    ) THEN
        RAISE EXCEPTION 'Dock or vehicle appointment period overlaps an active appointment'
            USING ERRCODE = '23P01';
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_prevent_dock_appointment_overlap ON etms.dock_appointments;
CREATE TRIGGER trg_prevent_dock_appointment_overlap
    BEFORE INSERT OR UPDATE ON etms.dock_appointments
    FOR EACH ROW EXECUTE PROCEDURE etms.prevent_dock_appointment_overlap();

CREATE UNIQUE INDEX IF NOT EXISTS ux_route_plan_current
    ON etms.route_plan_versions (run_id) WHERE is_current;
CREATE UNIQUE INDEX IF NOT EXISTS ux_tender_award_active
    ON etms.tender_awards (tender_id)
    WHERE status IN ('AWARDED','ACCEPTED') AND withdrawn_at IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_run_primary_carrier_active
    ON etms.run_carrier_assignments (run_id)
    WHERE assignment_role = 'PRIMARY' AND status IN ('PROPOSED','ASSIGNED','ACCEPTED','ACTIVE');
CREATE UNIQUE INDEX IF NOT EXISTS ux_run_primary_driver_active
    ON etms.run_driver_assignments (run_id)
    WHERE assignment_role = 'PRIMARY' AND status IN ('ASSIGNED','ACCEPTED','ACTIVE');
CREATE UNIQUE INDEX IF NOT EXISTS ux_run_primary_equipment_active
    ON etms.run_equipment_assignments (run_id, equipment_kind)
    WHERE assignment_role = 'PRIMARY' AND status IN ('ASSIGNED','ACCEPTED','ACTIVE');
CREATE UNIQUE INDEX IF NOT EXISTS ux_transport_event_source_sequence
    ON etms.transport_events (source_system_id, source_sequence)
    WHERE source_system_id IS NOT NULL AND source_sequence IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_gps_device_source_sequence
    ON etms.gps_positions (device_id, source_sequence)
    WHERE device_id IS NOT NULL AND source_sequence IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_scan_device_source_sequence
    ON etms.scan_events (device_id, source_sequence)
    WHERE device_id IS NOT NULL AND source_sequence IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_sensor_source_sequence
    ON etms.sensor_readings (sensor_id, source_sequence)
    WHERE source_sequence IS NOT NULL;

-- Append-only operational evidence: corrections use a new event/movement/reversal row.
CREATE OR REPLACE FUNCTION etms.prevent_ledger_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    RAISE EXCEPTION '%.% is append-only; record a correction or reversal row instead',
        TG_TABLE_SCHEMA, TG_TABLE_NAME USING ERRCODE = '55000';
END;
$function$;

DO $block$
DECLARE
    table_name text;
    immutable_tables constant text[] := ARRAY[
        'access_review_decisions','account_link_events','assignment_status_history',
        'audit_event_integrity_anchors','audit_events','claim_events',
        'claim_movements','claim_reserve_movements','container_events','custody_transfers',
        'data_access_logs','dispatch_status_history','driver_duty_logs',
        'driver_task_events','driving_hours_violations','entity_change_logs',
        'execution_state_transitions','geofence_events','gps_positions',
        'handling_unit_parent_history','handling_unit_state_history',
        'handling_unit_status_history','invoice_status_history','login_events',
        'milestone_events','order_split_merge_events','order_status_history',
        'planning_input_snapshots','planning_snapshot_orders','planning_snapshot_resources',
        'pod_correction_events','pod_verification_events','port_terminal_events',
        'rate_quote_acceptance_events','rating_snapshot_lines','rating_snapshots','replan_events',
        'run_status_history','scan_events','sensor_readings','shipment_status_history',
        'spot_bid_events','stop_dwell_events','stop_status_history','tax_invoice_events',
        'tender_award_history','transport_event_corrections','transport_events',
        'vehicle_registration_history','yard_events'
    ]::text[];
BEGIN
    FOREACH table_name IN ARRAY immutable_tables
    LOOP
        IF to_regclass(format('etms.%I', table_name)) IS NULL THEN
            CONTINUE;
        END IF;
        EXECUTE format('DROP TRIGGER IF EXISTS trg_append_only ON etms.%I', table_name);
        EXECUTE format('DROP TRIGGER IF EXISTS trg_append_only_row ON etms.%I', table_name);
        EXECUTE format('DROP TRIGGER IF EXISTS trg_append_only_truncate ON etms.%I', table_name);
        EXECUTE format(
            'CREATE TRIGGER trg_append_only_row BEFORE UPDATE OR DELETE ON etms.%I '
            'FOR EACH ROW EXECUTE PROCEDURE etms.prevent_ledger_mutation()', table_name
        );
        EXECUTE format(
            'CREATE TRIGGER trg_append_only_truncate BEFORE TRUNCATE ON etms.%I '
            'FOR EACH STATEMENT EXECUTE PROCEDURE etms.prevent_ledger_mutation()', table_name
        );
    END LOOP;
END;
$block$;

-- Re-run generic tenant and optimistic-lock hardening after the gap-closure tables.
DO $block$
DECLARE
    target record;
    index_name text;
BEGIN
    FOR target IN
        SELECT relation.oid, namespace_row.nspname AS schema_name, relation.relname AS table_name
        FROM pg_class relation
        JOIN pg_namespace namespace_row ON namespace_row.oid = relation.relnamespace
        JOIN pg_attribute tenant_column
          ON tenant_column.attrelid = relation.oid
         AND tenant_column.attname = 'tenant_id'
         AND tenant_column.attnotnull
         AND NOT tenant_column.attisdropped
        JOIN pg_attribute id_column
          ON id_column.attrelid = relation.oid
         AND id_column.attname = 'id'
         AND NOT id_column.attisdropped
        WHERE namespace_row.nspname = 'etms' AND relation.relkind = 'r'
    LOOP
        index_name := 'ux_tenant_id_' || substr(md5(target.schema_name || '.' || target.table_name), 1, 16);
        EXECUTE format(
            'CREATE UNIQUE INDEX IF NOT EXISTS %I ON %I.%I (tenant_id, id)',
            index_name, target.schema_name, target.table_name
        );
    END LOOP;
END;
$block$;

DO $block$
DECLARE
    target record;
BEGIN
    FOR target IN
        SELECT DISTINCT column_row.table_schema, column_row.table_name
        FROM information_schema.columns column_row
        JOIN information_schema.tables table_row
          ON table_row.table_schema = column_row.table_schema
         AND table_row.table_name = column_row.table_name
         AND table_row.table_type = 'BASE TABLE'
        WHERE column_row.table_schema = 'etms' AND column_row.column_name = 'tenant_id'
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_trigger trigger_row
            WHERE trigger_row.tgrelid = format('%I.%I', target.table_schema, target.table_name)::regclass
              AND trigger_row.tgname = 'trg_prevent_tenant_change'
              AND NOT trigger_row.tgisinternal
        ) THEN
            EXECUTE format(
                'CREATE TRIGGER trg_prevent_tenant_change BEFORE UPDATE OF tenant_id ON %I.%I '
                'FOR EACH ROW EXECUTE PROCEDURE etms.prevent_tenant_change()',
                target.table_schema, target.table_name
            );
        END IF;
    END LOOP;
END;
$block$;

DO $block$
DECLARE
    target record;
BEGIN
    FOR target IN
        SELECT updated_column.table_schema, updated_column.table_name
        FROM information_schema.columns updated_column
        JOIN information_schema.columns version_column
          ON version_column.table_schema = updated_column.table_schema
         AND version_column.table_name = updated_column.table_name
         AND version_column.column_name = 'row_version'
        WHERE updated_column.table_schema = 'etms'
          AND updated_column.column_name = 'updated_at'
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_trigger trigger_row
            WHERE trigger_row.tgrelid = format('%I.%I', target.table_schema, target.table_name)::regclass
              AND trigger_row.tgname = 'trg_touch_row'
              AND NOT trigger_row.tgisinternal
        ) THEN
            EXECUTE format(
                'CREATE TRIGGER trg_touch_row BEFORE UPDATE ON %I.%I '
                'FOR EACH ROW EXECUTE PROCEDURE etms.touch_row()',
                target.table_schema, target.table_name
            );
        END IF;
    END LOOP;
END;
$block$;

-- Same-tenant guard for every single-column FK between tenant-scoped relations.
DO $block$
DECLARE
    relationship record;
    child_column text;
    trigger_name text;
BEGIN
    FOR relationship IN
        SELECT constraint_row.conname, constraint_row.conrelid, constraint_row.confrelid,
               child_ns.nspname AS child_schema, child_relation.relname AS child_table,
               parent_ns.nspname AS parent_schema, parent_relation.relname AS parent_table,
               constraint_row.conkey[1] AS child_attnum
        FROM pg_constraint constraint_row
        JOIN pg_class child_relation ON child_relation.oid = constraint_row.conrelid
        JOIN pg_namespace child_ns ON child_ns.oid = child_relation.relnamespace
        JOIN pg_class parent_relation ON parent_relation.oid = constraint_row.confrelid
        JOIN pg_namespace parent_ns ON parent_ns.oid = parent_relation.relnamespace
        WHERE constraint_row.contype = 'f'
          AND child_ns.nspname = 'etms' AND parent_ns.nspname = 'etms'
          AND array_length(constraint_row.conkey, 1) = 1
          AND EXISTS (
              SELECT 1 FROM pg_attribute attribute
              WHERE attribute.attrelid = constraint_row.conrelid
                AND attribute.attname = 'tenant_id' AND NOT attribute.attisdropped
          )
          AND EXISTS (
              SELECT 1 FROM pg_attribute attribute
              WHERE attribute.attrelid = constraint_row.confrelid
                AND attribute.attname = 'tenant_id' AND NOT attribute.attisdropped
          )
          AND EXISTS (
              SELECT 1 FROM pg_attribute attribute
              WHERE attribute.attrelid = constraint_row.confrelid
                AND attribute.attnum = constraint_row.confkey[1]
                AND attribute.attname = 'id'
          )
    LOOP
        SELECT attname INTO child_column
        FROM pg_attribute
        WHERE attrelid = relationship.conrelid AND attnum = relationship.child_attnum;
        IF child_column = 'tenant_id' THEN CONTINUE; END IF;
        trigger_name := 'trg_tenant_fk_' || substr(
            md5(relationship.child_schema || '.' || relationship.child_table || '.' || relationship.conname),
            1, 12
        );
        IF NOT EXISTS (
            SELECT 1 FROM pg_trigger trigger_row
            WHERE trigger_row.tgrelid = relationship.conrelid
              AND trigger_row.tgname = trigger_name
              AND NOT trigger_row.tgisinternal
        ) THEN
            EXECUTE format(
                'CREATE TRIGGER %I BEFORE INSERT OR UPDATE OF %I ON %I.%I '
                'FOR EACH ROW EXECUTE PROCEDURE etms.enforce_same_tenant_fk(%L,%L,%L)',
                trigger_name, child_column, relationship.child_schema, relationship.child_table,
                child_column, relationship.parent_schema, relationship.parent_table
            );
        END IF;
    END LOOP;
END;
$block$;

-- PostgreSQL does not create indexes for referencing FK columns.
DO $block$
DECLARE
    relationship record;
    column_list text;
    index_name text;
BEGIN
    FOR relationship IN
        SELECT constraint_row.conname, constraint_row.conrelid,
               namespace_row.nspname AS schema_name, relation.relname AS table_name,
               constraint_row.conkey
        FROM pg_constraint constraint_row
        JOIN pg_class relation ON relation.oid = constraint_row.conrelid
        JOIN pg_namespace namespace_row ON namespace_row.oid = relation.relnamespace
        WHERE constraint_row.contype = 'f' AND namespace_row.nspname = 'etms'
    LOOP
        SELECT string_agg(quote_ident(attribute.attname), ', ' ORDER BY key_column.ordinality)
          INTO column_list
          FROM unnest(relationship.conkey) WITH ORDINALITY AS key_column(attnum, ordinality)
          JOIN pg_attribute attribute
            ON attribute.attrelid = relationship.conrelid
           AND attribute.attnum = key_column.attnum;
        IF EXISTS (
            SELECT 1 FROM pg_index index_row
            WHERE index_row.indrelid = relationship.conrelid
              AND index_row.indisvalid AND index_row.indisready
              AND index_row.indpred IS NULL
              AND (index_row.indkey::smallint[])[0:array_length(relationship.conkey, 1) - 1]
                    = relationship.conkey
        ) THEN
            CONTINUE;
        END IF;
        index_name := 'ix_fk_' || substr(relationship.table_name, 1, 30) || '_' ||
            substr(md5(relationship.schema_name || '.' || relationship.table_name || '.' || relationship.conname), 1, 10);
        EXECUTE format(
            'CREATE INDEX IF NOT EXISTS %I ON %I.%I (%s)',
            index_name, relationship.schema_name, relationship.table_name, column_list
        );
    END LOOP;
END;
$block$;

-- Global operational status vocabulary and enforceable transitions.
INSERT INTO etms.status_definitions (
    tenant_id, entity_type, status_code, status_name,
    terminal_status, success_status, sort_order
)
SELECT NULL, seed.entity_type, seed.status_code, seed.status_name,
       seed.terminal_status, seed.success_status, seed.sort_order
FROM (VALUES
    ('ORDER','DRAFT','Draft',false,false,10),
    ('ORDER','SUBMITTED','Submitted',false,false,20),
    ('ORDER','VALIDATED','Validated',false,false,30),
    ('ORDER','PLANNED','Planned',false,false,40),
    ('ORDER','DISPATCHED','Dispatched',false,false,50),
    ('ORDER','IN_TRANSIT','In transit',false,false,60),
    ('ORDER','DELIVERED','Delivered',false,true,70),
    ('ORDER','COMPLETED','Completed',true,true,80),
    ('ORDER','ON_HOLD','On hold',false,false,90),
    ('ORDER','EXCEPTION','Exception',false,false,100),
    ('ORDER','CANCELLED','Cancelled',true,false,110),
    ('SHIPMENT','PLANNED','Planned',false,false,10),
    ('SHIPMENT','TENDERING','Tendering',false,false,20),
    ('SHIPMENT','TENDERED','Tendered',false,false,30),
    ('SHIPMENT','ASSIGNED','Assigned',false,false,40),
    ('SHIPMENT','DISPATCHED','Dispatched',false,false,50),
    ('SHIPMENT','IN_TRANSIT','In transit',false,false,60),
    ('SHIPMENT','DELIVERED','Delivered',false,true,70),
    ('SHIPMENT','COMPLETED','Completed',true,true,80),
    ('SHIPMENT','EXCEPTION','Exception',false,false,90),
    ('SHIPMENT','CANCELLED','Cancelled',true,false,100),
    ('RUN','PLANNED','Planned',false,false,10),
    ('RUN','ASSIGNED','Assigned',false,false,20),
    ('RUN','DISPATCHED','Dispatched',false,false,30),
    ('RUN','IN_PROGRESS','In progress',false,false,40),
    ('RUN','COMPLETED','Completed',true,true,50),
    ('RUN','EXCEPTION','Exception',false,false,60),
    ('RUN','CANCELLED','Cancelled',true,false,70),
    ('DISPATCH','DRAFT','Draft',false,false,10),
    ('DISPATCH','ISSUED','Issued',false,false,20),
    ('DISPATCH','ACKNOWLEDGED','Acknowledged',false,false,30),
    ('DISPATCH','ACCEPTED','Accepted',false,false,40),
    ('DISPATCH','REJECTED','Rejected',true,false,50),
    ('DISPATCH','IN_PROGRESS','In progress',false,false,60),
    ('DISPATCH','COMPLETED','Completed',true,true,70),
    ('DISPATCH','CANCELLED','Cancelled',true,false,80),
    ('DISPATCH','EXPIRED','Expired',true,false,90)
) AS seed(entity_type,status_code,status_name,terminal_status,success_status,sort_order)
WHERE NOT EXISTS (
    SELECT 1 FROM etms.status_definitions existing_row
    WHERE existing_row.tenant_id IS NULL
      AND existing_row.entity_type = seed.entity_type
      AND existing_row.status_code = seed.status_code
);

INSERT INTO etms.status_transitions (
    tenant_id, entity_type, from_status_code, to_status_code
)
SELECT NULL, seed.entity_type, seed.from_status, seed.to_status
FROM (VALUES
    ('ORDER','DRAFT','SUBMITTED'),('ORDER','DRAFT','CANCELLED'),
    ('ORDER','SUBMITTED','VALIDATED'),('ORDER','SUBMITTED','ON_HOLD'),('ORDER','SUBMITTED','CANCELLED'),
    ('ORDER','VALIDATED','PLANNED'),('ORDER','VALIDATED','ON_HOLD'),('ORDER','VALIDATED','CANCELLED'),
    ('ORDER','PLANNED','DISPATCHED'),('ORDER','PLANNED','ON_HOLD'),('ORDER','PLANNED','CANCELLED'),
    ('ORDER','ON_HOLD','VALIDATED'),('ORDER','ON_HOLD','PLANNED'),('ORDER','ON_HOLD','CANCELLED'),
    ('ORDER','DISPATCHED','IN_TRANSIT'),('ORDER','DISPATCHED','CANCELLED'),
    ('ORDER','IN_TRANSIT','DELIVERED'),('ORDER','IN_TRANSIT','EXCEPTION'),
    ('ORDER','EXCEPTION','IN_TRANSIT'),('ORDER','EXCEPTION','CANCELLED'),
    ('ORDER','DELIVERED','COMPLETED'),('ORDER','DELIVERED','EXCEPTION'),
    ('SHIPMENT','PLANNED','TENDERING'),('SHIPMENT','PLANNED','ASSIGNED'),('SHIPMENT','PLANNED','CANCELLED'),
    ('SHIPMENT','TENDERING','TENDERED'),('SHIPMENT','TENDERING','CANCELLED'),
    ('SHIPMENT','TENDERED','ASSIGNED'),('SHIPMENT','TENDERED','CANCELLED'),
    ('SHIPMENT','ASSIGNED','DISPATCHED'),('SHIPMENT','ASSIGNED','CANCELLED'),
    ('SHIPMENT','DISPATCHED','IN_TRANSIT'),('SHIPMENT','DISPATCHED','CANCELLED'),
    ('SHIPMENT','IN_TRANSIT','DELIVERED'),('SHIPMENT','IN_TRANSIT','EXCEPTION'),
    ('SHIPMENT','EXCEPTION','IN_TRANSIT'),('SHIPMENT','EXCEPTION','CANCELLED'),
    ('SHIPMENT','DELIVERED','COMPLETED'),('SHIPMENT','DELIVERED','EXCEPTION'),
    ('RUN','PLANNED','ASSIGNED'),('RUN','PLANNED','CANCELLED'),
    ('RUN','ASSIGNED','DISPATCHED'),('RUN','ASSIGNED','CANCELLED'),
    ('RUN','DISPATCHED','IN_PROGRESS'),('RUN','DISPATCHED','CANCELLED'),
    ('RUN','IN_PROGRESS','COMPLETED'),('RUN','IN_PROGRESS','EXCEPTION'),
    ('RUN','EXCEPTION','IN_PROGRESS'),('RUN','EXCEPTION','CANCELLED'),
    ('DISPATCH','DRAFT','ISSUED'),('DISPATCH','DRAFT','CANCELLED'),
    ('DISPATCH','ISSUED','ACKNOWLEDGED'),('DISPATCH','ISSUED','ACCEPTED'),
    ('DISPATCH','ISSUED','REJECTED'),('DISPATCH','ISSUED','EXPIRED'),('DISPATCH','ISSUED','CANCELLED'),
    ('DISPATCH','ACKNOWLEDGED','ACCEPTED'),('DISPATCH','ACKNOWLEDGED','REJECTED'),
    ('DISPATCH','ACKNOWLEDGED','EXPIRED'),('DISPATCH','ACKNOWLEDGED','CANCELLED'),
    ('DISPATCH','ACCEPTED','IN_PROGRESS'),('DISPATCH','ACCEPTED','CANCELLED'),
    ('DISPATCH','IN_PROGRESS','COMPLETED'),('DISPATCH','IN_PROGRESS','CANCELLED')
) AS seed(entity_type,from_status,to_status)
WHERE NOT EXISTS (
    SELECT 1 FROM etms.status_transitions existing_row
    WHERE existing_row.tenant_id IS NULL
      AND existing_row.entity_type = seed.entity_type
      AND existing_row.from_status_code = seed.from_status
      AND existing_row.to_status_code = seed.to_status
);

CREATE OR REPLACE FUNCTION etms.enforce_operational_status_transition()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
BEGIN
    IF NEW.status IS NOT DISTINCT FROM OLD.status THEN RETURN NEW; END IF;
    IF NOT EXISTS (
        SELECT 1 FROM etms.status_definitions definition_row
        WHERE definition_row.entity_type = TG_ARGV[0]
          AND definition_row.status_code = NEW.status
          AND definition_row.is_active
          AND (definition_row.tenant_id IS NULL OR definition_row.tenant_id = NEW.tenant_id)
    ) OR NOT EXISTS (
        SELECT 1 FROM etms.status_transitions transition_row
        WHERE transition_row.entity_type = TG_ARGV[0]
          AND transition_row.from_status_code = OLD.status
          AND transition_row.to_status_code = NEW.status
          AND transition_row.is_active
          AND (transition_row.tenant_id IS NULL OR transition_row.tenant_id = NEW.tenant_id)
    ) THEN
        RAISE EXCEPTION 'Invalid % status transition: % -> %', TG_ARGV[0], OLD.status, NEW.status
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_validate_order_status_transition ON etms.transport_orders;
CREATE TRIGGER trg_validate_order_status_transition
    BEFORE UPDATE OF status ON etms.transport_orders
    FOR EACH ROW EXECUTE PROCEDURE etms.enforce_operational_status_transition('ORDER');
DROP TRIGGER IF EXISTS trg_validate_shipment_status_transition ON etms.shipments;
CREATE TRIGGER trg_validate_shipment_status_transition
    BEFORE UPDATE OF status ON etms.shipments
    FOR EACH ROW EXECUTE PROCEDURE etms.enforce_operational_status_transition('SHIPMENT');
DROP TRIGGER IF EXISTS trg_validate_run_status_transition ON etms.transport_runs;
CREATE TRIGGER trg_validate_run_status_transition
    BEFORE UPDATE OF status ON etms.transport_runs
    FOR EACH ROW EXECUTE PROCEDURE etms.enforce_operational_status_transition('RUN');
DROP TRIGGER IF EXISTS trg_validate_dispatch_status_transition ON etms.dispatch_orders;
CREATE TRIGGER trg_validate_dispatch_status_transition
    BEFORE UPDATE OF status ON etms.dispatch_orders
    FOR EACH ROW EXECUTE PROCEDURE etms.enforce_operational_status_transition('DISPATCH');

CREATE OR REPLACE FUNCTION etms.record_operational_status_history()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE actor_id uuid := etms.current_etms_user_id();
BEGIN
    IF NEW.status IS NOT DISTINCT FROM OLD.status THEN RETURN NEW; END IF;
    IF TG_ARGV[0] = 'ORDER' THEN
        INSERT INTO etms.order_status_history
            (tenant_id, order_id, from_status, to_status, source_type, changed_by)
        VALUES (NEW.tenant_id, NEW.id, OLD.status, NEW.status, 'SYSTEM', actor_id);
    ELSIF TG_ARGV[0] = 'SHIPMENT' THEN
        INSERT INTO etms.shipment_status_history
            (tenant_id, shipment_id, from_status, to_status, changed_by, occurred_at)
        VALUES (NEW.tenant_id, NEW.id, OLD.status, NEW.status, actor_id, statement_timestamp());
    ELSIF TG_ARGV[0] = 'RUN' THEN
        INSERT INTO etms.run_status_history
            (tenant_id, run_id, from_status, to_status, changed_by, occurred_at)
        VALUES (NEW.tenant_id, NEW.id, OLD.status, NEW.status, actor_id, statement_timestamp());
    ELSIF TG_ARGV[0] = 'DISPATCH' THEN
        INSERT INTO etms.dispatch_status_history
            (tenant_id, dispatch_order_id, from_status, to_status, changed_by)
        VALUES (NEW.tenant_id, NEW.id, OLD.status, NEW.status, actor_id);
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_record_order_status_history ON etms.transport_orders;
CREATE TRIGGER trg_record_order_status_history
    AFTER UPDATE OF status ON etms.transport_orders
    FOR EACH ROW EXECUTE PROCEDURE etms.record_operational_status_history('ORDER');
DROP TRIGGER IF EXISTS trg_record_shipment_status_history ON etms.shipments;
CREATE TRIGGER trg_record_shipment_status_history
    AFTER UPDATE OF status ON etms.shipments
    FOR EACH ROW EXECUTE PROCEDURE etms.record_operational_status_history('SHIPMENT');
DROP TRIGGER IF EXISTS trg_record_run_status_history ON etms.transport_runs;
CREATE TRIGGER trg_record_run_status_history
    AFTER UPDATE OF status ON etms.transport_runs
    FOR EACH ROW EXECUTE PROCEDURE etms.record_operational_status_history('RUN');
DROP TRIGGER IF EXISTS trg_record_dispatch_status_history ON etms.dispatch_orders;
CREATE TRIGGER trg_record_dispatch_status_history
    AFTER UPDATE OF status ON etms.dispatch_orders
    FOR EACH ROW EXECUTE PROCEDURE etms.record_operational_status_history('DISPATCH');

-- Fail-closed RLS for every tenant-owned relation. Global reference rows are read-only.
DO $block$
DECLARE
    target record;
    global_reference_tables constant text[] := ARRAY[
        'charge_codes','code_sets','code_values','commodity_classes','data_quality_rules',
        'emission_factors','equipment_types','exchange_rates','fuel_index_values','fuel_indices',
        'kpi_definitions','notification_templates','payment_terms','role_permissions','roles',
        'service_levels','status_definitions','status_transitions','tax_codes','tax_rates','vehicle_types'
    ]::text[];
    select_expression text;
    modify_expression text;
BEGIN
    FOR target IN
        SELECT DISTINCT column_row.table_schema, column_row.table_name
        FROM information_schema.columns column_row
        JOIN information_schema.tables table_row
          ON table_row.table_schema = column_row.table_schema
         AND table_row.table_name = column_row.table_name
         AND table_row.table_type = 'BASE TABLE'
        WHERE column_row.table_schema = 'etms' AND column_row.column_name = 'tenant_id'
    LOOP
        EXECUTE format('ALTER TABLE %I.%I ENABLE ROW LEVEL SECURITY', target.table_schema, target.table_name);
        EXECUTE format('DROP POLICY IF EXISTS tenant_isolation ON %I.%I', target.table_schema, target.table_name);
        EXECUTE format('DROP POLICY IF EXISTS tenant_select ON %I.%I', target.table_schema, target.table_name);
        EXECUTE format('DROP POLICY IF EXISTS tenant_modify ON %I.%I', target.table_schema, target.table_name);

        IF target.table_name = 'tenant_memberships' THEN
            select_expression :=
                'tenant_id = etms.current_tenant_id() '
                'OR etms.has_active_session_issue_context(user_id, tenant_id) '
                'OR etms.has_active_membership_provision_context(user_id, tenant_id)';
            modify_expression :=
                'tenant_id = etms.current_tenant_id() '
                'OR etms.has_active_session_issue_context(user_id, tenant_id) '
                'OR etms.has_active_membership_provision_context(user_id, tenant_id)';
        ELSIF target.table_name = ANY (global_reference_tables) THEN
            select_expression := 'tenant_id IS NULL OR tenant_id = etms.current_tenant_id()';
            modify_expression := 'tenant_id = etms.current_tenant_id()';
        ELSE
            select_expression := 'tenant_id = etms.current_tenant_id()';
            modify_expression := 'tenant_id = etms.current_tenant_id()';
        END IF;
        EXECUTE format(
            'CREATE POLICY tenant_select ON %I.%I FOR SELECT USING (%s)',
            target.table_schema, target.table_name, select_expression
        );
        EXECUTE format(
            'CREATE POLICY tenant_modify ON %I.%I FOR ALL USING (%s) WITH CHECK (%s)',
            target.table_schema, target.table_name, modify_expression, modify_expression
        );
        EXECUTE format('ALTER TABLE %I.%I FORCE ROW LEVEL SECURITY', target.table_schema, target.table_name);
    END LOOP;
END;
$block$;

-- Security control-plane tables are callable only through reviewed functions.
REVOKE ALL ON TABLE etms.request_contexts FROM PUBLIC;
REVOKE ALL ON TABLE etms.session_issue_contexts FROM PUBLIC;
REVOKE ALL ON TABLE etms.membership_provision_contexts FROM PUBLIC;
REVOKE ALL ON TABLE etms.identity_command_contexts FROM PUBLIC;
REVOKE ALL ON TABLE etms.auth_sessions FROM PUBLIC;
REVOKE ALL ON SCHEMA etms FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA etms FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA etms FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA etms FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA etms REVOKE ALL ON TABLES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA etms REVOKE ALL ON SEQUENCES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA etms REVOKE ALL ON FUNCTIONS FROM PUBLIC;

COMMENT ON SCHEMA etms IS
    'Enterprise transportation management system: protected Firebase IAM, master data, rating, transport demand, planning, assignment, dispatch, multimodal execution, performance, claims, settlement, accounting, compliance, integration, and analytics.';
