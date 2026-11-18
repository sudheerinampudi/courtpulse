-- CourtPulse: change the averaging window from 10 minutes to 1 hour.
-- Run once in Supabase → SQL Editor. Safe to re-run.
drop policy if exists "signed-in read reports" on reports;
create policy "signed-in read reports" on reports for select to authenticated using (created_at > now() - interval '1 hour');

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
  left join reports r on r.park_slug = p.slug and r.sport = p_sport and r.created_at > now() - interval '1 hour'
  where (case when p_sport = 'tennis' then p.tennis_courts else p.pickleball_courts end) > 0
  group by p.slug, p.name, p.tennis_courts, p.pickleball_courts, p.lat, p.lng
  order by p.name;
$$;
grant execute on function park_counts(text) to anon, authenticated;

create or replace function park_reports(p_slug text, p_sport text)
returns table (who text, playing int, waiting int, created_at timestamptz)
language sql security definer set search_path = public as $$
  select split_part(btrim(r.reporter_name), ' ', 1)
         || case when position(' ' in btrim(r.reporter_name)) > 0
                 then ' ' || upper(left(regexp_replace(btrim(r.reporter_name), '^.*\s', ''), 1)) || '.' else '' end,
         r.playing, r.waiting, r.created_at
  from reports r
  where r.park_slug = p_slug and r.sport = p_sport and r.created_at > now() - interval '1 hour'
  order by r.created_at desc
  limit 20;
$$;
grant execute on function park_reports(text, text) to anon, authenticated;
