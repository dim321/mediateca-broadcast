# Привязка экранов в config агента — план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Отдавать в `GET /api/agent/v1/config` для каждого экрана станции `adb_serial`, `mac` и общий `stream_port` ленты эфира, не меняя пакет v2.

**Architecture:** `Agent::ConfigBuilder` под `station.with_lock` считает дайджест ленты каждого привязанного экрана и сверяет его с реестром `station_stream_channels`. Порт принадлежит дайджесту, не строке `screens`. Неполный горизонт плейлистов реестр не меняет. Сборка config только читает плейлисты и не ставит `GenerateForDateJob`.

**Tech Stack:** Ruby 4.0.2, Rails 8.1, PostgreSQL 18, RSpec, FactoryBot.

**Репозиторий:** только `mediateca-broadcast`. `mediateca-station` не трогать. Спека: `docs/superpowers/specs/2026-10-16-hub-screen-wiring-design.md`.

---

## Карта файлов

Новые файлы:

- `db/migrate/20261016143000_create_station_stream_channels.rb` — реестр канал → порт.
- `app/models/station_stream_channel.rb` — модель, пул `8091..8190`.
- `spec/models/station_stream_channel_spec.rb` — ограничения таблицы.
- `spec/factories/station_stream_channels.rb` — фабрика реестра.
- `app/domain/agent/screen_wiring.rb` — кого считать привязанным и как собрать `adb_serial` / `mac`.
- `app/domain/agent/screen_timelines.rb` — слоты горизонта и SHA256 канонического JSON.
- `app/domain/agent/stream_channels/reconcile.rb` — выдача и заморозка портов.
- `spec/domain/agent/screen_timelines_spec.rb` — состав ленты и дайджест.
- `spec/domain/agent/stream_channels/reconcile_spec.rb` — пул, идемпотентность, неполный горизонт.
- `spec/support/screen_wiring_helpers.rb` — станция, экран и плейлисты горизонта для спеков.

Изменяемые файлы:

- `app/models/station.rb` — `has_many :stream_channels`.
- `app/domain/agent/config_builder.rb` — поля привязки рядом с `id` / `name` / `orientation`.
- `spec/domain/agent/config_builder_spec.rb` — случаи 1–9 спеки.
- `spec/requests/api/agent/v1/configs_spec.rb` — JSON config.
- `spec/requests/api/agent/v2/packages_spec.rb` — в пакете нет полей привязки.
- `spec/requests/admin/stations_spec.rb` — превью show уже печатает `@agent_config`.
- `db/schema.rb` и schema-комментарии — пишутся `db:migrate` и `annotaterb`.

Не менять: `Playlists::PackageFromPlaylists`, `Agent::PackageBuilder`, `Agent::Screens::Synchronize`, маршруты, вьюху станции, локали. Формы порта нет.

Команды ниже выполнять из корня `mediateca-broadcast`. На хосте `rspec` и `bin/ci` не запускать.

---

### Task 1: Реестр каналов

**Files:**
- Create: `db/migrate/20261016143000_create_station_stream_channels.rb`
- Create: `app/models/station_stream_channel.rb`
- Create: `spec/models/station_stream_channel_spec.rb`
- Create: `spec/factories/station_stream_channels.rb`
- Modify: `app/models/station.rb`
- Generated: `db/schema.rb`

- [ ] **Step 1: Написать падающий model spec**

Создать `spec/models/station_stream_channel_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe StationStreamChannel, type: :model do
  it "stores one digest and one port per station inside the Voxel pool" do
    channel = create(:station_stream_channel, stream_port: 8091)

    expect(channel.stream_port).to eq(8091)
    expect(channel.timeline_digest).to match(/\A[0-9a-f]{64}\z/)
  end

  it "rejects a duplicate digest or port on the same station" do
    channel = create(:station_stream_channel, stream_port: 8091)
    same_digest = build(
      :station_stream_channel,
      station: channel.station,
      timeline_digest: channel.timeline_digest,
      stream_port: 8092
    )
    same_port = build(
      :station_stream_channel,
      station: channel.station,
      stream_port: 8091
    )

    expect(same_digest).not_to be_valid
    expect(same_port).not_to be_valid
    expect(build(:station_stream_channel, stream_port: 8091)).to be_valid
  end

  it "rejects a port outside 8091..8190 in the model and in the database" do
    channel = create(:station_stream_channel, stream_port: 8091)
    channel.stream_port = 8090

    expect(channel).not_to be_valid
    expect {
      channel.update_columns(stream_port: 8191)
    }.to raise_error(ActiveRecord::StatementInvalid)
  end

  it "cascades when the station row is deleted" do
    foreign_key = described_class.connection.foreign_keys("station_stream_channels")
      .find { |key| key.to_table == "stations" }

    expect(foreign_key.on_delete.to_s).to eq("cascade")
  end
end
```

Создать `spec/factories/station_stream_channels.rb`:

```ruby
# frozen_string_literal: true

FactoryBot.define do
  factory :station_stream_channel do
    station
    sequence(:timeline_digest) { |n| Digest::SHA256.hexdigest("timeline-#{n}") }
    sequence(:stream_port) { |n| 8091 + ((n - 1) % StationStreamChannel::PORT_POOL.size) }
  end
end
```

Порт по умолчанию крутится внутри `8091..8190`. В спеках, где номер важен, передавать `stream_port:` явно. На одной станции сотый порт по умолчанию совпадёт с первым: для таких примеров порт задавать руками.

- [ ] **Step 2: Запустить spec и убедиться, что он падает**

Run:

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/models/station_stream_channel_spec.rb
```

Expected: FAIL. Нет таблицы `station_stream_channels` или константы `StationStreamChannel`.

- [ ] **Step 3: Добавить миграцию, модель и связь станции**

Создать `db/migrate/20261016143000_create_station_stream_channels.rb`:

```ruby
# frozen_string_literal: true

