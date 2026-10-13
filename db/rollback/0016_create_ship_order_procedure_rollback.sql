BEGIN;

DROP PROCEDURE IF EXISTS orders.ship_order(uuid, uuid);

DELETE FROM core.schema_migrations
WHERE version = '0016';

COMMIT;
