ALTER TABLE intake_photo ADD COLUMN captured_at TIMESTAMPTZ;
ALTER TABLE intake_photo ADD COLUMN client_id UUID;
ALTER TABLE intake_photo ADD COLUMN confirmed_at TIMESTAMPTZ;
ALTER TABLE intake_photo ADD COLUMN dismissed_at TIMESTAMPTZ;
CREATE UNIQUE INDEX idx_photo_user_client ON intake_photo(user_id, client_id) WHERE client_id IS NOT NULL;
CREATE INDEX idx_photo_pending_capture ON intake_photo(user_id, (COALESCE(captured_at, created_at)) DESC, id DESC)
    WHERE status = 'UPLOADED' AND confirmed_at IS NULL AND dismissed_at IS NULL;
UPDATE intake_photo p SET confirmed_at = i.first_saved
FROM (SELECT photo_id, user_id, min(created_at) AS first_saved FROM intake
      WHERE photo_id IS NOT NULL GROUP BY photo_id, user_id) i
WHERE p.id = i.photo_id AND p.user_id = i.user_id;
