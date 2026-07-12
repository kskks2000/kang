-- ETMS commercial contracts, rates, quotes, fuel indexes, SLA, and capacity commitments.

CREATE TABLE IF NOT EXISTS etms.rate_contracts (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    contract_no varchar(80) NOT NULL,
    contract_name varchar(300) NOT NULL,
    contract_type varchar(30) NOT NULL,
    organization_id uuid NOT NULL REFERENCES etms.organizations(id),
    owner_org_unit_id uuid REFERENCES etms.organization_units(id),
    base_currency_code char(3) NOT NULL REFERENCES etms.currencies(currency_code),
    valid_from date NOT NULL,
    valid_to date NOT NULL,
    auto_renew boolean NOT NULL DEFAULT false,
    notice_days integer,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    UNIQUE (tenant_id, contract_no),
    CONSTRAINT ck_rate_contracts_type CHECK (contract_type IN ('BUY','SELL','BIDIRECTIONAL','SPOT_FRAMEWORK')),
    CONSTRAINT ck_rate_contracts_dates CHECK (valid_to >= valid_from),
    CONSTRAINT ck_rate_contracts_notice CHECK (notice_days IS NULL OR notice_days >= 0),
    CONSTRAINT ck_rate_contracts_status CHECK (status IN ('DRAFT','UNDER_REVIEW','APPROVED','ACTIVE','SUSPENDED','EXPIRED','TERMINATED'))
);

CREATE TABLE IF NOT EXISTS etms.rate_contract_versions (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    contract_id uuid NOT NULL REFERENCES etms.rate_contracts(id) ON DELETE CASCADE,
    version_no integer NOT NULL,
    effective_from date NOT NULL,
    effective_to date,
    amendment_no varchar(80),
    change_summary text,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    approved_by uuid REFERENCES etms.users(id),
    approved_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (contract_id, version_no),
    CONSTRAINT ck_contract_versions_no CHECK (version_no > 0),
    CONSTRAINT ck_contract_versions_dates CHECK (effective_to IS NULL OR effective_to >= effective_from),
    CONSTRAINT ck_contract_versions_status CHECK (status IN ('DRAFT','APPROVED','ACTIVE','SUPERSEDED','CANCELLED'))
);

CREATE TABLE IF NOT EXISTS etms.contract_parties (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    contract_id uuid NOT NULL REFERENCES etms.rate_contracts(id) ON DELETE CASCADE,
    partner_id uuid NOT NULL REFERENCES etms.business_partners(id),
    party_role varchar(30) NOT NULL,
    is_primary boolean NOT NULL DEFAULT false,
    billing_currency_code char(3) REFERENCES etms.currencies(currency_code),
    payment_term_id uuid REFERENCES etms.payment_terms(id),
    valid_from date,
    valid_to date,
    UNIQUE (contract_id, partner_id, party_role),
    CONSTRAINT ck_contract_parties_role CHECK (party_role IN ('CUSTOMER','CARRIER','SUBCONTRACTOR','BROKER','BILL_TO','PAY_TO','GUARANTOR'))
);

CREATE TABLE IF NOT EXISTS etms.contract_service_scopes (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    contract_version_id uuid NOT NULL REFERENCES etms.rate_contract_versions(id) ON DELETE CASCADE,
    mode_code varchar(20) REFERENCES etms.transport_modes(mode_code),
    service_level_id uuid REFERENCES etms.service_levels(id),
    equipment_type_id uuid REFERENCES etms.equipment_types(id),
    origin_region_id uuid REFERENCES etms.service_regions(id),
    destination_region_id uuid REFERENCES etms.service_regions(id),
    commodity_class_id uuid REFERENCES etms.commodity_classes(id),
    include_exclude varchar(10) NOT NULL DEFAULT 'INCLUDE',
    conditions jsonb NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT ck_contract_scope_mode CHECK (include_exclude IN ('INCLUDE','EXCLUDE'))
);

