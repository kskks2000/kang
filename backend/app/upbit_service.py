from __future__ import annotations

from copy import deepcopy
from datetime import datetime, timedelta, timezone
from decimal import Decimal, InvalidOperation
import hashlib
import re
from typing import Any, Optional
from urllib.parse import unquote, urlencode
from uuid import uuid4
import warnings

import jwt
from jwt.warnings import InsecureKeyLengthWarning
import requests

from .settings import settings


UPBIT_DOCS_URL = "https://docs.upbit.com/kr/reference/api-overview"
UPBIT_AUTH_DOCS_URL = "https://docs.upbit.com/kr/reference/auth"
UPBIT_SOURCE_URL = "https://docs.upbit.com/kr/reference/list-tickers"
UPBIT_CACHE_SECONDS = 30
UPBIT_MARKET_CODE = "UPBIT"
UPBIT_DEFAULT_MARKETS = [
    "KRW-BTC",
    "KRW-USDT",
    "KRW-ETH",
    "KRW-XRP",
    "KRW-SOL",
    "KRW-DOGE",
    "KRW-ADA",
    "KRW-AVAX",
    "KRW-LINK",
]
UPBIT_DASHBOARD_SYMBOL_LIMIT = 30

_DASHBOARD_CACHE: dict[str, dict[str, Any]] = {}
_DASHBOARD_EXPIRES_AT: dict[str, datetime] = {}
_MARKETS_CACHE: list[dict[str, Any]] = []
_MARKETS_EXPIRES_AT: Optional[datetime] = None


class UpbitApiError(RuntimeError):
    pass


def load_upbit_crypto_dashboard(
    market: str = "KRW",
    symbol: Optional[str] = None,
    symbols: Optional[str] = None,
    candle_interval: str = "1m",
    user_email: Optional[str] = None,
) -> dict[str, Any]:
    quote_currency = _quote_currency(market)
    primary_symbol = _primary_symbol(quote_currency, symbol)
    request_symbols = _request_symbols(quote_currency, symbols)
    candle_interval = _candle_interval(candle_interval)
    dashboard_symbols = _dashboard_symbols(primary_symbol, request_symbols)
    cache_key = f"{quote_currency}:{primary_symbol}:{candle_interval}:{','.join(dashboard_symbols)}"
    now = datetime.now(timezone.utc)
    private_dashboard = _has_private_keys()
    private_data_enabled = private_dashboard and _trading_allowed_for_user(user_email)

    expires_at = _DASHBOARD_EXPIRES_AT.get(cache_key)
    cached_dashboard = _DASHBOARD_CACHE.get(cache_key)
    if not private_dashboard and cached_dashboard and expires_at and expires_at > now:
        payload = deepcopy(cached_dashboard)
        payload["cached"] = True
        return payload

    errors: list[str] = []
    market_names = _market_names()
    watchlist: list[dict[str, Any]] = []
    orderbook: Optional[dict[str, Any]] = None
    candles: list[dict[str, str]] = []
    accounts: list[dict[str, Any]] = []
    holdings: list[dict[str, Any]] = []
    open_orders: list[dict[str, str]] = []
    executions: list[dict[str, Any]] = []
    buying_power: list[dict[str, str]] = []

    try:
        ticker_result = _public_get(
            "/v1/ticker",
            params={"markets": ",".join(dashboard_symbols)},
        )
        tickers = ticker_result if isinstance(ticker_result, list) else []
        tickers_by_market = {
            str(item.get("market") or "").upper(): item
            for item in tickers
            if isinstance(item, dict)
        }
        watchlist = [
            _quote(symbol, tickers_by_market.get(symbol), market_names.get(symbol))
            for symbol in dashboard_symbols
        ]
    except Exception as exc:  # noqa: BLE001 - keep the dashboard shell usable.
        errors.append(f"현재가: {_safe_error(exc)}")
        watchlist = [_quote(symbol, None, market_names.get(symbol)) for symbol in dashboard_symbols]

    try:
        orderbook_result = _public_get("/v1/orderbook", params={"markets": primary_symbol})
        orderbooks = orderbook_result if isinstance(orderbook_result, list) else []
        orderbook = _orderbook(primary_symbol, orderbooks[0] if orderbooks else {})
    except Exception as exc:  # noqa: BLE001
        errors.append(f"호가: {_safe_error(exc)}")

    try:
        candles = _load_candles(primary_symbol, candle_interval, count=_candle_count(candle_interval))
    except Exception as exc:  # noqa: BLE001
        errors.append(f"차트: {_safe_error(exc)}")

    if private_data_enabled:
        try:
            account_result = _private_get("/v1/accounts")
            raw_accounts = account_result if isinstance(account_result, list) else []
            accounts = [_account_summary(item) for item in raw_accounts if isinstance(item, dict)]
            buying_power = _buying_power(raw_accounts, quote_currency)
            holdings = _holdings(raw_accounts, market_names)
        except Exception as exc:  # noqa: BLE001
            errors.append(f"잔고: {_safe_error(exc)}")

        try:
            open_result = _private_get(
                "/v1/orders/open",
                params={"market": primary_symbol, "limit": "20", "order_by": "desc"},
            )
            raw_open_orders = open_result if isinstance(open_result, list) else []
            open_orders = [_order(item) for item in raw_open_orders if isinstance(item, dict)]
        except Exception as exc:  # noqa: BLE001
            errors.append(f"미체결 주문: {_safe_error(exc)}")

        try:
            closed_result = _private_get(
                "/v1/orders/closed",
                params={"market": primary_symbol, "limit": "20", "order_by": "desc"},
            )
            raw_executions = closed_result if isinstance(closed_result, list) else []
            executions = [
                _execution(item) for item in raw_executions if isinstance(item, dict)
            ]
        except Exception as exc:  # noqa: BLE001
            errors.append(f"체결 주문: {_safe_error(exc)}")

    status = "ok" if not errors else "partial"
    dashboard = _dashboard_response(
        now,
        status=status,
        primary_symbol=primary_symbol,
        user_email=user_email,
        accounts=accounts,
        watchlist=watchlist,
        orderbook=orderbook,
        candles=candles,
        holdings=holdings,
        open_orders=open_orders,
        executions=executions,
        buying_power=buying_power,
        errors=errors,
    )
    if private_dashboard:
        _clear_dashboard_cache()
    else:
        _DASHBOARD_CACHE[cache_key] = deepcopy(dashboard)
        _DASHBOARD_EXPIRES_AT[cache_key] = now + timedelta(seconds=UPBIT_CACHE_SECONDS)
    dashboard["cached"] = False
    return dashboard


