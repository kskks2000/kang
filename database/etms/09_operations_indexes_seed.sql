-- ETMS notifications, EDI/webhooks/jobs, audit extensions, integrity triggers, indexes, and reference seeds.

CREATE TABLE IF NOT EXISTS etms.status_definitions (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid REFERENCES etms.tenants(id) ON DELETE CASCADE,
    entity_type varchar(80) NOT NULL,
    status_code varchar(50) NOT NULL,
    status_name varchar(150) NOT NULL,
    category varchar(30),
    terminal_status boolean NOT NULL DEFAULT false,
    success_status boolean NOT NULL DEFAULT false,
    sort_order integer NOT NULL DEFAULT 0,
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_status_definitions_scope
    ON etms.status_definitions (
        COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), entity_type, status_code
    );

CREATE TABLE IF NOT EXISTS etms.status_transitions (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid REFERENCES etms.tenants(id) ON DELETE CASCADE,
    entity_type varchar(80) NOT NULL,
    from_status_code varchar(50) NOT NULL,
    to_status_code varchar(50) NOT NULL,
    permission_code varchar(150),
    condition_expression jsonb NOT NULL DEFAULT '{}'::jsonb,
    requires_reason boolean NOT NULL DEFAULT false,
    requires_approval boolean NOT NULL DEFAULT false,
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_status_transition_distinct CHECK (from_status_code <> to_status_code)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_status_transitions_scope
    ON etms.status_transitions (
        COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), entity_type, from_status_code, to_status_code
    );

CREATE TABLE IF NOT EXISTS etms.tags (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    tag_code varchar(80) NOT NULL,
    tag_name varchar(150) NOT NULL,
    color_hex char(7),
    description text,
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, tag_code),
    CONSTRAINT ck_tags_color CHECK (color_hex IS NULL OR color_hex ~ '^#[0-9A-Fa-f]{6}$')
);

CREATE TABLE IF NOT EXISTS etms.entity_tags (
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    entity_type varchar(80) NOT NULL,
    entity_id uuid NOT NULL,
    tag_id uuid NOT NULL REFERENCES etms.tags(id) ON DELETE CASCADE,
    assigned_by uuid REFERENCES etms.users(id),
    assigned_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (entity_type, entity_id, tag_id)
);

CREATE TABLE IF NOT EXISTS etms.notification_templates (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid REFERENCES etms.tenants(id) ON DELETE CASCADE,
    template_code varchar(100) NOT NULL,
    channel varchar(20) NOT NULL,
    locale varchar(20) NOT NULL DEFAULT 'ko-KR',
    subject_template text,
    body_template text NOT NULL,
    variable_schema jsonb NOT NULL DEFAULT '{}'::jsonb,
    version_no integer NOT NULL DEFAULT 1,
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_notification_template_channel CHECK (channel IN ('APP','EMAIL','SMS','PUSH','KAKAO','WEBHOOK')),
    CONSTRAINT ck_notification_template_version CHECK (version_no > 0)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_notification_templates_scope
    ON etms.notification_templates (
        COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), template_code, channel, locale, version_no
    );

CREATE TABLE IF NOT EXISTS etms.notification_preferences (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    user_id uuid NOT NULL REFERENCES etms.users(id) ON DELETE CASCADE,
    event_type varchar(100) NOT NULL,
    channel varchar(20) NOT NULL,
    enabled boolean NOT NULL DEFAULT true,
    quiet_hours_from time,
    quiet_hours_to time,
    timezone varchar(100) NOT NULL DEFAULT 'Asia/Seoul',
    digest_frequency varchar(20) NOT NULL DEFAULT 'IMMEDIATE',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, user_id, event_type, channel)
);

CREATE TABLE IF NOT EXISTS etms.notifications (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    event_type varchar(100) NOT NULL,
    template_id uuid REFERENCES etms.notification_templates(id),
    entity_type varchar(80),
    entity_id uuid,
    priority varchar(20) NOT NULL DEFAULT 'NORMAL',
    subject_rendered text,
    body_rendered text NOT NULL,
    variables_masked jsonb NOT NULL DEFAULT '{}'::jsonb,
    scheduled_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz,
    status varchar(20) NOT NULL DEFAULT 'QUEUED',
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_notification_priority CHECK (priority IN ('LOW','NORMAL','HIGH','CRITICAL'))
);

CREATE TABLE IF NOT EXISTS etms.notification_deliveries (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    notification_id uuid NOT NULL REFERENCES etms.notifications(id) ON DELETE CASCADE,
    user_id uuid REFERENCES etms.users(id),
    partner_contact_id uuid REFERENCES etms.contacts(id),
    channel varchar(20) NOT NULL,
    recipient_masked varchar(500),
    status varchar(20) NOT NULL DEFAULT 'QUEUED',
    provider_code varchar(50),
    provider_message_id varchar(300),
    attempt_count integer NOT NULL DEFAULT 0,
    last_attempt_at timestamptz,
    delivered_at timestamptz,
    read_at timestamptz,
    failed_at timestamptz,
    error_detail_masked text,
    CONSTRAINT ck_notification_recipient CHECK (user_id IS NOT NULL OR partner_contact_id IS NOT NULL OR recipient_masked IS NOT NULL),
    CONSTRAINT ck_notification_attempt CHECK (attempt_count >= 0)
);

CREATE TABLE IF NOT EXISTS etms.edi_documents (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    external_system_id uuid REFERENCES etms.external_systems(id),
    interchange_control_no varchar(100),
    functional_group_no varchar(100),
    transaction_set_no varchar(100),
    standard_code varchar(30) NOT NULL,
    standard_version varchar(30),
    message_type varchar(50) NOT NULL,
    direction varchar(10) NOT NULL,
    sender_id varchar(150),
    receiver_id varchar(150),
    document_uri text,
    document_sha256 char(64),
    status varchar(20) NOT NULL DEFAULT 'RECEIVED',
    acknowledgement_status varchar(20) NOT NULL DEFAULT 'PENDING',
    received_at timestamptz,
    processed_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (external_system_id, direction, interchange_control_no, transaction_set_no),
    CONSTRAINT ck_edi_direction CHECK (direction IN ('IN','OUT'))
);

CREATE TABLE IF NOT EXISTS etms.edi_validation_errors (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    edi_document_id uuid NOT NULL REFERENCES etms.edi_documents(id) ON DELETE CASCADE,
    error_level varchar(20) NOT NULL,
    segment_id varchar(30),
    element_position varchar(30),
    error_code varchar(80) NOT NULL,
    error_message text NOT NULL,
    offending_value_masked text,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_edi_error_level CHECK (error_level IN ('INFO','WARNING','ERROR','FATAL'))
);

CREATE TABLE IF NOT EXISTS etms.webhook_subscriptions (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    subscription_code varchar(100) NOT NULL,
    target_url text NOT NULL,
    event_types text[] NOT NULL,
    secret_hash char(64),
    signing_key_secret_ref varchar(300),
    http_headers_encrypted text,
    retry_policy jsonb NOT NULL DEFAULT '{}'::jsonb,
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    last_success_at timestamptz,
    last_failure_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, subscription_code)
);

CREATE TABLE IF NOT EXISTS etms.webhook_deliveries (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    subscription_id uuid NOT NULL REFERENCES etms.webhook_subscriptions(id) ON DELETE CASCADE,
    outbox_event_id uuid REFERENCES etms.outbox_events(id),
    event_type varchar(120) NOT NULL,
    payload_hash char(64) NOT NULL,
    attempt_no integer NOT NULL DEFAULT 1,
    requested_at timestamptz,
    responded_at timestamptz,
    http_status integer,
    response_body_masked text,
    status varchar(20) NOT NULL DEFAULT 'QUEUED',
    next_attempt_at timestamptz,
    error_detail_masked text,
    UNIQUE (subscription_id, outbox_event_id, attempt_no),
    CONSTRAINT ck_webhook_attempt CHECK (attempt_no > 0),
    CONSTRAINT ck_webhook_http_status CHECK (http_status IS NULL OR http_status BETWEEN 100 AND 599)
);

CREATE TABLE IF NOT EXISTS etms.inbox_deduplication (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    source_system_id uuid NOT NULL REFERENCES etms.external_systems(id),
    message_type varchar(100) NOT NULL,
    idempotency_key varchar(300) NOT NULL,
    payload_hash char(64) NOT NULL,
    first_received_at timestamptz NOT NULL DEFAULT now(),
    last_received_at timestamptz NOT NULL DEFAULT now(),
    receive_count integer NOT NULL DEFAULT 1,
    processed_resource_type varchar(80),
    processed_resource_id uuid,
    status varchar(20) NOT NULL DEFAULT 'RECEIVED',
    UNIQUE (source_system_id, message_type, idempotency_key),
    CONSTRAINT ck_inbox_receive_count CHECK (receive_count > 0)
);

CREATE TABLE IF NOT EXISTS etms.import_jobs (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    job_no varchar(100) NOT NULL,
    import_type varchar(80) NOT NULL,
    source_file_id uuid NOT NULL REFERENCES etms.files(id),
    mapping_version varchar(50),
    validation_only boolean NOT NULL DEFAULT false,
    status varchar(20) NOT NULL DEFAULT 'QUEUED',
    total_rows integer NOT NULL DEFAULT 0,
    success_rows integer NOT NULL DEFAULT 0,
    warning_rows integer NOT NULL DEFAULT 0,
    error_rows integer NOT NULL DEFAULT 0,
    requested_by uuid REFERENCES etms.users(id),
    requested_at timestamptz NOT NULL DEFAULT now(),
    started_at timestamptz,
    completed_at timestamptz,
    result_file_id uuid REFERENCES etms.files(id),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, job_no),
    CONSTRAINT ck_import_job_counts CHECK (
        total_rows >= 0 AND success_rows >= 0 AND warning_rows >= 0 AND error_rows >= 0 AND
        success_rows + warning_rows + error_rows <= total_rows
    )
);

CREATE TABLE IF NOT EXISTS etms.import_job_rows (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    import_job_id uuid NOT NULL REFERENCES etms.import_jobs(id) ON DELETE CASCADE,
    row_no integer NOT NULL,
    source_data_masked jsonb NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'PENDING',
    target_entity_type varchar(80),
    target_entity_id uuid,
    validation_errors jsonb NOT NULL DEFAULT '[]'::jsonb,
    processed_at timestamptz,
    UNIQUE (import_job_id, row_no),
    CONSTRAINT ck_import_job_row_no CHECK (row_no > 0)
);

CREATE TABLE IF NOT EXISTS etms.export_jobs (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    job_no varchar(100) NOT NULL,
    export_type varchar(80) NOT NULL,
    output_format varchar(20) NOT NULL,
    filters jsonb NOT NULL DEFAULT '{}'::jsonb,
    selected_fields jsonb NOT NULL DEFAULT '[]'::jsonb,
    status varchar(20) NOT NULL DEFAULT 'QUEUED',
    row_count bigint NOT NULL DEFAULT 0,
    output_file_id uuid REFERENCES etms.files(id),
    requested_by uuid REFERENCES etms.users(id),
    requested_at timestamptz NOT NULL DEFAULT now(),
    completed_at timestamptz,
    expires_at timestamptz,
    error_detail_masked text,
    UNIQUE (tenant_id, job_no),
    CONSTRAINT ck_export_job_format CHECK (output_format IN ('CSV','XLSX','JSON','XML','PDF','EDI')),
    CONSTRAINT ck_export_job_count CHECK (row_count >= 0)
);

CREATE TABLE IF NOT EXISTS etms.scheduled_jobs (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid REFERENCES etms.tenants(id) ON DELETE CASCADE,
    job_code varchar(100) NOT NULL,
    job_name varchar(250) NOT NULL,
    job_type varchar(80) NOT NULL,
    cron_expression varchar(100) NOT NULL,
    timezone varchar(100) NOT NULL DEFAULT 'Asia/Seoul',
    parameters jsonb NOT NULL DEFAULT '{}'::jsonb,
    concurrency_policy varchar(20) NOT NULL DEFAULT 'FORBID',
    timeout_seconds integer NOT NULL DEFAULT 3600,
    retry_limit integer NOT NULL DEFAULT 3,
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    next_run_at timestamptz,
    last_run_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_scheduled_job_timeout CHECK (timeout_seconds > 0 AND retry_limit >= 0),
    CONSTRAINT ck_scheduled_job_concurrency CHECK (concurrency_policy IN ('ALLOW','FORBID','REPLACE'))
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_scheduled_jobs_scope
    ON etms.scheduled_jobs (
        COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), job_code
    );

