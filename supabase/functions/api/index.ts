// CourtPulse partner API (Supabase Edge Function named "api").
// Endpoints (header  x-api-key: <key>):
//   GET /functions/v1/api/v1/parks?sport=pickleball|tennis&zip=92880&radius=10&limit=50
//   GET /functions/v1/api/v1/parks?sport=tennis&lat=33.95&lng=-117.58&radius=5
//   GET /functions/v1/api/v1/parks/<slug>?sport=pickleball
// Returns counts only: never names or emails.
const SB = Deno.env.get('SUPABASE_URL');
const SK = Deno.env.get('CP_SERVICE_KEY') || Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
const SITE = 'https://sudheerinampudi.github.io/courtpulse/';
const LABELS = ['Free', 'Moderate', 'Busy', 'Very busy'];
const WINDOW_MIN = 120; // must match the window in park_counts (2 hours)
const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'x-api-key, content-type',
  'Access-Control-Allow-Methods': 'GET, OPTIONS',
};
const json = (obj, status = 200, extra = {}) =>
  new Response(JSON.stringify(obj), { status, headers: { 'content-type': 'application/json', ...CORS, ...extra } });
const err = (status, code, message, extra = {}) => json({ error: { code, message } }, status, extra);

async function rpc(name, body) {
  const r = await fetch(`${SB}/rest/v1/rpc/${name}`, {
    method: 'POST',
    headers: { apikey: SK, Authorization: `Bearer ${SK}`, 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });
  if (!r.ok) throw new Error(`${name} failed: ${r.status}`);
  return await r.json();
}
async function sha256(s) {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('');
}
const miles = (a, b, c, d) => {
  const R = 3958.8, r = Math.PI / 180, x = (c - a) * r, y = (d - b) * r;
  const h = Math.sin(x / 2) ** 2 + Math.cos(a * r) * Math.cos(c * r) * Math.sin(y / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });
  if (req.method !== 'GET') return err(405, 'method_not_allowed', 'Use GET.');
  if (!SB || !SK) return err(500, 'server_misconfigured', 'Server is missing its configuration.');

  const key = req.headers.get('x-api-key') || (req.headers.get('authorization') || '').replace(/^Bearer\s+/i, '');
  if (!key) return err(401, 'missing_key', 'Send your API key in the x-api-key header.');

  let auth;
  try {
    const rows = await rpc('api_authorize', { p_hash: await sha256(key.trim()) });
    auth = rows[0];
  } catch (_e) {
    return err(500, 'server_error', 'Could not check the API key.');
  }
  if (!auth || !auth.out_ok) {
    if (auth && auth.out_reason === 'rate_limited')
      return err(429, 'rate_limited', `Limit of ${auth.out_limit} requests per minute reached. Try again shortly.`, { 'Retry-After': '30' });
    return err(401, 'invalid_key', 'That API key is not valid or has been revoked.');
  }
  const rl = { 'X-RateLimit-Limit': String(auth.out_limit), 'X-RateLimit-Remaining': String(Math.max(0, auth.out_limit - auth.out_used)) };

  const url = new URL(req.url);
  const i = url.pathname.indexOf('/v1');
  if (i < 0) return err(404, 'not_found', 'Use /v1/parks or /v1/parks/<slug>.', rl);
  const parts = url.pathname.slice(i).split('/').filter(Boolean); // ['v1','parks',slug?]
  if (parts[0] !== 'v1' || parts[1] !== 'parks' || parts.length > 3) return err(404, 'not_found', 'Use /v1/parks or /v1/parks/<slug>.', rl);

  const sport = (url.searchParams.get('sport') || 'pickleball').toLowerCase();
  if (sport !== 'pickleball' && sport !== 'tennis') return err(400, 'bad_sport', 'sport must be pickleball or tennis.', rl);

  let rows;
  try { rows = await rpc('park_counts', { p_sport: sport }); }
  catch (_e) { return err(500, 'server_error', 'Could not load park data.', rl); }

  const shape = (r, d) => ({
    slug: r.slug, name: r.name, sport, courts: r.courts, lat: r.lat, lng: r.lng,
    distance_miles: d == null ? null : Math.round(d * 10) / 10,
    busyness: r.avg_level == null ? null : LABELS[Math.max(0, Math.min(3, Math.round(Number(r.avg_level))))],
    busyness_level: r.avg_level == null ? null : Math.max(0, Math.min(3, Math.round(Number(r.avg_level)))),
    avg_level: r.avg_level == null ? null : Number(r.avg_level),
    capacity_players: r.courts * 4,
    arriving_today: Number(r.arriving_today),
    reports_in_window: Number(r.report_count),
  });
  const meta = { as_of: new Date().toISOString(), window_minutes: WINDOW_MIN, attribution: `Data from CourtPulse (${SITE})` };

  if (parts.length === 3) {
    const r = rows.find((x) => x.slug === parts[2]);
    if (!r) return err(404, 'park_not_found', `No ${sport} park with slug "${parts[2]}".`, rl);
    return json({ data: shape(r, null), meta }, 200, rl);
  }

  let lat = parseFloat(url.searchParams.get('lat') ?? ''), lng = parseFloat(url.searchParams.get('lng') ?? '');
  const zip = url.searchParams.get('zip');
  if (zip) {
    if (!/^\d{5}$/.test(zip)) return err(400, 'bad_zip', 'zip must be 5 digits.', rl);
    try {
      const z = await fetch(`https://api.zippopotam.us/us/${zip}`);
      if (!z.ok) throw new Error('zip');
      const p = (await z.json()).places[0];
      lat = parseFloat(p.latitude); lng = parseFloat(p.longitude);
    } catch (_e) { return err(404, 'zip_not_found', 'Could not find that ZIP code.', rl); }
  }
  const located = Number.isFinite(lat) && Number.isFinite(lng);
  const radius = Math.min(50, Math.max(1, parseFloat(url.searchParams.get('radius') ?? '10') || 10));
  const limit = Math.min(100, Math.max(1, parseInt(url.searchParams.get('limit') ?? '50', 10) || 50));

  let list = rows.map((r) => ({ r, d: located && r.lat != null ? miles(lat, lng, r.lat, r.lng) : null }));
  if (located) list = list.filter((x) => x.d != null && x.d <= radius).sort((a, b) => a.d - b.d);
  const data = list.slice(0, limit).map((x) => shape(x.r, x.d));
  return json({ data, meta: { ...meta, count: data.length, ...(located ? { center: { lat, lng }, radius_miles: radius } : {}) } }, 200, rl);
});
