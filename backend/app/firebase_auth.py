from __future__ import annotations

import json
import os
from typing import Any

import firebase_admin
from fastapi import HTTPException, status
from firebase_admin import auth, credentials

from .settings import settings


def _initialize_firebase() -> None:
    try:
        firebase_admin.get_app()
        return
    except ValueError:
        pass

    options: dict[str, str] = {}
    if settings.firebase_project_id:
        options["projectId"] = settings.firebase_project_id

    credentials_json = os.getenv("FIREBASE_CREDENTIALS_JSON")
    credentials_path = os.getenv("GOOGLE_APPLICATION_CREDENTIALS")

    if credentials_json:
        credential = credentials.Certificate(json.loads(credentials_json))
        firebase_admin.initialize_app(credential, options)
    elif credentials_path:
        credential = credentials.Certificate(credentials_path)
        firebase_admin.initialize_app(credential, options)
    else:
        firebase_admin.initialize_app(options=options)


def verify_firebase_id_token(id_token: str) -> dict[str, Any]:
    _initialize_firebase()
    try:
        return auth.verify_id_token(id_token)
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Firebase 로그인 토큰을 확인할 수 없습니다.",
        ) from exc
