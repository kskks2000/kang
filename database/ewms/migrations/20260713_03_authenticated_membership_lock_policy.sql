-- EWMS forward-only migration 20260713_03
-- Permit authenticated bootstrap functions to take a row lock on the exact active
-- membership while keeping normal membership DML fail-closed.
-- PostgreSQL 11 compatible and idempotent.
--
-- PostgreSQL applies an UPDATE RLS USING policy to SELECT ... FOR SHARE/UPDATE.
-- Module 13 exposed the membership through its SELECT bootstrap branch but kept the
-- UPDATE policy tenant-only, so issue_ewms_session() and bind_request_context() saw no
-- row when they requested the concurrency-safe membership lock.  The protected marker
-- tables are not directly accessible to application roles and each marker is deleted
-- before its SECURITY DEFINER entry point returns.

DO $preflight$
BEGIN
    IF to_regprocedure('ewms.has_active_session_issue_context(uuid,uuid)') IS NULL
       OR to_regprocedure('ewms.has_active_session_bind_context(uuid,uuid,uuid)') IS NULL
       OR to_regprocedure('ewms.issue_ewms_session(uuid,text,text,text,text,uuid,timestamp with time zone,timestamp with time zone,text,inet,text)') IS NULL
       OR to_regprocedure('ewms.bind_request_context(text)') IS NULL THEN
        RAISE EXCEPTION 'EWMS authenticated request-context baseline is incomplete';
    END IF;
    IF NOT EXISTS (
        SELECT 1
          FROM pg_class relation
          JOIN pg_namespace namespace_row ON namespace_row.oid = relation.relnamespace
         WHERE namespace_row.nspname = 'ewms'
           AND relation.relname = 'tenant_memberships'
           AND relation.relkind = 'r'
           AND relation.relrowsecurity
           AND relation.relforcerowsecurity
    ) THEN
        RAISE EXCEPTION 'ewms.tenant_memberships must have ENABLE/FORCE RLS';
    END IF;
END;
$preflight$;

DROP POLICY IF EXISTS tenant_modify ON ewms.tenant_memberships;
CREATE POLICY tenant_modify
    ON ewms.tenant_memberships
    FOR ALL
    USING (
        tenant_id = ewms.current_tenant_id()
        OR ewms.has_active_session_issue_context(user_id, tenant_id)
        OR ewms.has_active_session_bind_context(id, user_id, tenant_id)
    )
    WITH CHECK (tenant_id = ewms.current_tenant_id());

COMMENT ON POLICY tenant_modify ON ewms.tenant_memberships IS
    'Normal DML remains current-tenant only. Protected, transaction-local bootstrap markers are included in USING solely so session issue/bind can acquire a concurrency-safe membership row lock; application roles have no direct membership DML ACL.';

DO $verify$
DECLARE
    policy_using text;
    policy_check text;
BEGIN
    SELECT pg_get_expr(policy_row.polqual, policy_row.polrelid),
           pg_get_expr(policy_row.polwithcheck, policy_row.polrelid)
      INTO policy_using, policy_check
      FROM pg_policy policy_row
     WHERE policy_row.polrelid = 'ewms.tenant_memberships'::regclass
       AND policy_row.polname = 'tenant_modify'
       AND policy_row.polcmd = '*'
       AND policy_row.polpermissive
       AND policy_row.polroles = ARRAY[0::oid];

    IF policy_using IS NULL
       OR position('current_tenant_id()' IN lower(policy_using)) = 0
       OR position('has_active_session_issue_context' IN lower(policy_using)) = 0
       OR position('has_active_session_bind_context' IN lower(policy_using)) = 0
       OR policy_check IS NULL
       OR position('current_tenant_id()' IN lower(policy_check)) = 0
       OR position('has_active_session_issue_context' IN lower(policy_check)) <> 0
       OR position('has_active_session_bind_context' IN lower(policy_check)) <> 0 THEN
        RAISE EXCEPTION 'EWMS membership bootstrap lock policy verification failed';
    END IF;
END;
$verify$;

