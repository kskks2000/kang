"""Apply and verify the ETMS PostgreSQL 11 schema without exposing credentials."""

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
SQL_DIR = REPO_ROOT / "database" / "etms"
FORWARD_MIGRATION_DIR = SQL_DIR / "migrations"
MIGRATION_VERSION = "20260712_01_enterprise_etms"
MIGRATION_DESCRIPTION = (
    "Enterprise ETMS schema: Firebase IAM, transportation master data, orders, "
    "rating, planning, dispatch, multimodal execution, performance, claims, "
    "settlement, accounting, workflow, integration, and analytics"
)
REQUIRED_MODULE_NUMBERS = tuple(range(12))
FORWARD_MIGRATION_ALLOWLIST = (
    (
        "20260713_02_context_fk_hardening",
        "Bind protected request and command contexts to canonical session and membership subjects",
        "20260713_02_context_fk_hardening.sql",
    ),
    (
        "20260713_03_operational_evidence_gap_closure",
        "Close operational evidence, initial status, verified POD, and evidence-file integrity gaps",
        "20260713_03_operational_evidence_gap_closure.sql",
    ),
    (
        "20260713_04_planning_dispatch_integrity",
        "Enforce order allocation, capacity, tender, assignment, dispatch, and dock integrity",
        "20260713_04_planning_dispatch_integrity.sql",
    ),
    (
        "20260713_05_finance_claim_cash_integrity",
        "Enforce journal, financial finalization, claim settlement, and COD cash integrity",
        "20260713_05_finance_claim_cash_integrity.sql",
    ),
    (
        "20260713_06_multimodal_analytics_security",
        "Harden pre-auth audit, multimodal parentage, and SCD analytics integrity",
        "20260713_06_multimodal_analytics_security.sql",
    ),
)

BASELINE_CURRENCY_CODES = (
    "KRW", "USD", "EUR", "JPY", "CNY", "GBP",
    "SGD", "VND", "INR", "AUD", "CAD", "AED",
)
BASELINE_COUNTRY_CODES = (
    "KR", "US", "CN", "JP", "DE", "FR", "GB", "NL",
    "BE", "SG", "VN", "IN", "AU", "CA", "AE",
)
BASELINE_UOM_CODES = (
    "EA", "PAL", "BOX", "CTN", "PKG", "TEU", "KG", "G", "T", "LB",
    "M3", "L", "FT3", "M", "CM", "MM", "KM", "MI", "MIN", "H", "DAY",
    "CEL", "KWH", "MJ",
)
BASELINE_TRANSPORT_MODE_CODES = (
    "ROAD", "RAIL", "AIR", "OCEAN", "INLAND_WATER", "COURIER",
    "INTERMODAL", "OTHER",
)
BASELINE_PERMISSION_CODES = (
    "iam.user.read",
    "iam.user.manage",
    "iam.role.manage",
    "master.read",
    "master.manage",
    "order.read",
    "order.create",
    "order.update",
    "order.cancel",
    "planning.read",
    "planning.manage",
    "tender.manage",
    "dispatch.read",
    "dispatch.manage",
    "execution.read",
    "execution.manage",
    "tracking.read",
    "pod.manage",
    "exception.manage",
    "claim.read",
    "claim.manage",
    "rate.read",
    "rate.manage",
    "finance.read",
    "finance.manage",
    "finance.approve",
    "invoice.manage",
    "tax_invoice.manage",
    "accounting.export",
    "analytics.read",
    "integration.manage",
    "audit.read",
    "pii.read",
    "admin.all",
)
BASELINE_SYSTEM_ROLE_CODES = (
    "TMS_ADMIN",
    "MASTER_ADMIN",
    "ORDER_OPERATOR",
    "TRANSPORT_PLANNER",
    "DISPATCHER",
    "CONTROL_TOWER",
    "DRIVER",
    "CARRIER_USER",
    "CUSTOMER_USER",
    "RATE_MANAGER",
    "SETTLEMENT_ANALYST",
    "FINANCE_APPROVER",
    "CLAIM_MANAGER",
    "ANALYST",
    "AUDITOR",
)

TABLE_PATTERN = re.compile(
    r"^CREATE TABLE IF NOT EXISTS etms\.([a-z0-9_]+)", re.MULTILINE
)
INDEX_PATTERN = re.compile(
    r"^CREATE (?:UNIQUE )?INDEX IF NOT EXISTS ([a-z0-9_]+)", re.MULTILINE
)
TRIGGER_PATTERN = re.compile(
    r"^\s*CREATE (?:CONSTRAINT )?TRIGGER\s+([a-z0-9_]+)\s+"
    r"[\s\S]*?\bON\s+etms\.([a-z0-9_]+)",
    re.MULTILINE,
)


@dataclass(frozen=True)
class SqlModule:
    """An immutable SQL module used for checksum, execution, and verification."""

    path: Path
    raw: bytes
    text: str


@dataclass(frozen=True)
class ForwardMigration:
    """An ordered forward-only migration with its immutable SQL checksum."""

    version: str
    description: str
    module: SqlModule
    checksum: str


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

    database_name, database_user, session_user, server_address, server_port = row
    if (
        database_name != REQUIRED_POSTGRES_DB
        or database_user != REQUIRED_POSTGRES_USER
        or session_user != REQUIRED_POSTGRES_USER
        or server_address != REQUIRED_POSTGRES_HOST
        or server_port != 5432
    ):
        raise RuntimeError(
            "Refusing ETMS DDL on the actual PostgreSQL target outside "
            f"{REQUIRED_POSTGRES_HOST}:5432/{REQUIRED_POSTGRES_DB} "
            f"as {REQUIRED_POSTGRES_USER}."
        )
    return database_name, database_user, session_user, server_address, server_port


