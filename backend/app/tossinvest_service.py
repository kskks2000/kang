from __future__ import annotations

from copy import deepcopy
from datetime import datetime, timedelta, timezone
import re
import time
from typing import Any, Optional
from uuid import uuid4

import requests

from .settings import settings


TOSS_OPEN_API_DOCS_URL = "https://developers.tossinvest.com/docs"
TOSS_OPEN_API_SPEC_URL = "https://openapi.tossinvest.com/openapi-docs/latest/openapi.json"
CACHE_SECONDS = 45
DASHBOARD_SYMBOL_LIMIT = 30

WATCHLIST_SYMBOLS = {
    "KR": [
        "005930",
        "000660",
        "035420",
        "035720",
        "068270",
        "005380",
        "051910",
        "006400",
        "207940",
        "105560",
    ],
    "US": ["NVDA", "AAPL", "MSFT", "TSLA", "GOOGL", "AMZN", "META", "NFLX"],
}

_TOKEN_CACHE: dict[str, Any] = {}
_DASHBOARD_CACHE: dict[str, dict[str, Any]] = {}
_DASHBOARD_EXPIRES_AT: dict[str, datetime] = {}


class TossInvestApiError(RuntimeError):
    pass


def create_toss_order(payload: dict[str, Any], *, user_email: str) -> dict[str, Any]:
    _ensure_trading_allowed(user_email)
    selected_account_seq = _selected_account_seq_for_trading()

    order_payload = _order_create_payload(payload)
    result = _api_post(
        "/api/v1/orders",
        payload=order_payload,
        account_seq=selected_account_seq,
    )
    if not isinstance(result, dict):
        result = {}

    _DASHBOARD_CACHE.clear()
    _DASHBOARD_EXPIRES_AT.clear()

    return {
        "status": "accepted",
        "orderId": str(result.get("orderId") or ""),
        "clientOrderId": result.get("clientOrderId") or order_payload.get("clientOrderId"),
        "symbol": str(order_payload.get("symbol") or ""),
        "side": str(order_payload.get("side") or ""),
        "orderType": str(order_payload.get("orderType") or ""),
        "quantity": order_payload.get("quantity"),
        "price": order_payload.get("price"),
        "orderAmount": order_payload.get("orderAmount"),
        "timeInForce": str(order_payload.get("timeInForce") or "DAY"),
        "message": "토스증권 주문이 접수되었습니다.",
    }


def get_toss_order(order_id: str, *, user_email: str) -> dict[str, Any]:
    _ensure_trading_allowed(user_email)
    selected_account_seq = _selected_account_seq_for_trading()
    result = _api_get(
        f"/api/v1/orders/{_order_id(order_id)}",
        account_seq=selected_account_seq,
    )
    if isinstance(result, dict):
        return _open_order(result)
    return _open_order({})


def modify_toss_order(
    order_id: str,
    payload: dict[str, Any],
    *,
    user_email: str,
) -> dict[str, Any]:
    _ensure_trading_allowed(user_email)
    selected_account_seq = _selected_account_seq_for_trading()
    modify_payload = _order_modify_payload(payload)
    result = _api_post(
        f"/api/v1/orders/{_order_id(order_id)}/modify",
        payload=modify_payload,
        account_seq=selected_account_seq,
    )
    _clear_dashboard_cache()
    return _order_action_response(result, order_id, message="토스증권 주문 정정이 접수되었습니다.")


def cancel_toss_order(order_id: str, *, user_email: str) -> dict[str, Any]:
    _ensure_trading_allowed(user_email)
    selected_account_seq = _selected_account_seq_for_trading()
    result = _api_post(
        f"/api/v1/orders/{_order_id(order_id)}/cancel",
        payload={},
        account_seq=selected_account_seq,
    )
    _clear_dashboard_cache()
    return _order_action_response(result, order_id, message="토스증권 주문 취소가 접수되었습니다.")


