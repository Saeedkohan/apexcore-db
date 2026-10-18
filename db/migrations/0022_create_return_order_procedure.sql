ALTER TYPE orders.order_status ADD VALUE IF NOT EXISTS 'RETURNED';
ALTER TYPE inventory.movement_type ADD VALUE IF NOT EXISTS 'RETURN_RESTOCK';

CREATE OR REPLACE PROCEDURE inventory.record_stock_movement(
    IN p_product_id uuid,
    IN p_warehouse_id uuid,
    IN p_movement_type inventory.movement_type,
    IN p_quantity_delta integer,
    IN p_reference_type character varying DEFAULT NULL::character varying,
    IN p_reference_id uuid DEFAULT NULL::uuid,
    IN p_notes text DEFAULT NULL::text,
    IN p_actor_id uuid DEFAULT NULL::uuid
)
LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_quantity_before   integer;
    v_quantity_after    integer;
    v_delta_to_record   integer := p_quantity_delta;
BEGIN
    IF p_quantity_delta = 0 AND p_movement_type NOT IN ('RESERVATION'::inventory.movement_type, 'RELEASE'::inventory.movement_type) THEN
        RAISE EXCEPTION 'record_stock_movement: quantity_delta must be a non-zero integer for physical movements';
    END IF;

    SELECT quantity
    INTO v_quantity_before
    FROM inventory.stock_levels
    WHERE product_id = p_product_id
      AND warehouse_id = p_warehouse_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Stock level not found for product % in warehouse %', p_product_id, p_warehouse_id;
    END IF;

    CASE p_movement_type
        WHEN 'PURCHASE_RECEIPT'::inventory.movement_type, 'TRANSFER_IN'::inventory.movement_type, 'RETURN_RESTOCK'::inventory.movement_type THEN
            UPDATE inventory.stock_levels
            SET quantity   = quantity + ABS(p_quantity_delta),
                updated_at = CLOCK_TIMESTAMP()
            WHERE product_id = p_product_id
              AND warehouse_id = p_warehouse_id;
        WHEN 'SALE_DISPATCH'::inventory.movement_type, 'TRANSFER_OUT'::inventory.movement_type THEN
            UPDATE inventory.stock_levels
            SET quantity   = quantity - ABS(p_quantity_delta),
                updated_at = CLOCK_TIMESTAMP()
            WHERE product_id = p_product_id
              AND warehouse_id = p_warehouse_id;
        WHEN 'STOCK_ADJUSTMENT'::inventory.movement_type THEN
            UPDATE inventory.stock_levels
            SET quantity   = quantity + p_quantity_delta,
                updated_at = CLOCK_TIMESTAMP()
            WHERE product_id = p_product_id
              AND warehouse_id = p_warehouse_id;
        WHEN 'RESERVATION'::inventory.movement_type THEN
            UPDATE inventory.stock_levels
            SET reserved_quantity = reserved_quantity + ABS(p_quantity_delta),
                updated_at        = CLOCK_TIMESTAMP()
            WHERE product_id = p_product_id
              AND warehouse_id = p_warehouse_id;
            v_delta_to_record := 0;
        WHEN 'RELEASE'::inventory.movement_type THEN
            UPDATE inventory.stock_levels
            SET reserved_quantity = reserved_quantity - ABS(p_quantity_delta),
                updated_at        = CLOCK_TIMESTAMP()
            WHERE product_id = p_product_id
              AND warehouse_id = p_warehouse_id;
            v_delta_to_record := 0;
        ELSE
            RAISE EXCEPTION 'record_stock_movement: unhandled movement type %', p_movement_type;
    END CASE;

    SELECT quantity
    INTO v_quantity_after
    FROM inventory.stock_levels
    WHERE product_id = p_product_id
      AND warehouse_id = p_warehouse_id;

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
        created_by
    )
    VALUES (
        p_product_id,
        p_warehouse_id,
        p_movement_type,
        v_delta_to_record,
        v_quantity_before,
        v_quantity_after,
        p_reference_type,
        p_reference_id,
        p_notes,
        p_actor_id
    );
END;
$procedure$;

DROP PROCEDURE IF EXISTS orders.return_order(uuid, uuid, text);

CREATE OR REPLACE PROCEDURE orders.return_order(
    IN p_order_id uuid,
    IN p_actor_id uuid DEFAULT NULL::uuid,
    IN p_return_reason text DEFAULT NULL::text
)
LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_current_status orders.order_status;
    v_item RECORD;
BEGIN
    IF p_order_id IS NULL THEN
        RAISE EXCEPTION 'return_order: order_id cannot be null';
    END IF;

    SELECT status
    INTO v_current_status
    FROM orders.orders
    WHERE id = p_order_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'return_order: order with id % does not exist', p_order_id;
    END IF;

    IF v_current_status <> 'DELIVERED'::orders.order_status THEN
        RAISE EXCEPTION 'return_order: order % cannot be returned from status %', p_order_id, v_current_status;
    END IF;

    FOR v_item IN
        SELECT
            oi.product_id,
            oi.quantity,
            sm.warehouse_id
        FROM orders.order_items oi
        JOIN inventory.stock_movements sm
          ON sm.reference_id = p_order_id
         AND sm.product_id = oi.product_id
         AND sm.movement_type = 'SALE_DISPATCH'::inventory.movement_type
        WHERE oi.order_id = p_order_id
    LOOP
        CALL inventory.record_stock_movement(
            p_product_id     => v_item.product_id,
            p_warehouse_id    => v_item.warehouse_id,
            p_movement_type   => 'RETURN_RESTOCK'::inventory.movement_type,
            p_quantity_delta  => v_item.quantity,
            p_reference_type  => 'orders.orders',
            p_reference_id    => p_order_id,
            p_notes           => COALESCE(p_return_reason, 'Order return restock'),
            p_actor_id        => p_actor_id
        );
    END LOOP;

    UPDATE orders.orders
    SET status     = 'RETURNED'::orders.order_status,
        updated_at = CLOCK_TIMESTAMP()
    WHERE id = p_order_id;
END;
$procedure$;
