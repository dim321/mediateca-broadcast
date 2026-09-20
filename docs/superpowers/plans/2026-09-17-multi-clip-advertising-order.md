# Multi-clip Advertising Order Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let an advertising order bind an ordered list of clips that cycle through hourly commercial slots independently of `shows_per_hour`.

**Architecture:** System-managed `Rotation` remains the clip source of truth with N `RotationItem`s. `CreateOrder` / `UpdateOrderClips` sync that catalog; occupy and playlist stay on `order.rotation` + `NeutralPicker` sequential (day-scoped cursor). Soft commercial quota sums durations of M sequential picks, not `M * sum(catalog)`. Shared Slim form + Stimulus list editor for admin and cabinet.

**Tech Stack:** Rails 8.1, Slim, daisyUI (form), Stimulus, RSpec, Docker Compose.

**Spec:** `docs/superpowers/specs/2026-09-17-multi-clip-advertising-order-design.md`

## Global Constraints

- Clip SoT = `order.rotation.ordered_items` (system-managed rotation).
- `shows_per_hour` is independent of clip count; catalog cycles.
- One show duration = the clip in that slot; soft quota = sum of M pick durations.
- Same `media_asset` at most once per order (`RotationItem` uniqueness already enforces).
- At least one ready org-owned asset required.
- Draft clip update: no playlist regen. Active: `Playlists::EnqueueRegen` outside the write transaction; no re-occupy.
- Do not reintroduce seconds quotas or skip ScreenLock/Guard in playlist generation.
- Tests: `docker compose exec -e RAILS_ENV=test web bundle exec rspec …`

## File map

| File | Role |
|------|------|
| `db/migrate/*_make_advertising_orders_media_asset_id_nullable.rb` | Nullable legacy FK |
| `app/models/advertising_order.rb` | Optional `media_asset`; stop requiring single-clip snapshots |
| `app/domain/advertising/create_order.rb` | `media_assets:` ordered list |
| `app/domain/advertising/update_order_clips.rb` | Sync rotation items; draft/active |
| `app/domain/advertising/replace_clip.rb` | Delete after callers migrate (or thin wrapper) |
| `app/domain/advertising/replace_draft_clip.rb` | Delete after callers migrate |
| `app/domain/commercial_quota/hourly_shows_duration.rb` | Sum of M sequential pick durations |
| `app/domain/commercial_quota/consumption.rb` | Use `HourlyShowsDuration` |
| Controllers (admin + cabinet) | `media_asset_ids: []`; call new services |
| `app/views/advertising_orders/_form.html.slim` | Ordered multi-clip editor |
| `app/javascript/controllers/order_media_assets_controller.js` | Add/remove/reorder |
| Show / print / replace_clip views | List from `ordered_items` |
| Specs mirroring the above | Domain, request, playlist, quota |

---

### Task 1: Nullable `media_asset_id` + model

**Files:**
- Create: `db/migrate/20260917120000_make_advertising_orders_media_asset_id_nullable.rb`
- Modify: `app/models/advertising_order.rb`
- Modify: `spec/factories/advertising_orders.rb` (keep association for backward-compat fixtures; CreateOrder path will stop writing FK)
- Test: `spec/models/advertising_order_spec.rb`

**Interfaces:**
- Produces: `belongs_to :media_asset, optional: true`; orders may persist with `media_asset_id: nil`

- [ ] **Step 1: Write failing model example**

```ruby
it "allows nil media_asset when rotation carries clips" do
  order = build(:advertising_order, media_asset: nil)
  expect(order).to be_valid
end
```

- [ ] **Step 2: Run RED**

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/models/advertising_order_spec.rb -e "allows nil media_asset"
```

Expected: FAIL (NOT NULL / belongs_to required).

- [ ] **Step 3: Migration + model**

```ruby
# frozen_string_literal: true

class MakeAdvertisingOrdersMediaAssetIdNullable < ActiveRecord::Migration[8.1]
  def change
    change_column_null :advertising_orders, :media_asset_id, true
  end
end
```

```ruby
belongs_to :media_asset, optional: true

# Keep snapshot_clip_from_media_asset as no-op when media_asset blank.
# Do not clear legacy clip_title/duration_seconds columns in this task.
```

Run migrate in test:

```bash
docker compose exec -e RAILS_ENV=test web bin/rails db:migrate
```

- [ ] **Step 4: GREEN + commit**

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/models/advertising_order_spec.rb
git add db/migrate db/schema.rb app/models/advertising_order.rb spec/models/advertising_order_spec.rb
git commit -m "fix(advertising): allow orders without single media_asset_id"
```

---

### Task 2: `CreateOrder` accepts ordered `media_assets`

**Files:**
- Modify: `app/domain/advertising/create_order.rb`
- Modify: `spec/domain/advertising/create_order_spec.rb`
- Later tasks update controller callers; for now keep a compatibility shim if needed:

