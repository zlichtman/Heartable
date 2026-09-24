
CREATE TABLE mixtapes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  spotify_playlist_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  theme TEXT NOT NULL DEFAULT 'rose',
  message TEXT DEFAULT '',
  share_token TEXT UNIQUE NOT NULL DEFAULT encode(gen_random_bytes(12), 'hex'),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_mixtapes_user ON mixtapes(user_id);
CREATE INDEX idx_mixtapes_share ON mixtapes(share_token);

CREATE TABLE mixtape_notes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  mixtape_id UUID NOT NULL REFERENCES mixtapes(id) ON DELETE CASCADE,
  track_id TEXT NOT NULL,
  note TEXT NOT NULL DEFAULT '',
  color TEXT NOT NULL DEFAULT 'rose',
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(mixtape_id, track_id)
);

CREATE INDEX idx_notes_mixtape ON mixtape_notes(mixtape_id);

CREATE TABLE mixtape_tracks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  mixtape_id UUID NOT NULL REFERENCES mixtapes(id) ON DELETE CASCADE,
  spotify_track_uri TEXT NOT NULL,
  position INT NOT NULL DEFAULT 0,
  track_name TEXT NOT NULL,
  artist_name TEXT NOT NULL,
  album_art_url TEXT,
  duration_ms INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_tracks_mixtape ON mixtape_tracks(mixtape_id);
;
