BEGIN;

DROP FUNCTION IF EXISTS inventory.record_stock_movement(uuid, uuid, inventory.movement_type, integer, varchar, uuid, text, uuid);

DELETE FROM core.schema_migrations WHERE version = '0012';

COMMIT;
