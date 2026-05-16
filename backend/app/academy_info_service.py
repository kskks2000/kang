from __future__ import annotations

from copy import deepcopy
from datetime import datetime, timedelta, timezone
from typing import Any
import xml.etree.ElementTree as ET

import requests

from .settings import settings


BASE_URL = (
    "http://openapi.academyinfo.go.kr/openapi/service/rest/"
    "BasicInformationService"
)
CACHE_TTL = timedelta(hours=6)
DEFAULT_PAGE_SIZE = 999
MAX_PAGES = 20


OPERATION_DEFS: list[dict[str, Any]] = [
    {
        "group": "연도·지표",
        "title": "공시년도 조회_대학비교통계",
        "endpoint": "getComparisonPubYear",
        "description": "대학비교통계에서 사용할 수 있는 공시년도를 조회합니다.",
        "requiredParams": ["serviceKey"],
        "optionalParams": [],
        "responseFields": ["yearVal"],
        "yearSource": None,
        "paged": False,
    },
    {
        "group": "대학 검색",
        "title": "대학 검색목록_대학비교통계",
        "endpoint": "getComparisonUniversitySearchList",
        "description": "공시년도와 대학 조건으로 대학비교통계용 대학 목록을 조회합니다.",
        "requiredParams": ["serviceKey", "svyYr"],
        "optionalParams": [
            "schlId",
            "schlKrnNm",
            "clgcpDivCd",
            "schlDivCd",
            "schlKndCd",
            "znCd",
            "estbDivCd",
            "numOfRows",
            "pageNo",
        ],
        "responseFields": [
            "schlId",
            "schlKrnNm",
            "schlFullNm",
            "clgcpDivNm",
            "schlDivNm",
            "schlKndNm",
            "estbDivNm",
            "znNm",
        ],
        "yearSource": "comparison",
        "fallbackYear": "2018",
        "paged": True,
    },
    {
        "group": "대학 검색",
        "title": "대학 검색목록_우리대학경쟁력",
        "endpoint": "getNoticeUniversitySearchList",
        "description": "우리대학경쟁력 지표에서 사용할 대학 검색 목록을 조회합니다.",
        "requiredParams": ["serviceKey", "svyYr"],
        "optionalParams": [
            "schlId",
            "schlKrnNm",
            "clgcpDivCd",
            "schlDivCd",
            "schlKndCd",
            "znCd",
            "estbDivCd",
            "numOfRows",
            "pageNo",
        ],
        "responseFields": [
            "schlId",
            "schlKrnNm",
            "schlFullNm",
            "clgcpDivNm",
            "schlDivNm",
            "schlKndNm",
            "estbDivNm",
            "znNm",
        ],
        "yearSource": "notice",
        "fallbackYear": "2019",
        "paged": True,
    },
    {
        "group": "대학 검색",
        "title": "대학 코드조회",
        "endpoint": "getUniversityCode",
        "description": "학교아이디, 대학명, 지역, 설립구분 등 대학 기본 코드를 조회합니다.",
        "requiredParams": ["serviceKey", "svyYr"],
        "optionalParams": [
            "schlId",
            "schlKrnNm",
            "clgcpDivCd",
            "schlDivCd",
            "znCd",
            "estbDivCd",
            "numOfRows",
            "pageNo",
        ],
        "responseFields": [
            "schlId",
            "schlKrnNm",
            "schlFullNm",
            "clgcpDivNm",
            "schlDivNm",
            "schlKndNm",
            "estbDivNm",
            "znNm",
        ],
        "yearSource": "comparison",
        "fallbackYear": "2018",
        "paged": True,
    },
    {
        "group": "코드표",
        "title": "설립유형별 코드조회",
        "endpoint": "getCodeByFound",
        "description": "국립, 공립, 사립 등 대학 설립유형 코드를 조회합니다.",
        "requiredParams": ["serviceKey"],
        "optionalParams": ["cdid", "cdnm", "numOfRows", "pageNo"],
        "responseFields": ["cdid", "cdnm"],
        "yearSource": None,
        "paged": True,
    },
    {
        "group": "연도·지표",
        "title": "조사년도 조회_우리대학경쟁력",
        "endpoint": "getNoticeSvyYear",
        "description": "우리대학경쟁력에서 사용할 수 있는 조사년도를 조회합니다.",
        "requiredParams": ["serviceKey"],
        "optionalParams": [],
        "responseFields": ["yearVal"],
        "yearSource": None,
        "paged": False,
    },
    {
        "group": "연도·지표",
        "title": "주요지표 코드조회",
        "endpoint": "getKeyIndicatorCode",
        "description": "재적학생, 취업률, 회계 현황 등 주요지표 코드를 조회합니다.",
        "requiredParams": ["serviceKey"],
        "optionalParams": ["cdid", "cdnm", "rmk", "numOfRows", "pageNo"],
        "responseFields": ["cdid", "cdnm", "rmk"],
        "yearSource": None,
        "paged": True,
    },
    {
        "group": "코드표",
        "title": "지역별 코드조회",
        "endpoint": "getCodeByRegion",
        "description": "대학 소재 지역 코드를 조회합니다.",
        "requiredParams": ["serviceKey"],
        "optionalParams": ["cdid", "cdnm", "numOfRows", "pageNo"],
        "responseFields": ["cdid", "cdnm"],
        "yearSource": None,
        "paged": True,
    },
    {
        "group": "코드표",
        "title": "학교유형별 코드조회",
        "endpoint": "getCodeByType",
        "description": "일반대학원, 전문대학, 사이버대학 등 학교유형 코드를 조회합니다.",
        "requiredParams": ["serviceKey"],
        "optionalParams": ["cdid", "cdnm", "numOfRows", "pageNo"],
        "responseFields": ["cdid", "cdnm"],
        "yearSource": None,
        "paged": True,
    },
    {
        "group": "코드표",
        "title": "학교종류별 코드조회",
        "endpoint": "getCodeByKind",
        "description": "전문대학, 대학, 대학원, 대학원대학 구분 코드를 조회합니다.",
        "requiredParams": ["serviceKey"],
        "optionalParams": ["cdid", "cdnm", "numOfRows", "pageNo"],
        "responseFields": ["cdid", "cdnm"],
        "yearSource": None,
        "paged": True,
    },
]

