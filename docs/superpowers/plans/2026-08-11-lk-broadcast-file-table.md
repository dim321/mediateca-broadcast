# LK Broadcast File Table Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show source and broadcast (`.ts`) download links side-by-side in the cabinet media library table and everywhere filenames appear (rotations list + add-media select).

**Architecture:** Shared `MediaAssetsHelper` owns link/placeholder rules. Media library switches from card grid to a daisyUI `table.table` via `Media::MediaAssetRowComponent`. Rotations reuse the helper. No job/model pipeline changes; keep `dom_id(..., :card)` for Turbo Stream replace.

**Tech Stack:** Rails, ViewComponent, Active Storage, Hotwire Turbo Streams, daisyUI 5 / Tailwind 4, RSpec, Slim.

**Spec:** `docs/superpowers/specs/2026-08-11-lk-broadcast-file-table-design.md`

## Global Constraints

- UI-only: do not change `ProcessMediaMetadataJob`, `MediaTranscodeJob`, or Active Storage attachment names (`file`, `broadcast_file`, `preview`).
- Keep Turbo replace target `dom_id(media_asset, :card)`.
- Broadcast placeholder: non-video → `N/A`; video without `.ts` and `pending`/`processing` → `Processing…`; otherwise humanized `processing_status`.
- Downloads use `rails_blob_path(..., disposition: :attachment)`.
- Prefer single quotes in Ruby; Slim + daisyUI classes; English i18n in `mediateca.en.yml`.
- TDD: failing test → implement → pass → commit per task.

## File map

| File | Responsibility |
|------|----------------|
| `app/helpers/media_assets_helper.rb` | Source link, broadcast cell/label, select label |
| `spec/helpers/media_assets_helper_spec.rb` | Unit coverage for helper rules |
| `config/locales/mediateca.en.yml` | Column headers + placeholder strings |
| `app/components/media/media_asset_row_component.rb` | Row status badge + attrs |
| `app/components/media/media_asset_row_component.html.slim` | `<tr>` columns |
| `app/views/media_assets/_media_asset.html.slim` | Turbo frame + row component |
| `app/views/media_assets/index.html.slim` | Table shell |
| `app/controllers/media_assets_controller.rb` | Eager-load `broadcast_file` |
| `app/components/rotations/rotation_item_component.html.slim` | Source + broadcast fields |
| `app/views/rotations/show.html.slim` | Select label via helper |
| `app/controllers/rotations_controller.rb` | Eager-load `broadcast_file` |
| Delete `media_asset_card_component.*` | Replaced by row component |
| `spec/requests/media_assets_spec.rb` | Table + N/A / links smoke |
| `spec/factories/media_assets.rb` | Optional video/broadcast traits for specs |

---

### Task 1: MediaAssetsHelper + i18n

**Files:**
- Create: `app/helpers/media_assets_helper.rb`
- Create: `spec/helpers/media_assets_helper_spec.rb`
- Modify: `config/locales/mediateca.en.yml`
- Modify: `spec/factories/media_assets.rb` (video + broadcast traits)

**Interfaces:**
- Produces:
  - `media_asset_source_link(media_asset)` → `ActiveSupport::SafeBuffer` (link) or `"—"`
  - `media_asset_broadcast_cell(media_asset)` → `ActiveSupport::SafeBuffer` (link) or plain placeholder `String`
  - `media_asset_broadcast_label(media_asset)` → `String` (filename or placeholder; no HTML)
  - `media_asset_select_label(media_asset)` → `String` `"#{source} · #{broadcast_label}"`
  - `media_asset_broadcast_placeholder(media_asset)` → `String`

- [ ] **Step 1: Add i18n keys**

In `config/locales/mediateca.en.yml` under `media_assets.index`, add:

```yaml
      columns:
        preview: Preview
        source: Source
        broadcast: Broadcast (.ts)
        status: Status
        duration: Duration
        content_type: Content type
        visibility: Availability
      broadcast_processing: Processing…
      broadcast_na: N/A
      source_label: Source
      broadcast_label: Broadcast
```

- [ ] **Step 2: Add factory traits**

Append to `spec/factories/media_assets.rb` inside the factory:

