CREATE TABLE IF NOT EXISTS inventory.categories (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    parent_category_id UUID,
    name TEXT NOT NULL,
    description TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,

    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    created_by UUID,
    updated_by UUID

)