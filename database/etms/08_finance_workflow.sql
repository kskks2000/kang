-- ETMS rating output, accrual, AP/AR invoice, Korean tax invoice, settlement, payment, accounting, and approvals.

CREATE TABLE IF NOT EXISTS etms.charges (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    charge_no varchar(120) NOT NULL,
    direction varchar(10) NOT NULL,
    stage varchar(20) NOT NULL DEFAULT 'ESTIMATE',
    charge_code_id uuid NOT NULL REFERENCES etms.charge_codes(id),
    order_id uuid REFERENCES etms.transport_orders(id),
    shipment_id uuid REFERENCES etms.shipments(id),
    shipment_leg_id uuid REFERENCES etms.shipment_legs(id),
    run_id uuid REFERENCES etms.transport_runs(id),
    run_stop_id uuid REFERENCES etms.run_stops(id),
    claim_id uuid REFERENCES etms.claims(id),
    payer_partner_id uuid NOT NULL REFERENCES etms.business_partners(id),
    payee_partner_id uuid NOT NULL REFERENCES etms.business_partners(id),
    contract_version_id uuid REFERENCES etms.rate_contract_versions(id),
    rate_rule_id uuid REFERENCES etms.rate_rules(id),
    rating_run_id uuid REFERENCES etms.rating_runs(id),
    service_date date,
    quantity numeric(20,6) NOT NULL DEFAULT 1,
    uom_code varchar(20) REFERENCES etms.units_of_measure(uom_code),
    unit_rate numeric(24,8),
    currency_code char(3) NOT NULL REFERENCES etms.currencies(currency_code),
    net_amount numeric(20,4) NOT NULL,
    tax_code_id uuid REFERENCES etms.tax_codes(id),
    tax_rate_percent numeric(9,6),
    tax_amount numeric(20,4) NOT NULL DEFAULT 0,
    gross_amount numeric(20,4) NOT NULL,
    base_currency_code char(3) REFERENCES etms.currencies(currency_code),
    exchange_rate numeric(24,12),
    exchange_rate_date date,
    exchange_rate_source varchar(80),
    base_net_amount numeric(20,4),
    base_tax_amount numeric(20,4),
    base_gross_amount numeric(20,4),
    evidence_required boolean NOT NULL DEFAULT false,
    evidence_status varchar(20) NOT NULL DEFAULT 'NOT_REQUIRED',
    approval_status varchar(20) NOT NULL DEFAULT 'NOT_REQUIRED',
    status varchar(20) NOT NULL DEFAULT 'OPEN',
    is_manual boolean NOT NULL DEFAULT false,
    is_reversal boolean NOT NULL DEFAULT false,
    reverses_charge_id uuid REFERENCES etms.charges(id),
    description text,
    calculation_trace jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_by uuid REFERENCES etms.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, charge_no),
    CONSTRAINT ck_charges_direction CHECK (direction IN ('BUY','SELL')),
    CONSTRAINT ck_charges_stage CHECK (stage IN ('ESTIMATE','PLANNED','ACCRUED','ACTUAL','INVOICED','SETTLED')),
    CONSTRAINT ck_charges_entity CHECK (order_id IS NOT NULL OR shipment_id IS NOT NULL OR shipment_leg_id IS NOT NULL OR run_id IS NOT NULL OR run_stop_id IS NOT NULL OR claim_id IS NOT NULL),
    CONSTRAINT ck_charges_parties CHECK (payer_partner_id <> payee_partner_id),
    CONSTRAINT ck_charges_amounts CHECK (quantity >= 0 AND tax_amount >= 0 AND gross_amount = net_amount + tax_amount),
    CONSTRAINT ck_charges_fx CHECK (
        (
            base_currency_code IS NULL AND exchange_rate IS NULL AND
            base_net_amount IS NULL AND base_tax_amount IS NULL AND base_gross_amount IS NULL
        ) OR (
            base_currency_code = currency_code AND
            (exchange_rate IS NULL OR exchange_rate = 1) AND
            base_net_amount = net_amount AND base_tax_amount = tax_amount AND base_gross_amount = gross_amount
        ) OR (
            base_currency_code IS NOT NULL AND base_currency_code <> currency_code AND
            exchange_rate > 0 AND exchange_rate_date IS NOT NULL AND exchange_rate_source IS NOT NULL AND
            base_net_amount IS NOT NULL AND base_tax_amount IS NOT NULL AND base_gross_amount IS NOT NULL AND
            base_gross_amount = base_net_amount + base_tax_amount
        )
    ),
    CONSTRAINT ck_charges_reversal CHECK ((is_reversal = false AND reverses_charge_id IS NULL) OR (is_reversal = true AND reverses_charge_id IS NOT NULL AND reverses_charge_id <> id))
);

