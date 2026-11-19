-- CourtPulse: players report how busy it is (Free / Moderate / Busy / Very busy) instead of counts.
-- Run once in Supabase → SQL Editor, AFTER supabase-arrivals.sql. Safe to re-run.

alter table reports add column if not exists level smallint check (level between 0 and 3);
alter table reports alter column playing drop not null;
alter table reports alter column waiting drop not null;
-- 0 = Free, 1 = Moderate, 2 = Busy, 3 = Very busy. Older reports (counts only) keep level = null and are ignored.

drop function if exists park_counts(text);
create or replace function park_counts(p_sport text)
returns table (slug text, name text, courts int, lat double precision, lng double precision,
               avg_level numeric, report_count bigint, arriving_today bigint)
language sql security definer set search_path = public as $$
  with coming as (
    select l.park_slug, count(*) as n
    from (
      select distinct on (park_slug, user_id) park_slug, user_id, arriving_at
      from arrivals
      where sport = p_sport and created_at >= (date_trunc('day', now() at time zone 'America/Los_Angeles') at time zone 'America/Los_Angeles')
      order by park_slug, user_id, created_at desc
    ) l
    where l.arriving_at > now() and l.arriving_at < ((date_trunc('day', now() at time zone 'America/Los_Angeles') + interval '1 day') at time zone 'America/Los_Angeles')
    group by l.park_slug
  )
  select p.slug, p.name,
         case when p_sport = 'tennis' then p.tennis_courts else p.pickleball_courts end as courts,
         p.lat, p.lng,
         round(avg(r.level)::numeric, 2), count(r.level), coalesce(max(c.n), 0)
  from parks p
  left join reports r on r.park_slug = p.slug and r.sport = p_sport and r.created_at > now() - interval '2 hours'
  left join coming c on c.park_slug = p.slug
  where (case when p_sport = 'tennis' then p.tennis_courts else p.pickleball_courts end) > 0
  group by p.slug, p.name, p.tennis_courts, p.pickleball_courts, p.lat, p.lng
  order by p.name;
$$;
grant execute on function park_counts(text) to anon, authenticated;

drop function if exists park_reports(text, text);
create or replace function park_reports(p_slug text, p_sport text)
returns table (who text, level smallint, playing int, waiting int, created_at timestamptz)
language sql security definer set search_path = public as $$
  select split_part(btrim(r.reporter_name), ' ', 1)
         || case when position(' ' in btrim(r.reporter_name)) > 0
                 then ' ' || upper(left(regexp_replace(btrim(r.reporter_name), '^.*\s', ''), 1)) || '.' else '' end,
         r.level, r.playing, r.waiting, r.created_at
  from reports r
  where r.park_slug = p_slug and r.sport = p_sport
    and r.created_at >= (date_trunc('day', now() at time zone 'America/Los_Angeles') at time zone 'America/Los_Angeles')
  order by r.created_at desc
  limit 50;
$$;
grant execute on function park_reports(text, text) to anon, authenticated;
