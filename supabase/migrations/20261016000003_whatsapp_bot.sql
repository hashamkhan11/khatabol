-- The WhatsApp bot.
--
-- The bot runs as an Edge Function with the service key, so it is not signed
-- in as anyone. It may only call the bot_* functions below. They:
--   * only answer numbers listed in bot_senders, each linked to one user;
--   * keep the entry the bot read back until the user says yes (bot_pending);
--   * save a confirmed entry by calling the same ledger functions the app
--     uses, signed in as the linked user for that one transaction.
-- So a WhatsApp entry follows exactly the same rules as one made in the app,
-- and nothing is saved that the user did not confirm.

-- ==================== TABLES ====================

-- WhatsApp numbers allowed to use the bot, in international format without
-- "+" (as WhatsApp sends them), e.g. 923001234567.
create table bot_senders (
  whatsapp   text primary key constraint whatsapp_digits_only check (whatsapp ~ '^[0-9]{8,15}$'),
  owner_id   uuid not null references auth.users (id),
  created_at timestamptz not null default now()
);

-- The entry the bot read back and is waiting for a yes on. One per number.
create table bot_pending (
  whatsapp   text primary key references bot_senders (whatsapp),
  plan       jsonb not null,
  created_at timestamptz not null default now()
);

-- WhatsApp may deliver the same message more than once.
create table bot_messages (
  wa_id       text primary key,
  received_at timestamptz not null default now()
);

-- What the bot saved, so the last one can be undone from WhatsApp.
create table bot_log (
  id         uuid primary key default gen_random_uuid(),
  whatsapp   text not null references bot_senders (whatsapp),
  owner_id   uuid not null references auth.users (id),
  wa_id      text,
  plan       jsonb not null,
  saved      jsonb not null,
  undone_at  timestamptz,
  created_at timestamptz not null default clock_timestamp()
);
create index bot_log_sender_idx on bot_log (whatsapp, created_at desc);

alter table bot_senders  enable row level security;
alter table bot_pending  enable row level security;
alter table bot_messages enable row level security;
alter table bot_log      enable row level security;
revoke all on bot_senders, bot_pending, bot_messages, bot_log from anon, authenticated;

-- ==================== HELPERS ====================

-- The user a WhatsApp number belongs to, or null.
create function _bot_owner(p_whatsapp text) returns uuid
language sql stable as $$
  select owner_id from bot_senders where whatsapp = p_whatsapp
$$;

-- Acts as p_owner for the rest of this transaction, so the ledger functions
-- see the same auth.uid() as when the user saves from the app.
create function _bot_sign_in(p_owner uuid) returns void
language sql as $$
  select set_config('request.jwt.claim.sub', p_owner::text, true),
         set_config('request.jwt.claims', json_build_object('sub', p_owner, 'role', 'authenticated')::text, true)
$$;

-- A party in a plan: {"id": ...} for an existing one, or
-- {"name": ..., "party_type": ...} for a new one. A new name that matches an
-- active party (same letters, any case) uses that party instead of a duplicate.
create function _bot_party(p_owner uuid, p_ref jsonb) returns uuid
language plpgsql as $$
declare
  v_id uuid;
begin
  if p_ref is null or jsonb_typeof(p_ref) = 'null' then
    return null;
  end if;
  if p_ref ? 'id' then
    return (p_ref ->> 'id')::uuid;
  end if;
  select id into v_id from parties
  where owner_id = p_owner and archived_at is null
    and lower(trim(name)) = lower(trim(p_ref ->> 'name'))
  order by created_at limit 1;
  return coalesce(v_id, create_party(p_ref ->> 'name',
                                     coalesce((p_ref ->> 'party_type')::party_type, 'other')));
end $$;

create function _bot_item(p_owner uuid, p_ref jsonb) returns uuid
language plpgsql as $$
declare
  v_id uuid;
begin
  if p_ref is null or jsonb_typeof(p_ref) = 'null' then
    return null;
  end if;
  if p_ref ? 'id' then
    return (p_ref ->> 'id')::uuid;
  end if;
  select id into v_id from items
  where owner_id = p_owner and archived_at is null
    and lower(trim(p_ref ->> 'name')) in (lower(trim(name_en)), lower(trim(coalesce(name_ur, ''))))
  order by created_at limit 1;
  return coalesce(v_id, create_item(trim(p_ref ->> 'name')));
end $$;

