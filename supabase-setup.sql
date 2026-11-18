-- CourtPulse: run once in Supabase → SQL Editor
create table if not exists parks (
  slug text primary key,
  name text not null,
  pickleball_courts int not null default 0,
  tennis_courts int not null default 0
);
create table if not exists reports (
  id bigint generated always as identity primary key,
  park_slug text not null references parks(slug),
  sport text not null check (sport in ('pickleball','tennis')),
  user_id uuid not null default auth.uid() references auth.users(id),
  reporter_name text not null,
  playing int not null check (playing >= 0),
  waiting int not null check (waiting >= 0),
  created_at timestamptz not null default now()
);
create index if not exists reports_recent on reports (park_slug, sport, created_at desc);

-- Enforce per-park maximums: playing <= courts*4, waiting <= courts*2
create or replace function check_report_limits() returns trigger language plpgsql as $$
declare c int;
begin
  select case when new.sport = 'tennis' then tennis_courts else pickleball_courts end into c from parks where slug = new.park_slug;
  if c is null or c = 0 then raise exception 'No % courts at this park', new.sport; end if;
  if new.playing > c*4 then raise exception 'Playing exceeds max of %', c*4; end if;
  if new.waiting > c*2 then raise exception 'Waiting exceeds max of %', c*2; end if;
  return new;
end $$;
drop trigger if exists report_limits on reports;
create trigger report_limits before insert on reports for each row execute function check_report_limits();

alter table parks enable row level security;
alter table reports enable row level security;
drop policy if exists "parks readable" on parks;
create policy "parks readable" on parks for select using (true);
drop policy if exists "signed-in read reports" on reports;
create policy "signed-in read reports" on reports for select to authenticated using (created_at > now() - interval '1 hour');
drop policy if exists "signed-in insert own report" on reports;
create policy "signed-in insert own report" on reports for insert to authenticated with check (user_id = auth.uid());

insert into parks (slug, name, pickleball_courts, tennis_courts) values
 ('lakeside','Lakeside Park',8,4),
 ('heritage','Heritage Courts',6,6),
 ('civic-center','Civic Center',4,3),
 ('oak-grove','Oak Grove',4,3),
 ('riverside','Riverside',2,2)
on conflict (slug) do nothing;
