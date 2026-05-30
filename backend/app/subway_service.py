from __future__ import annotations

from copy import deepcopy
from datetime import datetime, timedelta, timezone
import re
from typing import Any
from urllib.parse import quote

import requests

from .settings import settings


SEOUL_SUBWAY_BASE_URL = "http://swopenapi.seoul.go.kr/api/subway"
CACHE_TTL = timedelta(seconds=15)
DEFAULT_STATION = "야탑"
DEFAULT_LINE = "수인분당선"

FAVORITE_STATIONS = [
    {"station": "강남", "line": "2호선", "label": "강남"},
    {"station": "서울", "line": "1호선", "label": "서울역"},
    {"station": "시청", "line": "1호선", "label": "시청"},
    {"station": "잠실", "line": "2호선", "label": "잠실"},
    {"station": "홍대입구", "line": "2호선", "label": "홍대입구"},
    {"station": "여의도", "line": "9호선", "label": "여의도"},
]

LINE_COLORS = {
    "1호선": "#0052A4",
    "2호선": "#00A84D",
    "3호선": "#EF7C1C",
    "4호선": "#00A5DE",
    "5호선": "#996CAC",
    "6호선": "#CD7C2F",
    "7호선": "#747F00",
    "8호선": "#E6186C",
    "9호선": "#BDB092",
    "공항철도": "#0090D2",
    "신분당선": "#D4003B",
    "경의중앙선": "#77C4A3",
    "수인분당선": "#F5A200",
}

SUBWAY_ID_TO_LINE = {
    "1001": "1호선",
    "1002": "2호선",
    "1003": "3호선",
    "1004": "4호선",
    "1005": "5호선",
    "1006": "6호선",
    "1007": "7호선",
    "1008": "8호선",
    "1009": "9호선",
    "1063": "경의중앙선",
    "1065": "공항철도",
    "1075": "수인분당선",
    "1077": "신분당선",
}

ARRIVAL_STATUS = {
    "0": "진입",
    "1": "도착",
    "2": "출발",
    "3": "전역 출발",
    "4": "전역 진입",
    "5": "전역 도착",
    "99": "운행 중",
}

TRAIN_STATUS = {
    "0": "진입",
    "1": "도착",
    "2": "출발",
    "3": "전역 출발",
}

_CACHE: dict[tuple[str, str], tuple[datetime, dict[str, Any]]] = {}


def load_subway_overview(
    *,
    station: str = DEFAULT_STATION,
    line: str = DEFAULT_LINE,
) -> dict[str, Any]:
    now = datetime.now(timezone.utc)
    normalized_station = _clean_query(station) or DEFAULT_STATION
    normalized_line = _clean_query(line) or DEFAULT_LINE
    cache_key = (normalized_station, normalized_line)

    cached = _CACHE.get(cache_key)
    if cached and cached[0] > now:
        payload = deepcopy(cached[1])
        payload["cached"] = True
        return payload

    errors: list[str] = []
    arrivals: list[dict[str, Any]] = []
    trains: list[dict[str, Any]] = []

    try:
        arrivals = _fetch_arrivals(normalized_station)
    except Exception as exc:  # noqa: BLE001 - external source errors are surfaced.
        errors.append(f"도착정보: {exc}")

    try:
        trains = _fetch_train_positions(normalized_line)
    except Exception as exc:  # noqa: BLE001
        errors.append(f"열차위치: {exc}")

    payload = _dataset_response(
        now,
        station=normalized_station,
        line=normalized_line,
        arrivals=arrivals,
        trains=trains,
        errors=errors,
    )
    _CACHE[cache_key] = (now + CACHE_TTL, deepcopy(payload))
    return payload


def _fetch_arrivals(station: str) -> list[dict[str, Any]]:
    payload = _seoul_subway_get("realtimeStationArrival", station, row_end=12)
    rows = payload.get("realtimeArrivalList") or []
    if not isinstance(rows, list):
        raise ValueError("invalid arrival response")

    return [_normalize_arrival(row) for row in rows if isinstance(row, dict)]


def _fetch_train_positions(line: str) -> list[dict[str, Any]]:
    payload = _seoul_subway_get("realtimePosition", line, row_end=5)
    rows = payload.get("realtimePositionList") or []
    if not isinstance(rows, list):
        raise ValueError("invalid train position response")

    return [_normalize_train(row) for row in rows if isinstance(row, dict)]


def _seoul_subway_get(service: str, query: str, *, row_end: int) -> dict[str, Any]:
    key = settings.seoul_subway_api_key or "sample"
    if key == "sample":
        row_end = min(row_end, 5)
    url = (
        f"{SEOUL_SUBWAY_BASE_URL}/{quote(key, safe='')}/json/{service}/1/{row_end}/"
        f"{quote(query, safe='')}"
    )
    response = requests.get(
        url,
        headers={"User-Agent": "KangPrivateHub/1.0 (+https://kang.ai.kr)"},
        timeout=20,
    )
    response.raise_for_status()
    payload = response.json()
    if not isinstance(payload, dict):
        raise ValueError("invalid Seoul subway response")

    result = payload.get("errorMessage") or payload
    code = str(result.get("code") or "")
    if code == "INFO-000":
        return payload
    if code == "INFO-200":
        return payload

    message = str(result.get("message") or "Seoul subway API error")
    raise ValueError(message)


