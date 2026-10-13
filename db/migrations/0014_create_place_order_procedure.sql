BEGIN;

CREATE OR REPLACE PROCEDURE orders.place_order(
    IN p_customer_id UUID,
    IN p_order_number VARCHAR(32),
    IN p_shipping_address JSONB,
    IN p_items orders.order_item_input[],
    IN p_notes TEXT,
    INOUT p_order_id UUID
)
    LANGUAGE plpgsql
AS
$$
DECLARE
    v_item         orders.order_item_input;
    v_total_amount NUMERIC(12, 4) := 0.0000;
BEGIN
    IF p_items IS NULL OR array_length(p_items, 1) IS NULL THEN
        RAISE EXCEPTION 'place_order: order items array cannot be empty';
    END IF;

    IF p_order_id IS NULL THEN
        p_order_id := gen_random_uuid();
    END IF;

    -- Calculate total amount for the order
    FOREACH v_item IN ARRAY p_items
    LOOP
        v_total_amount := v_total_amount + (v_item.quantity * v_item.unit_price);
    END LOOP;

    -- Insert into orders
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
    )
    VALUES (
        p_order_id,
        p_order_number,
        p_customer_id,
        'PENDING',
        v_total_amount,
        'USD',
        p_shipping_address,
        p_notes,
        CLOCK_TIMESTAMP(),
        CLOCK_TIMESTAMP()
    );

    -- Insert order items and reserve stock
    FOREACH v_item IN ARRAY p_items
    LOOP
        -- Note: total_price is omitted here so the database handles it safely without generated-column conflicts
        INSERT INTO orders.order_items (
            id,
            order_id,
            product_id,
            quantity,
            unit_price,
            created_at
        )
        VALUES (
            gen_random_uuid(),
            p_order_id,
            v_item.product_id,
            v_item.quantity,
            v_item.unit_price,
            CLOCK_TIMESTAMP()
        );

        -- Call stock movement procedure to reserve stock
        CALL inventory.record_stock_movement(
            p_product_id     => v_item.product_id,
            p_warehouse_id   => v_item.warehouse_id,
            p_movement_type  => 'RESERVATION'::inventory.movement_type,
            p_quantity_delta => v_item.quantity,
            p_reference_type => 'ORDER',
            p_reference_id   => p_order_id,
            p_notes          => 'Order placement reservation',
            p_actor_id       => p_customer_id
        );
    END LOOP;
END;
$$;

INSERT INTO core.schema_migrations (version, name, applied_at)
VALUES ('0014', '0014_create_place_order_procedure', CLOCK_TIMESTAMP())
ON CONFLICT (version) DO NOTHING;

COMMIT;

