"""Apply and verify the DWMS PostgreSQL 11 schema without exposing credentials."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
BACKEND_DIR = REPO_ROOT / "backend"
SQL_DIR = REPO_ROOT / "database" / "dwms"
MIGRATION_VERSION = "20260712_01_enterprise_dwms"
MIGRATION_DESCRIPTION = (
    "Enterprise DWMS schema: Firebase IAM, warehouse masters, inbound, outbound, "
    "bonded/customs, integration, settlement, audit, and analytics"
)
REQUIRED_MODULE_NUMBERS = tuple(range(12))
TABLE_PATTERN = re.compile(r"^CREATE TABLE IF NOT EXISTS dwms\.([a-z0-9_]+)", re.MULTILINE)
INDEX_PATTERN = re.compile(
    r"^CREATE (?:UNIQUE )?INDEX IF NOT EXISTS ([a-z0-9_]+)", re.MULTILINE
)
INDEX_TARGET_PATTERN = re.compile(
    r"^CREATE (UNIQUE )?INDEX IF NOT EXISTS ([a-z0-9_]+)\s+"
    r"ON\s+dwms\.([a-z0-9_]+)",
    re.MULTILINE,
)
TRIGGER_PATTERN = re.compile(
    r"^\s*CREATE (?:CONSTRAINT )?TRIGGER\s+([a-z0-9_]+)\s+"
    r"[\s\S]*?\bON\s+dwms\.([a-z0-9_]+)",
    re.MULTILINE,
)
CRITICAL_INTEGRITY_TRIGGERS = (
    ("shipments", "trg_enforce_shipment_customs_release", "enforce_shipment_customs_release"),
    (
        "shipping_confirmations",
        "trg_enforce_shipping_confirmation_customs_release",
        "enforce_shipping_confirmation_customs_release",
    ),
    ("loads", "trg_enforce_load_customs_release", "enforce_load_customs_release"),
    (
        "customs_release_evidence",
        "trg_validate_customs_release_evidence",
        "validate_customs_release_evidence",
    ),
    (
        "customs_release_line_coverages",
        "trg_validate_customs_release_line_coverage",
        "validate_customs_release_line_coverage",
    ),
    (
        "shipment_lines",
        "trg_guard_customs_covered_shipment_line",
        "guard_customs_covered_shipment_line",
    ),
    (
        "customs_declarations",
        "trg_guard_customs_release_legal_header",
        "guard_customs_release_legal_header",
    ),
    (
        "shipment_trade_allocations",
        "trg_guard_shipment_trade_allocation_lifecycle",
        "guard_shipment_trade_allocation_lifecycle",
    ),
    (
        "load_shipments",
        "trg_guard_load_shipment_lifecycle",
        "guard_load_shipment_lifecycle",
    ),
    (
        "unipass_messages",
        "trg_validate_unipass_message_lifecycle",
        "validate_unipass_message_lifecycle",
    ),
    (
        "unipass_message_results",
        "trg_validate_unipass_message_result",
        "validate_unipass_message_result",
    ),
    (
        "bonded_inout_reports",
        "trg_validate_bonded_report_official_acceptance",
        "validate_bonded_report_official_acceptance",
    ),
    (
        "bonded_inventory_movements",
        "trg_10_validate_bonded_movement",
        "validate_bonded_inventory_movement",
    ),
    (
        "bonded_inventory_movements",
        "trg_95_require_posted_bonded_group",
        "ensure_bonded_movement_group_posted",
    ),
    (
        "inventory_transaction_headers",
        "trg_95_require_bonded_inventory_links",
        "ensure_bonded_inventory_transaction_linked",
    ),
    (
        "receipt_inventory_allocations",
        "trg_validate_receipt_inventory_alloc",
        "validate_receipt_inventory_allocation",
    ),
    (
        "receipt_inventory_postings",
        "trg_guard_receipt_inventory_posting",
        "guard_receipt_inventory_posting_mutation",
    ),
    (
        "receipt_inventory_allocations",
        "trg_guard_receipt_inventory_allocation",
        "guard_receipt_inventory_allocation_mutation",
    ),
    (
        "receipt_inventory_postings",
        "trg_receipt_inventory_posting_integrity",
        "deferred_check_receipt_inventory_integrity",
    ),
    (
        "receipt_inventory_allocations",
        "trg_receipt_inventory_allocation_integrity",
        "deferred_check_receipt_inventory_integrity",
    ),
    (
        "inventory_transaction_headers",
        "trg_receipt_inventory_transaction_integrity",
        "deferred_check_receipt_inventory_integrity",
    ),
    (
        "inventory_transaction_entries",
        "trg_receipt_inventory_entry_integrity",
        "deferred_check_receipt_inventory_integrity",
    ),
    (
        "shipping_inventory_allocations",
        "trg_validate_shipping_inventory_allocation",
        "validate_shipping_inventory_allocation",
    ),
    (
        "shipping_inventory_allocations",
        "trg_guard_shipping_inventory_allocation",
        "guard_shipping_inventory_allocation_mutation",
    ),
    (
        "shipping_confirmations",
        "trg_guard_shipping_confirmation",
        "guard_shipping_confirmation_mutation",
    ),
    (
        "shipping_confirmations",
        "trg_shipping_confirmation_inventory_integrity",
        "deferred_check_shipping_inventory_integrity",
    ),
    (
        "shipping_inventory_allocations",
        "trg_shipping_allocation_inventory_integrity",
        "deferred_check_shipping_inventory_integrity",
    ),
    (
        "inventory_transaction_headers",
        "trg_shipping_transaction_inventory_integrity",
        "deferred_check_shipping_inventory_integrity",
    ),
    (
        "inventory_transaction_entries",
        "trg_shipping_entry_inventory_integrity",
        "deferred_check_shipping_inventory_integrity",
    ),
    ("unipass_messages", "trg_protect_message_core", "protect_message_core"),
    (
        "customs_duty_payment_allocations",
        "trg_validate_customs_duty_payment_allocation",
        "validate_customs_duty_payment_allocation",
    ),
    (
        "customs_refund_allocations",
        "trg_validate_customs_refund_allocation",
        "validate_customs_refund_allocation",
    ),
    (
        "customs_duty_payments",
        "trg_guard_customs_duty_payment_projection",
        "guard_customs_financial_header_projection",
    ),
    (
        "customs_refund_claims",
        "trg_guard_customs_refund_claim_projection",
        "guard_customs_financial_header_projection",
    ),
    (
        "charge_allocations",
        "trg_finance_validate_charge_allocation",
        "validate_charge_allocation_mutation",
    ),
    (
        "invoice_line_charges",
        "trg_finance_validate_invoice_line_charge",
        "validate_invoice_line_charge_mutation",
    ),
    (
        "charges",
        "trg_finance_guard_charge_allocation_parent",
        "guard_charge_allocation_parent",
    ),
    (
        "invoice_lines",
        "trg_finance_guard_invoice_line_parent",
        "guard_invoice_line_charge_parent",
    ),
    (
        "charge_allocations",
        "trg_finance_deferred_charge_allocation",
        "deferred_check_charge_allocation",
    ),
    (
        "invoice_line_charges",
        "trg_finance_deferred_invoice_line_charge",
        "deferred_check_charge_allocation",
    ),
    (
        "payment_applications",
        "trg_finance_validate_payment_application",
        "validate_payment_application_mutation",
    ),
    (
        "payment_applications",
        "trg_finance_project_payment_application",
        "project_payment_application",
    ),
    ("payments", "trg_finance_guard_payment_projection", "guard_payment_projection"),
    (
        "settlements",
        "trg_finance_guard_settlement_projection",
        "guard_settlement_payment_projection",
    ),
    (
        "settlement_lines",
        "trg_finance_validate_settlement_line",
        "validate_settlement_line_mutation",
    ),
    (
        "settlements",
        "trg_finance_validate_settlement_commitment",
        "validate_settlement_commitment",
    ),
    (
        "settlement_lines",
        "trg_finance_deferred_settlement_line",
        "deferred_check_settlement_line",
    ),
    (
        "payment_applications",
        "trg_finance_deferred_payment_projection",
        "assert_payment_application_projection",
    ),
)
CRITICAL_TRIGGER_SHAPES = {
    ("shipments", "trg_enforce_shipment_customs_release"): (23, False, False, False),
    ("shipping_confirmations", "trg_enforce_shipping_confirmation_customs_release"): (23, False, False, False),
    ("loads", "trg_enforce_load_customs_release"): (23, False, False, False),
    ("customs_release_evidence", "trg_validate_customs_release_evidence"): (7, False, False, False),
    ("customs_release_line_coverages", "trg_validate_customs_release_line_coverage"): (7, False, False, False),
    ("shipment_lines", "trg_guard_customs_covered_shipment_line"): (27, False, False, False),
    ("customs_declarations", "trg_guard_customs_release_legal_header"): (27, False, False, False),
    ("shipment_trade_allocations", "trg_guard_shipment_trade_allocation_lifecycle"): (31, False, False, False),
    ("load_shipments", "trg_guard_load_shipment_lifecycle"): (31, False, False, False),
    ("unipass_messages", "trg_validate_unipass_message_lifecycle"): (23, False, False, False),
    ("unipass_message_results", "trg_validate_unipass_message_result"): (7, False, False, False),
    ("bonded_inout_reports", "trg_validate_bonded_report_official_acceptance"): (23, False, False, False),
    ("bonded_inventory_movements", "trg_10_validate_bonded_movement"): (7, False, False, False),
    ("bonded_inventory_movements", "trg_95_require_posted_bonded_group"): (5, True, True, True),
    ("inventory_transaction_headers", "trg_95_require_bonded_inventory_links"): (21, True, True, True),
    ("receipt_inventory_allocations", "trg_validate_receipt_inventory_alloc"): (23, False, False, False),
    ("receipt_inventory_postings", "trg_guard_receipt_inventory_posting"): (27, False, False, False),
    ("receipt_inventory_allocations", "trg_guard_receipt_inventory_allocation"): (27, False, False, False),
    ("receipt_inventory_postings", "trg_receipt_inventory_posting_integrity"): (29, True, True, True),
    ("receipt_inventory_allocations", "trg_receipt_inventory_allocation_integrity"): (29, True, True, True),
    ("inventory_transaction_headers", "trg_receipt_inventory_transaction_integrity"): (29, True, True, True),
    ("inventory_transaction_entries", "trg_receipt_inventory_entry_integrity"): (29, True, True, True),
    ("shipping_inventory_allocations", "trg_validate_shipping_inventory_allocation"): (23, False, False, False),
    ("shipping_inventory_allocations", "trg_guard_shipping_inventory_allocation"): (27, False, False, False),
    ("shipping_confirmations", "trg_guard_shipping_confirmation"): (27, False, False, False),
    ("shipping_confirmations", "trg_shipping_confirmation_inventory_integrity"): (29, True, True, True),
    ("shipping_inventory_allocations", "trg_shipping_allocation_inventory_integrity"): (29, True, True, True),
    ("inventory_transaction_headers", "trg_shipping_transaction_inventory_integrity"): (29, True, True, True),
    ("inventory_transaction_entries", "trg_shipping_entry_inventory_integrity"): (29, True, True, True),
    ("unipass_messages", "trg_protect_message_core"): (27, False, False, False),
    ("customs_duty_payment_allocations", "trg_validate_customs_duty_payment_allocation"): (7, False, False, False),
    ("customs_refund_allocations", "trg_validate_customs_refund_allocation"): (7, False, False, False),
    ("customs_duty_payments", "trg_guard_customs_duty_payment_projection"): (19, False, False, False),
    ("customs_refund_claims", "trg_guard_customs_refund_claim_projection"): (19, False, False, False),
    ("charge_allocations", "trg_finance_validate_charge_allocation"): (31, False, False, False),
    ("invoice_line_charges", "trg_finance_validate_invoice_line_charge"): (31, False, False, False),
    ("charges", "trg_finance_guard_charge_allocation_parent"): (27, False, False, False),
    ("invoice_lines", "trg_finance_guard_invoice_line_parent"): (27, False, False, False),
    ("charge_allocations", "trg_finance_deferred_charge_allocation"): (21, True, True, True),
    ("invoice_line_charges", "trg_finance_deferred_invoice_line_charge"): (21, True, True, True),
    ("payment_applications", "trg_finance_validate_payment_application"): (31, False, False, False),
    ("payment_applications", "trg_finance_project_payment_application"): (21, False, False, False),
    ("payments", "trg_finance_guard_payment_projection"): (31, False, False, False),
    ("settlements", "trg_finance_guard_settlement_projection"): (31, False, False, False),
    ("settlement_lines", "trg_finance_validate_settlement_line"): (31, False, False, False),
    ("settlements", "trg_finance_validate_settlement_commitment"): (23, False, False, False),
    ("settlement_lines", "trg_finance_deferred_settlement_line"): (21, True, True, True),
    ("payment_applications", "trg_finance_deferred_payment_projection"): (21, True, True, True),
}
CRITICAL_INDEX_SIGNATURES = {
    "ux_dwms_charge_alloc_outbound_active": (
        "charge_allocations", True, ("charge_id", "outbound_order_id"),
        "reversed_at is null and outbound_order_id is not null",
    ),
    "ux_dwms_charge_alloc_inbound_active": (
        "charge_allocations", True, ("charge_id", "inbound_order_id"),
        "reversed_at is null and inbound_order_id is not null",
    ),
    "ux_dwms_charge_alloc_shipment_active": (
        "charge_allocations", True, ("charge_id", "shipment_id"),
        "reversed_at is null and shipment_id is not null",
    ),
    "ux_dwms_charge_alloc_receipt_active": (
        "charge_allocations", True, ("charge_id", "receipt_id"),
        "reversed_at is null and receipt_id is not null",
    ),
    "ux_dwms_invoice_line_charge_active": (
        "invoice_line_charges", True, ("invoice_line_id", "charge_id"),
        "reversed_at is null",
    ),
    "ux_dwms_invoice_charge_per_invoice_active": (
        "invoice_line_charges", True, ("invoice_id", "charge_id"),
        "reversed_at is null",
    ),
    "ux_dwms_payment_invoice_application_active": (
        "payment_applications", True, ("payment_id", "invoice_id"),
        "reversed_at is null and invoice_id is not null",
    ),
    "ux_dwms_payment_settlement_application_active": (
        "payment_applications", True, ("payment_id", "settlement_id"),
        "reversed_at is null and settlement_id is not null",
    ),
    "ux_dwms_settlement_canonical_invoice": (
        "settlements", True, ("invoice_id",), "invoice_id is not null",
    ),
}
REQUIRED_REVERSAL_CHECKS = {
    "ck_dwms_charge_alloc_reversal": "charge_allocations",
    "ck_dwms_invoice_line_charge_reversal": "invoice_line_charges",
    "ck_dwms_payment_application_reversal": "payment_applications",
}
CRITICAL_FINANCE_SECURITY_DEFINERS = (
    "open_finance_projection_authorization",
    "close_finance_projection_authorization",
    "finance_projection_authorized",
    "validate_charge_allocation_mutation",
    "validate_invoice_line_charge_mutation",
    "guard_charge_allocation_parent",
    "guard_invoice_line_charge_parent",
    "assert_charge_allocation_integrity",
    "deferred_check_charge_allocation",
    "validate_payment_application_mutation",
    "guard_payment_projection",
    "guard_settlement_payment_projection",
    "project_payment_application",
    "assert_payment_application_projection",
    "validate_settlement_line_mutation",
    "validate_settlement_commitment",
    "deferred_check_settlement_line",
    "validate_invoice_posting",
    "protect_posted_invoice_core",
    "protect_finalized_row",
    "protect_committed_row",
)
CRITICAL_BONDED_SECURITY_DEFINERS = (
    "validate_unipass_message_result",
    "validate_bonded_report_official_acceptance",
    "ensure_bonded_movement_group_posted",
    "ensure_bonded_inventory_transaction_linked",
)
CRITICAL_RECEIPT_SHIPPING_SECURITY_DEFINERS = (
    "assert_receipt_inventory_posting",
    "assert_receipt_inventory_transaction",
    "assert_receipt_document_inventory",
    "guard_receipt_inventory_posting_mutation",
    "guard_receipt_inventory_allocation_mutation",
    "deferred_check_receipt_inventory_integrity",
    "validate_shipping_inventory_allocation",
    "assert_shipping_confirmation_inventory",
    "assert_shipping_inventory_transaction",
    "assert_shipment_inventory_coverage",
    "guard_shipping_confirmation_mutation",
    "guard_shipping_inventory_allocation_mutation",
    "deferred_check_shipping_inventory_integrity",
)

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
            "Refusing DWMS DDL on the actual PostgreSQL target outside "
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
        raise RuntimeError(f"No DWMS SQL modules found under {SQL_DIR}")

    modules: dict[int, Path] = {}
    for path in files:
        match = re.fullmatch(r"(0[0-9]|1[01])_[a-z0-9_]+\.sql", path.name)
        if match is None:
            raise RuntimeError(
                f"Unexpected numbered DWMS SQL module {path.name}; expected only 00 through 11"
            )
        module_number = int(match.group(1))
        if module_number in modules:
            raise RuntimeError(
                f"Duplicate DWMS SQL module prefix {module_number:02d}: "
                f"{modules[module_number].name}, {path.name}"
            )
        modules[module_number] = path

    missing = sorted(set(REQUIRED_MODULE_NUMBERS) - set(modules))
    if missing:
        raise RuntimeError(
            "DWMS SQL modules are incomplete; missing: "
            + ", ".join(f"{number:02d}" for number in missing)
        )
    return files


def _checksum(files: list[Path]) -> str:
    digest = hashlib.sha256()
    for path in files:
        digest.update(path.name.encode("utf-8"))
        digest.update(b"\0")
        digest.update(path.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()


def _normalize_fingerprint_value(value: object) -> object:
    """Return a JSON-stable scalar without weakening SQL-definition comparisons."""
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
    # pg_get_* output is the PostgreSQL 11 server's canonical deparse. Preserve all
    # spaces (including spaces inside literals/function bodies); normalize only line
    # endings introduced by a client platform.
    return str(value).replace("\r\n", "\n").replace("\r", "\n")


def _stable_fingerprint(
    format_version: str,
    sections: list[tuple[str, tuple[str, ...], list[tuple[object, ...]]]],
) -> str:
    normalized_sections: list[dict[str, object]] = []
    for section_name, columns, rows in sections:
        normalized_rows = []
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
            {
                "name": section_name,
                "columns": list(columns),
                "rows": normalized_rows,
            }
        )
    normalized_sections.sort(key=lambda section: str(section["name"]))
    canonical_payload = json.dumps(
        {"format": format_version, "sections": normalized_sections},
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    return hashlib.sha256(canonical_payload).hexdigest()


def _catalog_fingerprint(conn: psycopg.Connection) -> str:
    # Force deterministic qualification in pg_get_* output. PostgreSQL's deparser
    # text is otherwise preserved byte-for-byte (apart from CRLF normalization).
    conn.execute("SET LOCAL search_path = pg_catalog")
    sections: list[
        tuple[str, tuple[str, ...], list[tuple[object, ...]]]
    ] = []

    sections.append(
        (
            "schema",
            ("schema_name", "owner"),
            conn.execute(
                """
                SELECT namespace_row.nspname, pg_get_userbyid(namespace_row.nspowner)
                FROM pg_namespace namespace_row
                WHERE namespace_row.nspname = 'dwms'
                """
            ).fetchall(),
        )
    )
    sections.append(
        (
            "relations",
            (
                "schema_name", "relation_name", "relation_kind", "persistence",
                "owner", "row_security", "force_row_security", "replica_identity",
                "is_partition", "partition_bound", "access_method", "reloptions",
                "view_definition",
            ),
            conn.execute(
                """
                SELECT namespace_row.nspname,
                       relation_row.relname,
                       relation_row.relkind::text,
                       relation_row.relpersistence::text,
                       pg_get_userbyid(relation_row.relowner),
                       relation_row.relrowsecurity::text,
                       relation_row.relforcerowsecurity::text,
                       relation_row.relreplident::text,
                       relation_row.relispartition::text,
                       pg_get_expr(relation_row.relpartbound, relation_row.oid, false),
                       access_method.amname,
                       COALESCE((
                           SELECT string_agg(option_value, E'\\x1f' ORDER BY option_value)
                           FROM unnest(relation_row.reloptions) option_value
                       ), ''),
                       CASE WHEN relation_row.relkind IN ('v','m')
                            THEN pg_get_viewdef(relation_row.oid, false)
                            ELSE NULL END
                FROM pg_class relation_row
                JOIN pg_namespace namespace_row
                  ON namespace_row.oid = relation_row.relnamespace
                LEFT JOIN pg_am access_method ON access_method.oid = relation_row.relam
                WHERE namespace_row.nspname = 'dwms'
                  AND relation_row.relkind IN ('r','p','v','m','S','f','c')
                """
            ).fetchall(),
        )
    )
    sections.append(
        (
            "columns",
            (
                "schema_name", "relation_name", "attribute_number", "column_name",
                "formatted_type", "type_schema", "type_name", "type_modifier",
                "array_dimensions", "not_null", "identity_kind", "collation_schema",
                "collation_name", "default_expression",
            ),
            conn.execute(
                """
                SELECT namespace_row.nspname,
                       relation_row.relname,
                       attribute_row.attnum::text,
                       attribute_row.attname,
                       format_type(attribute_row.atttypid, attribute_row.atttypmod),
                       type_namespace.nspname,
                       type_row.typname,
                       attribute_row.atttypmod::text,
                       attribute_row.attndims::text,
                       attribute_row.attnotnull::text,
                       attribute_row.attidentity::text,
                       collation_namespace.nspname,
                       collation_row.collname,
                       pg_get_expr(default_row.adbin, default_row.adrelid, false)
                FROM pg_attribute attribute_row
                JOIN pg_class relation_row ON relation_row.oid = attribute_row.attrelid
                JOIN pg_namespace namespace_row
                  ON namespace_row.oid = relation_row.relnamespace
                JOIN pg_type type_row ON type_row.oid = attribute_row.atttypid
                JOIN pg_namespace type_namespace
                  ON type_namespace.oid = type_row.typnamespace
                LEFT JOIN pg_attrdef default_row
                  ON default_row.adrelid = attribute_row.attrelid
                 AND default_row.adnum = attribute_row.attnum
                LEFT JOIN pg_collation collation_row
                  ON collation_row.oid = NULLIF(attribute_row.attcollation, 0)
                LEFT JOIN pg_namespace collation_namespace
                  ON collation_namespace.oid = collation_row.collnamespace
                WHERE namespace_row.nspname = 'dwms'
                  AND relation_row.relkind IN ('r','p','v','m','f','c')
                  AND attribute_row.attnum > 0
                  AND NOT attribute_row.attisdropped
                """
            ).fetchall(),
        )
    )
    sections.append(
        (
            "constraints",
            (
                "schema_name", "object_kind", "object_name", "constraint_name",
                "constraint_type", "definition", "deferrable", "initially_deferred",
                "validated", "is_local", "inheritance_count", "no_inherit",
                "referenced_schema", "referenced_relation",
            ),
            conn.execute(
                """
                SELECT constraint_namespace.nspname,
                       CASE WHEN constraint_row.conrelid <> 0 THEN 'relation' ELSE 'type' END,
                       COALESCE(relation_row.relname, type_row.typname),
                       constraint_row.conname,
                       constraint_row.contype::text,
                       pg_get_constraintdef(constraint_row.oid, false),
                       constraint_row.condeferrable::text,
                       constraint_row.condeferred::text,
                       constraint_row.convalidated::text,
                       constraint_row.conislocal::text,
                       constraint_row.coninhcount::text,
                       constraint_row.connoinherit::text,
                       referenced_namespace.nspname,
                       referenced_relation.relname
                FROM pg_constraint constraint_row
                JOIN pg_namespace constraint_namespace
                  ON constraint_namespace.oid = constraint_row.connamespace
                LEFT JOIN pg_class relation_row
                  ON relation_row.oid = constraint_row.conrelid
                LEFT JOIN pg_type type_row ON type_row.oid = constraint_row.contypid
                LEFT JOIN pg_class referenced_relation
                  ON referenced_relation.oid = constraint_row.confrelid
                LEFT JOIN pg_namespace referenced_namespace
                  ON referenced_namespace.oid = referenced_relation.relnamespace
                WHERE constraint_namespace.nspname = 'dwms'
                """
            ).fetchall(),
        )
    )
    sections.append(
        (
            "indexes",
            (
                "schema_name", "index_name", "table_schema", "table_name", "owner",
                "definition", "unique", "primary", "exclusion", "immediate",
                "clustered", "replica_identity", "ready", "valid", "live",
                "attribute_count", "key_attribute_count",
            ),
            conn.execute(
                """
                SELECT index_namespace.nspname,
                       index_relation.relname,
                       table_namespace.nspname,
                       table_relation.relname,
                       pg_get_userbyid(index_relation.relowner),
                       pg_get_indexdef(index_relation.oid, 0, false),
                       index_row.indisunique::text,
                       index_row.indisprimary::text,
                       index_row.indisexclusion::text,
                       index_row.indimmediate::text,
                       index_row.indisclustered::text,
                       index_row.indisreplident::text,
                       index_row.indisready::text,
                       index_row.indisvalid::text,
                       index_row.indislive::text,
                       index_row.indnatts::text,
                       index_row.indnkeyatts::text
                FROM pg_index index_row
                JOIN pg_class index_relation ON index_relation.oid = index_row.indexrelid
                JOIN pg_namespace index_namespace
                  ON index_namespace.oid = index_relation.relnamespace
                JOIN pg_class table_relation ON table_relation.oid = index_row.indrelid
                JOIN pg_namespace table_namespace
                  ON table_namespace.oid = table_relation.relnamespace
                WHERE index_namespace.nspname = 'dwms'
                """
            ).fetchall(),
        )
    )
    sections.append(
        (
            "triggers",
            (
                "table_schema", "table_name", "trigger_name", "definition",
                "function_schema", "function_name", "function_arguments", "enabled",
                "trigger_type", "deferrable", "initially_deferred",
            ),
            conn.execute(
                """
                SELECT table_namespace.nspname,
                       table_relation.relname,
                       trigger_row.tgname,
                       pg_get_triggerdef(trigger_row.oid, false),
                       function_namespace.nspname,
                       function_row.proname,
                       pg_get_function_identity_arguments(function_row.oid),
                       trigger_row.tgenabled::text,
                       trigger_row.tgtype::text,
                       trigger_row.tgdeferrable::text,
                       trigger_row.tginitdeferred::text
                FROM pg_trigger trigger_row
                JOIN pg_class table_relation ON table_relation.oid = trigger_row.tgrelid
                JOIN pg_namespace table_namespace
                  ON table_namespace.oid = table_relation.relnamespace
                JOIN pg_proc function_row ON function_row.oid = trigger_row.tgfoid
                JOIN pg_namespace function_namespace
                  ON function_namespace.oid = function_row.pronamespace
                WHERE table_namespace.nspname = 'dwms'
                  AND NOT trigger_row.tgisinternal
                """
            ).fetchall(),
        )
    )
    sections.append(
        (
            "functions",
            (
                "schema_name", "function_name", "identity_arguments", "result_type",
                "kind", "language", "owner", "security_definer", "volatility",
                "strict", "leakproof", "parallel", "cost", "rows", "configuration",
                "definition",
            ),
            conn.execute(
                """
                SELECT function_namespace.nspname,
                       function_row.proname,
                       pg_get_function_identity_arguments(function_row.oid),
                       pg_get_function_result(function_row.oid),
                       function_row.prokind::text,
                       language_row.lanname,
                       pg_get_userbyid(function_row.proowner),
                       function_row.prosecdef::text,
                       function_row.provolatile::text,
                       function_row.proisstrict::text,
                       function_row.proleakproof::text,
                       function_row.proparallel::text,
                       function_row.procost::text,
                       function_row.prorows::text,
                       array_to_string(function_row.proconfig, E'\\x1f'),
                       CASE WHEN function_row.prokind = 'a' THEN function_row.prosrc
                            ELSE pg_get_functiondef(function_row.oid) END
                FROM pg_proc function_row
                JOIN pg_namespace function_namespace
                  ON function_namespace.oid = function_row.pronamespace
                JOIN pg_language language_row ON language_row.oid = function_row.prolang
                WHERE function_namespace.nspname = 'dwms'
                """
            ).fetchall(),
        )
    )
    sections.append(
        (
            "policies",
            (
                "table_schema", "table_name", "policy_name", "command", "permissive",
                "roles", "using_expression", "check_expression",
            ),
            conn.execute(
                """
                SELECT table_namespace.nspname,
                       table_relation.relname,
                       policy_row.polname,
                       policy_row.polcmd::text,
                       policy_row.polpermissive::text,
                       COALESCE((
                           SELECT string_agg(
                               CASE WHEN role_oid = 0 THEN 'PUBLIC'
                                    ELSE pg_get_userbyid(role_oid) END,
                               E'\\x1f' ORDER BY
                               CASE WHEN role_oid = 0 THEN 'PUBLIC'
                                    ELSE pg_get_userbyid(role_oid) END
                           )
                           FROM unnest(policy_row.polroles) role_oid
                       ), ''),
                       pg_get_expr(policy_row.polqual, policy_row.polrelid, false),
                       pg_get_expr(policy_row.polwithcheck, policy_row.polrelid, false)
                FROM pg_policy policy_row
                JOIN pg_class table_relation ON table_relation.oid = policy_row.polrelid
                JOIN pg_namespace table_namespace
                  ON table_namespace.oid = table_relation.relnamespace
                WHERE table_namespace.nspname = 'dwms'
                """
            ).fetchall(),
        )
    )
    sections.append(
        (
            "types",
            (
                "schema_name", "type_name", "owner", "kind", "category", "defined",
                "preferred", "not_null", "length", "by_value", "alignment", "storage",
                "delimiter", "element_schema", "element_type", "array_schema",
                "array_type", "base_schema", "base_type", "type_modifier", "dimensions",
                "collation_schema", "collation_name", "default_expression",
                "relation_schema", "relation_name",
            ),
            conn.execute(
                """
                SELECT type_namespace.nspname,
                       type_row.typname,
                       pg_get_userbyid(type_row.typowner),
                       type_row.typtype::text,
                       type_row.typcategory::text,
                       type_row.typisdefined::text,
                       type_row.typispreferred::text,
                       type_row.typnotnull::text,
                       type_row.typlen::text,
                       type_row.typbyval::text,
                       type_row.typalign::text,
                       type_row.typstorage::text,
                       type_row.typdelim::text,
                       element_namespace.nspname,
                       element_type.typname,
                       array_namespace.nspname,
                       array_type.typname,
                       base_namespace.nspname,
                       base_type.typname,
                       type_row.typtypmod::text,
                       type_row.typndims::text,
                       collation_namespace.nspname,
                       collation_row.collname,
                       COALESCE(pg_get_expr(type_row.typdefaultbin, 0, false), type_row.typdefault),
                       relation_namespace.nspname,
                       relation_row.relname
                FROM pg_type type_row
                JOIN pg_namespace type_namespace ON type_namespace.oid = type_row.typnamespace
                LEFT JOIN pg_type element_type ON element_type.oid = NULLIF(type_row.typelem, 0)
                LEFT JOIN pg_namespace element_namespace
                  ON element_namespace.oid = element_type.typnamespace
                LEFT JOIN pg_type array_type ON array_type.oid = NULLIF(type_row.typarray, 0)
                LEFT JOIN pg_namespace array_namespace
                  ON array_namespace.oid = array_type.typnamespace
                LEFT JOIN pg_type base_type ON base_type.oid = NULLIF(type_row.typbasetype, 0)
                LEFT JOIN pg_namespace base_namespace ON base_namespace.oid = base_type.typnamespace
                LEFT JOIN pg_collation collation_row
                  ON collation_row.oid = NULLIF(type_row.typcollation, 0)
                LEFT JOIN pg_namespace collation_namespace
                  ON collation_namespace.oid = collation_row.collnamespace
                LEFT JOIN pg_class relation_row ON relation_row.oid = NULLIF(type_row.typrelid, 0)
                LEFT JOIN pg_namespace relation_namespace
                  ON relation_namespace.oid = relation_row.relnamespace
                WHERE type_namespace.nspname = 'dwms'
                """
            ).fetchall(),
        )
    )
    sections.append(
        (
            "enum_labels",
            ("schema_name", "type_name", "sort_order", "label"),
            conn.execute(
                """
                SELECT type_namespace.nspname, type_row.typname,
                       enum_row.enumsortorder::text, enum_row.enumlabel
                FROM pg_enum enum_row
                JOIN pg_type type_row ON type_row.oid = enum_row.enumtypid
                JOIN pg_namespace type_namespace ON type_namespace.oid = type_row.typnamespace
                WHERE type_namespace.nspname = 'dwms'
                """
            ).fetchall(),
        )
    )
    sections.append(
        (
            "ranges",
            (
                "schema_name", "type_name", "subtype_schema", "subtype_name",
                "collation_schema", "collation_name", "operator_class_schema",
                "operator_class_name", "access_method", "canonical_schema",
                "canonical_function", "canonical_arguments", "subdiff_schema",
                "subdiff_function", "subdiff_arguments",
            ),
            conn.execute(
                """
                SELECT range_namespace.nspname,
                       range_type.typname,
                       subtype_namespace.nspname,
                       subtype_type.typname,
                       collation_namespace.nspname,
                       collation_row.collname,
                       operator_namespace.nspname,
                       operator_class.opcname,
                       access_method.amname,
                       canonical_namespace.nspname,
                       canonical_function.proname,
                       pg_get_function_identity_arguments(canonical_function.oid),
                       subdiff_namespace.nspname,
                       subdiff_function.proname,
                       pg_get_function_identity_arguments(subdiff_function.oid)
                FROM pg_range range_row
                JOIN pg_type range_type ON range_type.oid = range_row.rngtypid
                JOIN pg_namespace range_namespace ON range_namespace.oid = range_type.typnamespace
                JOIN pg_type subtype_type ON subtype_type.oid = range_row.rngsubtype
                JOIN pg_namespace subtype_namespace
                  ON subtype_namespace.oid = subtype_type.typnamespace
                LEFT JOIN pg_collation collation_row
                  ON collation_row.oid = NULLIF(range_row.rngcollation, 0)
                LEFT JOIN pg_namespace collation_namespace
                  ON collation_namespace.oid = collation_row.collnamespace
                JOIN pg_opclass operator_class ON operator_class.oid = range_row.rngsubopc
                JOIN pg_namespace operator_namespace
                  ON operator_namespace.oid = operator_class.opcnamespace
                JOIN pg_am access_method ON access_method.oid = operator_class.opcmethod
                LEFT JOIN pg_proc canonical_function
                  ON canonical_function.oid = NULLIF(range_row.rngcanonical, 0)
                LEFT JOIN pg_namespace canonical_namespace
                  ON canonical_namespace.oid = canonical_function.pronamespace
                LEFT JOIN pg_proc subdiff_function
                  ON subdiff_function.oid = NULLIF(range_row.rngsubdiff, 0)
                LEFT JOIN pg_namespace subdiff_namespace
                  ON subdiff_namespace.oid = subdiff_function.pronamespace
                WHERE range_namespace.nspname = 'dwms'
                """
            ).fetchall(),
        )
    )
    sections.append(
        (
            "sequences",
            (
                "schema_name", "sequence_name", "data_type", "start", "increment",
                "minimum", "maximum", "cache", "cycle",
            ),
            conn.execute(
                """
                SELECT sequence_namespace.nspname,
                       sequence_relation.relname,
                       format_type(sequence_row.seqtypid, NULL),
                       sequence_row.seqstart::text,
                       sequence_row.seqincrement::text,
                       sequence_row.seqmin::text,
                       sequence_row.seqmax::text,
                       sequence_row.seqcache::text,
                       sequence_row.seqcycle::text
                FROM pg_sequence sequence_row
                JOIN pg_class sequence_relation
                  ON sequence_relation.oid = sequence_row.seqrelid
                JOIN pg_namespace sequence_namespace
                  ON sequence_namespace.oid = sequence_relation.relnamespace
                WHERE sequence_namespace.nspname = 'dwms'
                """
            ).fetchall(),
        )
    )
    return _stable_fingerprint("dwms-catalog-pg11-v1", sections)


BASELINE_CURRENCY_CODES = ("KRW", "USD", "EUR", "JPY", "CNY")
BASELINE_COUNTRY_CODES = ("KR", "US", "JP", "CN", "DE", "VN")
BASELINE_UOM_CODES = (
    "EA", "CASE", "PALLET", "KG", "G", "TON", "L", "ML", "M3", "M", "CM",
    "MM", "M2", "MIN", "HOUR", "CEL",
)
BASELINE_TRANSPORT_MODE_CODES = ("ROAD", "SEA", "AIR", "RAIL", "PARCEL", "MULTIMODAL")
BASELINE_INCOTERM_CODES = ("EXW", "FCA", "CPT", "CIP", "DAP", "DPU", "DDP", "FAS", "FOB", "CFR", "CIF")
BASELINE_INVENTORY_STATUS_CODES = (
    "AVAILABLE", "RECEIVING", "QUALITY_HOLD", "QUARANTINE", "DAMAGED", "EXPIRED",
    "IN_TRANSIT", "SHIPPED", "VIRTUAL",
)
BASELINE_LOCATION_TYPE_CODES = (
    "RECEIVING", "STORAGE", "FORWARD_PICK", "STAGING", "PACKING", "SHIPPING",
    "CROSS_DOCK", "QUALITY", "QUARANTINE", "DAMAGE", "VIRTUAL",
)
BASELINE_PERMISSION_CODES = (
    "iam.user.read", "iam.role.manage", "config.manage", "master.read", "master.manage",
    "inbound.read", "inbound.execute", "inventory.read", "inventory.post",
    "inventory.adjust", "inventory.hold", "outbound.read", "outbound.execute",
    "customs.read", "customs.submit", "bonded.read", "bonded.report", "billing.read",
    "billing.approve", "workflow.approve", "audit.read", "data_access.read",
    "integration.monitor", "integration.manage",
)
BASELINE_SYSTEM_ROLE_CODES = (
    "DWMS_VIEWER", "DWMS_OPERATOR", "DWMS_SUPERVISOR", "DWMS_INVENTORY_CONTROLLER",
    "DWMS_CUSTOMS_SPECIALIST", "DWMS_BILLING_SPECIALIST", "DWMS_AUDITOR",
    "DWMS_TENANT_ADMIN",
)
BASELINE_RETENTION_ENTITY_TYPES = (
    "login_events", "notifications", "import_export_jobs", "sensor_readings",
    "data_access_logs", "audit_events", "entity_change_logs", "unipass_messages",
    "customs_declarations", "bonded_records", "inventory_ledger",
    "invoices_settlements_journals",
)


def _baseline_seed_fingerprint(conn: psycopg.Connection) -> str:
    def rows(query: str, codes: tuple[str, ...]) -> list[tuple[object, ...]]:
        return conn.execute(query, (list(codes),)).fetchall()

    sections: list[
        tuple[str, tuple[str, ...], list[tuple[object, ...]]]
    ] = [
        (
            "currencies",
            ("code", "name", "numeric_code", "fraction_digits", "rounding_increment", "active"),
            rows(
                """
                SELECT currency_code::text, currency_name, numeric_code::text,
                       fraction_digits::text, rounding_increment::text, is_active::text
                FROM dwms.currencies WHERE currency_code = ANY(%s::text[])
                """,
                BASELINE_CURRENCY_CODES,
            ),
        ),
        (
            "countries",
            ("code2", "code3", "numeric_code", "name_en", "name_local", "currency", "active"),
            rows(
                """
                SELECT country_code::text, country_code3::text, numeric_code::text,
                       country_name_en, country_name_local, default_currency_code::text,
                       is_active::text
                FROM dwms.countries WHERE country_code = ANY(%s::text[])
                """,
                BASELINE_COUNTRY_CODES,
            ),
        ),
        (
            "units_of_measure",
            ("code", "name", "dimension", "si_factor", "decimal_places", "active"),
            rows(
                """
                SELECT uom_code, uom_name, dimension, si_factor::text,
                       decimal_places::text, is_active::text
                FROM dwms.units_of_measure WHERE uom_code = ANY(%s::text[])
                """,
                BASELINE_UOM_CODES,
            ),
        ),
        (
            "transport_modes",
            ("code", "name", "group", "active"),
            rows(
                """
                SELECT mode_code, mode_name, mode_group, is_active::text
                FROM dwms.transport_modes WHERE mode_code = ANY(%s::text[])
                """,
                BASELINE_TRANSPORT_MODE_CODES,
            ),
        ),
        (
            "incoterms",
            ("code", "name", "version_year", "active"),
            rows(
                """
                SELECT incoterm_code::text, incoterm_name, version_year::text, is_active::text
                FROM dwms.incoterms WHERE incoterm_code = ANY(%s::text[])
                """,
                BASELINE_INCOTERM_CODES,
            ),
        ),
        (
            "inventory_statuses",
            ("code", "name", "category", "allocatable", "shippable", "hold", "system", "active"),
            rows(
                """
                SELECT status_code, status_name, status_category,
                       available_for_allocation::text, available_for_shipping::text,
                       requires_hold::text, is_system_status::text, is_active::text
                FROM dwms.inventory_statuses
                WHERE tenant_id IS NULL AND status_code = ANY(%s::text[])
                """,
                BASELINE_INVENTORY_STATUS_CODES,
            ),
        ),
        (
            "location_types",
            (
                "code", "name", "category", "pickable", "putaway", "countable",
                "virtual", "default_inventory_status", "active",
            ),
            rows(
                """
                SELECT location_type.location_type_code,
                       location_type.location_type_name,
                       location_type.location_category,
                       location_type.pickable::text,
                       location_type.putaway_allowed::text,
                       location_type.countable::text,
                       location_type.virtual_location::text,
                       default_status.status_code,
                       location_type.is_active::text
                FROM dwms.location_types location_type
                LEFT JOIN dwms.inventory_statuses default_status
                  ON default_status.id = location_type.default_inventory_status_id
                WHERE location_type.tenant_id IS NULL
                  AND location_type.location_type_code = ANY(%s::text[])
                """,
                BASELINE_LOCATION_TYPE_CODES,
            ),
        ),
        (
            "permissions",
            ("code", "name", "module", "action", "description", "sensitive", "active"),
            rows(
                """
                SELECT permission_code, permission_name, module_code, action_code,
                       description, is_sensitive::text, is_active::text
                FROM dwms.permissions WHERE permission_code = ANY(%s::text[])
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
                FROM dwms.roles
                WHERE tenant_id IS NULL AND role_code = ANY(%s::text[])
                """,
                BASELINE_SYSTEM_ROLE_CODES,
            ),
        ),
        (
            "system_role_permissions",
            ("role_code", "permission_code", "active_grant"),
            rows(
                """
                SELECT role_row.role_code, permission_row.permission_code,
                       (role_permission.revoked_at IS NULL)::text
                FROM dwms.role_permissions role_permission
                JOIN dwms.roles role_row ON role_row.id = role_permission.role_id
                JOIN dwms.permissions permission_row
                  ON permission_row.id = role_permission.permission_id
                WHERE role_permission.tenant_id IS NULL
                  AND role_row.tenant_id IS NULL
                  AND role_row.role_code = ANY(%s::text[])
                """,
                BASELINE_SYSTEM_ROLE_CODES,
            ),
        ),
        (
            "data_retention_policies",
            ("entity_type", "retention_days", "anonymize_after_days", "strategy", "legal_basis", "active"),
            rows(
                """
                SELECT entity_type, retention_days::text, anonymize_after_days::text,
                       purge_strategy, legal_basis, is_active::text
                FROM dwms.data_retention_policies
                WHERE tenant_id IS NULL AND entity_type = ANY(%s::text[])
                """,
                BASELINE_RETENTION_ENTITY_TYPES,
            ),
        ),
    ]
    return _stable_fingerprint("dwms-baseline-seeds-v1", sections)


def _normalize_catalog_expression(value: str | None) -> str:
    if value is None:
        return ""
    return re.sub(r'[\s()"]+', "", value).lower()


def _expected_catalog(
    files: list[Path],
) -> tuple[set[str], set[str], set[tuple[str, str]]]:
    sql = "\n".join(path.read_text(encoding="utf-8") for path in files)
    return (
        set(TABLE_PATTERN.findall(sql)),
        set(INDEX_PATTERN.findall(sql)),
        set(TRIGGER_PATTERN.findall(sql)),
    )


def _configured_append_only_tables(files: list[Path]) -> set[str]:
    operations_sql = next(path for path in files if path.name.startswith("11_")).read_text(
        encoding="utf-8"
    )
    start_marker = "-- Strict append-only records."
    end_marker = "-- Message payloads and routing identity"
    if start_marker not in operations_sql or end_marker not in operations_sql:
        raise RuntimeError("Unable to locate the module 11 append-only configuration")
    configured_block = operations_sql.split(start_marker, 1)[1].split(end_marker, 1)[0]
    array_match = re.search(
        r"FOREACH\s+table_name\s+IN\s+ARRAY\s+ARRAY\[(.*?)\]::text\[\]",
        configured_block,
        re.DOTALL,
    )
    if array_match is None:
        raise RuntimeError("Unable to parse the module 11 append-only table list")
    return set(re.findall(r"'([a-z][a-z0-9_]*)'", array_match.group(1)))


def _verify(
    conn: psycopg.Connection,
    files: list[Path],
    expected_checksum: str,
) -> dict[str, int | str]:
    (
        actual_database,
        actual_user,
        _actual_session_user,
        _actual_server_address,
        _actual_server_port,
    ) = _assert_actual_target(conn)
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
    if database_name != actual_database or database_user != actual_user:
        raise RuntimeError("PostgreSQL target identity changed during DWMS verification")
    if not 110000 <= server_version_num < 120000:
        raise RuntimeError(
            f"DWMS migration is pinned to PostgreSQL 11; server reports {server_version}"
        )

    schema_owner = conn.execute(
        """
        SELECT pg_get_userbyid(nspowner)
        FROM pg_namespace
        WHERE nspname = 'dwms'
        """
    ).fetchone()
    if schema_owner is None:
        raise RuntimeError("dwms schema does not exist after migration")
    if schema_owner[0] != REQUIRED_POSTGRES_USER:
        raise RuntimeError(
            f"dwms schema owner must be {REQUIRED_POSTGRES_USER}, found {schema_owner[0]}"
        )

    migration_table_exists = conn.execute(
        "SELECT to_regclass('dwms.schema_migrations') IS NOT NULL"
    ).fetchone()[0]
    if not migration_table_exists:
        raise RuntimeError("dwms.schema_migrations is missing")
    recorded_migration_versions = {
        row[0]
        for row in conn.execute(
            "SELECT version FROM dwms.schema_migrations ORDER BY version"
        ).fetchall()
    }
    if recorded_migration_versions != {MIGRATION_VERSION}:
        raise RuntimeError(
            "Verified DWMS migration history must contain exactly the supported baseline "
            f"{MIGRATION_VERSION}; found: "
            + (", ".join(sorted(recorded_migration_versions)) or "<empty>")
        )

    unexpected_owners = conn.execute(
        """
        SELECT object_type, object_name, object_owner
        FROM (
            SELECT 'relation'::text AS object_type, c.relname AS object_name,
                   pg_get_userbyid(c.relowner) AS object_owner
            FROM pg_class c
            JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'dwms'
              AND c.relkind IN ('r','p','v','m','S','f')
            UNION ALL
            SELECT 'function', p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')',
                   pg_get_userbyid(p.proowner)
            FROM pg_proc p
            JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'dwms'
            UNION ALL
            SELECT 'type', t.typname, pg_get_userbyid(t.typowner)
            FROM pg_type t
            JOIN pg_namespace n ON n.oid = t.typnamespace
            WHERE n.nspname = 'dwms'
        ) owned_object
        WHERE object_owner <> %s
        ORDER BY object_type, object_name
        LIMIT 20
        """,
        (REQUIRED_POSTGRES_USER,),
    ).fetchall()
    if unexpected_owners:
        detail = ", ".join(
            f"{object_type}:{object_name}={owner}"
            for object_type, object_name, owner in unexpected_owners
        )
        raise RuntimeError(f"DWMS objects have unexpected owners: {detail}")

    public_schema_create = conn.execute(
        """
        SELECT EXISTS (
            SELECT 1
            FROM pg_namespace n,
                 LATERAL aclexplode(COALESCE(n.nspacl, acldefault('n', n.nspowner))) acl
            WHERE n.nspname = 'dwms'
              AND acl.grantee = 0
              AND acl.privilege_type = 'CREATE'
        )
        """
    ).fetchone()[0]
    public_function_execute_count = conn.execute(
        """
        SELECT count(*)
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace,
             LATERAL aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) acl
        WHERE n.nspname = 'dwms'
          AND acl.grantee = 0
          AND acl.privilege_type = 'EXECUTE'
        """
    ).fetchone()[0]
    public_relation_privilege_count = conn.execute(
        """
        SELECT count(*)
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace,
             LATERAL aclexplode(
                 COALESCE(
                     c.relacl,
                     acldefault(
                         CASE WHEN c.relkind = 'S' THEN 'S'::"char" ELSE 'r'::"char" END,
                         c.relowner
                     )
                 )
             ) acl
        WHERE n.nspname = 'dwms'
          AND c.relkind IN ('r','p','v','m','S','f')
          AND acl.grantee = 0
        """
    ).fetchone()[0]
    if (
        public_schema_create
        or public_function_execute_count
        or public_relation_privilege_count
    ):
        raise RuntimeError(
            "PUBLIC must have no CREATE on dwms and no DWMS relation/sequence/function privileges"
        )

    table_count = conn.execute(
        """
        SELECT count(*)
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'dwms' AND c.relkind IN ('r', 'p')
        """
    ).fetchone()[0]
    fk_count = conn.execute(
        """
        SELECT count(*)
        FROM pg_constraint c
        JOIN pg_namespace n ON n.oid = c.connamespace
        WHERE n.nspname = 'dwms' AND c.contype = 'f'
        """
    ).fetchone()[0]
    check_count = conn.execute(
        """
        SELECT count(*)
        FROM pg_constraint c
        JOIN pg_namespace n ON n.oid = c.connamespace
        WHERE n.nspname = 'dwms' AND c.contype = 'c'
        """
    ).fetchone()[0]
    index_count = conn.execute(
        """
        SELECT count(*)
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'dwms' AND c.relkind = 'i'
        """
    ).fetchone()[0]
    trigger_count = conn.execute(
        """
        SELECT count(*)
        FROM pg_trigger t
        JOIN pg_class c ON c.oid = t.tgrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'dwms' AND NOT t.tgisinternal
        """
    ).fetchone()[0]
    tenant_table_count, rls_table_count, forced_rls_table_count = conn.execute(
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
        WHERE n.nspname = 'dwms' AND c.relkind IN ('r', 'p')
        """
    ).fetchone()

    expected_tables, expected_indexes, expected_triggers = _expected_catalog(files)
    existing_tables = {
        value[0]
        for value in conn.execute(
            """
            SELECT c.relname
            FROM pg_class c
            JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'dwms' AND c.relkind IN ('r', 'p')
            """
        ).fetchall()
    }
    missing_tables = sorted(expected_tables - existing_tables)
    if missing_tables:
        raise RuntimeError(f"Expected DWMS tables are missing: {', '.join(missing_tables)}")

    existing_indexes = {
        value[0]
        for value in conn.execute(
            """
            SELECT c.relname
            FROM pg_class c
            JOIN pg_namespace n ON n.oid = c.relnamespace
            JOIN pg_index index_row ON index_row.indexrelid = c.oid
            WHERE n.nspname = 'dwms'
              AND c.relkind = 'i'
              AND index_row.indisvalid
              AND index_row.indisready
            """
        ).fetchall()
    }
    missing_indexes = sorted(expected_indexes - existing_indexes)
    if missing_indexes:
        raise RuntimeError(f"Expected DWMS indexes are missing: {', '.join(missing_indexes)}")

    expected_index_targets = {
        (index_name, table_name, bool(unique_marker))
        for path in files
        for unique_marker, index_name, table_name in INDEX_TARGET_PATTERN.findall(
            path.read_text(encoding="utf-8")
        )
    }
    existing_index_targets = {
        (value[0], value[1], value[2])
        for value in conn.execute(
            """
            SELECT index_class.relname, table_class.relname, index_row.indisunique
            FROM pg_index index_row
            JOIN pg_class index_class ON index_class.oid = index_row.indexrelid
            JOIN pg_class table_class ON table_class.oid = index_row.indrelid
            JOIN pg_namespace namespace_row ON namespace_row.oid = index_class.relnamespace
            WHERE namespace_row.nspname = 'dwms'
              AND index_row.indisvalid
              AND index_row.indisready
            """
        ).fetchall()
    }
    missing_index_targets = sorted(expected_index_targets - existing_index_targets)
    if missing_index_targets:
        formatted = ", ".join(
            f"{index_name}->{table_name} (unique={is_unique})"
            for index_name, table_name, is_unique in missing_index_targets
        )
        raise RuntimeError(f"DWMS index target/uniqueness mismatch: {formatted}")

    critical_index_rows = conn.execute(
        """
        SELECT index_class.relname, table_class.relname, index_row.indisunique,
               ARRAY(
                   SELECT pg_get_indexdef(index_row.indexrelid, column_no, true)
                   FROM generate_series(1, index_row.indnkeyatts) column_no
                   ORDER BY column_no
               ),
               pg_get_expr(index_row.indpred, index_row.indrelid)
        FROM pg_index index_row
        JOIN pg_class index_class ON index_class.oid = index_row.indexrelid
        JOIN pg_class table_class ON table_class.oid = index_row.indrelid
        JOIN pg_namespace namespace_row ON namespace_row.oid = index_class.relnamespace
        WHERE namespace_row.nspname = 'dwms'
          AND index_class.relname = ANY(%s::text[])
          AND index_row.indisvalid
          AND index_row.indisready
        """,
        (list(CRITICAL_INDEX_SIGNATURES),),
    ).fetchall()
    critical_index_catalog = {row[0]: row[1:] for row in critical_index_rows}
    invalid_critical_indexes = []
    for index_name, expected in CRITICAL_INDEX_SIGNATURES.items():
        actual = critical_index_catalog.get(index_name)
        if actual is None:
            invalid_critical_indexes.append(index_name)
            continue
        table_name, is_unique, columns, predicate = actual
        expected_table, expected_unique, expected_columns, expected_predicate = expected
        if (
            table_name != expected_table
            or is_unique != expected_unique
            or tuple(columns) != expected_columns
            or _normalize_catalog_expression(predicate)
            != _normalize_catalog_expression(expected_predicate)
        ):
            invalid_critical_indexes.append(index_name)
    if invalid_critical_indexes:
        raise RuntimeError(
            "Critical financial index columns/predicates are missing or changed: "
            + ", ".join(sorted(invalid_critical_indexes))
        )

    existing_triggers = {
        (value[0], value[1])
        for value in conn.execute(
            """
            SELECT DISTINCT t.tgname, c.relname
            FROM pg_trigger t
            JOIN pg_class c ON c.oid = t.tgrelid
            JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'dwms' AND NOT t.tgisinternal
              AND t.tgenabled <> 'D'
            """
        ).fetchall()
    }
    missing_triggers = sorted(expected_triggers - existing_triggers)
    if missing_triggers:
        formatted = ", ".join(
            f"{table_name}.{trigger_name}"
            for trigger_name, table_name in missing_triggers
        )
        raise RuntimeError(f"Expected DWMS triggers are missing: {formatted}")

    critical_tables = [item[0] for item in CRITICAL_INTEGRITY_TRIGGERS]
    critical_names = [item[1] for item in CRITICAL_INTEGRITY_TRIGGERS]
    critical_functions = [item[2] for item in CRITICAL_INTEGRITY_TRIGGERS]
    missing_critical_triggers = conn.execute(
        """
        SELECT expected.table_name, expected.trigger_name, expected.function_name
        FROM unnest(%s::text[], %s::text[], %s::text[])
             AS expected(table_name, trigger_name, function_name)
        WHERE NOT EXISTS (
            SELECT 1
            FROM pg_trigger trigger_row
            JOIN pg_class table_row ON table_row.oid = trigger_row.tgrelid
            JOIN pg_namespace table_namespace ON table_namespace.oid = table_row.relnamespace
            JOIN pg_proc function_row ON function_row.oid = trigger_row.tgfoid
            JOIN pg_namespace function_namespace
              ON function_namespace.oid = function_row.pronamespace
            WHERE table_namespace.nspname = 'dwms'
              AND table_row.relname = expected.table_name
              AND trigger_row.tgname = expected.trigger_name
              AND function_namespace.nspname = 'dwms'
              AND function_row.proname = expected.function_name
              AND NOT trigger_row.tgisinternal
              AND trigger_row.tgenabled <> 'D'
        )
        ORDER BY expected.table_name, expected.trigger_name
        """,
        (critical_tables, critical_names, critical_functions),
    ).fetchall()
    if missing_critical_triggers:
        formatted = ", ".join(
            f"{table}.{trigger}->{function}"
            for table, trigger, function in missing_critical_triggers
        )
        raise RuntimeError(f"Critical DWMS integrity triggers are missing or miswired: {formatted}")

    critical_shape_tables = [item[0] for item in CRITICAL_TRIGGER_SHAPES]
    critical_shape_names = [item[1] for item in CRITICAL_TRIGGER_SHAPES]
    critical_shape_types = [item[0] for item in CRITICAL_TRIGGER_SHAPES.values()]
    critical_shape_deferrable = [item[1] for item in CRITICAL_TRIGGER_SHAPES.values()]
    critical_shape_initially_deferred = [item[2] for item in CRITICAL_TRIGGER_SHAPES.values()]
    critical_shape_constraint = [item[3] for item in CRITICAL_TRIGGER_SHAPES.values()]
    invalid_critical_trigger_shapes = conn.execute(
        """
        SELECT expected.table_name, expected.trigger_name
        FROM unnest(
            %s::text[], %s::text[], %s::smallint[],
            %s::boolean[], %s::boolean[], %s::boolean[]
        ) AS expected(
            table_name, trigger_name, trigger_type,
            is_deferrable, initially_deferred, is_constraint
        )
        LEFT JOIN pg_namespace namespace_row ON namespace_row.nspname = 'dwms'
        LEFT JOIN pg_class table_row
          ON table_row.relnamespace = namespace_row.oid
         AND table_row.relname = expected.table_name
        LEFT JOIN pg_trigger trigger_row
          ON trigger_row.tgrelid = table_row.oid
         AND trigger_row.tgname = expected.trigger_name
         AND NOT trigger_row.tgisinternal
        WHERE trigger_row.oid IS NULL
           OR trigger_row.tgenabled = 'D'
           OR trigger_row.tgtype <> expected.trigger_type
           OR trigger_row.tgdeferrable IS DISTINCT FROM expected.is_deferrable
           OR trigger_row.tginitdeferred IS DISTINCT FROM expected.initially_deferred
           OR (trigger_row.tgconstraint <> 0) IS DISTINCT FROM expected.is_constraint
        ORDER BY expected.table_name, expected.trigger_name
        """,
        (
            critical_shape_tables,
            critical_shape_names,
            critical_shape_types,
            critical_shape_deferrable,
            critical_shape_initially_deferred,
            critical_shape_constraint,
        ),
    ).fetchall()
    if invalid_critical_trigger_shapes:
        formatted = ", ".join(
            f"{table}.{trigger}" for table, trigger in invalid_critical_trigger_shapes
        )
        raise RuntimeError(
            "Critical trigger timing/events/constraint deferral are missing or changed: "
            + formatted
        )

    bonded_link_columns = dict(
        conn.execute(
            """
            SELECT column_name, is_nullable
            FROM information_schema.columns
            WHERE table_schema = 'dwms'
              AND table_name = 'bonded_inventory_movements'
              AND column_name IN (
                  'stock_bucket_id','inventory_transaction_id',
                  'inventory_transaction_entry_id'
              )
            """
        ).fetchall()
    )
    if bonded_link_columns != {
        "stock_bucket_id": "NO",
        "inventory_transaction_id": "NO",
        "inventory_transaction_entry_id": "NO",
    }:
        raise RuntimeError(
            "Bonded movements require non-null stock bucket, transaction, and transaction-entry links"
        )

    bonded_link_constraints = {
        (row[0], tuple(row[1]), row[2], row[3], tuple(row[4]))
        for row in conn.execute(
            """
            SELECT constraint_row.contype,
                   ARRAY(
                       SELECT attribute_row.attname
                       FROM unnest(constraint_row.conkey) WITH ORDINALITY
                            AS key_column(attnum, ordinal_position)
                       JOIN pg_attribute attribute_row
                         ON attribute_row.attrelid = constraint_row.conrelid
                        AND attribute_row.attnum = key_column.attnum
                       ORDER BY key_column.ordinal_position
                   ) AS local_columns,
                   COALESCE(referenced_namespace.nspname, '') AS referenced_schema,
                   COALESCE(referenced_table.relname, '') AS referenced_table,
                   ARRAY(
                       SELECT attribute_row.attname
                       FROM unnest(COALESCE(constraint_row.confkey, ARRAY[]::smallint[]))
                            WITH ORDINALITY AS key_column(attnum, ordinal_position)
                       JOIN pg_attribute attribute_row
                         ON attribute_row.attrelid = constraint_row.confrelid
                        AND attribute_row.attnum = key_column.attnum
                       ORDER BY key_column.ordinal_position
                   ) AS referenced_columns
            FROM pg_constraint constraint_row
            LEFT JOIN pg_class referenced_table
              ON referenced_table.oid = constraint_row.confrelid
            LEFT JOIN pg_namespace referenced_namespace
              ON referenced_namespace.oid = referenced_table.relnamespace
            WHERE constraint_row.conrelid = 'dwms.bonded_inventory_movements'::regclass
              AND constraint_row.contype IN ('f','u')
              AND constraint_row.convalidated
            """
        ).fetchall()
    }
    required_bonded_constraints = {
        ('u', ('inventory_transaction_entry_id',), '', '', ()),
        (
            'f',
            ('tenant_id', 'stock_bucket_id'),
            'dwms',
            'stock_buckets',
            ('tenant_id', 'id'),
        ),
        (
            'f',
            ('tenant_id', 'inventory_transaction_id'),
            'dwms',
            'inventory_transaction_headers',
            ('tenant_id', 'id'),
        ),
        (
            'f',
            ('tenant_id', 'inventory_transaction_entry_id'),
            'dwms',
            'inventory_transaction_entries',
            ('tenant_id', 'id'),
        ),
    }
    missing_bonded_constraints = sorted(
        required_bonded_constraints - bonded_link_constraints,
        key=repr,
    )
    if missing_bonded_constraints:
        raise RuntimeError(
            "Bonded physical-ledger unique/FK constraints are missing or changed: "
            + ", ".join(repr(constraint) for constraint in missing_bonded_constraints)
        )

    invalid_bonded_definers = [
        value[0]
        for value in conn.execute(
            """
            SELECT expected.function_name
            FROM unnest(%s::text[]) AS expected(function_name)
            WHERE NOT EXISTS (
                SELECT 1
                FROM pg_proc function_row
                JOIN pg_namespace namespace_row
                  ON namespace_row.oid = function_row.pronamespace
                WHERE namespace_row.nspname = 'dwms'
                  AND function_row.proname = expected.function_name
                  AND function_row.prosecdef
                  AND EXISTS (
                      SELECT 1
                      FROM unnest(COALESCE(function_row.proconfig, ARRAY[]::text[])) setting
                      WHERE replace(setting, ' ', '') = 'search_path=pg_catalog,dwms'
                  )
            )
            ORDER BY expected.function_name
            """,
            (list(CRITICAL_BONDED_SECURITY_DEFINERS),),
        ).fetchall()
    ]
    if invalid_bonded_definers:
        raise RuntimeError(
            "Critical bonded functions require SECURITY DEFINER and a fixed search_path: "
            + ", ".join(invalid_bonded_definers)
        )

    invalid_receipt_shipping_definers = [
        value[0]
        for value in conn.execute(
            """
            SELECT expected.function_name
            FROM unnest(%s::text[]) AS expected(function_name)
            WHERE NOT EXISTS (
                SELECT 1
                FROM pg_proc function_row
                JOIN pg_namespace namespace_row
                  ON namespace_row.oid = function_row.pronamespace
                WHERE namespace_row.nspname = 'dwms'
                  AND function_row.proname = expected.function_name
                  AND function_row.prosecdef
                  AND EXISTS (
                      SELECT 1
                      FROM unnest(COALESCE(function_row.proconfig, ARRAY[]::text[])) setting
                      WHERE replace(setting, ' ', '') = 'search_path=pg_catalog,dwms'
                  )
            )
            ORDER BY expected.function_name
            """,
            (list(CRITICAL_RECEIPT_SHIPPING_SECURITY_DEFINERS),),
        ).fetchall()
    ]
    if invalid_receipt_shipping_definers:
        raise RuntimeError(
            "Critical receipt/shipping functions require SECURITY DEFINER and a fixed search_path: "
            + ", ".join(invalid_receipt_shipping_definers)
        )

    reversal_checks = conn.execute(
        """
        SELECT constraint_row.conname, table_row.relname,
               pg_get_constraintdef(constraint_row.oid)
        FROM pg_constraint constraint_row
        JOIN pg_class table_row ON table_row.oid = constraint_row.conrelid
        JOIN pg_namespace namespace_row ON namespace_row.oid = table_row.relnamespace
        WHERE namespace_row.nspname = 'dwms'
          AND constraint_row.contype = 'c'
          AND constraint_row.convalidated
          AND constraint_row.conname = ANY(%s::text[])
        """,
        (list(REQUIRED_REVERSAL_CHECKS),),
    ).fetchall()
    reversal_definitions = {
        constraint_name: (table_name, definition)
        for constraint_name, table_name, definition in reversal_checks
    }
    invalid_reversal_checks = []
    for constraint_name, table_name in REQUIRED_REVERSAL_CHECKS.items():
        actual = reversal_definitions.get(constraint_name)
        if (
            actual is None
            or actual[0] != table_name
            or "reversal_reason IS NOT NULL" not in actual[1]
            or "btrim" not in actual[1]
            or "reversed_at>=created_at"
               not in _normalize_catalog_expression(actual[1])
        ):
            invalid_reversal_checks.append(f"{table_name}.{constraint_name}")
    if invalid_reversal_checks:
        raise RuntimeError(
            "Financial reversal checks must reject NULL/blank reasons and pre-creation timestamps: "
            + ", ".join(invalid_reversal_checks)
        )

    invalid_finance_definers = [
        value[0]
        for value in conn.execute(
            """
            SELECT expected.function_name
            FROM unnest(%s::text[]) AS expected(function_name)
            WHERE NOT EXISTS (
                SELECT 1
                FROM pg_proc function_row
                JOIN pg_namespace namespace_row
                  ON namespace_row.oid = function_row.pronamespace
                WHERE namespace_row.nspname = 'dwms'
                  AND function_row.proname = expected.function_name
                  AND function_row.prosecdef
                  AND EXISTS (
                      SELECT 1
                      FROM unnest(COALESCE(function_row.proconfig, ARRAY[]::text[])) setting
                      WHERE replace(setting, ' ', '') = 'search_path=pg_catalog,dwms'
                  )
            )
            ORDER BY expected.function_name
            """,
            (list(CRITICAL_FINANCE_SECURITY_DEFINERS),),
        ).fetchall()
    ]
    if invalid_finance_definers:
        raise RuntimeError(
            "Critical finance functions require SECURITY DEFINER and a fixed search_path: "
            + ", ".join(invalid_finance_definers)
        )

    public_finance_capabilities = [
        value[0]
        for value in conn.execute(
            """
            SELECT function_row.proname
            FROM pg_proc function_row
            JOIN pg_namespace namespace_row ON namespace_row.oid = function_row.pronamespace
            WHERE namespace_row.nspname = 'dwms'
              AND function_row.proname IN (
                  'open_finance_projection_authorization',
                  'close_finance_projection_authorization',
                  'finance_projection_authorized'
              )
              AND EXISTS (
                  SELECT 1
                  FROM aclexplode(
                      COALESCE(function_row.proacl, acldefault('f', function_row.proowner))
                  ) privilege_row
                  WHERE privilege_row.grantee = 0
                    AND privilege_row.privilege_type = 'EXECUTE'
              )
            ORDER BY function_row.proname
            """
        ).fetchall()
    ]
    if public_finance_capabilities:
        raise RuntimeError(
            "Finance projection capability functions remain executable by PUBLIC: "
            + ", ".join(public_finance_capabilities)
        )

    invalid_fk_count = conn.execute(
        """
        SELECT count(*)
        FROM pg_constraint c
        JOIN pg_namespace n ON n.oid = c.connamespace
        WHERE n.nspname = 'dwms' AND c.contype = 'f' AND NOT c.convalidated
        """
    ).fetchone()[0]
    if invalid_fk_count:
        raise RuntimeError(f"Found {invalid_fk_count} unvalidated foreign keys")

    invalid_check_count = conn.execute(
        """
        SELECT count(*)
        FROM pg_constraint c
        JOIN pg_namespace n ON n.oid = c.connamespace
        WHERE n.nspname = 'dwms' AND c.contype = 'c' AND NOT c.convalidated
        """
    ).fetchone()[0]
    if invalid_check_count:
        raise RuntimeError(f"Found {invalid_check_count} unvalidated check constraints")

    required_security_checks = {
        "ck_auth_identities_provider",
        "ck_auth_identities_no_secret_metadata",
        "ck_account_link_nonce_hash",
        "ck_account_link_event_no_secrets",
        "ck_user_sessions_handle_hash",
        "ck_api_clients_secret_hash",
    }
    existing_security_checks = {
        value[0]
        for value in conn.execute(
            """
            SELECT c.conname
            FROM pg_constraint c
            JOIN pg_namespace n ON n.oid = c.connamespace
            WHERE n.nspname = 'dwms'
              AND c.contype = 'c'
              AND c.convalidated
              AND c.conname::text = ANY(%s::text[])
            """,
            (list(required_security_checks),),
        ).fetchall()
    }
    missing_security_checks = sorted(required_security_checks - existing_security_checks)
    if missing_security_checks:
        raise RuntimeError(
            "Required DWMS authentication/secret checks are missing: "
            + ", ".join(missing_security_checks)
        )

    missing_touch_triggers = [
        value[0]
        for value in conn.execute(
            """
            SELECT c.relname
            FROM pg_class c
            JOIN pg_namespace n ON n.oid = c.relnamespace
            JOIN pg_attribute row_version
              ON row_version.attrelid = c.oid
             AND row_version.attname = 'row_version'
             AND NOT row_version.attisdropped
            JOIN pg_attribute updated_at
              ON updated_at.attrelid = c.oid
             AND updated_at.attname = 'updated_at'
             AND NOT updated_at.attisdropped
            WHERE n.nspname = 'dwms'
              AND c.relkind IN ('r', 'p')
              AND NOT EXISTS (
                  SELECT 1
                  FROM pg_trigger t
                  WHERE t.tgrelid = c.oid
                    AND t.tgfoid = to_regprocedure('dwms.touch_row()')
                    AND NOT t.tgisinternal
                    AND t.tgenabled <> 'D'
                    AND (t.tgtype & 1) = 1
                    AND (t.tgtype & 2) = 2
                    AND (t.tgtype & 16) = 16
              )
            ORDER BY c.relname
            """
        ).fetchall()
    ]
    if missing_touch_triggers:
        raise RuntimeError(
            "Optimistic-lock/update timestamp triggers are missing on: "
            + ", ".join(missing_touch_triggers)
        )

    missing_tenant_immutability_triggers = [
        value[0]
        for value in conn.execute(
            """
            SELECT c.relname
            FROM pg_class c
            JOIN pg_namespace n ON n.oid = c.relnamespace
            JOIN pg_attribute tenant_column
              ON tenant_column.attrelid = c.oid
             AND tenant_column.attname = 'tenant_id'
             AND NOT tenant_column.attisdropped
            WHERE n.nspname = 'dwms'
              AND c.relkind IN ('r', 'p')
              AND NOT EXISTS (
                  SELECT 1
                  FROM pg_trigger trigger_row
                  WHERE trigger_row.tgrelid = c.oid
                    AND trigger_row.tgname = 'trg_prevent_tenant_change'
                    AND trigger_row.tgfoid = to_regprocedure('dwms.prevent_tenant_change()')
                    AND NOT trigger_row.tgisinternal
                    AND trigger_row.tgenabled <> 'D'
                    AND (trigger_row.tgtype & 1) = 1
                    AND (trigger_row.tgtype & 2) = 2
                    AND (trigger_row.tgtype & 16) = 16
              )
            ORDER BY c.relname
            """
        ).fetchall()
    ]
    if missing_tenant_immutability_triggers:
        raise RuntimeError(
            "tenant_id immutability triggers are missing or disabled on: "
            + ", ".join(missing_tenant_immutability_triggers)
        )
    if tenant_table_count != rls_table_count:
        raise RuntimeError(
            f"RLS is missing on {tenant_table_count - rls_table_count} tenant-scoped tables"
        )
    if tenant_table_count != forced_rls_table_count:
        raise RuntimeError(
            "FORCE ROW LEVEL SECURITY is missing on "
            f"{tenant_table_count - forced_rls_table_count} tenant-scoped tables"
        )

    missing_policy_count = conn.execute(
        """
        SELECT count(*)
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        JOIN pg_attribute a
          ON a.attrelid = c.oid AND a.attname = 'tenant_id' AND NOT a.attisdropped
        WHERE n.nspname = 'dwms' AND c.relkind IN ('r', 'p')
          AND (
              NOT EXISTS (
                  SELECT 1
                  FROM pg_policy p
                  WHERE p.polrelid = c.oid
                    AND p.polname = 'tenant_select'
                    AND p.polcmd = 'r'
                    AND pg_get_expr(p.polqual, p.polrelid) LIKE '%current_tenant_id()%'
              )
              OR NOT EXISTS (
                  SELECT 1
                  FROM pg_policy p
                  WHERE p.polrelid = c.oid
                    AND p.polname = 'tenant_modify'
                    AND p.polcmd = '*'
                    AND pg_get_expr(p.polqual, p.polrelid) LIKE '%current_tenant_id()%'
                    AND pg_get_expr(p.polwithcheck, p.polrelid) LIKE '%current_tenant_id()%'
              )
          )
        """
    ).fetchone()[0]
    if missing_policy_count:
        raise RuntimeError(f"Tenant policies are missing on {missing_policy_count} tables")

    global_reference_tables = [
        "roles",
        "role_permissions",
        "code_sets",
        "code_values",
        "data_retention_policies",
        "exchange_rates",
        "tax_codes",
        "tax_rates",
        "payment_terms",
        "charge_codes",
        "reason_codes",
        "inventory_statuses",
        "location_types",
        "material_handling_equipment_types",
        "lpn_types",
        "status_definitions",
        "status_transitions",
        "notification_templates",
        "scheduled_jobs",
        "bonded_storage_rules",
        "sod_rules",
        "sod_rule_conflicts",
        "kpi_definitions",
        "data_quality_rules",
    ]
    nullable_select_tables = global_reference_tables + [
        "login_events",
        "audit_events",
        "data_access_logs",
        "job_runs",
    ]
    invalid_policy_shape_count = conn.execute(
        """
        SELECT count(*)
        FROM pg_class table_row
        JOIN pg_namespace namespace_row ON namespace_row.oid = table_row.relnamespace
        JOIN pg_attribute tenant_column
          ON tenant_column.attrelid = table_row.oid
         AND tenant_column.attname = 'tenant_id'
         AND NOT tenant_column.attisdropped
        WHERE namespace_row.nspname = 'dwms'
          AND table_row.relkind IN ('r', 'p')
          AND (
              (SELECT count(*) FROM pg_policy policy_row
                WHERE policy_row.polrelid = table_row.oid) <> 2
              OR EXISTS (
                  SELECT 1 FROM pg_policy policy_row
                  WHERE policy_row.polrelid = table_row.oid
                    AND (
                        policy_row.polname NOT IN ('tenant_select', 'tenant_modify')
                        OR NOT policy_row.polpermissive
                        OR policy_row.polroles <> ARRAY[0::oid]
                        OR (policy_row.polname = 'tenant_select' AND policy_row.polcmd <> 'r')
                        OR (policy_row.polname = 'tenant_modify' AND policy_row.polcmd <> '*')
                    )
              )
              OR (
                  table_row.relname = ANY(%s::text[])
                  AND NOT EXISTS (
                      SELECT 1 FROM pg_policy policy_row
                      WHERE policy_row.polrelid = table_row.oid
                        AND policy_row.polname = 'tenant_select'
                        AND pg_get_expr(policy_row.polqual, policy_row.polrelid)
                            LIKE '%%tenant_id IS NULL%%'
                  )
              )
              OR (
                  NOT (table_row.relname = ANY(%s::text[]))
                  AND EXISTS (
                      SELECT 1 FROM pg_policy policy_row
                      WHERE policy_row.polrelid = table_row.oid
                        AND policy_row.polname = 'tenant_select'
                        AND pg_get_expr(policy_row.polqual, policy_row.polrelid)
                            LIKE '%%tenant_id IS NULL%%'
                  )
              )
          )
        """,
        (nullable_select_tables, nullable_select_tables),
    ).fetchone()[0]
    if invalid_policy_shape_count:
        raise RuntimeError(
            "Found tenant tables with extra, disabled-shape, or incorrectly global RLS policies: "
            f"{invalid_policy_shape_count}"
        )

    append_only_tables = sorted(_configured_append_only_tables(files))
    missing_append_only_guards = [
        value[0]
        for value in conn.execute(
            """
            SELECT configured.table_name
            FROM unnest(%s::text[]) AS configured(table_name)
            JOIN pg_class table_row ON table_row.relname = configured.table_name
            JOIN pg_namespace namespace_row
              ON namespace_row.oid = table_row.relnamespace
             AND namespace_row.nspname = 'dwms'
            WHERE NOT EXISTS (
                SELECT 1
                FROM pg_trigger trigger_row
                JOIN pg_proc function_row ON function_row.oid = trigger_row.tgfoid
                JOIN pg_namespace function_namespace
                  ON function_namespace.oid = function_row.pronamespace
                WHERE trigger_row.tgrelid = table_row.oid
                  AND function_namespace.nspname = 'dwms'
                  AND function_row.proname IN (
                      'prevent_append_only_change','block_immutable_change',
                      'reject_append_only_change'
                  )
                  AND NOT trigger_row.tgisinternal
                  AND trigger_row.tgenabled <> 'D'
                  AND (trigger_row.tgtype & 1) = 1
                  AND (trigger_row.tgtype & 2) = 2
                  AND (trigger_row.tgtype & 8) = 8
                  AND (trigger_row.tgtype & 16) = 16
            )
            OR NOT EXISTS (
                SELECT 1
                FROM pg_trigger trigger_row
                WHERE trigger_row.tgrelid = table_row.oid
                  AND trigger_row.tgname = 'trg_dwms_append_only_truncate'
                  AND trigger_row.tgfoid = to_regprocedure('dwms.prevent_append_only_change()')
                  AND NOT trigger_row.tgisinternal
                  AND trigger_row.tgenabled <> 'D'
                  AND (trigger_row.tgtype & 1) = 0
                  AND (trigger_row.tgtype & 2) = 2
                  AND (trigger_row.tgtype & 32) = 32
            )
            ORDER BY configured.table_name
            """,
            (append_only_tables,),
        ).fetchall()
    ]
    if missing_append_only_guards:
        raise RuntimeError(
            "Append-only UPDATE/DELETE/TRUNCATE protection is missing or disabled on: "
            + ", ".join(missing_append_only_guards)
        )

    platform_fk_count = conn.execute(
        """
        SELECT count(*)
        FROM pg_constraint c
        WHERE c.conrelid = 'dwms.users'::regclass
          AND c.conname = 'fk_dwms_users_platform_user'
          AND c.confrelid = 'kang.users'::regclass
          AND c.contype = 'f'
          AND c.convalidated
          AND c.conkey = ARRAY[(
              SELECT attnum
              FROM pg_attribute
              WHERE attrelid = 'dwms.users'::regclass
                AND attname = 'platform_user_id'
                AND NOT attisdropped
          )]::smallint[]
          AND c.confkey = ARRAY[(
              SELECT attnum
              FROM pg_attribute
              WHERE attrelid = 'kang.users'::regclass
                AND attname = 'id'
                AND NOT attisdropped
          )]::smallint[]
        """
    ).fetchone()[0]
    if platform_fk_count != 1:
        raise RuntimeError("Canonical kang.users -> dwms.users platform FK is missing")

    platform_subject_trigger_count = conn.execute(
        """
        SELECT count(*)
        FROM pg_trigger t
        WHERE t.tgrelid = 'dwms.users'::regclass
          AND t.tgname = 'trg_validate_user_platform_subject'
          AND t.tgfoid = to_regprocedure('dwms.validate_user_platform_subject()')
          AND NOT t.tgisinternal
          AND t.tgenabled <> 'D'
          AND (t.tgtype & 1) = 1
          AND (t.tgtype & 2) = 2
          AND (t.tgtype & 4) = 4
          AND (t.tgtype & 16) = 16
        """
    ).fetchone()[0]
    if platform_subject_trigger_count != 1:
        raise RuntimeError(
            "Canonical kang.users Firebase-subject validation trigger is missing or disabled"
        )

    platform_subject_mismatch_count = conn.execute(
        """
        SELECT count(*)
        FROM dwms.users dwms_user
        LEFT JOIN kang.users platform_user
          ON platform_user.id = dwms_user.platform_user_id
         AND platform_user.firebase_uid = dwms_user.firebase_uid
        WHERE platform_user.id IS NULL
        """
    ).fetchone()[0]
    if platform_subject_mismatch_count:
        raise RuntimeError(
            f"Found {platform_subject_mismatch_count} DWMS users mapped to a different "
            "canonical Firebase subject"
        )

    session_membership_fk_count = conn.execute(
        """
        SELECT count(*)
        FROM pg_constraint constraint_row
        WHERE constraint_row.conrelid = 'dwms.user_sessions'::regclass
          AND constraint_row.confrelid = 'dwms.tenant_memberships'::regclass
          AND constraint_row.contype = 'f'
          AND constraint_row.convalidated
          AND constraint_row.conkey = ARRAY[
              (SELECT attnum FROM pg_attribute
                WHERE attrelid = 'dwms.user_sessions'::regclass
                  AND attname = 'active_membership_id' AND NOT attisdropped),
              (SELECT attnum FROM pg_attribute
                WHERE attrelid = 'dwms.user_sessions'::regclass
                  AND attname = 'user_id' AND NOT attisdropped)
          ]::smallint[]
          AND constraint_row.confkey = ARRAY[
              (SELECT attnum FROM pg_attribute
                WHERE attrelid = 'dwms.tenant_memberships'::regclass
                  AND attname = 'id' AND NOT attisdropped),
              (SELECT attnum FROM pg_attribute
                WHERE attrelid = 'dwms.tenant_memberships'::regclass
                  AND attname = 'user_id' AND NOT attisdropped)
          ]::smallint[]
        """
    ).fetchone()[0]
    if session_membership_fk_count != 1:
        raise RuntimeError(
            "user_sessions active membership must belong to the same DWMS user"
        )

    firebase_subject_index_count = conn.execute(
        """
        SELECT count(*)
        FROM pg_class i
        JOIN pg_namespace n ON n.oid = i.relnamespace
        JOIN pg_index x ON x.indexrelid = i.oid
        WHERE n.nspname = 'dwms'
          AND i.relname = 'ux_users_firebase_subject'
          AND x.indrelid = 'dwms.users'::regclass
          AND x.indisunique
          AND x.indisvalid
          AND pg_get_indexdef(i.oid) LIKE '%firebase_project_id%'
          AND pg_get_indexdef(i.oid) LIKE '%firebase_tenant_id%'
          AND pg_get_indexdef(i.oid) LIKE '%firebase_uid%'
        """
    ).fetchone()[0]
    if firebase_subject_index_count != 1:
        raise RuntimeError("Canonical DWMS Firebase subject unique index is missing or invalid")

    provider_constraint = conn.execute(
        """
        SELECT pg_get_constraintdef(c.oid)
        FROM pg_constraint c
        WHERE c.conrelid = 'dwms.auth_identities'::regclass
          AND c.conname = 'ck_auth_identities_provider'
          AND c.contype = 'c'
          AND c.convalidated
        """
    ).fetchone()
    if provider_constraint is None:
        raise RuntimeError("DWMS auth identity provider constraint is missing")
    provider_definition = provider_constraint[0]
    if (
        "'password'" not in provider_definition
        or "'google.com'" not in provider_definition
        or "'firebase'" in provider_definition
        or "'custom'" in provider_definition
    ):
        raise RuntimeError(
            "DWMS auth identities must allow only password and google.com providers"
        )

    forbidden_auth_columns = conn.execute(
        """
        SELECT table_name, column_name
        FROM information_schema.columns
        WHERE table_schema = 'dwms'
          AND table_name IN (
              'users','auth_identities','account_link_requests',
              'account_link_events','user_sessions'
          )
          AND column_name IN (
              'password','password_hash','raw_password','id_token','access_token',
              'refresh_token','firebase_token','google_token','raw_token',
              'session_token','session_handle','client_secret'
          )
        ORDER BY table_name, column_name
        """
    ).fetchall()
    if forbidden_auth_columns:
        names = ", ".join(f"{table}.{column}" for table, column in forbidden_auth_columns)
        raise RuntimeError(f"Forbidden raw authentication secret columns found: {names}")

    migration_row = conn.execute(
        """
        SELECT checksum_sha256,
               catalog_checksum_sha256,
               baseline_seed_checksum_sha256
        FROM dwms.schema_migrations
        WHERE version = %s
        """,
        (MIGRATION_VERSION,),
    ).fetchone()
    if not migration_row or not migration_row[0] or migration_row[0].strip() != expected_checksum:
        raise RuntimeError("Deployed DWMS migration checksum does not match the local SQL")
    actual_catalog_checksum = _catalog_fingerprint(conn)
    if (
        not migration_row[1]
        or migration_row[1].strip() != actual_catalog_checksum
    ):
        raise RuntimeError(
            "Deployed DWMS catalog fingerprint does not match the immutable baseline"
        )
    actual_seed_checksum = _baseline_seed_fingerprint(conn)
    if (
        not migration_row[2]
        or migration_row[2].strip() != actual_seed_checksum
    ):
        raise RuntimeError(
            "Deployed DWMS baseline seed fingerprint does not match the immutable baseline"
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
        help="Read the deployed dwms catalog without running DDL.",
    )
    parser.add_argument(
        "--force-reapply",
        action="store_true",
        help="Re-run idempotent DDL even when the recorded checksum matches.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Execute and verify the full migration in one transaction, then roll it back.",
    )
    args = parser.parse_args()

    if args.verify_only and args.dry_run:
        parser.error("--verify-only and --dry-run cannot be used together")

    files = _sql_files()
    checksum = _checksum(files)

    with psycopg.connect(settings.database_url) as conn:
        if args.verify_only:
            conn.execute(
                "SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY"
            )
        _assert_actual_target(conn)
        if args.verify_only:
            conn.execute("SET LOCAL statement_timeout = '30s'")

        metadata = conn.execute(
            "SELECT current_setting('server_version_num')::integer"
        ).fetchone()
        if metadata is None or not 110000 <= metadata[0] < 120000:
            raise RuntimeError("DWMS migration requires PostgreSQL 11.x")

        if args.verify_only:
            result = _verify(conn, files, checksum)
            print(
                "DWMS verified: "
                f"PostgreSQL {result['server_version']}, "
                f"tables={result['tables']}, foreign_keys={result['foreign_keys']}, "
                f"checks={result['checks']}, indexes={result['indexes']}, "
                f"triggers={result['triggers']}, rls_tables={result['rls_tables']}"
            )
            return 0

        conn.execute("SET LOCAL lock_timeout = '10s'")
        conn.execute("SET LOCAL statement_timeout = '15min'")
        conn.execute("SELECT pg_advisory_xact_lock(hashtext('dwms_schema_migration'))")

        migration_table_exists = conn.execute(
            "SELECT to_regclass('dwms.schema_migrations') IS NOT NULL"
        ).fetchone()[0]
        migration_row = None
        recorded_migration_versions: set[str] = set()
        if migration_table_exists:
            recorded_migration_versions = {
                row[0]
                for row in conn.execute(
                    "SELECT version FROM dwms.schema_migrations ORDER BY version"
                ).fetchall()
            }
            if recorded_migration_versions not in (set(), {MIGRATION_VERSION}):
                unsupported_versions = recorded_migration_versions - {MIGRATION_VERSION}
                raise RuntimeError(
                    "The target DWMS migration history is ahead of or incompatible with "
                    "this single-baseline runner. Unsupported versions: "
                    + ", ".join(sorted(unsupported_versions))
                )
            migration_row = conn.execute(
                """
                SELECT checksum_sha256,
                       catalog_checksum_sha256,
                       baseline_seed_checksum_sha256
                FROM dwms.schema_migrations
                WHERE version = %s
                """,
                (MIGRATION_VERSION,),
            ).fetchone()

        if migration_row and (
            not migration_row[0] or migration_row[0].strip() != checksum
        ):
            raise RuntimeError(
                "The recorded DWMS migration checksum differs from the local SQL. "
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
                    WHERE n.nspname = 'dwms'
                      AND c.relkind IN ('r','p','v','m','S','f')
                    UNION ALL
                    SELECT p.oid
                    FROM pg_proc p
                    JOIN pg_namespace n ON n.oid = p.pronamespace
                    WHERE n.nspname = 'dwms'
                    UNION ALL
                    SELECT t.oid
                    FROM pg_type t
                    JOIN pg_namespace n ON n.oid = t.typnamespace
                    WHERE n.nspname = 'dwms'
                ) existing_object
                """
            ).fetchone()[0]
            if preexisting_object_count:
                raise RuntimeError(
                    "Refusing to install the DWMS baseline without its migration row into a "
                    f"non-empty dwms schema ({preexisting_object_count} user objects found)."
                )

        should_execute_baseline = bool(
            args.dry_run
            or args.force_reapply
            or not (migration_row and migration_row[0] == checksum)
        )
        if should_execute_baseline:
            # Existing deployments finish with FORCE RLS. Temporarily remove it only inside this
            # advisory-locked transaction so owner-run idempotent DDL/seeds can be replayed; any
            # error rolls this state back and module 11 restores FORCE as its final operation.
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
                        WHERE columns.table_schema = 'dwms'
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
            for path in files:
                conn.execute(path.read_text(encoding="utf-8"))

            catalog_checksum = _catalog_fingerprint(conn)
            baseline_seed_checksum = _baseline_seed_fingerprint(conn)
            conn.execute(
                """
                INSERT INTO dwms.schema_migrations
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

        # Surface every DEFERRABLE integrity failure before catalog verification and,
        # in --dry-run mode, before the transaction is explicitly rolled back.
        conn.execute("SET CONSTRAINTS ALL IMMEDIATE")
        result = _verify(conn, files, checksum)

        if args.dry_run:
            conn.rollback()
            print(
                "DWMS dry run verified and rolled back: "
                f"PostgreSQL {result['server_version']}, "
                f"tables={result['tables']}, foreign_keys={result['foreign_keys']}, "
                f"checks={result['checks']}, indexes={result['indexes']}, "
                f"triggers={result['triggers']}, rls_tables={result['rls_tables']}"
            )
            return 0

    print(
        "DWMS migration committed: "
        f"PostgreSQL {result['server_version']}, "
        f"tables={result['tables']}, foreign_keys={result['foreign_keys']}, "
        f"checks={result['checks']}, indexes={result['indexes']}, "
        f"triggers={result['triggers']}, rls_tables={result['rls_tables']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
