BEGIN;

DO $$
DECLARE
    v_product_id        uuid;
    v_from_warehouse    uuid;
    v_to_warehouse      uuid;
    v_actor_id          uuid;
    v_from_qty_before   integer;
    v_to_qty_before     integer;
    v_from_qty_after    integer;
    v_to_qty_after      integer;
    v_err               text;
BEGIN
    SELECT id INTO v_actor_id FROM core.users LIMIT 1;
    IF v_actor_id IS NULL THEN
        v_actor_id := gen_random_uuid();
    END IF;

    SELECT p.id, sl.warehouse_id, sl.quantity
    INTO v_product_id, v_from_warehouse, v_from_qty_before
    FROM inventory.products p
    JOIN inventory.stock_levels sl ON sl.product_id = p.id
    WHERE p.is_active = true
      AND sl.quantity > 5
    LIMIT 1;

    IF v_product_id IS NULL THEN
        RAISE EXCEPTION 'test_transfer_stock: no suitable product with stock found';
    END IF;

    SELECT id
    INTO v_to_warehouse
    FROM inventory.warehouses
    WHERE id <> v_from_warehouse
      AND is_active = true
    LIMIT 1;

    IF v_to_warehouse IS NULL THEN
        v_to_warehouse := gen_random_uuid();
        INSERT INTO inventory.warehouses (id, code, name, is_active, created_by)
        VALUES (v_to_warehouse, 'WH-TEST-TEMP', 'Temporary Test Warehouse', true, v_actor_id);
    END IF;

    SELECT COALESCE(quantity, 0)
    INTO v_to_qty_before
    FROM inventory.stock_levels
    WHERE product_id = v_product_id
      AND warehouse_id = v_to_warehouse;

    IF v_to_qty_before IS NULL THEN
        v_to_qty_before := 0;
    END IF;

    BEGIN
        CALL inventory.transfer_stock(v_product_id, v_from_warehouse, v_to_warehouse, 0, 'test: zero qty', v_actor_id);
        RAISE EXCEPTION 'test_transfer_stock: expected error for zero quantity but none raised';
    EXCEPTION WHEN others THEN
        v_err := SQLERRM;
    END;

    BEGIN
        CALL inventory.transfer_stock(v_product_id, v_from_warehouse, v_from_warehouse, 2, 'test: same warehouse', v_actor_id);
        RAISE EXCEPTION 'test_transfer_stock: expected error for same warehouse but none was raised';
    EXCEPTION WHEN others THEN
        v_err := SQLERRM;
    END;

    BEGIN
        CALL inventory.transfer_stock(v_product_id, v_from_warehouse, v_to_warehouse, v_from_qty_before + 100, 'test: excessive qty', v_actor_id);
        RAISE EXCEPTION 'test_transfer_stock: expected error for excessive quantity but none was raised';
    EXCEPTION WHEN others THEN
        v_err := SQLERRM;
    END;

    CALL inventory.transfer_stock(v_product_id, v_from_warehouse, v_to_warehouse, 2, 'test: successful transfer', v_actor_id);

    SELECT quantity INTO v_from_qty_after
    FROM inventory.stock_levels
    WHERE product_id = v_product_id AND warehouse_id = v_from_warehouse;

    SELECT quantity INTO v_to_qty_after
    FROM inventory.stock_levels
    WHERE product_id = v_product_id AND warehouse_id = v_to_warehouse;

    IF v_from_qty_after <> v_from_qty_before - 2 THEN
        RAISE EXCEPTION 'test_transfer_stock: source quantity mismatch, expected % got %', (v_from_qty_before - 2), v_from_qty_after;
    END IF;

    IF v_to_qty_after <> v_to_qty_before + 2 THEN
        RAISE EXCEPTION 'test_transfer_stock: destination quantity mismatch, expected % got %', (v_to_qty_before + 2), v_to_qty_after;
    END IF;
END;
$$;

ROLLBACK;
