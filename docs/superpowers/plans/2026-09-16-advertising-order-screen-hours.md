# Автоматический интервал рекламного заказа — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** После выбора экранов автоматически устанавливать общий интервал их рабочих часов, сохраняя ручные и добавленные пользователем окна.

**Architecture:** Stimulus `order-screen-picker` сообщает об изменении выбранных экранов контроллеру `order-windows`. Контроллер окон хранит автоматический статус только у исходной строки, пересчитывает её по `data-hours`, а любое ручное редактирование снимает статус. Формат серверных параметров не меняется.

**Tech Stack:** Rails 8.1, Slim, Stimulus, Capybara/RSpec system specs, Docker Compose.

---

### Task 1: Обозначить автоматическое окно в форме

**Files:**
- Modify: `app/views/advertising_orders/_form.html.slim`
- Modify: `app/views/advertising_orders/_window_fields.html.slim`
- Modify: `app/views/advertising_orders/_screen_picker.html.slim`

- [ ] **Step 1: Write the failing system expectation**

В `spec/system/advertising_order_placement_spec.rb` добавить отдельный `:js` сценарий, который открывает новый заказ с двумя экранами и проверяет, что исходное окно получает рассчитанные значения `starts_at` и `ends_at`. Сначала ожидание должно падать, потому что строка окна и события ещё не имеют нужных data-атрибутов.

- [ ] **Step 2: Run the focused test**

Run:

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/system/advertising_order_placement_spec.rb
```

Expected: FAIL because the window remains `08:00–23:00`.

- [ ] **Step 3: Add the markup contract**

Передать в partial окна локальный признак:

```slim
= render 'advertising_orders/window_fields',
    starts_at: '08:00',
    ends_at: '23:00',
    automatic: true
```

В `_window_fields.html.slim` добавить `data-order-windows-automatic` на исходную строку и action `input->order-windows#markManual` на оба поля. Шаблон добавляемого окна должен рендериться с `automatic: false`.

В `_form.html.slim` добавить action формы:

```slim
data: {
  controller: stimulus_controllers.join(' '),
  action: 'order-grid:recompute->order-grid#recompute order-screen-picker:recompute->order-windows#updateAutomaticWindow'
}
```

- [ ] **Step 4: Verify the markup**

Run:

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/requests/advertising_orders_spec.rb
```

Expected: existing request specs pass and the rendered HTML contains the automatic-window marker.

- [ ] **Step 5: Commit**

```bash
git add app/views/advertising_orders/_form.html.slim app/views/advertising_orders/_window_fields.html.slim app/views/advertising_orders/_screen_picker.html.slim spec/system/advertising_order_placement_spec.rb
git commit -m "test: define automatic order window markup"
```

### Task 2: Пересчитывать автоматическое окно по выбранным экранам

**Files:**
- Modify: `app/javascript/controllers/order_screen_picker_controller.js`
- Modify: `app/javascript/controllers/order_windows_controller.js`

- [ ] **Step 1: Write the failing system scenarios**

В `spec/system/advertising_order_placement_spec.rb` покрыть:

```ruby
it "sets the common screen hours on the automatic window", :js do
  # select two screens with different hours
  # expect the first window to contain latest opening and earliest closing
end

it "preserves edited and added windows when screen selection changes", :js do
  # select screens, edit automatic window, add a second window
  # change selection
  # expect edited first and added second windows to remain unchanged
end
```

Тестовые экраны должны иметь часы `09:00–21:00` и `10:00–20:00`; ожидаемый общий интервал — `10:00–20:00`. После ручного изменения первого окна на `11:00–12:00` и добавления окна `14:00–15:00` оба значения должны пережить изменение выбора.

- [ ] **Step 2: Run the scenarios and verify RED**

Run:

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/system/advertising_order_placement_spec.rb
```

Expected: the new scenarios fail because no automatic-window recalculation exists.

- [ ] **Step 3: Dispatch a recompute event after selection changes**

В `order_screen_picker_controller.js` после синхронизации selected rows and frequency options вызвать существующее `this.dispatch("recompute", { prefix: "order-grid" })` расширив его отдельным событием для окон:

```javascript
this.dispatch("recompute", { prefix: "order-screen-picker" })
```

Событие должно выполняться из `selectionChanged`, `toggleAll` и initial `connect` only when the existing selection is rendered. Не менять синхронизацию grid rows.

- [ ] **Step 4: Implement the minimal automatic-window algorithm**

В `order_windows_controller.js` добавить:

```javascript
updateAutomaticWindow() {
  const row = this.listTarget.querySelector("[data-order-windows-automatic='true']")
  if (!row) return

  const selectedRows = Array.from(
    this.element.querySelectorAll("[data-order-screen-picker-target='row']")
  ).filter((pickerRow) => pickerRow.querySelector("input[type='checkbox']")?.checked)

  if (selectedRows.length === 0) {
    this.setWindow(row, "08:00", "23:00")
    return
  }

  const bounds = selectedRows.flatMap((pickerRow) => this.hoursBounds(pickerRow))
  if (bounds.length === 0) {
    this.setWindow(row, "", "")
    return
  }

  const start = Math.max(...bounds.map(([from]) => from))
  const end = Math.min(...bounds.map(([, to]) => to))

  if (start < end) {
    this.setWindow(row, this.clock(start), this.clock(end))
  } else {
    this.setWindow(row, "", "")
  }
}
```

`hoursBounds` должен безопасно разобрать `row.dataset.hours`, пройти значения по всем датам текущей сетки, получить для каждого списка часов `[minHour * 60, (maxHour + 1) * 60]`, а `setWindow` менять только поля автоматической строки. Если `markManual` вызывается на её input, установить `data-order-windows-automatic="false"`.

Поскольку сервер передаёт открытые часы по часам, границы вычисляются с точностью до часа. Снятие всех экранов возвращает `08:00–23:00`; отсутствие пересечения очищает поля.

- [ ] **Step 5: Verify GREEN**

Run:

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/system/advertising_order_placement_spec.rb
```

Expected: all advertising-order system examples pass.

- [ ] **Step 6: Commit**

```bash
git add app/javascript/controllers/order_screen_picker_controller.js app/javascript/controllers/order_windows_controller.js spec/system/advertising_order_placement_spec.rb
git commit -m "feat: derive order window from selected screen hours"
```

### Task 3: Проверить полную связанную область

**Files:**
- No new files.

- [ ] **Step 1: Run the related request and system specs**

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/requests/advertising_orders_spec.rb spec/requests/admin/advertising_orders_spec.rb spec/system/advertising_order_placement_spec.rb
```

- [ ] **Step 2: Run Ruby/ERB lint for changed Rails files**

Use the repository lint command or the configured RuboCop command inside the web container, limiting it to changed Ruby/ERB files where supported. Confirm there are no new errors.

- [ ] **Step 3: Inspect the final diff**

Run:

```bash
git diff HEAD~2..HEAD --check
git status --short
```

Confirm the pre-existing modification in `app/controllers/concerns/advertising_order_grid.rb` is untouched.
