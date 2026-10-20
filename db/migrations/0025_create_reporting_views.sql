DROP VIEW IF EXISTS orders.v_order_financial_summaries CASCADE;
DROP VIEW IF EXISTS inventory.v_stock_availability CASCADE;
DROP VIEW IF EXISTS inventory.v_warehouse_valuation CASCADE;

CREATE OR REPLACE VIEW orders.v_order_financial_summaries AS
SELECT o.id                                                                                                 AS order_id,
       o.order_number,
       o.customer_id,
       o.status                                                                                             AS order_status,
       o.currency,
       o.total_amount,
       COALESCE(p.total_paid, 0.00)::numeric(12, 2)                                                         AS total_paid,
       COALESCE(p.total_refunded, 0.00)::numeric(12, 2)                                                     AS total_refunded,
       (COALESCE(p.total_paid, 0.00) - COALESCE(p.total_refunded, 0.00))::numeric(12, 2)                    AS net_paid,
       (o.total_amount -
        (COALESCE(p.total_paid, 0.00) - COALESCE(p.total_refunded, 0.00)))::numeric(12, 2)                  AS balance_due,
       CASE
           WHEN (COALESCE(p.total_paid, 0.00) - COALESCE(p.total_refunded, 0.00)) <= 0.00 AND
                COALESCE(p.total_refunded, 0.00) > 0.00 THEN 'REFUNDED'
           WHEN (COALESCE(p.total_paid, 0.00) - COALESCE(p.total_refunded, 0.00)) <= 0.00 THEN 'UNPAID'
           WHEN (COALESCE(p.total_paid, 0.00) - COALESCE(p.total_refunded, 0.00)) < o.total_amount THEN 'PARTIALLY_PAID'
           WHEN (COALESCE(p.total_paid, 0.00) - COALESCE(p.total_refunded, 0.00)) = o.total_amount THEN 'PAID'
           ELSE 'OVERPAID'
           END                                                                                              AS financial_status,
       o.created_at,
       o.updated_at
FROM orders.orders o
         LEFT JOIN (SELECT order_id,
                           SUM(CASE
                                   WHEN status = 'COMPLETED'::payments.payment_status THEN amount
                                   ELSE 0.00 END)                                                                AS total_paid,
                           SUM(CASE
                                   WHEN status = 'REFUNDED'::payments.payment_status THEN amount
                                   ELSE 0.00 END)                                                                AS total_refunded
                    FROM payments.transactions
                    GROUP BY order_id) p ON o.id = p.order_id;

CREATE OR REPLACE VIEW inventory.v_stock_availability AS
SELECT sl.id         AS stock_level_id,
       sl.warehouse_id,
       w.code        AS warehouse_code,
       w.name        AS warehouse_name,
       sl.product_id,
       p.sku,
       p.name        AS product_name,
       sl.quantity   AS physical_quantity,
       sl.reserved_quantity,
       sl.available_quantity,
       sl.reorder_point,
       sl.reorder_quantity,
       CASE
           WHEN sl.available_quantity <= 0 THEN 'OUT_OF_STOCK'
           WHEN sl.reorder_point IS NOT NULL AND sl.available_quantity <= sl.reorder_point THEN 'CRITICAL'
           ELSE 'HEALTHY'
           END       AS stock_health_status,
       w.is_active   AS is_warehouse_active,
       p.is_active   AS is_product_active,
       sl.updated_at AS last_stock_update
FROM inventory.stock_levels sl
         JOIN inventory.warehouses w ON sl.warehouse_id = w.id
         JOIN inventory.products p ON sl.product_id = p.id;

CREATE OR REPLACE VIEW inventory.v_warehouse_valuation AS
SELECT w.id                                                                            AS warehouse_id,
       w.code                                                                          AS warehouse_code,
       w.name                                                                          AS warehouse_name,
       p.currency,
       COUNT(DISTINCT sl.product_id)                                                   AS total_distinct_products,
       COALESCE(SUM(sl.quantity), 0)::bigint                                           AS total_physical_units,
       COALESCE(SUM(sl.reserved_quantity), 0)::bigint                                  AS total_reserved_units,
       COALESCE(SUM(sl.available_quantity), 0)::bigint                                 AS total_available_units,
       COALESCE(SUM(sl.quantity * COALESCE(p.cost_price, 0.00)), 0.00)::numeric(16, 2) AS total_cost_value,
       COALESCE(SUM(sl.quantity * p.base_price), 0.00)::numeric(16, 2)                 AS total_retail_value,
       COALESCE(SUM(sl.available_quantity * p.base_price), 0.00)::numeric(16, 2)       AS total_available_retail_value
FROM inventory.warehouses w
         LEFT JOIN inventory.stock_levels sl ON w.id = sl.warehouse_id
         LEFT JOIN inventory.products p ON sl.product_id = p.id
GROUP BY w.id, w.code, w.name, p.currency;
