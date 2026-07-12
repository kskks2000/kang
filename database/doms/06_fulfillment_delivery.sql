-- DOMS enterprise OMS schema - fulfillment execution, shipment, delivery,
-- pickup, digital/service fulfillment, and fulfillment confirmation.
-- PostgreSQL 11 compatible. Applied after 04_orchestration_inventory.sql.

-- Upstream composite tenant keys used by this module.  The underlying primary
-- keys remain unchanged; these indexes allow every operational FK to reject a
-- cross-tenant UUID at the database boundary.
CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_order_addresses_tenant_id
    ON doms.order_address_snapshots (tenant_id, id);
CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_carrier_services_tenant_id
    ON doms.carrier_services (tenant_id, id);
CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_files_tenant_id
    ON doms.files (tenant_id, id);

-- -----------------------------------------------------------------------------
-- Fulfillment orders and independent lifecycle evidence.
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS doms.fulfillment_orders (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    fulfillment_order_no varchar(120) NOT NULL,
    sales_order_id uuid NOT NULL,
    fulfillment_node_id uuid NOT NULL,
    delivery_method_id uuid REFERENCES doms.delivery_methods(id) ON DELETE RESTRICT,
    ship_to_address_snapshot_id uuid,
    fulfillment_type varchar(30) NOT NULL DEFAULT 'PHYSICAL',
    priority integer NOT NULL DEFAULT 100,
    status varchar(30) NOT NULL DEFAULT 'DRAFT',
    requested_fulfill_at timestamptz,
    promised_ship_at timestamptz,
    promised_delivery_at timestamptz,
    released_at timestamptz,
    completed_at timestamptz,
    cancelled_at timestamptz,
    idempotency_key varchar(200) NOT NULL,
    external_fulfillment_reference varchar(300),
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    updated_by uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, fulfillment_order_no),
    UNIQUE (tenant_id, sales_order_id, idempotency_key),
    CONSTRAINT fk_doms_fulfillment_order_order
        FOREIGN KEY (tenant_id, sales_order_id)
        REFERENCES doms.sales_orders(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_fulfillment_order_node
        FOREIGN KEY (tenant_id, fulfillment_node_id)
        REFERENCES doms.fulfillment_nodes(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_fulfillment_order_address
        FOREIGN KEY (tenant_id, ship_to_address_snapshot_id)
        REFERENCES doms.order_address_snapshots(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_fulfillment_order_type CHECK (fulfillment_type IN (
        'PHYSICAL','PICKUP','DIGITAL','SERVICE','DROP_SHIP','TRANSFER','MIXED'
    )),
    CONSTRAINT ck_doms_fulfillment_order_priority CHECK (priority >= 0),
    CONSTRAINT ck_doms_fulfillment_order_status CHECK (status IN (
        'DRAFT','PLANNED','RELEASED','IN_PROGRESS','PARTIALLY_FULFILLED',
        'FULFILLED','ON_HOLD','EXCEPTION','CANCELLATION_PENDING','CANCELLED','CLOSED'
    )),
    CONSTRAINT ck_doms_fulfillment_order_dates CHECK (
        (promised_delivery_at IS NULL OR promised_ship_at IS NULL OR promised_delivery_at >= promised_ship_at) AND
        (released_at IS NULL OR released_at >= created_at) AND
        (completed_at IS NULL OR completed_at >= created_at) AND
        (cancelled_at IS NULL OR cancelled_at >= created_at)
    ),
    CONSTRAINT ck_doms_fulfillment_order_terminal CHECK (
        (status NOT IN ('FULFILLED','CLOSED') OR completed_at IS NOT NULL) AND
        (status <> 'CANCELLED' OR cancelled_at IS NOT NULL)
    ),
    CONSTRAINT ck_doms_fulfillment_order_attributes CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(attributes)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_fulfillment_order_external
    ON doms.fulfillment_orders (tenant_id, external_fulfillment_reference)
    WHERE external_fulfillment_reference IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_doms_fulfillment_orders_work
    ON doms.fulfillment_orders (tenant_id, fulfillment_node_id, status, priority, promised_ship_at);

CREATE TABLE IF NOT EXISTS doms.fulfillment_order_lines (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    fulfillment_order_id uuid NOT NULL,
    line_no integer NOT NULL,
    sales_order_line_id uuid NOT NULL,
    fulfillment_allocation_id uuid NOT NULL,
    item_id uuid NOT NULL,
    uom_code varchar(20) NOT NULL REFERENCES doms.units_of_measure(uom_code),
    requested_quantity numeric(24,8) NOT NULL,
    allocated_quantity numeric(24,8) NOT NULL,
    consumed_quantity numeric(24,8) NOT NULL DEFAULT 0,
    picked_quantity numeric(24,8) NOT NULL DEFAULT 0,
    packed_quantity numeric(24,8) NOT NULL DEFAULT 0,
    shipped_quantity numeric(24,8) NOT NULL DEFAULT 0,
    delivered_quantity numeric(24,8) NOT NULL DEFAULT 0,
    fulfilled_quantity numeric(24,8) NOT NULL DEFAULT 0,
    cancelled_quantity numeric(24,8) NOT NULL DEFAULT 0,
    status varchar(30) NOT NULL DEFAULT 'PLANNED',
    idempotency_key varchar(200) NOT NULL,
    external_line_reference varchar(300),
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (fulfillment_order_id, line_no),
    UNIQUE (tenant_id, fulfillment_order_id, idempotency_key),
    CONSTRAINT fk_doms_fulfillment_line_header
        FOREIGN KEY (tenant_id, fulfillment_order_id)
        REFERENCES doms.fulfillment_orders(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_fulfillment_line_order_line
        FOREIGN KEY (tenant_id, sales_order_line_id)
        REFERENCES doms.sales_order_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_fulfillment_line_allocation
        FOREIGN KEY (tenant_id, fulfillment_allocation_id)
        REFERENCES doms.fulfillment_allocations(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_fulfillment_line_item
        FOREIGN KEY (tenant_id, item_id)
        REFERENCES doms.items(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_fulfillment_line_no CHECK (line_no > 0),
    CONSTRAINT ck_doms_fulfillment_line_quantities CHECK (
        requested_quantity > 0 AND allocated_quantity > 0 AND allocated_quantity <= requested_quantity AND
        consumed_quantity >= 0 AND picked_quantity >= 0 AND packed_quantity >= 0 AND
        shipped_quantity >= 0 AND delivered_quantity >= 0 AND fulfilled_quantity >= 0 AND
        cancelled_quantity >= 0 AND cancelled_quantity <= allocated_quantity AND
        picked_quantity <= allocated_quantity - cancelled_quantity AND
        packed_quantity <= picked_quantity AND shipped_quantity <= packed_quantity AND
        delivered_quantity <= shipped_quantity AND shipped_quantity <= fulfilled_quantity AND
        fulfilled_quantity <= consumed_quantity AND consumed_quantity <= allocated_quantity - cancelled_quantity
    ),
    CONSTRAINT ck_doms_fulfillment_line_status CHECK (status IN (
        'PLANNED','RELEASED','PICKING','PARTIALLY_PICKED','PICKED','PACKING',
        'PARTIALLY_PACKED','PACKED','PARTIALLY_SHIPPED','SHIPPED','PARTIALLY_FULFILLED',
        'FULFILLED','ON_HOLD','EXCEPTION','CANCELLED','CLOSED'
    )),
    CONSTRAINT ck_doms_fulfillment_line_attributes CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(attributes)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_fulfillment_line_external
    ON doms.fulfillment_order_lines (tenant_id, fulfillment_order_id, external_line_reference)
    WHERE external_line_reference IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_doms_fulfillment_lines_order_line
    ON doms.fulfillment_order_lines (tenant_id, sales_order_line_id, status);

CREATE TABLE IF NOT EXISTS doms.fulfillment_order_status_events (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    fulfillment_order_id uuid NOT NULL,
    event_sequence bigint NOT NULL,
    event_type varchar(40) NOT NULL,
    from_status varchar(30),
    to_status varchar(30) NOT NULL,
    reason_code varchar(100),
    detail_masked text,
    idempotency_key varchar(200),
    actor_user_id uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    source varchar(30) NOT NULL DEFAULT 'OMS',
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (fulfillment_order_id, event_sequence),
    CONSTRAINT fk_doms_fulfillment_order_event
        FOREIGN KEY (tenant_id, fulfillment_order_id)
        REFERENCES doms.fulfillment_orders(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_fulfillment_order_event_sequence CHECK (event_sequence > 0),
    CONSTRAINT ck_doms_fulfillment_order_event_source CHECK (source IN ('OMS','WMS','CHANNEL','OPERATOR','SCHEDULED_JOB','INTEGRATION')),
    CONSTRAINT ck_doms_fulfillment_order_event_metadata CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(metadata)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_fulfillment_order_event_idempotency
    ON doms.fulfillment_order_status_events (tenant_id, fulfillment_order_id, idempotency_key)
    WHERE idempotency_key IS NOT NULL;

CREATE TABLE IF NOT EXISTS doms.fulfillment_order_line_status_events (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    fulfillment_order_line_id uuid NOT NULL,
    event_sequence bigint NOT NULL,
    event_type varchar(40) NOT NULL,
    from_status varchar(30),
    to_status varchar(30) NOT NULL,
    quantity numeric(24,8) NOT NULL DEFAULT 0,
    reason_code varchar(100),
    detail_masked text,
    idempotency_key varchar(200),
    actor_user_id uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (fulfillment_order_line_id, event_sequence),
    CONSTRAINT fk_doms_fulfillment_line_event
        FOREIGN KEY (tenant_id, fulfillment_order_line_id)
        REFERENCES doms.fulfillment_order_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_fulfillment_line_event_sequence CHECK (event_sequence > 0),
    CONSTRAINT ck_doms_fulfillment_line_event_quantity CHECK (quantity >= 0),
    CONSTRAINT ck_doms_fulfillment_line_event_metadata CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(metadata)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_fulfillment_line_event_idempotency
    ON doms.fulfillment_order_line_status_events (tenant_id, fulfillment_order_line_id, idempotency_key)
    WHERE idempotency_key IS NOT NULL;

CREATE TABLE IF NOT EXISTS doms.fulfillment_holds (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    fulfillment_order_id uuid,
    fulfillment_order_line_id uuid,
    hold_type varchar(40) NOT NULL,
    reason_code varchar(100) NOT NULL,
    reason_detail text,
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    placed_by uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    placed_at timestamptz NOT NULL DEFAULT now(),
    release_due_at timestamptz,
    released_by uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    released_at timestamptz,
    release_reason text,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    CONSTRAINT fk_doms_fulfillment_hold_header
        FOREIGN KEY (tenant_id, fulfillment_order_id)
        REFERENCES doms.fulfillment_orders(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_fulfillment_hold_line
        FOREIGN KEY (tenant_id, fulfillment_order_line_id)
        REFERENCES doms.fulfillment_order_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_fulfillment_hold_target CHECK (
        num_nonnulls(fulfillment_order_id, fulfillment_order_line_id) = 1
    ),
    CONSTRAINT ck_doms_fulfillment_hold_type CHECK (hold_type IN (
        'INVENTORY','PAYMENT','RISK','ADDRESS','COMPLIANCE','CUSTOMER','CARRIER','OPERATIONAL','MANUAL'
    )),
    CONSTRAINT ck_doms_fulfillment_hold_status CHECK (status IN ('ACTIVE','RELEASED','EXPIRED','CANCELLED')),
    CONSTRAINT ck_doms_fulfillment_hold_dates CHECK (
        (release_due_at IS NULL OR release_due_at > placed_at) AND
        (released_at IS NULL OR released_at >= placed_at)
    ),
    CONSTRAINT ck_doms_fulfillment_hold_release CHECK (
        status <> 'RELEASED' OR (released_by IS NOT NULL AND released_at IS NOT NULL)
    )
);

CREATE INDEX IF NOT EXISTS ix_doms_fulfillment_holds_active
    ON doms.fulfillment_holds (tenant_id, fulfillment_order_id, fulfillment_order_line_id, placed_at)
    WHERE status = 'ACTIVE';

CREATE TABLE IF NOT EXISTS doms.fulfillment_split_relations (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    parent_fulfillment_order_id uuid NOT NULL,
    child_fulfillment_order_id uuid NOT NULL,
    relation_type varchar(30) NOT NULL DEFAULT 'SPLIT',
    sequence_no integer NOT NULL,
    reason_code varchar(100),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, parent_fulfillment_order_id, child_fulfillment_order_id, relation_type),
    CONSTRAINT fk_doms_fulfillment_split_parent
        FOREIGN KEY (tenant_id, parent_fulfillment_order_id)
        REFERENCES doms.fulfillment_orders(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_fulfillment_split_child
        FOREIGN KEY (tenant_id, child_fulfillment_order_id)
        REFERENCES doms.fulfillment_orders(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_fulfillment_split_self CHECK (parent_fulfillment_order_id <> child_fulfillment_order_id),
    CONSTRAINT ck_doms_fulfillment_split_sequence CHECK (sequence_no > 0),
    CONSTRAINT ck_doms_fulfillment_split_type CHECK (relation_type IN ('SPLIT','MERGE','REPLACEMENT','RETRY','BACKORDER_RELEASE'))
);

CREATE TABLE IF NOT EXISTS doms.fulfillment_exceptions (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    fulfillment_order_id uuid,
    fulfillment_order_line_id uuid,
    shipment_id uuid,
    package_id uuid,
    exception_type varchar(50) NOT NULL,
    severity varchar(20) NOT NULL DEFAULT 'MEDIUM',
    exception_code varchar(100) NOT NULL,
    description_masked text,
    affected_quantity numeric(24,8),
    uom_code varchar(20) REFERENCES doms.units_of_measure(uom_code),
    status varchar(20) NOT NULL DEFAULT 'OPEN',
    reported_by uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    reported_at timestamptz NOT NULL DEFAULT now(),
    assigned_to uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    resolved_by uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    resolved_at timestamptz,
    resolution_code varchar(100),
    resolution_note text,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    CONSTRAINT fk_doms_fulfillment_exception_header
        FOREIGN KEY (tenant_id, fulfillment_order_id)
        REFERENCES doms.fulfillment_orders(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_fulfillment_exception_line
        FOREIGN KEY (tenant_id, fulfillment_order_line_id)
        REFERENCES doms.fulfillment_order_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_fulfillment_exception_target CHECK (
        num_nonnulls(fulfillment_order_id, fulfillment_order_line_id, shipment_id, package_id) = 1
    ),
    CONSTRAINT ck_doms_fulfillment_exception_severity CHECK (severity IN ('LOW','MEDIUM','HIGH','CRITICAL')),
    CONSTRAINT ck_doms_fulfillment_exception_quantity CHECK (affected_quantity IS NULL OR affected_quantity > 0),
    CONSTRAINT ck_doms_fulfillment_exception_status CHECK (status IN ('OPEN','TRIAGED','INVESTIGATING','RESOLVED','WAIVED','CLOSED')),
    CONSTRAINT ck_doms_fulfillment_exception_resolution CHECK (
        status NOT IN ('RESOLVED','WAIVED','CLOSED') OR resolved_at IS NOT NULL
    ),
    CONSTRAINT ck_doms_fulfillment_exception_metadata CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(metadata)
    )
);

-- -----------------------------------------------------------------------------
-- Shipment planning, shipment execution, packages, and inventory evidence.
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS doms.shipment_plans (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    shipment_plan_no varchar(120) NOT NULL,
    fulfillment_order_id uuid NOT NULL,
    fulfillment_node_id uuid NOT NULL,
    carrier_service_id uuid,
    delivery_method_id uuid REFERENCES doms.delivery_methods(id) ON DELETE RESTRICT,
    ship_to_address_snapshot_id uuid,
    planned_ship_at timestamptz,
    planned_delivery_at timestamptz,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    idempotency_key varchar(200) NOT NULL,
    planning_metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, shipment_plan_no),
    UNIQUE (tenant_id, fulfillment_order_id, idempotency_key),
    CONSTRAINT fk_doms_shipment_plan_fulfillment
        FOREIGN KEY (tenant_id, fulfillment_order_id)
        REFERENCES doms.fulfillment_orders(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_shipment_plan_node
        FOREIGN KEY (tenant_id, fulfillment_node_id)
        REFERENCES doms.fulfillment_nodes(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_shipment_plan_carrier_service
        FOREIGN KEY (tenant_id, carrier_service_id)
        REFERENCES doms.carrier_services(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_shipment_plan_address
        FOREIGN KEY (tenant_id, ship_to_address_snapshot_id)
        REFERENCES doms.order_address_snapshots(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_shipment_plan_status CHECK (status IN ('DRAFT','READY','RELEASED','PARTIALLY_SHIPPED','SHIPPED','CANCELLED','SUPERSEDED')),
    CONSTRAINT ck_doms_shipment_plan_dates CHECK (
        planned_delivery_at IS NULL OR planned_ship_at IS NULL OR planned_delivery_at >= planned_ship_at
    ),
    CONSTRAINT ck_doms_shipment_plan_metadata CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(planning_metadata)
    )
);

CREATE TABLE IF NOT EXISTS doms.shipment_plan_lines (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    shipment_plan_id uuid NOT NULL,
    line_no integer NOT NULL,
    fulfillment_order_line_id uuid NOT NULL,
    item_id uuid NOT NULL,
    planned_quantity numeric(24,8) NOT NULL,
    cancelled_quantity numeric(24,8) NOT NULL DEFAULT 0,
    uom_code varchar(20) NOT NULL REFERENCES doms.units_of_measure(uom_code),
    status varchar(20) NOT NULL DEFAULT 'PLANNED',
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (shipment_plan_id, line_no),
    CONSTRAINT fk_doms_shipment_plan_line_header
        FOREIGN KEY (tenant_id, shipment_plan_id)
        REFERENCES doms.shipment_plans(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_shipment_plan_line_fulfillment
        FOREIGN KEY (tenant_id, fulfillment_order_line_id)
        REFERENCES doms.fulfillment_order_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_shipment_plan_line_item
        FOREIGN KEY (tenant_id, item_id)
        REFERENCES doms.items(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_shipment_plan_line_no CHECK (line_no > 0),
    CONSTRAINT ck_doms_shipment_plan_line_quantity CHECK (
        planned_quantity > 0 AND cancelled_quantity >= 0 AND cancelled_quantity <= planned_quantity
    ),
    CONSTRAINT ck_doms_shipment_plan_line_status CHECK (status IN ('PLANNED','RELEASED','PARTIALLY_SHIPPED','SHIPPED','CANCELLED')),
    CONSTRAINT ck_doms_shipment_plan_line_attributes CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(attributes)
    )
);

CREATE TABLE IF NOT EXISTS doms.shipments (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    shipment_no varchar(120) NOT NULL,
    shipment_plan_id uuid NOT NULL,
    fulfillment_order_id uuid NOT NULL,
    fulfillment_node_id uuid NOT NULL,
    carrier_service_id uuid,
    ship_to_address_snapshot_id uuid,
    shipment_type varchar(30) NOT NULL DEFAULT 'OUTBOUND',
    status varchar(30) NOT NULL DEFAULT 'PLANNED',
    idempotency_key varchar(200) NOT NULL,
    external_shipment_reference varchar(300),
    planned_ship_at timestamptz,
    tendered_at timestamptz,
    shipped_at timestamptz,
    estimated_delivery_at timestamptz,
    delivered_at timestamptz,
    closed_at timestamptz,
    total_package_count integer NOT NULL DEFAULT 0,
    total_weight numeric(24,8),
    weight_uom_code varchar(20) REFERENCES doms.units_of_measure(uom_code),
    total_volume numeric(24,9),
    volume_uom_code varchar(20) REFERENCES doms.units_of_measure(uom_code),
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, shipment_no),
    UNIQUE (tenant_id, shipment_plan_id, idempotency_key),
    CONSTRAINT fk_doms_shipment_plan
        FOREIGN KEY (tenant_id, shipment_plan_id)
        REFERENCES doms.shipment_plans(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_shipment_fulfillment
        FOREIGN KEY (tenant_id, fulfillment_order_id)
        REFERENCES doms.fulfillment_orders(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_shipment_node
        FOREIGN KEY (tenant_id, fulfillment_node_id)
        REFERENCES doms.fulfillment_nodes(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_shipment_carrier_service
        FOREIGN KEY (tenant_id, carrier_service_id)
        REFERENCES doms.carrier_services(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_shipment_address
        FOREIGN KEY (tenant_id, ship_to_address_snapshot_id)
        REFERENCES doms.order_address_snapshots(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_shipment_type CHECK (shipment_type IN ('OUTBOUND','DROP_SHIP','TRANSFER','RETURN','PARCEL','FREIGHT','COURIER','OTHER')),
    CONSTRAINT ck_doms_shipment_status CHECK (status IN (
        'PLANNED','READY','BOOKING','BOOKED','PACKING','PACKED','TENDERING','TENDERED',
        'SHIPPED','IN_TRANSIT','PARTIALLY_DELIVERED','DELIVERED','EXCEPTION','CANCELLED','CLOSED'
    )),
    CONSTRAINT ck_doms_shipment_totals CHECK (
        total_package_count >= 0 AND (total_weight IS NULL OR total_weight >= 0) AND
        (total_volume IS NULL OR total_volume >= 0)
    ),
    CONSTRAINT ck_doms_shipment_dates CHECK (
        (tendered_at IS NULL OR tendered_at >= created_at) AND
        (shipped_at IS NULL OR shipped_at >= COALESCE(tendered_at, created_at)) AND
        (delivered_at IS NULL OR delivered_at >= COALESCE(shipped_at, created_at)) AND
        (closed_at IS NULL OR closed_at >= COALESCE(delivered_at, shipped_at, created_at))
    ),
    CONSTRAINT ck_doms_shipment_terminal CHECK (
        (status NOT IN ('SHIPPED','IN_TRANSIT','PARTIALLY_DELIVERED','DELIVERED','CLOSED') OR shipped_at IS NOT NULL) AND
        (status NOT IN ('DELIVERED','CLOSED') OR delivered_at IS NOT NULL)
    ),
    CONSTRAINT ck_doms_shipment_attributes CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(attributes)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_shipment_external
    ON doms.shipments (tenant_id, external_shipment_reference)
    WHERE external_shipment_reference IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_doms_shipments_work
    ON doms.shipments (tenant_id, fulfillment_node_id, status, planned_ship_at);

CREATE TABLE IF NOT EXISTS doms.shipment_lines (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    shipment_id uuid NOT NULL,
    shipment_plan_line_id uuid NOT NULL,
    fulfillment_order_line_id uuid NOT NULL,
    line_no integer NOT NULL,
    item_id uuid NOT NULL,
    uom_code varchar(20) NOT NULL REFERENCES doms.units_of_measure(uom_code),
    planned_quantity numeric(24,8) NOT NULL,
    packed_quantity numeric(24,8) NOT NULL DEFAULT 0,
    shipped_quantity numeric(24,8) NOT NULL DEFAULT 0,
    delivered_quantity numeric(24,8) NOT NULL DEFAULT 0,
    cancelled_quantity numeric(24,8) NOT NULL DEFAULT 0,
    status varchar(30) NOT NULL DEFAULT 'PLANNED',
    country_of_origin char(2) REFERENCES doms.countries(country_code),
    declared_value numeric(20,6),
    currency_code char(3) REFERENCES doms.currencies(currency_code),
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (shipment_id, line_no),
    CONSTRAINT fk_doms_shipment_line_header
        FOREIGN KEY (tenant_id, shipment_id)
        REFERENCES doms.shipments(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_shipment_line_plan_line
        FOREIGN KEY (tenant_id, shipment_plan_line_id)
        REFERENCES doms.shipment_plan_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_shipment_line_fulfillment
        FOREIGN KEY (tenant_id, fulfillment_order_line_id)
        REFERENCES doms.fulfillment_order_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_shipment_line_item
        FOREIGN KEY (tenant_id, item_id)
        REFERENCES doms.items(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_shipment_line_no CHECK (line_no > 0),
    CONSTRAINT ck_doms_shipment_line_quantity CHECK (
        planned_quantity > 0 AND packed_quantity >= 0 AND shipped_quantity >= 0 AND
        delivered_quantity >= 0 AND cancelled_quantity >= 0 AND
        cancelled_quantity <= planned_quantity AND packed_quantity <= planned_quantity - cancelled_quantity AND
        shipped_quantity <= packed_quantity AND delivered_quantity <= shipped_quantity
    ),
    CONSTRAINT ck_doms_shipment_line_status CHECK (status IN (
        'PLANNED','PACKING','PARTIALLY_PACKED','PACKED','PARTIALLY_SHIPPED',
        'SHIPPED','PARTIALLY_DELIVERED','DELIVERED','EXCEPTION','CANCELLED','CLOSED'
    )),
    CONSTRAINT ck_doms_shipment_line_value CHECK (declared_value IS NULL OR declared_value >= 0)
);

CREATE INDEX IF NOT EXISTS ix_doms_shipment_lines_fulfillment
    ON doms.shipment_lines (tenant_id, fulfillment_order_line_id, status);

CREATE TABLE IF NOT EXISTS doms.shipment_status_events (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    shipment_id uuid NOT NULL,
    event_sequence bigint NOT NULL,
    event_type varchar(50) NOT NULL,
    from_status varchar(30),
    to_status varchar(30) NOT NULL,
    location_text_masked text,
    reason_code varchar(100),
    detail_masked text,
    idempotency_key varchar(200),
    external_event_reference varchar(300),
    actor_user_id uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    occurred_at timestamptz NOT NULL,
    received_at timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (shipment_id, event_sequence),
    CONSTRAINT fk_doms_shipment_status_event
        FOREIGN KEY (tenant_id, shipment_id)
        REFERENCES doms.shipments(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_shipment_status_event_sequence CHECK (event_sequence > 0),
    CONSTRAINT ck_doms_shipment_status_event_metadata CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(metadata)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_shipment_status_event_idempotency
    ON doms.shipment_status_events (tenant_id, shipment_id, idempotency_key)
    WHERE idempotency_key IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_shipment_status_event_external
    ON doms.shipment_status_events (tenant_id, external_event_reference)
    WHERE external_event_reference IS NOT NULL;

CREATE TABLE IF NOT EXISTS doms.packages (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    shipment_id uuid NOT NULL,
    parent_package_id uuid,
    package_no varchar(150) NOT NULL,
    package_type varchar(30) NOT NULL DEFAULT 'CARTON',
    sscc varchar(30),
    status varchar(20) NOT NULL DEFAULT 'OPEN',
    gross_weight numeric(24,8),
    net_weight numeric(24,8),
    weight_uom_code varchar(20) REFERENCES doms.units_of_measure(uom_code),
    length_value numeric(20,6),
    width_value numeric(20,6),
    height_value numeric(20,6),
    dimension_uom_code varchar(20) REFERENCES doms.units_of_measure(uom_code),
    declared_value numeric(20,6),
    currency_code char(3) REFERENCES doms.currencies(currency_code),
    sealed_at timestamptz,
    shipped_at timestamptz,
    delivered_at timestamptz,
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, package_no),
    CONSTRAINT fk_doms_package_shipment
        FOREIGN KEY (tenant_id, shipment_id)
        REFERENCES doms.shipments(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_package_parent
        FOREIGN KEY (tenant_id, parent_package_id)
        REFERENCES doms.packages(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_package_parent CHECK (parent_package_id IS NULL OR parent_package_id <> id),
    CONSTRAINT ck_doms_package_type CHECK (package_type IN ('CARTON','PALLET','TOTE','BAG','CRATE','DRUM','ENVELOPE','CONTAINER','OTHER')),
    CONSTRAINT ck_doms_package_status CHECK (status IN ('OPEN','PACKING','PACKED','SEALED','STAGED','TENDERED','SHIPPED','IN_TRANSIT','DELIVERED','EXCEPTION','VOID')),
    CONSTRAINT ck_doms_package_weight CHECK (
        (gross_weight IS NULL OR gross_weight >= 0) AND (net_weight IS NULL OR net_weight >= 0) AND
        (gross_weight IS NULL OR net_weight IS NULL OR gross_weight >= net_weight)
    ),
    CONSTRAINT ck_doms_package_dimensions CHECK (
        (length_value IS NULL OR length_value >= 0) AND (width_value IS NULL OR width_value >= 0) AND
        (height_value IS NULL OR height_value >= 0)
    ),
    CONSTRAINT ck_doms_package_value CHECK (declared_value IS NULL OR declared_value >= 0),
    CONSTRAINT ck_doms_package_dates CHECK (
        (shipped_at IS NULL OR shipped_at >= COALESCE(sealed_at, created_at)) AND
        (delivered_at IS NULL OR delivered_at >= COALESCE(shipped_at, created_at))
    ),
    CONSTRAINT ck_doms_package_attributes CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(attributes)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_package_sscc
    ON doms.packages (tenant_id, sscc) WHERE sscc IS NOT NULL;

CREATE TABLE IF NOT EXISTS doms.package_items (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    package_id uuid NOT NULL,
    shipment_line_id uuid NOT NULL,
    fulfillment_order_line_id uuid NOT NULL,
    item_id uuid NOT NULL,
    packed_quantity numeric(24,8) NOT NULL,
    uom_code varchar(20) NOT NULL REFERENCES doms.units_of_measure(uom_code),
    idempotency_key varchar(200) NOT NULL,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, package_id, shipment_line_id, idempotency_key),
    CONSTRAINT fk_doms_package_item_package
        FOREIGN KEY (tenant_id, package_id)
        REFERENCES doms.packages(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_package_item_shipment_line
        FOREIGN KEY (tenant_id, shipment_line_id)
        REFERENCES doms.shipment_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_package_item_fulfillment_line
        FOREIGN KEY (tenant_id, fulfillment_order_line_id)
        REFERENCES doms.fulfillment_order_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_package_item_item
        FOREIGN KEY (tenant_id, item_id)
        REFERENCES doms.items(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_package_item_quantity CHECK (packed_quantity > 0)
);

CREATE INDEX IF NOT EXISTS ix_doms_package_items_shipment_line
    ON doms.package_items (tenant_id, shipment_line_id, package_id);

CREATE TABLE IF NOT EXISTS doms.package_status_events (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    package_id uuid NOT NULL,
    event_sequence bigint NOT NULL,
    event_type varchar(40) NOT NULL,
    from_status varchar(20),
    to_status varchar(20) NOT NULL,
    reason_code varchar(100),
    idempotency_key varchar(200),
    actor_user_id uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (package_id, event_sequence),
    CONSTRAINT fk_doms_package_status_event
        FOREIGN KEY (tenant_id, package_id)
        REFERENCES doms.packages(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_package_status_event_sequence CHECK (event_sequence > 0),
    CONSTRAINT ck_doms_package_status_event_metadata CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(metadata)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_package_status_event_idempotency
    ON doms.package_status_events (tenant_id, package_id, idempotency_key)
    WHERE idempotency_key IS NOT NULL;

CREATE TABLE IF NOT EXISTS doms.package_lot_evidence (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    package_item_id uuid NOT NULL,
    lot_no varchar(150) NOT NULL,
    quantity numeric(24,8) NOT NULL,
    manufacture_date date,
    expiry_date date,
    source_system_reference varchar(300),
    evidence_file_id uuid,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    captured_at timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, package_item_id, lot_no),
    CONSTRAINT fk_doms_package_lot_item
        FOREIGN KEY (tenant_id, package_item_id)
        REFERENCES doms.package_items(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_package_lot_file
        FOREIGN KEY (tenant_id, evidence_file_id)
        REFERENCES doms.files(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_package_lot_quantity CHECK (quantity > 0),
    CONSTRAINT ck_doms_package_lot_dates CHECK (expiry_date IS NULL OR manufacture_date IS NULL OR expiry_date >= manufacture_date),
    CONSTRAINT ck_doms_package_lot_metadata CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(metadata)
    )
);

CREATE TABLE IF NOT EXISTS doms.package_serial_evidence (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    package_item_id uuid NOT NULL,
    serial_number_encrypted text,
    serial_number_hash char(64) NOT NULL,
    serial_number_masked varchar(150),
    source_system_reference varchar(300),
    evidence_file_id uuid,
    captured_at timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, serial_number_hash),
    UNIQUE (tenant_id, package_item_id, serial_number_hash),
    CONSTRAINT fk_doms_package_serial_item
        FOREIGN KEY (tenant_id, package_item_id)
        REFERENCES doms.package_items(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_package_serial_file
        FOREIGN KEY (tenant_id, evidence_file_id)
        REFERENCES doms.files(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_package_serial_hash CHECK (serial_number_hash ~ '^[0-9A-Fa-f]{64}$')
);

ALTER TABLE doms.fulfillment_exceptions
    DROP CONSTRAINT IF EXISTS fk_doms_fulfillment_exception_shipment;
ALTER TABLE doms.fulfillment_exceptions
    ADD CONSTRAINT fk_doms_fulfillment_exception_shipment
    FOREIGN KEY (tenant_id, shipment_id)
    REFERENCES doms.shipments(tenant_id, id) ON DELETE RESTRICT;
ALTER TABLE doms.fulfillment_exceptions
    DROP CONSTRAINT IF EXISTS fk_doms_fulfillment_exception_package;
ALTER TABLE doms.fulfillment_exceptions
    ADD CONSTRAINT fk_doms_fulfillment_exception_package
    FOREIGN KEY (tenant_id, package_id)
    REFERENCES doms.packages(tenant_id, id) ON DELETE RESTRICT;

-- -----------------------------------------------------------------------------
-- Tracking, carrier booking, labels, manifests, and shipping costs.
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS doms.shipment_tracking_numbers (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    shipment_id uuid,
    package_id uuid,
    carrier_service_id uuid NOT NULL,
    tracking_number varchar(300) NOT NULL,
    tracking_type varchar(30) NOT NULL DEFAULT 'OUTBOUND',
    external_tracking_reference varchar(300),
    is_primary boolean NOT NULL DEFAULT false,
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    activated_at timestamptz NOT NULL DEFAULT now(),
    voided_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, carrier_service_id, tracking_number),
    CONSTRAINT fk_doms_tracking_shipment
        FOREIGN KEY (tenant_id, shipment_id)
        REFERENCES doms.shipments(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_tracking_package
        FOREIGN KEY (tenant_id, package_id)
        REFERENCES doms.packages(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_tracking_carrier_service
        FOREIGN KEY (tenant_id, carrier_service_id)
        REFERENCES doms.carrier_services(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_tracking_target CHECK (num_nonnulls(shipment_id, package_id) = 1),
    CONSTRAINT ck_doms_tracking_type CHECK (tracking_type IN ('OUTBOUND','RETURN','MASTER','CHILD','LAST_MILE')),
    CONSTRAINT ck_doms_tracking_status CHECK (status IN ('ACTIVE','DELIVERED','VOID','REPLACED')),
    CONSTRAINT ck_doms_tracking_void CHECK (status <> 'VOID' OR voided_at IS NOT NULL)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_tracking_external
    ON doms.shipment_tracking_numbers (tenant_id, external_tracking_reference)
    WHERE external_tracking_reference IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_tracking_primary_shipment
    ON doms.shipment_tracking_numbers (tenant_id, shipment_id)
    WHERE shipment_id IS NOT NULL AND is_primary AND status = 'ACTIVE';
CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_tracking_primary_package
    ON doms.shipment_tracking_numbers (tenant_id, package_id)
    WHERE package_id IS NOT NULL AND is_primary AND status = 'ACTIVE';

CREATE TABLE IF NOT EXISTS doms.shipment_tracking_events (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    shipment_tracking_number_id uuid NOT NULL,
    event_sequence bigint NOT NULL,
    event_code varchar(100) NOT NULL,
    event_status varchar(40) NOT NULL,
    event_description_masked text,
    location_text_masked text,
    latitude numeric(10,7),
    longitude numeric(10,7),
    external_event_reference varchar(300),
    idempotency_key varchar(200),
    payload_summary jsonb NOT NULL DEFAULT '{}'::jsonb,
    occurred_at timestamptz NOT NULL,
    received_at timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (shipment_tracking_number_id, event_sequence),
    CONSTRAINT fk_doms_tracking_event_number
        FOREIGN KEY (tenant_id, shipment_tracking_number_id)
        REFERENCES doms.shipment_tracking_numbers(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_tracking_event_sequence CHECK (event_sequence > 0),
    CONSTRAINT ck_doms_tracking_event_lat CHECK (latitude IS NULL OR latitude BETWEEN -90 AND 90),
    CONSTRAINT ck_doms_tracking_event_lon CHECK (longitude IS NULL OR longitude BETWEEN -180 AND 180),
    CONSTRAINT ck_doms_tracking_event_payload CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(payload_summary)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_tracking_event_external
    ON doms.shipment_tracking_events (tenant_id, external_event_reference)
    WHERE external_event_reference IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_tracking_event_idempotency
    ON doms.shipment_tracking_events (tenant_id, shipment_tracking_number_id, idempotency_key)
    WHERE idempotency_key IS NOT NULL;

CREATE TABLE IF NOT EXISTS doms.carrier_booking_requests (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    booking_request_no varchar(120) NOT NULL,
    shipment_id uuid NOT NULL,
    carrier_service_id uuid NOT NULL,
    idempotency_key varchar(200) NOT NULL,
    requested_pickup_at timestamptz,
    requested_delivery_at timestamptz,
    status varchar(20) NOT NULL DEFAULT 'PENDING',
    attempt_count integer NOT NULL DEFAULT 0,
    selected_attempt_id uuid,
    request_summary jsonb NOT NULL DEFAULT '{}'::jsonb,
    completed_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, booking_request_no),
    UNIQUE (tenant_id, shipment_id, idempotency_key),
    CONSTRAINT fk_doms_booking_request_shipment
        FOREIGN KEY (tenant_id, shipment_id)
        REFERENCES doms.shipments(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_booking_request_service
        FOREIGN KEY (tenant_id, carrier_service_id)
        REFERENCES doms.carrier_services(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_booking_request_dates CHECK (
        requested_delivery_at IS NULL OR requested_pickup_at IS NULL OR requested_delivery_at >= requested_pickup_at
    ),
    CONSTRAINT ck_doms_booking_request_status CHECK (status IN ('PENDING','IN_PROGRESS','BOOKED','FAILED','CANCELLED','EXPIRED')),
    CONSTRAINT ck_doms_booking_request_attempts CHECK (attempt_count >= 0),
    CONSTRAINT ck_doms_booking_request_completed CHECK (
        status NOT IN ('BOOKED','FAILED','CANCELLED','EXPIRED') OR completed_at IS NOT NULL
    ),
    CONSTRAINT ck_doms_booking_request_summary CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(request_summary)
    )
);

CREATE TABLE IF NOT EXISTS doms.carrier_booking_attempts (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    carrier_booking_request_id uuid NOT NULL,
    attempt_no integer NOT NULL,
    request_idempotency_key varchar(200) NOT NULL,
    provider_booking_reference varchar(300),
    provider_response_code varchar(100),
    status varchar(20) NOT NULL,
    failure_code varchar(100),
    failure_detail_masked text,
    retryable boolean NOT NULL DEFAULT false,
    response_summary jsonb NOT NULL DEFAULT '{}'::jsonb,
    started_at timestamptz NOT NULL DEFAULT now(),
    completed_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (carrier_booking_request_id, attempt_no),
    UNIQUE (tenant_id, request_idempotency_key),
    CONSTRAINT fk_doms_booking_attempt_request
        FOREIGN KEY (tenant_id, carrier_booking_request_id)
        REFERENCES doms.carrier_booking_requests(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_booking_attempt_no CHECK (attempt_no > 0),
    CONSTRAINT ck_doms_booking_attempt_status CHECK (status IN ('STARTED','SUCCEEDED','FAILED','TIMED_OUT','CANCELLED')),
    CONSTRAINT ck_doms_booking_attempt_dates CHECK (completed_at IS NULL OR completed_at >= started_at),
    CONSTRAINT ck_doms_booking_attempt_completed CHECK (status = 'STARTED' OR completed_at IS NOT NULL),
    CONSTRAINT ck_doms_booking_attempt_response CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(response_summary)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_booking_attempt_provider
    ON doms.carrier_booking_attempts (tenant_id, provider_booking_reference)
    WHERE provider_booking_reference IS NOT NULL;

ALTER TABLE doms.carrier_booking_requests
    DROP CONSTRAINT IF EXISTS fk_doms_booking_request_selected_attempt;
ALTER TABLE doms.carrier_booking_requests
    ADD CONSTRAINT fk_doms_booking_request_selected_attempt
    FOREIGN KEY (tenant_id, selected_attempt_id)
    REFERENCES doms.carrier_booking_attempts(tenant_id, id) ON DELETE RESTRICT;

CREATE TABLE IF NOT EXISTS doms.shipping_labels (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    shipment_id uuid,
    package_id uuid,
    carrier_service_id uuid NOT NULL,
    tracking_number_id uuid,
    label_type varchar(30) NOT NULL DEFAULT 'CARRIER',
    label_format varchar(30) NOT NULL,
    label_file_id uuid NOT NULL,
    label_sha256 char(64) NOT NULL,
    provider_label_reference varchar(300),
    idempotency_key varchar(200) NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'ACTIVE',
    generated_at timestamptz NOT NULL DEFAULT now(),
    voided_at timestamptz,
    void_reason text,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, idempotency_key),
    CONSTRAINT fk_doms_shipping_label_shipment
        FOREIGN KEY (tenant_id, shipment_id)
        REFERENCES doms.shipments(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_shipping_label_package
        FOREIGN KEY (tenant_id, package_id)
        REFERENCES doms.packages(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_shipping_label_service
        FOREIGN KEY (tenant_id, carrier_service_id)
        REFERENCES doms.carrier_services(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_shipping_label_tracking
        FOREIGN KEY (tenant_id, tracking_number_id)
        REFERENCES doms.shipment_tracking_numbers(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_shipping_label_file
        FOREIGN KEY (tenant_id, label_file_id)
        REFERENCES doms.files(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_shipping_label_target CHECK (num_nonnulls(shipment_id, package_id) = 1),
    CONSTRAINT ck_doms_shipping_label_type CHECK (label_type IN ('CARRIER','RETURN','CUSTOMS','HAZMAT','ADDRESS','CONTENT')),
    CONSTRAINT ck_doms_shipping_label_format CHECK (label_format IN ('PDF','PNG','ZPL','EPL','SVG')),
    CONSTRAINT ck_doms_shipping_label_hash CHECK (label_sha256 ~ '^[0-9A-Fa-f]{64}$'),
    CONSTRAINT ck_doms_shipping_label_status CHECK (status IN ('ACTIVE','VOID','REPLACED')),
    CONSTRAINT ck_doms_shipping_label_void CHECK (status <> 'VOID' OR (voided_at IS NOT NULL AND void_reason IS NOT NULL))
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_shipping_label_provider
    ON doms.shipping_labels (tenant_id, provider_label_reference)
    WHERE provider_label_reference IS NOT NULL;

CREATE TABLE IF NOT EXISTS doms.shipping_manifests (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    manifest_no varchar(120) NOT NULL,
    fulfillment_node_id uuid NOT NULL,
    carrier_service_id uuid NOT NULL,
    manifest_type varchar(30) NOT NULL DEFAULT 'PARCEL',
    external_manifest_reference varchar(300),
    document_file_id uuid,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    closed_at timestamptz,
    transmitted_at timestamptz,
    accepted_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, manifest_no),
    CONSTRAINT fk_doms_manifest_node
        FOREIGN KEY (tenant_id, fulfillment_node_id)
        REFERENCES doms.fulfillment_nodes(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_manifest_service
        FOREIGN KEY (tenant_id, carrier_service_id)
        REFERENCES doms.carrier_services(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_manifest_file
        FOREIGN KEY (tenant_id, document_file_id)
        REFERENCES doms.files(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_manifest_type CHECK (manifest_type IN ('PARCEL','COURIER','LTL','FTL','AIR','OCEAN','EXPORT','RETURN','OTHER')),
    CONSTRAINT ck_doms_manifest_status CHECK (status IN ('DRAFT','FINALIZED','TRANSMITTED','ACCEPTED','REJECTED','VOID')),
    CONSTRAINT ck_doms_manifest_dates CHECK (
        (transmitted_at IS NULL OR closed_at IS NULL OR transmitted_at >= closed_at) AND
        (accepted_at IS NULL OR transmitted_at IS NULL OR accepted_at >= transmitted_at)
    ),
    CONSTRAINT ck_doms_manifest_closed CHECK (
        status NOT IN ('FINALIZED','TRANSMITTED','ACCEPTED','REJECTED') OR closed_at IS NOT NULL
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_manifest_external
    ON doms.shipping_manifests (tenant_id, external_manifest_reference)
    WHERE external_manifest_reference IS NOT NULL;

CREATE TABLE IF NOT EXISTS doms.shipping_manifest_links (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    shipping_manifest_id uuid NOT NULL,
    link_sequence integer NOT NULL,
    shipment_id uuid,
    package_id uuid,
    status varchar(20) NOT NULL DEFAULT 'INCLUDED',
    linked_at timestamptz NOT NULL DEFAULT now(),
    removed_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (shipping_manifest_id, link_sequence),
    CONSTRAINT fk_doms_manifest_link_header
        FOREIGN KEY (tenant_id, shipping_manifest_id)
        REFERENCES doms.shipping_manifests(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_manifest_link_shipment
        FOREIGN KEY (tenant_id, shipment_id)
        REFERENCES doms.shipments(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_manifest_link_package
        FOREIGN KEY (tenant_id, package_id)
        REFERENCES doms.packages(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_manifest_link_sequence CHECK (link_sequence > 0),
    CONSTRAINT ck_doms_manifest_link_target CHECK (num_nonnulls(shipment_id, package_id) = 1),
    CONSTRAINT ck_doms_manifest_link_status CHECK (status IN ('INCLUDED','REMOVED','REJECTED')),
    CONSTRAINT ck_doms_manifest_link_removed CHECK (status <> 'REMOVED' OR removed_at IS NOT NULL)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_manifest_link_shipment
    ON doms.shipping_manifest_links (shipping_manifest_id, shipment_id)
    WHERE shipment_id IS NOT NULL AND status = 'INCLUDED';
CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_manifest_link_package
    ON doms.shipping_manifest_links (shipping_manifest_id, package_id)
    WHERE package_id IS NOT NULL AND status = 'INCLUDED';

CREATE TABLE IF NOT EXISTS doms.shipping_cost_facts (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    shipment_id uuid NOT NULL,
    package_id uuid,
    cost_sequence integer NOT NULL,
    cost_type varchar(40) NOT NULL,
    cost_source varchar(30) NOT NULL,
    estimated_amount numeric(20,6) NOT NULL DEFAULT 0,
    actual_amount numeric(20,6),
    currency_code char(3) NOT NULL REFERENCES doms.currencies(currency_code),
    provider_cost_reference varchar(300),
    status varchar(20) NOT NULL DEFAULT 'ESTIMATED',
    posted_at timestamptz,
    reversal_of_id uuid,
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (shipment_id, cost_sequence),
    CONSTRAINT fk_doms_shipping_cost_shipment
        FOREIGN KEY (tenant_id, shipment_id)
        REFERENCES doms.shipments(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_shipping_cost_package
        FOREIGN KEY (tenant_id, package_id)
        REFERENCES doms.packages(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_shipping_cost_reversal
        FOREIGN KEY (tenant_id, reversal_of_id)
        REFERENCES doms.shipping_cost_facts(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_shipping_cost_sequence CHECK (cost_sequence > 0),
    CONSTRAINT ck_doms_shipping_cost_type CHECK (cost_type IN ('BASE_FREIGHT','FUEL','REMOTE_AREA','RESIDENTIAL','SIGNATURE','INSURANCE','DUTY','TAX','HANDLING','ADJUSTMENT','OTHER')),
    CONSTRAINT ck_doms_shipping_cost_source CHECK (cost_source IN ('RATE_SHOP','CARRIER_QUOTE','CARRIER_INVOICE','MANUAL','CONTRACT')),
    CONSTRAINT ck_doms_shipping_cost_amount CHECK (estimated_amount >= 0 AND (actual_amount IS NULL OR actual_amount >= 0)),
    CONSTRAINT ck_doms_shipping_cost_status CHECK (status IN ('ESTIMATED','ACCRUED','INVOICED','POSTED','DISPUTED','REVERSED')),
    CONSTRAINT ck_doms_shipping_cost_posted CHECK (status NOT IN ('POSTED','REVERSED') OR posted_at IS NOT NULL),
    CONSTRAINT ck_doms_shipping_cost_reversal CHECK (
        (status = 'REVERSED' AND reversal_of_id IS NOT NULL) OR status <> 'REVERSED'
    ),
    CONSTRAINT ck_doms_shipping_cost_attributes CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(attributes)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_shipping_cost_provider
    ON doms.shipping_cost_facts (tenant_id, provider_cost_reference)
    WHERE provider_cost_reference IS NOT NULL;

-- -----------------------------------------------------------------------------
-- Pickup, appointments, delivery evidence, exceptions, and POD objects.
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS doms.pickup_orders (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    pickup_order_no varchar(120) NOT NULL,
    fulfillment_order_id uuid NOT NULL,
    fulfillment_node_id uuid NOT NULL,
    pickup_address_snapshot_id uuid,
    status varchar(30) NOT NULL DEFAULT 'PLANNED',
    idempotency_key varchar(200) NOT NULL,
    external_pickup_reference varchar(300),
    pickup_code_hash char(64),
    pickup_code_last4 char(4),
    scheduled_from timestamptz,
    scheduled_to timestamptz,
    ready_at timestamptz,
    picked_up_at timestamptz,
    expires_at timestamptz,
    recipient_name_masked varchar(200),
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, pickup_order_no),
    UNIQUE (tenant_id, fulfillment_order_id, idempotency_key),
    CONSTRAINT fk_doms_pickup_fulfillment
        FOREIGN KEY (tenant_id, fulfillment_order_id)
        REFERENCES doms.fulfillment_orders(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_pickup_node
        FOREIGN KEY (tenant_id, fulfillment_node_id)
        REFERENCES doms.fulfillment_nodes(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_pickup_address
        FOREIGN KEY (tenant_id, pickup_address_snapshot_id)
        REFERENCES doms.order_address_snapshots(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_pickup_status CHECK (status IN ('PLANNED','CONFIRMED','PREPARING','READY','PARTIALLY_PICKED_UP','PICKED_UP','NO_SHOW','EXPIRED','CANCELLED','CLOSED')),
    CONSTRAINT ck_doms_pickup_code_hash CHECK (pickup_code_hash IS NULL OR pickup_code_hash ~ '^[0-9A-Fa-f]{64}$'),
    CONSTRAINT ck_doms_pickup_code_last4 CHECK (pickup_code_last4 IS NULL OR pickup_code_last4 ~ '^[0-9A-Za-z]{4}$'),
    CONSTRAINT ck_doms_pickup_dates CHECK (
        (scheduled_to IS NULL OR scheduled_from IS NULL OR scheduled_to > scheduled_from) AND
        (ready_at IS NULL OR ready_at >= created_at) AND
        (picked_up_at IS NULL OR picked_up_at >= COALESCE(ready_at, created_at)) AND
        (expires_at IS NULL OR expires_at > created_at)
    ),
    CONSTRAINT ck_doms_pickup_terminal CHECK (status NOT IN ('PICKED_UP','CLOSED') OR picked_up_at IS NOT NULL),
    CONSTRAINT ck_doms_pickup_attributes CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(attributes)
    )
);

COMMENT ON COLUMN doms.pickup_orders.pickup_code_hash IS
    'Keyed pickup-code lookup hash. Plain pickup verification codes are prohibited.';

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_pickup_external
    ON doms.pickup_orders (tenant_id, external_pickup_reference)
    WHERE external_pickup_reference IS NOT NULL;

CREATE TABLE IF NOT EXISTS doms.pickup_events (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    pickup_order_id uuid NOT NULL,
    event_sequence bigint NOT NULL,
    event_type varchar(50) NOT NULL,
    from_status varchar(30),
    to_status varchar(30) NOT NULL,
    quantity numeric(24,8) NOT NULL DEFAULT 0,
    verification_method varchar(30),
    verification_result varchar(20),
    idempotency_key varchar(200),
    actor_user_id uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    detail_masked text,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (pickup_order_id, event_sequence),
    CONSTRAINT fk_doms_pickup_event_order
        FOREIGN KEY (tenant_id, pickup_order_id)
        REFERENCES doms.pickup_orders(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_pickup_event_sequence CHECK (event_sequence > 0),
    CONSTRAINT ck_doms_pickup_event_quantity CHECK (quantity >= 0),
    CONSTRAINT ck_doms_pickup_event_verification CHECK (
        verification_method IS NULL OR verification_method IN ('CODE','ID_CHECK','QR','BARCODE','SIGNATURE','MANUAL')
    ),
    CONSTRAINT ck_doms_pickup_event_result CHECK (
        verification_result IS NULL OR verification_result IN ('PASSED','FAILED','BYPASSED')
    ),
    CONSTRAINT ck_doms_pickup_event_metadata CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(metadata)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_pickup_event_idempotency
    ON doms.pickup_events (tenant_id, pickup_order_id, idempotency_key)
    WHERE idempotency_key IS NOT NULL;

CREATE TABLE IF NOT EXISTS doms.delivery_appointments (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    appointment_no varchar(120) NOT NULL,
    fulfillment_order_id uuid NOT NULL,
    shipment_id uuid,
    pickup_order_id uuid,
    appointment_type varchar(30) NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'REQUESTED',
    idempotency_key varchar(200) NOT NULL,
    scheduled_from timestamptz NOT NULL,
    scheduled_to timestamptz NOT NULL,
    timezone varchar(100) NOT NULL DEFAULT 'Asia/Seoul',
    confirmed_at timestamptz,
    completed_at timestamptz,
    cancelled_at timestamptz,
    customer_note_encrypted text,
    customer_note_masked text,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, appointment_no),
    UNIQUE (tenant_id, fulfillment_order_id, idempotency_key),
    CONSTRAINT fk_doms_appointment_fulfillment
        FOREIGN KEY (tenant_id, fulfillment_order_id)
        REFERENCES doms.fulfillment_orders(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_appointment_shipment
        FOREIGN KEY (tenant_id, shipment_id)
        REFERENCES doms.shipments(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_appointment_pickup
        FOREIGN KEY (tenant_id, pickup_order_id)
        REFERENCES doms.pickup_orders(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_appointment_target CHECK (num_nonnulls(shipment_id, pickup_order_id) <= 1),
    CONSTRAINT ck_doms_appointment_type CHECK (appointment_type IN ('DELIVERY','PICKUP','INSTALLATION','SERVICE','CURBSIDE','LOCKER')),
    CONSTRAINT ck_doms_appointment_status CHECK (status IN ('REQUESTED','CONFIRMED','RESCHEDULED','IN_PROGRESS','COMPLETED','NO_SHOW','CANCELLED')),
    CONSTRAINT ck_doms_appointment_dates CHECK (
        scheduled_to > scheduled_from AND
        (confirmed_at IS NULL OR confirmed_at >= created_at) AND
        (completed_at IS NULL OR completed_at >= scheduled_from) AND
        (cancelled_at IS NULL OR cancelled_at >= created_at)
    ),
    CONSTRAINT ck_doms_appointment_terminal CHECK (
        (status <> 'COMPLETED' OR completed_at IS NOT NULL) AND
        (status <> 'CANCELLED' OR cancelled_at IS NOT NULL)
    )
);

CREATE TABLE IF NOT EXISTS doms.delivery_appointment_events (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    delivery_appointment_id uuid NOT NULL,
    event_sequence bigint NOT NULL,
    event_type varchar(50) NOT NULL,
    from_status varchar(20),
    to_status varchar(20) NOT NULL,
    previous_scheduled_from timestamptz,
    previous_scheduled_to timestamptz,
    new_scheduled_from timestamptz,
    new_scheduled_to timestamptz,
    reason_code varchar(100),
    detail_masked text,
    idempotency_key varchar(200),
    actor_user_id uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (delivery_appointment_id, event_sequence),
    CONSTRAINT fk_doms_appointment_event_header
        FOREIGN KEY (tenant_id, delivery_appointment_id)
        REFERENCES doms.delivery_appointments(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_appointment_event_sequence CHECK (event_sequence > 0),
    CONSTRAINT ck_doms_appointment_event_old_dates CHECK (
        previous_scheduled_to IS NULL OR previous_scheduled_from IS NULL OR previous_scheduled_to > previous_scheduled_from
    ),
    CONSTRAINT ck_doms_appointment_event_new_dates CHECK (
        new_scheduled_to IS NULL OR new_scheduled_from IS NULL OR new_scheduled_to > new_scheduled_from
    ),
    CONSTRAINT ck_doms_appointment_event_metadata CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(metadata)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_appointment_event_idempotency
    ON doms.delivery_appointment_events (tenant_id, delivery_appointment_id, idempotency_key)
    WHERE idempotency_key IS NOT NULL;

CREATE TABLE IF NOT EXISTS doms.delivery_events (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    shipment_id uuid,
    pickup_order_id uuid,
    event_sequence bigint NOT NULL,
    event_type varchar(50) NOT NULL,
    event_code varchar(100),
    delivery_status varchar(30) NOT NULL,
    external_event_reference varchar(300),
    idempotency_key varchar(200),
    location_text_masked text,
    latitude numeric(10,7),
    longitude numeric(10,7),
    detail_masked text,
    payload_summary jsonb NOT NULL DEFAULT '{}'::jsonb,
    occurred_at timestamptz NOT NULL,
    received_at timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    CONSTRAINT fk_doms_delivery_event_shipment
        FOREIGN KEY (tenant_id, shipment_id)
        REFERENCES doms.shipments(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_delivery_event_pickup
        FOREIGN KEY (tenant_id, pickup_order_id)
        REFERENCES doms.pickup_orders(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_delivery_event_target CHECK (num_nonnulls(shipment_id, pickup_order_id) = 1),
    CONSTRAINT ck_doms_delivery_event_sequence CHECK (event_sequence > 0),
    CONSTRAINT ck_doms_delivery_event_status CHECK (delivery_status IN ('PENDING','OUT_FOR_DELIVERY','ATTEMPTED','PARTIALLY_DELIVERED','DELIVERED','PICKED_UP','FAILED','RETURNING','RETURNED','EXCEPTION')),
    CONSTRAINT ck_doms_delivery_event_lat CHECK (latitude IS NULL OR latitude BETWEEN -90 AND 90),
    CONSTRAINT ck_doms_delivery_event_lon CHECK (longitude IS NULL OR longitude BETWEEN -180 AND 180),
    CONSTRAINT ck_doms_delivery_event_payload CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(payload_summary)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_delivery_event_shipment_sequence
    ON doms.delivery_events (tenant_id, shipment_id, event_sequence)
    WHERE shipment_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_delivery_event_pickup_sequence
    ON doms.delivery_events (tenant_id, pickup_order_id, event_sequence)
    WHERE pickup_order_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_delivery_event_external
    ON doms.delivery_events (tenant_id, external_event_reference)
    WHERE external_event_reference IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_delivery_event_idempotency
    ON doms.delivery_events (tenant_id, COALESCE(shipment_id, pickup_order_id), idempotency_key)
    WHERE idempotency_key IS NOT NULL;

CREATE TABLE IF NOT EXISTS doms.delivery_exceptions (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    delivery_event_id uuid,
    shipment_id uuid,
    pickup_order_id uuid,
    exception_type varchar(50) NOT NULL,
    severity varchar(20) NOT NULL DEFAULT 'MEDIUM',
    description_masked text,
    status varchar(20) NOT NULL DEFAULT 'OPEN',
    retry_at timestamptz,
    assigned_to uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    resolved_by uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    resolved_at timestamptz,
    resolution_code varchar(100),
    resolution_note text,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    CONSTRAINT fk_doms_delivery_exception_event
        FOREIGN KEY (tenant_id, delivery_event_id)
        REFERENCES doms.delivery_events(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_delivery_exception_shipment
        FOREIGN KEY (tenant_id, shipment_id)
        REFERENCES doms.shipments(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_delivery_exception_pickup
        FOREIGN KEY (tenant_id, pickup_order_id)
        REFERENCES doms.pickup_orders(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_delivery_exception_target CHECK (
        delivery_event_id IS NOT NULL OR num_nonnulls(shipment_id, pickup_order_id) = 1
    ),
    CONSTRAINT ck_doms_delivery_exception_severity CHECK (severity IN ('LOW','MEDIUM','HIGH','CRITICAL')),
    CONSTRAINT ck_doms_delivery_exception_status CHECK (status IN ('OPEN','INVESTIGATING','RETRY_SCHEDULED','RESOLVED','WAIVED','CLOSED')),
    CONSTRAINT ck_doms_delivery_exception_resolution CHECK (
        status NOT IN ('RESOLVED','WAIVED','CLOSED') OR resolved_at IS NOT NULL
    ),
    CONSTRAINT ck_doms_delivery_exception_metadata CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(metadata)
    )
);

CREATE INDEX IF NOT EXISTS ix_doms_delivery_exception_queue
    ON doms.delivery_exceptions (tenant_id, status, severity, retry_at, created_at);

CREATE TABLE IF NOT EXISTS doms.proof_of_delivery_records (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    proof_no varchar(120) NOT NULL,
    delivery_event_id uuid NOT NULL,
    shipment_id uuid,
    pickup_order_id uuid,
    status varchar(20) NOT NULL DEFAULT 'CAPTURED',
    delivered_at timestamptz NOT NULL,
    receiver_name_encrypted text,
    receiver_name_masked varchar(200),
    receiver_relationship varchar(100),
    verification_method varchar(30),
    condition_code varchar(80),
    note_encrypted text,
    note_masked text,
    latitude numeric(10,7),
    longitude numeric(10,7),
    captured_by uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    verified_by uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    verified_at timestamptz,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, proof_no),
    UNIQUE (tenant_id, delivery_event_id),
    CONSTRAINT fk_doms_pod_event
        FOREIGN KEY (tenant_id, delivery_event_id)
        REFERENCES doms.delivery_events(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_pod_shipment
        FOREIGN KEY (tenant_id, shipment_id)
        REFERENCES doms.shipments(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_pod_pickup
        FOREIGN KEY (tenant_id, pickup_order_id)
        REFERENCES doms.pickup_orders(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_pod_target CHECK (num_nonnulls(shipment_id, pickup_order_id) = 1),
    CONSTRAINT ck_doms_pod_status CHECK (status IN ('CAPTURED','VERIFIED','DISPUTED','VOID')),
    CONSTRAINT ck_doms_pod_method CHECK (
        verification_method IS NULL OR verification_method IN ('SIGNATURE','PHOTO','CODE','ID_CHECK','GEOLOCATION','CONTACTLESS','MANUAL')
    ),
    CONSTRAINT ck_doms_pod_lat CHECK (latitude IS NULL OR latitude BETWEEN -90 AND 90),
    CONSTRAINT ck_doms_pod_lon CHECK (longitude IS NULL OR longitude BETWEEN -180 AND 180),
    CONSTRAINT ck_doms_pod_verified CHECK (
        status <> 'VERIFIED' OR (verified_by IS NOT NULL AND verified_at IS NOT NULL)
    )
);

CREATE TABLE IF NOT EXISTS doms.proof_of_delivery_objects (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    proof_of_delivery_id uuid NOT NULL,
    object_sequence integer NOT NULL,
    object_type varchar(30) NOT NULL,
    file_id uuid NOT NULL,
    object_sha256 char(64) NOT NULL,
    media_type varchar(200),
    byte_size bigint,
    captured_at timestamptz,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (proof_of_delivery_id, object_sequence),
    UNIQUE (tenant_id, proof_of_delivery_id, object_sha256),
    CONSTRAINT fk_doms_pod_object_header
        FOREIGN KEY (tenant_id, proof_of_delivery_id)
        REFERENCES doms.proof_of_delivery_records(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_pod_object_file
        FOREIGN KEY (tenant_id, file_id)
        REFERENCES doms.files(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_pod_object_sequence CHECK (object_sequence > 0),
    CONSTRAINT ck_doms_pod_object_type CHECK (object_type IN ('SIGNATURE','PHOTO','DOCUMENT','GEOLOCATION','RECIPIENT_ACKNOWLEDGEMENT','OTHER')),
    CONSTRAINT ck_doms_pod_object_hash CHECK (object_sha256 ~ '^[0-9A-Fa-f]{64}$'),
    CONSTRAINT ck_doms_pod_object_size CHECK (byte_size IS NULL OR byte_size >= 0),
    CONSTRAINT ck_doms_pod_object_metadata CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(metadata)
    )
);

-- -----------------------------------------------------------------------------
-- Digital and service fulfillment.  License values, activation codes, service
-- credentials, and download secrets remain in an approved external vault.
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS doms.digital_fulfillments (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    digital_fulfillment_no varchar(120) NOT NULL,
    fulfillment_order_id uuid NOT NULL,
    fulfillment_order_line_id uuid NOT NULL,
    item_id uuid NOT NULL,
    quantity numeric(24,8) NOT NULL,
    uom_code varchar(20) NOT NULL REFERENCES doms.units_of_measure(uom_code),
    entitlement_reference varchar(300) NOT NULL,
    secure_delivery_secret_ref varchar(500),
    external_fulfillment_reference varchar(300),
    idempotency_key varchar(200) NOT NULL,
    status varchar(30) NOT NULL DEFAULT 'PENDING',
    provisioned_at timestamptz,
    delivered_at timestamptz,
    activated_at timestamptz,
    revoked_at timestamptz,
    expires_at timestamptz,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, digital_fulfillment_no),
    UNIQUE (tenant_id, fulfillment_order_line_id, idempotency_key),
    UNIQUE (tenant_id, entitlement_reference),
    CONSTRAINT fk_doms_digital_fulfillment_header
        FOREIGN KEY (tenant_id, fulfillment_order_id)
        REFERENCES doms.fulfillment_orders(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_digital_fulfillment_line
        FOREIGN KEY (tenant_id, fulfillment_order_line_id)
        REFERENCES doms.fulfillment_order_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_digital_fulfillment_item
        FOREIGN KEY (tenant_id, item_id)
        REFERENCES doms.items(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_digital_fulfillment_quantity CHECK (quantity > 0),
    CONSTRAINT ck_doms_digital_fulfillment_status CHECK (status IN ('PENDING','PROVISIONING','PROVISIONED','DELIVERED','ACTIVATED','FAILED','REVOKED','EXPIRED','CANCELLED')),
    CONSTRAINT ck_doms_digital_fulfillment_dates CHECK (
        (provisioned_at IS NULL OR provisioned_at >= created_at) AND
        (delivered_at IS NULL OR delivered_at >= COALESCE(provisioned_at, created_at)) AND
        (activated_at IS NULL OR activated_at >= COALESCE(delivered_at, provisioned_at, created_at)) AND
        (revoked_at IS NULL OR revoked_at >= created_at) AND
        (expires_at IS NULL OR expires_at > created_at)
    ),
    CONSTRAINT ck_doms_digital_fulfillment_terminal CHECK (
        (status NOT IN ('PROVISIONED','DELIVERED','ACTIVATED') OR provisioned_at IS NOT NULL) AND
        (status <> 'REVOKED' OR revoked_at IS NOT NULL)
    ),
    CONSTRAINT ck_doms_digital_fulfillment_metadata CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(metadata)
    )
);

COMMENT ON COLUMN doms.digital_fulfillments.secure_delivery_secret_ref IS
    'Opaque external secret-manager reference only. Raw license keys, activation codes, download credentials, and bearer links are prohibited.';

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_digital_fulfillment_external
    ON doms.digital_fulfillments (tenant_id, external_fulfillment_reference)
    WHERE external_fulfillment_reference IS NOT NULL;

CREATE TABLE IF NOT EXISTS doms.digital_fulfillment_events (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    digital_fulfillment_id uuid NOT NULL,
    event_sequence bigint NOT NULL,
    event_type varchar(50) NOT NULL,
    from_status varchar(30),
    to_status varchar(30) NOT NULL,
    external_event_reference varchar(300),
    idempotency_key varchar(200),
    failure_code varchar(100),
    failure_detail_masked text,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (digital_fulfillment_id, event_sequence),
    CONSTRAINT fk_doms_digital_event_header
        FOREIGN KEY (tenant_id, digital_fulfillment_id)
        REFERENCES doms.digital_fulfillments(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_digital_event_sequence CHECK (event_sequence > 0),
    CONSTRAINT ck_doms_digital_event_metadata CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(metadata)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_digital_event_external
    ON doms.digital_fulfillment_events (tenant_id, external_event_reference)
    WHERE external_event_reference IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_digital_event_idempotency
    ON doms.digital_fulfillment_events (tenant_id, digital_fulfillment_id, idempotency_key)
    WHERE idempotency_key IS NOT NULL;

CREATE TABLE IF NOT EXISTS doms.service_fulfillments (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    service_fulfillment_no varchar(120) NOT NULL,
    fulfillment_order_id uuid NOT NULL,
    fulfillment_order_line_id uuid NOT NULL,
    item_id uuid NOT NULL,
    fulfillment_node_id uuid NOT NULL,
    delivery_appointment_id uuid,
    service_type varchar(40) NOT NULL,
    quantity numeric(24,8) NOT NULL,
    uom_code varchar(20) NOT NULL REFERENCES doms.units_of_measure(uom_code),
    status varchar(30) NOT NULL DEFAULT 'PLANNED',
    idempotency_key varchar(200) NOT NULL,
    external_service_reference varchar(300),
    scheduled_from timestamptz,
    scheduled_to timestamptz,
    started_at timestamptz,
    completed_at timestamptz,
    cancelled_at timestamptz,
    completion_summary jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    assigned_user_id uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, service_fulfillment_no),
    UNIQUE (tenant_id, fulfillment_order_line_id, idempotency_key),
    CONSTRAINT fk_doms_service_fulfillment_header
        FOREIGN KEY (tenant_id, fulfillment_order_id)
        REFERENCES doms.fulfillment_orders(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_service_fulfillment_line
        FOREIGN KEY (tenant_id, fulfillment_order_line_id)
        REFERENCES doms.fulfillment_order_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_service_fulfillment_item
        FOREIGN KEY (tenant_id, item_id)
        REFERENCES doms.items(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_service_fulfillment_node
        FOREIGN KEY (tenant_id, fulfillment_node_id)
        REFERENCES doms.fulfillment_nodes(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_service_fulfillment_appointment
        FOREIGN KEY (tenant_id, delivery_appointment_id)
        REFERENCES doms.delivery_appointments(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_service_fulfillment_type CHECK (service_type IN ('INSTALLATION','ASSEMBLY','CONFIGURATION','INSPECTION','TRAINING','MAINTENANCE','CONSULTING','OTHER')),
    CONSTRAINT ck_doms_service_fulfillment_quantity CHECK (quantity > 0),
    CONSTRAINT ck_doms_service_fulfillment_status CHECK (status IN ('PLANNED','SCHEDULED','ASSIGNED','IN_PROGRESS','COMPLETED','FAILED','NO_SHOW','CANCELLED','CLOSED')),
    CONSTRAINT ck_doms_service_fulfillment_dates CHECK (
        (scheduled_to IS NULL OR scheduled_from IS NULL OR scheduled_to > scheduled_from) AND
        (started_at IS NULL OR started_at >= COALESCE(scheduled_from, created_at)) AND
        (completed_at IS NULL OR completed_at >= COALESCE(started_at, scheduled_from, created_at)) AND
        (cancelled_at IS NULL OR cancelled_at >= created_at)
    ),
    CONSTRAINT ck_doms_service_fulfillment_terminal CHECK (
        (status NOT IN ('COMPLETED','CLOSED') OR completed_at IS NOT NULL) AND
        (status <> 'CANCELLED' OR cancelled_at IS NOT NULL)
    ),
    CONSTRAINT ck_doms_service_fulfillment_summary CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(completion_summary)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_service_fulfillment_external
    ON doms.service_fulfillments (tenant_id, external_service_reference)
    WHERE external_service_reference IS NOT NULL;

CREATE TABLE IF NOT EXISTS doms.service_fulfillment_events (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    service_fulfillment_id uuid NOT NULL,
    event_sequence bigint NOT NULL,
    event_type varchar(50) NOT NULL,
    from_status varchar(30),
    to_status varchar(30) NOT NULL,
    quantity numeric(24,8) NOT NULL DEFAULT 0,
    external_event_reference varchar(300),
    idempotency_key varchar(200),
    detail_masked text,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    actor_user_id uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (service_fulfillment_id, event_sequence),
    CONSTRAINT fk_doms_service_event_header
        FOREIGN KEY (tenant_id, service_fulfillment_id)
        REFERENCES doms.service_fulfillments(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_service_event_sequence CHECK (event_sequence > 0),
    CONSTRAINT ck_doms_service_event_quantity CHECK (quantity >= 0),
    CONSTRAINT ck_doms_service_event_metadata CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(metadata)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_service_event_external
    ON doms.service_fulfillment_events (tenant_id, external_event_reference)
    WHERE external_event_reference IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_service_event_idempotency
    ON doms.service_fulfillment_events (tenant_id, service_fulfillment_id, idempotency_key)
    WHERE idempotency_key IS NOT NULL;

-- -----------------------------------------------------------------------------
-- Fulfillment confirmations are draftable, but become immutable once posted.
-- Confirmation events are an independent append-only posting audit stream.
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS doms.fulfillment_confirmations (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    confirmation_no varchar(120) NOT NULL,
    fulfillment_order_id uuid NOT NULL,
    shipment_id uuid,
    pickup_order_id uuid,
    digital_fulfillment_id uuid,
    service_fulfillment_id uuid,
    confirmation_type varchar(30) NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'DRAFT',
    idempotency_key varchar(200) NOT NULL,
    external_confirmation_reference varchar(300),
    confirmed_at timestamptz,
    posted_at timestamptz,
    reversed_at timestamptz,
    reversal_of_id uuid,
    note text,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    confirmed_by uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    posted_by uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    UNIQUE (tenant_id, id),
    UNIQUE (tenant_id, confirmation_no),
    UNIQUE (tenant_id, idempotency_key),
    CONSTRAINT fk_doms_confirmation_fulfillment
        FOREIGN KEY (tenant_id, fulfillment_order_id)
        REFERENCES doms.fulfillment_orders(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_confirmation_shipment
        FOREIGN KEY (tenant_id, shipment_id)
        REFERENCES doms.shipments(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_confirmation_pickup
        FOREIGN KEY (tenant_id, pickup_order_id)
        REFERENCES doms.pickup_orders(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_confirmation_digital
        FOREIGN KEY (tenant_id, digital_fulfillment_id)
        REFERENCES doms.digital_fulfillments(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_confirmation_service
        FOREIGN KEY (tenant_id, service_fulfillment_id)
        REFERENCES doms.service_fulfillments(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_confirmation_reversal
        FOREIGN KEY (tenant_id, reversal_of_id)
        REFERENCES doms.fulfillment_confirmations(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_confirmation_target CHECK (
        num_nonnulls(shipment_id, pickup_order_id, digital_fulfillment_id, service_fulfillment_id) = 1
    ),
    CONSTRAINT ck_doms_confirmation_type CHECK (confirmation_type IN ('SHIPMENT','PICKUP','DIGITAL','SERVICE','REVERSAL')),
    CONSTRAINT ck_doms_confirmation_status CHECK (status IN ('DRAFT','CONFIRMED','POSTED','FAILED','REVERSED','CANCELLED')),
    CONSTRAINT ck_doms_confirmation_dates CHECK (
        (confirmed_at IS NULL OR confirmed_at >= created_at) AND
        (posted_at IS NULL OR confirmed_at IS NULL OR posted_at >= confirmed_at) AND
        (reversed_at IS NULL OR posted_at IS NULL OR reversed_at >= posted_at)
    ),
    CONSTRAINT ck_doms_confirmation_posted CHECK (
        status NOT IN ('POSTED','REVERSED') OR (confirmed_at IS NOT NULL AND posted_at IS NOT NULL)
    ),
    CONSTRAINT ck_doms_confirmation_reversal CHECK (
        (confirmation_type = 'REVERSAL' AND reversal_of_id IS NOT NULL) OR
        (confirmation_type <> 'REVERSAL' AND reversal_of_id IS NULL)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_confirmation_external
    ON doms.fulfillment_confirmations (tenant_id, external_confirmation_reference)
    WHERE external_confirmation_reference IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_confirmation_single_reversal
    ON doms.fulfillment_confirmations (reversal_of_id)
    WHERE reversal_of_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS doms.fulfillment_confirmation_lines (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    fulfillment_confirmation_id uuid NOT NULL,
    line_no integer NOT NULL,
    fulfillment_order_line_id uuid NOT NULL,
    shipment_line_id uuid,
    confirmed_quantity numeric(24,8) NOT NULL,
    uom_code varchar(20) NOT NULL REFERENCES doms.units_of_measure(uom_code),
    confirmation_result varchar(20) NOT NULL DEFAULT 'SUCCESS',
    reason_code varchar(100),
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (fulfillment_confirmation_id, line_no),
    CONSTRAINT fk_doms_confirmation_line_header
        FOREIGN KEY (tenant_id, fulfillment_confirmation_id)
        REFERENCES doms.fulfillment_confirmations(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_confirmation_line_fulfillment
        FOREIGN KEY (tenant_id, fulfillment_order_line_id)
        REFERENCES doms.fulfillment_order_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_doms_confirmation_line_shipment
        FOREIGN KEY (tenant_id, shipment_line_id)
        REFERENCES doms.shipment_lines(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_confirmation_line_no CHECK (line_no > 0),
    CONSTRAINT ck_doms_confirmation_line_quantity CHECK (confirmed_quantity > 0),
    CONSTRAINT ck_doms_confirmation_line_result CHECK (confirmation_result IN ('SUCCESS','PARTIAL','FAILED','REJECTED','REVERSED')),
    CONSTRAINT ck_doms_confirmation_line_metadata CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(metadata)
    )
);

CREATE TABLE IF NOT EXISTS doms.fulfillment_confirmation_events (
    id uuid PRIMARY KEY DEFAULT doms.generate_uuid(),
    tenant_id uuid NOT NULL REFERENCES doms.tenants(id),
    fulfillment_confirmation_id uuid NOT NULL,
    event_sequence bigint NOT NULL,
    event_type varchar(40) NOT NULL,
    from_status varchar(20),
    to_status varchar(20) NOT NULL,
    idempotency_key varchar(200),
    external_event_reference varchar(300),
    failure_code varchar(100),
    detail_masked text,
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    actor_user_id uuid REFERENCES doms.users(id) ON DELETE RESTRICT,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id),
    UNIQUE (fulfillment_confirmation_id, event_sequence),
    CONSTRAINT fk_doms_confirmation_event_header
        FOREIGN KEY (tenant_id, fulfillment_confirmation_id)
        REFERENCES doms.fulfillment_confirmations(tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT ck_doms_confirmation_event_sequence CHECK (event_sequence > 0),
    CONSTRAINT ck_doms_confirmation_event_metadata CHECK (
        NOT doms.jsonb_contains_forbidden_secret_key(metadata)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_confirmation_event_idempotency
    ON doms.fulfillment_confirmation_events (tenant_id, fulfillment_confirmation_id, idempotency_key)
    WHERE idempotency_key IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_doms_confirmation_event_external
    ON doms.fulfillment_confirmation_events (tenant_id, external_event_reference)
    WHERE external_event_reference IS NOT NULL;

-- -----------------------------------------------------------------------------
-- Lifecycle, quantity-chain, append-only, and posted-document integrity.
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION doms.prevent_fulfillment_append_only_change()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    RAISE EXCEPTION '% is append-only; % is not permitted', TG_TABLE_NAME, TG_OP
        USING ERRCODE = '55000';
END;
$function$;

CREATE OR REPLACE FUNCTION doms.prevent_fulfillment_delete()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    RAISE EXCEPTION '% uses state transitions; DELETE is not permitted', TG_TABLE_NAME
        USING ERRCODE = '55000';
END;
$function$;

CREATE OR REPLACE FUNCTION doms.fulfillment_status_transition_allowed(
    p_entity varchar,
    p_old_status varchar,
    p_new_status varchar
)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
STRICT
AS $function$
BEGIN
    IF p_old_status = p_new_status THEN
        RETURN true;
    END IF;
    IF p_entity = 'FULFILLMENT' THEN
        RETURN CASE p_old_status
            WHEN 'DRAFT' THEN p_new_status IN ('PLANNED','RELEASED','CANCELLED')
            WHEN 'PLANNED' THEN p_new_status IN ('RELEASED','ON_HOLD','CANCELLED')
            WHEN 'RELEASED' THEN p_new_status IN ('IN_PROGRESS','ON_HOLD','EXCEPTION','CANCELLED')
            WHEN 'IN_PROGRESS' THEN p_new_status IN ('PARTIALLY_FULFILLED','FULFILLED','ON_HOLD','EXCEPTION','CANCELLATION_PENDING')
            WHEN 'PARTIALLY_FULFILLED' THEN p_new_status IN ('IN_PROGRESS','FULFILLED','ON_HOLD','EXCEPTION','CANCELLATION_PENDING')
            WHEN 'ON_HOLD' THEN p_new_status IN ('RELEASED','IN_PROGRESS','EXCEPTION','CANCELLED')
            WHEN 'EXCEPTION' THEN p_new_status IN ('IN_PROGRESS','ON_HOLD','CANCELLATION_PENDING','CANCELLED')
            WHEN 'CANCELLATION_PENDING' THEN p_new_status IN ('IN_PROGRESS','CANCELLED')
            WHEN 'FULFILLED' THEN p_new_status = 'CLOSED'
            WHEN 'CANCELLED' THEN p_new_status = 'CLOSED'
            ELSE false
        END;
    ELSIF p_entity = 'FULFILLMENT_LINE' THEN
        RETURN CASE p_old_status
            WHEN 'PLANNED' THEN p_new_status IN ('RELEASED','ON_HOLD','CANCELLED')
            WHEN 'RELEASED' THEN p_new_status IN ('PICKING','PACKING','PARTIALLY_FULFILLED','FULFILLED','ON_HOLD','EXCEPTION','CANCELLED')
            WHEN 'PICKING' THEN p_new_status IN ('PARTIALLY_PICKED','PICKED','ON_HOLD','EXCEPTION','CANCELLED')
            WHEN 'PARTIALLY_PICKED' THEN p_new_status IN ('PICKING','PICKED','ON_HOLD','EXCEPTION','CANCELLED')
            WHEN 'PICKED' THEN p_new_status IN ('PACKING','PACKED','EXCEPTION','CANCELLED')
            WHEN 'PACKING' THEN p_new_status IN ('PARTIALLY_PACKED','PACKED','EXCEPTION','CANCELLED')
            WHEN 'PARTIALLY_PACKED' THEN p_new_status IN ('PACKING','PACKED','PARTIALLY_SHIPPED','EXCEPTION')
            WHEN 'PACKED' THEN p_new_status IN ('PARTIALLY_SHIPPED','SHIPPED','FULFILLED','EXCEPTION')
            WHEN 'PARTIALLY_SHIPPED' THEN p_new_status IN ('SHIPPED','PARTIALLY_FULFILLED','FULFILLED','EXCEPTION')
            WHEN 'SHIPPED' THEN p_new_status IN ('PARTIALLY_FULFILLED','FULFILLED','EXCEPTION')
            WHEN 'PARTIALLY_FULFILLED' THEN p_new_status IN ('FULFILLED','EXCEPTION')
            WHEN 'ON_HOLD' THEN p_new_status IN ('RELEASED','PICKING','PACKING','EXCEPTION','CANCELLED')
            WHEN 'EXCEPTION' THEN p_new_status IN ('RELEASED','PICKING','PACKING','CANCELLED')
            WHEN 'FULFILLED' THEN p_new_status = 'CLOSED'
            WHEN 'CANCELLED' THEN p_new_status = 'CLOSED'
            ELSE false
        END;
    ELSIF p_entity = 'SHIPMENT_PLAN' THEN
        RETURN CASE p_old_status
            WHEN 'DRAFT' THEN p_new_status IN ('READY','CANCELLED','SUPERSEDED')
            WHEN 'READY' THEN p_new_status IN ('RELEASED','CANCELLED','SUPERSEDED')
            WHEN 'RELEASED' THEN p_new_status IN ('PARTIALLY_SHIPPED','SHIPPED','CANCELLED','SUPERSEDED')
            WHEN 'PARTIALLY_SHIPPED' THEN p_new_status IN ('SHIPPED','CANCELLED')
            ELSE false
        END;
    ELSIF p_entity = 'SHIPMENT' THEN
        RETURN CASE p_old_status
            WHEN 'PLANNED' THEN p_new_status IN ('READY','BOOKING','CANCELLED')
            WHEN 'READY' THEN p_new_status IN ('BOOKING','BOOKED','PACKING','CANCELLED')
            WHEN 'BOOKING' THEN p_new_status IN ('BOOKED','EXCEPTION','CANCELLED')
            WHEN 'BOOKED' THEN p_new_status IN ('PACKING','PACKED','TENDERING','CANCELLED')
            WHEN 'PACKING' THEN p_new_status IN ('PACKED','EXCEPTION','CANCELLED')
            WHEN 'PACKED' THEN p_new_status IN ('TENDERING','TENDERED','SHIPPED','EXCEPTION','CANCELLED')
            WHEN 'TENDERING' THEN p_new_status IN ('TENDERED','EXCEPTION','CANCELLED')
            WHEN 'TENDERED' THEN p_new_status IN ('SHIPPED','EXCEPTION','CANCELLED')
            WHEN 'SHIPPED' THEN p_new_status IN ('IN_TRANSIT','PARTIALLY_DELIVERED','DELIVERED','EXCEPTION')
            WHEN 'IN_TRANSIT' THEN p_new_status IN ('PARTIALLY_DELIVERED','DELIVERED','EXCEPTION')
            WHEN 'PARTIALLY_DELIVERED' THEN p_new_status IN ('DELIVERED','EXCEPTION')
            WHEN 'EXCEPTION' THEN p_new_status IN ('READY','BOOKING','PACKING','TENDERING','SHIPPED','IN_TRANSIT','CANCELLED')
            WHEN 'DELIVERED' THEN p_new_status = 'CLOSED'
            ELSE false
        END;
    ELSIF p_entity = 'PACKAGE' THEN
        RETURN CASE p_old_status
            WHEN 'OPEN' THEN p_new_status IN ('PACKING','PACKED','VOID')
            WHEN 'PACKING' THEN p_new_status IN ('PACKED','VOID')
            WHEN 'PACKED' THEN p_new_status IN ('SEALED','STAGED','TENDERED','VOID')
            WHEN 'SEALED' THEN p_new_status IN ('STAGED','TENDERED','VOID')
            WHEN 'STAGED' THEN p_new_status IN ('TENDERED','SHIPPED','EXCEPTION','VOID')
            WHEN 'TENDERED' THEN p_new_status IN ('SHIPPED','EXCEPTION')
            WHEN 'SHIPPED' THEN p_new_status IN ('IN_TRANSIT','DELIVERED','EXCEPTION')
            WHEN 'IN_TRANSIT' THEN p_new_status IN ('DELIVERED','EXCEPTION')
            WHEN 'EXCEPTION' THEN p_new_status IN ('STAGED','TENDERED','SHIPPED','IN_TRANSIT','VOID')
            ELSE false
        END;
    ELSIF p_entity = 'PICKUP' THEN
        RETURN CASE p_old_status
            WHEN 'PLANNED' THEN p_new_status IN ('CONFIRMED','PREPARING','CANCELLED')
            WHEN 'CONFIRMED' THEN p_new_status IN ('PREPARING','READY','CANCELLED')
            WHEN 'PREPARING' THEN p_new_status IN ('READY','CANCELLED')
            WHEN 'READY' THEN p_new_status IN ('PARTIALLY_PICKED_UP','PICKED_UP','NO_SHOW','EXPIRED','CANCELLED')
            WHEN 'PARTIALLY_PICKED_UP' THEN p_new_status IN ('PICKED_UP','EXPIRED','CANCELLED')
            WHEN 'PICKED_UP' THEN p_new_status = 'CLOSED'
            WHEN 'NO_SHOW' THEN p_new_status IN ('READY','EXPIRED','CANCELLED')
            ELSE false
        END;
    ELSIF p_entity = 'APPOINTMENT' THEN
        RETURN CASE p_old_status
            WHEN 'REQUESTED' THEN p_new_status IN ('CONFIRMED','RESCHEDULED','CANCELLED')
            WHEN 'CONFIRMED' THEN p_new_status IN ('RESCHEDULED','IN_PROGRESS','NO_SHOW','CANCELLED')
            WHEN 'RESCHEDULED' THEN p_new_status IN ('CONFIRMED','IN_PROGRESS','NO_SHOW','CANCELLED')
            WHEN 'IN_PROGRESS' THEN p_new_status IN ('COMPLETED','NO_SHOW','CANCELLED')
            WHEN 'NO_SHOW' THEN p_new_status IN ('RESCHEDULED','CANCELLED')
            ELSE false
        END;
    ELSIF p_entity = 'DIGITAL' THEN
        RETURN CASE p_old_status
            WHEN 'PENDING' THEN p_new_status IN ('PROVISIONING','CANCELLED')
            WHEN 'PROVISIONING' THEN p_new_status IN ('PROVISIONED','FAILED','CANCELLED')
            WHEN 'PROVISIONED' THEN p_new_status IN ('DELIVERED','ACTIVATED','REVOKED','EXPIRED')
            WHEN 'DELIVERED' THEN p_new_status IN ('ACTIVATED','REVOKED','EXPIRED')
            WHEN 'ACTIVATED' THEN p_new_status IN ('REVOKED','EXPIRED')
            WHEN 'FAILED' THEN p_new_status IN ('PROVISIONING','CANCELLED')
            ELSE false
        END;
    ELSIF p_entity = 'SERVICE' THEN
        RETURN CASE p_old_status
            WHEN 'PLANNED' THEN p_new_status IN ('SCHEDULED','ASSIGNED','CANCELLED')
            WHEN 'SCHEDULED' THEN p_new_status IN ('ASSIGNED','IN_PROGRESS','NO_SHOW','CANCELLED')
            WHEN 'ASSIGNED' THEN p_new_status IN ('IN_PROGRESS','NO_SHOW','CANCELLED')
            WHEN 'IN_PROGRESS' THEN p_new_status IN ('COMPLETED','FAILED','CANCELLED')
            WHEN 'FAILED' THEN p_new_status IN ('SCHEDULED','ASSIGNED','CANCELLED')
            WHEN 'NO_SHOW' THEN p_new_status IN ('SCHEDULED','CANCELLED')
            WHEN 'COMPLETED' THEN p_new_status = 'CLOSED'
            ELSE false
        END;
    ELSIF p_entity = 'CONFIRMATION' THEN
        RETURN CASE p_old_status
            WHEN 'DRAFT' THEN p_new_status IN ('CONFIRMED','FAILED','CANCELLED')
            WHEN 'CONFIRMED' THEN p_new_status IN ('POSTED','FAILED','CANCELLED')
            ELSE false
        END;
    END IF;
    RETURN true;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.enforce_fulfillment_status_transition()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    IF OLD.status IS DISTINCT FROM NEW.status
       AND NOT doms.fulfillment_status_transition_allowed(TG_ARGV[0], OLD.status, NEW.status) THEN
        RAISE EXCEPTION 'Invalid % status transition: % -> %', TG_ARGV[0], OLD.status, NEW.status
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.validate_delivery_method_scope()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    method_tenant_id uuid;
BEGIN
    IF NEW.delivery_method_id IS NULL THEN
        RETURN NEW;
    END IF;
    SELECT tenant_id INTO method_tenant_id
      FROM doms.delivery_methods
     WHERE id = NEW.delivery_method_id;
    IF NOT FOUND OR (method_tenant_id IS NOT NULL AND method_tenant_id <> NEW.tenant_id) THEN
        RAISE EXCEPTION 'Delivery method must be global or belong to the same tenant'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.validate_fulfillment_order_scope()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    address_order_id uuid;
BEGIN
    IF TG_OP = 'UPDATE' AND (
        OLD.tenant_id IS DISTINCT FROM NEW.tenant_id OR
        OLD.sales_order_id IS DISTINCT FROM NEW.sales_order_id OR
        OLD.fulfillment_node_id IS DISTINCT FROM NEW.fulfillment_node_id OR
        OLD.idempotency_key IS DISTINCT FROM NEW.idempotency_key
    ) THEN
        RAISE EXCEPTION 'Fulfillment order tenant, order, node, and idempotency key are immutable'
            USING ERRCODE = '23514';
    END IF;
    IF NEW.ship_to_address_snapshot_id IS NOT NULL THEN
        SELECT sales_order_id INTO address_order_id
          FROM doms.order_address_snapshots
         WHERE tenant_id = NEW.tenant_id AND id = NEW.ship_to_address_snapshot_id;
        IF NOT FOUND OR address_order_id <> NEW.sales_order_id THEN
            RAISE EXCEPTION 'Fulfillment address snapshot must belong to its sales order'
                USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.validate_fulfillment_order_line()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    header_row record;
    allocation_row doms.fulfillment_allocations%ROWTYPE;
    order_line_row record;
    existing_allocated numeric(24,8);
    existing_consumed numeric(24,8);
    expected_current_consumed numeric(24,8);
BEGIN
    IF TG_OP = 'UPDATE' AND (
        OLD.tenant_id IS DISTINCT FROM NEW.tenant_id OR
        OLD.fulfillment_order_id IS DISTINCT FROM NEW.fulfillment_order_id OR
        OLD.sales_order_line_id IS DISTINCT FROM NEW.sales_order_line_id OR
        OLD.fulfillment_allocation_id IS DISTINCT FROM NEW.fulfillment_allocation_id OR
        OLD.item_id IS DISTINCT FROM NEW.item_id OR
        OLD.uom_code IS DISTINCT FROM NEW.uom_code OR
        OLD.idempotency_key IS DISTINCT FROM NEW.idempotency_key
    ) THEN
        RAISE EXCEPTION 'Fulfillment-line identity, allocation, item/UOM, and idempotency key are immutable'
            USING ERRCODE = '23514';
    END IF;

    SELECT sales_order_id, fulfillment_node_id, fulfillment_type
      INTO header_row
      FROM doms.fulfillment_orders
     WHERE tenant_id = NEW.tenant_id AND id = NEW.fulfillment_order_id;

    SELECT * INTO allocation_row
      FROM doms.fulfillment_allocations
     WHERE tenant_id = NEW.tenant_id AND id = NEW.fulfillment_allocation_id
     FOR UPDATE;

    SELECT sales_order_id, item_id, uom_code
      INTO order_line_row
      FROM doms.sales_order_lines
     WHERE tenant_id = NEW.tenant_id AND id = NEW.sales_order_line_id;

    IF header_row.sales_order_id IS NULL OR allocation_row.id IS NULL OR order_line_row.sales_order_id IS NULL
       OR allocation_row.sales_order_line_id <> NEW.sales_order_line_id
       OR allocation_row.item_id <> NEW.item_id OR allocation_row.uom_code <> NEW.uom_code
       OR allocation_row.fulfillment_node_id <> header_row.fulfillment_node_id
       OR order_line_row.sales_order_id <> header_row.sales_order_id
       OR order_line_row.item_id <> NEW.item_id OR order_line_row.uom_code <> NEW.uom_code THEN
        RAISE EXCEPTION 'Fulfillment line differs from its order, allocation, node, item, or UOM'
            USING ERRCODE = '23514';
    END IF;
    IF allocation_row.allocation_status NOT IN ('ACTIVE','PARTIALLY_CONSUMED','PARTIALLY_RELEASED')
       AND (
           TG_OP <> 'UPDATE'
           OR OLD.allocated_quantity IS DISTINCT FROM NEW.allocated_quantity
           OR OLD.consumed_quantity IS DISTINCT FROM NEW.consumed_quantity
           OR OLD.cancelled_quantity IS DISTINCT FROM NEW.cancelled_quantity
       ) THEN
        RAISE EXCEPTION 'Terminal allocation quantities cannot be reassigned by a fulfillment line'
            USING ERRCODE = '23514';
    END IF;
    IF NEW.status = 'CANCELLED' AND NEW.consumed_quantity <> 0 THEN
        RAISE EXCEPTION 'A consumed fulfillment line cannot be cancelled'
            USING ERRCODE = '23514';
    END IF;

    SELECT COALESCE(sum(allocated_quantity) FILTER (WHERE status <> 'CANCELLED'), 0),
           COALESCE(sum(consumed_quantity), 0)
      INTO existing_allocated, existing_consumed
      FROM doms.fulfillment_order_lines
     WHERE fulfillment_allocation_id = NEW.fulfillment_allocation_id
       AND id <> NEW.id;

    expected_current_consumed := existing_consumed +
        (CASE WHEN TG_OP = 'UPDATE' THEN OLD.consumed_quantity ELSE 0 END);
    IF allocation_row.consumed_quantity <> expected_current_consumed THEN
        RAISE EXCEPTION 'Allocation consumed quantity is out of sync with fulfillment lines'
            USING ERRCODE = '23514';
    END IF;
    IF existing_allocated +
       (CASE WHEN NEW.status = 'CANCELLED' THEN 0 ELSE NEW.allocated_quantity END)
       + allocation_row.released_quantity > allocation_row.allocated_quantity THEN
        RAISE EXCEPTION 'Fulfillment-line allocation portions exceed the active allocation quantity'
            USING ERRCODE = '23514';
    END IF;
    IF existing_consumed + NEW.consumed_quantity + allocation_row.released_quantity > allocation_row.allocated_quantity THEN
        RAISE EXCEPTION 'Allocation consumption plus released quantity exceeds allocated quantity'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.sync_fulfillment_allocation_consumption()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    target_allocation_id uuid;
    consumed_total numeric(24,8);
BEGIN
    target_allocation_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.fulfillment_allocation_id ELSE NEW.fulfillment_allocation_id END;
    SELECT COALESCE(sum(consumed_quantity), 0)
      INTO consumed_total
      FROM doms.fulfillment_order_lines
     WHERE fulfillment_allocation_id = target_allocation_id;

    UPDATE doms.fulfillment_allocations
       SET consumed_quantity = consumed_total,
           allocation_status = CASE
               WHEN consumed_total = allocated_quantity THEN 'CONSUMED'
               WHEN consumed_total > 0 THEN 'PARTIALLY_CONSUMED'
               WHEN released_quantity = allocated_quantity THEN 'RELEASED'
               WHEN released_quantity > 0 THEN 'PARTIALLY_RELEASED'
               ELSE 'ACTIVE'
           END,
           last_operation_key = 'doms06:consumed:' || consumed_total::text,
           row_version = row_version + 1,
           updated_at = now()
     WHERE id = target_allocation_id
       AND (
           consumed_quantity IS DISTINCT FROM consumed_total
           OR allocation_status IS DISTINCT FROM CASE
               WHEN consumed_total = allocated_quantity THEN 'CONSUMED'
               WHEN consumed_total > 0 THEN 'PARTIALLY_CONSUMED'
               WHEN released_quantity = allocated_quantity THEN 'RELEASED'
               WHEN released_quantity > 0 THEN 'PARTIALLY_RELEASED'
               ELSE 'ACTIVE'
           END
       );
    RETURN NULL;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.validate_shipment_plan_line()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    plan_fulfillment_order_id uuid;
    fulfillment_line_row doms.fulfillment_order_lines%ROWTYPE;
    planned_total numeric(24,8);
    nonshipment_total numeric(24,8);
BEGIN
    IF TG_OP = 'UPDATE' AND (
        OLD.tenant_id IS DISTINCT FROM NEW.tenant_id OR
        OLD.shipment_plan_id IS DISTINCT FROM NEW.shipment_plan_id OR
        OLD.fulfillment_order_line_id IS DISTINCT FROM NEW.fulfillment_order_line_id OR
        OLD.item_id IS DISTINCT FROM NEW.item_id OR OLD.uom_code IS DISTINCT FROM NEW.uom_code
    ) THEN
        RAISE EXCEPTION 'Shipment-plan line identity, fulfillment line, item, and UOM are immutable'
            USING ERRCODE = '23514';
    END IF;

    SELECT fulfillment_order_id INTO plan_fulfillment_order_id
      FROM doms.shipment_plans
     WHERE tenant_id = NEW.tenant_id AND id = NEW.shipment_plan_id;
    SELECT * INTO fulfillment_line_row
      FROM doms.fulfillment_order_lines
     WHERE tenant_id = NEW.tenant_id AND id = NEW.fulfillment_order_line_id
     FOR UPDATE;

    IF plan_fulfillment_order_id IS NULL OR fulfillment_line_row.id IS NULL
       OR plan_fulfillment_order_id <> fulfillment_line_row.fulfillment_order_id
       OR NEW.item_id <> fulfillment_line_row.item_id OR NEW.uom_code <> fulfillment_line_row.uom_code THEN
        RAISE EXCEPTION 'Shipment-plan line differs from its fulfillment order line'
            USING ERRCODE = '23514';
    END IF;

    SELECT COALESCE(sum(planned_quantity - cancelled_quantity), 0)
      INTO planned_total
      FROM doms.shipment_plan_lines
     WHERE fulfillment_order_line_id = NEW.fulfillment_order_line_id
       AND id <> NEW.id
       AND status <> 'CANCELLED';
    SELECT
        COALESCE((SELECT sum(quantity) FROM doms.digital_fulfillments
                   WHERE fulfillment_order_line_id = NEW.fulfillment_order_line_id
                     AND status NOT IN ('FAILED','REVOKED','EXPIRED','CANCELLED')), 0) +
        COALESCE((SELECT sum(quantity) FROM doms.service_fulfillments
                   WHERE fulfillment_order_line_id = NEW.fulfillment_order_line_id
                     AND status NOT IN ('FAILED','NO_SHOW','CANCELLED')), 0)
      INTO nonshipment_total;
    IF planned_total + nonshipment_total +
       (CASE WHEN NEW.status = 'CANCELLED' THEN 0 ELSE NEW.planned_quantity - NEW.cancelled_quantity END)
       > fulfillment_line_row.allocated_quantity - fulfillment_line_row.cancelled_quantity THEN
        RAISE EXCEPTION 'Active shipment-plan quantities exceed the fulfillment-line quantity'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.validate_shipment_scope()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    plan_row record;
BEGIN
    IF TG_OP = 'UPDATE' AND (
        OLD.tenant_id IS DISTINCT FROM NEW.tenant_id OR
        OLD.shipment_plan_id IS DISTINCT FROM NEW.shipment_plan_id OR
        OLD.fulfillment_order_id IS DISTINCT FROM NEW.fulfillment_order_id OR
        OLD.fulfillment_node_id IS DISTINCT FROM NEW.fulfillment_node_id OR
        OLD.idempotency_key IS DISTINCT FROM NEW.idempotency_key
    ) THEN
        RAISE EXCEPTION 'Shipment plan, fulfillment order, node, tenant, and idempotency key are immutable'
            USING ERRCODE = '23514';
    END IF;
    SELECT fulfillment_order_id, fulfillment_node_id, carrier_service_id, ship_to_address_snapshot_id
      INTO plan_row
      FROM doms.shipment_plans
     WHERE tenant_id = NEW.tenant_id AND id = NEW.shipment_plan_id;
    IF plan_row.fulfillment_order_id IS NULL
       OR plan_row.fulfillment_order_id <> NEW.fulfillment_order_id
       OR plan_row.fulfillment_node_id <> NEW.fulfillment_node_id
       OR plan_row.carrier_service_id IS DISTINCT FROM NEW.carrier_service_id
       OR plan_row.ship_to_address_snapshot_id IS DISTINCT FROM NEW.ship_to_address_snapshot_id THEN
        RAISE EXCEPTION 'Shipment must retain the fulfillment, node, carrier, and address of its plan'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.validate_shipment_line()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    shipment_row record;
    plan_line_row doms.shipment_plan_lines%ROWTYPE;
    fulfillment_line_row doms.fulfillment_order_lines%ROWTYPE;
    shipped_plan_total numeric(24,8);
BEGIN
    IF TG_OP = 'UPDATE' AND (
        OLD.tenant_id IS DISTINCT FROM NEW.tenant_id OR
        OLD.shipment_id IS DISTINCT FROM NEW.shipment_id OR
        OLD.shipment_plan_line_id IS DISTINCT FROM NEW.shipment_plan_line_id OR
        OLD.fulfillment_order_line_id IS DISTINCT FROM NEW.fulfillment_order_line_id OR
        OLD.item_id IS DISTINCT FROM NEW.item_id OR OLD.uom_code IS DISTINCT FROM NEW.uom_code
    ) THEN
        RAISE EXCEPTION 'Shipment-line identity, plan line, fulfillment line, item, and UOM are immutable'
            USING ERRCODE = '23514';
    END IF;

    SELECT shipment_plan_id, fulfillment_order_id INTO shipment_row
      FROM doms.shipments
     WHERE tenant_id = NEW.tenant_id AND id = NEW.shipment_id;
    SELECT * INTO plan_line_row
      FROM doms.shipment_plan_lines
     WHERE tenant_id = NEW.tenant_id AND id = NEW.shipment_plan_line_id
     FOR UPDATE;
    SELECT * INTO fulfillment_line_row
      FROM doms.fulfillment_order_lines
     WHERE tenant_id = NEW.tenant_id AND id = NEW.fulfillment_order_line_id
     FOR UPDATE;

    IF shipment_row.shipment_plan_id IS NULL OR plan_line_row.id IS NULL OR fulfillment_line_row.id IS NULL
       OR plan_line_row.shipment_plan_id <> shipment_row.shipment_plan_id
       OR plan_line_row.fulfillment_order_line_id <> NEW.fulfillment_order_line_id
       OR fulfillment_line_row.fulfillment_order_id <> shipment_row.fulfillment_order_id
       OR plan_line_row.item_id <> NEW.item_id OR fulfillment_line_row.item_id <> NEW.item_id
       OR plan_line_row.uom_code <> NEW.uom_code OR fulfillment_line_row.uom_code <> NEW.uom_code THEN
        RAISE EXCEPTION 'Shipment line differs from its plan or fulfillment line'
            USING ERRCODE = '23514';
    END IF;

    SELECT COALESCE(sum(planned_quantity - cancelled_quantity), 0)
      INTO shipped_plan_total
      FROM doms.shipment_lines
     WHERE shipment_plan_line_id = NEW.shipment_plan_line_id
       AND id <> NEW.id
       AND status <> 'CANCELLED';
    IF shipped_plan_total +
       (CASE WHEN NEW.status = 'CANCELLED' THEN 0 ELSE NEW.planned_quantity - NEW.cancelled_quantity END)
       > plan_line_row.planned_quantity - plan_line_row.cancelled_quantity THEN
        RAISE EXCEPTION 'Shipment lines exceed their shipment-plan line quantity'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.sync_fulfillment_line_shipping_quantities()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    target_line_id uuid;
    packed_total numeric(24,8);
    shipped_total numeric(24,8);
    delivered_total numeric(24,8);
    digital_total numeric(24,8);
    service_total numeric(24,8);
    completed_total numeric(24,8);
BEGIN
    target_line_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.fulfillment_order_line_id ELSE NEW.fulfillment_order_line_id END;
    SELECT COALESCE(sum(packed_quantity), 0), COALESCE(sum(shipped_quantity), 0),
           COALESCE(sum(delivered_quantity), 0)
      INTO packed_total, shipped_total, delivered_total
      FROM doms.shipment_lines
     WHERE fulfillment_order_line_id = target_line_id
       AND status <> 'CANCELLED';
    SELECT COALESCE(sum(quantity), 0) INTO digital_total
      FROM doms.digital_fulfillments
     WHERE fulfillment_order_line_id = target_line_id
       AND status IN ('DELIVERED','ACTIVATED');
    SELECT COALESCE(sum(quantity), 0) INTO service_total
      FROM doms.service_fulfillments
     WHERE fulfillment_order_line_id = target_line_id
       AND status IN ('COMPLETED','CLOSED');
    completed_total := shipped_total + digital_total + service_total;

    UPDATE doms.fulfillment_order_lines
       SET picked_quantity = GREATEST(picked_quantity, packed_total),
           packed_quantity = packed_total,
           shipped_quantity = shipped_total,
           delivered_quantity = delivered_total,
           fulfilled_quantity = GREATEST(fulfilled_quantity, completed_total),
           consumed_quantity = GREATEST(consumed_quantity, completed_total),
           updated_at = now(),
           row_version = row_version + 1
     WHERE id = target_line_id;
    RETURN NULL;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.validate_package_item_quantity()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    package_shipment_id uuid;
    shipment_line_row doms.shipment_lines%ROWTYPE;
    packed_total numeric(24,8);
    package_status varchar(20);
BEGIN
    IF TG_OP = 'UPDATE' AND (
        OLD.tenant_id IS DISTINCT FROM NEW.tenant_id OR OLD.package_id IS DISTINCT FROM NEW.package_id OR
        OLD.shipment_line_id IS DISTINCT FROM NEW.shipment_line_id OR
        OLD.fulfillment_order_line_id IS DISTINCT FROM NEW.fulfillment_order_line_id OR
        OLD.item_id IS DISTINCT FROM NEW.item_id OR OLD.uom_code IS DISTINCT FROM NEW.uom_code OR
        OLD.idempotency_key IS DISTINCT FROM NEW.idempotency_key
    ) THEN
        RAISE EXCEPTION 'Package-item identity, shipment/fulfillment line, item/UOM, and idempotency key are immutable'
            USING ERRCODE = '23514';
    END IF;
    SELECT shipment_id, status INTO package_shipment_id, package_status
      FROM doms.packages
     WHERE tenant_id = NEW.tenant_id AND id = NEW.package_id
     FOR UPDATE;
    SELECT * INTO shipment_line_row
      FROM doms.shipment_lines
     WHERE tenant_id = NEW.tenant_id AND id = NEW.shipment_line_id
     FOR UPDATE;

    IF package_shipment_id IS NULL OR shipment_line_row.id IS NULL
       OR package_shipment_id <> shipment_line_row.shipment_id
       OR NEW.fulfillment_order_line_id <> shipment_line_row.fulfillment_order_line_id
       OR NEW.item_id <> shipment_line_row.item_id OR NEW.uom_code <> shipment_line_row.uom_code THEN
        RAISE EXCEPTION 'Package item differs from its package or shipment line'
            USING ERRCODE = '23514';
    END IF;
    IF package_status NOT IN ('OPEN','PACKING') THEN
        RAISE EXCEPTION 'Package items are mutable only while the package is OPEN or PACKING'
            USING ERRCODE = '55000';
    END IF;
    SELECT COALESCE(sum(packed_quantity), 0)
      INTO packed_total
      FROM doms.package_items
     WHERE shipment_line_id = NEW.shipment_line_id AND id <> NEW.id;
    IF packed_total + NEW.packed_quantity > shipment_line_row.planned_quantity - shipment_line_row.cancelled_quantity THEN
        RAISE EXCEPTION 'Package-item quantities exceed the shipment-line quantity'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.guard_package_item_delete()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    package_status varchar(20);
BEGIN
    SELECT status INTO package_status
      FROM doms.packages
     WHERE tenant_id = OLD.tenant_id AND id = OLD.package_id
     FOR UPDATE;
    IF package_status NOT IN ('OPEN','PACKING') THEN
        RAISE EXCEPTION 'Package items can be removed only while the package is OPEN or PACKING'
            USING ERRCODE = '55000';
    END IF;
    RETURN OLD;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.sync_shipment_line_packed_quantity()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    target_line_id uuid;
    packed_total numeric(24,8);
BEGIN
    target_line_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.shipment_line_id ELSE NEW.shipment_line_id END;
    SELECT COALESCE(sum(packed_quantity), 0) INTO packed_total
      FROM doms.package_items
     WHERE shipment_line_id = target_line_id;
    UPDATE doms.shipment_lines
       SET packed_quantity = packed_total,
           updated_at = now(),
           row_version = row_version + 1
     WHERE id = target_line_id;
    RETURN NULL;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.validate_package_lot_evidence_quantity()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    package_item_row record;
    item_lot_controlled boolean;
    evidence_total numeric(24,8);
BEGIN
    SELECT packed_quantity, item_id INTO package_item_row
      FROM doms.package_items
     WHERE tenant_id = NEW.tenant_id AND id = NEW.package_item_id
     FOR UPDATE;
    SELECT lot_controlled INTO item_lot_controlled
      FROM doms.items WHERE tenant_id = NEW.tenant_id AND id = package_item_row.item_id;
    IF package_item_row.item_id IS NULL OR NOT COALESCE(item_lot_controlled, false) THEN
        RAISE EXCEPTION 'Lot evidence requires a lot-controlled package item'
            USING ERRCODE = '23514';
    END IF;
    SELECT COALESCE(sum(quantity), 0) INTO evidence_total
      FROM doms.package_lot_evidence
     WHERE package_item_id = NEW.package_item_id AND id <> NEW.id;
    IF evidence_total + NEW.quantity > package_item_row.packed_quantity THEN
        RAISE EXCEPTION 'Lot evidence quantities exceed the package-item quantity'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.validate_package_serial_evidence_quantity()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    package_item_row record;
    item_serial_controlled boolean;
    serial_count bigint;
BEGIN
    SELECT packed_quantity, item_id INTO package_item_row
      FROM doms.package_items
     WHERE tenant_id = NEW.tenant_id AND id = NEW.package_item_id
     FOR UPDATE;
    SELECT serial_controlled INTO item_serial_controlled
      FROM doms.items WHERE tenant_id = NEW.tenant_id AND id = package_item_row.item_id;
    IF package_item_row.item_id IS NULL OR NOT COALESCE(item_serial_controlled, false)
       OR package_item_row.packed_quantity <> trunc(package_item_row.packed_quantity) THEN
        RAISE EXCEPTION 'Serial evidence requires an integer quantity of a serial-controlled item'
            USING ERRCODE = '23514';
    END IF;
    SELECT count(*) INTO serial_count
      FROM doms.package_serial_evidence
     WHERE package_item_id = NEW.package_item_id AND id <> NEW.id;
    IF serial_count + 1 > package_item_row.packed_quantity THEN
        RAISE EXCEPTION 'Serial evidence count exceeds the package-item quantity'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.validate_digital_fulfillment_quantity()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    fulfillment_line_row doms.fulfillment_order_lines%ROWTYPE;
    header_fulfillment_type varchar(30);
    reserved_total numeric(24,8);
BEGIN
    IF TG_OP = 'UPDATE' AND (
        OLD.tenant_id IS DISTINCT FROM NEW.tenant_id OR
        OLD.fulfillment_order_id IS DISTINCT FROM NEW.fulfillment_order_id OR
        OLD.fulfillment_order_line_id IS DISTINCT FROM NEW.fulfillment_order_line_id OR
        OLD.item_id IS DISTINCT FROM NEW.item_id OR OLD.uom_code IS DISTINCT FROM NEW.uom_code OR
        OLD.idempotency_key IS DISTINCT FROM NEW.idempotency_key OR
        OLD.entitlement_reference IS DISTINCT FROM NEW.entitlement_reference
    ) THEN
        RAISE EXCEPTION 'Digital-fulfillment identity, entitlement, item/UOM, and idempotency key are immutable'
            USING ERRCODE = '23514';
    END IF;
    SELECT * INTO fulfillment_line_row
      FROM doms.fulfillment_order_lines
     WHERE tenant_id = NEW.tenant_id AND id = NEW.fulfillment_order_line_id
     FOR UPDATE;
    SELECT fulfillment_type INTO header_fulfillment_type
      FROM doms.fulfillment_orders
     WHERE tenant_id = NEW.tenant_id AND id = NEW.fulfillment_order_id;
    IF fulfillment_line_row.id IS NULL
       OR fulfillment_line_row.fulfillment_order_id <> NEW.fulfillment_order_id
       OR fulfillment_line_row.item_id <> NEW.item_id OR fulfillment_line_row.uom_code <> NEW.uom_code
       OR header_fulfillment_type NOT IN ('DIGITAL','MIXED') THEN
        RAISE EXCEPTION 'Digital fulfillment requires a matching DIGITAL or MIXED fulfillment line'
            USING ERRCODE = '23514';
    END IF;

    SELECT
        COALESCE((SELECT sum(planned_quantity - cancelled_quantity)
                    FROM doms.shipment_plan_lines
                   WHERE fulfillment_order_line_id = NEW.fulfillment_order_line_id
                     AND status <> 'CANCELLED'), 0) +
        COALESCE((SELECT sum(quantity)
                    FROM doms.service_fulfillments
                   WHERE fulfillment_order_line_id = NEW.fulfillment_order_line_id
                     AND status NOT IN ('FAILED','NO_SHOW','CANCELLED','CLOSED')), 0) +
        COALESCE((SELECT sum(quantity)
                    FROM doms.digital_fulfillments
                   WHERE fulfillment_order_line_id = NEW.fulfillment_order_line_id
                     AND id <> NEW.id
                     AND status NOT IN ('FAILED','REVOKED','EXPIRED','CANCELLED')), 0)
      INTO reserved_total;
    IF reserved_total +
       (CASE WHEN NEW.status IN ('FAILED','REVOKED','EXPIRED','CANCELLED') THEN 0 ELSE NEW.quantity END)
       > fulfillment_line_row.allocated_quantity - fulfillment_line_row.cancelled_quantity THEN
        RAISE EXCEPTION 'Digital/service/shipment execution quantities exceed the fulfillment-line quantity'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.validate_service_fulfillment_quantity()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    fulfillment_line_row doms.fulfillment_order_lines%ROWTYPE;
    header_fulfillment_type varchar(30);
    reserved_total numeric(24,8);
BEGIN
    IF TG_OP = 'UPDATE' AND (
        OLD.tenant_id IS DISTINCT FROM NEW.tenant_id OR
        OLD.fulfillment_order_id IS DISTINCT FROM NEW.fulfillment_order_id OR
        OLD.fulfillment_order_line_id IS DISTINCT FROM NEW.fulfillment_order_line_id OR
        OLD.item_id IS DISTINCT FROM NEW.item_id OR OLD.uom_code IS DISTINCT FROM NEW.uom_code OR
        OLD.idempotency_key IS DISTINCT FROM NEW.idempotency_key
    ) THEN
        RAISE EXCEPTION 'Service-fulfillment identity, item/UOM, and idempotency key are immutable'
            USING ERRCODE = '23514';
    END IF;
    SELECT * INTO fulfillment_line_row
      FROM doms.fulfillment_order_lines
     WHERE tenant_id = NEW.tenant_id AND id = NEW.fulfillment_order_line_id
     FOR UPDATE;
    SELECT fulfillment_type INTO header_fulfillment_type
      FROM doms.fulfillment_orders
     WHERE tenant_id = NEW.tenant_id AND id = NEW.fulfillment_order_id;
    IF fulfillment_line_row.id IS NULL
       OR fulfillment_line_row.fulfillment_order_id <> NEW.fulfillment_order_id
       OR fulfillment_line_row.item_id <> NEW.item_id OR fulfillment_line_row.uom_code <> NEW.uom_code
       OR header_fulfillment_type NOT IN ('SERVICE','MIXED') THEN
        RAISE EXCEPTION 'Service fulfillment requires a matching SERVICE or MIXED fulfillment line'
            USING ERRCODE = '23514';
    END IF;

    SELECT
        COALESCE((SELECT sum(planned_quantity - cancelled_quantity)
                    FROM doms.shipment_plan_lines
                   WHERE fulfillment_order_line_id = NEW.fulfillment_order_line_id
                     AND status <> 'CANCELLED'), 0) +
        COALESCE((SELECT sum(quantity)
                    FROM doms.digital_fulfillments
                   WHERE fulfillment_order_line_id = NEW.fulfillment_order_line_id
                     AND status NOT IN ('FAILED','REVOKED','EXPIRED','CANCELLED')), 0) +
        COALESCE((SELECT sum(quantity)
                     FROM doms.service_fulfillments
                   WHERE fulfillment_order_line_id = NEW.fulfillment_order_line_id
                     AND id <> NEW.id
                     AND status NOT IN ('FAILED','NO_SHOW','CANCELLED')), 0)
      INTO reserved_total;
    IF reserved_total +
       (CASE WHEN NEW.status IN ('FAILED','NO_SHOW','CANCELLED') THEN 0 ELSE NEW.quantity END)
       > fulfillment_line_row.allocated_quantity - fulfillment_line_row.cancelled_quantity THEN
        RAISE EXCEPTION 'Service/digital/shipment execution quantities exceed the fulfillment-line quantity'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.sync_fulfillment_line_completed_quantity()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    target_line_id uuid;
    shipped_total numeric(24,8);
    digital_total numeric(24,8);
    service_total numeric(24,8);
    completed_total numeric(24,8);
BEGIN
    target_line_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.fulfillment_order_line_id ELSE NEW.fulfillment_order_line_id END;
    SELECT COALESCE(sum(shipped_quantity), 0) INTO shipped_total
      FROM doms.shipment_lines
     WHERE fulfillment_order_line_id = target_line_id AND status <> 'CANCELLED';
    SELECT COALESCE(sum(quantity), 0) INTO digital_total
      FROM doms.digital_fulfillments
     WHERE fulfillment_order_line_id = target_line_id AND status IN ('DELIVERED','ACTIVATED');
    SELECT COALESCE(sum(quantity), 0) INTO service_total
      FROM doms.service_fulfillments
     WHERE fulfillment_order_line_id = target_line_id AND status IN ('COMPLETED','CLOSED');
    completed_total := shipped_total + digital_total + service_total;

    UPDATE doms.fulfillment_order_lines
       SET fulfilled_quantity = GREATEST(fulfilled_quantity, completed_total),
           consumed_quantity = GREATEST(consumed_quantity, completed_total),
           updated_at = now(),
           row_version = row_version + 1
     WHERE id = target_line_id;
    RETURN NULL;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.validate_booking_selected_attempt()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    attempt_row record;
BEGIN
    IF NEW.selected_attempt_id IS NULL THEN
        RETURN NEW;
    END IF;
    SELECT carrier_booking_request_id, status INTO attempt_row
      FROM doms.carrier_booking_attempts
     WHERE tenant_id = NEW.tenant_id AND id = NEW.selected_attempt_id;
    IF attempt_row.carrier_booking_request_id IS NULL
       OR attempt_row.carrier_booking_request_id <> NEW.id OR attempt_row.status <> 'SUCCEEDED' THEN
        RAISE EXCEPTION 'Selected booking attempt must be a successful attempt of the same request'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.sync_booking_attempt_count()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    target_request_id uuid;
    total_count integer;
BEGIN
    target_request_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.carrier_booking_request_id ELSE NEW.carrier_booking_request_id END;
    SELECT count(*) INTO total_count
      FROM doms.carrier_booking_attempts
     WHERE carrier_booking_request_id = target_request_id;
    UPDATE doms.carrier_booking_requests
       SET attempt_count = total_count,
           row_version = row_version + 1,
           updated_at = now()
     WHERE id = target_request_id;
    RETURN NULL;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.guard_shipping_cost_posted()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    IF TG_OP = 'DELETE' OR OLD.status IN ('POSTED','REVERSED') THEN
        RAISE EXCEPTION 'Posted/reversed shipping cost facts are immutable; use a reversal fact'
            USING ERRCODE = '55000';
    END IF;
    IF OLD.tenant_id IS DISTINCT FROM NEW.tenant_id OR OLD.shipment_id IS DISTINCT FROM NEW.shipment_id
       OR OLD.package_id IS DISTINCT FROM NEW.package_id OR OLD.cost_type IS DISTINCT FROM NEW.cost_type
       OR OLD.currency_code IS DISTINCT FROM NEW.currency_code THEN
        RAISE EXCEPTION 'Shipping cost fact identity, target, type, and currency are immutable'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.guard_confirmation_header()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    line_count integer;
    reversed_status varchar(20);
BEGIN
    IF TG_OP = 'UPDATE' AND OLD.status IN ('POSTED','REVERSED') THEN
        RAISE EXCEPTION 'Posted fulfillment confirmations are immutable; create a reversal confirmation'
            USING ERRCODE = '55000';
    END IF;
    IF TG_OP = 'UPDATE' AND (
        OLD.tenant_id IS DISTINCT FROM NEW.tenant_id OR
        OLD.fulfillment_order_id IS DISTINCT FROM NEW.fulfillment_order_id OR
        OLD.shipment_id IS DISTINCT FROM NEW.shipment_id OR
        OLD.pickup_order_id IS DISTINCT FROM NEW.pickup_order_id OR
        OLD.digital_fulfillment_id IS DISTINCT FROM NEW.digital_fulfillment_id OR
        OLD.service_fulfillment_id IS DISTINCT FROM NEW.service_fulfillment_id OR
        OLD.confirmation_type IS DISTINCT FROM NEW.confirmation_type OR
        OLD.idempotency_key IS DISTINCT FROM NEW.idempotency_key
    ) THEN
        RAISE EXCEPTION 'Fulfillment confirmation identity, target, type, and idempotency key are immutable'
            USING ERRCODE = '23514';
    END IF;
    IF NEW.confirmation_type = 'REVERSAL' THEN
        SELECT status INTO reversed_status
          FROM doms.fulfillment_confirmations
         WHERE tenant_id = NEW.tenant_id AND id = NEW.reversal_of_id;
        IF reversed_status IS DISTINCT FROM 'POSTED' THEN
            RAISE EXCEPTION 'Reversal confirmation must reference a posted confirmation'
                USING ERRCODE = '23514';
        END IF;
    END IF;
    IF NEW.status = 'POSTED' THEN
        SELECT count(*) INTO line_count
          FROM doms.fulfillment_confirmation_lines
         WHERE fulfillment_confirmation_id = NEW.id;
        IF line_count = 0 THEN
            RAISE EXCEPTION 'A confirmation must contain at least one line before posting'
                USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.validate_confirmation_line()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    confirmation_row record;
    fulfillment_line_row doms.fulfillment_order_lines%ROWTYPE;
    shipment_line_row doms.shipment_lines%ROWTYPE;
    prior_total numeric(24,8);
    new_effect numeric(24,8);
    allowed_quantity numeric(24,8);
BEGIN
    IF TG_OP = 'UPDATE' AND (
        OLD.tenant_id IS DISTINCT FROM NEW.tenant_id OR
        OLD.fulfillment_confirmation_id IS DISTINCT FROM NEW.fulfillment_confirmation_id OR
        OLD.fulfillment_order_line_id IS DISTINCT FROM NEW.fulfillment_order_line_id OR
        OLD.shipment_line_id IS DISTINCT FROM NEW.shipment_line_id OR
        OLD.uom_code IS DISTINCT FROM NEW.uom_code
    ) THEN
        RAISE EXCEPTION 'Confirmation-line header, target line, and UOM are immutable'
            USING ERRCODE = '23514';
    END IF;
    SELECT confirmation_type, status, fulfillment_order_id, shipment_id,
           digital_fulfillment_id, service_fulfillment_id
      INTO confirmation_row
      FROM doms.fulfillment_confirmations
     WHERE tenant_id = NEW.tenant_id AND id = NEW.fulfillment_confirmation_id
     FOR UPDATE;
    SELECT * INTO fulfillment_line_row
      FROM doms.fulfillment_order_lines
     WHERE tenant_id = NEW.tenant_id AND id = NEW.fulfillment_order_line_id
     FOR UPDATE;

    IF confirmation_row.status IS NULL OR confirmation_row.status NOT IN ('DRAFT','CONFIRMED')
       OR fulfillment_line_row.id IS NULL
       OR fulfillment_line_row.fulfillment_order_id <> confirmation_row.fulfillment_order_id
       OR fulfillment_line_row.uom_code <> NEW.uom_code THEN
        RAISE EXCEPTION 'Confirmation line must match an editable confirmation and fulfillment line/UOM'
            USING ERRCODE = '23514';
    END IF;

    allowed_quantity := fulfillment_line_row.allocated_quantity - fulfillment_line_row.cancelled_quantity;
    IF confirmation_row.confirmation_type = 'SHIPMENT' THEN
        IF NEW.shipment_line_id IS NULL THEN
            RAISE EXCEPTION 'Shipment confirmation lines require a shipment line'
                USING ERRCODE = '23514';
        END IF;
        SELECT * INTO shipment_line_row
          FROM doms.shipment_lines
         WHERE tenant_id = NEW.tenant_id AND id = NEW.shipment_line_id;
        IF shipment_line_row.id IS NULL
           OR shipment_line_row.shipment_id <> confirmation_row.shipment_id
           OR shipment_line_row.fulfillment_order_line_id <> NEW.fulfillment_order_line_id
           OR shipment_line_row.uom_code <> NEW.uom_code THEN
            RAISE EXCEPTION 'Shipment confirmation line differs from its shipment or fulfillment line'
                USING ERRCODE = '23514';
        END IF;
        allowed_quantity := shipment_line_row.shipped_quantity;
    ELSIF NEW.shipment_line_id IS NOT NULL THEN
        RAISE EXCEPTION 'Only shipment confirmations may reference a shipment line'
            USING ERRCODE = '23514';
    END IF;

    SELECT COALESCE(sum(
               CASE WHEN confirmation.confirmation_type = 'REVERSAL'
                    THEN -line.confirmed_quantity ELSE line.confirmed_quantity END
           ), 0)
      INTO prior_total
      FROM doms.fulfillment_confirmation_lines line
      JOIN doms.fulfillment_confirmations confirmation
        ON confirmation.id = line.fulfillment_confirmation_id
     WHERE line.fulfillment_order_line_id = NEW.fulfillment_order_line_id
       AND line.id <> NEW.id
       AND confirmation.status NOT IN ('FAILED','CANCELLED');

    new_effect := CASE WHEN confirmation_row.confirmation_type = 'REVERSAL'
                       THEN -NEW.confirmed_quantity ELSE NEW.confirmed_quantity END;
    IF prior_total + new_effect < 0 OR prior_total + new_effect > allowed_quantity THEN
        RAISE EXCEPTION 'Net confirmation quantity exceeds its fulfillment/shipment quantity'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION doms.guard_confirmation_line_change()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    parent_id uuid;
    parent_status varchar(20);
BEGIN
    parent_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.fulfillment_confirmation_id ELSE NEW.fulfillment_confirmation_id END;
    SELECT status INTO parent_status
      FROM doms.fulfillment_confirmations
     WHERE id = parent_id
     FOR UPDATE;
    IF parent_status NOT IN ('DRAFT','CONFIRMED') THEN
        RAISE EXCEPTION 'Confirmation lines are immutable after posting/failure/cancellation'
            USING ERRCODE = '55000';
    END IF;
    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$function$;

DROP TRIGGER IF EXISTS trg_fulfillment_order_status ON doms.fulfillment_orders;
CREATE TRIGGER trg_fulfillment_order_status
    BEFORE UPDATE OF status ON doms.fulfillment_orders
    FOR EACH ROW EXECUTE PROCEDURE doms.enforce_fulfillment_status_transition('FULFILLMENT');
DROP TRIGGER IF EXISTS trg_fulfillment_order_scope ON doms.fulfillment_orders;
CREATE TRIGGER trg_fulfillment_order_scope
    BEFORE INSERT OR UPDATE ON doms.fulfillment_orders
    FOR EACH ROW EXECUTE PROCEDURE doms.validate_fulfillment_order_scope();
DROP TRIGGER IF EXISTS trg_fulfillment_order_delivery_method ON doms.fulfillment_orders;
CREATE TRIGGER trg_fulfillment_order_delivery_method
    BEFORE INSERT OR UPDATE OF delivery_method_id ON doms.fulfillment_orders
    FOR EACH ROW EXECUTE PROCEDURE doms.validate_delivery_method_scope();

DROP TRIGGER IF EXISTS trg_fulfillment_line_status ON doms.fulfillment_order_lines;
CREATE TRIGGER trg_fulfillment_line_status
    BEFORE UPDATE OF status ON doms.fulfillment_order_lines
    FOR EACH ROW EXECUTE PROCEDURE doms.enforce_fulfillment_status_transition('FULFILLMENT_LINE');
DROP TRIGGER IF EXISTS trg_fulfillment_line_quantity ON doms.fulfillment_order_lines;
CREATE TRIGGER trg_fulfillment_line_quantity
    BEFORE INSERT OR UPDATE ON doms.fulfillment_order_lines
    FOR EACH ROW EXECUTE PROCEDURE doms.validate_fulfillment_order_line();
DROP TRIGGER IF EXISTS trg_fulfillment_line_sync_allocation ON doms.fulfillment_order_lines;
CREATE TRIGGER trg_fulfillment_line_sync_allocation
    AFTER INSERT OR UPDATE ON doms.fulfillment_order_lines
    FOR EACH ROW EXECUTE PROCEDURE doms.sync_fulfillment_allocation_consumption();

DROP TRIGGER IF EXISTS trg_shipment_plan_status ON doms.shipment_plans;
CREATE TRIGGER trg_shipment_plan_status
    BEFORE UPDATE OF status ON doms.shipment_plans
    FOR EACH ROW EXECUTE PROCEDURE doms.enforce_fulfillment_status_transition('SHIPMENT_PLAN');
DROP TRIGGER IF EXISTS trg_shipment_plan_delivery_method ON doms.shipment_plans;
CREATE TRIGGER trg_shipment_plan_delivery_method
    BEFORE INSERT OR UPDATE OF delivery_method_id ON doms.shipment_plans
    FOR EACH ROW EXECUTE PROCEDURE doms.validate_delivery_method_scope();
DROP TRIGGER IF EXISTS trg_shipment_plan_line_quantity ON doms.shipment_plan_lines;
CREATE TRIGGER trg_shipment_plan_line_quantity
    BEFORE INSERT OR UPDATE ON doms.shipment_plan_lines
    FOR EACH ROW EXECUTE PROCEDURE doms.validate_shipment_plan_line();

DROP TRIGGER IF EXISTS trg_shipment_status ON doms.shipments;
CREATE TRIGGER trg_shipment_status
    BEFORE UPDATE OF status ON doms.shipments
    FOR EACH ROW EXECUTE PROCEDURE doms.enforce_fulfillment_status_transition('SHIPMENT');
DROP TRIGGER IF EXISTS trg_shipment_scope ON doms.shipments;
CREATE TRIGGER trg_shipment_scope
    BEFORE INSERT OR UPDATE ON doms.shipments
    FOR EACH ROW EXECUTE PROCEDURE doms.validate_shipment_scope();
DROP TRIGGER IF EXISTS trg_shipment_line_quantity ON doms.shipment_lines;
CREATE TRIGGER trg_shipment_line_quantity
    BEFORE INSERT OR UPDATE ON doms.shipment_lines
    FOR EACH ROW EXECUTE PROCEDURE doms.validate_shipment_line();
DROP TRIGGER IF EXISTS trg_shipment_line_sync_fulfillment ON doms.shipment_lines;
CREATE TRIGGER trg_shipment_line_sync_fulfillment
    AFTER INSERT OR UPDATE ON doms.shipment_lines
    FOR EACH ROW EXECUTE PROCEDURE doms.sync_fulfillment_line_shipping_quantities();
DROP TRIGGER IF EXISTS trg_shipment_line_sync_completed ON doms.shipment_lines;

DROP TRIGGER IF EXISTS trg_package_status ON doms.packages;
CREATE TRIGGER trg_package_status
    BEFORE UPDATE OF status ON doms.packages
    FOR EACH ROW EXECUTE PROCEDURE doms.enforce_fulfillment_status_transition('PACKAGE');
DROP TRIGGER IF EXISTS trg_package_item_quantity ON doms.package_items;
CREATE TRIGGER trg_package_item_quantity
    BEFORE INSERT OR UPDATE ON doms.package_items
    FOR EACH ROW EXECUTE PROCEDURE doms.validate_package_item_quantity();
DROP TRIGGER IF EXISTS trg_package_item_delete_guard ON doms.package_items;
CREATE TRIGGER trg_package_item_delete_guard
    BEFORE DELETE ON doms.package_items
    FOR EACH ROW EXECUTE PROCEDURE doms.guard_package_item_delete();
DROP TRIGGER IF EXISTS trg_package_item_sync_line ON doms.package_items;
CREATE TRIGGER trg_package_item_sync_line
    AFTER INSERT OR UPDATE OR DELETE ON doms.package_items
    FOR EACH ROW EXECUTE PROCEDURE doms.sync_shipment_line_packed_quantity();
DROP TRIGGER IF EXISTS trg_package_lot_evidence_quantity ON doms.package_lot_evidence;
CREATE TRIGGER trg_package_lot_evidence_quantity
    BEFORE INSERT ON doms.package_lot_evidence
    FOR EACH ROW EXECUTE PROCEDURE doms.validate_package_lot_evidence_quantity();
DROP TRIGGER IF EXISTS trg_package_serial_evidence_quantity ON doms.package_serial_evidence;
CREATE TRIGGER trg_package_serial_evidence_quantity
    BEFORE INSERT ON doms.package_serial_evidence
    FOR EACH ROW EXECUTE PROCEDURE doms.validate_package_serial_evidence_quantity();

DROP TRIGGER IF EXISTS trg_booking_request_selected_attempt ON doms.carrier_booking_requests;
CREATE TRIGGER trg_booking_request_selected_attempt
    BEFORE INSERT OR UPDATE OF selected_attempt_id ON doms.carrier_booking_requests
    FOR EACH ROW EXECUTE PROCEDURE doms.validate_booking_selected_attempt();
DROP TRIGGER IF EXISTS trg_booking_attempt_sync_count ON doms.carrier_booking_attempts;
CREATE TRIGGER trg_booking_attempt_sync_count
    AFTER INSERT ON doms.carrier_booking_attempts
    FOR EACH ROW EXECUTE PROCEDURE doms.sync_booking_attempt_count();

DROP TRIGGER IF EXISTS trg_pickup_status ON doms.pickup_orders;
CREATE TRIGGER trg_pickup_status
    BEFORE UPDATE OF status ON doms.pickup_orders
    FOR EACH ROW EXECUTE PROCEDURE doms.enforce_fulfillment_status_transition('PICKUP');
DROP TRIGGER IF EXISTS trg_appointment_status ON doms.delivery_appointments;
CREATE TRIGGER trg_appointment_status
    BEFORE UPDATE OF status ON doms.delivery_appointments
    FOR EACH ROW EXECUTE PROCEDURE doms.enforce_fulfillment_status_transition('APPOINTMENT');

DROP TRIGGER IF EXISTS trg_digital_fulfillment_status ON doms.digital_fulfillments;
CREATE TRIGGER trg_digital_fulfillment_status
    BEFORE UPDATE OF status ON doms.digital_fulfillments
    FOR EACH ROW EXECUTE PROCEDURE doms.enforce_fulfillment_status_transition('DIGITAL');
DROP TRIGGER IF EXISTS trg_digital_fulfillment_quantity ON doms.digital_fulfillments;
CREATE TRIGGER trg_digital_fulfillment_quantity
    BEFORE INSERT OR UPDATE ON doms.digital_fulfillments
    FOR EACH ROW EXECUTE PROCEDURE doms.validate_digital_fulfillment_quantity();
DROP TRIGGER IF EXISTS trg_digital_fulfillment_sync_line ON doms.digital_fulfillments;
CREATE TRIGGER trg_digital_fulfillment_sync_line
    AFTER INSERT OR UPDATE ON doms.digital_fulfillments
    FOR EACH ROW EXECUTE PROCEDURE doms.sync_fulfillment_line_completed_quantity();

DROP TRIGGER IF EXISTS trg_service_fulfillment_status ON doms.service_fulfillments;
CREATE TRIGGER trg_service_fulfillment_status
    BEFORE UPDATE OF status ON doms.service_fulfillments
    FOR EACH ROW EXECUTE PROCEDURE doms.enforce_fulfillment_status_transition('SERVICE');
DROP TRIGGER IF EXISTS trg_service_fulfillment_quantity ON doms.service_fulfillments;
CREATE TRIGGER trg_service_fulfillment_quantity
    BEFORE INSERT OR UPDATE ON doms.service_fulfillments
    FOR EACH ROW EXECUTE PROCEDURE doms.validate_service_fulfillment_quantity();
DROP TRIGGER IF EXISTS trg_service_fulfillment_sync_line ON doms.service_fulfillments;
CREATE TRIGGER trg_service_fulfillment_sync_line
    AFTER INSERT OR UPDATE ON doms.service_fulfillments
    FOR EACH ROW EXECUTE PROCEDURE doms.sync_fulfillment_line_completed_quantity();

DROP TRIGGER IF EXISTS trg_shipping_cost_posted_guard ON doms.shipping_cost_facts;
CREATE TRIGGER trg_shipping_cost_posted_guard
    BEFORE UPDATE OR DELETE ON doms.shipping_cost_facts
    FOR EACH ROW EXECUTE PROCEDURE doms.guard_shipping_cost_posted();

DROP TRIGGER IF EXISTS trg_confirmation_status ON doms.fulfillment_confirmations;
CREATE TRIGGER trg_confirmation_status
    BEFORE UPDATE OF status ON doms.fulfillment_confirmations
    FOR EACH ROW EXECUTE PROCEDURE doms.enforce_fulfillment_status_transition('CONFIRMATION');
DROP TRIGGER IF EXISTS trg_confirmation_header_guard ON doms.fulfillment_confirmations;
CREATE TRIGGER trg_confirmation_header_guard
    BEFORE INSERT OR UPDATE ON doms.fulfillment_confirmations
    FOR EACH ROW EXECUTE PROCEDURE doms.guard_confirmation_header();
DROP TRIGGER IF EXISTS trg_confirmation_line_guard ON doms.fulfillment_confirmation_lines;
CREATE TRIGGER trg_confirmation_line_guard
    BEFORE INSERT OR UPDATE OR DELETE ON doms.fulfillment_confirmation_lines
    FOR EACH ROW EXECUTE PROCEDURE doms.guard_confirmation_line_change();
DROP TRIGGER IF EXISTS trg_confirmation_line_quantity ON doms.fulfillment_confirmation_lines;
CREATE TRIGGER trg_confirmation_line_quantity
    BEFORE INSERT OR UPDATE ON doms.fulfillment_confirmation_lines
    FOR EACH ROW EXECUTE PROCEDURE doms.validate_confirmation_line();

DO $block$
DECLARE
    table_name text;
BEGIN
    FOREACH table_name IN ARRAY ARRAY[
        'fulfillment_order_status_events','fulfillment_order_line_status_events',
        'fulfillment_split_relations','shipment_status_events','package_status_events',
        'package_lot_evidence','package_serial_evidence','shipment_tracking_events',
        'carrier_booking_attempts','pickup_events','delivery_appointment_events','delivery_events',
        'proof_of_delivery_objects','digital_fulfillment_events','service_fulfillment_events',
        'fulfillment_confirmation_events'
    ]
    LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS trg_append_only ON doms.%I', table_name);
        EXECUTE format(
            'CREATE TRIGGER trg_append_only BEFORE UPDATE OR DELETE ON doms.%I '
            'FOR EACH ROW EXECUTE PROCEDURE doms.prevent_fulfillment_append_only_change()',
            table_name
        );
    END LOOP;
END;
$block$;

DO $block$
DECLARE
    table_name text;
BEGIN
    FOREACH table_name IN ARRAY ARRAY[
        'fulfillment_orders','fulfillment_order_lines','fulfillment_holds','fulfillment_exceptions',
        'shipment_plans','shipment_plan_lines','shipments','shipment_lines','packages',
        'shipment_tracking_numbers','carrier_booking_requests','shipping_labels','shipping_manifests',
        'shipping_manifest_links','pickup_orders','delivery_appointments','delivery_exceptions',
        'proof_of_delivery_records','digital_fulfillments','service_fulfillments','fulfillment_confirmations'
    ]
    LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS trg_prevent_delete ON doms.%I', table_name);
        EXECUTE format(
            'CREATE TRIGGER trg_prevent_delete BEFORE DELETE ON doms.%I '
            'FOR EACH ROW EXECUTE PROCEDURE doms.prevent_fulfillment_delete()',
            table_name
        );
    END LOOP;
END;
$block$;

DO $block$
DECLARE
    table_name text;
BEGIN
    FOREACH table_name IN ARRAY ARRAY[
        'fulfillment_orders','fulfillment_order_lines','fulfillment_holds','fulfillment_exceptions',
        'shipment_plans','shipment_plan_lines','shipments','shipment_lines','packages','package_items',
        'shipment_tracking_numbers','carrier_booking_requests','shipping_labels','shipping_manifests',
        'shipping_manifest_links','shipping_cost_facts','pickup_orders','delivery_appointments',
        'delivery_exceptions','proof_of_delivery_records','digital_fulfillments',
        'service_fulfillments','fulfillment_confirmations','fulfillment_confirmation_lines'
    ]
    LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS trg_touch_row ON doms.%I', table_name);
        EXECUTE format(
            'CREATE TRIGGER trg_touch_row BEFORE UPDATE ON doms.%I '
            'FOR EACH ROW EXECUTE PROCEDURE doms.touch_row()',
            table_name
        );
    END LOOP;
END;
$block$;

COMMENT ON TABLE doms.fulfillment_order_status_events IS
    'Append-only fulfillment-order lifecycle evidence independent of the mutable order header.';
COMMENT ON TABLE doms.shipment_tracking_events IS
    'Append-only carrier tracking observations with idempotent provider event references.';
COMMENT ON TABLE doms.fulfillment_confirmation_events IS
    'Append-only confirmation and posting audit stream; posted confirmation rows are immutable.';
