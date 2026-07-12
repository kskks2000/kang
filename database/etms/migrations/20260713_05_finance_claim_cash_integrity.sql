-- ETMS forward migration: finance, claim, cash, and accounting integrity.
-- PostgreSQL 11 compatible. This migration is intentionally idempotent.

-- ---------------------------------------------------------------------------
-- Posted journal linkage for finalized financial documents.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS etms.financial_journal_links (
    id uuid PRIMARY KEY DEFAULT etms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES etms.tenants(id),
    financial_entity_type varchar(40) NOT NULL,
    financial_entity_id uuid NOT NULL,
    journal_entry_id uuid NOT NULL,
    link_role varchar(20) NOT NULL DEFAULT 'POSTING',
    linked_amount numeric(20,4) NOT NULL,
    currency_code char(3) NOT NULL REFERENCES etms.currencies(currency_code),
    link_reason text,
    linked_by_user_id uuid REFERENCES etms.users(id),
    linked_at timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fk_financial_journal_link_entry_tenant
        FOREIGN KEY (tenant_id, journal_entry_id)
        REFERENCES etms.journal_entries(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT uq_financial_journal_link
        UNIQUE (tenant_id, financial_entity_type, financial_entity_id, journal_entry_id, link_role),
    CONSTRAINT ck_financial_journal_link_entity_type CHECK (
        financial_entity_type IN (
            'INVOICE','TAX_INVOICE','SETTLEMENT','CREDIT_NOTE','DEBIT_NOTE',
            'DRIVER_SETTLEMENT','OWNER_OPERATOR_SETTLEMENT','BANK_STATEMENT',
            'BANK_RECONCILIATION','CLAIM_SETTLEMENT','COD_COLLECTION'
        )
    ),
    CONSTRAINT ck_financial_journal_link_role CHECK (
        link_role IN ('POSTING','REVERSAL','ADJUSTMENT')
    ),
    CONSTRAINT ck_financial_journal_link_amount CHECK (linked_amount > 0)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_financial_journal_links_tenant_id
    ON etms.financial_journal_links (tenant_id, id);
CREATE INDEX IF NOT EXISTS ix_financial_journal_links_entity
    ON etms.financial_journal_links (
        tenant_id, financial_entity_type, financial_entity_id, link_role
    );
CREATE INDEX IF NOT EXISTS ix_financial_journal_links_entry
    ON etms.financial_journal_links (tenant_id, journal_entry_id);
CREATE INDEX IF NOT EXISTS ix_financial_journal_links_currency
    ON etms.financial_journal_links (currency_code);
CREATE INDEX IF NOT EXISTS ix_financial_journal_links_linked_by
    ON etms.financial_journal_links (linked_by_user_id);
CREATE UNIQUE INDEX IF NOT EXISTS ux_financial_journal_links_posting_entry
    ON etms.financial_journal_links (tenant_id, journal_entry_id)
    WHERE link_role = 'POSTING';

ALTER TABLE etms.financial_journal_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE etms.financial_journal_links FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_select ON etms.financial_journal_links;
DROP POLICY IF EXISTS tenant_modify ON etms.financial_journal_links;
CREATE POLICY tenant_select ON etms.financial_journal_links
    FOR SELECT USING (tenant_id = etms.current_tenant_id());
CREATE POLICY tenant_modify ON etms.financial_journal_links
    FOR ALL
    USING (tenant_id = etms.current_tenant_id())
    WITH CHECK (tenant_id = etms.current_tenant_id());

DROP TRIGGER IF EXISTS trg_prevent_tenant_change
    ON etms.financial_journal_links;
CREATE TRIGGER trg_prevent_tenant_change
    BEFORE UPDATE OF tenant_id ON etms.financial_journal_links
    FOR EACH ROW EXECUTE PROCEDURE etms.prevent_tenant_change();

CREATE OR REPLACE FUNCTION etms.validate_financial_journal_link()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    entity_tenant_id uuid;
    entity_organization_id uuid;
    entity_currency_code char(3);
    entry_tenant_id uuid;
    entry_status text;
    entry_currency_code char(3);
    entry_source_type text;
    entry_source_id uuid;
    expected_source_types text[];
    batch_tenant_id uuid;
    batch_organization_id uuid;
    batch_status text;
    entry_debit_total numeric(30,4);
    allocated_total numeric(30,4);
BEGIN
    IF NEW.financial_entity_type = 'INVOICE' THEN
        SELECT tenant_id, organization_id, currency_code
          INTO entity_tenant_id, entity_organization_id, entity_currency_code
          FROM etms.invoices WHERE id = NEW.financial_entity_id;
    ELSIF NEW.financial_entity_type = 'TAX_INVOICE' THEN
        SELECT tenant_id, organization_id, currency_code
          INTO entity_tenant_id, entity_organization_id, entity_currency_code
          FROM etms.tax_invoices WHERE id = NEW.financial_entity_id;
    ELSIF NEW.financial_entity_type = 'SETTLEMENT' THEN
        SELECT tenant_id, organization_id, currency_code
          INTO entity_tenant_id, entity_organization_id, entity_currency_code
          FROM etms.settlements WHERE id = NEW.financial_entity_id;
    ELSIF NEW.financial_entity_type = 'CREDIT_NOTE' THEN
        SELECT note.tenant_id, invoice_row.organization_id, note.currency_code
          INTO entity_tenant_id, entity_organization_id, entity_currency_code
          FROM etms.credit_notes note
          LEFT JOIN etms.invoices invoice_row ON invoice_row.id = note.invoice_id
         WHERE note.id = NEW.financial_entity_id;
    ELSIF NEW.financial_entity_type = 'DEBIT_NOTE' THEN
        SELECT note.tenant_id, invoice_row.organization_id, note.currency_code
          INTO entity_tenant_id, entity_organization_id, entity_currency_code
          FROM etms.debit_notes note
          LEFT JOIN etms.invoices invoice_row ON invoice_row.id = note.invoice_id
         WHERE note.id = NEW.financial_entity_id;
    ELSIF NEW.financial_entity_type = 'DRIVER_SETTLEMENT' THEN
        SELECT tenant_id, currency_code INTO entity_tenant_id, entity_currency_code
          FROM etms.driver_settlements WHERE id = NEW.financial_entity_id;
    ELSIF NEW.financial_entity_type = 'OWNER_OPERATOR_SETTLEMENT' THEN
        SELECT tenant_id, currency_code INTO entity_tenant_id, entity_currency_code
          FROM etms.owner_operator_settlements WHERE id = NEW.financial_entity_id;
    ELSIF NEW.financial_entity_type = 'BANK_STATEMENT' THEN
        SELECT tenant_id, currency_code INTO entity_tenant_id, entity_currency_code
          FROM etms.bank_statements WHERE id = NEW.financial_entity_id;
    ELSIF NEW.financial_entity_type = 'BANK_RECONCILIATION' THEN
        SELECT tenant_id, currency_code INTO entity_tenant_id, entity_currency_code
          FROM etms.bank_reconciliation_runs WHERE id = NEW.financial_entity_id;
    ELSIF NEW.financial_entity_type = 'CLAIM_SETTLEMENT' THEN
        SELECT tenant_id, currency_code INTO entity_tenant_id, entity_currency_code
          FROM etms.claim_settlements WHERE id = NEW.financial_entity_id;
    ELSIF NEW.financial_entity_type = 'COD_COLLECTION' THEN
        SELECT tenant_id, currency_code INTO entity_tenant_id, entity_currency_code
          FROM etms.cash_on_delivery_collections WHERE id = NEW.financial_entity_id;
    END IF;

    IF entity_tenant_id IS NULL OR entity_tenant_id IS DISTINCT FROM NEW.tenant_id THEN
        RAISE EXCEPTION 'Financial journal link entity is missing or outside the tenant'
            USING ERRCODE = '23503';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtext(
        'financial-journal-entry:' || NEW.journal_entry_id::text
    ));
    SELECT entry_row.tenant_id, entry_row.status, entry_row.currency_code,
           upper(entry_row.source_entity_type), entry_row.source_entity_id,
           batch_row.tenant_id, batch_row.organization_id, batch_row.status
      INTO entry_tenant_id, entry_status, entry_currency_code,
           entry_source_type, entry_source_id,
           batch_tenant_id, batch_organization_id, batch_status
      FROM etms.journal_entries entry_row
      JOIN etms.journal_batches batch_row
        ON batch_row.id = entry_row.journal_batch_id
     WHERE entry_row.id = NEW.journal_entry_id
     FOR SHARE OF entry_row, batch_row;

    IF entry_tenant_id IS NULL
       OR entry_tenant_id IS DISTINCT FROM NEW.tenant_id
       OR batch_tenant_id IS DISTINCT FROM NEW.tenant_id THEN
        RAISE EXCEPTION 'Financial journal entry is missing or outside the tenant'
            USING ERRCODE = '23503';
    END IF;
    IF entry_status <> 'POSTED' OR batch_status <> 'POSTED' THEN
        RAISE EXCEPTION 'Financial journal links require a posted entry in a posted batch'
            USING ERRCODE = '23514';
    END IF;
    expected_source_types := CASE NEW.financial_entity_type
        WHEN 'INVOICE' THEN ARRAY['INVOICE','PAYABLE_INVOICE','RECEIVABLE_INVOICE']::text[]
        WHEN 'TAX_INVOICE' THEN ARRAY['TAX_INVOICE']::text[]
        WHEN 'SETTLEMENT' THEN ARRAY['SETTLEMENT']::text[]
        WHEN 'CREDIT_NOTE' THEN ARRAY['CREDIT_NOTE']::text[]
        WHEN 'DEBIT_NOTE' THEN ARRAY['DEBIT_NOTE']::text[]
        WHEN 'DRIVER_SETTLEMENT' THEN ARRAY['DRIVER_SETTLEMENT']::text[]
        WHEN 'OWNER_OPERATOR_SETTLEMENT' THEN ARRAY['OWNER_OPERATOR_SETTLEMENT']::text[]
        WHEN 'BANK_STATEMENT' THEN ARRAY['BANK_STATEMENT']::text[]
        WHEN 'BANK_RECONCILIATION' THEN ARRAY['BANK_RECONCILIATION']::text[]
        WHEN 'CLAIM_SETTLEMENT' THEN ARRAY['CLAIM_SETTLEMENT']::text[]
        WHEN 'COD_COLLECTION' THEN ARRAY['COD_COLLECTION','CASH_ON_DELIVERY']::text[]
        ELSE ARRAY[]::text[]
    END;
    IF entry_source_id IS DISTINCT FROM NEW.financial_entity_id
       OR NOT (entry_source_type = ANY (expected_source_types)) THEN
        RAISE EXCEPTION 'Journal entry source entity does not match the linked financial entity'
            USING ERRCODE = '23514';
    END IF;
    IF NEW.currency_code IS DISTINCT FROM entity_currency_code
       OR NEW.currency_code IS DISTINCT FROM entry_currency_code THEN
        RAISE EXCEPTION 'Financial entity, link, and journal entry currencies differ'
            USING ERRCODE = '23514';
    END IF;
    IF entity_organization_id IS NOT NULL
       AND batch_organization_id IS DISTINCT FROM entity_organization_id THEN
        RAISE EXCEPTION 'Financial document and journal batch organizations differ'
            USING ERRCODE = '23514';
    END IF;

    PERFORM etms.assert_journal_entry_balanced(NEW.journal_entry_id);
    SELECT COALESCE(sum(debit_amount), 0)
      INTO entry_debit_total
      FROM etms.journal_lines WHERE journal_entry_id = NEW.journal_entry_id;
    SELECT COALESCE(sum(linked_amount), 0)
      INTO allocated_total
      FROM etms.financial_journal_links existing_link
     WHERE existing_link.journal_entry_id = NEW.journal_entry_id
       AND existing_link.link_role = NEW.link_role;
    IF allocated_total + NEW.linked_amount > entry_debit_total THEN
        RAISE EXCEPTION 'Financial journal link allocations exceed the journal entry debit total'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;


-- ---------------------------------------------------------------------------
-- Claim settlement aggregate, currency, party, and payment integrity.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION etms.validate_claim_settlement_integrity()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    claim_row record;
    active_total numeric(30,4);
    paid_total numeric(30,4);
    inactive_statuses constant text[] := ARRAY[
        'CANCELLED','VOID','REVERSED','REJECTED'
    ]::text[];
BEGIN
    IF TG_OP = 'DELETE' THEN
        IF OLD.status NOT IN ('DRAFT','PROPOSED','CANCELLED','VOID','REJECTED') THEN
            RAISE EXCEPTION 'Agreed/final claim settlements are immutable; record a reversal'
                USING ERRCODE = '55000';
        END IF;
        RETURN OLD;
    END IF;

    PERFORM pg_advisory_xact_lock(hashtext('claim-settlement:' || NEW.claim_id::text));
    SELECT tenant_id, claimant_partner_id, respondent_partner_id,
           liable_carrier_id, claimed_amount, approved_amount, currency_code
      INTO claim_row
      FROM etms.claims WHERE id = NEW.claim_id FOR UPDATE;
    IF NOT FOUND OR claim_row.tenant_id IS DISTINCT FROM NEW.tenant_id THEN
        RAISE EXCEPTION 'Claim settlement claim is missing or outside the tenant'
            USING ERRCODE = '23503';
    END IF;
    IF NEW.currency_code IS DISTINCT FROM claim_row.currency_code THEN
        RAISE EXCEPTION 'Claim settlement currency differs from the claim currency'
            USING ERRCODE = '23514';
    END IF;
    IF NEW.payee_partner_id IS DISTINCT FROM claim_row.claimant_partner_id
       OR NOT (
           NEW.payer_partner_id = claim_row.respondent_partner_id
           OR (claim_row.liable_carrier_id IS NOT NULL
               AND NEW.payer_partner_id = claim_row.liable_carrier_id)
       ) THEN
        RAISE EXCEPTION 'Claim settlement payer/payee do not match claim liability parties'
            USING ERRCODE = '23514';
    END IF;

    SELECT COALESCE(sum(settlement_amount), 0)
      INTO active_total
      FROM etms.claim_settlements existing_row
     WHERE existing_row.claim_id = NEW.claim_id
       AND existing_row.id <> NEW.id
       AND NOT (upper(existing_row.status) = ANY (inactive_statuses));
    IF NOT (upper(NEW.status) = ANY (inactive_statuses)) THEN
        active_total := active_total + NEW.settlement_amount;
    END IF;
    IF active_total > COALESCE(claim_row.approved_amount, claim_row.claimed_amount) THEN
        RAISE EXCEPTION 'Active claim settlements exceed the approved/claimed amount'
            USING ERRCODE = '23514';
    END IF;

    IF upper(NEW.status) IN ('PAID','SETTLED') THEN
        SELECT COALESCE(sum(
                   application_row.applied_amount
                   + application_row.discount_taken
                   + application_row.writeoff_amount
               ), 0)
          INTO paid_total
          FROM etms.payment_applications application_row
         WHERE application_row.claim_settlement_id = NEW.id;
        IF paid_total IS DISTINCT FROM NEW.settlement_amount THEN
            RAISE EXCEPTION 'Paid claim settlement must reconcile to payment applications'
                USING ERRCODE = '23514';
        END IF;
    END IF;

    IF TG_OP = 'UPDATE'
       AND upper(OLD.status) IN ('PAID','SETTLED')
       AND (
           NEW.claim_id IS DISTINCT FROM OLD.claim_id
           OR NEW.payer_partner_id IS DISTINCT FROM OLD.payer_partner_id
           OR NEW.payee_partner_id IS DISTINCT FROM OLD.payee_partner_id
           OR NEW.settlement_amount IS DISTINCT FROM OLD.settlement_amount
           OR NEW.currency_code IS DISTINCT FROM OLD.currency_code
           OR NEW.settlement_date IS DISTINCT FROM OLD.settlement_date
       ) THEN
        RAISE EXCEPTION 'Paid claim settlement financial fields are immutable'
            USING ERRCODE = '55000';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION etms.validate_claim_header_settlement_cap()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    active_total numeric(30,4);
    invalid_count integer;
BEGIN
    PERFORM pg_advisory_xact_lock(hashtext('claim-settlement:' || NEW.id::text));
    SELECT COALESCE(sum(settlement_amount), 0),
           count(*) FILTER (
               WHERE currency_code IS DISTINCT FROM NEW.currency_code
                  OR payee_partner_id IS DISTINCT FROM NEW.claimant_partner_id
                  OR NOT (
                      payer_partner_id = NEW.respondent_partner_id
                      OR (NEW.liable_carrier_id IS NOT NULL
                          AND payer_partner_id = NEW.liable_carrier_id)
                  )
           )
      INTO active_total, invalid_count
      FROM etms.claim_settlements settlement_row
     WHERE settlement_row.claim_id = NEW.id
       AND upper(settlement_row.status) NOT IN ('CANCELLED','VOID','REVERSED','REJECTED');
    IF active_total > COALESCE(NEW.approved_amount, NEW.claimed_amount)
       OR invalid_count > 0 THEN
        RAISE EXCEPTION 'Claim header change conflicts with active settlement amount, currency, or parties'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_05_validate_claim_settlement
    ON etms.claim_settlements;
CREATE TRIGGER trg_05_validate_claim_settlement
    BEFORE INSERT OR UPDATE OR DELETE ON etms.claim_settlements
    FOR EACH ROW EXECUTE PROCEDURE etms.validate_claim_settlement_integrity();
DROP TRIGGER IF EXISTS trg_05_validate_claim_header_settlements ON etms.claims;
CREATE TRIGGER trg_05_validate_claim_header_settlements
    BEFORE UPDATE OF claimed_amount, approved_amount, currency_code,
        claimant_partner_id, respondent_partner_id, liable_carrier_id
    ON etms.claims
    FOR EACH ROW EXECUTE PROCEDURE etms.validate_claim_header_settlement_cap();

CREATE INDEX IF NOT EXISTS ix_claim_settlements_claim_status
    ON etms.claim_settlements (tenant_id, claim_id, status);

-- ---------------------------------------------------------------------------
-- Cash-on-delivery subject, collection, remittance, payment, and journal guard.
-- ---------------------------------------------------------------------------

ALTER TABLE etms.cash_on_delivery_collections
    ADD COLUMN IF NOT EXISTS payment_id uuid;

DO $block$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
         WHERE conrelid = 'etms.cash_on_delivery_collections'::regclass
           AND conname = 'fk_cod_collection_payment_tenant'
    ) THEN
        ALTER TABLE etms.cash_on_delivery_collections
            ADD CONSTRAINT fk_cod_collection_payment_tenant
            FOREIGN KEY (tenant_id, payment_id)
            REFERENCES etms.payments(tenant_id, id) ON DELETE RESTRICT;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
         WHERE conrelid = 'etms.cash_on_delivery_collections'::regclass
           AND conname = 'ck_cod_collection_amount_cap'
    ) THEN
        ALTER TABLE etms.cash_on_delivery_collections
            ADD CONSTRAINT ck_cod_collection_amount_cap
            CHECK (collected_amount <= expected_amount);
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
         WHERE conrelid = 'etms.cash_on_delivery_collections'::regclass
           AND conname = 'ck_cod_collection_one_subject'
    ) THEN
        ALTER TABLE etms.cash_on_delivery_collections
            ADD CONSTRAINT ck_cod_collection_one_subject CHECK (
                (parcel_shipment_id IS NOT NULL)::integer
                + (parcel_package_id IS NOT NULL)::integer
                + (shipment_id IS NOT NULL)::integer = 1
            );
    END IF;