class CreateStationStreamChannels < ActiveRecord::Migration[8.1]
  def change
    create_table :station_stream_channels do |t|
      t.references :station, null: false, foreign_key: { on_delete: :cascade }
      t.string :timeline_digest, null: false, limit: 64
      t.integer :stream_port, null: false

      t.timestamps
    end

    add_index :station_stream_channels, [ :station_id, :timeline_digest ], unique: true
    add_index :station_stream_channels, [ :station_id, :stream_port ], unique: true
    add_check_constraint :station_stream_channels,
      "stream_port BETWEEN 8091 AND 8190",
      name: "station_stream_channels_stream_port_in_pool"
  end
end
```

Создать `app/models/station_stream_channel.rb`:

```ruby
# frozen_string_literal: true

class StationStreamChannel < ApplicationRecord
  PORT_POOL = (8091..8190).freeze

  belongs_to :station, inverse_of: :stream_channels

  validates :timeline_digest, presence: true,
    uniqueness: { scope: :station_id },
    format: { with: /\A[0-9a-f]{64}\z/ }
  validates :stream_port, inclusion: { in: PORT_POOL }, uniqueness: { scope: :station_id }
end
```

В `app/models/station.rb` сразу после `has_many :playlists` добавить:

```ruby
  has_many :stream_channels, class_name: "StationStreamChannel", dependent: :delete_all, inverse_of: :station
```

`ransackable_associations` не расширять: в админке реестр не ищется.

- [ ] **Step 4: Накатить миграцию и обновить аннотации**

Run:

```bash
docker compose exec -e RAILS_ENV=test web bin/rails db:migrate
docker compose exec -e RAILS_ENV=test web bundle exec annotaterb models StationStreamChannel Station
```

Expected: в `db/schema.rb` есть `create_table "station_stream_channels"` с двумя unique-индексами, FK `ON DELETE CASCADE` и check `stream_port BETWEEN 8091 AND 8190`. Annotate дописывает schema comment в модель, фабрику и model spec. Эти комментарии коммитить.

- [ ] **Step 5: Запустить spec и убедиться, что он проходит**

Run:

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/models/station_stream_channel_spec.rb
```

Expected: 4 examples, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add db/migrate/20261016143000_create_station_stream_channels.rb db/schema.rb \
  app/models/station_stream_channel.rb app/models/station.rb \
  spec/models/station_stream_channel_spec.rb spec/factories/station_stream_channels.rb
git commit -m "$(cat <<'EOF'
feat: add a per-station registry of timeline stream ports

The Voxel port belongs to a timeline digest so screens that share an air timeline can share one broadcast process.
EOF
)"
```

---

### Task 2: Лента экрана и её дайджест

**Files:**
- Create: `spec/support/screen_wiring_helpers.rb`
- Create: `app/domain/agent/screen_wiring.rb`
- Create: `app/domain/agent/screen_timelines.rb`
- Create: `spec/domain/agent/screen_timelines_spec.rb`

Канонический слот — ровно эти ключи, в этом порядке: `for_date`, `offset_seconds`, `starts_at`, `duration_seconds`, `media_id`. `JSON.generate` от массива таких хешей и есть канонический JSON. В него не входят `screen_ids`, URL блоба, `source_kind`, `media_plan_id`, `position`.

Порядок слотов: `for_date`, `offset_seconds`, `media_id`, затем `duration_seconds` и строка `starts_at`. Последние два поля — только тай-брейк сортировки, в JSON они и так есть. Сортировка зависит от содержимого слота, а не от `id` пункта: два экрана с одним набором слотов получают один дайджест, даже если пункты созданы в разном порядке.

Пустой массив слотов дайджеста не имеет (`nil`). Такой экран в хеш дайджестов не входит.

`starts_at` — `broadcast_day_starts_at + offset_seconds`, ISO8601. Если якоря нет, в JSON уходит `null`, ключ не выкидывается.

Горизонт полный, когда на каждую дату `Playlists::EnqueueRegen.horizon_dates(station)` есть плейлист `current`. Берутся только `station.playlists.current`. Пункт входит в ленту, если экран есть в `playlist_item_screens` и у медиа есть `broadcast_delivery_attachment`.

- [ ] **Step 1: Написать хелпер и падающий spec**

Создать `spec/support/screen_wiring_helpers.rb`:

```ruby
# frozen_string_literal: true

module ScreenWiringHelpers
  HORIZON_DAY = Date.new(2026, 10, 16)

  def wiring_time
    Time.utc(2026, 10, 16, 6, 0, 0)
  end

  def wiring_station
    location = create(:location, time_zone: "UTC")
    create(:station, location:, offline_cache_hours: 24)
  end

  def wired_screen(station, ip:, mac: "78:53:33:4b:2c:29", **attributes)
    create(
      :screen,
      station:,
      network_registered: true,
      ip_address: ip,
      mac_address: mac,
      **attributes
    )
  end

  def horizon_playlist(station, for_date, anchor_hour: 2)
    station.playlists.current.find_by(for_date:) || create(
      :playlist,
      station:,
      for_date:,
      broadcast_day_starts_at: Time.utc(for_date.year, for_date.month, for_date.day, anchor_hour, 0, 0)
    )
  end

  def cover_horizon(station)
    [ HORIZON_DAY, HORIZON_DAY + 1 ].map { |date| horizon_playlist(station, date) }
  end

  def add_slot(playlist, screen, asset:, offset_seconds: 0, duration_seconds: 10, source_kind: "filler")
    position = playlist.items.maximum(:position).to_i + 1
    create(
      :playlist_item,
      playlist:,
      media_asset: asset,
      position:,
      offset_seconds:,
      duration_seconds:,
      source_kind:
    ).tap do |item|
      item.screens = [ screen ]
      item.save!
    end
  end

  def cover_horizon_with_slot(station, screen, asset:, offset_seconds: 0, duration_seconds: 10)
    cover_horizon(station).map do |playlist|
      add_slot(playlist, screen, asset:, offset_seconds:, duration_seconds:)
      playlist
    end
  end
