"""Read-only, independent catalog audit for the deployed ETMS baseline.

The audit deliberately prints aggregate counts only.  It never selects business
rows, credential material, JSON payloads, ciphertext, or secret references.
"""

from __future__ import annotations

import sys
from dataclasses import dataclass
from typing import Final

from apply_etms_schema import (
    _assert_actual_target,
    _checksum,
    _expected_catalog,
    _load_forward_migrations,
    _load_sql_modules,
    _sql_files,
    _verify,
    psycopg,
    settings,
)


# Only schema ledger, global authentication, transaction context, and global
# reference tables may omit tenant_id entirely.
TENANTLESS_TABLES_BY_CLASS: Final[dict[str, frozenset[str]]] = {
    "schema": frozenset({"schema_migrations"}),
    "auth_global": frozenset(
        {
            "auth_identities",
            "auth_sessions",
            "tenants",
            "terms_versions",
            "user_devices",
            "user_profiles",
            "user_terms_agreements",
            "users",
        }
    ),
    "context": frozenset(
        {
            "identity_command_contexts",
            "membership_provision_contexts",
            "request_contexts",
            "session_issue_contexts",
        }
    ),
    "reference": frozenset(
        {
            "countries",
            "currencies",
            "permissions",
            "transport_modes",
            "unit_conversions",
            "units_of_measure",
        }
    ),
}
TENANTLESS_TABLE_ALLOWLIST: Final[frozenset[str]] = frozenset().union(
    *TENANTLESS_TABLES_BY_CLASS.values()
)


# These tables intentionally support both tenant-owned and system-wide rows.
# Nullable tenant identifiers are forbidden everywhere else.  Log tables are
# separated so an operational log cannot be silently reclassified as reference
# data merely to bypass this check.
NULLABLE_TENANT_GLOBAL_TABLES: Final[frozenset[str]] = frozenset(
    {
        "charge_codes",
        "code_sets",
        "code_values",
        "commodity_classes",
        "data_quality_rules",
        "data_retention_policies",
        "emission_factors",
        "equipment_types",
        "exchange_rates",
        "fuel_index_values",
        "fuel_indices",
        "kpi_definitions",
        "notification_templates",
        "payment_terms",
        "role_permissions",
        "roles",
        "scheduled_jobs",
        "service_levels",
        "status_definitions",
        "status_transitions",
        "tax_codes",
        "tax_rates",
        "vehicle_types",
    }
)
NULLABLE_TENANT_LOG_TABLES: Final[frozenset[str]] = frozenset(
    {"audit_events", "data_access_logs", "job_runs", "login_events"}
)
NULLABLE_TENANT_ID_ALLOWLIST: Final[frozenset[str]] = (
    NULLABLE_TENANT_GLOBAL_TABLES | NULLABLE_TENANT_LOG_TABLES
)


# Required cross-column identity constraints.  Single-column foreign keys do
# not prove that a request's session, membership, user, and tenant agree.
CompositeForeignKey = tuple[str, tuple[str, ...], str, tuple[str, ...]]
REQUIRED_COMPOSITE_FOREIGN_KEYS: Final[frozenset[CompositeForeignKey]] = frozenset(
    {
        (
            "auth_sessions",
            ("auth_identity_id", "user_id"),
            "auth_identities",
            ("id", "user_id"),
        ),
        (
            "auth_sessions",
            ("active_membership_id", "user_id", "active_tenant_id"),
            "tenant_memberships",
            ("id", "user_id", "tenant_id"),
        ),
        (
            "request_contexts",
            (
                "bound_session_id",
                "bound_user_id",
                "bound_tenant_id",
                "bound_membership_id",
            ),
            "auth_sessions",
            ("id", "user_id", "active_tenant_id", "active_membership_id"),
        ),
        (
            "request_contexts",
            ("bound_membership_id", "bound_user_id", "bound_tenant_id"),
            "tenant_memberships",
            ("id", "user_id", "tenant_id"),
        ),
        (
            "session_issue_contexts",
            ("bound_membership_id", "bound_user_id", "bound_tenant_id"),
            "tenant_memberships",
            ("id", "user_id", "tenant_id"),
        ),
        (
            "membership_provision_contexts",
            ("bound_membership_id", "bound_user_id", "bound_tenant_id"),
            "tenant_memberships",
            ("id", "user_id", "tenant_id"),
        ),
        (
            "identity_command_contexts",
            ("bound_membership_id", "bound_user_id", "bound_tenant_id"),
            "tenant_memberships",
            ("id", "user_id", "tenant_id"),
        ),
    }
)


