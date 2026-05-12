from __future__ import annotations

from typing import Any

import requests
from fastapi import HTTPException, status
from psycopg import Connection
from psycopg.rows import dict_row


DRIVE_FILES_URL = "https://www.googleapis.com/drive/v3/files"
SHEETS_SPREADSHEET_URL = "https://sheets.googleapis.com/v4/spreadsheets/{file_id}"
SHEETS_VALUES_BATCH_URL = (
    "https://sheets.googleapis.com/v4/spreadsheets/{file_id}/values:batchGet"
)
GOOGLE_SHEETS_MIME_TYPE = "application/vnd.google-apps.spreadsheet"
TEXT_COLUMNS = [f"text{i:02d}" for i in range(1, 21)]


def user_id_from_claims(conn: Connection, claims: dict[str, Any]) -> str:
    firebase_uid = str(claims.get("uid") or claims.get("sub") or "").strip()
    email = str(claims.get("email") or "").strip().lower()

    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(
            """
            SELECT id
            FROM kang.users
            WHERE firebase_uid = %s
               OR (lower(email) = lower(%s) AND deleted_at IS NULL)
            ORDER BY CASE WHEN firebase_uid = %s THEN 0 ELSE 1 END
            LIMIT 1
            """,
            (firebase_uid, email, firebase_uid),
        )
        user = cur.fetchone()

    if user is None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="로그인 사용자 정보를 찾을 수 없습니다. 다시 로그인해 주세요.",
        )

    return str(user["id"])


def list_google_sheet_files(
    *,
    access_token: str,
    query: str | None,
    page_size: int,
) -> list[dict[str, Any]]:
    search_parts = [
        f"mimeType='{GOOGLE_SHEETS_MIME_TYPE}'",
        "trashed=false",
    ]
    if query:
        escaped_query = query.replace("\\", "\\\\").replace("'", "\\'")
        search_parts.append(f"name contains '{escaped_query}'")

    response = requests.get(
        DRIVE_FILES_URL,
        params={
            "q": " and ".join(search_parts),
            "pageSize": str(page_size),
            "orderBy": "modifiedTime desc",
            "fields": "files(id,name,modifiedTime,webViewLink)",
            "includeItemsFromAllDrives": "true",
            "supportsAllDrives": "true",
        },
        headers=_auth_headers(access_token),
        timeout=20,
    )
    _raise_for_google_error(response, service_name="Google Drive")

    payload = response.json()
    files = payload.get("files")
    if not isinstance(files, list):
        return []

    sheet_files: list[dict[str, Any]] = []
    for item in files:
        if not isinstance(item, dict) or not item.get("id"):
            continue

        file_id = str(item.get("id") or "")
        sheet_files.append(
            {
                "id": file_id,
                "name": str(item.get("name") or "Untitled sheet"),
                "sheet_names": _safe_load_sheet_titles(
                    access_token=access_token,
                    file_id=file_id,
                ),
                "modified_time": item.get("modifiedTime"),
                "web_view_link": item.get("webViewLink"),
            }
        )

    return sheet_files


def import_google_sheet(
    conn: Connection,
    *,
    user_id: str,
    access_token: str,
    file_id: str,
    file_name: str,
    sheet_name: str | None,
    max_rows: int,
) -> dict[str, Any]:
    sheets = _load_sheet_titles(access_token=access_token, file_id=file_id)
    if not sheets:
        return {
            "file_id": file_id,
            "file_name": file_name,
            "sheet_name": sheet_name,
            "imported_rows": 0,
            "sheet_count": 0,
        }

    selected_sheet = sheet_name.strip() if sheet_name else None
    if selected_sheet:
        matching_sheet = next((sheet for sheet in sheets if sheet == selected_sheet), None)
        if matching_sheet is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="선택한 Google Sheet 탭을 찾지 못했습니다.",
            )
        sheets_to_import = [matching_sheet]
    else:
        sheets_to_import = sheets

    values_by_sheet = _load_sheet_values(
        access_token=access_token,
        file_id=file_id,
        sheets=sheets_to_import,
        max_rows=max_rows,
    )
    rows: list[tuple[Any, ...]] = []
    for sheet_name, values in values_by_sheet.items():
        for value_row in values:
            normalized = [_cell_to_text(cell) for cell in value_row[:20]]
            normalized += [None] * (20 - len(normalized))
            if not any(value for value in normalized):
                continue
            rows.append((user_id, file_name, sheet_name, *normalized))

    with conn.cursor() as cur:
        if selected_sheet:
            cur.execute(
                """
                DELETE FROM kang.google_drives
                WHERE user_id = %s
                  AND drivename = %s
                  AND tabname = %s
                """,
                (user_id, file_name, selected_sheet),
            )
        else:
            cur.execute(
                """
                DELETE FROM kang.google_drives
                WHERE user_id = %s
                  AND drivename = %s
                """,
                (user_id, file_name),
            )
        if rows:
            columns = ["user_id", "drivename", "tabname", *TEXT_COLUMNS]
            placeholders = ", ".join(["%s"] * len(columns))
            cur.executemany(
                f"""
                INSERT INTO kang.google_drives ({", ".join(columns)})
                VALUES ({placeholders})
                """,
                rows,
            )

    return {
        "file_id": file_id,
        "file_name": file_name,
        "sheet_name": selected_sheet,
        "imported_rows": len(rows),
        "sheet_count": len(sheets_to_import),
    }


