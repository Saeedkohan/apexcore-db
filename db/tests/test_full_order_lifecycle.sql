BEGIN;

DO $lifecycle_test$
DECLARE
    v_suffix text := upper(replace(gen_random_uuid()::text, '-', ''));
    v_customer_id uuid;
    v_warehouse_id uuid;
    v_category_id uuid;
    v_product_id uuid;

    v_order_a_id uuid;
    v_order_a_num varchar := 'ORD-E2E-A-' || substring(v_suffix from 1 for 6);
    v_order_b_id uuid;
    v_order_b_num varchar := 'ORD-E2E-B-' || substring(v_suffix from 1 for 6);

    v_payment_tx_id uuid;
    v_refund_tx_id uuid;

    v_status orders.order_status;
    v_qty integer;
    v_reserved integer;
    v_total_paid numeric(12, 2);
    v_total_refunded numeric(12, 2);
BEGIN
    INSERT INTO core.users (
        username,
        email,
        password_hash,
        is_active,
        is_admin
    )
    VALUES (
        'USER_' || v_suffix,
        'user_' || lower(v_suffix) || '@apexcore.test',
        'hash-test-secret',
        true,
        false
    )
    RETURNING id INTO v_customer_id;

    INSERT INTO inventory.warehouses (
        code,
        name,
        is_active
    )
    VALUES (
        'WH-' || substring(v_suffix from 1 for 8),
        'Warehouse ' || v_suffix,
        true
    )
    RETURNING id INTO v_warehouse_id;

    INSERT INTO inventory.categories (name)
    VALUES ('Category ' || v_suffix)
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
        'SKU-' || substring(v_suffix from 1 for 8),
        'Lifecycle Product ' || v_suffix,
        50.00,
        'USD'
    )
    RETURNING id INTO v_product_id;

    INSERT INTO inventory.stock_levels (
        warehouse_id,
        product_id,
        quantity,
        reserved_quantity
    )
    VALUES (
        v_warehouse_id,
        v_product_id,
        20,
        0
    );

    -- =========================================================================
    -- SCENARIO A: place -> pay -> ship -> deliver -> return -> refund
    -- =========================================================================

    CALL orders.place_order(
        p_customer_id := v_customer_id,
        p_order_number := v_order_a_num,
        p_shipping_address := '{"country": "IR", "city": "Tehran"}'::jsonb,
        p_items := ARRAY[
            ROW(v_product_id, v_warehouse_id, 5, 50.0000)::orders.order_item_input
        ],
        p_notes := 'Lifecycle Order A',
        p_order_id := v_order_a_id
    );

    SELECT status INTO v_status FROM orders.orders WHERE id = v_order_a_id;
    IF v_status <> 'PENDING'::orders.order_status THEN
        RAISE EXCEPTION 'Scenario A Failed: Expected PENDING, got %', v_status;
    END IF;

    SELECT quantity, reserved_quantity INTO v_qty, v_reserved
    FROM inventory.stock_levels
    WHERE warehouse_id = v_warehouse_id AND product_id = v_product_id;

    IF v_qty <> 20 OR v_reserved <> 5 THEN
        RAISE EXCEPTION 'Scenario A Failed: Stock reservation mismatch after place_order (qty: %, reserved: %)', v_qty, v_reserved;
    END IF;

    CALL payments.process_payment(
        p_order_id := v_order_a_id,
        p_amount := 250.00,
        p_payment_method := 'CREDIT_CARD'::payments.payment_method,
        p_is_successful := true,
        p_transaction_id := v_payment_tx_id,
        p_gateway_reference := 'GW-A-' || v_suffix,
        p_actor_id := v_customer_id
    );

    SELECT status INTO v_status FROM orders.orders WHERE id = v_order_a_id;
    IF v_status <> 'CONFIRMED'::orders.order_status THEN
        RAISE EXCEPTION 'Scenario A Failed: Expected CONFIRMED, got %', v_status;
    END IF;

    CALL orders.ship_order(
        p_order_id := v_order_a_id,
        p_actor_id := v_customer_id
    );

    SELECT status INTO v_status FROM orders.orders WHERE id = v_order_a_id;
    IF v_status <> 'SHIPPED'::orders.order_status THEN
        RAISE EXCEPTION 'Scenario A Failed: Expected SHIPPED, got %', v_status;
    END IF;

    SELECT quantity, reserved_quantity INTO v_qty, v_reserved
    FROM inventory.stock_levels
    WHERE warehouse_id = v_warehouse_id AND product_id = v_product_id;

    IF v_qty <> 15 OR v_reserved <> 0 THEN
        RAISE EXCEPTION 'Scenario A Failed: Stock deduction mismatch after ship_order (qty: %, reserved: %)', v_qty, v_reserved;
    END IF;

    CALL orders.deliver_order(
        p_order_id := v_order_a_id,
        p_notes := 'Customer received shipment',
        p_actor_id := v_customer_id
    );

    SELECT status INTO v_status FROM orders.orders WHERE id = v_order_a_id;
    IF v_status <> 'DELIVERED'::orders.order_status THEN
        RAISE EXCEPTION 'Scenario A Failed: Expected DELIVERED, got %', v_status;
    END IF;

    CALL orders.return_order(
        p_order_id := v_order_a_id,
        p_actor_id := v_customer_id,
        p_return_reason := 'Product returned by customer'
    );

    SELECT status INTO v_status FROM orders.orders WHERE id = v_order_a_id;
    IF v_status <> 'RETURNED'::orders.order_status THEN
        RAISE EXCEPTION 'Scenario A Failed: Expected RETURNED, got %', v_status;
    END IF;

    SELECT quantity, reserved_quantity INTO v_qty, v_reserved
    FROM inventory.stock_levels
    WHERE warehouse_id = v_warehouse_id AND product_id = v_product_id;

    IF v_qty <> 20 OR v_reserved <> 0 THEN
        RAISE EXCEPTION 'Scenario A Failed: Stock restock mismatch after return_order (qty: %, reserved: %)', v_qty, v_reserved;
    END IF;

    CALL payments.refund_payment(
        p_order_id := v_order_a_id,
        p_amount := 250.00,
        p_refund_transaction_id := v_refund_tx_id,
        p_gateway_reference := 'GW-REF-A-' || v_suffix,
        p_actor_id := v_customer_id
    );

    SELECT
        COALESCE(SUM(CASE WHEN status = 'COMPLETED'::payments.payment_status THEN amount ELSE 0 END), 0),
        COALESCE(SUM(CASE WHEN status = 'REFUNDED'::payments.payment_status THEN amount ELSE 0 END), 0)
    INTO v_total_paid, v_total_refunded
    FROM payments.transactions
    WHERE order_id = v_order_a_id;

    IF v_total_paid <> 250.00 OR v_total_refunded <> 250.00 THEN
        RAISE EXCEPTION 'Scenario A Failed: Financial balance mismatch (paid: %, refunded: %)', v_total_paid, v_total_refunded;
    END IF;

    -- =========================================================================
    -- SCENARIO B: place -> pay -> cancel -> refund
    -- =========================================================================

    CALL orders.place_order(
        p_customer_id := v_customer_id,
        p_order_number := v_order_b_num,
        p_shipping_address := '{"country": "IR", "city": "Shiraz"}'::jsonb,
        p_items := ARRAY[
            ROW(v_product_id, v_warehouse_id, 3, 50.0000)::orders.order_item_input
        ],
        p_notes := 'Lifecycle Order B',
        p_order_id := v_order_b_id
    );

    SELECT quantity, reserved_quantity INTO v_qty, v_reserved
    FROM inventory.stock_levels
    WHERE warehouse_id = v_warehouse_id AND product_id = v_product_id;

    IF v_qty <> 20 OR v_reserved <> 3 THEN
        RAISE EXCEPTION 'Scenario B Failed: Reservation mismatch after place_order (qty: %, reserved: %)', v_qty, v_reserved;
    END IF;

    CALL payments.process_payment(
        p_order_id := v_order_b_id,
        p_amount := 150.00,
        p_payment_method := 'CREDIT_CARD'::payments.payment_method,
        p_is_successful := true,
        p_transaction_id := v_payment_tx_id,
        p_gateway_reference := 'GW-B-' || v_suffix,
        p_actor_id := v_customer_id
    );

    CALL orders.cancel_order(
        p_order_id := v_order_b_id,
        p_actor_id := v_customer_id,
        p_cancellation_reason := 'Customer cancelled before shipment'
    );

    SELECT status INTO v_status FROM orders.orders WHERE id = v_order_b_id;
    IF v_status <> 'CANCELLED'::orders.order_status THEN
        RAISE EXCEPTION 'Scenario B Failed: Expected CANCELLED, got %', v_status;
    END IF;

    SELECT quantity, reserved_quantity INTO v_qty, v_reserved
    FROM inventory.stock_levels
    WHERE warehouse_id = v_warehouse_id AND product_id = v_product_id;

    IF v_qty <> 20 OR v_reserved <> 0 THEN
        RAISE EXCEPTION 'Scenario B Failed: Reservation release mismatch after cancel_order (qty: %, reserved: %)', v_qty, v_reserved;
    END IF;

    CALL payments.refund_payment(
        p_order_id := v_order_b_id,
        p_amount := 150.00,
        p_refund_transaction_id := v_refund_tx_id,
        p_gateway_reference := 'GW-REF-B-' || v_suffix,
        p_actor_id := v_customer_id
    );

    SELECT
        COALESCE(SUM(CASE WHEN status = 'COMPLETED'::payments.payment_status THEN amount ELSE 0 END), 0),
        COALESCE(SUM(CASE WHEN status = 'REFUNDED'::payments.payment_status THEN amount ELSE 0 END), 0)
    INTO v_total_paid, v_total_refunded
    FROM payments.transactions
    WHERE order_id = v_order_b_id;

    IF v_total_paid <> 150.00 OR v_total_refunded <> 150.00 THEN
        RAISE EXCEPTION 'Scenario B Failed: Financial balance mismatch on cancelled order (paid: %, refunded: %)', v_total_paid, v_total_refunded;
    END IF;

    RAISE NOTICE 'SUCCESS: All full order lifecycle scenarios passed cleanly.';
END;
$lifecycle_test$;

ROLLBACK;
