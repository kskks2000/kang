# AGENTS.md

이 문서는 Kang 저장소에서 작업하는 AI 에이전트를 위한 지침입니다. 사람용 프로젝트 안내는 `README.md`에만 둡니다.

## 범위

- 이 파일은 저장소 전체에 적용됩니다.
- README에는 설치, 실행, 기능 설명처럼 사람이 바로 읽을 정보만 둡니다.
- 에이전트 작업 규칙, 코드 구조 메모, 검증 체크리스트는 이 파일에 둡니다.

## 프로젝트 구조

- `frontend/`: Flutter 앱입니다. 진입점은 `frontend/lib/main.dart`입니다.
- `frontend/lib/app_config.dart`: 실행 환경별 API 기본 주소를 결정합니다.
- `frontend/lib/firebase_options.dart`: Firebase 클라이언트 설정입니다. 현재 프로젝트는 `kang-84cdd`입니다.
- `scripts/flutter_run_with_env.ps1`: 루트 `.env`와 `backend/.env`를 읽어 Flutter `--dart-define` 값으로 전달합니다.
- `frontend/lib/screens/`: 화면 단위 UI입니다.
- `frontend/lib/services/`: 백엔드 및 Google/Firebase 연동 클라이언트입니다.
- `frontend/lib/theme/`, `frontend/lib/widgets/`: 공통 스타일과 UI 컴포넌트입니다.
- `backend/`: FastAPI 앱입니다. 로컬 진입점은 `backend/app/main.py`입니다.
- `backend/main.py`: Firebase Functions 진입점입니다.
- `backend/app/settings.py`: 환경값 로딩과 DB 연결 제한을 담당합니다.
- `backend/app/schemas.py`: API 요청/응답 모델입니다.
- `database/`: 운영 DB 스키마와 마이그레이션 SQL입니다.
- `database/dwms/`: PostgreSQL 11용 엔터프라이즈 WMS `dwms` 기준선입니다. 구조와 운영 전제는 `database/dwms/README.md`에 있습니다.
- `scripts/apply_dwms_schema.py`: 00~11 DWMS 모듈을 원자적으로 적용하고 카탈로그·RLS·무결성 보호를 검증합니다.
- `database/ewms/`: PostgreSQL 11용 엔터프라이즈 창고·수출입물류 EWMS `ewms` 기준선입니다. 구조와 운영 전제는 `database/ewms/README.md`에 있습니다.
- `scripts/apply_ewms_schema.py`, `scripts/audit_ewms_schema.py`, `scripts/smoke_test_ewms_schema.py`: 00~14 EWMS 모듈의 원자 적용, 읽기 전용 카탈로그 감사, rollback-only 업무 무결성 검증입니다.
- `database/deims/`: PostgreSQL 11용 엔터프라이즈 수출입물류 EIMS `deims` 기준선입니다. 구조와 운영 전제는 `database/deims/README.md`에 있습니다.
- `scripts/apply_deims_schema.py`: 00~12 DEIMS 모듈을 원자적으로 적용하고 카탈로그·RLS·무결성 보호를 검증합니다.
- `database/doms/`: PostgreSQL 11용 엔터프라이즈 오더관리 DOMS `doms` 기준선입니다. 구조와 운영 전제는 `database/doms/README.md`에 있습니다.
- `scripts/apply_doms_schema.py`: 00~10 DOMS 모듈을 원자적으로 적용하고 카탈로그·RLS·주문·결제·재고약속·반품·회계 무결성을 검증합니다.
- `database/etms/`: PostgreSQL 11용 엔터프라이즈 운송관리 ETMS `etms` 기준선입니다. 구조와 운영 전제는 `database/etms/README.md`에 있습니다.
- `scripts/apply_etms_schema.py`: 00~11 ETMS 모듈을 원자적으로 적용하고 SQL·카탈로그·시드 지문, RLS/FORCE RLS와 운송 무결성을 검증합니다.
- `scripts/audit_etms_schema.py`, `scripts/smoke_test_etms_schema.py`: ETMS의 읽기 전용 카탈로그 감사와 rollback-only 업무 무결성 검증입니다.
- `docs/stock_trading_dashboard_status.md`: 주식 거래 대시보드의 완료 항목, 구현 메모, 다음 작업 전 확인 사항입니다. 주식 거래 화면을 수정하기 전 반드시 먼저 읽습니다.

