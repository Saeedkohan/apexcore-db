BEGIN;

DO $$
DECLARE
    v_user_id uuid;
    v_category_id uuid;
    v_product_id uuid;
    v_warehouse_id uuid;
    v_order_id uuid;
    v_order_number varchar := 'ORD-PAY-' || UPPER(SUBSTRING(gen_random_uuid()::text, 1, 8));
    v_order_qty integer := 2;
    v_unit_price numeric := 150.00;
    v_expected_total numeric := 300.00;
    v_transaction_id uuid;
    v_failed_tx_id uuid;
    v_order_status orders.order_status;
    v_tx_status payments.payment_status;
    v_items orders.order_item_input[];
BEGIN
    INSERT INTO core.users (username, email, password_hash, is_active, is_admin)
    VALUES (
        'pay_user_' || LOWER(SUBSTRING(gen_random_uuid()::text, 1, 8)),
        'pay_' || LOWER(SUBSTRING(gen_random_uuid()::text, 1, 8)) || '@apexcore.local',
        'hash_test',
        true,
        false
    )
    RETURNING id INTO v_user_id;

    INSERT INTO inventory.categories (name, is_active)
    VALUES ('Pay Cat ' || SUBSTRING(gen_random_uuid()::text, 1, 8), true)
    RETURNING id INTO v_category_id;

    INSERT INTO inventory.products (category_id, sku, name, base_price, is_active)
    VALUES (
        v_category_id,
        'SKU-PAY-' || UPPER(SUBSTRING(gen_random_uuid()::text, 1, 8)),
        'Payment Test Product',
        v_unit_price,
        true
    )
    RETURNING id INTO v_product_id;

    INSERT INTO inventory.warehouses (code, name, is_active)
    VALUES (
        'WH-PAY-' || UPPER(SUBSTRING(gen_random_uuid()::text, 1, 8)),
        'Payment Test Warehouse',
        true
    )
    RETURNING id INTO v_warehouse_id;

    INSERT INTO inventory.stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
    VALUES (v_product_id, v_warehouse_id, 20, 0);

    v_items := ARRAY[
        ROW(v_product_id, v_warehouse_id, v_order_qty, v_unit_price)::orders.order_item_input
    ];

    CALL orders.place_order(
        p_customer_id      => v_user_id,
        p_order_number     => v_order_number,
        p_shipping_address => '{"city": "Tehran", "street": "Niavaran"}'::jsonb,
        p_items            => v_items,
        p_notes            => 'Test Payment Processing',
        p_order_id         => v_order_id
    );

    CALL payments.process_payment(
        p_order_id          => v_order_id,
        p_amount            => v_expected_total,
        p_payment_method    => 'CREDIT_CARD'::payments.payment_method,
        p_is_successful     => false,
        p_transaction_id    => v_failed_tx_id,
        p_gateway_reference => 'GTW-FAIL-001',
        p_actor_id         => v_user_id
    );

    SELECT status INTO v_order_status FROM orders.orders WHERE id = v_order_id;
    SELECT status INTO v_tx_status FROM payments.transactions WHERE id = v_failed_tx_id;

    IF v_order_status <> 'PENDING' THEN
        RAISE EXCEPTION 'TEST FAILED: Order status should remain PENDING after failed payment, got %', v_order_status;
    END IF;

    IF v_tx_status <> 'FAILED' THEN
        RAISE EXCEPTION 'TEST FAILED: Transaction status should be FAILED, got %', v_tx_status;
    END IF;

    CALL payments.process_payment(
        p_order_id          => v_order_id,
        p_amount            => v_expected_total,
        p_payment_method    => 'CREDIT_CARD'::payments.payment_method,
        p_is_successful     => true,
        p_transaction_id    => v_transaction_id,
        p_gateway_reference => 'GTW-SUCC-002',
        p_actor_id         => v_user_id
    );

    SELECT status INTO v_order_status FROM orders.orders WHERE id = v_order_id;
    SELECT status INTO v_tx_status FROM payments.transactions WHERE id = v_transaction_id;

    IF v_order_status <> 'CONFIRMED' THEN
        RAISE EXCEPTION 'TEST FAILED: Order status should be CONFIRMED after successful payment, got %', v_order_status;
    END IF;

    IF v_tx_status <> 'COMPLETED' THEN
        RAISE EXCEPTION 'TEST FAILED: Transaction status should be COMPLETED, got %', v_tx_status;
    END IF;

    RAISE NOTICE 'SUCCESS: All process_payment assertions passed cleanly.';
END $$;

ROLLBACK;