# Immutable operational evidence is corrected by a new row, never by mutating
# or truncating the original evidence.  This list intentionally mirrors the
# business classification, not trigger-name discovery, so a removed trigger is
# observable.
APPEND_ONLY_EVIDENCE_TABLES: Final[frozenset[str]] = frozenset(
    {
        "access_review_decisions",
        "account_link_events",
        "assignment_status_history",
        "audit_event_integrity_anchors",
        "audit_events",
        "claim_events",
        "claim_movements",
        "claim_reserve_movements",
        "container_events",
        "custody_transfers",
        "data_access_logs",
        "dispatch_status_history",
        "driver_duty_logs",
        "driver_task_events",
        "driving_hours_violations",
        "entity_change_logs",
        "execution_state_transitions",
        "geofence_events",
        "gps_positions",
        "handling_unit_parent_history",
        "handling_unit_state_history",
        "handling_unit_status_history",
        "invoice_status_history",
        "login_events",
        "milestone_events",
        "order_split_merge_events",
        "order_status_history",
        "planning_input_snapshots",
        "planning_snapshot_orders",
        "planning_snapshot_resources",
        "pod_correction_events",
        "pod_verification_events",
        "port_terminal_events",
        "rate_quote_acceptance_events",
        "rating_snapshot_lines",
        "rating_snapshots",
        "replan_events",
        "run_status_history",
        "scan_events",
        "sensor_readings",
        "shipment_status_history",
        "spot_bid_events",
        "stop_dwell_events",
        "stop_status_history",
        "tax_invoice_events",
        "tender_award_history",
        "transport_event_corrections",
        "transport_events",
        "vehicle_registration_history",
        "yard_events",
    }
)


