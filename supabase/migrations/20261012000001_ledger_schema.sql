-- Khata (ledger) schema for a cloth trading + brokerage business.
--
-- Rules this schema is built on:
--   * Money is numeric (exact decimal, never float). Weight is always kg.
--   * A party's balance is never stored. It is the SUM of its khata_entries.
--       positive amount = the party owes us more
--       negative amount = we owe the party more
--   * Money records are never edited or deleted. A mistake is fixed by
--     cancelling (which writes reversing entries) and recording again.
--   * Clients (app, bot) can only READ tables. Every write goes through the
--     functions in the next migration, so all business rules live in one place.

-- ==================== TYPES ====================

create type party_type      as enum ('supplier', 'factory', 'buyer', 'transporter', 'other');
create type deal_kind       as enum ('purchase', 'sale', 'commission');
create type entry_kind      as enum ('opening', 'purchase', 'sale', 'commission', 'deal_cost',
                                     'payment_in', 'payment_out', 'expense', 'adjustment', 'reversal');
create type entry_source    as enum ('app', 'whatsapp', 'system');
create type payment_method  as enum ('cash', 'bank', 'other');
create type commission_mode as enum ('per_kg', 'percent', 'fixed');

-- ==================== MASTER DATA ====================

-- Everyone the business deals with: suppliers, factories, buyers, transporters.
create table parties (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null references auth.users (id),
  name        text not null constraint party_name_required check (length(trim(name)) > 0),
  type        party_type not null default 'other',
  phone       text,
  whatsapp    text,
  city        text,
  notes       text,
  archived_at timestamptz,
  created_at  timestamptz not null default now()
);
create index parties_owner_idx on parties (owner_id);

-- Cloth types. Everything is weighed in kg.
create table items (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null references auth.users (id),
  name_en     text not null constraint item_name_required check (length(trim(name_en)) > 0),
  name_ur     text,
  archived_at timestamptz,
  created_at  timestamptz not null default now()
);
create index items_owner_idx on items (owner_id);

-- ==================== DEALS ====================

-- purchase:   party_id = supplier, goods come into stock
-- sale:       party_id = buyer, goods leave stock
-- commission: party_id = seller, buyer_id = buyer. Goods never enter our stock.
--             If goods_through_me, the goods money passes through our khata
--             (buyer owes us, we owe seller); otherwise only commission is booked.
create table deals (
  id               uuid primary key default gen_random_uuid(),
  owner_id         uuid not null references auth.users (id),
  kind             deal_kind not null,
  deal_date        date not null,
  party_id         uuid not null references parties (id),
  buyer_id         uuid references parties (id),
  item_id          uuid references items (id),
  weight_kg        numeric(12, 3) constraint weight_must_be_positive check (weight_kg > 0),
  rate             numeric(12, 2) constraint rate_cannot_be_negative check (rate >= 0),
  goods_amount     numeric(14, 2) generated always as (round(weight_kg * rate, 2)) stored,
  goods_through_me boolean not null default false,
  notes            text,
  source           entry_source not null default 'app',
  source_ref       text,
  replaces_id      uuid references deals (id),
  cancelled_at     timestamptz,
  cancel_reason    text,
  created_at       timestamptz not null default now(),

  constraint buyer_only_on_commission   check ((kind = 'commission') = (buyer_id is not null)),
  constraint trade_needs_item_weight_rate
    check (kind = 'commission' or (item_id is not null and weight_kg is not null and rate is not null)),
  constraint goods_through_me_needs_weight_rate
    check (not goods_through_me or (weight_kg is not null and rate is not null)),
  constraint goods_through_me_only_on_commission check (kind = 'commission' or not goods_through_me)
);
create index deals_owner_date_idx on deals (owner_id, deal_date);

-- Extra costs on a deal (freight, labour, loading...).
--   charged_to_id: party who bears the cost (must be in the deal). null = we bear it.
--   paid_to_id:    party we owe for it (e.g. a transporter on credit). null = paid in cash.
create table deal_costs (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null references auth.users (id),
  deal_id       uuid not null references deals (id),
  description   text not null constraint cost_description_required check (length(trim(description)) > 0),
  amount        numeric(14, 2) not null constraint cost_must_be_positive check (amount > 0),
  charged_to_id uuid references parties (id),
  paid_to_id    uuid references parties (id)
);
create index deal_costs_deal_idx on deal_costs (deal_id);

-- Commission earned on a commission deal, from the seller and/or the buyer.
create table deal_commissions (
  id       uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users (id),
  deal_id  uuid not null references deals (id),
  party_id uuid not null references parties (id),
  mode     commission_mode not null,
  value    numeric(12, 4) not null constraint commission_value_positive check (value > 0),
  amount   numeric(14, 2) not null constraint commission_amount_positive check (amount > 0)
);
create index deal_commissions_deal_idx on deal_commissions (deal_id);

-- ==================== OTHER MONEY & STOCK ====================