CREATE TABLE IF NOT EXISTS etms.charge_allocations (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    charge_id uuid NOT NULL REFERENCES etms.charges(id) ON DELETE CASCADE,
    allocation_type varchar(30) NOT NULL,
    order_id uuid REFERENCES etms.transport_orders(id),
    shipment_id uuid REFERENCES etms.shipments(id),
    shipment_leg_id uuid REFERENCES etms.shipment_legs(id),
    run_id uuid REFERENCES etms.transport_runs(id),
    order_line_id uuid REFERENCES etms.transport_order_lines(id),
    cost_center_id uuid REFERENCES etms.cost_centers(id),
    allocation_percent numeric(9,6),
    allocated_net_amount numeric(20,4) NOT NULL,
    allocated_tax_amount numeric(20,4) NOT NULL DEFAULT 0,
    allocated_gross_amount numeric(20,4) NOT NULL,
    allocation_basis numeric(24,8),
    allocation_basis_uom varchar(30),
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_charge_allocation_target CHECK ((order_id IS NOT NULL)::int + (shipment_id IS NOT NULL)::int + (shipment_leg_id IS NOT NULL)::int + (run_id IS NOT NULL)::int + (order_line_id IS NOT NULL)::int + (cost_center_id IS NOT NULL)::int >= 1),
    CONSTRAINT ck_charge_allocation_percent CHECK (allocation_percent IS NULL OR allocation_percent BETWEEN 0 AND 100),
    CONSTRAINT ck_charge_allocation_amounts CHECK (allocated_gross_amount = allocated_net_amount + allocated_tax_amount)
);

CREATE TABLE IF NOT EXISTS etms.charge_adjustments (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    charge_id uuid NOT NULL REFERENCES etms.charges(id),
    adjustment_no integer NOT NULL,
    adjustment_type varchar(30) NOT NULL,
    reason_code varchar(80) NOT NULL,
    reason_text text,
    net_amount_delta numeric(20,4) NOT NULL,
    tax_amount_delta numeric(20,4) NOT NULL DEFAULT 0,
    gross_amount_delta numeric(20,4) NOT NULL,
    requested_by uuid REFERENCES etms.users(id),
    requested_at timestamptz NOT NULL DEFAULT now(),
    approval_status varchar(20) NOT NULL DEFAULT 'PENDING',
    approved_by uuid REFERENCES etms.users(id),
    approved_at timestamptz,
    applied_at timestamptz,
    evidence_file_id uuid REFERENCES etms.files(id),
    UNIQUE (charge_id, adjustment_no),
    CONSTRAINT ck_charge_adjustment_no CHECK (adjustment_no > 0),
    CONSTRAINT ck_charge_adjustment_amounts CHECK (gross_amount_delta = net_amount_delta + tax_amount_delta)
);

CREATE TABLE IF NOT EXISTS etms.accruals (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    accrual_no varchar(120) NOT NULL,
    charge_id uuid NOT NULL REFERENCES etms.charges(id),
    accounting_date date NOT NULL,
    accounting_period varchar(20) NOT NULL,
    organization_id uuid NOT NULL REFERENCES etms.organizations(id),
    cost_center_id uuid REFERENCES etms.cost_centers(id),
    partner_id uuid NOT NULL REFERENCES etms.business_partners(id),
    currency_code char(3) NOT NULL REFERENCES etms.currencies(currency_code),
    accrued_amount numeric(20,4) NOT NULL,
    base_currency_code char(3) NOT NULL REFERENCES etms.currencies(currency_code),
    base_amount numeric(20,4) NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'OPEN',
    reversed_at timestamptz,
    reversal_accrual_id uuid REFERENCES etms.accruals(id),
    invoice_line_id uuid,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, accrual_no),
    CONSTRAINT ck_accrual_reversal CHECK (reversal_accrual_id IS NULL OR reversal_accrual_id <> id)
);

