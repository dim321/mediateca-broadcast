# Admin Operating Hours Copy Monday Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On the Administrate location operating-hours form, add a button that copies Monday start/end into all other weekdays in the browser.

**Architecture:** Extend `OperatingHoursField` form partial with an i18n-labeled `type="button"` and a small scoped vanilla JS snippet. No Stimulus, no model/controller changes. Persistence stays create/update + `Location::OperatingHours.normalize`.

**Tech Stack:** Rails, Administrate 1.0, ERB field partial, vanilla JS, RSpec request specs, `mediateca.*.yml` i18n.

**Spec:** `docs/superpowers/specs/2026-08-11-admin-operating-hours-copy-mon-design.md`

## Global Constraints

- Administrate only (`app/views/fields/operating_hours_field/_form.html.erb`); do not change ЛК `app/views/locations/edit.html.slim`.
- No server-side copy flag; no changes to `Location`, `OperatingHoursField.permitted_attribute`, or normalize/validate.
- Button must be `type="button"` (never submit the form).
- Overwrite Tue–Sun always; empty Monday clears other days; no confirm dialog.
- Prefer single quotes in Ruby; RU + EN i18n keys.
- TDD: failing test → implement → pass → commit per task.

## File map

| File | Responsibility |
|------|----------------|
| `config/locales/mediateca.en.yml` | `locations.edit.copy_monday_to_all` EN string |
| `config/locales/mediateca.ru.yml` | Same key RU string |
| `app/views/fields/operating_hours_field/_form.html.erb` | Button + data attrs + inline script |
| `spec/requests/admin/locations_spec.rb` | Assert button label on new form |

---

### Task 1: i18n + failing request assertion

**Files:**
- Modify: `config/locales/mediateca.en.yml` (under `locations.edit`)
- Modify: `config/locales/mediateca.ru.yml` (under `locations.edit`)
- Modify: `spec/requests/admin/locations_spec.rb`

**Interfaces:**
- Produces: i18n key `locations.edit.copy_monday_to_all`
  - EN: `Copy Mon to all days`
  - RU: `Скопировать пн на все дни`

- [ ] **Step 1: Add i18n keys**

In `config/locales/mediateca.en.yml`, under existing `locations.edit:` (alongside `hint`, `start`, `end`, `cancel`, `days`), add:

```yaml
      copy_monday_to_all: Copy Mon to all days
```

In `config/locales/mediateca.ru.yml`, under existing `locations.edit:`, add:

```yaml
      copy_monday_to_all: Скопировать пн на все дни
```

- [ ] **Step 2: Extend the new-form request spec (expect failure until Task 2)**

Replace the existing `"shows the operating hours fields on the new form"` example in `spec/requests/admin/locations_spec.rb` with:

```ruby
  it "shows the operating hours fields on the new form" do
    get new_admin_location_path

    expect(response).to have_http_status(:success)
    expect(response.body).to include('name="location[operating_hours][mon][][start]"')
    expect(response.body).to include(I18n.t("locations.edit.days.mon"))
    expect(response.body).to include(I18n.t("locations.edit.copy_monday_to_all"))
    expect(response.body).to include('data-operating-hours-copy-mon')
  end
```

- [ ] **Step 3: Run the spec and confirm it fails on the new assertions**

Run:

```bash
bundle exec rspec spec/requests/admin/locations_spec.rb:31 --format documentation
```

Expected: FAIL — body does not include `locations.edit.copy_monday_to_all` / `data-operating-hours-copy-mon` (i18n key may resolve, but HTML lacks the string until the button exists).

- [ ] **Step 4: Commit**

```bash
git add config/locales/mediateca.en.yml config/locales/mediateca.ru.yml spec/requests/admin/locations_spec.rb
git commit -m "$(cat <<'EOF'
test: expect copy-Monday control on admin location form

EOF
)"
```

---

### Task 2: Button + scoped vanilla JS in Administrate form

**Files:**
- Modify: `app/views/fields/operating_hours_field/_form.html.erb`
- Test: `spec/requests/admin/locations_spec.rb` (from Task 1)

**Interfaces:**
- Consumes: `t("locations.edit.copy_monday_to_all")`
- Produces: DOM contract
  - Root: `div.field-unit__field[data-operating-hours-root]`
  - Inputs: `data-operating-hours-day="mon|tue|…"` and `data-operating-hours-part="start|end"`
  - Button: `button[type=button][data-operating-hours-copy-mon]`
  - Days copied: all of `Location::OperatingHours::DAY_KEYS` except `mon`

