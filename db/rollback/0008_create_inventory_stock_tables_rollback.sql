BEGIN;

DROP TABLE IF EXISTS inventory.stock_levels CASCADE;
DROP TABLE IF EXISTS inventory.warehouses CASCADE;

DELETE FROM core.schema_migrations WHERE version = '0008';

COMMIT;