CREATE TABLE IF NOT EXISTS etms.invoices (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    invoice_type varchar(20) NOT NULL,
    invoice_no varchar(150) NOT NULL,
    external_invoice_no varchar(150),
    organization_id uuid NOT NULL REFERENCES etms.organizations(id),
    issuer_partner_id uuid NOT NULL REFERENCES etms.business_partners(id),
    recipient_partner_id uuid NOT NULL REFERENCES etms.business_partners(id),
    issuer_party_snapshot_id uuid NOT NULL REFERENCES etms.party_snapshots(id),
    recipient_party_snapshot_id uuid NOT NULL REFERENCES etms.party_snapshots(id),
    billing_address_snapshot_id uuid REFERENCES etms.address_snapshots(id),
    invoice_date date NOT NULL,
    service_period_from date,
    service_period_to date,
    posting_date date,
    due_date date,
    payment_term_id uuid REFERENCES etms.payment_terms(id),
    currency_code char(3) NOT NULL REFERENCES etms.currencies(currency_code),
    exchange_rate numeric(24,12),
    exchange_rate_date date,
    base_currency_code char(3) REFERENCES etms.currencies(currency_code),
    net_amount numeric(20,4) NOT NULL DEFAULT 0,
    tax_amount numeric(20,4) NOT NULL DEFAULT 0,
    gross_amount numeric(20,4) NOT NULL DEFAULT 0,
    paid_amount numeric(20,4) NOT NULL DEFAULT 0,
    outstanding_amount numeric(20,4) NOT NULL DEFAULT 0,
    status varchar(30) NOT NULL DEFAULT 'DRAFT',
    match_status varchar(20) NOT NULL DEFAULT 'NOT_MATCHED',
    approval_status varchar(20) NOT NULL DEFAULT 'NOT_REQUIRED',
    tax_invoice_required boolean NOT NULL DEFAULT false,
    source_system_id uuid REFERENCES etms.external_systems(id),
    source_document_id varchar(200),
    original_invoice_id uuid REFERENCES etms.invoices(id),
    correction_reason text,
    posted_at timestamptz,
    cancelled_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_by uuid REFERENCES etms.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, invoice_type, invoice_no),
    UNIQUE (tenant_id, source_system_id, source_document_id),
    CONSTRAINT ck_invoices_type CHECK (invoice_type IN ('PAYABLE','RECEIVABLE','CREDIT_NOTE','DEBIT_NOTE')),
    CONSTRAINT ck_invoices_parties CHECK (issuer_partner_id <> recipient_partner_id),
    CONSTRAINT ck_invoices_service_period CHECK (service_period_to IS NULL OR service_period_from IS NULL OR service_period_to >= service_period_from),
    CONSTRAINT ck_invoices_due CHECK (due_date IS NULL OR due_date >= invoice_date),
    CONSTRAINT ck_invoices_status CHECK (status IN ('DRAFT','RECEIVED','VALIDATING','REJECTED','APPROVED','POSTED','PARTIALLY_PAID','PAID','CANCELLED')),
    CONSTRAINT ck_invoices_match_status CHECK (match_status IN ('NOT_MATCHED','MATCHING','PARTIAL','MATCHED','EXCEPTION')),
    CONSTRAINT ck_invoices_amounts CHECK (
        net_amount >= 0 AND tax_amount >= 0 AND gross_amount >= 0 AND
        gross_amount = net_amount + tax_amount AND
        paid_amount >= 0 AND paid_amount <= gross_amount AND
        outstanding_amount = gross_amount - paid_amount
    ),
    CONSTRAINT ck_invoices_original CHECK (original_invoice_id IS NULL OR original_invoice_id <> id)
);

CREATE TABLE IF NOT EXISTS etms.invoice_lines (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    invoice_id uuid NOT NULL REFERENCES etms.invoices(id) ON DELETE CASCADE,
    line_no integer NOT NULL,
    charge_code_id uuid REFERENCES etms.charge_codes(id),
    description text NOT NULL,
    service_date date,
    quantity numeric(20,6) NOT NULL DEFAULT 1,
    uom_code varchar(20) REFERENCES etms.units_of_measure(uom_code),
    unit_price numeric(24,8),
    net_amount numeric(20,4) NOT NULL,
    discount_amount numeric(20,4) NOT NULL DEFAULT 0,
    tax_code_id uuid REFERENCES etms.tax_codes(id),
    tax_rate_percent numeric(9,6),
    tax_amount numeric(20,4) NOT NULL DEFAULT 0,
    gross_amount numeric(20,4) NOT NULL,
    cost_center_id uuid REFERENCES etms.cost_centers(id),
    gl_account_code varchar(50),
    match_status varchar(20) NOT NULL DEFAULT 'NOT_MATCHED',
    status varchar(20) NOT NULL DEFAULT 'OPEN',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (invoice_id, line_no),
    CONSTRAINT ck_invoice_line_no CHECK (line_no > 0),
    CONSTRAINT ck_invoice_line_qty CHECK (quantity >= 0),
    CONSTRAINT ck_invoice_line_amounts CHECK (
        net_amount >= 0 AND tax_amount >= 0 AND gross_amount >= 0 AND
        discount_amount >= 0 AND discount_amount <= net_amount AND
        gross_amount = net_amount - discount_amount + tax_amount
    )
);

DO $block$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'etms.accruals'::regclass
          AND conname = 'fk_accruals_invoice_line'
    ) THEN
        ALTER TABLE etms.accruals
            ADD CONSTRAINT fk_accruals_invoice_line FOREIGN KEY (invoice_line_id)
            REFERENCES etms.invoice_lines(id) ON DELETE SET NULL;
    END IF;
END;
$block$;

CREATE TABLE IF NOT EXISTS etms.invoice_line_charges (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    invoice_line_id uuid NOT NULL REFERENCES etms.invoice_lines(id) ON DELETE CASCADE,
    charge_id uuid NOT NULL REFERENCES etms.charges(id),
    allocated_net_amount numeric(20,4) NOT NULL,
    allocated_tax_amount numeric(20,4) NOT NULL DEFAULT 0,
    allocated_gross_amount numeric(20,4) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (invoice_line_id, charge_id),
    CONSTRAINT ck_invoice_line_charge_amounts CHECK (allocated_gross_amount = allocated_net_amount + allocated_tax_amount)
);