def load_upbit_crypto_candles(
    market: str = "KRW",
    symbol: Optional[str] = None,
    candle_interval: str = "1m",
    count: int = 200,
    before: Optional[str] = None,
) -> dict[str, Any]:
    quote_currency = _quote_currency(market)
    primary_symbol = _primary_symbol(quote_currency, symbol)
    candle_interval = _candle_interval(candle_interval)
    bounded_count = max(1, min(_safe_int(count, default=200), 200))
    candles = _load_candles(
        primary_symbol,
        candle_interval,
        count=bounded_count,
        before=before,
    )
    next_before = candles[0]["timestamp"] if candles else ""
    return {
        "symbol": primary_symbol,
        "interval": candle_interval,
        "count": len(candles),
        "nextBefore": next_before,
        "candles": candles,
    }


def search_upbit_markets(market: str = "KRW", query: str = "", limit: int = 30) -> dict[str, Any]:
    quote_currency = _quote_currency(market)
    normalized_query = _normalize_search(query)
    bounded_limit = max(1, min(_safe_int(limit, default=30), 50))
    items: list[dict[str, str]] = []
    for item in _markets():
        symbol = str(item.get("market") or "").upper()
        if not symbol.startswith(f"{quote_currency}-"):
            continue
        korean_name = str(item.get("korean_name") or "")
        english_name = str(item.get("english_name") or "")
        search_text = _normalize_search(f"{symbol} {symbol.split('-', 1)[-1]} {korean_name} {english_name}")
        if normalized_query and normalized_query not in search_text:
            continue
        items.append(
            {
                "symbol": symbol,
                "name": korean_name or english_name or symbol,
                "market": UPBIT_MARKET_CODE,
            }
        )
        if len(items) >= bounded_limit:
            break
    return {
        "market": UPBIT_MARKET_CODE,
        "query": query,
        "count": len(items),
        "items": items,
    }


def create_upbit_order(payload: dict[str, Any], *, user_email: str) -> dict[str, Any]:
    _ensure_trading_allowed(user_email)
    order_payload = _order_create_payload(payload)
    _ensure_order_available(order_payload)
    _private_post("/v1/orders/test", payload=order_payload)
    result = _private_post("/v1/orders", payload=order_payload)
    result = result if isinstance(result, dict) else {}
    _clear_dashboard_cache()
    return _order_submit_response(
        result,
        order_payload,
        status="accepted",
        message="업비트 주문이 접수되었습니다.",
    )


