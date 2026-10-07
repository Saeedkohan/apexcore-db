BEGIN;

-- ۱. ایجاد جدول انبارها (Warehouses)
CREATE TABLE IF NOT EXISTS inventory.warehouses
(
    id          UUID PRIMARY KEY         DEFAULT gen_random_uuid(),
    code        VARCHAR(32)     NOT NULL,
    name        VARCHAR(128)    NOT NULL,
    address     TEXT,
    metadata    JSONB           NOT NULL DEFAULT '{}'::jsonb,
    is_active   BOOLEAN         NOT NULL DEFAULT true,

    created_at  TIMESTAMPTZ     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  TIMESTAMPTZ     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by  UUID                     REFERENCES core.users (id) ON DELETE SET NULL,
    updated_by  UUID                     REFERENCES core.users (id) ON DELETE SET NULL,

    CONSTRAINT uq_warehouses_code UNIQUE (code),
    CONSTRAINT chk_warehouses_code_format CHECK (code ~ '^[A-Z0-9_-]+$')
);

-- ایندکس جستجوی انبارهای فعال
CREATE INDEX IF NOT EXISTS idx_warehouses_active
    ON inventory.warehouses (is_active)
    WHERE is_active = true;


-- ۲. ایجاد جدول موجودی کالاها (Stock Levels)
CREATE TABLE IF NOT EXISTS inventory.stock_levels
(
    id                  UUID PRIMARY KEY         DEFAULT gen_random_uuid(),
    product_id          UUID            NOT NULL REFERENCES inventory.products (id) ON DELETE RESTRICT,
    warehouse_id        UUID            NOT NULL REFERENCES inventory.warehouses (id) ON DELETE RESTRICT,
    quantity            INTEGER         NOT NULL DEFAULT 0,
    reserved_quantity   INTEGER         NOT NULL DEFAULT 0,
    reorder_point       INTEGER         NOT NULL DEFAULT 10,
    reorder_quantity    INTEGER         NOT NULL DEFAULT 50,

    -- فیلد محاسباتی موجودی قابل فروش
    available_quantity  INTEGER GENERATED ALWAYS AS (quantity - reserved_quantity) STORED,

    created_at          TIMESTAMPTZ     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by          UUID                     REFERENCES core.users (id) ON DELETE SET NULL,

    -- قیدهای یکتایی و منطق انبارداری
    CONSTRAINT uq_stock_product_warehouse UNIQUE (product_id, warehouse_id),
    CONSTRAINT chk_stock_quantity_non_negative CHECK (quantity >= 0),
    CONSTRAINT chk_stock_reserved_non_negative CHECK (reserved_quantity >= 0),
    CONSTRAINT chk_stock_valid_reservation CHECK (quantity >= reserved_quantity),
    CONSTRAINT chk_stock_reorder_points CHECK (reorder_point >= 0 AND reorder_quantity > 0)
);

-- ایندکس‌های کلیدی stock_levels
CREATE INDEX IF NOT EXISTS idx_stock_levels_product_id
    ON inventory.stock_levels (product_id);

CREATE INDEX IF NOT EXISTS idx_stock_levels_warehouse_id
    ON inventory.stock_levels (warehouse_id);

-- ایندکس برای گزارش‌گیری و آلارم کالاهای روبه اتمام (Partial Index)
CREATE INDEX IF NOT EXISTS idx_stock_levels_low_stock
    ON inventory.stock_levels (warehouse_id, product_id)
    WHERE (quantity - reserved_quantity) <= reorder_point;


-- ۳. ثبت میگریشن در جدول لاگ
INSERT INTO core.schema_migrations (version, name)
VALUES ('0008', 'create_inventory_stock_tables')
ON CONFLICT (version) DO NOTHING;

COMMIT;
