BEGIN;

DROP PROCEDURE IF EXISTS orders.ship_order(uuid, uuid);

CREATE OR REPLACE PROCEDURE orders.ship_order(
    IN p_order_id uuid,
    IN p_actor_id uuid DEFAULT NULL
)
LANGUAGE plpgsql
AS
$$
DECLARE
    v_current_status orders.order_status;
    v_item RECORD;
BEGIN
    IF p_order_id IS NULL THEN
        RAISE EXCEPTION 'ship_order: order_id cannot be null';
    END IF;

    SELECT status
    INTO v_current_status
    FROM orders.orders
    WHERE id = p_order_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'ship_order: order with id % does not exist', p_order_id;
    END IF;

    IF v_current_status NOT IN ('PENDING', 'CONFIRMED', 'PROCESSING') THEN
        RAISE EXCEPTION 'ship_order: cannot ship order with status %', v_current_status;
    END IF;

    FOR v_item IN
        SELECT
            oi.product_id,
            sm.warehouse_id,
            oi.quantity
        FROM orders.order_items oi
        JOIN inventory.stock_movements sm
          ON sm.reference_id = oi.order_id
         AND sm.product_id = oi.product_id
         AND sm.movement_type = 'RESERVATION'
        WHERE oi.order_id = p_order_id
    LOOP
        CALL inventory.record_stock_movement(
            p_product_id     => v_item.product_id,
            p_warehouse_id   => v_item.warehouse_id,
            p_movement_type  => 'RELEASE'::inventory.movement_type,
            p_quantity_delta => -(v_item.quantity),
            p_reference_type => 'ORDER_SHIPMENT',
            p_reference_id   => p_order_id,
            p_notes          => 'Release reservation for shipment',
            p_actor_id       => p_actor_id
        );

        CALL inventory.record_stock_movement(
            p_product_id     => v_item.product_id,
            p_warehouse_id   => v_item.warehouse_id,
            p_movement_type  => 'SALE_DISPATCH'::inventory.movement_type,
            p_quantity_delta => -(v_item.quantity),
            p_reference_type => 'ORDER_SHIPMENT',
            p_reference_id   => p_order_id,
            p_notes          => 'Physical deduction for shipment',
            p_actor_id       => p_actor_id
        );
    END LOOP;

    UPDATE orders.orders
    SET status     = 'SHIPPED',
        updated_at = CLOCK_TIMESTAMP()
    WHERE id = p_order_id;

    RETURN;
END;
$$;

INSERT INTO core.schema_migrations (version, name, applied_at)
VALUES ('0016', '0016_create_ship_order_procedure', CLOCK_TIMESTAMP())
ON CONFLICT (version) DO NOTHING;

COMMIT;
BEGIN;

DROP PROCEDURE IF EXISTS orders.ship_order(uuid, uuid);

CREATE OR REPLACE PROCEDURE orders.ship_order(
    IN p_order_id uuid,
    IN p_actor_id uuid DEFAULT NULL
)
LANGUAGE plpgsql
AS
$$
DECLARE
    v_current_status orders.order_status;
    v_item RECORD;
BEGIN
    IF p_order_id IS NULL THEN
        RAISE EXCEPTION 'ship_order: order_id cannot be null';
    END IF;

    SELECT status
    INTO v_current_status
    FROM orders.orders
    WHERE id = p_order_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'ship_order: order with id % does not exist', p_order_id;
    END IF;

    IF v_current_status NOT IN ('PENDING', 'CONFIRMED', 'PROCESSING') THEN
        RAISE EXCEPTION 'ship_order: cannot ship order with status %', v_current_status;
    END IF;

    FOR v_item IN
        SELECT
            oi.product_id,
            sm.warehouse_id,
            oi.quantity
        FROM orders.order_items oi
        JOIN inventory.stock_movements sm
          ON sm.reference_id = oi.order_id
         AND sm.product_id = oi.product_id
         AND sm.movement_type = 'RESERVATION'
        WHERE oi.order_id = p_order_id
    LOOP
        CALL inventory.record_stock_movement(
            p_product_id     => v_item.product_id,
            p_warehouse_id   => v_item.warehouse_id,
            p_movement_type  => 'RELEASE'::inventory.movement_type,
            p_quantity_delta => -(v_item.quantity),
            p_reference_type => 'ORDER_SHIPMENT',
            p_reference_id   => p_order_id,
            p_notes          => 'Release reservation for shipment',
            p_actor_id       => p_actor_id
        );

        CALL inventory.record_stock_movement(
            p_product_id     => v_item.product_id,
            p_warehouse_id   => v_item.warehouse_id,
            p_movement_type  => 'SALE_DISPATCH'::inventory.movement_type,
            p_quantity_delta => -(v_item.quantity),
            p_reference_type => 'ORDER_SHIPMENT',
            p_reference_id   => p_order_id,
            p_notes          => 'Physical deduction for shipment',
            p_actor_id       => p_actor_id
        );
    END LOOP;

    UPDATE orders.orders
    SET status     = 'SHIPPED',
        updated_at = CLOCK_TIMESTAMP()
    WHERE id = p_order_id;

    RETURN;
END;
$$;

INSERT INTO core.schema_migrations (version, name, applied_at)
VALUES ('0016', '0016_create_ship_order_procedure', CLOCK_TIMESTAMP())
ON CONFLICT (version) DO NOTHING;

COMMIT;
