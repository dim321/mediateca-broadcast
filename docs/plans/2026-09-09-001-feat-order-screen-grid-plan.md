---
title: "Сетка заказа по экранам и общий коммерческий эфир"
type: feat
date: 2026-09-09
topic: order-screen-grid
artifact_contract: ce-unified-plan/v1
artifact_readiness: implementation-ready
product_contract_source: ce-brainstorm
execution: code
origin: docs/brainstorms/2026-09-09-order-screen-grid-brainstorm.md
deepened: false
---

# Сетка заказа по экранам Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Форма заказа (админка и кабинет) собирает один документ на отмеченные экраны: частота в час и суточные интервалы на заказ, строка сетки на экран, ячейка = частота × пересечение окон с часами экрана; активация создаёт overlapping заявки, плейлист мешает ролики по портрету.

**Architecture:** Строка заказа привязана к `screen_id`. Окна и `shows_per_hour` живут на заказе. `Airtime::OccupyWithPlan` для заявок заказа занимает **перечень экранов** (`media_plan_screens`), группа необязательна. `ScreenOverlapGuard` не отвергает пересечение двух заявок с `order_claim: true`. Генератор плейлиста берёт все occupying-планы экрана в часе и мешает клипы в commercial-блоке.

**Tech Stack:** Rails 8.1, PostgreSQL, RSpec/FactoryBot, Slim + daisyUI (кабинет), ERB + Flowbite (админка использует тот же Slim-partial формы), Stimulus, i18n ru/en.

## Global Constraints

- Тесты только: `docker compose exec -e RAILS_ENV=test web bundle exec rspec …` (`RAILS_ENV=test` обязателен).
- TDD: Red → Green → Refactor. Не писать production-код до падающего теста.
- Старые `AdvertisingOrder` можно удалить в миграции (проект не в коммерческой эксплуатации).
- Интервалы через полночь (22:00–02:00) не делаем.
- Цена / коэффициент / скидка на форме не появляются. Колонки БД не обязательно дропать (`price_per_day_cents` default 0).
- Календарные даты сетки — TZ организации-клиента. Пересечение часов — wall-clock той же TZ, что `Advertising::OperatingHours` (сейчас `order.organization.time_zone`).
- Ручные медиапланы (без `advertising_order_line_id`) остаются FWW. Делят эфир только заявки заказов (`order_claim: true`).
- Квота коммерции — soft flash, без отката occupy. Не класть % в Guard.
- Admin `/admin` — не daisyUI. Кабинет — daisyUI. Общий partial `_form.html.slim` уже daisyUI и рендерится в админке как сейчас.
- UI copy: `config/locales/mediateca.ru.yml` + `mediateca.en.yml`.
- Mutations that redirect: `status: :see_other`.

## File map

**Create**

- `db/migrate/YYYYMMDDHHMMSS_rebuild_advertising_order_grid.rb` — wipe orders, `shows_per_hour`, `advertising_order_windows`, `screen_id` on lines, drop `broadcast_point_group_id` on lines, `media_plan_screens`, nullable `broadcast_point_group_id` on `media_plans` and `airtime_bookings`.
- `app/models/advertising_order_window.rb`
- `app/models/media_plan_screen.rb`
- `app/domain/advertising/screen_day_hours.rb`
- `spec/models/advertising_order_window_spec.rb`
- `spec/models/media_plan_screen_spec.rb`
- `spec/domain/advertising/screen_day_hours_spec.rb`
- `app/views/advertising_orders/_window_fields.html.slim`
- `app/javascript/controllers/order_windows_controller.js`

**Modify**

