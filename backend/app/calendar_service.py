from __future__ import annotations

from datetime import datetime
from datetime import timezone
from typing import Any

import requests
from fastapi import HTTPException, status


GOOGLE_CALENDAR_EVENTS_URL = (
    "https://www.googleapis.com/calendar/v3/calendars/primary/events"
)


def load_calendar_events(
    *,
    access_token: str,
    time_min: datetime,
    time_max: datetime,
    max_results: int,
) -> list[dict[str, Any]]:
    response = requests.get(
        GOOGLE_CALENDAR_EVENTS_URL,
        params={
            "maxResults": str(max_results),
            "orderBy": "startTime",
            "singleEvents": "true",
            "timeMin": _to_google_datetime(time_min),
            "timeMax": _to_google_datetime(time_max),
        },
        headers={"Authorization": f"Bearer {access_token}"},
        timeout=15,
    )

    if response.status_code in (401, 403):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Google Calendar 권한이 만료되었거나 허용되지 않았습니다.",
        )

    if response.status_code < 200 or response.status_code >= 300:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Google Calendar 일정을 불러오지 못했습니다.",
        )

    payload = response.json()
    items = payload.get("items")
    if not isinstance(items, list):
        return []

    return [_event_from_item(item) for item in items if isinstance(item, dict)]


def _to_google_datetime(value: datetime) -> str:
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def _event_from_item(item: dict[str, Any]) -> dict[str, Any]:
    start = item.get("start") if isinstance(item.get("start"), dict) else {}
    end = item.get("end") if isinstance(item.get("end"), dict) else {}
    title = str(item.get("summary") or "").strip() or "Untitled event"
    location = str(item.get("location") or "").strip() or None

    return {
        "id": str(item.get("id") or ""),
        "title": title,
        "start": _event_time(start),
        "end": _event_time(end),
        "location": location,
        "all_day": bool(start.get("date")),
    }


def _event_time(value: dict[str, Any]) -> str | None:
    raw_value = value.get("dateTime") or value.get("date")
    if raw_value is None:
        return None
    return str(raw_value)