CREATE TABLE IF NOT EXISTS etms.job_runs (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    scheduled_job_id uuid NOT NULL REFERENCES etms.scheduled_jobs(id) ON DELETE CASCADE,
    run_no bigint NOT NULL,
    trigger_type varchar(20) NOT NULL DEFAULT 'SCHEDULED',
    status varchar(20) NOT NULL DEFAULT 'QUEUED',
    queued_at timestamptz NOT NULL DEFAULT now(),
    started_at timestamptz,
    completed_at timestamptz,
    processed_count bigint NOT NULL DEFAULT 0,
    success_count bigint NOT NULL DEFAULT 0,
    error_count bigint NOT NULL DEFAULT 0,
    result_summary jsonb NOT NULL DEFAULT '{}'::jsonb,
    error_detail_masked text,
    correlation_id varchar(100),
    UNIQUE (scheduled_job_id, run_no),
    CONSTRAINT ck_job_run_counts CHECK (
        processed_count >= 0 AND success_count >= 0 AND error_count >= 0 AND
        success_count + error_count <= processed_count
    )
);

CREATE TABLE IF NOT EXISTS etms.dead_letter_messages (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    source_type varchar(30) NOT NULL,
    source_id uuid,
    message_type varchar(100) NOT NULL,
    payload_uri text,
    payload_hash char(64),
    failure_code varchar(100),
    failure_detail_masked text NOT NULL,
    failed_at timestamptz NOT NULL DEFAULT now(),
    retry_count integer NOT NULL DEFAULT 0,
    next_retry_at timestamptz,
    status varchar(20) NOT NULL DEFAULT 'OPEN',
    resolved_at timestamptz,
    resolved_by uuid REFERENCES etms.users(id),
    resolution text,
    CONSTRAINT ck_dead_letter_retry CHECK (retry_count >= 0)
);

CREATE TABLE IF NOT EXISTS etms.impersonation_events (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    administrator_user_id uuid NOT NULL REFERENCES etms.users(id),
    impersonated_user_id uuid NOT NULL REFERENCES etms.users(id),
    reason text NOT NULL,
    ticket_reference varchar(150),
    started_at timestamptz NOT NULL,
    ended_at timestamptz,
    ip_address inet,
    user_agent text,
    approved_by uuid REFERENCES etms.users(id),
    CONSTRAINT ck_impersonation_users CHECK (administrator_user_id <> impersonated_user_id),
    CONSTRAINT ck_impersonation_dates CHECK (ended_at IS NULL OR ended_at >= started_at)
);

CREATE TABLE IF NOT EXISTS etms.entity_change_logs (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    entity_type varchar(80) NOT NULL,
    entity_id uuid NOT NULL,
    operation varchar(10) NOT NULL,
    changed_fields text[],
    before_data_masked jsonb,
    after_data_masked jsonb,
    row_version_before bigint,
    row_version_after bigint,
    actor_user_id uuid REFERENCES etms.users(id),
    correlation_id varchar(100),
    occurred_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_entity_change_operation CHECK (operation IN ('INSERT','UPDATE','DELETE','RESTORE'))
);

CREATE TABLE IF NOT EXISTS etms.data_access_logs (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid REFERENCES etms.tenants(id),
    actor_user_id uuid REFERENCES etms.users(id),
    actor_api_client_id uuid REFERENCES etms.api_clients(id),
    access_type varchar(30) NOT NULL,
    entity_type varchar(80) NOT NULL,
    entity_id uuid,
    field_categories text[],
    purpose_code varchar(80),
    result_count integer,
    ip_address inet,
    correlation_id varchar(100),
    occurred_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_data_access_actor CHECK (actor_user_id IS NOT NULL OR actor_api_client_id IS NOT NULL),
    CONSTRAINT ck_data_access_count CHECK (result_count IS NULL OR result_count >= 0)
);

-- Link/detail/history tables inherit tenant ownership explicitly. This makes RLS and
-- cross-tenant FK checks effective even when the natural parent key is globally unique.
DO $block$
DECLARE
    table_name text;
    constraint_name text;
    tenant_nullable_tables constant text[] := ARRAY[
        'code_values',
        'fuel_index_values',
        'job_runs',
        'role_permissions',
        'tax_rates'
    ]::text[];
BEGIN
    FOREACH table_name IN ARRAY ARRAY[
        'api_client_permissions','approval_actions','approval_steps','calendar_dates','carrier_booking_items',
        'carrier_insurance_policies','carrier_profiles','carrier_scorecard_metrics',
        'carrier_service_regions','claim_events','claim_items','claim_reserves','claim_settlements',
        'code_values','consolidation_group_orders','contract_parties','contract_service_scopes',
        'customs_declaration_items','dangerous_goods_profiles','dispatch_acknowledgements',
        'dispatch_instructions','dock_appointment_history','driver_availability',
        'driver_certifications','driver_licenses','driver_task_events','edi_validation_errors',
        'exception_actions','execution_checklist_items','fuel_index_values','handling_unit_contents',
        'import_job_rows','incident_items','incident_parties','invoice_dispute_events',
        'invoice_line_charges','invoice_taxes','item_packagings','job_runs','journal_lines',
        'lane_points','location_blackouts','location_contacts','location_docks',
        'location_operating_hours','manifest_items','notification_deliveries','odometer_readings',
        'order_line_requirements','order_stop_lines','order_stop_time_windows','partner_addresses',
        'partner_bank_accounts','partner_certifications','partner_contacts','partner_identifiers',
        'partner_roles','partner_tax_profiles','payment_applications','planning_constraints',
        'planning_run_logs','planning_run_results','planning_scenario_orders','pod_items',
        'pod_signatures','rate_contract_versions','rate_lanes','rate_quote_lines','rate_rule_tiers',
        'rating_run_details','role_permissions','route_legs','route_plan_segments','settlement_lines',
        'shipment_leg_allocations','shipment_stop_orders','sla_policy_milestones',
        'tax_invoice_events','tax_invoice_lines','tax_rates','tender_responses','tender_rounds','terminal_cutoffs',
        'transport_document_lines','transport_order_references','transport_requirement_profiles',
        'transport_schedule_calls','user_group_members','workflow_steps','workflow_versions'
    ]::text[]
    LOOP
        EXECUTE format(
            'ALTER TABLE etms.%I ADD COLUMN IF NOT EXISTS tenant_id uuid', table_name
        );

        constraint_name := 'fk_' || substr(table_name, 1, 35) || '_tenant_' ||
            substr(md5(table_name), 1, 8);
        IF NOT EXISTS (
            SELECT 1
            FROM pg_constraint c
            WHERE c.conrelid = format('etms.%I', table_name)::regclass
              AND c.conname = constraint_name
        ) THEN
            EXECUTE format(
                'ALTER TABLE etms.%I ADD CONSTRAINT %I FOREIGN KEY (tenant_id) '
                'REFERENCES etms.tenants(id)',
                table_name, constraint_name
            );
        END IF;

        IF NOT (table_name = ANY (tenant_nullable_tables)) THEN
            EXECUTE format(
                'ALTER TABLE etms.%I ALTER COLUMN tenant_id SET NOT NULL', table_name
            );
        END IF;
    END LOOP;
END;
$block$;

-- Add database-native composite tenant FKs for every relationship whose parent and child
-- are strictly tenant-owned. These remain safe regardless of RLS or connection role.
DO $block$
DECLARE
    r record;
    child_column text;
    parent_index_name text;
    tenant_constraint_name text;
BEGIN
    FOR r IN
        SELECT c.oid AS table_oid, n.nspname AS schema_name, c.relname AS table_name
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'etms'
          AND c.relkind = 'r'
          AND EXISTS (
              SELECT 1 FROM pg_attribute a
              WHERE a.attrelid = c.oid AND a.attname = 'id' AND NOT a.attisdropped
          )
          AND EXISTS (
              SELECT 1 FROM pg_attribute a
              WHERE a.attrelid = c.oid AND a.attname = 'tenant_id'
                AND a.attnotnull AND NOT a.attisdropped
          )
    LOOP
        parent_index_name := 'ux_tenant_id_' || substr(md5(r.schema_name || '.' || r.table_name), 1, 16);
        EXECUTE format(
            'CREATE UNIQUE INDEX IF NOT EXISTS %I ON %I.%I (tenant_id, id)',
            parent_index_name, r.schema_name, r.table_name
        );
    END LOOP;

    FOR r IN
        SELECT con.oid, con.conname, con.conrelid, con.confrelid,
               child_ns.nspname AS child_schema, child.relname AS child_table,
               parent_ns.nspname AS parent_schema, parent.relname AS parent_table,
               con.conkey[1] AS child_attnum
        FROM pg_constraint con
        JOIN pg_class child ON child.oid = con.conrelid
        JOIN pg_namespace child_ns ON child_ns.oid = child.relnamespace
        JOIN pg_class parent ON parent.oid = con.confrelid
        JOIN pg_namespace parent_ns ON parent_ns.oid = parent.relnamespace
        WHERE con.contype = 'f'
          AND con.confdeltype = 'a'
          AND con.confupdtype = 'a'
          AND child_ns.nspname = 'etms'
          AND parent_ns.nspname = 'etms'
          AND array_length(con.conkey, 1) = 1
          AND EXISTS (
              SELECT 1 FROM pg_attribute a
              WHERE a.attrelid = con.conrelid AND a.attname = 'tenant_id'
                AND a.attnotnull AND NOT a.attisdropped
          )
          AND EXISTS (
              SELECT 1 FROM pg_attribute a
              WHERE a.attrelid = con.confrelid AND a.attname = 'tenant_id'
                AND a.attnotnull AND NOT a.attisdropped
          )
          AND EXISTS (
              SELECT 1 FROM pg_attribute a
              WHERE a.attrelid = con.confrelid AND a.attnum = con.confkey[1] AND a.attname = 'id'
          )
    LOOP
        SELECT attname INTO child_column
        FROM pg_attribute
        WHERE attrelid = r.conrelid AND attnum = r.child_attnum;
        IF child_column = 'tenant_id' THEN CONTINUE; END IF;

        tenant_constraint_name := 'fk_tenant_scope_' || substr(
            md5(r.child_schema || '.' || r.child_table || '.' || child_column || '.' || r.parent_table),
            1, 20
        );
        IF NOT EXISTS (
            SELECT 1 FROM pg_constraint c
            WHERE c.conrelid = r.conrelid AND c.conname = tenant_constraint_name
        ) THEN
            EXECUTE format(
                'ALTER TABLE %I.%I ADD CONSTRAINT %I '
                'FOREIGN KEY (tenant_id, %I) REFERENCES %I.%I (tenant_id, id)',
                r.child_schema, r.child_table, tenant_constraint_name,
                child_column, r.parent_schema, r.parent_table
            );
        END IF;
    END LOOP;
END;
$block$;

-- Prevent tenant_id changes after creation. Moving records between tenants must be an audited copy operation.
CREATE OR REPLACE FUNCTION etms.prevent_tenant_change()
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

-- Cross-tenant FK guard for every single-column UUID FK between tenant-scoped tables.
CREATE OR REPLACE FUNCTION etms.enforce_same_tenant_fk()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    child_reference uuid;
    parent_tenant uuid;
BEGIN
    child_reference := NULLIF(to_jsonb(NEW) ->> TG_ARGV[0], '')::uuid;
    IF child_reference IS NULL THEN
        RETURN NEW;
    END IF;

    EXECUTE format('SELECT tenant_id FROM %I.%I WHERE id = $1', TG_ARGV[1], TG_ARGV[2])
       INTO parent_tenant
       USING child_reference;

    IF parent_tenant IS NOT NULL AND parent_tenant IS DISTINCT FROM NEW.tenant_id THEN
        RAISE EXCEPTION 'Cross-tenant reference rejected: %.% -> %.%',
            TG_TABLE_SCHEMA, TG_TABLE_NAME, TG_ARGV[1], TG_ARGV[2]
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

-- Core aggregate guards prevent same-tenant but wrong-parent links that ordinary FKs cannot detect.
CREATE OR REPLACE FUNCTION etms.validate_order_line_stops()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
BEGIN
    IF NEW.pickup_stop_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM etms.transport_order_stops s
        WHERE s.id = NEW.pickup_stop_id AND s.order_id = NEW.order_id
    ) THEN
        RAISE EXCEPTION 'pickup_stop_id must belong to the same transport order'
            USING ERRCODE = '23514';
    END IF;
    IF NEW.delivery_stop_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM etms.transport_order_stops s
        WHERE s.id = NEW.delivery_stop_id AND s.order_id = NEW.order_id
    ) THEN
        RAISE EXCEPTION 'delivery_stop_id must belong to the same transport order'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION etms.validate_order_stop_line()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    stop_order_id uuid;
    line_order_id uuid;