def _sql_files() -> list[Path]:
    files = sorted(SQL_DIR.glob("[0-9][0-9]_*.sql"))
    if not files:
        raise RuntimeError(f"No ETMS SQL modules found under {SQL_DIR}")

    modules: dict[int, Path] = {}
    for path in files:
        match = re.fullmatch(r"(0[0-9]|1[01])_[a-z0-9_]+\.sql", path.name)
        if match is None:
            raise RuntimeError(
                f"Unexpected numbered ETMS SQL module {path.name}; "
                "expected only 00 through 11"
            )
        module_number = int(match.group(1))
        if module_number in modules:
            raise RuntimeError(
                f"Duplicate ETMS SQL module prefix {module_number:02d}: "
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
        raise RuntimeError("ETMS SQL module set is invalid: " + "; ".join(details))

    return [modules[number] for number in REQUIRED_MODULE_NUMBERS]


def _forward_migration_files() -> list[Path]:
    allowlisted_names = tuple(
        file_name for _, _, file_name in FORWARD_MIGRATION_ALLOWLIST
    )
    if len(allowlisted_names) != len(set(allowlisted_names)):
        raise RuntimeError("Duplicate ETMS forward migration file in the allowlist")
    if allowlisted_names != tuple(sorted(allowlisted_names)):
        raise RuntimeError("ETMS forward migration allowlist must be ordered by file name")

    discovered_names = tuple(
        path.name
        for path in sorted(FORWARD_MIGRATION_DIR.glob("*.sql"), key=lambda item: item.name)
    )
    if discovered_names != allowlisted_names:
        missing = sorted(set(allowlisted_names) - set(discovered_names))
        unexpected = sorted(set(discovered_names) - set(allowlisted_names))
        details: list[str] = []
        if missing:
            details.append("missing " + ", ".join(missing))
        if unexpected:
            details.append("unexpected " + ", ".join(unexpected))
        if not details:
            details.append("file order differs from the immutable allowlist")
        raise RuntimeError(
            "ETMS forward migration file set is invalid: " + "; ".join(details)
        )

    return [FORWARD_MIGRATION_DIR / file_name for file_name in allowlisted_names]


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


def _load_forward_migrations() -> tuple[ForwardMigration, ...]:
    files = _forward_migration_files()
    modules = _load_sql_modules(files)
    migrations: list[ForwardMigration] = []
    versions: list[str] = []
    for (version, description, file_name), module in zip(
        FORWARD_MIGRATION_ALLOWLIST, modules
    ):
        if module.path.name != file_name or module.path.stem != version:
            raise RuntimeError(
                f"ETMS forward migration {file_name} must use version {version}"
            )
        versions.append(version)
        migrations.append(
            ForwardMigration(
                version=version,
                description=description,
                module=module,
                checksum=_checksum((module,)),
            )
        )

    if len(versions) != len(set(versions)):
        raise RuntimeError("Duplicate ETMS forward migration version in the allowlist")
    if versions != sorted(versions):
        raise RuntimeError("ETMS forward migration versions must be strictly ordered")
    if versions and MIGRATION_VERSION >= versions[0]:
        raise RuntimeError("ETMS forward migration versions must follow the baseline")
    return tuple(migrations)


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
            ("name", "owner", "acl", "description"),
            conn.execute(
                """
                SELECT n.nspname, pg_get_userbyid(n.nspowner), n.nspacl::text,
                       obj_description(n.oid, 'pg_namespace')
                FROM pg_namespace n
                WHERE n.nspname = 'etms'
                """
            ).fetchall(),
        )
    )
    sections.append(
        (
            "relations",
            (
                "name", "kind", "persistence", "owner", "rls", "force_rls",
                "replica_identity", "options", "acl", "view_definition", "description",
            ),
            conn.execute(
                """
                SELECT c.relname, c.relkind::text, c.relpersistence::text,
                       pg_get_userbyid(c.relowner), c.relrowsecurity,
                       c.relforcerowsecurity, c.relreplident::text,
                       c.reloptions::text, c.relacl::text,
                       CASE WHEN c.relkind IN ('v','m')
                            THEN pg_get_viewdef(c.oid, true) END,
                       obj_description(c.oid, 'pg_class')
                FROM pg_class c
                JOIN pg_namespace n ON n.oid = c.relnamespace
                WHERE n.nspname = 'etms'
                  AND c.relkind IN ('r','p','v','m','S','f')
                """
            ).fetchall(),
        )
    )
    sections.append(
        (
            "columns",
            (
                "table", "position", "name", "type", "not_null", "default",
                "identity", "description",
            ),
            conn.execute(
                """
                SELECT c.relname, a.attnum::text, a.attname,
                       format_type(a.atttypid, a.atttypmod), a.attnotnull,
                       pg_get_expr(d.adbin, d.adrelid), a.attidentity::text,
                       col_description(c.oid, a.attnum)
                FROM pg_attribute a
                JOIN pg_class c ON c.oid = a.attrelid
                JOIN pg_namespace n ON n.oid = c.relnamespace
                LEFT JOIN pg_attrdef d
                  ON d.adrelid = a.attrelid AND d.adnum = a.attnum
                WHERE n.nspname = 'etms'
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
                "table", "name", "type", "deferrable", "deferred", "validated",
                "definition",
            ),
            conn.execute(
                """
                SELECT c.relname, constraint_row.conname,
                       constraint_row.contype::text,
                       constraint_row.condeferrable,
                       constraint_row.condeferred,
                       constraint_row.convalidated,
                       pg_get_constraintdef(constraint_row.oid, true)
                FROM pg_constraint constraint_row
                JOIN pg_class c ON c.oid = constraint_row.conrelid
                JOIN pg_namespace n ON n.oid = c.relnamespace
                WHERE n.nspname = 'etms'
                """
            ).fetchall(),
        )
    )
    sections.append(
        (
            "indexes",
            (
                "table", "name", "primary", "unique", "valid", "ready", "definition",
            ),
            conn.execute(
                """
                SELECT parent.relname, index_row.relname, idx.indisprimary,
                       idx.indisunique, idx.indisvalid, idx.indisready,
                       pg_get_indexdef(index_row.oid)
                FROM pg_index idx
                JOIN pg_class parent ON parent.oid = idx.indrelid
                JOIN pg_class index_row ON index_row.oid = idx.indexrelid
                JOIN pg_namespace n ON n.oid = parent.relnamespace
                WHERE n.nspname = 'etms'
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
                SELECT c.relname, trigger_row.tgname, trigger_row.tgenabled::text,
                       pg_get_triggerdef(trigger_row.oid, true),
                       function_row.proname || '(' ||
                           pg_get_function_identity_arguments(function_row.oid) || ')'
                FROM pg_trigger trigger_row
                JOIN pg_class c ON c.oid = trigger_row.tgrelid
                JOIN pg_namespace n ON n.oid = c.relnamespace
                JOIN pg_proc function_row ON function_row.oid = trigger_row.tgfoid
                WHERE n.nspname = 'etms' AND NOT trigger_row.tgisinternal
                """
            ).fetchall(),
        )
    )
    sections.append(
        (
            "functions",
            (
                "name", "arguments", "return_type", "owner", "language", "volatility",
                "security_definer", "config", "acl", "definition",
            ),
            conn.execute(
                """
                SELECT function_row.proname,
                       pg_get_function_identity_arguments(function_row.oid),
                       pg_get_function_result(function_row.oid),
                       pg_get_userbyid(function_row.proowner), language_row.lanname,
                       function_row.provolatile::text, function_row.prosecdef,
                       function_row.proconfig::text, function_row.proacl::text,
                       pg_get_functiondef(function_row.oid)
                FROM pg_proc function_row
                JOIN pg_namespace n ON n.oid = function_row.pronamespace
                JOIN pg_language language_row
                  ON language_row.oid = function_row.prolang
                WHERE n.nspname = 'etms'
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
                SELECT c.relname, policy_row.polname, policy_row.polcmd::text,
                       policy_row.polpermissive, policy_row.polroles::text,
                       pg_get_expr(policy_row.polqual, policy_row.polrelid),
                       pg_get_expr(policy_row.polwithcheck, policy_row.polrelid)
                FROM pg_policy policy_row
                JOIN pg_class c ON c.oid = policy_row.polrelid
                JOIN pg_namespace n ON n.oid = c.relnamespace
                WHERE n.nspname = 'etms'
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
                SELECT pg_get_userbyid(default_acl.defaclrole), n.nspname,
                       default_acl.defaclobjtype::text, default_acl.defaclacl::text
                FROM pg_default_acl default_acl
                JOIN pg_namespace n ON n.oid = default_acl.defaclnamespace
                WHERE n.nspname = 'etms'
                """
            ).fetchall(),
        )
    )
    return _stable_fingerprint("etms-catalog-v1", sections)


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
                FROM etms.currencies WHERE currency_code = ANY(%s::text[])
                """,
                BASELINE_CURRENCY_CODES,
            ),
        ),
        (
            "countries",
            ("code", "code3", "numeric_code", "name_en", "name_local", "currency", "active"),
            rows(
                """
                SELECT country_code::text, country_code3::text, numeric_code::text,
                       country_name_en, country_name_local,
                       default_currency_code::text, is_active::text
                FROM etms.countries WHERE country_code = ANY(%s::text[])
                """,
                BASELINE_COUNTRY_CODES,
            ),
        ),
        (
            "units_of_measure",
            ("code", "name", "dimension", "factor", "decimals", "active"),
            rows(
                """
                SELECT uom_code, uom_name, dimension, si_factor::text,
                       decimal_places::text, is_active::text
                FROM etms.units_of_measure WHERE uom_code = ANY(%s::text[])
                """,
                BASELINE_UOM_CODES,
            ),
        ),
        (
            "transport_modes",
            ("code", "name", "group", "scheduled", "active"),
            rows(
                """
                SELECT mode_code, mode_name, mode_group,
                       is_scheduled::text, is_active::text
                FROM etms.transport_modes WHERE mode_code = ANY(%s::text[])
                """,
                BASELINE_TRANSPORT_MODE_CODES,
            ),
        ),
        (
            "permissions",
            ("code", "name", "module", "action", "description", "sensitive"),
            rows(
                """
                SELECT permission_code, permission_name, module_code, action_code,
                       description, is_sensitive::text
                FROM etms.permissions WHERE permission_code = ANY(%s::text[])
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
                FROM etms.roles
                WHERE tenant_id IS NULL AND role_code = ANY(%s::text[])
                """,
                BASELINE_SYSTEM_ROLE_CODES,
            ),
        ),
        (
            "system_role_permissions",
            ("role", "permission"),
            conn.execute(
                """
                SELECT role_row.role_code, permission_row.permission_code
                FROM etms.role_permissions role_permission
                JOIN etms.roles role_row ON role_row.id = role_permission.role_id
                JOIN etms.permissions permission_row
                  ON permission_row.id = role_permission.permission_id
                WHERE role_row.tenant_id IS NULL
                  AND role_row.role_code = ANY(%s::text[])
                  AND permission_row.permission_code = ANY(%s::text[])
                """,
                (
                    list(BASELINE_SYSTEM_ROLE_CODES),
                    list(BASELINE_PERMISSION_CODES),
                ),
            ).fetchall(),
        ),
    ]
    return _stable_fingerprint("etms-baseline-seeds-v1", sections)


