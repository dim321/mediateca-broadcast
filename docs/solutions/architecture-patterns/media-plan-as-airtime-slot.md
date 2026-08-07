---
title: MediaPlan as Airtime Slot with Internal AirtimeBooking
date: 2026-08-07
category: architecture-patterns
module: airtime
problem_type: architecture_pattern
component: service_object
severity: medium
applies_when:
  - Designing or changing airtime slot occupancy on shared screens
  - Tempted to delete AirtimeBooking or reintroduce AirtimeQuota
  - Changing MediaPlanConflictDetector or ScreenOverlapGuard scope
  - Soft-cancelling or rescheduling media plans on shared screens
  - Adding or auditing occupancy UI for calendar exclusivity
tags:
  - airtime
  - media-plan
  - airtime-booking
  - first-write-wins
  - cross-org
  - screen-overlap-guard
  - soft-cancel
  - architecture
related_components:
  - MediaPlan
  - AirtimeBooking
  - OccupyWithPlan
  - Reschedule
  - Cancel
  - ScreenLock
  - ScreenOverlapGuard
  - MediaPlanConflictDetector
  - OccupancyPresenter
---

# MediaPlan as Airtime Slot with Internal AirtimeBooking

## Context

Broadcast Hub multi-org airtime treats a MediaPlan as the user-facing calendar slot. Shared screens need exclusive windows without selling “seconds capacity.” The shipped model is:

1. **`Airtime::OccupyWithPlan`** — one transaction: `ScreenLock` → `ScreenOverlapGuard` → confirmed `AirtimeBooking` (`seconds` = window duration, no quota) → active `MediaPlan` linked 1:1 (`app/domain/airtime/occupy_with_plan.rb`).
2. **`Airtime::Reschedule`** — lock old∪new screens, Guard with `exclude_booking`, update booking + plan together; plan uses `save!(validate: false)` for window/group moves (`app/domain/airtime/reschedule.rb`).
3. **`Airtime::Cancel`** — soft-cancel plan and booking via `update_columns` so cancel still frees the slot even when readiness validations would fail (`app/domain/airtime/cancel.rb`).

There is **no** `AirtimeQuota` in schema or runtime, and **no** `Airtime::Book`. LK has no booking CRUD; admin cancel/reschedule only (no form edit/destroy of the slot). Controllers resolve org-local windows through `Scheduling::TimeWindowResolver`. Occupancy UI is `Airtime::OccupancyPresenter`. Historical plan authority: `docs/plans/2026-08-06-001-feat-media-plan-as-airtime-slot-plan.md`.

Cross-org exclusivity lives on confirmed bookings via `Airtime::ScreenOverlapGuard` (`.confirmed`, no org filter, half-open overlap) (`app/domain/airtime/screen_overlap_guard.rb`). Same-org plan overlap is separate: `Scheduling::MediaPlanConflictDetector` optionally scopes by `organization_id` (`app/domain/scheduling/media_plan_conflict_detector.rb`). Transaction-scoped FWW uses `Airtime::ScreenLock` (`pg_advisory_xact_lock` under namespace `874_201`, via `sanitize_sql_array`) (`app/domain/airtime/screen_lock.rb`).

## Guidance

Keep these decisions when touching airtime occupancy:

1. **Drop capacity quotas, keep calendar exclusivity.** Free time is unused calendar intervals on shared screens, not a residual seconds budget. Reintroducing `AirtimeQuota` (model, admin, FK, remaining-seconds races) is an anti-pattern.

2. **Keep internal `AirtimeBooking` for cross-org FWW.** Do not delete booking as the occupancy authority. Confirmed bookings are created/updated only inside occupy/reschedule domain services — no LK booking create/index/nav. Booking window must match plan window (same org/group).

3. **Create = one transaction: ScreenLock → Guard → booking → plan.** Reject with conflict/validation and roll back; no partial writes. Guard remains authoritative for cross-org exclusivity; do not rely on org-scoped `MediaPlanConflictDetector` alone for FWW.

