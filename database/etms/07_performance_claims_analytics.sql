-- ETMS transport results, SLA/KPI, carrier performance, emissions, claims, and reporting facts.

CREATE TABLE IF NOT EXISTS etms.shipment_results (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    shipment_id uuid NOT NULL REFERENCES etms.shipments(id),
    result_version integer NOT NULL DEFAULT 1,
    actual_pickup_at timestamptz,
    actual_delivery_at timestamptz,
    actual_transit_minutes integer,
    pickup_variance_minutes integer,
    delivery_variance_minutes integer,
    actual_distance_km numeric(20,3),
    actual_weight_kg numeric(20,6),
    actual_volume_m3 numeric(20,6),
    delivered_quantity numeric(20,6),
    quantity_uom_code varchar(20) REFERENCES etms.units_of_measure(uom_code),
    damaged_quantity numeric(20,6) NOT NULL DEFAULT 0,
    shortage_quantity numeric(20,6) NOT NULL DEFAULT 0,
    stop_count integer NOT NULL DEFAULT 0,
    exception_count integer NOT NULL DEFAULT 0,
    on_time_pickup boolean,
    on_time_delivery boolean,
    in_full boolean,
    otif boolean,
    pod_complete boolean NOT NULL DEFAULT false,
    actual_buy_cost numeric(20,4),
    actual_sell_revenue numeric(20,4),
    buy_currency_code char(3) REFERENCES etms.currencies(currency_code),
    sell_currency_code char(3) REFERENCES etms.currencies(currency_code),
    emissions_kg_co2e numeric(20,6),
    calculated_at timestamptz NOT NULL DEFAULT now(),
    calculation_version varchar(80) NOT NULL,
    source_lineage jsonb NOT NULL DEFAULT '{}'::jsonb,
    UNIQUE (shipment_id, result_version),
    CONSTRAINT ck_shipment_result_version CHECK (result_version > 0),
    CONSTRAINT ck_shipment_result_dates CHECK (actual_delivery_at IS NULL OR actual_pickup_at IS NULL OR actual_delivery_at >= actual_pickup_at),
    CONSTRAINT ck_shipment_result_values CHECK (
        (actual_transit_minutes IS NULL OR actual_transit_minutes >= 0) AND
        (actual_distance_km IS NULL OR actual_distance_km >= 0) AND
        (actual_weight_kg IS NULL OR actual_weight_kg >= 0) AND
        (actual_volume_m3 IS NULL OR actual_volume_m3 >= 0) AND
        (damaged_quantity >= 0 AND shortage_quantity >= 0 AND stop_count >= 0 AND exception_count >= 0)
    )
);

CREATE TABLE IF NOT EXISTS etms.run_results (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    run_id uuid NOT NULL REFERENCES etms.transport_runs(id),
    result_version integer NOT NULL DEFAULT 1,
    actual_start_at timestamptz,
    actual_end_at timestamptz,
    actual_drive_minutes integer,
    actual_duty_minutes integer,
    actual_wait_minutes integer,
    actual_service_minutes integer,
    actual_distance_km numeric(20,3),
    empty_distance_km numeric(20,3),
    loaded_distance_km numeric(20,3),
    max_weight_kg numeric(20,6),
    max_volume_m3 numeric(20,6),
    weight_utilization_percent numeric(9,6),
    volume_utilization_percent numeric(9,6),
    energy_used_quantity numeric(20,6),
    energy_uom_code varchar(20) REFERENCES etms.units_of_measure(uom_code),
    distance_per_energy_unit numeric(20,6),
    stop_count integer NOT NULL DEFAULT 0,
    completed_stop_count integer NOT NULL DEFAULT 0,
    exception_count integer NOT NULL DEFAULT 0,
    actual_cost numeric(20,4),
    currency_code char(3) REFERENCES etms.currencies(currency_code),
    emissions_kg_co2e numeric(20,6),
    calculated_at timestamptz NOT NULL DEFAULT now(),
    calculation_version varchar(80) NOT NULL,
    source_lineage jsonb NOT NULL DEFAULT '{}'::jsonb,
    UNIQUE (run_id, result_version),
    CONSTRAINT ck_run_result_version CHECK (result_version > 0),
    CONSTRAINT ck_run_result_dates CHECK (actual_end_at IS NULL OR actual_start_at IS NULL OR actual_end_at >= actual_start_at),
    CONSTRAINT ck_run_result_distances CHECK ((actual_distance_km IS NULL OR actual_distance_km >= 0) AND (empty_distance_km IS NULL OR empty_distance_km >= 0) AND (loaded_distance_km IS NULL OR loaded_distance_km >= 0)),
    CONSTRAINT ck_run_result_utilization CHECK ((weight_utilization_percent IS NULL OR weight_utilization_percent >= 0) AND (volume_utilization_percent IS NULL OR volume_utilization_percent >= 0)),
    CONSTRAINT ck_run_result_counts CHECK (stop_count >= 0 AND completed_stop_count >= 0 AND completed_stop_count <= stop_count AND exception_count >= 0)
);

