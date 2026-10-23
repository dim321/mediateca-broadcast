---
title: Operator service themes on screen portraits
date: 2026-09-04
last_updated: 2026-10-20
category: architecture-patterns
module: service-themes
problem_type: architecture_pattern
component: service_object
severity: medium
applies_when:
  - Adding or changing operator service clips, ServiceTheme, or theme folders
  - Binding a theme or pick strategy on a screen portrait
  - Generating welcome/close clips or service headers
  - Changing screen vs location operating hours or regen hooks
  - Tempted to list system_managed theme rotations in ordinary Rotation CRUD
  - Tempted to put a portrait or hours on the station instead of the screen
tags:
  - service-theme
  - broadcast-portrait
  - playlist
  - operating-hours
  - admin
  - architecture
related_components:
  - ServiceTheme
  - BroadcastPortrait
  - Screen
  - Playlists::GenerateForDate
  - Playlists::NeutralPicker
  - Playlists::EnqueueRegen
  - Portraits::ApplyServiceTheme
  - ServiceThemes::Create
  - ServiceThemes::AddClip
---

# Operator service themes on screen portraits

## Context

The operator needs themed service clips (ad-block headers, welcome, close) that differ per screen in one location: a salon screen and a fish-counter screen on the same station can have different folders and different opening hours. Clients must not upload `content_type: service`. The daily playlist stays one document per station (one agent token).

The 2026-09-03 brainstorm chose `ServiceTheme` with four `system_managed` rotations over tagging rotations or treating a portrait preset as the theme. The 2026-09-04 revision moved broadcast portrait and operating hours from the station onto the screen so those two screens can diverge. Occupancy writers (`Airtime::*`, FWW, Guard) and `GET /api/agent/v1/package` stay untouched.

Shipped split:

1. **ServiceTheme** — operator-org row with five `system_managed` folders (`ServiceTheme::FOLDER_ROLES`: four service roles plus `:neutral`). `ServiceThemes::Create` creates all five; clips use `content_type: service` on the four service folders and `content_type: neutral` on `neutral_rotation` (admin label «Нейтральный контент»). Destroy is restrict while a portrait still references the theme.
2. **Admin library** — `/admin` service-library CRUD and nested clip upload (`ServiceThemes::AddClip` → `MediaAsset` with `content_type: service` on service folders and `neutral` on `neutral_rotation`, plus `RotationItem`). Cabinet upload rejects `service`. Theme rotations are hidden from ordinary `Admin::RotationsController#index` (`Rotation.unmanaged`); clip edits go through the theme, not Rotation CRUD.
3. **Screen portrait + hours** — instance portraits have `screen_id`; templates have `screen_id` nil. Hours: `inherit_operating_hours_from_location` (default true) plus optional `screens.operating_hours`. `Screen#effective_operating_hours` feeds generation. `Portraits::ApplyServiceTheme` upserts the four service blocks (each with `service_theme_id` and the matching rotation) and overwrites the portrait `filler` block (rotation, pick strategy, `service_theme_id`) from `neutral_rotation`, including filler that had no theme; commercial blocks are unchanged. Clearing the theme removes service blocks and theme-owned filler only; non-theme-owned filler is left alone. Manual block edit clears portrait-level `service_theme_id`. Portrait form service kinds pick a theme folder, not a raw rotation. A filler block can pick a service theme too: `Portraits::UpsertBlocks` keeps `service_theme_id` and the block rotation becomes `neutral_rotation`. A filler without a theme still points at an assignable rotation.
4. **Generator** — per screen, then merge via `playlist_item_screens`. Welcome at the first effective window open, close at the last window end, outside the hourly cycle. Closed weekday: no welcome/close, still a current playlist. Headers use `NeutralPicker` with the block `pick_strategy` and `min_seconds: nil`. After scheduled clips are placed, each unoccupied stretch of the screen's operating window is measured and packed by `NeutralGapFill`: the longest eligible filler clip that fits, then the next longest that fits the remainder, repeating the catalog until nothing else fits. The filler rotation is the theme `neutral_rotation` when the filler block has `service_theme_id`.
5. **Regen** — clip/rotation item → `EnqueueRegen.from_rotation`; portrait/theme/hours on the screen → `from_screen`; location hours → `from_location_hours` (inheriting screens only). Horizon stays location TZ.

## Guidance

Do not attach a portrait or a time zone to the station. Do not generate a playlist per screen. Do not let clients upload service assets. Do not list theme folders next to client rotations. Do not pick welcome/close from `time_of_day` or from the cyclic hour — those kinds are day-bound to effective hours. Do not change v1 package JSON.

Empty service folders warn (`warn_once`) and skip that emission; generate still succeeds. Fingerprint includes per-screen portrait blocks and `effective_operating_hours`.

## When to Apply

- Adding another service block kind — extend `ServiceTheme::ROTATION_ROLES` and `ApplyServiceTheme`, not a one-off rotation flag on the portrait. The fifth theme folder is already `:neutral` in `FOLDER_ROLES` / `neutral_rotation`; it is not a new `service_*` block kind — apply maps it to portrait `filler`, not a sixth service kind.
- Changing hours — inherit vs custom on the screen; location hours only regen inheriting screens.
- Changing header pick — go through `NeutralPicker` / block `pick_strategy`, not “first eligible item”.
- Admin rotation lists — start from `Rotation.unmanaged` / `Rotation.assignable`. Portrait service blocks and theme-owned filler use the `ServiceTheme` picker; filler without a theme and insertion still use assignable rotations.

## Related

- Playlist projection: `docs/solutions/architecture-patterns/playlist-as-airtime-projection.md`
- Plan: `docs/plans/2026-09-03-001-feat-operator-service-media-library-plan.md`
- Brainstorm: `docs/brainstorms/2026-09-03-operator-service-media-brainstorm.md`
- Vocabulary: `CONCEPTS.md` (Broadcast portrait, Service theme, Screen operating hours, Playlist)
- Domain: `app/domain/service_themes/`, `app/domain/portraits/apply_service_theme.rb`, `app/domain/playlists/generate_for_date.rb`