- `app/models/advertising_order.rb` — `shows_per_hour`, `has_many :advertising_order_windows`
- `app/models/advertising_order_line.rb` — `belongs_to :screen`, unique `(order, screen)`
- `app/models/media_plan.rb` — `has_many :media_plan_screens`, optional group, screens required
- `app/models/airtime_booking.rb` — optional group
- `app/domain/advertising/update_grid.rb` — `screen_id`, без кратности к часам группы, без цены как входного смысла
- `app/domain/advertising/activate_order.rb` — per screen × occupy_ranges, `order_claim: true`
- `app/domain/advertising/create_order.rb` — `shows_per_hour:`
- `app/domain/airtime/occupy_with_plan.rb` — `screens:`, `order_claim:`, optional group
- `app/domain/airtime/screen_overlap_guard.rb` — union group memberships + `media_plan_screens`; skip when both sides order claims
- `app/domain/airtime/placement_channel.rb` — `screens:` path for order claims
- `app/domain/playlists/generate_for_date.rb` — mix all occupying order/commercial plans
- `app/controllers/advertising_orders_controller.rb` + `app/controllers/admin/advertising_orders_controller.rb`
- `app/views/advertising_orders/_form.html.slim`, `_line_fields.html.slim`
- `app/views/advertising_orders/new.html.slim` — `show_screen_picker: true`
- `app/javascript/admin/controllers/order_screen_picker_controller.js` — sync grid rows from checkboxes
- `app/javascript/controllers/order_grid_controller.js` — recompute cells, weekend class, drop add-line
- `app/components/advertising/print_sheet_component*`
- factories + all specs that still pass `broadcast_point_group_id` into order lines
- `spec/system/advertising_order_placement_spec.rb`
- `CONCEPTS.md` — Advertising order line = screen; shared commercial hour
- `config/locales/mediateca.ru.yml`, `mediateca.en.yml`

---

### Task 1: Схема и модели (экран, окна, частота)

**Files:**
- Create: `db/migrate/*_rebuild_advertising_order_grid.rb`
- Create: `app/models/advertising_order_window.rb`
- Create: `app/models/media_plan_screen.rb`
- Modify: `app/models/advertising_order.rb`, `app/models/advertising_order_line.rb`, `app/models/media_plan.rb`, `app/models/airtime_booking.rb`
- Modify: `spec/factories/advertising_orders.rb`, `spec/factories/advertising_order_lines.rb`
- Create: `spec/factories/advertising_order_windows.rb`
- Test: `spec/models/advertising_order_line_spec.rb`, `spec/models/advertising_order_window_spec.rb`

**Interfaces:**
- Consumes: current `AdvertisingOrder` / `AdvertisingOrderLine` / `MediaPlan`
- Produces: `AdvertisingOrder#shows_per_hour`, `AdvertisingOrder#advertising_order_windows` (`starts_at`/`ends_at` as `time` clock, no date), `AdvertisingOrderLine#screen`, `MediaPlan#screens` through `MediaPlanScreen`

- [ ] **Step 1: Write the failing model specs**

В `spec/models/advertising_order_window_spec.rb`:

```ruby
RSpec.describe AdvertisingOrderWindow do
  it "belongs to an order and requires start before end on the same clock day" do
    order = create(:advertising_order)
    window = described_class.new(
      advertising_order: order,
      starts_at: "09:00",
      ends_at: "12:00"
    )
    expect(window).to be_valid

    window.ends_at = "08:00"
    expect(window).not_to be_valid
    expect(window.errors[:ends_at]).to be_present
  end
end
```

В `spec/models/advertising_order_line_spec.rb` заменить uniqueness group на screen:

```ruby
it "rejects a second line for the same screen on the same order" do
  line = create(:advertising_order_line)
  duplicate = build(:advertising_order_line, advertising_order: line.advertising_order, screen: line.screen)
  expect(duplicate).not_to be_valid
  expect(duplicate.errors[:screen_id]).to be_present
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/models/advertising_order_window_spec.rb spec/models/advertising_order_line_spec.rb`

Expected: FAIL (`uninitialized constant AdvertisingOrderWindow` / `screen` association missing).

- [ ] **Step 3: Migration**

Одна миграция, порядок:

1. `MediaPlan.where.not(advertising_order_line_id: nil).update_all(advertising_order_line_id: nil)` затем `AdvertisingOrder.find_each(&:destroy!)` (и system_managed rotations заказа). Если FK мешает — `update_columns` / `delete_all` в безопасном порядке: days → lines → orders → orphan rotations.
2. `add_column :advertising_orders, :shows_per_hour, :integer`
3. `create_table :advertising_order_windows` — `advertising_order_id` FK cascade, `starts_at`/`ends_at` тип `time` null: false. Check `starts_at < ends_at` (сравнение time).
4. `add_reference :advertising_order_lines, :screen, null: false, foreign_key: { on_delete: :restrict }`
5. Удалить unique `(advertising_order_id, broadcast_point_group_id)`, колонку `broadcast_point_group_id`, её FK и индекс.
6. Unique index `(advertising_order_id, screen_id)` name `index_advertising_order_lines_on_order_and_screen`.
7. `create_table :media_plan_screens` — как `playlist_item_screens`: unique `(media_plan_id, screen_id)`, FK cascade на plan, restrict/cascade на screen (cascade как у playlist_item_screens).
8. `change_column_null :media_plans, :broadcast_point_group_id, true` и то же для `airtime_bookings`. Check: план с `broadcast_point_group_id IS NULL` обязан иметь строки в `media_plan_screens` (если удобнее — валидация AR, не SQL).

