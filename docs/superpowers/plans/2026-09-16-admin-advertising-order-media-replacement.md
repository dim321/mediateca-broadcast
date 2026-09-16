# Admin Advertising Order Media Replacement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Allow operators to replace the media asset of a draft advertising order from the admin edit form.

**Architecture:** Reuse the existing media-asset select and metadata Stimulus controller from the new-order form. Extend the admin update flow only for draft orders, selecting assets from the order organization’s ready catalog; keep the existing grid persistence path unchanged.

**Tech Stack:** Rails 8.1, Slim, Hotwire Stimulus, RSpec request specs, Docker Compose.

## Global Constraints

- Only ready media assets belonging to the advertising order organization are valid.
- Only draft advertising orders expose and accept media replacement.
- Existing grid updates and persistence remain unchanged.
- Admin advertising-order forms use the shared cabinet-styled Slim partial.
- Tests run inside the `web` Docker container with `RAILS_ENV=test`.

---

### Task 1: Add failing request coverage

**Files:**
- Modify: `spec/requests/admin/advertising_orders_spec.rb`

- [ ] **Step 1: Add examples for the draft edit form and update behavior**

Cover these observable behaviors:

```ruby
it "shows ready client media assets on the draft edit form" do
  replacement = create(:media_asset, :ready, :with_png_file, organization: client)
  order = Advertising::CreateOrder.call(
    organization: client, created_by: client_user, media_asset: asset, product_name: "Triumph"
  )

  get edit_admin_advertising_order_path(order)

  expect(response.body).to include("advertising_order_media_asset_id")
  expect(response.body).to include(replacement.file.filename.to_s)
end

it "replaces the draft media asset without changing its grid" do
  replacement = create(:media_asset, :ready, :with_png_file, organization: client)
  order = Advertising::CreateOrder.call(
    organization: client, created_by: client_user, media_asset: asset, product_name: "Triumph"
  )
  fill_order_grid!(order, screen: order_screen, dates: [ Date.new(2026, 6, 3) ])
  original_line_ids = order.advertising_order_lines.pluck(:id)

  patch admin_advertising_order_path(order),
    params: order_params(media_asset_id: replacement.id, dates: [])

  expect(response).to redirect_to(admin_advertising_order_path(order))
  expect(order.reload.media_asset).to eq(replacement)
  expect(order.advertising_order_lines.pluck(:id)).to eq(original_line_ids)
end
```

Also add request examples proving that a foreign organization asset, a non-ready
asset, and an active order cannot change the order’s media asset. Assert the
response is unprocessable for invalid draft input, and assert the edit response
does not contain the media-asset field for an active order.

- [ ] **Step 2: Run the focused request spec and verify RED**

Run:

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/requests/admin/advertising_orders_spec.rb
```

Expected: the new examples fail because the edit form does not render the
select and `update` does not persist `media_asset_id`.

### Task 2: Implement draft-only media replacement

**Files:**
- Modify: `app/controllers/admin/advertising_orders_controller.rb`
- Modify: `app/views/advertising_orders/_form.html.slim`

- [ ] **Step 1: Render the existing media selector for editable drafts**

Change the form condition from “new record only” to “new record or draft
record”. Keep the existing `order-media-asset` controller and metadata targets.
This preserves the current new-order behavior and gives edit forms the same
catalog UI.

- [ ] **Step 2: Load and validate the selected asset server-side**

Keep `@media_assets` scoped to `@form_organization.media_assets.ready.with_attached_file`.
Add `media_asset_id` to update attributes only when `@advertising_order.draft?`.
Resolve the submitted ID through that scoped organization relation; reject an
invalid ID with a model error and render the edit form with status
`unprocessable_content`.

- [ ] **Step 3: Run the focused request spec and verify GREEN**

Run:

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/requests/admin/advertising_orders_spec.rb
```

Expected: all examples in the request spec pass, including the new draft-only
replacement and grid-preservation scenarios.

### Task 3: Quality and regression verification

**Files:**
- Review: `app/javascript/controllers/order_media_asset_controller.js`
- Review: `app/javascript/admin.js`
- Review: `docs/superpowers/specs/2026-09-16-admin-advertising-order-media-replacement-design.md`

- [ ] **Step 1: Run syntax and lint checks**

Run the project’s applicable Ruby/JavaScript checks and confirm no new errors:

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rubocop app/controllers/admin/advertising_orders_controller.rb app/helpers/advertising_orders_helper.rb
```

- [ ] **Step 2: Run the full test suite in Docker**

Run:

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec
```

Expected: exit code `0` and no failures.

- [ ] **Step 3: Inspect the final diff**

Run:

```bash
git diff --check
git status --short
```

Confirm only the requested implementation, tests, and already-created design
documentation are present; do not revert unrelated pre-existing work.
