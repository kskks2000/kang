"""Rollback-only DOMS integrity smoke tests without exposing credentials."""

from __future__ import annotations

import hashlib
import sys
from collections.abc import Callable
from pathlib import Path
from uuid import uuid4


REPO_ROOT = Path(__file__).resolve().parents[1]
BACKEND_DIR = REPO_ROOT / "backend"
sys.path.insert(0, str(REPO_ROOT))
sys.path.insert(0, str(BACKEND_DIR))

import psycopg  # noqa: E402
from app.settings import settings  # noqa: E402
from scripts.apply_doms_schema import _assert_actual_target  # noqa: E402


def _clear_request_context(conn: psycopg.Connection) -> None:
    conn.execute(
        """
        DELETE FROM doms.request_contexts
        WHERE backend_pid = pg_backend_pid()
          AND transaction_id = txid_current()
        """
    )


def _bind_session(conn: psycopg.Connection, session_handle_hash: str, tenant_id: object) -> None:
    bound_tenant = conn.execute(
        "SELECT doms.bind_request_context(%s)", (session_handle_hash,)
    ).fetchone()[0]
    if bound_tenant != tenant_id:
        raise AssertionError(f"Unexpected bound tenant: {bound_tenant}")


def _expect_database_rejection(
    conn: psycopg.Connection,
    savepoint_name: str,
    operation: Callable[[], None],
    expected_sqlstates: set[str],
) -> None:
    conn.execute(f"SAVEPOINT {savepoint_name}")
    try:
        operation()
    except psycopg.Error as error:
        conn.execute(f"ROLLBACK TO SAVEPOINT {savepoint_name}")
        conn.execute(f"RELEASE SAVEPOINT {savepoint_name}")
        if error.sqlstate not in expected_sqlstates:
            raise AssertionError(
                f"Unexpected SQLSTATE for {savepoint_name}: {error.sqlstate}; "
                f"expected one of {sorted(expected_sqlstates)}"
            ) from error
        return
    conn.execute(f"ROLLBACK TO SAVEPOINT {savepoint_name}")
    conn.execute(f"RELEASE SAVEPOINT {savepoint_name}")
    raise AssertionError(f"Expected database rejection did not occur: {savepoint_name}")


