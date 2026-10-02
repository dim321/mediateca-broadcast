# Правка активного заказа на размещение — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Дать менеджеру клиента и оператору править активный заказ — частоту, будущую сетку, ролики, экраны, окна и стратегию — без удлинения даты окончания и без изменения уже вышедших дней, с пересборкой плейлистов после сохранения.

**Architecture:** `Advertising::ReviseActiveOrder` в одной транзакции под `Airtime::ScreenLock` сверяет документ с эфиром. Прошедшие дни и сегодня не переписываются. Конфликт слота откатывает всю правку. `Playlists::EnqueueRegen` ставится только после коммита. Кабинет авторизует `revise?`, админка вызывает тот же сервис для любого заказа.

**Tech Stack:** Rails 8.1, PostgreSQL, RSpec, Pundit, Slim, Stimulus, Docker Compose.

**Spec:** `docs/superpowers/specs/2026-10-02-active-advertising-order-revision-design.md`

---

### Task 1: Политика `revise?`

**Files:**
- Modify: `app/policies/advertising_order_policy.rb`
- Test: `spec/policies/advertising_order_policy_spec.rb`

- [x] **Step 1: Write the failing test**

В `describe "update?"` файл уже запрещает `update?` для активного заказа. Добавить рядом:

```ruby
describe "revise?" do
  it "разрешает менеджеру и администратору своей организации править активный заказ" do
    order.update!(status: :active)

    [ manager, administrator ].each do |user|
      expect(described_class.new(user, order).revise?).to be true
    end
  end

  it "запрещает правку черновика, бухгалтера, трафик-менеджера и чужую организацию" do
    expect(described_class.new(manager, order).revise?).to be false

    order.update!(status: :active)

    stranger = create(:user, :manager, organization: create(:organization, :client))
    expect(described_class.new(accountant, order).revise?).to be false
    expect(described_class.new(traffic_manager, order).revise?).to be false
    expect(described_class.new(stranger, order).revise?).to be false
    expect(described_class.new(manager, order).update?).to be false
  end
end
```

- [x] **Step 2: Run test to verify it fails**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/policies/advertising_order_policy_spec.rb --format documentation`

Expected: FAIL, `revise?` не определён.

- [x] **Step 3: Write minimal implementation**

В `app/policies/advertising_order_policy.rb` после `update?`:

```ruby
def revise? = client_mutator? && operator_or_in_organization? && record.active?
```

`update?` не менять: он остаётся только для черновика.

- [x] **Step 4: Run test to verify it passes**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/policies/advertising_order_policy_spec.rb --format documentation`

Expected: PASS

- [x] **Step 5: Commit**

```bash
git add app/policies/advertising_order_policy.rb spec/policies/advertising_order_policy_spec.rb
git commit -m "$(cat <<'EOF'
feat: allow client managers to revise active advertising orders

EOF
)"
```

---

### Task 2: Калькулятор показов дня

**Files:**
- Create: `app/domain/advertising/day_shows.rb`
- Create: `spec/domain/advertising/day_shows_spec.rb`
- Modify: `app/controllers/concerns/advertising_order_grid.rb`

- [x] **Step 1: Write the failing test**

`spec/domain/advertising/day_shows_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Advertising::DayShows do
  let(:date) { Date.new(2026, 6, 6) } # суббота

  def shows(strategy, screen_index: 0, screen_count: 2, hours: 3, rate: 3)
    described_class.call(
      date: date,
      shows_per_hour: rate,
      hours: hours,
      distribution_strategy: strategy,
      screen_index: screen_index,
      screen_count: screen_count
    )
  end

  it "возвращает частоту на число часов для linear" do
    expect(shows("linear")).to eq(9)
  end

  it "обнуляет выходные для weekdays и будни для weekends" do
    expect(shows("weekdays")).to eq(0)
    expect(shows("weekends")).to eq(9)
    expect(described_class.call(
      date: Date.new(2026, 6, 5),
      shows_per_hour: 3,
      hours: 3,
      distribution_strategy: "weekdays",
      screen_index: 0,
      screen_count: 1
    )).to eq(9)
  end

  it "делит чётные и нечётные дни месяца" do
    expect(shows("even_days")).to eq(9)
    expect(shows("odd_days")).to eq(0)
  end

  it "расставляет шахматку по половине экранов" do
    expect(shows("chess", screen_index: 0, screen_count: 2)).to eq(0)
    expect(shows("chess", screen_index: 1, screen_count: 2)).to eq(9)
  end
end
```

6 июня 2026 — суббота, день месяца чётный. Для `chess` нечётный день отдаёт первую половину экранов; чётный день — вторую. Индекс 0 при двух экранах в первую половину не попадает.

- [x] **Step 2: Run test to verify it fails**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/advertising/day_shows_spec.rb --format documentation`

Expected: FAIL, класс не найден.

- [x] **Step 3: Write minimal implementation**

`app/domain/advertising/day_shows.rb`:

```ruby
# frozen_string_literal: true

module Advertising
  class DayShows < BaseService
    def initialize(date:, shows_per_hour:, hours:, distribution_strategy:, screen_index:, screen_count:)
      @date = date
      @shows_per_hour = shows_per_hour.to_i
      @hours = hours.to_i
      @distribution_strategy = distribution_strategy.to_s
      @screen_index = screen_index
      @screen_count = screen_count
    end

    def call
      base = shows_per_hour * hours
      case distribution_strategy
      when "weekdays"
        weekend? ? 0 : base
      when "weekends"
        weekend? ? base : 0
      when "even_days"
        date.day.even? ? base : 0
      when "odd_days"
        date.day.odd? ? base : 0
      when "chess"
        first_half_day = date.day.odd?
        in_first_half = screen_index < (screen_count / 2.0).ceil
        first_half_day == in_first_half ? base : 0
      else
        base
      end
    end

    private

    attr_reader :date, :shows_per_hour, :hours, :distribution_strategy, :screen_index, :screen_count

    def weekend?
      date.saturday? || date.sunday?
    end
  end
end
```

В `AdvertisingOrderGrid#distributed_shows` заменить тело на вызов калькулятора. Сигнатуру метода оставить, чтобы черновой пересчёт не разъехался:

```ruby
def distributed_shows(order, date, screen_index, screen_count, shows)
  Advertising::DayShows.call(
    date: date,
    shows_per_hour: order.shows_per_hour,
    hours: order.shows_per_hour.to_i.zero? ? 0 : shows / order.shows_per_hour.to_i,
    distribution_strategy: order.distribution_strategy,
    screen_index: screen_index,
    screen_count: screen_count
  )
end
```

`shows` сюда уже приходит как `shows_per_hour * hours`. Деление восстанавливает часы только при ненулевой частоте. Методы `weekend?` в concern удалить, если после этого на них нет ссылок.