CREATE TABLE IF NOT EXISTS etms.invoice_taxes (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    invoice_id uuid NOT NULL REFERENCES etms.invoices(id) ON DELETE CASCADE,
    tax_code_id uuid NOT NULL REFERENCES etms.tax_codes(id),
    tax_rate_percent numeric(9,6) NOT NULL,
    taxable_amount numeric(20,4) NOT NULL,
    tax_amount numeric(20,4) NOT NULL,
    recoverable_amount numeric(20,4) NOT NULL DEFAULT 0,
    jurisdiction_code varchar(80),
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_invoice_tax_values CHECK (taxable_amount >= 0 AND tax_amount >= 0 AND recoverable_amount >= 0)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_invoice_taxes_scope
    ON etms.invoice_taxes (
        invoice_id, tax_code_id, tax_rate_percent, COALESCE(jurisdiction_code, '')
    );

CREATE TABLE IF NOT EXISTS etms.invoice_match_results (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    invoice_id uuid NOT NULL REFERENCES etms.invoices(id) ON DELETE CASCADE,
    invoice_line_id uuid REFERENCES etms.invoice_lines(id) ON DELETE CASCADE,
    match_type varchar(30) NOT NULL,
    matched_entity_type varchar(30),
    matched_entity_id uuid,
    expected_amount numeric(20,4),
    invoiced_amount numeric(20,4),
    variance_amount numeric(20,4),
    variance_percent numeric(12,6),
    tolerance_amount numeric(20,4),
    tolerance_percent numeric(12,6),
    result_status varchar(20) NOT NULL,
    reason_code varchar(80),
    match_details jsonb NOT NULL DEFAULT '{}'::jsonb,
    matched_at timestamptz NOT NULL DEFAULT now(),
    matched_by uuid REFERENCES etms.users(id),
    CONSTRAINT ck_invoice_match_entity CHECK (invoice_line_id IS NOT NULL OR matched_entity_id IS NOT NULL)
);

CREATE TABLE IF NOT EXISTS etms.invoice_disputes (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    dispute_no varchar(100) NOT NULL,
    invoice_id uuid NOT NULL REFERENCES etms.invoices(id),
    invoice_line_id uuid REFERENCES etms.invoice_lines(id),
    raised_by_partner_id uuid REFERENCES etms.business_partners(id),
    disputed_partner_id uuid REFERENCES etms.business_partners(id),
    dispute_type varchar(50) NOT NULL,
    disputed_amount numeric(20,4) NOT NULL,
    currency_code char(3) NOT NULL REFERENCES etms.currencies(currency_code),
    reason text NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'OPEN',
    assigned_to uuid REFERENCES etms.users(id),
    raised_at timestamptz NOT NULL DEFAULT now(),
    response_due_at timestamptz,
    resolved_at timestamptz,
    resolution_type varchar(30),
    resolution_amount numeric(20,4),
    resolution_notes text,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, dispute_no),
    CONSTRAINT ck_invoice_dispute_amount CHECK (disputed_amount >= 0 AND (resolution_amount IS NULL OR resolution_amount >= 0)),
    CONSTRAINT ck_invoice_dispute_dates CHECK (resolved_at IS NULL OR resolved_at >= raised_at)
);