`price_per_day_cents` оставить `null: false, default: 0`.

- [ ] **Step 4: Models**

`AdvertisingOrderWindow`:

```ruby
class AdvertisingOrderWindow < ApplicationRecord
  belongs_to :advertising_order
  validates :starts_at, :ends_at, presence: true
  validate :ends_after_starts

  private
    def ends_after_starts
      return if starts_at.blank? || ends_at.blank?
      errors.add(:ends_at, :must_be_after_starts) unless ends_at > starts_at
    end
end
```

`AdvertisingOrder`: `has_many :advertising_order_windows, dependent: :destroy`, `validates :shows_per_hour, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true` (nil на черновике до заполнения формы ок; create может оставить nil).

`AdvertisingOrderLine`: `belongs_to :screen`, убрать `broadcast_point_group` и `group_matches_order_organization_for_own_atmosphere`. Unique `screen_id` scoped to `advertising_order_id`.

`MediaPlanScreen`: `belongs_to :media_plan`, `belongs_to :screen`, unique screen per plan.

`MediaPlan`: `has_many :media_plan_screens, dependent: :destroy`, `has_many :screens, through: :media_plan_screens`. `belongs_to :broadcast_point_group, optional: true`. `validate :must_have_screens` — `screens.exists? || broadcast_point_group&.screens&.any?`.

`AirtimeBooking`: `belongs_to :broadcast_point_group, optional: true`. Ослабить `booking_matches_organization_and_group`, если group nil.

Factory `:advertising_order_line` — `screen { association :screen, owner_organization: advertising_order.organization }` вместо group.

- [ ] **Step 5: Run tests to verify they pass**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/models/advertising_order_window_spec.rb spec/models/advertising_order_line_spec.rb spec/models/advertising_order_spec.rb`

Expected: PASS. Починить фабрики/аннотации annotate, если упадёт schema comment.

- [ ] **Step 6: Commit**

```bash
git add db/migrate app/models spec/models spec/factories
git commit -m "feat: bind advertising order lines to screens and store hour windows"
```

---

### Task 2: `Advertising::ScreenDayHours`

**Files:**
- Create: `app/domain/advertising/screen_day_hours.rb`
- Test: `spec/domain/advertising/screen_day_hours_spec.rb`
- Modify: `app/models/location/operating_hours.rb` только если нужен class-method `minutes_in_hour(hours, local_time)` без `Location.new`

**Interfaces:**
- Consumes: `screen.effective_operating_hours`, `Location::OperatingHours` / `operating_minutes_in_hour` semantics
- Produces: `Advertising::ScreenDayHours.call(screen:, date:, windows:, time_zone:) -> Result(hours:, ranges:)`
  - `windows` — array of `{ start: "09:00", end: "12:00" }` or Window objects with `starts_at`/`ends_at`
  - `hours` — Integer, число clock-hours `0..23`, где и экран, и хотя бы одно окно заказа имеют положительные минуты
  - `ranges` — `Array` of `[starts_at, ends_at]` ActiveSupport::TimeWithZone в `time_zone` на `date`: попарное пересечение окон заказа с рабочими окнами экрана в этот weekday; пустой массив, если пересечения нет

- [ ] **Step 1: Write the failing spec**

```ruby
RSpec.describe Advertising::ScreenDayHours do
  let(:zone) { "UTC" }
  let(:date) { Date.new(2026, 6, 3) } # Wednesday
  let(:hours_hash) { AdvertisingNetwork::WEEKLY_HOURS }
  let(:screen) { create(:screen) }

  before { screen.station.location.update!(operating_hours: hours_hash, time_zone: zone) }

  def result(windows)
    described_class.call(screen: screen.reload, date: date, windows: windows, time_zone: zone)
  end

  it "counts hours where order windows intersect the screen schedule" do
    out = result([ { start: "09:00", end: "12:00" } ])
    expect(out.hours).to eq(3)
    expect(out.ranges.size).to eq(1)
    expect(out.ranges.first[0].strftime("%H:%M")).to eq("09:00")
    expect(out.ranges.first[1].strftime("%H:%M")).to eq("12:00")
  end

  it "clips a window to the screen's open interval" do
    # WEEKLY_HOURS is 09:00–21:00 every day
    out = result([ { start: "07:00", end: "10:00" } ])
    expect(out.hours).to eq(1)
    expect(out.ranges.first[0].strftime("%H:%M")).to eq("09:00")
    expect(out.ranges.first[1].strftime("%H:%M")).to eq("10:00")
  end

  it "returns zero when the screen is closed that weekday" do
    closed = AdvertisingNetwork::WEEKLY_HOURS.merge("wed" => [])
    screen.update!(inherit_operating_hours_from_location: false, operating_hours: closed)
    out = result([ { start: "09:00", end: "12:00" } ])
    expect(out.hours).to eq(0)
    expect(out.ranges).to eq([])
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/advertising/screen_day_hours_spec.rb`

Expected: FAIL `uninitialized constant Advertising::ScreenDayHours`.

- [ ] **Step 3: Implement**

Считать минуты экрана в часе через тот же overlap, что `Location#operating_minutes_in_hour`, но по `screen.effective_operating_hours` (вынести `Location::OperatingHours.minutes_in_hour(hours, local_time)` если иначе пришлось бы `Location.new`).

