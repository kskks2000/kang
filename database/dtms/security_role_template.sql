-- DBA 전용 예시입니다. scripts/apply_dtms_schema.py가 실행하지 않습니다.
-- 현재 kang 계정에는 CREATEROLE 권한이 없으므로 권한 있는 DBA가 검토 후 실행해야 합니다.

DO $block$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'dtms_app') THEN
        CREATE ROLE dtms_app
            NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;
    END IF;
END;
$block$;

GRANT USAGE ON SCHEMA dtms TO dtms_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA dtms TO dtms_app;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA dtms TO dtms_app;

-- 로그인 가능한 별도 런타임 역할을 만든 뒤 이 역할만 부여합니다.
-- CREATE ROLE dtms_runtime LOGIN ...;
-- GRANT dtms_app TO dtms_runtime;
-- 연결 풀은 트랜잭션마다 Firebase UID와 membership을 서버에서 확인한 뒤
-- SET LOCAL dtms.tenant_id를 실행해야 하며 클라이언트가 보낸 tenant_id를 신뢰하면 안 됩니다.

