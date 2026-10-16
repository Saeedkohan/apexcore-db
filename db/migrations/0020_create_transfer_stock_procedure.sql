DROP PROCEDURE IF EXISTS inventory.transfer_stock(uuid, uuid, uuid, integer, text, uuid);

CREATE OR REPLACE PROCEDURE inventory.transfer_stock(
    IN p_product_id uuid,
    IN p_from_warehouse_id uuid,
    IN p_to_warehouse_id uuid,
    IN p_quantity integer,
    IN p_notes text DEFAULT NULL,
    IN p_actor_id uuid DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_from_available integer;
    v_to_level_id    uuid;
BEGIN
    IF p_quantity IS NULL OR p_quantity <= 0 THEN
        RAISE EXCEPTION 'transfer_stock: quantity must be greater than zero';
    END IF;

    IF p_from_warehouse_id = p_to_warehouse_id THEN
        RAISE EXCEPTION 'transfer_stock: source and destination warehouses cannot be the same';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM inventory.products WHERE id = p_product_id AND is_active = true) THEN
        RAISE EXCEPTION 'transfer_stock: product % does not exist or is inactive', p_product_id;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM inventory.warehouses WHERE id = p_from_warehouse_id AND is_active = true) THEN
        RAISE EXCEPTION 'transfer_stock: source warehouse % does not exist or is inactive', p_from_warehouse_id;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM inventory.warehouses WHERE id = p_to_warehouse_id AND is_active = true) THEN
        RAISE EXCEPTION 'transfer_stock: destination warehouse % does not exist or is inactive', p_to_warehouse_id;
    END IF;

    SELECT available_quantity
    INTO v_from_available
    FROM inventory.stock_levels
    WHERE product_id = p_product_id
      AND warehouse_id = p_from_warehouse_id
    FOR UPDATE;

    IF v_from_available IS NULL THEN
        RAISE EXCEPTION 'transfer_stock: stock level record not found for product % in source warehouse %', p_product_id, p_from_warehouse_id;
    END IF;

    IF v_from_available < p_quantity THEN
        RAISE EXCEPTION 'transfer_stock: insufficient available stock in source warehouse (available: %, requested: %)', v_from_available, p_quantity;
    END IF;

    SELECT id INTO v_to_level_id
    FROM inventory.stock_levels
    WHERE product_id = p_product_id
      AND warehouse_id = p_to_warehouse_id
    FOR UPDATE;

    IF v_to_level_id IS NULL THEN
        INSERT INTO inventory.stock_levels (
            id,
            product_id,
            warehouse_id,
            quantity,
            reserved_quantity
        ) VALUES (
            gen_random_uuid(),
            p_product_id,
            p_to_warehouse_id,
            0,
            0
        );
    END IF;

    CALL inventory.record_stock_movement(
        p_product_id,
        p_from_warehouse_id,
        'TRANSFER_OUT'::inventory.movement_type,
        -p_quantity,
        'WAREHOUSE_TRANSFER',
        p_to_warehouse_id,
        p_notes,
        p_actor_id
    );

    CALL inventory.record_stock_movement(
        p_product_id,
        p_to_warehouse_id,
        'TRANSFER_IN'::inventory.movement_type,
        p_quantity,
        'WAREHOUSE_TRANSFER',
        p_from_warehouse_id,
        p_notes,
        p_actor_id
    );
END;
$$;