Час входит в `hours`, если `screen_minutes > 0` и сумма overlap минут окон заказа с `[hour, hour+1)` > 0.

`ranges`: для каждого окна заказа × каждого window экрана в день `DAY_KEYS[wday]` построй `[max(starts), min(ends)]` на `date` в `time_zone`; отбрось нулевую длительность; слей смежные.

- [ ] **Step 4: Run test to verify it passes**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/advertising/screen_day_hours_spec.rb`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/domain/advertising/screen_day_hours.rb spec/domain/advertising/screen_day_hours_spec.rb app/models/location/operating_hours.rb
git commit -m "feat: compute order-hour intersections against screen operating hours"
```

---

### Task 3: `UpdateGrid` пишет экраны и посчитанные `shows`

**Files:**
- Modify: `app/domain/advertising/update_grid.rb`
- Modify: `app/domain/advertising/create_order.rb` — принять `shows_per_hour:`
- Test: `spec/domain/advertising/update_grid_spec.rb`
- Modify: `spec/domain/advertising/create_order_spec.rb` если сигнатура create меняется

**Interfaces:**
- Consumes: `Advertising::ScreenDayHours`, `order.shows_per_hour`, `order.advertising_order_windows`
- Produces: `Advertising::UpdateGrid.call(order:, lines:)` где каждый line:

```ruby
{ screen_id:, days: [ { date:, shows: } ] }
```

`shows > 0` сохраняется. `shows == 0` или отсутствие дня — прочерк (нет `AdvertisingOrderLineDay`). Больше нет `broadcast_point_group_id` и нет валидации «shows % hours == 0»: сервер **доверяет** присланным shows (форма считает `shows_per_hour * hours`, ноль — явный skip). Если `shows_per_hour` blank или окон нет — все ячейки 0, линии экранов всё равно создаются (пустые дни).

`price_per_day_cents` писать `0`.

- [ ] **Step 1: Rewrite failing `update_grid_spec`**

Заменить payload:

```ruby
def line_payload(screen:, days:)
  { screen_id: screen.id, days: days }
end

it "upserts a screen line and stores computed daily shows" do
  screen = create(:screen, owner_organization: organization)
  create(:broadcast_point_group_membership, broadcast_point_group: group, screen: screen)
  order.update!(shows_per_hour: 3)
  order.advertising_order_windows.create!(starts_at: "09:00", ends_at: "12:00")

  hours = Advertising::ScreenDayHours.call(
    screen: screen, date: Date.new(2026, 6, 3),
    windows: [ { start: "09:00", end: "12:00" } ],
    time_zone: "UTC"
  ).hours

  update!([ line_payload(screen: screen, days: [ { date: Date.new(2026, 6, 3), shows: 3 * hours } ]) ])

  line = order.advertising_order_lines.sole
  expect(line.screen).to eq(screen)
  expect(line.advertising_order_line_days.sole.shows).to eq(3 * hours)
end

it "omits a zeroed day" do
  # first persist a day, then payload without it or shows: 0
end
```

Удалить примеры про group missing hours / not multiple of hours.

