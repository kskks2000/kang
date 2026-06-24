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
DEFAULT_APP_PUBLIC_URL = "https://www.kang.ai.kr"
DEFAULT_SEOUL_SUBWAY_BASE_URL = "http://swopenapi.seoul.go.kr/api/subway"
DEFAULT_SUBWAY_STATION = "야탑"
DEFAULT_SUBWAY_LINE = "수인분당선"


def _csv(value: str) -> list[str]:
    return [item.strip() for item in value.split(",") if item.strip()]


def _bool(value: str) -> bool:
    return value.strip().lower() in {"1", "true", "yes", "y", "on"}


def _load_env_file(env_path: Path, *, override: bool, protected_keys: set[str]) -> None:
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
            if key in protected_keys:
                continue
            if override or key not in os.environ:
                os.environ[key] = value


def _load_env_files() -> None:
    settings_path = Path(__file__).resolve()
    backend_dir = settings_path.parents[1]
    repo_root = settings_path.parents[2]
    protected_keys = set(os.environ)

    _load_env_file(repo_root / ".env", override=False, protected_keys=protected_keys)
    _load_env_file(backend_dir / ".env", override=True, protected_keys=protected_keys)


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
    app_public_url: str
    http_user_agent: str
    browser_user_agent: str
    academyinfo_service_key: str
    seoul_subway_api_key: str
    seoul_subway_base_url: str
    default_subway_station: str
    default_subway_line: str
    sftp_host: str
    sftp_port: str
    sftp_username: str
    sftp_password: str
    sftp_remote_path: str
    tossinvest_api_base_url: str
    tossinvest_client_id: str
    tossinvest_client_secret: str
    tossinvest_account: str
    tossinvest_trading_enabled: bool
    tossinvest_trading_allowed_emails: list[str]


def load_settings() -> Settings:
    _load_env_files()

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
        "https://www.kang.ai.kr,https://kang.ai.kr,"
        "http://www.kang.ai.kr,http://kang.ai.kr,"
        "https://kang-84cdd.web.app,https://kang-84cdd.firebaseapp.com",
    )

    firebase_project_id = (
        os.getenv("KANG_FIREBASE_PROJECT_ID")
        or os.getenv("FIREBASE_PROJECT_ID")
        or os.getenv("GCLOUD_PROJECT")
        or os.getenv("GOOGLE_CLOUD_PROJECT")
        or ""
    )

    app_public_url = os.getenv("APP_PUBLIC_URL", DEFAULT_APP_PUBLIC_URL).strip()
    if not app_public_url:
        app_public_url = DEFAULT_APP_PUBLIC_URL

    http_user_agent = os.getenv("HTTP_USER_AGENT", "").strip()
    if not http_user_agent:
        http_user_agent = f"KangPrivateHub/1.0 (+{app_public_url})"

    browser_user_agent = os.getenv("BROWSER_USER_AGENT", "").strip()
    if not browser_user_agent:
        browser_user_agent = f"Mozilla/5.0 (compatible; {http_user_agent})"

    return Settings(
        database_url=database_url,
        firebase_project_id=firebase_project_id,
        cors_allowed_origins=_csv(cors_origins),
        app_public_url=app_public_url,
        http_user_agent=http_user_agent,
        browser_user_agent=browser_user_agent,
        academyinfo_service_key=os.getenv("ACADEMYINFO_SERVICE_KEY", "").strip(),
        seoul_subway_api_key=os.getenv("SEOUL_SUBWAY_API_KEY", "sample").strip()
        or "sample",
        seoul_subway_base_url=os.getenv(
            "SEOUL_SUBWAY_BASE_URL",
            DEFAULT_SEOUL_SUBWAY_BASE_URL,
        ).strip()
        or DEFAULT_SEOUL_SUBWAY_BASE_URL,
        default_subway_station=os.getenv(
            "DEFAULT_SUBWAY_STATION",
            DEFAULT_SUBWAY_STATION,
        ).strip()
        or DEFAULT_SUBWAY_STATION,
        default_subway_line=os.getenv(
            "DEFAULT_SUBWAY_LINE",
            DEFAULT_SUBWAY_LINE,
        ).strip()
        or DEFAULT_SUBWAY_LINE,
        sftp_host=os.getenv("SFTP_HOST", "").strip(),
        sftp_port=os.getenv("SFTP_PORT", "22").strip() or "22",
        sftp_username=os.getenv("SFTP_USERNAME", "").strip(),
        sftp_password=os.getenv("SFTP_PASSWORD", "").strip(),
        sftp_remote_path=os.getenv("SFTP_REMOTE_PATH", "").strip(),
        tossinvest_api_base_url=os.getenv(
            "TOSSINVEST_API_BASE_URL",
            "https://openapi.tossinvest.com",
        ).strip()
        or "https://openapi.tossinvest.com",
        tossinvest_client_id=os.getenv("TOSSINVEST_CLIENT_ID", "").strip(),
        tossinvest_client_secret=os.getenv("TOSSINVEST_CLIENT_SECRET", "").strip(),
        tossinvest_account=os.getenv("TOSSINVEST_ACCOUNT", "").strip(),
        tossinvest_trading_enabled=_bool(
            os.getenv("TOSSINVEST_TRADING_ENABLED", ""),
        ),
        tossinvest_trading_allowed_emails=[
            item.lower() for item in _csv(os.getenv("TOSSINVEST_TRADING_ALLOWED_EMAILS", ""))
        ],
    )


settings = load_settings()