```ruby
    trait :with_mp4_file do
      content_kind { "video" }
      after(:build) do |record|
        record.file.attach(
          io: StringIO.new("fake-mp4-bytes"),
          filename: "source.mp4",
          content_type: "video/mp4"
        )
      end
    end

    trait :with_broadcast_ts do
      after(:build) do |record|
        path = Rails.root.join("spec/fixtures/files/broadcast.ts")
        record.broadcast_file.attach(
          io: File.open(path),
          filename: "source.ts",
          content_type: "video/mp2t"
        )
      end
    end
```

- [ ] **Step 3: Write the failing helper spec**

Create `spec/helpers/media_assets_helper_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe MediaAssetsHelper, type: :helper do
  let(:organization) { create(:organization) }
  let(:user) { create(:user, organization: organization) }

  describe "#media_asset_broadcast_placeholder" do
    it "returns N/A for non-video" do
      asset = create(:media_asset, :with_png_file, :ready, organization: organization, uploaded_by: user)
      expect(helper.media_asset_broadcast_placeholder(asset)).to eq(I18n.t("media_assets.index.broadcast_na"))
    end

    it "returns Processing… for video without broadcast_file while processing" do
      asset = create(:media_asset, :with_mp4_file, organization: organization, uploaded_by: user, processing_status: "processing")
      expect(helper.media_asset_broadcast_placeholder(asset)).to eq(I18n.t("media_assets.index.broadcast_processing"))
    end

    it "returns humanized status for failed video without broadcast_file" do
      asset = create(:media_asset, :with_mp4_file, organization: organization, uploaded_by: user, processing_status: "failed")
      expect(helper.media_asset_broadcast_placeholder(asset)).to eq("Failed")
    end
  end

  describe "#media_asset_broadcast_cell" do
    it "links to broadcast_file when attached" do
      asset = create(:media_asset, :with_mp4_file, :with_broadcast_ts, :ready, organization: organization, uploaded_by: user)
      html = helper.media_asset_broadcast_cell(asset)
      expect(html).to include("source.ts")
      expect(html).to include("disposition=attachment")
    end

    it "shows placeholder text when broadcast_file missing" do
      asset = create(:media_asset, :with_png_file, :ready, organization: organization, uploaded_by: user)
      expect(helper.media_asset_broadcast_cell(asset)).to eq(I18n.t("media_assets.index.broadcast_na"))
    end
  end

  describe "#media_asset_source_link" do
    it "links to the original file" do
      asset = create(:media_asset, :with_png_file, :ready, organization: organization, uploaded_by: user)
      html = helper.media_asset_source_link(asset)
      expect(html).to include("1x1.png")
      expect(html).to include("disposition=attachment")
    end
  end

  describe "#media_asset_select_label" do
    it "joins source filename and broadcast label" do
      asset = create(:media_asset, :with_mp4_file, :with_broadcast_ts, :ready, organization: organization, uploaded_by: user)
      expect(helper.media_asset_select_label(asset)).to eq("source.mp4 · source.ts")
    end

    it "joins source filename and Processing… when video is encoding" do
      asset = create(:media_asset, :with_mp4_file, organization: organization, uploaded_by: user, processing_status: "processing")
      expect(helper.media_asset_select_label(asset)).to eq(
        "source.mp4 · #{I18n.t('media_assets.index.broadcast_processing')}"
      )
    end
  end
end
```

- [ ] **Step 4: Run helper spec to verify it fails**

Run: `bundle exec rspec spec/helpers/media_assets_helper_spec.rb`

Expected: FAIL (uninitialized constant `MediaAssetsHelper` / undefined methods)

- [ ] **Step 5: Implement helper**

Create `app/helpers/media_assets_helper.rb`:

```ruby
# frozen_string_literal: true

module MediaAssetsHelper
  def media_asset_source_link(media_asset)
    return "—" unless media_asset.file.attached?

    link_to(
      media_asset.file.filename.to_s,
      rails_blob_path(media_asset.file, disposition: :attachment),
      class: "link link-hover"
    )
  end

  def media_asset_broadcast_cell(media_asset)
    if media_asset.broadcast_file.attached?
      link_to(
        media_asset.broadcast_file.filename.to_s,
        rails_blob_path(media_asset.broadcast_file, disposition: :attachment),
        class: "link link-hover"
      )
    else
      media_asset_broadcast_placeholder(media_asset)
    end
  end

  def media_asset_broadcast_label(media_asset)
    if media_asset.broadcast_file.attached?
      media_asset.broadcast_file.filename.to_s
    else
      media_asset_broadcast_placeholder(media_asset)
    end
  end

  def media_asset_broadcast_placeholder(media_asset)
    return t("media_assets.index.broadcast_na") unless media_asset.video?

    if media_asset.pending? || media_asset.processing?
      t("media_assets.index.broadcast_processing")
    else
      media_asset.processing_status.to_s.humanize
    end
  end

  def media_asset_select_label(media_asset)
    source = media_asset.file.attached? ? media_asset.file.filename.to_s : "—"
    "#{source} · #{media_asset_broadcast_label(media_asset)}"
  end
end
```

- [ ] **Step 6: Run helper spec to verify it passes**

Run: `bundle exec rspec spec/helpers/media_assets_helper_spec.rb`

Expected: PASS (all examples)

- [ ] **Step 7: Commit**

```bash
git add app/helpers/media_assets_helper.rb \
  spec/helpers/media_assets_helper_spec.rb \
  config/locales/mediateca.en.yml \
  spec/factories/media_assets.rb
git commit -m "$(cat <<'EOF'
feat: add media asset source/broadcast display helpers

Centralize LK link and placeholder rules for original and .ts files.
EOF
)"
```

---

### Task 2: MediaAssetRowComponent + replace card partial

**Files:**
- Create: `app/components/media/media_asset_row_component.rb`
- Create: `app/components/media/media_asset_row_component.html.slim`
- Modify: `app/views/media_assets/_media_asset.html.slim`
- Delete: `app/components/media/media_asset_card_component.rb`
- Delete: `app/components/media/media_asset_card_component.html.slim`
- Create: `spec/components/media/media_asset_row_component_spec.rb`

**Interfaces:**
- Consumes: `MediaAssetsHelper#media_asset_source_link`, `#media_asset_broadcast_cell`
- Produces: `Media::MediaAssetRowComponent.new(media_asset:)` rendering a `<tr>`

- [ ] **Step 1: Write the failing component spec**

Create `spec/components/media/media_asset_row_component_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Media::MediaAssetRowComponent, type: :component do
  let(:organization) { create(:organization) }
  let(:user) { create(:user, organization: organization) }

  it "renders source and broadcast links for a ready video" do
    asset = create(:media_asset, :with_mp4_file, :with_broadcast_ts, :ready,
                   organization: organization, uploaded_by: user,
                   content_type: "own", visibility: "organization", duration_seconds: 12)

    render_inline(described_class.new(media_asset: asset))

    expect(page).to have_link("source.mp4")
    expect(page).to have_link("source.ts")
    expect(page).to have_content("Ready")
    expect(page).to have_content("12s")
    expect(page).to have_content(I18n.t("media_assets.index.content_types.own"))
    expect(page).to have_content(I18n.t("media_assets.index.visibilities.organization"))
  end

  it "renders N/A broadcast cell for an image" do
    asset = create(:media_asset, :with_png_file, :ready, organization: organization, uploaded_by: user)
    render_inline(described_class.new(media_asset: asset))
    expect(page).to have_content(I18n.t("media_assets.index.broadcast_na"))
    expect(page).not_to have_link(href: /broadcast/)
  end
end
```

- [ ] **Step 2: Run component spec to verify it fails**

Run: `bundle exec rspec spec/components/media/media_asset_row_component_spec.rb`

Expected: FAIL (`uninitialized constant Media::MediaAssetRowComponent`)

- [ ] **Step 3: Implement row component**

Create `app/components/media/media_asset_row_component.rb`:

```ruby
# frozen_string_literal: true

module Media
  class MediaAssetRowComponent < ViewComponent::Base
    def initialize(media_asset:)
      @media_asset = media_asset
    end

    attr_reader :media_asset

    def status_badge_class
      case media_asset.processing_status
      when "ready" then "badge-success"
      when "failed" then "badge-error"
      when "processing", "pending" then "badge-warning"
      else "badge-ghost"
      end
    end
  end
end
```

