ALTER TABLE mixtape_notes
  ADD COLUMN timestamp_ms integer DEFAULT NULL,
  ADD COLUMN emoji text DEFAULT NULL,
  ADD COLUMN visual_type text DEFAULT NULL;

CREATE INDEX idx_mixtape_notes_timestamp
  ON mixtape_notes(mixtape_id, track_id, timestamp_ms);;