CREATE TABLE IF NOT EXISTS etms.rate_lanes (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    contract_version_id uuid NOT NULL REFERENCES etms.rate_contract_versions(id) ON DELETE CASCADE,
    lane_id uuid REFERENCES etms.lanes(id),
    origin_location_id uuid REFERENCES etms.locations(id),
    origin_region_id uuid REFERENCES etms.service_regions(id),
    destination_location_id uuid REFERENCES etms.locations(id),
    destination_region_id uuid REFERENCES etms.service_regions(id),
    mode_code varchar(20) NOT NULL REFERENCES etms.transport_modes(mode_code),
    service_level_id uuid REFERENCES etms.service_levels(id),
    equipment_type_id uuid REFERENCES etms.equipment_types(id),
    transit_minutes integer,
    minimum_charge numeric(20,4),
    currency_code char(3) NOT NULL REFERENCES etms.currencies(currency_code),
    valid_from date NOT NULL,
    valid_to date,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_rate_lanes_origin CHECK ((origin_location_id IS NOT NULL)::int + (origin_region_id IS NOT NULL)::int + (lane_id IS NOT NULL)::int >= 1),
    CONSTRAINT ck_rate_lanes_destination CHECK ((destination_location_id IS NOT NULL)::int + (destination_region_id IS NOT NULL)::int + (lane_id IS NOT NULL)::int >= 1),
    CONSTRAINT ck_rate_lanes_minimum CHECK (minimum_charge IS NULL OR minimum_charge >= 0),
    CONSTRAINT ck_rate_lanes_dates CHECK (valid_to IS NULL OR valid_to >= valid_from)
);

CREATE TABLE IF NOT EXISTS etms.rate_rules (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    contract_version_id uuid NOT NULL REFERENCES etms.rate_contract_versions(id) ON DELETE CASCADE,
    rate_lane_id uuid REFERENCES etms.rate_lanes(id) ON DELETE CASCADE,
    rule_code varchar(80) NOT NULL,
    charge_code_id uuid NOT NULL REFERENCES etms.charge_codes(id),
    direction varchar(10) NOT NULL,
    calculation_method varchar(30) NOT NULL,
    basis_type varchar(30) NOT NULL,
    basis_uom_code varchar(20) REFERENCES etms.units_of_measure(uom_code),
    unit_rate numeric(24,8),
    flat_amount numeric(20,4),
    minimum_amount numeric(20,4),
    maximum_amount numeric(20,4),
    currency_code char(3) NOT NULL REFERENCES etms.currencies(currency_code),
    rounding_mode varchar(20) NOT NULL DEFAULT 'HALF_UP',
    rounding_scale smallint NOT NULL DEFAULT 2,
    priority integer NOT NULL DEFAULT 100,
    condition_expression jsonb NOT NULL DEFAULT '{}'::jsonb,
    valid_from date NOT NULL,
    valid_to date,
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (contract_version_id, rule_code),
    CONSTRAINT ck_rate_rules_direction CHECK (direction IN ('BUY','SELL')),
    CONSTRAINT ck_rate_rules_method CHECK (calculation_method IN ('FLAT','PER_UNIT','TIERED','BREAK','PERCENT','FORMULA','MINIMUM','MAXIMUM')),
    CONSTRAINT ck_rate_rules_basis CHECK (basis_type IN ('SHIPMENT','ORDER','LEG','RUN','STOP','WEIGHT','VOLUME','DISTANCE','PALLET','HANDLING_UNIT','TIME','VALUE','QUANTITY')),
    CONSTRAINT ck_rate_rules_rounding CHECK (rounding_scale BETWEEN 0 AND 8),
    CONSTRAINT ck_rate_rules_amounts CHECK (
        (unit_rate IS NULL OR unit_rate >= 0) AND
        (flat_amount IS NULL OR flat_amount >= 0) AND
        (minimum_amount IS NULL OR minimum_amount >= 0) AND
        (maximum_amount IS NULL OR maximum_amount >= 0) AND
        (maximum_amount IS NULL OR minimum_amount IS NULL OR maximum_amount >= minimum_amount)
    ),
    CONSTRAINT ck_rate_rules_dates CHECK (valid_to IS NULL OR valid_to >= valid_from)
);

