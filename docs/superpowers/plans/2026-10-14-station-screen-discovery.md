# Station Screen Discovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Добавить в Hub обнаружение экранов станции через команду `fetch_screens`, синхронизацию MAC/IP и управление из операторской админки.

**Architecture:** Существующая очередь `AgentCommand` получает станционную команду с nullable `screen_id`. HTTP-протокол подтверждения остаётся общим, но нормализация адресов и синхронизация экранов вынесены в отдельные доменные сервисы. PostgreSQL 18 хранит адреса встроенными типами `macaddr` и `inet`, а ограничения и блокировка станции защищают конкурентные записи.

**Tech Stack:** Ruby 4.0, Rails 8.1, PostgreSQL 18, RSpec, FactoryBot, ERB, Tailwind/Flowbite.

---

## Карта файлов

Новые файлы:

- `db/migrate/20261014030000_add_network_identity_to_screens.rb` — схема адресов, nullable screen command и ограничения.
- `spec/models/agent_command_spec.rb` — правила станционной и экранной команды.
- `app/domain/agent/screens/normalize_discovery.rb` — чистая проверка и канонизация payload.
- `app/domain/agent/screens/synchronize.rb` — транзакционная синхронизация экранов.
- `spec/domain/agent/screens/normalize_discovery_spec.rb` — контракт адресов.
- `spec/domain/agent/screens/synchronize_spec.rb` — создание, обновление и снятие регистрации.
- `app/domain/agent/commands/fetch_screens.rb` — идемпотентная постановка команды.
- `spec/domain/agent/commands/fetch_screens_spec.rb` — постановка и защита от дублей.
- `app/controllers/admin/station_screen_refreshes_controller.rb` — admin POST endpoint.

Изменяемые файлы:

- `app/models/screen.rb` и `spec/models/screen_spec.rb` — IPv4 host validation и новые поля.
- `app/models/agent_command.rb` — новый тип и правила optional `screen`.
- `spec/factories/agent_commands.rb` — trait станционной команды.
- `app/domain/agent/commands/acknowledge.rb` — запуск синхронизации до ack.
- `app/controllers/api/agent/v1/command_results_controller.rb` — strong parameters для `result.screens`.
- `spec/requests/api/agent/v1/commands_spec.rb` — `screen_id: null`.
- `spec/requests/api/agent/v1/command_results_spec.rb` — интеграция результата.
- `config/routes.rb` — admin screen refresh.
- `app/controllers/admin/stations_controller.rb` — упорядоченный список экранов.
- `app/views/admin/stations/show.html.erb` — секция экранов и кнопка.
- `spec/requests/admin/stations_spec.rb` — UI и POST.
- `config/locales/mediateca.ru.yml`, `config/locales/mediateca.en.yml` — тексты.
- `db/schema.rb` и schema annotations — генерируются миграцией/Annotate.

### Task 1: Схема данных и инварианты моделей

**Files:**
- Create: `db/migrate/20261014030000_add_network_identity_to_screens.rb`
- Create: `spec/models/agent_command_spec.rb`
- Modify: `spec/models/screen_spec.rb`
- Modify: `spec/factories/agent_commands.rb`
- Modify: `app/models/screen.rb`
- Modify: `app/models/agent_command.rb`
- Generated: `db/schema.rb`

- [ ] **Step 1: Написать падающие model specs**

В `spec/models/screen_spec.rb` добавить:

```ruby
describe "network identity" do
  it "stores PostgreSQL network types and defaults to unregistered" do
    screen = create(:screen, mac_address: "AA-BB-CC-DD-EE-FF", ip_address: "192.168.1.10")

    expect(screen.reload.mac_address).to eq("aa:bb:cc:dd:ee:ff")
    expect(screen.ip_address).to eq(IPAddr.new("192.168.1.10"))
    expect(screen.network_registered).to be(false)
  end

  it "rejects IPv6 and an IPv4 network prefix" do
    ipv6 = build(:screen, ip_address: "2001:db8::1")
    subnet = build(:screen, ip_address: "192.168.1.0/24")

    expect(ipv6).not_to be_valid
    expect(subnet).not_to be_valid
    expect(ipv6.errors[:ip_address]).to be_present
    expect(subnet.errors[:ip_address]).to be_present
  end

  it "allows the same MAC on different stations but not twice on one station" do
    first = create(:screen, mac_address: "aa:bb:cc:dd:ee:ff")

    expect(build(:screen, station: first.station, mac_address: first.mac_address)).not_to be_valid
    expect(build(:screen, mac_address: first.mac_address)).to be_valid
  end
end
```

