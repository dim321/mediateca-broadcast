# Timed service welcome/close Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Optional `time_of_day` on `service_welcome` / `service_close`: blank keeps open/close day-bound; set replaces the covering hour slot like `insertion`, with playlist `source_kind: "service"`.

**Architecture:** No migration. Relax model validation; extend `Playlists::GenerateForDate` so timed welcome/close join the insertion-style slot-replacement path while untimed stay in `day_bound_emissions`. Admin Stimulus shows the time field for those kinds; short i18n hint.

**Tech Stack:** Rails 8.1, RSpec/FactoryBot, ERB+Flowbite admin, Stimulus `portrait-blocks`.

**Spec:** `docs/superpowers/specs/2026-09-17-timed-service-welcome-close-design.md`

## Global Constraints

- Tests only: `docker compose exec -e RAILS_ENV=test web bundle exec rspec …` (`RAILS_ENV=test` required).
- TDD: Red → Green. Do not write production code before a failing test for that change.
- UI copy: `config/locales/mediateca.ru.yml` + `mediateca.en.yml`.
- Admin `/admin` — Flowbite utilities only; no daisyUI classes.
- Ruby: single quotes unless interpolation needed.
- No schema migration; do not change `insertion` validation or commercial/filler/header time rules.
- Timed welcome/close must use `min_seconds: nil` when picking clips (not `neutral_min_seconds`).
- Timed welcome/close playlist items must use `source_kind: "service"`, never `"insertion"`.
- Do not commit `.env` / credentials.

## File map

| File | Responsibility |
|------|----------------|
| `app/models/broadcast_portrait_block.rb` | Allow optional `time_of_day` on welcome/close |
| `app/domain/playlists/generate_for_date.rb` | Untimed day-bound filter; timed slot events + emit with `service` kind |
| `spec/models/broadcast_portrait_block_spec.rb` | Validation examples |
| `spec/domain/playlists/generate_for_date_spec.rb` | Timed / mixed / DST generate examples |
| `spec/support/playlist_generation.rb` | Optional `welcome_time` / `close_time` for helpers |
| `app/javascript/admin/controllers/portrait_blocks_controller.js` | Show time field for welcome/close |
| `app/views/admin/broadcast_portraits/_block_fields.html.erb` | Hint under time input |
| `config/locales/mediateca.ru.yml` / `mediateca.en.yml` | Hint copy |
| `spec/requests/admin/broadcast_portraits_spec.rb` | Persist welcome with blank and set time |
| `docs/solutions/architecture-patterns/broadcast-portrait-as-screen-airtime-structure.md` | Note optional time on welcome/close |
| `CONCEPTS.md` | One-line clarification under Broadcast portrait |

---

### Task 1: Model — optional `time_of_day` on welcome/close

**Files:**
- Modify: `spec/models/broadcast_portrait_block_spec.rb`
- Modify: `app/models/broadcast_portrait_block.rb` (remove reject in `fields_match_kind` for welcome/close)

**Interfaces:**
- Consumes: existing factory traits `:service_welcome`, `:service_close`.
- Produces: welcome/close valid with `time_of_day` nil or set; rotation/pick_strategy rules unchanged.

- [ ] **Step 1: Write the failing test**

In `spec/models/broadcast_portrait_block_spec.rb`, **replace** the example `rejects time_of_day on welcome and close blocks` with:

```ruby
it 'allows optional time_of_day on welcome and close blocks' do
  with_time = build(:broadcast_portrait_block, :service_welcome, time_of_day: '09:00')
  without_time = build(:broadcast_portrait_block, :service_close)

  expect(with_time).to be_valid
  expect(without_time).to be_valid
end
```

Keep the existing example `requires rotation and pick strategy on welcome and close blocks` unchanged.

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec \
  spec/models/broadcast_portrait_block_spec.rb \
  -e 'allows optional time_of_day on welcome and close blocks'
```

Expected: FAIL — `with_time` invalid, `errors[:time_of_day]` present (old reject still in model).

- [ ] **Step 3: Minimal implementation**

In `app/models/broadcast_portrait_block.rb`, in the `when "service_welcome", "service_close"` branch of `fields_match_kind`, **delete** this line only:

```ruby
errors.add(:time_of_day, :present) if time_of_day.present?
```

Leave the `service_theme_id` / `rotation_id` / `pick_strategy` checks as they are.

- [ ] **Step 4: Run tests to verify they pass**

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec \
  spec/models/broadcast_portrait_block_spec.rb
```

Expected: PASS (all examples in the file).

- [ ] **Step 5: Commit**

