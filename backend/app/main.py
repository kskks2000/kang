from __future__ import annotations

from typing import Optional

from fastapi import FastAPI, HTTPException, Query, Request
from fastapi.middleware.cors import CORSMiddleware

from .academy_info_service import load_academy_info_basic
from .auth_service import create_or_update_session, find_login_id
from .calendar_service import load_calendar_events
from .db import get_db
from .drive_service import (
    import_google_sheet,
    list_google_drive_rows,
    list_google_sheet_names,
    list_google_sheet_files,
    user_id_from_claims,
)
from .financial_market_service import load_financial_markets
from .firebase_auth import verify_firebase_id_token
from .market_cap_service import load_global_market_cap_top
from .krx_stock_search_service import search_krx_stocks
from .subway_service import load_subway_overview
from .tossinvest_service import (
    TossInvestApiError,
    cancel_toss_order,
    create_toss_order,
    get_toss_order,
    load_toss_stock_candles,
    load_toss_stock_dashboard,
    modify_toss_order,
)
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
    DriveSheetNamesRequest,
    DriveSheetNamesResponse,
    FinancialMarketsResponse,
    FindLoginIdRequest,
    FindLoginIdResponse,
    MarketCapTopResponse,
    SessionRequest,
    SessionResponse,
    SubwayOverviewResponse,
    TossInvestCandlesResponse,
    TossInvestOpenOrder,
    TossInvestOrderActionResponse,
    TossInvestOrderModifyRequest,
    TossInvestOrderRequest,
    TossInvestOrderResponse,
    TossInvestStockDashboardResponse,
    TossInvestStockSearchResponse,
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


def _client_ip(request: Request) -> Optional[str]:
    forwarded_for = request.headers.get("x-forwarded-for")
    if forwarded_for:
        return forwarded_for.split(",", 1)[0].strip()
    return request.client.host if request.client else None


def _require_firebase_bearer_token(request: Request) -> dict:
    authorization = request.headers.get("authorization", "")
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token.strip():
        raise HTTPException(status_code=401, detail="Firebase 인증 토큰이 필요합니다.")
    return verify_firebase_id_token(token.strip())


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


@app.get("/toss/stock-dashboard", response_model=TossInvestStockDashboardResponse)
def toss_stock_dashboard(
    request: Request,
    market: str = "KR",
    symbol: Optional[str] = None,
    symbols: Optional[str] = None,
    candle_interval: str = Query("1m", alias="candleInterval"),
) -> dict:
    _require_firebase_bearer_token(request)
    return load_toss_stock_dashboard(
        market=market,
        symbol=symbol,
        symbols=symbols,
        candle_interval=candle_interval,
    )


@app.get("/toss/candles", response_model=TossInvestCandlesResponse)
def toss_stock_candles(
    request: Request,
    market: str = "KR",
    symbol: Optional[str] = None,
    candle_interval: str = Query("1m", alias="candleInterval"),
    count: int = 200,
    before: Optional[str] = None,
) -> dict:
    _require_firebase_bearer_token(request)
    try:
        return load_toss_stock_candles(
            market=market,
            symbol=symbol,
            candle_interval=candle_interval,
            count=count,
            before=before,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except TossInvestApiError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@app.get("/toss/stocks/search", response_model=TossInvestStockSearchResponse)
def toss_stock_search(
    request: Request,
    market: str = "KR",
    query: str = "",
    limit: int = 30,
) -> dict:
    _require_firebase_bearer_token(request)
    market_code = "US" if market.strip().upper() in {"US", "USA", "GLOBAL"} else "KR"
    bounded_limit = max(1, min(limit, 50))
    items = search_krx_stocks(query, limit=bounded_limit) if market_code == "KR" else []
    return {
        "market": market_code,
        "query": query,
        "count": len(items),
        "items": items,
    }


@app.post("/toss/orders", response_model=TossInvestOrderResponse)
def toss_create_order(payload: TossInvestOrderRequest, request: Request) -> dict:
    claims = _require_firebase_bearer_token(request)
    user_email = str(claims.get("email") or "")
    try:
        return create_toss_order(payload.dict(), user_email=user_email)
    except PermissionError as exc:
        raise HTTPException(status_code=403, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except TossInvestApiError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@app.get("/toss/orders/{order_id}", response_model=TossInvestOpenOrder)
def toss_get_order(order_id: str, request: Request) -> dict:
    claims = _require_firebase_bearer_token(request)
    user_email = str(claims.get("email") or "")
    try:
        return get_toss_order(order_id, user_email=user_email)
    except PermissionError as exc:
        raise HTTPException(status_code=403, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except TossInvestApiError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@app.post("/toss/orders/{order_id}/modify", response_model=TossInvestOrderActionResponse)
def toss_modify_order(
    order_id: str,
    payload: TossInvestOrderModifyRequest,
    request: Request,
) -> dict:
    claims = _require_firebase_bearer_token(request)
    user_email = str(claims.get("email") or "")
    try:
        return modify_toss_order(order_id, payload.dict(), user_email=user_email)
    except PermissionError as exc:
        raise HTTPException(status_code=403, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except TossInvestApiError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@app.post("/toss/orders/{order_id}/cancel", response_model=TossInvestOrderActionResponse)
def toss_cancel_order(order_id: str, request: Request) -> dict:
    claims = _require_firebase_bearer_token(request)
    user_email = str(claims.get("email") or "")
    try:
        return cancel_toss_order(order_id, user_email=user_email)
    except PermissionError as exc:
        raise HTTPException(status_code=403, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except TossInvestApiError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@app.get("/subway/overview", response_model=SubwayOverviewResponse)
def subway_overview(station: Optional[str] = None, line: Optional[str] = None) -> dict:
    return load_subway_overview(station=station, line=line)


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
        include_sheet_names=payload.include_sheet_names,
    )
    return {"files": files}


@app.post("/drive/sheets", response_model=DriveSheetNamesResponse)
def drive_sheets(payload: DriveSheetNamesRequest) -> dict:
    verify_firebase_id_token(payload.id_token)
    return {
        "sheet_names": list_google_sheet_names(
            access_token=payload.google_access_token,
            file_id=payload.file_id,
        )
    }


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
