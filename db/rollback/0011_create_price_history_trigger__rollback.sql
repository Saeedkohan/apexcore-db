BEGIN;

DROP TRIGGER IF EXISTS trg_products_log_price_change ON inventory.products;
DROP FUNCTION IF EXISTS inventory.log_product_price_change();
DELETE
FROM core.schema_migrations
WHERE version = '0011';

COMMIT;
