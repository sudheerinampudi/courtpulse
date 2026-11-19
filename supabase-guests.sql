-- CourtPulse: guests can tap "Join" with just a first name (Supabase anonymous sign-in).
-- 1) In Supabase: Authentication → Sign In / Providers → turn ON "Allow anonymous sign-ins".
-- 2) Run this file once in SQL Editor, AFTER supabase-arrivals.sql. Safe to re-run.

alter table arrivals add column if not exists is_guest boolean not null default false;

-- Mark guests, cap guest joins at 3 per 24 hours, and sanity-check the name.
create or replace function check_arrival() returns trigger language plpgsql as $$
begin
  if new.arriving_at < now() - interval '10 minutes' then raise exception 'Arrival time has already passed'; end if;
  if new.arriving_at > now() + interval '12 hours' then raise exception 'Arrival time is too far ahead'; end if;
  new.reporter_name := left(btrim(new.reporter_name), 40);
  if length(new.reporter_name) < 1 then raise exception 'Name is required'; end if;
  new.is_guest := coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false);
  if new.is_guest and (select count(*) from arrivals where user_id = new.user_id and created_at > now() - interval '24 hours') >= 3 then
    raise exception 'Guest join limit reached for today. Sign in to join more.';
  end if;
  return new;
end $$;

-- Busy reports stay for signed-in (email) users only, not guests.
drop policy if exists "signed-in insert own report" on reports;
create policy "signed-in insert own report" on reports for insert to authenticated
  with check (user_id = auth.uid() and not coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false));

-- Coming-soon list: guests show as "Sam (guest)", members as "Sam L."
create or replace function park_arrivals(p_slug text, p_sport text)
returns table (who text, arriving_at timestamptz)
language sql security definer set search_path = public as $$
  select split_part(btrim(l.reporter_name), ' ', 1)
         || case when l.is_guest then ' (guest)'
                 when position(' ' in btrim(l.reporter_name)) > 0
                 then ' ' || upper(left(regexp_replace(btrim(l.reporter_name), '^.*\s', ''), 1)) || '.' else '' end,
         l.arriving_at
  from (
    select distinct on (user_id) user_id, reporter_name, is_guest, arriving_at
    from arrivals
    where park_slug = p_slug and sport = p_sport
      and created_at >= (date_trunc('day', now() at time zone 'America/Los_Angeles') at time zone 'America/Los_Angeles')
    order by user_id, created_at desc
  ) l
  where l.arriving_at > now()
  order by l.arriving_at
  limit 30;
$$;
grant execute on function park_arrivals(text, text) to anon, authenticated;

-- Guest contact details (nickname + email). Private: guests can add their own row, nobody can read them from the website.
create table if not exists guest_contacts (
  user_id uuid primary key default auth.uid() references auth.users(id) on delete cascade,
  nickname text not null check (length(btrim(nickname)) between 2 and 20),
  email text not null check (length(email) <= 254 and email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  created_at timestamptz not null default now()
);
alter table guest_contacts enable row level security;
drop policy if exists "guest adds own contact" on guest_contacts;
create policy "guest adds own contact" on guest_contacts for insert to authenticated
  with check (user_id = auth.uid() and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false));

-- Show the full nickname for guests: "Pickle King (guest)"
create or replace function park_arrivals(p_slug text, p_sport text)
returns table (who text, arriving_at timestamptz)
language sql security definer set search_path = public as $$
  select case when l.is_guest then btrim(l.reporter_name) || ' (guest)'
              else split_part(btrim(l.reporter_name), ' ', 1)
                   || case when position(' ' in btrim(l.reporter_name)) > 0
                           then ' ' || upper(left(regexp_replace(btrim(l.reporter_name), '^.*\s', ''), 1)) || '.' else '' end end,
         l.arriving_at
  from (
    select distinct on (user_id) user_id, reporter_name, is_guest, arriving_at
    from arrivals
    where park_slug = p_slug and sport = p_sport
      and created_at >= (date_trunc('day', now() at time zone 'America/Los_Angeles') at time zone 'America/Los_Angeles')
    order by user_id, created_at desc
  ) l
  where l.arriving_at > now()
  order by l.arriving_at
  limit 30;
$$;
grant execute on function park_arrivals(text, text) to anon, authenticated;
