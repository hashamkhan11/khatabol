-- Archiving hides a party or cloth type from lists and totals. Hiding one that
-- still has money or stock on it would make "total to receive / to pay" and
-- stock value wrong, so it is only allowed once the khata or stock is at zero.

create or replace function set_party_archived(p_id uuid, p_archived boolean) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_owner uuid := _current_owner();
begin
  if p_archived and (select coalesce(sum(amount), 0) from khata_entries
                     where party_id = p_id and owner_id = v_owner) <> 0 then
    raise exception 'settle the khata before archiving this party';
  end if;
  update parties
  set archived_at = case when p_archived then coalesce(archived_at, now()) end
  where id = p_id and owner_id = v_owner;
  if not found then
    raise exception 'party not found';
  end if;
end $$;

create or replace function set_item_archived(p_id uuid, p_archived boolean) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_owner uuid := _current_owner();
begin
  if p_archived and coalesce((select s.qty_after from _stock_valuation(v_owner) s
                              where s.item_id = p_id order by s.seq desc limit 1), 0) <> 0 then
    raise exception 'stock must be zero before archiving this cloth type';
  end if;
  update items set archived_at = case when p_archived then coalesce(archived_at, now()) end
  where id = p_id and owner_id = v_owner;
  if not found then
    raise exception 'cloth type not found';
  end if;
end $$;