def test_upbit_order(payload: dict[str, Any], *, user_email: str) -> dict[str, Any]:
    _ensure_trading_allowed(user_email)
    order_payload = _order_create_payload(payload)
    _ensure_order_available(order_payload)
    result = _private_post("/v1/orders/test", payload=order_payload)
    result = result if isinstance(result, dict) else {}
    return _order_submit_response(
        result,
        order_payload,
        status="validated",
        message="업비트 주문 테스트를 통과했습니다. 최종 주문 전송이 가능합니다.",
    )


def get_upbit_order(order_id: str, *, user_email: str) -> dict[str, str]:
    _ensure_trading_allowed(user_email)
    result = _private_get("/v1/order", params={"uuid": _order_id(order_id)})
    return _order(result if isinstance(result, dict) else {})


def cancel_upbit_order(order_id: str, *, user_email: str) -> dict[str, Any]:
    _ensure_trading_allowed(user_email)
    result = _private_delete("/v1/order", params={"uuid": _order_id(order_id)})
    result = result if isinstance(result, dict) else {}
    _clear_dashboard_cache()
    return {
        "status": "accepted",
        "orderId": str(result.get("uuid") or order_id),
        "clientOrderId": result.get("identifier"),
        "message": "업비트 주문 취소가 접수되었습니다.",
    }


def _order_submit_response(
    result: dict[str, Any],
    order_payload: dict[str, Any],
    *,
    status: str,
    message: str,
) -> dict[str, Any]:
    return {
        "status": status,
        "orderId": str(result.get("uuid") or ""),
        "clientOrderId": result.get("identifier") or order_payload.get("identifier"),
        "symbol": str(result.get("market") or order_payload.get("market") or ""),
        "side": _ui_side(str(result.get("side") or order_payload.get("side") or "")),
        "orderType": "LIMIT",
        "quantity": str(result.get("volume") or order_payload.get("volume") or ""),
        "price": str(result.get("price") or order_payload.get("price") or ""),
        "orderAmount": None,
        "timeInForce": "DAY",
        "message": message,
    }


def _api_base_url() -> str:
    return (settings.upbit_api_base_url or "https://api.upbit.com").rstrip("/")


def _quote_currency(value: str) -> str:
    normalized = str(value or "KRW").strip().upper()
    if normalized in {"UPBIT", "CRYPTO", "COIN", "KR"}:
        return "KRW"
    if normalized in {"KRW", "BTC", "USDT"}:
        return normalized
    return "KRW"


def _primary_symbol(quote_currency: str, symbol: Optional[str]) -> str:
    normalized = _normalize_market_symbol(symbol or "", quote_currency=quote_currency)
    return normalized or f"{quote_currency}-BTC"


def _request_symbols(quote_currency: str, symbols: Optional[str]) -> list[str]:
    result: list[str] = []
    for raw_symbol in str(symbols or "").split(","):
        symbol = _normalize_market_symbol(raw_symbol, quote_currency=quote_currency)
        if symbol and symbol not in result:
            result.append(symbol)
        if len(result) >= UPBIT_DASHBOARD_SYMBOL_LIMIT:
            break
    return result


def _dashboard_symbols(primary_symbol: str, extra_symbols: list[str]) -> list[str]:
    quote_currency = primary_symbol.split("-", 1)[0] if "-" in primary_symbol else "KRW"
    defaults = [
        symbol for symbol in UPBIT_DEFAULT_MARKETS if symbol.startswith(f"{quote_currency}-")
    ]
    result: list[str] = []
    for symbol in [primary_symbol, *extra_symbols, *defaults]:
        if symbol not in result:
            result.append(symbol)
        if len(result) >= UPBIT_DASHBOARD_SYMBOL_LIMIT:
            break
    return result


def _normalize_market_symbol(value: str, *, quote_currency: str) -> str:
    symbol = str(value or "").strip().upper()
    if not symbol:
        return ""
    if re.fullmatch(r"(KRW|BTC|USDT)-[A-Z0-9]{2,20}", symbol):
        return symbol
    if re.fullmatch(r"[A-Z0-9]{2,20}", symbol):
        return f"{quote_currency}-{symbol}"
    return ""


def _candle_interval(value: str) -> str:
    normalized = str(value or "1m").strip().lower()
    if normalized in {"1m", "1d"}:
        return normalized
    return "1m"


def _candle_count(interval: str) -> int:
    return 200 if interval == "1m" else 120


def _load_candles(
    symbol: str,
    interval: str,
    *,
    count: int,
    before: Optional[str] = None,
) -> list[dict[str, str]]:
    path = "/v1/candles/days" if interval == "1d" else "/v1/candles/minutes/1"
    params = {"market": symbol, "count": str(count)}
    before_value = str(before or "").strip()
    if before_value:
        params["to"] = before_value
    result = _public_get(path, params=params)
    raw_candles = result if isinstance(result, list) else []
    candles = [_candle(item) for item in raw_candles if isinstance(item, dict)]
    return sorted(candles, key=lambda item: item["timestamp"])


