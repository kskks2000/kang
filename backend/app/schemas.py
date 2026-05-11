from __future__ import annotations

from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field


class SessionRequest(BaseModel):
    id_token: str = Field(min_length=20)


class UserSession(BaseModel):
    id: str
    firebase_uid: str
    email: Optional[str]
    display_name: Optional[str]
    photo_url: Optional[str]
    user_no: Optional[int]
    user_name: str
    user_type: str
    role_code: str


class SessionResponse(BaseModel):
    user: UserSession


class FindLoginIdRequest(BaseModel):
    email: str = Field(min_length=3, max_length=320)


class FindLoginIdResponse(BaseModel):
    found: bool
    masked_login_id: Optional[str] = None
    message: str


class CalendarEventsRequest(BaseModel):
    id_token: str = Field(min_length=20)
    google_access_token: str = Field(min_length=20)
    time_min: datetime
    time_max: datetime
    max_results: int = Field(default=50, ge=1, le=100)


class CalendarEvent(BaseModel):
    id: str
    title: str
    start: Optional[str] = None
    end: Optional[str] = None
    location: Optional[str] = None
    all_day: bool = False


class CalendarEventsResponse(BaseModel):
    events: list[CalendarEvent]
