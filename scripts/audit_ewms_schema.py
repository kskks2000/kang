"""Aggregate-only, read-only catalog audit for the deployed EWMS schema.

This audit reads PostgreSQL catalogs only, except for invoking the context
accessors with an intentionally spoofed custom GUC.  It never selects EWMS
business rows, authentication rows, payloads, ciphertext, or credential data,
and it reports counts rather than object identifiers.
"""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Final

from apply_ewms_schema import (
    _assert_actual_target,
    _configured_append_only_tables,
    _expected_catalog,
    _sql_files,
    psycopg,
    settings,
)


# This registry is deliberately independent of CREATE TABLE discovery.  The
# exact table-set check detects deployment drift; this registry also detects a
# locally edited baseline that has silently dropped an entire business area.
REQUIRED_TABLES_BY_DOMAIN: Final[dict[str, frozenset[str]]] = {
    "identity_access": frozenset(
        {
            "schema_migrations",
            "tenants",
            "tenant_settings",
            "organizations",
            "organization_units",
            "users",
            "user_profiles",
            "auth_identities",
            "tenant_memberships",
            "permissions",
            "roles",
            "role_permissions",
            "role_assignments",
            "user_sessions",
            "session_issue_contexts",
            "session_bind_contexts",
            "request_contexts",
            "login_events",
            "audit_events",
            "data_access_logs",
        }
    ),
    "master_data": frozenset(
        {
            "countries",
            "currencies",
            "units_of_measure",
            "unit_conversions",
            "transport_modes",
            "incoterms",
            "ports",
            "customs_offices",
            "hs_codes",
            "exchange_rates",
            "business_partners",
            "partner_roles",
            "addresses",
            "contacts",
            "items",
            "item_packagings",
            "item_storage_requirements",
            "dangerous_goods_profiles",
            "inventory_statuses",
        }
    ),
    "warehouse_facility": frozenset(
        {
            "warehouses",
            "warehouse_clients",
            "warehouse_item_policies",
            "warehouse_zones",
            "warehouse_areas",
            "warehouse_aisles",
            "warehouse_racks",
            "warehouse_locations",
            "location_capacity_overrides",
            "docks",
            "dock_doors",
            "yards",
            "yard_slots",
            "work_areas",
            "workstations",
            "material_handling_equipment",
            "rf_devices",
            "putaway_strategies",
            "allocation_strategies",
            "replenishment_policies",
        }
    ),
    "inbound_quality_returns": frozenset(
        {
            "inbound_orders",
            "inbound_order_lines",
            "dock_appointments",
            "receipts",
            "receipt_lines",
            "receipt_lot_observations",
            "receipt_serial_observations",
            "receipt_discrepancies",
            "unloading_tasks",
            "quality_specifications",
            "quality_inspections",
            "quality_inspection_results",
            "quality_holds",
            "quality_dispositions",
            "putaway_requests",
            "crossdock_requests",
            "supplier_return_orders",
            "supplier_return_order_lines",
        }
    ),
    "inventory_control": frozenset(
        {
            "inventory_lots",
            "serial_numbers",
            "lpns",
            "stock_buckets",
            "inventory_transaction_headers",
            "inventory_transaction_entries",
            "inventory_balances",
            "inventory_reservations",
            "inventory_holds",
            "receipt_inventory_postings",
            "receipt_inventory_allocations",
            "stock_transfer_orders",
            "movement_tasks",
            "putaway_tasks",
            "replenishment_requests",
            "inventory_adjustments",
            "cycle_count_plans",
            "cycle_count_tasks",
            "inventory_freezes",
            "inventory_snapshots",
            "inventory_valuation_layers",
            "inventory_valuation_movements",
            "inventory_transformations",
            "inventory_reconciliation_runs",
        }
    ),
    "outbound_fulfillment": frozenset(
        {
            "outbound_orders",
            "outbound_order_lines",
            "outbound_order_holds",
            "allocation_runs",
            "inventory_allocations",
            "waves",
            "pick_tasks",
            "pick_task_lines",
            "pick_confirmations",
            "packing_sessions",
            "packages",
            "package_items",
            "shipments",
            "shipment_lines",
            "shipment_stops",
            "loads",
            "load_shipments",
            "manifests",
            "shipping_confirmations",
            "shipping_inventory_allocations",
            "proof_of_deliveries",
            "customer_return_orders",
            "customer_return_lines",
            "customer_return_status_history",
            "customer_return_receipt_allocations",
            "customer_return_quality_allocations",
            "customer_return_disposition_allocations",
            "customer_return_inventory_allocations",
        }
    ),
    "vas_labor_yard_iot": frozenset(
        {
            "vas_service_catalog",
            "vas_work_orders",
            "vas_work_order_lines",
            "labor_shifts",
            "worker_profiles",
            "worker_skills",
            "attendance_events",
            "labor_tasks",
            "labor_time_entries",
            "drivers",
            "vehicles",
            "trailers",
            "yard_visits",
            "dock_operations",
            "scan_events",
            "sensor_devices",
            "sensor_readings",
            "sensor_alerts",
            "safety_incidents",
        }
    ),
    "international_trade": frozenset(
        {
            "trade_cases",
            "trade_case_items",
            "trade_orders",
            "trade_order_lines",
            "import_cases",
            "import_case_items",
            "import_arrival_notices",
            "import_release_orders",
            "export_cases",
            "export_case_items",
            "export_shipping_instructions",
            "export_cargo_receipts",
            "trade_shipments",
            "trade_shipment_items",
            "trade_containers",
            "trade_documents",
            "commercial_invoices",
            "packing_lists",
            "bills_of_lading",
            "air_waybills",
            "transport_schedules",
            "carrier_bookings",
            "verified_gross_masses",
        }
    ),
    "customs_unipass": frozenset(
        {
            "customs_declarations",
            "customs_declaration_versions",
            "customs_declaration_lines",
            "customs_declaration_taxes",
            "customs_declaration_events",
            "customs_documents",
            "customs_duty_payments",
            "customs_duty_payment_allocations",
            "customs_refund_claims",
            "customs_refund_allocations",
            "customs_release_evidence",
            "customs_release_line_coverages",
            "customs_message_schemas",
            "unipass_connection_profiles",
            "unipass_messages",
            "unipass_message_events",
            "unipass_message_errors",
            "unipass_message_results",
            "unipass_sync_runs",
            "customs_inventory_legal_statuses",
            "unipass_mapping_versions",
            "unipass_code_mapping_versions",
            "unipass_code_mappings",
            "unipass_field_mappings",
            "inventory_customs_status_transitions",
            "shipping_customs_release_allocations",
        }
    ),
    "bonded_warehouse": frozenset(
        {
            "bonded_facilities",
            "bonded_facility_licenses",
            "bonded_zone_controls",
            "bonded_cargo",
            "bonded_cargo_items",
            "bonded_cargo_status_events",
            "bonded_inout_reports",
            "bonded_inout_report_versions",
            "bonded_inout_report_lines",
            "bonded_inout_report_events",
            "bonded_movement_groups",
            "bonded_inventory_movements",
            "bonded_inventory_balances",
            "bonded_exception_authorizations",
            "bonded_exception_authorization_usages",
            "bonded_transport_orders",
            "bonded_seals",
            "bonded_storage_periods",
            "bonded_release_notices",
            "bonded_overdue_cases",
            "bonded_handling_operations",
            "bonded_sample_movements",
            "bonded_disposal_cases",
            "bonded_inventory_counts",
            "bonded_compliance_reports",
        }
    ),
    "origin_trade_compliance": frozenset(
        {
            "customs_valuations",
            "tariff_classification_cases",
            "tariff_classification_decisions",
            "customs_guarantees",
            "duty_drawback_claims",
            "trade_agreements",
            "origin_rules",
            "item_hs_classifications",
            "item_origins",
            "supplier_origin_declarations",
            "origin_calculations",
            "origin_determinations",
            "origin_certificates",
            "screening_requests",
            "screening_matches",
            "screening_decisions",
            "compliance_holds",
            "item_control_classifications",
            "trade_control_rules",
            "trade_licenses",
            "trade_license_usages",
            "quota_allocations",
            "regulatory_permits",
        }
    ),
    "billing_settlement_accounting": frozenset(
        {
            "service_contracts",
            "service_contract_versions",
            "rate_rules",
            "rate_rule_tiers",
            "charge_events",
            "rating_runs",
            "charges",
            "charge_allocations",
            "charge_adjustments",
            "landed_costs",
            "invoices",
            "invoice_lines",
            "invoice_taxes",
            "tax_invoices",
            "settlement_batches",
            "settlements",
            "settlement_lines",
            "payments",
            "payment_applications",
            "accounting_periods",
            "gl_accounts",
            "journal_batches",
            "journal_entries",
            "journal_lines",
            "accounting_exports",
        }
    ),
    "trade_finance_insurance_claims": frozenset(
        {
            "letters_of_credit",
            "letter_of_credit_amendments",
            "document_presentations",
            "documentary_collections",
            "trade_finance_events",
            "payment_requests",
            "bank_statement_imports",
            "bank_statement_lines",
            "cash_reconciliation_matches",
            "foreign_exchange_contracts",
            "insurance_policies",
            "insurance_certificates",
            "insurance_declarations",
            "loss_incidents",
            "claims",
            "claim_items",
            "claim_events",
            "claim_documents",
            "claim_reserve_movements",
            "claim_settlements",
        }
    ),
    "workflow_integration_analytics": frozenset(
        {
            "outbox_events",
            "integration_messages",
            "integration_message_attempts",
            "edi_documents",
            "webhook_subscriptions",
            "webhook_deliveries",
            "import_jobs",
            "export_jobs",
            "scheduled_jobs",
            "job_runs",
            "job_run_events",
            "dead_letter_messages",
            "workflow_definitions",
            "workflow_versions",
            "workflow_instances",
            "workflow_tasks",
            "workflow_events",
            "approval_policies",
            "approval_requests",
            "approval_actions",
            "sod_rules",
            "sod_violations",
            "kpi_definitions",
            "kpi_values",
            "warehouse_daily_facts",
            "inventory_daily_facts",
            "data_quality_rules",
            "data_quality_results",
        }
    ),
    "recall_slotting_automation": frozenset(
        {
            "recall_campaigns",
            "recall_campaign_status_history",
            "recall_campaign_lots",
            "recall_actions",
            "recall_action_events",
            "dock_appointment_outbound_orders",
            "dock_appointment_shipments",
            "dock_appointment_loads",
            "slotting_runs",
            "slotting_recommendations",
            "slotting_recommendation_events",
            "automation_systems",
            "automation_resources",
            "automation_missions",
            "automation_mission_steps",
            "automation_events",
        }
    ),
}