Создать `spec/models/agent_command_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe AgentCommand, type: :model do
  it "allows fetch_screens without a screen" do
    expect(build(:agent_command, :fetch_screens)).to be_valid
  end

  it "requires a screen for a screen command" do
    command = build(:agent_command, screen: nil)

    expect(command).not_to be_valid
    expect(command.errors[:screen]).to be_present
  end

  it "rejects a screen on fetch_screens" do
    command = build(:agent_command, command_type: "fetch_screens")

    expect(command).not_to be_valid
    expect(command.errors[:screen]).to be_present
  end

  it "allows only one pending fetch_screens per station at the database level" do
    station = create(:station)
    create(:agent_command, :fetch_screens, station:)

    expect {
      create(:agent_command, :fetch_screens, station:)
    }.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
```

Добавить trait в `spec/factories/agent_commands.rb`:

```ruby
trait :fetch_screens do
  command_type { "fetch_screens" }
  screen { nil }
  params { {} }
end
```

- [ ] **Step 2: Запустить specs и подтвердить ожидаемое падение**

Run:

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/models/screen_spec.rb spec/models/agent_command_spec.rb
```

Expected: FAIL из-за неизвестных колонок/trait и отсутствующего `fetch_screens` в `AgentCommand::TYPES`.

- [ ] **Step 3: Добавить миграцию**

Создать:

```ruby
# frozen_string_literal: true

class AddNetworkIdentityToScreens < ActiveRecord::Migration[8.1]
  def change
    add_column :screens, :mac_address, :macaddr
    add_column :screens, :ip_address, :inet
    add_column :screens, :network_registered, :boolean, null: false, default: false

    add_index :screens, [ :station_id, :mac_address ],
      unique: true,
      where: "mac_address IS NOT NULL"
    add_check_constraint :screens,
      "ip_address IS NULL OR (family(ip_address) = 4 AND masklen(ip_address) = 32)",
      name: "screens_ip_address_is_ipv4_host"

    change_column_null :agent_commands, :screen_id, true
    add_index :agent_commands, :station_id,
      unique: true,
      where: "status = 'pending' AND command_type = 'fetch_screens'",
      name: "index_agent_commands_on_pending_fetch_screens"
  end
end
```

Run:

```bash
docker compose exec -e RAILS_ENV=test web bin/rails db:migrate
```

Expected: migration succeeds; `db/schema.rb` contains `inet`, `macaddr`, the check constraint and both partial indexes.

- [ ] **Step 4: Реализовать model validations**

В `Screen` добавить новые ransack attributes и validation:

```ruby
validates :mac_address, uniqueness: { scope: :station_id }, allow_nil: true
validate :ip_address_must_be_ipv4_host

def ip_address_must_be_ipv4_host
  raw = ip_address_before_type_cast
  return if raw.blank?

  address = raw.is_a?(IPAddr) ? raw : IPAddr.new(raw.to_s)
  return if address.ipv4? && address.prefix == 32 && !raw.to_s.include?("/")

  errors.add(:ip_address, :invalid)
rescue IPAddr::InvalidAddressError
  errors.add(:ip_address, :invalid)
end
```

Добавить `mac_address ip_address network_registered` в
`Screen.ransackable_attributes`.

В `AgentCommand`:

```ruby
TYPES = %w[start_stream restart_stream stop wake sleep screenshot record ensure_app install_apk fetch_screens].freeze

belongs_to :screen, optional: true

validate :screen_matches_command_scope

def screen_matches_command_scope
  if command_type == "fetch_screens"
    errors.add(:screen, :present) if screen.present?
  elsif screen.blank?
    errors.add(:screen, :blank)
  elsif screen.station_id != station_id
    errors.add(:screen, :invalid)
  end
end
```

Заменить старый callback `screen_belongs_to_station` новым
`screen_matches_command_scope`.

- [ ] **Step 5: Запустить model specs**

Run:

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/models/screen_spec.rb spec/models/agent_command_spec.rb
```