def _postgres_identifier(identifier: str) -> str:
    """Return the unquoted identifier PostgreSQL 11 stores in its catalog."""

    return identifier[:63]


def _expected_catalog(
    modules: tuple[SqlModule, ...],
) -> tuple[set[str], set[str], set[tuple[str, str]]]:
    sql = "\n".join(module.text for module in modules)
    return (
        {_postgres_identifier(name) for name in TABLE_PATTERN.findall(sql)},
        {_postgres_identifier(name) for name in INDEX_PATTERN.findall(sql)},
        {
            (_postgres_identifier(trigger), _postgres_identifier(table))
            for trigger, table in TRIGGER_PATTERN.findall(sql)
        },
    )


def _assert_baseline_seed_presence(conn: psycopg.Connection) -> None:
    checks: tuple[tuple[str, str, tuple[str, ...]], ...] = (
        (
            "currencies",
            "SELECT currency_code::text FROM etms.currencies WHERE currency_code = ANY(%s::text[])",
            BASELINE_CURRENCY_CODES,
        ),
        (
            "countries",
            "SELECT country_code::text FROM etms.countries WHERE country_code = ANY(%s::text[])",
            BASELINE_COUNTRY_CODES,
        ),
        (
            "units of measure",
            "SELECT uom_code FROM etms.units_of_measure WHERE uom_code = ANY(%s::text[])",
            BASELINE_UOM_CODES,
        ),
        (
            "transport modes",
            "SELECT mode_code FROM etms.transport_modes WHERE mode_code = ANY(%s::text[])",
            BASELINE_TRANSPORT_MODE_CODES,
        ),
        (
            "permissions",
            "SELECT permission_code FROM etms.permissions WHERE permission_code = ANY(%s::text[])",
            BASELINE_PERMISSION_CODES,
        ),
        (
            "system roles",
            "SELECT role_code FROM etms.roles WHERE tenant_id IS NULL AND role_code = ANY(%s::text[])",
            BASELINE_SYSTEM_ROLE_CODES,
        ),
    )
    for label, query, expected in checks:
        actual = {row[0] for row in conn.execute(query, (list(expected),)).fetchall()}
        missing = sorted(set(expected) - actual)
        if missing:
            raise RuntimeError(f"ETMS baseline {label} are missing: {', '.join(missing)}")

    roles_without_permissions = [
        row[0]
        for row in conn.execute(
            """
            SELECT role_row.role_code
            FROM etms.roles role_row
            WHERE role_row.tenant_id IS NULL
              AND role_row.role_code = ANY(%s::text[])
              AND NOT EXISTS (
                  SELECT 1 FROM etms.role_permissions role_permission
                  WHERE role_permission.role_id = role_row.id
              )
            ORDER BY role_row.role_code
            """,
            (list(BASELINE_SYSTEM_ROLE_CODES),),
        ).fetchall()
    ]
    if roles_without_permissions:
        raise RuntimeError(
            "ETMS system roles without baseline permissions: "
            + ", ".join(roles_without_permissions)
        )

    missing_admin_permissions = [
        row[0]
        for row in conn.execute(
            """
            SELECT permission_row.permission_code
            FROM etms.permissions permission_row
            WHERE permission_row.permission_code = ANY(%s::text[])
              AND NOT EXISTS (
                  SELECT 1
                  FROM etms.roles role_row
                  JOIN etms.role_permissions role_permission
                    ON role_permission.role_id = role_row.id
                  WHERE role_row.tenant_id IS NULL
                    AND role_row.role_code = 'TMS_ADMIN'
                    AND role_permission.permission_id = permission_row.id
              )
            ORDER BY permission_row.permission_code
            """,
            (list(BASELINE_PERMISSION_CODES),),
        ).fetchall()
    ]
    if missing_admin_permissions:
        raise RuntimeError(
            "TMS_ADMIN is missing baseline permissions: "
            + ", ".join(missing_admin_permissions)
        )


