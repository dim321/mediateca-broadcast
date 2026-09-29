# Media playback and content validation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Play a media asset on its cabinet and admin show pages, and let only a traffic manager mark or clear content validation, blocking new air use until the mark exists.

**Architecture:** Two nullable columns on `media_assets` record who validated the clip and when. `MediaAssets::MarkContentValidated` and `MediaAssets::RevokeContentValidation` are the only writers. Activate, active clip replace, and non-draft rotation-item writes refuse an unmarked asset. Revoke cancels active orders through `Advertising::CancelOrder`, then deletes rotation items that do not belong to an order and enqueues playlist regen after that transaction.

**Tech Stack:** Ruby 4.0.2, Rails ~> 8.1, PostgreSQL 18, RSpec, FactoryBot, Pundit (cabinet only), Slim + daisyUI (cabinet), ERB + Flowbite utilities (admin), Stimulus, importmap, mpegts.js.

## Global Constraints

- Cabinet CSS is daisyUI. Admin CSS is Flowbite utilities. Do not put `btn`, `alert`, `badge`, or other daisyUI classes in `app/views/admin/**`.
- Admin has no Pundit. Role checks for mark/revoke live in the admin controller.
- Do not add traffic managers to `ApplicationPolicy#lk_content_access?`. Extra read access is only on `MediaAssetPolicy`.
- Accountants stay denied on media assets (KTD11).
- Do not backfill existing rows as validated.
- Do not delete rotation items that belong to an advertising order's system rotation.
- Do not cancel draft or completed orders on revoke. Cancel only `active` orders.
- `Advertising::ValidatesMediaAssets` / `CreateOrder` do not gain a content-validation check. Drafts may contain unmarked assets.
- Video playback source is `broadcast_file` (MPEG-TS, `video/mp2t`). No second preview encode. Native `<video src>` is not used for `.ts`.
- Images, audio, PDF, and presentations play or display the original `file`. They have no `.ts`.
- Playlist regen stays outside the revoke transaction. `Airtime::Cancel` already enqueues regen after its own transaction.
- Do not take `Airtime::ScreenLock` inside `Playlists::GenerateForDate`.
- Copy goes in `config/locales/mediateca.ru.yml` and `config/locales/mediateca.en.yml`.
- Mutations that redirect use `status: :see_other`.
- Tests run inside Docker: `docker compose exec -e RAILS_ENV=test web bundle exec rspec <path>`. Never `bundle exec rspec` on the host.
- Spec: `docs/superpowers/specs/2026-09-28-media-playback-content-validation-design.md`.

---

### Task 1: Validation columns

**Files:**
- Create: `db/migrate/20260928120000_add_content_validation_to_media_assets.rb`
- Modify: `app/models/media_asset.rb`
- Modify: `spec/factories/media_assets.rb`
- Test: `spec/models/media_asset_spec.rb`

**Interfaces:**
- Consumes: existing `MediaAsset`, `uploaded_by`
- Produces: `MediaAsset#content_validated?` → bool, true only when both `content_validated_at` and `content_validated_by_id` are present. `belongs_to :content_validated_by`. Factory trait `:content_validated`.

- [ ] **Step 1: Write the failing model spec**

Add to `spec/models/media_asset_spec.rb`:

```ruby
describe "#content_validated?" do
  it "is false when both columns are empty" do
    asset = create(:media_asset, :with_png_file)
    expect(asset.content_validated?).to be false
  end

  it "is false when only the timestamp is set" do
    asset = create(:media_asset, :with_png_file, content_validated_at: Time.current)
    expect(asset.content_validated?).to be false
  end

  it "is true when timestamp and user are both set" do
    asset = create(:media_asset, :with_png_file, :content_validated)
    expect(asset.content_validated?).to be true
    expect(asset.content_validated_by).to eq(asset.uploaded_by)
  end
end
```

- [ ] **Step 2: Run the spec and confirm it fails**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/models/media_asset_spec.rb`

Expected: FAIL because `:content_validated` and `#content_validated?` do not exist.

- [ ] **Step 3: Migrate and implement**

`db/migrate/20260928120000_add_content_validation_to_media_assets.rb`:

```ruby
# frozen_string_literal: true

class AddContentValidationToMediaAssets < ActiveRecord::Migration[8.1]
  def change
    add_reference :media_assets, :content_validated_by, foreign_key: { to_table: :users, on_delete: :nullify }, null: true
    add_column :media_assets, :content_validated_at, :datetime
  end
end
```

Run:

```bash
docker compose exec web bin/rails db:migrate
docker compose exec -e RAILS_ENV=test web bin/rails db:migrate
```

In `spec/factories/media_assets.rb`, inside `factory :media_asset`, add:

```ruby
trait :content_validated do
  content_validated_at { Time.zone.parse("2026-09-28 12:00:00 UTC") }
  content_validated_by { uploaded_by }
end
```

In `app/models/media_asset.rb`:

- Add `content_validated_at` and `content_validated_by_id` to the schema comment and to `ransackable_attributes`.
- Add `belongs_to :content_validated_by, class_name: "User", optional: true` next to `uploaded_by`.
- Add:

```ruby
def content_validated?
  content_validated_at.present? && content_validated_by_id.present?
end
```

- [ ] **Step 4: Run the spec**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/models/media_asset_spec.rb`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add db/migrate/20260928120000_add_content_validation_to_media_assets.rb db/schema.rb app/models/media_asset.rb spec/factories/media_assets.rb spec/models/media_asset_spec.rb
git commit -m "feat: record who validated a media asset"
```

---

### Task 2: MarkContentValidated

**Files:**
- Create: `app/domain/media_assets/error.rb`
- Create: `app/domain/media_assets/mark_content_validated.rb`
- Test: `spec/domain/media_assets/mark_content_validated_spec.rb`

**Interfaces:**
- Consumes: `MediaAsset#content_validated?`, `#broadcast_ready?`, `#ready?`, `#video?`
- Produces: `MediaAssets::Error < StandardError`. `MediaAssets::MarkContentValidated.call(media_asset:, user:)` returns the asset. Sets both columns when the asset is playable and unmarked. Leaves an existing mark unchanged. Raises `MediaAssets::Error` with `I18n.t("media_assets.content_validation.not_playable")` when the asset is not playable.

- [ ] **Step 1: Write the failing spec**

`spec/domain/media_assets/mark_content_validated_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe MediaAssets::MarkContentValidated do
  let(:organization) { create(:organization) }
  let(:user) { create(:user, :traffic_manager, organization: organization) }

  it "sets the timestamp and the user for a ready image" do
    asset = create(:media_asset, :ready, :with_png_file, organization: organization)

    described_class.call(media_asset: asset, user: user)

    expect(asset.reload.content_validated?).to be true
    expect(asset.content_validated_by).to eq(user)
  end

  it "sets the mark for a ready video that has a broadcast file" do
    asset = create(:media_asset, :ready, :with_mp4_file, :with_broadcast_ts, organization: organization)

    described_class.call(media_asset: asset, user: user)

    expect(asset.reload.content_validated?).to be true
  end

  it "does not change an existing mark" do
    marker = create(:user, :traffic_manager, organization: organization)
    asset = create(:media_asset, :ready, :with_png_file, :content_validated, organization: organization, uploaded_by: marker)
    stamped_at = asset.content_validated_at

    described_class.call(media_asset: asset, user: user)

    asset.reload
    expect(asset.content_validated_at).to eq(stamped_at)
    expect(asset.content_validated_by).to eq(marker)
  end

  it "refuses a video without a broadcast file" do
    asset = create(:media_asset, :ready, :with_mp4_file, organization: organization)

    expect {
      described_class.call(media_asset: asset, user: user)
    }.to raise_error(MediaAssets::Error, I18n.t("media_assets.content_validation.not_playable"))
    expect(asset.reload.content_validated?).to be false
  end

  it "refuses an asset that is not ready" do
    asset = create(:media_asset, :with_png_file, organization: organization, processing_status: "pending")

    expect {
      described_class.call(media_asset: asset, user: user)
    }.to raise_error(MediaAssets::Error)
  end
end
```

