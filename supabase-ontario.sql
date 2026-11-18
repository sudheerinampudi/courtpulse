-- CourtPulse: add Ontario, CA parks. Run in Supabase → SQL Editor after supabase-parks.sql. Safe to re-run.
alter table parks add column if not exists lat double precision;
alter table parks add column if not exists lng double precision;

insert into parks (slug, name, pickleball_courts, tennis_courts, lat, lng) values
 ('del-rancho-park', 'Del Rancho Park', 0, 8, 34.0377, -117.6661),
 ('westwind-park',   'Westwind Park',   0, 3, 34.0203, -117.5989),
 ('olympic-park',    'Olympic Park',    0, 2, 33.9934, -117.6654),
 ('creekside-park',  'Creekside Park',  0, 1, 34.0201, -117.5834)
on conflict (slug) do update set name = excluded.name, pickleball_courts = excluded.pickleball_courts,
  tennis_courts = excluded.tennis_courts, lat = excluded.lat, lng = excluded.lng;