CREATE TABLE IF NOT EXISTS etms.rate_rule_tiers (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    rate_rule_id uuid NOT NULL REFERENCES etms.rate_rules(id) ON DELETE CASCADE,
    tier_no integer NOT NULL,
    from_value numeric(24,8) NOT NULL,
    to_value numeric(24,8),
    unit_rate numeric(24,8),
    flat_amount numeric(20,4),
    cumulative boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (rate_rule_id, tier_no),
    CONSTRAINT ck_rate_rule_tiers_no CHECK (tier_no > 0),
    CONSTRAINT ck_rate_rule_tiers_range CHECK (to_value IS NULL OR to_value > from_value),
    CONSTRAINT ck_rate_rule_tiers_price CHECK ((unit_rate IS NOT NULL)::int + (flat_amount IS NOT NULL)::int >= 1)
);

CREATE TABLE IF NOT EXISTS etms.accessorial_rules (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    contract_version_id uuid NOT NULL REFERENCES etms.rate_contract_versions(id) ON DELETE CASCADE,
    charge_code_id uuid NOT NULL REFERENCES etms.charge_codes(id),
    trigger_event_type varchar(100),
    approval_required boolean NOT NULL DEFAULT false,
    evidence_required boolean NOT NULL DEFAULT false,
    grace_quantity numeric(20,6) NOT NULL DEFAULT 0,
    grace_uom_code varchar(20) REFERENCES etms.units_of_measure(uom_code),
    unit_rate numeric(24,8),
    flat_amount numeric(20,4),
    maximum_amount numeric(20,4),
    currency_code char(3) NOT NULL REFERENCES etms.currencies(currency_code),
    condition_expression jsonb NOT NULL DEFAULT '{}'::jsonb,
    valid_from date NOT NULL,
    valid_to date,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_accessorial_grace CHECK (grace_quantity >= 0),
    CONSTRAINT ck_accessorial_dates CHECK (valid_to IS NULL OR valid_to >= valid_from)
);

CREATE TABLE IF NOT EXISTS etms.fuel_indices (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid REFERENCES etms.tenants(id) ON DELETE CASCADE,
    index_code varchar(80) NOT NULL,
    index_name varchar(200) NOT NULL,
    country_code char(2) REFERENCES etms.countries(country_code),
    fuel_type varchar(30) NOT NULL,
    currency_code char(3) NOT NULL REFERENCES etms.currencies(currency_code),
    price_uom_code varchar(20) NOT NULL REFERENCES etms.units_of_measure(uom_code),
    publisher varchar(200),
    frequency varchar(20) NOT NULL,
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_fuel_indices_scope
    ON etms.fuel_indices (
        COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), index_code
    );

CREATE TABLE IF NOT EXISTS etms.fuel_index_values (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    fuel_index_id uuid NOT NULL REFERENCES etms.fuel_indices(id) ON DELETE CASCADE,
    effective_date date NOT NULL,
    index_value numeric(24,8) NOT NULL,
    published_at timestamptz,
    source_reference varchar(500),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (fuel_index_id, effective_date),
    CONSTRAINT ck_fuel_index_value CHECK (index_value >= 0)
);

CREATE TABLE IF NOT EXISTS etms.fuel_surcharge_rules (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    contract_version_id uuid NOT NULL REFERENCES etms.rate_contract_versions(id) ON DELETE CASCADE,
    fuel_index_id uuid NOT NULL REFERENCES etms.fuel_indices(id),
    charge_code_id uuid NOT NULL REFERENCES etms.charge_codes(id),
    base_index_value numeric(24,8) NOT NULL,
    base_fuel_percent numeric(9,6) NOT NULL DEFAULT 0,
    change_interval numeric(24,8) NOT NULL,
    surcharge_percent_per_interval numeric(9,6) NOT NULL,
    minimum_percent numeric(9,6),
    maximum_percent numeric(9,6),
    lag_days integer NOT NULL DEFAULT 0,
    effective_from date NOT NULL,
    effective_to date,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_fuel_surcharge_base CHECK (base_index_value >= 0 AND change_interval > 0),
    CONSTRAINT ck_fuel_surcharge_lag CHECK (lag_days >= 0),
    CONSTRAINT ck_fuel_surcharge_dates CHECK (effective_to IS NULL OR effective_to >= effective_from)
);