Expected: PASS.

- [ ] **Step 6: Зафиксировать схему и модели**

```bash
git add db/migrate/20261014030000_add_network_identity_to_screens.rb db/schema.rb app/models/screen.rb app/models/agent_command.rb spec/models/screen_spec.rb spec/models/agent_command_spec.rb spec/factories/agent_commands.rb
git commit -m "feat: add station network identity to screens"
```

### Task 2: Нормализация результата обнаружения

**Files:**
- Create: `app/domain/agent/screens/normalize_discovery.rb`
- Create: `spec/domain/agent/screens/normalize_discovery_spec.rb`

- [ ] **Step 1: Написать падающие specs нормализатора**

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agent::Screens::NormalizeDiscovery do
  it "canonicalizes and deduplicates equal pairs" do
    rows = [
      { mac_address: "AA-BB-CC-DD-EE-FF", ip_address: "192.168.1.10" },
      { mac_address: "aa:bb:cc:dd:ee:ff", ip_address: "192.168.1.10" }
    ]

    expect(described_class.call(screens: rows).map(&:to_h)).to eq([
      { mac_address: "aa:bb:cc:dd:ee:ff", ip_address: IPAddr.new("192.168.1.10") }
    ])
  end

  it "accepts an empty array" do
    expect(described_class.call(screens: [])).to eq([])
  end

  it "rejects missing rows, IPv6, CIDR and malformed MAC" do
    invalid_values = [
      nil,
      [ { mac_address: "bad", ip_address: "192.168.1.10" } ],
      [ { mac_address: "aa:bb:cc:dd:ee:ff", ip_address: "2001:db8::1" } ],
      [ { mac_address: "aa:bb:cc:dd:ee:ff", ip_address: "192.168.1.0/24" } ]
    ]

    invalid_values.each do |screens|
      expect { described_class.call(screens:) }.to raise_error(described_class::Invalid)
    end
  end

  it "rejects conflicting active mappings" do
    same_mac = [
      { mac_address: "aa:bb:cc:dd:ee:ff", ip_address: "192.168.1.10" },
      { mac_address: "aa:bb:cc:dd:ee:ff", ip_address: "192.168.1.11" }
    ]
    same_ip = [
      { mac_address: "aa:bb:cc:dd:ee:ff", ip_address: "192.168.1.10" },
      { mac_address: "11:22:33:44:55:66", ip_address: "192.168.1.10" }
    ]

    expect { described_class.call(screens: same_mac) }.to raise_error(described_class::Invalid)
    expect { described_class.call(screens: same_ip) }.to raise_error(described_class::Invalid)
  end
end
```

- [ ] **Step 2: Запустить spec и подтвердить отсутствие класса**

Run:

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/agent/screens/normalize_discovery_spec.rb
```

Expected: FAIL with `uninitialized constant Agent::Screens`.

- [ ] **Step 3: Реализовать чистый нормализатор**

```ruby
# frozen_string_literal: true

module Agent
  module Screens
    class NormalizeDiscovery < BaseService
      class Invalid < StandardError; end

      Pair = Data.define(:mac_address, :ip_address)
      MAC_PATTERNS = [
        /\A(?:[0-9a-f]{2}[:-]){5}[0-9a-f]{2}\z/i,
        /\A[0-9a-f]{12}\z/i,
        /\A[0-9a-f]{4}(?:\.[0-9a-f]{4}){2}\z/i
      ].freeze

      def initialize(screens:)
        @screens = screens
      end

      def call
        raise Invalid unless screens.is_a?(Array)

        pairs = screens.map { |row| pair(row.to_h.deep_stringify_keys) }.uniq
        raise Invalid unless unique_mapping?(pairs, &:mac_address)
        raise Invalid unless unique_mapping?(pairs, &:ip_address)

        pairs
      rescue NoMethodError, TypeError, IPAddr::InvalidAddressError
        raise Invalid
      end

      private

      attr_reader :screens

      def pair(row)
        Pair.new(mac_address: normalize_mac(row.fetch("mac_address")), ip_address: normalize_ip(row.fetch("ip_address")))
      end

      def normalize_mac(value)
        raw = value.to_s.strip
        raise Invalid unless MAC_PATTERNS.any? { |pattern| pattern.match?(raw) }

        raw.delete(":-.").downcase.scan(/../).join(":")
      end

      def normalize_ip(value)
        raw = value.to_s.strip
        raise Invalid if raw.include?("/")

        address = IPAddr.new(raw)
        raise Invalid unless address.ipv4?

        address
      end

      def unique_mapping?(pairs, &key)
        pairs.group_by(&key).values.all? { |group| group.one? }
      end
    end
  end
end
```

