DROP PROCEDURE IF EXISTS inventory.transfer_stock(uuid, uuid, uuid, integer, uuid, text);

CREATE OR REPLACE PROCEDURE inventory.transfer_stock(
    IN p_source_warehouse_id uuid,
    IN p_destination_warehouse_id uuid,
    IN p_product_id uuid,
    IN p_quantity integer,
    IN p_actor_id uuid DEFAULT NULL::uuid,
    IN p_notes text DEFAULT NULL::text
)
    LANGUAGE plpgsql
AS
$$
DECLARE
    v_src_qty       integer;
    v_src_reserved  integer;
    v_src_avail     integer;
    v_src_new_qty   integer;
    v_dest_qty      integer;
    v_dest_reserved integer;
    v_dest_new_qty  integer;
    v_first_wh      uuid;
    v_second_wh     uuid;
BEGIN
    IF p_source_warehouse_id = p_destination_warehouse_id THEN
        RAISE EXCEPTION 'Source and destination warehouses cannot be the same.'
            USING ERRCODE = '22023';
    END IF;

    IF p_quantity <= 0 THEN
        RAISE EXCEPTION 'Transfer quantity must be greater than zero.'
            USING ERRCODE = '22023';
    END IF;

    IF p_source_warehouse_id < p_destination_warehouse_id THEN
        v_first_wh := p_source_warehouse_id;
        v_second_wh := p_destination_warehouse_id;
    ELSE
        v_first_wh := p_destination_warehouse_id;
        v_second_wh := p_source_warehouse_id;
    END IF;

    SELECT quantity, reserved_quantity
    INTO v_src_qty, v_src_reserved
    FROM inventory.stock_levels
    WHERE warehouse_id = p_source_warehouse_id
      AND product_id = p_product_id
        FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Product % does not exist in source warehouse %.', p_product_id, p_source_warehouse_id
            USING ERRCODE = '23503';
    END IF;

    v_src_avail := v_src_qty - v_src_reserved;
    IF v_src_avail < p_quantity THEN
        RAISE EXCEPTION 'Insufficient available quantity in source warehouse. Available: %, Requested: %', v_src_avail, p_quantity
            USING ERRCODE = '22000';
    END IF;

    SELECT quantity, reserved_quantity
    INTO v_dest_qty, v_dest_reserved
    FROM inventory.stock_levels
    WHERE warehouse_id = p_destination_warehouse_id
      AND product_id = p_product_id
        FOR UPDATE;

    IF NOT FOUND THEN
        INSERT INTO inventory.stock_levels (warehouse_id,
                                            product_id,
                                            quantity,
                                            reserved_quantity,
                                            updated_by)
        VALUES (p_destination_warehouse_id,
                p_product_id,
                0,
                0,
                p_actor_id);
        v_dest_qty := 0;
        v_dest_reserved := 0;
    END IF;

    v_src_new_qty := v_src_qty - p_quantity;
    v_dest_new_qty := v_dest_qty + p_quantity;

    UPDATE inventory.stock_levels
    SET quantity   = v_src_new_qty,
        updated_at = CURRENT_TIMESTAMP,
        updated_by = p_actor_id
    WHERE warehouse_id = p_source_warehouse_id
      AND product_id = p_product_id;

    INSERT INTO inventory.stock_movements (product_id,
                                           warehouse_id,
                                           movement_type,
                                           quantity_delta,
                                           quantity_before,
                                           quantity_after,
                                           reference_type,
                                           notes,
                                           created_by)
    VALUES (p_product_id,
            p_source_warehouse_id,
            'TRANSFER_OUT'::inventory.movement_type,
            -p_quantity,
            v_src_qty,
            v_src_new_qty,
            'WAREHOUSE_TRANSFER',
            COALESCE(p_notes, 'Transfer out to warehouse ' || p_destination_warehouse_id),
            p_actor_id);

    UPDATE inventory.stock_levels
    SET quantity   = v_dest_new_qty,
        updated_at = CURRENT_TIMESTAMP,
        updated_by = p_actor_id
    WHERE warehouse_id = p_destination_warehouse_id
      AND product_id = p_product_id;

    INSERT INTO inventory.stock_movements (product_id,
                                           warehouse_id,
                                           movement_type,
                                           quantity_delta,
                                           quantity_before,
                                           quantity_after,
                                           reference_type,
                                           notes,
                                           created_by)
    VALUES (p_product_id,
            p_destination_warehouse_id,
            'TRANSFER_IN'::inventory.movement_type,
            p_quantity,
            v_dest_qty,
            v_dest_new_qty,
            'WAREHOUSE_TRANSFER',
            COALESCE(p_notes, 'Transfer in from warehouse ' || p_source_warehouse_id),
            p_actor_id);

END;
$$;
