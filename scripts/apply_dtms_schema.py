"""Apply and verify the DTMS PostgreSQL 11 schema without exposing credentials."""

from __future__ import annotations

import argparse
import hashlib
import re
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
BACKEND_DIR = REPO_ROOT / "backend"
SQL_DIR = REPO_ROOT / "database" / "dtms"
MIGRATION_VERSION = "20260712_01_enterprise_dtms"
MIGRATION_DESCRIPTION = "Enterprise DTMS schema: IAM through planning, execution, settlement, and analytics"
TABLE_PATTERN = re.compile(r"^CREATE TABLE IF NOT EXISTS dtms\.([a-z0-9_]+)", re.MULTILINE)
INDEX_PATTERN = re.compile(
    r"^CREATE (?:UNIQUE )?INDEX IF NOT EXISTS ([a-z0-9_]+)", re.MULTILINE
)
TRIGGER_PATTERN = re.compile(
    r"^CREATE (?:CONSTRAINT )?TRIGGER ([a-z0-9_]+)", re.MULTILINE
)

sys.path.insert(0, str(BACKEND_DIR))

import psycopg  # noqa: E402
from app.settings import settings  # noqa: E402


def _sql_files() -> list[Path]:
    files = sorted(SQL_DIR.glob("[0-9][0-9]_*.sql"))
    if not files:
        raise RuntimeError(f"No DTMS SQL modules found under {SQL_DIR}")
    return files