BEGIN
    SELECT order_id INTO stop_order_id FROM etms.transport_order_stops WHERE id = NEW.order_stop_id;
    SELECT order_id INTO line_order_id FROM etms.transport_order_lines WHERE id = NEW.order_line_id;
    IF stop_order_id IS DISTINCT FROM line_order_id THEN
        RAISE EXCEPTION 'order_stop_lines must link a stop and line from the same order'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION etms.validate_shipment_leg_stops()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM etms.shipment_stops f, etms.shipment_stops t
        WHERE f.id = NEW.from_stop_id
          AND t.id = NEW.to_stop_id
          AND f.shipment_id = NEW.shipment_id
          AND t.shipment_id = NEW.shipment_id
    ) THEN
        RAISE EXCEPTION 'shipment leg endpoints must belong to the same shipment as the leg'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION etms.validate_shipment_stop_order()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    parent_shipment_id uuid;
    parent_order_id uuid;
BEGIN
    SELECT shipment_id INTO parent_shipment_id
    FROM etms.shipment_stops WHERE id = NEW.shipment_stop_id;

    IF NEW.order_stop_id IS NOT NULL THEN
        SELECT order_id INTO parent_order_id
        FROM etms.transport_order_stops WHERE id = NEW.order_stop_id;
        IF parent_order_id IS DISTINCT FROM NEW.order_id THEN
            RAISE EXCEPTION 'order_stop_id must belong to shipment_stop_orders.order_id'
                USING ERRCODE = '23514';
        END IF;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM etms.shipment_orders so
        WHERE so.shipment_id = parent_shipment_id
          AND so.order_id = NEW.order_id
          AND so.removed_at IS NULL
    ) THEN
        RAISE EXCEPTION 'order must be actively allocated to the shipment before stop activity is linked'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION etms.validate_handling_unit_content()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    handling_order_id uuid;
    line_order_id uuid;
BEGIN
    SELECT order_id INTO handling_order_id FROM etms.handling_units WHERE id = NEW.handling_unit_id;
    SELECT order_id INTO line_order_id FROM etms.transport_order_lines WHERE id = NEW.order_line_id;
    IF handling_order_id IS DISTINCT FROM line_order_id THEN
        RAISE EXCEPTION 'handling unit contents must belong to the handling unit order'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION etms.validate_leg_allocation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    parent_shipment_id uuid;
    parent_order_id uuid;
    handling_order_id uuid;
BEGIN
    SELECT shipment_id INTO parent_shipment_id
    FROM etms.shipment_legs WHERE id = NEW.shipment_leg_id;
    SELECT order_id INTO parent_order_id
    FROM etms.transport_order_lines WHERE id = NEW.order_line_id;

    IF NOT EXISTS (
        SELECT 1 FROM etms.shipment_orders so
        WHERE so.shipment_id = parent_shipment_id
          AND so.order_id = parent_order_id
          AND so.removed_at IS NULL
    ) THEN
        RAISE EXCEPTION 'leg allocation order line must belong to an order allocated to the shipment'
            USING ERRCODE = '23514';
    END IF;

    IF NEW.handling_unit_id IS NOT NULL THEN
        SELECT order_id INTO handling_order_id
        FROM etms.handling_units WHERE id = NEW.handling_unit_id;
        IF handling_order_id IS DISTINCT FROM parent_order_id THEN
            RAISE EXCEPTION 'leg allocation handling unit and order line must belong to the same order'
                USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION etms.validate_pod_order()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    pod_run_id uuid;
BEGIN
    IF NEW.order_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM etms.shipment_orders so
        WHERE so.shipment_id = NEW.shipment_id
          AND so.order_id = NEW.order_id
          AND so.removed_at IS NULL
    ) THEN
        RAISE EXCEPTION 'POD order must be actively allocated to the POD shipment'
            USING ERRCODE = '23514';
    END IF;
    IF NEW.run_stop_id IS NOT NULL THEN
        SELECT run_id INTO pod_run_id FROM etms.run_stops WHERE id = NEW.run_stop_id;
        IF NOT EXISTS (
            SELECT 1
            FROM etms.run_legs rl
            LEFT JOIN etms.shipment_legs direct_leg ON direct_leg.id = rl.shipment_leg_id
            LEFT JOIN etms.run_leg_allocations rla ON rla.run_leg_id = rl.id
            LEFT JOIN etms.shipment_leg_allocations sla ON sla.id = rla.shipment_leg_allocation_id
            LEFT JOIN etms.shipment_legs allocated_leg ON allocated_leg.id = sla.shipment_leg_id
            WHERE rl.run_id = pod_run_id
              AND (direct_leg.shipment_id = NEW.shipment_id OR allocated_leg.shipment_id = NEW.shipment_id)
        ) THEN
            RAISE EXCEPTION 'POD run stop must belong to a run executing the POD shipment'
                USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION etms.validate_pod_item_parentage()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    pod_shipment_id uuid;
    pod_order_id uuid;
    item_order_id uuid;
    handling_order_id uuid;
BEGIN
    SELECT shipment_id, order_id INTO pod_shipment_id, pod_order_id
    FROM etms.proof_of_deliveries WHERE id = NEW.pod_id;
    IF NEW.order_line_id IS NOT NULL THEN
        SELECT order_id INTO item_order_id
        FROM etms.transport_order_lines WHERE id = NEW.order_line_id;
    END IF;
    IF NEW.handling_unit_id IS NOT NULL THEN
        SELECT order_id INTO handling_order_id
        FROM etms.handling_units WHERE id = NEW.handling_unit_id;
    END IF;
    IF item_order_id IS NOT NULL AND handling_order_id IS NOT NULL
       AND item_order_id IS DISTINCT FROM handling_order_id THEN
        RAISE EXCEPTION 'POD item line and handling unit must belong to the same order'
            USING ERRCODE = '23514';
    END IF;
    item_order_id := COALESCE(item_order_id, handling_order_id);
    IF pod_order_id IS NOT NULL AND item_order_id IS DISTINCT FROM pod_order_id THEN
        RAISE EXCEPTION 'POD item must belong to the POD order'
            USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM etms.shipment_orders so
        WHERE so.shipment_id = pod_shipment_id
          AND so.order_id = item_order_id
          AND so.removed_at IS NULL
    ) THEN
        RAISE EXCEPTION 'POD item order must be actively allocated to the POD shipment'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_validate_order_line_stops ON etms.transport_order_lines;
CREATE TRIGGER trg_validate_order_line_stops
BEFORE INSERT OR UPDATE OF order_id, pickup_stop_id, delivery_stop_id
ON etms.transport_order_lines
FOR EACH ROW EXECUTE PROCEDURE etms.validate_order_line_stops();

DROP TRIGGER IF EXISTS trg_validate_order_stop_line ON etms.order_stop_lines;
CREATE TRIGGER trg_validate_order_stop_line
BEFORE INSERT OR UPDATE OF order_stop_id, order_line_id
ON etms.order_stop_lines
FOR EACH ROW EXECUTE PROCEDURE etms.validate_order_stop_line();

DROP TRIGGER IF EXISTS trg_validate_shipment_leg_stops ON etms.shipment_legs;
CREATE TRIGGER trg_validate_shipment_leg_stops
BEFORE INSERT OR UPDATE OF shipment_id, from_stop_id, to_stop_id
ON etms.shipment_legs
FOR EACH ROW EXECUTE PROCEDURE etms.validate_shipment_leg_stops();

DROP TRIGGER IF EXISTS trg_validate_shipment_stop_order ON etms.shipment_stop_orders;
CREATE TRIGGER trg_validate_shipment_stop_order
BEFORE INSERT OR UPDATE OF shipment_stop_id, order_id, order_stop_id
ON etms.shipment_stop_orders
FOR EACH ROW EXECUTE PROCEDURE etms.validate_shipment_stop_order();

DROP TRIGGER IF EXISTS trg_validate_handling_unit_content ON etms.handling_unit_contents;
CREATE TRIGGER trg_validate_handling_unit_content
BEFORE INSERT OR UPDATE OF handling_unit_id, order_line_id
ON etms.handling_unit_contents
FOR EACH ROW EXECUTE PROCEDURE etms.validate_handling_unit_content();

DROP TRIGGER IF EXISTS trg_validate_leg_allocation ON etms.shipment_leg_allocations;
CREATE TRIGGER trg_validate_leg_allocation
BEFORE INSERT OR UPDATE OF shipment_leg_id, order_line_id, handling_unit_id
ON etms.shipment_leg_allocations
FOR EACH ROW EXECUTE PROCEDURE etms.validate_leg_allocation();

DROP TRIGGER IF EXISTS trg_validate_pod_order ON etms.proof_of_deliveries;
CREATE TRIGGER trg_validate_pod_order
BEFORE INSERT OR UPDATE OF shipment_id, order_id
ON etms.proof_of_deliveries
FOR EACH ROW EXECUTE PROCEDURE etms.validate_pod_order();

DROP TRIGGER IF EXISTS trg_validate_pod_item_parentage ON etms.pod_items;
CREATE TRIGGER trg_validate_pod_item_parentage
BEFORE INSERT OR UPDATE OF pod_id, order_line_id, handling_unit_id
ON etms.pod_items
FOR EACH ROW EXECUTE PROCEDURE etms.validate_pod_item_parentage();

CREATE OR REPLACE FUNCTION etms.validate_unit_conversion()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    from_dimension text;
    to_dimension text;
BEGIN
    PERFORM pg_advisory_xact_lock(hashtext(
        'uom-conversion:' || NEW.from_uom_code || ':' || NEW.to_uom_code
    ));
    SELECT dimension INTO from_dimension FROM etms.units_of_measure WHERE uom_code = NEW.from_uom_code;
    SELECT dimension INTO to_dimension FROM etms.units_of_measure WHERE uom_code = NEW.to_uom_code;
    IF from_dimension IS DISTINCT FROM to_dimension THEN
        RAISE EXCEPTION 'Unit conversion dimensions must match (% to %)', from_dimension, to_dimension
            USING ERRCODE = '23514';
    END IF;
    IF EXISTS (
        SELECT 1 FROM etms.unit_conversions c
        WHERE c.from_uom_code = NEW.from_uom_code
          AND c.to_uom_code = NEW.to_uom_code
          AND c.valid_from <= COALESCE(NEW.valid_to, 'infinity'::date)
          AND NEW.valid_from <= COALESCE(c.valid_to, 'infinity'::date)
          AND (
              TG_OP <> 'UPDATE' OR
              (c.from_uom_code, c.to_uom_code, c.valid_from) IS DISTINCT FROM
              (OLD.from_uom_code, OLD.to_uom_code, OLD.valid_from)
          )
    ) THEN
        RAISE EXCEPTION 'Unit conversion effective periods may not overlap'
            USING ERRCODE = '23P01';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION etms.validate_rate_basis_uom()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    actual_dimension text;
    expected_dimension text;
BEGIN
    expected_dimension := CASE NEW.basis_type
        WHEN 'WEIGHT' THEN 'MASS'
        WHEN 'VOLUME' THEN 'VOLUME'
        WHEN 'DISTANCE' THEN 'DISTANCE'
        WHEN 'TIME' THEN 'TIME'
        WHEN 'PALLET' THEN 'COUNT'
        WHEN 'HANDLING_UNIT' THEN 'COUNT'
        WHEN 'QUANTITY' THEN 'COUNT'
        ELSE NULL
    END;
    IF expected_dimension IS NOT NULL THEN
        IF NEW.basis_uom_code IS NULL THEN
            RAISE EXCEPTION 'Rate basis % requires a basis UOM', NEW.basis_type
                USING ERRCODE = '23514';
        END IF;
        SELECT dimension INTO actual_dimension
        FROM etms.units_of_measure WHERE uom_code = NEW.basis_uom_code;
        IF actual_dimension IS DISTINCT FROM expected_dimension THEN
            RAISE EXCEPTION 'Rate basis % requires UOM dimension %, got %',
                NEW.basis_type, expected_dimension, actual_dimension USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION etms.prevent_driver_assignment_overlap()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
BEGIN
    PERFORM pg_advisory_xact_lock(hashtext('driver-assignment:' || NEW.driver_id::text));
    IF NEW.status NOT IN ('CANCELLED','REJECTED','RELEASED') AND EXISTS (
        SELECT 1 FROM etms.run_driver_assignments a
        WHERE a.driver_id = NEW.driver_id
          AND a.id <> NEW.id
          AND a.status NOT IN ('CANCELLED','REJECTED','RELEASED')
          AND a.valid_from < COALESCE(NEW.valid_to, 'infinity'::timestamptz)
          AND NEW.valid_from < COALESCE(a.valid_to, 'infinity'::timestamptz)
    ) THEN
        RAISE EXCEPTION 'Driver assignment periods may not overlap'
            USING ERRCODE = '23P01';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION etms.prevent_equipment_assignment_overlap()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
