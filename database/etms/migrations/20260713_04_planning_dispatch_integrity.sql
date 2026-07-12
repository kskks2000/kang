-- ETMS forward migration: planning, tender, dispatch, capacity, and dock
-- integrity closure. PostgreSQL 11 compatible.

-- Transaction-scoped advisory-lock helpers. Callers supply complete entity keys;
-- sorting distinct keys prevents update/swap deadlocks while hash collisions remain
-- conservative (they can only serialize unrelated work).
CREATE OR REPLACE FUNCTION etms._lock_integrity_uuid_keys_20260713(
    p_scope text,
    p_ids uuid[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    target_id uuid;
BEGIN
    IF p_scope IS NULL OR pg_catalog.btrim(p_scope) = '' THEN
        RAISE EXCEPTION 'Integrity advisory-lock scope is required'
            USING ERRCODE = '22023';
    END IF;

    FOR target_id IN
        SELECT key_row.entity_id
        FROM (
            SELECT DISTINCT source_row.entity_id
            FROM pg_catalog.unnest(
                COALESCE(p_ids, ARRAY[]::uuid[])
            ) AS source_row(entity_id)
            WHERE source_row.entity_id IS NOT NULL
        ) AS key_row
        ORDER BY key_row.entity_id
    LOOP
        PERFORM pg_catalog.pg_advisory_xact_lock(
            pg_catalog.hashtext(p_scope),
            pg_catalog.hashtext(target_id::text)
        );
    END LOOP;
END;
$function$;

CREATE OR REPLACE FUNCTION etms._lock_integrity_text_keys_20260713(
    p_scope text,
    p_keys text[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    target_key text;
BEGIN
    IF p_scope IS NULL OR pg_catalog.btrim(p_scope) = '' THEN
        RAISE EXCEPTION 'Integrity advisory-lock scope is required'
            USING ERRCODE = '22023';
    END IF;

    FOR target_key IN
        SELECT key_row.entity_key
        FROM (
            SELECT DISTINCT source_row.entity_key
            FROM pg_catalog.unnest(
                COALESCE(p_keys, ARRAY[]::text[])
            ) AS source_row(entity_key)
            WHERE source_row.entity_key IS NOT NULL
        ) AS key_row
        ORDER BY key_row.entity_key
    LOOP
        PERFORM pg_catalog.pg_advisory_xact_lock(
            pg_catalog.hashtext(p_scope),
            pg_catalog.hashtext(target_key)
        );
    END LOOP;
END;
$function$;

REVOKE ALL ON FUNCTION etms._lock_integrity_uuid_keys_20260713(text, uuid[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION etms._lock_integrity_text_keys_20260713(text, text[]) FROM PUBLIC;

-- Active shipment allocations are ceilings against their source order. A NULL
-- allocation metric is deliberately "not specified" and contributes zero only
-- to that metric. Removed rows are historical and do not consume the ceiling.
-- allocation_quantity is always interpreted in transport_orders.quantity_uom_code.
CREATE OR REPLACE FUNCTION etms.validate_shipment_order_allocation_totals()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    source_order record;
    used_percent numeric;
    used_quantity numeric;
    used_weight numeric;
    used_volume numeric;
    specified_quantity_count bigint;
    lock_ids uuid[];
BEGIN
    IF TG_OP = 'INSERT' THEN
        lock_ids := ARRAY[NEW.order_id]::uuid[];
    ELSIF TG_OP = 'UPDATE' THEN
        lock_ids := ARRAY[OLD.order_id, NEW.order_id]::uuid[];
    ELSE
        lock_ids := ARRAY[OLD.order_id]::uuid[];
    END IF;

    PERFORM etms._lock_integrity_uuid_keys_20260713(
        'etms:shipment-order-allocation', lock_ids
    );

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;

    IF NEW.removed_at IS NOT NULL THEN
        RETURN NEW;
    END IF;

    SELECT order_row.total_quantity,
           order_row.quantity_uom_code,
           order_row.total_weight_kg,
           order_row.total_volume_m3
      INTO source_order
      FROM etms.transport_orders AS order_row
     WHERE order_row.id = NEW.order_id
       AND order_row.tenant_id = NEW.tenant_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Shipment allocation source order is unavailable in the tenant'
            USING ERRCODE = '23503';
    END IF;

    SELECT COALESCE(pg_catalog.sum(link_row.allocation_percent), 0),
           COALESCE(pg_catalog.sum(link_row.allocation_quantity), 0),
           COALESCE(pg_catalog.sum(link_row.allocation_weight_kg), 0),
           COALESCE(pg_catalog.sum(link_row.allocation_volume_m3), 0),
           pg_catalog.count(link_row.allocation_quantity)
      INTO used_percent, used_quantity, used_weight, used_volume,
           specified_quantity_count
      FROM etms.shipment_orders AS link_row
     WHERE link_row.tenant_id = NEW.tenant_id
       AND link_row.order_id = NEW.order_id
       AND link_row.removed_at IS NULL
       AND link_row.id IS DISTINCT FROM NEW.id;

    used_percent := used_percent + COALESCE(NEW.allocation_percent, 0);
    used_quantity := used_quantity + COALESCE(NEW.allocation_quantity, 0);
    used_weight := used_weight + COALESCE(NEW.allocation_weight_kg, 0);
    used_volume := used_volume + COALESCE(NEW.allocation_volume_m3, 0);
    specified_quantity_count := specified_quantity_count
        + CASE WHEN NEW.allocation_quantity IS NULL THEN 0 ELSE 1 END;

    IF specified_quantity_count > 0
       AND source_order.quantity_uom_code IS NULL THEN
        RAISE EXCEPTION
            'allocation_quantity requires the source transport order quantity UOM'
            USING ERRCODE = '23514';
    END IF;
    IF used_percent > 100 THEN
        RAISE EXCEPTION 'Active shipment allocation percent exceeds 100 for the order'
            USING ERRCODE = '23514';
    END IF;
    IF used_quantity > source_order.total_quantity THEN
        RAISE EXCEPTION 'Active shipment allocation quantity exceeds the source order total'
            USING ERRCODE = '23514';
    END IF;
    IF used_weight > source_order.total_weight_kg THEN
        RAISE EXCEPTION 'Active shipment allocation weight exceeds the source order total'
            USING ERRCODE = '23514';
    END IF;
    IF used_volume > source_order.total_volume_m3 THEN
        RAISE EXCEPTION 'Active shipment allocation volume exceeds the source order total'
            USING ERRCODE = '23514';
    END IF;

    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION etms.validate_transport_order_allocation_totals()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    used_percent numeric;
    used_quantity numeric;
    used_weight numeric;
    used_volume numeric;
    specified_quantity_count bigint;
BEGIN
    PERFORM etms._lock_integrity_uuid_keys_20260713(
        'etms:shipment-order-allocation', ARRAY[NEW.id]::uuid[]
    );

    SELECT COALESCE(pg_catalog.sum(link_row.allocation_percent), 0),
           COALESCE(pg_catalog.sum(link_row.allocation_quantity), 0),
           COALESCE(pg_catalog.sum(link_row.allocation_weight_kg), 0),
           COALESCE(pg_catalog.sum(link_row.allocation_volume_m3), 0),
           pg_catalog.count(link_row.allocation_quantity)
      INTO used_percent, used_quantity, used_weight, used_volume,
           specified_quantity_count
      FROM etms.shipment_orders AS link_row
     WHERE link_row.tenant_id = NEW.tenant_id
       AND link_row.order_id = NEW.id
       AND link_row.removed_at IS NULL;

    IF specified_quantity_count > 0 AND NEW.quantity_uom_code IS NULL THEN
        RAISE EXCEPTION
            'An order with active quantity allocations must retain a quantity UOM'
            USING ERRCODE = '23514';
    END IF;
    IF specified_quantity_count > 0
       AND OLD.quantity_uom_code IS NOT NULL
       AND NEW.quantity_uom_code IS DISTINCT FROM OLD.quantity_uom_code THEN
        RAISE EXCEPTION
            'The source order quantity UOM cannot change while quantity allocations are active'
            USING ERRCODE = '23514';
    END IF;
    IF used_percent > 100 THEN
        RAISE EXCEPTION 'Active shipment allocation percent exceeds 100 for the order'
            USING ERRCODE = '23514';
    END IF;
    IF used_quantity > NEW.total_quantity THEN
        RAISE EXCEPTION 'Order quantity cannot be reduced below active shipment allocations'
            USING ERRCODE = '23514';
    END IF;
    IF used_weight > NEW.total_weight_kg THEN
        RAISE EXCEPTION 'Order weight cannot be reduced below active shipment allocations'
            USING ERRCODE = '23514';
    END IF;
    IF used_volume > NEW.total_volume_m3 THEN
        RAISE EXCEPTION 'Order volume cannot be reduced below active shipment allocations'
            USING ERRCODE = '23514';
    END IF;

    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_validate_shipment_order_allocation_totals
    ON etms.shipment_orders;
CREATE TRIGGER trg_validate_shipment_order_allocation_totals
    BEFORE INSERT OR UPDATE OR DELETE ON etms.shipment_orders
    FOR EACH ROW EXECUTE PROCEDURE etms.validate_shipment_order_allocation_totals();

DROP TRIGGER IF EXISTS trg_validate_transport_order_allocation_totals
    ON etms.transport_orders;
CREATE TRIGGER trg_validate_transport_order_allocation_totals
    BEFORE UPDATE OF total_quantity, quantity_uom_code,
                     total_weight_kg, total_volume_m3
    ON etms.transport_orders
    FOR EACH ROW EXECUTE PROCEDURE etms.validate_transport_order_allocation_totals();

REVOKE ALL ON FUNCTION etms.validate_shipment_order_allocation_totals() FROM PUBLIC;
REVOKE ALL ON FUNCTION etms.validate_transport_order_allocation_totals() FROM PUBLIC;

CREATE INDEX IF NOT EXISTS ix_shipment_orders_active_order_allocations
    ON etms.shipment_orders (tenant_id, order_id)
    WHERE removed_at IS NULL;

COMMENT ON COLUMN etms.shipment_orders.allocation_quantity IS
    'Optional active allocation in the source transport order quantity_uom_code; NULL is unspecified, and removed_at rows do not consume the order ceiling.';

-- Pallet capacity is nullable: NULL means that dimension is not bounded. Exact
-- nonnegative checks cover every run capacity dimension.
ALTER TABLE etms.transport_runs
    ADD COLUMN IF NOT EXISTS capacity_pallets numeric(20,3);

DO $migration$
DECLARE
    actual_type text;
BEGIN
    SELECT pg_catalog.format_type(attribute_row.atttypid, attribute_row.atttypmod)
      INTO actual_type
      FROM pg_catalog.pg_attribute AS attribute_row
     WHERE attribute_row.attrelid = 'etms.transport_runs'::regclass
       AND attribute_row.attname = 'capacity_pallets'
       AND NOT attribute_row.attisdropped;

    IF actual_type IS DISTINCT FROM 'numeric(20,3)' THEN
        RAISE EXCEPTION
            'etms.transport_runs.capacity_pallets has incompatible type %', actual_type;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_constraint AS constraint_row
        WHERE constraint_row.conrelid = 'etms.transport_runs'::regclass
          AND constraint_row.conname = 'ck_transport_runs_capacities_nonnegative'
          AND constraint_row.contype = 'c'
    ) THEN
        ALTER TABLE etms.transport_runs
            ADD CONSTRAINT ck_transport_runs_capacities_nonnegative
            CHECK (
                (capacity_weight_kg IS NULL OR capacity_weight_kg >= 0) AND
                (capacity_volume_m3 IS NULL OR capacity_volume_m3 >= 0) AND
                (capacity_pallets IS NULL OR capacity_pallets >= 0)
            ) NOT VALID;
    END IF;
END;
$migration$;

ALTER TABLE etms.transport_runs
    VALIDATE CONSTRAINT ck_transport_runs_capacities_nonnegative;

COMMENT ON COLUMN etms.transport_runs.capacity_pallets IS
    'Maximum reservable pallet quantity for the run; NULL means no pallet-dimension ceiling.';

-- Active reservations exclude terminal statuses and rows whose expiry is at or
-- before statement time, even if their status still says RESERVED.
CREATE OR REPLACE FUNCTION etms.validate_capacity_reservation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    run_row record;
    used_weight numeric;
    used_volume numeric;
    used_pallets numeric;
    validation_time timestamptz := pg_catalog.statement_timestamp();
    lock_ids uuid[];
BEGIN
    IF TG_OP = 'INSERT' THEN
        lock_ids := ARRAY[NEW.run_id]::uuid[];
    ELSE
        lock_ids := ARRAY[OLD.run_id, NEW.run_id]::uuid[];
    END IF;

    PERFORM etms._lock_integrity_uuid_keys_20260713(
        'etms:run-capacity-reservation', lock_ids
    );

    IF NEW.status IN ('RELEASED', 'CANCELLED', 'EXPIRED')
       OR (NEW.expires_at IS NOT NULL AND NEW.expires_at <= validation_time) THEN
        RETURN NEW;
    END IF;

    -- Do not take a row lock here. A concurrent transport_runs capacity update
    -- already owns that row before its trigger runs; the shared advisory key is
    -- the serialization mechanism and avoids a row/advisory lock inversion.
    SELECT run_header.capacity_weight_kg,
           run_header.capacity_volume_m3,
           run_header.capacity_pallets
      INTO run_row
      FROM etms.transport_runs AS run_header
     WHERE run_header.id = NEW.run_id
       AND run_header.tenant_id = NEW.tenant_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Capacity reservation run is unavailable in the tenant'
            USING ERRCODE = '23503';
    END IF;

    SELECT COALESCE(pg_catalog.sum(reservation_row.reserved_weight_kg), 0),
           COALESCE(pg_catalog.sum(reservation_row.reserved_volume_m3), 0),
           COALESCE(pg_catalog.sum(reservation_row.reserved_pallets), 0)
      INTO used_weight, used_volume, used_pallets
      FROM etms.capacity_reservations AS reservation_row
     WHERE reservation_row.tenant_id = NEW.tenant_id
       AND reservation_row.run_id = NEW.run_id
       AND reservation_row.id IS DISTINCT FROM NEW.id
       AND reservation_row.status NOT IN ('RELEASED', 'CANCELLED', 'EXPIRED')
       AND (
           reservation_row.expires_at IS NULL
           OR reservation_row.expires_at > validation_time
       );

    used_weight := used_weight + NEW.reserved_weight_kg;
    used_volume := used_volume + NEW.reserved_volume_m3;
    used_pallets := used_pallets + NEW.reserved_pallets;

    IF run_row.capacity_weight_kg IS NOT NULL
       AND used_weight > run_row.capacity_weight_kg THEN
        RAISE EXCEPTION 'Run weight capacity exceeded by active reservations'
            USING ERRCODE = '23514';
    END IF;
    IF run_row.capacity_volume_m3 IS NOT NULL
       AND used_volume > run_row.capacity_volume_m3 THEN
        RAISE EXCEPTION 'Run volume capacity exceeded by active reservations'
            USING ERRCODE = '23514';
    END IF;
    IF run_row.capacity_pallets IS NOT NULL
       AND used_pallets > run_row.capacity_pallets THEN
        RAISE EXCEPTION 'Run pallet capacity exceeded by active reservations'
            USING ERRCODE = '23514';
    END IF;

    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION etms.validate_transport_run_capacity()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    used_weight numeric;
    used_volume numeric;
    used_pallets numeric;
    validation_time timestamptz := pg_catalog.statement_timestamp();
BEGIN
    PERFORM etms._lock_integrity_uuid_keys_20260713(
        'etms:run-capacity-reservation', ARRAY[NEW.id]::uuid[]
    );

    SELECT COALESCE(pg_catalog.sum(reservation_row.reserved_weight_kg), 0),
           COALESCE(pg_catalog.sum(reservation_row.reserved_volume_m3), 0),
           COALESCE(pg_catalog.sum(reservation_row.reserved_pallets), 0)
      INTO used_weight, used_volume, used_pallets
      FROM etms.capacity_reservations AS reservation_row
     WHERE reservation_row.tenant_id = NEW.tenant_id
       AND reservation_row.run_id = NEW.id
       AND reservation_row.status NOT IN ('RELEASED', 'CANCELLED', 'EXPIRED')
       AND (
           reservation_row.expires_at IS NULL
           OR reservation_row.expires_at > validation_time
       );

    IF NEW.capacity_weight_kg IS NOT NULL
       AND used_weight > NEW.capacity_weight_kg THEN
        RAISE EXCEPTION 'Run weight capacity cannot be reduced below active reservations'
            USING ERRCODE = '23514';
    END IF;
    IF NEW.capacity_volume_m3 IS NOT NULL
       AND used_volume > NEW.capacity_volume_m3 THEN
        RAISE EXCEPTION 'Run volume capacity cannot be reduced below active reservations'
            USING ERRCODE = '23514';
    END IF;
    IF NEW.capacity_pallets IS NOT NULL
       AND used_pallets > NEW.capacity_pallets THEN
        RAISE EXCEPTION 'Run pallet capacity cannot be reduced below active reservations'
            USING ERRCODE = '23514';
    END IF;

    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_validate_capacity_reservation
    ON etms.capacity_reservations;
CREATE TRIGGER trg_validate_capacity_reservation
    BEFORE INSERT OR UPDATE ON etms.capacity_reservations
    FOR EACH ROW EXECUTE PROCEDURE etms.validate_capacity_reservation();

DROP TRIGGER IF EXISTS trg_validate_transport_run_capacity
    ON etms.transport_runs;
CREATE TRIGGER trg_validate_transport_run_capacity
    BEFORE UPDATE OF capacity_weight_kg, capacity_volume_m3, capacity_pallets
    ON etms.transport_runs
    FOR EACH ROW EXECUTE PROCEDURE etms.validate_transport_run_capacity();

REVOKE ALL ON FUNCTION etms.validate_capacity_reservation() FROM PUBLIC;
REVOKE ALL ON FUNCTION etms.validate_transport_run_capacity() FROM PUBLIC;

CREATE INDEX IF NOT EXISTS ix_capacity_reservations_active_run_expiry
    ON etms.capacity_reservations (tenant_id, run_id, expires_at)
    WHERE status NOT IN ('RELEASED', 'CANCELLED', 'EXPIRED');

-- Partial unique indexes are only sound when an unrecognised status cannot be
-- used as a shadow active state. These exact sets contain every indexed active
-- state plus explicit terminal states. Dispatch already has the exact validated
-- ck_dispatch_orders_status_v03 constraint from the preceding migration.
DO $migration$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_constraint AS constraint_row
        WHERE constraint_row.conrelid = 'etms.capacity_reservations'::regclass
          AND constraint_row.conname = 'ck_capacity_reservations_status'
          AND constraint_row.contype = 'c'
    ) THEN
        ALTER TABLE etms.capacity_reservations
            ADD CONSTRAINT ck_capacity_reservations_status
            CHECK (status IN (
                'RESERVED', 'CONFIRMED', 'CONSUMED',
                'RELEASED', 'CANCELLED', 'EXPIRED'
            )) NOT VALID;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_constraint AS constraint_row
        WHERE constraint_row.conrelid = 'etms.run_carrier_assignments'::regclass
          AND constraint_row.conname = 'ck_run_carrier_assignment_status'
          AND constraint_row.contype = 'c'
    ) THEN
        ALTER TABLE etms.run_carrier_assignments
            ADD CONSTRAINT ck_run_carrier_assignment_status
            CHECK (status IN (
                'PROPOSED', 'ASSIGNED', 'ACCEPTED', 'ACTIVE',
                'REJECTED', 'RELEASED', 'COMPLETED', 'SUPERSEDED',
                'CANCELLED', 'EXPIRED'
            )) NOT VALID;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_constraint AS constraint_row
        WHERE constraint_row.conrelid = 'etms.run_driver_assignments'::regclass
          AND constraint_row.conname = 'ck_run_driver_assignment_status'
          AND constraint_row.contype = 'c'
    ) THEN
        ALTER TABLE etms.run_driver_assignments
            ADD CONSTRAINT ck_run_driver_assignment_status
            CHECK (status IN (
                'ASSIGNED', 'ACCEPTED', 'ACTIVE',
                'REJECTED', 'RELEASED', 'COMPLETED', 'SUPERSEDED',
                'CANCELLED', 'EXPIRED'
            )) NOT VALID;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_constraint AS constraint_row
        WHERE constraint_row.conrelid = 'etms.run_equipment_assignments'::regclass
          AND constraint_row.conname = 'ck_run_equipment_assignment_status'
          AND constraint_row.contype = 'c'
    ) THEN
        ALTER TABLE etms.run_equipment_assignments
            ADD CONSTRAINT ck_run_equipment_assignment_status
            CHECK (status IN (
                'ASSIGNED', 'ACCEPTED', 'ACTIVE',
                'REJECTED', 'RELEASED', 'COMPLETED', 'SUPERSEDED',
                'CANCELLED', 'EXPIRED'
            )) NOT VALID;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_constraint AS constraint_row
        WHERE constraint_row.conrelid = 'etms.run_equipment_assignments'::regclass
          AND constraint_row.conname = 'ck_run_equipment_assignment_role'
          AND constraint_row.contype = 'c'
    ) THEN
        ALTER TABLE etms.run_equipment_assignments
            ADD CONSTRAINT ck_run_equipment_assignment_role
            CHECK (assignment_role IN ('PRIMARY', 'SECONDARY', 'SPARE'))
            NOT VALID;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_constraint AS constraint_row
        WHERE constraint_row.conrelid = 'etms.tenders'::regclass
          AND constraint_row.conname = 'ck_tenders_status'
          AND constraint_row.contype = 'c'
    ) THEN
        ALTER TABLE etms.tenders
            ADD CONSTRAINT ck_tenders_status
            CHECK (status IN (
                'DRAFT', 'OPEN', 'IN_PROGRESS', 'AWARDED', 'ACCEPTED',
                'CLOSED', 'COMPLETED', 'NO_AWARD', 'WITHDRAWN',
                'CANCELLED', 'EXPIRED', 'FAILED'
            )) NOT VALID;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_constraint AS constraint_row
        WHERE constraint_row.conrelid = 'etms.tender_awards'::regclass
          AND constraint_row.conname = 'ck_tender_awards_status'
          AND constraint_row.contype = 'c'
    ) THEN
        ALTER TABLE etms.tender_awards
            ADD CONSTRAINT ck_tender_awards_status
            CHECK (status IN (
                'AWARDED', 'ACCEPTED', 'REJECTED',
                'WITHDRAWN', 'CANCELLED', 'EXPIRED'
            )) NOT VALID;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_constraint AS constraint_row
        WHERE constraint_row.conrelid = 'etms.tender_awards'::regclass
          AND constraint_row.conname = 'ck_tender_awards_withdrawal_state'
          AND constraint_row.contype = 'c'
    ) THEN
        ALTER TABLE etms.tender_awards
            ADD CONSTRAINT ck_tender_awards_withdrawal_state
            CHECK (
                (status = 'WITHDRAWN' AND withdrawn_at IS NOT NULL)
                OR
                (status <> 'WITHDRAWN' AND withdrawn_at IS NULL)
            ) NOT VALID;
    END IF;