END;
$block$;

CREATE UNIQUE INDEX IF NOT EXISTS ux_cod_active_parcel_shipment
    ON etms.cash_on_delivery_collections (tenant_id, parcel_shipment_id)
    WHERE parcel_shipment_id IS NOT NULL AND status NOT IN ('FAILED','VOID');
CREATE UNIQUE INDEX IF NOT EXISTS ux_cod_active_parcel_package
    ON etms.cash_on_delivery_collections (tenant_id, parcel_package_id)
    WHERE parcel_package_id IS NOT NULL AND status NOT IN ('FAILED','VOID');
CREATE UNIQUE INDEX IF NOT EXISTS ux_cod_active_shipment
    ON etms.cash_on_delivery_collections (tenant_id, shipment_id)
    WHERE shipment_id IS NOT NULL AND status NOT IN ('FAILED','VOID');
CREATE INDEX IF NOT EXISTS ix_cod_collection_payment
    ON etms.cash_on_delivery_collections (tenant_id, payment_id);

CREATE OR REPLACE FUNCTION etms.validate_cod_collection_integrity()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    subject_type text;
    subject_id uuid;
    subject_tenant_id uuid;
    parent_parcel_shipment_id uuid;
    parent_shipment_id uuid;
    payment_row record;
    payment_applied_total numeric(30,4);
    allowed_transition boolean;
