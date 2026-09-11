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
Required schedule on a Location used as the denominator for commercial-quota percent. Without operating hours, a commercial quota cannot be set. Windows are wall-clock in the location time zone. Also the default schedule for screens that inherit operating hours from their location.

### Screen operating hours
Optional schedule on a Screen. By default a screen **inherits** operating hours from its station's Location (`inherit_operating_hours_from_location`). When inheritance is off, the screen's own jsonb schedule applies. **Effective operating hours** for playlist generation and service welcome/close clips are inherited or custom accordingly. Commercial quota still uses Location hours on the group.

### Location time zone
IANA TZDB zone on Location (default `"UTC"`). It is the clock of the **broadcast day**: playlist `for_date` / day anchor, and operating-hours windows (location and per-screen effective hours). Distinct from the client organization's time zone, which advertising orders still use for their grids.

### Commercial placement
A media-plan placement kind counted toward commercial quota. Own/atmosphere placements do not increase the commercial numerator. Foreign commercial on owned screens is allowed only via the owner’s broadcast point group.

### Shows per hour
Integer N on a media plan and on an advertising order. Planned play time for a clock hour is `N × rotation cycle duration`. Multiple commercial plans in the same hour sum without subtracting real on-screen overlap (soft MVP). When the quota period unit is day, checks still slice by hour within the day. An advertising order stores one N for the whole document; activation copies it onto each occupied claim.

### Airtime booking
An internal reservation record for a calendar window on screens (optional broadcast point group). Kept as a non-UX companion under a media plan so shared-screen exclusivity across organizations can be enforced independently of same-org media-plan conflict checks.
*Avoid:* treating booking as a separate client “hold without content” step in the MediaPlan-as-slot model.

### Media plan
Binding of a rotation to screens (`media_plan_screens`; broadcast point group optional) for a time window. In the slot model, creating an active media plan occupies the airtime slot; soft-cancel releases it.

### Advertising order
Commercial order document (counterparty, product, clip, hourly rate and day windows on the order, per-screen day grid). Each order line is one screen. Activation occupies intersecting operating-hour windows as overlapping claims; two commercial orders may share a screen hour. Slots keep a nullable reference to their order line; manually created slots have none. The order is the commercial truth; the slot remains the airtime truth. Authored either by the client's manager in the client cabinet or by the operator on the client's behalf in the admin panel — the order always belongs to the client organization, while `created_by_user_id` records the actual author.

### Organization profile
A 1:1 companion of an Organization holding descriptive attributes filled by the operator in the admin panel: business sphere (chosen from the operator-managed `Directory::BusinessSphere` directory), brand, and holding (a holding groups several brands, e.g. holding "Командор" contains brands Командор, Аллея, Хороший). An advertising order snapshots the business sphere name from the profile at creation; later profile or directory edits do not rewrite issued order documents.

### Directory (Справочник)
Namespace (`Directory::`) for operator-managed reference lists, e.g. `Directory::BusinessSphere`. Values are maintained in the admin panel before use; entities reference directory entries by FK, while issued documents snapshot entry names so renames or deletions never rewrite history.

### Broadcast portrait
A screen's airtime structure (cyclic kind with block frequency per hour, ordered blocks: commercial from active slots, filler rotations with pick strategy, timed insertions, service headers, service welcome/close). A portrait without a screen (`screen_id` nil) is an operator **template** copied to a screen when the screen is created or when the operator replaces the template on edit. Neutral filler clips must be at least 10 seconds unless the operator narrows the portrait to 5. Screens on one station may each have a different portrait (e.g. different service theme).

### Service theme
Operator-managed thematic bundle for service clips: one named theme owns four `system_managed` rotations (ad header start/end, welcome, close). The operator uploads service `MediaAsset`s into the theme's rotations in admin. A whole theme may be applied to a screen portrait via `service_theme_id` (materializing the four blocks), or each service block on a portrait may pick its own theme; the block stores `service_theme_id` and the matching rotation.