def _expected_migration_checksums(
    baseline_checksum: str,
    forward_migrations: tuple[ForwardMigration, ...],
) -> tuple[tuple[str, str], ...]:
    return (
        (MIGRATION_VERSION, baseline_checksum),
        *((migration.version, migration.checksum) for migration in forward_migrations),
    )


def _migration_history_rows(
    conn: psycopg.Connection,
) -> list[tuple[str, str, str | None, str | None]]:
    return conn.execute(
        """
        SELECT version, checksum_sha256,
               catalog_checksum_sha256, baseline_seed_checksum_sha256
        FROM etms.schema_migrations
        ORDER BY version
        """
    ).fetchall()


def _assert_recorded_migration_checksums(
    rows: list[tuple[str, str, str | None, str | None]],
    expected: tuple[tuple[str, str], ...],
) -> None:
    expected_by_version = dict(expected)
    for version, recorded_checksum, _, _ in rows:
        expected_checksum = expected_by_version[version]
        if not recorded_checksum or recorded_checksum.strip() != expected_checksum:
            if version == MIGRATION_VERSION:
                raise RuntimeError(
                    "Deployed ETMS baseline checksum does not match local modules 00..11. "
                    "Create a forward migration instead of rewriting deployed history."
                )
            raise RuntimeError(
                f"Deployed ETMS forward migration checksum for {version} does not "
                "match its allowlisted SQL file. Never rewrite an applied migration."
            )


def _assert_migration_history_prefix(
    rows: list[tuple[str, str, str | None, str | None]],
    expected: tuple[tuple[str, str], ...],
) -> None:
    expected_versions = [version for version, _ in expected]
    actual_versions = [row[0] for row in rows]
    if actual_versions != expected_versions[: len(actual_versions)]:
        raise RuntimeError(
            "The target ETMS migration history is ahead of, out of order, or "
            "incompatible with this runner. Expected an ordered prefix of ["
            + ", ".join(expected_versions)
            + "]; found ["
            + (", ".join(actual_versions) if actual_versions else "empty")
            + "]."
        )
    _assert_recorded_migration_checksums(rows, expected)


def _assert_current_fingerprints(
    conn: psycopg.Connection,
    row: tuple[str, str, str | None, str | None],
) -> None:
    version, _, recorded_catalog_checksum, recorded_seed_checksum = row
    actual_catalog_checksum = _catalog_fingerprint(conn)
    if (
        not recorded_catalog_checksum
        or recorded_catalog_checksum.strip() != actual_catalog_checksum
    ):
        raise RuntimeError(
            f"Deployed ETMS catalog fingerprint does not match latest migration {version}"
        )

    actual_seed_checksum = _baseline_seed_fingerprint(conn)
    if not recorded_seed_checksum or recorded_seed_checksum.strip() != actual_seed_checksum:
        raise RuntimeError(
            "Deployed ETMS baseline seed fingerprint does not match latest "
            f"migration {version}"
        )


def _assert_exact_migration_history(
    conn: psycopg.Connection,
    baseline_checksum: str,
    forward_migrations: tuple[ForwardMigration, ...],
) -> list[tuple[str, str, str | None, str | None]]:
    expected = _expected_migration_checksums(
        baseline_checksum, forward_migrations
    )
    rows = _migration_history_rows(conn)
    expected_versions = [version for version, _ in expected]
    actual_versions = [row[0] for row in rows]
    if actual_versions != expected_versions:
        prefix_matches = actual_versions == expected_versions[: len(actual_versions)]
        if prefix_matches and len(actual_versions) < len(expected_versions):
            missing_versions = expected_versions[len(actual_versions) :]
            raise RuntimeError(
                "ETMS migration history is incomplete. Expected exact ordered history ["
                + ", ".join(expected_versions)
                + "]; found ["
                + (", ".join(actual_versions) if actual_versions else "empty")
                + "]; missing ["
                + ", ".join(missing_versions)
                + "]. Run apply_etms_schema.py without --verify-only."
            )
        raise RuntimeError(
            "ETMS migration history is incompatible. Expected exact ordered history ["
            + ", ".join(expected_versions)
            + "]; found ["
            + (", ".join(actual_versions) if actual_versions else "empty")
            + "]."
        )

    _assert_recorded_migration_checksums(rows, expected)
    return rows


