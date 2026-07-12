# DTMS 데이터베이스

이 디렉터리는 PostgreSQL 11 전용 엔터프라이즈 TMS 스키마입니다. 파일명 순서대로 하나의 트랜잭션에서 실행하며, 직접 일부 파일만 적용하지 않습니다.

```powershell
cd <repository-root>
.\backend\.venv\Scripts\python.exe .\scripts\apply_dtms_schema.py
.\backend\.venv\Scripts\python.exe .\scripts\apply_dtms_schema.py --verify-only
```

- `00`: 테넌트, 조직, Firebase IAM/RBAC, 공통 플랫폼
- `01`: 표준코드, 파트너, 거점, 품목, 기사/차량/장비, 노선
- `02`: 계약, 요율, 할증, 견적, SLA, 운송사 용량
- `03`: 운송주문, 정차, 화물라인, Handling Unit, 회수자산
- `04`: 계획, 합배송, Shipment/Leg/Run, 배정, 입찰, 배차
- `05`: 스케줄 운송, 컨테이너, 예약, 통관/운송문서
- `06`: 실행, 관제, GPS/센서, POD, 예외/사고
- `07`: 실적, KPI/SLA, 탄소, 클레임, 분석 Fact
- `08`: 운임, 미지급비용, 청구, 세금계산서, 정산, 회계, 승인
- `09`: EDI/알림/배치, RLS, 테넌트 무결성, 인덱스, 기준 시드

운영 애플리케이션은 테이블 소유자 계정을 사용하지 말고 DBA가 만든 별도 `NOBYPASSRLS` 역할을 사용해야 합니다. 매 트랜잭션에서 검증된 Firebase 사용자 membership을 기준으로 다음 값을 먼저 설정합니다.

```sql
SET LOCAL dtms.tenant_id = '<검증된 tenant uuid>';
```

DBA 역할 예시는 `security_role_template.sql`에 있으며 자동 적용되지 않습니다.
