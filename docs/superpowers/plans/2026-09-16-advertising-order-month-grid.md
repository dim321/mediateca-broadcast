# Сетка выходов по месяцам в заказе — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Разделить сетку выходов заказа на отдельные таблицы по месяцам и показывать русские названия месяцев в именительном падеже.

**Architecture:** Helper будет возвращать упорядоченные месячные блоки и форматировать их заголовки. Форма будет рендерить один partial таблицы на каждый блок, а строки экранов будут использовать одинаковый индекс строки и общие имена полей, чтобы параметры разных месяцев собирались в одну строку заказа. Stimulus-контроллер останется на общей форме и продолжит видеть все строки и ячейки.

**Tech Stack:** Rails views, Slim partials, ERB admin view, AdvertisingOrdersHelper, RSpec request/helper specs, Docker Compose.

---

### Task 1: Добавить тесты для месячных блоков и заголовков

**Files:**
- Modify: `spec/helpers/advertising_orders_helper_spec.rb`
- Modify: `spec/requests/admin/advertising_orders_spec.rb`

- [ ] **Step 1: Написать failing helper specs**

В `spec/helpers/advertising_orders_helper_spec.rb` добавить проверки:

```ruby
describe "#advertising_grid_months" do
  it "groups dates in chronological month blocks" do
    dates = (Date.new(2026, 8, 30)..Date.new(2026, 9, 2)).to_a

    expect(helper.advertising_grid_months(dates)).to eq(
      Date.new(2026, 8, 1) => dates.first(2),
      Date.new(2026, 9, 1) => dates.last(2)
    )
  end
end

describe "#advertising_grid_month_label" do
  it "uses nominative Russian month names with a capital letter" do
    I18n.with_locale(:ru) do
      expect(helper.advertising_grid_month_label(Date.new(2026, 9, 1))).to eq("Сентябрь 2026")
    end
  end
end
```

- [ ] **Step 2: Написать failing request spec**

В контексте оператора добавить запрос с `grid_from: "2026-08-30"` и
`grid_to: "2026-09-02"`, затем проверить Nokogiri-структуру:

```ruby
it "renders a separate grid table for each month" do
  get new_admin_advertising_order_path, params: {
    organization_id: client.id,
    grid_from: "2026-08-30",
    grid_to: "2026-09-02"
  }

  tables = Nokogiri::HTML(response.body).css("table[id^='order-airtime-grid']")

  expect(tables.size).to eq(2)
  expect(tables.first.text).to include("Август 2026", "30", "31")
  expect(tables.first.text).not_to include("Сентябрь 2026", "1", "2")
  expect(tables.second.text).to include("Сентябрь 2026", "1", "2")
end
```

Тест должен проверять не голую цифру месяца, а наличие `th` с датами,
чтобы однозначно отличать дни от текста в других ячейках.

- [ ] **Step 3: Запустить только новые тесты и убедиться, что они падают**

Run:

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec \
  spec/helpers/advertising_orders_helper_spec.rb \
  spec/requests/admin/advertising_orders_spec.rb
```

Expected: FAIL, потому что helper заголовка и отдельные месячные таблицы ещё
не реализованы.

### Task 2: Реализовать helper месячных блоков и локализованный заголовок

**Files:**
- Modify: `app/helpers/advertising_orders_helper.rb`
- Modify: `config/locales/mediateca.ru.yml`
- Modify: `config/locales/mediateca.en.yml`

- [ ] **Step 1: Реализовать форматирование названия месяца**

Добавить публичный helper:

```ruby
def advertising_grid_month_label(month)
  month_name = I18n.t("date.month_names_nominative")[month.month]
  "#{month_name.capitalize} #{month.year}"
end
```

Добавить `date.month_names_nominative` в русскую и английскую локали массивом
из 13 элементов с `nil` на позиции 0. Использовать месяц как первый день
месяца, который уже возвращает `advertising_grid_months`.

- [ ] **Step 2: Сохранить хронологический порядок групп**

Обновить `advertising_grid_months`, чтобы результат был устойчивым при
получении дат в любом порядке:

```ruby
def advertising_grid_months(dates)
  Array(dates).group_by { |date| Date.new(date.year, date.month, 1) }.sort.to_h
end
```

- [ ] **Step 3: Запустить helper specs**

Run:

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec \
  spec/helpers/advertising_orders_helper_spec.rb
```

Expected: PASS.

### Task 3: Вынести одну месячную таблицу в partial

**Files:**
- Create: `app/views/advertising_orders/_monthly_grid.html.slim`
- Modify: `app/views/advertising_orders/_line_fields.html.slim`
- Modify: `app/views/advertising_orders/_form.html.slim`

- [ ] **Step 1: Создать partial месячной таблицы**

Partial должен принимать `month`, `dates`, `advertising_order`, `rows` и рендерить
существующую таблицу. Внутри:

- сохранять `data-controller` формы на внешнем элементе, не добавлять второй
  Stimulus controller;