end

RSpec.configure do |config|
  config.include ScreenWiringHelpers
end
```

`offline_cache_hours: 24` и полночь UTC 2026-10-16 дают горизонт 16 и 17 октября. `cover_horizon` создаёт пустые `current` на обе даты. `cover_horizon_with_slot` кладёт один и тот же слот на каждую дату.

Создать `spec/domain/agent/screen_timelines_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agent::ScreenTimelines do
  include ActiveSupport::Testing::TimeHelpers

  around do |example|
    travel_to(wiring_time, &example)
  end

  it "hashes the delivery slots a wired screen will actually show" do
    station = wiring_station
    screen = wired_screen(station, ip: "192.168.33.182")
    asset = create(:media_asset, :ready, :with_png_file)
    cover_horizon_with_slot(station, screen, asset:)

    result = described_class.call(station:)

    expect(result.complete).to be(true)
    expect(result.digests_by_screen_id.keys).to eq([ screen.id ])
    expect(result.digests_by_screen_id[screen.id]).to eq(
      Digest::SHA256.hexdigest(JSON.generate(expected_slots(asset)))
    )
  end

  it "ignores screens that are not on the network and items without a delivery attachment" do
    station = wiring_station
    wired = wired_screen(station, ip: "192.168.33.182")
    create(:screen, station:, network_registered: false, ip_address: "192.168.33.183")
    png = create(:media_asset, :ready, :with_png_file)
    video = create(:media_asset, :ready, :with_mp4_file)
    playlists = cover_horizon_with_slot(station, wired, asset: png)
    playlists.each do |playlist|
      add_slot(playlist, wired, asset: video, offset_seconds: 30)
    end

    result = described_class.call(station:)

    expect(result.digests_by_screen_id.keys).to eq([ wired.id ])
    expect(result.digests_by_screen_id[wired.id]).to eq(
      Digest::SHA256.hexdigest(JSON.generate(expected_slots(png)))
    )
  end

  it "returns no digest for an empty timeline and reports an incomplete horizon" do
    station = wiring_station
    screen = wired_screen(station, ip: "192.168.33.182")
    horizon_playlist(station, HORIZON_DAY)

    result = described_class.call(station:)

    expect(result.complete).to be(false)
    expect(result.digests_by_screen_id).to eq({})
    expect(screen).to be_persisted
  end

  it "uses a null starts_at when the playlist has no broadcast-day anchor" do
    station = wiring_station
    screen = wired_screen(station, ip: "192.168.33.182")
    asset = create(:media_asset, :ready, :with_png_file)
    playlist = create(:playlist, station:, for_date: HORIZON_DAY, broadcast_day_starts_at: nil)
    create(:playlist, station:, for_date: HORIZON_DAY + 1, broadcast_day_starts_at: nil)
    add_slot(playlist, screen, asset:)

    result = described_class.call(station:)
    slots = expected_slots(asset)
    slots.first[:starts_at] = nil
    slots.slice!(1, 1)

    expect(result.digests_by_screen_id[screen.id]).to eq(Digest::SHA256.hexdigest(JSON.generate(slots)))
  end

  def expected_slots(asset)
    [ HORIZON_DAY, HORIZON_DAY + 1 ].map do |date|
      {
        for_date: date.iso8601,
        offset_seconds: 0,
        starts_at: Time.utc(date.year, date.month, date.day, 2, 0, 0).iso8601,
        duration_seconds: 10,
        media_id: asset.id
      }
    end
  end
end
```

Четвёртый пример оставляет слот только на 16 октября: у 17-го плейлист есть, пунктов для экрана нет. `starts_at` этого слота — `null`.

- [ ] **Step 2: Запустить spec и убедиться, что он падает**

Run:

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/agent/screen_timelines_spec.rb
```

Expected: FAIL с `uninitialized constant Agent::ScreenTimelines`.

- [ ] **Step 3: Реализовать привязку и сбор ленты**

Создать `app/domain/agent/screen_wiring.rb`:

```ruby
# frozen_string_literal: true

module Agent
  module ScreenWiring
    ADB_PORT = 5555

    module_function

    def wired?(screen)
      screen.network_registered? && ipv4_host?(screen.ip_address)
    end

    def adb_serial(screen)
      host = screen.ip_address.to_s.split("/").first
      return if host.blank?

      "#{host}:#{ADB_PORT}"
    end

    def mac(screen)
      screen.mac_address&.to_s.presence
    end

    def ipv4_host?(ip)
      return false if ip.blank?

      address = ip.is_a?(IPAddr) ? ip : IPAddr.new(ip.to_s.split("/").first)
      address.ipv4? && address.prefix == 32
    rescue IPAddr::InvalidAddressError, IPAddr::InvalidPrefixError
      false
    end
  end
end
```

Создать `app/domain/agent/screen_timelines.rb`:

