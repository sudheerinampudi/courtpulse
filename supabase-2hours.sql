-- CourtPulse: live averages cover the last 2 hours (update lists stay on 'today').
-- Run once in Supabase → SQL Editor. Safe to re-run.
drop function if exists park_counts(text);
create or replace function park_counts(p_sport text)
returns table (slug text, name text, courts int, lat double precision, lng double precision,
               avg_playing numeric, avg_waiting numeric, report_count bigint)
language sql security definer set search_path = public as $$
  select p.slug, p.name,
         case when p_sport = 'tennis' then p.tennis_courts else p.pickleball_courts end as courts,
         p.lat, p.lng,
         coalesce(round(avg(r.playing)), 0), coalesce(round(avg(r.waiting)), 0), count(r.id)
  from parks p
  left join reports r on r.park_slug = p.slug and r.sport = p_sport and r.created_at > now() - interval '2 hours'
  where (case when p_sport = 'tennis' then p.tennis_courts else p.pickleball_courts end) > 0
  group by p.slug, p.name, p.tennis_courts, p.pickleball_courts, p.lat, p.lng
  order by p.name;
$$;
grant execute on function park_counts(text) to anon, authenticated;