- [x] **Step 4: Run test to verify it passes**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/advertising/day_shows_spec.rb spec/requests/advertising_orders_spec.rb --format documentation`

Expected: PASS. Запросные тесты черновика по-прежнему получают 9 показов на день при окне 09:00–12:00 и частоте 3.

- [x] **Step 5: Commit**

```bash
git add app/domain/advertising/day_shows.rb spec/domain/advertising/day_shows_spec.rb app/controllers/concerns/advertising_order_grid.rb
git commit -m "$(cat <<'EOF'
feat: share advertising day-show distribution between draft and revision

EOF
)"
```

---

### Task 3: Отложенная пересборка у занятия и отмены

**Files:**
- Modify: `app/domain/airtime/cancel.rb`
- Modify: `app/domain/airtime/occupy_with_plan.rb`
- Test: `spec/domain/airtime/cancel_spec.rb`
- Test: `spec/domain/airtime/occupy_with_plan_spec.rb`

- [x] **Step 1: Write the failing test**

В `spec/domain/airtime/cancel_spec.rb` после примера про `GenerateForDateJob`:

```ruby
it "does not enqueue playlist regen when asked to defer it" do
  travel_to Time.utc(2026, 9, 2, 12, 0, 0) do
    future_plan = Airtime::OccupyWithPlan.call(
      organization: organization,
      broadcast_point_group: group,
      rotation: rotation,
      starts_at: Time.utc(2026, 9, 3, 10, 0, 0),
      ends_at: Time.utc(2026, 9, 3, 11, 0, 0)
    )

    expect {
      described_class.call(plan: future_plan, enqueue_regen: false)
    }.not_to have_enqueued_job(Playlists::GenerateForDateJob)

    expect(future_plan.reload).to be_cancelled
  end
end
```

В `spec/domain/airtime/occupy_with_plan_spec.rb` после примера `"enqueues GenerateForDateJob for tomorrow after occupy (AE7)"`:

```ruby
it "does not enqueue playlist regen when asked to defer it" do
  travel_to Time.utc(2026, 9, 2, 12, 0, 0) do
    expect {
      described_class.call(
        organization: organization,
        broadcast_point_group: group,
        rotation: rotation,
        starts_at: Time.utc(2026, 9, 3, 10, 0, 0),
        ends_at: Time.utc(2026, 9, 3, 11, 0, 0),
        enqueue_regen: false
      )
    }.not_to have_enqueued_job(Playlists::GenerateForDateJob)
  end

  expect(MediaPlan.active.count).to eq(1)
end
```

- [x] **Step 2: Run test to verify it fails**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/airtime/cancel_spec.rb spec/domain/airtime/occupy_with_plan_spec.rb --format documentation`

Expected: FAIL, неизвестный keyword `enqueue_regen`.

- [x] **Step 3: Write minimal implementation**

`Airtime::Cancel#initialize` получает `enqueue_regen: true`. После успешной отмены:

```ruby
Playlists::EnqueueRegen.from_plan(cancelled) if enqueue_regen
```

`Airtime::OccupyWithPlan#initialize` получает `enqueue_regen: true` в конец списка keyword-аргументов. После транзакции:

```ruby
Playlists::EnqueueRegen.from_plan(plan) if enqueue_regen
```

Сохранить оба флага в `attr_reader`. Значение по умолчанию `true`, чтобы текущие вызовы не изменились.

- [x] **Step 4: Run test to verify it passes**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/airtime/cancel_spec.rb spec/domain/airtime/occupy_with_plan_spec.rb --format documentation`

Expected: PASS, включая прежние примеры, где задача ставится.

- [x] **Step 5: Commit**

```bash
git add app/domain/airtime/cancel.rb app/domain/airtime/occupy_with_plan.rb spec/domain/airtime/cancel_spec.rb spec/domain/airtime/occupy_with_plan_spec.rb
git commit -m "$(cat <<'EOF'
feat: let airtime writes defer playlist regeneration

EOF
)"
```

---

### Task 4: Замена роликов без второй версии документа

**Files:**
- Modify: `app/domain/advertising/update_order_clips.rb`
- Test: `spec/domain/advertising/update_order_clips_spec.rb`

- [x] **Step 1: Write the failing test**

В `spec/domain/advertising/update_order_clips_spec.rb` после примера `"does not enqueue regen when enqueue_regen is false"`:

```ruby
it "syncs clips without a version bump when the caller owns the version" do
  activate!

  expect {
    described_class.call(
      order: order,
      media_assets: [ clip_b ],
      enqueue_regen: false,
      bump_version: false
    )
  }.not_to have_enqueued_job(Playlists::GenerateForDateJob)

  expect(order.reload.rotation.ordered_items.sole.media_asset).to eq(clip_b)
  expect(order.document_version).to eq(1)
end
```

- [x] **Step 2: Run test to verify it fails**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/advertising/update_order_clips_spec.rb --format documentation`

Expected: FAIL, неизвестный keyword `bump_version`.

- [x] **Step 3: Write minimal implementation**

```ruby
def initialize(order:, media_assets:, enqueue_regen: true, bump_version: true)
  @order = order
  @media_assets = Array(media_assets)
  @enqueue_regen = enqueue_regen
  @bump_version = bump_version
end
```

В `update_order!`:

```ruby
attrs[:document_version] = order.document_version + 1 if order.active? && bump_version
```

Добавить `bump_version` в `attr_reader`.

- [x] **Step 4: Run test to verify it passes**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/advertising/update_order_clips_spec.rb --format documentation`

Expected: PASS. Прежний пример по-прежнему ставит версию 2 и задачу.

- [x] **Step 5: Commit**

```bash
git add app/domain/advertising/update_order_clips.rb spec/domain/advertising/update_order_clips_spec.rb
git commit -m "$(cat <<'EOF'
feat: let clip sync skip the document version bump

EOF
)"
```

---

### Task 5: Отказ правки до записи эфира

**Files:**
- Create: `app/domain/advertising/revise_active_order.rb`
- Create: `spec/domain/advertising/revise_active_order_spec.rb`
- Modify: `config/locales/mediateca.ru.yml`
- Modify: `config/locales/mediateca.en.yml`

- [x] **Step 1: Write the failing test**

`spec/domain/advertising/revise_active_order_spec.rb`. Общий setup, его же используют следующие задачи:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Advertising::ReviseActiveOrder do
  let(:organization) { create(:organization, :client, time_zone: "UTC") }
  let(:user) { create(:user, :manager, organization: organization) }
  let(:asset) { create(:media_asset, :ready, :content_validated, :with_png_file, organization: organization, duration_seconds: 10) }
  let(:group) { create_group_with_hours!(organization: organization) }
  let(:screen) { group.screens.first }

  before do
    create(:broadcast_portrait, :for_screen, screen: screen, block_frequencies_per_hour: [ 1, 2, 3, 4, 6 ])
  end

  def active_order!(dates:)
    order = Advertising::CreateOrder.call(
      organization: organization,
      created_by: user,
      media_assets: [ asset ],
      product_name: "Triumph",
      shows_per_hour: 3
    )
    fill_order_grid!(order, screen: screen, dates: dates, shows: 9)
    Advertising::ActivateOrder.call(order: order)
    order.reload
  end

  def revise(order, **overrides)
    described_class.call({
      order: order,
      shows_per_hour: 3,
      distribution_strategy: order.distribution_strategy,
      windows: [ { starts_at: "09:00", ends_at: "12:00" } ],
      screen_ids: [ screen.id ],
      lines: [ {
        screen_id: screen.id,
        days: order.advertising_order_line_days.map do |day|
          { date: day.date, skipped: false, shows: day.shows }
        end
      } ],
      grid_from: order.advertising_order_line_days.map(&:date).min,
      grid_to: order.advertising_order_line_days.map(&:date).max,
      product_name: order.product_name,
      placement_kind: order.placement_kind
    }.merge(overrides))
  end
end
```

