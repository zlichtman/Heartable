-- Break the mixtapes <-> mixtape_shares SELECT-policy recursion without
-- SECURITY DEFINER or disabling RLS. Ownership on a share is constrained to
-- the parent mixtape, so a client cannot forge it to gain access.
alter table public.mixtapes add constraint mixtapes_id_owner_unique unique (id, owner);
alter table public.mixtape_shares add column owner uuid;
update public.mixtape_shares s set owner = m.owner
from public.mixtapes m where m.id = s.mixtape_id;
alter table public.mixtape_shares alter column owner set not null;
alter table public.mixtape_shares alter column owner set default auth.uid();
alter table public.mixtape_shares add constraint mixtape_shares_parent_owner_fkey
  foreign key (mixtape_id, owner) references public.mixtapes(id, owner) on delete cascade;
create index mixtape_shares_owner_idx on public.mixtape_shares(owner);

drop policy mxs_sel on public.mixtape_shares;
drop policy mxs_wr on public.mixtape_shares;
create policy mxs_sel on public.mixtape_shares for select to authenticated
  using (owner = (select auth.uid()) or shared_with = (select auth.uid()));
create policy mxs_ins on public.mixtape_shares for insert to authenticated
  with check (owner = (select auth.uid()));
create policy mxs_upd on public.mixtape_shares for update to authenticated
  using (owner = (select auth.uid())) with check (owner = (select auth.uid()));
create policy mxs_del on public.mixtape_shares for delete to authenticated
  using (owner = (select auth.uid()));

create policy np_del on public.now_playing for delete to authenticated
  using (user_id = (select auth.uid()));

-- A durable baseline marker prevents reinstalls (and an intentional clear)
-- from creating the same "first launch" backup again.
alter table public.profiles add column initial_backup_at timestamptz;

create function public.clear_my_music_data(expected_owner uuid)
returns void language plpgsql security invoker set search_path = '' as $$
declare caller uuid := auth.uid();
begin
  if caller is null or caller is distinct from expected_owner then
    raise exception 'Account changed. Sign in again before clearing data.' using errcode = '42501';
  end if;
  -- Parent deletes use verified ON DELETE CASCADE foreign keys. No unbounded
  -- client-side ID arrays, URL length limits, or partially committed DB wipes.
  delete from public.library_snapshots where owner = caller;
  delete from public.mixtapes where owner = caller;
  delete from public.track_skip_versions where owner = caller;
  delete from public.now_playing where user_id = caller;
  delete from public.play_log where user_id = caller;
  update public.profiles set initial_backup_at = coalesce(initial_backup_at, now()) where user_id = caller;
end;
$$;
revoke all on function public.clear_my_music_data(uuid) from public, anon;
grant execute on function public.clear_my_music_data(uuid) to authenticated;