def _public_get(path: str, *, params: Optional[dict[str, str]] = None) -> Any:
    response = requests.get(
        f"{_api_base_url()}{path}",
        params=params,
        headers={"Accept": "application/json", "User-Agent": settings.http_user_agent},
        timeout=15,
    )
    if response.status_code < 200 or response.status_code >= 300:
        raise UpbitApiError(_response_error(response))
    return response.json()


def _private_get(path: str, *, params: Optional[dict[str, str]] = None) -> Any:
    return _private_request("GET", path, params=params)


def _private_post(path: str, *, payload: dict[str, Any]) -> Any:
    return _private_request("POST", path, payload=payload)


def _private_delete(path: str, *, params: Optional[dict[str, str]] = None) -> Any:
    return _private_request("DELETE", path, params=params)


def _private_request(
    method: str,
    path: str,
    *,
    params: Optional[dict[str, Any]] = None,
    payload: Optional[dict[str, Any]] = None,
) -> Any:
    if not _has_private_keys():
        raise UpbitApiError("업비트 API 키가 설정되지 않았습니다.")

    token_source = payload if payload is not None else params
    headers = {
        "Accept": "application/json",
        "Authorization": f"Bearer {_jwt_token(token_source)}",
        "User-Agent": settings.http_user_agent,
    }
    if payload is not None:
        headers["Content-Type"] = "application/json"

    response = requests.request(
        method,
        f"{_api_base_url()}{path}",
        params=params,
        json=payload,
        headers=headers,
        timeout=15,
    )
    if response.status_code < 200 or response.status_code >= 300:
        raise UpbitApiError(_response_error(response))
    if not response.text.strip():
        return {}
    return response.json()


def _jwt_token(params: Optional[dict[str, Any]] = None) -> str:
    payload: dict[str, Any] = {
        "access_key": settings.upbit_access_key,
        "nonce": str(uuid4()),
    }
    cleaned = {
        key: value
        for key, value in (params or {}).items()
        if value is not None and str(value).strip() != ""
    }
    if cleaned:
        query_string = _query_string(cleaned)
        query_hash = hashlib.sha512(query_string.encode("utf-8")).hexdigest()
        payload["query_hash"] = query_hash
        payload["query_hash_alg"] = "SHA512"
    with warnings.catch_warnings():
        warnings.filterwarnings("ignore", category=InsecureKeyLengthWarning)
        return jwt.encode(payload, settings.upbit_secret_key, algorithm="HS512")


def _query_string(params: dict[str, Any]) -> str:
    return unquote(urlencode(params, doseq=True))


def _markets() -> list[dict[str, Any]]:
    global _MARKETS_CACHE, _MARKETS_EXPIRES_AT  # noqa: PLW0603
    now = datetime.now(timezone.utc)
    if _MARKETS_CACHE and _MARKETS_EXPIRES_AT and _MARKETS_EXPIRES_AT > now:
        return _MARKETS_CACHE
    result = _public_get("/v1/market/all", params={"is_details": "false"})
    _MARKETS_CACHE = result if isinstance(result, list) else []
    _MARKETS_EXPIRES_AT = now + timedelta(hours=6)
    return _MARKETS_CACHE


def _market_names() -> dict[str, dict[str, str]]:
    try:
        return {
            str(item.get("market") or "").upper(): {
                "koreanName": str(item.get("korean_name") or ""),
                "englishName": str(item.get("english_name") or ""),
            }
            for item in _markets()
            if isinstance(item, dict)
        }
    except Exception:
        return {}


def _quote(
    symbol: str,
    ticker: Optional[dict[str, Any]],
    names: Optional[dict[str, str]],
) -> dict[str, Any]:
    ticker = ticker or {}
    names = names or {}
    korean_name = names.get("koreanName") or symbol
    english_name = names.get("englishName") or ""
    last_price = _safe_float(ticker.get("trade_price"))
    previous_close = _safe_float(ticker.get("prev_closing_price"))
    change = _safe_float(ticker.get("signed_change_price"))
    change_rate = _safe_float(ticker.get("signed_change_rate"))
    return {
        "symbol": symbol,
        "name": korean_name,
        "englishName": english_name,
        "displayName": korean_name or english_name or symbol,
        "market": UPBIT_MARKET_CODE,
        "currency": symbol.split("-", 1)[0] if "-" in symbol else "KRW",
        "lastPrice": _decimal_string(last_price),
        "previousClose": _decimal_string(previous_close),
        "change": _decimal_string(change),
        "changePercent": _decimal_string(change_rate * 100 if change_rate is not None else None),
        "sharesOutstanding": "",
        "marketCap": "",
        "timestamp": _ticker_timestamp(ticker),
    }


