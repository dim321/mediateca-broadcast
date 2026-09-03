# Mediateca Broadcast

Operator-run digital signage hub: organizations place media on shared screens, stations cache a daily on-air document, agents report play events. Default UI locale is Russian (`config.i18n.default_locale = :ru`); English keys exist alongside.

`CONCEPTS.md` is the shared domain vocabulary (entities, named processes, status concepts). Relevant when orienting to the codebase or discussing domain terms — Playlist vs Rotation, airtime slot vs commercial quota, location time zone vs organization time zone.

`docs/solutions/` holds documented solutions to past problems (bugs, best practices, architecture patterns), organized by category with YAML frontmatter (`module`, `tags`, `problem_type`). Relevant when implementing or debugging in documented areas.

## Stack

- Ruby 4.0.2, Rails ~> 8.1, PostgreSQL 18, Propshaft, importmap, Hotwire (Turbo + Stimulus), Tailwind CSS 4
- Auth: bcrypt sessions + `Current.user` — not Devise
- Jobs/cache/cable: Solid Queue, Solid Cache, Solid Cable (not Sidekiq)
- Authz: Pundit in the client cabinet only
- Views: Slim + daisyUI in the cabinet; ERB + Flowbite in `/admin`
- Deploy: Kamal; local run: Docker Compose (`compose.yaml`)

## Surfaces

| Surface | Who | Notes |
|--------|-----|--------|
| Cabinet `/` | Client managers / accountants | Pundit, Slim, daisyUI (`btn`, `alert`, …) |
| Operator admin `/admin` | Operator org only | No Pundit; Flowbite utilities; **never** daisyUI classes |
| Station agent `/api/agent` | Device, Bearer station token | JSON; v1 package frozen; v2 timed playlist entries |

Do not mix the two CSS worlds. Admin details: `.cursor/rules/flowbite-admin.mdc`. Cabinet Hotwire: `.cursor/rules/hotwire.mdc`.

Admin sidebar is `AdminHelper::NAV_SECTIONS` plus i18n `admin.nav.*`, not route introspection. Adding an admin resource means routes + nav + locale keys.

## Domain layer

Business writes live in `app/domain/` as callable objects (`ServiceObject.call` / `Foo::Bar.call`). Controllers stay thin.

Occupancy writers (MediaPlan + confirmed `AirtimeBooking`, first-write-wins):

- `Airtime::OccupyWithPlan`, `Airtime::Cancel`, `Airtime::Reschedule`
- Serialize with `Airtime::ScreenLock` (advisory namespace `874_201`), then `Airtime::ScreenOverlapGuard`

Playlist is a **daily projection**, not a second occupancy writer. After a successful occupy/cancel/reschedule (and clip replace), call `Playlists::EnqueueRegen` **outside** the FWW transaction. Cancel uses `update_columns`, so ActiveRecord callbacks cannot hook regen.

Patterns:

- `docs/solutions/architecture-patterns/media-plan-as-airtime-slot.md`
- `docs/solutions/architecture-patterns/playlist-as-airtime-projection.md`

## Invariants

- Do not delete `AirtimeBooking` or restore seconds `AirtimeQuota` as placement capacity. Commercial quota is a soft percent cap on owner-homogeneous groups — flash, do not roll back occupy.
- Do not skip Guard or take ScreenLock inside `Playlists::GenerateForDate` (playlist lock namespace is `874_202`).
- Broadcast-day clock is `locations.time_zone`. Advertising order grids use the **client organization** time zone.
- Playlist items carry screens (`playlist_item_screens`). Screens of one station can sit in different groups.
- `GET /api/agent/v1/package` stays overlapping-plan JSON (`Agent::PackageBuilder`). Do not add `schema_version` there. New agents use `GET /api/agent/v2/package` (`Playlists::PackageFromPlaylists`). Play events stay `POST /api/agent/v1/play_events`.
- Neutral filler: sequential offset from the epoch date, not `yday`; random = `Random.new(SHA256 digest)`, never `srand` / `String#hash`.
- MVP1 name “Playlist” is today’s **Rotation** (clip catalog). `Playlist` is the station daily row.

## Docs map

| Path | What |
|------|------|
| `CONCEPTS.md` | Glossary |
| `docs/solutions/` | Searchable learnings (YAML frontmatter) |
| `docs/plans/` | Implementation plans |
| `docs/brainstorms/` | Design notes before a plan |
| `docs/guides/` | Human onboarding / manager guide |
| `specs/002-monitors-broadcast-tz/contracts/` | Agent API v1 (frozen) and v2 |

Older `specs/001-*` and `.specify/` snapshots can lag the tree (they may still mention Devise/Sidekiq). Prefer `CONCEPTS.md`, `docs/solutions/`, and the current code.

## Tests and local run

App: http://localhost:3000. PostgreSQL is the Compose `postgres` service — do not look for a host Postgres.

```bash
docker compose up --build
docker compose exec -e RAILS_ENV=test web bundle exec rspec
docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/path/to/spec.rb
```

Always pass `RAILS_ENV=test` into the `web` container. The Compose default is development; omitting it points RSpec at the development DB. Do not run `bundle exec rspec` on the host.

RSpec + FactoryBot. Spec path mirrors `app/` (`app/domain/airtime/cancel.rb` → `spec/domain/airtime/cancel_spec.rb`).

## Conventions

- UI copy and enum labels: `config/locales/mediateca.ru.yml` / `mediateca.en.yml`
- Recurring jobs: `config/recurring.yml` under `production:` (dispatch playlist horizon every 15 minutes UTC, purge aged playlists at 4am)
- Mutations that redirect: `status: :see_other`
- Admin destroy with FK restrict: `destroy_with_restriction`
- Ransack: allowlist `ransackable_attributes` / `ransackable_associations`; admin search uses `ransack_params` (hash-only)
- New domain work: extend an existing `app/domain/<area>/` service rather than stuffing occupy/cancel/playlist logic into models
