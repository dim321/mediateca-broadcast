# Implementation Plan: Медиатека и трансляция в торговых точках

**Branch**: `001-media-playlist-broadcast` | **Date**: 2026-03-31 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/001-media-playlist-broadcast/spec.md`

## Summary

Мультитенантный SaaS: загрузка рекламных медиа в кабинет организации,
асинхронный анализ формата и длительности, превью, плейлисты с **drag-and-drop**
порядком, точки трансляции с произвольными тегами и группами, расписание эфира
по времени (UTC + часовые пояса), выдача контента на ТВ-плееры по **Device API
v1**. Технически: **Rails 8**, **Hotwire** (Slim + ViewComponent + Stimulus),
**PostgreSQL 18**, **Active Storage**, фоновые джобы для метаданных и конвертации
PDF/PPTX, **Pundit** + **Avo** для админки, деплой **Kamal**; плеер —
HTTPS + JSON + подписанные URL на blob.

## Technical Context

**Language/Version**: Ruby 4.x  
**Primary Dependencies**: Rails 8, Hotwire (Turbo + Stimulus), Slim, ViewComponent,
Pundit, Avo, Active Storage, Active Job (Solid Queue или Sidekiq — зафиксировать
при генерации приложения), ffmpeg/ffprobe в runtime обработки медиа  
**Storage**: PostgreSQL 18 (OLTP); объекты медиа — Active Storage (local/S3/R2 в prod)  
**Testing**: RSpec, FactoryBot, Capybara (системные сценарии Turbo), request specs
для Device API и критичных JSON-эндпоинтов кабинета  
**Target Platform**: Linux (Kamal), браузер в кабинете; WebView/браузер на устройстве
трансляции  
**Project Type**: Rails web application + отдельный контракт для плеера  
**Performance Goals**: фильтрация ~200 точек по тегам — воспринимаемо < 2 с (SC-003);
пилот до 50 устройств; метаданные медиа — не блокировать HTTP-запрос загрузки  
**Constraints**: мультитенантная изоляция по `organization_id`; конфликт окон
расписания на одну целевую группу — отклонять по умолчанию; подписанные URL медиа
с ограниченным TTL  
**Scale/Scope**: MVP — полный сквозной сценарий spec (5 user stories); роли
пользователей детализировать в итерации политик Pundit

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Перед Phase 0

- [x] TDD: для этой фичи тесты описаны в spec/EQ; при реализации — Red → Green → Refactor.
- [x] DDD: контексты и сущности — в [data-model.md](./data-model.md); инварианты — в таблицах и разделе удалений.
- [x] UI: Hotwire-first; Inertia не требуется (DnD через Stimulus + SortableJS).
- [x] UI stack: кабинет — Slim + ViewComponent; админка — Avo.
- [x] Runtime/Tooling: Devcontainer + PG 18 — при создании репозитория приложения.
- [x] Delivery: Kamal + миграции с планом отката.
- [x] Authorization: Pundit (+ тесты политик); Avo с теми же политиками.
- [x] Admin: операторы/саппорт через Avo на модели тенанта.
- [x] Data: схема под PostgreSQL 18, индексы — см. data-model.

### После Phase 1 (дизайн и контракты)

- [x] Контракт плеера зафиксирован: [contracts/device-api-v1.md](./contracts/device-api-v1.md).
- [x] Исследования без противоречий конституции: [research.md](./research.md).
- [x] Дублирование доменных правил в Avo — только через вызовы модели/сервисов, не копировать в Resource.

**Итог по gate**: нарушений нет; таблица Complexity Tracking не заполняется.

## Project Structure

### Documentation (this feature)

```text
specs/001-media-playlist-broadcast/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── device-api-v1.md
│   └── cabinet-json-shapes.md
├── spec.md
├── checklists/
└── tasks.md              # Phase 2: /speckit.tasks
```

### Source Code (repository root) — целевая раскладка Rails

```text
app/
├── controllers/
│   ├── concerns/
│   └── api/v1/devices/
├── models/
├── policies/
├── avo/
├── components/
├── views/                 # Slim
├── domain/
│   ├── media/
│   ├── playlists/
│   ├── fleet/
│   └── scheduling/
├── jobs/
└── javascript/controllers/

config/
├── routes.rb
└── deploy.yml

spec/
├── models/
├── requests/api/v1/
├── system/
├── policies/
└── components/

.devcontainer/
```

**Structure Decision**: основной продукт — монолит Rails 8; границы DDD отражены
подкаталогами `app/domain/{media,playlists,fleet,scheduling}`. API устройств —
версионируемый namespace `Api::V1::Devices::*`. Медиа-пайплайн и расписание не
выносить в отдельный сервис в MVP без ADR.

## Complexity Tracking

Нет отклонений от конституции, требующих исключения.

## Phase 0 – Outline & Research

**Выходной артефакт**: [research.md](./research.md) — закрыты выбор Pundit,
Active Storage, ffprobe/джобы, конвертация PDF/PPTX, протокол устройства, DnD,
часовые пояса, тестовый стек.

## Phase 1 – Design & Contracts

**Выходные артефакты**:

- [data-model.md](./data-model.md) — сущности, индексы, инварианты, статусы медиа.
- [contracts/device-api-v1.md](./contracts/device-api-v1.md) — публичный контракт плеера.
- [contracts/cabinet-json-shapes.md](./contracts/cabinet-json-shapes.md) — внутренние формы/DnD.
- [quickstart.md](./quickstart.md) — локальный запуск и проверка историй.

## Phase 2 – Tasks

Не входит в эту команду. Следующий шаг: **`/speckit.tasks`** → `tasks.md`.

## Agent context

После обновления плана выполнено: `.specify/scripts/bash/update-agent-context.sh cursor-agent`
(с `SPECIFY_FEATURE=001-media-playlist-broadcast`).
