-- EWMS workflow, notifications, EDI/webhooks/jobs, audit extensions, and analytics.

CREATE TABLE IF NOT EXISTS ewms.status_definitions (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid REFERENCES ewms.tenants(id) ON DELETE CASCADE,
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
    ON ewms.status_definitions (
        COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), entity_type, status_code
    );

CREATE TABLE IF NOT EXISTS ewms.status_transitions (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid REFERENCES ewms.tenants(id) ON DELETE CASCADE,
    entity_type varchar(80) NOT NULL,
    from_status_code varchar(50) NOT NULL,
    to_status_code varchar(50) NOT NULL,
    permission_code varchar(150) REFERENCES ewms.permissions(permission_code),
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
    ON ewms.status_transitions (
        COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), entity_type, from_status_code, to_status_code
    );

CREATE TABLE IF NOT EXISTS ewms.tags (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
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

CREATE TABLE IF NOT EXISTS ewms.entity_tags (
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    entity_type varchar(80) NOT NULL,
    entity_id uuid NOT NULL,
    tag_id uuid NOT NULL REFERENCES ewms.tags(id) ON DELETE CASCADE,
    assigned_by uuid REFERENCES ewms.users(id),
    assigned_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, entity_type, entity_id, tag_id)
);

CREATE TABLE IF NOT EXISTS ewms.notification_templates (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid REFERENCES ewms.tenants(id) ON DELETE CASCADE,
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
    ON ewms.notification_templates (
        COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), template_code, channel, locale, version_no
    );

CREATE TABLE IF NOT EXISTS ewms.notification_preferences (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    user_id uuid NOT NULL REFERENCES ewms.users(id) ON DELETE CASCADE,
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
    UNIQUE (tenant_id, user_id, event_type, channel),
    CONSTRAINT ck_notification_preference_channel CHECK (
        channel IN ('APP','EMAIL','SMS','PUSH','KAKAO','WEBHOOK')
    ),
    CONSTRAINT ck_notification_digest CHECK (
        digest_frequency IN ('IMMEDIATE','HOURLY','DAILY','WEEKLY','DISABLED')
    )
);

CREATE TABLE IF NOT EXISTS ewms.notifications (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    event_type varchar(100) NOT NULL,
    template_id uuid REFERENCES ewms.notification_templates(id),
    entity_type varchar(80),
    entity_id uuid,
    priority varchar(20) NOT NULL DEFAULT 'NORMAL',
    subject_rendered text,
    body_rendered text NOT NULL,
    variables_masked jsonb NOT NULL DEFAULT '{}'::jsonb,
    scheduled_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz,
    status varchar(20) NOT NULL DEFAULT 'QUEUED',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_notification_priority CHECK (priority IN ('LOW','NORMAL','HIGH','CRITICAL')),
    CONSTRAINT ck_notification_status CHECK (
        status IN ('QUEUED','PROCESSING','PARTIALLY_SENT','SENT','FAILED','CANCELLED','EXPIRED')
    ),
    CONSTRAINT ck_notification_dates CHECK (
        expires_at IS NULL OR expires_at > scheduled_at
    ),
    CONSTRAINT ck_notification_no_secret_variables CHECK (
        NOT ewms.jsonb_contains_forbidden_secret_key(variables_masked)
    )
);

CREATE TABLE IF NOT EXISTS ewms.notification_deliveries (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    notification_id uuid NOT NULL REFERENCES ewms.notifications(id) ON DELETE CASCADE,
    user_id uuid REFERENCES ewms.users(id),
    contact_id uuid REFERENCES ewms.contacts(id),
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
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_notification_recipient CHECK (user_id IS NOT NULL OR contact_id IS NOT NULL OR recipient_masked IS NOT NULL),
    CONSTRAINT ck_notification_attempt CHECK (attempt_count >= 0),
    CONSTRAINT ck_notification_delivery_channel CHECK (
        channel IN ('APP','EMAIL','SMS','PUSH','KAKAO','WEBHOOK')
    ),
    CONSTRAINT ck_notification_delivery_status CHECK (
        status IN ('QUEUED','PROCESSING','SENT','DELIVERED','READ','FAILED','BOUNCED','CANCELLED')
    )
);

CREATE TABLE IF NOT EXISTS ewms.edi_documents (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    external_system_id uuid REFERENCES ewms.external_systems(id),
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
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (external_system_id, direction, interchange_control_no, transaction_set_no),
    CONSTRAINT ck_edi_direction CHECK (direction IN ('IN','OUT')),
    CONSTRAINT ck_edi_hash CHECK (
        document_sha256 IS NULL OR document_sha256 ~ '^[0-9A-Fa-f]{64}$'
    ),
    CONSTRAINT ck_edi_status CHECK (
        status IN ('RECEIVED','VALIDATING','VALID','INVALID','PROCESSING','PROCESSED','FAILED','ARCHIVED')
    ),
    CONSTRAINT ck_edi_ack_status CHECK (
        acknowledgement_status IN ('PENDING','ACCEPTED','ACCEPTED_WITH_ERRORS','REJECTED','NOT_REQUIRED')
    )
);

CREATE TABLE IF NOT EXISTS ewms.edi_validation_errors (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    edi_document_id uuid NOT NULL REFERENCES ewms.edi_documents(id) ON DELETE CASCADE,
    error_level varchar(20) NOT NULL,
    segment_id varchar(30),
    element_position varchar(30),
    error_code varchar(80) NOT NULL,
    error_message text NOT NULL,
    offending_value_masked text,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_edi_error_level CHECK (error_level IN ('INFO','WARNING','ERROR','FATAL'))
);

CREATE TABLE IF NOT EXISTS ewms.webhook_subscriptions (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    subscription_code varchar(100) NOT NULL,
    target_url text NOT NULL,
    event_types text[] NOT NULL,
    signing_key_secret_ref varchar(300) NOT NULL,
    signing_key_fingerprint_sha256 char(64),
    http_headers_secret_ref varchar(300),
    retry_policy jsonb NOT NULL DEFAULT '{}'::jsonb,
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    last_success_at timestamptz,
    last_failure_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, subscription_code),
    CONSTRAINT ck_webhook_subscription_key_fingerprint CHECK (
        signing_key_fingerprint_sha256 IS NULL OR
        signing_key_fingerprint_sha256 ~ '^[0-9A-Fa-f]{64}$'
    ),
    CONSTRAINT ck_webhook_subscription_status CHECK (
        status IN ('ACTIVE','PAUSED','DISABLED','EXPIRED')
    ),
    CONSTRAINT ck_webhook_subscription_signing CHECK (
        btrim(signing_key_secret_ref) <> '' AND
        (http_headers_secret_ref IS NULL OR btrim(http_headers_secret_ref) <> '')
    )
);

