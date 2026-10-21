-- Integration test: inventory.receive_stock

START TRANSACTION;

DO $$
DECLARE
    v_warehouse_id UUID;
    v_product_id UUID;
    v_baseline BIGINT;
    v_expected BIGINT;
    v_qty BIGINT;
    v_moves BIGINT;
BEGIN
    -- Pick an active product and an active warehouse that already exist in the database
    SELECT id INTO v_warehouse_id
    FROM inventory.warehouses
    WHERE is_active = TRUE
    LIMIT 1;

    SELECT id INTO v_product_id
    FROM inventory.products
    WHERE is_active = TRUE
    LIMIT 1;

    IF v_warehouse_id IS NULL OR v_product_id IS NULL THEN
        RAISE EXCEPTION 'Test setup failed: No active warehouse or active product found in database.';
    END IF;

    -- Get initial stock quantity (0 if not exists yet)
    SELECT COALESCE(
        (SELECT quantity
         FROM inventory.stock_levels
         WHERE product_id = v_product_id AND warehouse_id = v_warehouse_id),
    0)::BIGINT INTO v_baseline;

    v_expected := v_baseline + 100;

    -- Call procedure with existing valid IDs
    CALL inventory.receive_stock(
        p_product_id     => v_product_id,
        p_warehouse_id   => v_warehouse_id,
        p_quantity       => 100,
        p_reference_id   => NULL,
        p_notes          => 'Integration test receipt',
        p_actor_id       => NULL
    );

    -- Verify quantity
    SELECT quantity INTO v_qty
    FROM inventory.stock_levels
    WHERE product_id = v_product_id AND warehouse_id = v_warehouse_id;

    IF v_qty IS DISTINCT FROM v_expected THEN
        RAISE EXCEPTION 'FAIL: expected quantity %, got %', v_expected, v_qty;
    END IF;

    -- Verify stock movement logged
    SELECT count(*) INTO v_moves
    FROM inventory.stock_movements
    WHERE product_id = v_product_id
      AND warehouse_id = v_warehouse_id
      AND movement_type = 'PURCHASE_RECEIPT';

    IF v_moves = 0 THEN
        RAISE EXCEPTION 'FAIL: no PURCHASE_RECEIPT movement logged';
    END IF;

    RAISE NOTICE 'SUCCESS: receive_stock added quantity and logged movement correctly';
END $$;

ROLLBACK;
