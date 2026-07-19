-- EWMS runtime-role hardening template (PostgreSQL 11).
--
-- DBA-ONLY / MANUAL: this file is deliberately not numbered and is never executed by
-- scripts/apply_ewms_schema.py. The current deployment role `kang` does not have CREATEROLE,
-- so a database administrator or other role with the required authority must review and run it.
-- Keep these fixed NOLOGIN policy roles because module 13 intentionally gates NULL-tenant log/job
-- rows by their names. Map organization-standard LOGIN roles to them with GRANT. Never put a
-- login password in this repository; provision credentials through the approved secret manager.
--
-- RLS context contract:
--   BEGIN;
--   SET LOCAL ROLE ewms_runtime;
--   SET LOCAL row_security = on;
--   SET LOCAL search_path = pg_catalog, ewms;
--   SELECT ewms.bind_request_context('<lowercase SHA-256 server-session handle hash>');
--   ... statements ...;
--   COMMIT;
-- The numbered baseline ignores arbitrary ewms.tenant_id custom-GUC values. Tenant identity is
-- derived only from the protected server session and the backend_pid + transaction_id binding.
-- The runtime login and session-handle hash must remain reachable only by the trusted backend.

-- Keep cluster-role creation and every ACL/default-privilege change atomic. In psql, an
-- error aborts this transaction and the final COMMIT rolls it back instead of leaving a
-- partially hardened runtime role.
BEGIN;

DO $block$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'ewms_runtime') THEN
        CREATE ROLE ewms_runtime
            NOLOGIN
            NOSUPERUSER
            NOCREATEDB
            NOCREATEROLE
            NOINHERIT
            NOREPLICATION
            NOBYPASSRLS;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'ewms_platform_logger') THEN
        CREATE ROLE ewms_platform_logger
            NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'ewms_global_job_runner') THEN
        CREATE ROLE ewms_global_job_runner
            NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'ewms_auth_service') THEN
        CREATE ROLE ewms_auth_service
            NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS;
    END IF;
END;
$block$;

ALTER ROLE ewms_runtime
    NOLOGIN
    NOSUPERUSER
    NOCREATEDB
    NOCREATEROLE
    NOINHERIT
    NOREPLICATION
    NOBYPASSRLS;
ALTER ROLE ewms_platform_logger
    NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS;
ALTER ROLE ewms_global_job_runner
    NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS;
ALTER ROLE ewms_auth_service
    NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS;

-- NOINHERIT does not prevent SET ROLE into a parent role. Abort if a protected service group is
-- itself a member of any other role; nested membership could otherwise retain an owner/admin path.
DO $block$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_auth_members membership
        JOIN pg_roles member_role ON member_role.oid = membership.member
        WHERE member_role.rolname IN (
            'ewms_runtime', 'ewms_platform_logger',
            'ewms_global_job_runner', 'ewms_auth_service'
        )
    ) THEN
        RAISE EXCEPTION 'EWMS service group roles must not be members of other database roles';
    END IF;
END;
$block$;

-- The application role must neither own EWMS objects nor inherit from the schema owner.
-- The numbered baseline applies FORCE ROW LEVEL SECURITY to tenant tables after seeds, so even
-- the table owner follows tenant policies during normal DML. Runtime isolation still requires a
-- separate NOBYPASSRLS non-owner role, explicit grants, and trusted service boundaries: an owner
-- or DBA can execute ALTER TABLE ... NO FORCE ROW LEVEL SECURITY and remains an administrative
-- credential. SECURITY DEFINER routines must set/validate tenant context before tenant-table DML.
REVOKE CREATE ON SCHEMA ewms FROM PUBLIC;
REVOKE ALL ON SCHEMA ewms FROM
    ewms_runtime, ewms_platform_logger, ewms_global_job_runner, ewms_auth_service;

-- Remove implicit access before applying an allow-list. This is intentionally conservative.
REVOKE ALL ON ALL TABLES IN SCHEMA ewms FROM
    PUBLIC, ewms_runtime, ewms_platform_logger, ewms_global_job_runner, ewms_auth_service;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA ewms FROM
    PUBLIC, ewms_runtime, ewms_platform_logger, ewms_global_job_runner, ewms_auth_service;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA ewms FROM
    ewms_runtime, ewms_platform_logger, ewms_global_job_runner, ewms_auth_service;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA ewms FROM PUBLIC;
GRANT USAGE ON SCHEMA ewms TO
    ewms_runtime, ewms_platform_logger, ewms_global_job_runner, ewms_auth_service;

