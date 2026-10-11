-- Mixtapes are sent to friends inside the app; public share links are gone.
drop function public.read_shared_mixtape(text);
drop function public.manage_mixtape_link(uuid, text);
drop function heartable_private.manage_mixtape_link(uuid, text);
drop table heartable_private.mixtape_links;
drop schema heartable_private;
