---
title: Playlist as Airtime Projection
date: 2026-09-02
last_updated: 2026-09-02
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

A station agent needs a deterministic daily document — commercial slots, filler, timed insertions, service headers — that it can cache for `offline_cache_hours`. Airtime exclusivity is already owned by MediaPlan plus a confirmed `AirtimeBooking` under first-write-wins (`docs/solutions/architecture-patterns/media-plan-as-airtime-slot.md`).

The late-August 2026 brainstorm started from that slot writer and an on-the-fly `Agent::PackageBuilder`, with no portrait and no daily playlist row. Leaving the playlist virtual failed the ТЗ (no durable station×date document to join to `PlayLog`); a jsonb portrait was rejected because the grid had to be queryable rows. The fork was a persisted daily projection, not another occupy path. Occupancy stays on occupy/cancel/reschedule; generation is downstream. (session history)

The shipped split is five parts (portrait, playlist, generator, regen, agent with two URLs):

1. **Portrait** — operator template of the cyclic hour (`BroadcastPortrait` plus blocks). `station_id` is optional: a row with `station_id` nil is a fleet template (`app/models/broadcast_portrait.rb:36`, `scope :templates` at `app/models/broadcast_portrait.rb:40`). Creating a station copies an assigned template via `Portraits::CopyTemplate` (`app/controllers/admin/stations_controller.rb:30`). Updating a station with a `template_id` copies with `replace: true` (`app/controllers/admin/stations_controller.rb:44-45`).

2. **Playlist** — materialized projection for `(station, date)`. Exactly one `current` row per station and date (unique index `app/models/playlist.rb:23`, validation `app/models/playlist.rb:49`). Items carry `offset_seconds` from the location-TZ day anchor (`app/domain/playlists/generate_for_date.rb:358-360`) and screens via `playlist_item_screens`.

3. **Generator** — `Playlists::GenerateForDate` runs inside a transaction that first takes `Playlists::StationDateLock` (`app/domain/playlists/generate_for_date.rb:14-15`). Fingerprint equality skips persist so an unchanged input set does not bump `version` (`app/domain/playlists/generate_for_date.rb:19-23`). Occupying plans for a date are active MediaPlans with confirmed bookings overlapping the location-TZ day (`app/domain/playlists/fingerprint.rb:17-38`). Missing portrait skips with no playlist row (`skipped: :missing_portrait`, `app/domain/playlists/generate_for_date.rb:17`).

4. **Regen** — `Playlists::EnqueueRegen` is called **after** occupy / cancel / reschedule / replace-clip succeed. It is not invoked inside the occupy transaction and is not an ActiveRecord callback. Cancel uses `update_columns`, so an `after_commit` on MediaPlan would miss it.

5. **Agent** — two URLs, two builders. `GET /api/agent/v1/package` still builds overlapping MediaPlan JSON via `Agent::PackageBuilder` (`app/controllers/api/agent/v1/packages_controller.rb:8`). `GET /api/agent/v2/package` stitches current playlists via `Playlists::PackageFromPlaylists` (`app/controllers/api/agent/v2/packages_controller.rb:8`). A miss returns `entries: []` and enqueues generate; it never inlines `GenerateForDate` and never falls back to the v1 body.

Historical product name “Playlist” in MVP1 is today’s **Rotation**. The 2026-08-01 hub plan recorded the rename (`docs/plans/2026-08-01-001-feat-broadcast-hub-mvp1-plan.md:46`, KTD5 at line 216). The `Playlist` model in this tree is the daily projection (`app/models/playlist.rb:29`), not a loop of clips. `Rotation` remains the catalog (`app/models/rotation.rb`). Do not confuse the two.

## Guidance

### Playlist is a projection, not occupancy truth

Occupy, cancel, and reschedule remain the airtime writers. They create or mutate MediaPlan + AirtimeBooking under `Airtime::ScreenLock` and `ScreenOverlapGuard`. They do not persist playlist rows inside that transaction.

`Airtime::OccupyWithPlan#call` opens `MediaPlan.transaction`, takes `ScreenLock`, runs `ScreenOverlapGuard`, creates the confirmed booking and active plan, then **after** the transaction block calls `Playlists::EnqueueRegen.from_plan(plan)` (`app/domain/airtime/occupy_with_plan.rb:28-56`). Generation is not inside the lock.