```bash
git add spec/models/broadcast_portrait_block_spec.rb app/models/broadcast_portrait_block.rb
git commit -m "$(cat <<'EOF'
fix: allow optional time_of_day on welcome/close portrait blocks

Operators need timed service welcome/close; blank time keeps day-bound defaults.
EOF
)"
```

---

### Task 2: Generator — timed welcome/close replace slots; untimed stay day-bound

**Files:**
- Modify: `spec/support/playlist_generation.rb`
- Modify: `spec/domain/playlists/generate_for_date_spec.rb`
- Modify: `app/domain/playlists/generate_for_date.rb`

**Interfaces:**
- Consumes: `BroadcastPortraitBlock` with optional `time_of_day` on welcome/close.
- Produces:
  - `timed_slot_events(portrait)` → Array of `{ block:, at: }` for insertion **or** welcome/close with present `time_of_day`, sorted by block `position`.
  - Slot match emits insertion with `source_kind "insertion"`; timed welcome/close with `source_kind "service"` and `min_seconds: nil`.
  - `day_bound_emissions` only processes welcome/close where `time_of_day` is blank.

- [ ] **Step 1: Extend playlist generation helpers**

In `spec/support/playlist_generation.rb`, add optional kwargs `welcome_time: nil, close_time: nil` to both `create_cyclic_portrait!` and `build_cyclic_portrait_for_screen!` (thread them through like `insertion_time`).

When creating the welcome block, pass `time_of_day: welcome_time` if present:

```ruby
if welcome_rotation
  position += 1
  attrs = {
    broadcast_portrait: portrait,
    position: position,
    rotation: welcome_rotation,
    pick_strategy: 'sequential'
  }
  attrs[:time_of_day] = welcome_time if welcome_time
  create(:broadcast_portrait_block, :service_welcome, **attrs)
end
```

Same pattern for `close_rotation` / `close_time`.

- [ ] **Step 2: Write failing generate specs**

Append to `spec/domain/playlists/generate_for_date_spec.rb` (reuse existing helpers; Krasnoyarsk Wed 09:00–21:00 → noon offset `3.hours`):

```ruby
it 'lets a timed welcome replace the noon slot with source_kind service' do
  station = create_playlist_station!
  screen = create(:screen, station: station)
  org = create(:organization, :client)
  filler = create_clip_rotation!(organization: org)
  welcome = create_clip_rotation!(organization: org)
  create_cyclic_portrait!(
    station,
    filler_rotation: filler,
    welcome_rotation: welcome,
    welcome_time: '12:00'
  )
  occupy_with_clips!(
    screen: screen,
    organization: org,
    rotation: create_clip_rotation!(organization: org),
    starts_at: local_slot(9),
    ends_at: local_slot(21)
  )

  playlist = generate!(station).playlist
  noon = 3.hours.to_i
  quarter = noon + 15.minutes.to_i

  expect(source_kinds_at(playlist, noon)).to eq(%w[service])
  expect(items_at(playlist, noon).first.media_asset_id).to eq(welcome.ordered_items.first.media_asset_id)
  expect(source_kinds_at(playlist, quarter)).to eq(%w[filler])
  expect(playlist.items.none? { |item| item.service? && item.offset_seconds.zero? }).to be(true)
end

it 'emits both untimed day-bound welcome and a timed welcome on the same portrait' do
  station = create_playlist_station!
  screen = create(:screen, station: station)
  org = create(:organization, :client)
  filler = create_clip_rotation!(organization: org)
  welcome_open = create_clip_rotation!(organization: org)
  welcome_noon = create_clip_rotation!(organization: org)
  create_cyclic_portrait!(station, filler_rotation: filler, welcome_rotation: welcome_open)

  portrait = screen.reload.broadcast_portrait
  create(
    :broadcast_portrait_block,
    :service_welcome,
    broadcast_portrait: portrait,
    position: portrait.blocks.maximum(:position).to_i + 1,
    rotation: welcome_noon,
    pick_strategy: 'sequential',
    time_of_day: '12:00'
  )

  playlist = generate!(station).playlist
  open_id = welcome_open.ordered_items.first.media_asset_id
  noon_id = welcome_noon.ordered_items.first.media_asset_id

  open_item = playlist.items.find { |item| item.service? && item.media_asset_id == open_id }
  noon_item = playlist.items.find { |item| item.service? && item.media_asset_id == noon_id }

  expect(open_item.offset_seconds).to eq(0)
  expect(noon_item.offset_seconds).to eq(3.hours.to_i)
  expect(noon_item.source_kind).to eq('service')
end

it 'skips a spring-forward timed welcome like insertion (AE8 mirror)' do
  org = create(:organization, :client)
  filler = create_clip_rotation!(organization: org)
  welcome = create_clip_rotation!(organization: org)
  spring_station = create_playlist_station!(time_zone: 'Europe/Berlin', hours: PlaylistGeneration::BERLIN_SUN_HOURS)
  create(:screen, station: spring_station)
  create_cyclic_portrait!(
    spring_station,
    filler_rotation: filler,
    welcome_rotation: welcome,
    welcome_time: '02:30'
  )

  spring = generate!(spring_station, Date.new(2026, 3, 29)).playlist

  expect(spring.items.count(&:service?)).to eq(0)
end
```

