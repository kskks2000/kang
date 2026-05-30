from __future__ import annotations

from copy import deepcopy
from datetime import datetime, timedelta, timezone
from typing import Any
import xml.etree.ElementTree as ET

import requests


TREASURY_URL = "https://home.treasury.gov/resource-center/data-chart-center/interest-rates/pages/xml"
YAHOO_CHART_URL = "https://query1.finance.yahoo.com/v8/finance/chart/{symbol}"
CACHE_SECONDS = 60

TREASURY_MATURITIES = [
    ("1M", "BC_1MONTH", "1개월"),
    ("3M", "BC_3MONTH", "3개월"),
    ("6M", "BC_6MONTH", "6개월"),
    ("1Y", "BC_1YEAR", "1년"),
    ("2Y", "BC_2YEAR", "2년"),
    ("5Y", "BC_5YEAR", "5년"),
    ("10Y", "BC_10YEAR", "10년"),
    ("30Y", "BC_30YEAR", "30년"),
]

FX_QUOTES = [
    ("KRW=X", "USD/KRW", "달러/원"),
    ("JPY=X", "USD/JPY", "달러/엔"),
    ("CNY=X", "USD/CNY", "달러/위안"),
    ("EURUSD=X", "EUR/USD", "유로/달러"),
    ("GBPUSD=X", "GBP/USD", "파운드/달러"),
    ("CHF=X", "USD/CHF", "달러/스위스프랑"),
    ("CAD=X", "USD/CAD", "달러/캐나다달러"),
    ("AUDUSD=X", "AUD/USD", "호주달러/달러"),
]

MARKET_SYMBOLS = [
    ("ES=F", "S&P 500 E-mini", "미국 지수선물"),
    ("NQ=F", "Nasdaq 100 E-mini", "미국 지수선물"),
    ("YM=F", "Dow Jones Mini", "미국 지수선물"),
    ("RTY=F", "Russell 2000 E-mini", "미국 지수선물"),
    ("CL=F", "WTI Crude Oil", "원자재"),
    ("GC=F", "Gold", "원자재"),
    ("DX-Y.NYB", "US Dollar Index", "매크로"),
    ("^VIX", "CBOE VIX", "리스크"),
]

_CACHE: dict[str, Any] | None = None
_CACHE_EXPIRES_AT: datetime | None = None


def load_financial_markets() -> dict[str, Any]:
    global _CACHE, _CACHE_EXPIRES_AT

    now = datetime.now(timezone.utc)
    if _CACHE and _CACHE_EXPIRES_AT and _CACHE_EXPIRES_AT > now:
        cached = deepcopy(_CACHE)
        cached["cached"] = True
        return cached

    errors: list[str] = []
    treasury_rates: list[dict[str, Any]] = []
    treasury_spreads: list[dict[str, Any]] = []
    exchange_rates: list[dict[str, Any]] = []
    futures: list[dict[str, Any]] = []

    try:
        treasury_rates, treasury_spreads = _fetch_treasury_rates()
    except Exception as exc:  # noqa: BLE001 - surface source failures per section.
        errors.append(f"US Treasury: {exc}")

    try:
        exchange_rates = _fetch_exchange_rates()
    except Exception as exc:  # noqa: BLE001
        errors.append(f"FX: {exc}")

    for symbol, name, group in MARKET_SYMBOLS:
        try:
            futures.append(_fetch_market_quote(symbol, name=name, group=group))
        except Exception as exc:  # noqa: BLE001
            errors.append(f"{symbol}: {exc}")

    dataset = _dataset_response(
        now,
        treasury_rates=treasury_rates,
        treasury_spreads=treasury_spreads,
        exchange_rates=exchange_rates,
        futures=futures,
        errors=errors,
    )
    _CACHE = deepcopy(dataset)
    _CACHE_EXPIRES_AT = now + timedelta(seconds=CACHE_SECONDS)
    dataset["cached"] = False
    return dataset


def _fetch_treasury_rates() -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    response = requests.get(
        TREASURY_URL,
        params={
            "data": "daily_treasury_yield_curve",
            "field_tdr_date_value": str(datetime.now(timezone.utc).year),
        },
        headers={"User-Agent": "KangPrivateHub/1.0 (+https://kang.ai.kr)"},
        timeout=30,
    )
    response.raise_for_status()
    records = _parse_treasury_records(response.content)
    if len(records) < 1:
        raise ValueError("no treasury yield records returned")

    records.sort(key=lambda item: item["date"])
    latest = records[-1]
    previous = records[-2] if len(records) >= 2 else {}
    rates = []
    for maturity, field, label in TREASURY_MATURITIES:
        rate = _safe_float(latest.get(field))
        previous_rate = _safe_float(previous.get(field))
        rates.append(
            {
                "maturity": maturity,
                "label": label,
                "rate": rate,
                "previousRate": previous_rate,
                "change": _diff(rate, previous_rate),
                "date": latest["date"],
            }
        )

    values = {item["maturity"]: item["rate"] for item in rates}
    spreads = [
        _spread("10Y-2Y", "장단기 스프레드", values.get("10Y"), values.get("2Y"), latest["date"]),
        _spread("30Y-10Y", "초장기 프리미엄", values.get("30Y"), values.get("10Y"), latest["date"]),
        _spread("10Y-3M", "경기민감 스프레드", values.get("10Y"), values.get("3M"), latest["date"]),
    ]
    return rates, spreads


def _parse_treasury_records(payload: bytes) -> list[dict[str, str]]:
    root = ET.fromstring(payload)
    records: list[dict[str, str]] = []
    for entry in root.findall("{http://www.w3.org/2005/Atom}entry"):
        record: dict[str, str] = {}
        for element in entry.iter():
            tag = _local_name(element.tag)
            if tag == "NEW_DATE" and element.text:
                record["date"] = element.text[:10]
            elif tag.startswith("BC_") and element.text:
                record[tag] = element.text.strip()
        if record.get("date"):
            records.append(record)
    return records