END;
$migration$;

ALTER TABLE etms.capacity_reservations
    VALIDATE CONSTRAINT ck_capacity_reservations_status;
ALTER TABLE etms.run_carrier_assignments
    VALIDATE CONSTRAINT ck_run_carrier_assignment_status;
ALTER TABLE etms.run_driver_assignments
    VALIDATE CONSTRAINT ck_run_driver_assignment_status;
ALTER TABLE etms.run_equipment_assignments
    VALIDATE CONSTRAINT ck_run_equipment_assignment_status;
ALTER TABLE etms.run_equipment_assignments
    VALIDATE CONSTRAINT ck_run_equipment_assignment_role;
ALTER TABLE etms.tenders
    VALIDATE CONSTRAINT ck_tenders_status;
ALTER TABLE etms.tender_awards
    VALIDATE CONSTRAINT ck_tender_awards_status;
ALTER TABLE etms.tender_awards
    VALIDATE CONSTRAINT ck_tender_awards_withdrawal_state;

-- Validate the complete tender path after every mutable link. AFTER triggers let
-- a single assertion inspect the proposed row state, while the sorted tender
-- advisory keys serialize concurrent parent/child changes without row-lock
-- inversion.
CREATE OR REPLACE FUNCTION etms._assert_tender_chain_integrity_20260713(
    p_tender_ids uuid[],
    p_require_complete_award boolean
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
BEGIN
    PERFORM etms._lock_integrity_uuid_keys_20260713(
        'etms:tender-chain', p_tender_ids
    );

    IF pg_catalog.array_length(p_tender_ids, 1) IS NULL THEN
        RETURN;
    END IF;

    -- A response inherits round, tender, tenant, and carrier from its offer path.
    IF EXISTS (
        SELECT 1
        FROM etms.tender_responses AS response_row
        JOIN etms.tender_offers AS offer_row
          ON offer_row.id = response_row.tender_offer_id
        JOIN etms.tender_rounds AS round_row
          ON round_row.id = offer_row.tender_round_id
        JOIN etms.tenders AS tender_row
          ON tender_row.id = round_row.tender_id
        WHERE round_row.tender_id = ANY (p_tender_ids)
          AND offer_row.tenant_id IS DISTINCT FROM tender_row.tenant_id
    ) THEN
        RAISE EXCEPTION
            'Tender response offer/round/tender path crosses tenant scope'
            USING ERRCODE = '23514';
    END IF;

    -- Offers without a response still must belong to the round tender tenant.
    IF EXISTS (
        SELECT 1
        FROM etms.tender_offers AS offer_row
        JOIN etms.tender_rounds AS round_row
          ON round_row.id = offer_row.tender_round_id
        JOIN etms.tenders AS tender_row
          ON tender_row.id = round_row.tender_id
        WHERE round_row.tender_id = ANY (p_tender_ids)
          AND offer_row.tenant_id IS DISTINCT FROM tender_row.tenant_id
    ) THEN
        RAISE EXCEPTION 'Tender offer does not belong to the round tender tenant'
            USING ERRCODE = '23514';
    END IF;

    -- If an award cites a response, both the response tender and offered carrier
    -- are exact: a response from another round/tender/carrier cannot be awarded.
    IF EXISTS (
        SELECT 1
        FROM etms.tender_awards AS award_row
        JOIN etms.tenders AS tender_row
          ON tender_row.id = award_row.tender_id
        LEFT JOIN etms.tender_responses AS response_row
          ON response_row.id = award_row.tender_response_id
        LEFT JOIN etms.tender_offers AS offer_row
          ON offer_row.id = response_row.tender_offer_id
        LEFT JOIN etms.tender_rounds AS round_row
          ON round_row.id = offer_row.tender_round_id
        WHERE award_row.tender_id = ANY (p_tender_ids)
          AND (
              award_row.tenant_id IS DISTINCT FROM tender_row.tenant_id
              OR (
                  award_row.tender_response_id IS NOT NULL
                  AND (
                      response_row.id IS NULL
                      OR offer_row.id IS NULL
                      OR round_row.id IS NULL
                      OR round_row.tender_id IS DISTINCT FROM award_row.tender_id
                      OR offer_row.tenant_id IS DISTINCT FROM award_row.tenant_id
                      OR offer_row.carrier_id IS DISTINCT FROM award_row.carrier_id
                      OR response_row.response_type NOT IN ('ACCEPT', 'COUNTER')
                  )
              )
          )
    ) THEN
        RAISE EXCEPTION
            'Tender award response, carrier, tender, or tenant chain is inconsistent'
            USING ERRCODE = '23514';
    END IF;

    -- When the tender header declares its winner, every live award agrees with it.
    IF EXISTS (
        SELECT 1
        FROM etms.tenders AS tender_row
        JOIN etms.tender_awards AS award_row
          ON award_row.tender_id = tender_row.id
        WHERE tender_row.id = ANY (p_tender_ids)
          AND tender_row.awarded_carrier_id IS NOT NULL
          AND award_row.status IN ('AWARDED', 'ACCEPTED')
          AND award_row.withdrawn_at IS NULL
          AND award_row.carrier_id IS DISTINCT FROM tender_row.awarded_carrier_id
    ) THEN
        RAISE EXCEPTION 'Tender header winner and active tender award carrier differ'
            USING ERRCODE = '23514';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM etms.run_carrier_assignments AS assignment_row
        JOIN etms.tenders AS tender_row
          ON tender_row.id = assignment_row.awarded_tender_id
        WHERE assignment_row.awarded_tender_id = ANY (p_tender_ids)
          AND (
              assignment_row.tenant_id IS DISTINCT FROM tender_row.tenant_id
              OR tender_row.run_id IS NULL
              OR assignment_row.run_id IS DISTINCT FROM tender_row.run_id
              OR (
                  tender_row.awarded_carrier_id IS NOT NULL
                  AND assignment_row.carrier_id
                      IS DISTINCT FROM tender_row.awarded_carrier_id
              )
              OR EXISTS (
                  SELECT 1
                  FROM etms.tender_awards AS live_award
                  WHERE live_award.tender_id = tender_row.id
                    AND live_award.status IN ('AWARDED', 'ACCEPTED')
                    AND live_award.withdrawn_at IS NULL
                    AND live_award.carrier_id
                        IS DISTINCT FROM assignment_row.carrier_id
              )
          )
    ) THEN
        RAISE EXCEPTION
            'Run carrier assignment awarded tender must match tenant, run, and carrier'
            USING ERRCODE = '23514';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM etms.dispatch_orders AS dispatch_row
        JOIN etms.tender_awards AS award_row
          ON award_row.id = dispatch_row.tender_award_id
        JOIN etms.tenders AS tender_row
          ON tender_row.id = award_row.tender_id
        WHERE award_row.tender_id = ANY (p_tender_ids)
          AND (
              dispatch_row.tenant_id IS DISTINCT FROM award_row.tenant_id
              OR dispatch_row.tenant_id IS DISTINCT FROM tender_row.tenant_id
              OR dispatch_row.carrier_id IS DISTINCT FROM award_row.carrier_id
              OR tender_row.run_id IS NULL
              OR dispatch_row.run_id IS DISTINCT FROM tender_row.run_id
              OR (
                  dispatch_row.status NOT IN (
                      'REJECTED', 'COMPLETED', 'CANCELLED', 'EXPIRED'
                  )
                  AND (
                      award_row.status NOT IN ('AWARDED', 'ACCEPTED')
                      OR award_row.withdrawn_at IS NOT NULL
                      OR tender_row.awarded_carrier_id
                          IS DISTINCT FROM award_row.carrier_id
                      OR tender_row.awarded_amount
                          IS DISTINCT FROM award_row.award_amount
                      OR tender_row.awarded_at IS NULL
                  )
              )
          )
    ) THEN
        RAISE EXCEPTION
            'Dispatch run/carrier/tender award chain is inconsistent'
            USING ERRCODE = '23514';
    END IF;

    IF p_require_complete_award AND EXISTS (
        SELECT 1
        FROM etms.tenders AS tender_row
        LEFT JOIN etms.tender_awards AS live_award
          ON live_award.tender_id = tender_row.id
         AND live_award.status IN ('AWARDED', 'ACCEPTED')
         AND live_award.withdrawn_at IS NULL
        WHERE tender_row.id = ANY (p_tender_ids)
        GROUP BY tender_row.id,
                 tender_row.status,
                 tender_row.awarded_carrier_id,
                 tender_row.awarded_amount,
                 tender_row.awarded_at
        HAVING
            (
                tender_row.status IN ('AWARDED', 'ACCEPTED')
                OR tender_row.awarded_carrier_id IS NOT NULL
                OR tender_row.awarded_amount IS NOT NULL
                OR tender_row.awarded_at IS NOT NULL
                OR pg_catalog.count(live_award.id) > 0
                OR EXISTS (
                    SELECT 1
                    FROM etms.run_carrier_assignments AS assignment_row
                    WHERE assignment_row.awarded_tender_id = tender_row.id
                      AND assignment_row.status IN (
                          'PROPOSED', 'ASSIGNED', 'ACCEPTED', 'ACTIVE'
                      )
                )
            )
            AND (
                pg_catalog.count(live_award.id) <> 1
                OR tender_row.awarded_carrier_id IS NULL
                OR tender_row.awarded_amount IS NULL
                OR tender_row.awarded_at IS NULL
                OR pg_catalog.min(live_award.carrier_id::text)::uuid
                    IS DISTINCT FROM tender_row.awarded_carrier_id
                OR pg_catalog.min(live_award.award_amount)
                    IS DISTINCT FROM tender_row.awarded_amount
                OR EXISTS (
                    SELECT 1
                    FROM etms.run_carrier_assignments AS assignment_row
                    WHERE assignment_row.awarded_tender_id = tender_row.id
                      AND assignment_row.status IN (
                          'PROPOSED', 'ASSIGNED', 'ACCEPTED', 'ACTIVE'
                      )
                      AND assignment_row.carrier_id
                          IS DISTINCT FROM tender_row.awarded_carrier_id
                )
            )
    ) THEN
        RAISE EXCEPTION
            'Winning tender header, active award, and awarded-tender assignments must be complete and agree at transaction end'
            USING ERRCODE = '23514';
    END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION etms.validate_tender_chain_mutation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    tender_ids uuid[] := ARRAY[]::uuid[];
    parent_ids uuid[];
