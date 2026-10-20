BEGIN;

DO $test_warehouse_transfer$
DECLARE
    v_suffix text := upper(replace(gen_random_uuid()::text, '-', ''));
    v_category_id uuid;
    v_product_id uuid;
    v_source_warehouse_id uuid;
    v_destination_warehouse_id uuid;

    v_source_after integer;
    v_destination_after integer;

    v_out_movement record;
    v_in_movement record;

    v_failed boolean;
BEGIN
    -- 1. Setup Test Category
    INSERT INTO inventory.categories (
        id,
        name,
        created_by,
        updated_by
    )
    VALUES (
        gen_random_uuid(),
        'TEST-CAT-' || substring(v_suffix from 1 for 8),
        NULL,
        NULL
    )
    RETURNING id INTO v_category_id;

    -- 2. Setup Test Product
    INSERT INTO inventory.products (
        id,
        category_id,
        sku,
        name,
        description,
        base_price,
        cost_price,
        currency,
        attributes,
        is_active,
        created_by,
        updated_by
    )
    VALUES (
        gen_random_uuid(),
        v_category_id,
        'SKU-TRF-' || substring(v_suffix from 1 for 8),
        'Warehouse Transfer Test Product',
        'Integration test product for warehouse transfer',
        100,
        50,
        'IRR',
        '{}'::jsonb,
        true,
        NULL,
        NULL
    )
    RETURNING id INTO v_product_id;

    -- 3. Setup Source Warehouse
    INSERT INTO inventory.warehouses (
        id,
        code,
        name,
        is_active,
        created_by,
        updated_by
    )
    VALUES (
        gen_random_uuid(),
        'WH-SRC-' || substring(v_suffix from 1 for 6),
        'Source Warehouse',
        true,
        NULL,
        NULL
    )
    RETURNING id INTO v_source_warehouse_id;

    -- 4. Setup Destination Warehouse
    INSERT INTO inventory.warehouses (
        id,
        code,
        name,
        is_active,
        created_by,
        updated_by
    )
    VALUES (
        gen_random_uuid(),
        'WH-DST-' || substring(v_suffix from 1 for 6),
        'Destination Warehouse',
        true,
        NULL,
        NULL
    )
    RETURNING id INTO v_destination_warehouse_id;

    -- 5. Setup Initial Stock Level in Source Warehouse (Total: 20, Reserved: 5, Available: 15)
    INSERT INTO inventory.stock_levels (
        id,
        product_id,
        warehouse_id,
        quantity,
        reserved_quantity,
        reorder_point,
        reorder_quantity,
        updated_by
    )
    VALUES (
        gen_random_uuid(),
        v_product_id,
        v_source_warehouse_id,
        20,
        5,
        10,
        50,
        NULL
    );

    -- 6. Test Successful Transfer of 10 items
    CALL inventory.transfer_stock(
        v_source_warehouse_id,
        v_destination_warehouse_id,
        v_product_id,
        10,
        NULL::uuid,
        'successful transfer test'::text
    );

    -- 7. Assertions on Stock Levels
    SELECT quantity
    INTO v_source_after
    FROM inventory.stock_levels
    WHERE product_id = v_product_id
      AND warehouse_id = v_source_warehouse_id;

    IF v_source_after <> 10 THEN
        RAISE EXCEPTION 'Expected source quantity to be 10, got %', v_source_after;
    END IF;

    SELECT quantity
    INTO v_destination_after
    FROM inventory.stock_levels
    WHERE product_id = v_product_id
      AND warehouse_id = v_destination_warehouse_id;

    IF v_destination_after <> 10 THEN
        RAISE EXCEPTION 'Expected destination quantity to be 10, got %', v_destination_after;
    END IF;

    -- 8. Assertions on Stock Movements (TRANSFER_OUT)
    SELECT *
    INTO v_out_movement
    FROM inventory.stock_movements
    WHERE product_id = v_product_id
      AND warehouse_id = v_source_warehouse_id
      AND movement_type = 'TRANSFER_OUT'
    ORDER BY created_at DESC, id DESC
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'TRANSFER_OUT movement record was not created.';
    END IF;

    IF v_out_movement.quantity_delta <> -10 THEN
        RAISE EXCEPTION 'Expected TRANSFER_OUT quantity_delta = -10, got %', v_out_movement.quantity_delta;
    END IF;

    IF v_out_movement.quantity_before <> 20 OR v_out_movement.quantity_after <> 10 THEN
        RAISE EXCEPTION
            'Unexpected TRANSFER_OUT quantities. Before: %, After: %',
            v_out_movement.quantity_before,
            v_out_movement.quantity_after;
    END IF;

    -- 9. Assertions on Stock Movements (TRANSFER_IN)
    SELECT *
    INTO v_in_movement
    FROM inventory.stock_movements
    WHERE product_id = v_product_id
      AND warehouse_id = v_destination_warehouse_id
      AND movement_type = 'TRANSFER_IN'
    ORDER BY created_at DESC, id DESC
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'TRANSFER_IN movement record was not created.';
    END IF;

    IF v_in_movement.quantity_delta <> 10 THEN
        RAISE EXCEPTION 'Expected TRANSFER_IN quantity_delta = 10, got %', v_in_movement.quantity_delta;
    END IF;

    IF v_in_movement.quantity_before <> 0 OR v_in_movement.quantity_after <> 10 THEN
        RAISE EXCEPTION
            'Unexpected TRANSFER_IN quantities. Before: %, After: %',
            v_in_movement.quantity_before,
            v_in_movement.quantity_after;
    END IF;

    -- 10. Negative Test: Insufficient Available Quantity (Remaining available is 10 - 5 = 5, trying to transfer 10)
    v_failed := false;
    BEGIN
        CALL inventory.transfer_stock(
            v_source_warehouse_id,
            v_destination_warehouse_id,
            v_product_id,
            10,
            NULL::uuid,
            'should fail due to insufficient available stock'::text
        );
    EXCEPTION
        WHEN OTHERS THEN
            v_failed := true;
    END;

    IF NOT v_failed THEN
        RAISE EXCEPTION 'Expected insufficient stock transfer to fail, but it succeeded.';
    END IF;

    -- 11. Negative Test: Same Warehouse Transfer
    v_failed := false;
    BEGIN
        CALL inventory.transfer_stock(
            v_source_warehouse_id,
            v_source_warehouse_id,
            v_product_id,
            1,
            NULL::uuid,
            'should fail due to same source and destination'::text
        );
    EXCEPTION
        WHEN OTHERS THEN
            v_failed := true;
    END;

    IF NOT v_failed THEN
        RAISE EXCEPTION 'Expected same-warehouse transfer to fail, but it succeeded.';
    END IF;

    -- 12. Negative Test: Zero or Negative Quantity
    v_failed := false;
    BEGIN
        CALL inventory.transfer_stock(
            v_source_warehouse_id,
            v_destination_warehouse_id,
            v_product_id,
            0,
            NULL::uuid,
            'should fail due to zero quantity'::text
        );
    EXCEPTION
        WHEN OTHERS THEN
            v_failed := true;
    END;

    IF NOT v_failed THEN
        RAISE EXCEPTION 'Expected zero-quantity transfer to fail, but it succeeded.';
    END IF;

    RAISE NOTICE 'SUCCESS: All warehouse transfer precision and boundary tests passed.';
END;
$test_warehouse_transfer$;

ROLLBACK;