def _fetch_exchange_rates() -> list[dict[str, Any]]:
    result = []
    for symbol, pair, label in FX_QUOTES:
        result.append(_fetch_exchange_quote(symbol, pair=pair, label=label))
    return result


def _fetch_exchange_quote(symbol: str, *, pair: str, label: str) -> dict[str, Any]:
    result = _fetch_yahoo_chart(symbol, range_value="1d", interval="1m")
    meta = result.get("meta") or {}
    rate = _safe_float(meta.get("regularMarketPrice")) or _latest_close(result)
    previous = _safe_float(meta.get("previousClose")) or _safe_float(
        meta.get("chartPreviousClose"),
    )
    change = _diff(rate, previous)
    change_percent = None
    if change is not None and previous not in (None, 0):
        change_percent = change / previous * 100
    market_time = _timestamp_to_iso(meta.get("regularMarketTime"))
    return {
        "pair": pair,
        "label": label,
        "base": pair.split("/", 1)[0],
        "quote": pair.split("/", 1)[1],
        "rate": rate or 0,
        "usdBaseRate": rate or 0,
        "previousRate": previous,
        "change": change,
        "changePercent": change_percent,
        "date": market_time[:10] if market_time else "",
        "marketTime": market_time,
        "sourceSymbol": symbol,
    }


def _fetch_market_quote(symbol: str, *, name: str, group: str) -> dict[str, Any]:
    result = _fetch_yahoo_chart(symbol, range_value="1d", interval="1m")
    meta = result.get("meta") or {}
    price = _safe_float(meta.get("regularMarketPrice")) or _latest_close(result)
    previous = _safe_float(meta.get("previousClose")) or _safe_float(
        meta.get("chartPreviousClose"),
    )
    change = _diff(price, previous)
    change_percent = None
    if change is not None and previous not in (None, 0):
        change_percent = change / previous * 100
    market_time = _timestamp_to_iso(meta.get("regularMarketTime"))
    return {
        "symbol": symbol,
        "name": name,
        "displayName": meta.get("shortName") or name,
        "group": group,
        "price": price,
        "change": change,
        "changePercent": change_percent,
        "previousClose": previous,
        "currency": meta.get("currency") or "",
        "marketTime": market_time,
        "exchange": meta.get("fullExchangeName") or meta.get("exchangeName") or "",
    }


def _dataset_response(
    now: datetime,
    *,
    treasury_rates: list[dict[str, Any]],
    treasury_spreads: list[dict[str, Any]],
    exchange_rates: list[dict[str, Any]],
    futures: list[dict[str, Any]],
    errors: list[str],
) -> dict[str, Any]:
    sections_ready = sum(
        1
        for section in (treasury_rates, exchange_rates, futures)
        if len(section) > 0
    )
    status = "ok" if not errors and sections_ready == 3 else "partial" if sections_ready else "error"
    treasury_date = treasury_rates[0]["date"] if treasury_rates else None
    fx_date = exchange_rates[0]["date"] if exchange_rates else None
    return {
        "status": status,
        "fetchedAt": now.isoformat(),
        "cached": False,
        "cacheSeconds": CACHE_SECONDS,
        "sources": [
            {
                "name": "U.S. Department of the Treasury",
                "url": "https://home.treasury.gov/treasury-daily-interest-rate-xml-feed",
                "description": "Daily Treasury par yield curve XML feed.",
            },
            {
                "name": "Yahoo Finance chart data",
                "url": "https://finance.yahoo.com/",
                "description": "Currency, index futures, commodity and macro market quotes.",
            },
        ],
        "summary": {
            "treasuryDate": treasury_date,
            "exchangeRateDate": fx_date,
            "treasuryCount": len(treasury_rates),
            "exchangeRateCount": len(exchange_rates),
            "futureCount": len(futures),
            "errorCount": len(errors),
        },
        "treasuryRates": treasury_rates,
        "treasurySpreads": treasury_spreads,
        "exchangeRates": exchange_rates,
        "futures": futures,
        "errors": errors,
    }


def _spread(
    code: str,
    label: str,
    high: float | None,
    low: float | None,
    date: str,
) -> dict[str, Any]:
    return {
        "code": code,
        "label": label,
        "value": _diff(high, low),
        "date": date,
    }


def _diff(left: float | None, right: float | None) -> float | None:
    if left is None or right is None:
        return None
    return left - right


def _fetch_yahoo_chart(
    symbol: str,
    *,
    range_value: str,
    interval: str,
) -> dict[str, Any]:
    response = requests.get(
        YAHOO_CHART_URL.format(symbol=symbol),
        params={"range": range_value, "interval": interval},
        headers={"User-Agent": "Mozilla/5.0"},
        timeout=30,
    )
    response.raise_for_status()
    payload = response.json()
    result = ((payload.get("chart") or {}).get("result") or [None])[0]
    if not isinstance(result, dict):
        raise ValueError("invalid chart response")
    return result


def _latest_close(result: dict[str, Any]) -> float | None:
    quotes = ((result.get("indicators") or {}).get("quote") or [])
    if not quotes or not isinstance(quotes[0], dict):
        return None
    closes = quotes[0].get("close")
    if not isinstance(closes, list):
        return None
    for value in reversed(closes):
        close = _safe_float(value)
        if close is not None:
            return close
    return None


def _safe_float(value: Any) -> float | None:
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _timestamp_to_iso(value: Any) -> str:
    try:
        return datetime.fromtimestamp(int(value), tz=timezone.utc).isoformat()
    except (TypeError, ValueError, OSError):
        return ""


def _local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]