### Playlist
Materialized daily **projection** per station: versioned positions with timing, screens, and origin (media plan / filler / insertion / service), generated from active slots plus **each screen's** broadcast portrait and effective operating hours, then merged into one station document. One current version per station and date. Aged playlists (dates past the purge cutoff, any status) are purged; superseded versions of in-window dates remain until that date ages out. Airtime truth remains MediaPlan + confirmed booking; certificates, when added, must come from orders and play logs, not playlists. New station agents read `GET /api/agent/v2/package`; `GET /api/agent/v1/package` stays the overlapping-plan shape.

Regen runs after occupy, cancel, and reschedule succeed; cancel does not fire ActiveRecord callbacks, so regen must be explicit. When a current playlist exists in the station cache horizon, play events attribute from that playlist; otherwise they fall back to overlapping-plan matching.

### Rotation
An ordered catalog of clips belonging to an organization. A media plan binds one rotation to a group's screens for a window; portrait filler and insertion blocks also point at rotations. `system_managed` rotations (advertising-order singletons and service-theme folders) are not listed in ordinary rotation CRUD; theme clips are uploaded through the operator service library.
*Avoid:* Playlist (MVP1 name for this catalog)

### Soft-cancel
Releasing an airtime slot by marking the media plan (and its internal booking) cancelled rather than hard-deleting. Cancelled occupancy must not block new placements or appear in on-air packages.

### Invalidated plan
A media plan taken off air by system/operator invalidation rather than an intentional soft-cancel. Like cancelled, it must not occupy calendar exclusivity or appear in on-air packages; it is not the primary client release path.

### First-write-wins (FWW)
Conflict rule for overlapping placements on shared screens: the first successful occupy/reschedule commits; the loser is rejected without mutating the winner’s slot.

### Screen lock
Transaction-scoped serialization over the screens affected by an occupy or reschedule, so two writers cannot both pass the overlap check in the same window.

### Screen overlap guard
The all-organization check that confirmed bookings must not overlap on shared screens. Distinct from same-organization media-plan conflict detection. Advertising-order claims (`order_claim`, `advertising_order_line_id` present) may overlap each other; a manual media plan without an order line stays first-write-wins against everyone, including order claims.

### Media plan conflict (same-org)
Rule that active media plans from the same organization must not overlap on shared screens. Does not by itself enforce exclusivity between different organizations.

### Occupancy
The calendar view of busy intervals on a group’s screens for placement UI. Shows only whether a window is occupied and its bounds — not foreign organization identity or booking identifiers.

## Relationships

- A media plan occupies at most one internal airtime booking (1:1 in the slot model); the booking’s window matches the plan.
- Cross-org exclusivity on shared screens is owned by the screen overlap guard on confirmed bookings; same-org plan overlap is owned by media plan conflict detection.
- Soft-cancel of a media plan must free the corresponding booking so FWW can admit a later occupy.
- Occupy and reschedule take a screen lock before the screen overlap guard; the guard, not same-org media plan conflict detection, is authoritative for FWW.
- A playlist is a daily projection of occupied slots plus per-screen portraits (merged per station); it does not occupy airtime. A rotation is a clip catalog bound by a media plan or portrait block. A service theme groups four rotations for operator service clips on a screen portrait.

## Flagged ambiguities

- “‘Квота’ / ‘бронь’ in older TZ language meant both capacity budget and calendar hold — product now: no capacity seconds quota for placement; booking is internal; user-facing calendar unit is the media plan. Separately, **commercial quota** is a soft percent cap on commercial placements for owner-homogeneous groups — not a return of AirtimeQuota seconds budgets.”
- “‘Playlist’ in MVP1 named today’s Rotation (clip catalog); Playlist is now the station daily projection.”
- “Broadcast portrait was initially per station; product direction (2026-09) is per screen, with templates copied on screen create. Operating hours follow the same pattern: location default, optional per-screen override with inherit flag.”
