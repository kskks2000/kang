"""Rollback-only ETMS integrity smoke tests without exposing credentials or PII."""

from __future__ import annotations

import argparse
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
from scripts.apply_etms_schema import (  # noqa: E402
    MIGRATION_DESCRIPTION,
    MIGRATION_VERSION,
    _assert_actual_target,
    _assert_current_fingerprints,
    _assert_empty_schema_for_new_baseline,
    _assert_migration_history_prefix,
    _checksum,
    _expected_migration_checksums,
    _load_forward_migrations,
    _load_sql_modules,
    _migration_history_rows,
    _record_migration,
    _sql_files,
    _verify,
)


def _clear_request_context(conn: psycopg.Connection) -> None:
    conn.execute(
        """
        DELETE FROM etms.request_contexts
        WHERE backend_pid = pg_backend_pid()
          AND transaction_id = txid_current()
        """
    )


def _bind_session(
    conn: psycopg.Connection, session_handle_hash: str, expected_tenant_id: object
) -> None:
    bound_tenant_id = conn.execute(
        "SELECT etms.bind_request_context(%s)", (session_handle_hash,)
    ).fetchone()[0]
    if bound_tenant_id != expected_tenant_id:
        raise AssertionError("Protected request context bound an unexpected tenant")
    if conn.execute("SELECT etms.current_tenant_id()").fetchone()[0] != expected_tenant_id:
        raise AssertionError("Protected request context did not project the bound tenant")


