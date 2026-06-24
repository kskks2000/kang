from __future__ import annotations

from datetime import datetime, timedelta, timezone
import re
from typing import Any

import requests

from .settings import settings


KRX_STOCK_SEARCH_URL = "https://data.krx.co.kr/comm/util/SearchEngine/isuCore.cmd"
KRX_SEARCH_REFERER = "https://data.krx.co.kr/contents/MDC/COMS/search/MDCCOMS902.cmd"
KRX_CACHE_SECONDS = 60 * 30
KRX_MARKETS = {"KOSPI", "KOSDAQ"}

FALLBACK_KRX_STOCKS = [
    {"symbol": "005930", "name": "삼성전자", "market": "KOSPI"},
    {"symbol": "000660", "name": "SK하이닉스", "market": "KOSPI"},
    {"symbol": "035420", "name": "NAVER", "market": "KOSPI"},
    {"symbol": "035720", "name": "카카오", "market": "KOSPI"},
    {"symbol": "068270", "name": "셀트리온", "market": "KOSPI"},
    {"symbol": "005380", "name": "현대차", "market": "KOSPI"},
    {"symbol": "051910", "name": "LG화학", "market": "KOSPI"},
    {"symbol": "066570", "name": "LG전자", "market": "KOSPI"},
    {"symbol": "034020", "name": "두산에너빌리티", "market": "KOSPI"},
    {"symbol": "086520", "name": "에코프로", "market": "KOSDAQ"},
    {"symbol": "247540", "name": "에코프로비엠", "market": "KOSDAQ"},
]

_SEARCH_CACHE: dict[str, tuple[datetime, list[dict[str, str]]]] = {}


def search_krx_stocks(query: str, *, limit: int = 30) -> list[dict[str, str]]:
    normalized_query = _normalize_query(query)
    if not normalized_query:
        return []

    bounded_limit = max(1, min(limit, 50))
    cache_key = f"{normalized_query.lower()}:{bounded_limit}"
    now = datetime.now(timezone.utc)
    cached = _SEARCH_CACHE.get(cache_key)
    if cached and cached[0] > now:
        return [dict(item) for item in cached[1]]

    try:
        items = _fetch_krx_search(normalized_query, bounded_limit=bounded_limit)
    except (requests.RequestException, ValueError):
        items = []
    if not items:
        items = _fallback_search(normalized_query, bounded_limit=bounded_limit)

    if re.fullmatch(r"\d{6}", normalized_query) and not any(
        item["symbol"] == normalized_query for item in items
    ):
        items.insert(
            0,
            {"symbol": normalized_query, "name": normalized_query, "market": "KRX"},
        )

    items = _rank_items(items, normalized_query)[:bounded_limit]
    _SEARCH_CACHE[cache_key] = (now + timedelta(seconds=KRX_CACHE_SECONDS), items)
    return [dict(item) for item in items]


def _fetch_krx_search(
    normalized_query: str,
    *,
    bounded_limit: int,
) -> list[dict[str, str]]:
    rows = max(80, bounded_limit * 4)
    response = requests.get(
        KRX_STOCK_SEARCH_URL,
        params={"solrKeyword": normalized_query, "rows": str(rows), "start": "0"},
        headers={
            "Accept": "application/json",
            "Referer": KRX_SEARCH_REFERER,
            "User-Agent": settings.http_user_agent,
        },
        timeout=8,
    )
    response.raise_for_status()
    payload = response.json()
    raw_items = payload.get("result", []) if isinstance(payload, dict) else []
    if not isinstance(raw_items, list):
        return []

    results: list[dict[str, str]] = []
    seen_symbols: set[str] = set()
    for raw_item in raw_items:
        item = _krx_item(raw_item)
        if item is None or item["symbol"] in seen_symbols:
            continue
        seen_symbols.add(item["symbol"])
        results.append(item)
    return results


def _krx_item(raw_item: Any) -> dict[str, str] | None:
    if not isinstance(raw_item, dict):
        return None
    item_type = _first_text(raw_item.get("isu_tp")).upper()
    symbol = _first_text(raw_item.get("isu_srt_cd")).upper()
    name = _first_text(raw_item.get("isu_abbrv"))
    market = _first_text(raw_item.get("mkt_nm")).upper()
    if item_type != "STK":
        return None
    if market not in KRX_MARKETS:
        return None
    if not re.fullmatch(r"\d{6}", symbol):
        return None
    return {"symbol": symbol, "name": name or symbol, "market": market}


def _fallback_search(normalized_query: str, *, bounded_limit: int) -> list[dict[str, str]]:
    query = normalized_query.lower()
    return [
        dict(item)
        for item in FALLBACK_KRX_STOCKS
        if query in item["symbol"].lower()
        or query in item["name"].lower()
        or query in item["market"].lower()
    ][:bounded_limit]


def _rank_items(
    items: list[dict[str, str]],
    normalized_query: str,
) -> list[dict[str, str]]:
    query = normalized_query.lower()

    def rank(item: dict[str, str]) -> tuple[int, str]:
        symbol = item["symbol"].lower()
        name = item["name"].lower()
        if symbol == query:
            return (0, symbol)
        if name == query:
            return (1, symbol)
        if symbol.startswith(query):
            return (2, symbol)
        if name.startswith(query):
            return (3, symbol)
        return (4, symbol)

    return sorted(items, key=rank)


def _first_text(value: Any) -> str:
    if isinstance(value, list):
        value = value[0] if value else ""
    return str(value or "").strip()


def _normalize_query(query: str) -> str:
    return re.sub(r"\s+", " ", str(query or "").strip())