BEGIN
    IF NEW.parcel_package_id IS NOT NULL THEN
        subject_type := 'PARCEL_PACKAGE'; subject_id := NEW.parcel_package_id;
        SELECT package_row.tenant_id, package_row.parcel_shipment_id,
               parcel_row.shipment_id
          INTO subject_tenant_id, parent_parcel_shipment_id, parent_shipment_id
          FROM etms.parcel_packages package_row
          JOIN etms.parcel_shipments parcel_row
            ON parcel_row.id = package_row.parcel_shipment_id
         WHERE package_row.id = NEW.parcel_package_id;
    ELSIF NEW.parcel_shipment_id IS NOT NULL THEN
        subject_type := 'PARCEL_SHIPMENT'; subject_id := NEW.parcel_shipment_id;
        SELECT tenant_id, id, shipment_id
          INTO subject_tenant_id, parent_parcel_shipment_id, parent_shipment_id
          FROM etms.parcel_shipments WHERE id = NEW.parcel_shipment_id;
    ELSE
        subject_type := 'SHIPMENT'; subject_id := NEW.shipment_id;
        SELECT tenant_id, id
          INTO subject_tenant_id, parent_shipment_id
          FROM etms.shipments WHERE id = NEW.shipment_id;
    END IF;

    IF subject_tenant_id IS NULL OR subject_tenant_id IS DISTINCT FROM NEW.tenant_id THEN
        RAISE EXCEPTION 'COD subject is missing or outside the tenant'
            USING ERRCODE = '23503';
    END IF;
    PERFORM pg_advisory_xact_lock(hashtext(
        'cod-subject:' || subject_type || ':' || subject_id::text
    ));

    IF NEW.collected_amount > NEW.expected_amount THEN
        RAISE EXCEPTION 'COD collected amount exceeds the expected amount'
            USING ERRCODE = '23514';
    END IF;
    IF NEW.status = 'PENDING'
       AND (NEW.collected_amount <> 0 OR NEW.collected_at IS NOT NULL) THEN
        RAISE EXCEPTION 'Pending COD collection cannot contain collected cash'
            USING ERRCODE = '23514';
    ELSIF NEW.status = 'PARTIAL'
       AND NOT (NEW.collected_amount > 0 AND NEW.collected_amount < NEW.expected_amount
                AND NEW.collected_at IS NOT NULL) THEN
        RAISE EXCEPTION 'Partial COD collection requires a positive partial amount and collection time'
            USING ERRCODE = '23514';
    ELSIF NEW.status = 'COLLECTED'
       AND NOT (NEW.collected_amount = NEW.expected_amount AND NEW.collected_at IS NOT NULL) THEN
        RAISE EXCEPTION 'Collected COD status requires full collection and collection time'
            USING ERRCODE = '23514';
    ELSIF NEW.status = 'REMITTED'
       AND (NEW.collected_amount <= 0 OR NEW.collected_at IS NULL
            OR NEW.remitted_at IS NULL OR NEW.payment_id IS NULL) THEN
        RAISE EXCEPTION 'Remitted COD status requires collection, remittance time, and payment'
            USING ERRCODE = '23514';
    END IF;

    IF TG_OP = 'UPDATE' AND NEW.status IS DISTINCT FROM OLD.status THEN
        allowed_transition :=
            (OLD.status = 'PENDING' AND NEW.status IN ('PARTIAL','COLLECTED','FAILED','VOID')) OR
            (OLD.status = 'PARTIAL' AND NEW.status IN ('COLLECTED','REMITTED','DISPUTED','FAILED','VOID')) OR
            (OLD.status = 'COLLECTED' AND NEW.status IN ('REMITTED','DISPUTED','VOID')) OR
            (OLD.status = 'DISPUTED' AND NEW.status IN ('PARTIAL','COLLECTED','REMITTED','VOID')) OR
            (OLD.status = 'FAILED' AND NEW.status IN ('PENDING','VOID'));
        IF NOT allowed_transition THEN
            RAISE EXCEPTION 'Invalid COD collection status transition: % -> %',
                OLD.status, NEW.status USING ERRCODE = '23514';
        END IF;
    END IF;
    IF TG_OP = 'UPDATE' AND OLD.status = 'REMITTED' AND (
        NEW.tenant_id IS DISTINCT FROM OLD.tenant_id
        OR NEW.parcel_shipment_id IS DISTINCT FROM OLD.parcel_shipment_id
        OR NEW.parcel_package_id IS DISTINCT FROM OLD.parcel_package_id
        OR NEW.shipment_id IS DISTINCT FROM OLD.shipment_id
        OR NEW.expected_amount IS DISTINCT FROM OLD.expected_amount
        OR NEW.collected_amount IS DISTINCT FROM OLD.collected_amount
        OR NEW.currency_code IS DISTINCT FROM OLD.currency_code
        OR NEW.payment_id IS DISTINCT FROM OLD.payment_id
        OR NEW.collected_at IS DISTINCT FROM OLD.collected_at
        OR NEW.remitted_at IS DISTINCT FROM OLD.remitted_at
    ) THEN
        RAISE EXCEPTION 'Remitted COD financial fields are immutable'
            USING ERRCODE = '55000';
    END IF;

    IF NEW.payment_id IS NOT NULL THEN
        SELECT tenant_id, currency_code, payment_amount, payment_type, status,
               payer_partner_id, payee_partner_id
          INTO payment_row
          FROM etms.payments WHERE id = NEW.payment_id FOR UPDATE;
        IF NOT FOUND OR payment_row.tenant_id IS DISTINCT FROM NEW.tenant_id
           OR payment_row.currency_code IS DISTINCT FROM NEW.currency_code THEN
            RAISE EXCEPTION 'COD payment is missing or has a different tenant/currency'
                USING ERRCODE = '23514';
        END IF;
        IF NEW.status = 'REMITTED' AND (
            payment_row.payment_type NOT IN ('INBOUND','OFFSET')
            OR upper(payment_row.status) NOT IN ('COMPLETED','SETTLED')
            OR payment_row.payer_partner_id IS DISTINCT FROM
               COALESCE(NEW.collecting_partner_id, NEW.payer_partner_id)
        ) THEN
            RAISE EXCEPTION 'COD remittance payment type, status, or payer is invalid'
                USING ERRCODE = '23514';
        END IF;
        SELECT COALESCE(sum(application_row.applied_amount), 0)
          INTO payment_applied_total
          FROM etms.payment_applications application_row
         WHERE application_row.payment_id = NEW.payment_id;
        SELECT payment_applied_total + COALESCE(sum(collected_amount), 0)
          INTO payment_applied_total
          FROM etms.cash_on_delivery_collections existing_row
         WHERE existing_row.payment_id = NEW.payment_id
           AND existing_row.id <> NEW.id
           AND existing_row.status = 'REMITTED';
        IF NEW.status = 'REMITTED' THEN
            payment_applied_total := payment_applied_total + NEW.collected_amount;
        END IF;
        IF payment_applied_total > payment_row.payment_amount THEN
            RAISE EXCEPTION 'COD remittances exceed the linked payment amount'
                USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_05_validate_cod_collection
    ON etms.cash_on_delivery_collections;
CREATE TRIGGER trg_05_validate_cod_collection
    BEFORE INSERT OR UPDATE ON etms.cash_on_delivery_collections
    FOR EACH ROW EXECUTE PROCEDURE etms.validate_cod_collection_integrity();
-- Complete body is installed later in this same transaction.
CREATE OR REPLACE FUNCTION etms.require_posted_financial_journal()
RETURNS trigger LANGUAGE plpgsql AS $function$
BEGIN
    RETURN NEW;
END;
$function$;
DROP TRIGGER IF EXISTS trg_05_require_cod_journal
    ON etms.cash_on_delivery_collections;
CREATE TRIGGER trg_05_require_cod_journal
    BEFORE INSERT OR UPDATE OF status ON etms.cash_on_delivery_collections
    FOR EACH ROW EXECUTE PROCEDURE etms.require_posted_financial_journal(
        'COD_COLLECTION','status','REMITTED','collected_amount','currency_code'
    );


DO $block$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
         WHERE conrelid = 'etms.driver_settlement_lines'::regclass
           AND conname = 'ck_driver_settlement_line_integrity'
    ) THEN
        ALTER TABLE etms.driver_settlement_lines
            ADD CONSTRAINT ck_driver_settlement_line_integrity CHECK (
                line_type IN (
                    'EARNING','ALLOWANCE','REIMBURSEMENT','DEDUCTION','TAX_WITHHOLDING'
                ) AND line_amount >= 0
            );
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
         WHERE conrelid = 'etms.owner_operator_settlement_lines'::regclass
           AND conname = 'ck_owner_settlement_line_integrity'
    ) THEN
        ALTER TABLE etms.owner_operator_settlement_lines
            ADD CONSTRAINT ck_owner_settlement_line_integrity CHECK (
                line_type IN (
                    'HAUL_REVENUE','FUEL_SURCHARGE','ACCESSORIAL',
                    'ADVANCE','CHARGEBACK','WITHHOLDING'
                ) AND line_amount >= 0
            );
    END IF;
END;
$block$;

CREATE OR REPLACE FUNCTION etms.protect_bank_statement_line()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    old_parent_status text;
    new_parent record;