`pairs.uniq` удаляет точные повторы до проверки, поэтому группа больше одного
элемента всегда является конфликтом соответствия.

- [ ] **Step 4: Запустить spec**

Run:

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/agent/screens/normalize_discovery_spec.rb
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/domain/agent/screens/normalize_discovery.rb spec/domain/agent/screens/normalize_discovery_spec.rb
git commit -m "feat: validate discovered screen addresses"
```

### Task 3: Транзакционная синхронизация экранов

**Files:**
- Create: `app/domain/agent/screens/synchronize.rb`
- Create: `spec/domain/agent/screens/synchronize_spec.rb`

- [ ] **Step 1: Написать падающие domain specs**

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agent::Screens::Synchronize do
  let(:station) { create(:station, name: "Station", location: create(:location, name: "Mall")) }

  it "creates unknown screens in numeric IP order" do
    described_class.call(station:, screens: [
      { mac_address: "00:00:00:00:00:20", ip_address: "192.168.1.20" },
      { mac_address: "00:00:00:00:00:03", ip_address: "192.168.1.3" }
    ])

    expect(station.screens.order(:name).pluck(:name, :mac_address, :network_registered)).to eq([
      [ "Mall-Station-screen-1", "00:00:00:00:00:03", true ],
      [ "Mall-Station-screen-2", "00:00:00:00:00:20", true ]
    ])
  end

  it "updates by MAC, preserves the name, and unregisters missing screens" do
    found = create(:screen, station:, name: "Manual", mac_address: "aa:bb:cc:dd:ee:ff",
      ip_address: "192.168.1.8", network_registered: false)
    missing = create(:screen, station:, mac_address: "11:22:33:44:55:66",
      ip_address: "192.168.1.9", network_registered: true)

    described_class.call(station:, screens: [
      { mac_address: "aa:bb:cc:dd:ee:ff", ip_address: "192.168.1.18" }
    ])

    expect(found.reload.attributes.slice("name", "network_registered")).to eq(
      "name" => "Manual", "network_registered" => true
    )
    expect(found.ip_address).to eq(IPAddr.new("192.168.1.18"))
    expect(missing.reload.network_registered).to be(false)
  end

  it "unregisters every screen for a successful empty result" do
    screen = create(:screen, station:, network_registered: true)

    described_class.call(station:, screens: [])

    expect(screen.reload.network_registered).to be(false)
  end

  it "does not change records when normalization fails" do
    screen = create(:screen, station:, network_registered: true)

    expect {
      described_class.call(station:, screens: [
        { mac_address: "bad", ip_address: "192.168.1.10" }
      ])
    }.to raise_error(Agent::Screens::NormalizeDiscovery::Invalid)

    expect(screen.reload.network_registered).to be(true)
  end

  it "does not match the same MAC from another station" do
    foreign = create(:screen, mac_address: "aa:bb:cc:dd:ee:ff",
      ip_address: "192.168.2.10", network_registered: true)

    described_class.call(station:, screens: [
      { mac_address: "aa:bb:cc:dd:ee:ff", ip_address: "192.168.1.10" }
    ])

    expect(station.screens.sole.ip_address).to eq(IPAddr.new("192.168.1.10"))
    expect(foreign.reload.ip_address).to eq(IPAddr.new("192.168.2.10"))
  end
end
```

- [ ] **Step 2: Запустить spec и подтвердить отсутствие сервиса**

Run:

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/agent/screens/synchronize_spec.rb
```

Expected: FAIL with `uninitialized constant Agent::Screens::Synchronize`.

- [ ] **Step 3: Реализовать сервис синхронизации**

```ruby
# frozen_string_literal: true

