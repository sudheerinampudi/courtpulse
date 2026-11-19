-- CourtPulse: players can say when they are coming. Run once in Supabase → SQL Editor. Safe to re-run.
alter table reports add column if not exists arriving_at timestamptz;

-- Public "today's updates" list now also returns the arrival time.
drop function if exists park_reports(text, text);
create or replace function park_reports(p_slug text, p_sport text)
returns table (who text, playing int, waiting int, created_at timestamptz, arriving_at timestamptz)
language sql security definer set search_path = public as $$
  select split_part(btrim(r.reporter_name), ' ', 1)
         || case when position(' ' in btrim(r.reporter_name)) > 0
                 then ' ' || upper(left(regexp_replace(btrim(r.reporter_name), '^.*\s', ''), 1)) || '.' else '' end,
         r.playing, r.waiting, r.created_at, r.arriving_at
  from reports r
  where r.park_slug = p_slug and r.sport = p_sport
    and r.created_at >= (date_trunc('day', now() at time zone 'America/Los_Angeles') at time zone 'America/Los_Angeles')
  order by r.created_at desc
  limit 50;
$$;
grant execute on function park_reports(text, text) to anon, authenticated;
