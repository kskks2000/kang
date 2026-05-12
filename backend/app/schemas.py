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


class DriveFilesRequest(BaseModel):
    id_token: str = Field(min_length=20)
    google_access_token: str = Field(min_length=20)
    query: Optional[str] = Field(default=None, max_length=200)
    page_size: int = Field(default=50, ge=1, le=100)


class DriveSheetFile(BaseModel):
    id: str
    name: str
    sheet_names: list[str] = Field(default_factory=list)
    modified_time: Optional[str] = None
    web_view_link: Optional[str] = None


class DriveFilesResponse(BaseModel):
    files: list[DriveSheetFile]


class DriveImportRequest(BaseModel):
    id_token: str = Field(min_length=20)
    google_access_token: str = Field(min_length=20)
    file_id: str = Field(min_length=5, max_length=300)
    file_name: str = Field(min_length=1, max_length=500)
    sheet_name: Optional[str] = Field(default=None, min_length=1, max_length=500)
    max_rows: int = Field(default=1000, ge=1, le=5000)


class DriveImportResponse(BaseModel):
    file_id: str
    file_name: str
    sheet_name: Optional[str] = None
    imported_rows: int
    sheet_count: int


class DriveRowsRequest(BaseModel):
    id_token: str = Field(min_length=20)
    search: Optional[str] = Field(default=None, max_length=200)
    limit: int = Field(default=200, ge=1, le=1000)


class GoogleDriveRow(BaseModel):
    id: str
    drivename: Optional[str] = None
    tabname: Optional[str] = None
    text01: Optional[str] = None
    text02: Optional[str] = None
    text03: Optional[str] = None
    text04: Optional[str] = None
    text05: Optional[str] = None
    text06: Optional[str] = None
    text07: Optional[str] = None
    text08: Optional[str] = None
    text09: Optional[str] = None
    text10: Optional[str] = None
    text11: Optional[str] = None
    text12: Optional[str] = None
    text13: Optional[str] = None
    text14: Optional[str] = None
    text15: Optional[str] = None
    text16: Optional[str] = None
    text17: Optional[str] = None
    text18: Optional[str] = None
    text19: Optional[str] = None
    text20: Optional[str] = None


class DriveRowsResponse(BaseModel):
    rows: list[GoogleDriveRow]
