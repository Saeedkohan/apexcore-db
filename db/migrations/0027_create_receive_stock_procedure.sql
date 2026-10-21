-- Migration 0027: Create inventory.receive_stock procedure
-- Description: Adds stock to a warehouse from a purchase receipt and logs movement.

DROP PROCEDURE IF EXISTS inventory.receive_stock(uuid, uuid, numeric, uuid, text);

CREATE OR REPLACE PROCEDURE inventory.receive_stock(
    p_warehouse_id UUID,
    p_product_id UUID,
    p_quantity NUMERIC,
    p_reference_id UUID DEFAULT NULL,
    p_notes TEXT DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_quantity INTEGER;
BEGIN
    -- 1. Validate inputs
    IF p_quantity IS NULL OR p_quantity <= 0 OR p_quantity <> trunc(p_quantity) THEN
        RAISE EXCEPTION 'Receive quantity must be a positive whole number. Received: %', p_quantity
            USING ERRCODE = '22023';
    END IF;

    IF p_quantity > 2147483647 THEN
        RAISE EXCEPTION 'Receive quantity exceeds the supported integer range.'
            USING ERRCODE = '22003';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM inventory.warehouses WHERE id = p_warehouse_id) THEN
        RAISE EXCEPTION 'Warehouse with ID % does not exist.', p_warehouse_id
            USING ERRCODE = '23503';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM inventory.products WHERE id = p_product_id) THEN
        RAISE EXCEPTION 'Product with ID % does not exist.', p_product_id
            USING ERRCODE = '23503';
    END IF;

    v_quantity := p_quantity::INTEGER;

    -- 2. Upsert stock levels (omitting all generated, identity, or computed columns)
    INSERT INTO inventory.stock_levels (
        warehouse_id,
        product_id,
        quantity,
        reserved_quantity,
        created_at,
        updated_at
    )
    VALUES (
        p_warehouse_id,
        p_product_id,
        v_quantity,
        0,
        clock_timestamp(),
        clock_timestamp()
    )
    ON CONFLICT (warehouse_id, product_id)
    DO UPDATE SET
        quantity = inventory.stock_levels.quantity + EXCLUDED.quantity,
        updated_at = clock_timestamp();

    -- 3. Log movement (omitting generated/identity columns)
    INSERT INTO inventory.stock_movements (
        warehouse_id,
        product_id,
        movement_type,
        quantity_delta,
        reference_id,
        notes,
        created_at
    )
    VALUES (
        p_warehouse_id,
        p_product_id,
        'PURCHASE_RECEIPT',
        v_quantity,
        p_reference_id,
        p_notes,
        clock_timestamp()
    );

END;
$$;