REQUIRED_DOMAIN_TABLES: Final[frozenset[str]] = frozenset().union(
    *REQUIRED_TABLES_BY_DOMAIN.values()
)

REQUIRED_CONTEXT_FUNCTIONS: Final[frozenset[str]] = frozenset(
    {
        "issue_ewms_session",
        "bind_request_context",
        "current_tenant_id",
        "current_ewms_user_id",
    }
)

# A static core prevents weakening the SQL-driven configuration by deleting a
# high-value evidence table from its list.  The full configured list and new
# event/history tables are added dynamically in _critical_append_only_tables.
CRITICAL_APPEND_ONLY_CORE: Final[frozenset[str]] = frozenset(
    {
        "schema_migrations",
        "account_link_events",
        "login_events",
        "audit_events",
        "data_access_logs",
        "entity_change_logs",
        "inventory_valuation_movements",
        "customs_declaration_events",
        "customs_release_evidence",
        "customs_release_line_coverages",
        "unipass_message_events",
        "unipass_message_errors",
        "unipass_message_attachments",
        "unipass_message_results",
        "bonded_cargo_status_events",
        "bonded_inventory_movements",
        "bonded_inout_report_events",
        "invoice_status_history",
        "tax_invoice_events",
        "approval_actions",
        "workflow_events",
        "job_run_events",
        "claim_events",
        "claim_documents",
        "claim_reserve_movements",
    }
)