Create `app/components/media/media_asset_row_component.html.slim` (root `<tr>` carries Turbo replace id — valid table child, no turbo-frame wrapper):

```slim
tr id=dom_id(media_asset, :card)
  td
    - if media_asset.preview.attached?
      = image_tag url_for(media_asset.preview), class: "w-12 h-12 object-cover rounded-box bg-base-200", alt: ""
    - else
      .w-12.h-12.bg-base-200.rounded-box.flex.items-center.justify-center.text-xs.text-base-content/50
        | …
  td = helpers.media_asset_source_link(media_asset)
  td = helpers.media_asset_broadcast_cell(media_asset)
  td
    span.badge.badge-soft class=status_badge_class = media_asset.processing_status.to_s.humanize
  td
    - if media_asset.duration_seconds.present?
      | #{media_asset.duration_seconds}s
    - else
      | —
  td = t("media_assets.index.content_types.#{media_asset.content_type}")
  td = t("media_assets.index.visibilities.#{media_asset.visibility}")
```

- [ ] **Step 4: Wire partial and delete card component**

Replace `app/views/media_assets/_media_asset.html.slim` with:

```slim
= render Media::MediaAssetRowComponent.new(media_asset: media_asset)
```

Delete:
- `app/components/media/media_asset_card_component.rb`
- `app/components/media/media_asset_card_component.html.slim`

- [ ] **Step 5: Run component spec to verify it passes**

Run: `bundle exec rspec spec/components/media/media_asset_row_component_spec.rb`

Expected: PASS

If `type: :component` / `render_inline` / `page` are missing, add to `spec/rails_helper.rb` inside `RSpec.configure`:

```ruby
  config.include ViewComponent::TestHelpers, type: :component
  config.include ViewComponent::SystemTestHelpers, type: :component
  config.include Capybara::RSpecMatchers, type: :component
```

Then re-run until PASS.

- [ ] **Step 6: Commit**

```bash
git add app/components/media/media_asset_row_component.rb \
  app/components/media/media_asset_row_component.html.slim \
  app/views/media_assets/_media_asset.html.slim \
  spec/components/media/media_asset_row_component_spec.rb \
  spec/rails_helper.rb
git rm -f app/components/media/media_asset_card_component.rb \
  app/components/media/media_asset_card_component.html.slim
git commit -m "$(cat <<'EOF'
feat: replace media asset card with table row component

Render library rows with source and broadcast cells via shared helpers.
EOF
)"
```

---

### Task 3: Media library index table + eager load + request coverage

**Files:**
- Modify: `app/views/media_assets/index.html.slim`
- Modify: `app/controllers/media_assets_controller.rb`
- Modify: `spec/requests/media_assets_spec.rb`

**Interfaces:**
- Consumes: `_media_asset` partial / `Media::MediaAssetRowComponent`
- Produces: HTML table with seven column headers; `#media_assets_table` body listing rows

- [ ] **Step 1: Extend request spec (failing assertions)**

In `spec/requests/media_assets_spec.rb`, inside `describe "GET /"`, add:

```ruby
    it "renders a media table with source and broadcast columns" do
      sign_in_as(user)
      create(:media_asset, :with_mp4_file, :with_broadcast_ts, :ready,
             organization: user.organization, uploaded_by: user)
      create(:media_asset, :with_png_file, :ready,
             organization: user.organization, uploaded_by: user)

      get media_assets_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include(I18n.t("media_assets.index.columns.source"))
      expect(response.body).to include(I18n.t("media_assets.index.columns.broadcast"))
      expect(response.body).to include("source.mp4")
      expect(response.body).to include("source.ts")
      expect(response.body).to include(I18n.t("media_assets.index.broadcast_na"))
      expect(response.body).to include('id="media_assets_table"')
    end
```

- [ ] **Step 2: Run the new example to verify it fails**

Run: `bundle exec rspec spec/requests/media_assets_spec.rb -e "renders a media table"`

Expected: FAIL (missing `media_assets_table` / column headers)

