-- EWMS enterprise WMS schema - operational and regulatory gap closure.
-- PostgreSQL 11 compatible. Applied after 13_auth_context_hardening.sql.
-- This forward-only module adds explicit return traceability, inventory/customs
-- execution gates, official UNI-PASS mappings, recall, outbound dock planning,
-- slotting, and WCS/WES/AMR orchestration records.

ALTER TABLE ewms.inventory_statuses
    ADD COLUMN IF NOT EXISTS requires_inventory_freeze boolean NOT NULL DEFAULT false;

ALTER TABLE ewms.inventory_statuses
    ADD COLUMN IF NOT EXISTS blocks_internal_movement boolean NOT NULL DEFAULT false;

DO $block$
BEGIN
    IF NOT EXISTS (
        SELECT 1
          FROM pg_constraint
         WHERE conrelid = 'ewms.inventory_statuses'::regclass
           AND conname = 'ck_ewms_inventory_status_operability'
    ) THEN
        ALTER TABLE ewms.inventory_statuses
            ADD CONSTRAINT ck_ewms_inventory_status_operability CHECK (
                NOT (
                    (available_for_allocation OR available_for_shipping)
                    AND (requires_hold OR requires_inventory_freeze)
                )
                AND NOT (available_for_shipping AND blocks_internal_movement)
            );
    END IF;
END;
$block$;

CREATE OR REPLACE FUNCTION ewms.validate_recall_scope()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, ewms
AS $function$
DECLARE
    campaign_row record;
    campaign_lot_row record;
    lot_row record;
    item_base_uom varchar(20);
    target_tenant_id uuid;
    target_owner_partner_id uuid;
    hold_bucket_row record;
BEGIN
    IF TG_TABLE_NAME = 'recall_campaign_lots' THEN
        SELECT * INTO campaign_row
          FROM ewms.recall_campaigns
         WHERE id = NEW.recall_campaign_id
         FOR SHARE;
        SELECT * INTO lot_row
          FROM ewms.inventory_lots
         WHERE id = NEW.inventory_lot_id
         FOR SHARE;
        SELECT base_uom_code INTO item_base_uom
          FROM ewms.items
         WHERE id = NEW.item_id;
        IF campaign_row.id IS NULL OR lot_row.id IS NULL OR item_base_uom IS NULL THEN
            RAISE EXCEPTION 'Recall lot references an unknown campaign, lot, or item'
                USING ERRCODE = '23503';
        END IF;
        IF campaign_row.tenant_id <> NEW.tenant_id
           OR lot_row.tenant_id <> NEW.tenant_id
           OR lot_row.owner_partner_id <> campaign_row.owner_partner_id
           OR lot_row.item_id <> NEW.item_id
           OR NEW.base_uom_code <> item_base_uom THEN
            RAISE EXCEPTION 'Recall campaign lot crosses tenant/owner/item/base-unit scope'
                USING ERRCODE = '23514';
        END IF;
        IF NEW.inventory_hold_id IS NOT NULL THEN
            SELECT bucket.* INTO hold_bucket_row
              FROM ewms.inventory_holds hold_row
              JOIN ewms.stock_buckets bucket ON bucket.id = hold_row.stock_bucket_id
             WHERE hold_row.id = NEW.inventory_hold_id
               AND hold_row.tenant_id = NEW.tenant_id
               AND hold_row.hold_type = 'RECALL'
               AND hold_row.status IN ('ACTIVE','PARTIALLY_RELEASED');
            IF hold_bucket_row.id IS NULL
               OR hold_bucket_row.inventory_lot_id <> NEW.inventory_lot_id
               OR hold_bucket_row.item_id <> NEW.item_id
               OR hold_bucket_row.owner_partner_id <> campaign_row.owner_partner_id THEN
                RAISE EXCEPTION 'Recall lot hold must be an active RECALL hold on the same stock lot'
                    USING ERRCODE = '23514';
            END IF;
        END IF;
    ELSE
        SELECT * INTO campaign_row
          FROM ewms.recall_campaigns
         WHERE id = NEW.recall_campaign_id
         FOR SHARE;
        IF campaign_row.id IS NULL OR campaign_row.tenant_id <> NEW.tenant_id THEN
            RAISE EXCEPTION 'Recall action references an invalid tenant-scoped campaign'
                USING ERRCODE = '23503';
        END IF;
        IF NEW.recall_campaign_lot_id IS NOT NULL THEN
            SELECT * INTO campaign_lot_row
              FROM ewms.recall_campaign_lots
             WHERE id = NEW.recall_campaign_lot_id;
            IF campaign_lot_row.id IS NULL
               OR campaign_lot_row.recall_campaign_id <> campaign_row.id
               OR campaign_lot_row.tenant_id <> NEW.tenant_id THEN
                RAISE EXCEPTION 'Recall action lot is outside its campaign'
                    USING ERRCODE = '23514';
            END IF;
        END IF;

        IF NEW.stock_bucket_id IS NOT NULL THEN
            SELECT tenant_id, owner_partner_id INTO target_tenant_id, target_owner_partner_id
              FROM ewms.stock_buckets WHERE id = NEW.stock_bucket_id;
        ELSIF NEW.shipment_id IS NOT NULL THEN
            SELECT tenant_id, owner_partner_id INTO target_tenant_id, target_owner_partner_id
              FROM ewms.shipments WHERE id = NEW.shipment_id;
        ELSIF NEW.receipt_id IS NOT NULL THEN
            SELECT tenant_id, owner_partner_id INTO target_tenant_id, target_owner_partner_id
              FROM ewms.receipts WHERE id = NEW.receipt_id;
        ELSIF NEW.customer_return_order_id IS NOT NULL THEN
            SELECT tenant_id, owner_partner_id INTO target_tenant_id, target_owner_partner_id
              FROM ewms.customer_return_orders WHERE id = NEW.customer_return_order_id;
        ELSIF NEW.partner_id IS NOT NULL THEN
            SELECT tenant_id, id INTO target_tenant_id, target_owner_partner_id
              FROM ewms.business_partners WHERE id = NEW.partner_id;
        ELSE
            target_tenant_id := NEW.tenant_id;
            target_owner_partner_id := campaign_row.owner_partner_id;
        END IF;
        IF target_tenant_id IS DISTINCT FROM NEW.tenant_id
           OR (NEW.target_type NOT IN ('PARTNER','AUTHORITY','CAMPAIGN')
               AND target_owner_partner_id IS DISTINCT FROM campaign_row.owner_partner_id) THEN
            RAISE EXCEPTION 'Recall action target crosses tenant or inventory-owner boundary'
                USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION ewms.validate_outbound_dock_link()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, ewms
AS $function$
DECLARE
    appointment_row record;
    target_tenant_id uuid;
    target_warehouse_id uuid;
    target_id uuid;
BEGIN
    SELECT * INTO appointment_row
      FROM ewms.dock_appointments
     WHERE id = NEW.appointment_id
     FOR SHARE;
    IF appointment_row.id IS NULL OR appointment_row.tenant_id <> NEW.tenant_id THEN
        RAISE EXCEPTION 'Outbound dock link references an invalid tenant-scoped appointment'
            USING ERRCODE = '23503';
    END IF;
    IF appointment_row.appointment_type NOT IN ('OUTBOUND','BOTH')
       OR appointment_row.status IN ('CHECKED_OUT','NO_SHOW','CANCELLED') THEN
        RAISE EXCEPTION 'Appointment % is not an open outbound appointment', NEW.appointment_id
            USING ERRCODE = '23514';
    END IF;
    IF TG_TABLE_NAME = 'dock_appointment_outbound_orders' THEN
        target_id := NEW.outbound_order_id;
        SELECT tenant_id, warehouse_id INTO target_tenant_id, target_warehouse_id
          FROM ewms.outbound_orders WHERE id = target_id;
    ELSIF TG_TABLE_NAME = 'dock_appointment_shipments' THEN
        target_id := NEW.shipment_id;
        SELECT tenant_id, warehouse_id INTO target_tenant_id, target_warehouse_id
          FROM ewms.shipments WHERE id = target_id;
    ELSE
        target_id := NEW.load_id;
        SELECT tenant_id, warehouse_id INTO target_tenant_id, target_warehouse_id
          FROM ewms.loads WHERE id = target_id;
    END IF;
    IF target_tenant_id IS NULL THEN
        RAISE EXCEPTION 'Outbound dock link target % does not exist', target_id
            USING ERRCODE = '23503';
    END IF;
    IF target_tenant_id <> NEW.tenant_id
       OR target_warehouse_id <> appointment_row.warehouse_id THEN
        RAISE EXCEPTION 'Outbound dock link target crosses tenant or warehouse boundary'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION ewms.protect_outbound_dock_link()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    old_core jsonb;
    new_core jsonb;
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'Outbound dock links cannot be deleted; mark the link CANCELLED'
            USING ERRCODE = '55000';
    END IF;
    old_core := to_jsonb(OLD) - ARRAY[
        'status','cancelled_by','cancelled_at','cancellation_reason','row_version','updated_at'
    ]::text[];
    new_core := to_jsonb(NEW) - ARRAY[
        'status','cancelled_by','cancelled_at','cancellation_reason','row_version','updated_at'
    ]::text[];
    IF old_core IS DISTINCT FROM new_core THEN
        RAISE EXCEPTION 'Outbound dock link identity is immutable'
            USING ERRCODE = '55000';
    END IF;
    IF OLD.status = 'CANCELLED' OR NEW.status NOT IN (OLD.status, 'CANCELLED') THEN
        RAISE EXCEPTION 'Cancelled outbound dock links are final'
            USING ERRCODE = '55000';
    END IF;
    RETURN NEW;
END;
$function$;

DO $block$
DECLARE
    table_name text;
BEGIN
    FOREACH table_name IN ARRAY ARRAY[
        'dock_appointment_outbound_orders','dock_appointment_shipments','dock_appointment_loads'
    ]::text[]
    LOOP
        IF to_regclass(format('ewms.%I', table_name)) IS NULL THEN
            CONTINUE;
        END IF;
        EXECUTE format('DROP TRIGGER IF EXISTS trg_validate_outbound_dock_link ON ewms.%I', table_name);
        EXECUTE format(
            'CREATE TRIGGER trg_validate_outbound_dock_link BEFORE INSERT OR UPDATE ON ewms.%I '
            'FOR EACH ROW EXECUTE PROCEDURE ewms.validate_outbound_dock_link()', table_name
        );
        EXECUTE format('DROP TRIGGER IF EXISTS trg_protect_outbound_dock_link ON ewms.%I', table_name);
        EXECUTE format(
            'CREATE TRIGGER trg_protect_outbound_dock_link BEFORE UPDATE OR DELETE ON ewms.%I '
            'FOR EACH ROW EXECUTE PROCEDURE ewms.protect_outbound_dock_link()', table_name
        );
    END LOOP;
END;
$block$;

/* Deferred duplicate block: the executable copy is appended after all CREATE TABLE statements.
-- Wire triggers that depend on tables created by this module. Some trigger helper
-- functions are declared near the top so existing-table gates take effect early;
-- all new-table trigger creation is intentionally centralized here.
DROP TRIGGER IF EXISTS trg_validate_inventory_customs_status_transition
    ON ewms.inventory_customs_status_transitions;
CREATE TRIGGER trg_validate_inventory_customs_status_transition
    BEFORE INSERT ON ewms.inventory_customs_status_transitions
    FOR EACH ROW EXECUTE PROCEDURE ewms.validate_inventory_customs_status_transition();

DROP TRIGGER IF EXISTS trg_validate_shipping_customs_release_allocation
    ON ewms.shipping_customs_release_allocations;
CREATE TRIGGER trg_validate_shipping_customs_release_allocation
    BEFORE INSERT ON ewms.shipping_customs_release_allocations
    FOR EACH ROW EXECUTE PROCEDURE ewms.validate_shipping_customs_release_allocation();

DROP TRIGGER IF EXISTS trg_deferred_shipping_customs_release
    ON ewms.shipping_inventory_allocations;
CREATE CONSTRAINT TRIGGER trg_deferred_shipping_customs_release
    AFTER INSERT OR UPDATE OR DELETE ON ewms.shipping_inventory_allocations
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE PROCEDURE ewms.deferred_assert_shipping_customs_release();

DROP TRIGGER IF EXISTS trg_deferred_shipping_customs_release_alloc
    ON ewms.shipping_customs_release_allocations;
CREATE CONSTRAINT TRIGGER trg_deferred_shipping_customs_release_alloc
    AFTER INSERT OR UPDATE OR DELETE ON ewms.shipping_customs_release_allocations
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE PROCEDURE ewms.deferred_assert_shipping_customs_release();

DROP TRIGGER IF EXISTS trg_validate_recall_campaign_lot ON ewms.recall_campaign_lots;
CREATE TRIGGER trg_validate_recall_campaign_lot
    BEFORE INSERT OR UPDATE ON ewms.recall_campaign_lots
    FOR EACH ROW EXECUTE PROCEDURE ewms.validate_recall_scope();
DROP TRIGGER IF EXISTS trg_validate_recall_action ON ewms.recall_actions;
CREATE TRIGGER trg_validate_recall_action
    BEFORE INSERT OR UPDATE ON ewms.recall_actions
    FOR EACH ROW EXECUTE PROCEDURE ewms.validate_recall_scope();
DROP TRIGGER IF EXISTS trg_validate_slotting_recommendation ON ewms.slotting_recommendations;
CREATE TRIGGER trg_validate_slotting_recommendation
    BEFORE INSERT OR UPDATE ON ewms.slotting_recommendations
    FOR EACH ROW EXECUTE PROCEDURE ewms.validate_slotting_recommendation();

DO $block$
DECLARE
    table_name text;
BEGIN
    FOREACH table_name IN ARRAY ARRAY[
        'dock_appointment_outbound_orders','dock_appointment_shipments','dock_appointment_loads'
    ]::text[]
    LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS trg_validate_outbound_dock_link ON ewms.%I', table_name);
        EXECUTE format(
            'CREATE TRIGGER trg_validate_outbound_dock_link BEFORE INSERT OR UPDATE ON ewms.%I '
            'FOR EACH ROW EXECUTE PROCEDURE ewms.validate_outbound_dock_link()', table_name
        );
        EXECUTE format('DROP TRIGGER IF EXISTS trg_protect_outbound_dock_link ON ewms.%I', table_name);
        EXECUTE format(
            'CREATE TRIGGER trg_protect_outbound_dock_link BEFORE UPDATE OR DELETE ON ewms.%I '
            'FOR EACH ROW EXECUTE PROCEDURE ewms.protect_outbound_dock_link()', table_name
        );
    END LOOP;
END;
$block$;

-- Finalized business rows are immutable. Corrections use a new run/action/mission,
-- reversal inventory transaction, or a new official mapping version.
DO $block$
DECLARE
    target record;
BEGIN
    FOR target IN
        SELECT * FROM (VALUES
            ('customer_return_orders','status','CLOSED,REJECTED,CANCELLED'),
            ('recall_campaigns','status','CLOSED,CANCELLED'),
            ('recall_campaign_lots','trace_status','DESTROYED,RELEASED,EXCLUDED'),
            ('recall_actions','status','COMPLETED,FAILED,CANCELLED'),
            ('slotting_runs','status','COMPLETED,FAILED,CANCELLED'),
            ('slotting_recommendations','status','APPLIED,REJECTED,EXPIRED,CANCELLED'),
            ('automation_systems','status','RETIRED'),
            ('automation_resources','operational_status','RETIRED'),
            ('automation_missions','status','COMPLETED,FAILED,CANCELLED,SUPERSEDED'),
            ('automation_mission_steps','status','COMPLETED,FAILED,SKIPPED,CANCELLED')
        ) AS configured(table_name, status_column, terminal_statuses)
    LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS trg_14_protect_finalized ON ewms.%I', target.table_name);
        EXECUTE format(
            'CREATE TRIGGER trg_14_protect_finalized BEFORE UPDATE OR DELETE ON ewms.%I '
            'FOR EACH ROW EXECUTE PROCEDURE ewms.protect_finalized_row(%L,%L)',
            target.table_name, target.status_column, target.terminal_statuses
        );
    END LOOP;
END;
$block$;

-- Append-only evidence and lineage. TRUNCATE is protected separately because row
-- DELETE triggers do not fire for TRUNCATE in PostgreSQL 11.
DO $block$
DECLARE
    table_name text;
BEGIN
    FOREACH table_name IN ARRAY ARRAY[
        'customer_return_status_history','customer_return_receipt_allocations',
        'customer_return_quality_allocations','customer_return_disposition_allocations',
        'customer_return_inventory_allocations','recall_campaign_status_history',
        'recall_action_events','slotting_recommendation_events','automation_events',
        'inventory_customs_status_transitions','shipping_customs_release_allocations'
    ]::text[]
    LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS trg_14_append_only ON ewms.%I', table_name);
        EXECUTE format(
            'CREATE TRIGGER trg_14_append_only BEFORE UPDATE OR DELETE ON ewms.%I '
            'FOR EACH ROW EXECUTE PROCEDURE ewms.prevent_append_only_change()', table_name
        );
        EXECUTE format('DROP TRIGGER IF EXISTS trg_14_append_only_truncate ON ewms.%I', table_name);
        EXECUTE format(
            'CREATE TRIGGER trg_14_append_only_truncate BEFORE TRUNCATE ON ewms.%I '
            'FOR EACH STATEMENT EXECUTE PROCEDURE ewms.prevent_append_only_change()', table_name
        );
    END LOOP;
END;
$block$;

DROP TRIGGER IF EXISTS trg_14_customs_legal_status_append_only
    ON ewms.customs_inventory_legal_statuses;
CREATE TRIGGER trg_14_customs_legal_status_append_only
    BEFORE UPDATE OR DELETE ON ewms.customs_inventory_legal_statuses
    FOR EACH ROW EXECUTE PROCEDURE ewms.prevent_append_only_change();
DROP TRIGGER IF EXISTS trg_14_customs_legal_status_truncate
    ON ewms.customs_inventory_legal_statuses;
CREATE TRIGGER trg_14_customs_legal_status_truncate
    BEFORE TRUNCATE ON ewms.customs_inventory_legal_statuses
    FOR EACH STATEMENT EXECUTE PROCEDURE ewms.prevent_append_only_change();

-- New mutable rows receive optimistic locking, and tenant_id never changes.
DO $block$
DECLARE
    target record;
BEGIN
    FOR target IN
        SELECT DISTINCT columns.table_name
          FROM information_schema.columns columns
          JOIN information_schema.columns version_column
            ON version_column.table_schema = columns.table_schema
           AND version_column.table_name = columns.table_name
           AND version_column.column_name = 'row_version'
         WHERE columns.table_schema = 'ewms'
           AND columns.column_name = 'updated_at'
           AND columns.table_name = ANY (ARRAY[
               'recall_campaigns','recall_campaign_lots','recall_actions',
               'dock_appointment_outbound_orders','dock_appointment_shipments','dock_appointment_loads',
               'slotting_runs','slotting_recommendations','automation_systems',
               'automation_resources','automation_missions','automation_mission_steps'
           ]::text[])
    LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS trg_touch_row ON ewms.%I', target.table_name);
        EXECUTE format(
            'CREATE TRIGGER trg_touch_row BEFORE UPDATE ON ewms.%I '
            'FOR EACH ROW EXECUTE PROCEDURE ewms.touch_row()', target.table_name
        );
    END LOOP;
END;
$block$;

DO $block$
DECLARE
    table_name text;
BEGIN
    FOREACH table_name IN ARRAY ARRAY[
        'customer_return_status_history','customer_return_receipt_allocations',
        'customer_return_quality_allocations','customer_return_disposition_allocations',
        'customer_return_inventory_allocations','recall_campaigns','recall_campaign_status_history',
        'recall_campaign_lots','recall_actions','recall_action_events',
        'dock_appointment_outbound_orders','dock_appointment_shipments','dock_appointment_loads',
        'slotting_runs','slotting_recommendations','slotting_recommendation_events',
        'automation_systems','automation_resources','automation_missions',
        'automation_mission_steps','automation_events','inventory_customs_status_transitions',
        'shipping_customs_release_allocations'
    ]::text[]
    LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS trg_prevent_tenant_change ON ewms.%I', table_name);
        EXECUTE format(
            'CREATE TRIGGER trg_prevent_tenant_change BEFORE UPDATE OF tenant_id ON ewms.%I '
            'FOR EACH ROW EXECUTE PROCEDURE ewms.prevent_tenant_change()', table_name
        );
    END LOOP;
END;
$block$;

-- Add same-tenant guards for simple UUID FKs to tenant-scoped EWMS parents. Composite
-- (tenant_id,id) FKs are already stronger and are skipped.
DO $block$
DECLARE
    relation record;
    child_column text;
    trigger_name text;
BEGIN
    FOR relation IN
        SELECT con.oid, con.conname, con.conrelid, con.confrelid,
               child.relname AS child_table, parent_ns.nspname AS parent_schema,
               parent.relname AS parent_table, con.conkey[1] AS child_attnum
          FROM pg_constraint con
          JOIN pg_class child ON child.oid = con.conrelid
          JOIN pg_namespace child_ns ON child_ns.oid = child.relnamespace
          JOIN pg_class parent ON parent.oid = con.confrelid
          JOIN pg_namespace parent_ns ON parent_ns.oid = parent.relnamespace
         WHERE con.contype = 'f'
           AND child_ns.nspname = 'ewms' AND parent_ns.nspname = 'ewms'
           AND child.relname = ANY (ARRAY[
               'customer_return_status_history','customer_return_receipt_allocations',
               'customer_return_quality_allocations','customer_return_disposition_allocations',
               'customer_return_inventory_allocations','recall_campaigns','recall_campaign_status_history',
               'recall_campaign_lots','recall_actions','recall_action_events',
               'dock_appointment_outbound_orders','dock_appointment_shipments','dock_appointment_loads',
               'slotting_runs','slotting_recommendations','slotting_recommendation_events',
               'automation_systems','automation_resources','automation_missions',
               'automation_mission_steps','automation_events','inventory_customs_status_transitions',
               'shipping_customs_release_allocations'
           ]::text[])
           AND array_length(con.conkey, 1) = 1
           AND EXISTS (SELECT 1 FROM pg_attribute a
                        WHERE a.attrelid = con.confrelid AND a.attname = 'tenant_id' AND NOT a.attisdropped)
           AND EXISTS (SELECT 1 FROM pg_attribute a
                        WHERE a.attrelid = con.confrelid AND a.attnum = con.confkey[1] AND a.attname = 'id')
    LOOP
        SELECT attname INTO child_column FROM pg_attribute
         WHERE attrelid = relation.conrelid AND attnum = relation.child_attnum;
        IF child_column = 'tenant_id' THEN CONTINUE; END IF;
        IF EXISTS (
            SELECT 1 FROM pg_constraint companion
             WHERE companion.contype = 'f'
               AND companion.conrelid = relation.conrelid
               AND companion.confrelid = relation.confrelid
               AND array_length(companion.conkey, 1) >= 2
               AND relation.child_attnum = ANY (companion.conkey)
        ) THEN CONTINUE; END IF;
        trigger_name := 'trg_tenant_fk_' || substr(
            md5('ewms.' || relation.child_table || '.' || relation.conname), 1, 12
        );
        EXECUTE format('DROP TRIGGER IF EXISTS %I ON ewms.%I', trigger_name, relation.child_table);
        EXECUTE format(
            'CREATE TRIGGER %I BEFORE INSERT OR UPDATE OF %I ON ewms.%I '
            'FOR EACH ROW EXECUTE PROCEDURE ewms.enforce_same_tenant_fk(%L,%L,%L)',
            trigger_name, child_column, relation.child_table,
            child_column, relation.parent_schema, relation.parent_table
        );
    END LOOP;
END;
$block$;

-- Every FK receives a valid non-partial leading-column index; PostgreSQL does not
-- create indexes on the referencing side automatically.
DO $block$
DECLARE
    relation record;
    column_list text;
    index_name text;
BEGIN
    FOR relation IN
        SELECT con.oid, con.conname, con.conrelid, child.relname AS table_name, con.conkey
          FROM pg_constraint con
          JOIN pg_class child ON child.oid = con.conrelid
          JOIN pg_namespace child_ns ON child_ns.oid = child.relnamespace
         WHERE con.contype = 'f' AND child_ns.nspname = 'ewms'
           AND child.relname = ANY (ARRAY[
               'customer_return_status_history','customer_return_receipt_allocations',
               'customer_return_quality_allocations','customer_return_disposition_allocations',
               'customer_return_inventory_allocations','recall_campaigns','recall_campaign_status_history',
               'recall_campaign_lots','recall_actions','recall_action_events',
               'dock_appointment_outbound_orders','dock_appointment_shipments','dock_appointment_loads',
               'slotting_runs','slotting_recommendations','slotting_recommendation_events',
               'automation_systems','automation_resources','automation_missions',
               'automation_mission_steps','automation_events','inventory_customs_status_transitions',
               'shipping_customs_release_allocations','unipass_mapping_versions',
               'unipass_code_mapping_versions','unipass_code_mappings','unipass_field_mappings'
           ]::text[])
         ORDER BY child.relname, array_length(con.conkey, 1) DESC, con.conname
    LOOP
        SELECT string_agg(quote_ident(attribute.attname), ', ' ORDER BY key_column.ordinality)
          INTO column_list
          FROM unnest(relation.conkey) WITH ORDINALITY AS key_column(attnum, ordinality)
          JOIN pg_attribute attribute
            ON attribute.attrelid = relation.conrelid AND attribute.attnum = key_column.attnum;
        IF EXISTS (
            SELECT 1 FROM pg_index index_row
             WHERE index_row.indrelid = relation.conrelid
               AND index_row.indisvalid AND index_row.indisready AND index_row.indpred IS NULL
               AND index_row.indnkeyatts >= array_length(relation.conkey, 1)
               AND ARRAY(
                   SELECT index_column.attnum
                     FROM unnest(index_row.indkey) WITH ORDINALITY AS index_column(attnum, ordinality)
                    WHERE index_column.ordinality <= array_length(relation.conkey, 1)
                    ORDER BY index_column.ordinality
               )::smallint[] = relation.conkey
        ) THEN CONTINUE; END IF;
        index_name := 'ix_fk14_' || substr(relation.table_name, 1, 28) || '_' ||
            substr(md5(relation.table_name || '.' || relation.conname), 1, 10);
        EXECUTE format('CREATE INDEX IF NOT EXISTS %I ON ewms.%I (%s)',
            index_name, relation.table_name, column_list);
    END LOOP;
END;
$block$;

-- Exact tenant policies required by the hardened authenticated context in module 13.
DO $block$
DECLARE
    table_name text;
BEGIN
    FOREACH table_name IN ARRAY ARRAY[
        'customer_return_status_history','customer_return_receipt_allocations',
        'customer_return_quality_allocations','customer_return_disposition_allocations',
        'customer_return_inventory_allocations','recall_campaigns','recall_campaign_status_history',
        'recall_campaign_lots','recall_actions','recall_action_events',
        'dock_appointment_outbound_orders','dock_appointment_shipments','dock_appointment_loads',
        'slotting_runs','slotting_recommendations','slotting_recommendation_events',
        'automation_systems','automation_resources','automation_missions',
        'automation_mission_steps','automation_events','inventory_customs_status_transitions',
        'shipping_customs_release_allocations'
    ]::text[]
    LOOP
        EXECUTE format('ALTER TABLE ewms.%I ENABLE ROW LEVEL SECURITY', table_name);
        EXECUTE format('DROP POLICY IF EXISTS tenant_select ON ewms.%I', table_name);
        EXECUTE format('DROP POLICY IF EXISTS tenant_modify ON ewms.%I', table_name);
        EXECUTE format(
            'CREATE POLICY tenant_select ON ewms.%I FOR SELECT '
            'USING (tenant_id = ewms.current_tenant_id())', table_name
        );
        EXECUTE format(
            'CREATE POLICY tenant_modify ON ewms.%I FOR ALL '
            'USING (tenant_id = ewms.current_tenant_id()) '
            'WITH CHECK (tenant_id = ewms.current_tenant_id())', table_name
        );
        EXECUTE format('ALTER TABLE ewms.%I FORCE ROW LEVEL SECURITY', table_name);
    END LOOP;
END;
$block$;

REVOKE ALL ON SCHEMA ewms FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA ewms FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA ewms FROM PUBLIC;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA ewms FROM PUBLIC;

COMMENT ON TABLE ewms.inventory_customs_status_transitions IS
    'Append-only evidence bridge for balanced ledger moves between customs legal statuses; FOREIGN to DOMESTIC requires current line-level import-release evidence.';
COMMENT ON TABLE ewms.shipping_customs_release_allocations IS
    'Exact quantity coverage between a physical shipping allocation and current official UNI-PASS release evidence.';
COMMENT ON TABLE ewms.automation_events IS
    'Append-only WCS/WES/AMR event envelope. Payload bytes remain in protected object storage; the database retains URI/hash and a non-secret summary.';
*/

