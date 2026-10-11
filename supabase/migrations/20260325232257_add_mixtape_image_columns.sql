
ALTER TABLE mixtapes ADD COLUMN IF NOT EXISTS cover_image_url text;
ALTER TABLE mixtapes ADD COLUMN IF NOT EXISTS background_image_url text;
ALTER TABLE mixtapes ADD COLUMN IF NOT EXISTS recipient_name text;
ALTER TABLE mixtapes ADD COLUMN IF NOT EXISTS name text DEFAULT '';
ALTER TABLE mixtape_notes ADD COLUMN IF NOT EXISTS image_url text;
ALTER TABLE mixtape_tracks ADD COLUMN IF NOT EXISTS image_url text;
;