```ruby
# frozen_string_literal: true

module Agent
  class ScreenTimelines < BaseService
    Result = Data.define(:complete, :digests_by_screen_id)

    def initialize(station:)
      @station = station
    end

    def call
      dates = Playlists::EnqueueRegen.horizon_dates(station)
      playlists = load_playlists(dates)
      Result.new(
        complete: dates.all? { |date| playlists.any? { |playlist| playlist.for_date == date } },
        digests_by_screen_id: digests_for(playlists)
      )
    end

    private

    attr_reader :station

    def load_playlists(dates)
      station.playlists.current.where(for_date: dates)
        .includes(items: [ :screens, { media_asset: [ { file_attachment: :blob }, { broadcast_file_attachment: :blob } ] } ])
        .order(:for_date, :id)
        .to_a
    end

    def digests_for(playlists)
      station.screens.select { |screen| ScreenWiring.wired?(screen) }.each_with_object({}) do |screen, digests|
        digest = digest_for(slots_for(screen, playlists))
        digests[screen.id] = digest if digest
      end
    end

    def slots_for(screen, playlists)
      playlists.flat_map { |playlist| slots_from(playlist, screen) }
        .sort_by { |slot| [ slot[:for_date], slot[:offset_seconds], slot[:media_id], slot[:duration_seconds], slot[:starts_at].to_s ] }
    end

    def slots_from(playlist, screen)
      playlist.items.sort_by(&:position).filter_map do |item|
        next unless item.screens.any? { |candidate| candidate.id == screen.id }
        next unless item.media_asset.broadcast_delivery_attachment

        anchor = playlist.broadcast_day_starts_at
        starts_at = anchor + item.offset_seconds.seconds if anchor
        {
          for_date: playlist.for_date.iso8601,
          offset_seconds: item.offset_seconds,
          starts_at: starts_at&.iso8601,
          duration_seconds: item.duration_seconds,
          media_id: item.media_asset_id
        }
      end
    end

    def digest_for(slots)
      return if slots.empty?

      Digest::SHA256.hexdigest(JSON.generate(slots))
    end
  end
end
```

`ScreenTimelines` не вызывает `Playlists::PackageFromPlaylists` и `Playlists::EnqueueRegen.call`. `horizon_dates` — чистая функция от часов кеша и часового пояса локации.

- [ ] **Step 4: Запустить spec и убедиться, что он проходит**

Run:

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/agent/screen_timelines_spec.rb
```

Expected: 4 examples, 0 failures.

Если RuboCop ругнётся на длину `sort_by`, вынести ключ в метод `slot_sort_key(slot)`. Состав ключа не менять.

- [ ] **Step 5: Commit**

```bash
git add spec/support/screen_wiring_helpers.rb app/domain/agent/screen_wiring.rb \
  app/domain/agent/screen_timelines.rb spec/domain/agent/screen_timelines_spec.rb
git commit -m "$(cat <<'EOF'
feat: digest the on-air timeline a wired screen will show

Screens with the same delivery slots share a digest, and a missing horizon day stays visible to the config builder.
EOF
)"
```

---

### Task 3: Назначение портов

**Files:**
- Create: `app/domain/agent/stream_channels/reconcile.rb`
- Create: `spec/domain/agent/stream_channels/reconcile_spec.rb`

Контракт `Agent::StreamChannels::Reconcile.call(station:, digests_by_screen_id:, horizon_complete:)`:

- Возвращает `{ screen_id => stream_port }` только для тех экранов, чей дайджест уже есть в реестре после вызова.
- Весь метод внутри `station.with_lock`.
- `horizon_complete: true`:
  1. Удалить строки, чьего `timeline_digest` нет среди значений `digests_by_screen_id`. Пустой хеш удаляет все строки станции. Не использовать `where.not(timeline_digest: [])`: в Rails пустой массив в `NOT IN` ведёт себя не так, как «удалить все».
  2. Дайджест, строка которого осталась, сохраняет свой `stream_port`. На меньший освободившийся порт его не переносить.
  3. Новые дайджесты брать в лексикографическом порядке hex-строки. Каждому — наименьший порт из `StationStreamChannel::PORT_POOL`, который ещё не занят. Так повторный poll с тем же набором лент стабилен.
  4. Если свободного порта нет, дайджест без строки. Исключение не бросать и чужой порт не отбирать.
- `horizon_complete: false`: не вставлять и не удалять строки. Вернуть порт, только если дайджест уже лежит в реестре.

- [ ] **Step 1: Написать падающий spec**

Создать `spec/domain/agent/stream_channels/reconcile_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agent::StreamChannels::Reconcile do
  def digest(seed)
    Digest::SHA256.hexdigest(seed)
  end

  it "keeps an existing port and gives the smallest free port to a new digest" do
    station = create(:station)
    kept = digest("kept")
    create(:station_stream_channel, station:, timeline_digest: digest("gone"), stream_port: 8091)
    create(:station_stream_channel, station:, timeline_digest: kept, stream_port: 8092)

    ports = described_class.call(
      station:,
      digests_by_screen_id: { 7 => kept, 8 => digest("fresh") },
      horizon_complete: true
    )

    expect(ports).to eq(7 => 8092, 8 => 8091)
    expect(station.stream_channels.order(:stream_port).pluck(:timeline_digest, :stream_port)).to eq(
      [ [ digest("fresh"), 8091 ], [ kept, 8092 ] ]
    )
  end

  it "assigns the same port to every screen that shares a digest" do
    station = create(:station)
    shared = digest("shared")

    ports = described_class.call(
      station:,
      digests_by_screen_id: { 7 => shared, 8 => shared },
      horizon_complete: true
    )

    expect(ports).to eq(7 => 8091, 8 => 8091)
    expect(station.stream_channels.count).to eq(1)
  end

  it "does not change rows when the same digests are reconciled again" do
    station = create(:station)
    shared = digest("shared")
    described_class.call(station:, digests_by_screen_id: { 7 => shared }, horizon_complete: true)

    expect {
      described_class.call(station:, digests_by_screen_id: { 7 => shared }, horizon_complete: true)
    }.not_to change { station.stream_channels.order(:id).pluck(:timeline_digest, :stream_port, :updated_at) }
  end

  it "does not insert or delete while the horizon is incomplete" do
    station = create(:station)
    stored = digest("stored")
    create(:station_stream_channel, station:, timeline_digest: stored, stream_port: 8094)

    matched = described_class.call(
      station:,
      digests_by_screen_id: { 7 => stored },
      horizon_complete: false
    )
    unmatched = described_class.call(
      station:,
      digests_by_screen_id: { 8 => digest("new") },
      horizon_complete: false
    )

    expect(matched).to eq(7 => 8094)
    expect(unmatched).to eq({})
    expect(station.stream_channels.pluck(:timeline_digest, :stream_port)).to eq([ [ stored, 8094 ] ])
  end

  it "leaves a new digest without a port when the pool is full" do
    station = create(:station)
    pool = StationStreamChannel::PORT_POOL.to_a
    kept = pool.index_with { |port| digest("kept-#{port}") }
    kept.each { |port, timeline_digest| create(:station_stream_channel, station:, timeline_digest:, stream_port: port) }
    digests = kept.values.each_with_index.to_h { |timeline_digest, index| [ index + 1, timeline_digest ] }
    digests[999] = digest("overflow")

    ports = described_class.call(station:, digests_by_screen_id: digests, horizon_complete: true)

    expect(ports[999]).to be_nil
    expect(ports[1]).to eq(8091)
    expect(station.stream_channels.count).to eq(100)
  end