`Airtime::Cancel#call` locks the plan and booking, takes `ScreenLock`, then `update_columns` on both records so cancel still frees the slot when later validations would fail (`app/domain/airtime/cancel.rb:11-31`). After the transaction it calls `Playlists::EnqueueRegen.from_plan(cancelled)` (`app/domain/airtime/cancel.rb:33`). Because `update_columns` skips ActiveRecord callbacks, regen must be explicit; hanging `after_commit` on MediaPlan would leave tomorrow’s current playlist showing a cancelled commercial.

`Airtime::Reschedule#call` captures the old group and window, then in one transaction moves booking and plan. After success it enqueues the **new** window via `from_plan(updated)` and the **old** window via `from_group_window(group: old_group, starts_at: old_starts_at, ends_at: old_ends_at)` (`app/domain/airtime/reschedule.rb:16-18`, `app/domain/airtime/reschedule.rb:69-70`). Skipping the old window would leave the vacated dates still projecting the moved plan.

Do not delete `AirtimeBooking` to “sync” a playlist. Do not skip Guard. Do not build certificates from playlist items. Play facts are written as `PlayLog` rows from agent play events (`app/controllers/api/agent/v1/play_events_controller.rb:30-36`). Certificates, when added, must be built from orders and play logs, not from playlist rows.

Clip replacement is not an occupancy rewrite: `Advertising::ReplaceClip` swaps the rotation item, then `EnqueueRegen.from_plan` for each active plan (`app/domain/advertising/replace_clip.rb:14-27`). That matches the earlier order-plan decision that clip swap must not cancel/occupy. (session history)

### Distinct advisory-lock namespaces

`Playlists::GenerateForDate` serializes per station with `Playlists::StationDateLock`. That lock’s namespace is `874_202` and the payload is `station.id` (`app/domain/playlists/station_date_lock.rb:7-17`). The comment on the class states the namespace is distinct from `Airtime::ScreenLock` (`app/domain/playlists/station_date_lock.rb:5`).

`Airtime::ScreenLock` uses namespace `874_201` and locks each `screen_id` (`app/domain/airtime/screen_lock.rb:7-18`). Both use `pg_advisory_xact_lock`, so they live for the surrounding transaction only. Because the namespaces differ, a station id that happens to equal a screen id cannot collide. Do not reuse `874_201` for playlist generation, and do not take ScreenLock inside `GenerateForDate`.

### EnqueueRegen: location TZ horizon, overlapping dates from the plan window

`Playlists::EnqueueRegen#call` loads stations with locations, intersects requested dates with `horizon_dates(station)`, and `perform_later`s `GenerateForDateJob` for unique pairs (`app/domain/playlists/enqueue_regen.rb:10-23`). It does not call `GenerateForDate` inline.

`horizon_dates` takes **today in the station location’s time zone**, then `span = (station.offline_cache_hours.to_f / 24.0).ceil`, and returns the inclusive range `today..(today + span)` (`app/domain/playlists/enqueue_regen.rb:72-76`). Station `offline_cache_hours` defaults to 24 (`app/models/station.rb:10`). Location `time_zone` is an IANA zone defaulting to `"UTC"` (`app/models/location.rb:10`). Do not invent `stations.time_zone`; the broadcast day is `locations.time_zone`. Advertising orders still use the client organization TZ — that split is intentional.

`from_plan` is a thin wrapper: blank plan is a no-op; otherwise `from_group_window` with the plan’s group and `starts_at`/`ends_at` (`app/domain/playlists/enqueue_regen.rb:26-30`). `from_group_window` walks unique stations of the group’s screens and enqueues `overlapping_dates(station, starts_at, ends_at)` (`app/domain/playlists/enqueue_regen.rb:32-38`). `overlapping_dates` converts the window into the location zone; if `ends_at` is exactly `beginning_of_day`, the end date is exclusive (`end_time.to_date - 1`) so a midnight exclusive end does not pull the next calendar day (`app/domain/playlists/enqueue_regen.rb:78-89`).

Other hooks (`from_station`, `from_location`, `from_screen`, `from_rotation`) exist for portrait, location hours, membership, and rotation edits. They are regen entry points, not occupancy writers.