# These are processing queues whose core identity is protected separately but
# whose delivery/rating state is intentionally mutable.
MUTABLE_EVENT_TABLE_EXCEPTIONS: Final[frozenset[str]] = frozenset(
    {"charge_events", "outbox_events"}
)

APPEND_ONLY_GUARD_FUNCTIONS: Final[tuple[str, ...]] = (
    "prevent_append_only_change",
    "block_immutable_change",
    "reject_append_only_change",
)


@dataclass(frozen=True)
class AuditCounts:
    """Aggregate results that contain no catalog identifiers or business data."""

    modules: int
    domains: int
    tables: int
    foreign_keys: int
    checks: int
    indexes: int
    tenant_tables: int
    same_tenant_references: int
    security_definers: int
    append_only_tables: int


class CatalogAuditError(RuntimeError):
    """Count-only audit failure safe for logs and unattended verification."""

    def __init__(self, violations: dict[str, int]) -> None:
        self.violations = {
            name: count for name, count in sorted(violations.items()) if count
        }
        super().__init__(self.render())

    def render(self) -> str:
        rendered = ", ".join(
            f"{name}={count}" for name, count in self.violations.items()
        )
        return "EWMS catalog audit failed: " + rendered


def _critical_append_only_tables(
    files: list[Path], expected_tables: set[str]
) -> frozenset[str]:
    configured = _configured_append_only_tables(files)
    sql_declared: set[str] = set()
    guard_alternation = "|".join(APPEND_ONLY_GUARD_FUNCTIONS)
    direct_trigger_pattern = re.compile(
        r"CREATE\s+(?:CONSTRAINT\s+)?TRIGGER\s+[a-z0-9_]+\s+"
        r"BEFORE\s+(?:UPDATE\s+OR\s+DELETE|DELETE\s+OR\s+UPDATE)\s+"
        r"ON\s+ewms\.([a-z0-9_]+)[^;]*?"
        rf"EXECUTE\s+(?:FUNCTION|PROCEDURE)\s+ewms\.({guard_alternation})\s*\(",
        re.IGNORECASE,
    )
    dollar_block_pattern = re.compile(
        r"DO\s+\$([a-z0-9_]*)\$(.*?)\$\1\$\s*;",
        re.IGNORECASE | re.DOTALL,
    )
    array_pattern = re.compile(
        r"ARRAY\s*\[(.*?)\]\s*::\s*text\s*\[\s*\]",
        re.IGNORECASE | re.DOTALL,
    )
    for path in files:
        sql = path.read_text(encoding="utf-8")
        sql_declared.update(
            match.group(1).lower()
            for match in direct_trigger_pattern.finditer(sql)
        )
        for block_match in dollar_block_pattern.finditer(sql):
            block = block_match.group(2)
            normalized = block.lower()
            if (
                "before update or delete" not in normalized
                and "before delete or update" not in normalized
            ):
                continue
            if not any(
                guard_name in normalized
                for guard_name in APPEND_ONLY_GUARD_FUNCTIONS
            ):
                continue
            for array_match in array_pattern.finditer(block):
                sql_declared.update(
                    re.findall(
                        r"'([a-z][a-z0-9_]*)'",
                        array_match.group(1),
                        re.IGNORECASE,
                    )
                )
    convention_based = {
        table_name
        for table_name in expected_tables
        if (
            table_name.endswith("_events")
            or table_name.endswith("_history")
        )
        and table_name not in MUTABLE_EVENT_TABLE_EXCEPTIONS
    }
    return frozenset(
        configured
        | CRITICAL_APPEND_ONLY_CORE
        | convention_based
        | (sql_declared & expected_tables)
    )