BEGIN
    IF TG_OP <> 'INSERT' THEN
        SELECT status INTO old_parent_status
          FROM etms.bank_statements WHERE id = OLD.bank_statement_id FOR UPDATE;
        IF old_parent_status <> 'IMPORTED' THEN
            IF TG_OP = 'DELETE' THEN
                RAISE EXCEPTION 'Validated bank statement source lines cannot be deleted'
                    USING ERRCODE = '55000';
            END IF;
            IF OLD.bank_statement_id IS DISTINCT FROM NEW.bank_statement_id
               OR OLD.line_no IS DISTINCT FROM NEW.line_no
               OR OLD.bank_transaction_id IS DISTINCT FROM NEW.bank_transaction_id
               OR OLD.booking_date IS DISTINCT FROM NEW.booking_date
               OR OLD.value_date IS DISTINCT FROM NEW.value_date
               OR OLD.transaction_type IS DISTINCT FROM NEW.transaction_type
               OR OLD.debit_credit_indicator IS DISTINCT FROM NEW.debit_credit_indicator
               OR OLD.transaction_amount IS DISTINCT FROM NEW.transaction_amount
               OR OLD.currency_code IS DISTINCT FROM NEW.currency_code
               OR OLD.running_balance IS DISTINCT FROM NEW.running_balance
               OR OLD.counterparty_name IS DISTINCT FROM NEW.counterparty_name
               OR OLD.counterparty_account_masked IS DISTINCT FROM NEW.counterparty_account_masked
               OR OLD.bank_reference IS DISTINCT FROM NEW.bank_reference
               OR OLD.remittance_information IS DISTINCT FROM NEW.remittance_information THEN
                RAISE EXCEPTION 'Validated bank statement source values are immutable'
                    USING ERRCODE = '55000';
            END IF;
        END IF;
    END IF;

    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;

    SELECT tenant_id, currency_code, period_start, period_end, status
      INTO new_parent
      FROM etms.bank_statements WHERE id = NEW.bank_statement_id FOR UPDATE;
    IF NOT FOUND OR new_parent.tenant_id IS DISTINCT FROM NEW.tenant_id THEN
        RAISE EXCEPTION 'Bank statement line parent is missing or outside the tenant'
            USING ERRCODE = '23503';
    END IF;
    IF new_parent.status <> 'IMPORTED' THEN
        IF TG_OP = 'INSERT' THEN
            RAISE EXCEPTION 'New source lines cannot be added to a validated bank statement'
                USING ERRCODE = '55000';
        ELSIF OLD.bank_statement_id IS DISTINCT FROM NEW.bank_statement_id THEN
            RAISE EXCEPTION 'Source lines cannot be moved to a validated bank statement'
                USING ERRCODE = '55000';
        END IF;
    END IF;
    IF NEW.currency_code IS DISTINCT FROM new_parent.currency_code
       OR NEW.booking_date < new_parent.period_start
       OR NEW.booking_date > new_parent.period_end THEN
        RAISE EXCEPTION 'Bank statement line currency or booking date differs from the statement'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION etms.validate_bank_reconciliation_match()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    source_data jsonb := CASE WHEN TG_OP = 'DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
    run_id_value uuid := NULLIF(source_data ->> 'bank_reconciliation_run_id', '')::uuid;
    line_id_value uuid := NULLIF(source_data ->> 'bank_statement_line_id', '')::uuid;
    run_row record;
    line_row record;
    existing_total numeric(30,4);
    old_run_status text;
BEGIN
    IF TG_OP = 'UPDATE' THEN
        SELECT status INTO old_run_status
          FROM etms.bank_reconciliation_runs
         WHERE id = OLD.bank_reconciliation_run_id FOR UPDATE;
        IF old_run_status NOT IN ('RUNNING','FAILED') THEN
            RAISE EXCEPTION 'Completed bank reconciliation matches cannot be moved or changed'
                USING ERRCODE = '55000';
        END IF;
    END IF;
    SELECT tenant_id, bank_statement_id, currency_code, status
      INTO run_row
      FROM etms.bank_reconciliation_runs WHERE id = run_id_value FOR UPDATE;
    SELECT tenant_id, bank_statement_id, transaction_amount, currency_code
      INTO line_row
      FROM etms.bank_statement_lines WHERE id = line_id_value FOR UPDATE;
    IF run_row.tenant_id IS NULL OR line_row.tenant_id IS NULL
       OR run_row.tenant_id IS DISTINCT FROM line_row.tenant_id
       OR run_row.bank_statement_id IS DISTINCT FROM line_row.bank_statement_id THEN
        RAISE EXCEPTION 'Reconciliation match line does not belong to the run bank statement'
            USING ERRCODE = '23514';
    END IF;
    IF run_row.status NOT IN ('RUNNING','FAILED') THEN
        RAISE EXCEPTION 'Completed bank reconciliation matches are immutable'
            USING ERRCODE = '55000';
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    IF NEW.tenant_id IS DISTINCT FROM run_row.tenant_id
       OR NEW.currency_code IS DISTINCT FROM run_row.currency_code
       OR NEW.currency_code IS DISTINCT FROM line_row.currency_code THEN
        RAISE EXCEPTION 'Reconciliation match tenant or currency differs from its run and line'
            USING ERRCODE = '23514';
    END IF;

    SELECT COALESCE(sum(matched_amount), 0)
      INTO existing_total
      FROM etms.bank_reconciliation_matches existing_row
     WHERE existing_row.bank_statement_line_id = NEW.bank_statement_line_id
       AND existing_row.id <> NEW.id
       AND existing_row.status NOT IN ('REJECTED','REVERSED');
    IF NEW.status NOT IN ('REJECTED','REVERSED') THEN
        existing_total := existing_total + NEW.matched_amount;
    END IF;
    IF existing_total > line_row.transaction_amount THEN
        RAISE EXCEPTION 'Confirmed/proposed reconciliation matches exceed the bank line amount'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

-- Forward declarations are replaced with their complete bodies below before the
-- migration transaction can commit. They let the trigger DDL remain grouped
-- with the protected tables without creating an unguarded deployment window.
CREATE OR REPLACE FUNCTION etms.validate_extended_finance_status_transition()
RETURNS trigger LANGUAGE plpgsql AS $function$
BEGIN
    RETURN NEW;
END;
$function$;
CREATE OR REPLACE FUNCTION etms.validate_extended_financial_totals()
RETURNS trigger LANGUAGE plpgsql AS $function$
BEGIN
    RETURN NEW;
END;
$function$;
CREATE OR REPLACE FUNCTION etms.prevent_locked_financial_child_mutation()
RETURNS trigger LANGUAGE plpgsql AS $function$
BEGIN
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_05_credit_note_status ON etms.credit_notes;
CREATE TRIGGER trg_05_credit_note_status
    BEFORE UPDATE OF status ON etms.credit_notes
    FOR EACH ROW EXECUTE PROCEDURE etms.validate_extended_finance_status_transition('CREDIT_NOTE');
DROP TRIGGER IF EXISTS trg_05_debit_note_status ON etms.debit_notes;
CREATE TRIGGER trg_05_debit_note_status
    BEFORE UPDATE OF status ON etms.debit_notes
    FOR EACH ROW EXECUTE PROCEDURE etms.validate_extended_finance_status_transition('DEBIT_NOTE');
DROP TRIGGER IF EXISTS trg_05_driver_settlement_status ON etms.driver_settlements;
CREATE TRIGGER trg_05_driver_settlement_status
    BEFORE UPDATE OF status ON etms.driver_settlements
    FOR EACH ROW EXECUTE PROCEDURE etms.validate_extended_finance_status_transition('DRIVER_SETTLEMENT');
DROP TRIGGER IF EXISTS trg_05_owner_settlement_status ON etms.owner_operator_settlements;
CREATE TRIGGER trg_05_owner_settlement_status
    BEFORE UPDATE OF status ON etms.owner_operator_settlements
    FOR EACH ROW EXECUTE PROCEDURE etms.validate_extended_finance_status_transition('OWNER_OPERATOR_SETTLEMENT');
DROP TRIGGER IF EXISTS trg_05_bank_statement_status ON etms.bank_statements;
CREATE TRIGGER trg_05_bank_statement_status
    BEFORE UPDATE OF status ON etms.bank_statements
    FOR EACH ROW EXECUTE PROCEDURE etms.validate_extended_finance_status_transition('BANK_STATEMENT');
DROP TRIGGER IF EXISTS trg_05_bank_reconciliation_status ON etms.bank_reconciliation_runs;
CREATE TRIGGER trg_05_bank_reconciliation_status
    BEFORE UPDATE OF status ON etms.bank_reconciliation_runs
    FOR EACH ROW EXECUTE PROCEDURE etms.validate_extended_finance_status_transition('BANK_RECONCILIATION');

DROP TRIGGER IF EXISTS trg_05_validate_credit_note_totals ON etms.credit_notes;
CREATE TRIGGER trg_05_validate_credit_note_totals
    BEFORE INSERT OR UPDATE OF status, subtotal_amount, tax_amount, total_amount, currency_code
    ON etms.credit_notes
    FOR EACH ROW EXECUTE PROCEDURE etms.validate_extended_financial_totals();
DROP TRIGGER IF EXISTS trg_05_validate_debit_note_totals ON etms.debit_notes;
CREATE TRIGGER trg_05_validate_debit_note_totals
    BEFORE INSERT OR UPDATE OF status, subtotal_amount, tax_amount, total_amount, currency_code
    ON etms.debit_notes
    FOR EACH ROW EXECUTE PROCEDURE etms.validate_extended_financial_totals();
DROP TRIGGER IF EXISTS trg_05_validate_driver_settlement_totals ON etms.driver_settlements;
CREATE TRIGGER trg_05_validate_driver_settlement_totals
    BEFORE INSERT OR UPDATE OF status, earnings_amount, allowance_amount,
        reimbursement_amount, deduction_amount, tax_withholding_amount, currency_code
    ON etms.driver_settlements
    FOR EACH ROW EXECUTE PROCEDURE etms.validate_extended_financial_totals();
DROP TRIGGER IF EXISTS trg_05_validate_owner_settlement_totals ON etms.owner_operator_settlements;
CREATE TRIGGER trg_05_validate_owner_settlement_totals
    BEFORE INSERT OR UPDATE OF status, haul_revenue_amount, fuel_surcharge_amount,
        accessorial_amount, advance_amount, chargeback_amount, withholding_amount, currency_code
    ON etms.owner_operator_settlements
    FOR EACH ROW EXECUTE PROCEDURE etms.validate_extended_financial_totals();
DROP TRIGGER IF EXISTS trg_05_validate_bank_statement_totals ON etms.bank_statements;
CREATE TRIGGER trg_05_validate_bank_statement_totals
    BEFORE INSERT OR UPDATE OF status, total_debit_amount, total_credit_amount,
        opening_balance, closing_balance, currency_code, period_start, period_end
    ON etms.bank_statements
    FOR EACH ROW EXECUTE PROCEDURE etms.validate_extended_financial_totals();
DROP TRIGGER IF EXISTS trg_05_validate_bank_reconciliation_totals ON etms.bank_reconciliation_runs;
CREATE TRIGGER trg_05_validate_bank_reconciliation_totals
    BEFORE INSERT OR UPDATE OF status, total_line_count, matched_line_count,
        exception_line_count, matched_amount, unmatched_amount, currency_code
    ON etms.bank_reconciliation_runs
    FOR EACH ROW EXECUTE PROCEDURE etms.validate_extended_financial_totals();

DROP TRIGGER IF EXISTS trg_05_lock_credit_note_lines ON etms.credit_note_lines;
CREATE TRIGGER trg_05_lock_credit_note_lines
    BEFORE INSERT OR UPDATE OR DELETE ON etms.credit_note_lines
    FOR EACH ROW EXECUTE PROCEDURE etms.prevent_locked_financial_child_mutation(
        'credit_note_id','credit_notes','DRAFT'
    );
DROP TRIGGER IF EXISTS trg_05_lock_debit_note_lines ON etms.debit_note_lines;
CREATE TRIGGER trg_05_lock_debit_note_lines
    BEFORE INSERT OR UPDATE OR DELETE ON etms.debit_note_lines
    FOR EACH ROW EXECUTE PROCEDURE etms.prevent_locked_financial_child_mutation(
        'debit_note_id','debit_notes','DRAFT'
    );
