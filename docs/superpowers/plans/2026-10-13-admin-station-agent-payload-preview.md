# Admin station agent package/config preview — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On `GET /admin/stations/:id`, show pretty-printed JSON for agent v2 package and v1 config — the same payloads the station receives from the hub.

**Architecture:** `Admin::StationsController#show` calls existing builders `Playlists::PackageFromPlaylists` and `Agent::ConfigBuilder` as-is (package miss still enqueues regenerate). The show view adds two Flowbite cards with `<pre>` + `JSON.pretty_generate`. No domain API changes.

**Tech Stack:** Rails admin (ERB + Flowbite utilities), RSpec request specs, Docker Compose for tests (`docker compose exec -e RAILS_ENV=test web …`).

**Spec:** `docs/superpowers/specs/2026-10-13-admin-station-agent-payload-preview-design.md`

---

## File map

| Path | Responsibility |
| --- | --- |
| `app/controllers/admin/stations_controller.rb` | Set `@agent_package` and `@agent_config` in `show`. |
| `app/views/admin/stations/show.html.erb` | Two preview sections after telemetry. |
| `config/locales/mediateca.ru.yml` | Section titles under `admin.stations`. |
| `config/locales/mediateca.en.yml` | English section titles. |
| `spec/requests/admin/stations_spec.rb` | Request coverage for JSON keys + enqueue on miss. |

No new domain services, routes, or Stimulus controllers.

---

### Task 1: Failing request specs

**Files:**
- Modify: `spec/requests/admin/stations_spec.rb`

- [ ] **Step 1: Add two examples at the end of the describe block (before the final `end`)**

```ruby
  it "renders agent v2 package and v1 config JSON on show" do
    station = create(:station, location: location)
    create(:screen, station: station, name: "Lobby TV", orientation: "landscape")

    get admin_station_path(station)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("admin.stations.agent_package_v2"))
    expect(response.body).to include(I18n.t("admin.stations.agent_config_v1"))
    expect(response.body).to include('"entries"')
    expect(response.body).to include('"screen_map"')
    expect(response.body).to include('"etag"')
    expect(response.body).to include('"station_id"')
    expect(response.body).to include('"screens"')
    expect(response.body).to include('"offline_cache_hours"')
    expect(response.body).to include("Lobby TV")
  end

  it "enqueues GenerateForDateJob when show builds package with missing horizon playlists" do
    station = create(:station, location: location, offline_cache_hours: 24)

    expect {
      get admin_station_path(station)
    }.to have_enqueued_job(Playlists::GenerateForDateJob).at_least(:once)

    expect(response).to have_http_status(:ok)
  end
```

If the file already has `include ActiveJob::TestHelper` (it does), keep it. Do not add a duplicate include.

- [ ] **Step 2: Run the new examples and confirm they fail**

Run:

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec \
  spec/requests/admin/stations_spec.rb \
  -e "renders agent v2 package" \
  -e "enqueues GenerateForDateJob when show builds package"
```

Expected: FAIL — missing i18n keys and/or missing JSON fragments / no enqueue from show.

- [ ] **Step 3: Commit the failing specs**

```bash
git add spec/requests/admin/stations_spec.rb
git commit -m "$(cat <<'EOF'
test: expect agent package/config preview on admin station show

EOF
)"
```

---

### Task 2: Controller + i18n + view

**Files:**
- Modify: `app/controllers/admin/stations_controller.rb`
- Modify: `config/locales/mediateca.ru.yml`
- Modify: `config/locales/mediateca.en.yml`
- Modify: `app/views/admin/stations/show.html.erb`

- [ ] **Step 1: Load builders in `show`**

In `Admin::StationsController#show`, after `@screen_telemetry = …`, add:

```ruby
      @agent_package = Playlists::PackageFromPlaylists.call(station: @station)
      @agent_config = Agent::ConfigBuilder.call(station: @station)
```

Do not pass `enqueue_missing` or any other new keyword — call as-is.