# Exact monetary exceptions without a local currency column.  In each case the
# currency is functionally inherited from the named immutable/parent business
# document, or the suffix explicitly denotes the tenant reporting base currency.
# Keeping exceptions at (table, column) grain prevents future amount columns in
# the same table from inheriting an accidental blanket exemption.
AMOUNT_WITHOUT_CURRENCY_ALLOWLIST: Final[dict[tuple[str, str], str]] = {
    ("accounting_exports", "total_amount"): "organization base currency",
    (
        "carrier_performance_facts",
        "invoice_variance_amount_base",
    ): "tenant reporting base currency",
    (
        "carrier_performance_facts",
        "invoiced_amount_base",
    ): "tenant reporting base currency",
    ("charge_adjustments", "gross_amount_delta"): "parent charge currency",
    ("charge_adjustments", "net_amount_delta"): "parent charge currency",
    ("charge_adjustments", "tax_amount_delta"): "parent charge currency",
    ("charge_allocations", "allocated_gross_amount"): "parent charge currency",
    ("charge_allocations", "allocated_net_amount"): "parent charge currency",
    ("charge_allocations", "allocated_tax_amount"): "parent charge currency",
    ("claim_items", "approved_amount"): "parent claim currency",
    ("claim_items", "claimed_amount"): "parent claim currency",
    (
        "customs_declaration_items",
        "duty_amount",
    ): "parent customs declaration currency",
    (
        "customs_declaration_items",
        "tax_amount",
    ): "parent customs declaration currency",
    ("invoice_dispute_events", "amount"): "parent invoice dispute currency",
    (
        "invoice_line_charges",
        "allocated_gross_amount",
    ): "parent invoice currency",
    (
        "invoice_line_charges",
        "allocated_net_amount",
    ): "parent invoice currency",
    (
        "invoice_line_charges",
        "allocated_tax_amount",
    ): "parent invoice currency",
    ("invoice_lines", "discount_amount"): "parent invoice currency",
    ("invoice_lines", "gross_amount"): "parent invoice currency",
    ("invoice_lines", "net_amount"): "parent invoice currency",
    ("invoice_lines", "tax_amount"): "parent invoice currency",
    ("invoice_match_results", "expected_amount"): "parent invoice currency",
    ("invoice_match_results", "invoiced_amount"): "parent invoice currency",
    ("invoice_match_results", "tolerance_amount"): "parent invoice currency",
    ("invoice_match_results", "variance_amount"): "parent invoice currency",
    ("invoice_taxes", "recoverable_amount"): "parent invoice currency",
    ("invoice_taxes", "taxable_amount"): "parent invoice currency",
    ("invoice_taxes", "tax_amount"): "parent invoice currency",
    ("journal_lines", "base_credit_amount"): "parent journal base currency",
    ("journal_lines", "base_debit_amount"): "parent journal base currency",
    ("journal_lines", "credit_amount"): "parent journal transaction currency",
    ("journal_lines", "debit_amount"): "parent journal transaction currency",
    ("payment_applications", "applied_amount"): "parent payment currency",
    ("payment_applications", "writeoff_amount"): "parent payment currency",
    ("rate_quote_lines", "gross_amount"): "parent rate quote currency",
    ("rate_quote_lines", "net_amount"): "parent rate quote currency",
    ("rate_quote_lines", "tax_amount"): "parent rate quote currency",
    ("rate_rule_tiers", "flat_amount"): "parent rate card currency",
    ("settlement_lines", "deduction_amount"): "parent settlement currency",
    ("settlement_lines", "gross_amount"): "parent settlement currency",
    ("settlement_lines", "net_amount"): "parent settlement currency",
    ("settlement_lines", "tax_amount"): "parent settlement currency",
    ("tax_invoice_lines", "supply_amount"): "parent tax invoice currency",
    ("tax_invoice_lines", "tax_amount"): "parent tax invoice currency",
    ("tender_rounds", "reserve_amount"): "parent tender currency",
}


# Exact quantity exceptions without a local UOM.  They are counts or allocations
# whose unit is fixed by the structural/parent document, rather than independent
# measured quantities.
QUANTITY_WITHOUT_UOM_ALLOWLIST: Final[dict[tuple[str, str], str]] = {
    ("handling_units", "quantity"): "count of the declared handling-unit type",
    (
        "shipment_orders",
        "allocation_quantity",
    ): "source transport-order quantity UOM",
    (
        "tax_invoice_lines",
        "quantity",
    ): "source invoice-line UOM or legal presentation count",
}


@dataclass(frozen=True)
class AuditCounts:
    """Aggregate-only audit results safe to print."""

    tables: int
    tenantless_tables: int
    nullable_tenant_tables: int
    tenant_business_tables: int
    composite_foreign_keys: int
    jsonb_tables: int
    encrypted_columns: int
    secret_reference_columns: int
    append_only_tables: int
    amount_columns: int
    amount_exceptions: int
    quantity_columns: int
    quantity_exceptions: int


class CatalogAuditError(RuntimeError):
    """A count-only catalog failure safe for unattended audit output."""

    def __init__(self, violations: dict[str, int]) -> None:
        self.violations = {
            name: count for name, count in sorted(violations.items()) if count
        }
        super().__init__(self.render())

    def render(self) -> str:
        counts = ", ".join(
            f"{name}={count}" for name, count in self.violations.items()
        )
        return "ETMS catalog audit failed: " + counts


