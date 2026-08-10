# Concepts

Shared domain vocabulary for this project — entities, named processes, and status concepts with project-specific meaning. Seeded with core domain vocabulary, then accretes as ce-compound and ce-compound-refresh process learnings; direct edits are fine. Glossary only, not a spec or catch-all.

## Airtime

### Airtime slot
A calendar window on the screens of a broadcast point group that one client organization may occupy for playback. In the MediaPlan-as-slot model the user-facing slot is created with a media plan; capacity budgets in seconds are not part of the product.

### Airtime quota
*(Legacy / anti-pattern.)* An operator-defined seconds budget for a group and time window used as a prerequisite for booking. Do not reintroduce as capacity for calendar placement; free time remains unused calendar intervals (MediaPlan-as-slot).

### Commercial quota
A lasting percent cap on commercial placement airtime for an owner-homogeneous broadcast point group. Set as percent plus period unit (hour or day); applies indefinitely until changed. Soft-checked after successful media-plan create/reschedule — flash warning, do not block or roll back. Distinct from legacy airtime quota seconds budgets.

### Screen owner
Optional client organization that owns a Screen. Ownership is per screen. Quotas attach only to broadcast point groups whose screens all share one owner.

### Location operating hours
Required schedule on a Location used as the denominator for commercial-quota percent. Without operating hours, a commercial quota cannot be set.

### Commercial placement
A media-plan placement kind counted toward commercial quota. Own/atmosphere placements do not increase the commercial numerator. Foreign commercial on owned screens is allowed only via the owner’s broadcast point group.

### Shows per hour
Integer N on a media plan. Planned play time for a clock hour is `N × rotation cycle duration`. Multiple commercial plans in the same hour sum without subtracting real on-screen overlap (soft MVP). When the quota period unit is day, checks still slice by hour within the day.

### Airtime booking
An internal reservation record for a calendar window on a group. Kept as a non-UX companion under a media plan so shared-screen exclusivity across organizations can be enforced independently of same-org media-plan conflict checks.
*Avoid:* treating booking as a separate client “hold without content” step in the MediaPlan-as-slot model.

### Media plan
Binding of a rotation to a broadcast point group for a time window. In the slot model, creating an active media plan occupies the airtime slot; soft-cancel releases it.

### Soft-cancel
Releasing an airtime slot by marking the media plan (and its internal booking) cancelled rather than hard-deleting. Cancelled occupancy must not block new placements or appear in on-air packages.

### Invalidated plan
A media plan taken off air by system/operator invalidation rather than an intentional soft-cancel. Like cancelled, it must not occupy calendar exclusivity or appear in on-air packages; it is not the primary client release path.

### First-write-wins (FWW)
Conflict rule for overlapping placements on shared screens: the first successful occupy/reschedule commits; the loser is rejected without mutating the winner’s slot.

### Screen lock
Transaction-scoped serialization over the screens affected by an occupy or reschedule, so two writers cannot both pass the overlap check in the same window.

### Screen overlap guard
The all-organization check that confirmed bookings must not overlap on shared screens. Distinct from same-organization media-plan conflict detection.

### Media plan conflict (same-org)
Rule that active media plans from the same organization must not overlap on shared screens. Does not by itself enforce exclusivity between different organizations.

### Occupancy
The calendar view of busy intervals on a group’s screens for placement UI. Shows only whether a window is occupied and its bounds — not foreign organization identity or booking identifiers.

## Relationships

- A media plan occupies at most one internal airtime booking (1:1 in the slot model); the booking’s window matches the plan.
- Cross-org exclusivity on shared screens is owned by the screen overlap guard on confirmed bookings; same-org plan overlap is owned by media plan conflict detection.
- Soft-cancel of a media plan must free the corresponding booking so FWW can admit a later occupy.
- Occupy and reschedule take a screen lock before the screen overlap guard; the guard, not same-org media plan conflict detection, is authoritative for FWW.

## Flagged ambiguities

- “‘Квота’ / ‘бронь’ in older TZ language meant both capacity budget and calendar hold — product now: no capacity seconds quota for placement; booking is internal; user-facing calendar unit is the media plan. Separately, **commercial quota** is a soft percent cap on commercial placements for owner-homogeneous groups — not a return of AirtimeQuota seconds budgets.”
