from __future__ import annotations

from copy import deepcopy
from datetime import datetime, timedelta, timezone
from typing import Any
import json

import requests


SOURCE_URL = "https://companiesmarketcap.org/"
CACHE_TTL = timedelta(minutes=30)
DEFAULT_LIMIT = 100

_CACHE: dict[str, Any] | None = None
_CACHE_EXPIRES_AT: datetime | None = None


def load_global_market_cap_top(limit: int = DEFAULT_LIMIT) -> dict[str, Any]:
    global _CACHE, _CACHE_EXPIRES_AT

    now = datetime.now(timezone.utc)
    if _CACHE and _CACHE_EXPIRES_AT and _CACHE_EXPIRES_AT > now:
        cached = deepcopy(_CACHE)
        cached["cached"] = True
        return cached

    companies = _fetch_companies(limit=limit)
    dataset = _dataset_response(now, companies, limit=limit)
    _CACHE = deepcopy(dataset)
    _CACHE_EXPIRES_AT = now + CACHE_TTL
    dataset["cached"] = False
    return dataset


def _fetch_companies(*, limit: int) -> list[dict[str, Any]]:
    response = requests.get(
        SOURCE_URL,
        headers={
            "Accept": "text/html,application/xhtml+xml",
            "User-Agent": "KangPrivateHub/1.0 (+https://kang.ai.kr)",
        },
        timeout=30,
    )
    response.raise_for_status()
    raw_companies = _extract_companies(response.text)
    normalized = [_normalize_company(item) for item in raw_companies]
    normalized.sort(key=lambda item: item["rank"])
    return normalized[:limit]


def _extract_companies(html: str) -> list[dict[str, Any]]:
    decoded = html.replace('\\"', '"')
    marker = '"companies":['
    marker_index = decoded.find(marker)
    if marker_index < 0:
        raise ValueError("CompaniesMarketCap payload was not found.")

    start = decoded.find("[", marker_index)
    if start < 0:
        raise ValueError("CompaniesMarketCap company list was not found.")

    end = _matching_json_array_end(decoded, start)
    payload = decoded[start:end]
    companies = json.loads(payload)
    if not isinstance(companies, list):
        raise ValueError("CompaniesMarketCap company list is invalid.")
    return [item for item in companies if isinstance(item, dict)]


def _matching_json_array_end(text: str, start: int) -> int:
    depth = 0
    in_string = False
    escaped = False
    for index in range(start, len(text)):
        char = text[index]
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            continue

        if char == '"':
            in_string = True
        elif char == "[":
            depth += 1
        elif char == "]":
            depth -= 1
            if depth == 0:
                return index + 1

    raise ValueError("CompaniesMarketCap company list was not closed.")


def _normalize_company(item: dict[str, Any]) -> dict[str, Any]:
    return {
        "rank": _safe_int(item.get("rank")),
        "symbol": _safe_text(item.get("symbol")),
        "name": _safe_text(item.get("name")),
        "country": _country_name(_safe_text(item.get("country"))),
        "countryCode": _safe_text(item.get("country")),
        "sector": _safe_text(item.get("sector")),
        "industry": _safe_text(item.get("industry")),
        "marketCap": _safe_int(item.get("marketCap")),
        "price": _safe_float(item.get("price")),
        "dailyChangePercent": _safe_float(item.get("dailyChangePercent")),
        "peRatio": _safe_float(item.get("peRatio")),
        "revenue": _safe_int(item.get("revenue")),
        "earnings": _safe_int(item.get("earnings")),
        "lastUpdated": _safe_text(item.get("lastUpdated")),
    }


def _dataset_response(
    now: datetime,
    companies: list[dict[str, Any]],
    *,
    limit: int,
) -> dict[str, Any]:
    top = companies[0] if companies else None
    last_updated = max(
        (item["lastUpdated"] for item in companies if item["lastUpdated"]),
        default=None,
    )
    return {
        "status": "ok" if companies else "error",
        "fetchedAt": now.isoformat(),
        "cached": False,
        "cacheSeconds": int(CACHE_TTL.total_seconds()),
        "source": {
            "title": "Largest Companies by Market Cap",
            "provider": "CompaniesMarketCap.org",
            "sourceUrl": SOURCE_URL,
            "description": "Global public-company rankings ordered by market capitalization.",
        },
        "summary": {
            "requestedLimit": limit,
            "count": len(companies),
            "topCompany": top["name"] if top else None,
            "topSymbol": top["symbol"] if top else None,
            "topMarketCap": top["marketCap"] if top else None,
            "lastUpdated": last_updated,
        },
        "companies": companies,
    }


def _safe_text(value: Any) -> str:
    if value is None:
        return ""
    return str(value).strip()


def _safe_int(value: Any) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


def _safe_float(value: Any) -> float | None:
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _country_name(code: str) -> str:
    return {
        "AE": "United Arab Emirates",
        "AU": "Australia",
        "BE": "Belgium",
        "BR": "Brazil",
        "CA": "Canada",
        "CH": "Switzerland",
        "CN": "China",
        "DE": "Germany",
        "DK": "Denmark",
        "ES": "Spain",
        "FI": "Finland",
        "FR": "France",
        "GB": "United Kingdom",
        "HK": "Hong Kong",
        "IE": "Ireland",
        "IN": "India",
        "IT": "Italy",
        "JP": "Japan",
        "KR": "South Korea",
        "NL": "Netherlands",
        "NO": "Norway",
        "SA": "Saudi Arabia",
        "SE": "Sweden",
        "SG": "Singapore",
        "TW": "Taiwan",
        "US": "United States",
    }.get(code, code)
