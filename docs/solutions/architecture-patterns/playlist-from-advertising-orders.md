---
title: Playlist from Advertising Orders
date: 2026-09-21
last_updated: 2026-09-22
category: architecture-patterns
module: playlists
problem_type: architecture_pattern
component: service_object
severity: medium
applies_when:
  - Explaining how a screen's daily playlist is built from multiple clients' advertising orders
  - Changing ActivateOrder, order-claim overlap, or commercial interleaving
  - Debugging why two commercial orders share an hour on one screen
  - Changing HourGrid, emit_beat_slot, emit_mixed_commercial, or NeutralPicker
  - Choosing org vs location time zone for grids vs broadcast day
  - Tempted to generate the playlist from AdvertisingOrder rows, or to drop MediaPlan because orders exist
tags:
  - playlist
  - advertising-order
  - media-plan
  - airtime
  - broadcast-portrait
  - hour-grid
  - location-time-zone
  - architecture
related_components:
  - AdvertisingOrder
  - Advertising::ActivateOrder
  - Advertising::ScreenDayHours
  - Airtime::OccupyWithPlan
  - Airtime::ScreenOverlapGuard
  - BroadcastPortrait
  - Playlist
  - Playlists::GenerateForDate
  - Playlists::HourGrid
  - Playlists::NeutralPicker
  - Playlists::EnqueueRegen
  - Playlists::PackageFromPlaylists
  - Playlists::Fingerprint
related_docs:
  - docs/solutions/architecture-patterns/playlist-as-airtime-projection.md
  - docs/solutions/architecture-patterns/media-plan-as-airtime-slot.md
  - docs/solutions/architecture-patterns/broadcast-portrait-as-screen-airtime-structure.md
  - CONCEPTS.md
---

# Как формируется плейлист экрана из заказов нескольких клиентов

Плейлист — дневная проекция станции, не документ заказа и не медиаплан. Заказ хранит коммерческое намерение. Активация нарезает его на слоты эфира (`MediaPlan` + confirmed `AirtimeBooking`). Генератор читает эти слоты и портрет экрана. Заказ он не открывает.

Иерархия: `Location → Station → Screen`. Плейлист пишется на пару `(station, for_date)` в часовом поясе локации. Привязка ролика к монитору — `playlist_item_screens`.

Смежные паттерны: `playlist-as-airtime-projection.md` (инварианты проекции, regen, агент), `media-plan-as-airtime-slot.md` (occupy/FWW ручного слота), `broadcast-portrait-as-screen-airtime-structure.md` (портрет). Глоссарий: `CONCEPTS.md`.

---

## 1. Роли

| Сущность | Роль |
|----------|------|
| **AdvertisingOrder** | Коммерческий документ: продукт, цена, скидка, один `shows_per_hour` на весь документ, стратегия распределения дней, статус |
| **AdvertisingOrderWindow** | Окна суток заказа (`time`, например 10:00–18:00), общие для всех строк |
| **AdvertisingOrderLine** | Одна строка = один экран |
| **AdvertisingOrderLineDay** | День строки и учётное `shows`. День с `shows <= 0` не пишется и эфир не занимает |
| **Rotation** (`system_managed`) | Упорядоченный каталог клипов заказа. Все планы заказа ссылаются на одну rotation |
| **MediaPlan** | Занятое окно `[starts_at, ends_at)` + rotation + экраны. У заказа есть `advertising_order_line_id`; у ручного слота его нет |
| **AirtimeBooking** | Внутренняя бронь 1:1 с планом. На ней guard пересечений |
| **BroadcastPortrait** | Структура часа экрана: частоты, лимит рекламы подряд, филлер, врезки, сервис |
| **Playlist / PlaylistItem** | День станции: `offset_seconds` от якоря, `source_kind`, `media_plan_id`, экраны |

Код: `app/domain/advertising/`, `app/domain/airtime/`, `app/domain/playlists/`.

---

## 2. От заказа к занятым окнам

### Черновик

`Advertising::CreateOrder` в одной транзакции создаёт скрытую rotation организации и кладёт ролики в `rotation_items` в порядке выбора. Этот порядок — порядок показов. Заказ остаётся `draft`.

