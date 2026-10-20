# Design: папка «Нейтральный контент» в Service Theme

**Date:** 2026-10-20  
**Status:** approved for planning  
**Approach:** A — `neutral_rotation_id` на тематике; при apply — upsert блока `filler` с ownership через `service_theme_id`

## Problem

При создании тематики (`ServiceThemes::Create`) жёстко создаются только четыре system-managed папки: сервисные шапки (начало/конец), приветствие, завершение дня. Оператору нужна пятая папка «Нейтральный контент», из которой при назначении тематики на экран берётся нейтралка эфира (`filler`).

## Goals

- Новая тематика всегда получает пять папок; пятая называется «Нейтральный контент» / «Neutral content».
- Папка хранит клипы с `content_type: neutral` (не `service`).
- `Portraits::ApplyServiceTheme` подставляет ротацию этой папки в блок `filler` портрета и помечает ownership через `service_theme_id`.
- Снятие тематики удаляет theme-owned `filler`; чужой `filler` без `service_theme_id` не трогает при clear (но при apply существующий `filler` перезаписывается ротацией тематики и становится theme-owned).
- Существующие тематики получают пустую пятую папку (data migration / backfill).
- Генератор плейлиста не меняется: эфир нейтралки остаётся через kind `filler` и `NeutralPicker`.

## Non-goals

- Новый block kind (`service_neutral` и т.п.).
- Изменения `Playlists::GenerateForDate` / agent API v1/v2.
- Автоматический backfill клипов в новую папку.
- Восстановление прежней ротации `filler` после снятия тематики (после clear theme-owned filler удаляется).

## Why This Approach

| Option | Verdict |
|--------|---------|
| A — FK `neutral_rotation_id` + upsert `filler` с `service_theme_id` | Chosen: без нового kind, filler уже в генераторе, ownership явный |
| B — новый kind `service_neutral` | Rejected: дублирует filler, трогает генератор и enum |
| C — ротация по соглашению об имени | Rejected: хрупко для destroy/backfill |

## Behavior

### Создание тематики

`ServiceThemes::Create` создаёт пять `system_managed` ротаций. Имя пятой: `"{theme.name} · neutral"`. FK: `neutral_rotation_id` NOT NULL.

Константы модели:

- `ROTATION_ROLES` — без изменений (четыре сервисных kind для портрета).
- Отдельная роль `:neutral` для папки и для ключа `pick_strategies`.
- UI/создание папок итерируют «folder roles» = ключи `ROTATION_ROLES` + `:neutral`.

### Админ-медиатека тематики

На `show` — пять секций. Подпись пятой — i18n `admin.service_themes.folder_labels.neutral` («Нейтральный контент» / «Neutral content»), не `enums.broadcast_portrait_block.kind.filler` («Нейтралка»).

- Upload (`ServiceThemes::AddClip`): для `:neutral` → `content_type: neutral`; для сервисных ролей → `service` как сейчас.
- Place (`PlaceValidatedClip` + options helper): для `:neutral` допускает validated `neutral` клипы той же org; для сервисных — `service`.

### Apply / clear тематики

`Portraits::ApplyServiceTheme#apply_theme!`:

1. Как сейчас upsert четырёх service-блоков по `ROTATION_ROLES`.
2. Upsert одного блока `kind: filler`: `rotation = theme.neutral_rotation`, `service_theme_id = theme.id`, `pick_strategy` из `pick_strategies[:neutral]` (или default `sequential`).
3. `portrait.update!(service_theme: theme)`.

`clear_theme!`:

1. Удаляет блоки с kind из `ROTATION_ROLES.values`.
2. Удаляет `filler`-блоки с `service_theme_id` (theme-owned).
3. `portrait.update!(service_theme: nil)`.

Если на портрете уже был `filler` без theme — apply перезаписывает его ротацию/strategy и ставит `service_theme_id`.

### Валидации

`BroadcastPortraitBlock#fields_match_kind` для `filler`: разрешить `service_theme_id` (убрать `reject_service_theme`). Остальные требования filler без изменений (rotation, pick_strategy, no time_of_day).

`assign_rotation_from_service_theme`: для filler с theme можно выставлять `theme.neutral_rotation` (симметрия с service kinds), либо полагаться на явный assign в `ApplyServiceTheme` — выбрать один путь и покрыть спеком.

### Экран: pick strategy

Virtual attr `neutral_pick_strategy` на `Screen` (как у четырёх сервисных), передаётся в `pick_strategies` при apply. Форма экрана показывает пятый select с подписью «Нейтральный контент».

### Backfill

Миграция:

1. Добавить `neutral_rotation_id` nullable.
2. Для каждой `service_themes` строки создать system-managed `Rotation` и проставить FK.
3. Сделать колонку NOT NULL + FK restrict + index.

Портреты с уже назначенной тематикой **не** получают filler автоматически в миграции; filler появится при следующем apply тематики (сохранение экрана / повторный выбор темы). Это осознанный MVP-компромисс — задокументировать в плане.

## Testing

- `ServiceThemes::Create` — 5 ротаций, имя `· neutral`.
- `AddClip` / `PlaceValidatedClip` — neutral role → `content_type` neutral.
- `ApplyServiceTheme` — создаёт/обновляет filler; clear удаляет theme-owned filler, оставляет commercial и non-theme filler если такой есть (сценарий: clear после apply → filler уходит; отдельный кейс non-theme filler только если clear без предшествующего apply на этот filler).
- Request admin show — пять папок, подпись «Нейтральный контент».
- Factory `:service_theme` — `neutral_rotation`.
- Model validation filler + `service_theme_id`.

## Docs to update after ship

- `docs/solutions/architecture-patterns/operator-service-theme-on-screen.md` — пять папок; apply также пишет filler.
- `docs/solutions/architecture-patterns/broadcast-portrait-as-screen-airtime-structure.md` — `service_theme_id` материализует четыре service + filler.
- Copy `admin.service_themes.empty.description` — «пять папок» вместо «четыре».