def load_toss_stock_dashboard(
    market: str = "KR",
    symbol: Optional[str] = None,
    symbols: Optional[str] = None,
    candle_interval: str = "1m",
) -> dict[str, Any]:
    market_code = _market_code(market)
    primary_symbol = _primary_symbol(market_code, symbol)
    request_symbols = _request_symbols_for_market(market_code, symbols)
    candle_interval = _candle_interval(candle_interval)
    symbols = _dashboard_symbols(
        market_code,
        primary_symbol,
        extra_symbols=request_symbols,
    )
    cache_key = f"{market_code}:{primary_symbol}:{candle_interval}:{','.join(symbols)}"
    now = datetime.now(timezone.utc)

    expires_at = _DASHBOARD_EXPIRES_AT.get(cache_key)
    cached_dashboard = _DASHBOARD_CACHE.get(cache_key)
    if cached_dashboard and expires_at and expires_at > now:
        payload = deepcopy(cached_dashboard)
        payload["cached"] = True
        return payload

    if not settings.tossinvest_client_id or not settings.tossinvest_client_secret:
        return _empty_dashboard(
            market_code,
            now,
            primary_symbol=primary_symbol,
            status="not_configured",
            errors=["토스증권 Open API 키가 설정되지 않았습니다."],
        )

    errors: list[str] = []
    accounts: list[dict[str, Any]] = []
    selected_account: Optional[dict[str, Any]] = None
    selected_account_seq: Optional[int] = None
    watchlist: list[dict[str, Any]] = []
    orderbook: Optional[dict[str, Any]] = None
    candles: list[dict[str, Any]] = []
    holdings: list[dict[str, Any]] = []
    open_orders: list[dict[str, Any]] = []
    buying_power: list[dict[str, str]] = []

    try:
        account_result = _api_get("/api/v1/accounts")
        accounts = account_result if isinstance(account_result, list) else []
        selected_account = _select_account(accounts)
        selected_account_seq = _account_seq(selected_account)
    except Exception as exc:  # noqa: BLE001 - keep dashboard partially useful.
        errors.append(f"계좌 목록: {_safe_error(exc)}")

    try:
        prices_result = _api_get("/api/v1/prices", params={"symbols": ",".join(symbols)})
        stocks_result = _api_get("/api/v1/stocks", params={"symbols": ",".join(symbols)})
        prices_by_symbol = _by_symbol(prices_result)
        stocks_by_symbol = _by_symbol(stocks_result)
        watchlist = [
            _stock_quote(
                symbol,
                prices_by_symbol.get(symbol),
                stocks_by_symbol.get(symbol),
            )
            for symbol in symbols
        ]
    except Exception as exc:  # noqa: BLE001
        errors.append(f"현재가: {_safe_error(exc)}")
        watchlist = [_stock_quote(symbol, None, None) for symbol in symbols]

    try:
        orderbook_result = _api_get("/api/v1/orderbook", params={"symbol": primary_symbol})
        orderbook = _orderbook(primary_symbol, orderbook_result)
    except Exception as exc:  # noqa: BLE001
        if not _is_rate_limit_error(exc):
            errors.append(f"호가: {_safe_error(exc)}")

    try:
        candle_result = _api_get(
            "/api/v1/candles",
            params={
                "symbol": primary_symbol,
                "interval": candle_interval,
                "count": str(_candle_count(candle_interval)),
                "adjusted": "true",
            },
        )
        raw_candles = candle_result.get("candles", []) if isinstance(candle_result, dict) else []
        candles = [_candle(item) for item in raw_candles if isinstance(item, dict)]
        _apply_primary_candle_change(watchlist, primary_symbol, raw_candles)
    except Exception as exc:  # noqa: BLE001
        if not _is_rate_limit_error(exc):
            errors.append(f"차트: {_safe_error(exc)}")

    if selected_account_seq is not None:
        try:
            holding_result = _api_get("/api/v1/holdings", account_seq=selected_account_seq)
            raw_items = holding_result.get("items", []) if isinstance(holding_result, dict) else []
            holdings = [_holding(item) for item in raw_items if isinstance(item, dict)]
        except Exception as exc:  # noqa: BLE001
            errors.append(f"보유 주식: {_safe_error(exc)}")

        try:
            orders_result = _api_get(
                "/api/v1/orders",
                params={"status": "OPEN", "limit": "20"},
                account_seq=selected_account_seq,
            )
            raw_orders = orders_result.get("orders", []) if isinstance(orders_result, dict) else []
            open_orders = [_open_order(item) for item in raw_orders if isinstance(item, dict)]
        except Exception as exc:  # noqa: BLE001
            errors.append(f"미체결 주문: {_safe_error(exc)}")

        for currency in ("KRW", "USD"):
            try:
                buying_power_result = _api_get(
                    "/api/v1/buying-power",
                    params={"currency": currency},
                    account_seq=selected_account_seq,
                )
                if isinstance(buying_power_result, dict):
                    buying_power.append(
                        {
                            "currency": str(buying_power_result.get("currency") or currency),
                            "cashBuyingPower": str(
                                buying_power_result.get("cashBuyingPower") or ""
                            ),
                        }
                    )
            except Exception as exc:  # noqa: BLE001
                errors.append(f"{currency} 매수 가능 금액: {_safe_error(exc)}")
    elif accounts:
        errors.append("선택할 토스증권 계좌를 찾지 못했습니다.")

    status = "ok" if not errors else "partial"
    dashboard = _dashboard_response(
        market_code,
        now,
        status=status,
        primary_symbol=primary_symbol,
        accounts=accounts,
        selected_account=selected_account,
        watchlist=watchlist,
        orderbook=orderbook,
        candles=candles,
        holdings=holdings,
        open_orders=open_orders,
        buying_power=buying_power,
        errors=errors,
    )
    _DASHBOARD_CACHE[cache_key] = deepcopy(dashboard)
    _DASHBOARD_EXPIRES_AT[cache_key] = now + timedelta(seconds=CACHE_SECONDS)
    dashboard["cached"] = False
    return dashboard


