# Kang API

FastAPI backend for Firebase-authenticated user login.

## Run locally

The API reads the repository root `.env` first and then `backend/.env` for backend-specific overrides. PostgreSQL is restricted to `211.47.74.33/dbkang` as user `kang`, so a wrong `DATABASE_URL` or `POSTGRES_DB` will stop startup instead of connecting elsewhere.

```powershell
cd D:\kcastle\kang\backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

Use `.env.example` in the repository root for the full environment variable list. `backend/.env.example` contains the backend-only subset.

The Flutter app sends a Firebase ID token to `POST /auth/session`.
The API verifies the token and creates or updates the matching user records in `kang.users`.