def _catalog_object_counts(
    conn: psycopg.Connection,
) -> tuple[int, int, int, int, int, int]:
    row = conn.execute(
        """
        SELECT
            count(DISTINCT relation.oid)
                FILTER (WHERE relation.relkind IN ('r','p')),
            count(DISTINCT constraint_row.oid)
                FILTER (WHERE constraint_row.contype = 'f'),
            count(DISTINCT constraint_row.oid)
                FILTER (WHERE constraint_row.contype = 'c'),
            count(DISTINCT index_row.indexrelid),
            count(DISTINCT constraint_row.oid)
                FILTER (
                    WHERE constraint_row.contype IN ('f','c')
                      AND NOT constraint_row.convalidated
                ),
            count(DISTINCT index_row.indexrelid)
                FILTER (
                    WHERE NOT index_row.indisvalid
                       OR NOT index_row.indisready
                       OR NOT index_row.indislive
                )
        FROM pg_class relation
        JOIN pg_namespace namespace_row
          ON namespace_row.oid = relation.relnamespace
        LEFT JOIN pg_constraint constraint_row
          ON constraint_row.conrelid = relation.oid
        LEFT JOIN pg_index index_row
          ON index_row.indrelid = relation.oid
        WHERE namespace_row.nspname = 'ewms'
          AND relation.relkind IN ('r','p')
        """
    ).fetchone()
    if row is None:
        raise RuntimeError("Unable to aggregate EWMS catalog objects")
    return tuple(int(value) for value in row)


def _actual_tables(conn: psycopg.Connection) -> set[str]:
    return {
        row[0]
        for row in conn.execute(
            """
            SELECT relation.relname
            FROM pg_class relation
            JOIN pg_namespace namespace_row
              ON namespace_row.oid = relation.relnamespace
            WHERE namespace_row.nspname = 'ewms'
              AND relation.relkind IN ('r','p')
            """
        ).fetchall()
    }


def _foreign_key_leading_index_counts(
    conn: psycopg.Connection,
) -> tuple[int, int]:
    row = conn.execute(
        """
        SELECT count(*),
               count(*) FILTER (
                   WHERE NOT EXISTS (
                       SELECT 1
                       FROM pg_index index_row
                       WHERE index_row.indrelid = constraint_row.conrelid
                         AND index_row.indisvalid
                         AND index_row.indisready
                         AND index_row.indislive
                         AND index_row.indpred IS NULL
                         AND (index_row.indkey::smallint[])
                                 [0:array_length(constraint_row.conkey, 1) - 1]
                             = constraint_row.conkey
                   )
               )
        FROM pg_constraint constraint_row
        JOIN pg_class child ON child.oid = constraint_row.conrelid
        JOIN pg_namespace child_namespace
          ON child_namespace.oid = child.relnamespace
        WHERE child_namespace.nspname = 'ewms'
          AND constraint_row.contype = 'f'
        """
    ).fetchone()
    return int(row[0]), int(row[1])


def _tenant_policy_counts(conn: psycopg.Connection) -> tuple[int, int]:
    row = conn.execute(
        """
        WITH tenant_tables AS (
            SELECT relation.oid, relation.relrowsecurity,
                   relation.relforcerowsecurity
            FROM pg_class relation
            JOIN pg_namespace namespace_row
              ON namespace_row.oid = relation.relnamespace
            JOIN pg_attribute tenant_column
              ON tenant_column.attrelid = relation.oid
             AND tenant_column.attname = 'tenant_id'
             AND tenant_column.attnum > 0
             AND NOT tenant_column.attisdropped
            WHERE namespace_row.nspname = 'ewms'
              AND relation.relkind IN ('r','p')
        )
        SELECT count(*),
               count(*) FILTER (
                   WHERE NOT tenant_table.relrowsecurity
                      OR NOT tenant_table.relforcerowsecurity
                      OR (SELECT count(*) FROM pg_policy policy_row
                          WHERE policy_row.polrelid = tenant_table.oid) <> 2
                      OR NOT EXISTS (
                          SELECT 1
                          FROM pg_policy policy_row
                          WHERE policy_row.polrelid = tenant_table.oid
                            AND policy_row.polname = 'tenant_select'
                            AND policy_row.polcmd = 'r'
                            AND policy_row.polpermissive
                            AND policy_row.polroles = ARRAY[0::oid]
                            AND position(
                                'current_tenant_id()' IN lower(
                                    COALESCE(
                                        pg_get_expr(
                                            policy_row.polqual,
                                            policy_row.polrelid
                                        ),
                                        ''
                                    )
                                )
                            ) > 0
                      )
                      OR NOT EXISTS (
                          SELECT 1
                          FROM pg_policy policy_row
                          WHERE policy_row.polrelid = tenant_table.oid
                            AND policy_row.polname = 'tenant_modify'
                            AND policy_row.polcmd = '*'
                            AND policy_row.polpermissive
                            AND policy_row.polroles = ARRAY[0::oid]
                            AND position(
                                'current_tenant_id()' IN lower(
                                    COALESCE(
                                        pg_get_expr(
                                            policy_row.polqual,
                                            policy_row.polrelid
                                        ),
                                        ''
                                    )
                                )
                            ) > 0
                            AND position(
                                'current_tenant_id()' IN lower(
                                    COALESCE(
                                        pg_get_expr(
                                            policy_row.polwithcheck,
                                            policy_row.polrelid
                                        ),
                                        ''
                                    )
                                )
                            ) > 0
                      )
               )
        FROM tenant_tables tenant_table
        """
    ).fetchone()
    return int(row[0]), int(row[1])