def _table_tenant_classification(
    conn: psycopg.Connection,
) -> dict[str, bool | None]:
    """Return table -> tenant_id NOT NULL; None means no tenant_id column."""

    rows = conn.execute(
        """
        SELECT relation.relname, tenant_column.attnotnull
        FROM pg_class relation
        JOIN pg_namespace namespace_row
          ON namespace_row.oid = relation.relnamespace
        LEFT JOIN pg_attribute tenant_column
          ON tenant_column.attrelid = relation.oid
         AND tenant_column.attname = 'tenant_id'
         AND tenant_column.attnum > 0
         AND NOT tenant_column.attisdropped
        WHERE namespace_row.nspname = 'etms'
          AND relation.relkind = 'r'
        ORDER BY relation.relname
        """
    ).fetchall()
    return {table_name: is_not_null for table_name, is_not_null in rows}


def _validated_composite_foreign_keys(
    conn: psycopg.Connection,
) -> set[CompositeForeignKey]:
    rows = conn.execute(
        """
        SELECT child.relname,
               ARRAY(
                   SELECT attribute.attname
                   FROM unnest(constraint_row.conkey)
                        WITH ORDINALITY AS key_column(attnum, position)
                   JOIN pg_attribute attribute
                     ON attribute.attrelid = constraint_row.conrelid
                    AND attribute.attnum = key_column.attnum
                   ORDER BY key_column.position
               ),
               parent.relname,
               ARRAY(
                   SELECT attribute.attname
                   FROM unnest(constraint_row.confkey)
                        WITH ORDINALITY AS key_column(attnum, position)
                   JOIN pg_attribute attribute
                     ON attribute.attrelid = constraint_row.confrelid
                    AND attribute.attnum = key_column.attnum
                   ORDER BY key_column.position
               )
        FROM pg_constraint constraint_row
        JOIN pg_class child ON child.oid = constraint_row.conrelid
        JOIN pg_namespace child_namespace
          ON child_namespace.oid = child.relnamespace
        JOIN pg_class parent ON parent.oid = constraint_row.confrelid
        JOIN pg_namespace parent_namespace
          ON parent_namespace.oid = parent.relnamespace
        WHERE child_namespace.nspname = 'etms'
          AND parent_namespace.nspname = 'etms'
          AND constraint_row.contype = 'f'
          AND constraint_row.convalidated
        """
    ).fetchall()
    return {
        (child, tuple(child_columns), parent, tuple(parent_columns))
        for child, child_columns, parent, parent_columns in rows
    }


def _public_privilege_counts(conn: psycopg.Connection) -> tuple[int, int]:
    table_count = conn.execute(
        """
        SELECT count(DISTINCT relation.oid)
        FROM pg_class relation
        JOIN pg_namespace namespace_row
          ON namespace_row.oid = relation.relnamespace
        CROSS JOIN LATERAL aclexplode(
            COALESCE(relation.relacl, acldefault('r', relation.relowner))
        ) privilege_row
        WHERE namespace_row.nspname = 'etms'
          AND relation.relkind IN ('r','p')
          AND privilege_row.grantee = 0
        """
    ).fetchone()[0]
    function_count = conn.execute(
        """
        SELECT count(DISTINCT function_row.oid)
        FROM pg_proc function_row
        JOIN pg_namespace namespace_row
          ON namespace_row.oid = function_row.pronamespace
        CROSS JOIN LATERAL aclexplode(
            COALESCE(function_row.proacl, acldefault('f', function_row.proowner))
        ) privilege_row
        WHERE namespace_row.nspname = 'etms'
          AND privilege_row.grantee = 0
        """
    ).fetchone()[0]
    return table_count, function_count