def _checksum(files: list[Path]) -> str:
    digest = hashlib.sha256()
    for path in files:
        digest.update(path.name.encode("utf-8"))
        digest.update(b"\0")
        digest.update(path.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()


def _expected_catalog(files: list[Path]) -> tuple[set[str], set[str], set[str]]:
    sql = "\n".join(path.read_text(encoding="utf-8") for path in files)
    return (
        set(TABLE_PATTERN.findall(sql)),
        set(INDEX_PATTERN.findall(sql)),
        set(TRIGGER_PATTERN.findall(sql)),
    )


def _verify(
    conn: psycopg.Connection,
    files: list[Path],
    expected_checksum: str,
) -> dict[str, int | str]:
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
            f"DTMS migration is pinned to PostgreSQL 11; server reports {server_version}"
        )

    schema_owner = conn.execute(
        """
        SELECT pg_get_userbyid(nspowner)
        FROM pg_namespace
        WHERE nspname = 'dtms'
        """
    ).fetchone()
    if schema_owner is None:
        raise RuntimeError("dtms schema does not exist after migration")

    table_count = conn.execute(
        """
        SELECT count(*)
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'dtms' AND c.relkind = 'r'
        """
    ).fetchone()[0]
    fk_count = conn.execute(
        """
        SELECT count(*)
        FROM pg_constraint c
        JOIN pg_namespace n ON n.oid = c.connamespace
        WHERE n.nspname = 'dtms' AND c.contype = 'f'
        """
    ).fetchone()[0]
    check_count = conn.execute(
        """
        SELECT count(*)
        FROM pg_constraint c
        JOIN pg_namespace n ON n.oid = c.connamespace
        WHERE n.nspname = 'dtms' AND c.contype = 'c'
        """
    ).fetchone()[0]
    index_count = conn.execute(
        """
        SELECT count(*)
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'dtms' AND c.relkind = 'i'
        """
    ).fetchone()[0]
    trigger_count = conn.execute(
        """
        SELECT count(*)
        FROM pg_trigger t
        JOIN pg_class c ON c.oid = t.tgrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'dtms' AND NOT t.tgisinternal
        """
    ).fetchone()[0]
    tenant_table_count, rls_table_count = conn.execute(
        """
        SELECT
            count(*) FILTER (WHERE tenant_column.attname IS NOT NULL),
            count(*) FILTER (WHERE tenant_column.attname IS NOT NULL AND c.relrowsecurity)
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        LEFT JOIN pg_attribute tenant_column
          ON tenant_column.attrelid = c.oid
         AND tenant_column.attname = 'tenant_id'
         AND NOT tenant_column.attisdropped
        WHERE n.nspname = 'dtms' AND c.relkind = 'r'
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
            WHERE n.nspname = 'dtms' AND c.relkind = 'r'
            """
        ).fetchall()
    }
    missing_tables = sorted(expected_tables - existing_tables)
    if missing_tables:
        raise RuntimeError(f"Expected DTMS tables are missing: {', '.join(missing_tables)}")

    existing_indexes = {
        value[0]
        for value in conn.execute(
            """
            SELECT c.relname
            FROM pg_class c
            JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'dtms' AND c.relkind = 'i'
            """
        ).fetchall()
    }
    missing_indexes = sorted(expected_indexes - existing_indexes)
    if missing_indexes:
        raise RuntimeError(f"Expected DTMS indexes are missing: {', '.join(missing_indexes)}")

    existing_triggers = {
        value[0]
        for value in conn.execute(
            """
            SELECT DISTINCT t.tgname
            FROM pg_trigger t
            JOIN pg_class c ON c.oid = t.tgrelid
            JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'dtms' AND NOT t.tgisinternal
            """
        ).fetchall()
    }
    missing_triggers = sorted(expected_triggers - existing_triggers)
    if missing_triggers:
        raise RuntimeError(f"Expected DTMS triggers are missing: {', '.join(missing_triggers)}")

    invalid_fk_count = conn.execute(
        """
        SELECT count(*)
        FROM pg_constraint c
        JOIN pg_namespace n ON n.oid = c.connamespace
        WHERE n.nspname = 'dtms' AND c.contype = 'f' AND NOT c.convalidated
        """
    ).fetchone()[0]
    if invalid_fk_count:
        raise RuntimeError(f"Found {invalid_fk_count} unvalidated foreign keys")
    if tenant_table_count != rls_table_count:
        raise RuntimeError(
            f"RLS is missing on {tenant_table_count - rls_table_count} tenant-scoped tables"
        )

    missing_policy_count = conn.execute(
        """
        SELECT count(*)
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        JOIN pg_attribute a
          ON a.attrelid = c.oid AND a.attname = 'tenant_id' AND NOT a.attisdropped
        WHERE n.nspname = 'dtms' AND c.relkind = 'r'
          AND (
              NOT EXISTS (SELECT 1 FROM pg_policy p WHERE p.polrelid = c.oid AND p.polname = 'tenant_select')
              OR NOT EXISTS (SELECT 1 FROM pg_policy p WHERE p.polrelid = c.oid AND p.polname = 'tenant_modify')
          )
        """
    ).fetchone()[0]
    if missing_policy_count:
        raise RuntimeError(f"Tenant policies are missing on {missing_policy_count} tables")

    platform_fk_count = conn.execute(
        """
        SELECT count(*)
        FROM pg_constraint
        WHERE conrelid = 'dtms.users'::regclass
          AND conname = 'fk_dtms_users_platform_user'
          AND confrelid = 'kang.users'::regclass
          AND contype = 'f'
          AND convalidated
        """
    ).fetchone()[0]
    if platform_fk_count != 1:
        raise RuntimeError("Canonical kang.users -> dtms.users platform FK is missing")

    migration_row = conn.execute(
        """
        SELECT checksum_sha256
        FROM dtms.schema_migrations
        WHERE version = %s
        """,
        (MIGRATION_VERSION,),
    ).fetchone()
    if not migration_row or not migration_row[0] or migration_row[0].strip() != expected_checksum:
        raise RuntimeError("Deployed DTMS migration checksum does not match the local SQL")

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
        help="Read the deployed dtms catalog without running DDL.",
    )
    parser.add_argument(
        "--force-reapply",
        action="store_true",
        help="Re-run idempotent DDL even when the recorded checksum matches.",
    )
    args = parser.parse_args()

    files = _sql_files()
    checksum = _checksum(files)

    with psycopg.connect(settings.database_url) as conn:
        metadata = conn.execute(
            "SELECT current_setting('server_version_num')::integer"
        ).fetchone()
        if metadata is None or not 110000 <= metadata[0] < 120000:
            raise RuntimeError("DTMS migration requires PostgreSQL 11.x")

        if args.verify_only:
            result = _verify(conn, files, checksum)
            print(
                "DTMS verified: "
                f"PostgreSQL {result['server_version']}, "
                f"tables={result['tables']}, foreign_keys={result['foreign_keys']}, "
                f"checks={result['checks']}, indexes={result['indexes']}, "
                f"triggers={result['triggers']}, rls_tables={result['rls_tables']}"
            )
            return 0

        conn.execute("SET LOCAL lock_timeout = '10s'")
        conn.execute("SET LOCAL statement_timeout = '15min'")
        conn.execute("SELECT pg_advisory_xact_lock(hashtext('dtms_schema_migration'))")

        migration_table_exists = conn.execute(
            "SELECT to_regclass('dtms.schema_migrations') IS NOT NULL"
        ).fetchone()[0]
        migration_row = None
        if migration_table_exists:
            migration_row = conn.execute(
                """
                SELECT checksum_sha256
                FROM dtms.schema_migrations
                WHERE version = %s
                """,
                (MIGRATION_VERSION,),
            ).fetchone()

        if migration_row and migration_row[0] and migration_row[0].strip() != checksum:
            raise RuntimeError(
                "The recorded DTMS migration checksum differs from the local SQL. "
                "Create a new migration version instead of rewriting deployed history."
            )

        if not (migration_row and migration_row[0] == checksum and not args.force_reapply):
            for path in files:
                conn.execute(path.read_text(encoding="utf-8"))

            conn.execute(
                """
                INSERT INTO dtms.schema_migrations
                    (version, description, checksum_sha256, applied_at, applied_by)
                VALUES (%s, %s, %s, now(), current_user)
                ON CONFLICT (version) DO UPDATE
                SET description = EXCLUDED.description,
                    checksum_sha256 = EXCLUDED.checksum_sha256,
                    applied_at = EXCLUDED.applied_at,
                    applied_by = EXCLUDED.applied_by
                """,
                (MIGRATION_VERSION, MIGRATION_DESCRIPTION, checksum),
            )

        result = _verify(conn, files, checksum)

    print(
        "DTMS migration committed: "
        f"PostgreSQL {result['server_version']}, "
        f"tables={result['tables']}, foreign_keys={result['foreign_keys']}, "
        f"checks={result['checks']}, indexes={result['indexes']}, "
        f"triggers={result['triggers']}, rls_tables={result['rls_tables']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