- [ ] **Step 2: Run spec to verify it fails**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/advertising/update_grid_spec.rb`

Expected: FAIL on `broadcast_point_group_id` / missing `screen_id`.

- [ ] **Step 3: Implement `UpdateGrid`**

`stage_line`: `Screen.find(attrs.fetch(:screen_id))`, `AdvertisingOrderLine.new(advertising_order: order, screen:, price_per_day_cents: 0)`. Не вызывать `OperatingHours.call(group:)`. Не проверять `shows % hours`.

`persist!`: destroy lines whose `screen_id` not in incoming ids; upsert by `screen_id`.

- [ ] **Step 4: Run spec to verify it passes**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/advertising/update_grid_spec.rb spec/domain/advertising/create_order_spec.rb spec/domain/advertising/recalculate_totals_spec.rb spec/domain/advertising/cancel_order_spec.rb`

Expected: PASS (починить остальные domain advertising specs, которые ещё передают group).

- [ ] **Step 5: Commit**

```bash
git add app/domain/advertising spec/domain/advertising
git commit -m "feat: persist advertising order grid lines per screen"
```

---

### Task 4: Форма — частота, интервалы, строка на экран

**Files:**
- Modify: `app/views/advertising_orders/_form.html.slim`
- Modify: `app/views/advertising_orders/_line_fields.html.slim`
- Create: `app/views/advertising_orders/_window_fields.html.slim`
- Modify: `app/views/advertising_orders/new.html.slim` — `show_screen_picker: true`
- Modify: `app/views/admin/advertising_orders/new.html.erb` — уже picker
- Modify: `app/controllers/advertising_orders_controller.rb`, `app/controllers/admin/advertising_orders_controller.rb`
- Modify: `app/helpers/advertising_orders_helper.rb`
- Modify: `config/locales/mediateca.ru.yml`, `mediateca.en.yml`
- Modify: `app/javascript/controllers/order_grid_controller.js`
- Modify: `app/javascript/admin/controllers/order_screen_picker_controller.js`
- Create: `app/javascript/controllers/order_windows_controller.js`
- Test: `spec/requests/advertising_orders_spec.rb`, `spec/requests/admin/advertising_orders_spec.rb`

**Interfaces:**
- Consumes: `@order_screens`, `Fleet::ScreensForOrderPicker` (кабинет тоже)
- Produces: params

```
advertising_order[shows_per_hour]
advertising_order[windows][][starts_at]
advertising_order[windows][][ends_at]
advertising_order[screen_ids][]
advertising_order[lines][<i>][screen_id]
advertising_order[lines][<i>][days][][date]
advertising_order[lines][<i>][days][][shows]
advertising_order[lines][<i>][days][][skipped]  # optional "1" if user zeroed
```

Контроллеры: перед `UpdateGrid` для каждого отмеченного screen посчитать shows через `ScreenDayHours` × `shows_per_hour`, **кроме** дней, где `skipped` / клиент прислал `shows=0`. Сохранить windows: replace `advertising_order_windows` from params. `CreateOrder.call(..., shows_per_hour:)`.

Убрать `addLine` / `lineTemplate` / fillShows. Диапазон дат остаётся GET `grid_from`/`grid_to`.

Строка сетки: hidden `screen_id`, подпись `screen.name` / location / station. Ячейка `readonly` кроме возможности стереть в 0 (number min=0). Класс выходного: `date.saturday? || date.sunday?` → `bg-base-200` (кабинет) / `bg-gray-100` (если тот же partial в админке — daisyUI уже используется).

Stimulus `order-screen-picker`: при check — клонировать row template с `data-screen-id`; при uncheck — удалить row. Больше не фильтровать `groupSelect`.

Stimulus `order-grid`: при input частоты/окон пересчитать не-skipped ячейки: `hours` положить в `tr[data-hours-by-date]` JSON с сервера (`data-hours='{"2026-06-03":3,...}'` на строке). Сервер рендерит hours per screen per grid date.

`order-windows`: add/remove window fields from a template.

Кабинет `new`/`edit`: тот же picker (`load_form_collections` вызывает `Fleet::ScreensForOrderPicker.call`).

- [ ] **Step 1: Failing request specs**

Админка `GET new`:

```ruby
expect(response.body).to include('name="advertising_order[shows_per_hour]"')
expect(response.body).to include("advertising_order[windows]")
expect(response.body).not_to include("broadcast_point_group_id")
expect(response.body).to include(I18n.t("advertising_orders.form.add_window"))
```