BEGIN
    IF TG_TABLE_NAME = 'tenders' THEN
        tender_ids := ARRAY[NEW.id]::uuid[];

    ELSIF TG_TABLE_NAME = 'tender_rounds' THEN
        IF TG_OP = 'UPDATE' THEN
            tender_ids := ARRAY[OLD.tender_id, NEW.tender_id]::uuid[];
        ELSE
            tender_ids := ARRAY[NEW.tender_id]::uuid[];
        END IF;

    ELSIF TG_TABLE_NAME = 'tender_offers' THEN
        IF TG_OP = 'UPDATE' THEN
            parent_ids := ARRAY[OLD.tender_round_id, NEW.tender_round_id]::uuid[];
        ELSE
            parent_ids := ARRAY[NEW.tender_round_id]::uuid[];
        END IF;
        SELECT COALESCE(pg_catalog.array_agg(DISTINCT round_row.tender_id), ARRAY[]::uuid[])
          INTO tender_ids
          FROM etms.tender_rounds AS round_row
         WHERE round_row.id = ANY (parent_ids);

    ELSIF TG_TABLE_NAME = 'tender_responses' THEN
        IF TG_OP = 'UPDATE' THEN
            parent_ids := ARRAY[OLD.tender_offer_id, NEW.tender_offer_id]::uuid[];
        ELSE
            parent_ids := ARRAY[NEW.tender_offer_id]::uuid[];
        END IF;
        SELECT COALESCE(pg_catalog.array_agg(DISTINCT round_row.tender_id), ARRAY[]::uuid[])
          INTO tender_ids
          FROM etms.tender_offers AS offer_row
          JOIN etms.tender_rounds AS round_row
            ON round_row.id = offer_row.tender_round_id
         WHERE offer_row.id = ANY (parent_ids);

    ELSIF TG_TABLE_NAME = 'tender_awards' THEN
        IF TG_OP = 'UPDATE' THEN
            tender_ids := ARRAY[OLD.tender_id, NEW.tender_id]::uuid[];
        ELSE
            tender_ids := ARRAY[NEW.tender_id]::uuid[];
        END IF;

    ELSIF TG_TABLE_NAME = 'run_carrier_assignments' THEN
        IF TG_OP = 'UPDATE' THEN
            tender_ids := ARRAY[OLD.awarded_tender_id, NEW.awarded_tender_id]::uuid[];
        ELSE
            tender_ids := ARRAY[NEW.awarded_tender_id]::uuid[];
        END IF;

    ELSIF TG_TABLE_NAME = 'dispatch_orders' THEN
        IF TG_OP = 'UPDATE' THEN
            parent_ids := ARRAY[OLD.tender_award_id, NEW.tender_award_id]::uuid[];
        ELSE
            parent_ids := ARRAY[NEW.tender_award_id]::uuid[];
        END IF;
        SELECT COALESCE(pg_catalog.array_agg(DISTINCT award_row.tender_id), ARRAY[]::uuid[])
          INTO tender_ids
          FROM etms.tender_awards AS award_row
         WHERE award_row.id = ANY (parent_ids);
    ELSE
        RAISE EXCEPTION 'Unsupported tender-chain trigger table %', TG_TABLE_NAME
            USING ERRCODE = '0A000';
    END IF;

    PERFORM etms._assert_tender_chain_integrity_20260713(tender_ids, false);
    RETURN NEW;