-- Saves one entry of a confirmed plan. Returns what was saved, for undo:
-- {"type": "deal" | "payment" | "expense" | "stock", "id": ..., "parties": [...]}
create function _bot_save_entry(p_owner uuid, e jsonb, p_ref text) returns jsonb
language plpgsql as $$
declare
  v_party uuid;
  v_buyer uuid;
  v_id    uuid;
  c       jsonb;
  v_costs jsonb := '[]';
  v_comms jsonb := '[]';
  v_paid_to uuid;
  v_involved uuid[] := '{}';
begin
  case e ->> 'type'
  when 'deal' then
    v_party := _bot_party(p_owner, e -> 'party');
    v_buyer := _bot_party(p_owner, e -> 'buyer');
    v_involved := array_remove(array[v_party, v_buyer], null);
    for c in select * from jsonb_array_elements(coalesce(e -> 'costs', '[]')) loop
      v_paid_to := _bot_party(p_owner, c -> 'paid_to');
      v_involved := v_involved || v_paid_to;
      v_costs := v_costs || jsonb_build_object(
        'description', c ->> 'description',
        'amount', c -> 'amount',
        'charged_to_id', case c ->> 'charged_to' when 'party' then v_party when 'buyer' then v_buyer end,
        'paid_to_id', v_paid_to);
    end loop;
    for c in select * from jsonb_array_elements(coalesce(e -> 'commissions', '[]')) loop
      v_comms := v_comms || jsonb_build_object(
        'party_id', case c ->> 'from' when 'buyer' then v_buyer else v_party end,
        'mode', c ->> 'mode',
        'value', c -> 'value');
    end loop;
    v_id := record_deal(jsonb_strip_nulls(jsonb_build_object(
      'kind', e ->> 'kind',
      'deal_date', e ->> 'date',
      'party_id', v_party,
      'buyer_id', v_buyer,
      'item_id', _bot_item(p_owner, e -> 'item'),
      'weight_kg', e -> 'weight_kg',
      'rate', e -> 'rate',
      'paid_now', e -> 'paid_now',
      'paid_method', e ->> 'paid_method',
      'goods_through_me', e -> 'goods_through_me',
      'notes', e ->> 'notes',
      'costs', v_costs,
      'commissions', v_comms,
      'source', 'whatsapp',
      'source_ref', p_ref)));

  when 'payment' then
    v_party := _bot_party(p_owner, e -> 'party');
    v_involved := array[v_party];
    v_id := record_payment(v_party, e ->> 'direction', (e ->> 'amount')::numeric,
                           (e ->> 'date')::date, coalesce((e ->> 'method')::payment_method, 'cash'),
                           e ->> 'note', 'whatsapp', p_ref);

  when 'expense' then
    v_party := _bot_party(p_owner, e -> 'paid_to');
    v_involved := array_remove(array[v_party], null);
    v_id := record_expense(e ->> 'category', (e ->> 'amount')::numeric, (e ->> 'date')::date,
                           v_party, e ->> 'notes', 'whatsapp', p_ref);

  when 'stock' then
    v_id := record_stock_adjustment(_bot_item(p_owner, e -> 'item'),
                                    (e ->> 'kind')::stock_adjustment_kind,
                                    (e ->> 'weight_kg')::numeric, (e ->> 'cost_per_kg')::numeric,
                                    (e ->> 'date')::date, e ->> 'reason');
  else
    raise exception 'unknown entry type %', e ->> 'type';
  end case;

  return jsonb_build_object('type', e ->> 'type', 'id', v_id, 'parties', to_jsonb(v_involved));
end $$;

-- ==================== FUNCTIONS THE BOT CALLS ====================

-- Records a WhatsApp message id. False if it was already seen (a redelivery).
create function bot_claim_message(p_wa_id text) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  insert into bot_messages (wa_id) values (p_wa_id) on conflict do nothing;
  return found;
end $$;