COMMENT ON TABLE ewms.webhook_subscriptions IS
    'Webhook configuration stores external secret-manager references and an optional key fingerprint only; raw signing secrets, credentials in target_url, and plaintext authorization headers are prohibited.';

CREATE TABLE IF NOT EXISTS ewms.webhook_deliveries (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    subscription_id uuid NOT NULL REFERENCES ewms.webhook_subscriptions(id) ON DELETE CASCADE,
    outbox_event_id uuid REFERENCES ewms.outbox_events(id),
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
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (subscription_id, outbox_event_id, attempt_no),
    CONSTRAINT ck_webhook_attempt CHECK (attempt_no > 0),
    CONSTRAINT ck_webhook_http_status CHECK (http_status IS NULL OR http_status BETWEEN 100 AND 599),
    CONSTRAINT ck_webhook_payload_hash CHECK (payload_hash ~ '^[0-9A-Fa-f]{64}$'),
    CONSTRAINT ck_webhook_delivery_status CHECK (
        status IN ('QUEUED','SENDING','DELIVERED','RETRY','FAILED','CANCELLED')
    )
);

CREATE TABLE IF NOT EXISTS ewms.inbox_deduplication (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    source_system_id uuid NOT NULL REFERENCES ewms.external_systems(id),
    message_type varchar(100) NOT NULL,
    idempotency_key varchar(300) NOT NULL,
    payload_hash char(64) NOT NULL,
    first_received_at timestamptz NOT NULL DEFAULT now(),
    last_received_at timestamptz NOT NULL DEFAULT now(),
    receive_count integer NOT NULL DEFAULT 1,
    processed_resource_type varchar(80),
    processed_resource_id uuid,
    status varchar(20) NOT NULL DEFAULT 'RECEIVED',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (source_system_id, message_type, idempotency_key),
    CONSTRAINT ck_inbox_receive_count CHECK (receive_count > 0),
    CONSTRAINT ck_inbox_payload_hash CHECK (payload_hash ~ '^[0-9A-Fa-f]{64}$'),
    CONSTRAINT ck_inbox_status CHECK (
        status IN ('RECEIVED','DUPLICATE','PROCESSING','PROCESSED','FAILED','DEAD_LETTER')
    )
);

CREATE TABLE IF NOT EXISTS ewms.import_jobs (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    job_no varchar(100) NOT NULL,
    import_type varchar(80) NOT NULL,
    source_file_id uuid NOT NULL REFERENCES ewms.files(id),
    mapping_version varchar(50),
    validation_only boolean NOT NULL DEFAULT false,
    status varchar(20) NOT NULL DEFAULT 'QUEUED',
    total_rows integer NOT NULL DEFAULT 0,
    success_rows integer NOT NULL DEFAULT 0,
    warning_rows integer NOT NULL DEFAULT 0,
    error_rows integer NOT NULL DEFAULT 0,
    requested_by uuid REFERENCES ewms.users(id),
    requested_at timestamptz NOT NULL DEFAULT now(),
    started_at timestamptz,
    completed_at timestamptz,
    result_file_id uuid REFERENCES ewms.files(id),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, job_no),
    CONSTRAINT ck_import_job_counts CHECK (
        total_rows >= 0 AND success_rows >= 0 AND warning_rows >= 0 AND error_rows >= 0 AND
        success_rows + warning_rows + error_rows <= total_rows
    ),
    CONSTRAINT ck_import_job_status CHECK (
        status IN ('QUEUED','VALIDATING','READY','IMPORTING','COMPLETED','PARTIAL','FAILED','CANCELLED')
    ),
    CONSTRAINT ck_import_job_dates CHECK (
        (started_at IS NULL OR started_at >= requested_at) AND
        (completed_at IS NULL OR started_at IS NULL OR completed_at >= started_at)
    )
);

CREATE TABLE IF NOT EXISTS ewms.import_job_rows (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    import_job_id uuid NOT NULL REFERENCES ewms.import_jobs(id) ON DELETE CASCADE,
    row_no integer NOT NULL,
    source_data_masked jsonb NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'PENDING',
    target_entity_type varchar(80),
    target_entity_id uuid,
    validation_errors jsonb NOT NULL DEFAULT '[]'::jsonb,
    processed_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (import_job_id, row_no),
    CONSTRAINT ck_import_job_row_no CHECK (row_no > 0),
    CONSTRAINT ck_import_job_row_status CHECK (
        status IN ('PENDING','VALID','WARNING','INVALID','IMPORTED','SKIPPED','FAILED')
    )
);

CREATE TABLE IF NOT EXISTS ewms.export_jobs (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    job_no varchar(100) NOT NULL,
    export_type varchar(80) NOT NULL,
    output_format varchar(20) NOT NULL,
    filters jsonb NOT NULL DEFAULT '{}'::jsonb,
    selected_fields jsonb NOT NULL DEFAULT '[]'::jsonb,
    status varchar(20) NOT NULL DEFAULT 'QUEUED',
    row_count bigint NOT NULL DEFAULT 0,
    output_file_id uuid REFERENCES ewms.files(id),
    requested_by uuid REFERENCES ewms.users(id),
    requested_at timestamptz NOT NULL DEFAULT now(),
    completed_at timestamptz,
    expires_at timestamptz,
    error_detail_masked text,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, job_no),
    CONSTRAINT ck_export_job_format CHECK (output_format IN ('CSV','XLSX','JSON','XML','PDF','EDI')),
    CONSTRAINT ck_export_job_count CHECK (row_count >= 0),
    CONSTRAINT ck_export_job_status CHECK (
        status IN ('QUEUED','RUNNING','COMPLETED','PARTIAL','FAILED','CANCELLED','EXPIRED')
    ),
    CONSTRAINT ck_export_job_dates CHECK (
        (completed_at IS NULL OR completed_at >= requested_at) AND
        (expires_at IS NULL OR expires_at > requested_at)
    )
);

CREATE TABLE IF NOT EXISTS ewms.export_job_rows (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    export_job_id uuid NOT NULL REFERENCES ewms.export_jobs(id) ON DELETE CASCADE,
    row_no bigint NOT NULL,
    source_entity_type varchar(80),
    source_entity_id uuid,
    row_hash char(64),
    status varchar(20) NOT NULL DEFAULT 'PENDING',
    error_detail_masked text,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (export_job_id, row_no),
    CONSTRAINT ck_export_job_row_no CHECK (row_no > 0),
    CONSTRAINT ck_export_job_row_hash CHECK (
        row_hash IS NULL OR row_hash ~ '^[0-9A-Fa-f]{64}$'
    ),
    CONSTRAINT ck_export_job_row_status CHECK (
        status IN ('PENDING','EXPORTED','SKIPPED','FAILED')
    )
);

