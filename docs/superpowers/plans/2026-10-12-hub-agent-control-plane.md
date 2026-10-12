# Hub Agent Control Plane Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Довести Broadcast Hub до контракта station M2: опциональный `tv_monitor` в config, приём telemetry, очередь per-screen команд с signed PUT для screenshot/record и идемпотентный ack.

**Architecture:** Station по-прежнему сама ходит в Hub по Bearer-токену. Новые маршруты сидят на `Api::Agent::V1::BaseController`. Снимок telemetry — одна строка на station и одна на screen (без истории). Команда живёт в `agent_commands` со статусом `pending`, пока `command_results` не переведёт её в `acked`. Файл screenshot/record station кладёт PUT-ом на Hub (URL авторизует сам себя), Hub пишет байты в Active Storage. Прямой presign в rustfs не используем: в `config/storage.yml` бакет приватный, клиенты ходят только в приложение.

**Tech Stack:** Rails 8.1, PostgreSQL, Active Storage, RSpec, FactoryBot, существующий `ServiceObject` (`Agent::BaseService`).

**Repository:** `/home/dim/Projects/MyPets/mediateca-broadcast`. Все пути ниже от корня этого репозитория. Station не менять.

**Spec:** `/home/dim/Projects/MyPets/mediateca-station/.worktrees/002-voxel-integration/docs/superpowers/specs/2026-10-09-hub-agent-control-plane-api.md`

**Клиент, с которым сверять JSON:** `mediateca-station/.worktrees/002-voxel-integration/internal/hub/client.go`. Сейчас `agent.go` вызывает `FetchCommands(ctx, "")`, то есть `If-None-Match` пустой. `304` station трактует как пустую очередь.

## Global Constraints

- Auth на `/api/agent/v1/*`: `Authorization: Bearer <agent_token>`. Невалидный токен — HTTP 401 и тело `{ "error": "unauthorized" }`.
- `PUT /api/agent/uploads/:token` без Bearer. Не отвечать на него 401: `UploadArtifact` превращает 401 в `ErrUnauthorized`. Просроченный или чужой token — **403**.
- Не менять семантику `GET /api/agent/v1/config` (кроме добавления ключа), `GET /api/agent/v2/package`, `POST /api/agent/v1/play_events`. Не трогать их контроллеры.
- Нет записи `station_tv_monitors` — ключа `tv_monitor` в JSON нет. Не слать `tv_monitor: {}`. Если запись есть, `auto_restart_when_not_playing` всегда явный `true` или `false`.
- Telemetry: успех **202**. Пустой `wakefulness`, нулевой `broadcast_clients` и чужой `screen_id` не дают 422 на весь батч. Чужой id копится в `ignored_screen_ids` последнего снимка.
- Команды только per-screen. `id` — `cmd_` + UUID, не переиспользовать. `params` — JSON object. `issued_at` — UTC `iso8601` с `Z`.
- `screenshot` и `record` всегда получают `params.upload_url` (TTL токена **15 минут**). Без multipart в `command_results`.
- Повторный `command_results` с тем же `command_id` — **200**. Неизвестный `command_id` и команда другой station — **200** и ignore, не 404.
- `error: "already_done"` при `ok: true` — успешный ack, команда уходит из `pending`.
- Hub не открывает соединение на mini-PC. История telemetry и UI конфликта `stop` vs auto-restart сверх текста подсказки — не этот план (спека §10).

---

## File map

| Path | Responsibility |
| --- | --- |
| `db/migrate/20261012100100_create_station_tv_monitors.rb` | Опциональные настройки watchdog. |
| `db/migrate/20261012100200_create_telemetry_snapshots.rb` | Последний снимок station и screen. |
| `db/migrate/20261012100300_create_agent_commands.rb` | Очередь команд. |
| `app/models/station_tv_monitor.rb` | Валидации интервалов и bool. |
| `app/models/station_telemetry_snapshot.rb` | Последний station-снимок. |
| `app/models/screen_telemetry_snapshot.rb` | Последний снимок экрана. |
| `app/models/agent_command.rb` | `pending` / `acked`, вложение artifact. |
| `app/domain/agent/config_builder.rb` | Добавляет `tv_monitor` только при наличии записи. |
| `app/domain/agent/record_telemetry.rb` | Идемпотентная запись снимка. |
| `app/domain/agent/artifact_token.rb` | Signed token на 15 минут. |
| `app/domain/agent/store_artifact.rb` | Кладёт байты PUT в Active Storage. |
| `app/domain/agent/commands/issue.rb` | Создаёт pending-команду и `upload_url`. |
| `app/domain/agent/commands/queue.rb` | JSON очереди и ETag. |
| `app/domain/agent/commands/acknowledge.rb` | Ack, в том числе повторный. |
| `app/controllers/api/agent/v1/telemetries_controller.rb` | `POST /api/agent/v1/telemetry`. |
| `app/controllers/api/agent/v1/commands_controller.rb` | `GET /api/agent/v1/commands`. |
| `app/controllers/api/agent/v1/command_results_controller.rb` | `POST /api/agent/v1/command_results`. |
| `app/controllers/api/agent/uploads_controller.rb` | `PUT /api/agent/uploads/:token` без Bearer. |
| `app/controllers/admin/agent_commands_controller.rb` | Постановка команды с экрана. |
| `app/views/admin/stations/_form.html.erb` | Чекбокс и поля `tv_monitor`. |
| `app/views/admin/stations/show.html.erb` | Последний снимок. |
| `app/views/admin/screens/show.html.erb` | Форма команды и последние результаты. |

Ассоциации, на которые опираются следующие задачи:

- `Station#tv_monitor` — `has_one :tv_monitor, class_name: "StationTvMonitor", dependent: :destroy`
- `Station#telemetry_snapshot` — `has_one :telemetry_snapshot, class_name: "StationTelemetrySnapshot", dependent: :destroy`
- `Station#screen_telemetry_snapshots` — `has_many :screen_telemetry_snapshots, dependent: :destroy`
- `Station#agent_commands` — `has_many :agent_commands, dependent: :destroy`
- `Screen#telemetry_snapshot` — `has_one :telemetry_snapshot, class_name: "ScreenTelemetrySnapshot", dependent: :destroy`
- `Screen#agent_commands` — `has_many :agent_commands, dependent: :destroy`

---

### Task 1: Optional `tv_monitor` on agent config

**Files:**
- Create: `db/migrate/20261012100100_create_station_tv_monitors.rb`
- Create: `app/models/station_tv_monitor.rb`
- Create: `spec/models/station_tv_monitor_spec.rb`
- Create: `spec/factories/station_tv_monitors.rb`
- Modify: `app/models/station.rb`
- Modify: `app/domain/agent/config_builder.rb`
- Modify: `spec/domain/agent/config_builder_spec.rb`
- Modify: `spec/requests/api/agent/v1/configs_spec.rb`
- Modify: `db/schema.rb` (через миграцию)

**Interfaces:**
- Consumes: `Agent::ConfigBuilder.call(station:)` уже возвращает Hash с `station_id`, `offline_cache_hours`, `screens`.
- Produces: `Station#tv_monitor` (`StationTvMonitor` или `nil`). Поля `health_interval_seconds` (Integer), `auto_restart_when_not_playing` (Boolean), `telemetry_interval_seconds` (Integer). `ConfigBuilder` добавляет ключ `tv_monitor` только когда ассоциация есть.

- [ ] **Step 1: Write the failing tests**

`spec/models/station_tv_monitor_spec.rb`

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe StationTvMonitor do
  it "rejects a health interval below the station clamp" do
    monitor = build(:station_tv_monitor, health_interval_seconds: 4)

    expect(monitor).not_to be_valid
    expect(monitor.errors[:health_interval_seconds]).to be_present
  end

  it "stores an explicit false auto-restart flag" do
    monitor = create(:station_tv_monitor, auto_restart_when_not_playing: false)

    expect(monitor.reload.auto_restart_when_not_playing).to be(false)
  end
end
```

Добавь в `spec/domain/agent/config_builder_spec.rb` второй пример рядом с существующим:

```ruby
it "omits tv_monitor when the station has no settings row" do
  station = create(:station)

  expect(described_class.call(station:)).not_to have_key(:tv_monitor)
end

it "includes an explicit auto-restart boolean when settings exist" do
  station = create(:station)
  create(:station_tv_monitor, station:, health_interval_seconds: 15,
    auto_restart_when_not_playing: false, telemetry_interval_seconds: 45)

  expect(described_class.call(station:)).to include(
    tv_monitor: {
      health_interval_seconds: 15,
      auto_restart_when_not_playing: false,
      telemetry_interval_seconds: 45
    }
  )
end
```

Добавь в `spec/requests/api/agent/v1/configs_spec.rb`:

```ruby
it "returns tv_monitor only when the station has settings" do
  token = SecureRandom.hex(16)
  station = create(:station)
  station.assign_agent_token!(token)
  create(:station_tv_monitor, station:, health_interval_seconds: 30,
    auto_restart_when_not_playing: true, telemetry_interval_seconds: 60)

  get "/api/agent/v1/config", headers: agent_authorization_headers(token), as: :json

  expect(response).to have_http_status(:ok)
  expect(response.parsed_body["tv_monitor"]).to eq(
    "health_interval_seconds" => 30,
    "auto_restart_when_not_playing" => true,
    "telemetry_interval_seconds" => 60
  )
end
```

Существующий пример `returns this station cache policy and screens` не меняй: он фиксирует JSON без ключа `tv_monitor`.

- [ ] **Step 2: Run the tests and verify they fail**

Run: `bundle exec rspec spec/models/station_tv_monitor_spec.rb spec/domain/agent/config_builder_spec.rb spec/requests/api/agent/v1/configs_spec.rb`

Expected: FAIL. `Factory not registered: "station_tv_monitor"` или `uninitialized constant StationTvMonitor`.

- [ ] **Step 3: Migrate, model, factory, builder**

`db/migrate/20261012100100_create_station_tv_monitors.rb`

```ruby
# frozen_string_literal: true

class CreateStationTvMonitors < ActiveRecord::Migration[8.1]
  def change
    create_table :station_tv_monitors do |t|
      t.references :station, null: false, foreign_key: true, index: { unique: true }
      t.integer :health_interval_seconds, null: false, default: 30
      t.boolean :auto_restart_when_not_playing, null: false, default: true
      t.integer :telemetry_interval_seconds, null: false, default: 60

      t.timestamps
    end
  end
end
```

Run: `bin/rails db:migrate`

`app/models/station_tv_monitor.rb`

```ruby
# frozen_string_literal: true

class StationTvMonitor < ApplicationRecord
  belongs_to :station

  validates :health_interval_seconds,
    numericality: { only_integer: true, greater_than_or_equal_to: 5 }
  validates :telemetry_interval_seconds,
    numericality: { only_integer: true, greater_than_or_equal_to: 5 }
  validates :auto_restart_when_not_playing, inclusion: { in: [ true, false ] }
end
```

Пол 5 секунд совпадает с clamp station для health и не даёт telemetry с нулём.

`spec/factories/station_tv_monitors.rb`

```ruby
# frozen_string_literal: true

FactoryBot.define do
  factory :station_tv_monitor do
    station
    health_interval_seconds { 30 }
    auto_restart_when_not_playing { true }
    telemetry_interval_seconds { 60 }
  end
end
```

В `app/models/station.rb` внутрь класса, сразу после `has_many :playlists, ...`:

```ruby
has_one :tv_monitor, class_name: "StationTvMonitor", dependent: :destroy
```

Замени тело `Agent::ConfigBuilder#call` на:

```ruby
def call
  payload = {
    station_id: station.id,
    offline_cache_hours: station.offline_cache_hours,
    screens: station.screens.order(:id).map { |screen| screen_payload(screen) }
  }
  payload[:tv_monitor] = tv_monitor_payload if station.tv_monitor
  payload
end
```

И добавь private-метод рядом с `screen_payload`:

```ruby
def tv_monitor_payload
  monitor = station.tv_monitor
  {
    health_interval_seconds: monitor.health_interval_seconds,
    auto_restart_when_not_playing: monitor.auto_restart_when_not_playing,
    telemetry_interval_seconds: monitor.telemetry_interval_seconds
  }
end
```

Run: `bundle exec annotaterb models Station StationTvMonitor`

- [ ] **Step 4: Run the tests and RuboCop**

Run: `bundle exec rspec spec/models/station_tv_monitor_spec.rb spec/domain/agent/config_builder_spec.rb spec/requests/api/agent/v1/configs_spec.rb`

Expected: PASS, включая старый пример config без ключа `tv_monitor`.

Run: `bundle exec rubocop app/models/station.rb app/models/station_tv_monitor.rb app/domain/agent/config_builder.rb spec/models/station_tv_monitor_spec.rb spec/factories/station_tv_monitors.rb spec/domain/agent/config_builder_spec.rb spec/requests/api/agent/v1/configs_spec.rb db/migrate/20261012100100_create_station_tv_monitors.rb`

Expected: no offenses.

- [ ] **Step 5: Commit**

```bash
git add db/migrate/20261012100100_create_station_tv_monitors.rb db/schema.rb \
  app/models/station.rb app/models/station_tv_monitor.rb \
  app/domain/agent/config_builder.rb \
  spec/models/station_tv_monitor_spec.rb spec/factories/station_tv_monitors.rb \
  spec/factories/stations.rb \
  spec/domain/agent/config_builder_spec.rb spec/requests/api/agent/v1/configs_spec.rb
git commit -m "$(cat <<'EOF'
feat: send tv_monitor on agent config only when configured

A missing key keeps the station defaults. An empty object would turn auto-restart off.
EOF
)"
```

`spec/factories/stations.rb` добавляй только если annotaterb сам дописал в него schema comment.

---

### Task 2: `POST /api/agent/v1/telemetry`

**Files:**
- Create: `db/migrate/20261012100200_create_telemetry_snapshots.rb`
- Create: `app/models/station_telemetry_snapshot.rb`
- Create: `app/models/screen_telemetry_snapshot.rb`
- Create: `app/domain/agent/record_telemetry.rb`
- Create: `app/controllers/api/agent/v1/telemetries_controller.rb`
- Create: `spec/requests/api/agent/v1/telemetries_spec.rb`
- Modify: `app/models/station.rb`
- Modify: `app/models/screen.rb`
- Modify: `config/routes.rb`
- Modify: `db/schema.rb`

**Interfaces:**
- Consumes: `current_station` из `Api::Agent::V1::BaseController`. `station.screens`.
- Produces:
  - `Agent::RecordTelemetry.call(station:, payload:)` — `payload` это Hash со строковыми ключами `reported_at`, `station`, `screens`. Возвращает `:recorded` или `:stale`. Свежий снимок пишется в `station.telemetry_snapshot` и `ScreenTelemetrySnapshot` по экранам этой station. Более ранний `reported_at` не затирает снимок.
  - `StationTelemetrySnapshot` колонки: `reported_at`, `uptime_seconds`, `package_etag` (string, `""` допустим), `broadcast_ok`, `ignored_screen_ids` (jsonb, массив Integer).
  - `ScreenTelemetrySnapshot` колонки: `screen_id`, `station_id`, `reported_at`, `reachable`, `agent_ok`, `playing`, `url`, `wakefulness`, `stream_port`, `broadcast_clients`, `last_error` (nullable string).
  - `POST /api/agent/v1/telemetry` → 202 без тела, 401 `{ "error": "unauthorized" }`, 422 `{ "error": "invalid_telemetry" }`.

- [ ] **Step 1: Write the failing request spec**

`spec/requests/api/agent/v1/telemetries_spec.rb`

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::Agent::V1::Telemetries", type: :request do
  let(:token) { SecureRandom.hex(16) }
  let(:station) { create(:station) }
  let!(:screen) { create(:screen, station:) }

  before { station.assign_agent_token!(token) }

  def payload(screen_id: screen.id, reported_at: "2026-10-09T11:00:00Z")
    {
      reported_at: reported_at,
      station: {
        uptime_seconds: 3600,
        package_etag: "W/\"pkg\"",
        broadcast_ok: true
      },
      screens: [
        {
          screen_id: screen_id,
          reachable: true,
          agent_ok: true,
          playing: true,
          url: "http://192.168.33.1:8091/",
          wakefulness: "",
          stream_port: 8091,
          broadcast_clients: 0,
          last_error: nil
        }
      ]
    }
  end

  it "returns 401 without a token" do
    post "/api/agent/v1/telemetry", params: payload, as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body).to eq("error" => "unauthorized")
  end

  it "accepts an empty wakefulness and a zero client count" do
    post "/api/agent/v1/telemetry", params: payload, headers: agent_authorization_headers(token), as: :json

    expect(response).to have_http_status(:accepted)
    expect(response.body).to be_empty
    snapshot = station.reload.telemetry_snapshot
    expect(snapshot.package_etag).to eq("W/\"pkg\"")
    expect(snapshot.broadcast_ok).to be(true)
    screen_snapshot = screen.reload.telemetry_snapshot
    expect(screen_snapshot.wakefulness).to eq("")
    expect(screen_snapshot.broadcast_clients).to eq(0)
    expect(screen_snapshot.last_error).to be_nil
    expect(screen_snapshot.playing).to be(true)
  end

  it "keeps the batch when a screen id belongs to another station" do
    other = create(:screen)

    post "/api/agent/v1/telemetry",
      params: payload(screen_id: other.id),
      headers: agent_authorization_headers(token),
      as: :json

    expect(response).to have_http_status(:accepted)
    expect(station.reload.telemetry_snapshot.ignored_screen_ids).to eq([ other.id ])
    expect(other.reload.telemetry_snapshot).to be_nil
    expect(screen.reload.telemetry_snapshot).to be_nil
  end

  it "does not overwrite a newer snapshot with an older reported_at" do
    post "/api/agent/v1/telemetry",
      params: payload(reported_at: "2026-10-09T12:00:00Z"),
      headers: agent_authorization_headers(token),
      as: :json
    post "/api/agent/v1/telemetry",
      params: payload(reported_at: "2026-10-09T11:00:00Z"),
      headers: agent_authorization_headers(token),
      as: :json

    expect(response).to have_http_status(:accepted)
    expect(station.reload.telemetry_snapshot.reported_at.utc.iso8601).to eq("2026-10-09T12:00:00Z")
  end

  it "returns 422 when reported_at is missing" do
    post "/api/agent/v1/telemetry",
      params: payload.except(:reported_at),
      headers: agent_authorization_headers(token),
      as: :json

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body).to eq("error" => "invalid_telemetry")
  end
end
```

- [ ] **Step 2: Run the spec and verify it fails**

Run: `bundle exec rspec spec/requests/api/agent/v1/telemetries_spec.rb`

Expected: FAIL. Маршрут не найден (`RoutingError` / 404) либо `uninitialized constant`.

- [ ] **Step 3: Persist the snapshot and accept the POST**

`db/migrate/20261012100200_create_telemetry_snapshots.rb`

```ruby
# frozen_string_literal: true

class CreateTelemetrySnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :station_telemetry_snapshots do |t|
      t.references :station, null: false, foreign_key: true, index: { unique: true }
      t.datetime :reported_at, null: false
      t.integer :uptime_seconds, null: false
      t.string :package_etag, null: false, default: ""
      t.boolean :broadcast_ok, null: false, default: false
      t.jsonb :ignored_screen_ids, null: false, default: []

      t.timestamps
    end

    create_table :screen_telemetry_snapshots do |t|
      t.references :screen, null: false, foreign_key: true, index: { unique: true }
      t.references :station, null: false, foreign_key: true
      t.datetime :reported_at, null: false
      t.boolean :reachable, null: false, default: false
      t.boolean :agent_ok, null: false, default: false
      t.boolean :playing, null: false, default: false
      t.string :url, null: false, default: ""
      t.string :wakefulness, null: false, default: ""
      t.integer :stream_port, null: false, default: 0
      t.integer :broadcast_clients, null: false, default: 0
      t.string :last_error

      t.timestamps
    end
  end
end
```

Run: `bin/rails db:migrate`

`app/models/station_telemetry_snapshot.rb`

```ruby
# frozen_string_literal: true

class StationTelemetrySnapshot < ApplicationRecord
  belongs_to :station

  validates :reported_at, :uptime_seconds, presence: true
  validates :uptime_seconds, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
```

`app/models/screen_telemetry_snapshot.rb`

```ruby
# frozen_string_literal: true

class ScreenTelemetrySnapshot < ApplicationRecord
  belongs_to :screen
  belongs_to :station

  validates :reported_at, presence: true
  validates :stream_port, :broadcast_clients,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
```

В `Station`, рядом с `has_one :tv_monitor`:

```ruby
has_one :telemetry_snapshot, class_name: "StationTelemetrySnapshot", dependent: :destroy
has_many :screen_telemetry_snapshots, dependent: :destroy
```

В `Screen`, рядом с `belongs_to :station`:

```ruby
has_one :telemetry_snapshot, class_name: "ScreenTelemetrySnapshot", dependent: :destroy
```

`app/domain/agent/record_telemetry.rb`

```ruby
# frozen_string_literal: true

module Agent
  class RecordTelemetry < BaseService
    def initialize(station:, payload:)
      @station = station
      @payload = payload.deep_stringify_keys
    end

    def call
      reported_at = Time.iso8601(payload.fetch("reported_at").to_s)
      existing = station.telemetry_snapshot
      return :stale if existing && existing.reported_at > reported_at

      station_row = payload.fetch("station")
      screen_rows = payload.fetch("screens")
      raise ArgumentError, "screens must be an array" unless screen_rows.is_a?(Array)

      Station.transaction do
        write_station(reported_at, station_row, ignored_ids_for(screen_rows))
        write_screens(reported_at, screen_rows)
      end
      :recorded
    end

    private

    attr_reader :station, :payload

    def write_station(reported_at, row, ignored_ids)
      snapshot = station.telemetry_snapshot || station.build_telemetry_snapshot
      snapshot.update!(
        reported_at: reported_at,
        uptime_seconds: integer!(row.fetch("uptime_seconds")),
        package_etag: row.fetch("package_etag", "").to_s,
        broadcast_ok: boolean!(row.fetch("broadcast_ok")),
        ignored_screen_ids: ignored_ids
      )
    end

    def write_screens(reported_at, rows)
      kept_ids = []
      rows.each do |row|
        screen = station.screens.find_by(id: row.fetch("screen_id"))
        next unless screen

        kept_ids << screen.id
        snapshot = ScreenTelemetrySnapshot.find_or_initialize_by(screen:)
        snapshot.update!(
          station: station,
          reported_at: reported_at,
          reachable: boolean!(row.fetch("reachable")),
          agent_ok: boolean!(row.fetch("agent_ok")),
          playing: boolean!(row.fetch("playing")),
          url: row.fetch("url", "").to_s,
          wakefulness: row.fetch("wakefulness", "").to_s,
          stream_port: integer!(row.fetch("stream_port", 0)),
          broadcast_clients: integer!(row.fetch("broadcast_clients", 0)),
          last_error: nullable_string(row["last_error"])
        )
      end
      station.screen_telemetry_snapshots.where.not(screen_id: kept_ids).delete_all
    end

    def ignored_ids_for(rows)
      known = station.screens.where(id: rows.map { |row| row["screen_id"] }).ids
      rows.filter_map { |row| Integer(row.fetch("screen_id")) unless known.include?(Integer(row.fetch("screen_id"))) }
    end

    def boolean!(value)
      return value if value == true || value == false

      raise ArgumentError, "expected boolean"
    end

    def integer!(value)
      Integer(value)
    end

    def nullable_string(value)
      return if value.nil?

      value.to_s
    end
  end