END;
$function$;

-- The winner header and active award are a transaction-final invariant. Keeping
-- this check deferred permits either write order (award then header, or header
-- then award) while rejecting incomplete state at COMMIT / SET CONSTRAINTS.
CREATE OR REPLACE FUNCTION etms.validate_tender_chain_completion()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    tender_ids uuid[] := ARRAY[]::uuid[];
    award_ids uuid[];
BEGIN
    IF TG_TABLE_NAME = 'tenders' THEN
        tender_ids := ARRAY[NEW.id]::uuid[];

    ELSIF TG_TABLE_NAME = 'tender_awards' THEN
        IF TG_OP = 'DELETE' THEN
            tender_ids := ARRAY[OLD.tender_id]::uuid[];
        ELSIF TG_OP = 'UPDATE' THEN
            tender_ids := ARRAY[OLD.tender_id, NEW.tender_id]::uuid[];
        ELSE
            tender_ids := ARRAY[NEW.tender_id]::uuid[];
        END IF;

    ELSIF TG_TABLE_NAME = 'run_carrier_assignments' THEN
        IF TG_OP = 'DELETE' THEN
            tender_ids := ARRAY[OLD.awarded_tender_id]::uuid[];
        ELSIF TG_OP = 'UPDATE' THEN
            tender_ids := ARRAY[
                OLD.awarded_tender_id, NEW.awarded_tender_id
            ]::uuid[];
        ELSE
            tender_ids := ARRAY[NEW.awarded_tender_id]::uuid[];
        END IF;

    ELSIF TG_TABLE_NAME = 'dispatch_orders' THEN
        IF TG_OP = 'UPDATE' THEN
            award_ids := ARRAY[
                OLD.tender_award_id, NEW.tender_award_id
            ]::uuid[];
        ELSE
            award_ids := ARRAY[NEW.tender_award_id]::uuid[];
        END IF;
        SELECT COALESCE(
                   pg_catalog.array_agg(DISTINCT award_row.tender_id),
                   ARRAY[]::uuid[]
               )
          INTO tender_ids
          FROM etms.tender_awards AS award_row
         WHERE award_row.id = ANY (award_ids);
    ELSE
        RAISE EXCEPTION 'Unsupported deferred tender-chain table %', TG_TABLE_NAME
            USING ERRCODE = '0A000';
    END IF;

    PERFORM etms._assert_tender_chain_integrity_20260713(tender_ids, true);

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_validate_tender_chain ON etms.tenders;
CREATE TRIGGER trg_validate_tender_chain
    AFTER INSERT OR UPDATE OF tenant_id, run_id, status,
                              awarded_carrier_id, awarded_amount, awarded_at
    ON etms.tenders
    FOR EACH ROW EXECUTE PROCEDURE etms.validate_tender_chain_mutation();

