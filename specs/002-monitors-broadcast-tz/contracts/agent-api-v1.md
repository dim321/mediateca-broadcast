# Agent API v1

`Broadcast Hub` is the source of truth for a station package. `Station Agent` pulls
the endpoints below over HTTPS. This contract does not select a transport protocol
between the station and Android TV.

## Authentication

Every request requires `Authorization: Bearer <agent-token>`. The Hub resolves the
token to one `Station` by comparing it against the BCrypt `agent_token_digest`.

An operator provisions a token through `Station#assign_agent_token!`; the plain
token is returned once and only its digest is stored. Missing, malformed, and invalid
credentials receive:

```json
{ "error": "unauthorized" }
```

with HTTP `401`.

## GET `/api/agent/v1/package`

Returns HTTP `200` and an `ETag` header. The `etag` and `version` values are the
same SHA-256 checksum of the package manifest, so they change when its schedule,
screen mapping, media, or rotation ordering changes.

```json
{
  "version": "sha256",
  "etag": "sha256",
  "generated_at": "2026-08-03T03:00:00Z",
  "valid_until": "2026-08-04T03:00:00Z",
  "items": [
    {
      "media_plan_id": 42,
      "organization_id": 3,
      "airtime_booking_id": 15,
      "starts_at": "2026-08-03T02:00:00Z",
      "ends_at": "2026-08-03T05:00:00Z",
      "screen_ids": [7],
      "rotation": {
        "id": 11,
        "name": "Morning loop",
        "items": [
          {
            "position": 1,
            "display_duration_seconds": null,
            "media": {
              "id": 19,
              "url": "/rails/active_storage/blobs/redirect/...",
              "mime_type": "video/mp2t"
            }
          }
        ]
      }
    }
  ],
  "screen_map": {
    "7": [42]
  }
}
```

`items` includes **active** MediaPlans that intersect the station cache window
`[now, now + offline_cache_hours]`, are linked to a **confirmed** `AirtimeBooking`
whose window covers the plan, and only the screens belonging to the
authenticated station. Multi-org plans on the same station are returned as a
union; each item carries `organization_id` and `airtime_booking_id`. Video media
uses its prepared `broadcast_file` (`.ts`); non-video media uses its original
file. A video without a prepared `.ts` is omitted. Rotation entries preserve
ascending `position`. Plans without a confirmed covering booking are omitted.

An eligible station with no media plans receives HTTP `200` with `"items": []` and
`"screen_map": {}`. It never receives `204`.

## GET `/api/agent/v1/config`

Returns HTTP `200`:

```json
{
  "station_id": 3,
  "offline_cache_hours": 24,
  "screens": [
    { "id": 7, "name": "Entrance", "orientation": "landscape" }
  ]
}
```

`offline_cache_hours` defines the package horizon and the Agent's local cache
policy. `screens` contains only displays connected to this station.

## POST `/api/agent/v1/play_events`

Records proof-of-play start events. Send:

```json
{
  "events": [
    {
      "screen_id": 7,
      "media_asset_id": 19,
      "started_at": "2026-08-03T03:00:00Z"
    }
  ]
}
```

The Hub accepts only screens belonging to the authenticated station and only
media assets that appear in that station's current package horizon for the given
screen. It creates one `PlayLog` per event with `source: "agent"` and the
organization of the matched media plan. On success it returns HTTP `201`:

```json
{ "play_log_ids": [101] }
```

Unknown station screens return `404`; invalid event records return `422`. The
endpoint is transactional: either all submitted events are stored or none are.

## Deferred endpoints

Heartbeat and alerts are intentionally not part of v1. PlayLog retention is a
separate follow-up; the intended retention period is two months.
