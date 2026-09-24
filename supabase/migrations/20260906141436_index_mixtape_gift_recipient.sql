-- Cover recipient lookups and foreign-key checks independently of the owner.
create index mixtapes_recipient_idx on public.mixtapes (recipient_id);
