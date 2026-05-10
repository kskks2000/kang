from __future__ import annotations

from pydantic import BaseModel, Field


class SessionRequest(BaseModel):
    id_token: str = Field(min_length=20)


class UserSession(BaseModel):
    id: str
    firebase_uid: str
    email: str | None
    display_name: str | None
    photo_url: str | None
    user_no: int | None
    user_name: str
    user_type: str
    role_code: str
    allowlist_status: str


class SessionResponse(BaseModel):
    user: UserSession


class FindLoginIdRequest(BaseModel):
    email: str = Field(min_length=3, max_length=320)


class FindLoginIdResponse(BaseModel):
    found: bool
    masked_login_id: str | None = None
    message: str
