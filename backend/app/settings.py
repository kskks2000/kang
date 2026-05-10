from __future__ import annotations

import os
from dataclasses import dataclass
from urllib.parse import quote_plus


def _csv(value: str) -> list[str]:
    return [item.strip() for item in value.split(",") if item.strip()]


@dataclass(frozen=True)
class Settings:
    database_url: str
    firebase_project_id: str
    cors_allowed_origins: list[str]


def load_settings() -> Settings:
    database_url = os.getenv("DATABASE_URL")
    if not database_url:
        host = os.getenv("POSTGRES_HOST", "211.47.74.33")
        port = os.getenv("POSTGRES_PORT", "5432")
        db_name = os.getenv("POSTGRES_DB", "dbkang")
        user = os.getenv("POSTGRES_USER", "kang")
        password = os.getenv("POSTGRES_PASSWORD", "")
        database_url = (
            f"postgresql://{quote_plus(user)}:{quote_plus(password)}"
            f"@{host}:{port}/{quote_plus(db_name)}"
        )

    cors_origins = os.getenv(
        "CORS_ALLOWED_ORIGINS",
        "http://localhost:3000,http://localhost:5000,http://localhost:8080,"
        "http://127.0.0.1:3000,http://127.0.0.1:5000,http://127.0.0.1:8080",
    )

    return Settings(
        database_url=database_url,
        firebase_project_id=os.getenv("FIREBASE_PROJECT_ID", ""),
        cors_allowed_origins=_csv(cors_origins),
    )


settings = load_settings()
