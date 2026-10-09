BEGIN;

CREATE TABLE IF NOT EXISTS core.schema_migrations (
    version     VARCHAR(4) PRIMARY KEY,
    name        VARCHAR(128) NOT NULL,
    applied_at  TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO core.schema_migrations (version, name) VALUES
    ('0001', 'init'),
    ('0002', 'create_schemas'),
    ('0003', 'create_extensions'),
    ('0004', 'create_core_tables'),
    ('0005', 'create_inventory_tables'),
    ('0006', 'create_products_table')
ON CONFLICT (version) DO NOTHING;

COMMIT;