-- Business expenses that belong to no deal: rent, salaries, tea, electricity.
create table expenses (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null references auth.users (id),
  expense_date  date not null,
  category      text not null constraint expense_category_required check (length(trim(category)) > 0),
  amount        numeric(14, 2) not null constraint expense_must_be_positive check (amount > 0),
  paid_to_id    uuid references parties (id),
  notes         text,
  source        entry_source not null default 'app',
  source_ref    text,
  cancelled_at  timestamptz,
  cancel_reason text,
  created_at    timestamptz not null default now()
);
create index expenses_owner_date_idx on expenses (owner_id, expense_date);

-- Stock corrections outside deals: opening stock (+, with cost) or wastage (-).
create table stock_adjustments (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null references auth.users (id),
  item_id       uuid not null references items (id),
  adj_date      date not null,
  weight_kg     numeric(12, 3) not null constraint adjustment_weight_nonzero check (weight_kg <> 0),
  cost_per_kg   numeric(12, 2) constraint adjustment_cost_not_negative check (cost_per_kg >= 0),
  reason        text,
  cancelled_at  timestamptz,
  cancel_reason text,
  created_at    timestamptz not null default now(),

  constraint added_stock_needs_cost check (weight_kg < 0 or cost_per_kg is not null)
);

-- ==================== THE KHATA ====================

-- One line per change in what a party owes. Balance = SUM(amount).
create table khata_entries (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null references auth.users (id),
  party_id    uuid not null references parties (id),
  entry_date  date not null,
  amount      numeric(14, 2) not null constraint entry_amount_nonzero check (amount <> 0),
  kind        entry_kind not null,
  note        text,
  method      payment_method,
  deal_id     uuid references deals (id),
  expense_id  uuid references expenses (id),
  reverses_id uuid unique references khata_entries (id),
  source      entry_source not null default 'app',
  source_ref  text,
  -- clock_timestamp, not now(): lines written in one call keep their order
  created_at  timestamptz not null default clock_timestamp()
);
create index khata_party_date_idx on khata_entries (party_id, entry_date);
create index khata_owner_idx on khata_entries (owner_id);
create index khata_deal_idx on khata_entries (deal_id);
create index khata_expense_idx on khata_entries (expense_id);

-- ==================== IMMUTABILITY ====================

create function _forbid_change() returns trigger
language plpgsql as $$
begin
  raise exception '% rows cannot be changed or deleted; cancel and record again', tg_table_name;
end $$;

-- Deals, expenses and stock adjustments may only be cancelled, never edited.
create function _allow_cancel_only() returns trigger
language plpgsql as $$
begin
  if tg_op = 'DELETE' then
    raise exception '% rows cannot be deleted; cancel them instead', tg_table_name;
  end if;
  -- goods_amount is generated, so it is still null in NEW here; skip it.
  if old.cancelled_at is not null
     or (to_jsonb(new) - 'cancelled_at' - 'cancel_reason' - 'goods_amount')
        is distinct from (to_jsonb(old) - 'cancelled_at' - 'cancel_reason' - 'goods_amount') then
    raise exception '% rows can only be cancelled once, not edited', tg_table_name;
  end if;
  return new;
end $$;

create trigger khata_entries_immutable    before update or delete on khata_entries    for each row execute function _forbid_change();
create trigger deal_costs_immutable       before update or delete on deal_costs       for each row execute function _forbid_change();
create trigger deal_commissions_immutable before update or delete on deal_commissions for each row execute function _forbid_change();
create trigger deals_cancel_only          before update or delete on deals             for each row execute function _allow_cancel_only();
create trigger expenses_cancel_only       before update or delete on expenses          for each row execute function _allow_cancel_only();
create trigger stock_adj_cancel_only      before update or delete on stock_adjustments for each row execute function _allow_cancel_only();

-- ==================== ACCESS ====================

-- Each user sees only their own rows. There are no write policies: writes
-- happen only inside the security-definer functions.
alter table parties           enable row level security;
alter table items             enable row level security;
alter table deals             enable row level security;
alter table deal_costs        enable row level security;
alter table deal_commissions  enable row level security;
alter table expenses          enable row level security;
alter table stock_adjustments enable row level security;
alter table khata_entries     enable row level security;

create policy owner_reads on parties           for select to authenticated using (owner_id = (select auth.uid()));
create policy owner_reads on items             for select to authenticated using (owner_id = (select auth.uid()));
create policy owner_reads on deals             for select to authenticated using (owner_id = (select auth.uid()));
create policy owner_reads on deal_costs        for select to authenticated using (owner_id = (select auth.uid()));
create policy owner_reads on deal_commissions  for select to authenticated using (owner_id = (select auth.uid()));
create policy owner_reads on expenses          for select to authenticated using (owner_id = (select auth.uid()));
create policy owner_reads on stock_adjustments for select to authenticated using (owner_id = (select auth.uid()));
create policy owner_reads on khata_entries     for select to authenticated using (owner_id = (select auth.uid()));

revoke all on all tables in schema public from anon, authenticated;
grant select on all tables in schema public to authenticated;
