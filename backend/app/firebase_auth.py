from __future__ import annotations

import json
import os
from functools import lru_cache
from typing import Any

import firebase_admin
import jwt
import requests
from cryptography import x509
from fastapi import HTTPException, status
from firebase_admin import auth, credentials

from .settings import settings


FIREBASE_CERTS_URL = (
    "https://www.googleapis.com/robot/v1/metadata/x509/"
    "securetoken@system.gserviceaccount.com"
)


def _initialize_firebase() -> bool:
    try:
        firebase_admin.get_app()
        return True
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
        return True
    if credentials_path:
        credential = credentials.Certificate(credentials_path)
        firebase_admin.initialize_app(credential, options)
        return True

    return False


@lru_cache(maxsize=1)
def _firebase_public_certs() -> dict[str, str]:
    response = requests.get(FIREBASE_CERTS_URL, timeout=10)
    response.raise_for_status()
    certs = response.json()
    if not isinstance(certs, dict):
        raise ValueError("Firebase certificate response is invalid.")
    return {str(key): str(value) for key, value in certs.items()}


def _verify_with_public_certs(id_token: str) -> dict[str, Any]:
    if not settings.firebase_project_id:
        raise ValueError("FIREBASE_PROJECT_ID is required.")

    header = jwt.get_unverified_header(id_token)
    key_id = header.get("kid")
    if not key_id:
        raise ValueError("Firebase token is missing key id.")

    cert = _firebase_public_certs().get(str(key_id))
    if cert is None:
        _firebase_public_certs.cache_clear()
        cert = _firebase_public_certs().get(str(key_id))
    if cert is None:
        raise ValueError("Firebase token signing certificate was not found.")

    issuer = f"https://securetoken.google.com/{settings.firebase_project_id}"
    certificate = x509.load_pem_x509_certificate(cert.encode("utf-8"))
    public_key = certificate.public_key()

    decoded = jwt.decode(
        id_token,
        public_key,
        algorithms=["RS256"],
        audience=settings.firebase_project_id,
        issuer=issuer,
    )
    if not isinstance(decoded, dict):
        raise ValueError("Firebase token payload is invalid.")
    return decoded


def verify_firebase_id_token(id_token: str) -> dict[str, Any]:
    try:
        if _initialize_firebase():
            return auth.verify_id_token(id_token)
        return _verify_with_public_certs(id_token)
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Firebase 로그인 토큰을 확인할 수 없습니다.",
        ) from exc
