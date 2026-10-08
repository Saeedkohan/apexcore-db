BEGIN;


CREATE OR REPLACE FUNCTION inventory.log_product_price_change()
    RETURNS TRIGGER
    LANGUAGE plpgsql
AS
$$
BEGIN

    IF (OLD.base_price IS DISTINCT FROM NEW.base_price OR OLD.cost_price IS DISTINCT FROM NEW.cost_price) THEN
        INSERT INTO inventory.price_history (product_id,
                                             old_base_price,
                                             new_base_price,
                                             old_cost_price,
                                             new_cost_price,
                                             reason,
                                             valid_from,
                                             currency)
        VALUES (NEW.id,
                OLD.base_price,
                NEW.base_price,
                OLD.cost_price,
                NEW.cost_price,
                'Price updated via system trigger',
                CLOCK_TIMESTAMP(),
                'USD');
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_products_log_price_change ON inventory.products;
CREATE TRIGGER trg_products_log_price_change
    AFTER UPDATE OF base_price, cost_price
    ON inventory.products
    FOR EACH ROW
EXECUTE FUNCTION inventory.log_product_price_change();

INSERT INTO core.schema_migrations (version, name, applied_at)
VALUES ('0011', '0011_create_price_history_trigger', CLOCK_TIMESTAMP());

COMMIT;

SELECT enumlabel FROM pg_enum
WHERE enumtypid = 'inventory.movement_type'::regtype
ORDER BY enumsortorder;
