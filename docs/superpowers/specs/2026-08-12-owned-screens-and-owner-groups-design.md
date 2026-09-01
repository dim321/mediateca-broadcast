# Owned screens and owner groups in LK

**Date:** 2026-08-12  
**Status:** approved for planning  
**Approach:** A — two LK sections on existing models (`Screen`, `BroadcastPointGroup`)

## What We're Building

Client organization **managers and administrators** get two new cabinet sections:

1. **Мои экраны** — full CRUD for screens owned by their organization (`owner_organization_id`).
2. **Мои группы** — create / edit / show / manage members for named broadcast point groups built **only** from those owned screens, including commercial quota (same action set as existing groups: **no destroy**, matching `BroadcastPointGroupsController`).

Stations and locations remain operator-only (Administrate). Existing **Экраны в эфире** (`fleet/screens`) and **Группы экранов** (`broadcast_point_groups`) stay unchanged.

## Why This Approach

| Option | Verdict |
|--------|---------|
| A — two sections, same models | Chosen: reuses ownership + quota gates, isolates UX from fleet catalog groups |
| B — nested groups under screens only | Rejected: weaker discoverability of quota |
| C — new `OwnerScreenGroup` table | Rejected: duplicates `BroadcastPointGroup` and breaks media-plan/quota path |

## Key Decisions

- **Ownership on create:** controller always sets `owner_organization = Current.user.organization`; client cannot clear or reassign owner.
- **Station selection:** create/edit uses cascade — choose existing **location**, then **station** belonging to that location (Turbo Frame or Stimulus dependent select).
- **Authorization:** manager/administrator of client org (`client_mutator?` / `lk_content_access?`). Accountant denied. Operator continues via admin; no requirement to expose these sections to operators.
- **Screen destroy:** respect `dependent: :restrict_with_exception` (memberships, play_logs); show flash, keep record.
- **Owner groups catalog:** add/remove members only from `organization.owned_screens`; rejecting any other screen id.
- **Quota:** reuse `BroadcastPointGroup` validations (`commercial_quota_percent` / `period`, homogeneous owner, locations with operating hours). No schema change required for quota.
- **No tags on client screen create** in this scope (tags remain operator/admin concern).
- **No changes** to `fleet/screens` or existing `broadcast_point_groups` controllers/views beyond sidebar links for the new sections.

## Routes

```ruby
resources :owned_screens
resources :owned_broadcast_point_groups do
  member do
    post :add_screens
    delete :remove_member
  end
end
```

Sidebar (manager/admin, not accountant): «Мои экраны», «Мои группы».

## Controllers and policies

### Owned screens

- `OwnedScreensController` — standard CRUD; `require_user`; `authorize` + `policy_scope`.
- Scope: `Screen.where(owner_organization_id: user.organization_id)`.
- Strong params: `name`, `orientation`, `station_id` only.
- Form-only `location_id` drives the cascade UI and is **not** stored on `Screen`. On create/update, `station_id` must reference an existing station; if `location_id` is also submitted, reject when the station’s location does not match.

### Owned broadcast point groups

- `OwnedBroadcastPointGroupsController` — mirror of `BroadcastPointGroupsController` UX, but:
  - `organization` always `Current.user.organization`
  - member catalog = owned screens not already in the group
  - no fleet tag filter
- Same model validations for commercial quota.

### Policies

- Dedicated policy (or ScreenPolicy branch) for owned-screen actions: mutate only if `client_mutator?` and `record.owner_organization_id == user.organization_id`.
- Owner-group actions: tenant-scoped like existing BPG policy; `add_screens` additionally constrained in controller to owned screens.

## UI

Follow existing LK patterns (`shared/page_header`, daisyUI `btn` / `input` / `select` / `list`, Slim forms like media plans / groups).

**Мои экраны**

- Index: name, station, location, orientation; CTA «Добавить экран»; empty state.
- New/Edit: location select → station select (reset station when location changes); name; orientation.
- Show: details + edit/delete (delete with confirm).

**Мои группы**

- Index/new/edit/show analogous to current groups (no destroy).
- Form: name, commercial_quota_percent, commercial_quota_period + existing quota hint.
- Show: members list; add from owned screens only; remove member.

## Error handling

- Model validation failures → `render :new/:edit, status: :unprocessable_content`.
- Out-of-scope ids → 404 via `policy_scope` or alert on add_screens.
- Destroy restricted by associations → alert, no delete.
- Quota gate failures → existing AR error keys (`commercial_quota_requires_*`, incomplete pair).

## Testing

- Request specs for owned screens CRUD: tenant isolation, forced owner, station must belong to chosen location flow, destroy restrict.
- Request specs for owned groups: only owned screens as members, quota assign/clear, isolation from other orgs.
- Policy specs: manager/admin allowed; accountant denied; cannot mutate another org’s owned screen/group.
- Regression: unchanged behaviour for `fleet/screens` and `broadcast_point_groups`.

## Out of scope

- Creating/editing stations or locations from these sections.
- Client-managed screen tags.
- Changing fleet catalog or legacy groups UI.
- New DB tables for owner groups.
- Accountant access.

## Open Questions

None for planning — resolved in brainstorming.

## Next Steps

→ Implementation plan via writing-plans skill.