-- What the bot needs to read a message: today's date, the parties and cloth
-- types with their names, recent expense categories, the entry waiting for a
-- yes and the last saved entry. Null when the number is not linked.
create function bot_context(p_whatsapp text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_owner uuid := _bot_owner(p_whatsapp);
begin
  if v_owner is null then
    return null;
  end if;
  return jsonb_build_object(
    'today', _today(),
    'parties', coalesce((
      select jsonb_agg(jsonb_build_object('id', p.id, 'name', p.name, 'type', p.type,
                                          'balance', coalesce(b.balance, 0)) order by p.name)
      from parties p
      left join (select party_id, sum(amount) balance from khata_entries
                 where owner_id = v_owner group by party_id) b on b.party_id = p.id
      where p.owner_id = v_owner and p.archived_at is null), '[]'),
    'items', coalesce((
      select jsonb_agg(jsonb_build_object('id', i.id, 'name', i.name_en, 'name_ur', i.name_ur)
                       order by i.name_en)
      from items i where i.owner_id = v_owner and i.archived_at is null), '[]'),
    'categories', coalesce((
      select jsonb_agg(category) from (
        select category from expenses where owner_id = v_owner and cancelled_at is null
        group by category order by max(created_at) desc limit 30) c), '[]'),
    'pending', (select plan from bot_pending
                where whatsapp = p_whatsapp and created_at > now() - interval '1 day'),
    'last_saved', (select jsonb_build_object('id', id, 'plan', plan, 'at', created_at)
                   from bot_log where whatsapp = p_whatsapp and undone_at is null
                   order by created_at desc limit 1));
end $$;

-- Keeps the plan the bot read back, replacing any older one. Null clears it.
create function bot_set_pending(p_whatsapp text, p_plan jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  if _bot_owner(p_whatsapp) is null then
    raise exception 'number not linked';
  end if;
  delete from bot_pending where whatsapp = p_whatsapp;
  if p_plan is not null then
    insert into bot_pending (whatsapp, plan) values (p_whatsapp, p_plan);
  end if;
end $$;

-- The user said yes: saves the waiting plan in one transaction and returns
-- what was saved with the new balance of every party involved. If any part
-- fails, nothing is saved and the plan keeps waiting.
--
-- A plan is {"action": "save", "entries": [...]} or
-- {"action": "undo", "log_id": ...} to cancel the last saved plan.
create function bot_confirm(p_whatsapp text, p_wa_id text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_owner uuid := _bot_owner(p_whatsapp);
  v_plan  jsonb;
  v_saved jsonb := '[]';
  v_log   bot_log;
  e       jsonb;
  v_parties uuid[];
begin
  if v_owner is null then
    raise exception 'number not linked';
  end if;
  delete from bot_pending
  where whatsapp = p_whatsapp and created_at > now() - interval '1 day'
  returning plan into v_plan;
  if v_plan is null then
    raise exception 'nothing to confirm';
  end if;
  perform _bot_sign_in(v_owner);

  if v_plan ->> 'action' = 'undo' then
    update bot_log set undone_at = now()
    where id = (v_plan ->> 'log_id')::uuid and whatsapp = p_whatsapp and undone_at is null
    returning * into v_log;
    if not found then
      raise exception 'already undone';
    end if;
    for e in select * from jsonb_array_elements(v_log.saved) loop
      case e ->> 'type'
      when 'deal'    then perform cancel_deal((e ->> 'id')::uuid, 'WhatsApp undo', 'whatsapp');
      when 'payment' then perform reverse_entry((e ->> 'id')::uuid, 'WhatsApp undo', 'whatsapp');
      when 'expense' then perform cancel_expense((e ->> 'id')::uuid, 'WhatsApp undo', 'whatsapp');
      when 'stock'   then perform cancel_stock_adjustment((e ->> 'id')::uuid, 'WhatsApp undo');
      end case;
    end loop;
    v_saved := v_log.saved;
  else
    for e in select * from jsonb_array_elements(coalesce(v_plan -> 'entries', '[]')) loop
      v_saved := v_saved || _bot_save_entry(v_owner, e, p_wa_id);
    end loop;
    if jsonb_array_length(v_saved) = 0 then
      raise exception 'nothing to confirm';
    end if;
    insert into bot_log (whatsapp, owner_id, wa_id, plan, saved)
    values (p_whatsapp, v_owner, p_wa_id, v_plan, v_saved);
  end if;

  select array_agg(distinct p::uuid) into v_parties
  from jsonb_array_elements(v_saved) s, jsonb_array_elements_text(s -> 'parties') p;

  return jsonb_build_object(
    'action', coalesce(v_plan ->> 'action', 'save'),
    'saved', v_saved,
    'balances', coalesce((
      select jsonb_agg(jsonb_build_object('name', p.name,
                                          'balance', coalesce((select sum(amount) from khata_entries k
                                                               where k.party_id = p.id), 0))
                       order by p.name)
      from parties p where p.id = any (v_parties) and p.owner_id = v_owner), '[]'));
end $$;

revoke execute on function
  _bot_owner(text), _bot_sign_in(uuid), _bot_party(uuid, jsonb), _bot_item(uuid, jsonb),
  _bot_save_entry(uuid, jsonb, text),
  bot_claim_message(text), bot_context(text), bot_set_pending(text, jsonb), bot_confirm(text, text)
from public, anon, authenticated;

grant execute on function
  bot_claim_message(text), bot_context(text), bot_set_pending(text, jsonb), bot_confirm(text, text)
to service_role;