Примеры этой задачи, внутри `travel_to Time.utc(2026, 6, 4, 8, 0, 0)`:

```ruby
it "rejects a draft before writing" do
  order = Advertising::CreateOrder.call(
    organization: organization, created_by: user, media_assets: [ asset ], product_name: "Triumph", shows_per_hour: 3
  )
  fill_order_grid!(order, screen: screen, dates: [ Date.new(2026, 6, 5) ], shows: 9)

  expect { revise(order) }.to raise_error(Advertising::Error, I18n.t("advertising.errors.order_not_revisable"))
  expect(order.reload).to be_draft
end

it "rejects an end date later than the stored grid" do
  order = active_order!(dates: [ Date.new(2026, 6, 3), Date.new(2026, 6, 6) ])

  expect {
    revise(order, grid_to: Date.new(2026, 6, 7), lines: [ {
      screen_id: screen.id,
      days: [
        { date: Date.new(2026, 6, 3), skipped: false, shows: 9 },
        { date: Date.new(2026, 6, 6), skipped: false, shows: 9 },
        { date: Date.new(2026, 6, 7), skipped: false, shows: 9 }
      ]
    } ])
  }.to raise_error(Advertising::Error, I18n.t("advertising.errors.end_date_extended"))

  expect(order.reload.advertising_order_line_days.map(&:date)).to contain_exactly(Date.new(2026, 6, 3), Date.new(2026, 6, 6))
  expect(order.media_plans.active.count).to eq(2)
end

it "rejects a changed grid start" do
  order = active_order!(dates: [ Date.new(2026, 6, 3), Date.new(2026, 6, 6) ])

  expect {
    revise(order, grid_from: Date.new(2026, 6, 4))
  }.to raise_error(Advertising::Error, I18n.t("advertising.errors.start_date_changed"))
end

it "rejects a tampered day on or before today" do
  order = active_order!(dates: [ Date.new(2026, 6, 3), Date.new(2026, 6, 4), Date.new(2026, 6, 6) ])

  expect {
    revise(order, lines: [ {
      screen_id: screen.id,
      days: [
        { date: Date.new(2026, 6, 3), skipped: true, shows: 0 },
        { date: Date.new(2026, 6, 4), skipped: false, shows: 9 },
        { date: Date.new(2026, 6, 6), skipped: false, shows: 9 }
      ]
    } ])
  }.to raise_error(Advertising::Error, I18n.t("advertising.errors.locked_day_changed"))

  expect(order.advertising_order_line_days.find_by!(date: Date.new(2026, 6, 3)).shows).to eq(9)
end

it "rejects a changed product name or placement kind" do
  order = active_order!(dates: [ Date.new(2026, 6, 6) ])

  expect {
    revise(order, product_name: "Other")
  }.to raise_error(Advertising::Error, I18n.t("advertising.errors.frozen_field_changed"))
end

it "rejects a frequency outside the screen portrait intersection" do
  order = active_order!(dates: [ Date.new(2026, 6, 6) ])

  expect { revise(order, shows_per_hour: 12) }.to raise_error(Advertising::InvalidGrid)
  expect(order.reload.shows_per_hour).to eq(3)
end
```

Отдельный пример без `travel_to` на 4 июня, а на `Time.utc(2026, 6, 1, 8, 0, 0)`: заказ с датами 3–6 июня, правка не включает 3 июня. Ожидание — `I18n.t("advertising.errors.future_start_removed")`, слоты на месте.

- [x] **Step 2: Run test to verify it fails**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/advertising/revise_active_order_spec.rb --format documentation`

Expected: FAIL, класс не найден.

- [x] **Step 3: Write minimal implementation**

Ключи в оба локаля, в `advertising.errors`:

```yaml
order_not_revisable: править можно только активный заказ
end_date_extended: дату окончания нельзя сдвинуть вперёд
start_date_changed: дату начала менять нельзя
locked_day_changed: прошедшие дни и сегодняшний день менять нельзя
frozen_field_changed: название и тип размещения менять нельзя
future_start_removed: дата начала ещё впереди и должна остаться в сетке
slot_conflict: выбранный интервал уже занят
```

Английские строки — рядом с существующими `advertising.errors` в `mediateca.en.yml`.

`app/domain/advertising/revise_active_order.rb` на этом шаге валидирует и возвращает результат, не трогая слоты. Конструктор принимает keyword-аргументы из теста: `order`, `shows_per_hour`, `distribution_strategy`, `windows`, `screen_ids`, `lines`, `media_assets: nil`, `grid_from: nil`, `grid_to: nil`, `product_name: nil`, `placement_kind: nil`.

```ruby
Result = Data.define(:order, :quota_exceeded)

def call
  validate!
  Result.new(order: order, quota_exceeded: false)
end
```

`validate!`:

- `raise Error, I18n.t("advertising.errors.order_not_revisable") unless order.active?`
- `period_start` / `period_end` — min/max дат `advertising_order_line_days`
- `grid_from` сравнивать как `Date` с `period_start`; иное значение — `start_date_changed`
- `grid_to` и любая дата в `lines` позже `period_end` — `end_date_extended`
- `product_name`, если передан и не равен заказу, или `placement_kind`, если передан и не равен заказу — `frozen_field_changed`
- для каждой строки дня с `date <= today` найти день в `lines` того же экрана: нет строки, `skipped` истинно или `shows.to_i != day.shows` — `locked_day_changed`
- если `period_start > today` и ни один экран из `screen_ids` не содержит эту дату как не пропущенную — `future_start_removed`
- выставить `order.shows_per_hour = shows_per_hour` и вызвать `Advertising::AssertShowsPerHour.call(order: order, screens: Screen.where(id: screen_ids))`, не сохраняя заказ. Перед вызовом запомнить прежнюю частоту и вернуть её в объект, если валидация нужна только как проверка: `order.shows_per_hour` после отказа не должен сохраниться, потому что `save` не вызывается. В тесте `reload` это подтверждает.

`today` — `Time.find_zone!(order.organization.time_zone).today`.

`lines` нормализовать через `to_h.deep_symbolize_keys`. Даты принимать и как `Date`, и как строку `Date.iso8601`.

- [x] **Step 4: Run test to verify it passes**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/advertising/revise_active_order_spec.rb --format documentation`

