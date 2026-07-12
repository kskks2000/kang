-- DEIMS enterprise WMS schema - operational integrity, RLS, indexes, and baseline seeds.
-- PostgreSQL 11 compatible. Applied last, after all 00-10 modules, in one transaction.

CREATE OR REPLACE FUNCTION deims.prevent_tenant_change()
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

CREATE OR REPLACE FUNCTION deims.enforce_same_tenant_fk()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, deims
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
        RAISE EXCEPTION 'Referenced parent is unavailable in the active tenant: %.% -> %.%',
            TG_TABLE_SCHEMA, TG_TABLE_NAME, TG_ARGV[1], TG_ARGV[2]
            USING ERRCODE = '23503';
    END IF;

    -- A NULL parent tenant denotes an explicitly global reference master.
    IF parent_tenant IS NOT NULL AND parent_tenant IS DISTINCT FROM NEW.tenant_id THEN
        RAISE EXCEPTION 'Cross-tenant reference rejected: %.% -> %.%',
            TG_TABLE_SCHEMA, TG_TABLE_NAME, TG_ARGV[1], TG_ARGV[2]
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

-- This deliberately replaces the 07 helper and removes its client-settable maintenance bypass.
-- Exceptional maintenance must disable a trigger under an audited DBA procedure instead.
CREATE OR REPLACE FUNCTION deims.block_immutable_change()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    RAISE EXCEPTION '%.% is append-only; create a correction, reversal, or new version instead of %',
        TG_TABLE_SCHEMA, TG_TABLE_NAME, TG_OP
        USING ERRCODE = '55000';
END;
$function$;

CREATE OR REPLACE FUNCTION deims.prevent_append_only_change()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    RAISE EXCEPTION '%.% is append-only; create a correction, reversal, or new event instead of %',
        TG_TABLE_SCHEMA, TG_TABLE_NAME, TG_OP
        USING ERRCODE = '55000';
END;
$function$;

CREATE OR REPLACE FUNCTION deims.protect_message_core()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    old_core jsonb;
    new_core jsonb;
    argument_no integer;
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION '%.% message/envelope rows cannot be deleted', TG_TABLE_SCHEMA, TG_TABLE_NAME
            USING ERRCODE = '55000';
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
        RAISE EXCEPTION 'Immutable message/envelope content changed on %.%',
            TG_TABLE_SCHEMA, TG_TABLE_NAME USING ERRCODE = '55000';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION deims.protect_finalized_row()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, deims
AS $function$
DECLARE
    old_status text;
    new_status text;
    terminal_statuses text[];
BEGIN
    old_status := to_jsonb(OLD) ->> TG_ARGV[0];
    new_status := CASE WHEN TG_OP = 'UPDATE' THEN to_jsonb(NEW) ->> TG_ARGV[0] ELSE NULL END;
    terminal_statuses := string_to_array(TG_ARGV[1], ',');
    IF TG_TABLE_NAME = 'settlements' AND TG_OP = 'UPDATE' THEN
        IF deims.finance_projection_authorized('PAYMENT_APPLICATION') THEN
            RETURN NEW;
        END IF;
        IF old_status = 'PAID' AND new_status = 'CLOSED' THEN
            RETURN NEW;
        END IF;
    END IF;
    IF old_status = ANY (terminal_statuses) THEN
        RAISE EXCEPTION 'Finalized %.% row with %=% is immutable; use reversal/correction records',
            TG_TABLE_SCHEMA, TG_TABLE_NAME, TG_ARGV[0], old_status
            USING ERRCODE = '55000';
    END IF;
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION deims.protect_committed_row()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, deims
AS $function$
DECLARE
    old_status text;
    new_status text;
    progression text[];
    old_position integer;
    new_position integer;
    mutable_columns text[];
    mutable_column text;
    old_core jsonb;
    new_core jsonb;
BEGIN
    IF TG_OP = 'INSERT' THEN
        new_status := to_jsonb(NEW) ->> TG_ARGV[0];
        progression := string_to_array(TG_ARGV[1], ',');
        IF array_position(progression, new_status) IS NOT NULL THEN
            RAISE EXCEPTION '%.% must be created before its committed processing states',
                TG_TABLE_SCHEMA, TG_TABLE_NAME USING ERRCODE = '23514';
        END IF;
        RETURN NEW;
    END IF;
    old_status := to_jsonb(OLD) ->> TG_ARGV[0];
    new_status := CASE WHEN TG_OP = 'DELETE' THEN NULL ELSE to_jsonb(NEW) ->> TG_ARGV[0] END;
    progression := string_to_array(TG_ARGV[1], ',');
    IF TG_TABLE_NAME = 'settlements' AND TG_OP = 'UPDATE'
       AND deims.finance_projection_authorized('PAYMENT_APPLICATION') THEN
        old_core := to_jsonb(OLD) - 'status' - 'row_version' - 'updated_at';
        new_core := to_jsonb(NEW) - 'status' - 'row_version' - 'updated_at';
        IF old_core IS DISTINCT FROM new_core THEN
            RAISE EXCEPTION 'Authorized settlement payment projection may change only projection fields'
                USING ERRCODE = '55000';
        END IF;
        RETURN NEW;
    END IF;
    old_position := array_position(progression, old_status);
    IF old_position IS NULL THEN
        new_position := array_position(progression, new_status);
        IF new_position IS NOT NULL AND new_position <> 1 THEN
            RAISE EXCEPTION '%.% must enter committed processing at %, not %',
                TG_TABLE_SCHEMA, TG_TABLE_NAME, progression[1], new_status
                USING ERRCODE = '23514';
        END IF;
        IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
        RETURN NEW;
    END IF;
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'Committed %.% row cannot be deleted', TG_TABLE_SCHEMA, TG_TABLE_NAME
            USING ERRCODE = '55000';
    END IF;

    new_position := array_position(progression, new_status);
    IF new_position IS NULL OR new_position < old_position THEN
        RAISE EXCEPTION 'Committed %.% status cannot move backward from % to %',
            TG_TABLE_SCHEMA, TG_TABLE_NAME, old_status, new_status
            USING ERRCODE = '23514';
    END IF;

    old_core := to_jsonb(OLD);
    new_core := to_jsonb(NEW);
    mutable_columns := string_to_array(TG_ARGV[2], ',');
    FOREACH mutable_column IN ARRAY mutable_columns LOOP
        old_core := old_core - mutable_column;
        new_core := new_core - mutable_column;
    END LOOP;
    IF old_core IS DISTINCT FROM new_core THEN
        RAISE EXCEPTION 'Committed %.% core fields are immutable', TG_TABLE_SCHEMA, TG_TABLE_NAME
            USING ERRCODE = '55000';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION deims.protect_versioned_filing_aggregate()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, deims
AS $function$
DECLARE
    old_status text;
    new_status text;
    protected_statuses text[];
    mutable_columns text[];
    mutable_column text;
    old_core jsonb;
    new_core jsonb;
    old_version_id uuid;
    new_version_id uuid;
    new_version_no integer;
    stored_version_no integer;
    filing_action text;
    supersedes_version_id uuid;
    sealed_at timestamptz;
    aggregate_id uuid;
    entering_protected_state boolean;
    selected_row_count bigint;
BEGIN
    IF TG_OP = 'INSERT' THEN
        new_status := to_jsonb(NEW) ->> TG_ARGV[0];
        protected_statuses := string_to_array(TG_ARGV[1], ',');
        IF new_status = ANY (protected_statuses) THEN
            RAISE EXCEPTION 'Filing aggregate must be created in a pre-filing state before a sealed version is attached'
                USING ERRCODE = '23514';
        END IF;
        RETURN NEW;
    END IF;
    old_status := to_jsonb(OLD) ->> TG_ARGV[0];
    protected_statuses := string_to_array(TG_ARGV[1], ',');
    IF TG_OP = 'DELETE' THEN
        IF old_status = ANY (protected_statuses) THEN
            RAISE EXCEPTION 'Filed %.% aggregate cannot be deleted', TG_TABLE_SCHEMA, TG_TABLE_NAME
                USING ERRCODE = '55000';
        END IF;
        RETURN OLD;
    END IF;

    new_status := to_jsonb(NEW) ->> TG_ARGV[0];
    entering_protected_state := NOT (old_status = ANY (protected_statuses))
        AND new_status = ANY (protected_statuses);
    IF entering_protected_state AND new_status <> TG_ARGV[5] THEN
        RAISE EXCEPTION '%.% must enter filed processing at %, not %',
            TG_TABLE_SCHEMA, TG_TABLE_NAME, TG_ARGV[5], new_status
            USING ERRCODE = '23514';
    END IF;
    IF NOT (old_status = ANY (protected_statuses)) AND NOT entering_protected_state THEN
        RETURN NEW;
    END IF;
    IF old_status = ANY (protected_statuses)
       AND NOT (new_status = ANY (protected_statuses)) THEN
        RAISE EXCEPTION 'Filed %.% cannot return from % to pre-filing status %',
            TG_TABLE_SCHEMA, TG_TABLE_NAME, old_status, new_status
            USING ERRCODE = '23514';
    END IF;

    IF NOT entering_protected_state THEN
        old_core := to_jsonb(OLD);
        new_core := to_jsonb(NEW);
        mutable_columns := string_to_array(TG_ARGV[4], ',');
        FOREACH mutable_column IN ARRAY mutable_columns LOOP
            old_core := old_core - mutable_column;
            new_core := new_core - mutable_column;
        END LOOP;
        IF old_core IS DISTINCT FROM new_core THEN
            RAISE EXCEPTION 'Filed %.% identity/scope/source fields are immutable',
                TG_TABLE_SCHEMA, TG_TABLE_NAME USING ERRCODE = '55000';
        END IF;
    END IF;

    old_version_id := OLD.current_version_id;
    new_version_id := NEW.current_version_id;
    new_version_no := NEW.current_version_no;
    IF old_version_id IS NOT NULL AND new_version_id IS NULL THEN
        RAISE EXCEPTION 'Filed aggregate current version cannot be cleared'
            USING ERRCODE = '23514';
    END IF;

    IF entering_protected_state
       OR new_version_id IS DISTINCT FROM old_version_id
       OR new_version_no IS DISTINCT FROM OLD.current_version_no THEN
        EXECUTE format(
            'SELECT version_no, filing_action, supersedes_version_id, sealed_at, %I '
            'FROM deims.%I WHERE id = $1 FOR SHARE',
            TG_ARGV[3], TG_ARGV[2]
        ) INTO stored_version_no, filing_action, supersedes_version_id, sealed_at, aggregate_id
          USING new_version_id;
        GET DIAGNOSTICS selected_row_count = ROW_COUNT;
        IF selected_row_count = 0 OR aggregate_id IS DISTINCT FROM NEW.id
           OR stored_version_no IS DISTINCT FROM new_version_no
           OR sealed_at IS NULL THEN
            RAISE EXCEPTION 'Current filing version must be sealed and belong to the same aggregate/version number'
                USING ERRCODE = '23514';
        END IF;
        IF entering_protected_state OR old_version_id IS NULL THEN
            IF filing_action <> 'ORIGINAL' OR supersedes_version_id IS NOT NULL THEN
                RAISE EXCEPTION 'First aggregate version must be an ORIGINAL without a superseded version'
                    USING ERRCODE = '23514';
            END IF;
        ELSIF filing_action NOT IN (
                  'CORRECTION','CANCELLATION','WITHDRAWAL','RESUBMISSION','OFFICIAL_CORRECTION'
              )
              OR supersedes_version_id IS DISTINCT FROM old_version_id THEN
            RAISE EXCEPTION 'Replacement filing version must explicitly supersede the prior current version'
                USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION deims.protect_child_when_parent_final()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, deims
AS $function$
DECLARE
    old_parent_id uuid;
    new_parent_id uuid;
    parent_status text;
    terminal_statuses text[];