### Two package builders; v2 miss enqueues, never generates inline

`Playlists::PackageFromPlaylists#call` asks `EnqueueRegen.horizon_dates(station)`, loads current playlists for those dates (`app/domain/playlists/package_from_playlists.rb:11-13`), computes `missing = dates - playlists.map(&:for_date)`, and if any dates are missing calls `EnqueueRegen.call` — not `GenerateForDate.call` (`app/domain/playlists/package_from_playlists.rb:13-14`). The JSON shape is `entries` plus `screen_map`; there is no `items` key. ETag is SHA-256 of the entries payload without package `generated_at` / `valid_until` (`app/domain/playlists/package_from_playlists.rb:16-17`, `app/domain/playlists/package_from_playlists.rb:69-76`). `valid_until` is `now + station.offline_cache_hours.hours` (`app/domain/playlists/package_from_playlists.rb:23`).

v1 `Agent::PackageBuilder` is unchanged overlapping-plan JSON: active MediaPlans whose windows overlap `[now, horizon]`, nested rotation items. `screen_map` maps screen id to `media_plan_id` values (`app/domain/agent/package_builder.rb:10-16`, `app/domain/agent/package_builder.rb:106-110`). v2 `screen_map` maps screen id to entry indexes (`app/domain/playlists/package_from_playlists.rb:78-81`). `Api::Agent::V1::PackagesController#show` always `render json: package` after setting ETag; it does not call `stale?` (`app/controllers/api/agent/v1/packages_controller.rb:7-12`). Do not put `schema_version` on `/v1/package`. Do not generate playlists inside the agent GET.

v2 `Api::Agent::V2::PackagesController#show` calls `PackageFromPlaylists`, then `stale?(etag: package[:etag], template: false)` (`app/controllers/api/agent/v2/packages_controller.rb:8-9`). Fresh body: 200 JSON. Matching `If-None-Match`: 304 (Rails `stale?` false branch, `app/controllers/api/agent/v2/packages_controller.rb:12-14`). Cache-Control is `private, must-revalidate` (`app/controllers/api/agent/v2/packages_controller.rb:19-21`). 304 belongs on v2 only.

### Play events: playlist path if current exists in the horizon, else legacy

`Playlists::ResolvePlayEvent#call` branches on `current_playlist_in_horizon?` (`app/domain/playlists/resolve_play_event.rb:15-19`). That predicate is `station.playlists.current.where(for_date: EnqueueRegen.horizon_dates(station)).exists?` (`app/domain/playlists/resolve_play_event.rb:26-28`). If true, `from_playlist` joins `playlist_item_screens` for the reporting screen, matches `media_asset_id`, and accepts `current` or a `superseded` playlist generated within the last two hours (`app/domain/playlists/resolve_play_event.rb:30-44`). Organization for a `media_plan` item is the plan’s organization only when the plan is still active and its booking confirmed; otherwise the operator organization (`app/domain/playlists/resolve_play_event.rb:50-57`). If there is no current playlist in the horizon, `from_legacy_plan` matches an overlapping MediaPlan via the rotation item — the v1-fleet path (`app/domain/playlists/resolve_play_event.rb:59-73`). The play-events controller always goes through this resolver (`app/controllers/api/agent/v1/play_events_controller.rb:23-27`).

### Neutral min default 10, inclusion `[5, 10]`

`broadcast_portraits.neutral_min_seconds` defaults to 10 at the column (`app/models/broadcast_portrait.rb:13`) and is validated `inclusion: { in: [ 5, 10 ] }` (`app/models/broadcast_portrait.rb:51`). `GenerateForDate` passes `portrait.neutral_min_seconds` into filler and insertion picks (`app/domain/playlists/generate_for_date.rb:121`, `app/domain/playlists/generate_for_date.rb:190`). Commercial clips from an occupying plan use `min_seconds: nil` so a short ad is not dropped (`app/domain/playlists/generate_for_date.rb:206`). `NeutralPicker#eligible?` rejects a clip when `min_seconds` is present and duration is below it (`app/domain/playlists/neutral_picker.rb:49`).

### Items have `playlist_item_screens`