Expected: PASS

- [x] **Step 5: Commit**

```bash
git add app/domain/advertising/revise_active_order.rb spec/domain/advertising/revise_active_order_spec.rb config/locales/mediateca.ru.yml config/locales/mediateca.en.yml
git commit -m "$(cat <<'EOF'
feat: reject invalid active-order revisions before airtime writes

EOF
)"
```

---

### Task 6: Частота будущих слотов и версия документа

**Files:**
- Modify: `app/domain/advertising/revise_active_order.rb`
- Test: `spec/domain/advertising/revise_active_order_spec.rb`

- [x] **Step 1: Write the failing test**

```ruby
it "updates shows per hour only on future plans and line days" do
  travel_to Time.utc(2026, 6, 4, 8, 0, 0) do
    order = active_order!(dates: [ Date.new(2026, 6, 3), Date.new(2026, 6, 4), Date.new(2026, 6, 6) ])

    expect {
      revise(order, shows_per_hour: 6)
    }.to have_enqueued_job(Playlists::GenerateForDateJob).with(screen.station_id, "2026-06-06")

    order.reload
    expect(order.shows_per_hour).to eq(6)
    expect(order.document_version).to eq(2)
    expect(order.advertising_order_line_days.find_by!(date: Date.new(2026, 6, 6)).shows).to eq(18)
    expect(order.advertising_order_line_days.find_by!(date: Date.new(2026, 6, 3)).shows).to eq(9)
    expect(order.advertising_order_line_days.find_by!(date: Date.new(2026, 6, 4)).shows).to eq(9)
    future = order.media_plans.active.find { |plan| plan.starts_at.to_date == Date.new(2026, 6, 6) }
    today_plan = order.media_plans.active.find { |plan| plan.starts_at.to_date == Date.new(2026, 6, 4) }
    expect(future.shows_per_hour).to eq(6)
    expect(today_plan.shows_per_hour).to eq(3)
    expect(future.starts_at).to eq(Time.utc(2026, 6, 6, 9, 0, 0))
  end
end

it "does not bump the document or enqueue regen when nothing changed" do
  travel_to Time.utc(2026, 6, 4, 8, 0, 0) do
    order = active_order!(dates: [ Date.new(2026, 6, 6) ])

    expect { revise(order) }.not_to have_enqueued_job(Playlists::GenerateForDateJob)

    expect(order.reload.document_version).to eq(1)
  end
end
```

Окно 09:00–12:00 даёт 3 часа. Частота 6 даёт 18 показов. `starts_at.to_date` в UTC совпадает с локальным днём, потому что организация в этом тесте живёт в UTC.

- [x] **Step 2: Run test to verify it fails**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/advertising/revise_active_order_spec.rb --format documentation`

Expected: FAIL, частота и версия не меняются, задача не ставится.

- [x] **Step 3: Write minimal implementation**

После `validate!` открыть `MediaPlan.transaction`. Внутри:

1. `Airtime::ScreenLock.call(screen_ids: lock_ids)`, где `lock_ids` — объединение `screen_ids` и экранов существующих строк.
2. Записать `shows_per_hour` и `distribution_strategy`, если отличаются.
3. Заменить окна, только если набор пар `HH:MM–HH:MM` отличается. На этом шаге тест окна не меняет, метод должен уметь сравнить и ничего не удалять при равенстве.
4. Для каждой существующей строки и каждой её даты `> today` пересчитать показы через `Advertising::ScreenDayHours` и `Advertising::DayShows`. Если дата пропущена в `lines` или `grid_to` её отсекает, это задача 7: пока считать день включённым, если он есть в `lines` и не `skipped`.
5. Если показы изменились, обновить строку дня. Если активный слот этого локального дня имеет те же границы, что новый расчёт `ranges`, обновить `shows_per_hour` через `update_columns` и запомнить план. Границы не двигать.
6. `Advertising::RecalculateTotals.call(order: order)`.
7. Если частота, стратегия, окна или будущие показы изменились — `order.update!(document_version: order.document_version + 1)`.

После коммита для каждого запомненного плана вызвать `Playlists::EnqueueRegen.from_plan`. Внутри транзакции `Cancel` и `OccupyWithPlan` не вызывать.

Сравнение границ: пары `[starts_at, ends_at]` из `ScreenDayHours#ranges` и активных планов строки, пересекающих локальные сутки. Сутки — как в `Advertising::Coverage.occupied?`.

- [x] **Step 4: Run test to verify it passes**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/advertising/revise_active_order_spec.rb --format documentation`

Expected: PASS

- [x] **Step 5: Commit**

```bash
git add app/domain/advertising/revise_active_order.rb spec/domain/advertising/revise_active_order_spec.rb
git commit -m "$(cat <<'EOF'
feat: revise future show frequency on an active advertising order

EOF
)"
```

---

### Task 7: Состав будущих дней

**Files:**
- Modify: `app/domain/advertising/revise_active_order.rb`
- Test: `spec/domain/advertising/revise_active_order_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
it "cancels a removed future day and keeps the order active" do
  travel_to Time.utc(2026, 6, 4, 8, 0, 0) do
    order = active_order!(dates: [ Date.new(2026, 6, 3), Date.new(2026, 6, 6) ])

    revise(order, grid_to: Date.new(2026, 6, 3), lines: [ {
      screen_id: screen.id,
      days: [ { date: Date.new(2026, 6, 3), skipped: false, shows: 9 } ]
    } ])

    expect(order.reload).to be_active
    expect(order.advertising_order_line_days.map(&:date)).to eq([ Date.new(2026, 6, 3) ])
    expect(order.media_plans.active.count).to eq(1)
    expect(order.media_plans.cancelled.count).to eq(1)
  end
end