CREATE OR REPLACE FUNCTION ewms.validate_shipping_customs_release_allocation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, ewms
AS $function$
DECLARE
    shipping_row record;
    confirmation_row record;
    shipment_row record;
    bucket_row record;
    coverage_row record;
    evidence_row record;
    allocated_to_shipping numeric(24,8);
    allocated_to_coverage numeric(24,8);
BEGIN
    -- Serialize every quantity consumer on both limiting parents. FOR SHARE lets
    -- concurrent inserts observe the same pre-insert SUM and over-consume the
    -- physical allocation or official release coverage under READ COMMITTED.
    SELECT * INTO shipping_row FROM ewms.shipping_inventory_allocations
     WHERE id = NEW.shipping_inventory_allocation_id FOR UPDATE;
    SELECT * INTO bucket_row FROM ewms.stock_buckets
     WHERE id = NEW.source_stock_bucket_id FOR SHARE;
    SELECT * INTO coverage_row FROM ewms.customs_release_line_coverages
     WHERE id = NEW.customs_release_line_coverage_id FOR UPDATE;
    IF shipping_row.id IS NULL OR bucket_row.id IS NULL OR coverage_row.id IS NULL THEN
        RAISE EXCEPTION 'Shipping customs allocation references an unknown allocation, bucket, or release coverage'
            USING ERRCODE = '23503';
    END IF;
    SELECT * INTO confirmation_row FROM ewms.shipping_confirmations
     WHERE id = shipping_row.shipping_confirmation_id FOR SHARE;
    SELECT * INTO shipment_row FROM ewms.shipments
     WHERE id = confirmation_row.shipment_id FOR SHARE;
    SELECT * INTO evidence_row FROM ewms.customs_release_evidence
     WHERE id = coverage_row.customs_release_evidence_id FOR SHARE;
    IF confirmation_row.id IS NULL OR shipment_row.id IS NULL OR evidence_row.id IS NULL
       OR NOT ewms.customs_release_evidence_is_current(evidence_row.id) THEN
        RAISE EXCEPTION 'Shipping customs allocation requires current official UNI-PASS release evidence'
            USING ERRCODE = '23514';
    END IF;
    IF shipping_row.tenant_id <> NEW.tenant_id
       OR bucket_row.tenant_id <> NEW.tenant_id
       OR coverage_row.tenant_id <> NEW.tenant_id
       OR evidence_row.tenant_id <> NEW.tenant_id
       OR shipment_row.tenant_id <> NEW.tenant_id
       OR shipping_row.source_stock_bucket_id <> bucket_row.id
       OR NEW.source_stock_bucket_id <> bucket_row.id
       OR coverage_row.shipment_line_id <> shipping_row.shipment_line_id
       OR evidence_row.shipment_id <> shipment_row.id
       OR evidence_row.owner_partner_id <> bucket_row.owner_partner_id
       OR bucket_row.item_id <> coverage_row.item_id_snapshot
       OR bucket_row.country_of_origin IS DISTINCT FROM coverage_row.country_of_origin_snapshot
       OR NEW.base_uom_code <> shipping_row.base_uom_code
       OR NEW.base_uom_code <> coverage_row.base_uom_code THEN
        RAISE EXCEPTION 'Shipping customs evidence does not match shipment line, owner, item, origin, bucket, or base unit'
            USING ERRCODE = '23514';
    END IF;
    IF (NEW.release_purpose = 'DOMESTIC_RELEASE' AND evidence_row.evidence_type <> 'IMPORT_RELEASE')
       OR (NEW.release_purpose = 'EXPORT' AND evidence_row.evidence_type NOT IN ('EXPORT_CLEARANCE','RETURN_RELEASE'))
       OR (NEW.release_purpose = 'BONDED_TRANSFER' AND evidence_row.evidence_type NOT IN ('BONDED_RELEASE','TRANSIT_RELEASE'))
       OR (NEW.release_purpose = 'RETURN' AND evidence_row.evidence_type <> 'RETURN_RELEASE')
       OR (NEW.release_purpose = 'DISPOSAL' AND evidence_row.evidence_type <> 'BONDED_RELEASE') THEN
        RAISE EXCEPTION 'Release purpose % is incompatible with official evidence type %',
            NEW.release_purpose, evidence_row.evidence_type USING ERRCODE = '23514';
    END IF;
    IF bucket_row.customs_legal_status_code = 'EXPORT' AND NEW.release_purpose <> 'EXPORT'
       OR bucket_row.customs_legal_status_code = 'BONDED_TRANSIT' AND NEW.release_purpose <> 'BONDED_TRANSFER'
       OR bucket_row.customs_legal_status_code = 'FOREIGN' THEN
        RAISE EXCEPTION 'Customs legal status % is incompatible with shipping release purpose %',
            bucket_row.customs_legal_status_code, NEW.release_purpose USING ERRCODE = '23514';
    END IF;
    SELECT COALESCE(sum(released_base_quantity), 0) INTO allocated_to_shipping
      FROM ewms.shipping_customs_release_allocations
     WHERE shipping_inventory_allocation_id = NEW.shipping_inventory_allocation_id;
    SELECT COALESCE(sum(released_base_quantity), 0) INTO allocated_to_coverage
      FROM ewms.shipping_customs_release_allocations
     WHERE customs_release_line_coverage_id = NEW.customs_release_line_coverage_id;
    IF allocated_to_shipping + NEW.released_base_quantity > shipping_row.allocated_quantity
       OR allocated_to_coverage + NEW.released_base_quantity > coverage_row.covered_base_quantity THEN
        RAISE EXCEPTION 'Shipping customs allocation exceeds physical allocation or official release coverage'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION ewms.assert_shipping_customs_release(p_shipping_allocation_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, ewms
AS $function$
DECLARE
    shipping_row record;
    bucket_row record;
    legal_status_row record;
    shipment_row record;
    released_quantity numeric(24,8);
BEGIN
    SELECT * INTO shipping_row FROM ewms.shipping_inventory_allocations
     WHERE id = p_shipping_allocation_id;
    IF shipping_row.id IS NULL THEN RETURN; END IF;
    SELECT * INTO bucket_row FROM ewms.stock_buckets
     WHERE id = shipping_row.source_stock_bucket_id;
    IF bucket_row.customs_legal_status_code IS NULL THEN RETURN; END IF;
    SELECT * INTO legal_status_row FROM ewms.customs_inventory_legal_statuses
     WHERE legal_status_code = bucket_row.customs_legal_status_code;
    SELECT shipment.* INTO shipment_row
      FROM ewms.shipping_confirmations confirmation
      JOIN ewms.shipments shipment ON shipment.id = confirmation.shipment_id
     WHERE confirmation.id = shipping_row.shipping_confirmation_id;
    IF bucket_row.customs_legal_status_code = 'FOREIGN' THEN
        RAISE EXCEPTION 'Unreleased FOREIGN inventory cannot be physically shipped'
            USING ERRCODE = '23514';
    END IF;
    IF legal_status_row.requires_release_evidence THEN
        IF shipment_row.id IS NULL OR NOT shipment_row.customs_release_required THEN
            RAISE EXCEPTION 'Customs-controlled stock requires shipment.customs_release_required'
                USING ERRCODE = '23514';
        END IF;
        SELECT COALESCE(sum(released_base_quantity), 0) INTO released_quantity
          FROM ewms.shipping_customs_release_allocations
         WHERE shipping_inventory_allocation_id = p_shipping_allocation_id;
        IF released_quantity <> shipping_row.allocated_quantity THEN
            RAISE EXCEPTION 'Shipping allocation % has customs evidence coverage %, expected %',
                p_shipping_allocation_id, released_quantity, shipping_row.allocated_quantity
                USING ERRCODE = '23514';
        END IF;
    END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION ewms.deferred_assert_shipping_customs_release()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, ewms
AS $function$
DECLARE
    old_allocation_id uuid;
    new_allocation_id uuid;
BEGIN
    IF TG_TABLE_NAME = 'shipping_inventory_allocations' THEN
        old_allocation_id := CASE WHEN TG_OP IN ('UPDATE','DELETE') THEN OLD.id ELSE NULL END;
        new_allocation_id := CASE WHEN TG_OP IN ('INSERT','UPDATE') THEN NEW.id ELSE NULL END;
    ELSE
        old_allocation_id := CASE WHEN TG_OP IN ('UPDATE','DELETE') THEN OLD.shipping_inventory_allocation_id ELSE NULL END;
        new_allocation_id := CASE WHEN TG_OP IN ('INSERT','UPDATE') THEN NEW.shipping_inventory_allocation_id ELSE NULL END;
    END IF;
    IF old_allocation_id IS NOT NULL THEN
        PERFORM ewms.assert_shipping_customs_release(old_allocation_id);
    END IF;
    IF new_allocation_id IS NOT NULL AND new_allocation_id IS DISTINCT FROM old_allocation_id THEN
        PERFORM ewms.assert_shipping_customs_release(new_allocation_id);
    END IF;
    RETURN NULL;
END;
$function$;

CREATE OR REPLACE FUNCTION ewms.validate_inventory_operational_gate()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, ewms
AS $function$
DECLARE
    row_data jsonb := to_jsonb(NEW);
    bucket_id uuid;
    bucket_row record;
    inventory_status_row record;
    customs_status_row record;
    operation_code varchar(40);
    must_check boolean := true;
BEGIN
    IF TG_TABLE_NAME = 'shipping_inventory_allocations' THEN
        bucket_id := NULLIF(row_data ->> 'source_stock_bucket_id', '')::uuid;
        operation_code := 'SHIPMENT';
    ELSE
        bucket_id := NULLIF(row_data ->> 'stock_bucket_id', '')::uuid;
        operation_code := 'PICK';
        IF row_data ->> 'status' IN ('RELEASED','CONSUMED','CANCELLED','EXPIRED','SHORT') THEN
            must_check := false;
        END IF;
    END IF;
    IF NOT must_check THEN RETURN NEW; END IF;

    SELECT bucket.*, location.zone_id AS bucket_zone_id
      INTO bucket_row
      FROM ewms.stock_buckets bucket
      LEFT JOIN ewms.warehouse_locations location ON location.id = bucket.location_id
     WHERE bucket.id = bucket_id
     FOR SHARE OF bucket;
    IF bucket_row.id IS NULL OR bucket_row.tenant_id <> NEW.tenant_id THEN
        RAISE EXCEPTION 'Inventory operation references an invalid tenant-scoped stock bucket'
            USING ERRCODE = '23503';
    END IF;
    SELECT status.* INTO inventory_status_row
      FROM ewms.inventory_statuses status
     WHERE status.id = bucket_row.inventory_status_id
       AND status.is_active
       AND (status.tenant_id IS NULL OR status.tenant_id = NEW.tenant_id);
    IF inventory_status_row.id IS NULL
       OR (operation_code = 'PICK' AND NOT inventory_status_row.available_for_allocation)
       OR (operation_code = 'SHIPMENT' AND NOT inventory_status_row.available_for_shipping)
       OR inventory_status_row.requires_hold
       OR inventory_status_row.requires_inventory_freeze THEN
        RAISE EXCEPTION 'Stock bucket % inventory status is not eligible for %', bucket_id, operation_code
            USING ERRCODE = '23514';
    END IF;
    IF EXISTS (
        SELECT 1 FROM ewms.inventory_holds hold_row
         WHERE hold_row.tenant_id = NEW.tenant_id
           AND hold_row.stock_bucket_id = bucket_id
           AND hold_row.status IN ('ACTIVE','PARTIALLY_RELEASED')
           AND hold_row.held_quantity > hold_row.released_quantity
    ) THEN
        RAISE EXCEPTION 'Stock bucket % has an active inventory hold', bucket_id
            USING ERRCODE = '23514';
    END IF;
    IF EXISTS (
        SELECT 1 FROM ewms.inventory_freezes freeze_row
         WHERE freeze_row.tenant_id = NEW.tenant_id
           AND freeze_row.warehouse_id = bucket_row.warehouse_id
           AND freeze_row.status = 'ACTIVE'
           AND (freeze_row.expires_at IS NULL OR freeze_row.expires_at > now())
           AND (freeze_row.owner_partner_id IS NULL OR freeze_row.owner_partner_id = bucket_row.owner_partner_id)
           AND (freeze_row.zone_id IS NULL OR freeze_row.zone_id = bucket_row.bucket_zone_id)
           AND (freeze_row.location_id IS NULL OR freeze_row.location_id = bucket_row.location_id)
           AND (freeze_row.item_id IS NULL OR freeze_row.item_id = bucket_row.item_id)
           AND (freeze_row.inventory_lot_id IS NULL OR freeze_row.inventory_lot_id = bucket_row.inventory_lot_id)
           AND (freeze_row.lpn_id IS NULL OR freeze_row.lpn_id = bucket_row.lpn_id)
           AND (operation_code = ANY (freeze_row.blocked_operations) OR 'ALL' = ANY (freeze_row.blocked_operations))
    ) THEN
        RAISE EXCEPTION 'Stock bucket % is covered by an active % freeze', bucket_id, operation_code
            USING ERRCODE = '23514';
    END IF;

    IF bucket_row.customs_legal_status_code IS NULL THEN
        IF bucket_row.bonded_cargo_reference IS NOT NULL
           OR bucket_row.customs_declaration_line_id IS NOT NULL THEN
            RAISE EXCEPTION 'Customs-controlled stock bucket % requires an explicit customs legal status', bucket_id
                USING ERRCODE = '23514';
        END IF;
    ELSE
        SELECT * INTO customs_status_row
          FROM ewms.customs_inventory_legal_statuses
         WHERE legal_status_code = bucket_row.customs_legal_status_code
           AND is_active
           AND effective_from <= current_date
           AND (effective_to IS NULL OR effective_to >= current_date);
        IF customs_status_row.legal_status_code IS NULL
           OR (operation_code = 'PICK' AND NOT customs_status_row.available_for_allocation)
           OR (operation_code = 'SHIPMENT' AND NOT customs_status_row.available_for_shipping) THEN
            RAISE EXCEPTION 'Customs legal status % blocks % for stock bucket %',
                bucket_row.customs_legal_status_code, operation_code, bucket_id
                USING ERRCODE = '23514';
        END IF;
        IF operation_code = 'SHIPMENT' AND bucket_row.customs_legal_status_code = 'FOREIGN' THEN
            RAISE EXCEPTION 'Unreleased FOREIGN inventory cannot be withdrawn from Korea for domestic delivery'
                USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_inventory_reservation_operational_gate ON ewms.inventory_reservations;
CREATE TRIGGER trg_inventory_reservation_operational_gate
    BEFORE INSERT OR UPDATE OF stock_bucket_id, status, reserved_quantity
    ON ewms.inventory_reservations
    FOR EACH ROW EXECUTE PROCEDURE ewms.validate_inventory_operational_gate();

DROP TRIGGER IF EXISTS trg_inventory_allocation_operational_gate ON ewms.inventory_allocations;
CREATE TRIGGER trg_inventory_allocation_operational_gate
    BEFORE INSERT OR UPDATE OF stock_bucket_id, status, allocated_quantity
    ON ewms.inventory_allocations
    FOR EACH ROW EXECUTE PROCEDURE ewms.validate_inventory_operational_gate();

DROP TRIGGER IF EXISTS trg_shipping_allocation_operational_gate ON ewms.shipping_inventory_allocations;
CREATE TRIGGER trg_shipping_allocation_operational_gate
    BEFORE INSERT OR UPDATE OF source_stock_bucket_id, allocated_quantity
    ON ewms.shipping_inventory_allocations
    FOR EACH ROW EXECUTE PROCEDURE ewms.validate_inventory_operational_gate();

CREATE OR REPLACE FUNCTION ewms.validate_inventory_customs_status_transition()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, ewms
AS $function$
DECLARE
    transaction_row record;
    source_entry_row record;
    destination_entry_row record;
    source_bucket_row record;
    destination_bucket_row record;
    coverage_row record;
    evidence_row record;
    already_source numeric(24,8);
    already_destination numeric(24,8);
    already_coverage numeric(24,8);
BEGIN
    -- Lock both ledger-entry quantity limits in UUID order before reading their
    -- totals. The stable order avoids source/destination inversion deadlocks,
    -- while the release-coverage row serializes every consumer of that evidence.
    PERFORM entry.id
      FROM ewms.inventory_transaction_entries entry
     WHERE entry.id IN (NEW.source_inventory_entry_id, NEW.destination_inventory_entry_id)
     ORDER BY entry.id
     FOR UPDATE;
    SELECT * INTO transaction_row FROM ewms.inventory_transaction_headers
     WHERE id = NEW.inventory_transaction_id FOR SHARE;
    SELECT * INTO source_entry_row FROM ewms.inventory_transaction_entries
     WHERE id = NEW.source_inventory_entry_id;
    SELECT * INTO destination_entry_row FROM ewms.inventory_transaction_entries
     WHERE id = NEW.destination_inventory_entry_id;
    SELECT * INTO source_bucket_row FROM ewms.stock_buckets
     WHERE id = NEW.source_stock_bucket_id FOR SHARE;
    SELECT * INTO destination_bucket_row FROM ewms.stock_buckets
     WHERE id = NEW.destination_stock_bucket_id FOR SHARE;
    SELECT * INTO coverage_row FROM ewms.customs_release_line_coverages
     WHERE id = NEW.customs_release_line_coverage_id FOR UPDATE;
    IF transaction_row.id IS NULL OR source_entry_row.id IS NULL OR destination_entry_row.id IS NULL
       OR source_bucket_row.id IS NULL OR destination_bucket_row.id IS NULL OR coverage_row.id IS NULL THEN
        RAISE EXCEPTION 'Customs status transition references an unknown ledger or release object'
            USING ERRCODE = '23503';
    END IF;
    SELECT * INTO evidence_row FROM ewms.customs_release_evidence
     WHERE id = coverage_row.customs_release_evidence_id FOR SHARE;
    IF evidence_row.id IS NULL OR NOT ewms.customs_release_evidence_is_current(evidence_row.id) THEN
        RAISE EXCEPTION 'Customs status transition requires current official UNI-PASS release evidence'
            USING ERRCODE = '23514';
    END IF;
    IF transaction_row.tenant_id <> NEW.tenant_id
       OR source_entry_row.tenant_id <> NEW.tenant_id
       OR destination_entry_row.tenant_id <> NEW.tenant_id
       OR source_bucket_row.tenant_id <> NEW.tenant_id
       OR destination_bucket_row.tenant_id <> NEW.tenant_id
       OR coverage_row.tenant_id <> NEW.tenant_id
       OR evidence_row.tenant_id <> NEW.tenant_id
       OR source_bucket_row.owner_partner_id <> NEW.owner_partner_id
       OR destination_bucket_row.owner_partner_id <> NEW.owner_partner_id
       OR evidence_row.owner_partner_id <> NEW.owner_partner_id
       OR source_entry_row.inventory_transaction_id <> transaction_row.id
       OR destination_entry_row.inventory_transaction_id <> transaction_row.id
       OR source_entry_row.stock_bucket_id <> source_bucket_row.id
       OR destination_entry_row.stock_bucket_id <> destination_bucket_row.id
       OR source_entry_row.signed_quantity >= 0
       OR destination_entry_row.signed_quantity <= 0
       OR transaction_row.transaction_type NOT IN ('STATUS_CHANGE','BONDED_MOVE','TRANSFER','ADJUSTMENT')
       OR source_bucket_row.customs_legal_status_code <> NEW.from_legal_status_code
       OR destination_bucket_row.customs_legal_status_code <> NEW.to_legal_status_code
       OR source_entry_row.base_uom_code <> NEW.base_uom_code
       OR destination_entry_row.base_uom_code <> NEW.base_uom_code
       OR coverage_row.base_uom_code <> NEW.base_uom_code
       OR source_bucket_row.item_id <> destination_bucket_row.item_id
       OR source_bucket_row.item_id <> coverage_row.item_id_snapshot
       OR source_bucket_row.warehouse_id <> destination_bucket_row.warehouse_id
       OR source_bucket_row.inventory_status_id <> destination_bucket_row.inventory_status_id
       OR source_bucket_row.inventory_lot_id IS DISTINCT FROM destination_bucket_row.inventory_lot_id
       OR source_bucket_row.serial_number_id IS DISTINCT FROM destination_bucket_row.serial_number_id
       OR source_bucket_row.lpn_id IS DISTINCT FROM destination_bucket_row.lpn_id
       OR source_bucket_row.country_of_origin IS DISTINCT FROM destination_bucket_row.country_of_origin
       OR source_bucket_row.country_of_origin IS DISTINCT FROM coverage_row.country_of_origin_snapshot THEN
        RAISE EXCEPTION 'Customs status transition ledger, owner, item, stock dimensions, or evidence scope mismatch'
            USING ERRCODE = '23514';
    END IF;
    IF (NEW.transition_purpose = 'IMPORT_RELEASE'
            AND (NEW.to_legal_status_code <> 'DOMESTIC' OR evidence_row.evidence_type <> 'IMPORT_RELEASE'))
       OR (NEW.transition_purpose = 'EXPORT_CLEARANCE'
            AND (NEW.to_legal_status_code <> 'EXPORT' OR evidence_row.evidence_type <> 'EXPORT_CLEARANCE'))
       OR (NEW.transition_purpose = 'TRANSIT_RELEASE'
            AND (NEW.to_legal_status_code <> 'BONDED_TRANSIT' OR evidence_row.evidence_type <> 'TRANSIT_RELEASE'))
       OR (NEW.transition_purpose = 'BONDED_RELEASE' AND evidence_row.evidence_type <> 'BONDED_RELEASE')
       OR (NEW.transition_purpose = 'RETURN_RELEASE' AND evidence_row.evidence_type <> 'RETURN_RELEASE') THEN
        RAISE EXCEPTION 'Customs evidence type does not authorize legal transition % -> %',
            NEW.from_legal_status_code, NEW.to_legal_status_code USING ERRCODE = '23514';
    END IF;
    SELECT COALESCE(sum(transitioned_base_quantity), 0) INTO already_source
      FROM ewms.inventory_customs_status_transitions
     WHERE source_inventory_entry_id = NEW.source_inventory_entry_id;
    SELECT COALESCE(sum(transitioned_base_quantity), 0) INTO already_destination
      FROM ewms.inventory_customs_status_transitions
     WHERE destination_inventory_entry_id = NEW.destination_inventory_entry_id;
    SELECT COALESCE(sum(transitioned_base_quantity), 0) INTO already_coverage
      FROM ewms.inventory_customs_status_transitions
     WHERE customs_release_line_coverage_id = NEW.customs_release_line_coverage_id;
    IF already_source + NEW.transitioned_base_quantity > abs(source_entry_row.signed_quantity)
       OR already_destination + NEW.transitioned_base_quantity > destination_entry_row.signed_quantity
       OR already_coverage + NEW.transitioned_base_quantity > coverage_row.covered_base_quantity THEN
        RAISE EXCEPTION 'Customs status transition quantity exceeds a ledger entry or release coverage'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION ewms.assert_inventory_customs_transaction()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, ewms
AS $function$
DECLARE
    source_row record;
    transitioned numeric(24,8);
BEGIN
    IF NEW.posting_status <> 'POSTED' THEN RETURN NULL; END IF;
    FOR source_row IN
        SELECT entry.id AS entry_id, entry.signed_quantity, bucket.item_id,
               bucket.owner_partner_id, bucket.customs_legal_status_code,
               status.available_for_allocation, status.available_for_shipping,
               status.blocks_internal_movement
          FROM ewms.inventory_transaction_entries entry
          JOIN ewms.stock_buckets bucket ON bucket.id = entry.stock_bucket_id
          JOIN ewms.inventory_statuses status ON status.id = bucket.inventory_status_id
         WHERE entry.inventory_transaction_id = NEW.id
           AND entry.signed_quantity < 0
    LOOP
        IF source_row.blocks_internal_movement
           AND NEW.transaction_type IN (
               'PUTAWAY','MOVE','TRANSFER','REPLENISHMENT','OWNER_TRANSFER',
               'BONDED_MOVE','TRANSFORMATION','REPACK','RELABEL'
           ) THEN
            RAISE EXCEPTION 'Inventory status blocks % movement for entry %',
                NEW.transaction_type, source_row.entry_id USING ERRCODE = '23514';
        END IF;
        IF NEW.transaction_type IN ('PICK','PACK')
           AND NOT source_row.available_for_allocation THEN
            RAISE EXCEPTION 'Inventory status is not eligible for % posting for entry %',
                NEW.transaction_type, source_row.entry_id USING ERRCODE = '23514';
        END IF;
        IF NEW.transaction_type = 'SHIPMENT'
           AND NOT source_row.available_for_shipping THEN
            RAISE EXCEPTION 'Inventory status is not eligible for shipment posting for entry %',
                source_row.entry_id USING ERRCODE = '23514';
        END IF;
        IF source_row.customs_legal_status_code = 'FOREIGN'
           AND NEW.transaction_type = 'SHIPMENT' THEN
            RAISE EXCEPTION 'Unreleased FOREIGN inventory cannot be posted to a shipment transaction'
                USING ERRCODE = '23514';
        END IF;
        IF EXISTS (
            SELECT 1
              FROM ewms.inventory_transaction_entries destination_entry
              JOIN ewms.stock_buckets destination_bucket
                ON destination_bucket.id = destination_entry.stock_bucket_id
             WHERE destination_entry.inventory_transaction_id = NEW.id
               AND destination_entry.signed_quantity > 0
               AND destination_bucket.owner_partner_id = source_row.owner_partner_id
               AND destination_bucket.item_id = source_row.item_id
               AND destination_bucket.customs_legal_status_code
                   IS DISTINCT FROM source_row.customs_legal_status_code
        ) THEN
            SELECT COALESCE(sum(transitioned_base_quantity), 0) INTO transitioned
              FROM ewms.inventory_customs_status_transitions
             WHERE inventory_transaction_id = NEW.id
               AND source_inventory_entry_id = source_row.entry_id;
            IF transitioned <> abs(source_row.signed_quantity) THEN
                RAISE EXCEPTION 'Customs legal-status change for entry % lacks exact official evidence coverage',
                    source_row.entry_id USING ERRCODE = '23514';
            END IF;
        END IF;
    END LOOP;
    RETURN NULL;
END;
$function$;

DROP TRIGGER IF EXISTS trg_assert_inventory_customs_transaction
    ON ewms.inventory_transaction_headers;
CREATE CONSTRAINT TRIGGER trg_assert_inventory_customs_transaction
    AFTER INSERT OR UPDATE ON ewms.inventory_transaction_headers
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE PROCEDURE ewms.assert_inventory_customs_transaction();

CREATE OR REPLACE FUNCTION ewms.validate_slotting_recommendation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, ewms
AS $function$
DECLARE
    run_row record;
    source_location_tenant uuid;
    source_location_warehouse uuid;
    target_location_tenant uuid;
    target_location_warehouse uuid;
    bucket_row record;
    task_row record;
    item_base_uom varchar(20);
BEGIN
    SELECT * INTO run_row FROM ewms.slotting_runs
     WHERE id = NEW.slotting_run_id FOR SHARE;
    IF run_row.id IS NULL OR run_row.tenant_id <> NEW.tenant_id
       OR run_row.status NOT IN ('RUNNING','COMPLETED') THEN
        RAISE EXCEPTION 'Slotting recommendation requires a RUNNING or COMPLETED tenant-scoped run'
            USING ERRCODE = '23514';
    END IF;
    SELECT base_uom_code INTO item_base_uom FROM ewms.items
     WHERE id = NEW.item_id AND tenant_id = NEW.tenant_id;
    SELECT tenant_id, warehouse_id INTO target_location_tenant, target_location_warehouse
      FROM ewms.warehouse_locations WHERE id = NEW.target_location_id AND deleted_at IS NULL;
    IF NEW.from_location_id IS NOT NULL THEN
        SELECT tenant_id, warehouse_id INTO source_location_tenant, source_location_warehouse
          FROM ewms.warehouse_locations WHERE id = NEW.from_location_id AND deleted_at IS NULL;
    ELSE
        source_location_tenant := NEW.tenant_id;
        source_location_warehouse := run_row.warehouse_id;
    END IF;
    IF item_base_uom IS NULL OR item_base_uom <> NEW.base_uom_code
       OR target_location_tenant <> NEW.tenant_id
       OR source_location_tenant <> NEW.tenant_id
       OR target_location_warehouse <> run_row.warehouse_id
       OR source_location_warehouse <> run_row.warehouse_id
       OR (run_row.owner_partner_id IS NOT NULL AND run_row.owner_partner_id <> NEW.owner_partner_id) THEN
        RAISE EXCEPTION 'Slotting recommendation crosses item, owner, tenant, warehouse, or base-unit scope'
            USING ERRCODE = '23514';
    END IF;
    IF NEW.source_stock_bucket_id IS NOT NULL THEN
        SELECT * INTO bucket_row FROM ewms.stock_buckets WHERE id = NEW.source_stock_bucket_id;
        IF bucket_row.id IS NULL OR bucket_row.tenant_id <> NEW.tenant_id
           OR bucket_row.warehouse_id <> run_row.warehouse_id
           OR bucket_row.owner_partner_id <> NEW.owner_partner_id
           OR bucket_row.item_id <> NEW.item_id
           OR bucket_row.location_id IS DISTINCT FROM NEW.from_location_id THEN
            RAISE EXCEPTION 'Slotting source bucket does not match recommendation dimensions'
                USING ERRCODE = '23514';
        END IF;
    END IF;
    IF NEW.executed_movement_task_id IS NOT NULL THEN
        SELECT * INTO task_row FROM ewms.movement_tasks WHERE id = NEW.executed_movement_task_id;
        IF task_row.id IS NULL OR task_row.tenant_id <> NEW.tenant_id
           OR task_row.warehouse_id <> run_row.warehouse_id
           OR task_row.owner_partner_id <> NEW.owner_partner_id
           OR task_row.item_id <> NEW.item_id
           OR task_row.destination_location_id <> NEW.target_location_id THEN
            RAISE EXCEPTION 'Applied slotting movement task does not implement the recommendation'
                USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

COMMENT ON COLUMN ewms.inventory_statuses.requires_inventory_freeze IS
    'True when stock in this status must be covered by an ACTIVE inventory_freeze and cannot be allocated or shipped.';
COMMENT ON COLUMN ewms.inventory_statuses.blocks_internal_movement IS
    'True when the status blocks MOVE/TRANSFER/PUTAWAY/REPLENISHMENT operations in addition to allocation and shipment.';

CREATE TABLE IF NOT EXISTS ewms.customs_inventory_legal_statuses (
    legal_status_code varchar(50) PRIMARY KEY,
    status_name_ko varchar(200) NOT NULL,
    status_name_en varchar(200),
    legal_category varchar(30) NOT NULL,
    available_for_allocation boolean NOT NULL DEFAULT false,
    available_for_shipping boolean NOT NULL DEFAULT false,
    domestic_withdrawal_allowed boolean NOT NULL DEFAULT false,
    requires_release_evidence boolean NOT NULL DEFAULT true,
    requires_bonded_control boolean NOT NULL DEFAULT false,
    is_terminal boolean NOT NULL DEFAULT false,
    is_active boolean NOT NULL DEFAULT true,
    effective_from date NOT NULL DEFAULT DATE '2000-01-01',
    effective_to date,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_ewms_customs_inventory_legal_category CHECK (legal_category IN (
        'DOMESTIC','FOREIGN','EXPORT','CONDITIONAL','TRANSIT','ENFORCEMENT','DISPOSAL'
    )),
    CONSTRAINT ck_ewms_customs_inventory_legal_dates CHECK (
        effective_to IS NULL OR effective_to >= effective_from
    ),
    CONSTRAINT ck_ewms_customs_inventory_legal_gate CHECK (
        NOT (domestic_withdrawal_allowed AND requires_release_evidence)
        AND NOT (available_for_shipping AND is_terminal)
    )
);

INSERT INTO ewms.customs_inventory_legal_statuses (
    legal_status_code, status_name_ko, status_name_en, legal_category,
    available_for_allocation, available_for_shipping,
    domestic_withdrawal_allowed, requires_release_evidence,
    requires_bonded_control, is_terminal
) VALUES
    ('DOMESTIC','내국화물','Domestic goods','DOMESTIC',true,true,true,false,false,false),
    ('FOREIGN','외국화물(미수리)','Foreign goods - not import released','FOREIGN',false,false,false,true,true,false),
    ('EXPORT','수출신고 수리화물','Export-cleared goods','EXPORT',true,true,false,true,true,false),
    ('CONDITIONAL_RELEASE','조건부 반출화물','Conditionally released goods','CONDITIONAL',false,false,false,true,true,false),
    ('BONDED_TRANSIT','보세운송 화물','Goods under bonded transit','TRANSIT',false,true,false,true,true,false),
    ('SEIZED','압수·유치 화물','Seized or detained goods','ENFORCEMENT',false,false,false,true,true,false),
    ('ABANDONED','몰수·국고귀속 대기 화물','Abandoned goods','ENFORCEMENT',false,false,false,true,true,false),
    ('DISPOSAL_PENDING','폐기 대기 화물','Goods pending disposal','DISPOSAL',false,false,false,true,true,false),
    ('DISPOSED','폐기 완료 화물','Disposed goods','DISPOSAL',false,false,false,false,false,true)
ON CONFLICT (legal_status_code) DO NOTHING;

DO $block$
BEGIN
    IF NOT EXISTS (
        SELECT 1
          FROM pg_constraint
         WHERE conrelid = 'ewms.stock_buckets'::regclass
           AND conname = 'fk_ewms_stock_bucket_customs_legal_status'
    ) THEN
        ALTER TABLE ewms.stock_buckets
            ADD CONSTRAINT fk_ewms_stock_bucket_customs_legal_status
            FOREIGN KEY (customs_legal_status_code)
            REFERENCES ewms.customs_inventory_legal_statuses(legal_status_code)
            ON DELETE RESTRICT;
    END IF;
END;
$block$;

CREATE INDEX IF NOT EXISTS ix_ewms_stock_bucket_customs_legal_status
    ON ewms.stock_buckets (customs_legal_status_code);

COMMENT ON TABLE ewms.customs_inventory_legal_statuses IS
    'Canonical customs-law state independent from physical inventory status. FOREIGN means import declaration not yet released and is never a domestic-withdrawal state.';

-- Official mapping versions are global authority configuration, like the existing
-- customs_message_schemas and customs_code_sets. Tenant overrides are deliberately
-- prohibited so a filing cannot silently use a customer-specific interpretation.
CREATE TABLE IF NOT EXISTS ewms.unipass_mapping_versions (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    message_schema_id uuid NOT NULL REFERENCES ewms.customs_message_schemas(id) ON DELETE RESTRICT,
    mapping_version varchar(100) NOT NULL,
    declaration_kind varchar(30) NOT NULL,
    direction varchar(10) NOT NULL,
    authority_publication_no varchar(150),
    source_uri text NOT NULL,
    source_sha256 char(64) NOT NULL,
    mapping_object_uri text NOT NULL,
    mapping_sha256 char(64) NOT NULL,
    effective_from date NOT NULL,
    effective_to date,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    verified_at timestamptz,
    activated_at timestamptz,
    retired_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (message_schema_id, mapping_version),
    CONSTRAINT ck_ewms_unipass_mapping_kind CHECK (declaration_kind IN (
        'IMPORT','EXPORT','RETURN_EXPORT','RETURN_IMPORT','TRANSIT','BONDED','COMMON','OTHER'
    )),
    CONSTRAINT ck_ewms_unipass_mapping_direction CHECK (direction IN ('IN','OUT')),
    CONSTRAINT ck_ewms_unipass_mapping_status CHECK (status IN (
        'DRAFT','VERIFIED','ACTIVE','RETIRED'
    )),
    CONSTRAINT ck_ewms_unipass_mapping_hashes CHECK (
        source_sha256 ~ '^[0-9A-Fa-f]{64}$'
        AND mapping_sha256 ~ '^[0-9A-Fa-f]{64}$'
    ),
    CONSTRAINT ck_ewms_unipass_mapping_dates CHECK (
        (effective_to IS NULL OR effective_to >= effective_from)
        AND (activated_at IS NULL OR verified_at IS NOT NULL)
        AND (retired_at IS NULL OR activated_at IS NOT NULL)
    ),
    CONSTRAINT ck_ewms_unipass_mapping_lifecycle CHECK (
        (status = 'DRAFT' AND verified_at IS NULL AND activated_at IS NULL AND retired_at IS NULL) OR
        (status = 'VERIFIED' AND verified_at IS NOT NULL AND activated_at IS NULL AND retired_at IS NULL) OR
        (status = 'ACTIVE' AND verified_at IS NOT NULL AND activated_at IS NOT NULL AND retired_at IS NULL) OR
        (status = 'RETIRED' AND verified_at IS NOT NULL AND activated_at IS NOT NULL AND retired_at IS NOT NULL)
    )
);

CREATE TABLE IF NOT EXISTS ewms.unipass_code_mapping_versions (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    unipass_mapping_version_id uuid NOT NULL REFERENCES ewms.unipass_mapping_versions(id) ON DELETE RESTRICT,
    customs_code_set_id uuid NOT NULL REFERENCES ewms.customs_code_sets(id) ON DELETE RESTRICT,
    code_domain varchar(120) NOT NULL,
    code_mapping_version varchar(100) NOT NULL,
    source_uri text NOT NULL,
    source_sha256 char(64) NOT NULL,
    effective_from date NOT NULL,
    effective_to date,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    verified_at timestamptz,
    activated_at timestamptz,
    retired_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (unipass_mapping_version_id, code_domain, code_mapping_version),
    CONSTRAINT ck_ewms_unipass_code_mapping_hash CHECK (
        source_sha256 ~ '^[0-9A-Fa-f]{64}$'
    ),
    CONSTRAINT ck_ewms_unipass_code_mapping_status CHECK (status IN (
        'DRAFT','VERIFIED','ACTIVE','RETIRED'
    )),
    CONSTRAINT ck_ewms_unipass_code_mapping_dates CHECK (
        effective_to IS NULL OR effective_to >= effective_from
    ),
    CONSTRAINT ck_ewms_unipass_code_mapping_lifecycle CHECK (
        (status = 'DRAFT' AND verified_at IS NULL AND activated_at IS NULL AND retired_at IS NULL) OR
        (status = 'VERIFIED' AND verified_at IS NOT NULL AND activated_at IS NULL AND retired_at IS NULL) OR
        (status = 'ACTIVE' AND verified_at IS NOT NULL AND activated_at IS NOT NULL AND retired_at IS NULL) OR
        (status = 'RETIRED' AND verified_at IS NOT NULL AND activated_at IS NOT NULL AND retired_at IS NOT NULL)
    )
);

CREATE TABLE IF NOT EXISTS ewms.unipass_code_mappings (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    code_mapping_version_id uuid NOT NULL REFERENCES ewms.unipass_code_mapping_versions(id) ON DELETE RESTRICT,
    mapping_sequence integer NOT NULL,
    internal_domain varchar(120) NOT NULL,
    internal_code_value varchar(200) NOT NULL,
    official_customs_code_id uuid NOT NULL REFERENCES ewms.customs_codes(id) ON DELETE RESTRICT,
    mapping_direction varchar(20) NOT NULL DEFAULT 'BIDIRECTIONAL',
    is_default boolean NOT NULL DEFAULT false,
    condition_key varchar(120),
    condition_value varchar(300),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (code_mapping_version_id, mapping_sequence),
    UNIQUE (code_mapping_version_id, internal_domain, internal_code_value, condition_key, condition_value),
    CONSTRAINT ck_ewms_unipass_code_mapping_sequence CHECK (mapping_sequence > 0),
    CONSTRAINT ck_ewms_unipass_code_mapping_direction CHECK (
        mapping_direction IN ('INBOUND','OUTBOUND','BIDIRECTIONAL')
    )
);

CREATE TABLE IF NOT EXISTS ewms.unipass_field_mappings (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    unipass_mapping_version_id uuid NOT NULL REFERENCES ewms.unipass_mapping_versions(id) ON DELETE RESTRICT,
    field_sequence integer NOT NULL,
    internal_entity varchar(150) NOT NULL,
    internal_field_path varchar(500) NOT NULL,
    official_field_path varchar(500) NOT NULL,
    official_field_id varchar(200),
    field_name_ko varchar(300),
    data_type varchar(30) NOT NULL,
    minimum_occurs integer NOT NULL DEFAULT 0,
    maximum_occurs integer,
    maximum_length integer,
    decimal_scale integer,
    format_mask varchar(150),
    transform_code varchar(120),
    code_mapping_version_id uuid REFERENCES ewms.unipass_code_mapping_versions(id) ON DELETE RESTRICT,
    is_sensitive boolean NOT NULL DEFAULT false,
    is_declaration_key boolean NOT NULL DEFAULT false,
    validation_rule_code varchar(120),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (unipass_mapping_version_id, field_sequence),
    UNIQUE (unipass_mapping_version_id, official_field_path),
    CONSTRAINT ck_ewms_unipass_field_mapping_sequence CHECK (field_sequence > 0),
    CONSTRAINT ck_ewms_unipass_field_mapping_type CHECK (data_type IN (
        'TEXT','INTEGER','DECIMAL','BOOLEAN','DATE','TIMESTAMP','CODE','IDENTIFIER','BINARY','GROUP'
    )),
    CONSTRAINT ck_ewms_unipass_field_mapping_occurs CHECK (
        minimum_occurs >= 0
        AND (maximum_occurs IS NULL OR maximum_occurs >= minimum_occurs)
        AND (maximum_length IS NULL OR maximum_length > 0)
        AND (decimal_scale IS NULL OR decimal_scale >= 0)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_ewms_unipass_active_mapping
    ON ewms.unipass_mapping_versions (message_schema_id, declaration_kind, direction)
    WHERE status = 'ACTIVE';
CREATE UNIQUE INDEX IF NOT EXISTS ux_ewms_unipass_active_code_mapping
    ON ewms.unipass_code_mapping_versions (unipass_mapping_version_id, code_domain)
    WHERE status = 'ACTIVE';
CREATE INDEX IF NOT EXISTS ix_ewms_unipass_field_internal
    ON ewms.unipass_field_mappings (
        unipass_mapping_version_id, internal_entity, internal_field_path
    );
CREATE INDEX IF NOT EXISTS ix_ewms_unipass_code_official
    ON ewms.unipass_code_mappings (official_customs_code_id, code_mapping_version_id);

-- Customer-return status and quantity lineage. Existing 05 tables contain the RMA
-- header/lines; these allocations make every received unit traceable through receipt,
-- inspection, disposition, and the immutable inventory ledger.
CREATE TABLE IF NOT EXISTS ewms.customer_return_status_history (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    customer_return_order_id uuid NOT NULL REFERENCES ewms.customer_return_orders(id) ON DELETE RESTRICT,
    event_sequence integer NOT NULL,
    from_status varchar(30),
    to_status varchar(30) NOT NULL,
    reason_code_id uuid REFERENCES ewms.reason_codes(id),
    reason_text text,
    actor_user_id uuid REFERENCES ewms.users(id) ON DELETE SET NULL,
    source_system_id uuid REFERENCES ewms.external_systems(id) ON DELETE RESTRICT,
    correlation_id varchar(100),
    occurred_at timestamptz NOT NULL DEFAULT now(),
    recorded_at timestamptz NOT NULL DEFAULT now(),
    metadata_masked jsonb NOT NULL DEFAULT '{}'::jsonb,
    UNIQUE (customer_return_order_id, event_sequence),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_customer_return_history_sequence CHECK (event_sequence > 0),
    CONSTRAINT ck_ewms_customer_return_history_status CHECK (to_status IN (
        'REQUESTED','AUTHORIZED','IN_TRANSIT','RECEIVING','RECEIVED','INSPECTING',
        'DISPOSITIONED','CLOSED','REJECTED','CANCELLED'
    )),
    CONSTRAINT ck_ewms_customer_return_history_masked CHECK (
        NOT ewms.jsonb_contains_forbidden_secret_key(metadata_masked)
    )
);

CREATE TABLE IF NOT EXISTS ewms.customer_return_receipt_allocations (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    customer_return_order_id uuid NOT NULL REFERENCES ewms.customer_return_orders(id) ON DELETE RESTRICT,
    customer_return_line_id uuid NOT NULL REFERENCES ewms.customer_return_lines(id) ON DELETE RESTRICT,
    receipt_id uuid NOT NULL REFERENCES ewms.receipts(id) ON DELETE RESTRICT,
    receipt_line_id uuid NOT NULL REFERENCES ewms.receipt_lines(id) ON DELETE RESTRICT,
    allocated_quantity numeric(24,8) NOT NULL,
    uom_code varchar(20) NOT NULL REFERENCES ewms.units_of_measure(uom_code),
    allocated_base_quantity numeric(24,8) NOT NULL,
    base_uom_code varchar(20) NOT NULL REFERENCES ewms.units_of_measure(uom_code),
    created_by uuid REFERENCES ewms.users(id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (customer_return_line_id, receipt_line_id),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_return_receipt_allocation_qty CHECK (
        allocated_quantity > 0 AND allocated_base_quantity > 0
    )
);

CREATE TABLE IF NOT EXISTS ewms.customer_return_quality_allocations (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    customer_return_receipt_allocation_id uuid NOT NULL,
    quality_inspection_id uuid NOT NULL REFERENCES ewms.quality_inspections(id) ON DELETE RESTRICT,
    allocated_quantity numeric(24,8) NOT NULL,
    uom_code varchar(20) NOT NULL REFERENCES ewms.units_of_measure(uom_code),
    created_by uuid REFERENCES ewms.users(id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (customer_return_receipt_allocation_id, quality_inspection_id),
    UNIQUE (tenant_id, id),
    FOREIGN KEY (tenant_id, customer_return_receipt_allocation_id)
        REFERENCES ewms.customer_return_receipt_allocations(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_ewms_return_quality_allocation_qty CHECK (allocated_quantity > 0)
);

CREATE TABLE IF NOT EXISTS ewms.customer_return_disposition_allocations (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    customer_return_receipt_allocation_id uuid NOT NULL,
    customer_return_quality_allocation_id uuid,
    quality_disposition_id uuid NOT NULL REFERENCES ewms.quality_dispositions(id) ON DELETE RESTRICT,
    allocated_quantity numeric(24,8) NOT NULL,
    uom_code varchar(20) NOT NULL REFERENCES ewms.units_of_measure(uom_code),
    created_by uuid REFERENCES ewms.users(id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (customer_return_receipt_allocation_id, quality_disposition_id),
    UNIQUE (tenant_id, id),
    FOREIGN KEY (tenant_id, customer_return_receipt_allocation_id)
        REFERENCES ewms.customer_return_receipt_allocations(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, customer_return_quality_allocation_id)
        REFERENCES ewms.customer_return_quality_allocations(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_ewms_return_disposition_allocation_qty CHECK (allocated_quantity > 0)
);

CREATE TABLE IF NOT EXISTS ewms.customer_return_inventory_allocations (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    customer_return_receipt_allocation_id uuid NOT NULL,
    customer_return_disposition_allocation_id uuid,
    receipt_inventory_allocation_id uuid NOT NULL REFERENCES ewms.receipt_inventory_allocations(id) ON DELETE RESTRICT,
    inventory_transaction_id uuid NOT NULL REFERENCES ewms.inventory_transaction_headers(id) ON DELETE RESTRICT,
    inventory_transaction_entry_id uuid NOT NULL REFERENCES ewms.inventory_transaction_entries(id) ON DELETE RESTRICT,
    destination_stock_bucket_id uuid NOT NULL REFERENCES ewms.stock_buckets(id) ON DELETE RESTRICT,
    posted_base_quantity numeric(24,8) NOT NULL,
    base_uom_code varchar(20) NOT NULL REFERENCES ewms.units_of_measure(uom_code),
    created_by uuid REFERENCES ewms.users(id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (customer_return_receipt_allocation_id, receipt_inventory_allocation_id),
    UNIQUE (tenant_id, id),
    FOREIGN KEY (tenant_id, customer_return_receipt_allocation_id)
        REFERENCES ewms.customer_return_receipt_allocations(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, customer_return_disposition_allocation_id)
        REFERENCES ewms.customer_return_disposition_allocations(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_ewms_return_inventory_allocation_qty CHECK (posted_base_quantity > 0)
);

CREATE INDEX IF NOT EXISTS ix_ewms_return_status_timeline
    ON ewms.customer_return_status_history (
        tenant_id, customer_return_order_id, occurred_at, event_sequence
    );
CREATE INDEX IF NOT EXISTS ix_ewms_return_receipt_trace
    ON ewms.customer_return_receipt_allocations (
        tenant_id, receipt_id, receipt_line_id, customer_return_line_id
    );
CREATE INDEX IF NOT EXISTS ix_ewms_return_quality_trace
    ON ewms.customer_return_quality_allocations (
        tenant_id, quality_inspection_id, customer_return_receipt_allocation_id
    );
CREATE INDEX IF NOT EXISTS ix_ewms_return_disposition_trace
    ON ewms.customer_return_disposition_allocations (
        tenant_id, quality_disposition_id, customer_return_receipt_allocation_id
    );
CREATE INDEX IF NOT EXISTS ix_ewms_return_inventory_trace
    ON ewms.customer_return_inventory_allocations (
        tenant_id, inventory_transaction_id, inventory_transaction_entry_id,
        destination_stock_bucket_id
    );
CREATE UNIQUE INDEX IF NOT EXISTS ux_ewms_return_inventory_source_once
    ON ewms.customer_return_inventory_allocations (receipt_inventory_allocation_id);

-- End-to-end product recall control.
CREATE TABLE IF NOT EXISTS ewms.recall_campaigns (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    owner_partner_id uuid NOT NULL REFERENCES ewms.business_partners(id),
    warehouse_id uuid REFERENCES ewms.warehouses(id),
    campaign_no varchar(120) NOT NULL,
    campaign_name varchar(300) NOT NULL,
    recall_class varchar(20) NOT NULL,
    recall_scope varchar(30) NOT NULL,
    authority_code varchar(80),
    authority_reference_no varchar(200),
    initiated_at timestamptz NOT NULL,
    effective_at timestamptz NOT NULL,
    response_due_at timestamptz,
    closed_at timestamptz,
    reason_code_id uuid REFERENCES ewms.reason_codes(id),
    reason_text text NOT NULL,
    public_notice_uri text,
    public_notice_sha256 char(64),
    status varchar(30) NOT NULL DEFAULT 'DRAFT',
    created_by uuid REFERENCES ewms.users(id) ON DELETE SET NULL,
    updated_by uuid REFERENCES ewms.users(id) ON DELETE SET NULL,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, campaign_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_recall_class CHECK (recall_class IN (
        'CLASS_I','CLASS_II','CLASS_III','MARKET_WITHDRAWAL','SAFETY_ALERT','INTERNAL'
    )),
    CONSTRAINT ck_ewms_recall_scope CHECK (recall_scope IN (
        'LOT','SERIAL','ITEM','DATE_RANGE','SHIPMENT','CUSTOMER','MIXED'
    )),
    CONSTRAINT ck_ewms_recall_status CHECK (status IN (
        'DRAFT','APPROVED','ACTIVE','CONTAINMENT','RECOVERY','EFFECTIVENESS_CHECK',
        'CLOSED','CANCELLED'
    )),
    CONSTRAINT ck_ewms_recall_dates CHECK (
        effective_at >= initiated_at
        AND (response_due_at IS NULL OR response_due_at >= initiated_at)
        AND (closed_at IS NULL OR closed_at >= initiated_at)
    ),
    CONSTRAINT ck_ewms_recall_evidence_hash CHECK (
        public_notice_sha256 IS NULL OR public_notice_sha256 ~ '^[0-9A-Fa-f]{64}$'
    ),
    CONSTRAINT ck_ewms_recall_evidence_pair CHECK (
        (public_notice_uri IS NULL AND public_notice_sha256 IS NULL) OR
        (public_notice_uri IS NOT NULL AND public_notice_sha256 IS NOT NULL)
    ),
    CONSTRAINT ck_ewms_recall_close CHECK (
        (status = 'CLOSED' AND closed_at IS NOT NULL) OR status <> 'CLOSED'
    )
);

CREATE TABLE IF NOT EXISTS ewms.recall_campaign_status_history (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    recall_campaign_id uuid NOT NULL,
    event_sequence integer NOT NULL,
    from_status varchar(30),
    to_status varchar(30) NOT NULL,
    reason_code_id uuid REFERENCES ewms.reason_codes(id),
    reason_text text,
    actor_user_id uuid REFERENCES ewms.users(id) ON DELETE SET NULL,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    recorded_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (recall_campaign_id, event_sequence),
    UNIQUE (tenant_id, id),
    FOREIGN KEY (tenant_id, recall_campaign_id)
        REFERENCES ewms.recall_campaigns(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_ewms_recall_history_sequence CHECK (event_sequence > 0),
    CONSTRAINT ck_ewms_recall_history_status CHECK (
        (from_status IS NULL OR from_status IN (
            'DRAFT','APPROVED','ACTIVE','CONTAINMENT','RECOVERY',
            'EFFECTIVENESS_CHECK','CLOSED','CANCELLED'
        ))
        AND to_status IN (
            'DRAFT','APPROVED','ACTIVE','CONTAINMENT','RECOVERY',
            'EFFECTIVENESS_CHECK','CLOSED','CANCELLED'
        )
    )
);

CREATE TABLE IF NOT EXISTS ewms.recall_campaign_lots (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    recall_campaign_id uuid NOT NULL,
    item_id uuid NOT NULL REFERENCES ewms.items(id) ON DELETE RESTRICT,
    inventory_lot_id uuid NOT NULL REFERENCES ewms.inventory_lots(id) ON DELETE RESTRICT,
    affected_base_quantity numeric(24,8),
    base_uom_code varchar(20) NOT NULL REFERENCES ewms.units_of_measure(uom_code),
    on_hand_base_quantity_snapshot numeric(24,8) NOT NULL DEFAULT 0,
    shipped_base_quantity_snapshot numeric(24,8) NOT NULL DEFAULT 0,
    recovered_base_quantity numeric(24,8) NOT NULL DEFAULT 0,
    destroyed_base_quantity numeric(24,8) NOT NULL DEFAULT 0,
    inventory_hold_id uuid REFERENCES ewms.inventory_holds(id) ON DELETE RESTRICT,
    trace_status varchar(30) NOT NULL DEFAULT 'IDENTIFIED',
    traced_at timestamptz,
    created_by uuid REFERENCES ewms.users(id) ON DELETE SET NULL,
    updated_by uuid REFERENCES ewms.users(id) ON DELETE SET NULL,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (recall_campaign_id, inventory_lot_id),
    UNIQUE (tenant_id, id),
    FOREIGN KEY (tenant_id, recall_campaign_id)
        REFERENCES ewms.recall_campaigns(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_ewms_recall_lot_quantities CHECK (
        (affected_base_quantity IS NULL OR affected_base_quantity > 0)
        AND on_hand_base_quantity_snapshot >= 0
        AND shipped_base_quantity_snapshot >= 0
        AND recovered_base_quantity >= 0
        AND destroyed_base_quantity >= 0
        AND (affected_base_quantity IS NULL OR recovered_base_quantity <= affected_base_quantity)
        AND destroyed_base_quantity <= recovered_base_quantity
    ),
    CONSTRAINT ck_ewms_recall_lot_status CHECK (trace_status IN (
        'IDENTIFIED','TRACING','HELD','PARTIALLY_RECOVERED','RECOVERED','DESTROYED','RELEASED','EXCLUDED'
    ))
);

CREATE TABLE IF NOT EXISTS ewms.recall_actions (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    recall_campaign_id uuid NOT NULL,
    recall_campaign_lot_id uuid,
    action_no integer NOT NULL,
    action_type varchar(40) NOT NULL,
    target_type varchar(40) NOT NULL,
    stock_bucket_id uuid REFERENCES ewms.stock_buckets(id) ON DELETE RESTRICT,
    shipment_id uuid REFERENCES ewms.shipments(id) ON DELETE RESTRICT,
    receipt_id uuid REFERENCES ewms.receipts(id) ON DELETE RESTRICT,
    customer_return_order_id uuid REFERENCES ewms.customer_return_orders(id) ON DELETE RESTRICT,
    partner_id uuid REFERENCES ewms.business_partners(id) ON DELETE RESTRICT,
    inventory_hold_id uuid REFERENCES ewms.inventory_holds(id) ON DELETE RESTRICT,
    assigned_user_id uuid REFERENCES ewms.users(id) ON DELETE SET NULL,
    due_at timestamptz,
    started_at timestamptz,
    completed_at timestamptz,
    status varchar(20) NOT NULL DEFAULT 'OPEN',
    result_code varchar(80),
    result_note text,
    evidence_uri text,
    evidence_sha256 char(64),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (recall_campaign_id, action_no),
    UNIQUE (tenant_id, id),
    FOREIGN KEY (tenant_id, recall_campaign_id)
        REFERENCES ewms.recall_campaigns(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, recall_campaign_lot_id)
        REFERENCES ewms.recall_campaign_lots(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_ewms_recall_action_no CHECK (action_no > 0),
    CONSTRAINT ck_ewms_recall_action_type CHECK (action_type IN (
        'TRACE','PLACE_HOLD','STOP_SHIP','NOTIFY_AUTHORITY','NOTIFY_CUSTOMER','RETRIEVE',
        'RECEIVE_RETURN','INSPECT','REWORK','DESTROY','RELEASE','EFFECTIVENESS_CHECK','OTHER'
    )),
    CONSTRAINT ck_ewms_recall_action_target CHECK (target_type IN (
        'CAMPAIGN','LOT','STOCK_BUCKET','SHIPMENT','RECEIPT','CUSTOMER_RETURN','PARTNER','AUTHORITY'
    )),
    CONSTRAINT ck_ewms_recall_action_target_value CHECK (
        (target_type = 'CAMPAIGN' AND num_nonnulls(
            recall_campaign_lot_id,stock_bucket_id,shipment_id,receipt_id,
            customer_return_order_id,partner_id
        ) = 0) OR
        (target_type = 'LOT' AND recall_campaign_lot_id IS NOT NULL) OR
        (target_type = 'STOCK_BUCKET' AND stock_bucket_id IS NOT NULL) OR
        (target_type = 'SHIPMENT' AND shipment_id IS NOT NULL) OR
        (target_type = 'RECEIPT' AND receipt_id IS NOT NULL) OR
        (target_type = 'CUSTOMER_RETURN' AND customer_return_order_id IS NOT NULL) OR
        (target_type = 'PARTNER' AND partner_id IS NOT NULL) OR
        target_type = 'AUTHORITY'
    ),
    CONSTRAINT ck_ewms_recall_action_status CHECK (status IN (
        'OPEN','ASSIGNED','IN_PROGRESS','BLOCKED','COMPLETED','FAILED','CANCELLED'
    )),
    CONSTRAINT ck_ewms_recall_action_dates CHECK (
        (started_at IS NULL OR due_at IS NULL OR started_at <= due_at + interval '365 days')
        AND (completed_at IS NULL OR started_at IS NULL OR completed_at >= started_at)
    ),
    CONSTRAINT ck_ewms_recall_action_completion CHECK (
        (status IN ('COMPLETED','FAILED') AND completed_at IS NOT NULL) OR
        status NOT IN ('COMPLETED','FAILED')
    ),
    CONSTRAINT ck_ewms_recall_action_evidence CHECK (
        (evidence_uri IS NULL AND evidence_sha256 IS NULL) OR
        (evidence_uri IS NOT NULL AND evidence_sha256 ~ '^[0-9A-Fa-f]{64}$')
    )
);

CREATE TABLE IF NOT EXISTS ewms.recall_action_events (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    recall_action_id uuid NOT NULL,
    event_sequence integer NOT NULL,
    event_type varchar(80) NOT NULL,
    from_status varchar(20),
    to_status varchar(20),
    quantity_delta numeric(24,8),
    base_uom_code varchar(20) REFERENCES ewms.units_of_measure(uom_code),
    actor_user_id uuid REFERENCES ewms.users(id) ON DELETE SET NULL,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    recorded_at timestamptz NOT NULL DEFAULT now(),
    detail_masked jsonb NOT NULL DEFAULT '{}'::jsonb,
    UNIQUE (recall_action_id, event_sequence),
    UNIQUE (tenant_id, id),
    FOREIGN KEY (tenant_id, recall_action_id)
        REFERENCES ewms.recall_actions(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_ewms_recall_action_event_sequence CHECK (event_sequence > 0),
    CONSTRAINT ck_ewms_recall_action_event_quantity CHECK (
        quantity_delta IS NULL OR quantity_delta <> 0
    ),
    CONSTRAINT ck_ewms_recall_action_event_status CHECK (
        (from_status IS NULL AND to_status IS NULL) OR
        (
            to_status IN (
                'OPEN','ASSIGNED','IN_PROGRESS','BLOCKED','COMPLETED','FAILED','CANCELLED'
            )
            AND (from_status IS NULL OR from_status IN (
                'OPEN','ASSIGNED','IN_PROGRESS','BLOCKED','COMPLETED','FAILED','CANCELLED'
            ))
        )
    ),
    CONSTRAINT ck_ewms_recall_action_event_masked CHECK (
        NOT ewms.jsonb_contains_forbidden_secret_key(detail_masked)
    )
);

CREATE INDEX IF NOT EXISTS ix_ewms_recall_campaign_queue
    ON ewms.recall_campaigns (
        tenant_id, owner_partner_id, status, response_due_at, initiated_at, id
    ) WHERE status NOT IN ('CLOSED','CANCELLED');
CREATE INDEX IF NOT EXISTS ix_ewms_recall_lot_lookup
    ON ewms.recall_campaign_lots (
        tenant_id, inventory_lot_id, trace_status, recall_campaign_id
    );
CREATE INDEX IF NOT EXISTS ix_ewms_recall_action_queue
    ON ewms.recall_actions (
        tenant_id, status, due_at, recall_campaign_id, action_no
    ) WHERE status NOT IN ('COMPLETED','FAILED','CANCELLED');

-- Outbound dock appointment links. The existing appointment header already models
-- INBOUND/OUTBOUND/BOTH; 03 only linked inbound orders.
CREATE TABLE IF NOT EXISTS ewms.dock_appointment_outbound_orders (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    appointment_id uuid NOT NULL REFERENCES ewms.dock_appointments(id) ON DELETE RESTRICT,
    outbound_order_id uuid NOT NULL REFERENCES ewms.outbound_orders(id) ON DELETE RESTRICT,
    sequence_no integer NOT NULL DEFAULT 1,
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    linked_by uuid REFERENCES ewms.users(id) ON DELETE SET NULL,
    linked_at timestamptz NOT NULL DEFAULT now(),
    cancelled_by uuid REFERENCES ewms.users(id) ON DELETE SET NULL,
    cancelled_at timestamptz,
    cancellation_reason text,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (appointment_id, outbound_order_id),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_dock_out_order_sequence CHECK (sequence_no > 0),
    CONSTRAINT ck_ewms_dock_out_order_status CHECK (status IN ('ACTIVE','CANCELLED')),
    CONSTRAINT ck_ewms_dock_out_order_cancel CHECK (
        (status = 'CANCELLED' AND cancelled_at IS NOT NULL) OR
        (status = 'ACTIVE' AND cancelled_at IS NULL AND cancelled_by IS NULL)
    )
);

CREATE TABLE IF NOT EXISTS ewms.dock_appointment_shipments (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    appointment_id uuid NOT NULL REFERENCES ewms.dock_appointments(id) ON DELETE RESTRICT,
    shipment_id uuid NOT NULL REFERENCES ewms.shipments(id) ON DELETE RESTRICT,
    sequence_no integer NOT NULL DEFAULT 1,
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    linked_by uuid REFERENCES ewms.users(id) ON DELETE SET NULL,
    linked_at timestamptz NOT NULL DEFAULT now(),
    cancelled_by uuid REFERENCES ewms.users(id) ON DELETE SET NULL,
    cancelled_at timestamptz,
    cancellation_reason text,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (appointment_id, shipment_id),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_dock_shipment_sequence CHECK (sequence_no > 0),
    CONSTRAINT ck_ewms_dock_shipment_status CHECK (status IN ('ACTIVE','CANCELLED')),
    CONSTRAINT ck_ewms_dock_shipment_cancel CHECK (
        (status = 'CANCELLED' AND cancelled_at IS NOT NULL) OR
        (status = 'ACTIVE' AND cancelled_at IS NULL AND cancelled_by IS NULL)
    )
);

CREATE TABLE IF NOT EXISTS ewms.dock_appointment_loads (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    appointment_id uuid NOT NULL REFERENCES ewms.dock_appointments(id) ON DELETE RESTRICT,
    load_id uuid NOT NULL REFERENCES ewms.loads(id) ON DELETE RESTRICT,
    sequence_no integer NOT NULL DEFAULT 1,
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    linked_by uuid REFERENCES ewms.users(id) ON DELETE SET NULL,
    linked_at timestamptz NOT NULL DEFAULT now(),
    cancelled_by uuid REFERENCES ewms.users(id) ON DELETE SET NULL,
    cancelled_at timestamptz,
    cancellation_reason text,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (appointment_id, load_id),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_dock_load_sequence CHECK (sequence_no > 0),
    CONSTRAINT ck_ewms_dock_load_status CHECK (status IN ('ACTIVE','CANCELLED')),
    CONSTRAINT ck_ewms_dock_load_cancel CHECK (
        (status = 'CANCELLED' AND cancelled_at IS NOT NULL) OR
        (status = 'ACTIVE' AND cancelled_at IS NULL AND cancelled_by IS NULL)
    )
);

CREATE INDEX IF NOT EXISTS ix_ewms_dock_out_order_target
    ON ewms.dock_appointment_outbound_orders (tenant_id, outbound_order_id, status, appointment_id);
CREATE INDEX IF NOT EXISTS ix_ewms_dock_shipment_target
    ON ewms.dock_appointment_shipments (tenant_id, shipment_id, status, appointment_id);
CREATE INDEX IF NOT EXISTS ix_ewms_dock_load_target
    ON ewms.dock_appointment_loads (tenant_id, load_id, status, appointment_id);

-- Slotting analysis and controlled execution recommendations.
CREATE TABLE IF NOT EXISTS ewms.slotting_runs (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    warehouse_id uuid NOT NULL REFERENCES ewms.warehouses(id),
    owner_partner_id uuid REFERENCES ewms.business_partners(id),
    run_no varchar(120) NOT NULL,
    run_type varchar(30) NOT NULL DEFAULT 'FULL',
    algorithm_code varchar(100) NOT NULL,
    algorithm_version varchar(100) NOT NULL,
    demand_window_start date,
    demand_window_end date,
    as_of_at timestamptz NOT NULL,
    input_object_uri text NOT NULL,
    input_sha256 char(64) NOT NULL,
    parameter_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
    result_summary jsonb NOT NULL DEFAULT '{}'::jsonb,
    status varchar(20) NOT NULL DEFAULT 'QUEUED',
    requested_by uuid REFERENCES ewms.users(id) ON DELETE SET NULL,
    requested_at timestamptz NOT NULL DEFAULT now(),
    started_at timestamptz,
    completed_at timestamptz,
    recommendation_count integer NOT NULL DEFAULT 0,
    accepted_count integer NOT NULL DEFAULT 0,
    applied_count integer NOT NULL DEFAULT 0,
    failure_code varchar(100),
    failure_detail_masked text,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, run_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_slotting_run_type CHECK (run_type IN (
        'FULL','INCREMENTAL','NEW_ITEM','REBALANCE','SEASONAL','WHAT_IF'
    )),
    CONSTRAINT ck_ewms_slotting_run_status CHECK (status IN (
        'QUEUED','RUNNING','COMPLETED','FAILED','CANCELLED'
    )),
    CONSTRAINT ck_ewms_slotting_run_hash CHECK (input_sha256 ~ '^[0-9A-Fa-f]{64}$'),
    CONSTRAINT ck_ewms_slotting_run_window CHECK (
        demand_window_end IS NULL OR demand_window_start IS NULL OR
        demand_window_end >= demand_window_start
    ),
    CONSTRAINT ck_ewms_slotting_run_counts CHECK (
        recommendation_count >= 0 AND accepted_count >= 0 AND applied_count >= 0
        AND accepted_count <= recommendation_count
        AND applied_count <= accepted_count
    ),
    CONSTRAINT ck_ewms_slotting_run_dates CHECK (
        (started_at IS NULL OR started_at >= requested_at)
        AND (completed_at IS NULL OR started_at IS NULL OR completed_at >= started_at)
    ),
    CONSTRAINT ck_ewms_slotting_run_completion CHECK (
        (status IN ('COMPLETED','FAILED','CANCELLED') AND completed_at IS NOT NULL) OR
        status IN ('QUEUED','RUNNING')
    ),
    CONSTRAINT ck_ewms_slotting_run_nonsecret CHECK (
        NOT ewms.jsonb_contains_forbidden_secret_key(parameter_snapshot)
        AND NOT ewms.jsonb_contains_forbidden_secret_key(result_summary)
    )
);

CREATE TABLE IF NOT EXISTS ewms.slotting_recommendations (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    slotting_run_id uuid NOT NULL,
    recommendation_rank integer NOT NULL,
    owner_partner_id uuid NOT NULL REFERENCES ewms.business_partners(id),
    item_id uuid NOT NULL REFERENCES ewms.items(id),
    from_location_id uuid REFERENCES ewms.warehouse_locations(id),
    target_location_id uuid NOT NULL REFERENCES ewms.warehouse_locations(id),
    source_stock_bucket_id uuid REFERENCES ewms.stock_buckets(id),
    recommended_base_quantity numeric(24,8),
    base_uom_code varchar(20) NOT NULL REFERENCES ewms.units_of_measure(uom_code),
    current_pick_faces integer NOT NULL DEFAULT 0,
    target_pick_faces integer NOT NULL DEFAULT 1,
    projected_travel_reduction_pct numeric(9,6),
    projected_replenishment_reduction_pct numeric(9,6),
    affinity_score numeric(20,10),
    velocity_class varchar(20),
    reason_code varchar(80) NOT NULL,
    reason_detail_masked jsonb NOT NULL DEFAULT '{}'::jsonb,
    status varchar(20) NOT NULL DEFAULT 'PROPOSED',
    reviewed_by uuid REFERENCES ewms.users(id) ON DELETE SET NULL,
    reviewed_at timestamptz,
    executed_movement_task_id uuid REFERENCES ewms.movement_tasks(id) ON DELETE RESTRICT,
    applied_at timestamptz,
    rejection_reason text,
    expires_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (slotting_run_id, recommendation_rank),
    UNIQUE (slotting_run_id, owner_partner_id, item_id, target_location_id),
    UNIQUE (tenant_id, id),
    FOREIGN KEY (tenant_id, slotting_run_id)
        REFERENCES ewms.slotting_runs(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_ewms_slotting_recommendation_rank CHECK (recommendation_rank > 0),
    CONSTRAINT ck_ewms_slotting_recommendation_locations CHECK (
        from_location_id IS NULL OR from_location_id <> target_location_id
    ),
    CONSTRAINT ck_ewms_slotting_recommendation_qty CHECK (
        recommended_base_quantity IS NULL OR recommended_base_quantity > 0
    ),
    CONSTRAINT ck_ewms_slotting_recommendation_faces CHECK (
        current_pick_faces >= 0 AND target_pick_faces > 0
    ),
    CONSTRAINT ck_ewms_slotting_recommendation_percent CHECK (
        (projected_travel_reduction_pct IS NULL OR projected_travel_reduction_pct BETWEEN -100 AND 100)
        AND (projected_replenishment_reduction_pct IS NULL OR projected_replenishment_reduction_pct BETWEEN -100 AND 100)
    ),
    CONSTRAINT ck_ewms_slotting_recommendation_velocity CHECK (
        velocity_class IS NULL OR velocity_class IN ('A','B','C','D','NEW','SEASONAL','OBSOLETE')
    ),
    CONSTRAINT ck_ewms_slotting_recommendation_status CHECK (status IN (
        'PROPOSED','ACCEPTED','REJECTED','EXECUTING','APPLIED','FAILED','EXPIRED','CANCELLED'
    )),
    CONSTRAINT ck_ewms_slotting_recommendation_review CHECK (
        (status IN ('ACCEPTED','REJECTED','EXECUTING','APPLIED','FAILED') AND reviewed_at IS NOT NULL) OR
        status IN ('PROPOSED','EXPIRED','CANCELLED')
    ),
    CONSTRAINT ck_ewms_slotting_recommendation_apply CHECK (
        (status = 'APPLIED' AND applied_at IS NOT NULL AND executed_movement_task_id IS NOT NULL) OR
        status <> 'APPLIED'
    ),
    CONSTRAINT ck_ewms_slotting_recommendation_masked CHECK (
        NOT ewms.jsonb_contains_forbidden_secret_key(reason_detail_masked)
    )
);

CREATE TABLE IF NOT EXISTS ewms.slotting_recommendation_events (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    slotting_recommendation_id uuid NOT NULL,
    event_sequence integer NOT NULL,
    from_status varchar(20),
    to_status varchar(20) NOT NULL,
    actor_user_id uuid REFERENCES ewms.users(id) ON DELETE SET NULL,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    recorded_at timestamptz NOT NULL DEFAULT now(),
    reason text,
    UNIQUE (slotting_recommendation_id, event_sequence),
    UNIQUE (tenant_id, id),
    FOREIGN KEY (tenant_id, slotting_recommendation_id)
        REFERENCES ewms.slotting_recommendations(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_ewms_slotting_event_sequence CHECK (event_sequence > 0)
);

CREATE INDEX IF NOT EXISTS ix_ewms_slotting_run_queue
    ON ewms.slotting_runs (tenant_id, warehouse_id, status, requested_at, id)
    WHERE status IN ('QUEUED','RUNNING');
CREATE INDEX IF NOT EXISTS ix_ewms_slotting_recommendation_queue
    ON ewms.slotting_recommendations (
        tenant_id, slotting_run_id, status, recommendation_rank, item_id
    ) WHERE status IN ('PROPOSED','ACCEPTED','EXECUTING','FAILED');

-- Warehouse automation integration: system -> resource -> mission -> step -> event.
CREATE TABLE IF NOT EXISTS ewms.automation_systems (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    warehouse_id uuid NOT NULL REFERENCES ewms.warehouses(id),
    external_system_id uuid REFERENCES ewms.external_systems(id) ON DELETE RESTRICT,
    system_code varchar(100) NOT NULL,
    system_name varchar(250) NOT NULL,
    system_type varchar(30) NOT NULL,
    orchestration_role varchar(30) NOT NULL,
    protocol varchar(30) NOT NULL,
    environment varchar(20) NOT NULL DEFAULT 'PRODUCTION',
    endpoint_uri text,
    credential_secret_ref varchar(500),
    heartbeat_interval_seconds integer NOT NULL DEFAULT 30,
    last_heartbeat_at timestamptz,
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    config_non_secret jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, warehouse_id, system_code),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_automation_system_type CHECK (system_type IN (
        'WCS','WES','AMR_FLEET','ASRS','CONVEYOR','SORTER','SHUTTLE','CAROUSEL','PLC','OTHER'
    )),
    CONSTRAINT ck_ewms_automation_orchestration_role CHECK (orchestration_role IN (
        'ORCHESTRATOR','EXECUTOR','RESOURCE_MANAGER','TELEMETRY','HYBRID'
    )),
    CONSTRAINT ck_ewms_automation_protocol CHECK (protocol IN (
        'REST','MQTT','AMQP','KAFKA','WEBSOCKET','OPC_UA','TCP','SFTP','OTHER'
    )),
    CONSTRAINT ck_ewms_automation_environment CHECK (environment IN (
        'DEVELOPMENT','TEST','SANDBOX','PRODUCTION'
    )),
    CONSTRAINT ck_ewms_automation_system_status CHECK (status IN (
        'ACTIVE','DEGRADED','OFFLINE','MAINTENANCE','DISABLED','RETIRED'
    )),
    CONSTRAINT ck_ewms_automation_heartbeat_interval CHECK (
        heartbeat_interval_seconds BETWEEN 1 AND 86400
    ),
    CONSTRAINT ck_ewms_automation_system_nonsecret CHECK (
        NOT ewms.jsonb_contains_forbidden_secret_key(config_non_secret)
    )
);

CREATE TABLE IF NOT EXISTS ewms.automation_resources (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    automation_system_id uuid NOT NULL,
    warehouse_id uuid NOT NULL REFERENCES ewms.warehouses(id),
    resource_code varchar(120) NOT NULL,
    resource_name varchar(250),
    resource_type varchar(40) NOT NULL,
    parent_resource_id uuid,
    current_location_id uuid REFERENCES ewms.warehouse_locations(id),
    home_location_id uuid REFERENCES ewms.warehouse_locations(id),
    work_area_id uuid REFERENCES ewms.work_areas(id),
    max_payload_weight numeric(24,8),
    weight_uom_code varchar(20) REFERENCES ewms.units_of_measure(uom_code),
    max_payload_volume numeric(24,9),
    volume_uom_code varchar(20) REFERENCES ewms.units_of_measure(uom_code),
    battery_percent numeric(7,4),
    availability_status varchar(30) NOT NULL DEFAULT 'AVAILABLE',
    operational_status varchar(30) NOT NULL DEFAULT 'ONLINE',
    active_mission_id uuid,
    last_telemetry_at timestamptz,
    config_non_secret jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (automation_system_id, resource_code),
    UNIQUE (tenant_id, id),
    FOREIGN KEY (tenant_id, automation_system_id)
        REFERENCES ewms.automation_systems(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, parent_resource_id)
        REFERENCES ewms.automation_resources(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_ewms_automation_resource_type CHECK (resource_type IN (
        'AMR','AGV','CRANE','SHUTTLE','CONVEYOR_ZONE','SORTER_CHUTE','LIFT','ROBOT_ARM',
        'STORAGE_BIN','BUFFER','STATION','DOOR','SENSOR','OTHER'
    )),
    CONSTRAINT ck_ewms_automation_resource_parent CHECK (
        parent_resource_id IS NULL OR parent_resource_id <> id
    ),
    CONSTRAINT ck_ewms_automation_resource_capacity CHECK (
        (max_payload_weight IS NULL OR max_payload_weight > 0)
        AND (max_payload_volume IS NULL OR max_payload_volume > 0)
        AND (battery_percent IS NULL OR battery_percent BETWEEN 0 AND 100)
    ),
    CONSTRAINT ck_ewms_automation_resource_availability CHECK (availability_status IN (
        'AVAILABLE','RESERVED','BUSY','BLOCKED','CHARGING','MAINTENANCE','UNAVAILABLE'
    )),
    CONSTRAINT ck_ewms_automation_resource_operational CHECK (operational_status IN (
        'ONLINE','DEGRADED','OFFLINE','ERROR','EMERGENCY_STOP','RETIRED'
    )),
    CONSTRAINT ck_ewms_automation_resource_nonsecret CHECK (
        NOT ewms.jsonb_contains_forbidden_secret_key(config_non_secret)
    )
);

CREATE TABLE IF NOT EXISTS ewms.automation_missions (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    automation_system_id uuid NOT NULL,
    warehouse_id uuid NOT NULL REFERENCES ewms.warehouses(id),
    mission_no varchar(150) NOT NULL,
    external_mission_id varchar(300),
    idempotency_key varchar(300) NOT NULL,
    mission_type varchar(40) NOT NULL,
    priority integer NOT NULL DEFAULT 100,
    source_location_id uuid REFERENCES ewms.warehouse_locations(id),
    destination_location_id uuid REFERENCES ewms.warehouse_locations(id),
    lpn_id uuid REFERENCES ewms.lpns(id) ON DELETE RESTRICT,
    movement_task_id uuid REFERENCES ewms.movement_tasks(id) ON DELETE RESTRICT,
    assigned_resource_id uuid,
    parent_mission_id uuid,
    requested_by_system varchar(100),
    requested_at timestamptz NOT NULL DEFAULT now(),
    queued_at timestamptz,
    dispatched_at timestamptz,
    started_at timestamptz,
    completed_at timestamptz,
    status varchar(30) NOT NULL DEFAULT 'CREATED',
    failure_code varchar(120),
    failure_detail_masked text,
    command_summary_masked jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, mission_no),
    UNIQUE (automation_system_id, idempotency_key),
    UNIQUE (tenant_id, id),
    FOREIGN KEY (tenant_id, automation_system_id)
        REFERENCES ewms.automation_systems(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, assigned_resource_id)
        REFERENCES ewms.automation_resources(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, parent_mission_id)
        REFERENCES ewms.automation_missions(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_ewms_automation_mission_type CHECK (mission_type IN (
        'PUTAWAY','MOVE','REPLENISHMENT','PICK','STAGE','LOAD','UNLOAD','CROSS_DOCK',
        'CYCLE_COUNT','CHARGE','PARK','RECOVERY','OTHER'
    )),
    CONSTRAINT ck_ewms_automation_mission_priority CHECK (priority BETWEEN 0 AND 9999),
    CONSTRAINT ck_ewms_automation_mission_locations CHECK (
        source_location_id IS NOT NULL OR destination_location_id IS NOT NULL
    ),
    CONSTRAINT ck_ewms_automation_mission_parent CHECK (parent_mission_id IS NULL OR parent_mission_id <> id),
    CONSTRAINT ck_ewms_automation_mission_status CHECK (status IN (
        'CREATED','QUEUED','DISPATCHED','ACCEPTED','IN_PROGRESS','PAUSED','BLOCKED',
        'COMPLETED','FAILED','CANCEL_REQUESTED','CANCELLED','SUPERSEDED'
    )),
    CONSTRAINT ck_ewms_automation_mission_dates CHECK (
        (queued_at IS NULL OR queued_at >= requested_at)
        AND (dispatched_at IS NULL OR queued_at IS NULL OR dispatched_at >= queued_at)
        AND (started_at IS NULL OR dispatched_at IS NULL OR started_at >= dispatched_at)
        AND (completed_at IS NULL OR started_at IS NULL OR completed_at >= started_at)
    ),
    CONSTRAINT ck_ewms_automation_mission_completion CHECK (
        (status IN ('COMPLETED','FAILED','CANCELLED','SUPERSEDED') AND completed_at IS NOT NULL) OR
        status NOT IN ('COMPLETED','FAILED','CANCELLED','SUPERSEDED')
    ),
    CONSTRAINT ck_ewms_automation_mission_nonsecret CHECK (
        NOT ewms.jsonb_contains_forbidden_secret_key(command_summary_masked)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_ewms_automation_external_mission
    ON ewms.automation_missions (automation_system_id, external_mission_id)
    WHERE external_mission_id IS NOT NULL;

DO $block$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
         WHERE conrelid = 'ewms.automation_resources'::regclass
           AND conname = 'fk_ewms_automation_resource_active_mission'
    ) THEN
        ALTER TABLE ewms.automation_resources
            ADD CONSTRAINT fk_ewms_automation_resource_active_mission
            FOREIGN KEY (tenant_id, active_mission_id)
            REFERENCES ewms.automation_missions(tenant_id, id) ON DELETE RESTRICT
            DEFERRABLE INITIALLY DEFERRED;
    END IF;
END;
$block$;

CREATE TABLE IF NOT EXISTS ewms.automation_mission_steps (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    automation_mission_id uuid NOT NULL,
    step_sequence integer NOT NULL,
    step_type varchar(40) NOT NULL,
    assigned_resource_id uuid,
    source_location_id uuid REFERENCES ewms.warehouse_locations(id),
    destination_location_id uuid REFERENCES ewms.warehouse_locations(id),
    lpn_id uuid REFERENCES ewms.lpns(id) ON DELETE RESTRICT,
    expected_base_quantity numeric(24,8),
    base_uom_code varchar(20) REFERENCES ewms.units_of_measure(uom_code),
    max_attempts integer NOT NULL DEFAULT 1,
    attempt_count integer NOT NULL DEFAULT 0,
    status varchar(30) NOT NULL DEFAULT 'PENDING',
    started_at timestamptz,
    completed_at timestamptz,
    failure_code varchar(120),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (automation_mission_id, step_sequence),
    UNIQUE (tenant_id, id),
    FOREIGN KEY (tenant_id, automation_mission_id)
        REFERENCES ewms.automation_missions(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, assigned_resource_id)
        REFERENCES ewms.automation_resources(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_ewms_automation_step_sequence CHECK (step_sequence > 0),
    CONSTRAINT ck_ewms_automation_step_type CHECK (step_type IN (
        'ACQUIRE','PICKUP','MOVE','DROP','SCAN','WEIGH','MEASURE','WAIT','CHARGE','PARK',
        'DOOR_OPEN','DOOR_CLOSE','HANDOFF','VERIFY','OTHER'
    )),
    CONSTRAINT ck_ewms_automation_step_qty CHECK (
        expected_base_quantity IS NULL OR expected_base_quantity > 0
    ),
    CONSTRAINT ck_ewms_automation_step_attempts CHECK (
        max_attempts > 0 AND attempt_count BETWEEN 0 AND max_attempts
    ),
    CONSTRAINT ck_ewms_automation_step_status CHECK (status IN (
        'PENDING','READY','DISPATCHED','IN_PROGRESS','PAUSED','BLOCKED',
        'COMPLETED','FAILED','SKIPPED','CANCELLED'
    )),
    CONSTRAINT ck_ewms_automation_step_dates CHECK (
        completed_at IS NULL OR started_at IS NULL OR completed_at >= started_at
    ),
    CONSTRAINT ck_ewms_automation_step_completion CHECK (
        (status IN ('COMPLETED','FAILED','SKIPPED','CANCELLED') AND completed_at IS NOT NULL) OR
        status NOT IN ('COMPLETED','FAILED','SKIPPED','CANCELLED')
    )
);

CREATE TABLE IF NOT EXISTS ewms.automation_events (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    automation_system_id uuid NOT NULL,
    automation_resource_id uuid,
    automation_mission_id uuid,
    automation_mission_step_id uuid,
    event_sequence bigint NOT NULL,
    external_event_id varchar(300),
    event_type varchar(100) NOT NULL,
    from_status varchar(30),
    to_status varchar(30),
    occurred_at timestamptz NOT NULL,
    received_at timestamptz NOT NULL DEFAULT now(),
    correlation_id varchar(150),
    payload_object_uri text,
    payload_sha256 char(64),
    payload_summary_masked jsonb NOT NULL DEFAULT '{}'::jsonb,
    UNIQUE (automation_system_id, event_sequence),
    UNIQUE (tenant_id, id),
    FOREIGN KEY (tenant_id, automation_system_id)
        REFERENCES ewms.automation_systems(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, automation_resource_id)
        REFERENCES ewms.automation_resources(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, automation_mission_id)
        REFERENCES ewms.automation_missions(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, automation_mission_step_id)
        REFERENCES ewms.automation_mission_steps(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_ewms_automation_event_sequence CHECK (event_sequence > 0),
    CONSTRAINT ck_ewms_automation_event_scope CHECK (
        automation_mission_step_id IS NULL OR automation_mission_id IS NOT NULL
    ),
    CONSTRAINT ck_ewms_automation_event_times CHECK (received_at >= occurred_at - interval '30 days'),
    CONSTRAINT ck_ewms_automation_event_payload CHECK (
        (payload_object_uri IS NULL AND payload_sha256 IS NULL) OR
        (payload_object_uri IS NOT NULL AND payload_sha256 ~ '^[0-9A-Fa-f]{64}$')
    ),
    CONSTRAINT ck_ewms_automation_event_nonsecret CHECK (
        NOT ewms.jsonb_contains_forbidden_secret_key(payload_summary_masked)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_ewms_automation_external_event
    ON ewms.automation_events (automation_system_id, external_event_id)
    WHERE external_event_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_ewms_automation_resource_queue
    ON ewms.automation_resources (
        tenant_id, warehouse_id, availability_status, operational_status, resource_type, id
    );
CREATE INDEX IF NOT EXISTS ix_ewms_automation_mission_queue
    ON ewms.automation_missions (
        tenant_id, warehouse_id, status, priority, requested_at, id
    ) WHERE status NOT IN ('COMPLETED','FAILED','CANCELLED','SUPERSEDED');
CREATE INDEX IF NOT EXISTS ix_ewms_automation_step_queue
    ON ewms.automation_mission_steps (
        tenant_id, status, automation_mission_id, step_sequence
    ) WHERE status NOT IN ('COMPLETED','FAILED','SKIPPED','CANCELLED');
CREATE INDEX IF NOT EXISTS ix_ewms_automation_event_timeline
    ON ewms.automation_events (
        tenant_id, automation_mission_id, occurred_at, event_sequence
    );

-- Legal-status changes and physical withdrawals carry line-level official evidence.
-- A stock bucket never changes dimensions in place; the inventory ledger moves quantity
-- between a source and destination bucket and this append-only row explains that legal move.
CREATE TABLE IF NOT EXISTS ewms.inventory_customs_status_transitions (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    owner_partner_id uuid NOT NULL REFERENCES ewms.business_partners(id),
    inventory_transaction_id uuid NOT NULL REFERENCES ewms.inventory_transaction_headers(id) ON DELETE RESTRICT,
    source_inventory_entry_id uuid NOT NULL REFERENCES ewms.inventory_transaction_entries(id) ON DELETE RESTRICT,
    destination_inventory_entry_id uuid NOT NULL REFERENCES ewms.inventory_transaction_entries(id) ON DELETE RESTRICT,
    source_stock_bucket_id uuid NOT NULL REFERENCES ewms.stock_buckets(id) ON DELETE RESTRICT,
    destination_stock_bucket_id uuid NOT NULL REFERENCES ewms.stock_buckets(id) ON DELETE RESTRICT,
    from_legal_status_code varchar(50) NOT NULL
        REFERENCES ewms.customs_inventory_legal_statuses(legal_status_code) ON DELETE RESTRICT,
    to_legal_status_code varchar(50) NOT NULL
        REFERENCES ewms.customs_inventory_legal_statuses(legal_status_code) ON DELETE RESTRICT,
    customs_release_line_coverage_id uuid NOT NULL
        REFERENCES ewms.customs_release_line_coverages(id) ON DELETE RESTRICT,
    transitioned_base_quantity numeric(24,8) NOT NULL,
    base_uom_code varchar(20) NOT NULL REFERENCES ewms.units_of_measure(uom_code),
    transition_purpose varchar(30) NOT NULL,
    created_by uuid REFERENCES ewms.users(id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (source_inventory_entry_id, destination_inventory_entry_id, customs_release_line_coverage_id),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_inventory_customs_transition_buckets CHECK (
        source_stock_bucket_id <> destination_stock_bucket_id
    ),
    CONSTRAINT ck_ewms_inventory_customs_transition_status CHECK (
        from_legal_status_code <> to_legal_status_code
    ),
    CONSTRAINT ck_ewms_inventory_customs_transition_qty CHECK (transitioned_base_quantity > 0),
    CONSTRAINT ck_ewms_inventory_customs_transition_purpose CHECK (transition_purpose IN (
        'IMPORT_RELEASE','EXPORT_CLEARANCE','BONDED_RELEASE','TRANSIT_RELEASE',
        'RETURN_RELEASE','ENFORCEMENT','DISPOSAL'
    ))
);

CREATE TABLE IF NOT EXISTS ewms.shipping_customs_release_allocations (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    shipping_inventory_allocation_id uuid NOT NULL
        REFERENCES ewms.shipping_inventory_allocations(id) ON DELETE RESTRICT,
    source_stock_bucket_id uuid NOT NULL REFERENCES ewms.stock_buckets(id) ON DELETE RESTRICT,
    customs_release_line_coverage_id uuid NOT NULL
        REFERENCES ewms.customs_release_line_coverages(id) ON DELETE RESTRICT,
    release_purpose varchar(30) NOT NULL,
    released_base_quantity numeric(24,8) NOT NULL,
    base_uom_code varchar(20) NOT NULL REFERENCES ewms.units_of_measure(uom_code),
    created_by uuid REFERENCES ewms.users(id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (shipping_inventory_allocation_id, customs_release_line_coverage_id, release_purpose),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_ewms_shipping_customs_release_purpose CHECK (release_purpose IN (
        'DOMESTIC_RELEASE','EXPORT','BONDED_TRANSFER','RETURN','DISPOSAL'
    )),
    CONSTRAINT ck_ewms_shipping_customs_release_qty CHECK (released_base_quantity > 0)
);

CREATE INDEX IF NOT EXISTS ix_ewms_inventory_customs_transition_tx
    ON ewms.inventory_customs_status_transitions (
        tenant_id, inventory_transaction_id, source_inventory_entry_id, destination_inventory_entry_id
    );
CREATE INDEX IF NOT EXISTS ix_ewms_inventory_customs_transition_coverage
    ON ewms.inventory_customs_status_transitions (
        customs_release_line_coverage_id, inventory_transaction_id
    );
CREATE INDEX IF NOT EXISTS ix_ewms_shipping_customs_release_allocation
    ON ewms.shipping_customs_release_allocations (
        tenant_id, shipping_inventory_allocation_id, source_stock_bucket_id
    );
CREATE INDEX IF NOT EXISTS ix_ewms_shipping_customs_release_coverage
    ON ewms.shipping_customs_release_allocations (
        customs_release_line_coverage_id, shipping_inventory_allocation_id
    );

CREATE OR REPLACE FUNCTION ewms.protect_unipass_mapping_version()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, ewms
AS $function$
DECLARE
    transition_allowed boolean;
    old_core jsonb;
    new_core jsonb;
    child_count bigint;
    invalid_child_count bigint;
    parent_status varchar(20);
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'Official UNI-PASS mapping version % cannot be deleted', OLD.id
            USING ERRCODE = '55000';
    END IF;

    transition_allowed :=
        OLD.status = NEW.status OR
        (OLD.status = 'DRAFT' AND NEW.status = 'VERIFIED') OR
        (OLD.status = 'VERIFIED' AND NEW.status = 'ACTIVE') OR
        (OLD.status = 'ACTIVE' AND NEW.status = 'RETIRED');
    IF NOT transition_allowed THEN
        RAISE EXCEPTION 'Invalid official mapping lifecycle % -> % for %.%',
            OLD.status, NEW.status, TG_TABLE_SCHEMA, TG_TABLE_NAME
            USING ERRCODE = '23514';
    END IF;

    old_core := to_jsonb(OLD) - ARRAY[
        'status','verified_at','activated_at','retired_at'
    ]::text[];
    new_core := to_jsonb(NEW) - ARRAY[
        'status','verified_at','activated_at','retired_at'
    ]::text[];
    IF OLD.status <> 'DRAFT' AND old_core IS DISTINCT FROM new_core THEN
        RAISE EXCEPTION 'Verified official mapping version % core is immutable', OLD.id
            USING ERRCODE = '55000';
    END IF;
    IF OLD.status = 'DRAFT' AND NEW.status <> 'DRAFT'
       AND old_core IS DISTINCT FROM new_core THEN
        RAISE EXCEPTION 'Edit and verification of mapping version % must be separate operations', OLD.id
            USING ERRCODE = '23514';
    END IF;

    IF NEW.status = 'VERIFIED' AND OLD.status = 'DRAFT' THEN
        IF TG_TABLE_NAME = 'unipass_mapping_versions' THEN
            SELECT count(*) INTO child_count
              FROM ewms.unipass_field_mappings
             WHERE unipass_mapping_version_id = NEW.id;
        ELSE
            SELECT count(*) INTO child_count
              FROM ewms.unipass_code_mappings
             WHERE code_mapping_version_id = NEW.id;
            SELECT mapping.status INTO parent_status
              FROM ewms.unipass_mapping_versions mapping
              JOIN ewms.unipass_code_mapping_versions code_version
                ON code_version.unipass_mapping_version_id = mapping.id
             WHERE code_version.id = NEW.id
             FOR SHARE OF mapping;
            IF parent_status IS NULL OR parent_status NOT IN ('VERIFIED','ACTIVE') THEN
                RAISE EXCEPTION 'Code mapping version % cannot be verified before its field mapping version', NEW.id
                    USING ERRCODE = '23514';
            END IF;
        END IF;
        IF child_count = 0 THEN
            RAISE EXCEPTION 'Official mapping version % has no mapping rows', NEW.id
                USING ERRCODE = '23514';
        END IF;
    END IF;

    IF TG_TABLE_NAME = 'unipass_code_mapping_versions'
       AND OLD.status = 'VERIFIED' AND NEW.status = 'ACTIVE' THEN
        SELECT mapping.status INTO parent_status
          FROM ewms.unipass_mapping_versions mapping
         WHERE mapping.id = NEW.unipass_mapping_version_id
         FOR SHARE;
        IF parent_status IS NULL OR parent_status NOT IN ('VERIFIED','ACTIVE') THEN
            RAISE EXCEPTION 'Code mapping version % cannot activate under a % field mapping version',
                NEW.id, COALESCE(parent_status, 'missing') USING ERRCODE = '23514';
        END IF;
    END IF;

    IF TG_TABLE_NAME = 'unipass_mapping_versions'
       AND OLD.status = 'VERIFIED' AND NEW.status = 'ACTIVE' THEN
        SELECT count(*) INTO invalid_child_count
          FROM ewms.unipass_field_mappings field_mapping
          LEFT JOIN ewms.unipass_code_mapping_versions code_version
            ON code_version.id = field_mapping.code_mapping_version_id
         WHERE field_mapping.unipass_mapping_version_id = NEW.id
           AND field_mapping.code_mapping_version_id IS NOT NULL
           AND (
               code_version.id IS NULL
               OR code_version.unipass_mapping_version_id <> NEW.id
               OR code_version.status <> 'ACTIVE'
           );
        IF invalid_child_count <> 0 THEN
            RAISE EXCEPTION 'Official mapping version % references % non-active or foreign code mappings',
                NEW.id, invalid_child_count USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION ewms.guard_unipass_mapping_child()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, ewms
AS $function$
DECLARE
    parent_id uuid;
    old_parent_id uuid;
    parent_status varchar(20);
    field_parent_id uuid;
    code_parent_id uuid;
BEGIN
    parent_id := NULLIF(
        (CASE WHEN TG_OP = 'DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END) ->> TG_ARGV[0],
        ''
    )::uuid;
    IF TG_OP = 'UPDATE' THEN
        old_parent_id := NULLIF(to_jsonb(OLD) ->> TG_ARGV[0], '')::uuid;
        IF old_parent_id IS DISTINCT FROM parent_id THEN
            RAISE EXCEPTION 'Official UNI-PASS mapping rows cannot be moved between versions'
                USING ERRCODE = '55000';
        END IF;
    END IF;
    -- Child DML and DRAFT -> VERIFIED are one lifecycle critical section.
    -- Without a conflicting parent-row lock, a concurrent last-child DELETE and
    -- verification can both validate an obsolete snapshot and commit an empty
    -- VERIFIED mapping version.
    EXECUTE format(
        'SELECT status FROM ewms.%I WHERE id = $1 FOR UPDATE', TG_ARGV[1]
    )
       INTO parent_status USING parent_id;
    IF parent_status IS NULL THEN
        RAISE EXCEPTION 'Unknown official mapping parent % in %', parent_id, TG_ARGV[1]
            USING ERRCODE = '23503';
    END IF;
    IF parent_status <> 'DRAFT' THEN
        RAISE EXCEPTION 'Mappings under % version % are immutable', parent_status, parent_id
            USING ERRCODE = '55000';
    END IF;

    IF TG_TABLE_NAME = 'unipass_field_mappings' AND TG_OP <> 'DELETE'
       AND NEW.code_mapping_version_id IS NOT NULL THEN
        SELECT unipass_mapping_version_id INTO code_parent_id
          FROM ewms.unipass_code_mapping_versions
         WHERE id = NEW.code_mapping_version_id
         FOR UPDATE;
        field_parent_id := NEW.unipass_mapping_version_id;
        IF code_parent_id IS DISTINCT FROM field_parent_id THEN
            RAISE EXCEPTION 'Field mapping and code mapping version must share one UNI-PASS mapping version'
                USING ERRCODE = '23514';
        END IF;
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_protect_unipass_mapping_version ON ewms.unipass_mapping_versions;
CREATE TRIGGER trg_protect_unipass_mapping_version
    BEFORE UPDATE OR DELETE ON ewms.unipass_mapping_versions
    FOR EACH ROW EXECUTE PROCEDURE ewms.protect_unipass_mapping_version();

DROP TRIGGER IF EXISTS trg_protect_unipass_code_mapping_version ON ewms.unipass_code_mapping_versions;
CREATE TRIGGER trg_protect_unipass_code_mapping_version
    BEFORE UPDATE OR DELETE ON ewms.unipass_code_mapping_versions
    FOR EACH ROW EXECUTE PROCEDURE ewms.protect_unipass_mapping_version();

DROP TRIGGER IF EXISTS trg_guard_unipass_field_mapping ON ewms.unipass_field_mappings;
CREATE TRIGGER trg_guard_unipass_field_mapping
    BEFORE INSERT OR UPDATE OR DELETE ON ewms.unipass_field_mappings
    FOR EACH ROW EXECUTE PROCEDURE ewms.guard_unipass_mapping_child(
        'unipass_mapping_version_id','unipass_mapping_versions'
    );

DROP TRIGGER IF EXISTS trg_guard_unipass_code_mapping ON ewms.unipass_code_mappings;
CREATE TRIGGER trg_guard_unipass_code_mapping
    BEFORE INSERT OR UPDATE OR DELETE ON ewms.unipass_code_mappings
    FOR EACH ROW EXECUTE PROCEDURE ewms.guard_unipass_mapping_child(
        'code_mapping_version_id','unipass_code_mapping_versions'
    );

CREATE OR REPLACE FUNCTION ewms.validate_customer_return_status_history()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, ewms
AS $function$
DECLARE
    return_tenant_id uuid;
    return_status varchar(30);
    previous_sequence integer;
    previous_status varchar(30);
BEGIN
    SELECT tenant_id, status
      INTO return_tenant_id, return_status
      FROM ewms.customer_return_orders
     WHERE id = NEW.customer_return_order_id
     FOR UPDATE;
    IF NOT FOUND OR return_tenant_id IS DISTINCT FROM NEW.tenant_id THEN
        RAISE EXCEPTION 'Customer-return history references an invalid tenant-scoped return order'
            USING ERRCODE = '23503';
    END IF;

    SELECT event_sequence, to_status
      INTO previous_sequence, previous_status
      FROM ewms.customer_return_status_history
     WHERE customer_return_order_id = NEW.customer_return_order_id
     ORDER BY event_sequence DESC
     LIMIT 1;
    IF previous_sequence IS NULL THEN
        IF NEW.event_sequence <> 1 OR NEW.from_status IS NOT NULL THEN
            RAISE EXCEPTION 'First customer-return status event must be sequence 1 with no from_status'
                USING ERRCODE = '23514';
        END IF;
    ELSIF NEW.event_sequence <> previous_sequence + 1
       OR NEW.from_status IS DISTINCT FROM previous_status THEN
        RAISE EXCEPTION 'Customer-return status history must be gap-free and continue from %', previous_status
            USING ERRCODE = '23514';
    END IF;
    IF NEW.to_status IS DISTINCT FROM return_status THEN
        RAISE EXCEPTION 'Customer-return history to_status % must equal header status %',
            NEW.to_status, return_status USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION ewms.assert_customer_return_status_history()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, ewms
AS $function$
DECLARE
    latest_status varchar(30);
BEGIN
    SELECT to_status INTO latest_status
      FROM ewms.customer_return_status_history
     WHERE tenant_id = NEW.tenant_id
       AND customer_return_order_id = NEW.id
     ORDER BY event_sequence DESC
     LIMIT 1;
    IF latest_status IS DISTINCT FROM NEW.status THEN
        RAISE EXCEPTION 'Customer-return order % status % lacks its append-only status event',
            NEW.id, NEW.status USING ERRCODE = '23514';
    END IF;
    RETURN NULL;
END;
$function$;

CREATE OR REPLACE FUNCTION ewms.validate_recall_campaign_status_history()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, ewms
AS $function$
DECLARE
    campaign_tenant_id uuid;
    campaign_status varchar(30);
    previous_sequence integer;
    previous_status varchar(30);
BEGIN
    SELECT tenant_id, status
      INTO campaign_tenant_id, campaign_status
      FROM ewms.recall_campaigns
     WHERE id = NEW.recall_campaign_id
     FOR UPDATE;
    IF NOT FOUND OR campaign_tenant_id IS DISTINCT FROM NEW.tenant_id THEN
        RAISE EXCEPTION 'Recall history references an invalid tenant-scoped campaign'
            USING ERRCODE = '23503';
    END IF;

    SELECT event_sequence, to_status
      INTO previous_sequence, previous_status
      FROM ewms.recall_campaign_status_history
     WHERE recall_campaign_id = NEW.recall_campaign_id
     ORDER BY event_sequence DESC
     LIMIT 1;
    IF previous_sequence IS NULL THEN
        IF NEW.event_sequence <> 1 OR NEW.from_status IS NOT NULL
           OR NEW.to_status <> 'DRAFT' THEN
            RAISE EXCEPTION 'First recall campaign event must establish DRAFT at sequence 1'
                USING ERRCODE = '23514';
        END IF;
    ELSE
        IF NEW.event_sequence <> previous_sequence + 1
           OR NEW.from_status IS DISTINCT FROM previous_status THEN
            RAISE EXCEPTION 'Recall campaign history must be gap-free and continue from %',
                previous_status USING ERRCODE = '23514';
        END IF;
        IF NOT (
            (previous_status = 'DRAFT' AND NEW.to_status IN ('APPROVED','CANCELLED')) OR
            (previous_status = 'APPROVED' AND NEW.to_status IN ('ACTIVE','CANCELLED')) OR
            (previous_status = 'ACTIVE' AND NEW.to_status IN ('CONTAINMENT','CANCELLED')) OR
            (previous_status = 'CONTAINMENT' AND NEW.to_status IN ('RECOVERY','CANCELLED')) OR
            (previous_status = 'RECOVERY' AND NEW.to_status IN ('EFFECTIVENESS_CHECK','CANCELLED')) OR
            (previous_status = 'EFFECTIVENESS_CHECK' AND NEW.to_status IN ('RECOVERY','CLOSED','CANCELLED'))
        ) THEN
            RAISE EXCEPTION 'Invalid recall campaign transition % -> %',
                previous_status, NEW.to_status USING ERRCODE = '23514';
        END IF;
    END IF;
    IF NEW.to_status IS DISTINCT FROM campaign_status THEN
        RAISE EXCEPTION 'Recall campaign history to_status % must equal header status %',
            NEW.to_status, campaign_status USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION ewms.assert_recall_campaign_status_history()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, ewms
AS $function$
DECLARE
    latest_status varchar(30);
BEGIN
    SELECT to_status INTO latest_status
      FROM ewms.recall_campaign_status_history
     WHERE tenant_id = NEW.tenant_id
       AND recall_campaign_id = NEW.id
     ORDER BY event_sequence DESC
     LIMIT 1;
    IF latest_status IS DISTINCT FROM NEW.status THEN
        RAISE EXCEPTION 'Recall campaign % status % lacks its append-only status event',
            NEW.id, NEW.status USING ERRCODE = '23514';
    END IF;
    RETURN NULL;
END;
$function$;

CREATE OR REPLACE FUNCTION ewms.validate_recall_action_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, ewms
AS $function$
DECLARE
    action_tenant_id uuid;
    action_status varchar(20);
    previous_sequence integer;
    previous_status varchar(20);
BEGIN
    SELECT tenant_id, status
      INTO action_tenant_id, action_status
      FROM ewms.recall_actions
     WHERE id = NEW.recall_action_id
     FOR UPDATE;
    IF NOT FOUND OR action_tenant_id IS DISTINCT FROM NEW.tenant_id THEN
        RAISE EXCEPTION 'Recall action event references an invalid tenant-scoped action'
            USING ERRCODE = '23503';
    END IF;

    SELECT max(event_sequence) INTO previous_sequence
      FROM ewms.recall_action_events
     WHERE recall_action_id = NEW.recall_action_id;
    SELECT to_status INTO previous_status
      FROM ewms.recall_action_events
     WHERE recall_action_id = NEW.recall_action_id
       AND to_status IS NOT NULL
     ORDER BY event_sequence DESC
     LIMIT 1;

    IF previous_sequence IS NULL THEN
        IF NEW.event_sequence <> 1 OR NEW.from_status IS NOT NULL
           OR NEW.to_status <> 'OPEN' THEN
            RAISE EXCEPTION 'First recall action event must establish OPEN at sequence 1'
                USING ERRCODE = '23514';
        END IF;
    ELSIF NEW.event_sequence <> previous_sequence + 1 THEN
        RAISE EXCEPTION 'Recall action event history must be gap-free'
            USING ERRCODE = '23514';
    END IF;

    IF NEW.to_status IS NULL THEN
        IF NEW.from_status IS NOT NULL OR previous_status IS DISTINCT FROM action_status THEN
            RAISE EXCEPTION 'Non-status recall events require a current status timeline and null status fields'
                USING ERRCODE = '23514';
        END IF;
    ELSIF previous_sequence IS NOT NULL THEN
        IF NEW.from_status IS DISTINCT FROM previous_status THEN
            RAISE EXCEPTION 'Recall action status event must continue from %', previous_status
                USING ERRCODE = '23514';
        END IF;
        IF NOT (
            (previous_status = 'OPEN' AND NEW.to_status IN ('ASSIGNED','IN_PROGRESS','CANCELLED')) OR
            (previous_status = 'ASSIGNED' AND NEW.to_status IN ('IN_PROGRESS','BLOCKED','CANCELLED')) OR
            (previous_status = 'IN_PROGRESS' AND NEW.to_status IN ('BLOCKED','COMPLETED','FAILED','CANCELLED')) OR
            (previous_status = 'BLOCKED' AND NEW.to_status IN ('ASSIGNED','IN_PROGRESS','FAILED','CANCELLED'))
        ) THEN
            RAISE EXCEPTION 'Invalid recall action transition % -> %',
                previous_status, NEW.to_status USING ERRCODE = '23514';
        END IF;
    END IF;
    IF NEW.to_status IS NOT NULL AND NEW.to_status IS DISTINCT FROM action_status THEN
        RAISE EXCEPTION 'Recall action event to_status % must equal header status %',
            NEW.to_status, action_status USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION ewms.assert_recall_action_status_history()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, ewms
AS $function$
DECLARE
    latest_status varchar(20);
BEGIN
    SELECT to_status INTO latest_status
      FROM ewms.recall_action_events
     WHERE tenant_id = NEW.tenant_id
       AND recall_action_id = NEW.id
       AND to_status IS NOT NULL
     ORDER BY event_sequence DESC
     LIMIT 1;
    IF latest_status IS DISTINCT FROM NEW.status THEN
        RAISE EXCEPTION 'Recall action % status % lacks its append-only status event',
            NEW.id, NEW.status USING ERRCODE = '23514';
    END IF;
    RETURN NULL;
END;
$function$;

CREATE OR REPLACE FUNCTION ewms.validate_customer_return_lineage()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, ewms
AS $function$
DECLARE
    return_order_row ewms.customer_return_orders%ROWTYPE;
    return_line_row ewms.customer_return_lines%ROWTYPE;
    receipt_row ewms.receipts%ROWTYPE;
    receipt_line_row ewms.receipt_lines%ROWTYPE;
    return_receipt_row ewms.customer_return_receipt_allocations%ROWTYPE;
    return_quality_row ewms.customer_return_quality_allocations%ROWTYPE;
    disposition_allocation_row ewms.customer_return_disposition_allocations%ROWTYPE;
    inspection_row ewms.quality_inspections%ROWTYPE;
    disposition_row ewms.quality_dispositions%ROWTYPE;
    receipt_inventory_row ewms.receipt_inventory_allocations%ROWTYPE;
    receipt_posting_row ewms.receipt_inventory_postings%ROWTYPE;
    transaction_row ewms.inventory_transaction_headers%ROWTYPE;
    entry_row ewms.inventory_transaction_entries%ROWTYPE;
    bucket_row ewms.stock_buckets%ROWTYPE;
    item_base_uom varchar(20);
    existing_quantity numeric(24,8);
    existing_base_quantity numeric(24,8);
    existing_parent_quantity numeric(24,8);
BEGIN
    IF TG_TABLE_NAME = 'customer_return_receipt_allocations' THEN
        SELECT * INTO return_order_row
          FROM ewms.customer_return_orders
         WHERE id = NEW.customer_return_order_id
         FOR SHARE;
        SELECT * INTO return_line_row
          FROM ewms.customer_return_lines
         WHERE id = NEW.customer_return_line_id
         FOR UPDATE;
        SELECT * INTO receipt_row
          FROM ewms.receipts
         WHERE id = NEW.receipt_id
         FOR SHARE;
        SELECT * INTO receipt_line_row
          FROM ewms.receipt_lines
         WHERE id = NEW.receipt_line_id
         FOR UPDATE;
        IF return_order_row.id IS NULL OR return_line_row.id IS NULL
           OR receipt_row.id IS NULL OR receipt_line_row.id IS NULL THEN
            RAISE EXCEPTION 'Customer-return receipt lineage contains an unknown parent'
                USING ERRCODE = '23503';
        END IF;
        SELECT base_uom_code INTO item_base_uom
          FROM ewms.items
         WHERE id = return_line_row.item_id;
        IF return_order_row.tenant_id <> NEW.tenant_id
           OR return_line_row.tenant_id <> NEW.tenant_id
           OR receipt_row.tenant_id <> NEW.tenant_id
           OR receipt_line_row.tenant_id <> NEW.tenant_id
           OR return_line_row.customer_return_order_id <> return_order_row.id
           OR receipt_line_row.receipt_id <> receipt_row.id
           OR return_order_row.warehouse_id <> receipt_row.warehouse_id
           OR return_order_row.owner_partner_id <> receipt_row.owner_partner_id
           OR receipt_row.receipt_type <> 'RETURN'
           OR return_line_row.item_id <> receipt_line_row.item_id
           OR NEW.uom_code <> return_line_row.uom_code
           OR NEW.uom_code <> receipt_line_row.uom_code
           OR NEW.base_uom_code <> item_base_uom
           OR NEW.base_uom_code <> receipt_line_row.base_uom_code THEN
            RAISE EXCEPTION 'Customer-return, receipt, owner, warehouse, item, or UOM lineage mismatch'
                USING ERRCODE = '23514';
        END IF;
        SELECT COALESCE(sum(allocated_quantity), 0),
               COALESCE(sum(allocated_base_quantity), 0)
          INTO existing_quantity, existing_base_quantity
          FROM ewms.customer_return_receipt_allocations
         WHERE customer_return_line_id = NEW.customer_return_line_id;
        IF existing_quantity + NEW.allocated_quantity > return_line_row.received_quantity THEN
            RAISE EXCEPTION 'Return receipt allocation exceeds customer-return line received quantity'
                USING ERRCODE = '23514';
        END IF;
        SELECT COALESCE(sum(allocated_base_quantity), 0)
          INTO existing_base_quantity
          FROM ewms.customer_return_receipt_allocations
         WHERE receipt_line_id = NEW.receipt_line_id;
        IF existing_base_quantity + NEW.allocated_base_quantity > receipt_line_row.received_base_quantity THEN
            RAISE EXCEPTION 'Return receipt allocation exceeds physical receipt-line base quantity'
                USING ERRCODE = '23514';
        END IF;

    ELSIF TG_TABLE_NAME = 'customer_return_quality_allocations' THEN
        SELECT * INTO return_receipt_row
          FROM ewms.customer_return_receipt_allocations
         WHERE id = NEW.customer_return_receipt_allocation_id
         FOR UPDATE;
        SELECT * INTO inspection_row
          FROM ewms.quality_inspections
         WHERE id = NEW.quality_inspection_id
         FOR UPDATE;
        IF return_receipt_row.id IS NULL OR inspection_row.id IS NULL THEN
            RAISE EXCEPTION 'Customer-return quality lineage contains an unknown parent'
                USING ERRCODE = '23503';
        END IF;
        IF return_receipt_row.tenant_id <> NEW.tenant_id
           OR inspection_row.tenant_id <> NEW.tenant_id
           OR inspection_row.receipt_id <> return_receipt_row.receipt_id
           OR inspection_row.receipt_line_id <> return_receipt_row.receipt_line_id
           OR inspection_row.uom_code <> NEW.uom_code
           OR inspection_row.status NOT IN ('COMPLETED','APPROVED') THEN
            RAISE EXCEPTION 'Return quality allocation must reference a completed inspection of the same receipt line'
                USING ERRCODE = '23514';
        END IF;
        SELECT COALESCE(sum(allocated_quantity), 0) INTO existing_quantity
          FROM ewms.customer_return_quality_allocations
         WHERE customer_return_receipt_allocation_id = NEW.customer_return_receipt_allocation_id;
        SELECT COALESCE(sum(allocated_quantity), 0) INTO existing_parent_quantity
          FROM ewms.customer_return_quality_allocations
         WHERE quality_inspection_id = NEW.quality_inspection_id;
        IF existing_quantity + NEW.allocated_quantity > return_receipt_row.allocated_quantity
           OR existing_parent_quantity + NEW.allocated_quantity > inspection_row.inspected_quantity THEN
            RAISE EXCEPTION 'Return quality allocation exceeds receipt or inspection quantity'
                USING ERRCODE = '23514';
        END IF;

    ELSIF TG_TABLE_NAME = 'customer_return_disposition_allocations' THEN
        SELECT * INTO return_receipt_row
          FROM ewms.customer_return_receipt_allocations
         WHERE id = NEW.customer_return_receipt_allocation_id
         FOR UPDATE;
        SELECT * INTO disposition_row
          FROM ewms.quality_dispositions
         WHERE id = NEW.quality_disposition_id
         FOR UPDATE;
        IF return_receipt_row.id IS NULL OR disposition_row.id IS NULL THEN
            RAISE EXCEPTION 'Customer-return disposition lineage contains an unknown parent'
                USING ERRCODE = '23503';
        END IF;
        IF return_receipt_row.tenant_id <> NEW.tenant_id
           OR disposition_row.tenant_id <> NEW.tenant_id
           OR disposition_row.receipt_line_id <> return_receipt_row.receipt_line_id
           OR disposition_row.uom_code <> NEW.uom_code
           OR disposition_row.status <> 'EXECUTED' THEN
            RAISE EXCEPTION 'Return disposition allocation must reference an executed disposition of the same receipt line'
                USING ERRCODE = '23514';
        END IF;
        IF NEW.customer_return_quality_allocation_id IS NOT NULL THEN
            SELECT * INTO return_quality_row
              FROM ewms.customer_return_quality_allocations
             WHERE id = NEW.customer_return_quality_allocation_id
             FOR SHARE;
            IF return_quality_row.id IS NULL
               OR return_quality_row.customer_return_receipt_allocation_id <> return_receipt_row.id
               OR (disposition_row.quality_inspection_id IS NOT NULL
                   AND disposition_row.quality_inspection_id <> return_quality_row.quality_inspection_id) THEN
                RAISE EXCEPTION 'Return disposition does not match its return quality allocation'
                    USING ERRCODE = '23514';
            END IF;
        END IF;
        SELECT COALESCE(sum(allocated_quantity), 0) INTO existing_quantity
          FROM ewms.customer_return_disposition_allocations
         WHERE customer_return_receipt_allocation_id = NEW.customer_return_receipt_allocation_id;
        SELECT COALESCE(sum(allocated_quantity), 0) INTO existing_parent_quantity
          FROM ewms.customer_return_disposition_allocations
         WHERE quality_disposition_id = NEW.quality_disposition_id;
        IF existing_quantity + NEW.allocated_quantity > return_receipt_row.allocated_quantity
           OR existing_parent_quantity + NEW.allocated_quantity > disposition_row.disposition_quantity THEN
            RAISE EXCEPTION 'Return disposition allocation exceeds receipt or disposition quantity'
                USING ERRCODE = '23514';
        END IF;

    ELSIF TG_TABLE_NAME = 'customer_return_inventory_allocations' THEN
        SELECT * INTO return_receipt_row
          FROM ewms.customer_return_receipt_allocations
         WHERE id = NEW.customer_return_receipt_allocation_id
         FOR UPDATE;
        SELECT * INTO receipt_inventory_row
          FROM ewms.receipt_inventory_allocations
         WHERE id = NEW.receipt_inventory_allocation_id
         FOR UPDATE;
        IF return_receipt_row.id IS NULL OR receipt_inventory_row.id IS NULL THEN
            RAISE EXCEPTION 'Customer-return inventory lineage contains an unknown allocation'
                USING ERRCODE = '23503';
        END IF;
        SELECT * INTO receipt_posting_row
          FROM ewms.receipt_inventory_postings
         WHERE id = receipt_inventory_row.receipt_inventory_posting_id
         FOR SHARE;
        SELECT * INTO transaction_row
          FROM ewms.inventory_transaction_headers
         WHERE id = NEW.inventory_transaction_id
         FOR SHARE;
        SELECT * INTO entry_row
          FROM ewms.inventory_transaction_entries
         WHERE id = NEW.inventory_transaction_entry_id
         FOR SHARE;
        SELECT * INTO bucket_row
          FROM ewms.stock_buckets
         WHERE id = NEW.destination_stock_bucket_id
         FOR SHARE;
        IF receipt_posting_row.id IS NULL OR transaction_row.id IS NULL
           OR entry_row.id IS NULL OR bucket_row.id IS NULL THEN
            RAISE EXCEPTION 'Customer-return inventory lineage contains an unknown ledger object'
                USING ERRCODE = '23503';
        END IF;
        IF return_receipt_row.tenant_id <> NEW.tenant_id
           OR receipt_inventory_row.tenant_id <> NEW.tenant_id
           OR receipt_posting_row.tenant_id <> NEW.tenant_id
           OR transaction_row.tenant_id <> NEW.tenant_id
           OR entry_row.tenant_id <> NEW.tenant_id
           OR bucket_row.tenant_id <> NEW.tenant_id
           OR receipt_inventory_row.receipt_line_id <> return_receipt_row.receipt_line_id
           OR receipt_posting_row.receipt_id <> return_receipt_row.receipt_id
           OR receipt_posting_row.inventory_transaction_id <> transaction_row.id
           OR receipt_inventory_row.inventory_transaction_entry_id <> entry_row.id
           OR receipt_inventory_row.destination_stock_bucket_id <> bucket_row.id
           OR entry_row.inventory_transaction_id <> transaction_row.id
           OR entry_row.stock_bucket_id <> bucket_row.id
           OR entry_row.signed_quantity <= 0
           OR transaction_row.posting_status <> 'POSTED'
           OR transaction_row.transaction_type NOT IN ('RECEIPT','CUSTOMER_RETURN')
           OR NEW.inventory_transaction_entry_id <> receipt_inventory_row.inventory_transaction_entry_id
           OR NEW.destination_stock_bucket_id <> receipt_inventory_row.destination_stock_bucket_id
           OR NEW.base_uom_code <> receipt_inventory_row.base_uom_code
           OR NEW.posted_base_quantity <> receipt_inventory_row.allocated_quantity THEN
            RAISE EXCEPTION 'Customer-return inventory link does not match its posted receipt ledger entry'
                USING ERRCODE = '23514';
        END IF;
        IF NEW.customer_return_disposition_allocation_id IS NOT NULL THEN
            SELECT * INTO disposition_allocation_row
              FROM ewms.customer_return_disposition_allocations
             WHERE id = NEW.customer_return_disposition_allocation_id;
            IF disposition_allocation_row.id IS NULL
               OR disposition_allocation_row.customer_return_receipt_allocation_id <> return_receipt_row.id THEN
                RAISE EXCEPTION 'Return inventory link disposition is outside its receipt allocation'
                    USING ERRCODE = '23514';
            END IF;
        END IF;
        SELECT COALESCE(sum(posted_base_quantity), 0) INTO existing_base_quantity
          FROM ewms.customer_return_inventory_allocations
         WHERE customer_return_receipt_allocation_id = NEW.customer_return_receipt_allocation_id;
        IF existing_base_quantity + NEW.posted_base_quantity > return_receipt_row.allocated_base_quantity THEN
            RAISE EXCEPTION 'Return inventory links exceed return receipt base quantity'
                USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_validate_customer_return_status_history
    ON ewms.customer_return_status_history;
CREATE TRIGGER trg_validate_customer_return_status_history
    BEFORE INSERT ON ewms.customer_return_status_history
    FOR EACH ROW EXECUTE PROCEDURE ewms.validate_customer_return_status_history();

DROP TRIGGER IF EXISTS trg_assert_customer_return_status_history
    ON ewms.customer_return_orders;
CREATE CONSTRAINT TRIGGER trg_assert_customer_return_status_history
    AFTER INSERT OR UPDATE ON ewms.customer_return_orders
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE PROCEDURE ewms.assert_customer_return_status_history();

DROP TRIGGER IF EXISTS trg_validate_recall_campaign_status_history
    ON ewms.recall_campaign_status_history;
CREATE TRIGGER trg_validate_recall_campaign_status_history
    BEFORE INSERT ON ewms.recall_campaign_status_history
    FOR EACH ROW EXECUTE PROCEDURE ewms.validate_recall_campaign_status_history();

DROP TRIGGER IF EXISTS trg_assert_recall_campaign_status_history
    ON ewms.recall_campaigns;
CREATE CONSTRAINT TRIGGER trg_assert_recall_campaign_status_history
    AFTER INSERT OR UPDATE ON ewms.recall_campaigns
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE PROCEDURE ewms.assert_recall_campaign_status_history();

DROP TRIGGER IF EXISTS trg_validate_recall_action_event
    ON ewms.recall_action_events;
CREATE TRIGGER trg_validate_recall_action_event
    BEFORE INSERT ON ewms.recall_action_events
    FOR EACH ROW EXECUTE PROCEDURE ewms.validate_recall_action_event();

DROP TRIGGER IF EXISTS trg_assert_recall_action_status_history
    ON ewms.recall_actions;
CREATE CONSTRAINT TRIGGER trg_assert_recall_action_status_history
    AFTER INSERT OR UPDATE ON ewms.recall_actions
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE PROCEDURE ewms.assert_recall_action_status_history();

DO $block$
DECLARE
    table_name text;
BEGIN
    FOREACH table_name IN ARRAY ARRAY[
        'customer_return_receipt_allocations','customer_return_quality_allocations',
        'customer_return_disposition_allocations','customer_return_inventory_allocations'
    ]::text[]
    LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS trg_validate_customer_return_lineage ON ewms.%I', table_name);
        EXECUTE format(
            'CREATE TRIGGER trg_validate_customer_return_lineage BEFORE INSERT ON ewms.%I '
            'FOR EACH ROW EXECUTE PROCEDURE ewms.validate_customer_return_lineage()',
            table_name
        );
    END LOOP;
END;
$block$;

-- Trigger wiring that must occur after every table in this module exists.
DROP TRIGGER IF EXISTS trg_validate_inventory_customs_status_transition ON ewms.inventory_customs_status_transitions;
CREATE TRIGGER trg_validate_inventory_customs_status_transition
    BEFORE INSERT ON ewms.inventory_customs_status_transitions
    FOR EACH ROW EXECUTE PROCEDURE ewms.validate_inventory_customs_status_transition();
DROP TRIGGER IF EXISTS trg_validate_shipping_customs_release_allocation ON ewms.shipping_customs_release_allocations;
CREATE TRIGGER trg_validate_shipping_customs_release_allocation
    BEFORE INSERT ON ewms.shipping_customs_release_allocations
    FOR EACH ROW EXECUTE PROCEDURE ewms.validate_shipping_customs_release_allocation();
DROP TRIGGER IF EXISTS trg_deferred_shipping_customs_release ON ewms.shipping_inventory_allocations;
CREATE CONSTRAINT TRIGGER trg_deferred_shipping_customs_release
    AFTER INSERT OR UPDATE OR DELETE ON ewms.shipping_inventory_allocations
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE PROCEDURE ewms.deferred_assert_shipping_customs_release();
DROP TRIGGER IF EXISTS trg_deferred_shipping_customs_release_alloc ON ewms.shipping_customs_release_allocations;
CREATE CONSTRAINT TRIGGER trg_deferred_shipping_customs_release_alloc
    AFTER INSERT OR UPDATE OR DELETE ON ewms.shipping_customs_release_allocations
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE PROCEDURE ewms.deferred_assert_shipping_customs_release();

DROP TRIGGER IF EXISTS trg_validate_recall_campaign_lot ON ewms.recall_campaign_lots;
CREATE TRIGGER trg_validate_recall_campaign_lot BEFORE INSERT OR UPDATE ON ewms.recall_campaign_lots
    FOR EACH ROW EXECUTE PROCEDURE ewms.validate_recall_scope();
DROP TRIGGER IF EXISTS trg_validate_recall_action ON ewms.recall_actions;
CREATE TRIGGER trg_validate_recall_action BEFORE INSERT OR UPDATE ON ewms.recall_actions
    FOR EACH ROW EXECUTE PROCEDURE ewms.validate_recall_scope();
DROP TRIGGER IF EXISTS trg_validate_slotting_recommendation ON ewms.slotting_recommendations;
CREATE TRIGGER trg_validate_slotting_recommendation BEFORE INSERT OR UPDATE ON ewms.slotting_recommendations
    FOR EACH ROW EXECUTE PROCEDURE ewms.validate_slotting_recommendation();

DO $block$
DECLARE table_name text;
BEGIN
    FOREACH table_name IN ARRAY ARRAY[
        'dock_appointment_outbound_orders','dock_appointment_shipments','dock_appointment_loads'
    ]::text[] LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS trg_validate_outbound_dock_link ON ewms.%I', table_name);
        EXECUTE format('CREATE TRIGGER trg_validate_outbound_dock_link BEFORE INSERT OR UPDATE ON ewms.%I '
            'FOR EACH ROW EXECUTE PROCEDURE ewms.validate_outbound_dock_link()', table_name);
        EXECUTE format('DROP TRIGGER IF EXISTS trg_protect_outbound_dock_link ON ewms.%I', table_name);
        EXECUTE format('CREATE TRIGGER trg_protect_outbound_dock_link BEFORE UPDATE OR DELETE ON ewms.%I '
            'FOR EACH ROW EXECUTE PROCEDURE ewms.protect_outbound_dock_link()', table_name);
    END LOOP;
END;
$block$;

-- Terminal headers cannot be edited or deleted.
DO $block$
DECLARE target record;
BEGIN
    FOR target IN SELECT * FROM (VALUES
        ('customer_return_orders','status','CLOSED,REJECTED,CANCELLED'),
        ('recall_campaigns','status','CLOSED,CANCELLED'),
        ('recall_campaign_lots','trace_status','DESTROYED,RELEASED,EXCLUDED'),
        ('recall_actions','status','COMPLETED,FAILED,CANCELLED'),
        ('slotting_runs','status','COMPLETED,FAILED,CANCELLED'),
        ('slotting_recommendations','status','APPLIED,REJECTED,EXPIRED,CANCELLED'),
        ('automation_systems','status','RETIRED'),
        ('automation_resources','operational_status','RETIRED'),
        ('automation_missions','status','COMPLETED,FAILED,CANCELLED,SUPERSEDED'),
        ('automation_mission_steps','status','COMPLETED,FAILED,SKIPPED,CANCELLED')
    ) AS configured(table_name,status_column,terminal_statuses) LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS trg_14_protect_finalized ON ewms.%I', target.table_name);
        EXECUTE format('CREATE TRIGGER trg_14_protect_finalized BEFORE UPDATE OR DELETE ON ewms.%I '
            'FOR EACH ROW EXECUTE PROCEDURE ewms.protect_finalized_row(%L,%L)',
            target.table_name,target.status_column,target.terminal_statuses);
    END LOOP;
END;
$block$;

-- Legal evidence and event streams are append-only, including TRUNCATE protection.
DO $block$
DECLARE table_name text;
BEGIN
    FOREACH table_name IN ARRAY ARRAY[
        'customer_return_status_history','customer_return_receipt_allocations',
        'customer_return_quality_allocations','customer_return_disposition_allocations',
        'customer_return_inventory_allocations','recall_campaign_status_history','recall_action_events',
        'slotting_recommendation_events','automation_events','inventory_customs_status_transitions',
        'shipping_customs_release_allocations'
    ]::text[] LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS trg_14_append_only ON ewms.%I',table_name);
        EXECUTE format('CREATE TRIGGER trg_14_append_only BEFORE UPDATE OR DELETE ON ewms.%I '
            'FOR EACH ROW EXECUTE PROCEDURE ewms.prevent_append_only_change()',table_name);
        EXECUTE format('DROP TRIGGER IF EXISTS trg_14_append_only_truncate ON ewms.%I',table_name);
        EXECUTE format('CREATE TRIGGER trg_14_append_only_truncate BEFORE TRUNCATE ON ewms.%I '
            'FOR EACH STATEMENT EXECUTE PROCEDURE ewms.prevent_append_only_change()',table_name);
    END LOOP;
END;
$block$;

DROP TRIGGER IF EXISTS trg_14_customs_legal_status_append_only ON ewms.customs_inventory_legal_statuses;
CREATE TRIGGER trg_14_customs_legal_status_append_only BEFORE UPDATE OR DELETE ON ewms.customs_inventory_legal_statuses
    FOR EACH ROW EXECUTE PROCEDURE ewms.prevent_append_only_change();
DROP TRIGGER IF EXISTS trg_14_customs_legal_status_truncate ON ewms.customs_inventory_legal_statuses;
CREATE TRIGGER trg_14_customs_legal_status_truncate BEFORE TRUNCATE ON ewms.customs_inventory_legal_statuses
    FOR EACH STATEMENT EXECUTE PROCEDURE ewms.prevent_append_only_change();

-- The baseline protected individual bonded in/out report events from UPDATE/DELETE,
-- but a statement-level TRUNCATE could still erase the complete legal audit trail.
DROP TRIGGER IF EXISTS trg_14_bonded_inout_report_events_truncate
    ON ewms.bonded_inout_report_events;
CREATE TRIGGER trg_14_bonded_inout_report_events_truncate
    BEFORE TRUNCATE ON ewms.bonded_inout_report_events
    FOR EACH STATEMENT EXECUTE PROCEDURE ewms.prevent_append_only_change();

-- Optimistic locking for new mutable records.
DO $block$
DECLARE table_name text;
BEGIN
    FOREACH table_name IN ARRAY ARRAY[
        'recall_campaigns','recall_campaign_lots','recall_actions',
        'dock_appointment_outbound_orders','dock_appointment_shipments','dock_appointment_loads',
        'slotting_runs','slotting_recommendations','automation_systems','automation_resources',
        'automation_missions','automation_mission_steps'
    ]::text[] LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS trg_touch_row ON ewms.%I',table_name);
        EXECUTE format('CREATE TRIGGER trg_touch_row BEFORE UPDATE ON ewms.%I '
            'FOR EACH ROW EXECUTE PROCEDURE ewms.touch_row()',table_name);
    END LOOP;
END;
$block$;

-- tenant_id immutability for every tenant table added here.
DO $block$
DECLARE table_name text;
BEGIN
    FOREACH table_name IN ARRAY ARRAY[
        'customer_return_status_history','customer_return_receipt_allocations',
        'customer_return_quality_allocations','customer_return_disposition_allocations',
        'customer_return_inventory_allocations','recall_campaigns','recall_campaign_status_history',
        'recall_campaign_lots','recall_actions','recall_action_events',
        'dock_appointment_outbound_orders','dock_appointment_shipments','dock_appointment_loads',
        'slotting_runs','slotting_recommendations','slotting_recommendation_events',
        'automation_systems','automation_resources','automation_missions','automation_mission_steps',
        'automation_events','inventory_customs_status_transitions','shipping_customs_release_allocations'
    ]::text[] LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS trg_prevent_tenant_change ON ewms.%I',table_name);
        EXECUTE format('CREATE TRIGGER trg_prevent_tenant_change BEFORE UPDATE OF tenant_id ON ewms.%I '
            'FOR EACH ROW EXECUTE PROCEDURE ewms.prevent_tenant_change()',table_name);
    END LOOP;
END;
$block$;

-- Same-tenant guards for simple UUID FKs; composite tenant FKs are already stronger.
DO $block$
DECLARE relation record; child_column text; trigger_name text;
BEGIN
    FOR relation IN
        SELECT con.conname,con.conrelid,con.confrelid,child.relname AS child_table,
               parent_ns.nspname AS parent_schema,parent.relname AS parent_table,con.conkey[1] AS child_attnum
        FROM pg_constraint con
        JOIN pg_class child ON child.oid=con.conrelid
        JOIN pg_namespace child_ns ON child_ns.oid=child.relnamespace
        JOIN pg_class parent ON parent.oid=con.confrelid
        JOIN pg_namespace parent_ns ON parent_ns.oid=parent.relnamespace
        WHERE con.contype='f' AND child_ns.nspname='ewms' AND parent_ns.nspname='ewms'
          AND child.relname = ANY (ARRAY[
            'customer_return_status_history','customer_return_receipt_allocations',
            'customer_return_quality_allocations','customer_return_disposition_allocations',
            'customer_return_inventory_allocations','recall_campaigns','recall_campaign_status_history',
            'recall_campaign_lots','recall_actions','recall_action_events',
            'dock_appointment_outbound_orders','dock_appointment_shipments','dock_appointment_loads',
            'slotting_runs','slotting_recommendations','slotting_recommendation_events',
            'automation_systems','automation_resources','automation_missions','automation_mission_steps',
            'automation_events','inventory_customs_status_transitions','shipping_customs_release_allocations'
          ]::text[])
          AND array_length(con.conkey,1)=1
          AND EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid=con.confrelid AND a.attname='tenant_id' AND NOT a.attisdropped)
          AND EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid=con.confrelid AND a.attnum=con.confkey[1] AND a.attname='id')
    LOOP
        SELECT attname INTO child_column FROM pg_attribute
         WHERE attrelid=relation.conrelid AND attnum=relation.child_attnum;
        IF child_column='tenant_id' THEN CONTINUE; END IF;
        IF EXISTS (SELECT 1 FROM pg_constraint companion
            WHERE companion.contype='f' AND companion.conrelid=relation.conrelid
              AND companion.confrelid=relation.confrelid AND array_length(companion.conkey,1)>=2
              AND relation.child_attnum=ANY(companion.conkey)) THEN CONTINUE; END IF;
        trigger_name := 'trg_tenant_fk_'||substr(md5('ewms.'||relation.child_table||'.'||relation.conname),1,12);
        EXECUTE format('DROP TRIGGER IF EXISTS %I ON ewms.%I',trigger_name,relation.child_table);
        EXECUTE format('CREATE TRIGGER %I BEFORE INSERT OR UPDATE OF %I ON ewms.%I '
            'FOR EACH ROW EXECUTE PROCEDURE ewms.enforce_same_tenant_fk(%L,%L,%L)',
            trigger_name,child_column,relation.child_table,child_column,relation.parent_schema,relation.parent_table);
    END LOOP;
END;
$block$;

-- FK child-key leading indexes for all new local and official-mapping tables.
DO $block$
DECLARE relation record; column_list text; index_name text;
BEGIN
    FOR relation IN
        SELECT con.conname,con.conrelid,child.relname AS table_name,con.conkey
        FROM pg_constraint con JOIN pg_class child ON child.oid=con.conrelid
        JOIN pg_namespace child_ns ON child_ns.oid=child.relnamespace
        WHERE con.contype='f' AND child_ns.nspname='ewms'
          AND child.relname = ANY (ARRAY[
            'customer_return_status_history','customer_return_receipt_allocations',
            'customer_return_quality_allocations','customer_return_disposition_allocations',
            'customer_return_inventory_allocations','recall_campaigns','recall_campaign_status_history',
            'recall_campaign_lots','recall_actions','recall_action_events',
            'dock_appointment_outbound_orders','dock_appointment_shipments','dock_appointment_loads',
            'slotting_runs','slotting_recommendations','slotting_recommendation_events',
            'automation_systems','automation_resources','automation_missions','automation_mission_steps',
            'automation_events','inventory_customs_status_transitions','shipping_customs_release_allocations',
            'unipass_mapping_versions','unipass_code_mapping_versions','unipass_code_mappings','unipass_field_mappings'
          ]::text[])
        ORDER BY child.relname,array_length(con.conkey,1) DESC,con.conname
    LOOP
        SELECT string_agg(quote_ident(a.attname),', ' ORDER BY k.ordinality) INTO column_list
        FROM unnest(relation.conkey) WITH ORDINALITY AS k(attnum,ordinality)
        JOIN pg_attribute a ON a.attrelid=relation.conrelid AND a.attnum=k.attnum;
        IF EXISTS (SELECT 1 FROM pg_index i WHERE i.indrelid=relation.conrelid
            AND i.indisvalid AND i.indisready AND i.indpred IS NULL
            AND i.indnkeyatts>=array_length(relation.conkey,1)
            AND ARRAY(SELECT x.attnum FROM unnest(i.indkey) WITH ORDINALITY AS x(attnum,ordinality)
                      WHERE x.ordinality<=array_length(relation.conkey,1) ORDER BY x.ordinality)::smallint[]=relation.conkey)
        THEN CONTINUE; END IF;
        index_name := 'ix_fk14_'||substr(relation.table_name,1,28)||'_'||substr(md5(relation.table_name||'.'||relation.conname),1,10);
        EXECUTE format('CREATE INDEX IF NOT EXISTS %I ON ewms.%I (%s)',index_name,relation.table_name,column_list);
    END LOOP;
END;
$block$;

-- Exact module-13 tenant policies and FORCE RLS.
DO $block$
DECLARE table_name text;
BEGIN
    FOREACH table_name IN ARRAY ARRAY[
        'customer_return_status_history','customer_return_receipt_allocations',
        'customer_return_quality_allocations','customer_return_disposition_allocations',
        'customer_return_inventory_allocations','recall_campaigns','recall_campaign_status_history',
        'recall_campaign_lots','recall_actions','recall_action_events',
        'dock_appointment_outbound_orders','dock_appointment_shipments','dock_appointment_loads',
        'slotting_runs','slotting_recommendations','slotting_recommendation_events',
        'automation_systems','automation_resources','automation_missions','automation_mission_steps',
        'automation_events','inventory_customs_status_transitions','shipping_customs_release_allocations'
    ]::text[] LOOP
        EXECUTE format('ALTER TABLE ewms.%I ENABLE ROW LEVEL SECURITY',table_name);
        EXECUTE format('DROP POLICY IF EXISTS tenant_select ON ewms.%I',table_name);
        EXECUTE format('DROP POLICY IF EXISTS tenant_modify ON ewms.%I',table_name);
        EXECUTE format('CREATE POLICY tenant_select ON ewms.%I FOR SELECT USING (tenant_id=ewms.current_tenant_id())',table_name);
        EXECUTE format('CREATE POLICY tenant_modify ON ewms.%I FOR ALL USING (tenant_id=ewms.current_tenant_id()) '
            'WITH CHECK (tenant_id=ewms.current_tenant_id())',table_name);
        EXECUTE format('ALTER TABLE ewms.%I FORCE ROW LEVEL SECURITY',table_name);
    END LOOP;
END;
$block$;

REVOKE ALL ON ALL TABLES IN SCHEMA ewms FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA ewms FROM PUBLIC;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA ewms FROM PUBLIC;

COMMENT ON TABLE ewms.inventory_customs_status_transitions IS
    'Append-only evidence bridge for balanced ledger moves between customs legal statuses; FOREIGN to DOMESTIC requires current line-level import-release evidence.';
COMMENT ON TABLE ewms.shipping_customs_release_allocations IS
    'Exact quantity coverage between a physical shipping allocation and current official UNI-PASS release evidence.';
COMMENT ON TABLE ewms.automation_events IS
    'Append-only WCS/WES/AMR event envelope; payload bytes remain in protected object storage.';
