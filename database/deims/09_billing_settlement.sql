-- DEIMS enterprise WMS schema - service contracts, rating, charges, invoicing, settlement, payment, and accounting.

CREATE TABLE IF NOT EXISTS deims.service_contracts (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    contract_no varchar(120) NOT NULL,
    contract_name varchar(250) NOT NULL,
    contract_type varchar(30) NOT NULL,
    organization_id uuid NOT NULL REFERENCES deims.organizations(id),
    owner_partner_id uuid REFERENCES deims.business_partners(id),
    counterparty_partner_id uuid NOT NULL REFERENCES deims.business_partners(id),
    currency_code char(3) NOT NULL REFERENCES deims.currencies(currency_code),
    payment_term_id uuid REFERENCES deims.payment_terms(id),
    valid_from date NOT NULL,
    valid_to date,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    auto_renew boolean NOT NULL DEFAULT false,
    notice_days integer,
    row_version bigint NOT NULL DEFAULT 1,
    created_by uuid REFERENCES deims.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, contract_no),
    CONSTRAINT ck_deims_contract_type CHECK (contract_type IN ('CUSTOMER','SUPPLIER','CARRIER','CUSTOMS_BROKER','LABOR','OTHER')),
    CONSTRAINT ck_deims_contract_dates CHECK (valid_to IS NULL OR valid_to >= valid_from),
    CONSTRAINT ck_deims_contract_notice CHECK (notice_days IS NULL OR notice_days >= 0),
    CONSTRAINT ck_deims_contract_status CHECK (status IN ('DRAFT','APPROVAL_PENDING','ACTIVE','SUSPENDED','EXPIRED','TERMINATED'))
);

CREATE TABLE IF NOT EXISTS deims.service_contract_versions (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    contract_id uuid NOT NULL REFERENCES deims.service_contracts(id) ON DELETE CASCADE,
    version_no integer NOT NULL,
    effective_from date NOT NULL,
    effective_to date,
    terms_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
    document_file_id uuid REFERENCES deims.files(id),
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    approved_by uuid REFERENCES deims.users(id),
    approved_at timestamptz,
    created_by uuid REFERENCES deims.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (contract_id, version_no),
    CONSTRAINT ck_deims_contract_version_no CHECK (version_no > 0),
    CONSTRAINT ck_deims_contract_version_dates CHECK (effective_to IS NULL OR effective_to >= effective_from),
    CONSTRAINT ck_deims_contract_version_status CHECK (status IN ('DRAFT','APPROVAL_PENDING','ACTIVE','SUPERSEDED','REJECTED'))
);

CREATE TABLE IF NOT EXISTS deims.contract_services (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    contract_version_id uuid NOT NULL REFERENCES deims.service_contract_versions(id) ON DELETE CASCADE,
    service_code varchar(80) NOT NULL,
    service_name varchar(200) NOT NULL,
    charge_code_id uuid NOT NULL REFERENCES deims.charge_codes(id),
    warehouse_id uuid REFERENCES deims.warehouses(id),
    owner_partner_id uuid REFERENCES deims.business_partners(id),
    billing_frequency varchar(20) NOT NULL DEFAULT 'MONTHLY',
    minimum_charge numeric(20,4),
    maximum_charge numeric(20,4),
    included_quantity numeric(24,8),
    included_uom_code varchar(20) REFERENCES deims.units_of_measure(uom_code),
    taxable boolean NOT NULL DEFAULT true,
    is_active boolean NOT NULL DEFAULT true,
    UNIQUE (contract_version_id, service_code),
    CONSTRAINT ck_deims_contract_service_frequency CHECK (billing_frequency IN ('EVENT','DAILY','WEEKLY','MONTHLY','QUARTERLY','MANUAL')),
    CONSTRAINT ck_deims_contract_service_amounts CHECK (
        (minimum_charge IS NULL OR minimum_charge >= 0) AND (maximum_charge IS NULL OR maximum_charge >= 0) AND
        (minimum_charge IS NULL OR maximum_charge IS NULL OR maximum_charge >= minimum_charge) AND
        (included_quantity IS NULL OR included_quantity >= 0)
    )
);

CREATE TABLE IF NOT EXISTS deims.rate_rules (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    contract_service_id uuid NOT NULL REFERENCES deims.contract_services(id) ON DELETE CASCADE,
    rule_no integer NOT NULL,
    rule_name varchar(200) NOT NULL,
    charge_basis varchar(30) NOT NULL,
    basis_uom_code varchar(20) REFERENCES deims.units_of_measure(uom_code),
    rate_amount numeric(24,8),
    rate_percent numeric(12,8),
    flat_amount numeric(20,4),
    currency_code char(3) NOT NULL REFERENCES deims.currencies(currency_code),
    minimum_amount numeric(20,4),
    maximum_amount numeric(20,4),
    rounding_mode varchar(20) NOT NULL DEFAULT 'HALF_UP',
    rounding_scale smallint NOT NULL DEFAULT 4,
    condition_expression jsonb NOT NULL DEFAULT '{}'::jsonb,
    priority integer NOT NULL DEFAULT 100,
    stackable boolean NOT NULL DEFAULT false,
    valid_from date,
    valid_to date,
    is_active boolean NOT NULL DEFAULT true,
    UNIQUE (contract_service_id, rule_no),
    CONSTRAINT ck_deims_rate_rule_no CHECK (rule_no > 0),
    CONSTRAINT ck_deims_rate_basis CHECK (charge_basis IN (
        'FLAT','QUANTITY','WEIGHT','VOLUME','PALLET','LPN','LOCATION','AREA','DAY','HOUR','EVENT','PERCENT','TIERED','ACTUAL'
    )),
    CONSTRAINT ck_deims_rate_value CHECK (num_nonnulls(rate_amount,rate_percent,flat_amount) >= 1),
    CONSTRAINT ck_deims_rate_percent CHECK (rate_percent IS NULL OR rate_percent >= 0),
    CONSTRAINT ck_deims_rate_limits CHECK (
        (minimum_amount IS NULL OR minimum_amount >= 0) AND (maximum_amount IS NULL OR maximum_amount >= 0) AND
        (minimum_amount IS NULL OR maximum_amount IS NULL OR maximum_amount >= minimum_amount)
    ),
    CONSTRAINT ck_deims_rate_rounding CHECK (rounding_mode IN ('HALF_UP','HALF_EVEN','UP','DOWN','CEILING','FLOOR') AND rounding_scale BETWEEN 0 AND 8),
    CONSTRAINT ck_deims_rate_dates CHECK (valid_to IS NULL OR valid_from IS NULL OR valid_to >= valid_from)
);

CREATE TABLE IF NOT EXISTS deims.rate_rule_tiers (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    rate_rule_id uuid NOT NULL REFERENCES deims.rate_rules(id) ON DELETE CASCADE,
    tier_no integer NOT NULL,
    from_quantity numeric(24,8) NOT NULL,
    to_quantity numeric(24,8),
    rate_amount numeric(24,8) NOT NULL,
    flat_amount numeric(20,4) NOT NULL DEFAULT 0,
    UNIQUE (rate_rule_id, tier_no),
    CONSTRAINT ck_deims_rate_tier_no CHECK (tier_no > 0),
    CONSTRAINT ck_deims_rate_tier_range CHECK (from_quantity >= 0 AND (to_quantity IS NULL OR to_quantity > from_quantity)),
    CONSTRAINT ck_deims_rate_tier_amount CHECK (rate_amount >= 0 AND flat_amount >= 0)
);

CREATE TABLE IF NOT EXISTS deims.charge_events (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    warehouse_id uuid NOT NULL REFERENCES deims.warehouses(id),
    owner_partner_id uuid NOT NULL REFERENCES deims.business_partners(id),
    event_type varchar(80) NOT NULL,
    event_no varchar(150),
    source_entity_type varchar(80) NOT NULL,
    source_entity_id uuid NOT NULL,
    source_line_id uuid,
    occurred_at timestamptz NOT NULL,
    service_date date NOT NULL,
    quantity numeric(24,8),
    uom_code varchar(20) REFERENCES deims.units_of_measure(uom_code),
    weight numeric(24,8),
    volume numeric(24,9),
    duration_minutes numeric(20,4),
    amount numeric(20,4),
    currency_code char(3) REFERENCES deims.currencies(currency_code),
    attributes_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
    source_system_id uuid REFERENCES deims.external_systems(id),
    idempotency_key varchar(300) NOT NULL,
    rated_at timestamptz,
    status varchar(20) NOT NULL DEFAULT 'NEW',
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, source_system_id, idempotency_key),
    CONSTRAINT ck_deims_charge_event_measures CHECK (
        (quantity IS NULL OR quantity >= 0) AND (weight IS NULL OR weight >= 0) AND
        (volume IS NULL OR volume >= 0) AND (duration_minutes IS NULL OR duration_minutes >= 0) AND
        (amount IS NULL OR amount >= 0)
    ),
    CONSTRAINT ck_deims_charge_event_status CHECK (status IN ('NEW','RATING','RATED','FAILED','WAIVED','REVERSED'))
);

CREATE TABLE IF NOT EXISTS deims.rating_runs (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    rating_run_no varchar(120) NOT NULL,
    run_type varchar(20) NOT NULL DEFAULT 'EVENT',
    service_period_from date,
    service_period_to date,
    owner_partner_id uuid REFERENCES deims.business_partners(id),
    warehouse_id uuid REFERENCES deims.warehouses(id),
    status varchar(20) NOT NULL DEFAULT 'QUEUED',
    requested_by uuid REFERENCES deims.users(id),
    requested_at timestamptz NOT NULL DEFAULT now(),
    started_at timestamptz,
    completed_at timestamptz,
    total_events integer NOT NULL DEFAULT 0,
    success_events integer NOT NULL DEFAULT 0,
    failed_events integer NOT NULL DEFAULT 0,
    input_parameters jsonb NOT NULL DEFAULT '{}'::jsonb,
    result_summary jsonb NOT NULL DEFAULT '{}'::jsonb,
    UNIQUE (tenant_id, rating_run_no),
    CONSTRAINT ck_deims_rating_run_type CHECK (run_type IN ('EVENT','PERIODIC','RECALCULATION','SIMULATION','MANUAL')),
    CONSTRAINT ck_deims_rating_run_period CHECK (service_period_to IS NULL OR service_period_from IS NULL OR service_period_to >= service_period_from),
    CONSTRAINT ck_deims_rating_run_counts CHECK (
        total_events >= 0 AND success_events >= 0 AND failed_events >= 0 AND success_events + failed_events <= total_events
    ),
    CONSTRAINT ck_deims_rating_run_dates CHECK (completed_at IS NULL OR started_at IS NULL OR completed_at >= started_at)
);

CREATE TABLE IF NOT EXISTS deims.rating_run_details (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    rating_run_id uuid NOT NULL REFERENCES deims.rating_runs(id) ON DELETE CASCADE,
    charge_event_id uuid NOT NULL REFERENCES deims.charge_events(id),
    contract_version_id uuid REFERENCES deims.service_contract_versions(id),
    contract_service_id uuid REFERENCES deims.contract_services(id),
    rate_rule_id uuid REFERENCES deims.rate_rules(id),
    basis_quantity numeric(24,8),
    basis_uom_code varchar(20) REFERENCES deims.units_of_measure(uom_code),
    applied_rate numeric(24,8),
    calculated_net_amount numeric(20,4),
    calculation_trace jsonb NOT NULL DEFAULT '{}'::jsonb,
    status varchar(20) NOT NULL,
    error_code varchar(80),
    error_detail_masked text,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (rating_run_id, charge_event_id, contract_service_id),
    CONSTRAINT ck_deims_rating_detail_basis CHECK (basis_quantity IS NULL OR basis_quantity >= 0),
    CONSTRAINT ck_deims_rating_detail_amount CHECK (calculated_net_amount IS NULL OR calculated_net_amount >= 0)
);

CREATE TABLE IF NOT EXISTS deims.charges (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    charge_no varchar(150) NOT NULL,
    direction varchar(20) NOT NULL,
    stage varchar(20) NOT NULL DEFAULT 'ACTUAL',
    charge_code_id uuid NOT NULL REFERENCES deims.charge_codes(id),
    charge_event_id uuid REFERENCES deims.charge_events(id),
    rating_detail_id uuid REFERENCES deims.rating_run_details(id),
    contract_version_id uuid REFERENCES deims.service_contract_versions(id),
    warehouse_id uuid NOT NULL REFERENCES deims.warehouses(id),
    owner_partner_id uuid NOT NULL REFERENCES deims.business_partners(id),
    payer_partner_id uuid NOT NULL REFERENCES deims.business_partners(id),
    payee_partner_id uuid NOT NULL REFERENCES deims.business_partners(id),
    service_date date NOT NULL,
    service_period_from date,
    service_period_to date,
    source_entity_type varchar(80),
    source_entity_id uuid,
    source_line_id uuid,
    quantity numeric(24,8),
    uom_code varchar(20) REFERENCES deims.units_of_measure(uom_code),
    unit_rate numeric(24,8),
    currency_code char(3) NOT NULL REFERENCES deims.currencies(currency_code),
    net_amount numeric(20,4) NOT NULL,
    tax_code_id uuid REFERENCES deims.tax_codes(id),
    tax_rate_percent numeric(9,6),
    tax_amount numeric(20,4) NOT NULL DEFAULT 0,
    gross_amount numeric(20,4) NOT NULL,
    base_currency_code char(3) REFERENCES deims.currencies(currency_code),
    exchange_rate numeric(24,12),
    base_amount numeric(20,4),
    status varchar(20) NOT NULL DEFAULT 'OPEN',
    billable boolean NOT NULL DEFAULT true,
    accrued boolean NOT NULL DEFAULT false,
    invoiced boolean NOT NULL DEFAULT false,
    settled boolean NOT NULL DEFAULT false,
    reversal_of_charge_id uuid REFERENCES deims.charges(id),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, charge_no),
    CONSTRAINT ck_deims_charge_direction CHECK (direction IN ('RECEIVABLE','PAYABLE')),
    CONSTRAINT ck_deims_charge_stage CHECK (stage IN ('ESTIMATE','ACCRUAL','ACTUAL','INVOICE','SETTLEMENT')),
    CONSTRAINT ck_deims_charge_parties CHECK (payer_partner_id <> payee_partner_id),
    CONSTRAINT ck_deims_charge_period CHECK (service_period_to IS NULL OR service_period_from IS NULL OR service_period_to >= service_period_from),
    CONSTRAINT ck_deims_charge_qty CHECK (quantity IS NULL OR quantity >= 0),
    CONSTRAINT ck_deims_charge_tax_rate CHECK (tax_rate_percent IS NULL OR tax_rate_percent BETWEEN 0 AND 100),
    CONSTRAINT ck_deims_charge_amounts CHECK (
        net_amount >= 0 AND tax_amount >= 0 AND gross_amount = net_amount + tax_amount AND
        (exchange_rate IS NULL OR exchange_rate > 0) AND (base_amount IS NULL OR base_amount >= 0)
    ),
    CONSTRAINT ck_deims_charge_reversal CHECK (reversal_of_charge_id IS NULL OR reversal_of_charge_id <> id),
    CONSTRAINT ck_deims_charge_status CHECK (status IN ('OPEN','ON_HOLD','APPROVED','INVOICED','SETTLED','WAIVED','REVERSED','CANCELLED'))
);