it "occupies a future day that was skipped" do
  travel_to Time.utc(2026, 6, 4, 8, 0, 0) do
    order = active_order!(dates: [ Date.new(2026, 6, 3), Date.new(2026, 6, 6) ])

    revise(order, lines: [ {
      screen_id: screen.id,
      days: [
        { date: Date.new(2026, 6, 3), skipped: false, shows: 9 },
        { date: Date.new(2026, 6, 5), skipped: false, shows: 9 },
        { date: Date.new(2026, 6, 6), skipped: false, shows: 9 }
      ]
    } ])

    expect(order.reload.advertising_order_line_days.map(&:date)).to contain_exactly(
      Date.new(2026, 6, 3), Date.new(2026, 6, 5), Date.new(2026, 6, 6)
    )
    expect(order.media_plans.active.count).to eq(3)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/advertising/revise_active_order_spec.rb --format documentation`

Expected: FAIL, 6 июня остаётся после сокращения, 5 июня не занимается.

- [ ] **Step 3: Write minimal implementation**

Желаемые будущие даты экрана — те, что `> today`, `>= period_start`, `<= [grid_to, period_end].min`, не `skipped`, и `DayShows` для них больше нуля.

Даты будущей строки, которых нет в этом множестве: `Airtime::Cancel.call(plan: plan, enqueue_regen: false)` для активных слотов локальных суток, затем `day.destroy!`. Запомнить отменённый план.

Даты из множества, которых не было: создать `advertising_order_line_days` с посчитанными показами и занять каждый range через `Airtime::OccupyWithPlan` с `enqueue_regen: false`, `order_claim: true`, `screens: [line.screen]`, `placement_kind: order.placement_kind`, `shows_per_hour: shows_per_hour`, `advertising_order_line: line`, `rotation: order.rotation`, `organization: order.organization`. Запомнить новый план.

После коммита поставить пересборку и по отменённым, и по новым планам. `Cancel` внутри внешней `MediaPlan.transaction` присоединяется к ней, поэтому флаг `enqueue_regen: false` обязателен.

- [ ] **Step 4: Run test to verify it passes**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/advertising/revise_active_order_spec.rb --format documentation`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/domain/advertising/revise_active_order.rb spec/domain/advertising/revise_active_order_spec.rb
git commit -m "$(cat <<'EOF'
feat: add and remove future days when revising an active order

EOF
)"
```

---

### Task 8: Окна часов только для будущего

**Files:**
- Modify: `app/domain/advertising/revise_active_order.rb`
- Test: `spec/domain/advertising/revise_active_order_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
it "moves future slot bounds and leaves today in place" do
  travel_to Time.utc(2026, 6, 4, 8, 0, 0) do
    order = active_order!(dates: [ Date.new(2026, 6, 4), Date.new(2026, 6, 6) ])

    revise(order, windows: [ { starts_at: "10:00", ends_at: "13:00" } ])

    order.reload
    future = order.media_plans.active.find { |plan| plan.starts_at.to_date == Date.new(2026, 6, 6) }
    current = order.media_plans.active.find { |plan| plan.starts_at.to_date == Date.new(2026, 6, 4) }
    expect(future.starts_at).to eq(Time.utc(2026, 6, 6, 10, 0, 0))
    expect(future.ends_at).to eq(Time.utc(2026, 6, 6, 13, 0, 0))
    expect(current.starts_at).to eq(Time.utc(2026, 6, 4, 9, 0, 0))
    expect(order.advertising_order_line_days.find_by!(date: Date.new(2026, 6, 4)).shows).to eq(9)
    expect(order.advertising_order_line_days.find_by!(date: Date.new(2026, 6, 6)).shows).to eq(9)
    expect(order.advertising_order_windows.map { |window| [ window.starts_at.strftime("%H:%M"), window.ends_at.strftime("%H:%M") ] }).to eq([ [ "10:00", "13:00" ] ])
  end
end
```

Новое окно тоже 3 часа, показы остаются 9. Меняются только границы будущего слота.

- [ ] **Step 2: Run test to verify it fails**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/advertising/revise_active_order_spec.rb -e "moves future slot bounds" --format documentation`

Expected: FAIL, будущий слот остаётся на 09:00.

- [ ] **Step 3: Write minimal implementation**

Если границы суток не совпали с новым `ranges`, отменить прежние активные слоты этих суток с `enqueue_regen: false` и занять новые тем же `OccupyWithPlan`, тоже с `enqueue_regen: false`. Строку дня обновить посчитанными показами. Сегодняшний и прошедший слоты в этот цикл не входят.

Пустой список окон или окно, у которого конец не позже начала, отклонять в `validate!` через `Advertising::Error` с уже существующей валидацией модели: построить `AdvertisingOrderWindow` и вызвать `valid?`. Сообщение модели достаточно; отдельный ключ не добавлять.

- [ ] **Step 4: Run test to verify it passes**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/advertising/revise_active_order_spec.rb --format documentation`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/domain/advertising/revise_active_order.rb spec/domain/advertising/revise_active_order_spec.rb
git commit -m "$(cat <<'EOF'
feat: reslot future days when an active order changes hours

EOF
)"
```

---

### Task 9: Экраны

**Files:**
- Modify: `app/domain/advertising/revise_active_order.rb`
- Test: `spec/domain/advertising/revise_active_order_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
it "occupies a newly selected screen from the first editable date" do
  travel_to Time.utc(2026, 6, 4, 8, 0, 0) do
    order = active_order!(dates: [ Date.new(2026, 6, 3), Date.new(2026, 6, 6) ])
    added = create_group_with_hours!(organization: organization).screens.first
    create(:broadcast_portrait, :for_screen, screen: added, block_frequencies_per_hour: [ 1, 2, 3, 4, 6 ])

    revise(order, screen_ids: [ screen.id, added.id ], lines: [
      { screen_id: screen.id, days: [
        { date: Date.new(2026, 6, 3), skipped: false, shows: 9 },
        { date: Date.new(2026, 6, 6), skipped: false, shows: 9 }
      ] },
      { screen_id: added.id, days: [
        { date: Date.new(2026, 6, 6), skipped: false, shows: 9 }
      ] }
    ])

    added_line = order.reload.advertising_order_lines.find_by!(screen: added)
    expect(added_line.advertising_order_line_days.map(&:date)).to eq([ Date.new(2026, 6, 6) ])
    expect(added_line.media_plans.active.count).to eq(1)
  end
end

it "drops future slots of an unchecked screen and keeps days through today" do
  travel_to Time.utc(2026, 6, 4, 8, 0, 0) do
    order = active_order!(dates: [ Date.new(2026, 6, 3), Date.new(2026, 6, 6) ])

    revise(order, screen_ids: [], lines: [ {
      screen_id: screen.id,
      days: [ { date: Date.new(2026, 6, 3), skipped: false, shows: 9 } ]
    } ])

    line = order.reload.advertising_order_lines.find_by!(screen: screen)
    expect(line.advertising_order_line_days.map(&:date)).to eq([ Date.new(2026, 6, 3) ])
    expect(line.media_plans.active.count).to eq(1)
    expect(line.media_plans.cancelled.count).to eq(1)
  end
end
```

Пустой `screen_ids` при сохранённой строке с прошедшим днём означает «убрать экран из будущего». Строка остаётся из-за внешнего ключа слотов.

- [ ] **Step 2: Run test to verify it fails**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/advertising/revise_active_order_spec.rb -e "screen" --format documentation`

Expected: FAIL

- [ ] **Step 3: Write minimal implementation**

Для `screen_id`, которого нет среди строк, `find_or_create_by!(screen_id:)` с `price_per_day_cents: 0`, затем занять желаемые будущие даты. Экран не из `screen_ids` получает пустое множество будущих дат: будущие дни снимаются, прошедшие строки не удаляются. Строку без дней не уничтожать, если на неё ссылается хотя бы один `MediaPlan`.

`AssertShowsPerHour` уже смотрит на итоговый `screen_ids`. Для экрана, снятого с будущего, но оставшегося в истории, в пересечение портретов его не включать.

- [ ] **Step 4: Run test to verify it passes**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/advertising/revise_active_order_spec.rb --format documentation`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/domain/advertising/revise_active_order.rb spec/domain/advertising/revise_active_order_spec.rb
git commit -m "$(cat <<'EOF'
feat: add and remove screens on the future part of an active order