- [ ] **Step 3: Update controller eager loads**

In `app/controllers/media_assets_controller.rb`, change both `@media_assets = ...` assignments (index success path and create failure path) from:

```ruby
policy_scope(MediaAsset).with_attached_file.with_attached_preview.order(created_at: :desc)
```

to:

```ruby
policy_scope(MediaAsset)
  .with_attached_file
  .with_attached_preview
  .with_attached_broadcast_file
  .order(created_at: :desc)
```

- [ ] **Step 4: Replace grid with table in index**

Replace the grid block in `app/views/media_assets/index.html.slim` (the `#media_assets_grid` section) with:

```slim
  .overflow-x-auto
    table.table#media_assets_table
      thead
        tr
          th = t(".columns.preview")
          th = t(".columns.source")
          th = t(".columns.broadcast")
          th = t(".columns.status")
          th = t(".columns.duration")
          th = t(".columns.content_type")
          th = t(".columns.visibility")
      tbody#media_assets_tbody
        - @media_assets.each do |asset|
          = render "media_assets/media_asset", media_asset: asset
```

`MediaAsset#broadcast_card_refresh` and `update.turbo_stream.erb` stay unchanged: replace target remains `dom_id(media_asset, :card)` on the `<tr>` from Task 2.

- [ ] **Step 5: Run request specs**

Run: `bundle exec rspec spec/requests/media_assets_spec.rb`

Expected: PASS (including existing AE8 listing + new table example)

- [ ] **Step 6: Commit**

```bash
git add app/views/media_assets/index.html.slim \
  app/controllers/media_assets_controller.rb \
  spec/requests/media_assets_spec.rb
git commit -m "$(cat <<'EOF'
feat: show media library as table with source and .ts columns

Eager-load broadcast_file and keep Turbo replace targets on table rows.
EOF
)"
```

---

### Task 4: Rotations list + select labels

**Files:**
- Modify: `app/components/rotations/rotation_item_component.html.slim`
- Modify: `app/views/rotations/show.html.slim`
- Modify: `app/controllers/rotations_controller.rb`
- Create: `spec/requests/rotations_media_labels_spec.rb` (or extend an existing rotations request spec if present)

**Interfaces:**
- Consumes: `media_asset_source_link`, `media_asset_broadcast_cell`, `media_asset_select_label`

- [ ] **Step 1: Write failing request coverage for rotation show**

Create `spec/requests/rotations_media_labels_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Rotation media labels", type: :request do
  let(:user) { create(:user) }
  let(:rotation) { create(:rotation, organization: user.organization) }

  before { sign_in_as(user) }

  it "shows source and broadcast links for rotation items" do
    asset = create(:media_asset, :with_mp4_file, :with_broadcast_ts, :ready,
                   organization: user.organization, uploaded_by: user)
    create(:rotation_item, rotation: rotation, media_asset: asset)

    get rotation_path(rotation)

    expect(response).to have_http_status(:success)
    expect(response.body).to include("source.mp4")
    expect(response.body).to include("source.ts")
  end

  it "uses combined labels in the add-media select" do
    asset = create(:media_asset, :with_mp4_file, :with_broadcast_ts, :ready,
                   organization: user.organization, uploaded_by: user)

    get rotation_path(rotation)

    expect(response.body).to include("source.mp4 · source.ts")
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec rspec spec/requests/rotations_media_labels_spec.rb`

Expected: FAIL on missing `source.ts` / combined select label (item still shows only `file.filename`)

- [ ] **Step 3: Update rotation item component**

Replace `app/components/rotations/rotation_item_component.html.slim` with:

```slim
li.flex.items-center.gap-2.border.border-base-300.rounded-box.p-2.mb-2.bg-base-100.cursor-grab.active:cursor-grabbing[
  data-item-id=item.id
]
  span.text-base-content/50.select-none.pr-1 aria-hidden="true" ⋮⋮
  .flex-1.min-w-0.flex.flex-col.sm:flex-row.sm:items-center.gap-1.sm:gap-3
    .min-w-0
      span.text-xs.text-base-content/60 = t("media_assets.index.source_label")
      .truncate = helpers.media_asset_source_link(item.media_asset)
    .min-w-0
      span.text-xs.text-base-content/60 = t("media_assets.index.broadcast_label")
      .truncate = helpers.media_asset_broadcast_cell(item.media_asset)
  = link_to t("rotations.show.remove_item"),
    rotation_rotation_item_path(rotation, item),
    data: { turbo_method: :delete },
    class: "link link-error text-sm shrink-0"
```