CREATE TABLE IF NOT EXISTS deims.charge_allocations (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    charge_id uuid NOT NULL REFERENCES deims.charges(id) ON DELETE CASCADE,
    allocation_no integer NOT NULL,
    warehouse_id uuid REFERENCES deims.warehouses(id),
    owner_partner_id uuid REFERENCES deims.business_partners(id),
    outbound_order_id uuid REFERENCES deims.outbound_orders(id),
    inbound_order_id uuid REFERENCES deims.inbound_orders(id),
    shipment_id uuid REFERENCES deims.shipments(id),
    receipt_id uuid REFERENCES deims.receipts(id),
    source_entity_type varchar(80),
    source_entity_id uuid,
    allocation_percent numeric(9,6),
    allocated_net_amount numeric(20,4) NOT NULL,
    allocated_tax_amount numeric(20,4) NOT NULL DEFAULT 0,
    allocated_gross_amount numeric(20,4) NOT NULL,
    reversed_by uuid REFERENCES deims.users(id),
    reversed_at timestamptz,
    reversal_reason text,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (charge_id, allocation_no),
    CONSTRAINT ck_deims_charge_alloc_no CHECK (allocation_no > 0),
    CONSTRAINT ck_deims_charge_alloc_target CHECK (
        num_nonnulls(outbound_order_id,inbound_order_id,shipment_id,receipt_id) = 1
        AND source_entity_type IS NULL AND source_entity_id IS NULL
    ),
    CONSTRAINT ck_deims_charge_alloc_percent CHECK (allocation_percent IS NULL OR allocation_percent BETWEEN 0 AND 100),
    CONSTRAINT ck_deims_charge_alloc_amount CHECK (
        allocated_net_amount >= 0 AND allocated_tax_amount >= 0 AND
        allocated_gross_amount > 0 AND
        allocated_gross_amount = allocated_net_amount + allocated_tax_amount
    ),
    CONSTRAINT ck_deims_charge_alloc_reversal CHECK (
        (reversed_at IS NULL AND reversed_by IS NULL AND reversal_reason IS NULL) OR
        (reversed_at IS NOT NULL AND reversed_by IS NOT NULL AND
         reversal_reason IS NOT NULL AND btrim(reversal_reason) <> '' AND
         reversed_at >= created_at)
    )
);

CREATE TABLE IF NOT EXISTS deims.charge_adjustments (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    charge_id uuid NOT NULL REFERENCES deims.charges(id),
    adjustment_no integer NOT NULL,
    adjustment_type varchar(30) NOT NULL,
    reason_code_id uuid REFERENCES deims.reason_codes(id),
    reason_text text NOT NULL,
    net_amount_delta numeric(20,4) NOT NULL,
    tax_amount_delta numeric(20,4) NOT NULL DEFAULT 0,
    gross_amount_delta numeric(20,4) NOT NULL,
    requested_by uuid REFERENCES deims.users(id),
    requested_at timestamptz NOT NULL DEFAULT now(),
    approval_status varchar(20) NOT NULL DEFAULT 'PENDING',
    approved_by uuid REFERENCES deims.users(id),
    approved_at timestamptz,
    applied_at timestamptz,
    evidence_file_id uuid REFERENCES deims.files(id),
    UNIQUE (charge_id, adjustment_no),
    CONSTRAINT ck_deims_charge_adjustment_no CHECK (adjustment_no > 0),
    CONSTRAINT ck_deims_charge_adjustment_amount CHECK (gross_amount_delta = net_amount_delta + tax_amount_delta),
    CONSTRAINT ck_deims_charge_adjustment_approval CHECK (approval_status IN ('PENDING','APPROVED','REJECTED','CANCELLED'))
);

CREATE TABLE IF NOT EXISTS deims.accruals (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    accrual_no varchar(120) NOT NULL,
    charge_id uuid NOT NULL REFERENCES deims.charges(id),
    accounting_date date NOT NULL,
    accounting_period varchar(20) NOT NULL,
    organization_id uuid NOT NULL REFERENCES deims.organizations(id),
    partner_id uuid NOT NULL REFERENCES deims.business_partners(id),
    currency_code char(3) NOT NULL REFERENCES deims.currencies(currency_code),
    accrued_amount numeric(20,4) NOT NULL,
    base_currency_code char(3) NOT NULL REFERENCES deims.currencies(currency_code),
    base_amount numeric(20,4) NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'OPEN',
    reversed_at timestamptz,
    reversal_accrual_id uuid REFERENCES deims.accruals(id),
    invoice_line_id uuid,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, accrual_no),
    CONSTRAINT ck_deims_accrual_amount CHECK (accrued_amount >= 0 AND base_amount >= 0),
    CONSTRAINT ck_deims_accrual_reversal CHECK (reversal_accrual_id IS NULL OR reversal_accrual_id <> id)
);

CREATE TABLE IF NOT EXISTS deims.landed_costs (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    landed_cost_no varchar(120) NOT NULL,
    owner_partner_id uuid NOT NULL REFERENCES deims.business_partners(id),
    receipt_id uuid REFERENCES deims.receipts(id),
    trade_shipment_id uuid REFERENCES deims.trade_shipments(id),
    customs_declaration_id uuid REFERENCES deims.customs_declarations(id),
    currency_code char(3) NOT NULL REFERENCES deims.currencies(currency_code),
    freight_amount numeric(20,4) NOT NULL DEFAULT 0,
    duty_amount numeric(20,4) NOT NULL DEFAULT 0,
    tax_amount numeric(20,4) NOT NULL DEFAULT 0,
    insurance_amount numeric(20,4) NOT NULL DEFAULT 0,
    handling_amount numeric(20,4) NOT NULL DEFAULT 0,
    other_amount numeric(20,4) NOT NULL DEFAULT 0,
    total_amount numeric(20,4) NOT NULL,
    allocation_method varchar(20) NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, landed_cost_no),
    CONSTRAINT ck_deims_landed_cost_source CHECK (num_nonnulls(receipt_id,trade_shipment_id,customs_declaration_id) >= 1),
    CONSTRAINT ck_deims_landed_cost_amount CHECK (
        freight_amount >= 0 AND duty_amount >= 0 AND tax_amount >= 0 AND insurance_amount >= 0 AND
        handling_amount >= 0 AND other_amount >= 0 AND
        total_amount = freight_amount + duty_amount + tax_amount + insurance_amount + handling_amount + other_amount
    ),
    CONSTRAINT ck_deims_landed_cost_method CHECK (allocation_method IN ('QUANTITY','WEIGHT','VOLUME','VALUE','MANUAL'))
);

CREATE TABLE IF NOT EXISTS deims.landed_cost_allocations (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    landed_cost_id uuid NOT NULL REFERENCES deims.landed_costs(id) ON DELETE CASCADE,
    receipt_line_id uuid REFERENCES deims.receipt_lines(id),
    inventory_lot_id uuid REFERENCES deims.inventory_lots(id),
    item_id uuid NOT NULL REFERENCES deims.items(id),
    allocation_basis numeric(24,8),
    allocation_percent numeric(9,6),
    allocated_amount numeric(20,4) NOT NULL,
    UNIQUE (landed_cost_id, receipt_line_id, inventory_lot_id, item_id),
    CONSTRAINT ck_deims_landed_alloc_target CHECK (receipt_line_id IS NOT NULL OR inventory_lot_id IS NOT NULL),
    CONSTRAINT ck_deims_landed_alloc_values CHECK (
        (allocation_basis IS NULL OR allocation_basis >= 0) AND
        (allocation_percent IS NULL OR allocation_percent BETWEEN 0 AND 100) AND allocated_amount >= 0
    )
);

CREATE TABLE IF NOT EXISTS deims.invoices (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    invoice_type varchar(20) NOT NULL,
    invoice_no varchar(150) NOT NULL,
    external_invoice_no varchar(150),
    organization_id uuid NOT NULL REFERENCES deims.organizations(id),
    issuer_partner_id uuid NOT NULL REFERENCES deims.business_partners(id),
    recipient_partner_id uuid NOT NULL REFERENCES deims.business_partners(id),
    owner_partner_id uuid REFERENCES deims.business_partners(id),
    invoice_date date NOT NULL,
    service_period_from date,
    service_period_to date,
    posting_date date,
    due_date date,
    payment_term_id uuid REFERENCES deims.payment_terms(id),
    currency_code char(3) NOT NULL REFERENCES deims.currencies(currency_code),
    exchange_rate numeric(24,12),
    exchange_rate_date date,
    base_currency_code char(3) REFERENCES deims.currencies(currency_code),
    net_amount numeric(20,4) NOT NULL DEFAULT 0,
    tax_amount numeric(20,4) NOT NULL DEFAULT 0,
    gross_amount numeric(20,4) NOT NULL DEFAULT 0,
    paid_amount numeric(20,4) NOT NULL DEFAULT 0,
    outstanding_amount numeric(20,4) NOT NULL DEFAULT 0,
    status varchar(30) NOT NULL DEFAULT 'DRAFT',
    match_status varchar(20) NOT NULL DEFAULT 'NOT_MATCHED',
    approval_status varchar(20) NOT NULL DEFAULT 'NOT_REQUIRED',
    tax_invoice_required boolean NOT NULL DEFAULT false,
    source_system_id uuid REFERENCES deims.external_systems(id),
    source_document_id varchar(200),
    original_invoice_id uuid REFERENCES deims.invoices(id),
    correction_reason text,
    posted_at timestamptz,
    cancelled_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_by uuid REFERENCES deims.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, invoice_type, invoice_no),
    UNIQUE (tenant_id, source_system_id, source_document_id),
    CONSTRAINT ck_deims_invoice_type CHECK (invoice_type IN ('RECEIVABLE','PAYABLE','CREDIT_NOTE','DEBIT_NOTE')),
    CONSTRAINT ck_deims_invoice_parties CHECK (issuer_partner_id <> recipient_partner_id),
    CONSTRAINT ck_deims_invoice_period CHECK (service_period_to IS NULL OR service_period_from IS NULL OR service_period_to >= service_period_from),
    CONSTRAINT ck_deims_invoice_due CHECK (due_date IS NULL OR due_date >= invoice_date),
    CONSTRAINT ck_deims_invoice_amounts CHECK (
        net_amount >= 0 AND tax_amount >= 0 AND gross_amount = net_amount + tax_amount AND
        paid_amount >= 0 AND paid_amount <= gross_amount AND outstanding_amount = gross_amount - paid_amount
    ),
    CONSTRAINT ck_deims_invoice_original CHECK (original_invoice_id IS NULL OR original_invoice_id <> id),
    CONSTRAINT ck_deims_invoice_status CHECK (status IN (
        'DRAFT','RECEIVED','VALIDATING','REJECTED','APPROVAL_PENDING','APPROVED','POSTED',
        'PARTIALLY_PAID','PAID','CANCELLED','REVERSED'
    )),
    CONSTRAINT ck_deims_invoice_approval_status CHECK (
        approval_status IN ('NOT_REQUIRED','PENDING','APPROVED','REJECTED','CANCELLED')
    ),
    CONSTRAINT ck_deims_invoice_match_status CHECK (match_status IN ('NOT_MATCHED','MATCHING','PARTIAL','MATCHED','EXCEPTION'))
);

CREATE TABLE IF NOT EXISTS deims.invoice_lines (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    invoice_id uuid NOT NULL REFERENCES deims.invoices(id) ON DELETE CASCADE,
    line_no integer NOT NULL,
    charge_code_id uuid REFERENCES deims.charge_codes(id),
    description text NOT NULL,
    service_date date,
    quantity numeric(24,8) NOT NULL DEFAULT 1,
    uom_code varchar(20) REFERENCES deims.units_of_measure(uom_code),
    unit_price numeric(24,8),
    net_amount numeric(20,4) NOT NULL,
    discount_amount numeric(20,4) NOT NULL DEFAULT 0,
    tax_code_id uuid REFERENCES deims.tax_codes(id),
    tax_rate_percent numeric(9,6),
    tax_amount numeric(20,4) NOT NULL DEFAULT 0,
    gross_amount numeric(20,4) NOT NULL,
    gl_account_code varchar(50),
    match_status varchar(20) NOT NULL DEFAULT 'NOT_MATCHED',
    status varchar(20) NOT NULL DEFAULT 'OPEN',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (invoice_id, line_no),
    UNIQUE (invoice_id, id),
    CONSTRAINT ck_deims_invoice_line_no CHECK (line_no > 0),
    CONSTRAINT ck_deims_invoice_line_qty CHECK (quantity >= 0),
    CONSTRAINT ck_deims_invoice_line_amounts CHECK (
        net_amount >= 0 AND discount_amount >= 0 AND discount_amount <= net_amount AND tax_amount >= 0 AND
        gross_amount = net_amount - discount_amount + tax_amount
    )
);

ALTER TABLE deims.accruals
    DROP CONSTRAINT IF EXISTS fk_deims_accrual_invoice_line;
ALTER TABLE deims.accruals
    ADD CONSTRAINT fk_deims_accrual_invoice_line
    FOREIGN KEY (invoice_line_id) REFERENCES deims.invoice_lines(id) ON DELETE SET NULL;

CREATE TABLE IF NOT EXISTS deims.invoice_line_charges (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    invoice_id uuid NOT NULL REFERENCES deims.invoices(id) ON DELETE RESTRICT,
    invoice_line_id uuid NOT NULL,
    charge_id uuid NOT NULL REFERENCES deims.charges(id),
    allocated_net_amount numeric(20,4) NOT NULL,
    allocated_tax_amount numeric(20,4) NOT NULL DEFAULT 0,
    allocated_gross_amount numeric(20,4) NOT NULL,
    reversed_by uuid REFERENCES deims.users(id),
    reversed_at timestamptz,
    reversal_reason text,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (invoice_id, invoice_line_id)
        REFERENCES deims.invoice_lines(invoice_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_deims_invoice_line_charge_amount CHECK (
        allocated_net_amount >= 0 AND allocated_tax_amount >= 0 AND
        allocated_gross_amount > 0 AND
        allocated_gross_amount = allocated_net_amount + allocated_tax_amount
    ),
    CONSTRAINT ck_deims_invoice_line_charge_reversal CHECK (
        (reversed_at IS NULL AND reversed_by IS NULL AND reversal_reason IS NULL) OR
        (reversed_at IS NOT NULL AND reversed_by IS NOT NULL AND
         reversal_reason IS NOT NULL AND btrim(reversal_reason) <> '' AND
         reversed_at >= created_at)
    )
);

CREATE TABLE IF NOT EXISTS deims.invoice_taxes (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    invoice_id uuid NOT NULL REFERENCES deims.invoices(id) ON DELETE CASCADE,
    tax_code_id uuid NOT NULL REFERENCES deims.tax_codes(id),
    taxable_amount numeric(20,4) NOT NULL,
    tax_rate_percent numeric(9,6) NOT NULL,
    tax_amount numeric(20,4) NOT NULL,
    exemption_amount numeric(20,4) NOT NULL DEFAULT 0,
    UNIQUE (invoice_id, tax_code_id, tax_rate_percent),
    CONSTRAINT ck_deims_invoice_tax_values CHECK (
        taxable_amount >= 0 AND tax_rate_percent BETWEEN 0 AND 100 AND tax_amount >= 0 AND exemption_amount >= 0
    )
);

CREATE TABLE IF NOT EXISTS deims.invoice_match_results (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    invoice_line_id uuid NOT NULL REFERENCES deims.invoice_lines(id) ON DELETE CASCADE,
    match_type varchar(30) NOT NULL,
    matched_entity_type varchar(80) NOT NULL,
    matched_entity_id uuid NOT NULL,
    expected_amount numeric(20,4),
    invoiced_amount numeric(20,4) NOT NULL,
    variance_amount numeric(20,4),
    tolerance_amount numeric(20,4),
    result varchar(20) NOT NULL,
    matched_at timestamptz NOT NULL DEFAULT now(),
    matched_by uuid REFERENCES deims.users(id),
    CONSTRAINT ck_deims_invoice_match_result CHECK (result IN ('MATCHED','WITHIN_TOLERANCE','VARIANCE','MISSING_REFERENCE','DUPLICATE'))
);

CREATE TABLE IF NOT EXISTS deims.invoice_disputes (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    dispute_no varchar(120) NOT NULL,
    invoice_id uuid NOT NULL REFERENCES deims.invoices(id),
    invoice_line_id uuid REFERENCES deims.invoice_lines(id),
    disputed_amount numeric(20,4) NOT NULL,
    currency_code char(3) NOT NULL REFERENCES deims.currencies(currency_code),
    reason_code_id uuid REFERENCES deims.reason_codes(id),
    reason_text text NOT NULL,
    opened_by uuid REFERENCES deims.users(id),
    opened_at timestamptz NOT NULL DEFAULT now(),
    status varchar(20) NOT NULL DEFAULT 'OPEN',
    resolved_amount numeric(20,4),
    resolution text,
    resolved_by uuid REFERENCES deims.users(id),
    resolved_at timestamptz,
    UNIQUE (tenant_id, dispute_no),
    CONSTRAINT ck_deims_invoice_dispute_amount CHECK (
        disputed_amount > 0 AND (resolved_amount IS NULL OR resolved_amount BETWEEN 0 AND disputed_amount)
    ),
    CONSTRAINT ck_deims_invoice_dispute_dates CHECK (resolved_at IS NULL OR resolved_at >= opened_at),
    CONSTRAINT ck_deims_invoice_dispute_status CHECK (status IN ('OPEN','INVESTIGATING','ACCEPTED','PARTIALLY_ACCEPTED','REJECTED','CLOSED'))
);

CREATE TABLE IF NOT EXISTS deims.invoice_dispute_events (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    dispute_id uuid NOT NULL REFERENCES deims.invoice_disputes(id) ON DELETE CASCADE,
    sequence_no integer NOT NULL,
    event_type varchar(40) NOT NULL,
    event_text text,
    actor_user_id uuid REFERENCES deims.users(id),
    occurred_at timestamptz NOT NULL DEFAULT now(),
    file_id uuid REFERENCES deims.files(id),
    UNIQUE (dispute_id, sequence_no)
);

CREATE TABLE IF NOT EXISTS deims.invoice_status_history (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    invoice_id uuid NOT NULL REFERENCES deims.invoices(id) ON DELETE CASCADE,
    sequence_no integer NOT NULL,
    from_status varchar(30),
    to_status varchar(30) NOT NULL,
    reason text,
    actor_user_id uuid REFERENCES deims.users(id),
    occurred_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (invoice_id, sequence_no),
    CONSTRAINT ck_deims_invoice_status_seq CHECK (sequence_no > 0)
);

CREATE TABLE IF NOT EXISTS deims.tax_invoices (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    tax_invoice_no varchar(150) NOT NULL,
    invoice_id uuid REFERENCES deims.invoices(id),
    issue_type varchar(20) NOT NULL DEFAULT 'NORMAL',
    issue_date date NOT NULL,
    supplier_partner_id uuid NOT NULL REFERENCES deims.business_partners(id),
    buyer_partner_id uuid NOT NULL REFERENCES deims.business_partners(id),
    supply_amount numeric(20,4) NOT NULL,
    tax_amount numeric(20,4) NOT NULL,
    total_amount numeric(20,4) NOT NULL,
    nts_approval_no varchar(100),
    nts_status varchar(20) NOT NULL DEFAULT 'DRAFT',
    transmitted_at timestamptz,
    accepted_at timestamptz,
    rejected_at timestamptz,
    error_detail_masked text,
    original_tax_invoice_id uuid REFERENCES deims.tax_invoices(id),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, tax_invoice_no),
    CONSTRAINT ck_deims_tax_invoice_parties CHECK (supplier_partner_id <> buyer_partner_id),
    CONSTRAINT ck_deims_tax_invoice_amount CHECK (supply_amount >= 0 AND tax_amount >= 0 AND total_amount = supply_amount + tax_amount),
    CONSTRAINT ck_deims_tax_invoice_original CHECK (original_tax_invoice_id IS NULL OR original_tax_invoice_id <> id),
    CONSTRAINT ck_deims_tax_invoice_status CHECK (nts_status IN ('DRAFT','QUEUED','TRANSMITTED','ACCEPTED','REJECTED','CANCELLED','CORRECTED'))
);