4. **Reschedule in place; soft-cancel both sides.** Lock old∪new screens; Guard with exclude-self; update booking + plan together or ROLLBACK. Soft-cancel sets plan and booking to `cancelled` atomically via `update_columns` (skip readiness validations). Prefer cancel over hard destroy. Admin and LK release paths must go through `Airtime::Cancel` / `Airtime::Reschedule`, not raw form destroy/edit of the slot.

5. **Preserve detector vs Guard split.** Keep `MediaPlanConflictDetector` org-scoped for same-org plan overlap. Keep Guard all-orgs for shared-screen FWW. Do not widen the detector to all orgs while Guard exists — Guard wins for FWW.

## Why This Matters

Quota capacity added an operator step and overflow races with no commercial value when the product is “any free calendar interval on shared screens.” Removing quotas simplifies LK/admin IA, but **deleting `AirtimeBooking` would remove the only all-org overlap check**. Org-filtered media-plan detection cannot alone enforce cross-org exclusivity. An invisible confirmed booking under `ScreenLock` preserves FWW while MediaPlan is the user-facing slot. Soft-cancel via `update_columns` avoids validation traps that would otherwise leave a dead plan occupying the calendar.

## When to Apply

Apply this guidance when:

- Changing create/reschedule/cancel of airtime or media plans on shared multi-org screens.
- Tempted to delete `AirtimeBooking` or reintroduce `AirtimeQuota`.
- Touching package/fleet gates that assume confirmed covering booking + active plan.
- Auditing concurrency: occupy/reschedule must take `ScreenLock` before Guard, not the detector alone.
- Reviewing admin/LK media-plan release paths — they must call `Airtime::Cancel` / `Airtime::Reschedule`.

This is the **current shipped architecture**, not a pending plan.

## Examples

**Occupy (FWW):** Two managers from different orgs submit overlapping MediaPlans on a shared screen → one transaction holds `ScreenLock` first, Guard sees empty, inserts booking+plan; the other locks, Guard sees confirmed overlap, raises `Airtime::ConflictError`, no partial plan (`occupy_with_plan.rb`).

**Guard (all-orgs):** Overlap query scopes `.confirmed`, joins memberships by `screen_id`, uses half-open `starts_at < ends_at AND ends_at > starts_at`, no org filter (`screen_overlap_guard.rb`). Cancelled bookings stay out of `.confirmed`.

**Detector (same-org):** Filters active plans overlapping screen×window; when `organization_id` is present, adds `.where(organization_id: …)` (`media_plan_conflict_detector.rb`). Suitable for same-org UX; insufficient alone for cross-org FWW.

**Reschedule:** Lock old∪new screens; Guard with `exclude_booking`; update booking then plan with `save!(validate: false)` so window/group moves are not blocked by rotation readiness (`reschedule.rb`).

**Soft-cancel:** Operator/manager cancels → plan and booking both `cancelled` via `update_columns` in one transaction → interval free for another org’s occupy (`cancel.rb`). Prefer this path over hard destroy.

**ScreenLock:** Sorted unique screen ids; `pg_advisory_xact_lock(NAMESPACE, screen_id)` with `NAMESPACE = 874_201` and `sanitize_sql_array` (`screen_lock.rb`).

## Related

- Plan authority (historical): `docs/plans/2026-08-06-001-feat-media-plan-as-airtime-slot-plan.md`
- Occupy / reschedule / cancel: `app/domain/airtime/occupy_with_plan.rb`, `app/domain/airtime/reschedule.rb`, `app/domain/airtime/cancel.rb`
- Lock / Guard: `app/domain/airtime/screen_lock.rb`, `app/domain/airtime/screen_overlap_guard.rb`
- Same-org overlap helper: `app/domain/scheduling/media_plan_conflict_detector.rb`
- Occupancy UI: `app/domain/airtime/occupancy_presenter.rb`
- Org TZ windows: `app/domain/scheduling/time_window_resolver.rb`
- Controllers: `app/controllers/media_plans_controller.rb`, `app/controllers/admin/media_plans_controller.rb`
