DROP PROCEDURE IF EXISTS inventory.receive_stock(UUID, UUID, INTEGER, TEXT, UUID);
DROP PROCEDURE IF EXISTS inventory.receive_stock(UUID, UUID, INTEGER, UUID, TEXT, UUID);

CREATE OR REPLACE PROCEDURE inventory.receive_stock(
    IN p_product_id   UUID,
    IN p_warehouse_id UUID,
    IN p_quantity     INTEGER,
    IN p_reference_id UUID,
    IN p_notes        TEXT DEFAULT NULL,
    IN p_actor_id     UUID DEFAULT NULL
)
LANGUAGE plpgsql
AS $$


DECLARE
    v_product_active   BOOLEAN;
    v_warehouse_active BOOLEAN;
BEGIN
    IF p_quantity IS NULL OR p_quantity <= 0 THEN
        RAISE EXCEPTION 'receive_stock: quantity must be a positive integer'
            USING ERRCODE = '22003';
    END IF;

    SELECT is_active
    INTO v_product_active
    FROM inventory.products
    WHERE id = p_product_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'receive_stock: product not found: %', p_product_id
            USING ERRCODE = '02000';
    END IF;

    IF NOT v_product_active THEN
        RAISE EXCEPTION 'receive_stock: product is inactive: %', p_product_id
            USING ERRCODE = '22000';
    END IF;

    SELECT is_active
    INTO v_warehouse_active
    FROM inventory.warehouses
    WHERE id = p_warehouse_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'receive_stock: warehouse not found: %', p_warehouse_id
            USING ERRCODE = '02000';
    END IF;

    IF NOT v_warehouse_active THEN
        RAISE EXCEPTION 'receive_stock: warehouse is inactive: %', p_warehouse_id
            USING ERRCODE = '22000';
    END IF;

    INSERT INTO inventory.stock_levels (
        product_id,
        warehouse_id
    )
    VALUES (
        p_product_id,
        p_warehouse_id
    )
    ON CONFLICT (product_id, warehouse_id) DO NOTHING;

    CALL inventory.record_stock_movement(
        p_product_id     => p_product_id,
        p_warehouse_id   => p_warehouse_id,
        p_movement_type  => 'PURCHASE_RECEIPT'::inventory.movement_type,
        p_quantity_delta => p_quantity,
        p_reference_type => 'PURCHASE_ORDER',
        p_reference_id   => p_reference_id,
        p_notes          => COALESCE(p_notes, 'Stock receipt'),
        p_actor_id       => p_actor_id
    );
END;
$$;
