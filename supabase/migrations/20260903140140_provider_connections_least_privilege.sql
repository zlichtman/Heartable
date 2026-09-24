-- Supabase's schema-level default privileges can grant more table capabilities
-- than Heartable needs. Restrict client roles explicitly; RLS still constrains
-- every permitted row operation to auth.uid().
revoke all on public.provider_connections from anon;
revoke all on public.provider_connections from authenticated;
grant select, insert, update on public.provider_connections to authenticated;
