# Service Theme — папка «Нейтральный контент» — план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** При создании Service Theme добавлять пятую system-managed папку «Нейтральный контент» и при apply тематики подставлять её ротацию в блок `filler` портрета.

**Architecture:** FK `neutral_rotation_id` на `service_themes`. Сервисные kind остаются в `ROTATION_ROLES` (4 шт.). Роль `:neutral` — отдельная folder-role: клипы `content_type: neutral`, apply upsert’ит `filler` с `service_theme_id`. Генератор плейлиста не трогаем.

**Tech Stack:** Ruby 4.0.2, Rails 8.1, PostgreSQL 18, RSpec, FactoryBot, Slim/ERB admin (Flowbite).

**Спека:** `docs/superpowers/specs/2026-10-20-service-theme-neutral-folder-design.md`.

---

## Карта файлов

Новые:

- `db/migrate/TIMESTAMP_add_neutral_rotation_to_service_themes.rb` — колонка + backfill.

Изменяемые:

- `app/models/service_theme.rb` — FK, `FOLDER_ROLES`, `rotation_for`, `rotations`, content type helper.
- `app/domain/service_themes/create.rb` — пять ротаций.
- `app/domain/service_themes/add_clip.rb` — `content_type` по роли.
- `app/domain/service_themes/place_validated_clip.rb` — placeable по роли.
- `app/domain/portraits/apply_service_theme.rb` — upsert/clear filler.
- `app/models/broadcast_portrait_block.rb` — filler + `service_theme_id`; assign rotation.
- `app/models/screen.rb` — `neutral_pick_strategy` + `service_pick_strategies`.
- `app/controllers/admin/screens_controller.rb` — strong params / assign.
- `app/views/admin/screens/_form.html.erb` — пятый pick strategy (или общий цикл по folder roles).
- `app/views/admin/service_themes/show.html.erb` — итерация `FOLDER_ROLES`, подписи, content_type, place options.
- `app/helpers/admin_helper.rb` — options для validated neutral (или общий helper по content_type).
- `config/locales/mediateca.ru.yml` / `mediateca.en.yml` — folder label, empty description.
- `spec/factories/service_themes.rb`
- `spec/domain/service_themes/create_spec.rb`
- `spec/domain/service_themes/add_clip_spec.rb`
- `spec/domain/service_themes/place_validated_clip_spec.rb`
- `spec/domain/portraits/apply_service_theme_spec.rb`
- `spec/requests/admin/service_themes_spec.rb`
- `spec/models/broadcast_portrait_block_spec.rb` (или рядом — filler + theme)
- `docs/solutions/architecture-patterns/operator-service-theme-on-screen.md`
- `docs/solutions/architecture-patterns/broadcast-portrait-as-screen-airtime-structure.md`
- `db/schema.rb` (через migrate)

Команды — только в Docker:

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/path/to/spec.rb
docker compose exec -e RAILS_ENV=test web bin/ci
```

---

### Task 1: Миграция + модель + factory

**Files:**
- Create: `db/migrate/YYYYMMDDHHMMSS_add_neutral_rotation_to_service_themes.rb`
- Modify: `app/models/service_theme.rb`
- Modify: `spec/factories/service_themes.rb`
- Modify: `spec/domain/service_themes/create_spec.rb` (пока только expectation на константы/rotation_for — полный create в Task 2)
- Generated: `db/schema.rb`

- [ ] **Step 1: Написать падающий кусок create_spec на пятую роль**

В `spec/domain/service_themes/create_spec.rb` заменить пример AE1:

```ruby
it "creates a theme with five empty system-managed rotations including neutral" do
  theme = described_class.call(organization: operator, name: "Салон красоты")

  expect(theme).to be_persisted
  expect(theme.name).to eq("Салон красоты")
  expect(theme.rotations.size).to eq(5)
  expect(theme.rotations).to all(be_system_managed)
  expect(theme.rotations.map { |rotation| rotation.rotation_items.count }).to all(eq(0))
  expect(theme.header_start_rotation.name).to eq("Салон красоты · header_start")
  expect(theme.neutral_rotation.name).to eq("Салон красоты · neutral")
  expect(theme.rotation_for(:service_welcome)).to eq(theme.welcome_rotation)
  expect(theme.rotation_for(:neutral)).to eq(theme.neutral_rotation)