end
```

`app/controllers/api/agent/v1/telemetries_controller.rb`

```ruby
# frozen_string_literal: true

module Api
  module Agent
    module V1
      class TelemetriesController < BaseController
        def create
          ::Agent::RecordTelemetry.call(station: current_station, payload: telemetry_payload)
          head :accepted
        rescue ArgumentError, KeyError, ActionController::ParameterMissing, TypeError
          render json: { error: "invalid_telemetry" }, status: :unprocessable_content
        end

        private

        def telemetry_payload
          params.expect(
            :reported_at,
            station: %i[uptime_seconds package_etag broadcast_ok],
            screens: [ %i[
              screen_id reachable agent_ok playing url wakefulness
              stream_port broadcast_clients last_error
            ] ]
          ).to_h
        end
      end
    end
  end
end
```

`params.expect` в Rails 8 требует присутствия перечисленных ключей верхнего уровня. Пустая строка `wakefulness` проходит permit. `last_error: null` остаётся `nil`.

В `config/routes.rb` внутри `namespace :v1` после `post :play_events`:

```ruby
post :telemetry, to: "telemetries#create"
```

`find_by`, не `find`: `BaseController` превращает `RecordNotFound` в 404, а чужой экран не должен ронять батч.

Run: `bundle exec annotaterb models Station Screen StationTelemetrySnapshot ScreenTelemetrySnapshot`

- [ ] **Step 4: Run the spec and RuboCop**

Run: `bundle exec rspec spec/requests/api/agent/v1/telemetries_spec.rb spec/requests/api/agent/v1/configs_spec.rb spec/requests/api/agent/v1/play_events_spec.rb`

Expected: PASS. Старые config и play_events не красные.

Run: `bundle exec rubocop app/models/station.rb app/models/screen.rb app/models/station_telemetry_snapshot.rb app/models/screen_telemetry_snapshot.rb app/domain/agent/record_telemetry.rb app/controllers/api/agent/v1/telemetries_controller.rb spec/requests/api/agent/v1/telemetries_spec.rb config/routes.rb db/migrate/20261012100200_create_telemetry_snapshots.rb`

Expected: no offenses.

Если `params.expect` с массивом объектов падает в рантайме с `ActionController::ParameterMissing` или отдаёт пустые screens, замени `telemetry_payload` на permit и оставь те же ключи:

```ruby
def telemetry_payload
  params.require(:reported_at)
  params.require(:station)
  params.require(:screens)
  params.permit(
    :reported_at,
    station: %i[uptime_seconds package_etag broadcast_ok],
    screens: %i[screen_id reachable agent_ok playing url wakefulness stream_port broadcast_clients last_error]
  ).to_h
end
```

Этот fallback допустим только если пример с пустым `wakefulness` зелёный. Не меняй контракт ответа.

- [ ] **Step 5: Commit**

```bash
git add db/migrate/20261012100200_create_telemetry_snapshots.rb db/schema.rb \
  app/models/station.rb app/models/screen.rb \
  app/models/station_telemetry_snapshot.rb app/models/screen_telemetry_snapshot.rb \
  app/domain/agent/record_telemetry.rb \
  app/controllers/api/agent/v1/telemetries_controller.rb \
  config/routes.rb spec/requests/api/agent/v1/telemetries_spec.rb \
  spec/factories/stations.rb spec/factories/screens.rb
git commit -m "$(cat <<'EOF'
feat: accept agent telemetry snapshots

Store the latest reading per station and screen. A foreign screen id stays in the snapshot instead of failing the batch.
EOF
)"
```

---

### Task 3: Issue a pending per-screen command

**Files:**
- Create: `db/migrate/20261012100300_create_agent_commands.rb`
- Create: `app/models/agent_command.rb`
- Create: `app/domain/agent/artifact_token.rb`
- Create: `app/domain/agent/commands/issue.rb`
- Create: `spec/factories/agent_commands.rb`
- Create: `spec/domain/agent/commands/issue_spec.rb`
- Modify: `app/models/station.rb`
- Modify: `app/models/screen.rb`
- Modify: `db/schema.rb`

**Interfaces:**
- Consumes: `station.screens`.
- Produces:
  - `AgentCommand` с `public_id` (string, unique), `command_type` (string), `params` (jsonb Hash), `issued_at` (Time), `status` enum `pending` / `acked` (строки `"pending"` и `"acked"`), `succeeded` (boolean, nullable), `result_error` (string, nullable), `finished_at` (datetime, nullable). `has_one_attached :artifact`. Скоуп `.pending`. `expects_upload?` истинно для `screenshot` и `record`.
  - `AgentCommand::TYPES` = `%w[start_stream restart_stream stop wake sleep screenshot record ensure_app install_apk]`.
  - `Agent::ArtifactToken.generate(public_id)` → String. `Agent::ArtifactToken.verify!(token)` → `public_id` или `ActiveSupport::MessageVerifier::InvalidSignature`. TTL `15.minutes`. Purpose `:agent_artifact_upload`.
  - `Agent::Commands::Issue.call(screen:, type:, params:, url_options:)` → `AgentCommand` в статусе `pending`. `params` — Hash (`url`, `buffer_ms`, `seconds`). `url_options` — Hash с ключами `:host`, `:protocol`, опционально `:port`. Для `screenshot`/`record` в `command.params["upload_url"]` абсолютный URL `api_agent_upload_url`. `Issue::Error#code` — строка: `unknown_type`, `buffer_ms_invalid`, `seconds_out_of_range`, `url_must_be_https`, `missing_host`.

- [ ] **Step 1: Write the failing service spec**

`spec/domain/agent/commands/issue_spec.rb`

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agent::Commands::Issue do
  let(:screen) { create(:screen) }
  let(:url_options) { { host: "hub.example", protocol: "https" } }

  it "queues a restart_stream with an empty params object" do
    command = described_class.call(screen:, type: "restart_stream", params: {}, url_options:)

    expect(command).to be_pending
    expect(command.public_id).to start_with("cmd_")
    expect(command.screen).to eq(screen)
    expect(command.station).to eq(screen.station)
    expect(command.params).to eq({})
    expect(command.command_type).to eq("restart_stream")
    expect(command.issued_at).to be_present
  end

  it "puts a signed upload url on screenshot and ignores a caller-supplied one" do
    command = described_class.call(
      screen:,
      type: "screenshot",
      params: { "upload_url" => "https://evil.example/put" },
      url_options:
    )

    expect(command.params.keys).to eq([ "upload_url" ])
    expect(command.params["upload_url"]).to start_with("https://hub.example/api/agent/uploads/")
    expect(command.params["upload_url"]).not_to include("evil.example")
    token = command.params["upload_url"].split("/").last
    expect(Agent::ArtifactToken.verify!(CGI.unescape(token))).to eq(command.public_id)
  end

  it "defaults record length to 10 seconds and keeps an explicit length" do
    command = described_class.call(screen:, type: "record", params: { seconds: 15 }, url_options:)

    expect(command.params["seconds"]).to eq(15)
    expect(command.params["upload_url"]).to be_present
  end

  it "rejects a record longer than 120 seconds" do
    expect {
      described_class.call(screen:, type: "record", params: { seconds: 121 }, url_options:)
    }.to raise_error(described_class::Error) { |error| expect(error.code).to eq("seconds_out_of_range") }
  end

  it "rejects an install_apk url that is not https" do
    expect {
      described_class.call(screen:, type: "install_apk", params: { url: "http://files.example/app.apk" }, url_options:)
    }.to raise_error(described_class::Error) { |error| expect(error.code).to eq("url_must_be_https") }
  end

  it "rejects an unknown type" do
    expect {
      described_class.call(screen:, type: "reboot_station", params: {}, url_options:)
    }.to raise_error(described_class::Error) { |error| expect(error.code).to eq("unknown_type") }
  end

  it "refuses to mint an upload url without a host" do
    expect {
      described_class.call(screen:, type: "screenshot", params: {}, url_options: {})
    }.to raise_error(described_class::Error) { |error| expect(error.code).to eq("missing_host") }
  end
end
```

- [ ] **Step 2: Run the spec and verify it fails**

Run: `bundle exec rspec spec/domain/agent/commands/issue_spec.rb`

Expected: FAIL. `uninitialized constant Agent::Commands::Issue`.

- [ ] **Step 3: Model, token, issuer**

`db/migrate/20261012100300_create_agent_commands.rb`

```ruby
# frozen_string_literal: true

class CreateAgentCommands < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_commands do |t|
      t.references :station, null: false, foreign_key: true
      t.references :screen, null: false, foreign_key: true
      t.string :public_id, null: false
      t.string :command_type, null: false
      t.jsonb :params, null: false, default: {}
      t.datetime :issued_at, null: false
      t.string :status, null: false, default: "pending"
      t.boolean :succeeded
      t.string :result_error
      t.datetime :finished_at

      t.timestamps
    end

    add_index :agent_commands, :public_id, unique: true
    add_index :agent_commands, [ :station_id, :status ]
  end
end
```

Run: `bin/rails db:migrate`

`app/models/agent_command.rb`

```ruby
# frozen_string_literal: true

class AgentCommand < ApplicationRecord
  TYPES = %w[start_stream restart_stream stop wake sleep screenshot record ensure_app install_apk].freeze
  UPLOAD_TYPES = %w[screenshot record].freeze

  belongs_to :station
  belongs_to :screen

  has_one_attached :artifact

  enum :status, { pending: "pending", acked: "acked" }, default: :pending, validate: true

  validates :public_id, :command_type, :issued_at, presence: true
  validates :public_id, uniqueness: true
  validates :command_type, inclusion: { in: TYPES }
  validate :screen_belongs_to_station

  def expects_upload?
    UPLOAD_TYPES.include?(command_type)
  end

  private

  def screen_belongs_to_station
    return if screen.blank? || station.blank?
    return if screen.station_id == station_id

    errors.add(:screen, :invalid)
  end
end
```

В `Station`:

```ruby
has_many :agent_commands, dependent: :destroy
```

В `Screen`:

```ruby
has_many :agent_commands, dependent: :destroy
```

`spec/factories/agent_commands.rb`

```ruby
# frozen_string_literal: true

FactoryBot.define do
  factory :agent_command do
    station
    screen { association :screen, station: station }
    sequence(:public_id) { |n| "cmd_factory_#{n}" }
    command_type { "restart_stream" }
    params { {} }
    issued_at { Time.utc(2026, 10, 9, 11, 1, 0) }
    status { "pending" }
  end
end
```

`app/domain/agent/artifact_token.rb`

```ruby
# frozen_string_literal: true

module Agent
  class ArtifactToken
    PURPOSE = :agent_artifact_upload
    TTL = 15.minutes

    def self.generate(public_id)
      verifier.generate(public_id, expires_in: TTL, purpose: PURPOSE)
    end

    def self.verify!(token)
      verifier.verify(token, purpose: PURPOSE)
    end

    def self.verifier
      Rails.application.message_verifier(PURPOSE)
    end
  end
end
```

`app/domain/agent/commands/issue.rb`

```ruby
# frozen_string_literal: true