def load_toss_stock_candles(
    market: str = "KR",
    symbol: Optional[str] = None,
    candle_interval: str = "1m",
    count: int = 200,
    before: Optional[str] = None,
) -> dict[str, Any]:
    market_code = _market_code(market)
    primary_symbol = _primary_symbol(market_code, symbol)
    candle_interval = _candle_interval(candle_interval)
    bounded_count = max(1, min(_safe_int(count, default=200), 200))
    if not settings.tossinvest_client_id or not settings.tossinvest_client_secret:
        raise ValueError("?좎뒪利앷텒 Open API ?ㅺ? ?ㅼ젙?섏? ?딆븯?듬땲??")

    params = {
        "symbol": primary_symbol,
        "interval": candle_interval,
        "count": str(bounded_count),
        "adjusted": "true",
    }
    before_value = str(before or "").strip()
    if before_value:
        params["before"] = before_value

    candle_result = _api_get("/api/v1/candles", params=params)
    raw_candles = (
        candle_result.get("candles", []) if isinstance(candle_result, dict) else []
    )
    candles = [_candle(item) for item in raw_candles if isinstance(item, dict)]
    next_before = (
        str(candle_result.get("nextBefore") or "")
        if isinstance(candle_result, dict)
        else ""
    )
    return {
        "symbol": primary_symbol,
        "interval": candle_interval,
        "count": len(candles),
        "nextBefore": next_before,
        "candles": candles,
    }


def _market_code(market: str) -> str:
    value = (market or "KR").strip().upper()
    if value in {"US", "USA", "OVERSEAS", "GLOBAL"}:
        return "US"
    return "KR"


def _primary_symbol(market: str, symbol: Optional[str]) -> str:
    symbols = WATCHLIST_SYMBOLS[market]
    value = str(symbol or "").strip().upper()
    if _valid_symbol_for_market(market, value):
        return value
    return symbols[0]


def _valid_symbol_for_market(market: str, symbol: str) -> bool:
    if market == "KR":
        return re.fullmatch(r"\d{6}", symbol) is not None
    return re.fullmatch(r"[A-Z0-9.\-]{1,20}", symbol) is not None


def _candle_interval(value: str) -> str:
    normalized = str(value or "1m").strip().lower()
    if normalized in {"1m", "1d"}:
        return normalized
    return "1m"


def _candle_count(interval: str) -> int:
    return 200 if interval == "1m" else 60


def _request_symbols_for_market(market: str, symbols: Optional[str]) -> list[str]:
    result: list[str] = []
    for raw_symbol in str(symbols or "").split(","):
        symbol = raw_symbol.strip().upper()
        if not _valid_symbol_for_market(market, symbol):
            continue
        if symbol not in result:
            result.append(symbol)
        if len(result) >= DASHBOARD_SYMBOL_LIMIT:
            break
    return result