-- Authentication control-plane tables are never application-facing. Runtime and auth roles
-- can populate/read them only through reviewed SECURITY DEFINER functions.
REVOKE ALL ON TABLE
    ewms.user_sessions,
    ewms.session_issue_contexts,
    ewms.session_bind_contexts,
    ewms.request_contexts
FROM ewms_runtime, ewms_auth_service, ewms_platform_logger, ewms_global_job_runner;

-- Tenant-less authentication failures/platform audit rows and global scheduled-job runs use
-- dedicated role-name-gated RLS branches. These group roles must be granted only to their trusted
-- services, which execute SET ROLE; the general runtime role cannot write NULL-tenant rows.
REVOKE ALL ON ALL TABLES IN SCHEMA ewms FROM ewms_platform_logger, ewms_global_job_runner;
GRANT INSERT ON TABLE
    ewms.login_events,
    ewms.audit_events,
    ewms.data_access_logs
TO ewms_platform_logger;
GRANT SELECT ON TABLE ewms.scheduled_jobs, ewms.job_runs TO ewms_global_job_runner;
GRANT INSERT, UPDATE ON TABLE ewms.job_runs TO ewms_global_job_runner;
GRANT INSERT ON TABLE ewms.job_run_events TO ewms_global_job_runner;

-- Safe global dictionaries required by normal WMS validation/display.
GRANT SELECT ON TABLE
    ewms.countries,
    ewms.currencies,
    ewms.units_of_measure,
    ewms.incoterms,
    ewms.transport_modes,
    ewms.code_sets,
    ewms.code_values,
    ewms.permissions
TO ewms_runtime;

-- Common tenant-scoped masters. RLS applies because the runtime role is not the owner and has
-- NOBYPASSRLS. Add further SELECT/DML grants per independently deployed service and endpoint;
-- do not replace this list with blanket ALL TABLES privileges.
GRANT SELECT ON TABLE
    ewms.organizations,
    ewms.organization_units,
    ewms.business_partners,
    ewms.addresses,
    ewms.partner_addresses,
    ewms.partner_contacts,
    ewms.items,
    ewms.item_packagings,
    ewms.warehouses,
    ewms.warehouse_locations,
    ewms.inventory_statuses,
    ewms.location_types,
    ewms.lpn_types,
    ewms.reason_codes,
    ewms.charge_codes,
    ewms.tax_codes,
    ewms.payment_terms
TO ewms_runtime;

-- Table ACLs cannot express "draft rows writable, posted rows read-only". These high-integrity
-- stores therefore have no direct runtime DML. Commands must go through reviewed functions or a
-- narrower service role; database triggers remain defense in depth against owner/operator errors.
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON TABLE
    ewms.stock_buckets,
    ewms.inventory_transaction_headers,
    ewms.inventory_transaction_entries,
    ewms.inventory_balances,
    ewms.receipt_inventory_postings,
    ewms.receipt_inventory_allocations,
    ewms.shipping_confirmations,
    ewms.shipping_inventory_allocations,
    ewms.inventory_valuation_layers,
    ewms.inventory_valuation_movements,
    ewms.bonded_movement_groups,
    ewms.bonded_inventory_movements,
    ewms.bonded_inventory_balances,
    ewms.bonded_exception_authorizations,
    ewms.bonded_exception_authorization_usages
FROM ewms_runtime;

REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON TABLE
    ewms.customs_declarations,
    ewms.customs_declaration_versions,
    ewms.customs_declaration_lines,
    ewms.customs_declaration_taxes,
    ewms.customs_declaration_events,
    ewms.customs_documents,
    ewms.customs_document_links,
    ewms.customs_duty_payments,
    ewms.customs_duty_payment_allocations,
    ewms.customs_refund_claims,
    ewms.customs_refund_allocations,
    ewms.customs_release_evidence,
    ewms.customs_release_line_coverages,
    ewms.unipass_messages,
    ewms.unipass_message_events,
    ewms.unipass_message_errors,
    ewms.unipass_message_attachments,
    ewms.unipass_message_results,
    ewms.bonded_inout_reports,
    ewms.bonded_inout_report_versions,
    ewms.bonded_inout_report_lines
FROM ewms_runtime;

REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON TABLE
    ewms.charges,
    ewms.charge_allocations,
    ewms.charge_adjustments,
    ewms.invoices,
    ewms.invoice_lines,
    ewms.invoice_line_charges,
    ewms.invoice_taxes,
    ewms.tax_invoices,
    ewms.tax_invoice_lines,
    ewms.settlement_batches,
    ewms.settlements,
    ewms.settlement_lines,
    ewms.payments,
    ewms.payment_applications,
    ewms.finance_projection_authorizations,
    ewms.journal_batches,
    ewms.journal_entries,
    ewms.journal_lines