DROP TRIGGER IF EXISTS trg_05_lock_driver_settlement_lines ON etms.driver_settlement_lines;
CREATE TRIGGER trg_05_lock_driver_settlement_lines
    BEFORE INSERT OR UPDATE OR DELETE ON etms.driver_settlement_lines
    FOR EACH ROW EXECUTE PROCEDURE etms.prevent_locked_financial_child_mutation(
        'driver_settlement_id','driver_settlements','DRAFT,CALCULATED,REVIEWED,DISPUTED'
    );
DROP TRIGGER IF EXISTS trg_05_lock_owner_settlement_lines ON etms.owner_operator_settlement_lines;
CREATE TRIGGER trg_05_lock_owner_settlement_lines
    BEFORE INSERT OR UPDATE OR DELETE ON etms.owner_operator_settlement_lines
    FOR EACH ROW EXECUTE PROCEDURE etms.prevent_locked_financial_child_mutation(
        'owner_operator_settlement_id','owner_operator_settlements','DRAFT,CALCULATED,REVIEWED,DISPUTED'
    );
DROP TRIGGER IF EXISTS trg_05_protect_bank_statement_lines ON etms.bank_statement_lines;
CREATE TRIGGER trg_05_protect_bank_statement_lines
    BEFORE INSERT OR UPDATE OR DELETE ON etms.bank_statement_lines
    FOR EACH ROW EXECUTE PROCEDURE etms.protect_bank_statement_line();
DROP TRIGGER IF EXISTS trg_05_validate_bank_reconciliation_match ON etms.bank_reconciliation_matches;
CREATE TRIGGER trg_05_validate_bank_reconciliation_match
    BEFORE INSERT OR UPDATE OR DELETE ON etms.bank_reconciliation_matches
    FOR EACH ROW EXECUTE PROCEDURE etms.validate_bank_reconciliation_match();

DROP TRIGGER IF EXISTS trg_05_protect_credit_note_header ON etms.credit_notes;
CREATE TRIGGER trg_05_protect_credit_note_header
    BEFORE UPDATE OR DELETE ON etms.credit_notes
    FOR EACH ROW EXECUTE PROCEDURE etms.protect_finalized_header(
        'status','DRAFT',
        'id,tenant_id,credit_note_no,invoice_id,issuer_partner_id,recipient_partner_id,credit_note_date,reason_code,subtotal_amount,tax_amount,total_amount,currency_code,approved_by_user_id,approved_at'
    );
DROP TRIGGER IF EXISTS trg_05_protect_debit_note_header ON etms.debit_notes;
CREATE TRIGGER trg_05_protect_debit_note_header
    BEFORE UPDATE OR DELETE ON etms.debit_notes
    FOR EACH ROW EXECUTE PROCEDURE etms.protect_finalized_header(
        'status','DRAFT',
        'id,tenant_id,debit_note_no,invoice_id,issuer_partner_id,recipient_partner_id,debit_note_date,reason_code,subtotal_amount,tax_amount,total_amount,currency_code,due_date,approved_by_user_id,approved_at'
    );
DROP TRIGGER IF EXISTS trg_05_protect_driver_settlement_header ON etms.driver_settlements;
CREATE TRIGGER trg_05_protect_driver_settlement_header
    BEFORE UPDATE OR DELETE ON etms.driver_settlements
    FOR EACH ROW EXECUTE PROCEDURE etms.protect_finalized_header(
        'status','DRAFT,CALCULATED,REVIEWED,DISPUTED',
        'id,tenant_id,driver_settlement_no,driver_id,settlement_period_start,settlement_period_end,earnings_amount,allowance_amount,reimbursement_amount,deduction_amount,tax_withholding_amount,net_payable_amount,currency_code,approved_by_user_id'
    );
DROP TRIGGER IF EXISTS trg_05_protect_owner_settlement_header ON etms.owner_operator_settlements;
CREATE TRIGGER trg_05_protect_owner_settlement_header
    BEFORE UPDATE OR DELETE ON etms.owner_operator_settlements
    FOR EACH ROW EXECUTE PROCEDURE etms.protect_finalized_header(
        'status','DRAFT,CALCULATED,REVIEWED,DISPUTED',
        'id,tenant_id,owner_settlement_no,owner_operator_partner_id,vehicle_id,settlement_period_start,settlement_period_end,haul_revenue_amount,fuel_surcharge_amount,accessorial_amount,advance_amount,chargeback_amount,withholding_amount,net_payable_amount,currency_code,approved_by_user_id'
    );
DROP TRIGGER IF EXISTS trg_05_protect_bank_statement_header ON etms.bank_statements;
CREATE TRIGGER trg_05_protect_bank_statement_header
    BEFORE UPDATE OR DELETE ON etms.bank_statements
    FOR EACH ROW EXECUTE PROCEDURE etms.protect_finalized_header(
        'status','IMPORTED',
        'id,tenant_id,statement_no,partner_bank_account_id,statement_date,period_start,period_end,opening_balance,total_debit_amount,total_credit_amount,closing_balance,currency_code,source_file_id,import_checksum,imported_at'
    );
DROP TRIGGER IF EXISTS trg_05_protect_bank_reconciliation_header ON etms.bank_reconciliation_runs;
CREATE TRIGGER trg_05_protect_bank_reconciliation_header
    BEFORE UPDATE OR DELETE ON etms.bank_reconciliation_runs
    FOR EACH ROW EXECUTE PROCEDURE etms.protect_finalized_header(
        'status','RUNNING,FAILED',
        'id,tenant_id,reconciliation_run_no,bank_statement_id,rule_set_version,started_at,completed_at,total_line_count,matched_line_count,exception_line_count,matched_amount,unmatched_amount,currency_code,result_summary'
    );

CREATE INDEX IF NOT EXISTS ix_bank_reconciliation_matches_line_status
    ON etms.bank_reconciliation_matches (tenant_id, bank_statement_line_id, status);


-- ---------------------------------------------------------------------------
-- Credit/debit documents, driver/owner settlement, and bank reconciliation.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION etms.validate_extended_finance_status_transition()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    allowed boolean := false;
BEGIN
    IF NEW.status IS NOT DISTINCT FROM OLD.status THEN
        RETURN NEW;
    END IF;

    IF TG_ARGV[0] IN ('CREDIT_NOTE','DEBIT_NOTE') THEN
        allowed :=
            (OLD.status = 'DRAFT' AND NEW.status IN ('APPROVED','VOID')) OR
            (OLD.status = 'APPROVED' AND NEW.status IN ('ISSUED','VOID')) OR
            (OLD.status = 'ISSUED' AND NEW.status IN ('PARTIALLY_APPLIED','PARTIALLY_PAID','APPLIED','PAID','VOID')) OR
            (OLD.status IN ('PARTIALLY_APPLIED','PARTIALLY_PAID') AND NEW.status IN ('APPLIED','PAID','VOID'));
    ELSIF TG_ARGV[0] IN ('DRIVER_SETTLEMENT','OWNER_OPERATOR_SETTLEMENT') THEN
        allowed :=
            (OLD.status = 'DRAFT' AND NEW.status IN ('CALCULATED','VOID')) OR
            (OLD.status = 'CALCULATED' AND NEW.status IN ('REVIEWED','DISPUTED','VOID')) OR
            (OLD.status = 'REVIEWED' AND NEW.status IN ('APPROVED','DISPUTED','VOID')) OR
            (OLD.status = 'DISPUTED' AND NEW.status IN ('CALCULATED','REVIEWED','VOID')) OR
            (OLD.status = 'APPROVED' AND NEW.status IN ('PAID','VOID'));
    ELSIF TG_ARGV[0] = 'BANK_STATEMENT' THEN
        allowed :=
            (OLD.status = 'IMPORTED' AND NEW.status IN ('VALIDATED','FAILED','VOID')) OR
            (OLD.status = 'FAILED' AND NEW.status = 'VOID') OR
            (OLD.status = 'VALIDATED' AND NEW.status IN ('RECONCILING','VOID')) OR
            (OLD.status = 'RECONCILING' AND NEW.status IN ('RECONCILED','FAILED','VOID'));
    ELSIF TG_ARGV[0] = 'BANK_RECONCILIATION' THEN
        allowed :=
            (OLD.status = 'RUNNING' AND NEW.status IN ('COMPLETED','PARTIAL','FAILED','CANCELLED')) OR
            (OLD.status = 'FAILED' AND NEW.status IN ('RUNNING','CANCELLED'));
    END IF;

    IF NOT allowed THEN
        RAISE EXCEPTION 'Invalid % status transition: % -> %',
            TG_ARGV[0], OLD.status, NEW.status USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION etms.validate_extended_financial_totals()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    first_total numeric(30,4);
    second_total numeric(30,4);
    third_total numeric(30,4);
    fourth_total numeric(30,4);
    fifth_total numeric(30,4);
    sixth_total numeric(30,4);
    invalid_count integer;