CREATE TABLE IF NOT EXISTS ewms.scheduled_jobs (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid REFERENCES ewms.tenants(id) ON DELETE CASCADE,
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
    CONSTRAINT ck_scheduled_job_concurrency CHECK (concurrency_policy IN ('ALLOW','FORBID','REPLACE')),
    CONSTRAINT ck_scheduled_job_status CHECK (status IN ('ACTIVE','PAUSED','DISABLED')),
    CONSTRAINT ck_scheduled_job_no_inline_secrets CHECK (
        NOT ewms.jsonb_contains_forbidden_secret_key(parameters)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_scheduled_jobs_scope
    ON ewms.scheduled_jobs (
        COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), job_code
    );

CREATE TABLE IF NOT EXISTS ewms.job_runs (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid REFERENCES ewms.tenants(id) ON DELETE CASCADE,
    scheduled_job_id uuid NOT NULL REFERENCES ewms.scheduled_jobs(id) ON DELETE CASCADE,
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
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (scheduled_job_id, run_no),
    CONSTRAINT ck_job_run_counts CHECK (
        processed_count >= 0 AND success_count >= 0 AND error_count >= 0 AND
        success_count + error_count <= processed_count
    ),
    CONSTRAINT ck_job_run_status CHECK (
        status IN ('QUEUED','RUNNING','SUCCEEDED','PARTIAL','FAILED','CANCELLED','TIMED_OUT','SKIPPED')
    ),
    CONSTRAINT ck_job_run_dates CHECK (
        (started_at IS NULL OR started_at >= queued_at) AND
        (completed_at IS NULL OR started_at IS NULL OR completed_at >= started_at)
    )
);

CREATE TABLE IF NOT EXISTS ewms.dead_letter_messages (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
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
    resolved_by uuid REFERENCES ewms.users(id),
    resolution text,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_dead_letter_retry CHECK (retry_count >= 0),
    CONSTRAINT ck_dead_letter_hash CHECK (
        payload_hash IS NULL OR payload_hash ~ '^[0-9A-Fa-f]{64}$'
    ),
    CONSTRAINT ck_dead_letter_status CHECK (
        status IN ('OPEN','RETRY_QUEUED','RETRYING','RESOLVED','DISCARDED')
    ),
    CONSTRAINT ck_dead_letter_resolution CHECK (
        status NOT IN ('RESOLVED','DISCARDED') OR resolved_at IS NOT NULL
    )
);

CREATE TABLE IF NOT EXISTS ewms.impersonation_sessions (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    administrator_user_id uuid NOT NULL REFERENCES ewms.users(id),
    impersonated_user_id uuid NOT NULL REFERENCES ewms.users(id),
    reason text NOT NULL,
    ticket_reference varchar(150),
    requested_at timestamptz NOT NULL DEFAULT now(),
    approved_by uuid REFERENCES ewms.users(id),
    approved_at timestamptz,
    started_at timestamptz,
    ended_at timestamptz,
    status varchar(20) NOT NULL DEFAULT 'REQUESTED',
    ip_address inet,
    user_agent text,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_impersonation_users CHECK (administrator_user_id <> impersonated_user_id),
    CONSTRAINT ck_impersonation_status CHECK (
        status IN ('REQUESTED','APPROVED','ACTIVE','ENDED','DENIED','REVOKED')
    ),
    CONSTRAINT ck_impersonation_approval CHECK (
        status NOT IN ('APPROVED','ACTIVE','ENDED') OR
        (approved_by IS NOT NULL AND approved_at IS NOT NULL)
    ),
    CONSTRAINT ck_impersonation_lifecycle CHECK (
        (status NOT IN ('ACTIVE','ENDED') OR started_at IS NOT NULL) AND
        (status <> 'ENDED' OR ended_at IS NOT NULL)
    ),
    CONSTRAINT ck_impersonation_dates CHECK (
        (approved_at IS NULL OR approved_at >= requested_at) AND
        (started_at IS NULL OR approved_at IS NULL OR started_at >= approved_at) AND
        (ended_at IS NULL OR started_at IS NULL OR ended_at >= started_at)
    )
);

CREATE TABLE IF NOT EXISTS ewms.impersonation_events (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    impersonation_session_id uuid NOT NULL REFERENCES ewms.impersonation_sessions(id) ON DELETE RESTRICT,
    sequence_no integer NOT NULL,
    event_type varchar(20) NOT NULL,
    actor_user_id uuid NOT NULL REFERENCES ewms.users(id),
    reason text,
    detail_masked jsonb NOT NULL DEFAULT '{}'::jsonb,
    ip_address inet,
    user_agent text,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    recorded_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (impersonation_session_id, sequence_no),
    CONSTRAINT ck_impersonation_event_sequence CHECK (sequence_no > 0),
    CONSTRAINT ck_impersonation_event_type CHECK (
        event_type IN ('REQUESTED','APPROVED','STARTED','ENDED','DENIED','REVOKED','ACCESSED')
    )
);

CREATE TABLE IF NOT EXISTS ewms.entity_change_logs (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    entity_type varchar(80) NOT NULL,
    entity_id uuid NOT NULL,
    operation varchar(10) NOT NULL,
    changed_fields text[],
    before_data_masked jsonb,
    after_data_masked jsonb,
    row_version_before bigint,
    row_version_after bigint,
    actor_user_id uuid REFERENCES ewms.users(id),
    correlation_id varchar(100),
    occurred_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_entity_change_operation CHECK (operation IN ('INSERT','UPDATE','DELETE','RESTORE'))
);

CREATE TABLE IF NOT EXISTS ewms.data_access_logs (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid REFERENCES ewms.tenants(id),
    actor_user_id uuid REFERENCES ewms.users(id),
    actor_api_client_id uuid REFERENCES ewms.api_clients(id),
    access_type varchar(30) NOT NULL,
    entity_type varchar(80) NOT NULL,
    entity_id uuid,
    field_categories text[],
    purpose_code varchar(80),
    result_count integer,
    ip_address inet,
    correlation_id varchar(100),
    occurred_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_data_access_actor CHECK (num_nonnulls(actor_user_id, actor_api_client_id) = 1),
    CONSTRAINT ck_data_access_count CHECK (result_count IS NULL OR result_count >= 0)
);

-- Operational, inventory, customs, billing, and interface reconciliation.

CREATE TABLE IF NOT EXISTS ewms.reconciliation_runs (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    reconciliation_no varchar(120) NOT NULL,
    reconciliation_type varchar(40) NOT NULL,
    warehouse_id uuid REFERENCES ewms.warehouses(id),
    owner_partner_id uuid REFERENCES ewms.business_partners(id),
    external_system_id uuid REFERENCES ewms.external_systems(id),
    as_of_at timestamptz NOT NULL,
    tolerance_quantity numeric(24,8) NOT NULL DEFAULT 0,
    tolerance_amount numeric(24,4) NOT NULL DEFAULT 0,
    currency_code char(3) REFERENCES ewms.currencies(currency_code),
    status varchar(20) NOT NULL DEFAULT 'QUEUED',
    total_count bigint NOT NULL DEFAULT 0,
    matched_count bigint NOT NULL DEFAULT 0,
    mismatch_count bigint NOT NULL DEFAULT 0,
    missing_count bigint NOT NULL DEFAULT 0,
    requested_by uuid REFERENCES ewms.users(id),
    requested_at timestamptz NOT NULL DEFAULT now(),
    started_at timestamptz,
    completed_at timestamptz,
    approved_by uuid REFERENCES ewms.users(id),
    approved_at timestamptz,
    result_summary jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, reconciliation_no),
    CONSTRAINT ck_reconciliation_type CHECK (reconciliation_type IN (
        'INVENTORY_BALANCE','INVENTORY_LEDGER','BONDED_VS_PHYSICAL',
        'CUSTOMS_VS_BONDED','BILLING_VS_OPERATION','INVOICE_VS_CHARGE',
        'GENERAL_LEDGER','SYSTEM_INTERFACE'
    )),
    CONSTRAINT ck_reconciliation_status CHECK (status IN (
        'QUEUED','RUNNING','COMPLETED','EXCEPTION','APPROVAL_PENDING',
        'APPROVED','FAILED','CANCELLED'
    )),
    CONSTRAINT ck_reconciliation_tolerance CHECK (
        tolerance_quantity >= 0 AND tolerance_amount >= 0
    ),
    CONSTRAINT ck_reconciliation_counts CHECK (
        total_count >= 0 AND matched_count >= 0 AND mismatch_count >= 0 AND missing_count >= 0 AND
        matched_count + mismatch_count + missing_count <= total_count
    ),
    CONSTRAINT ck_reconciliation_dates CHECK (
        (started_at IS NULL OR started_at >= requested_at) AND
        (completed_at IS NULL OR started_at IS NULL OR completed_at >= started_at) AND
        (approved_at IS NULL OR completed_at IS NULL OR approved_at >= completed_at)
    )
);