BEGIN
    PERFORM pg_advisory_xact_lock(hashtext(
        'equipment-assignment:' || NEW.equipment_kind || ':' || NEW.equipment_id::text
    ));
    IF NEW.status NOT IN ('CANCELLED','REJECTED','RELEASED') AND EXISTS (
        SELECT 1 FROM etms.run_equipment_assignments a
        WHERE a.equipment_kind = NEW.equipment_kind
          AND a.equipment_id = NEW.equipment_id
          AND a.id <> NEW.id
          AND a.status NOT IN ('CANCELLED','REJECTED','RELEASED')
          AND a.valid_from < COALESCE(NEW.valid_to, 'infinity'::timestamptz)
          AND NEW.valid_from < COALESCE(a.valid_to, 'infinity'::timestamptz)
    ) THEN
        RAISE EXCEPTION 'Equipment assignment periods may not overlap'
            USING ERRCODE = '23P01';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION etms.validate_polymorphic_asset_reference()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    kind_value text := to_jsonb(NEW) ->> TG_ARGV[0];
    asset_value uuid := NULLIF(to_jsonb(NEW) ->> TG_ARGV[1], '')::uuid;
    asset_tenant uuid;
BEGIN
    IF kind_value = 'VEHICLE' THEN
        SELECT tenant_id INTO asset_tenant FROM etms.vehicles WHERE id = asset_value;
    ELSIF kind_value = 'TRAILER' THEN
        SELECT tenant_id INTO asset_tenant FROM etms.trailers WHERE id = asset_value;
    ELSIF kind_value = 'CONTAINER' THEN
        SELECT tenant_id INTO asset_tenant FROM etms.containers WHERE id = asset_value;
    ELSIF kind_value = 'HANDLING_UNIT' THEN
        SELECT tenant_id INTO asset_tenant FROM etms.handling_units WHERE id = asset_value;
    ELSIF kind_value = 'SHIPMENT' THEN
        SELECT tenant_id INTO asset_tenant FROM etms.shipments WHERE id = asset_value;
    ELSE
        RAISE EXCEPTION 'Unsupported polymorphic asset kind %', kind_value
            USING ERRCODE = '23514';
    END IF;
    IF asset_tenant IS NULL OR asset_tenant IS DISTINCT FROM NEW.tenant_id THEN
        RAISE EXCEPTION 'Asset % % does not exist in the current tenant', kind_value, asset_value
            USING ERRCODE = '23503';
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_validate_unit_conversion ON etms.unit_conversions;
CREATE TRIGGER trg_validate_unit_conversion
BEFORE INSERT OR UPDATE ON etms.unit_conversions
FOR EACH ROW EXECUTE PROCEDURE etms.validate_unit_conversion();

DROP TRIGGER IF EXISTS trg_validate_rate_basis_uom ON etms.rate_rules;
CREATE TRIGGER trg_validate_rate_basis_uom
BEFORE INSERT OR UPDATE OF basis_type, basis_uom_code ON etms.rate_rules
FOR EACH ROW EXECUTE PROCEDURE etms.validate_rate_basis_uom();

DROP TRIGGER IF EXISTS trg_prevent_driver_assignment_overlap ON etms.run_driver_assignments;
CREATE TRIGGER trg_prevent_driver_assignment_overlap
BEFORE INSERT OR UPDATE OF driver_id, valid_from, valid_to, status ON etms.run_driver_assignments
FOR EACH ROW EXECUTE PROCEDURE etms.prevent_driver_assignment_overlap();

DROP TRIGGER IF EXISTS trg_prevent_equipment_assignment_overlap ON etms.run_equipment_assignments;
CREATE TRIGGER trg_prevent_equipment_assignment_overlap
BEFORE INSERT OR UPDATE OF equipment_kind, equipment_id, valid_from, valid_to, status
ON etms.run_equipment_assignments
FOR EACH ROW EXECUTE PROCEDURE etms.prevent_equipment_assignment_overlap();

DROP TRIGGER IF EXISTS trg_validate_run_equipment_asset ON etms.run_equipment_assignments;
CREATE TRIGGER trg_validate_run_equipment_asset
BEFORE INSERT OR UPDATE OF equipment_kind, equipment_id, tenant_id
ON etms.run_equipment_assignments
FOR EACH ROW EXECUTE PROCEDURE etms.validate_polymorphic_asset_reference('equipment_kind','equipment_id');

DROP TRIGGER IF EXISTS trg_validate_equipment_document_asset ON etms.equipment_documents;
CREATE TRIGGER trg_validate_equipment_document_asset
BEFORE INSERT OR UPDATE OF equipment_kind, equipment_id, tenant_id
ON etms.equipment_documents
FOR EACH ROW EXECUTE PROCEDURE etms.validate_polymorphic_asset_reference('equipment_kind','equipment_id');

DROP TRIGGER IF EXISTS trg_validate_equipment_availability_asset ON etms.equipment_availability;
CREATE TRIGGER trg_validate_equipment_availability_asset
BEFORE INSERT OR UPDATE OF equipment_kind, equipment_id, tenant_id
ON etms.equipment_availability
FOR EACH ROW EXECUTE PROCEDURE etms.validate_polymorphic_asset_reference('equipment_kind','equipment_id');

DROP TRIGGER IF EXISTS trg_validate_device_assignment_asset ON etms.device_assignments;
CREATE TRIGGER trg_validate_device_assignment_asset
BEFORE INSERT OR UPDATE OF asset_type, asset_id, tenant_id
ON etms.device_assignments
FOR EACH ROW EXECUTE PROCEDURE etms.validate_polymorphic_asset_reference('asset_type','asset_id');

DROP TRIGGER IF EXISTS trg_validate_sensor_assignment_asset ON etms.sensor_assignments;
CREATE TRIGGER trg_validate_sensor_assignment_asset
BEFORE INSERT OR UPDATE OF asset_type, asset_id, tenant_id
ON etms.sensor_assignments
FOR EACH ROW EXECUTE PROCEDURE etms.validate_polymorphic_asset_reference('asset_type','asset_id');

-- Financial documents are editable in DRAFT, but totals must reconcile before posting/finalization.
CREATE OR REPLACE FUNCTION etms.validate_invoice_totals()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    line_net numeric(20,4);
    line_tax numeric(20,4);
    line_gross numeric(20,4);
    tax_summary numeric(20,4);
BEGIN
    IF NEW.status NOT IN ('DRAFT','RECEIVED','VALIDATING','REJECTED','CANCELLED') THEN
        SELECT COALESCE(sum(net_amount - discount_amount), 0),
               COALESCE(sum(tax_amount), 0),
               COALESCE(sum(gross_amount), 0)
          INTO line_net, line_tax, line_gross
        FROM etms.invoice_lines WHERE invoice_id = NEW.id;

        IF NEW.net_amount IS DISTINCT FROM line_net
           OR NEW.tax_amount IS DISTINCT FROM line_tax
           OR NEW.gross_amount IS DISTINCT FROM line_gross THEN
            RAISE EXCEPTION 'Invoice header totals do not reconcile to invoice lines'
                USING ERRCODE = '23514';
        END IF;

        SELECT sum(tax_amount) INTO tax_summary
        FROM etms.invoice_taxes WHERE invoice_id = NEW.id;
        IF tax_summary IS NOT NULL AND NEW.tax_amount IS DISTINCT FROM tax_summary THEN
            RAISE EXCEPTION 'Invoice tax summary does not reconcile to the header tax amount'
                USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION etms.validate_tax_invoice_totals()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    line_supply numeric(20,4);
    line_tax numeric(20,4);
BEGIN
    IF NEW.nts_status NOT IN ('DRAFT','VALIDATING','REJECTED','CANCELLED') THEN
        SELECT COALESCE(sum(supply_amount), 0), COALESCE(sum(tax_amount), 0)
          INTO line_supply, line_tax
        FROM etms.tax_invoice_lines WHERE tax_invoice_id = NEW.id;
        IF NEW.supply_amount IS DISTINCT FROM line_supply
           OR NEW.tax_amount IS DISTINCT FROM line_tax THEN
            RAISE EXCEPTION 'Tax invoice header totals do not reconcile to tax invoice lines'
                USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION etms.validate_settlement_totals()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    line_gross numeric(20,4);
    line_deduction numeric(20,4);
    line_tax numeric(20,4);
    line_net numeric(20,4);
BEGIN
    IF NEW.status NOT IN ('DRAFT','OPEN','CALCULATING','REJECTED','CANCELLED') THEN
        SELECT COALESCE(sum(gross_amount), 0), COALESCE(sum(deduction_amount), 0),
               COALESCE(sum(tax_amount), 0), COALESCE(sum(net_amount), 0)
          INTO line_gross, line_deduction, line_tax, line_net
        FROM etms.settlement_lines WHERE settlement_id = NEW.id;
        IF NEW.gross_amount IS DISTINCT FROM line_gross
           OR NEW.deduction_amount IS DISTINCT FROM line_deduction
           OR NEW.tax_amount IS DISTINCT FROM line_tax
           OR NEW.net_payable_amount IS DISTINCT FROM line_net THEN
            RAISE EXCEPTION 'Settlement header totals do not reconcile to settlement lines'
                USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION etms.validate_payment_application()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    target_currency char(3);
    payment_currency char(3);
BEGIN
    SELECT currency_code INTO payment_currency
    FROM etms.payments WHERE id = NEW.payment_id FOR UPDATE;
    IF NEW.invoice_id IS NOT NULL THEN
        SELECT currency_code INTO target_currency
        FROM etms.invoices WHERE id = NEW.invoice_id FOR UPDATE;
    ELSIF NEW.settlement_id IS NOT NULL THEN
        SELECT currency_code INTO target_currency
        FROM etms.settlements WHERE id = NEW.settlement_id FOR UPDATE;
    ELSE
        SELECT currency_code INTO target_currency
        FROM etms.claim_settlements WHERE id = NEW.claim_settlement_id FOR UPDATE;
    END IF;
    IF target_currency IS DISTINCT FROM payment_currency THEN
        RAISE EXCEPTION 'Payment and application target currencies must match'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION etms.validate_payment_application_sum()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    target_payment_id uuid;
    payment_total numeric(20,4);
    application_total numeric(20,4);
