BEGIN;

CREATE TYPE orders.order_item_input AS
(
    product_id   UUID,
    warehouse_id UUID,
    quantity     INTEGER,
    unit_price   NUMERIC(12, 4)
);

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
        RAISE EXCEPTION 'Order must contain at least one item'
            USING ERRCODE = '22000';
    END IF;


    p_order_id := COALESCE(p_order_id, gen_random_uuid());

    INSERT INTO orders.orders (id, order_number, customer_id, status, total_amount,
                               shipping_address, notes, created_at, updated_at)
    VALUES (p_order_id, p_order_number, p_customer_id, 'PENDING', 0.0000,
            p_shipping_address, p_notes, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);

    FOREACH v_item IN ARRAY p_items
        LOOP
            IF v_item.quantity <= 0 THEN
                RAISE EXCEPTION 'Quantity for product % must be greater than zero', v_item.product_id
                    USING ERRCODE = '22003';
            END IF;

            IF v_item.unit_price < 0 THEN
                RAISE EXCEPTION 'Unit price for product % cannot be negative', v_item.product_id
                    USING ERRCODE = '22003';
            END IF;

            INSERT INTO orders.order_items (order_id, product_id, quantity, unit_price)
            VALUES (p_order_id, v_item.product_id, v_item.quantity, v_item.unit_price);

            CALL inventory.record_stock_movement(
                    p_product_id := v_item.product_id,
                    p_warehouse_id := v_item.warehouse_id,
                    p_movement_type := 'RESERVATION',
                    p_quantity_delta := v_item.quantity,
                    p_reference_type := 'ORDER',
                    p_reference_id := p_order_id,
                    p_notes := 'Reserved for order ' || p_order_number,
                    p_actor_id := p_customer_id
                 );

            v_total_amount := v_total_amount + (v_item.quantity * v_item.unit_price);
        END LOOP;

    UPDATE orders.orders
    SET total_amount = v_total_amount,
        updated_at   = CURRENT_TIMESTAMP
    WHERE id = p_order_id;

END;
$$;


INSERT INTO core.schema_migrations (version, name)
VALUES ('0014', 'create place_order atomic procedure');

COMMIT;

SELECT * FROM core.schema_migrations ORDER BY applied_at DESC LIMIT 5;


