CREATE TABLE progress_account (
    user_id UUID PRIMARY KEY REFERENCES app_user(id) ON DELETE CASCADE,
    state_json TEXT NOT NULL DEFAULT '{}',
    initialized BOOLEAN NOT NULL DEFAULT FALSE,
    revision BIGINT NOT NULL DEFAULT 0
);
CREATE TABLE progress_command (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    operation_id UUID NOT NULL,
    payload_hash VARCHAR(64) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    UNIQUE(user_id, operation_id)
);
