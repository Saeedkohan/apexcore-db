BEGIN;

DROP PROCEDURE IF EXISTS orders.cancel_order(uuid, uuid, text);
DROP PROCEDURE IF EXISTS orders.place_order(uuid, varchar, jsonb, orders.order_item_input[], text, uuid);
DROP TYPE IF EXISTS orders.order_item_input CASCADE;

COMMIT;
