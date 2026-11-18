-- CourtPulse home page: run once in Supabase → SQL Editor
-- Public live counts (average of reports from the last hour). Exposes only totals, never names.
create or replace function park_counts(p_sport text)
returns table (slug text, name text, courts int, avg_playing numeric, avg_waiting numeric, report_count bigint)
language sql security definer set search_path = public as $$
  select p.slug, p.name,
         case when p_sport = 'tennis' then p.tennis_courts else p.pickleball_courts end as courts,
         coalesce(round(avg(r.playing)), 0) as avg_playing,
         coalesce(round(avg(r.waiting)), 0) as avg_waiting,
         count(r.id) as report_count
  from parks p
  left join reports r on r.park_slug = p.slug and r.sport = p_sport and r.created_at > now() - interval '1 hour'
  where (case when p_sport = 'tennis' then p.tennis_courts else p.pickleball_courts end) > 0
  group by p.slug, p.name, p.tennis_courts, p.pickleball_courts
  order by avg(r.playing) desc nulls last, p.name;
$$;
grant execute on function park_counts(text) to anon, authenticated;