def _dashboard_symbols(
    market: str,
    primary_symbol: str,
    *,
    extra_symbols: Optional[list[str]] = None,
) -> list[str]:
    result: list[str] = []
    for symbol in [primary_symbol, *(extra_symbols or []), *WATCHLIST_SYMBOLS[market]]:
        if symbol not in result:
            result.append(symbol)
        if len(result) >= DASHBOARD_SYMBOL_LIMIT:
            break
    return result


def _api_base_url() -> str:
    return (settings.tossinvest_api_base_url or "https://openapi.tossinvest.com").rstrip("/")


def _get_access_token() -> str:
    now = datetime.now(timezone.utc)
    cached_token = _TOKEN_CACHE.get("access_token")
    expires_at = _TOKEN_CACHE.get("expires_at")
    if cached_token and isinstance(expires_at, datetime) and expires_at > now:
        return str(cached_token)

    response = requests.post(
        f"{_api_base_url()}/oauth2/token",
        data={
            "grant_type": "client_credentials",
            "client_id": settings.tossinvest_client_id,
            "client_secret": settings.tossinvest_client_secret,
        },
        headers={
            "Accept": "application/json",
            "Content-Type": "application/x-www-form-urlencoded",
            "User-Agent": settings.http_user_agent,
        },
        timeout=15,
    )
    if response.status_code < 200 or response.status_code >= 300:
        raise TossInvestApiError(_response_error(response))

    payload = response.json()
    access_token = str(payload.get("access_token") or "").strip()
    if not access_token:
        raise TossInvestApiError("토스증권 액세스 토큰이 응답에 없습니다.")

    expires_in = _safe_int(payload.get("expires_in"), default=3600)
    _TOKEN_CACHE["access_token"] = access_token
    _TOKEN_CACHE["expires_at"] = now + timedelta(seconds=max(60, expires_in - 60))
    return access_token


def _api_get(
    path: str,
    *,
    params: Optional[dict[str, str]] = None,
    account_seq: Optional[int] = None,
) -> Any:
    headers = {
        "Accept": "application/json",
        "Authorization": f"Bearer {_get_access_token()}",
        "User-Agent": settings.http_user_agent,
    }
    if account_seq is not None:
        headers["X-Tossinvest-Account"] = str(account_seq)

    response = requests.get(
        f"{_api_base_url()}{path}",
        params=params,
        headers=headers,
        timeout=15,
    )
    if response.status_code < 200 or response.status_code >= 300:
        if response.status_code == 401:
            _TOKEN_CACHE.clear()
        raise TossInvestApiError(_response_error(response))

    payload = response.json()
    if isinstance(payload, dict) and "result" in payload:
        return payload["result"]
    return payload


def _api_post(
    path: str,
    *,
    payload: dict[str, Any],
    account_seq: Optional[int] = None,
) -> Any:
    headers = {
        "Accept": "application/json",
        "Authorization": f"Bearer {_get_access_token()}",
        "Content-Type": "application/json",
        "User-Agent": settings.http_user_agent,
    }
    if account_seq is not None:
        headers["X-Tossinvest-Account"] = str(account_seq)

    response = requests.post(
        f"{_api_base_url()}{path}",
        json=payload,
        headers=headers,
        timeout=15,
    )
    if response.status_code < 200 or response.status_code >= 300:
        if response.status_code == 401:
            _TOKEN_CACHE.clear()
        raise TossInvestApiError(_response_error(response))

    payload_result = response.json()
    if isinstance(payload_result, dict) and "result" in payload_result:
        return payload_result["result"]
    return payload_result


def _ensure_trading_allowed(user_email: str) -> None:
    if not settings.tossinvest_trading_enabled:
        raise PermissionError("실제 주문 기능이 서버에서 비활성화되어 있습니다.")

    allowed_emails = settings.tossinvest_trading_allowed_emails
    normalized_email = (user_email or "").strip().lower()
    if not allowed_emails:
        raise PermissionError("실제 주문 허용 이메일이 설정되지 않았습니다.")
    if normalized_email not in allowed_emails:
        raise PermissionError("이 계정은 실제 주문 권한이 없습니다.")