BEGIN
    IF TG_TABLE_NAME = 'credit_notes' THEN
        IF NEW.status = 'DRAFT' THEN RETURN NEW; END IF;
        SELECT COALESCE(sum(net_amount), 0), COALESCE(sum(tax_amount), 0),
               COALESCE(sum(total_amount), 0),
               count(*) FILTER (WHERE currency_code IS DISTINCT FROM NEW.currency_code)
          INTO first_total, second_total, third_total, invalid_count
          FROM etms.credit_note_lines WHERE credit_note_id = NEW.id;
        IF NEW.subtotal_amount IS DISTINCT FROM first_total
           OR NEW.tax_amount IS DISTINCT FROM second_total
           OR NEW.total_amount IS DISTINCT FROM third_total
           OR invalid_count > 0 THEN
            RAISE EXCEPTION 'Credit note header, line totals, or currencies do not reconcile'
                USING ERRCODE = '23514';
        END IF;
    ELSIF TG_TABLE_NAME = 'debit_notes' THEN
        IF NEW.status = 'DRAFT' THEN RETURN NEW; END IF;
        SELECT COALESCE(sum(net_amount), 0), COALESCE(sum(tax_amount), 0),
               COALESCE(sum(total_amount), 0),
               count(*) FILTER (WHERE currency_code IS DISTINCT FROM NEW.currency_code)
          INTO first_total, second_total, third_total, invalid_count
          FROM etms.debit_note_lines WHERE debit_note_id = NEW.id;
        IF NEW.subtotal_amount IS DISTINCT FROM first_total
           OR NEW.tax_amount IS DISTINCT FROM second_total
           OR NEW.total_amount IS DISTINCT FROM third_total
           OR invalid_count > 0 THEN
            RAISE EXCEPTION 'Debit note header, line totals, or currencies do not reconcile'
                USING ERRCODE = '23514';
        END IF;
    ELSIF TG_TABLE_NAME = 'driver_settlements' THEN
        IF NEW.status = 'DRAFT' THEN RETURN NEW; END IF;
        SELECT
            COALESCE(sum(line_amount) FILTER (WHERE line_type = 'EARNING'), 0),
            COALESCE(sum(line_amount) FILTER (WHERE line_type = 'ALLOWANCE'), 0),
            COALESCE(sum(line_amount) FILTER (WHERE line_type = 'REIMBURSEMENT'), 0),
            COALESCE(sum(line_amount) FILTER (WHERE line_type = 'DEDUCTION'), 0),
            COALESCE(sum(line_amount) FILTER (WHERE line_type = 'TAX_WITHHOLDING'), 0),
            count(*) FILTER (
                WHERE line_type NOT IN (
                    'EARNING','ALLOWANCE','REIMBURSEMENT','DEDUCTION','TAX_WITHHOLDING'
                ) OR currency_code IS DISTINCT FROM NEW.currency_code OR line_amount < 0
            )
          INTO first_total, second_total, third_total, fourth_total, fifth_total,
               invalid_count
          FROM etms.driver_settlement_lines WHERE driver_settlement_id = NEW.id;
        IF NEW.earnings_amount IS DISTINCT FROM first_total
           OR NEW.allowance_amount IS DISTINCT FROM second_total
           OR NEW.reimbursement_amount IS DISTINCT FROM third_total
           OR NEW.deduction_amount IS DISTINCT FROM fourth_total
           OR NEW.tax_withholding_amount IS DISTINCT FROM fifth_total
           OR invalid_count > 0 THEN
            RAISE EXCEPTION 'Driver settlement header, categorized lines, or currencies do not reconcile'
                USING ERRCODE = '23514';
        END IF;
    ELSIF TG_TABLE_NAME = 'owner_operator_settlements' THEN
        IF NEW.status = 'DRAFT' THEN RETURN NEW; END IF;
        SELECT
            COALESCE(sum(line_amount) FILTER (WHERE line_type = 'HAUL_REVENUE'), 0),
            COALESCE(sum(line_amount) FILTER (WHERE line_type = 'FUEL_SURCHARGE'), 0),
            COALESCE(sum(line_amount) FILTER (WHERE line_type = 'ACCESSORIAL'), 0),
            COALESCE(sum(line_amount) FILTER (WHERE line_type = 'ADVANCE'), 0),
            COALESCE(sum(line_amount) FILTER (WHERE line_type = 'CHARGEBACK'), 0),
            COALESCE(sum(line_amount) FILTER (WHERE line_type = 'WITHHOLDING'), 0),
            count(*) FILTER (
                WHERE line_type NOT IN (
                    'HAUL_REVENUE','FUEL_SURCHARGE','ACCESSORIAL',
                    'ADVANCE','CHARGEBACK','WITHHOLDING'
                ) OR currency_code IS DISTINCT FROM NEW.currency_code OR line_amount < 0
            )
          INTO first_total, second_total, third_total, fourth_total, fifth_total,
               sixth_total, invalid_count
          FROM etms.owner_operator_settlement_lines
         WHERE owner_operator_settlement_id = NEW.id;
        IF NEW.haul_revenue_amount IS DISTINCT FROM first_total
           OR NEW.fuel_surcharge_amount IS DISTINCT FROM second_total
           OR NEW.accessorial_amount IS DISTINCT FROM third_total
           OR NEW.advance_amount IS DISTINCT FROM fourth_total
           OR NEW.chargeback_amount IS DISTINCT FROM fifth_total
           OR NEW.withholding_amount IS DISTINCT FROM sixth_total
           OR invalid_count > 0 THEN
            RAISE EXCEPTION 'Owner-operator settlement header, categorized lines, or currencies do not reconcile'
                USING ERRCODE = '23514';
        END IF;
    ELSIF TG_TABLE_NAME = 'bank_statements' THEN
        IF NEW.status IN ('IMPORTED','FAILED') THEN RETURN NEW; END IF;
        SELECT
            COALESCE(sum(transaction_amount) FILTER (WHERE debit_credit_indicator = 'D'), 0),
            COALESCE(sum(transaction_amount) FILTER (WHERE debit_credit_indicator = 'C'), 0),
            count(*) FILTER (
                WHERE currency_code IS DISTINCT FROM NEW.currency_code
                   OR booking_date < NEW.period_start OR booking_date > NEW.period_end
            )
          INTO first_total, second_total, invalid_count
          FROM etms.bank_statement_lines WHERE bank_statement_id = NEW.id;
        IF NEW.total_debit_amount IS DISTINCT FROM first_total
           OR NEW.total_credit_amount IS DISTINCT FROM second_total
           OR invalid_count > 0 THEN
            RAISE EXCEPTION 'Bank statement header and source lines do not reconcile'
                USING ERRCODE = '23514';
        END IF;
        IF NEW.status = 'RECONCILED' AND NOT EXISTS (
            SELECT 1 FROM etms.bank_reconciliation_runs run_row
             WHERE run_row.bank_statement_id = NEW.id
               AND run_row.status = 'COMPLETED'
        ) THEN
            RAISE EXCEPTION 'Reconciled bank statement requires a completed reconciliation run'
                USING ERRCODE = '23514';
        END IF;
    ELSIF TG_TABLE_NAME = 'bank_reconciliation_runs' THEN
        IF NEW.status NOT IN ('COMPLETED','PARTIAL') THEN RETURN NEW; END IF;
        IF NEW.completed_at IS NULL THEN
            RAISE EXCEPTION 'Final bank reconciliation run requires completed_at'
                USING ERRCODE = '23514';
        END IF;
        SELECT count(*), COALESCE(sum(transaction_amount), 0),
               count(*) FILTER (WHERE currency_code IS DISTINCT FROM NEW.currency_code)
          INTO first_total, second_total, invalid_count
          FROM etms.bank_statement_lines WHERE bank_statement_id = NEW.bank_statement_id;
        SELECT count(DISTINCT bank_statement_line_id), COALESCE(sum(matched_amount), 0)
          INTO third_total, fourth_total
          FROM etms.bank_reconciliation_matches
         WHERE bank_reconciliation_run_id = NEW.id AND status = 'CONFIRMED';
        IF NEW.total_line_count IS DISTINCT FROM first_total::integer
           OR NEW.matched_line_count IS DISTINCT FROM third_total::integer
           OR NEW.exception_line_count IS DISTINCT FROM (first_total - third_total)::integer
           OR NEW.matched_amount IS DISTINCT FROM fourth_total
           OR NEW.unmatched_amount IS DISTINCT FROM (second_total - fourth_total)
           OR invalid_count > 0
           OR (NEW.status = 'COMPLETED'
               AND (third_total IS DISTINCT FROM first_total OR fourth_total IS DISTINCT FROM second_total)) THEN
            RAISE EXCEPTION 'Bank reconciliation run does not reconcile to statement lines and confirmed matches'
                USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION etms.prevent_locked_financial_child_mutation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    parent_ids uuid[];
    parent_id uuid;
    parent_status text;
    approval_user_id uuid;
    editable_statuses text[] := string_to_array(TG_ARGV[2], ',');
BEGIN
    IF TG_OP = 'INSERT' THEN
        parent_ids := ARRAY[NULLIF(to_jsonb(NEW) ->> TG_ARGV[0], '')::uuid];
    ELSIF TG_OP = 'DELETE' THEN
        parent_ids := ARRAY[NULLIF(to_jsonb(OLD) ->> TG_ARGV[0], '')::uuid];
    ELSE
        parent_ids := ARRAY[
            NULLIF(to_jsonb(OLD) ->> TG_ARGV[0], '')::uuid,
            NULLIF(to_jsonb(NEW) ->> TG_ARGV[0], '')::uuid
        ];
    END IF;

    FOREACH parent_id IN ARRAY parent_ids LOOP
        parent_status := NULL;
        approval_user_id := NULL;
        IF TG_ARGV[1] = 'driver_settlements' THEN
            SELECT status, approved_by_user_id INTO parent_status, approval_user_id
              FROM etms.driver_settlements WHERE id = parent_id FOR UPDATE;
        ELSIF TG_ARGV[1] = 'owner_operator_settlements' THEN
            SELECT status, approved_by_user_id INTO parent_status, approval_user_id
              FROM etms.owner_operator_settlements WHERE id = parent_id FOR UPDATE;
        ELSE
            EXECUTE format('SELECT status FROM etms.%I WHERE id = $1 FOR UPDATE', TG_ARGV[1])
               INTO parent_status USING parent_id;
        END IF;

        IF parent_status IS NULL THEN
            RAISE EXCEPTION 'Financial child parent is unavailable'
                USING ERRCODE = '23503';
        END IF;
        IF NOT (parent_status = ANY (editable_statuses)) OR approval_user_id IS NOT NULL THEN
            RAISE EXCEPTION 'Finalized % child rows are immutable; create a correction or reversal',
                TG_ARGV[1] USING ERRCODE = '55000';
        END IF;
    END LOOP;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$function$;


DROP TRIGGER IF EXISTS trg_validate_financial_journal_link
    ON etms.financial_journal_links;
CREATE TRIGGER trg_validate_financial_journal_link
    BEFORE INSERT ON etms.financial_journal_links
    FOR EACH ROW EXECUTE PROCEDURE etms.validate_financial_journal_link();

DROP TRIGGER IF EXISTS trg_financial_journal_link_append_only_row
    ON etms.financial_journal_links;
CREATE TRIGGER trg_financial_journal_link_append_only_row
    BEFORE UPDATE OR DELETE ON etms.financial_journal_links
    FOR EACH ROW EXECUTE PROCEDURE etms.prevent_ledger_mutation();
DROP TRIGGER IF EXISTS trg_financial_journal_link_append_only_truncate
    ON etms.financial_journal_links;
CREATE TRIGGER trg_financial_journal_link_append_only_truncate
    BEFORE TRUNCATE ON etms.financial_journal_links
    FOR EACH STATEMENT EXECUTE PROCEDURE etms.prevent_ledger_mutation();

CREATE OR REPLACE FUNCTION etms.require_posted_financial_journal()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    target_status text := to_jsonb(NEW) ->> TG_ARGV[1];
    required_statuses text[] := string_to_array(TG_ARGV[2], ',');
    target_amount numeric(30,4) := NULLIF(to_jsonb(NEW) ->> TG_ARGV[3], '')::numeric;
    target_currency_code text := to_jsonb(NEW) ->> TG_ARGV[4];
    required_link_role text := CASE WHEN TG_NARGS >= 6 THEN TG_ARGV[5] ELSE 'POSTING' END;
    linked_entry_id uuid;
    found_link boolean := false;
    linked_total numeric(30,4) := 0;
