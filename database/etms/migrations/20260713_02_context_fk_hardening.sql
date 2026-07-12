-- ETMS forward migration: bind protected control-plane contexts to canonical
-- session and tenant-membership subjects. PostgreSQL 11 compatible.

CREATE INDEX IF NOT EXISTS ix_request_context_session_subject
    ON etms.request_contexts (
        bound_session_id, bound_user_id, bound_tenant_id, bound_membership_id
    );

CREATE INDEX IF NOT EXISTS ix_request_context_membership_subject
    ON etms.request_contexts (
        bound_membership_id, bound_user_id, bound_tenant_id
    );

CREATE INDEX IF NOT EXISTS ix_session_issue_context_membership_subject
    ON etms.session_issue_contexts (
        bound_membership_id, bound_user_id, bound_tenant_id
    );

CREATE INDEX IF NOT EXISTS ix_membership_provision_context_membership_subject
    ON etms.membership_provision_contexts (
        bound_membership_id, bound_user_id, bound_tenant_id
    );

CREATE INDEX IF NOT EXISTS ix_identity_command_context_membership_subject
    ON etms.identity_command_contexts (
        bound_membership_id, bound_user_id, bound_tenant_id
    );

-- A provisioning context row is transaction-scoped and may be reused by a
-- second provisioning call in the same transaction.  Clear the membership
-- resolved for the previous subject before the composite FK is checked; the
-- reviewed provisioning function writes the new membership back after it is
-- created or reactivated.
CREATE OR REPLACE FUNCTION etms.reset_membership_provision_subject()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    IF NEW.bound_tenant_id IS DISTINCT FROM OLD.bound_tenant_id
       OR NEW.bound_user_id IS DISTINCT FROM OLD.bound_user_id THEN
        NEW.bound_membership_id := NULL;
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_reset_membership_provision_subject
    ON etms.membership_provision_contexts;
CREATE TRIGGER trg_reset_membership_provision_subject
    BEFORE UPDATE OF bound_tenant_id, bound_user_id
    ON etms.membership_provision_contexts
    FOR EACH ROW EXECUTE PROCEDURE etms.reset_membership_provision_subject();

REVOKE ALL ON FUNCTION etms.reset_membership_provision_subject() FROM PUBLIC;

-- The immutable baseline declared these two single-column FKs with NO ACTION.
-- Keep the redundant existence checks, but align them with the request-row
-- lifecycle so the composite CASCADE actions cannot be contradicted or obscured.
DO $migration$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint constraint_row
        WHERE constraint_row.conrelid = 'etms.request_contexts'::regclass
          AND constraint_row.confrelid = 'etms.auth_sessions'::regclass
          AND constraint_row.conname = 'request_contexts_bound_session_id_fkey'
          AND constraint_row.contype = 'f'
          AND constraint_row.convalidated
          AND NOT constraint_row.condeferrable
          AND constraint_row.confmatchtype = 's'
          AND constraint_row.confupdtype = 'a'
          AND constraint_row.confdeltype = 'c'
          AND constraint_row.conkey = ARRAY[
              (SELECT attnum FROM pg_attribute
               WHERE attrelid = 'etms.request_contexts'::regclass
                 AND attname = 'bound_session_id' AND NOT attisdropped)
          ]::smallint[]
          AND constraint_row.confkey = ARRAY[
              (SELECT attnum FROM pg_attribute
               WHERE attrelid = 'etms.auth_sessions'::regclass
                 AND attname = 'id' AND NOT attisdropped)
          ]::smallint[]
    ) THEN
        ALTER TABLE etms.request_contexts
            DROP CONSTRAINT IF EXISTS request_contexts_bound_session_id_fkey;
        ALTER TABLE etms.request_contexts
            ADD CONSTRAINT request_contexts_bound_session_id_fkey
            FOREIGN KEY (bound_session_id)
            REFERENCES etms.auth_sessions (id)
            MATCH SIMPLE
            ON DELETE CASCADE;
    END IF;
END;
$migration$;