def _selected_account_seq_for_trading() -> int:
    if not settings.tossinvest_client_id or not settings.tossinvest_client_secret:
        raise ValueError("토스증권 Open API 키가 설정되지 않았습니다.")

    account_result = _api_get("/api/v1/accounts")
    accounts = account_result if isinstance(account_result, list) else []
    selected_account = _select_account(accounts)
    selected_account_seq = _account_seq(selected_account)
    if selected_account_seq is None:
        raise ValueError("주문에 사용할 토스증권 계좌를 찾지 못했습니다.")
    return selected_account_seq


def _order_id(order_id: str) -> str:
    value = str(order_id or "").strip()
    if not value or not re.fullmatch(r"[A-Za-z0-9_\-=.]{1,200}", value):
        raise ValueError("주문 ID가 올바르지 않습니다.")
    return value


def _order_create_payload(raw: dict[str, Any]) -> dict[str, Any]:
    symbol = str(raw.get("symbol") or "").strip().upper()
    if not re.fullmatch(r"[A-Za-z0-9.\-]{1,20}", symbol):
        raise ValueError("종목 코드가 올바르지 않습니다.")

    side = str(raw.get("side") or "").strip().upper()
    if side not in {"BUY", "SELL"}:
        raise ValueError("주문 방향은 BUY 또는 SELL만 가능합니다.")

    order_type = str(raw.get("orderType") or "").strip().upper()
    if order_type not in {"LIMIT", "MARKET"}:
        raise ValueError("주문 유형은 LIMIT 또는 MARKET만 가능합니다.")

    time_in_force = str(raw.get("timeInForce") or "DAY").strip().upper()
    if time_in_force not in {"DAY", "CLS"}:
        raise ValueError("주문 유효 조건은 DAY 또는 CLS만 가능합니다.")

    quantity = _clean_decimal(raw.get("quantity"))
    order_amount = _clean_decimal(raw.get("orderAmount"))
    if bool(quantity) == bool(order_amount):
        raise ValueError("주문 수량 또는 주문 금액 중 하나만 입력해야 합니다.")

    payload: dict[str, Any] = {
        "clientOrderId": _client_order_id(),
        "symbol": symbol,
        "side": side,
        "orderType": order_type,
        "timeInForce": time_in_force,
        "confirmHighValueOrder": bool(raw.get("confirmHighValueOrder") or False),
    }

    if quantity:
        if not re.fullmatch(r"\d+", quantity) or int(quantity) <= 0:
            raise ValueError("주문 수량은 1 이상의 정수만 가능합니다.")
        payload["quantity"] = quantity
    else:
        if order_type != "MARKET":
            raise ValueError("금액 주문은 시장가 주문에서만 가능합니다.")
        if side != "BUY":
            raise ValueError("금액 주문은 매수 주문에서만 가능합니다.")
        if not _decimal_token(order_amount) or not _positive_decimal(order_amount):
            raise ValueError("주문 금액은 0보다 커야 합니다.")
        payload["orderAmount"] = order_amount

    price = _clean_decimal(raw.get("price"))
    if order_type == "LIMIT":
        if not price or not _decimal_token(price) or not _positive_decimal(price):
            raise ValueError("지정가 주문에는 0보다 큰 주문 가격이 필요합니다.")
        payload["price"] = price
    elif price:
        raise ValueError("시장가 주문에는 가격을 입력하지 않습니다.")

    return payload


def _order_modify_payload(raw: dict[str, Any]) -> dict[str, Any]:
    order_type = str(raw.get("orderType") or "").strip().upper()
    if order_type not in {"LIMIT", "MARKET"}:
        raise ValueError("주문 유형은 LIMIT 또는 MARKET만 가능합니다.")

    payload: dict[str, Any] = {
        "orderType": order_type,
        "confirmHighValueOrder": bool(raw.get("confirmHighValueOrder") or False),
    }

    quantity = _clean_decimal(raw.get("quantity"))
    if quantity:
        if not re.fullmatch(r"\d+", quantity) or int(quantity) <= 0:
            raise ValueError("정정 수량은 1 이상의 정수만 가능합니다.")
        payload["quantity"] = quantity

    price = _clean_decimal(raw.get("price"))
    if order_type == "LIMIT":
        if not price or not _decimal_token(price) or not _positive_decimal(price):
            raise ValueError("지정가 정정에는 0보다 큰 주문 가격이 필요합니다.")
        payload["price"] = price
    elif price:
        raise ValueError("시장가 정정에는 가격을 입력하지 않습니다.")

    return payload


