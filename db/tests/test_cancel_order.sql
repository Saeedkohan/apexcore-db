ROLLBACK;

BEGIN;

INSERT INTO core.users (
    id, username, email, password_hash, is_active, is_admin, created_at, updated_at
) VALUES (
    'a0000000-0000-0000-0000-000000000001',
    'test_actor',
    'test_actor@apexcore.test',
    'hash_placeholder',
    TRUE,
    FALSE,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
);

INSERT INTO inventory.categories (
    id, parent_category_id, name, description, is_active, created_at, updated_at, created_by, updated_by
) VALUES (
    'b0000000-0000-0000-0000-000000000001',
    NULL,
    'Test Category',
    'Category for testing',
    TRUE,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP,
    'a0000000-0000-0000-0000-000000000001',
    'a0000000-0000-0000-0000-000000000001'
);

INSERT INTO inventory.warehouses (
    id, code, name, address, metadata, is_active, created_at, updated_at, created_by, updated_by
) VALUES (
    'c0000000-0000-0000-0000-000000000001',
    'WH-TEST-01',
    'Test Warehouse',
    'Test Address',
    '{}'::JSONB,
    TRUE,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP,
    'a0000000-0000-0000-0000-000000000001',
    'a0000000-0000-0000-0000-000000000001'
);

INSERT INTO inventory.products (
    id, category_id, sku, name, description, base_price, cost_price, currency, attributes, is_active, create_at, updated_at, created_by, updated_by
) VALUES (
    'd0000000-0000-0000-0000-000000000001',
    'b0000000-0000-0000-0000-000000000001',
    'SKU-TEST-01',
    'Test Product',
    'Test Product Description',
    100.0000,
    50.0000,
    'USD',
    '{}'::JSONB,
    TRUE,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP,
    'a0000000-0000-0000-0000-000000000001',
    'a0000000-0000-0000-0000-000000000001'
);

INSERT INTO inventory.stock_levels (
    id, product_id, warehouse_id, quantity, reserved_quantity, reorder_point, reorder_quantity, created_at, updated_at, updated_by
) VALUES (
    'e0000000-0000-0000-0000-000000000001',
    'd0000000-0000-0000-0000-000000000001',
    'c0000000-0000-0000-0000-000000000001',
    100,
    0,
    10,
    20,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP,
    'a0000000-0000-0000-0000-000000000001'
);

-- CALL orders.place_order(
--     p_customer_id => 'a0000000-0000-0000-0000-000000000001'::UUID,
--     p_order_number => 'ORD-TEST-001',
--     p_shipping_address => '{"country": "IR", "city": "Tehran"}'::JSONB,
--     p_items => ARRAY[ROW('d0000000-0000-0000-0000-000000000001'::UUID, 'c0000000-0000-0000-0000-000000000001'::UUID, 2, 100.0000)::orders.order_item_input],
--     p_order_id => NULL,
--     p_notes => 'Step-by-step test order'
-- );


ROLLBACK;

SELECT pg_get_constraintdef(oid) AS constraint_definition
FROM pg_constraint
WHERE conname = 'chk_stock_movement_math';
















ROLLBACK ;




BEGIN;

-- 1. Actor (core.users)
INSERT INTO core.users (id, username, email, password_hash)
VALUES ('a0000000-0000-0000-0000-000000000001', 'test_actor', 'test@apex.test', 'hash');

-- 2. Warehouse (inventory.warehouses)
INSERT INTO inventory.warehouses (id, code, name, created_by, updated_by)
VALUES ('e0000000-0000-0000-0000-000000000001', 'WH-MAIN', 'Main Warehouse', 'a0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001');

-- 3. Category (inventory.categories)
INSERT INTO inventory.categories (id, name, created_by, updated_by)
VALUES ('b0000000-0000-0000-0000-000000000001', 'Test Cat', 'a0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001');

-- 4. Product (inventory.products)
INSERT INTO inventory.products (id, category_id, sku, name, base_price, cost_price, created_by, updated_by)
VALUES ('d0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'SKU-01', 'Test Prod', 100, 50, 'a0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001');

-- 5. Stock Level (inventory.stock_levels)
INSERT INTO inventory.stock_levels (id, product_id, warehouse_id, quantity, reserved_quantity, updated_by)
VALUES (gen_random_uuid(), 'd0000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000001', 100, 2, 'a0000000-0000-0000-0000-000000000001');

-- 6. Order (orders.orders) - shipping_address included
INSERT INTO orders.orders (id, order_number, customer_id, status, total_amount, currency, shipping_address)
VALUES (
    'f0000000-0000-0000-0000-000000000001',
    'ORD-001',
    'a0000000-0000-0000-0000-000000000001',
    'PENDING',
    200,
    'USD',
    '{"country": "IR", "city": "Tehran"}'::jsonb
);

-- 7. Order Item (orders.order_items)
INSERT INTO orders.order_items (id, order_id, product_id, quantity, unit_price)
VALUES ('f1000000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001', 2, 100);

-- 8. Cancel Order Procedure Execution
CALL orders.cancel_order(
    p_order_id => 'f0000000-0000-0000-0000-000000000001'::UUID,
    p_actor_id => 'a0000000-0000-0000-0000-000000000001'::UUID,
    p_cancellation_reason => 'Test cancel'
);

-- 9. Verification
SELECT id, status FROM orders.orders WHERE id = 'f0000000-0000-0000-0000-000000000001';

SELECT product_id, warehouse_id, quantity, reserved_quantity, available_quantity
FROM inventory.stock_levels
WHERE product_id = 'd0000000-0000-0000-0000-000000000001';


   SELECT id, movement_type, quantity_delta, quantity_before, quantity_after, created_at
   FROM inventory.stock_movements
   WHERE product_id = 'd0000000-0000-0000-0000-000000000001'
   ORDER BY created_at DESC;

ROLLBACK ;