def _same_tenant_reference_counts(
    conn: psycopg.Connection,
) -> tuple[int, int]:
    row = conn.execute(
        """
        WITH tenant_foreign_keys AS (
            SELECT constraint_row.oid,
                   constraint_row.conname,
                   constraint_row.conrelid,
                   constraint_row.confrelid,
                   constraint_row.conkey,
                   constraint_row.confkey,
                   child.relname AS child_table,
                   parent.relname AS parent_table,
                   child_tenant.attnum AS child_tenant_attnum,
                   parent_tenant.attnum AS parent_tenant_attnum,
                   child_first.attname AS child_first_column,
                   parent_first.attname AS parent_first_column
            FROM pg_constraint constraint_row
            JOIN pg_class child ON child.oid = constraint_row.conrelid
            JOIN pg_namespace child_namespace
              ON child_namespace.oid = child.relnamespace
             AND child_namespace.nspname = 'ewms'
            JOIN pg_class parent ON parent.oid = constraint_row.confrelid
            JOIN pg_namespace parent_namespace
              ON parent_namespace.oid = parent.relnamespace
             AND parent_namespace.nspname = 'ewms'
            JOIN pg_attribute child_tenant
              ON child_tenant.attrelid = child.oid
             AND child_tenant.attname = 'tenant_id'
             AND child_tenant.attnum > 0
             AND NOT child_tenant.attisdropped
            JOIN pg_attribute parent_tenant
              ON parent_tenant.attrelid = parent.oid
             AND parent_tenant.attname = 'tenant_id'
             AND parent_tenant.attnum > 0
             AND NOT parent_tenant.attisdropped
            JOIN pg_attribute child_first
              ON child_first.attrelid = child.oid
             AND child_first.attnum = constraint_row.conkey[1]
            JOIN pg_attribute parent_first
              ON parent_first.attrelid = parent.oid
             AND parent_first.attnum = constraint_row.confkey[1]
            WHERE constraint_row.contype = 'f'
              AND constraint_row.convalidated
        ), coverage AS (
            SELECT tenant_fk.*,
                   EXISTS (
                       SELECT 1
                       FROM generate_subscripts(tenant_fk.conkey, 1) position_no
                       WHERE tenant_fk.conkey[position_no]
                                 = tenant_fk.child_tenant_attnum
                         AND tenant_fk.confkey[position_no]
                                 = tenant_fk.parent_tenant_attnum
                   ) AS carries_tenant_pair,
                   EXISTS (
                       SELECT 1
                       FROM pg_constraint companion
                       WHERE companion.contype = 'f'
                         AND companion.convalidated
                         AND companion.conrelid = tenant_fk.conrelid
                         AND companion.confrelid = tenant_fk.confrelid
                         AND EXISTS (
                             SELECT 1
                             FROM generate_subscripts(companion.conkey, 1)
                                  companion_position
                             WHERE companion.conkey[companion_position]
                                       = tenant_fk.child_tenant_attnum
                               AND companion.confkey[companion_position]
                                       = tenant_fk.parent_tenant_attnum
                         )
                         AND NOT EXISTS (
                             SELECT 1
                             FROM generate_subscripts(tenant_fk.conkey, 1)
                                  original_position
                             WHERE NOT EXISTS (
                                 SELECT 1
                                 FROM generate_subscripts(companion.conkey, 1)
                                      companion_position
                                 WHERE companion.conkey[companion_position]
                                           = tenant_fk.conkey[original_position]
                                   AND companion.confkey[companion_position]
                                           = tenant_fk.confkey[original_position]
                             )
                         )
                   ) AS has_tenant_companion,
                   EXISTS (
                       SELECT 1
                       FROM pg_trigger trigger_row
                       WHERE array_length(tenant_fk.conkey, 1) = 1
                         AND tenant_fk.parent_first_column = 'id'
                         AND trigger_row.tgrelid = tenant_fk.conrelid
                         AND trigger_row.tgname = 'trg_tenant_fk_' || substr(
                             md5(
                                 'ewms.' || tenant_fk.child_table || '.'
                                 || tenant_fk.conname
                             ),
                             1,
                             12
                         )
                         AND trigger_row.tgfoid = to_regprocedure(
                             'ewms.enforce_same_tenant_fk()'
                         )
                         AND NOT trigger_row.tgisinternal
                         AND trigger_row.tgenabled IN ('O','A')
                         AND (trigger_row.tgtype & 1) = 1
                         AND (trigger_row.tgtype & 2) = 2
                         AND (trigger_row.tgtype & 4) = 4
                         AND (trigger_row.tgtype & 16) = 16
                         AND tenant_fk.conkey[1]
                               = ANY(trigger_row.tgattr::smallint[])
                         AND encode(trigger_row.tgargs, 'hex') =
                             encode(
                                 convert_to(
                                     tenant_fk.child_first_column,
                                     'UTF8'
                                 ),
                                 'hex'
                             ) || '00' ||
                             encode(convert_to('ewms', 'UTF8'), 'hex') || '00' ||
                             encode(
                                 convert_to(tenant_fk.parent_table, 'UTF8'),
                                 'hex'
                             ) || '00'
                   ) AS has_tenant_trigger
            FROM tenant_foreign_keys tenant_fk
        )
        SELECT count(*),
               count(*) FILTER (
                   WHERE NOT (
                       carries_tenant_pair
                       OR has_tenant_companion
                       OR has_tenant_trigger
                   )
               )
        FROM coverage
        """
    ).fetchone()
    return int(row[0]), int(row[1])


