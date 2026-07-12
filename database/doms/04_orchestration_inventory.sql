-- DOMS enterprise OMS schema - order journeys, orchestration, ATP, sourcing,
-- fulfillment planning, and promise-level inventory reservations.
-- PostgreSQL 11 compatible. Applied after 03_order_capture_lifecycle.sql.
--
-- DOMS inventory is deliberately maintained at fulfillment-node + item promise
-- level. Physical warehouse lot, serial, stock-status, and location ledgers remain
-- the responsibility of WMS. WMS/ERP snapshots enter this module only through an
-- inventory source, a position, and append-only position events.

-- Composite tenant keys on upstream masters let every relationship below reject
-- a cross-tenant identifier at the foreign-key boundary.
CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_customers_tenant_id
    ON doms.customers (tenant_id, id);
CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_channels_tenant_id
    ON doms.sales_channels (tenant_id, id);
CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_nodes_tenant_id
    ON doms.fulfillment_nodes (tenant_id, id);
CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_items_tenant_id
    ON doms.items (tenant_id, id);
CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_ext_systems_tenant_id
    ON doms.external_systems (tenant_id, id);
CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_orders_tenant_id
    ON doms.sales_orders (tenant_id, id);
CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_order_lines_tenant_id
    ON doms.sales_order_lines (tenant_id, id);
CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_order_holds_tenant_id
    ON doms.order_holds (tenant_id, id);