CREATE TABLE IF NOT EXISTS etms.invoice_dispute_events (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    dispute_id uuid NOT NULL REFERENCES etms.invoice_disputes(id) ON DELETE CASCADE,
    event_type varchar(50) NOT NULL,
    from_status varchar(20),
    to_status varchar(20),
    comments text,
    amount numeric(20,4),
    actor_user_id uuid REFERENCES etms.users(id),
    actor_partner_id uuid REFERENCES etms.business_partners(id),
    file_id uuid REFERENCES etms.files(id),
    occurred_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS etms.invoice_status_history (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    invoice_id uuid NOT NULL REFERENCES etms.invoices(id) ON DELETE CASCADE,
    from_status varchar(30),
    to_status varchar(30) NOT NULL,
    reason_code varchar(80),
    reason_text text,
    changed_by uuid REFERENCES etms.users(id),
    occurred_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS etms.tax_invoices (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    tax_invoice_no varchar(150) NOT NULL,
    nts_approval_no varchar(100),
    tax_invoice_type varchar(30) NOT NULL DEFAULT 'GENERAL',
    direction varchar(10) NOT NULL,
    organization_id uuid NOT NULL REFERENCES etms.organizations(id),
    supplier_partner_id uuid NOT NULL REFERENCES etms.business_partners(id),
    buyer_partner_id uuid NOT NULL REFERENCES etms.business_partners(id),
    supplier_snapshot_id uuid NOT NULL REFERENCES etms.party_snapshots(id),
    buyer_snapshot_id uuid NOT NULL REFERENCES etms.party_snapshots(id),
    issue_date date NOT NULL,
    supply_date date NOT NULL,
    currency_code char(3) NOT NULL DEFAULT 'KRW' REFERENCES etms.currencies(currency_code),
    supply_amount numeric(20,4) NOT NULL,
    tax_amount numeric(20,4) NOT NULL,
    total_amount numeric(20,4) NOT NULL,
    cash_amount numeric(20,4) NOT NULL DEFAULT 0,
    check_amount numeric(20,4) NOT NULL DEFAULT 0,
    bill_amount numeric(20,4) NOT NULL DEFAULT 0,
    credit_amount numeric(20,4) NOT NULL DEFAULT 0,
    purpose_code varchar(20),
    original_tax_invoice_id uuid REFERENCES etms.tax_invoices(id),
    correction_reason_code varchar(30),
    nts_status varchar(30) NOT NULL DEFAULT 'DRAFT',
    issued_at timestamptz,
    transmitted_at timestamptz,
    accepted_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, tax_invoice_no),
    UNIQUE (tenant_id, nts_approval_no),
    CONSTRAINT ck_tax_invoice_direction CHECK (direction IN ('SALES','PURCHASE')),
    CONSTRAINT ck_tax_invoice_status CHECK (nts_status IN ('DRAFT','VALIDATING','REJECTED','ISSUED','TRANSMITTED','ACCEPTED','CANCELLED','CORRECTED')),
    CONSTRAINT ck_tax_invoice_parties CHECK (supplier_partner_id <> buyer_partner_id),
    CONSTRAINT ck_tax_invoice_amounts CHECK (total_amount = supply_amount + tax_amount AND cash_amount >= 0 AND check_amount >= 0 AND bill_amount >= 0 AND credit_amount >= 0),
    CONSTRAINT ck_tax_invoice_original CHECK (original_tax_invoice_id IS NULL OR original_tax_invoice_id <> id)
);

CREATE TABLE IF NOT EXISTS etms.tax_invoice_lines (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tax_invoice_id uuid NOT NULL REFERENCES etms.tax_invoices(id) ON DELETE CASCADE,
    line_no integer NOT NULL,
    invoice_id uuid REFERENCES etms.invoices(id),
    invoice_line_id uuid REFERENCES etms.invoice_lines(id),
    supply_date date,
    item_name varchar(300) NOT NULL,
    specification varchar(200),
    quantity numeric(20,6),
    unit_price numeric(24,8),
    supply_amount numeric(20,4) NOT NULL,
    tax_amount numeric(20,4) NOT NULL,
    remark varchar(500),
    UNIQUE (tax_invoice_id, line_no),
    CONSTRAINT ck_tax_invoice_line_no CHECK (line_no > 0)
);

CREATE TABLE IF NOT EXISTS etms.tax_invoice_events (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tax_invoice_id uuid NOT NULL REFERENCES etms.tax_invoices(id) ON DELETE CASCADE,
    event_type varchar(50) NOT NULL,
    from_status varchar(30),
    to_status varchar(30),
    nts_response_code varchar(100),
    nts_response_message_masked text,
    external_message_id varchar(200),
    occurred_at timestamptz NOT NULL DEFAULT now(),
    payload_hash char(64)
);

CREATE TABLE IF NOT EXISTS etms.settlement_batches (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    batch_no varchar(100) NOT NULL,
    settlement_type varchar(20) NOT NULL,
    organization_id uuid NOT NULL REFERENCES etms.organizations(id),
    period_from date NOT NULL,
    period_to date NOT NULL,
    cutoff_at timestamptz,
    currency_code char(3) REFERENCES etms.currencies(currency_code),
    status varchar(20) NOT NULL DEFAULT 'OPEN',
    item_count integer NOT NULL DEFAULT 0,
    total_amount numeric(20,4) NOT NULL DEFAULT 0,
    created_by uuid REFERENCES etms.users(id),
    closed_by uuid REFERENCES etms.users(id),
    closed_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, batch_no),
    CONSTRAINT ck_settlement_batch_type CHECK (settlement_type IN ('CARRIER','CUSTOMER','DRIVER','CLAIM','INTERCOMPANY')),
    CONSTRAINT ck_settlement_batch_dates CHECK (period_to >= period_from),
    CONSTRAINT ck_settlement_batch_count CHECK (item_count >= 0)
);

CREATE TABLE IF NOT EXISTS etms.settlements (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    settlement_no varchar(120) NOT NULL,
    batch_id uuid REFERENCES etms.settlement_batches(id),
    settlement_type varchar(20) NOT NULL,
    partner_id uuid NOT NULL REFERENCES etms.business_partners(id),
    organization_id uuid NOT NULL REFERENCES etms.organizations(id),
    period_from date NOT NULL,
    period_to date NOT NULL,
    settlement_date date,
    currency_code char(3) NOT NULL REFERENCES etms.currencies(currency_code),
    gross_amount numeric(20,4) NOT NULL DEFAULT 0,
    deduction_amount numeric(20,4) NOT NULL DEFAULT 0,
    tax_amount numeric(20,4) NOT NULL DEFAULT 0,
    net_payable_amount numeric(20,4) NOT NULL DEFAULT 0,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    approved_by uuid REFERENCES etms.users(id),
    approved_at timestamptz,
    invoice_id uuid REFERENCES etms.invoices(id),
    statement_file_id uuid REFERENCES etms.files(id),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, settlement_no),
    CONSTRAINT ck_settlement_dates CHECK (period_to >= period_from),
    CONSTRAINT ck_settlement_status CHECK (status IN ('DRAFT','OPEN','CALCULATING','REJECTED','APPROVED','INVOICED','PARTIALLY_PAID','PAID','CANCELLED')),
    CONSTRAINT ck_settlement_amounts CHECK (
        gross_amount >= 0 AND deduction_amount >= 0 AND tax_amount >= 0 AND
        net_payable_amount = gross_amount - deduction_amount + tax_amount
    )
);