- использовать уникальный `id`, например `order-airtime-grid-<month>`;
- выводить `advertising_grid_month_label(month)`;
- передавать в `_line_fields` только даты текущего месяца через local;
- рендерить `tfoot` с итогом текущего месячного блока.

Строка экрана должна сохранять исходный `index`, чтобы поля вида
`advertising_order[lines][0][days][][...]` из разных месячных таблиц
объединялись в один параметр.

- [ ] **Step 2: Сделать список дат в `_line_fields` локальным**

Заменить прямое использование `@grid_dates` на:

```slim
- grid_dates = local_assigns.fetch(:grid_dates) { @grid_dates }
- Array(grid_dates).each do |date|
```

Существующие вызовы partial без `grid_dates` продолжат использовать весь
период формы.

- [ ] **Step 3: Проверить, что месячный partial содержит только свой период**

Для каждого месячного блока передавать `grid_dates: dates`. Не дублировать
`rowTemplate` в каждом месяце: оставить его один раз после всех таблиц и
передать ему полный `@grid_dates`, чтобы добавляемая JS-строка могла работать
с текущей формой.

### Task 4: Переключить форму и Stimulus на месячные таблицы

**Files:**
- Modify: `app/views/advertising_orders/_form.html.slim`
- Modify: `spec/requests/admin/advertising_orders_spec.rb`
- Modify: `app/javascript/controllers/order_screen_picker_controller.js`

- [ ] **Step 1: Заменить одну таблицу циклом месячных partials**

Вместо текущего блока `table#order-airtime-grid` добавить:

```slim
- advertising_grid_months(@grid_dates).each do |month, dates|
  = render "advertising_orders/monthly_grid",
      month: month,
      dates: dates,
      advertising_order: advertising_order,
      rows: advertising_order.advertising_order_lines.select(&:screen_id)
```

Легенду оставить один раз перед циклом. В каждый месячный partial передавать
строки с индексами, вычисленными относительно полного списка экранов.
Первой таблице сохранить id `order-airtime-grid` для совместимости с
существующими селекторами, остальным таблицам дать id с годом и месяцем.

- [ ] **Step 2: Сохранить единый общий итог**

Оставить общий `grandTotal` target и `rowTemplate` на форме после месячных
таблиц. Месячные footer-итоги могут использовать отдельные `total` targets,
но итог заказа должен суммировать все line rows через существующий Stimulus
контроллер.

- [ ] **Step 3: Добавить request-проверки для одного месяца и экранов**

Проверить, что:

- период одного месяца создаёт одну таблицу;
- период двух месяцев создаёт две таблицы;
- каждая таблица содержит строку экрана и только даты своего месяца;
- одинаковый `name="advertising_order[lines][0][days][][date]"` используется
  в обеих таблицах, поэтому сервер получает единый набор дней.

- [ ] **Step 4: Обновить динамическое добавление экранов**

Заменить использование одиночных `rowTemplateTarget` и `gridLinesTarget` в
`order_screen_picker_controller.js` на `rowTemplateTargets` и
`gridLinesTargets`. При выборе нового экрана добавлять его строку в каждый
месячный `tbody`, используя соответствующий месяцу шаблон.

- [ ] **Step 5: Запустить request specs**

Run:

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec \
  spec/requests/admin/advertising_orders_spec.rb
```

Expected: PASS.

### Task 5: Проверить интеграцию Stimulus и весь набор тестов

**Files:**
- Modify: `app/javascript/controllers/order_screen_picker_controller.js`
  (already covered in Task 4)

- [ ] **Step 1: Проверить существующие JS targets**

Убедиться, что все месячные таблицы находятся внутри одного элемента формы с
`data-controller="order-grid"`, а `lineRowTargets`, `cellTargets`,
`grandTotalTarget` и `data-date` сохраняются. При корректной разметке код
контроллера менять не нужно.

- [ ] **Step 2: Запустить полный RSpec в Compose**

Run:

```bash
docker compose exec -e RAILS_ENV=test web bundle exec rspec
```

Expected: PASS без ошибок.

- [ ] **Step 3: Проверить стиль изменённых Ruby-файлов**

Run:

```bash
docker compose exec -e RAILS_ENV=test web bin/rubocop \
  app/helpers/advertising_orders_helper.rb \
  spec/helpers/advertising_orders_helper_spec.rb \
  spec/requests/admin/advertising_orders_spec.rb
```

Expected: PASS без новых нарушений RuboCop.

- [ ] **Step 4: Сделать итоговый commit**

```bash
git add app/helpers/advertising_orders_helper.rb \
  app/views/advertising_orders/_form.html.slim \
  app/views/advertising_orders/_line_fields.html.slim \
  app/views/advertising_orders/_monthly_grid.html.slim \
  spec/helpers/advertising_orders_helper_spec.rb \
  spec/requests/admin/advertising_orders_spec.rb
git commit -m "feat: split advertising order grid by month"
```
