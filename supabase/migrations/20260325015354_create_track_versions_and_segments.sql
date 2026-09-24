CREATE TABLE track_versions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id text NOT NULL,
  track_uri text NOT NULL,
  version_name text NOT NULL DEFAULT 'Original',
  mixtape_id uuid REFERENCES mixtapes(id) ON DELETE SET NULL,
  is_original boolean NOT NULL DEFAULT false,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE TABLE track_segments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  version_id uuid NOT NULL REFERENCES track_versions(id) ON DELETE CASCADE,
  start_ms integer NOT NULL,
  end_ms integer NOT NULL,
  action text NOT NULL DEFAULT 'skip' CHECK (action IN ('skip', 'keep')),
  position integer NOT NULL DEFAULT 0
);

ALTER TABLE track_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE track_segments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Public read track_versions" ON track_versions FOR SELECT USING (true);
CREATE POLICY "Public insert track_versions" ON track_versions FOR INSERT WITH CHECK (true);
CREATE POLICY "Public update track_versions" ON track_versions FOR UPDATE USING (true);
CREATE POLICY "Public delete track_versions" ON track_versions FOR DELETE USING (true);

CREATE POLICY "Public read track_segments" ON track_segments FOR SELECT USING (true);
CREATE POLICY "Public insert track_segments" ON track_segments FOR INSERT WITH CHECK (true);
CREATE POLICY "Public update track_segments" ON track_segments FOR UPDATE USING (true);
CREATE POLICY "Public delete track_segments" ON track_segments FOR DELETE USING (true);

CREATE INDEX idx_track_versions_user ON track_versions(user_id, track_uri);
CREATE INDEX idx_track_segments_version ON track_segments(version_id);;
