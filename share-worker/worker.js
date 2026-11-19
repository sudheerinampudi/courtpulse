// Play Pulse share link (Cloudflare Worker).
// WhatsApp reads the link preview from the first page it fetches and does not run JavaScript.
// This Worker returns a tiny page whose preview tags hold the LIVE numbers, then sends people on to the real park page.
// Share links look like:  https://<your-worker>.workers.dev/p/mountain-view-park

const SITE = 'https://sudheerinampudi.github.io/playpulse/';
const SUPABASE_URL = 'https://wjedvyqtqgvclxxsxyox.supabase.co';
const SUPABASE_KEY = 'sb_publishable_EDOf8NAuJK8AbWhDLKzjmQ_gNcBpSb6'; // publishable (public) key, same as the website
const LEVELS = ['Free', 'Moderate', 'Busy', 'Very busy'];

const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

function hint(level, courts) {
  const cap = courts * 4, a = Math.floor(cap * 0.25), b = Math.max(a + 1, Math.floor(cap * 0.6)), top = Math.max(b + 1, cap - 1);
  const r = (x, y) => (x >= y ? `${y}` : `${x}-${y}`);
  return ['about ' + r(0, a) + ' players', 'about ' + r(a + 1, b) + ' players', 'about ' + r(b + 1, top) + ' players', 'courts full, people waiting'][level];
}

export default {
  async fetch(req) {
    const url = new URL(req.url);
    const m = url.pathname.match(/^\/p\/([a-z0-9-]{1,80})\/?$/i);
    if (!m) return new Response('Play Pulse share link. Use /p/<park-slug>', { status: 404 });
    const slug = m[1].toLowerCase();
    const sport = url.searchParams.get('sport') === 'tennis' ? 'tennis' : 'pickleball';
    const target = `${SITE}?park=${encodeURIComponent(slug)}`;

    let title = 'Play Pulse: see how busy the courts are';
    let desc = 'Live court activity from players near you.';
    try {
      const r = await fetch(`${SUPABASE_URL}/rest/v1/rpc/park_counts`, {
        method: 'POST',
        headers: { apikey: SUPABASE_KEY, Authorization: `Bearer ${SUPABASE_KEY}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ p_sport: sport }),
      });
      const rows = r.ok ? await r.json() : [];
      const p = rows.find((x) => x.slug === slug);
      if (p) {
        const lvl = p.avg_level == null ? null : Math.max(0, Math.min(3, Math.round(Number(p.avg_level))));
        const coming = Number(p.arriving_today) || 0;
        const time = new Date().toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', timeZone: 'America/Los_Angeles' });
        title = lvl == null ? `${p.name} · no recent reports` : `${p.name} · ${LEVELS[lvl]} right now`;
        desc = (lvl == null ? 'Be the first to report how busy it is' : hint(lvl, p.courts)[0].toUpperCase() + hint(lvl, p.courts).slice(1))
          + (coming ? ` · ${coming} coming later today` : '')
          + ` · ${sport === 'tennis' ? 'Tennis' : 'Pickleball'} · updated ${time}`;
      }
    } catch (_e) { /* fall back to the generic preview */ }

    const html = `<!doctype html><html lang="en"><head><meta charset="utf-8">
<title>${esc(title)}</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta property="og:type" content="website"><meta property="og:site_name" content="Play Pulse">
<meta property="og:title" content="${esc(title)}"><meta property="og:description" content="${esc(desc)}">
<meta property="og:image" content="${SITE}icon.png?v=4"><meta property="og:url" content="${esc(target)}">
<meta name="twitter:card" content="summary"><meta name="description" content="${esc(desc)}">
<meta http-equiv="refresh" content="0;url=${esc(target)}"></head>
<body><p>Opening <a href="${esc(target)}">Play Pulse</a>…</p><script>location.replace(${JSON.stringify(target)})</script></body></html>`;
    return new Response(html, { headers: { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'public, max-age=60' } });
  },
};