DO $migration$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint constraint_row
        WHERE constraint_row.conrelid = 'etms.request_contexts'::regclass
          AND constraint_row.confrelid = 'etms.tenant_memberships'::regclass
          AND constraint_row.conname = 'request_contexts_bound_membership_id_fkey'
          AND constraint_row.contype = 'f'
          AND constraint_row.convalidated
          AND NOT constraint_row.condeferrable
          AND constraint_row.confmatchtype = 's'
          AND constraint_row.confupdtype = 'a'
          AND constraint_row.confdeltype = 'c'
          AND constraint_row.conkey = ARRAY[
              (SELECT attnum FROM pg_attribute
               WHERE attrelid = 'etms.request_contexts'::regclass
                 AND attname = 'bound_membership_id' AND NOT attisdropped)
          ]::smallint[]
          AND constraint_row.confkey = ARRAY[
              (SELECT attnum FROM pg_attribute
               WHERE attrelid = 'etms.tenant_memberships'::regclass
                 AND attname = 'id' AND NOT attisdropped)
          ]::smallint[]
    ) THEN
        ALTER TABLE etms.request_contexts
            DROP CONSTRAINT IF EXISTS request_contexts_bound_membership_id_fkey;
        ALTER TABLE etms.request_contexts
            ADD CONSTRAINT request_contexts_bound_membership_id_fkey
            FOREIGN KEY (bound_membership_id)
            REFERENCES etms.tenant_memberships (id)
            MATCH SIMPLE
            ON DELETE CASCADE;
    END IF;
END;
$migration$;

DO $migration$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint constraint_row
        WHERE constraint_row.conrelid = 'etms.request_contexts'::regclass
          AND constraint_row.conname = 'fk_request_context_session_subject'
    ) THEN
        ALTER TABLE etms.request_contexts
            ADD CONSTRAINT fk_request_context_session_subject
            FOREIGN KEY (
                bound_session_id, bound_user_id, bound_tenant_id, bound_membership_id
            )
            REFERENCES etms.auth_sessions (
                id, user_id, active_tenant_id, active_membership_id
            )
            MATCH SIMPLE
            ON DELETE CASCADE;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint constraint_row
        WHERE constraint_row.conrelid = 'etms.request_contexts'::regclass
          AND constraint_row.confrelid = 'etms.auth_sessions'::regclass
          AND constraint_row.conname = 'fk_request_context_session_subject'
          AND constraint_row.contype = 'f'
          AND constraint_row.convalidated
          AND NOT constraint_row.condeferrable
          AND constraint_row.confmatchtype = 's'
          AND constraint_row.confupdtype = 'a'
          AND constraint_row.confdeltype = 'c'
          AND constraint_row.conkey = ARRAY[
              (SELECT attnum FROM pg_attribute
               WHERE attrelid = 'etms.request_contexts'::regclass
                 AND attname = 'bound_session_id' AND NOT attisdropped),
              (SELECT attnum FROM pg_attribute
               WHERE attrelid = 'etms.request_contexts'::regclass
                 AND attname = 'bound_user_id' AND NOT attisdropped),
              (SELECT attnum FROM pg_attribute
               WHERE attrelid = 'etms.request_contexts'::regclass
                 AND attname = 'bound_tenant_id' AND NOT attisdropped),
              (SELECT attnum FROM pg_attribute
               WHERE attrelid = 'etms.request_contexts'::regclass
                 AND attname = 'bound_membership_id' AND NOT attisdropped)
          ]::smallint[]
          AND constraint_row.confkey = ARRAY[
              (SELECT attnum FROM pg_attribute
               WHERE attrelid = 'etms.auth_sessions'::regclass
                 AND attname = 'id' AND NOT attisdropped),
              (SELECT attnum FROM pg_attribute
               WHERE attrelid = 'etms.auth_sessions'::regclass
                 AND attname = 'user_id' AND NOT attisdropped),
              (SELECT attnum FROM pg_attribute
               WHERE attrelid = 'etms.auth_sessions'::regclass
                 AND attname = 'active_tenant_id' AND NOT attisdropped),
              (SELECT attnum FROM pg_attribute
               WHERE attrelid = 'etms.auth_sessions'::regclass
                 AND attname = 'active_membership_id' AND NOT attisdropped)
          ]::smallint[]
    ) THEN
        RAISE EXCEPTION
            'fk_request_context_session_subject exists with an incompatible definition';
    END IF;
END;
$migration$;