def list_google_drive_rows(
    conn: Connection,
    *,
    user_id: str,
    search: str | None,
    limit: int,
) -> list[dict[str, Any]]:
    where = ["user_id = %s"]
    params: list[Any] = [user_id]

    if search:
        like = f"%{search.strip()}%"
        searchable_columns = ["drivename", "tabname", *TEXT_COLUMNS]
        where.append(
            "("
            + " OR ".join(f"COALESCE({column}, '') ILIKE %s" for column in searchable_columns)
            + ")"
        )
        params.extend([like] * len(searchable_columns))

    params.append(limit)

    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(
            f"""
            SELECT id::text, drivename, tabname, {", ".join(TEXT_COLUMNS)}
            FROM kang.google_drives
            WHERE {" AND ".join(where)}
            ORDER BY drivename ASC, tabname ASC, id ASC
            LIMIT %s
            """,
            params,
        )
        return [dict(row) for row in cur.fetchall()]


def _load_sheet_titles(*, access_token: str, file_id: str) -> list[str]:
    response = requests.get(
        SHEETS_SPREADSHEET_URL.format(file_id=file_id),
        params={"fields": "sheets.properties.title"},
        headers=_auth_headers(access_token),
        timeout=20,
    )
    _raise_for_google_error(response, service_name="Google Sheets")

    payload = response.json()
    sheets = payload.get("sheets")
    if not isinstance(sheets, list):
        return []

    titles: list[str] = []
    for sheet in sheets:
        if not isinstance(sheet, dict):
            continue
        properties = sheet.get("properties")
        if not isinstance(properties, dict):
            continue
        title = str(properties.get("title") or "").strip()
        if title:
            titles.append(title)
    return titles


def _safe_load_sheet_titles(*, access_token: str, file_id: str) -> list[str]:
    try:
        return _load_sheet_titles(access_token=access_token, file_id=file_id)
    except HTTPException:
        return []


def _load_sheet_values(
    *,
    access_token: str,
    file_id: str,
    sheets: list[str],
    max_rows: int,
) -> dict[str, list[list[Any]]]:
    ranges = [f"{_quote_sheet_name(sheet)}!A1:T{max_rows}" for sheet in sheets]
    params: list[tuple[str, str]] = [
        ("majorDimension", "ROWS"),
        ("valueRenderOption", "FORMATTED_VALUE"),
    ]
    params.extend(("ranges", range_value) for range_value in ranges)

    response = requests.get(
        SHEETS_VALUES_BATCH_URL.format(file_id=file_id),
        params=params,
        headers=_auth_headers(access_token),
        timeout=30,
    )
    _raise_for_google_error(response, service_name="Google Sheets")

    payload = response.json()
    value_ranges = payload.get("valueRanges")
    if not isinstance(value_ranges, list):
        return {}

    values_by_sheet: dict[str, list[list[Any]]] = {}
    for sheet, value_range in zip(sheets, value_ranges):
        if not isinstance(value_range, dict):
            values_by_sheet[sheet] = []
            continue
        values = value_range.get("values")
        values_by_sheet[sheet] = values if isinstance(values, list) else []
    return values_by_sheet


def _quote_sheet_name(sheet_name: str) -> str:
    return "'" + sheet_name.replace("'", "''") + "'"


def _cell_to_text(value: Any) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    return text or None


def _auth_headers(access_token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {access_token}"}


def _raise_for_google_error(response: requests.Response, *, service_name: str) -> None:
    if 200 <= response.status_code < 300:
        return

    detail = f"{service_name} 데이터를 가져오지 못했습니다."
    try:
        payload = response.json()
        error = payload.get("error") if isinstance(payload, dict) else None
        if isinstance(error, dict) and error.get("message"):
            detail = f"{detail} {error['message']}"
    except ValueError:
        pass

    if response.status_code in (401, 403):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=detail)

    raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=detail)