### Сетка

Пояс сетки — `organizations.time_zone`.

`AdvertisingOrderGrid` сохраняет окна суток, затем для каждого выбранного экрана считает дни (`computed_lines_payload`):

`shows = shows_per_hour × число часов, где окно заказа пересекается с эффективными рабочими часами экрана`

`ScreenDayHours#counted_hours` считает час, если в нём положительны и минуты окна заказа, и минуты часов экрана.

Стратегия распределения обнуляет часть дат до записи (`distributed_shows`): будни, выходные, чётные дни, нечётные дни, шахматка по половине экранов. `UpdateGrid` дни с `shows <= 0` не сохраняет.

`shows` на дне — учёт и сумма заказа (`RecalculateTotals`). Частоту в плейлисте задаёт `shows_per_hour` заказа, который активация копирует на каждый медиаплан.

`Advertising::AssertShowsPerHour` требует, чтобы N входило в пересечение `block_frequencies_per_hour` портретов выбранных экранов. Каталог: 1, 2, 3, 4, 5, 6, 10, 12, 20, 30 (`BroadcastPortrait::BLOCK_FREQUENCIES_PER_HOUR`).

### Активация

`Advertising::ActivateOrder` идёт по строкам. День занимается, если `shows > 0` и `Coverage.occupied?` ещё ложен (у строки нет активного плана, пересекающего эти сутки в поясе организации).

На каждый такой день `ScreenDayHours#intersecting_ranges` пересекает окна заказа с рабочими часами экрана и склеивает соседние куски. Окно заказа `10:00–18:00` и часы экрана `09:00–13:00` плюс `14:00–22:00` дают два интервала и два медиаплана.

На каждый интервал — `Airtime::OccupyWithPlan` с `order_claim: true`, `screens: [line.screen]`, `placement_kind` и `shows_per_hour` с заказа, `advertising_order_line: line`.

Конфликт одного окна не откатывает остальные. Хотя бы один успех переводит `draft` → `active`. Коммерческая квота после этого только предупреждает (`CommercialQuota::Check`), занятость не снимает.

Повторная активация уже покрытый день пропускает целиком: покрытие смотрит на сутки, не на отдельный кусок.

Отмена заказа (`Advertising::CancelOrder`) мягко отменяет каждый активный план через `Airtime::Cancel`, затем ставит заказу `cancelled`.

### Occupy и два клиента на одном часе

`OccupyWithPlan` в транзакции: `ScreenLock` (advisory `874_201`) → `ScreenOverlapGuard` → confirmed booking + active MediaPlan + `media_plan_screens`. После коммита — `Playlists::EnqueueRegen.from_plan`. Генерации внутри lock нет.

При `order_claim: true` guard ищет пересечение только с ручными планами (`advertising_order_line_id IS NULL`). Два заказа делят экран и час. Ручной медиаплан остаётся first-write-wins против всех, включая заказы.

Файл: `app/domain/airtime/screen_overlap_guard.rb`.

Один заказ на несколько экранов и дней порождает много планов: строка × непокрытый день × слитый интервал пересечения. Все они ссылаются на одну rotation заказа. Замена ролика (`Advertising::ReplaceClip`) меняет каталог и ставит regen по активным планам, слоты не пересоздаёт.

---

## 3. Regen

`Playlists::EnqueueRegen` не генерирует inline. Ставит `GenerateForDateJob` на даты горизонта станции: сегодня в `locations.time_zone` и вперёд на `ceil(offline_cache_hours / 24)`.

Пояс broadcast day — локация. Пояс сетки заказа — организация. Это разделение намеренное.

---

## 4. Генерация дня станции

`Playlists::GenerateForDate`:

1. Транзакция + `StationDateLock` (`874_202` на `station.id`). ScreenLock здесь не брать.
2. Экраны станции. Нет портрета — `Portraits::CopyTemplate`. Нет ни одного портрета — `skipped: :missing_portrait`, строки плейлиста нет.
3. `Fingerprint` (SHA-256 входов). Совпал с current — version не растёт.
4. `build_entries` → старый current становится `superseded`, новый current с `version + 1`.

