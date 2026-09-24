
ALTER TABLE mixtapes ENABLE ROW LEVEL SECURITY;
ALTER TABLE mixtape_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE mixtape_tracks ENABLE ROW LEVEL SECURITY;

-- Public read access (for share pages)
CREATE POLICY "Anyone can read mixtapes" ON mixtapes FOR SELECT USING (true);
CREATE POLICY "Anyone can read notes" ON mixtape_notes FOR SELECT USING (true);
CREATE POLICY "Anyone can read tracks" ON mixtape_tracks FOR SELECT USING (true);

-- Service role handles writes via edge functions
-- No INSERT/UPDATE/DELETE policies needed for anon — edge functions use service_role key
;
