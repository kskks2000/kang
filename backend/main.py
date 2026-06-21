from __future__ import annotations

from firebase_fastapi_wrapper import FastAPIWrapper
from firebase_functions import https_fn, options

from app.main import app
from app.settings import settings


_handler = FastAPIWrapper(
    app,
    cors_origins=settings.cors_allowed_origins,
    timeout=300,
)


@https_fn.on_request(
    region="asia-northeast3",
    timeout_sec=300,
    memory=options.MemoryOption.MB_1GB,
)
def api(req: https_fn.Request) -> https_fn.Response:
    return _handler(req)
