-- ETMS forward migration: close operational-evidence gaps left intentionally
-- reserved by the immutable 00..11 baseline. PostgreSQL 11 compatible.
--
-- Evidence rows in this migration are append-only. Corrections, reversals, and
-- state changes are represented by additional rows, never in-place mutation.

-- ---------------------------------------------------------------------------
-- Claim reserve ledger.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS etms.claim_reserve_movements (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    reserve_id uuid NOT NULL,
    claim_id uuid NOT NULL,
    movement_sequence integer NOT NULL,
    movement_type varchar(30) NOT NULL,
    opening_reserve_amount numeric(20,4) NOT NULL,
    movement_amount numeric(20,4) NOT NULL,
    closing_reserve_amount numeric(20,4) NOT NULL,
    currency_code char(3) NOT NULL REFERENCES etms.currencies(currency_code),
    functional_amount numeric(20,4),
    functional_currency_code char(3) REFERENCES etms.currencies(currency_code),
    fx_rate numeric(24,12),
    effective_at timestamptz NOT NULL,
    reversal_of_movement_id uuid,
    reason_code varchar(80),
    reason_text text NOT NULL,
    external_reference varchar(200),
    approved_by uuid REFERENCES etms.users(id),
    recorded_by uuid REFERENCES etms.users(id),
    occurred_at timestamptz NOT NULL DEFAULT now(),
    received_at timestamptz NOT NULL DEFAULT now(),
    event_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, reserve_id, movement_sequence),
    CONSTRAINT fk_claim_reserve_movement_reserve
        FOREIGN KEY (tenant_id, reserve_id)
        REFERENCES etms.claim_reserves(tenant_id, id),
    CONSTRAINT fk_claim_reserve_movement_claim
        FOREIGN KEY (tenant_id, claim_id)
        REFERENCES etms.claims(tenant_id, id),
    CONSTRAINT fk_claim_reserve_movement_reversal
        FOREIGN KEY (tenant_id, reversal_of_movement_id)
        REFERENCES etms.claim_reserve_movements(tenant_id, id),
    CONSTRAINT ck_claim_reserve_movement_sequence CHECK (movement_sequence > 0),
    CONSTRAINT ck_claim_reserve_movement_type CHECK (
        movement_type IN (
            'ESTABLISH','INCREASE','DECREASE','RELEASE','REINSTATE',
            'REVALUE','CORRECTION','REVERSAL'
        )
    ),
    CONSTRAINT ck_claim_reserve_movement_balance CHECK (
        opening_reserve_amount >= 0
        AND closing_reserve_amount >= 0
        AND movement_amount <> 0
        AND closing_reserve_amount = opening_reserve_amount + movement_amount
    ),
    CONSTRAINT ck_claim_reserve_movement_direction CHECK (
        (movement_type IN ('ESTABLISH','INCREASE','REINSTATE') AND movement_amount > 0)
        OR (movement_type IN ('DECREASE','RELEASE') AND movement_amount < 0)
        OR movement_type IN ('REVALUE','CORRECTION','REVERSAL')
    ),
    CONSTRAINT ck_claim_reserve_movement_reversal CHECK (
        (movement_type = 'REVERSAL') = (reversal_of_movement_id IS NOT NULL)
    ),
    CONSTRAINT ck_claim_reserve_movement_establish CHECK (
        (movement_type = 'ESTABLISH') = (movement_sequence = 1)
    ),
    CONSTRAINT ck_claim_reserve_movement_functional CHECK (
        (functional_amount IS NULL AND functional_currency_code IS NULL AND fx_rate IS NULL)
        OR (functional_amount IS NOT NULL AND functional_amount <> 0
            AND functional_currency_code IS NOT NULL AND fx_rate IS NOT NULL AND fx_rate > 0)
    ),
    CONSTRAINT ck_claim_reserve_movement_times CHECK (received_at >= occurred_at)
);

CREATE INDEX IF NOT EXISTS ix_claim_reserve_movement_reserve
    ON etms.claim_reserve_movements (tenant_id, reserve_id);
CREATE INDEX IF NOT EXISTS ix_claim_reserve_movement_claim
    ON etms.claim_reserve_movements (tenant_id, claim_id);
CREATE INDEX IF NOT EXISTS ix_claim_reserve_movement_reversal
    ON etms.claim_reserve_movements (tenant_id, reversal_of_movement_id);
CREATE INDEX IF NOT EXISTS ix_claim_reserve_movement_currency
    ON etms.claim_reserve_movements (currency_code);
CREATE INDEX IF NOT EXISTS ix_claim_reserve_movement_functional_currency
    ON etms.claim_reserve_movements (functional_currency_code);
CREATE INDEX IF NOT EXISTS ix_claim_reserve_movement_approved_by
    ON etms.claim_reserve_movements (approved_by);
CREATE INDEX IF NOT EXISTS ix_claim_reserve_movement_recorded_by
    ON etms.claim_reserve_movements (recorded_by);
CREATE INDEX IF NOT EXISTS ix_claim_reserve_movement_occurred
    ON etms.claim_reserve_movements (tenant_id, occurred_at DESC);

-- ---------------------------------------------------------------------------
-- Driver hours-of-service evidence.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS etms.driving_hours_violations (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    violation_group_id uuid NOT NULL DEFAULT etms.generate_uuid(),
    supersedes_violation_id uuid,
    driver_id uuid NOT NULL,
    driver_duty_log_id uuid,
    run_id uuid,
    dispatch_order_id uuid,
    source_event_id uuid,
    evidence_file_id uuid,
    violation_action varchar(30) NOT NULL DEFAULT 'DETECTED',
    violation_type varchar(40) NOT NULL,
    regulation_code varchar(100) NOT NULL,
    rule_version varchar(80),
    jurisdiction_code varchar(40),
    severity varchar(20) NOT NULL DEFAULT 'HIGH',
    window_started_at timestamptz NOT NULL,
    window_ended_at timestamptz NOT NULL,
    allowed_duration numeric(20,6) NOT NULL,
    actual_duration numeric(20,6) NOT NULL,
    excess_duration numeric(20,6) NOT NULL,
    duration_uom_code varchar(20) NOT NULL DEFAULT 'MIN'
        REFERENCES etms.units_of_measure(uom_code),
    required_rest_duration numeric(20,6),
    detection_source varchar(30) NOT NULL,
    source_sequence bigint,
    acknowledged_by uuid REFERENCES etms.users(id),
    recorded_by uuid REFERENCES etms.users(id),
    reason_text text,
    occurred_at timestamptz NOT NULL,
    received_at timestamptz NOT NULL DEFAULT now(),
    event_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, violation_group_id, id),
    CONSTRAINT fk_driving_violation_supersedes
        FOREIGN KEY (tenant_id, supersedes_violation_id)
        REFERENCES etms.driving_hours_violations(tenant_id, id),
    CONSTRAINT fk_driving_violation_driver
        FOREIGN KEY (tenant_id, driver_id)
        REFERENCES etms.drivers(tenant_id, id),
    CONSTRAINT fk_driving_violation_duty_log
        FOREIGN KEY (tenant_id, driver_duty_log_id)
        REFERENCES etms.driver_duty_logs(tenant_id, id),
    CONSTRAINT fk_driving_violation_run
        FOREIGN KEY (tenant_id, run_id)
        REFERENCES etms.transport_runs(tenant_id, id),
    CONSTRAINT fk_driving_violation_dispatch
        FOREIGN KEY (tenant_id, dispatch_order_id)
        REFERENCES etms.dispatch_orders(tenant_id, id),
    CONSTRAINT fk_driving_violation_source_event
        FOREIGN KEY (tenant_id, source_event_id)
        REFERENCES etms.transport_events(tenant_id, id),
    CONSTRAINT fk_driving_violation_evidence_file
        FOREIGN KEY (tenant_id, evidence_file_id)
        REFERENCES etms.files(tenant_id, id),
    CONSTRAINT ck_driving_violation_action CHECK (
        violation_action IN ('DETECTED','ACKNOWLEDGED','WAIVED','CORRECTED','RESOLVED')
    ),
    CONSTRAINT ck_driving_violation_type CHECK (
        violation_type IN (
            'DAILY_DRIVING','WEEKLY_DRIVING','CONTINUOUS_DRIVING','DAILY_DUTY',
            'REST_BREAK','DAILY_REST','WEEKLY_REST','NIGHT_WORK','OTHER'
        )
    ),
    CONSTRAINT ck_driving_violation_severity CHECK (
        severity IN ('LOW','MEDIUM','HIGH','CRITICAL')
    ),
    CONSTRAINT ck_driving_violation_window CHECK (window_ended_at >= window_started_at),
    CONSTRAINT ck_driving_violation_duration CHECK (
        allowed_duration >= 0 AND actual_duration >= 0 AND excess_duration > 0
        AND actual_duration = allowed_duration + excess_duration
        AND (required_rest_duration IS NULL OR required_rest_duration >= 0)
    ),
    CONSTRAINT ck_driving_violation_source_sequence CHECK (
        source_sequence IS NULL OR source_sequence >= 0
    ),
    CONSTRAINT ck_driving_violation_correction CHECK (
        (violation_action = 'DETECTED') = (supersedes_violation_id IS NULL)
    ),
    CONSTRAINT ck_driving_violation_supersedes CHECK (
        supersedes_violation_id IS NULL OR supersedes_violation_id <> id
    ),
    CONSTRAINT ck_driving_violation_times CHECK (received_at >= occurred_at)
);

CREATE INDEX IF NOT EXISTS ix_driving_violation_supersedes
    ON etms.driving_hours_violations (tenant_id, supersedes_violation_id);
