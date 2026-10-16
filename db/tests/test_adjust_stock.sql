BEGIN;

DO $$
DECLARE
    v_product_id        uuid;
    v_warehouse_id      uuid;
    v_actor_id          uuid;
    v_qty_before        integer;
    v_qty_after         integer;
    v_reserved_before   integer;
    v_reserved_after    integer;
    v_last_movement_id  bigint;
    v_err               text;
BEGIN
    SELECT p.id, sl.warehouse_id
    INTO v_product_id, v_warehouse_id
    FROM inventory.products p
    JOIN inventory.stock_levels sl ON sl.product_id = p.id
    JOIN inventory.warehouses w ON w.id = sl.warehouse_id
    WHERE p.is_active = true
      AND w.is_active = true
    LIMIT 1;

    IF v_product_id IS NULL THEN
        RAISE EXCEPTION 'test_adjust_stock: no active product with stock_level found';
    END IF;

    SELECT id
    INTO v_actor_id
    FROM core.users
    LIMIT 1;

    IF v_actor_id IS NULL THEN
        v_actor_id := gen_random_uuid();
    END IF;

    SELECT quantity, reserved_quantity
    INTO v_qty_before, v_reserved_before
    FROM inventory.stock_levels
    WHERE product_id = v_product_id
      AND warehouse_id = v_warehouse_id;

    BEGIN
        CALL inventory.adjust_stock(v_product_id, v_warehouse_id, 0, 'test: zero delta', v_actor_id);
        RAISE EXCEPTION 'test_adjust_stock: expected error for zero delta but none was raised';
    EXCEPTION WHEN others THEN
        v_err := SQLERRM;
    END;

    BEGIN
        CALL inventory.adjust_stock(gen_random_uuid(), v_warehouse_id, 1, 'test: invalid product', v_actor_id);
        RAISE EXCEPTION 'test_adjust_stock: expected error for invalid product but none was raised';
    EXCEPTION WHEN others THEN
        v_err := SQLERRM;
    END;

    BEGIN
        CALL inventory.adjust_stock(v_product_id, gen_random_uuid(), 1, 'test: invalid warehouse', v_actor_id);
        RAISE EXCEPTION 'test_adjust_stock: expected error for invalid warehouse but none was raised';
    EXCEPTION WHEN others THEN
        v_err := SQLERRM;
    END;

    BEGIN
        CALL inventory.adjust_stock(v_product_id, v_warehouse_id, -(v_qty_before + 1), 'test: negative resulting quantity', v_actor_id);
        RAISE EXCEPTION 'test_adjust_stock: expected error for negative resulting quantity but none was raised';
    EXCEPTION WHEN others THEN
        v_err := SQLERRM;
    END;

    IF v_qty_before >= v_reserved_before THEN
        BEGIN
            CALL inventory.adjust_stock(
                v_product_id,
                v_warehouse_id,
                -( (v_qty_before - v_reserved_before) + 1 ),
                'test: would go below reserved',
                v_actor_id
            );
            RAISE EXCEPTION 'test_adjust_stock: expected error for below-reserved guard but none was raised';
        EXCEPTION WHEN others THEN
            v_err := SQLERRM;
        END;
    END IF;

    CALL inventory.adjust_stock(v_product_id, v_warehouse_id, 5, 'test: positive adjustment +5', v_actor_id);

    SELECT quantity, reserved_quantity
    INTO v_qty_after, v_reserved_after
    FROM inventory.stock_levels
    WHERE product_id = v_product_id
      AND warehouse_id = v_warehouse_id;

    IF v_qty_after <> v_qty_before + 5 THEN
        RAISE EXCEPTION 'test_adjust_stock: expected quantity % but got %', (v_qty_before + 5), v_qty_after;
    END IF;

    IF v_reserved_after <> v_reserved_before THEN
        RAISE EXCEPTION 'test_adjust_stock: reserved quantity changed unexpectedly';
    END IF;

    SELECT id
    INTO v_last_movement_id
    FROM inventory.stock_movements
    WHERE product_id = v_product_id
      AND warehouse_id = v_warehouse_id
      AND movement_type = 'STOCK_ADJUSTMENT'::inventory.movement_type
    ORDER BY id DESC
    LIMIT 1;

    IF v_last_movement_id IS NULL THEN
        RAISE EXCEPTION 'test_adjust_stock: expected movement row not found after +5';
    END IF;

    PERFORM 1
    FROM inventory.stock_movements
    WHERE id = v_last_movement_id
      AND quantity_delta = 5
      AND quantity_before = v_qty_before
      AND quantity_after = v_qty_before + 5;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'test_adjust_stock: movement row fields mismatch after +5';
    END IF;

    v_qty_before := v_qty_after;
    v_reserved_before := v_reserved_after;

    CALL inventory.adjust_stock(v_product_id, v_warehouse_id, -2, 'test: negative adjustment -2', v_actor_id);

    SELECT quantity, reserved_quantity
    INTO v_qty_after, v_reserved_after
    FROM inventory.stock_levels
    WHERE product_id = v_product_id
      AND warehouse_id = v_warehouse_id;

    IF v_qty_after <> v_qty_before - 2 THEN
        RAISE EXCEPTION 'test_adjust_stock: expected quantity % but got %', (v_qty_before - 2), v_qty_after;
    END IF;

    IF v_reserved_after <> v_reserved_before THEN
        RAISE EXCEPTION 'test_adjust_stock: reserved quantity changed unexpectedly on -2';
    END IF;

    SELECT id
    INTO v_last_movement_id
    FROM inventory.stock_movements
    WHERE product_id = v_product_id
      AND warehouse_id = v_warehouse_id
      AND movement_type = 'STOCK_ADJUSTMENT'::inventory.movement_type
    ORDER BY id DESC
    LIMIT 1;

    IF v_last_movement_id IS NULL THEN
        RAISE EXCEPTION 'test_adjust_stock: expected movement row not found after -2';
    END IF;

    PERFORM 1
    FROM inventory.stock_movements
    WHERE id = v_last_movement_id
      AND quantity_delta = -2
      AND quantity_before = v_qty_before
      AND quantity_after = v_qty_before - 2;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'test_adjust_stock: movement row fields mismatch after -2';
    END IF;
END
$$;

ROLLBACK;