CREATE TABLE IF NOT EXISTS etms.settlement_lines (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    settlement_id uuid NOT NULL REFERENCES etms.settlements(id) ON DELETE CASCADE,
    line_no integer NOT NULL,
    line_type varchar(30) NOT NULL,
    charge_id uuid REFERENCES etms.charges(id),
    invoice_line_id uuid REFERENCES etms.invoice_lines(id),
    claim_settlement_id uuid REFERENCES etms.claim_settlements(id),
    description text NOT NULL,
    gross_amount numeric(20,4) NOT NULL,
    deduction_amount numeric(20,4) NOT NULL DEFAULT 0,
    tax_amount numeric(20,4) NOT NULL DEFAULT 0,
    net_amount numeric(20,4) NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'OPEN',
    UNIQUE (settlement_id, line_no),
    CONSTRAINT ck_settlement_line_no CHECK (line_no > 0),
    CONSTRAINT ck_settlement_line_source CHECK (charge_id IS NOT NULL OR invoice_line_id IS NOT NULL OR claim_settlement_id IS NOT NULL),
    CONSTRAINT ck_settlement_line_amounts CHECK (
        gross_amount >= 0 AND deduction_amount >= 0 AND tax_amount >= 0 AND
        net_amount = gross_amount - deduction_amount + tax_amount
    )
);

CREATE TABLE IF NOT EXISTS etms.payments (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    payment_no varchar(120) NOT NULL,
    payment_type varchar(20) NOT NULL,
    organization_id uuid NOT NULL REFERENCES etms.organizations(id),
    payer_partner_id uuid NOT NULL REFERENCES etms.business_partners(id),
    payee_partner_id uuid NOT NULL REFERENCES etms.business_partners(id),
    payment_method varchar(30) NOT NULL,
    payment_date date NOT NULL,
    value_date date,
    currency_code char(3) NOT NULL REFERENCES etms.currencies(currency_code),
    payment_amount numeric(20,4) NOT NULL,
    bank_fee_amount numeric(20,4) NOT NULL DEFAULT 0,
    exchange_rate numeric(24,12),
    bank_reference varchar(200),
    bank_account_token_hash char(64),
    status varchar(20) NOT NULL DEFAULT 'PENDING',
    returned_at timestamptz,
    return_reason text,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, payment_no),
    CONSTRAINT ck_payment_type CHECK (payment_type IN ('OUTBOUND','INBOUND','REFUND','OFFSET')),
    CONSTRAINT ck_payment_parties CHECK (payer_partner_id <> payee_partner_id),
    CONSTRAINT ck_payment_amounts CHECK (payment_amount > 0 AND bank_fee_amount >= 0)
);

CREATE TABLE IF NOT EXISTS etms.payment_applications (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    payment_id uuid NOT NULL REFERENCES etms.payments(id) ON DELETE CASCADE,
    invoice_id uuid REFERENCES etms.invoices(id),
    settlement_id uuid REFERENCES etms.settlements(id),
    claim_settlement_id uuid REFERENCES etms.claim_settlements(id),
    applied_amount numeric(20,4) NOT NULL,
    discount_taken numeric(20,4) NOT NULL DEFAULT 0,
    writeoff_amount numeric(20,4) NOT NULL DEFAULT 0,
    applied_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid REFERENCES etms.users(id),
    CONSTRAINT ck_payment_application_target CHECK ((invoice_id IS NOT NULL)::int + (settlement_id IS NOT NULL)::int + (claim_settlement_id IS NOT NULL)::int = 1),
    CONSTRAINT ck_payment_application_amount CHECK (applied_amount > 0 AND discount_taken >= 0 AND writeoff_amount >= 0)
);

CREATE TABLE IF NOT EXISTS etms.accounting_periods (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    organization_id uuid NOT NULL REFERENCES etms.organizations(id),
    fiscal_year integer NOT NULL,
    period_no integer NOT NULL,
    period_name varchar(50) NOT NULL,
    starts_on date NOT NULL,
    ends_on date NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'OPEN',
    soft_closed_at timestamptz,
    hard_closed_at timestamptz,
    closed_by uuid REFERENCES etms.users(id),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, organization_id, fiscal_year, period_no),
    CONSTRAINT ck_accounting_period_no CHECK (period_no BETWEEN 1 AND 99),
    CONSTRAINT ck_accounting_period_dates CHECK (ends_on >= starts_on),
    CONSTRAINT ck_accounting_period_status CHECK (status IN ('FUTURE','OPEN','SOFT_CLOSED','HARD_CLOSED'))
);

CREATE TABLE IF NOT EXISTS etms.gl_accounts (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    organization_id uuid NOT NULL REFERENCES etms.organizations(id),
    account_code varchar(50) NOT NULL,
    account_name varchar(200) NOT NULL,
    account_type varchar(30) NOT NULL,
    parent_account_id uuid REFERENCES etms.gl_accounts(id),
    currency_code char(3) REFERENCES etms.currencies(currency_code),
    reconciliation_required boolean NOT NULL DEFAULT false,
    valid_from date,
    valid_to date,
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, organization_id, account_code),
    CONSTRAINT ck_gl_account_parent CHECK (parent_account_id IS NULL OR parent_account_id <> id),
    CONSTRAINT ck_gl_account_dates CHECK (valid_to IS NULL OR valid_from IS NULL OR valid_to >= valid_from)
);