CREATE INDEX IF NOT EXISTS ix_driving_violation_driver
    ON etms.driving_hours_violations (tenant_id, driver_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS ix_driving_violation_duty_log
    ON etms.driving_hours_violations (tenant_id, driver_duty_log_id);
CREATE INDEX IF NOT EXISTS ix_driving_violation_run
    ON etms.driving_hours_violations (tenant_id, run_id);
CREATE INDEX IF NOT EXISTS ix_driving_violation_dispatch
    ON etms.driving_hours_violations (tenant_id, dispatch_order_id);
CREATE INDEX IF NOT EXISTS ix_driving_violation_source_event
    ON etms.driving_hours_violations (tenant_id, source_event_id);
CREATE INDEX IF NOT EXISTS ix_driving_violation_evidence_file
    ON etms.driving_hours_violations (tenant_id, evidence_file_id);
CREATE INDEX IF NOT EXISTS ix_driving_violation_duration_uom
    ON etms.driving_hours_violations (duration_uom_code);
CREATE INDEX IF NOT EXISTS ix_driving_violation_acknowledged_by
    ON etms.driving_hours_violations (acknowledged_by);
CREATE INDEX IF NOT EXISTS ix_driving_violation_recorded_by
    ON etms.driving_hours_violations (recorded_by);
CREATE UNIQUE INDEX IF NOT EXISTS ux_driving_violation_source_sequence
    ON etms.driving_hours_violations (
        tenant_id, violation_group_id, source_sequence
    ) WHERE source_sequence IS NOT NULL;

-- ---------------------------------------------------------------------------
-- Handling-unit hierarchy and status ledgers.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS etms.handling_unit_parent_history (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    handling_unit_id uuid NOT NULL,
    from_parent_handling_unit_id uuid,
    to_parent_handling_unit_id uuid,
    change_type varchar(30) NOT NULL,
    reason_code varchar(80),
    reason_text text,
    source_event_id uuid,
    source_sequence bigint,
    changed_by uuid REFERENCES etms.users(id),
    occurred_at timestamptz NOT NULL DEFAULT now(),
    received_at timestamptz NOT NULL DEFAULT now(),
    event_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    CONSTRAINT fk_hu_parent_history_unit
        FOREIGN KEY (tenant_id, handling_unit_id)
        REFERENCES etms.handling_units(tenant_id, id),
    CONSTRAINT fk_hu_parent_history_from_parent
        FOREIGN KEY (tenant_id, from_parent_handling_unit_id)
        REFERENCES etms.handling_units(tenant_id, id),
    CONSTRAINT fk_hu_parent_history_to_parent
        FOREIGN KEY (tenant_id, to_parent_handling_unit_id)
        REFERENCES etms.handling_units(tenant_id, id),
    CONSTRAINT fk_hu_parent_history_source_event
        FOREIGN KEY (tenant_id, source_event_id)
        REFERENCES etms.transport_events(tenant_id, id),
    CONSTRAINT ck_hu_parent_history_type CHECK (
        change_type IN ('PARENT_ASSIGNED','PARENT_CHANGED','PARENT_REMOVED','CORRECTION')
    ),
    CONSTRAINT ck_hu_parent_history_change CHECK (
        from_parent_handling_unit_id IS DISTINCT FROM to_parent_handling_unit_id
        AND handling_unit_id IS DISTINCT FROM from_parent_handling_unit_id
        AND handling_unit_id IS DISTINCT FROM to_parent_handling_unit_id
    ),
    CONSTRAINT ck_hu_parent_history_times CHECK (received_at >= occurred_at),
    CONSTRAINT ck_hu_parent_history_source_sequence CHECK (
        source_sequence IS NULL OR source_sequence >= 0
    )
);

CREATE INDEX IF NOT EXISTS ix_hu_parent_history_unit
    ON etms.handling_unit_parent_history (tenant_id, handling_unit_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS ix_hu_parent_history_from_parent
    ON etms.handling_unit_parent_history (tenant_id, from_parent_handling_unit_id);
CREATE INDEX IF NOT EXISTS ix_hu_parent_history_to_parent
    ON etms.handling_unit_parent_history (tenant_id, to_parent_handling_unit_id);
CREATE INDEX IF NOT EXISTS ix_hu_parent_history_source_event
    ON etms.handling_unit_parent_history (tenant_id, source_event_id);
CREATE INDEX IF NOT EXISTS ix_hu_parent_history_changed_by
    ON etms.handling_unit_parent_history (changed_by);

CREATE TABLE IF NOT EXISTS etms.handling_unit_status_history (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    handling_unit_id uuid NOT NULL,
    from_status varchar(30),
    to_status varchar(30) NOT NULL,
    location_id uuid,
    reason_code varchar(80),
    reason_text text,
    source_event_id uuid,
    source_sequence bigint,
    changed_by uuid REFERENCES etms.users(id),
    occurred_at timestamptz NOT NULL DEFAULT now(),
    received_at timestamptz NOT NULL DEFAULT now(),
    event_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    CONSTRAINT fk_hu_status_history_unit
        FOREIGN KEY (tenant_id, handling_unit_id)
        REFERENCES etms.handling_units(tenant_id, id),
    CONSTRAINT fk_hu_status_history_location
        FOREIGN KEY (tenant_id, location_id)
        REFERENCES etms.locations(tenant_id, id),
    CONSTRAINT fk_hu_status_history_source_event
        FOREIGN KEY (tenant_id, source_event_id)
        REFERENCES etms.transport_events(tenant_id, id),
    CONSTRAINT ck_hu_status_history_change CHECK (
        from_status IS NULL OR from_status <> to_status
    ),
    CONSTRAINT ck_hu_status_history_times CHECK (received_at >= occurred_at),
    CONSTRAINT ck_hu_status_history_source_sequence CHECK (
        source_sequence IS NULL OR source_sequence >= 0
    )
);

CREATE INDEX IF NOT EXISTS ix_hu_status_history_unit
    ON etms.handling_unit_status_history (tenant_id, handling_unit_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS ix_hu_status_history_location
    ON etms.handling_unit_status_history (tenant_id, location_id);
CREATE INDEX IF NOT EXISTS ix_hu_status_history_source_event
    ON etms.handling_unit_status_history (tenant_id, source_event_id);
CREATE INDEX IF NOT EXISTS ix_hu_status_history_changed_by
    ON etms.handling_unit_status_history (changed_by);

-- ---------------------------------------------------------------------------
-- Order split/merge evidence.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS etms.order_split_merge_events (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    operation_id uuid NOT NULL,
    event_sequence integer NOT NULL,
    event_type varchar(30) NOT NULL,
    source_order_id uuid NOT NULL,
    result_order_id uuid NOT NULL,
    source_revision_no integer,
    result_revision_no integer,
    allocated_quantity numeric(20,6),
    quantity_uom_code varchar(20) REFERENCES etms.units_of_measure(uom_code),
    allocated_weight numeric(20,6),
    weight_uom_code varchar(20) REFERENCES etms.units_of_measure(uom_code),
    allocated_volume numeric(20,6),
    volume_uom_code varchar(20) REFERENCES etms.units_of_measure(uom_code),
    allocated_value numeric(20,4),
    currency_code char(3) REFERENCES etms.currencies(currency_code),
    source_event_id uuid,
    initiated_by uuid REFERENCES etms.users(id),
    approved_by uuid REFERENCES etms.users(id),
    reason_code varchar(80),
    reason_text text NOT NULL,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    received_at timestamptz NOT NULL DEFAULT now(),
    event_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, operation_id, event_sequence),
    CONSTRAINT fk_order_split_merge_source
        FOREIGN KEY (tenant_id, source_order_id)
        REFERENCES etms.transport_orders(tenant_id, id),
    CONSTRAINT fk_order_split_merge_result
        FOREIGN KEY (tenant_id, result_order_id)
        REFERENCES etms.transport_orders(tenant_id, id),
    CONSTRAINT fk_order_split_merge_source_event
        FOREIGN KEY (tenant_id, source_event_id)
        REFERENCES etms.transport_events(tenant_id, id),
    CONSTRAINT ck_order_split_merge_sequence CHECK (event_sequence > 0),
    CONSTRAINT ck_order_split_merge_type CHECK (
        event_type IN ('SPLIT','MERGE','SPLIT_REVERSED','MERGE_REVERSED','REALLOCATED')
    ),
    CONSTRAINT ck_order_split_merge_distinct CHECK (source_order_id <> result_order_id),
    CONSTRAINT ck_order_split_merge_revisions CHECK (
        (source_revision_no IS NULL OR source_revision_no > 0)
        AND (result_revision_no IS NULL OR result_revision_no > 0)
    ),
    CONSTRAINT ck_order_split_merge_quantity CHECK (
        (allocated_quantity IS NULL) = (quantity_uom_code IS NULL)
        AND (allocated_quantity IS NULL OR allocated_quantity >= 0)
    ),
    CONSTRAINT ck_order_split_merge_weight CHECK (
        (allocated_weight IS NULL) = (weight_uom_code IS NULL)
        AND (allocated_weight IS NULL OR allocated_weight >= 0)
    ),
    CONSTRAINT ck_order_split_merge_volume CHECK (
        (allocated_volume IS NULL) = (volume_uom_code IS NULL)
        AND (allocated_volume IS NULL OR allocated_volume >= 0)
    ),
    CONSTRAINT ck_order_split_merge_value CHECK (
        (allocated_value IS NULL) = (currency_code IS NULL)
        AND (allocated_value IS NULL OR allocated_value >= 0)
    ),
    CONSTRAINT ck_order_split_merge_times CHECK (received_at >= occurred_at)
);

CREATE INDEX IF NOT EXISTS ix_order_split_merge_source
    ON etms.order_split_merge_events (tenant_id, source_order_id);
CREATE INDEX IF NOT EXISTS ix_order_split_merge_result
    ON etms.order_split_merge_events (tenant_id, result_order_id);
CREATE INDEX IF NOT EXISTS ix_order_split_merge_source_event
    ON etms.order_split_merge_events (tenant_id, source_event_id);
CREATE INDEX IF NOT EXISTS ix_order_split_merge_quantity_uom
    ON etms.order_split_merge_events (quantity_uom_code);
CREATE INDEX IF NOT EXISTS ix_order_split_merge_weight_uom
    ON etms.order_split_merge_events (weight_uom_code);
CREATE INDEX IF NOT EXISTS ix_order_split_merge_volume_uom
    ON etms.order_split_merge_events (volume_uom_code);
CREATE INDEX IF NOT EXISTS ix_order_split_merge_currency
    ON etms.order_split_merge_events (currency_code);
CREATE INDEX IF NOT EXISTS ix_order_split_merge_initiated_by
    ON etms.order_split_merge_events (initiated_by);
CREATE INDEX IF NOT EXISTS ix_order_split_merge_approved_by
    ON etms.order_split_merge_events (approved_by);

-- ---------------------------------------------------------------------------
-- POD correction and verification evidence.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS etms.pod_correction_events (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    pod_id uuid NOT NULL,
    correction_no integer NOT NULL,
    correction_type varchar(30) NOT NULL,
    replacement_pod_id uuid,
    pod_item_id uuid,
    field_path text,
    previous_value jsonb,
    corrected_value jsonb,
    quantity_delta numeric(20,6),
    quantity_uom_code varchar(20) REFERENCES etms.units_of_measure(uom_code),
    reason_code varchar(80),
    reason_text text NOT NULL,
    source_event_id uuid,
    evidence_file_id uuid,
    requested_by uuid REFERENCES etms.users(id),
    approved_by uuid REFERENCES etms.users(id),
    occurred_at timestamptz NOT NULL DEFAULT now(),
    received_at timestamptz NOT NULL DEFAULT now(),
    event_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, pod_id, correction_no),
    CONSTRAINT fk_pod_correction_pod
        FOREIGN KEY (tenant_id, pod_id)
        REFERENCES etms.proof_of_deliveries(tenant_id, id),
    CONSTRAINT fk_pod_correction_replacement_pod
        FOREIGN KEY (tenant_id, replacement_pod_id)
        REFERENCES etms.proof_of_deliveries(tenant_id, id),
    CONSTRAINT fk_pod_correction_item
        FOREIGN KEY (tenant_id, pod_item_id)
        REFERENCES etms.pod_items(tenant_id, id),
    CONSTRAINT fk_pod_correction_source_event
        FOREIGN KEY (tenant_id, source_event_id)
        REFERENCES etms.transport_events(tenant_id, id),
    CONSTRAINT fk_pod_correction_evidence_file
        FOREIGN KEY (tenant_id, evidence_file_id)
        REFERENCES etms.files(tenant_id, id),
    CONSTRAINT ck_pod_correction_no CHECK (correction_no > 0),
    CONSTRAINT ck_pod_correction_type CHECK (
        correction_type IN (
            'REQUESTED','APPROVED','APPLIED','REJECTED','CANCELLED','VOIDED','REISSUED'
        )
    ),
    CONSTRAINT ck_pod_correction_replacement CHECK (
        replacement_pod_id IS NULL OR replacement_pod_id <> pod_id
    ),
    CONSTRAINT ck_pod_correction_quantity CHECK (
        (quantity_delta IS NULL) = (quantity_uom_code IS NULL)
    ),
    CONSTRAINT ck_pod_correction_evidence CHECK (
        field_path IS NOT NULL OR pod_item_id IS NOT NULL
        OR replacement_pod_id IS NOT NULL OR evidence_file_id IS NOT NULL
    ),
    CONSTRAINT ck_pod_correction_times CHECK (received_at >= occurred_at)
);

CREATE INDEX IF NOT EXISTS ix_pod_correction_pod
    ON etms.pod_correction_events (tenant_id, pod_id, correction_no);
CREATE INDEX IF NOT EXISTS ix_pod_correction_replacement_pod
    ON etms.pod_correction_events (tenant_id, replacement_pod_id);
CREATE INDEX IF NOT EXISTS ix_pod_correction_item
    ON etms.pod_correction_events (tenant_id, pod_item_id);
CREATE INDEX IF NOT EXISTS ix_pod_correction_source_event
    ON etms.pod_correction_events (tenant_id, source_event_id);
CREATE INDEX IF NOT EXISTS ix_pod_correction_evidence_file
    ON etms.pod_correction_events (tenant_id, evidence_file_id);
CREATE INDEX IF NOT EXISTS ix_pod_correction_quantity_uom
    ON etms.pod_correction_events (quantity_uom_code);
CREATE INDEX IF NOT EXISTS ix_pod_correction_requested_by
    ON etms.pod_correction_events (requested_by);
CREATE INDEX IF NOT EXISTS ix_pod_correction_approved_by
    ON etms.pod_correction_events (approved_by);

CREATE TABLE IF NOT EXISTS etms.pod_verification_events (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    pod_id uuid NOT NULL,
    verification_no integer NOT NULL,
    from_status varchar(20),
    to_status varchar(20) NOT NULL,
    verification_method varchar(30) NOT NULL,
    verification_result varchar(30) NOT NULL,
    rule_version varchar(80),
    verifier_user_id uuid REFERENCES etms.users(id),
    evidence_file_id uuid,
    reason_code varchar(80),
    reason_text text,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    received_at timestamptz NOT NULL DEFAULT now(),
    verification_detail jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, pod_id, verification_no),
    CONSTRAINT fk_pod_verification_pod
        FOREIGN KEY (tenant_id, pod_id)
        REFERENCES etms.proof_of_deliveries(tenant_id, id),
    CONSTRAINT fk_pod_verification_evidence_file
        FOREIGN KEY (tenant_id, evidence_file_id)
        REFERENCES etms.files(tenant_id, id),
    CONSTRAINT ck_pod_verification_no CHECK (verification_no > 0),
    CONSTRAINT ck_pod_verification_status CHECK (
        to_status IN ('PENDING','IN_REVIEW','VERIFIED','REJECTED','CORRECTION_REQUIRED')
        AND (from_status IS NULL OR from_status <> to_status)
    ),
    CONSTRAINT ck_pod_verification_method CHECK (
        verification_method IN (
            'MANUAL','SIGNATURE','CUSTOMER_PORTAL','API','AUTOMATED','CORRECTION'
        )
    ),
    CONSTRAINT ck_pod_verification_result CHECK (
        verification_result IN ('PASS','FAIL','REVIEW_REQUIRED','NOT_APPLICABLE')
    ),
    CONSTRAINT ck_pod_verification_times CHECK (received_at >= occurred_at)
);

CREATE INDEX IF NOT EXISTS ix_pod_verification_pod
    ON etms.pod_verification_events (tenant_id, pod_id, verification_no);
CREATE INDEX IF NOT EXISTS ix_pod_verification_evidence_file
    ON etms.pod_verification_events (tenant_id, evidence_file_id);
CREATE INDEX IF NOT EXISTS ix_pod_verification_verifier
    ON etms.pod_verification_events (verifier_user_id);
CREATE INDEX IF NOT EXISTS ix_pod_verification_occurred
    ON etms.pod_verification_events (tenant_id, occurred_at DESC);

-- A POD can have one evidence line for a given order-line/handling-unit scope.
CREATE UNIQUE INDEX IF NOT EXISTS ux_pod_items_evidence_scope
    ON etms.pod_items (
        pod_id,
        COALESCE(order_line_id, '00000000-0000-0000-0000-000000000000'::uuid),
        COALESCE(handling_unit_id, '00000000-0000-0000-0000-000000000000'::uuid)
    );