## 중요한 계약

- PostgreSQL 연결은 `211.47.74.33/dbkang` 및 사용자 `kang`으로 제한되어 있습니다. `backend/app/settings.py`의 DB 가드를 임의로 완화하지 마세요.
- `.env`, `backend/.env`, 서비스 계정 JSON, 토큰, 비밀번호는 커밋하지 않습니다.
- 백엔드는 루트 `.env`를 먼저 읽고 `backend/.env`로 백엔드 전용 값을 덮어씁니다. 이미 프로세스 환경변수로 지정된 값은 덮어쓰지 않습니다.
- Firebase 인증 이후 프론트엔드는 Firebase ID 토큰을 `POST /auth/session`으로 전달합니다.
- 로그인 세션 처리는 `kang.users`, `kang.auth_identities`, `kang.user_profiles`, `kang.user_roles`, `kang.login_events`와 맞아야 합니다.
- API 주소 기본값은 `frontend/lib/app_config.dart`에 있습니다. 모든 플랫폼 기본값은 `https://www.kang.ai.kr`입니다.
- 완료 처리 전에는 반드시 `https://www.kang.ai.kr`에 배포하고, 같은 도메인에서 직접 동작 확인을 끝내야 합니다. 로컬 실행, 로컬 빌드, 파일 확인만으로 완료 보고하지 마세요.
- 프론트엔드의 사용자 표시 문구는 현재 한국어 중심입니다. 새 UI도 같은 톤을 유지하세요.
- Google Calendar, Drive, Sheets, Keep 연동 코드는 권한 범위와 access token 흐름에 민감합니다. 토큰을 영구 저장하거나 로그에 남기지 마세요.
- 토스증권 Open API 주문 생성, 정정, 취소는 사용자가 명시적으로 요청한 경우에만 연결합니다. 실제 주문 전송은 Firebase 인증, `TOSSINVEST_TRADING_ENABLED=true`, `TOSSINVEST_TRADING_ALLOWED_EMAILS` 허용 목록, 프론트엔드 최종 확인 모달 또는 정정/취소 확인창을 모두 거쳐야 합니다.
- `TOSSINVEST_CLIENT_ID`, `TOSSINVEST_CLIENT_SECRET`, `TOSSINVEST_ACCOUNT`, `TOSSINVEST_TRADING_ALLOWED_EMAILS`는 비밀값 또는 개인정보로 취급하고 로그, 문서, diff에 실제 값을 노출하지 마세요.
- 운영 서버의 공인 IP가 토스증권 Open API 콘솔 허용 IP에 등록되어 있어야 합니다. 운영 확인 중 `IP address not allowed`가 나오면 코드보다 토스 콘솔 IP 허용 목록을 먼저 확인하세요.
- DWMS 기준선 변경 전에는 `database/dwms/README.md`를 먼저 읽고, 변경 후 `python scripts/apply_dwms_schema.py --dry-run`과 `--verify-only`를 실행합니다. 운영 배포 후 00~11 기준 파일은 체크섬이 잠긴 것으로 보고 직접 고치지 말고 새 forward-only 마이그레이션을 추가합니다.
- EWMS 기준선 변경 전에는 `database/ewms/README.md`를 먼저 읽습니다. 기존 운영 스키마에는 미적용 allowlisted forward migration만 대상으로 `python scripts/apply_ewms_schema.py --dry-run`을 실행한 뒤 실제 적용, `--verify-only`, `python scripts/audit_ewms_schema.py`, `python scripts/smoke_test_ewms_schema.py` 순서로 검증합니다. 완전히 빈 스키마에서는 같은 적용기가 00~14 기준선과 모든 후속 migration을 함께 검증합니다. 운영 배포된 00~14와 `migrations/20260713_02`~`03`은 SQL·카탈로그·시드 체크섬이 잠긴 것으로 보고 직접 고치지 말고 다음 번호의 forward-only migration을 추가합니다.
- EWMS tenant 권한은 임의 `SET ewms.tenant_id`가 아니라 `issue_ewms_session(...)`과 트랜잭션별 `bind_request_context(...)`로만 발급합니다. 앱 역할에 table owner, `BYPASSRLS`, 보호 context/session 테이블 직접 권한, 전체 함수 EXECUTE를 부여하지 않습니다.
- DEIMS 기준선 변경 전에는 `database/deims/README.md`를 먼저 읽고, 변경 후 `python scripts/apply_deims_schema.py --dry-run`과 `--verify-only`를 실행합니다. 운영 배포 후 00~12 기준 파일은 체크섬이 잠긴 것으로 보고 직접 고치지 말고 새 forward-only 마이그레이션을 추가합니다.
- DOMS 기준선 변경 전에는 `database/doms/README.md`를 먼저 읽고, 변경 후 `python scripts/apply_doms_schema.py --dry-run`, 실제 적용, `--verify-only`, `python scripts/smoke_test_doms_schema.py`를 실행합니다. 운영 배포 후 00~10 기준 파일은 체크섬이 잠긴 것으로 보고 직접 고치지 말고 새 forward-only 마이그레이션을 추가합니다.
- ETMS 변경 전에는 `database/etms/README.md`와 `docs/etms_database_design.md`를 먼저 읽습니다. 기존 운영 스키마는 `--dry-run`, `smoke_test_etms_schema.py --with-pending-forward-dry-run`, 실제 적용, `--verify-only`, `audit_etms_schema.py`, 기본 smoke 순서로 검증합니다. 완전히 빈 스키마의 신규 설치 검증에만 `--with-baseline-dry-run`을 사용합니다. 운영 배포된 00~11과 `migrations/20260713_02`~`06`은 SQL·카탈로그·시드 체크섬이 잠겼으므로 직접 고치지 말고 다음 번호의 forward-only migration을 추가합니다.
- ETMS tenant 권한은 임의 `SET etms.tenant_id`가 아니라 `issue_auth_session(...)`과 트랜잭션별 `bind_request_context(...)`로만 발급합니다. 앱 역할에 table owner, `BYPASSRLS`, 보호 context/auth session 테이블 직접 권한, 전체 함수 EXECUTE를 부여하지 않습니다.