def main() -> int:
    suffix = uuid4().hex[:12]

    with psycopg.connect(settings.database_url) as conn:
        _assert_actual_target(conn)
        version_num = conn.execute(
            "SELECT current_setting('server_version_num')::integer"
        ).fetchone()[0]
        if not 110000 <= version_num < 120000:
            raise RuntimeError("DOMS smoke tests require PostgreSQL 11.x")
        if not conn.execute(
            "SELECT EXISTS (SELECT 1 FROM doms.schema_migrations)"
        ).fetchone()[0]:
            raise RuntimeError("DOMS baseline is not deployed")

        conn.execute(
            "SELECT set_config('doms.tenant_id', '00000000-0000-0000-0000-000000000001', true)"
        )
        if conn.execute(
            "SELECT doms.current_tenant_id(), doms.current_doms_user_id()"
        ).fetchone() != (None, None):
            raise AssertionError("Legacy tenant GUC spoofed the protected request context")

        platform_user = conn.execute(
            """
            SELECT platform_user.id, platform_user.firebase_uid,
                   COALESCE(identity_row.provider_code, 'password'),
                   COALESCE(identity_row.provider_subject, platform_user.firebase_uid)
            FROM kang.users platform_user
            LEFT JOIN doms.users doms_user
              ON doms_user.platform_user_id = platform_user.id
            LEFT JOIN LATERAL (
                SELECT identity.provider_code, identity.provider_subject
                FROM doms.auth_identities identity
                WHERE identity.user_id = doms_user.id
                  AND identity.disabled_at IS NULL
                ORDER BY (identity.provider_code = 'password') DESC, identity.created_at, identity.id
                LIMIT 1
            ) identity_row ON true
            WHERE platform_user.firebase_uid IS NOT NULL
              AND platform_user.status::text = 'active'
              AND platform_user.is_active
              AND platform_user.deleted_at IS NULL
              AND platform_user.locked_at IS NULL
              AND (doms_user.id IS NULL OR identity_row.provider_code IS NOT NULL)
            ORDER BY (doms_user.id IS NULL) DESC, platform_user.created_at, platform_user.id
            LIMIT 1
            """
        ).fetchone()
        if platform_user is None:
            raise RuntimeError("A canonical kang.users Firebase principal is required")

        doms_user_id = conn.execute(
            "SELECT doms.bootstrap_firebase_identity(%s, %s, %s, %s)",
            (platform_user[0], platform_user[1], platform_user[2], platform_user[3]),
        ).fetchone()[0]

        tenant_a = conn.execute(
            """
            INSERT INTO doms.tenants (tenant_code, tenant_name)
            VALUES (%s, %s)
            RETURNING id
            """,
            (f"SMOKE_A_{suffix}", "DOMS smoke tenant A"),
        ).fetchone()[0]
        tenant_b = conn.execute(
            """
            INSERT INTO doms.tenants (tenant_code, tenant_name)
            VALUES (%s, %s)
            RETURNING id
            """,
            (f"SMOKE_B_{suffix}", "DOMS smoke tenant B"),
        ).fetchone()[0]

        membership_a = conn.execute(
            """
            SELECT doms.provision_tenant_membership(
                %s, %s, 'DOMS_SMOKE', %s, NULL,
                'TEST', statement_timestamp(),
                statement_timestamp() + interval '4 hours', NULL
            )
            """,
            (platform_user[0], tenant_a, f"MEMBERSHIP_A_{suffix}"),
        ).fetchone()[0]
        conn.execute(
            """
            SELECT doms.provision_tenant_membership(
                %s, %s, 'DOMS_SMOKE', %s, NULL,
                'TEST', statement_timestamp(),
                statement_timestamp() + interval '4 hours', NULL
            )
            """,
            (platform_user[0], tenant_b, f"MEMBERSHIP_B_{suffix}"),
        ).fetchone()

        session_hash_a = hashlib.sha256(f"DOMS-A-{suffix}".encode()).hexdigest()
        session_hash_b = hashlib.sha256(f"DOMS-B-{suffix}".encode()).hexdigest()
        session_a = conn.execute(
            """
            SELECT doms.issue_user_session(
                %s, %s, %s, %s, %s, %s,
                statement_timestamp(), statement_timestamp() + interval '2 hours',
                'SINGLE_FACTOR', NULL, 'DOMS rollback smoke'
            )
            """,
            (
                platform_user[0], platform_user[1], platform_user[2], platform_user[3],
                session_hash_a, tenant_a,
            ),
        ).fetchone()[0]
        conn.execute(
            """
            SELECT doms.issue_user_session(
                %s, %s, %s, %s, %s, %s,
                statement_timestamp(), statement_timestamp() + interval '2 hours',
                'SINGLE_FACTOR', NULL, 'DOMS rollback smoke'
            )
            """,
            (
                platform_user[0], platform_user[1], platform_user[2], platform_user[3],
                session_hash_b, tenant_b,
            ),
        ).fetchone()

        _bind_session(conn, session_hash_a, tenant_a)
        if conn.execute(
            "SELECT doms.current_tenant_id(), doms.current_doms_user_id()"
        ).fetchone() != (tenant_a, doms_user_id):
            raise AssertionError("Protected request context did not bind tenant and user")
        _expect_database_rejection(
            conn,
            "request_context_switch",
            lambda: conn.execute("SELECT doms.bind_request_context(%s)", (session_hash_b,)),
            {"25001"},
        )

        organization_a = conn.execute(
            """
            INSERT INTO doms.organizations
                (tenant_id, organization_code, organization_name)
            VALUES (%s, %s, %s)
            RETURNING id
            """,
            (tenant_a, f"ORG_{suffix}", "DOMS smoke organization"),
        ).fetchone()[0]
        partner_a = conn.execute(
            """
            INSERT INTO doms.business_partners
                (tenant_id, partner_code, partner_name)
            VALUES (%s, %s, %s)
            RETURNING id
            """,
            (tenant_a, f"PARTNER_A_{suffix}", "DOMS smoke partner A"),
        ).fetchone()[0]

        _clear_request_context(conn)
        _bind_session(conn, session_hash_b, tenant_b)
        partner_b = conn.execute(
            """
            INSERT INTO doms.business_partners
                (tenant_id, partner_code, partner_name)
            VALUES (%s, %s, %s)
            RETURNING id
            """,
            (tenant_b, f"PARTNER_B_{suffix}", "DOMS smoke partner B"),
        ).fetchone()[0]

        _clear_request_context(conn)
        _bind_session(conn, session_hash_a, tenant_a)
        visible_partner_count = conn.execute(
            "SELECT count(*) FROM doms.business_partners WHERE id IN (%s, %s)",
            (partner_a, partner_b),
        ).fetchone()[0]
        if visible_partner_count != 1:
            raise AssertionError("RLS did not isolate the second tenant's partner")

        _expect_database_rejection(
            conn,
            "cross_tenant_partner",
            lambda: conn.execute(
                """
                INSERT INTO doms.brands
                    (tenant_id, brand_code, brand_name, owner_partner_id)
                VALUES (%s, %s, %s, %s)
                """,
                (tenant_a, f"BAD_BRAND_{suffix}", "Cross-tenant brand", partner_b),
            ),
            {"23503"},
        )
        _expect_database_rejection(
            conn,
            "tenant_rekey",
            lambda: conn.execute(
                "UPDATE doms.business_partners SET tenant_id = %s WHERE id = %s",
                (tenant_b, partner_a),
            ),
            {"23514"},
        )

        audit_event_id = conn.execute(
            """
            INSERT INTO doms.audit_events
                (tenant_id, action_code, entity_type, entity_id)
            VALUES (%s, 'SMOKE_CREATED', 'business_partner', %s)
            RETURNING id
            """,
            (tenant_a, partner_a),
        ).fetchone()[0]
        _expect_database_rejection(
            conn,
            "append_only_audit",
            lambda: conn.execute(
                "UPDATE doms.audit_events SET action_code = 'TAMPERED' WHERE id = %s",
                (audit_event_id,),
            ),
            {"55000"},
        )
        _expect_database_rejection(
            conn,
            "json_secret_key",
            lambda: conn.execute(
                """
                INSERT INTO doms.audit_events
                    (tenant_id, action_code, before_data_masked)
                VALUES (%s, 'BAD_SECRET', '{"access_token":"prohibited"}'::jsonb)
                """,
                (tenant_a,),
            ),
            {"23514"},
        )

        legal_hold_id = conn.execute(
            """
            INSERT INTO doms.legal_holds
                (tenant_id, hold_no, hold_name, reason, effective_at, created_by)
            VALUES (%s, %s, %s, %s, now(), %s)
            RETURNING id
            """,
            (
                tenant_a,
                f"HOLD_{suffix}",
                "DOMS smoke legal hold",
                "Rollback-only integrity test",
                doms_user_id,
            ),
        ).fetchone()[0]
        conn.execute(
            """
            INSERT INTO doms.legal_hold_entities
                (tenant_id, legal_hold_id, entity_type, entity_id, applied_by)
            VALUES (%s, %s, 'business_partner', %s, %s)
            """,
            (tenant_a, legal_hold_id, partner_a, doms_user_id),
        )
        retention_policy_id = conn.execute(
            """
            SELECT id FROM doms.data_retention_policies
            WHERE tenant_id IS NULL AND entity_type = 'orders'
            """
        ).fetchone()[0]
        disposal_run_id = conn.execute(
            """
            INSERT INTO doms.data_disposal_runs (
                tenant_id, run_no, data_retention_policy_id, entity_type,
                cutoff_at, dry_run, requested_by
            )
            VALUES (%s, %s, %s, 'business_partner', now(), true, %s)
            RETURNING id
            """,
            (tenant_a, f"DISPOSE_{suffix}", retention_policy_id, doms_user_id),
        ).fetchone()[0]
        _expect_database_rejection(
            conn,
            "active_legal_hold",
            lambda: conn.execute(
                """
                INSERT INTO doms.data_disposal_results (
                    tenant_id, data_disposal_run_id, entity_type, entity_id,
                    action_taken, status, record_count
                )
                VALUES (%s, %s, 'business_partner', %s, 'DELETE', 'COMPLETED', 1)
                """,
                (tenant_a, disposal_run_id, partner_a),
            ),
            {"23514"},
        )
        disposal_result_id = conn.execute(
            """
            INSERT INTO doms.data_disposal_results (
                tenant_id, data_disposal_run_id, entity_type, entity_id,
                action_taken, status, record_count, legal_hold_id
            )
            VALUES (%s, %s, 'business_partner', %s, 'NONE',
                    'SKIPPED_LEGAL_HOLD', 0, %s)
            RETURNING id
            """,
            (tenant_a, disposal_run_id, partner_a, legal_hold_id),
        ).fetchone()[0]
        _expect_database_rejection(
            conn,
            "append_only_disposal",
            lambda: conn.execute(
                "UPDATE doms.data_disposal_results SET record_count = 1 WHERE id = %s",
                (disposal_result_id,),
            ),
            {"55000"},
        )

        period_id = conn.execute(
            """
            INSERT INTO doms.accounting_periods (
                tenant_id, organization_id, fiscal_year, period_no,
                period_name, start_date, end_date
            )
            VALUES (%s, %s, 2099, 1, 'Smoke period', '2099-01-01', '2099-12-31')
            RETURNING id
            """,
            (tenant_a, organization_a),
        ).fetchone()[0]
        debit_account_id = conn.execute(
            """
            INSERT INTO doms.gl_accounts (
                tenant_id, organization_id, account_code, account_name,
                account_type, normal_balance
            )
            VALUES (%s, %s, %s, 'Smoke cash', 'ASSET', 'DEBIT')
            RETURNING id
            """,
            (tenant_a, organization_a, f"CASH_{suffix}"),
        ).fetchone()[0]
        credit_account_id = conn.execute(
            """
            INSERT INTO doms.gl_accounts (
                tenant_id, organization_id, account_code, account_name,
                account_type, normal_balance
            )
            VALUES (%s, %s, %s, 'Smoke revenue', 'REVENUE', 'CREDIT')
            RETURNING id
            """,
            (tenant_a, organization_a, f"REV_{suffix}"),
        ).fetchone()[0]
        batch_id = conn.execute(
            """
            INSERT INTO doms.journal_batches (
                tenant_id, batch_no, organization_id, accounting_period_id,
                source_module, status, approved_by, approved_at
            )
            VALUES (%s, %s, %s, %s, 'MANUAL', 'APPROVED', %s, now())
            RETURNING id
            """,
            (tenant_a, f"BATCH_{suffix}", organization_a, period_id, doms_user_id),
        ).fetchone()[0]
        entry_id = conn.execute(
            """
            INSERT INTO doms.journal_entries (
                tenant_id, journal_batch_id, entry_no, entry_date,
                currency_code, description
            )
            VALUES (%s, %s, 1, '2099-01-01', 'KRW', 'Smoke entry')
            RETURNING id
            """,
            (tenant_a, batch_id),
        ).fetchone()[0]
        debit_line_id = conn.execute(
            """
            INSERT INTO doms.journal_lines (
                tenant_id, journal_entry_id, line_no, gl_account_id,
                debit_amount, currency_code
            )
            VALUES (%s, %s, 1, %s, 100, 'KRW')
            RETURNING id
            """,
            (tenant_a, entry_id, debit_account_id),
        ).fetchone()[0]
        _expect_database_rejection(
            conn,
            "unbalanced_journal",
            lambda: conn.execute(
                """
                UPDATE doms.journal_entries
                SET status = 'POSTED', posted_by = %s, posted_at = now()
                WHERE id = %s
                """,
                (doms_user_id, entry_id),
            ),
            {"23514"},
        )
        conn.execute(
            """
            INSERT INTO doms.journal_lines (
                tenant_id, journal_entry_id, line_no, gl_account_id,
                credit_amount, currency_code
            )
            VALUES (%s, %s, 2, %s, 100, 'KRW')
            """,
            (tenant_a, entry_id, credit_account_id),
        )
        posted_totals = conn.execute(
            """
            UPDATE doms.journal_entries
            SET status = 'POSTED', posted_by = %s, posted_at = now()
            WHERE id = %s
            RETURNING total_debit, total_credit
            """,
            (doms_user_id, entry_id),
        ).fetchone()
        if posted_totals != (100, 100):
            raise AssertionError(f"Unexpected posted journal totals: {posted_totals}")
        _expect_database_rejection(
            conn,
            "posted_journal_mutation",
            lambda: conn.execute(
                "UPDATE doms.journal_lines SET debit_amount = 99 WHERE id = %s",
                (debit_line_id,),
            ),
            {"55000"},
        )

        conn.execute("SAVEPOINT membership_suspension")
        conn.execute(
            "UPDATE doms.tenant_memberships SET status = 'SUSPENDED' WHERE id = %s",
            (membership_a,),
        )
        revoked_status = conn.execute(
            "SELECT session_status FROM doms.user_sessions WHERE id = %s",
            (session_a,),
        ).fetchone()[0]
        if revoked_status != "REVOKED":
            raise AssertionError("Membership suspension did not revoke its active session")
        _expect_database_rejection(
            conn,
            "revoked_session_bind",
            lambda: conn.execute(
                "SELECT doms.bind_request_context(%s)", (session_hash_a,)
            ),
            {"28000"},
        )
        conn.execute("ROLLBACK TO SAVEPOINT membership_suspension")
        conn.execute("RELEASE SAVEPOINT membership_suspension")

        critical_tables = (
            "sales_orders",
            "inventory_positions",
            "payment_captures",
            "fulfillment_order_lines",
            "return_request_lines",
            "journal_entries",
        )
        missing_trigger_tables = [
            row[0]
            for row in conn.execute(
                """
                SELECT requested.table_name
                FROM unnest(%s::text[]) requested(table_name)
                WHERE NOT EXISTS (
                    SELECT 1
                    FROM pg_trigger trigger_row
                    JOIN pg_class relation ON relation.oid = trigger_row.tgrelid
                    JOIN pg_namespace namespace_row ON namespace_row.oid = relation.relnamespace
                    WHERE namespace_row.nspname = 'doms'
                      AND relation.relname = requested.table_name
                      AND NOT trigger_row.tgisinternal
                )
                """,
                (list(critical_tables),),
            ).fetchall()
        ]
        if missing_trigger_tables:
            raise AssertionError(
                "Critical tables lack integrity triggers: "
                + ", ".join(missing_trigger_tables)
            )

        tenant_tables, rls_tables, force_rls_tables = conn.execute(
            """
            SELECT count(*),
                   count(*) FILTER (WHERE relation.relrowsecurity),
                   count(*) FILTER (WHERE relation.relforcerowsecurity)
            FROM pg_class relation
            JOIN pg_namespace namespace_row ON namespace_row.oid = relation.relnamespace
            JOIN pg_attribute tenant_column
              ON tenant_column.attrelid = relation.oid
             AND tenant_column.attname = 'tenant_id'
             AND NOT tenant_column.attisdropped
            WHERE namespace_row.nspname = 'doms' AND relation.relkind = 'r'
            """
        ).fetchone()
        if tenant_tables != rls_tables or tenant_tables != force_rls_tables:
            raise AssertionError("RLS/FORCE RLS coverage changed during smoke testing")

        conn.rollback()

    print(
        "DOMS rollback smoke tests passed: "
        "protected session/RLS context, GUC and cross-tenant rejection, "
        "JSON secret guard, append-only, legal hold, session auto-revocation, "
        "balanced journal posting, and posted-ledger immutability."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