module Agent
  module Commands
    class Issue < BaseService
      class Error < StandardError
        attr_reader :code

        def initialize(code)
          @code = code
          super(code)
        end
      end

      NO_PARAM_TYPES = %w[restart_stream stop wake sleep ensure_app].freeze

      def initialize(screen:, type:, params:, url_options:)
        @screen = screen
        @type = type.to_s
        @params = params.to_h.deep_stringify_keys
        @url_options = url_options.to_h.symbolize_keys
      end

      def call
        raise Error, "unknown_type" unless AgentCommand::TYPES.include?(type)

        AgentCommand.transaction do
          command = screen.station.agent_commands.create!(
            screen: screen,
            public_id: "cmd_#{SecureRandom.uuid}",
            command_type: type,
            params: normalized_params,
            issued_at: Time.current,
            status: "pending"
          )
          attach_upload_url(command)
          command
        end
      end

      private

      attr_reader :screen, :type, :params, :url_options

      def normalized_params
        case type
        when "start_stream" then start_stream_params
        when "screenshot" then {}
        when "record" then { "seconds" => record_seconds }
        when "install_apk" then install_apk_params
        when *NO_PARAM_TYPES then {}
        else
          raise Error, "unknown_type"
        end
      end

      def start_stream_params
        out = {}
        url = params["url"].to_s.strip
        out["url"] = url if url.present?
        if params["buffer_ms"].present?
          buffer = parse_integer(params["buffer_ms"], "buffer_ms_invalid")
          raise Error, "buffer_ms_invalid" if buffer.negative?

          out["buffer_ms"] = buffer
        end
        out
      end

      def record_seconds
        raw = params["seconds"]
        seconds = raw.present? ? parse_integer(raw, "seconds_out_of_range") : 10
        raise Error, "seconds_out_of_range" unless seconds.between?(1, 120)

        seconds
      end

      def install_apk_params
        url = params["url"].to_s.strip
        return {} if url.blank?
        raise Error, "url_must_be_https" unless url.start_with?("https://")

        { "url" => url }
      end

      def attach_upload_url(command)
        return unless command.expects_upload?
        raise Error, "missing_host" if url_options[:host].blank?

        command.update!(params: command.params.merge("upload_url" => upload_url(command)))
      end

      def upload_url(command)
        Rails.application.routes.url_helpers.api_agent_upload_url(
          token: ArtifactToken.generate(command.public_id),
          **url_options.compact
        )
      end

      def parse_integer(value, code)
        Integer(value)
      rescue ArgumentError, TypeError
        raise Error, code
      end
    end
  end
end
```

Маршрут `api_agent_upload_url` появится в Task 4. Пока spec проверяет только префикс строки, которую helper соберёт после Task 4. Чтобы Task 3 был зелёным до маршрута, в `config/routes.rb` внутри `namespace :agent` **перед** `namespace :v1` добавь заглушку маршрута (контроллер будет в Task 4):

```ruby
put "uploads/:token", to: "uploads#update", as: :upload
```

Без этого `api_agent_upload_url` поднимет `NoMethodError` в спеке Issue. Контроллер в этом таске не создавай: спека Issue не делает HTTP PUT.

Run: `bundle exec annotaterb models AgentCommand Station Screen`

- [ ] **Step 4: Run the spec and RuboCop**

Run: `bundle exec rspec spec/domain/agent/commands/issue_spec.rb`

Expected: PASS. 7 examples.

Run: `bundle exec rubocop app/models/agent_command.rb app/models/station.rb app/models/screen.rb app/domain/agent/artifact_token.rb app/domain/agent/commands/issue.rb spec/domain/agent/commands/issue_spec.rb spec/factories/agent_commands.rb db/migrate/20261012100300_create_agent_commands.rb config/routes.rb`

Expected: no offenses.

- [ ] **Step 5: Commit**

```bash
git add db/migrate/20261012100300_create_agent_commands.rb db/schema.rb \
  app/models/agent_command.rb app/models/station.rb app/models/screen.rb \
  app/domain/agent/artifact_token.rb app/domain/agent/commands/issue.rb \
  spec/factories/agent_commands.rb spec/domain/agent/commands/issue_spec.rb \
  spec/factories/stations.rb spec/factories/screens.rb config/routes.rb
git commit -m "$(cat <<'EOF'
feat: queue per-screen agent commands

Screenshot and record always get a hub-signed upload URL. Caller-supplied upload URLs are discarded.
EOF
)"
```

---

### Task 4: `PUT` artifact upload

**Files:**
- Create: `app/domain/agent/store_artifact.rb`
- Create: `app/controllers/api/agent/uploads_controller.rb`
- Create: `spec/requests/api/agent/uploads_spec.rb`
- Modify: `config/routes.rb` только если строка `put "uploads/:token"` из Task 3 отсутствует

**Interfaces:**
- Consumes: `Agent::ArtifactToken.verify!`, `AgentCommand#expects_upload?`, `AgentCommand#artifact`.
- Produces: `Agent::StoreArtifact.call(command:, io:, content_type:)` заменяет `command.artifact`. `MAX_BYTES = 100.megabytes`. Ожидаемые типы: `screenshot` → `image/png`, `record` → `video/mp4`. `PUT /api/agent/uploads/:token` без Bearer: 204 при успехе, 403 при плохом токене, 415 при чужом Content-Type, 422 `{ "error": "empty_body" }` при пустом теле, 413 при теле больше `MAX_BYTES`. Повторный PUT заменяет вложение и тоже отвечает 204.

- [ ] **Step 1: Write the failing request spec**

`spec/requests/api/agent/uploads_spec.rb`

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::Agent::Uploads", type: :request do
  let(:command) { create(:agent_command, command_type: "screenshot", params: {}) }

  def put_artifact(token:, body:, content_type:)
    put "/api/agent/uploads/#{token}",
      params: body,
      headers: { "CONTENT_TYPE" => content_type }
  end

  it "stores a png without a bearer token" do
    token = Agent::ArtifactToken.generate(command.public_id)

    put_artifact(token:, body: "png-bytes", content_type: "image/png")

    expect(response).to have_http_status(:no_content)
    expect(command.reload.artifact.download).to eq("png-bytes")
    expect(command.artifact.content_type).to eq("image/png")
    expect(command.artifact.filename.to_s).to eq("screenshot.png")
  end

  it "replaces the blob when the station retries the put" do
    token = Agent::ArtifactToken.generate(command.public_id)
    put_artifact(token:, body: "first", content_type: "image/png")
    put_artifact(token:, body: "second", content_type: "image/png")

    expect(response).to have_http_status(:no_content)
    expect(command.reload.artifact.download).to eq("second")
  end

  it "returns 403 for a bad token and does not use 401" do
    put_artifact(token: "not-a-token", body: "png-bytes", content_type: "image/png")

    expect(response).to have_http_status(:forbidden)
    expect(response).not_to have_http_status(:unauthorized)
  end

  it "returns 415 when the content type does not match the command" do
    token = Agent::ArtifactToken.generate(command.public_id)

    put_artifact(token:, body: "png-bytes", content_type: "text/plain")

    expect(response).to have_http_status(:unsupported_media_type)
    expect(command.reload.artifact).not_to be_attached
  end

  it "returns 422 for an empty body" do
    token = Agent::ArtifactToken.generate(command.public_id)

    put_artifact(token:, body: "", content_type: "image/png")

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body).to eq("error" => "empty_body")
  end

  it "stores an mp4 for a record command" do
    record = create(:agent_command, command_type: "record", params: { "seconds" => 15 })
    token = Agent::ArtifactToken.generate(record.public_id)

    put_artifact(token:, body: "mp4-bytes", content_type: "video/mp4")

    expect(response).to have_http_status(:no_content)
    expect(record.reload.artifact.download).to eq("mp4-bytes")
    expect(record.artifact.filename.to_s).to eq("record.mp4")
    expect(record.artifact.content_type).to eq("video/mp4")
  end
end
```

Строка `params` при `CONTENT_TYPE` не из семейства form становится сырым телом. Контроллер читает его через `request.raw_post`. Не клади байты в заголовок.

- [ ] **Step 2: Run the spec and verify it fails**

Run: `bundle exec rspec spec/requests/api/agent/uploads_spec.rb`

Expected: FAIL. `uninitialized constant Api::Agent::UploadsController`.

- [ ] **Step 3: Store the bytes**

`app/domain/agent/store_artifact.rb`

```ruby
# frozen_string_literal: true

module Agent
  class StoreArtifact < BaseService
    MAX_BYTES = 100.megabytes
    CONTENT_TYPES = {
      "screenshot" => "image/png",
      "record" => "video/mp4"
    }.freeze
    FILENAMES = {
      "screenshot" => "screenshot.png",
      "record" => "record.mp4"
    }.freeze

    def initialize(command:, io:, content_type:)
      @command = command
      @io = io
      @content_type = content_type
    end

    def call
      command.artifact.attach(
        io: io,
        filename: FILENAMES.fetch(command.command_type),
        content_type: content_type
      )
      command.artifact.blob
    end

    private

    attr_reader :command, :io, :content_type
  end
end
```

`app/controllers/api/agent/uploads_controller.rb`

```ruby
# frozen_string_literal: true

module Api
  module Agent
    class UploadsController < ActionController::API
      def update
        command = AgentCommand.find_by!(public_id: ::Agent::ArtifactToken.verify!(params[:token]))
        return head :unprocessable_content unless command.expects_upload?

        body = request.raw_post.to_s
        return render json: { error: "empty_body" }, status: :unprocessable_content if body.empty?
        return head :content_too_large if body.bytesize > ::Agent::StoreArtifact::MAX_BYTES

        expected = ::Agent::StoreArtifact::CONTENT_TYPES.fetch(command.command_type)
        return head :unsupported_media_type unless request.media_type == expected

        ::Agent::StoreArtifact.call(command:, io: StringIO.new(body), content_type: expected)
        head :no_content
      rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
        head :forbidden
      end
    end
  end
end
```

Контроллер наследует `ActionController::API`, не `V1::BaseController`, поэтому Bearer не проверяется. 403, не 401.

Убедись, что в `config/routes.rb` есть:

```ruby
namespace :api do
  namespace :agent do
    put "uploads/:token", to: "uploads#update", as: :upload
    namespace :v1 do
      # существующие config, package, play_events и telemetry
    end
  end
end
```

- [ ] **Step 4: Run the specs and RuboCop**

Run: `bundle exec rspec spec/requests/api/agent/uploads_spec.rb spec/domain/agent/commands/issue_spec.rb`

Expected: PASS.

Run: `bundle exec rubocop app/domain/agent/store_artifact.rb app/controllers/api/agent/uploads_controller.rb spec/requests/api/agent/uploads_spec.rb`

Expected: no offenses.

- [ ] **Step 5: Commit**

```bash
git add app/domain/agent/store_artifact.rb app/controllers/api/agent/uploads_controller.rb \
  spec/requests/api/agent/uploads_spec.rb config/routes.rb
git commit -m "$(cat <<'EOF'
feat: accept screenshot and record uploads on a signed URL

