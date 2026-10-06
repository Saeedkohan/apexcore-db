BEGIN;

CREATE TABLE IF NOT EXISTS inventory.categories
(
    id                 UUID PRIMARY KEY      DEFAULT gen_random_uuid(),
    parent_category_id UUID,
    name               VARCHAR(128) NOT NULL,
    description        TEXT,
    is_active          BOOLEAN      NOT NULL DEFAULT true,
    created_at         TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at         TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by         UUID         REFERENCES core.users (id) ON DELETE SET NULL,
    updated_by         UUID         REFERENCES core.users (id) ON DELETE SET NULL,

    CONSTRAINT fk_categories_parent
        FOREIGN KEY (parent_category_id)
            REFERENCES inventory.categories (id)
            ON DELETE RESTRICT,

    CONSTRAINT chk_categories_name_not_empty
        CHECK (length(trim(name)) > 0)
);

CREATE INDEX IF NOT EXISTS ix_categories_parent_id
    ON inventory.categories (parent_category_id);

CREATE INDEX IF NOT EXISTS ix_categories_is_active
    ON inventory.categories (is_active)
    WHERE is_active = true;

CREATE UNIQUE INDEX IF NOT EXISTS ux_categories_root_name
    ON inventory.categories (lower(trim(name)))
    WHERE parent_category_id IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS ux_categories_sibling_name
    ON inventory.categories (parent_category_id, lower(trim(name)))
    WHERE parent_category_id IS NOT NULL;

COMMIT;
