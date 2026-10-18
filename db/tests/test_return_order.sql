BEGIN;

DO $$
DECLARE
    v_user_id uuid;
    v_category_id uuid;
    v_product_id uuid;
    v_warehouse_id uuid;
    v_order_id uuid;
    v_order_number varchar := 'ORD-RET-' || UPPER(SUBSTRING(gen_random_uuid()::text, 1, 8));
    v_initial_physical integer := 50;
    v_order_qty integer := 10;
    v_stock_after_dispatch integer;
    v_stock_after_return integer;
    v_order_status orders.order_status;
    v_return_movements_count integer;
    v_items orders.order_item_input[];
BEGIN
    INSERT INTO core.users (username, email, password_hash, is_active, is_admin)
    VALUES (
        'return_user_' || LOWER(SUBSTRING(gen_random_uuid()::text, 1, 8)),
        'return_' || LOWER(SUBSTRING(gen_random_uuid()::text, 1, 8)) || '@apexcore.local',
        'hash_test',
        true,
        false
    )
    RETURNING id INTO v_user_id;

    INSERT INTO inventory.categories (name, is_active)
    VALUES ('Return Cat ' || SUBSTRING(gen_random_uuid()::text, 1, 8), true)
    RETURNING id INTO v_category_id;

    INSERT INTO inventory.products (category_id, sku, name, base_price, is_active)
    VALUES (
        v_category_id,
        'SKU-RET-' || UPPER(SUBSTRING(gen_random_uuid()::text, 1, 8)),
        'Return Test Product',
        100.00,
        true
    )
    RETURNING id INTO v_product_id;

    INSERT INTO inventory.warehouses (code, name, is_active)
    VALUES (
        'WH-RET-' || UPPER(SUBSTRING(gen_random_uuid()::text, 1, 8)),
        'Return Test Warehouse',
        true
    )
    RETURNING id INTO v_warehouse_id;

    INSERT INTO inventory.stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
    VALUES (v_product_id, v_warehouse_id, v_initial_physical, 0);

    v_items := ARRAY[
        ROW(v_product_id, v_warehouse_id, v_order_qty, 100.00)::orders.order_item_input
    ];

    CALL orders.place_order(
        p_customer_id      => v_user_id,
        p_order_number     => v_order_number,
        p_shipping_address => '{"city": "Tehran", "street": "Valiasr"}'::jsonb,
        p_items            => v_items,
        p_notes            => 'Test Return Order',
        p_order_id         => v_order_id
    );

    CALL orders.ship_order(p_order_id => v_order_id, p_actor_id => v_user_id);
    CALL orders.deliver_order(p_order_id => v_order_id, p_actor_id => v_user_id);

    SELECT quantity INTO v_stock_after_dispatch
    FROM inventory.stock_levels
    WHERE product_id = v_product_id AND warehouse_id = v_warehouse_id;

    IF v_stock_after_dispatch <> (v_initial_physical - v_order_qty) THEN
        RAISE EXCEPTION 'TEST FAILED: Stock after dispatch expected %, got %',
            (v_initial_physical - v_order_qty), v_stock_after_dispatch;
    END IF;

    CALL orders.return_order(
        p_order_id      => v_order_id,
        p_actor_id      => v_user_id,
        p_return_reason => 'Defective product customer claim'
    );

    SELECT status INTO v_order_status
    FROM orders.orders
    WHERE id = v_order_id;

    IF v_order_status <> 'RETURNED' THEN
        RAISE EXCEPTION 'TEST FAILED: Order status expected RETURNED, got %', v_order_status;
    END IF;

    SELECT quantity INTO v_stock_after_return
    FROM inventory.stock_levels
    WHERE product_id = v_product_id AND warehouse_id = v_warehouse_id;

    IF v_stock_after_return <> v_initial_physical THEN
        RAISE EXCEPTION 'TEST FAILED: Stock after return expected %, got %',
            v_initial_physical, v_stock_after_return;
    END IF;

    SELECT COUNT(*) INTO v_return_movements_count
    FROM inventory.stock_movements
    WHERE reference_id = v_order_id
      AND movement_type = 'RETURN_RESTOCK';

    IF v_return_movements_count <> 1 THEN
        RAISE EXCEPTION 'TEST FAILED: Expected 1 RETURN_RESTOCK movement, got %', v_return_movements_count;
    END IF;

    RAISE NOTICE 'SUCCESS: All return_order assertions passed cleanly.';
END $$;

ROLLBACK;
