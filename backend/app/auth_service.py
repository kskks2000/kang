from __future__ import annotations

import json
from typing import Any

from fastapi import HTTPException, status
from psycopg import Connection
from psycopg.rows import dict_row
from psycopg.types.json import Jsonb


def _provider_from_claims(claims: dict[str, Any]) -> str:
    firebase_claims = claims.get("firebase")
    if isinstance(firebase_claims, dict):
        provider = firebase_claims.get("sign_in_provider")
        if provider:
            return str(provider)
    return "firebase"


def _safe_json(data: dict[str, Any]) -> dict[str, Any]:
    return json.loads(json.dumps(data, default=str))


def _mask_login_id(value: str) -> str:
    if "@" not in value:
        if len(value) <= 3:
            return value[0] + "*" * max(len(value) - 1, 0)
        return value[:2] + "*" * (len(value) - 3) + value[-1]

    local, domain = value.split("@", 1)
    if len(local) <= 2:
        masked_local = local[0] + "*"
    else:
        masked_local = local[0] + "*" * (len(local) - 2) + local[-1]
    return f"{masked_local}@{domain}"


def _record_login_event(
    cur: Any,
    *,
    user_id: str | None,
    firebase_uid: str | None,
    provider: str | None,
    success: bool,
    failure_reason: str | None,
    ip_address: str | None,
    user_agent: str | None,
) -> None:
    cur.execute(
        """
        INSERT INTO metaserver.login_events (
            user_id, firebase_uid, provider, success, failure_reason, ip_address, user_agent
        )
        VALUES (%s, %s, %s, %s, %s, %s, %s)
        """,
        (user_id, firebase_uid, provider, success, failure_reason, ip_address, user_agent),
    )


