"""Apply and verify the DOMS PostgreSQL 11 schema without exposing credentials."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
BACKEND_DIR = REPO_ROOT / "backend"
SQL_DIR = REPO_ROOT / "database" / "doms"
MIGRATION_VERSION = "20260712_01_enterprise_doms"
MIGRATION_DESCRIPTION = (
    "Enterprise DOMS schema: Firebase IAM, omnichannel order capture, orchestration, "
    "payment, fulfillment, returns, settlement, audit, and analytics"
)
REQUIRED_MODULE_NUMBERS = tuple(range(11))
BASELINE_CURRENCY_CODES = ("KRW", "USD", "EUR", "JPY", "CNY")
BASELINE_COUNTRY_CODES = ("KR", "US", "JP", "CN", "DE")
BASELINE_UOM_CODES = ("EA", "KG", "G", "M", "CM", "MM", "L", "ML")
BASELINE_PERMISSION_CODES = (
    "orders.read",
    "orders.create",
    "orders.update",
    "orders.cancel",
    "pricing.override",
    "inventory.read",
    "inventory.reserve",
    "inventory.override",
    "payment.read",
    "payment.capture",
    "payment.refund",
    "risk.review",
    "fulfillment.read",
    "fulfillment.operate",
    "returns.read",
    "returns.approve",
    "workflow.approve",
    "integration.manage",
    "iam.manage",
    "audit.read",
)
BASELINE_SYSTEM_ROLE_CODES = (
    "DOMS_ADMIN",
    "ORDER_MANAGER",
    "CUSTOMER_SERVICE",
    "PAYMENT_OPERATOR",
    "FULFILLMENT_OPERATOR",
    "AUDITOR",
    "INTEGRATION_OPERATOR",
    "READ_ONLY",
)
BASELINE_ORDER_TYPE_CODES = (
    "STANDARD",
    "SUBSCRIPTION",
    "PREORDER",
    "EXCHANGE",
    "REPLACEMENT",
    "INTERNAL",
)
BASELINE_RETENTION_ENTITY_TYPES = (
    "authentication_events",
    "orders",
    "payments",
    "fulfillment",
    "returns",
    "audit_events",
    "customer_pii",
    "integration_messages",
)
ALLOWED_NULLABLE_TENANT_TABLES = (
    "audit_events",
    "charge_codes",
    "code_sets",
    "code_values",
    "data_access_logs",
    "data_quality_rules",
    "data_retention_policies",
    "delivery_methods",
    "exchange_rates",
    "inventory_statuses",
    "job_runs",
    "kpi_definitions",
    "login_events",
    "notification_templates",
    "order_types",
    "payment_terms",
    "reason_codes",
    "role_permissions",
    "roles",
    "scheduled_jobs",
    "sod_rule_conflicts",
    "sod_rules",
    "status_definitions",
    "status_transitions",
    "tax_codes",
    "tax_rates",
)
CRITICAL_TRIGGER_BINDINGS = (
    (
        "auth_identities",
        "trg_validate_auth_identity_owner",
        "validate_auth_identity_owner",
        23,
    ),
    (
        "account_link_requests",
        "trg_validate_account_link_transition",
        "validate_account_link_transition",
        23,
    ),
    (
        "user_sessions",
        "trg_validate_user_session_state",
        "validate_user_session_state",
        23,
    ),
    (
        "tenant_memberships",
        "trg_revoke_sessions_after_membership_change",
        "revoke_sessions_after_principal_change",
        17,
    ),
    ("sales_orders", "trg_20_validate_order_mutation", "validate_sales_order_mutation", 23),
    ("sales_orders", "trg_90_record_order_status", "record_sales_order_status_events", 21),
    (
        "inventory_positions",
        "trg_validate_inventory_position_projection",
        "validate_inventory_position_projection",
        23,
    ),
    (
        "inventory_reservation_lines",
        "trg_project_inventory_reservation_line",
        "project_inventory_reservation_line",
        21,
    ),
    (
        "fulfillment_allocations",
        "trg_project_fulfillment_allocation",
        "project_fulfillment_allocation",
        21,
    ),
    ("payment_intents", "trg_payment_intent_initial_status", "enforce_payment_initial_status", 7),
    ("payment_intents", "trg_payment_intent_ready", "validate_payment_intent_ready", 23),
    (
        "payment_authorizations",
        "trg_payment_authorization_limit",
        "enforce_payment_authorization_limit",
        23,
    ),
    ("payment_captures", "trg_payment_capture_limit", "enforce_payment_capture_limit", 23),
    ("payment_refunds", "trg_payment_refund_limit", "enforce_payment_refund_limit", 23),
    (
        "payment_refund_requests",
        "trg_payment_refund_request_integrity",
        "validate_payment_refund_request",
        23,
    ),
    (
        "gift_card_ledger_entries",
        "trg_gift_card_ledger_apply",
        "apply_gift_card_ledger_entry",
        7,
    ),
    (
        "fulfillment_order_lines",
        "trg_fulfillment_line_quantity",
        "validate_fulfillment_order_line",
        23,
    ),
    (
        "shipment_lines",
        "trg_shipment_line_sync_fulfillment",
        "sync_fulfillment_line_shipping_quantities",
        21,
    ),
    (
        "rma_authorization_lines",
        "trg_doms_rma_line_validate",
        "validate_rma_authorization_line",
        23,
    ),
    (
        "return_receipt_lines",
        "trg_doms_return_receipt_line_validate",
        "validate_return_receipt_line",
        7,
    ),
    (
        "return_refund_calculation_lines",
        "trg_doms_return_refund_line_validate",
        "validate_return_refund_calculation_line",
        23,
    ),
    (
        "journal_entries",
        "trg_validate_journal_entry_posting",
        "validate_journal_entry_posting",
        23,
    ),
    (
        "data_quality_results",
        "trg_validate_data_quality_result_lifecycle",
        "validate_data_quality_result_lifecycle",
        23,
    ),
    (
        "data_disposal_results",
        "trg_prevent_disposal_under_legal_hold",
        "prevent_disposal_under_legal_hold",
        23,
    ),
)
TABLE_PATTERN = re.compile(r"^CREATE TABLE IF NOT EXISTS doms\.([a-z0-9_]+)", re.MULTILINE)
INDEX_PATTERN = re.compile(
    r"^CREATE (?:UNIQUE )?INDEX IF NOT EXISTS ([a-z0-9_]+)", re.MULTILINE
)
TRIGGER_PATTERN = re.compile(
    r"^\s*CREATE (?:CONSTRAINT )?TRIGGER\s+([a-z0-9_]+)\s+"
    r"[\s\S]*?\bON\s+doms\.([a-z0-9_]+)",
    re.MULTILINE,
)


@dataclass(frozen=True)
class SqlModule:
    """Immutable SQL input used for checksum, execution, and verification."""

    path: Path
    raw: bytes
    text: str

sys.path.insert(0, str(BACKEND_DIR))

import psycopg  # noqa: E402
from app.settings import (  # noqa: E402
    REQUIRED_POSTGRES_DB,
    REQUIRED_POSTGRES_HOST,
    REQUIRED_POSTGRES_USER,
    settings,
)


def _assert_actual_target(
    conn: psycopg.Connection,
) -> tuple[str, str, str, str, int]:
    row = conn.execute(
        """
        SELECT current_database(), current_user, session_user,
               COALESCE(host(inet_server_addr()), ''),
               COALESCE(inet_server_port(), 0)
        """
    ).fetchone()
    if row is None:
        raise RuntimeError("Unable to verify the actual PostgreSQL target")
    database_name, database_user, session_database_user, server_address, server_port = row
    if (
        database_name != REQUIRED_POSTGRES_DB
        or database_user != REQUIRED_POSTGRES_USER
        or session_database_user != REQUIRED_POSTGRES_USER
        or server_address != REQUIRED_POSTGRES_HOST
        or server_port != 5432
    ):
        raise RuntimeError(
            "Refusing DOMS DDL on the actual PostgreSQL target outside "
            f"{REQUIRED_POSTGRES_HOST}:5432/{REQUIRED_POSTGRES_DB} "
            f"as {REQUIRED_POSTGRES_USER}."
        )
    return (
        database_name,
        database_user,
        session_database_user,
        server_address,
        server_port,
    )


def _sql_files() -> list[Path]:
    files = sorted(SQL_DIR.glob("[0-9][0-9]_*.sql"))
    if not files:
        raise RuntimeError(f"No DOMS SQL modules found under {SQL_DIR}")

    modules: dict[int, Path] = {}
    for path in files:
        match = re.fullmatch(r"(0[0-9]|10)_[a-z0-9_]+\.sql", path.name)
        if match is None:
            raise RuntimeError(
                f"Unexpected numbered DOMS SQL module {path.name}; expected only 00 through 10"
            )
        module_number = int(match.group(1))
        if module_number in modules:
            raise RuntimeError(
                f"Duplicate DOMS SQL module prefix {module_number:02d}: "
                f"{modules[module_number].name}, {path.name}"
            )
        modules[module_number] = path

    missing = sorted(set(REQUIRED_MODULE_NUMBERS) - set(modules))
    unexpected = sorted(set(modules) - set(REQUIRED_MODULE_NUMBERS))
    if missing or unexpected:
        details: list[str] = []
        if missing:
            details.append("missing " + ", ".join(f"{number:02d}" for number in missing))
        if unexpected:
            details.append(
                "unexpected " + ", ".join(f"{number:02d}" for number in unexpected)
            )
        raise RuntimeError("DOMS SQL module set is invalid: " + "; ".join(details))
    return files


def _load_sql_modules(files: list[Path]) -> tuple[SqlModule, ...]:
    modules: list[SqlModule] = []
    for path in files:
        raw = path.read_bytes()
        modules.append(SqlModule(path=path, raw=raw, text=raw.decode("utf-8")))
    return tuple(modules)


def _checksum(modules: tuple[SqlModule, ...]) -> str:
    digest = hashlib.sha256()
    for module in modules:
        digest.update(module.path.name.encode("utf-8"))
        digest.update(b"\0")
        digest.update(module.raw)
        digest.update(b"\0")
    return digest.hexdigest()


def _normalize_fingerprint_value(value: object) -> object:
    if value is None or isinstance(value, (bool, int, float)):
        return value
    if isinstance(value, bytes):
        return value.hex()
    if isinstance(value, (list, tuple)):
        return [_normalize_fingerprint_value(item) for item in value]
    if isinstance(value, dict):
        return {
            str(key): _normalize_fingerprint_value(item)
            for key, item in sorted(value.items(), key=lambda pair: str(pair[0]))
        }
    return str(value).replace("\r\n", "\n").replace("\r", "\n")


def _stable_fingerprint(
    format_version: str,
    sections: list[tuple[str, tuple[str, ...], list[tuple[object, ...]]]],
) -> str:
    normalized_sections: list[dict[str, object]] = []
    for section_name, columns, rows in sections:
        normalized_rows: list[list[object]] = []
        for row in rows:
            if len(row) != len(columns):
                raise RuntimeError(
                    f"Fingerprint section {section_name} returned {len(row)} values "
                    f"for {len(columns)} columns"
                )
            normalized_rows.append(
                [_normalize_fingerprint_value(value) for value in row]
            )
        normalized_rows.sort(
            key=lambda row: json.dumps(
                row, ensure_ascii=False, sort_keys=True, separators=(",", ":")
            )
        )
        normalized_sections.append(
            {"name": section_name, "columns": list(columns), "rows": normalized_rows}
        )
    normalized_sections.sort(key=lambda section: str(section["name"]))
    payload = json.dumps(
        {"format": format_version, "sections": normalized_sections},
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def _catalog_fingerprint(conn: psycopg.Connection) -> str:
    conn.execute("SET LOCAL search_path = pg_catalog")
    sections: list[tuple[str, tuple[str, ...], list[tuple[object, ...]]]] = []

    sections.append(
        (
            "schema",
            ("schema_name", "owner"),
            conn.execute(
                """
                SELECT n.nspname, pg_get_userbyid(n.nspowner)
                FROM pg_namespace n
                WHERE n.nspname = 'doms'
                """
            ).fetchall(),
        )
    )
    sections.append(
        (
            "relations",
            (
                "name", "kind", "persistence", "owner", "rls", "force_rls",
                "replica_identity", "options", "view_definition",
            ),
            conn.execute(
                """
                SELECT c.relname, c.relkind::text, c.relpersistence::text,
                       pg_get_userbyid(c.relowner), c.relrowsecurity,
                       c.relforcerowsecurity, c.relreplident::text,
                       c.reloptions::text,
                       CASE WHEN c.relkind IN ('v','m') THEN pg_get_viewdef(c.oid, true) END
                FROM pg_class c
                JOIN pg_namespace n ON n.oid = c.relnamespace
                WHERE n.nspname = 'doms'
                  AND c.relkind IN ('r','p','v','m','S','f')
                """
            ).fetchall(),
        )
    )
    sections.append(
        (
            "columns",
            (
                "table", "position", "name", "type", "not_null", "default", "identity",
            ),
            conn.execute(
                """
                SELECT c.relname, a.attnum::text, a.attname,
                       format_type(a.atttypid, a.atttypmod), a.attnotnull,
                       pg_get_expr(d.adbin, d.adrelid), a.attidentity::text
                FROM pg_attribute a
                JOIN pg_class c ON c.oid = a.attrelid
                JOIN pg_namespace n ON n.oid = c.relnamespace
                LEFT JOIN pg_attrdef d
                  ON d.adrelid = a.attrelid AND d.adnum = a.attnum
                WHERE n.nspname = 'doms'
                  AND c.relkind IN ('r','p','v','m','f')
                  AND a.attnum > 0 AND NOT a.attisdropped
                """
            ).fetchall(),
        )
    )
    sections.append(
        (
            "constraints",
            (
                "table", "name", "type", "deferrable", "deferred", "validated", "definition",
            ),
            conn.execute(
                """
                SELECT c.relname, con.conname, con.contype::text,
                       con.condeferrable, con.condeferred, con.convalidated,
                       pg_get_constraintdef(con.oid, true)
                FROM pg_constraint con
                JOIN pg_class c ON c.oid = con.conrelid
                JOIN pg_namespace n ON n.oid = c.relnamespace
                WHERE n.nspname = 'doms'
                """
            ).fetchall(),
        )
    )
    sections.append(
        (
            "indexes",
            ("table", "name", "primary", "unique", "valid", "ready", "definition"),
            conn.execute(
                """
                SELECT parent.relname, index_row.relname, idx.indisprimary,
                       idx.indisunique, idx.indisvalid, idx.indisready,
                       pg_get_indexdef(index_row.oid)
                FROM pg_index idx
                JOIN pg_class parent ON parent.oid = idx.indrelid
                JOIN pg_class index_row ON index_row.oid = idx.indexrelid
                JOIN pg_namespace n ON n.oid = parent.relnamespace
                WHERE n.nspname = 'doms'
                """
            ).fetchall(),
        )
    )
    sections.append(
        (
            "triggers",
            ("table", "name", "enabled", "definition", "function"),
            conn.execute(
                """
                SELECT c.relname, t.tgname, t.tgenabled::text,
                       pg_get_triggerdef(t.oid, true),
                       p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')'
                FROM pg_trigger t
                JOIN pg_class c ON c.oid = t.tgrelid
                JOIN pg_namespace n ON n.oid = c.relnamespace
                JOIN pg_proc p ON p.oid = t.tgfoid
                WHERE n.nspname = 'doms' AND NOT t.tgisinternal
                """
            ).fetchall(),
        )
    )
    sections.append(
        (
            "functions",
            (
                "name", "arguments", "return_type", "owner", "language", "volatility",
                "security_definer", "config", "definition",
            ),
            conn.execute(
                """
                SELECT p.proname, pg_get_function_identity_arguments(p.oid),
                       pg_get_function_result(p.oid), pg_get_userbyid(p.proowner),
                       l.lanname, p.provolatile::text,
                       p.prosecdef, p.proconfig::text,
                       pg_get_functiondef(p.oid)
                FROM pg_proc p
                JOIN pg_namespace n ON n.oid = p.pronamespace
                JOIN pg_language l ON l.oid = p.prolang
                WHERE n.nspname = 'doms'
                """
            ).fetchall(),
        )
    )
    sections.append(
        (
            "policies",
            ("table", "name", "command", "permissive", "roles", "using", "check"),
            conn.execute(
                """
                SELECT c.relname, p.polname, p.polcmd::text, p.polpermissive,
                       p.polroles::text, pg_get_expr(p.polqual, p.polrelid),
                       pg_get_expr(p.polwithcheck, p.polrelid)
                FROM pg_policy p
                JOIN pg_class c ON c.oid = p.polrelid
                JOIN pg_namespace n ON n.oid = c.relnamespace
                WHERE n.nspname = 'doms'
                """
            ).fetchall(),
        )
    )
    sections.append(
        (
            "default_privileges",
            ("owner", "schema", "object_type", "acl"),
            conn.execute(
                """
                SELECT pg_get_userbyid(d.defaclrole), n.nspname,
                       d.defaclobjtype::text, d.defaclacl::text
                FROM pg_default_acl d
                JOIN pg_namespace n ON n.oid = d.defaclnamespace
                WHERE n.nspname = 'doms'
                """
            ).fetchall(),
        )
    )
    return _stable_fingerprint("doms-catalog-v1", sections)


def _baseline_seed_fingerprint(conn: psycopg.Connection) -> str:
    def rows(query: str, codes: tuple[str, ...]) -> list[tuple[object, ...]]:
        return conn.execute(query, (list(codes),)).fetchall()

    sections: list[tuple[str, tuple[str, ...], list[tuple[object, ...]]]] = [
        (
            "currencies",
            ("code", "name", "numeric_code", "digits", "increment", "active"),
            rows(
                """
                SELECT currency_code::text, currency_name, numeric_code::text,
                       fraction_digits::text, rounding_increment::text, is_active::text
                FROM doms.currencies WHERE currency_code = ANY(%s::text[])
                """,
                BASELINE_CURRENCY_CODES,
            ),
        ),
        (
            "countries",
            (
                "code", "code3", "numeric_code", "name_en", "name_local",
                "currency", "active",
            ),
            rows(
                """
                SELECT country_code::text, country_code3::text, numeric_code::text,
                       country_name_en, country_name_local,
                       default_currency_code::text, is_active::text
                FROM doms.countries WHERE country_code = ANY(%s::text[])
                """,
                BASELINE_COUNTRY_CODES,
            ),
        ),
        (
            "units",
            ("code", "name", "dimension", "factor", "decimals", "active"),
            rows(
                """
                SELECT uom_code, uom_name, dimension, si_factor::text,
                       decimal_places::text, is_active::text
                FROM doms.units_of_measure WHERE uom_code = ANY(%s::text[])
                """,
                BASELINE_UOM_CODES,
            ),
        ),
        (
            "permissions",
            (
                "code", "name", "module", "action", "description",
                "sensitive", "active",
            ),
            rows(
                """
                SELECT permission_code, permission_name, module_code, action_code,
                       description, is_sensitive::text, is_active::text
                FROM doms.permissions WHERE permission_code = ANY(%s::text[])
                """,
                BASELINE_PERMISSION_CODES,
            ),
        ),
        (
            "system_roles",
            ("code", "name", "description", "system", "active"),
            rows(
                """
                SELECT role_code, role_name, description,
                       is_system_role::text, is_active::text
                FROM doms.roles
                WHERE tenant_id IS NULL AND role_code = ANY(%s::text[])
                """,
                BASELINE_SYSTEM_ROLE_CODES,
            ),
        ),
        (
            "order_types",
            (
                "code", "name", "lifecycle", "payment", "fulfillment",
                "partial", "backorder", "preorder", "active",
            ),
            rows(
                """
                SELECT order_type_code, order_type_name, lifecycle_model,
                       requires_payment::text, requires_fulfillment::text,
                       allows_partial_fulfillment::text, allows_backorder::text,
                       allows_preorder::text, is_active::text
                FROM doms.order_types
                WHERE tenant_id IS NULL AND order_type_code = ANY(%s::text[])
                """,
                BASELINE_ORDER_TYPE_CODES,
            ),
        ),
        (
            "retention",
            ("entity", "days", "anonymize_days", "strategy", "basis", "active"),
            rows(
                """
                SELECT entity_type, retention_days::text, anonymize_after_days::text,
                       purge_strategy, legal_basis, is_active::text
                FROM doms.data_retention_policies
                WHERE tenant_id IS NULL AND entity_type = ANY(%s::text[])
                """,
                BASELINE_RETENTION_ENTITY_TYPES,
            ),
        ),
        (
            "system_role_permissions",
            ("role", "permission", "active"),
            conn.execute(
                """
                SELECT role_row.role_code, permission_row.permission_code,
                       (role_permission.revoked_at IS NULL)::text
                FROM doms.role_permissions role_permission
                JOIN doms.roles role_row ON role_row.id = role_permission.role_id
                JOIN doms.permissions permission_row
                  ON permission_row.id = role_permission.permission_id
                WHERE role_permission.tenant_id IS NULL
                  AND role_row.tenant_id IS NULL
                  AND role_row.role_code = ANY(%s::text[])
                """,
                (list(BASELINE_SYSTEM_ROLE_CODES),),
            ).fetchall(),
        ),
        (
            "status_definitions",
            (
                "entity", "code", "name", "category", "terminal",
                "success", "sort", "attributes", "active",
            ),
            conn.execute(
                """
                SELECT entity_type, status_code, status_name, category,
                       terminal_status::text, success_status::text,
                       sort_order::text, attributes, is_active::text
                FROM doms.status_definitions
                WHERE tenant_id IS NULL
                  AND entity_type IN ('SALES_ORDER','PAYMENT','FULFILLMENT','RETURN')
                """
            ).fetchall(),
        ),
        (
            "reason_codes",
            ("group", "code", "name", "note", "approval", "active"),
            conn.execute(
                """
                SELECT reason_group, reason_code, reason_name,
                       requires_note::text, requires_approval::text, is_active::text
                FROM doms.reason_codes
                WHERE tenant_id IS NULL
                  AND reason_group IN (
                      'ORDER_CANCEL','ORDER_CHANGE','PAYMENT','FULFILLMENT','RETURN','RISK'
                  )
                """
            ).fetchall(),
        ),
    ]
    return _stable_fingerprint("doms-baseline-seeds-v1", sections)


def _expected_catalog(
    modules: tuple[SqlModule, ...],
) -> tuple[set[str], set[str], set[tuple[str, str]]]:
    sql = "\n".join(module.text for module in modules)
    return (
        set(TABLE_PATTERN.findall(sql)),
        set(INDEX_PATTERN.findall(sql)),
        set(TRIGGER_PATTERN.findall(sql)),
    )


def _configured_append_only_tables(modules: tuple[SqlModule, ...]) -> set[str]:
    operations_sql = next(
        module.text
        for module in modules
        if module.path.name.startswith("10_operations_indexes_seed")
    )
    start_marker = "-- Strict append-only records."
    end_marker = "-- Message payloads and routing identity"
    if start_marker not in operations_sql or end_marker not in operations_sql:
        raise RuntimeError("Unable to locate the DOMS append-only configuration markers")
    configured_block = operations_sql.split(start_marker, 1)[1].split(end_marker, 1)[0]
    table_names = set(re.findall(r"'([a-z][a-z0-9_]*)'", configured_block))
    if not table_names:
        raise RuntimeError("The DOMS append-only table list is empty")
    return table_names


def _assert_baseline_seed_presence(conn: psycopg.Connection) -> None:
    checks: tuple[tuple[str, str, tuple[str, ...]], ...] = (
        (
            "currencies",
            "SELECT currency_code::text FROM doms.currencies WHERE currency_code = ANY(%s::text[])",
            BASELINE_CURRENCY_CODES,
        ),
        (
            "countries",
            "SELECT country_code::text FROM doms.countries WHERE country_code = ANY(%s::text[])",
            BASELINE_COUNTRY_CODES,
        ),
        (
            "units of measure",
            "SELECT uom_code FROM doms.units_of_measure WHERE uom_code = ANY(%s::text[])",
            BASELINE_UOM_CODES,
        ),
        (
            "permissions",
            "SELECT permission_code FROM doms.permissions WHERE permission_code = ANY(%s::text[])",
            BASELINE_PERMISSION_CODES,
        ),
        (
            "system roles",
            "SELECT role_code FROM doms.roles WHERE tenant_id IS NULL AND role_code = ANY(%s::text[])",
            BASELINE_SYSTEM_ROLE_CODES,
        ),
        (
            "order types",
            "SELECT order_type_code FROM doms.order_types WHERE tenant_id IS NULL AND order_type_code = ANY(%s::text[])",
            BASELINE_ORDER_TYPE_CODES,
        ),
        (
            "retention policies",
            "SELECT entity_type FROM doms.data_retention_policies WHERE tenant_id IS NULL AND entity_type = ANY(%s::text[])",
            BASELINE_RETENTION_ENTITY_TYPES,
        ),
    )
    for label, query, expected in checks:
        actual = {row[0] for row in conn.execute(query, (list(expected),)).fetchall()}
        missing = sorted(set(expected) - actual)
        if missing:
            raise RuntimeError(f"DOMS baseline {label} are missing: {', '.join(missing)}")

    status_count = conn.execute(
        """
        SELECT count(*) FROM doms.status_definitions
        WHERE tenant_id IS NULL
          AND entity_type IN ('SALES_ORDER','PAYMENT','FULFILLMENT','RETURN')
        """
    ).fetchone()[0]
    reason_count = conn.execute(
        """
        SELECT count(*) FROM doms.reason_codes
        WHERE tenant_id IS NULL
          AND reason_group IN (
              'ORDER_CANCEL','ORDER_CHANGE','PAYMENT','FULFILLMENT','RETURN','RISK'
          )
        """
    ).fetchone()[0]
    role_permission_count = conn.execute(
        """
        SELECT count(*)
        FROM doms.role_permissions role_permission
        JOIN doms.roles role_row ON role_row.id = role_permission.role_id
        WHERE role_permission.tenant_id IS NULL
          AND role_row.tenant_id IS NULL
          AND role_row.role_code = ANY(%s::text[])
          AND role_permission.revoked_at IS NULL
        """,
        (list(BASELINE_SYSTEM_ROLE_CODES),),
    ).fetchone()[0]
    if status_count != 36:
        raise RuntimeError(f"Expected 36 global DOMS status definitions, found {status_count}")
    if reason_count != 32:
        raise RuntimeError(f"Expected 32 global DOMS reason codes, found {reason_count}")
    if role_permission_count < 1:
        raise RuntimeError("DOMS system roles have no active baseline permission grants")


def _verify(
    conn: psycopg.Connection,
    modules: tuple[SqlModule, ...],
    expected_checksum: str,
) -> dict[str, int | str]:
    _assert_actual_target(conn)
    row = conn.execute(
        """
        SELECT
            current_database(),
            current_user,
            current_setting('server_version'),
            current_setting('server_version_num')::integer
        """
    ).fetchone()
    if row is None:
        raise RuntimeError("Unable to read PostgreSQL server metadata")

    database_name, database_user, server_version, server_version_num = row
    if not 110000 <= server_version_num < 120000:
        raise RuntimeError(
            f"DOMS migration is pinned to PostgreSQL 11; server reports {server_version}"
        )

    schema_owner = conn.execute(
        """
        SELECT pg_get_userbyid(nspowner)
        FROM pg_namespace
        WHERE nspname = 'doms'
        """
    ).fetchone()
    if schema_owner is None:
        raise RuntimeError("doms schema does not exist after migration")
    if schema_owner[0] != database_user:
        raise RuntimeError(
            f"doms schema owner is {schema_owner[0]!r}, expected migration owner {database_user!r}"
        )

    migration_role_flags = conn.execute(
        "SELECT rolsuper, rolbypassrls FROM pg_roles WHERE rolname = current_user"
    ).fetchone()
    if migration_role_flags is None or migration_role_flags[0] or migration_role_flags[1]:
        raise RuntimeError("DOMS migration owner must be NOSUPERUSER and NOBYPASSRLS")

    wrong_owner_count = conn.execute(
        """
        SELECT count(*)
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'doms'
          AND c.relkind IN ('r','p','v','m','S','f')
          AND pg_get_userbyid(c.relowner) <> current_user
        """
    ).fetchone()[0]
    if wrong_owner_count:
        raise RuntimeError(f"Found {wrong_owner_count} DOMS relations owned by another role")

    wrong_function_owner_count = conn.execute(
        """
        SELECT count(*)
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'doms'
          AND pg_get_userbyid(p.proowner) <> current_user
        """
    ).fetchone()[0]
    if wrong_function_owner_count:
        raise RuntimeError(
            f"Found {wrong_function_owner_count} DOMS functions owned by another role"
        )

    table_count = conn.execute(
        """
        SELECT count(*)
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'doms' AND c.relkind = 'r'
        """
    ).fetchone()[0]
    fk_count = conn.execute(
        """
        SELECT count(*)
        FROM pg_constraint c
        JOIN pg_namespace n ON n.oid = c.connamespace
        WHERE n.nspname = 'doms' AND c.contype = 'f'
        """
    ).fetchone()[0]
    check_count = conn.execute(
        """
        SELECT count(*)
        FROM pg_constraint c
        JOIN pg_namespace n ON n.oid = c.connamespace
        WHERE n.nspname = 'doms' AND c.contype = 'c'
        """
    ).fetchone()[0]
    index_count = conn.execute(
        """
        SELECT count(*)
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'doms' AND c.relkind = 'i'
        """
    ).fetchone()[0]
    trigger_count = conn.execute(
        """
        SELECT count(*)
        FROM pg_trigger t
        JOIN pg_class c ON c.oid = t.tgrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'doms' AND NOT t.tgisinternal
        """
    ).fetchone()[0]
    tenant_table_count, rls_table_count, force_rls_table_count = conn.execute(
        """
        SELECT
            count(*) FILTER (WHERE tenant_column.attname IS NOT NULL),
            count(*) FILTER (WHERE tenant_column.attname IS NOT NULL AND c.relrowsecurity),
            count(*) FILTER (WHERE tenant_column.attname IS NOT NULL AND c.relforcerowsecurity)
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        LEFT JOIN pg_attribute tenant_column
          ON tenant_column.attrelid = c.oid
         AND tenant_column.attname = 'tenant_id'
         AND NOT tenant_column.attisdropped
        WHERE n.nspname = 'doms' AND c.relkind = 'r'
        """
    ).fetchone()

    expected_tables, expected_indexes, expected_triggers = _expected_catalog(modules)
    existing_tables = {
        value[0]
        for value in conn.execute(
            """
            SELECT c.relname
            FROM pg_class c
            JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'doms' AND c.relkind = 'r'
            """
        ).fetchall()
    }
    missing_tables = sorted(expected_tables - existing_tables)
    if missing_tables:
        raise RuntimeError(f"Expected DOMS tables are missing: {', '.join(missing_tables)}")

    existing_indexes = {
        value[0]
        for value in conn.execute(
            """
            SELECT c.relname
            FROM pg_class c
            JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'doms' AND c.relkind = 'i'
            """
        ).fetchall()
    }
    missing_indexes = sorted(expected_indexes - existing_indexes)
    if missing_indexes:
        raise RuntimeError(f"Expected DOMS indexes are missing: {', '.join(missing_indexes)}")

    existing_triggers = {
        (value[0], value[1])
        for value in conn.execute(
            """
            SELECT DISTINCT t.tgname, c.relname
            FROM pg_trigger t
            JOIN pg_class c ON c.oid = t.tgrelid
            JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'doms' AND NOT t.tgisinternal
            """
        ).fetchall()
    }
    missing_triggers = sorted(expected_triggers - existing_triggers)
    if missing_triggers:
        names = ", ".join(f"{table}.{trigger}" for trigger, table in missing_triggers)
        raise RuntimeError(f"Expected DOMS triggers are missing: {names}")

    invalid_fk_count = conn.execute(
        """
        SELECT count(*)
        FROM pg_constraint c
        JOIN pg_namespace n ON n.oid = c.connamespace
        WHERE n.nspname = 'doms' AND c.contype = 'f' AND NOT c.convalidated
        """
    ).fetchone()[0]
    if invalid_fk_count:
        raise RuntimeError(f"Found {invalid_fk_count} unvalidated foreign keys")
    invalid_check_count = conn.execute(
        """
        SELECT count(*)
        FROM pg_constraint c
        JOIN pg_namespace n ON n.oid = c.connamespace
        WHERE n.nspname = 'doms' AND c.contype = 'c' AND NOT c.convalidated
        """
    ).fetchone()[0]
    if invalid_check_count:
        raise RuntimeError(f"Found {invalid_check_count} unvalidated check constraints")
    if tenant_table_count != rls_table_count:
        raise RuntimeError(
            f"RLS is missing on {tenant_table_count - rls_table_count} tenant-scoped tables"
        )
    if tenant_table_count != force_rls_table_count:
        raise RuntimeError(
            "FORCE ROW LEVEL SECURITY is missing on "
            f"{tenant_table_count - force_rls_table_count} tenant-scoped tables"
        )

    missing_policy_count = conn.execute(
        """
        SELECT count(*)
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        JOIN pg_attribute a
          ON a.attrelid = c.oid AND a.attname = 'tenant_id' AND NOT a.attisdropped
        WHERE n.nspname = 'doms' AND c.relkind = 'r'
          AND (
              NOT EXISTS (SELECT 1 FROM pg_policy p WHERE p.polrelid = c.oid AND p.polname = 'tenant_select')
              OR NOT EXISTS (SELECT 1 FROM pg_policy p WHERE p.polrelid = c.oid AND p.polname = 'tenant_modify')
          )
        """
    ).fetchone()[0]
    if missing_policy_count:
        raise RuntimeError(f"Tenant policies are missing on {missing_policy_count} tables")

    invalid_policy_shape_count = conn.execute(
        """
        SELECT count(*)
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        JOIN pg_attribute a
          ON a.attrelid = c.oid AND a.attname = 'tenant_id' AND NOT a.attisdropped
        WHERE n.nspname = 'doms' AND c.relkind = 'r'
          AND NOT (
              (SELECT count(*) FROM pg_policy p WHERE p.polrelid = c.oid) = 2
              AND EXISTS (
                  SELECT 1 FROM pg_policy p
                  WHERE p.polrelid = c.oid AND p.polname = 'tenant_select'
                    AND p.polcmd = 'r' AND p.polpermissive
                    AND p.polroles = ARRAY[0::oid]
                    AND pg_get_expr(p.polqual, p.polrelid)
                        LIKE '%%doms.current_tenant_id()%%'
              )
              AND EXISTS (
                  SELECT 1 FROM pg_policy p
                  WHERE p.polrelid = c.oid AND p.polname = 'tenant_modify'
                    AND p.polcmd = '*' AND p.polpermissive
                    AND p.polroles = ARRAY[0::oid]
                    AND pg_get_expr(p.polqual, p.polrelid)
                        LIKE '%%doms.current_tenant_id()%%'
                    AND pg_get_expr(p.polwithcheck, p.polrelid)
                        LIKE '%%doms.current_tenant_id()%%'
              )
          )
        """
    ).fetchone()[0]
    if invalid_policy_shape_count:
        raise RuntimeError(
            f"Found {invalid_policy_shape_count} tenant tables with unsafe policy shape"
        )

    unexpected_nullable_tenant_tables = [
        row[0]
        for row in conn.execute(
            """
            SELECT c.relname
            FROM pg_class c
            JOIN pg_namespace n ON n.oid = c.relnamespace
            JOIN pg_attribute a
              ON a.attrelid = c.oid AND a.attname = 'tenant_id'
             AND NOT a.attisdropped
            WHERE n.nspname = 'doms' AND c.relkind = 'r'
              AND NOT a.attnotnull
              AND NOT (c.relname = ANY(%s::text[]))
            ORDER BY c.relname
            """,
            (list(ALLOWED_NULLABLE_TENANT_TABLES),),
        ).fetchall()
    ]
    if unexpected_nullable_tenant_tables:
        raise RuntimeError(
            "Unexpected nullable tenant_id columns: "
            + ", ".join(unexpected_nullable_tenant_tables)
        )

    missing_tenant_immutability_count = conn.execute(
        """
        SELECT count(*)
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        JOIN pg_attribute a
          ON a.attrelid = c.oid AND a.attname = 'tenant_id' AND NOT a.attisdropped
        WHERE n.nspname = 'doms' AND c.relkind = 'r'
          AND NOT EXISTS (
              SELECT 1 FROM pg_trigger t
              WHERE t.tgrelid = c.oid AND NOT t.tgisinternal
                AND t.tgname = 'trg_tenant_immutable'
                AND t.tgfoid = 'doms.prevent_tenant_change()'::regprocedure
          )
        """
    ).fetchone()[0]
    if missing_tenant_immutability_count:
        raise RuntimeError(
            "tenant_id immutability trigger is missing on "
            f"{missing_tenant_immutability_count} tables"
        )

    missing_touch_trigger_count = conn.execute(
        """
        SELECT count(*)
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'doms' AND c.relkind = 'r'
          AND EXISTS (
              SELECT 1 FROM pg_attribute a
              WHERE a.attrelid = c.oid AND a.attname = 'row_version' AND NOT a.attisdropped
          )
          AND EXISTS (
              SELECT 1 FROM pg_attribute a
              WHERE a.attrelid = c.oid AND a.attname = 'updated_at' AND NOT a.attisdropped
          )
          AND NOT EXISTS (
              SELECT 1 FROM pg_trigger t
              WHERE t.tgrelid = c.oid AND NOT t.tgisinternal
                AND t.tgname = 'trg_touch_row'
                AND t.tgfoid = 'doms.touch_row()'::regprocedure
          )
        """
    ).fetchone()[0]
    if missing_touch_trigger_count:
        raise RuntimeError(
            f"Optimistic-lock touch trigger is missing on {missing_touch_trigger_count} tables"
        )

    disabled_user_trigger_count = conn.execute(
        """
        SELECT count(*)
        FROM pg_trigger trigger_row
        JOIN pg_class relation ON relation.oid = trigger_row.tgrelid
        JOIN pg_namespace namespace_row ON namespace_row.oid = relation.relnamespace
        WHERE namespace_row.nspname = 'doms'
          AND NOT trigger_row.tgisinternal
          AND trigger_row.tgenabled = 'D'
        """
    ).fetchone()[0]
    if disabled_user_trigger_count:
        raise RuntimeError(f"Found {disabled_user_trigger_count} disabled DOMS triggers")

    invalid_critical_triggers: list[str] = []
    for table_name, trigger_name, function_name, trigger_type in CRITICAL_TRIGGER_BINDINGS:
        binding = conn.execute(
            """
            SELECT trigger_row.tgenabled, trigger_row.tgtype::integer,
                   function_row.proname
            FROM pg_trigger trigger_row
            JOIN pg_class relation ON relation.oid = trigger_row.tgrelid
            JOIN pg_namespace relation_namespace
              ON relation_namespace.oid = relation.relnamespace
            JOIN pg_proc function_row ON function_row.oid = trigger_row.tgfoid
            JOIN pg_namespace function_namespace
              ON function_namespace.oid = function_row.pronamespace
            WHERE relation_namespace.nspname = 'doms'
              AND relation.relname = %s
              AND trigger_row.tgname = %s
              AND NOT trigger_row.tgisinternal
              AND function_namespace.nspname = 'doms'
            """,
            (table_name, trigger_name),
        ).fetchone()
        if (
            binding is None
            or binding[0] not in ("O", "A")
            or binding[1] != trigger_type
            or binding[2] != function_name
        ):
            invalid_critical_triggers.append(f"{table_name}.{trigger_name}")
    if invalid_critical_triggers:
        raise RuntimeError(
            "Critical integrity trigger bindings are missing or unsafe: "
            + ", ".join(invalid_critical_triggers)
        )

    missing_same_tenant_guard_count = conn.execute(
        """
        SELECT count(*)
        FROM pg_constraint con
        JOIN pg_class child_relation ON child_relation.oid = con.conrelid
        JOIN pg_namespace child_namespace ON child_namespace.oid = child_relation.relnamespace
        JOIN pg_class parent_relation ON parent_relation.oid = con.confrelid
        JOIN pg_namespace parent_namespace ON parent_namespace.oid = parent_relation.relnamespace
        JOIN pg_attribute child_tenant
          ON child_tenant.attrelid = con.conrelid
         AND child_tenant.attname = 'tenant_id' AND NOT child_tenant.attisdropped
        JOIN pg_attribute parent_tenant
          ON parent_tenant.attrelid = con.confrelid
         AND parent_tenant.attname = 'tenant_id' AND NOT parent_tenant.attisdropped
        JOIN pg_attribute parent_key
          ON parent_key.attrelid = con.confrelid
         AND parent_key.attnum = con.confkey[1]
        WHERE con.contype = 'f'
          AND child_namespace.nspname = 'doms'
          AND parent_namespace.nspname = 'doms'
          AND array_length(con.conkey, 1) = 1
          AND parent_key.attname = 'id'
          AND con.conkey[1] <> child_tenant.attnum
          AND NOT EXISTS (
              SELECT 1
              FROM pg_constraint companion
              WHERE companion.contype = 'f'
                AND companion.conrelid = con.conrelid
                AND companion.confrelid = con.confrelid
                AND array_length(companion.conkey, 1) >= 2
                AND companion.conkey[1] = child_tenant.attnum
                AND con.conkey[1] = ANY(companion.conkey)
          )
          AND NOT EXISTS (
              SELECT 1
              FROM pg_trigger trigger_row
              WHERE trigger_row.tgrelid = con.conrelid
                AND NOT trigger_row.tgisinternal
                AND trigger_row.tgenabled IN ('O','A')
                AND trigger_row.tgname = 'trg_tenant_fk_' || substr(
                    md5(child_namespace.nspname || '.' || child_relation.relname || '.' || con.conname),
                    1, 12
                )
                AND trigger_row.tgfoid = 'doms.enforce_same_tenant_fk()'::regprocedure
          )
        """
    ).fetchone()[0]
    if missing_same_tenant_guard_count:
        raise RuntimeError(
            f"Found {missing_same_tenant_guard_count} tenant foreign keys without a same-tenant guard"
        )

    unindexed_fk_count = conn.execute(
        """
        SELECT count(*)
        FROM pg_constraint con
        JOIN pg_class rel ON rel.oid = con.conrelid
        JOIN pg_namespace n ON n.oid = rel.relnamespace
        WHERE n.nspname = 'doms' AND con.contype = 'f'
          AND NOT EXISTS (
              SELECT 1 FROM pg_index idx
              WHERE idx.indrelid = con.conrelid
                AND idx.indisvalid AND idx.indisready
                AND idx.indpred IS NULL
                AND (idx.indkey::smallint[])[0:array_length(con.conkey, 1) - 1] = con.conkey
          )
        """
    ).fetchone()[0]
    if unindexed_fk_count:
        raise RuntimeError(f"Found {unindexed_fk_count} foreign keys without a leading index")

    public_schema_create = conn.execute(
        "SELECT has_schema_privilege('public', 'doms', 'CREATE')"
    ).fetchone()[0]
    public_relation_grants = conn.execute(
        """
        SELECT count(*) FROM information_schema.role_table_grants
        WHERE table_schema = 'doms' AND grantee = 'PUBLIC'
        """
    ).fetchone()[0]
    public_sequence_grants = conn.execute(
        """
        SELECT count(*) FROM information_schema.role_usage_grants
        WHERE object_schema = 'doms' AND grantee = 'PUBLIC' AND object_type = 'SEQUENCE'
        """
    ).fetchone()[0]
    public_function_execute = conn.execute(
        """
        SELECT count(*)
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'doms'
          AND has_function_privilege('public', p.oid, 'EXECUTE')
        """
    ).fetchone()[0]
    public_default_privileges = conn.execute(
        """
        SELECT count(*)
        FROM pg_default_acl default_acl
        JOIN pg_namespace namespace_row
          ON namespace_row.oid = default_acl.defaclnamespace
        CROSS JOIN LATERAL aclexplode(default_acl.defaclacl) privilege_row
        WHERE namespace_row.nspname = 'doms'
          AND privilege_row.grantee = 0
        """
    ).fetchone()[0]
    if (
        public_schema_create
        or public_relation_grants
        or public_sequence_grants
        or public_function_execute
        or public_default_privileges
    ):
        raise RuntimeError(
            "PUBLIC privileges remain in DOMS "
            f"(schema_create={public_schema_create}, table_grants={public_relation_grants}, "
            f"sequence_grants={public_sequence_grants}, function_execute={public_function_execute}, "
            f"default_privileges={public_default_privileges})"
        )

    append_only_tables = _configured_append_only_tables(modules)
    unknown_append_only_tables = append_only_tables - existing_tables
    if unknown_append_only_tables:
        raise RuntimeError(
            "Append-only configuration names missing tables: "
            + ", ".join(sorted(unknown_append_only_tables))
        )
    append_only_trigger_rows = conn.execute(
        """
        SELECT c.relname,
               bool_or(
                   t.tgname = 'trg_append_only'
                   AND (t.tgtype & 1) = 1
                   AND (t.tgtype & 2) = 2
                   AND (t.tgtype & 8) = 8
                   AND (t.tgtype & 16) = 16
                   AND t.tgfoid = 'doms.prevent_append_only_change()'::regprocedure
               ) AS has_row_guard,
               bool_or(
                   t.tgname = 'trg_append_only_truncate'
                   AND (t.tgtype & 1) = 0
                   AND (t.tgtype & 2) = 2
                   AND (t.tgtype & 32) = 32
                   AND t.tgfoid = 'doms.prevent_append_only_truncate()'::regprocedure
               ) AS has_truncate_guard
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        LEFT JOIN pg_trigger t ON t.tgrelid = c.oid AND NOT t.tgisinternal
        WHERE n.nspname = 'doms' AND c.relname = ANY(%s::text[])
        GROUP BY c.relname
        """,
        (list(append_only_tables),),
    ).fetchall()
    unprotected_append_only = sorted(
        row[0] for row in append_only_trigger_rows if not row[1] or not row[2]
    )
    if unprotected_append_only:
        raise RuntimeError(
            "Append-only UPDATE/DELETE/TRUNCATE protection is incomplete on: "
            + ", ".join(unprotected_append_only)
        )

    platform_fk_count = conn.execute(
        """
        SELECT count(*)
        FROM pg_constraint
        WHERE conrelid = 'doms.users'::regclass
          AND conname = 'fk_doms_users_platform_user'
          AND confrelid = 'kang.users'::regclass
          AND contype = 'f'
          AND convalidated
        """
    ).fetchone()[0]
    if platform_fk_count != 1:
        raise RuntimeError("Canonical kang.users -> doms.users platform FK is missing")

    platform_user_not_null = conn.execute(
        """
        SELECT a.attnotnull
        FROM pg_attribute a
        WHERE a.attrelid = 'doms.users'::regclass
          AND a.attname = 'platform_user_id' AND NOT a.attisdropped
        """
    ).fetchone()
    if not platform_user_not_null or not platform_user_not_null[0]:
        raise RuntimeError("doms.users.platform_user_id must be NOT NULL")

    firebase_subject_index_count = conn.execute(
        """
        SELECT count(*)
        FROM pg_class i
        JOIN pg_namespace n ON n.oid = i.relnamespace
        JOIN pg_index x ON x.indexrelid = i.oid
        WHERE n.nspname = 'doms'
          AND i.relname = 'ux_users_firebase_subject'
          AND x.indrelid = 'doms.users'::regclass
          AND x.indisunique AND x.indisvalid
          AND pg_get_indexdef(i.oid) LIKE '%firebase_project_id%'
          AND pg_get_indexdef(i.oid) LIKE '%firebase_tenant_id%'
          AND pg_get_indexdef(i.oid) LIKE '%firebase_uid%'
        """
    ).fetchone()[0]
    if firebase_subject_index_count != 1:
        raise RuntimeError("Canonical DOMS Firebase subject unique index is missing")

    provider_constraint = conn.execute(
        """
        SELECT pg_get_constraintdef(c.oid)
        FROM pg_constraint c
        WHERE c.conrelid = 'doms.auth_identities'::regclass
          AND c.conname = 'ck_auth_identities_provider'
          AND c.contype = 'c' AND c.convalidated
        """
    ).fetchone()
    if provider_constraint is None:
        raise RuntimeError("DOMS auth provider constraint is missing")
    provider_definition = provider_constraint[0]
    if (
        "'password'" not in provider_definition
        or "'google.com'" not in provider_definition
        or "'firebase'" in provider_definition
        or "'custom'" in provider_definition
    ):
        raise RuntimeError(
            "DOMS auth identities must allow only password and google.com providers"
        )

    auth_constraint_definitions = {
        (row[0], row[1]): row[2]
        for row in conn.execute(
            """
            SELECT relation.relname, constraint_row.conname,
                   pg_get_constraintdef(constraint_row.oid)
            FROM pg_constraint constraint_row
            JOIN pg_class relation ON relation.oid = constraint_row.conrelid
            JOIN pg_namespace namespace_row ON namespace_row.oid = relation.relnamespace
            WHERE namespace_row.nspname = 'doms'
              AND constraint_row.contype = 'c'
              AND constraint_row.convalidated
              AND constraint_row.conname IN (
                  'ck_users_firebase_scope',
                  'ck_auth_identities_firebase_scope',
                  'ck_auth_identities_password_subject',
                  'ck_account_link_firebase_scope',
                  'ck_account_link_password_subject',
                  'ck_user_sessions_status_projection'
              )
            """
        ).fetchall()
    }
    for table_name, constraint_name in (
        ("users", "ck_users_firebase_scope"),
        ("auth_identities", "ck_auth_identities_firebase_scope"),
        ("account_link_requests", "ck_account_link_firebase_scope"),
    ):
        definition = auth_constraint_definitions.get((table_name, constraint_name), "")
        if "'kang-84cdd'" not in definition or "firebase_tenant_id IS NULL" not in definition:
            raise RuntimeError(f"Unsafe Firebase project/tenant constraint: {table_name}")
    for table_name, constraint_name in (
        ("auth_identities", "ck_auth_identities_password_subject"),
        ("account_link_requests", "ck_account_link_password_subject"),
    ):
        definition = auth_constraint_definitions.get((table_name, constraint_name), "")
        if (
            "provider_code" not in definition
            or "'password'" not in definition
            or "provider_subject" not in definition
            or "firebase_uid" not in definition
        ):
            raise RuntimeError(f"Unsafe Firebase password subject constraint: {table_name}")
    if ("user_sessions", "ck_user_sessions_status_projection") not in auth_constraint_definitions:
        raise RuntimeError("DOMS session status projection constraint is missing")

    context_contract = conn.execute(
        """
        SELECT
            to_regprocedure('doms.bind_request_context(text)') IS NOT NULL,
            to_regprocedure('doms.current_tenant_id()') IS NOT NULL,
            to_regprocedure('doms.current_doms_user_id()') IS NOT NULL,
            to_regprocedure(
                'doms.issue_user_session(uuid,text,text,text,text,uuid,timestamptz,timestamptz,text,inet,text)'
            ) IS NOT NULL,
            to_regprocedure(
                'doms.provision_tenant_membership(uuid,uuid,text,text,uuid,text,timestamptz,timestamptz,text)'
            ) IS NOT NULL,
            (
                SELECT attribute.attnotnull
                FROM pg_attribute attribute
                WHERE attribute.attrelid = 'doms.user_sessions'::regclass
                  AND attribute.attname = 'active_tenant_id'
                  AND NOT attribute.attisdropped
            ),
            NOT EXISTS (
                SELECT 1
                FROM pg_attribute attribute
                WHERE attribute.attrelid IN (
                    'doms.request_contexts'::regclass,
                    'doms.session_issue_contexts'::regclass,
                    'doms.membership_provision_contexts'::regclass
                )
                  AND attribute.attname = 'tenant_id'
                  AND NOT attribute.attisdropped
            )
        """
    ).fetchone()
    if context_contract is None or not all(context_contract):
        raise RuntimeError("DOMS protected session/request context contract is incomplete")

    conn.execute(
        "SELECT set_config('doms.tenant_id', '00000000-0000-0000-0000-000000000001', true)"
    )
    spoofed_context = conn.execute(
        "SELECT doms.current_tenant_id(), doms.current_doms_user_id()"
    ).fetchone()
    if spoofed_context != (None, None):
        raise RuntimeError("Legacy custom GUC can spoof the protected DOMS tenant context")

    forbidden_secret_columns = conn.execute(
        """
        SELECT table_name, column_name
        FROM information_schema.columns
        WHERE table_schema = 'doms'
          AND lower(regexp_replace(column_name, '[^a-zA-Z0-9]', '', 'g')) IN (
              'password','passwordhash','hashedpassword','rawpassword',
              'idtoken','accesstoken','refreshtoken','firebasetoken','googletoken',
              'sessiontoken','sessionhandle','clientsecret','privatekey','cvv','cvc',
              'pannumber','cardnumber','trackdata','pinblock'
          )
        ORDER BY table_name, column_name
        """
    ).fetchall()
    if forbidden_secret_columns:
        names = ", ".join(f"{table}.{column}" for table, column in forbidden_secret_columns)
        raise RuntimeError(f"Forbidden raw secret or payment credential columns found: {names}")

    unsafe_security_definer_count = conn.execute(
        """
        SELECT count(*)
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'doms' AND p.prosecdef
          AND NOT (
              p.proconfig IS NOT NULL
              AND EXISTS (
                  SELECT 1 FROM unnest(p.proconfig) config
                  WHERE config = 'search_path=pg_catalog, doms, pg_temp'
                     OR config = 'search_path=pg_catalog,doms,pg_temp'
              )
          )
        """
    ).fetchone()[0]
    if unsafe_security_definer_count:
        raise RuntimeError(
            f"Found {unsafe_security_definer_count} SECURITY DEFINER functions without pg_catalog, doms, pg_temp search_path"
        )

    unguarded_jsonb_count = conn.execute(
        """
        SELECT count(*)
        FROM pg_attribute attribute
        JOIN pg_class relation ON relation.oid = attribute.attrelid
        JOIN pg_namespace namespace_row ON namespace_row.oid = relation.relnamespace
        WHERE namespace_row.nspname = 'doms'
          AND relation.relkind = 'r'
          AND attribute.attnum > 0
          AND NOT attribute.attisdropped
          AND attribute.atttypid = 'jsonb'::regtype
          AND NOT EXISTS (
              SELECT 1
              FROM pg_constraint constraint_row
              WHERE constraint_row.conrelid = relation.oid
                AND constraint_row.contype = 'c'
                AND constraint_row.convalidated
                AND attribute.attnum = ANY(constraint_row.conkey)
                AND pg_get_constraintdef(constraint_row.oid)
                    LIKE '%%jsonb_contains_forbidden_secret_key%%'
          )
        """
    ).fetchone()[0]
    if unguarded_jsonb_count:
        raise RuntimeError(
            f"Found {unguarded_jsonb_count} JSONB columns without recursive secret-key checks"
        )

    unguarded_protected_text_count = conn.execute(
        r"""
        SELECT count(*)
        FROM pg_attribute attribute
        JOIN pg_class relation ON relation.oid = attribute.attrelid
        JOIN pg_namespace namespace_row ON namespace_row.oid = relation.relnamespace
        WHERE namespace_row.nspname = 'doms'
          AND relation.relkind = 'r'
          AND attribute.attnum > 0
          AND NOT attribute.attisdropped
          AND attribute.atttypid IN ('text'::regtype, 'varchar'::regtype, 'bpchar'::regtype)
          AND (
              attribute.attname LIKE '%%\_encrypted' ESCAPE '\'
              OR attribute.attname LIKE '%%\_secret\_ref' ESCAPE '\'
              OR attribute.attname = 'secret_reference'
          )
          AND NOT EXISTS (
              SELECT 1
              FROM pg_constraint constraint_row
              WHERE constraint_row.conrelid = relation.oid
                AND constraint_row.contype = 'c'
                AND constraint_row.convalidated
                AND attribute.attnum = ANY(constraint_row.conkey)
                AND (
                    (attribute.attname LIKE '%%\_encrypted' ESCAPE '\'
                     AND pg_get_constraintdef(constraint_row.oid)
                         LIKE '%%doms.is_valid_ciphertext_envelope%%')
                    OR
                    (attribute.attname NOT LIKE '%%\_encrypted' ESCAPE '\'
                     AND pg_get_constraintdef(constraint_row.oid)
                         LIKE '%%doms.is_valid_secret_reference%%')
                )
          )
        """
    ).fetchone()[0]
    if unguarded_protected_text_count:
        raise RuntimeError(
            f"Found {unguarded_protected_text_count} encrypted/secret-reference columns without envelope checks"
        )

    secret_guard_semantics = conn.execute(
        """
        SELECT
            doms.jsonb_contains_forbidden_secret_key(
                '{"paymentCardNumber":"4111111111111111"}'::jsonb
            ),
            doms.jsonb_contains_forbidden_secret_key(
                '{"card":{"number":"4111111111111111"}}'::jsonb
            ),
            doms.jsonb_contains_forbidden_secret_key(
                '{"auth":{"value":"Bearer abcdefghijk"}}'::jsonb
            ),
            doms.jsonb_contains_forbidden_secret_key(
                '["4111111111111111"]'::jsonb
            ),
            NOT doms.jsonb_contains_forbidden_secret_key(
                '{"authorization_status":"APPROVED","reference":"order-123"}'::jsonb
            ),
            doms.is_valid_ciphertext_envelope(
                'enc:v1:gcp-kms/projects/proj/locations/global/keyRings/ring/cryptoKeys/key:Abcdefghijklmnop'
            ),
            NOT doms.is_valid_ciphertext_envelope('plaintext'),
            doms.is_valid_secret_reference(
                'projects/proj/secrets/payment-gateway/versions/latest'
            ),
            NOT doms.is_valid_secret_reference('Bearer embedded-secret-value')
        """
    ).fetchone()
    if secret_guard_semantics is None or not all(secret_guard_semantics):
        raise RuntimeError("DOMS recursive secret/ciphertext guard semantics are unsafe")

    _assert_baseline_seed_presence(conn)

    migration_row = conn.execute(
        """
        SELECT checksum_sha256, catalog_checksum_sha256, baseline_seed_checksum_sha256
        FROM doms.schema_migrations
        WHERE version = %s
        """,
        (MIGRATION_VERSION,),
    ).fetchone()
    if not migration_row or not migration_row[0] or migration_row[0].strip() != expected_checksum:
        raise RuntimeError("Deployed DOMS migration checksum does not match the local SQL")
    actual_catalog_checksum = _catalog_fingerprint(conn)
    if not migration_row[1] or migration_row[1].strip() != actual_catalog_checksum:
        raise RuntimeError(
            "Deployed DOMS catalog fingerprint does not match the immutable baseline"
        )
    actual_seed_checksum = _baseline_seed_fingerprint(conn)
    if not migration_row[2] or migration_row[2].strip() != actual_seed_checksum:
        raise RuntimeError(
            "Deployed DOMS baseline seed fingerprint does not match the immutable baseline"
        )

    return {
        "database": database_name,
        "user": database_user,
        "server_version": server_version,
        "tables": table_count,
        "foreign_keys": fk_count,
        "checks": check_count,
        "indexes": index_count,
        "triggers": trigger_count,
        "rls_tables": rls_table_count,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--verify-only",
        action="store_true",
        help="Read the deployed doms catalog without running DDL.",
    )
    parser.add_argument(
        "--force-reapply",
        action="store_true",
        help="Re-run idempotent DDL even when the recorded checksum matches.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Execute and verify the entire migration, then roll the transaction back.",
    )
    args = parser.parse_args()

    if args.verify_only and args.dry_run:
        parser.error("--verify-only and --dry-run cannot be used together")

    files = _sql_files()
    modules = _load_sql_modules(files)
    checksum = _checksum(modules)

    with psycopg.connect(settings.database_url) as conn:
        if args.verify_only:
            conn.execute("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY")
        _assert_actual_target(conn)
        if args.verify_only:
            conn.execute("SET LOCAL statement_timeout = '30s'")

        metadata = conn.execute(
            "SELECT current_setting('server_version_num')::integer"
        ).fetchone()
        if metadata is None or not 110000 <= metadata[0] < 120000:
            raise RuntimeError("DOMS migration requires PostgreSQL 11.x")

        if args.verify_only:
            result = _verify(conn, modules, checksum)
            print(
                "DOMS verified: "
                f"PostgreSQL {result['server_version']}, "
                f"tables={result['tables']}, foreign_keys={result['foreign_keys']}, "
                f"checks={result['checks']}, indexes={result['indexes']}, "
                f"triggers={result['triggers']}, rls_tables={result['rls_tables']}"
            )
            return 0

        conn.execute("SET LOCAL lock_timeout = '10s'")
        conn.execute("SET LOCAL statement_timeout = '15min'")
        conn.execute("SELECT pg_advisory_xact_lock(hashtext('doms_schema_migration'))")

        migration_table_exists = conn.execute(
            "SELECT to_regclass('doms.schema_migrations') IS NOT NULL"
        ).fetchone()[0]
        migration_row = None
        recorded_migration_versions: set[str] = set()
        if migration_table_exists:
            recorded_migration_versions = {
                row[0]
                for row in conn.execute(
                    "SELECT version FROM doms.schema_migrations ORDER BY version"
                ).fetchall()
            }
            if recorded_migration_versions not in (set(), {MIGRATION_VERSION}):
                unsupported_versions = recorded_migration_versions - {MIGRATION_VERSION}
                raise RuntimeError(
                    "The target DOMS migration history is ahead of or incompatible with "
                    "this single-baseline runner. Unsupported versions: "
                    + ", ".join(sorted(unsupported_versions))
                )
            migration_row = conn.execute(
                """
                SELECT checksum_sha256, catalog_checksum_sha256,
                       baseline_seed_checksum_sha256
                FROM doms.schema_migrations
                WHERE version = %s
                """,
                (MIGRATION_VERSION,),
            ).fetchone()

        if migration_row and migration_row[0] and migration_row[0].strip() != checksum:
            raise RuntimeError(
                "The recorded DOMS migration checksum differs from the local SQL. "
                "Create a new migration version instead of rewriting deployed history."
            )

        if migration_row is None:
            preexisting_object_count = conn.execute(
                """
                SELECT count(*)
                FROM (
                    SELECT c.oid
                    FROM pg_class c
                    JOIN pg_namespace n ON n.oid = c.relnamespace
                    WHERE n.nspname = 'doms'
                      AND c.relkind IN ('r','p','v','m','S','f')
                    UNION ALL
                    SELECT p.oid
                    FROM pg_proc p
                    JOIN pg_namespace n ON n.oid = p.pronamespace
                    WHERE n.nspname = 'doms'
                    UNION ALL
                    SELECT t.oid
                    FROM pg_type t
                    JOIN pg_namespace n ON n.oid = t.typnamespace
                    WHERE n.nspname = 'doms' AND t.typtype IN ('d','e','r')
                ) existing_object
                """
            ).fetchone()[0]
            if preexisting_object_count:
                raise RuntimeError(
                    "Refusing to install the DOMS baseline without its migration row into a "
                    f"non-empty doms schema ({preexisting_object_count} user objects found)."
                )

        should_execute_baseline = bool(
            args.dry_run
            or args.force_reapply
            or not (migration_row and migration_row[0] == checksum)
        )
        if should_execute_baseline:
            conn.execute(
                """
                DO $block$
                DECLARE
                    target record;
                BEGIN
                    FOR target IN
                        SELECT DISTINCT columns.table_schema, columns.table_name
                        FROM information_schema.columns columns
                        JOIN information_schema.tables tables
                          ON tables.table_schema = columns.table_schema
                         AND tables.table_name = columns.table_name
                         AND tables.table_type = 'BASE TABLE'
                        WHERE columns.table_schema = 'doms'
                          AND columns.column_name = 'tenant_id'
                    LOOP
                        EXECUTE format(
                            'ALTER TABLE %I.%I NO FORCE ROW LEVEL SECURITY',
                            target.table_schema, target.table_name
                        );
                    END LOOP;
                END;
                $block$;
                """
            )
            for module in modules:
                conn.execute(module.text)

            catalog_checksum = _catalog_fingerprint(conn)
            baseline_seed_checksum = _baseline_seed_fingerprint(conn)
            conn.execute(
                """
                INSERT INTO doms.schema_migrations
                    (
                        version, description, checksum_sha256,
                        catalog_checksum_sha256, baseline_seed_checksum_sha256,
                        applied_at, applied_by
                    )
                VALUES (%s, %s, %s, %s, %s, now(), current_user)
                ON CONFLICT (version) DO NOTHING
                """,
                (
                    MIGRATION_VERSION,
                    MIGRATION_DESCRIPTION,
                    checksum,
                    catalog_checksum,
                    baseline_seed_checksum,
                ),
            )

        conn.execute("SET CONSTRAINTS ALL IMMEDIATE")
        result = _verify(conn, modules, checksum)

        if args.dry_run:
            conn.rollback()
            print(
                "DOMS dry run verified and rolled back: "
                f"PostgreSQL {result['server_version']}, "
                f"tables={result['tables']}, foreign_keys={result['foreign_keys']}, "
                f"checks={result['checks']}, indexes={result['indexes']}, "
                f"triggers={result['triggers']}, rls_tables={result['rls_tables']}"
            )
            return 0

    print(
        "DOMS migration committed: "
        f"PostgreSQL {result['server_version']}, "
        f"tables={result['tables']}, foreign_keys={result['foreign_keys']}, "
        f"checks={result['checks']}, indexes={result['indexes']}, "
        f"triggers={result['triggers']}, rls_tables={result['rls_tables']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
