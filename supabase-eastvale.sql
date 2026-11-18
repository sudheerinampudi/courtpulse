-- CourtPulse: add Eastvale parks (ZIP 92880). Run in Supabase → SQL Editor after supabase-parks.sql. Safe to re-run.
alter table parks add column if not exists lat double precision;
alter table parks add column if not exists lng double precision;

insert into parks (slug, name, pickleball_courts, tennis_courts, lat, lng) values
 ('mountain-view-park',    'Mountain View Park',     8, 2, 33.9506, -117.5997),
 ('huber-park',            'James C. Huber Park',    1, 2, 33.9721, -117.5902),
 ('eastvale-tennis',       'Eastvale Tennis Courts', 0, 10, 33.9553, -117.5681),
 ('celebration-park',      'Celebration Park',       0, 1, 33.9833, -117.5894),
 ('mccune-park',           'McCune Park',            0, 1, 33.9527, -117.5893),
 ('nature-retreat-park',   'Nature Retreat Park',    0, 2, 33.9655, -117.6386)
on conflict (slug) do update set name = excluded.name, pickleball_courts = excluded.pickleball_courts,
  tennis_courts = excluded.tennis_courts, lat = excluded.lat, lng = excluded.lng;