def _normalize_arrival(row: dict[str, Any]) -> dict[str, Any]:
    subway_id = _safe_text(row.get("subwayId"))
    line = SUBWAY_ID_TO_LINE.get(subway_id, _safe_text(row.get("subwayList")))
    eta_seconds = _arrival_eta_seconds(row)
    return {
        "line": line,
        "lineColor": LINE_COLORS.get(line, "#5B3FA3"),
        "station": _safe_text(row.get("statnNm")),
        "direction": _safe_text(row.get("updnLine")),
        "destination": _safe_text(row.get("bstatnNm")),
        "trainLine": _safe_text(row.get("trainLineNm")),
        "arrivalMessage": _safe_text(row.get("arvlMsg2")),
        "arrivalDetail": _safe_text(row.get("arvlMsg3")),
        "etaSeconds": eta_seconds,
        "status": ARRIVAL_STATUS.get(_safe_text(row.get("arvlCd")), "운행 중"),
        "trainNo": _safe_text(row.get("btrainNo")),
        "receivedAt": _safe_text(row.get("recptnDt")),
        "terminalStation": _safe_text(row.get("bstatnNm")),
    }


def _arrival_eta_seconds(row: dict[str, Any]) -> int | None:
    eta_seconds = _safe_int(row.get("barvlDt"))
    if eta_seconds is not None and eta_seconds > 0:
        return eta_seconds

    message = _safe_text(row.get("arvlMsg2"))
    detail = _safe_text(row.get("arvlMsg3"))
    status_code = _safe_text(row.get("arvlCd"))

    minute_match = re.search(r"(\d+)\s*분(?:\s*(\d+)\s*초)?", message)
    if minute_match:
        minutes = int(minute_match.group(1))
        seconds = int(minute_match.group(2) or 0)
        return minutes * 60 + seconds

    seconds_match = re.search(r"(\d+)\s*초", message)
    if seconds_match:
        return int(seconds_match.group(1))

    station_count_match = re.search(r"\[(\d+)\]\s*번째\s*전역", message)
    if station_count_match:
        station_count = int(station_count_match.group(1))
        return max(station_count * 120, 60)

    if status_code == "1" or "도착" in message or "도착" in detail:
        return 0
    if status_code == "0" or "진입" in message:
        return 30
    if status_code == "2" or "출발" in message:
        return 90

    return eta_seconds


def _normalize_train(row: dict[str, Any]) -> dict[str, Any]:
    line = _safe_text(row.get("subwayNm"))
    return {
        "line": line,
        "lineColor": LINE_COLORS.get(line, "#5B3FA3"),
        "station": _safe_text(row.get("statnNm")),
        "trainNo": _safe_text(row.get("trainNo")),
        "destination": _safe_text(row.get("statnTnm")),
        "status": TRAIN_STATUS.get(_safe_text(row.get("trainSttus")), "운행 중"),
        "directionCode": _safe_text(row.get("updnLine")),
        "isExpress": _safe_text(row.get("directAt")) == "1",
        "isLastTrain": _safe_text(row.get("lstcarAt")) == "1",
        "receivedAt": _safe_text(row.get("recptnDt")),
    }


def _dataset_response(
    now: datetime,
    *,
    station: str,
    line: str,
    arrivals: list[dict[str, Any]],
    trains: list[dict[str, Any]],
    errors: list[str],
) -> dict[str, Any]:
    status = "ok" if not errors else "partial" if arrivals or trains else "error"
    key_mode = "sample" if settings.seoul_subway_api_key == "sample" else "configured"
    return {
        "status": status,
        "fetchedAt": now.isoformat(),
        "cached": False,
        "cacheSeconds": int(CACHE_TTL.total_seconds()),
        "source": {
            "title": "서울시 지하철 실시간 운행정보",
            "provider": "서울 열린데이터광장 TOPIS",
            "arrivalUrl": "http://swopenapi.seoul.go.kr/api/subway/(KEY)/json/realtimeStationArrival/1/12/(역명)",
            "positionUrl": "http://swopenapi.seoul.go.kr/api/subway/(KEY)/json/realtimePosition/1/5/(호선)",
            "description": "서울시 실시간 지하철 도착정보와 열차 위치정보를 FastAPI에서 15초 캐시로 중계합니다.",
        },
        "summary": {
            "station": station,
            "line": line,
            "lineColor": LINE_COLORS.get(line, "#5B3FA3"),
            "arrivalCount": len(arrivals),
            "trainCount": len(trains),
            "keyMode": key_mode,
            "favoriteStations": FAVORITE_STATIONS,
        },
        "arrivals": arrivals,
        "trains": trains,
        "errors": errors,
    }


def _clean_query(value: str) -> str:
    return str(value or "").strip().replace("역", "")


def _safe_text(value: Any) -> str:
    if value is None:
        return ""
    return str(value).strip()


def _safe_int(value: Any) -> int | None:
    try:
        return int(value)
    except (TypeError, ValueError):
        return None
