-- EWMS authenticated request context and fail-closed tenant isolation.
-- PostgreSQL 11 compatible. Applied after module 12 in the same atomic baseline transaction.
--
-- Authentication contract:
--   * The trusted authentication service verifies Firebase, generates a high-entropy
--     opaque session handle, and passes only its lowercase SHA-256 hash here.
--   * Every business transaction calls bind_request_context(hash) before tenant DML.
--   * RLS identity is derived only from protected server-side rows bound to the current
--     backend PID and transaction ID. The ewms.tenant_id custom GUC is deliberately ignored.

-- Existing sessions identify a membership, but the original baseline did not retain the
-- membership's tenant on the session row. Keep that subject explicit so request contexts can
-- have a single composite FK to the complete authenticated session subject.
DO $migration$
BEGIN
    IF NOT EXISTS (
        SELECT 1
          FROM pg_attribute
         WHERE attrelid = 'ewms.user_sessions'::regclass
           AND attname = 'active_tenant_id'
           AND NOT attisdropped
    ) THEN
        ALTER TABLE ewms.user_sessions
            ADD COLUMN active_tenant_id uuid;
    END IF;
END;
$migration$;

-- The owner is normally subject to FORCE RLS at this point. Temporarily remove FORCE only
-- inside this migration transaction to derive the tenant of any pre-existing session; an
-- error rolls the whole transaction back and the final policy block also restores FORCE.
ALTER TABLE ewms.tenant_memberships NO FORCE ROW LEVEL SECURITY;

UPDATE ewms.user_sessions session_row
   SET active_tenant_id = membership.tenant_id
  FROM ewms.tenant_memberships membership
 WHERE session_row.active_tenant_id IS NULL
   AND session_row.active_membership_id = membership.id
   AND session_row.user_id = membership.user_id;

ALTER TABLE ewms.tenant_memberships FORCE ROW LEVEL SECURITY;

DO $migration$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
         WHERE conrelid = 'ewms.tenant_memberships'::regclass
           AND conname = 'uq_ewms_membership_subject'
    ) THEN
        ALTER TABLE ewms.tenant_memberships
            ADD CONSTRAINT uq_ewms_membership_subject
            UNIQUE (id, user_id, tenant_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
         WHERE conrelid = 'ewms.user_sessions'::regclass
           AND conname = 'fk_ewms_session_active_tenant'
    ) THEN
        ALTER TABLE ewms.user_sessions
            ADD CONSTRAINT fk_ewms_session_active_tenant
            FOREIGN KEY (active_tenant_id)
            REFERENCES ewms.tenants(id) ON DELETE RESTRICT;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
         WHERE conrelid = 'ewms.user_sessions'::regclass
           AND conname = 'fk_ewms_session_membership_subject'
    ) THEN
        ALTER TABLE ewms.user_sessions
            ADD CONSTRAINT fk_ewms_session_membership_subject
            FOREIGN KEY (active_membership_id, user_id, active_tenant_id)
            REFERENCES ewms.tenant_memberships(id, user_id, tenant_id)
            ON DELETE CASCADE;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
         WHERE conrelid = 'ewms.user_sessions'::regclass
           AND conname = 'ck_ewms_session_tenant_membership_pair'
    ) THEN
        ALTER TABLE ewms.user_sessions
            ADD CONSTRAINT ck_ewms_session_tenant_membership_pair CHECK (
                (active_membership_id IS NULL AND active_tenant_id IS NULL) OR
                (active_membership_id IS NOT NULL AND active_tenant_id IS NOT NULL)
            );
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
         WHERE conrelid = 'ewms.user_sessions'::regclass
           AND conname = 'uq_ewms_session_subject'
    ) THEN
        ALTER TABLE ewms.user_sessions
            ADD CONSTRAINT uq_ewms_session_subject
            UNIQUE (id, user_id, active_tenant_id, active_membership_id);
    END IF;
END;
$migration$;

COMMENT ON COLUMN ewms.user_sessions.active_tenant_id IS
    'Tenant fixed at server-session issuance; paired with active_membership_id and immutable for authenticated use.';

