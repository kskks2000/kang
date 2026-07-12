# ETMS 데이터베이스

`etms`는 PostgreSQL 11 전용 엔터프라이즈 운송관리 스키마입니다. 00~11 기준선 480개와 운영 2차 점검 순방향 마이그레이션의 13개를 합친 493개 테이블이 로그인과 테넌트 보안부터 마스터, 운송주문, 편성·배정·배차, 복합운송 실행, 실적·클레임, 매입·매출 정산, 회계, 컴플라이언스, 연계·분석까지 연결합니다.

번호가 붙은 00~11 SQL은 하나의 원자적 트랜잭션으로만 적용합니다. 운영 적용 후에는 SQL·카탈로그·기준 시드 SHA-256 지문이 잠기므로 기존 파일을 고치지 않고 forward-only migration을 추가해야 합니다. 운영 반영된 `migrations/20260713_02`~`06`도 각각 체크섬이 잠긴 이력입니다.

```powershell
cd D:\kcastle\kang
python .\scripts\apply_etms_schema.py --dry-run
python .\scripts\smoke_test_etms_schema.py --with-pending-forward-dry-run
python .\scripts\apply_etms_schema.py
python .\scripts\apply_etms_schema.py --verify-only
python .\scripts\audit_etms_schema.py
python .\scripts\smoke_test_etms_schema.py
```

완전히 빈 `etms` 스키마에 신규 설치를 사전 검증할 때만 `smoke_test_etms_schema.py --with-baseline-dry-run`을 사용합니다. 기존 운영 스키마에는 미적용 migration만 올렸다가 되돌리는 `--with-pending-forward-dry-run`을 사용합니다.

## 모듈

- `00`: 테넌트·조직, Firebase 사용자/identity, membership, RBAC, 세션, 공통 파일·감사·연계 원장
- `01`: 국가·통화·UOM, 파트너·거점·품목, 기사·차량·장비·노선 마스터
- `02`: 매입/매출 계약·버전, lane·tier·부대비·유가, 견적·rating trace, SLA·capacity
- `03`: 운송주문·revision, 당사자/address snapshot, stop·line·HU, hold·변경이력
- `04`: scenario/optimizer, 합배송, shipment/leg/run, 자원배정, tender/award, 배차·dock appointment
- `05`: 해상·항공·철도 schedule/booking, 컨테이너, B/L·AWB 문서, 통관·permit
- `06`: 실행 이벤트, GPS·geofence·ETA·센서, 기사 workflow/HOS, scan·custody, POD·예외·사고·yard
- `07`: shipment/run/stop 실적, SLA·scorecard·탄소, 클레임, KPI·운송/원가 분석 fact
- `08`: BUY/SELL charge, accrual, AP/AR invoice, 세금계산서, 정산·지급, 복식분개, 승인 workflow
- `09`: 상태, 알림·EDI·webhook·batch, tenant detail 보강, 기본 무결성·인덱스·기준 시드
- `10`: 보안 컨텍스트, SOD·권한검토, 상세 차량/기사, tariff·snapshot rating, 수요예측·적재·재계획, 라스트마일, 회수·구상, 은행대사, 규제·제재, 데이터 계보·SCD 분석 보강 160개
- `11`: 보호된 세션/요청 컨텍스트, 상태전이, overlap/capacity 검증, append-only, JSON/암호문 보호, RLS/FORCE RLS, 권한 회수

## 운영 2차 점검 마이그레이션

- `20260713_02`: 요청·세션발급·membership·identity command context를 canonical session/membership 복합 FK에 결합
- `20260713_03`: 12개 운영 증적 테이블, 최초 상태이력, POD 검증 후 불변성, 증적 파일 보호, HU·견적·낙찰 이력
- `20260713_04`: 주문 배분 합계, 만료 포함 중량·부피·팔레트 capacity, tender/award/배정/배차 연쇄, dock·vehicle 중복
- `20260713_05`: posted journal 연결, 회계기간·조직·기준통화, claim 합계, COD 수납·송금, 확정 재무문서 불변성
- `20260713_06`: 로그인 전 보안감사, 택배·해상·항공·철도 parentage, SCD2 기간 중복, nullable 분석 grain 유일성