CREATE TABLE IF NOT EXISTS etms.stop_results (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    run_stop_id uuid NOT NULL REFERENCES etms.run_stops(id),
    result_version integer NOT NULL DEFAULT 1,
    first_arrival_at timestamptz,
    final_departure_at timestamptz,
    waiting_minutes integer,
    service_minutes integer,
    arrival_variance_minutes integer,
    quantity_loaded numeric(20,6) NOT NULL DEFAULT 0,
    quantity_unloaded numeric(20,6) NOT NULL DEFAULT 0,
    discrepancy_quantity numeric(20,6) NOT NULL DEFAULT 0,
    quantity_uom_code varchar(20) REFERENCES etms.units_of_measure(uom_code),
    appointment_compliant boolean,
    completed_first_attempt boolean,
    calculated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (run_stop_id, result_version),
    CONSTRAINT ck_stop_result_dates CHECK (final_departure_at IS NULL OR first_arrival_at IS NULL OR final_departure_at >= first_arrival_at),
    CONSTRAINT ck_stop_result_values CHECK ((waiting_minutes IS NULL OR waiting_minutes >= 0) AND (service_minutes IS NULL OR service_minutes >= 0) AND quantity_loaded >= 0 AND quantity_unloaded >= 0 AND discrepancy_quantity >= 0)
);

