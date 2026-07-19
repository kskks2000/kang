"""Rollback-only EWMS security and business-integrity smoke tests."""

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
from scripts.apply_ewms_schema import _assert_actual_target  # noqa: E402


def _clear_request_context_for_owner_smoke(conn: psycopg.Connection) -> None:
    """Clear only this rollback transaction's protected context as the DDL owner."""

    conn.execute(
        """
        DELETE FROM ewms.request_contexts
        WHERE backend_pid = pg_backend_pid()
          AND transaction_id = txid_current()
        """
    )


def _bind_session(
    conn: psycopg.Connection,
    session_handle_hash: str,
    expected_tenant_id: object,
) -> None:
    bound_tenant_id = conn.execute(
        "SELECT ewms.bind_request_context(%s)",
        (session_handle_hash,),
    ).fetchone()[0]
    if bound_tenant_id != expected_tenant_id:
        raise AssertionError("Protected request context bound an unexpected tenant")
    current_tenant_id, current_user_id = conn.execute(
        "SELECT ewms.current_tenant_id(), ewms.current_ewms_user_id()"
    ).fetchone()
    if current_tenant_id != expected_tenant_id or current_user_id is None:
        raise AssertionError("Protected request context did not expose its authenticated subject")


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


def _select_or_create_smoke_subject(
    conn: psycopg.Connection,
    suffix: str,
) -> tuple[object, str, object, str, str]:
    """Reuse a valid EWMS identity, or create only rollback-scoped identity rows."""

    existing_identity = conn.execute(
        """
        SELECT platform_user.id, platform_user.firebase_uid, ewms_user.id,
               identity_row.provider_code, identity_row.provider_subject
        FROM ewms.users ewms_user
        JOIN kang.users platform_user
          ON platform_user.id = ewms_user.platform_user_id
         AND platform_user.firebase_uid = ewms_user.firebase_uid
        JOIN ewms.auth_identities identity_row
          ON identity_row.user_id = ewms_user.id
         AND identity_row.firebase_project_id = ewms_user.firebase_project_id
         AND identity_row.firebase_tenant_id IS NOT DISTINCT FROM ewms_user.firebase_tenant_id
         AND identity_row.firebase_uid = ewms_user.firebase_uid
         AND identity_row.disabled_at IS NULL
        WHERE ewms_user.status = 'ACTIVE'
          AND ewms_user.deleted_at IS NULL
          AND ewms_user.locked_at IS NULL
          AND identity_row.provider_code IN ('password', 'google.com')
          AND (
              identity_row.provider_code <> 'password'
              OR identity_row.provider_subject = identity_row.firebase_uid
          )
        ORDER BY ewms_user.id, identity_row.provider_code, identity_row.id
        LIMIT 1
        """
    ).fetchone()
    if existing_identity is not None:
        return existing_identity

    mapped_user = conn.execute(
        """
        SELECT platform_user.id, platform_user.firebase_uid, ewms_user.id
        FROM ewms.users ewms_user
        JOIN kang.users platform_user
          ON platform_user.id = ewms_user.platform_user_id
         AND platform_user.firebase_uid = ewms_user.firebase_uid
        WHERE ewms_user.status = 'ACTIVE'
          AND ewms_user.deleted_at IS NULL
          AND ewms_user.locked_at IS NULL
        ORDER BY ewms_user.id
        LIMIT 1
        """
    ).fetchone()
    if mapped_user is None:
        platform_user = conn.execute(
            """
            SELECT platform_user.id, platform_user.firebase_uid
            FROM kang.users platform_user
            LEFT JOIN ewms.users ewms_user
              ON ewms_user.platform_user_id = platform_user.id
            WHERE ewms_user.id IS NULL
              AND platform_user.firebase_uid IS NOT NULL
              AND btrim(platform_user.firebase_uid) <> ''
            ORDER BY platform_user.id
            LIMIT 1
            """
        ).fetchone()
        if platform_user is None:
            raise RuntimeError(
                "EWMS smoke tests require one canonical Firebase platform user"
            )
        platform_user_id, firebase_uid = platform_user
        ewms_user_id = conn.execute(
            """
            INSERT INTO ewms.users
                (platform_user_id, firebase_uid, status, display_name)
            VALUES (%s, %s, 'ACTIVE', 'EWMS rollback smoke')
            RETURNING id
            """,
            (platform_user_id, firebase_uid),
        ).fetchone()[0]
    else:
        platform_user_id, firebase_uid, ewms_user_id = mapped_user

    provider_code = "google.com"
    provider_subject = f"EWMS_SMOKE_SUBJECT_{suffix}"
    conn.execute(
        """
        INSERT INTO ewms.auth_identities
            (user_id, firebase_uid, provider_code, provider_subject)
        VALUES (%s, %s, %s, %s)
        """,
        (ewms_user_id, firebase_uid, provider_code, provider_subject),
    )
    return (
        platform_user_id,
        firebase_uid,
        ewms_user_id,
        provider_code,
        provider_subject,
    )