The station PUTs bytes without its bearer token. A bad token is 403 so it does not look like an agent-auth failure.
EOF
)"
```

---

### Task 5: `GET /api/agent/v1/commands`

**Files:**
- Create: `app/domain/agent/commands/queue.rb`
- Create: `app/controllers/api/agent/v1/commands_controller.rb`
- Create: `spec/requests/api/agent/v1/commands_spec.rb`
- Modify: `config/routes.rb`

**Interfaces:**
- Consumes: `AgentCommand.pending`, `public_id`, `screen_id`, `command_type`, `params`, `issued_at`. `current_station`.
- Produces: `Agent::Commands::Queue.call(station:)` → Array of Hash с ключами `id`, `screen_id`, `type`, `params`, `issued_at` (String UTC iso8601). Только `pending` этой station, порядок `issued_at asc, id asc`. `Agent::Commands::Queue.etag(station:)` → strong ETag, quoted hex SHA256 от `public_id@issued_at` каждой pending-команды, соединённых `\n`. `GET /api/agent/v1/commands`: 200 `{ "commands": [...] }`, заголовок `ETag`. Совпавший `If-None-Match` → 304 и пустое тело. Пустой заголовок не даёт 304. 401 как у config.

- [ ] **Step 1: Write the failing request spec**

`spec/requests/api/agent/v1/commands_spec.rb`

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::Agent::V1::Commands", type: :request do
  let(:token) { SecureRandom.hex(16) }
  let(:station) { create(:station) }
  let(:screen) { create(:screen, station:) }

  before { station.assign_agent_token!(token) }

  it "returns 401 for an invalid token" do
    get "/api/agent/v1/commands", headers: agent_authorization_headers("nope"), as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body).to eq("error" => "unauthorized")
  end

  it "returns an empty queue" do
    get "/api/agent/v1/commands", headers: agent_authorization_headers(token), as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq("commands" => [])
    expect(response.headers["ETag"]).to be_present
  end

  it "returns pending commands for this station only" do
    command = create(:agent_command, station:, screen:, public_id: "cmd_restart_1",
      command_type: "restart_stream", params: {}, issued_at: Time.utc(2026, 10, 9, 11, 1, 0))
    create(:agent_command, public_id: "cmd_other_station")
    create(:agent_command, station:, screen:, public_id: "cmd_done", status: "acked",
      succeeded: true, finished_at: Time.utc(2026, 10, 9, 11, 2, 0))

    get "/api/agent/v1/commands", headers: agent_authorization_headers(token), as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq(
      "commands" => [
        {
          "id" => command.public_id,
          "screen_id" => screen.id,
          "type" => "restart_stream",
          "params" => {},
          "issued_at" => "2026-10-09T11:01:00Z"
        }
      ]
    )
  end

  it "returns 304 when If-None-Match repeats the queue etag" do
    get "/api/agent/v1/commands", headers: agent_authorization_headers(token), as: :json
    etag = response.headers["ETag"]

    get "/api/agent/v1/commands",
      headers: agent_authorization_headers(token).merge("If-None-Match" => etag)

    expect(response).to have_http_status(:not_modified)
    expect(response.body).to be_empty
  end

  it "returns 200 when If-None-Match is empty even if the queue is unchanged" do
    create(:agent_command, station:, screen:, public_id: "cmd_visible")

    get "/api/agent/v1/commands",
      headers: agent_authorization_headers(token).merge("If-None-Match" => ""),
      as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["commands"].map { |row| row["id"] }).to eq([ "cmd_visible" ])
  end
end
```

- [ ] **Step 2: Run the spec and verify it fails**

Run: `bundle exec rspec spec/requests/api/agent/v1/commands_spec.rb`

Expected: FAIL. Нет маршрута или контроллера.

- [ ] **Step 3: Queue reader and controller**

`app/domain/agent/commands/queue.rb`

```ruby
# frozen_string_literal: true

module Agent
  module Commands
    class Queue < BaseService
      def self.etag(station:)
        body = pending(station).map { |command| "#{command.public_id}@#{command.issued_at.utc.iso8601}" }.join("\n")
        %("#{Digest::SHA256.hexdigest(body)}")
      end

      def self.pending(station)
        station.agent_commands.pending.order(:issued_at, :id)
      end

      def initialize(station:)
        @station = station
      end

      def call
        self.class.pending(station).map { |command| payload(command) }
      end

      private

      attr_reader :station

      def payload(command)
        {
          id: command.public_id,
          screen_id: command.screen_id,
          type: command.command_type,
          params: command.params,
          issued_at: command.issued_at.utc.iso8601
        }
      end
    end
  end
end
```

`app/controllers/api/agent/v1/commands_controller.rb`

```ruby
# frozen_string_literal: true

module Api
  module Agent
    module V1
      class CommandsController < BaseController
        def index
          etag = ::Agent::Commands::Queue.etag(station: current_station)
          response.headers["ETag"] = etag
          if none_match?(etag)
            head :not_modified
            return
          end

          render json: { commands: ::Agent::Commands::Queue.call(station: current_station) }
        end

        private

        def none_match?(etag)
          header = request.headers["If-None-Match"].to_s
          return false if header.blank?

          header.split(",").map(&:strip).any? { |candidate| candidate == etag || candidate == "W/#{etag}" }
        end
      end
    end
  end
end
```

В `namespace :v1` routes:

```ruby
get :commands, to: "commands#index"
```

Не используй `stale?` / `fresh_when`: Rack сравнивает weak etag и может отдать 304 на непустую очередь, которую текущий station примет за пустую. Сравнение строки выше отдаёт 304 только при точном совпадении.

- [ ] **Step 4: Run the spec and RuboCop**

Run: `bundle exec rspec spec/requests/api/agent/v1/commands_spec.rb`

Expected: PASS. 5 examples.

Run: `bundle exec rubocop app/domain/agent/commands/queue.rb app/controllers/api/agent/v1/commands_controller.rb spec/requests/api/agent/v1/commands_spec.rb config/routes.rb`

Expected: no offenses.

- [ ] **Step 5: Commit**

```bash
git add app/domain/agent/commands/queue.rb app/controllers/api/agent/v1/commands_controller.rb \
  spec/requests/api/agent/v1/commands_spec.rb config/routes.rb
git commit -m "$(cat <<'EOF'
feat: list pending agent commands

304 is reserved for an exact ETag match. A blank If-None-Match still returns the queue, matching the current station poll.
EOF
)"
```

---

### Task 6: `POST /api/agent/v1/command_results`

**Files:**
- Create: `app/domain/agent/commands/acknowledge.rb`
- Create: `app/controllers/api/agent/v1/command_results_controller.rb`
- Create: `spec/requests/api/agent/v1/command_results_spec.rb`
- Modify: `config/routes.rb`

**Interfaces:**
- Consumes: `station.agent_commands.find_by(public_id:)`, колонки `status`, `succeeded`, `result_error`, `finished_at`.
- Produces: `Agent::Commands::Acknowledge.call(station:, results:)` → `nil`. `results` — Array of Hash со строковыми ключами `command_id`, `ok` (true/false), `error` (String или nil), `finished_at` (ISO8601). Неизвестный id и id другой station пропускаются. Повторный вызов по уже `acked` команде не меняет первую запись `finished_at` и не поднимает ошибку. `Acknowledge::Invalid` с `code` `"invalid_result"`, если нет `command_id`, `ok` не boolean, `finished_at` не парсится, или `error` не String и не nil. `POST /api/agent/v1/command_results` → 200 пустое тело, 401, 422 `{ "error": "invalid_result" }`.

- [ ] **Step 1: Write the failing request spec**

`spec/requests/api/agent/v1/command_results_spec.rb`

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::Agent::V1::CommandResults", type: :request do
  let(:token) { SecureRandom.hex(16) }
  let(:station) { create(:station) }
  let(:screen) { create(:screen, station:) }

  before { station.assign_agent_token!(token) }

  def post_results(results, headers: agent_authorization_headers(token))
    post "/api/agent/v1/command_results", params: { results: results }, headers: headers, as: :json
  end

  it "returns 401 without a token" do
    post_results([], headers: {})

    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body).to eq("error" => "unauthorized")
  end

  it "acks a command and drops it from the queue" do
    command = create(:agent_command, station:, screen:, public_id: "cmd_restart_1")

    post_results([
      { command_id: "cmd_restart_1", ok: true, error: nil, finished_at: "2026-10-09T11:01:02Z" }
    ])

    expect(response).to have_http_status(:ok)
    expect(response.body).to be_empty
    command.reload
    expect(command).to be_acked
    expect(command.succeeded).to be(true)
    expect(command.result_error).to be_nil
    expect(command.finished_at.utc.iso8601).to eq("2026-10-09T11:01:02Z")

    get "/api/agent/v1/commands", headers: agent_authorization_headers(token), as: :json
    expect(response.parsed_body).to eq("commands" => [])
  end

  it "treats already_done as a successful ack" do
    command = create(:agent_command, station:, screen:, public_id: "cmd_done_locally")

    post_results([
      { command_id: "cmd_done_locally", ok: true, error: "already_done", finished_at: "2026-10-09T11:01:03Z" }
    ])

    expect(response).to have_http_status(:ok)
    expect(command.reload).to be_acked
    expect(command.succeeded).to be(true)
    expect(command.result_error).to eq("already_done")
  end

  it "acks a failed screenshot and removes it from pending" do
    command = create(:agent_command, station:, screen:, public_id: "cmd_bad",
      command_type: "screenshot", params: {})

    post_results([
      { command_id: "cmd_bad", ok: false, error: "missing_upload_url", finished_at: "2026-10-09T11:01:03Z" }
    ])

    expect(response).to have_http_status(:ok)
    expect(command.reload).to be_acked
    expect(command.succeeded).to be(false)
    expect(command.result_error).to eq("missing_upload_url")
  end

  it "returns 200 for an unknown command id" do
    post_results([
      { command_id: "cmd_missing", ok: true, error: nil, finished_at: "2026-10-09T11:01:02Z" }
    ])

    expect(response).to have_http_status(:ok)
    expect(response).not_to have_http_status(:not_found)
  end

  it "does not ack another station command" do
    foreign = create(:agent_command, public_id: "cmd_foreign")

    post_results([
      { command_id: "cmd_foreign", ok: true, error: nil, finished_at: "2026-10-09T11:01:02Z" }
    ])

    expect(response).to have_http_status(:ok)
    expect(foreign.reload).to be_pending
  end

  it "returns 200 again for the same command id" do
    create(:agent_command, station:, screen:, public_id: "cmd_twice")
    body = [ { command_id: "cmd_twice", ok: true, error: nil, finished_at: "2026-10-09T11:01:02Z" } ]

    post_results(body)
    post_results(body)

    expect(response).to have_http_status(:ok)
    expect(AgentCommand.find_by!(public_id: "cmd_twice").finished_at.utc.iso8601).to eq("2026-10-09T11:01:02Z")
  end

  it "returns 422 when finished_at is not a timestamp" do
    create(:agent_command, station:, screen:, public_id: "cmd_bad_time")

    post_results([
      { command_id: "cmd_bad_time", ok: true, error: nil, finished_at: "yesterday" }
    ])

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body).to eq("error" => "invalid_result")
    expect(AgentCommand.find_by!(public_id: "cmd_bad_time")).to be_pending
  end
end
```

- [ ] **Step 2: Run the spec and verify it fails**

Run: `bundle exec rspec spec/requests/api/agent/v1/command_results_spec.rb`

Expected: FAIL. Нет маршрута.

- [ ] **Step 3: Acknowledge results**

`app/domain/agent/commands/acknowledge.rb`

```ruby
# frozen_string_literal: true

module Agent
  module Commands
    class Acknowledge < BaseService
      class Invalid < StandardError
        attr_reader :code

        def initialize(code = "invalid_result")
          @code = code
          super(code)
        end
      end

      def initialize(station:, results:)
        @station = station
        @results = results
      end

      def call
        rows = normalize
        AgentCommand.transaction do
          rows.each { |row| apply(row) }
        end
        nil
      end

      private

      attr_reader :station, :results

      def normalize
        Array(results).map { |result| normalize_row(result.to_h.deep_stringify_keys) }
      end

      def normalize_row(data)
        raise Invalid if data["command_id"].blank?
        raise Invalid unless data["ok"] == true || data["ok"] == false
        raise Invalid unless data["error"].nil? || data["error"].is_a?(String)

        finished_at = Time.iso8601(data["finished_at"].to_s)
        {
          "command_id" => data["command_id"],
          "ok" => data["ok"],
          "error" => data["error"],
          "finished_at" => finished_at
        }
      rescue ArgumentError
        raise Invalid
      end

      def apply(row)
        command = station.agent_commands.find_by(public_id: row["command_id"])
        return if command.nil?
        return if command.acked?

        command.update!(
          status: "acked",
          succeeded: row["ok"],
          result_error: row["error"],
          finished_at: row["finished_at"]
        )
      end
    end
  end
