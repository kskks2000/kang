# ETMS 엔터프라이즈 데이터베이스 설계

## 설계 결과

`etms`는 로그인부터 마스터, 주문, 운송계획(편성·배정·배차), 운송실행/관제, 운송실적, 계약·요율, 매입/매출 정산, 세금계산서, 회계, 컴플라이언스, KPI·탄소 분석까지 한 흐름으로 추적하는 PostgreSQL 11 스키마입니다. 최초 기준선은 00~11 모듈과 480개 테이블이며, 2차 점검 순방향 보완 13개를 포함한 운영 구조는 493개 테이블입니다.

핵심 업무 흐름은 다음과 같습니다.

```text
Firebase 사용자 → 테넌트 membership/RBAC
운송주문(N) ↔ Shipment(N) → Shipment Leg
                 ↓              ↓
              편성/합배송     Transport Run/Run Leg
                                ↓
                       운송사·기사·차량 배정/배차
                                ↓
                    실행 이벤트·관제·POD·예외·실적
                                ↓
                  BUY/SELL Charge → Invoice/Tax Invoice
                                ↓
                       Settlement/Payment/Journal
                                ↓
                      SLA/KPI/원가/탄소/운송사 분석
```

주문과 Shipment는 N:M이므로 분할배송과 합배송을 모두 지원합니다. 상업적 운송단위인 Shipment/Leg와 실제 차량 회차인 Transport Run/Run Leg를 분리해 다중 픽업·멀티드롭·밀크런·릴레이·환적·백홀·공차회송과 기사/차량 교체를 보존합니다. Run Leg 배분·실행·실적 및 컨테이너 적입·구간 배정도 별도 계층으로 추적합니다.

## 도메인 구성

| 모듈 | 주요 범위 |
|---|---|
| Foundation/IAM | 테넌트, 법인/조직, Firebase 사용자, password·Google identity, membership, RBAC, 세션 해시, 로그인/감사 |
| Master | 국가/통화/UOM, 파트너/운송사, 주소/거점/도크/지오펜스, 품목/위험물/온도, 기사/면허, 차량/트레일러/컨테이너, 노선 |
| Contract/Rate | 매입·매출 계약 버전, lane rate, tier/accessorial, 유가할증, 견적, SLA, 운송사 capacity commitment |
| Order | 주문 revision, 당사자/address snapshot, 다중 stop/time window, cargo line, HU/SSCC 계층, hold/change request |
| Planning/Dispatch | planning scenario/run, 합배송, shipment/leg, run/stop, capacity, 입찰/award, dispatch revision, dock appointment |
| Multimodal | 선박/항공/철도 schedule/call, booking, container load/leg, seal/VGM, B/L·AWB 등 문서, 통관/permit |
| Execution | 불변형 이벤트 원장, 상태이력, GPS/geofence/ETA, driver task/HOS, scan/custody, sensor, POD, 예외/사고/yard |
| Result/Claim | shipment/run/stop/run-leg 실적, SLA, scorecard, 배출량, 손상/클레임/reserve/settlement, KPI와 분석 fact |
| Finance | canonical BUY/SELL charge, allocation/adjustment/accrual, AP·AR invoice, 한국 세금계산서, 정산/지급, GL journal |
| Integration | outbox/idempotency, 외부 ID, EDI/webhook, import/export/job/DLQ, 알림, 데이터품질, retention/legal hold |
| Governance/Compliance | 보호된 세션 context, SOD·권한검토, 개인정보 요청, 법적보류, 차량/기사 안전, 제재 screening |
| Extended Operations | tariff/rating snapshot, 수요예측, 적재·resource calendar, 재계획, 해상·항공·철도·택배/COD, 회수·구상 |
| Analytics | lineage, SCD2 location/partner/carrier/driver/vehicle/lane dimension, 주문·계획·복합운송·클레임·정산 fact |

