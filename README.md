# Kang

Flutter + FastAPI + PostgreSQL foundation for the Kang private app.

## Created parts

- `frontend/`: Flutter app with login, sign-up, ID lookup, password reset, and signed-in home screen.
- `backend/`: FastAPI server that verifies Firebase ID tokens and checks `metaserver.family_login_allowlist`.
- `database/login_auth_schema.sql`: Login/auth schema DDL.
- `database/seed_family_allowlist.sql`: Sample family allowlist insert.

## Backend

```powershell
cd D:\kcastle\kang\backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt

$env:POSTGRES_HOST="211.47.74.33"
$env:POSTGRES_PORT="5432"
$env:POSTGRES_DB="dbkang"
$env:POSTGRES_USER="kang"
$env:POSTGRES_PASSWORD="<db password>"
$env:FIREBASE_PROJECT_ID="<firebase project id>"
$env:GOOGLE_APPLICATION_CREDENTIALS="<firebase service account json path>"

uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

## Android Studio

Open this folder in Android Studio:

```text
D:\kcastle\kang\frontend
```

Use `lib/main.dart` as the entrypoint. In Run Configuration > Additional run args, add the Firebase and API values:

```text
--dart-define=API_BASE_URL=http://10.0.2.2:8000
--dart-define=FIREBASE_API_KEY=<firebase web api key>
--dart-define=FIREBASE_PROJECT_ID=<firebase project id>
--dart-define=FIREBASE_WEB_APP_ID=1:153980946207:web:3044ef09ff07b6bf9f922a
--dart-define=FIREBASE_MESSAGING_SENDER_ID=153980946207
--dart-define=FIREBASE_AUTH_DOMAIN=<project id>.firebaseapp.com
```

`10.0.2.2` is for the Android emulator. Use `http://localhost:8000` for Chrome.

## Flutter web

```powershell
cd D:\kcastle\kang\frontend
C:\src\flutter\bin\flutter.bat run -d chrome `
  --dart-define=API_BASE_URL=http://localhost:8000 `
  --dart-define=FIREBASE_API_KEY=<firebase web api key> `
  --dart-define=FIREBASE_PROJECT_ID=<firebase project id> `
  --dart-define=FIREBASE_WEB_APP_ID=1:153980946207:web:3044ef09ff07b6bf9f922a `
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=153980946207 `
  --dart-define=FIREBASE_AUTH_DOMAIN=<project id>.firebaseapp.com
```

## Family allowlist

Before a family member can enter the app, add their email to:

```sql
INSERT INTO metaserver.family_login_allowlist (
    email, display_name, relationship, role_code, status
)
VALUES (
    'person@example.com', 'Name', 'family', 'family_member', 'invited'
);
```