EOF
)"
```

---

### Task 10: Стратегия распределения

**Files:**
- Modify: `app/domain/advertising/revise_active_order.rb`
- Test: `spec/domain/advertising/revise_active_order_spec.rb`

- [ ] **Step 1: Write the failing test**

5 июня 2026 — пятница, 6 июня — суббота.

```ruby
it "recomputes future days for the new strategy and leaves past shows" do
  travel_to Time.utc(2026, 6, 4, 8, 0, 0) do
    order = active_order!(dates: [ Date.new(2026, 6, 3), Date.new(2026, 6, 5), Date.new(2026, 6, 6) ])

    revise(order, distribution_strategy: "weekdays")

    order.reload
    expect(order.distribution_strategy).to eq("weekdays")
    expect(order.advertising_order_line_days.find_by!(date: Date.new(2026, 6, 3)).shows).to eq(9)
    expect(order.advertising_order_line_days.find_by(date: Date.new(2026, 6, 6))).to be_nil
    expect(order.advertising_order_line_days.find_by!(date: Date.new(2026, 6, 5)).shows).to eq(9)
    expect(order.media_plans.active.map { |plan| plan.starts_at.to_date }).to contain_exactly(
      Date.new(2026, 6, 3), Date.new(2026, 6, 5)
    )
  end
end
```

Суббота при `weekdays` получает 0 показов и снимается, даже если в `lines` она не помечена `skipped`. Сервер считает сам.

- [ ] **Step 2: Run test to verify it fails**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/advertising/revise_active_order_spec.rb -e "strategy" --format documentation`

Expected: FAIL, суббота остаётся в сетке.

- [ ] **Step 3: Write minimal implementation**

Желаемый день существует только когда `DayShows` больше нуля. `skipped` в запросе дополнительно выключает день, но не может включить день, который стратегия обнулила. Прошедшие строки не пересчитывать.

- [ ] **Step 4: Run test to verify it passes**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/advertising/revise_active_order_spec.rb --format documentation`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/domain/advertising/revise_active_order.rb spec/domain/advertising/revise_active_order_spec.rb
git commit -m "$(cat <<'EOF'
feat: apply a new distribution strategy to future order days

EOF
)"
```

---

### Task 11: Ролики, конфликт и квота

**Files:**
- Modify: `app/domain/advertising/revise_active_order.rb`
- Test: `spec/domain/advertising/revise_active_order_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
it "replaces clips, bumps the version once, and regenerates today's plan" do
  travel_to Time.utc(2026, 6, 4, 8, 0, 0) do
    order = active_order!(dates: [ Date.new(2026, 6, 4), Date.new(2026, 6, 6) ])
    replacement = create(:media_asset, :ready, :content_validated, :with_png_file, organization: organization, duration_seconds: 15)

    expect {
      revise(order, media_assets: [ replacement ])
    }.to have_enqueued_job(Playlists::GenerateForDateJob).with(screen.station_id, "2026-06-04")

    expect(order.reload.rotation.ordered_items.sole.media_asset).to eq(replacement)
    expect(order.document_version).to eq(2)
  end
end

it "rolls back clips and other days when one future slot conflicts" do
  travel_to Time.utc(2026, 6, 4, 8, 0, 0) do
    order = active_order!(dates: [ Date.new(2026, 6, 6) ])
    replacement = create(:media_asset, :ready, :content_validated, :with_png_file, organization: organization, duration_seconds: 15)
    Airtime::OccupyWithPlan.call(
      organization: organization,
      broadcast_point_group: group,
      rotation: create(:rotation, organization: organization),
      starts_at: Time.utc(2026, 6, 5, 0, 0, 0),
      ends_at: Time.utc(2026, 6, 6, 0, 0, 0)
    )

    expect {
      revise(order, media_assets: [ replacement ], lines: [ {
        screen_id: screen.id,
        days: [
          { date: Date.new(2026, 6, 5), skipped: false, shows: 9 },
          { date: Date.new(2026, 6, 6), skipped: false, shows: 9 }
        ]
      } ])
    }.to raise_error(Advertising::Error, I18n.t("advertising.errors.slot_conflict"))

    expect(order.reload.rotation.ordered_items.sole.media_asset).to eq(asset)
    expect(order.advertising_order_line_days.map(&:date)).to eq([ Date.new(2026, 6, 6) ])
    expect(order.document_version).to eq(1)
  end
end
```

Конфликт строится чужим слотом без `advertising_order_line`: `ScreenOverlapGuard` при `order_claim: true` пропускает другие заказы и останавливается о ручном занятии. 5 июня пересекается с сутками 5 июня 00:00–6 июня 00:00.

```ruby
it "reports commercial quota without rolling the revision back" do
  travel_to Time.utc(2026, 6, 4, 8, 0, 0) do
    owner = create(:organization, :client)
    owned = create_group_with_hours!(
      organization: owner,
      commercial_quota_percent: 10,
      commercial_quota_period: :hour
    )
    owned_screen = owned.screens.first
    create(:broadcast_portrait, :for_screen, screen: owned_screen, block_frequencies_per_hour: [ 1, 2, 3, 4, 6 ])
    long_clip = create(:media_asset, :ready, :content_validated, :with_png_file, organization: organization, duration_seconds: 240)
    commercial = Advertising::CreateOrder.call(
      organization: organization,
      created_by: user,
      media_assets: [ long_clip ],
      product_name: "Triumph",
      placement_kind: :commercial,
      shows_per_hour: 3
    )
    fill_order_grid!(commercial, screen: owned_screen, dates: [ Date.new(2026, 6, 6) ], shows: 9)
    Advertising::ActivateOrder.call(order: commercial)

    result = described_class.call(
      order: commercial.reload,
      shows_per_hour: 6,
      distribution_strategy: "linear",
      windows: [ { starts_at: "09:00", ends_at: "12:00" } ],
      screen_ids: [ owned_screen.id ],
      lines: [ { screen_id: owned_screen.id, days: [ { date: Date.new(2026, 6, 6), skipped: false, shows: 9 } ] } ],
      grid_from: Date.new(2026, 6, 6),
      grid_to: Date.new(2026, 6, 6),
      product_name: "Triumph",
      placement_kind: "commercial"
    )

    expect(result.quota_exceeded).to be(true)
    expect(commercial.reload.shows_per_hour).to eq(6)
    expect(commercial).to be_active
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/advertising/revise_active_order_spec.rb -e "clips" -e "conflict" -e "quota" --format documentation`

Expected: FAIL

