# Station medium (audio / video) — Hub design

## What this is

The Broadcast Hub gains a first-class **medium** on stations and advertising
orders so commercial placement can target either:

- **video** stations — existing Android TV screens driven by the Go station
  agent (`mediateca-station`); or
- **audio** stations — a mini-PC that plays only audio ads via a Go agent
  and host mpv (`mediateca-audio-station`), with exactly one Hub
  **pseudo-screen** registered on the station.

This document covers Hub schema, cabinet/admin UX, validation, playlist
eligibility, and package behaviour. The audio agent itself is specified in
`2026-10-20-audio-station-agent-design.md`.

## Why this shape

Operators already model every playback target as a `Screen` under a `Station`.
Audio keeps that model: the pseudo-screen is a normal `Screen` so orders, media
plans, portraits, playlists, and agent config/package stay on one path.

Medium lives on the **station** (one agent, one topology) and on the
**advertising order** (one radio choice that filters clips and screens). Mixing
audio and video inside one order is rejected. The agent HTTP contract stays
unchanged so the new audio agent and the existing video agent share
`v1/config`, `v2/package`, and `v1/play_events`.

Rejected alternatives:

- Medium only on `Screen` with a medium-neutral station — hides that the agent
  binary and topology differ per station.
- Deriving order medium from selected screens — breaks draft UX and server
  validation when the picker is empty.
- A separate audio agent API — duplicates the timed-playlist contract.
- Audio transcode / broadcast file in MVP — audio already delivers via the
  original upload; normalize later if field files break.

## Decisions already made

- **Station medium.** `stations.medium` enum `video` | `audio`, NOT NULL,
  default `video`. Set only on create; immutable afterward. Existing rows
  backfill to `video`.
- **Pseudo-screen.** Creating a station with `medium: audio` auto-creates
  exactly one `Screen` (name via existing `next_screen_name`). Further screens
  on that station are forbidden (UI hidden + server reject).
- **Screen has no medium column.** Inheritance is `screen.station.medium`.
- **Order medium.** `advertising_orders.medium` enum `video` | `audio`, NOT
  NULL, default `video`. Editable in draft/rejected; frozen when `active`
  (same idea as product/placement fields).
- **Switch clears.** Changing order medium immediately drops incompatible
  selected clips and screen lines, with a short warning, then refreshes
  available lists.
- **Playlist.** Same `Playlists::GenerateForDate` pipeline for audio stations;
  eligible clips additionally require `content_kind: audio`. Video stations keep
  current eligibility (including MPEG-TS for video).
- **Package.** No API schema change. Audio items use the original file URL and
  its MIME type (existing non-video delivery).
- **No audio transcode** in this work.
- **Agent contract.** Unchanged; see agent design for consumer behaviour.

## Data model

### `stations.medium`

```ruby
# migration sketch
add_column :stations, :medium, :string, null: false, default: "video"
add_check_constraint :stations, "medium IN ('video', 'audio')", name: "stations_medium_video_or_audio"
```

```ruby
# Station
enum :medium, { video: "video", audio: "audio" }, default: :video
validate :medium_immutable_on_update, on: :update
after_create :ensure_audio_pseudo_screen!, if: :audio?

def ensure_audio_pseudo_screen!
  screens.create!(name: next_screen_name) if screens.none?
end
```

Rules:

- Admin create form requires medium (radio or select).
- Admin edit shows medium as read-only badge; strong params omit `:medium` on
  update.
- `screens#create` (and any bulk create) rejects when `station.audio?` and a
  screen already exists, or when creating would exceed one screen.
- Destroying the sole audio screen is either forbidden or immediately
  recreated — prefer **forbid destroy** while the station is audio so the
  pseudo-screen identity stays stable for orders and agent config.

### `advertising_orders.medium`

```ruby
add_column :advertising_orders, :medium, :string, null: false, default: "video"
add_check_constraint :advertising_orders, "medium IN ('video', 'audio')",
  name: "advertising_orders_medium_video_or_audio"
```

```ruby
enum :medium, { video: "video", audio: "audio" }, default: :video
```

Compatibility rules (domain + model):

