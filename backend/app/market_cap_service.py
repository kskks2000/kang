from __future__ import annotations

from copy import deepcopy
from datetime import datetime, timedelta, timezone
from html import unescape
from html.parser import HTMLParser
from typing import Any

import requests

from .settings import settings


SOURCE_URL = "https://companiesmarketcap.com/"
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
            "User-Agent": settings.browser_user_agent,
        },
        timeout=30,
    )
    response.raise_for_status()
    companies = _extract_companies(response.text, fetched_at=datetime.now(timezone.utc))
    companies.sort(key=lambda item: item["rank"])
    return companies[:limit]


def _extract_companies(html: str, *, fetched_at: datetime) -> list[dict[str, Any]]:
    parser = _CompaniesMarketCapTableParser(fetched_at=fetched_at)
    parser.feed(html)
    companies = parser.companies
    if not companies:
        raise ValueError("CompaniesMarketCap table was not found.")
    return companies


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
            "title": "Largest Companies by Marketcap",
            "provider": "CompaniesMarketCap.com",
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


def _safe_float_from_cents(value: Any) -> float | None:
    number = _safe_float(value)
    if number is None:
        return None
    return number / 100


def _safe_percent_from_basis(value: Any) -> float | None:
    number = _safe_float(value)
    if number is None:
        return None
    return number / 100


def _classes(attrs: dict[str, str]) -> set[str]:
    return set(attrs.get("class", "").split())


def _clean_text(value: str) -> str:
    return " ".join(unescape(value).split()).strip()


def _country_code(country: str) -> str:
    return {
        "Argentina": "AR",
        "Australia": "AU",
        "Belgium": "BE",
        "Brazil": "BR",
        "Canada": "CA",
        "Chile": "CL",
        "China": "CN",
        "Denmark": "DK",
        "Finland": "FI",
        "France": "FR",
        "Germany": "DE",
        "Hong Kong": "HK",
        "India": "IN",
        "Indonesia": "ID",
        "Ireland": "IE",
        "Israel": "IL",
        "Italy": "IT",
        "Japan": "JP",
        "Luxembourg": "LU",
        "Mexico": "MX",
        "Netherlands": "NL",
        "Norway": "NO",
        "Poland": "PL",
        "S. Africa": "ZA",
        "S. Arabia": "SA",
        "S. Korea": "KR",
        "Singapore": "SG",
        "Spain": "ES",
        "Sweden": "SE",
        "Switzerland": "CH",
        "Taiwan": "TW",
        "Thailand": "TH",
        "Turkey": "TR",
        "UAE": "AE",
        "UK": "GB",
        "USA": "US",
    }.get(country, "")


class _CompaniesMarketCapTableParser(HTMLParser):
    def __init__(self, *, fetched_at: datetime) -> None:
        super().__init__(convert_charrefs=True)
        self.companies: list[dict[str, Any]] = []
        self._fetched_at = fetched_at.isoformat()
        self._in_row = False
        self._current_cells: list[dict[str, Any]] = []
        self._current_cell: dict[str, Any] | None = None
        self._company_name_parts: list[str] = []
        self._company_code_parts: list[str] = []
        self._country_parts: list[str] = []
        self._name_depth = 0
        self._code_depth = 0
        self._country_depth = 0

    def handle_starttag(
        self,
        tag: str,
        attrs: list[tuple[str, str | None]],
    ) -> None:
        attrs_dict = {key: value or "" for key, value in attrs}
        if self._name_depth:
            self._name_depth += 1
        if self._code_depth:
            self._code_depth += 1
        if self._country_depth:
            self._country_depth += 1

        if tag == "tr":
            self._in_row = True
            self._current_cells = []
            self._current_cell = None
            self._company_name_parts = []
            self._company_code_parts = []
            self._country_parts = []
            self._name_depth = 0
            self._code_depth = 0
            self._country_depth = 0
            return

        if not self._in_row:
            return

        if tag == "td":
            self._current_cell = {
                "classes": _classes(attrs_dict),
                "data_sort": attrs_dict.get("data-sort", ""),
                "text_parts": [],
            }
            return

        tag_classes = _classes(attrs_dict)
        if tag == "div" and "company-name" in tag_classes:
            self._name_depth = 1
        elif tag == "div" and "company-code" in tag_classes:
            self._code_depth = 1
        elif tag == "span" and "responsive-hidden" in tag_classes:
            self._country_depth = 1

    def handle_data(self, data: str) -> None:
        if not self._in_row:
            return
        if self._current_cell is not None:
            self._current_cell["text_parts"].append(data)
        if self._name_depth:
            self._company_name_parts.append(data)
        if self._code_depth:
            self._company_code_parts.append(data)
        if self._country_depth:
            self._country_parts.append(data)

    def handle_endtag(self, tag: str) -> None:
        if tag == "td" and self._current_cell is not None:
            self._current_cell["text"] = _clean_text(
                "".join(self._current_cell.pop("text_parts")),
            )
            self._current_cells.append(self._current_cell)
            self._current_cell = None

        if tag == "tr" and self._in_row:
            company = self._build_company()
            if company is not None:
                self.companies.append(company)
            self._in_row = False
            self._current_cell = None

        if self._name_depth:
            self._name_depth -= 1
        if self._code_depth:
            self._code_depth -= 1
        if self._country_depth:
            self._country_depth -= 1

    def _build_company(self) -> dict[str, Any] | None:
        rank_cell = self._find_cell("rank-td")
        if rank_cell is None:
            return None

        name = _clean_text("".join(self._company_name_parts))
        symbol = _clean_text("".join(self._company_code_parts))
        if not name or not symbol:
            return None

        rank = _safe_int(rank_cell.get("data_sort") or rank_cell.get("text"))
        data_cells = [
            cell
            for cell in self._current_cells
            if cell.get("data_sort") not in (None, "")
        ]
        if len(data_cells) < 4:
            return None

        country = _clean_text("".join(self._country_parts))
        if not country:
            country_cell = self._current_cells[-1] if self._current_cells else {}
            country = _clean_text(str(country_cell.get("text", "")))

        return {
            "rank": rank,
            "symbol": symbol,
            "name": name,
            "country": country,
            "countryCode": _country_code(country),
            "sector": "",
            "industry": "",
            "marketCap": _safe_int(data_cells[1].get("data_sort")),
            "price": _safe_float_from_cents(data_cells[2].get("data_sort")),
            "dailyChangePercent": _safe_percent_from_basis(
                data_cells[3].get("data_sort"),
            ),
            "peRatio": None,
            "revenue": 0,
            "earnings": 0,
            "lastUpdated": self._fetched_at,
        }

    def _find_cell(self, class_name: str) -> dict[str, Any] | None:
        for cell in self._current_cells:
            if class_name in cell.get("classes", set()):
                return cell
        return None
