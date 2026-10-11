
CREATE TABLE library_snapshots (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL,
  name TEXT DEFAULT '',
  playlist_count INT DEFAULT 0,
  track_count INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_snapshots_user ON library_snapshots(user_id, created_at DESC);

CREATE TABLE snapshot_playlists (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  snapshot_id UUID NOT NULL REFERENCES library_snapshots(id) ON DELETE CASCADE,
  spotify_playlist_id TEXT NOT NULL,
  name TEXT NOT NULL,
  description TEXT,
  image_url TEXT,
  owner_id TEXT,
  owner_name TEXT,
  track_count INT DEFAULT 0,
  is_public BOOLEAN DEFAULT false
);
CREATE INDEX idx_snap_playlists ON snapshot_playlists(snapshot_id);

CREATE TABLE snapshot_tracks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  snapshot_playlist_id UUID NOT NULL REFERENCES snapshot_playlists(id) ON DELETE CASCADE,
  spotify_track_uri TEXT NOT NULL,
  track_name TEXT NOT NULL,
  artist_name TEXT NOT NULL,
  album_name TEXT,
  album_art_url TEXT,
  duration_ms INT DEFAULT 0,
  position INT DEFAULT 0
);
CREATE INDEX idx_snap_tracks ON snapshot_tracks(snapshot_playlist_id);

-- RLS
ALTER TABLE library_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE snapshot_playlists ENABLE ROW LEVEL SECURITY;
ALTER TABLE snapshot_tracks ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can read snapshots" ON library_snapshots FOR SELECT USING (true);
CREATE POLICY "Anyone can read snap playlists" ON snapshot_playlists FOR SELECT USING (true);
CREATE POLICY "Anyone can read snap tracks" ON snapshot_tracks FOR SELECT USING (true);
;
