from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import quote_plus
from urllib.parse import unquote
from urllib.parse import urlparse


REQUIRED_POSTGRES_HOST = "211.47.74.33"
REQUIRED_POSTGRES_DB = "dbkang"
REQUIRED_POSTGRES_USER = "kang"


def _csv(value: str) -> list[str]:
    return [item.strip() for item in value.split(",") if item.strip()]


def _load_env_file() -> None:
    env_path = Path(__file__).resolve().parents[1] / ".env"
    if not env_path.exists():
        return

    for raw_line in env_path.read_text(encoding="utf-8-sig").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue

        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key:
            os.environ.setdefault(key, value)


def _validate_database_url(database_url: str) -> None:
    parsed = urlparse(database_url)
    db_name = unquote(parsed.path.lstrip("/"))
    user = unquote(parsed.username or "")
    host = parsed.hostname or ""

    if host != REQUIRED_POSTGRES_HOST or db_name != REQUIRED_POSTGRES_DB or user != REQUIRED_POSTGRES_USER:
        raise RuntimeError(
            "Refusing to start with a PostgreSQL connection outside "
            f"{REQUIRED_POSTGRES_HOST}/{REQUIRED_POSTGRES_DB} as {REQUIRED_POSTGRES_USER}."
        )


@dataclass(frozen=True)
class Settings:
    database_url: str
    firebase_project_id: str
    cors_allowed_origins: list[str]


def load_settings() -> Settings:
    _load_env_file()

    database_url = os.getenv("DATABASE_URL")
    if not database_url:
        host = os.getenv("POSTGRES_HOST", REQUIRED_POSTGRES_HOST)
        port = os.getenv("POSTGRES_PORT", "5432")
        db_name = os.getenv("POSTGRES_DB", REQUIRED_POSTGRES_DB)
        user = os.getenv("POSTGRES_USER", REQUIRED_POSTGRES_USER)
        password = os.getenv("POSTGRES_PASSWORD", "")
        database_url = (
            f"postgresql://{quote_plus(user)}:{quote_plus(password)}"
            f"@{host}:{port}/{quote_plus(db_name)}"
        )

    _validate_database_url(database_url)

    cors_origins = os.getenv(
        "CORS_ALLOWED_ORIGINS",
        "http://localhost:3000,http://localhost:5000,http://localhost:8080,"
        "http://127.0.0.1:3000,http://127.0.0.1:5000,http://127.0.0.1:8080,"
        "https://kang-84cdd.web.app,https://kang-84cdd.firebaseapp.com,"
        "https://www.kang.ai.kr,https://kang.ai.kr,"
        "http://www.kang.ai.kr,http://kang.ai.kr",
    )

    firebase_project_id = (
        os.getenv("KANG_FIREBASE_PROJECT_ID")
        or os.getenv("FIREBASE_PROJECT_ID")
        or os.getenv("GCLOUD_PROJECT")
        or os.getenv("GOOGLE_CLOUD_PROJECT")
        or ""
    )

    return Settings(
        database_url=database_url,
        firebase_project_id=firebase_project_id,
        cors_allowed_origins=_csv(cors_origins),
    )


settings = load_settings()