## 주식 거래 대시보드 작업 전 확인

- 주식 거래 대시보드, 토스증권 연동, 종목 검색, 종목 아이콘, 차트, 주문, 체결/미체결/잔고, 현재가/등락률 표시를 수정하기 전에는 반드시 `docs/stock_trading_dashboard_status.md`를 먼저 읽습니다.
- 해당 문서에는 이미 적용 완료된 1~10번 항목, 관련 코드 위치, 운영 배포/검증 기준이 정리되어 있습니다.
- 기존 적용 완료 항목을 되돌리거나 중복 구현하지 말고, 현재 코드와 운영 동작을 확인한 뒤 필요한 부분만 좁게 수정합니다.

## 개발 명령

백엔드 로컬 실행:

```powershell
cd D:\kcastle\kang\backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

프론트엔드 로컬 실행:

```powershell
cd D:\kcastle\kang
.\scripts\flutter_run_with_env.ps1 -Device chrome
```

검증:

```powershell
cd D:\kcastle\kang\frontend
C:\src\flutter\bin\flutter.bat analyze
C:\src\flutter\bin\flutter.bat test
```

백엔드에는 현재 별도 테스트 스위트가 없습니다. 백엔드 변경 후에는 서버를 띄우고 `GET /health` 및 변경한 엔드포인트를 확인하세요.

배포용 웹 빌드:

```powershell
cd D:\kcastle\kang\frontend
C:\src\flutter\bin\flutter.bat build web --release `
  --dart-define=API_BASE_URL=https://www.kang.ai.kr
```

