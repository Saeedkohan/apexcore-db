DROP PROCEDURE IF EXISTS payments.process_payment(uuid, numeric, payments.payment_method, boolean, uuid, varchar, uuid);

DROP TABLE IF EXISTS payments.transactions CASCADE;

DROP TYPE IF EXISTS payments.payment_status CASCADE;

DROP TYPE IF EXISTS payments.payment_method CASCADE;

DROP SCHEMA IF EXISTS payments CASCADE;