CREATE TABLE IF NOT EXISTS etms.journal_batches (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    batch_no varchar(100) NOT NULL,
    organization_id uuid NOT NULL REFERENCES etms.organizations(id),
    accounting_period_id uuid NOT NULL REFERENCES etms.accounting_periods(id),
    source_code varchar(50) NOT NULL DEFAULT 'ETMS',
    batch_type varchar(30) NOT NULL,
    accounting_date date NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    total_debit numeric(20,4) NOT NULL DEFAULT 0,
    total_credit numeric(20,4) NOT NULL DEFAULT 0,
    posted_at timestamptz,
    posted_by uuid REFERENCES etms.users(id),
    reversal_of_batch_id uuid REFERENCES etms.journal_batches(id),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, batch_no),
    CONSTRAINT ck_journal_batch_balance CHECK (
        total_debit >= 0 AND total_credit >= 0 AND
        (status <> 'POSTED' OR total_debit = total_credit)
    ),
    CONSTRAINT ck_journal_batch_status CHECK (status IN ('DRAFT','APPROVED','POSTED','REVERSED','CANCELLED')),
    CONSTRAINT ck_journal_batch_reversal CHECK (reversal_of_batch_id IS NULL OR reversal_of_batch_id <> id)
);

CREATE TABLE IF NOT EXISTS etms.journal_entries (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    journal_batch_id uuid NOT NULL REFERENCES etms.journal_batches(id) ON DELETE CASCADE,
    entry_no integer NOT NULL,
    source_entity_type varchar(30) NOT NULL,
    source_entity_id uuid NOT NULL,
    description text,
    currency_code char(3) NOT NULL REFERENCES etms.currencies(currency_code),
    exchange_rate numeric(24,12),
    entry_date date NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    UNIQUE (journal_batch_id, entry_no),
    CONSTRAINT ck_journal_entry_no CHECK (entry_no > 0),
    CONSTRAINT ck_journal_entry_status CHECK (status IN ('DRAFT','POSTED','REVERSED'))
);

CREATE TABLE IF NOT EXISTS etms.journal_lines (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    journal_entry_id uuid NOT NULL REFERENCES etms.journal_entries(id) ON DELETE CASCADE,
    line_no integer NOT NULL,
    gl_account_id uuid NOT NULL REFERENCES etms.gl_accounts(id),
    cost_center_id uuid REFERENCES etms.cost_centers(id),
    partner_id uuid REFERENCES etms.business_partners(id),
    debit_amount numeric(20,4) NOT NULL DEFAULT 0,
    credit_amount numeric(20,4) NOT NULL DEFAULT 0,
    base_debit_amount numeric(20,4) NOT NULL DEFAULT 0,
    base_credit_amount numeric(20,4) NOT NULL DEFAULT 0,
    description text,
    reference_no varchar(150),
    UNIQUE (journal_entry_id, line_no),
    CONSTRAINT ck_journal_line_no CHECK (line_no > 0),
    CONSTRAINT ck_journal_line_side CHECK ((debit_amount > 0 AND credit_amount = 0) OR (credit_amount > 0 AND debit_amount = 0)),
    CONSTRAINT ck_journal_line_base_side CHECK ((base_debit_amount > 0 AND base_credit_amount = 0) OR (base_credit_amount > 0 AND base_debit_amount = 0))
);

CREATE TABLE IF NOT EXISTS etms.accounting_exports (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    export_no varchar(100) NOT NULL,
    external_system_id uuid NOT NULL REFERENCES etms.external_systems(id),
    organization_id uuid NOT NULL REFERENCES etms.organizations(id),
    accounting_period_id uuid REFERENCES etms.accounting_periods(id),
    export_type varchar(30) NOT NULL,
    record_count integer NOT NULL DEFAULT 0,
    total_amount numeric(20,4),
    status varchar(20) NOT NULL DEFAULT 'QUEUED',
    file_id uuid REFERENCES etms.files(id),
    requested_at timestamptz NOT NULL DEFAULT now(),
    completed_at timestamptz,
    external_batch_id varchar(200),
    error_detail_masked text,
    created_by uuid REFERENCES etms.users(id),
    UNIQUE (tenant_id, export_no),
    CONSTRAINT ck_accounting_export_count CHECK (record_count >= 0)
);

