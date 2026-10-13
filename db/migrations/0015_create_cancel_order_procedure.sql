ROLLBACK;


BEGIN;

DROP PROCEDURE IF EXISTS orders.cancel_order(UUID, UUID, TEXT);

CREATE OR REPLACE PROCEDURE orders.cancel_order(
    IN p_order_id UUID,
    IN p_actor_id UUID DEFAULT NULL,
    IN p_cancellation_reason TEXT DEFAULT NULL
)
LANGUAGE plpgsql
AS
$$
DECLARE
    v_order_status orders.order_status;
    v_item         RECORD;
BEGIN
    SELECT status
    INTO v_order_status
    FROM orders.orders
    WHERE id = p_order_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Order not found: %', p_order_id
            USING ERRCODE = '02000';
    END IF;

    IF v_order_status IN ('CANCELLED'::orders.order_status, 'DELIVERED'::orders.order_status, 'SHIPPED'::orders.order_status) THEN
        RAISE EXCEPTION 'Order cannot be cancelled in status: %', v_order_status
            USING ERRCODE = '22000';
    END IF;

    FOR v_item IN
        SELECT oi.product_id, sm.warehouse_id, oi.quantity
        FROM orders.order_items oi
        JOIN inventory.stock_movements sm
          ON sm.reference_id = oi.order_id
         AND sm.product_id = oi.product_id
         AND sm.reference_type = 'ORDER'
         AND sm.movement_type = 'RESERVATION'::inventory.movement_type
        WHERE oi.order_id = p_order_id
    LOOP
        CALL inventory.record_stock_movement(
            p_product_id     => v_item.product_id,
            p_warehouse_id   => v_item.warehouse_id,
            p_movement_type  => 'RELEASE'::inventory.movement_type,
            p_quantity_delta => -(v_item.quantity),
            p_reference_type => 'ORDER_CANCELLATION',
            p_reference_id   => p_order_id,
            p_notes          => COALESCE(p_cancellation_reason, 'Order cancelled'),
            p_actor_id       => p_actor_id
        );
    END LOOP;

    UPDATE orders.orders
    SET status     = 'CANCELLED'::orders.order_status,
        updated_at = CLOCK_TIMESTAMP()
    WHERE id = p_order_id;
END;
$$;

INSERT INTO core.schema_migrations (version, name, applied_at)
VALUES ('0015', '0015_create_cancel_order_procedure', CLOCK_TIMESTAMP())
ON CONFLICT (version) DO NOTHING;

COMMIT;
