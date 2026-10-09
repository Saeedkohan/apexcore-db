BEGIN;

DROP TABLE IF EXISTS orders.order_items CASCADE;
DROP TABLE IF EXISTS orders.orders CASCADE;
DROP TYPE IF EXISTS orders.order_status CASCADE;

DELETE FROM core.schema_migrations WHERE version = '0013';

COMMIT;