BEGIN
    IF TG_OP <> 'INSERT' THEN
        old_parent_id := NULLIF(to_jsonb(OLD) ->> TG_ARGV[0], '')::uuid;
    END IF;
    IF TG_OP <> 'DELETE' THEN
        new_parent_id := NULLIF(to_jsonb(NEW) ->> TG_ARGV[0], '')::uuid;
    END IF;

    terminal_statuses := string_to_array(TG_ARGV[3], ',');
    IF old_parent_id IS NOT NULL THEN
        EXECUTE format('SELECT %I::text FROM deims.%I WHERE id = $1 FOR SHARE', TG_ARGV[2], TG_ARGV[1])
           INTO parent_status
           USING old_parent_id;
        IF parent_status = ANY (terminal_statuses) THEN
            RAISE EXCEPTION 'Child %.% cannot move from or change under finalized parent %.% (%)',
                TG_TABLE_SCHEMA, TG_TABLE_NAME, TG_ARGV[1], old_parent_id, parent_status
                USING ERRCODE = '55000';
        END IF;
    END IF;

    IF new_parent_id IS NOT NULL AND new_parent_id IS DISTINCT FROM old_parent_id THEN
        EXECUTE format('SELECT %I::text FROM deims.%I WHERE id = $1 FOR SHARE', TG_ARGV[2], TG_ARGV[1])
           INTO parent_status
           USING new_parent_id;
        IF parent_status = ANY (terminal_statuses) THEN
            RAISE EXCEPTION 'Child %.% cannot be added or moved under finalized parent %.% (%)',
                TG_TABLE_SCHEMA, TG_TABLE_NAME, TG_ARGV[1], new_parent_id, parent_status
                USING ERRCODE = '55000';
        END IF;
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION deims.validate_inventory_transaction_posting()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, deims
AS $function$
DECLARE
    entry_count integer;
BEGIN
    IF NEW.posting_status <> 'POSTED'
       OR (TG_OP = 'UPDATE' AND OLD.posting_status = 'POSTED') THEN
        RETURN NEW;
    END IF;

    SELECT count(*) INTO entry_count
      FROM deims.inventory_transaction_entries
     WHERE inventory_transaction_id = NEW.id;
    IF entry_count < 2 THEN
        RAISE EXCEPTION 'Posted inventory transaction % requires at least two entries', NEW.id
            USING ERRCODE = '23514';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM deims.inventory_transaction_entries e
        WHERE e.inventory_transaction_id = NEW.id
        GROUP BY e.item_id, e.base_uom_code
        HAVING abs(sum(e.signed_quantity)) > 0.00000001
    ) THEN
        RAISE EXCEPTION 'Inventory transaction % is not quantity-balanced by item/base UOM', NEW.id
            USING ERRCODE = '23514';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM deims.inventory_transaction_entries e
        JOIN deims.stock_buckets b ON b.id = e.stock_bucket_id
        WHERE e.inventory_transaction_id = NEW.id
           AND (
               e.tenant_id IS DISTINCT FROM NEW.tenant_id
               OR b.tenant_id IS DISTINCT FROM NEW.tenant_id
               OR (
                   NEW.transaction_type NOT IN ('TRANSFER','OWNER_TRANSFER','BONDED_MOVE')
                   AND (
                       b.warehouse_id IS DISTINCT FROM NEW.warehouse_id
                       OR b.owner_partner_id IS DISTINCT FROM NEW.owner_partner_id
                   )
               )
           )
    ) THEN
        RAISE EXCEPTION 'Inventory transaction % entries cross tenant, warehouse, or owner boundaries', NEW.id
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION deims.protect_journal_line_when_posted()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, deims
AS $function$
DECLARE
    old_entry_id uuid;
    new_entry_id uuid;
    batch_status text;
BEGIN
    IF TG_OP <> 'INSERT' THEN old_entry_id := OLD.journal_entry_id; END IF;
    IF TG_OP <> 'DELETE' THEN new_entry_id := NEW.journal_entry_id; END IF;

    IF old_entry_id IS NOT NULL THEN
        SELECT b.status INTO batch_status
          FROM deims.journal_entries e
          JOIN deims.journal_batches b ON b.id = e.journal_batch_id
         WHERE e.id = old_entry_id
         FOR SHARE OF e, b;
        IF batch_status IN ('POSTED','REVERSED','CANCELLED') THEN
            RAISE EXCEPTION 'Journal line cannot move from or change under a finalized batch'
                USING ERRCODE = '55000';
        END IF;
    END IF;

    IF new_entry_id IS NOT NULL AND new_entry_id IS DISTINCT FROM old_entry_id THEN
        SELECT b.status INTO batch_status
          FROM deims.journal_entries e
          JOIN deims.journal_batches b ON b.id = e.journal_batch_id
         WHERE e.id = new_entry_id
         FOR SHARE OF e, b;
        IF batch_status IN ('POSTED','REVERSED','CANCELLED') THEN
            RAISE EXCEPTION 'Journal line cannot be added or moved under a finalized batch'
                USING ERRCODE = '55000';
        END IF;
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION deims.protect_invoice_line_child_when_posted()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, deims
AS $function$
DECLARE
    old_line_id uuid;
    new_line_id uuid;
    invoice_status text;
BEGIN
    IF TG_OP <> 'INSERT' THEN old_line_id := OLD.invoice_line_id; END IF;
    IF TG_OP <> 'DELETE' THEN new_line_id := NEW.invoice_line_id; END IF;

    IF old_line_id IS NOT NULL THEN
        SELECT invoice.status INTO invoice_status
          FROM deims.invoice_lines line
          JOIN deims.invoices invoice ON invoice.id = line.invoice_id
         WHERE line.id = old_line_id
         FOR SHARE OF line, invoice;
        IF invoice_status IN ('POSTED','PARTIALLY_PAID','PAID','CANCELLED','REVERSED') THEN
            RAISE EXCEPTION 'Invoice line charge cannot move from or change under a posted invoice'
                USING ERRCODE = '55000';
        END IF;
    END IF;

    IF new_line_id IS NOT NULL AND new_line_id IS DISTINCT FROM old_line_id THEN
        SELECT invoice.status INTO invoice_status
          FROM deims.invoice_lines line
          JOIN deims.invoices invoice ON invoice.id = line.invoice_id
         WHERE line.id = new_line_id
         FOR SHARE OF line, invoice;
        IF invoice_status IN ('POSTED','PARTIALLY_PAID','PAID','CANCELLED','REVERSED') THEN
            RAISE EXCEPTION 'Invoice line charge cannot be added or moved under a posted invoice'
                USING ERRCODE = '55000';
        END IF;
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION deims.validate_journal_batch_posting()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, deims
AS $function$
DECLARE
    period_row record;
    line_count bigint;
    calculated_debit numeric(20,4);
    calculated_credit numeric(20,4);
BEGIN
    IF NEW.status <> 'POSTED' THEN
        RETURN NEW;
    END IF;
    IF TG_OP = 'UPDATE' AND OLD.status = 'POSTED' THEN
        RETURN NEW;
    END IF;

    SELECT tenant_id, organization_id, start_date, end_date, status
      INTO period_row
     FROM deims.accounting_periods
     WHERE id = NEW.accounting_period_id
     FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Journal batch accounting period does not exist'
            USING ERRCODE = '23503';
    END IF;
    IF period_row.tenant_id IS DISTINCT FROM NEW.tenant_id
       OR period_row.organization_id IS DISTINCT FROM NEW.organization_id
       OR NEW.accounting_date NOT BETWEEN period_row.start_date AND period_row.end_date
       OR period_row.status NOT IN ('OPEN','REOPENED') THEN
        RAISE EXCEPTION 'Journal batch accounting period is unavailable, closed, or outside scope/date'
            USING ERRCODE = '23514';
    END IF;

    IF NEW.posted_by IS NULL OR NEW.posted_at IS NULL THEN
        RAISE EXCEPTION 'Posted journal batch requires posted_by and posted_at'
            USING ERRCODE = '23514';
    END IF;

    IF EXISTS (
        SELECT 1
          FROM deims.journal_entries entry
          JOIN deims.journal_lines line ON line.journal_entry_id = entry.id
          JOIN deims.gl_accounts account ON account.id = line.gl_account_id
         WHERE entry.journal_batch_id = NEW.id
           AND (
               entry.tenant_id IS DISTINCT FROM NEW.tenant_id
               OR line.tenant_id IS DISTINCT FROM NEW.tenant_id
               OR account.tenant_id IS DISTINCT FROM NEW.tenant_id
               OR account.organization_id IS DISTINCT FROM NEW.organization_id
               OR NOT account.is_active
               OR (
                   line.currency_code IS DISTINCT FROM NEW.currency_code
                   AND (
                       line.exchange_rate IS NULL
                       OR (line.debit_amount > 0 AND line.base_debit_amount IS NULL)
                       OR (line.credit_amount > 0 AND line.base_credit_amount IS NULL)
                   )
               )
           )
    ) THEN
        RAISE EXCEPTION 'Journal batch contains a cross-scope, inactive-account, or unconverted line'
            USING ERRCODE = '23514';
    END IF;

    SELECT count(*),
           COALESCE(sum(
               CASE WHEN line.currency_code = NEW.currency_code
                    THEN line.debit_amount ELSE line.base_debit_amount END
           ), 0),
           COALESCE(sum(
               CASE WHEN line.currency_code = NEW.currency_code
                    THEN line.credit_amount ELSE line.base_credit_amount END
           ), 0)
      INTO line_count, calculated_debit, calculated_credit
      FROM deims.journal_entries entry
      JOIN deims.journal_lines line ON line.journal_entry_id = entry.id
     WHERE entry.journal_batch_id = NEW.id;

    IF line_count < 2 OR calculated_debit <= 0 OR calculated_debit <> calculated_credit THEN
        RAISE EXCEPTION 'Posted journal batch requires at least two balanced non-zero lines'
            USING ERRCODE = '23514';
    END IF;
    IF NEW.total_debit IS DISTINCT FROM calculated_debit
       OR NEW.total_credit IS DISTINCT FROM calculated_credit THEN
        RAISE EXCEPTION 'Journal batch header totals do not match line totals (% debit, % credit)',
            calculated_debit, calculated_credit USING ERRCODE = '23514';
    END IF;

    IF EXISTS (
        SELECT 1
          FROM deims.journal_entries entry
          LEFT JOIN deims.journal_lines line ON line.journal_entry_id = entry.id
         WHERE entry.journal_batch_id = NEW.id
         GROUP BY entry.id
        HAVING count(line.id) < 2
            OR COALESCE(sum(
                   CASE WHEN line.currency_code = NEW.currency_code
                        THEN line.debit_amount ELSE line.base_debit_amount END
               ), 0) IS DISTINCT FROM
               COALESCE(sum(
                   CASE WHEN line.currency_code = NEW.currency_code
                        THEN line.credit_amount ELSE line.base_credit_amount END
               ), 0)
    ) THEN
        RAISE EXCEPTION 'Each journal entry must balance independently in batch currency'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION deims.validate_invoice_posting()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, deims
AS $function$
DECLARE
    line_count bigint;
    line_net numeric(20,4);
    line_tax numeric(20,4);
    line_gross numeric(20,4);
    tax_detail_count bigint;
    tax_detail_total numeric(20,4);