Screens of one station can sit in different groups. A station-wide timeline without per-item screens would mix foreign commercials. `PlaylistItem` has `has_many :playlist_item_screens` and `has_many :screens, through: :playlist_item_screens` (`app/models/playlist_item.rb:44-45`). Validation `must_have_screens` requires at least one (`app/models/playlist_item.rb:59-66`). The join is unique on `(playlist_item_id, screen_id)` (`app/models/playlist_item_screen.rb:15`). The generator builds one emission per screen then merges equal `(offset_seconds, media_asset_id, source_kind, media_plan_id)` and unions `screen_ids` (`app/domain/playlists/generate_for_date.rb:267-273`). ResolvePlayEvent and the v2 package both read screens from that join.

### Deterministic NeutralPicker

`Playlists::NeutralPicker#build_sequence` (`app/domain/playlists/neutral_picker.rb:31-41`):

- `"ordered"` — catalog as stored.
- `"random"` — `catalog.shuffle(random: rng)`, where `rng` is `Random.new` seeded from the first eight bytes of `SHA256("v1|#{station.id}|#{for_date.iso8601}|#{rotation.id}")` (`app/domain/playlists/neutral_picker.rb:37`, `app/domain/playlists/neutral_picker.rb:59-61`). Not `srand`, not `String#hash`.
- else (including `"sequential"`, the generator default when `pick_strategy` is blank — `app/domain/playlists/generate_for_date.rb:226`) — `catalog.rotate(offset % catalog.size)` with `offset = (for_date - Date.new(1970, 1, 1)).to_i` (`app/domain/playlists/neutral_picker.rb:39-40`). Sequential offset is days since the Unix epoch date, not `yday`.

### Recurring dispatch every 15 minutes, purge at 4am

`config/recurring.yml` under the `production:` key (Solid Queue recurring in this app is keyed that way; there is no `development:` block in the file):

- `Playlists::DispatchHorizonJob` — `schedule: every 15 minutes` (`config/recurring.yml:20-23`). The job enqueues `GenerateStationHorizonJob` per station (`app/jobs/playlists/dispatch_horizon_job.rb:7-10`). That job generates **inline** for each horizon date (`app/jobs/playlists/generate_station_horizon_job.rb:15-17`) and, when the API is present, limits concurrency to 1 per station with discard on conflict (`app/jobs/playlists/generate_station_horizon_job.rb:7-8`).
- `Playlists::PurgeExpiredJob` — `schedule: at 4am every day` (`config/recurring.yml:24-27`). It destroys playlists with `for_date < Time.current.to_date - 14.days` in batches of 1000 (`app/jobs/playlists/purge_expired_job.rb:8-12`). Recurring task TZ is the app `config.time_zone`; it is not the station location zone.

Force regen from admin is `Playlists::EnqueueRegen.from_station` (`app/controllers/admin/stations_controller.rb:17-20`), not an inline generate in the request.

### Closed day is an empty current playlist, not a miss

When operating hours for that weekday yield no windows, `GenerateForDate#build_entries` still sets `@anchor` to local midnight of `for_date` and returns `[]` (`app/domain/playlists/generate_for_date.rb:46-48`). Persist still creates a `current` playlist with zero items (`app/domain/playlists/generate_for_date.rb:57-68`). That is distinct from “no current row”: a closed-day current playlist is present, so `PackageFromPlaylists` will not treat that date as missing. A weekday with hours only on Monday, generated for Wednesday, is the AE10 closed-day case in specs.

## Why This Matters

If the playlist becomes a second occupancy writer, FWW and Guard drift from what the agent plays: two sources of “who owns this hour” will disagree after the first cancel or reschedule. If regen hangs off AR callbacks, cancel’s `update_columns` (`app/domain/airtime/cancel.rb:20-28`) silently skips it and tomorrow’s current playlist keeps a dead commercial. If occupy generated inside the ScreenLock transaction (`app/domain/airtime/occupy_with_plan.rb:28-55`), playlist work would lengthen the exclusivity lock and mix two namespaces.

If v2 miss fell back to v1 JSON, a new agent would treat overlapping plans as timed `entries`. If v2 generated inline on GET, a station fleet without current rows would thundering-herd `GenerateForDate` on the request thread. If 304/`stale?` were added to v1, the frozen overlapping-plan contract would change; it belongs on v2 only (`app/controllers/api/agent/v2/packages_controller.rb:9`).

