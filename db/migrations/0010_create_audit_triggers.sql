BEGIN;

CREATE OR REPLACE FUNCTION core.set_updated_at()
    RETURNS TRIGGER
    LANGUAGE plpgsql
AS
$$
BEGIN
    NEW.updated_at = CLOCK_TIMESTAMP();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_categories_set_updated_at ON inventory.categories;
CREATE TRIGGER trg_categories_set_updated_at
    BEFORE UPDATE
    ON inventory.categories
    FOR EACH ROW
EXECUTE FUNCTION core.set_updated_at();

DROP TRIGGER IF EXISTS trg_products_set_updated_at ON inventory.products;
CREATE TRIGGER trg_products_set_updated_at
    BEFORE UPDATE
    ON inventory.products
    FOR EACH ROW
EXECUTE FUNCTION core.set_updated_at();

DROP TRIGGER IF EXISTS trg_warehouses_set_updated_at ON inventory.warehouses;
CREATE TRIGGER trg_warehouses_set_updated_at
    BEFORE UPDATE
    ON inventory.warehouses
    FOR EACH ROW
EXECUTE FUNCTION core.set_updated_at();

DROP TRIGGER IF EXISTS trg_stock_levels_set_updated_at ON inventory.stock_levels;
CREATE TRIGGER trg_stock_levels_set_updated_at
    BEFORE UPDATE
    ON inventory.stock_levels
    FOR EACH ROW
EXECUTE FUNCTION core.set_updated_at();

INSERT INTO core.schema_migrations (version, name, applied_at)
VALUES ('0010', '0010_create_audit_triggers', CLOCK_TIMESTAMP());

COMMIT;