CREATE TABLE IF NOT EXISTS deims.tax_invoice_lines (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    tax_invoice_id uuid NOT NULL REFERENCES deims.tax_invoices(id) ON DELETE CASCADE,
    line_no integer NOT NULL,
    supply_date date NOT NULL,
    item_name varchar(300) NOT NULL,
    specification varchar(300),
    quantity numeric(24,8),
    unit_price numeric(24,8),
    supply_amount numeric(20,4) NOT NULL,
    tax_amount numeric(20,4) NOT NULL,
    remark text,
    UNIQUE (tax_invoice_id, line_no),
    CONSTRAINT ck_deims_tax_invoice_line_no CHECK (line_no > 0),
    CONSTRAINT ck_deims_tax_invoice_line_values CHECK (
        (quantity IS NULL OR quantity >= 0) AND (unit_price IS NULL OR unit_price >= 0) AND supply_amount >= 0 AND tax_amount >= 0
    )
);

CREATE TABLE IF NOT EXISTS deims.tax_invoice_events (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    tax_invoice_id uuid NOT NULL REFERENCES deims.tax_invoices(id) ON DELETE CASCADE,
    sequence_no integer NOT NULL,
    event_type varchar(40) NOT NULL,
    external_status_code varchar(80),
    occurred_at timestamptz NOT NULL,
    received_at timestamptz NOT NULL DEFAULT now(),
    details_masked jsonb NOT NULL DEFAULT '{}'::jsonb,
    UNIQUE (tax_invoice_id, sequence_no)
);

CREATE TABLE IF NOT EXISTS deims.settlement_batches (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    batch_no varchar(120) NOT NULL,
    settlement_type varchar(20) NOT NULL,
    period_from date NOT NULL,
    period_to date NOT NULL,
    currency_code char(3) NOT NULL REFERENCES deims.currencies(currency_code),
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    requested_by uuid REFERENCES deims.users(id),
    requested_at timestamptz NOT NULL DEFAULT now(),
    approved_by uuid REFERENCES deims.users(id),
    approved_at timestamptz,
    closed_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, batch_no),
    CONSTRAINT ck_deims_settlement_batch_type CHECK (settlement_type IN ('RECEIVABLE','PAYABLE','NETTING')),
    CONSTRAINT ck_deims_settlement_batch_period CHECK (period_to >= period_from),
    CONSTRAINT ck_deims_settlement_batch_status CHECK (status IN ('DRAFT','CALCULATING','REVIEW','APPROVAL_PENDING','APPROVED','POSTED','CLOSED','CANCELLED'))
);

CREATE TABLE IF NOT EXISTS deims.settlements (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    settlement_batch_id uuid REFERENCES deims.settlement_batches(id),
    settlement_no varchar(120) NOT NULL,
    payer_partner_id uuid NOT NULL REFERENCES deims.business_partners(id),
    payee_partner_id uuid NOT NULL REFERENCES deims.business_partners(id),
    owner_partner_id uuid REFERENCES deims.business_partners(id),
    currency_code char(3) NOT NULL REFERENCES deims.currencies(currency_code),
    gross_charge_amount numeric(20,4) NOT NULL,
    adjustment_amount numeric(20,4) NOT NULL DEFAULT 0,
    tax_amount numeric(20,4) NOT NULL DEFAULT 0,
    withholding_amount numeric(20,4) NOT NULL DEFAULT 0,
    net_settlement_amount numeric(20,4) NOT NULL,
    due_date date,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    invoice_id uuid REFERENCES deims.invoices(id),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, settlement_no),
    CONSTRAINT ck_deims_settlement_parties CHECK (payer_partner_id <> payee_partner_id),
    CONSTRAINT ck_deims_settlement_amounts CHECK (
        gross_charge_amount >= 0 AND tax_amount >= 0 AND withholding_amount >= 0 AND
        net_settlement_amount >= 0 AND
        net_settlement_amount = gross_charge_amount + adjustment_amount + tax_amount - withholding_amount
    ),
    CONSTRAINT ck_deims_settlement_status CHECK (status IN (
        'DRAFT','REVIEW','APPROVAL_PENDING','APPROVED','INVOICED',
        'PARTIALLY_PAID','PAID','CLOSED','CANCELLED','REVERSED'
    ))
);

CREATE TABLE IF NOT EXISTS deims.settlement_lines (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    settlement_id uuid NOT NULL REFERENCES deims.settlements(id) ON DELETE CASCADE,
    line_no integer NOT NULL,
    charge_id uuid NOT NULL REFERENCES deims.charges(id),
    charge_amount numeric(20,4) NOT NULL,
    adjustment_amount numeric(20,4) NOT NULL DEFAULT 0,
    tax_amount numeric(20,4) NOT NULL DEFAULT 0,
    settled_amount numeric(20,4) NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'INCLUDED',
    UNIQUE (settlement_id, line_no),
    UNIQUE (settlement_id, charge_id),
    CONSTRAINT ck_deims_settlement_line_no CHECK (line_no > 0),
    CONSTRAINT ck_deims_settlement_line_amount CHECK (
        charge_amount >= 0 AND tax_amount >= 0 AND settled_amount >= 0 AND
        settled_amount = charge_amount + adjustment_amount + tax_amount
    )
);

CREATE TABLE IF NOT EXISTS deims.payments (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    payment_no varchar(120) NOT NULL,
    payment_direction varchar(10) NOT NULL,
    payer_partner_id uuid NOT NULL REFERENCES deims.business_partners(id),
    payee_partner_id uuid NOT NULL REFERENCES deims.business_partners(id),
    payment_method varchar(30) NOT NULL,
    currency_code char(3) NOT NULL REFERENCES deims.currencies(currency_code),
    payment_amount numeric(20,4) NOT NULL,
    unapplied_amount numeric(20,4) NOT NULL,
    payment_date date NOT NULL,
    value_date date,
    bank_reference varchar(200),
    bank_account_id uuid REFERENCES deims.partner_bank_accounts(id),
    status varchar(20) NOT NULL DEFAULT 'RECEIVED',
    reversed_payment_id uuid REFERENCES deims.payments(id),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, payment_no),
    CONSTRAINT ck_deims_payment_direction CHECK (payment_direction IN ('IN','OUT')),
    CONSTRAINT ck_deims_payment_parties CHECK (payer_partner_id <> payee_partner_id),
    CONSTRAINT ck_deims_payment_amount CHECK (payment_amount > 0 AND unapplied_amount BETWEEN 0 AND payment_amount),
    CONSTRAINT ck_deims_payment_reversal CHECK (reversed_payment_id IS NULL OR reversed_payment_id <> id),
    CONSTRAINT ck_deims_payment_status CHECK (status IN ('PENDING','RECEIVED','CLEARED','PARTIALLY_APPLIED','APPLIED','FAILED','REVERSED','CANCELLED'))
);

CREATE TABLE IF NOT EXISTS deims.payment_applications (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    payment_id uuid NOT NULL REFERENCES deims.payments(id) ON DELETE CASCADE,
    invoice_id uuid REFERENCES deims.invoices(id),
    settlement_id uuid REFERENCES deims.settlements(id),
    applied_amount numeric(20,4) NOT NULL,
    applied_at timestamptz NOT NULL DEFAULT now(),
    applied_by uuid NOT NULL REFERENCES deims.users(id),
    reversed_at timestamptz,
    reversed_by uuid REFERENCES deims.users(id),
    reversal_reason text,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_deims_payment_application_target CHECK (num_nonnulls(invoice_id, settlement_id) = 1),
    CONSTRAINT ck_deims_payment_application_amount CHECK (applied_amount > 0),
    CONSTRAINT ck_deims_payment_application_dates CHECK (reversed_at IS NULL OR reversed_at >= applied_at),
    CONSTRAINT ck_deims_payment_application_reversal CHECK (
        (reversed_at IS NULL AND reversed_by IS NULL AND reversal_reason IS NULL) OR
        (reversed_at IS NOT NULL AND reversed_by IS NOT NULL AND
         reversal_reason IS NOT NULL AND btrim(reversal_reason) <> '' AND
         reversed_at >= created_at)
    )
);

CREATE TABLE IF NOT EXISTS deims.finance_projection_authorizations (
    authorization_token uuid PRIMARY KEY,
    backend_pid integer NOT NULL,
    transaction_id bigint NOT NULL,
    authorization_scope varchar(40) NOT NULL,
    authorized_role name NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL,
    CONSTRAINT ck_deims_finance_auth_scope CHECK (
        authorization_scope IN ('PAYMENT_APPLICATION')
    ),
    CONSTRAINT ck_deims_finance_auth_expiry CHECK (expires_at > created_at)
);

REVOKE ALL ON TABLE deims.finance_projection_authorizations FROM PUBLIC;

CREATE UNIQUE INDEX IF NOT EXISTS ux_deims_charge_alloc_outbound_active
    ON deims.charge_allocations (charge_id, outbound_order_id)
    WHERE reversed_at IS NULL AND outbound_order_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_deims_charge_alloc_inbound_active
    ON deims.charge_allocations (charge_id, inbound_order_id)
    WHERE reversed_at IS NULL AND inbound_order_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_deims_charge_alloc_shipment_active
    ON deims.charge_allocations (charge_id, shipment_id)
    WHERE reversed_at IS NULL AND shipment_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_deims_charge_alloc_receipt_active
    ON deims.charge_allocations (charge_id, receipt_id)
    WHERE reversed_at IS NULL AND receipt_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_deims_invoice_line_charge_active
    ON deims.invoice_line_charges (invoice_line_id, charge_id)
    WHERE reversed_at IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_deims_invoice_charge_per_invoice_active
    ON deims.invoice_line_charges (invoice_id, charge_id)
    WHERE reversed_at IS NULL;
CREATE INDEX IF NOT EXISTS ix_deims_invoice_charge_active_sum
    ON deims.invoice_line_charges (charge_id, invoice_id, invoice_line_id)
    WHERE reversed_at IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS ux_deims_payment_invoice_application_active
    ON deims.payment_applications (payment_id, invoice_id)
    WHERE reversed_at IS NULL AND invoice_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_deims_payment_settlement_application_active
    ON deims.payment_applications (payment_id, settlement_id)
    WHERE reversed_at IS NULL AND settlement_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_deims_payment_application_invoice_active
    ON deims.payment_applications (invoice_id, payment_id)
    WHERE reversed_at IS NULL AND invoice_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_deims_payment_application_settlement_active
    ON deims.payment_applications (settlement_id, payment_id)
    WHERE reversed_at IS NULL AND settlement_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_deims_settlement_canonical_invoice
    ON deims.settlements (invoice_id)
    WHERE invoice_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_deims_settlement_line_charge
    ON deims.settlement_lines (charge_id, settlement_id);

CREATE TABLE IF NOT EXISTS deims.accounting_periods (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    organization_id uuid NOT NULL REFERENCES deims.organizations(id),
    fiscal_year integer NOT NULL,
    period_no smallint NOT NULL,
    period_name varchar(100),
    start_date date NOT NULL,
    end_date date NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'OPEN',
    closed_by uuid REFERENCES deims.users(id),
    closed_at timestamptz,
    UNIQUE (tenant_id, organization_id, fiscal_year, period_no),
    CONSTRAINT ck_deims_accounting_year CHECK (fiscal_year BETWEEN 1900 AND 9999),
    CONSTRAINT ck_deims_accounting_period_no CHECK (period_no BETWEEN 1 AND 53),
    CONSTRAINT ck_deims_accounting_period_dates CHECK (end_date >= start_date),
    CONSTRAINT ck_deims_accounting_period_status CHECK (status IN ('FUTURE','OPEN','SOFT_CLOSED','CLOSED','REOPENED'))
);

CREATE TABLE IF NOT EXISTS deims.gl_accounts (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    organization_id uuid NOT NULL REFERENCES deims.organizations(id),
    account_code varchar(50) NOT NULL,
    account_name varchar(200) NOT NULL,
    account_type varchar(20) NOT NULL,
    parent_account_id uuid REFERENCES deims.gl_accounts(id),
    normal_balance varchar(10) NOT NULL,
    currency_code char(3) REFERENCES deims.currencies(currency_code),
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, organization_id, account_code),
    CONSTRAINT ck_deims_gl_account_type CHECK (account_type IN ('ASSET','LIABILITY','EQUITY','REVENUE','EXPENSE','CONTRA')),
    CONSTRAINT ck_deims_gl_normal_balance CHECK (normal_balance IN ('DEBIT','CREDIT')),
    CONSTRAINT ck_deims_gl_parent CHECK (parent_account_id IS NULL OR parent_account_id <> id)
);

CREATE TABLE IF NOT EXISTS deims.journal_batches (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    organization_id uuid NOT NULL REFERENCES deims.organizations(id),
    batch_no varchar(120) NOT NULL,
    batch_type varchar(30) NOT NULL,
    accounting_date date NOT NULL,
    accounting_period_id uuid NOT NULL REFERENCES deims.accounting_periods(id),
    currency_code char(3) NOT NULL REFERENCES deims.currencies(currency_code),
    total_debit numeric(20,4) NOT NULL DEFAULT 0,
    total_credit numeric(20,4) NOT NULL DEFAULT 0,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    posted_by uuid REFERENCES deims.users(id),
    posted_at timestamptz,
    reversal_batch_id uuid REFERENCES deims.journal_batches(id),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, batch_no),
    CONSTRAINT ck_deims_journal_batch_balance CHECK (total_debit >= 0 AND total_credit >= 0 AND total_debit = total_credit),
    CONSTRAINT ck_deims_journal_batch_reversal CHECK (reversal_batch_id IS NULL OR reversal_batch_id <> id),
    CONSTRAINT ck_deims_journal_batch_status CHECK (status IN ('DRAFT','VALIDATING','APPROVAL_PENDING','APPROVED','POSTED','REVERSED','CANCELLED'))
);

