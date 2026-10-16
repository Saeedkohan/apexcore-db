BEGIN;

DO $$
DECLARE
    v_admin_id      UUID;
    v_product_id    UUID;
    v_category_id   UUID;
    v_log_record    RECORD;
    v_old_val       TEXT;
    v_new_val       TEXT;
BEGIN
    SELECT id INTO v_admin_id
    FROM core.users
    LIMIT 1;

    SELECT id INTO v_category_id
    FROM inventory.categories
    LIMIT 1;

    v_product_id := gen_random_uuid();

    INSERT INTO inventory.products (
        id,
        sku,
        name,
        description,
        base_price,
        category_id,
        created_by
    ) VALUES (
        v_product_id,
        'SKU-AUDIT-TEST-001',
        'Audit Test Product',
        'Initial Description',
        150000.00,
        v_category_id,
        v_admin_id
    );

    SELECT * INTO v_log_record
    FROM audit.audit_logs
    WHERE table_name = 'products'
      AND record_id = v_product_id::text
      AND action = 'INSERT'
    ORDER BY created_at DESC
    LIMIT 1;

    IF v_log_record.id IS NULL THEN
        RAISE EXCEPTION 'test_audit_logging: INSERT trigger failed to record audit log for product';
    END IF;

    v_new_val := jsonb_extract_path_text(v_log_record.new_data, 'name');
    IF v_new_val <> 'Audit Test Product' THEN
        RAISE EXCEPTION 'test_audit_logging: INSERT new_data payload mismatch';
    END IF;

    UPDATE inventory.products
    SET name = 'Audit Test Product Renamed'
    WHERE id = v_product_id;

    SELECT * INTO v_log_record
    FROM audit.audit_logs
    WHERE table_name = 'products'
      AND record_id = v_product_id::text
      AND action = 'UPDATE'
    ORDER BY created_at DESC
    LIMIT 1;

    IF v_log_record.id IS NULL THEN
        RAISE EXCEPTION 'test_audit_logging: UPDATE trigger failed to record audit log';
    END IF;

    v_old_val := jsonb_extract_path_text(v_log_record.old_data, 'name');
    v_new_val := jsonb_extract_path_text(v_log_record.new_data, 'name');

    IF v_old_val <> 'Audit Test Product' OR v_new_val <> 'Audit Test Product Renamed' THEN
        RAISE EXCEPTION 'test_audit_logging: UPDATE payload transition mismatch';
    END IF;

    DELETE FROM inventory.products
    WHERE id = v_product_id;

    SELECT * INTO v_log_record
    FROM audit.audit_logs
    WHERE table_name = 'products'
      AND record_id = v_product_id::text
      AND action = 'DELETE'
    ORDER BY created_at DESC
    LIMIT 1;

    IF v_log_record.id IS NULL THEN
        RAISE EXCEPTION 'test_audit_logging: DELETE trigger failed to record audit log';
    END IF;

    v_old_val := jsonb_extract_path_text(v_log_record.old_data, 'name');
    IF v_old_val <> 'Audit Test Product Renamed' OR v_log_record.new_data IS NOT NULL THEN
        RAISE EXCEPTION 'test_audit_logging: DELETE payload integrity mismatch';
    END IF;

    RAISE NOTICE 'SUCCESS: All audit logging test assertions passed cleanly.';
END;
$$;

ROLLBACK;