end
```

- [ ] **Step 2: Прогнать spec — ожидаем FAIL** (нет `neutral_rotation`)

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/service_themes/create_spec.rb
```

- [ ] **Step 3: Миграция с backfill**

```ruby
# frozen_string_literal: true

class AddNeutralRotationToServiceThemes < ActiveRecord::Migration[8.1]
  class MigrationRotation < ApplicationRecord
    self.table_name = "rotations"
  end

  class MigrationServiceTheme < ApplicationRecord
    self.table_name = "service_themes"
  end

  def up
    add_reference :service_themes, :neutral_rotation, foreign_key: { to_table: :rotations, on_delete: :restrict },
      null: true

    MigrationServiceTheme.reset_column_information
    MigrationServiceTheme.find_each do |theme|
      rotation = MigrationRotation.create!(
        organization_id: theme.organization_id,
        name: "#{theme.name} · neutral",
        system_managed: true
      )
      theme.update_columns(neutral_rotation_id: rotation.id)
    end

    change_column_null :service_themes, :neutral_rotation_id, false
  end

  def down
    remove_reference :service_themes, :neutral_rotation, foreign_key: true
  end
end
```

Прогнать migrate в test:

```bash
docker compose exec -e RAILS_ENV=test web bin/rails db:migrate
```

- [ ] **Step 4: Обновить `ServiceTheme`**

```ruby
ROTATION_ROLES = {
  header_start: "service_header_start",
  header_end: "service_header_end",
  welcome: "service_welcome",
  close: "service_close"
}.freeze

FOLDER_ROLES = (ROTATION_ROLES.keys + [ :neutral ]).freeze

CONTENT_TYPE_BY_ROLE = FOLDER_ROLES.index_with { |role|
  role == :neutral ? "neutral" : "service"
}.freeze

belongs_to :neutral_rotation, class_name: "Rotation"

def rotations
  [
    header_start_rotation,
    header_end_rotation,
    welcome_rotation,
    close_rotation,
    neutral_rotation
  ]
end

def rotation_for(role)
  case role.to_sym
  when :header_start, :service_header_start then header_start_rotation
  when :header_end, :service_header_end then header_end_rotation
  when :welcome, :service_welcome then welcome_rotation
  when :close, :service_close then close_rotation
  when :neutral then neutral_rotation
  end
end

def self.content_type_for_role(role)
  CONTENT_TYPE_BY_ROLE.fetch(role.to_sym)
rescue KeyError
  nil
end
```

Обновить `ransackable_associations` — добавить `neutral_rotation`.

- [ ] **Step 5: Factory**

```ruby
neutral_rotation { association :rotation, :system_managed, organization: organization }
```

- [ ] **Step 6: Create — проставить FK** (минимально, чтобы factory/create жили)

В `ServiceThemes::Create#call` добавить `neutral_rotation: rotations.fetch(:neutral)` и в `build_rotations` итерировать `ServiceTheme::FOLDER_ROLES` вместо `ROTATION_ROLES.keys`.

- [ ] **Step 7: Прогнать create_spec — PASS**

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/service_themes/create_spec.rb
```

- [ ] **Step 8: Commit**

```bash
git add db/migrate db/schema.rb app/models/service_theme.rb app/domain/service_themes/create.rb \
  spec/factories/service_themes.rb spec/domain/service_themes/create_spec.rb
git commit -m "$(cat <<'EOF'
feat(service-themes): add neutral_rotation folder on create