DO $migration$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint constraint_row
        WHERE constraint_row.conrelid = 'etms.request_contexts'::regclass
          AND constraint_row.conname = 'fk_request_context_membership_subject'
    ) THEN
        ALTER TABLE etms.request_contexts
            ADD CONSTRAINT fk_request_context_membership_subject
            FOREIGN KEY (bound_membership_id, bound_user_id, bound_tenant_id)
            REFERENCES etms.tenant_memberships (id, user_id, tenant_id)
            MATCH SIMPLE
            ON DELETE CASCADE;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint constraint_row
        WHERE constraint_row.conrelid = 'etms.request_contexts'::regclass
          AND constraint_row.confrelid = 'etms.tenant_memberships'::regclass
          AND constraint_row.conname = 'fk_request_context_membership_subject'
          AND constraint_row.contype = 'f'
          AND constraint_row.convalidated
          AND NOT constraint_row.condeferrable
          AND constraint_row.confmatchtype = 's'
          AND constraint_row.confupdtype = 'a'
          AND constraint_row.confdeltype = 'c'
          AND constraint_row.conkey = ARRAY[
              (SELECT attnum FROM pg_attribute
               WHERE attrelid = 'etms.request_contexts'::regclass
                 AND attname = 'bound_membership_id' AND NOT attisdropped),
              (SELECT attnum FROM pg_attribute
               WHERE attrelid = 'etms.request_contexts'::regclass
                 AND attname = 'bound_user_id' AND NOT attisdropped),
              (SELECT attnum FROM pg_attribute
               WHERE attrelid = 'etms.request_contexts'::regclass
                 AND attname = 'bound_tenant_id' AND NOT attisdropped)
          ]::smallint[]
          AND constraint_row.confkey = ARRAY[
              (SELECT attnum FROM pg_attribute
               WHERE attrelid = 'etms.tenant_memberships'::regclass
                 AND attname = 'id' AND NOT attisdropped),
              (SELECT attnum FROM pg_attribute
               WHERE attrelid = 'etms.tenant_memberships'::regclass
                 AND attname = 'user_id' AND NOT attisdropped),
              (SELECT attnum FROM pg_attribute
               WHERE attrelid = 'etms.tenant_memberships'::regclass
                 AND attname = 'tenant_id' AND NOT attisdropped)
          ]::smallint[]
    ) THEN
        RAISE EXCEPTION
            'fk_request_context_membership_subject exists with an incompatible definition';
    END IF;
END;
$migration$;

DO $migration$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint constraint_row
        WHERE constraint_row.conrelid = 'etms.session_issue_contexts'::regclass
          AND constraint_row.conname = 'fk_session_issue_context_membership_subject'
    ) THEN
        ALTER TABLE etms.session_issue_contexts
            ADD CONSTRAINT fk_session_issue_context_membership_subject
            FOREIGN KEY (bound_membership_id, bound_user_id, bound_tenant_id)
            REFERENCES etms.tenant_memberships (id, user_id, tenant_id)
            MATCH SIMPLE
            ON DELETE RESTRICT;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint constraint_row
        WHERE constraint_row.conrelid = 'etms.session_issue_contexts'::regclass
          AND constraint_row.confrelid = 'etms.tenant_memberships'::regclass
          AND constraint_row.conname = 'fk_session_issue_context_membership_subject'
          AND constraint_row.contype = 'f'
          AND constraint_row.convalidated
          AND NOT constraint_row.condeferrable
          AND constraint_row.confmatchtype = 's'
          AND constraint_row.confupdtype = 'a'
          AND constraint_row.confdeltype = 'r'
          AND constraint_row.conkey = ARRAY[
              (SELECT attnum FROM pg_attribute
               WHERE attrelid = 'etms.session_issue_contexts'::regclass
                 AND attname = 'bound_membership_id' AND NOT attisdropped),
              (SELECT attnum FROM pg_attribute
               WHERE attrelid = 'etms.session_issue_contexts'::regclass
                 AND attname = 'bound_user_id' AND NOT attisdropped),
              (SELECT attnum FROM pg_attribute
               WHERE attrelid = 'etms.session_issue_contexts'::regclass
                 AND attname = 'bound_tenant_id' AND NOT attisdropped)
          ]::smallint[]
          AND constraint_row.confkey = ARRAY[
              (SELECT attnum FROM pg_attribute
               WHERE attrelid = 'etms.tenant_memberships'::regclass
                 AND attname = 'id' AND NOT attisdropped),
              (SELECT attnum FROM pg_attribute
               WHERE attrelid = 'etms.tenant_memberships'::regclass
                 AND attname = 'user_id' AND NOT attisdropped),
              (SELECT attnum FROM pg_attribute
               WHERE attrelid = 'etms.tenant_memberships'::regclass
                 AND attname = 'tenant_id' AND NOT attisdropped)
          ]::smallint[]
    ) THEN
        RAISE EXCEPTION
            'fk_session_issue_context_membership_subject exists with an incompatible definition';
    END IF;
END;
$migration$;