CREATE TABLE IF NOT EXISTS ewms.reconciliation_details (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    reconciliation_run_id uuid NOT NULL REFERENCES ewms.reconciliation_runs(id) ON DELETE CASCADE,
    detail_no bigint NOT NULL,
    entity_type varchar(80) NOT NULL,
    entity_id uuid,
    source_a_reference varchar(300),
    source_b_reference varchar(300),
    source_a_quantity numeric(24,8),
    source_b_quantity numeric(24,8),
    quantity_difference numeric(24,8),
    uom_code varchar(20) REFERENCES ewms.units_of_measure(uom_code),
    source_a_amount numeric(24,4),
    source_b_amount numeric(24,4),
    amount_difference numeric(24,4),
    currency_code char(3) REFERENCES ewms.currencies(currency_code),
    result varchar(30) NOT NULL,
    difference_reason_code varchar(80),
    resolution_status varchar(20) NOT NULL DEFAULT 'OPEN',
    assigned_to uuid REFERENCES ewms.users(id),
    resolved_by uuid REFERENCES ewms.users(id),
    resolved_at timestamptz,
    resolution text,
    evidence_masked jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (reconciliation_run_id, detail_no),
    CONSTRAINT ck_reconciliation_detail_no CHECK (detail_no > 0),
    CONSTRAINT ck_reconciliation_detail_result CHECK (result IN (
        'MATCHED','QUANTITY_MISMATCH','AMOUNT_MISMATCH','BOTH_MISMATCH',
        'MISSING_SOURCE_A','MISSING_SOURCE_B','DUPLICATE','INVALID'
    )),
    CONSTRAINT ck_reconciliation_detail_resolution CHECK (
        resolution_status IN ('OPEN','ASSIGNED','RESOLVED','WAIVED','ADJUSTED')
    )
);

-- Workflow and approval orchestration.

CREATE TABLE IF NOT EXISTS ewms.workflow_definitions (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    workflow_code varchar(100) NOT NULL,
    workflow_name varchar(250) NOT NULL,
    entity_type varchar(80) NOT NULL,
    description text,
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, workflow_code)
);

CREATE TABLE IF NOT EXISTS ewms.workflow_versions (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    workflow_definition_id uuid NOT NULL REFERENCES ewms.workflow_definitions(id) ON DELETE CASCADE,
    version_no integer NOT NULL,
    effective_from timestamptz NOT NULL,
    effective_to timestamptz,
    trigger_conditions jsonb NOT NULL DEFAULT '{}'::jsonb,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    published_by uuid REFERENCES ewms.users(id),
    published_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (workflow_definition_id, version_no),
    CONSTRAINT ck_workflow_version_no CHECK (version_no > 0),
    CONSTRAINT ck_workflow_version_dates CHECK (effective_to IS NULL OR effective_to > effective_from),
    CONSTRAINT ck_workflow_version_status CHECK (
        status IN ('DRAFT','REVIEW','PUBLISHED','RETIRED','REJECTED')
    ),
    CONSTRAINT ck_workflow_version_publish CHECK (
        status <> 'PUBLISHED' OR (published_by IS NOT NULL AND published_at IS NOT NULL)
    )
);

CREATE TABLE IF NOT EXISTS ewms.workflow_steps (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    workflow_version_id uuid NOT NULL REFERENCES ewms.workflow_versions(id) ON DELETE CASCADE,
    step_code varchar(80) NOT NULL,
    step_name varchar(200) NOT NULL,
    step_type varchar(30) NOT NULL,
    sequence_no integer NOT NULL,
    assignee_rule jsonb NOT NULL DEFAULT '{}'::jsonb,
    due_rule jsonb NOT NULL DEFAULT '{}'::jsonb,
    entry_condition jsonb NOT NULL DEFAULT '{}'::jsonb,
    completion_condition jsonb NOT NULL DEFAULT '{}'::jsonb,
    on_approve_step_code varchar(80),
    on_reject_step_code varchar(80),
    escalation_rule jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (workflow_version_id, step_code),
    UNIQUE (workflow_version_id, sequence_no),
    CONSTRAINT ck_workflow_step_sequence CHECK (sequence_no > 0),
    CONSTRAINT ck_workflow_step_type CHECK (step_type IN ('APPROVAL','REVIEW','TASK','AUTOMATION','NOTIFICATION','GATE'))
);