def _jsonb_trigger_coverage(conn: psycopg.Connection) -> tuple[int, int]:
    row = conn.execute(
        """
        WITH jsonb_tables AS (
            SELECT DISTINCT relation.oid
            FROM pg_class relation
            JOIN pg_namespace namespace_row
              ON namespace_row.oid = relation.relnamespace
            JOIN pg_attribute attribute ON attribute.attrelid = relation.oid
            WHERE namespace_row.nspname = 'etms'
              AND relation.relkind = 'r'
              AND attribute.attnum > 0
              AND NOT attribute.attisdropped
              AND attribute.atttypid = 'jsonb'::regtype
        )
        SELECT count(*),
               count(*) FILTER (
                   WHERE EXISTS (
                       SELECT 1
                       FROM pg_trigger trigger_row
                       WHERE trigger_row.tgrelid = jsonb_tables.oid
                         AND NOT trigger_row.tgisinternal
                         AND trigger_row.tgenabled IN ('O','A')
                         AND trigger_row.tgfoid = to_regprocedure(
                             'etms.reject_forbidden_json_secrets()'
                         )
                         AND (trigger_row.tgtype & 1) = 1
                         AND (trigger_row.tgtype & 2) = 2
                         AND (trigger_row.tgtype & 4) = 4
                         AND (trigger_row.tgtype & 16) = 16
                   )
               )
        FROM jsonb_tables
        """
    ).fetchone()
    return row[0], row[1]


def _protected_text_column_counts(
    conn: psycopg.Connection,
) -> tuple[int, int, int, int]:
    row = conn.execute(
        r"""
        WITH protected_columns AS (
            SELECT relation.oid AS table_oid, attribute.attnum,
                   attribute.attname,
                   attribute.attname LIKE '%\_encrypted' ESCAPE '\' AS encrypted,
                   (
                       attribute.attname LIKE '%\_secret\_ref' ESCAPE '\'
                       OR attribute.attname LIKE '%\_secret\_reference' ESCAPE '\'
                       OR attribute.attname = 'secret_reference'
                   ) AS secret_reference
            FROM pg_class relation
            JOIN pg_namespace namespace_row
              ON namespace_row.oid = relation.relnamespace
            JOIN pg_attribute attribute ON attribute.attrelid = relation.oid
            WHERE namespace_row.nspname = 'etms'
              AND relation.relkind = 'r'
              AND attribute.attnum > 0
              AND NOT attribute.attisdropped
              AND attribute.atttypid IN (
                  'text'::regtype, 'varchar'::regtype, 'bpchar'::regtype
              )
              AND (
                  attribute.attname LIKE '%\_encrypted' ESCAPE '\'
                  OR attribute.attname LIKE '%\_secret\_ref' ESCAPE '\'
                  OR attribute.attname LIKE '%\_secret\_reference' ESCAPE '\'
                  OR attribute.attname = 'secret_reference'
              )
        )
        SELECT
            count(*) FILTER (WHERE encrypted),
            count(*) FILTER (
                WHERE encrypted AND EXISTS (
                    SELECT 1
                    FROM pg_constraint constraint_row
                    WHERE constraint_row.conrelid = protected_columns.table_oid
                      AND constraint_row.contype = 'c'
                      AND constraint_row.convalidated
                      AND protected_columns.attnum = ANY(constraint_row.conkey)
                      AND position(
                          'is_valid_ciphertext_envelope'
                          IN pg_get_constraintdef(constraint_row.oid, true)
                      ) > 0
                )
            ),
            count(*) FILTER (WHERE secret_reference),
            count(*) FILTER (
                WHERE secret_reference AND EXISTS (
                    SELECT 1
                    FROM pg_constraint constraint_row
                    WHERE constraint_row.conrelid = protected_columns.table_oid
                      AND constraint_row.contype = 'c'
                      AND constraint_row.convalidated
                      AND protected_columns.attnum = ANY(constraint_row.conkey)
                      AND position(
                          'is_valid_secret_reference'
                          IN pg_get_constraintdef(constraint_row.oid, true)
                      ) > 0
                )
            )
        FROM protected_columns
        """
    ).fetchone()
    return row[0], row[1], row[2], row[3]