def _ticker_timestamp(ticker: dict[str, Any]) -> Optional[str]:
    timestamp = _safe_int(ticker.get("timestamp"), default=0)
    if timestamp > 0:
        return datetime.fromtimestamp(timestamp / 1000, tz=timezone.utc).isoformat()
    return None


def _orderbook(symbol: str, raw: Any) -> dict[str, Any]:
    raw = raw if isinstance(raw, dict) else {}
    units = raw.get("orderbook_units", [])
    return {
        "symbol": symbol,
        "timestamp": _ticker_timestamp(raw),
        "currency": symbol.split("-", 1)[0] if "-" in symbol else "KRW",
        "asks": [
            {
                "price": str(item.get("ask_price") or ""),
                "volume": str(item.get("ask_size") or ""),
            }
            for item in units
            if isinstance(item, dict)
        ],
        "bids": [
            {
                "price": str(item.get("bid_price") or ""),
                "volume": str(item.get("bid_size") or ""),
            }
            for item in units
            if isinstance(item, dict)
        ],
    }


def _candle(raw: dict[str, Any]) -> dict[str, str]:
    timestamp = str(raw.get("candle_date_time_utc") or "")
    if timestamp and not timestamp.endswith("Z"):
        timestamp = f"{timestamp}Z"
    return {
        "timestamp": timestamp,
        "openPrice": str(raw.get("opening_price") or ""),
        "highPrice": str(raw.get("high_price") or ""),
        "lowPrice": str(raw.get("low_price") or ""),
        "closePrice": str(raw.get("trade_price") or ""),
        "volume": str(raw.get("candle_acc_trade_volume") or ""),
        "currency": str(raw.get("market") or "KRW").split("-", 1)[0],
    }


def _account_summary(raw: dict[str, Any]) -> dict[str, Any]:
    currency = str(raw.get("currency") or "")
    return {
        "accountSeq": None,
        "accountNoMasked": f"{currency} 지갑" if currency else "업비트 지갑",
        "accountType": "UPBIT",
        "selected": currency == "KRW",
    }


def _buying_power(accounts: list[Any], quote_currency: str) -> list[dict[str, str]]:
    for account in accounts:
        if not isinstance(account, dict):
            continue
        if str(account.get("currency") or "").upper() == quote_currency:
            return [
                {
                    "currency": quote_currency,
                    "cashBuyingPower": str(account.get("balance") or "0"),
                }
            ]
    return [{"currency": quote_currency, "cashBuyingPower": "0"}]


def _holdings(
    accounts: list[Any],
    market_names: dict[str, dict[str, str]],
) -> list[dict[str, Any]]:
    raw_holdings = [
        account
        for account in accounts
        if isinstance(account, dict)
        and str(account.get("currency") or "").upper() != "KRW"
        and (_safe_float(account.get("balance")) or 0) + (_safe_float(account.get("locked")) or 0) > 0
    ]
    if not raw_holdings:
        return []

    symbols = [
        f"{str(account.get('unit_currency') or 'KRW').upper()}-{str(account.get('currency') or '').upper()}"
        for account in raw_holdings
    ]
    tickers_by_market: dict[str, dict[str, Any]] = {}
    try:
        ticker_result = _public_get("/v1/ticker", params={"markets": ",".join(symbols)})
        tickers = ticker_result if isinstance(ticker_result, list) else []
        tickers_by_market = {
            str(item.get("market") or "").upper(): item
            for item in tickers
            if isinstance(item, dict)
        }
    except Exception:
        tickers_by_market = {}

    result: list[dict[str, Any]] = []
    for account in raw_holdings:
        asset = str(account.get("currency") or "").upper()
        quote_currency = str(account.get("unit_currency") or "KRW").upper()
        symbol = f"{quote_currency}-{asset}"
        ticker = tickers_by_market.get(symbol, {})
        names = market_names.get(symbol, {})
        available_quantity = _safe_float(account.get("balance")) or 0
        locked_quantity = _safe_float(account.get("locked")) or 0
        quantity = available_quantity + locked_quantity
        last_price = (
            _safe_float(ticker.get("trade_price"))
            or _safe_float(account.get("avg_buy_price"))
            or 0
        )
        avg_price = _safe_float(account.get("avg_buy_price")) or 0
        market_value = quantity * last_price
        cost = quantity * avg_price
        profit_loss = market_value - cost if cost > 0 else 0
        profit_loss_rate = profit_loss / cost * 100 if cost > 0 else 0
        result.append(
            {
                "symbol": symbol,
                "name": names.get("koreanName") or names.get("englishName") or asset,
                "marketCountry": UPBIT_MARKET_CODE,
                "currency": quote_currency,
                "quantity": _decimal_string(quantity),
                "availableQuantity": _decimal_string(available_quantity),
                "lockedQuantity": _decimal_string(locked_quantity),
                "lastPrice": _decimal_string(last_price),
                "averagePurchasePrice": _decimal_string(avg_price),
                "marketValue": _decimal_string(market_value),
                "profitLoss": _decimal_string(profit_loss),
                "profitLossRate": _decimal_string(profit_loss_rate),
                "dailyProfitLoss": "",
                "dailyProfitLossRate": "",
            }
        )
    return result