- [ ] **Step 1: Replace `_form.html.erb` with button + script**

Overwrite `app/views/fields/operating_hours_field/_form.html.erb` with:

```erb
<%#
# OperatingHours Form Partial
%>

<div class="field-unit__label">
  <%= f.label field.attribute %>
</div>
<div class="field-unit__field" data-operating-hours-root>
  <p class="field-unit__hint">
    Weekly schedule used as the commercial quota denominator. Leave a day blank when closed.
  </p>
  <table class="collection-data">
    <thead>
      <tr>
        <th>Day</th>
        <th>Start</th>
        <th>End</th>
      </tr>
    </thead>
    <tbody>
      <% Location::OperatingHours::DAY_KEYS.each do |day| %>
        <% window = field.window_for(day) %>
        <tr>
          <td><%= t("locations.edit.days.#{day}") %></td>
          <td>
            <input
              type="time"
              name="<%= f.object_name %>[operating_hours][<%= day %>][][start]"
              value="<%= window['start'] || window[:start] %>"
              class="field-unit__field"
              data-operating-hours-day="<%= day %>"
              data-operating-hours-part="start"
            >
          </td>
          <td>
            <input
              type="time"
              name="<%= f.object_name %>[operating_hours][<%= day %>][][end]"
              value="<%= window['end'] || window[:end] %>"
              class="field-unit__field"
              data-operating-hours-day="<%= day %>"
              data-operating-hours-part="end"
            >
          </td>
        </tr>
      <% end %>
    </tbody>
  </table>
  <p class="field-unit__hint" style="margin-top: 0.75rem;">
    <button type="button" class="button" data-operating-hours-copy-mon>
      <%= t("locations.edit.copy_monday_to_all") %>
    </button>
  </p>
</div>

<script>
  (function () {
    var roots = document.querySelectorAll("[data-operating-hours-root]");
    roots.forEach(function (root) {
      if (root.dataset.operatingHoursBound === "1") return;
      root.dataset.operatingHoursBound = "1";

      var button = root.querySelector("[data-operating-hours-copy-mon]");
      if (!button) return;

      button.addEventListener("click", function () {
        var monStart = root.querySelector(
          '[data-operating-hours-day="mon"][data-operating-hours-part="start"]'
        );
        var monEnd = root.querySelector(
          '[data-operating-hours-day="mon"][data-operating-hours-part="end"]'
        );
        if (!monStart || !monEnd) return;

        var startValue = monStart.value || "";
        var endValue = monEnd.value || "";
        var days = <%= Location::OperatingHours::DAY_KEYS.reject { |d| d == "mon" }.to_json %>;

        days.forEach(function (day) {
          var startInput = root.querySelector(
            '[data-operating-hours-day="' + day + '"][data-operating-hours-part="start"]'
          );
          var endInput = root.querySelector(
            '[data-operating-hours-day="' + day + '"][data-operating-hours-part="end"]'
          );
          if (startInput) startInput.value = startValue;
          if (endInput) endInput.value = endValue;
        });
      });
    });
  })();
</script>
```

Notes for the implementer:
- `dataset.operatingHoursBound` avoids double-binding if the partial is rendered more than once in the same document.
- Administrate’s default `.button` class matches other admin controls; keep it.
- Do not add Stimulus or touch the admin layout javascript partial.

- [ ] **Step 2: Run admin locations request specs**

Run:

```bash
bundle exec rspec spec/requests/admin/locations_spec.rb --format documentation
```

Expected: PASS (both create + new form examples).

- [ ] **Step 3: Manual smoke (optional but recommended)**

1. Sign in as operator.
2. Open `/admin/locations/new`.
3. Set Monday to `09:00`–`21:00`, click the button, confirm Tue–Sun match.
4. Clear Monday, click again, confirm Tue–Sun clear.
5. Save; confirm persisted hours via show page / DB.

- [ ] **Step 4: Commit**

```bash
git add app/views/fields/operating_hours_field/_form.html.erb
git commit -m "$(cat <<'EOF'
feat: copy Monday hours to all days in admin locations form

EOF
)"
```

---

## Spec coverage checklist

| Spec requirement | Task |
|------------------|------|
| Button on Administrate operating-hours form | Task 2 |
| RU/EN labels | Task 1 |
| Client-side copy Mon → Tue–Sun | Task 2 |
| Empty Mon clears other days | Task 2 (same overwrite path) |
| `type="button"`, no submit | Task 2 |
| No ЛК / model / Stimulus changes | Global constraints |
| Request spec asserts control present | Task 1 → green in Task 2 |