DROP TRIGGER IF EXISTS trg_validate_tender_chain ON etms.tender_rounds;
CREATE TRIGGER trg_validate_tender_chain
    AFTER INSERT OR UPDATE OF tender_id ON etms.tender_rounds
    FOR EACH ROW EXECUTE PROCEDURE etms.validate_tender_chain_mutation();

DROP TRIGGER IF EXISTS trg_validate_tender_chain ON etms.tender_offers;
CREATE TRIGGER trg_validate_tender_chain
    AFTER INSERT OR UPDATE OF tenant_id, tender_round_id, carrier_id
    ON etms.tender_offers
    FOR EACH ROW EXECUTE PROCEDURE etms.validate_tender_chain_mutation();

DROP TRIGGER IF EXISTS trg_validate_tender_chain ON etms.tender_responses;
CREATE TRIGGER trg_validate_tender_chain
    AFTER INSERT OR UPDATE OF tender_offer_id, response_type
    ON etms.tender_responses
    FOR EACH ROW EXECUTE PROCEDURE etms.validate_tender_chain_mutation();

DROP TRIGGER IF EXISTS trg_validate_tender_chain ON etms.tender_awards;
CREATE TRIGGER trg_validate_tender_chain
    AFTER INSERT OR UPDATE OF tenant_id, tender_id, tender_response_id,
                              carrier_id, status, withdrawn_at
    ON etms.tender_awards
    FOR EACH ROW EXECUTE PROCEDURE etms.validate_tender_chain_mutation();