EOF
)"
```

---

### Task 2: AddClip / PlaceValidatedClip по content_type роли

**Files:**
- Modify: `app/domain/service_themes/add_clip.rb`
- Modify: `app/domain/service_themes/place_validated_clip.rb`
- Modify: `spec/domain/service_themes/add_clip_spec.rb`
- Modify: `spec/domain/service_themes/place_validated_clip_spec.rb`

- [ ] **Step 1: Падающие specs**

В `add_clip_spec.rb`:

```ruby
it "stores a neutral clip when uploading to the neutral folder" do
  asset = described_class.call(theme: theme, role: :neutral, file: png, uploaded_by: user)

  expect(asset).to have_attributes(content_type: "neutral", visibility: "network", organization: operator)
end
```

В `place_validated_clip_spec.rb` добавить пример: place validated `neutral` в `:neutral`; reject `service` asset в `:neutral` (и наоборот — опционально).

- [ ] **Step 2: FAIL**

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec \
  spec/domain/service_themes/add_clip_spec.rb \
  spec/domain/service_themes/place_validated_clip_spec.rb
```

- [ ] **Step 3: Реализация**

`AddClip#build_asset`:

```ruby
content_type: ServiceTheme.content_type_for_role(role) || :service
```

(после проверки `rotation_for` — неизвестная роль уже raise).

`PlaceValidatedClip#placeable?`:

```ruby
expected = ServiceTheme.content_type_for_role(role)
media_asset.content_validated? &&
  expected.present? &&
  media_asset.content_type == expected &&
  media_asset.organization_id == theme.organization_id
```

- [ ] **Step 4: PASS + commit**

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec \
  spec/domain/service_themes/add_clip_spec.rb \
  spec/domain/service_themes/place_validated_clip_spec.rb
git add app/domain/service_themes/add_clip.rb app/domain/service_themes/place_validated_clip.rb \
  spec/domain/service_themes/add_clip_spec.rb spec/domain/service_themes/place_validated_clip_spec.rb
git commit -m "$(cat <<'EOF'
feat(service-themes): neutral folder uses content_type neutral

EOF
)"
```

---

### Task 3: Admin show + i18n + place options

**Files:**
- Modify: `app/views/admin/service_themes/show.html.erb`
- Modify: `app/helpers/admin_helper.rb`
- Modify: `config/locales/mediateca.ru.yml`
- Modify: `config/locales/mediateca.en.yml`
- Modify: `spec/requests/admin/service_themes_spec.rb`

- [ ] **Step 1: Обновить request spec**

Пример «shows four folders» → five; ожидать текст «Нейтральный контент» (locale ru default). Create AE1 в request — `change` rotations / theme с 5 папками. Empty description — «пять» если проверяется.

- [ ] **Step 2: FAIL**

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/requests/admin/service_themes_spec.rb
```

- [ ] **Step 3: Локали**

`admin.service_themes.folder_labels.neutral`: ru «Нейтральный контент», en «Neutral content».  
`empty.description`: «пять … папок» / «five … folders».

- [ ] **Step 4: Helper**

```ruby
def admin_validated_theme_clip_options(rotation, content_type:)
  MediaAsset.public_send(:"content_type_#{content_type}")
    .where(organization_id: rotation.organization_id)
    .where.not(content_validated_at: nil)
    .where.not(content_validated_by_id: nil)
    .where.not(id: rotation.rotation_items.select(:media_asset_id))
    .includes(file_attachment: :blob)
    .filter_map { |asset| [ asset.file.filename.to_s, asset.id ] if asset.file.attached? }
end

def admin_validated_service_clip_options(rotation)
  admin_validated_theme_clip_options(rotation, content_type: :service)
end
```

- [ ] **Step 5: show.html.erb**

Итерировать `ServiceTheme::FOLDER_ROLES`. Для роли:

```erb
<% kind = ServiceTheme::ROTATION_ROLES[role] %>
<% title = kind ? t("enums.broadcast_portrait_block.kind.#{kind}") : t("admin.service_themes.folder_labels.#{role}") %>
<% content_type = ServiceTheme.content_type_for_role(role) %>
```

Hidden `clip[content_type]` = `content_type`.  
Place select: `admin_validated_theme_clip_options(rotation, content_type: content_type)`.