CREATE TABLE IF NOT EXISTS etms.cost_allocations (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    source_entity_type varchar(30) NOT NULL,
    source_entity_id uuid NOT NULL,
    allocation_rule_code varchar(80),
    target_cost_center_id uuid NOT NULL REFERENCES etms.cost_centers(id),
    allocation_percent numeric(9,6),
    allocated_amount numeric(20,4) NOT NULL,
    currency_code char(3) NOT NULL REFERENCES etms.currencies(currency_code),
    accounting_date date NOT NULL,
    journal_line_id uuid REFERENCES etms.journal_lines(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_cost_allocation_percent CHECK (allocation_percent IS NULL OR allocation_percent BETWEEN 0 AND 100)
);

CREATE TABLE IF NOT EXISTS etms.workflow_definitions (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
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

CREATE TABLE IF NOT EXISTS etms.workflow_versions (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    workflow_definition_id uuid NOT NULL REFERENCES etms.workflow_definitions(id) ON DELETE CASCADE,
    version_no integer NOT NULL,
    effective_from timestamptz NOT NULL,
    effective_to timestamptz,
    trigger_conditions jsonb NOT NULL DEFAULT '{}'::jsonb,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    published_by uuid REFERENCES etms.users(id),
    published_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (workflow_definition_id, version_no),
    CONSTRAINT ck_workflow_version_no CHECK (version_no > 0),
    CONSTRAINT ck_workflow_version_dates CHECK (effective_to IS NULL OR effective_to > effective_from)
);

CREATE TABLE IF NOT EXISTS etms.workflow_steps (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    workflow_version_id uuid NOT NULL REFERENCES etms.workflow_versions(id) ON DELETE CASCADE,
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
    UNIQUE (workflow_version_id, step_code),
    UNIQUE (workflow_version_id, sequence_no),
    CONSTRAINT ck_workflow_step_sequence CHECK (sequence_no > 0),
    CONSTRAINT ck_workflow_step_type CHECK (step_type IN ('APPROVAL','REVIEW','TASK','AUTOMATION','NOTIFICATION','GATE'))
);

CREATE TABLE IF NOT EXISTS etms.workflow_instances (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    workflow_version_id uuid NOT NULL REFERENCES etms.workflow_versions(id),
    entity_type varchar(80) NOT NULL,
    entity_id uuid NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'RUNNING',
    current_step_id uuid REFERENCES etms.workflow_steps(id),
    started_at timestamptz NOT NULL DEFAULT now(),
    completed_at timestamptz,
    cancelled_at timestamptz,
    context jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_by uuid REFERENCES etms.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS etms.workflow_tasks (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    workflow_instance_id uuid NOT NULL REFERENCES etms.workflow_instances(id) ON DELETE CASCADE,
    workflow_step_id uuid NOT NULL REFERENCES etms.workflow_steps(id),
    task_no integer NOT NULL,
    assignee_user_id uuid REFERENCES etms.users(id),
    assignee_group_id uuid REFERENCES etms.user_groups(id),
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
    CONSTRAINT ck_workflow_task_assignee CHECK (assignee_user_id IS NOT NULL OR assignee_group_id IS NOT NULL)
);

CREATE TABLE IF NOT EXISTS etms.approval_policies (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
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

CREATE TABLE IF NOT EXISTS etms.approval_requests (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    request_no varchar(100) NOT NULL,
    policy_id uuid REFERENCES etms.approval_policies(id),
    workflow_instance_id uuid REFERENCES etms.workflow_instances(id),
    entity_type varchar(80) NOT NULL,
    entity_id uuid NOT NULL,
    amount numeric(20,4),
    currency_code char(3) REFERENCES etms.currencies(currency_code),
    reason text,
    status varchar(20) NOT NULL DEFAULT 'PENDING',
    requested_by uuid NOT NULL REFERENCES etms.users(id),
    requested_at timestamptz NOT NULL DEFAULT now(),
    completed_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, request_no)
);

CREATE TABLE IF NOT EXISTS etms.approval_steps (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    approval_request_id uuid NOT NULL REFERENCES etms.approval_requests(id) ON DELETE CASCADE,
    level_no integer NOT NULL,
    approver_user_id uuid REFERENCES etms.users(id),
    approver_group_id uuid REFERENCES etms.user_groups(id),
    status varchar(20) NOT NULL DEFAULT 'PENDING',
    assigned_at timestamptz NOT NULL DEFAULT now(),
    due_at timestamptz,
    decided_at timestamptz,
    decision varchar(20),
    comments text,
    delegated_from_user_id uuid REFERENCES etms.users(id),
    CONSTRAINT ck_approval_step_level CHECK (level_no > 0),
    CONSTRAINT ck_approval_step_approver CHECK ((approver_user_id IS NOT NULL)::int + (approver_group_id IS NOT NULL)::int = 1)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_approval_steps_user
    ON etms.approval_steps (approval_request_id, level_no, approver_user_id)
    WHERE approver_user_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS ux_approval_steps_group
    ON etms.approval_steps (approval_request_id, level_no, approver_group_id)
    WHERE approver_group_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS etms.approval_actions (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    approval_step_id uuid NOT NULL REFERENCES etms.approval_steps(id) ON DELETE CASCADE,
    action_type varchar(20) NOT NULL,
    actor_user_id uuid NOT NULL REFERENCES etms.users(id),
    comments text,
    ip_address inet,
    user_agent text,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_approval_action_type CHECK (action_type IN ('APPROVE','REJECT','RETURN','DELEGATE','ESCALATE','CANCEL','COMMENT'))
);