BEGIN
    IF NOT (target_status = ANY (required_statuses)) THEN
        RETURN NEW;
    END IF;

    FOR linked_entry_id IN
        SELECT link_row.journal_entry_id
          FROM etms.financial_journal_links link_row
          JOIN etms.journal_entries entry_row
            ON entry_row.id = link_row.journal_entry_id
           AND entry_row.tenant_id = link_row.tenant_id
          JOIN etms.journal_batches batch_row
            ON batch_row.id = entry_row.journal_batch_id
           AND batch_row.tenant_id = link_row.tenant_id
         WHERE link_row.tenant_id = NEW.tenant_id
           AND link_row.financial_entity_type = TG_ARGV[0]
           AND link_row.financial_entity_id = NEW.id
           AND link_row.link_role = required_link_role
           AND link_row.currency_code = target_currency_code
           AND entry_row.status = 'POSTED'
           AND batch_row.status = 'POSTED'
    LOOP
        found_link := true;
        PERFORM etms.assert_journal_entry_balanced(linked_entry_id);
    END LOOP;

    IF NOT found_link THEN
        RAISE EXCEPTION 'Finalized % % requires a posted balanced % journal link',
            TG_ARGV[0], NEW.id, required_link_role USING ERRCODE = '23514';
    END IF;
    SELECT COALESCE(sum(linked_amount), 0)
      INTO linked_total
      FROM etms.financial_journal_links link_row
     WHERE link_row.tenant_id = NEW.tenant_id
       AND link_row.financial_entity_type = TG_ARGV[0]
       AND link_row.financial_entity_id = NEW.id
       AND link_row.link_role = required_link_role
       AND link_row.currency_code = target_currency_code;
    IF linked_total IS DISTINCT FROM target_amount THEN
        RAISE EXCEPTION 'Financial journal % allocations % do not reconcile to document amount %',
            required_link_role, linked_total, target_amount USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_require_invoice_journal ON etms.invoices;
CREATE TRIGGER trg_require_invoice_journal
    BEFORE INSERT OR UPDATE OF status ON etms.invoices
    FOR EACH ROW EXECUTE PROCEDURE etms.require_posted_financial_journal(
        'INVOICE','status','POSTED,PARTIALLY_PAID,PAID','gross_amount','currency_code'
    );
DROP TRIGGER IF EXISTS trg_require_tax_invoice_journal ON etms.tax_invoices;
CREATE TRIGGER trg_require_tax_invoice_journal
    BEFORE INSERT OR UPDATE OF nts_status ON etms.tax_invoices
    FOR EACH ROW EXECUTE PROCEDURE etms.require_posted_financial_journal(
        'TAX_INVOICE','nts_status','ISSUED,TRANSMITTED,ACCEPTED,CORRECTED','total_amount','currency_code'
    );
DROP TRIGGER IF EXISTS trg_require_settlement_journal ON etms.settlements;
CREATE TRIGGER trg_require_settlement_journal
    BEFORE INSERT OR UPDATE OF status ON etms.settlements
    FOR EACH ROW EXECUTE PROCEDURE etms.require_posted_financial_journal(
        'SETTLEMENT','status','APPROVED,INVOICED,PARTIALLY_PAID,PAID','net_payable_amount','currency_code'
    );
DROP TRIGGER IF EXISTS trg_05_require_credit_note_journal ON etms.credit_notes;
CREATE TRIGGER trg_05_require_credit_note_journal
    BEFORE INSERT OR UPDATE OF status ON etms.credit_notes
    FOR EACH ROW EXECUTE PROCEDURE etms.require_posted_financial_journal(
        'CREDIT_NOTE','status','ISSUED,PARTIALLY_APPLIED,APPLIED','total_amount','currency_code'
    );
DROP TRIGGER IF EXISTS trg_05_require_debit_note_journal ON etms.debit_notes;
CREATE TRIGGER trg_05_require_debit_note_journal
    BEFORE INSERT OR UPDATE OF status ON etms.debit_notes
    FOR EACH ROW EXECUTE PROCEDURE etms.require_posted_financial_journal(
        'DEBIT_NOTE','status','ISSUED,PARTIALLY_PAID,PAID','total_amount','currency_code'
    );
DROP TRIGGER IF EXISTS trg_05_require_driver_settlement_journal ON etms.driver_settlements;
CREATE TRIGGER trg_05_require_driver_settlement_journal
    BEFORE INSERT OR UPDATE OF status ON etms.driver_settlements
    FOR EACH ROW EXECUTE PROCEDURE etms.require_posted_financial_journal(
        'DRIVER_SETTLEMENT','status','APPROVED,PAID','net_payable_amount','currency_code'
    );
DROP TRIGGER IF EXISTS trg_05_require_owner_settlement_journal ON etms.owner_operator_settlements;
CREATE TRIGGER trg_05_require_owner_settlement_journal
    BEFORE INSERT OR UPDATE OF status ON etms.owner_operator_settlements
    FOR EACH ROW EXECUTE PROCEDURE etms.require_posted_financial_journal(
        'OWNER_OPERATOR_SETTLEMENT','status','APPROVED,PAID','net_payable_amount','currency_code'
    );
DROP TRIGGER IF EXISTS trg_05_require_claim_settlement_journal ON etms.claim_settlements;
CREATE TRIGGER trg_05_require_claim_settlement_journal
    BEFORE INSERT OR UPDATE OF status ON etms.claim_settlements
    FOR EACH ROW EXECUTE PROCEDURE etms.require_posted_financial_journal(
        'CLAIM_SETTLEMENT','status','PAID,SETTLED','settlement_amount','currency_code'
    );

-- Replace the baseline batch validator with organization, period, currency,
-- transaction-currency, and base-currency posting controls.
CREATE OR REPLACE FUNCTION etms.validate_journal_batch_posting()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    period_row record;
    currency_row record;
    entry_count integer;
    line_count integer;
    unposted_count integer;
    invalid_entry_date_count integer;
    invalid_account_count integer;
    invalid_exchange_count integer;
    base_debit_total numeric(30,4);
    base_credit_total numeric(30,4);
BEGIN
    IF NEW.status <> 'POSTED' THEN
        RETURN NEW;
    END IF;

    SELECT period_row_source.tenant_id, period_row_source.organization_id,
           period_row_source.starts_on, period_row_source.ends_on,
           period_row_source.status, organization_row.base_currency_code
      INTO period_row
      FROM etms.accounting_periods period_row_source
      JOIN etms.organizations organization_row
        ON organization_row.id = period_row_source.organization_id
     WHERE period_row_source.id = NEW.accounting_period_id
     FOR SHARE;

    IF NOT FOUND
       OR period_row.tenant_id IS DISTINCT FROM NEW.tenant_id
       OR period_row.organization_id IS DISTINCT FROM NEW.organization_id THEN
        RAISE EXCEPTION 'Journal batch accounting period is outside its tenant or organization'
            USING ERRCODE = '23514';
    END IF;
    IF period_row.status <> 'OPEN' THEN
        RAISE EXCEPTION 'Journal batches may post only to an OPEN accounting period'
            USING ERRCODE = '23514';
    END IF;
    IF NEW.accounting_date < period_row.starts_on
       OR NEW.accounting_date > period_row.ends_on THEN
        RAISE EXCEPTION 'Journal batch accounting date is outside the accounting period'
            USING ERRCODE = '23514';
    END IF;

    SELECT count(*), count(*) FILTER (WHERE entry_row.status <> 'POSTED'),
           count(*) FILTER (
               WHERE entry_row.entry_date < period_row.starts_on
                  OR entry_row.entry_date > period_row.ends_on
           )
      INTO entry_count, unposted_count, invalid_entry_date_count
      FROM etms.journal_entries entry_row
     WHERE entry_row.journal_batch_id = NEW.id;

    SELECT count(*)
      INTO line_count
      FROM etms.journal_entries entry_row
      JOIN etms.journal_lines line_row
        ON line_row.journal_entry_id = entry_row.id
     WHERE entry_row.journal_batch_id = NEW.id;

    IF entry_count = 0 OR line_count = 0 OR unposted_count > 0
       OR invalid_entry_date_count > 0 THEN
        RAISE EXCEPTION 'Posted journal batch requires posted entries and lines within the accounting period'
            USING ERRCODE = '23514';
    END IF;

    FOR currency_row IN
        SELECT entry_row.currency_code,
               sum(line_row.debit_amount) AS debit_total,
               sum(line_row.credit_amount) AS credit_total
          FROM etms.journal_entries entry_row
          JOIN etms.journal_lines line_row
            ON line_row.journal_entry_id = entry_row.id
         WHERE entry_row.journal_batch_id = NEW.id
         GROUP BY entry_row.currency_code
    LOOP
        IF currency_row.debit_total <= 0
           OR currency_row.debit_total IS DISTINCT FROM currency_row.credit_total THEN
            RAISE EXCEPTION 'Journal batch is unbalanced in transaction currency %',
                currency_row.currency_code USING ERRCODE = '23514';
        END IF;
    END LOOP;

    SELECT sum(line_row.base_debit_amount), sum(line_row.base_credit_amount),
           count(*) FILTER (
               WHERE account_row.organization_id IS DISTINCT FROM NEW.organization_id
                  OR (center_row.id IS NOT NULL
                      AND center_row.organization_id IS DISTINCT FROM NEW.organization_id)
           ),
           count(*) FILTER (
               WHERE (
                   entry_row.currency_code = period_row.base_currency_code
                   AND (
                       entry_row.exchange_rate IS DISTINCT FROM 1::numeric
                       OR abs(line_row.base_debit_amount - line_row.debit_amount) > 0.0001
                       OR abs(line_row.base_credit_amount - line_row.credit_amount) > 0.0001
                   )
               ) OR (
                   entry_row.currency_code <> period_row.base_currency_code
                   AND (
                       entry_row.exchange_rate IS NULL OR entry_row.exchange_rate <= 0
                       OR abs(
                           line_row.base_debit_amount
                           - round(line_row.debit_amount * entry_row.exchange_rate, 4)
                       ) > 0.0001
                       OR abs(
                           line_row.base_credit_amount
                           - round(line_row.credit_amount * entry_row.exchange_rate, 4)
                       ) > 0.0001
                   )
               )
           )
      INTO base_debit_total, base_credit_total, invalid_account_count,
           invalid_exchange_count
      FROM etms.journal_entries entry_row
      JOIN etms.journal_lines line_row
        ON line_row.journal_entry_id = entry_row.id
      JOIN etms.gl_accounts account_row ON account_row.id = line_row.gl_account_id
      LEFT JOIN etms.cost_centers center_row ON center_row.id = line_row.cost_center_id
     WHERE entry_row.journal_batch_id = NEW.id;

    IF invalid_account_count > 0 THEN
        RAISE EXCEPTION 'Journal line account or cost center belongs to another organization'
            USING ERRCODE = '23514';
    END IF;
    IF invalid_exchange_count > 0 THEN
        RAISE EXCEPTION 'Journal entry exchange rate or base-currency line amounts are inconsistent (tolerance 0.0001)'
            USING ERRCODE = '23514';
    END IF;
    IF base_debit_total <= 0
       OR base_debit_total IS DISTINCT FROM base_credit_total THEN
        RAISE EXCEPTION 'Journal batch base-currency debits and credits must be equal and positive'
            USING ERRCODE = '23514';
    END IF;
    IF NEW.total_debit IS DISTINCT FROM base_debit_total
       OR NEW.total_credit IS DISTINCT FROM base_credit_total THEN
        RAISE EXCEPTION 'Journal batch header totals must equal base-currency line totals'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

