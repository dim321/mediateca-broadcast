---
title: MediaPlan as Airtime Slot with Internal AirtimeBooking
date: 2026-08-06
category: architecture-patterns
module: airtime
problem_type: architecture_pattern
component: service_object
severity: medium
applies_when:
  - Designing or implementing airtime slot occupancy on shared screens
  - Tempted to delete AirtimeBooking after removing client booking UX
  - Replacing quota-then-book-then-plan with MediaPlan-as-slot
  - Changing MediaPlanConflictDetector or ScreenOverlapGuard scope
  - Adding soft-cancel or occupancy UI for media plans
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
  - MediaPlanConflictDetector
  - ScreenOverlapGuard
  - AirtimeQuota
---

# MediaPlan as Airtime Slot with Internal AirtimeBooking

## Context

In Broadcast Hub multi-org airtime, shared screens need exclusive calendar windows without selling “seconds capacity.” Today’s tree still implements the older quota → booking → media plan path: `Airtime::Book` locks screens, decrements `AirtimeQuota.seconds_remaining`, then inserts a confirmed `AirtimeBooking` (`app/domain/airtime/book.rb` (lines 16-37)). Cross-org exclusivity lives on confirmed bookings via `Airtime::ScreenOverlapGuard`, which joins group memberships and applies a half-open overlap predicate with **no** organization filter (`app/domain/airtime/screen_overlap_guard.rb` (lines 24-31)). Same-org media-plan overlap is separate: `Scheduling::MediaPlanConflictDetector` optionally scopes by `organization_id` when present (`app/domain/scheduling/media_plan_conflict_detector.rb` (lines 24-32)). Transaction-scoped FWW uses `Airtime::ScreenLock` (`pg_advisory_xact_lock` under namespace `874_201`) (`app/domain/airtime/screen_lock.rb` (lines 7-18)).

The planned product contract (`docs/plans/2026-08-06-001-feat-media-plan-as-airtime-slot-plan.md`) replaces capacity quotas with calendar occupancy: creating a MediaPlan occupies the slot; operator quota UX goes away; `AirtimeBooking` stays as an internal 1:1 record for cross-org FWW. **This model is planned (pending implementation), not merged** — treat current `Book` quota decrement as as-is tree behavior to be removed per that plan’s KTDs.

## Guidance

When implementing MediaPlan-as-airtime-slot (or reviewing related PRs), keep these decisions aligned with the plan and the existing lock/guard primitives:

1. **Drop capacity, not calendar exclusivity.** Remove `AirtimeQuota` (model, admin, factories, FK, `seconds_total` / `seconds_remaining`, overflow paths). Do not reintroduce operator “how many seconds to give clients.” Free time is unused calendar intervals on shared screens, not a residual budget.

2. **Keep internal `AirtimeBooking` for cross-org FWW.** Do not delete booking as the occupancy authority in this slice. Create/update confirmed bookings only inside MediaPlan create/reschedule domain services — no LK booking create/index/nav. Booking window must match plan window (same org/group). Package/fleet consumers can keep joining on confirmed covering booking + active plan while booking exists.

3. **Create = one transaction patterned on `Book` minus quota.** Reuse: `ScreenLock` → `ScreenOverlapGuard` (confirmed, all orgs) → insert confirmed booking (seconds = duration, no quota) → insert active MediaPlan linked 1:1. Reject with conflict/validation and roll back; no partial writes. Guard remains authoritative for cross-org exclusivity; do not rely on org-scoped `MediaPlanConflictDetector` alone for FWW.

4. **Reschedule in place; soft-cancel both sides.** Lock old∪new screens; Guard with exclude-self; update booking + plan together or ROLLBACK. Soft-cancel sets plan and booking to `cancelled` atomically; cancelled/invalidated rows must be excluded from Guard, occupancy UI, and package/fleet gates. Prefer cancel action over hard destroy as the primary release path.

