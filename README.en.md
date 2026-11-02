# 🚀 Mediateca Broadcast

**Mediateca Broadcast** is an operator-run digital signage hub: organizations place media on shared screens, stations cache a daily on-air document, and device agents report playback. The client cabinet and operator admin cover media plans, commercial orders, broadcast portraits, and the station fleet.

[![CI](https://github.com/dim321/mediateca-broadcast/actions/workflows/ci.yml/badge.svg)](https://github.com/dim321/mediateca-broadcast/actions/workflows/ci.yml)
![Ruby](https://img.shields.io/badge/Ruby-4.0.9-red?logo=ruby)
![Rails](https://img.shields.io/badge/Rails-8.1-red?logo=rubyonrails)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-18-blue?logo=postgresql)

**Русский:** [README.md](README.md)

---

## 🌟 Features

- **Organization-scoped multi-tenancy** — clients, operator, and cabinet data isolation (Pundit); operator admin without Pundit.
- **Airtime slot (MediaPlan-as-slot)** — calendar occupancy via media plans with first-write-wins, advisory locks, and overlap checks.
- **Commercial orders** — per-screen hourly grids, activation with slot occupancy, soft commercial quota checks (percent; no occupy rollback).
- **Daily playlist** — materialized on-air projection per station; regen after occupy/cancel/reschedule; Agent API v2 for new agents.
- **Broadcast portrait & service themes** — cyclic block structure, neutral filler, welcome/close tied to location hours.
- **Agent API** — station Bearer token, `v1` (legacy package + play events) and `v2` (playlist-based package), telemetry and commands.
- **Two UI stacks** — client cabinet (Slim, Hotwire, daisyUI 5) and `/admin` (ERB, Flowbite; no daisyUI).
- **Operator directories** — e.g. business spheres (`Directory::BusinessSphere`) with CSV import.
- **Kamal deploy** — production containers; local dev via Docker Compose and `bin/dev`.

Domain glossary: [`CONCEPTS.md`](CONCEPTS.md). Role onboarding: [`docs/guides/onboarding/`](docs/guides/onboarding/).

---

## 🛠 Tech stack

### Backend

| Component | Technology |
|-----------|------------|
| Language / framework | Ruby **4.0.9**, Rails **~> 8.1.4** |
| Database | PostgreSQL **18** (`pg`) |
| App server | Puma, Thruster (production) |
| Background jobs | **Solid Queue** (not Sidekiq) |
| Cache / Cable | **Solid Cache**, **Solid Cable** (PostgreSQL-backed) |
| Auth | `bcrypt` + `Current.user` (not Devise) |
| Cabinet authorization | Pundit |
| Domain logic | `app/domain/` — callable service objects |
| Media | Active Storage, `ruby-vips`, ffmpeg; S3-compatible storage in production |
| i18n | Default locale **Russian** (`config.i18n.default_locale = :ru`) |

### Frontend

| Component | Technology |
|-----------|------------|
| Interactivity | Hotwire (**Turbo**, **Stimulus**), importmap |
| Styles | **Tailwind CSS 4** (`tailwindcss-rails`) |
| Cabinet | Slim, **daisyUI 5**, ViewComponent |
| Admin | ERB, **Flowbite 4** (separate `admin.css` build) |

### Database & ops

| Component | Technology |
|-----------|------------|
| Admin search | Ransack, Kaminari |
| Production logs | Lograge |
| Local dev | Docker Compose (`compose.yaml`), Foreman (`Procfile.dev`) |
| CI/CD | **GitHub Actions** (`.github/workflows/ci.yml`) |
| Deploy | Kamal (`config/deploy.yml`) |

> **Note:** The project does **not** use Redis or Sidekiq. There is no Sentry integration in the codebase.

---

## ⚙️ Prerequisites

### Recommended — Docker Compose

- Docker and Docker Compose
- Optional: `.env` file (see [`.env.example`](.env.example))

### Native host (without Docker)

| Dependency | Version / notes |
|------------|-----------------|
| Ruby | **4.0.9** (`.ruby-version`) |
| Bundler | compatible with `Gemfile.lock` |
| PostgreSQL | **18** (or compatible; omit `DB_HOST` for socket) |
| Node.js | **22** (matches CI; for `npm ci` / daisyUI / Flowbite) |
| ffmpeg | media processing |
| libvips | Active Storage previews/variants |
| Foreman | installed on first `bin/dev` run |

Redis is **not** required.

---

## 🚀 Getting started

### 1. Clone

```bash
git clone git@github.com:dim321/mediateca-broadcast.git
cd mediateca-broadcast
```

### 2. Environment

```bash
cp .env.example .env
```

With **Docker Compose**, do not set `DB_HOST=localhost` in `.env` — the `web` service already uses `DB_HOST=postgres`. See comments in `.env.example`.

### 3. Docker Compose (recommended)

```bash
docker compose up --build
```

- App: [http://localhost:3000](http://localhost:3000)
- PostgreSQL from host: `localhost:5432`, user/password `postgres` / `postgres`

One-time setup inside the container:

```bash
docker compose run --rm web bin/setup --skip-server
```

Optional business-sphere directory import:

```bash
docker compose exec web bundle exec rake directory:business_spheres:import
```

See [`docs/guides/directory-business-spheres-import.md`](docs/guides/directory-business-spheres-import.md).

### 4. Native host

```bash
bundle install
npm install
bin/setup          # db:prepare (dev + test), tailwindcss:build, then bin/dev
# or server only:
bin/dev            # Foreman: Rails + tailwind watch + admin CSS watch
```

`bin/dev` runs `Procfile.dev` (default port **3000**).

### 5. Database

| Command | Purpose |
|---------|---------|
| `bin/rails db:prepare` | create DB, migrate, load schema |
| `bin/rails db:seed` | seed data (`db/seeds.rb`) |
| `bin/setup --reset` | `db:reset` in dev (destructive) |

In Docker, always pass `RAILS_ENV=test` for specs:

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec
```

---

## 🧪 Testing & quality

### Full local CI (after changes)

In Docker:

```bash
docker compose exec -e RAILS_ENV=test web bin/ci
```

`bin/ci` runs: `bin/setup --skip-server`, RuboCop, RSpec, bundler-audit, importmap audit, Brakeman.

### Individual commands

```bash
# RSpec
docker compose exec -e RAILS_ENV=test web bundle exec rspec
docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/path/to/spec.rb

# RuboCop
bin/rubocop

# Security
bin/brakeman --no-pager
bin/bundler-audit
bin/importmap audit

# Autoload
bin/rails zeitwerk:check
```

### GitHub Actions

On every **push to `main`** and **pull request**, [`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs:

1. **scan_ruby** — Brakeman, bundler-audit  
2. **scan_js** — importmap audit  
3. **lint** — RuboCop  
4. **test** — PostgreSQL 18, `npm ci`, Tailwind build, `db:test:prepare`, Zeitwerk, **RSpec**

---

## 📁 Architecture & layout

### Application surfaces

| Path | Audience | UI / auth |
|------|----------|-----------|
| `/` | Client managers / accountants | Slim, daisyUI, Pundit |
| `/admin` | Operator org only | Flowbite, no Pundit |
| `/api/agent` | Station agent (Bearer token) | JSON |

### Domain layer

Business logic lives in **`app/domain/`** (`ServiceObject` subclasses, `Foo::Bar.call`):

| Area | Examples |
|------|----------|
| `airtime/` | `OccupyWithPlan`, `Cancel`, `Reschedule`, `ScreenLock`, `ScreenOverlapGuard` |
| `playlists/` | `GenerateForDate`, `EnqueueRegen`, `PackageFromPlaylists` |
| `advertising/` | orders, activation, grid, clip validation |
| `agent/` | package/config, play events, commands, telemetry |
| `commercial_quota/` | soft commercial percent checks |
| `portraits/`, `rotations/`, `service_themes/` | broadcast portrait and service rotations |

**Invariants (short):** airtime truth is MediaPlan + confirmed booking; playlist is a projection, not a second occupy writer. After successful occupy/cancel/reschedule, call `Playlists::EnqueueRegen` **outside** the FWW transaction. Do not break Agent **v1** package contract; new agents use **v2**.

### Useful paths

| Path | Contents |
|------|----------|
| [`AGENTS.md`](AGENTS.md) | Developer / assistant summary |
| [`CONCEPTS.md`](CONCEPTS.md) | Domain glossary |
| [`docs/solutions/`](docs/solutions/) | Documented patterns and fixes |
| [`specs/002-monitors-broadcast-tz/contracts/`](specs/002-monitors-broadcast-tz/contracts/) | Agent API v1/v2 contracts |
| [`lib/data/`](lib/data/) | CSV directories (business spheres, etc.) |

Specs mirror `app/` (e.g. `app/domain/airtime/cancel.rb` → `spec/domain/airtime/cancel_spec.rb`).

---

## 🚢 Production / Kamal

Production is deployed with **[Kamal 2](https://kamal-deploy.org/)**, not the root `compose.yaml` (Compose is local development only). Images are built from the production [`Dockerfile`](Dockerfile) (Puma + Thruster, ffmpeg, libvips).

### Configuration

| File | Purpose |
|------|---------|
| [`config/deploy.yml`](config/deploy.yml) | Service, hosts, proxy/SSL, registry, env, accessories |
| [`bin/deploy`](bin/deploy) | Load `.env` and invoke Kamal (`bundle exec kamal`) |
| [`.kamal/secrets`](.kamal/secrets) | Secret interpolation from ENV / `config/master.key` (no raw passwords in git) |
| [`config/recurring.yml`](config/recurring.yml) | Solid Queue recurring tasks in production (playlists, purge, advertising) |

Public host and TLS are set in `deploy.yml` (`proxy.host`, Let's Encrypt). `APP_HOST` / `APP_PROTOCOL` are used by agents and media uploads from external stations.

### Secrets before deploy

Secrets and Kamal-related variables belong in **`.env`** (do not commit; template: [`.env.example`](.env.example)). [`.kamal/secrets`](.kamal/secrets) maps them into `config/deploy.yml` (including `RAILS_MASTER_KEY` from `config/master.key`).

Before any Kamal command, variables from `.env` must be exported. Use the **`bin/deploy`** wrapper — it runs `set -a`, `source .env`, then `bundle exec kamal`:

```bash
# Examples (same arguments as kamal)
bin/deploy deploy
bin/deploy logs
bin/deploy console
```

Do not call `bin/kamal` directly if secrets live only in `.env`; deploy will fail on registry/DB/S3 without the export step.

Minimum `.env` set for production (see `.env.example` and `.kamal/secrets`):

- `MEDIATECA_BROADCAST_DATABASE_PASSWORD` — PostgreSQL accessory password (same value wired as `POSTGRES_PASSWORD` in secrets)
- `KAMAL_REGISTRY_USER` / `KAMAL_REGISTRY_PASSWORD` — private registry login
- `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` — **rustfs** (S3-compatible), bucket `media`, endpoint in `deploy.yml`

Inside the app container: `DB_HOST=mediateca_broadcast-db`, `ACTIVE_STORAGE_SERVICE=rustfs`, `SOLID_QUEUE_IN_PUMA=true` (Solid Queue workers run inside Puma on the current topology).

### Accessories

`deploy.yml` defines:

- **`registry`** — Docker Registry on port `:5555` on the deploy host (Kamal image push/pull)
- **`db`** — PostgreSQL **18**, bound to `127.0.0.1:5432` on the host

First-time boot (or after recreation):

```bash
bin/deploy accessory boot registry
bin/deploy accessory boot db
```

For HTTP registries without TLS, you may need Docker `insecure-registries` on all push/pull hosts — see comments in `config/deploy.yml`.

### Deploy & operations

```bash
# Build, push to registry, rolling deploy
bin/deploy deploy

# Logs, console, database console
bin/deploy logs
bin/deploy console
bin/deploy dbc
```

Aliases (`console`, `shell`, `logs`, `dbc`) are defined in `deploy.yml` and should be invoked via **`bin/deploy`**, not `bin/kamal`.

Migrations run as part of the standard Kamal + Rails 8 deploy flow. Manual run if needed:

```bash
bin/deploy app exec 'bin/rails db:migrate'
```

### Background work in production

Solid Queue runs inside Puma (`SOLID_QUEUE_IN_PUMA`). Recurring tasks (`config/recurring.yml`, `production:`):

- every **15 minutes** — playlist horizon dispatch (`Playlists::DispatchHorizonJob`)
- **04:00** — purge expired playlists
- **03:00** — complete expired advertising orders
- hourly — clear finished Solid Queue jobs

When scaling to multiple web servers, consider a dedicated `servers.job` role (template is commented in `deploy.yml`).

---

## 📝 License

There is **no `LICENSE` file** in the repository root. Use and distribution terms are defined by the project owner. Add a `LICENSE` file and update this section if you open-source the code.

---

## 📚 Further reading

- [Role onboarding](docs/guides/onboarding/README.md)
- [Business sphere import](docs/guides/directory-business-spheres-import.md)
- [Manager guide](docs/guides/manager-guide.md)