-- ---------------------------------------------------------------------------
-- Port/terminal operational evidence.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS etms.port_terminal_events (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    event_type varchar(40) NOT NULL,
    location_id uuid NOT NULL,
    schedule_call_id uuid,
    transport_schedule_id uuid,
    carrier_booking_id uuid,
    shipment_id uuid,
    container_id uuid,
    run_id uuid,
    source_event_id uuid,
    source_system_id uuid,
    external_event_id varchar(300),
    source_sequence bigint,
    terminal_reference varchar(200),
    voyage_flight_train_no varchar(100),
    equipment_status varchar(30),
    measured_quantity numeric(20,6),
    quantity_uom_code varchar(20) REFERENCES etms.units_of_measure(uom_code),
    assessed_charge_amount numeric(20,4),
    currency_code char(3) REFERENCES etms.currencies(currency_code),
    latitude numeric(10,7),
    longitude numeric(11,7),
    recorded_by uuid REFERENCES etms.users(id),
    occurred_at timestamptz NOT NULL,
    received_at timestamptz NOT NULL DEFAULT now(),
    event_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    CONSTRAINT fk_port_terminal_location
        FOREIGN KEY (tenant_id, location_id)
        REFERENCES etms.locations(tenant_id, id),
    CONSTRAINT fk_port_terminal_schedule_call
        FOREIGN KEY (tenant_id, schedule_call_id)
        REFERENCES etms.transport_schedule_calls(tenant_id, id),
    CONSTRAINT fk_port_terminal_schedule
        FOREIGN KEY (tenant_id, transport_schedule_id)
        REFERENCES etms.transport_schedules(tenant_id, id),
    CONSTRAINT fk_port_terminal_booking
        FOREIGN KEY (tenant_id, carrier_booking_id)
        REFERENCES etms.carrier_bookings(tenant_id, id),
    CONSTRAINT fk_port_terminal_shipment
        FOREIGN KEY (tenant_id, shipment_id)
        REFERENCES etms.shipments(tenant_id, id),
    CONSTRAINT fk_port_terminal_container
        FOREIGN KEY (tenant_id, container_id)
        REFERENCES etms.containers(tenant_id, id),
    CONSTRAINT fk_port_terminal_run
        FOREIGN KEY (tenant_id, run_id)
        REFERENCES etms.transport_runs(tenant_id, id),
    CONSTRAINT fk_port_terminal_source_event
        FOREIGN KEY (tenant_id, source_event_id)
        REFERENCES etms.transport_events(tenant_id, id),
    CONSTRAINT fk_port_terminal_source_system
        FOREIGN KEY (tenant_id, source_system_id)
        REFERENCES etms.external_systems(tenant_id, id),
    CONSTRAINT ck_port_terminal_event_type CHECK (
        event_type IN (
            'GATE_IN','GATE_OUT','BERTHED','UNBERTHED','DISCHARGED','LOADED',
            'AVAILABLE','CUSTOMS_HOLD','CUSTOMS_RELEASE','TERMINAL_HOLD','RELEASED',
            'EMPTY_RETURNED','ROLLED','DELAYED','CORRECTED'
        )
    ),
    CONSTRAINT ck_port_terminal_quantity CHECK (
        (measured_quantity IS NULL) = (quantity_uom_code IS NULL)
        AND (measured_quantity IS NULL OR measured_quantity >= 0)
    ),
    CONSTRAINT ck_port_terminal_charge CHECK (
        (assessed_charge_amount IS NULL) = (currency_code IS NULL)
        AND (assessed_charge_amount IS NULL OR assessed_charge_amount >= 0)
    ),
    CONSTRAINT ck_port_terminal_lat CHECK (latitude IS NULL OR latitude BETWEEN -90 AND 90),
    CONSTRAINT ck_port_terminal_lon CHECK (longitude IS NULL OR longitude BETWEEN -180 AND 180),
    CONSTRAINT ck_port_terminal_times CHECK (received_at >= occurred_at),
    CONSTRAINT ck_port_terminal_source_sequence CHECK (
        source_sequence IS NULL OR source_sequence >= 0
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_port_terminal_external_event
    ON etms.port_terminal_events (tenant_id, source_system_id, external_event_id)
    WHERE source_system_id IS NOT NULL AND external_event_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_port_terminal_source_sequence
    ON etms.port_terminal_events (tenant_id, source_system_id, source_sequence)
    WHERE source_system_id IS NOT NULL AND source_sequence IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_port_terminal_location
    ON etms.port_terminal_events (tenant_id, location_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS ix_port_terminal_schedule_call
    ON etms.port_terminal_events (tenant_id, schedule_call_id);
CREATE INDEX IF NOT EXISTS ix_port_terminal_schedule
    ON etms.port_terminal_events (tenant_id, transport_schedule_id);
CREATE INDEX IF NOT EXISTS ix_port_terminal_booking
    ON etms.port_terminal_events (tenant_id, carrier_booking_id);
CREATE INDEX IF NOT EXISTS ix_port_terminal_shipment
    ON etms.port_terminal_events (tenant_id, shipment_id);
CREATE INDEX IF NOT EXISTS ix_port_terminal_container
    ON etms.port_terminal_events (tenant_id, container_id);
CREATE INDEX IF NOT EXISTS ix_port_terminal_run
    ON etms.port_terminal_events (tenant_id, run_id);
CREATE INDEX IF NOT EXISTS ix_port_terminal_source_event
    ON etms.port_terminal_events (tenant_id, source_event_id);
CREATE INDEX IF NOT EXISTS ix_port_terminal_source_system
    ON etms.port_terminal_events (tenant_id, source_system_id);
CREATE INDEX IF NOT EXISTS ix_port_terminal_quantity_uom
    ON etms.port_terminal_events (quantity_uom_code);
CREATE INDEX IF NOT EXISTS ix_port_terminal_currency
    ON etms.port_terminal_events (currency_code);
CREATE INDEX IF NOT EXISTS ix_port_terminal_recorded_by
    ON etms.port_terminal_events (recorded_by);

-- ---------------------------------------------------------------------------
-- Rate-quote acceptance evidence.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS etms.rate_quote_acceptance_events (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    rate_quote_id uuid NOT NULL,
    event_sequence integer NOT NULL,
    event_type varchar(30) NOT NULL,
    from_status varchar(20),
    to_status varchar(20) NOT NULL,
    accepted_amount numeric(20,4) NOT NULL,
    currency_code char(3) NOT NULL REFERENCES etms.currencies(currency_code),
    accepted_quantity numeric(20,6),
    quantity_uom_code varchar(20) REFERENCES etms.units_of_measure(uom_code),
    accepting_partner_id uuid,
    accepted_by uuid REFERENCES etms.users(id),
    acceptance_channel varchar(30) NOT NULL DEFAULT 'SYSTEM',
    terms_hash char(64),
    reason_code varchar(80),
    reason_text text,
    source_event_id uuid,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    received_at timestamptz NOT NULL DEFAULT now(),
    terms_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, rate_quote_id, event_sequence),
    CONSTRAINT fk_rate_quote_acceptance_quote
        FOREIGN KEY (tenant_id, rate_quote_id)
        REFERENCES etms.rate_quotes(tenant_id, id),
    CONSTRAINT fk_rate_quote_acceptance_partner
        FOREIGN KEY (tenant_id, accepting_partner_id)
        REFERENCES etms.business_partners(tenant_id, id),
    CONSTRAINT fk_rate_quote_acceptance_source_event
        FOREIGN KEY (tenant_id, source_event_id)
        REFERENCES etms.transport_events(tenant_id, id),
    CONSTRAINT ck_rate_quote_acceptance_sequence CHECK (event_sequence > 0),
    CONSTRAINT ck_rate_quote_acceptance_type CHECK (
        event_type IN ('STATUS_CHANGED','ACCEPTED','REJECTED','WITHDRAWN','EXPIRED','CORRECTED')
    ),
    CONSTRAINT ck_rate_quote_acceptance_status CHECK (
        from_status IS NULL OR from_status <> to_status
    ),
    CONSTRAINT ck_rate_quote_acceptance_amount CHECK (accepted_amount >= 0),
    CONSTRAINT ck_rate_quote_acceptance_quantity CHECK (
        (accepted_quantity IS NULL) = (quantity_uom_code IS NULL)
        AND (accepted_quantity IS NULL OR accepted_quantity >= 0)
    ),
    CONSTRAINT ck_rate_quote_acceptance_channel CHECK (
        acceptance_channel IN ('SYSTEM','PORTAL','API','EMAIL','EDI','MANUAL')
    ),
    CONSTRAINT ck_rate_quote_acceptance_times CHECK (received_at >= occurred_at)
);

CREATE INDEX IF NOT EXISTS ix_rate_quote_acceptance_quote
    ON etms.rate_quote_acceptance_events (tenant_id, rate_quote_id, event_sequence);
CREATE INDEX IF NOT EXISTS ix_rate_quote_acceptance_partner
    ON etms.rate_quote_acceptance_events (tenant_id, accepting_partner_id);
CREATE INDEX IF NOT EXISTS ix_rate_quote_acceptance_source_event
    ON etms.rate_quote_acceptance_events (tenant_id, source_event_id);
CREATE INDEX IF NOT EXISTS ix_rate_quote_acceptance_currency
    ON etms.rate_quote_acceptance_events (currency_code);
CREATE INDEX IF NOT EXISTS ix_rate_quote_acceptance_quantity_uom
    ON etms.rate_quote_acceptance_events (quantity_uom_code);
CREATE INDEX IF NOT EXISTS ix_rate_quote_acceptance_accepted_by
    ON etms.rate_quote_acceptance_events (accepted_by);

-- ---------------------------------------------------------------------------
-- Replanning decision evidence.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS etms.replan_events (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    replan_request_id uuid NOT NULL,
    event_sequence integer NOT NULL,
    event_type varchar(30) NOT NULL,
    trigger_type varchar(40) NOT NULL,
    base_scenario_id uuid,
    result_scenario_id uuid,
    planning_run_id uuid,
    order_id uuid,
    shipment_id uuid,
    run_id uuid,
    source_event_id uuid,
    affected_order_count integer NOT NULL DEFAULT 0,
    affected_shipment_count integer NOT NULL DEFAULT 0,
    affected_run_count integer NOT NULL DEFAULT 0,
    cost_delta numeric(20,4),
    currency_code char(3) REFERENCES etms.currencies(currency_code),
    distance_delta numeric(20,6),
    distance_uom_code varchar(20) REFERENCES etms.units_of_measure(uom_code),
    duration_delta numeric(20,6),
    duration_uom_code varchar(20) REFERENCES etms.units_of_measure(uom_code),
    requested_by uuid REFERENCES etms.users(id),
    approved_by uuid REFERENCES etms.users(id),
    reason_code varchar(80),
    reason_text text NOT NULL,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    received_at timestamptz NOT NULL DEFAULT now(),
    decision_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, replan_request_id, event_sequence),
    CONSTRAINT fk_replan_base_scenario
        FOREIGN KEY (tenant_id, base_scenario_id)
        REFERENCES etms.planning_scenarios(tenant_id, id),
    CONSTRAINT fk_replan_result_scenario
        FOREIGN KEY (tenant_id, result_scenario_id)
        REFERENCES etms.planning_scenarios(tenant_id, id),
    CONSTRAINT fk_replan_planning_run
        FOREIGN KEY (tenant_id, planning_run_id)
        REFERENCES etms.planning_runs(tenant_id, id),
    CONSTRAINT fk_replan_order
        FOREIGN KEY (tenant_id, order_id)
        REFERENCES etms.transport_orders(tenant_id, id),
    CONSTRAINT fk_replan_shipment
        FOREIGN KEY (tenant_id, shipment_id)
        REFERENCES etms.shipments(tenant_id, id),
    CONSTRAINT fk_replan_run
        FOREIGN KEY (tenant_id, run_id)
        REFERENCES etms.transport_runs(tenant_id, id),
    CONSTRAINT fk_replan_source_event
        FOREIGN KEY (tenant_id, source_event_id)
        REFERENCES etms.transport_events(tenant_id, id),
    CONSTRAINT ck_replan_event_sequence CHECK (event_sequence > 0),
    CONSTRAINT ck_replan_event_type CHECK (
        event_type IN ('REQUESTED','STARTED','COMPLETED','FAILED','COMMITTED','CANCELLED','CORRECTED')
    ),
    CONSTRAINT ck_replan_trigger_type CHECK (
        trigger_type IN (
            'ORDER_CHANGE','CAPACITY_CHANGE','CARRIER_REJECTION','DISRUPTION',
            'ETA_BREACH','EQUIPMENT_FAILURE','MANUAL','OPTIMIZER','OTHER'
        )
    ),
    CONSTRAINT ck_replan_entity CHECK (
        base_scenario_id IS NOT NULL OR result_scenario_id IS NOT NULL
        OR order_id IS NOT NULL OR shipment_id IS NOT NULL OR run_id IS NOT NULL
    ),
    CONSTRAINT ck_replan_counts CHECK (
        affected_order_count >= 0 AND affected_shipment_count >= 0 AND affected_run_count >= 0
    ),
    CONSTRAINT ck_replan_cost CHECK ((cost_delta IS NULL) = (currency_code IS NULL)),
    CONSTRAINT ck_replan_distance CHECK (
        (distance_delta IS NULL) = (distance_uom_code IS NULL)
    ),
    CONSTRAINT ck_replan_duration CHECK (
        (duration_delta IS NULL) = (duration_uom_code IS NULL)
    ),
    CONSTRAINT ck_replan_scenarios CHECK (
        base_scenario_id IS NULL OR result_scenario_id IS NULL
        OR base_scenario_id <> result_scenario_id
    ),
    CONSTRAINT ck_replan_times CHECK (received_at >= occurred_at)
);

CREATE INDEX IF NOT EXISTS ix_replan_base_scenario
    ON etms.replan_events (tenant_id, base_scenario_id);
CREATE INDEX IF NOT EXISTS ix_replan_result_scenario
    ON etms.replan_events (tenant_id, result_scenario_id);
CREATE INDEX IF NOT EXISTS ix_replan_planning_run
    ON etms.replan_events (tenant_id, planning_run_id);
CREATE INDEX IF NOT EXISTS ix_replan_order
    ON etms.replan_events (tenant_id, order_id);
CREATE INDEX IF NOT EXISTS ix_replan_shipment
    ON etms.replan_events (tenant_id, shipment_id);
CREATE INDEX IF NOT EXISTS ix_replan_run
    ON etms.replan_events (tenant_id, run_id);
CREATE INDEX IF NOT EXISTS ix_replan_source_event
    ON etms.replan_events (tenant_id, source_event_id);
CREATE INDEX IF NOT EXISTS ix_replan_currency
    ON etms.replan_events (currency_code);
CREATE INDEX IF NOT EXISTS ix_replan_distance_uom
    ON etms.replan_events (distance_uom_code);
CREATE INDEX IF NOT EXISTS ix_replan_duration_uom
    ON etms.replan_events (duration_uom_code);
CREATE INDEX IF NOT EXISTS ix_replan_requested_by
    ON etms.replan_events (requested_by);
CREATE INDEX IF NOT EXISTS ix_replan_approved_by
    ON etms.replan_events (approved_by);

-- ---------------------------------------------------------------------------
-- Stop dwell and detention evidence.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS etms.stop_dwell_events (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    stop_execution_id uuid NOT NULL,
    run_stop_id uuid NOT NULL,
    event_sequence integer NOT NULL,
    event_type varchar(40) NOT NULL,
    dwell_started_at timestamptz,
    dwell_ended_at timestamptz,
    planned_duration numeric(20,6),
    free_duration numeric(20,6),
    actual_duration numeric(20,6),
    chargeable_duration numeric(20,6),
    duration_uom_code varchar(20) NOT NULL DEFAULT 'MIN'
        REFERENCES etms.units_of_measure(uom_code),
    detention_amount numeric(20,4),
    currency_code char(3) REFERENCES etms.currencies(currency_code),
    threshold_code varchar(80),
    source_event_id uuid,
    recorded_by uuid REFERENCES etms.users(id),
    reason_text text,
    occurred_at timestamptz NOT NULL,
    received_at timestamptz NOT NULL DEFAULT now(),
    event_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, stop_execution_id, event_sequence),
    CONSTRAINT fk_stop_dwell_execution
        FOREIGN KEY (tenant_id, stop_execution_id)
        REFERENCES etms.stop_executions(tenant_id, id),
    CONSTRAINT fk_stop_dwell_run_stop
        FOREIGN KEY (tenant_id, run_stop_id)
        REFERENCES etms.run_stops(tenant_id, id),
    CONSTRAINT fk_stop_dwell_source_event
        FOREIGN KEY (tenant_id, source_event_id)
        REFERENCES etms.transport_events(tenant_id, id),
    CONSTRAINT ck_stop_dwell_sequence CHECK (event_sequence > 0),
    CONSTRAINT ck_stop_dwell_type CHECK (
        event_type IN (
            'ARRIVED','DWELL_STARTED','THRESHOLD_BREACHED','SERVICE_STARTED',
            'DWELL_ENDED','DEPARTED','RECALCULATED','CORRECTED'
        )
    ),
    CONSTRAINT ck_stop_dwell_window CHECK (
        dwell_ended_at IS NULL OR dwell_started_at IS NULL OR dwell_ended_at >= dwell_started_at
    ),
    CONSTRAINT ck_stop_dwell_durations CHECK (
        (planned_duration IS NULL OR planned_duration >= 0)
        AND (free_duration IS NULL OR free_duration >= 0)
        AND (actual_duration IS NULL OR actual_duration >= 0)
        AND (chargeable_duration IS NULL OR chargeable_duration >= 0)
        AND (actual_duration IS NULL OR chargeable_duration IS NULL
             OR chargeable_duration <= actual_duration)
    ),
    CONSTRAINT ck_stop_dwell_charge CHECK (
        (detention_amount IS NULL) = (currency_code IS NULL)
        AND (detention_amount IS NULL OR detention_amount >= 0)
    ),
    CONSTRAINT ck_stop_dwell_times CHECK (received_at >= occurred_at)
);