CREATE TABLE IF NOT EXISTS ewms.workflow_instances (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    workflow_version_id uuid NOT NULL REFERENCES ewms.workflow_versions(id),
    entity_type varchar(80) NOT NULL,
    entity_id uuid NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'RUNNING',
    current_step_id uuid REFERENCES ewms.workflow_steps(id),
    started_at timestamptz NOT NULL DEFAULT now(),
    completed_at timestamptz,
    cancelled_at timestamptz,
    context jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_by uuid REFERENCES ewms.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_workflow_instance_status CHECK (
        status IN ('PENDING','RUNNING','SUSPENDED','COMPLETED','FAILED','CANCELLED')
    ),
    CONSTRAINT ck_workflow_instance_dates CHECK (
        (completed_at IS NULL OR completed_at >= started_at) AND
        (cancelled_at IS NULL OR cancelled_at >= started_at) AND
        num_nonnulls(completed_at, cancelled_at) <= 1
    )
);

CREATE TABLE IF NOT EXISTS ewms.workflow_tasks (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    workflow_instance_id uuid NOT NULL REFERENCES ewms.workflow_instances(id) ON DELETE CASCADE,
    workflow_step_id uuid NOT NULL REFERENCES ewms.workflow_steps(id),
    task_no integer NOT NULL,
    assignee_user_id uuid REFERENCES ewms.users(id),
    assignee_group_id uuid REFERENCES ewms.user_groups(id),
    status varchar(20) NOT NULL DEFAULT 'PENDING',
    assigned_at timestamptz NOT NULL DEFAULT now(),
    due_at timestamptz,
    completed_at timestamptz,
    decision varchar(20),
    comments text,
    outcome_data jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (workflow_instance_id, task_no),
    CONSTRAINT ck_workflow_task_assignee CHECK (
        num_nonnulls(assignee_user_id, assignee_group_id) = 1
    ),
    CONSTRAINT ck_workflow_task_status CHECK (
        status IN ('PENDING','ASSIGNED','IN_PROGRESS','APPROVED','REJECTED','COMPLETED','CANCELLED','EXPIRED')
    ),
    CONSTRAINT ck_workflow_task_decision CHECK (
        decision IS NULL OR decision IN ('APPROVE','REJECT','RETURN','SKIP','COMPLETE')
    ),
    CONSTRAINT ck_workflow_task_dates CHECK (
        (due_at IS NULL OR due_at >= assigned_at) AND
        (completed_at IS NULL OR completed_at >= assigned_at)
    )
);

CREATE TABLE IF NOT EXISTS ewms.approval_policies (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    policy_code varchar(100) NOT NULL,
    policy_name varchar(250) NOT NULL,
    entity_type varchar(80) NOT NULL,
    condition_expression jsonb NOT NULL DEFAULT '{}'::jsonb,
    approval_levels integer NOT NULL DEFAULT 1,
    allow_self_approval boolean NOT NULL DEFAULT false,
    escalation_minutes integer,
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, policy_code),
    CONSTRAINT ck_approval_policy_levels CHECK (approval_levels > 0),
    CONSTRAINT ck_approval_policy_escalation CHECK (escalation_minutes IS NULL OR escalation_minutes > 0)
);

CREATE TABLE IF NOT EXISTS ewms.approval_requests (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    request_no varchar(100) NOT NULL,
    policy_id uuid REFERENCES ewms.approval_policies(id),
    workflow_instance_id uuid REFERENCES ewms.workflow_instances(id),
    entity_type varchar(80) NOT NULL,
    entity_id uuid NOT NULL,
    amount numeric(20,4),
    currency_code char(3) REFERENCES ewms.currencies(currency_code),
    reason text,
    status varchar(20) NOT NULL DEFAULT 'PENDING',
    requested_by uuid NOT NULL REFERENCES ewms.users(id),
    requested_at timestamptz NOT NULL DEFAULT now(),
    completed_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, request_no),
    CONSTRAINT ck_approval_request_status CHECK (
        status IN ('PENDING','IN_REVIEW','APPROVED','REJECTED','RETURNED','CANCELLED','EXPIRED')
    ),
    CONSTRAINT ck_approval_request_amount CHECK (amount IS NULL OR amount >= 0),
    CONSTRAINT ck_approval_request_dates CHECK (
        completed_at IS NULL OR completed_at >= requested_at
    )
);

