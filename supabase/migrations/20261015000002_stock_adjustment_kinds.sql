-- Stock adjustments say why stock changed, so each cloth type gets a stock
-- register that reads like the paper one: opening stock, found on recount,
-- wastage, shortage, own use, samples.

create type stock_adjustment_kind as enum (
  'opening', 'found', 'other_in',                   -- stock comes in
  'wastage', 'shortage', 'own_use', 'sample', 'other_out'  -- stock goes out
);

alter table stock_adjustments add column kind stock_adjustment_kind;

-- Existing rows: additions were opening stock, removals were wastage.
alter table stock_adjustments disable trigger stock_adj_cancel_only;
update stock_adjustments set kind = case when weight_kg > 0 then 'opening' else 'wastage' end::stock_adjustment_kind;
alter table stock_adjustments enable trigger stock_adj_cancel_only;

alter table stock_adjustments
  alter column kind set not null,
  add constraint adjustment_direction_matches_kind
    check ((weight_kg > 0) = (kind in ('opening', 'found', 'other_in')));

drop function record_stock_adjustment(uuid, numeric, numeric, date, text);

-- p_weight_kg is always positive; p_kind decides whether stock comes in or goes out.
-- Stock coming in needs a cost per kg. Stock going out is valued at average cost
-- and counted as a loss in the profit report.
create function record_stock_adjustment(
  p_item_id uuid, p_kind stock_adjustment_kind, p_weight_kg numeric,
  p_cost_per_kg numeric default null, p_date date default null, p_reason text default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_owner uuid := _current_owner();
  v_in boolean := p_kind in ('opening', 'found', 'other_in');
  v_id uuid;
begin
  perform _item(v_owner, p_item_id);
  if p_kind is null then
    raise exception 'kind is required';
  end if;
  if coalesce(p_weight_kg, 0) <= 0 then
    raise exception 'weight must be positive';
  end if;
  if v_in and p_cost_per_kg is null then
    raise exception 'stock coming in needs a cost per kg';
  end if;

  insert into stock_adjustments (owner_id, item_id, kind, adj_date, weight_kg, cost_per_kg, reason)
  values (v_owner, p_item_id, p_kind, coalesce(p_date, _today()),
          case when v_in then p_weight_kg else -p_weight_kg end,
          case when v_in then p_cost_per_kg end,
          nullif(trim(p_reason), ''))
  returning id into v_id;
  return v_id;
end $$;

-- One cloth type's stock register, oldest first: every purchase, sale and
-- adjustment with the kg in hand after it. Cancelled moves are left out.
-- kind is the deal kind ('purchase', 'sale') or the adjustment kind.
create function stock_history(p_item_id uuid)
returns table (move_date date, deal_id uuid, adjustment_id uuid, kind text, party_name text,
               weight_kg numeric, rate numeric, reason text, qty_after numeric, avg_cost_after numeric)
language sql stable security definer set search_path = public as $$
  select v.move_date, v.deal_id, v.adjustment_id,
         coalesce(d.kind::text, a.kind::text),
         p.name,
         v.weight_kg,
         coalesce(d.rate, a.cost_per_kg),
         a.reason,
         v.qty_after,
         v.avg_cost_after
  from _stock_valuation(_current_owner()) v
  left join deals d             on d.id = v.deal_id
  left join parties p           on p.id = d.party_id
  left join stock_adjustments a on a.id = v.adjustment_id
  where v.item_id = p_item_id
  order by v.seq
$$;

revoke execute on function
  record_stock_adjustment(uuid, stock_adjustment_kind, numeric, numeric, date, text),
  stock_history(uuid)
from public, anon;

grant execute on function
  record_stock_adjustment(uuid, stock_adjustment_kind, numeric, numeric, date, text),
  stock_history(uuid)
to authenticated;