def _public_privilege_counts(
    conn: psycopg.Connection,
) -> tuple[int, int, int, int]:
    schema_count = conn.execute(
        """
        SELECT count(*)
        FROM pg_namespace namespace_row
        CROSS JOIN LATERAL aclexplode(
            COALESCE(
                namespace_row.nspacl,
                acldefault('n', namespace_row.nspowner)
            )
        ) privilege_row
        WHERE namespace_row.nspname = 'ewms'
          AND privilege_row.grantee = 0
        """
    ).fetchone()[0]
    relation_count = conn.execute(
        """
        SELECT count(*)
        FROM pg_class relation
        JOIN pg_namespace namespace_row
          ON namespace_row.oid = relation.relnamespace
        CROSS JOIN LATERAL aclexplode(
            COALESCE(
                relation.relacl,
                acldefault(
                    CASE
                        WHEN relation.relkind = 'S' THEN 'S'::"char"
                        ELSE 'r'::"char"
                    END,
                    relation.relowner
                )
            )
        ) privilege_row
        WHERE namespace_row.nspname = 'ewms'
          AND relation.relkind IN ('r','p','v','m','S','f')
          AND privilege_row.grantee = 0
        """
    ).fetchone()[0]
    function_count = conn.execute(
        """
        SELECT count(*)
        FROM pg_proc function_row
        JOIN pg_namespace namespace_row
          ON namespace_row.oid = function_row.pronamespace
        CROSS JOIN LATERAL aclexplode(
            COALESCE(
                function_row.proacl,
                acldefault('f', function_row.proowner)
            )
        ) privilege_row
        WHERE namespace_row.nspname = 'ewms'
          AND privilege_row.grantee = 0
        """
    ).fetchone()[0]
    security_definer_count = conn.execute(
        """
        SELECT count(*)
        FROM pg_proc function_row
        JOIN pg_namespace namespace_row
          ON namespace_row.oid = function_row.pronamespace
        CROSS JOIN LATERAL aclexplode(
            COALESCE(
                function_row.proacl,
                acldefault('f', function_row.proowner)
            )
        ) privilege_row
        WHERE namespace_row.nspname = 'ewms'
          AND function_row.prosecdef
          AND privilege_row.grantee = 0
          AND privilege_row.privilege_type = 'EXECUTE'
        """
    ).fetchone()[0]
    return (
        int(schema_count),
        int(relation_count),
        int(function_count),
        int(security_definer_count),
    )


def _security_definer_counts(conn: psycopg.Connection) -> tuple[int, int]:
    row = conn.execute(
        """
        SELECT count(*),
               count(*) FILTER (
                   WHERE NOT EXISTS (
                       SELECT 1
                       FROM unnest(
                           COALESCE(
                               function_row.proconfig,
                               ARRAY[]::text[]
                           )
                       ) setting(value)
                       WHERE lower(
                           regexp_replace(
                               setting.value,
                               '[[:space:]]',
                               '',
                               'g'
                           )
                       ) = 'search_path=pg_catalog,ewms'
                   )
               )
        FROM pg_proc function_row
        JOIN pg_namespace namespace_row
          ON namespace_row.oid = function_row.pronamespace
        WHERE namespace_row.nspname = 'ewms'
          AND function_row.prosecdef
        """
    ).fetchone()
    return int(row[0]), int(row[1])