Кабинет `GET new`: picker **есть** (`order-screen-picker`), нет `coefficient`/`discount`/`broadcast_point_group_id`.

`POST` создаёт заказ с окнами и линией на screen, `total_shows` = сумма ячеек.

Существующий пример «does not render the admin screen picker» в кабинете — **удалить/инвертировать**.

- [ ] **Step 2: Run specs to verify they fail**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/requests/advertising_orders_spec.rb spec/requests/admin/advertising_orders_spec.rb`

Expected: FAIL (нет `shows_per_hour` / picker still absent in cabinet).

- [ ] **Step 3: Implement views, Stimulus, controllers, i18n**

Ключи (ru/en): `form.shows_per_hour`, `form.windows`, `form.add_window`, `form.remove_window`, `form.window_start`, `form.window_end`, `form.screen`, убрать `multiplicity_hint` про группу / `add_line` / `fill_shows` / `fill_range` если кнопки ушли.

`order_params` permit `:shows_per_hour`, `windows: [:starts_at, :ends_at]`, `screen_ids: []`, `lines: [:screen_id, { days: [:date, :shows, :skipped] }]`.

- [ ] **Step 4: Run request specs**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/requests/advertising_orders_spec.rb spec/requests/admin/advertising_orders_spec.rb`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/views app/controllers app/javascript app/helpers config/locales spec/requests
git commit -m "feat: order form uses hourly rate, day windows, and one grid row per screen"
```

---

### Task 5: Occupy по экранам и overlapping order claims

**Files:**
- Modify: `app/domain/airtime/occupy_with_plan.rb`
- Modify: `app/domain/airtime/screen_overlap_guard.rb`
- Modify: `app/domain/airtime/placement_channel.rb`
- Modify: `app/models/media_plan.rb` validations (`placement_channel_allowed` when group nil)
- Test: `spec/domain/airtime/occupy_with_plan_spec.rb`
- Create/modify: `spec/domain/airtime/screen_overlap_guard_spec.rb`

**Interfaces:**
- Produces:

```ruby
Airtime::OccupyWithPlan.call(
  organization:,
  rotation:,
  starts_at:,
  ends_at:,
  placement_kind:,
  shows_per_hour:,
  screens:,                 # required Array<Screen> or ids; locked set
  broadcast_point_group: nil, # optional; required for manual LK occupy (existing callers pass group, screens default to group.screens)
  order_claim: false,
  advertising_order_line: nil
)
```

`screen_ids` для lock/guard = `Array(screens).map(&:id)` если переданы, иначе `broadcast_point_group.screen_ids`.

После create plan: `screens.each { |s| plan.media_plan_screens.create!(screen: s) }`. Если group передан и `screens` nil — заполнить `media_plan_screens` из `group.screens` (чтобы Guard/playlist читали одно место).

`ScreenOverlapGuard.call(..., order_claim: false)`:

- overlapping bookings: join `LEFT OUTER JOIN media_plans ON media_plans.airtime_booking_id = airtime_bookings.id` + `LEFT OUTER JOIN media_plan_screens` + legacy `broadcast_point_groups` memberships. Screen match если `media_plan_screens.screen_id IN (:ids) OR memberships.screen_id IN (:ids)`.
- если `order_claim:` и у overlapping booking медиаплан имеет `advertising_order_line_id` **или** мы помечаем booking (проще: `media_plans.advertising_order_line_id IS NOT NULL`) — **исключить** эти booking из конфликта.
- ручной план vs заявка заказа → конфликт остаётся (FWW).

`PlacementChannel.assert_screens!(organization:, screens:, placement_kind:)`:

- `own_atmosphere`: каждый `screen.owner_organization_id == organization.id`
- `commercial`: разрешено (флот `owner` nil и чужие экраны). Не требовать группу.

Существующие вызовы `OccupyWithPlan` с `broadcast_point_group:` без `screens:` должны продолжить работать (спеки media plan).

- [ ] **Step 1: Failing occupy spec**

```ruby
it "allows a second order claim on the same screen and window" do
  screen = create(:screen)
  # two rotations/orgs
  first = Airtime::OccupyWithPlan.call(..., screens: [screen], order_claim: true, shows_per_hour: 3, placement_kind: :commercial)
  second = Airtime::OccupyWithPlan.call(..., screens: [screen], order_claim: true, shows_per_hour: 3, placement_kind: :commercial)
  expect(first).to be_active
  expect(second).to be_active
