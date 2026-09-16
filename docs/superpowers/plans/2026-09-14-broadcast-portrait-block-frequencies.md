# Набор частот блока в портрете эфира Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Портрет хранит подмножество каталога частот `1,2,3,4,5,6,10,12,20`; заказ выбирает одно `shows_per_hour` из пересечения после экранов; генератор режет час по НОК каталожных частот occupying-заказов.

**Architecture:** Колонка `broadcast_portraits.block_frequencies_per_hour integer[]` + константа каталога. Пересечение — `Portraits::FrequencySet`. Нарезка часа — `Playlists::HourGrid` (НОК / max набора). Форма заказа: пикер экранов выше `select` частоты, Stimulus пересобирает options.

**Tech Stack:** Rails 8.1, PostgreSQL 18 integer[], RSpec/FactoryBot, Slim+daisyUI (кабинет), ERB+Flowbite (админка портрета), общая `_form` заказа, Stimulus.

**Spec:** `docs/superpowers/specs/2026-09-14-broadcast-portrait-block-frequencies-design.md`

## Global Constraints

- Тесты только: `docker compose exec -e RAILS_ENV=test web bundle exec rspec …` (`RAILS_ENV=test` обязателен).
- TDD: Red → Green. Не писать production-код до падающего теста.
- UI copy: `config/locales/mediateca.ru.yml` + `mediateca.en.yml`.
- Admin `/admin` портрета — Flowbite, без daisyUI. Форма заказа в админке — существующий Slim `_form` (daisyUI), не трогать CSS-миры.
- Mutations that redirect: `status: :see_other`.
- Ruby: single quotes, если нет интерполяции. Каталог не в таблице.
- Ручной `MediaPlan` number_field каталогом не ограничиваем.
- Живые заказы при сужении набора не откатываем.
- Не коммитить `.env` / credentials.

## File map

| File | Responsibility |
|------|----------------|
| `db/migrate/20260914120000_replace_portrait_block_frequency_with_set.rb` | Колонка-массив, backfill, drop скаляра и старого check |
| `app/models/broadcast_portrait.rb` | Каталог, нормализация, валидации, `catalog_value_for` |
| `app/domain/portraits/frequency_set.rb` | Пересечение наборов экранов |
| `app/domain/portraits/copy_template.rb` | Копирует массив |
| `app/domain/playlists/hour_grid.rb` | N = НОК / max; удар `i % (N/f) == 0` |
| `app/domain/playlists/generate_for_date.rb` | Слоты по clock-hour; beat-path для каталожных order-claim |
| `app/domain/playlists/fingerprint.rb` | Хеш массива |
| `app/domain/advertising/assert_shows_per_hour.rb` | Серверная проверка пересечения перед сеткой |
| `app/controllers/concerns/advertising_order_grid.rb` | Вызов assert до `UpdateGrid` |
| `app/controllers/admin/broadcast_portraits_controller.rb` | permit массива, default `[4]` |
| `app/views/admin/broadcast_portraits/_form.html.erb` | Чекбоксы каталога |
| `app/views/admin/broadcast_portraits/show.html.erb` | Список частот |
| `app/views/advertising_orders/_form.html.slim` | Пикер выше частоты; `select` |
| `app/views/advertising_orders/_screen_picker.html.slim` | `data-frequencies` |
| `app/javascript/controllers/order_screen_picker_controller.js` | Пересечение → options селекта |
| `spec/support/playlist_generation.rb` | `frequencies:` вместо скаляра |
| `spec/factories/broadcast_portraits.rb` | `block_frequencies_per_hour { [4] }` |

---

### Task 1: Миграция, модель, factory, drop-in `max` в генераторе

**Files:**
- Create: `db/migrate/20260914120000_replace_portrait_block_frequency_with_set.rb`
- Modify: `app/models/broadcast_portrait.rb`
- Modify: `spec/models/broadcast_portrait_spec.rb`
- Modify: `spec/factories/broadcast_portraits.rb`
- Modify: `app/domain/portraits/copy_template.rb`
- Modify: `spec/domain/portraits/copy_template_spec.rb`
- Modify: `app/domain/playlists/fingerprint.rb`
- Modify: `app/domain/playlists/generate_for_date.rb` (только `3600 / max` и `commercial_clip_count` через max)
- Modify: `spec/support/playlist_generation.rb`
- Modify: `spec/requests/admin/broadcast_portraits_spec.rb` (`portrait_attrs`)
- Modify: `config/locales/mediateca.ru.yml` / `mediateca.en.yml` (human attribute)

**Interfaces:**
- Produces: `BroadcastPortrait::BLOCK_FREQUENCIES_PER_HOUR`, `BroadcastPortrait.catalog_value_for(n)`, атрибут `block_frequencies_per_hour` (Array of Integer, sorted unique, cardinality ≥ 1).
- Consumes: существующие портреты со скаляром `block_frequency_per_hour`.

- [ ] **Step 1: Write failing model specs**

В `spec/models/broadcast_portrait_spec.rb` заменить пример `rejects a frequency outside 1..60` на:

```ruby
it 'normalizes frequencies to a unique sorted catalog subset' do
  portrait = build(:broadcast_portrait, block_frequencies_per_hour: [6, 4, 4])

  expect(portrait).to be_valid
  expect(portrait.block_frequencies_per_hour).to eq([4, 6])
end

it 'rejects an empty frequency set' do
  portrait = build(:broadcast_portrait, block_frequencies_per_hour: [])

  expect(portrait).not_to be_valid
  expect(portrait.errors[:block_frequencies_per_hour]).to be_present
end

it 'rejects a frequency outside the catalog' do
  portrait = build(:broadcast_portrait, block_frequencies_per_hour: [4, 8])

  expect(portrait).not_to be_valid
  expect(portrait.errors[:block_frequencies_per_hour]).to be_present
end

it 'maps legacy scalars onto the catalog (8 -> 6)' do
  expect(BroadcastPortrait.catalog_value_for(4)).to eq(4)
  expect(BroadcastPortrait.catalog_value_for(8)).to eq(6)
  expect(BroadcastPortrait.catalog_value_for(0)).to eq(1)
end
```

Factory: `block_frequencies_per_hour { [4] }`, убрать `block_frequency_per_hour`.

- [ ] **Step 2: Run model spec to verify it fails**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/models/broadcast_portrait_spec.rb`
Expected: FAIL — unknown attribute / constant `catalog_value_for`.

- [ ] **Step 3: Migration + model**

`db/migrate/20260914120000_replace_portrait_block_frequency_with_set.rb`:

```ruby
# frozen_string_literal: true