Add both locale keys now so the example message matches:

`config/locales/mediateca.ru.yml` under `media_assets:`:

```yaml
    content_validation:
      not_playable: Ролик ещё нельзя проверить
      marked: Содержимое ролика проверено
      revoked: Отметка снята, активные заказы с роликом отменены
      forbidden: Отметку ставит только трафик-менеджер
      not_validated: Содержимое ролика не проверено
      validated: Содержимое проверено
      validated_by: "Проверил %{name}, %{time}"
      confirm_revoke: Снять отметку? Активные заказы с этим роликом будут отменены, ролик уйдёт из обычных и служебных ротаций.
```

`config/locales/mediateca.en.yml` under `media_assets:`:

```yaml
    content_validation:
      not_playable: This clip cannot be validated yet
      marked: Clip content validated
      revoked: Validation cleared and active orders with this clip were cancelled
      forbidden: Only a traffic manager can set this mark
      not_validated: Content not validated
      validated: Content validated
      validated_by: "Validated by %{name}, %{time}"
      confirm_revoke: Clear validation? Active orders with this clip will be cancelled and the clip will leave catalog and service rotations.
```

- [ ] **Step 2: Run the spec and confirm it fails**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/media_assets/mark_content_validated_spec.rb`

Expected: FAIL with uninitialized constant `MediaAssets::MarkContentValidated`.

- [ ] **Step 3: Implement**

`app/domain/media_assets/error.rb`:

```ruby
# frozen_string_literal: true

module MediaAssets
  class Error < StandardError; end
end
```

`app/domain/media_assets/mark_content_validated.rb`:

```ruby
# frozen_string_literal: true

module MediaAssets
  class MarkContentValidated < ServiceObject
    def initialize(media_asset:, user:)
      @media_asset = media_asset
      @user = user
    end

    def call
      return media_asset if media_asset.content_validated?

      raise Error, I18n.t("media_assets.content_validation.not_playable") unless playable?

      media_asset.update!(
        content_validated_at: Time.current,
        content_validated_by: user
      )
      media_asset
    end

    private

    attr_reader :media_asset, :user

    def playable?
      return false unless media_asset.ready?
      return media_asset.broadcast_ready? if media_asset.video?

      true
    end
  end
end
```

- [ ] **Step 4: Run the spec**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/media_assets/mark_content_validated_spec.rb`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/domain/media_assets spec/domain/media_assets/mark_content_validated_spec.rb config/locales/mediateca.ru.yml config/locales/mediateca.en.yml
git commit -m "feat: mark media content as validated"
```

---

### Task 3: RevokeContentValidation

**Files:**
- Create: `app/domain/media_assets/revoke_content_validation.rb`
- Test: `spec/domain/media_assets/revoke_content_validation_spec.rb`

**Interfaces:**
- Consumes: `Advertising::CancelOrder`, `Playlists::EnqueueRegen.from_rotation`, `MediaAsset#content_validated?`, `Rotation#advertising_order`
- Produces: `MediaAssets::RevokeContentValidation.call(media_asset:)` returns the asset. No-op when the mark is absent. Otherwise cancels each active order whose rotation items include the asset, then in a later transaction destroys rotation items whose rotation has no advertising order and clears both columns, then calls `Playlists::EnqueueRegen.from_rotation` for each stripped rotation.

- [ ] **Step 1: Write the failing spec**

`spec/domain/media_assets/revoke_content_validation_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe MediaAssets::RevokeContentValidation do
  include ActiveJob::TestHelper

  let(:organization) { create(:organization, :client, time_zone: "UTC") }
  let(:user) { create(:user, :traffic_manager, organization: organization) }
  let(:asset) do
    create(:media_asset, :ready, :with_png_file, :content_validated, organization: organization, duration_seconds: 10)
  end

  it "does nothing when the asset is unmarked" do
    unmarked = create(:media_asset, :ready, :with_png_file, organization: organization)

    expect {
      described_class.call(media_asset: unmarked)
    }.not_to change(AdvertisingOrder, :count)
    expect(unmarked.reload.content_validated?).to be false
  end

  it "cancels an active order and keeps the draft order rotation item" do
    draft = Advertising::CreateOrder.call(
      organization: organization,
      created_by: user,
      media_assets: [ asset ],
      product_name: "Draft",
      shows_per_hour: 3
    )
    active = Advertising::CreateOrder.call(
      organization: organization,
      created_by: user,
      media_assets: [ asset ],
      product_name: "Live",
      shows_per_hour: 3
    )
    group = create_group_with_hours!(organization: organization)
    fill_order_grid!(active, screen: group.screens.first, dates: [ Date.new(2026, 6, 3) ])
    Advertising::ActivateOrder.call(order: active)

    described_class.call(media_asset: asset)

    expect(active.reload).to be_cancelled
    expect(draft.reload).to be_draft
    expect(draft.rotation.rotation_items.where(media_asset: asset)).to exist
    expect(active.rotation.rotation_items.where(media_asset: asset)).to exist
    expect(asset.reload.content_validated?).to be false
  end

  it "removes a service-theme item and enqueues regen for that rotation" do
    operator = create(:organization, :operator)
    theme = ServiceThemes::Create.call(organization: operator, name: "Theme")
    service_asset = create(
      :media_asset, :ready, :with_png_file, :content_validated,
      organization: operator, content_type: "service", visibility: "network"
    )
    theme.welcome_rotation.rotation_items.create!(
      media_asset: service_asset,
      display_duration_seconds: service_asset.duration_seconds
    )
    station = create(:station, location: create(:location, time_zone: "UTC"), offline_cache_hours: 24)
    screen = create(:screen, station: station)
    portrait = create(:broadcast_portrait, :for_screen, screen: screen)
    create(:broadcast_portrait_block, :service_welcome, broadcast_portrait: portrait, rotation: theme.welcome_rotation)

    travel_to(Time.utc(2026, 9, 28, 12, 0, 0)) do
      expect {
        described_class.call(media_asset: service_asset)
      }.to have_enqueued_job(Playlists::GenerateForDateJob).with(station.id, "2026-09-28")
    end

    expect(theme.welcome_rotation.rotation_items.where(media_asset: service_asset)).to be_empty
    expect(service_asset.reload.content_validated?).to be false
  end
end
```

- [ ] **Step 2: Run the spec and confirm it fails**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/media_assets/revoke_content_validation_spec.rb`

Expected: FAIL with uninitialized constant `MediaAssets::RevokeContentValidation`. The active-order example uses `:content_validated`, so `ActivateOrder` still succeeds before Task 5.

- [ ] **Step 3: Implement**

`app/domain/media_assets/revoke_content_validation.rb`:

```ruby
# frozen_string_literal: true

module MediaAssets
  class RevokeContentValidation < ServiceObject
    def initialize(media_asset:)
      @media_asset = media_asset
    end

    def call
      return media_asset unless media_asset.content_validated?

      cancel_active_orders
      rotations = strip_non_order_items
      rotations.each { |rotation| Playlists::EnqueueRegen.from_rotation(rotation) }
      media_asset
    end

    private

    attr_reader :media_asset

    def cancel_active_orders
      AdvertisingOrder.active
        .joins(rotation: :rotation_items)
        .where(rotation_items: { media_asset_id: media_asset.id })
        .distinct
        .find_each do |order|
          Advertising::CancelOrder.call(order: order)
        end
    end

    def strip_non_order_items
      items = media_asset.rotation_items.includes(rotation: :advertising_order).select do |item|
        item.rotation.advertising_order.blank?
      end
      rotations = items.map(&:rotation).uniq
      MediaAsset.transaction do
        items.each(&:destroy!)
        media_asset.update!(content_validated_at: nil, content_validated_by: nil)
      end
      rotations
    end
  end
