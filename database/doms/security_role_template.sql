-- DOMS DBA-reviewed role template. This file is intentionally not applied by
-- scripts/apply_doms_schema.py. Run only after replacing login-role placeholders,
-- reviewing endpoint-specific grants, and confirming the roles are NOBYPASSRLS.

DO $block$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'doms_authenticator') THEN
        EXECUTE 'CREATE ROLE doms_authenticator NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'doms_tenant_provisioner') THEN
        EXECUTE 'CREATE ROLE doms_tenant_provisioner NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'doms_runtime') THEN
        EXECUTE 'CREATE ROLE doms_runtime NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'doms_readonly') THEN
        EXECUTE 'CREATE ROLE doms_readonly NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'doms_platform_logger') THEN
        EXECUTE 'CREATE ROLE doms_platform_logger NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'doms_global_job_runner') THEN
        EXECUTE 'CREATE ROLE doms_global_job_runner NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS';
    END IF;
END;
$block$;

REVOKE ALL ON SCHEMA doms FROM doms_runtime, doms_readonly,
    doms_platform_logger, doms_global_job_runner, doms_authenticator,
    doms_tenant_provisioner;
REVOKE ALL ON ALL TABLES IN SCHEMA doms FROM doms_runtime, doms_readonly,
    doms_platform_logger, doms_global_job_runner, doms_authenticator,
    doms_tenant_provisioner;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA doms FROM doms_runtime, doms_readonly,
    doms_platform_logger, doms_global_job_runner, doms_authenticator,
    doms_tenant_provisioner;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA doms FROM doms_runtime, doms_readonly,
    doms_platform_logger, doms_global_job_runner, doms_authenticator,
    doms_tenant_provisioner;

GRANT USAGE ON SCHEMA doms TO doms_runtime, doms_readonly,
    doms_platform_logger, doms_global_job_runner, doms_authenticator,
    doms_tenant_provisioner;

-- SECURITY DEFINER functions deliberately retain the migration/schema owner.
-- Application roles receive EXECUTE only; they never receive the owner's role,
-- auth-table DML, BYPASSRLS, or ownership of schema objects.

-- Safe global/reference reads. Tenant-specific rows remain governed by RLS.
GRANT SELECT ON TABLE
    doms.countries,
    doms.currencies,
    doms.units_of_measure,
    doms.unit_conversions,
    doms.transport_modes,
    doms.incoterms,
    doms.tax_codes,
    doms.tax_rates,
    doms.payment_terms,
    doms.charge_codes,
    doms.reason_codes,
    doms.order_types,
    doms.delivery_methods,
    doms.status_definitions
TO doms_runtime, doms_readonly;

GRANT EXECUTE ON FUNCTION doms.current_tenant_id()
TO doms_runtime, doms_readonly, doms_platform_logger, doms_global_job_runner,
    doms_authenticator;
GRANT EXECUTE ON FUNCTION doms.current_doms_user_id()
TO doms_runtime, doms_readonly, doms_platform_logger, doms_global_job_runner,
    doms_authenticator;
GRANT EXECUTE ON FUNCTION doms.has_active_session_issue_context(uuid, uuid)
TO doms_runtime, doms_readonly, doms_authenticator;
GRANT EXECUTE ON FUNCTION doms.has_active_membership_provision_context(uuid, uuid),
    doms.is_membership_provision_candidate(uuid, uuid, uuid),
    doms.has_membership_provision_audit_context(uuid, uuid)
TO doms_runtime, doms_readonly, doms_platform_logger, doms_global_job_runner,
    doms_authenticator, doms_tenant_provisioner;

-- A normal request role receives only the opaque-session binder. It cannot mint,
-- revoke, bootstrap, or link identities, and it has no direct DML on auth tables.
GRANT EXECUTE ON FUNCTION doms.bind_request_context(text)
TO doms_runtime, doms_readonly;