module Agent
  module Screens
    class Synchronize < BaseService
      def initialize(station:, screens:)
        @station = station
        @pairs = NormalizeDiscovery.call(screens:)
      end

      def call
        station.with_lock do
          existing = station.screens.where.not(mac_address: nil).index_by { |screen| screen.mac_address.downcase }
          known_pairs, new_pairs = pairs.partition { |pair| existing.key?(pair.mac_address) }

          update_known(existing, known_pairs)
          unregister_missing(existing, known_pairs)
          create_new(new_pairs)
        end
      end

      private

      attr_reader :station, :pairs

      def update_known(existing, known_pairs)
        known_pairs.each do |pair|
          existing.fetch(pair.mac_address).update!(ip_address: pair.ip_address, network_registered: true)
        end
      end

      def unregister_missing(existing, known_pairs)
        found_ids = known_pairs.map { |pair| existing.fetch(pair.mac_address).id }
        station.screens.where.not(id: found_ids).update_all(network_registered: false, updated_at: Time.current)
      end

      def create_new(new_pairs)
        new_pairs.sort_by { |pair| pair.ip_address.to_i }.each do |pair|
          station.screens.create!(
            name: station.next_screen_name,
            mac_address: pair.mac_address,
            ip_address: pair.ip_address,
            network_registered: true
          )
        end
      end
    end
  end
end
```

При реализации проверить, что `station.screens` после `create!` отражает
новый экран для следующего `next_screen_name`. Если association не загружена,
вызвать `station.screens.reset` после каждого создания.

- [ ] **Step 4: Запустить domain specs**

Run:

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/agent/screens
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/domain/agent/screens/synchronize.rb spec/domain/agent/screens/synchronize_spec.rb
git commit -m "feat: synchronize station screens from discovery"
```

### Task 4: Идемпотентная постановка `fetch_screens`

**Files:**
- Create: `app/domain/agent/commands/fetch_screens.rb`
- Create: `spec/domain/agent/commands/fetch_screens_spec.rb`
- Create: `app/controllers/admin/station_screen_refreshes_controller.rb`
- Modify: `config/routes.rb`
- Modify: `config/locales/mediateca.ru.yml`
- Modify: `config/locales/mediateca.en.yml`
- Modify: `spec/requests/admin/stations_spec.rb`

- [ ] **Step 1: Написать падающие service и request specs**

Создать service spec:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agent::Commands::FetchScreens do
  let(:station) { create(:station) }

  it "creates one station command" do
    result = described_class.call(station:)

    expect(result).to be_created
    expect(result.command).to have_attributes(
      station: station, screen: nil, command_type: "fetch_screens", params: {}, status: "pending"
    )
  end

  it "reuses a pending command" do
    first = described_class.call(station:)
    second = described_class.call(station:)

    expect(second).not_to be_created
    expect(second.command).to eq(first.command)
    expect(station.agent_commands.where(command_type: "fetch_screens").count).to eq(1)
  end
end
```

В `spec/requests/admin/stations_spec.rb` добавить:

```ruby
it "queues one fetch_screens command from the station page" do
  station = create(:station, location:)

  expect {
    post admin_station_screen_refresh_path(station)
  }.to change { station.agent_commands.count }.by(1)

  expect(response).to have_http_status(:see_other)
  expect(response).to redirect_to(admin_station_path(station))
  expect(station.agent_commands.sole).to have_attributes(command_type: "fetch_screens", screen_id: nil)

  expect {
    post admin_station_screen_refresh_path(station)
  }.not_to change { station.agent_commands.count }
end
```

- [ ] **Step 2: Запустить specs и подтвердить отсутствие route/service**

Run:

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/agent/commands/fetch_screens_spec.rb spec/requests/admin/stations_spec.rb
```

Expected: FAIL with missing constant/route.

- [ ] **Step 3: Реализовать сервис**

```ruby
# frozen_string_literal: true

module Agent
  module Commands
    class FetchScreens < BaseService
      Result = Data.define(:command, :created) do
        def created? = created
      end

      def initialize(station:)
        @station = station
      end

      def call
        return Result.new(command: pending, created: false) if pending

        Result.new(command: create_command, created: true)
      rescue ActiveRecord::RecordNotUnique
        Result.new(command: pending!, created: false)
      end

      private

      attr_reader :station

      def pending
        station.agent_commands.pending.find_by(command_type: "fetch_screens")
      end

      def pending!
        station.agent_commands.pending.find_by!(command_type: "fetch_screens")
      end

      def create_command
        station.agent_commands.create!(
          screen: nil,
          public_id: "cmd_#{SecureRandom.uuid}",
          command_type: "fetch_screens",
          params: {},
          issued_at: Time.current
        )
      end
    end
  end
end
```

