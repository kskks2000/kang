-- ETMS forward migration: pre-auth audit, multimodal parentage, and SCD integrity.
-- PostgreSQL 11 compatible; do not rewrite deployed baseline modules.

CREATE OR REPLACE FUNCTION etms.is_etms_owner_execution()
RETURNS boolean
LANGUAGE sql
STABLE
AS $function$
    SELECT current_user = (
        SELECT pg_get_userbyid(namespace_row.nspowner)
        FROM pg_namespace namespace_row
        WHERE namespace_row.nspname = 'etms'
    );
$function$;

DROP POLICY IF EXISTS preauth_insert ON etms.login_events;
CREATE POLICY preauth_insert ON etms.login_events
    FOR INSERT
    WITH CHECK (tenant_id IS NULL AND etms.is_etms_owner_execution());
DROP POLICY IF EXISTS preauth_select ON etms.login_events;
CREATE POLICY preauth_select ON etms.login_events
    FOR SELECT
    USING (tenant_id IS NULL AND etms.is_etms_owner_execution());

DROP POLICY IF EXISTS preauth_insert ON etms.audit_events;
CREATE POLICY preauth_insert ON etms.audit_events
    FOR INSERT
    WITH CHECK (tenant_id IS NULL AND etms.is_etms_owner_execution());
DROP POLICY IF EXISTS preauth_select ON etms.audit_events;
CREATE POLICY preauth_select ON etms.audit_events
    FOR SELECT
    USING (tenant_id IS NULL AND etms.is_etms_owner_execution());

