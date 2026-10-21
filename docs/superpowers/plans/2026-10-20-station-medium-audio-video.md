# Station Medium (Audio / Video) — Hub Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `medium` (`video`|`audio`) on stations and advertising orders so the cabinet can place audio-only orders onto audio pseudo-screens, and playlist generation emits only audio clips for audio stations.

**Architecture:** Enum columns with defaults and check constraints; audio stations auto-create one `Screen` and forbid more; order form radio filters clips/screens; `Playlists::NeutralPicker` (and any shared eligibility) filters by `station.medium`. Agent HTTP JSON stays unchanged.

**Tech Stack:** Ruby 4.0.2, Rails ~> 8.1, PostgreSQL 18, Hotwire/Stimulus, Slim + daisyUI (cabinet), ERB + Flowbite (admin), RSpec + FactoryBot. Tests only in Docker (`RAILS_ENV=test`).

**Spec:** `docs/superpowers/specs/2026-10-20-station-medium-audio-video-design.md`

## Global Constraints

- Do not change `GET /api/agent/v1/package`, `v2/package`, `v1/config`, or `v1/play_events` shapes.
- Do not add audio transcode / `broadcast_file` for audio.
- Do not allow changing `station.medium` after create.
- Do not delete `AirtimeBooking` or restore seconds `AirtimeQuota`.
- Playlist regen stays outside FWW occupy transactions via `Playlists::EnqueueRegen`.
- Admin views: never daisyUI. Cabinet: daisyUI OK.
- Verify with `docker compose exec -e RAILS_ENV=test web bundle exec rspec …` then `bin/ci` before considering the branch done (unless PR already open — then use CI checks).

---

## File map

| Path | Responsibility |
| --- | --- |
| `db/migrate/*_add_medium_to_stations_and_advertising_orders.rb` | Columns, defaults, check constraints |
| `app/models/station.rb` | enum, immutability, auto pseudo-screen, screen cap |
| `app/models/screen.rb` | reject create when audio station already has a screen; forbid destroy of sole audio screen |
| `app/models/advertising_order.rb` | enum medium; freeze when active |
| `app/domain/advertising/validates_media_assets.rb` | medium-aware clip kind checks |
| `app/domain/advertising/update_order_clips.rb` | pass order medium into validation |
| `app/domain/advertising/create_order.rb` | persist medium; validate clips |
| `app/domain/fleet/screens_for_order_picker.rb` | optional `medium:` filter |
| `app/domain/playlists/neutral_picker.rb` | eligible only matching station medium |
| `app/controllers/admin/stations_controller.rb` | permit medium on create only |
| `app/controllers/admin/screens_controller.rb` | block create on full audio station |
| `app/controllers/advertising_orders_controller.rb` | permit medium; filter `@media_assets` / screens |
| `app/controllers/admin/advertising_orders_controller.rb` | same |
| `app/controllers/concerns/advertising_order_grid.rb` | `load_order_screens(medium:)` |
| `app/helpers/advertising_orders_helper.rb` | filter available assets by medium |
| `app/views/advertising_orders/_form.html.slim` | medium radio under title |
| `app/views/admin/stations/_form.html.erb` | medium on new; badge on edit |
| `app/views/admin/screens/*` | hide new when station audio + has screen |
| `app/javascript/controllers/order_medium_controller.js` | clear incompatible selections + turbo refresh |
| `config/locales/mediateca.ru.yml` / `mediateca.en.yml` | labels/errors |
| `CONCEPTS.md` | glossary entries |
| Factories + specs mirroring the above |

---

### Task 1: Migration + Station medium + auto pseudo-screen

**Files:**
- Create: `db/migrate/YYYYMMDDHHMMSS_add_medium_to_stations_and_advertising_orders.rb`
- Modify: `app/models/station.rb`
- Modify: `spec/factories/stations.rb`
- Create/Modify: `spec/models/station_spec.rb`
- Generated: `db/schema.rb`

**Interfaces:**
- Produces: `Station#medium` enum (`video`/`audio`), `Station#audio?`, auto-create one screen after create when audio

- [ ] **Step 1: Write failing model specs**

```ruby
# spec/models/station_spec.rb (add examples)
describe "medium" do
  it "defaults to video" do
    station = create(:station)
    expect(station.medium).to eq("video")
  end

  it "creates exactly one screen when medium is audio" do
    station = create(:station, medium: "audio")
    expect(station.screens.count).to eq(1)
  end

  it "rejects changing medium after create" do
    station = create(:station, medium: "video")
    station.medium = "audio"
    expect(station).not_to be_valid
    expect(station.errors[:medium]).to be_present
  end
end
```