- [ ] **Step 6: PASS + commit**

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/requests/admin/service_themes_spec.rb
git add app/views/admin/service_themes/show.html.erb app/helpers/admin_helper.rb \
  config/locales/mediateca.ru.yml config/locales/mediateca.en.yml \
  spec/requests/admin/service_themes_spec.rb
git commit -m "$(cat <<'EOF'
feat(admin): show neutral content folder on service themes

EOF
)"
```

---

### Task 4: Filler validation + ApplyServiceTheme

**Files:**
- Modify: `app/models/broadcast_portrait_block.rb`
- Modify: `app/domain/portraits/apply_service_theme.rb`
- Modify: `spec/domain/portraits/apply_service_theme_spec.rb`
- Modify: `spec/models/broadcast_portrait_block_spec.rb` (создать/дополнить)

- [ ] **Step 1: Падающие specs**

`apply_service_theme_spec.rb`:

```ruby
it "upserts filler from theme neutral rotation and clears theme-owned filler" do
  create(:broadcast_portrait_block, :commercial, broadcast_portrait: portrait, position: 1)

  described_class.call(
    portrait: portrait,
    theme: theme,
    pick_strategies: { neutral: "random" }
  )

  portrait.reload
  filler = portrait.blocks.find_by!(kind: "filler")
  expect(filler).to have_attributes(
    service_theme: theme,
    rotation: theme.neutral_rotation,
    pick_strategy: "random"
  )

  described_class.call(portrait: portrait, theme: nil)
  portrait.reload
  expect(portrait.blocks.map(&:kind)).to eq(%w[commercial])
end

it "keeps a non-theme filler when clearing a theme that never owned filler" do
  other_rotation = create(:rotation, organization: theme.organization)
  create(:broadcast_portrait_block, :filler, broadcast_portrait: portrait, position: 1,
    rotation: other_rotation, pick_strategy: "sequential")
  # portrait has no service_theme; clear is no-op for filler
  described_class.call(portrait: portrait, theme: nil)
  expect(portrait.reload.blocks.find_by!(kind: "filler").rotation).to eq(other_rotation)
end
```

И пример: apply перезаписывает существующий non-theme filler.

Model: filler с `service_theme` валиден.

- [ ] **Step 2: FAIL**

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec \
  spec/domain/portraits/apply_service_theme_spec.rb \
  spec/models/broadcast_portrait_block_spec.rb
```

- [ ] **Step 3: `BroadcastPortraitBlock`**

В `fields_match_kind` для `"filler"` — убрать `reject_service_theme`.

`assign_rotation_from_service_theme`:

```ruby
def assign_rotation_from_service_theme
  return unless service_theme

  if service_kind?
    self.rotation = service_theme.rotation_for(kind)
  elsif filler?
    self.rotation = service_theme.neutral_rotation
  end
end
```

- [ ] **Step 4: `ApplyServiceTheme`**

После цикла `ROTATION_ROLES`:

```ruby
upsert_filler_from_theme!
```

```ruby
def upsert_filler_from_theme!
  block = portrait.blocks.find_or_initialize_by(kind: "filler")
  if block.new_record?
    block.position = (portrait.blocks.maximum(:position).to_i) + 1
  end
  block.assign_attributes(
    service_theme: theme,
    rotation: theme.neutral_rotation,
    pick_strategy: strategy_for(:neutral),
    time_of_day: nil
  )
  block.save!
end
```

`clear_theme!`:

```ruby
portrait.blocks.where(kind: ServiceTheme::ROTATION_ROLES.values).find_each(&:destroy!)
portrait.blocks.where(kind: "filler").where.not(service_theme_id: nil).find_each(&:destroy!)
portrait.update!(service_theme: nil)
```

Обновить комментарий/описание AE3: «four service + filler».

- [ ] **Step 5: PASS + commit**

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec \
  spec/domain/portraits/apply_service_theme_spec.rb \
  spec/models/broadcast_portrait_block_spec.rb
