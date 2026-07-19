-- EWMS enterprise WMS schema - lot/serial/LPN, stock dimensions, immutable inventory ledger,
-- reservations, holds, inventory execution, counts, valuation, and transformations.
-- PostgreSQL 11 compatible. Applied after 03_inbound_quality_returns.sql.

CREATE TABLE IF NOT EXISTS ewms.inventory_lots (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    owner_partner_id uuid NOT NULL REFERENCES ewms.business_partners(id),
    item_id uuid NOT NULL REFERENCES ewms.items(id),
    lot_no varchar(200) NOT NULL,
    supplier_lot_no varchar(200),
    manufacturer_lot_no varchar(200),
    manufactured_on date,
    received_on date,
    expires_on date,
    best_before_on date,
    retest_on date,
    country_of_origin char(2) REFERENCES ewms.countries(country_code),
    source_receipt_line_id uuid,
    source_lot_observation_id uuid,
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    quality_status varchar(20) NOT NULL DEFAULT 'PENDING',
    potency numeric(20,8),
    potency_uom_code varchar(20) REFERENCES ewms.units_of_measure(uom_code),
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_by uuid REFERENCES ewms.users(id),
    updated_by uuid REFERENCES ewms.users(id),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    UNIQUE (tenant_id, owner_partner_id, item_id, lot_no),
    UNIQUE (tenant_id, id),
    FOREIGN KEY (tenant_id, source_receipt_line_id)
        REFERENCES ewms.receipt_lines(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, source_lot_observation_id)
        REFERENCES ewms.receipt_lot_observations(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_inventory_lot_no CHECK (btrim(lot_no) <> ''),
    CONSTRAINT ck_inventory_lot_dates CHECK (
        (expires_on IS NULL OR manufactured_on IS NULL OR expires_on >= manufactured_on) AND
        (best_before_on IS NULL OR manufactured_on IS NULL OR best_before_on >= manufactured_on) AND
        (retest_on IS NULL OR manufactured_on IS NULL OR retest_on >= manufactured_on) AND
        (received_on IS NULL OR manufactured_on IS NULL OR received_on >= manufactured_on)
    ),
    CONSTRAINT ck_inventory_lot_status CHECK (status IN (
        'ACTIVE','BLOCKED','EXPIRED','CONSUMED','RECALLED','CLOSED','CANCELLED'
    )),
    CONSTRAINT ck_inventory_lot_quality CHECK (quality_status IN (
        'PENDING','ACCEPTED','CONDITIONAL','REJECTED','QUARANTINE','NOT_REQUIRED'
    )),
    CONSTRAINT ck_inventory_lot_potency CHECK (potency IS NULL OR potency >= 0)
);

CREATE TABLE IF NOT EXISTS ewms.inventory_lot_attributes (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    inventory_lot_id uuid NOT NULL,
    attribute_definition_id uuid REFERENCES ewms.item_lot_attribute_definitions(id),
    attribute_code varchar(80) NOT NULL,
    text_value text,
    numeric_value numeric(30,12),
    date_value date,
    timestamp_value timestamptz,
    boolean_value boolean,
    code_value varchar(200),
    source_type varchar(30) NOT NULL DEFAULT 'RECEIPT',
    verified_by uuid REFERENCES ewms.users(id),
    verified_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (tenant_id, inventory_lot_id)
        REFERENCES ewms.inventory_lots(tenant_id, id) ON DELETE RESTRICT,
    UNIQUE (inventory_lot_id, attribute_code),
    CONSTRAINT ck_inventory_lot_attr_value CHECK (
        num_nonnulls(text_value,numeric_value,date_value,timestamp_value,boolean_value,code_value) = 1
    ),
    CONSTRAINT ck_inventory_lot_attr_source CHECK (source_type IN (
        'RECEIPT','SUPPLIER','INSPECTION','TRANSFORMATION','IMPORT','MANUAL'
    ))
);

CREATE TABLE IF NOT EXISTS ewms.inventory_lot_genealogy (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    parent_lot_id uuid NOT NULL,
    child_lot_id uuid NOT NULL,
    relationship_type varchar(30) NOT NULL,
    parent_quantity numeric(24,8),
    child_quantity numeric(24,8),
    uom_code varchar(20) REFERENCES ewms.units_of_measure(uom_code),
    transformation_reference varchar(150),
    effective_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid REFERENCES ewms.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (tenant_id, parent_lot_id)
        REFERENCES ewms.inventory_lots(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, child_lot_id)
        REFERENCES ewms.inventory_lots(tenant_id, id) ON DELETE RESTRICT,
    UNIQUE (parent_lot_id, child_lot_id, relationship_type, effective_at),
    CONSTRAINT ck_inventory_lot_genealogy_distinct CHECK (parent_lot_id <> child_lot_id),
    CONSTRAINT ck_inventory_lot_genealogy_type CHECK (relationship_type IN (
        'SPLIT','MERGE','REPACK','RELABEL','TRANSFORM','REWORK','DERIVED'
    )),
    CONSTRAINT ck_inventory_lot_genealogy_qty CHECK (
        (parent_quantity IS NULL OR parent_quantity > 0) AND
        (child_quantity IS NULL OR child_quantity > 0)
    )
);

CREATE TABLE IF NOT EXISTS ewms.serial_numbers (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    owner_partner_id uuid NOT NULL REFERENCES ewms.business_partners(id),
    item_id uuid NOT NULL REFERENCES ewms.items(id),
    serial_no varchar(300) NOT NULL,
    manufacturer_serial_no varchar(300),
    inventory_lot_id uuid,
    country_of_origin char(2) REFERENCES ewms.countries(country_code),
    manufactured_on date,
    expires_on date,
    source_receipt_line_id uuid,
    source_serial_observation_id uuid,
    status varchar(30) NOT NULL DEFAULT 'RECEIVED',
    warranty_start_on date,
    warranty_end_on date,
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_by uuid REFERENCES ewms.users(id),
    updated_by uuid REFERENCES ewms.users(id),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    UNIQUE (tenant_id, owner_partner_id, item_id, serial_no),
    UNIQUE (tenant_id, id),
    FOREIGN KEY (tenant_id, inventory_lot_id)
        REFERENCES ewms.inventory_lots(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, source_receipt_line_id)
        REFERENCES ewms.receipt_lines(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, source_serial_observation_id)
        REFERENCES ewms.receipt_serial_observations(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_serial_no_nonempty CHECK (btrim(serial_no) <> ''),
    CONSTRAINT ck_serial_status CHECK (status IN (
        'EXPECTED','RECEIVED','AVAILABLE','ALLOCATED','PICKED','PACKED','SHIPPED',
        'RETURNED','HOLD','DAMAGED','SCRAPPED','LOST','CONSUMED','CANCELLED'
    )),
    CONSTRAINT ck_serial_dates CHECK (
        (expires_on IS NULL OR manufactured_on IS NULL OR expires_on >= manufactured_on) AND
        (warranty_end_on IS NULL OR warranty_start_on IS NULL OR warranty_end_on >= warranty_start_on)
    )
);

CREATE TABLE IF NOT EXISTS ewms.serial_status_history (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    serial_number_id uuid NOT NULL,
    event_sequence integer NOT NULL,
    from_status varchar(30),
    to_status varchar(30) NOT NULL,
    reason_code_id uuid REFERENCES ewms.reason_codes(id),
    inventory_transaction_id uuid,
    actor_user_id uuid REFERENCES ewms.users(id) ON DELETE SET NULL,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    recorded_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (tenant_id, serial_number_id)
        REFERENCES ewms.serial_numbers(tenant_id, id) ON DELETE RESTRICT,
    UNIQUE (serial_number_id, event_sequence),
    CONSTRAINT ck_serial_history_sequence CHECK (event_sequence > 0)
);

CREATE TABLE IF NOT EXISTS ewms.lpn_types (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid REFERENCES ewms.tenants(id) ON DELETE CASCADE,
    lpn_type_code varchar(50) NOT NULL,
    lpn_type_name varchar(150) NOT NULL,
    container_class varchar(30) NOT NULL,
    sscc_capable boolean NOT NULL DEFAULT false,
    reusable boolean NOT NULL DEFAULT false,
    returnable boolean NOT NULL DEFAULT false,
    max_weight numeric(24,6),
    weight_uom_code varchar(20) REFERENCES ewms.units_of_measure(uom_code),
    max_volume numeric(24,9),
    volume_uom_code varchar(20) REFERENCES ewms.units_of_measure(uom_code),
    max_child_count integer,
    is_active boolean NOT NULL DEFAULT true,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_lpn_type_class CHECK (container_class IN (
        'PALLET','CARTON','TOTE','CRATE','DRUM','BAG','CONTAINER','ROLL_CAGE','VIRTUAL','OTHER'
    )),
    CONSTRAINT ck_lpn_type_limits CHECK (
        (max_weight IS NULL OR max_weight >= 0) AND
        (max_volume IS NULL OR max_volume >= 0) AND
        (max_child_count IS NULL OR max_child_count > 0)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_lpn_types_scope
    ON ewms.lpn_types (
        COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), lpn_type_code
    );

CREATE TABLE IF NOT EXISTS ewms.lpns (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    lpn_no varchar(200) NOT NULL,
    sscc varchar(30),
    lpn_type_id uuid NOT NULL REFERENCES ewms.lpn_types(id),
    warehouse_id uuid NOT NULL REFERENCES ewms.warehouses(id),
    owner_partner_id uuid REFERENCES ewms.business_partners(id),
    parent_lpn_id uuid,
    current_location_id uuid REFERENCES ewms.warehouse_locations(id),
    status varchar(30) NOT NULL DEFAULT 'OPEN',
    sealed boolean NOT NULL DEFAULT false,
    seal_no varchar(100),
    gross_weight numeric(24,8),
    tare_weight numeric(24,8),
    weight_uom_code varchar(20) REFERENCES ewms.units_of_measure(uom_code),
    volume numeric(24,9),
    volume_uom_code varchar(20) REFERENCES ewms.units_of_measure(uom_code),
    mixed_owner boolean NOT NULL DEFAULT false,
    mixed_item boolean NOT NULL DEFAULT false,
    mixed_lot boolean NOT NULL DEFAULT false,
    source_type varchar(30),
    source_id uuid,
    created_by uuid REFERENCES ewms.users(id),
    updated_by uuid REFERENCES ewms.users(id),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    closed_at timestamptz,
    deleted_at timestamptz,
    UNIQUE (tenant_id, lpn_no),
    UNIQUE (tenant_id, id),
    FOREIGN KEY (tenant_id, parent_lpn_id)
        REFERENCES ewms.lpns(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_lpn_parent CHECK (parent_lpn_id IS NULL OR parent_lpn_id <> id),
    CONSTRAINT ck_lpn_status CHECK (status IN (
        'OPEN','RECEIVING','AVAILABLE','ALLOCATED','PICKING','PICKED','PACKED','STAGED',
        'LOADED','SHIPPED','IN_TRANSIT','HOLD','DAMAGED','EMPTY','CLOSED','CANCELLED'
    )),
    CONSTRAINT ck_lpn_weights CHECK (
        (gross_weight IS NULL OR gross_weight >= 0) AND
        (tare_weight IS NULL OR tare_weight >= 0) AND
        (gross_weight IS NULL OR tare_weight IS NULL OR gross_weight >= tare_weight) AND
        (volume IS NULL OR volume >= 0)
    ),
    CONSTRAINT ck_lpn_seal CHECK (NOT sealed OR seal_no IS NOT NULL)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_lpns_sscc
    ON ewms.lpns (tenant_id, sscc)
    WHERE sscc IS NOT NULL AND deleted_at IS NULL;

CREATE TABLE IF NOT EXISTS ewms.lpn_status_history (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    lpn_id uuid NOT NULL,
    event_sequence integer NOT NULL,
    from_status varchar(30),
    to_status varchar(30) NOT NULL,
    reason_code_id uuid REFERENCES ewms.reason_codes(id),
    inventory_transaction_id uuid,
    actor_user_id uuid REFERENCES ewms.users(id) ON DELETE SET NULL,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    recorded_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (tenant_id, lpn_id)
        REFERENCES ewms.lpns(tenant_id, id) ON DELETE RESTRICT,
    UNIQUE (lpn_id, event_sequence),
    CONSTRAINT ck_lpn_status_history_sequence CHECK (event_sequence > 0)
);

CREATE TABLE IF NOT EXISTS ewms.lpn_location_history (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    lpn_id uuid NOT NULL,
    event_sequence integer NOT NULL,
    from_location_id uuid REFERENCES ewms.warehouse_locations(id),
    to_location_id uuid REFERENCES ewms.warehouse_locations(id),
    movement_type varchar(30) NOT NULL,
    inventory_transaction_id uuid,
    actor_user_id uuid REFERENCES ewms.users(id) ON DELETE SET NULL,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    recorded_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (tenant_id, lpn_id)
        REFERENCES ewms.lpns(tenant_id, id) ON DELETE RESTRICT,
    UNIQUE (lpn_id, event_sequence),
    CONSTRAINT ck_lpn_location_sequence CHECK (event_sequence > 0),
    CONSTRAINT ck_lpn_location_distinct CHECK (
        from_location_id IS DISTINCT FROM to_location_id
    )
);

CREATE TABLE IF NOT EXISTS ewms.lpn_relationship_history (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    child_lpn_id uuid NOT NULL,
    parent_lpn_id uuid,
    relationship_action varchar(20) NOT NULL,
    actor_user_id uuid REFERENCES ewms.users(id) ON DELETE SET NULL,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (tenant_id, child_lpn_id)
        REFERENCES ewms.lpns(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, parent_lpn_id)
        REFERENCES ewms.lpns(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_lpn_relationship_action CHECK (relationship_action IN ('ATTACH','DETACH','RE_PARENT')),
    CONSTRAINT ck_lpn_relationship_distinct CHECK (parent_lpn_id IS NULL OR parent_lpn_id <> child_lpn_id)
);

CREATE TABLE IF NOT EXISTS ewms.stock_buckets (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    owner_partner_id uuid NOT NULL REFERENCES ewms.business_partners(id),
    warehouse_id uuid NOT NULL REFERENCES ewms.warehouses(id),
    location_id uuid REFERENCES ewms.warehouse_locations(id),
    item_id uuid NOT NULL REFERENCES ewms.items(id),
    inventory_status_id uuid NOT NULL REFERENCES ewms.inventory_statuses(id),
    inventory_lot_id uuid,
    serial_number_id uuid,
    lpn_id uuid,
    country_of_origin char(2) REFERENCES ewms.countries(country_code),
    account_type varchar(30) NOT NULL DEFAULT 'PHYSICAL',
    customs_legal_status_code varchar(50),
    bonded_cargo_reference varchar(200),
    customs_declaration_line_id uuid,
    stock_attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_by uuid REFERENCES ewms.users(id),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    FOREIGN KEY (tenant_id, inventory_lot_id)
        REFERENCES ewms.inventory_lots(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, serial_number_id)
        REFERENCES ewms.serial_numbers(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, lpn_id)
        REFERENCES ewms.lpns(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_stock_bucket_account_type CHECK (account_type IN (
        'PHYSICAL','INBOUND_SOURCE','OUTBOUND_SINK','ADJUSTMENT','IN_TRANSIT','WIP','VIRTUAL'
    )),
    CONSTRAINT ck_stock_bucket_location CHECK (
        (account_type IN ('PHYSICAL','IN_TRANSIT','WIP') AND location_id IS NOT NULL) OR
        (account_type IN ('INBOUND_SOURCE','OUTBOUND_SINK','ADJUSTMENT','VIRTUAL') AND location_id IS NULL)
    )
);

-- PG11 treats NULL values as distinct in UNIQUE constraints. COALESCE provides one canonical
-- key for all nullable dimensions without relying on PG15 NULLS NOT DISTINCT.
CREATE UNIQUE INDEX IF NOT EXISTS ux_stock_bucket_dimensions
    ON ewms.stock_buckets (
        tenant_id, owner_partner_id, warehouse_id,
        COALESCE(location_id, '00000000-0000-0000-0000-000000000000'::uuid),
        item_id, inventory_status_id,
        COALESCE(inventory_lot_id, '00000000-0000-0000-0000-000000000000'::uuid),
        COALESCE(serial_number_id, '00000000-0000-0000-0000-000000000000'::uuid),
        COALESCE(lpn_id, '00000000-0000-0000-0000-000000000000'::uuid),
        COALESCE(country_of_origin, ''), account_type,
        COALESCE(customs_legal_status_code, ''), COALESCE(bonded_cargo_reference, ''),
        COALESCE(customs_declaration_line_id, '00000000-0000-0000-0000-000000000000'::uuid)
    );

CREATE TABLE IF NOT EXISTS ewms.inventory_transaction_headers (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    transaction_no varchar(100) NOT NULL,
    transaction_type varchar(40) NOT NULL,
    warehouse_id uuid NOT NULL REFERENCES ewms.warehouses(id),
    owner_partner_id uuid NOT NULL REFERENCES ewms.business_partners(id),
    posting_status varchar(20) NOT NULL DEFAULT 'DRAFT',
    source_document_type varchar(50),
    source_document_id uuid,
    source_document_line_id uuid,
    source_document_no varchar(150),
    source_system_id uuid REFERENCES ewms.external_systems(id),
    idempotency_key varchar(200),
    reversal_of_transaction_id uuid,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    posted_at timestamptz,
    posted_by uuid REFERENCES ewms.users(id),
    reason_code_id uuid REFERENCES ewms.reason_codes(id),
    reason_text text,
    correlation_id varchar(100),
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_by uuid REFERENCES ewms.users(id),
    updated_by uuid REFERENCES ewms.users(id),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, transaction_no),
    UNIQUE (tenant_id, id),
    FOREIGN KEY (tenant_id, reversal_of_transaction_id)
        REFERENCES ewms.inventory_transaction_headers(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_inventory_tx_type CHECK (transaction_type IN (
        'OPENING','RECEIPT','PUTAWAY','MOVE','TRANSFER','REPLENISHMENT','PICK','PACK','SHIPMENT',
        'RETURN_TO_SUPPLIER','CUSTOMER_RETURN','ADJUSTMENT','CYCLE_COUNT','STATUS_CHANGE',
        'OWNER_TRANSFER','BONDED_MOVE','TRANSFORMATION','REPACK','RELABEL','REVERSAL'
    )),
    CONSTRAINT ck_inventory_tx_status CHECK (posting_status IN ('DRAFT','VALIDATED','POSTED','FAILED','CANCELLED')),
    CONSTRAINT ck_inventory_tx_posted CHECK (
        (posting_status = 'POSTED' AND posted_at IS NOT NULL AND posted_by IS NOT NULL) OR
        posting_status <> 'POSTED'
    ),
    CONSTRAINT ck_inventory_tx_reversal CHECK (
        (transaction_type = 'REVERSAL' AND reversal_of_transaction_id IS NOT NULL) OR
        (transaction_type <> 'REVERSAL' AND reversal_of_transaction_id IS NULL)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_inventory_tx_idempotency
    ON ewms.inventory_transaction_headers (
        tenant_id,
        COALESCE(source_system_id, '00000000-0000-0000-0000-000000000000'::uuid),
        idempotency_key
    ) WHERE idempotency_key IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS ux_inventory_tx_reversal
    ON ewms.inventory_transaction_headers (reversal_of_transaction_id)
    WHERE reversal_of_transaction_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS ewms.inventory_transaction_entries (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    inventory_transaction_id uuid NOT NULL,
    entry_sequence integer NOT NULL,
    stock_bucket_id uuid NOT NULL,
    item_id uuid NOT NULL REFERENCES ewms.items(id),
    signed_quantity numeric(24,8) NOT NULL,
    base_uom_code varchar(20) NOT NULL REFERENCES ewms.units_of_measure(uom_code),
    entered_quantity numeric(24,8),
    entered_uom_code varchar(20) REFERENCES ewms.units_of_measure(uom_code),
    catch_weight numeric(24,8),
    catch_weight_uom_code varchar(20) REFERENCES ewms.units_of_measure(uom_code),
    unit_cost numeric(24,8),
    extended_value numeric(28,8),
    currency_code char(3) REFERENCES ewms.currencies(currency_code),
    entry_role varchar(20) NOT NULL DEFAULT 'STOCK',
    source_line_type varchar(50),
    source_line_id uuid,
    created_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (tenant_id, inventory_transaction_id)
        REFERENCES ewms.inventory_transaction_headers(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, stock_bucket_id)
        REFERENCES ewms.stock_buckets(tenant_id, id) ON DELETE RESTRICT,
    UNIQUE (inventory_transaction_id, entry_sequence),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_inventory_entry_sequence CHECK (entry_sequence > 0),
    CONSTRAINT ck_inventory_entry_quantity CHECK (
        signed_quantity <> 0 AND (entered_quantity IS NULL OR entered_quantity > 0) AND
        (catch_weight IS NULL OR catch_weight >= 0)
    ),
    CONSTRAINT ck_inventory_entry_cost CHECK (
        (unit_cost IS NULL OR unit_cost >= 0) AND
        (extended_value IS NULL OR extended_value >= 0)
    ),
    CONSTRAINT ck_inventory_entry_role CHECK (entry_role IN ('SOURCE','STOCK','DESTINATION','COST','VARIANCE'))
);

CREATE TABLE IF NOT EXISTS ewms.inventory_balances (
    stock_bucket_id uuid PRIMARY KEY,
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    on_hand_quantity numeric(24,8) NOT NULL DEFAULT 0,
    reserved_quantity numeric(24,8) NOT NULL DEFAULT 0,
    held_quantity numeric(24,8) NOT NULL DEFAULT 0,
    pending_out_quantity numeric(24,8) NOT NULL DEFAULT 0,
    pending_in_quantity numeric(24,8) NOT NULL DEFAULT 0,
    last_transaction_id uuid,
    last_transaction_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (tenant_id, stock_bucket_id)
        REFERENCES ewms.stock_buckets(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, last_transaction_id)
        REFERENCES ewms.inventory_transaction_headers(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_inventory_balance_reservations CHECK (
        reserved_quantity >= 0 AND held_quantity >= 0 AND
        pending_out_quantity >= 0 AND pending_in_quantity >= 0
    )
);

CREATE OR REPLACE VIEW ewms.inventory_available_balances AS
SELECT
    b.tenant_id,
    b.stock_bucket_id,
    sb.owner_partner_id,
    sb.warehouse_id,
    sb.location_id,
    sb.item_id,
    sb.inventory_status_id,
    sb.inventory_lot_id,
    sb.serial_number_id,
    sb.lpn_id,
    sb.country_of_origin,
    sb.account_type,
    sb.customs_legal_status_code,
    b.on_hand_quantity,
    b.reserved_quantity,
    b.held_quantity,
    b.pending_out_quantity,
    b.pending_in_quantity,
    b.on_hand_quantity - b.reserved_quantity - b.held_quantity - b.pending_out_quantity AS available_quantity,
    b.last_transaction_id,
    b.last_transaction_at
FROM ewms.inventory_balances b
JOIN ewms.stock_buckets sb ON sb.id = b.stock_bucket_id
WHERE sb.account_type = 'PHYSICAL';

CREATE OR REPLACE VIEW ewms.lpn_current_contents AS
SELECT
    sb.tenant_id,
    sb.lpn_id,
    sb.stock_bucket_id,
    sb.owner_partner_id,
    sb.warehouse_id,
    sb.location_id,
    sb.item_id,
    sb.inventory_status_id,
    sb.inventory_lot_id,
    sb.serial_number_id,
    b.on_hand_quantity
FROM ewms.inventory_available_balances sb
JOIN ewms.inventory_balances b ON b.stock_bucket_id = sb.stock_bucket_id
WHERE sb.lpn_id IS NOT NULL AND b.on_hand_quantity <> 0;

CREATE TABLE IF NOT EXISTS ewms.inventory_reservations (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    reservation_no varchar(100) NOT NULL,
    stock_bucket_id uuid NOT NULL,
    reservation_type varchar(30) NOT NULL DEFAULT 'ORDER',
    demand_document_type varchar(50) NOT NULL,
    demand_document_id uuid NOT NULL,
    demand_line_id uuid,
    reserved_quantity numeric(24,8) NOT NULL,
    base_uom_code varchar(20) NOT NULL REFERENCES ewms.units_of_measure(uom_code),
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    priority integer NOT NULL DEFAULT 100,
    reserved_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz,
    consumed_at timestamptz,
    released_at timestamptz,
    consumed_transaction_id uuid,
    reason_code_id uuid REFERENCES ewms.reason_codes(id),
    created_by uuid REFERENCES ewms.users(id),
    updated_by uuid REFERENCES ewms.users(id),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, reservation_no),
    UNIQUE (tenant_id, id),
    FOREIGN KEY (tenant_id, stock_bucket_id)
        REFERENCES ewms.stock_buckets(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, consumed_transaction_id)
        REFERENCES ewms.inventory_transaction_headers(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_inventory_reservation_qty CHECK (reserved_quantity > 0),
    CONSTRAINT ck_inventory_reservation_type CHECK (reservation_type IN (
        'ORDER','WAVE','TRANSFER','REPLENISHMENT','PRODUCTION','CUSTOMS','MANUAL'
    )),
    CONSTRAINT ck_inventory_reservation_status CHECK (status IN (
        'ACTIVE','PARTIALLY_CONSUMED','CONSUMED','RELEASED','EXPIRED','CANCELLED'
    )),
    CONSTRAINT ck_inventory_reservation_expiry CHECK (expires_at IS NULL OR expires_at > reserved_at),
    CONSTRAINT ck_inventory_reservation_terminal CHECK (
        (status IN ('CONSUMED','PARTIALLY_CONSUMED') AND consumed_at IS NOT NULL) OR
        (status IN ('RELEASED','EXPIRED','CANCELLED') AND released_at IS NOT NULL) OR
        status = 'ACTIVE'
    )
);

CREATE TABLE IF NOT EXISTS ewms.inventory_reservation_history (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    inventory_reservation_id uuid NOT NULL,
    event_sequence integer NOT NULL,
    from_status varchar(20),
    to_status varchar(20) NOT NULL,
    quantity_delta numeric(24,8),
    reason_code_id uuid REFERENCES ewms.reason_codes(id),
    actor_user_id uuid REFERENCES ewms.users(id) ON DELETE SET NULL,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    recorded_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (tenant_id, inventory_reservation_id)
        REFERENCES ewms.inventory_reservations(tenant_id, id) ON DELETE RESTRICT,
    UNIQUE (inventory_reservation_id, event_sequence),
    CONSTRAINT ck_inventory_reservation_hist_seq CHECK (event_sequence > 0)
);

CREATE TABLE IF NOT EXISTS ewms.inventory_holds (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    hold_no varchar(100) NOT NULL,
    stock_bucket_id uuid NOT NULL,
    quality_hold_id uuid,
    hold_type varchar(30) NOT NULL DEFAULT 'OPERATIONAL',
    held_quantity numeric(24,8) NOT NULL,
    base_uom_code varchar(20) NOT NULL REFERENCES ewms.units_of_measure(uom_code),
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    reason_code_id uuid REFERENCES ewms.reason_codes(id),
    reason_text text NOT NULL,
    placed_by uuid REFERENCES ewms.users(id),
    placed_at timestamptz NOT NULL DEFAULT now(),
    review_due_at timestamptz,
    released_quantity numeric(24,8) NOT NULL DEFAULT 0,
    released_by uuid REFERENCES ewms.users(id),
    released_at timestamptz,
    created_by uuid REFERENCES ewms.users(id),
    updated_by uuid REFERENCES ewms.users(id),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, hold_no),
    UNIQUE (tenant_id, id),
    FOREIGN KEY (tenant_id, stock_bucket_id)
        REFERENCES ewms.stock_buckets(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, quality_hold_id)
        REFERENCES ewms.quality_holds(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_inventory_hold_qty CHECK (
        held_quantity > 0 AND released_quantity >= 0 AND released_quantity <= held_quantity
    ),
    CONSTRAINT ck_inventory_hold_type CHECK (hold_type IN (
        'OPERATIONAL','QUALITY','QUARANTINE','REGULATORY','CUSTOMS','DAMAGE','EXPIRY','RECALL','COUNT','OTHER'
    )),
    CONSTRAINT ck_inventory_hold_status CHECK (status IN (
        'ACTIVE','PARTIALLY_RELEASED','RELEASED','CANCELLED'
    )),
    CONSTRAINT ck_inventory_hold_release CHECK (
        (status IN ('PARTIALLY_RELEASED','RELEASED') AND released_at IS NOT NULL) OR
        status IN ('ACTIVE','CANCELLED')
    ),
    CONSTRAINT ck_inventory_hold_release_qty CHECK (
        (status = 'RELEASED' AND released_quantity = held_quantity) OR
        (status = 'PARTIALLY_RELEASED' AND released_quantity > 0 AND released_quantity < held_quantity) OR
        status IN ('ACTIVE','CANCELLED')
    )
);

CREATE TABLE IF NOT EXISTS ewms.inventory_hold_releases (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    inventory_hold_id uuid NOT NULL,
    release_sequence integer NOT NULL,
    released_quantity numeric(24,8) NOT NULL,
    reason_code_id uuid REFERENCES ewms.reason_codes(id),
    reason_text text,
    released_by uuid REFERENCES ewms.users(id),
    released_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (tenant_id, inventory_hold_id)
        REFERENCES ewms.inventory_holds(tenant_id, id) ON DELETE RESTRICT,
    UNIQUE (inventory_hold_id, release_sequence),
    CONSTRAINT ck_inventory_hold_release_seq CHECK (release_sequence > 0),
    CONSTRAINT ck_inventory_hold_release_qty CHECK (released_quantity > 0)
);

CREATE TABLE IF NOT EXISTS ewms.receipt_inventory_postings (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    receipt_id uuid NOT NULL,
    posting_sequence integer NOT NULL,
    inventory_transaction_id uuid NOT NULL,
    posting_type varchar(20) NOT NULL DEFAULT 'RECEIPT',
    status varchar(20) NOT NULL DEFAULT 'CREATED',
    posted_at timestamptz,
    reversed_by_posting_id uuid,
    created_by uuid REFERENCES ewms.users(id),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (tenant_id, receipt_id)
        REFERENCES ewms.receipts(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, inventory_transaction_id)
        REFERENCES ewms.inventory_transaction_headers(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, reversed_by_posting_id)
        REFERENCES ewms.receipt_inventory_postings(tenant_id, id) ON DELETE RESTRICT,
    UNIQUE (receipt_id, posting_sequence),
    UNIQUE (inventory_transaction_id),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_receipt_inventory_posting_seq CHECK (posting_sequence > 0),
    CONSTRAINT ck_receipt_inventory_posting_type CHECK (posting_type IN ('RECEIPT','CORRECTION','REVERSAL')),
    CONSTRAINT ck_receipt_inventory_posting_status CHECK (status IN ('CREATED','VALIDATED','POSTED','REVERSED','FAILED'))
);

CREATE TABLE IF NOT EXISTS ewms.receipt_inventory_allocations (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    receipt_inventory_posting_id uuid NOT NULL,
    receipt_line_id uuid NOT NULL,
    receipt_lot_observation_id uuid,
    receipt_serial_observation_id uuid,
    inventory_lot_id uuid,
    serial_number_id uuid,
    destination_stock_bucket_id uuid NOT NULL,
    inventory_transaction_entry_id uuid NOT NULL,
    allocated_quantity numeric(24,8) NOT NULL,
    base_uom_code varchar(20) NOT NULL REFERENCES ewms.units_of_measure(uom_code),
    created_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (tenant_id, receipt_inventory_posting_id)
        REFERENCES ewms.receipt_inventory_postings(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, receipt_line_id)
        REFERENCES ewms.receipt_lines(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, receipt_lot_observation_id)
        REFERENCES ewms.receipt_lot_observations(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, receipt_serial_observation_id)
        REFERENCES ewms.receipt_serial_observations(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, inventory_lot_id)
        REFERENCES ewms.inventory_lots(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, serial_number_id)
        REFERENCES ewms.serial_numbers(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, destination_stock_bucket_id)
        REFERENCES ewms.stock_buckets(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, inventory_transaction_entry_id)
        REFERENCES ewms.inventory_transaction_entries(tenant_id, id) ON DELETE RESTRICT,
    UNIQUE (receipt_inventory_posting_id, receipt_line_id, inventory_transaction_entry_id),
    CONSTRAINT ck_receipt_inventory_alloc_qty CHECK (allocated_quantity > 0)
);

DO $block$
DECLARE
    legacy_constraint name;
BEGIN
    SELECT constraint_row.conname INTO legacy_constraint
      FROM pg_constraint constraint_row
     WHERE constraint_row.conrelid = 'ewms.receipt_inventory_allocations'::regclass
       AND constraint_row.contype = 'u'
       AND constraint_row.conkey = ARRAY[
           (SELECT attnum FROM pg_attribute
             WHERE attrelid = 'ewms.receipt_inventory_allocations'::regclass
               AND attname = 'receipt_inventory_posting_id' AND NOT attisdropped),
           (SELECT attnum FROM pg_attribute
             WHERE attrelid = 'ewms.receipt_inventory_allocations'::regclass
               AND attname = 'inventory_transaction_entry_id' AND NOT attisdropped)
       ]::smallint[];
    IF legacy_constraint IS NOT NULL THEN
        EXECUTE format('ALTER TABLE ewms.receipt_inventory_allocations DROP CONSTRAINT %I',
                       legacy_constraint);
    END IF;
    IF NOT EXISTS (
        SELECT 1
          FROM pg_constraint constraint_row
         WHERE constraint_row.conrelid = 'ewms.receipt_inventory_allocations'::regclass
           AND constraint_row.contype = 'u'
           AND constraint_row.conkey = ARRAY[
               (SELECT attnum FROM pg_attribute
                 WHERE attrelid = 'ewms.receipt_inventory_allocations'::regclass
                   AND attname = 'receipt_inventory_posting_id' AND NOT attisdropped),
               (SELECT attnum FROM pg_attribute
                 WHERE attrelid = 'ewms.receipt_inventory_allocations'::regclass
                   AND attname = 'receipt_line_id' AND NOT attisdropped),
               (SELECT attnum FROM pg_attribute
                 WHERE attrelid = 'ewms.receipt_inventory_allocations'::regclass
                   AND attname = 'inventory_transaction_entry_id' AND NOT attisdropped)
           ]::smallint[]
    ) THEN
        ALTER TABLE ewms.receipt_inventory_allocations
            ADD CONSTRAINT uq_ewms_receipt_inventory_allocation_split
            UNIQUE (receipt_inventory_posting_id, receipt_line_id, inventory_transaction_entry_id);
    END IF;
END;
$block$;

CREATE TABLE IF NOT EXISTS ewms.supplier_return_inventory_allocations (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    supplier_return_order_line_id uuid NOT NULL,
    source_stock_bucket_id uuid NOT NULL,
    inventory_transaction_entry_id uuid,
    allocated_quantity numeric(24,8) NOT NULL,
    base_uom_code varchar(20) NOT NULL REFERENCES ewms.units_of_measure(uom_code),
    status varchar(20) NOT NULL DEFAULT 'ALLOCATED',
    allocated_at timestamptz NOT NULL DEFAULT now(),
    posted_at timestamptz,
    FOREIGN KEY (tenant_id, supplier_return_order_line_id)
        REFERENCES ewms.supplier_return_order_lines(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, source_stock_bucket_id)
        REFERENCES ewms.stock_buckets(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, inventory_transaction_entry_id)
        REFERENCES ewms.inventory_transaction_entries(tenant_id, id) ON DELETE RESTRICT,
    UNIQUE (supplier_return_order_line_id, source_stock_bucket_id),
    CONSTRAINT ck_supplier_return_inventory_qty CHECK (allocated_quantity > 0),
    CONSTRAINT ck_supplier_return_inventory_status CHECK (status IN ('ALLOCATED','PICKED','POSTED','RELEASED','CANCELLED'))
);

COMMENT ON TABLE ewms.stock_buckets IS
    'Canonical stock dimensions. Physical inventory_status_id and customs_legal_status_code are deliberately independent.';
COMMENT ON TABLE ewms.inventory_transaction_entries IS
    'Signed double-entry stock ledger. Every posted transaction must balance to zero by item and base UOM, including external source/sink buckets.';
COMMENT ON TABLE ewms.inventory_balances IS
    'Current projection maintained only by controlled posting/reservation/hold functions; it is not the audit source of truth.';

CREATE TABLE IF NOT EXISTS ewms.quality_hold_inventory_allocations (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    quality_hold_id uuid NOT NULL,
    inventory_hold_id uuid NOT NULL,
    stock_bucket_id uuid NOT NULL,
    allocated_quantity numeric(24,8) NOT NULL,
    base_uom_code varchar(20) NOT NULL REFERENCES ewms.units_of_measure(uom_code),
    created_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (tenant_id, quality_hold_id)
        REFERENCES ewms.quality_holds(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, inventory_hold_id)
        REFERENCES ewms.inventory_holds(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, stock_bucket_id)
        REFERENCES ewms.stock_buckets(tenant_id, id) ON DELETE RESTRICT,
    UNIQUE (quality_hold_id, inventory_hold_id, stock_bucket_id),
    CONSTRAINT ck_quality_hold_inventory_qty CHECK (allocated_quantity > 0)
);

CREATE TABLE IF NOT EXISTS ewms.stock_transfer_orders (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    transfer_order_no varchar(100) NOT NULL,
    transfer_type varchar(30) NOT NULL DEFAULT 'INTERNAL',
    owner_partner_id uuid NOT NULL REFERENCES ewms.business_partners(id),
    source_warehouse_id uuid NOT NULL REFERENCES ewms.warehouses(id),
    destination_warehouse_id uuid NOT NULL REFERENCES ewms.warehouses(id),
    requested_ship_at timestamptz,
    required_receive_at timestamptz,
    status varchar(30) NOT NULL DEFAULT 'DRAFT',
    posting_status varchar(20) NOT NULL DEFAULT 'NOT_POSTED',
    in_transit_location_id uuid REFERENCES ewms.warehouse_locations(id),
    source_system_id uuid REFERENCES ewms.external_systems(id),
    source_document_id varchar(300),
    reason_code_id uuid REFERENCES ewms.reason_codes(id),
    instructions text,
    created_by uuid REFERENCES ewms.users(id),
    updated_by uuid REFERENCES ewms.users(id),
    approved_by uuid REFERENCES ewms.users(id),
    approved_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, transfer_order_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_stock_transfer_type CHECK (transfer_type IN (
        'INTERNAL','INTER_WAREHOUSE','OWNER_TRANSFER','BONDED_TRANSFER','RETURN_TRANSFER'
    )),
    CONSTRAINT ck_stock_transfer_status CHECK (status IN (
        'DRAFT','REQUESTED','APPROVED','RELEASED','PICKING','SHIPPED','IN_TRANSIT',
        'PARTIALLY_RECEIVED','RECEIVED','CLOSED','ON_HOLD','CANCELLED'
    )),
    CONSTRAINT ck_stock_transfer_posting CHECK (posting_status IN (
        'NOT_POSTED','PARTIAL','POSTED','REVERSED','FAILED'
    )),
    CONSTRAINT ck_stock_transfer_dates CHECK (
        required_receive_at IS NULL OR requested_ship_at IS NULL OR required_receive_at >= requested_ship_at
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_stock_transfer_external
    ON ewms.stock_transfer_orders (tenant_id, source_system_id, source_document_id)
    WHERE source_system_id IS NOT NULL AND source_document_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS ewms.stock_transfer_lines (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    stock_transfer_order_id uuid NOT NULL,
    line_no integer NOT NULL,
    item_id uuid NOT NULL REFERENCES ewms.items(id),
    requested_quantity numeric(24,8) NOT NULL,
    allocated_quantity numeric(24,8) NOT NULL DEFAULT 0,
    shipped_quantity numeric(24,8) NOT NULL DEFAULT 0,
    received_quantity numeric(24,8) NOT NULL DEFAULT 0,
    cancelled_quantity numeric(24,8) NOT NULL DEFAULT 0,
    uom_code varchar(20) NOT NULL REFERENCES ewms.units_of_measure(uom_code),
    requested_lot_id uuid,
    requested_inventory_status_id uuid REFERENCES ewms.inventory_statuses(id),
    destination_inventory_status_id uuid REFERENCES ewms.inventory_statuses(id),
    status varchar(20) NOT NULL DEFAULT 'OPEN',
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (tenant_id, stock_transfer_order_id)
        REFERENCES ewms.stock_transfer_orders(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, requested_lot_id)
        REFERENCES ewms.inventory_lots(tenant_id, id) ON DELETE RESTRICT,
    UNIQUE (stock_transfer_order_id, line_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_stock_transfer_line_no CHECK (line_no > 0),
    CONSTRAINT ck_stock_transfer_line_qty CHECK (
        requested_quantity > 0 AND allocated_quantity >= 0 AND shipped_quantity >= 0 AND
        received_quantity >= 0 AND cancelled_quantity >= 0 AND
        allocated_quantity <= requested_quantity AND shipped_quantity <= allocated_quantity AND
        received_quantity <= shipped_quantity AND cancelled_quantity <= requested_quantity
    ),
    CONSTRAINT ck_stock_transfer_line_status CHECK (status IN (
        'OPEN','ALLOCATED','PARTIALLY_ALLOCATED','PICKED','SHIPPED','PARTIALLY_RECEIVED',
        'RECEIVED','CLOSED','SHORT','CANCELLED'
    ))
);

CREATE TABLE IF NOT EXISTS ewms.stock_transfer_status_history (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    stock_transfer_order_id uuid NOT NULL,
    event_sequence integer NOT NULL,
    from_status varchar(30),
    to_status varchar(30) NOT NULL,
    reason_code_id uuid REFERENCES ewms.reason_codes(id),
    actor_user_id uuid REFERENCES ewms.users(id) ON DELETE SET NULL,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    recorded_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (tenant_id, stock_transfer_order_id)
        REFERENCES ewms.stock_transfer_orders(tenant_id, id) ON DELETE RESTRICT,
    UNIQUE (stock_transfer_order_id, event_sequence),
    CONSTRAINT ck_stock_transfer_hist_sequence CHECK (event_sequence > 0)
);

CREATE TABLE IF NOT EXISTS ewms.movement_tasks (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    task_no varchar(100) NOT NULL,
    task_type varchar(30) NOT NULL,
    warehouse_id uuid NOT NULL REFERENCES ewms.warehouses(id),
    owner_partner_id uuid NOT NULL REFERENCES ewms.business_partners(id),
    item_id uuid NOT NULL REFERENCES ewms.items(id),
    source_stock_bucket_id uuid NOT NULL,
    destination_stock_bucket_id uuid,
    destination_location_id uuid REFERENCES ewms.warehouse_locations(id),
    destination_inventory_status_id uuid REFERENCES ewms.inventory_statuses(id),
    destination_lpn_id uuid,
    requested_quantity numeric(24,8) NOT NULL,
    completed_quantity numeric(24,8) NOT NULL DEFAULT 0,
    short_quantity numeric(24,8) NOT NULL DEFAULT 0,
    cancelled_quantity numeric(24,8) NOT NULL DEFAULT 0,
    base_uom_code varchar(20) NOT NULL REFERENCES ewms.units_of_measure(uom_code),
    priority integer NOT NULL DEFAULT 100,
    task_group_type varchar(40),
    task_group_id uuid,
    assigned_user_id uuid REFERENCES ewms.users(id),
    assigned_equipment_id uuid REFERENCES ewms.material_handling_equipment(id),
    planned_start_at timestamptz,
    started_at timestamptz,
    completed_at timestamptz,
    inventory_transaction_id uuid,
    status varchar(20) NOT NULL DEFAULT 'OPEN',
    exception_code varchar(80),
    instructions text,
    created_by uuid REFERENCES ewms.users(id),
    updated_by uuid REFERENCES ewms.users(id),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, task_no),
    UNIQUE (tenant_id, id),
    FOREIGN KEY (tenant_id, source_stock_bucket_id)
        REFERENCES ewms.stock_buckets(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, destination_stock_bucket_id)
        REFERENCES ewms.stock_buckets(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, destination_lpn_id)
        REFERENCES ewms.lpns(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, inventory_transaction_id)
        REFERENCES ewms.inventory_transaction_headers(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_movement_task_type CHECK (task_type IN (
        'PUTAWAY','MOVE','REPLENISHMENT','TRANSFER_PICK','TRANSFER_RECEIVE','STATUS_MOVE',
        'LPN_MOVE','CONSOLIDATE','DECONSOLIDATE','COUNT_MOVE','OTHER'
    )),
    CONSTRAINT ck_movement_task_qty CHECK (
        requested_quantity > 0 AND completed_quantity >= 0 AND short_quantity >= 0 AND cancelled_quantity >= 0 AND
        completed_quantity + short_quantity + cancelled_quantity <= requested_quantity
    ),
    CONSTRAINT ck_movement_task_priority CHECK (priority >= 0),
    CONSTRAINT ck_movement_task_destination CHECK (
        destination_stock_bucket_id IS NOT NULL OR destination_location_id IS NOT NULL
    ),
    CONSTRAINT ck_movement_task_status CHECK (status IN (
        'OPEN','ASSIGNED','RELEASED','IN_PROGRESS','PAUSED','PARTIALLY_COMPLETED',
        'COMPLETED','SHORT','EXCEPTION','CANCELLED'
    )),
    CONSTRAINT ck_movement_task_dates CHECK (completed_at IS NULL OR started_at IS NULL OR completed_at >= started_at)
);

CREATE TABLE IF NOT EXISTS ewms.movement_confirmations (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    movement_task_id uuid NOT NULL,
    confirmation_sequence integer NOT NULL,
    from_stock_bucket_id uuid NOT NULL,
    to_stock_bucket_id uuid NOT NULL,
    confirmed_quantity numeric(24,8) NOT NULL,
    base_uom_code varchar(20) NOT NULL REFERENCES ewms.units_of_measure(uom_code),
    inventory_transaction_id uuid NOT NULL,
    confirmed_by uuid REFERENCES ewms.users(id),
    confirmed_at timestamptz NOT NULL DEFAULT now(),
    device_id uuid REFERENCES ewms.rf_devices(id),
    source_check_value varchar(100),
    destination_check_value varchar(100),
    FOREIGN KEY (tenant_id, movement_task_id)
        REFERENCES ewms.movement_tasks(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, from_stock_bucket_id)
        REFERENCES ewms.stock_buckets(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, to_stock_bucket_id)
        REFERENCES ewms.stock_buckets(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, inventory_transaction_id)
        REFERENCES ewms.inventory_transaction_headers(tenant_id, id) ON DELETE RESTRICT,
    UNIQUE (movement_task_id, confirmation_sequence),
    CONSTRAINT ck_movement_confirmation_seq CHECK (confirmation_sequence > 0),
    CONSTRAINT ck_movement_confirmation_qty CHECK (confirmed_quantity > 0),
    CONSTRAINT ck_movement_confirmation_buckets CHECK (from_stock_bucket_id <> to_stock_bucket_id)
);

CREATE TABLE IF NOT EXISTS ewms.movement_task_status_history (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    movement_task_id uuid NOT NULL,
    event_sequence integer NOT NULL,
    from_status varchar(20),
    to_status varchar(20) NOT NULL,
    actor_user_id uuid REFERENCES ewms.users(id) ON DELETE SET NULL,
    reason_code_id uuid REFERENCES ewms.reason_codes(id),
    occurred_at timestamptz NOT NULL DEFAULT now(),
    recorded_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (tenant_id, movement_task_id)
        REFERENCES ewms.movement_tasks(tenant_id, id) ON DELETE RESTRICT,
    UNIQUE (movement_task_id, event_sequence),
    CONSTRAINT ck_movement_task_hist_seq CHECK (event_sequence > 0)
);

CREATE TABLE IF NOT EXISTS ewms.putaway_tasks (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    putaway_request_id uuid NOT NULL,
    movement_task_id uuid NOT NULL,
    strategy_id uuid REFERENCES ewms.putaway_strategies(id),
    suggested_location_id uuid REFERENCES ewms.warehouse_locations(id),
    suggestion_rank integer,
    capacity_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
    rule_trace jsonb NOT NULL DEFAULT '[]'::jsonb,
    override_reason_code_id uuid REFERENCES ewms.reason_codes(id),
    override_by uuid REFERENCES ewms.users(id),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (tenant_id, putaway_request_id)
        REFERENCES ewms.putaway_requests(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, movement_task_id)
        REFERENCES ewms.movement_tasks(tenant_id, id) ON DELETE RESTRICT,
    UNIQUE (putaway_request_id, movement_task_id),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_putaway_task_rank CHECK (suggestion_rank IS NULL OR suggestion_rank > 0)
);

CREATE TABLE IF NOT EXISTS ewms.putaway_confirmations (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    putaway_task_id uuid NOT NULL,
    movement_confirmation_id uuid NOT NULL,
    destination_location_id uuid NOT NULL REFERENCES ewms.warehouse_locations(id),
    confirmed_quantity numeric(24,8) NOT NULL,
    base_uom_code varchar(20) NOT NULL REFERENCES ewms.units_of_measure(uom_code),
    confirmed_by uuid REFERENCES ewms.users(id),
    confirmed_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (tenant_id, putaway_task_id)
        REFERENCES ewms.putaway_tasks(tenant_id, id) ON DELETE RESTRICT,
    UNIQUE (movement_confirmation_id),
    CONSTRAINT ck_putaway_confirmation_qty CHECK (confirmed_quantity > 0)
);

CREATE TABLE IF NOT EXISTS ewms.replenishment_requests (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    request_no varchar(100) NOT NULL,
    warehouse_id uuid NOT NULL REFERENCES ewms.warehouses(id),
    owner_partner_id uuid NOT NULL REFERENCES ewms.business_partners(id),
    item_id uuid NOT NULL REFERENCES ewms.items(id),
    replenishment_policy_id uuid REFERENCES ewms.replenishment_policies(id),
    demand_type varchar(30) NOT NULL,
    demand_id uuid,
    destination_location_id uuid NOT NULL REFERENCES ewms.warehouse_locations(id),
    requested_quantity numeric(24,8) NOT NULL,
    allocated_quantity numeric(24,8) NOT NULL DEFAULT 0,
    completed_quantity numeric(24,8) NOT NULL DEFAULT 0,
    base_uom_code varchar(20) NOT NULL REFERENCES ewms.units_of_measure(uom_code),
    priority integer NOT NULL DEFAULT 100,
    required_at timestamptz,
    status varchar(20) NOT NULL DEFAULT 'OPEN',
    created_by uuid REFERENCES ewms.users(id),
    updated_by uuid REFERENCES ewms.users(id),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, request_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_replenishment_request_demand CHECK (demand_type IN (
        'MIN_MAX','ORDER','WAVE','EMPTY_LOCATION','SCHEDULED','MANUAL'
    )),
    CONSTRAINT ck_replenishment_request_qty CHECK (
        requested_quantity > 0 AND allocated_quantity >= 0 AND completed_quantity >= 0 AND
        allocated_quantity <= requested_quantity AND completed_quantity <= allocated_quantity
    ),
    CONSTRAINT ck_replenishment_request_status CHECK (status IN (
        'OPEN','PLANNED','ALLOCATED','RELEASED','IN_PROGRESS','PARTIALLY_COMPLETED','COMPLETED','SHORT','CANCELLED'
    ))
);

CREATE TABLE IF NOT EXISTS ewms.replenishment_tasks (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    replenishment_request_id uuid NOT NULL,
    movement_task_id uuid NOT NULL,
    source_stock_bucket_id uuid NOT NULL,
    allocated_quantity numeric(24,8) NOT NULL,
    base_uom_code varchar(20) NOT NULL REFERENCES ewms.units_of_measure(uom_code),
    status varchar(20) NOT NULL DEFAULT 'ALLOCATED',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (tenant_id, replenishment_request_id)
        REFERENCES ewms.replenishment_requests(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, movement_task_id)
        REFERENCES ewms.movement_tasks(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, source_stock_bucket_id)
        REFERENCES ewms.stock_buckets(tenant_id, id) ON DELETE RESTRICT,
    UNIQUE (replenishment_request_id, movement_task_id),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_replenishment_task_qty CHECK (allocated_quantity > 0),
    CONSTRAINT ck_replenishment_task_status CHECK (status IN (
        'ALLOCATED','RELEASED','IN_PROGRESS','COMPLETED','SHORT','CANCELLED'
    ))
);

CREATE TABLE IF NOT EXISTS ewms.inventory_adjustments (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    adjustment_no varchar(100) NOT NULL,
    warehouse_id uuid NOT NULL REFERENCES ewms.warehouses(id),
    owner_partner_id uuid NOT NULL REFERENCES ewms.business_partners(id),
    adjustment_type varchar(30) NOT NULL,
    reason_code_id uuid NOT NULL REFERENCES ewms.reason_codes(id),
    reason_text text,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    approval_required boolean NOT NULL DEFAULT true,
    requested_by uuid REFERENCES ewms.users(id),
    requested_at timestamptz NOT NULL DEFAULT now(),
    approved_by uuid REFERENCES ewms.users(id),
    approved_at timestamptz,
    posted_transaction_id uuid,
    posted_at timestamptz,
    source_system_id uuid REFERENCES ewms.external_systems(id),
    source_document_id varchar(300),
    created_by uuid REFERENCES ewms.users(id),
    updated_by uuid REFERENCES ewms.users(id),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, adjustment_no),
    UNIQUE (tenant_id, id),
    FOREIGN KEY (tenant_id, posted_transaction_id)
        REFERENCES ewms.inventory_transaction_headers(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_inventory_adjustment_type CHECK (adjustment_type IN (
        'GAIN','LOSS','DAMAGE','EXPIRY','SCRAP','STATUS','OWNER','COST','COUNT','SYSTEM_CORRECTION'
    )),
    CONSTRAINT ck_inventory_adjustment_status CHECK (status IN (
        'DRAFT','SUBMITTED','APPROVED','REJECTED','POSTED','REVERSED','CANCELLED'
    )),
    CONSTRAINT ck_inventory_adjustment_approval CHECK (
        (status IN ('APPROVED','POSTED','REVERSED') AND approved_at IS NOT NULL) OR
        status NOT IN ('APPROVED','POSTED','REVERSED')
    ),
    CONSTRAINT ck_inventory_adjustment_posted CHECK (
        status <> 'POSTED' OR (posted_transaction_id IS NOT NULL AND posted_at IS NOT NULL)
    )
);

CREATE TABLE IF NOT EXISTS ewms.inventory_adjustment_lines (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    inventory_adjustment_id uuid NOT NULL,
    line_no integer NOT NULL,
    stock_bucket_id uuid NOT NULL,
    requested_quantity_delta numeric(24,8) NOT NULL,
    approved_quantity_delta numeric(24,8),
    base_uom_code varchar(20) NOT NULL REFERENCES ewms.units_of_measure(uom_code),
    unit_cost_delta numeric(24,8),
    currency_code char(3) REFERENCES ewms.currencies(currency_code),
    target_inventory_status_id uuid REFERENCES ewms.inventory_statuses(id),
    target_owner_partner_id uuid REFERENCES ewms.business_partners(id),
    inventory_transaction_entry_id uuid,
    note text,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (tenant_id, inventory_adjustment_id)
        REFERENCES ewms.inventory_adjustments(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, stock_bucket_id)
        REFERENCES ewms.stock_buckets(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, inventory_transaction_entry_id)
        REFERENCES ewms.inventory_transaction_entries(tenant_id, id) ON DELETE RESTRICT,
    UNIQUE (inventory_adjustment_id, line_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_inventory_adjustment_line_no CHECK (line_no > 0),
    CONSTRAINT ck_inventory_adjustment_line_qty CHECK (
        requested_quantity_delta <> 0 AND
        (approved_quantity_delta IS NULL OR approved_quantity_delta <> 0)
    )
);

CREATE TABLE IF NOT EXISTS ewms.inventory_adjustment_approvals (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    inventory_adjustment_id uuid NOT NULL,
    approval_sequence integer NOT NULL,
    approver_user_id uuid NOT NULL REFERENCES ewms.users(id),
    decision varchar(20) NOT NULL,
    decision_reason text,
    decided_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (tenant_id, inventory_adjustment_id)
        REFERENCES ewms.inventory_adjustments(tenant_id, id) ON DELETE RESTRICT,
    UNIQUE (inventory_adjustment_id, approval_sequence),
    CONSTRAINT ck_inventory_adjustment_approval_seq CHECK (approval_sequence > 0),
    CONSTRAINT ck_inventory_adjustment_decision CHECK (decision IN ('APPROVED','REJECTED','RETURNED','CANCELLED'))
);

CREATE TABLE IF NOT EXISTS ewms.inventory_adjustment_status_history (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    inventory_adjustment_id uuid NOT NULL,
    event_sequence integer NOT NULL,
    from_status varchar(20),
    to_status varchar(20) NOT NULL,
    actor_user_id uuid REFERENCES ewms.users(id) ON DELETE SET NULL,
    reason text,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    recorded_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (tenant_id, inventory_adjustment_id)
        REFERENCES ewms.inventory_adjustments(tenant_id, id) ON DELETE RESTRICT,
    UNIQUE (inventory_adjustment_id, event_sequence),
    CONSTRAINT ck_inventory_adjustment_hist_seq CHECK (event_sequence > 0)
);

CREATE TABLE IF NOT EXISTS ewms.cycle_count_plans (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    count_plan_no varchar(100) NOT NULL,
    warehouse_id uuid NOT NULL REFERENCES ewms.warehouses(id),
    owner_partner_id uuid REFERENCES ewms.business_partners(id),
    count_type varchar(30) NOT NULL DEFAULT 'CYCLE',
    selection_method varchar(30) NOT NULL DEFAULT 'MANUAL',
    blind_count boolean NOT NULL DEFAULT true,
    recount_threshold_quantity numeric(24,8),
    recount_threshold_percent numeric(9,6),
    freeze_inventory boolean NOT NULL DEFAULT true,
    scheduled_start_at timestamptz,
    scheduled_end_at timestamptz,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    approved_by uuid REFERENCES ewms.users(id),
    approved_at timestamptz,
    created_by uuid REFERENCES ewms.users(id),
    updated_by uuid REFERENCES ewms.users(id),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, count_plan_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_cycle_count_plan_type CHECK (count_type IN (
        'CYCLE','ANNUAL','WALL_TO_WALL','SPOT','ZERO_BALANCE','RECOUNT','REGULATORY'
    )),
    CONSTRAINT ck_cycle_count_selection CHECK (selection_method IN (
        'MANUAL','ABC','LOCATION','ITEM','LOT','OWNER','RISK','RANDOM','SYSTEM'
    )),
    CONSTRAINT ck_cycle_count_threshold CHECK (
        (recount_threshold_quantity IS NULL OR recount_threshold_quantity >= 0) AND
        (recount_threshold_percent IS NULL OR recount_threshold_percent BETWEEN 0 AND 100)
    ),
    CONSTRAINT ck_cycle_count_plan_dates CHECK (
        scheduled_end_at IS NULL OR scheduled_start_at IS NULL OR scheduled_end_at >= scheduled_start_at
    ),
    CONSTRAINT ck_cycle_count_plan_status CHECK (status IN (
        'DRAFT','APPROVED','RELEASED','IN_PROGRESS','RECONCILING','COMPLETED','CLOSED','CANCELLED'
    ))
);

CREATE TABLE IF NOT EXISTS ewms.cycle_count_scopes (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    cycle_count_plan_id uuid NOT NULL,
    scope_sequence integer NOT NULL,
    owner_partner_id uuid REFERENCES ewms.business_partners(id),
    zone_id uuid REFERENCES ewms.warehouse_zones(id),
    location_id uuid REFERENCES ewms.warehouse_locations(id),
    item_id uuid REFERENCES ewms.items(id),
    inventory_lot_id uuid,
    lpn_id uuid,
    inventory_status_id uuid REFERENCES ewms.inventory_statuses(id),
    include_zero_balance boolean NOT NULL DEFAULT false,
    selection_criteria jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (tenant_id, cycle_count_plan_id)
        REFERENCES ewms.cycle_count_plans(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, inventory_lot_id)
        REFERENCES ewms.inventory_lots(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, lpn_id)
        REFERENCES ewms.lpns(tenant_id, id) ON DELETE RESTRICT,
    UNIQUE (cycle_count_plan_id, scope_sequence),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_cycle_count_scope_seq CHECK (scope_sequence > 0),
    CONSTRAINT ck_cycle_count_scope_target CHECK (
        num_nonnulls(owner_partner_id,zone_id,location_id,item_id,inventory_lot_id,lpn_id,inventory_status_id) >= 1
    )
);

CREATE TABLE IF NOT EXISTS ewms.cycle_count_tasks (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    count_task_no varchar(100) NOT NULL,
    cycle_count_plan_id uuid NOT NULL,
    cycle_count_scope_id uuid,
    warehouse_id uuid NOT NULL REFERENCES ewms.warehouses(id),
    location_id uuid NOT NULL REFERENCES ewms.warehouse_locations(id),
    owner_partner_id uuid REFERENCES ewms.business_partners(id),
    count_round integer NOT NULL DEFAULT 1,
    assigned_user_id uuid REFERENCES ewms.users(id),
    assigned_at timestamptz,
    started_at timestamptz,
    completed_at timestamptz,
    blind_count boolean NOT NULL DEFAULT true,
    status varchar(20) NOT NULL DEFAULT 'OPEN',
    priority integer NOT NULL DEFAULT 100,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, count_task_no),
    UNIQUE (tenant_id, id),
    FOREIGN KEY (tenant_id, cycle_count_plan_id)
        REFERENCES ewms.cycle_count_plans(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, cycle_count_scope_id)
        REFERENCES ewms.cycle_count_scopes(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_cycle_count_task_round CHECK (count_round > 0),
    CONSTRAINT ck_cycle_count_task_status CHECK (status IN (
        'OPEN','ASSIGNED','IN_PROGRESS','SUBMITTED','RECOUNT_REQUIRED','APPROVED','COMPLETED','CANCELLED'
    )),
    CONSTRAINT ck_cycle_count_task_dates CHECK (completed_at IS NULL OR started_at IS NULL OR completed_at >= started_at)
);

CREATE TABLE IF NOT EXISTS ewms.cycle_count_observations (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    cycle_count_task_id uuid NOT NULL,
    observation_sequence integer NOT NULL,
    stock_bucket_id uuid,
    scanned_item_id uuid NOT NULL REFERENCES ewms.items(id),
    scanned_lot_no varchar(200),
    scanned_serial_no varchar(300),
    scanned_lpn_no varchar(200),
    counted_quantity numeric(24,8) NOT NULL,
    base_uom_code varchar(20) NOT NULL REFERENCES ewms.units_of_measure(uom_code),
    catch_weight numeric(24,8),
    catch_weight_uom_code varchar(20) REFERENCES ewms.units_of_measure(uom_code),
    counted_by uuid REFERENCES ewms.users(id),
    counted_at timestamptz NOT NULL DEFAULT now(),
    device_id uuid REFERENCES ewms.rf_devices(id),
    observation_source varchar(20) NOT NULL DEFAULT 'SCAN',
    notes text,
    FOREIGN KEY (tenant_id, cycle_count_task_id)
        REFERENCES ewms.cycle_count_tasks(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, stock_bucket_id)
        REFERENCES ewms.stock_buckets(tenant_id, id) ON DELETE RESTRICT,
    UNIQUE (cycle_count_task_id, observation_sequence),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_cycle_count_observation_seq CHECK (observation_sequence > 0),
    CONSTRAINT ck_cycle_count_observation_qty CHECK (
        counted_quantity >= 0 AND (catch_weight IS NULL OR catch_weight >= 0)
    ),
    CONSTRAINT ck_cycle_count_observation_source CHECK (observation_source IN ('SCAN','MANUAL','IMPORT','SENSOR','SYSTEM'))
);

CREATE TABLE IF NOT EXISTS ewms.cycle_count_results (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    cycle_count_task_id uuid NOT NULL,
    stock_bucket_id uuid,
    item_id uuid NOT NULL REFERENCES ewms.items(id),
    expected_quantity numeric(24,8) NOT NULL,
    counted_quantity numeric(24,8) NOT NULL,
    variance_quantity numeric(24,8) NOT NULL,
    variance_percent numeric(18,8),
    base_uom_code varchar(20) NOT NULL REFERENCES ewms.units_of_measure(uom_code),
    result_status varchar(20) NOT NULL DEFAULT 'PENDING',
    recount_task_id uuid,
    inventory_adjustment_line_id uuid,
    approved_by uuid REFERENCES ewms.users(id),
    approved_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (tenant_id, cycle_count_task_id)
        REFERENCES ewms.cycle_count_tasks(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, stock_bucket_id)
        REFERENCES ewms.stock_buckets(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, recount_task_id)
        REFERENCES ewms.cycle_count_tasks(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, inventory_adjustment_line_id)
        REFERENCES ewms.inventory_adjustment_lines(tenant_id, id) ON DELETE RESTRICT,
    UNIQUE (cycle_count_task_id, stock_bucket_id, item_id),
    CONSTRAINT ck_cycle_count_result_qty CHECK (
        expected_quantity >= 0 AND counted_quantity >= 0 AND
        variance_quantity = counted_quantity - expected_quantity
    ),
    CONSTRAINT ck_cycle_count_result_status CHECK (result_status IN (
        'PENDING','MATCHED','VARIANCE','RECOUNT_REQUIRED','APPROVED','ADJUSTED','REJECTED'
    ))
);

CREATE TABLE IF NOT EXISTS ewms.cycle_count_status_history (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    cycle_count_plan_id uuid NOT NULL,
    event_sequence integer NOT NULL,
    from_status varchar(20),
    to_status varchar(20) NOT NULL,
    actor_user_id uuid REFERENCES ewms.users(id) ON DELETE SET NULL,
    reason text,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    recorded_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (tenant_id, cycle_count_plan_id)
        REFERENCES ewms.cycle_count_plans(tenant_id, id) ON DELETE RESTRICT,
    UNIQUE (cycle_count_plan_id, event_sequence),
    CONSTRAINT ck_cycle_count_history_seq CHECK (event_sequence > 0)
);

CREATE TABLE IF NOT EXISTS ewms.inventory_freezes (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    freeze_no varchar(100) NOT NULL,
    warehouse_id uuid NOT NULL REFERENCES ewms.warehouses(id),
    cycle_count_plan_id uuid,
    owner_partner_id uuid REFERENCES ewms.business_partners(id),
    zone_id uuid REFERENCES ewms.warehouse_zones(id),
    location_id uuid REFERENCES ewms.warehouse_locations(id),
    item_id uuid REFERENCES ewms.items(id),
    inventory_lot_id uuid,
    lpn_id uuid,
    freeze_scope varchar(30) NOT NULL,
    blocked_operations varchar(40)[] NOT NULL DEFAULT ARRAY[
        'MOVE','PICK','SHIPMENT','ADJUSTMENT','TRANSFER','PUTAWAY','REPLENISHMENT',
        'STATUS_CHANGE','OWNER_TRANSFER','BONDED_MOVE','TRANSFORMATION','REPACK','RELABEL'
    ]::varchar(40)[],
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    frozen_by uuid REFERENCES ewms.users(id),
    frozen_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz,
    released_by uuid REFERENCES ewms.users(id),
    released_at timestamptz,
    reason text,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, freeze_no),
    UNIQUE (tenant_id, id),
    FOREIGN KEY (tenant_id, cycle_count_plan_id)
        REFERENCES ewms.cycle_count_plans(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, inventory_lot_id)
        REFERENCES ewms.inventory_lots(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, lpn_id)
        REFERENCES ewms.lpns(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_inventory_freeze_scope CHECK (freeze_scope IN (
        'WAREHOUSE','OWNER','ZONE','LOCATION','ITEM','LOT','LPN','COMPOSITE'
    )),
    CONSTRAINT ck_inventory_freeze_target CHECK (
        freeze_scope = 'WAREHOUSE' OR
        num_nonnulls(owner_partner_id,zone_id,location_id,item_id,inventory_lot_id,lpn_id) >= 1
    ),
    CONSTRAINT ck_inventory_freeze_status CHECK (status IN ('ACTIVE','EXPIRED','RELEASED','CANCELLED')),
    CONSTRAINT ck_inventory_freeze_dates CHECK (
        (expires_at IS NULL OR expires_at > frozen_at) AND
        (released_at IS NULL OR released_at >= frozen_at)
    )
);

CREATE TABLE IF NOT EXISTS ewms.inventory_snapshots (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    snapshot_no varchar(100) NOT NULL,
    snapshot_type varchar(30) NOT NULL DEFAULT 'DAILY',
    warehouse_id uuid NOT NULL REFERENCES ewms.warehouses(id),
    owner_partner_id uuid REFERENCES ewms.business_partners(id),
    as_of_at timestamptz NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'CREATING',
    row_count bigint NOT NULL DEFAULT 0,
    total_quantity numeric(30,8) NOT NULL DEFAULT 0,
    total_value numeric(30,8),
    currency_code char(3) REFERENCES ewms.currencies(currency_code),
    checksum_sha256 char(64),
    generated_by uuid REFERENCES ewms.users(id),
    generated_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, snapshot_no),
    UNIQUE (tenant_id, warehouse_id, owner_partner_id, snapshot_type, as_of_at),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_inventory_snapshot_type CHECK (snapshot_type IN (
        'DAILY','MONTH_END','YEAR_END','ON_DEMAND','COUNT','CUSTOMS','VALUATION'
    )),
    CONSTRAINT ck_inventory_snapshot_status CHECK (status IN ('CREATING','COMPLETED','FAILED','ARCHIVED')),
    CONSTRAINT ck_inventory_snapshot_counts CHECK (row_count >= 0),
    CONSTRAINT ck_inventory_snapshot_hash CHECK (
        checksum_sha256 IS NULL OR checksum_sha256 ~ '^[0-9A-Fa-f]{64}$'
    )
);

CREATE TABLE IF NOT EXISTS ewms.inventory_snapshot_lines (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    inventory_snapshot_id uuid NOT NULL,
    line_no bigint NOT NULL,
    stock_bucket_id uuid NOT NULL,
    on_hand_quantity numeric(24,8) NOT NULL,
    reserved_quantity numeric(24,8) NOT NULL,
    held_quantity numeric(24,8) NOT NULL,
    pending_out_quantity numeric(24,8) NOT NULL,
    pending_in_quantity numeric(24,8) NOT NULL,
    unit_cost numeric(24,8),
    total_value numeric(30,8),
    currency_code char(3) REFERENCES ewms.currencies(currency_code),
    last_transaction_id uuid,
    created_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (tenant_id, inventory_snapshot_id)
        REFERENCES ewms.inventory_snapshots(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, stock_bucket_id)
        REFERENCES ewms.stock_buckets(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, last_transaction_id)
        REFERENCES ewms.inventory_transaction_headers(tenant_id, id) ON DELETE RESTRICT,
    UNIQUE (inventory_snapshot_id, line_no),
    UNIQUE (inventory_snapshot_id, stock_bucket_id),
    CONSTRAINT ck_inventory_snapshot_line_no CHECK (line_no > 0),
    CONSTRAINT ck_inventory_snapshot_line_qty CHECK (
        reserved_quantity >= 0 AND held_quantity >= 0 AND pending_out_quantity >= 0 AND pending_in_quantity >= 0
    )
);

CREATE TABLE IF NOT EXISTS ewms.inventory_valuation_layers (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    valuation_layer_no varchar(120) NOT NULL,
    owner_partner_id uuid NOT NULL REFERENCES ewms.business_partners(id),
    warehouse_id uuid NOT NULL REFERENCES ewms.warehouses(id),
    item_id uuid NOT NULL REFERENCES ewms.items(id),
    inventory_lot_id uuid,
    source_transaction_id uuid NOT NULL,
    valuation_method varchar(20) NOT NULL,
    original_quantity numeric(24,8) NOT NULL,
    remaining_quantity numeric(24,8) NOT NULL,
    base_uom_code varchar(20) NOT NULL REFERENCES ewms.units_of_measure(uom_code),
    unit_cost numeric(24,8) NOT NULL,
    currency_code char(3) NOT NULL REFERENCES ewms.currencies(currency_code),
    exchange_rate numeric(24,12) NOT NULL DEFAULT 1,
    functional_unit_cost numeric(24,8) NOT NULL,
    received_at timestamptz NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'OPEN',
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, valuation_layer_no),
    UNIQUE (tenant_id, id),
    FOREIGN KEY (tenant_id, inventory_lot_id)
        REFERENCES ewms.inventory_lots(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, source_transaction_id)
        REFERENCES ewms.inventory_transaction_headers(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_inventory_valuation_method CHECK (valuation_method IN (
        'STANDARD','MOVING_AVERAGE','FIFO','LIFO','SPECIFIC'
    )),
    CONSTRAINT ck_inventory_valuation_qty CHECK (
        original_quantity > 0 AND remaining_quantity >= 0 AND remaining_quantity <= original_quantity
    ),
    CONSTRAINT ck_inventory_valuation_cost CHECK (
        unit_cost >= 0 AND exchange_rate > 0 AND functional_unit_cost >= 0
    ),
    CONSTRAINT ck_inventory_valuation_status CHECK (status IN ('OPEN','DEPLETED','ADJUSTED','REVERSED','CLOSED'))
);

CREATE TABLE IF NOT EXISTS ewms.inventory_valuation_movements (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    valuation_layer_id uuid NOT NULL,
    inventory_transaction_entry_id uuid NOT NULL,
    movement_quantity numeric(24,8) NOT NULL,
    unit_cost numeric(24,8) NOT NULL,
    movement_value numeric(30,8) NOT NULL,
    currency_code char(3) NOT NULL REFERENCES ewms.currencies(currency_code),
    movement_type varchar(20) NOT NULL,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (tenant_id, valuation_layer_id)
        REFERENCES ewms.inventory_valuation_layers(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, inventory_transaction_entry_id)
        REFERENCES ewms.inventory_transaction_entries(tenant_id, id) ON DELETE RESTRICT,
    UNIQUE (valuation_layer_id, inventory_transaction_entry_id, movement_type),
    CONSTRAINT ck_inventory_valuation_move_qty CHECK (movement_quantity <> 0),
    CONSTRAINT ck_inventory_valuation_move_cost CHECK (unit_cost >= 0 AND movement_value >= 0),
    CONSTRAINT ck_inventory_valuation_move_type CHECK (movement_type IN (
        'RECEIPT','ISSUE','ADJUSTMENT','REVALUATION','TRANSFER','REVERSAL'
    ))
);

CREATE TABLE IF NOT EXISTS ewms.inventory_transformations (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    transformation_no varchar(100) NOT NULL,
    transformation_type varchar(30) NOT NULL,
    warehouse_id uuid NOT NULL REFERENCES ewms.warehouses(id),
    owner_partner_id uuid NOT NULL REFERENCES ewms.business_partners(id),
    work_area_id uuid REFERENCES ewms.work_areas(id),
    bom_id uuid REFERENCES ewms.bill_of_materials(id),
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    planned_start_at timestamptz,
    started_at timestamptz,
    completed_at timestamptz,
    inventory_transaction_id uuid,
    reason_code_id uuid REFERENCES ewms.reason_codes(id),
    instructions text,
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_by uuid REFERENCES ewms.users(id),
    updated_by uuid REFERENCES ewms.users(id),
    approved_by uuid REFERENCES ewms.users(id),
    approved_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, transformation_no),
    UNIQUE (tenant_id, id),
    FOREIGN KEY (tenant_id, inventory_transaction_id)
        REFERENCES ewms.inventory_transaction_headers(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_inventory_transformation_type CHECK (transformation_type IN (
        'KIT','UNKIT','ASSEMBLY','DISASSEMBLY','REPACK','RELABEL','BLEND','GRADE','REWORK','CONVERSION'
    )),
    CONSTRAINT ck_inventory_transformation_status CHECK (status IN (
        'DRAFT','APPROVED','RELEASED','IN_PROGRESS','COMPLETED','POSTED','CANCELLED'
    )),
    CONSTRAINT ck_inventory_transformation_dates CHECK (
        (started_at IS NULL OR planned_start_at IS NULL OR started_at >= planned_start_at) AND
        (completed_at IS NULL OR started_at IS NULL OR completed_at >= started_at)
    )
);

CREATE TABLE IF NOT EXISTS ewms.inventory_transformation_inputs (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    inventory_transformation_id uuid NOT NULL,
    line_no integer NOT NULL,
    source_stock_bucket_id uuid NOT NULL,
    item_id uuid NOT NULL REFERENCES ewms.items(id),
    planned_quantity numeric(24,8) NOT NULL,
    consumed_quantity numeric(24,8) NOT NULL DEFAULT 0,
    scrap_quantity numeric(24,8) NOT NULL DEFAULT 0,
    base_uom_code varchar(20) NOT NULL REFERENCES ewms.units_of_measure(uom_code),
    inventory_transaction_entry_id uuid,
    FOREIGN KEY (tenant_id, inventory_transformation_id)
        REFERENCES ewms.inventory_transformations(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, source_stock_bucket_id)
        REFERENCES ewms.stock_buckets(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, inventory_transaction_entry_id)
        REFERENCES ewms.inventory_transaction_entries(tenant_id, id) ON DELETE RESTRICT,
    UNIQUE (inventory_transformation_id, line_no),
    CONSTRAINT ck_inventory_transformation_input_no CHECK (line_no > 0),
    CONSTRAINT ck_inventory_transformation_input_qty CHECK (
        planned_quantity > 0 AND consumed_quantity >= 0 AND scrap_quantity >= 0 AND
        consumed_quantity + scrap_quantity <= planned_quantity
    )
);

CREATE TABLE IF NOT EXISTS ewms.inventory_transformation_outputs (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    inventory_transformation_id uuid NOT NULL,
    line_no integer NOT NULL,
    destination_stock_bucket_id uuid NOT NULL,
    item_id uuid NOT NULL REFERENCES ewms.items(id),
    planned_quantity numeric(24,8) NOT NULL,
    produced_quantity numeric(24,8) NOT NULL DEFAULT 0,
    rejected_quantity numeric(24,8) NOT NULL DEFAULT 0,
    base_uom_code varchar(20) NOT NULL REFERENCES ewms.units_of_measure(uom_code),
    output_lot_id uuid,
    inventory_transaction_entry_id uuid,
    FOREIGN KEY (tenant_id, inventory_transformation_id)
        REFERENCES ewms.inventory_transformations(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, destination_stock_bucket_id)
        REFERENCES ewms.stock_buckets(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, output_lot_id)
        REFERENCES ewms.inventory_lots(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, inventory_transaction_entry_id)
        REFERENCES ewms.inventory_transaction_entries(tenant_id, id) ON DELETE RESTRICT,
    UNIQUE (inventory_transformation_id, line_no),
    CONSTRAINT ck_inventory_transformation_output_no CHECK (line_no > 0),
    CONSTRAINT ck_inventory_transformation_output_qty CHECK (
        planned_quantity > 0 AND produced_quantity >= 0 AND rejected_quantity >= 0
    )
);

CREATE TABLE IF NOT EXISTS ewms.inventory_transformation_status_history (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    inventory_transformation_id uuid NOT NULL,
    event_sequence integer NOT NULL,
    from_status varchar(20),
    to_status varchar(20) NOT NULL,
    actor_user_id uuid REFERENCES ewms.users(id) ON DELETE SET NULL,
    reason text,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    recorded_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (tenant_id, inventory_transformation_id)
        REFERENCES ewms.inventory_transformations(tenant_id, id) ON DELETE RESTRICT,
    UNIQUE (inventory_transformation_id, event_sequence),
    CONSTRAINT ck_inventory_transform_hist_seq CHECK (event_sequence > 0)
);

CREATE TABLE IF NOT EXISTS ewms.inventory_reconciliation_runs (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    reconciliation_no varchar(100) NOT NULL,
    warehouse_id uuid NOT NULL REFERENCES ewms.warehouses(id),
    owner_partner_id uuid REFERENCES ewms.business_partners(id),
    reconciliation_type varchar(30) NOT NULL,
    as_of_at timestamptz NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'PENDING',
    checked_count bigint NOT NULL DEFAULT 0,
    exception_count bigint NOT NULL DEFAULT 0,
    started_at timestamptz,
    completed_at timestamptz,
    created_by uuid REFERENCES ewms.users(id),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, reconciliation_no),
    UNIQUE (tenant_id, id),
    CONSTRAINT ck_inventory_reconciliation_type CHECK (reconciliation_type IN (
        'LEDGER_BALANCE','RESERVATION_BALANCE','HOLD_BALANCE','SERIAL_BALANCE','LPN_BALANCE','BONDED_CUSTOMS','SNAPSHOT'
    )),
    CONSTRAINT ck_inventory_reconciliation_status CHECK (status IN ('PENDING','RUNNING','COMPLETED','FAILED','REVIEWED')),
    CONSTRAINT ck_inventory_reconciliation_counts CHECK (checked_count >= 0 AND exception_count >= 0),
    CONSTRAINT ck_inventory_reconciliation_dates CHECK (completed_at IS NULL OR started_at IS NULL OR completed_at >= started_at)
);

CREATE TABLE IF NOT EXISTS ewms.inventory_reconciliation_details (
    id uuid PRIMARY KEY DEFAULT ewms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES ewms.tenants(id),
    inventory_reconciliation_run_id uuid NOT NULL,
    stock_bucket_id uuid,
    serial_number_id uuid,
    lpn_id uuid,
    expected_quantity numeric(24,8),
    actual_quantity numeric(24,8),
    variance_quantity numeric(24,8),
    exception_code varchar(80) NOT NULL,
    severity varchar(20) NOT NULL DEFAULT 'MEDIUM',
    status varchar(20) NOT NULL DEFAULT 'OPEN',
    resolution_note text,
    resolved_by uuid REFERENCES ewms.users(id),
    resolved_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (tenant_id, inventory_reconciliation_run_id)
        REFERENCES ewms.inventory_reconciliation_runs(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, stock_bucket_id)
        REFERENCES ewms.stock_buckets(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, serial_number_id)
        REFERENCES ewms.serial_numbers(tenant_id, id) ON DELETE RESTRICT,
    FOREIGN KEY (tenant_id, lpn_id)
        REFERENCES ewms.lpns(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_inventory_reconciliation_target CHECK (
        num_nonnulls(stock_bucket_id,serial_number_id,lpn_id) >= 1
    ),
    CONSTRAINT ck_inventory_reconciliation_severity CHECK (severity IN ('LOW','MEDIUM','HIGH','CRITICAL')),
    CONSTRAINT ck_inventory_reconciliation_detail_status CHECK (status IN ('OPEN','ACKNOWLEDGED','RESOLVED','WAIVED'))
);

-- Private, transaction-scoped capability records. A client-supplied custom GUC is never trusted
-- on its own: balance/header guards require an unexpired random token stored here for the same
-- backend PID and top-level transaction. Runtime roles must not own this table or schema.
CREATE TABLE IF NOT EXISTS ewms.inventory_write_authorizations (
    authorization_token uuid PRIMARY KEY,
    backend_pid integer NOT NULL,
    transaction_id bigint NOT NULL,
    authorization_scope varchar(20) NOT NULL,
    authorized_role name NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL DEFAULT (now() + interval '5 minutes'),
    UNIQUE (backend_pid, transaction_id, authorization_scope),
    CONSTRAINT ck_inventory_write_auth_scope CHECK (
        authorization_scope IN ('POSTING','RESERVATION','HOLD','RECONCILIATION')
    ),
    CONSTRAINT ck_inventory_write_auth_expiry CHECK (expires_at > created_at)
);

REVOKE ALL ON ewms.inventory_write_authorizations FROM PUBLIC;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON ewms.inventory_balances FROM PUBLIC;
REVOKE UPDATE (posting_status, posted_at, posted_by) ON ewms.inventory_transaction_headers FROM PUBLIC;

ALTER TABLE ewms.serial_status_history
    DROP CONSTRAINT IF EXISTS fk_serial_history_transaction;
ALTER TABLE ewms.serial_status_history
    ADD CONSTRAINT fk_serial_history_transaction
    FOREIGN KEY (tenant_id, inventory_transaction_id)
    REFERENCES ewms.inventory_transaction_headers(tenant_id, id) ON DELETE RESTRICT;

ALTER TABLE ewms.lpn_status_history
    DROP CONSTRAINT IF EXISTS fk_lpn_status_history_transaction;
ALTER TABLE ewms.lpn_status_history
    ADD CONSTRAINT fk_lpn_status_history_transaction
    FOREIGN KEY (tenant_id, inventory_transaction_id)
    REFERENCES ewms.inventory_transaction_headers(tenant_id, id) ON DELETE RESTRICT;

ALTER TABLE ewms.lpn_location_history
    DROP CONSTRAINT IF EXISTS fk_lpn_location_history_transaction;
ALTER TABLE ewms.lpn_location_history
    ADD CONSTRAINT fk_lpn_location_history_transaction
    FOREIGN KEY (tenant_id, inventory_transaction_id)
    REFERENCES ewms.inventory_transaction_headers(tenant_id, id) ON DELETE RESTRICT;

CREATE OR REPLACE FUNCTION ewms.open_inventory_write_authorization(p_scope varchar)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, ewms
AS $function$
DECLARE
    new_token uuid := ewms.generate_uuid();
BEGIN
    IF p_scope NOT IN ('POSTING','RESERVATION','HOLD','RECONCILIATION') THEN
        RAISE EXCEPTION 'Unsupported inventory write authorization scope %', p_scope;
    END IF;
    DELETE FROM ewms.inventory_write_authorizations
     WHERE expires_at <= now()
        OR (backend_pid = pg_backend_pid()
            AND transaction_id = txid_current()
            AND authorization_scope = p_scope);
    INSERT INTO ewms.inventory_write_authorizations (
        authorization_token, backend_pid, transaction_id, authorization_scope,
        authorized_role, expires_at
    ) VALUES (
        new_token, pg_backend_pid(), txid_current(), p_scope,
        current_user, now() + interval '5 minutes'
    );
    PERFORM set_config('ewms.inventory_write_token', new_token::text, true);
    RETURN new_token;
END;
$function$;

CREATE OR REPLACE FUNCTION ewms.close_inventory_write_authorization(p_token uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, ewms
AS $function$
BEGIN
    DELETE FROM ewms.inventory_write_authorizations
     WHERE authorization_token = p_token
       AND backend_pid = pg_backend_pid()
       AND transaction_id = txid_current();
    PERFORM set_config('ewms.inventory_write_token', '', true);
END;
$function$;

CREATE OR REPLACE FUNCTION ewms.assert_inventory_write_authorized(p_scope varchar DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, ewms
AS $function$
DECLARE
    token_text text;
    supplied_token uuid;
BEGIN
    token_text := NULLIF(current_setting('ewms.inventory_write_token', true), '');
    IF token_text IS NULL THEN
        RAISE EXCEPTION 'Controlled inventory write authorization is missing';
    END IF;
    BEGIN
        supplied_token := token_text::uuid;
    EXCEPTION WHEN invalid_text_representation THEN
        RAISE EXCEPTION 'Controlled inventory write authorization is invalid';
    END;
    IF NOT EXISTS (
        SELECT 1
          FROM ewms.inventory_write_authorizations a
         WHERE a.authorization_token = supplied_token
           AND a.backend_pid = pg_backend_pid()
           AND a.transaction_id = txid_current()
           AND a.expires_at > now()
           AND (p_scope IS NULL OR a.authorization_scope = p_scope)
    ) THEN
        RAISE EXCEPTION 'Controlled inventory write authorization is not valid for this transaction';
    END IF;
END;
$function$;

REVOKE ALL ON FUNCTION ewms.open_inventory_write_authorization(varchar) FROM PUBLIC;
REVOKE ALL ON FUNCTION ewms.close_inventory_write_authorization(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION ewms.assert_inventory_write_authorized(varchar) FROM PUBLIC;

CREATE OR REPLACE FUNCTION ewms.validate_lpn_parent()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    parent_warehouse_id uuid;
BEGIN
    IF NEW.parent_lpn_id IS NULL THEN
        RETURN NEW;
    END IF;

    IF NEW.parent_lpn_id = NEW.id THEN
        RAISE EXCEPTION 'LPN cannot be its own parent';
    END IF;

    SELECT warehouse_id INTO parent_warehouse_id
      FROM ewms.lpns
     WHERE tenant_id = NEW.tenant_id AND id = NEW.parent_lpn_id;
    IF NOT FOUND OR parent_warehouse_id <> NEW.warehouse_id THEN
        RAISE EXCEPTION 'Parent LPN must exist in the same tenant and warehouse';
    END IF;

    IF EXISTS (
        WITH RECURSIVE ancestors AS (
            SELECT l.id, l.parent_lpn_id, ARRAY[l.id]::uuid[] AS path
              FROM ewms.lpns l
             WHERE l.tenant_id = NEW.tenant_id AND l.id = NEW.parent_lpn_id
            UNION ALL
            SELECT l.id, l.parent_lpn_id, a.path || l.id
              FROM ewms.lpns l
              JOIN ancestors a ON l.id = a.parent_lpn_id
             WHERE l.tenant_id = NEW.tenant_id
               AND NOT l.id = ANY(a.path)
        )
        SELECT 1 FROM ancestors WHERE id = NEW.id
    ) THEN
        RAISE EXCEPTION 'LPN hierarchy cycle detected for %', NEW.lpn_no;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION ewms.validate_stock_bucket()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    item_row ewms.items%ROWTYPE;
    lot_row ewms.inventory_lots%ROWTYPE;
    serial_row ewms.serial_numbers%ROWTYPE;
    lpn_row ewms.lpns%ROWTYPE;
    location_warehouse_id uuid;
    client_row ewms.warehouse_clients%ROWTYPE;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ewms.warehouses
         WHERE id = NEW.warehouse_id AND tenant_id = NEW.tenant_id AND deleted_at IS NULL
    ) THEN
        RAISE EXCEPTION 'Stock bucket warehouse is outside its tenant or inactive';
    END IF;

    SELECT * INTO item_row
      FROM ewms.items
     WHERE id = NEW.item_id AND tenant_id = NEW.tenant_id AND deleted_at IS NULL;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Stock bucket item is outside its tenant or deleted';
    END IF;

    SELECT * INTO client_row
      FROM ewms.warehouse_clients
     WHERE tenant_id = NEW.tenant_id
       AND warehouse_id = NEW.warehouse_id
       AND owner_partner_id = NEW.owner_partner_id
       AND status IN ('ONBOARDING','ACTIVE','ON_HOLD')
       AND (valid_to IS NULL OR valid_to >= CURRENT_DATE);
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Inventory owner is not configured for this warehouse';
    END IF;

    IF NEW.location_id IS NOT NULL THEN
        SELECT warehouse_id INTO location_warehouse_id
          FROM ewms.warehouse_locations
         WHERE id = NEW.location_id AND tenant_id = NEW.tenant_id AND deleted_at IS NULL;
        IF NOT FOUND OR location_warehouse_id <> NEW.warehouse_id THEN
            RAISE EXCEPTION 'Stock bucket location must belong to the same warehouse and tenant';
        END IF;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM ewms.inventory_statuses
         WHERE id = NEW.inventory_status_id
           AND (tenant_id IS NULL OR tenant_id = NEW.tenant_id)
           AND is_active
    ) THEN
        RAISE EXCEPTION 'Inventory status is not valid for this tenant';
    END IF;

    IF NEW.inventory_lot_id IS NOT NULL THEN
        SELECT * INTO lot_row
          FROM ewms.inventory_lots
         WHERE id = NEW.inventory_lot_id AND tenant_id = NEW.tenant_id AND deleted_at IS NULL;
        IF NOT FOUND OR lot_row.owner_partner_id <> NEW.owner_partner_id OR lot_row.item_id <> NEW.item_id THEN
            RAISE EXCEPTION 'Inventory lot does not match stock bucket tenant, owner, or item';
        END IF;
        IF item_row.expiry_controlled AND lot_row.expires_on IS NULL THEN
            RAISE EXCEPTION 'Expiry-controlled item requires an expiry date on its lot';
        END IF;
    ELSIF item_row.lot_controlled THEN
        RAISE EXCEPTION 'Lot-controlled item requires inventory_lot_id';
    END IF;

    IF NEW.serial_number_id IS NOT NULL THEN
        SELECT * INTO serial_row
          FROM ewms.serial_numbers
         WHERE id = NEW.serial_number_id AND tenant_id = NEW.tenant_id AND deleted_at IS NULL;
        IF NOT FOUND OR serial_row.owner_partner_id <> NEW.owner_partner_id OR serial_row.item_id <> NEW.item_id THEN
            RAISE EXCEPTION 'Serial number does not match stock bucket tenant, owner, or item';
        END IF;
        IF NEW.inventory_lot_id IS NOT NULL
           AND serial_row.inventory_lot_id IS NOT NULL
           AND serial_row.inventory_lot_id <> NEW.inventory_lot_id THEN
            RAISE EXCEPTION 'Serial number lot differs from stock bucket lot';
        END IF;
    ELSIF item_row.serial_controlled THEN
        RAISE EXCEPTION 'Serial-controlled item requires serial_number_id';
    END IF;

    IF NEW.lpn_id IS NOT NULL THEN
        SELECT * INTO lpn_row
          FROM ewms.lpns
         WHERE id = NEW.lpn_id AND tenant_id = NEW.tenant_id AND deleted_at IS NULL;
        IF NOT FOUND OR lpn_row.warehouse_id <> NEW.warehouse_id THEN
            RAISE EXCEPTION 'LPN does not match stock bucket tenant or warehouse';
        END IF;
        IF NOT client_row.allow_mixed_owner_lpn AND EXISTS (
            SELECT 1 FROM ewms.stock_buckets b
             WHERE b.tenant_id = NEW.tenant_id AND b.lpn_id = NEW.lpn_id
               AND b.owner_partner_id <> NEW.owner_partner_id AND b.id <> NEW.id
        ) THEN
            RAISE EXCEPTION 'Warehouse-client policy prohibits mixed-owner LPNs';
        END IF;
        IF NOT client_row.allow_mixed_item_lpn AND EXISTS (
            SELECT 1 FROM ewms.stock_buckets b
             WHERE b.tenant_id = NEW.tenant_id AND b.lpn_id = NEW.lpn_id
               AND b.item_id <> NEW.item_id AND b.id <> NEW.id
        ) THEN
            RAISE EXCEPTION 'Warehouse-client policy prohibits mixed-item LPNs';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION ewms.protect_stock_bucket_dimensions()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    IF ROW(
        OLD.tenant_id, OLD.owner_partner_id, OLD.warehouse_id, OLD.location_id,
        OLD.item_id, OLD.inventory_status_id, OLD.inventory_lot_id, OLD.serial_number_id,
        OLD.lpn_id, OLD.country_of_origin, OLD.account_type,
        OLD.customs_legal_status_code, OLD.bonded_cargo_reference, OLD.customs_declaration_line_id
    ) IS DISTINCT FROM ROW(
        NEW.tenant_id, NEW.owner_partner_id, NEW.warehouse_id, NEW.location_id,
        NEW.item_id, NEW.inventory_status_id, NEW.inventory_lot_id, NEW.serial_number_id,
        NEW.lpn_id, NEW.country_of_origin, NEW.account_type,
        NEW.customs_legal_status_code, NEW.bonded_cargo_reference, NEW.customs_declaration_line_id
    ) AND (
        EXISTS (SELECT 1 FROM ewms.inventory_transaction_entries WHERE stock_bucket_id = OLD.id) OR
        EXISTS (
            SELECT 1 FROM ewms.inventory_balances
             WHERE stock_bucket_id = OLD.id AND
                   (on_hand_quantity <> 0 OR reserved_quantity <> 0 OR held_quantity <> 0 OR
                    pending_out_quantity <> 0 OR pending_in_quantity <> 0)
        )
    ) THEN
        RAISE EXCEPTION 'Posted stock bucket dimensions are immutable; use a balanced inventory transaction';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION ewms.validate_inventory_entry()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    tx_status varchar(20);
    bucket_item_id uuid;
    item_base_uom varchar(20);
    bucket_serial_id uuid;
BEGIN
    SELECT posting_status INTO tx_status
      FROM ewms.inventory_transaction_headers
     WHERE tenant_id = NEW.tenant_id AND id = NEW.inventory_transaction_id
     FOR UPDATE;
    IF NOT FOUND OR tx_status <> 'DRAFT' THEN
        RAISE EXCEPTION 'Inventory entries may be inserted or changed only while the transaction is DRAFT';
    END IF;

    SELECT item_id, serial_number_id INTO bucket_item_id, bucket_serial_id
      FROM ewms.stock_buckets
     WHERE tenant_id = NEW.tenant_id AND id = NEW.stock_bucket_id;
    SELECT base_uom_code INTO item_base_uom
      FROM ewms.items
     WHERE tenant_id = NEW.tenant_id AND id = NEW.item_id;
    IF bucket_item_id IS DISTINCT FROM NEW.item_id THEN
        RAISE EXCEPTION 'Inventory entry item must equal stock bucket item';
    END IF;
    IF item_base_uom IS DISTINCT FROM NEW.base_uom_code THEN
        RAISE EXCEPTION 'Inventory entry base UOM must equal item base UOM';
    END IF;
    IF bucket_serial_id IS NOT NULL AND abs(NEW.signed_quantity) > 1 THEN
        RAISE EXCEPTION 'A serial-number bucket entry cannot move more than one base unit';
    END IF;
    IF (NEW.entered_quantity IS NULL) <> (NEW.entered_uom_code IS NULL) THEN
        RAISE EXCEPTION 'Entered quantity and UOM must be supplied together';
    END IF;
    IF (NEW.extended_value IS NULL) <> (NEW.currency_code IS NULL) THEN
        RAISE EXCEPTION 'Extended value and currency must be supplied together';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION ewms.guard_inventory_entry_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    tx_id uuid;
    tx_status varchar(20);
BEGIN
    tx_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.inventory_transaction_id ELSE NEW.inventory_transaction_id END;
    SELECT posting_status INTO tx_status FROM ewms.inventory_transaction_headers WHERE id = tx_id FOR UPDATE;
    IF tx_status <> 'DRAFT' THEN
        RAISE EXCEPTION 'Validated or posted inventory transaction entries are immutable';
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION ewms.guard_inventory_transaction_header()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, ewms
AS $function$
BEGIN
    IF TG_OP = 'DELETE' THEN
        IF OLD.posting_status IN ('VALIDATED','POSTED') THEN
            RAISE EXCEPTION 'Validated or posted inventory transaction headers are immutable';
        END IF;
        RETURN OLD;
    END IF;
    IF OLD.posting_status = 'POSTED' THEN
        RAISE EXCEPTION 'Posted inventory transaction headers are immutable; create a REVERSAL transaction';
    END IF;
    IF NEW.posting_status = 'POSTED' THEN
        PERFORM ewms.assert_inventory_write_authorized('POSTING');
    END IF;
    IF OLD.posting_status = 'VALIDATED' AND NEW.posting_status NOT IN ('VALIDATED','POSTED','FAILED','CANCELLED') THEN
        RAISE EXCEPTION 'Invalid inventory posting status transition';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION ewms.guard_inventory_balance_write()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, ewms
AS $function$
BEGIN
    PERFORM ewms.assert_inventory_write_authorized(NULL);
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION ewms.validate_inventory_balance()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    bucket_account_type varchar(30);
    bucket_serial_id uuid;
    allow_negative boolean;
BEGIN
    SELECT sb.account_type, sb.serial_number_id, COALESCE(wc.allow_negative_inventory, false)
      INTO bucket_account_type, bucket_serial_id, allow_negative
      FROM ewms.stock_buckets sb
      LEFT JOIN ewms.warehouse_clients wc
        ON wc.tenant_id = sb.tenant_id
       AND wc.warehouse_id = sb.warehouse_id
       AND wc.owner_partner_id = sb.owner_partner_id
     WHERE sb.tenant_id = NEW.tenant_id AND sb.id = NEW.stock_bucket_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Inventory balance stock bucket is invalid';
    END IF;

    IF bucket_account_type = 'PHYSICAL' THEN
        IF NEW.on_hand_quantity < 0 AND NOT allow_negative THEN
            RAISE EXCEPTION 'Negative physical inventory is disabled for this warehouse client';
        END IF;
        IF NEW.reserved_quantity + NEW.held_quantity + NEW.pending_out_quantity > GREATEST(NEW.on_hand_quantity, 0) THEN
            RAISE EXCEPTION 'Reserved, held, and pending-out quantities exceed physical on-hand inventory';
        END IF;
        IF bucket_serial_id IS NOT NULL AND (NEW.on_hand_quantity < 0 OR NEW.on_hand_quantity > 1) THEN
            RAISE EXCEPTION 'Serial-number physical balance must be zero or one';
        END IF;
    ELSIF NEW.reserved_quantity <> 0 OR NEW.held_quantity <> 0 OR NEW.pending_out_quantity <> 0 THEN
        RAISE EXCEPTION 'Reservations, holds, and pending-out quantities are allowed only on PHYSICAL buckets';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION ewms.project_inventory_reservation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, ewms
AS $function$
DECLARE
    old_projected numeric(24,8) := 0;
    new_projected numeric(24,8) := 0;
    authorization_token uuid;
BEGIN
    authorization_token := ewms.open_inventory_write_authorization('RESERVATION');
    IF TG_OP IN ('UPDATE','DELETE') AND OLD.status IN ('ACTIVE','PARTIALLY_CONSUMED') THEN
        old_projected := OLD.reserved_quantity;
        UPDATE ewms.inventory_balances
           SET reserved_quantity = reserved_quantity - old_projected,
               updated_at = now()
         WHERE tenant_id = OLD.tenant_id AND stock_bucket_id = OLD.stock_bucket_id;
        IF NOT FOUND THEN RAISE EXCEPTION 'Reservation source balance does not exist'; END IF;
    END IF;
    IF TG_OP IN ('INSERT','UPDATE') AND NEW.status IN ('ACTIVE','PARTIALLY_CONSUMED') THEN
        new_projected := NEW.reserved_quantity;
        UPDATE ewms.inventory_balances
           SET reserved_quantity = reserved_quantity + new_projected,
               updated_at = now()
         WHERE tenant_id = NEW.tenant_id AND stock_bucket_id = NEW.stock_bucket_id;
        IF NOT FOUND THEN RAISE EXCEPTION 'Reservation target balance does not exist'; END IF;
    END IF;
    PERFORM ewms.close_inventory_write_authorization(authorization_token);
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION ewms.project_inventory_hold()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, ewms
AS $function$
DECLARE
    old_projected numeric(24,8) := 0;
    new_projected numeric(24,8) := 0;
    authorization_token uuid;
BEGIN
    IF TG_OP IN ('INSERT','UPDATE') AND NEW.released_quantity <> COALESCE((
        SELECT sum(r.released_quantity)
          FROM ewms.inventory_hold_releases r
         WHERE r.inventory_hold_id = NEW.id
    ), 0) THEN
        RAISE EXCEPTION 'Inventory hold released quantity must equal its append-only release records';
    END IF;
    authorization_token := ewms.open_inventory_write_authorization('HOLD');
    IF TG_OP IN ('UPDATE','DELETE') AND OLD.status IN ('ACTIVE','PARTIALLY_RELEASED') THEN
        old_projected := OLD.held_quantity - OLD.released_quantity;
        UPDATE ewms.inventory_balances
           SET held_quantity = held_quantity - old_projected,
               updated_at = now()
         WHERE tenant_id = OLD.tenant_id AND stock_bucket_id = OLD.stock_bucket_id;
        IF NOT FOUND THEN RAISE EXCEPTION 'Hold source balance does not exist'; END IF;
    END IF;
    IF TG_OP IN ('INSERT','UPDATE') AND NEW.status IN ('ACTIVE','PARTIALLY_RELEASED') THEN
        new_projected := NEW.held_quantity - NEW.released_quantity;
        UPDATE ewms.inventory_balances
           SET held_quantity = held_quantity + new_projected,
               updated_at = now()
         WHERE tenant_id = NEW.tenant_id AND stock_bucket_id = NEW.stock_bucket_id;
        IF NOT FOUND THEN RAISE EXCEPTION 'Hold target balance does not exist'; END IF;
    END IF;
    PERFORM ewms.close_inventory_write_authorization(authorization_token);
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION ewms.apply_inventory_hold_release()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, ewms
AS $function$
DECLARE
    hold_row ewms.inventory_holds%ROWTYPE;
    total_released numeric(24,8);
BEGIN
    SELECT * INTO hold_row
      FROM ewms.inventory_holds
     WHERE tenant_id = NEW.tenant_id AND id = NEW.inventory_hold_id
     FOR UPDATE;
    IF NOT FOUND OR hold_row.status NOT IN ('ACTIVE','PARTIALLY_RELEASED') THEN
        RAISE EXCEPTION 'Inventory hold is not releasable';
    END IF;
    SELECT sum(released_quantity) INTO total_released
      FROM ewms.inventory_hold_releases
     WHERE inventory_hold_id = NEW.inventory_hold_id;
    IF total_released > hold_row.held_quantity THEN
        RAISE EXCEPTION 'Inventory hold releases exceed held quantity';
    END IF;
    UPDATE ewms.inventory_holds
       SET released_quantity = total_released,
           status = CASE WHEN total_released = held_quantity THEN 'RELEASED' ELSE 'PARTIALLY_RELEASED' END,
           released_by = NEW.released_by,
           released_at = NEW.released_at,
           updated_at = now()
     WHERE id = NEW.inventory_hold_id;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION ewms.validate_receipt_inventory_allocation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, ewms
AS $function$
DECLARE
    posting_row ewms.receipt_inventory_postings%ROWTYPE;
    receipt_row ewms.receipts%ROWTYPE;
    receipt_line_row ewms.receipt_lines%ROWTYPE;
    transaction_row ewms.inventory_transaction_headers%ROWTYPE;
    entry_row ewms.inventory_transaction_entries%ROWTYPE;
    bucket_row ewms.stock_buckets%ROWTYPE;
    lot_row ewms.inventory_lots%ROWTYPE;
    serial_row ewms.serial_numbers%ROWTYPE;
    accepted_base_quantity numeric(24,8);
    existing_line_quantity numeric(24,8);
    existing_entry_quantity numeric(24,8);
    excluded_id uuid;
BEGIN
    excluded_id := CASE WHEN TG_OP = 'UPDATE' THEN OLD.id ELSE NULL END;
    SELECT * INTO posting_row
      FROM ewms.receipt_inventory_postings
     WHERE tenant_id = NEW.tenant_id AND id = NEW.receipt_inventory_posting_id
     FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Receipt inventory allocation references an invalid tenant-scoped posting'
            USING ERRCODE = '23503';
    END IF;
    SELECT * INTO transaction_row
      FROM ewms.inventory_transaction_headers
     WHERE tenant_id = NEW.tenant_id AND id = posting_row.inventory_transaction_id
     FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Receipt inventory posting references an invalid tenant-scoped transaction'
            USING ERRCODE = '23503';
    END IF;
    SELECT * INTO receipt_row
      FROM ewms.receipts
     WHERE tenant_id = NEW.tenant_id AND id = posting_row.receipt_id
     FOR SHARE;
    SELECT * INTO receipt_line_row
      FROM ewms.receipt_lines
     WHERE tenant_id = NEW.tenant_id AND id = NEW.receipt_line_id
     FOR UPDATE;
    SELECT * INTO entry_row
      FROM ewms.inventory_transaction_entries
     WHERE tenant_id = NEW.tenant_id AND id = NEW.inventory_transaction_entry_id
     FOR UPDATE;
    SELECT * INTO bucket_row
      FROM ewms.stock_buckets
     WHERE tenant_id = NEW.tenant_id AND id = NEW.destination_stock_bucket_id
     FOR SHARE;
    IF receipt_row.id IS NULL OR receipt_line_row.id IS NULL OR entry_row.id IS NULL OR bucket_row.id IS NULL THEN
        RAISE EXCEPTION 'Receipt inventory allocation references an invalid tenant-scoped object';
    END IF;
    IF posting_row.posting_type = 'REVERSAL' THEN
        RAISE EXCEPTION 'Receipt reversal postings use an exact REVERSAL transaction and cannot carry receipt allocations'
            USING ERRCODE = '23514';
    END IF;
    IF posting_row.status NOT IN ('CREATED','VALIDATED')
       OR transaction_row.posting_status NOT IN ('DRAFT','VALIDATED') THEN
        RAISE EXCEPTION 'Receipt inventory allocations are immutable after transaction posting';
    END IF;
    IF receipt_line_row.receipt_id <> posting_row.receipt_id THEN
        RAISE EXCEPTION 'Receipt inventory posting and receipt line belong to different receipts';
    END IF;
    accepted_base_quantity := CASE
        WHEN receipt_line_row.received_quantity = 0 THEN 0
        ELSE receipt_line_row.accepted_quantity
             * receipt_line_row.received_base_quantity / receipt_line_row.received_quantity
    END;
    IF transaction_row.transaction_type <> 'RECEIPT'
       OR transaction_row.warehouse_id <> receipt_row.warehouse_id
       OR transaction_row.owner_partner_id <> receipt_row.owner_partner_id
       OR receipt_line_row.owner_partner_id <> receipt_row.owner_partner_id THEN
        RAISE EXCEPTION 'Receipt allocation transaction/line warehouse or owner differs from receipt'
            USING ERRCODE = '23514';
    END IF;
    IF entry_row.inventory_transaction_id <> posting_row.inventory_transaction_id
       OR entry_row.stock_bucket_id <> NEW.destination_stock_bucket_id
       OR entry_row.signed_quantity <= 0
       OR entry_row.entry_role NOT IN ('DESTINATION','STOCK')
       OR bucket_row.account_type <> 'PHYSICAL' THEN
        RAISE EXCEPTION 'Receipt allocation requires a positive entry in the linked transaction and destination bucket';
    END IF;
    IF receipt_line_row.item_id <> bucket_row.item_id
       OR receipt_line_row.owner_partner_id <> bucket_row.owner_partner_id
       OR bucket_row.warehouse_id <> receipt_row.warehouse_id
       OR receipt_line_row.base_uom_code <> NEW.base_uom_code
       OR entry_row.item_id <> receipt_line_row.item_id
       OR entry_row.base_uom_code <> NEW.base_uom_code THEN
        RAISE EXCEPTION 'Receipt allocation item, owner, warehouse, or base UOM mismatch';
    END IF;
    IF NEW.inventory_lot_id IS DISTINCT FROM bucket_row.inventory_lot_id
       OR NEW.serial_number_id IS DISTINCT FROM bucket_row.serial_number_id THEN
        RAISE EXCEPTION 'Receipt allocation lot/serial must equal destination bucket dimensions';
    END IF;
    IF NEW.receipt_lot_observation_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM ewms.receipt_lot_observations
         WHERE tenant_id = NEW.tenant_id AND id = NEW.receipt_lot_observation_id
           AND receipt_line_id = NEW.receipt_line_id
    ) THEN
        RAISE EXCEPTION 'Receipt lot observation does not belong to receipt line';
    END IF;
    IF NEW.receipt_serial_observation_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM ewms.receipt_serial_observations
         WHERE tenant_id = NEW.tenant_id AND id = NEW.receipt_serial_observation_id
           AND receipt_line_id = NEW.receipt_line_id
           AND (NEW.receipt_lot_observation_id IS NULL OR
                lot_observation_id IS NOT DISTINCT FROM NEW.receipt_lot_observation_id)
    ) THEN
        RAISE EXCEPTION 'Receipt serial observation does not belong to receipt line';
    END IF;
    IF NEW.inventory_lot_id IS NOT NULL THEN
        SELECT * INTO lot_row
          FROM ewms.inventory_lots
         WHERE tenant_id = NEW.tenant_id AND id = NEW.inventory_lot_id
         FOR SHARE;
        IF NOT FOUND
           OR lot_row.owner_partner_id <> receipt_line_row.owner_partner_id
           OR lot_row.item_id <> receipt_line_row.item_id
           OR lot_row.source_receipt_line_id IS DISTINCT FROM NEW.receipt_line_id
           OR lot_row.source_lot_observation_id IS DISTINCT FROM NEW.receipt_lot_observation_id THEN
            RAISE EXCEPTION 'Receipt allocation inventory lot does not preserve receipt line/observation dimensions'
                USING ERRCODE = '23514';
        END IF;
    ELSIF NEW.receipt_lot_observation_id IS NOT NULL THEN
        RAISE EXCEPTION 'A receipt lot observation requires its materialized inventory lot'
            USING ERRCODE = '23514';
    END IF;
    IF NEW.serial_number_id IS NOT NULL THEN
        SELECT * INTO serial_row
          FROM ewms.serial_numbers
         WHERE tenant_id = NEW.tenant_id AND id = NEW.serial_number_id
         FOR SHARE;
        IF NOT FOUND
           OR serial_row.owner_partner_id <> receipt_line_row.owner_partner_id
           OR serial_row.item_id <> receipt_line_row.item_id
           OR serial_row.inventory_lot_id IS DISTINCT FROM NEW.inventory_lot_id
           OR serial_row.source_receipt_line_id IS DISTINCT FROM NEW.receipt_line_id
           OR serial_row.source_serial_observation_id IS DISTINCT FROM NEW.receipt_serial_observation_id
           OR NEW.allocated_quantity > 1 THEN
            RAISE EXCEPTION 'Receipt allocation serial does not preserve receipt line/lot/observation dimensions'
                USING ERRCODE = '23514';
        END IF;
    ELSIF NEW.receipt_serial_observation_id IS NOT NULL THEN
        RAISE EXCEPTION 'A receipt serial observation requires its materialized serial number'
            USING ERRCODE = '23514';
    END IF;
    SELECT COALESCE(sum(allocated_quantity), 0) INTO existing_line_quantity
      FROM ewms.receipt_inventory_allocations allocation
      JOIN ewms.receipt_inventory_postings other_posting
        ON other_posting.id = allocation.receipt_inventory_posting_id
     WHERE allocation.receipt_line_id = NEW.receipt_line_id
       AND other_posting.posting_type <> 'REVERSAL'
       AND other_posting.status NOT IN ('REVERSED','FAILED')
       AND (excluded_id IS NULL OR allocation.id <> excluded_id);
    IF existing_line_quantity + NEW.allocated_quantity > accepted_base_quantity THEN
        RAISE EXCEPTION 'Receipt allocation exceeds accepted receipt-line quantity';
    END IF;
    SELECT COALESCE(sum(allocated_quantity), 0) INTO existing_entry_quantity
      FROM ewms.receipt_inventory_allocations
     WHERE inventory_transaction_entry_id = NEW.inventory_transaction_entry_id
       AND (excluded_id IS NULL OR id <> excluded_id);
    IF existing_entry_quantity + NEW.allocated_quantity > entry_row.signed_quantity THEN
        RAISE EXCEPTION 'Receipt allocations exceed linked positive transaction entry';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION ewms.assert_receipt_inventory_posting(
    p_receipt_inventory_posting_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, ewms
AS $function$
DECLARE
    posting_row ewms.receipt_inventory_postings%ROWTYPE;
    receipt_row ewms.receipts%ROWTYPE;
    transaction_row ewms.inventory_transaction_headers%ROWTYPE;
    positive_entry_count bigint;
BEGIN
    IF p_receipt_inventory_posting_id IS NULL THEN
        RETURN;
    END IF;
    SELECT * INTO posting_row
      FROM ewms.receipt_inventory_postings
     WHERE id = p_receipt_inventory_posting_id
     FOR SHARE;
    IF NOT FOUND OR posting_row.status NOT IN ('POSTED','REVERSED') THEN
        RETURN;
    END IF;
    SELECT * INTO receipt_row
      FROM ewms.receipts
     WHERE id = posting_row.receipt_id
     FOR SHARE;
    SELECT * INTO transaction_row
      FROM ewms.inventory_transaction_headers
     WHERE id = posting_row.inventory_transaction_id
     FOR SHARE;
    IF receipt_row.id IS NULL OR transaction_row.id IS NULL
       OR receipt_row.tenant_id <> posting_row.tenant_id
       OR transaction_row.tenant_id <> posting_row.tenant_id
       OR transaction_row.warehouse_id <> receipt_row.warehouse_id
       OR transaction_row.owner_partner_id <> receipt_row.owner_partner_id THEN
        RAISE EXCEPTION 'Receipt inventory posting % crosses tenant, warehouse, owner, or document scope',
            posting_row.id USING ERRCODE = '23514';
    END IF;
    IF posting_row.posted_at IS NULL THEN
        RAISE EXCEPTION 'Final receipt inventory posting % requires posted_at', posting_row.id
            USING ERRCODE = '23514';
    END IF;

    IF posting_row.posting_type = 'REVERSAL' THEN
        IF posting_row.status <> 'POSTED'
           OR transaction_row.transaction_type <> 'REVERSAL'
           OR transaction_row.posting_status <> 'POSTED'
           OR posting_row.reversed_by_posting_id IS NOT NULL THEN
            RAISE EXCEPTION 'Receipt reversal posting % must reference one POSTED REVERSAL transaction',
                posting_row.id USING ERRCODE = '23514';
        END IF;
        IF EXISTS (
            SELECT 1 FROM ewms.receipt_inventory_allocations allocation
             WHERE allocation.receipt_inventory_posting_id = posting_row.id
        ) THEN
            RAISE EXCEPTION 'Receipt reversal posting % cannot duplicate positive receipt allocations',
                posting_row.id USING ERRCODE = '23514';
        END IF;
        PERFORM 1
          FROM ewms.inventory_transaction_headers original_transaction
          JOIN ewms.receipt_inventory_postings original_posting
            ON original_posting.inventory_transaction_id = original_transaction.id
         WHERE original_transaction.id = transaction_row.reversal_of_transaction_id
           AND original_transaction.tenant_id = posting_row.tenant_id
           AND original_transaction.transaction_type = 'RECEIPT'
           AND original_transaction.posting_status = 'POSTED'
           AND original_transaction.warehouse_id = transaction_row.warehouse_id
           AND original_transaction.owner_partner_id = transaction_row.owner_partner_id
           AND original_posting.receipt_id = posting_row.receipt_id
           AND original_posting.posting_type IN ('RECEIPT','CORRECTION')
           AND original_posting.status = 'REVERSED'
           AND original_posting.reversed_by_posting_id = posting_row.id
         FOR SHARE OF original_transaction, original_posting;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Receipt reversal posting % is not paired to its reversed receipt posting',
                posting_row.id USING ERRCODE = '23514';
        END IF;
        RETURN;
    END IF;

    IF transaction_row.transaction_type <> 'RECEIPT'
       OR transaction_row.posting_status <> 'POSTED' THEN
        RAISE EXCEPTION 'Final receipt posting % requires a POSTED RECEIPT inventory transaction',
            posting_row.id USING ERRCODE = '23514';
    END IF;
    IF posting_row.status = 'POSTED' AND posting_row.reversed_by_posting_id IS NOT NULL THEN
        RAISE EXCEPTION 'Active receipt posting % cannot already reference a reversal posting',
            posting_row.id USING ERRCODE = '23514';
    END IF;
    IF posting_row.status = 'REVERSED' THEN
        IF posting_row.reversed_by_posting_id IS NULL THEN
            RAISE EXCEPTION 'Reversed receipt posting % requires its reversal posting', posting_row.id
                USING ERRCODE = '23514';
        END IF;
        PERFORM 1
          FROM ewms.receipt_inventory_postings reversal_posting
          JOIN ewms.inventory_transaction_headers reversal_transaction
            ON reversal_transaction.id = reversal_posting.inventory_transaction_id
         WHERE reversal_posting.id = posting_row.reversed_by_posting_id
           AND reversal_posting.tenant_id = posting_row.tenant_id
           AND reversal_posting.receipt_id = posting_row.receipt_id
           AND reversal_posting.posting_type = 'REVERSAL'
           AND reversal_posting.status = 'POSTED'
           AND reversal_transaction.transaction_type = 'REVERSAL'
           AND reversal_transaction.posting_status = 'POSTED'
           AND reversal_transaction.reversal_of_transaction_id = transaction_row.id
         FOR SHARE OF reversal_posting, reversal_transaction;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Reversed receipt posting % has no exact posted reversal transaction',
                posting_row.id USING ERRCODE = '23514';
        END IF;
    END IF;

    IF EXISTS (
        SELECT 1
          FROM ewms.inventory_transaction_entries entry
          JOIN ewms.stock_buckets bucket ON bucket.id = entry.stock_bucket_id
         WHERE entry.inventory_transaction_id = transaction_row.id
           AND NOT (
               (bucket.account_type = 'PHYSICAL'
                    AND entry.signed_quantity > 0
                    AND entry.entry_role IN ('DESTINATION','STOCK'))
               OR
               (bucket.account_type IN ('INBOUND_SOURCE','VIRTUAL')
                    AND entry.signed_quantity < 0
                    AND entry.entry_role = 'SOURCE')
           )
    ) THEN
        RAISE EXCEPTION 'RECEIPT transaction % must move only from a nonphysical inbound source to positive physical destinations; corrections require REVERSAL plus a new receipt',
            transaction_row.id USING ERRCODE = '23514';
    END IF;
    SELECT count(*) INTO positive_entry_count
      FROM ewms.inventory_transaction_entries entry
     WHERE entry.inventory_transaction_id = transaction_row.id
       AND entry.signed_quantity > 0;
    IF positive_entry_count = 0 THEN
        RAISE EXCEPTION 'POSTED RECEIPT transaction % has no positive destination entries',
            transaction_row.id USING ERRCODE = '23514';
    END IF;
    IF EXISTS (
        SELECT 1
          FROM ewms.inventory_transaction_entries entry
          JOIN ewms.stock_buckets bucket ON bucket.id = entry.stock_bucket_id
         WHERE entry.inventory_transaction_id = transaction_row.id
           AND entry.signed_quantity > 0
           AND (
               entry.tenant_id <> posting_row.tenant_id
               OR entry.entry_role NOT IN ('DESTINATION','STOCK')
               OR bucket.account_type <> 'PHYSICAL'
               OR bucket.tenant_id <> posting_row.tenant_id
               OR bucket.warehouse_id <> receipt_row.warehouse_id
               OR bucket.owner_partner_id <> receipt_row.owner_partner_id
               OR (SELECT COALESCE(sum(allocation.allocated_quantity), 0)
                     FROM ewms.receipt_inventory_allocations allocation
                    WHERE allocation.receipt_inventory_posting_id = posting_row.id
                      AND allocation.inventory_transaction_entry_id = entry.id)
                    IS DISTINCT FROM entry.signed_quantity
           )
    ) THEN
        RAISE EXCEPTION 'POSTED RECEIPT transaction % positive physical entries are not exactly allocated',
            transaction_row.id USING ERRCODE = '23514';
    END IF;
    IF EXISTS (
        SELECT 1
          FROM ewms.receipt_inventory_allocations allocation
          JOIN ewms.receipt_lines receipt_line ON receipt_line.id = allocation.receipt_line_id
          JOIN ewms.inventory_transaction_entries entry
            ON entry.id = allocation.inventory_transaction_entry_id
          JOIN ewms.stock_buckets bucket ON bucket.id = allocation.destination_stock_bucket_id
         WHERE allocation.receipt_inventory_posting_id = posting_row.id
           AND (
               allocation.tenant_id <> posting_row.tenant_id
               OR receipt_line.tenant_id <> posting_row.tenant_id
               OR receipt_line.receipt_id <> posting_row.receipt_id
               OR receipt_line.owner_partner_id <> receipt_row.owner_partner_id
               OR entry.tenant_id <> posting_row.tenant_id
               OR entry.inventory_transaction_id <> transaction_row.id
               OR entry.stock_bucket_id <> allocation.destination_stock_bucket_id
               OR entry.signed_quantity <= 0
               OR entry.entry_role NOT IN ('DESTINATION','STOCK')
               OR entry.item_id <> receipt_line.item_id
               OR entry.base_uom_code <> allocation.base_uom_code
               OR bucket.tenant_id <> posting_row.tenant_id
               OR bucket.account_type <> 'PHYSICAL'
               OR bucket.warehouse_id <> receipt_row.warehouse_id
               OR bucket.owner_partner_id <> receipt_line.owner_partner_id
               OR bucket.item_id <> receipt_line.item_id
               OR bucket.inventory_lot_id IS DISTINCT FROM allocation.inventory_lot_id
               OR bucket.serial_number_id IS DISTINCT FROM allocation.serial_number_id
               OR receipt_line.base_uom_code <> allocation.base_uom_code
               OR (allocation.inventory_lot_id IS NOT NULL AND NOT EXISTS (
                   SELECT 1 FROM ewms.inventory_lots inventory_lot
                    WHERE inventory_lot.id = allocation.inventory_lot_id
                      AND inventory_lot.tenant_id = allocation.tenant_id
                      AND inventory_lot.owner_partner_id = receipt_line.owner_partner_id
                      AND inventory_lot.item_id = receipt_line.item_id
                      AND inventory_lot.source_receipt_line_id = receipt_line.id
                      AND inventory_lot.source_lot_observation_id
                          IS NOT DISTINCT FROM allocation.receipt_lot_observation_id
               ))
               OR (allocation.serial_number_id IS NOT NULL AND NOT EXISTS (
                   SELECT 1 FROM ewms.serial_numbers serial_number
                    WHERE serial_number.id = allocation.serial_number_id
                      AND serial_number.tenant_id = allocation.tenant_id
                      AND serial_number.owner_partner_id = receipt_line.owner_partner_id
                      AND serial_number.item_id = receipt_line.item_id
                      AND serial_number.inventory_lot_id IS NOT DISTINCT FROM allocation.inventory_lot_id
                      AND serial_number.source_receipt_line_id = receipt_line.id
                      AND serial_number.source_serial_observation_id
                          IS NOT DISTINCT FROM allocation.receipt_serial_observation_id
               ))
           )
    ) THEN
        RAISE EXCEPTION 'Receipt posting % contains a line, bucket, lot, serial, owner, or UOM mismatch',
            posting_row.id USING ERRCODE = '23514';
    END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION ewms.assert_receipt_inventory_transaction(
    p_inventory_transaction_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, ewms
AS $function$
DECLARE
    transaction_row ewms.inventory_transaction_headers%ROWTYPE;
    original_type varchar(40);
    posting_id uuid;
    posting_count bigint;
BEGIN
    IF p_inventory_transaction_id IS NULL THEN RETURN; END IF;
    SELECT * INTO transaction_row
      FROM ewms.inventory_transaction_headers
     WHERE id = p_inventory_transaction_id
     FOR SHARE;
    IF NOT FOUND OR transaction_row.posting_status <> 'POSTED' THEN RETURN; END IF;

    IF transaction_row.transaction_type = 'RECEIPT' THEN
        SELECT count(*), min(posting.id::text)::uuid
          INTO posting_count, posting_id
          FROM ewms.receipt_inventory_postings posting
         WHERE posting.inventory_transaction_id = transaction_row.id
           AND posting.tenant_id = transaction_row.tenant_id
           AND posting.posting_type IN ('RECEIPT','CORRECTION')
           AND posting.status IN ('POSTED','REVERSED');
        IF posting_count <> 1 THEN
            RAISE EXCEPTION 'POSTED RECEIPT transaction % requires exactly one final receipt posting',
                transaction_row.id USING ERRCODE = '23514';
        END IF;
        PERFORM ewms.assert_receipt_inventory_posting(posting_id);
    ELSIF transaction_row.transaction_type = 'REVERSAL' THEN
        SELECT transaction_type INTO original_type
          FROM ewms.inventory_transaction_headers
         WHERE id = transaction_row.reversal_of_transaction_id
         FOR SHARE;
        IF original_type = 'RECEIPT' THEN
            SELECT count(*), min(posting.id::text)::uuid
              INTO posting_count, posting_id
              FROM ewms.receipt_inventory_postings posting
             WHERE posting.inventory_transaction_id = transaction_row.id
               AND posting.tenant_id = transaction_row.tenant_id
               AND posting.posting_type = 'REVERSAL'
               AND posting.status = 'POSTED';
            IF posting_count <> 1 THEN
                RAISE EXCEPTION 'POSTED reversal of RECEIPT transaction % requires one receipt reversal posting',
                    transaction_row.id USING ERRCODE = '23514';
            END IF;
            PERFORM ewms.assert_receipt_inventory_posting(posting_id);
        END IF;
    END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION ewms.assert_receipt_document_inventory(
    p_receipt_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, ewms
AS $function$
DECLARE
    receipt_row ewms.receipts%ROWTYPE;
    line_row record;
    active_quantity numeric(24,8);
    posted_quantity numeric(24,8);
    posting_row record;
BEGIN
    IF p_receipt_id IS NULL THEN RETURN; END IF;
    SELECT * INTO receipt_row FROM ewms.receipts WHERE id = p_receipt_id FOR SHARE;
    IF NOT FOUND THEN RETURN; END IF;
    FOR line_row IN
        SELECT id,
               CASE WHEN received_quantity = 0 THEN 0::numeric
                    ELSE accepted_quantity * received_base_quantity / received_quantity END
                   AS accepted_base_quantity,
               posting_status
          FROM ewms.receipt_lines
         WHERE receipt_id = receipt_row.id
         ORDER BY id
         FOR SHARE
    LOOP
        SELECT COALESCE(sum(allocation.allocated_quantity), 0)
          INTO active_quantity
          FROM ewms.receipt_inventory_allocations allocation
          JOIN ewms.receipt_inventory_postings posting
            ON posting.id = allocation.receipt_inventory_posting_id
         WHERE allocation.receipt_line_id = line_row.id
           AND posting.posting_type <> 'REVERSAL'
           AND posting.status NOT IN ('REVERSED','FAILED');
        IF active_quantity > line_row.accepted_base_quantity THEN
            RAISE EXCEPTION 'Receipt line % active inventory allocations exceed accepted quantity',
                line_row.id USING ERRCODE = '23514';
        END IF;
        IF receipt_row.posting_status = 'POSTED' OR line_row.posting_status = 'POSTED' THEN
            SELECT COALESCE(sum(allocation.allocated_quantity), 0)
              INTO posted_quantity
              FROM ewms.receipt_inventory_allocations allocation
              JOIN ewms.receipt_inventory_postings posting
                ON posting.id = allocation.receipt_inventory_posting_id
             WHERE allocation.receipt_line_id = line_row.id
               AND posting.posting_type <> 'REVERSAL'
               AND posting.status = 'POSTED';
            IF posted_quantity IS DISTINCT FROM line_row.accepted_base_quantity THEN
                RAISE EXCEPTION 'Posted receipt line % quantity % does not equal accepted quantity %',
                    line_row.id, posted_quantity, line_row.accepted_base_quantity
                    USING ERRCODE = '23514';
            END IF;
        END IF;
    END LOOP;
    FOR posting_row IN
        SELECT id FROM ewms.receipt_inventory_postings
         WHERE receipt_id = receipt_row.id AND status IN ('POSTED','REVERSED')
         ORDER BY id
    LOOP
        PERFORM ewms.assert_receipt_inventory_posting(posting_row.id);
    END LOOP;
END;
$function$;

CREATE OR REPLACE FUNCTION ewms.guard_receipt_inventory_posting_mutation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, ewms
AS $function$
DECLARE
    transaction_status varchar(20);
    old_core jsonb;
    new_core jsonb;
BEGIN
    SELECT posting_status INTO transaction_status
      FROM ewms.inventory_transaction_headers
     WHERE id = OLD.inventory_transaction_id
     FOR SHARE;
    IF TG_OP = 'DELETE' THEN
        IF OLD.status IN ('POSTED','REVERSED') OR transaction_status = 'POSTED' THEN
            RAISE EXCEPTION 'Final receipt inventory posting % cannot be deleted; use a REVERSAL posting', OLD.id
                USING ERRCODE = '55000';
        END IF;
        RETURN OLD;
    END IF;
    IF OLD.status IN ('POSTED','REVERSED') OR transaction_status = 'POSTED' THEN
        old_core := to_jsonb(OLD) - ARRAY[
            'status','posted_at','reversed_by_posting_id','row_version','updated_at'
        ]::text[];
        new_core := to_jsonb(NEW) - ARRAY[
            'status','posted_at','reversed_by_posting_id','row_version','updated_at'
        ]::text[];
        IF old_core IS DISTINCT FROM new_core THEN
            RAISE EXCEPTION 'Final receipt inventory posting % core fields are immutable', OLD.id
                USING ERRCODE = '55000';
        END IF;
        IF OLD.status = 'REVERSED' AND ROW(NEW.status, NEW.posted_at, NEW.reversed_by_posting_id)
            IS DISTINCT FROM ROW(OLD.status, OLD.posted_at, OLD.reversed_by_posting_id) THEN
            RAISE EXCEPTION 'Reversed receipt inventory posting % is immutable', OLD.id
                USING ERRCODE = '55000';
        END IF;
        IF OLD.status = 'POSTED' THEN
            IF NEW.posted_at IS DISTINCT FROM OLD.posted_at
               OR NOT (
                   (NEW.status = 'POSTED' AND NEW.reversed_by_posting_id IS NULL) OR
                   (NEW.status = 'REVERSED' AND OLD.reversed_by_posting_id IS NULL
                    AND NEW.reversed_by_posting_id IS NOT NULL)
               ) THEN
                RAISE EXCEPTION 'Posted receipt posting % may only transition once to REVERSED', OLD.id
                    USING ERRCODE = '55000';
            END IF;
        ELSIF transaction_status = 'POSTED' AND OLD.status NOT IN ('POSTED','REVERSED') THEN
            IF NEW.status <> 'POSTED' OR NEW.posted_at IS NULL
               OR NEW.reversed_by_posting_id IS NOT NULL THEN
                RAISE EXCEPTION 'A posted inventory transaction requires its receipt posting to finalize as POSTED'
                    USING ERRCODE = '23514';
            END IF;
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION ewms.guard_receipt_inventory_allocation_mutation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, ewms
AS $function$
DECLARE
    target_posting_id uuid;
    posting_status varchar(20);
    transaction_status varchar(20);
BEGIN
    FOR target_posting_id IN
        SELECT DISTINCT posting_id
          FROM (VALUES
              (CASE WHEN TG_OP <> 'INSERT' THEN OLD.receipt_inventory_posting_id END),
              (CASE WHEN TG_OP <> 'DELETE' THEN NEW.receipt_inventory_posting_id END)
          ) AS candidate(posting_id)
         WHERE posting_id IS NOT NULL
         ORDER BY posting_id
    LOOP
        SELECT posting.status, transaction.posting_status
          INTO posting_status, transaction_status
          FROM ewms.receipt_inventory_postings posting
          JOIN ewms.inventory_transaction_headers transaction
            ON transaction.id = posting.inventory_transaction_id
         WHERE posting.id = target_posting_id
         FOR SHARE OF posting, transaction;
        IF posting_status IN ('POSTED','REVERSED') OR transaction_status = 'POSTED' THEN
            RAISE EXCEPTION 'Receipt inventory allocations are append-only after posting %', target_posting_id
                USING ERRCODE = '55000';
        END IF;
    END LOOP;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION ewms.deferred_check_receipt_inventory_integrity()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, ewms
AS $function$
DECLARE
    old_data jsonb := '{}'::jsonb;
    new_data jsonb := '{}'::jsonb;
    old_posting_id uuid;
    new_posting_id uuid;
    old_transaction_id uuid;
    new_transaction_id uuid;
    old_receipt_id uuid;
    new_receipt_id uuid;
    old_receipt_line_id uuid;
    new_receipt_line_id uuid;
BEGIN
    IF TG_OP <> 'INSERT' THEN old_data := to_jsonb(OLD); END IF;
    IF TG_OP <> 'DELETE' THEN new_data := to_jsonb(NEW); END IF;

    IF TG_TABLE_NAME = 'receipt_inventory_postings' THEN
        old_posting_id := NULLIF(old_data ->> 'id', '')::uuid;
        new_posting_id := NULLIF(new_data ->> 'id', '')::uuid;
        old_transaction_id := NULLIF(old_data ->> 'inventory_transaction_id', '')::uuid;
        new_transaction_id := NULLIF(new_data ->> 'inventory_transaction_id', '')::uuid;
        old_receipt_id := NULLIF(old_data ->> 'receipt_id', '')::uuid;
        new_receipt_id := NULLIF(new_data ->> 'receipt_id', '')::uuid;
    ELSIF TG_TABLE_NAME = 'receipt_inventory_allocations' THEN
        old_posting_id := NULLIF(old_data ->> 'receipt_inventory_posting_id', '')::uuid;
        new_posting_id := NULLIF(new_data ->> 'receipt_inventory_posting_id', '')::uuid;
        SELECT inventory_transaction_id, receipt_id
          INTO old_transaction_id, old_receipt_id
          FROM ewms.receipt_inventory_postings WHERE id = old_posting_id;
        SELECT inventory_transaction_id, receipt_id
          INTO new_transaction_id, new_receipt_id
          FROM ewms.receipt_inventory_postings WHERE id = new_posting_id;
    ELSIF TG_TABLE_NAME = 'inventory_transaction_headers' THEN
        old_transaction_id := NULLIF(old_data ->> 'id', '')::uuid;
        new_transaction_id := NULLIF(new_data ->> 'id', '')::uuid;
    ELSIF TG_TABLE_NAME = 'inventory_transaction_entries' THEN
        old_transaction_id := NULLIF(old_data ->> 'inventory_transaction_id', '')::uuid;
        new_transaction_id := NULLIF(new_data ->> 'inventory_transaction_id', '')::uuid;
    ELSIF TG_TABLE_NAME = 'receipts' THEN
        old_receipt_id := NULLIF(old_data ->> 'id', '')::uuid;
        new_receipt_id := NULLIF(new_data ->> 'id', '')::uuid;
    ELSIF TG_TABLE_NAME = 'receipt_lines' THEN
        old_receipt_line_id := NULLIF(old_data ->> 'id', '')::uuid;
        new_receipt_line_id := NULLIF(new_data ->> 'id', '')::uuid;
        old_receipt_id := NULLIF(old_data ->> 'receipt_id', '')::uuid;
        new_receipt_id := NULLIF(new_data ->> 'receipt_id', '')::uuid;
    ELSIF TG_TABLE_NAME IN ('inventory_lots','serial_numbers') THEN
        old_receipt_line_id := NULLIF(old_data ->> 'source_receipt_line_id', '')::uuid;
        new_receipt_line_id := NULLIF(new_data ->> 'source_receipt_line_id', '')::uuid;
        SELECT receipt_id INTO old_receipt_id
          FROM ewms.receipt_lines WHERE id = old_receipt_line_id;
        SELECT receipt_id INTO new_receipt_id
          FROM ewms.receipt_lines WHERE id = new_receipt_line_id;
    END IF;

    PERFORM ewms.assert_receipt_inventory_posting(old_posting_id);
    IF new_posting_id IS DISTINCT FROM old_posting_id THEN
        PERFORM ewms.assert_receipt_inventory_posting(new_posting_id);
    END IF;
    PERFORM ewms.assert_receipt_inventory_transaction(old_transaction_id);
    IF new_transaction_id IS DISTINCT FROM old_transaction_id THEN
        PERFORM ewms.assert_receipt_inventory_transaction(new_transaction_id);
    END IF;
    PERFORM ewms.assert_receipt_document_inventory(old_receipt_id);
    IF new_receipt_id IS DISTINCT FROM old_receipt_id THEN
        PERFORM ewms.assert_receipt_document_inventory(new_receipt_id);
    END IF;
    RETURN NULL;
END;
$function$;

REVOKE ALL ON FUNCTION ewms.assert_receipt_inventory_posting(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION ewms.assert_receipt_inventory_transaction(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION ewms.assert_receipt_document_inventory(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION ewms.guard_receipt_inventory_posting_mutation() FROM PUBLIC;
REVOKE ALL ON FUNCTION ewms.guard_receipt_inventory_allocation_mutation() FROM PUBLIC;
REVOKE ALL ON FUNCTION ewms.deferred_check_receipt_inventory_integrity() FROM PUBLIC;

CREATE OR REPLACE FUNCTION ewms.validate_supplier_return_inventory_allocation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, ewms
AS $function$
DECLARE
    entry_row ewms.inventory_transaction_entries%ROWTYPE;
BEGIN
    IF NEW.inventory_transaction_entry_id IS NULL THEN
        RETURN NEW;
    END IF;
    SELECT * INTO entry_row
      FROM ewms.inventory_transaction_entries
     WHERE tenant_id = NEW.tenant_id AND id = NEW.inventory_transaction_entry_id;
    IF NOT FOUND OR entry_row.stock_bucket_id <> NEW.source_stock_bucket_id
       OR entry_row.signed_quantity >= 0
       OR abs(entry_row.signed_quantity) < NEW.allocated_quantity THEN
        RAISE EXCEPTION 'Supplier return allocation requires a sufficient negative entry on its source bucket';
    END IF;
    IF EXISTS (
        SELECT 1 FROM ewms.inventory_transaction_headers h
         WHERE h.id = entry_row.inventory_transaction_id AND h.posting_status = 'POSTED'
    ) THEN
        RAISE EXCEPTION 'Supplier return allocation is immutable after transaction posting';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION ewms.post_inventory_transaction(
    p_inventory_transaction_id uuid,
    p_posted_by uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, ewms
AS $function$
DECLARE
    tx_row ewms.inventory_transaction_headers%ROWTYPE;
    entry_count integer;
    balance_delta record;
    authorization_token uuid;
BEGIN
    SELECT * INTO tx_row
      FROM ewms.inventory_transaction_headers
     WHERE id = p_inventory_transaction_id
     FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Inventory transaction % does not exist', p_inventory_transaction_id;
    END IF;
    IF tx_row.posting_status = 'POSTED' THEN
        RETURN;
    END IF;
    IF tx_row.posting_status NOT IN ('DRAFT','VALIDATED') THEN
        RAISE EXCEPTION 'Inventory transaction status % cannot be posted', tx_row.posting_status;
    END IF;
    IF p_posted_by IS NULL OR NOT EXISTS (
        SELECT 1 FROM ewms.users WHERE id = p_posted_by AND status = 'ACTIVE'
    ) THEN
        RAISE EXCEPTION 'An active posting user is required';
    END IF;

    SELECT count(*) INTO entry_count
      FROM ewms.inventory_transaction_entries
     WHERE inventory_transaction_id = tx_row.id AND tenant_id = tx_row.tenant_id;
    IF entry_count < 2 THEN
        RAISE EXCEPTION 'Inventory transaction requires at least two signed entries';
    END IF;

    IF EXISTS (
        SELECT 1
          FROM ewms.inventory_transaction_entries
         WHERE inventory_transaction_id = tx_row.id
         GROUP BY item_id, base_uom_code
        HAVING sum(signed_quantity) <> 0
    ) THEN
        RAISE EXCEPTION 'Inventory transaction must balance to zero by item and base UOM';
    END IF;

    IF tx_row.transaction_type NOT IN ('TRANSFER','OWNER_TRANSFER','BONDED_MOVE') AND EXISTS (
        SELECT 1
          FROM ewms.inventory_transaction_entries e
          JOIN ewms.stock_buckets b ON b.id = e.stock_bucket_id
         WHERE e.inventory_transaction_id = tx_row.id
           AND (b.warehouse_id <> tx_row.warehouse_id OR b.owner_partner_id <> tx_row.owner_partner_id)
    ) THEN
        RAISE EXCEPTION 'Inventory transaction bucket warehouse/owner differs from its header';
    END IF;

    IF tx_row.transaction_type = 'REVERSAL' THEN
        IF NOT EXISTS (
            SELECT 1 FROM ewms.inventory_transaction_headers original
             WHERE original.id = tx_row.reversal_of_transaction_id
               AND original.tenant_id = tx_row.tenant_id
               AND original.posting_status = 'POSTED'
        ) THEN
            RAISE EXCEPTION 'Reversal requires an original POSTED transaction in the same tenant';
        END IF;
        IF EXISTS (
            WITH original_entries AS (
                SELECT stock_bucket_id, item_id, base_uom_code, sum(signed_quantity) AS quantity
                  FROM ewms.inventory_transaction_entries
                 WHERE inventory_transaction_id = tx_row.reversal_of_transaction_id
                 GROUP BY stock_bucket_id, item_id, base_uom_code
            ), reversal_entries AS (
                SELECT stock_bucket_id, item_id, base_uom_code, sum(signed_quantity) AS quantity
                  FROM ewms.inventory_transaction_entries
                 WHERE inventory_transaction_id = tx_row.id
                 GROUP BY stock_bucket_id, item_id, base_uom_code
            )
            SELECT 1
              FROM original_entries o
              FULL JOIN reversal_entries r
                ON r.stock_bucket_id = o.stock_bucket_id
               AND r.item_id = o.item_id
               AND r.base_uom_code = o.base_uom_code
             WHERE COALESCE(o.quantity, 0) + COALESCE(r.quantity, 0) <> 0
        ) THEN
            RAISE EXCEPTION 'Reversal entries must be the exact signed inverse of the original transaction';
        END IF;
    END IF;

    IF EXISTS (
        SELECT 1
          FROM ewms.inventory_transaction_entries e
          JOIN ewms.stock_buckets b ON b.id = e.stock_bucket_id
          JOIN ewms.lpns l ON l.id = b.lpn_id AND l.sealed
         WHERE e.inventory_transaction_id = tx_row.id
         GROUP BY b.lpn_id, b.item_id, b.inventory_lot_id, b.serial_number_id, e.base_uom_code
        HAVING sum(e.signed_quantity) <> 0
    ) THEN
        RAISE EXCEPTION 'A sealed LPN transaction must preserve every item/lot/serial content quantity';
    END IF;

    IF EXISTS (
        SELECT 1
          FROM ewms.inventory_transaction_entries e
          JOIN ewms.stock_buckets b ON b.id = e.stock_bucket_id
          JOIN ewms.inventory_freezes f
            ON f.tenant_id = b.tenant_id
           AND f.warehouse_id = b.warehouse_id
           AND f.status = 'ACTIVE'
           AND (f.expires_at IS NULL OR f.expires_at > now())
           AND (f.owner_partner_id IS NULL OR f.owner_partner_id = b.owner_partner_id)
           AND (f.location_id IS NULL OR f.location_id = b.location_id)
           AND (f.item_id IS NULL OR f.item_id = b.item_id)
           AND (f.inventory_lot_id IS NULL OR f.inventory_lot_id = b.inventory_lot_id)
           AND (f.lpn_id IS NULL OR f.lpn_id = b.lpn_id)
         WHERE e.inventory_transaction_id = tx_row.id
           AND (tx_row.transaction_type = ANY(f.blocked_operations) OR 'ALL' = ANY(f.blocked_operations))
    ) THEN
        RAISE EXCEPTION 'Inventory transaction touches an active inventory freeze';
    END IF;

    authorization_token := ewms.open_inventory_write_authorization('POSTING');
    INSERT INTO ewms.inventory_balances (stock_bucket_id, tenant_id)
    SELECT DISTINCT e.stock_bucket_id, e.tenant_id
      FROM ewms.inventory_transaction_entries e
     WHERE e.inventory_transaction_id = tx_row.id
    ON CONFLICT (stock_bucket_id) DO NOTHING;

    PERFORM 1
      FROM ewms.inventory_balances b
      JOIN ewms.inventory_transaction_entries e ON e.stock_bucket_id = b.stock_bucket_id
     WHERE e.inventory_transaction_id = tx_row.id
     ORDER BY b.stock_bucket_id
     FOR UPDATE OF b;

    FOR balance_delta IN
        SELECT stock_bucket_id, sum(signed_quantity) AS quantity_delta
          FROM ewms.inventory_transaction_entries
         WHERE inventory_transaction_id = tx_row.id
         GROUP BY stock_bucket_id
         ORDER BY stock_bucket_id
    LOOP
        UPDATE ewms.inventory_balances
           SET on_hand_quantity = on_hand_quantity + balance_delta.quantity_delta,
               last_transaction_id = tx_row.id,
               last_transaction_at = tx_row.occurred_at,
               updated_at = now()
         WHERE tenant_id = tx_row.tenant_id
           AND stock_bucket_id = balance_delta.stock_bucket_id;
    END LOOP;

    IF EXISTS (
        SELECT 1
          FROM ewms.stock_buckets b
          JOIN ewms.inventory_balances bal ON bal.stock_bucket_id = b.id
         WHERE b.tenant_id = tx_row.tenant_id
           AND b.account_type = 'PHYSICAL'
           AND b.serial_number_id IN (
               SELECT b2.serial_number_id
                 FROM ewms.inventory_transaction_entries e2
                 JOIN ewms.stock_buckets b2 ON b2.id = e2.stock_bucket_id
                WHERE e2.inventory_transaction_id = tx_row.id
                  AND b2.serial_number_id IS NOT NULL
           )
         GROUP BY b.serial_number_id
        HAVING count(*) FILTER (WHERE bal.on_hand_quantity > 0) > 1
            OR sum(GREATEST(bal.on_hand_quantity, 0)) > 1
    ) THEN
        RAISE EXCEPTION 'Serial number would exist in more than one positive physical balance';
    END IF;

    IF EXISTS (
        SELECT 1
          FROM ewms.stock_buckets b
          JOIN ewms.inventory_balances bal ON bal.stock_bucket_id = b.id
         WHERE b.tenant_id = tx_row.tenant_id
           AND b.account_type = 'PHYSICAL'
           AND bal.on_hand_quantity > 0
           AND b.lpn_id IN (
               SELECT b2.lpn_id
                 FROM ewms.inventory_transaction_entries e2
                 JOIN ewms.stock_buckets b2 ON b2.id = e2.stock_bucket_id
                WHERE e2.inventory_transaction_id = tx_row.id AND b2.lpn_id IS NOT NULL
           )
         GROUP BY b.lpn_id
        HAVING count(DISTINCT b.location_id) > 1
    ) THEN
        RAISE EXCEPTION 'One LPN cannot have positive physical contents in multiple locations';
    END IF;

    UPDATE ewms.inventory_transaction_headers
       SET posting_status = 'POSTED',
           posted_at = now(),
           posted_by = p_posted_by,
           updated_by = p_posted_by,
           updated_at = now()
     WHERE id = tx_row.id;
    PERFORM ewms.close_inventory_write_authorization(authorization_token);
END;
$function$;

REVOKE ALL ON FUNCTION ewms.post_inventory_transaction(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION ewms.project_inventory_reservation() FROM PUBLIC;
REVOKE ALL ON FUNCTION ewms.project_inventory_hold() FROM PUBLIC;
REVOKE ALL ON FUNCTION ewms.apply_inventory_hold_release() FROM PUBLIC;

-- Operational and reconciliation indexes.
CREATE INDEX IF NOT EXISTS ix_inventory_lots_lookup
    ON ewms.inventory_lots (tenant_id, owner_partner_id, item_id, status, expires_on, id);
CREATE INDEX IF NOT EXISTS ix_inventory_lots_supplier_lot
    ON ewms.inventory_lots (tenant_id, supplier_lot_no, item_id)
    WHERE supplier_lot_no IS NOT NULL AND deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS ix_serial_numbers_lookup
    ON ewms.serial_numbers (tenant_id, owner_partner_id, serial_no, status);
CREATE INDEX IF NOT EXISTS ix_lpns_worklist
    ON ewms.lpns (tenant_id, warehouse_id, status, current_location_id, id);
CREATE INDEX IF NOT EXISTS ix_lpns_parent
    ON ewms.lpns (tenant_id, parent_lpn_id) WHERE parent_lpn_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_stock_buckets_item_location
    ON ewms.stock_buckets (tenant_id, owner_partner_id, warehouse_id, item_id, location_id, inventory_status_id);
CREATE INDEX IF NOT EXISTS ix_stock_buckets_lot
    ON ewms.stock_buckets (tenant_id, inventory_lot_id, warehouse_id, location_id)
    WHERE inventory_lot_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_stock_buckets_serial
    ON ewms.stock_buckets (tenant_id, serial_number_id)
    WHERE serial_number_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_stock_buckets_lpn
    ON ewms.stock_buckets (tenant_id, lpn_id, location_id)
    WHERE lpn_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_stock_buckets_bonded
    ON ewms.stock_buckets (tenant_id, warehouse_id, customs_legal_status_code, bonded_cargo_reference)
    WHERE customs_legal_status_code IS NOT NULL OR bonded_cargo_reference IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_inventory_balances_nonzero
    ON ewms.inventory_balances (tenant_id, stock_bucket_id)
    WHERE on_hand_quantity <> 0 OR reserved_quantity <> 0 OR held_quantity <> 0 OR
          pending_out_quantity <> 0 OR pending_in_quantity <> 0;
CREATE INDEX IF NOT EXISTS ix_inventory_transactions_worklist
    ON ewms.inventory_transaction_headers (tenant_id, warehouse_id, owner_partner_id, posting_status, occurred_at DESC, id);
CREATE INDEX IF NOT EXISTS ix_inventory_transactions_source
    ON ewms.inventory_transaction_headers (tenant_id, source_document_type, source_document_id, source_document_line_id);
CREATE INDEX IF NOT EXISTS ix_inventory_entries_bucket_time
    ON ewms.inventory_transaction_entries (tenant_id, stock_bucket_id, inventory_transaction_id);
CREATE INDEX IF NOT EXISTS ix_inventory_entries_item
    ON ewms.inventory_transaction_entries (tenant_id, item_id, inventory_transaction_id);
CREATE INDEX IF NOT EXISTS ix_inventory_reservations_active
    ON ewms.inventory_reservations (tenant_id, stock_bucket_id, expires_at, priority, id)
    WHERE status IN ('ACTIVE','PARTIALLY_CONSUMED');
CREATE INDEX IF NOT EXISTS ix_inventory_reservations_demand
    ON ewms.inventory_reservations (tenant_id, demand_document_type, demand_document_id, demand_line_id);
CREATE INDEX IF NOT EXISTS ix_inventory_holds_active
    ON ewms.inventory_holds (tenant_id, stock_bucket_id, review_due_at, id)
    WHERE status IN ('ACTIVE','PARTIALLY_RELEASED');
CREATE INDEX IF NOT EXISTS ix_movement_tasks_queue
    ON ewms.movement_tasks (tenant_id, warehouse_id, status, priority, planned_start_at, id);
CREATE INDEX IF NOT EXISTS ix_movement_tasks_source
    ON ewms.movement_tasks (tenant_id, source_stock_bucket_id, status);
CREATE INDEX IF NOT EXISTS ix_putaway_tasks_request
    ON ewms.putaway_tasks (tenant_id, putaway_request_id, movement_task_id);
CREATE INDEX IF NOT EXISTS ix_replenishment_requests_queue
    ON ewms.replenishment_requests (tenant_id, warehouse_id, status, priority, required_at, id);
CREATE INDEX IF NOT EXISTS ix_adjustments_worklist
    ON ewms.inventory_adjustments (tenant_id, warehouse_id, owner_partner_id, status, requested_at DESC);
CREATE INDEX IF NOT EXISTS ix_cycle_count_tasks_queue
    ON ewms.cycle_count_tasks (tenant_id, warehouse_id, status, priority, assigned_at, id);
CREATE INDEX IF NOT EXISTS ix_inventory_freezes_active
    ON ewms.inventory_freezes (tenant_id, warehouse_id, status, expires_at)
    WHERE status = 'ACTIVE';
CREATE INDEX IF NOT EXISTS ix_inventory_snapshots_asof
    ON ewms.inventory_snapshots (tenant_id, warehouse_id, owner_partner_id, as_of_at DESC);
CREATE INDEX IF NOT EXISTS ix_valuation_layers_open
    ON ewms.inventory_valuation_layers (tenant_id, owner_partner_id, warehouse_id, item_id, received_at, id)
    WHERE status = 'OPEN' AND remaining_quantity > 0;
CREATE INDEX IF NOT EXISTS ix_reconciliation_details_open
    ON ewms.inventory_reconciliation_details (tenant_id, inventory_reconciliation_run_id, severity, exception_code)
    WHERE status IN ('OPEN','ACKNOWLEDGED');

DROP TRIGGER IF EXISTS trg_validate_lpn_parent ON ewms.lpns;
CREATE TRIGGER trg_validate_lpn_parent
BEFORE INSERT OR UPDATE OF tenant_id, parent_lpn_id, warehouse_id
ON ewms.lpns FOR EACH ROW EXECUTE PROCEDURE ewms.validate_lpn_parent();

DROP TRIGGER IF EXISTS trg_protect_stock_bucket_dimensions ON ewms.stock_buckets;
CREATE TRIGGER trg_protect_stock_bucket_dimensions
BEFORE UPDATE ON ewms.stock_buckets
FOR EACH ROW EXECUTE PROCEDURE ewms.protect_stock_bucket_dimensions();

DROP TRIGGER IF EXISTS trg_validate_stock_bucket ON ewms.stock_buckets;
CREATE TRIGGER trg_validate_stock_bucket
BEFORE INSERT OR UPDATE ON ewms.stock_buckets
FOR EACH ROW EXECUTE PROCEDURE ewms.validate_stock_bucket();

DROP TRIGGER IF EXISTS trg_validate_inventory_entry ON ewms.inventory_transaction_entries;
CREATE TRIGGER trg_validate_inventory_entry
BEFORE INSERT OR UPDATE ON ewms.inventory_transaction_entries
FOR EACH ROW EXECUTE PROCEDURE ewms.validate_inventory_entry();

DROP TRIGGER IF EXISTS trg_guard_inventory_entry_mutation ON ewms.inventory_transaction_entries;
CREATE TRIGGER trg_guard_inventory_entry_mutation
BEFORE UPDATE OR DELETE ON ewms.inventory_transaction_entries
FOR EACH ROW EXECUTE PROCEDURE ewms.guard_inventory_entry_mutation();

DROP TRIGGER IF EXISTS trg_guard_inventory_tx_header ON ewms.inventory_transaction_headers;
CREATE TRIGGER trg_guard_inventory_tx_header
BEFORE UPDATE OR DELETE ON ewms.inventory_transaction_headers
FOR EACH ROW EXECUTE PROCEDURE ewms.guard_inventory_transaction_header();

DROP TRIGGER IF EXISTS trg_guard_inventory_balance_write ON ewms.inventory_balances;
CREATE TRIGGER trg_guard_inventory_balance_write
BEFORE INSERT OR UPDATE OR DELETE ON ewms.inventory_balances
FOR EACH ROW EXECUTE PROCEDURE ewms.guard_inventory_balance_write();

DROP TRIGGER IF EXISTS trg_validate_inventory_balance ON ewms.inventory_balances;
CREATE TRIGGER trg_validate_inventory_balance
BEFORE INSERT OR UPDATE ON ewms.inventory_balances
FOR EACH ROW EXECUTE PROCEDURE ewms.validate_inventory_balance();

DROP TRIGGER IF EXISTS trg_project_inventory_reservation ON ewms.inventory_reservations;
CREATE TRIGGER trg_project_inventory_reservation
AFTER INSERT OR UPDATE OR DELETE ON ewms.inventory_reservations
FOR EACH ROW EXECUTE PROCEDURE ewms.project_inventory_reservation();

DROP TRIGGER IF EXISTS trg_project_inventory_hold ON ewms.inventory_holds;
CREATE TRIGGER trg_project_inventory_hold
AFTER INSERT OR UPDATE OR DELETE ON ewms.inventory_holds
FOR EACH ROW EXECUTE PROCEDURE ewms.project_inventory_hold();

DROP TRIGGER IF EXISTS trg_apply_inventory_hold_release ON ewms.inventory_hold_releases;
CREATE TRIGGER trg_apply_inventory_hold_release
AFTER INSERT ON ewms.inventory_hold_releases
FOR EACH ROW EXECUTE PROCEDURE ewms.apply_inventory_hold_release();

DROP TRIGGER IF EXISTS trg_validate_receipt_inventory_alloc
ON ewms.receipt_inventory_allocations;
CREATE TRIGGER trg_validate_receipt_inventory_alloc
BEFORE INSERT OR UPDATE ON ewms.receipt_inventory_allocations
FOR EACH ROW EXECUTE PROCEDURE ewms.validate_receipt_inventory_allocation();

DROP TRIGGER IF EXISTS trg_guard_receipt_inventory_posting
ON ewms.receipt_inventory_postings;
CREATE TRIGGER trg_guard_receipt_inventory_posting
BEFORE UPDATE OR DELETE ON ewms.receipt_inventory_postings
FOR EACH ROW EXECUTE PROCEDURE ewms.guard_receipt_inventory_posting_mutation();

DROP TRIGGER IF EXISTS trg_guard_receipt_inventory_allocation
ON ewms.receipt_inventory_allocations;
CREATE TRIGGER trg_guard_receipt_inventory_allocation
BEFORE UPDATE OR DELETE ON ewms.receipt_inventory_allocations
FOR EACH ROW EXECUTE PROCEDURE ewms.guard_receipt_inventory_allocation_mutation();

DROP TRIGGER IF EXISTS trg_receipt_inventory_posting_integrity
ON ewms.receipt_inventory_postings;
CREATE CONSTRAINT TRIGGER trg_receipt_inventory_posting_integrity
AFTER INSERT OR UPDATE OR DELETE ON ewms.receipt_inventory_postings
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE PROCEDURE ewms.deferred_check_receipt_inventory_integrity();

DROP TRIGGER IF EXISTS trg_receipt_inventory_allocation_integrity
ON ewms.receipt_inventory_allocations;
CREATE CONSTRAINT TRIGGER trg_receipt_inventory_allocation_integrity
AFTER INSERT OR UPDATE OR DELETE ON ewms.receipt_inventory_allocations
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE PROCEDURE ewms.deferred_check_receipt_inventory_integrity();

DROP TRIGGER IF EXISTS trg_receipt_inventory_transaction_integrity
ON ewms.inventory_transaction_headers;
CREATE CONSTRAINT TRIGGER trg_receipt_inventory_transaction_integrity
AFTER INSERT OR UPDATE OR DELETE ON ewms.inventory_transaction_headers
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE PROCEDURE ewms.deferred_check_receipt_inventory_integrity();

DROP TRIGGER IF EXISTS trg_receipt_inventory_entry_integrity
ON ewms.inventory_transaction_entries;
CREATE CONSTRAINT TRIGGER trg_receipt_inventory_entry_integrity
AFTER INSERT OR UPDATE OR DELETE ON ewms.inventory_transaction_entries
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE PROCEDURE ewms.deferred_check_receipt_inventory_integrity();

DROP TRIGGER IF EXISTS trg_receipt_document_inventory_integrity
ON ewms.receipts;
CREATE CONSTRAINT TRIGGER trg_receipt_document_inventory_integrity
AFTER INSERT OR UPDATE OR DELETE ON ewms.receipts
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE PROCEDURE ewms.deferred_check_receipt_inventory_integrity();

DROP TRIGGER IF EXISTS trg_receipt_line_inventory_integrity
ON ewms.receipt_lines;
CREATE CONSTRAINT TRIGGER trg_receipt_line_inventory_integrity
AFTER INSERT OR UPDATE OR DELETE ON ewms.receipt_lines
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE PROCEDURE ewms.deferred_check_receipt_inventory_integrity();

DROP TRIGGER IF EXISTS trg_receipt_lot_inventory_integrity ON ewms.inventory_lots;
CREATE CONSTRAINT TRIGGER trg_receipt_lot_inventory_integrity
AFTER INSERT OR UPDATE OR DELETE ON ewms.inventory_lots
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE PROCEDURE ewms.deferred_check_receipt_inventory_integrity();

DROP TRIGGER IF EXISTS trg_receipt_serial_inventory_integrity ON ewms.serial_numbers;
CREATE CONSTRAINT TRIGGER trg_receipt_serial_inventory_integrity
AFTER INSERT OR UPDATE OR DELETE ON ewms.serial_numbers
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE PROCEDURE ewms.deferred_check_receipt_inventory_integrity();

DROP TRIGGER IF EXISTS trg_prevent_core_truncate ON ewms.receipt_inventory_allocations;
CREATE TRIGGER trg_prevent_core_truncate
BEFORE TRUNCATE ON ewms.receipt_inventory_allocations
FOR EACH STATEMENT EXECUTE PROCEDURE ewms.prevent_core_document_truncate();

COMMENT ON TABLE ewms.receipt_inventory_allocations IS
    'Line-level evidence that exactly covers every positive physical destination entry of a POSTED RECEIPT transaction; final rows are immutable and reversals use a separate exact-inverse REVERSAL transaction.';

DROP TRIGGER IF EXISTS trg_validate_supplier_return_alloc
ON ewms.supplier_return_inventory_allocations;
CREATE TRIGGER trg_validate_supplier_return_alloc
BEFORE INSERT OR UPDATE ON ewms.supplier_return_inventory_allocations
FOR EACH ROW EXECUTE PROCEDURE ewms.validate_supplier_return_inventory_allocation();

DO $block$
DECLARE
    table_name text;
BEGIN
    FOREACH table_name IN ARRAY ARRAY[
        'inventory_lots','inventory_lot_attributes','serial_numbers','lpn_types','lpns',
        'stock_buckets','inventory_transaction_headers','inventory_balances','inventory_reservations',
        'inventory_holds','receipt_inventory_postings','stock_transfer_orders','stock_transfer_lines',
        'movement_tasks','putaway_tasks','replenishment_requests','replenishment_tasks',
        'inventory_adjustments','inventory_adjustment_lines','cycle_count_plans','cycle_count_tasks',
        'cycle_count_results','inventory_freezes','inventory_snapshots','inventory_valuation_layers',
        'inventory_transformations','inventory_reconciliation_runs'
    ] LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS trg_touch_row ON ewms.%I', table_name);
        EXECUTE format(
            'CREATE TRIGGER trg_touch_row BEFORE UPDATE ON ewms.%I '
            'FOR EACH ROW EXECUTE PROCEDURE ewms.touch_row()', table_name
        );
    END LOOP;

    FOREACH table_name IN ARRAY ARRAY[
        'inventory_lot_genealogy','serial_status_history','lpn_status_history',
        'lpn_location_history','lpn_relationship_history','inventory_reservation_history',
        'inventory_hold_releases','movement_confirmations','movement_task_status_history',
        'putaway_confirmations','stock_transfer_status_history','inventory_adjustment_approvals',
        'inventory_adjustment_status_history','cycle_count_observations','cycle_count_status_history',
        'inventory_snapshot_lines','inventory_valuation_movements',
        'inventory_transformation_status_history'
    ] LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS trg_append_only ON ewms.%I', table_name);
        EXECUTE format(
            'CREATE TRIGGER trg_append_only BEFORE UPDATE OR DELETE ON ewms.%I '
            'FOR EACH ROW EXECUTE PROCEDURE ewms.reject_append_only_change()', table_name
        );
    END LOOP;
END;
$block$;

COMMENT ON FUNCTION ewms.post_inventory_transaction(uuid, uuid) IS
    'Atomically validates a zero-sum signed inventory ledger, locks buckets in deterministic order, applies balances, enforces freezes/negative-stock/serial rules, and seals the header as POSTED.';
COMMENT ON TABLE ewms.inventory_freezes IS
    'Operational freeze scopes used by posting validation; count and approved adjustment operations can be selectively allowed through blocked_operations.';
COMMENT ON TABLE ewms.inventory_reconciliation_runs IS
    'Reconciliation evidence for ledger/balance, reservation, hold, serial, LPN, snapshot, and bonded/customs consistency checks.';