def create_or_update_session(
    conn: Connection,
    *,
    claims: dict[str, Any],
    ip_address: str | None,
    user_agent: str | None,
) -> dict[str, Any]:
    firebase_uid = str(claims.get("uid") or claims.get("sub") or "")
    email = str(claims.get("email") or "").strip().lower()
    email_verified = bool(claims.get("email_verified") or False)
    display_name = (claims.get("name") or claims.get("display_name") or "") or None
    photo_url = (claims.get("picture") or "") or None
    provider = _provider_from_claims(claims)

    with conn.cursor(row_factory=dict_row) as cur:
        if not firebase_uid or not email:
            _record_login_event(
                cur,
                user_id=None,
                firebase_uid=firebase_uid or None,
                provider=provider,
                success=False,
                failure_reason="missing_email_or_uid",
                ip_address=ip_address,
                user_agent=user_agent,
            )
            conn.commit()
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Firebase 계정의 이메일 정보를 확인할 수 없습니다.",
            )

        cur.execute(
            """
            SELECT id, email, display_name, role_code, status, firebase_uid
            FROM metaserver.family_login_allowlist
            WHERE revoked_at IS NULL
              AND (lower(email) = lower(%s) OR firebase_uid = %s)
            ORDER BY CASE WHEN firebase_uid = %s THEN 0 ELSE 1 END, created_at DESC
            LIMIT 1
            """,
            (email, firebase_uid, firebase_uid),
        )
        allowlist = cur.fetchone()
        if not allowlist:
            _record_login_event(
                cur,
                user_id=None,
                firebase_uid=firebase_uid,
                provider=provider,
                success=False,
                failure_reason="not_allowlisted",
                ip_address=ip_address,
                user_agent=user_agent,
            )
            conn.commit()
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="가족 계정으로 등록된 이메일만 사용할 수 있습니다.",
            )

        role_code = allowlist["role_code"] or "family_member"
        preferred_name = display_name or allowlist["display_name"] or email.split("@", 1)[0]

        cur.execute(
            """
            SELECT id
            FROM metaserver.users
            WHERE firebase_uid = %s
               OR (lower(email) = lower(%s) AND deleted_at IS NULL)
            ORDER BY CASE WHEN firebase_uid = %s THEN 0 ELSE 1 END
            LIMIT 1
            """,
            (firebase_uid, email, firebase_uid),
        )
        existing_user = cur.fetchone()

        if existing_user:
            cur.execute(
                """
                UPDATE metaserver.users
                SET firebase_uid = %s,
                    email = %s,
                    email_verified = %s,
                    display_name = %s,
                    photo_url = %s,
                    last_login_at = now(),
                    login_id = COALESCE(login_id, %s),
                    user_name = CASE WHEN user_name = '' THEN %s ELSE user_name END,
                    auth_provider = %s,
                    updated_at = now()
                WHERE id = %s
                RETURNING id, firebase_uid, email, display_name, photo_url, user_no,
                          user_name, user_type, status::text AS status, is_active, locked_at
                """,
                (
                    firebase_uid,
                    email,
                    email_verified,
                    display_name,
                    photo_url,
                    email,
                    preferred_name,
                    provider,
                    existing_user["id"],
                ),
            )
            user = cur.fetchone()
        else:
            cur.execute(
                """
                INSERT INTO metaserver.users (
                    firebase_uid, email, email_verified, display_name, photo_url,
                    last_login_at, login_id, user_name, user_type, auth_provider, is_active
                )
                VALUES (%s, %s, %s, %s, %s, now(), %s, %s, 'member', %s, true)
                RETURNING id, firebase_uid, email, display_name, photo_url, user_no,
                          user_name, user_type, status::text AS status, is_active, locked_at
                """,
                (
                    firebase_uid,
                    email,
                    email_verified,
                    display_name,
                    photo_url,
                    email,
                    preferred_name,
                    provider,
                ),
            )
            user = cur.fetchone()

        if user["status"] != "active" or not user["is_active"] or user["locked_at"] is not None:
            _record_login_event(
                cur,
                user_id=str(user["id"]),
                firebase_uid=firebase_uid,
                provider=provider,
                success=False,
                failure_reason="user_inactive_or_locked",
                ip_address=ip_address,
                user_agent=user_agent,
            )
            conn.commit()
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="비활성화되었거나 잠긴 계정입니다.",
            )

        cur.execute(
            """
            INSERT INTO metaserver.user_profiles (user_id)
            VALUES (%s)
            ON CONFLICT (user_id) DO NOTHING
            """,
            (user["id"],),
        )

        cur.execute(
            """
            INSERT INTO metaserver.auth_identities (
                user_id, provider, provider_uid, email, email_verified, raw_claims
            )
            VALUES (%s, %s, %s, %s, %s, %s)
            ON CONFLICT (provider, provider_uid) DO UPDATE
            SET user_id = EXCLUDED.user_id,
                email = EXCLUDED.email,
                email_verified = EXCLUDED.email_verified,
                raw_claims = EXCLUDED.raw_claims,
                updated_at = now()
            """,
            (
                user["id"],
                provider,
                firebase_uid,
                email,
                email_verified,
                Jsonb(_safe_json(claims)),
            ),
        )

        cur.execute("SELECT id FROM metaserver.roles WHERE code = %s", (role_code,))
        role = cur.fetchone()
        if role:
            cur.execute(
                """
                INSERT INTO metaserver.user_roles (user_id, role_id)
                VALUES (%s, %s)
                ON CONFLICT (user_id, role_id) DO NOTHING
                """,
                (user["id"], role["id"]),
            )

        cur.execute(
            """
            UPDATE metaserver.family_login_allowlist
            SET firebase_uid = COALESCE(firebase_uid, %s),
                first_accepted_user_id = COALESCE(first_accepted_user_id, %s),
                status = 'active',
                accepted_at = COALESCE(accepted_at, now())
            WHERE id = %s
            """,
            (firebase_uid, user["id"], allowlist["id"]),
        )

        _record_login_event(
            cur,
            user_id=str(user["id"]),
            firebase_uid=firebase_uid,
            provider=provider,
            success=True,
            failure_reason=None,
            ip_address=ip_address,
            user_agent=user_agent,
        )

        return {
            "user": {
                "id": str(user["id"]),
                "firebase_uid": user["firebase_uid"],
                "email": user["email"],
                "display_name": user["display_name"],
                "photo_url": user["photo_url"],
                "user_no": user["user_no"],
                "user_name": user["user_name"],
                "user_type": user["user_type"],
                "role_code": role_code,
                "allowlist_status": "active",
            }
        }


def find_login_id(conn: Connection, *, email: str) -> dict[str, Any]:
    normalized_email = email.strip().lower()
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(
            """
            SELECT login_id, email
            FROM metaserver.users
            WHERE lower(email) = lower(%s)
              AND deleted_at IS NULL
              AND is_active = true
            LIMIT 1
            """,
            (normalized_email,),
        )
        user = cur.fetchone()
        if user:
            login_id = user["login_id"] or user["email"]
            return {
                "found": True,
                "masked_login_id": _mask_login_id(login_id),
                "message": "가입된 ID를 찾았습니다.",
            }

        cur.execute(
            """
            SELECT email
            FROM metaserver.family_login_allowlist
            WHERE lower(email) = lower(%s)
              AND revoked_at IS NULL
            LIMIT 1
            """,
            (normalized_email,),
        )
        allowlist = cur.fetchone()
        if allowlist:
            return {
                "found": True,
                "masked_login_id": _mask_login_id(allowlist["email"]),
                "message": "가족 초대 목록에 등록된 ID입니다. 회원가입을 진행해 주세요.",
            }

        return {
            "found": False,
            "masked_login_id": None,
            "message": "등록된 ID를 찾을 수 없습니다.",
        }
