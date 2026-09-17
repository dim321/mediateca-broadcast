---
title: Broadcast portrait as screen airtime structure
date: 2026-09-17
last_updated: 2026-09-17
category: architecture-patterns
module: broadcast-portraits
problem_type: architecture_pattern
component: model
severity: medium
applies_when:
  - Explaining or documenting BroadcastPortrait / BroadcastPortraitBlock
  - Changing playlist generation that reads per-screen portraits
  - Adding or validating portrait block kinds
  - Choosing shows_per_hour for advertising orders across screens
  - Tempted to treat the portrait as an order catalog or airtime occupancy store
  - Tempted to bind a portrait to a station instead of a screen
tags:
  - broadcast-portrait
  - playlist
  - screen
  - service-theme
  - advertising-order
  - architecture
related_components:
  - BroadcastPortrait
  - BroadcastPortraitBlock
  - Screen
  - ServiceTheme
  - Playlists::GenerateForDate
  - Playlists::HourGrid
  - Portraits::CopyTemplate
  - Portraits::FrequencySet
  - Portraits::ApplyServiceTheme
  - Portraits::UpsertBlocks
---

# Broadcast portrait as screen airtime structure

## Context

«Портрет эфира» (`BroadcastPortrait`) задаёт, **как** собирать дневной эфир конкретного экрана: частоты слотов, лимиты рекламы подряд, нейтралка, упорядоченные блоки (реклама, нейтралка, вставки, сервис). Без портрета генератор плейлиста не знает структуру экрана.

Краткий глоссарий: `CONCEPTS.md` → Broadcast portrait. Смежные паттерны: playlist projection, service themes on portraits.

## Core idea

Портрет — **структура и правила сборки**, не источник заказов и не occupancy.

- Привязка: `Screen` `has_one :broadcast_portrait` (уникальный `screen_id`).
- Без `screen_id` — операторский **шаблон** (`templates`); `is_default` только у шаблонов; копирование на экран — `Portraits::CopyTemplate`.
- Экраны одной станции могут иметь разные портреты (например разная тематика).
- Рекламный контент в слотах приходит из активных медиапланов (в т.ч. из заказов), а не из ротации блока `commercial`.
- Генерация: per-screen эмиссии по портрету + часам работы + occupying plans → merge в один `Playlist` станции на дату (`Playlists::GenerateForDate`).

## Block kinds

Упорядочены по `position` (`BroadcastPortraitBlock`):

| `kind` | Роль |
|--------|------|
| `commercial` | Структурный слот под рекламу из медиапланов; без ротации / pick / time |
| `filler` | Нейтралка: ротация + `pick_strategy`; учитывается `neutral_min_seconds` |
| `insertion` | Точечная вставка: ротация + обязательный `time_of_day` |
| `service_header_start` / `service_header_end` | Обёртка рекламного пакета |
| `service_welcome` | Приветствие у открытия окон работы |
| `service_close` | Завершение у закрытия окон работы |

Сервисные блоки часто из `ServiceTheme` (на портрете или на блоке) — см. `operator-service-theme-on-screen.md`. Welcome/close и insertions не входят в циклический beat (`cycle_blocks`); welcome/close эмитятся как day-bound.

## Portrait-level knobs

- `block_frequencies_per_hour` — каталог допустимых частот слотов в час (`BLOCK_FREQUENCIES_PER_HOUR`); пересечение по экранам заказа — `Portraits::FrequencySet` (UI `shows_per_hour`).
- `hour_slot_count` — max частоты; шаг часа в генераторе / `Playlists::HourGrid`.
- `max_commercial_in_row` — потолок клипов рекламы подряд в слоте.
- `neutral_min_seconds` — 5 или 10 (по умолчанию 10).
- `kind` портрета: в схеме `cyclic` / `timed`, валидация сейчас допускает только `cyclic`.
- Опциональный `service_theme_id` — материализация четырёх сервисных блоков (`Portraits::ApplyServiceTheme`).

## What the portrait is not

- Не хранит заказы и не занимает эфир (occupancy = MediaPlan + confirmed booking).
- Не дневной документ станции (это `Playlist`).
- Не каталог клипов (это `Rotation`); блоки filler/insertion/service лишь ссылаются на ротации.
- Исторически портрет был per-station; продуктовое направление — **per screen** + шаблоны (см. Flagged ambiguities в `CONCEPTS.md`).

## Generation touchpoints

- `Playlists::GenerateForDate` — основной потребитель; при отсутствии портрета — copy template; если портретов нет — `skipped: :missing_portrait`.
- `Playlists::Fingerprint` — портрет и блоки входят в отпечаток дня.
- `Playlists::EnqueueRegen` — смена ротации, на которую ссылаются portrait blocks, триггерит regen затронутых станций.
- Admin: CRUD портретов/блоков; на экране — выбор шаблона / правка портрета.

## Verification

- `screen.broadcast_portrait` present after create (default template copy).
- Commercial block has no rotation; filler/insertion/service validations match kind.
- Order placement offers only intersection of selected screens' `block_frequencies_per_hour`.
- Playlist items: media_plan origin from occupying plans; filler/insertion/service from portrait blocks.
- Two screens on one station with different portraits → different per-screen emissions in one station playlist.

## Related

- `docs/solutions/architecture-patterns/playlist-as-airtime-projection.md`
- `docs/solutions/architecture-patterns/operator-service-theme-on-screen.md`
- `docs/solutions/architecture-patterns/media-plan-as-airtime-slot.md`
- `docs/superpowers/specs/2026-09-14-broadcast-portrait-block-frequencies-design.md`
- Models: `app/models/broadcast_portrait.rb`, `app/models/broadcast_portrait_block.rb`
