-- All writes and reports. The app and the WhatsApp bot call these functions;
-- they never write to tables directly.
--
-- Functions starting with "_" are internal helpers and cannot be called by
-- clients. Public functions run as SECURITY DEFINER and always scope every
-- read and write to the signed-in user (auth.uid()).

-- ==================== HELPERS ====================

-- The business works in Pakistan time; the database server runs in UTC.
create function _today() returns date
language sql stable as $$
  select (now() at time zone 'Asia/Karachi')::date
$$;

create function _current_owner() returns uuid
language plpgsql stable as $$
declare
  v_owner uuid := auth.uid();
begin
  if v_owner is null then
    raise exception 'Not signed in';
  end if;
  return v_owner;
end $$;

create function _party(p_owner uuid, p_id uuid, p_label text default 'party') returns parties
language plpgsql stable as $$
declare
  r parties;
begin
  if p_id is null then
    raise exception '% is required', p_label;
  end if;
  select * into r from parties where id = p_id and owner_id = p_owner;
  if not found then
    raise exception '% not found', p_label;
  end if;
  if r.archived_at is not null then
    raise exception '% "%" is archived', p_label, r.name;
  end if;
  return r;
end $$;

create function _item(p_owner uuid, p_id uuid) returns items
language plpgsql stable as $$
declare
  r items;
begin
  select * into r from items where id = p_id and owner_id = p_owner;
  if not found then
    raise exception 'cloth type not found';
  end if;
  if r.archived_at is not null then
    raise exception 'cloth type "%" is archived', r.name_en;
  end if;
  return r;
end $$;

create function _add_entry(
  p_owner uuid, p_party uuid, p_date date, p_amount numeric, p_kind entry_kind, p_note text,
  p_source entry_source, p_source_ref text,
  p_deal uuid default null, p_expense uuid default null, p_method payment_method default null
) returns uuid
language sql as $$
  insert into khata_entries (owner_id, party_id, entry_date, amount, kind, note, source, source_ref,
                             deal_id, expense_id, method)
  values (p_owner, p_party, p_date, round(p_amount, 2), p_kind, p_note, p_source, p_source_ref,
          p_deal, p_expense, p_method)
  returning id
$$;

-- Writes a reversing line for every not-yet-reversed entry matching the filter.
-- Reversals keep the original date so past balances and statements are corrected.
create function _reverse_entries(p_owner uuid, p_deal uuid, p_expense uuid, p_entry uuid,
                                 p_reason text, p_source entry_source) returns void
language sql as $$
  insert into khata_entries (owner_id, party_id, entry_date, amount, kind, note, method,
                             deal_id, expense_id, reverses_id, source)
  select e.owner_id, e.party_id, e.entry_date, -e.amount, 'reversal',
         'Cancelled: ' || coalesce(e.note, e.kind::text) || coalesce(' (' || p_reason || ')', ''),
         e.method, e.deal_id, e.expense_id, e.id, p_source
  from khata_entries e
  where e.owner_id = p_owner
    and e.kind <> 'reversal'
    and (p_deal is null or e.deal_id = p_deal)
    and (p_expense is null or e.expense_id = p_expense)
    and (p_entry is null or e.id = p_entry)
    and not exists (select 1 from khata_entries r where r.reverses_id = e.id)
$$;

-- ==================== PARTIES & CLOTH TYPES ====================