CREATE TABLE IF NOT EXISTS deims.journal_entries (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    journal_batch_id uuid NOT NULL REFERENCES deims.journal_batches(id) ON DELETE CASCADE,
    entry_no integer NOT NULL,
    source_type varchar(50),
    source_id uuid,
    description text NOT NULL,
    reference_no varchar(200),
    UNIQUE (journal_batch_id, entry_no),
    CONSTRAINT ck_deims_journal_entry_no CHECK (entry_no > 0)
);

CREATE TABLE IF NOT EXISTS deims.journal_lines (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    journal_entry_id uuid NOT NULL REFERENCES deims.journal_entries(id) ON DELETE CASCADE,
    line_no integer NOT NULL,
    gl_account_id uuid NOT NULL REFERENCES deims.gl_accounts(id),
    owner_partner_id uuid REFERENCES deims.business_partners(id),
    warehouse_id uuid REFERENCES deims.warehouses(id),
    partner_id uuid REFERENCES deims.business_partners(id),
    debit_amount numeric(20,4) NOT NULL DEFAULT 0,
    credit_amount numeric(20,4) NOT NULL DEFAULT 0,
    currency_code char(3) NOT NULL REFERENCES deims.currencies(currency_code),
    exchange_rate numeric(24,12),
    base_debit_amount numeric(20,4),
    base_credit_amount numeric(20,4),
    description text,
    UNIQUE (journal_entry_id, line_no),
    CONSTRAINT ck_deims_journal_line_no CHECK (line_no > 0),
    CONSTRAINT ck_deims_journal_line_side CHECK (
        debit_amount >= 0 AND credit_amount >= 0 AND num_nonnulls(NULLIF(debit_amount,0), NULLIF(credit_amount,0)) = 1
    ),
    CONSTRAINT ck_deims_journal_line_rate CHECK (exchange_rate IS NULL OR exchange_rate > 0)
);

CREATE TABLE IF NOT EXISTS deims.accounting_exports (
    id uuid PRIMARY KEY DEFAULT deims.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES deims.tenants(id),
    export_no varchar(120) NOT NULL,
    external_system_id uuid NOT NULL REFERENCES deims.external_systems(id),
    accounting_period_id uuid REFERENCES deims.accounting_periods(id),
    export_type varchar(30) NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'QUEUED',
    requested_by uuid REFERENCES deims.users(id),
    requested_at timestamptz NOT NULL DEFAULT now(),
    started_at timestamptz,
    completed_at timestamptz,
    record_count integer NOT NULL DEFAULT 0,
    payload_uri text,
    payload_sha256 char(64),
    acknowledgement_uri text,
    error_detail_masked text,
    UNIQUE (tenant_id, export_no),
    CONSTRAINT ck_deims_accounting_export_count CHECK (record_count >= 0),
    CONSTRAINT ck_deims_accounting_export_dates CHECK (completed_at IS NULL OR started_at IS NULL OR completed_at >= started_at)
);

COMMENT ON TABLE deims.rating_run_details IS
    'Immutable explanation of the contract version, rule, input basis and calculation trace used for each charge event.';
COMMENT ON TABLE deims.charges IS
    'Canonical receivable/payable charge record. Corrections are adjustments or reversal charges; posted history is not overwritten.';
COMMENT ON TABLE deims.partner_bank_accounts IS
    'Bank account numbers are encrypted, hashed for equality lookup, and masked for display.';