| Order medium | Allowed clips (`MediaAsset#content_kind`) | Allowed screens |
| --- | --- | --- |
| `video` | Current order-eligible set **excluding** `audio` (typically `video`; keep today's readiness/validation gates) | Screens whose `station.medium == "video"` |
| `audio` | Only `audio`, ready (and content-validated when the order path already requires it) | Screens whose `station.medium == "audio"` |

Server must enforce on save / activate / clip update / line update even if the
UI is bypassed.

### CONCEPTS.md

Add glossary entries:

- **Station medium** — `video` or `audio`; fixed at station create; selects
  agent topology (Android TVs vs local mpv pseudo-screen).
- **Audio pseudo-screen** — the single `Screen` on an audio station; booking
  and playlist target for audio ads; not a physical display.
- **Order medium** — `video` or `audio` on an advertising order; filters
  attachable clips and selectable screens.

## Cabinet and admin UX

### Advertising order form (cabinet Slim / daisyUI; admin ERB / Flowbite)

Placement: **immediately under the form heading**, before product name,
placement kind, and clips editor.

- Radio: «Видео заказ» / «Аудио заказ» (i18n `mediateca.ru.yml` /
  `mediateca.en.yml`).
- Default checked: video.
- Disabled when order is `active`.

On medium change (Stimulus + Turbo Frame preferred, matching existing
order-grid patterns):

1. Clear selected clips whose `content_kind` does not match the new medium.
2. Clear selected screens / order lines for stations of the other medium.
3. Show a short inline/alert warning that incompatible selections were cleared.
4. Reload available clip list and screen picker scoped to the new medium.

Helpers / queries:

- `order_form_available_media_assets` filters by order medium.
- Screen picker collection filters `Screen.joins(:station).where(stations: { medium: order.medium })`.

### Admin stations / screens

- Station new: medium required.
- Station edit: medium read-only.
- Station show: badge for medium; for audio, note “1 pseudo-screen”.
- Screen create button hidden on audio stations; POST rejected with flash.

## Playlist and package

### Eligibility

Extend the shared “eligible clip” checks used by generation / neutral picker /
plan catalog walks:

- If `station.audio?`, require `media_asset.content_kind == "audio"` **and**
  existing delivery attachment rules for non-video (original file present,
  positive duration, min-seconds for neutral when applicable).
- If `station.video?`, keep current rules (video needs broadcast `.ts`, etc.).

Empty catalogs after filtering produce the same soft warnings as today
(`warn_once`); generation does not hard-fail the day.

### Operational prerequisite

Continuous audio airtime needs audio assets in the pseudo-screen’s broadcast
portrait filler/service rotations. That is operator content setup, not a
separate generator mode.

### Occupy / activation

Order activation already writes media plans per line/screen. Audio orders only
reference audio screens (validated). Manual media plans that point a video
rotation at an audio screen simply yield no video clips in generation; optional
admin soft-warn is out of MVP.

### Agent package

- `Playlists::PackageFromPlaylists` / media URL presenter: no new fields.
- Audio: `media.url` = original blob redirect/service URL; `mime_type` from
  blob; `duration_seconds` unchanged.
- Do not add `schema_version` to v1 package. Do not change v2 entry shape.

## Error handling

| Case | Behaviour |
| --- | --- |
| Invalid medium value | DB check + enum validation |
| Update station medium | Validation error; no write |
| Second screen on audio station | Reject create |
| Order clips/screens wrong medium | Domain/model errors on form re-render |
| Switch medium with selections | Clear + warn (not a hard block) |
| Active order medium change | Field disabled; server ignores/rejects change |
| No audio clips in portrait | Playlist warns; gaps/filler absence as today |

## Testing (Hub)

- Migration: default `video` for existing stations and orders.
- Station create `audio` → one screen; second create fails; medium immutable.
- Order form / request: available assets and screens filtered; switch clears.
- `Advertising::UpdateOrderClips` rejects wrong `content_kind` for medium.
- Playlist generation for audio station includes only audio assets; video
  station unchanged.
- Agent package for audio entry serves original audio MIME/URL.
- i18n keys present for ru/en.

## Out of scope (Hub)

- Changing medium on an existing station (create a new station instead).
- Multiple pseudo-screens / multi-channel audio on one station.
- Audio broadcast transcode pipeline.
- New agent API routes or `medium` in config JSON.
- Auto-provisioning audio filler libraries / service themes.
- Merging Go and Ruby agents.

## Implementation notes

- Prefer extending existing domain objects (`Advertising::UpdateOrderClips`,
  playlist eligibility helpers, admin station/screen controllers) over new
  parallel services.
- Regen after occupy/cancel/reschedule/clip replace stays as today
  (`Playlists::EnqueueRegen` outside FWW transactions).
- Ransack allowlists: add `medium` where stations/orders are searchable in
  admin if filters are desired in the same PR; otherwise index badge only.

## Approval

Design sections approved in brainstorming (2026-10-20): data model, order UI,
playlist/package, errors/testing. Approach: medium enums + separate audio
agent repo; shared agent HTTP contract.
