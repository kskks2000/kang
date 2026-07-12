# Kang

Kang은 Flutter 프론트엔드와 FastAPI 백엔드, PostgreSQL, Firebase Auth를 함께 사용하는 개인용 앱입니다.

이 문서는 사람이 프로젝트를 이해하고 실행하기 위한 안내입니다. AI 에이전트용 작업 규칙은 [AGENTS.md](AGENTS.md)를 보세요.

## 구성

- `frontend/`: Flutter 앱. 로그인, 회원가입, 아이디 찾기, 비밀번호 재설정, 로그인 후 홈 화면을 제공합니다.
- `backend/`: FastAPI 서버. Firebase ID 토큰을 검증하고 사용자 정보와 외부 데이터 API를 처리합니다.
- `database/`: 로그인/인증, Google OAuth, Drive 연동 SQL과 PostgreSQL 11용 엔터프라이즈 WMS·EIMS·OMS·TMS 기준 스키마를 포함합니다.
- `firebase.json`: Firebase Hosting과 Python Functions 배포 설정입니다.

## 주요 기능

- Firebase 이메일/비밀번호 및 Google 로그인
- 로그인 세션 생성과 사용자 정보 저장
- Google Calendar, Drive, Sheets, Keep 연동 화면
- 대학 정보, 금융 시장, 글로벌 시가총액, 지하철 정보 조회

## 환경변수

루트의 `.env`에서 공통 환경변수를 관리합니다. 이 파일은 git에 올라가지 않습니다. 처음 설정할 때는 `.env.example`을 참고해서 `.env`를 채우세요.

백엔드는 루트 `.env`를 먼저 읽고, `backend/.env`가 있으면 그 값으로 백엔드 전용 설정을 덮어씁니다. 기존처럼 민감한 DB 비밀번호나 서비스 계정 경로를 `backend/.env`에만 두어도 됩니다.

프론트엔드는 Flutter 특성상 `.env`를 직접 읽지 않고 `--dart-define`으로 값을 받습니다. `scripts/flutter_run_with_env.ps1`가 `.env`를 읽어서 필요한 값을 자동으로 넘깁니다.

## 백엔드 실행

PostgreSQL 연결은 `211.47.74.33/dbkang` 데이터베이스와 `kang` 사용자로 제한되어 있으며, 다른 DB로 설정되면 서버가 시작되지 않습니다.

```powershell
cd D:\kcastle\kang\backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

주요 백엔드 환경값은 다음과 같습니다.

- `DATABASE_URL` 또는 `POSTGRES_HOST`, `POSTGRES_PORT`, `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`
- `KANG_FIREBASE_PROJECT_ID` 또는 `FIREBASE_PROJECT_ID`
- `GOOGLE_APPLICATION_CREDENTIALS` 또는 `FIREBASE_CREDENTIALS_JSON`
- `CORS_ALLOWED_ORIGINS`
- `ACADEMYINFO_SERVICE_KEY`, `SEOUL_SUBWAY_API_KEY`
- `TOSSINVEST_API_BASE_URL`, `TOSSINVEST_CLIENT_ID`, `TOSSINVEST_CLIENT_SECRET`, `TOSSINVEST_ACCOUNT`
- `TOSSINVEST_TRADING_ENABLED`, `TOSSINVEST_TRADING_ALLOWED_EMAILS`
- `UPBIT_API_BASE_URL`, `UPBIT_ACCESS_KEY`, `UPBIT_SECRET_KEY`
- `UPBIT_TRADING_ENABLED`, `UPBIT_TRADING_ALLOWED_EMAILS`
- `APP_PUBLIC_URL`, `HTTP_USER_AGENT`, `BROWSER_USER_AGENT`
- `DEFAULT_SUBWAY_STATION`, `DEFAULT_SUBWAY_LINE`
- `SFTP_HOST`, `SFTP_PORT`, `SFTP_USERNAME`, `SFTP_PASSWORD`, `SFTP_REMOTE_PATH`

토스증권 Open API는 콘솔의 허용 IP 설정이 필요합니다. 운영 서버에서 토스 조회가 `IP address not allowed`로 실패하면 `https://www.kang.ai.kr` 서버의 공인 IP를 토스증권 Open API 허용 IP에 등록하세요. 실제 주문 생성, 정정, 취소는 `TOSSINVEST_TRADING_ENABLED=true`이고 Firebase 이메일이 `TOSSINVEST_TRADING_ALLOWED_EMAILS`에 포함된 경우에만 동작합니다.