- [ ] **Step 4: Добавить route и admin controller**

В `resources :stations`:

```ruby
resource :screen_refresh, only: :create, controller: "station_screen_refreshes"
```

Создать контроллер:

```ruby
# frozen_string_literal: true

module Admin
  class StationScreenRefreshesController < Admin::BaseController
    def create
      station = Station.find(params[:station_id])
      result = Agent::Commands::FetchScreens.call(station:)
      key = result.created? ? "queued" : "already_queued"

      redirect_to admin_station_path(station),
        notice: t("admin.stations.screen_refresh.#{key}"),
        status: :see_other
    end
  end
end
```

- [ ] **Step 5: Добавить flash-переводы**

Под `admin.stations` в русском locale:

```yaml
screen_refresh:
  queued: Обновление экранов поставлено в очередь.
  already_queued: Обновление экранов уже ожидает выполнения.
```

В английском locale:

```yaml
screen_refresh:
  queued: Screen refresh queued.
  already_queued: A screen refresh is already pending.
```

- [ ] **Step 6: Запустить specs**

Run:

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/agent/commands/fetch_screens_spec.rb spec/requests/admin/stations_spec.rb
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add app/domain/agent/commands/fetch_screens.rb app/controllers/admin/station_screen_refreshes_controller.rb config/routes.rb config/locales/mediateca.ru.yml config/locales/mediateca.en.yml spec/domain/agent/commands/fetch_screens_spec.rb spec/requests/admin/stations_spec.rb
git commit -m "feat: queue station screen refresh command"
```

### Task 5: Приём результата и атомарный ack

**Files:**
- Modify: `app/domain/agent/commands/acknowledge.rb`
- Modify: `app/controllers/api/agent/v1/command_results_controller.rb`
- Modify: `spec/requests/api/agent/v1/commands_spec.rb`
- Modify: `spec/requests/api/agent/v1/command_results_spec.rb`

- [ ] **Step 1: Написать падающие request specs**

В commands spec добавить:

```ruby
it "returns a station-level fetch_screens command with a null screen_id" do
  command = create(:agent_command, :fetch_screens, station:)

  get "/api/agent/v1/commands", headers: agent_authorization_headers(token), as: :json

  expect(response.parsed_body.fetch("commands")).to include(
    "id" => command.public_id,
    "screen_id" => nil,
    "type" => "fetch_screens",
    "params" => {},
    "issued_at" => command.issued_at.utc.iso8601
  )
end
```

В command results spec добавить:

```ruby
it "synchronizes screens before acknowledging fetch_screens" do
  command = create(:agent_command, :fetch_screens, station:, public_id: "cmd_fetch")

  post_results([
    {
      command_id: command.public_id,
      ok: true,
      error: nil,
      finished_at: "2026-10-09T11:01:02Z",
      result: {
        screens: [
          { mac_address: "aa:bb:cc:dd:ee:ff", ip_address: "192.168.1.10" }
        ]
      }
    }
  ])

  expect(response).to have_http_status(:ok)
  expect(command.reload).to be_acked
  expect(station.screens.sole).to have_attributes(
    mac_address: "aa:bb:cc:dd:ee:ff", network_registered: true
  )
end

it "leaves the command pending and rolls back screens for an invalid discovery result" do
  command = create(:agent_command, :fetch_screens, station:, public_id: "cmd_invalid_fetch")

  post_results([
    {
      command_id: command.public_id,
      ok: true,
      error: nil,
      finished_at: "2026-10-09T11:01:02Z",
      result: { screens: [ { mac_address: "bad", ip_address: "192.168.1.10" } ] }
    }
  ])

  expect(response).to have_http_status(:unprocessable_content)
  expect(response.parsed_body).to eq("error" => "invalid_result")
  expect(command.reload).to be_pending
  expect(station.screens).to be_empty
end

