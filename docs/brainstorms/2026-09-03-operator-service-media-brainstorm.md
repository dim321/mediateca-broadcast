---
date: 2026-09-03
revised: 2026-09-04
topic: operator-service-media-library
plan: docs/plans/2026-09-03-001-feat-operator-service-media-library-plan.md
---

# Служебная медиатека оператора: тематические сервисные ролики

Оператор загружает и организует сервисные медиафайлы по тематикам (салон красоты, рыбный отдел, кошерное питание, галантерея и т.д.) для использования в эфире: шапки начала/конца рекламного блока, приветствие в начале рабочего дня и ролик завершения рабочего дня **экрана**. Клиенты используют общую библиотеку оператора; загрузка — в `/admin`.

> **Ревизия 2026-09-04:** портрет эфира и часы работы привязаны к **экрану** (не к станции). Часы работы экрана по умолчанию наследуются от локации. Детали — в плане (U0).

Свёрнуто с текущим продуктом: `MediaAsset.content_type = service`, ротации как каталоги, блоки портрета `service_header_start/end`, генератор `Playlists::GenerateForDate`. Сегодня портрет на станции — **меняется на экран**. Нет admin upload, нет тематической организации медиа, service headers берут первый eligible клип без pick_strategy.

## What We're Building

**Служебная медиатека оператора** — отдельный контур в admin:

1. **Тематики (ServiceTheme)** — свободное название («Салон красоты», «Рыбный отдел»). На каждую тему автоматически создаются **4 ротации** организации оператора:
   - шапка начала рекламного блока (`service_header_start`);
   - шапка конца рекламного блока (`service_header_end`);
   - приветствие (`service_welcome` на время открытия экрана);
   - завершение рабочего дня (`service_close` на время закрытия экрана).

2. **Загрузка в admin** — оператор добавляет файлы в «папку» темы и типа ролика; файл становится `MediaAsset` (`content_type: service`, org = operator) и `RotationItem` в соответствующей ротации темы.

3. **Портрет и тема на экране** — при создании экрана выбирается шаблон портрета (копия на экран); при редактировании — смена шаблона, правка портрета, выбор `service_theme_id`. Блоки портрета получают ссылки на 4 ротации темы. Стратегия перебора (`sequential` / `random` / `ordered`) — **настраивается оператором для каждого блока**.

4. **Часы работы экрана** — на экране: наследование от локации (по умолчанию) или собственный график. Welcome/close считаются по **эффективным** часам экрана. Плейлист остаётся на станцию; генератор мержит per-screen timeline.

## Why This Approach

| Подход | Плюсы | Минусы |
|--------|-------|--------|
| **ServiceTheme + 4 ротации (выбрано)** | Явная связь «тема → 4 ротации»; папки в UI; портрет выбирает одну тему; reuse генератора | Новая модель + admin CRUD |
| Метаданные на Rotation без модели | Меньше таблиц | Сложнее целостность «всегда 4 ротации» |
| Пресеты портрета как тема | Без новой сущности | Дублирование ротаций; слабая медиатека |

**Почему ServiceTheme:** «папка = готовая ротация» (4 на тему), библиотека по темам + ручной выбор в портрете экрана, цепочка MediaAsset → Rotation → PortraitBlock → Playlist.

**Почему портрет на экране (rev 2026-09-04):** экраны одной станции могут иметь разную тематику (салон vs рыбный отдел) и разный режим работы; станционный портрет это не позволяет.

**YAGNI:** без Directory тем; без network visibility; без клиентских service-роликов в первой итерации.

## Key Decisions

### Домен и данные

- `service_themes` — `name` (unique в org оператора), `organization_id` (operator), FK на 4 ротации. Ротации `system_managed: true`.
- `ServiceThemes::Create` — 4 пустые ротации в одной транзакции.
- `MediaAsset` из медиатеки: `content_type: service`, org оператора, `visibility: organization`.
- Удаление темы — restrict, если портреты экранов ссылаются на `service_theme_id`.

### Портрет и часы на экране (rev 2026-09-04)

- `broadcast_portraits.screen_id` — экземпляр портрета на экране; `screen_id IS NULL` — шаблон.
- При create screen: `template_id` → `Portraits::CopyTemplate(screen:)`.
- При edit screen: смена шаблона (replace), правка портрета, `service_theme_id`.
- `screens.inherit_operating_hours_from_location` default `true`; `screens.operating_hours` jsonb — свои часы при отключённом наследовании.
- `Screen#effective_operating_hours` — локация или экран.

### Портрет эфира и тема

- Nullable `service_theme_id` на портрете экрана. `ApplyServiceTheme` upsert: `service_header_start`, `service_header_end`, `service_welcome`, `service_close`.
- `pick_strategy` на всех четырёх блоках темы (в т.ч. service headers — новое).
- Welcome/close — из effective hours экрана (`day_bounds`: open первого окна, close последнего).

### Admin UI

- Секция «Служебная медиатека»: темы → 4 папки → upload.
- Форма экрана: шаблон портрета, inherit hours, custom hours, ссылка на портрет / тему.
- Upload service в admin (Flowbite). Убрать назначение портрета со станции.

### Генератор плейлиста

- Per-screen: свой портрет + effective hours → merge в station playlist (`playlist_item_screens`).
- Service headers: `NeutralPicker` + `pick_strategy`, `min_seconds: nil`.
- Fingerprint включает per-screen portrait и effective hours.

### Regen и совместимость

- Upload / rotation items → `EnqueueRegen.from_rotation`.
- Смена портрета, темы, hours экрана → `EnqueueRegen.from_screen`.
- Смена hours локации → regen экранов с inherit.
- Agent v2 / v1 — без изменения контракта.

### Вне scope первой итерации

- Клиентские service-ролики; network visibility; zip-import; Directory тем; автотема по BusinessSphere; per-screen agent token.

## Open Questions

Закрыты в плане (rev 2026-09-04):

1. ~~Разные часы в одной станции~~ → **часы и портрет на экране**, inherit от локации.
2. **День без работы** — welcome/close не генерируются; generate success.
3. **Welcome в день** — один slot на open per screen per day.
4. **Замена темы** — regen полного горизонта (`offline_cache_hours`).
5. **min_seconds** — nil для всех service-клипов (короткие шапки не отсекаются).
6. **Pipeline** — тот же transcode/`broadcast_ready`; отдельная модерация не нужна в MVP.

## Next Steps

План: `docs/plans/2026-09-03-001-feat-operator-service-media-library-plan.md`

1. **U0** — портрет и hours на экране (пререквизит).
2. **ServiceTheme + admin медиатека** — модель, upload, UI папок.
3. **Тема на портрете экрана + pick_strategy + generator** — welcome/close из effective hours.
