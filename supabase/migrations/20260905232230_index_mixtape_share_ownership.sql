-- Cover the composite ownership FK used for share integrity and parent cascades.
create index mixtape_shares_parent_owner_idx on public.mixtape_shares(mixtape_id, owner);