Occupying plans (`Fingerprint.occupying_plans`): active MediaPlan + confirmed booking, окно пересекает `[day_start, day_end)` в поясе локации, экран станции в `media_plan_screens` или в membership группы, `order(:id)`.

Закрытый день (нет рабочих окон) всё равно пишет current-плейлист с нулём позиций и якорем в локальную полночь. Это не промах горизонта: агент v2 не ставит повторную генерацию.

---

## 5. Эфир одного экрана

`emissions_for_screen` берёт эффективные рабочие часы экрана (свои или унаследованные от локации) в поясе локации. `build_slots` режет каждый час.

Число слотов часа — `Playlists::HourGrid.slot_count`:

- есть коммерческие планы с `shows_per_hour` из каталога → НОК этих частот;
- иначе → `portrait.hour_slot_count` (максимум частот портрета).

Шаг = `3600 / count`. Слот, вылезающий за рабочее окно, обрезается.

На слот, по приоритету (`emissions_for_screen`):

1. Врезка или welcome/close с `time_of_day`, попавшие в слот, заменяют слот.
2. Иначе, если у покрывающих планов есть каталожные частоты — `emit_beat_slot`. Это обычный путь активированного заказа: N уже проверен на каталог портрета.
3. Иначе слот берёт следующий блок цикла портрета (`commercial` / `filler` / служебные заголовки). Welcome/close без времени и врезки в цикл не входят.

Welcome/close без `time_of_day` ставятся на открытие и закрытие рабочих окон (`day_bound_emissions`), вне нарезки часа.

### Сетка ударов нескольких клиентов

`HourGrid.catalog_hit?`: план с частотой N попадает в слот `index`, если `index % (slot_count / N) == 0`. На удар берётся один клип (`clips_per_plan: 1`). Несколько планов на одном ударе идут по кругу (`round_robin_plan_clips`): A, B, A, B. Порядок планов — `id`.

Пример. A заказал 6 показов в час, B — 4. НОК = 12 слотов.

- A: каждый 2-й слот (0, 2, 4, 6, 8, 10).
- B: каждый 3-й (0, 3, 6, 9).
- Слоты 0 и 6: клип A, затем клип B.
- Слот без ударов: филлер портрета (`emit_commercial_fallback`).

Клип плана берёт `NeutralPicker` со стратегией `sequential`: каталог сдвинут на число дней от 1970-01-01, курсор идёт вперёд по дню. `min_seconds` для рекламы нет — короткий ролик не отбрасывается. Филлер и врезки короче `portrait.neutral_min_seconds` (допустимо 0, 5, 10; по умолчанию 10) отбрасываются.

Коммерческий пакет оборачивается `service_header_start` / `service_header_end`, если хотя бы один план в слоте — `commercial`.

Пока на часе есть каталожные частоты, циклические блоки портрета на этих слотах не шагаются. Пустой удар уходит в филлер, а не в следующий commercial-блок цикла.

### Цикл портрета

Путь `emit_cycle_block` → `emit_commercial` остаётся для часа без каталожных частот.

- Ровно один план и у него нет `advertising_order_line_id` (ручной слот): в слот кладётся пачка клипов сразу (`emit_single_plan_commercial`). Размер пачки — `ceil(shows_per_hour / hour_slot_count)`, не больше `max_commercial_in_row`.
- Иначе (несколько планов, в том числе заказы вне каталога): `emit_mixed_commercial` берёт с каждого плана такую же пачку и чередует клипы по кругу, с общим потолком `max_commercial_in_row`.

Для заказа с каталожным N этот путь не основной.

Нет занимающего плана на commercial-слоте — тот же fallback на первый filler-блок портрета.

---

## 6. Слияние экранов и выдача агенту

Эмиссия рождается с `screen_ids: [screen.id]`. `merge_emissions` группирует по `(offset_seconds, media_asset_id, source_kind, media_plan_id)` и объединяет экраны.

- Два клиента на одном экране — разные `media_plan_id`, разные позиции.
- Один филлер на двух экранах станции в один offset — одна позиция с обоими экранами.

`offset_seconds` считается от самого раннего открытия рабочих окон станции в этот день. Закрытый день якорит полночь.