BEGIN
    IF TG_OP = 'INSERT' AND NEW.status <> 'DRAFT' THEN
        RAISE EXCEPTION 'Invoice must be created in DRAFT status'
            USING ERRCODE = '23514';
    END IF;
    IF TG_OP = 'INSERT'
       AND (NEW.paid_amount <> 0 OR NEW.outstanding_amount IS DISTINCT FROM NEW.gross_amount) THEN
        RAISE EXCEPTION 'A new invoice must be fully outstanding with no paid amount'
            USING ERRCODE = '23514';
    END IF;
    IF TG_OP = 'UPDATE'
       AND deims.finance_projection_authorized('PAYMENT_APPLICATION') THEN
        RETURN NEW;
    END IF;
    IF NEW.status <> 'POSTED' THEN
        RETURN NEW;
    END IF;
    IF TG_OP = 'UPDATE' AND OLD.status = 'POSTED' THEN
        RETURN NEW;
    END IF;
    IF NEW.posted_at IS NULL OR NEW.approval_status NOT IN ('NOT_REQUIRED','APPROVED') THEN
        RAISE EXCEPTION 'Posted invoice requires posted_at and an approved/not-required approval state'
            USING ERRCODE = '23514';
    END IF;
    IF NEW.paid_amount <> 0 OR NEW.outstanding_amount IS DISTINCT FROM NEW.gross_amount THEN
        RAISE EXCEPTION 'A newly posted invoice must be fully outstanding with no paid amount'
            USING ERRCODE = '23514';
    END IF;

    IF EXISTS (
        SELECT 1 FROM deims.invoice_lines line
         WHERE line.invoice_id = NEW.id
           AND line.tenant_id IS DISTINCT FROM NEW.tenant_id
    ) OR EXISTS (
        SELECT 1 FROM deims.invoice_taxes tax
         WHERE tax.invoice_id = NEW.id
           AND tax.tenant_id IS DISTINCT FROM NEW.tenant_id
    ) THEN
        RAISE EXCEPTION 'Invoice details cross the invoice tenant boundary'
            USING ERRCODE = '23514';
    END IF;

    SELECT count(*),
           COALESCE(sum(net_amount - discount_amount), 0),
           COALESCE(sum(tax_amount), 0),
           COALESCE(sum(gross_amount), 0)
      INTO line_count, line_net, line_tax, line_gross
      FROM deims.invoice_lines
     WHERE invoice_id = NEW.id;
    IF line_count < 1
       OR NEW.net_amount IS DISTINCT FROM line_net
       OR NEW.tax_amount IS DISTINCT FROM line_tax
       OR NEW.gross_amount IS DISTINCT FROM line_gross THEN
        RAISE EXCEPTION 'Invoice header totals do not match its line details'
            USING ERRCODE = '23514';
    END IF;

    SELECT count(*), COALESCE(sum(tax_amount), 0)
      INTO tax_detail_count, tax_detail_total
      FROM deims.invoice_taxes
     WHERE invoice_id = NEW.id;
    IF (NEW.tax_amount > 0 AND tax_detail_count < 1)
       OR (tax_detail_count > 0 AND tax_detail_total IS DISTINCT FROM NEW.tax_amount) THEN
        RAISE EXCEPTION 'Invoice tax summary does not match invoice tax detail rows'
            USING ERRCODE = '23514';
    END IF;

    IF EXISTS (
        SELECT 1
          FROM deims.invoice_lines line
          LEFT JOIN deims.invoice_line_charges allocation
            ON allocation.invoice_line_id = line.id
           AND allocation.reversed_at IS NULL
         WHERE line.invoice_id = NEW.id
           AND EXISTS (
               SELECT 1
                 FROM deims.invoice_line_charges allocation_history
                WHERE allocation_history.invoice_line_id = line.id
           )
         GROUP BY line.id, line.net_amount, line.discount_amount, line.tax_amount, line.gross_amount
        HAVING COALESCE(sum(allocation.allocated_net_amount), 0)
                   IS DISTINCT FROM line.net_amount - line.discount_amount
            OR COALESCE(sum(allocation.allocated_tax_amount), 0)
                   IS DISTINCT FROM line.tax_amount
            OR COALESCE(sum(allocation.allocated_gross_amount), 0)
                   IS DISTINCT FROM line.gross_amount
    ) THEN
        RAISE EXCEPTION 'Every charge-backed invoice line must be fully covered by active charge allocations'
            USING ERRCODE = '23514';
    END IF;

    IF EXISTS (
        SELECT 1
          FROM deims.invoice_line_charges allocation
          JOIN deims.invoice_lines line ON line.id = allocation.invoice_line_id
          JOIN deims.charges charge ON charge.id = allocation.charge_id
         WHERE allocation.invoice_id = NEW.id
           AND allocation.reversed_at IS NULL
           AND (
               allocation.tenant_id IS DISTINCT FROM NEW.tenant_id
               OR line.invoice_id IS DISTINCT FROM NEW.id
               OR line.tenant_id IS DISTINCT FROM NEW.tenant_id
               OR charge.tenant_id IS DISTINCT FROM NEW.tenant_id
               OR charge.currency_code IS DISTINCT FROM NEW.currency_code
               OR charge.payee_partner_id IS DISTINCT FROM NEW.issuer_partner_id
               OR charge.payer_partner_id IS DISTINCT FROM NEW.recipient_partner_id
               OR line.charge_code_id IS DISTINCT FROM charge.charge_code_id
               OR NOT charge.billable
               OR charge.status NOT IN ('APPROVED','INVOICED')
               OR (NEW.invoice_type IN ('RECEIVABLE','DEBIT_NOTE') AND charge.direction <> 'RECEIVABLE')
               OR (NEW.invoice_type IN ('PAYABLE','CREDIT_NOTE') AND charge.direction <> 'PAYABLE')
           )
    ) THEN
        RAISE EXCEPTION 'Invoice has an invalid tenant, party, currency, direction or charge allocation'
            USING ERRCODE = '23514';
    END IF;
    IF EXISTS (
        SELECT 1
          FROM deims.invoice_line_charges allocation
          JOIN deims.settlement_lines settlement_line
            ON settlement_line.charge_id = allocation.charge_id
          JOIN deims.settlements settlement
            ON settlement.id = settlement_line.settlement_id
         WHERE allocation.invoice_id = NEW.id
           AND allocation.reversed_at IS NULL
           AND settlement.status NOT IN ('CANCELLED','REVERSED')
           AND settlement.invoice_id IS DISTINCT FROM NEW.id
    ) THEN
        RAISE EXCEPTION 'Invoice charge is already committed to a different/direct settlement'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION deims.protect_posted_invoice_core()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, deims
AS $function$
DECLARE
    old_core jsonb;
    new_core jsonb;
    application_total numeric(20,4);
    expected_status text;
    authorized boolean;
BEGIN
    IF TG_OP = 'DELETE' THEN
        IF OLD.status IN ('POSTED','PARTIALLY_PAID','PAID','CANCELLED','REVERSED')
           OR EXISTS (SELECT 1 FROM deims.payment_applications WHERE invoice_id = OLD.id) THEN
            RAISE EXCEPTION 'Posted or payment-linked invoice % cannot be deleted', OLD.id
                USING ERRCODE = '55000';
        END IF;
        RETURN OLD;
    END IF;

    SELECT COALESCE(sum(applied_amount), 0)
      INTO application_total
      FROM deims.payment_applications
     WHERE invoice_id = OLD.id AND reversed_at IS NULL;
    authorized := deims.finance_projection_authorized('PAYMENT_APPLICATION');
    IF authorized THEN
        old_core := to_jsonb(OLD)
            - 'paid_amount' - 'outstanding_amount' - 'status' - 'row_version' - 'updated_at';
        new_core := to_jsonb(NEW)
            - 'paid_amount' - 'outstanding_amount' - 'status' - 'row_version' - 'updated_at';
        expected_status := CASE
            WHEN application_total = 0 THEN 'POSTED'
            WHEN application_total < NEW.gross_amount THEN 'PARTIALLY_PAID'
            ELSE 'PAID'
        END;
        IF old_core IS DISTINCT FROM new_core
           OR application_total > NEW.gross_amount
           OR NEW.paid_amount IS DISTINCT FROM application_total
           OR NEW.outstanding_amount IS DISTINCT FROM NEW.gross_amount - application_total
           OR NEW.status <> expected_status THEN
            RAISE EXCEPTION 'Authorized invoice projection must exactly match active payment applications'
                USING ERRCODE = '23514';
        END IF;
        RETURN NEW;
    END IF;

    IF OLD.status IN ('POSTED','PARTIALLY_PAID','PAID','CANCELLED','REVERSED') THEN
        IF OLD.paid_amount IS DISTINCT FROM NEW.paid_amount
           OR OLD.outstanding_amount IS DISTINCT FROM NEW.outstanding_amount THEN
            RAISE EXCEPTION 'Invoice paid and outstanding amounts are maintained only by payment applications'
                USING ERRCODE = '55000';
        END IF;
    ELSIF NEW.paid_amount <> 0 OR NEW.outstanding_amount IS DISTINCT FROM NEW.gross_amount THEN
        RAISE EXCEPTION 'An unposted invoice must be fully outstanding with no paid amount'
            USING ERRCODE = '23514';
    END IF;
    IF OLD.status IS DISTINCT FROM NEW.status AND NEW.status IN ('PARTIALLY_PAID','PAID')
       AND NOT (
           OLD.status = 'POSTED' AND NEW.status = 'PAID'
           AND NEW.gross_amount = 0 AND NEW.paid_amount = 0
           AND NEW.outstanding_amount = 0 AND application_total = 0
       ) THEN
        RAISE EXCEPTION 'Invoice payment status is maintained only by payment applications'
            USING ERRCODE = '55000';
    END IF;
    IF OLD.status IS DISTINCT FROM NEW.status AND NOT (
        (OLD.status = 'DRAFT' AND NEW.status IN ('RECEIVED','VALIDATING','CANCELLED'))
        OR (OLD.status = 'RECEIVED' AND NEW.status IN ('VALIDATING','REJECTED','CANCELLED'))
        OR (OLD.status = 'VALIDATING' AND NEW.status IN ('REJECTED','APPROVAL_PENDING','APPROVED','CANCELLED'))
        OR (OLD.status = 'REJECTED' AND NEW.status IN ('VALIDATING','CANCELLED'))
        OR (OLD.status = 'APPROVAL_PENDING' AND NEW.status IN ('APPROVED','REJECTED','CANCELLED'))
        OR (OLD.status = 'APPROVED' AND NEW.status IN ('POSTED','CANCELLED'))
        OR (OLD.status = 'POSTED' AND NEW.status IN ('CANCELLED','REVERSED'))
        OR (OLD.status = 'POSTED' AND NEW.status = 'PAID'
            AND NEW.gross_amount = 0 AND NEW.paid_amount = 0
            AND NEW.outstanding_amount = 0 AND application_total = 0)
        OR (OLD.status = 'PARTIALLY_PAID' AND NEW.status IN ('CANCELLED','REVERSED'))
    ) THEN
        RAISE EXCEPTION 'Invalid invoice status transition from % to %', OLD.status, NEW.status
            USING ERRCODE = '23514';
    END IF;
    IF OLD.status IN ('PAID','CANCELLED','REVERSED') THEN
        RAISE EXCEPTION 'Final invoice % is immutable; use an explicit correction/reversal document', OLD.id
            USING ERRCODE = '55000';
    END IF;
    IF OLD.status NOT IN ('POSTED','PARTIALLY_PAID') THEN
        RETURN NEW;
    END IF;

    old_core := to_jsonb(OLD)
        - 'paid_amount' - 'outstanding_amount' - 'status' - 'cancelled_at'
        - 'row_version' - 'updated_at';
    new_core := to_jsonb(NEW)
        - 'paid_amount' - 'outstanding_amount' - 'status' - 'cancelled_at'
        - 'row_version' - 'updated_at';
    IF old_core IS DISTINCT FROM new_core THEN
        RAISE EXCEPTION 'Posted invoice identity, parties, dates, currency, approval, and totals are immutable'
            USING ERRCODE = '55000';
    END IF;
    IF NEW.status IN ('CANCELLED','REVERSED') AND application_total <> 0 THEN
        RAISE EXCEPTION 'Reverse all payment applications before cancelling or reversing an invoice'
            USING ERRCODE = '23514';
    END IF;
    IF (NEW.status = 'POSTED' AND (NEW.paid_amount <> 0 OR NEW.outstanding_amount <> NEW.gross_amount))
       OR (NEW.status = 'PARTIALLY_PAID' AND NOT (
               NEW.paid_amount > 0 AND NEW.paid_amount < NEW.gross_amount AND NEW.outstanding_amount > 0
           ))
       OR (NEW.status = 'PAID' AND NOT (
               NEW.paid_amount = NEW.gross_amount AND NEW.outstanding_amount = 0
           )) THEN
        RAISE EXCEPTION 'Invoice payment amounts are inconsistent with status %', NEW.status
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

-- Replace the 04 guard so changing inventory_transaction_id cannot move an entry out of a
-- posted/validated transaction before mutating it.
CREATE OR REPLACE FUNCTION deims.guard_inventory_entry_mutation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, deims
AS $function$
DECLARE
    old_transaction_status text;
    new_transaction_status text;
BEGIN
    IF TG_OP <> 'INSERT' THEN
        SELECT posting_status INTO old_transaction_status
          FROM deims.inventory_transaction_headers
         WHERE id = OLD.inventory_transaction_id
         FOR UPDATE;
        IF old_transaction_status IS DISTINCT FROM 'DRAFT' THEN
            RAISE EXCEPTION 'Entry cannot move from or change under a non-draft inventory transaction'
                USING ERRCODE = '55000';
        END IF;
    END IF;

    IF TG_OP = 'INSERT' THEN
        SELECT posting_status INTO new_transaction_status
          FROM deims.inventory_transaction_headers
         WHERE id = NEW.inventory_transaction_id
         FOR UPDATE;
        IF new_transaction_status IS DISTINCT FROM 'DRAFT' THEN
            RAISE EXCEPTION 'Entry cannot be added or moved under a non-draft inventory transaction'
                USING ERRCODE = '55000';
        END IF;
    ELSIF TG_OP = 'UPDATE'
          AND NEW.inventory_transaction_id IS DISTINCT FROM OLD.inventory_transaction_id THEN
        SELECT posting_status INTO new_transaction_status
          FROM deims.inventory_transaction_headers
         WHERE id = NEW.inventory_transaction_id
         FOR UPDATE;
        IF new_transaction_status IS DISTINCT FROM 'DRAFT' THEN
            RAISE EXCEPTION 'Entry cannot be added or moved under a non-draft inventory transaction'
                USING ERRCODE = '55000';
        END IF;
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$function$;