전체 객체 수와 제약 수는 배포 스크립트의 카탈로그 검증 결과를 기준으로 관리합니다. `--verify-only`는 SQL 파일 SHA-256, 실제 relation/column/constraint/index/trigger/function/RLS 카탈로그 지문, 기준 시드 지문을 함께 대조합니다.

## Firebase 로그인 설계

- Firebase Authentication이 이메일/비밀번호와 Google 로그인을 모두 처리합니다.
- `etms.users`의 식별 기준은 mutable email이 아니라 `(firebase_project_id, firebase_tenant_id, firebase_uid)`입니다.
- `etms.auth_identities`가 `password`, `google.com` 공급자 subject와 issuer/audience를 분리해 한 Firebase 계정의 provider link를 보존합니다.
- 비밀번호 해시, Firebase ID/refresh token, Google access/refresh token 원문은 저장하지 않습니다.
- 세션 테이블에는 서버 세션 ID의 단방향 해시, auth time, assurance level, 만료/폐기만 저장합니다.
- 현재 앱의 canonical 계정은 `kang.users`입니다. `etms.users.platform_user_id`는 `kang.users(id)`에 필수 1:1 FK로 연결됩니다. `/auth/session` 뒤 TMS onboarding 로직은 이 FK를 사용해 `etms.users`를 upsert하고, 관리자가 membership/role을 부여해야 합니다. membership이 없거나 suspended이면 Firebase 인증 성공 후에도 ETMS 접근을 거부합니다.
- Google 로그인 인증과 Drive/Calendar OAuth 권한·토큰은 서로 다른 목적이므로 합치지 않습니다.

## 멀티테넌시와 보안

- 모든 tenant-owned header/detail/history에 `tenant_id`를 둡니다.
- 엄격한 관계는 `(tenant_id, child_fk) → (tenant_id, parent.id)` 복합 FK로 교차 테넌트 참조를 DB에서 차단합니다.
- global/tenant 겸용 마스터는 고정 `search_path`의 검증 트리거로 검사합니다.
- tenant_id는 생성 후 변경할 수 없습니다.
- tenant table 474개에 SELECT/write 정책을 분리한 RLS와 FORCE RLS를 모두 적용합니다. global reference는 SELECT만 공유하고 tenant_id NULL 행의 수정/삭제는 허용하지 않습니다.
- `issue_auth_session(...)`은 canonical Firebase 사용자·identity·membership을 한 번 더 대사해 서버 세션 hash를 발급합니다. `bind_request_context(...)`는 이를 `(backend_pid, transaction_id)`에 묶고, `current_tenant_id()`는 이 보호된 행만 읽습니다. 사용자가 임의로 `SET etms.tenant_id`를 실행해도 tenant를 가장할 수 없습니다.
- 운영 애플리케이션은 table owner가 아닌 별도 `NOBYPASSRLS` 역할을 사용해야 합니다. 현재 DB 사용자에는 CREATEROLE 권한이 없어 역할 생성은 DBA 작업으로 분리했습니다.
- object storage 파일은 URI, 크기, SHA-256, 암호화 키 참조만 DB에 저장합니다. POD 사진/서명/문서 binary는 DB에 넣지 않습니다.
- 전화번호·계좌·면허·VIN 등 검색이 필요한 개인정보는 암호문과 검색용 단방향 hash를 분리합니다.

## 시간·수량·금액

- 실제 순간은 `timestamptz`, 서비스일/회계일은 `date`, 거점에는 IANA timezone을 저장합니다.
- 이벤트는 현장 발생시각 `occurred_at`과 서버 수신시각 `received_at`을 분리해 지연·역순 이벤트를 보존합니다.
- 수량은 `numeric(20,6)`, 요율/환율은 더 높은 scale, 금액은 `numeric(20,4)`를 사용하고 floating point를 쓰지 않습니다.
- 거래통화, 기준통화, 환율값·기준일·출처를 snapshot합니다. 매입원가와 매출은 서로 다른 통화를 가질 수 있습니다.
- UOM은 dimension을 갖고 서로 다른 dimension 변환 및 유효기간 중복을 차단합니다. 연료/에너지는 litre 고정 대신 quantity+UOM으로 전기·CNG·LNG를 지원합니다.