def _append_only_coverage(conn: psycopg.Connection) -> tuple[int, int]:
    covered = 0
    for table_name in APPEND_ONLY_EVIDENCE_TABLES:
        table_oid = conn.execute(
            "SELECT to_regclass(%s)::oid", (f"etms.{table_name}",)
        ).fetchone()[0]
        if table_oid is None:
            continue
        row_update, row_delete, statement_truncate = conn.execute(
            """
            SELECT
                EXISTS (
                    SELECT 1 FROM pg_trigger trigger_row
                    WHERE trigger_row.tgrelid = %s
                      AND NOT trigger_row.tgisinternal
                      AND trigger_row.tgenabled IN ('O','A')
                      AND trigger_row.tgfoid =
                          to_regprocedure('etms.prevent_ledger_mutation()')
                      AND (trigger_row.tgtype & 1) = 1
                      AND (trigger_row.tgtype & 2) = 2
                      AND (trigger_row.tgtype & 16) = 16
                ),
                EXISTS (
                    SELECT 1 FROM pg_trigger trigger_row
                    WHERE trigger_row.tgrelid = %s
                      AND NOT trigger_row.tgisinternal
                      AND trigger_row.tgenabled IN ('O','A')
                      AND trigger_row.tgfoid =
                          to_regprocedure('etms.prevent_ledger_mutation()')
                      AND (trigger_row.tgtype & 1) = 1
                      AND (trigger_row.tgtype & 2) = 2
                      AND (trigger_row.tgtype & 8) = 8
                ),
                EXISTS (
                    SELECT 1 FROM pg_trigger trigger_row
                    WHERE trigger_row.tgrelid = %s
                      AND NOT trigger_row.tgisinternal
                      AND trigger_row.tgenabled IN ('O','A')
                      AND trigger_row.tgfoid =
                          to_regprocedure('etms.prevent_ledger_mutation()')
                      AND (trigger_row.tgtype & 1) = 0
                      AND (trigger_row.tgtype & 2) = 2
                      AND (trigger_row.tgtype & 32) = 32
                )
            """,
            (table_oid, table_oid, table_oid),
        ).fetchone()
        if row_update and row_delete and statement_truncate:
            covered += 1
    return len(APPEND_ONLY_EVIDENCE_TABLES), covered


def _numeric_semantic_columns(
    conn: psycopg.Connection,
    semantic_pattern: str,
    companion_pattern: str,
) -> tuple[set[tuple[str, str]], set[tuple[str, str]]]:
    all_columns = {
        (table_name, column_name)
        for table_name, column_name in conn.execute(
            """
            SELECT relation.relname, attribute.attname
            FROM pg_class relation
            JOIN pg_namespace namespace_row
              ON namespace_row.oid = relation.relnamespace
            JOIN pg_attribute attribute ON attribute.attrelid = relation.oid
            JOIN pg_type type_row ON type_row.oid = attribute.atttypid
            WHERE namespace_row.nspname = 'etms'
              AND relation.relkind = 'r'
              AND attribute.attnum > 0
              AND NOT attribute.attisdropped
              AND type_row.typcategory = 'N'
              AND attribute.attname ~ %s
            """,
            (semantic_pattern,),
        ).fetchall()
    }
    without_companion = {
        (table_name, column_name)
        for table_name, column_name in conn.execute(
            """
            SELECT relation.relname, attribute.attname
            FROM pg_class relation
            JOIN pg_namespace namespace_row
              ON namespace_row.oid = relation.relnamespace
            JOIN pg_attribute attribute ON attribute.attrelid = relation.oid
            JOIN pg_type type_row ON type_row.oid = attribute.atttypid
            WHERE namespace_row.nspname = 'etms'
              AND relation.relkind = 'r'
              AND attribute.attnum > 0
              AND NOT attribute.attisdropped
              AND type_row.typcategory = 'N'
              AND attribute.attname ~ %s
              AND NOT EXISTS (
                  SELECT 1
                  FROM pg_attribute companion
                  WHERE companion.attrelid = relation.oid
                    AND companion.attnum > 0
                    AND NOT companion.attisdropped
                    AND companion.attname ~ %s
              )
            """,
            (semantic_pattern, companion_pattern),
        ).fetchall()
    }
    return all_columns, without_companion


