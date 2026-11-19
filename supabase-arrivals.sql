-- CourtPulse: "I'm coming" is its own action, separate from "Share update".
-- Run once in Supabase → SQL Editor. Safe to re-run. (Replaces supabase-arrival.sql and supabase-coming.sql.)

create table if not exists arrivals (
  id bigint generated always as identity primary key,
  park_slug text not null references parks(slug),
  sport text not null check (sport in ('pickleball','tennis')),
  user_id uuid not null default auth.uid() references auth.users(id),
  reporter_name text not null,
  arriving_at timestamptz not null,
  created_at timestamptz not null default now()
);
create index if not exists arrivals_lookup on arrivals (park_slug, sport, created_at desc);

create or replace function check_arrival() returns trigger language plpgsql as $$
begin
  if new.arriving_at < now() - interval '10 minutes' then raise exception 'Arrival time has already passed'; end if;
  if new.arriving_at > now() + interval '12 hours' then raise exception 'Arrival time is too far ahead'; end if;
  return new;
end $$;
drop trigger if exists arrival_check on arrivals;
create trigger arrival_check before insert on arrivals for each row execute function check_arrival();

alter table arrivals enable row level security;
drop policy if exists "insert own arrival" on arrivals;
create policy "insert own arrival" on arrivals for insert to authenticated with check (user_id = auth.uid());
drop policy if exists "read own arrivals" on arrivals;
create policy "read own arrivals" on arrivals for select to authenticated using (user_id = auth.uid());

-- Live counts: averages of the last 2 hours + people coming in the next hour (each player counted once, latest arrival).
drop function if exists park_counts(text);
create or replace function park_counts(p_sport text)
returns table (slug text, name text, courts int, lat double precision, lng double precision,
               avg_playing numeric, avg_waiting numeric, report_count bigint, arriving_next_hour bigint)
language sql security definer set search_path = public as $$
  with coming as (
    select l.park_slug, count(*) as n
    from (
      select distinct on (park_slug, user_id) park_slug, user_id, arriving_at
      from arrivals
      where sport = p_sport and created_at > now() - interval '12 hours'
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

-- Today's updates list (no arrival column any more).
drop function if exists park_reports(text, text);
create or replace function park_reports(p_slug text, p_sport text)
returns table (who text, playing int, waiting int, created_at timestamptz)
language sql security definer set search_path = public as $$
  select split_part(btrim(r.reporter_name), ' ', 1)
         || case when position(' ' in btrim(r.reporter_name)) > 0
                 then ' ' || upper(left(regexp_replace(btrim(r.reporter_name), '^.*\s', ''), 1)) || '.' else '' end,
         r.playing, r.waiting, r.created_at
  from reports r
  where r.park_slug = p_slug and r.sport = p_sport
    and r.created_at >= (date_trunc('day', now() at time zone 'America/Los_Angeles') at time zone 'America/Los_Angeles')
  order by r.created_at desc
  limit 50;
$$;
grant execute on function park_reports(text, text) to anon, authenticated;

-- Who is coming (upcoming arrivals only; first name + last initial).
create or replace function park_arrivals(p_slug text, p_sport text)
returns table (who text, arriving_at timestamptz)
language sql security definer set search_path = public as $$
  select split_part(btrim(l.reporter_name), ' ', 1)
         || case when position(' ' in btrim(l.reporter_name)) > 0
                 then ' ' || upper(left(regexp_replace(btrim(l.reporter_name), '^.*\s', ''), 1)) || '.' else '' end,
         l.arriving_at
  from (
    select distinct on (user_id) user_id, reporter_name, arriving_at
    from arrivals
    where park_slug = p_slug and sport = p_sport and created_at > now() - interval '12 hours'
    order by user_id, created_at desc
  ) l
  where l.arriving_at > now()
  order by l.arriving_at
  limit 30;
$$;
grant execute on function park_arrivals(text, text) to anon, authenticated;