FROM ewms_runtime;

-- Append-only security/business evidence is not mutable by the general runtime role. A separate
-- logger role may receive INSERT only after its ingestion path and retention controls are reviewed.
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON TABLE
    ewms.login_events,
    ewms.audit_events,
    ewms.account_link_events,
    ewms.impersonation_sessions,
    ewms.entity_change_logs,
    ewms.data_access_logs
FROM ewms_runtime;

-- Only the tenant-authorized wrapper is callable. Do not grant the underlying
-- ewms.post_inventory_transaction(uuid, uuid) SECURITY DEFINER function to the runtime role.
GRANT EXECUTE ON FUNCTION ewms.current_tenant_id()
TO ewms_runtime, ewms_platform_logger, ewms_global_job_runner;
GRANT EXECUTE ON FUNCTION ewms.current_ewms_user_id()
TO ewms_runtime;
GRANT EXECUTE ON FUNCTION ewms.bind_request_context(text)
TO ewms_runtime;
-- These helpers disclose only whether the current backend transaction owns a matching
-- protected bootstrap marker. EXECUTE is required because membership RLS references them;
-- callers still have no table access and cannot create such a marker directly.
GRANT EXECUTE ON FUNCTION ewms.has_active_session_issue_context(uuid, uuid)
TO ewms_runtime;
GRANT EXECUTE ON FUNCTION ewms.has_active_session_bind_context(uuid, uuid, uuid)
TO ewms_runtime;
GRANT EXECUTE ON FUNCTION ewms.issue_ewms_session(
    uuid, text, text, text, text, uuid, timestamptz, timestamptz, text, inet, text
)
TO ewms_auth_service;
GRANT EXECUTE ON FUNCTION ewms.generate_uuid()
TO ewms_runtime, ewms_platform_logger, ewms_global_job_runner;
GRANT EXECUTE ON FUNCTION ewms.jsonb_contains_forbidden_secret_key(jsonb)
TO ewms_runtime, ewms_platform_logger, ewms_global_job_runner;
GRANT EXECUTE ON FUNCTION
    ewms.post_inventory_transaction_for_tenant(uuid, uuid)
TO ewms_runtime;

-- New objects default to private. Repeat with the actual schema-owner role if it differs from
-- `kang`. These statements also require DBA/schema-owner authority.
ALTER DEFAULT PRIVILEGES FOR ROLE kang IN SCHEMA ewms
    REVOKE ALL ON TABLES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE kang IN SCHEMA ewms
    REVOKE ALL ON TABLES FROM
        ewms_runtime, ewms_platform_logger, ewms_global_job_runner, ewms_auth_service;
ALTER DEFAULT PRIVILEGES FOR ROLE kang IN SCHEMA ewms
    REVOKE ALL ON SEQUENCES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE kang IN SCHEMA ewms
    REVOKE ALL ON SEQUENCES FROM
        ewms_runtime, ewms_platform_logger, ewms_global_job_runner, ewms_auth_service;
ALTER DEFAULT PRIVILEGES FOR ROLE kang IN SCHEMA ewms
    REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE kang IN SCHEMA ewms
    REVOKE EXECUTE ON FUNCTIONS FROM
        ewms_runtime, ewms_platform_logger, ewms_global_job_runner, ewms_auth_service;

-- Example login provisioning (execute separately; credential supplied out of band):
--   CREATE ROLE ewms_app_login LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE
--       NOINHERIT NOREPLICATION NOBYPASSRLS;
--   GRANT ewms_runtime TO ewms_app_login;
--   ALTER ROLE ewms_app_login SET row_security = on;
--   ALTER ROLE ewms_app_login SET search_path = pg_catalog, ewms;
--   -- The connection pool executes SET LOCAL ROLE plus the local settings shown above.
--   CREATE ROLE ewms_auth_login LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE
--       NOINHERIT NOREPLICATION NOBYPASSRLS;
--   GRANT ewms_auth_service TO ewms_auth_login;
--   ALTER ROLE ewms_auth_login SET row_security = on;
--   ALTER ROLE ewms_auth_login SET search_path = pg_catalog, ewms;
-- Never grant ewms_runtime ownership, membership in `kang`, BYPASSRLS, SUPERUSER, or CREATE ROLE.
-- Never grant an application role direct access to owner-defined views until each view is audited:
-- on PostgreSQL 11 a view normally checks underlying access/RLS as the view owner.

COMMIT;
