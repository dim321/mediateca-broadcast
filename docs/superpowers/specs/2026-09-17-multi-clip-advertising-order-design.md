# Multi-clip advertising order — design

## What We're Building

An advertising order may bind several client clips in a fixed sequence. Hourly
commercial slots take the next clip from that sequence and wrap around: with
clips ABC and `shows_per_hour = 3`, one hour emits A, B, C; with
`shows_per_hour = 6`, ABCABC; with `shows_per_hour = 2`, AB in the first hour and
C continuing in the next hour of the same broadcast day.

Creation and clip-list editing work the same in operator admin and client
cabinet (shared order form).

## Why This Approach

Chosen approach: extend the order’s existing system-managed `Rotation` to hold
N ordered `RotationItem`s. Occupy and playlist keep using `order.rotation` and
`NeutralPicker` sequential; the day-scoped picker cursor already carries the
cycle across hours.

Rejected: a parallel `advertising_order_clips` table with dual-write into the
rotation; splitting one order into multiple media plans / frequencies per clip.

## Key Decisions

- **Frequency vs catalog size:** independent. Catalog cycles for any M and N.
- **One show duration:** duration of the clip actually placed in that slot.
  Commercial soft quota must sum the durations of `shows_per_hour` sequential
  picks — not `shows_per_hour * sum(all rotation items)`.
- **Source of truth for clips:** `order.rotation.ordered_items`. Stop writing
  `media_asset_id` / lone clip snapshots on create and update; make
  `media_asset_id` nullable (column drop can be a follow-up). Show/UI and any
  remaining readers derive clip list from the rotation.
- **Edit after create:** full ordered list sync (add / remove / reorder). Draft:
  no playlist regen. Active: `Playlists::EnqueueRegen` outside the write
  transaction; no re-occupy.
- **Surfaces:** admin and cabinet share the multi-clip form.
- **Duplicates:** the same `media_asset` may appear at most once in an order.
- **Minimum:** at least one eligible ready asset belonging to the order’s
  organization.

## Domain

### Create

`Advertising::CreateOrder` accepts an ordered list of media assets, creates the
system rotation, and inserts one `RotationItem` per asset (position = list
order, `display_duration_seconds` from each asset).

### Update clips

`Advertising::UpdateOrderClips` (replaces singleton assumptions in
`ReplaceClip` / `ReplaceDraftClip` / `.sole`):

1. Validate assets (org + `ready`, unique, non-empty).
2. In one transaction, sync `rotation_items` to the new ordered list.
3. If the order is active, after commit call `Playlists::EnqueueRegen` for
   affected stations/dates (same pattern as today’s active clip replace).

`Airtime::OccupyWithPlan` / `Advertising::ActivateOrder` stay rotation +
`shows_per_hour`; no new occupancy writers.

### Playlist

No new pick strategy. Commercial blocks keep
`NeutralPicker(rotation, "sequential")` with a picker memoized per
`(screen, rotation, …)` for the generated day so the cursor continues across
hours.

### Commercial quota

For soft commercial quota at frequency M, expected hourly seconds =
sum of durations of M sequential picks from the rotation catalog (picker /
catalog order starting at index 0 for the check). Do **not** use
`M * sum(all items)`.

Implementation: change the commercial consumption path (today
`n * CycleDuration`) accordingly — e.g. a dedicated
`CommercialQuota::HourlyShowsDuration` (or equivalent) that simulates M picks.
Leave soft quota flash-only; do not roll back occupy.

## UI

### Form (`advertising_orders/_form`)

Replace the single media select with an ordered multi-clip editor:

- Add from organization’s ready assets.
- Reorder (up/down or drag) and remove rows; enforce ≥1 row.
- Keep `shows_per_hour` as its own field; short hint that clips rotate through
  hourly slots.
- Optional compact preview of the first hour’s slot sequence given current
  frequency and list order.

Strong params: ordered `media_asset_ids: []` (not a single `media_asset_id`).

### Show

Display the ordered clip list (title + duration per item) instead of a single
clip. “Change clips” opens the same list editor for draft and active (subject
to domain rules above).

### Stimulus

Extend or replace `order-media-asset` with a list controller (add / remove /
reorder) posting ordered ids.

Admin index/show chrome stays Flowbite; the shared form keeps daisyUI.

## Relation to prior design

`docs/superpowers/specs/2026-09-16-admin-advertising-order-media-replacement-design.md`
described admin draft-only single-clip replace. This design supersedes that for
clip binding: both surfaces edit the full ordered list; active orders may change
clips with playlist regen only (aligning cabinet’s existing active replace
intent with multi-clip).

## Out of scope

- Separate document table mirrored into the rotation.
- Per-clip media plans or splitting `shows_per_hour` across orders.
- Certificate / reporting redesign beyond play events already keyed by
  `media_asset_id`.
- Requiring equal clip durations.

## Testing

- `CreateOrder`: N items, stable order.
- `UpdateOrderClips`: draft (no regen) vs active (regen enqueued).
- Playlist / picker: 3 clips × 3/hour → ABC; 3 × 2/hour → AB then C next hour.
- Commercial quota: hourly seconds = sum of M pick durations, not
  `M * sum(catalog)`.
- Request: form accepts ordered `media_asset_ids`; show lists clips; rejects
  empty, foreign, non-ready, and duplicate ids.

## Open Questions

None blocking. First UI iteration: up/down buttons for reorder; drag-and-drop
optional later.
