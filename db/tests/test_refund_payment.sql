BEGIN;

DO $test$
DECLARE
    v_customer_id uuid;
    v_category_id uuid;
    v_product_id uuid;
    v_order_confirmed_id uuid;
    v_order_cancelled_id uuid;
    v_order_unpaid_id uuid;
    v_payment_id uuid;
    v_refund_id uuid;
    v_second_refund_id uuid;
    v_refund_count integer;
    v_error_caught boolean;
    -- استفاده از حروف بزرگ برای سازگاری با chk_products_sku_format
    v_test_suffix text := upper(replace(gen_random_uuid()::text, '-', ''));
BEGIN
    INSERT INTO core.users (
        username,
        email,
        password_hash,
        is_active,
        is_admin
    )
    VALUES (
        'REFUND_TEST_' || v_test_suffix,
        'refund_test_' || lower(v_test_suffix) || '@example.test',
        'test-only-password-hash',
        true,
        false
    )
    RETURNING id INTO v_customer_id;

    INSERT INTO inventory.categories (name)
    VALUES ('Refund Test Category ' || v_test_suffix)
    RETURNING id INTO v_category_id;

    INSERT INTO inventory.products (
        category_id,
        sku,
        name,
        base_price,
        currency
    )
    VALUES (
        v_category_id,
        'SKU-' || substring(v_test_suffix from 1 for 8),
        'Refund Test Product',
        100.00,
        'USD'
    )
    RETURNING id INTO v_product_id;

    INSERT INTO orders.orders (
        order_number,
        customer_id,
        status,
        total_amount,
        currency,
        shipping_address
    )
    VALUES (
        'ORD-CONF-' || substring(v_test_suffix from 1 for 8),
        v_customer_id,
        'CONFIRMED'::orders.order_status,
        100.00,
        'USD',
        '{}'::jsonb
    )
    RETURNING id INTO v_order_confirmed_id;

    INSERT INTO payments.transactions (
        order_id,
        amount,
        currency,
        payment_method,
        status,
        gateway_reference
    )
    VALUES (
        v_order_confirmed_id,
        100.00,
        'USD',
        'CREDIT_CARD'::payments.payment_method,
        'COMPLETED'::payments.payment_status,
        'GW-CONF-' || substring(v_test_suffix from 1 for 8)
    )
    RETURNING id INTO v_payment_id;

    v_error_caught := false;

    BEGIN
        CALL payments.refund_payment(
            p_order_id := v_order_confirmed_id,
            p_amount := 10.00,
            p_refund_transaction_id := v_refund_id,
            p_gateway_reference := 'GW-REF-FAIL-1'
        );
    EXCEPTION
        WHEN OTHERS THEN
            v_error_caught := true;
    END;

    IF NOT v_error_caught THEN
        RAISE EXCEPTION 'Test failed: a CONFIRMED order must not be refundable.';
    END IF;

    SELECT COUNT(*)::integer
    INTO v_refund_count
    FROM payments.transactions
    WHERE order_id = v_order_confirmed_id
      AND status = 'REFUNDED'::payments.payment_status;

    IF v_refund_count <> 0 THEN
        RAISE EXCEPTION 'Test failed: rejected refund created a refund transaction.';
    END IF;

    INSERT INTO orders.orders (
        order_number,
        customer_id,
        status,
        total_amount,
        currency,
        shipping_address
    )
    VALUES (
        'ORD-CANC-' || substring(v_test_suffix from 1 for 8),
        v_customer_id,
        'CANCELLED'::orders.order_status,
        100.00,
        'USD',
        '{}'::jsonb
    )
    RETURNING id INTO v_order_cancelled_id;

    INSERT INTO payments.transactions (
        order_id,
        amount,
        currency,
        payment_method,
        status,
        gateway_reference
    )
    VALUES (
        v_order_cancelled_id,
        100.00,
        'USD',
        'CREDIT_CARD'::payments.payment_method,
        'COMPLETED'::payments.payment_status,
        'GW-CANC-' || substring(v_test_suffix from 1 for 8)
    );

    CALL payments.refund_payment(
        p_order_id := v_order_cancelled_id,
        p_amount := 40.00,
        p_refund_transaction_id := v_refund_id,
        p_gateway_reference := 'GW-REF-SUCC-1'
    );

    IF v_refund_id IS NULL THEN
        RAISE EXCEPTION 'Test failed: procedure returned a NULL refund transaction id.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM payments.transactions
        WHERE id = v_refund_id
          AND order_id = v_order_cancelled_id
          AND amount = 40.00
          AND currency = 'USD'
          AND payment_method = 'CREDIT_CARD'::payments.payment_method
          AND status = 'REFUNDED'::payments.payment_status
          AND gateway_reference = 'GW-REF-SUCC-1'
    ) THEN
        RAISE EXCEPTION 'Test failed: refund transaction data is incorrect.';
    END IF;

    v_error_caught := false;

    BEGIN
        CALL payments.refund_payment(
            p_order_id := v_order_cancelled_id,
            p_amount := 61.00,
            p_refund_transaction_id := v_second_refund_id,
            p_gateway_reference := 'GW-REF-FAIL-OVER'
        );
    EXCEPTION
        WHEN OTHERS THEN
            v_error_caught := true;
    END;

    IF NOT v_error_caught THEN
        RAISE EXCEPTION 'Test failed: over-refund must be rejected.';
    END IF;

    SELECT COUNT(*)::integer
    INTO v_refund_count
    FROM payments.transactions
    WHERE order_id = v_order_cancelled_id
      AND status = 'REFUNDED'::payments.payment_status;

    IF v_refund_count <> 1 THEN
        RAISE EXCEPTION 'Test failed: rejected over-refund changed refund transactions.';
    END IF;

    INSERT INTO orders.orders (
        order_number,
        customer_id,
        status,
        total_amount,
        currency,
        shipping_address
    )
    VALUES (
        'ORD-UNPAID-' || substring(v_test_suffix from 1 for 8),
        v_customer_id,
        'RETURNED'::orders.order_status,
        100.00,
        'USD',
        '{}'::jsonb
    )
    RETURNING id INTO v_order_unpaid_id;

    v_error_caught := false;

    BEGIN
        CALL payments.refund_payment(
            p_order_id := v_order_unpaid_id,
            p_amount := 10.00,
            p_refund_transaction_id := v_second_refund_id,
            p_gateway_reference := 'GW-REF-FAIL-UNPAID'
        );
    EXCEPTION
        WHEN OTHERS THEN
            v_error_caught := true;
    END;

    IF NOT v_error_caught THEN
        RAISE EXCEPTION 'Test failed: an order without completed payments must not be refundable.';
    END IF;

    RAISE NOTICE 'All refund_payment tests passed successfully.';
END;
$test$;

ROLLBACK;