git add app/models/broadcast_portrait_block.rb app/domain/portraits/apply_service_theme.rb \
  spec/domain/portraits/apply_service_theme_spec.rb spec/models/broadcast_portrait_block_spec.rb
git commit -m "$(cat <<'EOF'
feat(portraits): apply service theme neutral folder as filler

EOF
)"
```

---

### Task 5: Screen `neutral_pick_strategy`

**Files:**
- Modify: `app/models/screen.rb`
- Modify: `app/controllers/admin/screens_controller.rb`
- Modify: `app/views/admin/screens/_form.html.erb`
- Modify: `spec/requests/admin/screens_spec.rb` (если есть кейсы theme strategies)

- [ ] **Step 1: Model**

```ruby
attribute :neutral_pick_strategy, :string, default: "sequential"

def service_pick_strategies
  {
    header_start: header_start_pick_strategy,
    header_end: header_end_pick_strategy,
    welcome: welcome_pick_strategy,
    close: close_pick_strategy,
    neutral: neutral_pick_strategy
  }
end
```

- [ ] **Step 2: Controller**

В permit — `:neutral_pick_strategy`.  
В `assign_service_theme_fields` — читать strategy с filler-блока в `neutral_pick_strategy`.

```ruby
filler = portrait.blocks.detect(&:filler?)
screen.neutral_pick_strategy = filler.pick_strategy if filler&.pick_strategy.present?
```

- [ ] **Step 3: Form**

После цикла `ROTATION_ROLES` (или расширить цикл) — select для `neutral_pick_strategy` с label `t("admin.service_themes.folder_labels.neutral")`.

- [ ] **Step 4: Request spec** — при сохранении экрана с theme + `neutral_pick_strategy: random` filler получает random (если уже есть покрытие apply — расширить).

- [ ] **Step 5: PASS + commit**

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/requests/admin/screens_spec.rb
git add app/models/screen.rb app/controllers/admin/screens_controller.rb \
  app/views/admin/screens/_form.html.erb spec/requests/admin/screens_spec.rb
git commit -m "$(cat <<'EOF'
feat(admin): neutral pick strategy on screen theme apply

EOF
)"
```

---

### Task 6: Docs solutions + полный CI

**Files:**
- Modify: `docs/solutions/architecture-patterns/operator-service-theme-on-screen.md`
- Modify: `docs/solutions/architecture-patterns/broadcast-portrait-as-screen-airtime-structure.md`

- [ ] **Step 1: Обновить solutions**

`operator-service-theme-on-screen.md`: пять папок; apply пишет четыре service + filler; guidance «fifth folder» = `FOLDER_ROLES` / `neutral_rotation`, не новый service kind.  
`broadcast-portrait-as-screen-airtime-structure.md`: `service_theme_id` материализует четыре service + theme-owned filler.

- [ ] **Step 2: bin/ci**

```bash
docker compose exec -e RAILS_ENV=test web bin/ci
```

Ожидание: green.

- [ ] **Step 3: Commit docs**

```bash
git add docs/solutions/architecture-patterns/operator-service-theme-on-screen.md \
  docs/solutions/architecture-patterns/broadcast-portrait-as-screen-airtime-structure.md
git commit -m "$(cat <<'EOF'
docs: service theme neutral folder as portrait filler

EOF
)"
```

---

## Self-review (plan vs spec)

| Spec requirement | Task |
|------------------|------|
| FK + backfill | Task 1 |
| Create 5 folders, name `· neutral` | Task 1 |
| Admin UI label «Нейтральный контент» | Task 3 |
| Upload/place `content_type: neutral` | Task 2, 3 |
| Apply upsert filler + ownership | Task 4 |
| Clear removes theme-owned filler | Task 4 |
| Filler validation allows service_theme | Task 4 |
| Screen pick strategy | Task 5 |
| No GenerateForDate / agent API | — out of scope |
| Solutions docs | Task 6 |
| Existing portraits not auto-filled in migration | documented in spec; no task needed |

Placeholders: none. Naming: `neutral_rotation` / `:neutral` / `FOLDER_ROLES` consistent across tasks.