## 이력·무결성

- master/계약/요율은 valid period와 version을 보존하고, 거래에는 party/address snapshot을 남깁니다.
- 주문·shipment·run·dispatch·invoice는 current status와 append형 status history를 함께 가집니다.
- 정산 확정 전 invoice/tax/settlement/journal header-line 합계를 DB가 대사합니다.
- 확정 invoice/tax invoice/settlement 및 posted journal은 editable 상태로 되돌리거나 삭제할 수 없고, 자식행 변경도 차단합니다. 수정세금계산서·credit/debit note·charge reversal·반대분개를 사용합니다.
- payment application은 payment와 target header를 잠근 뒤 통화와 누적 한도를 검사해 동시 처리 초과를 막습니다.
- 동일 기사/차량 장비의 겹치는 배정기간은 advisory transaction lock과 overlap 검사로 차단합니다.
- 단일 current route plan, 단일 active tender award/primary assignment, dock slot overlap과 run capacity 초과를 DB에서 차단합니다.
- 주문 stop/line, shipment leg/stop, run leg allocation, POD item의 같은 aggregate 소속을 업무 트리거가 검사합니다.
- 운송·상태·감사 evidence는 UPDATE뿐 아니라 DELETE와 TRUNCATE도 차단하고 correction/reversal 행을 추가합니다.

## 2차 점검 보완 결과

- 최초 설계 이후 독립 카탈로그 감사와 업무 스모크를 다시 수행해 운영 증적 12개와 재무 journal link 1개 테이블을 추가했습니다.
- 주문 배분은 percent·수량·중량·부피 누적 상한, run은 중량·부피·팔레트와 예약 만료를 동시성 잠금 아래 검사합니다.
- tender response→award→현재 winner→carrier assignment→dispatch 연결과 dock·vehicle 이중 예약을 DB가 검증합니다.
- POD 검증 완료 후 header·item·signature·discrepancy와 연결 증적 파일은 수정·삭제할 수 없고 correction/verification event만 추가합니다.
- invoice·tax invoice·settlement·credit/debit note·기사/차주 정산·claim·COD의 확정 상태는 출처가 일치하는 posted journal을 요구합니다. 회계기간, 조직, 거래통화 균형, 기준통화 환산과 header 합계를 함께 대사합니다.
- 택배·해상·항공·철도 parentage, SCD2 유효기간 중복, nullable 복합운송 fact grain 중복을 차단합니다.
- 최종 카탈로그는 FK 2,706개, CHECK 1,091개, 인덱스 3,500개, 트리거 2,301개이며 21개 rollback smoke를 통과했습니다.

## 운영 및 확장

- 이벤트/GPS/센서/감사 테이블에는 시각 BRIN, 핵심 조회 B-tree, 선택적 JSONB GIN을 둡니다.
- PostgreSQL 11의 partition FK 제약 때문에 최초 DDL은 일반 테이블로 두었습니다. 실제 수집량이 확정되면 `transport_events`, `gps_positions`, `sensor_readings`, audit/login 로그를 월별 range partition으로 이전하고 hot/cold retention 및 legal hold 절차를 함께 적용합니다.
- schema owner와 runtime role을 분리하고, connection pool의 매 transaction마다 서버 세션 hash로 `etms.bind_request_context(...)`를 호출합니다.
- 00~11은 운영 적용된 immutable baseline이며 `migrations/20260713_02`~`06`도 체크섬이 잠긴 운영 이력입니다. 일부 파일만 수동 적용하거나 적용된 SQL을 직접 고치지 않고 다음 번호의 forward-only migration을 추가합니다.