end
```

`app/controllers/api/agent/v1/command_results_controller.rb`

```ruby
# frozen_string_literal: true

module Api
  module Agent
    module V1
      class CommandResultsController < BaseController
        def create
          ::Agent::Commands::Acknowledge.call(station: current_station, results: result_rows)
          head :ok
        rescue ::Agent::Commands::Acknowledge::Invalid, ActionController::ParameterMissing
          render json: { error: "invalid_result" }, status: :unprocessable_content
        end

        private

        def result_rows
          permitted = params.expect(results: [ [ :command_id, :ok, :error, :finished_at ] ])
          permitted[:results].map(&:to_h)
        end
      end
    end
  end
end
```

Если `params.expect` на массиве не отдаёт `ok: false`, перейди на:

```ruby
def result_rows
  rows = params.require(:results)
  rows.map do |row|
    row.permit(:command_id, :ok, :error, :finished_at).to_h
  end
end
```

Проверка: пример с `ok: false` и `error: "missing_upload_url"` остаётся зелёным. `false` не должен превращаться в `nil`.

В `namespace :v1` routes:

```ruby
post :command_results, to: "command_results#create"
```

- [ ] **Step 4: Run the specs and RuboCop**

Run: `bundle exec rspec spec/requests/api/agent/v1/command_results_spec.rb spec/requests/api/agent/v1/commands_spec.rb`

Expected: PASS.

Run: `bundle exec rubocop app/domain/agent/commands/acknowledge.rb app/controllers/api/agent/v1/command_results_controller.rb spec/requests/api/agent/v1/command_results_spec.rb config/routes.rb`

Expected: no offenses.

- [ ] **Step 5: Commit**

```bash
git add app/domain/agent/commands/acknowledge.rb \
  app/controllers/api/agent/v1/command_results_controller.rb \
  spec/requests/api/agent/v1/command_results_spec.rb config/routes.rb
git commit -m "$(cat <<'EOF'
feat: ack agent command results idempotently

Unknown ids and repeats stay HTTP 200. A failed result still leaves the pending queue.
EOF
)"
```

---

### Task 7: Admin `tv_monitor` settings

**Files:**
- Modify: `app/controllers/admin/stations_controller.rb`
- Modify: `app/views/admin/stations/_form.html.erb`
- Modify: `spec/requests/admin/stations_spec.rb`
- Modify: `config/locales/mediateca.ru.yml`
- Modify: `config/locales/mediateca.en.yml`

**Interfaces:**
- Consumes: `Station#tv_monitor`, валидации `StationTvMonitor` из Task 1.
- Produces: чекбокс `station[configure_tv_monitor]` и поля `station[tv_monitor][health_interval_seconds]`, `station[tv_monitor][auto_restart_when_not_playing]`, `station[tv_monitor][telemetry_interval_seconds]`. Снятый чекбокс удаляет строку. Сохранение station без включённого чекбокса не создаёт `StationTvMonitor`.

- [ ] **Step 1: Write the failing admin spec**

В `spec/requests/admin/stations_spec.rb` добавь примеры:

```ruby
it "does not create tv monitor settings unless the operator opts in" do
  post admin_stations_path, params: {
    station: {
      location_id: location.id,
      name: "Lobby",
      offline_cache_hours: 24,
      configure_tv_monitor: "0",
      tv_monitor: { health_interval_seconds: 30, auto_restart_when_not_playing: "1", telemetry_interval_seconds: 60 }
    }
  }

  station = Station.find_by!(name: "Lobby")
  expect(station.tv_monitor).to be_nil
end

it "saves an explicit false auto-restart when tv monitor is enabled" do
  station = create(:station, location: location)

  patch admin_station_path(station), params: {
    station: {
      location_id: location.id,
      name: station.name,
      offline_cache_hours: 24,
      configure_tv_monitor: "1",
      tv_monitor: {
        health_interval_seconds: 20,
        auto_restart_when_not_playing: "0",
        telemetry_interval_seconds: 90
      }
    }
  }

  expect(response).to redirect_to(admin_station_path(station))
  monitor = station.reload.tv_monitor
  expect(monitor.health_interval_seconds).to eq(20)
  expect(monitor.auto_restart_when_not_playing).to be(false)
  expect(monitor.telemetry_interval_seconds).to eq(90)
end

it "drops tv monitor settings when the operator clears the checkbox" do
  station = create(:station, location: location)
  create(:station_tv_monitor, station:)

  patch admin_station_path(station), params: {
    station: {
      location_id: location.id,
      name: station.name,
      offline_cache_hours: 24,
      configure_tv_monitor: "0"
    }
  }

  expect(station.reload.tv_monitor).to be_nil
end

it "renders the edit form again when the health interval is below 5" do
  station = create(:station, location: location)

  patch admin_station_path(station), params: {
    station: {
      location_id: location.id,
      name: station.name,
      offline_cache_hours: 24,
      configure_tv_monitor: "1",
      tv_monitor: {
        health_interval_seconds: 1,
        auto_restart_when_not_playing: "1",
        telemetry_interval_seconds: 60
      }
    }
  }

  expect(response).to have_http_status(:unprocessable_content)
  expect(station.reload.tv_monitor).to be_nil
end
```

- [ ] **Step 2: Run the spec and verify it fails**

Run: `bundle exec rspec spec/requests/admin/stations_spec.rb`

Expected: FAIL на новых примерах. Чекбокс игнорируется, `tv_monitor` не создаётся там, где `"1"`, либо создаётся там, где `"0"`.

- [ ] **Step 3: Form and controller**

В `config/locales/mediateca.ru.yml` вставь ключи в `admin.stations` (тот же отступ, что у `regenerate_playlists`) и соседний блок `admin.agent_commands` пока не нужен:

```yaml
      configure_tv_monitor: Отдавать tv_monitor станции
      tv_monitor_hint: Пустой объект не отправляем. Снятие флажка возвращает дефолты station (health 30 с, авторестарт включён, telemetry 60 с). При включённом авторестарте команда stop может быть сразу отменена watchdog.
      tv_monitor_health: Интервал health, секунды
      tv_monitor_auto_restart: Авторестарт, когда эфир есть, а playing=false
      tv_monitor_telemetry: Интервал telemetry, секунды
```

В `config/locales/mediateca.en.yml` в `admin.stations`:

```yaml
      configure_tv_monitor: Send tv_monitor to the station
      tv_monitor_hint: An empty object is never sent. Clearing the box restores station defaults (health 30s, auto-restart on, telemetry 60s). With auto-restart on, a stop command can be undone by the watchdog.
      tv_monitor_health: Health interval, seconds
      tv_monitor_auto_restart: Auto-restart when the broadcast is up and playing is false
      tv_monitor_telemetry: Telemetry interval, seconds
```

Замени `app/views/admin/stations/_form.html.erb` целиком:

```erb
<%= form_with model: [:admin, station], class: "max-w-xl bg-white border border-gray-200 rounded-lg p-6" do |f| %>
  <%= render "admin/shared/form_errors", record: station %>
  <% if station.tv_monitor&.errors&.any? %>
    <%= render "admin/shared/form_errors", record: station.tv_monitor %>
  <% end %>
  <div class="mb-5">
    <%= f.label :location_id, class: admin_label_class %>
    <%= f.collection_select :location_id, Location.order(:name), :id, :name, { include_blank: true }, class: admin_select_class %>
  </div>
  <div class="mb-5">
    <%= f.label :name, class: admin_label_class %>
    <%= f.text_field :name, class: admin_input_class, required: true %>
  </div>
  <div class="mb-5">
    <%= f.label :offline_cache_hours, class: admin_label_class %>
    <%= f.number_field :offline_cache_hours, class: admin_input_class %>
  </div>
  <% monitor = station.tv_monitor || station.build_tv_monitor %>
  <fieldset class="mb-5 space-y-4">
    <div>
      <%= hidden_field_tag "station[configure_tv_monitor]", "0" %>
      <%= check_box_tag "station[configure_tv_monitor]", "1", @configure_tv_monitor, id: "station_configure_tv_monitor", class: "rounded border-gray-300" %>
      <%= label_tag "station_configure_tv_monitor", t("admin.stations.configure_tv_monitor"), class: "ml-2 text-sm text-gray-700" %>
      <p class="mt-2 text-sm text-gray-500"><%= t("admin.stations.tv_monitor_hint") %></p>
    </div>
    <div>
      <%= label_tag "station_tv_monitor_health_interval_seconds", t("admin.stations.tv_monitor_health"), class: admin_label_class %>
      <%= number_field_tag "station[tv_monitor][health_interval_seconds]", monitor.health_interval_seconds, id: "station_tv_monitor_health_interval_seconds", class: admin_input_class, min: 5 %>
    </div>
    <div>
      <%= hidden_field_tag "station[tv_monitor][auto_restart_when_not_playing]", "0" %>
      <%= check_box_tag "station[tv_monitor][auto_restart_when_not_playing]", "1", monitor.auto_restart_when_not_playing, id: "station_tv_monitor_auto_restart_when_not_playing", class: "rounded border-gray-300" %>
      <%= label_tag "station_tv_monitor_auto_restart_when_not_playing", t("admin.stations.tv_monitor_auto_restart"), class: "ml-2 text-sm text-gray-700" %>
    </div>
    <div>
      <%= label_tag "station_tv_monitor_telemetry_interval_seconds", t("admin.stations.tv_monitor_telemetry"), class: admin_label_class %>
      <%= number_field_tag "station[tv_monitor][telemetry_interval_seconds]", monitor.telemetry_interval_seconds, id: "station_tv_monitor_telemetry_interval_seconds", class: admin_input_class, min: 5 %>
    </div>
  </fieldset>
  <div class="flex flex-wrap gap-3">
    <%= f.submit class: admin_primary_button_class %>
    <%= link_to t("admin.chrome.cancel"), admin_stations_path, class: admin_secondary_button_class %>
  </div>
<% end %>
```

Чекбокс читает `@configure_tv_monitor`, который выставляет контроллер. Не выводи его из `new_record?`: после `build_tv_monitor` несохранённая запись с ошибкой валидации тоже `new_record?`, и флажок погас бы при повторном показе формы.

В `Admin::StationsController` замени `new`, `edit`, `create`, `update` и добавь private-методы. `station_params` оставь прежним: `location_id`, `name`, `offline_cache_hours`. Не передавай `configure_tv_monitor` в `Station` — это не колонка.

Валидируй монитор до `save!`. Иначе откат транзакции оставляет у нового `Station` id в памяти, и `form_with` уходит в `PATCH` вместо `POST`.

```ruby
def new
  @station = Station.new
  @configure_tv_monitor = false
  @station.build_tv_monitor
end

def edit
  @station = Station.find(params[:id])
  @configure_tv_monitor = @station.tv_monitor.present?
  @station.build_tv_monitor unless @station.tv_monitor
end

def create
  @station = Station.new(station_params)
  monitor = drafted_monitor(@station)
  if save_station(@station, monitor)
    redirect_to admin_station_path(@station), notice: t("admin.crud.created"), status: :see_other
  else
    render_station_form(:new, monitor)
  end
end

def update
  @station = Station.find(params[:id])
  @station.assign_attributes(station_params)
  monitor = drafted_monitor(@station)
  if save_station(@station, monitor)
    redirect_to admin_station_path(@station), notice: t("admin.crud.updated"), status: :see_other
  else
    render_station_form(:edit, monitor)
  end
end
```

