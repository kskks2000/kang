-- DOMS enterprise OMS schema - final operational hardening, RLS, indexes, and seeds.
-- PostgreSQL 11 compatible. Applied last, after all 00-09 modules, in one transaction.
-- This module intentionally creates no tables.

CREATE OR REPLACE FUNCTION doms.prevent_tenant_change()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    IF OLD.tenant_id IS DISTINCT FROM NEW.tenant_id THEN
        RAISE EXCEPTION 'tenant_id is immutable for %.%', TG_TABLE_SCHEMA, TG_TABLE_NAME
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.current_tenant_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, doms, pg_temp
AS $function$
    SELECT request_context.bound_tenant_id
    FROM doms.request_contexts request_context
    JOIN doms.user_sessions session_row
      ON session_row.id = request_context.session_id
     AND session_row.user_id = request_context.bound_user_id
     AND session_row.active_tenant_id = request_context.bound_tenant_id
     AND session_row.active_membership_id = request_context.bound_membership_id
    JOIN doms.users doms_user ON doms_user.id = session_row.user_id
    JOIN doms.auth_identities identity_row
      ON identity_row.id = session_row.auth_identity_id
     AND identity_row.user_id = session_row.user_id
    JOIN doms.tenants tenant_row ON tenant_row.id = session_row.active_tenant_id
    JOIN kang.users platform_user ON platform_user.id = doms_user.platform_user_id
    WHERE request_context.backend_pid = pg_backend_pid()
      AND request_context.transaction_id = txid_current()
      AND request_context.context_expires_at > statement_timestamp()
      AND session_row.session_status = 'ACTIVE'
      AND session_row.revoked_at IS NULL
      AND session_row.expires_at > statement_timestamp()
      AND doms_user.status = 'ACTIVE'
      AND doms_user.deleted_at IS NULL
      AND identity_row.disabled_at IS NULL
      AND tenant_row.status = 'ACTIVE'
      AND tenant_row.deleted_at IS NULL
      AND platform_user.firebase_uid = doms_user.firebase_uid
      AND platform_user.status::text = 'active'
      AND platform_user.is_active
      AND platform_user.deleted_at IS NULL
      AND platform_user.locked_at IS NULL;
$function$;

COMMENT ON FUNCTION doms.current_tenant_id() IS
    'Fail-closed tenant identity derived only from a protected, session-validated backend_pid + transaction context.';

CREATE OR REPLACE FUNCTION doms.current_doms_user_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, doms, pg_temp
AS $function$
    SELECT request_context.bound_user_id
    FROM doms.request_contexts request_context
    JOIN doms.user_sessions session_row
      ON session_row.id = request_context.session_id
     AND session_row.user_id = request_context.bound_user_id
     AND session_row.active_tenant_id = request_context.bound_tenant_id
     AND session_row.active_membership_id = request_context.bound_membership_id
    JOIN doms.users doms_user ON doms_user.id = session_row.user_id
    JOIN doms.auth_identities identity_row
      ON identity_row.id = session_row.auth_identity_id
     AND identity_row.user_id = session_row.user_id
    JOIN doms.tenants tenant_row ON tenant_row.id = session_row.active_tenant_id
    JOIN kang.users platform_user ON platform_user.id = doms_user.platform_user_id
    WHERE request_context.backend_pid = pg_backend_pid()
      AND request_context.transaction_id = txid_current()
      AND request_context.context_expires_at > statement_timestamp()
      AND session_row.session_status = 'ACTIVE'
      AND session_row.revoked_at IS NULL
      AND session_row.expires_at > statement_timestamp()
      AND doms_user.status = 'ACTIVE'
      AND doms_user.deleted_at IS NULL
      AND identity_row.disabled_at IS NULL
      AND tenant_row.status = 'ACTIVE'
      AND tenant_row.deleted_at IS NULL
      AND platform_user.firebase_uid = doms_user.firebase_uid
      AND platform_user.status::text = 'active'
      AND platform_user.is_active
      AND platform_user.deleted_at IS NULL
      AND platform_user.locked_at IS NULL;
$function$;

REVOKE ALL ON FUNCTION doms.current_tenant_id() FROM PUBLIC;
REVOKE ALL ON FUNCTION doms.current_doms_user_id() FROM PUBLIC;