_CACHE: dict[str, Any] | None = None
_CACHE_EXPIRES_AT: datetime | None = None


def load_academy_info_basic() -> dict[str, Any]:
    global _CACHE, _CACHE_EXPIRES_AT

    now = datetime.now(timezone.utc)
    if _CACHE and _CACHE_EXPIRES_AT and _CACHE_EXPIRES_AT > now:
        cached = deepcopy(_CACHE)
        cached["cached"] = True
        return cached

    dataset = _build_dataset(now)
    _CACHE = deepcopy(dataset)
    _CACHE_EXPIRES_AT = now + CACHE_TTL
    dataset["cached"] = False
    return dataset


def _build_dataset(now: datetime) -> dict[str, Any]:
    service_key = settings.academyinfo_service_key
    if not service_key:
        operations = [
            _operation_error(
                operation,
                result_msg="ACADEMYINFO_SERVICE_KEY is not configured.",
            )
            for operation in OPERATION_DEFS
        ]
        return _dataset_response(now, operations)

    preloaded: dict[str, dict[str, Any]] = {}
    comparison_years = _fetch_operation(
        _operation_by_endpoint("getComparisonPubYear"),
        service_key=service_key,
    )
    notice_years = _fetch_operation(
        _operation_by_endpoint("getNoticeSvyYear"),
        service_key=service_key,
    )
    preloaded["getComparisonPubYear"] = comparison_years
    preloaded["getNoticeSvyYear"] = notice_years

    latest_comparison_year = _latest_year(comparison_years["rows"])
    latest_notice_year = _latest_year(notice_years["rows"])

    operations: list[dict[str, Any]] = []
    for operation in OPERATION_DEFS:
        endpoint = operation["endpoint"]
        if endpoint in preloaded:
            result = preloaded[endpoint]
        else:
            params: dict[str, str] = {}
            year_source = operation.get("yearSource")
            if year_source == "comparison":
                params["svyYr"] = latest_comparison_year or operation.get("fallbackYear", "2018")
            elif year_source == "notice":
                params["svyYr"] = latest_notice_year or operation.get("fallbackYear", "2019")

            result = _fetch_operation(
                operation,
                service_key=service_key,
                extra_params=params,
            )
        operations.append(result)

    return _dataset_response(
        now,
        operations,
        latest_comparison_year=latest_comparison_year,
        latest_notice_year=latest_notice_year,
    )


def _dataset_response(
    now: datetime,
    operations: list[dict[str, Any]],
    *,
    latest_comparison_year: str | None = None,
    latest_notice_year: str | None = None,
) -> dict[str, Any]:
    success_count = sum(1 for item in operations if item["status"] == "ok")
    total_rows = sum(item["rowCount"] for item in operations)
    status = "ok"
    if success_count == 0:
        status = "error"
    elif success_count < len(operations):
        status = "partial"

    return {
        "status": status,
        "fetchedAt": now.isoformat(),
        "cached": False,
        "cacheSeconds": int(CACHE_TTL.total_seconds()),
        "source": {
            "title": "한국대학교육협의회_대학알리미 대학 기본 정보",
            "provider": "한국대학교육협의회",
            "sourceUrl": "https://www.data.go.kr/data/15037507/openapi.do",
            "serviceBaseUrl": BASE_URL,
            "format": "XML",
        },
        "summary": {
            "operationCount": len(operations),
            "successCount": success_count,
            "errorCount": len(operations) - success_count,
            "totalRows": total_rows,
            "latestComparisonYear": latest_comparison_year,
            "latestNoticeYear": latest_notice_year,
        },
        "operations": operations,
    }


def _operation_by_endpoint(endpoint: str) -> dict[str, Any]:
    return next(item for item in OPERATION_DEFS if item["endpoint"] == endpoint)


