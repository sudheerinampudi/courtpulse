-- CourtPulse partner API: keys, request log, rate limiting.
-- Run once in Supabase → SQL Editor. Safe to re-run.

create table if not exists api_keys (
  id bigint generated always as identity primary key,
  name text not null,
  key_hash text not null unique,
  rate_limit_per_min int not null default 60,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  last_used_at timestamptz
);
create table if not exists api_requests (
  id bigint generated always as identity primary key,
  key_id bigint not null references api_keys(id) on delete cascade,
  at timestamptz not null default now()
);
create index if not exists api_requests_key_at on api_requests (key_id, at desc);

-- Locked down: no policies, so only the server (service role) can read or write these tables.
alter table api_keys enable row level security;
alter table api_requests enable row level security;

-- Called by the Edge Function: checks the key hash, enforces the per-minute limit, logs the request.
create or replace function api_authorize(p_hash text)
returns table (out_ok boolean, out_reason text, out_key_id bigint, out_limit int, out_used int)
language plpgsql security definer set search_path = public as $$
declare k api_keys%rowtype; n int;
begin
  select * into k from api_keys where key_hash = p_hash;
  if not found or not k.active then
    return query select false, 'invalid_key'::text, null::bigint, 0, 0; return;
  end if;
  select count(*) into n from api_requests where key_id = k.id and at > now() - interval '1 minute';
  if n >= k.rate_limit_per_min then
    return query select false, 'rate_limited'::text, k.id, k.rate_limit_per_min, n; return;
  end if;
  insert into api_requests (key_id) values (k.id);
  update api_keys set last_used_at = now() where id = k.id;
  if random() < 0.01 then delete from api_requests where at < now() - interval '7 days'; end if;
  return query select true, 'ok'::text, k.id, k.rate_limit_per_min, n + 1;
end $$;
revoke all on function api_authorize(text) from public, anon, authenticated;

-- Create a partner key (run it yourself in the SQL Editor). The key is shown ONCE; only its hash is stored.
--   select create_api_key('Partner name');          -- default 60 requests/minute
--   select create_api_key('Partner name', 300);     -- custom limit
create or replace function create_api_key(p_name text, p_limit int default 60)
returns text language plpgsql security definer set search_path = public, extensions as $$
declare plain text;
begin
  plain := 'cp_live_' || encode(gen_random_bytes(24), 'hex');
  insert into api_keys (name, key_hash, rate_limit_per_min)
  values (p_name, encode(digest(plain, 'sha256'), 'hex'), p_limit);
  return plain;
end $$;
revoke all on function create_api_key(text, int) from public, anon, authenticated;

-- Revoke a key:   update api_keys set active = false where name = 'Partner name';
-- See usage:      select k.name, count(r.id) as last_24h from api_keys k left join api_requests r on r.key_id = k.id and r.at > now() - interval '24 hours' group by k.name;