**Interfaces:**
- Consumes: Task 1 nullable FK
- Produces: `Advertising::CreateOrder.call(..., media_assets: [MediaAsset, ...])`
- Deprecated: `media_asset:` single arg — remove after controllers updated (Task 5). During this task, accept only `media_assets:`.

- [ ] **Step 1: Failing domain examples**

```ruby
it "creates ordered rotation items for each media asset" do
  a = create(:media_asset, :ready, :with_png_file, organization: organization, duration_seconds: 10)
  b = create(:media_asset, :ready, :with_png_file, organization: organization, duration_seconds: 12)
  c = create(:media_asset, :ready, :with_png_file, organization: organization, duration_seconds: 14)

  order = Advertising::CreateOrder.call(
    organization: organization,
    created_by: user,
    media_assets: [ a, b, c ],
    product_name: "Multi",
    shows_per_hour: 3
  )

  expect(order.media_asset_id).to be_nil
  expect(order.rotation.ordered_items.map(&:media_asset)).to eq([ a, b, c ])
  expect(order.rotation.ordered_items.map(&:display_duration_seconds)).to eq([ 10, 12, 14 ])
end

it "rejects an empty media_assets list" do
  expect {
    Advertising::CreateOrder.call(
      organization: organization, created_by: user, media_assets: [], product_name: "X"
    )
  }.to raise_error(Advertising::Error)
end
```

Update existing single-clip examples to pass `media_assets: [ media_asset ]`.

- [ ] **Step 2: RED**

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/advertising/create_order_spec.rb
```

- [ ] **Step 3: Implement**

```ruby
def initialize(..., media_assets:, ...)
  @media_assets = Array(media_assets)
end

def call
  raise Error, I18n.t("advertising.errors.clips_required") if media_assets.empty?
  # optional: validate each broadcast_ready? + same organization

  AdvertisingOrder.transaction do
    rotation = organization.rotations.create!(name: "order-#{SecureRandom.uuid}", system_managed: true)
    media_assets.each do |asset|
      rotation.rotation_items.create!(
        media_asset: asset,
        display_duration_seconds: asset.duration_seconds
      )
    end
    order = organization.advertising_orders.create!(
      created_by: created_by,
      media_asset: nil,
      rotation: rotation,
      product_name: product_name,
      # ... unchanged header fields ...
    )
    rotation.update!(name: I18n.t("advertising.system_rotation_name", number: order.id))
    order
  end
end
```

Add i18n keys `advertising.errors.clips_required` (ru + en).

- [ ] **Step 4: GREEN + commit**

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/advertising/create_order_spec.rb
git commit -am "feat(advertising): create orders with ordered media_assets list"
```

Note: other specs still calling `media_asset:` will fail until Task 5/8 — either update them in this commit (preferred: change helper to `media_assets: [asset]`) or land Task 5 immediately after. Prefer updating all `CreateOrder.call` helpers in this same commit so the suite stays green.

---

### Task 3: Commercial quota — hourly shows duration

**Files:**
- Create: `app/domain/commercial_quota/hourly_shows_duration.rb`
- Modify: `app/domain/commercial_quota/consumption.rb`
- Create: `spec/domain/commercial_quota/hourly_shows_duration_spec.rb`
- Modify: `spec/domain/commercial_quota/check_spec.rb` if assertions assume `n * sum(catalog)`

**Interfaces:**
- Produces: `CommercialQuota::HourlyShowsDuration.call(rotation:, shows_per_hour:) -> Integer`
- Consumes: `rotation.ordered_items` durations (same rules as `CycleDuration` item seconds)

- [ ] **Step 1: Failing examples**

```ruby
# three items 10, 20, 30; shows_per_hour 3 → 60
# three items 10, 20, 30; shows_per_hour 2 → 30 (first two picks)
# three items 10, 20, 30; shows_per_hour 5 → 10+20+30+10+20 = 90
```

- [ ] **Step 2: RED** then implement:

```ruby
module CommercialQuota
  class HourlyShowsDuration < ServiceObject
    def initialize(rotation:, shows_per_hour:)
      @rotation = rotation
      @shows_per_hour = shows_per_hour.to_i
    end

    def call
      return 0 if shows_per_hour < 1

      catalog = rotation.ordered_items
      return shows_per_hour * CycleDuration::DEFAULT_ITEM_SECONDS if catalog.empty?

      durations = catalog.map { |item| item_seconds(item) }
      shows_per_hour.times.sum { |i| durations[i % durations.size] }
    end
    # item_seconds same as CycleDuration
  end
end
```

```ruby
def plan_seconds(plan)
  n = plan.shows_per_hour.to_i
  return 0 if n < 1

  HourlyShowsDuration.call(rotation: plan.rotation, shows_per_hour: n)
end
```

