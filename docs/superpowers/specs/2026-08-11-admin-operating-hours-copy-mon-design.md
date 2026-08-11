# Design: Copy Monday to all days (Administrate operating hours)

**Date:** 2026-08-11  
**Status:** approved for implementation planning  
**Scope:** Administrate location form only — `OperatingHoursField` new/edit

## Problem

When setting weekly operating hours for a location in `/admin/locations`, operators usually reuse the same window for every day. Filling seven rows by hand is tedious and error-prone.

## Goals

- Add a **«Скопировать пн на все дни» / «Copy Mon to all days»** control on the Administrate operating-hours form.
- On click, copy Monday `start`/`end` into Tue–Sun inputs immediately in the browser.
- If Monday is blank, clear the other days as well (overwrite always; no confirm dialog).

## Non-goals

- No changes to ЛК `/locations` edit form.
- No server-side “copy Monday” flag or model API.
- No multi-window-per-day UI (still one window per day).
- No Stimulus wiring into Administrate layout.

## Approach

Vanilla JS in the Administrate field form partial. Button `type="button"` so it does not submit the form. Values are written into existing `input[type=time]` fields; persistence remains the normal create/update path and `Location::OperatingHours.normalize`.

## UI

Location: under the days table in `app/views/fields/operating_hours_field/_form.html.erb`.

| Element | Detail |
|---------|--------|
| Button | `type="button"`, visible label via i18n |
| RU | `Скопировать пн на все дни` |
| EN | `Copy Mon to all days` |

Hint text above the table stays as-is.

## Behavior

1. Read Monday start/end from `location[operating_hours][mon][][start|end]` (or current `f.object_name`).
2. Write those strings into each of `tue`…`sun` corresponding inputs.
3. Empty Monday → empty strings on other days.
4. No network request; no toast required.

## Implementation notes

- Prefer a small inline script in the form partial (Administrate already yields `content_for :javascript`; either is fine if the listener attaches after the button exists).
- Scope selectors to the field wrapper so multiple instances would not clash (defensive; one field per form today).
- Keep `OperatingHoursField.permitted_attribute` and model normalize/validate unchanged.

## Testing

- Extend `spec/requests/admin/locations_spec.rb` (or equivalent): new form body includes the button label / i18n key string.
- Optional: system/Cuprite click copies values — not required for MVP if request assertion covers presence; add only if cheap given existing Cuprite setup.

## Success criteria

- Operator on admin location new/edit can fill Monday once, click the button, see Tue–Sun match, then save successfully with those hours persisted.