- [ ] **Step 3: Write minimal implementation**

Если `media_assets` не `nil`, внутри той же транзакции вызвать:

```ruby
Advertising::UpdateOrderClips.call(
  order: order,
  media_assets: media_assets,
  enqueue_regen: false,
  bump_version: false
)
```

`nil` означает «ротацию не менять». Пустой массив отклоняет `UpdateOrderClips`.

Смена роликов — повод увеличить `document_version` один раз вместе с остальными изменениями, не второй раз внутри `UpdateOrderClips`.

После коммита, если ролики менялись, `Playlists::EnqueueRegen.from_plan` для каждого активного слота заказа, включая сегодняшний. Иначе — только для планов, которые эта правка отменила, создала или обновила.

`Airtime::ConflictError`, вылетевший из транзакции, снаружи `call` превратить в `Advertising::Error` с `advertising.errors.slot_conflict`. Не перехватывать его внутри транзакции. Пересборку в этой ветке не ставить.

Квота: после занятия пройтись по новым планам через `CommercialQuota::Check.call(plan:).exceeded`. Хотя бы одно превышение даёт `quota_exceeded: true` в `Result`. Запись не откатывать.

- [ ] **Step 4: Run test to verify it passes**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/advertising/revise_active_order_spec.rb spec/domain/advertising/activate_order_spec.rb --format documentation`

Expected: PASS. Активация по-прежнему оставляет конфликтные окна частичным успехом: это поведение `ActivateOrder`, не правки.

- [ ] **Step 5: Commit**

```bash
git add app/domain/advertising/revise_active_order.rb spec/domain/advertising/revise_active_order_spec.rb
git commit -m "$(cat <<'EOF'
feat: revise clips atomically and roll back on slot conflict

EOF
)"
```

---

### Task 12: Форма и контроллер кабинета

**Files:**
- Modify: `app/controllers/advertising_orders_controller.rb`
- Modify: `app/controllers/concerns/advertising_order_grid.rb`
- Modify: `app/views/advertising_orders/show.html.slim`
- Modify: `app/views/advertising_orders/edit.html.slim`
- Modify: `app/views/advertising_orders/_form.html.slim`
- Modify: `app/views/advertising_orders/_line_fields.html.slim`
- Modify: `app/helpers/advertising_orders_helper.rb`
- Modify: `app/javascript/controllers/order_grid_controller.js`
- Modify: `app/javascript/controllers/order_screen_picker_controller.js`
- Test: `spec/requests/advertising_orders_spec.rb`

- [ ] **Step 1: Write the failing test**

В `describe "PATCH /advertising_orders/:id"`:

```ruby
it "lets a manager revise frequency on an active order" do
  travel_to Time.utc(2026, 6, 4, 8, 0, 0) do
    order = Advertising::CreateOrder.call(
      organization: organization, created_by: user, media_assets: [ asset ], product_name: "Triumph", shows_per_hour: 3
    )
    fill_order_grid!(order, screen: order_screen, dates: [ Date.new(2026, 6, 3), Date.new(2026, 6, 6) ], shows: 9)
    Advertising::ActivateOrder.call(order: order)

    patch advertising_order_path(order), params: order_params(
      dates: [ "2026-06-03", "2026-06-06" ],
      shows_per_hour: 6,
      grid_from: "2026-06-03",
      grid_to: "2026-06-06"
    )

    expect(response).to redirect_to(advertising_order_path(order))
    expect(order.reload.shows_per_hour).to eq(6)
    expect(order.advertising_order_line_days.find_by!(date: Date.new(2026, 6, 3)).shows).to eq(9)
    expect(order.advertising_order_line_days.find_by!(date: Date.new(2026, 6, 6)).shows).to eq(18)
  end
end

it "rejects a tampered grid start on an active order" do
  travel_to Time.utc(2026, 6, 4, 8, 0, 0) do
    order = Advertising::CreateOrder.call(
      organization: organization, created_by: user, media_assets: [ asset ], product_name: "Triumph", shows_per_hour: 3
    )
    fill_order_grid!(order, screen: order_screen, dates: [ Date.new(2026, 6, 3), Date.new(2026, 6, 6) ], shows: 9)
    Advertising::ActivateOrder.call(order: order)

    patch advertising_order_path(order), params: order_params(
      dates: [ "2026-06-03", "2026-06-06" ],
      grid_from: "2026-06-04",
      grid_to: "2026-06-06"
    )

    expect(response).to have_http_status(:unprocessable_content)
    expect(order.reload.advertising_order_line_days.map(&:date)).to contain_exactly(
      Date.new(2026, 6, 3), Date.new(2026, 6, 6)
    )
  end
end
```

`order_params` сейчас не прокидывает `grid_from` / `grid_to` на верхний уровень. Добавить их в хелпер как ключи рядом с `advertising_order`, не внутрь него: контроллер читает `params[:grid_from]`.

В `describe "accountant mutations"` добавить отказ `patch` активного заказа: редирект на `rails_health_check_path`, частота не меняется.

`GET edit` активного заказа менеджером возвращает 200, поле названия `disabled`, клетка 3 июня `disabled`.

- [ ] **Step 2: Run test to verify it fails**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/requests/advertising_orders_spec.rb -e "active order" --format documentation`

Expected: FAIL, `update?` запрещает менеджеру сохранение.

- [ ] **Step 3: Write minimal implementation**

`edit` и `update`: если заказ `active?`, `authorize @advertising_order, :revise?`, иначе прежний `authorize @advertising_order`.

`update` для активного заказа не вызывает `header_update_attrs`, `persist_grid!` и `UpdateOrderClips` напрямую. Он вызывает `Advertising::ReviseActiveOrder` и редиректит с `notice: t(".updated")`. `result.quota_exceeded` кладёт в `flash[:warning]` ключ `advertising_orders.activate.quota_exceeded`.

Аргументы сервиса собирать так:

- `shows_per_hour` из `order_header_shows_per_hour`
- `distribution_strategy` из параметров или текущей стратегии
- `windows` из `order_params[:windows]`
- `screen_ids` из `form_screen_ids`
- `lines` из `line_rows`, даты как `Date`, `skipped` когда значение `"1"` или `shows == "0"`
- `media_assets` из `find_media_assets`, только если `clip_ids_submitted?`
- `grid_from` / `grid_to` через уже существующий `parse_grid_date`
- `product_name` и `placement_kind` передавать, только если ключ есть в `order_params`

`Advertising::Error` и `Airtime::ConflictError` рендерят `edit` со статусом 422, сообщение в `errors.add(:base, e.message)`. `InvalidGrid` оставить как сейчас.

`grid_dates` для активного заказа: `from` всегда `order_grid_bounds.begin`, `to` — минимум из запрошенного конца и `order_grid_bounds.end`.

На странице заказа ссылка «Изменить» при `can_mutate.update? || can_mutate.revise?`.

