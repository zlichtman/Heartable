-- Add INSERT policies for tables that edge functions write to via service role
-- (service role bypasses RLS, but anon/frontend needs these for direct writes)

-- library_snapshots: UPDATE needed for rename feature from frontend
CREATE POLICY "Anyone can update snapshots" ON public.library_snapshots FOR UPDATE USING (true) WITH CHECK (true);
CREATE POLICY "Anyone can insert snapshots" ON public.library_snapshots FOR INSERT WITH CHECK (true);

-- snapshot_playlists
CREATE POLICY "Anyone can insert snap playlists" ON public.snapshot_playlists FOR INSERT WITH CHECK (true);
CREATE POLICY "Anyone can update snap playlists" ON public.snapshot_playlists FOR UPDATE USING (true) WITH CHECK (true);

-- snapshot_tracks
CREATE POLICY "Anyone can insert snap tracks" ON public.snapshot_tracks FOR INSERT WITH CHECK (true);

-- mixtapes
CREATE POLICY "Anyone can insert mixtapes" ON public.mixtapes FOR INSERT WITH CHECK (true);
CREATE POLICY "Anyone can update mixtapes" ON public.mixtapes FOR UPDATE USING (true) WITH CHECK (true);

-- mixtape_notes
CREATE POLICY "Anyone can insert mixtape notes" ON public.mixtape_notes FOR INSERT WITH CHECK (true);
CREATE POLICY "Anyone can update mixtape notes" ON public.mixtape_notes FOR UPDATE USING (true) WITH CHECK (true);

-- mixtape_tracks
CREATE POLICY "Anyone can insert mixtape tracks" ON public.mixtape_tracks FOR INSERT WITH CHECK (true);
CREATE POLICY "Anyone can update mixtape tracks" ON public.mixtape_tracks FOR UPDATE USING (true) WITH CHECK (true);;
