-- CourtPulse: real parks near ZIP 92880 (Corona, CA) + locations for distance search.
-- Run once in Supabase → SQL Editor. Safe to re-run.
-- NOTE: removes the 5 sample parks (Lakeside, Heritage, etc.) and any test reports at them.

alter table parks add column if not exists lat double precision;
alter table parks add column if not exists lng double precision;

delete from reports where park_slug in ('lakeside','heritage','civic-center','oak-grove','riverside');
delete from parks   where slug      in ('lakeside','heritage','civic-center','oak-grove','riverside');

insert into parks (slug, name, pickleball_courts, tennis_courts, lat, lng) values
 ('border-park',        'Border Park',               10, 0, 33.8573, -117.6050),
 ('kellogg-park',       'Kellogg Park',               0, 4, 33.8638, -117.5576),
 ('husted-park',        'Husted Park',                2, 1, 33.8700, -117.5732),
 ('mangular-park',      'Mangular Park',              0, 2, 33.8590, -117.5978),
 ('promenade-park',     'Promenade Community Park',   0, 2, 33.8957, -117.5195),
 ('mountain-gate-park', 'Mountain Gate Park',         0, 4, 33.8407, -117.5732),
 ('eagle-glen-park',    'Eagle Glen Community Park',  0, 3, 33.8166, -117.5312),
 ('el-cerrito-park',    'El Cerrito Sports Park',     0, 2, 33.8348, -117.5280),
 ('kips-korner-park',   'Kips Korner Park',           0, 1, 33.9118, -117.5808)
on conflict (slug) do update set name = excluded.name, pickleball_courts = excluded.pickleball_courts,
  tennis_courts = excluded.tennis_courts, lat = excluded.lat, lng = excluded.lng;

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