-- Table ACLs are the primary boundary, but session identity and validity must remain immutable
-- even for an accidentally over-privileged service role. Only last-seen bookkeeping, the first
-- terminal revocation, and normal touch_row maintenance may change after issuance.
CREATE OR REPLACE FUNCTION ewms.protect_user_session_core()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, ewms
AS $function$
BEGIN
    IF OLD.id IS DISTINCT FROM NEW.id
       OR OLD.user_id IS DISTINCT FROM NEW.user_id
       OR OLD.active_membership_id IS DISTINCT FROM NEW.active_membership_id
       OR OLD.active_tenant_id IS DISTINCT FROM NEW.active_tenant_id
       OR OLD.session_handle_hash IS DISTINCT FROM NEW.session_handle_hash
       OR OLD.firebase_auth_time IS DISTINCT FROM NEW.firebase_auth_time
       OR OLD.assurance_level IS DISTINCT FROM NEW.assurance_level
       OR OLD.issued_at IS DISTINCT FROM NEW.issued_at
       OR OLD.expires_at IS DISTINCT FROM NEW.expires_at
       OR OLD.ip_address IS DISTINCT FROM NEW.ip_address
       OR OLD.user_agent IS DISTINCT FROM NEW.user_agent
       OR OLD.created_at IS DISTINCT FROM NEW.created_at THEN
        RAISE EXCEPTION
            'Session subject, handle, authentication evidence, and validity window are immutable'
            USING ERRCODE = '55000';
    END IF;

    IF OLD.last_seen_at IS NOT NULL
       AND NEW.last_seen_at IS DISTINCT FROM OLD.last_seen_at
       AND (NEW.last_seen_at IS NULL OR NEW.last_seen_at < OLD.last_seen_at) THEN
        RAISE EXCEPTION 'Session last_seen_at cannot move backwards or be cleared'
            USING ERRCODE = '55000';
    END IF;

    IF OLD.revoked_at IS NOT NULL
       AND (NEW.revoked_at IS DISTINCT FROM OLD.revoked_at
            OR NEW.revoke_reason IS DISTINCT FROM OLD.revoke_reason) THEN
        RAISE EXCEPTION 'A terminal session revocation cannot be cleared or rewritten'
            USING ERRCODE = '55000';
    END IF;
    IF OLD.revoked_at IS NULL AND NEW.revoked_at IS NULL
       AND NEW.revoke_reason IS DISTINCT FROM OLD.revoke_reason THEN
        RAISE EXCEPTION 'A revocation reason cannot be recorded without revoked_at'
            USING ERRCODE = '23514';
    END IF;
    IF OLD.revoked_at IS NULL AND NEW.revoked_at IS NOT NULL
       AND btrim(COALESCE(NEW.revoke_reason, '')) = '' THEN
        RAISE EXCEPTION 'A non-empty reason is required when revoking a session'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_protect_user_session_core ON ewms.user_sessions;
CREATE TRIGGER trg_protect_user_session_core
    BEFORE UPDATE ON ewms.user_sessions
    FOR EACH ROW EXECUTE PROCEDURE ewms.protect_user_session_core();

REVOKE ALL ON FUNCTION ewms.protect_user_session_core() FROM PUBLIC;

-- Session issuance and binding must bootstrap through FORCE RLS before a normal request
-- context exists. These short-lived control-plane rows are not tenant business data and use
-- bound_* names so the schema-wide tenant policy generator never attaches ordinary RLS.
CREATE TABLE IF NOT EXISTS ewms.session_issue_contexts (
    backend_pid integer NOT NULL,
    transaction_id bigint NOT NULL,
    bound_user_id uuid NOT NULL REFERENCES ewms.users(id) ON DELETE CASCADE,
    bound_tenant_id uuid NOT NULL REFERENCES ewms.tenants(id) ON DELETE CASCADE,
    established_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    expires_at timestamptz NOT NULL,
    PRIMARY KEY (backend_pid, transaction_id),
    CONSTRAINT ck_session_issue_context_backend CHECK (
        backend_pid > 0 AND transaction_id > 0
    ),
    CONSTRAINT ck_session_issue_context_expiry CHECK (expires_at > established_at)
);

CREATE TABLE IF NOT EXISTS ewms.session_bind_contexts (
    backend_pid integer NOT NULL,
    transaction_id bigint NOT NULL,
    session_id uuid NOT NULL,
    bound_user_id uuid NOT NULL,
    bound_tenant_id uuid NOT NULL,
    bound_membership_id uuid NOT NULL,
    established_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    expires_at timestamptz NOT NULL,
    PRIMARY KEY (backend_pid, transaction_id),
    FOREIGN KEY (session_id, bound_user_id, bound_tenant_id, bound_membership_id)
        REFERENCES ewms.user_sessions(id, user_id, active_tenant_id, active_membership_id)
        ON DELETE CASCADE,
    FOREIGN KEY (bound_membership_id, bound_user_id, bound_tenant_id)
        REFERENCES ewms.tenant_memberships(id, user_id, tenant_id)
        ON DELETE CASCADE,
    CONSTRAINT ck_session_bind_context_backend CHECK (
        backend_pid > 0 AND transaction_id > 0
    ),
    CONSTRAINT ck_session_bind_context_expiry CHECK (expires_at > established_at)
);

