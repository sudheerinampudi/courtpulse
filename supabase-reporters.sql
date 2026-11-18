-- CourtPulse: public "who updated" list for a park (last 24 hours).
-- Shows first name + last initial only (e.g. "Maria S."), never email. Run once in Supabase → SQL Editor.
create or replace function park_reports(p_slug text, p_sport text)
returns table (who text, playing int, waiting int, created_at timestamptz)
language sql security definer set search_path = public as $$
  select split_part(btrim(r.reporter_name), ' ', 1)
         || case when position(' ' in btrim(r.reporter_name)) > 0
                 then ' ' || upper(left(regexp_replace(btrim(r.reporter_name), '^.*\s', ''), 1)) || '.' else '' end,
         r.playing, r.waiting, r.created_at
  from reports r
  where r.park_slug = p_slug and r.sport = p_sport and r.created_at > now() - interval '24 hours'
  order by r.created_at desc
  limit 50;
$$;
grant execute on function park_reports(text, text) to anon, authenticated;