- [ ] **Step 2: Add locale keys**

Under `admin.stations` in `config/locales/mediateca.ru.yml` (next to `telemetry_*` keys):

```yaml
      agent_package_v2: Пакет агента (v2)
      agent_config_v1: Конфиг агента (v1)
```

Under `admin.stations` in `config/locales/mediateca.en.yml`:

```yaml
      agent_package_v2: Agent package (v2)
      agent_config_v1: Agent config (v1)
```

- [ ] **Step 3: Render two preview cards on show**

In `app/views/admin/stations/show.html.erb`, insert **after** the telemetry `</div>` block and **before** the actions `div` (`mt-6 flex flex-wrap gap-3`):

```erb
<div class="mt-6 bg-white border border-gray-200 rounded-lg p-6">
  <h2 class="mb-4 text-lg font-medium text-gray-900"><%= t("admin.stations.agent_package_v2") %></h2>
  <pre class="overflow-x-auto rounded-lg bg-gray-50 p-4 text-xs text-gray-900 whitespace-pre"><%= JSON.pretty_generate(@agent_package) %></pre>
</div>

<div class="mt-6 bg-white border border-gray-200 rounded-lg p-6">
  <h2 class="mb-4 text-lg font-medium text-gray-900"><%= t("admin.stations.agent_config_v1") %></h2>
  <pre class="overflow-x-auto rounded-lg bg-gray-50 p-4 text-xs text-gray-900 whitespace-pre"><%= JSON.pretty_generate(@agent_config) %></pre>
</div>
```

Use only Tailwind utilities (Flowbite admin world). Do **not** use daisyUI classes (`btn`, `alert`, …).

- [ ] **Step 4: Run the new examples and confirm they pass**

Run:

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec \
  spec/requests/admin/stations_spec.rb \
  -e "renders agent v2 package" \
  -e "enqueues GenerateForDateJob when show builds package"
```

Expected: PASS (2 examples).

- [ ] **Step 5: Run the full admin stations request file**

Run:

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/requests/admin/stations_spec.rb
```

Expected: all examples PASS.

- [ ] **Step 6: Commit implementation**

```bash
git add \
  app/controllers/admin/stations_controller.rb \
  app/views/admin/stations/show.html.erb \
  config/locales/mediateca.ru.yml \
  config/locales/mediateca.en.yml
git commit -m "$(cat <<'EOF'
feat(admin): show agent v2 package and v1 config on station page

EOF
)"
```

---

### Task 3: Verification

**Files:** none (run only)

- [ ] **Step 1: Run focused CI subset used while developing**

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/requests/admin/stations_spec.rb
docker compose exec -e RAILS_ENV=test web bundle exec rubocop \
  app/controllers/admin/stations_controller.rb \
  spec/requests/admin/stations_spec.rb
```

Expected: RSpec green; RuboCop clean (or only pre-existing offenses unrelated to this change).

- [ ] **Step 2: Finish with full `bin/ci` before considering the branch done**

```bash
docker compose exec -e RAILS_ENV=test web bin/ci
```

Expected: exit 0.

- [ ] **Step 3: If CI made no extra file changes, stop. If rubocop -A touched files, commit the fix separately**

```bash
git status
# only if needed:
git add <touched files>
git commit -m "$(cat <<'EOF'
style: fix rubocop on admin station agent preview

EOF
)"
```

---

## Spec coverage checklist

| Spec requirement | Task |
| --- | --- |
| Call `PackageFromPlaylists` as-is (enqueue on miss) | Task 2 Step 1 + Task 1 enqueue example |
| Call `Agent::ConfigBuilder` | Task 2 Step 1 |
| Pretty JSON for full v2 package | Task 2 Step 3 |
| Pretty JSON for full v1 config | Task 2 Step 3 |
| Placement after telemetry, before actions | Task 2 Step 3 |
| i18n ru+en | Task 2 Step 2 |
| Request specs for keys + enqueue | Task 1 |
| No domain contract change | File map (no builder edits) |