DROP TRIGGER IF EXISTS trg_validate_tender_chain ON etms.run_carrier_assignments;
CREATE TRIGGER trg_validate_tender_chain
    AFTER INSERT OR UPDATE OF tenant_id, run_id, carrier_id, awarded_tender_id
    ON etms.run_carrier_assignments
    FOR EACH ROW EXECUTE PROCEDURE etms.validate_tender_chain_mutation();

DROP TRIGGER IF EXISTS trg_validate_tender_chain ON etms.dispatch_orders;
CREATE TRIGGER trg_validate_tender_chain
    AFTER INSERT OR UPDATE OF tenant_id, run_id, carrier_id, tender_award_id
    ON etms.dispatch_orders
    FOR EACH ROW EXECUTE PROCEDURE etms.validate_tender_chain_mutation();

DROP TRIGGER IF EXISTS trg_validate_tender_chain_completion ON etms.tenders;
CREATE CONSTRAINT TRIGGER trg_validate_tender_chain_completion
    AFTER INSERT OR UPDATE ON etms.tenders
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE PROCEDURE etms.validate_tender_chain_completion();

DROP TRIGGER IF EXISTS trg_validate_tender_chain_completion ON etms.tender_awards;
CREATE CONSTRAINT TRIGGER trg_validate_tender_chain_completion
    AFTER INSERT OR UPDATE OR DELETE ON etms.tender_awards
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE PROCEDURE etms.validate_tender_chain_completion();

