# CourtPulse partner API (v1)

Live, crowd-reported player counts at tennis and pickleball courts. Read-only. Counts only: no names or emails.

**Base URL:** `https://wjedvyqtqgvclxxsxyox.supabase.co/functions/v1/api`
**Auth:** send your key in the `x-api-key` header. Keys are issued by CourtPulse.
**Limit:** 60 requests per minute per key by default. Responses carry `X-RateLimit-Limit` and `X-RateLimit-Remaining`; over the limit returns `429`.
**Attribution:** please credit "Data from CourtPulse".

## GET /v1/parks
Query parameters:
| name | meaning |
|---|---|
| `sport` | `pickleball` (default) or `tennis` |
| `zip` | 5-digit US ZIP; sorts by distance and filters by `radius` |
| `lat`, `lng` | alternative to `zip` |
| `radius` | miles, default 10, max 50 (used with zip or lat/lng) |
| `limit` | default 50, max 100 |

```
curl -H "x-api-key: YOUR_KEY" \
  "https://wjedvyqtqgvclxxsxyox.supabase.co/functions/v1/api/v1/parks?sport=tennis&zip=92880&radius=5"
```
```json
{
  "data": [
    {
      "slug": "mountain-view-park", "name": "Mountain View Park", "sport": "tennis",
      "courts": 2, "lat": 33.9506, "lng": -117.5997, "distance_miles": 1.2,
      "busyness": "Busy", "busyness_level": 2, "avg_level": 2.0,
      "capacity_players": 8, "arriving_today": 3,
      "reports_in_window": 3
    }
  ],
  "meta": { "as_of": "2026-11-18T23:10:00.000Z", "window_minutes": 120,
            "attribution": "Data from CourtPulse (...)", "count": 1,
            "center": { "lat": 33.95, "lng": -117.58 }, "radius_miles": 5 }
}
```

## GET /v1/parks/{slug}?sport=...
One park, same fields (no distance).

## Reading the numbers
- `busyness` / `busyness_level`: Free (0), Moderate (1), Busy (2), Very busy (3): the average of player reports in the last `window_minutes` (120), rounded. `avg_level` is the unrounded 0-3 average. All are `null` when there are no recent reports.
- `capacity_players`: about 4 players per court. `arriving_today`: players coming later today.
- `reports_in_window`: how many reports the average is based on. `0` means no recent data; `busyness` is `null` (unknown, not free).
- Busyness is self-reported by players and may be approximate.

## Errors
`{ "error": { "code": "...", "message": "..." } }` with `400` bad parameter, `401` missing/invalid key, `404` not found, `429` rate limited.