def _assert_spoofed_guc_is_ignored(conn: psycopg.Connection) -> int:
    no_context = conn.execute(
        """
        SELECT NOT EXISTS (
            SELECT 1
            FROM etms.request_contexts context_row
            WHERE context_row.backend_pid = pg_backend_pid()
              AND context_row.transaction_id = txid_current()
        )
        """
    ).fetchone()[0]
    spoof_value = "11111111-1111-4111-8111-111111111111"
    conn.execute("SELECT set_config(%s, %s, true)", ("etms.tenant_id", spoof_value))
    configured_value, derived_tenant_id = conn.execute(
        "SELECT current_setting(%s, true), etms.current_tenant_id()",
        ("etms.tenant_id",),
    ).fetchone()
    return int(not (no_context and configured_value == spoof_value and derived_tenant_id is None))


def _audit_catalog(
    conn: psycopg.Connection,
    expected_tables: set[str],
) -> AuditCounts:
    transaction_state = conn.execute(
        """
        SELECT current_setting('transaction_read_only') = 'on',
               current_setting('transaction_isolation') = 'repeatable read'
        """
    ).fetchone()
    classifications = _table_tenant_classification(conn)
    actual_tables = set(classifications)
    actual_tenantless = {
        table_name
        for table_name, is_not_null in classifications.items()
        if is_not_null is None
    }
    actual_nullable_tenant = {
        table_name
        for table_name, is_not_null in classifications.items()
        if is_not_null is False
    }
    business_tables = (
        actual_tables
        - TENANTLESS_TABLE_ALLOWLIST
        - NULLABLE_TENANT_ID_ALLOWLIST
    )
    business_tenant_violations = {
        table_name
        for table_name in business_tables
        if classifications[table_name] is not True
    }

    actual_composite_fks = _validated_composite_foreign_keys(conn)
    public_table_privileges, public_function_privileges = _public_privilege_counts(
        conn
    )
    jsonb_tables, jsonb_tables_covered = _jsonb_trigger_coverage(conn)
    (
        encrypted_columns,
        encrypted_columns_covered,
        secret_reference_columns,
        secret_reference_columns_covered,
    ) = _protected_text_column_counts(conn)
    append_only_tables, append_only_tables_covered = _append_only_coverage(conn)

    amount_columns, amounts_without_currency = _numeric_semantic_columns(
        conn,
        r"(^|_)amount($|_)",
        r"(^|_)currency(_code)?$",
    )
    amount_allowlist = set(AMOUNT_WITHOUT_CURRENCY_ALLOWLIST)
    quantity_columns, quantities_without_uom = _numeric_semantic_columns(
        conn,
        r"(^|_)quantity($|_)",
        r"(^|_)(uom(_code)?|unit(_code)?)$",
    )
    quantity_allowlist = set(QUANTITY_WITHOUT_UOM_ALLOWLIST)

    violations = {
        "transaction_mode": int(not all(transaction_state)),
        "table_set": len(expected_tables ^ actual_tables),
        "tenantless_classification": len(
            actual_tenantless ^ TENANTLESS_TABLE_ALLOWLIST
        ),
        "nullable_tenant_classification": len(
            actual_nullable_tenant ^ NULLABLE_TENANT_ID_ALLOWLIST
        ),
        "business_tenant_not_null": len(business_tenant_violations),
        "composite_foreign_keys": len(
            REQUIRED_COMPOSITE_FOREIGN_KEYS - actual_composite_fks
        ),
        "spoofed_tenant_guc": _assert_spoofed_guc_is_ignored(conn),
        "public_table_privileges": public_table_privileges,
        "public_function_privileges": public_function_privileges,
        "jsonb_secret_triggers": jsonb_tables - jsonb_tables_covered,
        "ciphertext_checks": encrypted_columns - encrypted_columns_covered,
        "secret_reference_checks": (
            secret_reference_columns - secret_reference_columns_covered
        ),
        "append_only_triggers": append_only_tables - append_only_tables_covered,
        "amount_currency": len(amounts_without_currency - amount_allowlist),
        "amount_allowlist_stale": len(amount_allowlist - amounts_without_currency),
        "quantity_uom": len(quantities_without_uom - quantity_allowlist),
        "quantity_allowlist_stale": len(
            quantity_allowlist - quantities_without_uom
        ),
    }
    if any(violations.values()):
        raise CatalogAuditError(violations)

    return AuditCounts(
        tables=len(actual_tables),
        tenantless_tables=len(actual_tenantless),
        nullable_tenant_tables=len(actual_nullable_tenant),
        tenant_business_tables=len(business_tables),
        composite_foreign_keys=len(REQUIRED_COMPOSITE_FOREIGN_KEYS),
        jsonb_tables=jsonb_tables,
        encrypted_columns=encrypted_columns,
        secret_reference_columns=secret_reference_columns,
        append_only_tables=append_only_tables,
        amount_columns=len(amount_columns),
        amount_exceptions=len(amount_allowlist),
        quantity_columns=len(quantity_columns),
        quantity_exceptions=len(quantity_allowlist),
    )