업비트 Open API 키는 백엔드 환경변수에만 저장합니다. 코인 시세는 키 없이 조회되지만, 잔고와 실제 주문은 `UPBIT_ACCESS_KEY`, `UPBIT_SECRET_KEY`, `UPBIT_TRADING_ENABLED=true`, `UPBIT_TRADING_ALLOWED_EMAILS` 허용 이메일이 모두 설정된 경우에만 동작합니다. 실제 코인 주문은 최종 확인 후 업비트 주문 테스트 API(`/v1/orders/test`)를 통과한 경우에만 주문 생성 API(`/v1/orders`)로 전송하며, 백엔드 실주문 라우트도 주문 테스트를 다시 강제합니다.

## 엔터프라이즈 WMS 데이터베이스

`database/dwms/`에는 `dwms` 스키마의 457개 테이블을 만드는 PostgreSQL 11 기준선이 있습니다. Firebase 이메일/비밀번호·Google 로그인 매핑, 다화주 마스터, 입고·재고 이중분개·출고, 국제무역/대한민국 세관·UNI-PASS, 보세창고, 청구·정산·회계, 워크플로·감사·분석을 포함합니다. 상세 설계와 운영 전제는 [DWMS 데이터베이스 안내](database/dwms/README.md)를 참고하세요.

```powershell
cd D:\kcastle\kang
python .\scripts\apply_dwms_schema.py --dry-run
python .\scripts\apply_dwms_schema.py
python .\scripts\apply_dwms_schema.py --verify-only
```

적용기는 `.env`의 기존 DB 접속값을 사용하고 PostgreSQL 11 및 허용된 운영 DB인지 확인합니다. 비밀번호·토큰·인증서 개인키는 DWMS 테이블에 저장하지 않으며, 별도 런타임 DB 역할은 DBA가 `database/dwms/security_role_template.sql`을 검토한 뒤 구성해야 합니다.

## 엔터프라이즈 수출입물류 EIMS 데이터베이스

`database/deims/`에는 `deims` 스키마의 611개 테이블을 만드는 PostgreSQL 11 기준선이 있습니다. Firebase 이메일/비밀번호·Google 로그인 매핑, 조직·파트너·품목, 수입/수출 업무건과 주문, 국제운송 예약, 관세·UNI-PASS·보세, FTA 원산지, 제재·전략물자·허가, 정산·무역금융, 보험·클레임, 문서·워크플로·감사를 포함합니다. 상세 설계와 운영 전제는 [DEIMS 데이터베이스 안내](database/deims/README.md)를 참고하세요.

```powershell
cd D:\kcastle\kang
python .\scripts\apply_deims_schema.py --dry-run
python .\scripts\apply_deims_schema.py
python .\scripts\apply_deims_schema.py --verify-only
```

적용기는 00~12 모듈을 한 트랜잭션에서 실행하고 SQL·카탈로그·기준 시드 체크섬, FK/CHECK/트리거, RLS/FORCE RLS, Firebase 주체 매핑과 비밀값 금지 규칙을 검증합니다. 애플리케이션 런타임 역할은 `database/deims/security_role_template.sql`을 DBA가 검토한 뒤 별도로 생성해야 합니다.

## 엔터프라이즈 오더관리 DOMS 데이터베이스

`database/doms/`에는 `doms` 스키마의 433개 테이블을 만드는 PostgreSQL 11 기준선이 있습니다. Firebase 이메일/비밀번호·Google 로그인과 보호된 세션/RLS 컨텍스트, 고객·채널·가격·프로모션, 다채널 주문, ATP·예약·할당, 결제·세금·부정탐지, 분할출고·배송, 반품·RMA·교환·보증, 조달·드롭십, 청구·채널정산·복식분개, 워크플로·통합·감사·개인정보 처리를 포함합니다. 상세 설계와 운영 전제는 [DOMS 데이터베이스 안내](database/doms/README.md)를 참고하세요.