-- Authentication endpoints use this distinct callable role. The functions run
-- as the migration/schema owner and validate Firebase/canonical-user/membership state.
GRANT EXECUTE ON FUNCTION doms.bootstrap_firebase_identity(uuid, text, text, text)
TO doms_authenticator;
GRANT EXECUTE ON FUNCTION doms.complete_account_link_identity(uuid)
TO doms_authenticator;
GRANT EXECUTE ON FUNCTION doms.issue_user_session(
    uuid, text, text, text, text, uuid, timestamptz, timestamptz, text, inet, text
) TO doms_authenticator;
GRANT EXECUTE ON FUNCTION doms.revoke_user_session(text, text)
TO doms_authenticator;
GRANT EXECUTE ON FUNCTION doms.cleanup_request_contexts(interval)
TO doms_authenticator;

REVOKE EXECUTE ON FUNCTION doms.bootstrap_firebase_identity(uuid, text, text, text)
FROM doms_runtime, doms_readonly, doms_platform_logger, doms_global_job_runner;
REVOKE EXECUTE ON FUNCTION doms.complete_account_link_identity(uuid)
FROM doms_runtime, doms_readonly, doms_platform_logger, doms_global_job_runner;
REVOKE EXECUTE ON FUNCTION doms.issue_user_session(
    uuid, text, text, text, text, uuid, timestamptz, timestamptz, text, inet, text
) FROM doms_runtime, doms_readonly, doms_platform_logger, doms_global_job_runner;
REVOKE EXECUTE ON FUNCTION doms.revoke_user_session(text, text)
FROM doms_runtime, doms_readonly, doms_platform_logger, doms_global_job_runner;
REVOKE EXECUTE ON FUNCTION doms.cleanup_request_contexts(interval)
FROM doms_runtime, doms_readonly, doms_platform_logger, doms_global_job_runner;

-- Initial and administrative tenant onboarding is isolated from authentication.
-- This role has no table privileges and can create only one validated membership
-- plus its append-only, correlation-bearing audit event per command invocation.
GRANT EXECUTE ON FUNCTION doms.provision_tenant_membership(
    uuid, uuid, text, text, uuid, text, timestamptz, timestamptz, text
) TO doms_tenant_provisioner;
REVOKE EXECUTE ON FUNCTION doms.provision_tenant_membership(
    uuid, uuid, text, text, uuid, text, timestamptz, timestamptz, text
) FROM doms_runtime, doms_readonly, doms_platform_logger,
    doms_global_job_runner, doms_authenticator;

-- Reviewed inventory-promise command entry points. These functions still require
-- a verified tenant context and enforce row locks, idempotency, and quantity caps.
GRANT EXECUTE ON FUNCTION doms.apply_inventory_position_delta(
    uuid, uuid, varchar, numeric, varchar, varchar, varchar, varchar, timestamptz, jsonb
) TO doms_runtime;
GRANT EXECUTE ON FUNCTION doms.activate_inventory_reservation(
    uuid, uuid, varchar, uuid
) TO doms_runtime;
GRANT EXECUTE ON FUNCTION doms.transition_inventory_reservation_line(
    uuid, uuid, varchar, numeric, varchar, uuid, varchar
) TO doms_runtime;
GRANT EXECUTE ON FUNCTION doms.transition_fulfillment_allocation(
    uuid, uuid, varchar, numeric, varchar, uuid, varchar
) TO doms_runtime;

-- Authentication failures may occur before a tenant can be selected. The RLS
-- policy permits tenant_id IS NULL only while current_user is this exact role.
GRANT INSERT ON TABLE doms.login_events, doms.audit_events, doms.data_access_logs
TO doms_platform_logger;

-- Global scheduler runs use a separate role for the same reason. Scheduled job
-- definitions are read-only; job run state is the only mutable surface here.
GRANT SELECT ON TABLE doms.scheduled_jobs TO doms_global_job_runner;
GRANT SELECT, INSERT, UPDATE ON TABLE doms.job_runs TO doms_global_job_runner;

-- Do not grant broad ALL TABLES privileges in this template. Create separate
-- endpoint/service roles and grant only reviewed SELECT/INSERT/UPDATE columns or
-- command functions. In particular, do not grant direct DML on:
--
--   * payment authorization/capture/refund projections or gift/store-credit ledgers
--   * inventory position/reservation/allocation projections
--   * posted invoices, credit memos, settlements, payouts, or journal entries
--   * sealed order versions, status/event history, audit/access logs, or outbox facts
--
-- Login roles should receive one group role explicitly and use SET ROLE after
-- connection. Never make an application login the doms schema/table owner.