- [ ] **Step 3: Run specs to verify they fail**

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec \
  spec/domain/playlists/generate_for_date_spec.rb \
  -e 'timed welcome' -e 'untimed day-bound welcome' -e 'spring-forward timed welcome'
```

Expected: FAIL — timed welcome still day-bound or rejected by validation / not replacing noon; spring may still place at open incorrectly or place zero for other reasons. The noon `source_kinds_at` expectation should fail first on the first example if validation already allows time.

- [ ] **Step 4: Implement generator changes**

In `app/domain/playlists/generate_for_date.rb`:

1. In `emissions_for_screen`, replace `insertions = insertion_events(portrait)` with `timed = timed_slot_events(portrait)`.

2. Replace the matching/emit branch:

```ruby
matching = timed
  .select { |event| slot_start <= event[:at] && event[:at] < slot_end }
  .map { |event| event[:block] }
  .sort_by(&:position)
if matching.any?
  cycle_index += 1 if cycle.any?
  matching.flat_map { |block| emit_timed_slot_block(block, screen, portrait, slot_start, pickers) }
```

3. Replace `insertion_events` with:

```ruby
def timed_slot_events(portrait)
  portrait.blocks.sort_by(&:position).filter_map do |block|
    next unless timed_slot_block?(block)

    tod = block.time_of_day
    next unless tod

    at = local_wall_clock(tod.hour, tod.min)
    next unless at

    { block: block, at: at }
  end
end

def timed_slot_block?(block)
  return true if block.insertion?
  return false unless block.service_welcome? || block.service_close?

  block.time_of_day.present?
end
```

4. Add emit helper (keep `emit_insertion` for insertion path or inline):

```ruby
def emit_timed_slot_block(block, screen, portrait, slot_start, pickers)
  if block.insertion?
    emit_insertion(block, screen, portrait, slot_start, pickers)
  else
    pick = take_from_block(block, screen, pickers, min_seconds: nil)
    return [ emission(pick, screen, slot_start, 'service') ] if pick

    warn_once("service timed block #{block.kind} has no eligible clips")
    []
  end
end
```

5. In `day_bound_emissions`, only untimed blocks:

```ruby
header_blocks(portrait, 'service_welcome').reject { |block| block.time_of_day.present? }.each do |block|
  # unchanged body
end
header_blocks(portrait, 'service_close').reject { |block| block.time_of_day.present? }.each do |block|
  # unchanged body
end
```

Do **not** change `cycle_blocks` (welcome/close remain excluded entirely).

- [ ] **Step 5: Run generate specs**

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec \
  spec/domain/playlists/generate_for_date_spec.rb
```

Expected: PASS (including existing AE4/AE5/AE6/AE8/AE12 welcome examples).

- [ ] **Step 6: Commit**

```bash
git add spec/support/playlist_generation.rb \
  spec/domain/playlists/generate_for_date_spec.rb \
  app/domain/playlists/generate_for_date.rb
git commit -m "$(cat <<'EOF'
feat: emit timed welcome/close as slot replacements

Blank time keeps open/close day-bound; set time replaces the covering slot like insertion with source_kind service.
EOF
)"
```

---

### Task 3: Admin UI — show time for welcome/close + hint + request coverage + docs

**Files:**
- Modify: `app/javascript/admin/controllers/portrait_blocks_controller.js`
- Modify: `app/views/admin/broadcast_portraits/_block_fields.html.erb`
- Modify: `config/locales/mediateca.ru.yml`
- Modify: `config/locales/mediateca.en.yml`
- Modify: `spec/requests/admin/broadcast_portraits_spec.rb`
- Modify: `docs/solutions/architecture-patterns/broadcast-portrait-as-screen-airtime-structure.md`
- Modify: `CONCEPTS.md` (Broadcast portrait paragraph)

**Interfaces:**
- Consumes: existing `data-portrait-blocks-field="time"` toggle.
- Produces: time field visible for `service_welcome` / `service_close`; optional blank persists; hint string under the input.

- [ ] **Step 1: Write failing request example**

In `spec/requests/admin/broadcast_portraits_spec.rb`, inside the update/blocks context (mirror the existing `service_welcome` + theme example), add:

```ruby
it 'persists optional time_of_day on welcome and clears it when blank' do
  screen = create(:screen)
  portrait = create(:broadcast_portrait, :for_screen, screen: screen)
  theme = create(:service_theme)
  create(:broadcast_portrait_block, :commercial, broadcast_portrait: portrait, position: 1)

  patch admin_broadcast_portrait_path(portrait), params: {
    broadcast_portrait: {
      blocks: [
        { position: 1, kind: 'commercial' },
        {
          position: 2,
          kind: 'service_welcome',
          service_theme_id: theme.id,
          pick_strategy: 'sequential',
          time_of_day: '12:30'
        }
      ]
    }
  }

  welcome = portrait.reload.blocks.find_by!(kind: 'service_welcome')
  expect(welcome.time_of_day.strftime('%H:%M')).to eq('12:30')

  patch admin_broadcast_portrait_path(portrait), params: {
    broadcast_portrait: {
      blocks: [
        { position: 1, kind: 'commercial' },
        {
          position: 2,
          kind: 'service_welcome',
          service_theme_id: theme.id,
          pick_strategy: 'sequential',
          time_of_day: ''
        }
      ]
    }
  }

  expect(portrait.reload.blocks.find_by!(kind: 'service_welcome').time_of_day).to be_nil
end
```

Adjust params shape to match existing examples in that file (nested `blocks` array) if the snippet above differs slightly.

- [ ] **Step 2: Run request spec to verify fail/pass baseline**

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec \
  spec/requests/admin/broadcast_portraits_spec.rb \
  -e 'persists optional time_of_day on welcome'
```

Expected after Task 1–2: may already PASS on persistence (UpsertBlocks already permits `time_of_day`). If it fails on blank→nil normalization, fix in controller/`UpsertBlocks` only as needed (blank string → nil). Do not expand scope.

- [ ] **Step 3: Stimulus — show time field**

In `app/javascript/admin/controllers/portrait_blocks_controller.js`, set `time: true` for welcome and close:

```javascript
service_welcome: { rotation: false, theme: true, pick: true, time: true },
service_close: { rotation: false, theme: true, pick: true, time: true }
```

- [ ] **Step 4: Hint under time field**

In `_block_fields.html.erb`, after the time `<input>`, add:

```erb
<p class="mt-1 text-xs text-gray-500" data-portrait-blocks-time-hint>
  <%= t("admin.broadcast_portraits.time_of_day_hint") %>
</p>
```

Add locale keys:

`config/locales/mediateca.ru.yml` under `admin.broadcast_portraits`:

```yaml
time_of_day_hint: Пусто — в начале или конце рабочего дня. Задано — замена слота в это время (как вставка).
```

`config/locales/mediateca.en.yml`:

```yaml
time_of_day_hint: Leave blank for start or end of the operating day. Set a time to replace that slot (like an insertion).
```

- [ ] **Step 5: Docs touch-up**

In `docs/solutions/architecture-patterns/broadcast-portrait-as-screen-airtime-structure.md`, update the welcome/close rows to note optional `time_of_day` (blank = open/close; set = insertion-style slot replace, `source_kind` service).

In `CONCEPTS.md` Broadcast portrait sentence, add that welcome/close may optionally set wall-clock time; otherwise they stay day-bound to operating windows.

- [ ] **Step 6: Run request + model + generate regression**

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec \
  spec/models/broadcast_portrait_block_spec.rb \
  spec/domain/playlists/generate_for_date_spec.rb \
  spec/requests/admin/broadcast_portraits_spec.rb
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add app/javascript/admin/controllers/portrait_blocks_controller.js \
  app/views/admin/broadcast_portraits/_block_fields.html.erb \
  config/locales/mediateca.ru.yml config/locales/mediateca.en.yml \
  spec/requests/admin/broadcast_portraits_spec.rb \
  docs/solutions/architecture-patterns/broadcast-portrait-as-screen-airtime-structure.md \
  CONCEPTS.md
git commit -m "$(cat <<'EOF'
feat: expose optional welcome/close time in portrait admin

Show the time field for service welcome/close with a blank-vs-slot hint; document the behavior.
EOF
)"
```

---

## Spec coverage checklist

| Spec requirement | Task |
|------------------|------|
| Optional `time_of_day` on welcome/close | 1 |
| Blank → day-bound open/close | 2 |
| Set → insertion-style slot replace | 2 |
| `source_kind` stays `service` | 2 |
| Multiple / mix timed+untimed | 2 |
| DST / outside windows skip | 2 |
| No migration | — |
| Admin optional time + hint | 3 |
| CopyTemplate / fingerprint unchanged | — (already copy/hash `time_of_day`) |
| Model + generate + request tests | 1–3 |