CREATE TABLE IF NOT EXISTS etms.rate_quotes (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    quote_no varchar(80) NOT NULL,
    quote_type varchar(20) NOT NULL DEFAULT 'SELL',
    customer_id uuid REFERENCES etms.business_partners(id),
    carrier_id uuid REFERENCES etms.business_partners(id),
    mode_code varchar(20) NOT NULL REFERENCES etms.transport_modes(mode_code),
    service_level_id uuid REFERENCES etms.service_levels(id),
    origin_location_id uuid REFERENCES etms.locations(id),
    destination_location_id uuid REFERENCES etms.locations(id),
    planned_ship_date date,
    total_weight_kg numeric(20,6),
    total_volume_m3 numeric(20,6),
    equipment_type_id uuid REFERENCES etms.equipment_types(id),
    currency_code char(3) NOT NULL REFERENCES etms.currencies(currency_code),
    net_amount numeric(20,4) NOT NULL DEFAULT 0,
    tax_amount numeric(20,4) NOT NULL DEFAULT 0,
    gross_amount numeric(20,4) NOT NULL DEFAULT 0,
    valid_until timestamptz,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    accepted_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, quote_no),
    CONSTRAINT ck_rate_quotes_type CHECK (quote_type IN ('BUY','SELL')),
    CONSTRAINT ck_rate_quotes_amounts CHECK (
        net_amount >= 0 AND tax_amount >= 0
        AND gross_amount = net_amount + tax_amount
    )
);

CREATE TABLE IF NOT EXISTS etms.rate_quote_lines (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    quote_id uuid NOT NULL REFERENCES etms.rate_quotes(id) ON DELETE CASCADE,
    line_no integer NOT NULL,
    charge_code_id uuid NOT NULL REFERENCES etms.charge_codes(id),
    description text,
    quantity numeric(20,6) NOT NULL DEFAULT 1,
    uom_code varchar(20) REFERENCES etms.units_of_measure(uom_code),
    unit_rate numeric(24,8) NOT NULL,
    net_amount numeric(20,4) NOT NULL,
    tax_code_id uuid REFERENCES etms.tax_codes(id),
    tax_amount numeric(20,4) NOT NULL DEFAULT 0,
    gross_amount numeric(20,4) NOT NULL,
    rate_rule_id uuid REFERENCES etms.rate_rules(id),
    calculation_trace jsonb NOT NULL DEFAULT '{}'::jsonb,
    UNIQUE (quote_id, line_no),
    CONSTRAINT ck_quote_lines_no CHECK (line_no > 0),
    CONSTRAINT ck_quote_lines_qty CHECK (quantity >= 0),
    CONSTRAINT ck_quote_lines_amounts CHECK (
        net_amount >= 0 AND tax_amount >= 0
        AND gross_amount = net_amount + tax_amount
    )
);

CREATE TABLE IF NOT EXISTS etms.rating_runs (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    run_type varchar(20) NOT NULL,
    entity_type varchar(30) NOT NULL,
    entity_id uuid NOT NULL,
    requested_currency_code char(3) REFERENCES etms.currencies(currency_code),
    rule_snapshot_at timestamptz NOT NULL,
    input_snapshot jsonb NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'RUNNING',
    started_at timestamptz NOT NULL DEFAULT now(),
    completed_at timestamptz,
    error_detail_masked text,
    created_by uuid REFERENCES etms.users(id),
    CONSTRAINT ck_rating_runs_type CHECK (run_type IN ('BUY','SELL','BOTH','AUDIT')),
    CONSTRAINT ck_rating_runs_entity CHECK (entity_type IN ('ORDER','SHIPMENT','LEG','RUN','QUOTE'))
);

