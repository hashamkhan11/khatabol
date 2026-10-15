-- Khata lines store facts, not sentences.
--
-- The functions used to write English text into khata_entries.note, such as
-- "Purchase: Used cloth 500 kg @ 120". The app shows Roman Urdu and the
-- WhatsApp bot will reply in the language it is spoken to, so wording now
-- belongs to the client. note holds only what a person typed: a payment
-- note, a cost description or a cancel reason. Everything else is read from
-- the linked deal or expense through the khata_lines view.

-- ==================== WRITERS ====================

create or replace function _reverse_entries(p_owner uuid, p_deal uuid, p_expense uuid, p_entry uuid,
                                 p_reason text, p_source entry_source) returns void
language sql as $$
  insert into khata_entries (owner_id, party_id, entry_date, amount, kind, note, method,
                             deal_id, expense_id, reverses_id, source)
  select e.owner_id, e.party_id, e.entry_date, -e.amount, 'reversal',
         nullif(trim(p_reason), ''),
         e.method, e.deal_id, e.expense_id, e.id, p_source
  from khata_entries e
  where e.owner_id = p_owner
    and e.kind <> 'reversal'
    and (p_deal is null or e.deal_id = p_deal)
    and (p_expense is null or e.expense_id = p_expense)
    and (p_entry is null or e.id = p_entry)
    and not exists (select 1 from khata_entries r where r.reverses_id = e.id)
$$;

create or replace function create_party(
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
                       'opening', null, 'app', null);
  end if;
  return v_id;
end $$;

create or replace function record_deal(p jsonb) returns uuid
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

  -- Goods money
  if coalesce(v_deal.goods_amount, 0) <> 0 then
    if v_kind = 'purchase' then
      perform _add_entry(v_owner, v_party.id, v_date, -v_deal.goods_amount, 'purchase', null, v_source, v_ref, v_deal.id);
    elsif v_kind = 'sale' then
      perform _add_entry(v_owner, v_party.id, v_date, v_deal.goods_amount, 'sale', null, v_source, v_ref, v_deal.id);
    elsif v_deal.goods_through_me then
      perform _add_entry(v_owner, v_party.id, v_date, -v_deal.goods_amount, 'purchase',
                         null, v_source, v_ref, v_deal.id);
      perform _add_entry(v_owner, v_buyer.id, v_date, v_deal.goods_amount, 'sale',
                         null, v_source, v_ref, v_deal.id);
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
                         c ->> 'description', v_source, v_ref, v_deal.id);
    end if;
    if (c ->> 'paid_to_id') is not null then
      perform _add_entry(v_owner, (c ->> 'paid_to_id')::uuid, v_date, -v_amount, 'deal_cost',
                         c ->> 'description', v_source, v_ref, v_deal.id);
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
                       null, v_source, v_ref, v_deal.id);
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
                       null,
                       v_source, v_ref, v_deal.id, null,
                       coalesce((p ->> 'paid_method')::payment_method, 'cash'));
  end if;

  return v_deal.id;
end $$;

