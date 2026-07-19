-- EWMS forward-only migration 20260713_02
-- Close composite/reference-key tenant gaps identified by the independent catalog audit.
-- PostgreSQL 11 compatible. The migration is idempotent and must run atomically.
--
-- The 27 baseline FKs below correctly bind their business keys, but the tenant pair was
-- not carried in the same FK.  This migration preserves those FKs and adds exact
-- tenant-bearing companion FKs.  Existing rows are explicitly preflighted and every
-- new FK is installed NOT VALID and then VALIDATEd before this transaction can commit.

-- FK targets must expose the exact tenant-bearing candidate key.  Each trailing id is
-- already globally unique, so these indexes add no new logical uniqueness assumption;
-- they make the tenant relationship explicit and usable by PostgreSQL's FK engine.
CREATE UNIQUE INDEX IF NOT EXISTS ux_ewms_bonded_item_tenant_owner_cargo_id
    ON ewms.bonded_cargo_items (tenant_id, owner_partner_id, bonded_cargo_id, id);

CREATE UNIQUE INDEX IF NOT EXISTS ux_ewms_bonded_report_version_tenant_report_id
    ON ewms.bonded_inout_report_versions (tenant_id, bonded_inout_report_id, id);

CREATE UNIQUE INDEX IF NOT EXISTS ux_ewms_customs_line_tenant_owner_version_id
    ON ewms.customs_declaration_lines (
        tenant_id, owner_partner_id, declaration_version_id, id
    );

CREATE UNIQUE INDEX IF NOT EXISTS ux_ewms_customs_version_tenant_declaration_id
    ON ewms.customs_declaration_versions (tenant_id, declaration_id, id);

CREATE UNIQUE INDEX IF NOT EXISTS ux_ewms_invoice_line_tenant_invoice_id
    ON ewms.invoice_lines (tenant_id, invoice_id, id);

DO $migration$
DECLARE
    relation record;
    existing_constraint record;
    child_column_list text;
    parent_column_list text;
    join_predicate text;
    child_not_null_predicate text;
    constraint_name text;
    index_name text;
    has_mismatch boolean;