-- Projection authorizations are transaction-local capabilities created only by the
-- payment-application trigger. A client-set custom GUC is insufficient because the
-- token must also exist for the same backend, transaction and session role.
CREATE OR REPLACE FUNCTION deims.open_finance_projection_authorization(p_scope text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, deims
AS $function$
DECLARE
    authorization_token uuid;
BEGIN
    IF p_scope <> 'PAYMENT_APPLICATION' THEN
        RAISE EXCEPTION 'Unsupported finance projection scope %', p_scope
            USING ERRCODE = '22023';
    END IF;

    DELETE FROM deims.finance_projection_authorizations
     WHERE expires_at <= clock_timestamp();

    authorization_token := deims.generate_uuid();
    INSERT INTO deims.finance_projection_authorizations (
        authorization_token, backend_pid, transaction_id,
        authorization_scope, authorized_role, expires_at
    ) VALUES (
        authorization_token, pg_backend_pid(), txid_current(),
        p_scope, session_user, clock_timestamp() + interval '5 minutes'
    );
    PERFORM set_config('deims.finance_projection_token', authorization_token::text, true);
    RETURN authorization_token;
END;
$function$;

CREATE OR REPLACE FUNCTION deims.close_finance_projection_authorization(p_token uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, deims
AS $function$
BEGIN
    DELETE FROM deims.finance_projection_authorizations
     WHERE authorization_token = p_token
       AND backend_pid = pg_backend_pid()
       AND transaction_id = txid_current()
       AND authorized_role = session_user;
    PERFORM set_config('deims.finance_projection_token', '', true);
END;
$function$;

CREATE OR REPLACE FUNCTION deims.finance_projection_authorized(p_scope text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, deims
AS $function$
DECLARE
    token_text text;
    token_value uuid;
BEGIN
    token_text := current_setting('deims.finance_projection_token', true);
    IF token_text IS NULL OR token_text = '' THEN
        RETURN false;
    END IF;
    BEGIN
        token_value := token_text::uuid;
    EXCEPTION WHEN invalid_text_representation THEN
        RETURN false;
    END;

    RETURN EXISTS (
        SELECT 1
          FROM deims.finance_projection_authorizations finance_auth
         WHERE finance_auth.authorization_token = token_value
           AND finance_auth.backend_pid = pg_backend_pid()
           AND finance_auth.transaction_id = txid_current()
           AND finance_auth.authorization_scope = p_scope
           AND finance_auth.authorized_role = session_user
           AND finance_auth.expires_at > clock_timestamp()
    );
END;
$function$;

REVOKE ALL ON FUNCTION deims.open_finance_projection_authorization(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION deims.close_finance_projection_authorization(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION deims.finance_projection_authorized(text) FROM PUBLIC;

CREATE OR REPLACE FUNCTION deims.validate_charge_allocation_mutation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, deims
AS $function$
DECLARE
    charge_row record;
    target_row record;
    old_core jsonb;
    new_core jsonb;
    active_net numeric(20,4);
    active_tax numeric(20,4);
    active_gross numeric(20,4);
    active_percent numeric(20,6);
    actor_id uuid;
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'Charge allocation % cannot be deleted; record an explicit reversal', OLD.id
            USING ERRCODE = '55000';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtext('deims.finance'), hashtext(NEW.tenant_id::text));

    IF TG_OP = 'INSERT' THEN
        IF NEW.reversed_at IS NOT NULL OR NEW.reversed_by IS NOT NULL OR NEW.reversal_reason IS NOT NULL THEN
            RAISE EXCEPTION 'A charge allocation must be created active'
                USING ERRCODE = '23514';
        END IF;
    ELSE
        IF OLD.reversed_at IS NOT NULL THEN
            RAISE EXCEPTION 'Reversed charge allocation % is immutable', OLD.id
                USING ERRCODE = '55000';
        END IF;
        old_core := to_jsonb(OLD)
            - 'reversed_at' - 'reversed_by' - 'reversal_reason' - 'row_version' - 'updated_at';
        new_core := to_jsonb(NEW)
            - 'reversed_at' - 'reversed_by' - 'reversal_reason' - 'row_version' - 'updated_at';
        IF old_core IS DISTINCT FROM new_core OR NEW.reversed_at IS NULL THEN
            RAISE EXCEPTION 'Charge allocation corrections require a one-way reversal and a new allocation'
                USING ERRCODE = '55000';
        END IF;
    END IF;

    actor_id := CASE WHEN NEW.reversed_at IS NULL THEN NULL ELSE NEW.reversed_by END;
    IF actor_id IS NOT NULL AND NOT EXISTS (
        SELECT 1
          FROM deims.tenant_memberships membership
         WHERE membership.tenant_id = NEW.tenant_id
           AND membership.user_id = actor_id
           AND membership.status = 'ACTIVE'
           AND membership.valid_from <= clock_timestamp()
           AND (membership.valid_to IS NULL OR membership.valid_to > clock_timestamp())
    ) THEN
        RAISE EXCEPTION 'Charge allocation reversal actor is not an active tenant member'
            USING ERRCODE = '23514';
    END IF;

    SELECT charge.* INTO charge_row
      FROM deims.charges charge
     WHERE charge.id = NEW.charge_id
     FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Charge % does not exist', NEW.charge_id USING ERRCODE = '23503';
    END IF;
    IF charge_row.tenant_id IS DISTINCT FROM NEW.tenant_id THEN
        RAISE EXCEPTION 'Charge allocation crosses tenant boundary' USING ERRCODE = '23514';
    END IF;
    IF NEW.warehouse_id IS NOT NULL AND NEW.warehouse_id IS DISTINCT FROM charge_row.warehouse_id THEN
        RAISE EXCEPTION 'Charge allocation warehouse differs from its charge' USING ERRCODE = '23514';
    END IF;
    IF NEW.owner_partner_id IS NOT NULL AND NEW.owner_partner_id IS DISTINCT FROM charge_row.owner_partner_id THEN
        RAISE EXCEPTION 'Charge allocation owner differs from its charge' USING ERRCODE = '23514';
    END IF;
    IF NEW.reversed_at IS NULL AND charge_row.status IN ('WAIVED','REVERSED','CANCELLED') THEN
        RAISE EXCEPTION 'Active allocations are not allowed for charge status %', charge_row.status
            USING ERRCODE = '23514';
    END IF;

    IF NEW.source_entity_type IS NOT NULL OR NEW.source_entity_id IS NOT NULL
       OR num_nonnulls(
           NEW.outbound_order_id, NEW.inbound_order_id, NEW.shipment_id, NEW.receipt_id
       ) <> 1 THEN
        RAISE EXCEPTION 'Charge allocations require exactly one typed, tenant-scoped target'
            USING ERRCODE = '23514';
    END IF;

    IF NEW.outbound_order_id IS NOT NULL THEN
        SELECT tenant_id, warehouse_id, owner_partner_id INTO target_row
          FROM deims.outbound_orders WHERE id = NEW.outbound_order_id FOR SHARE;
    ELSIF NEW.inbound_order_id IS NOT NULL THEN
        SELECT tenant_id, warehouse_id, owner_partner_id INTO target_row
          FROM deims.inbound_orders WHERE id = NEW.inbound_order_id FOR SHARE;
    ELSIF NEW.shipment_id IS NOT NULL THEN
        SELECT tenant_id, warehouse_id, owner_partner_id INTO target_row
          FROM deims.shipments WHERE id = NEW.shipment_id FOR SHARE;
    ELSIF NEW.receipt_id IS NOT NULL THEN
        SELECT tenant_id, warehouse_id, owner_partner_id INTO target_row
          FROM deims.receipts WHERE id = NEW.receipt_id FOR SHARE;
    END IF;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Charge allocation target does not exist' USING ERRCODE = '23503';
    END IF;
    IF target_row.tenant_id IS DISTINCT FROM NEW.tenant_id
       OR target_row.warehouse_id IS DISTINCT FROM charge_row.warehouse_id
       OR target_row.owner_partner_id IS DISTINCT FROM charge_row.owner_partner_id THEN
        RAISE EXCEPTION 'Charge allocation target tenant, warehouse or owner differs from its charge'
            USING ERRCODE = '23514';
    END IF;

    SELECT COALESCE(sum(allocated_net_amount), 0),
           COALESCE(sum(allocated_tax_amount), 0),
           COALESCE(sum(allocated_gross_amount), 0),
           COALESCE(sum(allocation_percent), 0)
      INTO active_net, active_tax, active_gross, active_percent
      FROM deims.charge_allocations allocation
     WHERE allocation.charge_id = NEW.charge_id
       AND allocation.reversed_at IS NULL
       AND allocation.id <> NEW.id;
    IF NEW.reversed_at IS NULL THEN
        active_net := active_net + NEW.allocated_net_amount;
        active_tax := active_tax + NEW.allocated_tax_amount;
        active_gross := active_gross + NEW.allocated_gross_amount;
        active_percent := active_percent + COALESCE(NEW.allocation_percent, 0);
    END IF;
    IF active_net > charge_row.net_amount
       OR active_tax > charge_row.tax_amount
       OR active_gross > charge_row.gross_amount
       OR active_percent > 100 THEN
        RAISE EXCEPTION 'Active charge allocations exceed charge amount or 100 percent'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION deims.validate_invoice_line_charge_mutation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, deims
AS $function$
DECLARE
    charge_row record;
    invoice_row record;
    line_row record;
    old_core jsonb;
    new_core jsonb;
    charge_net numeric(20,4);
    charge_tax numeric(20,4);
    charge_gross numeric(20,4);
    line_net numeric(20,4);
    line_tax numeric(20,4);
    line_gross numeric(20,4);
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'Invoice charge allocation % cannot be deleted; record an explicit reversal', OLD.id
            USING ERRCODE = '55000';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtext('deims.finance'), hashtext(NEW.tenant_id::text));

    IF TG_OP = 'INSERT' THEN
        IF NEW.reversed_at IS NOT NULL OR NEW.reversed_by IS NOT NULL OR NEW.reversal_reason IS NOT NULL THEN
            RAISE EXCEPTION 'An invoice charge allocation must be created active'
                USING ERRCODE = '23514';
        END IF;
    ELSE
        IF OLD.reversed_at IS NOT NULL THEN
            RAISE EXCEPTION 'Reversed invoice charge allocation % is immutable', OLD.id
                USING ERRCODE = '55000';
        END IF;
        old_core := to_jsonb(OLD)
            - 'reversed_at' - 'reversed_by' - 'reversal_reason' - 'row_version' - 'updated_at';
        new_core := to_jsonb(NEW)
            - 'reversed_at' - 'reversed_by' - 'reversal_reason' - 'row_version' - 'updated_at';
        IF old_core IS DISTINCT FROM new_core OR NEW.reversed_at IS NULL THEN
            RAISE EXCEPTION 'Invoice charge corrections require a one-way reversal and a new allocation'
                USING ERRCODE = '55000';
        END IF;
        IF NOT EXISTS (
            SELECT 1 FROM deims.tenant_memberships membership
             WHERE membership.tenant_id = NEW.tenant_id
               AND membership.user_id = NEW.reversed_by
               AND membership.status = 'ACTIVE'
               AND membership.valid_from <= clock_timestamp()
               AND (membership.valid_to IS NULL OR membership.valid_to > clock_timestamp())
        ) THEN
            RAISE EXCEPTION 'Invoice charge reversal actor is not an active tenant member'
                USING ERRCODE = '23514';
        END IF;
    END IF;

    -- The lock order is charge, invoice, invoice line for every allocation path.
    SELECT charge.* INTO charge_row
      FROM deims.charges charge
     WHERE charge.id = NEW.charge_id
     FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Charge % does not exist', NEW.charge_id USING ERRCODE = '23503';
    END IF;

    SELECT invoice.* INTO invoice_row
      FROM deims.invoices invoice
     WHERE invoice.id = NEW.invoice_id
     FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Invoice % does not exist', NEW.invoice_id USING ERRCODE = '23503';
    END IF;
    SELECT line.* INTO line_row
      FROM deims.invoice_lines line
     WHERE line.id = NEW.invoice_line_id
       AND line.invoice_id = NEW.invoice_id
     FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Invoice line is not part of invoice %', NEW.invoice_id USING ERRCODE = '23503';
    END IF;

    IF charge_row.tenant_id IS DISTINCT FROM NEW.tenant_id
       OR invoice_row.tenant_id IS DISTINCT FROM NEW.tenant_id
       OR line_row.tenant_id IS DISTINCT FROM NEW.tenant_id THEN
        RAISE EXCEPTION 'Invoice charge allocation crosses tenant boundary' USING ERRCODE = '23514';
    END IF;
    IF charge_row.currency_code IS DISTINCT FROM invoice_row.currency_code THEN
        RAISE EXCEPTION 'Charge and invoice currencies differ' USING ERRCODE = '23514';
    END IF;
    IF charge_row.payee_partner_id IS DISTINCT FROM invoice_row.issuer_partner_id
       OR charge_row.payer_partner_id IS DISTINCT FROM invoice_row.recipient_partner_id THEN
        RAISE EXCEPTION 'Charge payer/payee do not match invoice recipient/issuer'
            USING ERRCODE = '23514';
    END IF;
    IF (invoice_row.invoice_type IN ('RECEIVABLE','DEBIT_NOTE') AND charge_row.direction <> 'RECEIVABLE')
       OR (invoice_row.invoice_type IN ('PAYABLE','CREDIT_NOTE') AND charge_row.direction <> 'PAYABLE') THEN
        RAISE EXCEPTION 'Charge direction is incompatible with invoice type %', invoice_row.invoice_type
            USING ERRCODE = '23514';
    END IF;
    IF line_row.charge_code_id IS DISTINCT FROM charge_row.charge_code_id THEN
        RAISE EXCEPTION 'Invoice line charge code differs from the allocated charge'
            USING ERRCODE = '23514';
    END IF;
    IF NEW.reversed_at IS NULL AND (
        NOT charge_row.billable OR charge_row.status <> 'APPROVED'
        OR invoice_row.status IN ('POSTED','PARTIALLY_PAID','PAID','CANCELLED','REVERSED')
    ) THEN
        RAISE EXCEPTION 'Only an approved billable charge may be allocated to an unposted invoice'
            USING ERRCODE = '23514';
    END IF;

    SELECT COALESCE(sum(allocated_net_amount), 0),
           COALESCE(sum(allocated_tax_amount), 0),
           COALESCE(sum(allocated_gross_amount), 0)
      INTO charge_net, charge_tax, charge_gross
      FROM deims.invoice_line_charges allocation
     WHERE allocation.charge_id = NEW.charge_id
       AND allocation.reversed_at IS NULL
       AND allocation.id <> NEW.id;
    SELECT COALESCE(sum(allocated_net_amount), 0),
           COALESCE(sum(allocated_tax_amount), 0),
           COALESCE(sum(allocated_gross_amount), 0)
      INTO line_net, line_tax, line_gross
      FROM deims.invoice_line_charges allocation
     WHERE allocation.invoice_line_id = NEW.invoice_line_id
       AND allocation.reversed_at IS NULL
       AND allocation.id <> NEW.id;
    IF NEW.reversed_at IS NULL THEN
        charge_net := charge_net + NEW.allocated_net_amount;
        charge_tax := charge_tax + NEW.allocated_tax_amount;
        charge_gross := charge_gross + NEW.allocated_gross_amount;
        line_net := line_net + NEW.allocated_net_amount;
        line_tax := line_tax + NEW.allocated_tax_amount;
        line_gross := line_gross + NEW.allocated_gross_amount;
    END IF;
    IF charge_net > charge_row.net_amount OR charge_tax > charge_row.tax_amount
       OR charge_gross > charge_row.gross_amount THEN
        RAISE EXCEPTION 'Active invoice allocations exceed the charge amount'
            USING ERRCODE = '23514';
    END IF;
    IF line_net > line_row.net_amount - line_row.discount_amount
       OR line_tax > line_row.tax_amount OR line_gross > line_row.gross_amount THEN
        RAISE EXCEPTION 'Active charge allocations exceed the invoice line amount'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION deims.guard_charge_allocation_parent()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, deims
AS $function$
DECLARE
    has_history boolean;
    active_operational boolean;
    active_invoice boolean;
    active_settlement boolean;
    operational_net numeric(20,4);
    operational_tax numeric(20,4);
    operational_gross numeric(20,4);
    operational_percent numeric(20,6);
    invoice_net numeric(20,4);
    invoice_tax numeric(20,4);
    invoice_gross numeric(20,4);
    settlement_net numeric(20,4);
    settlement_tax numeric(20,4);
BEGIN
    SELECT EXISTS (
               SELECT 1 FROM deims.charge_allocations WHERE charge_id = OLD.id
               UNION ALL
               SELECT 1 FROM deims.invoice_line_charges WHERE charge_id = OLD.id
               UNION ALL
               SELECT 1 FROM deims.settlement_lines WHERE charge_id = OLD.id
           ),
           EXISTS (SELECT 1 FROM deims.charge_allocations WHERE charge_id = OLD.id AND reversed_at IS NULL),
           EXISTS (SELECT 1 FROM deims.invoice_line_charges WHERE charge_id = OLD.id AND reversed_at IS NULL),
           EXISTS (
               SELECT 1
                 FROM deims.settlement_lines line
                 JOIN deims.settlements settlement ON settlement.id = line.settlement_id
                WHERE line.charge_id = OLD.id
                  AND settlement.status NOT IN ('CANCELLED','REVERSED')
           )
      INTO has_history, active_operational, active_invoice, active_settlement;

    IF TG_OP = 'DELETE' THEN
        IF has_history THEN
            RAISE EXCEPTION 'Charge % with allocation history cannot be deleted', OLD.id
                USING ERRCODE = '55000';
        END IF;
        RETURN OLD;
    END IF;

    IF has_history AND (
        OLD.tenant_id IS DISTINCT FROM NEW.tenant_id
        OR OLD.warehouse_id IS DISTINCT FROM NEW.warehouse_id
        OR OLD.owner_partner_id IS DISTINCT FROM NEW.owner_partner_id
        OR OLD.payer_partner_id IS DISTINCT FROM NEW.payer_partner_id
        OR OLD.payee_partner_id IS DISTINCT FROM NEW.payee_partner_id
        OR OLD.currency_code IS DISTINCT FROM NEW.currency_code
        OR OLD.direction IS DISTINCT FROM NEW.direction
        OR OLD.charge_code_id IS DISTINCT FROM NEW.charge_code_id
    ) THEN
        RAISE EXCEPTION 'Allocated charge tenant, scope, parties, currency, direction and code are immutable'
            USING ERRCODE = '55000';
    END IF;

    SELECT COALESCE(sum(allocated_net_amount), 0),
           COALESCE(sum(allocated_tax_amount), 0),
           COALESCE(sum(allocated_gross_amount), 0),
           COALESCE(sum(allocation_percent), 0)
      INTO operational_net, operational_tax, operational_gross, operational_percent
      FROM deims.charge_allocations
     WHERE charge_id = OLD.id AND reversed_at IS NULL;
    SELECT COALESCE(sum(allocated_net_amount), 0),
           COALESCE(sum(allocated_tax_amount), 0),
           COALESCE(sum(allocated_gross_amount), 0)
      INTO invoice_net, invoice_tax, invoice_gross
      FROM deims.invoice_line_charges
     WHERE charge_id = OLD.id AND reversed_at IS NULL;
    SELECT COALESCE(sum(line.charge_amount), 0), COALESCE(sum(line.tax_amount), 0)
      INTO settlement_net, settlement_tax
      FROM deims.settlement_lines line
      JOIN deims.settlements settlement ON settlement.id = line.settlement_id
     WHERE line.charge_id = OLD.id
       AND settlement.status NOT IN ('CANCELLED','REVERSED');

    IF operational_net > NEW.net_amount OR operational_tax > NEW.tax_amount
       OR operational_gross > NEW.gross_amount OR operational_percent > 100
       OR invoice_net > NEW.net_amount OR invoice_tax > NEW.tax_amount
       OR invoice_gross > NEW.gross_amount
       OR settlement_net > NEW.net_amount OR settlement_tax > NEW.tax_amount
       OR settlement_net + settlement_tax > NEW.gross_amount THEN
        RAISE EXCEPTION 'Charge amount cannot be reduced below its active allocations'
            USING ERRCODE = '23514';
    END IF;
    IF (active_operational OR active_invoice OR active_settlement)
       AND NEW.status IN ('WAIVED','REVERSED','CANCELLED') THEN
        RAISE EXCEPTION 'Reverse active allocations before setting charge status to %', NEW.status
            USING ERRCODE = '23514';
    END IF;
    IF active_invoice AND NOT NEW.billable THEN
        RAISE EXCEPTION 'A charge with active invoice allocations must remain billable'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION deims.guard_invoice_line_charge_parent()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, deims
AS $function$
DECLARE
    has_history boolean;
    active_net numeric(20,4);
    active_tax numeric(20,4);
    active_gross numeric(20,4);
BEGIN
    SELECT EXISTS (
               SELECT 1 FROM deims.invoice_line_charges WHERE invoice_line_id = OLD.id
           ),
           COALESCE(sum(allocated_net_amount), 0),
           COALESCE(sum(allocated_tax_amount), 0),
           COALESCE(sum(allocated_gross_amount), 0)
      INTO has_history, active_net, active_tax, active_gross
      FROM deims.invoice_line_charges
     WHERE invoice_line_id = OLD.id AND reversed_at IS NULL;

    IF TG_OP = 'DELETE' THEN
        IF has_history THEN
            RAISE EXCEPTION 'Invoice line % with charge-allocation history cannot be deleted', OLD.id
                USING ERRCODE = '55000';
        END IF;
        RETURN OLD;
    END IF;
    IF has_history AND (
        OLD.tenant_id IS DISTINCT FROM NEW.tenant_id
        OR OLD.invoice_id IS DISTINCT FROM NEW.invoice_id
        OR OLD.charge_code_id IS DISTINCT FROM NEW.charge_code_id
    ) THEN
        RAISE EXCEPTION 'Allocated invoice line tenant, invoice and charge code are immutable'
            USING ERRCODE = '55000';
    END IF;
    IF active_net > NEW.net_amount - NEW.discount_amount
       OR active_tax > NEW.tax_amount OR active_gross > NEW.gross_amount THEN
        RAISE EXCEPTION 'Invoice line amount cannot be reduced below active charge allocations'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION deims.assert_charge_allocation_integrity(
    p_charge_id uuid,
    p_invoice_line_id uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, deims
AS $function$
DECLARE
    charge_row record;
    line_row record;
    operational_net numeric(20,4);
    operational_tax numeric(20,4);
    operational_gross numeric(20,4);
    operational_percent numeric(20,6);
    invoice_net numeric(20,4);
    invoice_tax numeric(20,4);
    invoice_gross numeric(20,4);
    line_net numeric(20,4);
    line_tax numeric(20,4);
    line_gross numeric(20,4);
BEGIN
    SELECT charge.* INTO charge_row
      FROM deims.charges charge WHERE charge.id = p_charge_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Allocated charge % no longer exists', p_charge_id USING ERRCODE = '23503';
    END IF;

    SELECT COALESCE(sum(allocated_net_amount), 0),
           COALESCE(sum(allocated_tax_amount), 0),
           COALESCE(sum(allocated_gross_amount), 0),
           COALESCE(sum(allocation_percent), 0)
      INTO operational_net, operational_tax, operational_gross, operational_percent
      FROM deims.charge_allocations
     WHERE charge_id = p_charge_id AND reversed_at IS NULL;
    SELECT COALESCE(sum(allocated_net_amount), 0),
           COALESCE(sum(allocated_tax_amount), 0),
           COALESCE(sum(allocated_gross_amount), 0)
      INTO invoice_net, invoice_tax, invoice_gross
      FROM deims.invoice_line_charges
     WHERE charge_id = p_charge_id AND reversed_at IS NULL;
    IF operational_net > charge_row.net_amount OR operational_tax > charge_row.tax_amount
       OR operational_gross > charge_row.gross_amount OR operational_percent > 100
       OR invoice_net > charge_row.net_amount OR invoice_tax > charge_row.tax_amount
       OR invoice_gross > charge_row.gross_amount THEN
        RAISE EXCEPTION 'Deferred allocation check failed for charge %', p_charge_id
            USING ERRCODE = '23514';
    END IF;

    IF p_invoice_line_id IS NOT NULL THEN
        SELECT line.* INTO line_row
          FROM deims.invoice_lines line
          JOIN deims.invoices invoice ON invoice.id = line.invoice_id
         WHERE line.id = p_invoice_line_id
         FOR UPDATE OF invoice, line;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Allocated invoice line % no longer exists', p_invoice_line_id
                USING ERRCODE = '23503';
        END IF;
        SELECT COALESCE(sum(allocated_net_amount), 0),
               COALESCE(sum(allocated_tax_amount), 0),
               COALESCE(sum(allocated_gross_amount), 0)
          INTO line_net, line_tax, line_gross
          FROM deims.invoice_line_charges
         WHERE invoice_line_id = p_invoice_line_id AND reversed_at IS NULL;
        IF line_net > line_row.net_amount - line_row.discount_amount
           OR line_tax > line_row.tax_amount OR line_gross > line_row.gross_amount THEN
            RAISE EXCEPTION 'Deferred allocation check failed for invoice line %', p_invoice_line_id
                USING ERRCODE = '23514';
        END IF;
    END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION deims.deferred_check_charge_allocation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, deims
AS $function$
BEGIN
    PERFORM deims.assert_charge_allocation_integrity(
        NEW.charge_id,
        NULLIF(to_jsonb(NEW) ->> 'invoice_line_id', '')::uuid
    );
    RETURN NULL;
END;
$function$;

DROP TRIGGER IF EXISTS trg_finance_validate_charge_allocation ON deims.charge_allocations;
CREATE TRIGGER trg_finance_validate_charge_allocation
    BEFORE INSERT OR UPDATE OR DELETE ON deims.charge_allocations
    FOR EACH ROW EXECUTE PROCEDURE deims.validate_charge_allocation_mutation();

DROP TRIGGER IF EXISTS trg_finance_validate_invoice_line_charge ON deims.invoice_line_charges;
CREATE TRIGGER trg_finance_validate_invoice_line_charge
    BEFORE INSERT OR UPDATE OR DELETE ON deims.invoice_line_charges
    FOR EACH ROW EXECUTE PROCEDURE deims.validate_invoice_line_charge_mutation();

DROP TRIGGER IF EXISTS trg_finance_guard_charge_allocation_parent ON deims.charges;
CREATE TRIGGER trg_finance_guard_charge_allocation_parent
    BEFORE UPDATE OR DELETE ON deims.charges
    FOR EACH ROW EXECUTE PROCEDURE deims.guard_charge_allocation_parent();

DROP TRIGGER IF EXISTS trg_finance_guard_invoice_line_parent ON deims.invoice_lines;
CREATE TRIGGER trg_finance_guard_invoice_line_parent
    BEFORE UPDATE OR DELETE ON deims.invoice_lines
    FOR EACH ROW EXECUTE PROCEDURE deims.guard_invoice_line_charge_parent();

DROP TRIGGER IF EXISTS trg_finance_deferred_charge_allocation ON deims.charge_allocations;
CREATE CONSTRAINT TRIGGER trg_finance_deferred_charge_allocation
    AFTER INSERT OR UPDATE ON deims.charge_allocations
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE PROCEDURE deims.deferred_check_charge_allocation();

DROP TRIGGER IF EXISTS trg_finance_deferred_invoice_line_charge ON deims.invoice_line_charges;
CREATE CONSTRAINT TRIGGER trg_finance_deferred_invoice_line_charge
    AFTER INSERT OR UPDATE ON deims.invoice_line_charges
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE PROCEDURE deims.deferred_check_charge_allocation();

CREATE OR REPLACE FUNCTION deims.validate_payment_application_mutation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, deims
AS $function$
DECLARE
    payment_row record;
    invoice_row record;
    linked_settlement_row record;
    settlement_row record;
    old_core jsonb;
    new_core jsonb;
    current_payment_total numeric(20,4);
    resulting_payment_total numeric(20,4);
    current_target_total numeric(20,4);
    resulting_target_total numeric(20,4);
    expected_current_status text;
    expected_settlement_status text;
    expected_direction text;
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'Payment application % cannot be deleted; record an explicit reversal', OLD.id
            USING ERRCODE = '55000';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtext('deims.finance'), hashtext(NEW.tenant_id::text));

    IF TG_OP = 'INSERT' THEN
        IF NEW.reversed_at IS NOT NULL OR NEW.reversed_by IS NOT NULL OR NEW.reversal_reason IS NOT NULL THEN
            RAISE EXCEPTION 'A payment application must be created active'
                USING ERRCODE = '23514';
        END IF;
    ELSE
        IF OLD.reversed_at IS NOT NULL THEN
            RAISE EXCEPTION 'Reversed payment application % is immutable', OLD.id
                USING ERRCODE = '55000';
        END IF;
        old_core := to_jsonb(OLD)
            - 'reversed_at' - 'reversed_by' - 'reversal_reason' - 'row_version' - 'updated_at';
        new_core := to_jsonb(NEW)
            - 'reversed_at' - 'reversed_by' - 'reversal_reason' - 'row_version' - 'updated_at';
        IF old_core IS DISTINCT FROM new_core OR NEW.reversed_at IS NULL THEN
            RAISE EXCEPTION 'Payment application corrections require a one-way reversal and a new application'
                USING ERRCODE = '55000';
        END IF;
    END IF;

    IF TG_OP = 'INSERT' AND NOT EXISTS (
        SELECT 1 FROM deims.tenant_memberships membership
         WHERE membership.tenant_id = NEW.tenant_id
           AND membership.user_id = NEW.applied_by
           AND membership.status = 'ACTIVE'
           AND membership.valid_from <= clock_timestamp()
           AND (membership.valid_to IS NULL OR membership.valid_to > clock_timestamp())
    ) THEN
        RAISE EXCEPTION 'Payment application actor is not an active tenant member'
            USING ERRCODE = '23514';
    END IF;
    IF NEW.reversed_at IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM deims.tenant_memberships membership
         WHERE membership.tenant_id = NEW.tenant_id
           AND membership.user_id = NEW.reversed_by
           AND membership.status = 'ACTIVE'
           AND membership.valid_from <= clock_timestamp()
           AND (membership.valid_to IS NULL OR membership.valid_to > clock_timestamp())
    ) THEN
        RAISE EXCEPTION 'Payment reversal actor is not an active tenant member'
            USING ERRCODE = '23514';
    END IF;
    IF NEW.reversed_at IS NOT NULL AND NEW.reversed_by = NEW.applied_by THEN
        RAISE EXCEPTION 'Payment application reversal requires a different active tenant member'
            USING ERRCODE = '23514';
    END IF;

    SELECT payment.* INTO payment_row
      FROM deims.payments payment
     WHERE payment.id = NEW.payment_id
     FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Payment % does not exist', NEW.payment_id USING ERRCODE = '23503';
    END IF;
    IF payment_row.tenant_id IS DISTINCT FROM NEW.tenant_id THEN
        RAISE EXCEPTION 'Payment application crosses tenant boundary' USING ERRCODE = '23514';
    END IF;

    SELECT COALESCE(sum(applied_amount), 0)
      INTO current_payment_total
      FROM deims.payment_applications application
     WHERE application.payment_id = NEW.payment_id
       AND application.reversed_at IS NULL;
    IF payment_row.unapplied_amount IS DISTINCT FROM payment_row.payment_amount - current_payment_total THEN
        RAISE EXCEPTION 'Payment header is out of sync with active applications'
            USING ERRCODE = '23514';
    END IF;
    expected_current_status := CASE
        WHEN current_payment_total = 0 THEN 'CLEARED'
        WHEN current_payment_total < payment_row.payment_amount THEN 'PARTIALLY_APPLIED'
        ELSE 'APPLIED'
    END;
    IF TG_OP = 'INSERT' AND payment_row.status <> expected_current_status THEN
        RAISE EXCEPTION 'Payment must be % before this application, found %',
            expected_current_status, payment_row.status USING ERRCODE = '23514';
    END IF;
    IF TG_OP = 'UPDATE' AND payment_row.status <> expected_current_status THEN
        RAISE EXCEPTION 'Payment projection status is out of sync before reversal'
            USING ERRCODE = '23514';
    END IF;

    resulting_payment_total := current_payment_total;
    IF TG_OP = 'INSERT' THEN
        resulting_payment_total := resulting_payment_total + NEW.applied_amount;
    ELSE
        resulting_payment_total := resulting_payment_total - OLD.applied_amount;
    END IF;
    IF resulting_payment_total < 0 OR resulting_payment_total > payment_row.payment_amount THEN
        RAISE EXCEPTION 'Active applications exceed payment amount %', payment_row.payment_amount
            USING ERRCODE = '23514';
    END IF;

    IF NEW.invoice_id IS NOT NULL THEN
        SELECT invoice.* INTO invoice_row
          FROM deims.invoices invoice
         WHERE invoice.id = NEW.invoice_id
         FOR UPDATE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Invoice % does not exist', NEW.invoice_id USING ERRCODE = '23503';
        END IF;
        IF invoice_row.tenant_id IS DISTINCT FROM NEW.tenant_id
           OR invoice_row.currency_code IS DISTINCT FROM payment_row.currency_code
           OR invoice_row.recipient_partner_id IS DISTINCT FROM payment_row.payer_partner_id
           OR invoice_row.issuer_partner_id IS DISTINCT FROM payment_row.payee_partner_id THEN
            RAISE EXCEPTION 'Payment and invoice tenant, currency or parties do not match'
                USING ERRCODE = '23514';
        END IF;
        expected_direction := CASE
            WHEN invoice_row.invoice_type IN ('RECEIVABLE','DEBIT_NOTE') THEN 'IN'
            ELSE 'OUT'
        END;
        IF payment_row.payment_direction <> expected_direction THEN
            RAISE EXCEPTION 'Payment direction % is incompatible with invoice type %',
                payment_row.payment_direction, invoice_row.invoice_type USING ERRCODE = '23514';
        END IF;

        SELECT COALESCE(sum(applied_amount), 0)
          INTO current_target_total
          FROM deims.payment_applications application
         WHERE application.invoice_id = NEW.invoice_id
           AND application.reversed_at IS NULL;
        IF invoice_row.paid_amount IS DISTINCT FROM current_target_total THEN
            RAISE EXCEPTION 'Invoice paid amount is out of sync with active payment applications'
                USING ERRCODE = '23514';
        END IF;
        expected_current_status := CASE
            WHEN current_target_total = 0 THEN 'POSTED'
            WHEN current_target_total < invoice_row.gross_amount THEN 'PARTIALLY_PAID'
            ELSE 'PAID'
        END;
        IF invoice_row.status <> expected_current_status THEN
            RAISE EXCEPTION 'Invoice payment status is out of sync before application mutation'
                USING ERRCODE = '23514';
        END IF;

        SELECT settlement.* INTO linked_settlement_row
          FROM deims.settlements settlement
         WHERE settlement.invoice_id = NEW.invoice_id
         FOR UPDATE;
        IF FOUND THEN
            expected_settlement_status := CASE
                WHEN current_target_total = 0 THEN 'INVOICED'
                WHEN current_target_total < invoice_row.gross_amount THEN 'PARTIALLY_PAID'
                ELSE 'PAID'
            END;
            IF linked_settlement_row.tenant_id IS DISTINCT FROM NEW.tenant_id
               OR linked_settlement_row.currency_code IS DISTINCT FROM invoice_row.currency_code
               OR linked_settlement_row.payer_partner_id IS DISTINCT FROM invoice_row.recipient_partner_id
               OR linked_settlement_row.payee_partner_id IS DISTINCT FROM invoice_row.issuer_partner_id
               OR linked_settlement_row.net_settlement_amount IS DISTINCT FROM invoice_row.gross_amount THEN
                RAISE EXCEPTION 'Canonical invoice and linked settlement scope or amount do not match'
                    USING ERRCODE = '23514';
            END IF;
            IF EXISTS (
                SELECT 1 FROM deims.payment_applications application
                 WHERE application.settlement_id = linked_settlement_row.id
                   AND application.reversed_at IS NULL
            ) THEN
                RAISE EXCEPTION 'Invoice-linked settlement contains a non-canonical direct payment application'
                    USING ERRCODE = '23514';
            END IF;
            IF linked_settlement_row.status <> expected_settlement_status
               AND NOT (TG_OP = 'UPDATE' AND expected_settlement_status = 'PAID'
                        AND linked_settlement_row.status = 'CLOSED') THEN
                RAISE EXCEPTION 'Linked settlement payment status is out of sync with its canonical invoice'
                    USING ERRCODE = '23514';
            END IF;
        END IF;
        resulting_target_total := current_target_total +
            CASE WHEN TG_OP = 'INSERT' THEN NEW.applied_amount ELSE -OLD.applied_amount END;
        IF resulting_target_total < 0 OR resulting_target_total > invoice_row.gross_amount THEN
            RAISE EXCEPTION 'Active applications exceed invoice gross amount %', invoice_row.gross_amount
                USING ERRCODE = '23514';
        END IF;
    ELSE
        SELECT settlement.tenant_id, settlement.payer_partner_id, settlement.payee_partner_id,
               settlement.owner_partner_id, settlement.currency_code,
               settlement.net_settlement_amount, settlement.status, settlement.invoice_id,
               batch.settlement_type
          INTO settlement_row
          FROM deims.settlements settlement
          LEFT JOIN deims.settlement_batches batch ON batch.id = settlement.settlement_batch_id
         WHERE settlement.id = NEW.settlement_id
         FOR UPDATE OF settlement;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Settlement % does not exist', NEW.settlement_id USING ERRCODE = '23503';
        END IF;
        IF settlement_row.tenant_id IS DISTINCT FROM NEW.tenant_id
           OR settlement_row.currency_code IS DISTINCT FROM payment_row.currency_code
           OR settlement_row.payer_partner_id IS DISTINCT FROM payment_row.payer_partner_id
           OR settlement_row.payee_partner_id IS DISTINCT FROM payment_row.payee_partner_id THEN
            RAISE EXCEPTION 'Payment and settlement tenant, currency or parties do not match'
                USING ERRCODE = '23514';
        END IF;
        IF settlement_row.invoice_id IS NOT NULL THEN
            RAISE EXCEPTION 'Invoice-linked settlement % must be paid through canonical invoice %',
                NEW.settlement_id, settlement_row.invoice_id USING ERRCODE = '23514';
        END IF;
        expected_direction := CASE
            WHEN settlement_row.settlement_type = 'RECEIVABLE' THEN 'IN'
            WHEN settlement_row.settlement_type = 'PAYABLE' THEN 'OUT'
            WHEN settlement_row.owner_partner_id = settlement_row.payee_partner_id THEN 'IN'
            WHEN settlement_row.owner_partner_id = settlement_row.payer_partner_id THEN 'OUT'
            ELSE NULL
        END;
        IF expected_direction IS NULL OR payment_row.payment_direction <> expected_direction THEN
            RAISE EXCEPTION 'Payment direction cannot be reconciled with settlement ownership/type'
                USING ERRCODE = '23514';
        END IF;

        SELECT COALESCE(sum(applied_amount), 0)
          INTO current_target_total
          FROM deims.payment_applications application
         WHERE application.settlement_id = NEW.settlement_id
           AND application.reversed_at IS NULL;
        expected_current_status := CASE
            WHEN current_target_total = 0 THEN 'INVOICED'
            WHEN current_target_total < settlement_row.net_settlement_amount THEN 'PARTIALLY_PAID'
            ELSE 'PAID'
        END;
        IF settlement_row.status <> expected_current_status
           AND NOT (TG_OP = 'UPDATE' AND expected_current_status = 'PAID'
                    AND settlement_row.status = 'CLOSED') THEN
            RAISE EXCEPTION 'Settlement payment status is out of sync before application mutation'
                USING ERRCODE = '23514';
        END IF;
        resulting_target_total := current_target_total +
            CASE WHEN TG_OP = 'INSERT' THEN NEW.applied_amount ELSE -OLD.applied_amount END;
        IF resulting_target_total < 0 OR resulting_target_total > settlement_row.net_settlement_amount THEN
            RAISE EXCEPTION 'Active applications exceed settlement amount %', settlement_row.net_settlement_amount
                USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION deims.guard_payment_projection()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, deims
AS $function$
DECLARE
    application_total numeric(20,4);
    expected_status text;
    has_history boolean;
    old_core jsonb;
    new_core jsonb;
    authorized boolean;
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'Payment % cannot be deleted; use an explicit reversal payment', OLD.id
            USING ERRCODE = '55000';
    END IF;

    IF TG_OP = 'INSERT' THEN
        IF NEW.unapplied_amount IS DISTINCT FROM NEW.payment_amount
           OR NEW.status NOT IN ('PENDING','RECEIVED','CLEARED') THEN
            RAISE EXCEPTION 'A payment must be created fully unapplied in PENDING, RECEIVED or CLEARED status'
                USING ERRCODE = '23514';
        END IF;
        RETURN NEW;
    END IF;

    IF OLD.status IN ('FAILED','REVERSED','CANCELLED') THEN
        RAISE EXCEPTION 'Final payment % is immutable; create a correction/reversal payment', OLD.id
            USING ERRCODE = '55000';
    END IF;

    SELECT COALESCE(sum(applied_amount) FILTER (WHERE reversed_at IS NULL), 0), count(*) > 0
      INTO application_total, has_history
      FROM deims.payment_applications
     WHERE payment_id = OLD.id;
    authorized := deims.finance_projection_authorized('PAYMENT_APPLICATION');

    old_core := to_jsonb(OLD) - 'unapplied_amount' - 'status' - 'row_version' - 'updated_at';
    new_core := to_jsonb(NEW) - 'unapplied_amount' - 'status' - 'row_version' - 'updated_at';
    IF (authorized OR has_history) AND old_core IS DISTINCT FROM new_core THEN
        RAISE EXCEPTION 'Payment identity, amount, parties, currency and evidence are immutable after application'
            USING ERRCODE = '55000';
    END IF;
    IF application_total > NEW.payment_amount THEN
        RAISE EXCEPTION 'Active payment applications exceed payment amount'
            USING ERRCODE = '23514';
    END IF;
    IF NEW.unapplied_amount IS DISTINCT FROM NEW.payment_amount - application_total THEN
        RAISE EXCEPTION 'Payment unapplied amount must equal payment amount less active applications'
            USING ERRCODE = '23514';
    END IF;

    expected_status := CASE
        WHEN application_total = 0 THEN 'CLEARED'
        WHEN application_total < NEW.payment_amount THEN 'PARTIALLY_APPLIED'
        ELSE 'APPLIED'
    END;
    IF authorized THEN
        IF NEW.status <> expected_status THEN
            RAISE EXCEPTION 'Authorized payment projection must set status %', expected_status
                USING ERRCODE = '23514';
        END IF;
    ELSIF application_total > 0 AND NEW.status <> expected_status THEN
        RAISE EXCEPTION 'Payment application status must be derived from active applications'
            USING ERRCODE = '23514';
    ELSIF application_total = 0 AND NEW.status IN ('PARTIALLY_APPLIED','APPLIED') THEN
        RAISE EXCEPTION 'Applied payment status requires an active application'
            USING ERRCODE = '23514';
    END IF;
    IF NOT authorized AND OLD.status IS DISTINCT FROM NEW.status AND NOT (
        (OLD.status = 'PENDING' AND NEW.status IN ('RECEIVED','FAILED','CANCELLED'))
        OR (OLD.status = 'RECEIVED' AND NEW.status IN ('CLEARED','FAILED','CANCELLED'))
        OR (OLD.status = 'CLEARED' AND NEW.status IN ('FAILED','REVERSED','CANCELLED'))
    ) THEN
        RAISE EXCEPTION 'Invalid payment status transition from % to %', OLD.status, NEW.status
            USING ERRCODE = '23514';
    END IF;
    IF NEW.status IN ('FAILED','REVERSED','CANCELLED') AND application_total <> 0 THEN
        RAISE EXCEPTION 'Reverse all payment applications before finalizing the payment'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION deims.guard_settlement_payment_projection()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, deims
AS $function$
DECLARE
    application_total numeric(20,4);
    expected_status text;
    has_history boolean;
    invoice_row record;
    old_core jsonb;
    new_core jsonb;
    authorized boolean;
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.status <> 'DRAFT' THEN
            RAISE EXCEPTION 'A settlement must be created in DRAFT status'
                USING ERRCODE = '23514';
        END IF;
        IF NEW.invoice_id IS NOT NULL THEN
            PERFORM pg_advisory_xact_lock(hashtext('deims.finance'), hashtext(NEW.tenant_id::text));
            SELECT invoice.* INTO invoice_row
              FROM deims.invoices invoice WHERE invoice.id = NEW.invoice_id FOR SHARE;
            IF NOT FOUND THEN
                RAISE EXCEPTION 'Canonical settlement invoice % does not exist', NEW.invoice_id
                    USING ERRCODE = '23503';
            END IF;
            IF invoice_row.tenant_id IS DISTINCT FROM NEW.tenant_id
               OR invoice_row.currency_code IS DISTINCT FROM NEW.currency_code
               OR invoice_row.recipient_partner_id IS DISTINCT FROM NEW.payer_partner_id
               OR invoice_row.issuer_partner_id IS DISTINCT FROM NEW.payee_partner_id
               OR invoice_row.gross_amount IS DISTINCT FROM NEW.net_settlement_amount
               OR invoice_row.gross_amount = 0
               OR invoice_row.paid_amount <> 0
               OR invoice_row.status <> 'POSTED' THEN
                RAISE EXCEPTION 'Canonical settlement invoice scope, amount or payment state is invalid'
                    USING ERRCODE = '23514';
            END IF;
        END IF;
        RETURN NEW;
    END IF;

    SELECT COALESCE(sum(applied_amount) FILTER (WHERE reversed_at IS NULL), 0), count(*) > 0
      INTO application_total, has_history
      FROM deims.payment_applications
     WHERE settlement_id = OLD.id
        OR (OLD.invoice_id IS NOT NULL AND invoice_id = OLD.invoice_id);
    IF TG_OP = 'DELETE' THEN
        IF has_history THEN
            RAISE EXCEPTION 'Settlement % with payment history cannot be deleted', OLD.id
                USING ERRCODE = '55000';
        END IF;
        IF EXISTS (SELECT 1 FROM deims.settlement_lines WHERE settlement_id = OLD.id) THEN
            RAISE EXCEPTION 'Delete draft settlement lines explicitly before deleting settlement %', OLD.id
                USING ERRCODE = '55000';
        END IF;
        RETURN OLD;
    END IF;

    authorized := deims.finance_projection_authorized('PAYMENT_APPLICATION');
    old_core := to_jsonb(OLD) - 'status' - 'row_version' - 'updated_at';
    new_core := to_jsonb(NEW) - 'status' - 'row_version' - 'updated_at';
    IF has_history AND old_core IS DISTINCT FROM new_core THEN
        RAISE EXCEPTION 'Settlement amount, parties, currency and identity are immutable after payment application'
            USING ERRCODE = '55000';
    END IF;
    IF OLD.invoice_id IS NOT NULL AND old_core IS DISTINCT FROM new_core THEN
        RAISE EXCEPTION 'Invoice-linked settlement scope and amounts are immutable'
            USING ERRCODE = '55000';
    END IF;
    IF OLD.invoice_id IS NOT NULL AND OLD.invoice_id IS DISTINCT FROM NEW.invoice_id THEN
        RAISE EXCEPTION 'Canonical settlement invoice link is immutable once assigned'
            USING ERRCODE = '55000';
    END IF;
    IF OLD.invoice_id IS DISTINCT FROM NEW.invoice_id AND NEW.invoice_id IS NOT NULL THEN
        IF EXISTS (SELECT 1 FROM deims.payment_applications WHERE settlement_id = OLD.id) THEN
            RAISE EXCEPTION 'A settlement with direct payment history cannot be linked to an invoice'
                USING ERRCODE = '55000';
        END IF;
        PERFORM pg_advisory_xact_lock(hashtext('deims.finance'), hashtext(NEW.tenant_id::text));
        SELECT invoice.* INTO invoice_row
          FROM deims.invoices invoice WHERE invoice.id = NEW.invoice_id FOR SHARE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Canonical settlement invoice % does not exist', NEW.invoice_id
                USING ERRCODE = '23503';
        END IF;
        IF invoice_row.tenant_id IS DISTINCT FROM NEW.tenant_id
           OR invoice_row.currency_code IS DISTINCT FROM NEW.currency_code
           OR invoice_row.recipient_partner_id IS DISTINCT FROM NEW.payer_partner_id
           OR invoice_row.issuer_partner_id IS DISTINCT FROM NEW.payee_partner_id
           OR invoice_row.gross_amount IS DISTINCT FROM NEW.net_settlement_amount
           OR invoice_row.gross_amount = 0
           OR invoice_row.paid_amount <> 0
           OR invoice_row.status <> 'POSTED' THEN
            RAISE EXCEPTION 'Canonical settlement invoice scope, amount or payment state is invalid'
                USING ERRCODE = '23514';
        END IF;
    END IF;
    IF application_total > NEW.net_settlement_amount THEN
        RAISE EXCEPTION 'Active applications exceed settlement amount'
            USING ERRCODE = '23514';
    END IF;
    expected_status := CASE
        WHEN NEW.net_settlement_amount = 0 AND application_total = 0 THEN 'PAID'
        WHEN application_total = 0 THEN 'INVOICED'
        WHEN application_total < NEW.net_settlement_amount THEN 'PARTIALLY_PAID'
        ELSE 'PAID'
    END;
    IF authorized THEN
        IF old_core IS DISTINCT FROM new_core OR NEW.status <> expected_status THEN
            RAISE EXCEPTION 'Authorized settlement projection may change only status to %', expected_status
                USING ERRCODE = '23514';
        END IF;
        RETURN NEW;
    END IF;

    IF OLD.status IS DISTINCT FROM NEW.status AND NEW.status IN ('PARTIALLY_PAID','PAID')
       AND NOT (
           OLD.status = 'INVOICED' AND NEW.status = 'PAID'
           AND NEW.net_settlement_amount = 0 AND application_total = 0
       ) THEN
        RAISE EXCEPTION 'Settlement payment status is maintained only by payment applications'
            USING ERRCODE = '23514';
    END IF;
    IF OLD.status = 'PARTIALLY_PAID' AND NEW.status <> OLD.status THEN
        RAISE EXCEPTION 'Reverse or complete payment applications before changing a partially paid settlement'
            USING ERRCODE = '23514';
    END IF;
    IF NEW.status = 'PARTIALLY_PAID' AND expected_status <> 'PARTIALLY_PAID' THEN
        RAISE EXCEPTION 'Settlement partial-payment status does not match active applications'
            USING ERRCODE = '23514';
    END IF;
    IF NEW.status IN ('PAID','CLOSED') AND expected_status <> 'PAID' THEN
        RAISE EXCEPTION 'Paid/closed settlement must be fully covered by active applications'
            USING ERRCODE = '23514';
    END IF;
    IF NEW.status IN ('CANCELLED','REVERSED') AND application_total <> 0 THEN
        RAISE EXCEPTION 'Reverse all applications before cancelling or reversing a settlement'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION deims.project_payment_application()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, deims
AS $function$
DECLARE
    authorization_token uuid;
    payment_total numeric(20,4);
    target_total numeric(20,4);
    payment_row record;
    target_amount numeric(20,4);
    target_status text;
BEGIN
    authorization_token := deims.open_finance_projection_authorization('PAYMENT_APPLICATION');
    BEGIN
        SELECT payment.* INTO payment_row
          FROM deims.payments payment
         WHERE payment.id = NEW.payment_id
         FOR UPDATE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Payment % disappeared during projection', NEW.payment_id
                USING ERRCODE = '23503';
        END IF;
        SELECT COALESCE(sum(applied_amount), 0)
          INTO payment_total
          FROM deims.payment_applications
         WHERE payment_id = NEW.payment_id AND reversed_at IS NULL;
        UPDATE deims.payments
           SET unapplied_amount = payment_row.payment_amount - payment_total,
               status = CASE
                   WHEN payment_total = 0 THEN 'CLEARED'
                   WHEN payment_total < payment_row.payment_amount THEN 'PARTIALLY_APPLIED'
                   ELSE 'APPLIED'
               END
         WHERE id = NEW.payment_id;

        IF NEW.invoice_id IS NOT NULL THEN
            SELECT invoice.gross_amount INTO target_amount
              FROM deims.invoices invoice
             WHERE invoice.id = NEW.invoice_id
             FOR UPDATE;
            IF NOT FOUND THEN
                RAISE EXCEPTION 'Invoice % disappeared during projection', NEW.invoice_id
                    USING ERRCODE = '23503';
            END IF;
            SELECT COALESCE(sum(applied_amount), 0)
              INTO target_total
              FROM deims.payment_applications
             WHERE invoice_id = NEW.invoice_id AND reversed_at IS NULL;
            target_status := CASE
                WHEN target_total = 0 THEN 'POSTED'
                WHEN target_total < target_amount THEN 'PARTIALLY_PAID'
                ELSE 'PAID'
            END;
            UPDATE deims.invoices
               SET paid_amount = target_total,
                   outstanding_amount = gross_amount - target_total,
                   status = target_status
             WHERE id = NEW.invoice_id;
            UPDATE deims.settlements
               SET status = CASE
                   WHEN target_total = 0 THEN 'INVOICED'
                   WHEN target_total < target_amount THEN 'PARTIALLY_PAID'
                   ELSE 'PAID'
               END
             WHERE invoice_id = NEW.invoice_id;
        ELSE
            SELECT settlement.net_settlement_amount INTO target_amount
              FROM deims.settlements settlement
             WHERE settlement.id = NEW.settlement_id
             FOR UPDATE;
            IF NOT FOUND THEN
                RAISE EXCEPTION 'Settlement % disappeared during projection', NEW.settlement_id
                    USING ERRCODE = '23503';
            END IF;
            SELECT COALESCE(sum(applied_amount), 0)
              INTO target_total
              FROM deims.payment_applications
             WHERE settlement_id = NEW.settlement_id AND reversed_at IS NULL;
            target_status := CASE
                WHEN target_total = 0 THEN 'INVOICED'
                WHEN target_total < target_amount THEN 'PARTIALLY_PAID'
                ELSE 'PAID'
            END;
            UPDATE deims.settlements SET status = target_status WHERE id = NEW.settlement_id;
        END IF;
        PERFORM deims.close_finance_projection_authorization(authorization_token);
    EXCEPTION WHEN OTHERS THEN
        PERFORM deims.close_finance_projection_authorization(authorization_token);
        RAISE;
    END;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION deims.assert_payment_application_projection()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, deims
AS $function$
DECLARE
    payment_row record;
    invoice_row record;
    linked_settlement_row record;
    settlement_row record;
    application_total numeric(20,4);
    expected_status text;
BEGIN
    SELECT payment.* INTO payment_row
      FROM deims.payments payment WHERE payment.id = NEW.payment_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Payment % is missing at deferred projection check', NEW.payment_id
            USING ERRCODE = '23503';
    END IF;
    SELECT COALESCE(sum(applied_amount), 0) INTO application_total
      FROM deims.payment_applications
     WHERE payment_id = NEW.payment_id AND reversed_at IS NULL;
    expected_status := CASE
        WHEN application_total = 0 THEN 'CLEARED'
        WHEN application_total < payment_row.payment_amount THEN 'PARTIALLY_APPLIED'
        ELSE 'APPLIED'
    END;
    IF application_total > payment_row.payment_amount
       OR payment_row.unapplied_amount IS DISTINCT FROM payment_row.payment_amount - application_total
       OR payment_row.status <> expected_status THEN
        RAISE EXCEPTION 'Deferred payment projection check failed for payment %', NEW.payment_id
            USING ERRCODE = '23514';
    END IF;

    IF NEW.invoice_id IS NOT NULL THEN
        SELECT invoice.* INTO invoice_row
          FROM deims.invoices invoice WHERE invoice.id = NEW.invoice_id FOR UPDATE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Invoice % is missing at deferred projection check', NEW.invoice_id
                USING ERRCODE = '23503';
        END IF;
        SELECT COALESCE(sum(applied_amount), 0) INTO application_total
          FROM deims.payment_applications
         WHERE invoice_id = NEW.invoice_id AND reversed_at IS NULL;
        expected_status := CASE
            WHEN application_total = 0 THEN 'POSTED'
            WHEN application_total < invoice_row.gross_amount THEN 'PARTIALLY_PAID'
            ELSE 'PAID'
        END;
        IF application_total > invoice_row.gross_amount
           OR invoice_row.paid_amount IS DISTINCT FROM application_total
           OR invoice_row.outstanding_amount IS DISTINCT FROM invoice_row.gross_amount - application_total
           OR invoice_row.status <> expected_status THEN
            RAISE EXCEPTION 'Deferred invoice payment projection check failed for invoice %', NEW.invoice_id
                USING ERRCODE = '23514';
        END IF;
        SELECT settlement.* INTO linked_settlement_row
          FROM deims.settlements settlement
         WHERE settlement.invoice_id = NEW.invoice_id
         FOR UPDATE;
        IF FOUND THEN
            expected_status := CASE
                WHEN application_total = 0 THEN 'INVOICED'
                WHEN application_total < invoice_row.gross_amount THEN 'PARTIALLY_PAID'
                ELSE 'PAID'
            END;
            IF linked_settlement_row.tenant_id IS DISTINCT FROM invoice_row.tenant_id
               OR linked_settlement_row.currency_code IS DISTINCT FROM invoice_row.currency_code
               OR linked_settlement_row.payer_partner_id IS DISTINCT FROM invoice_row.recipient_partner_id
               OR linked_settlement_row.payee_partner_id IS DISTINCT FROM invoice_row.issuer_partner_id
               OR linked_settlement_row.net_settlement_amount IS DISTINCT FROM invoice_row.gross_amount
               OR NOT (
                   linked_settlement_row.status = expected_status
                   OR (expected_status = 'PAID' AND linked_settlement_row.status = 'CLOSED')
               )
               OR EXISTS (
                   SELECT 1 FROM deims.payment_applications application
                    WHERE application.settlement_id = linked_settlement_row.id
                      AND application.reversed_at IS NULL
               ) THEN
                RAISE EXCEPTION 'Deferred canonical settlement projection check failed for invoice %',
                    NEW.invoice_id USING ERRCODE = '23514';
            END IF;
        END IF;
    ELSE
        SELECT settlement.* INTO settlement_row
          FROM deims.settlements settlement WHERE settlement.id = NEW.settlement_id FOR UPDATE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Settlement % is missing at deferred projection check', NEW.settlement_id
                USING ERRCODE = '23503';
        END IF;
        SELECT COALESCE(sum(applied_amount), 0) INTO application_total
          FROM deims.payment_applications
         WHERE settlement_id = NEW.settlement_id AND reversed_at IS NULL;
        expected_status := CASE
            WHEN application_total = 0 THEN 'INVOICED'
            WHEN application_total < settlement_row.net_settlement_amount THEN 'PARTIALLY_PAID'
            ELSE 'PAID'
        END;
        IF application_total > settlement_row.net_settlement_amount
           OR NOT (
               settlement_row.status = expected_status
               OR (expected_status = 'PAID' AND settlement_row.status = 'CLOSED')
           ) THEN
            RAISE EXCEPTION 'Deferred settlement payment projection check failed for settlement %', NEW.settlement_id
                USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NULL;
END;
$function$;

CREATE OR REPLACE FUNCTION deims.prevent_finance_history_truncate()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    RAISE EXCEPTION '%.% contains financial allocation history and cannot be truncated',
        TG_TABLE_SCHEMA, TG_TABLE_NAME USING ERRCODE = '55000';
END;
$function$;

REVOKE ALL ON FUNCTION deims.validate_charge_allocation_mutation() FROM PUBLIC;
REVOKE ALL ON FUNCTION deims.validate_invoice_line_charge_mutation() FROM PUBLIC;
REVOKE ALL ON FUNCTION deims.guard_charge_allocation_parent() FROM PUBLIC;
REVOKE ALL ON FUNCTION deims.guard_invoice_line_charge_parent() FROM PUBLIC;
REVOKE ALL ON FUNCTION deims.assert_charge_allocation_integrity(uuid,uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION deims.deferred_check_charge_allocation() FROM PUBLIC;
REVOKE ALL ON FUNCTION deims.validate_payment_application_mutation() FROM PUBLIC;
REVOKE ALL ON FUNCTION deims.guard_payment_projection() FROM PUBLIC;
REVOKE ALL ON FUNCTION deims.guard_settlement_payment_projection() FROM PUBLIC;
REVOKE ALL ON FUNCTION deims.project_payment_application() FROM PUBLIC;
REVOKE ALL ON FUNCTION deims.assert_payment_application_projection() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_finance_validate_payment_application ON deims.payment_applications;
CREATE TRIGGER trg_finance_validate_payment_application
    BEFORE INSERT OR UPDATE OR DELETE ON deims.payment_applications
    FOR EACH ROW EXECUTE PROCEDURE deims.validate_payment_application_mutation();

DROP TRIGGER IF EXISTS trg_finance_project_payment_application ON deims.payment_applications;
CREATE TRIGGER trg_finance_project_payment_application
    AFTER INSERT OR UPDATE ON deims.payment_applications
    FOR EACH ROW EXECUTE PROCEDURE deims.project_payment_application();

DROP TRIGGER IF EXISTS trg_finance_deferred_payment_projection ON deims.payment_applications;
CREATE CONSTRAINT TRIGGER trg_finance_deferred_payment_projection
    AFTER INSERT OR UPDATE ON deims.payment_applications
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE PROCEDURE deims.assert_payment_application_projection();

DROP TRIGGER IF EXISTS trg_finance_guard_payment_projection ON deims.payments;
CREATE TRIGGER trg_finance_guard_payment_projection
    BEFORE INSERT OR UPDATE OR DELETE ON deims.payments
    FOR EACH ROW EXECUTE PROCEDURE deims.guard_payment_projection();

DROP TRIGGER IF EXISTS trg_finance_guard_settlement_projection ON deims.settlements;
CREATE TRIGGER trg_finance_guard_settlement_projection
    BEFORE INSERT OR UPDATE OR DELETE ON deims.settlements
    FOR EACH ROW EXECUTE PROCEDURE deims.guard_settlement_payment_projection();

DROP TRIGGER IF EXISTS trg_finance_prevent_truncate ON deims.charge_allocations;
CREATE TRIGGER trg_finance_prevent_truncate
    BEFORE TRUNCATE ON deims.charge_allocations
    FOR EACH STATEMENT EXECUTE PROCEDURE deims.prevent_finance_history_truncate();
DROP TRIGGER IF EXISTS trg_finance_prevent_truncate ON deims.invoice_line_charges;
CREATE TRIGGER trg_finance_prevent_truncate
    BEFORE TRUNCATE ON deims.invoice_line_charges
    FOR EACH STATEMENT EXECUTE PROCEDURE deims.prevent_finance_history_truncate();
DROP TRIGGER IF EXISTS trg_finance_prevent_truncate ON deims.payment_applications;
CREATE TRIGGER trg_finance_prevent_truncate
    BEFORE TRUNCATE ON deims.payment_applications
    FOR EACH STATEMENT EXECUTE PROCEDURE deims.prevent_finance_history_truncate();

CREATE OR REPLACE FUNCTION deims.validate_settlement_line_mutation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, deims
AS $function$
DECLARE
    charge_row record;
    settlement_row record;
    target_tenant_id uuid;
    target_charge_id uuid;
    target_settlement_id uuid;
BEGIN
    target_tenant_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.tenant_id ELSE NEW.tenant_id END;
    target_charge_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.charge_id ELSE NEW.charge_id END;
    target_settlement_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.settlement_id ELSE NEW.settlement_id END;
    PERFORM pg_advisory_xact_lock(hashtext('deims.finance'), hashtext(target_tenant_id::text));

    -- Charge is always locked before settlement, matching the other finance allocation paths.
    SELECT charge.* INTO charge_row
      FROM deims.charges charge WHERE charge.id = target_charge_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Settlement charge % does not exist', target_charge_id USING ERRCODE = '23503';
    END IF;
    SELECT settlement.*, batch.settlement_type INTO settlement_row
      FROM deims.settlements settlement
      LEFT JOIN deims.settlement_batches batch ON batch.id = settlement.settlement_batch_id
     WHERE settlement.id = target_settlement_id
     FOR UPDATE OF settlement;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Settlement % does not exist', target_settlement_id USING ERRCODE = '23503';
    END IF;
    IF settlement_row.status NOT IN ('DRAFT','REVIEW','APPROVAL_PENDING') THEN
        RAISE EXCEPTION 'Settlement lines are immutable after settlement approval'
            USING ERRCODE = '55000';
    END IF;
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;

    IF charge_row.tenant_id IS DISTINCT FROM NEW.tenant_id
       OR settlement_row.tenant_id IS DISTINCT FROM NEW.tenant_id THEN
        RAISE EXCEPTION 'Settlement line crosses tenant boundary' USING ERRCODE = '23514';
    END IF;
    IF charge_row.currency_code IS DISTINCT FROM settlement_row.currency_code
       OR charge_row.payer_partner_id IS DISTINCT FROM settlement_row.payer_partner_id
       OR charge_row.payee_partner_id IS DISTINCT FROM settlement_row.payee_partner_id
       OR (settlement_row.owner_partner_id IS NOT NULL
           AND charge_row.owner_partner_id IS DISTINCT FROM settlement_row.owner_partner_id) THEN
        RAISE EXCEPTION 'Settlement charge currency, payer, payee or owner does not match its header'
            USING ERRCODE = '23514';
    END IF;
    IF (settlement_row.settlement_type = 'RECEIVABLE' AND charge_row.direction <> 'RECEIVABLE')
       OR (settlement_row.settlement_type = 'PAYABLE' AND charge_row.direction <> 'PAYABLE') THEN
        RAISE EXCEPTION 'Charge direction is incompatible with settlement batch type'
            USING ERRCODE = '23514';
    END IF;
    IF charge_row.status <> 'APPROVED' THEN
        RAISE EXCEPTION 'Only an approved charge may be added to a settlement'
            USING ERRCODE = '23514';
    END IF;
    IF NEW.status <> 'INCLUDED' THEN
        RAISE EXCEPTION 'Settlement line status must be INCLUDED; cancel/reverse the settlement for corrections'
            USING ERRCODE = '23514';
    END IF;
    IF NEW.charge_amount > charge_row.net_amount
       OR NEW.tax_amount > charge_row.tax_amount
       OR NEW.charge_amount + NEW.tax_amount > charge_row.gross_amount THEN
        RAISE EXCEPTION 'Settlement line exceeds charge net, tax or gross amount'
            USING ERRCODE = '23514';
    END IF;
    IF EXISTS (
        SELECT 1
          FROM deims.settlement_lines other_line
          JOIN deims.settlements other_settlement ON other_settlement.id = other_line.settlement_id
         WHERE other_line.charge_id = NEW.charge_id
           AND other_line.id <> NEW.id
           AND other_settlement.id <> NEW.settlement_id
           AND other_settlement.status NOT IN ('CANCELLED','REVERSED')
    ) THEN
        RAISE EXCEPTION 'Charge % already belongs to another active settlement', NEW.charge_id
            USING ERRCODE = '23505';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION deims.validate_settlement_commitment()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, deims
AS $function$
DECLARE
    line_count bigint;
    line_charge numeric(20,4);
    line_adjustment numeric(20,4);
    line_tax numeric(20,4);
    line_settled numeric(20,4);
    invoice_row record;
BEGIN
    IF NEW.status NOT IN ('APPROVED','INVOICED','PARTIALLY_PAID','PAID','CLOSED') THEN
        RETURN NEW;
    END IF;
    IF TG_OP = 'UPDATE' AND deims.finance_projection_authorized('PAYMENT_APPLICATION') THEN
        RETURN NEW;
    END IF;

    SELECT count(*), COALESCE(sum(charge_amount), 0),
           COALESCE(sum(adjustment_amount), 0), COALESCE(sum(tax_amount), 0),
           COALESCE(sum(settled_amount), 0)
      INTO line_count, line_charge, line_adjustment, line_tax, line_settled
      FROM deims.settlement_lines
     WHERE settlement_id = NEW.id;
    IF line_count < 1
       OR line_charge IS DISTINCT FROM NEW.gross_charge_amount
       OR line_adjustment IS DISTINCT FROM NEW.adjustment_amount
       OR line_tax IS DISTINCT FROM NEW.tax_amount
       OR line_settled - NEW.withholding_amount IS DISTINCT FROM NEW.net_settlement_amount THEN
        RAISE EXCEPTION 'Settlement header amounts do not reconcile to included lines and withholding'
            USING ERRCODE = '23514';
    END IF;
    IF EXISTS (
        SELECT 1
          FROM deims.settlement_lines line
          JOIN deims.charges charge ON charge.id = line.charge_id
          LEFT JOIN deims.settlement_batches batch ON batch.id = NEW.settlement_batch_id
         WHERE line.settlement_id = NEW.id
           AND (
               line.status <> 'INCLUDED'
               OR line.tenant_id IS DISTINCT FROM NEW.tenant_id
               OR charge.tenant_id IS DISTINCT FROM NEW.tenant_id
               OR charge.currency_code IS DISTINCT FROM NEW.currency_code
               OR charge.payer_partner_id IS DISTINCT FROM NEW.payer_partner_id
               OR charge.payee_partner_id IS DISTINCT FROM NEW.payee_partner_id
               OR (NEW.owner_partner_id IS NOT NULL
                   AND charge.owner_partner_id IS DISTINCT FROM NEW.owner_partner_id)
               OR charge.status NOT IN ('APPROVED','INVOICED','SETTLED')
               OR line.charge_amount > charge.net_amount
               OR line.tax_amount > charge.tax_amount
               OR line.charge_amount + line.tax_amount > charge.gross_amount
               OR (batch.settlement_type = 'RECEIVABLE' AND charge.direction <> 'RECEIVABLE')
               OR (batch.settlement_type = 'PAYABLE' AND charge.direction <> 'PAYABLE')
               OR EXISTS (
                   SELECT 1
                     FROM deims.invoice_line_charges invoice_allocation
                    WHERE invoice_allocation.charge_id = line.charge_id
                      AND invoice_allocation.reversed_at IS NULL
                      AND (NEW.invoice_id IS NULL
                           OR invoice_allocation.invoice_id IS DISTINCT FROM NEW.invoice_id)
               )
           )
    ) THEN
        RAISE EXCEPTION 'Settlement contains an invalid charge scope, status, direction or amount'
            USING ERRCODE = '23514';
    END IF;
    IF EXISTS (
        SELECT 1
          FROM deims.settlement_lines line
          JOIN deims.settlement_lines other_line
            ON other_line.charge_id = line.charge_id
           AND other_line.settlement_id <> line.settlement_id
          JOIN deims.settlements other_settlement ON other_settlement.id = other_line.settlement_id
         WHERE line.settlement_id = NEW.id
           AND other_settlement.status NOT IN ('CANCELLED','REVERSED')
    ) THEN
        RAISE EXCEPTION 'A charge is included in more than one active settlement'
            USING ERRCODE = '23505';
    END IF;

    IF NEW.invoice_id IS NOT NULL
       AND NEW.status IN ('APPROVED','INVOICED','PARTIALLY_PAID','PAID','CLOSED') THEN
        SELECT invoice.* INTO invoice_row
          FROM deims.invoices invoice WHERE invoice.id = NEW.invoice_id FOR SHARE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Canonical settlement invoice does not exist' USING ERRCODE = '23503';
        END IF;
        IF invoice_row.tenant_id IS DISTINCT FROM NEW.tenant_id
           OR invoice_row.currency_code IS DISTINCT FROM NEW.currency_code
           OR invoice_row.recipient_partner_id IS DISTINCT FROM NEW.payer_partner_id
           OR invoice_row.issuer_partner_id IS DISTINCT FROM NEW.payee_partner_id
           OR invoice_row.gross_amount IS DISTINCT FROM NEW.net_settlement_amount
           OR (NEW.status IN ('APPROVED','INVOICED') AND invoice_row.status <> 'POSTED')
           OR (NEW.status = 'PARTIALLY_PAID' AND invoice_row.status <> 'PARTIALLY_PAID')
           OR (NEW.status IN ('PAID','CLOSED') AND invoice_row.status <> 'PAID') THEN
            RAISE EXCEPTION 'Canonical invoice does not match committed settlement scope, amount or status'
                USING ERRCODE = '23514';
        END IF;
        IF EXISTS (
            SELECT 1
              FROM deims.settlement_lines line
              LEFT JOIN deims.invoice_line_charges allocation
                ON allocation.invoice_id = NEW.invoice_id
               AND allocation.charge_id = line.charge_id
               AND allocation.reversed_at IS NULL
             WHERE line.settlement_id = NEW.id
               AND (
                   allocation.id IS NULL
                   OR allocation.allocated_net_amount IS DISTINCT FROM line.charge_amount
                   OR allocation.allocated_tax_amount IS DISTINCT FROM line.tax_amount
                   OR allocation.allocated_gross_amount
                      IS DISTINCT FROM line.charge_amount + line.tax_amount
               )
        ) OR EXISTS (
            SELECT 1
              FROM deims.invoice_line_charges allocation
              LEFT JOIN deims.settlement_lines line
                ON line.settlement_id = NEW.id
               AND line.charge_id = allocation.charge_id
             WHERE allocation.invoice_id = NEW.invoice_id
               AND allocation.reversed_at IS NULL
               AND line.id IS NULL
        ) OR EXISTS (
            SELECT 1
              FROM deims.invoice_lines invoice_line
              LEFT JOIN deims.invoice_line_charges allocation
                ON allocation.invoice_line_id = invoice_line.id
               AND allocation.reversed_at IS NULL
             WHERE invoice_line.invoice_id = NEW.invoice_id
             GROUP BY invoice_line.id
            HAVING count(allocation.id) = 0
        ) THEN
            RAISE EXCEPTION 'Canonical invoice and settlement charge sets/amounts do not reconcile bidirectionally'
                USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION deims.deferred_check_settlement_line()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, deims
AS $function$
DECLARE
    line_row record;
BEGIN
    SELECT line.* INTO line_row
      FROM deims.settlement_lines line WHERE line.id = NEW.id;
    IF NOT FOUND THEN
        RETURN NULL;
    END IF;
    PERFORM 1 FROM deims.charges charge WHERE charge.id = line_row.charge_id FOR UPDATE;
    IF EXISTS (
        SELECT 1
          FROM deims.settlement_lines other_line
          JOIN deims.settlements other_settlement ON other_settlement.id = other_line.settlement_id
         WHERE other_line.charge_id = line_row.charge_id
           AND other_line.settlement_id <> line_row.settlement_id
           AND other_settlement.status NOT IN ('CANCELLED','REVERSED')
    ) THEN
        RAISE EXCEPTION 'Deferred settlement check found charge % in multiple active settlements',
            line_row.charge_id USING ERRCODE = '23505';
    END IF;
    RETURN NULL;
END;
$function$;

REVOKE ALL ON FUNCTION deims.validate_settlement_line_mutation() FROM PUBLIC;
REVOKE ALL ON FUNCTION deims.validate_settlement_commitment() FROM PUBLIC;
REVOKE ALL ON FUNCTION deims.deferred_check_settlement_line() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_finance_validate_settlement_line ON deims.settlement_lines;
CREATE TRIGGER trg_finance_validate_settlement_line
    BEFORE INSERT OR UPDATE OR DELETE ON deims.settlement_lines
    FOR EACH ROW EXECUTE PROCEDURE deims.validate_settlement_line_mutation();

DROP TRIGGER IF EXISTS trg_finance_validate_settlement_commitment ON deims.settlements;
CREATE TRIGGER trg_finance_validate_settlement_commitment
    BEFORE INSERT OR UPDATE OF status ON deims.settlements
    FOR EACH ROW EXECUTE PROCEDURE deims.validate_settlement_commitment();

DROP TRIGGER IF EXISTS trg_finance_deferred_settlement_line ON deims.settlement_lines;
CREATE CONSTRAINT TRIGGER trg_finance_deferred_settlement_line
    AFTER INSERT OR UPDATE ON deims.settlement_lines
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE PROCEDURE deims.deferred_check_settlement_line();

DROP TRIGGER IF EXISTS trg_finance_prevent_truncate ON deims.settlement_lines;
CREATE TRIGGER trg_finance_prevent_truncate
    BEFORE TRUNCATE ON deims.settlement_lines
    FOR EACH STATEMENT EXECUTE PROCEDURE deims.prevent_finance_history_truncate();