Private:

```ruby
def configure_tv_monitor?
  ActiveModel::Type::Boolean.new.cast(params.dig(:station, :configure_tv_monitor))
end

def tv_monitor_input
  raw = params.dig(:station, :tv_monitor)
  return {} unless raw.respond_to?(:permit)

  raw.permit(:health_interval_seconds, :auto_restart_when_not_playing, :telemetry_interval_seconds)
end

def drafted_monitor(station)
  return unless configure_tv_monitor?

  monitor = station.tv_monitor || station.build_tv_monitor
  monitor.assign_attributes(tv_monitor_input)
  monitor
end

def save_station(station, monitor)
  station_ok = station.valid?
  monitor_ok = monitor.nil? || monitor.valid?
  return false unless station_ok && monitor_ok

  Station.transaction do
    station.save!
    if monitor
      monitor.station = station
      monitor.save!
    else
      station.tv_monitor&.destroy!
    end
  end
  true
end

def render_station_form(template, monitor)
  @configure_tv_monitor = configure_tv_monitor?
  if monitor
    @station.association(:tv_monitor).target = monitor
  else
    @station.build_tv_monitor unless @station.tv_monitor
  end
  render template, status: :unprocessable_content
end
```

`drafted_monitor` возвращает `nil`, когда флажок снят: `save_station` тогда удаляет существующую строку. Скрытое поле чекбокса шлёт `"0"`, так что `auto_restart_when_not_playing` сохраняется как явный `false`, а не пропадает из JSON.

- [ ] **Step 4: Run the spec and RuboCop**

Run: `bundle exec rspec spec/requests/admin/stations_spec.rb spec/requests/api/agent/v1/configs_spec.rb`

Expected: PASS. После patch с `configure_tv_monitor: "1"` и `auto_restart_when_not_playing: "0"` config JSON содержит `"auto_restart_when_not_playing" => false`. Это уже покрыто admin-спекой на модели; config-спека Task 1 остаётся зелёной.

Run: `bundle exec rubocop app/controllers/admin/stations_controller.rb spec/requests/admin/stations_spec.rb`

Expected: no offenses.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/admin/stations_controller.rb app/views/admin/stations/_form.html.erb \
  spec/requests/admin/stations_spec.rb config/locales/mediateca.ru.yml config/locales/mediateca.en.yml
git commit -m "$(cat <<'EOF'
feat: edit per-station tv_monitor settings

Leaving the box unchecked omits the config key. A saved false auto-restart flag is sent explicitly.
EOF
)"
```

---

### Task 8: Show the latest telemetry in admin

**Files:**
- Modify: `app/controllers/admin/stations_controller.rb` (`show`)
- Modify: `app/views/admin/stations/show.html.erb`
- Modify: `spec/requests/admin/stations_spec.rb`
- Modify: `config/locales/mediateca.ru.yml`
- Modify: `config/locales/mediateca.en.yml`

**Interfaces:**
- Consumes: `station.telemetry_snapshot`, `station.screen_telemetry_snapshots` с `screen`.
- Produces: на `GET /admin/stations/:id` блок с `package_etag`, `broadcast_ok`, `reported_at`, и по каждому screen — `playing`, `wakefulness`, `last_error`, `ignored` ids. Пустой снимок показывает `admin.stations.telemetry_empty`.

- [ ] **Step 1: Write the failing spec**

В `spec/requests/admin/stations_spec.rb`:

```ruby
it "shows the latest telemetry snapshot" do
  station = create(:station, location: location)
  screen = create(:screen, station:)
  StationTelemetrySnapshot.create!(
    station: station,
    reported_at: Time.utc(2026, 10, 9, 11, 0, 0),
    uptime_seconds: 3600,
    package_etag: "W/\"pkg\"",
    broadcast_ok: true,
    ignored_screen_ids: [ 404 ]
  )
  ScreenTelemetrySnapshot.create!(
    screen: screen,
    station: station,
    reported_at: Time.utc(2026, 10, 9, 11, 0, 0),
    reachable: true,
    agent_ok: true,
    playing: false,
    url: "http://192.168.33.1:8091/",
    wakefulness: "",
    stream_port: 8091,
    broadcast_clients: 0,
    last_error: "player down"
  )

  get admin_station_path(station)

  expect(response).to have_http_status(:ok)
  expect(response.body).to include("W/&quot;pkg&quot;").or include("W/\"pkg\"")
  expect(response.body).to include("player down")
  expect(response.body).to include("404")
end
```

`or` — матчер RSpec compound. Если он неудобен, проверяй `response.body` через `include("pkg")` и `include("player down")`. Обязательные вхождения: `pkg`, `player down`, `404`.

- [ ] **Step 2: Run the spec and verify it fails**

Run: `bundle exec rspec spec/requests/admin/stations_spec.rb -e "latest telemetry"`

Expected: FAIL. В теле нет `player down`.

- [ ] **Step 3: Render the snapshot**

В `show` контроллера после загрузки `@station` добавь:

```ruby
@telemetry = @station.telemetry_snapshot
@screen_telemetry = @station.screen_telemetry_snapshots.includes(:screen).order(:screen_id)
```

Локали `admin.stations` ru:

```yaml
      telemetry: Телеметрия
      telemetry_empty: Снимка ещё не было.
      telemetry_reported_at: Время снимка
      telemetry_package_etag: ETag пакета
      telemetry_broadcast_ok: Эфир поднят
      telemetry_ignored: Чужие screen_id
      telemetry_playing: playing
      telemetry_wakefulness: wakefulness
      telemetry_last_error: last_error
```

en:

```yaml
      telemetry: Telemetry
      telemetry_empty: No snapshot yet.
      telemetry_reported_at: Reported at
      telemetry_package_etag: Package ETag
      telemetry_broadcast_ok: Broadcast up
      telemetry_ignored: Foreign screen ids
      telemetry_playing: playing
      telemetry_wakefulness: wakefulness
      telemetry_last_error: last_error
```

В `app/views/admin/stations/show.html.erb` перед блоком `<div class="mt-6 flex flex-wrap gap-3">` вставь:

```erb
<div class="mt-6 bg-white border border-gray-200 rounded-lg p-6">
  <h2 class="mb-4 text-lg font-medium text-gray-900"><%= t("admin.stations.telemetry") %></h2>
  <% if @telemetry %>
    <dl class="mb-4 grid grid-cols-1 gap-2 sm:grid-cols-2 text-sm text-gray-900">
      <div>
        <dt class="text-gray-500"><%= t("admin.stations.telemetry_reported_at") %></dt>
        <dd><%= @telemetry.reported_at.utc.iso8601 %></dd>
      </div>
      <div>
        <dt class="text-gray-500"><%= t("admin.stations.telemetry_package_etag") %></dt>
        <dd><%= @telemetry.package_etag %></dd>
      </div>
      <div>
        <dt class="text-gray-500"><%= t("admin.stations.telemetry_broadcast_ok") %></dt>
        <dd><%= admin_boolean(@telemetry.broadcast_ok) %></dd>
      </div>
      <div>
        <dt class="text-gray-500"><%= t("admin.stations.telemetry_ignored") %></dt>
        <dd><%= @telemetry.ignored_screen_ids.presence&.join(", ") || t("admin.crud.none") %></dd>
      </div>
    </dl>
    <table class="w-full text-sm text-left text-gray-500">
      <thead class="text-xs text-gray-700 uppercase bg-gray-50">
        <tr>
          <th class="px-4 py-3"><%= Screen.model_name.human %></th>
          <th class="px-4 py-3"><%= t("admin.stations.telemetry_playing") %></th>
          <th class="px-4 py-3"><%= t("admin.stations.telemetry_wakefulness") %></th>
          <th class="px-4 py-3"><%= t("admin.stations.telemetry_last_error") %></th>
        </tr>
      </thead>
      <tbody>
        <% @screen_telemetry.each do |row| %>
          <tr class="bg-white border-b">
            <td class="px-4 py-3"><%= row.screen.name %></td>
            <td class="px-4 py-3"><%= admin_boolean(row.playing) %></td>
            <td class="px-4 py-3"><%= row.wakefulness.presence || t("admin.crud.none") %></td>
            <td class="px-4 py-3"><%= row.last_error.presence || t("admin.crud.none") %></td>
          </tr>
        <% end %>
      </tbody>
    </table>
  <% else %>
    <p class="text-sm text-gray-500"><%= t("admin.stations.telemetry_empty") %></p>
  <% end %>
</div>
```

- [ ] **Step 4: Run the spec and RuboCop**

Run: `bundle exec rspec spec/requests/admin/stations_spec.rb`

Expected: PASS.

Run: `bundle exec rubocop app/controllers/admin/stations_controller.rb spec/requests/admin/stations_spec.rb`

Expected: no offenses.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/admin/stations_controller.rb app/views/admin/stations/show.html.erb \
  spec/requests/admin/stations_spec.rb config/locales/mediateca.ru.yml config/locales/mediateca.en.yml
git commit -m "$(cat <<'EOF'
feat: show the latest station telemetry in admin

Operators can see the last snapshot, including empty wakefulness and ignored screen ids.
EOF
)"
```

---

### Task 9: Enqueue a command from the screen page

**Files:**
- Create: `app/controllers/admin/agent_commands_controller.rb`
- Modify: `app/controllers/admin/screens_controller.rb`
- Modify: `app/views/admin/screens/show.html.erb`
- Modify: `config/routes.rb`
- Modify: `spec/requests/admin/screens_spec.rb` (создай файл, если его нет)
- Modify: `config/locales/mediateca.ru.yml`
- Modify: `config/locales/mediateca.en.yml`
- Modify: `.env.example`

**Interfaces:**
- Consumes: `Agent::Commands::Issue.call(screen:, type:, params:, url_options:)` и `Issue::Error#code`. `AgentCommand::TYPES`.
- Produces: `POST /admin/screens/:screen_id/agent_commands` с полями `agent_command[command_type]`, `agent_command[url]`, `agent_command[buffer_ms]`, `agent_command[seconds]`. Редирект на `admin_screen_path`. `url_options` берутся из `ENV["APP_HOST"]` / `ENV["APP_PROTOCOL"]`, иначе из текущего request. Страница экрана показывает последние 20 команд: `public_id`, `command_type`, `status`, `result_error`.

- [ ] **Step 1: Write the failing request spec**

