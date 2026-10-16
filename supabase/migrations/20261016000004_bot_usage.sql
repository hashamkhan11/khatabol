-- How much of the AI model each message used, to know what the bot costs
-- before paying for it. One row per message the model read.

create table bot_usage (
  id              bigint generated always as identity primary key,
  whatsapp        text not null references bot_senders (whatsapp),
  wa_id           text not null,
  kind            text not null constraint bot_usage_kind check (kind in ('text', 'audio', 'image')),
  model           text not null,
  input_tokens    integer not null default 0 check (input_tokens >= 0),
  output_tokens   integer not null default 0 check (output_tokens >= 0),
  thinking_tokens integer not null default 0 check (thinking_tokens >= 0),
  -- the part of input_tokens that was the voice note or photo
  media_tokens    integer not null default 0 check (media_tokens >= 0),
  created_at      timestamptz not null default now()
);
create index bot_usage_created_idx on bot_usage (created_at);

alter table bot_usage enable row level security;
revoke all on bot_usage from anon, authenticated;

create function bot_log_usage(
  p_whatsapp text, p_wa_id text, p_kind text, p_model text,
  p_input integer, p_output integer, p_thinking integer, p_media integer
) returns void
language sql security definer set search_path = public as $$
  insert into bot_usage (whatsapp, wa_id, kind, model, input_tokens, output_tokens, thinking_tokens, media_tokens)
  values (p_whatsapp, p_wa_id, p_kind, p_model,
          coalesce(p_input, 0), coalesce(p_output, 0), coalesce(p_thinking, 0), coalesce(p_media, 0))
$$;

revoke execute on function bot_log_usage(text, text, text, text, integer, integer, integer, integer)
from public, anon, authenticated;
grant execute on function bot_log_usage(text, text, text, text, integer, integer, integer, integer)
to service_role;

-- Per day, in Pakistan time. est_usd is what the day would cost on the paid
-- plan at gemini-3.8-flash prices for 2026 (input $0.75, output and thinking
-- $3.75 per million tokens); the free plan costs nothing.
--   select * from bot_usage_daily;
create view bot_usage_daily with (security_invoker = true) as
select (created_at at time zone 'Asia/Karachi')::date        as day,
       count(*)                                              as messages,
       count(*) filter (where kind = 'audio')                as voice_notes,
       count(*) filter (where kind = 'image')                as photos,
       sum(input_tokens)                                     as input_tokens,
       sum(output_tokens + thinking_tokens)                  as output_tokens,
       round((sum(input_tokens) * 0.75
            + sum(output_tokens + thinking_tokens) * 3.75) / 1e6, 4) as est_usd
from bot_usage
group by 1
order by 1 desc;

revoke all on bot_usage_daily from anon, authenticated;