def _verify(
    conn: psycopg.Connection,
    modules: tuple[SqlModule, ...],
    expected_checksum: str,
    forward_migrations: tuple[ForwardMigration, ...],
) -> dict[str, int | str]:
    _assert_actual_target(conn)
    row = conn.execute(
        """
        SELECT current_database(), current_user,
               current_setting('server_version'),
               current_setting('server_version_num')::integer
        """
    ).fetchone()
    if row is None:
        raise RuntimeError("Unable to read PostgreSQL server metadata")

    database_name, database_user, server_version, server_version_num = row
    if not 110000 <= server_version_num < 120000:
        raise RuntimeError(
            f"ETMS migration is pinned to PostgreSQL 11; server reports {server_version}"
        )

    schema_owner = conn.execute(
        """
        SELECT pg_get_userbyid(nspowner)
        FROM pg_namespace
        WHERE nspname = 'etms'
        """
    ).fetchone()
    if schema_owner is None:
        raise RuntimeError("etms schema does not exist after migration")
    if schema_owner[0] != database_user:
        raise RuntimeError(
            f"etms schema owner is {schema_owner[0]!r}, "
            f"expected migration owner {database_user!r}"
        )

    migration_role_flags = conn.execute(
        "SELECT rolsuper, rolbypassrls FROM pg_roles WHERE rolname = current_user"
    ).fetchone()
    if migration_role_flags is None or migration_role_flags[0] or migration_role_flags[1]:
        raise RuntimeError("ETMS migration owner must be NOSUPERUSER and NOBYPASSRLS")

    wrong_relation_owner_count = conn.execute(
        """
        SELECT count(*)
        FROM pg_class relation
        JOIN pg_namespace namespace_row ON namespace_row.oid = relation.relnamespace
        WHERE namespace_row.nspname = 'etms'
          AND relation.relkind IN ('r','p','v','m','S','f')
          AND pg_get_userbyid(relation.relowner) <> current_user
        """
    ).fetchone()[0]
    if wrong_relation_owner_count:
        raise RuntimeError(
            f"Found {wrong_relation_owner_count} ETMS relations owned by another role"
        )

    wrong_function_owner_count = conn.execute(
        """
        SELECT count(*)
        FROM pg_proc function_row
        JOIN pg_namespace namespace_row
          ON namespace_row.oid = function_row.pronamespace
        WHERE namespace_row.nspname = 'etms'
          AND pg_get_userbyid(function_row.proowner) <> current_user
        """
    ).fetchone()[0]
    if wrong_function_owner_count:
        raise RuntimeError(
            f"Found {wrong_function_owner_count} ETMS functions owned by another role"
        )

    migration_rows = _assert_exact_migration_history(
        conn, expected_checksum, forward_migrations
    )

    table_count = conn.execute(
        """
        SELECT count(*)
        FROM pg_class relation
        JOIN pg_namespace namespace_row ON namespace_row.oid = relation.relnamespace
        WHERE namespace_row.nspname = 'etms' AND relation.relkind = 'r'
        """
    ).fetchone()[0]
    fk_count = conn.execute(
        """
        SELECT count(*)
        FROM pg_constraint constraint_row
        JOIN pg_namespace namespace_row
          ON namespace_row.oid = constraint_row.connamespace
        WHERE namespace_row.nspname = 'etms' AND constraint_row.contype = 'f'
        """
    ).fetchone()[0]
    check_count = conn.execute(
        """
        SELECT count(*)
        FROM pg_constraint constraint_row
        JOIN pg_namespace namespace_row
          ON namespace_row.oid = constraint_row.connamespace
        WHERE namespace_row.nspname = 'etms' AND constraint_row.contype = 'c'
        """
    ).fetchone()[0]
    index_count = conn.execute(
        """
        SELECT count(*)
        FROM pg_class relation
        JOIN pg_namespace namespace_row ON namespace_row.oid = relation.relnamespace
        WHERE namespace_row.nspname = 'etms' AND relation.relkind = 'i'
        """
    ).fetchone()[0]
    trigger_count = conn.execute(
        """
        SELECT count(*)
        FROM pg_trigger trigger_row
        JOIN pg_class relation ON relation.oid = trigger_row.tgrelid
        JOIN pg_namespace namespace_row ON namespace_row.oid = relation.relnamespace
        WHERE namespace_row.nspname = 'etms' AND NOT trigger_row.tgisinternal
        """
    ).fetchone()[0]
    tenant_table_count, rls_table_count, force_rls_table_count = conn.execute(
        """
        SELECT
            count(*) FILTER (WHERE tenant_column.attname IS NOT NULL),
            count(*) FILTER (
                WHERE tenant_column.attname IS NOT NULL AND relation.relrowsecurity
            ),
            count(*) FILTER (
                WHERE tenant_column.attname IS NOT NULL AND relation.relforcerowsecurity
            )
        FROM pg_class relation
        JOIN pg_namespace namespace_row ON namespace_row.oid = relation.relnamespace
        LEFT JOIN pg_attribute tenant_column
          ON tenant_column.attrelid = relation.oid
         AND tenant_column.attname = 'tenant_id'
         AND NOT tenant_column.attisdropped
        WHERE namespace_row.nspname = 'etms' AND relation.relkind = 'r'
        """
    ).fetchone()

    expected_modules = modules + tuple(
        migration.module for migration in forward_migrations
    )
    expected_tables, expected_indexes, expected_triggers = _expected_catalog(
        expected_modules
    )
    existing_tables = {
        value[0]
        for value in conn.execute(
            """
            SELECT relation.relname
            FROM pg_class relation
            JOIN pg_namespace namespace_row
              ON namespace_row.oid = relation.relnamespace
            WHERE namespace_row.nspname = 'etms' AND relation.relkind = 'r'
            """
        ).fetchall()
    }
    missing_tables = sorted(expected_tables - existing_tables)
    if missing_tables:
        raise RuntimeError(f"Expected ETMS tables are missing: {', '.join(missing_tables)}")

    existing_indexes = {
        value[0]
        for value in conn.execute(
            """
            SELECT relation.relname
            FROM pg_class relation
            JOIN pg_namespace namespace_row
              ON namespace_row.oid = relation.relnamespace
            WHERE namespace_row.nspname = 'etms' AND relation.relkind = 'i'
            """
        ).fetchall()
    }
    missing_indexes = sorted(expected_indexes - existing_indexes)
    if missing_indexes:
        raise RuntimeError(f"Expected ETMS indexes are missing: {', '.join(missing_indexes)}")

    invalid_index_count = conn.execute(
        """
        SELECT count(*)
        FROM pg_index index_row
        JOIN pg_class relation ON relation.oid = index_row.indrelid
        JOIN pg_namespace namespace_row ON namespace_row.oid = relation.relnamespace
        WHERE namespace_row.nspname = 'etms'
          AND (NOT index_row.indisvalid OR NOT index_row.indisready)
        """
    ).fetchone()[0]
    if invalid_index_count:
        raise RuntimeError(f"Found {invalid_index_count} invalid or unready ETMS indexes")

    existing_triggers = {
        (value[0], value[1])
        for value in conn.execute(
            """
            SELECT DISTINCT trigger_row.tgname, relation.relname
            FROM pg_trigger trigger_row
            JOIN pg_class relation ON relation.oid = trigger_row.tgrelid
            JOIN pg_namespace namespace_row
              ON namespace_row.oid = relation.relnamespace
            WHERE namespace_row.nspname = 'etms' AND NOT trigger_row.tgisinternal
            """
        ).fetchall()
    }
    missing_triggers = sorted(expected_triggers - existing_triggers)
    if missing_triggers:
        names = ", ".join(f"{table}.{trigger}" for trigger, table in missing_triggers)
        raise RuntimeError(f"Expected ETMS triggers are missing: {names}")

    invalid_fk_count = conn.execute(
        """
        SELECT count(*)
        FROM pg_constraint constraint_row
        JOIN pg_namespace namespace_row
          ON namespace_row.oid = constraint_row.connamespace
        WHERE namespace_row.nspname = 'etms'
          AND constraint_row.contype = 'f'
          AND NOT constraint_row.convalidated
        """
    ).fetchone()[0]
    if invalid_fk_count:
        raise RuntimeError(f"Found {invalid_fk_count} unvalidated ETMS foreign keys")

    invalid_check_count = conn.execute(
        """
        SELECT count(*)
        FROM pg_constraint constraint_row
        JOIN pg_namespace namespace_row
          ON namespace_row.oid = constraint_row.connamespace
        WHERE namespace_row.nspname = 'etms'
          AND constraint_row.contype = 'c'
          AND NOT constraint_row.convalidated
        """
    ).fetchone()[0]
    if invalid_check_count:
        raise RuntimeError(f"Found {invalid_check_count} unvalidated ETMS checks")

    if tenant_table_count != rls_table_count:
        raise RuntimeError(
            f"RLS is missing on {tenant_table_count - rls_table_count} "
            "tenant-scoped ETMS tables"
        )
    if tenant_table_count != force_rls_table_count:
        raise RuntimeError(
            "FORCE ROW LEVEL SECURITY is missing on "
            f"{tenant_table_count - force_rls_table_count} tenant-scoped ETMS tables"
        )

    unsafe_policy_tables = [
        row[0]
        for row in conn.execute(
            """
            SELECT relation.relname
            FROM pg_class relation
            JOIN pg_namespace namespace_row ON namespace_row.oid = relation.relnamespace
            JOIN pg_attribute tenant_column
              ON tenant_column.attrelid = relation.oid
             AND tenant_column.attname = 'tenant_id'
             AND NOT tenant_column.attisdropped
            WHERE namespace_row.nspname = 'etms' AND relation.relkind = 'r'
              AND (
                  NOT EXISTS (
                      SELECT 1 FROM pg_policy policy_row
                      WHERE policy_row.polrelid = relation.oid
                        AND policy_row.polname = 'tenant_select'
                        AND policy_row.polcmd = 'r'
                        AND policy_row.polpermissive
                        AND policy_row.polroles = ARRAY[0::oid]
                        AND pg_get_expr(policy_row.polqual, policy_row.polrelid)
                            LIKE '%%etms.current_tenant_id()%%'
                  )
                  OR NOT EXISTS (
                      SELECT 1 FROM pg_policy policy_row
                      WHERE policy_row.polrelid = relation.oid
                        AND policy_row.polname = 'tenant_modify'
                        AND policy_row.polcmd = '*'
                        AND policy_row.polpermissive
                        AND policy_row.polroles = ARRAY[0::oid]
                        AND pg_get_expr(policy_row.polqual, policy_row.polrelid)
                            LIKE '%%etms.current_tenant_id()%%'
                        AND pg_get_expr(policy_row.polwithcheck, policy_row.polrelid)
                            LIKE '%%etms.current_tenant_id()%%'
                  )
              )
            ORDER BY relation.relname
            """
        ).fetchall()
    ]
    if unsafe_policy_tables:
        raise RuntimeError(
            "Missing or unsafe tenant_select/tenant_modify policies on: "
            + ", ".join(unsafe_policy_tables)
        )

    missing_tenant_immutability = [
        row[0]
        for row in conn.execute(
            """
            SELECT relation.relname
            FROM pg_class relation
            JOIN pg_namespace namespace_row ON namespace_row.oid = relation.relnamespace
            JOIN pg_attribute tenant_column
              ON tenant_column.attrelid = relation.oid
             AND tenant_column.attname = 'tenant_id'
             AND NOT tenant_column.attisdropped
            WHERE namespace_row.nspname = 'etms' AND relation.relkind = 'r'
              AND NOT EXISTS (
                  SELECT 1
                  FROM pg_trigger trigger_row
                  WHERE trigger_row.tgrelid = relation.oid
                    AND NOT trigger_row.tgisinternal
                    AND trigger_row.tgenabled IN ('O','A')
                    AND trigger_row.tgfoid =
                        to_regprocedure('etms.prevent_tenant_change()')
                    AND (trigger_row.tgtype & 1) = 1
                    AND (trigger_row.tgtype & 2) = 2
                    AND (trigger_row.tgtype & 16) = 16
              )
            ORDER BY relation.relname
            """
        ).fetchall()
    ]
    if missing_tenant_immutability:
        raise RuntimeError(
            "tenant_id immutability protection is missing or disabled on: "
            + ", ".join(missing_tenant_immutability)
        )

    disabled_trigger_count = conn.execute(
        """
        SELECT count(*)
        FROM pg_trigger trigger_row
        JOIN pg_class relation ON relation.oid = trigger_row.tgrelid
        JOIN pg_namespace namespace_row ON namespace_row.oid = relation.relnamespace
        WHERE namespace_row.nspname = 'etms'
          AND NOT trigger_row.tgisinternal
          AND trigger_row.tgenabled = 'D'
        """
    ).fetchone()[0]
    if disabled_trigger_count:
        raise RuntimeError(f"Found {disabled_trigger_count} disabled ETMS triggers")

    unindexed_fk_rows = conn.execute(
        """
        SELECT relation.relname, constraint_row.conname
        FROM pg_constraint constraint_row
        JOIN pg_class relation ON relation.oid = constraint_row.conrelid
        JOIN pg_namespace namespace_row ON namespace_row.oid = relation.relnamespace
        WHERE namespace_row.nspname = 'etms'
          AND constraint_row.contype = 'f'
          AND NOT EXISTS (
              SELECT 1
              FROM pg_index index_row
              WHERE index_row.indrelid = constraint_row.conrelid
                AND index_row.indisvalid
                AND index_row.indisready
                AND index_row.indpred IS NULL
                AND (index_row.indkey::smallint[])
                        [0:array_length(constraint_row.conkey, 1) - 1]
                    = constraint_row.conkey
          )
        ORDER BY relation.relname, constraint_row.conname
        """
    ).fetchall()
    if unindexed_fk_rows:
        names = ", ".join(f"{table}.{fk}" for table, fk in unindexed_fk_rows)
        raise RuntimeError(f"Foreign keys without a valid leading index: {names}")

    platform_fk_count = conn.execute(
        """
        SELECT count(*)
        FROM pg_constraint constraint_row
        WHERE constraint_row.conrelid = 'etms.users'::regclass
          AND constraint_row.conname = 'fk_etms_users_platform_user'
          AND constraint_row.confrelid = 'kang.users'::regclass
          AND constraint_row.contype = 'f'
          AND constraint_row.convalidated
          AND constraint_row.conkey = ARRAY[(
              SELECT attribute.attnum
              FROM pg_attribute attribute
              WHERE attribute.attrelid = 'etms.users'::regclass
                AND attribute.attname = 'platform_user_id'
                AND NOT attribute.attisdropped
          )]::smallint[]
          AND constraint_row.confkey = ARRAY[(
              SELECT attribute.attnum
              FROM pg_attribute attribute
              WHERE attribute.attrelid = 'kang.users'::regclass
                AND attribute.attname = 'id'
                AND NOT attribute.attisdropped
          )]::smallint[]
        """
    ).fetchone()[0]
    if platform_fk_count != 1:
        raise RuntimeError("Canonical kang.users -> etms.users platform FK is missing")

    forbidden_secret_columns = conn.execute(
        """
        SELECT table_name, column_name
        FROM information_schema.columns
        WHERE table_schema = 'etms'
          AND lower(regexp_replace(column_name, '[^a-zA-Z0-9]', '', 'g')) IN (
              'password','passwordhash','hashedpassword','rawpassword',
              'idtoken','accesstoken','refreshtoken','firebasetoken','googletoken',
              'rawtoken','sessiontoken','sessionhandle','clientsecret','privatekey',
              'cvv','cvc','pannumber','cardnumber','trackdata','pinblock'
          )
        ORDER BY table_name, column_name
        """
    ).fetchall()
    if forbidden_secret_columns:
        names = ", ".join(f"{table}.{column}" for table, column in forbidden_secret_columns)
        raise RuntimeError(f"Forbidden raw secret columns found: {names}")

    unsafe_security_definer_count = conn.execute(
        """
        SELECT count(*)
        FROM pg_proc function_row
        JOIN pg_namespace namespace_row
          ON namespace_row.oid = function_row.pronamespace
        WHERE namespace_row.nspname = 'etms'
          AND function_row.prosecdef
          AND NOT EXISTS (
              SELECT 1
              FROM unnest(function_row.proconfig) config
              WHERE regexp_replace(config, '[[:space:]]', '', 'g') =
                    'search_path=pg_catalog,etms,pg_temp'
          )
        """
    ).fetchone()[0]
    if unsafe_security_definer_count:
        raise RuntimeError(
            f"Found {unsafe_security_definer_count} ETMS SECURITY DEFINER functions "
            "without the safe pg_catalog, etms, pg_temp search_path"
        )

    _assert_baseline_seed_presence(conn)

    _assert_current_fingerprints(conn, migration_rows[-1])

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