5. **Preserve detector vs Guard split.** Keep `MediaPlanConflictDetector` org-scoped for same-org plan overlap (`media_plan_conflict_detector.rb:30`). Keep Guard all-orgs for shared-screen FWW (`screen_overlap_guard.rb` (lines 24-29)). Do not widen the detector to all orgs while Guard exists — double enforcement is acceptable if both agree; Guard wins for FWW.

Until the slot-model units land, any code path that still calls `Airtime::Book` will continue to decrement quota (`book.rb` (lines 20-27)) — that is current tree behavior, not the target product model.

## Why This Matters

Quota capacity adds an operator step and overflow semantics with no commercial value when the product is “any free calendar interval on shared screens.” Dropping quotas simplifies LK/admin IA and removes remaining-seconds races, but **deleting booking entirely would remove the only all-org overlap check present in the tree today**. Org-filtered media-plan detection (`organization_id` optional filter at `media_plan_conflict_detector.rb:30`) cannot alone enforce cross-org exclusivity. Keeping an invisible confirmed booking under ScreenLock preserves the existing FWW canon (`screen_lock.rb` + `screen_overlap_guard.rb`) while MediaPlan becomes the user-facing slot.

## When to Apply

Apply this guidance when:

- Implementing or reviewing the MediaPlan-as-airtime-slot plan (and related units).
- Changing create/reschedule/cancel of airtime or media plans on shared multi-org screens.
- Touching `Airtime::Book`, quota admin, LK bookings nav, or package/fleet gates that assume quota → booking → plan.
- Deciding whether to delete `AirtimeBooking` — defer full deletion; keep internal booking for this slice.
- Auditing concurrency: any occupy/reschedule path must take `ScreenLock` before Guard, not MediaPlanConflictDetector alone.

Do not apply as “already shipped”: phrase new work as pending plan execution against current quota-aware `Book`.

## Examples

**Current tree — quota decrement on book (to be removed):** After advisory locks, `Book` loads the quota with `lock`, raises if `seconds_remaining` is insufficient, runs Guard, then decrements remaining and creates a confirmed booking (`book.rb` (lines 16-37)). Planned occupy services should mirror lock → Guard → insert booking → insert plan **without** the quota branch (`book.rb` (lines 20-21), `book.rb:27`).

**Current tree — all-org Guard:** Overlap query scopes `.confirmed`, joins memberships by `screen_id`, and uses `starts_at < ends_at AND ends_at > starts_at` with no org filter (`screen_overlap_guard.rb` (lines 24-29)). Cancelled bookings must stay out of `.confirmed` (or equivalent) after soft-cancel lands.

**Current tree — org-scoped plan conflicts:** Detector filters active plans overlapping screen×window and, when `organization_id` is present, adds `.where(organization_id: …)` (`media_plan_conflict_detector.rb` (lines 24-32)). Suitable for same-org plan overlap; insufficient alone for cross-org first-write-wins.

**Planned create (FWW):** Two managers from different orgs submit overlapping MediaPlans on a shared screen → one transaction holds `ScreenLock` first, Guard sees empty, inserts booking+plan; the other locks, Guard sees confirmed overlap, raises conflict, no partial plan. **Behavior is specified in the plan; occupy service not yet in tree as of this writing.**

**Planned soft-cancel:** Operator/manager cancels an active plan → plan and booking both `cancelled` in one transaction → interval free for another org’s occupy. Invert any legacy “cancel booking blocked by active plan” gate once cancel entry point is the plan.

## Related

- Plan authority: `docs/plans/2026-08-06-001-feat-media-plan-as-airtime-slot-plan.md`
- Prior MVP-2 airtime cycle (superseded for slot model only): `docs/plans/2026-08-05-002-feat-broadcast-hub-mvp2-airtime-plan.md`
- Lock/Guard/Book as-is: `app/domain/airtime/screen_lock.rb`, `screen_overlap_guard.rb`, `book.rb`
- Same-org overlap helper: `app/domain/scheduling/media_plan_conflict_detector.rb`