CREATE INDEX IF NOT EXISTS ix_stop_dwell_execution
    ON etms.stop_dwell_events (tenant_id, stop_execution_id, event_sequence);
CREATE INDEX IF NOT EXISTS ix_stop_dwell_run_stop
    ON etms.stop_dwell_events (tenant_id, run_stop_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS ix_stop_dwell_source_event
    ON etms.stop_dwell_events (tenant_id, source_event_id);
CREATE INDEX IF NOT EXISTS ix_stop_dwell_duration_uom
    ON etms.stop_dwell_events (duration_uom_code);
CREATE INDEX IF NOT EXISTS ix_stop_dwell_currency
    ON etms.stop_dwell_events (currency_code);
CREATE INDEX IF NOT EXISTS ix_stop_dwell_recorded_by
    ON etms.stop_dwell_events (recorded_by);

-- ---------------------------------------------------------------------------
-- Tender-award change history.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS etms.tender_award_history (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    tender_award_id uuid NOT NULL,
    tender_id uuid NOT NULL,
    carrier_id uuid NOT NULL,
    history_no integer NOT NULL,
    event_type varchar(30) NOT NULL,
    from_status varchar(20),
    to_status varchar(20) NOT NULL,
    previous_award_amount numeric(20,4),
    previous_currency_code char(3) REFERENCES etms.currencies(currency_code),
    new_award_amount numeric(20,4) NOT NULL,
    new_currency_code char(3) NOT NULL REFERENCES etms.currencies(currency_code),
    previous_withdrawn_at timestamptz,
    new_withdrawn_at timestamptz,
    previous_withdrawal_reason text,
    new_withdrawal_reason text,
    source_event_id uuid,
    changed_by uuid REFERENCES etms.users(id),
    reason_text text,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    received_at timestamptz NOT NULL DEFAULT now(),
    event_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, tender_award_id, history_no),
    CONSTRAINT fk_tender_award_history_award
        FOREIGN KEY (tenant_id, tender_award_id)
        REFERENCES etms.tender_awards(tenant_id, id),
    CONSTRAINT fk_tender_award_history_tender
        FOREIGN KEY (tenant_id, tender_id)
        REFERENCES etms.tenders(tenant_id, id),
    CONSTRAINT fk_tender_award_history_carrier
        FOREIGN KEY (tenant_id, carrier_id)
        REFERENCES etms.business_partners(tenant_id, id),
    CONSTRAINT fk_tender_award_history_source_event
        FOREIGN KEY (tenant_id, source_event_id)
        REFERENCES etms.transport_events(tenant_id, id),
    CONSTRAINT ck_tender_award_history_no CHECK (history_no > 0),
    CONSTRAINT ck_tender_award_history_type CHECK (
        event_type IN (
            'CREATED','STATUS_CHANGED','AMOUNT_CHANGED','WITHDRAWAL_CHANGED','MULTIPLE_CHANGED'
        )
    ),
    CONSTRAINT ck_tender_award_history_amounts CHECK (
        (previous_award_amount IS NULL) = (previous_currency_code IS NULL)
        AND (previous_award_amount IS NULL OR previous_award_amount >= 0)
        AND new_award_amount >= 0
    ),
    CONSTRAINT ck_tender_award_history_change CHECK (
        event_type = 'CREATED'
        OR from_status IS DISTINCT FROM to_status
        OR previous_award_amount IS DISTINCT FROM new_award_amount
        OR previous_currency_code IS DISTINCT FROM new_currency_code
        OR previous_withdrawn_at IS DISTINCT FROM new_withdrawn_at
        OR previous_withdrawal_reason IS DISTINCT FROM new_withdrawal_reason
    ),
    CONSTRAINT ck_tender_award_history_times CHECK (received_at >= occurred_at)
);

CREATE INDEX IF NOT EXISTS ix_tender_award_history_award
    ON etms.tender_award_history (tenant_id, tender_award_id, history_no);
CREATE INDEX IF NOT EXISTS ix_tender_award_history_tender
    ON etms.tender_award_history (tenant_id, tender_id);
CREATE INDEX IF NOT EXISTS ix_tender_award_history_carrier
    ON etms.tender_award_history (tenant_id, carrier_id);
CREATE INDEX IF NOT EXISTS ix_tender_award_history_source_event
    ON etms.tender_award_history (tenant_id, source_event_id);
CREATE INDEX IF NOT EXISTS ix_tender_award_history_previous_currency
    ON etms.tender_award_history (previous_currency_code);
CREATE INDEX IF NOT EXISTS ix_tender_award_history_new_currency
    ON etms.tender_award_history (new_currency_code);
CREATE INDEX IF NOT EXISTS ix_tender_award_history_changed_by
    ON etms.tender_award_history (changed_by);

-- ---------------------------------------------------------------------------
-- Operational aggregate status starts and complete initial status histories.
-- ---------------------------------------------------------------------------

DO $migration$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'etms.transport_orders'::regclass
          AND conname = 'ck_transport_orders_status_v03'
    ) THEN
        ALTER TABLE etms.transport_orders
            ADD CONSTRAINT ck_transport_orders_status_v03 CHECK (
                status IN (
                    'DRAFT','SUBMITTED','VALIDATED','PLANNED','DISPATCHED',
                    'IN_TRANSIT','DELIVERED','COMPLETED','ON_HOLD','EXCEPTION','CANCELLED'
                )
            ) NOT VALID;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'etms.shipments'::regclass
          AND conname = 'ck_shipments_status_v03'
    ) THEN
        ALTER TABLE etms.shipments
            ADD CONSTRAINT ck_shipments_status_v03 CHECK (
                status IN (
                    'PLANNED','TENDERING','TENDERED','ASSIGNED','DISPATCHED',
                    'IN_TRANSIT','DELIVERED','COMPLETED','EXCEPTION','CANCELLED'
                )
            ) NOT VALID;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'etms.transport_runs'::regclass
          AND conname = 'ck_transport_runs_status_v03'
    ) THEN
        ALTER TABLE etms.transport_runs
            ADD CONSTRAINT ck_transport_runs_status_v03 CHECK (
                status IN (
                    'PLANNED','ASSIGNED','DISPATCHED','IN_PROGRESS',
                    'COMPLETED','EXCEPTION','CANCELLED'
                )
            ) NOT VALID;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'etms.dispatch_orders'::regclass
          AND conname = 'ck_dispatch_orders_status_v03'
    ) THEN
        ALTER TABLE etms.dispatch_orders
            ADD CONSTRAINT ck_dispatch_orders_status_v03 CHECK (
                status IN (
                    'DRAFT','ISSUED','ACKNOWLEDGED','ACCEPTED','REJECTED',
                    'IN_PROGRESS','COMPLETED','CANCELLED','EXPIRED'
                )
            ) NOT VALID;
    END IF;
END;
$migration$;

ALTER TABLE etms.transport_orders
    VALIDATE CONSTRAINT ck_transport_orders_status_v03;
ALTER TABLE etms.shipments
    VALIDATE CONSTRAINT ck_shipments_status_v03;
ALTER TABLE etms.transport_runs
    VALIDATE CONSTRAINT ck_transport_runs_status_v03;
ALTER TABLE etms.dispatch_orders
    VALIDATE CONSTRAINT ck_dispatch_orders_status_v03;

CREATE OR REPLACE FUNCTION etms.enforce_initial_operational_status()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
BEGIN
    IF NEW.status IS DISTINCT FROM TG_ARGV[1] THEN
        RAISE EXCEPTION 'New % rows must start in status %, not %',
            TG_ARGV[0], TG_ARGV[1], NEW.status
            USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (
        SELECT 1
          FROM etms.status_definitions definition_row
         WHERE definition_row.entity_type = TG_ARGV[0]
           AND definition_row.status_code = TG_ARGV[1]
           AND definition_row.is_active
           AND (definition_row.tenant_id IS NULL
                OR definition_row.tenant_id = NEW.tenant_id)
    ) THEN
        RAISE EXCEPTION 'Initial status % is not an active % status definition',
            TG_ARGV[1], TG_ARGV[0]
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION etms.record_initial_operational_status_history()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    actor_id uuid := COALESCE(etms.current_etms_user_id(), NEW.created_by);
BEGIN
    IF TG_ARGV[0] = 'ORDER' THEN
        INSERT INTO etms.order_status_history (
            tenant_id, order_id, from_status, to_status,
            source_type, changed_by, occurred_at, received_at
        ) VALUES (
            NEW.tenant_id, NEW.id, NULL, NEW.status,
            'SYSTEM', actor_id, statement_timestamp(), statement_timestamp()
        );
    ELSIF TG_ARGV[0] = 'SHIPMENT' THEN
        INSERT INTO etms.shipment_status_history (
            tenant_id, shipment_id, from_status, to_status,
            changed_by, occurred_at, received_at
        ) VALUES (
            NEW.tenant_id, NEW.id, NULL, NEW.status,
            actor_id, statement_timestamp(), statement_timestamp()
        );
    ELSIF TG_ARGV[0] = 'RUN' THEN
        INSERT INTO etms.run_status_history (
            tenant_id, run_id, from_status, to_status,
            changed_by, occurred_at, received_at
        ) VALUES (
            NEW.tenant_id, NEW.id, NULL, NEW.status,
            actor_id, statement_timestamp(), statement_timestamp()
        );
    ELSIF TG_ARGV[0] = 'DISPATCH' THEN
        INSERT INTO etms.dispatch_status_history (
            tenant_id, dispatch_order_id, from_status, to_status,
            changed_by, occurred_at
        ) VALUES (
            NEW.tenant_id, NEW.id, NULL, NEW.status,
            actor_id, statement_timestamp()
        );
    ELSE
        RAISE EXCEPTION 'Unsupported operational entity type %', TG_ARGV[0]
            USING ERRCODE = '22023';
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_enforce_order_initial_status ON etms.transport_orders;
CREATE TRIGGER trg_enforce_order_initial_status
    BEFORE INSERT ON etms.transport_orders
    FOR EACH ROW EXECUTE PROCEDURE
        etms.enforce_initial_operational_status('ORDER', 'DRAFT');
DROP TRIGGER IF EXISTS trg_enforce_shipment_initial_status ON etms.shipments;
CREATE TRIGGER trg_enforce_shipment_initial_status
    BEFORE INSERT ON etms.shipments
    FOR EACH ROW EXECUTE PROCEDURE
        etms.enforce_initial_operational_status('SHIPMENT', 'PLANNED');
DROP TRIGGER IF EXISTS trg_enforce_run_initial_status ON etms.transport_runs;
CREATE TRIGGER trg_enforce_run_initial_status
    BEFORE INSERT ON etms.transport_runs
    FOR EACH ROW EXECUTE PROCEDURE
        etms.enforce_initial_operational_status('RUN', 'PLANNED');
DROP TRIGGER IF EXISTS trg_enforce_dispatch_initial_status ON etms.dispatch_orders;
CREATE TRIGGER trg_enforce_dispatch_initial_status
    BEFORE INSERT ON etms.dispatch_orders
    FOR EACH ROW EXECUTE PROCEDURE
        etms.enforce_initial_operational_status('DISPATCH', 'DRAFT');

DROP TRIGGER IF EXISTS trg_record_order_initial_history ON etms.transport_orders;
CREATE TRIGGER trg_record_order_initial_history
    AFTER INSERT ON etms.transport_orders
    FOR EACH ROW EXECUTE PROCEDURE
        etms.record_initial_operational_status_history('ORDER');
DROP TRIGGER IF EXISTS trg_record_shipment_initial_history ON etms.shipments;
CREATE TRIGGER trg_record_shipment_initial_history
    AFTER INSERT ON etms.shipments
    FOR EACH ROW EXECUTE PROCEDURE
        etms.record_initial_operational_status_history('SHIPMENT');
DROP TRIGGER IF EXISTS trg_record_run_initial_history ON etms.transport_runs;
CREATE TRIGGER trg_record_run_initial_history
    AFTER INSERT ON etms.transport_runs
    FOR EACH ROW EXECUTE PROCEDURE
        etms.record_initial_operational_status_history('RUN');