def _expect_database_rejection(
    conn: psycopg.Connection,
    savepoint_name: str,
    operation: Callable[[], object],
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


def _run_forward_control_probes(
    conn: psycopg.Connection, suffix: str
) -> set[str]:
    """Exercise security, analytics, and multimodal forward-migration controls."""

    login_event_id = conn.execute(
        "SELECT etms.record_preauth_login_event(%s,%s,%s,%s,%s,%s,%s,%s)",
        (
            f"ROLLBACK_PROBE_{suffix}",
            "password",
            False,
            "INVALID_CREDENTIAL",
            "masked rollback probe",
            None,
            "ETMS rollback smoke",
            f"PREAUTH_{suffix}",
        ),
    ).fetchone()[0]
    audit_event_id = conn.execute(
        "SELECT etms.record_preauth_security_audit(%s,%s,%s,%s,%s)",
        (
            "AUTH.PRECHECK.REJECTED",
            "masked rollback probe",
            None,
            "ETMS rollback smoke",
            f"PREAUTH_{suffix}",
        ),
    ).fetchone()[0]
    evidence_visible = conn.execute(
        """
        SELECT EXISTS (SELECT 1 FROM etms.login_events WHERE id = %s),
               EXISTS (SELECT 1 FROM etms.audit_events WHERE id = %s)
        """,
        (login_event_id, audit_event_id),
    ).fetchone()
    if evidence_visible != (True, True):
        raise AssertionError("Pre-authentication audit evidence was not recorded")
    _expect_database_rejection(
        conn,
        "preauth_secret_rejection",
        lambda: conn.execute(
            "SELECT etms.record_preauth_security_audit(%s,%s)",
            ("AUTH.PRECHECK.REJECTED", "password=not-allowed"),
        ),
        {"23514"},
    )

    conn.execute(
        """
        CREATE TEMPORARY TABLE etms_scd_probe (
            id uuid PRIMARY KEY,
            tenant_id uuid NOT NULL,
            source_id uuid NOT NULL,
            effective_from timestamptz NOT NULL,
            effective_to timestamptz
        ) ON COMMIT DROP
        """
    )
    conn.execute(
        """
        CREATE TRIGGER trg_etms_scd_probe
        BEFORE INSERT OR UPDATE ON etms_scd_probe
        FOR EACH ROW EXECUTE PROCEDURE
            etms.prevent_scd_interval_overlap('source_id')
        """
    )
    probe_tenant_id = uuid4()
    probe_source_id = uuid4()
    conn.execute(
        """
        INSERT INTO etms_scd_probe
            (id, tenant_id, source_id, effective_from, effective_to)
        VALUES (%s, %s, %s, '2099-01-01', '2099-02-01')
        """,
        (uuid4(), probe_tenant_id, probe_source_id),
    )
    _expect_database_rejection(
        conn,
        "scd_interval_overlap",
        lambda: conn.execute(
            """
            INSERT INTO etms_scd_probe
                (id, tenant_id, source_id, effective_from, effective_to)
            VALUES (%s, %s, %s, '2099-01-15', '2099-03-01')
            """,
            (uuid4(), probe_tenant_id, probe_source_id),
        ),
        {"23P01"},
    )

    multimodal_probes = (
        (
            "parcel_parentage_probe",
            "CREATE TEMPORARY TABLE etms_parcel_parentage_probe "
            "(tenant_id uuid, order_id uuid, shipment_id uuid) ON COMMIT DROP",
            "CREATE TRIGGER trg_probe BEFORE INSERT OR UPDATE ON "
            "etms_parcel_parentage_probe FOR EACH ROW EXECUTE PROCEDURE "
            "etms.validate_parcel_shipment_parentage()",
            "INSERT INTO etms_parcel_parentage_probe VALUES (%s,%s,%s)",
            (uuid4(), uuid4(), uuid4()),
        ),
        (
            "package_parentage_probe",
            "CREATE TEMPORARY TABLE etms_package_parentage_probe "
            "(tenant_id uuid, parcel_shipment_id uuid, handling_unit_id uuid) "
            "ON COMMIT DROP",
            "CREATE TRIGGER trg_probe BEFORE INSERT OR UPDATE ON "
            "etms_package_parentage_probe FOR EACH ROW EXECUTE PROCEDURE "
            "etms.validate_parcel_package_parentage()",
            "INSERT INTO etms_package_parentage_probe VALUES (%s,%s,%s)",
            (uuid4(), uuid4(), uuid4()),
        ),
        (
            "ocean_parentage_probe",
            "CREATE TEMPORARY TABLE etms_ocean_parentage_probe "
            "(tenant_id uuid, ocean_voyage_id uuid, carrier_booking_id uuid, "
            "shipment_id uuid) ON COMMIT DROP",
            "CREATE TRIGGER trg_probe BEFORE INSERT OR UPDATE ON "
            "etms_ocean_parentage_probe FOR EACH ROW EXECUTE PROCEDURE "
            "etms.validate_ocean_bill_parentage()",
            "INSERT INTO etms_ocean_parentage_probe VALUES (%s,NULL,%s,NULL)",
            (uuid4(), uuid4()),
        ),
        (
            "air_parentage_probe",
            "CREATE TEMPORARY TABLE etms_air_parentage_probe "
            "(tenant_id uuid, air_flight_id uuid, shipment_id uuid, "
            "carrier_booking_id uuid, issuing_carrier_partner_id uuid, "
            "origin_airport_id uuid, destination_airport_id uuid) ON COMMIT DROP",
            "CREATE TRIGGER trg_probe BEFORE INSERT OR UPDATE ON "
            "etms_air_parentage_probe FOR EACH ROW EXECUTE PROCEDURE "
            "etms.validate_air_waybill_parentage()",
            "INSERT INTO etms_air_parentage_probe "
            "VALUES (%s,NULL,NULL,%s,%s,%s,%s)",
            (uuid4(), uuid4(), uuid4(), uuid4(), uuid4()),
        ),
        (
            "rail_parentage_probe",
            "CREATE TEMPORARY TABLE etms_rail_parentage_probe "
            "(tenant_id uuid, rail_consist_id uuid, rail_car_id uuid) ON COMMIT DROP",
            "CREATE TRIGGER trg_probe BEFORE INSERT OR UPDATE ON "
            "etms_rail_parentage_probe FOR EACH ROW EXECUTE PROCEDURE "
            "etms.validate_rail_waybill_parentage()",
            "INSERT INTO etms_rail_parentage_probe VALUES (%s,%s,%s)",
            (uuid4(), uuid4(), uuid4()),
        ),
    )
    for savepoint_name, create_table, create_trigger, insert_sql, params in (
        multimodal_probes
    ):
        conn.execute(create_table)
        conn.execute(create_trigger)
        _expect_database_rejection(
            conn,
            savepoint_name,
            lambda insert_sql=insert_sql, params=params: conn.execute(
                insert_sql, params
            ),
            {"23514"},
        )

    return {"preauth_audit", "scd_interval", "multimodal_parentage"}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--with-baseline-dry-run",
        action="store_true",
        help=(
            "Require an empty etms schema, install and verify the local 00..11 "
            "baseline in this transaction, run smoke tests, then roll everything back."
        ),
    )
    parser.add_argument(
        "--with-pending-forward-dry-run",
        action="store_true",
        help=(
            "Apply only allowlisted forward migrations missing from the deployed "
            "ETMS history, run all smoke tests, and roll the transaction back."
        ),
    )
    args = parser.parse_args()
    if args.with_baseline_dry_run and args.with_pending_forward_dry_run:
        parser.error(
            "--with-baseline-dry-run and --with-pending-forward-dry-run "
            "cannot be used together"
        )
    suffix = uuid4().hex[:12]
    passed_checks: set[str] = set()
    catalog_counts: dict[str, int | str] = {}

    with psycopg.connect(settings.database_url) as conn:
        try:
            _assert_actual_target(conn)
            version_num = conn.execute(
                "SELECT current_setting('server_version_num')::integer"
            ).fetchone()[0]
            if not 110000 <= version_num < 120000:
                raise RuntimeError("ETMS smoke tests require PostgreSQL 11.x")

            modules = _load_sql_modules(_sql_files())
            checksum = _checksum(modules)
            forward_migrations = _load_forward_migrations()
            if args.with_baseline_dry_run:
                _assert_empty_schema_for_new_baseline(conn)
                conn.execute("SET LOCAL lock_timeout = '10s'")
                conn.execute("SET LOCAL statement_timeout = '15min'")
                conn.execute(
                    "SELECT pg_advisory_xact_lock(hashtext('etms_schema_migration'))"
                )
                for module in modules:
                    conn.execute(module.text)

                _record_migration(
                    conn,
                    MIGRATION_VERSION,
                    MIGRATION_DESCRIPTION,
                    checksum,
                )
                for migration in forward_migrations:
                    conn.execute(migration.module.text)
                    _record_migration(
                        conn,
                        migration.version,
                        migration.description,
                        migration.checksum,
                    )
                conn.execute("SET CONSTRAINTS ALL IMMEDIATE")
            elif args.with_pending_forward_dry_run:
                conn.execute("SET LOCAL lock_timeout = '10s'")
                conn.execute("SET LOCAL statement_timeout = '15min'")
                conn.execute(
                    "SELECT pg_advisory_xact_lock(hashtext('etms_schema_migration'))"
                )
                expected_migrations = _expected_migration_checksums(
                    checksum, forward_migrations
                )
                recorded_rows = _migration_history_rows(conn)
                _assert_migration_history_prefix(
                    recorded_rows, expected_migrations
                )
                if not recorded_rows:
                    raise RuntimeError(
                        "The ETMS baseline must be deployed before a pending-forward "
                        "smoke dry run"
                    )
                _assert_current_fingerprints(conn, recorded_rows[-1])
                first_missing_forward = len(recorded_rows) - 1
                for migration in forward_migrations[first_missing_forward:]:
                    conn.execute(migration.module.text)
                    _record_migration(
                        conn,
                        migration.version,
                        migration.description,
                        migration.checksum,
                    )
                conn.execute("SET CONSTRAINTS ALL IMMEDIATE")

            catalog_counts = _verify(
                conn, modules, checksum, forward_migrations
            )
            conn.execute("SET CONSTRAINTS ALL DEFERRED")
            passed_checks.add("immutable_baseline")
            passed_checks.update(_run_forward_control_probes(conn, suffix))

            platform_user = conn.execute(
                """
                SELECT platform_user.id, platform_user.firebase_uid
                FROM kang.users platform_user
                WHERE platform_user.firebase_uid IS NOT NULL
                  AND platform_user.status::text = 'active'
                  AND platform_user.is_active
                  AND platform_user.deleted_at IS NULL
                  AND platform_user.locked_at IS NULL
                  AND NOT EXISTS (
                      SELECT 1
                      FROM etms.users etms_user
                      WHERE etms_user.platform_user_id = platform_user.id
                  )
                ORDER BY platform_user.created_at, platform_user.id
                LIMIT 1
                """
            ).fetchone()
            if platform_user is None:
                raise RuntimeError(
                    "An active canonical kang.users principal not yet mapped to ETMS is required"
                )

            tenant_a = conn.execute(
                """
                INSERT INTO etms.tenants (
                    tenant_code, tenant_name, status, activated_at
                )
                VALUES (%s, %s, 'ACTIVE', statement_timestamp())
                RETURNING id
                """,
                (f"SMOKE_A_{suffix}", "ETMS smoke tenant A"),
            ).fetchone()[0]
            tenant_b = conn.execute(
                """
                INSERT INTO etms.tenants (
                    tenant_code, tenant_name, status, activated_at
                )
                VALUES (%s, %s, 'ACTIVE', statement_timestamp())
                RETURNING id
                """,
                (f"SMOKE_B_{suffix}", "ETMS smoke tenant B"),
            ).fetchone()[0]

            etms_user_id = conn.execute(
                """
                INSERT INTO etms.users (
                    firebase_project_id, firebase_uid, platform_user_id, status
                )
                VALUES ('kang-84cdd', %s, %s, 'ACTIVE')
                RETURNING id
                """,
                (platform_user[1], platform_user[0]),
            ).fetchone()[0]
            conn.execute(
                """
                INSERT INTO etms.auth_identities (
                    user_id, provider_code, provider_subject,
                    last_authenticated_at, metadata
                )
                VALUES (
                    %s, 'password', %s, statement_timestamp(),
                    '{"source":"rollback_smoke"}'::jsonb
                )
                """,
                (etms_user_id, platform_user[1]),
            )

            membership_a = conn.execute(
                """
                SELECT etms.provision_tenant_membership(
                    %s, %s, %s, 'EMPLOYEE', %s,
                    statement_timestamp() - interval '1 minute',
                    statement_timestamp() + interval '4 hours'
                )
                """,
                (tenant_a, etms_user_id, etms_user_id, f"EMP_A_{suffix}"),
            ).fetchone()[0]
            conn.execute(
                """
                SELECT etms.provision_tenant_membership(
                    %s, %s, %s, 'EMPLOYEE', %s,
                    statement_timestamp() - interval '1 minute',
                    statement_timestamp() + interval '4 hours'
                )
                """,
                (tenant_b, etms_user_id, etms_user_id, f"EMP_B_{suffix}"),
            ).fetchone()

            session_hash_a = hashlib.sha256(f"ETMS-A-{suffix}".encode()).hexdigest()
            session_hash_b = hashlib.sha256(f"ETMS-B-{suffix}".encode()).hexdigest()
            conn.execute(
                """
                SELECT etms.issue_auth_session(
                    %s, %s, 'password', %s, %s, %s,
                    statement_timestamp(), statement_timestamp() + interval '2 hours',
                    'SINGLE_FACTOR', NULL, 'ETMS rollback smoke'
                )
                """,
                (
                    platform_user[0],
                    platform_user[1],
                    platform_user[1],
                    session_hash_a,
                    tenant_a,
                ),
            ).fetchone()
            conn.execute(
                """
                DELETE FROM etms.session_issue_contexts
                WHERE backend_pid = pg_backend_pid()
                  AND transaction_id = txid_current()
                """
            )
            conn.execute(
                """
                SELECT etms.issue_auth_session(
                    %s, %s, 'password', %s, %s, %s,
                    statement_timestamp(), statement_timestamp() + interval '2 hours',
                    'SINGLE_FACTOR', NULL, 'ETMS rollback smoke'
                )
                """,
                (
                    platform_user[0],
                    platform_user[1],
                    platform_user[1],
                    session_hash_b,
                    tenant_b,
                ),
            ).fetchone()

            conn.execute(
                "SELECT set_config('etms.tenant_id', %s, true)", (str(tenant_a),)
            )
            if conn.execute("SELECT etms.current_tenant_id()").fetchone()[0] is not None:
                raise AssertionError("Legacy tenant GUC spoofed the protected request context")

            _bind_session(conn, session_hash_a, tenant_a)
            if conn.execute("SELECT etms.current_etms_user_id()").fetchone()[0] != etms_user_id:
                raise AssertionError("Protected request context did not project the ETMS user")
            _expect_database_rejection(
                conn,
                "request_context_switch",
                lambda: conn.execute(
                    "SELECT etms.bind_request_context(%s)", (session_hash_b,)
                ),
                {"25001"},
            )
            passed_checks.add("protected_context")

            _clear_request_context(conn)
            _bind_session(conn, session_hash_b, tenant_b)
            partner_b = conn.execute(
                """
                INSERT INTO etms.business_partners (
                    tenant_id, partner_code, partner_name, country_code
                )
                VALUES (%s, %s, %s, 'KR')
                RETURNING id
                """,
                (tenant_b, f"PARTNER_B_{suffix}", "ETMS smoke partner B"),
            ).fetchone()[0]

            _clear_request_context(conn)
            _bind_session(conn, session_hash_a, tenant_a)
            organization_a = conn.execute(
                """
                INSERT INTO etms.organizations (
                    tenant_id, organization_code, organization_name,
                    country_code, base_currency_code
                )
                VALUES (%s, %s, %s, 'KR', 'KRW')
                RETURNING id
                """,
                (tenant_a, f"ORG_{suffix}", "ETMS smoke organization"),
            ).fetchone()[0]
            conn.execute(
                """
                UPDATE etms.tenant_memberships
                SET organization_id = %s
                WHERE id = %s
                """,
                (organization_a, membership_a),
            )
            customer_a = conn.execute(
                """
                INSERT INTO etms.business_partners (
                    tenant_id, partner_code, partner_name, country_code
                )
                VALUES (%s, %s, %s, 'KR')
                RETURNING id
                """,
                (tenant_a, f"CUSTOMER_{suffix}", "ETMS smoke customer"),
            ).fetchone()[0]
            carrier_a = conn.execute(
                """
                INSERT INTO etms.business_partners (
                    tenant_id, partner_code, partner_name, country_code
                )
                VALUES (%s, %s, %s, 'KR')
                RETURNING id
                """,
                (tenant_a, f"CARRIER_{suffix}", "ETMS smoke carrier"),
            ).fetchone()[0]
            conn.execute(
                """
                INSERT INTO etms.partner_roles (tenant_id, partner_id, role_code)
                VALUES (%s, %s, 'CUSTOMER')
                """,
                (tenant_a, customer_a),
            )
            conn.execute(
                """
                INSERT INTO etms.partner_roles (tenant_id, partner_id, role_code)
                VALUES (%s, %s, 'CARRIER')
                """,
                (tenant_a, carrier_a),
            )

            if conn.execute(
                "SELECT count(*) FROM etms.business_partners WHERE id IN (%s, %s)",
                (customer_a, partner_b),
            ).fetchone()[0] != 1:
                raise AssertionError("RLS did not isolate the second tenant's partner")
            _expect_database_rejection(
                conn,
                "cross_tenant_reference",
                lambda: conn.execute(
                    """
                    INSERT INTO etms.partner_relationships (
                        tenant_id, parent_partner_id, child_partner_id,
                        relationship_type
                    )
                    VALUES (%s, %s, %s, 'SMOKE_LINK')
                    """,
                    (tenant_a, customer_a, partner_b),
                ),
                {"23503", "23514", "42501"},
            )
            passed_checks.add("tenant_isolation")
            _expect_database_rejection(
                conn,
                "tenant_mutation",
                lambda: conn.execute(
                    "UPDATE etms.business_partners SET tenant_id = %s WHERE id = %s",
                    (tenant_b, customer_a),
                ),
                {"23514"},
            )
            passed_checks.add("tenant_immutability")

            address_a = conn.execute(
                """
                INSERT INTO etms.addresses (
                    tenant_id, country_code, postal_code, city, line1, timezone
                )
                VALUES (%s, 'KR', '00000', 'Seoul', 'Rollback smoke address', 'Asia/Seoul')
                RETURNING id
                """,
                (tenant_a,),
            ).fetchone()[0]
            location_a = conn.execute(
                """
                INSERT INTO etms.locations (
                    tenant_id, location_code, location_name, location_type,
                    address_id, timezone
                )
                VALUES (%s, %s, %s, 'WAREHOUSE', %s, 'Asia/Seoul')
                RETURNING id
                """,
                (tenant_a, f"LOC_{suffix}", "ETMS smoke location", address_a),
            ).fetchone()[0]
            dock_a = conn.execute(
                """
                INSERT INTO etms.location_docks (
                    tenant_id, location_id, dock_code, dock_name, dock_type
                )
                VALUES (%s, %s, %s, %s, 'GENERAL')
                RETURNING id
                """,
                (tenant_a, location_a, f"DOCK_{suffix}", "ETMS smoke dock"),
            ).fetchone()[0]
            address_snapshot_a = conn.execute(
                """
                INSERT INTO etms.address_snapshots (
                    tenant_id, address_id, country_code, postal_code,
                    city, line1, timezone
                )
                VALUES (%s, %s, 'KR', '00000', 'Seoul', 'Rollback smoke address', 'Asia/Seoul')
                RETURNING id
                """,
                (tenant_a, address_a),
            ).fetchone()[0]

            order_a = conn.execute(
                """
                INSERT INTO etms.transport_orders (
                    tenant_id, order_no, current_revision_no, organization_id,
                    customer_id, mode_code, requested_pickup_from,
                    requested_pickup_to, requested_delivery_from,
                    requested_delivery_to, total_quantity, quantity_uom_code,
                    total_weight_kg, total_volume_m3, status, created_by
                )
                VALUES (
                    %s, %s, 2, %s, %s, 'ROAD',
                    statement_timestamp() + interval '1 hour',
                    statement_timestamp() + interval '2 hours',
                    statement_timestamp() + interval '3 hours',
                    statement_timestamp() + interval '4 hours',
                    10, 'EA', 10, 1, 'DRAFT', %s
                )
                RETURNING id
                """,
                (tenant_a, f"ORDER_{suffix}", organization_a, customer_a, etms_user_id),
            ).fetchone()[0]
            other_order = conn.execute(
                """
                INSERT INTO etms.transport_orders (
                    tenant_id, order_no, current_revision_no, organization_id,
                    customer_id, mode_code, total_quantity,
                    quantity_uom_code, total_weight_kg, total_volume_m3,
                    status, created_by
                )
                VALUES (
                    %s, %s, 1, %s, %s, 'ROAD', 1, 'EA', 1, 0,
                    'DRAFT', %s
                )
                RETURNING id
                """,
                (
                    tenant_a,
                    f"OTHER_ORDER_{suffix}",
                    organization_a,
                    customer_a,
                    etms_user_id,
                ),
            ).fetchone()[0]
            revision_1 = conn.execute(
                """
                INSERT INTO etms.transport_order_revisions (
                    tenant_id, order_id, revision_no, change_type, snapshot,
                    requested_by
                )
                VALUES (%s, %s, 1, 'CREATE', '{"revision":1}'::jsonb, %s)
                RETURNING id
                """,
                (tenant_a, other_order, etms_user_id),
            ).fetchone()[0]
            revision_2 = conn.execute(
                """
                INSERT INTO etms.transport_order_revisions (
                    tenant_id, order_id, revision_no, change_type, snapshot,
                    requested_by
                )
                VALUES (%s, %s, 2, 'OPERATIONAL_CHANGE', '{"revision":2}'::jsonb, %s)
                RETURNING id
                """,
                (tenant_a, order_a, etms_user_id),
            ).fetchone()[0]
            order_line_a = conn.execute(
                """
                INSERT INTO etms.transport_order_lines (
                    tenant_id, order_id, line_no, item_description, quantity,
                    quantity_uom_code, gross_weight_kg, volume_m3
                )
                VALUES (%s, %s, 1, 'Rollback smoke item', 10, 'EA', 10, 1)
                RETURNING id
                """,
                (tenant_a, order_a),
            ).fetchone()[0]
            scenario_a = conn.execute(
                """
                INSERT INTO etms.planning_scenarios (
                    tenant_id, scenario_no, scenario_name,
                    planning_horizon_from, planning_horizon_to, created_by
                )
                VALUES (
                    %s, %s, %s, statement_timestamp(),
                    statement_timestamp() + interval '1 day', %s
                )
                RETURNING id
                """,
                (tenant_a, f"SCENARIO_{suffix}", "ETMS smoke scenario", etms_user_id),
            ).fetchone()[0]
            _expect_database_rejection(
                conn,
                "scenario_revision_mismatch",
                lambda: conn.execute(
                    """
                    INSERT INTO etms.planning_scenario_orders (
                        tenant_id, scenario_id, order_id, order_revision_id
                    )
                    VALUES (%s, %s, %s, %s)
                    """,
                    (tenant_a, scenario_a, order_a, revision_1),
                ),
                {"23514"},
            )
            conn.execute(
                """
                INSERT INTO etms.planning_scenario_orders (
                    tenant_id, scenario_id, order_id, order_revision_id
                )
                VALUES (%s, %s, %s, %s)
                """,
                (tenant_a, scenario_a, order_a, revision_2),
            )
            passed_checks.add("scenario_revision")

            shipment_a = conn.execute(
                """
                INSERT INTO etms.shipments (
                    tenant_id, shipment_no, planning_scenario_id,
                    organization_id, customer_id, primary_mode_code,
                    origin_location_id, destination_location_id,
                    planned_pickup_at, planned_delivery_at, total_quantity,
                    quantity_uom_code, total_weight_kg, total_volume_m3,
                    created_by
                )
                VALUES (
                    %s, %s, %s, %s, %s, 'ROAD', %s, %s,
                    statement_timestamp() + interval '1 hour',
                    statement_timestamp() + interval '4 hours',
                    10, 'EA', 10, 1, %s
                )
                RETURNING id
                """,
                (
                    tenant_a,
                    f"SHIPMENT_{suffix}",
                    scenario_a,
                    organization_a,
                    customer_a,
                    location_a,
                    location_a,
                    etms_user_id,
                ),
            ).fetchone()[0]
            conn.execute(
                """
                INSERT INTO etms.shipment_orders (
                    tenant_id, shipment_id, order_id, allocation_quantity,
                    allocation_weight_kg, allocation_volume_m3,
                    allocation_percent
                )
                VALUES (%s, %s, %s, 10, 10, 1, 100)
                """,
                (tenant_a, shipment_a, order_a),
            )
            _expect_database_rejection(
                conn,
                "shipment_allocation_overflow",
                lambda: conn.execute(
                    "UPDATE etms.transport_orders SET total_quantity = 9 WHERE id = %s",
                    (order_a,),
                ),
                {"23514"},
            )
            passed_checks.add("shipment_allocation_limit")
            run_a = conn.execute(
                """
                INSERT INTO etms.transport_runs (
                    tenant_id, run_no, organization_id, service_date,
                    mode_code, start_location_id, end_location_id,
                    planned_start_at, planned_end_at, total_weight_kg,
                    total_volume_m3, capacity_weight_kg, capacity_volume_m3,
                    capacity_pallets, created_by
                )
                VALUES (
                    %s, %s, %s, CURRENT_DATE, 'ROAD', %s, %s,
                    statement_timestamp() + interval '1 hour',
                    statement_timestamp() + interval '5 hours',
                    10, 1, 100, 10, 2, %s
                )
                RETURNING id
                """,
                (
                    tenant_a,
                    f"RUN_{suffix}",
                    organization_a,
                    location_a,
                    location_a,
                    etms_user_id,
                ),
            ).fetchone()[0]
            run_stop_a = conn.execute(
                """
                INSERT INTO etms.run_stops (
                    tenant_id, run_id, sequence_no, stop_type, location_id,
                    address_snapshot_id, planned_arrival_at, planned_departure_at
                )
                VALUES (
                    %s, %s, 1, 'DELIVERY', %s, %s,
                    statement_timestamp() + interval '3 hours',
                    statement_timestamp() + interval '4 hours'
                )
                RETURNING id
                """,
                (tenant_a, run_a, location_a, address_snapshot_a),
            ).fetchone()[0]

            core_presence = conn.execute(
                """
                SELECT
                    EXISTS (SELECT 1 FROM etms.organizations WHERE id = %s),
                    EXISTS (SELECT 1 FROM etms.transport_orders WHERE id = %s),
                    EXISTS (SELECT 1 FROM etms.shipments WHERE id = %s),
                    EXISTS (SELECT 1 FROM etms.transport_runs WHERE id = %s)
                """,
                (organization_a, order_a, shipment_a, run_a),
            ).fetchone()
            if core_presence != (True, True, True, True):
                raise AssertionError("Core ETMS master/order/shipment/run seed is incomplete")
            passed_checks.add("core_records")

            conn.execute(
                """
                INSERT INTO etms.capacity_reservations (
                    tenant_id, run_id, shipment_id, reserved_weight_kg,
                    reserved_volume_m3, reserved_pallets, status
                )
                VALUES (%s, %s, %s, 60, 1, 2, 'RESERVED')
                """,
                (tenant_a, run_a, shipment_a),
            )
            _expect_database_rejection(
                conn,
                "pallet_capacity_overflow",
                lambda: conn.execute(
                    """
                    INSERT INTO etms.capacity_reservations (
                        tenant_id, run_id, order_id, reserved_weight_kg,
                        reserved_volume_m3, reserved_pallets, status
                    )
                    VALUES (%s, %s, %s, 0, 0, 1, 'RESERVED')
                    """,
                    (tenant_a, run_a, order_a),
                ),
                {"23514"},
            )
            conn.execute(
                """
                INSERT INTO etms.capacity_reservations (
                    tenant_id, run_id, order_id, reserved_weight_kg,
                    reserved_volume_m3, reserved_pallets, status, expires_at
                )
                VALUES (
                    %s, %s, %s, 999, 999, 999, 'RESERVED',
                    statement_timestamp() - interval '1 second'
                )
                """,
                (tenant_a, run_a, other_order),
            )
            _expect_database_rejection(
                conn,
                "capacity_overflow",
                lambda: conn.execute(
                    """
                    INSERT INTO etms.capacity_reservations (
                        tenant_id, run_id, order_id, reserved_weight_kg,
                        reserved_volume_m3, status
                    )
                    VALUES (%s, %s, %s, 50, 1, 'RESERVED')
                    """,
                    (tenant_a, run_a, order_a),
                ),
                {"23514"},
            )
            passed_checks.add("capacity_limit")

            tender_a = conn.execute(
                """
                INSERT INTO etms.tenders (
                    tenant_id, tender_no, tender_type, run_id,
                    currency_code, response_deadline, status, created_by
                )
                VALUES (
                    %s, %s, 'SEQUENTIAL', %s, 'KRW',
                    statement_timestamp() + interval '1 hour', 'OPEN', %s
                )
                RETURNING id
                """,
                (tenant_a, f"TENDER_{suffix}", run_a, etms_user_id),
            ).fetchone()[0]
            conn.execute(
                """
                INSERT INTO etms.tender_awards (
                    tenant_id, tender_id, carrier_id, award_amount,
                    currency_code, awarded_by, status
                )
                VALUES (%s, %s, %s, 100, 'KRW', %s, 'AWARDED')
                """,
                (tenant_a, tender_a, carrier_a, etms_user_id),
            )
            conn.execute(
                """
                UPDATE etms.tenders
                SET status = 'AWARDED', awarded_carrier_id = %s,
                    awarded_amount = 100, awarded_at = statement_timestamp()
                WHERE id = %s
                """,
                (carrier_a, tender_a),
            )
            conn.execute("SET CONSTRAINTS ALL IMMEDIATE")
            conn.execute("SET CONSTRAINTS ALL DEFERRED")
            _expect_database_rejection(
                conn,
                "duplicate_tender_award",
                lambda: conn.execute(
                    """
                    INSERT INTO etms.tender_awards (
                        tenant_id, tender_id, carrier_id, award_amount,
                        currency_code, awarded_by, status
                    )
                    VALUES (%s, %s, %s, 101, 'KRW', %s, 'AWARDED')
                    """,
                    (tenant_a, tender_a, carrier_a, etms_user_id),
                ),
                {"23505"},
            )
            passed_checks.add("single_tender_award")

            conn.execute(
                """
                INSERT INTO etms.route_plan_versions (
                    tenant_id, run_id, version_no, route_source,
                    is_current, created_by
                )
                VALUES (%s, %s, 1, 'MANUAL', true, %s)
                """,
                (tenant_a, run_a, etms_user_id),
            )
            _expect_database_rejection(
                conn,
                "duplicate_current_route",
                lambda: conn.execute(
                    """
                    INSERT INTO etms.route_plan_versions (
                        tenant_id, run_id, version_no, route_source,
                        is_current, created_by
                    )
                    VALUES (%s, %s, 2, 'MANUAL', true, %s)
                    """,
                    (tenant_a, run_a, etms_user_id),
                ),
                {"23505"},
            )
            passed_checks.add("single_current_route")

            conn.execute(
                """
                INSERT INTO etms.run_carrier_assignments (
                    tenant_id, run_id, carrier_id, assignment_role,
                    valid_from, valid_to, status, source_type,
                    awarded_tender_id
                )
                VALUES (
                    %s, %s, %s, 'PRIMARY', statement_timestamp(),
                    statement_timestamp() + interval '4 hours',
                    'ACCEPTED', 'TENDER', %s
                )
                """,
                (tenant_a, run_a, carrier_a, tender_a),
            )
            _expect_database_rejection(
                conn,
                "duplicate_primary_assignment",
                lambda: conn.execute(
                    """
                    INSERT INTO etms.run_carrier_assignments (
                        tenant_id, run_id, carrier_id, assignment_role,
                        valid_from, valid_to, status, source_type
                    )
                    VALUES (
                        %s, %s, %s, 'PRIMARY', statement_timestamp(),
                        statement_timestamp() + interval '4 hours',
                        'PROPOSED', 'MANUAL'
                    )
                    """,
                    (tenant_a, run_a, carrier_a),
                ),
                {"23505"},
            )
            passed_checks.add("single_primary_assignment")

            conn.execute(
                """
                INSERT INTO etms.dock_appointments (
                    tenant_id, appointment_no, location_id, dock_id,
                    run_stop_id, appointment_type, scheduled_start_at,
                    scheduled_end_at, carrier_id, status
                )
                VALUES (
                    %s, %s, %s, %s, %s, 'DELIVERY',
                    statement_timestamp() + interval '2 hours',
                    statement_timestamp() + interval '3 hours',
                    %s, 'CONFIRMED'
                )
                """,
                (
                    tenant_a,
                    f"APPOINTMENT_1_{suffix}",
                    location_a,
                    dock_a,
                    run_stop_a,
                    carrier_a,
                ),
            )
            _expect_database_rejection(
                conn,
                "dock_overlap",
                lambda: conn.execute(
                    """
                    INSERT INTO etms.dock_appointments (
                        tenant_id, appointment_no, location_id, dock_id,
                        run_stop_id, appointment_type, scheduled_start_at,
                        scheduled_end_at, carrier_id, status
                    )
                    VALUES (
                        %s, %s, %s, %s, %s, 'DELIVERY',
                        statement_timestamp() + interval '150 minutes',
                        statement_timestamp() + interval '210 minutes',
                        %s, 'CONFIRMED'
                    )
                    """,
                    (
                        tenant_a,
                        f"APPOINTMENT_2_{suffix}",
                        location_a,
                        dock_a,
                        run_stop_a,
                        carrier_a,
                    ),
                ),
                {"23P01"},
            )
            passed_checks.add("dock_overlap")

            audit_event_id = conn.execute(
                """
                INSERT INTO etms.audit_events (
                    tenant_id, actor_user_id, action_code, entity_type,
                    entity_id, correlation_id
                )
                VALUES (%s, %s, 'SMOKE_CREATED', 'transport_run', %s, %s)
                RETURNING id
                """,
                (tenant_a, etms_user_id, run_a, f"AUDIT_{suffix}"),
            ).fetchone()[0]
            _expect_database_rejection(
                conn,
                "append_only_update",
                lambda: conn.execute(
                    "UPDATE etms.audit_events SET action_code = 'TAMPERED' WHERE id = %s",
                    (audit_event_id,),
                ),
                {"55000"},
            )
            _expect_database_rejection(
                conn,
                "append_only_delete",
                lambda: conn.execute(
                    "DELETE FROM etms.audit_events WHERE id = %s", (audit_event_id,)
                ),
                {"55000"},
            )
            passed_checks.add("append_only")

            pod_a = conn.execute(
                """
                INSERT INTO etms.proof_of_deliveries (
                    tenant_id, pod_no, order_id, shipment_id,
                    delivery_result, delivered_at, verification_status
                )
                VALUES (
                    %s, %s, %s, %s, 'DELIVERED',
                    statement_timestamp(), 'PENDING'
                )
                RETURNING id
                """,
                (tenant_a, f"POD_{suffix}", order_a, shipment_a),
            ).fetchone()[0]
            _expect_database_rejection(
                conn,
                "pod_overquantity",
                lambda: conn.execute(
                    """
                    INSERT INTO etms.pod_items (
                        tenant_id, pod_id, order_line_id, expected_quantity,
                        delivered_quantity, uom_code
                    )
                    VALUES (%s, %s, %s, 10, 11, 'EA')
                    """,
                    (tenant_a, pod_a, order_line_a),
                ),
                {"23514"},
            )
            passed_checks.add("pod_quantity")

            _expect_database_rejection(
                conn,
                "quote_total_mismatch",
                lambda: conn.execute(
                    """
                    INSERT INTO etms.rate_quotes (
                        tenant_id, quote_no, quote_type, customer_id,
                        mode_code, currency_code, net_amount, tax_amount,
                        gross_amount
                    )
                    VALUES (%s, %s, 'SELL', %s, 'ROAD', 'KRW', 10, 1, 12)
                    """,
                    (tenant_a, f"BAD_QUOTE_{suffix}", customer_a),
                ),
                {"23514"},
            )
            vehicle_type_a = conn.execute(
                """
                INSERT INTO etms.vehicle_types (
                    tenant_id, vehicle_type_code, vehicle_type_name,
                    max_payload_kg, fuel_type
                )
                VALUES (%s, %s, %s, 1000, 'DIESEL')
                RETURNING id
                """,
                (tenant_a, f"VEHICLE_TYPE_{suffix}", "ETMS smoke vehicle type"),
            ).fetchone()[0]
            vehicle_a = conn.execute(
                """
                INSERT INTO etms.vehicles (
                    tenant_id, owner_partner_id, operating_carrier_id,
                    vehicle_code, registration_no, vehicle_type_id,
                    fuel_type, max_payload_kg, home_location_id
                )
                VALUES (%s, %s, %s, %s, %s, %s, 'DIESEL', 1000, %s)
                RETURNING id
                """,
                (
                    tenant_a,
                    carrier_a,
                    carrier_a,
                    f"VEHICLE_{suffix}",
                    f"REG_{suffix}",
                    vehicle_type_a,
                    location_a,
                ),
            ).fetchone()[0]
            dock_b = conn.execute(
                """
                INSERT INTO etms.location_docks (
                    tenant_id, location_id, dock_code, dock_name, dock_type
                )
                VALUES (%s, %s, %s, %s, 'GENERAL')
                RETURNING id
                """,
                (tenant_a, location_a, f"DOCK_B_{suffix}", "ETMS smoke dock B"),
            ).fetchone()[0]
            conn.execute(
                """
                INSERT INTO etms.dock_appointments (
                    tenant_id, appointment_no, location_id, dock_id,
                    run_stop_id, appointment_type, scheduled_start_at,
                    scheduled_end_at, carrier_id, vehicle_id, status
                )
                VALUES (
                    %s, %s, %s, %s, %s, 'DELIVERY',
                    statement_timestamp() + interval '6 hours',
                    statement_timestamp() + interval '7 hours',
                    %s, %s, 'CONFIRMED'
                )
                """,
                (
                    tenant_a,
                    f"VEHICLE_APPOINTMENT_1_{suffix}",
                    location_a,
                    dock_b,
                    run_stop_a,
                    carrier_a,
                    vehicle_a,
                ),
            )
            _expect_database_rejection(
                conn,
                "vehicle_appointment_overlap",
                lambda: conn.execute(
                    """
                    INSERT INTO etms.dock_appointments (
                        tenant_id, appointment_no, location_id, dock_id,
                        run_stop_id, appointment_type, scheduled_start_at,
                        scheduled_end_at, carrier_id, vehicle_id, status
                    )
                    VALUES (
                        %s, %s, %s, %s, %s, 'DELIVERY',
                        statement_timestamp() + interval '390 minutes',
                        statement_timestamp() + interval '450 minutes',
                        %s, %s, 'CONFIRMED'
                    )
                    """,
                    (
                        tenant_a,
                        f"VEHICLE_APPOINTMENT_2_{suffix}",
                        location_a,
                        dock_a,
                        run_stop_a,
                        carrier_a,
                        vehicle_a,
                    ),
                ),
                {"23P01"},
            )
            passed_checks.add("vehicle_appointment_overlap")
            _expect_database_rejection(
                conn,
                "fuel_total_mismatch",
                lambda: conn.execute(
                    """
                    INSERT INTO etms.fuel_transactions (
                        tenant_id, run_id, vehicle_id, transaction_at,
                        fuel_type, fuel_quantity, fuel_uom_code, unit_price,
                        net_amount, tax_amount, gross_amount, currency_code
                    )
                    VALUES (
                        %s, %s, %s, statement_timestamp(), 'DIESEL',
                        10, 'L', 1, 10, 1, 12, 'KRW'
                    )
                    """,
                    (tenant_a, run_a, vehicle_a),
                ),
                {"23514"},
            )
            _expect_database_rejection(
                conn,
                "expense_total_mismatch",
                lambda: conn.execute(
                    """
                    INSERT INTO etms.run_expenses (
                        tenant_id, run_id, expense_type, incurred_at,
                        partner_id, net_amount, tax_amount, gross_amount,
                        currency_code, created_by
                    )
                    VALUES (
                        %s, %s, 'PARKING', statement_timestamp(), %s,
                        10, 1, 12, 'KRW', %s
                    )
                    """,
                    (tenant_a, run_a, carrier_a, etms_user_id),
                ),
                {"23514"},
            )
            passed_checks.add("amount_arithmetic")

            period_a = conn.execute(
                """
                INSERT INTO etms.accounting_periods (
                    tenant_id, organization_id, fiscal_year, period_no,
                    period_name, starts_on, ends_on, status
                )
                VALUES (
                    %s, %s, 2099, 1, 'Rollback smoke period',
                    DATE '2099-01-01', DATE '2099-12-31', 'OPEN'
                )
                RETURNING id
                """,
                (tenant_a, organization_a),
            ).fetchone()[0]
            debit_account = conn.execute(
                """
                INSERT INTO etms.gl_accounts (
                    tenant_id, organization_id, account_code,
                    account_name, account_type, currency_code
                )
                VALUES (%s, %s, %s, 'Rollback smoke debit', 'ASSET', 'KRW')
                RETURNING id
                """,
                (tenant_a, organization_a, f"DEBIT_{suffix}"),
            ).fetchone()[0]
            credit_account = conn.execute(
                """
                INSERT INTO etms.gl_accounts (
                    tenant_id, organization_id, account_code,
                    account_name, account_type, currency_code
                )
                VALUES (%s, %s, %s, 'Rollback smoke credit', 'REVENUE', 'KRW')
                RETURNING id
                """,
                (tenant_a, organization_a, f"CREDIT_{suffix}"),
            ).fetchone()[0]
            issuer_snapshot = conn.execute(
                """
                INSERT INTO etms.party_snapshots (
                    tenant_id, partner_id, partner_code, partner_name,
                    country_code
                )
                VALUES (%s, %s, %s, 'ETMS smoke issuer', 'KR')
                RETURNING id
                """,
                (tenant_a, carrier_a, f"ISSUER_{suffix}"),
            ).fetchone()[0]
            recipient_snapshot = conn.execute(
                """
                INSERT INTO etms.party_snapshots (
                    tenant_id, partner_id, partner_code, partner_name,
                    country_code
                )
                VALUES (%s, %s, %s, 'ETMS smoke recipient', 'KR')
                RETURNING id
                """,
                (tenant_a, customer_a, f"RECIPIENT_{suffix}"),
            ).fetchone()[0]
            invoice_a = conn.execute(
                """
                INSERT INTO etms.invoices (
                    tenant_id, invoice_type, invoice_no, organization_id,
                    issuer_partner_id, recipient_partner_id,
                    issuer_party_snapshot_id, recipient_party_snapshot_id,
                    invoice_date, posting_date, currency_code, exchange_rate,
                    base_currency_code, net_amount, tax_amount, gross_amount,
                    paid_amount, outstanding_amount, status, created_by
                )
                VALUES (
                    %s, 'RECEIVABLE', %s, %s, %s, %s, %s, %s,
                    DATE '2099-01-01', DATE '2099-01-01', 'KRW', 1,
                    'KRW', 100, 0, 100, 0, 100, 'DRAFT', %s
                )
                RETURNING id
                """,
                (
                    tenant_a,
                    f"INVOICE_{suffix}",
                    organization_a,
                    carrier_a,
                    customer_a,
                    issuer_snapshot,
                    recipient_snapshot,
                    etms_user_id,
                ),
            ).fetchone()[0]
            conn.execute(
                """
                INSERT INTO etms.invoice_lines (
                    tenant_id, invoice_id, line_no, description, quantity,
                    uom_code, unit_price, net_amount, discount_amount,
                    tax_amount, gross_amount
                )
                VALUES (%s, %s, 1, 'Rollback smoke invoice line', 1,
                        'EA', 100, 100, 0, 0, 100)
                """,
                (tenant_a, invoice_a),
            )
            conn.execute(
                "UPDATE etms.invoices SET status = 'APPROVED' WHERE id = %s",
                (invoice_a,),
            )
            _expect_database_rejection(
                conn,
                "invoice_without_journal",
                lambda: conn.execute(
                    "UPDATE etms.invoices SET status = 'POSTED' WHERE id = %s",
                    (invoice_a,),
                ),
                {"23514"},
            )
            journal_batch = conn.execute(
                """
                INSERT INTO etms.journal_batches (
                    tenant_id, batch_no, organization_id,
                    accounting_period_id, source_code, batch_type,
                    accounting_date, status
                )
                VALUES (
                    %s, %s, %s, %s, 'ETMS', 'MANUAL',
                    DATE '2099-01-01', 'APPROVED'
                )
                RETURNING id
                """,
                (tenant_a, f"JOURNAL_{suffix}", organization_a, period_a),
            ).fetchone()[0]
            journal_entry = conn.execute(
                """
                INSERT INTO etms.journal_entries (
                    tenant_id, journal_batch_id, entry_no,
                    source_entity_type, source_entity_id, description,
                    currency_code, exchange_rate, entry_date, status
                )
                VALUES (
                    %s, %s, 1, 'INVOICE', %s,
                    'Rollback smoke journal', 'KRW', 1,
                    DATE '2099-01-01', 'DRAFT'
                )
                RETURNING id
                """,
                (tenant_a, journal_batch, invoice_a),
            ).fetchone()[0]
            debit_line = conn.execute(
                """
                INSERT INTO etms.journal_lines (
                    tenant_id, journal_entry_id, line_no, gl_account_id,
                    debit_amount, credit_amount, base_debit_amount,
                    base_credit_amount
                )
                VALUES (%s, %s, 1, %s, 100, 0, 100, 0)
                RETURNING id
                """,
                (tenant_a, journal_entry, debit_account),
            ).fetchone()[0]
            _expect_database_rejection(
                conn,
                "unbalanced_journal",
                lambda: (
                    conn.execute(
                        "UPDATE etms.journal_entries SET status = 'POSTED' WHERE id = %s",
                        (journal_entry,),
                    ),
                    conn.execute("SET CONSTRAINTS ALL IMMEDIATE"),
                ),
                {"23514"},
            )
            conn.execute(
                """
                INSERT INTO etms.journal_lines (
                    tenant_id, journal_entry_id, line_no, gl_account_id,
                    debit_amount, credit_amount, base_debit_amount,
                    base_credit_amount
                )
                VALUES (%s, %s, 2, %s, 0, 100, 0, 100)
                """,
                (tenant_a, journal_entry, credit_account),
            )
            conn.execute(
                "UPDATE etms.journal_entries SET status = 'POSTED' WHERE id = %s",
                (journal_entry,),
            )
            conn.execute("SET CONSTRAINTS ALL IMMEDIATE")
            conn.execute(
                """
                UPDATE etms.journal_batches
                SET status = 'POSTED', total_debit = 100, total_credit = 100,
                    posted_at = statement_timestamp(), posted_by = %s
                WHERE id = %s
                """,
                (etms_user_id, journal_batch),
            )
            journal_link_id = conn.execute(
                """
                INSERT INTO etms.financial_journal_links (
                    tenant_id, financial_entity_type, financial_entity_id,
                    journal_entry_id, link_role, linked_amount,
                    currency_code, linked_by_user_id
                )
                VALUES (%s, 'INVOICE', %s, %s, 'POSTING', 100, 'KRW', %s)
                RETURNING id
                """,
                (tenant_a, invoice_a, journal_entry, etms_user_id),
            ).fetchone()[0]
            conn.execute(
                "UPDATE etms.invoices SET status = 'POSTED' WHERE id = %s",
                (invoice_a,),
            )
            _expect_database_rejection(
                conn,
                "journal_link_mutation",
                lambda: conn.execute(
                    "DELETE FROM etms.financial_journal_links WHERE id = %s",
                    (journal_link_id,),
                ),
                {"55000"},
            )
            passed_checks.add("financial_journal_link")
            _expect_database_rejection(
                conn,
                "posted_journal_line_mutation",
                lambda: conn.execute(
                    "UPDATE etms.journal_lines SET debit_amount = 99 WHERE id = %s",
                    (debit_line,),
                ),
                {"55000"},
            )
            _expect_database_rejection(
                conn,
                "posted_journal_batch_delete",
                lambda: conn.execute(
                    "DELETE FROM etms.journal_batches WHERE id = %s", (journal_batch,)
                ),
                {"55000"},
            )
            passed_checks.add("finance_integrity")

            tenant_tables, rls_tables, force_rls_tables = conn.execute(
                """
                SELECT count(*),
                       count(*) FILTER (WHERE relation.relrowsecurity),
                       count(*) FILTER (WHERE relation.relforcerowsecurity)
                FROM pg_class relation
                JOIN pg_namespace namespace_row
                  ON namespace_row.oid = relation.relnamespace
                JOIN pg_attribute tenant_column
                  ON tenant_column.attrelid = relation.oid
                 AND tenant_column.attname = 'tenant_id'
                 AND NOT tenant_column.attisdropped
                WHERE namespace_row.nspname = 'etms'
                  AND relation.relkind = 'r'
                """
            ).fetchone()
            if tenant_tables != rls_tables or tenant_tables != force_rls_tables:
                raise AssertionError("RLS/FORCE RLS coverage changed during smoke testing")

            if len(passed_checks) != 21:
                raise AssertionError("ETMS smoke check accounting changed unexpectedly")
        finally:
            conn.rollback()

    print(
        "ETMS rollback smoke tests passed: "
        f"checks={len(passed_checks)}, "
        f"tables={catalog_counts.get('tables', 0)}, "
        f"rls_tables={catalog_counts.get('rls_tables', 0)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