def _context_definition_violations(conn: psycopg.Connection) -> tuple[int, int]:
    found_function_names = {
        row[0]
        for row in conn.execute(
            """
            SELECT DISTINCT function_row.proname
            FROM pg_proc function_row
            JOIN pg_namespace namespace_row
              ON namespace_row.oid = function_row.pronamespace
            WHERE namespace_row.nspname = 'ewms'
              AND function_row.proname = ANY(%s::text[])
            """,
            (sorted(REQUIRED_CONTEXT_FUNCTIONS),),
        ).fetchall()
    }
    current_tenant_rows = conn.execute(
        """
        SELECT function_row.prosrc
        FROM pg_proc function_row
        JOIN pg_namespace namespace_row
          ON namespace_row.oid = function_row.pronamespace
        WHERE namespace_row.nspname = 'ewms'
          AND function_row.proname = 'current_tenant_id'
          AND function_row.pronargs = 0
        """
    ).fetchall()
    definition_violation = int(
        len(current_tenant_rows) != 1
        or "request_contexts" not in current_tenant_rows[0][0].lower()
        or "backend_pid" not in current_tenant_rows[0][0].lower()
        or "transaction_id" not in current_tenant_rows[0][0].lower()
        or "pg_backend_pid" not in current_tenant_rows[0][0].lower()
        or "txid_current" not in current_tenant_rows[0][0].lower()
        or "current_setting" in current_tenant_rows[0][0].lower()
    )
    return (
        len(REQUIRED_CONTEXT_FUNCTIONS - found_function_names),
        definition_violation,
    )


def _spoofed_guc_violation(conn: psycopg.Connection) -> int:
    spoof_value = "11111111-1111-4111-8111-111111111111"
    configured = conn.execute(
        "SELECT set_config(%s, %s, true) = %s",
        ("ewms.tenant_id", spoof_value, spoof_value),
    ).fetchone()[0]
    tenant_is_null, user_is_null = conn.execute(
        """
        SELECT ewms.current_tenant_id() IS NULL,
               ewms.current_ewms_user_id() IS NULL
        """
    ).fetchone()
    return int(not (configured and tenant_is_null and user_is_null))


def _forbidden_raw_credential_column_count(conn: psycopg.Connection) -> int:
    return int(
        conn.execute(
            """
            SELECT count(*)
            FROM pg_class relation
            JOIN pg_namespace namespace_row
              ON namespace_row.oid = relation.relnamespace
            JOIN pg_attribute attribute
              ON attribute.attrelid = relation.oid
            WHERE namespace_row.nspname = 'ewms'
              AND relation.relkind IN ('r','p')
              AND attribute.attnum > 0
              AND NOT attribute.attisdropped
              AND (
                  attribute.attname ~ '(^|_)password([a-z0-9_]*$)'
                  OR attribute.attname IN (
                      'id_token',
                      'access_token',
                      'refresh_token',
                      'firebase_token',
                      'google_token',
                      'oauth_token',
                      'bearer_token',
                      'api_token',
                      'credential_token',
                      'raw_token',
                      'session_token',
                      'session_handle',
                      'client_secret',
                      'secret',
                      'secret_value',
                      'token',
                      'token_value'
                  )
                  OR attribute.attname ~ '(^|_)(access_token|refresh_token)$'
              )
            """
        ).fetchone()[0]
    )


def _append_only_counts(
    conn: psycopg.Connection, critical_tables: frozenset[str]
) -> tuple[int, int]:
    row = conn.execute(
        """
        WITH required(table_name) AS (
            SELECT unnest(%s::text[])
        ), coverage AS (
            SELECT required.table_name,
                   relation.oid,
                   EXISTS (
                       SELECT 1
                       FROM pg_trigger trigger_row
                       JOIN pg_proc function_row
                         ON function_row.oid = trigger_row.tgfoid
                       JOIN pg_namespace function_namespace
                         ON function_namespace.oid = function_row.pronamespace
                       WHERE trigger_row.tgrelid = relation.oid
                         AND function_namespace.nspname = 'ewms'
                         AND function_row.proname IN (
                             'prevent_append_only_change',
                             'block_immutable_change',
                             'reject_append_only_change'
                         )
                         AND NOT trigger_row.tgisinternal
                         AND trigger_row.tgenabled IN ('O','A')
                         AND (trigger_row.tgtype & 1) = 1
                         AND (trigger_row.tgtype & 2) = 2
                         AND (trigger_row.tgtype & 8) = 8
                         AND (trigger_row.tgtype & 16) = 16
                   ) AS row_guarded,
                   EXISTS (
                       SELECT 1
                       FROM pg_trigger trigger_row
                       JOIN pg_proc function_row
                         ON function_row.oid = trigger_row.tgfoid
                       JOIN pg_namespace function_namespace
                         ON function_namespace.oid = function_row.pronamespace
                       WHERE trigger_row.tgrelid = relation.oid
                         AND function_namespace.nspname = 'ewms'
                         AND function_row.proname IN (
                             'prevent_append_only_change',
                             'block_immutable_change',
                             'reject_append_only_change'
                         )
                         AND NOT trigger_row.tgisinternal
                         AND trigger_row.tgenabled IN ('O','A')
                         AND (trigger_row.tgtype & 1) = 0
                         AND (trigger_row.tgtype & 2) = 2
                         AND (trigger_row.tgtype & 32) = 32
                   ) AS truncate_guarded
            FROM required
            LEFT JOIN pg_namespace namespace_row
              ON namespace_row.nspname = 'ewms'
            LEFT JOIN pg_class relation
              ON relation.relnamespace = namespace_row.oid
             AND relation.relname = required.table_name
             AND relation.relkind IN ('r','p')
        )
        SELECT count(*),
               count(*) FILTER (
                   WHERE oid IS NULL
                      OR NOT row_guarded
                      OR NOT truncate_guarded
               )
        FROM coverage
        """,
        (sorted(critical_tables),),
    ).fetchone()
    return int(row[0]), int(row[1])