DROP TRIGGER IF EXISTS trg_validate_tender_chain_completion
    ON etms.run_carrier_assignments;
CREATE CONSTRAINT TRIGGER trg_validate_tender_chain_completion
    AFTER INSERT OR UPDATE OR DELETE ON etms.run_carrier_assignments
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE PROCEDURE etms.validate_tender_chain_completion();

DROP TRIGGER IF EXISTS trg_validate_tender_chain_completion ON etms.dispatch_orders;
CREATE CONSTRAINT TRIGGER trg_validate_tender_chain_completion
    AFTER INSERT OR UPDATE ON etms.dispatch_orders
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE PROCEDURE etms.validate_tender_chain_completion();

REVOKE ALL ON FUNCTION etms._assert_tender_chain_integrity_20260713(uuid[], boolean)
    FROM PUBLIC;
REVOKE ALL ON FUNCTION etms.validate_tender_chain_mutation() FROM PUBLIC;
REVOKE ALL ON FUNCTION etms.validate_tender_chain_completion() FROM PUBLIC;

CREATE INDEX IF NOT EXISTS ix_tender_rounds_tender_chain
    ON etms.tender_rounds (tender_id, id);
CREATE INDEX IF NOT EXISTS ix_tender_responses_offer_chain
    ON etms.tender_responses (tender_offer_id, id);