end
```

`CreateOrder` currently inserts rotation items before the order row exists. The active-order example calls `ActivateOrder` on an order built by `CreateOrder`. That path does not need the draft exception yet. The draft example keeps items because revoke only deletes items whose rotation already has an advertising order. After `CreateOrder` today, the draft order exists, so its items are kept. Good.

- [ ] **Step 4: Run the spec**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/media_assets/revoke_content_validation_spec.rb`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/domain/media_assets/revoke_content_validation.rb spec/domain/media_assets/revoke_content_validation_spec.rb
git commit -m "feat: clear content validation and cancel active orders"
```

---

### Task 4: Rotation-item gate and draft order create order

**Files:**
- Modify: `app/models/rotation_item.rb`
- Modify: `app/domain/advertising/create_order.rb`
- Modify: `spec/factories/rotation_items.rb`
- Modify: `spec/models/rotation_item_spec.rb`
- Test: `spec/domain/advertising/create_order_spec.rb` (existing unmarked asset must still create a draft)

**Interfaces:**
- Consumes: `MediaAsset#content_validated?`, `Rotation#advertising_order`
- Produces: `RotationItem` adds `:content_not_validated` on `:media_asset` when the asset is unmarked, on create and when `media_asset_id` or `rotation_id` changes, unless `rotation.advertising_order` is draft. `CreateOrder` creates the draft order before rotation items so that exception is visible. Factory `:rotation_item` media assets include `:content_validated`.

- [ ] **Step 1: Write the failing rotation-item examples**

In `spec/models/rotation_item_spec.rb`, add:

```ruby
it "rejects an unmarked asset on a catalog rotation" do
  rotation = create(:rotation)
  asset = create(:media_asset, :ready, :with_png_file, organization: rotation.organization)
  item = build(:rotation_item, rotation: rotation, media_asset: asset, position: 1)

  expect(item).not_to be_valid
  expect(item.errors[:media_asset]).to include(
    I18n.t("activerecord.errors.models.rotation_item.attributes.media_asset.content_not_validated")
  )
end

it "allows an unmarked asset on a draft order rotation" do
  organization = create(:organization, :client)
  asset = create(:media_asset, :ready, :with_png_file, organization: organization, duration_seconds: 10)
  order = Advertising::CreateOrder.call(
    organization: organization,
    created_by: create(:user, organization: organization),
    media_assets: [ asset ],
    product_name: "Draft"
  )

  expect(order.rotation.rotation_items.find_by(media_asset: asset)).to be_present
end

it "rejects moving an item onto another catalog rotation when the asset is unmarked" do
  organization = create(:organization)
  asset = create(:media_asset, :ready, :with_png_file, :content_validated, organization: organization)
  source = create(:rotation, organization: organization)
  destination = create(:rotation, organization: organization)
  item = source.rotation_items.create!(media_asset: asset, position: 1)
  asset.update!(content_validated_at: nil, content_validated_by: nil)
  item.rotation = destination

  expect(item).not_to be_valid
end
```

Replace the pending-service example that currently expects a pending service clip to be valid. It must expect invalid:

```ruby
it "rejects an unvalidated service clip on a theme rotation" do
  rotation = create(:rotation, :system_managed)
  asset = create(:media_asset, :with_png_file, content_type: "service", processing_status: "pending",
    organization: rotation.organization)
  item = build(:rotation_item, rotation: rotation, media_asset: asset, position: 1)

  expect(item).not_to be_valid
end
```

Update the existing "allows a network-shared media asset" and "rejects duplicate media_asset_id" examples so their assets include `:content_validated`. Without that, they fail for the new error instead of the behavior they describe.

- [ ] **Step 2: Run the spec and confirm the new examples fail**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/models/rotation_item_spec.rb`

Expected: the unmarked-catalog example FAILs because the item is valid.

- [ ] **Step 3: Implement the validation, the factory, the locale, and the create reorder**

`spec/factories/rotation_items.rb` media_asset association:

```ruby
media_asset do
  association :media_asset, :ready, :content_validated, :with_png_file, organization: rotation.organization
end
```

`config/locales/mediateca.ru.yml` under `activerecord.errors.models.rotation_item.attributes.media_asset`:

```yaml
              content_not_validated: содержимое не проверено трафик-менеджером
```

`config/locales/mediateca.en.yml` in the same nest:

```yaml
              content_not_validated: content has not been validated by a traffic manager
```

`app/models/rotation_item.rb` add:

```ruby
validate :media_asset_content_validated, on: :create
validate :media_asset_content_validated, if: -> { media_asset_id_changed? || rotation_id_changed? }
```

```ruby
def media_asset_content_validated
  return if media_asset.blank? || rotation.blank?
  return if media_asset.content_validated?
  return if rotation.advertising_order&.draft?

  errors.add(:media_asset, :content_not_validated)
end
```

`CreateOrder` inserts items before the order exists, so `advertising_order` is nil and the exception would reject draft clips. In `app/domain/advertising/create_order.rb`, create the order before the items. Keep the same attributes. Sequence inside the transaction:

```ruby
rotation = organization.rotations.create!(
  name: "order-#{SecureRandom.uuid}",
  system_managed: true
)
order = organization.advertising_orders.create!(
  created_by: created_by,
  media_asset: nil,
  rotation: rotation,
  product_name: product_name,
  placement_kind: placement_kind,
  shows_per_hour: shows_per_hour,
  distribution_strategy: distribution_strategy,
  coefficient_percent: coefficient_percent,
  discount_cents: discount_cents
)
media_assets.each do |asset|
  rotation.rotation_items.create!(
    media_asset: asset,
    display_duration_seconds: asset.duration_seconds
  )
end
rotation.update!(name: I18n.t("advertising.system_rotation_name", number: order.id))
order
```

`advertising.errors.content_not_validated` is added in Task 5. Do not add it here.

- [ ] **Step 4: Run rotation-item and create-order specs**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/models/rotation_item_spec.rb spec/domain/advertising/create_order_spec.rb`

Expected: PASS. `create_order_spec` uses an unmarked `:ready` asset and must stay green.

- [ ] **Step 5: Commit**

```bash
git add app/models/rotation_item.rb app/domain/advertising/create_order.rb spec/factories/rotation_items.rb spec/models/rotation_item_spec.rb config/locales/mediateca.ru.yml config/locales/mediateca.en.yml
git commit -m "feat: require content validation to enter a rotation"
```

---

### Task 5: Activate and active clip-replace gates

**Files:**
- Modify: `app/domain/advertising/activate_order.rb`
- Modify: `app/domain/advertising/update_order_clips.rb`
- Modify: `spec/domain/advertising/activate_order_spec.rb`
- Modify: `spec/domain/advertising/update_order_clips_spec.rb`
- Modify: specs that activate an order or replace clips on an active order (listed in Step 3)

**Interfaces:**
- Consumes: `MediaAsset#content_validated?`, `Advertising::Error`
- Produces: `ActivateOrder#call` raises `Advertising::Error` with `I18n.t("advertising.errors.content_not_validated")` before occupy when any rotation item asset is unmarked. `UpdateOrderClips#call` raises the same error before write when `order.active?` and any replacement asset is unmarked. Draft replace still accepts unmarked assets.

- [ ] **Step 1: Write the failing examples**

In `spec/domain/advertising/activate_order_spec.rb`:

```ruby
it "does not occupy when a clip is unmarked" do
  unmarked = create(:media_asset, :ready, :with_png_file, organization: organization, duration_seconds: 10)
  unmarked_order = Advertising::CreateOrder.call(
    organization: organization,
    created_by: user,
    media_assets: [ unmarked ],
    product_name: "Unmarked",
    shows_per_hour: 3
  )
  setup_order!(order: unmarked_order, dates: [ Date.new(2026, 6, 3) ])

  expect {
    described_class.call(order: unmarked_order)
  }.to raise_error(Advertising::Error, I18n.t("advertising.errors.content_not_validated"))
  expect(unmarked_order.reload).to be_draft
  expect(MediaPlan.count).to eq(0)
end
```

In `spec/domain/advertising/update_order_clips_spec.rb`:

```ruby
it "rejects an unmarked clip on an active order" do
  Advertising::ActivateOrder.call(order: order)
  unmarked = create(:media_asset, :ready, :with_png_file, organization: organization, duration_seconds: 9)

  expect {
    described_class.call(order: order.reload, media_assets: [ unmarked ])
  }.to raise_error(Advertising::Error, I18n.t("advertising.errors.content_not_validated"))
end

it "accepts an unmarked clip on a draft" do
  unmarked = create(:media_asset, :ready, :with_png_file, organization: organization, duration_seconds: 9)

  described_class.call(order: order, media_assets: [ unmarked ])

  expect(order.reload.rotation.ordered_items.sole.media_asset).to eq(unmarked)
end
```

The active example needs `order`'s current clips to already be validated, which Step 3 does by adding `:content_validated` to `clip_a`.

- [ ] **Step 2: Run the new examples and confirm they fail**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/advertising/activate_order_spec.rb spec/domain/advertising/update_order_clips_spec.rb`

Expected: the new activate example FAIL because occupy proceeds. Existing activate examples still pass until the gate lands, then they fail until Step 3 adds the trait.

- [ ] **Step 3: Implement the gates and mark assets that existing success paths activate**

`config/locales/mediateca.ru.yml` under `advertising.errors`:

```yaml
      content_not_validated: ролик не прошёл проверку содержимого
```

`config/locales/mediateca.en.yml` under `advertising.errors`:

```yaml
      content_not_validated: clip content has not been validated
```

In `ActivateOrder#call`, before `occupied = []`:

```ruby
raise Error, I18n.t("advertising.errors.content_not_validated") unless clips_content_validated?
```

```ruby
def clips_content_validated?
  items = order.rotation.rotation_items.includes(:media_asset)
  items.any? && items.all? { |item| item.media_asset.content_validated? }
end
```

In `UpdateOrderClips#call`, after `validate_order_status!`:

```ruby
validate_content_validated! if order.active?
```

```ruby
def validate_content_validated!
  return if media_assets.all?(&:content_validated?)

  raise Error, I18n.t("advertising.errors.content_not_validated")
end
```

Add `:content_validated` to every media asset that an existing example activates or uses as a replacement on an already active order. Draft-only assets stay unmarked. Required edits:

- `spec/domain/advertising/activate_order_spec.rb` `let(:asset)` and `long_clip` (the 240 second clip that is activated).
- `spec/domain/advertising/update_order_clips_spec.rb` `clip_a`, `clip_b`, `clip_c`, and the ready video that replaces clips on an active order. Leave `pending_clip` unmarked.
- `spec/domain/advertising/grid_coverage_spec.rb` the asset passed to `CreateOrder` before `ActivateOrder`.
- `spec/requests/advertising_orders_spec.rb` `let(:asset)` and any later `create(:media_asset, :ready, ...)` that is activated or that replaces clips after the order is active (`replacement` near the active replace example, `long_clip` if that example activates).
- `spec/requests/admin/advertising_orders_spec.rb` the same pattern.
- `spec/system/advertising_order_replace_clip_spec.rb` assets that are activated or used as the active replacement.

Example edit:

```ruby
let(:asset) { create(:media_asset, :ready, :content_validated, :with_png_file, organization: organization, duration_seconds: 10) }
```

- [ ] **Step 4: Run the advertising specs**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/advertising spec/requests/advertising_orders_spec.rb spec/requests/admin/advertising_orders_spec.rb spec/system/advertising_order_replace_clip_spec.rb spec/domain/media_assets/revoke_content_validation_spec.rb`

Expected: PASS. If a failure message is `ролик не прошёл проверку содержимого` or the English equivalent, add `:content_validated` to that example's asset and rerun that file.

- [ ] **Step 5: Commit**

```bash
git add app/domain/advertising/activate_order.rb app/domain/advertising/update_order_clips.rb spec/domain/advertising spec/requests/advertising_orders_spec.rb spec/requests/admin/advertising_orders_spec.rb spec/system/advertising_order_replace_clip_spec.rb config/locales/mediateca.ru.yml config/locales/mediateca.en.yml
git commit -m "feat: block activation until clip content is validated"
```

---

### Task 6: MediaAssetPolicy

**Files:**
- Modify: `app/policies/media_asset_policy.rb`
- Modify: `spec/policies/media_asset_policy_spec.rb`

**Interfaces:**
- Consumes: `ApplicationPolicy#traffic_manager?`, `#operator?`, `#in_organization?`
- Produces: `MediaAssetPolicy#index?` and `#show?` true for manager, administrator, traffic manager, and any operator-org user. Accountant false. Scope unchanged for managers plus traffic managers see own organization or `visibility: network`. `#mark_content_validation?` and `#revoke_content_validation?` true only for a traffic manager who is in the asset organization or whose organization is the operator.

- [ ] **Step 1: Write the failing policy examples**

Add to `spec/policies/media_asset_policy_spec.rb`:

```ruby
describe "traffic manager reads" do
  let(:traffic_manager) { create(:user, :traffic_manager, organization: org) }

  it "allows index and show for own assets" do
    policy = described_class.new(traffic_manager, asset)
    expect(policy.index?).to be true
    expect(policy.show?).to be true
  end

  it "allows show of a foreign network asset and forbids marking it" do
    shared = create(:media_asset, :with_png_file, :network_neutral, organization: other_org)
    policy = described_class.new(traffic_manager, shared)
    expect(policy.show?).to be true
    expect(policy.mark_content_validation?).to be false
    expect(policy.revoke_content_validation?).to be false
  end

  it "allows marking an asset of the traffic manager organization" do
    policy = described_class.new(traffic_manager, asset)
    expect(policy.mark_content_validation?).to be true
    expect(policy.revoke_content_validation?).to be true
  end
end

describe "mark_content_validation?" do
  it "forbids a manager" do
    expect(described_class.new(user, asset).mark_content_validation?).to be false
  end

  it "forbids an accountant" do
    accountant = create(:user, :accountant, organization: org)
    expect(described_class.new(accountant, asset).show?).to be false
    expect(described_class.new(accountant, asset).mark_content_validation?).to be false
  end

  it "allows an operator traffic manager to mark a client asset" do
    operator = create(:user, :traffic_manager, organization: create(:organization, :operator))
    expect(described_class.new(operator, asset).mark_content_validation?).to be true
  end

  it "forbids an operator manager" do
    operator = create(:user, :manager, organization: create(:organization, :operator))
    expect(described_class.new(operator, asset).show?).to be true
    expect(described_class.new(operator, asset).mark_content_validation?).to be false
  end
end

describe "Scope for a traffic manager" do
  it "returns own assets and foreign network assets" do
    traffic_manager = create(:user, :traffic_manager, organization: org)
    own = create(:media_asset, :with_png_file, organization: org)
    shared = create(:media_asset, :with_png_file, :network_neutral, organization: other_org)
    private_foreign = create(:media_asset, :with_png_file, organization: other_org, visibility: :organization)

    resolved = described_class::Scope.new(traffic_manager, MediaAsset).resolve

    expect(resolved).to include(own, shared)
    expect(resolved).not_to include(private_foreign)
  end
end
```

- [ ] **Step 2: Run the spec and confirm it fails**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/policies/media_asset_policy_spec.rb`

Expected: FAIL on `mark_content_validation?` and on traffic-manager index (today `lk_content_access?` excludes that role).

- [ ] **Step 3: Implement**

Replace `lk_content_access?` uses inside `MediaAssetPolicy` only. Do not edit `ApplicationPolicy`.

```ruby
def index? = media_library_access?

def show?
  return false unless media_library_access?
  return true if operator?
  return true if in_organization?

  record.visibility_network?
end

def mark_content_validation?
  traffic_manager? && operator_or_in_organization?
end

def revoke_content_validation? = mark_content_validation?
```

Scope:

```ruby
def resolve
  return scope.none unless user
  return scope.all if operator?
  return scope.none unless media_library_access?

  scope.where(organization_id: user.organization_id)
    .or(scope.where(visibility: MediaAsset.visibilities[:network]))
end
```

Private on both the policy and the scope class:

```ruby
def media_library_access?
  return false unless user
  return true if operator?

  user.manager? || user.administrator? || user.traffic_manager?