-- -----------------------------------------------------------------------------
-- Order journey definitions and execution
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS doms.order_journey_definitions (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    journey_code varchar(80) NOT NULL,
    journey_name varchar(200) NOT NULL,
    entity_type varchar(30) NOT NULL DEFAULT 'SALES_ORDER',
    sales_channel_id uuid,
    description text,
    selection_criteria jsonb NOT NULL DEFAULT '{}'::jsonb,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    is_default boolean NOT NULL DEFAULT false,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    updated_by uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, journey_code),
    CONSTRAINT fk_doms_journey_channel FOREIGN KEY (tenant_id, sales_channel_id)
        REFERENCES doms.sales_channels(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_journey_code CHECK (btrim(journey_code) <> ''),
    CONSTRAINT ck_doms_journey_entity CHECK (entity_type IN ('SALES_ORDER','ORDER_LINE')),
    CONSTRAINT ck_doms_journey_status CHECK (status IN ('DRAFT','ACTIVE','SUSPENDED','RETIRED')),
    CONSTRAINT ck_doms_journey_criteria CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(selection_criteria)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_journey_default
    ON doms.order_journey_definitions (
        tenant_id,
        COALESCE(sales_channel_id, '00000000-0000-0000-0000-000000000000'::uuid),
        entity_type
    ) WHERE is_default AND status = 'ACTIVE';

CREATE TABLE IF NOT EXISTS doms.order_journey_versions (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    journey_definition_id uuid NOT NULL,
    version_no integer NOT NULL,
    version_status varchar(20) NOT NULL DEFAULT 'DRAFT',
    effective_from timestamptz,
    effective_to timestamptz,
    configuration jsonb NOT NULL DEFAULT '{}'::jsonb,
    definition_checksum_sha256 char(64),
    published_by uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    published_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, journey_definition_id, version_no),
    CONSTRAINT fk_doms_journey_version_definition
        FOREIGN KEY (tenant_id, journey_definition_id)
        REFERENCES doms.order_journey_definitions(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_journey_version_no CHECK (version_no > 0),
    CONSTRAINT ck_doms_journey_version_status CHECK (
        version_status IN ('DRAFT','PUBLISHED','ACTIVE','SUPERSEDED','RETIRED')
    ),
    CONSTRAINT ck_doms_journey_version_dates CHECK (
        effective_to IS NULL OR effective_from IS NULL OR effective_to > effective_from
    ),
    CONSTRAINT ck_doms_journey_version_publish CHECK (
        version_status NOT IN ('PUBLISHED','ACTIVE','SUPERSEDED','RETIRED') OR
        (published_by IS NOT NULL AND published_at IS NOT NULL)
    ),
    CONSTRAINT ck_doms_journey_version_checksum CHECK (
        definition_checksum_sha256 IS NULL OR
        definition_checksum_sha256 ~ '^[0-9A-Fa-f]{64}$'
    ),
    CONSTRAINT ck_doms_journey_version_config CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(configuration)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_journey_active_version
    ON doms.order_journey_versions (tenant_id, journey_definition_id)
    WHERE version_status = 'ACTIVE';

CREATE TABLE IF NOT EXISTS doms.order_journey_steps (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    journey_version_id uuid NOT NULL,
    step_code varchar(80) NOT NULL,
    step_name varchar(200) NOT NULL,
    step_type varchar(30) NOT NULL,
    execution_mode varchar(20) NOT NULL DEFAULT 'SYNCHRONOUS',
    handler_code varchar(150),
    sequence_no integer NOT NULL,
    is_entry_step boolean NOT NULL DEFAULT false,
    is_terminal_step boolean NOT NULL DEFAULT false,
    is_optional boolean NOT NULL DEFAULT false,
    timeout_seconds integer,
    max_attempts integer NOT NULL DEFAULT 1,
    retry_policy jsonb NOT NULL DEFAULT '{}'::jsonb,
    handler_config jsonb NOT NULL DEFAULT '{}'::jsonb,
    input_schema jsonb NOT NULL DEFAULT '{}'::jsonb,
    output_schema jsonb NOT NULL DEFAULT '{}'::jsonb,
    compensation_step_id uuid,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, journey_version_id, id),
    UNIQUE (tenant_id, journey_version_id, step_code),
    UNIQUE (tenant_id, journey_version_id, sequence_no),
    CONSTRAINT fk_doms_journey_step_version
        FOREIGN KEY (tenant_id, journey_version_id)
        REFERENCES doms.order_journey_versions(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_journey_step_code CHECK (btrim(step_code) <> ''),
    CONSTRAINT ck_doms_journey_step_type CHECK (step_type IN (
        'VALIDATE','RISK','PAYMENT','ATP','SOURCE','RESERVE','ALLOCATE','RELEASE',
        'FULFILL','NOTIFY','WAIT','APPROVAL','INTEGRATION','DECISION','CUSTOM'
    )),
    CONSTRAINT ck_doms_journey_step_mode CHECK (
        execution_mode IN ('SYNCHRONOUS','ASYNCHRONOUS','HUMAN','EVENT_WAIT')
    ),
    CONSTRAINT ck_doms_journey_step_values CHECK (
        sequence_no > 0 AND max_attempts > 0 AND
        (timeout_seconds IS NULL OR timeout_seconds > 0) AND
        NOT (is_entry_step AND is_terminal_step)
    ),
    CONSTRAINT ck_doms_journey_step_handler CHECK (
        step_type IN ('WAIT','APPROVAL','DECISION') OR
        (handler_code IS NOT NULL AND btrim(handler_code) <> '')
    ),
    CONSTRAINT ck_doms_journey_step_json CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(retry_policy) AND
        NOT doms.jsonb_contains_forbidden_secret_key(handler_config) AND
        NOT doms.jsonb_contains_forbidden_secret_key(input_schema) AND
        NOT doms.jsonb_contains_forbidden_secret_key(output_schema)
    )
);

ALTER TABLE doms.order_journey_steps
    DROP CONSTRAINT IF EXISTS fk_doms_journey_step_compensation;
ALTER TABLE doms.order_journey_steps
    ADD CONSTRAINT fk_doms_journey_step_compensation
    FOREIGN KEY (tenant_id, journey_version_id, compensation_step_id)
    REFERENCES doms.order_journey_steps(tenant_id, journey_version_id, id)
    ON DELETE RESTRICT;

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_journey_entry_step
    ON doms.order_journey_steps (tenant_id, journey_version_id)
    WHERE is_entry_step;

CREATE TABLE IF NOT EXISTS doms.order_journey_transitions (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    journey_version_id uuid NOT NULL,
    from_step_id uuid NOT NULL,
    to_step_id uuid NOT NULL,
    outcome_code varchar(80) NOT NULL DEFAULT 'SUCCESS',
    priority integer NOT NULL DEFAULT 100,
    is_default boolean NOT NULL DEFAULT false,
    condition_config jsonb NOT NULL DEFAULT '{}'::jsonb,
    transition_action jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, journey_version_id, from_step_id, outcome_code, priority),
    CONSTRAINT fk_doms_journey_transition_version
        FOREIGN KEY (tenant_id, journey_version_id)
        REFERENCES doms.order_journey_versions(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_journey_transition_from
        FOREIGN KEY (tenant_id, journey_version_id, from_step_id)
        REFERENCES doms.order_journey_steps(tenant_id, journey_version_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_journey_transition_to
        FOREIGN KEY (tenant_id, journey_version_id, to_step_id)
        REFERENCES doms.order_journey_steps(tenant_id, journey_version_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_journey_transition_steps CHECK (from_step_id <> to_step_id),
    CONSTRAINT ck_doms_journey_transition_values CHECK (
        btrim(outcome_code) <> '' AND priority >= 0
    ),
    CONSTRAINT ck_doms_journey_transition_json CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(condition_config) AND
        NOT doms.jsonb_contains_forbidden_secret_key(transition_action)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_journey_default_transition
    ON doms.order_journey_transitions (
        tenant_id, journey_version_id, from_step_id, outcome_code
    ) WHERE is_default;

CREATE TABLE IF NOT EXISTS doms.order_journey_runs (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    journey_definition_id uuid NOT NULL,
    journey_version_id uuid NOT NULL,
    sales_order_id uuid NOT NULL,
    run_no integer NOT NULL,
    run_status varchar(30) NOT NULL DEFAULT 'PENDING',
    current_step_id uuid,
    blocking_order_hold_id uuid,
    trigger_type varchar(30) NOT NULL DEFAULT 'ORDER_EVENT',
    trigger_reference varchar(300),
    idempotency_key varchar(200) NOT NULL,
    correlation_id varchar(100),
    causation_id varchar(100),
    context_data jsonb NOT NULL DEFAULT '{}'::jsonb,
    started_at timestamptz,
    completed_at timestamptz,
    cancelled_at timestamptz,
    last_heartbeat_at timestamptz,
    started_by uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, journey_version_id, id),
    UNIQUE (tenant_id, sales_order_id, journey_version_id, run_no),
    UNIQUE (tenant_id, journey_version_id, idempotency_key),
    CONSTRAINT fk_doms_journey_run_definition
        FOREIGN KEY (tenant_id, journey_definition_id)
        REFERENCES doms.order_journey_definitions(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_journey_run_version
        FOREIGN KEY (tenant_id, journey_version_id)
        REFERENCES doms.order_journey_versions(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_journey_run_order
        FOREIGN KEY (tenant_id, sales_order_id)
        REFERENCES doms.sales_orders(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_journey_run_step
        FOREIGN KEY (tenant_id, journey_version_id, current_step_id)
        REFERENCES doms.order_journey_steps(tenant_id, journey_version_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_journey_run_hold
        FOREIGN KEY (tenant_id, blocking_order_hold_id)
        REFERENCES doms.order_holds(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_journey_run_no CHECK (run_no > 0),
    CONSTRAINT ck_doms_journey_run_key CHECK (btrim(idempotency_key) <> ''),
    CONSTRAINT ck_doms_journey_run_status CHECK (run_status IN (
        'PENDING','RUNNING','WAITING','BLOCKED','COMPENSATING','SUCCEEDED','FAILED',
        'CANCELLED','TIMED_OUT'
    )),
    CONSTRAINT ck_doms_journey_run_trigger CHECK (trigger_type IN (
        'ORDER_EVENT','MANUAL','SCHEDULED','INTEGRATION','RETRY','COMPENSATION'
    )),
    CONSTRAINT ck_doms_journey_run_dates CHECK (
        (completed_at IS NULL OR completed_at >= COALESCE(started_at, created_at)) AND
        (cancelled_at IS NULL OR cancelled_at >= COALESCE(started_at, created_at)) AND
        (last_heartbeat_at IS NULL OR last_heartbeat_at >= COALESCE(started_at, created_at))
    ),
    CONSTRAINT ck_doms_journey_run_terminal CHECK (
        (run_status = 'SUCCEEDED' AND completed_at IS NOT NULL) OR
        (run_status = 'CANCELLED' AND cancelled_at IS NOT NULL) OR
        run_status NOT IN ('SUCCEEDED','CANCELLED')
    ),
    CONSTRAINT ck_doms_journey_run_context CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(context_data)
    )
);

CREATE TABLE IF NOT EXISTS doms.order_journey_step_runs (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    journey_run_id uuid NOT NULL,
    journey_version_id uuid NOT NULL,
    journey_step_id uuid NOT NULL,
    attempt_no integer NOT NULL,
    step_status varchar(30) NOT NULL DEFAULT 'PENDING',
    worker_reference varchar(200),
    idempotency_key varchar(200) NOT NULL,
    input_data jsonb NOT NULL DEFAULT '{}'::jsonb,
    output_data jsonb NOT NULL DEFAULT '{}'::jsonb,
    started_at timestamptz,
    heartbeat_at timestamptz,
    next_retry_at timestamptz,
    completed_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, journey_run_id, id),
    UNIQUE (tenant_id, journey_run_id, journey_step_id, attempt_no),
    UNIQUE (tenant_id, journey_run_id, idempotency_key),
    CONSTRAINT fk_doms_journey_step_run
        FOREIGN KEY (tenant_id, journey_version_id, journey_run_id)
        REFERENCES doms.order_journey_runs(tenant_id, journey_version_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_journey_step_run_step
        FOREIGN KEY (tenant_id, journey_version_id, journey_step_id)
        REFERENCES doms.order_journey_steps(tenant_id, journey_version_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_journey_step_attempt CHECK (attempt_no > 0),
    CONSTRAINT ck_doms_journey_step_run_key CHECK (btrim(idempotency_key) <> ''),
    CONSTRAINT ck_doms_journey_step_run_status CHECK (step_status IN (
        'PENDING','READY','RUNNING','WAITING','SUCCEEDED','FAILED','RETRY_SCHEDULED',
        'SKIPPED','COMPENSATED','CANCELLED','TIMED_OUT'
    )),
    CONSTRAINT ck_doms_journey_step_run_dates CHECK (
        (heartbeat_at IS NULL OR heartbeat_at >= COALESCE(started_at, created_at)) AND
        (completed_at IS NULL OR completed_at >= COALESCE(started_at, created_at)) AND
        (next_retry_at IS NULL OR next_retry_at >= created_at)
    ),
    CONSTRAINT ck_doms_journey_step_run_json CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(input_data) AND
        NOT doms.jsonb_contains_forbidden_secret_key(output_data)
    )
);

CREATE TABLE IF NOT EXISTS doms.order_journey_run_errors (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    journey_run_id uuid NOT NULL,
    journey_step_run_id uuid,
    error_sequence integer NOT NULL,
    error_code varchar(120) NOT NULL,
    error_category varchar(30) NOT NULL,
    retryable boolean NOT NULL DEFAULT false,
    error_message_masked text NOT NULL,
    error_details_masked jsonb NOT NULL DEFAULT '{}'::jsonb,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, journey_run_id, error_sequence),
    CONSTRAINT fk_doms_journey_error_run
        FOREIGN KEY (tenant_id, journey_run_id)
        REFERENCES doms.order_journey_runs(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_journey_error_step_run
        FOREIGN KEY (tenant_id, journey_run_id, journey_step_run_id)
        REFERENCES doms.order_journey_step_runs(tenant_id, journey_run_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_journey_error_sequence CHECK (error_sequence > 0),
    CONSTRAINT ck_doms_journey_error_code CHECK (btrim(error_code) <> ''),
    CONSTRAINT ck_doms_journey_error_category CHECK (error_category IN (
        'VALIDATION','BUSINESS','TRANSIENT','INTEGRATION','TIMEOUT','SECURITY','SYSTEM','UNKNOWN'
    )),
    CONSTRAINT ck_doms_journey_error_json CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(error_details_masked)
    )
);

-- -----------------------------------------------------------------------------
-- Promise-level inventory sources, measures, positions, supply, and demand
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS doms.inventory_sources (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    source_code varchar(80) NOT NULL,
    source_name varchar(200) NOT NULL,
    source_type varchar(30) NOT NULL,
    external_system_id uuid,
    sales_channel_id uuid,
    default_fulfillment_node_id uuid,
    source_priority integer NOT NULL DEFAULT 100,
    stale_after_seconds integer NOT NULL DEFAULT 900,
    supports_reservation boolean NOT NULL DEFAULT true,
    supports_future_supply boolean NOT NULL DEFAULT false,
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    secret_reference varchar(500),
    source_config jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, source_code),
    CONSTRAINT fk_doms_inventory_source_system
        FOREIGN KEY (tenant_id, external_system_id)
        REFERENCES doms.external_systems(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_inventory_source_channel
        FOREIGN KEY (tenant_id, sales_channel_id)
        REFERENCES doms.sales_channels(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_inventory_source_node
        FOREIGN KEY (tenant_id, default_fulfillment_node_id)
        REFERENCES doms.fulfillment_nodes(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_inventory_source_code CHECK (btrim(source_code) <> ''),
    CONSTRAINT ck_doms_inventory_source_type CHECK (source_type IN (
        'WMS','ERP','STORE','SUPPLIER','DROPSHIP','MARKETPLACE','VIRTUAL','MANUAL'
    )),
    CONSTRAINT ck_doms_inventory_source_status CHECK (status IN (
        'ACTIVE','DEGRADED','STALE','SUSPENDED','CLOSED'
    )),
    CONSTRAINT ck_doms_inventory_source_values CHECK (
        source_priority >= 0 AND stale_after_seconds > 0
    ),
    CONSTRAINT ck_doms_inventory_source_config CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(source_config)
    )
);

COMMENT ON COLUMN doms.inventory_sources.secret_reference IS
    'Opaque secret-manager reference only; WMS, ERP, marketplace, and supplier credentials are prohibited in DOMS.';

CREATE TABLE IF NOT EXISTS doms.inventory_measures (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    measure_code varchar(60) NOT NULL,
    measure_name varchar(150) NOT NULL,
    position_bucket varchar(30) NOT NULL,
    measure_category varchar(20) NOT NULL,
    atp_effect smallint NOT NULL DEFAULT 0,
    source_authoritative boolean NOT NULL DEFAULT true,
    system_managed boolean NOT NULL DEFAULT false,
    is_active boolean NOT NULL DEFAULT true,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, measure_code),
    CONSTRAINT ck_doms_inventory_measure_bucket CHECK (position_bucket IN (
        'ON_HAND','INBOUND','UNAVAILABLE','SAFETY_STOCK','OTHER_DEMAND','ATP','RESERVED','ALLOCATED'
    )),
    CONSTRAINT ck_doms_inventory_measure_category CHECK (
        measure_category IN ('SUPPLY','DEMAND','CONTROL','PROJECTION')
    ),
    CONSTRAINT ck_doms_inventory_measure_effect CHECK (atp_effect BETWEEN -1 AND 1),
    CONSTRAINT ck_doms_inventory_measure_metadata CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(metadata)
    )
);

CREATE TABLE IF NOT EXISTS doms.inventory_positions (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    inventory_source_id uuid NOT NULL,
    fulfillment_node_id uuid NOT NULL,
    item_id uuid NOT NULL,
    uom_code varchar(20) NOT NULL REFERENCES doms.units_of_measure(uom_code),
    source_position_key varchar(300),
    on_hand_quantity numeric(24,8) NOT NULL DEFAULT 0,
    inbound_quantity numeric(24,8) NOT NULL DEFAULT 0,
    unavailable_quantity numeric(24,8) NOT NULL DEFAULT 0,
    safety_stock_quantity numeric(24,8) NOT NULL DEFAULT 0,
    other_demand_quantity numeric(24,8) NOT NULL DEFAULT 0,
    atp_quantity numeric(24,8) NOT NULL DEFAULT 0,
    reserved_quantity numeric(24,8) NOT NULL DEFAULT 0,
    allocated_quantity numeric(24,8) NOT NULL DEFAULT 0,
    position_status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    source_version varchar(150),
    source_updated_at timestamptz,
    freshness_expires_at timestamptz,
    last_reconciled_at timestamptz,
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, inventory_source_id, fulfillment_node_id, item_id),
    CONSTRAINT fk_doms_inventory_position_source
        FOREIGN KEY (tenant_id, inventory_source_id)
        REFERENCES doms.inventory_sources(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_inventory_position_node
        FOREIGN KEY (tenant_id, fulfillment_node_id)
        REFERENCES doms.fulfillment_nodes(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_inventory_position_item
        FOREIGN KEY (tenant_id, item_id)
        REFERENCES doms.items(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_inventory_position_quantities CHECK (
        on_hand_quantity >= 0 AND inbound_quantity >= 0 AND unavailable_quantity >= 0 AND
        safety_stock_quantity >= 0 AND other_demand_quantity >= 0 AND atp_quantity >= 0 AND
        reserved_quantity >= 0 AND allocated_quantity >= 0 AND reserved_quantity <= atp_quantity
    ),
    CONSTRAINT ck_doms_inventory_position_status CHECK (position_status IN (
        'ACTIVE','STALE','FROZEN','SUSPENDED','CLOSED'
    )),
    CONSTRAINT ck_doms_inventory_position_dates CHECK (
        freshness_expires_at IS NULL OR source_updated_at IS NULL OR
        freshness_expires_at > source_updated_at
    ),
    CONSTRAINT ck_doms_inventory_position_attributes CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(attributes)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_inventory_position_source_key
    ON doms.inventory_positions (tenant_id, inventory_source_id, source_position_key)
    WHERE source_position_key IS NOT NULL;

CREATE TABLE IF NOT EXISTS doms.inventory_position_events (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    inventory_position_id uuid NOT NULL,
    inventory_measure_id uuid,
    event_type varchar(40) NOT NULL,
    position_bucket varchar(30) NOT NULL,
    quantity_before numeric(24,8) NOT NULL,
    quantity_delta numeric(24,8) NOT NULL,
    quantity_after numeric(24,8) NOT NULL,
    source_event_id varchar(300),
    source_version varchar(150),
    idempotency_key varchar(300),
    actor_user_id uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    correlation_id varchar(100),
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    occurred_at timestamptz NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fk_doms_inventory_event_position
        FOREIGN KEY (tenant_id, inventory_position_id)
        REFERENCES doms.inventory_positions(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_inventory_event_measure
        FOREIGN KEY (tenant_id, inventory_measure_id)
        REFERENCES doms.inventory_measures(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_inventory_event_type CHECK (event_type IN (
        'SOURCE_SNAPSHOT','SOURCE_DELTA','SUPPLY_CHANGED','DEMAND_CHANGED','ATP_RECALCULATED',
        'RESERVATION_CHANGED','ALLOCATION_CHANGED','RECONCILED','CORRECTION'
    )),
    CONSTRAINT ck_doms_inventory_event_bucket CHECK (position_bucket IN (
        'ON_HAND','INBOUND','UNAVAILABLE','SAFETY_STOCK','OTHER_DEMAND','ATP','RESERVED','ALLOCATED'
    )),
    CONSTRAINT ck_doms_inventory_event_math CHECK (
        quantity_before >= 0 AND quantity_after >= 0 AND
        abs(quantity_after - (quantity_before + quantity_delta)) <= 0.00000001
    ),
    CONSTRAINT ck_doms_inventory_event_time CHECK (recorded_at >= occurred_at),
    CONSTRAINT ck_doms_inventory_event_metadata CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(metadata)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_inventory_event_idempotency
    ON doms.inventory_position_events (tenant_id, inventory_position_id, idempotency_key)
    WHERE idempotency_key IS NOT NULL;

CREATE TABLE IF NOT EXISTS doms.inventory_supply (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    inventory_position_id uuid NOT NULL,
    supply_no varchar(120) NOT NULL,
    supply_type varchar(30) NOT NULL,
    source_document_type varchar(60),
    source_document_id varchar(300),
    quantity numeric(24,8) NOT NULL,
    consumed_quantity numeric(24,8) NOT NULL DEFAULT 0,
    cancelled_quantity numeric(24,8) NOT NULL DEFAULT 0,
    available_from timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz,
    supply_status varchar(20) NOT NULL DEFAULT 'EXPECTED',
    confidence_percent numeric(7,4) NOT NULL DEFAULT 100,
    idempotency_key varchar(200) NOT NULL,
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, inventory_position_id, supply_no),
    UNIQUE (tenant_id, inventory_position_id, idempotency_key),
    CONSTRAINT fk_doms_inventory_supply_position
        FOREIGN KEY (tenant_id, inventory_position_id)
        REFERENCES doms.inventory_positions(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_inventory_supply_type CHECK (supply_type IN (
        'ON_HAND','PURCHASE_ORDER','TRANSFER','RETURN','PRODUCTION','DROPSHIP','ADJUSTMENT','OTHER'
    )),
    CONSTRAINT ck_doms_inventory_supply_status CHECK (supply_status IN (
        'EXPECTED','CONFIRMED','AVAILABLE','PARTIALLY_CONSUMED','CONSUMED','CANCELLED','EXPIRED'
    )),
    CONSTRAINT ck_doms_inventory_supply_qty CHECK (
        quantity > 0 AND consumed_quantity >= 0 AND cancelled_quantity >= 0 AND
        consumed_quantity + cancelled_quantity <= quantity
    ),
    CONSTRAINT ck_doms_inventory_supply_values CHECK (
        confidence_percent BETWEEN 0 AND 100 AND btrim(idempotency_key) <> ''
    ),
    CONSTRAINT ck_doms_inventory_supply_dates CHECK (
        expires_at IS NULL OR expires_at > available_from
    ),
    CONSTRAINT ck_doms_inventory_supply_attributes CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(attributes)
    )
);

CREATE TABLE IF NOT EXISTS doms.inventory_demand (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    inventory_position_id uuid NOT NULL,
    sales_order_line_id uuid,
    demand_no varchar(120) NOT NULL,
    demand_type varchar(30) NOT NULL,
    source_document_type varchar(60),
    source_document_id varchar(300),
    quantity numeric(24,8) NOT NULL,
    fulfilled_quantity numeric(24,8) NOT NULL DEFAULT 0,
    cancelled_quantity numeric(24,8) NOT NULL DEFAULT 0,
    required_at timestamptz,
    priority integer NOT NULL DEFAULT 100,
    demand_status varchar(20) NOT NULL DEFAULT 'OPEN',
    idempotency_key varchar(200) NOT NULL,
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, inventory_position_id, demand_no),
    UNIQUE (tenant_id, inventory_position_id, idempotency_key),
    CONSTRAINT fk_doms_inventory_demand_position
        FOREIGN KEY (tenant_id, inventory_position_id)
        REFERENCES doms.inventory_positions(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_inventory_demand_order_line
        FOREIGN KEY (tenant_id, sales_order_line_id)
        REFERENCES doms.sales_order_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_inventory_demand_type CHECK (demand_type IN (
        'ORDER','FORECAST','TRANSFER','SAFETY_STOCK','HOLD','ALLOCATION','OTHER'
    )),
    CONSTRAINT ck_doms_inventory_demand_status CHECK (demand_status IN (
        'OPEN','PARTIALLY_FULFILLED','FULFILLED','CANCELLED','EXPIRED'
    )),
    CONSTRAINT ck_doms_inventory_demand_qty CHECK (
        quantity > 0 AND fulfilled_quantity >= 0 AND cancelled_quantity >= 0 AND
        fulfilled_quantity + cancelled_quantity <= quantity
    ),
    CONSTRAINT ck_doms_inventory_demand_values CHECK (
        priority >= 0 AND btrim(idempotency_key) <> ''
    ),
    CONSTRAINT ck_doms_inventory_demand_attributes CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(attributes)
    )
);

-- -----------------------------------------------------------------------------
-- ATP checks and sourcing
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS doms.atp_check_requests (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    request_no varchar(100) NOT NULL,
    sales_order_id uuid,
    customer_id uuid,
    sales_channel_id uuid,
    request_status varchar(20) NOT NULL DEFAULT 'PENDING',
    request_scope varchar(20) NOT NULL DEFAULT 'ORDER',
    requested_at timestamptz NOT NULL DEFAULT now(),
    horizon_end_at timestamptz,
    completed_at timestamptz,
    idempotency_key varchar(200) NOT NULL,
    correlation_id varchar(100),
    constraints_data jsonb NOT NULL DEFAULT '{}'::jsonb,
    requested_by uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, request_no),
    UNIQUE (tenant_id, idempotency_key),
    CONSTRAINT fk_doms_atp_request_order
        FOREIGN KEY (tenant_id, sales_order_id)
        REFERENCES doms.sales_orders(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_atp_request_customer
        FOREIGN KEY (tenant_id, customer_id)
        REFERENCES doms.customers(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_atp_request_channel
        FOREIGN KEY (tenant_id, sales_channel_id)
        REFERENCES doms.sales_channels(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_atp_request_no CHECK (btrim(request_no) <> ''),
    CONSTRAINT ck_doms_atp_request_key CHECK (btrim(idempotency_key) <> ''),
    CONSTRAINT ck_doms_atp_request_status CHECK (request_status IN (
        'PENDING','RUNNING','COMPLETED','PARTIAL','FAILED','EXPIRED','CANCELLED'
    )),
    CONSTRAINT ck_doms_atp_request_scope CHECK (request_scope IN (
        'ORDER','ORDER_LINE','CART','QUOTE','MANUAL'
    )),
    CONSTRAINT ck_doms_atp_request_dates CHECK (
        (horizon_end_at IS NULL OR horizon_end_at > requested_at) AND
        (completed_at IS NULL OR completed_at >= requested_at)
    ),
    CONSTRAINT ck_doms_atp_request_context CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(constraints_data)
    )
);

CREATE TABLE IF NOT EXISTS doms.atp_check_request_lines (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    atp_check_request_id uuid NOT NULL,
    line_no integer NOT NULL,
    sales_order_line_id uuid,
    item_id uuid NOT NULL,
    requested_fulfillment_node_id uuid,
    requested_quantity numeric(24,8) NOT NULL,
    uom_code varchar(20) NOT NULL REFERENCES doms.units_of_measure(uom_code),
    required_ship_at timestamptz,
    required_delivery_at timestamptz,
    allow_split boolean NOT NULL DEFAULT true,
    allow_substitution boolean NOT NULL DEFAULT false,
    allow_backorder boolean NOT NULL DEFAULT false,
    allow_preorder boolean NOT NULL DEFAULT false,
    priority integer NOT NULL DEFAULT 100,
    constraints_data jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, atp_check_request_id, line_no),
    CONSTRAINT fk_doms_atp_line_request
        FOREIGN KEY (tenant_id, atp_check_request_id)
        REFERENCES doms.atp_check_requests(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_atp_line_order_line
        FOREIGN KEY (tenant_id, sales_order_line_id)
        REFERENCES doms.sales_order_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_atp_line_item
        FOREIGN KEY (tenant_id, item_id)
        REFERENCES doms.items(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_atp_line_requested_node
        FOREIGN KEY (tenant_id, requested_fulfillment_node_id)
        REFERENCES doms.fulfillment_nodes(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_atp_line_values CHECK (
        line_no > 0 AND requested_quantity > 0 AND priority >= 0
    ),
    CONSTRAINT ck_doms_atp_line_dates CHECK (
        required_delivery_at IS NULL OR required_ship_at IS NULL OR
        required_delivery_at >= required_ship_at
    ),
    CONSTRAINT ck_doms_atp_line_context CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(constraints_data)
    )
);

CREATE TABLE IF NOT EXISTS doms.atp_check_results (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    atp_check_request_line_id uuid NOT NULL,
    inventory_position_id uuid,
    inventory_source_id uuid NOT NULL,
    fulfillment_node_id uuid NOT NULL,
    item_id uuid NOT NULL,
    result_rank integer NOT NULL,
    on_hand_quantity numeric(24,8) NOT NULL DEFAULT 0,
    atp_quantity numeric(24,8) NOT NULL DEFAULT 0,
    active_reserved_quantity numeric(24,8) NOT NULL DEFAULT 0,
    reservable_quantity numeric(24,8) NOT NULL DEFAULT 0,
    promised_quantity numeric(24,8) NOT NULL DEFAULT 0,
    promise_ship_at timestamptz,
    promise_delivery_at timestamptz,
    freshness_status varchar(20) NOT NULL DEFAULT 'CURRENT',
    selected boolean NOT NULL DEFAULT false,
    explanation jsonb NOT NULL DEFAULT '{}'::jsonb,
    calculated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, atp_check_request_line_id, result_rank),
    CONSTRAINT fk_doms_atp_result_line
        FOREIGN KEY (tenant_id, atp_check_request_line_id)
        REFERENCES doms.atp_check_request_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_atp_result_position
        FOREIGN KEY (tenant_id, inventory_position_id)
        REFERENCES doms.inventory_positions(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_atp_result_source
        FOREIGN KEY (tenant_id, inventory_source_id)
        REFERENCES doms.inventory_sources(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_atp_result_node
        FOREIGN KEY (tenant_id, fulfillment_node_id)
        REFERENCES doms.fulfillment_nodes(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_atp_result_item
        FOREIGN KEY (tenant_id, item_id)
        REFERENCES doms.items(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_atp_result_values CHECK (
        result_rank > 0 AND on_hand_quantity >= 0 AND atp_quantity >= 0 AND
        active_reserved_quantity >= 0 AND reservable_quantity >= 0 AND promised_quantity >= 0 AND
        active_reserved_quantity <= atp_quantity AND
        reservable_quantity <= atp_quantity - active_reserved_quantity AND
        promised_quantity <= reservable_quantity
    ),
    CONSTRAINT ck_doms_atp_result_freshness CHECK (
        freshness_status IN ('CURRENT','NEAR_STALE','STALE','UNKNOWN')
    ),
    CONSTRAINT ck_doms_atp_result_dates CHECK (
        promise_delivery_at IS NULL OR promise_ship_at IS NULL OR
        promise_delivery_at >= promise_ship_at
    ),
    CONSTRAINT ck_doms_atp_result_explanation CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(explanation)
    )
);

CREATE TABLE IF NOT EXISTS doms.sourcing_policies (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    policy_code varchar(80) NOT NULL,
    policy_name varchar(200) NOT NULL,
    version_no integer NOT NULL DEFAULT 1,
    sales_channel_id uuid,
    customer_id uuid,
    policy_status varchar(20) NOT NULL DEFAULT 'DRAFT',
    effective_from timestamptz,
    effective_to timestamptz,
    allow_split boolean NOT NULL DEFAULT true,
    allow_substitution boolean NOT NULL DEFAULT false,
    allow_backorder boolean NOT NULL DEFAULT false,
    allow_preorder boolean NOT NULL DEFAULT false,
    applies_to jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, policy_code, version_no),
    CONSTRAINT fk_doms_sourcing_policy_channel
        FOREIGN KEY (tenant_id, sales_channel_id)
        REFERENCES doms.sales_channels(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_sourcing_policy_customer
        FOREIGN KEY (tenant_id, customer_id)
        REFERENCES doms.customers(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_sourcing_policy_code CHECK (btrim(policy_code) <> ''),
    CONSTRAINT ck_doms_sourcing_policy_version CHECK (version_no > 0),
    CONSTRAINT ck_doms_sourcing_policy_status CHECK (
        policy_status IN ('DRAFT','ACTIVE','SUSPENDED','SUPERSEDED','RETIRED')
    ),
    CONSTRAINT ck_doms_sourcing_policy_dates CHECK (
        effective_to IS NULL OR effective_from IS NULL OR effective_to > effective_from
    ),
    CONSTRAINT ck_doms_sourcing_policy_json CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(applies_to)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_sourcing_policy_active
    ON doms.sourcing_policies (
        tenant_id, policy_code,
        COALESCE(sales_channel_id, '00000000-0000-0000-0000-000000000000'::uuid),
        COALESCE(customer_id, '00000000-0000-0000-0000-000000000000'::uuid)
    ) WHERE policy_status = 'ACTIVE';

CREATE TABLE IF NOT EXISTS doms.sourcing_policy_rules (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    sourcing_policy_id uuid NOT NULL,
    rule_code varchar(80) NOT NULL,
    rule_name varchar(200) NOT NULL,
    sequence_no integer NOT NULL,
    rule_type varchar(30) NOT NULL,
    fulfillment_node_id uuid,
    inventory_source_id uuid,
    condition_config jsonb NOT NULL DEFAULT '{}'::jsonb,
    action_config jsonb NOT NULL DEFAULT '{}'::jsonb,
    score_adjustment numeric(16,6) NOT NULL DEFAULT 0,
    stop_processing boolean NOT NULL DEFAULT false,
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, sourcing_policy_id, rule_code),
    UNIQUE (tenant_id, sourcing_policy_id, sequence_no),
    CONSTRAINT fk_doms_sourcing_rule_policy
        FOREIGN KEY (tenant_id, sourcing_policy_id)
        REFERENCES doms.sourcing_policies(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_sourcing_rule_node
        FOREIGN KEY (tenant_id, fulfillment_node_id)
        REFERENCES doms.fulfillment_nodes(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_sourcing_rule_source
        FOREIGN KEY (tenant_id, inventory_source_id)
        REFERENCES doms.inventory_sources(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_sourcing_rule_values CHECK (
        btrim(rule_code) <> '' AND sequence_no > 0
    ),
    CONSTRAINT ck_doms_sourcing_rule_type CHECK (rule_type IN (
        'INCLUDE','EXCLUDE','PRIORITIZE','CAP_QUANTITY','DISTANCE','COST','CAPACITY',
        'SERVICE_LEVEL','SPLIT','SUBSTITUTION','BACKORDER','PREORDER','CUSTOM'
    )),
    CONSTRAINT ck_doms_sourcing_rule_json CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(condition_config) AND
        NOT doms.jsonb_contains_forbidden_secret_key(action_config)
    )
);

CREATE TABLE IF NOT EXISTS doms.sourcing_requests (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    request_no varchar(100) NOT NULL,
    sales_order_id uuid NOT NULL,
    sales_order_line_id uuid NOT NULL,
    atp_check_request_line_id uuid,
    sourcing_policy_id uuid NOT NULL,
    item_id uuid NOT NULL,
    requested_quantity numeric(24,8) NOT NULL,
    uom_code varchar(20) NOT NULL REFERENCES doms.units_of_measure(uom_code),
    required_ship_at timestamptz,
    required_delivery_at timestamptz,
    request_status varchar(20) NOT NULL DEFAULT 'PENDING',
    idempotency_key varchar(200) NOT NULL,
    request_context jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, request_no),
    UNIQUE (tenant_id, sales_order_line_id, idempotency_key),
    CONSTRAINT fk_doms_sourcing_request_order
        FOREIGN KEY (tenant_id, sales_order_id)
        REFERENCES doms.sales_orders(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_sourcing_request_order_line
        FOREIGN KEY (tenant_id, sales_order_line_id)
        REFERENCES doms.sales_order_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_sourcing_request_atp_line
        FOREIGN KEY (tenant_id, atp_check_request_line_id)
        REFERENCES doms.atp_check_request_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_sourcing_request_policy
        FOREIGN KEY (tenant_id, sourcing_policy_id)
        REFERENCES doms.sourcing_policies(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_sourcing_request_item
        FOREIGN KEY (tenant_id, item_id)
        REFERENCES doms.items(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_sourcing_request_values CHECK (
        btrim(request_no) <> '' AND btrim(idempotency_key) <> '' AND requested_quantity > 0
    ),
    CONSTRAINT ck_doms_sourcing_request_status CHECK (request_status IN (
        'PENDING','EVALUATING','DECIDED','PARTIAL','FAILED','CANCELLED','EXPIRED'
    )),
    CONSTRAINT ck_doms_sourcing_request_dates CHECK (
        required_delivery_at IS NULL OR required_ship_at IS NULL OR
        required_delivery_at >= required_ship_at
    ),
    CONSTRAINT ck_doms_sourcing_request_context CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(request_context)
    )
);

CREATE TABLE IF NOT EXISTS doms.sourcing_candidates (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    sourcing_request_id uuid NOT NULL,
    inventory_position_id uuid,
    inventory_source_id uuid NOT NULL,
    fulfillment_node_id uuid NOT NULL,
    item_id uuid NOT NULL,
    substitution_candidate_id uuid,
    candidate_rank integer NOT NULL,
    candidate_status varchar(20) NOT NULL DEFAULT 'ELIGIBLE',
    available_quantity numeric(24,8) NOT NULL DEFAULT 0,
    reservable_quantity numeric(24,8) NOT NULL DEFAULT 0,
    proposed_quantity numeric(24,8) NOT NULL DEFAULT 0,
    score numeric(20,8) NOT NULL DEFAULT 0,
    unit_fulfillment_cost numeric(24,6),
    currency_code char(3) REFERENCES doms.currencies(currency_code),
    promise_ship_at timestamptz,
    promise_delivery_at timestamptz,
    rejection_reason varchar(300),
    score_components jsonb NOT NULL DEFAULT '{}'::jsonb,
    evaluated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, sourcing_request_id, candidate_rank),
    CONSTRAINT fk_doms_sourcing_candidate_request
        FOREIGN KEY (tenant_id, sourcing_request_id)
        REFERENCES doms.sourcing_requests(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_sourcing_candidate_position
        FOREIGN KEY (tenant_id, inventory_position_id)
        REFERENCES doms.inventory_positions(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_sourcing_candidate_source
        FOREIGN KEY (tenant_id, inventory_source_id)
        REFERENCES doms.inventory_sources(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_sourcing_candidate_node
        FOREIGN KEY (tenant_id, fulfillment_node_id)
        REFERENCES doms.fulfillment_nodes(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_sourcing_candidate_item
        FOREIGN KEY (tenant_id, item_id)
        REFERENCES doms.items(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_sourcing_candidate_values CHECK (
        candidate_rank > 0 AND available_quantity >= 0 AND reservable_quantity >= 0 AND
        proposed_quantity >= 0 AND proposed_quantity <= reservable_quantity AND
        reservable_quantity <= available_quantity AND
        (unit_fulfillment_cost IS NULL OR unit_fulfillment_cost >= 0)
    ),
    CONSTRAINT ck_doms_sourcing_candidate_status CHECK (candidate_status IN (
        'ELIGIBLE','SELECTED','REJECTED','STALE','UNAVAILABLE','EXPIRED'
    )),
    CONSTRAINT ck_doms_sourcing_candidate_dates CHECK (
        promise_delivery_at IS NULL OR promise_ship_at IS NULL OR
        promise_delivery_at >= promise_ship_at
    ),
    CONSTRAINT ck_doms_sourcing_candidate_score CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(score_components)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_sourcing_candidate_request_id
    ON doms.sourcing_candidates (tenant_id, sourcing_request_id, id);

-- substitution_candidate_id is linked after the substitution tables are defined.

CREATE TABLE IF NOT EXISTS doms.sourcing_decisions (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    sourcing_request_id uuid NOT NULL,
    sourcing_candidate_id uuid NOT NULL,
    decision_sequence integer NOT NULL,
    decision_type varchar(20) NOT NULL DEFAULT 'SELECTED',
    decided_quantity numeric(24,8) NOT NULL,
    decision_reason varchar(300),
    override_approved_by uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    override_approved_at timestamptz,
    override_reason text,
    decision_data jsonb NOT NULL DEFAULT '{}'::jsonb,
    decided_by uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    decided_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, sourcing_request_id, decision_sequence),
    UNIQUE (tenant_id, sourcing_request_id, sourcing_candidate_id),
    CONSTRAINT fk_doms_sourcing_decision_request
        FOREIGN KEY (tenant_id, sourcing_request_id)
        REFERENCES doms.sourcing_requests(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_sourcing_decision_candidate
        FOREIGN KEY (tenant_id, sourcing_request_id, sourcing_candidate_id)
        REFERENCES doms.sourcing_candidates(tenant_id, sourcing_request_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_sourcing_decision_values CHECK (
        decision_sequence > 0 AND decided_quantity > 0
    ),
    CONSTRAINT ck_doms_sourcing_decision_type CHECK (
        decision_type IN ('SELECTED','REJECTED','OVERRIDDEN')
    ),
    CONSTRAINT ck_doms_sourcing_decision_override CHECK (
        (decision_type = 'OVERRIDDEN' AND override_approved_by IS NOT NULL AND
            override_approved_at IS NOT NULL AND btrim(COALESCE(override_reason, '')) <> '') OR
        (decision_type <> 'OVERRIDDEN' AND override_approved_by IS NULL AND
            override_approved_at IS NULL AND override_reason IS NULL)
    ),
    CONSTRAINT ck_doms_sourcing_decision_data CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(decision_data)
    )
);

-- -----------------------------------------------------------------------------
-- Fulfillment plans and node/source splits
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS doms.fulfillment_plans (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    plan_no varchar(100) NOT NULL,
    sales_order_id uuid NOT NULL,
    plan_revision integer NOT NULL DEFAULT 1,
    plan_status varchar(30) NOT NULL DEFAULT 'DRAFT',
    sourcing_policy_id uuid,
    journey_run_id uuid,
    idempotency_key varchar(200) NOT NULL,
    planned_at timestamptz,
    confirmed_at timestamptz,
    superseded_at timestamptz,
    expires_at timestamptz,
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_by uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, plan_no, plan_revision),
    UNIQUE (tenant_id, sales_order_id, idempotency_key),
    CONSTRAINT fk_doms_fulfillment_plan_order
        FOREIGN KEY (tenant_id, sales_order_id)
        REFERENCES doms.sales_orders(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_fulfillment_plan_policy
        FOREIGN KEY (tenant_id, sourcing_policy_id)
        REFERENCES doms.sourcing_policies(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_fulfillment_plan_journey
        FOREIGN KEY (tenant_id, journey_run_id)
        REFERENCES doms.order_journey_runs(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_fulfillment_plan_values CHECK (
        btrim(plan_no) <> '' AND btrim(idempotency_key) <> '' AND plan_revision > 0
    ),
    CONSTRAINT ck_doms_fulfillment_plan_status CHECK (plan_status IN (
        'DRAFT','PLANNING','READY','CONFIRMED','PARTIALLY_RESERVED','RESERVED',
        'RELEASED','SUPERSEDED','FAILED','CANCELLED','EXPIRED'
    )),
    CONSTRAINT ck_doms_fulfillment_plan_dates CHECK (
        (confirmed_at IS NULL OR confirmed_at >= COALESCE(planned_at, created_at)) AND
        (superseded_at IS NULL OR superseded_at >= created_at) AND
        (expires_at IS NULL OR expires_at > created_at)
    ),
    CONSTRAINT ck_doms_fulfillment_plan_attributes CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(attributes)
    )
);

CREATE TABLE IF NOT EXISTS doms.fulfillment_plan_lines (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    fulfillment_plan_id uuid NOT NULL,
    line_no integer NOT NULL,
    sales_order_line_id uuid NOT NULL,
    item_id uuid NOT NULL,
    requested_quantity numeric(24,8) NOT NULL,
    planned_quantity numeric(24,8) NOT NULL DEFAULT 0,
    backorder_quantity numeric(24,8) NOT NULL DEFAULT 0,
    preorder_quantity numeric(24,8) NOT NULL DEFAULT 0,
    uom_code varchar(20) NOT NULL REFERENCES doms.units_of_measure(uom_code),
    line_status varchar(20) NOT NULL DEFAULT 'PENDING',
    required_ship_at timestamptz,
    required_delivery_at timestamptz,
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, fulfillment_plan_id, line_no),
    UNIQUE (tenant_id, fulfillment_plan_id, sales_order_line_id),
    CONSTRAINT fk_doms_fulfillment_plan_line_plan
        FOREIGN KEY (tenant_id, fulfillment_plan_id)
        REFERENCES doms.fulfillment_plans(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_fulfillment_plan_line_order_line
        FOREIGN KEY (tenant_id, sales_order_line_id)
        REFERENCES doms.sales_order_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_fulfillment_plan_line_item
        FOREIGN KEY (tenant_id, item_id)
        REFERENCES doms.items(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_fulfillment_plan_line_values CHECK (
        line_no > 0 AND requested_quantity > 0 AND planned_quantity >= 0 AND
        backorder_quantity >= 0 AND preorder_quantity >= 0 AND
        planned_quantity + backorder_quantity + preorder_quantity <= requested_quantity
    ),
    CONSTRAINT ck_doms_fulfillment_plan_line_status CHECK (line_status IN (
        'PENDING','PLANNED','PARTIAL','UNSOURCED','RESERVED','ALLOCATED','RELEASED',
        'FAILED','CANCELLED'
    )),
    CONSTRAINT ck_doms_fulfillment_plan_line_dates CHECK (
        required_delivery_at IS NULL OR required_ship_at IS NULL OR
        required_delivery_at >= required_ship_at
    ),
    CONSTRAINT ck_doms_fulfillment_plan_line_attributes CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(attributes)
    )
);

CREATE TABLE IF NOT EXISTS doms.fulfillment_plan_source_splits (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    fulfillment_plan_line_id uuid NOT NULL,
    split_no integer NOT NULL,
    sourcing_decision_id uuid,
    sourcing_candidate_id uuid,
    inventory_position_id uuid NOT NULL,
    inventory_source_id uuid NOT NULL,
    fulfillment_node_id uuid NOT NULL,
    item_id uuid NOT NULL,
    split_quantity numeric(24,8) NOT NULL,
    uom_code varchar(20) NOT NULL REFERENCES doms.units_of_measure(uom_code),
    promise_ship_at timestamptz,
    promise_delivery_at timestamptz,
    split_status varchar(20) NOT NULL DEFAULT 'PLANNED',
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, fulfillment_plan_line_id, split_no),
    CONSTRAINT fk_doms_fulfillment_split_plan_line
        FOREIGN KEY (tenant_id, fulfillment_plan_line_id)
        REFERENCES doms.fulfillment_plan_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_fulfillment_split_decision
        FOREIGN KEY (tenant_id, sourcing_decision_id)
        REFERENCES doms.sourcing_decisions(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_fulfillment_split_candidate
        FOREIGN KEY (tenant_id, sourcing_candidate_id)
        REFERENCES doms.sourcing_candidates(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_fulfillment_split_position
        FOREIGN KEY (tenant_id, inventory_position_id)
        REFERENCES doms.inventory_positions(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_fulfillment_split_source
        FOREIGN KEY (tenant_id, inventory_source_id)
        REFERENCES doms.inventory_sources(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_fulfillment_split_node
        FOREIGN KEY (tenant_id, fulfillment_node_id)
        REFERENCES doms.fulfillment_nodes(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_fulfillment_split_item
        FOREIGN KEY (tenant_id, item_id)
        REFERENCES doms.items(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_fulfillment_split_values CHECK (
        split_no > 0 AND split_quantity > 0
    ),
    CONSTRAINT ck_doms_fulfillment_split_status CHECK (split_status IN (
        'PLANNED','RESERVATION_PENDING','RESERVED','ALLOCATED','RELEASED','FAILED','CANCELLED'
    )),
    CONSTRAINT ck_doms_fulfillment_split_dates CHECK (
        promise_delivery_at IS NULL OR promise_ship_at IS NULL OR
        promise_delivery_at >= promise_ship_at
    ),
    CONSTRAINT ck_doms_fulfillment_split_attributes CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(attributes)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_fulfillment_split_decision
    ON doms.fulfillment_plan_source_splits (tenant_id, sourcing_decision_id)
    WHERE sourcing_decision_id IS NOT NULL;

-- -----------------------------------------------------------------------------
-- Reservation requests and inventory reservations
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS doms.reservation_requests (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    request_no varchar(100) NOT NULL,
    sales_order_id uuid NOT NULL,
    fulfillment_plan_id uuid,
    request_status varchar(20) NOT NULL DEFAULT 'PENDING',
    requested_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL,
    completed_at timestamptz,
    idempotency_key varchar(200) NOT NULL,
    correlation_id varchar(100),
    request_data jsonb NOT NULL DEFAULT '{}'::jsonb,
    requested_by uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, request_no),
    UNIQUE (tenant_id, sales_order_id, idempotency_key),
    CONSTRAINT fk_doms_reservation_request_order
        FOREIGN KEY (tenant_id, sales_order_id)
        REFERENCES doms.sales_orders(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_reservation_request_plan
        FOREIGN KEY (tenant_id, fulfillment_plan_id)
        REFERENCES doms.fulfillment_plans(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_reservation_request_values CHECK (
        btrim(request_no) <> '' AND btrim(idempotency_key) <> ''
    ),
    CONSTRAINT ck_doms_reservation_request_status CHECK (request_status IN (
        'PENDING','PROCESSING','PARTIAL','COMPLETED','FAILED','EXPIRED','CANCELLED'
    )),
    CONSTRAINT ck_doms_reservation_request_dates CHECK (
        expires_at > requested_at AND
        (completed_at IS NULL OR completed_at >= requested_at)
    ),
    CONSTRAINT ck_doms_reservation_request_data CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(request_data)
    )
);

CREATE TABLE IF NOT EXISTS doms.reservation_request_lines (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    reservation_request_id uuid NOT NULL,
    line_no integer NOT NULL,
    sales_order_line_id uuid NOT NULL,
    fulfillment_plan_source_split_id uuid,
    inventory_position_id uuid NOT NULL,
    item_id uuid NOT NULL,
    requested_quantity numeric(24,8) NOT NULL,
    uom_code varchar(20) NOT NULL REFERENCES doms.units_of_measure(uom_code),
    line_status varchar(20) NOT NULL DEFAULT 'PENDING',
    failure_code varchar(100),
    failure_detail_masked text,
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, reservation_request_id, line_no),
    CONSTRAINT fk_doms_reservation_request_line_request
        FOREIGN KEY (tenant_id, reservation_request_id)
        REFERENCES doms.reservation_requests(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_reservation_request_line_order_line
        FOREIGN KEY (tenant_id, sales_order_line_id)
        REFERENCES doms.sales_order_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_reservation_request_line_split
        FOREIGN KEY (tenant_id, fulfillment_plan_source_split_id)
        REFERENCES doms.fulfillment_plan_source_splits(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_reservation_request_line_position
        FOREIGN KEY (tenant_id, inventory_position_id)
        REFERENCES doms.inventory_positions(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_reservation_request_line_item
        FOREIGN KEY (tenant_id, item_id)
        REFERENCES doms.items(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_reservation_request_line_values CHECK (
        line_no > 0 AND requested_quantity > 0
    ),
    CONSTRAINT ck_doms_reservation_request_line_status CHECK (line_status IN (
        'PENDING','RESERVED','PARTIAL','FAILED','EXPIRED','CANCELLED'
    )),
    CONSTRAINT ck_doms_reservation_request_line_attributes CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(attributes)
    )
);

CREATE TABLE IF NOT EXISTS doms.inventory_reservations (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    reservation_no varchar(100) NOT NULL,
    reservation_request_id uuid NOT NULL,
    sales_order_id uuid NOT NULL,
    fulfillment_plan_id uuid,
    reservation_status varchar(30) NOT NULL DEFAULT 'PENDING',
    priority integer NOT NULL DEFAULT 100,
    expires_at timestamptz NOT NULL,
    activated_at timestamptz,
    closed_at timestamptz,
    creation_idempotency_key varchar(200) NOT NULL,
    last_operation_key varchar(200),
    correlation_id varchar(100),
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_by uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, reservation_no),
    UNIQUE (tenant_id, reservation_request_id),
    UNIQUE (tenant_id, sales_order_id, creation_idempotency_key),
    CONSTRAINT fk_doms_inventory_reservation_request
        FOREIGN KEY (tenant_id, reservation_request_id)
        REFERENCES doms.reservation_requests(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_inventory_reservation_order
        FOREIGN KEY (tenant_id, sales_order_id)
        REFERENCES doms.sales_orders(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_inventory_reservation_plan
        FOREIGN KEY (tenant_id, fulfillment_plan_id)
        REFERENCES doms.fulfillment_plans(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_inventory_reservation_values CHECK (
        btrim(reservation_no) <> '' AND btrim(creation_idempotency_key) <> '' AND priority >= 0
    ),
    CONSTRAINT ck_doms_inventory_reservation_status CHECK (reservation_status IN (
        'PENDING','ACTIVE','PARTIALLY_CONSUMED','CONSUMED','PARTIALLY_RELEASED',
        'RELEASED','EXPIRED','CANCELLED','FAILED'
    )),
    CONSTRAINT ck_doms_inventory_reservation_dates CHECK (
        expires_at > created_at AND
        (activated_at IS NULL OR activated_at >= created_at) AND
        (closed_at IS NULL OR closed_at >= COALESCE(activated_at, created_at))
    ),
    CONSTRAINT ck_doms_inventory_reservation_activation CHECK (
        reservation_status = 'PENDING' OR activated_at IS NOT NULL OR
        reservation_status IN ('CANCELLED','FAILED')
    ),
    CONSTRAINT ck_doms_inventory_reservation_attributes CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(attributes)
    )
);

CREATE TABLE IF NOT EXISTS doms.inventory_reservation_lines (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    inventory_reservation_id uuid NOT NULL,
    reservation_request_line_id uuid NOT NULL,
    line_no integer NOT NULL,
    sales_order_line_id uuid NOT NULL,
    fulfillment_plan_source_split_id uuid,
    inventory_position_id uuid NOT NULL,
    inventory_source_id uuid NOT NULL,
    fulfillment_node_id uuid NOT NULL,
    item_id uuid NOT NULL,
    requested_quantity numeric(24,8) NOT NULL,
    reserved_quantity numeric(24,8) NOT NULL DEFAULT 0,
    released_quantity numeric(24,8) NOT NULL DEFAULT 0,
    consumed_quantity numeric(24,8) NOT NULL DEFAULT 0,
    uom_code varchar(20) NOT NULL REFERENCES doms.units_of_measure(uom_code),
    reservation_status varchar(30) NOT NULL DEFAULT 'PENDING',
    expires_at timestamptz NOT NULL,
    last_operation_key varchar(200),
    last_actor_user_id uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    last_reason_code varchar(100),
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, inventory_reservation_id, line_no),
    UNIQUE (tenant_id, reservation_request_line_id),
    CONSTRAINT fk_doms_reservation_line_header
        FOREIGN KEY (tenant_id, inventory_reservation_id)
        REFERENCES doms.inventory_reservations(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_reservation_line_request_line
        FOREIGN KEY (tenant_id, reservation_request_line_id)
        REFERENCES doms.reservation_request_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_reservation_line_order_line
        FOREIGN KEY (tenant_id, sales_order_line_id)
        REFERENCES doms.sales_order_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_reservation_line_split
        FOREIGN KEY (tenant_id, fulfillment_plan_source_split_id)
        REFERENCES doms.fulfillment_plan_source_splits(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_reservation_line_position
        FOREIGN KEY (tenant_id, inventory_position_id)
        REFERENCES doms.inventory_positions(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_reservation_line_source
        FOREIGN KEY (tenant_id, inventory_source_id)
        REFERENCES doms.inventory_sources(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_reservation_line_node
        FOREIGN KEY (tenant_id, fulfillment_node_id)
        REFERENCES doms.fulfillment_nodes(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_reservation_line_item
        FOREIGN KEY (tenant_id, item_id)
        REFERENCES doms.items(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_reservation_line_values CHECK (
        line_no > 0 AND requested_quantity > 0 AND reserved_quantity >= 0 AND
        released_quantity >= 0 AND consumed_quantity >= 0 AND
        reserved_quantity <= requested_quantity AND
        released_quantity + consumed_quantity <= reserved_quantity
    ),
    CONSTRAINT ck_doms_reservation_line_status CHECK (reservation_status IN (
        'PENDING','ACTIVE','PARTIALLY_CONSUMED','CONSUMED','PARTIALLY_RELEASED',
        'RELEASED','EXPIRED','CANCELLED','FAILED'
    )),
    CONSTRAINT ck_doms_reservation_line_expiry CHECK (expires_at > created_at),
    CONSTRAINT ck_doms_reservation_line_attributes CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(attributes)
    )
);

CREATE TABLE IF NOT EXISTS doms.inventory_reservation_events (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    inventory_reservation_id uuid NOT NULL,
    inventory_reservation_line_id uuid NOT NULL,
    event_type varchar(30) NOT NULL,
    from_status varchar(30),
    to_status varchar(30) NOT NULL,
    quantity numeric(24,8) NOT NULL DEFAULT 0,
    idempotency_key varchar(200),
    reason_code varchar(100),
    actor_user_id uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fk_doms_reservation_event_header
        FOREIGN KEY (tenant_id, inventory_reservation_id)
        REFERENCES doms.inventory_reservations(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_reservation_event_line
        FOREIGN KEY (tenant_id, inventory_reservation_line_id)
        REFERENCES doms.inventory_reservation_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_reservation_event_type CHECK (event_type IN (
        'REQUESTED','ACTIVATED','CONSUMED','RELEASED','EXPIRED','CANCELLED',
        'FAILED','STATUS_CHANGED'
    )),
    CONSTRAINT ck_doms_reservation_event_qty CHECK (quantity >= 0),
    CONSTRAINT ck_doms_reservation_event_metadata CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(metadata)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_reservation_event_idempotency
    ON doms.inventory_reservation_events (
        tenant_id, inventory_reservation_line_id, event_type, idempotency_key
    ) WHERE idempotency_key IS NOT NULL;

-- -----------------------------------------------------------------------------
-- Fulfillment allocations. An allocation must fit inside its reservation line;
-- exceeding it or omitting a reservation requires explicit override evidence.
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS doms.fulfillment_allocations (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    allocation_no varchar(100) NOT NULL,
    fulfillment_plan_line_id uuid NOT NULL,
    fulfillment_plan_source_split_id uuid NOT NULL,
    sales_order_line_id uuid NOT NULL,
    inventory_reservation_line_id uuid,
    inventory_position_id uuid NOT NULL,
    inventory_source_id uuid NOT NULL,
    fulfillment_node_id uuid NOT NULL,
    item_id uuid NOT NULL,
    allocated_quantity numeric(24,8) NOT NULL,
    released_quantity numeric(24,8) NOT NULL DEFAULT 0,
    consumed_quantity numeric(24,8) NOT NULL DEFAULT 0,
    uom_code varchar(20) NOT NULL REFERENCES doms.units_of_measure(uom_code),
    allocation_status varchar(30) NOT NULL DEFAULT 'ACTIVE',
    override_approved_by uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    override_approved_at timestamptz,
    override_reason text,
    idempotency_key varchar(200) NOT NULL,
    last_operation_key varchar(200),
    last_actor_user_id uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    last_reason_code varchar(100),
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, allocation_no),
    UNIQUE (tenant_id, fulfillment_plan_source_split_id, idempotency_key),
    CONSTRAINT fk_doms_allocation_plan_line
        FOREIGN KEY (tenant_id, fulfillment_plan_line_id)
        REFERENCES doms.fulfillment_plan_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_allocation_split
        FOREIGN KEY (tenant_id, fulfillment_plan_source_split_id)
        REFERENCES doms.fulfillment_plan_source_splits(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_allocation_order_line
        FOREIGN KEY (tenant_id, sales_order_line_id)
        REFERENCES doms.sales_order_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_allocation_reservation_line
        FOREIGN KEY (tenant_id, inventory_reservation_line_id)
        REFERENCES doms.inventory_reservation_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_allocation_position
        FOREIGN KEY (tenant_id, inventory_position_id)
        REFERENCES doms.inventory_positions(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_allocation_source
        FOREIGN KEY (tenant_id, inventory_source_id)
        REFERENCES doms.inventory_sources(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_allocation_node
        FOREIGN KEY (tenant_id, fulfillment_node_id)
        REFERENCES doms.fulfillment_nodes(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_allocation_item
        FOREIGN KEY (tenant_id, item_id)
        REFERENCES doms.items(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_allocation_values CHECK (
        btrim(allocation_no) <> '' AND btrim(idempotency_key) <> '' AND
        allocated_quantity > 0 AND released_quantity >= 0 AND consumed_quantity >= 0 AND
        released_quantity + consumed_quantity <= allocated_quantity
    ),
    CONSTRAINT ck_doms_allocation_status CHECK (allocation_status IN (
        'ACTIVE','PARTIALLY_CONSUMED','CONSUMED','PARTIALLY_RELEASED','RELEASED',
        'CANCELLED','FAILED'
    )),
    CONSTRAINT ck_doms_allocation_override CHECK (
        inventory_reservation_line_id IS NOT NULL OR
        (override_approved_by IS NOT NULL AND override_approved_at IS NOT NULL AND
            btrim(COALESCE(override_reason, '')) <> '')
    ),
    CONSTRAINT ck_doms_allocation_attributes CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(attributes)
    )
);

CREATE TABLE IF NOT EXISTS doms.fulfillment_allocation_events (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    fulfillment_allocation_id uuid NOT NULL,
    event_type varchar(30) NOT NULL,
    from_status varchar(30),
    to_status varchar(30) NOT NULL,
    quantity numeric(24,8) NOT NULL DEFAULT 0,
    idempotency_key varchar(200),
    reason_code varchar(100),
    actor_user_id uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fk_doms_allocation_event
        FOREIGN KEY (tenant_id, fulfillment_allocation_id)
        REFERENCES doms.fulfillment_allocations(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_allocation_event_type CHECK (event_type IN (
        'ALLOCATED','CONSUMED','RELEASED','CANCELLED','FAILED','STATUS_CHANGED'
    )),
    CONSTRAINT ck_doms_allocation_event_qty CHECK (quantity >= 0),
    CONSTRAINT ck_doms_allocation_event_metadata CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(metadata)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_allocation_event_idempotency
    ON doms.fulfillment_allocation_events (
        tenant_id, fulfillment_allocation_id, event_type, idempotency_key
    ) WHERE idempotency_key IS NOT NULL;

-- -----------------------------------------------------------------------------
-- Backorders, preorders, and substitution policy
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS doms.backorders (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    backorder_no varchar(100) NOT NULL,
    sales_order_id uuid NOT NULL,
    sales_order_line_id uuid NOT NULL,
    fulfillment_plan_line_id uuid,
    item_id uuid NOT NULL,
    backordered_quantity numeric(24,8) NOT NULL,
    released_quantity numeric(24,8) NOT NULL DEFAULT 0,
    cancelled_quantity numeric(24,8) NOT NULL DEFAULT 0,
    uom_code varchar(20) NOT NULL REFERENCES doms.units_of_measure(uom_code),
    priority integer NOT NULL DEFAULT 100,
    expected_available_at timestamptz,
    backorder_status varchar(20) NOT NULL DEFAULT 'OPEN',
    reason_code varchar(100),
    idempotency_key varchar(200) NOT NULL,
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, backorder_no),
    UNIQUE (tenant_id, sales_order_line_id, idempotency_key),
    CONSTRAINT fk_doms_backorder_order
        FOREIGN KEY (tenant_id, sales_order_id)
        REFERENCES doms.sales_orders(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_backorder_order_line
        FOREIGN KEY (tenant_id, sales_order_line_id)
        REFERENCES doms.sales_order_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_backorder_plan_line
        FOREIGN KEY (tenant_id, fulfillment_plan_line_id)
        REFERENCES doms.fulfillment_plan_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_backorder_item
        FOREIGN KEY (tenant_id, item_id)
        REFERENCES doms.items(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_backorder_values CHECK (
        btrim(backorder_no) <> '' AND btrim(idempotency_key) <> '' AND priority >= 0 AND
        backordered_quantity > 0 AND released_quantity >= 0 AND cancelled_quantity >= 0 AND
        released_quantity + cancelled_quantity <= backordered_quantity
    ),
    CONSTRAINT ck_doms_backorder_status CHECK (backorder_status IN (
        'OPEN','PARTIALLY_RELEASED','RELEASED','CANCELLED','EXPIRED','FAILED'
    )),
    CONSTRAINT ck_doms_backorder_attributes CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(attributes)
    )
);

CREATE TABLE IF NOT EXISTS doms.preorders (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    preorder_no varchar(100) NOT NULL,
    sales_order_id uuid NOT NULL,
    sales_order_line_id uuid NOT NULL,
    fulfillment_plan_line_id uuid,
    item_id uuid NOT NULL,
    preorder_quantity numeric(24,8) NOT NULL,
    released_quantity numeric(24,8) NOT NULL DEFAULT 0,
    cancelled_quantity numeric(24,8) NOT NULL DEFAULT 0,
    uom_code varchar(20) NOT NULL REFERENCES doms.units_of_measure(uom_code),
    available_from timestamptz NOT NULL,
    release_at timestamptz,
    preorder_status varchar(20) NOT NULL DEFAULT 'OPEN',
    priority integer NOT NULL DEFAULT 100,
    idempotency_key varchar(200) NOT NULL,
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, preorder_no),
    UNIQUE (tenant_id, sales_order_line_id, idempotency_key),
    CONSTRAINT fk_doms_preorder_order
        FOREIGN KEY (tenant_id, sales_order_id)
        REFERENCES doms.sales_orders(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_preorder_order_line
        FOREIGN KEY (tenant_id, sales_order_line_id)
        REFERENCES doms.sales_order_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_preorder_plan_line
        FOREIGN KEY (tenant_id, fulfillment_plan_line_id)
        REFERENCES doms.fulfillment_plan_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_preorder_item
        FOREIGN KEY (tenant_id, item_id)
        REFERENCES doms.items(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_preorder_values CHECK (
        btrim(preorder_no) <> '' AND btrim(idempotency_key) <> '' AND priority >= 0 AND
        preorder_quantity > 0 AND released_quantity >= 0 AND cancelled_quantity >= 0 AND
        released_quantity + cancelled_quantity <= preorder_quantity
    ),
    CONSTRAINT ck_doms_preorder_dates CHECK (
        release_at IS NULL OR release_at >= available_from
    ),
    CONSTRAINT ck_doms_preorder_status CHECK (preorder_status IN (
        'OPEN','SCHEDULED','PARTIALLY_RELEASED','RELEASED','CANCELLED','EXPIRED','FAILED'
    )),
    CONSTRAINT ck_doms_preorder_attributes CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(attributes)
    )
);

CREATE TABLE IF NOT EXISTS doms.item_substitutions (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    substitution_code varchar(80) NOT NULL,
    original_item_id uuid NOT NULL,
    substitution_name varchar(200) NOT NULL,
    substitution_type varchar(30) NOT NULL DEFAULT 'EQUIVALENT',
    substitution_status varchar(20) NOT NULL DEFAULT 'DRAFT',
    effective_from timestamptz,
    effective_to timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, substitution_code),
    CONSTRAINT fk_doms_item_substitution_original
        FOREIGN KEY (tenant_id, original_item_id)
        REFERENCES doms.items(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_item_substitution_code CHECK (btrim(substitution_code) <> ''),
    CONSTRAINT ck_doms_item_substitution_type CHECK (substitution_type IN (
        'EQUIVALENT','UPGRADE','DOWNGRADE','SUCCESSOR','CUSTOMER_CHOICE'
    )),
    CONSTRAINT ck_doms_item_substitution_status CHECK (substitution_status IN (
        'DRAFT','ACTIVE','SUSPENDED','EXPIRED','RETIRED'
    )),
    CONSTRAINT ck_doms_item_substitution_dates CHECK (
        effective_to IS NULL OR effective_from IS NULL OR effective_to > effective_from
    )
);

CREATE TABLE IF NOT EXISTS doms.item_substitution_rules (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    item_substitution_id uuid NOT NULL,
    rule_code varchar(80) NOT NULL,
    sequence_no integer NOT NULL,
    sales_channel_id uuid,
    customer_id uuid,
    fulfillment_node_id uuid,
    auto_apply boolean NOT NULL DEFAULT false,
    customer_approval_required boolean NOT NULL DEFAULT true,
    allow_price_increase boolean NOT NULL DEFAULT false,
    maximum_price_increase_percent numeric(9,6),
    conditions jsonb NOT NULL DEFAULT '{}'::jsonb,
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, item_substitution_id, rule_code),
    UNIQUE (tenant_id, item_substitution_id, sequence_no),
    CONSTRAINT fk_doms_substitution_rule_header
        FOREIGN KEY (tenant_id, item_substitution_id)
        REFERENCES doms.item_substitutions(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_substitution_rule_channel
        FOREIGN KEY (tenant_id, sales_channel_id)
        REFERENCES doms.sales_channels(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_substitution_rule_customer
        FOREIGN KEY (tenant_id, customer_id)
        REFERENCES doms.customers(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_substitution_rule_node
        FOREIGN KEY (tenant_id, fulfillment_node_id)
        REFERENCES doms.fulfillment_nodes(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_substitution_rule_values CHECK (
        btrim(rule_code) <> '' AND sequence_no > 0 AND
        (maximum_price_increase_percent IS NULL OR
            maximum_price_increase_percent BETWEEN 0 AND 100)
    ),
    CONSTRAINT ck_doms_substitution_rule_approval CHECK (
        NOT auto_apply OR NOT customer_approval_required
    ),
    CONSTRAINT ck_doms_substitution_rule_conditions CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(conditions)
    )
);

CREATE TABLE IF NOT EXISTS doms.item_substitution_candidates (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    item_substitution_id uuid NOT NULL,
    substitute_item_id uuid NOT NULL,
    candidate_priority integer NOT NULL DEFAULT 100,
    quantity_numerator numeric(24,8) NOT NULL DEFAULT 1,
    quantity_denominator numeric(24,8) NOT NULL DEFAULT 1,
    maximum_quantity numeric(24,8),
    price_behavior varchar(30) NOT NULL DEFAULT 'KEEP_ORIGINAL',
    candidate_status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, item_substitution_id, substitute_item_id),
    CONSTRAINT fk_doms_substitution_candidate_header
        FOREIGN KEY (tenant_id, item_substitution_id)
        REFERENCES doms.item_substitutions(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_substitution_candidate_item
        FOREIGN KEY (tenant_id, substitute_item_id)
        REFERENCES doms.items(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_substitution_candidate_values CHECK (
        candidate_priority >= 0 AND quantity_numerator > 0 AND quantity_denominator > 0 AND
        (maximum_quantity IS NULL OR maximum_quantity > 0)
    ),
    CONSTRAINT ck_doms_substitution_candidate_price CHECK (price_behavior IN (
        'KEEP_ORIGINAL','USE_SUBSTITUTE','LOWER_OF','HIGHER_OF','MANUAL'
    )),
    CONSTRAINT ck_doms_substitution_candidate_status CHECK (candidate_status IN (
        'ACTIVE','SUSPENDED','OUT_OF_STOCK','EXPIRED','RETIRED'
    )),
    CONSTRAINT ck_doms_substitution_candidate_attributes CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(attributes)
    )
);

ALTER TABLE doms.sourcing_candidates
    DROP CONSTRAINT IF EXISTS fk_doms_sourcing_candidate_substitution;
ALTER TABLE doms.sourcing_candidates
    ADD CONSTRAINT fk_doms_sourcing_candidate_substitution
    FOREIGN KEY (tenant_id, substitution_candidate_id)
    REFERENCES doms.item_substitution_candidates(tenant_id, id)
    ON DELETE RESTRICT;

-- -----------------------------------------------------------------------------
-- Cross-document and aggregate integrity
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION doms.prevent_orchestration_append_only_change()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    RAISE EXCEPTION '% is append-only; % is not permitted', TG_TABLE_NAME, TG_OP
        USING ERRCODE = '55000';
END;
$function$;

CREATE OR REPLACE FUNCTION doms.prevent_orchestration_delete()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    RAISE EXCEPTION '% uses state/event transitions; % is not permitted', TG_TABLE_NAME, TG_OP
        USING ERRCODE = '55000';
END;
$function$;

CREATE OR REPLACE FUNCTION doms.validate_journey_run_scope()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    version_definition_id uuid;
BEGIN
    SELECT journey_definition_id
      INTO version_definition_id
      FROM doms.order_journey_versions
     WHERE tenant_id = NEW.tenant_id
       AND id = NEW.journey_version_id;

    IF version_definition_id IS NULL OR version_definition_id <> NEW.journey_definition_id THEN
        RAISE EXCEPTION 'Journey run definition/version mismatch'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.validate_sourcing_request_scope()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    order_line_row record;
BEGIN
    SELECT sales_order_id, item_id, uom_code,
           ordered_qty, cancelled_qty, fulfilled_qty
      INTO order_line_row
      FROM doms.sales_order_lines
     WHERE tenant_id = NEW.tenant_id
       AND id = NEW.sales_order_line_id;

    IF NOT FOUND OR order_line_row.sales_order_id <> NEW.sales_order_id
       OR order_line_row.item_id <> NEW.item_id
       OR order_line_row.uom_code <> NEW.uom_code THEN
        RAISE EXCEPTION 'Sourcing request order, line, item, or UOM mismatch'
            USING ERRCODE = '23514';
    END IF;
    IF NEW.requested_quantity >
       order_line_row.ordered_qty - order_line_row.cancelled_qty - order_line_row.fulfilled_qty THEN
        RAISE EXCEPTION 'Sourcing request exceeds the open order-line quantity'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.validate_atp_result_scope()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    request_item_id uuid;
    position_row record;
BEGIN
    SELECT item_id INTO request_item_id
      FROM doms.atp_check_request_lines
     WHERE tenant_id = NEW.tenant_id
       AND id = NEW.atp_check_request_line_id;
    IF request_item_id IS NULL OR request_item_id <> NEW.item_id THEN
        RAISE EXCEPTION 'ATP result item differs from its request line'
            USING ERRCODE = '23514';
    END IF;

    IF NEW.inventory_position_id IS NOT NULL THEN
        SELECT inventory_source_id, fulfillment_node_id, item_id
          INTO position_row
          FROM doms.inventory_positions
         WHERE tenant_id = NEW.tenant_id
           AND id = NEW.inventory_position_id;
        IF NOT FOUND OR position_row.inventory_source_id <> NEW.inventory_source_id
           OR position_row.fulfillment_node_id <> NEW.fulfillment_node_id
           OR position_row.item_id <> NEW.item_id THEN
            RAISE EXCEPTION 'ATP result differs from its inventory position'
                USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.validate_sourcing_candidate_scope()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    request_item_id uuid;
    position_row record;
    substitution_row record;
BEGIN
    SELECT item_id INTO request_item_id
      FROM doms.sourcing_requests
     WHERE tenant_id = NEW.tenant_id
       AND id = NEW.sourcing_request_id;
    IF request_item_id IS NULL THEN
        RAISE EXCEPTION 'Sourcing request is unavailable in the tenant'
            USING ERRCODE = '23503';
    END IF;

    IF NEW.inventory_position_id IS NOT NULL THEN
        SELECT inventory_source_id, fulfillment_node_id, item_id
          INTO position_row
          FROM doms.inventory_positions
         WHERE tenant_id = NEW.tenant_id
           AND id = NEW.inventory_position_id;
        IF NOT FOUND OR position_row.inventory_source_id <> NEW.inventory_source_id
           OR position_row.fulfillment_node_id <> NEW.fulfillment_node_id
           OR position_row.item_id <> NEW.item_id THEN
            RAISE EXCEPTION 'Sourcing candidate differs from its inventory position'
                USING ERRCODE = '23514';
        END IF;
    END IF;

    IF NEW.substitution_candidate_id IS NULL THEN
        IF NEW.item_id <> request_item_id THEN
            RAISE EXCEPTION 'Non-substitute sourcing candidate must use the requested item'
                USING ERRCODE = '23514';
        END IF;
    ELSE
        SELECT header.original_item_id, candidate.substitute_item_id,
               candidate.candidate_status, header.substitution_status
          INTO substitution_row
          FROM doms.item_substitution_candidates candidate
          JOIN doms.item_substitutions header
            ON header.tenant_id = candidate.tenant_id
           AND header.id = candidate.item_substitution_id
         WHERE candidate.tenant_id = NEW.tenant_id
           AND candidate.id = NEW.substitution_candidate_id;
        IF NOT FOUND OR substitution_row.original_item_id <> request_item_id
           OR substitution_row.substitute_item_id <> NEW.item_id
           OR substitution_row.candidate_status <> 'ACTIVE'
           OR substitution_row.substitution_status <> 'ACTIVE' THEN
            RAISE EXCEPTION 'Sourcing substitution candidate is invalid for the requested item'
                USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.validate_fulfillment_plan_line_scope()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    plan_order_id uuid;
    order_line_row record;
BEGIN
    SELECT sales_order_id INTO plan_order_id
      FROM doms.fulfillment_plans
     WHERE tenant_id = NEW.tenant_id
       AND id = NEW.fulfillment_plan_id;

    SELECT sales_order_id, item_id, uom_code,
           ordered_qty, cancelled_qty, fulfilled_qty
      INTO order_line_row
      FROM doms.sales_order_lines
     WHERE tenant_id = NEW.tenant_id
       AND id = NEW.sales_order_line_id;

    IF plan_order_id IS NULL OR NOT FOUND
       OR plan_order_id <> order_line_row.sales_order_id
       OR NEW.item_id <> order_line_row.item_id
       OR NEW.uom_code <> order_line_row.uom_code THEN
        RAISE EXCEPTION 'Fulfillment-plan line order, item, or UOM mismatch'
            USING ERRCODE = '23514';
    END IF;
    IF NEW.requested_quantity >
       order_line_row.ordered_qty - order_line_row.cancelled_qty - order_line_row.fulfilled_qty THEN
        RAISE EXCEPTION 'Fulfillment-plan line exceeds the open order-line quantity'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.validate_fulfillment_source_split_scope()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    plan_line_row record;
    position_row record;
    candidate_row record;
    decision_row record;
BEGIN
    SELECT item_id, uom_code, planned_quantity
      INTO plan_line_row
      FROM doms.fulfillment_plan_lines
     WHERE tenant_id = NEW.tenant_id
       AND id = NEW.fulfillment_plan_line_id;

    SELECT inventory_source_id, fulfillment_node_id, item_id, uom_code
      INTO position_row
      FROM doms.inventory_positions
     WHERE tenant_id = NEW.tenant_id
       AND id = NEW.inventory_position_id;

    IF NOT FOUND OR plan_line_row.item_id <> NEW.item_id
       OR plan_line_row.uom_code <> NEW.uom_code
       OR position_row.inventory_source_id <> NEW.inventory_source_id
       OR position_row.fulfillment_node_id <> NEW.fulfillment_node_id
       OR position_row.item_id <> NEW.item_id
       OR position_row.uom_code <> NEW.uom_code THEN
        RAISE EXCEPTION 'Fulfillment source split differs from its plan line or inventory position'
            USING ERRCODE = '23514';
    END IF;

    IF NEW.sourcing_candidate_id IS NOT NULL THEN
        SELECT inventory_source_id, fulfillment_node_id, item_id, proposed_quantity
          INTO candidate_row
          FROM doms.sourcing_candidates
         WHERE tenant_id = NEW.tenant_id
           AND id = NEW.sourcing_candidate_id;
        IF NOT FOUND
           OR candidate_row.inventory_source_id <> NEW.inventory_source_id
           OR candidate_row.fulfillment_node_id <> NEW.fulfillment_node_id
           OR candidate_row.item_id <> NEW.item_id
           OR NEW.split_quantity > candidate_row.proposed_quantity THEN
            RAISE EXCEPTION 'Fulfillment source split differs from its sourcing candidate'
                USING ERRCODE = '23514';
        END IF;
    END IF;

    IF NEW.sourcing_decision_id IS NOT NULL THEN
        SELECT sourcing_candidate_id, decided_quantity, decision_type
          INTO decision_row
          FROM doms.sourcing_decisions
         WHERE tenant_id = NEW.tenant_id
           AND id = NEW.sourcing_decision_id;
        IF NOT FOUND OR NEW.sourcing_candidate_id IS NULL
           OR decision_row.sourcing_candidate_id <> NEW.sourcing_candidate_id
           OR decision_row.decision_type NOT IN ('SELECTED','OVERRIDDEN')
           OR NEW.split_quantity > decision_row.decided_quantity THEN
            RAISE EXCEPTION 'Fulfillment source split differs from its sourcing decision'
                USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.check_fulfillment_split_total()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    target_line_id uuid;
    planned_qty numeric(24,8);
    split_qty numeric(24,8);
BEGIN
    target_line_id := CASE WHEN TG_OP = 'DELETE'
                           THEN OLD.fulfillment_plan_line_id
                           ELSE NEW.fulfillment_plan_line_id END;

    SELECT planned_quantity
      INTO planned_qty
      FROM doms.fulfillment_plan_lines
     WHERE id = target_line_id
     FOR UPDATE;
    IF planned_qty IS NULL THEN
        RETURN NULL;
    END IF;

    SELECT COALESCE(sum(split_quantity), 0)
      INTO split_qty
      FROM doms.fulfillment_plan_source_splits
     WHERE fulfillment_plan_line_id = target_line_id
       AND split_status NOT IN ('CANCELLED','FAILED');

    IF split_qty > planned_qty THEN
        RAISE EXCEPTION 'Active fulfillment source splits % exceed planned quantity %',
            split_qty, planned_qty USING ERRCODE = '23514';
    END IF;
    RETURN NULL;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.check_sourcing_decision_total()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    target_request_id uuid;
    requested_qty numeric(24,8);
    selected_qty numeric(24,8);
    unapproved_override_count integer;
BEGIN
    target_request_id := CASE WHEN TG_OP = 'DELETE'
                              THEN OLD.sourcing_request_id
                              ELSE NEW.sourcing_request_id END;

    SELECT requested_quantity
      INTO requested_qty
      FROM doms.sourcing_requests
     WHERE id = target_request_id
     FOR UPDATE;
    IF requested_qty IS NULL THEN
        RETURN NULL;
    END IF;

    SELECT COALESCE(sum(decided_quantity), 0),
           count(*) FILTER (
               WHERE decision_type = 'OVERRIDDEN'
                 AND (override_approved_by IS NULL OR override_approved_at IS NULL OR
                      btrim(COALESCE(override_reason, '')) = '')
           )
      INTO selected_qty, unapproved_override_count
      FROM doms.sourcing_decisions
     WHERE sourcing_request_id = target_request_id
       AND decision_type IN ('SELECTED','OVERRIDDEN');

    IF selected_qty > requested_qty AND unapproved_override_count > 0 THEN
        RAISE EXCEPTION 'Sourcing decisions exceed requested quantity without complete override evidence'
            USING ERRCODE = '23514';
    END IF;
    IF selected_qty > requested_qty AND NOT EXISTS (
        SELECT 1 FROM doms.sourcing_decisions
         WHERE sourcing_request_id = target_request_id
           AND decision_type = 'OVERRIDDEN'
           AND override_approved_by IS NOT NULL
           AND override_approved_at IS NOT NULL
           AND btrim(COALESCE(override_reason, '')) <> ''
    ) THEN
        RAISE EXCEPTION 'Sourcing decisions exceed requested quantity without an approved override'
            USING ERRCODE = '23514';
    END IF;
    RETURN NULL;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.validate_reservation_request_line_scope()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    request_order_id uuid;
    order_line_row record;
    position_row record;
    split_row record;
BEGIN
    SELECT sales_order_id INTO request_order_id
      FROM doms.reservation_requests
     WHERE tenant_id = NEW.tenant_id
       AND id = NEW.reservation_request_id;
    SELECT sales_order_id, item_id, uom_code,
           ordered_qty, cancelled_qty, fulfilled_qty
      INTO order_line_row
      FROM doms.sales_order_lines
     WHERE tenant_id = NEW.tenant_id
       AND id = NEW.sales_order_line_id;
    SELECT item_id, uom_code
      INTO position_row
      FROM doms.inventory_positions
     WHERE tenant_id = NEW.tenant_id
       AND id = NEW.inventory_position_id;

    IF request_order_id IS NULL OR NOT FOUND
       OR request_order_id <> order_line_row.sales_order_id
       OR NEW.item_id <> order_line_row.item_id
       OR NEW.uom_code <> order_line_row.uom_code
       OR NEW.item_id <> position_row.item_id
       OR NEW.uom_code <> position_row.uom_code THEN
        RAISE EXCEPTION 'Reservation request line differs from its order or inventory position'
            USING ERRCODE = '23514';
    END IF;
    IF NEW.requested_quantity >
       order_line_row.ordered_qty - order_line_row.cancelled_qty - order_line_row.fulfilled_qty THEN
        RAISE EXCEPTION 'Reservation request line exceeds open order-line quantity'
            USING ERRCODE = '23514';
    END IF;

    IF NEW.fulfillment_plan_source_split_id IS NOT NULL THEN
        SELECT plan_line.sales_order_line_id, split.inventory_position_id,
               split.item_id, split.uom_code, split.split_quantity
          INTO split_row
          FROM doms.fulfillment_plan_source_splits split
          JOIN doms.fulfillment_plan_lines plan_line
            ON plan_line.tenant_id = split.tenant_id
           AND plan_line.id = split.fulfillment_plan_line_id
         WHERE split.tenant_id = NEW.tenant_id
           AND split.id = NEW.fulfillment_plan_source_split_id;
        IF NOT FOUND OR split_row.sales_order_line_id <> NEW.sales_order_line_id
           OR split_row.inventory_position_id <> NEW.inventory_position_id
           OR split_row.item_id <> NEW.item_id
           OR split_row.uom_code <> NEW.uom_code
           OR NEW.requested_quantity > split_row.split_quantity THEN
            RAISE EXCEPTION 'Reservation request line differs from its fulfillment source split'
                USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.validate_inventory_reservation_scope()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    request_row record;
BEGIN
    IF TG_OP = 'UPDATE' AND (
        OLD.tenant_id IS DISTINCT FROM NEW.tenant_id OR
        OLD.reservation_request_id IS DISTINCT FROM NEW.reservation_request_id OR
        OLD.sales_order_id IS DISTINCT FROM NEW.sales_order_id OR
        OLD.fulfillment_plan_id IS DISTINCT FROM NEW.fulfillment_plan_id OR
        OLD.expires_at IS DISTINCT FROM NEW.expires_at OR
        OLD.creation_idempotency_key IS DISTINCT FROM NEW.creation_idempotency_key
    ) THEN
        RAISE EXCEPTION 'Reservation header demand, scope, expiry, and creation key are immutable'
            USING ERRCODE = '55000';
    END IF;

    SELECT sales_order_id, fulfillment_plan_id, expires_at
      INTO request_row
      FROM doms.reservation_requests
     WHERE tenant_id = NEW.tenant_id
       AND id = NEW.reservation_request_id;
    IF NOT FOUND OR request_row.sales_order_id <> NEW.sales_order_id
       OR request_row.fulfillment_plan_id IS DISTINCT FROM NEW.fulfillment_plan_id
       OR NEW.expires_at > request_row.expires_at THEN
        RAISE EXCEPTION 'Inventory reservation differs from its reservation request'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.validate_inventory_position_projection()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    active_reserved numeric(24,8);
    active_allocated numeric(24,8);
BEGIN
    SELECT COALESCE(sum(
               reserved_quantity - released_quantity - consumed_quantity
           ), 0)
      INTO active_reserved
      FROM doms.inventory_reservation_lines
     WHERE tenant_id = NEW.tenant_id
       AND inventory_position_id = NEW.id
       AND reservation_status IN ('ACTIVE','PARTIALLY_CONSUMED','PARTIALLY_RELEASED');

    SELECT COALESCE(sum(
               allocated_quantity - released_quantity - consumed_quantity
           ), 0)
      INTO active_allocated
      FROM doms.fulfillment_allocations
     WHERE tenant_id = NEW.tenant_id
       AND inventory_position_id = NEW.id
       AND allocation_status IN ('ACTIVE','PARTIALLY_CONSUMED','PARTIALLY_RELEASED');

    IF abs(NEW.reserved_quantity - active_reserved) > 0.00000001 THEN
        RAISE EXCEPTION 'Inventory position reserved projection % differs from active reservation sum %',
            NEW.reserved_quantity, active_reserved USING ERRCODE = '23514';
    END IF;
    IF abs(NEW.allocated_quantity - active_allocated) > 0.00000001 THEN
        RAISE EXCEPTION 'Inventory position allocated projection % differs from active allocation sum %',
            NEW.allocated_quantity, active_allocated USING ERRCODE = '23514';
    END IF;
    IF active_reserved > NEW.atp_quantity THEN
        RAISE EXCEPTION 'Active reservation sum % exceeds ATP % for inventory position %',
            active_reserved, NEW.atp_quantity, NEW.id USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.apply_inventory_position_delta(
    p_tenant_id uuid,
    p_inventory_position_id uuid,
    p_measure_code varchar,
    p_quantity_delta numeric,
    p_event_type varchar,
    p_idempotency_key varchar,
    p_source_event_id varchar DEFAULT NULL,
    p_source_version varchar DEFAULT NULL,
    p_occurred_at timestamptz DEFAULT now(),
    p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, doms, pg_temp
AS $function$
DECLARE
    position_row doms.inventory_positions%ROWTYPE;
    measure_row doms.inventory_measures%ROWTYPE;
    existing_event_id uuid;
    new_event_id uuid;
    before_qty numeric(24,8);
    after_qty numeric(24,8);
    active_reserved numeric(24,8);
BEGIN
    IF p_tenant_id IS NULL OR p_inventory_position_id IS NULL
       OR btrim(COALESCE(p_measure_code, '')) = ''
       OR btrim(COALESCE(p_event_type, '')) = ''
       OR btrim(COALESCE(p_idempotency_key, '')) = '' THEN
        RAISE EXCEPTION 'Tenant, position, measure, event type, and idempotency key are required'
            USING ERRCODE = '22023';
    END IF;
    IF p_quantity_delta IS NULL THEN
        RAISE EXCEPTION 'Inventory quantity delta is required' USING ERRCODE = '22004';
    END IF;
    IF doms.jsonb_contains_forbidden_secret_key(p_metadata) THEN
        RAISE EXCEPTION 'Inventory event metadata contains a forbidden secret key'
            USING ERRCODE = '22023';
    END IF;

    SELECT id INTO existing_event_id
      FROM doms.inventory_position_events
     WHERE tenant_id = p_tenant_id
       AND inventory_position_id = p_inventory_position_id
       AND idempotency_key = p_idempotency_key;
    IF existing_event_id IS NOT NULL THEN
        RETURN existing_event_id;
    END IF;

    SELECT * INTO measure_row
      FROM doms.inventory_measures
     WHERE tenant_id = p_tenant_id
       AND measure_code = p_measure_code
       AND is_active;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Active inventory measure % is unavailable in the tenant', p_measure_code
            USING ERRCODE = '23503';
    END IF;
    IF measure_row.system_managed
       OR measure_row.position_bucket IN ('RESERVED','ALLOCATED') THEN
        RAISE EXCEPTION 'Measure % is maintained only by reservation/allocation projections',
            p_measure_code USING ERRCODE = '42501';
    END IF;

    SELECT * INTO position_row
      FROM doms.inventory_positions
     WHERE tenant_id = p_tenant_id
       AND id = p_inventory_position_id
     FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Inventory position is unavailable in the tenant'
            USING ERRCODE = '42501';
    END IF;
    IF position_row.position_status IN ('SUSPENDED','CLOSED') THEN
        RAISE EXCEPTION 'Inventory position % is not writable in status %',
            position_row.id, position_row.position_status USING ERRCODE = '55000';
    END IF;

    before_qty := CASE measure_row.position_bucket
        WHEN 'ON_HAND' THEN position_row.on_hand_quantity
        WHEN 'INBOUND' THEN position_row.inbound_quantity
        WHEN 'UNAVAILABLE' THEN position_row.unavailable_quantity
        WHEN 'SAFETY_STOCK' THEN position_row.safety_stock_quantity
        WHEN 'OTHER_DEMAND' THEN position_row.other_demand_quantity
        WHEN 'ATP' THEN position_row.atp_quantity
        ELSE NULL
    END;
    IF before_qty IS NULL THEN
        RAISE EXCEPTION 'Inventory measure % cannot update a position quantity bucket', p_measure_code
            USING ERRCODE = '22023';
    END IF;

    after_qty := before_qty + p_quantity_delta;
    IF after_qty < 0 THEN
        RAISE EXCEPTION 'Inventory position bucket % cannot become negative',
            measure_row.position_bucket USING ERRCODE = '23514';
    END IF;

    IF measure_row.position_bucket = 'ATP' THEN
        SELECT COALESCE(sum(
                   reserved_quantity - released_quantity - consumed_quantity
               ), 0)
          INTO active_reserved
          FROM doms.inventory_reservation_lines
         WHERE tenant_id = p_tenant_id
           AND inventory_position_id = p_inventory_position_id
           AND reservation_status IN ('ACTIVE','PARTIALLY_CONSUMED','PARTIALLY_RELEASED');
        IF after_qty < active_reserved THEN
            RAISE EXCEPTION 'ATP reduction to % would be below active reservation sum %',
                after_qty, active_reserved USING ERRCODE = '23514';
        END IF;
    END IF;

    UPDATE doms.inventory_positions
       SET on_hand_quantity = CASE WHEN measure_row.position_bucket = 'ON_HAND'
                                   THEN after_qty ELSE on_hand_quantity END,
           inbound_quantity = CASE WHEN measure_row.position_bucket = 'INBOUND'
                                   THEN after_qty ELSE inbound_quantity END,
           unavailable_quantity = CASE WHEN measure_row.position_bucket = 'UNAVAILABLE'
                                       THEN after_qty ELSE unavailable_quantity END,
           safety_stock_quantity = CASE WHEN measure_row.position_bucket = 'SAFETY_STOCK'
                                        THEN after_qty ELSE safety_stock_quantity END,
           other_demand_quantity = CASE WHEN measure_row.position_bucket = 'OTHER_DEMAND'
                                        THEN after_qty ELSE other_demand_quantity END,
           atp_quantity = CASE WHEN measure_row.position_bucket = 'ATP'
                               THEN after_qty ELSE atp_quantity END,
           source_version = COALESCE(p_source_version, source_version),
           source_updated_at = GREATEST(COALESCE(source_updated_at, p_occurred_at), p_occurred_at),
           updated_at = now(),
           row_version = row_version + 1
     WHERE id = p_inventory_position_id;

    new_event_id := doms.generate_uuid();
    INSERT INTO doms.inventory_position_events (
        id, tenant_id, inventory_position_id, inventory_measure_id,
        event_type, position_bucket, quantity_before, quantity_delta, quantity_after,
        source_event_id, source_version, idempotency_key, metadata, occurred_at
    ) VALUES (
        new_event_id, p_tenant_id, p_inventory_position_id, measure_row.id,
        p_event_type, measure_row.position_bucket, before_qty, p_quantity_delta, after_qty,
        p_source_event_id, p_source_version, p_idempotency_key, p_metadata, p_occurred_at
    );
    RETURN new_event_id;
END;
$function$;

REVOKE ALL ON FUNCTION doms.apply_inventory_position_delta(
    uuid, uuid, varchar, numeric, varchar, varchar, varchar, varchar, timestamptz, jsonb
) FROM PUBLIC;

CREATE OR REPLACE FUNCTION doms.validate_inventory_reservation_line()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    position_row doms.inventory_positions%ROWTYPE;
    reservation_row doms.inventory_reservations%ROWTYPE;
    order_line_row record;
    other_position_reserved numeric(24,8);
    other_order_line_reserved numeric(24,8);
    active_allocated numeric(24,8);
    unapproved_allocation_count integer;
    active_remaining numeric(24,8);
    open_order_quantity numeric(24,8);
BEGIN
    IF TG_OP = 'UPDATE' AND (
        OLD.tenant_id IS DISTINCT FROM NEW.tenant_id OR
        OLD.inventory_reservation_id IS DISTINCT FROM NEW.inventory_reservation_id OR
        OLD.reservation_request_line_id IS DISTINCT FROM NEW.reservation_request_line_id OR
        OLD.sales_order_line_id IS DISTINCT FROM NEW.sales_order_line_id OR
        OLD.fulfillment_plan_source_split_id IS DISTINCT FROM NEW.fulfillment_plan_source_split_id OR
        OLD.inventory_position_id IS DISTINCT FROM NEW.inventory_position_id OR
        OLD.inventory_source_id IS DISTINCT FROM NEW.inventory_source_id OR
        OLD.fulfillment_node_id IS DISTINCT FROM NEW.fulfillment_node_id OR
        OLD.item_id IS DISTINCT FROM NEW.item_id OR
        OLD.requested_quantity IS DISTINCT FROM NEW.requested_quantity OR
        OLD.uom_code IS DISTINCT FROM NEW.uom_code OR
        OLD.expires_at IS DISTINCT FROM NEW.expires_at
    ) THEN
        RAISE EXCEPTION 'Reservation-line identity, demand, quantity, and expiry are immutable'
            USING ERRCODE = '55000';
    END IF;
    IF TG_OP = 'UPDATE' AND (
        OLD.reserved_quantity IS DISTINCT FROM NEW.reserved_quantity OR
        OLD.released_quantity IS DISTINCT FROM NEW.released_quantity OR
        OLD.consumed_quantity IS DISTINCT FROM NEW.consumed_quantity OR
        OLD.reservation_status IS DISTINCT FROM NEW.reservation_status
    ) AND (
        btrim(COALESCE(NEW.last_operation_key, '')) = '' OR
        NEW.last_operation_key IS NOT DISTINCT FROM OLD.last_operation_key
    ) THEN
        RAISE EXCEPTION 'Reservation state mutation requires a new idempotent operation key'
            USING ERRCODE = '23514';
    END IF;

    SELECT * INTO reservation_row
      FROM doms.inventory_reservations
     WHERE tenant_id = NEW.tenant_id
       AND id = NEW.inventory_reservation_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Reservation header is unavailable in the tenant'
            USING ERRCODE = '23503';
    END IF;

    SELECT * INTO position_row
      FROM doms.inventory_positions
     WHERE tenant_id = NEW.tenant_id
       AND id = NEW.inventory_position_id
     FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Inventory position is unavailable in the tenant'
            USING ERRCODE = '23503';
    END IF;

    SELECT sales_order_id, item_id, uom_code,
           ordered_qty, cancelled_qty, fulfilled_qty
      INTO order_line_row
      FROM doms.sales_order_lines
     WHERE tenant_id = NEW.tenant_id
       AND id = NEW.sales_order_line_id;
    IF NOT FOUND OR reservation_row.sales_order_id <> order_line_row.sales_order_id
       OR position_row.inventory_source_id <> NEW.inventory_source_id
       OR position_row.fulfillment_node_id <> NEW.fulfillment_node_id
       OR position_row.item_id <> NEW.item_id
       OR position_row.uom_code <> NEW.uom_code
       OR order_line_row.item_id <> NEW.item_id
       OR order_line_row.uom_code <> NEW.uom_code THEN
        RAISE EXCEPTION 'Reservation line differs from its order line, reservation, or position'
            USING ERRCODE = '23514';
    END IF;
    IF NEW.expires_at > reservation_row.expires_at THEN
        RAISE EXCEPTION 'Reservation-line expiry exceeds header expiry'
            USING ERRCODE = '23514';
    END IF;

    active_remaining := CASE
        WHEN NEW.reservation_status IN ('ACTIVE','PARTIALLY_CONSUMED','PARTIALLY_RELEASED')
        THEN NEW.reserved_quantity - NEW.released_quantity - NEW.consumed_quantity
        ELSE 0
    END;

    IF NEW.reservation_status = 'PENDING' AND (
        NEW.reserved_quantity <> 0 OR NEW.released_quantity <> 0 OR NEW.consumed_quantity <> 0
    ) THEN
        RAISE EXCEPTION 'Pending reservation line cannot carry reserved/released/consumed quantity'
            USING ERRCODE = '23514';
    END IF;
    IF active_remaining > 0 AND NEW.expires_at <= now() THEN
        RAISE EXCEPTION 'Active reservation line is already expired'
            USING ERRCODE = '23514';
    END IF;
    IF NEW.reservation_status IN ('ACTIVE','PARTIALLY_CONSUMED','PARTIALLY_RELEASED')
       AND active_remaining <= 0 THEN
        RAISE EXCEPTION 'Active reservation line must have a positive remaining quantity'
            USING ERRCODE = '23514';
    END IF;
    IF NEW.reservation_status IN ('CONSUMED','RELEASED','EXPIRED','CANCELLED')
       AND NEW.released_quantity + NEW.consumed_quantity <> NEW.reserved_quantity THEN
        RAISE EXCEPTION 'Terminal reservation line must have no remaining quantity'
            USING ERRCODE = '23514';
    END IF;

    SELECT COALESCE(sum(
               allocated_quantity - released_quantity - consumed_quantity
           ), 0),
           count(*) FILTER (WHERE
               override_approved_by IS NULL OR override_approved_at IS NULL OR
               btrim(COALESCE(override_reason, '')) = ''
           )
      INTO active_allocated, unapproved_allocation_count
      FROM doms.fulfillment_allocations
     WHERE tenant_id = NEW.tenant_id
       AND inventory_reservation_line_id = NEW.id
       AND allocation_status IN ('ACTIVE','PARTIALLY_CONSUMED','PARTIALLY_RELEASED');
    IF active_allocated > active_remaining AND unapproved_allocation_count > 0 THEN
        RAISE EXCEPTION 'Reservation remainder % would fall below active non-override allocation %',
            active_remaining, active_allocated USING ERRCODE = '23514';
    END IF;

    IF active_remaining > 0 THEN
        SELECT COALESCE(sum(
                   reserved_quantity - released_quantity - consumed_quantity
               ), 0)
          INTO other_position_reserved
          FROM doms.inventory_reservation_lines
         WHERE tenant_id = NEW.tenant_id
           AND inventory_position_id = NEW.inventory_position_id
           AND id <> NEW.id
           AND reservation_status IN ('ACTIVE','PARTIALLY_CONSUMED','PARTIALLY_RELEASED');

        IF other_position_reserved + active_remaining > position_row.atp_quantity THEN
            RAISE EXCEPTION 'Active reservation sum % would exceed ATP % for position %',
                other_position_reserved + active_remaining, position_row.atp_quantity,
                position_row.id USING ERRCODE = '23514';
        END IF;

        SELECT COALESCE(sum(
                   reserved_quantity - released_quantity - consumed_quantity
               ), 0)
          INTO other_order_line_reserved
          FROM doms.inventory_reservation_lines
         WHERE tenant_id = NEW.tenant_id
           AND sales_order_line_id = NEW.sales_order_line_id
           AND id <> NEW.id
           AND reservation_status IN ('ACTIVE','PARTIALLY_CONSUMED','PARTIALLY_RELEASED');

        open_order_quantity := order_line_row.ordered_qty -
                               order_line_row.cancelled_qty -
                               order_line_row.fulfilled_qty;
        IF other_order_line_reserved + active_remaining > open_order_quantity THEN
            RAISE EXCEPTION 'Active reservation sum exceeds open order-line quantity'
                USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.project_inventory_reservation_line()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    projection_before numeric(24,8);
    projection_after numeric(24,8);
    event_kind varchar(30);
    event_quantity numeric(24,8);
    header_status varchar(30);
    pending_count integer;
    active_count integer;
    consumed_sum numeric(24,8);
    released_sum numeric(24,8);
    total_count integer;
    expired_count integer;
    cancelled_count integer;
BEGIN
    SELECT reserved_quantity
      INTO projection_before
      FROM doms.inventory_positions
     WHERE tenant_id = NEW.tenant_id
       AND id = NEW.inventory_position_id
     FOR UPDATE;

    SELECT COALESCE(sum(
               reserved_quantity - released_quantity - consumed_quantity
           ), 0)
      INTO projection_after
      FROM doms.inventory_reservation_lines
     WHERE tenant_id = NEW.tenant_id
       AND inventory_position_id = NEW.inventory_position_id
       AND reservation_status IN ('ACTIVE','PARTIALLY_CONSUMED','PARTIALLY_RELEASED');

    UPDATE doms.inventory_positions
       SET reserved_quantity = projection_after,
           updated_at = now(),
           row_version = row_version + 1
     WHERE tenant_id = NEW.tenant_id
       AND id = NEW.inventory_position_id;

    IF TG_OP = 'INSERT' THEN
        event_kind := CASE WHEN NEW.reservation_status = 'PENDING'
                           THEN 'REQUESTED' ELSE 'ACTIVATED' END;
        event_quantity := CASE WHEN NEW.reservation_status = 'PENDING'
                               THEN NEW.requested_quantity ELSE NEW.reserved_quantity END;
    ELSIF NEW.reserved_quantity > OLD.reserved_quantity THEN
        event_kind := 'ACTIVATED';
        event_quantity := NEW.reserved_quantity - OLD.reserved_quantity;
    ELSIF NEW.consumed_quantity > OLD.consumed_quantity THEN
        event_kind := 'CONSUMED';
        event_quantity := NEW.consumed_quantity - OLD.consumed_quantity;
    ELSIF NEW.released_quantity > OLD.released_quantity THEN
        event_kind := CASE NEW.reservation_status
            WHEN 'EXPIRED' THEN 'EXPIRED'
            WHEN 'CANCELLED' THEN 'CANCELLED'
            ELSE 'RELEASED'
        END;
        event_quantity := NEW.released_quantity - OLD.released_quantity;
    ELSE
        event_kind := CASE NEW.reservation_status
            WHEN 'FAILED' THEN 'FAILED'
            ELSE 'STATUS_CHANGED'
        END;
        event_quantity := 0;
    END IF;

    INSERT INTO doms.inventory_reservation_events (
        tenant_id, inventory_reservation_id, inventory_reservation_line_id,
        event_type, from_status, to_status, quantity, idempotency_key,
        reason_code, actor_user_id
    ) VALUES (
        NEW.tenant_id, NEW.inventory_reservation_id, NEW.id,
        event_kind, CASE WHEN TG_OP = 'INSERT' THEN NULL ELSE OLD.reservation_status END,
        NEW.reservation_status, event_quantity, NEW.last_operation_key,
        NEW.last_reason_code, NEW.last_actor_user_id
    ) ON CONFLICT DO NOTHING;

    IF projection_before IS DISTINCT FROM projection_after THEN
        INSERT INTO doms.inventory_position_events (
            tenant_id, inventory_position_id, event_type, position_bucket,
            quantity_before, quantity_delta, quantity_after, idempotency_key,
            actor_user_id, occurred_at
        ) VALUES (
            NEW.tenant_id, NEW.inventory_position_id, 'RESERVATION_CHANGED', 'RESERVED',
            projection_before, projection_after - projection_before, projection_after,
            CASE WHEN NEW.last_operation_key IS NULL THEN NULL
                 ELSE 'RESERVATION:' || NEW.id::text || ':' || NEW.last_operation_key END,
            NEW.last_actor_user_id, now()
        ) ON CONFLICT DO NOTHING;
    END IF;

    SELECT count(*),
           count(*) FILTER (WHERE reservation_status = 'PENDING'),
           count(*) FILTER (WHERE reservation_status IN (
               'ACTIVE','PARTIALLY_CONSUMED','PARTIALLY_RELEASED'
           )),
           COALESCE(sum(consumed_quantity), 0),
           COALESCE(sum(released_quantity), 0),
           count(*) FILTER (WHERE reservation_status = 'EXPIRED'),
           count(*) FILTER (WHERE reservation_status = 'CANCELLED')
      INTO total_count, pending_count, active_count, consumed_sum,
           released_sum, expired_count, cancelled_count
      FROM doms.inventory_reservation_lines
     WHERE tenant_id = NEW.tenant_id
       AND inventory_reservation_id = NEW.inventory_reservation_id;

    header_status := CASE
        WHEN total_count = pending_count THEN 'PENDING'
        WHEN active_count > 0 AND consumed_sum > 0 THEN 'PARTIALLY_CONSUMED'
        WHEN active_count > 0 AND released_sum > 0 THEN 'PARTIALLY_RELEASED'
        WHEN active_count > 0 THEN 'ACTIVE'
        WHEN expired_count = total_count THEN 'EXPIRED'
        WHEN cancelled_count = total_count THEN 'CANCELLED'
        WHEN consumed_sum > 0 AND released_sum = 0 THEN 'CONSUMED'
        ELSE 'RELEASED'
    END;

    UPDATE doms.inventory_reservations
       SET reservation_status = header_status,
           activated_at = CASE WHEN header_status <> 'PENDING'
                               THEN COALESCE(activated_at, now()) ELSE activated_at END,
           closed_at = CASE WHEN header_status IN (
                               'CONSUMED','RELEASED','EXPIRED','CANCELLED','FAILED'
                           ) THEN COALESCE(closed_at, now()) ELSE NULL END,
           updated_at = now(),
           row_version = row_version + 1
     WHERE tenant_id = NEW.tenant_id
       AND id = NEW.inventory_reservation_id;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.activate_inventory_reservation(
    p_tenant_id uuid,
    p_inventory_reservation_id uuid,
    p_idempotency_key varchar,
    p_actor_user_id uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, doms, pg_temp
AS $function$
DECLARE
    reservation_row doms.inventory_reservations%ROWTYPE;
    line_row record;
    line_count integer;
BEGIN
    IF p_tenant_id IS NULL OR p_inventory_reservation_id IS NULL
       OR btrim(COALESCE(p_idempotency_key, '')) = '' THEN
        RAISE EXCEPTION 'Tenant, reservation, and idempotency key are required'
            USING ERRCODE = '22023';
    END IF;

    SELECT * INTO reservation_row
      FROM doms.inventory_reservations
     WHERE tenant_id = p_tenant_id
       AND id = p_inventory_reservation_id
     FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Inventory reservation is unavailable in the tenant'
            USING ERRCODE = '42501';
    END IF;
    IF reservation_row.last_operation_key = p_idempotency_key
       AND reservation_row.reservation_status <> 'PENDING' THEN
        RETURN reservation_row.id;
    END IF;
    IF reservation_row.reservation_status <> 'PENDING' THEN
        RAISE EXCEPTION 'Only a pending reservation can be activated; current status is %',
            reservation_row.reservation_status USING ERRCODE = '55000';
    END IF;
    IF reservation_row.expires_at <= now() THEN
        RAISE EXCEPTION 'Reservation expired before activation' USING ERRCODE = '23514';
    END IF;

    SELECT count(*) INTO line_count
      FROM doms.inventory_reservation_lines
     WHERE tenant_id = p_tenant_id
       AND inventory_reservation_id = p_inventory_reservation_id;
    IF line_count = 0 THEN
        RAISE EXCEPTION 'Reservation has no lines' USING ERRCODE = '23514';
    END IF;
    IF EXISTS (
        SELECT 1 FROM doms.inventory_reservation_lines
         WHERE tenant_id = p_tenant_id
           AND inventory_reservation_id = p_inventory_reservation_id
           AND reservation_status <> 'PENDING'
    ) THEN
        RAISE EXCEPTION 'Reservation activation found a non-pending line'
            USING ERRCODE = '23514';
    END IF;

    -- Deterministic position lock order serializes concurrent reservations and
    -- avoids deadlocks when a reservation spans multiple nodes/items.
    PERFORM position.id
      FROM doms.inventory_positions position
      JOIN (
          SELECT DISTINCT inventory_position_id
            FROM doms.inventory_reservation_lines
           WHERE tenant_id = p_tenant_id
             AND inventory_reservation_id = p_inventory_reservation_id
      ) target ON target.inventory_position_id = position.id
     WHERE position.tenant_id = p_tenant_id
     ORDER BY position.id
     FOR UPDATE OF position;

    FOR line_row IN
        SELECT id
          FROM doms.inventory_reservation_lines
         WHERE tenant_id = p_tenant_id
           AND inventory_reservation_id = p_inventory_reservation_id
         ORDER BY inventory_position_id, id
    LOOP
        UPDATE doms.inventory_reservation_lines
           SET reserved_quantity = requested_quantity,
               reservation_status = 'ACTIVE',
               last_operation_key = p_idempotency_key,
               last_actor_user_id = p_actor_user_id,
               last_reason_code = 'ACTIVATED',
               updated_at = now(),
               row_version = row_version + 1
         WHERE id = line_row.id;
    END LOOP;

    UPDATE doms.inventory_reservations
       SET reservation_status = 'ACTIVE',
           activated_at = COALESCE(activated_at, now()),
           last_operation_key = p_idempotency_key,
           updated_at = now(),
           row_version = row_version + 1
     WHERE tenant_id = p_tenant_id
       AND id = p_inventory_reservation_id;

    UPDATE doms.reservation_requests
       SET request_status = 'COMPLETED',
           completed_at = COALESCE(completed_at, now()),
           updated_at = now(),
           row_version = row_version + 1
     WHERE tenant_id = p_tenant_id
       AND id = reservation_row.reservation_request_id;

    UPDATE doms.reservation_request_lines request_line
       SET line_status = 'RESERVED',
           updated_at = now(),
           row_version = row_version + 1
     WHERE request_line.tenant_id = p_tenant_id
       AND request_line.reservation_request_id = reservation_row.reservation_request_id;

    RETURN p_inventory_reservation_id;
END;
$function$;

REVOKE ALL ON FUNCTION doms.activate_inventory_reservation(uuid, uuid, varchar, uuid)
    FROM PUBLIC;

CREATE OR REPLACE FUNCTION doms.transition_inventory_reservation_line(
    p_tenant_id uuid,
    p_inventory_reservation_line_id uuid,
    p_action varchar,
    p_quantity numeric,
    p_idempotency_key varchar,
    p_actor_user_id uuid DEFAULT NULL,
    p_reason_code varchar DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, doms, pg_temp
AS $function$
DECLARE
    reservation_line doms.inventory_reservation_lines%ROWTYPE;
    transition_quantity numeric(24,8);
    remaining_quantity numeric(24,8);
    next_status varchar(30);
    existing_event_id uuid;
BEGIN
    IF p_tenant_id IS NULL OR p_inventory_reservation_line_id IS NULL
       OR btrim(COALESCE(p_action, '')) = ''
       OR btrim(COALESCE(p_idempotency_key, '')) = '' THEN
        RAISE EXCEPTION 'Tenant, reservation line, action, and idempotency key are required'
            USING ERRCODE = '22023';
    END IF;
    IF upper(p_action) NOT IN ('CONSUME','RELEASE','EXPIRE','CANCEL') THEN
        RAISE EXCEPTION 'Unsupported reservation transition action %', p_action
            USING ERRCODE = '22023';
    END IF;

    SELECT id INTO existing_event_id
      FROM doms.inventory_reservation_events
     WHERE tenant_id = p_tenant_id
       AND inventory_reservation_line_id = p_inventory_reservation_line_id
       AND idempotency_key = p_idempotency_key
     ORDER BY occurred_at DESC
     LIMIT 1;
    IF existing_event_id IS NOT NULL THEN
        RETURN existing_event_id;
    END IF;

    SELECT * INTO reservation_line
      FROM doms.inventory_reservation_lines
     WHERE tenant_id = p_tenant_id
       AND id = p_inventory_reservation_line_id
     FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Inventory reservation line is unavailable in the tenant'
            USING ERRCODE = '42501';
    END IF;
    IF reservation_line.reservation_status NOT IN (
        'ACTIVE','PARTIALLY_CONSUMED','PARTIALLY_RELEASED'
    ) THEN
        RAISE EXCEPTION 'Reservation line in status % cannot transition',
            reservation_line.reservation_status USING ERRCODE = '55000';
    END IF;

    remaining_quantity := reservation_line.reserved_quantity -
                          reservation_line.released_quantity -
                          reservation_line.consumed_quantity;
    transition_quantity := COALESCE(p_quantity, remaining_quantity);
    IF transition_quantity <= 0 OR transition_quantity > remaining_quantity THEN
        RAISE EXCEPTION 'Transition quantity % exceeds remaining reservation quantity %',
            transition_quantity, remaining_quantity USING ERRCODE = '23514';
    END IF;
    IF upper(p_action) = 'EXPIRE' AND reservation_line.expires_at > now() THEN
        RAISE EXCEPTION 'Reservation line cannot expire before %', reservation_line.expires_at
            USING ERRCODE = '23514';
    END IF;

    IF upper(p_action) = 'CONSUME' THEN
        next_status := CASE
            WHEN transition_quantity = remaining_quantity
                 AND reservation_line.released_quantity = 0 THEN 'CONSUMED'
            WHEN transition_quantity = remaining_quantity THEN 'RELEASED'
            ELSE 'PARTIALLY_CONSUMED'
        END;
        UPDATE doms.inventory_reservation_lines
           SET consumed_quantity = consumed_quantity + transition_quantity,
               reservation_status = next_status,
               last_operation_key = p_idempotency_key,
               last_actor_user_id = p_actor_user_id,
               last_reason_code = COALESCE(p_reason_code, 'CONSUMED'),
               updated_at = now(),
               row_version = row_version + 1
         WHERE id = reservation_line.id;
    ELSE
        next_status := CASE
            WHEN transition_quantity < remaining_quantity THEN 'PARTIALLY_RELEASED'
            WHEN upper(p_action) = 'EXPIRE' THEN 'EXPIRED'
            WHEN upper(p_action) = 'CANCEL' THEN 'CANCELLED'
            ELSE 'RELEASED'
        END;
        UPDATE doms.inventory_reservation_lines
           SET released_quantity = released_quantity + transition_quantity,
               reservation_status = next_status,
               last_operation_key = p_idempotency_key,
               last_actor_user_id = p_actor_user_id,
               last_reason_code = COALESCE(p_reason_code, upper(p_action)),
               updated_at = now(),
               row_version = row_version + 1
         WHERE id = reservation_line.id;
    END IF;

    SELECT id INTO existing_event_id
      FROM doms.inventory_reservation_events
     WHERE tenant_id = p_tenant_id
       AND inventory_reservation_line_id = p_inventory_reservation_line_id
       AND idempotency_key = p_idempotency_key
     ORDER BY occurred_at DESC
     LIMIT 1;
    RETURN COALESCE(existing_event_id, p_inventory_reservation_line_id);
END;
$function$;

REVOKE ALL ON FUNCTION doms.transition_inventory_reservation_line(
    uuid, uuid, varchar, numeric, varchar, uuid, varchar
) FROM PUBLIC;

CREATE OR REPLACE FUNCTION doms.validate_fulfillment_allocation()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    position_row doms.inventory_positions%ROWTYPE;
    reservation_line doms.inventory_reservation_lines%ROWTYPE;
    split_row record;
    other_reserved_allocation numeric(24,8);
    other_split_allocation numeric(24,8);
    reservation_remaining numeric(24,8);
    allocation_remaining numeric(24,8);
    override_complete boolean;
BEGIN
    IF TG_OP = 'UPDATE' AND (
        OLD.tenant_id IS DISTINCT FROM NEW.tenant_id OR
        OLD.fulfillment_plan_line_id IS DISTINCT FROM NEW.fulfillment_plan_line_id OR
        OLD.fulfillment_plan_source_split_id IS DISTINCT FROM NEW.fulfillment_plan_source_split_id OR
        OLD.sales_order_line_id IS DISTINCT FROM NEW.sales_order_line_id OR
        OLD.inventory_reservation_line_id IS DISTINCT FROM NEW.inventory_reservation_line_id OR
        OLD.inventory_position_id IS DISTINCT FROM NEW.inventory_position_id OR
        OLD.inventory_source_id IS DISTINCT FROM NEW.inventory_source_id OR
        OLD.fulfillment_node_id IS DISTINCT FROM NEW.fulfillment_node_id OR
        OLD.item_id IS DISTINCT FROM NEW.item_id OR
        OLD.allocated_quantity IS DISTINCT FROM NEW.allocated_quantity OR
        OLD.uom_code IS DISTINCT FROM NEW.uom_code OR
        OLD.override_approved_by IS DISTINCT FROM NEW.override_approved_by OR
        OLD.override_approved_at IS DISTINCT FROM NEW.override_approved_at OR
        OLD.override_reason IS DISTINCT FROM NEW.override_reason OR
        OLD.idempotency_key IS DISTINCT FROM NEW.idempotency_key
    ) THEN
        RAISE EXCEPTION 'Fulfillment allocation identity, quantity, override, and creation key are immutable'
            USING ERRCODE = '55000';
    END IF;
    IF TG_OP = 'UPDATE' AND (
        OLD.released_quantity IS DISTINCT FROM NEW.released_quantity OR
        OLD.consumed_quantity IS DISTINCT FROM NEW.consumed_quantity OR
        OLD.allocation_status IS DISTINCT FROM NEW.allocation_status
    ) AND (
        btrim(COALESCE(NEW.last_operation_key, '')) = '' OR
        NEW.last_operation_key IS NOT DISTINCT FROM OLD.last_operation_key
    ) THEN
        RAISE EXCEPTION 'Allocation state mutation requires a new idempotent operation key'
            USING ERRCODE = '23514';
    END IF;

    override_complete := NEW.override_approved_by IS NOT NULL
                         AND NEW.override_approved_at IS NOT NULL
                         AND btrim(COALESCE(NEW.override_reason, '')) <> '';
    IF override_complete AND NEW.override_approved_at > now() THEN
        RAISE EXCEPTION 'Allocation override approval cannot be in the future'
            USING ERRCODE = '23514';
    END IF;

    SELECT * INTO position_row
      FROM doms.inventory_positions
     WHERE tenant_id = NEW.tenant_id
       AND id = NEW.inventory_position_id
     FOR UPDATE;
    IF NOT FOUND OR position_row.inventory_source_id <> NEW.inventory_source_id
       OR position_row.fulfillment_node_id <> NEW.fulfillment_node_id
       OR position_row.item_id <> NEW.item_id
       OR position_row.uom_code <> NEW.uom_code THEN
        RAISE EXCEPTION 'Allocation source, node, item, or UOM differs from inventory position'
            USING ERRCODE = '23514';
    END IF;

    SELECT fulfillment_plan_line_id, inventory_position_id, inventory_source_id,
           fulfillment_node_id, item_id, uom_code, split_quantity
      INTO split_row
      FROM doms.fulfillment_plan_source_splits
     WHERE tenant_id = NEW.tenant_id
       AND id = NEW.fulfillment_plan_source_split_id;
    IF NOT FOUND OR split_row.fulfillment_plan_line_id <> NEW.fulfillment_plan_line_id
       OR split_row.inventory_position_id <> NEW.inventory_position_id
       OR split_row.inventory_source_id <> NEW.inventory_source_id
       OR split_row.fulfillment_node_id <> NEW.fulfillment_node_id
       OR split_row.item_id <> NEW.item_id
       OR split_row.uom_code <> NEW.uom_code THEN
        RAISE EXCEPTION 'Allocation differs from its fulfillment source split'
            USING ERRCODE = '23514';
    END IF;

    allocation_remaining := CASE
        WHEN NEW.allocation_status IN ('ACTIVE','PARTIALLY_CONSUMED','PARTIALLY_RELEASED')
        THEN NEW.allocated_quantity - NEW.released_quantity - NEW.consumed_quantity
        ELSE 0
    END;
    IF NEW.allocation_status IN ('ACTIVE','PARTIALLY_CONSUMED','PARTIALLY_RELEASED')
       AND allocation_remaining <= 0 THEN
        RAISE EXCEPTION 'Active allocation must have a positive remaining quantity'
            USING ERRCODE = '23514';
    END IF;
    IF NEW.allocation_status IN ('CONSUMED','RELEASED','CANCELLED')
       AND NEW.released_quantity + NEW.consumed_quantity <> NEW.allocated_quantity THEN
        RAISE EXCEPTION 'Terminal allocation must have no remaining quantity'
            USING ERRCODE = '23514';
    END IF;

    SELECT COALESCE(sum(
               allocated_quantity - released_quantity - consumed_quantity
           ), 0)
      INTO other_split_allocation
      FROM doms.fulfillment_allocations
     WHERE tenant_id = NEW.tenant_id
       AND fulfillment_plan_source_split_id = NEW.fulfillment_plan_source_split_id
       AND id <> NEW.id
       AND allocation_status IN ('ACTIVE','PARTIALLY_CONSUMED','PARTIALLY_RELEASED');
    IF other_split_allocation + allocation_remaining > split_row.split_quantity
       AND NOT override_complete THEN
        RAISE EXCEPTION 'Active allocations exceed source-split quantity without approved override'
            USING ERRCODE = '23514';
    END IF;

    IF NEW.inventory_reservation_line_id IS NULL THEN
        IF allocation_remaining > 0 AND NOT override_complete THEN
            RAISE EXCEPTION 'Allocation without reservation requires approved override evidence'
                USING ERRCODE = '23514';
        END IF;
    ELSE
        SELECT * INTO reservation_line
          FROM doms.inventory_reservation_lines
         WHERE tenant_id = NEW.tenant_id
           AND id = NEW.inventory_reservation_line_id
         FOR UPDATE;
        IF NOT FOUND
           OR reservation_line.inventory_position_id <> NEW.inventory_position_id
           OR reservation_line.inventory_source_id <> NEW.inventory_source_id
           OR reservation_line.fulfillment_node_id <> NEW.fulfillment_node_id
           OR reservation_line.item_id <> NEW.item_id
           OR reservation_line.sales_order_line_id <> NEW.sales_order_line_id
           OR reservation_line.uom_code <> NEW.uom_code THEN
            RAISE EXCEPTION 'Allocation differs from its inventory reservation line'
                USING ERRCODE = '23514';
        END IF;
        IF allocation_remaining > 0 AND reservation_line.reservation_status NOT IN (
            'ACTIVE','PARTIALLY_CONSUMED','PARTIALLY_RELEASED'
        ) AND NOT override_complete THEN
            RAISE EXCEPTION 'Allocation requires an active reservation or approved override'
                USING ERRCODE = '23514';
        END IF;
        IF allocation_remaining > 0 AND reservation_line.expires_at <= now()
           AND NOT override_complete THEN
            RAISE EXCEPTION 'Allocation reservation is expired'
                USING ERRCODE = '23514';
        END IF;

        reservation_remaining := reservation_line.reserved_quantity -
                                 reservation_line.released_quantity -
                                 reservation_line.consumed_quantity;
        SELECT COALESCE(sum(
                   allocated_quantity - released_quantity - consumed_quantity
               ), 0)
          INTO other_reserved_allocation
          FROM doms.fulfillment_allocations
         WHERE tenant_id = NEW.tenant_id
           AND inventory_reservation_line_id = NEW.inventory_reservation_line_id
           AND id <> NEW.id
           AND allocation_status IN ('ACTIVE','PARTIALLY_CONSUMED','PARTIALLY_RELEASED');

        IF other_reserved_allocation + allocation_remaining > reservation_remaining
           AND NOT override_complete THEN
            RAISE EXCEPTION 'Allocation sum % exceeds reservation remainder % without approved override',
                other_reserved_allocation + allocation_remaining, reservation_remaining
                USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.project_fulfillment_allocation()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    projection_before numeric(24,8);
    projection_after numeric(24,8);
    event_kind varchar(30);
    event_quantity numeric(24,8);
BEGIN
    SELECT allocated_quantity
      INTO projection_before
      FROM doms.inventory_positions
     WHERE tenant_id = NEW.tenant_id
       AND id = NEW.inventory_position_id
     FOR UPDATE;

    SELECT COALESCE(sum(
               allocated_quantity - released_quantity - consumed_quantity
           ), 0)
      INTO projection_after
      FROM doms.fulfillment_allocations
     WHERE tenant_id = NEW.tenant_id
       AND inventory_position_id = NEW.inventory_position_id
       AND allocation_status IN ('ACTIVE','PARTIALLY_CONSUMED','PARTIALLY_RELEASED');

    UPDATE doms.inventory_positions
       SET allocated_quantity = projection_after,
           updated_at = now(),
           row_version = row_version + 1
     WHERE tenant_id = NEW.tenant_id
       AND id = NEW.inventory_position_id;

    IF TG_OP = 'INSERT' THEN
        event_kind := 'ALLOCATED';
        event_quantity := NEW.allocated_quantity;
    ELSIF NEW.consumed_quantity > OLD.consumed_quantity THEN
        event_kind := 'CONSUMED';
        event_quantity := NEW.consumed_quantity - OLD.consumed_quantity;
    ELSIF NEW.released_quantity > OLD.released_quantity THEN
        event_kind := CASE WHEN NEW.allocation_status = 'CANCELLED'
                           THEN 'CANCELLED' ELSE 'RELEASED' END;
        event_quantity := NEW.released_quantity - OLD.released_quantity;
    ELSE
        event_kind := CASE WHEN NEW.allocation_status = 'FAILED'
                           THEN 'FAILED' ELSE 'STATUS_CHANGED' END;
        event_quantity := 0;
    END IF;

    INSERT INTO doms.fulfillment_allocation_events (
        tenant_id, fulfillment_allocation_id, event_type, from_status, to_status,
        quantity, idempotency_key, reason_code, actor_user_id
    ) VALUES (
        NEW.tenant_id, NEW.id, event_kind,
        CASE WHEN TG_OP = 'INSERT' THEN NULL ELSE OLD.allocation_status END,
        NEW.allocation_status, event_quantity,
        COALESCE(NEW.last_operation_key, NEW.idempotency_key),
        NEW.last_reason_code, NEW.last_actor_user_id
    ) ON CONFLICT DO NOTHING;

    IF projection_before IS DISTINCT FROM projection_after THEN
        INSERT INTO doms.inventory_position_events (
            tenant_id, inventory_position_id, event_type, position_bucket,
            quantity_before, quantity_delta, quantity_after, idempotency_key,
            actor_user_id, occurred_at
        ) VALUES (
            NEW.tenant_id, NEW.inventory_position_id, 'ALLOCATION_CHANGED', 'ALLOCATED',
            projection_before, projection_after - projection_before, projection_after,
            'ALLOCATION:' || NEW.id::text || ':' ||
                COALESCE(NEW.last_operation_key, NEW.idempotency_key),
            NEW.last_actor_user_id, now()
        ) ON CONFLICT DO NOTHING;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.transition_fulfillment_allocation(
    p_tenant_id uuid,
    p_fulfillment_allocation_id uuid,
    p_action varchar,
    p_quantity numeric,
    p_idempotency_key varchar,
    p_actor_user_id uuid DEFAULT NULL,
    p_reason_code varchar DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, doms, pg_temp
AS $function$
DECLARE
    allocation_row doms.fulfillment_allocations%ROWTYPE;
    transition_quantity numeric(24,8);
    remaining_quantity numeric(24,8);
    reservation_remaining numeric(24,8);
    reservation_consume_quantity numeric(24,8);
    next_status varchar(30);
    existing_event_id uuid;
BEGIN
    IF p_tenant_id IS NULL OR p_fulfillment_allocation_id IS NULL
       OR btrim(COALESCE(p_action, '')) = ''
       OR btrim(COALESCE(p_idempotency_key, '')) = '' THEN
        RAISE EXCEPTION 'Tenant, allocation, action, and idempotency key are required'
            USING ERRCODE = '22023';
    END IF;
    IF upper(p_action) NOT IN ('CONSUME','RELEASE','CANCEL') THEN
        RAISE EXCEPTION 'Unsupported allocation transition action %', p_action
            USING ERRCODE = '22023';
    END IF;

    SELECT id INTO existing_event_id
      FROM doms.fulfillment_allocation_events
     WHERE tenant_id = p_tenant_id
       AND fulfillment_allocation_id = p_fulfillment_allocation_id
       AND idempotency_key = p_idempotency_key
     ORDER BY occurred_at DESC
     LIMIT 1;
    IF existing_event_id IS NOT NULL THEN
        RETURN existing_event_id;
    END IF;

    SELECT * INTO allocation_row
      FROM doms.fulfillment_allocations
     WHERE tenant_id = p_tenant_id
       AND id = p_fulfillment_allocation_id
     FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Fulfillment allocation is unavailable in the tenant'
            USING ERRCODE = '42501';
    END IF;
    IF allocation_row.allocation_status NOT IN (
        'ACTIVE','PARTIALLY_CONSUMED','PARTIALLY_RELEASED'
    ) THEN
        RAISE EXCEPTION 'Allocation in status % cannot transition',
            allocation_row.allocation_status USING ERRCODE = '55000';
    END IF;

    remaining_quantity := allocation_row.allocated_quantity -
                          allocation_row.released_quantity -
                          allocation_row.consumed_quantity;
    transition_quantity := COALESCE(p_quantity, remaining_quantity);
    IF transition_quantity <= 0 OR transition_quantity > remaining_quantity THEN
        RAISE EXCEPTION 'Transition quantity % exceeds remaining allocation quantity %',
            transition_quantity, remaining_quantity USING ERRCODE = '23514';
    END IF;

    IF upper(p_action) = 'CONSUME' THEN
        next_status := CASE WHEN transition_quantity = remaining_quantity
                            THEN 'CONSUMED' ELSE 'PARTIALLY_CONSUMED' END;
        UPDATE doms.fulfillment_allocations
           SET consumed_quantity = consumed_quantity + transition_quantity,
               allocation_status = next_status,
               last_operation_key = p_idempotency_key,
               last_actor_user_id = p_actor_user_id,
               last_reason_code = COALESCE(p_reason_code, 'CONSUMED'),
               updated_at = now(),
               row_version = row_version + 1
         WHERE id = allocation_row.id;

        IF allocation_row.inventory_reservation_line_id IS NOT NULL THEN
            SELECT reserved_quantity - released_quantity - consumed_quantity
              INTO reservation_remaining
              FROM doms.inventory_reservation_lines
             WHERE tenant_id = p_tenant_id
               AND id = allocation_row.inventory_reservation_line_id
             FOR UPDATE;
            reservation_consume_quantity := LEAST(
                transition_quantity, GREATEST(COALESCE(reservation_remaining, 0), 0)
            );
            IF reservation_consume_quantity > 0 THEN
                PERFORM doms.transition_inventory_reservation_line(
                    p_tenant_id,
                    allocation_row.inventory_reservation_line_id,
                    'CONSUME',
                    reservation_consume_quantity,
                    left(p_idempotency_key || ':RESERVATION', 200),
                    p_actor_user_id,
                    COALESCE(p_reason_code, 'ALLOCATION_CONSUMED')
                );
            END IF;
        END IF;
    ELSE
        next_status := CASE
            WHEN transition_quantity < remaining_quantity THEN 'PARTIALLY_RELEASED'
            WHEN upper(p_action) = 'CANCEL' THEN 'CANCELLED'
            ELSE 'RELEASED'
        END;
        UPDATE doms.fulfillment_allocations
           SET released_quantity = released_quantity + transition_quantity,
               allocation_status = next_status,
               last_operation_key = p_idempotency_key,
               last_actor_user_id = p_actor_user_id,
               last_reason_code = COALESCE(p_reason_code, upper(p_action)),
               updated_at = now(),
               row_version = row_version + 1
         WHERE id = allocation_row.id;
    END IF;

    SELECT id INTO existing_event_id
      FROM doms.fulfillment_allocation_events
     WHERE tenant_id = p_tenant_id
       AND fulfillment_allocation_id = p_fulfillment_allocation_id
       AND idempotency_key = p_idempotency_key
     ORDER BY occurred_at DESC
     LIMIT 1;
    RETURN COALESCE(existing_event_id, p_fulfillment_allocation_id);
END;
$function$;

REVOKE ALL ON FUNCTION doms.transition_fulfillment_allocation(
    uuid, uuid, varchar, numeric, varchar, uuid, varchar
) FROM PUBLIC;

-- -----------------------------------------------------------------------------
-- Triggers
-- -----------------------------------------------------------------------------

DROP TRIGGER IF EXISTS trg_validate_journey_run_scope ON doms.order_journey_runs;
CREATE TRIGGER trg_validate_journey_run_scope
BEFORE INSERT OR UPDATE OF tenant_id, journey_definition_id, journey_version_id
ON doms.order_journey_runs
FOR EACH ROW EXECUTE PROCEDURE doms.validate_journey_run_scope();

DROP TRIGGER IF EXISTS trg_validate_sourcing_request_scope ON doms.sourcing_requests;
CREATE TRIGGER trg_validate_sourcing_request_scope
BEFORE INSERT OR UPDATE OF tenant_id, sales_order_id, sales_order_line_id, item_id,
    requested_quantity, uom_code
ON doms.sourcing_requests
FOR EACH ROW EXECUTE PROCEDURE doms.validate_sourcing_request_scope();

DROP TRIGGER IF EXISTS trg_validate_atp_result_scope ON doms.atp_check_results;
CREATE TRIGGER trg_validate_atp_result_scope
BEFORE INSERT OR UPDATE OF tenant_id, atp_check_request_line_id,
    inventory_position_id, inventory_source_id, fulfillment_node_id, item_id
ON doms.atp_check_results
FOR EACH ROW EXECUTE PROCEDURE doms.validate_atp_result_scope();

DROP TRIGGER IF EXISTS trg_validate_sourcing_candidate_scope ON doms.sourcing_candidates;
CREATE TRIGGER trg_validate_sourcing_candidate_scope
BEFORE INSERT OR UPDATE OF tenant_id, sourcing_request_id, inventory_position_id,
    inventory_source_id, fulfillment_node_id, item_id, substitution_candidate_id
ON doms.sourcing_candidates
FOR EACH ROW EXECUTE PROCEDURE doms.validate_sourcing_candidate_scope();

DROP TRIGGER IF EXISTS trg_validate_plan_line_scope ON doms.fulfillment_plan_lines;
CREATE TRIGGER trg_validate_plan_line_scope
BEFORE INSERT OR UPDATE OF tenant_id, fulfillment_plan_id, sales_order_line_id,
    item_id, requested_quantity, uom_code
ON doms.fulfillment_plan_lines
FOR EACH ROW EXECUTE PROCEDURE doms.validate_fulfillment_plan_line_scope();

DROP TRIGGER IF EXISTS trg_validate_plan_split_scope
ON doms.fulfillment_plan_source_splits;
CREATE TRIGGER trg_validate_plan_split_scope
BEFORE INSERT OR UPDATE OF tenant_id, fulfillment_plan_line_id, sourcing_candidate_id,
    sourcing_decision_id, inventory_position_id, inventory_source_id, fulfillment_node_id, item_id,
    split_quantity, uom_code
ON doms.fulfillment_plan_source_splits
FOR EACH ROW EXECUTE PROCEDURE doms.validate_fulfillment_source_split_scope();

DROP TRIGGER IF EXISTS trg_validate_reservation_request_line
ON doms.reservation_request_lines;
CREATE TRIGGER trg_validate_reservation_request_line
BEFORE INSERT OR UPDATE OF tenant_id, reservation_request_id, sales_order_line_id,
    fulfillment_plan_source_split_id, inventory_position_id, item_id,
    requested_quantity, uom_code
ON doms.reservation_request_lines
FOR EACH ROW EXECUTE PROCEDURE doms.validate_reservation_request_line_scope();

DROP TRIGGER IF EXISTS trg_validate_inventory_reservation_scope
ON doms.inventory_reservations;
CREATE TRIGGER trg_validate_inventory_reservation_scope
BEFORE INSERT OR UPDATE ON doms.inventory_reservations
FOR EACH ROW EXECUTE PROCEDURE doms.validate_inventory_reservation_scope();

DROP TRIGGER IF EXISTS trg_check_plan_split_total
ON doms.fulfillment_plan_source_splits;
CREATE CONSTRAINT TRIGGER trg_check_plan_split_total
AFTER INSERT OR UPDATE OR DELETE ON doms.fulfillment_plan_source_splits
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE PROCEDURE doms.check_fulfillment_split_total();

DROP TRIGGER IF EXISTS trg_check_sourcing_decision_total ON doms.sourcing_decisions;
CREATE CONSTRAINT TRIGGER trg_check_sourcing_decision_total
AFTER INSERT OR UPDATE OR DELETE ON doms.sourcing_decisions
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE PROCEDURE doms.check_sourcing_decision_total();

DROP TRIGGER IF EXISTS trg_validate_inventory_position_projection
ON doms.inventory_positions;
CREATE TRIGGER trg_validate_inventory_position_projection
BEFORE INSERT OR UPDATE OF atp_quantity, reserved_quantity, allocated_quantity
ON doms.inventory_positions
FOR EACH ROW EXECUTE PROCEDURE doms.validate_inventory_position_projection();

DROP TRIGGER IF EXISTS trg_validate_inventory_reservation_line
ON doms.inventory_reservation_lines;
CREATE TRIGGER trg_validate_inventory_reservation_line
BEFORE INSERT OR UPDATE ON doms.inventory_reservation_lines
FOR EACH ROW EXECUTE PROCEDURE doms.validate_inventory_reservation_line();

DROP TRIGGER IF EXISTS trg_project_inventory_reservation_line
ON doms.inventory_reservation_lines;
CREATE TRIGGER trg_project_inventory_reservation_line
AFTER INSERT OR UPDATE ON doms.inventory_reservation_lines
FOR EACH ROW EXECUTE PROCEDURE doms.project_inventory_reservation_line();

DROP TRIGGER IF EXISTS trg_validate_fulfillment_allocation
ON doms.fulfillment_allocations;
CREATE TRIGGER trg_validate_fulfillment_allocation
BEFORE INSERT OR UPDATE ON doms.fulfillment_allocations
FOR EACH ROW EXECUTE PROCEDURE doms.validate_fulfillment_allocation();

DROP TRIGGER IF EXISTS trg_project_fulfillment_allocation
ON doms.fulfillment_allocations;
CREATE TRIGGER trg_project_fulfillment_allocation
AFTER INSERT OR UPDATE ON doms.fulfillment_allocations
FOR EACH ROW EXECUTE PROCEDURE doms.project_fulfillment_allocation();

DO $block$
DECLARE
    target_table text;
BEGIN
    FOREACH target_table IN ARRAY ARRAY[
        'order_journey_run_errors',
        'inventory_position_events',
        'inventory_reservation_events',
        'fulfillment_allocation_events'
    ]::text[]
    LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS trg_doms_append_only_row ON doms.%I', target_table);
        EXECUTE format(
            'CREATE TRIGGER trg_doms_append_only_row BEFORE UPDATE OR DELETE ON doms.%I '
            'FOR EACH ROW EXECUTE PROCEDURE doms.prevent_orchestration_append_only_change()',
            target_table
        );
        EXECUTE format('DROP TRIGGER IF EXISTS trg_doms_append_only_truncate ON doms.%I', target_table);
        EXECUTE format(
            'CREATE TRIGGER trg_doms_append_only_truncate BEFORE TRUNCATE ON doms.%I '
            'FOR EACH STATEMENT EXECUTE PROCEDURE doms.prevent_orchestration_append_only_change()',
            target_table
        );
    END LOOP;
END;
$block$;

DO $block$
DECLARE
    target_table text;
BEGIN
    FOREACH target_table IN ARRAY ARRAY[
        'inventory_supply',
        'inventory_demand',
        'reservation_requests',
        'reservation_request_lines',
        'inventory_reservations',
        'inventory_reservation_lines',
        'fulfillment_allocations',
        'backorders',
        'preorders'
    ]::text[]
    LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS trg_doms_state_no_delete ON doms.%I', target_table);
        EXECUTE format(
            'CREATE TRIGGER trg_doms_state_no_delete BEFORE DELETE ON doms.%I '
            'FOR EACH ROW EXECUTE PROCEDURE doms.prevent_orchestration_delete()',
            target_table
        );
        EXECUTE format('DROP TRIGGER IF EXISTS trg_doms_state_no_truncate ON doms.%I', target_table);
        EXECUTE format(
            'CREATE TRIGGER trg_doms_state_no_truncate BEFORE TRUNCATE ON doms.%I '
            'FOR EACH STATEMENT EXECUTE PROCEDURE doms.prevent_orchestration_delete()',
            target_table
        );
    END LOOP;
END;
$block$;

-- -----------------------------------------------------------------------------
-- Operational indexes
-- -----------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS ix_doms_journey_runs_queue
    ON doms.order_journey_runs (tenant_id, run_status, created_at, id)
    WHERE run_status IN ('PENDING','RUNNING','WAITING','BLOCKED','COMPENSATING');
CREATE INDEX IF NOT EXISTS ix_doms_journey_runs_order
    ON doms.order_journey_runs (tenant_id, sales_order_id, created_at DESC, id);
CREATE INDEX IF NOT EXISTS ix_doms_journey_step_runs_queue
    ON doms.order_journey_step_runs (tenant_id, step_status, next_retry_at, created_at, id)
    WHERE step_status IN ('PENDING','READY','RUNNING','WAITING','RETRY_SCHEDULED');
CREATE INDEX IF NOT EXISTS ix_doms_journey_errors_timeline
    ON doms.order_journey_run_errors (tenant_id, journey_run_id, occurred_at, id);

CREATE INDEX IF NOT EXISTS ix_doms_inventory_positions_lookup
    ON doms.inventory_positions (
        tenant_id, fulfillment_node_id, item_id, position_status, inventory_source_id, id
    );
CREATE INDEX IF NOT EXISTS ix_doms_inventory_positions_stale
    ON doms.inventory_positions (tenant_id, freshness_expires_at, id)
    WHERE position_status IN ('ACTIVE','STALE');
CREATE INDEX IF NOT EXISTS ix_doms_inventory_events_timeline
    ON doms.inventory_position_events (
        tenant_id, inventory_position_id, occurred_at, id
    );
CREATE INDEX IF NOT EXISTS ix_doms_inventory_supply_available
    ON doms.inventory_supply (
        tenant_id, inventory_position_id, supply_status, available_from, expires_at, id
    ) WHERE supply_status IN ('EXPECTED','CONFIRMED','AVAILABLE','PARTIALLY_CONSUMED');
CREATE INDEX IF NOT EXISTS ix_doms_inventory_demand_open
    ON doms.inventory_demand (
        tenant_id, inventory_position_id, demand_status, priority, required_at, id
    ) WHERE demand_status IN ('OPEN','PARTIALLY_FULFILLED');

CREATE INDEX IF NOT EXISTS ix_doms_atp_requests_queue
    ON doms.atp_check_requests (tenant_id, request_status, requested_at, id)
    WHERE request_status IN ('PENDING','RUNNING');
CREATE INDEX IF NOT EXISTS ix_doms_atp_results_line
    ON doms.atp_check_results (
        tenant_id, atp_check_request_line_id, selected DESC, result_rank, id
    );
CREATE INDEX IF NOT EXISTS ix_doms_sourcing_requests_queue
    ON doms.sourcing_requests (tenant_id, request_status, created_at, id)
    WHERE request_status IN ('PENDING','EVALUATING','PARTIAL');
CREATE INDEX IF NOT EXISTS ix_doms_sourcing_candidates_request
    ON doms.sourcing_candidates (
        tenant_id, sourcing_request_id, candidate_status, candidate_rank, id
    );

CREATE INDEX IF NOT EXISTS ix_doms_fulfillment_plans_order
    ON doms.fulfillment_plans (tenant_id, sales_order_id, plan_status, plan_revision DESC, id);
CREATE INDEX IF NOT EXISTS ix_doms_fulfillment_splits_position
    ON doms.fulfillment_plan_source_splits (
        tenant_id, inventory_position_id, split_status, id
    );
CREATE INDEX IF NOT EXISTS ix_doms_reservation_lines_active_position
    ON doms.inventory_reservation_lines (
        tenant_id, inventory_position_id, expires_at, inventory_reservation_id, id
    ) WHERE reservation_status IN ('ACTIVE','PARTIALLY_CONSUMED','PARTIALLY_RELEASED');
CREATE INDEX IF NOT EXISTS ix_doms_reservation_lines_active_order
    ON doms.inventory_reservation_lines (
        tenant_id, sales_order_line_id, expires_at, id
    ) WHERE reservation_status IN ('ACTIVE','PARTIALLY_CONSUMED','PARTIALLY_RELEASED');
CREATE INDEX IF NOT EXISTS ix_doms_reservations_expiry
    ON doms.inventory_reservations (tenant_id, reservation_status, expires_at, id)
    WHERE reservation_status IN ('PENDING','ACTIVE','PARTIALLY_CONSUMED','PARTIALLY_RELEASED');
CREATE INDEX IF NOT EXISTS ix_doms_allocations_active_reservation
    ON doms.fulfillment_allocations (
        tenant_id, inventory_reservation_line_id, allocation_status, id
    ) WHERE allocation_status IN ('ACTIVE','PARTIALLY_CONSUMED','PARTIALLY_RELEASED');
CREATE INDEX IF NOT EXISTS ix_doms_allocations_active_position
    ON doms.fulfillment_allocations (
        tenant_id, inventory_position_id, allocation_status, id
    ) WHERE allocation_status IN ('ACTIVE','PARTIALLY_CONSUMED','PARTIALLY_RELEASED');
CREATE INDEX IF NOT EXISTS ix_doms_backorders_queue
    ON doms.backorders (
        tenant_id, backorder_status, priority, expected_available_at, created_at, id
    ) WHERE backorder_status IN ('OPEN','PARTIALLY_RELEASED');
CREATE INDEX IF NOT EXISTS ix_doms_preorders_queue
    ON doms.preorders (
        tenant_id, preorder_status, available_from, priority, id
    ) WHERE preorder_status IN ('OPEN','SCHEDULED','PARTIALLY_RELEASED');
CREATE INDEX IF NOT EXISTS ix_doms_substitution_original
    ON doms.item_substitutions (
        tenant_id, original_item_id, substitution_status, effective_from, id
    );

COMMENT ON TABLE doms.inventory_positions IS
    'OMS promise control row at inventory source + fulfillment node + item. It is not a WMS lot/location/serial stock ledger.';
COMMENT ON COLUMN doms.inventory_positions.atp_quantity IS
    'Gross promise capacity before active DOMS reservations. Reservation triggers lock this row and require active reservation sum <= ATP.';
COMMENT ON TABLE doms.inventory_position_events IS
    'Append-only evidence for source, ATP, reservation, allocation, and reconciliation changes.';
COMMENT ON TABLE doms.inventory_reservation_events IS
    'Append-only reservation lifecycle. Release, expiry, cancellation, and consumption are events/status transitions, never deletes.';
COMMENT ON TABLE doms.fulfillment_allocations IS
    'Promise-level allocation. Physical lot/location allocation remains in WMS.';
