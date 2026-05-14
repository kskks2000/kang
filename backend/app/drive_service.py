from __future__ import annotations

from dataclasses import dataclass
import time
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
SHEET_VALUE_ROW_CHUNK_SIZE = 5000
MAX_SHEET_ROWS_TO_IMPORT = 100000
GOOGLE_GET_RETRY_COUNT = 3
GOOGLE_TRANSIENT_STATUS_CODES = {429, 500, 502, 503, 504}


@dataclass(frozen=True)
class SheetInfo:
    title: str
    row_count: int | None = None


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
            "orderBy": "name_natural",
            "fields": "files(id,name,parents,modifiedTime,webViewLink)",
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

    parent_ids = {
        parent_id
        for item in files
        if isinstance(item, dict)
        for parent_id in [_first_parent_id(item)]
        if parent_id
    }
    folder_names = _load_drive_file_names(access_token=access_token, file_ids=parent_ids)

    sheet_files: list[dict[str, Any]] = []
    for item in files:
        if not isinstance(item, dict) or not item.get("id"):
            continue

        file_id = str(item.get("id") or "")
        parent_id = _first_parent_id(item)
        sheet_files.append(
            {
                "id": file_id,
                "name": str(item.get("name") or "Untitled sheet"),
                "folder_name": folder_names.get(parent_id) if parent_id else None,
                "sheet_names": _safe_load_sheet_titles(
                    access_token=access_token,
                    file_id=file_id,
                ),
                "modified_time": item.get("modifiedTime"),
                "web_view_link": item.get("webViewLink"),
            }
        )

    sheet_files.sort(
        key=lambda item: (
            _sort_text(item.get("folder_name")),
            _sort_text(item.get("name")),
            str(item.get("id") or ""),
        )
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
    try:
        sheet_infos = _load_sheet_infos(access_token=access_token, file_id=file_id)
    except requests.RequestException:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Google Sheets 정보를 불러오는 중 네트워크 시간이 초과되었습니다. 다시 시도해 주세요.",
        )
    sheets = [sheet.title for sheet in sheet_infos]
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

    row_counts_by_sheet = {
        sheet.title: sheet.row_count
        for sheet in sheet_infos
        if sheet.title in sheets_to_import
    }
    try:
        values_by_sheet = _load_sheet_values(
            access_token=access_token,
            file_id=file_id,
            sheets=sheets_to_import,
            row_counts_by_sheet=row_counts_by_sheet,
            max_rows=max_rows,
        )
    except requests.RequestException:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Google Sheets 행 데이터를 불러오는 중 네트워크 시간이 초과되었습니다. 다시 시도해 주세요.",
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
        if rows:
            _upsert_google_drive_rows(cur, rows)

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
            ORDER BY
                btrim(drivename) ASC NULLS LAST,
                btrim(tabname) ASC NULLS LAST,
                CASE
                    WHEN btrim(text01) = '순번' THEN 0
                    ELSE 1
                END ASC,
                CASE
                    WHEN replace(btrim(text01), ',', '') ~ '^[+-]?([0-9]+([.][0-9]+)?|[.][0-9]+)$'
                    THEN replace(btrim(text01), ',', '')::numeric
                END ASC NULLS LAST,
                btrim(text01) ASC NULLS LAST,
                id ASC
            LIMIT %s
            """,
            params,
        )
        return [dict(row) for row in cur.fetchall()]


def _load_sheet_infos(*, access_token: str, file_id: str) -> list[SheetInfo]:
    response = _google_get(
        SHEETS_SPREADSHEET_URL.format(file_id=file_id),
        params={"fields": "sheets.properties(title,gridProperties.rowCount)"},
        headers=_auth_headers(access_token),
        timeout=20,
    )
    _raise_for_google_error(response, service_name="Google Sheets")

    payload = response.json()
    sheets = payload.get("sheets")
    if not isinstance(sheets, list):
        return []

    sheet_infos: list[SheetInfo] = []
    for sheet in sheets:
        if not isinstance(sheet, dict):
            continue
        properties = sheet.get("properties")
        if not isinstance(properties, dict):
            continue
        title = str(properties.get("title") or "").strip()
        if title:
            grid_properties = properties.get("gridProperties")
            row_count = None
            if isinstance(grid_properties, dict):
                raw_row_count = grid_properties.get("rowCount")
                row_count = raw_row_count if isinstance(raw_row_count, int) else None
            sheet_infos.append(SheetInfo(title=title, row_count=row_count))
    return sheet_infos


def _load_sheet_titles(*, access_token: str, file_id: str) -> list[str]:
    return [
        sheet.title
        for sheet in _load_sheet_infos(access_token=access_token, file_id=file_id)
    ]


def _safe_load_sheet_titles(*, access_token: str, file_id: str) -> list[str]:
    try:
        return _load_sheet_titles(access_token=access_token, file_id=file_id)
    except (HTTPException, requests.RequestException):
        return []


def _first_parent_id(item: dict[str, Any]) -> str | None:
    parents = item.get("parents")
    if not isinstance(parents, list) or not parents:
        return None
    parent_id = str(parents[0] or "").strip()
    return parent_id or None


def _load_drive_file_names(
    *,
    access_token: str,
    file_ids: set[str],
) -> dict[str, str]:
    names: dict[str, str] = {}
    for file_id in sorted(file_ids):
        folder_name = _safe_load_drive_file_name(
            access_token=access_token,
            file_id=file_id,
        )
        if folder_name:
            names[file_id] = folder_name
    return names


def _safe_load_drive_file_name(*, access_token: str, file_id: str) -> str | None:
    try:
        response = requests.get(
            f"{DRIVE_FILES_URL}/{file_id}",
            params={"fields": "id,name", "supportsAllDrives": "true"},
            headers=_auth_headers(access_token),
            timeout=20,
        )
        _raise_for_google_error(response, service_name="Google Drive")
        payload = response.json()
        if not isinstance(payload, dict):
            return None
        name = str(payload.get("name") or "").strip()
        return name or None
    except (HTTPException, requests.RequestException):
        return None


def _sort_text(value: Any) -> tuple[int, str]:
    text = str(value or "").strip().casefold()
    return (0, text) if text else (1, "")


def _load_sheet_values(
    *,
    access_token: str,
    file_id: str,
    sheets: list[str],
    row_counts_by_sheet: dict[str, int | None],
    max_rows: int,
) -> dict[str, list[list[Any]]]:
    values_by_sheet: dict[str, list[list[Any]]] = {sheet: [] for sheet in sheets}
    for sheet in sheets:
        try:
            values = _load_sheet_value_range(
                access_token=access_token,
                file_id=file_id,
                range_value=f"{_quote_sheet_name(sheet)}!A:T",
                timeout=25,
                retry_count=1,
            )
        except requests.Timeout:
            fallback_max_rows = row_counts_by_sheet.get(sheet) or max_rows
            values = _load_sheet_values_chunked(
                access_token=access_token,
                file_id=file_id,
                sheet=sheet,
                max_rows=fallback_max_rows,
            )
        if max_rows > 0:
            values = values[:max_rows]
        values_by_sheet[sheet] = values

    return values_by_sheet


def _load_sheet_values_chunked(
    *,
    access_token: str,
    file_id: str,
    sheet: str,
    max_rows: int,
) -> list[list[Any]]:
    rows: list[list[Any]] = []
    rows_to_load = min(max_rows, MAX_SHEET_ROWS_TO_IMPORT)
    for start_row in range(1, rows_to_load + 1, SHEET_VALUE_ROW_CHUNK_SIZE):
        end_row = min(start_row + SHEET_VALUE_ROW_CHUNK_SIZE - 1, rows_to_load)
        range_value = f"{_quote_sheet_name(sheet)}!A{start_row}:T{end_row}"
        rows.extend(
            _load_sheet_value_range(
                access_token=access_token,
                file_id=file_id,
                range_value=range_value,
            )
        )
        if rows and len(rows) < end_row:
            break

    return rows


def _load_sheet_value_range(
    *,
    access_token: str,
    file_id: str,
    range_value: str,
    timeout: int = 90,
    retry_count: int = GOOGLE_GET_RETRY_COUNT,
) -> list[list[Any]]:
    params: list[tuple[str, str]] = [
        ("majorDimension", "ROWS"),
        ("valueRenderOption", "FORMATTED_VALUE"),
        ("ranges", range_value),
    ]

    response = _google_get(
        SHEETS_VALUES_BATCH_URL.format(file_id=file_id),
        params=params,
        headers=_auth_headers(access_token),
        timeout=timeout,
        retry_count=retry_count,
    )
    _raise_for_google_error(response, service_name="Google Sheets")

    payload = response.json()
    value_ranges = payload.get("valueRanges")
    if not isinstance(value_ranges, list):
        return []

    value_range = value_ranges[0] if value_ranges else None
    if not isinstance(value_range, dict):
        return []
    values = value_range.get("values")
    return values if isinstance(values, list) else []


def _upsert_google_drive_rows(cur: Any, rows: list[tuple[Any, ...]]) -> None:
    columns = ["user_id", "drivename", "tabname", *TEXT_COLUMNS]
    column_defs = ", ".join(
        "user_id uuid" if column == "user_id" else f"{column} text"
        for column in columns
    )
    placeholders = ", ".join(["%s"] * len(columns))

    cur.execute(
        f"""
        CREATE TEMP TABLE tmp_google_drive_import (
            {column_defs}
        ) ON COMMIT DROP
        """
    )
    cur.executemany(
        f"""
        INSERT INTO tmp_google_drive_import ({", ".join(columns)})
        VALUES ({placeholders})
        """,
        rows,
    )
    cur.execute(
        f"""
        CREATE TEMP TABLE tmp_google_drive_import_keyed ON COMMIT DROP AS
        SELECT DISTINCT ON (
            user_id,
            btrim(COALESCE(drivename, '')),
            btrim(COALESCE(tabname, '')),
            btrim(COALESCE(text01, ''))
        )
            {", ".join(columns)}
        FROM tmp_google_drive_import
        WHERE btrim(COALESCE(text01, '')) <> ''
        ORDER BY
            user_id,
            btrim(COALESCE(drivename, '')),
            btrim(COALESCE(tabname, '')),
            btrim(COALESCE(text01, '')),
            ctid DESC
        """
    )

    _delete_duplicate_google_drive_keys(cur)
    set_clause = ", ".join(f"{column} = source.{column}" for column in columns[1:])
    cur.execute(
        f"""
        UPDATE kang.google_drives AS target
        SET {set_clause}
        FROM tmp_google_drive_import_keyed AS source
        WHERE target.user_id = source.user_id
          AND btrim(COALESCE(target.drivename, '')) = btrim(COALESCE(source.drivename, ''))
          AND btrim(COALESCE(target.tabname, '')) = btrim(COALESCE(source.tabname, ''))
          AND btrim(COALESCE(target.text01, '')) = btrim(COALESCE(source.text01, ''))
          AND btrim(COALESCE(target.text01, '')) <> ''
        """
    )

    cur.execute(
        f"""
        INSERT INTO kang.google_drives ({", ".join(columns)})
        SELECT {", ".join(f"source.{column}" for column in columns)}
        FROM tmp_google_drive_import_keyed AS source
        WHERE NOT EXISTS (
            SELECT 1
            FROM kang.google_drives AS target
            WHERE target.user_id = source.user_id
              AND btrim(COALESCE(target.drivename, '')) = btrim(COALESCE(source.drivename, ''))
              AND btrim(COALESCE(target.tabname, '')) = btrim(COALESCE(source.tabname, ''))
              AND btrim(COALESCE(target.text01, '')) = btrim(COALESCE(source.text01, ''))
              AND btrim(COALESCE(target.text01, '')) <> ''
        )
        """
    )

    cur.execute(
        f"""
        INSERT INTO kang.google_drives ({", ".join(columns)})
        SELECT {", ".join(columns)}
        FROM tmp_google_drive_import
        WHERE btrim(COALESCE(text01, '')) = ''
        """
    )


def _delete_duplicate_google_drive_keys(cur: Any) -> None:
    cur.execute(
        """
        WITH matching_keys AS (
            SELECT DISTINCT
                user_id,
                btrim(COALESCE(drivename, '')) AS drive_key,
                btrim(COALESCE(tabname, '')) AS sheet_key,
                btrim(COALESCE(text01, '')) AS sequence_key
            FROM tmp_google_drive_import_keyed
        ),
        ranked AS (
            SELECT
                target.ctid,
                row_number() OVER (
                    PARTITION BY
                        target.user_id,
                        btrim(COALESCE(target.drivename, '')),
                        btrim(COALESCE(target.tabname, '')),
                        btrim(COALESCE(target.text01, ''))
                    ORDER BY target.id
                ) AS row_number
            FROM kang.google_drives AS target
            INNER JOIN matching_keys AS keys
                ON target.user_id = keys.user_id
               AND btrim(COALESCE(target.drivename, '')) = keys.drive_key
               AND btrim(COALESCE(target.tabname, '')) = keys.sheet_key
               AND btrim(COALESCE(target.text01, '')) = keys.sequence_key
            WHERE btrim(COALESCE(target.text01, '')) <> ''
        )
        DELETE FROM kang.google_drives AS target
        USING ranked
        WHERE target.ctid = ranked.ctid
          AND ranked.row_number > 1
        """
    )


def _quote_sheet_name(sheet_name: str) -> str:
    return "'" + sheet_name.replace("'", "''") + "'"


def _cell_to_text(value: Any) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    return text or None


def _auth_headers(access_token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {access_token}"}


def _google_get(
    url: str,
    *,
    params: Any,
    headers: dict[str, str],
    timeout: int,
    retry_count: int = GOOGLE_GET_RETRY_COUNT,
) -> requests.Response:
    last_response: requests.Response | None = None
    for attempt in range(retry_count):
        try:
            response = requests.get(
                url,
                params=params,
                headers=headers,
                timeout=timeout,
            )
        except requests.Timeout:
            if attempt == retry_count - 1:
                raise
            time.sleep(1.5 * (attempt + 1))
            continue

        if response.status_code not in GOOGLE_TRANSIENT_STATUS_CODES:
            return response
        last_response = response
        if attempt < retry_count - 1:
            time.sleep(1.5 * (attempt + 1))

    if last_response is None:
        raise requests.Timeout("Google API request timed out.")
    return last_response


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