end
```

The policy class already has `manager?` / `administrator?` / `traffic_manager?` helpers. Use those in the policy. The scope class does not; call the predicates on `user` as above. Define `media_library_access?` separately in `Scope`, do not call the policy instance from the scope.

- [ ] **Step 4: Run the spec**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/policies/media_asset_policy_spec.rb`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/policies/media_asset_policy.rb spec/policies/media_asset_policy_spec.rb
git commit -m "feat: let traffic managers open and validate media"
```

---

### Task 7: Service theme upload no longer joins the folder

**Files:**
- Modify: `app/domain/service_themes/add_clip.rb`
- Create: `app/domain/service_themes/place_validated_clip.rb`
- Modify: `app/controllers/admin/service_theme_clips_controller.rb`
- Modify: `config/routes.rb` (admin `service_themes` clips collection `post :place`)
- Modify: `spec/domain/service_themes/add_clip_spec.rb`
- Test: `spec/domain/service_themes/place_validated_clip_spec.rb`

**Interfaces:**
- Consumes: `MediaAsset#content_validated?`, `RotationItem` validation from Task 4
- Produces: `ServiceThemes::AddClip.call` still returns the new service asset and does not create a rotation item or enqueue regen. `ServiceThemes::PlaceValidatedClip.call(theme:, role:, media_asset:)` creates one rotation item and then calls `Playlists::EnqueueRegen.from_rotation`. Raises `ArgumentError` for an unknown role. Raises `MediaAssets::Error` with `I18n.t("media_assets.content_validation.not_validated")` when the asset is unmarked, not `content_type_service`, or not owned by the theme organization. `POST place_admin_service_theme_clips_path` redirects to the theme. Upload redirects to `admin_media_asset_path`.

- [ ] **Step 1: Rewrite the add-clip spec and write the place spec**

Replace the example `"stores a service clip in the theme folder and regenerates using portraits (AE2)"` so it expects a new asset, zero new rotation items, and no `Playlists::GenerateForDateJob`. Keep the attribute expectations (`content_type: "service"`, `visibility: "network"`, organization, uploaded_by).

`spec/domain/service_themes/place_validated_clip_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe ServiceThemes::PlaceValidatedClip do
  include ActiveJob::TestHelper

  let(:operator) { create(:organization, :operator) }
  let(:user) { create(:user, :traffic_manager, organization: operator) }
  let(:theme) { ServiceThemes::Create.call(organization: operator, name: "Салон красоты") }
  let(:asset) do
    create(:media_asset, :ready, :with_png_file, :content_validated,
      organization: operator, content_type: "service", visibility: "network", uploaded_by: user)
  end

  it "adds a validated service clip and regenerates playlists" do
    station = create(:station, location: create(:location, time_zone: "UTC"), offline_cache_hours: 24)
    screen = create(:screen, station: station)
    portrait = create(:broadcast_portrait, :for_screen, screen: screen)
    create(:broadcast_portrait_block, :service_welcome, broadcast_portrait: portrait, rotation: theme.welcome_rotation)

    travel_to(Time.utc(2026, 9, 28, 12, 0, 0)) do
      expect {
        described_class.call(theme: theme, role: :welcome, media_asset: asset)
      }.to change(RotationItem, :count).by(1)
        .and have_enqueued_job(Playlists::GenerateForDateJob).with(station.id, "2026-09-28")
    end
  end

  it "rejects an unmarked service clip" do
    unmarked = create(:media_asset, :ready, :with_png_file, organization: operator, content_type: "service", visibility: "network")

    expect {
      described_class.call(theme: theme, role: :welcome, media_asset: unmarked)
    }.to raise_error(MediaAssets::Error, I18n.t("media_assets.content_validation.not_validated"))
  end

  it "rejects an unknown role" do
    expect {
      described_class.call(theme: theme, role: :nope, media_asset: asset)
    }.to raise_error(ArgumentError)
  end
end
```

- [ ] **Step 2: Run both specs and confirm they fail**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/service_themes/add_clip_spec.rb spec/domain/service_themes/place_validated_clip_spec.rb`

Expected: add-clip FAIL because a rotation item is still created. Place spec FAIL because the class is missing.

- [ ] **Step 3: Implement**

In `AddClip#call`, delete `rotation.rotation_items.create!` and both `Playlists::EnqueueRegen.from_rotation` calls. Still `asset.save!` inside the transaction. Still rescue storage errors and enqueue `ProcessMediaMetadataJob`. Return `asset`. `rotation_for` is only needed to reject an unknown role before save:

```ruby
def call
  raise ArgumentError, "unknown service theme role #{role.inspect}" if theme.rotation_for(role).blank?

  asset = nil
  ServiceTheme.transaction do
    asset = build_asset
    asset.save!
  end
  asset
rescue StandardError => e
  raise unless asset&.persisted? && Media::StorageErrors.network?(e)

  ProcessMediaMetadataJob.perform_later(asset.id)
  asset
end
```

`app/domain/service_themes/place_validated_clip.rb`:

```ruby
# frozen_string_literal: true

module ServiceThemes
  class PlaceValidatedClip < BaseService
    def initialize(theme:, role:, media_asset:)
      @theme = theme
      @role = role
      @media_asset = media_asset
    end

    def call
      rotation = theme.rotation_for(role)
      raise ArgumentError, "unknown service theme role #{role.inspect}" if rotation.blank?
      raise MediaAssets::Error, I18n.t("media_assets.content_validation.not_validated") unless placeable?

      item = rotation.rotation_items.create!(
        media_asset: media_asset,
        display_duration_seconds: media_asset.duration_seconds
      )
      Playlists::EnqueueRegen.from_rotation(rotation)
      item
    end

    private

    attr_reader :theme, :role, :media_asset

    def placeable?
      media_asset.content_validated? &&
        media_asset.content_type_service? &&
        media_asset.organization_id == theme.organization_id
    end
  end
end
```

Routes, inside `namespace :admin` replace the clips line:

```ruby
resources :service_themes do
  resources :clips, only: :create, controller: "service_theme_clips" do
    collection do
      post :place
    end
  end
end
```

`Admin::ServiceThemeClipsController#create` redirects to the asset show page:

```ruby
asset = ServiceThemes::AddClip.call(
  theme: theme,
  role: params[:role],
  file: clip_file,
  uploaded_by: Current.user
)
redirect_to admin_media_asset_path(asset), notice: t("admin.service_themes.clip_uploaded"),
  status: :see_other
```

Add `#place`:

```ruby
def place
  theme = ServiceTheme.find(params[:service_theme_id])
  asset = MediaAsset.find(params[:media_asset_id])
  ServiceThemes::PlaceValidatedClip.call(theme: theme, role: params[:role], media_asset: asset)
  redirect_to admin_service_theme_path(theme), notice: t("admin.service_themes.clip_placed"),
    status: :see_other
rescue ArgumentError
  redirect_to admin_service_theme_path(theme), alert: t("admin.service_themes.unknown_role"),
    status: :see_other
rescue MediaAssets::Error, ActiveRecord::RecordInvalid => e
  message = e.is_a?(ActiveRecord::RecordInvalid) ? e.record.errors.full_messages.to_sentence : e.message
  redirect_to admin_service_theme_path(theme), alert: message, status: :see_other
end
```

Locale `admin.service_themes.clip_placed`: ru `Ролик добавлен в папку`, en `Clip added to the folder`.

Update `spec/requests/admin/service_themes_spec.rb` examples that upload a clip and expect it in the folder. They should expect a redirect to `admin_media_asset_path` and no rotation item. Add a request example for `post place_admin_service_theme_clips_path(theme), params: { role: "welcome", media_asset_id: asset.id }` with a validated service asset, expecting the item on `theme.welcome_rotation`.

- [ ] **Step 4: Run the service-theme specs**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/domain/service_themes spec/requests/admin/service_themes_spec.rb`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/domain/service_themes app/controllers/admin/service_theme_clips_controller.rb config/routes.rb spec/domain/service_themes spec/requests/admin/service_themes_spec.rb config/locales/mediateca.ru.yml config/locales/mediateca.en.yml
git commit -m "feat: add service clips to a theme only after validation"
```