If `StationDateLock` reused ScreenLock’s `874_201`, a station id equal to a screen id could deadlock or serialize unrelated writers. If NeutralPicker used `srand` or `yday`, two workers generating the same station-date would diverge, and year-boundary dates would jump. Location vs organization TZ looks like a bug until you remember orders are commercial documents and playlists are the station’s broadcast day (`app/models/location.rb:10`, `app/domain/playlists/enqueue_regen.rb:73`).

If items lacked `playlist_item_screens`, two groups on one station in the same hour would share a single commercial timeline. AE4 in the generator spec is the regression for that.

The MVP1 name collision (Playlist → Rotation) is a vocabulary trap: a “playlist item” in 2026-08 docs is a rotation clip; a `PlaylistItem` in this tree is a timed projection row with screens.

## When to Apply

Apply this guidance when:

- Adding a new airtime mutation that should refresh tomorrow’s playlist — hook `Playlists::EnqueueRegen` **after** the FWW transaction, and on reschedule enqueue both windows.
- Changing agent package shape, adding `schema_version`, or touching ETag / 304 behavior.
- Designing PlayLog attribution or future certificates for filler vs commercial — go through `ResolvePlayEvent`, not raw playlist rows as occupancy.
- Moving portrait storage, attaching portraits to groups/screens instead of stations, or copying templates on station create/update.
- Choosing a time zone for `for_date`, insertions, operating hours, or regen horizon — use `locations.time_zone`.
- Introducing another advisory lock — pick a new namespace, do not reuse `874_201` or `874_202`.
- Editing filler pick strategy, `neutral_min_seconds`, or any code that calls `Kernel.srand` near playlist generation.

## Examples

**Occupy does not generate inside the transaction.** `OccupyWithPlan` creates booking + plan under ScreenLock, then line 56 enqueues regen. A spec traveling to 2026-09-02 noon and occupying 2026-09-03 10:00-11:00 expects `GenerateForDateJob` with that station and `"2026-09-03"` (`spec/domain/airtime/occupy_with_plan_spec.rb:28-39`). The occupy transaction body (`app/domain/airtime/occupy_with_plan.rb:28-55`) has no `GenerateForDate` or `Playlist.create`.

**Cancel after `update_columns`.** Soft-cancel of a 2026-09-03 window still enqueues `GenerateForDateJob` for `"2026-09-03"` (`spec/domain/airtime/cancel_spec.rb:27-40`) even though status is written with `update_columns` (`app/domain/airtime/cancel.rb:20-23`). Relying on `after_commit` would fail this example.

**Reschedule enqueues new and old.** After moving a plan from 10:00 to 14:00 on the same date, both `from_plan` and `from_group_window(old_…)` run (`app/domain/airtime/reschedule.rb:69-70`). The spec asserts the job for the station-date is enqueued at least once (`spec/domain/airtime/reschedule_spec.rb:25-42`); the old-window call is what keeps the vacated hour from remaining in the projection.

**ReplaceClip.** After the order/rotation item transaction, `Advertising::ReplaceClip` walks `order.rotation.media_plans.active` and `EnqueueRegen.from_plan` for each (`app/domain/advertising/replace_clip.rb:14-27`). Clip replacement is not an occupancy write and does not take ScreenLock; it still must refresh projected commercials. The spec expects `GenerateForDateJob` for the station and `"2026-09-03"` (`spec/domain/advertising/replace_clip_spec.rb:42-58`).

**AE4 two groups.** Two screens of one station in different groups get two occupying plans in the same hour. Generator emits per screen then merges: each commercial item’s `screen_ids` stay inside its group; filler items union both screens (`app/domain/playlists/generate_for_date.rb:267-273`, `spec/domain/playlists/generate_for_date_spec.rb:70-91`).

**Closed day empty playlist.** Operating hours only on Monday; generate Wednesday. `windows.empty?` persists a current playlist with zero items and midnight locational anchor (`app/domain/playlists/generate_for_date.rb:46-48`, `spec/domain/playlists/generate_for_date_spec.rb:153-166`). v2 for that station with empty current rows returns `entries: []` and must **not** include v1’s `items` key (`spec/requests/api/agent/v2/packages_spec.rb:88-99`). That is not a miss: current rows exist, so PackageFromPlaylists does not enqueue those dates.