def _order_action_response(raw: Any, order_id: str, *, message: str) -> dict[str, Any]:
    result = raw if isinstance(raw, dict) else {}
    return {
        "status": "accepted",
        "orderId": str(result.get("orderId") or order_id),
        "clientOrderId": result.get("clientOrderId"),
        "message": message,
    }


def _clear_dashboard_cache() -> None:
    _DASHBOARD_CACHE.clear()
    _DASHBOARD_EXPIRES_AT.clear()


def _clean_decimal(value: Any) -> str:
    return str(value or "").replace(",", "").strip()


def _positive_decimal(value: str) -> bool:
    try:
        return float(value) > 0
    except ValueError:
        return False


def _decimal_token(value: str) -> bool:
    return bool(re.fullmatch(r"\d+(\.\d+)?", value or ""))


def _client_order_id() -> str:
    millis = int(time.time() * 1000)
    suffix = uuid4().hex[:8]
    return f"kang-{millis}-{suffix}"[:36]


def _response_error(response: requests.Response) -> str:
    try:
        payload = response.json()
    except ValueError:
        payload = {}

    message = ""
    if isinstance(payload, dict):
        for key in ("message", "error_description", "error", "code"):
            value = payload.get(key)
            if value:
                message = str(value)
                break
    if not message:
        message = response.text[:160]
    return f"HTTP {response.status_code}: {message[:180]}"


def _safe_error(exc: Exception) -> str:
    message = str(exc)
    if settings.tossinvest_client_id:
        message = message.replace(settings.tossinvest_client_id, "[client_id]")
    if settings.tossinvest_client_secret:
        message = message.replace(settings.tossinvest_client_secret, "[client_secret]")
    return message[:220]


def _is_rate_limit_error(exc: Exception) -> bool:
    message = str(exc).lower()
    return (
        "http 429" in message
        or "rate-limit" in message
        or "too many request" in message
        or "요청 한도" in message
    )


def _by_symbol(raw_items: Any) -> dict[str, dict[str, Any]]:
    if not isinstance(raw_items, list):
        return {}
    result: dict[str, dict[str, Any]] = {}
    for item in raw_items:
        if not isinstance(item, dict):
            continue
        symbol = str(item.get("symbol") or "").upper()
        if symbol:
            result[symbol] = item
    return result


def _apply_primary_candle_change(
    watchlist: list[dict[str, Any]],
    primary_symbol: str,
    raw_candles: list[dict[str, Any]],
) -> None:
    if not raw_candles:
        return

    for quote in watchlist:
        if quote.get("symbol") != primary_symbol:
            continue
        candle_change = _price_change(_safe_float(quote.get("lastPrice")), raw_candles)
        quote["previousClose"] = _decimal_string(candle_change.get("previousClose"))
        quote["change"] = _decimal_string(candle_change.get("change"))
        quote["changePercent"] = _decimal_string(candle_change.get("changePercent"))
        return


def _stock_quote(
    symbol: str,
    price: Optional[dict[str, Any]],
    stock: Optional[dict[str, Any]],
    recent_candles: Optional[list[dict[str, Any]]] = None,
) -> dict[str, Any]:
    price = price or {}
    stock = stock or {}
    name = str(stock.get("name") or "")
    english_name = str(stock.get("englishName") or "")
    last_price = _safe_float(price.get("lastPrice"))
    candle_change = _price_change(last_price, recent_candles or [])
    shares_outstanding = _safe_float(stock.get("sharesOutstanding"))
    market_cap = (
        last_price * shares_outstanding
        if last_price is not None and shares_outstanding is not None
        else None
    )
    return {
        "symbol": symbol,
        "name": name,
        "englishName": english_name,
        "displayName": name or english_name or symbol,
        "market": str(stock.get("market") or ""),
        "currency": str(price.get("currency") or stock.get("currency") or ""),
        "lastPrice": str(price.get("lastPrice") or ""),
        "previousClose": _decimal_string(candle_change.get("previousClose")),
        "change": _decimal_string(candle_change.get("change")),
        "changePercent": _decimal_string(candle_change.get("changePercent")),
        "sharesOutstanding": str(stock.get("sharesOutstanding") or ""),
        "marketCap": _decimal_string(market_cap),
        "timestamp": price.get("timestamp"),
    }


