BEGIN;

DROP PROCEDURE IF EXISTS orders.deliver_order(uuid, text, uuid);

DELETE
FROM core.schema_migrations
WHERE version = '0017';

COMMIT;
