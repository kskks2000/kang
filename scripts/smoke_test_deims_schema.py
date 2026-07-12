"""Rollback-only DEIMS integrity smoke tests without exposing credentials."""

from __future__ import annotations

import sys
from collections.abc import Callable
from pathlib import Path
from uuid import uuid4


REPO_ROOT = Path(__file__).resolve().parents[1]
BACKEND_DIR = REPO_ROOT / "backend"
sys.path.insert(0, str(BACKEND_DIR))

import psycopg  # noqa: E402
from app.settings import settings  # noqa: E402


def _set_tenant(conn: psycopg.Connection, tenant_id: object) -> None:
    conn.execute("SELECT set_config('deims.tenant_id', %s, true)", (str(tenant_id),))


def _expect_database_rejection(
    conn: psycopg.Connection,
    savepoint_name: str,
    operation: Callable[[], None],
) -> None:
    conn.execute(f"SAVEPOINT {savepoint_name}")
    try:
        operation()
    except psycopg.Error:
        conn.execute(f"ROLLBACK TO SAVEPOINT {savepoint_name}")
        conn.execute(f"RELEASE SAVEPOINT {savepoint_name}")
        return
    conn.execute(f"ROLLBACK TO SAVEPOINT {savepoint_name}")
    conn.execute(f"RELEASE SAVEPOINT {savepoint_name}")
    raise AssertionError(f"Expected database rejection did not occur: {savepoint_name}")


def main() -> int:
    suffix = uuid4().hex[:12]

    with psycopg.connect(settings.database_url) as conn:
        version_num = conn.execute(
            "SELECT current_setting('server_version_num')::integer"
        ).fetchone()[0]
        if not 110000 <= version_num < 120000:
            raise RuntimeError("DEIMS smoke tests require PostgreSQL 11.x")

        tenant_a = conn.execute(
            """
            INSERT INTO deims.tenants (tenant_code, tenant_name)
            VALUES (%s, %s)
            RETURNING id
            """,
            (f"SMOKE_A_{suffix}", "DEIMS smoke tenant A"),
        ).fetchone()[0]
        tenant_b = conn.execute(
            """
            INSERT INTO deims.tenants (tenant_code, tenant_name)
            VALUES (%s, %s)
            RETURNING id
            """,
            (f"SMOKE_B_{suffix}", "DEIMS smoke tenant B"),
        ).fetchone()[0]

        _set_tenant(conn, tenant_a)
        organization_a = conn.execute(
            """
            INSERT INTO deims.organizations
                (tenant_id, organization_code, organization_name)
            VALUES (%s, %s, %s)
            RETURNING id
            """,
            (tenant_a, f"ORG_{suffix}", "Smoke organization"),
        ).fetchone()[0]
        partner_a = conn.execute(
            """
            INSERT INTO deims.business_partners
                (tenant_id, partner_code, partner_name)
            VALUES (%s, %s, %s)
            RETURNING id
            """,
            (tenant_a, f"PARTNER_A_{suffix}", "Smoke partner A"),
        ).fetchone()[0]

        _set_tenant(conn, tenant_b)
        partner_b = conn.execute(
            """
            INSERT INTO deims.business_partners
                (tenant_id, partner_code, partner_name)
            VALUES (%s, %s, %s)
            RETURNING id
            """,
            (tenant_b, f"PARTNER_B_{suffix}", "Smoke partner B"),
        ).fetchone()[0]

        _set_tenant(conn, tenant_a)
        _expect_database_rejection(
            conn,
            "cross_tenant_reference",
            lambda: conn.execute(
                """
                INSERT INTO deims.trade_cases
                    (tenant_id, case_no, direction, owner_partner_id)
                VALUES (%s, %s, 'IMPORT', %s)
                """,
                (tenant_a, f"BAD_CASE_{suffix}", partner_b),
            ),
        )

        trade_case_id = conn.execute(
            """
            INSERT INTO deims.trade_cases
                (tenant_id, case_no, direction, owner_partner_id, status)
            VALUES (%s, %s, 'EXPORT', %s, 'OPEN')
            RETURNING id
            """,
            (tenant_a, f"CASE_{suffix}", partner_a),
        ).fetchone()[0]
        trade_shipment_id = conn.execute(
            """
            INSERT INTO deims.trade_shipments
                (tenant_id, owner_partner_id, trade_shipment_no, direction)
            VALUES (%s, %s, %s, 'EXPORT')
            RETURNING id
            """,
            (tenant_a, partner_a, f"TS_{suffix}"),
        ).fetchone()[0]
        conn.execute(
            """
            INSERT INTO deims.trade_case_shipments
                (tenant_id, trade_case_id, trade_shipment_id)
            VALUES (%s, %s, %s)
            """,
            (tenant_a, trade_case_id, trade_shipment_id),
        )
        hold_id = conn.execute(
            """
            INSERT INTO deims.compliance_holds
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
                "UPDATE deims.trade_shipments SET status='BOOKED' WHERE id=%s",
                (trade_shipment_id,),
            ),
        )
        conn.execute(
            """
            UPDATE deims.compliance_holds
               SET status='RELEASED', released_at=now(), release_reason='Smoke release'
             WHERE id=%s
            """,
            (hold_id,),
        )
        conn.execute(
            "UPDATE deims.trade_shipments SET status='BOOKED' WHERE id=%s",
            (trade_shipment_id,),
        )

        event_id = conn.execute(
            """
            INSERT INTO deims.trade_case_events
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
                "UPDATE deims.trade_case_events SET event_type='MUTATED' WHERE id=%s",
                (event_id,),
            ),
        )

        item_id = conn.execute(
            """
            INSERT INTO deims.items
                (tenant_id, item_code, item_name, base_uom_code)
            VALUES (%s, %s, 'Smoke item', 'EA')
            RETURNING id
            """,
            (tenant_a, f"ITEM_{suffix}"),
        ).fetchone()[0]
        agreement_id = conn.execute(
            """
            INSERT INTO deims.trade_agreements
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
            INSERT INTO deims.origin_determinations
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
            INSERT INTO deims.origin_certificates
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
                INSERT INTO deims.origin_certificate_lines
                    (
                        tenant_id, origin_certificate_id, line_no, origin_determination_id,
                        item_id, goods_description, hs_code, origin_country_code,
                        certified_quantity, uom_code
                    )
                VALUES (%s, %s, 1, %s, %s, 'Smoke item', '0000', 'KR', 1, 'EA')
                """,
                (tenant_a, certificate_id, determination_id, item_id),
            ),
        )

        payment_request_id = conn.execute(
            """
            INSERT INTO deims.payment_requests
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
                    INSERT INTO deims.payment_request_lines
                        (tenant_id, payment_request_id, line_no, line_description, amount)
                    VALUES (%s, %s, 1, 'Smoke line', 90)
                    """,
                    (tenant_a, payment_request_id),
                ),
                conn.execute("SET CONSTRAINTS trg_validate_payment_request_total IMMEDIATE"),
            ),
        )

        _set_tenant(conn, tenant_b)
        visible_count = conn.execute(
            "SELECT count(*) FROM deims.trade_cases WHERE id=%s",
            (trade_case_id,),
        ).fetchone()[0]
        if visible_count != 0:
            raise AssertionError("RLS exposed another tenant's trade case")

        conn.rollback()

    print(
        "DEIMS rollback-only smoke tests passed: "
        "same-tenant FK, blocking hold, append-only event, origin PASS gate, "
        "allocation total, and RLS isolation"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
