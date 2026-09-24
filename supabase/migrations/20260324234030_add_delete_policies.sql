
CREATE POLICY "Anyone can delete snapshots" ON library_snapshots FOR DELETE USING (true);
CREATE POLICY "Anyone can delete snap playlists" ON snapshot_playlists FOR DELETE USING (true);
CREATE POLICY "Anyone can delete snap tracks" ON snapshot_tracks FOR DELETE USING (true);
CREATE POLICY "Anyone can delete mixtapes" ON mixtapes FOR DELETE USING (true);
CREATE POLICY "Anyone can delete mixtape notes" ON mixtape_notes FOR DELETE USING (true);
CREATE POLICY "Anyone can delete mixtape tracks" ON mixtape_tracks FOR DELETE USING (true);
;