end
```

- [ ] **Step 2: Запустить spec и убедиться, что он падает**

Run:

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/agent/stream_channels/reconcile_spec.rb
```

Expected: FAIL с `uninitialized constant Agent::StreamChannels::Reconcile`.

- [ ] **Step 3: Реализовать сверку реестра**

Создать `app/domain/agent/stream_channels/reconcile.rb`:

```ruby
# frozen_string_literal: true

module Agent
  module StreamChannels
    class Reconcile < BaseService
      def initialize(station:, digests_by_screen_id:, horizon_complete:)
        @station = station
        @digests_by_screen_id = digests_by_screen_id
        @horizon_complete = horizon_complete
      end

      def call
        station.with_lock do
          sync_registry! if horizon_complete
          ports_by_screen_id
        end
      end

      private

      attr_reader :station, :digests_by_screen_id, :horizon_complete

      def sync_registry!
        keep = digests_by_screen_id.values.uniq
        if keep.empty?
          station.stream_channels.delete_all
        else
          station.stream_channels.where.not(timeline_digest: keep).delete_all
        end
        assign_missing!(keep.sort)
      end

      def assign_missing!(keep)
        present = station.stream_channels.pluck(:timeline_digest)
        taken = station.stream_channels.pluck(:stream_port)
        (keep - present).each do |timeline_digest|
          port = (StationStreamChannel::PORT_POOL.to_a - taken).min
          break unless port

          station.stream_channels.create!(timeline_digest:, stream_port: port)
          taken << port
        end
      end

      def ports_by_screen_id
        by_digest = station.stream_channels.pluck(:timeline_digest, :stream_port).to_h
        digests_by_screen_id.each_with_object({}) do |(screen_id, timeline_digest), ports|
          port = by_digest[timeline_digest]
          ports[screen_id] = port if port
        end
      end
    end
  end
end
```

Порядок шагов внутри полного горизонта: сначала удалить неиспользуемые дайджесты, потом выдать новым наименьший свободный порт. Порт всё ещё используемого дайджеста при этом не сдвигается. Это и есть «уже выданные порты не отбираются»: отбирается только строка, которую больше никто из привязанных экранов не слушает.

- [ ] **Step 4: Запустить spec и убедиться, что он проходит**

Run:

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/agent/stream_channels/reconcile_spec.rb
```

Expected: 5 examples, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add app/domain/agent/stream_channels/reconcile.rb spec/domain/agent/stream_channels/reconcile_spec.rb
git commit -m "$(cat <<'EOF'
feat: assign stable Voxel ports to timeline digests

A repeated poll keeps the same ports, and an incomplete playlist horizon neither creates nor drops channels.
EOF
)"
```

---

### Task 4: Сборка config

**Files:**
- Modify: `app/domain/agent/config_builder.rb`
- Modify: `spec/domain/agent/config_builder_spec.rb`

`ConfigBuilder` берёт `station.with_lock`, внутри читает `ScreenTimelines` и вызывает `StreamChannels::Reconcile`. Вложенный `with_lock` в `Reconcile` на той же записи — savepoint, отдельное соединение не открывать.

Поля `adb_serial`, `mac`, `stream_port` добавляются к экрану, который и так есть в массиве. Ключ опускается, а не приходит как `null` или `""`.

| Ключ | Когда есть |
| --- | --- |
| `id`, `name`, `orientation` | всегда |
| `adb_serial` | `ScreenWiring.wired?` |
| `mac` | экран привязан и `mac_address` не пуст |
| `stream_port` | `Reconcile` вернул порт для `screen.id` |

`adb_serial` не зависит от MAC. `stream_port` не зависит от MAC. Пустая лента порта не даёт, но `adb_serial` у сетевого экрана остаётся. `tv_monitor` не меняется.

Существующие три примера `config_builder_spec.rb` не переписывать: их экраны не в сети, поэтому форма ответа прежняя.

- [ ] **Step 1: Дописать падающие примеры**

В `spec/domain/agent/config_builder_spec.rb` добавить `include ActiveJob::TestHelper` и `include ActiveSupport::Testing::TimeHelpers`. В конец `describe '.call'` добавить примеры. Хелпер `screen_named` — внизу того же `describe`, не в отдельном файле: имена экранов в ответе так проще отличить.

