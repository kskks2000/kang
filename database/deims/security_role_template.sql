-- DEIMS runtime-role hardening template (PostgreSQL 11).
--
-- DBA-ONLY / MANUAL: this file is deliberately not numbered and is never executed by
-- scripts/apply_deims_schema.py. The current deployment role `kang` does not have CREATEROLE,
-- so a database administrator or other role with the required authority must review and run it.
-- Replace role names to match the organization's service-account standard. Never put a login
-- password in this repository; provision credentials through the approved secret manager.
--
-- RLS context contract:
--   BEGIN;
--   SET LOCAL deims.tenant_id = '<tenant UUID derived by the trusted backend>';
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
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'deims_runtime') THEN
        CREATE ROLE deims_runtime
            NOLOGIN
            NOSUPERUSER
            NOCREATEDB
            NOCREATEROLE
            NOINHERIT
            NOREPLICATION
            NOBYPASSRLS;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'deims_platform_logger') THEN
        CREATE ROLE deims_platform_logger
            NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'deims_global_job_runner') THEN
        CREATE ROLE deims_global_job_runner
            NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS;
    END IF;
END;
$block$;

ALTER ROLE deims_runtime
    NOLOGIN
    NOSUPERUSER
    NOCREATEDB
    NOCREATEROLE
    NOINHERIT
    NOREPLICATION
    NOBYPASSRLS;
ALTER ROLE deims_runtime SET row_security = on;
ALTER ROLE deims_runtime SET search_path = pg_catalog, deims;
ALTER ROLE deims_platform_logger
    NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS;
ALTER ROLE deims_platform_logger SET row_security = on;
ALTER ROLE deims_platform_logger SET search_path = pg_catalog, deims;
ALTER ROLE deims_global_job_runner
    NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS;
ALTER ROLE deims_global_job_runner SET row_security = on;
ALTER ROLE deims_global_job_runner SET search_path = pg_catalog, deims;

-- The application role must neither own DEIMS objects nor inherit from the schema owner.
-- The numbered baseline applies FORCE ROW LEVEL SECURITY to tenant tables after seeds, so even
-- the table owner follows tenant policies during normal DML. Runtime isolation still requires a
-- separate NOBYPASSRLS non-owner role, explicit grants, and trusted service boundaries: an owner
-- or DBA can execute ALTER TABLE ... NO FORCE ROW LEVEL SECURITY and remains an administrative
-- credential. SECURITY DEFINER routines must set/validate tenant context before tenant-table DML.
REVOKE CREATE ON SCHEMA deims FROM PUBLIC;
REVOKE ALL ON SCHEMA deims FROM deims_runtime;
GRANT USAGE ON SCHEMA deims TO deims_runtime;
GRANT USAGE ON SCHEMA deims TO deims_platform_logger, deims_global_job_runner;

-- Remove implicit access before applying an allow-list. This is intentionally conservative.
REVOKE ALL ON ALL TABLES IN SCHEMA deims FROM deims_runtime;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA deims FROM deims_runtime;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA deims FROM deims_runtime;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA deims FROM PUBLIC;

-- Tenant-less authentication failures/platform audit rows and global scheduled-job runs use
-- dedicated role-name-gated RLS branches. These group roles must be granted only to their trusted
-- services, which execute SET ROLE; the general runtime role cannot write NULL-tenant rows.
REVOKE ALL ON ALL TABLES IN SCHEMA deims FROM deims_platform_logger, deims_global_job_runner;
GRANT INSERT ON TABLE
    deims.login_events,
    deims.audit_events,
    deims.data_access_logs
TO deims_platform_logger;
GRANT SELECT ON TABLE deims.scheduled_jobs, deims.job_runs TO deims_global_job_runner;
GRANT INSERT, UPDATE ON TABLE deims.job_runs TO deims_global_job_runner;

-- Safe global dictionaries required by normal WMS validation/display.
GRANT SELECT ON TABLE
    deims.countries,
    deims.currencies,
    deims.units_of_measure,
    deims.incoterms,
    deims.transport_modes,
    deims.code_sets,
    deims.code_values,
    deims.permissions
TO deims_runtime;

-- Common tenant-scoped masters. RLS applies because the runtime role is not the owner and has
-- NOBYPASSRLS. Add further SELECT/DML grants per independently deployed service and endpoint;
-- do not replace this list with blanket ALL TABLES privileges.
GRANT SELECT ON TABLE
    deims.organizations,
    deims.organization_units,
    deims.business_partners,
    deims.addresses,
    deims.partner_addresses,
    deims.partner_contacts,
    deims.items,
    deims.item_packagings,
    deims.warehouses,
    deims.warehouse_locations,
    deims.inventory_statuses,
    deims.location_types,
    deims.lpn_types,
    deims.reason_codes,
    deims.charge_codes,
    deims.tax_codes,
    deims.payment_terms