def _price_change(
    last_price: Optional[float],
    recent_candles: list[dict[str, Any]],
) -> dict[str, Optional[float]]:
    if not recent_candles:
        return {"previousClose": None, "change": None, "changePercent": None}

    sorted_candles = sorted(
        recent_candles,
        key=lambda item: str(item.get("timestamp") or ""),
    )
    latest_close = _safe_float(sorted_candles[-1].get("closePrice"))
    current_price = last_price if last_price is not None else latest_close
    previous_close = None
    if len(sorted_candles) >= 2:
        previous_close = _safe_float(sorted_candles[-2].get("closePrice"))

    if current_price is None or previous_close in (None, 0):
        return {
            "previousClose": previous_close,
            "change": None,
            "changePercent": None,
        }

    change = current_price - previous_close
    return {
        "previousClose": previous_close,
        "change": change,
        "changePercent": change / previous_close * 100,
    }


def _orderbook(symbol: str, raw: Any) -> dict[str, Any]:
    raw = raw if isinstance(raw, dict) else {}
    return {
        "symbol": symbol,
        "timestamp": raw.get("timestamp"),
        "currency": str(raw.get("currency") or ""),
        "asks": [_orderbook_entry(item) for item in raw.get("asks", []) if isinstance(item, dict)],
        "bids": [_orderbook_entry(item) for item in raw.get("bids", []) if isinstance(item, dict)],
    }


def _orderbook_entry(raw: dict[str, Any]) -> dict[str, str]:
    return {
        "price": str(raw.get("price") or ""),
        "volume": str(raw.get("volume") or ""),
    }


def _candle(raw: dict[str, Any]) -> dict[str, str]:
    return {
        "timestamp": str(raw.get("timestamp") or ""),
        "openPrice": str(raw.get("openPrice") or ""),
        "highPrice": str(raw.get("highPrice") or ""),
        "lowPrice": str(raw.get("lowPrice") or ""),
        "closePrice": str(raw.get("closePrice") or ""),
        "volume": str(raw.get("volume") or ""),
        "currency": str(raw.get("currency") or ""),
    }


def _holding(raw: dict[str, Any]) -> dict[str, Any]:
    market_value = raw.get("marketValue") if isinstance(raw.get("marketValue"), dict) else {}
    profit_loss = raw.get("profitLoss") if isinstance(raw.get("profitLoss"), dict) else {}
    daily_profit_loss = (
        raw.get("dailyProfitLoss") if isinstance(raw.get("dailyProfitLoss"), dict) else {}
    )
    return {
        "symbol": str(raw.get("symbol") or ""),
        "name": str(raw.get("name") or ""),
        "marketCountry": str(raw.get("marketCountry") or ""),
        "currency": str(raw.get("currency") or ""),
        "quantity": str(raw.get("quantity") or ""),
        "lastPrice": str(raw.get("lastPrice") or ""),
        "averagePurchasePrice": str(raw.get("averagePurchasePrice") or ""),
        "marketValue": str(market_value.get("amount") or ""),
        "profitLoss": str(profit_loss.get("amount") or ""),
        "profitLossRate": str(profit_loss.get("rate") or ""),
        "dailyProfitLoss": str(daily_profit_loss.get("amount") or ""),
        "dailyProfitLossRate": str(daily_profit_loss.get("rate") or ""),
    }


def _open_order(raw: dict[str, Any]) -> dict[str, str]:
    return {
        "orderId": str(raw.get("orderId") or ""),
        "symbol": str(raw.get("symbol") or ""),
        "side": str(raw.get("side") or ""),
        "status": str(raw.get("status") or ""),
        "orderType": str(raw.get("orderType") or ""),
        "quantity": str(raw.get("quantity") or ""),
        "price": str(raw.get("price") or ""),
        "currency": str(raw.get("currency") or ""),
        "orderedAt": str(raw.get("orderedAt") or ""),
    }


def _select_account(accounts: list[dict[str, Any]]) -> Optional[dict[str, Any]]:
    configured = settings.tossinvest_account.strip()
    configured_digits = re.sub(r"\D+", "", configured)

    if configured:
        for account in accounts:
            if str(account.get("accountSeq") or "") == configured:
                return account
        for account in accounts:
            account_digits = re.sub(r"\D+", "", str(account.get("accountNo") or ""))
            if configured_digits and account_digits == configured_digits:
                return account

    if len(accounts) == 1:
        return accounts[0]
    return None