---

### Task 8: Cabinet show page, player markup, and mark actions

**Files:**
- Modify: `config/routes.rb`
- Modify: `app/controllers/media_assets_controller.rb`
- Create: `app/views/media_assets/show.html.slim`
- Create: `app/views/media_assets/_player.html.slim`
- Modify: `app/helpers/media_assets_helper.rb`
- Modify: `app/components/media/media_asset_row_component.html.slim`
- Modify: `app/views/media_assets/index.html.slim`
- Modify: `spec/helpers/media_assets_helper_spec.rb`
- Test: `spec/requests/media_assets_spec.rb`

**Interfaces:**
- Consumes: `MediaAssets::MarkContentValidated`, `MediaAssets::RevokeContentValidation`, `MediaAssetPolicy#mark_content_validation?`
- Produces: `GET /media_assets/:id`. Member `POST mark_content_validation` and `DELETE revoke_content_validation`. Show renders `data-controller="media-asset-player"` and `data-media-asset-player-url-value` pointing at `broadcast_file` for a ready video. Images render the original file. Mark button only when policy allows and the asset is playable (`ready?` and, for video, `broadcast_file` attached).

- [ ] **Step 1: Write the failing request examples**

Add to `spec/requests/media_assets_spec.rb`:

```ruby
describe "GET /media_assets/:id" do
  let(:traffic_manager) { create(:user, :traffic_manager, organization: user.organization) }

  it "plays a ready video from the broadcast file" do
    sign_in_as(user)
    asset = create(:media_asset, :ready, :with_mp4_file, :with_broadcast_ts, organization: user.organization)

    get media_asset_path(asset)

    expect(response).to have_http_status(:success)
    expect(response.body).to include('data-controller="media-asset-player"')
    expect(response.body).to include("source.ts")
    expect(response.body).not_to include(I18n.t("media_assets.content_validation.validated"))
  end

  it "shows an image from the original file" do
    sign_in_as(user)
    asset = create(:media_asset, :ready, :with_png_file, organization: user.organization)

    get media_asset_path(asset)

    expect(response.body).to include("1x1.png")
    expect(response.body).not_to include("media-asset-player")
  end

  it "shows the validator and the mark button to the owning traffic manager" do
    sign_in_as(traffic_manager)
    asset = create(:media_asset, :ready, :with_png_file, :content_validated, organization: user.organization)

    get media_asset_path(asset)

    expect(response.body).to include(asset.content_validated_by.display_name)
    expect(response.body).to include(I18n.t("media_assets.content_validation.validated"))
  end

  it "hides the mark button from a manager" do
    sign_in_as(user)
    asset = create(:media_asset, :ready, :with_png_file, organization: user.organization)

    get media_asset_path(asset)

    expect(response.body).not_to include(mark_content_validation_media_asset_path(asset))
  end
end

describe "POST mark_content_validation" do
  it "marks the asset for a traffic manager and redirects back" do
    traffic_manager = create(:user, :traffic_manager, organization: user.organization)
    sign_in_as(traffic_manager)
    asset = create(:media_asset, :ready, :with_png_file, organization: user.organization)

    post mark_content_validation_media_asset_path(asset)

    expect(response).to redirect_to(media_asset_path(asset))
    expect(asset.reload.content_validated_by).to eq(traffic_manager)
  end

  it "forbids a manager" do
    sign_in_as(user)
    asset = create(:media_asset, :ready, :with_png_file, organization: user.organization)

    post mark_content_validation_media_asset_path(asset)

    expect(response).to redirect_to(rails_health_check_path)
    expect(asset.reload.content_validated?).to be false
  end
end
```

`ApplicationController#user_not_authorized` calls `redirect_back(fallback_location: rails_health_check_path)`. A request spec POST has no referer, so the fallback is `rails_health_check_path`.

Update `spec/helpers/media_assets_helper_spec.rb` `#media_asset_source_link` so the href is the show path, not `disposition=attachment`:

```ruby
expect(html).to include(media_asset_path(asset))
expect(html).not_to include("disposition=attachment")
```

- [ ] **Step 2: Run the request spec and confirm it fails**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/requests/media_assets_spec.rb spec/helpers/media_assets_helper_spec.rb`

Expected: FAIL routing error for `media_asset_path`.

- [ ] **Step 3: Implement routes, controller, views, helper, library column**

`config/routes.rb` cabinet resources:

```ruby
resources :media_assets, only: %i[index create update show] do
  member do
    post :mark_content_validation
    delete :revoke_content_validation
  end
end
```

`MediaAssetsController`:

```ruby
before_action :set_media_asset, only: %i[show update mark_content_validation revoke_content_validation]

def show
  authorize @media_asset
end

def mark_content_validation
  authorize @media_asset
  MediaAssets::MarkContentValidated.call(media_asset: @media_asset, user: Current.user)
  redirect_to media_asset_path(@media_asset), notice: t("media_assets.content_validation.marked"), status: :see_other
rescue MediaAssets::Error => e
  redirect_to media_asset_path(@media_asset), alert: e.message, status: :see_other
end

def revoke_content_validation
  authorize @media_asset
  MediaAssets::RevokeContentValidation.call(media_asset: @media_asset)
  redirect_to media_asset_path(@media_asset), notice: t("media_assets.content_validation.revoked"), status: :see_other
end
```

`set_media_asset` already uses `policy_scope`. `show` must eager-load `content_validated_by` (`policy_scope(MediaAsset).includes(:content_validated_by)...` only on show, or `includes` in `set_media_asset`).

`app/views/media_assets/_player.html.slim`:

```slim
- if media_asset.video?
  - if media_asset.broadcast_file.attached?
    video.w-full.max-w-3xl controls="controls" data-controller="media-asset-player" data-media-asset-player-url-value=url_for(media_asset.broadcast_file)
  - else
    p.text-sm.text-base-content/70 = t("media_assets.show.video_not_ready")
- elsif media_asset.audio? && media_asset.file.attached?
  audio.w-full controls="controls" src=url_for(media_asset.file)
- elsif media_asset.image? && media_asset.file.attached?
  = image_tag url_for(media_asset.file), class: "max-w-3xl", alt: media_asset.file.filename.to_s
- elsif media_asset.document? && media_asset.file.attached?
  iframe.w-full.max-w-3xl.h-96 src=url_for(media_asset.file)
- elsif media_asset.file.attached?
  = link_to media_asset.file.filename.to_s, rails_blob_path(media_asset.file, disposition: :attachment), class: "link link-hover"
```

`app/views/media_assets/show.html.slim`:

```slim
- content_for :title, @media_asset.file.attached? ? @media_asset.file.filename.to_s : MediaAsset.model_name.human

.mx-auto.w-full.max-w-6xl.flex.flex-col.gap-6
  = render "shared/page_header", title: (@media_asset.file.attached? ? @media_asset.file.filename.to_s : MediaAsset.model_name.human)
  .card.bg-base-100.border.border-base-300.shadow-sm
    .card-body.gap-4
      = render "media_assets/player", media_asset: @media_asset
      - if @media_asset.file.attached?
        = link_to t("media_assets.show.download"), rails_blob_path(@media_asset.file, disposition: :attachment), class: "link link-hover"
  .card.bg-base-100.border.border-base-300.shadow-sm
    .card-body.gap-3
      - if @media_asset.content_validated?
        span.badge.badge-success = t("media_assets.content_validation.validated")
        p.text-sm = t("media_assets.content_validation.validated_by", name: @media_asset.content_validated_by.display_name, time: l(@media_asset.content_validated_at, format: :long))
      - else
        span.badge.badge-warning = t("media_assets.content_validation.not_validated")
      - if policy(@media_asset).mark_content_validation?
        - if @media_asset.content_validated?
          = button_to t("media_assets.content_validation.revoke"), revoke_content_validation_media_asset_path(@media_asset), method: :delete, class: "btn btn-warning", form: { data: { turbo_confirm: t("media_assets.content_validation.confirm_revoke") } }
        - elsif playable_for_validation?(@media_asset)
          = button_to t("media_assets.content_validation.mark"), mark_content_validation_media_asset_path(@media_asset), class: "btn btn-primary"
  = link_to t("media_assets.show.back"), media_assets_path, class: "link link-hover"
