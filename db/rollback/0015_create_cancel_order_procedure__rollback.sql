BEGIN;

DROP PROCEDURE IF EXISTS orders.cancel_order(UUID, UUID, TEXT);

DELETE FROM core.schema_migrations
WHERE version = '0015';

COMMIT;