BEGIN
    IF TG_OP = 'DELETE' THEN
        target_payment_id := OLD.payment_id;
    ELSE
        target_payment_id := NEW.payment_id;
    END IF;
    SELECT payment_amount INTO payment_total
    FROM etms.payments WHERE id = target_payment_id FOR UPDATE;
    SELECT COALESCE(sum(applied_amount), 0) INTO application_total
    FROM etms.payment_applications WHERE payment_id = target_payment_id;
    IF application_total > payment_total THEN
        RAISE EXCEPTION 'Payment applications exceed the payment amount'
            USING ERRCODE = '23514';
    END IF;
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION etms.assert_journal_entry_balanced(target_entry_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    entry_status varchar(20);
    batch_status varchar(20);
    debit_total numeric(20,4);
    credit_total numeric(20,4);
    base_debit_total numeric(20,4);
    base_credit_total numeric(20,4);
BEGIN
    SELECT e.status, b.status INTO entry_status, batch_status
    FROM etms.journal_entries e
    JOIN etms.journal_batches b ON b.id = e.journal_batch_id
    WHERE e.id = target_entry_id;
    IF entry_status = 'POSTED' OR batch_status = 'POSTED' THEN
        SELECT COALESCE(sum(debit_amount), 0), COALESCE(sum(credit_amount), 0),
               COALESCE(sum(base_debit_amount), 0), COALESCE(sum(base_credit_amount), 0)
          INTO debit_total, credit_total, base_debit_total, base_credit_total
        FROM etms.journal_lines WHERE journal_entry_id = target_entry_id;
        IF debit_total <= 0 OR debit_total IS DISTINCT FROM credit_total
           OR base_debit_total <= 0 OR base_debit_total IS DISTINCT FROM base_credit_total THEN
            RAISE EXCEPTION 'Posted journal entry must have equal, positive transaction and base-currency totals'
                USING ERRCODE = '23514';
        END IF;
    END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION etms.validate_journal_line_balance()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
BEGIN
    IF TG_OP = 'DELETE' THEN
        PERFORM etms.assert_journal_entry_balanced(OLD.journal_entry_id);
    ELSIF TG_OP = 'UPDATE' THEN
        PERFORM etms.assert_journal_entry_balanced(OLD.journal_entry_id);
        IF NEW.journal_entry_id IS DISTINCT FROM OLD.journal_entry_id THEN
            PERFORM etms.assert_journal_entry_balanced(NEW.journal_entry_id);
        END IF;
    ELSE
        PERFORM etms.assert_journal_entry_balanced(NEW.journal_entry_id);
    END IF;
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION etms.validate_journal_entry_status()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
BEGIN
    IF NEW.status = 'POSTED' THEN
        PERFORM etms.assert_journal_entry_balanced(NEW.id);
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION etms.validate_journal_batch_posting()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    line_debit numeric(20,4);
    line_credit numeric(20,4);
    unposted_count integer;
BEGIN
    IF NEW.status = 'POSTED' THEN
        SELECT COALESCE(sum(l.debit_amount), 0), COALESCE(sum(l.credit_amount), 0)
          INTO line_debit, line_credit
        FROM etms.journal_entries e
        JOIN etms.journal_lines l ON l.journal_entry_id = e.id
        WHERE e.journal_batch_id = NEW.id;
        SELECT count(*) INTO unposted_count
        FROM etms.journal_entries e
        WHERE e.journal_batch_id = NEW.id AND e.status <> 'POSTED';
        IF line_debit <= 0 OR line_debit IS DISTINCT FROM line_credit
           OR NEW.total_debit IS DISTINCT FROM line_debit
           OR NEW.total_credit IS DISTINCT FROM line_credit
           OR unposted_count > 0 THEN
            RAISE EXCEPTION 'Posted journal batch must reconcile and contain only posted entries'
                USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_validate_invoice_totals ON etms.invoices;
CREATE TRIGGER trg_validate_invoice_totals
BEFORE INSERT OR UPDATE OF status, net_amount, tax_amount, gross_amount
ON etms.invoices FOR EACH ROW EXECUTE PROCEDURE etms.validate_invoice_totals();

DROP TRIGGER IF EXISTS trg_validate_tax_invoice_totals ON etms.tax_invoices;
CREATE TRIGGER trg_validate_tax_invoice_totals
BEFORE INSERT OR UPDATE OF nts_status, supply_amount, tax_amount, total_amount
ON etms.tax_invoices FOR EACH ROW EXECUTE PROCEDURE etms.validate_tax_invoice_totals();

DROP TRIGGER IF EXISTS trg_validate_settlement_totals ON etms.settlements;
CREATE TRIGGER trg_validate_settlement_totals
BEFORE INSERT OR UPDATE OF status, gross_amount, deduction_amount, tax_amount, net_payable_amount
ON etms.settlements FOR EACH ROW EXECUTE PROCEDURE etms.validate_settlement_totals();

DROP TRIGGER IF EXISTS trg_validate_payment_application ON etms.payment_applications;
CREATE TRIGGER trg_validate_payment_application
BEFORE INSERT OR UPDATE OF payment_id, invoice_id, settlement_id, claim_settlement_id
ON etms.payment_applications FOR EACH ROW EXECUTE PROCEDURE etms.validate_payment_application();

DROP TRIGGER IF EXISTS trg_validate_payment_application_sum ON etms.payment_applications;
CREATE CONSTRAINT TRIGGER trg_validate_payment_application_sum
AFTER INSERT OR UPDATE OR DELETE ON etms.payment_applications
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE PROCEDURE etms.validate_payment_application_sum();

DROP TRIGGER IF EXISTS trg_validate_journal_line_balance ON etms.journal_lines;
CREATE CONSTRAINT TRIGGER trg_validate_journal_line_balance
AFTER INSERT OR UPDATE OR DELETE ON etms.journal_lines
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE PROCEDURE etms.validate_journal_line_balance();

DROP TRIGGER IF EXISTS trg_validate_journal_entry_status ON etms.journal_entries;
CREATE CONSTRAINT TRIGGER trg_validate_journal_entry_status
AFTER INSERT OR UPDATE OF status ON etms.journal_entries
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE PROCEDURE etms.validate_journal_entry_status();

DROP TRIGGER IF EXISTS trg_validate_journal_batch_posting ON etms.journal_batches;
CREATE TRIGGER trg_validate_journal_batch_posting
BEFORE INSERT OR UPDATE OF status, total_debit, total_credit
ON etms.journal_batches FOR EACH ROW EXECUTE PROCEDURE etms.validate_journal_batch_posting();

CREATE OR REPLACE FUNCTION etms.prevent_finalized_child_mutation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    parent_reference uuid;
    parent_references uuid[];
    parent_status text;
    editable_statuses text[];
BEGIN
    IF TG_OP = 'INSERT' THEN
        parent_references := ARRAY[NULLIF(to_jsonb(NEW) ->> TG_ARGV[0], '')::uuid];
    ELSIF TG_OP = 'DELETE' THEN
        parent_references := ARRAY[NULLIF(to_jsonb(OLD) ->> TG_ARGV[0], '')::uuid];
    ELSE
        parent_references := ARRAY[
            NULLIF(to_jsonb(OLD) ->> TG_ARGV[0], '')::uuid,
            NULLIF(to_jsonb(NEW) ->> TG_ARGV[0], '')::uuid
        ];
    END IF;
    editable_statuses := string_to_array(TG_ARGV[3], ',');

    FOREACH parent_reference IN ARRAY parent_references LOOP
        IF parent_reference IS NOT NULL THEN
            EXECUTE format(
                'SELECT %I::text FROM etms.%I WHERE id = $1', TG_ARGV[2], TG_ARGV[1]
            ) INTO parent_status USING parent_reference;
            IF parent_status IS NOT NULL AND NOT (parent_status = ANY (editable_statuses)) THEN
                RAISE EXCEPTION 'Finalized % child records are immutable; use a correction/reversal', TG_ARGV[1]
                    USING ERRCODE = '55000';
            END IF;
        END IF;
    END LOOP;
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION etms.protect_finalized_header()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    old_data jsonb := to_jsonb(OLD);
    new_data jsonb;
    old_status text;
    new_status text;
    editable_statuses text[] := string_to_array(TG_ARGV[1], ',');
    immutable_fields text[] := string_to_array(TG_ARGV[2], ',');
    field_name text;
BEGIN
    old_status := old_data ->> TG_ARGV[0];
    IF old_status = ANY (editable_statuses) THEN
        IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
        RETURN NEW;
    END IF;

    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'Finalized %.% rows cannot be deleted; use a reversal/correction',
            TG_TABLE_SCHEMA, TG_TABLE_NAME USING ERRCODE = '55000';
    END IF;

    new_data := to_jsonb(NEW);
    new_status := new_data ->> TG_ARGV[0];
    IF new_status = ANY (editable_statuses) THEN
        RAISE EXCEPTION 'Finalized %.% status cannot return to an editable state',
            TG_TABLE_SCHEMA, TG_TABLE_NAME USING ERRCODE = '55000';
    END IF;

    FOREACH field_name IN ARRAY immutable_fields LOOP
        IF (old_data -> field_name) IS DISTINCT FROM (new_data -> field_name) THEN
            RAISE EXCEPTION 'Finalized %.% field % is immutable',
                TG_TABLE_SCHEMA, TG_TABLE_NAME, field_name USING ERRCODE = '55000';
        END IF;
    END LOOP;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION etms.validate_finance_status_transition()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    old_status text;
    new_status text;
    old_rank integer;
    new_rank integer;
BEGIN
    IF TG_ARGV[0] = 'TAX_INVOICE' THEN
        old_status := OLD.nts_status;
        new_status := NEW.nts_status;
        old_rank := CASE old_status WHEN 'ISSUED' THEN 30 WHEN 'TRANSMITTED' THEN 40 WHEN 'ACCEPTED' THEN 50 WHEN 'CORRECTED' THEN 60 WHEN 'CANCELLED' THEN 99 ELSE 0 END;
        new_rank := CASE new_status WHEN 'ISSUED' THEN 30 WHEN 'TRANSMITTED' THEN 40 WHEN 'ACCEPTED' THEN 50 WHEN 'CORRECTED' THEN 60 WHEN 'CANCELLED' THEN 99 ELSE 0 END;
    ELSIF TG_ARGV[0] = 'INVOICE' THEN
        old_status := OLD.status; new_status := NEW.status;
        old_rank := CASE old_status WHEN 'APPROVED' THEN 30 WHEN 'POSTED' THEN 40 WHEN 'PARTIALLY_PAID' THEN 50 WHEN 'PAID' THEN 60 WHEN 'CANCELLED' THEN 99 ELSE 0 END;
        new_rank := CASE new_status WHEN 'APPROVED' THEN 30 WHEN 'POSTED' THEN 40 WHEN 'PARTIALLY_PAID' THEN 50 WHEN 'PAID' THEN 60 WHEN 'CANCELLED' THEN 99 ELSE 0 END;
    ELSIF TG_ARGV[0] = 'SETTLEMENT' THEN
        old_status := OLD.status; new_status := NEW.status;
        old_rank := CASE old_status WHEN 'APPROVED' THEN 30 WHEN 'INVOICED' THEN 40 WHEN 'PARTIALLY_PAID' THEN 50 WHEN 'PAID' THEN 60 WHEN 'CANCELLED' THEN 99 ELSE 0 END;
        new_rank := CASE new_status WHEN 'APPROVED' THEN 30 WHEN 'INVOICED' THEN 40 WHEN 'PARTIALLY_PAID' THEN 50 WHEN 'PAID' THEN 60 WHEN 'CANCELLED' THEN 99 ELSE 0 END;
    ELSE
        old_status := OLD.status; new_status := NEW.status;
        old_rank := CASE old_status WHEN 'POSTED' THEN 30 WHEN 'REVERSED' THEN 40 WHEN 'CANCELLED' THEN 99 ELSE 0 END;
        new_rank := CASE new_status WHEN 'POSTED' THEN 30 WHEN 'REVERSED' THEN 40 WHEN 'CANCELLED' THEN 99 ELSE 0 END;
    END IF;
    IF old_rank >= 30 AND new_rank < old_rank THEN
        RAISE EXCEPTION '% status cannot move backward from % to %', TG_ARGV[0], old_status, new_status
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION etms.prevent_finalized_invoice_line_child_mutation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    target_invoice_line_id uuid;
    target_invoice_line_ids uuid[];
    invoice_status text;
BEGIN
    IF TG_OP = 'INSERT' THEN
        target_invoice_line_ids := ARRAY[NEW.invoice_line_id];
    ELSIF TG_OP = 'DELETE' THEN
        target_invoice_line_ids := ARRAY[OLD.invoice_line_id];
    ELSE
        target_invoice_line_ids := ARRAY[OLD.invoice_line_id, NEW.invoice_line_id];
    END IF;
    FOREACH target_invoice_line_id IN ARRAY target_invoice_line_ids LOOP
        SELECT i.status INTO invoice_status
        FROM etms.invoice_lines l JOIN etms.invoices i ON i.id = l.invoice_id
        WHERE l.id = target_invoice_line_id;
        IF invoice_status IS NOT NULL AND invoice_status NOT IN ('DRAFT','RECEIVED','VALIDATING','REJECTED') THEN
            RAISE EXCEPTION 'Finalized invoice allocations are immutable; use a correction document'
                USING ERRCODE = '55000';
        END IF;
    END LOOP;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION etms.prevent_posted_journal_line_mutation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    target_entry_id uuid;
    target_entry_ids uuid[];
    entry_status text;
    batch_status text;
BEGIN
    IF TG_OP = 'INSERT' THEN target_entry_ids := ARRAY[NEW.journal_entry_id];
    ELSIF TG_OP = 'DELETE' THEN target_entry_ids := ARRAY[OLD.journal_entry_id];
    ELSE target_entry_ids := ARRAY[OLD.journal_entry_id, NEW.journal_entry_id];
    END IF;
    FOREACH target_entry_id IN ARRAY target_entry_ids LOOP
        SELECT e.status, b.status INTO entry_status, batch_status
        FROM etms.journal_entries e JOIN etms.journal_batches b ON b.id = e.journal_batch_id
        WHERE e.id = target_entry_id;
        IF entry_status = 'POSTED' OR batch_status = 'POSTED' THEN
            RAISE EXCEPTION 'Posted journal lines are immutable; create a reversal batch'
                USING ERRCODE = '55000';
        END IF;
    END LOOP;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION etms.prevent_posted_journal_entry_mutation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    target_batch_id uuid;
    target_batch_ids uuid[];
    batch_status text;
BEGIN
    IF TG_OP IN ('UPDATE','DELETE') AND OLD.status = 'POSTED' THEN
        RAISE EXCEPTION 'Posted journal entries are immutable; create a reversal entry'
            USING ERRCODE = '55000';
    END IF;
    IF TG_OP = 'INSERT' THEN target_batch_ids := ARRAY[NEW.journal_batch_id];
    ELSIF TG_OP = 'DELETE' THEN target_batch_ids := ARRAY[OLD.journal_batch_id];
    ELSE target_batch_ids := ARRAY[OLD.journal_batch_id, NEW.journal_batch_id];
    END IF;
    FOREACH target_batch_id IN ARRAY target_batch_ids LOOP
        SELECT status INTO batch_status FROM etms.journal_batches WHERE id = target_batch_id;
        IF batch_status = 'POSTED' THEN
            RAISE EXCEPTION 'Entries in a posted journal batch are immutable; create a reversal batch'
                USING ERRCODE = '55000';
        END IF;
    END LOOP;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION etms.validate_payment_target_limit()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    target_type text;
    target_id uuid;
    target_amount numeric(20,4);
    applied_total numeric(20,4);
BEGIN
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    IF NEW.invoice_id IS NOT NULL THEN
        target_type := 'INVOICE'; target_id := NEW.invoice_id;
        SELECT gross_amount INTO target_amount FROM etms.invoices WHERE id = target_id;
        SELECT COALESCE(sum(applied_amount + discount_taken + writeoff_amount), 0)
          INTO applied_total FROM etms.payment_applications WHERE invoice_id = target_id;
    ELSIF NEW.settlement_id IS NOT NULL THEN
        target_type := 'SETTLEMENT'; target_id := NEW.settlement_id;
        SELECT net_payable_amount INTO target_amount FROM etms.settlements WHERE id = target_id;
        SELECT COALESCE(sum(applied_amount + discount_taken + writeoff_amount), 0)
          INTO applied_total FROM etms.payment_applications WHERE settlement_id = target_id;
    ELSE
        target_type := 'CLAIM_SETTLEMENT'; target_id := NEW.claim_settlement_id;
        SELECT settlement_amount INTO target_amount FROM etms.claim_settlements WHERE id = target_id;
        SELECT COALESCE(sum(applied_amount + discount_taken + writeoff_amount), 0)
          INTO applied_total FROM etms.payment_applications WHERE claim_settlement_id = target_id;
    END IF;
    IF applied_total > target_amount THEN
        RAISE EXCEPTION '% payment applications exceed target amount', target_type
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION etms.validate_payment_header_after_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    applied_total numeric(20,4);
    mismatched_currency_count integer;
BEGIN
    SELECT COALESCE(sum(applied_amount), 0) INTO applied_total
    FROM etms.payment_applications WHERE payment_id = NEW.id;
    IF applied_total > NEW.payment_amount THEN
        RAISE EXCEPTION 'Payment amount cannot be lower than existing applications'
            USING ERRCODE = '23514';
    END IF;
    SELECT count(*) INTO mismatched_currency_count
    FROM etms.payment_applications a
    LEFT JOIN etms.invoices i ON i.id = a.invoice_id
    LEFT JOIN etms.settlements s ON s.id = a.settlement_id
    LEFT JOIN etms.claim_settlements c ON c.id = a.claim_settlement_id
    WHERE a.payment_id = NEW.id
      AND COALESCE(i.currency_code, s.currency_code, c.currency_code) IS DISTINCT FROM NEW.currency_code;
    IF mismatched_currency_count > 0 THEN
        RAISE EXCEPTION 'Payment currency cannot differ from existing application targets'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_lock_final_invoice_lines ON etms.invoice_lines;
CREATE TRIGGER trg_lock_final_invoice_lines
BEFORE INSERT OR UPDATE OR DELETE ON etms.invoice_lines
FOR EACH ROW EXECUTE PROCEDURE etms.prevent_finalized_child_mutation(
    'invoice_id','invoices','status','DRAFT,RECEIVED,VALIDATING,REJECTED'
);

DROP TRIGGER IF EXISTS trg_lock_final_invoice_taxes ON etms.invoice_taxes;
CREATE TRIGGER trg_lock_final_invoice_taxes
BEFORE INSERT OR UPDATE OR DELETE ON etms.invoice_taxes
FOR EACH ROW EXECUTE PROCEDURE etms.prevent_finalized_child_mutation(
    'invoice_id','invoices','status','DRAFT,RECEIVED,VALIDATING,REJECTED'
);

DROP TRIGGER IF EXISTS trg_lock_final_invoice_allocations ON etms.invoice_line_charges;
CREATE TRIGGER trg_lock_final_invoice_allocations
BEFORE INSERT OR UPDATE OR DELETE ON etms.invoice_line_charges
FOR EACH ROW EXECUTE PROCEDURE etms.prevent_finalized_invoice_line_child_mutation();

DROP TRIGGER IF EXISTS trg_lock_final_tax_invoice_lines ON etms.tax_invoice_lines;
CREATE TRIGGER trg_lock_final_tax_invoice_lines
BEFORE INSERT OR UPDATE OR DELETE ON etms.tax_invoice_lines
FOR EACH ROW EXECUTE PROCEDURE etms.prevent_finalized_child_mutation(
    'tax_invoice_id','tax_invoices','nts_status','DRAFT,VALIDATING,REJECTED'
);

DROP TRIGGER IF EXISTS trg_lock_final_settlement_lines ON etms.settlement_lines;
CREATE TRIGGER trg_lock_final_settlement_lines
BEFORE INSERT OR UPDATE OR DELETE ON etms.settlement_lines
FOR EACH ROW EXECUTE PROCEDURE etms.prevent_finalized_child_mutation(
    'settlement_id','settlements','status','DRAFT,OPEN,CALCULATING,REJECTED'
);

DROP TRIGGER IF EXISTS trg_protect_final_invoice_header ON etms.invoices;
CREATE TRIGGER trg_protect_final_invoice_header
BEFORE UPDATE OR DELETE ON etms.invoices
FOR EACH ROW EXECUTE PROCEDURE etms.protect_finalized_header(
    'status','DRAFT,RECEIVED,VALIDATING,REJECTED',
    'id,tenant_id,invoice_type,invoice_no,organization_id,issuer_partner_id,recipient_partner_id,issuer_party_snapshot_id,recipient_party_snapshot_id,billing_address_snapshot_id,invoice_date,service_period_from,service_period_to,currency_code,exchange_rate,exchange_rate_date,base_currency_code,net_amount,tax_amount,gross_amount,original_invoice_id'
);

DROP TRIGGER IF EXISTS trg_protect_final_tax_invoice_header ON etms.tax_invoices;
CREATE TRIGGER trg_protect_final_tax_invoice_header
BEFORE UPDATE OR DELETE ON etms.tax_invoices
FOR EACH ROW EXECUTE PROCEDURE etms.protect_finalized_header(
    'nts_status','DRAFT,VALIDATING,REJECTED',
    'id,tenant_id,tax_invoice_no,tax_invoice_type,direction,organization_id,supplier_partner_id,buyer_partner_id,supplier_snapshot_id,buyer_snapshot_id,issue_date,supply_date,currency_code,supply_amount,tax_amount,total_amount,original_tax_invoice_id'
);

DROP TRIGGER IF EXISTS trg_protect_final_settlement_header ON etms.settlements;
CREATE TRIGGER trg_protect_final_settlement_header
BEFORE UPDATE OR DELETE ON etms.settlements
FOR EACH ROW EXECUTE PROCEDURE etms.protect_finalized_header(
    'status','DRAFT,OPEN,CALCULATING,REJECTED',
    'id,tenant_id,settlement_no,settlement_type,partner_id,organization_id,period_from,period_to,currency_code,gross_amount,deduction_amount,tax_amount,net_payable_amount'
);

DROP TRIGGER IF EXISTS trg_protect_posted_journal_batch ON etms.journal_batches;
CREATE TRIGGER trg_protect_posted_journal_batch
BEFORE UPDATE OR DELETE ON etms.journal_batches
FOR EACH ROW EXECUTE PROCEDURE etms.protect_finalized_header(
    'status','DRAFT,APPROVED',
    'id,tenant_id,batch_no,organization_id,accounting_period_id,source_code,batch_type,accounting_date,total_debit,total_credit,reversal_of_batch_id'
);

DROP TRIGGER IF EXISTS trg_invoice_status_forward ON etms.invoices;
CREATE TRIGGER trg_invoice_status_forward BEFORE UPDATE OF status ON etms.invoices
FOR EACH ROW EXECUTE PROCEDURE etms.validate_finance_status_transition('INVOICE');

DROP TRIGGER IF EXISTS trg_tax_invoice_status_forward ON etms.tax_invoices;
CREATE TRIGGER trg_tax_invoice_status_forward BEFORE UPDATE OF nts_status ON etms.tax_invoices
FOR EACH ROW EXECUTE PROCEDURE etms.validate_finance_status_transition('TAX_INVOICE');

DROP TRIGGER IF EXISTS trg_settlement_status_forward ON etms.settlements;
CREATE TRIGGER trg_settlement_status_forward BEFORE UPDATE OF status ON etms.settlements
FOR EACH ROW EXECUTE PROCEDURE etms.validate_finance_status_transition('SETTLEMENT');

DROP TRIGGER IF EXISTS trg_journal_batch_status_forward ON etms.journal_batches;
CREATE TRIGGER trg_journal_batch_status_forward BEFORE UPDATE OF status ON etms.journal_batches
FOR EACH ROW EXECUTE PROCEDURE etms.validate_finance_status_transition('JOURNAL_BATCH');

DROP TRIGGER IF EXISTS trg_lock_posted_journal_lines ON etms.journal_lines;
CREATE TRIGGER trg_lock_posted_journal_lines
BEFORE INSERT OR UPDATE OR DELETE ON etms.journal_lines
FOR EACH ROW EXECUTE PROCEDURE etms.prevent_posted_journal_line_mutation();

DROP TRIGGER IF EXISTS trg_lock_posted_journal_entries ON etms.journal_entries;
CREATE TRIGGER trg_lock_posted_journal_entries
BEFORE INSERT OR UPDATE OR DELETE ON etms.journal_entries
FOR EACH ROW EXECUTE PROCEDURE etms.prevent_posted_journal_entry_mutation();

DROP TRIGGER IF EXISTS trg_validate_payment_target_limit ON etms.payment_applications;
CREATE CONSTRAINT TRIGGER trg_validate_payment_target_limit
AFTER INSERT OR UPDATE ON etms.payment_applications
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE PROCEDURE etms.validate_payment_target_limit();

DROP TRIGGER IF EXISTS trg_validate_payment_header_update ON etms.payments;
CREATE TRIGGER trg_validate_payment_header_update
BEFORE UPDATE OF payment_amount, currency_code ON etms.payments
FOR EACH ROW EXECUTE PROCEDURE etms.validate_payment_header_after_update();

CREATE OR REPLACE FUNCTION etms.prevent_ledger_update()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    RAISE EXCEPTION '%.% is append-only; record a correction/reversal event instead',
        TG_TABLE_SCHEMA, TG_TABLE_NAME USING ERRCODE = '55000';
END;
$function$;

DO $block$
DECLARE
    table_name text;
BEGIN
    FOREACH table_name IN ARRAY ARRAY[
        'audit_events','container_events','data_access_logs','dispatch_status_history',
        'entity_change_logs','geofence_events','gps_positions','invoice_status_history',
        'login_events','milestone_events','order_status_history','run_status_history',
        'scan_events','sensor_readings','shipment_status_history','stop_status_history',
        'tax_invoice_events','transport_events','yard_events'
    ]::text[]
    LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS trg_append_only ON etms.%I', table_name);
        EXECUTE format(
            'CREATE TRIGGER trg_append_only BEFORE UPDATE ON etms.%I '
            'FOR EACH ROW EXECUTE PROCEDURE etms.prevent_ledger_update()', table_name
        );
    END LOOP;
END;
$block$;

-- Standard optimistic-lock timestamp/version triggers.
DO $block$
DECLARE
    r record;
BEGIN
    FOR r IN
        SELECT c.table_schema, c.table_name
        FROM information_schema.columns c
        JOIN information_schema.columns u
          ON u.table_schema = c.table_schema
         AND u.table_name = c.table_name
         AND u.column_name = 'updated_at'
        JOIN information_schema.columns v
          ON v.table_schema = c.table_schema
         AND v.table_name = c.table_name
         AND v.column_name = 'row_version'
        WHERE c.table_schema = 'etms'
          AND c.column_name = 'updated_at'
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_trigger t
            WHERE t.tgrelid = format('%I.%I', r.table_schema, r.table_name)::regclass
              AND t.tgname = 'trg_touch_row'
              AND NOT t.tgisinternal
        ) THEN
            EXECUTE format(
                'CREATE TRIGGER trg_touch_row BEFORE UPDATE ON %I.%I '
                'FOR EACH ROW EXECUTE PROCEDURE etms.touch_row()',
                r.table_schema, r.table_name
            );
        END IF;
    END LOOP;
