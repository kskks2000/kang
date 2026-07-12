# DOMS 엔터프라이즈 오더관리 데이터베이스

이 디렉터리는 PostgreSQL 11용 `doms` 분산 오더관리시스템(Distributed Order Management System) 기준선입니다. Firebase 로그인/IAM부터 고객·채널·상품, 가격·프로모션, 다채널 주문 수집, ATP·소싱·예약·할당, 결제·세금·부정탐지, 분할이행·배송, 취소·반품·RMA·교환·보증, 조달·드롭십, 청구·정산·복식분개, 워크플로·통합·감사·개인정보 처리까지 한 트랜잭션으로 정의합니다.

현재 기준선은 번호가 붙은 11개 모듈, 433개 테이블입니다. `security_role_template.sql`은 DBA 검토용 수동 템플릿이며 자동 적용되지 않습니다.

## 모듈 구성

| 파일 | 테이블 | 범위 |
|---|---:|---|
| `00_foundation_auth.sql` | 49 | 테넌트·조직, `kang.users` 1:1 매핑, Firebase `password`/`google.com` 제공자, 계정 연결, 보호된 멤버십 발급·세션·요청 컨텍스트, RBAC, 로그인 감사, 공통 코드·파일·멱등성·outbox·보존·법적 보류 |
| `01_reference_partner_item.sql` | 38 | 국가·통화·단위·세금·결제조건, 거래처·주소·연락처, 품목·포장·바코드·번들·보관/위험물 기준정보 |
| `02_customer_channel_pricing.sql` | 51 | 고객·동의·신용, 판매채널/계정/스토어, 이행노드·운송사·권역, 가격표 버전·계약가격, 프로모션 버전·쿠폰 |
| `03_order_capture_lifecycle.sql` | 35 | 견적, 주문/라인, 고객·주소·연락처·상품 스냅샷, 가격·할인·세금·총액, 봉인 버전, 상태이력, hold, 검증, 변경·취소 |
| `04_orchestration_inventory.sql` | 36 | 주문 journey, ATP, inventory source/position/event, 소싱, fulfillment plan, 예약·할당·백오더·프리오더·대체품 |
| `05_payment_tax_risk.sql` | 42 | 결제 vault 참조, intent·승인·매입·취소·환불·분쟁, gift/store credit 원장, 세금 계산, fraud/risk, PSP 정산·대사 |
| `06_fulfillment_delivery.sql` | 40 | fulfillment order, shipment/package, lot/serial 증적, tracking, carrier booking·label·manifest, pickup·delivery·POD, digital/service fulfillment |
| `07_returns_service.sql` | 45 | 반품정책/적격성, RMA, return shipment·receipt·inspection·disposition, 환불계산, 교환·대체·보증, 고객서비스 case/SLA |
| `08_procurement_finance.sql` | 43 | 공급처 계약·발주·승인·입고, 드롭십·노드이전, invoice·credit memo, 채널 수수료·정산·payout, 회계기간·복식분개·ERP export |
| `09_workflow_integration_analytics.sql` | 54 | 상태전이, 알림, EDI/webhook/inbox, import/export/job/DLQ, 승인·SoD, 감사·접근로그·대사·KPI, DSAR·폐기 증적 |
| `10_operations_indexes_seed.sql` | 0 | 갱신·테넌트 불변·동일 테넌트 참조, JSON 비밀키 차단, RLS/FORCE RLS, append-only, FK/업무/BRIN 인덱스, 기준시드·권한 회수 |

## 핵심 업무 경계

하나의 상태나 테이블에 서로 다른 업무 사실을 합치지 않습니다.

- `sales_orders`는 고객과의 상거래 약속입니다. 결제, 위험, 이행, 반품 상태는 별도 상태축과 이력으로 보존합니다.
- `inventory_positions`는 이행노드·SKU 수준의 OMS 판매가능재고 투영입니다. WMS의 로케이션·lot·serial 물리재고 원장을 대체하지 않습니다.
- `fulfillment_orders`는 주문의 이행 지시, `shipments`는 운송 단위, `packages`는 포장 단위입니다. 주문 라인은 여러 노드·출고·상자로 분할될 수 있습니다.
- 결제 승인·매입·취소·환불, gift card/store credit, 회계분개는 성공한 사실을 덮어쓰지 않고 새 거래·반전·반대분개로 정정합니다.
- 교환품과 대체품은 원 반품행을 수정해 만드는 것이 아니라 별도의 정상 주문을 생성하고 관계 테이블로 연결합니다.
- 대용량 문서·라벨·POD·증빙 본문은 DB에 BLOB으로 넣지 않고 보호된 객체 URI, SHA-256, 크기와 최소화된 메타데이터만 저장합니다.