```ruby
    around do |example|
      travel_to(wiring_time) { example.run }
    end

    it "adds adb serial, canonical mac and a pool port for a wired screen with a timeline" do
      station = wiring_station
      screen = wired_screen(station, ip: "192.168.33.182", mac: "78-53-33-4B-2C-29", name: "Entrance")
      asset = create(:media_asset, :ready, :with_png_file)
      cover_horizon_with_slot(station, screen, asset:)

      payload = described_class.call(station:)

      expect(payload[:screens]).to eq([
        {
          id: screen.id,
          name: "Entrance",
          orientation: "landscape",
          adb_serial: "192.168.33.182:5555",
          mac: "78:53:33:4b:2c:29",
          stream_port: 8091
        }
      ])
    end

    it "strips an inet host prefix from the adb serial" do
      station = wiring_station
      screen = wired_screen(station, ip: "192.168.33.182")
      screen.update_columns(ip_address: "192.168.33.182/32")
      asset = create(:media_asset, :ready, :with_png_file)
      cover_horizon_with_slot(station, screen.reload, asset:)

      payload = described_class.call(station:)

      expect(payload[:screens].first[:adb_serial]).to eq("192.168.33.182:5555")
    end

    it "gives two screens with the same slots one port and splits different slots" do
      station = wiring_station
      shared_asset = create(:media_asset, :ready, :with_png_file)
      other_asset = create(:media_asset, :ready, :with_png_file)
      entrance = wired_screen(station, ip: "192.168.33.182", mac: "78:53:33:4b:2c:29", name: "Entrance")
      hall = wired_screen(station, ip: "192.168.33.183", mac: "78:53:33:4b:2c:30", name: "Hall")
      window = wired_screen(station, ip: "192.168.33.184", mac: "78:53:33:4b:2c:31", name: "Window")
      cover_horizon(station).each do |playlist|
        add_slot(playlist, entrance, asset: shared_asset)
        add_slot(playlist, hall, asset: shared_asset)
        add_slot(playlist, window, asset: other_asset, offset_seconds: 30)
      end

      screens = described_class.call(station:)[:screens].index_by { |item| item[:name] }

      expect(screens["Entrance"][:stream_port]).to eq(screens["Hall"][:stream_port])
      expect(screens["Window"][:stream_port]).not_to eq(screens["Entrance"][:stream_port])
      expect(station.stream_channels.count).to eq(2)
    end

    it "keeps an unwired screen in the list with only identity fields" do
      station = wiring_station
      wired = wired_screen(station, ip: "192.168.33.182", name: "Entrance")
      dark = create(:screen, station:, name: "Window", network_registered: false, ip_address: nil, mac_address: nil)
      asset = create(:media_asset, :ready, :with_png_file)
      cover_horizon_with_slot(station, wired, asset:)

      screens = described_class.call(station:)[:screens].index_by { |item| item[:name] }

      expect(screens["Window"]).to eq(id: dark.id, name: "Window", orientation: "landscape")
      expect(screens["Entrance"]).to have_key(:stream_port)
    end

    it "omits mac without a hardware address and omits the port for an empty timeline" do
      station = wiring_station
      silent = wired_screen(station, ip: "192.168.33.182", mac: nil, name: "Silent")
      cover_horizon(station)

      screen = described_class.call(station:)[:screens].first

      expect(screen[:adb_serial]).to eq("192.168.33.182:5555")
      expect(screen).not_to have_key(:mac)
      expect(screen).not_to have_key(:stream_port)
      expect(silent).to be_persisted
      expect(station.stream_channels).to be_empty
    end

    it "returns the same port on the second call and reuses it for a new screen with the known timeline" do
      station = wiring_station
      first = wired_screen(station, ip: "192.168.33.182", name: "Entrance")
      asset = create(:media_asset, :ready, :with_png_file)
      cover_horizon_with_slot(station, first, asset:)
      first_port = described_class.call(station:)[:screens].first[:stream_port]

      second_port = described_class.call(station:)[:screens].first[:stream_port]
      hall = wired_screen(station, ip: "192.168.33.183", mac: "78:53:33:4b:2c:30", name: "Hall")
      cover_horizon(station).each { |playlist| add_slot(playlist, hall, asset:) }
      ports = described_class.call(station:)[:screens].map { |item| item[:stream_port] }

      expect(second_port).to eq(first_port)
      expect(ports).to eq([ first_port, first_port ])
      expect(station.stream_channels.count).to eq(1)
    end

    it "does not open or close channels while a horizon day is missing" do
      station = wiring_station
      screen = wired_screen(station, ip: "192.168.33.182", name: "Entrance")
      asset = create(:media_asset, :ready, :with_png_file)
      cover_horizon(station)
      add_slot(horizon_playlist(station, HORIZON_DAY), screen, asset:)
      described_class.call(station:)
      station.playlists.current.find_by!(for_date: HORIZON_DAY + 1).update_columns(status: "superseded")
      stranger = wired_screen(station, ip: "192.168.33.183", mac: "78:53:33:4b:2c:30", name: "Hall")
      add_slot(horizon_playlist(station, HORIZON_DAY), stranger, asset: create(:media_asset, :ready, :with_png_file))

      screens = described_class.call(station:)[:screens].index_by { |item| item[:name] }

      expect(screens["Entrance"][:stream_port]).to eq(8091)
      expect(screens["Hall"]).not_to have_key(:stream_port)
      expect(station.stream_channels.pluck(:stream_port)).to eq([ 8091 ])
    end

    it "drops the channel once a complete horizon no longer uses its digest" do
      station = wiring_station
      screen = wired_screen(station, ip: "192.168.33.182")
      asset = create(:media_asset, :ready, :with_png_file)
      cover_horizon_with_slot(station, screen, asset:)
      described_class.call(station:)
      screen.update!(network_registered: false)

      payload = described_class.call(station:)

      expect(payload[:screens].first.keys).to eq(%i[id name orientation])
      expect(station.stream_channels).to be_empty
    end

    it "does not enqueue playlist generation when the horizon is incomplete" do
      station = wiring_station
      wired_screen(station, ip: "192.168.33.182")

      expect {
        described_class.call(station:)
      }.not_to have_enqueued_job(Playlists::GenerateForDateJob)
    end
```