DROP TRIGGER IF EXISTS trg_record_dispatch_initial_history ON etms.dispatch_orders;
CREATE TRIGGER trg_record_dispatch_initial_history
    AFTER INSERT ON etms.dispatch_orders
    FOR EACH ROW EXECUTE PROCEDURE
        etms.record_initial_operational_status_history('DISPATCH');

-- ---------------------------------------------------------------------------
-- Ledger parentage and sequence validation.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION etms.validate_claim_reserve_movement()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    parent_claim_id uuid;
    parent_currency_code char(3);
    prior_sequence integer;
    prior_closing numeric(20,4);
BEGIN
    SELECT reserve_row.claim_id, reserve_row.currency_code
      INTO parent_claim_id, parent_currency_code
      FROM etms.claim_reserves reserve_row
     WHERE reserve_row.tenant_id = NEW.tenant_id
       AND reserve_row.id = NEW.reserve_id
     FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Claim reserve is unavailable in the current tenant'
            USING ERRCODE = '23503';
    END IF;
    IF parent_claim_id IS DISTINCT FROM NEW.claim_id
       OR parent_currency_code IS DISTINCT FROM NEW.currency_code THEN
        RAISE EXCEPTION 'Reserve movement claim or currency differs from its reserve'
            USING ERRCODE = '23514';
    END IF;

    SELECT movement_row.movement_sequence, movement_row.closing_reserve_amount
      INTO prior_sequence, prior_closing
      FROM etms.claim_reserve_movements movement_row
     WHERE movement_row.tenant_id = NEW.tenant_id
       AND movement_row.reserve_id = NEW.reserve_id
     ORDER BY movement_row.movement_sequence DESC
     LIMIT 1;
    IF FOUND THEN
        IF NEW.movement_sequence <> prior_sequence + 1
           OR NEW.opening_reserve_amount IS DISTINCT FROM prior_closing THEN
            RAISE EXCEPTION 'Reserve movement sequence or opening balance is discontinuous'
                USING ERRCODE = '23514';
        END IF;
    ELSIF NEW.movement_sequence <> 1 OR NEW.opening_reserve_amount <> 0 THEN
        RAISE EXCEPTION 'The first reserve movement must be sequence 1 with zero opening balance'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_validate_claim_reserve_movement
    ON etms.claim_reserve_movements;
CREATE TRIGGER trg_validate_claim_reserve_movement
    BEFORE INSERT ON etms.claim_reserve_movements
    FOR EACH ROW EXECUTE PROCEDURE etms.validate_claim_reserve_movement();

CREATE OR REPLACE FUNCTION etms.validate_driving_hours_violation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    duty_driver_id uuid;
    duty_run_id uuid;
    dispatch_run_id uuid;
    prior_group_id uuid;
    prior_driver_id uuid;
BEGIN
    IF NEW.supersedes_violation_id IS NOT NULL THEN
        SELECT prior_row.violation_group_id, prior_row.driver_id
          INTO prior_group_id, prior_driver_id
          FROM etms.driving_hours_violations prior_row
         WHERE prior_row.tenant_id = NEW.tenant_id
           AND prior_row.id = NEW.supersedes_violation_id;
        IF NOT FOUND OR prior_group_id IS DISTINCT FROM NEW.violation_group_id
           OR prior_driver_id IS DISTINCT FROM NEW.driver_id THEN
            RAISE EXCEPTION
                'A HOS follow-up must supersede a violation for the same group and driver'
                USING ERRCODE = '23514';
        END IF;
    END IF;
    IF NEW.driver_duty_log_id IS NOT NULL THEN
        SELECT duty_row.driver_id, duty_row.run_id
          INTO duty_driver_id, duty_run_id
          FROM etms.driver_duty_logs duty_row
         WHERE duty_row.tenant_id = NEW.tenant_id
           AND duty_row.id = NEW.driver_duty_log_id;
        IF NOT FOUND OR duty_driver_id IS DISTINCT FROM NEW.driver_id
           OR (NEW.run_id IS NOT NULL AND duty_run_id IS NOT NULL
               AND duty_run_id IS DISTINCT FROM NEW.run_id) THEN
            RAISE EXCEPTION 'Duty log does not match the violation driver/run'
                USING ERRCODE = '23514';
        END IF;
    END IF;
    IF NEW.dispatch_order_id IS NOT NULL AND NEW.run_id IS NOT NULL THEN
        SELECT dispatch_row.run_id INTO dispatch_run_id
          FROM etms.dispatch_orders dispatch_row
         WHERE dispatch_row.tenant_id = NEW.tenant_id
           AND dispatch_row.id = NEW.dispatch_order_id;
        IF NOT FOUND OR dispatch_run_id IS DISTINCT FROM NEW.run_id THEN
            RAISE EXCEPTION 'Dispatch order does not match the violation run'
                USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_validate_driving_hours_violation
    ON etms.driving_hours_violations;
CREATE TRIGGER trg_validate_driving_hours_violation
    BEFORE INSERT ON etms.driving_hours_violations
    FOR EACH ROW EXECUTE PROCEDURE etms.validate_driving_hours_violation();

CREATE OR REPLACE FUNCTION etms.validate_pod_correction_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    item_pod_id uuid;
BEGIN
    IF NEW.pod_item_id IS NOT NULL THEN
        SELECT item_row.pod_id INTO item_pod_id
          FROM etms.pod_items item_row
         WHERE item_row.tenant_id = NEW.tenant_id
           AND item_row.id = NEW.pod_item_id;
        IF NOT FOUND OR item_pod_id IS DISTINCT FROM NEW.pod_id THEN
            RAISE EXCEPTION 'POD correction item must belong to the corrected POD'
                USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_validate_pod_correction_event ON etms.pod_correction_events;
CREATE TRIGGER trg_validate_pod_correction_event
    BEFORE INSERT ON etms.pod_correction_events
    FOR EACH ROW EXECUTE PROCEDURE etms.validate_pod_correction_event();

CREATE OR REPLACE FUNCTION etms.enforce_pod_item_allocation_totals()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    pod_shipment_id uuid;
    pod_order_id uuid;
    line_order_id uuid;
    line_quantity numeric(20,6);
    line_uom_code varchar(20);
    shipment_quantity numeric(20,6);
    shipment_uom_code varchar(20);
    order_uom_code varchar(20);
    order_allocation_quantity numeric(20,6);
    prior_delivered numeric(20,6);
BEGIN
    SELECT pod_row.shipment_id, pod_row.order_id
      INTO pod_shipment_id, pod_order_id
      FROM etms.proof_of_deliveries pod_row
     WHERE pod_row.tenant_id = NEW.tenant_id
       AND pod_row.id = NEW.pod_id
     FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'POD is unavailable in the current tenant'
            USING ERRCODE = '23503';
    END IF;

    SELECT shipment_row.total_quantity, shipment_row.quantity_uom_code
      INTO shipment_quantity, shipment_uom_code
      FROM etms.shipments shipment_row
     WHERE shipment_row.tenant_id = NEW.tenant_id
       AND shipment_row.id = pod_shipment_id
     FOR UPDATE;

    IF NEW.order_line_id IS NOT NULL THEN
        SELECT line_row.order_id, line_row.quantity, line_row.quantity_uom_code
          INTO line_order_id, line_quantity, line_uom_code
          FROM etms.transport_order_lines line_row
         WHERE line_row.tenant_id = NEW.tenant_id
           AND line_row.id = NEW.order_line_id
         FOR UPDATE;
        IF NOT FOUND OR line_uom_code IS DISTINCT FROM NEW.uom_code THEN
            RAISE EXCEPTION 'POD item UOM must match its transport-order line UOM'
                USING ERRCODE = '23514';
        END IF;
        IF pod_order_id IS NOT NULL AND line_order_id IS DISTINCT FROM pod_order_id THEN
            RAISE EXCEPTION 'POD item order line does not match the POD order'
                USING ERRCODE = '23514';
        END IF;
        SELECT COALESCE(sum(item_row.delivered_quantity), 0)
          INTO prior_delivered
          FROM etms.pod_items item_row
          JOIN etms.proof_of_deliveries other_pod
            ON other_pod.tenant_id = item_row.tenant_id
           AND other_pod.id = item_row.pod_id
         WHERE item_row.tenant_id = NEW.tenant_id
           AND item_row.order_line_id = NEW.order_line_id
           AND item_row.id <> NEW.id;
        IF prior_delivered + NEW.delivered_quantity > line_quantity THEN
            RAISE EXCEPTION 'POD delivered quantity exceeds the order-line allocation'
                USING ERRCODE = '23514';
        END IF;

        SELECT order_row.quantity_uom_code INTO order_uom_code
          FROM etms.transport_orders order_row
         WHERE order_row.tenant_id = NEW.tenant_id
           AND order_row.id = line_order_id
         FOR UPDATE;
        SELECT shipment_order.allocation_quantity
          INTO order_allocation_quantity
          FROM etms.shipment_orders shipment_order
         WHERE shipment_order.tenant_id = NEW.tenant_id
           AND shipment_order.shipment_id = pod_shipment_id
           AND shipment_order.order_id = line_order_id
           AND shipment_order.removed_at IS NULL
         FOR UPDATE;
        IF FOUND AND order_allocation_quantity IS NOT NULL
           AND order_uom_code IS NOT DISTINCT FROM NEW.uom_code THEN
            SELECT COALESCE(sum(item_row.delivered_quantity), 0)
              INTO prior_delivered
              FROM etms.pod_items item_row
              JOIN etms.proof_of_deliveries other_pod
                ON other_pod.tenant_id = item_row.tenant_id
               AND other_pod.id = item_row.pod_id
              JOIN etms.transport_order_lines line_row
                ON line_row.tenant_id = item_row.tenant_id
               AND line_row.id = item_row.order_line_id
             WHERE item_row.tenant_id = NEW.tenant_id
               AND other_pod.shipment_id = pod_shipment_id
               AND line_row.order_id = line_order_id
               AND item_row.uom_code = NEW.uom_code
               AND item_row.id <> NEW.id;
            IF prior_delivered + NEW.delivered_quantity > order_allocation_quantity THEN
                RAISE EXCEPTION 'POD delivered quantity exceeds the shipment-order allocation'
                    USING ERRCODE = '23514';
            END IF;
        END IF;
    END IF;

    IF shipment_quantity > 0
       AND shipment_uom_code IS NOT DISTINCT FROM NEW.uom_code THEN
        SELECT COALESCE(sum(item_row.delivered_quantity), 0)
          INTO prior_delivered
          FROM etms.pod_items item_row
          JOIN etms.proof_of_deliveries other_pod
            ON other_pod.tenant_id = item_row.tenant_id
           AND other_pod.id = item_row.pod_id
         WHERE item_row.tenant_id = NEW.tenant_id
           AND other_pod.shipment_id = pod_shipment_id
           AND item_row.uom_code = NEW.uom_code
           AND item_row.id <> NEW.id;
        IF prior_delivered + NEW.delivered_quantity > shipment_quantity THEN
            RAISE EXCEPTION 'POD delivered quantity exceeds the shipment allocation'
                USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_enforce_pod_item_allocation_totals ON etms.pod_items;
CREATE TRIGGER trg_enforce_pod_item_allocation_totals
    BEFORE INSERT OR UPDATE OF pod_id, order_line_id, handling_unit_id,
        delivered_quantity, uom_code
    ON etms.pod_items
    FOR EACH ROW EXECUTE PROCEDURE etms.enforce_pod_item_allocation_totals();

CREATE OR REPLACE FUNCTION etms.validate_stop_dwell_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    execution_run_stop_id uuid;
BEGIN
    SELECT execution_row.run_stop_id INTO execution_run_stop_id
      FROM etms.stop_executions execution_row
     WHERE execution_row.tenant_id = NEW.tenant_id
       AND execution_row.id = NEW.stop_execution_id;
    IF NOT FOUND OR execution_run_stop_id IS DISTINCT FROM NEW.run_stop_id THEN
        RAISE EXCEPTION 'Dwell event run stop must match its stop execution'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_validate_stop_dwell_event ON etms.stop_dwell_events;
CREATE TRIGGER trg_validate_stop_dwell_event
    BEFORE INSERT ON etms.stop_dwell_events
    FOR EACH ROW EXECUTE PROCEDURE etms.validate_stop_dwell_event();

-- ---------------------------------------------------------------------------
-- Automatic handling-unit, quote-acceptance, and tender-award histories.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION etms.record_handling_unit_parent_history()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    actor_id uuid := etms.current_etms_user_id();
    change_code text;
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.parent_handling_unit_id IS NULL THEN
            RETURN NEW;
        END IF;
        change_code := 'PARENT_ASSIGNED';
    ELSE
        IF NEW.parent_handling_unit_id IS NOT DISTINCT FROM OLD.parent_handling_unit_id THEN
            RETURN NEW;
        END IF;
        change_code := CASE
            WHEN OLD.parent_handling_unit_id IS NULL THEN 'PARENT_ASSIGNED'
            WHEN NEW.parent_handling_unit_id IS NULL THEN 'PARENT_REMOVED'
            ELSE 'PARENT_CHANGED'
        END;
    END IF;

    INSERT INTO etms.handling_unit_parent_history (
        tenant_id, handling_unit_id,
        from_parent_handling_unit_id, to_parent_handling_unit_id,
        change_type, changed_by, occurred_at, received_at
    ) VALUES (
        NEW.tenant_id, NEW.id,
        CASE WHEN TG_OP = 'INSERT' THEN NULL ELSE OLD.parent_handling_unit_id END,
        NEW.parent_handling_unit_id,
        change_code, actor_id, statement_timestamp(), statement_timestamp()
    );
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION etms.record_handling_unit_status_history()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    actor_id uuid := etms.current_etms_user_id();
BEGIN
    IF TG_OP = 'UPDATE' AND NEW.status IS NOT DISTINCT FROM OLD.status THEN
        RETURN NEW;
    END IF;
    INSERT INTO etms.handling_unit_status_history (
        tenant_id, handling_unit_id, from_status, to_status,
        location_id, changed_by, occurred_at, received_at
    ) VALUES (
        NEW.tenant_id, NEW.id,
        CASE WHEN TG_OP = 'INSERT' THEN NULL ELSE OLD.status END,
        NEW.status, NEW.current_location_id, actor_id,
        statement_timestamp(), statement_timestamp()
    );
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_record_hu_parent_initial ON etms.handling_units;
CREATE TRIGGER trg_record_hu_parent_initial
    AFTER INSERT ON etms.handling_units
    FOR EACH ROW EXECUTE PROCEDURE etms.record_handling_unit_parent_history();