CREATE TABLE IF NOT EXISTS etms.run_leg_results (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    run_leg_execution_id uuid NOT NULL REFERENCES etms.run_leg_executions(id),
    result_version integer NOT NULL DEFAULT 1,
    actual_duration_minutes integer,
    actual_distance_km numeric(20,3),
    loaded_weight_kg numeric(20,6),
    loaded_volume_m3 numeric(20,6),
    fuel_or_energy_quantity numeric(20,6),
    energy_uom_code varchar(20) REFERENCES etms.units_of_measure(uom_code),
    buy_cost numeric(20,4),
    buy_currency_code char(3) REFERENCES etms.currencies(currency_code),
    emissions_kg_co2e numeric(20,6),
    is_final boolean NOT NULL DEFAULT false,
    calculated_at timestamptz NOT NULL DEFAULT now(),
    calculation_version varchar(80) NOT NULL,
    source_lineage jsonb NOT NULL DEFAULT '{}'::jsonb,
    UNIQUE (run_leg_execution_id, result_version),
    CONSTRAINT ck_run_leg_result_version CHECK (result_version > 0),
    CONSTRAINT ck_run_leg_result_values CHECK (
        (actual_duration_minutes IS NULL OR actual_duration_minutes >= 0) AND
        (actual_distance_km IS NULL OR actual_distance_km >= 0) AND
        (loaded_weight_kg IS NULL OR loaded_weight_kg >= 0) AND
        (loaded_volume_m3 IS NULL OR loaded_volume_m3 >= 0) AND
        (fuel_or_energy_quantity IS NULL OR fuel_or_energy_quantity >= 0)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_run_leg_results_final
    ON etms.run_leg_results (run_leg_execution_id)
    WHERE is_final;

CREATE TABLE IF NOT EXISTS etms.service_level_results (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    sla_policy_id uuid NOT NULL REFERENCES etms.sla_policies(id),
    sla_milestone_id uuid REFERENCES etms.sla_policy_milestones(id),
    order_id uuid REFERENCES etms.transport_orders(id),
    shipment_id uuid REFERENCES etms.shipments(id),
    run_id uuid REFERENCES etms.transport_runs(id),
    carrier_id uuid REFERENCES etms.business_partners(id),
    customer_id uuid REFERENCES etms.business_partners(id),
    target_at timestamptz,
    actual_at timestamptz,
    variance_minutes integer,
    compliant boolean NOT NULL,
    breach_reason_code varchar(80),
    excluded boolean NOT NULL DEFAULT false,
    exclusion_reason text,
    penalty_amount numeric(20,4),
    currency_code char(3) REFERENCES etms.currencies(currency_code),
    calculated_at timestamptz NOT NULL DEFAULT now(),
    calculation_version varchar(80) NOT NULL,
    source_lineage jsonb NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT ck_service_result_entity CHECK (order_id IS NOT NULL OR shipment_id IS NOT NULL OR run_id IS NOT NULL),
    CONSTRAINT ck_service_result_penalty CHECK (penalty_amount IS NULL OR penalty_amount >= 0)
);

CREATE TABLE IF NOT EXISTS etms.carrier_scorecards (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    carrier_id uuid NOT NULL REFERENCES etms.business_partners(id),
    period_type varchar(20) NOT NULL,
    period_start date NOT NULL,
    period_end date NOT NULL,
    mode_code varchar(20) REFERENCES etms.transport_modes(mode_code),
    lane_id uuid REFERENCES etms.lanes(id),
    shipment_count integer NOT NULL DEFAULT 0,
    overall_score numeric(9,6),
    tier varchar(30),
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    published_at timestamptz,
    calculated_at timestamptz NOT NULL DEFAULT now(),
    calculation_version varchar(80) NOT NULL,
    CONSTRAINT ck_carrier_scorecard_dates CHECK (period_end >= period_start),
    CONSTRAINT ck_carrier_scorecard_count CHECK (shipment_count >= 0),
    CONSTRAINT ck_carrier_scorecard_score CHECK (overall_score IS NULL OR overall_score BETWEEN 0 AND 100)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_carrier_scorecards_scope
    ON etms.carrier_scorecards (
        tenant_id, carrier_id, period_type, period_start,
        COALESCE(mode_code, ''),
        COALESCE(lane_id, '00000000-0000-0000-0000-000000000000'::uuid)
    );

CREATE TABLE IF NOT EXISTS etms.carrier_scorecard_metrics (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    scorecard_id uuid NOT NULL REFERENCES etms.carrier_scorecards(id) ON DELETE CASCADE,
    metric_code varchar(80) NOT NULL,
    metric_value numeric(30,10),
    target_value numeric(30,10),
    score numeric(9,6),
    weight_percent numeric(7,4) NOT NULL DEFAULT 0,
    numerator numeric(30,10),
    denominator numeric(30,10),
    sample_size integer,
    source_lineage jsonb NOT NULL DEFAULT '{}'::jsonb,
    UNIQUE (scorecard_id, metric_code),
    CONSTRAINT ck_scorecard_metric_score CHECK (score IS NULL OR score BETWEEN 0 AND 100),
    CONSTRAINT ck_scorecard_metric_weight CHECK (weight_percent BETWEEN 0 AND 100),
    CONSTRAINT ck_scorecard_metric_sample CHECK (sample_size IS NULL OR sample_size >= 0)
);

CREATE TABLE IF NOT EXISTS etms.emission_factors (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid REFERENCES etms.tenants(id) ON DELETE CASCADE,
    factor_code varchar(100) NOT NULL,
    methodology varchar(100) NOT NULL,
    methodology_version varchar(80) NOT NULL,
    mode_code varchar(20) REFERENCES etms.transport_modes(mode_code),
    vehicle_type_id uuid REFERENCES etms.vehicle_types(id),
    equipment_type_id uuid REFERENCES etms.equipment_types(id),
    fuel_type varchar(30),
    load_factor_from numeric(9,6),
    load_factor_to numeric(9,6),
    factor_value numeric(30,12) NOT NULL,
    factor_uom varchar(80) NOT NULL,
    well_to_tank_factor numeric(30,12),
    tank_to_wheel_factor numeric(30,12),
    country_code char(2) REFERENCES etms.countries(country_code),
    valid_from date NOT NULL,
    valid_to date,
    source_reference varchar(500) NOT NULL,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_emission_factor_value CHECK (factor_value >= 0),
    CONSTRAINT ck_emission_factor_load CHECK (load_factor_to IS NULL OR load_factor_from IS NULL OR load_factor_to >= load_factor_from),
    CONSTRAINT ck_emission_factor_dates CHECK (valid_to IS NULL OR valid_to >= valid_from)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_emission_factors_scope
    ON etms.emission_factors (
        COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), factor_code, valid_from
    );

CREATE TABLE IF NOT EXISTS etms.emission_calculations (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    entity_type varchar(20) NOT NULL,
    entity_id uuid NOT NULL,
    emission_scope varchar(30) NOT NULL,
    factor_id uuid REFERENCES etms.emission_factors(id),
    methodology varchar(100) NOT NULL,
    methodology_version varchar(80) NOT NULL,
    activity_value numeric(30,10) NOT NULL,
    activity_uom varchar(80) NOT NULL,
    distance_km numeric(20,3),
    weight_tonnes numeric(20,6),
    tonne_km numeric(24,6),
    fuel_quantity numeric(20,6),
    fuel_uom_code varchar(20) REFERENCES etms.units_of_measure(uom_code),
    co2_kg numeric(20,6) NOT NULL DEFAULT 0,
    ch4_kg numeric(20,9) NOT NULL DEFAULT 0,
    n2o_kg numeric(20,9) NOT NULL DEFAULT 0,
    co2e_kg numeric(20,6) NOT NULL,
    allocation_method varchar(30),
    data_quality_score numeric(7,4),
    calculated_at timestamptz NOT NULL DEFAULT now(),
    input_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
    source_lineage jsonb NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT ck_emission_calc_entity CHECK (entity_type IN ('ORDER','SHIPMENT','LEG','RUN')),
    CONSTRAINT ck_emission_calc_values CHECK (activity_value >= 0 AND co2_kg >= 0 AND ch4_kg >= 0 AND n2o_kg >= 0 AND co2e_kg >= 0),
    CONSTRAINT ck_emission_calc_quality CHECK (data_quality_score IS NULL OR data_quality_score BETWEEN 0 AND 100)
);

CREATE TABLE IF NOT EXISTS etms.claims (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    claim_no varchar(100) NOT NULL,
    claim_type varchar(30) NOT NULL,
    claimant_partner_id uuid NOT NULL REFERENCES etms.business_partners(id),
    respondent_partner_id uuid NOT NULL REFERENCES etms.business_partners(id),
    liable_carrier_id uuid REFERENCES etms.business_partners(id),
    order_id uuid REFERENCES etms.transport_orders(id),
    shipment_id uuid REFERENCES etms.shipments(id),
    run_id uuid REFERENCES etms.transport_runs(id),
    incident_id uuid REFERENCES etms.incidents(id),
    damage_report_id uuid REFERENCES etms.damage_reports(id),
    claim_date date NOT NULL,
    loss_date date,
    notification_deadline date,
    filing_deadline date,
    claimed_amount numeric(20,4) NOT NULL,
    approved_amount numeric(20,4),
    paid_amount numeric(20,4) NOT NULL DEFAULT 0,
    currency_code char(3) NOT NULL REFERENCES etms.currencies(currency_code),
    description text NOT NULL,
    root_cause_code varchar(80),
    liability_percent numeric(7,4),
    status varchar(30) NOT NULL DEFAULT 'DRAFT',
    assigned_to_user_id uuid REFERENCES etms.users(id),
    closed_at timestamptz,
    closure_reason text,
    row_version bigint NOT NULL DEFAULT 1,
    created_by uuid REFERENCES etms.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, claim_no),
    CONSTRAINT ck_claim_parties CHECK (claimant_partner_id <> respondent_partner_id),
    CONSTRAINT ck_claim_entity CHECK (order_id IS NOT NULL OR shipment_id IS NOT NULL OR run_id IS NOT NULL OR incident_id IS NOT NULL),
    CONSTRAINT ck_claim_amounts CHECK (
        claimed_amount >= 0 AND
        (approved_amount IS NULL OR (approved_amount >= 0 AND approved_amount <= claimed_amount)) AND
        paid_amount >= 0 AND paid_amount <= COALESCE(approved_amount, claimed_amount)
    ),
    CONSTRAINT ck_claim_liability CHECK (liability_percent IS NULL OR liability_percent BETWEEN 0 AND 100)
);

CREATE TABLE IF NOT EXISTS etms.claim_items (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    claim_id uuid NOT NULL REFERENCES etms.claims(id) ON DELETE CASCADE,
    line_no integer NOT NULL,
    order_line_id uuid REFERENCES etms.transport_order_lines(id),
    handling_unit_id uuid REFERENCES etms.handling_units(id),
    claim_category varchar(50) NOT NULL,
    quantity numeric(20,6),
    uom_code varchar(20) REFERENCES etms.units_of_measure(uom_code),
    unit_value numeric(20,4),
    claimed_amount numeric(20,4) NOT NULL,
    approved_amount numeric(20,4),
    description text,
    UNIQUE (claim_id, line_no),
    CONSTRAINT ck_claim_item_line CHECK (line_no > 0),
    CONSTRAINT ck_claim_item_values CHECK ((quantity IS NULL OR quantity >= 0) AND (unit_value IS NULL OR unit_value >= 0) AND claimed_amount >= 0 AND (approved_amount IS NULL OR approved_amount >= 0))
);

CREATE TABLE IF NOT EXISTS etms.claim_events (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    claim_id uuid NOT NULL REFERENCES etms.claims(id) ON DELETE CASCADE,
    event_type varchar(50) NOT NULL,
    from_status varchar(30),
    to_status varchar(30),
    event_detail text,
    amount numeric(20,4),
    currency_code char(3) REFERENCES etms.currencies(currency_code),
    actor_user_id uuid REFERENCES etms.users(id),
    actor_partner_id uuid REFERENCES etms.business_partners(id),
    occurred_at timestamptz NOT NULL DEFAULT now(),
    file_id uuid REFERENCES etms.files(id)
);

CREATE TABLE IF NOT EXISTS etms.claim_reserves (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    claim_id uuid NOT NULL REFERENCES etms.claims(id) ON DELETE CASCADE,
    reserve_type varchar(30) NOT NULL,
    reserve_amount numeric(20,4) NOT NULL,
    currency_code char(3) NOT NULL REFERENCES etms.currencies(currency_code),
    effective_date date NOT NULL,
    released_amount numeric(20,4) NOT NULL DEFAULT 0,
    released_at timestamptz,
    reason text,
    approved_by uuid REFERENCES etms.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_claim_reserve_amounts CHECK (reserve_amount >= 0 AND released_amount >= 0 AND released_amount <= reserve_amount)
);

CREATE TABLE IF NOT EXISTS etms.claim_settlements (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    claim_id uuid NOT NULL REFERENCES etms.claims(id) ON DELETE CASCADE,
    settlement_no varchar(100) NOT NULL,
    settlement_type varchar(30) NOT NULL,
    payer_partner_id uuid NOT NULL REFERENCES etms.business_partners(id),
    payee_partner_id uuid NOT NULL REFERENCES etms.business_partners(id),
    settlement_amount numeric(20,4) NOT NULL,
    currency_code char(3) NOT NULL REFERENCES etms.currencies(currency_code),
    settlement_date date NOT NULL,
    payment_reference varchar(200),
    release_text text,
    status varchar(20) NOT NULL DEFAULT 'AGREED',
    file_id uuid REFERENCES etms.files(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (claim_id, settlement_no),
    CONSTRAINT ck_claim_settlement_parties CHECK (payer_partner_id <> payee_partner_id),
    CONSTRAINT ck_claim_settlement_amount CHECK (settlement_amount >= 0)
);

CREATE TABLE IF NOT EXISTS etms.customer_feedback (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    customer_id uuid NOT NULL REFERENCES etms.business_partners(id),
    order_id uuid REFERENCES etms.transport_orders(id),
    shipment_id uuid REFERENCES etms.shipments(id),
    feedback_type varchar(30) NOT NULL,
    rating smallint,
    category_code varchar(80),
    comments text,
    submitted_at timestamptz NOT NULL DEFAULT now(),
    contact_consent boolean NOT NULL DEFAULT false,
    follow_up_status varchar(20) NOT NULL DEFAULT 'NONE',
    assigned_to uuid REFERENCES etms.users(id),
    CONSTRAINT ck_customer_feedback_entity CHECK (order_id IS NOT NULL OR shipment_id IS NOT NULL),
    CONSTRAINT ck_customer_feedback_rating CHECK (rating IS NULL OR rating BETWEEN 1 AND 5)
);

CREATE TABLE IF NOT EXISTS etms.kpi_definitions (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid REFERENCES etms.tenants(id) ON DELETE CASCADE,
    kpi_code varchar(100) NOT NULL,
    kpi_name varchar(250) NOT NULL,
    domain varchar(50) NOT NULL,
    description text,
    unit_code varchar(30) NOT NULL,
    aggregation_method varchar(30) NOT NULL,
    numerator_definition text,
    denominator_definition text,
    calculation_expression jsonb NOT NULL DEFAULT '{}'::jsonb,
    calculation_version varchar(80) NOT NULL,
    direction varchar(20) NOT NULL DEFAULT 'HIGHER_BETTER',
    frequency varchar(20) NOT NULL,
    owner_org_unit_id uuid REFERENCES etms.organization_units(id),
    valid_from date NOT NULL,
    valid_to date,
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_kpi_definitions_scope
    ON etms.kpi_definitions (
        COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), kpi_code, calculation_version
    );

CREATE TABLE IF NOT EXISTS etms.kpi_targets (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    kpi_definition_id uuid NOT NULL REFERENCES etms.kpi_definitions(id),
    scope_type varchar(30) NOT NULL,
    scope_id uuid,
    period_start date NOT NULL,
    period_end date NOT NULL,
    target_value numeric(30,10) NOT NULL,
    warning_threshold numeric(30,10),
    critical_threshold numeric(30,10),
    approved_by uuid REFERENCES etms.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_kpi_target_dates CHECK (period_end >= period_start)
);

CREATE TABLE IF NOT EXISTS etms.kpi_values (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    kpi_definition_id uuid NOT NULL REFERENCES etms.kpi_definitions(id),
    scope_type varchar(30) NOT NULL,
    scope_id uuid,
    period_start date NOT NULL,
    period_end date NOT NULL,
    kpi_value numeric(30,10),
    numerator numeric(30,10),
    denominator numeric(30,10),
    sample_size bigint,
    quality_status varchar(20) NOT NULL DEFAULT 'VALID',
    calculated_at timestamptz NOT NULL DEFAULT now(),
    source_lineage jsonb NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT ck_kpi_value_dates CHECK (period_end >= period_start),
    CONSTRAINT ck_kpi_value_sample CHECK (sample_size IS NULL OR sample_size >= 0)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_kpi_values_scope_period
    ON etms.kpi_values (
        tenant_id, kpi_definition_id, scope_type,
        COALESCE(scope_id, '00000000-0000-0000-0000-000000000000'::uuid),
        period_start, period_end
    );

CREATE TABLE IF NOT EXISTS etms.transport_daily_facts (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    fact_date date NOT NULL,
    organization_id uuid NOT NULL REFERENCES etms.organizations(id),
    mode_code varchar(20),
    customer_id uuid,
    carrier_id uuid,
    order_count bigint NOT NULL DEFAULT 0,
    shipment_count bigint NOT NULL DEFAULT 0,
    run_count bigint NOT NULL DEFAULT 0,
    delivered_count bigint NOT NULL DEFAULT 0,
    on_time_pickup_count bigint NOT NULL DEFAULT 0,
    on_time_delivery_count bigint NOT NULL DEFAULT 0,
    otif_count bigint NOT NULL DEFAULT 0,
    exception_count bigint NOT NULL DEFAULT 0,
    claim_count bigint NOT NULL DEFAULT 0,
    total_weight_kg numeric(30,6) NOT NULL DEFAULT 0,
    total_volume_m3 numeric(30,6) NOT NULL DEFAULT 0,
    total_distance_km numeric(30,3) NOT NULL DEFAULT 0,
    buy_cost_base numeric(30,4) NOT NULL DEFAULT 0,
    sell_revenue_base numeric(30,4) NOT NULL DEFAULT 0,
    emissions_kg_co2e numeric(30,6) NOT NULL DEFAULT 0,
    loaded_at timestamptz NOT NULL DEFAULT now(),
    source_watermark timestamptz
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_transport_daily_facts_grain
    ON etms.transport_daily_facts (
        tenant_id, fact_date, organization_id,
        COALESCE(mode_code, ''),
        COALESCE(customer_id, '00000000-0000-0000-0000-000000000000'::uuid),
        COALESCE(carrier_id, '00000000-0000-0000-0000-000000000000'::uuid)
    );

CREATE TABLE IF NOT EXISTS etms.lane_performance_facts (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    fact_month date NOT NULL,
    lane_id uuid NOT NULL REFERENCES etms.lanes(id),
    carrier_id uuid REFERENCES etms.business_partners(id),
    shipment_count bigint NOT NULL DEFAULT 0,
    total_weight_kg numeric(30,6) NOT NULL DEFAULT 0,
    average_transit_minutes numeric(20,4),
    p90_transit_minutes numeric(20,4),
    on_time_delivery_percent numeric(9,6),
    average_cost_per_kg numeric(24,8),
    average_cost_per_km numeric(24,8),
    empty_distance_percent numeric(9,6),
    claim_rate_percent numeric(9,6),
    emissions_kg_co2e numeric(30,6),
    loaded_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_lane_performance_facts_grain
    ON etms.lane_performance_facts (
        tenant_id, fact_month, lane_id,
        COALESCE(carrier_id, '00000000-0000-0000-0000-000000000000'::uuid)
    );

CREATE TABLE IF NOT EXISTS etms.carrier_performance_facts (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    fact_month date NOT NULL,
    carrier_id uuid NOT NULL REFERENCES etms.business_partners(id),
    mode_code varchar(20),
    tender_count bigint NOT NULL DEFAULT 0,
    tender_accept_count bigint NOT NULL DEFAULT 0,
    shipment_count bigint NOT NULL DEFAULT 0,
    on_time_pickup_count bigint NOT NULL DEFAULT 0,
    on_time_delivery_count bigint NOT NULL DEFAULT 0,
    claim_count bigint NOT NULL DEFAULT 0,
    exception_count bigint NOT NULL DEFAULT 0,
    invoiced_amount_base numeric(30,4) NOT NULL DEFAULT 0,
    invoice_variance_amount_base numeric(30,4) NOT NULL DEFAULT 0,
    average_score numeric(9,6),
    loaded_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_carrier_performance_facts_grain
    ON etms.carrier_performance_facts (
        tenant_id, fact_month, carrier_id, COALESCE(mode_code, '')
    );

CREATE TABLE IF NOT EXISTS etms.financial_performance_facts (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    fact_month date NOT NULL,
    organization_id uuid NOT NULL REFERENCES etms.organizations(id),
    customer_id uuid,
    carrier_id uuid,
    mode_code varchar(20),
    currency_code char(3) NOT NULL,
    sell_revenue numeric(30,4) NOT NULL DEFAULT 0,
    buy_cost numeric(30,4) NOT NULL DEFAULT 0,
    gross_margin numeric(30,4) NOT NULL DEFAULT 0,
    accrual_amount numeric(30,4) NOT NULL DEFAULT 0,
    invoice_variance numeric(30,4) NOT NULL DEFAULT 0,
    claim_cost numeric(30,4) NOT NULL DEFAULT 0,
    shipment_count bigint NOT NULL DEFAULT 0,
    loaded_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_financial_performance_facts_grain
    ON etms.financial_performance_facts (
        tenant_id, fact_month, organization_id,
        COALESCE(customer_id, '00000000-0000-0000-0000-000000000000'::uuid),
        COALESCE(carrier_id, '00000000-0000-0000-0000-000000000000'::uuid),
        COALESCE(mode_code, ''), currency_code
    );

CREATE TABLE IF NOT EXISTS etms.fleet_utilization_facts (
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    fact_date date NOT NULL,
    vehicle_id uuid NOT NULL REFERENCES etms.vehicles(id),
    available_minutes integer NOT NULL DEFAULT 0,
    dispatched_minutes integer NOT NULL DEFAULT 0,
    driving_minutes integer NOT NULL DEFAULT 0,
    idle_minutes integer NOT NULL DEFAULT 0,
    maintenance_minutes integer NOT NULL DEFAULT 0,
    loaded_distance_km numeric(20,3) NOT NULL DEFAULT 0,
    empty_distance_km numeric(20,3) NOT NULL DEFAULT 0,
    fuel_used_l numeric(20,6) NOT NULL DEFAULT 0,
    emissions_kg_co2e numeric(20,6) NOT NULL DEFAULT 0,
    loaded_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, fact_date, vehicle_id)
);

CREATE TABLE IF NOT EXISTS etms.emission_facts (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    fact_month date NOT NULL,
    organization_id uuid NOT NULL REFERENCES etms.organizations(id),
    mode_code varchar(20),
    customer_id uuid,
    carrier_id uuid,
    co2e_kg numeric(30,6) NOT NULL DEFAULT 0,
    well_to_tank_co2e_kg numeric(30,6) NOT NULL DEFAULT 0,
    tank_to_wheel_co2e_kg numeric(30,6) NOT NULL DEFAULT 0,
    tonne_km numeric(30,6) NOT NULL DEFAULT 0,
    intensity_g_co2e_per_tonne_km numeric(30,10),
    measured_percent numeric(9,6),
    estimated_percent numeric(9,6),
    loaded_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_emission_facts_grain
    ON etms.emission_facts (
        tenant_id, fact_month, organization_id,
        COALESCE(mode_code, ''),
        COALESCE(customer_id, '00000000-0000-0000-0000-000000000000'::uuid),
        COALESCE(carrier_id, '00000000-0000-0000-0000-000000000000'::uuid)
    );

CREATE TABLE IF NOT EXISTS etms.data_quality_rules (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid REFERENCES etms.tenants(id) ON DELETE CASCADE,
    rule_code varchar(100) NOT NULL,
    rule_name varchar(250) NOT NULL,
    entity_type varchar(80) NOT NULL,
    severity varchar(20) NOT NULL,
    rule_expression jsonb NOT NULL,
    threshold_percent numeric(7,4),
    is_active boolean NOT NULL DEFAULT true,
    owner_user_id uuid REFERENCES etms.users(id),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_data_quality_rules_scope
    ON etms.data_quality_rules (
        COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), rule_code
    );

CREATE TABLE IF NOT EXISTS etms.data_quality_results (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    rule_id uuid NOT NULL REFERENCES etms.data_quality_rules(id),
    run_at timestamptz NOT NULL,
    entity_id uuid,
    record_count bigint NOT NULL DEFAULT 0,
    failure_count bigint NOT NULL DEFAULT 0,
    failure_percent numeric(9,6),
    status varchar(20) NOT NULL,
    sample_failures jsonb NOT NULL DEFAULT '[]'::jsonb,
    resolved_at timestamptz,
    resolution text,
    CONSTRAINT ck_data_quality_counts CHECK (record_count >= 0 AND failure_count >= 0 AND failure_count <= record_count),
    CONSTRAINT ck_data_quality_percent CHECK (failure_percent IS NULL OR failure_percent BETWEEN 0 AND 100)
);

CREATE TABLE IF NOT EXISTS etms.etl_watermarks (
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    pipeline_code varchar(100) NOT NULL,
    source_entity varchar(100) NOT NULL,
    watermark_type varchar(20) NOT NULL,
    watermark_value varchar(500),
    last_success_at timestamptz,
    last_attempt_at timestamptz,
    status varchar(20) NOT NULL DEFAULT 'IDLE',
    row_count bigint,
    error_detail_masked text,
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, pipeline_code, source_entity)
);