## Firebase 로그인과 사용자 모델

- Firebase Admin SDK가 백엔드에서 ID 토큰을 검증한 후에만 DOMS 사용자와 멤버십을 조회합니다.
- `doms.users.platform_user_id`는 `kang.users(id)`에 대한 필수·고유 `ON DELETE RESTRICT` FK입니다. DOMS는 별도 비밀번호 DB를 만들지 않습니다.
- 정규 Firebase 주체 키는 `(firebase_project_id, COALESCE(firebase_tenant_id, ''), firebase_uid)`입니다.
- `auth_identities.provider_code`는 `password`, `google.com`만 허용합니다. 이메일은 표시·검색값이며 계정 생성·자동 병합 키가 아닙니다.
- 비밀번호/해시, Firebase·Google ID/access/refresh token, 세션 원문, service-account JSON은 저장하지 않습니다. 서버 세션은 고엔트로피 handle의 해시만 저장합니다.
- 서로 다른 Firebase 주체 연결은 `account_link_requests`와 불변 `account_link_events`를 거치는 명시적 절차입니다.
- 인증 성공은 권한 부여가 아닙니다. 활성 `tenant_memberships`와 유효 RBAC/범위/SoD를 통과하지 못하면 DOMS 접근을 거부해야 합니다.

현재 애플리케이션의 일반 홈 진입과 별개로 DOMS API/화면은 반드시 fail-closed로 구현해야 합니다. `/auth/session` 실패 시 Firebase 사용자만으로 DOMS 화면을 여는 흐름은 허용하지 않습니다.

## 주문·금액·상태 불변조건

- 채널 외부 주문키와 요청 멱등키는 테넌트/채널 범위에서 고유합니다. 같은 키에 다른 request hash를 재사용할 수 없습니다.
- 주문 당시 고객·수취인·주소·상품·가격표·프로모션·세율 버전을 스냅샷으로 보존합니다.
- `order_status`, `payment_status`, `fulfillment_status`, `return_status`, `risk_status`를 독립적으로 관리합니다.
- 주문 헤더 합계와 라인·할인·비용·세금 합계는 확정/상태전이 시 DB 함수와 트리거가 대사합니다.
- `row_version`은 낙관적 잠금용이며, 최종/봉인 버전과 상태·업무 이벤트는 append-only입니다.
- PostgreSQL `CHECK`는 다른 행을 안전하게 참조하지 않으므로 자식 합계는 부모행 잠금, posting/finalization 함수, deferred constraint trigger로 검증합니다.

## 재고 약속과 동시성

- 재고 position 갱신과 예약/할당은 부모 position 행을 `FOR UPDATE`로 잠급니다.
- 활성 예약합은 ATP를 초과할 수 없고 ATP를 활성 예약 아래로 낮출 수 없습니다.
- 할당은 유효 예약과 fulfillment plan source split 범위를 초과할 수 없습니다. 예외는 승인자·승인시각·사유가 모두 있는 명시적 override만 허용합니다.
- 예약/할당 해제·소비·만료·취소는 행 삭제가 아니라 상태와 append-only 이벤트로 남깁니다.
- `sales_order_line → fulfillment_order_line → shipment_line → package_item` 수량은 각 단계에서 상위 잔량을 초과할 수 없습니다.

## 결제·환불·회계 통제

- 카드 PAN, CVV/CVC, PIN, track data는 저장하지 않습니다. PSP vault reference, brand/last4처럼 최소화된 비민감 표시값만 허용합니다.
- 성공/처리 중 capture 합계는 유효 승인 잔액을, refund 합계는 성공 capture 잔액을 넘지 못합니다.
- gift card/store credit와 payout/credit memo application은 부모행 잠금과 append-only 원장으로 동시 초과사용을 막습니다.
- invoice/credit memo/채널 settlement는 게시·승인 시 상세합계와 대사하고, 게시된 상업조건은 불변입니다.
- journal entry는 같은 통화의 차변·대변 합계가 일치해야 게시되며, 반전분개는 원분개의 GL 계정별 차변/대변을 정확히 반대로 구성해야 합니다.

