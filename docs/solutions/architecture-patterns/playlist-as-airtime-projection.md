---
title: Playlist as Airtime Projection
date: 2026-09-02
category: architecture-patterns
module: playlists
problem_type: architecture_pattern
component: service_object
severity: medium
applies_when:
  - Changing playlist generation, regen hooks, or agent package JSON
  - Tempted to treat playlist rows as airtime truth or certificate source
  - Adding occupy/cancel/reschedule side effects inside ScreenLock or Guard
  - Mixing v1 overlapping-plan JSON with v2 timed entries
  - Choosing a time zone for for_date, insertions, or operating hours
tags:
  - playlist
  - broadcast-portrait
  - airtime
  - agent-api
  - location-time-zone
  - architecture
related_components:
  - BroadcastPortrait
  - Playlist
  - Playlists::GenerateForDate
  - Playlists::EnqueueRegen
  - Playlists::PackageFromPlaylists
  - OccupyWithPlan
  - Cancel
  - Reschedule
---

# Playlist as Airtime Projection

## Context

A station needs a deterministic daily document (commercial slots, filler, insertions, service headers) that the agent can cache for `offline_cache_hours`. Airtime exclusivity is already owned by MediaPlan + confirmed `AirtimeBooking` under first-write-wins (`docs/solutions/architecture-patterns/media-plan-as-airtime-slot.md`). The shipped split is:

1. **Portrait** — operator template of the cyclic hour (`BroadcastPortrait` + blocks). Nullable `station_id` is a fleet template; create-station copies the default.
2. **Playlist** — materialized projection for `(station, date)`: one `current` row, items with `screen_ids`, offsets from the location-TZ day anchor.
3. **Generator** — `Playlists::GenerateForDate` under a station advisory lock (namespace `874_202`, distinct from ScreenLock `874_201`). Fingerprint skip avoids version bumps when inputs did not change.
4. **Regen** — `Playlists::EnqueueRegen` **after** occupy/cancel/reschedule/replace-clip succeed. Cancel uses `update_columns`, so ActiveRecord callbacks cannot be the hook.
5. **Agent** — two URLs. `GET /api/agent/v1/package` is frozen overlapping MediaPlan JSON. `GET /api/agent/v2/package` stitches current playlists; miss returns `entries: []` and enqueues generate, never the v1 body and never 204.

Historical product name “Playlist” in MVP1 is today’s **Rotation**. Do not confuse the two.

## Guidance

1. **Playlist is a projection, not a slot.** Occupy/cancel/reschedule stay the airtime writers. Do not delete `AirtimeBooking`, do not skip Guard, do not build certificates from playlist items. PlayLog remains the fact for future certificates.

2. **Items carry screens.** Screens of one station can sit in different groups. Without `playlist_item_screens`, a station-wide timeline would mix foreign commercials. Merge equal `(offset, asset, source_kind, media_plan_id)` and union `screen_ids`.

3. **Broadcast-day TZ is `locations.time_zone`.** Operating hours are already wall-clock on the location. Do not add `stations.time_zone`. Advertising orders keep using the client organization TZ — that split is intentional.

4. **Hook after the FWW transaction, never inside it.** One `EnqueueRegen.from_plan` (and old window on reschedule) after success. Do not `after_commit` on MediaPlan: cancel will not fire it.

5. **Keep v1 and v2 as two builders.** Do not put `schema_version` on `/v1/package`. Do not generate playlists inside the agent GET (thundering herd). 304/`stale?` belongs on v2 only.

6. **Deterministic filler.** Sequential offset from the epoch date, not `yday`. Random = `Random.new(SHA256 digest)`, never `srand` / `String#hash`.

## Why This Matters

If the playlist becomes a second occupancy writer, FWW and Guard drift from what the agent plays. If regen hangs off AR callbacks, cancel leaves tomorrow’s current playlist showing a dead commercial. If v2 miss falls back to v1 JSON, a new agent treats overlapping plans as timed entries. Location vs organization TZ looks like a bug until you remember orders are commercial documents and playlists are the station’s broadcast day.

## When to Apply

Apply this guidance when:

- Adding a new airtime mutation that should refresh tomorrow’s playlist.
- Changing agent package shape or adding `schema_version`.
- Designing certificates or PlayLog attribution for filler vs commercial.
- Moving portrait storage (jsonb vs normalized blocks) or attaching portraits to groups/screens instead of stations.

## Examples

**AE4 two groups:** Two screens of one station in different groups get two occupying plans in the same hour. Each commercial item’s `screen_ids` ⊆ its group; filler/service may list both screens.

**Cancel:** `Airtime::Cancel` `update_columns` then `EnqueueRegen.from_plan` — the cancelled window’s dates in the location TZ, clamped to today..horizon.

**v2 miss:** No current playlist and no portrait → `entries: []`, enqueue `GenerateForDateJob`, HTTP 200. v1 for the same token still returns overlapping plans.

## Related

- Plan: `docs/plans/2026-09-02-001-feat-broadcast-portrait-playlist-plan.md`
- Brainstorm: `docs/brainstorms/2026-08-27-media-plan-playlist-storage-brainstorm.md`
- Slot pattern: `docs/solutions/architecture-patterns/media-plan-as-airtime-slot.md`
- Contracts: `specs/002-monitors-broadcast-tz/contracts/agent-api-v1.md` (frozen), `agent-api-v2.md`
- Vocabulary: `CONCEPTS.md` (Broadcast portrait, Playlist, Location time zone)
- Generator / regen: `app/domain/playlists/generate_for_date.rb`, `app/domain/playlists/enqueue_regen.rb`
- Agent: `app/domain/playlists/package_from_playlists.rb`, `app/domain/agent/package_builder.rb`