-- p_opening_balance: positive = they already owe us, negative = we already owe them.
create function create_party(
  p_name text,
  p_type party_type default 'other',
  p_phone text default null,
  p_whatsapp text default null,
  p_city text default null,
  p_notes text default null,
  p_opening_balance numeric default 0,
  p_opening_date date default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_owner uuid := _current_owner();
  v_id uuid;
begin
  insert into parties (owner_id, name, type, phone, whatsapp, city, notes)
  values (v_owner, trim(p_name), p_type, p_phone, p_whatsapp, p_city, p_notes)
  returning id into v_id;

  if coalesce(p_opening_balance, 0) <> 0 then
    perform _add_entry(v_owner, v_id, coalesce(p_opening_date, _today()), p_opening_balance,
                       'opening', 'Opening balance', 'app', null);
  end if;
  return v_id;
end $$;

create function update_party(
  p_id uuid, p_name text, p_type party_type, p_phone text, p_whatsapp text, p_city text, p_notes text
) returns void
language plpgsql security definer set search_path = public as $$
begin
  update parties
  set name = trim(p_name), type = p_type, phone = p_phone, whatsapp = p_whatsapp, city = p_city, notes = p_notes
  where id = p_id and owner_id = _current_owner();
  if not found then
    raise exception 'party not found';
  end if;
end $$;

-- Archived parties keep their history but cannot get new entries.
create function set_party_archived(p_id uuid, p_archived boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  update parties
  set archived_at = case when p_archived then coalesce(archived_at, now()) end
  where id = p_id and owner_id = _current_owner();
  if not found then
    raise exception 'party not found';
  end if;
end $$;

create function create_item(p_name_en text, p_name_ur text default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
begin
  insert into items (owner_id, name_en, name_ur)
  values (_current_owner(), trim(p_name_en), nullif(trim(p_name_ur), ''))
  returning id into v_id;
  return v_id;
end $$;

create function update_item(p_id uuid, p_name_en text, p_name_ur text) returns void
language plpgsql security definer set search_path = public as $$
begin
  update items set name_en = trim(p_name_en), name_ur = nullif(trim(p_name_ur), '')
  where id = p_id and owner_id = _current_owner();
  if not found then
    raise exception 'cloth type not found';
  end if;
end $$;

create function set_item_archived(p_id uuid, p_archived boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  update items set archived_at = case when p_archived then coalesce(archived_at, now()) end
  where id = p_id and owner_id = _current_owner();
  if not found then
    raise exception 'cloth type not found';
  end if;
end $$;

-- ==================== DEALS ====================

-- Records a purchase, sale or commission deal and all its khata lines.
--
-- p (jsonb):
--   kind              'purchase' | 'sale' | 'commission'            (required)
--   deal_date         'YYYY-MM-DD'                                  (default: today)
--   party_id          supplier / buyer / seller                    (required)
--   buyer_id          buyer, commission deals only
--   item_id           cloth type (required for purchase and sale)
--   weight_kg, rate   (required for purchase and sale)
--   goods_through_me  commission only: goods money passes through our khata
--   paid_now          purchase: we paid now; sale: they paid now   (default 0)
--   paid_method       'cash' | 'bank' | 'other'                     (default 'cash')
--   costs             [{description, amount, charged_to_id?, paid_to_id?}]
--   commissions       [{party_id, mode: 'per_kg'|'percent'|'fixed', value}]
--   notes, source ('app'|'whatsapp'), source_ref
create function record_deal(p jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_owner  uuid := _current_owner();
  v_kind   deal_kind := (p ->> 'kind')::deal_kind;
  v_date   date := coalesce((p ->> 'deal_date')::date, _today());
  v_source entry_source := coalesce((p ->> 'source')::entry_source, 'app');
  v_ref    text := p ->> 'source_ref';
  v_paid   numeric := coalesce((p ->> 'paid_now')::numeric, 0);
  v_party  parties;
  v_buyer  parties;
  v_item   items;
  v_deal   deals;
  v_label  text;
  c        jsonb;
  v_amount numeric;
  v_pid    uuid;
  v_mode   commission_mode;
  v_value  numeric;
begin
  if v_kind is null then
    raise exception 'kind is required';
  end if;

  v_party := _party(v_owner, (p ->> 'party_id')::uuid,
                    case v_kind when 'purchase' then 'supplier' when 'sale' then 'buyer' else 'seller' end);
  if v_kind = 'commission' then
    v_buyer := _party(v_owner, (p ->> 'buyer_id')::uuid, 'buyer');
    if v_buyer.id = v_party.id then
      raise exception 'seller and buyer must be different parties';
    end if;
  end if;
  if p ->> 'item_id' is not null then
    v_item := _item(v_owner, (p ->> 'item_id')::uuid);
  end if;
  if p ->> 'replaces_id' is not null
     and not exists (select 1 from deals where id = (p ->> 'replaces_id')::uuid and owner_id = v_owner) then
    raise exception 'replaced deal not found';
  end if;

  insert into deals (owner_id, kind, deal_date, party_id, buyer_id, item_id, weight_kg, rate,
                     goods_through_me, notes, source, source_ref, replaces_id)
  values (v_owner, v_kind, v_date, v_party.id, v_buyer.id, v_item.id,
          (p ->> 'weight_kg')::numeric, (p ->> 'rate')::numeric,
          coalesce((p ->> 'goods_through_me')::boolean, false),
          p ->> 'notes', v_source, v_ref, (p ->> 'replaces_id')::uuid)
  returning * into v_deal;

  -- e.g. "Purchase: Used cloth 500 kg @ 120"
  v_label := initcap(v_kind::text)
          || coalesce(': ' || v_item.name_en, '')
          || coalesce(' ' || trim_scale(v_deal.weight_kg) || ' kg', '')
          || coalesce(' @ ' || trim_scale(v_deal.rate), '');

  -- Goods money
  if coalesce(v_deal.goods_amount, 0) <> 0 then
    if v_kind = 'purchase' then
      perform _add_entry(v_owner, v_party.id, v_date, -v_deal.goods_amount, 'purchase', v_label, v_source, v_ref, v_deal.id);
    elsif v_kind = 'sale' then
      perform _add_entry(v_owner, v_party.id, v_date, v_deal.goods_amount, 'sale', v_label, v_source, v_ref, v_deal.id);
    elsif v_deal.goods_through_me then
      perform _add_entry(v_owner, v_party.id, v_date, -v_deal.goods_amount, 'purchase',
                         v_label || ' (sold to ' || v_buyer.name || ')', v_source, v_ref, v_deal.id);
      perform _add_entry(v_owner, v_buyer.id, v_date, v_deal.goods_amount, 'sale',
                         v_label || ' (bought from ' || v_party.name || ')', v_source, v_ref, v_deal.id);
    end if;
  end if;

  -- Extra costs
  for c in select * from jsonb_array_elements(coalesce(p -> 'costs', '[]'::jsonb)) loop
    v_amount := (c ->> 'amount')::numeric;
    if (c ->> 'charged_to_id') is not null
       and (c ->> 'charged_to_id')::uuid not in (v_party.id, coalesce(v_buyer.id, v_party.id)) then
      raise exception 'a cost can only be charged to a party of this deal';
    end if;
    if (c ->> 'paid_to_id') is not null then
      perform _party(v_owner, (c ->> 'paid_to_id')::uuid, 'party the cost was paid to');
    end if;

    insert into deal_costs (owner_id, deal_id, description, amount, charged_to_id, paid_to_id)
    values (v_owner, v_deal.id, c ->> 'description', v_amount,
            (c ->> 'charged_to_id')::uuid, (c ->> 'paid_to_id')::uuid);

    if (c ->> 'charged_to_id') is not null then
      perform _add_entry(v_owner, (c ->> 'charged_to_id')::uuid, v_date, v_amount, 'deal_cost',
                         (c ->> 'description') || ' — ' || v_label, v_source, v_ref, v_deal.id);
    end if;
    if (c ->> 'paid_to_id') is not null then
      perform _add_entry(v_owner, (c ->> 'paid_to_id')::uuid, v_date, -v_amount, 'deal_cost',
                         (c ->> 'description') || ' — ' || v_label, v_source, v_ref, v_deal.id);
    end if;
  end loop;

  -- Commission
  for c in select * from jsonb_array_elements(coalesce(p -> 'commissions', '[]'::jsonb)) loop
    if v_kind <> 'commission' then
      raise exception 'commission can only be added to a commission deal';
    end if;
    v_pid := (c ->> 'party_id')::uuid;
    if v_pid is null or v_pid not in (v_party.id, v_buyer.id) then
      raise exception 'commission must come from the seller or the buyer of the deal';
    end if;
    v_mode := (c ->> 'mode')::commission_mode;
    v_value := (c ->> 'value')::numeric;
    v_amount := round(case v_mode
                        when 'fixed'   then v_value
                        when 'per_kg'  then v_value * v_deal.weight_kg
                        when 'percent' then v_value * v_deal.goods_amount / 100
                      end, 2);
    if v_amount is null then
      raise exception 'a % commission needs the deal weight%', v_mode,
        case when v_mode = 'percent' then ' and rate' else '' end;
    end if;

    insert into deal_commissions (owner_id, deal_id, party_id, mode, value, amount)
    values (v_owner, v_deal.id, v_pid, v_mode, v_value, v_amount);

    perform _add_entry(v_owner, v_pid, v_date, v_amount, 'commission',
                       'Commission — ' || v_label
                       || case when v_pid = v_party.id then ' (sold to ' || v_buyer.name || ')'
                               else ' (bought from ' || v_party.name || ')' end,
                       v_source, v_ref, v_deal.id);
  end loop;

  -- Money paid or received on the spot
  if v_paid < 0 then
    raise exception 'paid_now cannot be negative';
  elsif v_paid > 0 then
    if v_kind = 'commission' then
      raise exception 'record payments for commission deals separately';
    end if;
    perform _add_entry(v_owner, v_party.id, v_date,
                       case when v_kind = 'purchase' then v_paid else -v_paid end,
                       case when v_kind = 'purchase' then 'payment_out' else 'payment_in' end::entry_kind,
                       case when v_kind = 'purchase' then 'Paid on deal — ' else 'Received on deal — ' end || v_label,
                       v_source, v_ref, v_deal.id, null,
                       coalesce((p ->> 'paid_method')::payment_method, 'cash'));
  end if;

  return v_deal.id;
end $$;

-- Cancels a deal: marks it cancelled and reverses all of its khata lines
-- (including money paid on the spot). Stock and profit ignore cancelled deals.
create function cancel_deal(p_deal_id uuid, p_reason text default null, p_source entry_source default 'app')
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_owner uuid := _current_owner();
  v_deal deals;
begin
  select * into v_deal from deals where id = p_deal_id and owner_id = v_owner for update;
  if not found then
    raise exception 'deal not found';
  end if;
  if v_deal.cancelled_at is not null then
    raise exception 'deal is already cancelled';
  end if;

  update deals set cancelled_at = now(), cancel_reason = p_reason where id = p_deal_id;
  perform _reverse_entries(v_owner, p_deal_id, null, null, p_reason, p_source);
end $$;

-- "Editing" a deal: cancel the old one and record the corrected one, atomically.
create function replace_deal(p_deal_id uuid, p jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
begin
  perform cancel_deal(p_deal_id, 'Edited', coalesce((p ->> 'source')::entry_source, 'app'));
  return record_deal(p || jsonb_build_object('replaces_id', p_deal_id));
end $$;

-- ==================== PAYMENTS & ADJUSTMENTS ====================

-- p_direction: 'in' = the party paid us, 'out' = we paid the party.
-- Payments go against the party's running khata, not a single bill.
create function record_payment(
  p_party_id uuid,
  p_direction text,
  p_amount numeric,
  p_date date default null,
  p_method payment_method default 'cash',
  p_note text default null,
  p_source entry_source default 'app',
  p_source_ref text default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_owner uuid := _current_owner();
  v_party parties := _party(v_owner, p_party_id);
begin
  if p_direction not in ('in', 'out') then
    raise exception 'direction must be "in" or "out"';
  end if;
  if coalesce(p_amount, 0) <= 0 then
    raise exception 'payment amount must be positive';
  end if;
  return _add_entry(v_owner, v_party.id, coalesce(p_date, _today()),
                    case when p_direction = 'in' then -p_amount else p_amount end,
                    case when p_direction = 'in' then 'payment_in' else 'payment_out' end::entry_kind,
                    coalesce(p_note, case when p_direction = 'in' then 'Payment received' else 'Payment made' end),
                    p_source, p_source_ref, null, null, p_method);
end $$;

-- A manual correction to a party's balance. Positive = they owe us more.
create function record_adjustment(
  p_party_id uuid, p_amount numeric, p_note text, p_date date default null,
  p_source entry_source default 'app'
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_owner uuid := _current_owner();
begin
  if coalesce(p_amount, 0) = 0 then
    raise exception 'adjustment amount cannot be zero';
  end if;
  if coalesce(trim(p_note), '') = '' then
    raise exception 'an adjustment needs a note explaining it';
  end if;
  perform _party(v_owner, p_party_id);
  return _add_entry(v_owner, p_party_id, coalesce(p_date, _today()), p_amount, 'adjustment', p_note, p_source, null);
end $$;

-- Cancels a payment, adjustment or opening balance line.
-- Deal and expense lines are cancelled through cancel_deal / cancel_expense.
create function reverse_entry(p_entry_id uuid, p_reason text default null, p_source entry_source default 'app')
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_owner uuid := _current_owner();
  e khata_entries;
begin
  select * into e from khata_entries where id = p_entry_id and owner_id = v_owner;
  if not found then
    raise exception 'entry not found';
  end if;
  if e.deal_id is not null or e.expense_id is not null then
    raise exception 'this line belongs to a deal or expense; cancel that instead';
  end if;
  if e.kind = 'reversal' then
    raise exception 'a cancellation cannot be cancelled; record the entry again instead';
  end if;
  if exists (select 1 from khata_entries where reverses_id = e.id) then
    raise exception 'entry is already cancelled';
  end if;
  perform _reverse_entries(v_owner, null, null, p_entry_id, p_reason, p_source);
end $$;

-- ==================== EXPENSES ====================

-- p_paid_to_id: set when the expense is owed to a party (on credit); null = paid in cash.
create function record_expense(
  p_category text,
  p_amount numeric,
  p_date date default null,
  p_paid_to_id uuid default null,
  p_notes text default null,
  p_source entry_source default 'app',
  p_source_ref text default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_owner uuid := _current_owner();
  v_id uuid;
  v_date date := coalesce(p_date, _today());
begin
  if p_paid_to_id is not null then
    perform _party(v_owner, p_paid_to_id);
  end if;
  insert into expenses (owner_id, expense_date, category, amount, paid_to_id, notes, source, source_ref)
  values (v_owner, v_date, trim(p_category), p_amount, p_paid_to_id, p_notes, p_source, p_source_ref)
  returning id into v_id;

  if p_paid_to_id is not null then
    perform _add_entry(v_owner, p_paid_to_id, v_date, -p_amount, 'expense',
                       'Expense: ' || trim(p_category) || coalesce(' — ' || p_notes, ''),
                       p_source, p_source_ref, null, v_id);
  end if;
  return v_id;
end $$;

create function cancel_expense(p_expense_id uuid, p_reason text default null, p_source entry_source default 'app')
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_owner uuid := _current_owner();
begin
  update expenses set cancelled_at = now(), cancel_reason = p_reason
  where id = p_expense_id and owner_id = v_owner and cancelled_at is null;
  if not found then
    raise exception 'expense not found or already cancelled';
  end if;
  perform _reverse_entries(v_owner, null, p_expense_id, null, p_reason, p_source);
end $$;

-- ==================== STOCK ====================

-- p_weight_kg: positive adds stock (opening stock, found stock; needs cost per kg),
-- negative removes it (wastage, shortage; valued at average cost).
create function record_stock_adjustment(
  p_item_id uuid, p_weight_kg numeric, p_cost_per_kg numeric default null,
  p_date date default null, p_reason text default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_owner uuid := _current_owner();
  v_id uuid;
begin
  perform _item(v_owner, p_item_id);
  insert into stock_adjustments (owner_id, item_id, adj_date, weight_kg, cost_per_kg, reason)
  values (v_owner, p_item_id, coalesce(p_date, _today()), p_weight_kg, p_cost_per_kg, p_reason)
  returning id into v_id;
  return v_id;
end $$;

create function cancel_stock_adjustment(p_id uuid, p_reason text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  update stock_adjustments set cancelled_at = now(), cancel_reason = p_reason
  where id = p_id and owner_id = _current_owner() and cancelled_at is null;
  if not found then
    raise exception 'stock adjustment not found or already cancelled';
  end if;
end $$;

-- Every stock movement, oldest first. weight > 0 = in (with total cost), < 0 = out.
-- Purchase cost includes extra costs we bear on that purchase.
create function _stock_moves(p_owner uuid)
returns table (item_id uuid, move_date date, created_at timestamptz, deal_id uuid, adjustment_id uuid,
               weight_kg numeric, cost_in numeric)
language sql stable as $$
  select d.item_id, d.deal_date, d.created_at, d.id, null::uuid, d.weight_kg,
         d.goods_amount + coalesce((select sum(c.amount) from deal_costs c
                                    where c.deal_id = d.id and c.charged_to_id is null), 0)
  from deals d
  where d.owner_id = p_owner and d.kind = 'purchase' and d.cancelled_at is null
  union all
  select d.item_id, d.deal_date, d.created_at, d.id, null, -d.weight_kg, null
  from deals d
  where d.owner_id = p_owner and d.kind = 'sale' and d.cancelled_at is null
  union all
  select a.item_id, a.adj_date, a.created_at, null, a.id, a.weight_kg,
         case when a.weight_kg > 0 then a.weight_kg * a.cost_per_kg end
  from stock_adjustments a
  where a.owner_id = p_owner and a.cancelled_at is null
$$;

-- Walks every item's stock movements in date order using moving average cost.
-- Recomputed on every read, so back-dated entries are always valued correctly.
--
-- Selling more than is in stock is allowed (he sometimes sells before the
-- purchase is entered). Such sales are costed at the last known average, or the
-- item's overall average purchase cost, and flagged cost_estimated.
create function _stock_valuation(p_owner uuid)
returns table (seq bigint, item_id uuid, move_date date, deal_id uuid, adjustment_id uuid,
               weight_kg numeric, cost_out numeric, cost_estimated boolean,
               qty_after numeric, avg_cost_after numeric)
language plpgsql stable as $$
declare
  m        record;
  v_item   uuid;
  v_qty    numeric;
  v_avg    numeric;
  v_cost   numeric;
  v_seq    bigint := 0;
begin
  for m in
    select s.*,
           sum(s.cost_in) filter (where s.weight_kg > 0) over w
             / nullif(sum(s.weight_kg) filter (where s.weight_kg > 0) over w, 0) as fallback_avg
    from _stock_moves(p_owner) s
    window w as (partition by s.item_id)
    order by s.item_id, s.move_date, (s.weight_kg < 0), s.created_at
  loop
    if v_item is distinct from m.item_id then
      v_item := m.item_id;
      v_qty := 0;
      v_avg := null;
    end if;

    v_seq := v_seq + 1;
    cost_out := null;
    cost_estimated := false;

    if m.weight_kg > 0 then
      if v_qty <= 0 or v_avg is null then
        v_avg := m.cost_in / m.weight_kg;
      else
        v_avg := (v_qty * v_avg + m.cost_in) / (v_qty + m.weight_kg);
      end if;
    else
      if v_qty > 0 and v_avg is not null then
        v_cost := v_avg;
      else
        v_cost := coalesce(v_avg, m.fallback_avg, 0);
        cost_estimated := true;
      end if;
      cost_out := round(-m.weight_kg * v_cost, 2);
    end if;
    v_qty := v_qty + m.weight_kg;

    seq := v_seq;
    item_id := m.item_id;
    move_date := m.move_date;
    deal_id := m.deal_id;
    adjustment_id := m.adjustment_id;
    weight_kg := m.weight_kg;
    qty_after := v_qty;
    avg_cost_after := round(v_avg, 4);
    return next;
  end loop;
end $$;

-- ==================== REPORTS ====================

-- Live balance of every party. Positive = they owe us, negative = we owe them.
create view party_balances with (security_invoker = true) as
select p.id                                   as party_id,
       p.name,
       p.type,
       p.city,
       p.archived_at,
       coalesce(sum(e.amount), 0)::numeric(14, 2) as balance,
       max(e.entry_date)                      as last_entry_date
from parties p
left join khata_entries e on e.party_id = p.id
group by p.id;

-- A party's khata with running balance. Cancelled lines (and their reversals)
-- are hidden by default; they cancel out, so the balance is the same either way.
create function party_statement(
  p_party_id uuid, p_from date default null, p_to date default null, p_include_cancelled boolean default false
) returns table (entry_id uuid, entry_date date, kind entry_kind, note text, method payment_method,
                 amount numeric, balance numeric)
language plpgsql stable security definer set search_path = public as $$
declare
  v_owner uuid := _current_owner();
  v_opening numeric;
begin
  if not exists (select 1 from parties where id = p_party_id and owner_id = v_owner) then
    raise exception 'party not found';
  end if;

  select coalesce(sum(e.amount), 0) into v_opening
  from khata_entries e
  where e.party_id = p_party_id and p_from is not null and e.entry_date < p_from;

  if p_from is not null then
    entry_id := null; entry_date := p_from; kind := null; note := 'Balance brought forward';
    method := null; amount := v_opening; balance := v_opening;
    return next;
  end if;

  return query
  select e.id, e.entry_date, e.kind, e.note, e.method, e.amount,
         (v_opening + sum(e.amount) over (order by e.entry_date, e.created_at, e.id))::numeric
  from khata_entries e
  where e.party_id = p_party_id
    and (p_from is null or e.entry_date >= p_from)
    and (p_to is null or e.entry_date <= p_to)
    and (p_include_cancelled
         or (e.kind <> 'reversal' and not exists (select 1 from khata_entries r where r.reverses_id = e.id)))
  order by e.entry_date, e.created_at, e.id;
end $$;

-- Stock per cloth type as of a date (default: everything entered).
create function stock_summary(p_as_of date default null)
returns table (item_id uuid, name_en text, name_ur text, archived boolean,
               weight_kg numeric, avg_cost numeric, stock_value numeric)
language sql stable security definer set search_path = public as $$
  with v as (
    select distinct on (s.item_id) s.item_id, s.qty_after, s.avg_cost_after
    from _stock_valuation(_current_owner()) s
    where p_as_of is null or s.move_date <= p_as_of
    order by s.item_id, s.seq desc
  )
  select i.id, i.name_en, i.name_ur, i.archived_at is not null,
         coalesce(v.qty_after, 0),
         v.avg_cost_after,
         round(greatest(coalesce(v.qty_after, 0), 0) * coalesce(v.avg_cost_after, 0), 2)
  from items i
  left join v on v.item_id = i.id
  where i.owner_id = _current_owner()
  order by i.name_en
$$;

-- Profit for a date range.
--   trading profit = sales − cost of cloth sold − our costs on sales
--   net profit     = trading profit + commission − our costs on commission deals
--                    − stock losses − expenses
-- has_estimates is true when some sale was made before its stock was entered.
create function profit_report(p_from date, p_to date)
returns table (sales_amount numeric, cost_of_goods_sold numeric, sale_costs numeric, trading_profit numeric,
               commission_income numeric, commission_costs numeric, stock_losses numeric,
               expenses numeric, net_profit numeric, has_estimates boolean)
language plpgsql stable security definer set search_path = public as $$
declare
  v_owner uuid := _current_owner();
begin
  return query
  with d as (
    select * from deals
    where owner_id = v_owner and cancelled_at is null and deal_date between p_from and p_to
  ),
  val as (
    select * from _stock_valuation(v_owner) s where s.move_date between p_from and p_to
  ),
  my_costs as (
    select d.kind, sum(c.amount) as amount
    from d join deal_costs c on c.deal_id = d.id
    where c.charged_to_id is null
    group by d.kind
  ),
  r as (
    select
      coalesce((select sum(goods_amount) from d where kind = 'sale'), 0)                                   as sales,
      coalesce((select sum(cost_out) from val where val.deal_id is not null), 0)                           as cogs,
      coalesce((select amount from my_costs where kind = 'sale'), 0)                                       as sale_costs,
      coalesce((select sum(dc.amount) from deal_commissions dc join d on d.id = dc.deal_id), 0)            as commission,
      coalesce((select amount from my_costs where kind = 'commission'), 0)                                 as commission_costs,
      coalesce((select sum(cost_out) from val where val.adjustment_id is not null and val.weight_kg < 0), 0) as losses,
      coalesce((select sum(x.amount) from expenses x
                where x.owner_id = v_owner and x.cancelled_at is null
                  and x.expense_date between p_from and p_to), 0)                                          as expenses,
      coalesce((select bool_or(cost_estimated) from val where val.deal_id is not null), false)             as estimated
  )
  select r.sales, r.cogs, r.sale_costs,
         r.sales - r.cogs - r.sale_costs,
         r.commission, r.commission_costs, r.losses, r.expenses,
         r.sales - r.cogs - r.sale_costs + r.commission - r.commission_costs - r.losses - r.expenses,
         r.estimated
  from r;
end $$;

-- ==================== ACCESS ====================

revoke execute on all functions in schema public from public, anon, authenticated;

grant execute on function
  create_party(text, party_type, text, text, text, text, numeric, date),
  update_party(uuid, text, party_type, text, text, text, text),
  set_party_archived(uuid, boolean),
  create_item(text, text),
  update_item(uuid, text, text),
  set_item_archived(uuid, boolean),
  record_deal(jsonb),
  cancel_deal(uuid, text, entry_source),
  replace_deal(uuid, jsonb),
  record_payment(uuid, text, numeric, date, payment_method, text, entry_source, text),
  record_adjustment(uuid, numeric, text, date, entry_source),
  reverse_entry(uuid, text, entry_source),
  record_expense(text, numeric, date, uuid, text, entry_source, text),
  cancel_expense(uuid, text, entry_source),
  record_stock_adjustment(uuid, numeric, numeric, date, text),
  cancel_stock_adjustment(uuid, text),
  party_statement(uuid, date, date, boolean),
  stock_summary(date),
  profit_report(date, date)
to authenticated;

grant select on party_balances to authenticated;
