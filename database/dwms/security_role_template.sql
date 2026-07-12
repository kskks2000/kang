-- DWMS runtime-role hardening template (PostgreSQL 11).
--
-- DBA-ONLY / MANUAL: this file is deliberately not numbered and is never executed by
-- scripts/apply_dwms_schema.py. The current deployment role `kang` does not have CREATEROLE,
-- so a database administrator or other role with the required authority must review and run it.
-- Replace role names to match the organization's service-account standard. Never put a login
-- password in this repository; provision credentials through the approved secret manager.
--
-- RLS context contract:
--   BEGIN;
--   SET LOCAL dwms.tenant_id = '<tenant UUID derived by the trusted backend>';
--   ... statements ...;
--   COMMIT;
-- A custom GUC can be set by any SQL client with a database session. It is routing context, not
-- an authentication boundary. The runtime login must therefore be reachable only by the trusted
-- backend after Firebase token/session verification, and must never be exposed to end users.

-- Keep cluster-role creation and every ACL/default-privilege change atomic. In psql, an
-- error aborts this transaction and the final COMMIT rolls it back instead of leaving a
-- partially hardened runtime role.
BEGIN;

DO $block$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'dwms_runtime') THEN
        CREATE ROLE dwms_runtime
            NOLOGIN
            NOSUPERUSER
            NOCREATEDB
            NOCREATEROLE
            NOINHERIT
            NOREPLICATION
            NOBYPASSRLS;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'dwms_platform_logger') THEN
        CREATE ROLE dwms_platform_logger
            NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'dwms_global_job_runner') THEN
        CREATE ROLE dwms_global_job_runner
            NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS;
    END IF;
END;
$block$;

ALTER ROLE dwms_runtime
    NOLOGIN
    NOSUPERUSER
    NOCREATEDB
    NOCREATEROLE
    NOINHERIT
    NOREPLICATION
    NOBYPASSRLS;
ALTER ROLE dwms_runtime SET row_security = on;
ALTER ROLE dwms_runtime SET search_path = pg_catalog, dwms;
ALTER ROLE dwms_platform_logger
    NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS;
ALTER ROLE dwms_platform_logger SET row_security = on;
ALTER ROLE dwms_platform_logger SET search_path = pg_catalog, dwms;
ALTER ROLE dwms_global_job_runner
    NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS;
ALTER ROLE dwms_global_job_runner SET row_security = on;
ALTER ROLE dwms_global_job_runner SET search_path = pg_catalog, dwms;

-- The application role must neither own DWMS objects nor inherit from the schema owner.
-- The numbered baseline applies FORCE ROW LEVEL SECURITY to tenant tables after seeds, so even
-- the table owner follows tenant policies during normal DML. Runtime isolation still requires a
-- separate NOBYPASSRLS non-owner role, explicit grants, and trusted service boundaries: an owner
-- or DBA can execute ALTER TABLE ... NO FORCE ROW LEVEL SECURITY and remains an administrative
-- credential. SECURITY DEFINER routines must set/validate tenant context before tenant-table DML.
REVOKE CREATE ON SCHEMA dwms FROM PUBLIC;
REVOKE ALL ON SCHEMA dwms FROM dwms_runtime;
GRANT USAGE ON SCHEMA dwms TO dwms_runtime;
GRANT USAGE ON SCHEMA dwms TO dwms_platform_logger, dwms_global_job_runner;

-- Remove implicit access before applying an allow-list. This is intentionally conservative.
REVOKE ALL ON ALL TABLES IN SCHEMA dwms FROM dwms_runtime;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA dwms FROM dwms_runtime;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA dwms FROM dwms_runtime;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA dwms FROM PUBLIC;

-- Tenant-less authentication failures/platform audit rows and global scheduled-job runs use
-- dedicated role-name-gated RLS branches. These group roles must be granted only to their trusted
-- services, which execute SET ROLE; the general runtime role cannot write NULL-tenant rows.
REVOKE ALL ON ALL TABLES IN SCHEMA dwms FROM dwms_platform_logger, dwms_global_job_runner;
GRANT INSERT ON TABLE
    dwms.login_events,
    dwms.audit_events,
    dwms.data_access_logs
TO dwms_platform_logger;
GRANT SELECT ON TABLE dwms.scheduled_jobs, dwms.job_runs TO dwms_global_job_runner;
GRANT INSERT, UPDATE ON TABLE dwms.job_runs TO dwms_global_job_runner;

-- Safe global dictionaries required by normal WMS validation/display.
GRANT SELECT ON TABLE
    dwms.countries,
    dwms.currencies,
    dwms.units_of_measure,
    dwms.incoterms,
    dwms.transport_modes,
    dwms.code_sets,
    dwms.code_values,
    dwms.permissions
TO dwms_runtime;