Если `spec/requests/admin/screens_spec.rb` нет, создай его с тем же `sign_in` хелпером, что в `spec/requests/admin/stations_spec.rb` (`sign_in_as`, operator). Прочитай этот хелпер и скопируй `let`/`before` оттуда, не выдумывай новый логин.

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin screen agent commands", type: :request do
  let(:operator_org) { create(:organization, :operator) }
  let(:operator) { create(:user, :manager, organization: operator_org) }
  let(:station) { create(:station) }
  let(:screen) { create(:screen, station:) }

  before { sign_in_as(operator) }

  it "queues a restart_stream that the agent poll can see" do
    token = SecureRandom.hex(16)
    station.assign_agent_token!(token)

    post admin_screen_agent_commands_path(screen), params: {
      agent_command: { command_type: "restart_stream", url: "", buffer_ms: "", seconds: "" }
    }

    expect(response).to redirect_to(admin_screen_path(screen))
    command = screen.agent_commands.pending.sole
    expect(command.command_type).to eq("restart_stream")
    expect(command.params).to eq({})

    get "/api/agent/v1/commands", headers: agent_authorization_headers(token), as: :json
    expect(response.parsed_body["commands"].map { |row| row["id"] }).to eq([ command.public_id ])
  end

  it "queues a screenshot whose upload url is on this host" do
    post admin_screen_agent_commands_path(screen), params: {
      agent_command: { command_type: "screenshot", url: "https://evil.example/put", buffer_ms: "", seconds: "" }
    }

    command = screen.agent_commands.pending.sole
    expect(command.params["upload_url"]).to include("/api/agent/uploads/")
    expect(command.params["upload_url"]).not_to include("evil.example")

    token = command.params["upload_url"].split("/uploads/").last
    put "/api/agent/uploads/#{token}", params: "png-bytes", headers: { "CONTENT_TYPE" => "image/png" }
    expect(response).to have_http_status(:no_content)
    expect(command.reload.artifact.download).to eq("png-bytes")
  end

  it "rejects a non-https apk url and leaves the queue empty" do
    post admin_screen_agent_commands_path(screen), params: {
      agent_command: { command_type: "install_apk", url: "http://files.example/app.apk", buffer_ms: "", seconds: "" }
    }

    expect(response).to redirect_to(admin_screen_path(screen))
    expect(screen.agent_commands).to be_empty
    follow_redirect!
    expect(response.body).to include(I18n.t("admin.agent_commands.errors.url_must_be_https"))
  end
end
```

`agent_authorization_headers` подключён только для `type: :request`, так что хелпер доступен.

- [ ] **Step 2: Run the spec and verify it fails**

Run: `bundle exec rspec spec/requests/admin/screens_spec.rb -e "agent"`

Если файл общий и фильтр не сработал, запусти файл целиком.

Expected: FAIL. `undefined method admin_screen_agent_commands_path` или нет маршрута.

- [ ] **Step 3: Admin create**

В `namespace :admin` у `resources :screens` сделай блок:

```ruby
resources :screens do
  resources :agent_commands, only: :create
end
```

Не дублируй `resources :screens`, если строка уже есть: замени её на блок. Проверь, что `admin_screens_path` и `admin_screen_path` живы (`bin/rails routes -g agent_command`).

`app/controllers/admin/agent_commands_controller.rb`

```ruby
# frozen_string_literal: true

module Admin
  class AgentCommandsController < Admin::BaseController
    def create
      screen = Screen.find(params[:screen_id])
      raw = params.expect(agent_command: [ :command_type, :url, :buffer_ms, :seconds ])
      Agent::Commands::Issue.call(
        screen: screen,
        type: raw[:command_type].to_s,
        params: raw.slice(:url, :buffer_ms, :seconds).to_h,
        url_options: artifact_url_options
      )
      redirect_to admin_screen_path(screen), notice: t("admin.agent_commands.created"), status: :see_other
    rescue Agent::Commands::Issue::Error => error
      redirect_to admin_screen_path(screen), alert: t("admin.agent_commands.errors.#{error.code}"), status: :see_other
    end

    private

    def artifact_url_options
      if ENV["APP_HOST"].present?
        { host: ENV["APP_HOST"], protocol: ENV.fetch("APP_PROTOCOL", "https") }
      else
        { host: request.host, port: request.optional_port, protocol: request.protocol.delete_suffix("://") }
      end
    end
  end
end
```

`screen` в rescue виден, потому что присвоен до `Issue.call`. Если `Screen.find` бросит `RecordNotFound`, это не `Issue::Error` — оставь стандартный 404.

В `Admin::ScreensController#show` после `find`:

```ruby
@agent_commands = @screen.agent_commands.order(issued_at: :desc).limit(20)
```

Локали ru, блок рядом с `admin.stations` (внутри `admin:`):

```yaml
    agent_commands:
      title: Команды станции
      created: Команда поставлена в очередь.
      type: Тип
      url: URL
      buffer_ms: buffer_ms
      seconds: Секунды записи
      submit: Поставить в очередь
      empty: Команд ещё не было.
      errors:
        unknown_type: Неизвестный тип команды.
        buffer_ms_invalid: buffer_ms должен быть неотрицательным числом.
        seconds_out_of_range: Длина записи от 1 до 120 секунд.
        url_must_be_https: URL APK должен начинаться с https://.
        missing_host: Не задан хост Hub для upload URL.
```

en:

```yaml
    agent_commands:
      title: Station commands
      created: Command queued.
      type: Type
      url: URL
      buffer_ms: buffer_ms
      seconds: Record seconds
      submit: Queue command
      empty: No commands yet.
      errors:
        unknown_type: Unknown command type.
        buffer_ms_invalid: buffer_ms must be a non-negative number.
        seconds_out_of_range: Record length must be from 1 to 120 seconds.
        url_must_be_https: The APK URL must start with https://.
        missing_host: No hub host is configured for the upload URL.
```

В `app/views/admin/screens/show.html.erb` перед нижним `<div class="mt-6 flex flex-wrap gap-3">` вставь:

```erb
<div class="mt-6 bg-white border border-gray-200 rounded-lg p-6 max-w-xl">
  <h2 class="mb-4 text-lg font-medium text-gray-900"><%= t("admin.agent_commands.title") %></h2>
  <%= form_with url: admin_screen_agent_commands_path(@screen), scope: :agent_command, class: "space-y-4" do |f| %>
    <div>
      <%= f.label :command_type, t("admin.agent_commands.type"), class: admin_label_class %>
      <%= f.select :command_type, AgentCommand::TYPES, {}, class: admin_select_class %>
    </div>
    <div>
      <%= f.label :url, t("admin.agent_commands.url"), class: admin_label_class %>
      <%= f.text_field :url, class: admin_input_class %>
    </div>
    <div>
      <%= f.label :buffer_ms, t("admin.agent_commands.buffer_ms"), class: admin_label_class %>
      <%= f.number_field :buffer_ms, class: admin_input_class, min: 0 %>
    </div>
    <div>
      <%= f.label :seconds, t("admin.agent_commands.seconds"), class: admin_label_class %>
      <%= f.number_field :seconds, class: admin_input_class, min: 1, max: 120 %>
    </div>
    <%= f.submit t("admin.agent_commands.submit"), class: admin_primary_button_class %>
  <% end %>

  <% if @agent_commands.any? %>
    <ul class="mt-6 space-y-2 text-sm text-gray-900">
      <% @agent_commands.each do |command| %>
        <li>
          <span class="font-mono"><%= command.public_id %></span>
          <%= command.command_type %>
          <%= command.status %>
          <%= command.result_error %>
        </li>
      <% end %>
    </ul>
  <% else %>
    <p class="mt-6 text-sm text-gray-500"><%= t("admin.agent_commands.empty") %></p>
  <% end %>
</div>
```

В `.env.example` в конец:

```
# Хост, которым station уже пользуется как hub base URL.
# Upload URL для screenshot/record берёт APP_HOST, если переменная задана.
# Иначе берётся хост админского запроса (для localhost station с другой машины не скачает файл).
# APP_HOST=hub.example.com
# APP_PROTOCOL=https
```

- [ ] **Step 4: Run the specs and RuboCop**

Run: `bundle exec rspec spec/requests/admin/screens_spec.rb spec/requests/api/agent/v1/commands_spec.rb spec/requests/api/agent/uploads_spec.rb spec/domain/agent/commands/issue_spec.rb`

Expected: PASS. Screenshot из админки принимает PUT и кладёт байты в Active Storage.

Run: `bundle exec rubocop app/controllers/admin/agent_commands_controller.rb app/controllers/admin/screens_controller.rb spec/requests/admin/screens_spec.rb config/routes.rb`

Expected: no offenses.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/admin/agent_commands_controller.rb app/controllers/admin/screens_controller.rb \
  app/views/admin/screens/show.html.erb config/routes.rb spec/requests/admin/screens_spec.rb \
  config/locales/mediateca.ru.yml config/locales/mediateca.en.yml .env.example
git commit -m "$(cat <<'EOF'
feat: queue a station command from the screen page

The upload URL is minted by the hub. APP_HOST overrides the admin request host when the station uses a different base URL.
EOF
)"
```

---

### Task 10: Contract sweep

**Files:**
- Modify: none, если спеки зелёные. Правки только по красному прогону.

**Interfaces:**
- Consumes: всё, что произвели Task 1–9.
- Produces: зелёный прогон списка ниже. Это последний барьер перед тем, как считать Hub совместимым со station M2 на уровне request specs.

- [ ] **Step 1: Run the agent and admin specs together**

Run:

```bash
bundle exec rspec \
  spec/requests/api/agent/v1/configs_spec.rb \
  spec/requests/api/agent/v1/telemetries_spec.rb \
  spec/requests/api/agent/v1/commands_spec.rb \
  spec/requests/api/agent/v1/command_results_spec.rb \
  spec/requests/api/agent/uploads_spec.rb \
  spec/requests/api/agent/v1/play_events_spec.rb \
  spec/requests/api/agent/v2/packages_spec.rb \
  spec/domain/agent/config_builder_spec.rb \
  spec/domain/agent/commands/issue_spec.rb \
  spec/requests/admin/stations_spec.rb \
  spec/requests/admin/screens_spec.rb
```

Expected: PASS. Все примеры, ноль pending.

- [ ] **Step 2: RuboCop the control-plane files**

Run:

```bash
bundle exec rubocop \
  app/controllers/api/agent \
  app/controllers/admin/stations_controller.rb \
  app/controllers/admin/agent_commands_controller.rb \
  app/controllers/admin/screens_controller.rb \
  app/domain/agent \
  app/models/agent_command.rb \
  app/models/station.rb \
  app/models/screen.rb \
  app/models/station_tv_monitor.rb \
  app/models/station_telemetry_snapshot.rb \
  app/models/screen_telemetry_snapshot.rb \
  spec/requests/api/agent \
  spec/domain/agent \
  spec/requests/admin/stations_spec.rb \
  spec/requests/admin/screens_spec.rb
```

Expected: no offenses.

- [ ] **Step 3: Commit only if the sweep required a fix**

Если шаг 1 или 2 заставил менять код, почини минимальным коммитом с сообщением, которое называет конкретный красный пример. Если оба шага зелёные без правок, коммит не создавай.

---

## Spec coverage

| Спека | Задача |
| --- | --- |
| §3 `tv_monitor` опционален, bool явный | Task 1, Task 7 |
| §4 POST telemetry, 202, пустые поля, чужой screen | Task 2 |
| §5 GET commands, ETag/304, типы и params | Task 3, Task 5 |
| §5 upload PUT 2xx без Bearer, TTL ≥ 5 мин | Task 3 (15 мин), Task 4 |
| §6 command_results 200, идемпотентность, already_done, не 404 | Task 6 |
| §7 request specs 401 / пустая очередь / ack / дубль | Task 2, 5, 6 |
| §7 admin: постановка команды, снимок, tv_monitor | Task 7, 8, 9 |
| §8 screenshot, record 15s, missing_upload_url уходит из pending | Task 3 (seconds), Task 6 (ack ошибки), Task 9 (PUT png) |
| §9 пункты 1–4 на уровне request specs | Task 10 |
| §9 пункт 5: admin меняет интервалы, config их отдаёт | Task 1 + Task 7. Живой station poll — после merge, не код этого плана |
| §10 история telemetry | Не делаем |
| §2 package и play_events | Не меняем контроллеры; Task 10 гоняет их спеки |

## Out of scope

- Таблица истории telemetry и job очистки.
- Multipart в `command_results`.
- Команды без `screen_id`.
- Входящий push Hub → station.
- Правки `mediateca-station`.
- Presigned PUT напрямую в rustfs.