def _order(raw: dict[str, Any]) -> dict[str, str]:
    market = str(raw.get("market") or "")
    return {
        "orderId": str(raw.get("uuid") or ""),
        "symbol": market,
        "side": _ui_side(str(raw.get("side") or "")),
        "status": str(raw.get("state") or ""),
        "orderType": str(raw.get("ord_type") or "").upper(),
        "quantity": str(raw.get("remaining_volume") or raw.get("volume") or ""),
        "price": str(raw.get("price") or ""),
        "currency": market.split("-", 1)[0] if "-" in market else "KRW",
        "orderedAt": str(raw.get("created_at") or ""),
    }


def _execution(raw: dict[str, Any]) -> dict[str, Any]:
    market = str(raw.get("market") or "")
    volume = _safe_float(raw.get("volume")) or 0
    remaining = _safe_float(raw.get("remaining_volume")) or 0
    executed_volume = _safe_float(raw.get("executed_volume"))
    if executed_volume is None:
        executed_volume = max(0.0, volume - remaining)
    paid_fee = _safe_float(raw.get("paid_fee")) or 0
    price = _safe_float(raw.get("price")) or 0
    filled_amount = _safe_float(raw.get("executed_funds"))
    if filled_amount is None:
        filled_amount = executed_volume * price if price else 0
    average_price = filled_amount / executed_volume if executed_volume > 0 else price
    return {
        "orderId": str(raw.get("uuid") or ""),
        "symbol": market,
        "side": _ui_side(str(raw.get("side") or "")),
        "status": str(raw.get("state") or ""),
        "orderType": str(raw.get("ord_type") or "").upper(),
        "quantity": str(raw.get("volume") or ""),
        "price": str(raw.get("price") or ""),
        "filledQuantity": _decimal_string(executed_volume),
        "averageFilledPrice": _decimal_string(average_price),
        "filledAmount": _decimal_string(filled_amount + paid_fee),
        "currency": market.split("-", 1)[0] if "-" in market else "KRW",
        "orderedAt": str(raw.get("created_at") or ""),
        "filledAt": str(raw.get("done_at") or raw.get("created_at") or ""),
        "settlementDate": None,
    }


def _dashboard_response(
    now: datetime,
    *,
    status: str,
    primary_symbol: str,
    user_email: Optional[str],
    accounts: list[dict[str, Any]],
    watchlist: list[dict[str, Any]],
    orderbook: Optional[dict[str, Any]],
    candles: list[dict[str, str]],
    holdings: list[dict[str, Any]],
    open_orders: list[dict[str, str]],
    executions: list[dict[str, Any]],
    buying_power: list[dict[str, str]],
    errors: list[str],
) -> dict[str, Any]:
    buying_power_by_currency = {
        item["currency"]: item["cashBuyingPower"] for item in buying_power
    }
    trading_status = _trading_status(user_email=user_email)
    return {
        "status": status,
        "fetchedAt": now.isoformat(),
        "cached": False,
        "cacheSeconds": UPBIT_CACHE_SECONDS,
        "source": {
            "title": "업비트 Open API",
            "provider": "Upbit",
            "sourceUrl": UPBIT_SOURCE_URL,
            "specUrl": UPBIT_DOCS_URL,
            "description": "업비트 Open API의 공개 시세와 API Key 기반 잔고, 주문 조회 및 주문 생성 API를 사용합니다.",
        },
        "summary": {
            "market": UPBIT_MARKET_CODE,
            "primarySymbol": primary_symbol,
            "symbolCount": len(watchlist),
            "accountCount": len(accounts),
            "accountConfigured": _has_private_keys(),
            "selectedAccountMasked": "업비트 지갑" if _has_private_keys() else None,
            "holdingCount": len(holdings),
            "openOrderCount": len(open_orders),
            "executionCount": len(executions),
            "buyingPowerKrw": buying_power_by_currency.get("KRW"),
            "buyingPowerUsd": None,
            **trading_status,
        },
        "accounts": accounts,
        "watchlist": watchlist,
        "orderbook": orderbook,
        "candles": candles,
        "holdings": holdings,
        "openOrders": open_orders,
        "executions": executions,
        "buyingPower": buying_power,
        "errors": errors,
    }