def main() -> int:
    try:
        modules = _load_sql_modules(_sql_files())
        checksum = _checksum(modules)
        forward_migrations = _load_forward_migrations()
        expected_modules = modules + tuple(
            migration.module for migration in forward_migrations
        )
        expected_tables, _, _ = _expected_catalog(expected_modules)
        with psycopg.connect(settings.database_url) as conn:
            conn.execute("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY")
            conn.execute("SET LOCAL statement_timeout = '2min'")
            _assert_actual_target(conn)
            baseline_counts = _verify(
                conn, modules, checksum, forward_migrations
            )
            audit_counts = _audit_catalog(conn, expected_tables)
            conn.rollback()
    except CatalogAuditError as exc:
        print(exc.render(), file=sys.stderr)
        return 1
    except Exception:
        # Baseline verifier exceptions may contain catalog identifiers.  Keep this
        # standalone audit's output aggregate-only; run apply_etms_schema.py
        # --verify-only separately for DBA diagnostics.
        print("ETMS catalog audit failed: baseline_or_internal_failures=1", file=sys.stderr)
        return 1

    print(
        "ETMS catalog audit passed: "
        f"tables={audit_counts.tables}, "
        f"foreign_keys={baseline_counts['foreign_keys']}, "
        f"checks={baseline_counts['checks']}, "
        f"indexes={baseline_counts['indexes']}, "
        f"triggers={baseline_counts['triggers']}, "
        f"tenantless_tables={audit_counts.tenantless_tables}, "
        f"nullable_tenant_tables={audit_counts.nullable_tenant_tables}, "
        f"tenant_business_tables={audit_counts.tenant_business_tables}, "
        f"composite_foreign_keys={audit_counts.composite_foreign_keys}, "
        f"jsonb_tables={audit_counts.jsonb_tables}, "
        f"encrypted_columns={audit_counts.encrypted_columns}, "
        f"secret_reference_columns={audit_counts.secret_reference_columns}, "
        f"append_only_tables={audit_counts.append_only_tables}, "
        f"amount_columns={audit_counts.amount_columns}, "
        f"amount_exceptions={audit_counts.amount_exceptions}, "
        f"quantity_columns={audit_counts.quantity_columns}, "
        f"quantity_exceptions={audit_counts.quantity_exceptions}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