## 반품·RMA 통제

- RMA 라인은 원 주문라인뿐 아니라 원 shipment line/package item 증적을 연결합니다.
- 활성/완료 승인수량은 출고수량에서 기존 반품을 뺀 잔량을 초과할 수 없습니다.
- 수령수량은 승인수량, 검사/처분수량은 수령수량, 환불 적격·환불수량과 금액은 정책 계산 결과를 초과할 수 없습니다.
- 초과수령·예외처분·정책 외 환불은 별도 승인과 불변 이벤트를 요구합니다.

## RLS와 런타임 역할

백엔드는 Firebase ID token을 검증한 뒤 고엔트로피 세션 handle의 SHA-256 해시로 세션을 발급합니다. 매 업무 트랜잭션 시작 시 그 해시를 binder에 전달하면 DB가 활성 Firebase 주체·DOMS 사용자·테넌트·멤버십·세션을 다시 검증하고 `(backend_pid, transaction_id)`에 묶인 짧은 요청 컨텍스트를 만듭니다.

```sql
BEGIN;
SELECT doms.bind_request_context(:sha256_session_handle_hash);
SELECT doms.current_tenant_id(), doms.current_doms_user_id();
-- tenant-scoped statements
COMMIT;
```

임의 `SET doms.tenant_id` 또는 `set_config()` 값은 정책에서 사용하지 않으며 테넌트를 바꾸지 못합니다. 같은 트랜잭션에서 다른 세션으로 전환할 수도 없습니다. 런타임 역할은 `NOSUPERUSER`, `NOCREATEROLE`, `NOBYPASSRLS`이며 스키마/테이블 소유자가 아니어야 합니다. 브라우저나 모바일 앱에 DB 자격증명을 배포하지 않습니다.

모든 `tenant_id` 기본 테이블에 RLS와 `FORCE ROW LEVEL SECURITY`를 적용합니다. nullable 전역 기준행은 읽기만 허용합니다. Firebase bootstrap·세션 발급은 `doms_authenticator`, 최초/관리자 멤버십 발급은 `doms_tenant_provisioner`, 일반 요청은 `doms_runtime`, 전역 로그인 실패/감사와 스케줄러는 각각 `doms_platform_logger`, `doms_global_job_runner`로 분리합니다. 현재 migration 계정 `kang`에는 `CREATEROLE`이 없으므로 DBA가 [`security_role_template.sql`](security_role_template.sql)을 검토·적용해야 하며, 애플리케이션은 절대 schema owner인 `kang`으로 접속하지 않습니다.

## 적용 전 확인

- 대상은 PostgreSQL **11.x**, `211.47.74.33:5432/dbkang`, 사용자 `kang`, 스키마 `doms`로 고정됩니다. 적용기는 설정 URL뿐 아니라 실제 세션의 DB·사용자·서버 IP·포트를 다시 검사합니다.
- `kang.users(id)`가 먼저 존재해야 합니다.
- 접속값은 루트 `.env`와 `backend/.env`를 읽는 `backend/app/settings.py`를 사용하며 자격증명을 출력하지 않습니다.
- `--dry-run`도 실제 DB에서 DDL을 실행한 뒤 롤백하므로 메타데이터 잠금을 획득합니다.
- 현재 운영 PostgreSQL이 TLS를 제공하지 않는다면 실제 DOMS 서비스 가동 전에 TLS/`hostssl`, CA 기반 `verify-full`, 승인된 VPN·사설망 또는 네트워크 allowlist와 자격증명 회전을 완료해야 합니다.
- PostgreSQL 11은 커뮤니티 지원이 종료되었습니다. 지원 중인 메이저 버전으로 업그레이드하는 별도 계획과 복구 연습이 필요합니다.
- PG11의 파티션 FK/고유키 제약 때문에 이번 기준선은 핵심 FK 대상을 일반 테이블과 BRIN/업무 인덱스로 구성했습니다. 대용량 이벤트·감사·분석 fact의 월별 파티션 전환은 보존정책, 전역 고유키, CDC·아카이브 절차를 함께 설계한 forward migration으로 진행합니다.

## 적용과 검증