class ReplacePortraitBlockFrequencyWithSet < ActiveRecord::Migration[8.1]
  CATALOG = [1, 2, 3, 4, 5, 6, 10, 12, 20].freeze

  def up
    add_column :broadcast_portraits, :block_frequencies_per_hour, :integer, array: true

    catalog_sql = CATALOG.join(',')
    execute <<~SQL
      UPDATE broadcast_portraits
      SET block_frequencies_per_hour = ARRAY[mapped.n]::integer[]
      FROM (
        SELECT id,
          CASE
            WHEN block_frequency_per_hour = ANY(ARRAY[#{catalog_sql}]) THEN block_frequency_per_hour
            ELSE COALESCE(
              (SELECT MAX(v) FROM unnest(ARRAY[#{catalog_sql}]) AS v
               WHERE v <= block_frequency_per_hour),
              1
            )
          END AS n
        FROM broadcast_portraits
      ) mapped
      WHERE broadcast_portraits.id = mapped.id
    SQL

    change_column_null :broadcast_portraits, :block_frequencies_per_hour, false
    add_check_constraint :broadcast_portraits,
      'cardinality(block_frequencies_per_hour) >= 1',
      name: 'broadcast_portraits_block_frequencies_present'
    add_check_constraint :broadcast_portraits,
      "block_frequencies_per_hour <@ ARRAY[#{catalog_sql}]::integer[]",
      name: 'broadcast_portraits_block_frequencies_catalog'
    remove_check_constraint :broadcast_portraits, 'broadcast_portraits_block_frequency_per_hour_range'
    remove_column :broadcast_portraits, :block_frequency_per_hour
  end

  def down
    add_column :broadcast_portraits, :block_frequency_per_hour, :integer
    execute <<~SQL
      UPDATE broadcast_portraits
      SET block_frequency_per_hour = block_frequencies_per_hour[1]
    SQL
    change_column_null :broadcast_portraits, :block_frequency_per_hour, false
    add_check_constraint :broadcast_portraits,
      'block_frequency_per_hour >= 1 AND block_frequency_per_hour <= 60',
      name: 'broadcast_portraits_block_frequency_per_hour_range'
    remove_check_constraint :broadcast_portraits, 'broadcast_portraits_block_frequencies_present'
    remove_check_constraint :broadcast_portraits, 'broadcast_portraits_block_frequencies_catalog'
    remove_column :broadcast_portraits, :block_frequencies_per_hour
  end
end
```

В `BroadcastPortrait`:

```ruby
BLOCK_FREQUENCIES_PER_HOUR = [1, 2, 3, 4, 5, 6, 10, 12, 20].freeze

before_validation :normalize_block_frequencies_per_hour

validates :block_frequencies_per_hour, presence: true
validate :block_frequencies_must_be_catalog_subset

def self.catalog_value_for(value)
  number = Integer(value)
  return number if BLOCK_FREQUENCIES_PER_HOUR.include?(number)

  BLOCK_FREQUENCIES_PER_HOUR.select { |item| item <= number }.max || BLOCK_FREQUENCIES_PER_HOUR.first
rescue ArgumentError, TypeError
  BLOCK_FREQUENCIES_PER_HOUR.first
end

def hour_slot_count
  Array(block_frequencies_per_hour).max
end

private

def normalize_block_frequencies_per_hour
  values = Array(block_frequencies_per_hour).filter_map { |item| Integer(item, exception: false) }
  self.block_frequencies_per_hour = values.uniq.sort
end

def block_frequencies_must_be_catalog_subset
  return if block_frequencies_per_hour.blank?

  extras = block_frequencies_per_hour - BLOCK_FREQUENCIES_PER_HOUR
  errors.add(:block_frequencies_per_hour, :inclusion) if extras.any?
end
```

Ransack: заменить `block_frequency_per_hour` на ничего (массив не ищем).

`CopyTemplate#copy_from`: `block_frequencies_per_hour: source.block_frequencies_per_hour`.

`Fingerprint#portrait_payload`: `block_frequencies_per_hour: portrait.block_frequencies_per_hour`.

`GenerateForDate`:

```ruby
n = portrait.hour_slot_count
# commercial_clip_count и build_slots: 3600 / portrait.hour_slot_count
```

`playlist_generation.rb`:

```ruby
def create_cyclic_portrait!(..., frequencies: [4], frequency: nil, ...)
  freqs = frequency ? [frequency] : frequencies
  # build_cyclic_portrait_for_screen!: block_frequencies_per_hour: Array(freqs)
```

Оставить kwarg `frequency:` как alias на одноэлементный массив, чтобы старые вызовы `frequency: 4` не падали, пока Task 5 не перепишет хелперы.

`portrait_attrs` в admin request spec: `block_frequencies_per_hour: [4]`.

Локали `activerecord.attributes.broadcast_portrait.block_frequencies_per_hour`: «Допустимые блоки в час» / «Allowed blocks per hour». Ключ скаляра удалить.

- [ ] **Step 4: Migrate and run focused specs**

Run:

```bash
docker compose exec -e RAILS_ENV=test web bin/rails db:migrate
docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/models/broadcast_portrait_spec.rb spec/domain/portraits/copy_template_spec.rb spec/domain/playlists/fingerprint_spec.rb spec/domain/playlists/generate_for_date_spec.rb spec/requests/admin/broadcast_portraits_spec.rb
```

Expected: PASS (генератор ещё режет час через `max` набора = 4 для factory).

- [ ] **Step 5: Commit**

```bash
git checkout -b feat/portrait-block-frequencies
git add db/migrate/20260914120000_replace_portrait_block_frequency_with_set.rb db/schema.rb app/models/broadcast_portrait.rb spec/models/broadcast_portrait_spec.rb spec/factories/broadcast_portraits.rb app/domain/portraits/copy_template.rb spec/domain/portraits/copy_template_spec.rb app/domain/playlists/fingerprint.rb app/domain/playlists/generate_for_date.rb spec/support/playlist_generation.rb spec/requests/admin/broadcast_portraits_spec.rb config/locales/mediateca.ru.yml config/locales/mediateca.en.yml
git commit -m "$(cat <<'EOF'
Store portrait block frequencies as a catalog integer[].

Replace the 1..60 scalar so templates can carry the allowed subset; playlist slot count temporarily uses max(set) so existing generate specs stay green.
EOF
)"
```

---

### Task 2: Админка портрета — чекбоксы каталога

**Files:**
- Modify: `app/controllers/admin/broadcast_portraits_controller.rb`
- Modify: `app/views/admin/broadcast_portraits/_form.html.erb`
- Modify: `app/views/admin/broadcast_portraits/show.html.erb`
- Modify: `spec/requests/admin/broadcast_portraits_spec.rb`

**Interfaces:**
- Consumes: `BroadcastPortrait::BLOCK_FREQUENCIES_PER_HOUR`, default `[4]`.
- Produces: permit `block_frequencies_per_hour: []`; HTML checkboxes `broadcast_portrait[block_frequencies_per_hour][]`.

- [ ] **Step 1: Write failing request example**

В `spec/requests/admin/broadcast_portraits_spec.rb` в пример создания добавить:

```ruby
expect(response.body).to include('broadcast_portrait[block_frequencies_per_hour][]')
```

на `get new_admin_broadcast_portrait_path` (новый example):

```ruby
it 'renders catalog frequency checkboxes instead of a 1..60 number field' do
  get new_admin_broadcast_portrait_path

  expect(response).to have_http_status(:success)
  expect(response.body).to include('broadcast_portrait[block_frequencies_per_hour][]')
  expect(response.body).not_to include('block_frequency_per_hour')
end
```

И в create-example: `block_frequencies_per_hour: [4, 6]`, затем `expect(portrait.block_frequencies_per_hour).to eq([4, 6])`.

- [ ] **Step 2: Run request spec to verify it fails**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/requests/admin/broadcast_portraits_spec.rb`
Expected: FAIL — нет checkbox name / Unpermitted.

- [ ] **Step 3: Controller + views**

`new`: `block_frequencies_per_hour: [4]`.

`portrait_header_params`:

```ruby
permitted = params.require(:broadcast_portrait).permit(
  :name, :max_commercial_in_row, :neutral_min_seconds, :is_default,
  block_frequencies_per_hour: []
)
permitted[:block_frequencies_per_hour] = Array(permitted[:block_frequencies_per_hour]).map(&:to_i)
permitted = permitted.except(:is_default) if @portrait&.screen_id.present?
permitted
```

`_form.html.erb` вместо number_field:

```erb
<fieldset class="mb-5">
  <legend class="<%= admin_label_class %>"><%= f.label :block_frequencies_per_hour %></legend>
  <div class="mt-2 flex flex-wrap gap-4">
    <% BroadcastPortrait::BLOCK_FREQUENCIES_PER_HOUR.each do |frequency| %>
      <label class="flex items-center gap-2 text-sm text-gray-900">
        <%= check_box_tag 'broadcast_portrait[block_frequencies_per_hour][]',
              frequency,
              Array(portrait.block_frequencies_per_hour).include?(frequency),
              class: admin_checkbox_class,
              id: "broadcast_portrait_block_frequencies_per_hour_#{frequency}" %>
        <%= frequency %>
      </label>
    <% end %>
  </div>
</fieldset>
```

`show.html.erb`: `Array(@portrait.block_frequencies_per_hour).join(', ')`.

- [ ] **Step 4: Run request spec**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/requests/admin/broadcast_portraits_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/admin/broadcast_portraits_controller.rb app/views/admin/broadcast_portraits/_form.html.erb app/views/admin/broadcast_portraits/show.html.erb spec/requests/admin/broadcast_portraits_spec.rb
git commit -m "$(cat <<'EOF'
Let operators pick portrait frequencies from catalog checkboxes.

EOF
)"
```

---

### Task 3: Пересечение наборов и серверная валидация заказа

**Files:**
- Create: `app/domain/portraits/frequency_set.rb`
- Create: `spec/domain/portraits/frequency_set_spec.rb`
- Create: `app/domain/advertising/assert_shows_per_hour.rb`
- Create: `spec/domain/advertising/assert_shows_per_hour_spec.rb`
- Modify: `app/controllers/concerns/advertising_order_grid.rb`
- Modify: `config/locales/mediateca.ru.yml` / `mediateca.en.yml`

**Interfaces:**
- Produces: `Portraits::FrequencySet.intersection_for_screens(screens) -> Array<Integer>` (sorted; `[]` если экранов нет или пересечение пусто).
- Produces: `Advertising::AssertShowsPerHour.call(order:, screens:)` — no-op если `screens.empty?`; иначе пустое пересечение → `errors.add(:advertising_order_lines, :empty_frequency_intersection)`; частота не из пересечения (и не nil) → `errors.add(:shows_per_hour, :not_in_portrait_intersection)`; в обоих случаях `raise Advertising::InvalidGrid.new(order)`.
- Consumes: `broadcast_portrait.block_frequencies_per_hour`, `Advertising::InvalidGrid`.

- [ ] **Step 1: Write failing FrequencySet spec**

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Portraits::FrequencySet do
  def portrait_for(values)
    create(:broadcast_portrait, :for_screen, block_frequencies_per_hour: values)
  end

  it 'returns the sorted intersection of selected screens' do
    a = portrait_for([4, 6, 12]).screen
    b = portrait_for([2, 4, 6]).screen

    expect(described_class.intersection_for_screens([a, b])).to eq([4, 6])
  end

  it 'is empty when any screen has no overlapping values' do
    a = portrait_for([4]).screen
    b = portrait_for([6]).screen

    expect(described_class.intersection_for_screens([a, b])).to eq([])
  end

  it 'is empty when the list of screens is empty' do
    expect(described_class.intersection_for_screens([])).to eq([])
  end
end
```

- [ ] **Step 2: Run FrequencySet spec to verify it fails**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/portraits/frequency_set_spec.rb`
Expected: FAIL — uninitialized constant.

- [ ] **Step 3: Implement FrequencySet**

```ruby
# frozen_string_literal: true

module Portraits
  class FrequencySet
    def self.intersection_for_screens(screens)
      list = Array(screens)
      return [] if list.empty?

      list.map { |screen| Array(screen.broadcast_portrait&.block_frequencies_per_hour) }
        .reduce { |acc, set| acc & set }
        .sort
    end
  end
end
```

- [ ] **Step 4: Run FrequencySet spec**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/portraits/frequency_set_spec.rb`
Expected: PASS.

- [ ] **Step 5: Write failing AssertShowsPerHour spec**

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Advertising::AssertShowsPerHour do
  let(:order) { create(:advertising_order, shows_per_hour: 4) }

  def screen_with(values)
    create(:broadcast_portrait, :for_screen, block_frequencies_per_hour: values).screen
  end

  it 'does nothing when no screens are selected' do
    expect { described_class.call(order: order, screens: []) }.not_to raise_error
  end

  it 'rejects a disjoint set of screens' do
    expect {
      described_class.call(order: order, screens: [screen_with([4]), screen_with([6])])
    }.to raise_error(Advertising::InvalidGrid)
    expect(order.errors[:advertising_order_lines]).to be_present
  end

  it 'rejects a frequency outside the intersection' do
    screens = [screen_with([4, 6]), screen_with([6, 12])]
    order.shows_per_hour = 4
    expect { described_class.call(order: order, screens: screens) }.to raise_error(Advertising::InvalidGrid)
    expect(order.errors[:shows_per_hour]).to be_present
  end

  it 'allows a frequency in the intersection' do
    screens = [screen_with([4, 6]), screen_with([6, 12])]
    order.shows_per_hour = 6
    expect { described_class.call(order: order, screens: screens) }.not_to raise_error
  end
end
```

- [ ] **Step 6: Run assert spec to verify it fails**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/advertising/assert_shows_per_hour_spec.rb`
Expected: FAIL — uninitialized constant.

- [ ] **Step 7: Implement AssertShowsPerHour + wire persist_grid!**

```ruby
# frozen_string_literal: true

module Advertising
  class AssertShowsPerHour < BaseService
    def initialize(order:, screens:)
      @order = order
      @screens = Array(screens)
    end

    def call
      return if screens.empty?

      allowed = Portraits::FrequencySet.intersection_for_screens(screens)
      if allowed.empty?
        order.errors.add(:advertising_order_lines, :empty_frequency_intersection)
        raise InvalidGrid.new(order)
      end
      return if order.shows_per_hour.nil?
      return if allowed.include?(order.shows_per_hour)

      order.errors.add(:shows_per_hour, :not_in_portrait_intersection)
      raise InvalidGrid.new(order)
    end

    private

    attr_reader :order, :screens
  end
end
```

В `AdvertisingOrderGrid#persist_grid!` сразу после `form_screen_ids` / перед `UpdateGrid`:

```ruby
screens = form_screen_ids.filter_map { |id| Screen.find_by(id: id) }
Advertising::AssertShowsPerHour.call(order: order, screens: screens)
```

i18n `activerecord.errors.models.advertising_order.attributes`:

- `advertising_order_lines.empty_frequency_intersection`: «у выбранных экранов нет общей частоты блока» / «selected screens have no common block frequency»
- `shows_per_hour.not_in_portrait_intersection`: «не входит в допустимые частоты выбранных экранов» / «is not allowed for the selected screens»

- [ ] **Step 8: Run assert + a request spec that saves a grid**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/advertising/assert_shows_per_hour_spec.rb spec/domain/portraits/frequency_set_spec.rb spec/requests/advertising_orders_spec.rb`
Expected: PASS. Если request spec создаёт заказ с `shows_per_hour: 3` на экране без портрета — добавить портрет `[3]` (или `[1,2,3,4]`) в setup этого spec. Не оставлять красный suite.

- [ ] **Step 9: Commit**

```bash
git add app/domain/portraits/frequency_set.rb spec/domain/portraits/frequency_set_spec.rb app/domain/advertising/assert_shows_per_hour.rb spec/domain/advertising/assert_shows_per_hour_spec.rb app/controllers/concerns/advertising_order_grid.rb spec/requests/advertising_orders_spec.rb config/locales/mediateca.ru.yml config/locales/mediateca.en.yml
git commit -m "$(cat <<'EOF'
Validate order shows_per_hour against portrait frequency intersection.

EOF
)"
```

---

### Task 4: Форма заказа — экраны, затем select из пересечения

**Files:**
- Modify: `app/views/advertising_orders/_form.html.slim`
- Modify: `app/views/advertising_orders/_screen_picker.html.slim`
- Modify: `app/javascript/controllers/order_screen_picker_controller.js`
- Modify: `spec/requests/advertising_orders_spec.rb`
- Modify: `spec/system/advertising_order_placement_spec.rb`
- Modify: `config/locales/mediateca.ru.yml` / `mediateca.en.yml` (hint под select, если ещё нет)

**Interfaces:**
- Consumes: `Portraits::FrequencySet` только на сервере; клиент считает пересечение из `data-frequencies`.
- Produces: `select` `advertising_order[shows_per_hour]` с `data-order-grid-target="showsPerHour"` и `data-order-screen-picker-target="showsPerHour"`. Disabled, пока пересечение пустое.

- [ ] **Step 1: Write failing request/system expectations**

В `spec/requests/advertising_orders_spec.rb` (new form):

```ruby
expect(response.body).to include('data-order-screen-picker-target="showsPerHour"')
expect(response.body).to include('advertising_order[screen_ids][]')
# number_field больше не используем:
expect(response.body).not_to match(/input[^>]*name="advertising_order\[shows_per_hour\]"[^>]*type="number"/)
```

В `spec/system/advertising_order_placement_spec.rb`:

- Перед визитом создать портрет экрана: `create(:broadcast_portrait, :for_screen, screen: screen, block_frequencies_per_hour: [1, 2, 3, 4, 6])`.
- Заменить `fill_in … shows_per_hour, with: "3"` на: сначала `check "order_screen_#{screen.id}"`, затем `select "3", from: "advertising_order_shows_per_hour"`.

- [ ] **Step 2: Run those specs to verify they fail**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/requests/advertising_orders_spec.rb spec/system/advertising_order_placement_spec.rb`
Expected: FAIL — всё ещё number_field / нет select.

- [ ] **Step 3: Reorder form + picker data + Stimulus**

В `_form.html.slim`: убрать блок `shows_per_hour` из верхней сетки. Порядок: продукт / placement_kind → `render screen_picker` (если `show_picker`) → затем:

```slim
div
  = f.label :shows_per_hour, t('.shows_per_hour'), class: 'block text-sm font-medium'
  = f.select :shows_per_hour,
      [],
      { include_blank: true },
      class: 'select select-bordered w-full mt-1',
      id: 'advertising_order_shows_per_hour',
      data: { order_grid_target: 'showsPerHour', order_screen_picker_target: 'showsPerHour', action: 'change->order-grid#recompute' }
  p.text-sm.text-base-content/60.mt-1 = t('.shows_per_hour_from_screens')
```

Ключи: `advertising_orders.form.shows_per_hour_from_screens` — «Сначала отметьте экраны. Доступны только общие частоты их портретов.» / «Select screens first. Only frequencies shared by their portraits are available.»

Окна и сетка — после частоты.

В `_screen_picker.html.slim` на `tr`:

```
data-frequencies=(Array(screen.broadcast_portrait&.block_frequencies_per_hour).to_json)
```

В `order_screen_picker_controller.js`:

- Добавить `showsPerHour` в `static targets`.
- В конце `selectionChanged` / `toggleAll` / `connect` вызывать `syncFrequencyOptions()`.

```javascript
syncFrequencyOptions() {
  if (!this.hasShowsPerHourTarget) return

  const selected = this.rowTargets.filter((row) => this.rowCheckbox(row)?.checked)
  const select = this.showsPerHourTarget
  const previous = select.value

  let options = []
  if (selected.length > 0) {
    const sets = selected.map((row) => {
      try {
        return JSON.parse(row.dataset.frequencies || "[]")
      } catch (_error) {
        return []
      }
    })
    options = sets.reduce((acc, set) => acc.filter((item) => set.includes(item)))
    options.sort((a, b) => a - b)
  }

  select.innerHTML = ""
  const blank = document.createElement("option")
  blank.value = ""
  select.append(blank)
  options.forEach((value) => {
    const option = document.createElement("option")
    option.value = String(value)
    option.textContent = String(value)
    select.append(option)
  })

  const keep = options.map(String).includes(previous) ? previous : ""
  select.value = keep
  select.disabled = options.length === 0
  this.dispatch("recompute", { prefix: "order-grid" })
}
```

На edit: после connect Stimulus выставит options; чтобы текущее `shows_per_hour` не моргнуло пустым, сервер может отрендерить options пересечения уже в `f.select` вторым аргументом:

```ruby
options_for_select(
  Portraits::FrequencySet.intersection_for_screens(@advertising_order.advertising_order_lines.filter_map(&:screen)),
  @advertising_order.shows_per_hour
)
```

Для new — пустой список, пока JS не отметит экраны.

- [ ] **Step 4: Run request + system specs**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/requests/advertising_orders_spec.rb spec/system/advertising_order_placement_spec.rb spec/requests/admin/advertising_orders_spec.rb`
Expected: PASS. В admin advertising_orders request spec, где заполняется `shows_per_hour: 3`, на каждый выбранный экран заранее повесить портрет с набором, содержащим `3` (например `[1, 2, 3, 4, 6]`), и выбирать частоту селектом, не number_field.

- [ ] **Step 5: Commit**

```bash
git add app/views/advertising_orders/_form.html.slim app/views/advertising_orders/_screen_picker.html.slim app/javascript/controllers/order_screen_picker_controller.js spec/requests/advertising_orders_spec.rb spec/system/advertising_order_placement_spec.rb spec/requests/admin/advertising_orders_spec.rb config/locales/mediateca.ru.yml config/locales/mediateca.en.yml
git commit -m "$(cat <<'EOF'
Choose order shows_per_hour from selected screens' frequency intersection.

EOF
)"
```

---

### Task 5: Генератор — НОК и удары заказов

**Files:**
- Create: `app/domain/playlists/hour_grid.rb`
- Create: `spec/domain/playlists/hour_grid_spec.rb`
- Modify: `app/domain/playlists/generate_for_date.rb`
- Modify: `spec/domain/playlists/generate_for_date_spec.rb`
- Modify: `spec/support/playlist_generation.rb` (по желанию убрать alias `frequency:` в новых вызовах)

**Interfaces:**
- Produces: `Playlists::HourGrid.slot_count(portrait:, occupying_plans:) -> Integer`
- Produces: `Playlists::HourGrid.catalog_hit?(plan, index, slot_count) -> bool`
- Produces: `Playlists::HourGrid.catalog_frequencies(plans) -> Array<Integer>`
- Consumes: `BroadcastPortrait::BLOCK_FREQUENCIES_PER_HOUR`, `plan.commercial?`, `plan.shows_per_hour`.

Правила (спека):

- Каталожные commercial occupying этого clock-hour → `N = НОК(частот)`; иначе `N = portrait.hour_slot_count` (max набора).
- Слоты: N штук от начала календарного часа локали, длина `3600/N`; обрезать по окну работы.
- Если в часе есть каталожные частоты заказов — **beat-path**: план с `f` играет при `i % (N/f) == 0`, **один** клип; non-catalog commercial мешается только в слоты, где уже есть удар; слот без ударов — filler; шапки wrap как сейчас.
- Если каталожных частот в часе нет — **cycle-path** как сегодня (`cycle_blocks` + `hour_slot_count`), чтобы AE3/AE6/own_atmosphere не разъехались. `commercial_clip_count` для cycle-path: `1` если `shows_per_hour.nil?`, иначе `[(shows_per_hour.to_f / portrait.hour_slot_count).ceil, max_commercial_in_row].min` — только здесь; beat-path всегда 1.

- [ ] **Step 1: Write failing HourGrid spec**

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Playlists::HourGrid do
  let(:portrait) { build(:broadcast_portrait, block_frequencies_per_hour: [4, 6, 12]) }

  def plan(shows, kind: :commercial)
    instance_double(MediaPlan, commercial?: kind == :commercial, shows_per_hour: shows)
  end

  it 'uses LCM of catalog commercial frequencies' do
    expect(described_class.slot_count(portrait: portrait, occupying_plans: [plan(4), plan(6)])).to eq(12)
  end

  it 'falls back to max portrait frequency when no catalog commercials occupy' do
    expect(described_class.slot_count(portrait: portrait, occupying_plans: [plan(nil, kind: :own_atmosphere)])).to eq(12)
    expect(described_class.slot_count(portrait: portrait, occupying_plans: [plan(7)])).to eq(12)
  end

  it 'places 4 and 6 hits on a 12-slot hour' do
    four = plan(4)
    six = plan(6)
    hits_four = (0...12).select { |i| described_class.catalog_hit?(four, i, 12) }
    hits_six = (0...12).select { |i| described_class.catalog_hit?(six, i, 12) }

    expect(hits_four).to eq([0, 3, 6, 9])
    expect(hits_six).to eq([0, 2, 4, 6, 8, 10])
  end
end
```

`own_atmosphere` на MediaPlan — проверить реальное имя enum `own_atmosphere?` / `commercial?`. Для double достаточно `commercial?: false`.

- [ ] **Step 2: Run HourGrid spec to verify it fails**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/playlists/hour_grid_spec.rb`
Expected: FAIL — uninitialized constant.

- [ ] **Step 3: Implement HourGrid**

```ruby
# frozen_string_literal: true

module Playlists
  class HourGrid
    CATALOG = BroadcastPortrait::BLOCK_FREQUENCIES_PER_HOUR

    def self.slot_count(portrait:, occupying_plans:)
      freqs = catalog_frequencies(occupying_plans)
      return Integer(portrait.hour_slot_count) if freqs.empty?

      freqs.reduce(:lcm)
    end

    def self.catalog_hit?(plan, index, slot_count)
      freq = plan.shows_per_hour
      return false unless catalog_frequency?(freq)
      return false if slot_count.to_i <= 0 || (slot_count % freq).nonzero?

      (index % (slot_count / freq)).zero?
    end

    def self.catalog_frequency?(value)
      value.present? && CATALOG.include?(value)
    end

    def self.catalog_frequencies(plans)
      Array(plans).filter_map do |plan|
        next unless plan.commercial?

        freq = plan.shows_per_hour
        freq if catalog_frequency?(freq)
      end.uniq
    end
  end
end
```

- [ ] **Step 4: Run HourGrid spec**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/playlists/hour_grid_spec.rb`
Expected: PASS.

- [ ] **Step 5: Write failing generate example for 4+6**

В `spec/domain/playlists/generate_for_date_spec.rb`:

```ruby
it 'places catalog order claims on LCM beats (4 and 6 -> 12 slots)' do
  station = create_playlist_station!
  screen = create(:screen, station: station)
  filler = create_clip_rotation!(organization: create(:organization, :client))
  create_cyclic_portrait!(station, filler_rotation: filler, frequencies: [4, 6, 12])

  first_org = create(:organization, :client)
  second_org = create(:organization, :client)
  occupy_order_claim!(
    screen: screen, organization: first_org,
    rotation: create_clip_rotation!(organization: first_org),
    starts_at: local_slot(9), ends_at: local_slot(10), shows_per_hour: 4
  )
  occupy_order_claim!(
    screen: screen, organization: second_org,
    rotation: create_clip_rotation!(organization: second_org),
    starts_at: local_slot(9), ends_at: local_slot(10), shows_per_hour: 6
  )

  hour = generate!(station).playlist.items.sort_by(&:offset_seconds).select do |item|
    item.offset_seconds < 3600 && item_screen_ids(item).include?(screen.id)
  end
  media = hour.select(&:media_plan?)
  filler_offsets = hour.select(&:filler?).map(&:offset_seconds)

  expect(media.count { |item| item.media_plan.shows_per_hour == 4 }).to eq(4)
  expect(media.count { |item| item.media_plan.shows_per_hour == 6 }).to eq(6)
  expect(filler_offsets).to include(300, 1500, 2100, 3300) # slots 1,5,7,11 at 5 minutes
end
```

Сохранить возвращаемые планы:

```ruby
four_plan = occupy_order_claim!(..., shows_per_hour: 4)
six_plan = occupy_order_claim!(..., shows_per_hour: 6)
expect(media.count { |item| item.media_plan_id == four_plan.id }).to eq(4)
expect(media.count { |item| item.media_plan_id == six_plan.id }).to eq(6)
```

- [ ] **Step 6: Run generate spec example to verify it fails**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/playlists/generate_for_date_spec.rb -e 'LCM beats'`
Expected: FAIL — counts not 4 and 6 (старый cycle + ceil).

- [ ] **Step 7: Wire GenerateForDate**

Заменить `build_slots(windows, portrait)` на построение троек `[start, end, index, n, covering_plans]` по каждому clock-hour, пересекающему окно:

```ruby
def build_slots(windows, screen, portrait)
  windows.flat_map do |window|
    hour = window[:start].change(min: 0, sec: 0)
    slots = []
    while hour < window[:end]
      hour_end = hour + 3600
      covering = occupying_plans.select do |plan|
        plan_covers_screen?(plan, screen) && plan.starts_at < hour_end && plan.ends_at > hour
      end
      count = Playlists::HourGrid.slot_count(portrait: portrait, occupying_plans: covering)
      step = 3600 / count
      count.times do |index|
        slot_start = hour + (step * index)
        slot_end = slot_start + step
        next if slot_end <= window[:start] || slot_start >= window[:end]

        clipped_start = slot_start < window[:start] ? window[:start] : slot_start
        clipped_end = slot_end > window[:end] ? window[:end] : slot_end
        slots << [clipped_start, clipped_end, index, count, covering]
      end
      hour = hour_end
    end
    slots
  end
end
```

В `emissions_for_screen` цикл по слотам:

```ruby
matching = insertions.select { |event| slot_start <= event[:at] && event[:at] < slot_end }.map { |event| event[:block] }
if matching.any?
  cycle_index += 1 if cycle.any?
  matching.flat_map { |block| emit_insertion(block, screen, portrait, slot_start, pickers) }
elsif Playlists::HourGrid.catalog_frequencies(covering).any?
  emit_beat_slot(screen, portrait, slot_start, index, count, pickers)
elsif cycle.empty?
  []
else
  block = cycle[cycle_index % cycle.size]
  cycle_index += 1
  emit_cycle_block(block, screen, portrait, slot_start, pickers)
end
```

`emit_beat_slot`:

```ruby
def emit_beat_slot(screen, portrait, slot_start, index, slot_count, pickers)
  occupying = occupying_plans_for(screen, slot_start)
  hitters = occupying.select { |plan| Playlists::HourGrid.catalog_hit?(plan, index, slot_count) }
  extras = occupying.select do |plan|
    plan.commercial? && plan.shows_per_hour.present? && !Playlists::HourGrid.catalog_frequency?(plan.shows_per_hour)
  end
  players = hitters + extras
  return emit_commercial_fallback(screen, portrait, slot_start, pickers) if players.empty?

  emit_mixed_commercial(players, screen, portrait, slot_start, pickers, clips_per_plan: 1)
end
```

Расширить `emit_mixed_commercial` / `commercial_clip_count` аргументом `clips_per_plan:` (default `nil` = старая формула для cycle-path). Для beat-path передавать `1`. `max_commercial_in_row` по-прежнему суммарный cap слота.

Переписать AE5 на `occupy_order_claim!(..., shows_per_hour: 2)` и портрет `frequencies: [2, 4]`, ожидание 2 `media_plan` за первый час.

Спека «wraps mixed order-claim commercials»: оба заказа `shows_per_hour: 3` → `N=3`, шаг 1200 с. Заменить фильтр `offset_seconds < 900` на `offset_seconds < 1200` (первый слот часа). Ожидания шапок + двух `media_plan` в этом слоте сохраняются.

- [ ] **Step 8: Run generate + hour_grid specs**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/playlists/hour_grid_spec.rb spec/domain/playlists/generate_for_date_spec.rb spec/domain/playlists/fingerprint_spec.rb`
Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add app/domain/playlists/hour_grid.rb spec/domain/playlists/hour_grid_spec.rb app/domain/playlists/generate_for_date.rb spec/domain/playlists/generate_for_date_spec.rb spec/support/playlist_generation.rb
git commit -m "$(cat <<'EOF'
Slice playlist hours by LCM of occupying catalog order frequencies.

EOF
)"
```

---

### Task 6: Добить i18n/fingerprint example и полный прогон

**Files:**
- Modify: `spec/domain/playlists/fingerprint_spec.rb` (явный example: смена набора частот меняет fingerprint без смены name)
- Grep: `block_frequency_per_hour` по репо — не должно остаться, кроме `down` миграции и changelog спеки.

- [ ] **Step 1: Write failing fingerprint example**

```ruby
it 'changes when block frequencies change' do
  station = create_playlist_station!
  filler = create_clip_rotation!(organization: create(:organization, :client))
  portrait = create_cyclic_portrait!(station, filler_rotation: filler, frequencies: [4])
  first = described_class.call(station: station, for_date: PlaylistGeneration::WEDNESDAY)

  portrait.update!(block_frequencies_per_hour: [4, 6])
  changed = described_class.call(station: station.reload, for_date: PlaylistGeneration::WEDNESDAY)

  expect(changed).not_to eq(first)
end
```

- [ ] **Step 2: Run to verify fail/pass (payload already hashes the array — should PASS immediately; if not, fix payload key)**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/playlists/fingerprint_spec.rb`

- [ ] **Step 3: Repo grep and full suite**

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec
```

Expected: PASS. `rg block_frequency_per_hour` — только migration `down` и, если нужно, schema comment истории.

- [ ] **Step 4: Commit**

```bash
git add spec/domain/playlists/fingerprint_spec.rb
git commit -m "$(cat <<'EOF'
Cover fingerprint changes when portrait frequency sets change.

EOF
)"
```

---

## Spec coverage (self-review)

| Spec requirement | Task |
|------------------|------|
| `integer[]` + каталог в коде + check cardinality/⊆ | 1 |
| Backfill 8→6 / in-catalog `ARRAY[n]` | 1 (`catalog_value_for` + SQL) |
| Default новой формы `[4]` | 2 |
| CopyTemplate копирует массив | 1 |
| Fingerprint массива | 1, 6 |
| Админ чекбоксы / show | 2 |
| Заказ: экраны затем select пересечения | 4 |
| Сервер: пустое пересечение / частота вне набора | 3 |
| Черновик без экранов, nil частота | 3 (early return) |
| НОК 4+6, удары, filler без удара, 1 клип | 5 |
| Без каталожных заказов — max набора + cycle | 5 |
| Non-catalog commercial не в НОК | 5 (`HourGrid` + extras only on hit slots) |
| Живые заказы не откатываем | нет кода (non-goal) |
| Ручной media plan number_field | нет кода (non-goal) |
