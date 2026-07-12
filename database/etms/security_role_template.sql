-- DBA review template only. scripts/apply_etms_schema.py never executes this file.
-- The migration owner cannot create roles; a CREATEROLE-capable DBA must adapt it.

DO $block$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'etms_runtime') THEN
        CREATE ROLE etms_runtime
            NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'etms_auth_service') THEN
        CREATE ROLE etms_auth_service
            NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'etms_membership_admin') THEN
        CREATE ROLE etms_membership_admin
            NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;
    END IF;
END;
$block$;

GRANT USAGE ON SCHEMA etms TO etms_runtime, etms_auth_service, etms_membership_admin;

-- Every ordinary request binds a server-side session hash. A client-provided
-- tenant ID or `SET etms.tenant_id` is never an authorization source.
GRANT EXECUTE ON FUNCTION etms.bind_request_context(text) TO etms_runtime;
GRANT EXECUTE ON FUNCTION etms.current_tenant_id() TO etms_runtime;
GRANT EXECUTE ON FUNCTION etms.current_etms_user_id() TO etms_runtime;
GRANT EXECUTE ON FUNCTION etms.generate_uuid() TO etms_runtime;
GRANT EXECUTE ON FUNCTION etms.is_etms_owner_execution()
    TO etms_runtime, etms_auth_service, etms_membership_admin;

-- Authentication and membership provisioning are deliberately separated from
-- normal runtime access. Grant these group roles to different login/service roles.
GRANT EXECUTE ON FUNCTION etms.issue_auth_session(
    uuid,text,text,text,text,uuid,timestamptz,timestamptz,text,inet,text
) TO etms_auth_service;
GRANT EXECUTE ON FUNCTION etms.record_preauth_login_event(
    text,text,boolean,text,text,inet,text,text,timestamptz
) TO etms_auth_service;
GRANT EXECUTE ON FUNCTION etms.record_preauth_security_audit(
    text,text,inet,text,text
) TO etms_auth_service;
GRANT EXECUTE ON FUNCTION etms.provision_tenant_membership(
    uuid,uuid,uuid,text,text,timestamptz,timestamptz
) TO etms_membership_admin;

-- No blanket table DML or ALL-FUNCTION grant is intentional. The DBA should grant
-- SELECT/INSERT/UPDATE/DELETE only to the exact service-owned tables for each
-- application login role. Never grant direct access to the following control plane.
REVOKE ALL ON TABLE etms.schema_migrations FROM etms_runtime, etms_auth_service, etms_membership_admin;
REVOKE ALL ON TABLE etms.request_contexts FROM etms_runtime, etms_auth_service, etms_membership_admin;
REVOKE ALL ON TABLE etms.session_issue_contexts FROM etms_runtime, etms_auth_service, etms_membership_admin;
REVOKE ALL ON TABLE etms.membership_provision_contexts FROM etms_runtime, etms_auth_service, etms_membership_admin;
REVOKE ALL ON TABLE etms.identity_command_contexts FROM etms_runtime, etms_auth_service, etms_membership_admin;
REVOKE ALL ON TABLE etms.auth_sessions FROM etms_runtime, etms_auth_service, etms_membership_admin;

-- Example only:
-- CREATE ROLE etms_api_login LOGIN ... NOBYPASSRLS;
-- GRANT etms_runtime, etms_auth_service TO etms_api_login;
-- GRANT SELECT ON etms.transport_orders, etms.shipments, etms.transport_runs TO etms_runtime;
-- GRANT INSERT, UPDATE ON etms.transport_orders TO etms_runtime;