DROP TRIGGER IF EXISTS trg_record_hu_parent_change ON etms.handling_units;
CREATE TRIGGER trg_record_hu_parent_change
    AFTER UPDATE OF parent_handling_unit_id ON etms.handling_units
    FOR EACH ROW EXECUTE PROCEDURE etms.record_handling_unit_parent_history();
DROP TRIGGER IF EXISTS trg_record_hu_status_initial ON etms.handling_units;
CREATE TRIGGER trg_record_hu_status_initial
    AFTER INSERT ON etms.handling_units
    FOR EACH ROW EXECUTE PROCEDURE etms.record_handling_unit_status_history();
DROP TRIGGER IF EXISTS trg_record_hu_status_change ON etms.handling_units;
CREATE TRIGGER trg_record_hu_status_change
    AFTER UPDATE OF status ON etms.handling_units
    FOR EACH ROW EXECUTE PROCEDURE etms.record_handling_unit_status_history();

CREATE OR REPLACE FUNCTION etms.record_rate_quote_acceptance_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    next_sequence integer;
    actor_id uuid := etms.current_etms_user_id();
    event_code text;
BEGIN
    IF NEW.status IS NOT DISTINCT FROM OLD.status THEN
        RETURN NEW;
    END IF;
    SELECT COALESCE(max(event_row.event_sequence), 0) + 1
      INTO next_sequence
      FROM etms.rate_quote_acceptance_events event_row
     WHERE event_row.tenant_id = NEW.tenant_id
       AND event_row.rate_quote_id = NEW.id;
    event_code := CASE upper(NEW.status)
        WHEN 'ACCEPTED' THEN 'ACCEPTED'
        WHEN 'REJECTED' THEN 'REJECTED'
        WHEN 'WITHDRAWN' THEN 'WITHDRAWN'
        WHEN 'EXPIRED' THEN 'EXPIRED'
        ELSE 'STATUS_CHANGED'
    END;
    INSERT INTO etms.rate_quote_acceptance_events (
        tenant_id, rate_quote_id, event_sequence, event_type,
        from_status, to_status, accepted_amount, currency_code,
        accepting_partner_id, accepted_by, acceptance_channel,
        occurred_at, received_at, terms_snapshot
    ) VALUES (
        NEW.tenant_id, NEW.id, next_sequence, event_code,
        OLD.status, NEW.status, NEW.gross_amount, NEW.currency_code,
        NEW.customer_id, actor_id, 'SYSTEM',
        statement_timestamp(), statement_timestamp(),
        jsonb_build_object(
            'quote_type', NEW.quote_type,
            'valid_until', NEW.valid_until,
            'accepted_at', NEW.accepted_at
        )
    );
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_record_rate_quote_acceptance
    ON etms.rate_quotes;
CREATE TRIGGER trg_record_rate_quote_acceptance
    AFTER UPDATE OF status ON etms.rate_quotes
    FOR EACH ROW EXECUTE PROCEDURE etms.record_rate_quote_acceptance_event();

CREATE OR REPLACE FUNCTION etms.record_tender_award_history()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    next_history_no integer;
    actor_id uuid := COALESCE(etms.current_etms_user_id(), NEW.awarded_by);
    event_code text;
    change_count integer;
BEGIN
    IF TG_OP = 'INSERT' THEN
        event_code := 'CREATED';
    ELSE
        change_count :=
            (NEW.status IS DISTINCT FROM OLD.status)::integer
            + ((NEW.award_amount IS DISTINCT FROM OLD.award_amount)
               OR (NEW.currency_code IS DISTINCT FROM OLD.currency_code))::integer
            + ((NEW.withdrawn_at IS DISTINCT FROM OLD.withdrawn_at)
               OR (NEW.withdrawal_reason IS DISTINCT FROM OLD.withdrawal_reason))::integer;
        IF change_count = 0 THEN
            RETURN NEW;
        ELSIF change_count > 1 THEN
            event_code := 'MULTIPLE_CHANGED';
        ELSIF NEW.status IS DISTINCT FROM OLD.status THEN
            event_code := 'STATUS_CHANGED';
        ELSIF NEW.award_amount IS DISTINCT FROM OLD.award_amount
              OR NEW.currency_code IS DISTINCT FROM OLD.currency_code THEN
            event_code := 'AMOUNT_CHANGED';
        ELSE
            event_code := 'WITHDRAWAL_CHANGED';
        END IF;
    END IF;

    SELECT COALESCE(max(history_row.history_no), 0) + 1
      INTO next_history_no
      FROM etms.tender_award_history history_row
     WHERE history_row.tenant_id = NEW.tenant_id
       AND history_row.tender_award_id = NEW.id;
    INSERT INTO etms.tender_award_history (
        tenant_id, tender_award_id, tender_id, carrier_id,
        history_no, event_type, from_status, to_status,
        previous_award_amount, previous_currency_code,
        new_award_amount, new_currency_code,
        previous_withdrawn_at, new_withdrawn_at,
        previous_withdrawal_reason, new_withdrawal_reason,
        changed_by, occurred_at, received_at
    ) VALUES (
        NEW.tenant_id, NEW.id, NEW.tender_id, NEW.carrier_id,
        next_history_no, event_code,
        CASE WHEN TG_OP = 'INSERT' THEN NULL ELSE OLD.status END,
        NEW.status,
        CASE WHEN TG_OP = 'INSERT' THEN NULL ELSE OLD.award_amount END,
        CASE WHEN TG_OP = 'INSERT' THEN NULL ELSE OLD.currency_code END,
        NEW.award_amount, NEW.currency_code,
        CASE WHEN TG_OP = 'INSERT' THEN NULL ELSE OLD.withdrawn_at END,
        NEW.withdrawn_at,
        CASE WHEN TG_OP = 'INSERT' THEN NULL ELSE OLD.withdrawal_reason END,
        NEW.withdrawal_reason,
        actor_id, statement_timestamp(), statement_timestamp()
    );
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_record_tender_award_initial ON etms.tender_awards;
CREATE TRIGGER trg_record_tender_award_initial
    AFTER INSERT ON etms.tender_awards
    FOR EACH ROW EXECUTE PROCEDURE etms.record_tender_award_history();
DROP TRIGGER IF EXISTS trg_record_tender_award_change ON etms.tender_awards;
CREATE TRIGGER trg_record_tender_award_change
    AFTER UPDATE OF status, award_amount, currency_code, withdrawn_at, withdrawal_reason
    ON etms.tender_awards
    FOR EACH ROW EXECUTE PROCEDURE etms.record_tender_award_history();

-- ---------------------------------------------------------------------------
-- Verified POD finalization, immutability, and verification history.
-- ---------------------------------------------------------------------------

DO $migration$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'etms.proof_of_deliveries'::regclass
          AND conname = 'ck_pod_verification_status_v03'
    ) THEN
        ALTER TABLE etms.proof_of_deliveries
            ADD CONSTRAINT ck_pod_verification_status_v03 CHECK (
                verification_status IN (
                    'PENDING','IN_REVIEW','VERIFIED','REJECTED','CORRECTION_REQUIRED'
                )
            ) NOT VALID;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'etms.proof_of_deliveries'::regclass
          AND conname = 'ck_pod_verification_fields_v03'
    ) THEN
        ALTER TABLE etms.proof_of_deliveries
            ADD CONSTRAINT ck_pod_verification_fields_v03 CHECK (
                (verified_by IS NULL) = (verified_at IS NULL)
                AND (
                    verification_status <> 'VERIFIED'
                    OR (verified_by IS NOT NULL AND verified_at IS NOT NULL)
                )
            ) NOT VALID;
    END IF;
END;
$migration$;

ALTER TABLE etms.proof_of_deliveries
    VALIDATE CONSTRAINT ck_pod_verification_status_v03;
ALTER TABLE etms.proof_of_deliveries
    VALIDATE CONSTRAINT ck_pod_verification_fields_v03;

CREATE OR REPLACE FUNCTION etms.finalize_pod_verification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    actor_id uuid := etms.current_etms_user_id();
    has_items boolean;
    has_signature_evidence boolean;
BEGIN
    IF NEW.verification_status <> 'VERIFIED'
       OR (TG_OP = 'UPDATE' AND OLD.verification_status = 'VERIFIED') THEN
        RETURN NEW;
    END IF;

    IF actor_id IS NOT NULL AND NEW.verified_by IS NOT NULL
       AND NEW.verified_by IS DISTINCT FROM actor_id THEN
        RAISE EXCEPTION 'POD verifier must match the authenticated ETMS user'
            USING ERRCODE = '42501';
    END IF;
    NEW.verified_by := COALESCE(actor_id, NEW.verified_by);
    IF NEW.verified_by IS NULL THEN
        RAISE EXCEPTION 'Verified POD requires an authenticated or explicit verifier'
            USING ERRCODE = '23514';
    END IF;
    NEW.verified_at := COALESCE(NEW.verified_at, statement_timestamp());

    IF NEW.delivery_result IN ('DELIVERED','PARTIAL') THEN
        SELECT EXISTS (
            SELECT 1
              FROM etms.pod_items item_row
             WHERE item_row.tenant_id = NEW.tenant_id
               AND item_row.pod_id = NEW.id
        ) INTO has_items;
        SELECT (
            EXISTS (
                SELECT 1
                  FROM etms.files file_row
                 WHERE file_row.tenant_id = NEW.tenant_id
                   AND file_row.id = NEW.signature_file_id
                   AND file_row.deleted_at IS NULL
                   AND file_row.malware_scan_status = 'CLEAN'
            )
            OR EXISTS (
                SELECT 1
                  FROM etms.pod_signatures signature_row
                  JOIN etms.files file_row
                    ON file_row.tenant_id = signature_row.tenant_id
                   AND file_row.id = signature_row.signature_file_id
                 WHERE signature_row.tenant_id = NEW.tenant_id
                   AND signature_row.pod_id = NEW.id
                   AND file_row.deleted_at IS NULL
                   AND file_row.malware_scan_status = 'CLEAN'
            )
        ) INTO has_signature_evidence;
        IF NOT has_items OR NOT has_signature_evidence THEN
            RAISE EXCEPTION
                'Delivered or partial POD requires item rows and clean signature evidence before verification'
                USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION etms.prevent_verified_pod_mutation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
BEGIN
    IF OLD.verification_status = 'VERIFIED' THEN
        RAISE EXCEPTION 'Verified POD headers are immutable; append a correction event or replacement POD'
            USING ERRCODE = '55000';
    END IF;
    IF TG_OP = 'UPDATE'
       AND (NEW.shipment_id IS DISTINCT FROM OLD.shipment_id
            OR NEW.order_id IS DISTINCT FROM OLD.order_id)
       AND (
           EXISTS (
               SELECT 1 FROM etms.pod_items item_row
                WHERE item_row.tenant_id = OLD.tenant_id
                  AND item_row.pod_id = OLD.id
           )
           OR EXISTS (
               SELECT 1 FROM etms.pod_signatures signature_row
                WHERE signature_row.tenant_id = OLD.tenant_id
                  AND signature_row.pod_id = OLD.id
           )
           OR EXISTS (
               SELECT 1 FROM etms.delivery_discrepancies discrepancy_row
                WHERE discrepancy_row.tenant_id = OLD.tenant_id
                  AND discrepancy_row.pod_id = OLD.id
           )
       ) THEN
        RAISE EXCEPTION 'POD order/shipment scope cannot change after evidence is attached'
            USING ERRCODE = '55000';
    END IF;
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION etms.prevent_verified_pod_child_mutation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    old_pod_id uuid;
    new_pod_id uuid;
    row_tenant_id uuid;
BEGIN
    IF TG_OP = 'INSERT' THEN
        row_tenant_id := NEW.tenant_id;
        new_pod_id := NEW.pod_id;
    ELSIF TG_OP = 'DELETE' THEN
        row_tenant_id := OLD.tenant_id;
        old_pod_id := OLD.pod_id;
    ELSE
        row_tenant_id := NEW.tenant_id;
        old_pod_id := NULLIF(to_jsonb(OLD) ->> 'pod_id', '')::uuid;
        new_pod_id := NULLIF(to_jsonb(NEW) ->> 'pod_id', '')::uuid;
    END IF;
    IF EXISTS (
        SELECT 1
          FROM etms.proof_of_deliveries pod_row
         WHERE pod_row.tenant_id = row_tenant_id
           AND pod_row.id IN (old_pod_id, new_pod_id)
           AND pod_row.verification_status = 'VERIFIED'
    ) THEN
        RAISE EXCEPTION 'POD child evidence cannot change under a verified POD'
            USING ERRCODE = '55000';
    END IF;
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION etms.record_pod_verification_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    next_verification_no integer;
    actor_id uuid := COALESCE(etms.current_etms_user_id(), NEW.verified_by);
    result_code text;
BEGIN
    IF NEW.verification_status IS NOT DISTINCT FROM OLD.verification_status THEN
        RETURN NEW;
    END IF;
    SELECT COALESCE(max(event_row.verification_no), 0) + 1
      INTO next_verification_no
      FROM etms.pod_verification_events event_row
     WHERE event_row.tenant_id = NEW.tenant_id
       AND event_row.pod_id = NEW.id;
    result_code := CASE NEW.verification_status
        WHEN 'VERIFIED' THEN 'PASS'
        WHEN 'REJECTED' THEN 'FAIL'
        WHEN 'CORRECTION_REQUIRED' THEN 'FAIL'
        ELSE 'REVIEW_REQUIRED'
    END;
    INSERT INTO etms.pod_verification_events (
        tenant_id, pod_id, verification_no,
        from_status, to_status, verification_method, verification_result,
        verifier_user_id, occurred_at, received_at
    ) VALUES (
        NEW.tenant_id, NEW.id, next_verification_no,
        OLD.verification_status, NEW.verification_status,
        CASE WHEN actor_id IS NULL THEN 'AUTOMATED' ELSE 'MANUAL' END,
        result_code, actor_id, statement_timestamp(), statement_timestamp()
    );
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_finalize_pod_verification ON etms.proof_of_deliveries;
CREATE TRIGGER trg_finalize_pod_verification
    BEFORE INSERT OR UPDATE OF verification_status, verified_by, verified_at,
        delivery_result, signature_file_id
    ON etms.proof_of_deliveries
    FOR EACH ROW EXECUTE PROCEDURE etms.finalize_pod_verification();
