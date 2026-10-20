BEGIN;

DO $test_views$
DECLARE
    v_suffix text := upper(replace(gen_random_uuid()::text, '-', ''));
    v_customer_id uuid;
    v_warehouse_id uuid;
    v_category_id uuid;
    v_product_id uuid;
    v_order_id uuid;
    v_payment_id uuid;
    v_refund_id uuid;

    v_fin_record record;
    v_stock_record record;
    v_val_record record;
BEGIN
    INSERT INTO core.users (username, email, password_hash)
    VALUES ('USER_VW_' || v_suffix, 'user_vw_' || lower(v_suffix) || '@test.com', 'hash_pw')
    RETURNING id INTO v_customer_id;

    INSERT INTO inventory.warehouses (code, name, is_active)
    VALUES ('WH-VW-' || substring(v_suffix from 1 for 6), 'Warehouse Views ' || v_suffix, true)
    RETURNING id INTO v_warehouse_id;

    INSERT INTO inventory.categories (name)
    VALUES ('Category Views ' || v_suffix)
    RETURNING id INTO v_category_id;

    INSERT INTO inventory.products (
        category_id,
        sku,
        name,
        base_price,
        cost_price,
        currency,
        is_active
    )
    VALUES (
        v_category_id,
        'SKU-VW-' || substring(v_suffix from 1 for 6),
        'Product View ' || v_suffix,
        100.00,
        60.00,
        'USD',
        true
    )
    RETURNING id INTO v_product_id;

    INSERT INTO inventory.stock_levels (
        warehouse_id,
        product_id,
        quantity,
        reserved_quantity,
        reorder_point,
        reorder_quantity
    )
    VALUES (
        v_warehouse_id,
        v_product_id,
        50,
        10,
        15,
        20
    );

    SELECT * INTO v_stock_record
    FROM inventory.v_stock_availability
    WHERE warehouse_id = v_warehouse_id AND product_id = v_product_id;

    IF v_stock_record.available_quantity <> 40 OR v_stock_record.stock_health_status <> 'HEALTHY' THEN
        RAISE EXCEPTION 'Stock availability test failed: qty=%, reserved=%, avail=%, status=%',
            v_stock_record.physical_quantity, v_stock_record.reserved_quantity,
            v_stock_record.available_quantity, v_stock_record.stock_health_status;
    END IF;

    SELECT * INTO v_val_record
    FROM inventory.v_warehouse_valuation
    WHERE warehouse_id = v_warehouse_id AND currency = 'USD';

    IF v_val_record.total_physical_units <> 50
       OR v_val_record.total_cost_value <> 3000.00
       OR v_val_record.total_retail_value <> 5000.00 THEN
        RAISE EXCEPTION 'Warehouse valuation test failed: units=%, cost=%, retail=%',
            v_val_record.total_physical_units, v_val_record.total_cost_value, v_val_record.total_retail_value;
    END IF;

    -- اصلاح شده: اضافه کردن shipping_address
    INSERT INTO orders.orders (
        order_number,
        customer_id,
        status,
        total_amount,
        currency,
        shipping_address
    )
    VALUES (
        'ORD-VW-' || substring(v_suffix from 1 for 8),
        v_customer_id,
        'CONFIRMED'::orders.order_status,
        200.00,
        'USD',
        '{"country": "IR", "city": "Tehran"}'::jsonb
    )
    RETURNING id INTO v_order_id;

    INSERT INTO payments.transactions (
        order_id,
        amount,
        currency,
        payment_method,
        status,
        gateway_reference
    )
    VALUES (
        v_order_id,
        200.00,
        'USD',
        'CREDIT_CARD'::payments.payment_method,
        'COMPLETED'::payments.payment_status,
        'GW-TEST-VW'
    )
    RETURNING id INTO v_payment_id;

    SELECT * INTO v_fin_record
    FROM orders.v_order_financial_summaries
    WHERE order_id = v_order_id;

    IF v_fin_record.total_paid <> 200.00
       OR v_fin_record.balance_due <> 0.00
       OR v_fin_record.financial_status <> 'PAID' THEN
        RAISE EXCEPTION 'Order summary PAID test failed: paid=%, due=%, status=%',
            v_fin_record.total_paid, v_fin_record.balance_due, v_fin_record.financial_status;
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
        v_order_id,
        50.00,
        'USD',
        'CREDIT_CARD'::payments.payment_method,
        'REFUNDED'::payments.payment_status,
        'GW-TEST-REF-VW'
    )
    RETURNING id INTO v_refund_id;

    SELECT * INTO v_fin_record
    FROM orders.v_order_financial_summaries
    WHERE order_id = v_order_id;

    IF v_fin_record.total_refunded <> 50.00
       OR v_fin_record.net_paid <> 150.00
       OR v_fin_record.balance_due <> 50.00
       OR v_fin_record.financial_status <> 'PARTIALLY_PAID' THEN
        RAISE EXCEPTION 'Order summary PARTIAL REFUND test failed: refunded=%, net=%, due=%, status=%',
            v_fin_record.total_refunded, v_fin_record.net_paid, v_fin_record.balance_due, v_fin_record.financial_status;
    END IF;

    RAISE NOTICE 'SUCCESS: All reporting views passed precision tests.';
END;
$test_views$;

ROLLBACK;

