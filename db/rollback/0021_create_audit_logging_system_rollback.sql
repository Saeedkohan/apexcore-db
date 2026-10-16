DROP TRIGGER IF EXISTS trg_audit_orders ON orders.orders;
DROP TRIGGER IF EXISTS trg_audit_products ON inventory.products;
DROP SCHEMA IF EXISTS audit CASCADE;