-- ---------------------------------------------------------------------------
-- Payment/COD combined cap, claim status control, and linked-journal stability.
-- ---------------------------------------------------------------------------

DO $block$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
         WHERE conrelid = 'etms.claim_settlements'::regclass
           AND conname = 'ck_claim_settlement_status_05'
    ) THEN
        ALTER TABLE etms.claim_settlements
            ADD CONSTRAINT ck_claim_settlement_status_05 CHECK (
                status IN (
                    'DRAFT','PROPOSED','AGREED','APPROVED','PARTIALLY_PAID',
                    'PAID','SETTLED','DISPUTED','REJECTED','CANCELLED',
                    'VOID','REVERSED'
                )
            );
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
         WHERE conrelid = 'etms.payments'::regclass
           AND conname = 'ck_payments_status_05'
    ) THEN
        ALTER TABLE etms.payments
            ADD CONSTRAINT ck_payments_status_05 CHECK (
                status IN (
                    'PENDING','PROCESSING','COMPLETED','SETTLED','FAILED',
                    'CANCELLED','RETURNED','REVERSED'
                )
            );
    END IF;
END;
$block$;

CREATE OR REPLACE FUNCTION etms.validate_claim_settlement_status_transition()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    old_status text := upper(OLD.status);
    new_status text := upper(NEW.status);
    allowed boolean;
BEGIN
    IF new_status = old_status THEN RETURN NEW; END IF;
    allowed :=
        (old_status = 'DRAFT' AND new_status IN ('PROPOSED','AGREED','REJECTED','CANCELLED','VOID')) OR
        (old_status = 'PROPOSED' AND new_status IN ('AGREED','APPROVED','REJECTED','CANCELLED','VOID')) OR
        (old_status = 'AGREED' AND new_status IN ('APPROVED','PARTIALLY_PAID','PAID','SETTLED','DISPUTED','CANCELLED','VOID')) OR
        (old_status = 'APPROVED' AND new_status IN ('PARTIALLY_PAID','PAID','SETTLED','DISPUTED','CANCELLED','VOID')) OR
        (old_status = 'PARTIALLY_PAID' AND new_status IN ('PAID','SETTLED','DISPUTED','REVERSED')) OR
        (old_status = 'DISPUTED' AND new_status IN ('AGREED','APPROVED','CANCELLED','VOID')) OR
        (old_status IN ('PAID','SETTLED') AND new_status = 'REVERSED');
    IF NOT allowed THEN
        RAISE EXCEPTION 'Invalid claim settlement status transition: % -> %',
            OLD.status, NEW.status USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_05_claim_settlement_status ON etms.claim_settlements;
CREATE TRIGGER trg_05_claim_settlement_status
    BEFORE UPDATE OF status ON etms.claim_settlements
    FOR EACH ROW EXECUTE PROCEDURE etms.validate_claim_settlement_status_transition();
DROP TRIGGER IF EXISTS trg_05_require_claim_reversal_journal ON etms.claim_settlements;
CREATE TRIGGER trg_05_require_claim_reversal_journal
    BEFORE INSERT OR UPDATE OF status ON etms.claim_settlements
    FOR EACH ROW EXECUTE PROCEDURE etms.require_posted_financial_journal(
        'CLAIM_SETTLEMENT','status','REVERSED','settlement_amount','currency_code','REVERSAL'
    );

CREATE OR REPLACE FUNCTION etms.validate_payment_application_sum()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    target_payment_id uuid;
    payment_total numeric(20,4);
    application_total numeric(30,4);
    cod_total numeric(30,4);
BEGIN
    target_payment_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.payment_id ELSE NEW.payment_id END;
    SELECT payment_amount INTO payment_total
      FROM etms.payments WHERE id = target_payment_id FOR UPDATE;
    SELECT COALESCE(sum(applied_amount), 0) INTO application_total
      FROM etms.payment_applications WHERE payment_id = target_payment_id;
    SELECT COALESCE(sum(collected_amount), 0) INTO cod_total
      FROM etms.cash_on_delivery_collections
     WHERE payment_id = target_payment_id AND status = 'REMITTED';
    IF application_total + cod_total > payment_total THEN
        RAISE EXCEPTION 'Payment applications plus COD remittances exceed the payment amount'
            USING ERRCODE = '23514';
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
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
    application_total numeric(30,4);
    cod_total numeric(30,4);
    mismatched_currency_count integer;
    invalid_cod_count integer;
BEGIN
    SELECT COALESCE(sum(applied_amount), 0) INTO application_total
      FROM etms.payment_applications WHERE payment_id = NEW.id;
    SELECT COALESCE(sum(collected_amount), 0),
           count(*) FILTER (
               WHERE currency_code IS DISTINCT FROM NEW.currency_code
                  OR NEW.payment_type NOT IN ('INBOUND','OFFSET')
                  OR upper(NEW.status) NOT IN ('COMPLETED','SETTLED')
                  OR NEW.payer_partner_id IS DISTINCT FROM
                     COALESCE(collecting_partner_id, payer_partner_id)
           )
      INTO cod_total, invalid_cod_count
      FROM etms.cash_on_delivery_collections
     WHERE payment_id = NEW.id AND status = 'REMITTED';
    IF application_total + cod_total > NEW.payment_amount THEN
        RAISE EXCEPTION 'Payment amount is lower than applications plus COD remittances'
            USING ERRCODE = '23514';
    END IF;
    SELECT count(*) INTO mismatched_currency_count
      FROM etms.payment_applications application_row
      LEFT JOIN etms.invoices invoice_row ON invoice_row.id = application_row.invoice_id
      LEFT JOIN etms.settlements settlement_row ON settlement_row.id = application_row.settlement_id
      LEFT JOIN etms.claim_settlements claim_row ON claim_row.id = application_row.claim_settlement_id
     WHERE application_row.payment_id = NEW.id
       AND COALESCE(
               invoice_row.currency_code,
               settlement_row.currency_code,
               claim_row.currency_code
           ) IS DISTINCT FROM NEW.currency_code;
    IF mismatched_currency_count > 0 OR invalid_cod_count > 0 THEN
        RAISE EXCEPTION 'Payment currency/type/status/party conflicts with applications or COD remittances'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_validate_payment_header_update ON etms.payments;
CREATE TRIGGER trg_validate_payment_header_update
    BEFORE UPDATE OF payment_amount, currency_code, payment_type, status,
        payer_partner_id, payee_partner_id
    ON etms.payments
    FOR EACH ROW EXECUTE PROCEDURE etms.validate_payment_header_after_update();

CREATE OR REPLACE FUNCTION etms.protect_linked_journal_batch_status()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
BEGIN
    IF OLD.status = 'POSTED' AND NEW.status <> 'POSTED' AND EXISTS (
        SELECT 1
          FROM etms.financial_journal_links link_row
          JOIN etms.journal_entries entry_row
            ON entry_row.id = link_row.journal_entry_id
           AND entry_row.tenant_id = link_row.tenant_id
         WHERE entry_row.journal_batch_id = OLD.id
           AND link_row.link_role IN ('POSTING','REVERSAL')
    ) THEN
        RAISE EXCEPTION 'A linked posted journal batch must remain POSTED; create a separate reversal batch'
            USING ERRCODE = '55000';
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_05_protect_linked_journal_batch_status ON etms.journal_batches;
CREATE TRIGGER trg_05_protect_linked_journal_batch_status
    BEFORE UPDATE OF status ON etms.journal_batches
    FOR EACH ROW EXECUTE PROCEDURE etms.protect_linked_journal_batch_status();

-- ---------------------------------------------------------------------------
-- Least-privilege closure for objects introduced or replaced by this migration.
-- ---------------------------------------------------------------------------

REVOKE ALL ON TABLE etms.financial_journal_links FROM PUBLIC;
REVOKE ALL ON FUNCTION etms.validate_financial_journal_link() FROM PUBLIC;
REVOKE ALL ON FUNCTION etms.require_posted_financial_journal() FROM PUBLIC;
REVOKE ALL ON FUNCTION etms.validate_journal_batch_posting() FROM PUBLIC;
REVOKE ALL ON FUNCTION etms.validate_extended_finance_status_transition() FROM PUBLIC;
REVOKE ALL ON FUNCTION etms.validate_extended_financial_totals() FROM PUBLIC;
REVOKE ALL ON FUNCTION etms.prevent_locked_financial_child_mutation() FROM PUBLIC;
REVOKE ALL ON FUNCTION etms.protect_bank_statement_line() FROM PUBLIC;
REVOKE ALL ON FUNCTION etms.validate_bank_reconciliation_match() FROM PUBLIC;
REVOKE ALL ON FUNCTION etms.validate_claim_settlement_integrity() FROM PUBLIC;
REVOKE ALL ON FUNCTION etms.validate_claim_header_settlement_cap() FROM PUBLIC;
REVOKE ALL ON FUNCTION etms.validate_claim_settlement_status_transition() FROM PUBLIC;
REVOKE ALL ON FUNCTION etms.validate_cod_collection_integrity() FROM PUBLIC;
REVOKE ALL ON FUNCTION etms.validate_payment_application_sum() FROM PUBLIC;
REVOKE ALL ON FUNCTION etms.validate_payment_header_after_update() FROM PUBLIC;
REVOKE ALL ON FUNCTION etms.protect_linked_journal_batch_status() FROM PUBLIC;

COMMENT ON TABLE etms.financial_journal_links IS
    'Append-only tenant-scoped link from finalized financial entities to posted, balanced journal entries.';