저장소 루트에서 실행합니다.

```powershell
python .\scripts\apply_doms_schema.py --dry-run
python .\scripts\apply_doms_schema.py
python .\scripts\apply_doms_schema.py --verify-only
python .\scripts\smoke_test_doms_schema.py
```

적용기는 다음을 검증합니다.

- 00~10 모듈 누락·중복, PostgreSQL 11과 허용 대상
- SQL에서 정의한 테이블·인덱스·트리거, 모든 유효 FK/CHECK
- 변경 가능 테이블의 `touch_row`, 모든 tenant 테이블의 불변 trigger·RLS·FORCE RLS·정책
- 단일 FK의 동일 tenant 방어와 모든 FK의 선두 인덱스
- 정확한 append-only UPDATE/DELETE/TRUNCATE 보호
- 모든 JSONB scalar/path의 재귀 비밀·PAN 차단, `_encrypted` ciphertext envelope와 secret-manager reference 형식, 금지 인증/결제 컬럼 부재
- `kang.users` 매핑, 고정 Firebase project/tenant, 주체 고유키, `password`/`google.com` 제공자와 password subject 제한
- 보호된 membership→session→request context, legacy tenant GUC 위조 무효화
- `SECURITY DEFINER` 함수의 `pg_catalog, doms, pg_temp` 고정 search path, PUBLIC 및 기본 실행권한 회수
- 로컬 SQL 체크섬, PostgreSQL 카탈로그 지문, 기준시드 지문

`smoke_test_doms_schema.py`는 운영 스키마에서 테스트 데이터를 한 트랜잭션 안에 만들고 보호된 membership 발급→session 발급→request bind, GUC 위조·세션 전환 차단, 교차 tenant, append-only, 법적 보류, 복식분개 및 세션 자동 폐기를 검사한 뒤 전부 롤백합니다.

## 보존·개인정보·법적 검토

`data_retention_policies`의 전역 시드는 기술적 출발점이지 법률 의견이나 자동 폐기 명령이 아닙니다. 주문·결제·배송·반품·고객상담·전자상거래 기록의 실제 보존기간은 회사 법무·세무·개인정보 담당자가 확정해야 합니다.

- 활성 `legal_holds`가 적용된 엔터티에는 삭제·익명화·아카이브 결과를 기록할 수 없습니다.
- DSAR와 폐기는 요청, 항목, 승인, 실행, 건수대사, 객체 해시와 실패 증적을 분리합니다.
- 모든 JSONB 컬럼은 비밀번호·토큰·PAN/CVV·개인키 등 금지 키를 재귀 검사합니다.
- PII 조회는 `data_access_logs`, 보안/업무 변경은 append-only 감사 이벤트로 남기고 SIEM/장기 보관소로 반출해야 합니다.

## 변경 원칙

운영 배포 후 00~10 파일은 체크섬으로 잠긴 불변 기준선입니다. 기존 파일을 고쳐 이력을 덮어쓰지 말고 새 forward-only 마이그레이션과 체크섬을 추가합니다. 파괴적 롤백 대신 보정/반전 마이그레이션을 사용하고, 컬럼·테이블 삭제는 사용 중단·백필·애플리케이션 전환·보존 검토 후 진행합니다.

DDL만으로 Firebase 토큰 검증, API 권한 검사, 결제기관 호출, WMS/ERP/마켓플레이스 어댑터, 키관리, SIEM, 백업/PITR, 부하·장애·복구 훈련이 완성되지는 않습니다. 운영 전 별도 구현과 검증이 필요합니다.

## 설계 참고자료

- [Firebase Admin ID token 검증](https://firebase.google.com/docs/auth/admin/verify-id-tokens)
- [Firebase 사용자/provider 관리](https://firebase.google.com/docs/auth/admin/manage-users)
- [PostgreSQL 11 Row Security](https://www.postgresql.org/docs/11/ddl-rowsecurity.html)
- [PostgreSQL 11 제약조건](https://www.postgresql.org/docs/11/ddl-constraints.html)
- [Stripe 멱등 요청](https://docs.stripe.com/api/idempotent_requests)
- [PCI SSC 민감 인증정보 저장 금지 FAQ](https://www.pcisecuritystandards.org/faqs/1533/)
- [OWASP Logging Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Logging_Cheat_Sheet.html)
