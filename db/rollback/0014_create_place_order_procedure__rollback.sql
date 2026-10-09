BEGIN;

DROP PROCEDURE IF EXISTS orders.place_order;

DROP TYPE IF EXISTS orders.order_item_input CASCADE;

DELETE
FROM core.schema_migrations
WHERE version = '0014';

COMMIT;