-- Replace the 07 helpers so a client-settable custom GUC cannot bypass sealed declarations.
CREATE OR REPLACE FUNCTION deims.protect_customs_declaration_version()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    IF OLD.sealed_at IS NOT NULL THEN
        RAISE EXCEPTION 'Sealed customs declaration version % is immutable', OLD.id
            USING ERRCODE = '55000';
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION deims.protect_customs_version_child()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, deims
AS $function$
DECLARE
    old_version_id uuid;
    new_version_id uuid;
    version_sealed_at timestamptz;
BEGIN
    IF TG_OP <> 'INSERT' THEN
        old_version_id := NULLIF(to_jsonb(OLD) ->> 'declaration_version_id', '')::uuid;
    END IF;
    IF TG_OP <> 'DELETE' THEN
        new_version_id := NULLIF(to_jsonb(NEW) ->> 'declaration_version_id', '')::uuid;
    END IF;

    IF old_version_id IS NOT NULL THEN
        SELECT sealed_at INTO version_sealed_at
          FROM deims.customs_declaration_versions
         WHERE id = old_version_id
         FOR SHARE;
        IF version_sealed_at IS NOT NULL THEN
            RAISE EXCEPTION 'Child cannot move from or change under sealed customs version %', old_version_id
                USING ERRCODE = '55000';
        END IF;
    END IF;

    IF new_version_id IS NOT NULL AND new_version_id IS DISTINCT FROM old_version_id THEN
        SELECT sealed_at INTO version_sealed_at
          FROM deims.customs_declaration_versions
         WHERE id = new_version_id
         FOR SHARE;
        IF version_sealed_at IS NOT NULL THEN
            RAISE EXCEPTION 'Child cannot be added or moved under sealed customs version %', new_version_id
                USING ERRCODE = '55000';
        END IF;
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION deims.protect_sealed_version()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    IF OLD.sealed_at IS NOT NULL THEN
        RAISE EXCEPTION 'Sealed %.% version % is immutable', TG_TABLE_SCHEMA, TG_TABLE_NAME, OLD.id
            USING ERRCODE = '55000';
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION deims.protect_child_when_parent_sealed()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, deims
AS $function$
DECLARE
    old_parent_id uuid;
    new_parent_id uuid;
    parent_sealed_at timestamptz;
BEGIN
    IF TG_OP <> 'INSERT' THEN
        old_parent_id := NULLIF(to_jsonb(OLD) ->> TG_ARGV[0], '')::uuid;
    END IF;
    IF TG_OP <> 'DELETE' THEN
        new_parent_id := NULLIF(to_jsonb(NEW) ->> TG_ARGV[0], '')::uuid;
    END IF;

    IF old_parent_id IS NOT NULL THEN
        EXECUTE format('SELECT sealed_at FROM deims.%I WHERE id = $1 FOR SHARE', TG_ARGV[1])
           INTO parent_sealed_at
           USING old_parent_id;
        IF parent_sealed_at IS NOT NULL THEN
            RAISE EXCEPTION 'Child cannot move from or change under sealed deims.% version %',
                TG_ARGV[1], old_parent_id USING ERRCODE = '55000';
        END IF;
    END IF;

    IF new_parent_id IS NOT NULL AND new_parent_id IS DISTINCT FROM old_parent_id THEN
        EXECUTE format('SELECT sealed_at FROM deims.%I WHERE id = $1 FOR SHARE', TG_ARGV[1])
           INTO parent_sealed_at
           USING new_parent_id;
        IF parent_sealed_at IS NOT NULL THEN
            RAISE EXCEPTION 'Child cannot be added or moved under sealed deims.% version %',
                TG_ARGV[1], new_parent_id USING ERRCODE = '55000';
        END IF;
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION deims.validate_bonded_movement_posting()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, deims
AS $function$
BEGIN
    IF NEW.status <> 'POSTED'
       OR (TG_OP = 'UPDATE' AND OLD.status = 'POSTED')
       OR NOT NEW.requires_zero_sum THEN
        RETURN NEW;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM deims.bonded_inventory_movements
        WHERE bonded_movement_group_id = NEW.id
    ) THEN
        RAISE EXCEPTION 'Posted bonded movement group % has no movement rows', NEW.id
            USING ERRCODE = '23514';
    END IF;
    IF EXISTS (
        SELECT 1
        FROM deims.bonded_inventory_movements
        WHERE bonded_movement_group_id = NEW.id
        GROUP BY bonded_cargo_item_id, base_uom_code
        HAVING abs(sum(quantity_delta)) > 0.00000001
    ) THEN
        RAISE EXCEPTION 'Bonded movement group % is not quantity-balanced by cargo item/base UOM', NEW.id
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

-- Standard optimistic-lock timestamp/version triggers for every mutable table.
DO $block$
DECLARE
    target record;
BEGIN
    FOR target IN
        SELECT DISTINCT c.table_schema, c.table_name
        FROM information_schema.columns c
        JOIN information_schema.columns u
          ON u.table_schema = c.table_schema
         AND u.table_name = c.table_name
         AND u.column_name = 'updated_at'
        JOIN information_schema.columns v
          ON v.table_schema = c.table_schema
         AND v.table_name = c.table_name
         AND v.column_name = 'row_version'
        JOIN information_schema.tables table_meta
          ON table_meta.table_schema = c.table_schema
         AND table_meta.table_name = c.table_name
         AND table_meta.table_type = 'BASE TABLE'
        WHERE c.table_schema = 'deims'
          AND c.column_name = 'updated_at'
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_trigger t
            WHERE t.tgrelid = format('%I.%I', target.table_schema, target.table_name)::regclass
              AND t.tgfoid = 'deims.touch_row()'::regprocedure
              AND NOT t.tgisinternal
        ) THEN
            EXECUTE format(
                'CREATE TRIGGER trg_touch_row BEFORE UPDATE ON %I.%I '
                'FOR EACH ROW EXECUTE PROCEDURE deims.touch_row()',
                target.table_schema, target.table_name
            );
        END IF;
    END LOOP;
END;
$block$;

-- Finalized business headers remain as evidence; corrections use explicit reversal/version rows.
DO $block$
DECLARE
    target record;
BEGIN
    FOR target IN
        SELECT * FROM (VALUES
            ('charges','status','SETTLED,WAIVED,REVERSED,CANCELLED'),
            ('tax_invoices','nts_status','ACCEPTED,CANCELLED,CORRECTED'),
            ('settlement_batches','status','POSTED,CLOSED,CANCELLED'),
            ('settlements','status','PAID,CLOSED,CANCELLED,REVERSED'),
            ('journal_batches','status','POSTED,REVERSED,CANCELLED'),
            ('customs_duty_payments','status','REFUNDED,VOID'),
            ('customs_refund_claims','status','PAID,REJECTED,CANCELLED'),
            ('bonded_movement_groups','status','POSTED,REVERSED,CANCELLED'),
            ('bonded_compliance_reports','submission_status','ACCEPTED,REJECTED,SUPERSEDED'),
            ('service_contract_versions','status','SUPERSEDED,REJECTED'),
            ('inventory_valuation_layers','status','REVERSED,CLOSED'),
            ('inventory_transformations','status','POSTED,CANCELLED')
        ) AS configured(table_name, status_column, terminal_statuses)
    LOOP
        IF to_regclass(format('deims.%I', target.table_name)) IS NULL THEN
            CONTINUE;
        END IF;
        EXECUTE format('DROP TRIGGER IF EXISTS trg_protect_finalized_row ON deims.%I', target.table_name);
        EXECUTE format(
            'CREATE TRIGGER trg_protect_finalized_row BEFORE UPDATE OR DELETE ON deims.%I '
            'FOR EACH ROW EXECUTE PROCEDURE deims.protect_finalized_row(%L,%L)',
            target.table_name, target.status_column, target.terminal_statuses
        );
        EXECUTE format('DROP TRIGGER IF EXISTS trg_protect_finalized_truncate ON deims.%I', target.table_name);
        EXECUTE format(
            'CREATE TRIGGER trg_protect_finalized_truncate BEFORE TRUNCATE ON deims.%I '
            'FOR EACH STATEMENT EXECUTE PROCEDURE deims.prevent_append_only_change()',
            target.table_name
        );
    END LOOP;
END;
$block$;

DROP TRIGGER IF EXISTS trg_protect_customs_filing_aggregate ON deims.customs_declarations;
CREATE TRIGGER trg_protect_customs_filing_aggregate
    BEFORE INSERT OR UPDATE OR DELETE ON deims.customs_declarations
    FOR EACH ROW EXECUTE PROCEDURE deims.protect_versioned_filing_aggregate(
        'workflow_status',
        'SUBMITTED,ACCEPTED,UNDER_REVIEW,INSPECTION,ASSESSED,PAID,RELEASED,CLEARED,CORRECTION_REQUIRED,REJECTED,WITHDRAWN,CANCELLED',
        'customs_declaration_versions',
        'declaration_id',
        'current_version_id,current_version_no,declaration_no_raw,declaration_no_normalized,submission_no,workflow_status,customs_system_recorded_at,accepted_at,assessed_at,released_at,cleared_at,rejected_at,withdrawn_at,retention_until,legal_hold,updated_by,row_version,updated_at',
        'SUBMITTED'
    );

DROP TRIGGER IF EXISTS trg_protect_bonded_filing_aggregate ON deims.bonded_inout_reports;
CREATE TRIGGER trg_protect_bonded_filing_aggregate
    BEFORE INSERT OR UPDATE OR DELETE ON deims.bonded_inout_reports
    FOR EACH ROW EXECUTE PROCEDURE deims.protect_versioned_filing_aggregate(
        'report_status',
        'SUBMITTED,ACCEPTED,REJECTED,CORRECTION_REQUIRED,WITHDRAWN,CANCELLED',
        'bonded_inout_report_versions',
        'bonded_inout_report_id',
        'customs_report_no_raw,customs_report_no_normalized,current_version_id,current_version_no,report_status,acceptance_status,submitted_at,customs_system_recorded_at,accepted_at,rejected_at,accepted_unipass_message_id,retention_until,legal_hold,updated_by,row_version,updated_at',
        'SUBMITTED'
    );

-- Once a header reaches the point where its children are frozen, it may advance only through
-- forward processing states and only explicitly enumerated processing fields may change.
DO $block$
DECLARE
    target record;
BEGIN
    FOR target IN
        SELECT * FROM (VALUES
            ('charges','status','INVOICED,SETTLED,WAIVED,REVERSED,CANCELLED',
             'status,settled,row_version,updated_at'),
            ('settlements','status','APPROVED,INVOICED,PARTIALLY_PAID,PAID,CLOSED,CANCELLED,REVERSED',
             'status,row_version,updated_at'),
            ('tax_invoices','nts_status','TRANSMITTED,ACCEPTED,REJECTED,CANCELLED,CORRECTED',
             'nts_status,nts_approval_no,transmitted_at,accepted_at,rejected_at,error_detail_masked,row_version,updated_at'),
            ('journal_batches','status','APPROVED,POSTED,REVERSED,CANCELLED',
             'status,posted_by,posted_at,reversal_batch_id,row_version,updated_at'),
            ('settlement_batches','status','APPROVED,POSTED,CLOSED,CANCELLED',
             'status,closed_at,row_version,updated_at')
        ) AS configured(table_name, status_column, progression, mutable_columns)
    LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS trg_protect_committed_row ON deims.%I', target.table_name);
        EXECUTE format(
            'CREATE TRIGGER trg_protect_committed_row BEFORE INSERT OR UPDATE OR DELETE ON deims.%I '
            'FOR EACH ROW EXECUTE PROCEDURE deims.protect_committed_row(%L,%L,%L)',
            target.table_name, target.status_column, target.progression, target.mutable_columns
        );
    END LOOP;
END;
$block$;

-- Detail rows are frozen as soon as their financial parent reaches a posting/final state.
DO $block$
DECLARE
    target record;