DO $migration$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint constraint_row
        WHERE constraint_row.conrelid = 'etms.membership_provision_contexts'::regclass
          AND constraint_row.conname = 'fk_membership_provision_context_membership_subject'
    ) THEN
        ALTER TABLE etms.membership_provision_contexts
            ADD CONSTRAINT fk_membership_provision_context_membership_subject
            FOREIGN KEY (bound_membership_id, bound_user_id, bound_tenant_id)
            REFERENCES etms.tenant_memberships (id, user_id, tenant_id)
            MATCH SIMPLE
            ON DELETE RESTRICT;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint constraint_row
        WHERE constraint_row.conrelid = 'etms.membership_provision_contexts'::regclass
          AND constraint_row.confrelid = 'etms.tenant_memberships'::regclass
          AND constraint_row.conname = 'fk_membership_provision_context_membership_subject'
          AND constraint_row.contype = 'f'
          AND constraint_row.convalidated
          AND NOT constraint_row.condeferrable
          AND constraint_row.confmatchtype = 's'
          AND constraint_row.confupdtype = 'a'
          AND constraint_row.confdeltype = 'r'
          AND constraint_row.conkey = ARRAY[
              (SELECT attnum FROM pg_attribute
               WHERE attrelid = 'etms.membership_provision_contexts'::regclass
                 AND attname = 'bound_membership_id' AND NOT attisdropped),
              (SELECT attnum FROM pg_attribute
               WHERE attrelid = 'etms.membership_provision_contexts'::regclass
                 AND attname = 'bound_user_id' AND NOT attisdropped),
              (SELECT attnum FROM pg_attribute
               WHERE attrelid = 'etms.membership_provision_contexts'::regclass
                 AND attname = 'bound_tenant_id' AND NOT attisdropped)
          ]::smallint[]
          AND constraint_row.confkey = ARRAY[
              (SELECT attnum FROM pg_attribute
               WHERE attrelid = 'etms.tenant_memberships'::regclass
                 AND attname = 'id' AND NOT attisdropped),
              (SELECT attnum FROM pg_attribute
               WHERE attrelid = 'etms.tenant_memberships'::regclass
                 AND attname = 'user_id' AND NOT attisdropped),
              (SELECT attnum FROM pg_attribute
               WHERE attrelid = 'etms.tenant_memberships'::regclass
                 AND attname = 'tenant_id' AND NOT attisdropped)
          ]::smallint[]
    ) THEN
        RAISE EXCEPTION
            'fk_membership_provision_context_membership_subject exists with an incompatible definition';
    END IF;
END;
$migration$;

DO $migration$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint constraint_row
        WHERE constraint_row.conrelid = 'etms.identity_command_contexts'::regclass
          AND constraint_row.conname = 'fk_identity_command_context_membership_subject'
    ) THEN
        ALTER TABLE etms.identity_command_contexts
            ADD CONSTRAINT fk_identity_command_context_membership_subject
            FOREIGN KEY (bound_membership_id, bound_user_id, bound_tenant_id)
            REFERENCES etms.tenant_memberships (id, user_id, tenant_id)
            MATCH SIMPLE
            ON DELETE RESTRICT;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint constraint_row
        WHERE constraint_row.conrelid = 'etms.identity_command_contexts'::regclass
          AND constraint_row.confrelid = 'etms.tenant_memberships'::regclass
          AND constraint_row.conname = 'fk_identity_command_context_membership_subject'
          AND constraint_row.contype = 'f'
          AND constraint_row.convalidated
          AND NOT constraint_row.condeferrable
          AND constraint_row.confmatchtype = 's'
          AND constraint_row.confupdtype = 'a'
          AND constraint_row.confdeltype = 'r'
          AND constraint_row.conkey = ARRAY[
              (SELECT attnum FROM pg_attribute
               WHERE attrelid = 'etms.identity_command_contexts'::regclass
                 AND attname = 'bound_membership_id' AND NOT attisdropped),
              (SELECT attnum FROM pg_attribute
               WHERE attrelid = 'etms.identity_command_contexts'::regclass
                 AND attname = 'bound_user_id' AND NOT attisdropped),
              (SELECT attnum FROM pg_attribute
               WHERE attrelid = 'etms.identity_command_contexts'::regclass
                 AND attname = 'bound_tenant_id' AND NOT attisdropped)
          ]::smallint[]
          AND constraint_row.confkey = ARRAY[
              (SELECT attnum FROM pg_attribute
               WHERE attrelid = 'etms.tenant_memberships'::regclass
                 AND attname = 'id' AND NOT attisdropped),
              (SELECT attnum FROM pg_attribute
               WHERE attrelid = 'etms.tenant_memberships'::regclass
                 AND attname = 'user_id' AND NOT attisdropped),
              (SELECT attnum FROM pg_attribute
               WHERE attrelid = 'etms.tenant_memberships'::regclass
                 AND attname = 'tenant_id' AND NOT attisdropped)
          ]::smallint[]
    ) THEN
        RAISE EXCEPTION
            'fk_identity_command_context_membership_subject exists with an incompatible definition';
    END IF;
END;
$migration$;