CREATE TABLE IF NOT EXISTS etms.rating_run_details (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    rating_run_id uuid NOT NULL REFERENCES etms.rating_runs(id) ON DELETE CASCADE,
    sequence_no integer NOT NULL,
    rate_rule_id uuid REFERENCES etms.rate_rules(id),
    charge_code_id uuid REFERENCES etms.charge_codes(id),
    matched boolean NOT NULL,
    basis_value numeric(24,8),
    basis_uom_code varchar(20) REFERENCES etms.units_of_measure(uom_code),
    calculated_amount numeric(20,4),
    currency_code char(3) REFERENCES etms.currencies(currency_code),
    trace jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (rating_run_id, sequence_no)
);

CREATE TABLE IF NOT EXISTS etms.sla_policies (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    policy_code varchar(80) NOT NULL,
    policy_name varchar(200) NOT NULL,
    customer_id uuid REFERENCES etms.business_partners(id),
    carrier_id uuid REFERENCES etms.business_partners(id),
    contract_version_id uuid REFERENCES etms.rate_contract_versions(id),
    mode_code varchar(20) REFERENCES etms.transport_modes(mode_code),
    service_level_id uuid REFERENCES etms.service_levels(id),
    valid_from date NOT NULL,
    valid_to date,
    priority integer NOT NULL DEFAULT 100,
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, policy_code),
    CONSTRAINT ck_sla_policies_dates CHECK (valid_to IS NULL OR valid_to >= valid_from)
);

CREATE TABLE IF NOT EXISTS etms.sla_policy_milestones (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    sla_policy_id uuid NOT NULL REFERENCES etms.sla_policies(id) ON DELETE CASCADE,
    milestone_code varchar(80) NOT NULL,
    target_type varchar(30) NOT NULL,
    target_minutes integer,
    tolerance_early_minutes integer NOT NULL DEFAULT 0,
    tolerance_late_minutes integer NOT NULL DEFAULT 0,
    business_calendar_id uuid REFERENCES etms.business_calendars(id),
    penalty_rule jsonb NOT NULL DEFAULT '{}'::jsonb,
    weight_percent numeric(7,4) NOT NULL DEFAULT 0,
    UNIQUE (sla_policy_id, milestone_code),
    CONSTRAINT ck_sla_milestone_target CHECK (target_type IN ('TRANSIT','PICKUP_WINDOW','DELIVERY_WINDOW','EVENT_AFTER_EVENT','RESPONSE_TIME')),
    CONSTRAINT ck_sla_milestone_minutes CHECK ((target_minutes IS NULL OR target_minutes >= 0) AND tolerance_early_minutes >= 0 AND tolerance_late_minutes >= 0),
    CONSTRAINT ck_sla_milestone_weight CHECK (weight_percent BETWEEN 0 AND 100)
);

CREATE TABLE IF NOT EXISTS etms.carrier_capacity_commitments (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    contract_version_id uuid REFERENCES etms.rate_contract_versions(id),
    carrier_id uuid NOT NULL REFERENCES etms.business_partners(id),
    lane_id uuid REFERENCES etms.lanes(id),
    service_region_id uuid REFERENCES etms.service_regions(id),
    equipment_type_id uuid REFERENCES etms.equipment_types(id),
    period_type varchar(20) NOT NULL,
    period_start date NOT NULL,
    period_end date NOT NULL,
    committed_quantity numeric(20,6) NOT NULL,
    uom_code varchar(20) NOT NULL REFERENCES etms.units_of_measure(uom_code),
    minimum_acceptance_percent numeric(7,4),
    penalty_rule jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_capacity_commitment_dates CHECK (period_end >= period_start),
    CONSTRAINT ck_capacity_commitment_qty CHECK (committed_quantity >= 0),
    CONSTRAINT ck_capacity_acceptance CHECK (minimum_acceptance_percent IS NULL OR minimum_acceptance_percent BETWEEN 0 AND 100)
);

