from __future__ import annotations

from contextlib import contextmanager
from collections.abc import Iterator

import psycopg

from .settings import settings


@contextmanager
def get_db() -> Iterator[psycopg.Connection]:
    conn = psycopg.connect(settings.database_url)
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()
