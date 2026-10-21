BEGIN;

DROP PROCEDURE IF EXISTS inventory.receive_stock(IN uuid, IN uuid, IN numeric, IN uuid, IN text);

CREATE PROCEDURE inventory.receive_stock(
    IN p_warehouse_id uuid,
    IN p_product_id uuid,
    IN p_quantity numeric,
    IN p_reference_id uuid,
    IN p_notes text
)
LANGUAGE plpgsql
AS $$
BEGIN
    CALL inventory.receive_stock(
        p_product_id := p_product_id,
        p_warehouse_id := p_warehouse_id,
        p_quantity := p_quantity::integer,
        p_reference_id := p_reference_id,
        p_notes := p_notes,
        p_actor_id := NULL
    );
END;
$$;

DROP PROCEDURE IF EXISTS inventory.transfer_stock(IN uuid, IN uuid, IN uuid, IN integer, IN uuid, IN text);

CREATE PROCEDURE inventory.transfer_stock(
    IN p_source_warehouse_id uuid,
    IN p_destination_warehouse_id uuid,
    IN p_product_id uuid,
    IN p_quantity integer,
    IN p_actor_id uuid,
    IN p_notes text
)
LANGUAGE plpgsql
AS $$
BEGIN
    CALL inventory.transfer_stock(
        p_product_id := p_product_id,
        p_from_warehouse_id := p_source_warehouse_id,
        p_to_warehouse_id := p_destination_warehouse_id,
        p_quantity := p_quantity,
        p_notes := p_notes,
        p_actor_id := p_actor_id
    );
END;
$$;

COMMIT;
