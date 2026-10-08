BEGIN;

DROP TRIGGER IF EXISTS trg_stock_levels_set_updated_at ON inventory.stock_levels;
DROP TRIGGER IF EXISTS trg_warehouses_set_updated_at ON inventory.warehouses;
DROP TRIGGER IF EXISTS trg_products_set_updated_at ON inventory.products;
DROP TRIGGER IF EXISTS trg_categories_set_updated_at ON inventory.categories;

DROP FUNCTION IF EXISTS core.set_updated_at();

DELETE FROM core.schema_migrations WHERE version = '0010';

COMMIT;