end

it "still rejects a manual plan overlapping an order claim on the same screen" do
  expect {
    Airtime::OccupyWithPlan.call(..., broadcast_point_group: group, order_claim: false)
  }.to raise_error(Airtime::ConflictError)
end
```

Для commercial без group: не вызывать старый `PlacementChannel.assert!(group:)`.

- [ ] **Step 2: Run to verify fail**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/airtime/occupy_with_plan_spec.rb spec/domain/airtime/screen_overlap_guard_spec.rb`

Expected: FAIL (second occupy raises ConflictError).

- [ ] **Step 3: Implement Guard + Occupy + PlacementChannel + MediaPlan validations**

`conflict_screen_ids` на MediaPlan: `screens.ids.presence || broadcast_point_group.screen_ids`.

Когда group nil, `placement_channel_allowed` зовёт `assert_screens!`.

- [ ] **Step 4: Run airtime specs**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/airtime spec/requests/media_plans_spec.rb spec/requests/admin/media_plans_spec.rb`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/domain/airtime app/models/media_plan.rb app/models/airtime_booking.rb spec/domain/airtime spec/models/media_plan_spec.rb
git commit -m "feat: allow overlapping advertising-order airtime claims per screen"
```

---

### Task 6: `ActivateOrder` — заявки на пересечения окон

**Files:**
- Modify: `app/domain/advertising/activate_order.rb`
- Test: `spec/domain/advertising/activate_order_spec.rb`

**Interfaces:**
- Consumes: `line.screen`, `order.advertising_order_windows`, `Advertising::ScreenDayHours`, `Airtime::OccupyWithPlan`
- Produces: для каждого дня с `shows > 0` и каждого `range` из `ScreenDayHours` — `OccupyWithPlan.call(screens: [line.screen], starts_at: range[0], ends_at: range[1], shows_per_hour: order.shows_per_hour, placement_kind: order.placement_kind, order_claim: true, advertising_order_line: line)` затем `plan.update_column(:advertising_order_line_id, line.id)` как сейчас.

Не схлопывать полночь–полночь по группе. Не делить `day.shows / hours` — частота только `order.shows_per_hour`.

Конфликт одного range — в `conflicted_windows`, остальные occupy продолжаются (как сейчас per-chain).

- [ ] **Step 1: Failing activate spec**

Два заказа, один экран, окна 09:00–12:00, `shows_per_hour: 3`, день с shows > 0. Оба `ActivateOrder` без `ConflictError`. `MediaPlan.active.count >= 2`. Оба плана имеют этот `screen` через `media_plan_screens`.

Один заказ, два окна 09–12 и 17–20 → два плана (два range) на тот день.

- [ ] **Step 2: Run to verify fail**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/advertising/activate_order_spec.rb`

Expected: FAIL (ищет group / один полночь–полночь план).

- [ ] **Step 3: Implement ActivateOrder**

Убрать `OperatingHours.call(group:)`. `includes(:screen, :advertising_order_line_days)`.

- [ ] **Step 4: Run spec**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/advertising/activate_order_spec.rb`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/domain/advertising/activate_order.rb spec/domain/advertising/activate_order_spec.rb
git commit -m "feat: activate orders as per-screen window claims"
```

---

### Task 7: Плейлист мешает несколько коммерческих заявок

**Files:**
- Modify: `app/domain/playlists/generate_for_date.rb`
- Test: `spec/domain/playlists/generate_for_date_spec.rb` (или новый `spec/domain/playlists/commercial_mix_spec.rb` если вынесешь mixer)

**Interfaces:**
- Consumes: occupying plans whose `media_plan_screens` include the screen OR legacy group membership
- Produces: `occupying_plans_for(screen, slot_start) -> Array<MediaPlan>` covering `[starts_at, ends_at)`
- `emit_commercial`:
  1. `plans = occupying_plans_for(...)`
  2. если пусто — нынешний filler fallback
  3. если ровно один план **без** `advertising_order_line_id` — текущее поведение (один plan, headers если commercial)
  4. иначе (есть order claims и/или несколько планов): шапки start **один раз**, если любой план `commercial?`; клипы — round-robin по планам, с каждого плана за этот commercial-слот `min(ceil(plan.shows_per_hour / N), remaining_in_row)` клипов, суммарно не больше `portrait.max_commercial_in_row`; шапки end один раз если был commercial; `media_plan_id` на emission — id плана-источника клипа

`N = portrait.block_frequency_per_hour`. Недобор клипов не ломает max-in-row (как AE5 портрета).

- [ ] **Step 1: Failing generator spec**

Два commercial order-plan на один экран, `shows_per_hour: 3`, портрет N=4, `max_commercial_in_row: 3`. В commercial-слоте часа есть клипы **обоих** `media_asset` (ротации двух оргов). Не только первого `occupying_plans.find`.

- [ ] **Step 2: Run to verify fail**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/playlists/generate_for_date_spec.rb`