DROP TRIGGER IF EXISTS trg_protect_verified_pod ON etms.proof_of_deliveries;
CREATE TRIGGER trg_protect_verified_pod
    BEFORE UPDATE OR DELETE ON etms.proof_of_deliveries
    FOR EACH ROW EXECUTE PROCEDURE etms.prevent_verified_pod_mutation();
DROP TRIGGER IF EXISTS trg_record_pod_verification ON etms.proof_of_deliveries;
CREATE TRIGGER trg_record_pod_verification
    AFTER UPDATE OF verification_status ON etms.proof_of_deliveries
    FOR EACH ROW EXECUTE PROCEDURE etms.record_pod_verification_event();

DROP TRIGGER IF EXISTS trg_protect_verified_pod_item ON etms.pod_items;
CREATE TRIGGER trg_protect_verified_pod_item
    BEFORE INSERT OR UPDATE OR DELETE ON etms.pod_items
    FOR EACH ROW EXECUTE PROCEDURE etms.prevent_verified_pod_child_mutation();
DROP TRIGGER IF EXISTS trg_protect_verified_pod_signature ON etms.pod_signatures;
CREATE TRIGGER trg_protect_verified_pod_signature
    BEFORE INSERT OR UPDATE OR DELETE ON etms.pod_signatures
    FOR EACH ROW EXECUTE PROCEDURE etms.prevent_verified_pod_child_mutation();
DROP TRIGGER IF EXISTS trg_protect_verified_pod_discrepancy
    ON etms.delivery_discrepancies;
CREATE TRIGGER trg_protect_verified_pod_discrepancy
    BEFORE INSERT OR UPDATE OR DELETE ON etms.delivery_discrepancies
    FOR EACH ROW EXECUTE PROCEDURE etms.prevent_verified_pod_child_mutation();

DROP TRIGGER IF EXISTS trg_protect_pod_truncate ON etms.proof_of_deliveries;
CREATE TRIGGER trg_protect_pod_truncate
    BEFORE TRUNCATE ON etms.proof_of_deliveries
    FOR EACH STATEMENT EXECUTE PROCEDURE etms.prevent_ledger_mutation();
DROP TRIGGER IF EXISTS trg_protect_pod_item_truncate ON etms.pod_items;
CREATE TRIGGER trg_protect_pod_item_truncate
    BEFORE TRUNCATE ON etms.pod_items
    FOR EACH STATEMENT EXECUTE PROCEDURE etms.prevent_ledger_mutation();
DROP TRIGGER IF EXISTS trg_protect_pod_signature_truncate ON etms.pod_signatures;
CREATE TRIGGER trg_protect_pod_signature_truncate
    BEFORE TRUNCATE ON etms.pod_signatures
    FOR EACH STATEMENT EXECUTE PROCEDURE etms.prevent_ledger_mutation();
DROP TRIGGER IF EXISTS trg_protect_pod_discrepancy_truncate
    ON etms.delivery_discrepancies;
CREATE TRIGGER trg_protect_pod_discrepancy_truncate
    BEFORE TRUNCATE ON etms.delivery_discrepancies
    FOR EACH STATEMENT EXECUTE PROCEDURE etms.prevent_ledger_mutation();

-- Signature rows are themselves signed evidence and are append-only even
-- before header verification. A replacement signature is a new row.
DROP TRIGGER IF EXISTS trg_append_only_pod_signature_row ON etms.pod_signatures;
CREATE TRIGGER trg_append_only_pod_signature_row
    BEFORE UPDATE OR DELETE ON etms.pod_signatures
    FOR EACH ROW EXECUTE PROCEDURE etms.prevent_ledger_mutation();

-- Preserve the identity and chain of custody of claim evidence while allowing
-- its review/admissibility workflow fields to advance.
DROP TRIGGER IF EXISTS trg_protect_claim_evidence_core
    ON etms.claim_evidence_items;
CREATE TRIGGER trg_protect_claim_evidence_core
    BEFORE UPDATE OF tenant_id, claim_id, evidence_no, evidence_type,
        file_id, transport_event_id, incident_id, captured_at, received_at,
        content_hash, chain_of_custody
        OR DELETE ON etms.claim_evidence_items
    FOR EACH ROW EXECUTE PROCEDURE etms.prevent_ledger_mutation();
DROP TRIGGER IF EXISTS trg_protect_claim_evidence_truncate
    ON etms.claim_evidence_items;
CREATE TRIGGER trg_protect_claim_evidence_truncate
    BEFORE TRUNCATE ON etms.claim_evidence_items
    FOR EACH STATEMENT EXECUTE PROCEDURE etms.prevent_ledger_mutation();