create or replace function replace_deal(p_deal_id uuid, p jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
begin
  perform cancel_deal(p_deal_id, null, coalesce((p ->> 'source')::entry_source, 'app'));
  return record_deal(p || jsonb_build_object('replaces_id', p_deal_id));
end $$;

create or replace function record_payment(
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
                    nullif(trim(p_note), ''),
                    p_source, p_source_ref, null, null, p_method);
end $$;

create or replace function record_expense(
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
                       nullif(trim(p_notes), ''),
                       p_source, p_source_ref, null, v_id);
  end if;
  return v_id;
end $$;

-- ==================== EXISTING LINES ====================

-- Clears the generated text from lines written before this migration.
-- Khata lines are otherwise immutable; this one-off rewrite only touches text
-- the functions generated, never amounts, parties or dates.
alter table khata_entries disable trigger khata_entries_immutable;

update khata_entries e
set note = case
  when e.kind in ('opening', 'purchase', 'sale', 'commission') then null
  when e.kind in ('payment_in', 'payment_out') then
    case when e.deal_id is not null or e.note in ('Payment received', 'Payment made') then null else e.note end
  when e.kind = 'deal_cost' then split_part(e.note, ' — ', 1)
  when e.kind = 'expense' then (select x.notes from expenses x where x.id = e.expense_id)
  when e.deal_id is not null then (select nullif(d.cancel_reason, 'Edited') from deals d where d.id = e.deal_id)
  when e.expense_id is not null then (select x.cancel_reason from expenses x where x.id = e.expense_id)
  else substring(e.note from ' \(([^()]*)\)$')
end
where e.kind <> 'adjustment';

alter table khata_entries enable trigger khata_entries_immutable;

-- ==================== READERS ====================

-- Every khata line with what a client needs to describe it in any language:
-- the deal (kind, cloth, kg, rate), the other side of the deal, the expense
-- category, and what a reversal cancelled.
create view khata_lines with (security_invoker = true) as
select e.id,
       e.owner_id,
       e.party_id,
       p.name        as party_name,
       e.entry_date,
       e.seq,
       e.amount,
       e.kind,
       e.note,
       e.method,
       e.source,
       e.deal_id,
       d.kind        as deal_kind,
       i.name_en     as item_name,
       i.name_ur     as item_name_ur,
       d.weight_kg,
       d.rate,
       -- commission: the other side of the deal; a cost owed to a transporter: the deal party
       case when d.kind = 'commission' then case when e.party_id = d.party_id then b.name else s.name end
            when e.party_id <> d.party_id then s.name
       end           as counterparty_name,
       e.expense_id,
       x.category    as expense_category,
       e.reverses_id,
       r.kind        as reversed_kind,
       (e.kind = 'reversal'
        or exists (select 1 from khata_entries c where c.reverses_id = e.id)) as cancelled,
       e.created_at
from khata_entries e
join parties p            on p.id = e.party_id
left join deals d         on d.id = e.deal_id
left join parties s       on s.id = d.party_id
left join parties b       on b.id = d.buyer_id
left join items i         on i.id = d.item_id
left join expenses x      on x.id = e.expense_id
left join khata_entries r on r.id = e.reverses_id;

drop function party_statement(uuid, date, date, boolean);

-- A party's khata with running balance. Cancelled lines (and their reversals)
-- are hidden by default; they cancel out, so the balance is the same either way.
create function party_statement(
  p_party_id uuid, p_from date default null, p_to date default null, p_include_cancelled boolean default false
) returns table (entry_id uuid, entry_date date, kind entry_kind, note text, method payment_method,
                 amount numeric, balance numeric,
                 deal_id uuid, deal_kind deal_kind, item_name text, weight_kg numeric, rate numeric,
                 counterparty_name text, expense_id uuid, expense_category text,
                 reversed_kind entry_kind, cancelled boolean)
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

  -- Balance brought forward: the only line with no entry_id and no kind.
  if p_from is not null then
    entry_date := p_from; amount := v_opening; balance := v_opening; cancelled := false;
    return next;
  end if;

  return query
  select l.id, l.entry_date, l.kind, l.note, l.method, l.amount,
         (v_opening + sum(l.amount) over (order by l.entry_date, l.seq))::numeric,
         l.deal_id, l.deal_kind, l.item_name, l.weight_kg, l.rate,
         l.counterparty_name, l.expense_id, l.expense_category,
         l.reversed_kind, l.cancelled
  from khata_lines l
  where l.party_id = p_party_id
    and (p_from is null or l.entry_date >= p_from)
    and (p_to is null or l.entry_date <= p_to)
    and (p_include_cancelled or not l.cancelled)
  order by l.entry_date, l.seq;
end $$;

-- ==================== ACCESS ====================

revoke execute on function party_statement(uuid, date, date, boolean) from public, anon;
grant execute on function party_statement(uuid, date, date, boolean) to authenticated;
grant select on khata_lines to authenticated;