CREATE TABLE IF NOT EXISTS ewms.approval_steps (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    approval_request_id uuid NOT NULL REFERENCES ewms.approval_requests(id) ON DELETE CASCADE,
    level_no integer NOT NULL,
    approver_user_id uuid REFERENCES ewms.users(id),
    approver_group_id uuid REFERENCES ewms.user_groups(id),
    status varchar(20) NOT NULL DEFAULT 'PENDING',
    assigned_at timestamptz NOT NULL DEFAULT now(),
    due_at timestamptz,
    decided_at timestamptz,
    decision varchar(20),
    comments text,
    delegated_from_user_id uuid REFERENCES ewms.users(id),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_approval_step_level CHECK (level_no > 0),
    CONSTRAINT ck_approval_step_approver CHECK (
        num_nonnulls(approver_user_id, approver_group_id) = 1
    ),
    CONSTRAINT ck_approval_step_status CHECK (
        status IN ('PENDING','ASSIGNED','APPROVED','REJECTED','RETURNED','DELEGATED','ESCALATED','CANCELLED','EXPIRED')
    ),
    CONSTRAINT ck_approval_step_decision CHECK (
        decision IS NULL OR decision IN ('APPROVE','REJECT','RETURN','DELEGATE','ESCALATE','CANCEL')
    ),
    CONSTRAINT ck_approval_step_dates CHECK (
        (due_at IS NULL OR due_at >= assigned_at) AND
        (decided_at IS NULL OR decided_at >= assigned_at)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_approval_steps_user
    ON ewms.approval_steps (approval_request_id, level_no, approver_user_id)
    WHERE approver_user_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS ux_approval_steps_group
    ON ewms.approval_steps (approval_request_id, level_no, approver_group_id)
    WHERE approver_group_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS ewms.approval_actions (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    approval_step_id uuid NOT NULL REFERENCES ewms.approval_steps(id) ON DELETE CASCADE,
    action_type varchar(20) NOT NULL,
    actor_user_id uuid NOT NULL REFERENCES ewms.users(id),
    comments text,
    ip_address inet,
    user_agent text,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_approval_action_type CHECK (action_type IN ('APPROVE','REJECT','RETURN','DELEGATE','ESCALATE','CANCEL','COMMENT'))
);

-- Segregation of duties (SoD) policy and detected conflicts.

CREATE TABLE IF NOT EXISTS ewms.sod_rules (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid REFERENCES ewms.tenants(id) ON DELETE CASCADE,
    rule_code varchar(100) NOT NULL,
    rule_name varchar(250) NOT NULL,
    domain_code varchar(50) NOT NULL,
    description text NOT NULL,
    severity varchar(20) NOT NULL DEFAULT 'HIGH',
    enforcement_mode varchar(20) NOT NULL DEFAULT 'PREVENT',
    scope_type varchar(30) NOT NULL DEFAULT 'TENANT',
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_sod_rule_severity CHECK (severity IN ('LOW','MEDIUM','HIGH','CRITICAL')),
    CONSTRAINT ck_sod_rule_mode CHECK (enforcement_mode IN ('PREVENT','WARN','DETECT')),
    CONSTRAINT ck_sod_rule_scope CHECK (
        scope_type IN ('TENANT','ORGANIZATION','WAREHOUSE','OWNER','ENTITY')
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_sod_rules_scope
    ON ewms.sod_rules (
        COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid),
        rule_code
    );

CREATE TABLE IF NOT EXISTS ewms.sod_rule_conflicts (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid REFERENCES ewms.tenants(id) ON DELETE CASCADE,
    sod_rule_id uuid NOT NULL REFERENCES ewms.sod_rules(id) ON DELETE CASCADE,
    left_permission_id uuid NOT NULL REFERENCES ewms.permissions(id),
    right_permission_id uuid NOT NULL REFERENCES ewms.permissions(id),
    conflict_condition jsonb NOT NULL DEFAULT '{}'::jsonb,
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (sod_rule_id, left_permission_id, right_permission_id),
    CONSTRAINT ck_sod_conflict_distinct CHECK (left_permission_id <> right_permission_id)
);

CREATE TABLE IF NOT EXISTS ewms.sod_violations (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    sod_rule_id uuid NOT NULL REFERENCES ewms.sod_rules(id),
    user_id uuid NOT NULL REFERENCES ewms.users(id),
    left_role_assignment_id uuid REFERENCES ewms.role_assignments(id),
    right_role_assignment_id uuid REFERENCES ewms.role_assignments(id),
    scope_type varchar(30),
    scope_id uuid,
    entity_type varchar(80),
    entity_id uuid,
    detected_at timestamptz NOT NULL DEFAULT now(),
    status varchar(20) NOT NULL DEFAULT 'OPEN',
    detected_evidence_masked jsonb NOT NULL DEFAULT '{}'::jsonb,
    assigned_to uuid REFERENCES ewms.users(id),
    waiver_reason text,
    waiver_expires_at timestamptz,
    waived_by uuid REFERENCES ewms.users(id),
    waived_at timestamptz,
    resolved_by uuid REFERENCES ewms.users(id),
    resolved_at timestamptz,
    resolution text,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_sod_violation_status CHECK (
        status IN ('OPEN','INVESTIGATING','WAIVED','REMEDIATED','FALSE_POSITIVE','CLOSED')
    ),
    CONSTRAINT ck_sod_violation_waiver CHECK (
        status <> 'WAIVED' OR (waiver_reason IS NOT NULL AND waived_by IS NOT NULL AND waived_at IS NOT NULL)
    ),
    CONSTRAINT ck_sod_violation_resolution CHECK (
        status NOT IN ('REMEDIATED','FALSE_POSITIVE','CLOSED') OR resolved_at IS NOT NULL
    )
);

COMMENT ON COLUMN ewms.workflow_versions.trigger_conditions IS
    'Declarative, allow-listed workflow DSL only; never execute this JSON as SQL, PL/pgSQL, shell, or template code.';
COMMENT ON COLUMN ewms.workflow_steps.assignee_rule IS
    'Declarative, allow-listed assignment DSL only; server-side code must validate operators and fields.';

-- KPI catalog, targets, calculated values, warehouse facts, and data quality.

CREATE TABLE IF NOT EXISTS ewms.kpi_definitions (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid REFERENCES ewms.tenants(id) ON DELETE CASCADE,
    kpi_code varchar(100) NOT NULL,
    kpi_name varchar(250) NOT NULL,
    domain_code varchar(50) NOT NULL,
    description text,
    unit_code varchar(30) NOT NULL,
    aggregation_method varchar(30) NOT NULL,
    numerator_definition text,
    denominator_definition text,
    calculation_expression jsonb NOT NULL DEFAULT '{}'::jsonb,
    calculation_version varchar(80) NOT NULL,
    direction varchar(20) NOT NULL DEFAULT 'HIGHER_BETTER',
    frequency varchar(20) NOT NULL,
    owner_org_unit_id uuid REFERENCES ewms.organization_units(id),
    valid_from date NOT NULL,
    valid_to date,
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_kpi_aggregation CHECK (
        aggregation_method IN ('SUM','COUNT','AVERAGE','MIN','MAX','RATIO','PERCENTILE','LAST_VALUE')
    ),
    CONSTRAINT ck_kpi_direction CHECK (
        direction IN ('HIGHER_BETTER','LOWER_BETTER','TARGET_RANGE','INFORMATIONAL')
    ),
    CONSTRAINT ck_kpi_frequency CHECK (
        frequency IN ('REALTIME','HOURLY','DAILY','WEEKLY','MONTHLY','QUARTERLY','YEARLY')
    ),
    CONSTRAINT ck_kpi_dates CHECK (valid_to IS NULL OR valid_to >= valid_from)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_kpi_definitions_scope
    ON ewms.kpi_definitions (
        COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid),
        kpi_code, calculation_version
    );

COMMENT ON COLUMN ewms.kpi_definitions.calculation_expression IS
    'Declarative, versioned KPI DSL only; never execute as SQL or application code.';

CREATE TABLE IF NOT EXISTS ewms.kpi_targets (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    kpi_definition_id uuid NOT NULL REFERENCES ewms.kpi_definitions(id),
    scope_type varchar(30) NOT NULL,
    scope_id uuid,
    warehouse_id uuid REFERENCES ewms.warehouses(id),
    owner_partner_id uuid REFERENCES ewms.business_partners(id),
    period_start date NOT NULL,
    period_end date NOT NULL,
    target_value numeric(30,10) NOT NULL,
    warning_threshold numeric(30,10),
    critical_threshold numeric(30,10),
    approved_by uuid REFERENCES ewms.users(id),
    approved_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_kpi_target_scope CHECK (
        scope_type IN ('TENANT','ORGANIZATION','WAREHOUSE','OWNER','CLIENT','ITEM','USER','TEAM')
    ),
    CONSTRAINT ck_kpi_target_dates CHECK (period_end >= period_start)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_kpi_targets_scope_period
    ON ewms.kpi_targets (
        tenant_id, kpi_definition_id, scope_type,
        COALESCE(scope_id, '00000000-0000-0000-0000-000000000000'::uuid),
        COALESCE(warehouse_id, '00000000-0000-0000-0000-000000000000'::uuid),
        COALESCE(owner_partner_id, '00000000-0000-0000-0000-000000000000'::uuid),
        period_start, period_end
    );

CREATE TABLE IF NOT EXISTS ewms.kpi_values (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    kpi_definition_id uuid NOT NULL REFERENCES ewms.kpi_definitions(id),
    scope_type varchar(30) NOT NULL,
    scope_id uuid,
    warehouse_id uuid REFERENCES ewms.warehouses(id),
    owner_partner_id uuid REFERENCES ewms.business_partners(id),
    period_start date NOT NULL,
    period_end date NOT NULL,
    kpi_value numeric(30,10),
    numerator numeric(30,10),
    denominator numeric(30,10),
    sample_size bigint,
    quality_status varchar(20) NOT NULL DEFAULT 'VALID',
    calculated_at timestamptz NOT NULL DEFAULT now(),
    source_lineage jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_kpi_value_scope CHECK (
        scope_type IN ('TENANT','ORGANIZATION','WAREHOUSE','OWNER','CLIENT','ITEM','USER','TEAM')
    ),
    CONSTRAINT ck_kpi_value_dates CHECK (period_end >= period_start),
    CONSTRAINT ck_kpi_value_sample CHECK (sample_size IS NULL OR sample_size >= 0),
    CONSTRAINT ck_kpi_value_quality CHECK (
        quality_status IN ('VALID','PARTIAL','ESTIMATED','STALE','INVALID')
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_kpi_values_scope_period
    ON ewms.kpi_values (
        tenant_id, kpi_definition_id, scope_type,
        COALESCE(scope_id, '00000000-0000-0000-0000-000000000000'::uuid),
        COALESCE(warehouse_id, '00000000-0000-0000-0000-000000000000'::uuid),
        COALESCE(owner_partner_id, '00000000-0000-0000-0000-000000000000'::uuid),
        period_start, period_end
    );

CREATE TABLE IF NOT EXISTS ewms.warehouse_daily_facts (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    fact_date date NOT NULL,
    warehouse_id uuid NOT NULL REFERENCES ewms.warehouses(id),
    warehouse_client_id uuid REFERENCES ewms.warehouse_clients(id),
    owner_partner_id uuid REFERENCES ewms.business_partners(id),
    inbound_order_count bigint NOT NULL DEFAULT 0,
    receipt_count bigint NOT NULL DEFAULT 0,
    outbound_order_count bigint NOT NULL DEFAULT 0,
    shipment_count bigint NOT NULL DEFAULT 0,
    return_order_count bigint NOT NULL DEFAULT 0,
    received_unit_quantity numeric(30,8) NOT NULL DEFAULT 0,
    shipped_unit_quantity numeric(30,8) NOT NULL DEFAULT 0,
    returned_unit_quantity numeric(30,8) NOT NULL DEFAULT 0,
    inventory_unit_quantity numeric(30,8) NOT NULL DEFAULT 0,
    occupied_location_count bigint NOT NULL DEFAULT 0,
    available_location_count bigint NOT NULL DEFAULT 0,
    exception_count bigint NOT NULL DEFAULT 0,
    on_time_receipt_count bigint NOT NULL DEFAULT 0,
    on_time_shipment_count bigint NOT NULL DEFAULT 0,
    labor_hours numeric(20,4) NOT NULL DEFAULT 0,
    billable_service_count bigint NOT NULL DEFAULT 0,
    loaded_at timestamptz NOT NULL DEFAULT now(),
    source_watermark timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_warehouse_daily_counts CHECK (
        inbound_order_count >= 0 AND receipt_count >= 0 AND outbound_order_count >= 0 AND
        shipment_count >= 0 AND return_order_count >= 0 AND occupied_location_count >= 0 AND
        available_location_count >= 0 AND exception_count >= 0 AND
        on_time_receipt_count >= 0 AND on_time_shipment_count >= 0 AND
        billable_service_count >= 0
    ),
    CONSTRAINT ck_warehouse_daily_quantities CHECK (
        received_unit_quantity >= 0 AND shipped_unit_quantity >= 0 AND
        returned_unit_quantity >= 0 AND inventory_unit_quantity >= 0 AND labor_hours >= 0
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_warehouse_daily_facts_grain
    ON ewms.warehouse_daily_facts (
        tenant_id, fact_date, warehouse_id,
        COALESCE(warehouse_client_id, '00000000-0000-0000-0000-000000000000'::uuid),
        COALESCE(owner_partner_id, '00000000-0000-0000-0000-000000000000'::uuid)
    );

CREATE TABLE IF NOT EXISTS ewms.inventory_daily_facts (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    fact_date date NOT NULL,
    warehouse_id uuid NOT NULL REFERENCES ewms.warehouses(id),
    warehouse_client_id uuid REFERENCES ewms.warehouse_clients(id),
    owner_partner_id uuid NOT NULL REFERENCES ewms.business_partners(id),
    item_id uuid NOT NULL REFERENCES ewms.items(id),
    inventory_status_id uuid NOT NULL REFERENCES ewms.inventory_statuses(id),
    opening_quantity numeric(30,8) NOT NULL DEFAULT 0,
    receipt_quantity numeric(30,8) NOT NULL DEFAULT 0,
    issue_quantity numeric(30,8) NOT NULL DEFAULT 0,
    adjustment_quantity numeric(30,8) NOT NULL DEFAULT 0,
    closing_quantity numeric(30,8) NOT NULL DEFAULT 0,
    allocated_quantity numeric(30,8) NOT NULL DEFAULT 0,
    available_quantity numeric(30,8) NOT NULL DEFAULT 0,
    hold_quantity numeric(30,8) NOT NULL DEFAULT 0,
    damaged_quantity numeric(30,8) NOT NULL DEFAULT 0,
    expired_quantity numeric(30,8) NOT NULL DEFAULT 0,
    in_transit_quantity numeric(30,8) NOT NULL DEFAULT 0,
    inventory_value numeric(30,4),
    currency_code char(3) REFERENCES ewms.currencies(currency_code),
    aged_over_30_quantity numeric(30,8) NOT NULL DEFAULT 0,
    aged_over_90_quantity numeric(30,8) NOT NULL DEFAULT 0,
    expiring_30_day_quantity numeric(30,8) NOT NULL DEFAULT 0,
    loaded_at timestamptz NOT NULL DEFAULT now(),
    source_watermark timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_inventory_daily_nonnegative CHECK (
        allocated_quantity >= 0 AND available_quantity >= 0 AND hold_quantity >= 0 AND
        damaged_quantity >= 0 AND expired_quantity >= 0 AND in_transit_quantity >= 0 AND
        aged_over_30_quantity >= 0 AND aged_over_90_quantity >= 0 AND
        expiring_30_day_quantity >= 0
    ),
    CONSTRAINT ck_inventory_daily_value CHECK (
        inventory_value IS NULL OR inventory_value >= 0
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_inventory_daily_facts_grain
    ON ewms.inventory_daily_facts (
        tenant_id, fact_date, warehouse_id,
        COALESCE(warehouse_client_id, '00000000-0000-0000-0000-000000000000'::uuid),
        owner_partner_id, item_id, inventory_status_id
    );

CREATE TABLE IF NOT EXISTS ewms.operation_daily_facts (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    fact_date date NOT NULL,
    warehouse_id uuid NOT NULL REFERENCES ewms.warehouses(id),
    warehouse_client_id uuid REFERENCES ewms.warehouse_clients(id),
    owner_partner_id uuid REFERENCES ewms.business_partners(id),
    operation_type varchar(30) NOT NULL,
    planned_task_count bigint NOT NULL DEFAULT 0,
    started_task_count bigint NOT NULL DEFAULT 0,
    completed_task_count bigint NOT NULL DEFAULT 0,
    cancelled_task_count bigint NOT NULL DEFAULT 0,
    exception_task_count bigint NOT NULL DEFAULT 0,
    processed_line_count bigint NOT NULL DEFAULT 0,
    processed_unit_quantity numeric(30,8) NOT NULL DEFAULT 0,
    standard_minutes numeric(30,4) NOT NULL DEFAULT 0,
    actual_minutes numeric(30,4) NOT NULL DEFAULT 0,
    labor_hours numeric(30,4) NOT NULL DEFAULT 0,
    on_time_count bigint NOT NULL DEFAULT 0,
    accuracy_numerator bigint NOT NULL DEFAULT 0,
    accuracy_denominator bigint NOT NULL DEFAULT 0,
    loaded_at timestamptz NOT NULL DEFAULT now(),
    source_watermark timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_operation_daily_type CHECK (operation_type IN (
        'INBOUND','RECEIPT','QUALITY','PUTAWAY','MOVE','REPLENISHMENT','COUNT',
        'PICK','PACK','SHIP','RETURN','VAS','YARD','CUSTOMS','BONDED'
    )),
    CONSTRAINT ck_operation_daily_counts CHECK (
        planned_task_count >= 0 AND started_task_count >= 0 AND completed_task_count >= 0 AND
        cancelled_task_count >= 0 AND exception_task_count >= 0 AND processed_line_count >= 0 AND
        on_time_count >= 0 AND accuracy_numerator >= 0 AND accuracy_denominator >= 0 AND
        accuracy_numerator <= accuracy_denominator
    ),
    CONSTRAINT ck_operation_daily_measures CHECK (
        processed_unit_quantity >= 0 AND standard_minutes >= 0 AND actual_minutes >= 0 AND labor_hours >= 0
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_operation_daily_facts_grain
    ON ewms.operation_daily_facts (
        tenant_id, fact_date, warehouse_id,
        COALESCE(warehouse_client_id, '00000000-0000-0000-0000-000000000000'::uuid),
        COALESCE(owner_partner_id, '00000000-0000-0000-0000-000000000000'::uuid),
        operation_type
    );

CREATE TABLE IF NOT EXISTS ewms.data_quality_rules (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid REFERENCES ewms.tenants(id) ON DELETE CASCADE,
    rule_code varchar(100) NOT NULL,
    rule_name varchar(250) NOT NULL,
    entity_type varchar(80) NOT NULL,
    severity varchar(20) NOT NULL,
    rule_expression jsonb NOT NULL,
    threshold_percent numeric(7,4),
    sample_limit integer NOT NULL DEFAULT 100,
    is_active boolean NOT NULL DEFAULT true,
    owner_user_id uuid REFERENCES ewms.users(id),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_data_quality_severity CHECK (
        severity IN ('INFO','WARNING','ERROR','CRITICAL')
    ),
    CONSTRAINT ck_data_quality_threshold CHECK (
        threshold_percent IS NULL OR threshold_percent BETWEEN 0 AND 100
    ),
    CONSTRAINT ck_data_quality_sample_limit CHECK (sample_limit > 0)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_data_quality_rules_scope
    ON ewms.data_quality_rules (
        COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid),
        rule_code
    );

COMMENT ON COLUMN ewms.data_quality_rules.rule_expression IS
    'Declarative, allow-listed validation DSL only; never execute this JSON as SQL or code.';

CREATE TABLE IF NOT EXISTS ewms.data_quality_results (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    evaluation_id uuid NOT NULL,
    rule_id uuid NOT NULL REFERENCES ewms.data_quality_rules(id),
    evaluated_at timestamptz NOT NULL,
    entity_id uuid,
    record_count bigint NOT NULL DEFAULT 0,
    failure_count bigint NOT NULL DEFAULT 0,
    failure_percent numeric(9,6),
    status varchar(20) NOT NULL,
    sample_failures_masked jsonb NOT NULL DEFAULT '[]'::jsonb,
    assigned_to uuid REFERENCES ewms.users(id),
    resolved_at timestamptz,
    resolved_by uuid REFERENCES ewms.users(id),
    resolution text,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_data_quality_counts CHECK (
        record_count >= 0 AND failure_count >= 0 AND failure_count <= record_count
    ),
    CONSTRAINT ck_data_quality_percent CHECK (
        failure_percent IS NULL OR failure_percent BETWEEN 0 AND 100
    ),
    CONSTRAINT ck_data_quality_result_status CHECK (
        status IN ('PASS','WARNING','FAIL','CRITICAL','WAIVED','RESOLVED')
    )
);

CREATE INDEX IF NOT EXISTS ix_data_quality_results_evaluation
    ON ewms.data_quality_results (tenant_id, evaluation_id, rule_id, status);

CREATE TABLE IF NOT EXISTS ewms.etl_watermarks (
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    pipeline_code varchar(100) NOT NULL,
    source_entity varchar(100) NOT NULL,
    watermark_type varchar(20) NOT NULL,
    watermark_value varchar(500),
    last_success_at timestamptz,
    last_attempt_at timestamptz,
    status varchar(20) NOT NULL DEFAULT 'IDLE',
    row_count bigint,
    error_detail_masked text,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, pipeline_code, source_entity),
    CONSTRAINT ck_etl_watermark_type CHECK (
        watermark_type IN ('TIMESTAMP','SEQUENCE','VERSION','DATE','OPAQUE')
    ),
    CONSTRAINT ck_etl_watermark_status CHECK (
        status IN ('IDLE','RUNNING','SUCCEEDED','FAILED','PAUSED')
    ),
    CONSTRAINT ck_etl_watermark_count CHECK (row_count IS NULL OR row_count >= 0)
);
