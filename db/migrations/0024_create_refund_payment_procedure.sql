DROP PROCEDURE IF EXISTS payments.refund_payment(uuid, numeric, uuid, varchar, uuid);

CREATE OR REPLACE PROCEDURE payments.refund_payment(
    IN p_order_id uuid,
    IN p_amount numeric,
    OUT p_refund_transaction_id uuid,
    IN p_gateway_reference varchar DEFAULT NULL::varchar,
    IN p_actor_id uuid DEFAULT NULL::uuid
)
LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_order_status orders.order_status;
    v_order_currency varchar(3);
    v_total_paid numeric(12, 2);
    v_total_refunded numeric(12, 2);
    v_original_payment_method payments.payment_method;
BEGIN
    IF p_order_id IS NULL THEN
        RAISE EXCEPTION 'refund_payment: order_id cannot be null';
    END IF;

    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION 'refund_payment: amount must be positive';
    END IF;

    SELECT status, currency
    INTO v_order_status, v_order_currency
    FROM orders.orders
    WHERE id = p_order_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'refund_payment: order with id % does not exist', p_order_id;
    END IF;

    IF v_order_status NOT IN ('CANCELLED'::orders.order_status, 'RETURNED'::orders.order_status) THEN
        RAISE EXCEPTION 'refund_payment: refunds are only allowed for CANCELLED or RETURNED orders, current status is %', v_order_status;
    END IF;

    SELECT
        COALESCE(SUM(amount), 0),
        MAX(payment_method)
    INTO v_total_paid, v_original_payment_method
    FROM payments.transactions
    WHERE order_id = p_order_id
      AND status = 'COMPLETED'::payments.payment_status;

    IF v_total_paid = 0 THEN
        RAISE EXCEPTION 'refund_payment: order % has no completed payments to refund', p_order_id;
    END IF;

    SELECT COALESCE(SUM(amount), 0)
    INTO v_total_refunded
    FROM payments.transactions
    WHERE order_id = p_order_id
      AND status = 'REFUNDED'::payments.payment_status;

    IF (v_total_refunded + p_amount) > v_total_paid THEN
        RAISE EXCEPTION 'refund_payment: refund amount % exceeds refundable balance % (paid: %, already refunded: %)',
            p_amount, (v_total_paid - v_total_refunded), v_total_paid, v_total_refunded;
    END IF;

    INSERT INTO payments.transactions (
        order_id,
        amount,
        currency,
        payment_method,
        status,
        gateway_reference
    )
    VALUES (
        p_order_id,
        p_amount,
        v_order_currency,
        v_original_payment_method,
        'REFUNDED'::payments.payment_status,
        p_gateway_reference
    )
    RETURNING id INTO p_refund_transaction_id;
END;
$procedure$;