- [ ] **Step 2: Run spec — expect FAIL**

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/models/station_spec.rb
```

Expected: FAIL (unknown attribute / no enum)

- [ ] **Step 3: Migration**

```ruby
# frozen_string_literal: true

class AddMediumToStationsAndAdvertisingOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :stations, :medium, :string, null: false, default: "video"
    add_check_constraint :stations, "medium IN ('video', 'audio')", name: "stations_medium_video_or_audio"

    add_column :advertising_orders, :medium, :string, null: false, default: "video"
    add_check_constraint :advertising_orders,
      "medium IN ('video', 'audio')",
      name: "advertising_orders_medium_video_or_audio"
  end
end
```

Run migrate in test:

```bash
docker compose exec -e RAILS_ENV=test web bin/rails db:migrate
```

- [ ] **Step 4: Station model**

```ruby
# app/models/station.rb — add
enum :medium, { video: "video", audio: "audio" }, default: :video

validate :medium_must_not_change, on: :update
after_create :ensure_audio_pseudo_screen!

def self.ransackable_attributes(_auth_object = nil)
  %w[id agent_token_digest name offline_cache_hours medium created_at updated_at location_id]
end

private

def medium_must_not_change
  return unless medium_changed?

  errors.add(:medium, :immutable)
end

def ensure_audio_pseudo_screen!
  return unless audio?
  return if screens.exists?

  screens.create!(name: next_screen_name)
end
```

Factory:

```ruby
factory :station do
  location
  sequence(:name) { |n| "Station #{n}" }
  medium { "video" }

  trait :audio do
    medium { "audio" }
  end
end
```

Locale keys `activerecord.errors.models.station.attributes.medium.immutable` in ru/en.

- [ ] **Step 5: Run specs — expect PASS**

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/models/station_spec.rb
```

- [ ] **Step 6: Commit**

```bash
git add db/migrate db/schema.rb app/models/station.rb spec/models/station_spec.rb spec/factories/stations.rb config/locales
git commit -m "$(cat <<'EOF'
feat(stations): add immutable medium and audio pseudo-screen

EOF
)"
```

---

### Task 2: Screen constraints on audio stations

**Files:**
- Modify: `app/models/screen.rb`
- Modify: `spec/models/screen_spec.rb`
- Modify: `app/controllers/admin/screens_controller.rb`
- Modify: `spec/requests/admin/screens_spec.rb`
- Modify: admin screen new/index views as needed

**Interfaces:**
- Consumes: `Station#audio?`
- Produces: at most one screen per audio station; sole audio screen not destroyable

- [ ] **Step 1: Failing specs**

```ruby
it "rejects a second screen on an audio station" do
  station = create(:station, :audio)
  expect(station.screens.count).to eq(1)
  second = station.screens.build(name: "extra", orientation: "landscape")
  expect(second).not_to be_valid
end

it "rejects destroying the sole screen of an audio station" do
  station = create(:station, :audio)
  screen = station.screens.first
  expect { screen.destroy! }.to raise_error(ActiveRecord::RecordNotDestroyed)
    .or change { screen.errors[:base] } # prefer validate :prevent_destroy_audio_sole_screen
end
```

Prefer an explicit validation + `before_destroy` abort:

```ruby
# screen.rb
validate :audio_station_may_have_only_one_screen, on: :create
before_destroy :prevent_destroying_sole_audio_screen

def audio_station_may_have_only_one_screen
  return unless station&.audio?
  return if station.screens.where.not(id: id).none? && station.screens.empty?
  # on create after auto-screen exists:
  return if station.screens.where.not(id: id).none? && new_record? && station.screens.count.zero?

  errors.add(:station_id, :audio_station_full) if station.screens.where.not(id: id).exists?
end

def prevent_destroying_sole_audio_screen
  return unless station&.audio?
  return if station.screens.where.not(id: id).exists?

  errors.add(:base, :audio_pseudo_screen_required)
  throw :abort
end
```

Simplify create check to: if `station.audio? && station.screens.where.not(id: id).exists?` then error.

- [ ] **Step 2: Run FAIL, implement, PASS**

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/models/screen_spec.rb spec/requests/admin/screens_spec.rb
```

Admin: on `new`/`create`, if `station_id` points to audio station with a screen, redirect with flash. Hide “New screen” when listing from an audio station show page if one already exists.

- [ ] **Step 3: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(screens): enforce single pseudo-screen on audio stations

EOF
)"
```