-- Common tenant-scoped masters. RLS applies because the runtime role is not the owner and has
-- NOBYPASSRLS. Add further SELECT/DML grants per independently deployed service and endpoint;
-- do not replace this list with blanket ALL TABLES privileges.
GRANT SELECT ON TABLE
    dwms.organizations,
    dwms.organization_units,
    dwms.business_partners,
    dwms.addresses,
    dwms.partner_addresses,
    dwms.partner_contacts,
    dwms.items,
    dwms.item_packagings,
    dwms.warehouses,
    dwms.warehouse_locations,
    dwms.inventory_statuses,
    dwms.location_types,
    dwms.lpn_types,
    dwms.reason_codes,
    dwms.charge_codes,
    dwms.tax_codes,
    dwms.payment_terms
TO dwms_runtime;

-- Table ACLs cannot express "draft rows writable, posted rows read-only". These high-integrity
-- stores therefore have no direct runtime DML. Commands must go through reviewed functions or a
-- narrower service role; database triggers remain defense in depth against owner/operator errors.
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON TABLE
    dwms.stock_buckets,
    dwms.inventory_transaction_headers,
    dwms.inventory_transaction_entries,
    dwms.inventory_balances,
    dwms.receipt_inventory_postings,
    dwms.receipt_inventory_allocations,
    dwms.shipping_confirmations,
    dwms.shipping_inventory_allocations,
    dwms.inventory_valuation_layers,
    dwms.inventory_valuation_movements,
    dwms.bonded_movement_groups,
    dwms.bonded_inventory_movements,
    dwms.bonded_inventory_balances,
    dwms.bonded_exception_authorizations,
    dwms.bonded_exception_authorization_usages
FROM dwms_runtime;

REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON TABLE
    dwms.customs_declarations,
    dwms.customs_declaration_versions,
    dwms.customs_declaration_lines,
    dwms.customs_declaration_taxes,
    dwms.customs_declaration_events,
    dwms.customs_documents,
    dwms.customs_document_links,
    dwms.customs_duty_payments,
    dwms.customs_duty_payment_allocations,
    dwms.customs_refund_claims,
    dwms.customs_refund_allocations,
    dwms.customs_release_evidence,
    dwms.customs_release_line_coverages,
    dwms.unipass_messages,
    dwms.unipass_message_events,
    dwms.unipass_message_errors,
    dwms.unipass_message_attachments,
    dwms.unipass_message_results,
    dwms.bonded_inout_reports,
    dwms.bonded_inout_report_versions,
    dwms.bonded_inout_report_lines
FROM dwms_runtime;

REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON TABLE
    dwms.charges,
    dwms.charge_allocations,
    dwms.charge_adjustments,
    dwms.invoices,
    dwms.invoice_lines,
    dwms.invoice_line_charges,
    dwms.invoice_taxes,
    dwms.tax_invoices,
    dwms.tax_invoice_lines,
    dwms.settlement_batches,
    dwms.settlements,
    dwms.settlement_lines,
    dwms.payments,
    dwms.payment_applications,
    dwms.finance_projection_authorizations,
    dwms.journal_batches,
    dwms.journal_entries,
    dwms.journal_lines
FROM dwms_runtime;

-- Append-only security/business evidence is not mutable by the general runtime role. A separate
-- logger role may receive INSERT only after its ingestion path and retention controls are reviewed.
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON TABLE
    dwms.login_events,
    dwms.audit_events,
    dwms.account_link_events,
    dwms.impersonation_sessions,
    dwms.entity_change_logs,
    dwms.data_access_logs
FROM dwms_runtime;

-- Only the tenant-authorized wrapper is callable. Do not grant the underlying
-- dwms.post_inventory_transaction(uuid, uuid) SECURITY DEFINER function to the runtime role.
GRANT EXECUTE ON FUNCTION dwms.current_tenant_id()
TO dwms_runtime, dwms_platform_logger, dwms_global_job_runner;
GRANT EXECUTE ON FUNCTION dwms.generate_uuid()
TO dwms_runtime, dwms_platform_logger, dwms_global_job_runner;
GRANT EXECUTE ON FUNCTION dwms.jsonb_contains_forbidden_secret_key(jsonb)
TO dwms_runtime, dwms_platform_logger, dwms_global_job_runner;
GRANT EXECUTE ON FUNCTION
    dwms.post_inventory_transaction_for_tenant(uuid, uuid)
TO dwms_runtime;

-- New objects default to private. Repeat with the actual schema-owner role if it differs from
-- `kang`. These statements also require DBA/schema-owner authority.
ALTER DEFAULT PRIVILEGES FOR ROLE kang IN SCHEMA dwms
    REVOKE ALL ON TABLES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE kang IN SCHEMA dwms
    REVOKE ALL ON SEQUENCES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE kang IN SCHEMA dwms
    REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

-- Example login provisioning (execute separately; credential supplied out of band):
--   CREATE ROLE dwms_app_login LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE
--       NOINHERIT NOREPLICATION NOBYPASSRLS;
--   GRANT dwms_runtime TO dwms_app_login;
--   -- The connection pool executes SET ROLE dwms_runtime after connecting.
-- Never grant dwms_runtime ownership, membership in `kang`, BYPASSRLS, SUPERUSER, or CREATE ROLE.
-- Never grant an application role direct access to owner-defined views until each view is audited:
-- on PostgreSQL 11 a view normally checks underlying access/RLS as the view owner.

COMMIT;
