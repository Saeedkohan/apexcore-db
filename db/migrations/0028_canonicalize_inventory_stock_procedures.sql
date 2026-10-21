BEGIN;

DROP PROCEDURE IF EXISTS inventory.receive_stock(IN uuid, IN uuid, IN numeric, IN uuid, IN text);
DROP PROCEDURE IF EXISTS inventory.transfer_stock(IN uuid, IN uuid, IN uuid, IN integer, IN uuid, IN text);

COMMIT;
