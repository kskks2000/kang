from __future__ import annotations

from firebase_fastapi_wrapper import FastAPIWrapper
from firebase_functions import https_fn, options

from app.main import app


_handler = FastAPIWrapper(
    app,
    cors_origins=[
        "https://kang-84cdd.web.app",
        "https://kang-84cdd.firebaseapp.com",
        "https://www.kang.ai.kr",
        "https://kang.ai.kr",
        "http://localhost:5000",
        "http://localhost:5004",
        "http://127.0.0.1:5000",
        "http://127.0.0.1:5004",
    ],
    timeout=60,
)


@https_fn.on_request(
    region="asia-northeast3",
    timeout_sec=60,
    memory=options.MemoryOption.MB_512,
)
def api(req: https_fn.Request) -> https_fn.Response:
    return _handler(req)