В `_form` для `active?`: `product_name` и `placement_kind` с `disabled: true`. Ролики, экраны, окна, стратегия и частота остаются доступными.

В `edit.html.slim` для активного заказа поле «с» получает `readonly: true`, поле «по» — `max` равный последнему дню сетки. Расширить `order_grid_date_field_tag` keyword-аргументами `readonly: false` и `max: nil` и проставить их на текстовое поле и на `input type="date"`.

В `_line_fields` клетка с датой `<= Time.find_zone!(order_form_time_zone).today` при активном заказе получает `disabled: true` и `readonly: true`.

В `recompute` контроллера `order_grid_controller.js` первой проверкой клетки:

```javascript
if (cell.disabled) {
  this.updateCellAppearance(cell)
  return
}
```

`syncGridRows` в `order_screen_picker_controller.js` заменить на:

```javascript
syncGridRows() {
  if (!this.hasGridLinesTarget || !this.hasRowTemplateTarget) return

  const selectedRows = this.rowTargets.filter((row) => this.rowCheckbox(row)?.checked)
  const selectedIds = new Set(selectedRows.map((row) => this.rowCheckbox(row).value))

  this.gridRowTargets.forEach((row) => {
    if (selectedIds.has(String(row.dataset.screenId))) return
    if (this.rowHasLockedCell(row)) {
      this.setFutureSkipped(row, true)
      return
    }
    row.remove()
  })

  selectedRows.forEach((pickerRow) => {
    const id = this.rowCheckbox(pickerRow).value
    const existing = this.gridRowTargets.find((row) => String(row.dataset.screenId) === id)
    if (existing) {
      this.setFutureSkipped(existing, false)
      return
    }
    this.appendGridRows(pickerRow, id)
  })

  this.dispatch("recompute", { prefix: "order-grid" })
  this.element.dispatchEvent(new Event("input", { bubbles: true }))
}

rowHasLockedCell(row) {
  return row.querySelector("[data-order-grid-target='cell']:disabled") != null
}

setFutureSkipped(row, skipped) {
  row.querySelectorAll("[data-order-grid-target='cell']").forEach((cell) => {
    if (cell.disabled) return

    const flag = cell.parentElement?.querySelector("[data-order-grid-target='skipped']")
    cell.dataset.skipped = skipped ? "1" : ""
    if (skipped) cell.value = "0"
    if (flag) flag.value = skipped ? "1" : "0"
  })
}
```

Черновик заблокированных клеток не имеет, поэтому строка по-прежнему удаляется при снятии экрана.

- [ ] **Step 4: Run test to verify it passes**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/requests/advertising_orders_spec.rb spec/policies/advertising_order_policy_spec.rb --format documentation`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/controllers/advertising_orders_controller.rb app/controllers/concerns/advertising_order_grid.rb app/views/advertising_orders app/helpers/advertising_orders_helper.rb app/javascript/controllers/order_grid_controller.js app/javascript/controllers/order_screen_picker_controller.js spec/requests/advertising_orders_spec.rb
git commit -m "$(cat <<'EOF'
feat: revise an active advertising order from the client cabinet

EOF
)"
```

---

### Task 13: Та же правка в админке

**Files:**
- Modify: `app/controllers/admin/advertising_orders_controller.rb`
- Modify: `app/views/admin/advertising_orders/show.html.erb`
- Modify: `app/views/admin/advertising_orders/edit.html.erb`
- Test: `spec/requests/admin/advertising_orders_spec.rb`

- [ ] **Step 1: Write the failing test**

Внутри `context "when signed in as operator"` файла `spec/requests/admin/advertising_orders_spec.rb`. Хелпер `order_params` и `order_screen` в этом файле уже есть.

```ruby
def activated_client_order
  order = Advertising::CreateOrder.call(
    organization: client,
    created_by: client_user,
    media_assets: [ asset ],
    product_name: "Triumph",
    shows_per_hour: 3
  )
  fill_order_grid!(order, screen: order_screen, dates: [ Date.new(2026, 6, 3), Date.new(2026, 6, 6) ], shows: 9)
  Advertising::ActivateOrder.call(order: order)
  order.reload
end

it "lets an operator revise another organization's active order" do
  travel_to Time.utc(2026, 6, 4, 8, 0, 0) do
    order = activated_client_order

    patch admin_advertising_order_path(order), params: order_params(
      dates: [ "2026-06-03", "2026-06-06" ],
      shows_per_hour: 6
    ).merge(grid_from: "2026-06-03", grid_to: "2026-06-06")

    expect(response).to redirect_to(admin_advertising_order_path(order))
    expect(order.reload.shows_per_hour).to eq(6)
    expect(order.advertising_order_line_days.find_by!(date: Date.new(2026, 6, 3)).shows).to eq(9)
  end
end

it "rejects an extended end date for an active order" do
  travel_to Time.utc(2026, 6, 4, 8, 0, 0) do
    order = activated_client_order

    patch admin_advertising_order_path(order), params: order_params(
      dates: [ "2026-06-03", "2026-06-06", "2026-06-07" ],
      shows_per_hour: 3
    ).merge(grid_from: "2026-06-03", grid_to: "2026-06-07")

    expect(response).to have_http_status(:unprocessable_content)
    expect(order.reload.advertising_order_line_days.map(&:date)).to contain_exactly(
      Date.new(2026, 6, 3), Date.new(2026, 6, 6)
    )
  end
end

it "links to edit from an active order" do
  order = activated_client_order

  get admin_advertising_order_path(order)

  expect(response.body).to include(edit_admin_advertising_order_path(order))
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/requests/admin/advertising_orders_spec.rb -e "active order" --format documentation`

Expected: FAIL. Текущий `update` либо не пускает активный заказ в сетку правки, либо переписывает весь документ черновым путём.

- [ ] **Step 3: Write minimal implementation**

В `Admin::AdvertisingOrdersController#update` та же развилка, что в кабинете: активный заказ идёт в `Advertising::ReviseActiveOrder`, черновик остаётся на текущем `update!` + `persist_grid!`. Успех редиректит на `admin_advertising_order_path` с `t("advertising_orders.update.updated")`. Квота — `flash[:warning]`. Ошибки `Advertising::Error`, `Airtime::ConflictError` и `InvalidGrid` рендерят `:edit` со статусом 422.

`edit.html.erb`: для активного заказа дата начала `readonly`, дата окончания с `max` на последний день сетки. Общая форма уже прячет название и тип размещения по `active?`.

`show.html.erb`: ссылка «Изменить» и для `active?`, классом `admin_primary_button_class`, рядом с отменой. Черновик свою ссылку сохраняет.

- [ ] **Step 4: Run test to verify it passes**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/requests/admin/advertising_orders_spec.rb --format documentation`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/controllers/admin/advertising_orders_controller.rb app/views/admin/advertising_orders spec/requests/admin/advertising_orders_spec.rb
git commit -m "$(cat <<'EOF'
feat: revise any client's active advertising order in admin

EOF
)"
```