TO deims_runtime;

-- Table ACLs cannot express "draft rows writable, posted rows read-only". These high-integrity
-- stores therefore have no direct runtime DML. Commands must go through reviewed functions or a
-- narrower service role; database triggers remain defense in depth against owner/operator errors.
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON TABLE
    deims.stock_buckets,
    deims.inventory_transaction_headers,
    deims.inventory_transaction_entries,
    deims.inventory_balances,
    deims.receipt_inventory_postings,
    deims.receipt_inventory_allocations,
    deims.shipping_confirmations,
    deims.shipping_inventory_allocations,
    deims.inventory_valuation_layers,
    deims.inventory_valuation_movements,
    deims.bonded_movement_groups,
    deims.bonded_inventory_movements,
    deims.bonded_inventory_balances,
    deims.bonded_exception_authorizations,
    deims.bonded_exception_authorization_usages
FROM deims_runtime;

REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON TABLE
    deims.customs_declarations,
    deims.customs_declaration_versions,
    deims.customs_declaration_lines,
    deims.customs_declaration_taxes,
    deims.customs_declaration_events,
    deims.customs_documents,
    deims.customs_document_links,
    deims.customs_duty_payments,
    deims.customs_duty_payment_allocations,
    deims.customs_refund_claims,
    deims.customs_refund_allocations,
    deims.customs_release_evidence,
    deims.customs_release_line_coverages,
    deims.unipass_messages,
    deims.unipass_message_events,
    deims.unipass_message_errors,
    deims.unipass_message_attachments,
    deims.unipass_message_results,
    deims.bonded_inout_reports,
    deims.bonded_inout_report_versions,
    deims.bonded_inout_report_lines
FROM deims_runtime;

REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON TABLE
    deims.charges,
    deims.charge_allocations,
    deims.charge_adjustments,
    deims.invoices,
    deims.invoice_lines,
    deims.invoice_line_charges,
    deims.invoice_taxes,
    deims.tax_invoices,
    deims.tax_invoice_lines,
    deims.settlement_batches,
    deims.settlements,
    deims.settlement_lines,
    deims.payments,
    deims.payment_applications,
    deims.finance_projection_authorizations,
    deims.journal_batches,
    deims.journal_entries,
    deims.journal_lines
FROM deims_runtime;

-- Append-only security/business evidence is not mutable by the general runtime role. A separate
-- logger role may receive INSERT only after its ingestion path and retention controls are reviewed.
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON TABLE
    deims.login_events,
    deims.audit_events,
    deims.account_link_events,
    deims.impersonation_sessions,
    deims.entity_change_logs,
    deims.data_access_logs
FROM deims_runtime;

-- Only the tenant-authorized wrapper is callable. Do not grant the underlying
-- deims.post_inventory_transaction(uuid, uuid) SECURITY DEFINER function to the runtime role.
GRANT EXECUTE ON FUNCTION deims.current_tenant_id()
TO deims_runtime, deims_platform_logger, deims_global_job_runner;
GRANT EXECUTE ON FUNCTION deims.generate_uuid()
TO deims_runtime, deims_platform_logger, deims_global_job_runner;
GRANT EXECUTE ON FUNCTION deims.jsonb_contains_forbidden_secret_key(jsonb)
TO deims_runtime, deims_platform_logger, deims_global_job_runner;
GRANT EXECUTE ON FUNCTION
    deims.post_inventory_transaction_for_tenant(uuid, uuid)
TO deims_runtime;

-- New objects default to private. Repeat with the actual schema-owner role if it differs from
-- `kang`. These statements also require DBA/schema-owner authority.
ALTER DEFAULT PRIVILEGES FOR ROLE kang IN SCHEMA deims
    REVOKE ALL ON TABLES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE kang IN SCHEMA deims
    REVOKE ALL ON SEQUENCES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE kang IN SCHEMA deims
    REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

-- Example login provisioning (execute separately; credential supplied out of band):
--   CREATE ROLE deims_app_login LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE
--       NOINHERIT NOREPLICATION NOBYPASSRLS;
--   GRANT deims_runtime TO deims_app_login;
--   -- The connection pool executes SET ROLE deims_runtime after connecting.
-- Never grant deims_runtime ownership, membership in `kang`, BYPASSRLS, SUPERUSER, or CREATE ROLE.
-- Never grant an application role direct access to owner-defined views until each view is audited:
-- on PostgreSQL 11 a view normally checks underlying access/RLS as the view owner.

COMMIT;
