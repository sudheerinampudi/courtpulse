-- CourtPulse: "people coming in the next hour" per park. Run once in Supabase → SQL Editor. Safe to re-run.
-- Needs supabase-arrival.sql to have been run first (adds reports.arriving_at).
-- Counts each player once, using their latest report today at that park. If their latest report says
-- "Here now" (no arrival time), or their arrival time has passed, they are no longer counted as coming.
drop function if exists park_counts(text);
create or replace function park_counts(p_sport text)
returns table (slug text, name text, courts int, lat double precision, lng double precision,
               avg_playing numeric, avg_waiting numeric, report_count bigint, arriving_next_hour bigint)
language sql security definer set search_path = public as $$
  with coming as (
    select l.park_slug, count(*) as n
    from (
      select distinct on (park_slug, user_id) park_slug, user_id, arriving_at
      from reports
      where sport = p_sport
        and created_at >= (date_trunc('day', now() at time zone 'America/Los_Angeles') at time zone 'America/Los_Angeles')
      order by park_slug, user_id, created_at desc
    ) l
    where l.arriving_at > now() and l.arriving_at <= now() + interval '1 hour'
    group by l.park_slug
  )
  select p.slug, p.name,
         case when p_sport = 'tennis' then p.tennis_courts else p.pickleball_courts end as courts,
         p.lat, p.lng,
         coalesce(round(avg(r.playing)), 0), coalesce(round(avg(r.waiting)), 0), count(r.id),
         coalesce(max(c.n), 0)
  from parks p
  left join reports r on r.park_slug = p.slug and r.sport = p_sport and r.created_at > now() - interval '2 hours'
  left join coming c on c.park_slug = p.slug
  where (case when p_sport = 'tennis' then p.tennis_courts else p.pickleball_courts end) > 0
  group by p.slug, p.name, p.tennis_courts, p.pickleball_courts, p.lat, p.lng
  order by p.name;
$$;
grant execute on function park_counts(text) to anon, authenticated;