---

### Task 3: AdvertisingOrder medium + clip validation

**Files:**
- Modify: `app/models/advertising_order.rb`
- Modify: `spec/factories/advertising_orders.rb`
- Modify: `app/domain/advertising/validates_media_assets.rb`
- Modify: `app/domain/advertising/update_order_clips.rb`
- Modify: `app/domain/advertising/create_order.rb`
- Modify: `spec/domain/advertising/update_order_clips_spec.rb`
- Modify: `spec/models/advertising_order_spec.rb`

**Interfaces:**
- Produces: `AdvertisingOrder#medium`; `validate_media_assets!(..., medium:)` rejects wrong `content_kind`

- [ ] **Step 1: Failing specs**

```ruby
it "rejects audio clips on a video order" do
  order = create(:advertising_order, medium: "video")
  audio = create(:media_asset, :ready, :with_mp3_file, organization: order.organization) # use existing audio trait or attach audio mime

  expect {
    Advertising::UpdateOrderClips.call(order: order, media_assets: [audio])
  }.to raise_error(Advertising::Error, /audio|medium|content/i)
end

it "accepts audio clips on an audio order" do
  order = create(:advertising_order, medium: "audio")
  audio = create(:media_asset, :ready, content_kind: "audio", organization: order.organization)
  # ensure broadcast_ready? for audio (original file)

  expect {
    Advertising::UpdateOrderClips.call(order: order, media_assets: [audio])
  }.not_to raise_error
end
```

Use or add a FactoryBot trait for ready audio (`:with_mp3_file` / `content_kind: audio`) matching `MediaAsset::ALLOWED_CONTENT_TYPES`.

- [ ] **Step 2: Model enum**

```ruby
enum :medium, { video: "video", audio: "audio" }, default: :video

validate :medium_frozen_when_active, on: :update

def medium_frozen_when_active
  return unless active?
  return unless medium_changed?

  errors.add(:medium, :immutable_when_active)
end
```

- [ ] **Step 3: ValidatesMediaAssets**

```ruby
def validate_media_assets!(media_assets, organization:, medium: "video")
  assets = Array(media_assets)
  # existing empty/duplicate/foreign/ready checks...

  assets.each do |asset|
    unless asset_matches_medium?(asset, medium)
      raise Error, I18n.t("advertising.errors.clip_wrong_medium", medium: medium)
    end
  end
end

def asset_matches_medium?(asset, medium)
  case medium.to_s
  when "audio" then asset.audio?
  when "video" then !asset.audio?
  else false
  end
end
```

Call sites (`CreateOrder`, `UpdateOrderClips`) pass `medium: order.medium`.

Also validate order lines’ screens: `line.screen.station.medium == order.medium` on save/activate (add in create/update line sync or model validation on `AdvertisingOrderLine`).

- [ ] **Step 4: PASS + commit**

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec \
  spec/domain/advertising/update_order_clips_spec.rb \
  spec/models/advertising_order_spec.rb
```

```bash
git commit -m "$(cat <<'EOF'
feat(orders): medium enum and medium-aware clip validation

EOF
)"
```

---

### Task 4: Screen picker + available assets filtered by medium

**Files:**
- Modify: `app/domain/fleet/screens_for_order_picker.rb`
- Modify: `spec/domain/fleet/screens_for_order_picker_spec.rb`
- Modify: `app/controllers/concerns/advertising_order_grid.rb`
- Modify: `app/helpers/advertising_orders_helper.rb`
- Modify: `app/controllers/advertising_orders_controller.rb`
- Modify: `app/controllers/admin/advertising_orders_controller.rb`
- Modify: request specs for advertising orders

**Interfaces:**
- Produces: `Fleet::ScreensForOrderPicker.call(medium: "audio"|"video"|nil)`
- Produces: helper filters `@media_assets` by order medium

- [ ] **Step 1: Failing domain spec**

```ruby
it "returns only screens for the given medium" do
  video_station = create(:station, medium: "video")
  audio_station = create(:station, :audio)
  video_screen = create(:screen, station: video_station)
  audio_screen = audio_station.screens.first

  result = described_class.call(medium: "audio")
  expect(result).to include(audio_screen)
  expect(result).not_to include(video_screen)