- [ ] **Step 4: Update select + eager load**

In `app/views/rotations/show.html.slim`, change the `collection_select` line to:

```slim
          = f.collection_select :media_asset_id, @available_media, :id,
            ->(a) { helpers.media_asset_select_label(a) },
            { prompt: t(".select_media") }, class: "select select-bordered w-full"
```

If `helpers` is unavailable in that Slim context, use:

```slim
          = f.collection_select :media_asset_id, @available_media, :id,
            ->(a) { view_context.media_asset_select_label(a) },
            { prompt: t(".select_media") }, class: "select select-bordered w-full"
```

Or simplest (views already have helpers mixed in):

```slim
          = f.collection_select :media_asset_id, @available_media, :id,
            method(:media_asset_select_label),
            { prompt: t(".select_media") }, class: "select select-bordered w-full"
```

Prefer `method(:media_asset_select_label)`.

In `app/controllers/rotations_controller.rb#show`, change `@available_media` to:

```ruby
    @available_media = policy_scope(MediaAsset).ready
      .with_attached_file
      .with_attached_broadcast_file
      .order(created_at: :desc)
      .where.not(id: @rotation.media_asset_ids)
```

Ensure `@items` / `ordered_items` already includes broadcast attachments (model already eager-loads both in `Rotation#ordered_items`). Confirm; if not, add `.includes(media_asset: [ { file_attachment: :blob }, { broadcast_file_attachment: :blob } ])` where items are loaded.

- [ ] **Step 5: Run rotation label specs + reorder system smoke if quick**

Run: `bundle exec rspec spec/requests/rotations_media_labels_spec.rb spec/system/rotation_reorder_spec.rb`

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add app/components/rotations/rotation_item_component.html.slim \
  app/views/rotations/show.html.slim \
  app/controllers/rotations_controller.rb \
  spec/requests/rotations_media_labels_spec.rb
git commit -m "$(cat <<'EOF'
feat: show source and broadcast files in rotation UI

Reuse media helpers for item rows and add-media select labels.
EOF
)"
```

---

### Task 5: Verification pass

**Files:** none new (run existing suites)

- [ ] **Step 1: Run focused regression suite**

Run:

```bash
bundle exec rspec \
  spec/helpers/media_assets_helper_spec.rb \
  spec/components/media/media_asset_row_component_spec.rb \
  spec/requests/media_assets_spec.rb \
  spec/requests/rotations_media_labels_spec.rb \
  spec/system/media_upload_spec.rb \
  spec/jobs/media_transcode_job_spec.rb
```

Expected: PASS

- [ ] **Step 2: Manual checklist (dev)**

1. Upload an image → table row: source link + `N/A`.
2. Upload a video → while processing: source link + `Processing…`; after ready: source + `.ts` downloadable.
3. Open a rotation with a ready video item → both links; select options show `name.mp4 · name.ts`.
4. Confirm Turbo: after job completes, row updates without full reload (status → Ready, `.ts` appears).

- [ ] **Step 3: Final commit only if Step 2 required fixes**

If fixes were needed, commit them with a message describing the fix. Otherwise stop.

---

## Self-review (plan vs spec)

| Spec requirement | Task |
|------------------|------|
| Shared helper for links/placeholders | Task 1 |
| Table columns: preview, source, `.ts`, status, duration, content type, visibility | Tasks 2–3 |
| Download links for both files | Task 1–3 |
| Placeholder `Processing…` / `N/A` / failed status | Task 1 |
| Everywhere filenames appear (library, rotation item, select) | Tasks 3–4 |
| Keep Turbo `dom_id(..., :card)` | Tasks 2–3 |
| Eager load attachments | Tasks 3–4 |
| No job/pipeline changes | Global constraints |
| Tests for helper + library + rotations | Tasks 1–5 |
