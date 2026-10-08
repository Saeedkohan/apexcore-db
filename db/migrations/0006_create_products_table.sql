BEGIN;
CREATE TABLE IF NOT EXISTS inventory.products
(
    id          UUID PRIMARY KEY        DEFAULT gen_random_uuid(),
    category_id UUID           NOT NULL,
    sku         VARCHAR(64)    NOT NULL,
    name        VARCHAR(255)   NOT NULL,
    description TEXT,
    base_price  NUMERIC(12, 4) NOT NULL,
    cost_price  NUMERIC(12, 4),
    currency    VARCHAR(3)     NOT NULL DEFAULT 'USD',
    attributes  JSONB          NOT NULL DEFAULT '{}'::jsonb,
    is_active   BOOLEAN        NOT NULL DEFAULT true,

    create_at   TIMESTAMPTZ    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  TIMESTAMPTZ    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by  UUID           REFERENCES core.users (id) ON DELETE SET NULL,
    updated_by  UUID           REFERENCES core.users (id) ON DELETE SET NULL,

        CONSTRAINT fk_products_category
        FOREIGN KEY (category_id)
        REFERENCES inventory.categories(id)
        ON DELETE RESTRICT,

    -- Business Validations & Integrity
    CONSTRAINT ux_products_sku UNIQUE (sku),

    CONSTRAINT chk_products_sku_format
        CHECK (sku ~ '^[A-Z0-9_\-]+$' AND length(sku) >= 3),

    CONSTRAINT chk_products_base_price_positive
        CHECK (base_price >= 0),

    CONSTRAINT chk_products_cost_price_positive
        CHECK (cost_price IS NULL OR cost_price >= 0),

    CONSTRAINT chk_products_currency_length
        CHECK (length(currency) = 3)
);
COMMIT;