BEGIN
    FOR target IN
        SELECT * FROM (VALUES
            ('invoice_lines','invoice_id','invoices','status','POSTED,PARTIALLY_PAID,PAID,CANCELLED,REVERSED'),
            ('invoice_taxes','invoice_id','invoices','status','POSTED,PARTIALLY_PAID,PAID,CANCELLED,REVERSED'),
            ('tax_invoice_lines','tax_invoice_id','tax_invoices','nts_status','TRANSMITTED,ACCEPTED,CANCELLED,CORRECTED'),
            ('settlement_lines','settlement_id','settlements','status','APPROVED,INVOICED,PARTIALLY_PAID,PAID,CLOSED,CANCELLED,REVERSED'),
            ('charge_allocations','charge_id','charges','status','INVOICED,SETTLED,WAIVED,REVERSED,CANCELLED'),
            ('charge_adjustments','charge_id','charges','status','INVOICED,SETTLED,WAIVED,REVERSED,CANCELLED'),
            ('journal_entries','journal_batch_id','journal_batches','status','APPROVED,POSTED,REVERSED,CANCELLED')
        ) AS configured(table_name, parent_fk, parent_table, parent_status_column, terminal_statuses)
    LOOP
        IF to_regclass(format('deims.%I', target.table_name)) IS NULL THEN
            CONTINUE;
        END IF;
        EXECUTE format('DROP TRIGGER IF EXISTS trg_protect_finalized_parent ON deims.%I', target.table_name);
        EXECUTE format(
            'CREATE TRIGGER trg_protect_finalized_parent BEFORE INSERT OR UPDATE OR DELETE ON deims.%I '
            'FOR EACH ROW EXECUTE PROCEDURE deims.protect_child_when_parent_final(%L,%L,%L,%L)',
            target.table_name, target.parent_fk, target.parent_table,
            target.parent_status_column, target.terminal_statuses
        );
        EXECUTE format('DROP TRIGGER IF EXISTS trg_protect_finalized_child_truncate ON deims.%I', target.table_name);
        EXECUTE format(
            'CREATE TRIGGER trg_protect_finalized_child_truncate BEFORE TRUNCATE ON deims.%I '
            'FOR EACH STATEMENT EXECUTE PROCEDURE deims.prevent_append_only_change()',
            target.table_name
        );
    END LOOP;
END;
$block$;

-- Inventory ledger sealing: draft entries remain editable, but posting validates zero-sum
-- quantity entries and posted headers/entries are protected by 04 plus this independent guard.
DROP TRIGGER IF EXISTS trg_guard_inventory_entry_mutation
    ON deims.inventory_transaction_entries;
CREATE TRIGGER trg_guard_inventory_entry_mutation
    BEFORE INSERT OR UPDATE OR DELETE ON deims.inventory_transaction_entries
    FOR EACH ROW EXECUTE PROCEDURE deims.guard_inventory_entry_mutation();

DROP TRIGGER IF EXISTS trg_validate_inventory_transaction_posting
    ON deims.inventory_transaction_headers;
CREATE TRIGGER trg_validate_inventory_transaction_posting
    BEFORE INSERT OR UPDATE OF posting_status ON deims.inventory_transaction_headers
    FOR EACH ROW EXECUTE PROCEDURE deims.validate_inventory_transaction_posting();

DROP TRIGGER IF EXISTS trg_validate_bonded_movement_posting ON deims.bonded_movement_groups;
CREATE TRIGGER trg_validate_bonded_movement_posting
    BEFORE INSERT OR UPDATE OF status ON deims.bonded_movement_groups
    FOR EACH ROW EXECUTE PROCEDURE deims.validate_bonded_movement_posting();

DROP TRIGGER IF EXISTS trg_protect_bonded_report_version
    ON deims.bonded_inout_report_versions;
CREATE TRIGGER trg_protect_bonded_report_version
    BEFORE UPDATE OR DELETE ON deims.bonded_inout_report_versions
    FOR EACH ROW EXECUTE PROCEDURE deims.protect_sealed_version();

DROP TRIGGER IF EXISTS trg_protect_bonded_report_line
    ON deims.bonded_inout_report_lines;
CREATE TRIGGER trg_protect_bonded_report_line
    BEFORE INSERT OR UPDATE OR DELETE ON deims.bonded_inout_report_lines
    FOR EACH ROW EXECUTE PROCEDURE deims.protect_child_when_parent_sealed(
        'bonded_inout_report_version_id','bonded_inout_report_versions'
    );

DROP TRIGGER IF EXISTS trg_protect_posted_journal_line ON deims.journal_lines;
CREATE TRIGGER trg_protect_posted_journal_line
    BEFORE INSERT OR UPDATE OR DELETE ON deims.journal_lines
    FOR EACH ROW EXECUTE PROCEDURE deims.protect_journal_line_when_posted();

DROP TRIGGER IF EXISTS trg_validate_journal_batch_posting ON deims.journal_batches;
CREATE TRIGGER trg_validate_journal_batch_posting
    BEFORE INSERT OR UPDATE OF status ON deims.journal_batches
    FOR EACH ROW EXECUTE PROCEDURE deims.validate_journal_batch_posting();

DROP TRIGGER IF EXISTS trg_validate_invoice_posting ON deims.invoices;
CREATE TRIGGER trg_validate_invoice_posting
    BEFORE INSERT OR UPDATE OF status ON deims.invoices
    FOR EACH ROW EXECUTE PROCEDURE deims.validate_invoice_posting();

DROP TRIGGER IF EXISTS trg_protect_posted_invoice_core ON deims.invoices;
CREATE TRIGGER trg_protect_posted_invoice_core
    BEFORE UPDATE OR DELETE ON deims.invoices
    FOR EACH ROW EXECUTE PROCEDURE deims.protect_posted_invoice_core();

DROP TRIGGER IF EXISTS trg_protect_invoice_line_charge ON deims.invoice_line_charges;
CREATE TRIGGER trg_protect_invoice_line_charge
    BEFORE INSERT OR UPDATE OR DELETE ON deims.invoice_line_charges
    FOR EACH ROW EXECUTE PROCEDURE deims.protect_invoice_line_child_when_posted();

-- TRUNCATE does not fire row-level DELETE triggers. Protect high-integrity stores explicitly;
-- exceptional resets require an audited DBA trigger-disable procedure.
DO $block$
DECLARE
    table_name text;
BEGIN
    FOREACH table_name IN ARRAY ARRAY[
        'schema_migrations','stock_buckets','inventory_transaction_headers','inventory_transaction_entries',
        'inventory_balances','customs_declarations','customs_declaration_versions',
        'customs_declaration_parties','customs_declaration_references','customs_declaration_lines',
        'customs_declaration_line_details','customs_declaration_requirements',
        'customs_declaration_taxes','customs_declaration_containers',
        'bonded_inout_reports','bonded_inout_report_versions','bonded_inout_report_lines',
        'unipass_message_results',
        'bonded_inventory_balances','invoices','invoice_line_charges','journal_lines'
    ]::text[]
    LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS trg_protect_integrity_truncate ON deims.%I', table_name);
        EXECUTE format(
            'CREATE TRIGGER trg_protect_integrity_truncate BEFORE TRUNCATE ON deims.%I '
            'FOR EACH STATEMENT EXECUTE PROCEDURE deims.prevent_append_only_change()',
            table_name
        );
    END LOOP;
END;
$block$;

-- Strict append-only records. Existing 03/04/07 triggers are retained; this fills gaps in
-- other modules and never introduces a client-controlled bypass.
DO $block$
DECLARE
    table_name text;
BEGIN
    FOREACH table_name IN ARRAY ARRAY[
        'schema_migrations','account_link_events','login_events','audit_events','location_status_history',
        'inbound_order_status_history','dock_appointment_history','receipt_status_history',
        'unloading_events','quality_hold_status_history','supplier_return_status_history',
        'inventory_lot_genealogy','serial_status_history','lpn_status_history',
        'lpn_location_history','lpn_relationship_history','inventory_reservation_history',
        'inventory_hold_releases','stock_transfer_status_history','movement_confirmations',
        'movement_task_status_history','putaway_confirmations','inventory_adjustment_approvals',
        'inventory_adjustment_status_history','cycle_count_observations','cycle_count_status_history',
        'inventory_snapshot_lines','inventory_valuation_movements','inventory_transformation_status_history',
        'outbound_order_status_history','wave_status_history','pick_confirmations',
        'shipment_status_history','shipping_confirmations','delivery_events',
        'vas_work_order_status_history','attendance_events','labor_productivity_events',
        'yard_visit_events','scan_events','sensor_readings',
        'trade_party_snapshots','trade_shipment_events','trade_container_events',
        'trade_document_versions','trade_document_parties','trade_document_links',
        'customs_declaration_events','customs_documents','customs_document_links',
        'customs_duty_payment_allocations','customs_refund_allocations',
        'customs_release_evidence','customs_release_line_coverages',
        'unipass_message_events','unipass_message_errors','unipass_message_attachments',
        'unipass_message_results',
        'bonded_cargo_status_events','bonded_inventory_movements','bonded_transport_events',
        'bonded_seal_checks','bonded_overdue_events',
        'rating_run_details','invoice_match_results','invoice_dispute_events',
        'invoice_status_history','tax_invoice_events','approval_actions',
        'impersonation_events','entity_change_logs','data_access_logs','edi_validation_errors',
        'trade_case_party_snapshots','trade_case_events','import_events','export_events',
        'export_fulfillment_evidence','carrier_booking_events','equipment_interchanges',
        'container_free_time_events','tariff_classification_decisions',
        'customs_guarantee_usages','duty_drawback_source_imports',
        'duty_drawback_export_lines','duty_drawback_events',
        'origin_calculation_results','origin_determinations','origin_certificate_uses',
        'origin_certificate_events','screening_request_lists','screening_matches',
        'screening_decisions','compliance_events','trade_license_usages','quota_usages',
        'regulatory_permit_usages','exchange_rate_snapshots',
        'letter_of_credit_amendments','trade_finance_events','bank_statement_lines',
        'insurance_premiums','claim_events','claim_documents','claim_reserve_movements',
        'trade_document_status_events','trade_document_signatures','workflow_events',
        'job_run_events'
    ]::text[]
    LOOP
        IF to_regclass(format('deims.%I', table_name)) IS NULL THEN
            CONTINUE;
        END IF;
        IF NOT EXISTS (
            SELECT 1
            FROM pg_trigger t
            WHERE t.tgrelid = format('deims.%I', table_name)::regclass
              AND t.tgname IN ('trg_append_only','trg_block_immutable_change','trg_deims_append_only')
              AND NOT t.tgisinternal
        ) THEN
            EXECUTE format(
                'CREATE TRIGGER trg_deims_append_only BEFORE UPDATE OR DELETE ON deims.%I '
                'FOR EACH ROW EXECUTE PROCEDURE deims.prevent_append_only_change()',
                table_name
            );
        END IF;
        EXECUTE format('DROP TRIGGER IF EXISTS trg_deims_append_only_truncate ON deims.%I', table_name);
        EXECUTE format(
            'CREATE TRIGGER trg_deims_append_only_truncate BEFORE TRUNCATE ON deims.%I '
            'FOR EACH STATEMENT EXECUTE PROCEDURE deims.prevent_append_only_change()',
            table_name
        );
    END LOOP;
END;
$block$;

-- Message payloads and routing identity are immutable while controlled processing fields may advance.
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
            ('notifications',
             '''status'',''scheduled_at'',''expires_at'',''row_version'',''updated_at'''),
            ('notification_deliveries',
             '''status'',''provider_message_id'',''attempt_count'',''last_attempt_at'',''delivered_at'',''read_at'',''failed_at'',''error_detail_masked'',''row_version'',''updated_at'''),
            ('inbox_deduplication',
             '''last_received_at'',''receive_count'',''processed_resource_type'',''processed_resource_id'',''status'',''row_version'',''updated_at'''),
            ('charge_events',
             '''rated_at'',''status'''),
            ('unipass_messages',
             '''recorded_status'',''sent_at'',''received_at'',''customs_system_recorded_at'',''retention_until'',''legal_hold''')
        ) AS configured(table_name, trigger_arguments)
    LOOP
        IF to_regclass(format('deims.%I', target.table_name)) IS NULL THEN
            CONTINUE;
        END IF;
        IF target.table_name = 'unipass_messages' THEN
            EXECUTE 'DROP TRIGGER IF EXISTS trg_block_immutable_change ON deims.unipass_messages';
            EXECUTE 'DROP TRIGGER IF EXISTS trg_deims_append_only ON deims.unipass_messages';
            EXECUTE 'DROP TRIGGER IF EXISTS trg_append_only ON deims.unipass_messages';
        END IF;
        EXECUTE format('DROP TRIGGER IF EXISTS trg_protect_message_core ON deims.%I', target.table_name);
        EXECUTE format(
            'CREATE TRIGGER trg_protect_message_core BEFORE UPDATE OR DELETE ON deims.%I '
            'FOR EACH ROW EXECUTE PROCEDURE deims.protect_message_core(%s)',
            target.table_name, target.trigger_arguments
        );
        EXECUTE format('DROP TRIGGER IF EXISTS trg_protect_message_truncate ON deims.%I', target.table_name);
        EXECUTE format(
            'CREATE TRIGGER trg_protect_message_truncate BEFORE TRUNCATE ON deims.%I '
            'FOR EACH STATEMENT EXECUTE PROCEDURE deims.prevent_append_only_change()',
            target.table_name
        );
    END LOOP;
