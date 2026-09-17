# Design: optional time_of_day for service_welcome / service_close

**Date:** 2026-09-17  
**Status:** approved for planning  
**Approach:** A — extend insertion slot-replacement path; untimed keep day-bound open/close

## Problem

`service_welcome` and `service_close` portrait blocks always emit at the start of the first operating window and the end of the last. Operators want an optional wall-clock time (same idea as `insertion`): when set, the block replaces that hour slot’s cyclic beat; when blank, keep today’s open/close defaults.

## Goals

- Optional `time_of_day` on `service_welcome` / `service_close`.
- Blank → day-bound at open / close (current behavior).
- Set → same slot matching as `insertion` (replace cyclic beat in the covering slot).
- Playlist `source_kind` stays `"service"` for both paths (not `"insertion"`).
- Multiple blocks of the same kind allowed; timed and untimed may coexist on one portrait.
- Outside operating windows / spring-forward gaps → skip (same as insertion).

## Non-goals

- Schema migration (`time_of_day` already exists on `broadcast_portrait_blocks`).
- New block kinds or renaming `insertion`.
- Auto-filling `time_of_day` from operating hours at save time.
- Cap of one welcome / one close per portrait.
- Changing commercial / filler / header / insertion validation rules.
- Resolving “winner” when several timed blocks share a slot beyond stable `position` order.

## Why This Approach

| Option | Verdict |
|--------|---------|
| A — route timed welcome/close through insertion-style slot replace | Chosen: one timed-slot mental model, no migration, small generator change |
| B — extract shared `timed_slot_replacements` abstraction | Deferred: cleaner later, unnecessary for one optional field |
| C — always persist `time_of_day`, synthesize from hours | Rejected: couples portrait to screen hours; blank-default UX lost |

Product decisions locked before implementation:

- Slot replace (option 1), not overlay and not “move day-bound anchor only”.
- Multiple welcome/close OK; mix of timed + untimed OK.

## Behavior

### Untimed (blank `time_of_day`)

Unchanged: `day_bound_emissions` picks welcome at `windows.first[:start]`, close at `windows.last[:end]`. Only blocks **without** `time_of_day` participate.

### Timed (present `time_of_day`)

Same selection as `insertion_events`: resolve wall-clock in location TZ; if the instant falls in a built slot `[slot_start, slot_end)`, that slot’s cyclic beat is replaced by emitting the service clip(s). Use existing DST / missing local time handling from insertion (skip when `local_wall_clock` yields nil / outside windows).

Emit via service path (`source_kind: "service"`), reusing clip pick rules already used for welcome/close (`take_from_block`, rotation / pick_strategy / theme).

### Same-slot collisions

If several timed blocks match one slot (e.g. insertion + timed welcome), emit all matching blocks in ascending `position`. No priority override.

### Cycle membership

`cycle_blocks` continues to exclude **all** welcome/close (timed and untimed). Timed ones never appear as cyclic beat fillers.

## Model validation

In `BroadcastPortraitBlock#fields_match_kind` for `service_welcome` / `service_close`:

- Remove the error that rejects `time_of_day` when present.
- Keep existing requirements: rotation (via theme or direct), `pick_strategy` required; no other field changes.

No DB check-constraint change required unless one currently forbids time on those kinds (there is none today).

## Generator (`Playlists::GenerateForDate`)

1. Split welcome/close into untimed vs timed by `time_of_day.present?`.
2. Untimed → existing `day_bound_emissions` (filter to untimed only).
3. Timed → include in the same per-slot matching loop as insertions (extract a small helper or extend `insertion_events` to “timed slot replacements” that carries `source_kind` / emit method). Prefer minimal diff: e.g. `timed_slot_events` returning `{ block:, at: }` for `insertion?` **or** (`service_welcome?`/`service_close?` and time present); emit branch chooses `"insertion"` vs `"service"`.
4. Fingerprint already hashes `time_of_day` — changing time invalidates the day fingerprint and triggers regen as today.

## Admin / copy

- Portrait block form: optional time field for welcome/close; empty means default open/close.
- Short hint (i18n): blank → start/end of operating day; set → replaces the slot at that time.
- `Portraits::CopyTemplate` and `Portraits::UpsertBlocks` already pass `time_of_day` — no special-case needed.
- Strong params already permit `time_of_day`.

## Tests

1. Model: welcome/close valid with and without `time_of_day`.
2. Generate: untimed welcome @ open, close @ last window end.
3. Generate: timed welcome at noon replaces that slot; item `source_kind` is `service`.
4. Generate: one untimed + one timed welcome on the same portrait both emit.
5. Generate: spring-forward timed welcome skipped (mirror insertion AE8).
6. Optional request coverage: admin update with blank `time_of_day` for welcome succeeds.

## Related

- `docs/solutions/architecture-patterns/broadcast-portrait-as-screen-airtime-structure.md`
- `docs/solutions/architecture-patterns/playlist-as-airtime-projection.md`
- Models: `BroadcastPortraitBlock`; domain: `Playlists::GenerateForDate`