def _audit_catalog(
    conn: psycopg.Connection,
    files: list[Path],
    expected_tables: set[str],
) -> AuditCounts:
    transaction_state = conn.execute(
        """
        SELECT current_setting('transaction_read_only') = 'on',
               current_setting('transaction_isolation') = 'repeatable read',
               current_setting('server_version_num')::integer
        """
    ).fetchone()
    transaction_read_only, repeatable_read, server_version_num = transaction_state

    actual_tables = _actual_tables(conn)
    (
        table_count,
        foreign_key_count,
        check_count,
        index_count,
        unvalidated_constraint_count,
        invalid_index_count,
    ) = _catalog_object_counts(conn)
    _, unindexed_foreign_key_count = _foreign_key_leading_index_counts(conn)
    tenant_table_count, tenant_policy_violation_count = _tenant_policy_counts(conn)
    (
        same_tenant_reference_count,
        same_tenant_violation_count,
    ) = _same_tenant_reference_counts(conn)
    (
        public_schema_privileges,
        public_relation_privileges,
        public_function_privileges,
        public_security_definer_execute,
    ) = _public_privilege_counts(conn)
    security_definer_count, unsafe_search_path_count = _security_definer_counts(conn)
    (
        missing_context_function_count,
        current_tenant_definition_violation,
    ) = _context_definition_violations(conn)
    spoofed_guc_violation = (
        1
        if missing_context_function_count
        else _spoofed_guc_violation(conn)
    )
    forbidden_credential_column_count = _forbidden_raw_credential_column_count(conn)
    critical_append_only_tables = _critical_append_only_tables(
        files, expected_tables
    )
    append_only_count, append_only_violation_count = _append_only_counts(
        conn, critical_append_only_tables
    )

    violations = {
        "transaction_mode": int(not transaction_read_only or not repeatable_read),
        "postgresql_11": int(not 110000 <= server_version_num < 120000),
        "exact_table_set": len(expected_tables ^ actual_tables),
        "required_domain_tables": len(REQUIRED_DOMAIN_TABLES - actual_tables),
        "unvalidated_fk_or_check": unvalidated_constraint_count,
        "invalid_indexes": invalid_index_count,
        "fk_leading_indexes": unindexed_foreign_key_count,
        "tenant_rls_force_policies": tenant_policy_violation_count,
        "same_tenant_references": same_tenant_violation_count,
        "public_schema_privileges": public_schema_privileges,
        "public_relation_privileges": public_relation_privileges,
        "public_function_privileges": public_function_privileges,
        "security_definer_public_execute": public_security_definer_execute,
        "security_definer_search_path": unsafe_search_path_count,
        "context_functions": missing_context_function_count,
        "current_tenant_definition": current_tenant_definition_violation,
        "spoofed_tenant_guc": spoofed_guc_violation,
        "raw_credential_columns": forbidden_credential_column_count,
        "append_only_guards": append_only_violation_count,
    }
    if any(violations.values()):
        raise CatalogAuditError(violations)

    return AuditCounts(
        modules=len(files),
        domains=len(REQUIRED_TABLES_BY_DOMAIN),
        tables=table_count,
        foreign_keys=foreign_key_count,
        checks=check_count,
        indexes=index_count,
        tenant_tables=tenant_table_count,
        same_tenant_references=same_tenant_reference_count,
        security_definers=security_definer_count,
        append_only_tables=append_only_count,
    )


def main() -> int:
    try:
        files = _sql_files()
        expected_tables, _expected_indexes, _expected_triggers = _expected_catalog(
            files
        )
        with psycopg.connect(settings.database_url) as conn:
            conn.execute(
                "SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY"
            )
            conn.execute("SET LOCAL statement_timeout = '2min'")
            _assert_actual_target(conn)
            counts = _audit_catalog(conn, files, expected_tables)
            conn.rollback()
    except CatalogAuditError as exc:
        print(exc.render(), file=sys.stderr)
        return 1
    except Exception:
        # Imported target guards and driver errors can include host/object detail.
        # Keep this standalone audit aggregate-only; the apply verifier is the
        # DBA-facing diagnostic command.
        print(
            "EWMS catalog audit failed: catalog_or_internal_failures=1",
            file=sys.stderr,
        )
        return 1

    print(
        "EWMS catalog audit passed: "
        f"modules={counts.modules}, "
        f"domains={counts.domains}, "
        f"tables={counts.tables}, "
        f"foreign_keys={counts.foreign_keys}, "
        f"checks={counts.checks}, "
        f"indexes={counts.indexes}, "
        f"tenant_tables={counts.tenant_tables}, "
        f"same_tenant_references={counts.same_tenant_references}, "
        f"security_definers={counts.security_definers}, "
        f"append_only_tables={counts.append_only_tables}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
