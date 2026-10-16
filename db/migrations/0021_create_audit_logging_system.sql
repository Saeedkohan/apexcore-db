CREATE SCHEMA IF NOT EXISTS audit;

CREATE TABLE IF NOT EXISTS audit.audit_logs (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    schema_name VARCHAR(64) NOT NULL,
    table_name VARCHAR(64) NOT NULL,
    record_id VARCHAR(128) NOT NULL,
    action VARCHAR(10) NOT NULL,
    old_data JSONB,
    new_data JSONB,
    changed_by UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT chk_audit_action CHECK (action IN ('INSERT', 'UPDATE', 'DELETE'))
);

CREATE INDEX IF NOT EXISTS idx_audit_logs_table_record
ON audit.audit_logs (schema_name, table_name, record_id);

CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at
ON audit.audit_logs (created_at DESC);

CREATE OR REPLACE FUNCTION audit.log_table_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_record_id VARCHAR(128);
    v_actor_id UUID;
    v_old_data JSONB;
    v_new_data JSONB;
BEGIN
    IF TG_OP = 'INSERT' THEN
        v_new_data := to_jsonb(NEW);
        v_record_id := COALESCE(v_new_data->>'id', 'UNKNOWN');
        v_actor_id := NULLIF(COALESCE(v_new_data->>'created_by', v_new_data->>'user_id'), '')::UUID;

        INSERT INTO audit.audit_logs (
            schema_name,
            table_name,
            record_id,
            action,
            old_data,
            new_data,
            changed_by,
            created_at
        ) VALUES (
            TG_TABLE_SCHEMA,
            TG_TABLE_NAME,
            v_record_id,
            'INSERT',
            NULL,
            v_new_data,
            v_actor_id,
            clock_timestamp()
        );

        RETURN NEW;

    ELSIF TG_OP = 'UPDATE' THEN
        v_old_data := to_jsonb(OLD);
        v_new_data := to_jsonb(NEW);
        v_record_id := COALESCE(v_new_data->>'id', v_old_data->>'id', 'UNKNOWN');
        v_actor_id := NULLIF(COALESCE(v_new_data->>'updated_by', v_new_data->>'created_by'), '')::UUID;

        INSERT INTO audit.audit_logs (
            schema_name,
            table_name,
            record_id,
            action,
            old_data,
            new_data,
            changed_by,
            created_at
        ) VALUES (
            TG_TABLE_SCHEMA,
            TG_TABLE_NAME,
            v_record_id,
            'UPDATE',
            v_old_data,
            v_new_data,
            v_actor_id,
            clock_timestamp()
        );

        RETURN NEW;

    ELSIF TG_OP = 'DELETE' THEN
        v_old_data := to_jsonb(OLD);
        v_record_id := COALESCE(v_old_data->>'id', 'UNKNOWN');
        v_actor_id := NULLIF(COALESCE(v_old_data->>'created_by', v_old_data->>'user_id'), '')::UUID;

        INSERT INTO audit.audit_logs (
            schema_name,
            table_name,
            record_id,
            action,
            old_data,
            new_data,
            changed_by,
            created_at
        ) VALUES (
            TG_TABLE_SCHEMA,
            TG_TABLE_NAME,
            v_record_id,
            'DELETE',
            v_old_data,
            NULL,
            v_actor_id,
            clock_timestamp()
        );

        RETURN OLD;
    END IF;

    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_audit_products ON inventory.products;
CREATE TRIGGER trg_audit_products
AFTER INSERT OR UPDATE OR DELETE ON inventory.products
FOR EACH ROW EXECUTE FUNCTION audit.log_table_change();

DROP TRIGGER IF EXISTS trg_audit_orders ON orders.orders;
CREATE TRIGGER trg_audit_orders
AFTER INSERT OR UPDATE OR DELETE ON orders.orders
FOR EACH ROW EXECUTE FUNCTION audit.log_table_change();
