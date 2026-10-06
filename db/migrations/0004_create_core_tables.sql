BEGIN;
CREATE TABLE IF NOT EXISTS core.users
(
    id        UUID PRIMARY KEY      DEFAULT gen_random_uuid(),
    username  VARCHAR(64)  NOT NULL,
    email     VARCHAR(255) NOT NULL,
    full_name VARCHAR(150),
    is_active BOOLEAN      NOT NULL DEFAULT true,
    create_at TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    update_at TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT ux_users_username UNIQUE (username),
    CONSTRAINT ux_users_email UNIQUE (email),
    CONSTRAINT chk_users_username_not_empty CHECK ( length(trim(username)) > 0 ),
    CONSTRAINT chk_users_email_valid CHECK ( email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$' )


);
CREATE INDEX IF NOT EXISTS ix_users_id_active ON core.users (is_active) WHERE is_active = true;

COMMIT;