END;
$block$;

-- Tenant immutability triggers.
DO $block$
DECLARE
    r record;
BEGIN
    FOR r IN
        SELECT DISTINCT table_schema, table_name
        FROM information_schema.columns
        WHERE table_schema = 'etms' AND column_name = 'tenant_id'
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_trigger t
            WHERE t.tgrelid = format('%I.%I', r.table_schema, r.table_name)::regclass
              AND t.tgname = 'trg_prevent_tenant_change'
              AND NOT t.tgisinternal
        ) THEN
            EXECUTE format(
                'CREATE TRIGGER trg_prevent_tenant_change BEFORE UPDATE OF tenant_id ON %I.%I '
                'FOR EACH ROW EXECUTE PROCEDURE etms.prevent_tenant_change()',
                r.table_schema, r.table_name
            );
        END IF;
    END LOOP;
END;
$block$;

-- Same-tenant relationship triggers. Global parent rows with tenant_id NULL remain shareable.
DO $block$
DECLARE
    r record;
    child_column text;
    trigger_name text;
BEGIN
    FOR r IN
        SELECT con.oid, con.conname, con.conrelid, con.confrelid,
               child_ns.nspname AS child_schema, child.relname AS child_table,
               parent_ns.nspname AS parent_schema, parent.relname AS parent_table,
               con.conkey[1] AS child_attnum
        FROM pg_constraint con
        JOIN pg_class child ON child.oid = con.conrelid
        JOIN pg_namespace child_ns ON child_ns.oid = child.relnamespace
        JOIN pg_class parent ON parent.oid = con.confrelid
        JOIN pg_namespace parent_ns ON parent_ns.oid = parent.relnamespace
        WHERE con.contype = 'f'
          AND child_ns.nspname = 'etms'
          AND parent_ns.nspname = 'etms'
          AND array_length(con.conkey, 1) = 1
          AND EXISTS (
              SELECT 1 FROM pg_attribute a
              WHERE a.attrelid = con.conrelid AND a.attname = 'tenant_id' AND NOT a.attisdropped
          )
          AND EXISTS (
              SELECT 1 FROM pg_attribute a
              WHERE a.attrelid = con.confrelid AND a.attname = 'tenant_id' AND NOT a.attisdropped
          )
          AND EXISTS (
              SELECT 1 FROM pg_attribute a
              WHERE a.attrelid = con.confrelid AND a.attnum = con.confkey[1] AND a.attname = 'id'
          )
    LOOP
        SELECT attname INTO child_column
        FROM pg_attribute
        WHERE attrelid = r.conrelid AND attnum = r.child_attnum;

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
              AND companion.conrelid = r.conrelid
              AND companion.confrelid = r.confrelid
              AND array_length(companion.conkey, 1) = 2
              AND companion.conkey[1] = tenant_column.attnum
              AND companion.conkey[2] = r.child_attnum
        ) THEN
            CONTINUE;
        END IF;

        trigger_name := 'trg_tenant_fk_' || substr(
            md5(r.child_schema || '.' || r.child_table || '.' || r.conname), 1, 12
        );
        IF NOT EXISTS (
            SELECT 1 FROM pg_trigger t
            WHERE t.tgrelid = r.conrelid AND t.tgname = trigger_name AND NOT t.tgisinternal
        ) THEN
            EXECUTE format(
                'CREATE TRIGGER %I BEFORE INSERT OR UPDATE OF %I ON %I.%I '
                'FOR EACH ROW EXECUTE PROCEDURE etms.enforce_same_tenant_fk(%L,%L,%L)',
                trigger_name, child_column, r.child_schema, r.child_table,
                child_column, r.parent_schema, r.parent_table
            );
        END IF;
    END LOOP;