END;
$block$;

CREATE OR REPLACE FUNCTION deims.current_tenant_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $function$
    SELECT NULLIF(current_setting('deims.tenant_id', true), '')::uuid;
$function$;

COMMENT ON FUNCTION deims.current_tenant_id() IS
    'Backend-supplied RLS routing context set with SET LOCAL for each transaction; the custom GUC is not an authentication boundary.';

-- The underlying posting routine is SECURITY DEFINER and intentionally remains unavailable to
-- the runtime role. This narrow wrapper binds it to the backend-selected tenant and to an active
-- tenant member who has a live tenant-level inventory.post grant. The backend must derive both
-- values from a verified Firebase session; neither a custom GUC nor p_posted_by is an independent
-- security boundary for an untrusted SQL client.
CREATE OR REPLACE FUNCTION deims.post_inventory_transaction_for_tenant(
    p_inventory_transaction_id uuid,
    p_posted_by uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, deims
AS $function$
DECLARE
    context_tenant_id uuid;
    transaction_tenant_id uuid;
BEGIN
    context_tenant_id := deims.current_tenant_id();
    IF context_tenant_id IS NULL THEN
        RAISE EXCEPTION 'A verified tenant context is required for inventory posting'
            USING ERRCODE = '28000';
    END IF;

    SELECT header.tenant_id
      INTO transaction_tenant_id
      FROM deims.inventory_transaction_headers header
     WHERE header.id = p_inventory_transaction_id;

    IF transaction_tenant_id IS NULL
       OR transaction_tenant_id IS DISTINCT FROM context_tenant_id THEN
        -- Do not reveal whether an identifier belongs to a different tenant.
        RAISE EXCEPTION 'Inventory transaction is unavailable in the active tenant'
            USING ERRCODE = '42501';
    END IF;

    IF NOT EXISTS (
        SELECT 1
          FROM deims.tenant_memberships membership
          JOIN deims.users principal
            ON principal.id = membership.user_id
           AND principal.status = 'ACTIVE'
          JOIN deims.role_assignments assignment
            ON assignment.tenant_id = membership.tenant_id
           AND assignment.revoked_at IS NULL
           AND (assignment.valid_until IS NULL OR assignment.valid_until > now())
           AND assignment.scope_type = 'TENANT'
           AND (
               assignment.membership_id = membership.id
               OR EXISTS (
                   SELECT 1
                     FROM deims.user_group_members group_member
                    WHERE group_member.tenant_id = membership.tenant_id
                      AND group_member.group_id = assignment.group_id
                      AND group_member.membership_id = membership.id
                      AND group_member.removed_at IS NULL
               )
           )
          JOIN deims.roles assigned_role
            ON assigned_role.id = assignment.role_id
           AND assigned_role.is_active
           AND (
               assigned_role.tenant_id IS NULL
               OR assigned_role.tenant_id = membership.tenant_id
           )
          JOIN deims.role_permissions role_permission
            ON role_permission.role_id = assigned_role.id
           AND role_permission.revoked_at IS NULL
           AND (
               role_permission.tenant_id IS NULL
               OR role_permission.tenant_id = membership.tenant_id
           )
          JOIN deims.permissions permission
            ON permission.id = role_permission.permission_id
           AND permission.permission_code = 'inventory.post'
           AND permission.is_active
         WHERE membership.tenant_id = context_tenant_id
           AND membership.user_id = p_posted_by
           AND membership.status = 'ACTIVE'
           AND membership.valid_from <= now()
           AND (membership.valid_to IS NULL OR membership.valid_to > now())
    ) THEN
        RAISE EXCEPTION 'Active tenant-level inventory.post permission is required'
            USING ERRCODE = '42501';
    END IF;

    PERFORM deims.post_inventory_transaction(p_inventory_transaction_id, p_posted_by);
END;
$function$;

REVOKE ALL ON FUNCTION deims.post_inventory_transaction_for_tenant(uuid, uuid) FROM PUBLIC;

COMMENT ON FUNCTION deims.post_inventory_transaction_for_tenant(uuid, uuid) IS
    'Runtime inventory posting entry point. Validates active tenant context, membership, and inventory.post permission before calling the sealed ledger posting routine.';

-- RLS applies to every table carrying tenant_id. Only explicitly enumerated nullable-tenant
-- reference masters expose their global rows; all writes still require the active tenant.
DO $block$
DECLARE
    target record;
    global_reference_tables constant text[] := ARRAY[
        'roles','role_permissions','code_sets','code_values','data_retention_policies',
        'exchange_rates','tax_codes','tax_rates','payment_terms','charge_codes','reason_codes',
        'inventory_statuses','location_types','material_handling_equipment_types','lpn_types',
        'status_definitions','status_transitions','notification_templates','scheduled_jobs',
        'bonded_storage_rules',
        'sod_rules','sod_rule_conflicts','kpi_definitions','data_quality_rules'
    ]::text[];
    platform_event_tables constant text[] := ARRAY[
        'login_events','audit_events','data_access_logs'
    ]::text[];
    global_job_tables constant text[] := ARRAY['job_runs','job_run_events']::text[];
    select_expression text;
    modify_expression text;
BEGIN
    FOR target IN
        SELECT DISTINCT column_meta.table_schema, column_meta.table_name
        FROM information_schema.columns column_meta
        JOIN information_schema.tables table_meta
          ON table_meta.table_schema = column_meta.table_schema
         AND table_meta.table_name = column_meta.table_name
         AND table_meta.table_type = 'BASE TABLE'
        WHERE column_meta.table_schema = 'deims'
          AND column_meta.column_name = 'tenant_id'
    LOOP
        EXECUTE format('ALTER TABLE %I.%I ENABLE ROW LEVEL SECURITY', target.table_schema, target.table_name);
        EXECUTE format('DROP POLICY IF EXISTS tenant_select ON %I.%I', target.table_schema, target.table_name);
        EXECUTE format('DROP POLICY IF EXISTS tenant_modify ON %I.%I', target.table_schema, target.table_name);

        IF target.table_name = ANY (global_reference_tables) THEN
            select_expression := 'tenant_id IS NULL OR tenant_id = deims.current_tenant_id()';
            modify_expression := 'tenant_id = deims.current_tenant_id()';
        ELSIF target.table_name = ANY (platform_event_tables) THEN
            select_expression := 'tenant_id = deims.current_tenant_id() OR '
                || '(tenant_id IS NULL AND current_user = ''deims_platform_logger'')';
            modify_expression := select_expression;
        ELSIF target.table_name = ANY (global_job_tables) THEN
            select_expression := 'tenant_id = deims.current_tenant_id() OR '
                || '(tenant_id IS NULL AND current_user = ''deims_global_job_runner'')';
            modify_expression := select_expression;
        ELSE
            select_expression := 'tenant_id = deims.current_tenant_id()';
            modify_expression := select_expression;
        END IF;

        EXECUTE format(
            'CREATE POLICY tenant_select ON %I.%I FOR SELECT USING (%s)',
            target.table_schema, target.table_name, select_expression
        );
        EXECUTE format(
            'CREATE POLICY tenant_modify ON %I.%I FOR ALL '
            'USING (%s) WITH CHECK (%s)',
            target.table_schema, target.table_name, modify_expression, modify_expression
        );
    END LOOP;
END;
$block$;

-- PostgreSQL does not automatically index referencing FK columns. Add a deterministic
-- leading-column index only when no valid non-partial index already covers the FK.
DO $block$
DECLARE
    relation record;
    column_list text;
    index_name text;
BEGIN
    FOR relation IN
        SELECT con.oid, con.conname, con.conrelid,
               ns.nspname AS schema_name, cls.relname AS table_name, con.conkey
        FROM pg_constraint con
        JOIN pg_class cls ON cls.oid = con.conrelid
        JOIN pg_namespace ns ON ns.oid = cls.relnamespace
        WHERE con.contype = 'f' AND ns.nspname = 'deims'
        ORDER BY ns.nspname, cls.relname,
                 array_length(con.conkey, 1) DESC,
                 con.conkey::text, con.conname
    LOOP
        SELECT string_agg(quote_ident(a.attname), ', ' ORDER BY key_column.ordinality)
          INTO column_list
        FROM unnest(relation.conkey) WITH ORDINALITY AS key_column(attnum, ordinality)
        JOIN pg_attribute a
          ON a.attrelid = relation.conrelid AND a.attnum = key_column.attnum;

        IF EXISTS (
            SELECT 1
            FROM pg_index i
            WHERE i.indrelid = relation.conrelid
              AND i.indisvalid
              AND i.indisready
              AND i.indpred IS NULL
              AND i.indnkeyatts >= array_length(relation.conkey, 1)
              AND ARRAY(
                  SELECT index_column.attnum
                  FROM unnest(i.indkey) WITH ORDINALITY AS index_column(attnum, ordinality)
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

-- tenant_id never changes in place; cross-tenant moves are audited copy/reversal operations.
DO $block$
DECLARE
    target record;
BEGIN
    FOR target IN
        SELECT DISTINCT column_meta.table_schema, column_meta.table_name
        FROM information_schema.columns column_meta
        JOIN information_schema.tables table_meta
          ON table_meta.table_schema = column_meta.table_schema
         AND table_meta.table_name = column_meta.table_name
         AND table_meta.table_type = 'BASE TABLE'
        WHERE column_meta.table_schema = 'deims'
          AND column_meta.column_name = 'tenant_id'
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_trigger t
            WHERE t.tgrelid = format('%I.%I', target.table_schema, target.table_name)::regclass
              AND t.tgname = 'trg_prevent_tenant_change'
              AND NOT t.tgisinternal
        ) THEN
            EXECUTE format(
                'CREATE TRIGGER trg_prevent_tenant_change BEFORE UPDATE OF tenant_id ON %I.%I '
                'FOR EACH ROW EXECUTE PROCEDURE deims.prevent_tenant_change()',
                target.table_schema, target.table_name
            );
        END IF;
    END LOOP;
END;
$block$;

-- Guard simple UUID references when both parent and child are tenant-scoped. Existing
-- composite (tenant_id,id) FKs are preferred and are detected so no redundant trigger is added.
DO $block$
DECLARE
    relation record;
    child_column text;
    trigger_name text;
BEGIN
    FOR relation IN
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
          AND child_ns.nspname = 'deims'
          AND parent_ns.nspname = 'deims'
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
            md5(relation.child_schema || '.' || relation.child_table || '.' || relation.conname), 1, 12
        );
        IF NOT EXISTS (
            SELECT 1 FROM pg_trigger t
            WHERE t.tgrelid = relation.conrelid
              AND t.tgname = trigger_name
              AND NOT t.tgisinternal
        ) THEN
            EXECUTE format(
                'CREATE TRIGGER %I BEFORE INSERT OR UPDATE OF %I ON %I.%I '
                'FOR EACH ROW EXECUTE PROCEDURE deims.enforce_same_tenant_fk(%L,%L,%L)',
                trigger_name, child_column, relation.child_schema, relation.child_table,
                child_column, relation.parent_schema, relation.parent_table
            );
        END IF;
    END LOOP;
END;
$block$;

-- High-value operational, queue, timeline, and analytical indexes.
CREATE INDEX IF NOT EXISTS ix_ops_inventory_tx_queue
    ON deims.inventory_transaction_headers (
        tenant_id, posting_status, warehouse_id, owner_partner_id, occurred_at, id
    ) WHERE posting_status IN ('DRAFT','VALIDATED','FAILED');
CREATE INDEX IF NOT EXISTS ix_ops_inventory_tx_occurred_brin
    ON deims.inventory_transaction_headers USING brin (occurred_at);
CREATE INDEX IF NOT EXISTS ix_ops_inventory_entries_tx_bucket
    ON deims.inventory_transaction_entries (
        tenant_id, inventory_transaction_id, stock_bucket_id, entry_sequence
    );
CREATE INDEX IF NOT EXISTS ix_ops_stock_bucket_lookup
    ON deims.stock_buckets (
        tenant_id, warehouse_id, owner_partner_id, item_id, inventory_status_id, location_id
    );
CREATE INDEX IF NOT EXISTS ix_ops_inventory_balance_last_tx
    ON deims.inventory_balances (tenant_id, last_transaction_at DESC, stock_bucket_id);

CREATE INDEX IF NOT EXISTS ix_ops_receipts_work_queue
    ON deims.receipts (tenant_id, warehouse_id, owner_partner_id, status, arrived_at, id)
    WHERE status NOT IN ('CLOSED','CANCELLED');
CREATE INDEX IF NOT EXISTS ix_ops_outbound_work_queue
    ON deims.outbound_orders (
        tenant_id, warehouse_id, owner_partner_id, status, priority, requested_ship_at, id
    ) WHERE status NOT IN ('SHIPPED','CANCELLED','CLOSED');
CREATE INDEX IF NOT EXISTS ix_ops_pick_task_queue
    ON deims.pick_tasks (tenant_id, warehouse_id, status, priority, scheduled_at, id)
    WHERE status NOT IN ('COMPLETED','CANCELLED');
CREATE INDEX IF NOT EXISTS ix_ops_shipments_status_schedule
    ON deims.shipments (tenant_id, warehouse_id, status, planned_ship_at, id);

CREATE INDEX IF NOT EXISTS ix_ops_customs_declaration_queue
    ON deims.customs_declarations (
        tenant_id, owner_partner_id, workflow_status, customs_office_code, created_at DESC
    ) WHERE workflow_status NOT IN ('CLEARED','REJECTED','WITHDRAWN','CANCELLED');
CREATE INDEX IF NOT EXISTS ix_ops_unipass_message_queue
    ON deims.unipass_messages (
        tenant_id, direction, recorded_status, connection_profile_id, created_at, id
    ) WHERE recorded_status IN ('CREATED','QUEUED','SENT','RECEIVED','ERROR');
CREATE INDEX IF NOT EXISTS ix_ops_unipass_message_created_brin
    ON deims.unipass_messages USING brin (created_at);
CREATE INDEX IF NOT EXISTS ix_ops_bonded_report_queue
    ON deims.bonded_inout_reports (
        tenant_id, bonded_facility_id, report_status, acceptance_status, created_at, id
    ) WHERE report_status NOT IN ('ACCEPTED','REJECTED','WITHDRAWN','CANCELLED');
CREATE INDEX IF NOT EXISTS ix_ops_bonded_movement_timeline
    ON deims.bonded_inventory_movements (
        tenant_id, bonded_cargo_id, bonded_cargo_item_id, occurred_at, movement_sequence
    );
CREATE INDEX IF NOT EXISTS ix_ops_bonded_movement_occurred_brin
    ON deims.bonded_inventory_movements USING brin (occurred_at);

CREATE INDEX IF NOT EXISTS ix_ops_charges_open
    ON deims.charges (tenant_id, owner_partner_id, status, service_date, id)
    WHERE status IN ('OPEN','ON_HOLD','APPROVED','INVOICED');
CREATE INDEX IF NOT EXISTS ix_ops_invoices_due
    ON deims.invoices (tenant_id, recipient_partner_id, status, due_date, id)
    WHERE status NOT IN ('PAID','CANCELLED','REVERSED');
CREATE INDEX IF NOT EXISTS ix_ops_settlements_open
    ON deims.settlements (tenant_id, payer_partner_id, payee_partner_id, status, due_date, id)
    WHERE status NOT IN ('PAID','CLOSED','CANCELLED','REVERSED');

CREATE INDEX IF NOT EXISTS ix_ops_workflow_tasks_pending
    ON deims.workflow_tasks (tenant_id, status, assignee_user_id, assignee_group_id, due_at, id)
    WHERE status IN ('PENDING','ASSIGNED','IN_PROGRESS');
CREATE INDEX IF NOT EXISTS ix_ops_approval_steps_pending
    ON deims.approval_steps (tenant_id, status, approver_user_id, approver_group_id, due_at, id)
    WHERE status IN ('PENDING','ASSIGNED','DELEGATED','ESCALATED');
CREATE INDEX IF NOT EXISTS ix_ops_outbox_unpublished
    ON deims.outbox_events (tenant_id, available_at, occurred_at, id)
    WHERE published_at IS NULL;
CREATE INDEX IF NOT EXISTS ix_ops_integration_unprocessed
    ON deims.integration_messages (tenant_id, direction, status, received_at, id)
    WHERE processed_at IS NULL;
CREATE INDEX IF NOT EXISTS ix_ops_notifications_queue
    ON deims.notifications (tenant_id, status, priority, scheduled_at, id)
    WHERE status IN ('QUEUED','PROCESSING','PARTIALLY_SENT','FAILED');
CREATE INDEX IF NOT EXISTS ix_ops_job_runs_queue
    ON deims.job_runs (tenant_id, status, queued_at, id)
    WHERE status IN ('QUEUED','RUNNING');
CREATE INDEX IF NOT EXISTS ix_ops_dead_letters_open
    ON deims.dead_letter_messages (tenant_id, status, next_retry_at, failed_at, id)
    WHERE status IN ('OPEN','RETRY_QUEUED','RETRYING');
CREATE INDEX IF NOT EXISTS ix_ops_reconciliation_open
    ON deims.reconciliation_runs (tenant_id, status, reconciliation_type, as_of_at, id)
    WHERE status NOT IN ('APPROVED','FAILED','CANCELLED');
CREATE INDEX IF NOT EXISTS ix_ops_data_quality_open
    ON deims.data_quality_results (tenant_id, status, evaluated_at, rule_id, id)
    WHERE status IN ('WARNING','FAIL','CRITICAL');

CREATE INDEX IF NOT EXISTS ix_ops_audit_entity_time
    ON deims.audit_events (tenant_id, entity_type, entity_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS ix_ops_audit_occurred_brin
    ON deims.audit_events USING brin (occurred_at);
CREATE INDEX IF NOT EXISTS ix_ops_change_entity_time
    ON deims.entity_change_logs (tenant_id, entity_type, entity_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS ix_ops_change_occurred_brin
    ON deims.entity_change_logs USING brin (occurred_at);
CREATE INDEX IF NOT EXISTS ix_ops_data_access_occurred_brin
    ON deims.data_access_logs USING brin (occurred_at);
CREATE INDEX IF NOT EXISTS ix_ops_impersonation_event_timeline
    ON deims.impersonation_events (tenant_id, impersonation_session_id, sequence_no, occurred_at);
CREATE INDEX IF NOT EXISTS ix_ops_impersonation_event_occurred_brin
    ON deims.impersonation_events USING brin (occurred_at);
CREATE INDEX IF NOT EXISTS ix_ops_login_occurred_brin
    ON deims.login_events USING brin (occurred_at);
CREATE INDEX IF NOT EXISTS ix_ops_scan_occurred_brin
    ON deims.scan_events USING brin (occurred_at);
CREATE INDEX IF NOT EXISTS ix_ops_sensor_reading_occurred_brin
    ON deims.sensor_readings USING brin (occurred_at);

CREATE INDEX IF NOT EXISTS ix_ops_warehouse_facts_date_brin
    ON deims.warehouse_daily_facts USING brin (fact_date);
CREATE INDEX IF NOT EXISTS ix_ops_inventory_facts_date_brin
    ON deims.inventory_daily_facts USING brin (fact_date);
CREATE INDEX IF NOT EXISTS ix_ops_operation_facts_date_brin
    ON deims.operation_daily_facts USING brin (fact_date);

-- Conservative global reference seeds. Tenant-specific overrides remain separate rows.
INSERT INTO deims.currencies (
    currency_code, currency_name, numeric_code, fraction_digits, rounding_increment, is_active
) VALUES
    ('KRW','Korean Won','410',0,1,true),
    ('USD','US Dollar','840',2,0.01,true),
    ('EUR','Euro','978',2,0.01,true),
    ('JPY','Japanese Yen','392',0,1,true),
    ('CNY','Chinese Yuan','156',2,0.01,true)
ON CONFLICT (currency_code) DO NOTHING;

INSERT INTO deims.countries (
    country_code, country_code3, numeric_code, country_name_en,
    country_name_local, default_currency_code, is_active
) VALUES
    ('KR','KOR','410','Korea, Republic of','대한민국','KRW',true),
    ('US','USA','840','United States','United States','USD',true),
    ('JP','JPN','392','Japan','日本','JPY',true),
    ('CN','CHN','156','China','中国','CNY',true),
    ('DE','DEU','276','Germany','Deutschland','EUR',true),
    ('VN','VNM','704','Viet Nam','Việt Nam',NULL,true)
ON CONFLICT (country_code) DO NOTHING;

INSERT INTO deims.units_of_measure (
    uom_code, uom_name, dimension, si_factor, decimal_places, is_active
) VALUES
    ('EA','Each','COUNT',1,0,true),
    ('CASE','Case','COUNT',1,3,true),
    ('PALLET','Pallet','COUNT',1,3,true),
    ('KG','Kilogram','MASS',1,6,true),
    ('G','Gram','MASS',0.001,6,true),
    ('TON','Metric tonne','MASS',1000,6,true),
    ('L','Litre','VOLUME',0.001,6,true),
    ('ML','Millilitre','VOLUME',0.000001,6,true),
    ('M3','Cubic metre','VOLUME',1,9,true),
    ('M','Metre','LENGTH',1,6,true),
    ('CM','Centimetre','LENGTH',0.01,6,true),
    ('MM','Millimetre','LENGTH',0.001,6,true),
    ('M2','Square metre','AREA',1,6,true),
    ('MIN','Minute','TIME',60,4,true),
    ('HOUR','Hour','TIME',3600,4,true),
    ('CEL','Degree Celsius','TEMPERATURE',1,3,true)
ON CONFLICT (uom_code) DO NOTHING;

INSERT INTO deims.transport_modes (mode_code, mode_name, mode_group, is_active) VALUES
    ('ROAD','Road','LAND',true),
    ('SEA','Sea','OCEAN',true),
    ('AIR','Air','AIR',true),
    ('RAIL','Rail','LAND',true),
    ('PARCEL','Parcel/Courier','PARCEL',true),
    ('MULTIMODAL','Multimodal','MULTIMODAL',true)
ON CONFLICT (mode_code) DO NOTHING;

INSERT INTO deims.incoterms (incoterm_code, incoterm_name, version_year, is_active) VALUES
    ('EXW','Ex Works',2020,true),
    ('FCA','Free Carrier',2020,true),
    ('CPT','Carriage Paid To',2020,true),
    ('CIP','Carriage and Insurance Paid To',2020,true),
    ('DAP','Delivered at Place',2020,true),
    ('DPU','Delivered at Place Unloaded',2020,true),
    ('DDP','Delivered Duty Paid',2020,true),
    ('FAS','Free Alongside Ship',2020,true),
    ('FOB','Free on Board',2020,true),
    ('CFR','Cost and Freight',2020,true),
    ('CIF','Cost, Insurance and Freight',2020,true)
ON CONFLICT (incoterm_code) DO NOTHING;

WITH seed(status_code, status_name, status_category, allocatable, shippable, requires_hold) AS (
    VALUES
        ('AVAILABLE','Available','AVAILABLE',true,true,false),
        ('RECEIVING','Receiving','RECEIVING',false,false,false),
        ('QUALITY_HOLD','Quality hold','QUALITY',false,false,true),
        ('QUARANTINE','Quarantine','HOLD',false,false,true),
        ('DAMAGED','Damaged','DAMAGED',false,false,true),
        ('EXPIRED','Expired','EXPIRED',false,false,true),
        ('IN_TRANSIT','In transit','IN_TRANSIT',false,false,false),
        ('SHIPPED','Shipped','SHIPPED',false,false,false),
        ('VIRTUAL','Virtual','VIRTUAL',false,false,false)
)
INSERT INTO deims.inventory_statuses (
    tenant_id, status_code, status_name, status_category,
    available_for_allocation, available_for_shipping, requires_hold,
    is_system_status, is_active
)
SELECT NULL, s.status_code, s.status_name, s.status_category,
       s.allocatable, s.shippable, s.requires_hold, true, true
FROM seed s
WHERE NOT EXISTS (
    SELECT 1 FROM deims.inventory_statuses existing
    WHERE existing.tenant_id IS NULL AND existing.status_code = s.status_code
);

WITH seed(code, name, category, pickable, putaway_allowed, countable, virtual_location) AS (
    VALUES
        ('RECEIVING','Receiving','RECEIVING',false,true,true,false),
        ('STORAGE','Storage','STORAGE',false,true,true,false),
        ('FORWARD_PICK','Forward pick','FORWARD_PICK',true,true,true,false),
        ('STAGING','Staging','STAGING',true,true,true,false),
        ('PACKING','Packing','PACKING',false,false,true,false),
        ('SHIPPING','Shipping','SHIPPING',false,false,true,false),
        ('CROSS_DOCK','Cross-dock','CROSS_DOCK',true,true,true,false),
        ('QUALITY','Quality inspection','QUALITY',false,true,true,false),
        ('QUARANTINE','Quarantine','QUARANTINE',false,true,true,false),
        ('DAMAGE','Damage','DAMAGE',false,true,true,false),
        ('VIRTUAL','Virtual','VIRTUAL',false,false,false,true)
)
INSERT INTO deims.location_types (
    tenant_id, location_type_code, location_type_name, location_category,
    pickable, putaway_allowed, countable, virtual_location, is_active
)
SELECT NULL, s.code, s.name, s.category,
       s.pickable, s.putaway_allowed, s.countable, s.virtual_location, true
FROM seed s
WHERE NOT EXISTS (
    SELECT 1 FROM deims.location_types existing
    WHERE existing.tenant_id IS NULL AND existing.location_type_code = s.code
);

INSERT INTO deims.permissions (
    permission_code, permission_name, module_code, action_code,
    description, is_sensitive, is_active
) VALUES
    ('iam.user.read','Read users and memberships','IAM','READ','Read tenant user/membership metadata',false,true),
    ('iam.role.manage','Manage tenant roles','IAM','MANAGE','Manage role assignments; subject to SoD review',true,true),
    ('config.manage','Manage warehouse configuration','CONFIG','MANAGE','Manage non-secret tenant/warehouse configuration',true,true),
    ('master.read','Read master data','MASTER','READ','Read partners, items, warehouses and reference data',false,true),
    ('master.manage','Manage master data','MASTER','MANAGE','Create and update tenant master data',true,true),
    ('inbound.read','Read inbound operations','INBOUND','READ','Read inbound orders, receipts and quality operations',false,true),
    ('inbound.execute','Execute inbound operations','INBOUND','EXECUTE','Receive, inspect and put away inventory',true,true),
    ('inventory.read','Read inventory','INVENTORY','READ','Read buckets, balances and inventory ledger',false,true),
    ('inventory.post','Post inventory ledger','INVENTORY','POST','Execute controlled inventory posting/reversal functions',true,true),
    ('inventory.adjust','Approve inventory adjustments','INVENTORY','ADJUST','Approve/post count and inventory adjustments',true,true),
    ('inventory.hold','Manage inventory holds','INVENTORY','HOLD','Apply or release operational inventory holds',true,true),
    ('outbound.read','Read outbound operations','OUTBOUND','READ','Read orders, allocations, picks, shipments and returns',false,true),
    ('outbound.execute','Execute outbound operations','OUTBOUND','EXECUTE','Allocate, pick, pack, load and ship',true,true),
    ('customs.read','Read customs records','CUSTOMS','READ','Read declaration, document and UNI-PASS metadata',true,true),
    ('customs.submit','Submit customs declarations','CUSTOMS','SUBMIT','Seal and submit declarations/corrections to UNI-PASS',true,true),
    ('bonded.read','Read bonded operations','BONDED','READ','Read bonded cargo, legal status and reports',true,true),
    ('bonded.report','Submit bonded reports','BONDED','REPORT','Seal and submit bonded inbound/outbound reports',true,true),
    ('billing.read','Read billing and settlement','BILLING','READ','Read charges, invoices, settlements and journals',true,true),
    ('billing.approve','Approve billing and settlement','BILLING','APPROVE','Approve/post billing, settlement and journals',true,true),
    ('workflow.approve','Act on approvals','WORKFLOW','APPROVE','Approve or reject assigned workflow tasks',true,true),
    ('audit.read','Read audit records','AUDIT','READ','Read immutable business/security audit trails',true,true),
    ('data_access.read','Read data-access logs','AUDIT','DATA_ACCESS','Read regulated data-access evidence',true,true),
    ('integration.monitor','Monitor integrations','INTEGRATION','MONITOR','Read EDI, webhook, job and dead-letter status',false,true),
    ('integration.manage','Manage integrations','INTEGRATION','MANAGE','Manage endpoints and retry/dead-letter operations',true,true)
ON CONFLICT (permission_code) DO NOTHING;

WITH seed(role_code, role_name, description) AS (
    VALUES
        ('DEIMS_VIEWER','DEIMS Viewer','Read-only operational visibility; excludes privileged audit/data-access views.'),
        ('DEIMS_OPERATOR','DEIMS Operator','Inbound/outbound execution without ledger posting or customs/finance approval.'),
        ('DEIMS_SUPERVISOR','DEIMS Supervisor','Operational supervision and assigned workflow approvals.'),
        ('DEIMS_INVENTORY_CONTROLLER','DEIMS Inventory Controller','Inventory posting, adjustment and hold authority.'),
        ('DEIMS_CUSTOMS_SPECIALIST','DEIMS Customs Specialist','Customs and bonded filing authority.'),
        ('DEIMS_BILLING_SPECIALIST','DEIMS Billing Specialist','Billing and settlement approval authority.'),
        ('DEIMS_AUDITOR','DEIMS Auditor','Read-only audit, regulated access and control evidence.'),
        ('DEIMS_TENANT_ADMIN','DEIMS Tenant Administrator','IAM/configuration administration without inventory, customs or finance posting authority.')
)
INSERT INTO deims.roles (
    tenant_id, role_code, role_name, description, is_system_role, is_active
)
SELECT NULL, s.role_code, s.role_name, s.description, true, true
FROM seed s
WHERE NOT EXISTS (
    SELECT 1 FROM deims.roles existing
    WHERE existing.tenant_id IS NULL AND existing.role_code = s.role_code
);

WITH grants(role_code, permission_code) AS (
    VALUES
        ('DEIMS_VIEWER','master.read'),
        ('DEIMS_VIEWER','inbound.read'),
        ('DEIMS_VIEWER','inventory.read'),
        ('DEIMS_VIEWER','outbound.read'),
        ('DEIMS_OPERATOR','master.read'),
        ('DEIMS_OPERATOR','inbound.read'),
        ('DEIMS_OPERATOR','inbound.execute'),
        ('DEIMS_OPERATOR','inventory.read'),
        ('DEIMS_OPERATOR','outbound.read'),
        ('DEIMS_OPERATOR','outbound.execute'),
        ('DEIMS_SUPERVISOR','master.read'),
        ('DEIMS_SUPERVISOR','inbound.read'),
        ('DEIMS_SUPERVISOR','inbound.execute'),
        ('DEIMS_SUPERVISOR','inventory.read'),
        ('DEIMS_SUPERVISOR','outbound.read'),
        ('DEIMS_SUPERVISOR','outbound.execute'),
        ('DEIMS_SUPERVISOR','workflow.approve'),
        ('DEIMS_INVENTORY_CONTROLLER','master.read'),
        ('DEIMS_INVENTORY_CONTROLLER','inbound.read'),
        ('DEIMS_INVENTORY_CONTROLLER','inventory.read'),
        ('DEIMS_INVENTORY_CONTROLLER','inventory.post'),
        ('DEIMS_INVENTORY_CONTROLLER','inventory.adjust'),
        ('DEIMS_INVENTORY_CONTROLLER','inventory.hold'),
        ('DEIMS_INVENTORY_CONTROLLER','workflow.approve'),
        ('DEIMS_CUSTOMS_SPECIALIST','master.read'),
        ('DEIMS_CUSTOMS_SPECIALIST','inventory.read'),
        ('DEIMS_CUSTOMS_SPECIALIST','customs.read'),
        ('DEIMS_CUSTOMS_SPECIALIST','customs.submit'),
        ('DEIMS_CUSTOMS_SPECIALIST','bonded.read'),
        ('DEIMS_CUSTOMS_SPECIALIST','bonded.report'),
        ('DEIMS_CUSTOMS_SPECIALIST','workflow.approve'),
        ('DEIMS_BILLING_SPECIALIST','master.read'),
        ('DEIMS_BILLING_SPECIALIST','billing.read'),
        ('DEIMS_BILLING_SPECIALIST','billing.approve'),
        ('DEIMS_BILLING_SPECIALIST','workflow.approve'),
        ('DEIMS_AUDITOR','master.read'),
        ('DEIMS_AUDITOR','inbound.read'),
        ('DEIMS_AUDITOR','inventory.read'),
        ('DEIMS_AUDITOR','outbound.read'),
        ('DEIMS_AUDITOR','customs.read'),
        ('DEIMS_AUDITOR','bonded.read'),
        ('DEIMS_AUDITOR','billing.read'),
        ('DEIMS_AUDITOR','audit.read'),
        ('DEIMS_AUDITOR','data_access.read'),
        ('DEIMS_AUDITOR','integration.monitor'),
        ('DEIMS_TENANT_ADMIN','iam.user.read'),
        ('DEIMS_TENANT_ADMIN','iam.role.manage'),
        ('DEIMS_TENANT_ADMIN','config.manage'),
        ('DEIMS_TENANT_ADMIN','master.read'),
        ('DEIMS_TENANT_ADMIN','master.manage'),
        ('DEIMS_TENANT_ADMIN','integration.monitor')
)
INSERT INTO deims.role_permissions (
    tenant_id, role_id, permission_id, granted_at,
    row_version, created_at, updated_at
)
SELECT NULL, role_row.id, permission_row.id, now(), 1, now(), now()
FROM grants g
JOIN deims.roles role_row
  ON role_row.tenant_id IS NULL AND role_row.role_code = g.role_code
JOIN deims.permissions permission_row
  ON permission_row.permission_code = g.permission_code
WHERE NOT EXISTS (
    SELECT 1 FROM deims.role_permissions existing
    WHERE existing.role_id = role_row.id
      AND existing.permission_id = permission_row.id
);

WITH seed(entity_type, retention_days, anonymize_after_days, purge_strategy, legal_basis) AS (
    VALUES
        ('login_events',365,180,'ANONYMIZE','Security baseline; validate with company policy and counsel.'),
        ('notifications',180,90,'DELETE','Operational baseline; validate with company policy and counsel.'),
        ('import_export_jobs',365,180,'DELETE','Operational baseline; validate with company policy and counsel.'),
        ('sensor_readings',365,NULL,'ARCHIVE','Operational baseline; validate with company policy and counsel.'),
        ('data_access_logs',730,365,'ANONYMIZE','Privacy/security baseline; validate with company policy and counsel.'),
        ('audit_events',1825,NULL,'ARCHIVE','Audit baseline; validate with company policy and counsel.'),
        ('entity_change_logs',1825,NULL,'ARCHIVE','Audit baseline; validate with company policy and counsel.'),
        ('unipass_messages',1825,NULL,'ARCHIVE','Customs baseline only; confirm statutory obligations with counsel.'),
        ('customs_declarations',1825,NULL,'ARCHIVE','Customs baseline only; confirm statutory obligations with counsel.'),
        ('bonded_records',1825,NULL,'ARCHIVE','Bonded baseline only; confirm statutory obligations with counsel.'),
        ('inventory_ledger',3650,NULL,'ARCHIVE','Financial/stock evidence baseline; validate with company policy and counsel.'),
        ('invoices_settlements_journals',3650,NULL,'ARCHIVE','Tax/accounting baseline only; confirm statutory obligations with counsel.')
)
INSERT INTO deims.data_retention_policies (
    tenant_id, entity_type, retention_days, anonymize_after_days,
    purge_strategy, legal_basis, is_active
)
SELECT NULL, s.entity_type, s.retention_days, s.anonymize_after_days,
       s.purge_strategy, s.legal_basis, true
FROM seed s
WHERE NOT EXISTS (
    SELECT 1 FROM deims.data_retention_policies existing
    WHERE existing.tenant_id IS NULL AND existing.entity_type = s.entity_type
);

-- PostgreSQL grants EXECUTE on newly created functions to PUBLIC by default.  The
-- application allow-list grants only reviewed entry points; trigger/check helpers
-- remain callable by their owner and through the database objects that use them.
REVOKE CREATE ON SCHEMA deims FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA deims FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA deims FROM PUBLIC;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA deims FROM PUBLIC;

COMMENT ON SCHEMA deims IS
    'Enterprise warehouse management: Firebase IAM, 3PL owner inventory, inbound/outbound, double-entry stock ledger, global trade, Korea UNI-PASS metadata, bonded operations, billing, workflow, audit, and analytics.';

-- Enforce tenant policies even for the table owner. The migration runner temporarily removes
-- FORCE only inside the same advisory-locked transaction when reapplying this baseline, then this
-- final block restores it after every seed and integrity object has been created.
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
         WHERE columns.table_schema = 'deims'
           AND columns.column_name = 'tenant_id'
    LOOP
        EXECUTE format(
            'ALTER TABLE %I.%I FORCE ROW LEVEL SECURITY',
            target.table_schema, target.table_name
        );
    END LOOP;
END;
$block$;