def main() -> int:
    suffix = uuid4().hex[:12]
    session_hash_a = hashlib.sha256(f"EWMS_SMOKE_A_{suffix}".encode()).hexdigest()
    session_hash_b = hashlib.sha256(f"EWMS_SMOKE_B_{suffix}".encode()).hexdigest()

    with psycopg.connect(settings.database_url) as conn:
        _assert_actual_target(conn)
        conn.execute("SET LOCAL lock_timeout = '10s'")
        conn.execute("SET LOCAL statement_timeout = '5min'")
        version_num = conn.execute(
            "SELECT current_setting('server_version_num')::integer"
        ).fetchone()[0]
        if not 110000 <= version_num < 120000:
            raise RuntimeError("EWMS smoke tests require PostgreSQL 11.x")

        tenant_a = conn.execute(
            """
            INSERT INTO ewms.tenants (tenant_code, tenant_name)
            VALUES (%s, %s)
            RETURNING id
            """,
            (f"SMOKE_A_{suffix}", "EWMS smoke tenant A"),
        ).fetchone()[0]
        tenant_b = conn.execute(
            """
            INSERT INTO ewms.tenants (tenant_code, tenant_name)
            VALUES (%s, %s)
            RETURNING id
            """,
            (f"SMOKE_B_{suffix}", "EWMS smoke tenant B"),
        ).fetchone()[0]

        (
            platform_user_id,
            firebase_uid,
            ewms_user_id,
            provider_code,
            provider_subject,
        ) = _select_or_create_smoke_subject(conn, suffix)

        # Bootstrap synthetic memberships as the isolated DDL owner. FORCE RLS is removed
        # only inside this rollback-only transaction and restored before any business probe.
        conn.execute("ALTER TABLE ewms.tenant_memberships NO FORCE ROW LEVEL SECURITY")
        conn.execute(
            """
            INSERT INTO ewms.tenant_memberships (tenant_id, user_id, status)
            VALUES (%s, %s, 'ACTIVE'), (%s, %s, 'ACTIVE')
            """,
            (tenant_a, ewms_user_id, tenant_b, ewms_user_id),
        )
        conn.execute("ALTER TABLE ewms.tenant_memberships FORCE ROW LEVEL SECURITY")

        for tenant_id, session_hash in (
            (tenant_a, session_hash_a),
            (tenant_b, session_hash_b),
        ):
            conn.execute(
                """
                SELECT ewms.issue_ewms_session(
                    %s, %s, %s, %s, %s, %s,
                    statement_timestamp(), statement_timestamp() + interval '1 hour',
                    'MULTI_FACTOR', NULL, 'EWMS rollback smoke'
                )
                """,
                (
                    platform_user_id,
                    firebase_uid,
                    provider_code,
                    provider_subject,
                    session_hash,
                    tenant_id,
                ),
            )

        conn.execute(
            "SELECT set_config('ewms.tenant_id', %s, true)",
            (str(tenant_a),),
        )
        spoofed_subject = conn.execute(
            "SELECT ewms.current_tenant_id(), ewms.current_ewms_user_id()"
        ).fetchone()
        if spoofed_subject != (None, None):
            raise AssertionError("Client-settable EWMS tenant GUC forged an authenticated context")

        _bind_session(conn, session_hash_a, tenant_a)
        _expect_database_rejection(
            conn,
            "transaction_session_switch",
            lambda: conn.execute(
                "SELECT ewms.bind_request_context(%s)",
                (session_hash_b,),
            ),
            {"25001"},
        )

        organization_a = conn.execute(
            """
            INSERT INTO ewms.organizations
                (tenant_id, organization_code, organization_name)
            VALUES (%s, %s, %s)
            RETURNING id
            """,
            (tenant_a, f"ORG_{suffix}", "Smoke organization"),
        ).fetchone()[0]
        partner_a = conn.execute(
            """
            INSERT INTO ewms.business_partners
                (tenant_id, partner_code, partner_name)
            VALUES (%s, %s, %s)
            RETURNING id
            """,
            (tenant_a, f"PARTNER_A_{suffix}", "Smoke partner A"),
        ).fetchone()[0]
        counterparty_a = conn.execute(
            """
            INSERT INTO ewms.business_partners
                (tenant_id, partner_code, partner_name)
            VALUES (%s, %s, %s)
            RETURNING id
            """,
            (tenant_a, f"PARTNER_COUNTER_{suffix}", "Smoke counterparty"),
        ).fetchone()[0]

        _clear_request_context_for_owner_smoke(conn)
        _bind_session(conn, session_hash_b, tenant_b)
        partner_b = conn.execute(
            """
            INSERT INTO ewms.business_partners
                (tenant_id, partner_code, partner_name)
            VALUES (%s, %s, %s)
            RETURNING id
            """,
            (tenant_b, f"PARTNER_B_{suffix}", "Smoke partner B"),
        ).fetchone()[0]

        _clear_request_context_for_owner_smoke(conn)
        _bind_session(conn, session_hash_a, tenant_a)
        _expect_database_rejection(
            conn,
            "cross_tenant_reference",
            lambda: conn.execute(
                """
                INSERT INTO ewms.trade_cases
                    (tenant_id, case_no, direction, owner_partner_id)
                VALUES (%s, %s, 'IMPORT', %s)
                """,
                (tenant_a, f"BAD_CASE_{suffix}", partner_b),
            ),
            {"23503", "23514"},
        )

        trade_case_id = conn.execute(
            """
            INSERT INTO ewms.trade_cases
                (tenant_id, case_no, direction, owner_partner_id, status)
            VALUES (%s, %s, 'EXPORT', %s, 'OPEN')
            RETURNING id
            """,
            (tenant_a, f"CASE_{suffix}", partner_a),
        ).fetchone()[0]
        trade_shipment_id = conn.execute(
            """
            INSERT INTO ewms.trade_shipments
                (tenant_id, owner_partner_id, trade_shipment_no, direction)
            VALUES (%s, %s, %s, 'EXPORT')
            RETURNING id
            """,
            (tenant_a, partner_a, f"TS_{suffix}"),
        ).fetchone()[0]
        conn.execute(
            """
            INSERT INTO ewms.trade_case_shipments
                (tenant_id, trade_case_id, trade_shipment_id)
            VALUES (%s, %s, %s)
            """,
            (tenant_a, trade_case_id, trade_shipment_id),
        )
        hold_id = conn.execute(
            """
            INSERT INTO ewms.compliance_holds
                (
                    tenant_id, hold_no, hold_type, severity, trade_shipment_id,
                    reason_code, reason_text
                )
            VALUES (%s, %s, 'SANCTIONS', 'BLOCKING', %s, 'SMOKE', 'Smoke blocking hold')
            RETURNING id
            """,
            (tenant_a, f"HOLD_{suffix}", trade_shipment_id),
        ).fetchone()[0]
        _expect_database_rejection(
            conn,
            "blocking_compliance_hold",
            lambda: conn.execute(
                "UPDATE ewms.trade_shipments SET status='BOOKED' WHERE id=%s",
                (trade_shipment_id,),
            ),
            {"23514", "42501", "55000", "P0001"},
        )
        conn.execute(
            """
            UPDATE ewms.compliance_holds
               SET status='RELEASED', released_at=now(), release_reason='Smoke release'
             WHERE id=%s
            """,
            (hold_id,),
        )
        conn.execute(
            "UPDATE ewms.trade_shipments SET status='BOOKED' WHERE id=%s",
            (trade_shipment_id,),
        )

        event_id = conn.execute(
            """
            INSERT INTO ewms.trade_case_events
                (tenant_id, trade_case_id, sequence_no, event_type, occurred_at)
            VALUES (%s, %s, 1, 'SMOKE', now())
            RETURNING id
            """,
            (tenant_a, trade_case_id),
        ).fetchone()[0]
        _expect_database_rejection(
            conn,
            "append_only_event",
            lambda: conn.execute(
                "UPDATE ewms.trade_case_events SET event_type='MUTATED' WHERE id=%s",
                (event_id,),
            ),
            {"55000"},
        )

        item_id = conn.execute(
            """
            INSERT INTO ewms.items
                (tenant_id, item_code, item_name, base_uom_code)
            VALUES (%s, %s, 'Smoke item', 'EA')
            RETURNING id
            """,
            (tenant_a, f"ITEM_{suffix}"),
        ).fetchone()[0]
        address_id = conn.execute(
            """
            INSERT INTO ewms.addresses
                (tenant_id, country_code, address_name, address_line1)
            VALUES (%s, 'KR', 'Smoke warehouse', 'Rollback-only address')
            RETURNING id
            """,
            (tenant_a,),
        ).fetchone()[0]
        warehouse_id = conn.execute(
            """
            INSERT INTO ewms.warehouses
                (
                    tenant_id, organization_id, warehouse_code,
                    warehouse_name, address_id, status
                )
            VALUES (%s, %s, %s, 'Smoke warehouse', %s, 'ACTIVE')
            RETURNING id
            """,
            (tenant_a, organization_a, f"WH_{suffix}", address_id),
        ).fetchone()[0]
        available_status_id, quality_status_id = conn.execute(
            """
            SELECT
                (SELECT id FROM ewms.inventory_statuses
                  WHERE tenant_id IS NULL AND status_code = 'AVAILABLE' LIMIT 1),
                (SELECT id FROM ewms.inventory_statuses
                  WHERE tenant_id IS NULL AND status_code = 'QUALITY_HOLD' LIMIT 1)
            """
        ).fetchone()
        if available_status_id is None or quality_status_id is None:
            raise AssertionError("EWMS baseline inventory-status seeds are incomplete")
        conn.execute(
            """
            INSERT INTO ewms.warehouse_clients
                (
                    tenant_id, warehouse_id, owner_partner_id, client_code,
                    default_inventory_status_id, default_receiving_status_id, status
                )
            VALUES (%s, %s, %s, %s, %s, %s, 'ACTIVE')
            """,
            (
                tenant_a,
                warehouse_id,
                partner_a,
                f"CLIENT_{suffix}",
                available_status_id,
                quality_status_id,
            ),
        )
        storage_location_type_id = conn.execute(
            """
            SELECT id
            FROM ewms.location_types
            WHERE tenant_id IS NULL
              AND location_type_code = 'STORAGE'
              AND is_active
            LIMIT 1
            """
        ).fetchone()
        if storage_location_type_id is None:
            raise AssertionError("EWMS baseline STORAGE location type seed is missing")
        bonded_zone_id = conn.execute(
            """
            INSERT INTO ewms.warehouse_zones
                (tenant_id, warehouse_id, zone_code, zone_name, zone_type, bonded_controlled)
            VALUES (%s, %s, %s, 'Smoke bonded zone', 'BONDED', true)
            RETURNING id
            """,
            (tenant_a, warehouse_id, f"BZ_{suffix}"),
        ).fetchone()[0]
        bonded_location_id = conn.execute(
            """
            INSERT INTO ewms.warehouse_locations
                (
                    tenant_id, warehouse_id, zone_id, location_type_id,
                    location_code, location_name, bonded_controlled, status
                )
            VALUES (%s, %s, %s, %s, %s, 'Smoke bonded location', true, 'ACTIVE')
            RETURNING id
            """,
            (
                tenant_a,
                warehouse_id,
                bonded_zone_id,
                storage_location_type_id[0],
                f"BLOC_{suffix}",
            ),
        ).fetchone()[0]
        quality_bucket_id = conn.execute(
            """
            INSERT INTO ewms.stock_buckets
                (
                    tenant_id, owner_partner_id, warehouse_id, item_id,
                    inventory_status_id, account_type
                )
            VALUES (%s, %s, %s, %s, %s, 'VIRTUAL')
            RETURNING id
            """,
            (tenant_a, partner_a, warehouse_id, item_id, quality_status_id),
        ).fetchone()[0]
        foreign_bucket_id = conn.execute(
            """
            INSERT INTO ewms.stock_buckets
                (
                    tenant_id, owner_partner_id, warehouse_id, item_id,
                    inventory_status_id, account_type, customs_legal_status_code
                )
            VALUES (%s, %s, %s, %s, %s, 'VIRTUAL', 'FOREIGN')
            RETURNING id
            """,
            (tenant_a, partner_a, warehouse_id, item_id, available_status_id),
        ).fetchone()[0]
        _expect_database_rejection(
            conn,
            "inventory_status_allocation_gate",
            lambda: conn.execute(
                """
                INSERT INTO ewms.inventory_reservations
                    (
                        tenant_id, reservation_no, stock_bucket_id,
                        demand_document_type, demand_document_id,
                        reserved_quantity, base_uom_code
                    )
                VALUES (%s, %s, %s, 'SMOKE', %s, 1, 'EA')
                """,
                (tenant_a, f"RSV_Q_{suffix}", quality_bucket_id, uuid4()),
            ),
            {"23514"},
        )
        _expect_database_rejection(
            conn,
            "foreign_inventory_allocation_gate",
            lambda: conn.execute(
                """
                INSERT INTO ewms.inventory_reservations
                    (
                        tenant_id, reservation_no, stock_bucket_id,
                        demand_document_type, demand_document_id,
                        reserved_quantity, base_uom_code
                    )
                VALUES (%s, %s, %s, 'SMOKE', %s, 1, 'EA')
                """,
                (tenant_a, f"RSV_F_{suffix}", foreign_bucket_id, uuid4()),
            ),
            {"23514"},
        )

        customs_declaration_id = conn.execute(
            """
            INSERT INTO ewms.customs_declarations
                (
                    tenant_id, owner_partner_id, warehouse_id, declaration_key,
                    declaration_kind, trade_shipment_id, workflow_status
                )
            VALUES (%s, %s, %s, %s, 'EXPORT', %s, 'DRAFT')
            RETURNING id
            """,
            (
                tenant_a,
                partner_a,
                warehouse_id,
                f"DECL_{suffix}",
                trade_shipment_id,
            ),
        ).fetchone()[0]
        customs_version_id = conn.execute(
            """
            INSERT INTO ewms.customs_declaration_versions
                (
                    tenant_id, owner_partner_id, declaration_id, version_no,
                    filing_action, declaration_date, invoice_currency_code,
                    total_invoice_amount, declared_line_count, prepared_by
                )
            VALUES (%s, %s, %s, 1, 'ORIGINAL', CURRENT_DATE, 'KRW', 100, 1, %s)
            RETURNING id
            """,
            (tenant_a, partner_a, customs_declaration_id, ewms_user_id),
        ).fetchone()[0]
        customs_line_id = conn.execute(
            """
            INSERT INTO ewms.customs_declaration_lines
                (
                    tenant_id, owner_partner_id, declaration_version_id, line_no,
                    item_id, goods_description, country_of_origin,
                    declared_base_quantity, base_uom_code,
                    invoice_amount, invoice_currency_code
                )
            VALUES (%s, %s, %s, 1, %s, 'Smoke export item', 'KR', 1, 'EA', 100, 'KRW')
            RETURNING id
            """,
            (tenant_a, partner_a, customs_version_id, item_id),
        ).fetchone()[0]
        conn.execute(
            """
            UPDATE ewms.customs_declaration_versions
               SET sealed_by = %s, sealed_at = statement_timestamp()
             WHERE id = %s
            """,
            (ewms_user_id, customs_version_id),
        )
        _expect_database_rejection(
            conn,
            "sealed_customs_line_mutation",
            lambda: conn.execute(
                "UPDATE ewms.customs_declaration_lines SET goods_description='MUTATED' WHERE id=%s",
                (customs_line_id,),
            ),
            {"55000"},
        )

        unipass_profile_id = conn.execute(
            """
            INSERT INTO ewms.unipass_connection_profiles
                (
                    tenant_id, organization_id, declarant_partner_id,
                    profile_code, profile_name, environment, endpoint_uri,
                    credential_secret_ref, status
                )
            VALUES (
                %s, %s, %s, %s, 'Smoke UNI-PASS profile', 'TEST',
                'https://invalid.example/rollback-smoke', 'secret://rollback-smoke', 'ACTIVE'
            )
            RETURNING id
            """,
            (tenant_a, organization_a, partner_a, f"UNIPASS_{suffix}"),
        ).fetchone()[0]
        unipass_message_id = conn.execute(
            """
            INSERT INTO ewms.unipass_messages
                (
                    tenant_id, owner_partner_id, connection_profile_id,
                    declaration_id, declaration_version_id, direction,
                    message_type, message_purpose, submission_no,
                    payload_object_uri, payload_sha256, payload_byte_size,
                    recorded_status
                )
            VALUES (
                %s, %s, %s, %s, %s, 'OUT', 'SMOKE_EXPORT_DECLARATION',
                'SUBMISSION', %s, 'urn:ewms:rollback-smoke', %s, 0, 'CREATED'
            )
            RETURNING id
            """,
            (
                tenant_a,
                partner_a,
                unipass_profile_id,
                customs_declaration_id,
                customs_version_id,
                f"SUBMIT_{suffix}",
                session_hash_a,
            ),
        ).fetchone()[0]
        conn.execute(
            "UPDATE ewms.unipass_messages SET recorded_status='QUEUED' WHERE id=%s",
            (unipass_message_id,),
        )
        conn.execute(
            """
            UPDATE ewms.unipass_messages
               SET recorded_status='SENT', sent_at=clock_timestamp()
             WHERE id=%s
            """,
            (unipass_message_id,),
        )
        _expect_database_rejection(
            conn,
            "unipass_invalid_reverse_transition",
            lambda: conn.execute(
                "UPDATE ewms.unipass_messages SET recorded_status='QUEUED' WHERE id=%s",
                (unipass_message_id,),
            ),
            {"23514"},
        )

        bonded_facility_id = conn.execute(
            """
            INSERT INTO ewms.bonded_facilities
                (
                    tenant_id, warehouse_id, operator_partner_id,
                    facility_code, facility_name, facility_type_code, status
                )
            VALUES (%s, %s, %s, %s, 'Smoke bonded facility', 'BONDED_WAREHOUSE', 'ACTIVE')
            RETURNING id
            """,
            (tenant_a, warehouse_id, partner_a, f"BF_{suffix}"),
        ).fetchone()[0]
        conn.execute(
            """
            INSERT INTO ewms.bonded_zone_controls
                (
                    tenant_id, bonded_facility_id, warehouse_zone_id,
                    warehouse_location_id, control_code, control_type, status
                )
            VALUES (%s, %s, %s, %s, %s, 'STORAGE', 'ACTIVE')
            """,
            (
                tenant_a,
                bonded_facility_id,
                bonded_zone_id,
                bonded_location_id,
                f"BZC_{suffix}",
            ),
        )
        bonded_cargo_id = conn.execute(
            """
            INSERT INTO ewms.bonded_cargo
                (
                    tenant_id, owner_partner_id, bonded_facility_id,
                    warehouse_id, bonded_cargo_no, trade_shipment_id,
                    physical_status, legal_status, customs_hold_status
                )
            VALUES (%s, %s, %s, %s, %s, %s, 'STORED', 'FOREIGN', 'CLEAR')
            RETURNING id
            """,
            (
                tenant_a,
                partner_a,
                bonded_facility_id,
                warehouse_id,
                f"BC_{suffix}",
                trade_shipment_id,
            ),
        ).fetchone()[0]
        bonded_cargo_item_id = conn.execute(
            """
            INSERT INTO ewms.bonded_cargo_items
                (
                    tenant_id, owner_partner_id, bonded_cargo_id, line_no,
                    item_id, country_of_origin, declared_quantity,
                    received_quantity, current_quantity, base_uom_code, status
                )
            VALUES (%s, %s, %s, 1, %s, 'KR', 1, 1, 1, 'EA', 'STORED')
            RETURNING id
            """,
            (tenant_a, partner_a, bonded_cargo_id, item_id),
        ).fetchone()[0]
        bonded_discrepancy_id = conn.execute(
            """
            INSERT INTO ewms.bonded_discrepancies
                (
                    tenant_id, owner_partner_id, bonded_cargo_id,
                    bonded_cargo_item_id, discrepancy_no, discrepancy_type,
                    detected_during, expected_quantity, actual_quantity,
                    variance_quantity, base_uom_code, status
                )
            VALUES (
                %s, %s, %s, %s, %s, 'OVERAGE', 'COUNT',
                0, 1, 1, 'EA', 'ADJUSTMENT_APPROVED'
            )
            RETURNING id
            """,
            (
                tenant_a,
                partner_a,
                bonded_cargo_id,
                bonded_cargo_item_id,
                f"BDISC_{suffix}",
            ),
        ).fetchone()[0]
        bonded_group_id = conn.execute(
            """
            INSERT INTO ewms.bonded_movement_groups
                (
                    tenant_id, owner_partner_id, bonded_cargo_id,
                    movement_group_no, group_type, status, occurred_at, reason_text
                )
            VALUES (%s, %s, %s, %s, 'ADJUSTMENT', 'DRAFT', statement_timestamp(), 'Smoke adjustment')
            RETURNING id
            """,
            (tenant_a, partner_a, bonded_cargo_id, f"BGRP_{suffix}"),
        ).fetchone()[0]
        bonded_physical_bucket_id = conn.execute(
            """
            INSERT INTO ewms.stock_buckets
                (
                    tenant_id, owner_partner_id, warehouse_id, location_id,
                    item_id, inventory_status_id, country_of_origin,
                    account_type, customs_legal_status_code
                )
            VALUES (%s, %s, %s, %s, %s, %s, 'KR', 'PHYSICAL', 'FOREIGN')
            RETURNING id
            """,
            (
                tenant_a,
                partner_a,
                warehouse_id,
                bonded_location_id,
                item_id,
                available_status_id,
            ),
        ).fetchone()[0]
        bonded_inventory_tx_id = conn.execute(
            """
            INSERT INTO ewms.inventory_transaction_headers
                (
                    tenant_id, transaction_no, transaction_type, warehouse_id,
                    owner_partner_id, posting_status, occurred_at, reason_text, created_by
                )
            VALUES (%s, %s, 'BONDED_MOVE', %s, %s, 'DRAFT', statement_timestamp(), 'Smoke bonded adjustment', %s)
            RETURNING id
            """,
            (
                tenant_a,
                f"BTX_{suffix}",
                warehouse_id,
                partner_a,
                ewms_user_id,
            ),
        ).fetchone()[0]
        bonded_physical_entry_id = conn.execute(
            """
            INSERT INTO ewms.inventory_transaction_entries
                (
                    tenant_id, inventory_transaction_id, entry_sequence,
                    stock_bucket_id, item_id, signed_quantity,
                    base_uom_code, entry_role
                )
            VALUES (%s, %s, 1, %s, %s, 1, 'EA', 'DESTINATION')
            RETURNING id
            """,
            (
                tenant_a,
                bonded_inventory_tx_id,
                bonded_physical_bucket_id,
                item_id,
            ),
        ).fetchone()[0]
        conn.execute(
            """
            INSERT INTO ewms.inventory_transaction_entries
                (
                    tenant_id, inventory_transaction_id, entry_sequence,
                    stock_bucket_id, item_id, signed_quantity,
                    base_uom_code, entry_role
                )
            VALUES (%s, %s, 2, %s, %s, -1, 'EA', 'SOURCE')
            """,
            (tenant_a, bonded_inventory_tx_id, foreign_bucket_id, item_id),
        )
        bonded_movement_id = conn.execute(
            """
            INSERT INTO ewms.bonded_inventory_movements
                (
                    tenant_id, owner_partner_id, bonded_movement_group_id,
                    bonded_cargo_id, bonded_cargo_item_id, movement_sequence,
                    movement_type, warehouse_id, warehouse_location_id,
                    legal_status, inventory_status_id, stock_bucket_id,
                    quantity_delta, base_uom_code, discrepancy_id,
                    inventory_transaction_id, inventory_transaction_entry_id,
                    reason_text, occurred_at, recorded_by
                )
            VALUES (
                %s, %s, %s, %s, %s, 1, 'ADJUSTMENT_IN', %s, %s,
                'FOREIGN', %s, %s, 1, 'EA', %s, %s, %s,
                'Smoke bonded overage', statement_timestamp(), %s
            )
            RETURNING id
            """,
            (
                tenant_a,
                partner_a,
                bonded_group_id,
                bonded_cargo_id,
                bonded_cargo_item_id,
                warehouse_id,
                bonded_location_id,
                available_status_id,
                bonded_physical_bucket_id,
                bonded_discrepancy_id,
                bonded_inventory_tx_id,
                bonded_physical_entry_id,
                ewms_user_id,
            ),
        ).fetchone()[0]
        conn.execute(
            """
            UPDATE ewms.bonded_movement_groups
               SET status='POSTED', posted_at=statement_timestamp(), posted_by=%s
             WHERE id=%s
            """,
            (ewms_user_id, bonded_group_id),
        )
        conn.execute(
            "SELECT ewms.post_inventory_transaction(%s, %s)",
            (bonded_inventory_tx_id, ewms_user_id),
        )
        conn.execute(
            """
            SET CONSTRAINTS
                ewms.trg_95_require_posted_bonded_group,
                ewms.trg_95_require_bonded_inventory_links
            IMMEDIATE
            """
        )
        _expect_database_rejection(
            conn,
            "posted_bonded_movement_mutation",
            lambda: conn.execute(
                "UPDATE ewms.bonded_inventory_movements SET reason_text='MUTATED' WHERE id=%s",
                (bonded_movement_id,),
            ),
            {"55000"},
        )

        agreement_id = conn.execute(
            """
            INSERT INTO ewms.trade_agreements
                (
                    tenant_id, agreement_code, agreement_name, version_code,
                    effective_from, status
                )
            VALUES (%s, %s, 'Smoke agreement', '1', CURRENT_DATE - 1, 'ACTIVE')
            RETURNING id
            """,
            (tenant_a, f"FTA_{suffix}"),
        ).fetchone()[0]
        determination_id = conn.execute(
            """
            INSERT INTO ewms.origin_determinations
                (
                    tenant_id, item_id, trade_agreement_id, country_of_origin,
                    determination_result, qualifying_quantity, uom_code,
                    valid_from, determined_at, status
                )
            VALUES (%s, %s, %s, 'KR', 'FAIL', 10, 'EA', CURRENT_DATE - 1, now(), 'ACTIVE')
            RETURNING id
            """,
            (tenant_a, item_id, agreement_id),
        ).fetchone()[0]
        certificate_id = conn.execute(
            """
            INSERT INTO ewms.origin_certificates
                (
                    tenant_id, certificate_no, certificate_type, trade_agreement_id,
                    exporter_partner_id, importer_partner_id, country_of_export,
                    country_of_import, issue_date, valid_from, valid_to, status, issued_at
                )
            VALUES (
                %s, %s, 'SELF_CERTIFICATION', %s, %s, %s, 'KR', 'US',
                CURRENT_DATE, CURRENT_DATE, CURRENT_DATE + 365, 'ISSUED', now()
            )
            RETURNING id
            """,
            (tenant_a, f"CO_{suffix}", agreement_id, partner_a, partner_a),
        ).fetchone()[0]
        _expect_database_rejection(
            conn,
            "failed_origin_determination",
            lambda: conn.execute(
                """
                INSERT INTO ewms.origin_certificate_lines
                    (
                        tenant_id, origin_certificate_id, line_no, origin_determination_id,
                        item_id, goods_description, hs_code, origin_country_code,
                        certified_quantity, uom_code
                    )
                VALUES (%s, %s, 1, %s, %s, 'Smoke item', '0000', 'KR', 1, 'EA')
                """,
                (tenant_a, certificate_id, determination_id, item_id),
            ),
            {"23514", "55000", "P0001"},
        )

        payment_request_id = conn.execute(
            """
            INSERT INTO ewms.payment_requests
                (
                    tenant_id, payment_request_no, payer_organization_id,
                    payee_partner_id, currency_code, requested_amount,
                    requested_payment_date, payment_reason
                )
            VALUES (%s, %s, %s, %s, 'KRW', 100, CURRENT_DATE, 'Smoke payment')
            RETURNING id
            """,
            (tenant_a, f"PAYREQ_{suffix}", organization_a, partner_a),
        ).fetchone()[0]
        _expect_database_rejection(
            conn,
            "payment_allocation_total",
            lambda: (
                conn.execute(
                    """
                    INSERT INTO ewms.payment_request_lines
                        (tenant_id, payment_request_id, line_no, line_description, amount)
                    VALUES (%s, %s, 1, 'Smoke line', 90)
                    """,
                    (tenant_a, payment_request_id),
                ),
                conn.execute(
                    "SET CONSTRAINTS ewms.trg_validate_payment_request_total IMMEDIATE"
                ),
            ),
            {"23514", "55000", "P0001"},
        )

        charge_code_id = conn.execute(
            """
            INSERT INTO ewms.charge_codes
                (tenant_id, charge_code, charge_name, charge_category, default_basis, taxable)
            VALUES (%s, %s, 'Smoke settlement charge', 'HANDLING', 'FLAT', false)
            RETURNING id
            """,
            (tenant_a, f"CHGCODE_{suffix}"),
        ).fetchone()[0]
        charge_id = conn.execute(
            """
            INSERT INTO ewms.charges
                (
                    tenant_id, charge_no, direction, charge_code_id,
                    warehouse_id, owner_partner_id, payer_partner_id,
                    payee_partner_id, service_date, currency_code,
                    net_amount, tax_amount, gross_amount, status
                )
            VALUES (
                %s, %s, 'RECEIVABLE', %s, %s, %s, %s, %s,
                CURRENT_DATE, 'KRW', 100, 0, 100, 'APPROVED'
            )
            RETURNING id
            """,
            (
                tenant_a,
                f"CHARGE_{suffix}",
                charge_code_id,
                warehouse_id,
                partner_a,
                counterparty_a,
                partner_a,
            ),
        ).fetchone()[0]
        invoice_id = conn.execute(
            """
            INSERT INTO ewms.invoices
                (
                    tenant_id, invoice_type, invoice_no, organization_id,
                    issuer_partner_id, recipient_partner_id, owner_partner_id,
                    invoice_date, currency_code, net_amount, tax_amount,
                    gross_amount, paid_amount, outstanding_amount,
                    status, approval_status, created_by
                )
            VALUES (
                %s, 'RECEIVABLE', %s, %s, %s, %s, %s,
                CURRENT_DATE, 'KRW', 100, 0, 100, 0, 100,
                'DRAFT', 'NOT_REQUIRED', %s
            )
            RETURNING id
            """,
            (
                tenant_a,
                f"INV_{suffix}",
                organization_a,
                partner_a,
                counterparty_a,
                partner_a,
                ewms_user_id,
            ),
        ).fetchone()[0]
        conn.execute(
            """
            INSERT INTO ewms.invoice_lines
                (
                    tenant_id, invoice_id, line_no, charge_code_id,
                    description, quantity, uom_code, unit_price,
                    net_amount, discount_amount, tax_amount, gross_amount
                )
            VALUES (%s, %s, 1, %s, 'Smoke invoice line', 1, 'EA', 100, 100, 0, 0, 100)
            """,
            (tenant_a, invoice_id, charge_code_id),
        )
        for next_invoice_status in ("RECEIVED", "VALIDATING", "APPROVED"):
            conn.execute(
                "UPDATE ewms.invoices SET status=%s WHERE id=%s",
                (next_invoice_status, invoice_id),
            )
        conn.execute(
            """
            UPDATE ewms.invoices
               SET status='POSTED', posted_at=statement_timestamp()
             WHERE id=%s
            """,
            (invoice_id,),
        )
        _expect_database_rejection(
            conn,
            "posted_invoice_core_mutation",
            lambda: conn.execute(
                "UPDATE ewms.invoices SET invoice_no=%s WHERE id=%s",
                (f"MUTATED_{suffix}", invoice_id),
            ),
            {"55000"},
        )

        settlement_id = conn.execute(
            """
            INSERT INTO ewms.settlements
                (
                    tenant_id, settlement_no, payer_partner_id, payee_partner_id,
                    owner_partner_id, currency_code, gross_charge_amount,
                    adjustment_amount, tax_amount, withholding_amount,
                    net_settlement_amount, due_date, status
                )
            VALUES (%s, %s, %s, %s, %s, 'KRW', 100, 0, 0, 0, 100, CURRENT_DATE, 'DRAFT')
            RETURNING id
            """,
            (
                tenant_a,
                f"SETTLE_{suffix}",
                counterparty_a,
                partner_a,
                partner_a,
            ),
        ).fetchone()[0]
        settlement_line_id = conn.execute(
            """
            INSERT INTO ewms.settlement_lines
                (
                    tenant_id, settlement_id, line_no, charge_id,
                    charge_amount, adjustment_amount, tax_amount,
                    settled_amount, status
                )
            VALUES (%s, %s, 1, %s, 100, 0, 0, 100, 'INCLUDED')
            RETURNING id
            """,
            (tenant_a, settlement_id, charge_id),
        ).fetchone()[0]
        conn.execute(
            "UPDATE ewms.settlements SET status='APPROVED' WHERE id=%s",
            (settlement_id,),
        )
        _expect_database_rejection(
            conn,
            "approved_settlement_line_mutation",
            lambda: conn.execute(
                "UPDATE ewms.settlement_lines SET adjustment_amount=1, settled_amount=101 WHERE id=%s",
                (settlement_line_id,),
            ),
            {"55000"},
        )

        accounting_period_id = conn.execute(
            """
            INSERT INTO ewms.accounting_periods
                (
                    tenant_id, organization_id, fiscal_year, period_no,
                    period_name, start_date, end_date, status
                )
            VALUES (
                %s, %s, EXTRACT(YEAR FROM CURRENT_DATE)::integer, 1,
                'Smoke period', CURRENT_DATE - 1, CURRENT_DATE + 1, 'OPEN'
            )
            RETURNING id
            """,
            (tenant_a, organization_a),
        ).fetchone()[0]
        debit_account_id = conn.execute(
            """
            INSERT INTO ewms.gl_accounts
                (
                    tenant_id, organization_id, account_code, account_name,
                    account_type, normal_balance, currency_code
                )
            VALUES (%s, %s, %s, 'Smoke receivable', 'ASSET', 'DEBIT', 'KRW')
            RETURNING id
            """,
            (tenant_a, organization_a, f"AR_{suffix}"),
        ).fetchone()[0]
        credit_account_id = conn.execute(
            """
            INSERT INTO ewms.gl_accounts
                (
                    tenant_id, organization_id, account_code, account_name,
                    account_type, normal_balance, currency_code
                )
            VALUES (%s, %s, %s, 'Smoke revenue', 'REVENUE', 'CREDIT', 'KRW')
            RETURNING id
            """,
            (tenant_a, organization_a, f"REV_{suffix}"),
        ).fetchone()[0]
        journal_batch_id = conn.execute(
            """
            INSERT INTO ewms.journal_batches
                (
                    tenant_id, organization_id, batch_no, batch_type,
                    accounting_date, accounting_period_id, currency_code,
                    total_debit, total_credit, status
                )
            VALUES (%s, %s, %s, 'BILLING', CURRENT_DATE, %s, 'KRW', 100, 100, 'DRAFT')
            RETURNING id
            """,
            (tenant_a, organization_a, f"JB_{suffix}", accounting_period_id),
        ).fetchone()[0]
        journal_entry_id = conn.execute(
            """
            INSERT INTO ewms.journal_entries
                (tenant_id, journal_batch_id, entry_no, source_type, source_id, description)
            VALUES (%s, %s, 1, 'INVOICE', %s, 'Smoke balanced entry')
            RETURNING id
            """,
            (tenant_a, journal_batch_id, invoice_id),
        ).fetchone()[0]
        journal_debit_line_id = conn.execute(
            """
            INSERT INTO ewms.journal_lines
                (
                    tenant_id, journal_entry_id, line_no, gl_account_id,
                    owner_partner_id, debit_amount, credit_amount, currency_code
                )
            VALUES (%s, %s, 1, %s, %s, 100, 0, 'KRW')
            RETURNING id
            """,
            (tenant_a, journal_entry_id, debit_account_id, partner_a),
        ).fetchone()[0]
        conn.execute(
            """
            INSERT INTO ewms.journal_lines
                (
                    tenant_id, journal_entry_id, line_no, gl_account_id,
                    owner_partner_id, debit_amount, credit_amount, currency_code
                )
            VALUES (%s, %s, 2, %s, %s, 0, 100, 'KRW')
            """,
            (tenant_a, journal_entry_id, credit_account_id, partner_a),
        )
        conn.execute(
            "UPDATE ewms.journal_batches SET status='APPROVED' WHERE id=%s",
            (journal_batch_id,),
        )
        conn.execute(
            """
            UPDATE ewms.journal_batches
               SET status='POSTED', posted_by=%s, posted_at=statement_timestamp()
             WHERE id=%s
            """,
            (ewms_user_id, journal_batch_id),
        )
        _expect_database_rejection(
            conn,
            "posted_journal_line_mutation",
            lambda: conn.execute(
                "UPDATE ewms.journal_lines SET debit_amount=99 WHERE id=%s",
                (journal_debit_line_id,),
            ),
            {"55000"},
        )

        _clear_request_context_for_owner_smoke(conn)
        _bind_session(conn, session_hash_b, tenant_b)
        visible_count = conn.execute(
            "SELECT count(*) FROM ewms.trade_cases WHERE id=%s",
            (trade_case_id,),
        ).fetchone()[0]
        if visible_count != 0:
            raise AssertionError("RLS exposed another tenant's trade case")

        conn.rollback()

    print(
        "EWMS rollback-only smoke tests passed: "
        "authenticated context/GUC spoof defense, session-switch rejection, same-tenant FK, "
        "blocking hold, append-only event, inventory/customs allocation gates, sealed customs "
        "declaration, UNI-PASS lifecycle, bonded/physical ledger coupling, origin PASS gate, "
        "allocation total, invoice/settlement reconciliation, balanced journal immutability, "
        "and RLS isolation"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