it "acks a failed fetch without changing registration" do
  screen = create(:screen, station:, network_registered: true)
  command = create(:agent_command, :fetch_screens, station:, public_id: "cmd_failed_fetch")

  post_results([
    {
      command_id: command.public_id,
      ok: false,
      error: "lease_file_unreadable",
      finished_at: "2026-10-09T11:01:02Z"
    }
  ])

  expect(response).to have_http_status(:ok)
  expect(command.reload).to be_acked
  expect(screen.reload.network_registered).to be(true)
end
```

- [ ] **Step 2: Запустить request specs и подтвердить 422/отсутствие payload**

Run:

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/requests/api/agent/v1/commands_spec.rb spec/requests/api/agent/v1/command_results_spec.rb
```

Expected: new success spec FAIL because strong parameters drop `result`.

- [ ] **Step 3: Разрешить вложенный result**

В `CommandResultsController#result_rows`:

```ruby
row.permit(
  :command_id,
  :ok,
  :error,
  :finished_at,
  result: { screens: [ :mac_address, :ip_address ] }
).to_h
```

- [ ] **Step 4: Встроить синхронизацию в транзакцию ack**

В `Acknowledge#apply` после проверок `nil?`/`acked?`, но до `command.update!`:

```ruby
synchronize_screens(command, row)
```

Добавить:

```ruby
def synchronize_screens(command, row)
  return unless command.command_type == "fetch_screens"
  return unless row["ok"]

  screens = row.dig("result", "screens")
  raise Invalid unless screens.is_a?(Array)

  Agent::Screens::Synchronize.call(station:, screens:)
rescue Agent::Screens::NormalizeDiscovery::Invalid
  raise Invalid
end
```

В `normalize_row` сохранить разрешённый payload:

```ruby
"result" => data["result"]
```

Текущий внешний `AgentCommand.transaction` должен охватывать и синхронизацию,
и `command.update!`; отдельный rescue `ActiveRecord::RecordInvalid` не
добавлять.

- [ ] **Step 5: Запустить API specs**

Run:

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/requests/api/agent/v1/commands_spec.rb spec/requests/api/agent/v1/command_results_spec.rb
```

Expected: PASS, включая прежние команды.

- [ ] **Step 6: Commit**

```bash
git add app/domain/agent/commands/acknowledge.rb app/controllers/api/agent/v1/command_results_controller.rb spec/requests/api/agent/v1/commands_spec.rb spec/requests/api/agent/v1/command_results_spec.rb
git commit -m "feat: process discovered screens from command results"
```

### Task 6: Список экранов и кнопка в админке

**Files:**
- Modify: `app/controllers/admin/stations_controller.rb`
- Modify: `app/views/admin/stations/show.html.erb`
- Modify: `config/locales/mediateca.ru.yml`
- Modify: `config/locales/mediateca.en.yml`
- Modify: `spec/requests/admin/stations_spec.rb`

- [ ] **Step 1: Добавить падающий UI spec**

```ruby
it "shows station screens and the refresh action" do
  station = create(:station, location:)
  screen = create(:screen, station:, name: "Lobby TV",
    mac_address: "aa:bb:cc:dd:ee:ff", ip_address: "192.168.1.10",
    network_registered: true)

  get admin_station_path(station)

  expect(response).to have_http_status(:ok)
  expect(response.body).to include(I18n.t("admin.stations.screens.title"))
  expect(response.body).to include(I18n.t("admin.stations.screens.refresh"))
  expect(response.body).to include(admin_screen_path(screen))
  expect(response.body).to include("Lobby TV", "aa:bb:cc:dd:ee:ff", "192.168.1.10")
end
```

- [ ] **Step 2: Запустить UI spec и подтвердить отсутствие секции**

Run:

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/requests/admin/stations_spec.rb
```

Expected: FAIL because translations and section are absent.

- [ ] **Step 3: Подготовить список в controller**

После загрузки `@station` в `show`:

```ruby
@screens = @station.screens.sort_by { |screen| screen.name.downcase }
```

- [ ] **Step 4: Добавить Flowbite-секцию перед телеметрией**