Пример с неполным горизонтом специально кладёт слот только на 16 октября. Плейлист 17 октября пустой для этого экрана, поэтому его снятие с `current` не меняет дайджест: экран продолжает получать `8091`. Второй экран с новой лентой порт не получает, и строка реестра не удаляется. Если бы пропавшая дата содержала слоты, дайджест стал бы другим, ключ `stream_port` опустился бы, а старая строка всё равно осталась бы до полного горизонта. Порт ищется по дайджесту, отдельной колонки на `screens` нет.

`around { travel_to }` действует и на старые примеры. Им дата не важна: экраны без сети, плейлистов нет.

- [ ] **Step 2: Запустить spec и убедиться, что новые примеры падают**

Run:

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/agent/config_builder_spec.rb
```

Expected: старые три примера зелёные. Новые падают: в payload нет `adb_serial` / `stream_port`.

- [ ] **Step 3: Собрать payload в ConfigBuilder**

Заменить `app/domain/agent/config_builder.rb` целиком:

```ruby
# frozen_string_literal: true

module Agent
  class ConfigBuilder < BaseService
    def initialize(station:)
      @station = station
    end

    def call
      station.with_lock do
        timelines = ScreenTimelines.call(station:)
        ports = StreamChannels::Reconcile.call(
          station:,
          digests_by_screen_id: timelines.digests_by_screen_id,
          horizon_complete: timelines.complete
        )
        build_payload(ports)
      end
    end

    private

    attr_reader :station

    def build_payload(ports_by_screen_id)
      payload = {
        station_id: station.id,
        offline_cache_hours: station.offline_cache_hours,
        screens: station.screens.order(:id).map { |screen| screen_payload(screen, ports_by_screen_id) }
      }
      payload[:tv_monitor] = tv_monitor_payload if station.tv_monitor
      payload
    end

    def tv_monitor_payload
      monitor = station.tv_monitor
      {
        health_interval_seconds: monitor.health_interval_seconds,
        auto_restart_when_not_playing: monitor.auto_restart_when_not_playing,
        telemetry_interval_seconds: monitor.telemetry_interval_seconds
      }
    end

    def screen_payload(screen, ports_by_screen_id)
      payload = {
        id: screen.id,
        name: screen.name,
        orientation: screen.orientation
      }
      return payload unless ScreenWiring.wired?(screen)

      payload[:adb_serial] = ScreenWiring.adb_serial(screen)
      mac = ScreenWiring.mac(screen)
      payload[:mac] = mac if mac
      port = ports_by_screen_id[screen.id]
      payload[:stream_port] = port if port
      payload
    end
  end
end
```

- [ ] **Step 4: Запустить spec и убедиться, что он проходит**

Run:

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/agent/config_builder_spec.rb spec/domain/agent/screen_timelines_spec.rb spec/domain/agent/stream_channels/reconcile_spec.rb
```

Expected: все примеры зелёные, включая прежние `tv_monitor`.

Если пример «two screens» получит больше восьми `expect`, не объединять их обратно: лимит `RSpec/MultipleExpectations` — 8, в примере их три.

- [ ] **Step 5: Commit**

```bash
git add app/domain/agent/config_builder.rb spec/domain/agent/config_builder_spec.rb
git commit -m "$(cat <<'EOF'
feat: publish screen wiring on the agent config

The station learns which TV listens to which Voxel port, while a screen without a network identity stays in the list.
EOF
)"
```

---

### Task 5: HTTP-контракт config, пакета и превью

**Files:**
- Modify: `spec/requests/api/agent/v1/configs_spec.rb`
- Modify: `spec/requests/api/agent/v2/packages_spec.rb`
- Modify: `spec/requests/admin/stations_spec.rb`

Контроллеры и вьюху не менять. `Api::Agent::V1::ConfigsController` уже рендерит `ConfigBuilder`. `Admin::StationsController#show` уже кладёт тот же хеш в `@agent_config` и печатает его в `<pre>`.

- [ ] **Step 1: Написать падающие request-примеры**

В `spec/requests/api/agent/v1/configs_spec.rb` внутри `describe 'GET /api/agent/v1/config'` добавить:

```ruby
    it "returns wiring fields for a networked screen and leaves a dark screen unchanged" do
      travel_to(wiring_time) do
        token = SecureRandom.hex(16)
        station = wiring_station
        station.assign_agent_token!(token)
        entrance = wired_screen(station, ip: "192.168.33.182", mac: "78:53:33:4b:2c:29", name: "Entrance")
        window = create(:screen, station:, name: "Window", orientation: :portrait)
        asset = create(:media_asset, :ready, :with_png_file)
        cover_horizon_with_slot(station, entrance, asset:)

        get "/api/agent/v1/config", headers: agent_authorization_headers(token), as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["screens"]).to eq([
          {
            "id" => entrance.id,
            "name" => "Entrance",
            "orientation" => "landscape",
            "adb_serial" => "192.168.33.182:5555",
            "mac" => "78:53:33:4b:2c:29",
            "stream_port" => 8091
          },
          {
            "id" => window.id,
            "name" => "Window",
            "orientation" => "portrait"
          }
        ])
      end
    end
```

В файле уже есть `require 'rails_helper'`. `travel_to` требует `include ActiveSupport::Testing::TimeHelpers` в этом `RSpec.describe`.

В `spec/requests/api/agent/v2/packages_spec.rb` внутрь `describe "GET /api/agent/v2/package"` добавить отдельный пример, не раздувая пример AE9:

```ruby
    it "does not add screen wiring fields to the package" do
      location = create(:location, time_zone: "UTC")
      station = create(:station, location:, offline_cache_hours: 24)
      screen = wired_screen(station, ip: "192.168.33.182")
      token = station.assign_agent_token!
      asset = create(:media_asset, :ready, :with_png_file)
      create_day_playlist(station, screen, for_date: Date.new(2026, 9, 2), asset:)
      create_day_playlist(station, screen, for_date: Date.new(2026, 9, 3), asset:)

      get "/api/agent/v2/package", headers: agent_authorization_headers(token), as: :json

      expect(response).to have_http_status(:ok)
      expect(deep_keys(response.parsed_body)).not_to include("adb_serial", "mac", "stream_port")
    end
```

И в конец файла, вне `describe`, но внутри `RSpec.describe`:

```ruby
  def deep_keys(value)
    case value
    when Hash
      value.keys + value.values.flat_map { |nested| deep_keys(nested) }
    when Array
      value.flat_map { |nested| deep_keys(nested) }
    else
      []
    end
  end
```

Пример лежит под уже существующим `around { travel_to(Time.utc(2026, 9, 2, 18, 0, 0)) }`. Даты плейлистов 2 и 3 сентября из-за этого совпадают с горизонтом пакета. `wired_screen` из хелпера здесь уместен: пакет не должен прочитать его MAC и IP.

В `spec/requests/admin/stations_spec.rb` добавить:

```ruby
  it "prints the wired screen port in the existing config preview" do
    travel_to(wiring_time) do
      station = wiring_station
      screen = wired_screen(station, ip: "192.168.33.182", name: "Entrance")
      asset = create(:media_asset, :ready, :with_png_file)
      cover_horizon_with_slot(station, screen, asset:)

      get admin_station_path(station)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("\"stream_port\": 8091")
      expect(response.body).to include("192.168.33.182:5555")
      expect(response.body).not_to include("station_stream_channel")
    end
  end
```

`JSON.pretty_generate` пишет `"stream_port": 8091` с пробелом после двоеточия. Отдельной формы порта на странице нет, поэтому имени модели в HTML быть не должно. `travel_to` снова требует `ActiveSupport::Testing::TimeHelpers`; файл уже включает `ActiveJob::TestHelper`, хелпер времени добавить рядом.

- [ ] **Step 2: Запустить specs и убедиться, что новые примеры падают до реализации Task 4**

Если Task 4 уже влит, примеры должны быть зелёными сразу. Если нет:

Run:

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec \
  spec/requests/api/agent/v1/configs_spec.rb \
  spec/requests/api/agent/v2/packages_spec.rb \
  spec/requests/admin/stations_spec.rb
```

Expected до Task 4: v1-пример без `adb_serial`, admin-пример без `"stream_port": 8091`. v2-пример зелёный и до реализации: пакет эти ключи не пишет. После Task 4 expected: 0 failures. Прежние примеры v1 config (экран без сети, `tv_monitor`, 401) остаются зелёными.

- [ ] **Step 3: Повторить request specs после зелёного ConfigBuilder**

Та же команда, что в Step 2.

Expected: 0 failures. В v1 у тёмного экрана нет ключей `adb_serial`, `mac`, `stream_port`. В v2 этих ключей нет ни на одном уровне JSON.

- [ ] **Step 4: Commit**

```bash
git add spec/requests/api/agent/v1/configs_spec.rb spec/requests/api/agent/v2/packages_spec.rb \
  spec/requests/admin/stations_spec.rb
git commit -m "$(cat <<'EOF'
test: cover screen wiring on agent config without touching the package

The admin station preview shows the same payload the agent polls, and the v2 package stays a schedule.
EOF
)"
```

---

### Task 6: Проверка целиком

- [ ] **Step 1: Прогнать затронутые спеки ещё раз**

Run:

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec \
  spec/models/station_stream_channel_spec.rb \
  spec/domain/agent/screen_timelines_spec.rb \
  spec/domain/agent/stream_channels/reconcile_spec.rb \
  spec/domain/agent/config_builder_spec.rb \
  spec/requests/api/agent/v1/configs_spec.rb \
  spec/requests/api/agent/v2/packages_spec.rb \
  spec/requests/admin/stations_spec.rb
```

Expected: 0 failures.

- [ ] **Step 2: Прогнать `bin/ci`**

Run:

```bash
docker compose exec -e RAILS_ENV=test web bin/ci
```

Expected: RuboCop, RSpec, bundler-audit, importmap audit и Brakeman без новых нарушений. `RAILS_ENV=test` обязателен.

Отдельную документацию в `docs/solutions/` не добавлять: поведение описано спекой и этим планом.

---

## Покрытие спеки

| Требование | Задача |
| --- | --- |
| Поля рядом со старыми, без `null` | Task 4, Task 5 |
| `adb_serial` = IPv4 без маски + `:5555` | Task 4 |
| `mac` нижний регистр, шесть октетов; без MAC ключ опущен | Task 2, Task 4 |
| Один непустой дайджест — один порт, разный слот — другой порт | Task 3, Task 4 |
| Пустая лента канал не создаёт | Task 4 |
| Неполный горизонт не создаёт и не удаляет каналы | Task 3, Task 4 |
| Повторный вызов и третий экран с известной лентой | Task 3, Task 4 |
| Пул `8091..8190`, исчерпание без смены уже выданных портов и без ошибки config | Task 1, Task 3 |
| Снятие с сети убирает поля; на полном горизонте неиспользуемый дайджест удаляется | Task 4 |
| Config не ставит `GenerateForDateJob` и не зовёт сборщик пакета | Task 2, Task 4 |
| v2 package не получает новые поля | Task 5 |
| Превью show не верстать заново | Task 5 |
| Discovery, `fetch_screens`, репозиторий станции | вне плана |