Keep `CycleDuration` for any non-commercial callers that still need full-catalog sum (grep first; if only Consumption uses it for commercials, leave CycleDuration as helper for empty/default).

- [ ] **Step 3: GREEN + commit**

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/commercial_quota/
git commit -am "fix(quota): bill commercial hours as sum of sequential show durations"
```

---

### Task 4: `UpdateOrderClips` (replace singleton replace services)

**Files:**
- Create: `app/domain/advertising/update_order_clips.rb`
- Create: `spec/domain/advertising/update_order_clips_spec.rb`
- Modify callers in Task 5; delete `replace_clip.rb` / `replace_draft_clip.rb` after migration
- Delete or rewrite: `spec/domain/advertising/replace_clip_spec.rb`, `replace_draft_clip_spec.rb`

**Interfaces:**
- Produces: `Advertising::UpdateOrderClips.call(order:, media_assets:) -> order`
- Behavior: draft → sync items, no regen; active → sync + bump `document_version` + `EnqueueRegen` on active plans; reject other statuses
- Validation: non-empty, unique, each `broadcast_ready?`, each `organization_id == order.organization_id`

- [ ] **Step 1: Failing specs** covering draft sync, active regen enqueue, reject empty/duplicate/foreign/non-ready, preserve order of assets

- [ ] **Step 2: Implement sync**

```ruby
AdvertisingOrder.transaction do
  rotation = order.rotation
  rotation.rotation_items.destroy_all
  media_assets.each do |asset|
    rotation.rotation_items.create!(
      media_asset: asset,
      display_duration_seconds: asset.duration_seconds
    )
  end
  attrs = { media_asset_id: nil }
  attrs[:document_version] = order.document_version + 1 if order.active?
  order.update!(attrs)
end
order.rotation.media_plans.active.find_each { |plan| Playlists::EnqueueRegen.from_plan(plan) } if order.active?
```

Prefer destroy_all + recreate to keep positions contiguous via `assign_position`.

- [ ] **Step 3: GREEN + commit**

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/advertising/update_order_clips_spec.rb
git commit -am "feat(advertising): sync ordered order clips via UpdateOrderClips"
```

---

### Task 5: Controllers + strong params

**Files:**
- Modify: `app/controllers/advertising_orders_controller.rb`
- Modify: `app/controllers/admin/advertising_orders_controller.rb`
- Modify: `app/policies/advertising_order_policy.rb` if `replace_clip?` should become `update_clips?` for active

**Interfaces:**
- Strong params: `media_asset_ids: []` instead of `:media_asset_id`
- Create: resolve ordered assets from org.ready scope, call `CreateOrder(..., media_assets:)`
- Cabinet `replace_clip`: call `UpdateOrderClips` with selected list (or keep dedicated page that edits full list)
- Admin update (draft or active): if `media_asset_ids` present, call `UpdateOrderClips`

- [ ] **Step 1: Update permit lists and resolvers**

```ruby
params.fetch(:advertising_order, {}).permit(
  ...,
  media_asset_ids: [],
  ...
)

def find_media_assets
  ids = Array(order_params[:media_asset_ids]).map(&:presence).compact
  return [] if ids.empty?

  assets_by_id = form_organization.media_assets.ready.where(id: ids).index_by { |a| a.id.to_s }
  ids.map { |id| assets_by_id[id.to_s] || (raise Advertising::Error, ...) }
end
```

Preserve submitted order when mapping ids → records.

- [ ] **Step 2: Wire create/update/replace_clip; remove `ReplaceDraftClip` / `ReplaceClip` calls**

- [ ] **Step 3: Commit** (request specs land in Task 8; smoke domain path if needed)

```bash
git commit -am "feat(advertising): accept ordered media_asset_ids in order controllers"
```

---

### Task 6: Shared form UI + Stimulus list controller

**Files:**
- Modify: `app/views/advertising_orders/_form.html.slim`
- Create: `app/javascript/controllers/order_media_assets_controller.js`
- Modify: `app/javascript/admin.js` (register new controller; remove old if unused)
- Optionally keep `order_media_asset_controller.js` deleted or unused
- Modify: `config/locales/mediateca.ru.yml`, `mediateca.en.yml` (labels: «Ролики», hint about cycling)

**Interfaces:**
- Form posts `advertising_order[media_asset_ids][]` in visual order
- Show editor when `new_record? || draft? || active?` (per design: full list edit on active too). If product prefers active-only via replace_clip page, still expose list editor there.

- [ ] **Step 1: Slim structure**

```slim
-# data-controller="order-media-assets"
-# template row + selected rows with hidden inputs media_asset_ids[]
-# buttons: add (from select of remaining assets), move up/down, remove
-# hint: clips rotate through hourly slots independent of count
```