def _fetch_operation(
    operation: dict[str, Any],
    *,
    service_key: str,
    extra_params: dict[str, str] | None = None,
) -> dict[str, Any]:
    params = dict(extra_params or {})
    try:
        result = _fetch_pages(
            endpoint=operation["endpoint"],
            service_key=service_key,
            params=params,
            paged=bool(operation.get("paged")),
        )
    except Exception as exc:  # noqa: BLE001 - remote API failures must be shown per module.
        return _operation_error(operation, params=params, result_msg=str(exc))

    safe_params = {key: value for key, value in params.items() if key != "serviceKey"}
    status = "ok" if result["resultCode"] == "00" else "error"
    return {
        **_operation_metadata(operation),
        "status": status,
        "resultCode": result["resultCode"],
        "resultMsg": result["resultMsg"],
        "totalCount": result["totalCount"],
        "rowCount": len(result["rows"]),
        "hasMore": result["hasMore"],
        "requestParams": safe_params,
        "rows": result["rows"],
        "fields": _ordered_fields(operation["responseFields"], result["rows"]),
    }


def _fetch_pages(
    *,
    endpoint: str,
    service_key: str,
    params: dict[str, str],
    paged: bool,
) -> dict[str, Any]:
    if not paged:
        first = _fetch_once(endpoint, service_key, params)
        return {
            **first,
            "hasMore": False,
        }

    first_params = {
        **params,
        "numOfRows": str(DEFAULT_PAGE_SIZE),
        "pageNo": "1",
    }
    first = _fetch_once(endpoint, service_key, first_params)
    rows = list(first["rows"])
    total_count = first["totalCount"] or len(rows)

    page = 2
    while total_count > len(rows) and page <= MAX_PAGES:
        page_result = _fetch_once(
            endpoint,
            service_key,
            {
                **params,
                "numOfRows": str(DEFAULT_PAGE_SIZE),
                "pageNo": str(page),
            },
        )
        if page_result["resultCode"] != "00":
            break
        new_rows = page_result["rows"]
        if not new_rows:
            break
        rows.extend(new_rows)
        page += 1

    return {
        "resultCode": first["resultCode"],
        "resultMsg": first["resultMsg"],
        "totalCount": total_count,
        "rows": rows,
        "hasMore": bool(total_count > len(rows)),
    }


def _fetch_once(
    endpoint: str,
    service_key: str,
    params: dict[str, str],
) -> dict[str, Any]:
    query = {
        **params,
        "serviceKey": service_key,
    }
    response = requests.get(
        f"{BASE_URL}/{endpoint}",
        params=query,
        timeout=30,
    )
    response.raise_for_status()
    return _parse_xml(response.content)


def _parse_xml(payload: bytes) -> dict[str, Any]:
    root = ET.fromstring(payload)
    result_code = _text(root.find(".//resultCode")) or ""
    result_msg = _text(root.find(".//resultMsg")) or ""
    total_count = _safe_int(_text(root.find(".//totalCount")))
    rows = []
    for item in root.findall(".//item"):
        row = {
            child.tag: _text(child)
            for child in list(item)
            if child.tag and _text(child) is not None
        }
        if row:
            rows.append(row)

    return {
        "resultCode": result_code,
        "resultMsg": result_msg,
        "totalCount": total_count,
        "rows": rows,
    }


def _operation_error(
    operation: dict[str, Any],
    *,
    result_msg: str,
    params: dict[str, str] | None = None,
) -> dict[str, Any]:
    return {
        **_operation_metadata(operation),
        "status": "error",
        "resultCode": "",
        "resultMsg": result_msg,
        "totalCount": 0,
        "rowCount": 0,
        "hasMore": False,
        "requestParams": params or {},
        "rows": [],
        "fields": list(operation["responseFields"]),
    }


def _operation_metadata(operation: dict[str, Any]) -> dict[str, Any]:
    return {
        "group": operation["group"],
        "title": operation["title"],
        "endpoint": operation["endpoint"],
        "description": operation["description"],
        "requiredParams": list(operation["requiredParams"]),
        "optionalParams": list(operation["optionalParams"]),
        "responseFields": list(operation["responseFields"]),
        "serviceUrl": f"{BASE_URL}/{operation['endpoint']}",
    }


def _latest_year(rows: list[dict[str, str]]) -> str | None:
    years = [
        row.get("yearVal", "")
        for row in rows
        if row.get("yearVal", "").isdigit()
    ]
    if not years:
        return None
    return max(years)


def _ordered_fields(
    preferred_fields: list[str],
    rows: list[dict[str, str]],
) -> list[str]:
    fields = list(preferred_fields)
    for row in rows:
        for field in row:
            if field not in fields:
                fields.append(field)
    return fields


def _text(element: ET.Element[str] | None) -> str | None:
    if element is None or element.text is None:
        return None
    return element.text.strip()


def _safe_int(value: str | None) -> int | None:
    if not value:
        return None
    try:
        return int(value)
    except ValueError:
        return None
