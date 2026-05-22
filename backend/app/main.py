from __future__ import annotations

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware

from .academy_info_service import load_academy_info_basic
from .auth_service import create_or_update_session, find_login_id
from .calendar_service import load_calendar_events
from .db import get_db
from .drive_service import (
    import_google_sheet,
    list_google_drive_rows,
    list_google_sheet_files,
    user_id_from_claims,
)
from .financial_market_service import load_financial_markets
from .firebase_auth import verify_firebase_id_token
from .market_cap_service import load_global_market_cap_top
from .schemas import (
    AcademyInfoBasicResponse,
    CalendarEventsRequest,
    CalendarEventsResponse,
    DriveFilesRequest,
    DriveFilesResponse,
    DriveImportRequest,
    DriveImportResponse,
    DriveRowsRequest,
    DriveRowsResponse,
    FinancialMarketsResponse,
    FindLoginIdRequest,
    FindLoginIdResponse,
    MarketCapTopResponse,
    SessionRequest,
    SessionResponse,
)
from .settings import settings


app = FastAPI(title="Kang API", version="0.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_allowed_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


def _client_ip(request: Request) -> str | None:
    forwarded_for = request.headers.get("x-forwarded-for")
    if forwarded_for:
        return forwarded_for.split(",", 1)[0].strip()
    return request.client.host if request.client else None


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/academy-info/basic", response_model=AcademyInfoBasicResponse)
def academy_info_basic() -> dict:
    return load_academy_info_basic()


@app.get("/market-cap/global-top", response_model=MarketCapTopResponse)
def market_cap_global_top() -> dict:
    return load_global_market_cap_top(limit=100)


@app.get("/financial/markets", response_model=FinancialMarketsResponse)
def financial_markets() -> dict:
    return load_financial_markets()


@app.post("/auth/session", response_model=SessionResponse)
def create_session(payload: SessionRequest, request: Request) -> dict:
    claims = verify_firebase_id_token(payload.id_token)
    with get_db() as conn:
        return create_or_update_session(
            conn,
            claims=claims,
            ip_address=_client_ip(request),
            user_agent=request.headers.get("user-agent"),
        )


@app.post("/auth/find-login-id", response_model=FindLoginIdResponse)
def find_login_id_endpoint(payload: FindLoginIdRequest) -> dict:
    with get_db() as conn:
        return find_login_id(conn, email=payload.email)


@app.post("/calendar/events", response_model=CalendarEventsResponse)
def calendar_events(payload: CalendarEventsRequest) -> dict:
    verify_firebase_id_token(payload.id_token)
    events = load_calendar_events(
        access_token=payload.google_access_token,
        time_min=payload.time_min,
        time_max=payload.time_max,
        max_results=payload.max_results,
    )
    return {"events": events}


@app.post("/drive/files", response_model=DriveFilesResponse)
def drive_files(payload: DriveFilesRequest) -> dict:
    verify_firebase_id_token(payload.id_token)
    files = list_google_sheet_files(
        access_token=payload.google_access_token,
        query=payload.query,
        page_size=payload.page_size,
    )
    return {"files": files}


@app.post("/drive/import", response_model=DriveImportResponse)
def drive_import(payload: DriveImportRequest) -> dict:
    claims = verify_firebase_id_token(payload.id_token)
    with get_db() as conn:
        user_id = user_id_from_claims(conn, claims)
        return import_google_sheet(
            conn,
            user_id=user_id,
            access_token=payload.google_access_token,
            file_id=payload.file_id,
            file_name=payload.file_name,
            sheet_name=payload.sheet_name,
            max_rows=payload.max_rows,
        )


@app.post("/drive/rows", response_model=DriveRowsResponse)
def drive_rows(payload: DriveRowsRequest) -> dict:
    claims = verify_firebase_id_token(payload.id_token)
    with get_db() as conn:
        user_id = user_id_from_claims(conn, claims)
        rows = list_google_drive_rows(
            conn,
            user_id=user_id,
            search=payload.search,
            limit=payload.limit,
        )
    return {"rows": rows}