-- ---------------------------------------------------------------------------
-- Protect immutable storage identities for files carrying legal/evidence value.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION etms.file_has_protected_operational_evidence(
    p_tenant_id uuid,
    p_file_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
    SELECT
        EXISTS (
            SELECT 1
              FROM etms.proof_of_deliveries pod_row
             WHERE pod_row.tenant_id = p_tenant_id
               AND pod_row.verification_status = 'VERIFIED'
               AND p_file_id IN (
                   pod_row.signature_file_id,
                   pod_row.primary_photo_file_id,
                   pod_row.document_file_id
               )
        )
        OR EXISTS (
            SELECT 1
              FROM etms.pod_signatures signature_row
             WHERE signature_row.tenant_id = p_tenant_id
               AND signature_row.signature_file_id = p_file_id
        )
        OR EXISTS (
            SELECT 1
              FROM etms.claim_evidence_items evidence_row
             WHERE evidence_row.tenant_id = p_tenant_id
               AND evidence_row.file_id = p_file_id
        )
        OR EXISTS (
            SELECT 1
              FROM etms.driving_hours_violations violation_row
             WHERE violation_row.tenant_id = p_tenant_id
               AND violation_row.evidence_file_id = p_file_id
        )
        OR EXISTS (
            SELECT 1
              FROM etms.pod_correction_events correction_row
             WHERE correction_row.tenant_id = p_tenant_id
               AND correction_row.evidence_file_id = p_file_id
        )
        OR EXISTS (
            SELECT 1
              FROM etms.pod_verification_events verification_row
             WHERE verification_row.tenant_id = p_tenant_id
               AND verification_row.evidence_file_id = p_file_id
        )
        OR EXISTS (
            SELECT 1
              FROM etms.entity_files entity_file_row
              JOIN etms.audit_event_integrity_anchors anchor_row
                ON anchor_row.tenant_id = entity_file_row.tenant_id
               AND anchor_row.id = entity_file_row.entity_id
             WHERE entity_file_row.tenant_id = p_tenant_id
               AND entity_file_row.file_id = p_file_id
               AND upper(regexp_replace(
                       entity_file_row.entity_type, '[^a-zA-Z0-9]', '', 'g'
                   )) IN ('AUDITEVENTINTEGRITYANCHOR','AUDITANCHOR')
        )
        OR EXISTS (
            SELECT 1
              FROM etms.entity_files entity_file_row
              JOIN etms.proof_of_deliveries pod_row
                ON pod_row.tenant_id = entity_file_row.tenant_id
               AND pod_row.id = entity_file_row.entity_id
               AND pod_row.verification_status = 'VERIFIED'
             WHERE entity_file_row.tenant_id = p_tenant_id
               AND entity_file_row.file_id = p_file_id
               AND upper(regexp_replace(
                       entity_file_row.entity_type, '[^a-zA-Z0-9]', '', 'g'
                   )) IN ('PROOFOFDELIVERY','POD')
        );
$function$;

CREATE OR REPLACE FUNCTION etms.protect_operational_evidence_file()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    protected_file boolean;
BEGIN
    protected_file := OLD.legal_hold
        OR etms.file_has_protected_operational_evidence(OLD.tenant_id, OLD.id);
    IF TG_OP = 'UPDATE' THEN
        protected_file := protected_file OR NEW.legal_hold;
    END IF;
    IF NOT protected_file THEN
        IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
        RETURN NEW;
    END IF;

    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'Legal-hold or operational-evidence files cannot be deleted'
            USING ERRCODE = '55000';
    END IF;
    IF NEW.storage_provider IS DISTINCT FROM OLD.storage_provider
       OR NEW.storage_bucket IS DISTINCT FROM OLD.storage_bucket
       OR NEW.object_key IS DISTINCT FROM OLD.object_key
       OR NEW.byte_size IS DISTINCT FROM OLD.byte_size
       OR NEW.sha256 IS DISTINCT FROM OLD.sha256
       OR NEW.encryption_key_ref IS DISTINCT FROM OLD.encryption_key_ref
       OR NEW.deleted_at IS DISTINCT FROM OLD.deleted_at THEN
        RAISE EXCEPTION
            'Legal-hold or operational-evidence file storage identity and deletion state are immutable'
            USING ERRCODE = '55000';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION etms.protect_operational_evidence_link()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    normalized_entity_type text;
    protected_link boolean;
BEGIN
    normalized_entity_type := upper(regexp_replace(
        OLD.entity_type, '[^a-zA-Z0-9]', '', 'g'
    ));
    protected_link := EXISTS (
        SELECT 1
          FROM etms.files file_row
         WHERE file_row.tenant_id = OLD.tenant_id
           AND file_row.id = OLD.file_id
           AND (
               file_row.legal_hold
               OR etms.file_has_protected_operational_evidence(
                   file_row.tenant_id, file_row.id
               )
           )
    ) OR (
        normalized_entity_type IN ('AUDITEVENTINTEGRITYANCHOR','AUDITANCHOR')
        AND EXISTS (
            SELECT 1
              FROM etms.audit_event_integrity_anchors anchor_row
             WHERE anchor_row.tenant_id = OLD.tenant_id
               AND anchor_row.id = OLD.entity_id
        )
    ) OR (
        normalized_entity_type IN ('PROOFOFDELIVERY','POD')
        AND EXISTS (
            SELECT 1
              FROM etms.proof_of_deliveries pod_row
             WHERE pod_row.tenant_id = OLD.tenant_id
               AND pod_row.id = OLD.entity_id
               AND pod_row.verification_status = 'VERIFIED'
        )
    );
    IF protected_link THEN
        RAISE EXCEPTION 'Operational-evidence file links are immutable; append a new revision'
            USING ERRCODE = '55000';
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_protect_operational_evidence_file ON etms.files;
CREATE TRIGGER trg_protect_operational_evidence_file
    BEFORE UPDATE OF storage_provider, storage_bucket, object_key,
        byte_size, sha256, encryption_key_ref, deleted_at, legal_hold
        OR DELETE ON etms.files
    FOR EACH ROW EXECUTE PROCEDURE etms.protect_operational_evidence_file();
DROP TRIGGER IF EXISTS trg_protect_operational_evidence_file_truncate ON etms.files;
CREATE TRIGGER trg_protect_operational_evidence_file_truncate
    BEFORE TRUNCATE ON etms.files
    FOR EACH STATEMENT EXECUTE PROCEDURE etms.prevent_ledger_mutation();

DROP TRIGGER IF EXISTS trg_protect_operational_evidence_link ON etms.entity_files;
CREATE TRIGGER trg_protect_operational_evidence_link
    BEFORE UPDATE OF tenant_id, entity_type, entity_id, file_id,
        document_type, revision_no OR DELETE ON etms.entity_files
    FOR EACH ROW EXECUTE PROCEDURE etms.protect_operational_evidence_link();
DROP TRIGGER IF EXISTS trg_protect_operational_evidence_link_truncate
    ON etms.entity_files;
CREATE TRIGGER trg_protect_operational_evidence_link_truncate
    BEFORE TRUNCATE ON etms.entity_files
    FOR EACH STATEMENT EXECUTE PROCEDURE etms.prevent_ledger_mutation();

-- ---------------------------------------------------------------------------
-- Common evidence-table security and immutability controls.
-- ---------------------------------------------------------------------------

DO $migration$
DECLARE
    table_name text;
    evidence_tables constant text[] := ARRAY[
        'claim_reserve_movements',
        'driving_hours_violations',
        'handling_unit_parent_history',
        'handling_unit_status_history',
        'order_split_merge_events',
        'pod_correction_events',
        'pod_verification_events',
        'port_terminal_events',
        'rate_quote_acceptance_events',
        'replan_events',
        'stop_dwell_events',
        'tender_award_history'
    ]::text[];
BEGIN
    FOREACH table_name IN ARRAY evidence_tables
    LOOP
        EXECUTE format('ALTER TABLE etms.%I ENABLE ROW LEVEL SECURITY', table_name);
        EXECUTE format('ALTER TABLE etms.%I FORCE ROW LEVEL SECURITY', table_name);
        EXECUTE format('DROP POLICY IF EXISTS tenant_isolation ON etms.%I', table_name);
        EXECUTE format('DROP POLICY IF EXISTS tenant_select ON etms.%I', table_name);
        EXECUTE format('DROP POLICY IF EXISTS tenant_modify ON etms.%I', table_name);
        EXECUTE format(
            'CREATE POLICY tenant_select ON etms.%I FOR SELECT '
            'USING (tenant_id = etms.current_tenant_id())',
            table_name
        );
        EXECUTE format(
            'CREATE POLICY tenant_modify ON etms.%I FOR ALL '
            'USING (tenant_id = etms.current_tenant_id()) '
            'WITH CHECK (tenant_id = etms.current_tenant_id())',
            table_name
        );

        EXECUTE format(
            'DROP TRIGGER IF EXISTS trg_prevent_tenant_change ON etms.%I',
            table_name
        );
        EXECUTE format(
            'CREATE TRIGGER trg_prevent_tenant_change '
            'BEFORE UPDATE OF tenant_id ON etms.%I FOR EACH ROW '
            'EXECUTE PROCEDURE etms.prevent_tenant_change()',
            table_name
        );
        EXECUTE format(
            'DROP TRIGGER IF EXISTS trg_reject_json_secrets ON etms.%I',
            table_name
        );
        EXECUTE format(
            'CREATE TRIGGER trg_reject_json_secrets '
            'BEFORE INSERT OR UPDATE ON etms.%I FOR EACH ROW '
            'EXECUTE PROCEDURE etms.reject_forbidden_json_secrets()',
            table_name
        );
        EXECUTE format(
            'DROP TRIGGER IF EXISTS trg_append_only_row ON etms.%I',
            table_name
        );
        EXECUTE format(
            'CREATE TRIGGER trg_append_only_row '
            'BEFORE UPDATE OR DELETE ON etms.%I FOR EACH ROW '
            'EXECUTE PROCEDURE etms.prevent_ledger_mutation()',
            table_name
        );
        EXECUTE format(
            'DROP TRIGGER IF EXISTS trg_append_only_truncate ON etms.%I',
            table_name
        );
        EXECUTE format(
            'CREATE TRIGGER trg_append_only_truncate '
            'BEFORE TRUNCATE ON etms.%I FOR EACH STATEMENT '
            'EXECUTE PROCEDURE etms.prevent_ledger_mutation()',
            table_name
        );
        EXECUTE format('REVOKE ALL ON TABLE etms.%I FROM PUBLIC', table_name);
    END LOOP;
END;
$migration$;

-- Ensure every FK on the new tables has a non-partial leading index. This is
-- deliberately catalog-driven so force-reapply also repairs a dropped index.
DO $migration$
DECLARE
    relationship record;
    column_list text;
    index_name text;
    evidence_tables constant text[] := ARRAY[
        'claim_reserve_movements','driving_hours_violations',
        'handling_unit_parent_history','handling_unit_status_history',
        'order_split_merge_events','pod_correction_events','pod_verification_events',
        'port_terminal_events','rate_quote_acceptance_events','replan_events',
        'stop_dwell_events','tender_award_history'
    ]::text[];
BEGIN
    FOR relationship IN
        SELECT constraint_row.conname, constraint_row.conrelid,
               relation.relname AS table_name, constraint_row.conkey
          FROM pg_constraint constraint_row
          JOIN pg_class relation ON relation.oid = constraint_row.conrelid
          JOIN pg_namespace namespace_row ON namespace_row.oid = relation.relnamespace
         WHERE namespace_row.nspname = 'etms'
           AND relation.relname = ANY (evidence_tables)
           AND constraint_row.contype = 'f'
    LOOP
        IF EXISTS (
            SELECT 1
              FROM pg_index index_row
             WHERE index_row.indrelid = relationship.conrelid
               AND index_row.indisvalid
               AND index_row.indisready
               AND index_row.indpred IS NULL
               AND (index_row.indkey::smallint[])
                       [0:array_length(relationship.conkey, 1) - 1]
                   = relationship.conkey
        ) THEN
            CONTINUE;
        END IF;
        SELECT string_agg(quote_ident(attribute.attname), ', '
                          ORDER BY key_column.ordinality)
          INTO column_list
          FROM unnest(relationship.conkey)
               WITH ORDINALITY AS key_column(attnum, ordinality)
          JOIN pg_attribute attribute
            ON attribute.attrelid = relationship.conrelid
           AND attribute.attnum = key_column.attnum;
        index_name := 'ix_fk_v03_' || substr(relationship.table_name, 1, 24)
            || '_' || substr(md5(relationship.conname), 1, 10);
        EXECUTE format(
            'CREATE INDEX IF NOT EXISTS %I ON etms.%I (%s)',
            index_name, relationship.table_name, column_list
        );
    END LOOP;
END;
$migration$;

REVOKE ALL ON FUNCTION etms.enforce_initial_operational_status() FROM PUBLIC;
REVOKE ALL ON FUNCTION etms.record_initial_operational_status_history() FROM PUBLIC;
REVOKE ALL ON FUNCTION etms.validate_claim_reserve_movement() FROM PUBLIC;
REVOKE ALL ON FUNCTION etms.validate_driving_hours_violation() FROM PUBLIC;
REVOKE ALL ON FUNCTION etms.validate_pod_correction_event() FROM PUBLIC;
REVOKE ALL ON FUNCTION etms.enforce_pod_item_allocation_totals() FROM PUBLIC;
REVOKE ALL ON FUNCTION etms.validate_stop_dwell_event() FROM PUBLIC;
REVOKE ALL ON FUNCTION etms.record_handling_unit_parent_history() FROM PUBLIC;
REVOKE ALL ON FUNCTION etms.record_handling_unit_status_history() FROM PUBLIC;
REVOKE ALL ON FUNCTION etms.record_rate_quote_acceptance_event() FROM PUBLIC;
REVOKE ALL ON FUNCTION etms.record_tender_award_history() FROM PUBLIC;
REVOKE ALL ON FUNCTION etms.finalize_pod_verification() FROM PUBLIC;
REVOKE ALL ON FUNCTION etms.prevent_verified_pod_mutation() FROM PUBLIC;
REVOKE ALL ON FUNCTION etms.prevent_verified_pod_child_mutation() FROM PUBLIC;
REVOKE ALL ON FUNCTION etms.record_pod_verification_event() FROM PUBLIC;
REVOKE ALL ON FUNCTION etms.file_has_protected_operational_evidence(uuid, uuid)
    FROM PUBLIC;
REVOKE ALL ON FUNCTION etms.protect_operational_evidence_file() FROM PUBLIC;
REVOKE ALL ON FUNCTION etms.protect_operational_evidence_link() FROM PUBLIC;

-- ---------------------------------------------------------------------------
-- Migration-local catalog assertions. Fail rather than bless a same-name,
-- incompatible object during a force replay.
-- ---------------------------------------------------------------------------

DO $migration$
DECLARE
    table_name text;
    evidence_tables constant text[] := ARRAY[
        'claim_reserve_movements','driving_hours_violations',
        'handling_unit_parent_history','handling_unit_status_history',
        'order_split_merge_events','pod_correction_events','pod_verification_events',
        'port_terminal_events','rate_quote_acceptance_events','replan_events',
        'stop_dwell_events','tender_award_history'
    ]::text[];
    relation_oid oid;
BEGIN
    IF array_length(evidence_tables, 1) <> 12 THEN
        RAISE EXCEPTION 'Operational evidence table contract must contain exactly 12 tables';
    END IF;
    FOREACH table_name IN ARRAY evidence_tables
    LOOP
        relation_oid := to_regclass(format('etms.%I', table_name));
        IF relation_oid IS NULL THEN
            RAISE EXCEPTION 'Required operational evidence table etms.% is missing', table_name;
        END IF;
        IF NOT EXISTS (
            SELECT 1
              FROM pg_class relation
             WHERE relation.oid = relation_oid
               AND relation.relkind = 'r'
               AND relation.relrowsecurity
               AND relation.relforcerowsecurity
        ) THEN
            RAISE EXCEPTION 'RLS/FORCE RLS is missing on etms.%', table_name;
        END IF;
        IF NOT EXISTS (
            SELECT 1
              FROM pg_attribute attribute
             WHERE attribute.attrelid = relation_oid
               AND attribute.attname = 'tenant_id'
               AND attribute.attnotnull
               AND NOT attribute.attisdropped
        ) OR NOT EXISTS (
            SELECT 1
              FROM pg_attribute attribute
             WHERE attribute.attrelid = relation_oid
               AND attribute.attname = 'id'
               AND attribute.atttypid = 'uuid'::regtype
               AND attribute.attnotnull
               AND NOT attribute.attisdropped
        ) THEN
            RAISE EXCEPTION 'Required tenant/id contract is missing on etms.%', table_name;
        END IF;
        IF NOT EXISTS (
            SELECT 1 FROM pg_policy policy_row
             WHERE policy_row.polrelid = relation_oid
               AND policy_row.polname = 'tenant_select'
               AND policy_row.polcmd = 'r'
               AND pg_get_expr(policy_row.polqual, policy_row.polrelid)
                   LIKE '%etms.current_tenant_id()%'
        ) OR NOT EXISTS (
            SELECT 1 FROM pg_policy policy_row
             WHERE policy_row.polrelid = relation_oid
               AND policy_row.polname = 'tenant_modify'
               AND policy_row.polcmd = '*'
               AND pg_get_expr(policy_row.polqual, policy_row.polrelid)
                   LIKE '%etms.current_tenant_id()%'
               AND pg_get_expr(policy_row.polwithcheck, policy_row.polrelid)
                   LIKE '%etms.current_tenant_id()%'
        ) THEN
            RAISE EXCEPTION 'Tenant policies are incompatible on etms.%', table_name;
        END IF;
        IF NOT EXISTS (
            SELECT 1 FROM pg_trigger trigger_row
             WHERE trigger_row.tgrelid = relation_oid
               AND trigger_row.tgname = 'trg_prevent_tenant_change'
               AND NOT trigger_row.tgisinternal
               AND trigger_row.tgfoid = to_regprocedure('etms.prevent_tenant_change()')
        ) OR NOT EXISTS (
            SELECT 1 FROM pg_trigger trigger_row
             WHERE trigger_row.tgrelid = relation_oid
               AND trigger_row.tgname = 'trg_append_only_row'
               AND NOT trigger_row.tgisinternal
               AND trigger_row.tgfoid = to_regprocedure('etms.prevent_ledger_mutation()')
        ) OR NOT EXISTS (
            SELECT 1 FROM pg_trigger trigger_row
             WHERE trigger_row.tgrelid = relation_oid
               AND trigger_row.tgname = 'trg_append_only_truncate'
               AND NOT trigger_row.tgisinternal
               AND trigger_row.tgfoid = to_regprocedure('etms.prevent_ledger_mutation()')
        ) OR NOT EXISTS (
            SELECT 1 FROM pg_trigger trigger_row
             WHERE trigger_row.tgrelid = relation_oid
               AND trigger_row.tgname = 'trg_reject_json_secrets'
               AND NOT trigger_row.tgisinternal
               AND trigger_row.tgfoid =
                   to_regprocedure('etms.reject_forbidden_json_secrets()')
        ) THEN
            RAISE EXCEPTION 'Evidence hardening trigger contract is missing on etms.%',
                table_name;
        END IF;
        IF EXISTS (
            SELECT 1 FROM pg_constraint constraint_row
             WHERE constraint_row.conrelid = relation_oid
               AND constraint_row.contype IN ('c','f')
               AND NOT constraint_row.convalidated
        ) THEN
            RAISE EXCEPTION 'Unvalidated CHECK/FK exists on etms.%', table_name;
        END IF;
    END LOOP;

    IF EXISTS (
        SELECT 1
          FROM pg_constraint constraint_row
          JOIN pg_class child_relation ON child_relation.oid = constraint_row.conrelid
          JOIN pg_namespace child_namespace
            ON child_namespace.oid = child_relation.relnamespace
          JOIN pg_class parent_relation ON parent_relation.oid = constraint_row.confrelid
          JOIN pg_namespace parent_namespace
            ON parent_namespace.oid = parent_relation.relnamespace
         WHERE child_namespace.nspname = 'etms'
           AND child_relation.relname = ANY (evidence_tables)
           AND parent_namespace.nspname = 'etms'
           AND constraint_row.contype = 'f'
           AND array_length(constraint_row.conkey, 1) = 1
           AND EXISTS (
               SELECT 1 FROM pg_attribute parent_tenant
                WHERE parent_tenant.attrelid = parent_relation.oid
                  AND parent_tenant.attname = 'tenant_id'
                  AND parent_tenant.attnotnull
                  AND NOT parent_tenant.attisdropped
           )
           AND NOT EXISTS (
               SELECT 1 FROM pg_attribute child_column
                WHERE child_column.attrelid = child_relation.oid
                  AND child_column.attnum = constraint_row.conkey[1]
                  AND child_column.attname = 'tenant_id'
           )
    ) THEN
        RAISE EXCEPTION 'A new evidence table has a non-tenant-scoped FK to a tenant parent';
    END IF;

    IF EXISTS (
        SELECT 1
          FROM pg_constraint constraint_row
          JOIN pg_class relation ON relation.oid = constraint_row.conrelid
          JOIN pg_namespace namespace_row ON namespace_row.oid = relation.relnamespace
         WHERE namespace_row.nspname = 'etms'
           AND relation.relname = ANY (evidence_tables)
           AND constraint_row.contype = 'f'
           AND NOT EXISTS (
               SELECT 1 FROM pg_index index_row
                WHERE index_row.indrelid = constraint_row.conrelid
                  AND index_row.indisvalid AND index_row.indisready
                  AND index_row.indpred IS NULL
                  AND (index_row.indkey::smallint[])
                          [0:array_length(constraint_row.conkey, 1) - 1]
                      = constraint_row.conkey
           )
    ) THEN
        RAISE EXCEPTION 'A new evidence-table FK lacks a valid leading index';
    END IF;
END;
$migration$;

DO $migration$
DECLARE
    required_constraint text;
BEGIN
    FOREACH required_constraint IN ARRAY ARRAY[
        'ck_transport_orders_status_v03',
        'ck_shipments_status_v03',
        'ck_transport_runs_status_v03',
        'ck_dispatch_orders_status_v03',
        'ck_pod_verification_status_v03',
        'ck_pod_verification_fields_v03'
    ]::text[]
    LOOP
        IF NOT EXISTS (
            SELECT 1
              FROM pg_constraint constraint_row
             WHERE constraint_row.conname = required_constraint
               AND constraint_row.contype = 'c'
               AND constraint_row.convalidated
               AND constraint_row.connamespace = 'etms'::regnamespace
        ) THEN
            RAISE EXCEPTION 'Required validated ETMS CHECK % is missing',
                required_constraint;
        END IF;
    END LOOP;
    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger trigger_row
         WHERE trigger_row.tgrelid = 'etms.files'::regclass
           AND trigger_row.tgname = 'trg_protect_operational_evidence_file'
           AND trigger_row.tgfoid =
               to_regprocedure('etms.protect_operational_evidence_file()')
           AND NOT trigger_row.tgisinternal
    ) OR NOT EXISTS (
        SELECT 1 FROM pg_trigger trigger_row
         WHERE trigger_row.tgrelid = 'etms.proof_of_deliveries'::regclass
           AND trigger_row.tgname = 'trg_record_pod_verification'
           AND trigger_row.tgfoid =
               to_regprocedure('etms.record_pod_verification_event()')
           AND NOT trigger_row.tgisinternal
    ) THEN
        RAISE EXCEPTION 'POD/file evidence hardening trigger contract is incomplete';
    END IF;
END;
$migration$;
