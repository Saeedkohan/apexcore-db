BEGIN;

CREATE OR REPLACE FUNCTION inventory.record_stock_movement(
    p_product_id uuid,
    p_warehouse_id uuid,
    p_movement_type inventory.movement_type,
    p_quantity_delta integer,
    p_reference_type varchar DEFAULT NULL,
    p_reference_id uuid DEFAULT NULL,
    p_notes text DEFAULT NULL,
    p_actor_id uuid DEFAULT NULL
)
    RETURNS bigint
    LANGUAGE plpgsql
AS
$$
DECLARE
    v_movement_id     bigint;
    v_stock_level_id  uuid;
    v_quantity_before integer;
    v_reserved_before integer;
    v_quantity_after  integer;
    v_reserved_after  integer;
BEGIN

    IF p_quantity_delta IS NULL OR p_quantity_delta = 0 THEN
        RAISE EXCEPTION 'record_stock_movement: quantity_delta must be a non-zero integer';
    END IF;


    CASE p_movement_type
        WHEN 'PURCHASE_RECEIPT', 'TRANSFER_IN' THEN IF p_quantity_delta < 0 THEN
            RAISE EXCEPTION 'record_stock_movement: % requires a positive delta (got %)', p_movement_type, p_quantity_delta;
        END IF;

        WHEN 'SALE_DISPATCH', 'TRANSFER_OUT' THEN IF p_quantity_delta > 0 THEN
            RAISE EXCEPTION 'record_stock_movement: % requires a negative delta (got %)', p_movement_type, p_quantity_delta;
        END IF;

        WHEN 'RESERVATION' THEN IF p_quantity_delta < 0 THEN
            RAISE EXCEPTION 'record_stock_movement: RESERVATION requires a positive delta to increase reserved quantity (got %)', p_quantity_delta;
        END IF;

        WHEN 'RELEASE' THEN IF p_quantity_delta > 0 THEN
            RAISE EXCEPTION 'record_stock_movement: RELEASE requires a negative delta to decrease reserved quantity (got %)', p_quantity_delta;
        END IF;

        WHEN 'STOCK_ADJUSTMENT' THEN NULL;
        END CASE;

    SELECT sl.id, sl.quantity, sl.reserved_quantity
    INTO v_stock_level_id, v_quantity_before, v_reserved_before
    FROM inventory.stock_levels sl
    WHERE sl.product_id = p_product_id
      AND sl.warehouse_id = p_warehouse_id
        FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'record_stock_movement: no stock_levels row found for product % in warehouse %',
            p_product_id, p_warehouse_id;
    END IF;

    IF p_movement_type IN ('RESERVATION', 'RELEASE') THEN
        v_quantity_after := v_quantity_before;
        v_reserved_after := v_reserved_before + p_quantity_delta;

        IF v_reserved_after < 0 THEN
            RAISE EXCEPTION 'record_stock_movement: invalid release, reserved quantity cannot be negative (current reserved: %, requested: %)',
                v_reserved_before, p_quantity_delta;
        END IF;

        IF v_reserved_after > v_quantity_before THEN
            RAISE EXCEPTION 'record_stock_movement: insufficient stock to reserve (available unreserved: %, requested: %)',
                (v_quantity_before - v_reserved_before), p_quantity_delta;
        END IF;
    ELSE
        v_quantity_after := v_quantity_before + p_quantity_delta;
        v_reserved_after := v_reserved_before;

        IF v_quantity_after < 0 THEN
            RAISE EXCEPTION 'record_stock_movement: insufficient physical stock (current: %, delta: %)',
                v_quantity_before, p_quantity_delta;
        END IF;

        IF v_quantity_after < v_reserved_before THEN
            RAISE EXCEPTION 'record_stock_movement: cannot reduce quantity below reserved amount (reserved: %, remaining: %)',
                v_reserved_before, v_quantity_after;
        END IF;
    END IF;

    INSERT INTO inventory.stock_movements (product_id,
                                           warehouse_id,
                                           movement_type,
                                           quantity_delta,
                                           quantity_before,
                                           quantity_after,
                                           reference_type,
                                           reference_id,
                                           notes,
                                           created_by)
    VALUES (p_product_id,
            p_warehouse_id,
            p_movement_type,
            p_quantity_delta,
            v_quantity_before,
            v_quantity_after,
            p_reference_type,
            p_reference_id,
            p_notes,
            p_actor_id)
    RETURNING id INTO v_movement_id;

    UPDATE inventory.stock_levels
    SET quantity          = v_quantity_after,
        reserved_quantity = v_reserved_after,
        updated_at        = CLOCK_TIMESTAMP(),
        updated_by        = p_actor_id
    WHERE id = v_stock_level_id;

    RETURN v_movement_id;
END;
$$;

COMMENT ON FUNCTION inventory.record_stock_movement(uuid, uuid, inventory.movement_type, integer, varchar, uuid, text, uuid)
    IS 'Atomically registers a stock movement ledger row and mutates physical/reserved stock levels with strict validation and FOR UPDATE locking.';

INSERT INTO core.schema_migrations (version, name, applied_at)
VALUES ('0012', '0012_record_stock_movement_procedure', CLOCK_TIMESTAMP())
ON CONFLICT (version) DO NOTHING;

COMMIT;