CREATE INDEX IF NOT EXISTS ix_tender_awards_response_chain
    ON etms.tender_awards (tender_response_id, tender_id, carrier_id)
    WHERE tender_response_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_run_carrier_assignments_tender_chain
    ON etms.run_carrier_assignments (awarded_tender_id, run_id, carrier_id)
    WHERE awarded_tender_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_dispatch_orders_tender_chain
    ON etms.dispatch_orders (tender_award_id, run_id, carrier_id)
    WHERE tender_award_id IS NOT NULL;

-- Lock both dock and vehicle keys, in a deterministic shared order, before
-- checking either resource. Updates also lock the old resources so moving or
-- cancelling an appointment serializes correctly with concurrent inserts.
CREATE OR REPLACE FUNCTION etms.prevent_dock_appointment_overlap()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    resource_keys text[];
BEGIN
    resource_keys := ARRAY[
        CASE WHEN NEW.dock_id IS NULL THEN NULL
             ELSE 'dock:' || NEW.dock_id::text END,
        CASE WHEN NEW.vehicle_id IS NULL THEN NULL
             ELSE 'vehicle:' || NEW.vehicle_id::text END
    ]::text[];

    IF TG_OP = 'UPDATE' THEN
        resource_keys := resource_keys || ARRAY[
            CASE WHEN OLD.dock_id IS NULL THEN NULL
                 ELSE 'dock:' || OLD.dock_id::text END,
            CASE WHEN OLD.vehicle_id IS NULL THEN NULL
                 ELSE 'vehicle:' || OLD.vehicle_id::text END
        ]::text[];
    END IF;

    PERFORM etms._lock_integrity_text_keys_20260713(
        'etms:dock-appointment-overlap', resource_keys
    );

    IF NEW.status IN ('CANCELLED', 'REJECTED') THEN
        RETURN NEW;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM etms.dock_appointments AS existing_row
        WHERE existing_row.tenant_id = NEW.tenant_id
          AND existing_row.id IS DISTINCT FROM NEW.id
          AND existing_row.status NOT IN ('CANCELLED', 'REJECTED')
          AND (
              (NEW.dock_id IS NOT NULL AND existing_row.dock_id = NEW.dock_id)
              OR
              (NEW.vehicle_id IS NOT NULL AND existing_row.vehicle_id = NEW.vehicle_id)
          )
          AND existing_row.scheduled_start_at < NEW.scheduled_end_at
          AND NEW.scheduled_start_at < existing_row.scheduled_end_at
    ) THEN
        RAISE EXCEPTION
            'Dock or vehicle appointment period overlaps an active appointment'
            USING ERRCODE = '23P01';
    END IF;

    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_prevent_dock_appointment_overlap
    ON etms.dock_appointments;
CREATE TRIGGER trg_prevent_dock_appointment_overlap
    BEFORE INSERT OR UPDATE ON etms.dock_appointments
    FOR EACH ROW EXECUTE PROCEDURE etms.prevent_dock_appointment_overlap();

REVOKE ALL ON FUNCTION etms.prevent_dock_appointment_overlap() FROM PUBLIC;

CREATE INDEX IF NOT EXISTS ix_dock_appointments_active_dock_window
    ON etms.dock_appointments (
        tenant_id, dock_id, scheduled_start_at, scheduled_end_at
    )
    WHERE dock_id IS NOT NULL AND status NOT IN ('CANCELLED', 'REJECTED');

CREATE INDEX IF NOT EXISTS ix_dock_appointments_active_vehicle_window
    ON etms.dock_appointments (
        tenant_id, vehicle_id, scheduled_start_at, scheduled_end_at
    )
    WHERE vehicle_id IS NOT NULL AND status NOT IN ('CANCELLED', 'REJECTED');