def _account_seq(account: Optional[dict[str, Any]]) -> Optional[int]:
    if not isinstance(account, dict):
        return None
    return _safe_int(account.get("accountSeq"), default=-1) if account.get("accountSeq") else None


def _account_summary(
    account: dict[str, Any],
    *,
    selected_account: Optional[dict[str, Any]],
) -> dict[str, Any]:
    account_seq = _account_seq(account)
    selected_seq = _account_seq(selected_account)
    return {
        "accountSeq": account_seq,
        "accountNoMasked": _mask_account_no(str(account.get("accountNo") or "")),
        "accountType": str(account.get("accountType") or ""),
        "selected": account_seq is not None and account_seq == selected_seq,
    }


def _mask_account_no(account_no: str) -> str:
    digits = re.sub(r"\D+", "", account_no)
    if not digits:
        return ""
    return f"{'*' * max(0, len(digits) - 4)}{digits[-4:]}"


def _dashboard_response(
    market: str,
    now: datetime,
    *,
    status: str,
    primary_symbol: str,
    accounts: list[dict[str, Any]],
    selected_account: Optional[dict[str, Any]],
    watchlist: list[dict[str, Any]],
    orderbook: Optional[dict[str, Any]],
    candles: list[dict[str, Any]],
    holdings: list[dict[str, Any]],
    open_orders: list[dict[str, Any]],
    buying_power: list[dict[str, str]],
    errors: list[str],
) -> dict[str, Any]:
    buying_power_by_currency = {item["currency"]: item["cashBuyingPower"] for item in buying_power}
    return {
        "status": status,
        "fetchedAt": now.isoformat(),
        "cached": False,
        "cacheSeconds": CACHE_SECONDS,
        "source": {
            "title": "토스증권 Open API",
            "provider": "Toss Securities",
            "sourceUrl": TOSS_OPEN_API_DOCS_URL,
            "specUrl": TOSS_OPEN_API_SPEC_URL,
            "description": "토스증권 Open API의 시세, 호가, 캔들, 계좌 조회 API를 읽기 전용으로 사용합니다.",
        },
        "summary": {
            "market": market,
            "primarySymbol": primary_symbol,
            "symbolCount": len(watchlist),
            "accountCount": len(accounts),
            "accountConfigured": bool(settings.tossinvest_account.strip()),
            "selectedAccountMasked": _mask_account_no(
                str(selected_account.get("accountNo") or "")
            )
            if selected_account
            else None,
            "holdingCount": len(holdings),
            "openOrderCount": len(open_orders),
            "buyingPowerKrw": buying_power_by_currency.get("KRW"),
            "buyingPowerUsd": buying_power_by_currency.get("USD"),
        },
        "accounts": [
            _account_summary(account, selected_account=selected_account) for account in accounts
        ],
        "watchlist": watchlist,
        "orderbook": orderbook,
        "candles": candles,
        "holdings": holdings,
        "openOrders": open_orders,
        "buyingPower": buying_power,
        "errors": errors,
    }


def _empty_dashboard(
    market: str,
    now: datetime,
    *,
    primary_symbol: str,
    status: str,
    errors: list[str],
) -> dict[str, Any]:
    symbols = _dashboard_symbols(market, primary_symbol)
    return _dashboard_response(
        market,
        now,
        status=status,
        primary_symbol=primary_symbol,
        accounts=[],
        selected_account=None,
        watchlist=[_stock_quote(symbol, None, None) for symbol in symbols],
        orderbook=None,
        candles=[],
        holdings=[],
        open_orders=[],
        buying_power=[],
        errors=errors,
    )


def _safe_int(value: Any, *, default: int = 0) -> int:
    try:
        return int(str(value))
    except (TypeError, ValueError):
        return default


def _safe_float(value: Any) -> Optional[float]:
    try:
        return float(str(value).replace(",", "").strip())
    except (TypeError, ValueError):
        return None


def _decimal_string(value: Optional[float]) -> str:
    if value is None:
        return ""
    return f"{value:.8f}".rstrip("0").rstrip(".")
