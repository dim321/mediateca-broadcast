# Admin Advertising Order Show Details Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Display placement, media, and total-show details on the admin advertising-order show page.

**Architecture:** Keep the admin show template declarative and add date-range/interval formatting to `AdvertisingOrdersHelper`. Use the existing order associations and enum translation helper; do not add queries or persistence changes.

**Tech Stack:** Rails 8.1, ERB, Flowbite utility classes, RSpec request specs, Docker Compose.

## Global Constraints

- Admin pages use Flowbite utility classes, not daisyUI classes.
- Dates come from all order line days and are grouped into consecutive ranges.
- Missing values use `admin.crud.none`.
- Tests run inside the `web` container with `RAILS_ENV=test`.

---

### Task 1: Add failing show-page coverage

**Files:**
- Modify: `spec/requests/admin/advertising_orders_spec.rb`

- [ ] **Step 1: Add a request example with a date gap**

Create an order with windows `09:00–12:00`, populate dates
`2026-06-01`, `2026-06-02`, `2026-06-04`, and request the show page. Assert
the response contains:

```ruby
expect(response.body).to include("01.06–02.06, 04.06")
expect(response.body).to include("3")
expect(response.body).to include("09:00–12:00")
expect(response.body).to include(asset.file.filename.to_s)
expect(response.body).to include("10")
expect(response.body).to include(I18n.t("enums.media_asset.content_kind.image"))
expect(response.body).to include(I18n.t("enums.media_asset.content_type.own"))
expect(response.body).to include(order.total_shows.to_s)
```

- [ ] **Step 2: Run the focused request spec and verify RED**

Run:

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/requests/admin/advertising_orders_spec.rb
```

Expected: the new example fails because the show page does not yet render the
requested detail fields and date grouping.

### Task 2: Implement formatting and show-page details

**Files:**
- Modify: `app/helpers/advertising_orders_helper.rb`
- Modify: `app/views/admin/advertising_orders/show.html.erb`

- [ ] **Step 1: Add helper methods for dates and windows**

Add helper methods that:

```ruby
def advertising_order_date_ranges(order)
  dates = order.advertising_order_line_days.map(&:date).compact.uniq.sort
  return t("admin.crud.none") if dates.empty?

  dates.slice_when { |previous, current| current != previous + 1 }.map do |range|
    first_date = range.first
    last_date = range.last
    first_label = first_date.strftime("%d.%m.%Y")
    last_label = last_date.strftime("%d.%m.%Y")
    first_date == last_date ? first_label : "#{first_label}–#{last_label}"
  end.join(", ")
end

def advertising_order_windows_label(order)
  windows = order.advertising_order_windows
  return t("admin.crud.none") if windows.empty?

  windows.map do |window|
    "#{window.starts_at.strftime('%H:%M')}–#{window.ends_at.strftime('%H:%M')}"
  end.join(", ")
end

def advertising_order_day_count(order)
  order.advertising_order_line_days.map(&:date).compact.uniq.count.presence || t("admin.crud.none")
end
```

Use the existing `t("admin.crud.none")` translation for empty collections.

- [ ] **Step 2: Render the requested detail rows**

Add a second Flowbite card/definition list to the show template with translated
labels for date ranges, day count, windows, media filename, duration, content
type, content category, and total shows. Use `admin_attachment_name` and
`admin_enum_label` for media fields and existing model human names where
available.

- [ ] **Step 3: Run focused specs and verify GREEN**

Run:

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/requests/admin/advertising_orders_spec.rb
```

Expected: the request spec passes, including the date-gap formatting example.

### Task 3: Final verification

**Files:**
- Review: `app/helpers/advertising_orders_helper.rb`
- Review: `app/views/admin/advertising_orders/show.html.erb`

- [ ] **Step 1: Run lint and diff checks**

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rubocop app/helpers/advertising_orders_helper.rb
git diff --check
```

- [ ] **Step 2: Run the full RSpec suite**

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec
```

Record unrelated pre-existing failures separately if they remain.
