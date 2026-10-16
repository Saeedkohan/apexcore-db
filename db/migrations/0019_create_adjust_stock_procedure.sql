DROP PROCEDURE IF EXISTS inventory.adjust_stock(uuid, uuid, integer, text, uuid);

CREATE OR REPLACE PROCEDURE inventory.adjust_stock(
    IN p_product_id     uuid,
    IN p_warehouse_id   uuid,
    IN p_quantity_delta integer,
    IN p_notes          text DEFAULT NULL::text,
    IN p_actor_id       uuid DEFAULT NULL::uuid
)
LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_product_active     boolean;
    v_warehouse_active   boolean;
    v_current_quantity   integer;
    v_reserved_quantity  integer;
BEGIN
    IF p_quantity_delta IS NULL OR p_quantity_delta = 0 THEN
        RAISE EXCEPTION 'adjust_stock: quantity delta cannot be null or zero'
            USING ERRCODE = '22003';
    END IF;

    SELECT is_active
    INTO v_product_active
    FROM inventory.products
    WHERE id = p_product_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'adjust_stock: product not found: %', p_product_id
            USING ERRCODE = 'P0002';
    END IF;

    IF NOT v_product_active THEN
        RAISE EXCEPTION 'adjust_stock: product is inactive: %', p_product_id
            USING ERRCODE = 'P0003';
    END IF;

    SELECT is_active
    INTO v_warehouse_active
    FROM inventory.warehouses
    WHERE id = p_warehouse_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'adjust_stock: warehouse not found: %', p_warehouse_id
            USING ERRCODE = 'P0002';
    END IF;

    IF NOT v_warehouse_active THEN
        RAISE EXCEPTION 'adjust_stock: warehouse is inactive: %', p_warehouse_id
            USING ERRCODE = 'P0003';
    END IF;

    SELECT quantity, reserved_quantity
    INTO v_current_quantity, v_reserved_quantity
    FROM inventory.stock_levels
    WHERE product_id = p_product_id
      AND warehouse_id = p_warehouse_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'adjust_stock: stock level record not found for product % in warehouse %',
            p_product_id, p_warehouse_id
            USING ERRCODE = 'P0002';
    END IF;

    IF (v_current_quantity + p_quantity_delta) < 0 THEN
        RAISE EXCEPTION 'adjust_stock: resulting quantity cannot be negative (current: %, delta: %)',
            v_current_quantity, p_quantity_delta
            USING ERRCODE = '22003';
    END IF;

    IF (v_current_quantity + p_quantity_delta) < v_reserved_quantity THEN
        RAISE EXCEPTION 'adjust_stock: resulting quantity cannot be less than reserved quantity (resulting: %, reserved: %)',
            (v_current_quantity + p_quantity_delta), v_reserved_quantity
            USING ERRCODE = '22003';
    END IF;

    CALL inventory.record_stock_movement(
        p_product_id,
        p_warehouse_id,
        'STOCK_ADJUSTMENT'::inventory.movement_type,
        p_quantity_delta,
        'STOCK_ADJUSTMENT'::character varying,
        NULL::uuid,
        p_notes,
        p_actor_id
    );
END;
$procedure$;