def _record_migration(
    conn: psycopg.Connection,
    version: str,
    description: str,
    checksum: str,
) -> tuple[str, str, str, str]:
    catalog_checksum = _catalog_fingerprint(conn)
    baseline_seed_checksum = _baseline_seed_fingerprint(conn)
    conn.execute(
        """
        INSERT INTO etms.schema_migrations
            (
                version, description, checksum_sha256,
                catalog_checksum_sha256, baseline_seed_checksum_sha256,
                applied_at, applied_by
            )
        VALUES (%s, %s, %s, %s, %s, now(), current_user)
        """,
        (
            version,
            description,
            checksum,
            catalog_checksum,
            baseline_seed_checksum,
        ),
    )
    return version, checksum, catalog_checksum, baseline_seed_checksum


def _assert_empty_schema_for_new_baseline(conn: psycopg.Connection) -> None:
    preexisting_object_count = conn.execute(
        """
        SELECT count(*)
        FROM (
            SELECT relation.oid
            FROM pg_class relation
            JOIN pg_namespace namespace_row
              ON namespace_row.oid = relation.relnamespace
            WHERE namespace_row.nspname = 'etms'
              AND relation.relkind IN ('r','p','v','m','S','f','c')
            UNION ALL
            SELECT function_row.oid
            FROM pg_proc function_row
            JOIN pg_namespace namespace_row
              ON namespace_row.oid = function_row.pronamespace
            WHERE namespace_row.nspname = 'etms'
            UNION ALL
            SELECT type_row.oid
            FROM pg_type type_row
            JOIN pg_namespace namespace_row
              ON namespace_row.oid = type_row.typnamespace
            WHERE namespace_row.nspname = 'etms'
        ) existing_object
        """
    ).fetchone()[0]
    if preexisting_object_count:
        raise RuntimeError(
            "Refusing to install the ETMS baseline without its migration row into a "
            f"non-empty etms schema ({preexisting_object_count} user objects found)."
        )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--verify-only",
        action="store_true",
        help="Read the deployed etms catalog without running DDL.",
    )
    parser.add_argument(
        "--force-reapply",
        action="store_true",
        help="Re-run idempotent DDL even when the recorded checksum matches.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help=(
            "Execute and verify missing allowlisted migrations in one transaction, "
            "then roll it back. Combine with --force-reapply for a full replay."
        ),
    )
    args = parser.parse_args()

    if args.verify_only and args.dry_run:
        parser.error("--verify-only and --dry-run cannot be used together")
    if args.verify_only and args.force_reapply:
        parser.error("--verify-only and --force-reapply cannot be used together")

    files = _sql_files()
    modules = _load_sql_modules(files)
    checksum = _checksum(modules)
    forward_migrations = _load_forward_migrations()
    expected_migrations = _expected_migration_checksums(
        checksum, forward_migrations
    )

    with psycopg.connect(settings.database_url) as conn:
        if args.verify_only:
            conn.execute("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY")

        _assert_actual_target(conn)
        metadata = conn.execute(
            "SELECT current_setting('server_version_num')::integer"
        ).fetchone()
        if metadata is None or not 110000 <= metadata[0] < 120000:
            raise RuntimeError("ETMS migration requires PostgreSQL 11.x")

        if args.verify_only:
            conn.execute("SET LOCAL statement_timeout = '30s'")
            result = _verify(conn, modules, checksum, forward_migrations)
            print(
                "ETMS verified: "
                f"PostgreSQL {result['server_version']}, "
                f"tables={result['tables']}, foreign_keys={result['foreign_keys']}, "
                f"checks={result['checks']}, indexes={result['indexes']}, "
                f"triggers={result['triggers']}, rls_tables={result['rls_tables']}"
            )
            return 0

        conn.execute("SET LOCAL lock_timeout = '10s'")
        conn.execute("SET LOCAL statement_timeout = '15min'")
        conn.execute("SELECT pg_advisory_xact_lock(hashtext('etms_schema_migration'))")

        migration_table_exists = conn.execute(
            "SELECT to_regclass('etms.schema_migrations') IS NOT NULL"
        ).fetchone()[0]
        recorded_rows: list[tuple[str, str, str | None, str | None]] = []
        if migration_table_exists:
            migration_columns = {
                row[0]
                for row in conn.execute(
                    """
                    SELECT column_name
                    FROM information_schema.columns
                    WHERE table_schema = 'etms' AND table_name = 'schema_migrations'
                    """
                ).fetchall()
            }
            required_migration_columns = {
                "version",
                "checksum_sha256",
                "catalog_checksum_sha256",
                "baseline_seed_checksum_sha256",
            }
            missing_migration_columns = sorted(
                required_migration_columns - migration_columns
            )
            if missing_migration_columns:
                raise RuntimeError(
                    "Existing ETMS migration ledger is incompatible; missing columns: "
                    + ", ".join(missing_migration_columns)
                )

            recorded_rows = _migration_history_rows(conn)
            _assert_migration_history_prefix(recorded_rows, expected_migrations)

        baseline_is_recorded = bool(recorded_rows)
        if not baseline_is_recorded:
            _assert_empty_schema_for_new_baseline(conn)

        should_execute_baseline = bool(
            args.force_reapply or not baseline_is_recorded
        )
        if should_execute_baseline:
            # Existing deployments finish with FORCE RLS.  Temporarily remove FORCE only
            # inside this advisory-locked transaction so owner-run idempotent seeds can be
            # replayed.  Module 11 must restore FORCE, and any error rolls this back.
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
                        WHERE columns.table_schema = 'etms'
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

            if not baseline_is_recorded:
                recorded_rows.append(
                    _record_migration(
                        conn,
                        MIGRATION_VERSION,
                        MIGRATION_DESCRIPTION,
                        checksum,
                    )
                )

        if recorded_rows and len(recorded_rows) < len(expected_migrations):
            # Never let a new forward row bless catalog or seed drift in the latest
            # already-recorded state. A force replay may repair idempotent baseline
            # objects first, but must still reproduce the recorded fingerprint here.
            _assert_current_fingerprints(conn, recorded_rows[-1])

        for migration_index, migration in enumerate(forward_migrations, start=1):
            migration_is_recorded = migration_index < len(recorded_rows)
            should_execute_forward = bool(
                args.force_reapply or not migration_is_recorded
            )
            if should_execute_forward:
                conn.execute(migration.module.text)

            if not migration_is_recorded:
                recorded_rows.append(
                    _record_migration(
                        conn,
                        migration.version,
                        migration.description,
                        migration.checksum,
                    )
                )

        conn.execute("SET CONSTRAINTS ALL IMMEDIATE")
        result = _verify(
            conn, modules, checksum, forward_migrations
        )

        if args.dry_run:
            conn.rollback()
            print(
                "ETMS dry run verified and rolled back: "
                f"PostgreSQL {result['server_version']}, "
                f"tables={result['tables']}, foreign_keys={result['foreign_keys']}, "
                f"checks={result['checks']}, indexes={result['indexes']}, "
                f"triggers={result['triggers']}, rls_tables={result['rls_tables']}"
            )
            return 0

    print(
        "ETMS migration committed: "
        f"PostgreSQL {result['server_version']}, "
        f"tables={result['tables']}, foreign_keys={result['foreign_keys']}, "
        f"checks={result['checks']}, indexes={result['indexes']}, "
        f"triggers={result['triggers']}, rls_tables={result['rls_tables']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