First iteration: up/down buttons only (no drag).

- [ ] **Step 2: Stimulus**

Targets: `list`, `row`, `availableSelect`, `template` (or build rows in JS). Actions: `add`, `remove`, `moveUp`, `moveDown`. Disable remove when one row left. On add, remove option from available select; on remove, restore option.

- [ ] **Step 3: Prefill from `@advertising_order.rotation.ordered_items` on edit**

- [ ] **Step 4: Commit**

```bash
git commit -am "feat(advertising): ordered multi-clip editor on shared order form"
```

---

### Task 7: Show / print / replace_clip views

**Files:**
- Modify: `app/views/advertising_orders/show.html.slim`
- Modify: `app/views/advertising_orders/replace_clip.html.slim` — reuse list editor or redirect to edit
- Modify: `app/views/admin/advertising_orders/show.html.erb`
- Modify: `app/components/advertising/print_sheet_component.html.slim` (+ component Ruby if needed)
- Helper: `advertising_orders_helper.rb` — e.g. `order_clip_rows(order)` → ordered items

Display each item: filename/title + duration. Fallback: if `ordered_items` empty and legacy `clip_title` present, show legacy once.

- [ ] **Step 1: Update views**
- [ ] **Step 2: Commit**

```bash
git commit -am "feat(advertising): show ordered clip lists on order surfaces"
```

---

### Task 8: Playlist cycle coverage + request/system specs

**Files:**
- Modify: `spec/domain/playlists/generate_for_date_spec.rb` (or focused NeutralPicker + generate example)
- Modify: `spec/requests/advertising_orders_spec.rb`
- Modify: `spec/requests/admin/advertising_orders_spec.rb`
- Modify: `spec/system/advertising_order_placement_spec.rb`
- Modify: `spec/system/advertising_order_replace_clip_spec.rb`

- [ ] **Step 1: Playlist / picker example**

Build one commercial plan whose rotation has assets A,B,C with `shows_per_hour: 2` and portrait that yields 2 commercial takes in hour 0 and continues in hour 1. Assert media_asset sequence across the two hours is A,B then C,… (cursor continuity). Also assert 3/hour → A,B,C in one hour.

Helper approach: call `NeutralPicker` with memoized instance across two `take(2)` calls if full generate setup is heavy; prefer one generate_for_date example if fixtures already exist.

- [ ] **Step 2: Request examples**

- POST create with `media_asset_ids: [id1, id2]`
- Reject empty / foreign / duplicate
- Admin + cabinet draft update list
- Active update/replace enqueues regen (reuse ReplaceClip expectations)
- Form exposes list UI (no sole `#advertising_order_media_asset_id` requirement)

- [ ] **Step 3: Run focused then broader suites**

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec \
  spec/domain/advertising/ \
  spec/domain/commercial_quota/ \
  spec/domain/playlists/generate_for_date_spec.rb \
  spec/requests/advertising_orders_spec.rb \
  spec/requests/admin/advertising_orders_spec.rb
```

- [ ] **Step 4: Commit**

```bash
git commit -am "test(advertising): cover multi-clip create, update, quota, and playlist cycle"
```

---

### Task 9: Cleanup + CONCEPTS touch

**Files:**
- Delete obsolete `ReplaceClip` / `ReplaceDraftClip` if unused
- Modify: `CONCEPTS.md` — Advertising order: ordered clip catalog via system rotation; hourly slots cycle the catalog
- Grep for `media_asset_id`, `.sole`, `ReplaceClip`, `ReplaceDraftClip`, `order-media-asset`

- [ ] **Step 1: Grep cleanup**
- [ ] **Step 2: CONCEPTS one-paragraph update**
- [ ] **Step 3: Full relevant RSpec + commit**

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/advertising spec/domain/commercial_quota spec/requests/advertising_orders_spec.rb spec/requests/admin/advertising_orders_spec.rb
git commit -am "docs: note multi-clip sequential orders in CONCEPTS"
```

---

## Spec coverage checklist (self-review)

| Spec requirement | Task |
|------------------|------|
| Ordered N clips on create | 2, 5, 6 |
| Frequency independent / cycle | 8 (playlist) |
| Per-show duration / quota | 3 |
| Rotation SoT; nullable `media_asset_id` | 1, 2 |
| Update full list draft/active | 4, 5 |
| Shared admin + cabinet UI | 5, 6, 7 |
| No duplicate assets | 4 (+ model uniqueness) |
| Out of scope: dual-write table, split plans | — |

## Execution handoff

Plan complete and saved to `docs/superpowers/plans/2026-09-17-multi-clip-advertising-order.md`.

**Two execution options:**

1. **Subagent-Driven (recommended)** — fresh subagent per task, review between tasks
2. **Inline Execution** — execute tasks in this session with executing-plans checkpoints

Which approach?
