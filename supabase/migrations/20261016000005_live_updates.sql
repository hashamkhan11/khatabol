-- Lets the app hear about rows changed elsewhere (the WhatsApp bot) and
-- refresh by itself. Supabase Realtime sends a change only to users whose
-- row-level security lets them read the row, so each user hears only their own.
-- Skipped where there is no Realtime (the local test database).

do $$
declare
  t text;
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    return;
  end if;
  foreach t in array array['khata_entries', 'deals', 'expenses', 'stock_adjustments', 'parties', 'items'] loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
