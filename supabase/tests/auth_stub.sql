-- LOCAL TESTS ONLY. Mimics the parts of Supabase the migrations rely on
-- (auth.users, auth.uid(), the anon/authenticated roles). Never deploy this.
create schema auth;
create table auth.users (id uuid primary key);

create function auth.uid() returns uuid
language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;

create role anon nologin;
create role authenticated nologin;
create role service_role nologin;
grant usage on schema auth to anon, authenticated;
grant execute on function auth.uid() to anon, authenticated;