Expected: FAIL (второй ролик отсутствует — генератор берёт один план).

- [ ] **Step 3: Implement mix in `emit_commercial` / `occupying_plans_for`**

`Fingerprint.occupying_plans` уже грузит планы дня — добавить `includes(:media_plan_screens, broadcast_point_group: :screens)` если ещё нет.

План покрывает экран если `plan.media_plan_screens.any? { |m| m.screen_id == screen.id } || plan.broadcast_point_group&.screens&.any? { |s| s.id == screen.id }`.

- [ ] **Step 4: Run playlist specs**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/playlists`

Expected: PASS. Не сломать AE с одним планом.

- [ ] **Step 5: Commit**

```bash
git add app/domain/playlists spec/domain/playlists
git commit -m "feat: mix overlapping order commercials in the hourly portrait block"
```

---

### Task 8: Печать, system spec, CONCEPTS, регресс

**Files:**
- Modify: `app/components/advertising/print_sheet_component.html.slim` + `.rb` + spec — строка сетки показывает экран, не группу; частота с заказа; окна
- Modify: `spec/system/advertising_order_placement_spec.rb` — чекбокс экрана, `shows_per_hour`, одно окно, без select группы и цены; активация; при двух заказах не требовать `MediaPlan.active.count == 1`
- Modify: `CONCEPTS.md` — Advertising order: line = screen; Shows per hour on the order; commercial order claims share the hour; Guard FWW only for non-order plans
- Grep leftover `broadcast_point_group_id` in `spec/domain/advertising`, `spec/requests/advertising_orders`, `spec/components`

- [ ] **Step 1: Failing print/system expectations**

Print spec: body includes screen name, `shows_per_hour`, window `09:00`.

System: check `order_screen_#{id}`, fill shows_per_hour `3`, add window 09:00–12:00, submit, activate, `MediaPlan.active.count >= 1`.

- [ ] **Step 2: Run to verify fail**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/components/advertising/print_sheet_component_spec.rb spec/system/advertising_order_placement_spec.rb`

Expected: FAIL until copy/selectors updated.

- [ ] **Step 3: Implement print + system + CONCEPTS**

- [ ] **Step 4: Full related suite**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/advertising spec/domain/airtime spec/domain/playlists spec/requests/advertising_orders_spec.rb spec/requests/admin/advertising_orders_spec.rb spec/system/advertising_order_placement_spec.rb spec/components/advertising spec/models/advertising_order_line_spec.rb spec/models/advertising_order_window_spec.rb`

Expected: 0 failures.

- [ ] **Step 5: Commit**

```bash
git add app/components spec/system spec/components CONCEPTS.md
git commit -m "feat: print and cabinet journey for per-screen order grids"
```

---

## Spec coverage (self-review)

| Spec requirement | Task |
|---|---|
| Строка сетки = экран, полный каталог в админке и кабинете | 4 |
| Частота и интервалы на заказ | 1, 4 |
| Ячейка = частота × пересечение часов; ноль = skip | 2, 3, 4 |
| Выходные подсвечены, не обнуляются сами | 4 |
| Нет цены/коэф/скидки на форме | 4 (уже частично) |
| Удалить старые групповые заказы | 1 |
| Occupy per screen × window ranges | 5, 6 |
| Два коммерческих заказа не ConflictError | 5, 6 |
| Плейлист мешает ролики по портрету | 7 |
| Квота soft | не менять `CommercialQuota::Check` |
| Ручной медиаплан остаётся FWW | 5 |

Нет TODO/TBD в шагах. `order_claim` / `media_plan_screens` / `ScreenDayHours.call` имена сквозные.

**Не в этом плане:** интервалы через полночь; дроп колонок цены/скидки; ослабление FWW между ручным слотом и заказом.
