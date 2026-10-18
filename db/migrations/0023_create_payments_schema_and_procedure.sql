CREATE SCHEMA IF NOT EXISTS payments;

CREATE TYPE payments.payment_method AS ENUM (
    'CREDIT_CARD',
    'BANK_TRANSFER',
    'CASH_ON_DELIVERY',
    'WALLET'
);

CREATE TYPE payments.payment_status AS ENUM (
    'PENDING',
    'COMPLETED',
    'FAILED',
    'REFUNDED'
);

CREATE TABLE IF NOT EXISTS payments.transactions (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    order_id uuid NOT NULL REFERENCES orders.orders(id) ON DELETE RESTRICT,
    amount numeric(12, 2) NOT NULL,
    currency varchar(3) NOT NULL DEFAULT 'USD',
    payment_method payments.payment_method NOT NULL,
    status payments.payment_status NOT NULL DEFAULT 'PENDING'::payments.payment_status,
    gateway_reference varchar(100),
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT chk_payments_amount_positive CHECK (amount > 0)
);

CREATE INDEX IF NOT EXISTS idx_payments_transactions_order_id ON payments.transactions(order_id);
CREATE INDEX IF NOT EXISTS idx_payments_transactions_status ON payments.transactions(status);

DROP PROCEDURE IF EXISTS payments.process_payment(uuid, numeric, payments.payment_method, boolean, uuid, varchar, uuid);

CREATE OR REPLACE PROCEDURE payments.process_payment(
    IN p_order_id uuid,
    IN p_amount numeric,
    IN p_payment_method payments.payment_method,
    IN p_is_successful boolean,
    OUT p_transaction_id uuid,
    IN p_gateway_reference varchar DEFAULT NULL::varchar,
    IN p_actor_id uuid DEFAULT NULL::uuid
)
LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_order_status orders.order_status;
    v_order_total numeric(12, 2);
    v_order_currency varchar(3);
    v_payment_status payments.payment_status;
BEGIN
    IF p_order_id IS NULL THEN
        RAISE EXCEPTION 'process_payment: order_id cannot be null';
    END IF;

    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION 'process_payment: amount must be positive';
    END IF;

    IF p_payment_method IS NULL THEN
        RAISE EXCEPTION 'process_payment: payment_method cannot be null';
    END IF;

    SELECT status, total_amount, currency
    INTO v_order_status, v_order_total, v_order_currency
    FROM orders.orders
    WHERE id = p_order_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'process_payment: order with id % does not exist', p_order_id;
    END IF;

    IF v_order_status <> 'PENDING'::orders.order_status THEN
        RAISE EXCEPTION 'process_payment: order % is in % status, payment can only be processed for PENDING orders', p_order_id, v_order_status;
    END IF;

    IF p_amount <> v_order_total THEN
        RAISE EXCEPTION 'process_payment: payment amount % does not match order total amount %', p_amount, v_order_total;
    END IF;

    IF p_is_successful THEN
        v_payment_status := 'COMPLETED'::payments.payment_status;
    ELSE
        v_payment_status := 'FAILED'::payments.payment_status;
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
        p_payment_method,
        v_payment_status,
        p_gateway_reference
    )
    RETURNING id INTO p_transaction_id;

    IF p_is_successful THEN
        UPDATE orders.orders
        SET status     = 'CONFIRMED'::orders.order_status,
            updated_at = clock_timestamp()
        WHERE id = p_order_id;
    END IF;
END;
$procedure$;