CREATE TABLE IF NOT EXISTS ewms.request_contexts (
    backend_pid integer NOT NULL,
    transaction_id bigint NOT NULL,
    session_id uuid NOT NULL,
    bound_user_id uuid NOT NULL,
    bound_tenant_id uuid NOT NULL,
    bound_membership_id uuid NOT NULL,
    request_id uuid NOT NULL DEFAULT ewms.generate_uuid(),
    bound_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    context_expires_at timestamptz NOT NULL,
    PRIMARY KEY (backend_pid, transaction_id),
    UNIQUE (request_id),
    CONSTRAINT fk_request_context_session_subject
        FOREIGN KEY (session_id, bound_user_id, bound_tenant_id, bound_membership_id)
        REFERENCES ewms.user_sessions(id, user_id, active_tenant_id, active_membership_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_request_context_membership_subject
        FOREIGN KEY (bound_membership_id, bound_user_id, bound_tenant_id)
        REFERENCES ewms.tenant_memberships(id, user_id, tenant_id)
        ON DELETE CASCADE,
    CONSTRAINT ck_request_context_backend CHECK (
        backend_pid > 0 AND transaction_id > 0
    ),
    CONSTRAINT ck_request_context_expiry CHECK (context_expires_at > bound_at)
);

CREATE INDEX IF NOT EXISTS ix_session_issue_contexts_expiry
    ON ewms.session_issue_contexts (expires_at);
CREATE INDEX IF NOT EXISTS ix_session_issue_contexts_user
    ON ewms.session_issue_contexts (bound_user_id);
CREATE INDEX IF NOT EXISTS ix_session_issue_contexts_tenant
    ON ewms.session_issue_contexts (bound_tenant_id);
CREATE INDEX IF NOT EXISTS ix_session_bind_contexts_expiry
    ON ewms.session_bind_contexts (expires_at);
CREATE INDEX IF NOT EXISTS ix_session_bind_context_session_subject
    ON ewms.session_bind_contexts (
        session_id, bound_user_id, bound_tenant_id, bound_membership_id
    );
CREATE INDEX IF NOT EXISTS ix_session_bind_context_membership_subject
    ON ewms.session_bind_contexts (
        bound_membership_id, bound_user_id, bound_tenant_id
    );
CREATE INDEX IF NOT EXISTS ix_request_contexts_expiry
    ON ewms.request_contexts (context_expires_at);
CREATE INDEX IF NOT EXISTS ix_request_context_session_subject
    ON ewms.request_contexts (session_id, bound_user_id, bound_tenant_id, bound_membership_id);
CREATE INDEX IF NOT EXISTS ix_request_context_membership_subject
    ON ewms.request_contexts (bound_membership_id, bound_user_id, bound_tenant_id);
CREATE INDEX IF NOT EXISTS ix_user_sessions_active_tenant
    ON ewms.user_sessions (active_tenant_id);
CREATE INDEX IF NOT EXISTS ix_user_sessions_membership_subject
    ON ewms.user_sessions (active_membership_id, user_id, active_tenant_id);

REVOKE ALL ON TABLE ewms.session_issue_contexts FROM PUBLIC;
REVOKE ALL ON TABLE ewms.session_bind_contexts FROM PUBLIC;
REVOKE ALL ON TABLE ewms.request_contexts FROM PUBLIC;

COMMENT ON TABLE ewms.session_issue_contexts IS
    'Protected one-minute transaction marker used only to resolve an active membership while issuing a server session through FORCE RLS.';
COMMENT ON TABLE ewms.session_bind_contexts IS
    'Protected one-minute transaction marker used only to revalidate the session membership while binding a normal request context.';
COMMENT ON TABLE ewms.request_contexts IS
    'Protected authenticated request subject bound to backend_pid and transaction_id; application roles receive no direct table privileges.';

CREATE OR REPLACE FUNCTION ewms.has_active_session_issue_context(
    p_user_id uuid,
    p_tenant_id uuid
)
RETURNS boolean
LANGUAGE sql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, ewms
AS $function$
    SELECT EXISTS (
        SELECT 1
          FROM ewms.session_issue_contexts context_row
         WHERE context_row.backend_pid = pg_backend_pid()
           AND context_row.transaction_id = txid_current()
           AND context_row.bound_user_id = p_user_id
           AND context_row.bound_tenant_id = p_tenant_id
           AND context_row.expires_at > statement_timestamp()
    );
$function$;

CREATE OR REPLACE FUNCTION ewms.has_active_session_bind_context(
    p_membership_id uuid,
    p_user_id uuid,
    p_tenant_id uuid
)
RETURNS boolean
LANGUAGE sql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, ewms
AS $function$
    SELECT EXISTS (
        SELECT 1
          FROM ewms.session_bind_contexts context_row
          JOIN ewms.user_sessions session_row
            ON session_row.id = context_row.session_id
           AND session_row.user_id = context_row.bound_user_id
           AND session_row.active_tenant_id = context_row.bound_tenant_id
           AND session_row.active_membership_id = context_row.bound_membership_id
         WHERE context_row.backend_pid = pg_backend_pid()
           AND context_row.transaction_id = txid_current()
           AND context_row.bound_membership_id = p_membership_id
           AND context_row.bound_user_id = p_user_id
           AND context_row.bound_tenant_id = p_tenant_id
           AND context_row.expires_at > statement_timestamp()
           AND session_row.revoked_at IS NULL
           AND session_row.issued_at <= statement_timestamp()
           AND session_row.expires_at > statement_timestamp()
    );
$function$;

REVOKE ALL ON FUNCTION ewms.has_active_session_issue_context(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION ewms.has_active_session_bind_context(uuid, uuid, uuid) FROM PUBLIC;

-- Revoke live sessions whenever a principal, identity, membership, or tenant authorization
-- boundary changes. Valid-to expiry is also enforced independently during every bind.
CREATE OR REPLACE FUNCTION ewms.revoke_sessions_after_subject_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, ewms
AS $function$
DECLARE
    reason_value text;
BEGIN
    IF TG_TABLE_NAME = 'tenant_memberships' THEN
        IF OLD.status IS NOT DISTINCT FROM NEW.status
           AND OLD.valid_from IS NOT DISTINCT FROM NEW.valid_from
           AND OLD.valid_to IS NOT DISTINCT FROM NEW.valid_to THEN
            RETURN NEW;
        END IF;
        reason_value := 'TENANT_MEMBERSHIP_AUTHORIZATION_CHANGED';
        UPDATE ewms.user_sessions
           SET revoked_at = statement_timestamp(),
               revoke_reason = reason_value
         WHERE active_membership_id = NEW.id
           AND revoked_at IS NULL;
        RETURN NEW;
    ELSIF TG_TABLE_NAME = 'users' THEN
        IF OLD.status IS NOT DISTINCT FROM NEW.status
           AND OLD.deleted_at IS NOT DISTINCT FROM NEW.deleted_at
           AND OLD.locked_at IS NOT DISTINCT FROM NEW.locked_at THEN
            RETURN NEW;
        END IF;
        reason_value := 'EWMS_USER_AUTHORIZATION_CHANGED';
        UPDATE ewms.user_sessions
           SET revoked_at = statement_timestamp(),
               revoke_reason = reason_value
         WHERE user_id = NEW.id
           AND revoked_at IS NULL;
        RETURN NEW;
    ELSIF TG_TABLE_NAME = 'tenants' THEN
        IF OLD.status IS NOT DISTINCT FROM NEW.status
           AND OLD.deleted_at IS NOT DISTINCT FROM NEW.deleted_at THEN
            RETURN NEW;
        END IF;
        reason_value := 'EWMS_TENANT_AUTHORIZATION_CHANGED';
        UPDATE ewms.user_sessions
           SET revoked_at = statement_timestamp(),
               revoke_reason = reason_value
         WHERE active_tenant_id = NEW.id
           AND revoked_at IS NULL;
        RETURN NEW;
    ELSIF TG_TABLE_NAME = 'auth_identities' THEN
        IF TG_OP = 'UPDATE' THEN
            IF OLD.disabled_at IS NOT DISTINCT FROM NEW.disabled_at THEN
                RETURN NEW;
            END IF;
        END IF;
        reason_value := 'FIREBASE_IDENTITY_AUTHORIZATION_CHANGED';
        UPDATE ewms.user_sessions
           SET revoked_at = statement_timestamp(),
               revoke_reason = reason_value
         WHERE user_id = OLD.user_id
           AND revoked_at IS NULL;
        IF TG_OP = 'DELETE' THEN
            RETURN OLD;
        END IF;
        RETURN NEW;
    END IF;
    RAISE EXCEPTION 'Unsupported authorization subject table: %', TG_TABLE_NAME;
END;
$function$;

DROP TRIGGER IF EXISTS trg_revoke_sessions_after_membership_change
    ON ewms.tenant_memberships;
CREATE TRIGGER trg_revoke_sessions_after_membership_change
    AFTER UPDATE OF status, valid_from, valid_to ON ewms.tenant_memberships
    FOR EACH ROW EXECUTE PROCEDURE ewms.revoke_sessions_after_subject_change();

DROP TRIGGER IF EXISTS trg_revoke_sessions_after_user_change ON ewms.users;
CREATE TRIGGER trg_revoke_sessions_after_user_change
    AFTER UPDATE OF status, deleted_at, locked_at ON ewms.users
    FOR EACH ROW EXECUTE PROCEDURE ewms.revoke_sessions_after_subject_change();

DROP TRIGGER IF EXISTS trg_revoke_sessions_after_tenant_change ON ewms.tenants;
CREATE TRIGGER trg_revoke_sessions_after_tenant_change
    AFTER UPDATE OF status, deleted_at ON ewms.tenants
    FOR EACH ROW EXECUTE PROCEDURE ewms.revoke_sessions_after_subject_change();

DROP TRIGGER IF EXISTS trg_revoke_sessions_after_identity_change ON ewms.auth_identities;
CREATE TRIGGER trg_revoke_sessions_after_identity_change
    AFTER UPDATE OF disabled_at OR DELETE ON ewms.auth_identities
    FOR EACH ROW EXECUTE PROCEDURE ewms.revoke_sessions_after_subject_change();

REVOKE ALL ON FUNCTION ewms.revoke_sessions_after_subject_change() FROM PUBLIC;

CREATE OR REPLACE FUNCTION ewms.issue_ewms_session(
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
SET search_path = pg_catalog, ewms
AS $function$
DECLARE
    candidate_user_id uuid;
    source_row record;
    new_session_id uuid;
BEGIN
    IF p_platform_user_id IS NULL
       OR btrim(COALESCE(p_firebase_uid, '')) = ''
       OR p_active_tenant_id IS NULL
       OR p_session_handle_hash IS NULL
       OR p_session_handle_hash !~ '^[0-9A-Fa-f]{64}$' THEN
        RAISE EXCEPTION 'Canonical subject, tenant, and SHA-256 session handle hash are required'
            USING ERRCODE = '22023';
    END IF;
    IF p_provider_code NOT IN ('password','google.com')
       OR btrim(COALESCE(p_provider_subject, '')) = ''
       OR (p_provider_code = 'password' AND p_provider_subject <> p_firebase_uid) THEN
        RAISE EXCEPTION 'Invalid verified Firebase provider subject'
            USING ERRCODE = '22023';
    END IF;
    IF p_firebase_auth_time IS NULL
       OR p_firebase_auth_time > statement_timestamp() + interval '5 minutes'
       OR p_expires_at IS NULL
       OR p_expires_at <= statement_timestamp()
       OR p_expires_at > statement_timestamp() + interval '14 days'
       OR p_assurance_level NOT IN ('SINGLE_FACTOR','MULTI_FACTOR','HARDWARE_BACKED') THEN
        RAISE EXCEPTION 'Invalid authentication or session validity window'
            USING ERRCODE = '22023';
    END IF;

    SELECT ewms_user.id
      INTO candidate_user_id
      FROM ewms.users ewms_user
      JOIN kang.users platform_user
        ON platform_user.id = ewms_user.platform_user_id
       AND platform_user.firebase_uid = ewms_user.firebase_uid
     WHERE ewms_user.platform_user_id = p_platform_user_id
       AND ewms_user.firebase_project_id = 'kang-84cdd'
       AND ewms_user.firebase_uid = p_firebase_uid
       AND ewms_user.status = 'ACTIVE'
       AND ewms_user.deleted_at IS NULL
       AND ewms_user.locked_at IS NULL
     FOR SHARE OF ewms_user, platform_user;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Active canonical EWMS/Firebase user mapping is unavailable'
            USING ERRCODE = '28000';
    END IF;

    DELETE FROM ewms.session_issue_contexts
     WHERE backend_pid = pg_backend_pid();
    DELETE FROM ewms.session_issue_contexts
     WHERE expires_at <= statement_timestamp();
    INSERT INTO ewms.session_issue_contexts (
        backend_pid, transaction_id, bound_user_id, bound_tenant_id,
        established_at, expires_at
    ) VALUES (
        pg_backend_pid(), txid_current(), candidate_user_id, p_active_tenant_id,
        statement_timestamp(), statement_timestamp() + interval '1 minute'
    );

    SELECT ewms_user.id AS user_id,
           membership.id AS membership_id,
           membership.valid_to AS membership_valid_to
      INTO source_row
      FROM ewms.users ewms_user
      JOIN kang.users platform_user
        ON platform_user.id = ewms_user.platform_user_id
       AND platform_user.firebase_uid = ewms_user.firebase_uid
      JOIN ewms.auth_identities identity_row
        ON identity_row.user_id = ewms_user.id
       AND identity_row.firebase_project_id = ewms_user.firebase_project_id
       AND identity_row.firebase_tenant_id IS NOT DISTINCT FROM ewms_user.firebase_tenant_id
       AND identity_row.firebase_uid = p_firebase_uid
       AND identity_row.provider_code = p_provider_code
       AND identity_row.provider_subject = p_provider_subject
       AND identity_row.disabled_at IS NULL
      JOIN ewms.tenant_memberships membership
        ON membership.user_id = ewms_user.id
       AND membership.tenant_id = p_active_tenant_id
      JOIN ewms.tenants tenant_row ON tenant_row.id = membership.tenant_id
     WHERE ewms_user.id = candidate_user_id
       AND ewms_user.status = 'ACTIVE'
       AND ewms_user.deleted_at IS NULL
       AND ewms_user.locked_at IS NULL
       AND membership.status = 'ACTIVE'
       AND membership.valid_from <= statement_timestamp()
       AND (membership.valid_to IS NULL OR membership.valid_to > statement_timestamp())
       AND (membership.valid_to IS NULL OR p_expires_at <= membership.valid_to)
       AND tenant_row.status = 'ACTIVE'
       AND tenant_row.deleted_at IS NULL
     FOR SHARE OF ewms_user, platform_user, identity_row, membership, tenant_row;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Active identity, tenant, and membership are required for session issuance'
            USING ERRCODE = '28000';
    END IF;

    INSERT INTO ewms.user_sessions (
        user_id, active_membership_id, active_tenant_id,
        session_handle_hash, firebase_auth_time, assurance_level,
        issued_at, expires_at, last_seen_at, ip_address, user_agent
    ) VALUES (
        source_row.user_id, source_row.membership_id, p_active_tenant_id,
        lower(p_session_handle_hash), p_firebase_auth_time, p_assurance_level,
        statement_timestamp(), p_expires_at, statement_timestamp(),
        p_ip_address, p_user_agent
    )
    RETURNING id INTO new_session_id;

    DELETE FROM ewms.session_issue_contexts
     WHERE backend_pid = pg_backend_pid()
       AND transaction_id = txid_current();
    RETURN new_session_id;
END;
$function$;

REVOKE ALL ON FUNCTION ewms.issue_ewms_session(
    uuid, text, text, text, text, uuid, timestamptz, timestamptz, text, inet, text
) FROM PUBLIC;

CREATE OR REPLACE FUNCTION ewms.bind_request_context(p_session_handle_hash text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, ewms
AS $function$
DECLARE
    current_transaction_id bigint := txid_current();
    session_row record;
    membership_row record;
    existing_context record;
    effective_expiry timestamptz;
BEGIN
    IF p_session_handle_hash IS NULL
       OR p_session_handle_hash !~ '^[0-9A-Fa-f]{64}$' THEN
        RAISE EXCEPTION 'A SHA-256 server-session handle hash is required'
            USING ERRCODE = '22023';
    END IF;

    -- A context for this exact transaction is never deleted or rebound. Expiry requires a
    -- new transaction, preventing a long transaction from changing or extending its subject.
    DELETE FROM ewms.request_contexts
     WHERE backend_pid = pg_backend_pid()
       AND transaction_id <> current_transaction_id;
    DELETE FROM ewms.session_bind_contexts
     WHERE backend_pid = pg_backend_pid();

    SELECT *
      INTO existing_context
      FROM ewms.request_contexts context_row
     WHERE context_row.backend_pid = pg_backend_pid()
       AND context_row.transaction_id = current_transaction_id;

    SELECT session_data.id AS session_id,
           session_data.user_id,
           session_data.active_tenant_id,
           session_data.active_membership_id,
           session_data.expires_at
      INTO session_row
      FROM ewms.user_sessions session_data
      JOIN ewms.users ewms_user ON ewms_user.id = session_data.user_id
      JOIN ewms.tenants tenant_row ON tenant_row.id = session_data.active_tenant_id
      JOIN kang.users platform_user
        ON platform_user.id = ewms_user.platform_user_id
       AND platform_user.firebase_uid = ewms_user.firebase_uid
     WHERE session_data.session_handle_hash = lower(p_session_handle_hash)
       AND session_data.active_tenant_id IS NOT NULL
       AND session_data.active_membership_id IS NOT NULL
       AND session_data.revoked_at IS NULL
       AND session_data.issued_at <= statement_timestamp()
       AND session_data.expires_at > statement_timestamp()
       AND ewms_user.status = 'ACTIVE'
       AND ewms_user.deleted_at IS NULL
       AND ewms_user.locked_at IS NULL
       AND tenant_row.status = 'ACTIVE'
       AND tenant_row.deleted_at IS NULL
     FOR SHARE OF session_data, ewms_user, tenant_row, platform_user;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Session is expired, revoked, or unavailable'
            USING ERRCODE = '28000';
    END IF;

    IF existing_context.backend_pid IS NOT NULL THEN
        IF existing_context.session_id IS DISTINCT FROM session_row.session_id THEN
            RAISE EXCEPTION 'A transaction cannot switch its bound EWMS session'
                USING ERRCODE = '25001';
        END IF;
        IF existing_context.context_expires_at <= statement_timestamp() THEN
            RAISE EXCEPTION 'The request context expired; start a new transaction'
                USING ERRCODE = '25001';
        END IF;
        RETURN existing_context.bound_tenant_id;
    END IF;

    INSERT INTO ewms.session_bind_contexts (
        backend_pid, transaction_id, session_id, bound_user_id,
        bound_tenant_id, bound_membership_id, established_at, expires_at
    ) VALUES (
        pg_backend_pid(), current_transaction_id, session_row.session_id,
        session_row.user_id, session_row.active_tenant_id,
        session_row.active_membership_id, statement_timestamp(),
        LEAST(session_row.expires_at, statement_timestamp() + interval '1 minute')
    );

    SELECT membership.valid_to
      INTO membership_row
      FROM ewms.tenant_memberships membership
     WHERE membership.id = session_row.active_membership_id
       AND membership.user_id = session_row.user_id
       AND membership.tenant_id = session_row.active_tenant_id
       AND membership.status = 'ACTIVE'
       AND membership.valid_from <= statement_timestamp()
       AND (membership.valid_to IS NULL OR membership.valid_to > statement_timestamp())
     FOR SHARE OF membership;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'The session membership is expired, revoked, or unavailable'
            USING ERRCODE = '28000';
    END IF;

    effective_expiry := LEAST(
        session_row.expires_at,
        COALESCE(membership_row.valid_to, session_row.expires_at),
        statement_timestamp() + interval '15 minutes'
    );
    INSERT INTO ewms.request_contexts (
        backend_pid, transaction_id, session_id, bound_user_id,
        bound_tenant_id, bound_membership_id, bound_at, context_expires_at
    ) VALUES (
        pg_backend_pid(), current_transaction_id, session_row.session_id,
        session_row.user_id, session_row.active_tenant_id,
        session_row.active_membership_id, statement_timestamp(), effective_expiry
    );

    DELETE FROM ewms.session_bind_contexts
     WHERE backend_pid = pg_backend_pid()
       AND transaction_id = current_transaction_id;
    -- Do not update last_seen_at here. Concurrent requests may legitimately bind the same
    -- server session; upgrading their compatible FOR SHARE locks to row-update locks would
    -- deadlock or serialize every request until its business transaction ends. If operational
    -- last-seen telemetry is required, record it through a separate best-effort path.
    RETURN session_row.active_tenant_id;
END;
$function$;

REVOKE ALL ON FUNCTION ewms.bind_request_context(text) FROM PUBLIC;

CREATE OR REPLACE FUNCTION ewms.current_tenant_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, ewms
AS $function$
    SELECT context_row.bound_tenant_id
      FROM ewms.request_contexts context_row
      JOIN ewms.user_sessions session_row
        ON session_row.id = context_row.session_id
       AND session_row.user_id = context_row.bound_user_id
       AND session_row.active_tenant_id = context_row.bound_tenant_id
       AND session_row.active_membership_id = context_row.bound_membership_id
      JOIN ewms.users ewms_user ON ewms_user.id = session_row.user_id
      JOIN ewms.tenants tenant_row ON tenant_row.id = session_row.active_tenant_id
      JOIN kang.users platform_user
        ON platform_user.id = ewms_user.platform_user_id
       AND platform_user.firebase_uid = ewms_user.firebase_uid
     WHERE context_row.backend_pid = pg_backend_pid()
       AND context_row.transaction_id = txid_current()
       AND context_row.context_expires_at > statement_timestamp()
       AND session_row.revoked_at IS NULL
       AND session_row.issued_at <= statement_timestamp()
       AND session_row.expires_at > statement_timestamp()
       AND ewms_user.status = 'ACTIVE'
       AND ewms_user.deleted_at IS NULL
       AND ewms_user.locked_at IS NULL
       AND tenant_row.status = 'ACTIVE'
       AND tenant_row.deleted_at IS NULL;
$function$;

CREATE OR REPLACE FUNCTION ewms.current_ewms_user_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, ewms
AS $function$
    SELECT context_row.bound_user_id
      FROM ewms.request_contexts context_row
      JOIN ewms.user_sessions session_row
        ON session_row.id = context_row.session_id
       AND session_row.user_id = context_row.bound_user_id
       AND session_row.active_tenant_id = context_row.bound_tenant_id
       AND session_row.active_membership_id = context_row.bound_membership_id
      JOIN ewms.users ewms_user ON ewms_user.id = session_row.user_id
      JOIN ewms.tenants tenant_row ON tenant_row.id = session_row.active_tenant_id
      JOIN kang.users platform_user
        ON platform_user.id = ewms_user.platform_user_id
       AND platform_user.firebase_uid = ewms_user.firebase_uid
     WHERE context_row.backend_pid = pg_backend_pid()
       AND context_row.transaction_id = txid_current()
       AND context_row.context_expires_at > statement_timestamp()
       AND session_row.revoked_at IS NULL
       AND session_row.issued_at <= statement_timestamp()
       AND session_row.expires_at > statement_timestamp()
       AND ewms_user.status = 'ACTIVE'
       AND ewms_user.deleted_at IS NULL
       AND ewms_user.locked_at IS NULL
       AND tenant_row.status = 'ACTIVE'
       AND tenant_row.deleted_at IS NULL;
$function$;

COMMENT ON FUNCTION ewms.current_tenant_id() IS
    'Fail-closed tenant identity derived only from a protected server session bound to the current backend PID and transaction; ewms.tenant_id GUC values are ignored.';
COMMENT ON FUNCTION ewms.current_ewms_user_id() IS
    'Fail-closed EWMS principal derived from the same protected transaction-bound server session as current_tenant_id().';

REVOKE ALL ON FUNCTION ewms.current_tenant_id() FROM PUBLIC;
REVOKE ALL ON FUNCTION ewms.current_ewms_user_id() FROM PUBLIC;

CREATE OR REPLACE FUNCTION ewms.cleanup_request_contexts(
    p_older_than interval DEFAULT interval '1 day'
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, ewms
AS $function$
DECLARE
    deleted_count bigint := 0;
    step_count bigint;
BEGIN
    IF p_older_than IS NULL OR p_older_than < interval '1 hour' THEN
        RAISE EXCEPTION 'Context cleanup window must be at least one hour'
            USING ERRCODE = '22023';
    END IF;
    DELETE FROM ewms.request_contexts
     WHERE context_expires_at <= statement_timestamp()
        OR bound_at < statement_timestamp() - p_older_than;
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    DELETE FROM ewms.session_bind_contexts
     WHERE expires_at <= statement_timestamp()
        OR established_at < statement_timestamp() - p_older_than;
    GET DIAGNOSTICS step_count = ROW_COUNT;
    deleted_count := deleted_count + step_count;
    DELETE FROM ewms.session_issue_contexts
     WHERE expires_at <= statement_timestamp()
        OR established_at < statement_timestamp() - p_older_than;
    GET DIAGNOSTICS step_count = ROW_COUNT;
    RETURN deleted_count + step_count;
END;
$function$;

REVOKE ALL ON FUNCTION ewms.cleanup_request_contexts(interval) FROM PUBLIC;

-- Replace every baseline tenant policy after current_tenant_id() has become fail-closed.
-- Only membership SELECT gets narrow transaction-local bootstrap branches; no bootstrap
-- context can modify memberships or any other tenant-owned table.
DO $policies$
DECLARE
    target record;
    existing_policy record;
    global_reference_tables constant text[] := ARRAY[
        'roles','role_permissions','code_sets','code_values','data_retention_policies',
        'exchange_rates','tax_codes','tax_rates','payment_terms','charge_codes','reason_codes',
        'inventory_statuses','location_types','material_handling_equipment_types','lpn_types',
        'status_definitions','status_transitions','notification_templates','scheduled_jobs',
        'bonded_storage_rules','sod_rules','sod_rule_conflicts','kpi_definitions',
        'data_quality_rules'
    ]::text[];
    platform_event_tables constant text[] := ARRAY[
        'login_events','audit_events','data_access_logs'
    ]::text[];
    global_job_tables constant text[] := ARRAY['job_runs','job_run_events']::text[];
    select_expression text;
    modify_expression text;
BEGIN
    FOR target IN
        SELECT DISTINCT column_meta.table_schema, column_meta.table_name
          FROM information_schema.columns column_meta
          JOIN information_schema.tables table_meta
            ON table_meta.table_schema = column_meta.table_schema
           AND table_meta.table_name = column_meta.table_name
           AND table_meta.table_type = 'BASE TABLE'
         WHERE column_meta.table_schema = 'ewms'
           AND column_meta.column_name = 'tenant_id'
    LOOP
        EXECUTE format('ALTER TABLE %I.%I ENABLE ROW LEVEL SECURITY',
                       target.table_schema, target.table_name);
        -- PostgreSQL 11 OR-combines permissive policies. Remove every pre-existing policy,
        -- including stale/custom names, so a legacy USING (true) branch cannot survive a
        -- hardening reapply and bypass the two canonical fail-closed policies below.
        FOR existing_policy IN
            SELECT policy_row.polname
              FROM pg_policy policy_row
             WHERE policy_row.polrelid = format(
                       '%I.%I', target.table_schema, target.table_name
                   )::regclass
        LOOP
            EXECUTE format(
                'DROP POLICY %I ON %I.%I',
                existing_policy.polname, target.table_schema, target.table_name
            );
        END LOOP;

        IF target.table_name = 'tenant_memberships' THEN
            select_expression := 'tenant_id = ewms.current_tenant_id() OR '
                || 'ewms.has_active_session_issue_context(user_id, tenant_id) OR '
                || 'ewms.has_active_session_bind_context(id, user_id, tenant_id)';
            modify_expression := 'tenant_id = ewms.current_tenant_id()';
        ELSIF target.table_name = ANY (global_reference_tables) THEN
            select_expression := 'tenant_id IS NULL OR tenant_id = ewms.current_tenant_id()';
            modify_expression := 'tenant_id = ewms.current_tenant_id()';
        ELSIF target.table_name = ANY (platform_event_tables) THEN
            select_expression := 'tenant_id = ewms.current_tenant_id() OR '
                || '(tenant_id IS NULL AND current_user = ''ewms_platform_logger'')';
            modify_expression := select_expression;
        ELSIF target.table_name = ANY (global_job_tables) THEN
            select_expression := 'tenant_id = ewms.current_tenant_id() OR '
                || '(tenant_id IS NULL AND current_user = ''ewms_global_job_runner'')';
            modify_expression := select_expression;
        ELSE
            select_expression := 'tenant_id = ewms.current_tenant_id()';
            modify_expression := select_expression;
        END IF;

        EXECUTE format(
            'CREATE POLICY tenant_select ON %I.%I FOR SELECT USING (%s)',
            target.table_schema, target.table_name, select_expression
        );
        EXECUTE format(
            'CREATE POLICY tenant_modify ON %I.%I FOR ALL USING (%s) WITH CHECK (%s)',
            target.table_schema, target.table_name, modify_expression, modify_expression
        );
        EXECUTE format('ALTER TABLE %I.%I FORCE ROW LEVEL SECURITY',
                       target.table_schema, target.table_name);
    END LOOP;
END;
$policies$;

-- Functions created after module 12 would otherwise regain PostgreSQL's default PUBLIC
-- EXECUTE. Keep the module independently safe even if a future deployment omits the role
-- template; the template grants only the reviewed entry points to dedicated roles.
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA ewms FROM PUBLIC;