CREATE OR REPLACE FUNCTION etms.record_preauth_login_event(
    p_firebase_uid text,
    p_provider_code text,
    p_success boolean,
    p_failure_code text DEFAULT NULL,
    p_failure_detail_masked text DEFAULT NULL,
    p_ip_address inet DEFAULT NULL,
    p_user_agent text DEFAULT NULL,
    p_correlation_id text DEFAULT NULL,
    p_occurred_at timestamptz DEFAULT statement_timestamp()
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    event_id uuid;
    mapped_user_id uuid;
BEGIN
    IF p_provider_code NOT IN ('password','google.com')
       OR p_occurred_at IS NULL
       OR p_occurred_at > statement_timestamp() + interval '5 minutes'
       OR (p_success AND p_failure_code IS NOT NULL)
       OR (NOT p_success AND btrim(COALESCE(p_failure_code, '')) = '') THEN
        RAISE EXCEPTION 'Invalid pre-authentication audit event'
            USING ERRCODE = '22023';
    END IF;
    IF p_failure_detail_masked ~* '(bearer[[:space:]]+[A-Za-z0-9._~+/-]{8,}|refresh[_ -]?token|access[_ -]?token|password[[:space:]]*[=:])' THEN
        RAISE EXCEPTION 'Pre-authentication audit detail contains credential-like material'
            USING ERRCODE = '23514';
    END IF;
    SELECT user_row.id INTO mapped_user_id
    FROM etms.users user_row
    WHERE user_row.firebase_uid = p_firebase_uid
      AND user_row.firebase_project_id = 'kang-84cdd'
      AND user_row.firebase_tenant_id IS NULL
      AND user_row.deleted_at IS NULL;

    INSERT INTO etms.login_events (
        tenant_id, user_id, firebase_uid, provider_code, success,
        failure_code, failure_detail_masked, ip_address, user_agent,
        correlation_id, occurred_at, received_at
    ) VALUES (
        NULL, mapped_user_id, p_firebase_uid, p_provider_code, p_success,
        p_failure_code, p_failure_detail_masked, p_ip_address, p_user_agent,
        p_correlation_id, p_occurred_at, statement_timestamp()
    ) RETURNING id INTO event_id;
    RETURN event_id;
END;
$function$;

CREATE OR REPLACE FUNCTION etms.record_preauth_security_audit(
    p_action_code text,
    p_reason text DEFAULT NULL,
    p_ip_address inet DEFAULT NULL,
    p_user_agent text DEFAULT NULL,
    p_correlation_id text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE event_id uuid;
BEGIN
    IF btrim(COALESCE(p_action_code, '')) = ''
       OR p_action_code !~ '^[A-Z0-9_.:-]{3,100}$' THEN
        RAISE EXCEPTION 'Invalid pre-authentication audit action'
            USING ERRCODE = '22023';
    END IF;
    IF p_reason ~* '(bearer[[:space:]]+[A-Za-z0-9._~+/-]{8,}|refresh[_ -]?token|access[_ -]?token|password[[:space:]]*[=:])' THEN
        RAISE EXCEPTION 'Pre-authentication audit reason contains credential-like material'
            USING ERRCODE = '23514';
    END IF;
    INSERT INTO etms.audit_events (
        tenant_id, action_code, reason, ip_address, user_agent,
        correlation_id, occurred_at
    ) VALUES (
        NULL, p_action_code, p_reason, p_ip_address, p_user_agent,
        p_correlation_id, statement_timestamp()
    ) RETURNING id INTO event_id;
    RETURN event_id;
END;
$function$;

CREATE OR REPLACE FUNCTION etms.validate_parcel_shipment_parentage()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
BEGIN
    IF NEW.order_id IS NOT NULL AND NEW.shipment_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM etms.shipment_orders allocation_row
        WHERE allocation_row.tenant_id = NEW.tenant_id
          AND allocation_row.order_id = NEW.order_id
          AND allocation_row.shipment_id = NEW.shipment_id
          AND allocation_row.removed_at IS NULL
    ) THEN
        RAISE EXCEPTION 'Parcel order and shipment must be an active allocated pair'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_validate_parcel_shipment_parentage ON etms.parcel_shipments;
CREATE TRIGGER trg_validate_parcel_shipment_parentage
    BEFORE INSERT OR UPDATE OF tenant_id, order_id, shipment_id
    ON etms.parcel_shipments
    FOR EACH ROW EXECUTE PROCEDURE etms.validate_parcel_shipment_parentage();

CREATE OR REPLACE FUNCTION etms.validate_parcel_package_parentage()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    parcel_row record;
    handling_order_id uuid;
BEGIN
    IF NEW.handling_unit_id IS NULL THEN RETURN NEW; END IF;
    SELECT order_id, shipment_id INTO parcel_row
    FROM etms.parcel_shipments
    WHERE id = NEW.parcel_shipment_id AND tenant_id = NEW.tenant_id;
    SELECT order_id INTO handling_order_id
    FROM etms.handling_units
    WHERE id = NEW.handling_unit_id AND tenant_id = NEW.tenant_id;
    IF NOT FOUND OR (
        parcel_row.order_id IS DISTINCT FROM handling_order_id
        AND NOT EXISTS (
            SELECT 1 FROM etms.shipment_orders allocation_row
            WHERE allocation_row.tenant_id = NEW.tenant_id
              AND allocation_row.shipment_id = parcel_row.shipment_id
              AND allocation_row.order_id = handling_order_id
              AND allocation_row.removed_at IS NULL
        )
    ) THEN
        RAISE EXCEPTION 'Parcel package handling unit is outside the parcel order/shipment'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_validate_parcel_package_parentage ON etms.parcel_packages;
CREATE TRIGGER trg_validate_parcel_package_parentage
    BEFORE INSERT OR UPDATE OF tenant_id, parcel_shipment_id, handling_unit_id
    ON etms.parcel_packages
    FOR EACH ROW EXECUTE PROCEDURE etms.validate_parcel_package_parentage();

CREATE OR REPLACE FUNCTION etms.validate_ocean_bill_parentage()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    booking_row record;
    voyage_carrier uuid;
BEGIN
    IF NEW.carrier_booking_id IS NOT NULL THEN
        SELECT carrier_id, mode_code INTO booking_row
        FROM etms.carrier_bookings
        WHERE id = NEW.carrier_booking_id AND tenant_id = NEW.tenant_id;
        IF booking_row.mode_code IS DISTINCT FROM 'OCEAN'
           OR (NEW.shipment_id IS NOT NULL AND NOT EXISTS (
               SELECT 1 FROM etms.carrier_booking_items item_row
               WHERE item_row.tenant_id = NEW.tenant_id
                 AND item_row.booking_id = NEW.carrier_booking_id
                 AND item_row.shipment_id = NEW.shipment_id
           )) THEN
            RAISE EXCEPTION 'Ocean bill booking/mode/shipment relationship is inconsistent'
                USING ERRCODE = '23514';
        END IF;
    END IF;
    IF NEW.ocean_voyage_id IS NOT NULL AND NEW.carrier_booking_id IS NOT NULL THEN
        SELECT carrier_partner_id INTO voyage_carrier
        FROM etms.ocean_voyages
        WHERE id = NEW.ocean_voyage_id AND tenant_id = NEW.tenant_id;
        IF voyage_carrier IS DISTINCT FROM booking_row.carrier_id THEN
            RAISE EXCEPTION 'Ocean voyage carrier must match the carrier booking'
                USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_validate_ocean_bill_parentage ON etms.ocean_bills_of_lading;
CREATE TRIGGER trg_validate_ocean_bill_parentage
    BEFORE INSERT OR UPDATE OF tenant_id, ocean_voyage_id, carrier_booking_id, shipment_id
    ON etms.ocean_bills_of_lading
    FOR EACH ROW EXECUTE PROCEDURE etms.validate_ocean_bill_parentage();

CREATE OR REPLACE FUNCTION etms.validate_air_waybill_parentage()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    booking_row record;
    flight_row record;
BEGIN
    IF NEW.carrier_booking_id IS NOT NULL THEN
        SELECT carrier_id, mode_code INTO booking_row
        FROM etms.carrier_bookings
        WHERE id = NEW.carrier_booking_id AND tenant_id = NEW.tenant_id;
        IF booking_row.mode_code IS DISTINCT FROM 'AIR'
           OR booking_row.carrier_id IS DISTINCT FROM NEW.issuing_carrier_partner_id
           OR (NEW.shipment_id IS NOT NULL AND NOT EXISTS (
               SELECT 1 FROM etms.carrier_booking_items item_row
               WHERE item_row.tenant_id = NEW.tenant_id
                 AND item_row.booking_id = NEW.carrier_booking_id
                 AND item_row.shipment_id = NEW.shipment_id
           )) THEN
            RAISE EXCEPTION 'Air waybill booking/carrier/shipment relationship is inconsistent'
                USING ERRCODE = '23514';
        END IF;
    END IF;
    IF NEW.air_flight_id IS NOT NULL THEN
        SELECT marketing_carrier_partner_id, operating_carrier_partner_id,
               origin_airport_id, destination_airport_id
          INTO flight_row
          FROM etms.air_flights
         WHERE id = NEW.air_flight_id AND tenant_id = NEW.tenant_id;
        IF NEW.origin_airport_id IS DISTINCT FROM flight_row.origin_airport_id
           OR NEW.destination_airport_id IS DISTINCT FROM flight_row.destination_airport_id
           OR NEW.issuing_carrier_partner_id NOT IN (
               flight_row.marketing_carrier_partner_id,
               COALESCE(flight_row.operating_carrier_partner_id, flight_row.marketing_carrier_partner_id)
           ) THEN
            RAISE EXCEPTION 'Air waybill flight airports/carrier are inconsistent'
                USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_validate_air_waybill_parentage ON etms.air_waybills;
CREATE TRIGGER trg_validate_air_waybill_parentage
    BEFORE INSERT OR UPDATE OF tenant_id, air_flight_id, shipment_id,
        carrier_booking_id, issuing_carrier_partner_id, origin_airport_id,
        destination_airport_id
    ON etms.air_waybills
    FOR EACH ROW EXECUTE PROCEDURE etms.validate_air_waybill_parentage();

CREATE OR REPLACE FUNCTION etms.validate_rail_waybill_parentage()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE car_consist_id uuid;
BEGIN
    IF NEW.rail_car_id IS NOT NULL AND NEW.rail_consist_id IS NOT NULL THEN
        SELECT rail_consist_id INTO car_consist_id
        FROM etms.rail_cars
        WHERE id = NEW.rail_car_id AND tenant_id = NEW.tenant_id;
        IF car_consist_id IS DISTINCT FROM NEW.rail_consist_id THEN
            RAISE EXCEPTION 'Rail waybill car must belong to its rail consist'
                USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_validate_rail_waybill_parentage ON etms.rail_waybills;
CREATE TRIGGER trg_validate_rail_waybill_parentage
    BEFORE INSERT OR UPDATE OF tenant_id, rail_consist_id, rail_car_id
    ON etms.rail_waybills
    FOR EACH ROW EXECUTE PROCEDURE etms.validate_rail_waybill_parentage();

CREATE OR REPLACE FUNCTION etms.prevent_scd_interval_overlap()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, etms, pg_temp
AS $function$
DECLARE
    source_value uuid;
    interval_overlaps boolean;
BEGIN
    source_value := NULLIF(to_jsonb(NEW) ->> TG_ARGV[0], '')::uuid;
    PERFORM pg_advisory_xact_lock(hashtext(
        TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME || ':' || NEW.tenant_id::text || ':' || source_value::text
    ));
    EXECUTE format(
        'SELECT EXISTS ('
        'SELECT 1 FROM %I.%I existing_row '
        'WHERE existing_row.tenant_id = $1 AND existing_row.%I = $2 '
        'AND existing_row.id <> $3 '
        'AND existing_row.effective_from < COALESCE($4, ''infinity''::timestamptz) '
        'AND $5 < COALESCE(existing_row.effective_to, ''infinity''::timestamptz))',
        TG_TABLE_SCHEMA, TG_TABLE_NAME, TG_ARGV[0]
    ) INTO interval_overlaps
    USING NEW.tenant_id, source_value, NEW.id, NEW.effective_to, NEW.effective_from;
    IF interval_overlaps THEN
        RAISE EXCEPTION 'SCD2 effective periods overlap for %.%', TG_TABLE_SCHEMA, TG_TABLE_NAME
            USING ERRCODE = '23P01';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE UNIQUE INDEX IF NOT EXISTS ux_dim_locations_scd_current
    ON etms.dim_locations_scd (tenant_id, source_location_id) WHERE is_current;
CREATE UNIQUE INDEX IF NOT EXISTS ux_dim_partners_scd_current
    ON etms.dim_partners_scd (tenant_id, source_partner_id) WHERE is_current;
CREATE UNIQUE INDEX IF NOT EXISTS ux_dim_carriers_scd_current
    ON etms.dim_carriers_scd (tenant_id, source_carrier_partner_id) WHERE is_current;
CREATE UNIQUE INDEX IF NOT EXISTS ux_dim_drivers_scd_current
    ON etms.dim_drivers_scd (tenant_id, source_driver_id) WHERE is_current;
CREATE UNIQUE INDEX IF NOT EXISTS ux_dim_vehicles_scd_current
    ON etms.dim_vehicles_scd (tenant_id, source_vehicle_id) WHERE is_current;
CREATE UNIQUE INDEX IF NOT EXISTS ux_dim_lanes_scd_current
    ON etms.dim_lanes_scd (tenant_id, source_lane_id) WHERE is_current;

DROP TRIGGER IF EXISTS trg_prevent_scd_overlap ON etms.dim_locations_scd;
CREATE TRIGGER trg_prevent_scd_overlap
    BEFORE INSERT OR UPDATE OF tenant_id, source_location_id, effective_from, effective_to
    ON etms.dim_locations_scd
    FOR EACH ROW EXECUTE PROCEDURE etms.prevent_scd_interval_overlap('source_location_id');
DROP TRIGGER IF EXISTS trg_prevent_scd_overlap ON etms.dim_partners_scd;
CREATE TRIGGER trg_prevent_scd_overlap
    BEFORE INSERT OR UPDATE OF tenant_id, source_partner_id, effective_from, effective_to
    ON etms.dim_partners_scd
    FOR EACH ROW EXECUTE PROCEDURE etms.prevent_scd_interval_overlap('source_partner_id');
DROP TRIGGER IF EXISTS trg_prevent_scd_overlap ON etms.dim_carriers_scd;
CREATE TRIGGER trg_prevent_scd_overlap
    BEFORE INSERT OR UPDATE OF tenant_id, source_carrier_partner_id, effective_from, effective_to
    ON etms.dim_carriers_scd
    FOR EACH ROW EXECUTE PROCEDURE etms.prevent_scd_interval_overlap('source_carrier_partner_id');
DROP TRIGGER IF EXISTS trg_prevent_scd_overlap ON etms.dim_drivers_scd;
CREATE TRIGGER trg_prevent_scd_overlap
    BEFORE INSERT OR UPDATE OF tenant_id, source_driver_id, effective_from, effective_to
    ON etms.dim_drivers_scd
    FOR EACH ROW EXECUTE PROCEDURE etms.prevent_scd_interval_overlap('source_driver_id');
DROP TRIGGER IF EXISTS trg_prevent_scd_overlap ON etms.dim_vehicles_scd;
CREATE TRIGGER trg_prevent_scd_overlap
    BEFORE INSERT OR UPDATE OF tenant_id, source_vehicle_id, effective_from, effective_to
    ON etms.dim_vehicles_scd
    FOR EACH ROW EXECUTE PROCEDURE etms.prevent_scd_interval_overlap('source_vehicle_id');
DROP TRIGGER IF EXISTS trg_prevent_scd_overlap ON etms.dim_lanes_scd;
CREATE TRIGGER trg_prevent_scd_overlap
    BEFORE INSERT OR UPDATE OF tenant_id, source_lane_id, effective_from, effective_to
    ON etms.dim_lanes_scd
    FOR EACH ROW EXECUTE PROCEDURE etms.prevent_scd_interval_overlap('source_lane_id');

CREATE UNIQUE INDEX IF NOT EXISTS ux_fact_multimodal_performance_grain
    ON etms.fact_multimodal_performance (
        tenant_id, shipment_id,
        COALESCE(shipment_leg_id, '00000000-0000-0000-0000-000000000000'::uuid),
        mode_code
    );

REVOKE ALL ON FUNCTION etms.is_etms_owner_execution() FROM PUBLIC;
REVOKE ALL ON FUNCTION etms.record_preauth_login_event(
    text,text,boolean,text,text,inet,text,text,timestamptz
) FROM PUBLIC;
REVOKE ALL ON FUNCTION etms.record_preauth_security_audit(text,text,inet,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION etms.validate_parcel_shipment_parentage() FROM PUBLIC;
REVOKE ALL ON FUNCTION etms.validate_parcel_package_parentage() FROM PUBLIC;
REVOKE ALL ON FUNCTION etms.validate_ocean_bill_parentage() FROM PUBLIC;
REVOKE ALL ON FUNCTION etms.validate_air_waybill_parentage() FROM PUBLIC;
REVOKE ALL ON FUNCTION etms.validate_rail_waybill_parentage() FROM PUBLIC;
REVOKE ALL ON FUNCTION etms.prevent_scd_interval_overlap() FROM PUBLIC;