```powershell
cd D:\kcastle\kang
python .\scripts\apply_doms_schema.py --dry-run
python .\scripts\apply_doms_schema.py
python .\scripts\apply_doms_schema.py --verify-only
python .\scripts\smoke_test_doms_schema.py
```

적용기는 00~10 모듈을 한 트랜잭션에서 실행하고 SQL·카탈로그·기준 시드 체크섬, 모든 tenant 테이블의 RLS/FORCE RLS, 세션에 결합된 요청 컨텍스트, 동일 tenant FK, append-only, JSONB·암호문·secret reference 규칙, Firebase 주체와 결제·재고·반품·회계 핵심 무결성을 검증합니다. 런타임 역할은 `database/doms/security_role_template.sql`을 CREATEROLE 권한이 있는 DBA가 검토한 뒤 별도로 생성해야 합니다.

## 엔터프라이즈 운송관리 ETMS 데이터베이스

`database/etms/`에는 PostgreSQL 11용 `etms` 기준선 480개와 순방향 보완 13개를 합친 493개 테이블이 있습니다. 보호된 Firebase 세션과 tenant context, 조직·파트너·거점·차량·기사 마스터, 운송주문, 편성·합배송·배정·배차, 도로·해상·항공·철도·택배 실행과 관제/POD, 계약·tariff·운임, 실적·탄소·클레임, 매입/매출 청구·세금계산서·정산·복식분개, 규제·제재·개인정보·연계·SCD 분석을 포함합니다. 상세 설계는 [ETMS 데이터베이스 안내](database/etms/README.md)와 [ETMS 설계 문서](docs/etms_database_design.md)를 참고하세요.

```powershell
cd D:\kcastle\kang
python .\scripts\apply_etms_schema.py --dry-run
python .\scripts\smoke_test_etms_schema.py --with-pending-forward-dry-run
python .\scripts\apply_etms_schema.py
python .\scripts\apply_etms_schema.py --verify-only
python .\scripts\audit_etms_schema.py
python .\scripts\smoke_test_etms_schema.py
```

적용기는 immutable 00~11 기준선과 allowlist 순방향 이력을 검증하고 SQL·카탈로그·기준 시드 지문, 2,706개 FK, 1,091개 CHECK, tenant 테이블 474개의 RLS/FORCE RLS, 동일 tenant 참조, 로그인 전용 세션 context, 계획 revision·주문배분·기간 overlap·중량/부피/팔레트 capacity·tender/배정/배차, append-only UPDATE/DELETE/TRUNCATE, JSONB 비밀값·암호문·secret reference와 claim/COD·정산·기준통화 복식분개 무결성을 검증합니다. 운영 런타임 역할은 `database/etms/security_role_template.sql`을 권한 있는 DBA가 검토한 뒤 최소 권한으로 별도 생성해야 합니다.

## 프론트엔드 실행

Android Studio에서 다음 폴더를 열고 `lib/main.dart`를 실행합니다.

```text
D:\kcastle\kang\frontend
```

명령줄에서는 `.env`를 읽어 실행하는 스크립트를 사용합니다.

```powershell
cd D:\kcastle\kang
.\scripts\flutter_run_with_env.ps1 -Device chrome
```

기본 API 주소는 모든 실행 환경에서 `https://www.kang.ai.kr`입니다.

다른 API 서버를 바라보게 하려면 `.env`의 `API_BASE_URL`을 원하는 주소로 바꿔 실행하세요.

Firebase 클라이언트 설정은 `frontend/lib/firebase_options.dart`에 있으며 프로젝트 ID는 `kang-84cdd`입니다.

## 로그인 데이터 흐름

사용자가 Flutter 앱에서 Firebase 인증을 완료하면 앱은 Firebase ID 토큰을 백엔드의 `POST /auth/session`으로 보냅니다. 백엔드는 토큰을 검증한 뒤 다음 테이블을 생성 또는 갱신합니다.

```text
kang.users
kang.auth_identities
kang.user_profiles
kang.user_roles
kang.login_events
```

## 확인 명령

```powershell
cd D:\kcastle\kang\frontend
C:\src\flutter\bin\flutter.bat analyze
C:\src\flutter\bin\flutter.bat test
```

백엔드는 현재 별도 테스트 스위트가 없으므로 서버 실행 후 `GET /health`로 기동 상태를 확인합니다.
