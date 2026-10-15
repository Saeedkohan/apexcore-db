BEGIN;

DROP PROCEDURE IF EXISTS orders.deliver_order(uuid, text, uuid);

CREATE OR REPLACE PROCEDURE orders.deliver_order(
    p_order_id uuid,
    p_notes text DEFAULT NULL,
    p_actor_id uuid DEFAULT NULL
)
    LANGUAGE plpgsql
AS
$$

DECLARE
    v_current_status orders.order_status;

BEGIN
    SELECT status
    INTO v_current_status
    FROM orders.orders
    WHERE id = p_order_id
        FOR UPDATE;


    IF NOT FOUND THEN
        RAISE EXCEPTION 'Order with ID % not found', p_order_id
            USING ERRCODE = 'P0002';
    END IF;
    IF v_current_status <> 'SHIPPED' THEN
        RAISE EXCEPTION 'Invalid order status transition: Order % is in % status, but must be SHIPPED to be delivered',
            p_order_id, v_current_status
            USING ERRCODE = 'check_violation';

    END IF;

    UPDATE orders.orders
    SET status='DELIVERED',
        notes=CASE
                  WHEN p_notes IS NOT NULL AND notes IS NOT NULL THEN notes || E'\n' || p_notes
                  WHEN p_notes IS NOT NULL THEN p_notes
                  ELSE notes
            END,
        updated_at = clock_timestamp()
    WHERE id = p_order_id;

    INSERT INTO core.schema_migrations (version, name, applied_at)
    VALUES ('0017', 'create_deliver_order_procedure', clock_timestamp())
    ON CONFLICT (version) DO NOTHING;

END ;
$$;
COMMIT;