CREATE OR REPLACE FUNCTION doms.is_valid_ciphertext_envelope(p_value text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
STRICT
PARALLEL SAFE
AS $function$
    SELECT p_value ~ '^enc:v1:(gcp-kms|aws-kms|azure-kv|vault)/[A-Za-z0-9._/-]{6,255}:[A-Za-z0-9_-]{16,}={0,2}$'
       AND p_value !~ '[[:space:]]';
$function$;

CREATE OR REPLACE FUNCTION doms.is_valid_secret_reference(p_value text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
STRICT
PARALLEL SAFE
AS $function$
    SELECT p_value !~ '[[:space:]@?#]'
       AND NOT doms.text_contains_forbidden_secret(p_value)
       AND (
           p_value ~ '^projects/[A-Za-z0-9._-]+/secrets/[A-Za-z0-9._-]+/versions/([A-Za-z0-9._-]+)$'
           OR p_value ~ '^(gcp-sm|gcp-kms|aws-sm|aws-kms|azure-kv|vault)://[A-Za-z0-9._:/-]+$'
       );
$function$;

REVOKE ALL ON FUNCTION doms.is_valid_ciphertext_envelope(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION doms.is_valid_secret_reference(text) FROM PUBLIC;

CREATE OR REPLACE FUNCTION doms.enforce_same_tenant_fk()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, doms, pg_temp
AS $function$
DECLARE
    child_reference uuid;
    parent_tenant uuid;
    selected_row_count bigint;
BEGIN
    child_reference := NULLIF(to_jsonb(NEW) ->> TG_ARGV[0], '')::uuid;
    IF child_reference IS NULL THEN
        RETURN NEW;
    END IF;

    EXECUTE format('SELECT tenant_id FROM %I.%I WHERE id = $1', TG_ARGV[1], TG_ARGV[2])
       INTO parent_tenant
       USING child_reference;
    GET DIAGNOSTICS selected_row_count = ROW_COUNT;

    IF selected_row_count = 0 THEN
        RAISE EXCEPTION 'Referenced parent is unavailable: %.% -> %.%',
            TG_TABLE_SCHEMA, TG_TABLE_NAME, TG_ARGV[1], TG_ARGV[2]
            USING ERRCODE = '23503';
    END IF;
    -- NULL parent tenant is an explicitly global reference master.
    IF parent_tenant IS NOT NULL AND parent_tenant IS DISTINCT FROM NEW.tenant_id THEN
        RAISE EXCEPTION 'Cross-tenant reference rejected: %.% -> %.%',
            TG_TABLE_SCHEMA, TG_TABLE_NAME, TG_ARGV[1], TG_ARGV[2]
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.prevent_append_only_change()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    RAISE EXCEPTION '%.% is append-only; create a correction, reversal, or new event instead of %',
        TG_TABLE_SCHEMA, TG_TABLE_NAME, TG_OP
        USING ERRCODE = '55000';
END;
$function$;

CREATE OR REPLACE FUNCTION doms.prevent_append_only_truncate()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    RAISE EXCEPTION '%.% is append-only and cannot be truncated',
        TG_TABLE_SCHEMA, TG_TABLE_NAME
        USING ERRCODE = '55000';
END;
$function$;

CREATE OR REPLACE FUNCTION doms.protect_message_core()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    old_core jsonb;
    new_core jsonb;
    argument_no integer;
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION '%.% message/envelope rows cannot be deleted',
            TG_TABLE_SCHEMA, TG_TABLE_NAME USING ERRCODE = '55000';
    END IF;
    old_core := to_jsonb(OLD);
    new_core := to_jsonb(NEW);
    IF TG_NARGS > 0 THEN
        FOR argument_no IN 0 .. TG_NARGS - 1 LOOP
            old_core := old_core - TG_ARGV[argument_no];
            new_core := new_core - TG_ARGV[argument_no];
        END LOOP;
    END IF;
    IF old_core IS DISTINCT FROM new_core THEN
        RAISE EXCEPTION '%.% immutable payload, identity, or routing fields cannot change',
            TG_TABLE_SCHEMA, TG_TABLE_NAME USING ERRCODE = '55000';
    END IF;
    RETURN NEW;
END;
$function$;

-- Install one canonical optimistic-lock trigger on every mutable table carrying
-- both row_version and updated_at. Existing same-name module triggers are replaced.
DO $block$
DECLARE
    target record;
BEGIN
    FOR target IN
        SELECT DISTINCT columns.table_schema, columns.table_name
        FROM information_schema.columns columns
        JOIN information_schema.columns updated_column
          ON updated_column.table_schema = columns.table_schema
         AND updated_column.table_name = columns.table_name
         AND updated_column.column_name = 'updated_at'
        JOIN information_schema.tables tables
          ON tables.table_schema = columns.table_schema
         AND tables.table_name = columns.table_name
         AND tables.table_type = 'BASE TABLE'
        WHERE columns.table_schema = 'doms'
          AND columns.column_name = 'row_version'
    LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS trg_touch_row ON %I.%I', target.table_schema, target.table_name);
        EXECUTE format(
            'CREATE TRIGGER trg_touch_row BEFORE UPDATE ON %I.%I '
            'FOR EACH ROW EXECUTE PROCEDURE doms.touch_row()',
            target.table_schema, target.table_name
        );
    END LOOP;
END;
$block$;

-- Every JSONB payload/configuration column is guarded recursively so generic
-- metadata cannot become an alternate password, token, PAN, or private-key store.
DO $block$
DECLARE
    target record;
    constraint_name text;
BEGIN
    FOR target IN
        SELECT namespace_row.nspname AS schema_name,
               relation.relname AS table_name,
               attribute.attname AS column_name,
               relation.oid AS table_oid
        FROM pg_attribute attribute
        JOIN pg_class relation ON relation.oid = attribute.attrelid
        JOIN pg_namespace namespace_row ON namespace_row.oid = relation.relnamespace
        WHERE namespace_row.nspname = 'doms'
          AND relation.relkind = 'r'
          AND attribute.attnum > 0
          AND NOT attribute.attisdropped
          AND attribute.atttypid = 'jsonb'::regtype
        ORDER BY relation.relname, attribute.attnum
    LOOP
        constraint_name := 'ck_json_secret_' || substr(
            md5(target.table_name || '.' || target.column_name), 1, 12
        );
        IF NOT EXISTS (
            SELECT 1
            FROM pg_constraint constraint_row
            WHERE constraint_row.conrelid = target.table_oid
              AND constraint_row.conname = constraint_name
        ) THEN
            EXECUTE format(
                'ALTER TABLE %I.%I ADD CONSTRAINT %I CHECK '
                || '(%I IS NULL OR NOT doms.jsonb_contains_forbidden_secret_key(%I))',
                target.schema_name, target.table_name, constraint_name,
                target.column_name, target.column_name
            );
        END IF;
    END LOOP;
END;
$block$;

-- Ciphertext and secret-reference columns use explicit envelopes. This rejects
-- plaintext PII and prevents a reference column from becoming an inline secret.
DO $block$
DECLARE
    target record;
    constraint_name text;
    validation_function text;
BEGIN
    FOR target IN
        SELECT namespace_row.nspname AS schema_name,
               relation.relname AS table_name,
               attribute.attname AS column_name,
               relation.oid AS table_oid,
               attribute.attnum
        FROM pg_attribute attribute
        JOIN pg_class relation ON relation.oid = attribute.attrelid
        JOIN pg_namespace namespace_row ON namespace_row.oid = relation.relnamespace
        WHERE namespace_row.nspname = 'doms'
          AND relation.relkind = 'r'
          AND attribute.attnum > 0
          AND NOT attribute.attisdropped
          AND attribute.atttypid IN ('text'::regtype, 'varchar'::regtype, 'bpchar'::regtype)
          AND (
              attribute.attname LIKE '%\_encrypted' ESCAPE '\'
              OR attribute.attname LIKE '%\_secret\_ref' ESCAPE '\'
              OR attribute.attname = 'secret_reference'
          )
        ORDER BY relation.relname, attribute.attnum
    LOOP
        validation_function := CASE
            WHEN target.column_name LIKE '%\_encrypted' ESCAPE '\'
                THEN 'doms.is_valid_ciphertext_envelope'
            ELSE 'doms.is_valid_secret_reference'
        END;
        constraint_name := CASE
            WHEN target.column_name LIKE '%\_encrypted' ESCAPE '\'
                THEN 'ck_ciphertext_'
            ELSE 'ck_secret_ref_'
        END || substr(md5(target.table_name || '.' || target.column_name), 1, 12);

        IF NOT EXISTS (
            SELECT 1
            FROM pg_constraint constraint_row
            WHERE constraint_row.conrelid = target.table_oid
              AND constraint_row.contype = 'c'
              AND target.attnum = ANY(constraint_row.conkey)
              AND pg_get_constraintdef(constraint_row.oid) LIKE
                  '%' || validation_function || '%'
        ) THEN
            EXECUTE format(
                'ALTER TABLE %I.%I ADD CONSTRAINT %I CHECK '
                || '(%I IS NULL OR %s(%I))',
                target.schema_name, target.table_name, constraint_name,
                target.column_name, validation_function, target.column_name
            );
        END IF;
    END LOOP;
END;
$block$;

DO $block$
DECLARE
    missing_count integer;
BEGIN
    SELECT count(*) INTO missing_count
    FROM pg_attribute attribute
    JOIN pg_class relation ON relation.oid = attribute.attrelid
    JOIN pg_namespace namespace_row ON namespace_row.oid = relation.relnamespace
    WHERE namespace_row.nspname = 'doms'
      AND relation.relkind = 'r'
      AND attribute.attnum > 0
      AND NOT attribute.attisdropped
      AND attribute.atttypid IN ('text'::regtype, 'varchar'::regtype, 'bpchar'::regtype)
      AND (
          attribute.attname LIKE '%\_encrypted' ESCAPE '\'
          OR attribute.attname LIKE '%\_secret\_ref' ESCAPE '\'
          OR attribute.attname = 'secret_reference'
      )
      AND NOT EXISTS (
          SELECT 1
          FROM pg_constraint constraint_row
          WHERE constraint_row.conrelid = relation.oid
            AND constraint_row.contype = 'c'
            AND attribute.attnum = ANY(constraint_row.conkey)
            AND (
                (attribute.attname LIKE '%\_encrypted' ESCAPE '\'
                 AND pg_get_constraintdef(constraint_row.oid)
                     LIKE '%doms.is_valid_ciphertext_envelope%')
                OR
                (attribute.attname NOT LIKE '%\_encrypted' ESCAPE '\'
                 AND pg_get_constraintdef(constraint_row.oid)
                     LIKE '%doms.is_valid_secret_reference%')
            )
      );
    IF missing_count <> 0 THEN
        RAISE EXCEPTION '% encrypted/secret-reference columns lack envelope checks',
            missing_count;
    END IF;
END;
$block$;

-- Deterministic global reference baseline. Tenant-specific overrides use separate
-- rows with tenant_id populated; baseline rows are never rewritten by this module.
INSERT INTO doms.currencies (
    currency_code, currency_name, numeric_code,
    fraction_digits, rounding_increment, is_active
) VALUES
    ('KRW','Korean Won','410',0,1,true),
    ('USD','US Dollar','840',2,0.01,true),
    ('EUR','Euro','978',2,0.01,true),
    ('JPY','Japanese Yen','392',0,1,true),
    ('CNY','Chinese Yuan Renminbi','156',2,0.01,true)
ON CONFLICT (currency_code) DO NOTHING;

INSERT INTO doms.countries (
    country_code, country_code3, numeric_code,
    country_name_en, country_name_local, default_currency_code, is_active
) VALUES
    ('KR','KOR','410','Korea, Republic of','대한민국','KRW',true),
    ('US','USA','840','United States','United States','USD',true),
    ('JP','JPN','392','Japan','日本','JPY',true),
    ('CN','CHN','156','China','中国','CNY',true),
    ('DE','DEU','276','Germany','Deutschland','EUR',true)
ON CONFLICT (country_code) DO NOTHING;

INSERT INTO doms.units_of_measure (
    uom_code, uom_name, dimension, si_factor, decimal_places, is_active
) VALUES
    ('EA','Each','COUNT',1,0,true),
    ('KG','Kilogram','MASS',1,6,true),
    ('G','Gram','MASS',0.001,6,true),
    ('M','Meter','LENGTH',1,6,true),
    ('CM','Centimeter','LENGTH',0.01,6,true),
    ('MM','Millimeter','LENGTH',0.001,6,true),
    ('L','Liter','VOLUME',0.001,6,true),
    ('ML','Milliliter','VOLUME',0.000001,6,true)
ON CONFLICT (uom_code) DO NOTHING;

INSERT INTO doms.permissions (
    permission_code, permission_name, module_code, action_code,
    description, is_sensitive, is_active
) VALUES
    ('orders.read','Read orders','ORDERS','READ','Read order headers, lines, lifecycle, and customer-safe projections.',false,true),
    ('orders.create','Create orders','ORDERS','CREATE','Create and submit new orders through controlled order-capture flows.',true,true),
    ('orders.update','Update orders','ORDERS','UPDATE','Request or apply permitted pre-fulfillment order changes.',true,true),
    ('orders.cancel','Cancel orders','ORDERS','CANCEL','Request or approve order cancellation within policy.',true,true),
    ('pricing.override','Override pricing','PRICING','OVERRIDE','Override calculated prices or discounts with auditable reason and approval.',true,true),
    ('inventory.read','Read inventory','INVENTORY','READ','Read ATP, inventory positions, reservations, and sourcing results.',false,true),
    ('inventory.reserve','Reserve inventory','INVENTORY','RESERVE','Create, release, or reallocate inventory reservations.',true,true),
    ('inventory.override','Override inventory controls','INVENTORY','OVERRIDE','Override allocation, sourcing, or reservation policy under approval.',true,true),
    ('payment.read','Read payment records','PAYMENT','READ','Read masked payment, capture, refund, dispute, and settlement data.',true,true),
    ('payment.capture','Capture payments','PAYMENT','CAPTURE','Authorize or capture customer payment through approved providers.',true,true),
    ('payment.refund','Refund payments','PAYMENT','REFUND','Approve or execute a payment refund within policy.',true,true),
    ('risk.review','Review risk cases','RISK','REVIEW','Review fraud assessments and disposition assigned risk cases.',true,true),
    ('fulfillment.read','Read fulfillment','FULFILLMENT','READ','Read fulfillment orders, shipments, delivery, and pickup state.',false,true),
    ('fulfillment.operate','Operate fulfillment','FULFILLMENT','OPERATE','Release, pick, pack, ship, deliver, or confirm fulfillment work.',true,true),
    ('returns.read','Read returns','RETURNS','READ','Read return, inspection, disposition, and refund coordination data.',false,true),
    ('returns.approve','Approve returns','RETURNS','APPROVE','Approve return acceptance, disposition, or exceptional resolution.',true,true),
    ('workflow.approve','Act on approvals','WORKFLOW','APPROVE','Approve or reject workflow tasks assigned under policy.',true,true),
    ('integration.manage','Manage integrations','INTEGRATION','MANAGE','Manage endpoints and controlled retry or dead-letter operations.',true,true),
    ('iam.manage','Manage tenant access','IAM','MANAGE','Manage tenant memberships, roles, and scoped assignments subject to SoD.',true,true),
    ('audit.read','Read audit evidence','AUDIT','READ','Read immutable security, business, and regulated access evidence.',true,true)
ON CONFLICT (permission_code) DO NOTHING;

WITH seed(role_code, role_name, description) AS (
    VALUES
        ('DOMS_ADMIN','DOMS Administrator','Tenant IAM, integration, and order administration without payment/refund or inventory override authority.'),
        ('ORDER_MANAGER','Order Manager','Order lifecycle, pricing exception, reservation, return, and workflow authority.'),
        ('CUSTOMER_SERVICE','Customer Service','Customer-facing order maintenance with read-only payment and fulfillment visibility.'),
        ('PAYMENT_OPERATOR','Payment Operator','Payment visibility and capture authority; refunds require separate explicit assignment.'),
        ('FULFILLMENT_OPERATOR','Fulfillment Operator','Inventory reservation and fulfillment execution authority.'),
        ('AUDITOR','Auditor','Read-only operational and immutable audit evidence access.'),
        ('INTEGRATION_OPERATOR','Integration Operator','Integration operations with minimal order visibility.'),
        ('READ_ONLY','Read Only','Read-only cross-functional operational visibility without audit access.')
)
INSERT INTO doms.roles (
    tenant_id, role_code, role_name, description, is_system_role, is_active
)
SELECT NULL, seed.role_code, seed.role_name, seed.description, true, true
FROM seed
WHERE NOT EXISTS (
    SELECT 1
    FROM doms.roles existing
    WHERE existing.tenant_id IS NULL
      AND existing.role_code = seed.role_code
);

-- Default grants deliberately preserve separation of duties. High-risk permissions
-- (refund, inventory override, and risk review) require an explicit tenant assignment.
WITH grants(role_code, permission_code) AS (
    VALUES
        ('DOMS_ADMIN','orders.read'),
        ('DOMS_ADMIN','orders.create'),
        ('DOMS_ADMIN','orders.update'),
        ('DOMS_ADMIN','integration.manage'),
        ('DOMS_ADMIN','iam.manage'),
        ('DOMS_ADMIN','audit.read'),
        ('ORDER_MANAGER','orders.read'),
        ('ORDER_MANAGER','orders.create'),
        ('ORDER_MANAGER','orders.update'),
        ('ORDER_MANAGER','orders.cancel'),
        ('ORDER_MANAGER','pricing.override'),
        ('ORDER_MANAGER','inventory.read'),
        ('ORDER_MANAGER','inventory.reserve'),
        ('ORDER_MANAGER','fulfillment.read'),
        ('ORDER_MANAGER','returns.read'),
        ('ORDER_MANAGER','returns.approve'),
        ('ORDER_MANAGER','workflow.approve'),
        ('CUSTOMER_SERVICE','orders.read'),
        ('CUSTOMER_SERVICE','orders.update'),
        ('CUSTOMER_SERVICE','orders.cancel'),
        ('CUSTOMER_SERVICE','payment.read'),
        ('CUSTOMER_SERVICE','fulfillment.read'),
        ('CUSTOMER_SERVICE','returns.read'),
        ('PAYMENT_OPERATOR','orders.read'),
        ('PAYMENT_OPERATOR','payment.read'),
        ('PAYMENT_OPERATOR','payment.capture'),
        ('FULFILLMENT_OPERATOR','orders.read'),
        ('FULFILLMENT_OPERATOR','inventory.read'),
        ('FULFILLMENT_OPERATOR','inventory.reserve'),
        ('FULFILLMENT_OPERATOR','fulfillment.read'),
        ('FULFILLMENT_OPERATOR','fulfillment.operate'),
        ('FULFILLMENT_OPERATOR','returns.read'),
        ('AUDITOR','orders.read'),
        ('AUDITOR','inventory.read'),
        ('AUDITOR','payment.read'),
        ('AUDITOR','fulfillment.read'),
        ('AUDITOR','returns.read'),
        ('AUDITOR','audit.read'),
        ('INTEGRATION_OPERATOR','orders.read'),
        ('INTEGRATION_OPERATOR','integration.manage'),
        ('READ_ONLY','orders.read'),
        ('READ_ONLY','inventory.read'),
        ('READ_ONLY','payment.read'),
        ('READ_ONLY','fulfillment.read'),
        ('READ_ONLY','returns.read')
)
INSERT INTO doms.role_permissions (
    tenant_id, role_id, permission_id, granted_at,
    row_version, created_at, updated_at
)
SELECT NULL, role_row.id, permission_row.id, now(), 1, now(), now()
FROM grants
JOIN doms.roles role_row
  ON role_row.tenant_id IS NULL
 AND role_row.role_code = grants.role_code
JOIN doms.permissions permission_row
  ON permission_row.permission_code = grants.permission_code
WHERE NOT EXISTS (
    SELECT 1
    FROM doms.role_permissions existing
    WHERE existing.role_id = role_row.id
      AND existing.permission_id = permission_row.id
);

WITH seed(
    order_type_code, order_type_name, lifecycle_model,
    requires_payment, requires_fulfillment,
    allows_partial_fulfillment, allows_backorder, allows_preorder
) AS (
    VALUES
        ('STANDARD','Standard Order','STANDARD',true,true,true,true,false),
        ('SUBSCRIPTION','Subscription Order','SUBSCRIPTION',true,true,true,true,false),
        ('PREORDER','Preorder','PREORDER',true,true,true,true,true),
        ('EXCHANGE','Exchange Order','EXCHANGE',false,true,true,false,false),
        ('REPLACEMENT','Replacement Order','REPLACEMENT',false,true,true,false,false),
        ('INTERNAL','Internal Order','INTERNAL',false,true,true,true,false)
)
INSERT INTO doms.order_types (
    tenant_id, order_type_code, order_type_name, lifecycle_model,
    requires_payment, requires_fulfillment, allows_partial_fulfillment,
    allows_backorder, allows_preorder, is_active
)
SELECT NULL, seed.order_type_code, seed.order_type_name, seed.lifecycle_model,
       seed.requires_payment, seed.requires_fulfillment,
       seed.allows_partial_fulfillment, seed.allows_backorder,
       seed.allows_preorder, true
FROM seed
WHERE NOT EXISTS (
    SELECT 1
    FROM doms.order_types existing
    WHERE existing.tenant_id IS NULL
      AND existing.order_type_code = seed.order_type_code
);

WITH seed(entity_type, retention_days, anonymize_after_days, purge_strategy, legal_basis) AS (
    VALUES
        ('authentication_events',365,180,'ANONYMIZE','Security baseline; validate against company policy, incident-response needs, and applicable law.'),
        ('orders',3650,1095,'ANONYMIZE','Commerce evidence baseline; validate tax, consumer-protection, and limitation requirements by jurisdiction.'),
        ('payments',3650,1095,'ANONYMIZE','Financial evidence baseline; retain only masked or tokenized payment references.'),
        ('fulfillment',2555,1095,'ANONYMIZE','Delivery evidence baseline; validate carrier claims and consumer-protection requirements.'),
        ('returns',2555,1095,'ANONYMIZE','Returns and warranty evidence baseline; validate product-specific obligations.'),
        ('audit_events',3650,NULL,'ARCHIVE','Security and control evidence baseline; archive immutably and apply legal hold before purge.'),
        ('customer_pii',1095,1095,'ANONYMIZE','Privacy baseline; shorten where purpose or consent expires and honor legal hold exceptions.'),
        ('integration_messages',365,180,'ANONYMIZE','Operational troubleshooting baseline; payload minimization and external object lifecycle remain mandatory.')
)
INSERT INTO doms.data_retention_policies (
    tenant_id, entity_type, retention_days, anonymize_after_days,
    purge_strategy, legal_basis, is_active
)
SELECT NULL, seed.entity_type, seed.retention_days, seed.anonymize_after_days,
       seed.purge_strategy, seed.legal_basis, true
FROM seed
WHERE NOT EXISTS (
    SELECT 1
    FROM doms.data_retention_policies existing
    WHERE existing.tenant_id IS NULL
      AND existing.entity_type = seed.entity_type
);

-- Canonical order-level rollup states. Detailed subsystem tables retain their own
-- finer-grained state machines while these definitions drive UI/workflow metadata.
WITH seed(
    entity_type, status_code, status_name, category,
    terminal_status, success_status, sort_order
) AS (
    VALUES
        ('SALES_ORDER','DRAFT','Draft','OPEN',false,false,10),
        ('SALES_ORDER','VALIDATING','Validating','OPEN',false,false,20),
        ('SALES_ORDER','VALIDATION_FAILED','Validation Failed','EXCEPTION',false,false,30),
        ('SALES_ORDER','SUBMITTED','Submitted','OPEN',false,false,40),
        ('SALES_ORDER','CONFIRMED','Confirmed','OPEN',false,false,50),
        ('SALES_ORDER','CHANGE_PENDING','Change Pending','PENDING',false,false,60),
        ('SALES_ORDER','ON_HOLD','On Hold','HOLD',false,false,70),
        ('SALES_ORDER','PARTIALLY_FULFILLED','Partially Fulfilled','IN_PROGRESS',false,false,80),
        ('SALES_ORDER','FULFILLED','Fulfilled','SUCCESS',false,true,90),
        ('SALES_ORDER','COMPLETED','Completed','SUCCESS',true,true,100),
        ('SALES_ORDER','CANCELLATION_PENDING','Cancellation Pending','PENDING',false,false,110),
        ('SALES_ORDER','CANCELLED','Cancelled','CANCELLED',true,false,120),
        ('SALES_ORDER','CLOSED','Closed','CLOSED',true,true,130),
        ('PAYMENT','NOT_REQUIRED','Not Required','SUCCESS',true,true,10),
        ('PAYMENT','PENDING','Pending','OPEN',false,false,20),
        ('PAYMENT','AUTHORIZED','Authorized','IN_PROGRESS',false,false,30),
        ('PAYMENT','PARTIALLY_PAID','Partially Paid','IN_PROGRESS',false,false,40),
        ('PAYMENT','PAID','Paid','SUCCESS',true,true,50),
        ('PAYMENT','PARTIALLY_REFUNDED','Partially Refunded','IN_PROGRESS',false,false,60),
        ('PAYMENT','REFUNDED','Refunded','CLOSED',true,true,70),
        ('PAYMENT','VOIDED','Voided','CANCELLED',true,false,80),
        ('PAYMENT','FAILED','Failed','EXCEPTION',true,false,90),
        ('FULFILLMENT','UNPLANNED','Unplanned','OPEN',false,false,10),
        ('FULFILLMENT','PLANNING','Planning','OPEN',false,false,20),
        ('FULFILLMENT','PARTIALLY_ALLOCATED','Partially Allocated','IN_PROGRESS',false,false,30),
        ('FULFILLMENT','ALLOCATED','Allocated','IN_PROGRESS',false,false,40),
        ('FULFILLMENT','RELEASED','Released','IN_PROGRESS',false,false,50),
        ('FULFILLMENT','PARTIALLY_FULFILLED','Partially Fulfilled','IN_PROGRESS',false,false,60),
        ('FULFILLMENT','FULFILLED','Fulfilled','SUCCESS',true,true,70),
        ('FULFILLMENT','DELIVERY_FAILED','Delivery Failed','EXCEPTION',false,false,80),
        ('FULFILLMENT','CANCELLED','Cancelled','CANCELLED',true,false,90),
        ('RETURN','NONE','No Return','OPEN',false,false,10),
        ('RETURN','REQUESTED','Return Requested','OPEN',false,false,20),
        ('RETURN','PARTIALLY_RETURNED','Partially Returned','IN_PROGRESS',false,false,30),
        ('RETURN','RETURNED','Returned','SUCCESS',false,true,40),
        ('RETURN','CLOSED','Return Closed','CLOSED',true,true,50)
)
INSERT INTO doms.status_definitions (
    tenant_id, entity_type, status_code, status_name, category,
    terminal_status, success_status, sort_order, is_active
)
SELECT NULL, seed.entity_type, seed.status_code, seed.status_name, seed.category,
       seed.terminal_status, seed.success_status, seed.sort_order, true
FROM seed
WHERE NOT EXISTS (
    SELECT 1
    FROM doms.status_definitions existing
    WHERE existing.tenant_id IS NULL
      AND existing.entity_type = seed.entity_type
      AND existing.status_code = seed.status_code
);

WITH seed(
    reason_group, reason_code, reason_name,
    requires_note, requires_approval
) AS (
    VALUES
        ('ORDER_CANCEL','CUSTOMER_REQUEST','Customer Request',false,false),
        ('ORDER_CANCEL','DUPLICATE_ORDER','Duplicate Order',false,false),
        ('ORDER_CANCEL','PAYMENT_FAILED','Payment Failed',false,false),
        ('ORDER_CANCEL','FRAUD_REJECTED','Fraud or Risk Rejected',true,true),
        ('ORDER_CANCEL','OUT_OF_STOCK','Out of Stock',true,false),
        ('ORDER_CANCEL','SELLER_CANCELLED','Seller Cancelled',true,true),
        ('ORDER_CHANGE','CUSTOMER_REQUEST','Customer Request',false,false),
        ('ORDER_CHANGE','ADDRESS_CORRECTION','Address Correction',true,false),
        ('ORDER_CHANGE','ITEM_SUBSTITUTION','Item Substitution',true,true),
        ('ORDER_CHANGE','PRICE_ADJUSTMENT','Price Adjustment',true,true),
        ('ORDER_CHANGE','QUANTITY_ADJUSTMENT','Quantity Adjustment',true,false),
        ('PAYMENT','AUTHORIZATION_FAILED','Authorization Failed',false,false),
        ('PAYMENT','CAPTURE_FAILED','Capture Failed',true,false),
        ('PAYMENT','CUSTOMER_REFUND','Customer Refund',true,true),
        ('PAYMENT','DUPLICATE_CHARGE','Duplicate Charge',true,true),
        ('PAYMENT','SERVICE_RECOVERY','Service Recovery',true,true),
        ('FULFILLMENT','INVENTORY_SHORTAGE','Inventory Shortage',true,false),
        ('FULFILLMENT','DAMAGED_IN_WAREHOUSE','Damaged in Warehouse',true,false),
        ('FULFILLMENT','CARRIER_EXCEPTION','Carrier Exception',true,false),
        ('FULFILLMENT','DELIVERY_FAILED','Delivery Failed',true,false),
        ('FULFILLMENT','CUSTOMER_UNAVAILABLE','Customer Unavailable',true,false),
        ('RETURN','CHANGED_MIND','Changed Mind',false,false),
        ('RETURN','DAMAGED','Damaged Item',true,false),
        ('RETURN','DEFECTIVE','Defective Item',true,false),
        ('RETURN','WRONG_ITEM','Wrong Item',true,false),
        ('RETURN','NOT_AS_DESCRIBED','Not as Described',true,false),
        ('RETURN','LATE_DELIVERY','Late Delivery',true,false),
        ('RISK','MANUAL_REVIEW','Manual Review Required',true,false),
        ('RISK','IDENTITY_MISMATCH','Identity Mismatch',true,true),
        ('RISK','VELOCITY_LIMIT','Velocity Limit Exceeded',true,true),
        ('RISK','ADDRESS_MISMATCH','Address Mismatch',true,false),
        ('RISK','CONFIRMED_FRAUD','Confirmed Fraud',true,true)
)
INSERT INTO doms.reason_codes (
    tenant_id, reason_group, reason_code, reason_name,
    requires_note, requires_approval, is_active
)
SELECT NULL, seed.reason_group, seed.reason_code, seed.reason_name,
       seed.requires_note, seed.requires_approval, true
FROM seed
WHERE NOT EXISTS (
    SELECT 1
    FROM doms.reason_codes existing
    WHERE existing.tenant_id IS NULL
      AND existing.reason_group = seed.reason_group
      AND existing.reason_code = seed.reason_code
);

-- PostgreSQL grants PUBLIC access and function EXECUTE by default. Application
-- roles receive only an explicit deployment-time allow-list outside this baseline.
REVOKE CREATE ON SCHEMA doms FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA doms FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA doms FROM PUBLIC;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA doms FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA doms REVOKE ALL ON TABLES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA doms REVOKE ALL ON SEQUENCES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA doms REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

COMMENT ON SCHEMA doms IS
    'Enterprise omnichannel order management: Firebase IAM, order capture and orchestration, inventory promise, payment, fulfillment, returns, procurement, settlement, workflow, integration, audit, and analytics.';

-- High-value work queues, external processing lanes, and operational timelines.
CREATE INDEX IF NOT EXISTS ix_ops_doms_orders_queue
    ON doms.sales_orders (
        tenant_id, order_status, risk_status, payment_status, fulfillment_status,
        ordered_at, id
    ) WHERE deleted_at IS NULL AND order_status NOT IN ('COMPLETED','CANCELLED','CLOSED');
CREATE INDEX IF NOT EXISTS ix_ops_doms_order_changes_queue
    ON doms.order_change_requests (tenant_id, request_status, requested_at, id)
    WHERE request_status IN ('REQUESTED','VALIDATING','APPROVAL_PENDING','APPROVED','APPLYING','FAILED');
CREATE INDEX IF NOT EXISTS ix_ops_doms_order_cancel_queue
    ON doms.order_cancellation_requests (tenant_id, request_status, requested_at, id)
    WHERE request_status IN ('REQUESTED','VALIDATING','APPROVAL_PENDING','APPROVED','PROCESSING','FAILED');
CREATE INDEX IF NOT EXISTS ix_ops_doms_order_holds_queue
    ON doms.order_holds (tenant_id, hold_status, severity, placed_at, id)
    WHERE hold_status IN ('ACTIVE','RELEASE_PENDING');

CREATE INDEX IF NOT EXISTS ix_ops_doms_atp_queue
    ON doms.atp_check_requests (tenant_id, request_status, requested_at, id)
    WHERE request_status IN ('REQUESTED','PROCESSING');
CREATE INDEX IF NOT EXISTS ix_ops_doms_sourcing_queue
    ON doms.sourcing_requests (tenant_id, request_status, required_ship_at, created_at, id)
    WHERE request_status IN ('REQUESTED','EVALUATING','PARTIALLY_SOURCED');
CREATE INDEX IF NOT EXISTS ix_ops_doms_reservation_queue
    ON doms.reservation_requests (tenant_id, request_status, expires_at, requested_at, id)
    WHERE request_status IN ('REQUESTED','PROCESSING','PARTIALLY_RESERVED');
CREATE INDEX IF NOT EXISTS ix_ops_doms_backorder_queue
    ON doms.backorders (tenant_id, backorder_status, priority, expected_available_at, id)
    WHERE backorder_status NOT IN ('RELEASED','CANCELLED','CLOSED');

CREATE INDEX IF NOT EXISTS ix_ops_doms_return_eligibility_queue
    ON doms.return_eligibility_checks (tenant_id, check_status, requested_at, id)
    WHERE check_status IN ('PENDING','RUNNING');
CREATE INDEX IF NOT EXISTS ix_ops_doms_return_request_queue
    ON doms.return_requests (tenant_id, return_status, requested_at, id)
    WHERE return_status NOT IN ('REFUNDED','EXCHANGED','REPLACED','REJECTED','CANCELLED','EXPIRED','CLOSED');
CREATE INDEX IF NOT EXISTS ix_ops_doms_rma_queue
    ON doms.rma_authorizations (tenant_id, authorization_status, expires_at, id)
    WHERE authorization_status NOT IN ('REFUNDED','REJECTED','CANCELLED','EXPIRED','CLOSED');
CREATE INDEX IF NOT EXISTS ix_ops_doms_return_label_queue
    ON doms.return_labels (tenant_id, label_status, created_at, id)
    WHERE label_status IN ('REQUESTED','GENERATED','ACTIVE','FAILED');
CREATE INDEX IF NOT EXISTS ix_ops_doms_return_shipment_queue
    ON doms.return_shipments (tenant_id, shipment_status, created_at, id)
    WHERE shipment_status NOT IN ('RECEIVED','LOST','CANCELLED','CLOSED');
CREATE INDEX IF NOT EXISTS ix_ops_doms_return_receipt_queue
    ON doms.return_receipts (tenant_id, receipt_status, received_at, id)
    WHERE receipt_status IN ('OPEN','RECEIVING','PARTIAL','EXCEPTION');

CREATE INDEX IF NOT EXISTS ix_ops_doms_fulfillment_queue
    ON doms.fulfillment_orders (tenant_id, status, priority, requested_fulfill_at, id)
    WHERE status NOT IN ('COMPLETED','CANCELLED','CLOSED');
CREATE INDEX IF NOT EXISTS ix_ops_doms_shipment_plan_queue
    ON doms.shipment_plans (tenant_id, status, planned_ship_at, id)
    WHERE status NOT IN ('COMPLETED','CANCELLED');
CREATE INDEX IF NOT EXISTS ix_ops_doms_shipment_queue
    ON doms.shipments (tenant_id, status, planned_ship_at, estimated_delivery_at, id)
    WHERE status NOT IN ('DELIVERED','CANCELLED','CLOSED');
CREATE INDEX IF NOT EXISTS ix_ops_doms_pickup_queue
    ON doms.pickup_orders (tenant_id, status, scheduled_from, expires_at, id)
    WHERE status NOT IN ('PICKED_UP','EXPIRED','CANCELLED','CLOSED');

CREATE INDEX IF NOT EXISTS ix_ops_doms_payment_intent_queue
    ON doms.payment_intents (tenant_id, status, expires_at, created_at, id)
    WHERE status IN ('REQUIRES_PAYMENT_METHOD','REQUIRES_CONFIRMATION','REQUIRES_ACTION','PROCESSING','AUTHORIZED','PARTIALLY_CAPTURED');
CREATE INDEX IF NOT EXISTS ix_ops_doms_refund_queue
    ON doms.payment_refund_requests (tenant_id, status, requested_at, id)
    WHERE status IN ('REQUESTED','REVIEWING','APPROVED','PROCESSING','FAILED');
CREATE INDEX IF NOT EXISTS ix_ops_doms_dispute_queue
    ON doms.payment_disputes (tenant_id, status, response_due_at, opened_at, id)
    WHERE status NOT IN ('WON','LOST','CLOSED','CANCELLED');
CREATE INDEX IF NOT EXISTS ix_ops_doms_fraud_case_queue
    ON doms.fraud_cases (tenant_id, status, priority, due_at, opened_at, id)
    WHERE status NOT IN ('RESOLVED','CLOSED','CANCELLED');

CREATE INDEX IF NOT EXISTS ix_ops_doms_purchase_order_queue
    ON doms.purchase_orders (tenant_id, status, approval_status, requested_delivery_date, id)
    WHERE status NOT IN ('CLOSED','CANCELLED');
CREATE INDEX IF NOT EXISTS ix_ops_doms_invoice_queue
    ON doms.invoices (tenant_id, status, due_date, invoice_date, id)
    WHERE status NOT IN ('PAID','VOID','CANCELLED','CREDITED');
CREATE INDEX IF NOT EXISTS ix_ops_doms_channel_settlement_queue
    ON doms.channel_settlements (tenant_id, status, expected_payout_at, id)
    WHERE status NOT IN ('SETTLED','CLOSED','CANCELLED');
CREATE INDEX IF NOT EXISTS ix_ops_doms_journal_batch_queue
    ON doms.journal_batches (tenant_id, status, created_at, id)
    WHERE status NOT IN ('POSTED','REVERSED','CANCELLED');

CREATE INDEX IF NOT EXISTS ix_ops_doms_outbox_queue
    ON doms.outbox_events (tenant_id, available_at, retry_count, occurred_at, id)
    WHERE published_at IS NULL;
CREATE INDEX IF NOT EXISTS ix_ops_doms_integration_queue
    ON doms.integration_messages (tenant_id, status, received_at, attempt_count, id)
    WHERE status NOT IN ('PROCESSED','CANCELLED','ARCHIVED');
CREATE INDEX IF NOT EXISTS ix_ops_doms_job_queue
    ON doms.job_runs (tenant_id, status, queued_at, id)
    WHERE status IN ('QUEUED','RUNNING','PARTIAL','FAILED');
CREATE INDEX IF NOT EXISTS ix_ops_doms_dead_letter_queue
    ON doms.dead_letter_messages (tenant_id, status, next_retry_at, failed_at, id)
    WHERE status IN ('OPEN','RETRY_QUEUED','RETRYING');

CREATE INDEX IF NOT EXISTS ix_ops_doms_orders_ordered_brin
    ON doms.sales_orders USING brin (ordered_at);
CREATE INDEX IF NOT EXISTS ix_ops_doms_order_events_brin
    ON doms.order_events USING brin (occurred_at);
CREATE INDEX IF NOT EXISTS ix_ops_doms_inventory_events_brin
    ON doms.inventory_position_events USING brin (occurred_at);
CREATE INDEX IF NOT EXISTS ix_ops_doms_payment_events_brin
    ON doms.payment_events USING brin (occurred_at);
CREATE INDEX IF NOT EXISTS ix_ops_doms_fulfillment_events_brin
    ON doms.fulfillment_order_status_events USING brin (occurred_at);
CREATE INDEX IF NOT EXISTS ix_ops_doms_shipment_events_brin
    ON doms.shipment_status_events USING brin (occurred_at);
CREATE INDEX IF NOT EXISTS ix_ops_doms_delivery_events_brin
    ON doms.delivery_events USING brin (occurred_at);
CREATE INDEX IF NOT EXISTS ix_ops_doms_audit_events_brin
    ON doms.audit_events USING brin (occurred_at);
CREATE INDEX IF NOT EXISTS ix_ops_doms_change_log_brin
    ON doms.entity_change_logs USING brin (occurred_at);
CREATE INDEX IF NOT EXISTS ix_ops_doms_data_access_brin
    ON doms.data_access_logs USING brin (occurred_at);
CREATE INDEX IF NOT EXISTS ix_ops_doms_return_events_brin
    ON doms.return_request_status_events USING brin (occurred_at);
CREATE INDEX IF NOT EXISTS ix_ops_doms_rma_events_brin
    ON doms.rma_authorization_events USING brin (occurred_at);
CREATE INDEX IF NOT EXISTS ix_ops_doms_return_tracking_brin
    ON doms.return_tracking_events USING brin (occurred_at);
CREATE INDEX IF NOT EXISTS ix_ops_doms_return_receipt_events_brin
    ON doms.return_receipt_events USING brin (occurred_at);
CREATE INDEX IF NOT EXISTS ix_ops_doms_return_inspection_events_brin
    ON doms.return_inspection_events USING brin (occurred_at);
CREATE INDEX IF NOT EXISTS ix_ops_doms_return_disposition_events_brin
    ON doms.return_disposition_events USING brin (occurred_at);

CREATE INDEX IF NOT EXISTS ix_ops_doms_node_facts_brin
    ON doms.fulfillment_node_daily_facts USING brin (fact_date);
CREATE INDEX IF NOT EXISTS ix_ops_doms_inventory_facts_brin
    ON doms.inventory_promise_daily_facts USING brin (fact_date);
CREATE INDEX IF NOT EXISTS ix_ops_doms_operation_facts_brin
    ON doms.order_operation_daily_facts USING brin (fact_date);
CREATE INDEX IF NOT EXISTS ix_ops_doms_order_facts_brin
    ON doms.order_daily_facts USING brin (fact_date);
CREATE INDEX IF NOT EXISTS ix_ops_doms_payment_facts_brin
    ON doms.payment_daily_facts USING brin (fact_date);
CREATE INDEX IF NOT EXISTS ix_ops_doms_return_facts_brin
    ON doms.return_daily_facts USING brin (fact_date);

-- Strict append-only records.
-- Lifecycle headers that require controlled DRAFT -> APPROVED/SEALED transitions keep
-- their module-specific guards; this list contains event streams and posted facts that
-- must never be updated, deleted, or truncated.
DO $block$
DECLARE
    table_name text;
BEGIN
    FOREACH table_name IN ARRAY ARRAY[
        'schema_migrations','account_link_events','login_events','audit_events',
        'sales_order_status_events','sales_order_line_status_events','order_hold_events',
        'order_events','order_validation_results','order_change_request_events',
        'order_cancellation_events',
        'order_journey_run_errors','inventory_position_events','atp_check_results',
        'sourcing_decisions','inventory_reservation_events','fulfillment_allocation_events',
        'return_eligibility_results','return_request_status_events',
        'rma_authorization_events','return_tracking_events','return_receipt_lines',
        'return_receipt_events','return_inspections','return_inspection_events',
        'return_dispositions','return_disposition_events','warranty_claim_events',
        'customer_service_interactions','customer_service_sla_events',
        'payment_events','payment_failures','payment_dispute_events',
        'payment_allocations','payment_refund_allocations','gift_card_ledger_entries',
        'store_credit_ledger_entries','risk_signals','risk_rule_evaluations',
        'risk_decisions','fraud_case_events','payment_settlement_entries',
        'fulfillment_order_status_events','fulfillment_order_line_status_events',
        'fulfillment_split_relations','shipment_status_events','package_status_events',
        'package_lot_evidence','package_serial_evidence','shipment_tracking_events',
        'carrier_booking_attempts','proof_of_delivery_objects',
        'digital_fulfillment_events','service_fulfillment_events',
        'fulfillment_confirmation_events',
        'pickup_events','delivery_appointment_events','delivery_events',
        'purchase_order_events','dropship_events','transfer_order_events',
        'invoice_events','credit_memo_events','channel_fee_events',
        'edi_validation_errors','impersonation_events','entity_change_logs',
        'data_access_logs','approval_actions',
        'data_disposal_results'
    ]::text[]
    LOOP
        IF to_regclass(format('doms.%I', table_name)) IS NULL THEN
            CONTINUE;
        END IF;
        EXECUTE format('DROP TRIGGER IF EXISTS trg_append_only ON doms.%I', table_name);
        EXECUTE format(
            'CREATE TRIGGER trg_append_only BEFORE UPDATE OR DELETE ON doms.%I '
            'FOR EACH ROW EXECUTE PROCEDURE doms.prevent_append_only_change()',
            table_name
        );
        EXECUTE format('DROP TRIGGER IF EXISTS trg_append_only_truncate ON doms.%I', table_name);
        EXECUTE format(
            'CREATE TRIGGER trg_append_only_truncate BEFORE TRUNCATE ON doms.%I '
            'FOR EACH STATEMENT EXECUTE PROCEDURE doms.prevent_append_only_truncate()',
            table_name
        );
    END LOOP;
END;
$block$;

-- Message payloads and routing identity remain immutable; only explicitly listed
-- processing/projection columns may advance.
DO $block$
DECLARE
    target record;
BEGIN
    FOR target IN
        SELECT * FROM (VALUES
            ('outbox_events',
             '''available_at'',''published_at'',''retry_count'',''last_error_masked'',''row_version'',''updated_at'''),
            ('integration_messages',
             '''status'',''attempt_count'',''processed_at'',''error_code'',''error_detail_masked'',''row_version'',''updated_at'''),
            ('edi_documents',
             '''status'',''acknowledgement_status'',''processed_at'',''row_version'',''updated_at'''),
            ('webhook_deliveries',
             '''requested_at'',''responded_at'',''http_status'',''response_body_masked'',''status'',''next_attempt_at'',''error_detail_masked'',''row_version'',''updated_at'''),
            ('inbox_deduplication',
             '''last_received_at'',''receive_count'',''processed_resource_type'',''processed_resource_id'',''status'',''row_version'',''updated_at'''),
            ('dead_letter_messages',
             '''retry_count'',''next_retry_at'',''status'',''resolved_at'',''resolved_by'',''resolution'',''row_version'',''updated_at''')
        ) AS configured(table_name, mutable_columns)
    LOOP
        IF to_regclass(format('doms.%I', target.table_name)) IS NULL THEN
            CONTINUE;
        END IF;
        EXECUTE format('DROP TRIGGER IF EXISTS trg_protect_message_core ON doms.%I', target.table_name);
        EXECUTE format(
            'CREATE TRIGGER trg_protect_message_core BEFORE UPDATE OR DELETE ON doms.%I '
            'FOR EACH ROW EXECUTE PROCEDURE doms.protect_message_core(%s)',
            target.table_name, target.mutable_columns
        );
        EXECUTE format('DROP TRIGGER IF EXISTS trg_protect_message_truncate ON doms.%I', target.table_name);
        EXECUTE format(
            'CREATE TRIGGER trg_protect_message_truncate BEFORE TRUNCATE ON doms.%I '
            'FOR EACH STATEMENT EXECUTE PROCEDURE doms.prevent_append_only_change()',
            target.table_name
        );
    END LOOP;
END;
$block$;

-- Analytical result identities and source facts stay immutable, while reviewed
-- recalculation and remediation fields may advance in place.
DROP TRIGGER IF EXISTS trg_protect_kpi_value_core ON doms.kpi_values;
CREATE TRIGGER trg_protect_kpi_value_core
BEFORE UPDATE OR DELETE ON doms.kpi_values
FOR EACH ROW EXECUTE PROCEDURE doms.protect_message_core(
    'kpi_value','numerator','denominator','sample_size','quality_status',
    'calculated_at','source_lineage','row_version','updated_at'
);
DROP TRIGGER IF EXISTS trg_protect_kpi_value_truncate ON doms.kpi_values;
CREATE TRIGGER trg_protect_kpi_value_truncate
BEFORE TRUNCATE ON doms.kpi_values
FOR EACH STATEMENT EXECUTE PROCEDURE doms.prevent_append_only_truncate();

DROP TRIGGER IF EXISTS trg_protect_data_quality_result_core ON doms.data_quality_results;
CREATE TRIGGER trg_protect_data_quality_result_core
BEFORE UPDATE OR DELETE ON doms.data_quality_results
FOR EACH ROW EXECUTE PROCEDURE doms.protect_message_core(
    'status','assigned_to','resolved_at','resolved_by','resolution',
    'row_version','updated_at'
);
DROP TRIGGER IF EXISTS trg_protect_data_quality_result_truncate ON doms.data_quality_results;
CREATE TRIGGER trg_protect_data_quality_result_truncate
BEFORE TRUNCATE ON doms.data_quality_results
FOR EACH STATEMENT EXECUTE PROCEDURE doms.prevent_append_only_truncate();

-- Version aggregates keep their explicit publish/seal transition guards, but a bulk
-- TRUNCATE must never bypass those row-level protections. They intentionally sit
-- outside the strict append-only marker block because their controlled state changes
-- remain legal.
DO $block$
DECLARE
    table_name text;
BEGIN
    FOREACH table_name IN ARRAY ARRAY[
        'price_book_versions','promotion_versions','sales_order_versions',
        'sales_order_version_lines','order_parties','order_address_snapshots',
        'order_contact_snapshots','order_journey_versions','order_journey_steps',
        'order_journey_transitions','return_policy_versions','return_policy_rules',
        'fraud_rule_versions','supplier_contract_versions',
        'supplier_contract_lines','workflow_versions','workflow_steps'
    ]::text[]
    LOOP
        IF to_regclass(format('doms.%I', table_name)) IS NULL THEN
            CONTINUE;
        END IF;
        EXECUTE format('DROP TRIGGER IF EXISTS trg_doms_version_truncate ON doms.%I', table_name);
        EXECUTE format(
            'CREATE TRIGGER trg_doms_version_truncate BEFORE TRUNCATE ON doms.%I '
            'FOR EACH STATEMENT EXECUTE PROCEDURE doms.prevent_append_only_truncate()',
            table_name
        );
    END LOOP;
END;
$block$;

-- tenant_id can never be reassigned in place. Transfers use new rows plus audited
-- cancellation, reversal, or relationship records.
DO $block$
DECLARE
    target record;
BEGIN
    FOR target IN
        SELECT DISTINCT columns.table_schema, columns.table_name
        FROM information_schema.columns columns
        JOIN information_schema.tables tables
          ON tables.table_schema = columns.table_schema
         AND tables.table_name = columns.table_name
         AND tables.table_type = 'BASE TABLE'
        WHERE columns.table_schema = 'doms'
          AND columns.column_name = 'tenant_id'
    LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS trg_tenant_immutable ON %I.%I', target.table_schema, target.table_name);
        EXECUTE format(
            'CREATE TRIGGER trg_tenant_immutable BEFORE UPDATE OF tenant_id ON %I.%I '
            'FOR EACH ROW EXECUTE PROCEDURE doms.prevent_tenant_change()',
            target.table_schema, target.table_name
        );
    END LOOP;
END;
$block$;

-- Every tenant-scoped table receives exactly two policies. Only explicitly listed
-- nullable-tenant masters expose global rows, while all ordinary writes require
-- the active tenant selected by the trusted backend.
DO $block$
DECLARE
    target record;
    global_reference_tables constant text[] := ARRAY[
        'roles','role_permissions','code_sets','code_values','data_retention_policies',
        'exchange_rates','tax_codes','tax_rates','payment_terms','charge_codes',
        'reason_codes','inventory_statuses','order_types','delivery_methods',
        'status_definitions','status_transitions','notification_templates','scheduled_jobs',
        'sod_rules','sod_rule_conflicts','kpi_definitions','data_quality_rules'
    ]::text[];
    platform_event_tables constant text[] := ARRAY[
        'login_events','audit_events','data_access_logs'
    ]::text[];
    global_job_tables constant text[] := ARRAY['job_runs']::text[];
    authenticator_read_tables constant text[] := ARRAY['tenant_memberships']::text[];
    select_expression text;
    modify_expression text;
BEGIN
    FOR target IN
        SELECT DISTINCT columns.table_schema, columns.table_name
        FROM information_schema.columns columns
        JOIN information_schema.tables tables
          ON tables.table_schema = columns.table_schema
         AND tables.table_name = columns.table_name
         AND tables.table_type = 'BASE TABLE'
        WHERE columns.table_schema = 'doms'
          AND columns.column_name = 'tenant_id'
    LOOP
        EXECUTE format('ALTER TABLE %I.%I ENABLE ROW LEVEL SECURITY', target.table_schema, target.table_name);
        EXECUTE format('DROP POLICY IF EXISTS tenant_select ON %I.%I', target.table_schema, target.table_name);
        EXECUTE format('DROP POLICY IF EXISTS tenant_modify ON %I.%I', target.table_schema, target.table_name);

        IF target.table_name = ANY (authenticator_read_tables) THEN
            select_expression := 'tenant_id = doms.current_tenant_id() OR '
                || 'doms.has_active_session_issue_context(user_id, tenant_id) OR '
                || 'doms.has_active_membership_provision_context(user_id, tenant_id)';
            modify_expression := 'tenant_id = doms.current_tenant_id() OR '
                || 'doms.has_active_session_issue_context(user_id, tenant_id) OR '
                || 'doms.is_membership_provision_candidate(id, user_id, tenant_id)';
        ELSIF target.table_name = ANY (global_reference_tables) THEN
            select_expression := 'tenant_id IS NULL OR tenant_id = doms.current_tenant_id()';
            modify_expression := 'tenant_id = doms.current_tenant_id()';
        ELSIF target.table_name = ANY (platform_event_tables) THEN
            select_expression := 'tenant_id = doms.current_tenant_id() OR '
                || '(tenant_id IS NULL AND current_user = ''doms_platform_logger'')';
            modify_expression := select_expression;
            IF target.table_name = 'audit_events' THEN
                select_expression := select_expression || ' OR '
                    || '(action_code = ''TENANT_MEMBERSHIP_PROVISIONED'' '
                    || 'AND entity_type = ''TENANT_MEMBERSHIP'' '
                    || 'AND doms.has_membership_provision_audit_context(entity_id, tenant_id))';
                modify_expression := select_expression;
            END IF;
        ELSIF target.table_name = ANY (global_job_tables) THEN
            select_expression := 'tenant_id = doms.current_tenant_id() OR '
                || '(tenant_id IS NULL AND current_user = ''doms_global_job_runner'')';
            modify_expression := select_expression;
        ELSE
            select_expression := 'tenant_id = doms.current_tenant_id()';
            modify_expression := select_expression;
        END IF;

        EXECUTE format(
            'CREATE POLICY tenant_select ON %I.%I FOR SELECT USING (%s)',
            target.table_schema, target.table_name, select_expression
        );
        EXECUTE format(
            'CREATE POLICY tenant_modify ON %I.%I FOR ALL USING (%s) WITH CHECK (%s)',
            target.table_schema, target.table_name, modify_expression, modify_expression
        );
    END LOOP;
END;
$block$;

-- PostgreSQL does not index referencing FK columns. Add a deterministic leading
-- non-partial index whenever no valid index already covers the complete FK prefix.
DO $block$
DECLARE
    relation record;
    column_list text;
    index_name text;
BEGIN
    FOR relation IN
        SELECT con.oid, con.conname, con.conrelid,
               namespace_row.nspname AS schema_name,
               relation_row.relname AS table_name,
               con.conkey
        FROM pg_constraint con
        JOIN pg_class relation_row ON relation_row.oid = con.conrelid
        JOIN pg_namespace namespace_row ON namespace_row.oid = relation_row.relnamespace
        WHERE con.contype = 'f' AND namespace_row.nspname = 'doms'
        ORDER BY relation_row.relname, array_length(con.conkey, 1) DESC,
                 con.conkey::text, con.conname
    LOOP
        SELECT string_agg(quote_ident(attribute_row.attname), ', ' ORDER BY key_column.ordinality)
          INTO column_list
        FROM unnest(relation.conkey) WITH ORDINALITY AS key_column(attnum, ordinality)
        JOIN pg_attribute attribute_row
          ON attribute_row.attrelid = relation.conrelid
         AND attribute_row.attnum = key_column.attnum;

        IF EXISTS (
            SELECT 1
            FROM pg_index index_row
            WHERE index_row.indrelid = relation.conrelid
              AND index_row.indisvalid
              AND index_row.indisready
              AND index_row.indpred IS NULL
              AND index_row.indnkeyatts >= array_length(relation.conkey, 1)
              AND ARRAY(
                  SELECT index_column.attnum
                  FROM unnest(index_row.indkey) WITH ORDINALITY AS index_column(attnum, ordinality)
                  WHERE index_column.ordinality <= array_length(relation.conkey, 1)
                  ORDER BY index_column.ordinality
              )::smallint[] = relation.conkey
        ) THEN
            CONTINUE;
        END IF;

        index_name := 'ix_fk_' || substr(relation.table_name, 1, 30) || '_' ||
            substr(md5(relation.schema_name || '.' || relation.table_name || '.' || relation.conname), 1, 10);
        EXECUTE format(
            'CREATE INDEX IF NOT EXISTS %I ON %I.%I (%s)',
            index_name, relation.schema_name, relation.table_name, column_list
        );
    END LOOP;
END;
$block$;

-- Single-column UUID references between tenant tables need a same-tenant guard.
-- Composite tenant_id + id foreign keys are preferred and suppress this fallback.
DO $block$
DECLARE
    relation record;
    child_column text;
    trigger_name text;
BEGIN
    FOR relation IN
        SELECT con.oid, con.conname, con.conrelid, con.confrelid,
               child_namespace.nspname AS child_schema,
               child_relation.relname AS child_table,
               parent_namespace.nspname AS parent_schema,
               parent_relation.relname AS parent_table,
               con.conkey[1] AS child_attnum
        FROM pg_constraint con
        JOIN pg_class child_relation ON child_relation.oid = con.conrelid
        JOIN pg_namespace child_namespace ON child_namespace.oid = child_relation.relnamespace
        JOIN pg_class parent_relation ON parent_relation.oid = con.confrelid
        JOIN pg_namespace parent_namespace ON parent_namespace.oid = parent_relation.relnamespace
        WHERE con.contype = 'f'
          AND child_namespace.nspname = 'doms'
          AND parent_namespace.nspname = 'doms'
          AND array_length(con.conkey, 1) = 1
          AND EXISTS (
              SELECT 1 FROM pg_attribute attribute_row
              WHERE attribute_row.attrelid = con.conrelid
                AND attribute_row.attname = 'tenant_id'
                AND NOT attribute_row.attisdropped
          )
          AND EXISTS (
              SELECT 1 FROM pg_attribute attribute_row
              WHERE attribute_row.attrelid = con.confrelid
                AND attribute_row.attname = 'tenant_id'
                AND NOT attribute_row.attisdropped
          )
          AND EXISTS (
              SELECT 1 FROM pg_attribute attribute_row
              WHERE attribute_row.attrelid = con.confrelid
                AND attribute_row.attnum = con.confkey[1]
                AND attribute_row.attname = 'id'
          )
    LOOP
        SELECT attname INTO child_column
        FROM pg_attribute
        WHERE attrelid = relation.conrelid AND attnum = relation.child_attnum;
        IF child_column = 'tenant_id' THEN
            CONTINUE;
        END IF;
        IF EXISTS (
            SELECT 1
            FROM pg_constraint companion
            JOIN pg_attribute tenant_column
              ON tenant_column.attrelid = companion.conrelid
             AND tenant_column.attname = 'tenant_id'
             AND NOT tenant_column.attisdropped
            WHERE companion.contype = 'f'
              AND companion.conrelid = relation.conrelid
              AND companion.confrelid = relation.confrelid
              AND array_length(companion.conkey, 1) >= 2
              AND companion.conkey[1] = tenant_column.attnum
              AND relation.child_attnum = ANY(companion.conkey)
        ) THEN
            CONTINUE;
        END IF;

        trigger_name := 'trg_tenant_fk_' || substr(
            md5(relation.child_schema || '.' || relation.child_table || '.' || relation.conname),
            1, 12
        );
        EXECUTE format('DROP TRIGGER IF EXISTS %I ON %I.%I',
            trigger_name, relation.child_schema, relation.child_table);
        EXECUTE format(
            'CREATE TRIGGER %I BEFORE INSERT OR UPDATE OF %I ON %I.%I '
            'FOR EACH ROW EXECUTE PROCEDURE doms.enforce_same_tenant_fk(%L,%L,%L)',
            trigger_name, child_column, relation.child_schema, relation.child_table,
            child_column, relation.parent_schema, relation.parent_table
        );
    END LOOP;
END;
$block$;

-- Restore FORCE after every integrity object has been installed. Keeping this as
-- the final operation prevents later module statements from accidentally weakening
-- owner-level tenant isolation.
DO $block$
DECLARE
    target record;
BEGIN
    FOR target IN
        SELECT DISTINCT columns.table_schema, columns.table_name
        FROM information_schema.columns columns
        JOIN information_schema.tables tables
          ON tables.table_schema = columns.table_schema
         AND tables.table_name = columns.table_name
         AND tables.table_type = 'BASE TABLE'
        WHERE columns.table_schema = 'doms'
          AND columns.column_name = 'tenant_id'
    LOOP
        EXECUTE format(
            'ALTER TABLE %I.%I FORCE ROW LEVEL SECURITY',
            target.table_schema, target.table_name
        );
    END LOOP;
END;
$block$;