Агент v2: `GET /api/agent/v2/package` → `PackageFromPlaylists`: timed `entries` и `screen_map` (id экрана → индексы). Промах горизонта только ставит генерацию в очередь. Inline `GenerateForDate` и подмена телом v1 запрещены.

v1 (`Agent::PackageBuilder`) — отдельный overlapping-plan контракт.

`media_plan_id` на позиции нужен разбору факта показа (`Playlists::ResolvePlayEvent`): организация берётся с плана, пока план активен и бронь подтверждена.

---

## 7. Сквозной сценарий

Один экран X на станции локации, два клиента.

```
Org A (6/час), Org B (4/час)
  → CreateOrder + сетка на Screen X (пояс организации)
       shows дня = N × часы пересечения окна и часов экрана
       стратегия может обнулить часть дат
  → ActivateOrder
       → ScreenDayHours ∩ operating hours → один или несколько интервалов на день
       → OccupyWithPlan(order_claim) на каждый интервал
            → MediaPlan A и MediaPlan B на один screen/hour, одна rotation у каждого заказа
  → EnqueueRegen (пояс локации)
  → GenerateForDate(station, date)
       → occupying_plans = [planA, planB] по id
       → час режется на НОК(6, 4) = 12 ударов
       → на ударе один клип с попавшего плана; на общем ударе A затем B
       → пустой удар — филлер портрета
       → PlaylistItem.media_plan_id + playlist_item_screens → Screen X
  → Agent v2: entries экрана через screen_map
```

---

## 8. Часовые пояса

| Контекст | TZ |
|----------|-----|
| Окна заказа, дни сетки, `ScreenDayHours`, `Coverage` | `organizations.time_zone` |
| `Playlist.for_date`, рабочие часы, границы дня в fingerprint, горизонт regen | `locations.time_zone` |

Расхождение поясов организации и локации само по себе не ошибка.

---

## 9. Медиаплан остаётся нарезкой эфира

Заказ закрыл пользовательский сценарий коммерческого размещения: ролики, экраны, дни, частота. Отдельный «создать медиаплан», чтобы выйти в эфир по заказу, не нужен.

Запись `MediaPlan` генератор не заменяет заказом.

- Заказ хранит намерение (экран, календарные дни, окна суток, одно N). Занятые интервалы считает активация и пишет отдельным планом на каждый слитый кусок.
- `Fingerprint.occupying_plans` и позиции плейлиста смотрят на `MediaPlan`, не на `AdvertisingOrder`.
- Ручной слот без строки заказа по-прежнему эксклюзивен. Заказы часы делят. Это два режима guard, оба живут на плане и брони.
- Покрытие, частичный конфликт и отмена одного окна опираются на уже нарезанные планы.

Убирать медиаплан из кабинета как способ оформить коммерческий заказ можно. Удалять модель, пока плейлист ищется по активным планам, нельзя: слой занятости переедет в документ, который хранит цену и статус договора.

Квота считает час как сумму N длительностей каталога по кругу (`CommercialQuota::HourlyShowsDuration`) и не вычитает реальное наложение планов. Это оценка доли, не раскладка плейлиста. Раскладка — сетка ударов из раздела 5.

---

## 10. Инварианты

1. Playlist не занимает эфир. Сертификаты — из заказов и PlayLog, не из позиций плейлиста.
2. Regen после транзакции occupy/cancel/reschedule. Cancel пишет `update_columns`, поэтому regen явный.
3. ScreenLock `874_201` и StationDateLock `874_202` не смешивать. В `GenerateForDate` ScreenLock не брать.
4. Order claims пересекаются друг с другом. Ручной план — FWW против всех.
5. Сетка заказа — пояс организации. День плейлиста — пояс локации.
6. `shows` дня строки — учёт. Частота эфира — `shows_per_hour` на медиаплане.
7. Каталожный N на покрывающих коммерческих планах включает сетку ударов на весь час. Цикл портрета на этих слотах не шагается.
8. У каждой позиции плейлиста хотя бы один экран в `playlist_item_screens`.
9. Секундный `AirtimeQuota` как ёмкость размещения не возвращать. Коммерческий процент — soft, вне Guard.
10. Промах v2 только ставит генерацию в очередь.
