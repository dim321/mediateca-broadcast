# Concepts

Shared domain vocabulary for this project — entities, named processes, and status concepts with project-specific meaning. Seeded with core domain vocabulary, then accretes as ce-compound and ce-compound-refresh process learnings; direct edits are fine. Glossary only, not a spec or catch-all.

## Airtime

### Airtime slot
A calendar window on the screens of a broadcast point group that one client organization may occupy for playback. In the MediaPlan-as-slot model the user-facing slot is created with a media plan; capacity budgets in seconds are not part of the product.

### Airtime quota
An operator-defined seconds budget for a group and time window. Settled product direction when selling the whole free calendar: do not use quotas as a prerequisite for placement.

### Airtime booking
An internal reservation record for a calendar window on a group. Kept as a non-UX companion under a media plan so shared-screen exclusivity across organizations can be enforced independently of same-org media-plan conflict checks.
*Avoid:* treating booking as a separate client “hold without content” step in the MediaPlan-as-slot model.

### Media plan
Binding of a rotation to a broadcast point group for a time window. In the slot model, creating an active media plan occupies the airtime slot; soft-cancel releases it.

### Soft-cancel
Releasing an airtime slot by marking the media plan (and its internal booking) cancelled rather than hard-deleting. Cancelled occupancy must not block new placements or appear in on-air packages.

### First-write-wins (FWW)
Conflict rule for overlapping placements on shared screens: the first successful occupy/reschedule commits; the loser is rejected without mutating the winner’s slot.

### Screen overlap guard
The all-organization check that confirmed bookings must not overlap on shared screens. Distinct from same-organization media-plan conflict detection.

### Media plan conflict (same-org)
Rule that active media plans from the same organization must not overlap on shared screens. Does not by itself enforce exclusivity between different organizations.

## Relationships

- A media plan occupies at most one internal airtime booking (1:1 in the slot model); the booking’s window matches the plan.
- Cross-org exclusivity on shared screens is owned by the screen overlap guard on confirmed bookings; same-org plan overlap is owned by media plan conflict detection.
- Soft-cancel of a media plan must free the corresponding booking so FWW can admit a later occupy.

## Flagged ambiguities

- “‘Квота’ / ‘бронь’ in older TZ language meant both capacity budget and calendar hold — product now: no capacity quota; booking is internal; user-facing unit is the media plan.”
