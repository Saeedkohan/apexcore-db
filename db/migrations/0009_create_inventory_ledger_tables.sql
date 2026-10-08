BEGIN;

DO
$$
    BEGIN
        CREATE TYPE inventory.movement_type AS ENUM (
            'PURCHASE_RECEIPT',
            'SALE_DISPATCH',
            'STOCK_ADJUSTMENT',
            'RESERVATION',
            'RELEASE',
            'TRANSFER_IN',
            'TRANSFER_OUT'
            );
    EXCEPTION
        WHEN duplicate_object THEN null;
    END
$$;


CREATE TABLE IF NOT EXISTS inventory.stock_movements
(
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_id      UUID                    NOT NULL REFERENCES inventory.products (id) ON DELETE RESTRICT,
    warehouse_id    UUID                    NOT NULL REFERENCES inventory.warehouses (id) ON DELETE RESTRICT,
    movement_type   inventory.movement_type NOT NULL,
    quantity_delta  INTEGER                 NOT NULL,
    quantity_before INTEGER                 NOT NULL,
    quantity_after  INTEGER                 NOT NULL,
    reference_type  VARCHAR(64),
    reference_id    UUID,
    notes           TEXT,

    created_at      TIMESTAMPTZ             NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by      UUID                    REFERENCES core.users (id) ON DELETE SET NULL,

    CONSTRAINT chk_stock_movement_math CHECK (quantity_after = quantity_before + quantity_delta)
);


CREATE INDEX IF NOT EXISTS idx_stock_movements_product_warehouse
    ON inventory.stock_movements (product_id, warehouse_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_stock_movements_reference
    ON inventory.stock_movements (reference_type, reference_id)
    WHERE reference_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS inventory.price_history
(
    id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_id     UUID           NOT NULL REFERENCES inventory.products (id) ON DELETE CASCADE,
    old_base_price NUMERIC(12, 4) NOT NULL,
    new_base_price NUMERIC(12, 4) NOT NULL,
    old_cost_price NUMERIC(12, 4),
    new_cost_price NUMERIC(12, 4),
    currency       VARCHAR(3)     NOT NULL DEFAULT 'USD',
    reason         TEXT,

    valid_from     TIMESTAMPTZ    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by     UUID           REFERENCES core.users (id) ON DELETE SET NULL,

    CONSTRAINT chk_price_history_non_negative CHECK (new_base_price >= 0 AND (new_cost_price IS NULL OR new_cost_price >= 0))
);

CREATE INDEX IF NOT EXISTS idx_price_history_product_valid
    ON inventory.price_history (product_id, valid_from DESC);


INSERT INTO core.schema_migrations (version, name)
VALUES ('0009', 'create_inventory_ledger_tables')
ON CONFLICT (version) DO NOTHING;

COMMIT;


SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'inventory' AND table_name = 'price_history';