def _order_create_payload(raw: dict[str, Any]) -> dict[str, Any]:
    symbol = _normalize_market_symbol(str(raw.get("symbol") or ""), quote_currency="KRW")
    if not symbol:
        raise ValueError("코인 마켓 코드를 확인해 주세요.")

    side = str(raw.get("side") or "").strip().upper()
    if side not in {"BUY", "SELL"}:
        raise ValueError("주문 방향은 BUY 또는 SELL만 가능합니다.")

    order_type = str(raw.get("orderType") or "").strip().upper()
    if order_type != "LIMIT":
        raise ValueError("현재 업비트 코인 주문은 지정가만 지원합니다.")

    quantity = _clean_decimal(raw.get("quantity"))
    price = _clean_decimal(raw.get("price"))
    if not _decimal_token(quantity) or not _positive_decimal(quantity):
        raise ValueError("주문 수량은 0보다 커야 합니다.")
    if not _decimal_token(price) or not _positive_decimal(price):
        raise ValueError("지정가 주문에는 0보다 큰 주문 가격이 필요합니다.")

    return {
        "market": symbol,
        "side": "bid" if side == "BUY" else "ask",
        "volume": quantity,
        "price": price,
        "ord_type": "limit",
        "identifier": _client_order_id(),
    }


def _ensure_order_available(order_payload: dict[str, Any]) -> None:
    market = str(order_payload.get("market") or "")
    chance = _private_get("/v1/orders/chance", params={"market": market})
    if not isinstance(chance, dict):
        raise UpbitApiError("업비트 주문 가능 정보를 확인하지 못했습니다.")

    market_info = chance.get("market")
    market_info = market_info if isinstance(market_info, dict) else {}
    side = str(order_payload.get("side") or "")
    order_amount = _order_amount(order_payload)

    supported_sides = market_info.get("order_sides")
    if supported_sides and not _contains_text(supported_sides, side):
        raise ValueError(f"{market} 마켓은 {_ui_side(side)} 주문을 지원하지 않습니다.")

    order_type_key = "bid_types" if side == "bid" else "ask_types"
    supported_order_types = market_info.get(order_type_key) or market_info.get(
        "order_types"
    )
    if supported_order_types and not _contains_text(supported_order_types, "limit"):
        raise ValueError(f"{market} 마켓은 지정가 {_ui_side(side)} 주문을 지원하지 않습니다.")

    min_total = _chance_total_limit(market_info, side, "min_total")
    if min_total is not None and order_amount < min_total:
        raise ValueError(
            f"{market} 최소 주문 금액은 {_decimal_label(min_total)} KRW 이상입니다."
        )

    max_total = _chance_total_limit(market_info, side, "max_total")
    if max_total is not None and order_amount > max_total:
        raise ValueError(
            f"{market} 최대 주문 금액은 {_decimal_label(max_total)} KRW 이하입니다."
        )

    if side == "bid":
        balance = _chance_account_balance(chance, "bid_account")
        if balance is not None and balance < order_amount:
            raise ValueError("주문가능 KRW 잔고가 부족합니다.")
        return

    balance = _chance_account_balance(chance, "ask_account")
    volume = _decimal_value(order_payload.get("volume"))
    if balance is not None and volume is not None and balance < volume:
        raise ValueError("주문가능 코인 잔고가 부족합니다.")


def _order_amount(order_payload: dict[str, Any]) -> Decimal:
    price = _decimal_value(order_payload.get("price"))
    volume = _decimal_value(order_payload.get("volume"))
    if price is None or volume is None:
        raise ValueError("주문 가격과 수량을 확인해 주세요.")
    return price * volume


def _chance_total_limit(
    market_info: dict[str, Any],
    side: str,
    field: str,
) -> Optional[Decimal]:
    side_key = "bid" if side == "bid" else "ask"
    side_policy = market_info.get(side_key)
    if isinstance(side_policy, dict):
        value = _decimal_value(side_policy.get(field))
        if value is not None:
            return value
    return _decimal_value(
        market_info.get(field) or market_info.get(f"{side_key}_{field}")
    )


