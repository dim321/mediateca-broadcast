# Agent API v2

Successor of [`agent-api-v1.md`](agent-api-v1.md). New station agents pull
`GET /api/agent/v2/package`. v1 remains frozen for agents still on the overlapping
MediaPlan shape.

## Authentication

Same as v1: `Authorization: Bearer <agent-token>`. Missing, malformed, and invalid
credentials receive HTTP `401`:

```json
{ "error": "unauthorized" }
```

## GET `/api/agent/v2/package`

Returns HTTP `200` and an `ETag` header. `Cache-Control` is `private, must-revalidate`.
The `etag` and `version` values are the same SHA-256 checksum of the stitched
`entries` manifest (without `generated_at` / `valid_until`), so they change when
timing, screens, media, or source kind change.

A request with `If-None-Match` equal to that ETag receives HTTP `304` and no body.

The body is a timed playlist projection, never the v1 `items` / rotation shape.
It never returns `204`. There is no `schema_version` discriminator; the URL is
the version.

```json
{
  "version": "sha256",
  "etag": "sha256",
  "generated_at": "2026-09-02T12:00:00Z",
  "valid_until": "2026-09-03T12:00:00Z",
  "entries": [
    {
      "for_date": "2026-09-02",
      "broadcast_day_starts_at": "2026-09-02T02:00:00Z",
      "position": 1,
      "offset_seconds": 0,
      "starts_at": "2026-09-02T02:00:00Z",
      "duration_seconds": 10,
      "source_kind": "service",
      "media_plan_id": null,
      "screen_ids": [7, 8],
      "media": {
        "id": 19,
        "url": "/rails/active_storage/blobs/redirect/...",
        "mime_type": "video/mp2t"
      }
    }
  ],
  "screen_map": {
    "7": [0, 1, 2]
  }
}
```

`entries` concatenates **current** playlists whose local calendar dates overlap
`[now, now + offline_cache_hours]` (location TZ), ordered by `for_date` then
`position`. `starts_at` is `broadcast_day_starts_at + offset_seconds`. Video media
uses the prepared `broadcast_file` (`.ts`); non-video uses the original file. An
item without a delivery attachment is omitted.

`screen_map` maps `screen_id` → 0-based indexes into `entries`.

No current playlist for a horizon date, or a current playlist with zero items
(closed weekday), contributes no rows. The response is still HTTP `200` with
`"entries": []` and `"screen_map": {}`. Missing current playlists enqueue
`Playlists::GenerateForDateJob`; the request does not generate inline and does
not fall back to the v1 body.

`source_kind` is one of `media_plan`, `filler`, `insertion`, `service`.
`media_plan_id` is present only for commercial items copied from an occupying
plan.

## POST `/api/agent/v1/play_events`

Play events stay on the v1 URL. When the station has a **current** playlist in
the cache horizon, eligibility is a playlist item (current, or superseded with
`generated_at >= 2 hours ago`) for that screen and media asset:

- `source_kind=media_plan` → PlayLog organization is the plan's organization if
  the plan is still `active` and its booking is `confirmed`; otherwise the
  operator organization.
- `filler` / `insertion` / `service` → operator organization.

If no current playlist exists in the horizon, the hub keeps the v1 overlapping
MediaPlan match so the old agent fleet can still record proof-of-play.

Unknown station screens or ineligible media return `404`. The endpoint stays
transactional: all submitted events are stored or none are.