```

Add locale keys `media_assets.show.download`, `media_assets.show.back`, `media_assets.show.video_not_ready`, `media_assets.content_validation.mark` (`Содержимое проверено` / `Content validated`), `media_assets.content_validation.revoke` (`Снять отметку` / `Clear validation`). `media_assets.index.columns.content_validation` (`Проверка` / `Validation`).

Helper:

```ruby
def media_asset_source_link(media_asset)
  return "—" unless media_asset.file.attached?

  link_to(media_asset.file.filename.to_s, media_asset_path(media_asset), class: "link link-hover")
end

def playable_for_validation?(media_asset)
  return false unless media_asset.ready?
  return media_asset.broadcast_file.attached? if media_asset.video?

  true
end

def media_asset_validation_label(media_asset)
  key = media_asset.content_validated? ? "validated" : "not_validated"
  I18n.t("media_assets.content_validation.#{key}")
end
```

`playable_for_validation?` is called from the Slim show via the helper. Include `MediaAssetsHelper` is automatic.

Library table: add a `th` in `index.html.slim` and a `td` in `media_asset_row_component.html.slim`:

```slim
td
  span.badge class=(media_asset.content_validated? ? "badge-success" : "badge-ghost") = helpers.media_asset_validation_label(media_asset)
```

The row component uses `helpers.` for other calls. Match that.

- [ ] **Step 4: Run the cabinet specs**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/requests/media_assets_spec.rb spec/helpers/media_assets_helper_spec.rb spec/components/media/media_asset_row_component_spec.rb`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add config/routes.rb app/controllers/media_assets_controller.rb app/views/media_assets app/helpers/media_assets_helper.rb app/components/media/media_asset_row_component.html.slim spec/requests/media_assets_spec.rb spec/helpers/media_assets_helper_spec.rb config/locales/mediateca.ru.yml config/locales/mediateca.en.yml
git commit -m "feat: play media and validate it from the cabinet"
```

---

### Task 9: Admin show, index column, and theme folder picker

**Files:**
- Modify: `config/routes.rb` (admin `media_assets` member routes)
- Modify: `app/controllers/admin/media_assets_controller.rb`
- Modify: `app/views/admin/media_assets/show.html.erb`
- Modify: `app/views/admin/media_assets/index.html.erb`
- Modify: `app/views/admin/service_themes/show.html.erb`
- Test: `spec/requests/admin/media_assets_spec.rb`

**Interfaces:**
- Consumes: Task 8 player contract (`data-controller="media-asset-player"`), `PlaceValidatedClip`, mark services
- Produces: admin member `POST mark_content_validation` and `DELETE revoke_content_validation`. Buttons render only when `Current.user.traffic_manager?`. Non-traffic-manager POST redirects to the show page with the forbidden alert and does not change columns. Index has a validation column. Each service-theme folder renders `form_with url: place_admin_service_theme_clips_path(@service_theme)` with `role` and `media_asset_id` options limited to validated service assets of the theme organization that are not already in that rotation.

- [ ] **Step 1: Write the failing admin request examples**

Add to `spec/requests/admin/media_assets_spec.rb`:

```ruby
it "renders a mpegts player for a ready video" do
  media_asset = create(:media_asset, :ready, :with_mp4_file, :with_broadcast_ts, organization: client_org)

  get admin_media_asset_path(media_asset)

  expect(response.body).to include('data-controller="media-asset-player"')
  expect(response.body).to include("source.ts")
end

it "lets an operator traffic manager mark a client asset" do
  sign_in_as(create(:user, :traffic_manager, organization: operator_org))
  media_asset = create(:media_asset, :ready, :with_png_file, organization: client_org)

  post mark_content_validation_admin_media_asset_path(media_asset)

  expect(response).to redirect_to(admin_media_asset_path(media_asset))
  expect(media_asset.reload.content_validated?).to be true
end

it "refuses the mark from an operator manager" do
  media_asset = create(:media_asset, :ready, :with_png_file, organization: client_org)

  post mark_content_validation_admin_media_asset_path(media_asset)

  expect(response).to redirect_to(admin_media_asset_path(media_asset))
  expect(flash[:alert]).to eq(I18n.t("media_assets.content_validation.forbidden"))
  expect(media_asset.reload.content_validated?).to be false
end
```

The existing `before { sign_in_as(operator) }` signs in a manager. The traffic-manager example calls `sign_in_as` again.

- [ ] **Step 2: Run the spec and confirm it fails**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/requests/admin/media_assets_spec.rb`

Expected: FAIL, route missing and show body has no player.

- [ ] **Step 3: Implement**

Admin routes:

```ruby
resources :media_assets do
  member do
    post :mark_content_validation
    delete :revoke_content_validation
  end
end
```

`show` loads `@media_asset = MediaAsset.with_attached_file.with_attached_preview.with_attached_broadcast_file.includes(:content_validated_by).find(params[:id])`.

```ruby
def mark_content_validation
  media_asset = MediaAsset.find(params[:id])
  unless Current.user.traffic_manager?
    redirect_to admin_media_asset_path(media_asset),
      alert: t("media_assets.content_validation.forbidden"), status: :see_other
    return
  end

  MediaAssets::MarkContentValidated.call(media_asset: media_asset, user: Current.user)
  redirect_to admin_media_asset_path(media_asset),
    notice: t("media_assets.content_validation.marked"), status: :see_other
rescue MediaAssets::Error => e
  redirect_to admin_media_asset_path(media_asset), alert: e.message, status: :see_other
end

def revoke_content_validation
  media_asset = MediaAsset.find(params[:id])
  unless Current.user.traffic_manager?
    redirect_to admin_media_asset_path(media_asset),
      alert: t("media_assets.content_validation.forbidden"), status: :see_other
    return
  end

  MediaAssets::RevokeContentValidation.call(media_asset: media_asset)
  redirect_to admin_media_asset_path(media_asset),
    notice: t("media_assets.content_validation.revoked"), status: :see_other
end
```

In `show.html.erb`, above the `<dl>`, add a player block that duplicates `_player.html.slim` with Tailwind classes only (`w-full max-w-3xl`). Video tag:

```erb
<video class="w-full max-w-3xl" controls
       data-controller="media-asset-player"
       data-media-asset-player-url-value="<%= url_for(@media_asset.broadcast_file) %>"></video>
```

Below the dl, if `Current.user.traffic_manager?`, render the status text and `button_to` mark/revoke using `admin_primary_button_class` / `admin_secondary_button_class`. Revoke `data: { turbo_confirm: t("media_assets.content_validation.confirm_revoke") }`.

Index: add a header cell `t("media_assets.content_validation.validated")` is the wrong label for a column. Use `t("media_assets.index.columns.content_validation")`. Cell text is `media_asset_validation_label(asset)`.

Service theme show, under each folder's upload form:

```erb
<%= form_with url: place_admin_service_theme_clips_path(@service_theme), class: "mt-4 flex flex-col gap-2 sm:flex-row sm:items-end" do %>
  <%= hidden_field_tag :role, role %>
  <% choices = validated_service_clips_for(rotation) %>
  <%= select_tag :media_asset_id,
        options_from_collection_for_select(choices, :id, :file_filename),
        include_blank: t("admin.service_themes.place_prompt"),
        class: admin_select_class %>
  <%= submit_tag t("admin.service_themes.place_submit"), class: admin_primary_button_class %>
<% end %>
```

`file_filename` does not exist. Use a label method on `AdminHelper`:

```ruby
def admin_validated_service_clip_options(rotation)
  MediaAsset.content_type_service
    .where(organization_id: rotation.organization_id)
    .where.not(content_validated_at: nil)
    .where.not(content_validated_by_id: nil)
    .where.not(id: rotation.rotation_items.select(:media_asset_id))
    .includes(file_attachment: :blob)
    .filter_map { |asset| [ asset.file.filename.to_s, asset.id ] if asset.file.attached? }
end
```