def _chance_account_balance(chance: dict[str, Any], key: str) -> Optional[Decimal]:
    account = chance.get(key)
    if not isinstance(account, dict):
        return None
    return _decimal_value(account.get("balance"))


def _contains_text(values: Any, needle: str) -> bool:
    if isinstance(values, str):
        return values.strip().lower() == needle.lower()
    if isinstance(values, (list, tuple, set)):
        return any(str(value).strip().lower() == needle.lower() for value in values)
    return False


def _decimal_value(value: Any) -> Optional[Decimal]:
    token = _clean_decimal(value)
    if not token:
        return None
    try:
        return Decimal(token)
    except InvalidOperation:
        return None


def _decimal_label(value: Decimal) -> str:
    text = format(value, "f")
    if "." in text:
        text = text.rstrip("0").rstrip(".")
    return text or "0"


def _ensure_trading_allowed(user_email: str) -> None:
    if not settings.upbit_trading_enabled:
        raise PermissionError("업비트 실제 주문 기능이 서버에서 비활성화되어 있습니다.")

    allowed_emails = settings.upbit_trading_allowed_emails
    normalized_email = (user_email or "").strip().lower()
    if not allowed_emails:
        raise PermissionError("업비트 실제 주문 허용 이메일이 설정되지 않았습니다.")
    if normalized_email not in allowed_emails:
        raise PermissionError("이 계정은 업비트 실제 주문 권한이 없습니다.")
    if not _has_private_keys():
        raise PermissionError("업비트 API 키가 설정되지 않았습니다.")


def _trading_allowed_for_user(user_email: Optional[str]) -> bool:
    normalized_email = (user_email or "").strip().lower()
    return bool(
        normalized_email
        and settings.upbit_trading_allowed_emails
        and normalized_email in settings.upbit_trading_allowed_emails
    )


def _trading_status(*, user_email: Optional[str]) -> dict[str, Any]:
    enabled = bool(settings.upbit_trading_enabled)
    allowed = _trading_allowed_for_user(user_email)
    has_api_keys = _has_private_keys()
    available = bool(enabled and allowed and has_api_keys)

    blocked_reason: Optional[str] = None
    if not enabled:
        blocked_reason = "업비트 실제 주문 기능이 서버에서 비활성화되어 있습니다."
    elif not settings.upbit_trading_allowed_emails:
        blocked_reason = "업비트 실제 주문 허용 이메일이 설정되지 않았습니다."
    elif not allowed:
        blocked_reason = "이 로그인 계정에는 업비트 실제 주문 권한이 없습니다."
    elif not has_api_keys:
        blocked_reason = "업비트 API 키가 설정되지 않았습니다."

    return {
        "tradingEnabled": enabled,
        "tradingAllowed": allowed,
        "tradingAvailable": available,
        "tradingBlockedReason": blocked_reason,
    }


def _has_private_keys() -> bool:
    return bool(settings.upbit_access_key and settings.upbit_secret_key)


def _order_id(order_id: str) -> str:
    value = str(order_id or "").strip()
    if not value or not re.fullmatch(r"[A-Za-z0-9_\-=.]{1,200}", value):
        raise ValueError("주문 ID가 올바르지 않습니다.")
    return value


def _ui_side(value: str) -> str:
    normalized = value.strip().lower()
    if normalized in {"bid", "buy"}:
        return "BUY"
    if normalized in {"ask", "sell"}:
        return "SELL"
    return value.strip().upper()


def _client_order_id() -> str:
    return f"kang-upbit-{uuid4().hex[:24]}"[:36]


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


def _normalize_search(value: str) -> str:
    return re.sub(r"\s+", "", str(value or "").lower())


def _response_error(response: requests.Response) -> str:
    try:
        payload = response.json()
    except ValueError:
        payload = {}
    message = ""
    if isinstance(payload, dict):
        error = payload.get("error")
        if isinstance(error, dict):
            message = str(error.get("message") or error.get("name") or "")
        if not message:
            for key in ("message", "error_description", "error", "name"):
                value = payload.get(key)
                if value:
                    message = str(value)
                    break
    if not message:
        message = response.text[:160]
    return f"HTTP {response.status_code}: {message[:180]}"


def _safe_error(exc: Exception) -> str:
    message = str(exc)
    if settings.upbit_access_key:
        message = message.replace(settings.upbit_access_key, "[access_key]")
    if settings.upbit_secret_key:
        message = message.replace(settings.upbit_secret_key, "[secret_key]")
    return message[:220]


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
    return f"{value:.10f}".rstrip("0").rstrip(".")