**v2 miss vs generate.** No current playlist: PackageFromPlaylists returns `entries: []` and does not call `GenerateForDate` (`spec/domain/playlists/package_from_playlists_spec.rb:61-69`). It enqueues only missing horizon dates (`spec/domain/playlists/package_from_playlists_spec.rb:72-78`). Request spec AE10: HTTP 200, empty entries, job enqueued (`spec/requests/api/agent/v2/packages_spec.rb:74-85`). Same token on v1 still returns overlapping plans (`spec/requests/api/agent/v2/packages_spec.rb:67-71`).

**AE11 304.** First GET v2 is 200 with an ETag. Repeat with `If-None-Match` equal to that ETag is 304 (`spec/requests/api/agent/v2/packages_spec.rb:102-120`), which is `stale?` returning false (`app/controllers/api/agent/v2/packages_controller.rb:9-14`). After the current playlist is superseded and a new current row is created, the same If-None-Match yields 200 and a new ETag (`spec/requests/api/agent/v2/packages_spec.rb:123-148`). v1’s controller never calls `stale?`.

**Play event split.** Current playlist in horizon + filler item → operator organization (`spec/domain/playlists/resolve_play_event_spec.rb:40-49`). Active commercial item → plan organization (`spec/domain/playlists/resolve_play_event_spec.rb:52-62`). Cancelled plan on a playlist item → operator (`spec/domain/playlists/resolve_play_event_spec.rb:65-76`). Asset not on that screen’s `playlist_item_screens` → nil, no legacy fallback (`spec/domain/playlists/resolve_play_event_spec.rb:79-86`). No current playlist in the horizon → overlapping MediaPlan match (`spec/domain/playlists/resolve_play_event_spec.rb:89-109`).

**Sequential epoch offset, isolated RNG.** Sequential catalog rotates by `(for_date - Date.new(1970, 1, 1)).to_i` (`spec/domain/playlists/neutral_picker_spec.rb:21-29`). Random strategy is stable across `srand(1)` vs `srand(99)` because the picker uses `Random.new(SHA256…)` (`spec/domain/playlists/neutral_picker_spec.rb:40-47`, `app/domain/playlists/neutral_picker.rb:59-61`).

**Fingerprint skip.** Second generate with unchanged inputs returns the same playlist id and version 1 (`spec/domain/playlists/generate_for_date_spec.rb:169-179`). Changing portrait name supersedes and bumps version (`spec/domain/playlists/generate_for_date_spec.rb:182-195`).

## Related

- Slot pattern: `docs/solutions/architecture-patterns/media-plan-as-airtime-slot.md`
- Plan: `docs/plans/2026-09-02-001-feat-broadcast-portrait-playlist-plan.md`
- MVP1 rename Playlist → Rotation: `docs/plans/2026-08-01-001-feat-broadcast-hub-mvp1-plan.md`
- Brainstorm: `docs/brainstorms/2026-08-27-media-plan-playlist-storage-brainstorm.md`
- Contracts: `specs/002-monitors-broadcast-tz/contracts/agent-api-v1.md` (frozen), `specs/002-monitors-broadcast-tz/contracts/agent-api-v2.md`
- Vocabulary: `CONCEPTS.md` (Broadcast portrait, Playlist, Rotation, Location time zone)
- Occupy / cancel / reschedule: `app/domain/airtime/occupy_with_plan.rb`, `app/domain/airtime/cancel.rb`, `app/domain/airtime/reschedule.rb`
- Locks: `app/domain/playlists/station_date_lock.rb` (`874_202`), `app/domain/airtime/screen_lock.rb` (`874_201`)
- Generator / regen / picker: `app/domain/playlists/generate_for_date.rb`, `app/domain/playlists/enqueue_regen.rb`, `app/domain/playlists/neutral_picker.rb`
- Agent: `app/domain/playlists/package_from_playlists.rb`, `app/domain/agent/package_builder.rb`, `app/controllers/api/agent/v2/packages_controller.rb`
- Play events: `app/domain/playlists/resolve_play_event.rb`