배포 후 운영 도메인 확인:

```powershell
Invoke-WebRequest -Uri https://www.kang.ai.kr/health -UseBasicParsing
```

## 작업 방식

- 변경 전 관련 파일을 먼저 읽고 기존 패턴을 따릅니다.
- 사용자가 만든 미커밋 변경을 되돌리지 않습니다.
- 기능 변경은 가능한 한 프론트엔드 서비스, 백엔드 스키마, DB SQL을 함께 맞춥니다.
- 새 API를 추가할 때는 `backend/app/schemas.py`에 요청/응답 모델을 정의하고 `backend/app/main.py`에서 명시적인 response model을 사용합니다.
- 외부 API 호출은 `backend/app/*_service.py` 또는 `frontend/lib/services/*`의 기존 스타일을 따릅니다.
- Flutter UI는 `KangTheme`, 공통 위젯, 기존 화면의 여백/색/상태 처리 방식을 재사용합니다.
- 문서 변경 시 사람에게 필요한 내용은 `README.md`, 에이전트에게 필요한 내용은 `AGENTS.md`에 분리합니다.
- 환경변수를 추가하면 `.env.example`, `backend/.env.example`, `README.md`, 필요 시 `scripts/flutter_run_with_env.ps1`의 dart define 목록을 함께 갱신합니다.

## 변경 후 체크리스트

- 프론트엔드 변경: `flutter analyze`와 `flutter test`를 실행합니다.
- 백엔드 변경: import 오류 없이 `uvicorn app.main:app`이 뜨는지 확인합니다.
- 인증/DB 변경: `database/` SQL과 백엔드 모델/쿼리가 서로 맞는지 확인합니다.
- DWMS 변경: PostgreSQL 11 전체 dry-run, 실제 적용, `--verify-only`, 핵심 원장/통관/정산 롤백 스모크 테스트를 순서대로 완료합니다.
- EWMS 변경: PostgreSQL 11 미적용 forward dry-run(빈 스키마면 기준선 포함), 실제 적용, `--verify-only`, 독립 catalog audit, 인증 context·교차 tenant·수출 업무건/신고 봉인·UNI-PASS 상태·재고/보세 원장 결합·컴플라이언스·청구서/정산/복식분개 rollback smoke를 순서대로 완료합니다. 실제 관세청 네트워크·생산 인증서/HSM·신고 전문 검증은 별도 연계 승인 환경에서 수행합니다.
- DEIMS 변경: PostgreSQL 11 전체 dry-run, 실제 적용, `--verify-only`, 수입/수출·통관·원산지·컴플라이언스·정산 핵심 무결성 스모크 테스트를 순서대로 완료합니다.
- DOMS 변경: PostgreSQL 11 전체 dry-run, 실제 적용, `--verify-only`, 교차 tenant·주문·예약·결제·이행·반품·법적보류·복식분개 롤백 스모크 테스트를 순서대로 완료합니다.
- ETMS 변경: PostgreSQL 11 전체 dry-run과 pending-forward smoke(빈 스키마면 baseline smoke), 실제 적용, `--verify-only`, 카탈로그 감사, 로그인 context·교차 tenant·계획 revision·주문배분·용량/배정/배차·POD·원장·정산·복식분개 rollback smoke를 순서대로 완료합니다.
- API 주소나 실행 방식 변경: `README.md`와 이 파일을 함께 갱신합니다.
- 비밀값, 로컬 경로, 개인 토큰이 diff에 포함되지 않았는지 확인합니다.
- 완료 보고 전: 반드시 `https://www.kang.ai.kr`에 배포합니다.
- 완료 보고 전: 반드시 `https://www.kang.ai.kr`에서 변경된 화면/API를 직접 테스트하고 결과를 사용자에게 알려줍니다.
- 완료 보고 전: 로컬 주소 문자열이 소스, 환경 예시, 문서, 배포 산출물에 남아 있지 않은지 확인합니다.
