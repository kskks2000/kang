# Kang

Flutter + FastAPI + PostgreSQL foundation for the Kang private app.

## Created parts

- `frontend/`: Flutter app with login, sign-up, ID lookup, password reset, and signed-in home screen.
- `backend/`: FastAPI server that verifies Firebase ID tokens and creates or updates users.
- `database/login_auth_schema.sql`: Login/auth schema DDL.
- `database/seed_default_roles.sql`: Default role seed SQL.

## Backend

The backend loads local environment values from `backend/.env`. DB settings are locked to `211.47.74.33/dbkang` as user `kang`; if another DB is configured through the environment, the API refuses to start.

```powershell
cd D:\kcastle\kang\backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt

$env:GOOGLE_APPLICATION_CREDENTIALS="<firebase service account json path>"

uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

## Android Studio

Open this folder in Android Studio:

```text
D:\kcastle\kang\frontend
```

Use `lib/main.dart` as the entrypoint. The Android emulator uses this API value by default:

```text
http://10.0.2.2:8000
```

`10.0.2.2` is the Android emulator address for your PC's local backend. Use `--dart-define=API_BASE_URL=...` only when you run against another backend host. Chrome and desktop default to `http://localhost:8000`.

Firebase client defaults are already set in `frontend/lib/firebase_options.dart` for project `kang-84cdd`.

## Flutter web

```powershell
cd D:\kcastle\kang\frontend
C:\src\flutter\bin\flutter.bat run -d chrome `
  --dart-define=API_BASE_URL=http://localhost:8000
```

## User Login

Users can sign up with email and password in the Flutter app. After Firebase authentication succeeds, the backend creates or updates the user in:

```text
kang.users
kang.auth_identities
kang.user_profiles
kang.user_roles
kang.login_events
```
