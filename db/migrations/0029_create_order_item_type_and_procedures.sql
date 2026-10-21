BEGIN;

DROP PROCEDURE IF EXISTS orders.place_order(uuid, varchar, jsonb, orders.order_item_input[], text, uuid);
DROP PROCEDURE IF EXISTS orders.cancel_order(uuid, uuid, text);
DROP TYPE IF EXISTS orders.order_item_input CASCADE;

CREATE TYPE orders.order_item_input AS (
    product_id uuid,
    quantity integer
);

CREATE OR REPLACE PROCEDURE orders.place_order(
    IN p_customer_id uuid,
    IN p_order_number varchar,
    IN p_shipping_address jsonb,
    IN p_items orders.order_item_input[],
    IN p_notes text,
    INOUT p_order_id uuid
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_item orders.order_item_input;
    v_warehouse_id uuid;
    v_unit_price numeric;
    v_total_amount numeric := 0;
    v_product_id uuid;
    v_qty integer;
    v_current_qty integer;
    v_order_item_id uuid;
BEGIN
    SELECT id INTO v_warehouse_id
    FROM inventory.warehouses
    ORDER BY created_at ASC
    LIMIT 1;

    IF v_warehouse_id IS NULL THEN
        RAISE EXCEPTION 'No active warehouse found';
    END IF;

    p_order_id := gen_random_uuid();

    INSERT INTO orders.orders (
        id,
        order_number,
        customer_id,
        status,
        total_amount,
        currency,
        shipping_address,
        notes,
        created_at,
        updated_at
    ) VALUES (
        p_order_id,
        p_order_number,
        p_customer_id,
        'PENDING',
        0,
        'USD',
        p_shipping_address,
        p_notes,
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP
    );

    FOREACH v_item IN ARRAY p_items
    LOOP
        v_product_id := v_item.product_id;
        v_qty := v_item.quantity;

        SELECT base_price INTO v_unit_price
        FROM inventory.products
        WHERE id = v_product_id;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Product % not found', v_product_id;
        END IF;

        SELECT quantity INTO v_current_qty
        FROM inventory.stock_levels
        WHERE product_id = v_product_id AND warehouse_id = v_warehouse_id
        FOR UPDATE;

        IF v_current_qty IS NULL OR (v_current_qty - v_qty) < 0 THEN
            RAISE EXCEPTION 'Insufficient stock for product %', v_product_id;
        END IF;

        UPDATE inventory.stock_levels
        SET reserved_quantity = reserved_quantity + v_qty,
            updated_at = CURRENT_TIMESTAMP
        WHERE product_id = v_product_id AND warehouse_id = v_warehouse_id;

        v_order_item_id := gen_random_uuid();

        INSERT INTO orders.order_items (
            id,
            order_id,
            product_id,
            quantity,
            unit_price,
            created_at
        ) VALUES (
            v_order_item_id,
            p_order_id,
            v_product_id,
            v_qty,
            v_unit_price,
            CURRENT_TIMESTAMP
        );

        v_total_amount := v_total_amount + (v_qty * v_unit_price);

        INSERT INTO inventory.stock_movements (
            product_id,
            warehouse_id,
            movement_type,
            quantity_delta,
            quantity_before,
            quantity_after,
            reference_type,
            reference_id,
            notes,
            created_at
        ) VALUES (
            v_product_id,
            v_warehouse_id,
            'RESERVATION',
            v_qty,
            v_current_qty,
            v_current_qty,
            'ORDER',
            p_order_id,
            'Stock reserved for order placement',
            CURRENT_TIMESTAMP
        );
    END LOOP;

    UPDATE orders.orders
    SET total_amount = v_total_amount,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_order_id;
END;
$$;

CREATE OR REPLACE PROCEDURE orders.cancel_order(
    IN p_order_id uuid,
    IN p_actor_id uuid,
    IN p_cancellation_reason text
)
LANGUAGE plpgsql
AS $$
DECLARE
    r_item RECORD;
    v_warehouse_id uuid;
    v_current_qty integer;
    v_status orders.order_status;
BEGIN
    SELECT status INTO v_status FROM orders.orders WHERE id = p_order_id;

    IF v_status = 'CANCELLED' THEN RETURN; END IF;

    SELECT id INTO v_warehouse_id FROM inventory.warehouses ORDER BY created_at ASC LIMIT 1;

    FOR r_item IN SELECT product_id, quantity FROM orders.order_items WHERE order_id = p_order_id
    LOOP
        SELECT quantity INTO v_current_qty
        FROM inventory.stock_levels
        WHERE product_id = r_item.product_id AND warehouse_id = v_warehouse_id
        FOR UPDATE;

        UPDATE inventory.stock_levels
        SET reserved_quantity = GREATEST(0, reserved_quantity - r_item.quantity),
            updated_at = CURRENT_TIMESTAMP
        WHERE product_id = r_item.product_id AND warehouse_id = v_warehouse_id;

        INSERT INTO inventory.stock_movements (
            product_id,
            warehouse_id,
            movement_type,
            quantity_delta,
            quantity_before,
            quantity_after,
            reference_type,
            reference_id,
            notes,
            created_at,
            created_by
        ) VALUES (
            r_item.product_id,
            v_warehouse_id,
            'RELEASE',
            -r_item.quantity,
            v_current_qty,
            v_current_qty,
            'ORDER_CANCELLATION',
            p_order_id,
            COALESCE(p_cancellation_reason, 'Order cancelled'),
            CURRENT_TIMESTAMP,
            p_actor_id
        );
    END LOOP;

    UPDATE orders.orders
    SET status = 'CANCELLED',
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_order_id;
END;
$$;

COMMIT;