Then `options_for_select(admin_validated_service_clip_options(rotation))`.

Locale: `admin.service_themes.place_prompt` ru `Проверенный ролик`, en `Validated clip`. `place_submit` ru `Добавить в папку`, en `Add to folder`.

- [ ] **Step 4: Run the admin specs**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/requests/admin/media_assets_spec.rb spec/requests/admin/service_themes_spec.rb`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add config/routes.rb app/controllers/admin/media_assets_controller.rb app/views/admin/media_assets app/views/admin/service_themes/show.html.erb app/helpers/admin_helper.rb spec/requests/admin/media_assets_spec.rb config/locales/mediateca.ru.yml config/locales/mediateca.en.yml
git commit -m "feat: play and validate media in operator admin"
```

---

### Task 10: Picker labels

**Files:**
- Modify: `app/helpers/media_assets_helper.rb`
- Modify: `app/helpers/advertising_orders_helper.rb`
- Modify: `app/views/admin/rotation_items/_form.html.erb`
- Modify: `spec/helpers/media_assets_helper_spec.rb`
- Test: `spec/helpers/advertising_orders_helper_spec.rb` if it exists; otherwise add the example to the existing advertising helper spec. If none exists, create `spec/helpers/advertising_orders_helper_spec.rb` with only the new example.

**Interfaces:**
- Consumes: `media_asset_validation_label`
- Produces: `media_asset_select_label` and `advertising_clip_option_label` append ` · ` plus the validation label. Admin rotation-item select shows filename and that label, not the bare id.

- [ ] **Step 1: Update the helper specs**

`media_asset_select_label` example becomes:

```ruby
expect(helper.media_asset_select_label(asset)).to eq(
  "source.mp4 · source.ts · #{I18n.t('media_assets.content_validation.not_validated')}"
)
```

Add an example with `:content_validated` expecting `content_validation.validated`.

Advertising helper:

```ruby
it "appends the validation label" do
  asset = create(:media_asset, :ready, :with_png_file, duration_seconds: 10)
  expect(helper.advertising_clip_option_label(asset)).to eq(
    "#{helper.advertising_clip_title(asset)} (10s) · #{I18n.t('media_assets.content_validation.not_validated')}"
  )
end
```

Read `advertising_clip_title` before writing the expectation so the string matches the helper. If the title is the filename, the expectation is `"1x1.png (10s) · ..."`.

- [ ] **Step 2: Run the helper specs and confirm they fail**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/helpers/media_assets_helper_spec.rb spec/helpers/advertising_orders_helper_spec.rb`

Expected: FAIL, label missing the validation suffix.

- [ ] **Step 3: Implement**

```ruby
def media_asset_select_label(media_asset)
  source = media_asset.file.attached? ? media_asset.file.filename.to_s : "—"
  "#{source} · #{media_asset_broadcast_label(media_asset)} · #{media_asset_validation_label(media_asset)}"
end
```

```ruby
def advertising_clip_option_label(asset)
  name = advertising_clip_title(asset)
  "#{name} (#{asset.duration_seconds}s) · #{media_asset_validation_label(asset)}"
end
```

Admin form `app/views/admin/rotation_items/_form.html.erb` replace the `collection_select` that uses `:id, :id`:

```erb
<%= f.collection_select :media_asset_id,
      MediaAsset.with_attached_file.order(created_at: :desc),
      :id,
      ->(asset) { "#{asset.file.attached? ? asset.file.filename.to_s : asset.id} · #{media_asset_validation_label(asset)}" },
      { include_blank: true },
      class: admin_select_class %>
```

- [ ] **Step 4: Run the helper specs**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/helpers/media_assets_helper_spec.rb spec/helpers/advertising_orders_helper_spec.rb spec/requests/admin/rotation_items_spec.rb`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/helpers/media_assets_helper.rb app/helpers/advertising_orders_helper.rb app/views/admin/rotation_items/_form.html.erb spec/helpers
git commit -m "feat: show content validation in clip pickers"
```

---

### Task 11: MPEG-TS player

**Files:**
- Modify: `config/importmap.rb`
- Create: `app/javascript/controllers/media_asset_player_controller.js`
- Modify: `app/javascript/admin.js`
- Test: `spec/requests/media_assets_spec.rb` (already asserts the data attributes). Add a JS-free request assertion that the importmap pin exists by reading `config/importmap.rb` in review, not in RSpec. Optional system spec is out of scope; do not add a browser driver for mpegts.

**Interfaces:**
- Consumes: `data-media-asset-player-url-value` from Tasks 8 and 9
- Produces: Stimulus controller `media-asset-player`. Cabinet loads it via `import "controllers"` eager load. Admin registers it explicitly because admin does not eager-load cabinet controllers. The controller creates an mpegts.js MSE player for a non-live asset, attaches `this.element` (the `<video>`), calls `load()`, and `destroy()`s the player in `disconnect()`.

- [ ] **Step 1: Pin the library and write the controller**

`config/importmap.rb`:

```ruby
pin "mpegts.js", to: "https://cdn.jsdelivr.net/npm/mpegts.js@1.8.0/dist/mpegts.js"
```

If that URL is not ESM and the import fails in the browser console, switch the pin to `https://esm.sh/mpegts.js@1.8.0` and keep the import name `mpegts.js`.

`app/javascript/controllers/media_asset_player_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"
import mpegts from "mpegts.js"

export default class extends Controller {
  static values = { url: String }

  connect() {
    if (!this.urlValue || !mpegts.isSupported()) return

    this.player = mpegts.createPlayer({
      type: "mse",
      isLive: false,
      url: this.urlValue
    })
    this.player.attachMediaElement(this.element)
    this.player.load()
  }

  disconnect() {
    if (!this.player) return

    this.player.destroy()
    this.player = null
  }
}
```

`app/javascript/admin.js` add:

```javascript
import MediaAssetPlayerController from "controllers/media_asset_player_controller"

application.register("media-asset-player", MediaAssetPlayerController)
```

Cabinet `app/javascript/controllers/index.js` eager-loads this file. Do not register it a second time in the cabinet bundle.

- [ ] **Step 2: Confirm the request specs still pass**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/requests/media_assets_spec.rb spec/requests/admin/media_assets_spec.rb`

Expected: PASS. The data attributes are unchanged.

- [ ] **Step 3: Commit**

```bash
git add config/importmap.rb app/javascript/controllers/media_asset_player_controller.js app/javascript/admin.js
git commit -m "feat: play broadcast MPEG-TS in the media show pages"
```

---

### Task 12: Suite check for rotation-item fallout

**Files:**
- Modify: any spec that creates a non-draft `RotationItem` with an explicit unmarked `media_asset` and starts failing.

**Interfaces:**
- Consumes: Task 4 validation and the `:content_validated` factory trait
- Produces: a green suite for the files below. This task does not weaken the validation.

- [ ] **Step 1: Run the rotation and playlist specs**

Run: `docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/models/rotation_item_spec.rb spec/models/rotation_spec.rb spec/domain/rotations spec/domain/playlists spec/domain/agent spec/requests/api spec/requests/rotations spec/requests/media_plans_spec.rb spec/requests/admin/rotation_items_spec.rb spec/system/rotation_reorder_spec.rb`

Expected: PASS, or FAIL with `содержимое не проверено трафик-менеджером` on a factory create that passes an explicit asset.

- [ ] **Step 2: Fix only those failures**

`create(:rotation_item)` without an explicit asset is already validated by the factory from Task 4. For a failure, add `:content_validated` to that spec's media asset. Do not delete the validation. Do not mark assets inside `CreateOrder` examples that are meant to stay unmarked drafts.

- [ ] **Step 3: Re-run the same command**

Expected: PASS

- [ ] **Step 4: Commit if anything changed**

```bash
git add spec
git commit -m "test: mark fixtures that enter non-draft rotations"
```

If nothing changed, skip the commit.