END;
$block$;

-- RLS is enabled for future least-privilege application roles. The schema owner bypasses
-- RLS on PostgreSQL 11, so production applications should connect through a non-owner role
-- and set `SET LOCAL etms.tenant_id = '<tenant uuid>'` for every transaction.
CREATE OR REPLACE FUNCTION etms.current_tenant_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $function$
    SELECT NULLIF(current_setting('etms.tenant_id', true), '')::uuid;
$function$;

DO $block$
DECLARE
    r record;
    global_reference_tables constant text[] := ARRAY[
        'charge_codes','code_sets','code_values','commodity_classes','data_quality_rules',
        'emission_factors','equipment_types','exchange_rates','fuel_index_values','fuel_indices',
        'kpi_definitions','notification_templates','payment_terms','role_permissions','roles',
        'service_levels','status_definitions','status_transitions','tax_codes','tax_rates','vehicle_types'
    ]::text[];
    select_expression text;
BEGIN
    FOR r IN
        SELECT DISTINCT table_schema, table_name
        FROM information_schema.columns
        WHERE table_schema = 'etms' AND column_name = 'tenant_id'
    LOOP
        EXECUTE format('ALTER TABLE %I.%I ENABLE ROW LEVEL SECURITY', r.table_schema, r.table_name);
        EXECUTE format('DROP POLICY IF EXISTS tenant_isolation ON %I.%I', r.table_schema, r.table_name);
        EXECUTE format('DROP POLICY IF EXISTS tenant_select ON %I.%I', r.table_schema, r.table_name);
        EXECUTE format('DROP POLICY IF EXISTS tenant_modify ON %I.%I', r.table_schema, r.table_name);

        IF r.table_name = ANY (global_reference_tables) THEN
            select_expression := 'tenant_id IS NULL OR tenant_id = etms.current_tenant_id()';
        ELSE
            select_expression := 'tenant_id = etms.current_tenant_id()';
        END IF;

        EXECUTE format(
            'CREATE POLICY tenant_select ON %I.%I FOR SELECT USING (%s)',
            r.table_schema, r.table_name, select_expression
        );
        EXECUTE format(
            'CREATE POLICY tenant_modify ON %I.%I FOR ALL '
            'USING (tenant_id = etms.current_tenant_id()) '
            'WITH CHECK (tenant_id = etms.current_tenant_id())',
            r.table_schema, r.table_name
        );
    END LOOP;
END;
$block$;

-- PostgreSQL does not index referencing FK columns automatically; generate deterministic indexes.
DO $block$
DECLARE
    r record;
    column_list text;
    index_name text;
BEGIN
    FOR r IN
        SELECT con.oid, con.conname, con.conrelid,
               ns.nspname AS schema_name, cls.relname AS table_name, con.conkey
        FROM pg_constraint con
        JOIN pg_class cls ON cls.oid = con.conrelid
        JOIN pg_namespace ns ON ns.oid = cls.relnamespace
        WHERE con.contype = 'f' AND ns.nspname = 'etms'
    LOOP
        SELECT string_agg(quote_ident(a.attname), ', ' ORDER BY k.ordinality)
          INTO column_list
        FROM unnest(r.conkey) WITH ORDINALITY AS k(attnum, ordinality)
        JOIN pg_attribute a ON a.attrelid = r.conrelid AND a.attnum = k.attnum;

        IF EXISTS (
            SELECT 1
            FROM pg_index i
            WHERE i.indrelid = r.conrelid
              AND i.indisvalid
              AND i.indisready
              AND i.indpred IS NULL
              AND i.indnkeyatts >= array_length(r.conkey, 1)
              AND ARRAY(
                  SELECT key_col.attnum
                  FROM unnest(i.indkey) WITH ORDINALITY AS key_col(attnum, ordinality)
                  WHERE key_col.ordinality <= array_length(r.conkey, 1)
                  ORDER BY key_col.ordinality
              )::smallint[] = r.conkey
        ) THEN
            CONTINUE;
        END IF;

        index_name := 'ix_fk_' || substr(r.table_name, 1, 30) || '_' ||
            substr(md5(r.schema_name || '.' || r.table_name || '.' || r.conname), 1, 10);
        EXECUTE format(
            'CREATE INDEX IF NOT EXISTS %I ON %I.%I (%s)',
            index_name, r.schema_name, r.table_name, column_list
        );
    END LOOP;
END;
$block$;

-- High-value operational query indexes.
CREATE INDEX IF NOT EXISTS ix_orders_tenant_status_pickup
    ON etms.transport_orders (tenant_id, status, requested_pickup_from);
CREATE INDEX IF NOT EXISTS ix_orders_tenant_customer_created
    ON etms.transport_orders (tenant_id, customer_id, created_at DESC);