BEGIN
    FOR relation IN
        SELECT mapping.child_table,
               mapping.child_columns,
               mapping.parent_table,
               mapping.parent_columns,
               mapping.delete_clause,
               mapping.deferrable_clause
          FROM (VALUES
            -- Bonded cargo-item scope.  The cargo id and item id must belong to the
            -- same tenant as the operational child row.
            ('bonded_discrepancies',
                ARRAY['tenant_id','owner_partner_id','bonded_cargo_id','bonded_cargo_item_id']::text[],
                'bonded_cargo_items',
                ARRAY['tenant_id','owner_partner_id','bonded_cargo_id','id']::text[],
                'ON DELETE RESTRICT', ''),
            ('bonded_disposal_lines',
                ARRAY['tenant_id','owner_partner_id','bonded_cargo_id','bonded_cargo_item_id']::text[],
                'bonded_cargo_items',
                ARRAY['tenant_id','owner_partner_id','bonded_cargo_id','id']::text[],
                'ON DELETE RESTRICT', ''),
            ('bonded_exception_authorizations',
                ARRAY['tenant_id','owner_partner_id','bonded_cargo_id','bonded_cargo_item_id']::text[],
                'bonded_cargo_items',
                ARRAY['tenant_id','owner_partner_id','bonded_cargo_id','id']::text[],
                'ON DELETE RESTRICT', ''),
            ('bonded_inventory_count_lines',
                ARRAY['tenant_id','owner_partner_id','bonded_cargo_id','bonded_cargo_item_id']::text[],
                'bonded_cargo_items',
                ARRAY['tenant_id','owner_partner_id','bonded_cargo_id','id']::text[],
                'ON DELETE RESTRICT', ''),
            ('bonded_inventory_movements',
                ARRAY['tenant_id','owner_partner_id','bonded_cargo_id','bonded_cargo_item_id']::text[],
                'bonded_cargo_items',
                ARRAY['tenant_id','owner_partner_id','bonded_cargo_id','id']::text[],
                'ON DELETE RESTRICT', ''),
            ('bonded_sample_movements',
                ARRAY['tenant_id','owner_partner_id','bonded_cargo_id','bonded_cargo_item_id']::text[],
                'bonded_cargo_items',
                ARRAY['tenant_id','owner_partner_id','bonded_cargo_id','id']::text[],
                'ON DELETE RESTRICT', ''),

            -- Current-version pointers are cyclic by design and remain deferred.
            ('bonded_inout_reports',
                ARRAY['tenant_id','id','current_version_id']::text[],
                'bonded_inout_report_versions',
                ARRAY['tenant_id','bonded_inout_report_id','id']::text[],
                '', 'DEFERRABLE INITIALLY DEFERRED'),

            -- Declaration line children must bind both the version and the line in
            -- the same tenant.
            ('customs_declaration_containers',
                ARRAY['tenant_id','owner_partner_id','declaration_version_id','declaration_line_id']::text[],
                'customs_declaration_lines',
                ARRAY['tenant_id','owner_partner_id','declaration_version_id','id']::text[],
                'ON DELETE RESTRICT', ''),
            ('customs_declaration_line_details',
                ARRAY['tenant_id','owner_partner_id','declaration_version_id','declaration_line_id']::text[],
                'customs_declaration_lines',
                ARRAY['tenant_id','owner_partner_id','declaration_version_id','id']::text[],
                'ON DELETE RESTRICT', ''),
            ('customs_declaration_requirements',
                ARRAY['tenant_id','owner_partner_id','declaration_version_id','declaration_line_id']::text[],
                'customs_declaration_lines',
                ARRAY['tenant_id','owner_partner_id','declaration_version_id','id']::text[],
                'ON DELETE RESTRICT', ''),
            ('customs_declaration_taxes',
                ARRAY['tenant_id','owner_partner_id','declaration_version_id','declaration_line_id']::text[],
                'customs_declaration_lines',
                ARRAY['tenant_id','owner_partner_id','declaration_version_id','id']::text[],
                'ON DELETE RESTRICT', ''),

            -- Declaration-version consumers must bind the declaration and version
            -- under the same tenant, including legal/financial evidence envelopes.
            ('customs_declaration_events',
                ARRAY['tenant_id','declaration_id','declaration_version_id']::text[],
                'customs_declaration_versions',
                ARRAY['tenant_id','declaration_id','id']::text[],
                'ON DELETE RESTRICT', ''),
            ('customs_declaration_inspections',
                ARRAY['tenant_id','declaration_id','declaration_version_id']::text[],
                'customs_declaration_versions',
                ARRAY['tenant_id','declaration_id','id']::text[],
                'ON DELETE RESTRICT', ''),
            ('customs_documents',
                ARRAY['tenant_id','declaration_id','declaration_version_id']::text[],
                'customs_declaration_versions',
                ARRAY['tenant_id','declaration_id','id']::text[],
                'ON DELETE RESTRICT', ''),
            ('customs_duty_payment_allocations',
                ARRAY['tenant_id','declaration_id','declaration_version_id']::text[],
                'customs_declaration_versions',
                ARRAY['tenant_id','declaration_id','id']::text[],
                'ON DELETE RESTRICT', ''),
            ('customs_refund_allocations',
                ARRAY['tenant_id','declaration_id','declaration_version_id']::text[],
                'customs_declaration_versions',
                ARRAY['tenant_id','declaration_id','id']::text[],
                'ON DELETE RESTRICT', ''),
            ('customs_release_evidence',
                ARRAY['tenant_id','declaration_id','declaration_version_id']::text[],
                'customs_declaration_versions',
                ARRAY['tenant_id','declaration_id','id']::text[],
                'ON DELETE RESTRICT', ''),
            ('unipass_messages',
                ARRAY['tenant_id','declaration_id','declaration_version_id']::text[],
                'customs_declaration_versions',
                ARRAY['tenant_id','declaration_id','id']::text[],
                'ON DELETE RESTRICT', ''),
            ('customs_declarations',
                ARRAY['tenant_id','id','current_version_id']::text[],
                'customs_declaration_versions',
                ARRAY['tenant_id','declaration_id','id']::text[],
                '', 'DEFERRABLE INITIALLY DEFERRED'),

            -- Import/export subtype records use trade_case_id as their parent key.
            ('export_cargo_receipts', ARRAY['tenant_id','export_case_id']::text[],
                'export_cases', ARRAY['tenant_id','trade_case_id']::text[],
                'ON DELETE RESTRICT', ''),
            ('export_events', ARRAY['tenant_id','export_case_id']::text[],
                'export_cases', ARRAY['tenant_id','trade_case_id']::text[],
                'ON DELETE RESTRICT', ''),
            ('export_fulfillment_evidence', ARRAY['tenant_id','export_case_id']::text[],
                'export_cases', ARRAY['tenant_id','trade_case_id']::text[],
                'ON DELETE RESTRICT', ''),
            ('export_shipping_instructions', ARRAY['tenant_id','export_case_id']::text[],
                'export_cases', ARRAY['tenant_id','trade_case_id']::text[],
                'ON DELETE RESTRICT', ''),
            ('import_arrival_notices', ARRAY['tenant_id','import_case_id']::text[],
                'import_cases', ARRAY['tenant_id','trade_case_id']::text[],
                'ON DELETE RESTRICT', ''),
            ('import_events', ARRAY['tenant_id','import_case_id']::text[],
                'import_cases', ARRAY['tenant_id','trade_case_id']::text[],
                'ON DELETE RESTRICT', ''),
            ('import_release_orders', ARRAY['tenant_id','import_case_id']::text[],
                'import_cases', ARRAY['tenant_id','trade_case_id']::text[],
                'ON DELETE RESTRICT', ''),

            -- Invoice allocation must not combine a tenant-local invoice with a line
            -- selected only by the globally unique line id.
            ('invoice_line_charges',
                ARRAY['tenant_id','invoice_id','invoice_line_id']::text[],
                'invoice_lines', ARRAY['tenant_id','invoice_id','id']::text[],
                'ON DELETE RESTRICT', '')
          ) AS mapping(
              child_table, child_columns, parent_table, parent_columns,
              delete_clause, deferrable_clause
          )
    LOOP
        IF cardinality(relation.child_columns) <> cardinality(relation.parent_columns) THEN
            RAISE EXCEPTION 'Invalid same-tenant FK mapping for ewms.%', relation.child_table;
        END IF;

        SELECT string_agg(format('%I', child_column), ', ' ORDER BY position_no),
               string_agg(format('%I', parent_column), ', ' ORDER BY position_no),
               string_agg(
                   format('parent_row.%I = child_row.%I', parent_column, child_column),
                   ' AND ' ORDER BY position_no
               ),
               string_agg(
                   format('child_row.%I IS NOT NULL', child_column),
                   ' AND ' ORDER BY position_no
               )
          INTO child_column_list, parent_column_list, join_predicate,
               child_not_null_predicate
          FROM unnest(relation.child_columns, relation.parent_columns)
               WITH ORDINALITY AS columns(child_column, parent_column, position_no);

        -- A stable hash keeps identifiers under PostgreSQL's 63-byte limit while the
        -- catalog definition remains fully inspectable.
        constraint_name := 'fk_ewms_stf_' || substr(
            md5(
                relation.child_table || ':' || array_to_string(relation.child_columns, ',')
                || '->' || relation.parent_table || ':'
                || array_to_string(relation.parent_columns, ',')
            ),
            1,
            16
        );
        index_name := 'ix_ewms_stf_' || substr(
            md5(relation.child_table || ':' || array_to_string(relation.child_columns, ',')),
            1,
            16
        );

        -- MATCH SIMPLE semantics: only rows with every child key present participate.
        EXECUTE format(
            'SELECT EXISTS ('
            'SELECT 1 FROM ewms.%I child_row '
            'LEFT JOIN ewms.%I parent_row ON %s '
            'WHERE %s AND parent_row.%I IS NULL'
            ')',
            relation.child_table,
            relation.parent_table,
            join_predicate,
            child_not_null_predicate,
            relation.parent_columns[1]
        ) INTO has_mismatch;

        IF has_mismatch THEN
            RAISE EXCEPTION
                'Existing cross-tenant or orphan reference blocks %.% -> ewms.%',
                'ewms', relation.child_table, relation.parent_table
                USING ERRCODE = '23514';
        END IF;

        SELECT constraint_row.oid,
               constraint_row.contype,
               constraint_row.confrelid,
               ARRAY(
                   SELECT attribute_row.attname::text
                     FROM unnest(constraint_row.conkey) WITH ORDINALITY
                          AS key_row(attnum, position_no)
                     JOIN pg_attribute attribute_row
                       ON attribute_row.attrelid = constraint_row.conrelid
                      AND attribute_row.attnum = key_row.attnum
                    ORDER BY key_row.position_no
               ) AS actual_child_columns,
               ARRAY(
                   SELECT attribute_row.attname::text
                     FROM unnest(constraint_row.confkey) WITH ORDINALITY
                          AS key_row(attnum, position_no)
                     JOIN pg_attribute attribute_row
                       ON attribute_row.attrelid = constraint_row.confrelid
                      AND attribute_row.attnum = key_row.attnum
                    ORDER BY key_row.position_no
               ) AS actual_parent_columns
          INTO existing_constraint
          FROM pg_constraint constraint_row
         WHERE constraint_row.conrelid = format('ewms.%I', relation.child_table)::regclass
           AND constraint_row.conname = constraint_name;

        IF FOUND THEN
            IF existing_constraint.contype <> 'f'
               OR existing_constraint.confrelid
                    <> format('ewms.%I', relation.parent_table)::regclass
               OR existing_constraint.actual_child_columns
                    IS DISTINCT FROM relation.child_columns
               OR existing_constraint.actual_parent_columns
                    IS DISTINCT FROM relation.parent_columns THEN
                RAISE EXCEPTION 'Constraint name collision for ewms.%.%',
                    relation.child_table, constraint_name;
            END IF;
        ELSE
            EXECUTE format(
                'ALTER TABLE ewms.%I ADD CONSTRAINT %I '
                'FOREIGN KEY (%s) REFERENCES ewms.%I (%s) %s %s NOT VALID',
                relation.child_table,
                constraint_name,
                child_column_list,
                relation.parent_table,
                parent_column_list,
                relation.delete_clause,
                relation.deferrable_clause
            );
        END IF;

        -- VALIDATE takes the appropriate PostgreSQL locks and rechecks any row that
        -- could have raced the explicit preflight.  A failure aborts the migration.
        EXECUTE format(
            'ALTER TABLE ewms.%I VALIDATE CONSTRAINT %I',
            relation.child_table,
            constraint_name
        );

        -- Every new referencing key receives a non-partial leading-column index for
        -- parent delete/update checks and catalog-index audit coverage.
        EXECUTE format(
            'CREATE INDEX IF NOT EXISTS %I ON ewms.%I (%s)',
            index_name,
            relation.child_table,
            child_column_list
        );
    END LOOP;
END;
$migration$;

COMMENT ON INDEX ewms.ux_ewms_bonded_item_tenant_owner_cargo_id IS
    'Candidate key for exact same-tenant and owner bonded cargo-item references.';
COMMENT ON INDEX ewms.ux_ewms_bonded_report_version_tenant_report_id IS
    'Candidate key for exact same-tenant bonded report current-version references.';
COMMENT ON INDEX ewms.ux_ewms_customs_line_tenant_owner_version_id IS
    'Candidate key for exact same-tenant and owner declaration line/version references.';
COMMENT ON INDEX ewms.ux_ewms_customs_version_tenant_declaration_id IS
    'Candidate key for exact same-tenant customs declaration-version references.';
COMMENT ON INDEX ewms.ux_ewms_invoice_line_tenant_invoice_id IS
    'Candidate key for exact same-tenant invoice line references.';