```erb
<div class="mt-6 bg-white border border-gray-200 rounded-lg p-6">
  <div class="mb-4 flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
    <h2 class="text-lg font-medium text-gray-900"><%= t("admin.stations.screens.title") %></h2>
    <%= button_to t("admin.stations.screens.refresh"),
          admin_station_screen_refresh_path(@station),
          method: :post,
          class: admin_secondary_button_class %>
  </div>

  <% if @screens.any? %>
    <div class="relative overflow-x-auto">
      <table class="w-full text-sm text-left text-gray-500">
        <thead class="text-xs text-gray-700 uppercase bg-gray-50">
          <tr>
            <th class="px-4 py-3"><%= Screen.human_attribute_name(:name) %></th>
            <th class="px-4 py-3"><%= Screen.human_attribute_name(:mac_address) %></th>
            <th class="px-4 py-3"><%= Screen.human_attribute_name(:ip_address) %></th>
            <th class="px-4 py-3"><%= Screen.human_attribute_name(:network_registered) %></th>
          </tr>
        </thead>
        <tbody>
          <% @screens.each do |screen| %>
            <tr class="bg-white border-b">
              <td class="px-4 py-3"><%= link_to screen.name, admin_screen_path(screen), class: "font-medium text-blue-600 hover:underline" %></td>
              <td class="px-4 py-3"><%= screen.mac_address.presence || t("admin.crud.none") %></td>
              <td class="px-4 py-3"><%= screen.ip_address&.to_s || t("admin.crud.none") %></td>
              <td class="px-4 py-3"><%= admin_boolean(screen.network_registered) %></td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
  <% else %>
    <p class="text-sm text-gray-500"><%= t("admin.stations.screens.empty") %></p>
  <% end %>
</div>
```

- [ ] **Step 5: Добавить русские и английские переводы**

Под `admin.stations`:

```yaml
screens:
  title: Экраны станции
  refresh: Обновить экраны
  empty: У станции пока нет экранов.
```

```yaml
screens:
  title: Station screens
  refresh: Refresh screens
  empty: This station has no screens yet.
```

Ключи `screen_refresh` уже созданы в Task 4. Под
`activerecord.attributes.screen` добавить:

```yaml
mac_address: MAC-адрес
ip_address: IP-адрес
network_registered: Зарегистрирован в сети станции
```

```yaml
mac_address: MAC address
ip_address: IP address
network_registered: Registered on station network
```

- [ ] **Step 6: Запустить admin specs**

Run:

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/requests/admin/stations_spec.rb
```

Expected: PASS, включая постановку первой и повторной команды.

- [ ] **Step 7: Commit**

```bash
git add app/controllers/admin/stations_controller.rb app/views/admin/stations/show.html.erb config/locales/mediateca.ru.yml config/locales/mediateca.en.yml spec/requests/admin/stations_spec.rb
git commit -m "feat: manage station screens from admin"
```

### Task 7: Полная проверка и актуализация аннотаций

**Files:**
- Modify if generated: schema comments in `app/models/*.rb`, `spec/factories/*.rb`, `spec/models/*.rb`
- Verify: all changed files

- [ ] **Step 1: Обновить schema annotations**

Run:

```bash
docker compose exec -e RAILS_ENV=test web bundle exec annotaterb models
```

Expected: comments show nullable `agent_commands.screen_id` and three new
screen columns/indexes. Проверить diff и не принимать несвязанные изменения.

- [ ] **Step 2: Запустить целевые наборы вместе**

Run:

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/models/screen_spec.rb spec/models/agent_command_spec.rb spec/domain/agent/screens spec/domain/agent/commands/fetch_screens_spec.rb spec/requests/api/agent/v1/commands_spec.rb spec/requests/api/agent/v1/command_results_spec.rb spec/requests/admin/stations_spec.rb
```

Expected: PASS.

- [ ] **Step 3: Запустить полный обязательный CI**

Run:

```bash
docker compose exec -e RAILS_ENV=test web bin/ci
```

Expected: RuboCop, RSpec, bundler-audit, importmap audit и Brakeman проходят.

- [ ] **Step 4: Проверить итоговый diff**

Run:

```bash
git diff --check
git status --short
```

Expected: no whitespace errors; только файлы этой функции.

- [ ] **Step 5: Зафиксировать финальные generated changes**

```bash
git add db/schema.rb app/models spec/factories spec/models
git commit -m "chore: refresh schema annotations"
```

Если Step 1 не изменил файлы, этот коммит пропустить.