운영 검증 기준은 테이블 493개, FK 2,706개, CHECK 1,091개, 인덱스 3,500개, 트리거 2,301개, tenant RLS/FORCE 테이블 474개입니다.

## 핵심 운송 모델

```text
운송주문(N) ↔ Shipment(N) → Shipment Leg
                                ↓ allocation
                      Transport Run → Run Leg/Stop
                                ↓
              운송사·기사·차량 배정 → 입찰/배차/수락
                                ↓
              이벤트·관제·POD·예외 → 실행/실적
                                ↓
             BUY/SELL Charge → Invoice/Tax/Settlement
                                ↓
                    Payment → 복식분개 → KPI/분석
```

주문 수요, 상업적 이동 단위인 shipment, 실제 차량 회차인 run을 분리합니다. 따라서 주문 분할, 다주문 합배송, 멀티픽업·멀티드롭, 릴레이·환적·백홀과 기사/차량 교체 이력을 보존할 수 있습니다.

## 로그인과 테넌트 보안

- `etms.users.platform_user_id`는 `kang.users(id)`와 필수 1:1 FK입니다.
- Firebase 범위는 `kang-84cdd`, tenant 없음, provider는 `password`와 `google.com`만 허용합니다.
- ID/refresh/access token, 비밀번호, 카드 원문은 저장하지 않습니다. 세션은 서버 handle의 SHA-256 hash만 저장합니다.
- `issue_auth_session(...)`이 활성 사용자·identity·membership을 검증해 세션을 발급합니다.
- 매 트랜잭션에서 서버가 `bind_request_context(<session-handle-sha256>)`를 호출합니다. `current_tenant_id()`는 보호된 `(backend_pid, transaction_id)` 컨텍스트에서만 값을 얻으며 `SET etms.tenant_id`는 무시합니다.
- tenant 테이블 474개는 RLS와 FORCE RLS가 모두 켜져 있습니다. 운영 앱은 소유자 계정이 아닌 `NOBYPASSRLS` 역할을 사용합니다.
- `security_role_template.sql`은 권한 분리를 위한 DBA 검토용 예시이며 자동 적용하지 않습니다.

## 주요 무결성

- tenant 관계는 동일 tenant FK/trigger와 tenant 불변 trigger로 교차 tenant 참조를 차단합니다.
- 확정 planning scenario는 order revision과 입력 snapshot을 고정합니다.
- 계약 버전, rate lane/tier, 기사·차량, dock slot은 기간 중복을 차단합니다.
- run capacity, 단일 current route, 단일 active tender award와 primary assignment를 DB에서 보장합니다.
- 실행 event/GPS/sensor/scan은 source sequence 중복을 막고 발생/수신 시각을 분리합니다.
- 이벤트·상태·감사 evidence는 UPDATE·DELETE·TRUNCATE를 막고 correction/reversal 행을 사용합니다.
- POD 수량, 견적·연료·경비·청구·정산·지급 합계와 복식분개 균형을 검증합니다.
- finalized invoice/tax/settlement와 posted journal은 되돌려 고치지 않고 credit/debit note·반대분개를 사용합니다.
- JSONB의 credential 키, 평문 암호문 필드, 잘못된 secret-manager reference를 차단합니다.

PostgreSQL 11의 partition FK 제약 때문에 기준선은 일반 테이블과 B-tree/BRIN/GIN 인덱스를 사용합니다. 실제 수집량이 확정되면 event/GPS/sensor/audit/fact를 월 단위 range partition으로 이전하는 별도 forward migration과 보존·legal hold 절차를 함께 적용합니다.