end
```

- [ ] **Step 2: Implementation**

```ruby
module Fleet
  class ScreensForOrderPicker < BaseService
    def initialize(medium: nil)
      @medium = medium.presence
    end

    def call
      scope = Screen.operator_catalog
        .includes(:tags, :broadcast_portrait, :broadcast_point_groups, station: :location)
        .joins(station: :location)
      scope = scope.where(stations: { medium: @medium }) if @medium
      scope.order("locations.name", "stations.name", "screens.name")
    end
  end
end
```

```ruby
# advertising_order_grid.rb
def load_order_screens
  @order_screens = Fleet::ScreensForOrderPicker.call(medium: @advertising_order&.medium)
end
```

```ruby
# helper
def order_form_available_media_assets(advertising_order, media_assets)
  selected_ids = order_form_selected_media_assets(advertising_order).map(&:id)
  Array(media_assets)
    .reject { |asset| selected_ids.include?(asset.id) }
    .select { |asset| order_asset_matches_medium?(advertising_order, asset) }
end

def order_asset_matches_medium?(order, asset)
  order.audio? ? asset.audio? : !asset.audio?
end
```

Controller: when loading `@media_assets`, also scope:

```ruby
@media_assets = policy_scope(MediaAsset).ready.with_attached_file.order(created_at: :desc)
@media_assets = @media_assets.where(content_kind: "audio") if @advertising_order.audio?
@media_assets = @media_assets.where.not(content_kind: "audio") if @advertising_order.video?
```

Permit `:medium` in order strong params for draft/rejected/new.

- [ ] **Step 3: Request specs assert picker HTML omits wrong medium screens / clips**
- [ ] **Step 4: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(orders): filter order screens and clips by medium

EOF
)"
```

---

### Task 5: Order form radio + Stimulus clear-on-switch

**Files:**
- Modify: `app/views/advertising_orders/_form.html.slim`
- Create: `app/javascript/controllers/order_medium_controller.js`
- Register in importmap / Stimulus index if needed
- Modify: `spec/system/advertising_order_placement_spec.rb` (or new system spec)
- Locales for radio labels + clear warning

- [ ] **Step 1: Place radio immediately under form heading**

In `_form.html.slim`, before the `product_name` grid:

```slim
.fieldset
  legend.fieldset-legend = t('.medium_legend')
  .flex.gap-4.mt-1
    label.flex.items-center.gap-2.cursor-pointer
      = f.radio_button :medium, "video",
          class: "radio radio-sm",
          disabled: advertising_order.active?,
          data: { order_medium_target: "radio", action: "change->order-medium#changed" }
      span = t('.medium_video')
    label.flex.items-center.gap-2.cursor-pointer
      = f.radio_button :medium, "audio",
          class: "radio radio-sm",
          disabled: advertising_order.active?,
          data: { order_medium_target: "radio", action: "change->order-medium#changed" }
      span = t('.medium_audio')
  p.text-sm.text-warning.hidden data-order-medium-target="warning" = t('.medium_switch_cleared')
```

Add `order-medium` to the form’s Stimulus `controller` list.

- [ ] **Step 2: Stimulus controller**

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["radio", "warning", "clipCheckbox", "screenCheckbox"]

  changed(event) {
    const medium = event.target.value
    let cleared = false

    this.clipCheckboxTargets.forEach((input) => {
      const kind = input.dataset.contentKind // "audio" | "video" | ...
      const ok = medium === "audio" ? kind === "audio" : kind !== "audio"
      if (!ok && input.checked) {
        input.checked = false
        cleared = true
      }
    })

    this.screenCheckboxTargets.forEach((input) => {
      const screenMedium = input.dataset.stationMedium
      if (screenMedium && screenMedium !== medium && input.checked) {
        input.checked = false
        cleared = true
      }
    })

    if (this.hasWarningTarget) {
      this.warningTarget.classList.toggle("hidden", !cleared)
    }

    // Prefer Turbo visit/frame reload of clips + picker partials with ?medium=
    if (this.element.dataset.orderMediumRefreshUrl) {
      const url = new URL(this.element.dataset.orderMediumRefreshUrl, window.location.origin)
      url.searchParams.set("medium", medium)
      // turbo.visit or frame.src = url — match existing order-grid refresh style
    }
  }
}
```

Wire `data-content-kind` / `data-station-medium` on clip and screen inputs in existing partials (`_media_asset_row`, `_screen_picker`).

For server-rendered available lists after switch: either full form re-submit via GET turbo frame, or client-only hide + server validate on save. Minimum acceptable: client clear + server filter on next render; preferred: Turbo Frame reload of clips/picker.

- [ ] **Step 3: System or request coverage that switching medium clears a selected video clip**
- [ ] **Step 4: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(orders): medium radio clears incompatible selections

EOF
)"
```

