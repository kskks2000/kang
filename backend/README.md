# Kang API

FastAPI backend for Firebase-authenticated family-only login.

## Run locally

```powershell
cd D:\kcastle\kang\backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
$env:POSTGRES_PASSWORD="<db password>"
$env:FIREBASE_PROJECT_ID="<firebase project id>"
$env:GOOGLE_APPLICATION_CREDENTIALS="<service-account-json-path>"
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

The Flutter app sends a Firebase ID token to `POST /auth/session`.
The API verifies the token, checks `metaserver.family_login_allowlist`, and creates or updates the matching user records.
