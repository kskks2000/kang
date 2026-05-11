from __future__ import annotations

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware

from .auth_service import create_or_update_session, find_login_id
from .calendar_service import load_calendar_events
from .db import get_db
from .firebase_auth import verify_firebase_id_token
from .schemas import (
    CalendarEventsRequest,
    CalendarEventsResponse,
    FindLoginIdRequest,
    FindLoginIdResponse,
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