---

### Task 6: Admin station form medium

**Files:**
- Modify: `app/views/admin/stations/_form.html.erb`
- Modify: `app/views/admin/stations/show.html.erb`
- Modify: `app/controllers/admin/stations_controller.rb`
- Modify: `spec/requests/admin/stations_spec.rb`

- [ ] **Step 1: Strong params**

```ruby
def station_params
  if action_name == "create"
    params.expect(station: [:location_id, :name, :offline_cache_hours, :medium])
  else
    params.expect(station: [:location_id, :name, :offline_cache_hours])
  end
end
```

- [ ] **Step 2: Form**

On `new`: Flowbite radios/select for medium (no daisyUI).  
On `edit`/`show`: read-only text/badge via `admin_enum_label(station, :medium)`.

- [ ] **Step 3: Request specs** create audio station → one screen; update cannot change medium
- [ ] **Step 4: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(admin): set station medium on create only

EOF
)"
```

---

### Task 7: Playlist eligibility by station medium

**Files:**
- Modify: `app/domain/playlists/neutral_picker.rb`
- Modify: `spec/domain/playlists/neutral_picker_spec.rb` (create if missing)
- Modify: `spec/domain/playlists/generate_for_date_spec.rb` (audio station case)

**Interfaces:**
- Consumes: `station.medium`
- Produces: `eligible?` false when asset kind mismatches station medium

- [ ] **Step 1: Failing picker spec**

```ruby
it "skips video assets on an audio station" do
  station = create(:station, :audio)
  rotation = create(:rotation, :with_video_and_audio_items) # or build items manually
  picker = described_class.new(
    rotation: rotation,
    strategy: "ordered",
    station: station,
    for_date: Date.current
  )
  kinds = picker.take(10).map { |pick| pick[:media_asset].content_kind }.uniq
  expect(kinds).to eq(["audio"])
end
```

- [ ] **Step 2: Implementation**

```ruby
def eligible?(item)
  asset = item.media_asset
  return false unless asset.broadcast_delivery_attachment
  return false unless medium_matches?(asset)

  duration = duration_for(item)
  return false if duration.blank? || duration <= 0
  return false if min_seconds.present? && duration < min_seconds

  true
end

def medium_matches?(asset)
  if station.audio?
    asset.audio?
  else
    !asset.audio?
  end
end
```

Note: video stations currently may emit non-video (image) if present in rotations; keep `!asset.audio?` so only audio is excluded from video stations. Audio stations accept only `audio?`.

- [ ] **Step 3: Integration example in generate_for_date for an audio station with commercial audio plan — package items all audio**
- [ ] **Step 4: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(playlists): emit only medium-matching clips per station

EOF
)"
```

---

### Task 8: CONCEPTS + i18n sweep + bin/ci

**Files:**
- Modify: `CONCEPTS.md`
- Modify: `config/locales/mediateca.ru.yml`, `mediateca.en.yml` (any missing keys)
- Optional: `docs/solutions/` only if a non-obvious gotcha appears during implementation

- [ ] **Step 1: Glossary**

Add under Relationships / entities:

- Station medium
- Audio pseudo-screen
- Order medium

(short definitions from the design spec)

- [ ] **Step 2: Run full CI**

```bash
docker compose exec -e RAILS_ENV=test web bin/ci
```

Expected: RuboCop, RSpec, bundler-audit, importmap audit, Brakeman all green.

- [ ] **Step 3: Commit docs + any locale fixes**

```bash
git commit -m "$(cat <<'EOF'
docs: CONCEPTS for station and order medium

EOF
)"
```

---

## Spec coverage checklist

| Spec requirement | Task |
| --- | --- |
| `stations.medium` default video, immutable | 1 |
| Audio station auto one screen | 1 |
| No second screen / no destroy sole audio screen | 2 |
| `advertising_orders.medium` | 3 |
| Clip validation by medium | 3 |
| Screen picker filter | 4 |
| Available clips filter | 4 |
| Radio under form title + clear on switch | 5 |
| Admin create-only medium | 6 |
| Playlist audio-only eligibility | 7 |
| Package API unchanged / original audio file | 7 (uses existing delivery) |
| CONCEPTS | 8 |

## Out of scope (do not implement)

- Audio agent repository (separate plan)
- Audio transcode
- Changing station medium in place
- Multiple audio channels per station