CREATE INDEX IF NOT EXISTS ix_orders_external_reference
    ON etms.transport_orders (tenant_id, customer_reference)
    WHERE customer_reference IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_order_status_history_order_time
    ON etms.order_status_history (order_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS ix_shipments_tenant_status_pickup
    ON etms.shipments (tenant_id, status, planned_pickup_at);
CREATE INDEX IF NOT EXISTS ix_shipments_tenant_customer_created
    ON etms.shipments (tenant_id, customer_id, created_at DESC);
CREATE INDEX IF NOT EXISTS ix_shipment_status_history_time
    ON etms.shipment_status_history (shipment_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS ix_runs_tenant_service_status
    ON etms.transport_runs (tenant_id, service_date, status);
CREATE INDEX IF NOT EXISTS ix_runs_tenant_assignment
    ON etms.transport_runs (tenant_id, assignment_status, planned_start_at);
CREATE INDEX IF NOT EXISTS ix_run_status_history_time
    ON etms.run_status_history (run_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS ix_transport_events_entity_time
    ON etms.transport_events (tenant_id, shipment_id, run_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS ix_transport_events_received
    ON etms.transport_events (tenant_id, received_at DESC);
CREATE INDEX IF NOT EXISTS ix_transport_events_occurred_brin
    ON etms.transport_events USING brin (occurred_at);
CREATE INDEX IF NOT EXISTS ix_transport_events_payload_gin
    ON etms.transport_events USING gin (payload jsonb_path_ops);
CREATE INDEX IF NOT EXISTS ix_gps_positions_vehicle_time
    ON etms.gps_positions (tenant_id, vehicle_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS ix_gps_positions_run_time
    ON etms.gps_positions (tenant_id, run_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS ix_gps_positions_occurred_brin
    ON etms.gps_positions USING brin (occurred_at);
CREATE INDEX IF NOT EXISTS ix_sensor_readings_sensor_time
    ON etms.sensor_readings (sensor_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS ix_sensor_readings_occurred_brin
    ON etms.sensor_readings USING brin (occurred_at);
CREATE INDEX IF NOT EXISTS ix_exceptions_open
    ON etms.execution_exceptions (tenant_id, severity, due_at)
    WHERE status NOT IN ('RESOLVED','CLOSED','CANCELLED');
CREATE INDEX IF NOT EXISTS ix_charges_entity_stage
    ON etms.charges (tenant_id, shipment_id, run_id, direction, stage);
CREATE INDEX IF NOT EXISTS ix_charges_parties_service_date
    ON etms.charges (tenant_id, payer_partner_id, payee_partner_id, service_date);
CREATE INDEX IF NOT EXISTS ix_invoices_partner_status_due
    ON etms.invoices (tenant_id, recipient_partner_id, status, due_date);
CREATE INDEX IF NOT EXISTS ix_claims_tenant_status_date
    ON etms.claims (tenant_id, status, claim_date DESC);
CREATE INDEX IF NOT EXISTS ix_login_events_user_time
    ON etms.login_events (user_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS ix_login_events_occurred_brin
    ON etms.login_events USING brin (occurred_at);
CREATE INDEX IF NOT EXISTS ix_audit_events_entity_time
    ON etms.audit_events (tenant_id, entity_type, entity_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS ix_audit_events_occurred_brin
    ON etms.audit_events USING brin (occurred_at);
CREATE INDEX IF NOT EXISTS ix_outbox_unpublished
    ON etms.outbox_events (available_at, occurred_at)
    WHERE published_at IS NULL;
CREATE INDEX IF NOT EXISTS ix_integration_messages_pending
    ON etms.integration_messages (tenant_id, status, received_at)
    WHERE processed_at IS NULL;
CREATE INDEX IF NOT EXISTS ix_entity_files_lookup
    ON etms.entity_files (tenant_id, entity_type, entity_id, document_type);
CREATE INDEX IF NOT EXISTS ix_custom_fields_entity
    ON etms.custom_field_values (tenant_id, entity_id);

-- Global ISO/reference seeds intentionally contain only defaults needed to bootstrap ETMS.
INSERT INTO etms.currencies (currency_code, currency_name, numeric_code, fraction_digits, rounding_increment)
VALUES
    ('KRW','South Korean Won','410',0,1),
    ('USD','US Dollar','840',2,0.01),
    ('EUR','Euro','978',2,0.01),
    ('JPY','Japanese Yen','392',0,1),
    ('CNY','Chinese Yuan','156',2,0.01),
    ('GBP','Pound Sterling','826',2,0.01),
    ('SGD','Singapore Dollar','702',2,0.01),
    ('VND','Vietnamese Dong','704',0,1),
    ('INR','Indian Rupee','356',2,0.01),
    ('AUD','Australian Dollar','036',2,0.01),
    ('CAD','Canadian Dollar','124',2,0.01),
    ('AED','UAE Dirham','784',2,0.01)
ON CONFLICT (currency_code) DO UPDATE SET
    currency_name = EXCLUDED.currency_name,
    numeric_code = EXCLUDED.numeric_code,
    fraction_digits = EXCLUDED.fraction_digits,
    rounding_increment = EXCLUDED.rounding_increment;

INSERT INTO etms.countries (country_code, country_code3, numeric_code, country_name_en, country_name_local, default_currency_code)
VALUES
    ('KR','KOR','410','Korea, Republic of','대한민국','KRW'),
    ('US','USA','840','United States','United States','USD'),
    ('CN','CHN','156','China','中国','CNY'),
    ('JP','JPN','392','Japan','日本','JPY'),
    ('DE','DEU','276','Germany','Deutschland','EUR'),
    ('FR','FRA','250','France','France','EUR'),
    ('GB','GBR','826','United Kingdom','United Kingdom','GBP'),
    ('NL','NLD','528','Netherlands','Nederland','EUR'),
    ('BE','BEL','056','Belgium','België','EUR'),
    ('SG','SGP','702','Singapore','Singapore','SGD'),
    ('VN','VNM','704','Viet Nam','Việt Nam','VND'),
    ('IN','IND','356','India','India','INR'),
    ('AU','AUS','036','Australia','Australia','AUD'),
    ('CA','CAN','124','Canada','Canada','CAD'),
    ('AE','ARE','784','United Arab Emirates','الإمارات العربية المتحدة','AED')
ON CONFLICT (country_code) DO UPDATE SET
    country_code3 = EXCLUDED.country_code3,
    numeric_code = EXCLUDED.numeric_code,
    country_name_en = EXCLUDED.country_name_en,
    country_name_local = EXCLUDED.country_name_local,
    default_currency_code = EXCLUDED.default_currency_code;

INSERT INTO etms.units_of_measure (uom_code, uom_name, dimension, si_factor, decimal_places)
VALUES
    ('EA','Each','COUNT',1,0), ('PAL','Pallet','COUNT',1,3), ('BOX','Box','COUNT',1,0),
    ('CTN','Carton','COUNT',1,0), ('PKG','Package','COUNT',1,0), ('TEU','Twenty-foot equivalent unit','COUNT',1,3),
    ('KG','Kilogram','MASS',1,6), ('G','Gram','MASS',0.001,3), ('T','Metric tonne','MASS',1000,6), ('LB','Pound','MASS',0.45359237,6),
    ('M3','Cubic metre','VOLUME',1,6), ('L','Litre','VOLUME',0.001,6), ('FT3','Cubic foot','VOLUME',0.028316846592,6),
    ('M','Metre','LENGTH',1,6), ('CM','Centimetre','LENGTH',0.01,3), ('MM','Millimetre','LENGTH',0.001,3),
    ('KM','Kilometre','DISTANCE',1000,3), ('MI','Mile','DISTANCE',1609.344,3),
    ('MIN','Minute','TIME',60,0), ('H','Hour','TIME',3600,3), ('DAY','Day','TIME',86400,3),
    ('CEL','Degree Celsius','TEMPERATURE',1,3),
    ('KWH','Kilowatt hour','ENERGY',3600000,6), ('MJ','Megajoule','ENERGY',1000000,6)
ON CONFLICT (uom_code) DO UPDATE SET
    uom_name = EXCLUDED.uom_name,
    dimension = EXCLUDED.dimension,
    si_factor = EXCLUDED.si_factor,
    decimal_places = EXCLUDED.decimal_places;

INSERT INTO etms.transport_modes (mode_code, mode_name, mode_group, is_scheduled)
VALUES
    ('ROAD','Road','LAND',false),
    ('RAIL','Rail','LAND',true),
    ('AIR','Air','AIR',true),
    ('OCEAN','Ocean','SEA',true),
    ('INLAND_WATER','Inland Waterway','SEA',true),
    ('COURIER','Courier/Parcel','PARCEL',false),
    ('INTERMODAL','Intermodal','MULTIMODAL',true),
    ('OTHER','Other','OTHER',false)
ON CONFLICT (mode_code) DO UPDATE SET
    mode_name = EXCLUDED.mode_name,
    mode_group = EXCLUDED.mode_group,
    is_scheduled = EXCLUDED.is_scheduled;

INSERT INTO etms.permissions (permission_code, permission_name, module_code, action_code, is_sensitive)
VALUES
    ('iam.user.read','사용자 조회','IAM','READ',true),
    ('iam.user.manage','사용자 관리','IAM','MANAGE',true),
    ('iam.role.manage','역할 및 권한 관리','IAM','MANAGE',true),
    ('master.read','마스터 조회','MASTER','READ',false),
    ('master.manage','마스터 관리','MASTER','MANAGE',false),
    ('order.read','운송주문 조회','ORDER','READ',false),
    ('order.create','운송주문 등록','ORDER','CREATE',false),
    ('order.update','운송주문 변경','ORDER','UPDATE',false),
    ('order.cancel','운송주문 취소','ORDER','CANCEL',true),
    ('planning.read','운송계획 조회','PLANNING','READ',false),
    ('planning.manage','편성 및 최적화','PLANNING','MANAGE',false),
    ('tender.manage','운송사 입찰 관리','TENDER','MANAGE',false),
    ('dispatch.read','배차 조회','DISPATCH','READ',false),
    ('dispatch.manage','배정 및 배차 관리','DISPATCH','MANAGE',false),
    ('execution.read','운송실행 조회','EXECUTION','READ',false),
    ('execution.manage','운송실행 관리','EXECUTION','MANAGE',false),
    ('tracking.read','관제 조회','TRACKING','READ',false),
    ('pod.manage','POD 관리','POD','MANAGE',true),
    ('exception.manage','예외 관리','EXCEPTION','MANAGE',false),
    ('claim.read','클레임 조회','CLAIM','READ',true),
    ('claim.manage','클레임 관리','CLAIM','MANAGE',true),
    ('rate.read','요율 조회','RATE','READ',true),
    ('rate.manage','계약 및 요율 관리','RATE','MANAGE',true),
    ('finance.read','정산 조회','FINANCE','READ',true),
    ('finance.manage','정산 관리','FINANCE','MANAGE',true),
    ('finance.approve','정산 승인','FINANCE','APPROVE',true),
    ('invoice.manage','청구서 관리','INVOICE','MANAGE',true),
    ('tax_invoice.manage','세금계산서 관리','TAX_INVOICE','MANAGE',true),
    ('accounting.export','회계 전송','ACCOUNTING','EXPORT',true),
    ('analytics.read','분석 조회','ANALYTICS','READ',false),
    ('integration.manage','연계 관리','INTEGRATION','MANAGE',true),
    ('audit.read','감사 로그 조회','AUDIT','READ',true),
    ('pii.read','개인정보 조회','SECURITY','READ',true),
    ('admin.all','전체 관리자 권한','ADMIN','ALL',true)
ON CONFLICT (permission_code) DO UPDATE SET
    permission_name = EXCLUDED.permission_name,
    module_code = EXCLUDED.module_code,
    action_code = EXCLUDED.action_code,
    is_sensitive = EXCLUDED.is_sensitive;

INSERT INTO etms.roles (tenant_id, role_code, role_name, description, is_system_role)
SELECT NULL, v.role_code, v.role_name, v.description, true
FROM (VALUES
    ('TMS_ADMIN','TMS 관리자','전체 시스템 및 보안 관리'),
    ('MASTER_ADMIN','마스터 관리자','조직, 파트너, 거점, 자원 마스터 관리'),
    ('ORDER_OPERATOR','운송주문 담당자','운송주문 등록 및 변경'),
    ('TRANSPORT_PLANNER','운송계획 담당자','편성, 최적화, 입찰 관리'),
    ('DISPATCHER','배차 담당자','운송사, 기사, 차량 배정 및 배차'),
    ('CONTROL_TOWER','관제 담당자','운송실행, 관제, 예외 처리'),
    ('DRIVER','기사','배차 수락, 실행 태스크, POD 처리'),
    ('CARRIER_USER','운송사 사용자','입찰, 배차, 실행 정보 처리'),
    ('CUSTOMER_USER','고객 사용자','주문 및 배송 추적 조회'),
    ('RATE_MANAGER','요율 관리자','계약, 요율, 견적 관리'),
    ('SETTLEMENT_ANALYST','정산 담당자','운임 검증, 청구, 정산 처리'),
    ('FINANCE_APPROVER','재무 승인자','정산 및 회계 승인'),
    ('CLAIM_MANAGER','클레임 담당자','사고, 손상, 클레임 처리'),
    ('ANALYST','분석 사용자','운송 KPI 및 분석 조회'),
    ('AUDITOR','감사자','감사, 개인정보 접근, 재무 이력 조회')
) AS v(role_code, role_name, description)
WHERE NOT EXISTS (
    SELECT 1 FROM etms.roles r WHERE r.tenant_id IS NULL AND r.role_code = v.role_code
);

-- System administrator gets all permissions. Other role grants are deliberately least-privilege.
INSERT INTO etms.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM etms.roles r CROSS JOIN etms.permissions p
WHERE r.tenant_id IS NULL AND r.role_code = 'TMS_ADMIN'
ON CONFLICT DO NOTHING;

INSERT INTO etms.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM etms.roles r
JOIN etms.permissions p ON p.permission_code = ANY (
    CASE r.role_code
        WHEN 'MASTER_ADMIN' THEN ARRAY['master.read','master.manage']::text[]
        WHEN 'ORDER_OPERATOR' THEN ARRAY['master.read','order.read','order.create','order.update']::text[]
        WHEN 'TRANSPORT_PLANNER' THEN ARRAY['master.read','order.read','planning.read','planning.manage','tender.manage','rate.read']::text[]
        WHEN 'DISPATCHER' THEN ARRAY['master.read','order.read','planning.read','dispatch.read','dispatch.manage','tracking.read']::text[]
        WHEN 'CONTROL_TOWER' THEN ARRAY['order.read','dispatch.read','execution.read','execution.manage','tracking.read','pod.manage','exception.manage']::text[]
        WHEN 'DRIVER' THEN ARRAY['dispatch.read','execution.read','execution.manage','pod.manage']::text[]
        WHEN 'CARRIER_USER' THEN ARRAY['order.read','dispatch.read','execution.read','tracking.read','pod.manage']::text[]
        WHEN 'CUSTOMER_USER' THEN ARRAY['order.read','tracking.read']::text[]
        WHEN 'RATE_MANAGER' THEN ARRAY['master.read','rate.read','rate.manage','analytics.read']::text[]
        WHEN 'SETTLEMENT_ANALYST' THEN ARRAY['order.read','rate.read','finance.read','finance.manage','invoice.manage','tax_invoice.manage','analytics.read']::text[]
        WHEN 'FINANCE_APPROVER' THEN ARRAY['finance.read','finance.approve','accounting.export','analytics.read']::text[]
        WHEN 'CLAIM_MANAGER' THEN ARRAY['execution.read','claim.read','claim.manage','finance.read']::text[]
        WHEN 'ANALYST' THEN ARRAY['analytics.read']::text[]
        WHEN 'AUDITOR' THEN ARRAY['audit.read','finance.read','claim.read','analytics.read','pii.read']::text[]
        ELSE ARRAY[]::text[]
    END
)
WHERE r.tenant_id IS NULL AND r.role_code <> 'TMS_ADMIN'
ON CONFLICT DO NOTHING;

COMMENT ON SCHEMA etms IS 'Enterprise transportation management system: IAM, master, order, planning, dispatch, execution, performance, settlement, accounting, analytics, and integration.';
COMMENT ON TABLE etms.users IS 'Global application principals mapped one-to-one to Firebase UID. Tenant access is controlled by tenant_memberships.';
COMMENT ON COLUMN etms.users.firebase_uid IS 'Canonical Firebase token subject (uid); do not identify users by mutable email.';
COMMENT ON TABLE etms.transport_orders IS 'Customer transportation demand. Orders can split across shipments and multiple orders can consolidate into one shipment.';
COMMENT ON TABLE etms.shipments IS 'Commercial/planned movement grouping one or more orders, potentially across several modal legs.';
COMMENT ON TABLE etms.transport_runs IS 'Physical operating trip/vehicle rotation. Shipment legs are allocated to runs independently of commercial shipment structure.';
COMMENT ON TABLE etms.transport_events IS 'Append-oriented execution event ledger. occurred_at and received_at are separate to preserve delayed/out-of-order events.';
COMMENT ON TABLE etms.charges IS 'Canonical BUY/SELL charge ledger across estimate, accrual, actual, invoice, and settlement stages; corrections use adjustments or reversals.';
COMMENT ON TABLE etms.files IS 'Object-storage metadata only. Binary POD photos, signatures, and documents are not stored in PostgreSQL.';
