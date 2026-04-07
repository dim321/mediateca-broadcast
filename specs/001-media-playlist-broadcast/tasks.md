# Tasks: Медиатека и трансляция в торговых точках

**Input**: Design documents from `/specs/001-media-playlist-broadcast/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/, quickstart.md

**Tests**: Тесты обязательны. Для каждой user story сначала пишутся тесты (Red), затем реализация (Green), затем рефакторинг.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: можно выполнять параллельно (разные файлы, нет зависимости от незавершенных задач)
- **[Story]**: метка пользовательской истории (`[US1]` ... `[US5]`)

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: инициализация проекта и базовых инструментов

- [X] T001 Initialize Rails 8 app skeleton in `Gemfile`, `config/application.rb`, and `config/routes.rb`
- [X] T002 Configure Devcontainer with Ruby 4.x, PostgreSQL 18, ffmpeg in `.devcontainer/devcontainer.json` and `.devcontainer/Dockerfile`
- [X] T003 [P] Configure RuboCop and RSpec in `.rubocop.yml`, `.rspec`, and `spec/spec_helper.rb`
- [X] T004 [P] Configure Tailwind pipeline in `config/tailwind.config.js` and `app/assets/stylesheets/application.tailwind.css`
- [X] T005 [P] Configure Kamal baseline in `config/deploy.yml` and `.kamal/secrets`
- [X] T006 Configure Active Storage and queue adapters in `config/storage.yml` and `config/environments/production.rb`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: базовая доменная и инфраструктурная платформа, блокирующая все user stories

**⚠️ CRITICAL**: завершить до начала US1-US5

- [X] T007 Create initial database migrations for tenancy and identity in `db/migrate/*_create_organizations_users.rb`
- [X] T008 Create core media/fleet/scheduling migrations in `db/migrate/*_create_media_and_broadcast_core.rb`
- [X] T009 [P] Implement tenant scoping concern in `app/controllers/concerns/current_organization.rb`
- [X] T010 [P] Add base models with associations in `app/models/organization.rb` and `app/models/user.rb`
- [X] T011 Implement Pundit wiring in `app/controllers/application_controller.rb` and `app/policies/application_policy.rb`
- [X] T012 [P] Create Avo base configuration in `config/initializers/avo.rb` and `app/avo/resources/application_resource.rb`
- [X] T013 [P] Implement domain folder structure and base service objects in `app/domain/media/base_service.rb`, `app/domain/playlists/base_service.rb`, `app/domain/fleet/base_service.rb`, and `app/domain/scheduling/base_service.rb`
- [X] T014 Configure job processing and retries in `config/queue.yml` and `app/jobs/application_job.rb`
- [X] T015 [P] Add shared request auth helpers for device API in `spec/support/device_auth_helpers.rb`
- [X] T016 Add structured logging baseline in `config/initializers/lograge.rb` and `config/environments/production.rb`

**Checkpoint**: Foundation ready - user story implementation can now begin

---

## Phase 3: User Story 1 - Загрузка медиа и превью в кабинете (Priority: P1) 🎯 MVP

**Goal**: загрузка поддерживаемых файлов, асинхронная обработка, превью и метаданные

**Independent Test**: загрузка валидного/невалидного файла, переход `processing -> ready/failed`, превью и длительность в кабинете в рамках одного tenant

### Tests for User Story 1 (MANDATORY) ⚠️

- [X] T017 [P] [US1] Add model specs for `MediaAsset` invariants and statuses in `spec/models/media_asset_spec.rb`
- [X] T018 [P] [US1] Add request specs for upload endpoint and validation errors in `spec/requests/media_assets_spec.rb`
- [X] T019 [P] [US1] Add job specs for metadata extraction flow in `spec/jobs/process_media_metadata_job_spec.rb`
- [X] T020 [US1] Add system spec for upload, preview, and status updates in `spec/system/media_upload_spec.rb`

### Implementation for User Story 1

- [X] T021 [P] [US1] Implement `MediaAsset` model and enums in `app/models/media_asset.rb`
- [X] T022 [P] [US1] Implement upload and index actions in `app/controllers/media_assets_controller.rb`
- [X] T023 [P] [US1] Create upload/index Slim views in `app/views/media_assets/index.html.slim` and `app/views/media_assets/_media_asset.html.slim`
- [X] T024 [P] [US1] Implement media card component in `app/components/media/media_asset_card_component.rb` and `app/components/media/media_asset_card_component.html.slim`
- [X] T025 [US1] Implement metadata processing job with ffprobe integration in `app/jobs/process_media_metadata_job.rb` and `app/domain/media/metadata_extractor.rb`
- [X] T026 [US1] Implement preview generation service in `app/domain/media/preview_generator.rb`
- [X] T027 [US1] Add Turbo stream updates for media status in `app/views/media_assets/update.turbo_stream.erb`
- [X] T028 [US1] Add media upload routes in `config/routes.rb`

**Checkpoint**: US1 works independently and is demo-ready

---

## Phase 4: User Story 2 - Плейлисты из библиотеки + Drag & Drop (Priority: P2)

**Goal**: создание плейлистов, состав, порядок элементов, перетаскивание и сохранение порядка

**Independent Test**: создать плейлист, добавить элементы, изменить порядок drag-and-drop, обновить страницу и увидеть тот же порядок

### Tests for User Story 2 (MANDATORY) ⚠️

- [X] T029 [P] [US2] Add model specs for `Playlist` and `PlaylistItem` ordering invariants in `spec/models/playlist_spec.rb` and `spec/models/playlist_item_spec.rb`
- [X] T030 [P] [US2] Add request specs for reorder endpoint in `spec/requests/playlists/reorder_spec.rb`
- [X] T031 [US2] Add system spec for drag-and-drop reorder flow in `spec/system/playlist_reorder_spec.rb`

### Implementation for User Story 2

- [X] T032 [P] [US2] Implement `Playlist` and `PlaylistItem` models in `app/models/playlist.rb` and `app/models/playlist_item.rb`
- [X] T033 [P] [US2] Implement playlist CRUD controller in `app/controllers/playlists_controller.rb`
- [X] T034 [P] [US2] Implement reorder endpoint in `app/controllers/internal/playlists/reorders_controller.rb`
- [X] T035 [P] [US2] Implement reorder domain service in `app/domain/playlists/reorder_items.rb`
- [X] T036 [P] [US2] Implement Stimulus drag-and-drop controller in `app/javascript/controllers/playlist_sort_controller.js`
- [X] T037 [P] [US2] Create playlist Slim views in `app/views/playlists/index.html.slim` and `app/views/playlists/show.html.slim`
- [X] T038 [P] [US2] Create playlist item component in `app/components/playlists/playlist_item_component.rb` and `app/components/playlists/playlist_item_component.html.slim`
- [X] T039 [US2] Add playlist and internal reorder routes in `config/routes.rb`

**Checkpoint**: US2 is independently functional and persists order correctly

---

## Phase 5: User Story 3 - Точки, теги и группы (Priority: P3)

**Goal**: управление точками трансляции, тегами, фильтрацией и группами

**Independent Test**: создать точки с тегами, отфильтровать по тегам, собрать группу из выбранных точек

### Tests for User Story 3 (MANDATORY) ⚠️

- [X] T040 [P] [US3] Add model specs for point-tag-group associations in `spec/models/broadcast_point_spec.rb`, `spec/models/tag_spec.rb`, and `spec/models/point_group_spec.rb`
- [X] T041 [P] [US3] Add request specs for point filtering and group membership in `spec/requests/broadcast_points_spec.rb` and `spec/requests/point_groups_spec.rb`
- [X] T042 [US3] Add system spec for points tagging and grouping in `spec/system/broadcast_points_management_spec.rb`

### Implementation for User Story 3

- [X] T043 [P] [US3] Implement fleet models in `app/models/broadcast_point.rb`, `app/models/tag.rb`, `app/models/broadcast_point_tag.rb`, `app/models/point_group.rb`, and `app/models/point_group_membership.rb`
- [X] T044 [P] [US3] Implement points controller with tag filters in `app/controllers/broadcast_points_controller.rb`
- [X] T045 [P] [US3] Implement point groups controller in `app/controllers/point_groups_controller.rb`
- [X] T046 [P] [US3] Implement fleet query/service objects in `app/domain/fleet/filter_points.rb` and `app/domain/fleet/group_membership_manager.rb`
- [X] T047 [P] [US3] Create fleet Slim views in `app/views/broadcast_points/index.html.slim` and `app/views/point_groups/show.html.slim`
- [X] T048 [US3] Add fleet routes in `config/routes.rb`

**Checkpoint**: US3 independently delivers points, tags, filters, and groups

---

## Phase 6: User Story 4 - Расписание трансляций (Priority: P4)

**Goal**: расписания плейлистов на группы точек с контролем конфликтов и TZ

**Independent Test**: создать расписание на группу, изменить его, получить ошибку на пересечение интервалов

### Tests for User Story 4 (MANDATORY) ⚠️

- [ ] T049 [P] [US4] Add model specs for schedule invariants and overlap rules in `spec/models/schedule_rule_spec.rb` and `spec/models/schedule_target_spec.rb`
- [ ] T050 [P] [US4] Add request specs for schedule CRUD and conflicts in `spec/requests/schedule_rules_spec.rb`
- [ ] T051 [US4] Add system spec for schedule creation/editing with conflict error in `spec/system/schedule_rules_spec.rb`

### Implementation for User Story 4

- [ ] T052 [P] [US4] Implement scheduling models in `app/models/schedule_rule.rb` and `app/models/schedule_target.rb`
- [ ] T053 [P] [US4] Implement scheduling domain services in `app/domain/scheduling/conflict_detector.rb` and `app/domain/scheduling/time_window_resolver.rb`
- [ ] T054 [P] [US4] Implement schedule controller in `app/controllers/schedule_rules_controller.rb`
- [ ] T055 [P] [US4] Create schedule Slim views in `app/views/schedule_rules/index.html.slim` and `app/views/schedule_rules/_form.html.slim`
- [ ] T056 [US4] Add scheduling routes in `config/routes.rb`

**Checkpoint**: US4 independently manages schedule lifecycle with conflict safety

---

## Phase 7: User Story 5 - Воспроизведение на устройстве (Priority: P5)

**Goal**: Device API для получения текущего назначения и медиа URL, плюс базовая регистрация устройства

**Independent Test**: получить `device_token`, запросить текущее назначение, воспроизвести порядок элементов из плейлиста в активном окне

### Tests for User Story 5 (MANDATORY) ⚠️

- [ ] T057 [P] [US5] Add request specs for device session endpoints in `spec/requests/api/v1/device_sessions_spec.rb`
- [ ] T058 [P] [US5] Add request specs for playback assignment endpoint in `spec/requests/api/v1/playback_assignments_spec.rb`
- [ ] T059 [US5] Add service specs for assignment resolver in `spec/domain/playback/current_assignment_resolver_spec.rb`

### Implementation for User Story 5

- [ ] T060 [P] [US5] Implement device session controller in `app/controllers/api/v1/device_sessions_controller.rb`
- [ ] T061 [P] [US5] Implement playback assignments controller in `app/controllers/api/v1/playback_assignments_controller.rb`
- [ ] T062 [P] [US5] Implement playback domain resolver in `app/domain/playback/current_assignment_resolver.rb`
- [ ] T063 [P] [US5] Implement signed media URL presenter in `app/domain/playback/media_url_presenter.rb`
- [ ] T064 [P] [US5] Implement device token policy checks in `app/policies/device_session_policy.rb`
- [ ] T065 [US5] Add Device API routes in `config/routes.rb`

**Checkpoint**: US5 independently serves device playback assignment and media URLs

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: сквозные улучшения и финальная валидация перед реализацией по фазам

- [ ] T066 [P] Add Avo resources for core entities in `app/avo/resources/media_asset.rb`, `app/avo/resources/playlist.rb`, `app/avo/resources/broadcast_point.rb`, and `app/avo/resources/schedule_rule.rb`
- [ ] T067 Add Pundit policy coverage for tenant boundaries in `spec/policies/*_policy_spec.rb`
- [ ] T068 [P] Add database indexes and constraints refinements in `db/migrate/*_add_indexes_and_constraints.rb`
- [ ] T069 [P] Add performance smoke specs for tag filtering and schedule queries in `spec/requests/performance/filtering_spec.rb`
- [ ] T070 Run quickstart validation and update notes in `specs/001-media-playlist-broadcast/quickstart.md`
- [ ] T071 Final docs sync for API and plan references in `specs/001-media-playlist-broadcast/contracts/device-api-v1.md` and `specs/001-media-playlist-broadcast/plan.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: старт сразу
- **Phase 2 (Foundational)**: после Phase 1; блокирует все user stories
- **Phase 3-7 (US1-US5)**: после завершения Phase 2; рекомендуется порядок P1 → P5
- **Phase 8 (Polish)**: после целевых user stories

### User Story Dependencies

- **US1 (P1)**: базовый MVP, не зависит от других US
- **US2 (P2)**: использует медиа из US1
- **US3 (P3)**: независима от US2, но общая авторизация/тенантность из Foundation
- **US4 (P4)**: зависит от US2 (playlist) и US3 (groups)
- **US5 (P5)**: зависит от US4 (активные назначения) и US2 (контент плейлиста)

### Within Each User Story

- Сначала тесты (красные), затем модели/доменные сервисы, затем контроллеры/UI/API
- Параллельные задачи отмечены `[P]`

### Parallel Opportunities

- Setup: `T003`, `T004`, `T005` параллельно после `T001`
- Foundation: `T009`, `T010`, `T012`, `T013`, `T015` параллельно после миграций
- US1: `T017`, `T018`, `T019` параллельно; затем `T021`-`T024` параллельно
- US2: `T029`, `T030` параллельно; затем `T032`-`T038` частично параллельно
- US3: `T040`, `T041` параллельно; затем `T043`-`T047` параллельно
- US4: `T049`, `T050` параллельно; затем `T052`-`T055` параллельно
- US5: `T057`, `T058` параллельно; затем `T060`-`T064` параллельно

---

## Parallel Example: User Story 2

```bash
Task: "T029 [US2] model specs in spec/models/playlist_spec.rb and spec/models/playlist_item_spec.rb"
Task: "T030 [US2] request specs in spec/requests/playlists/reorder_spec.rb"

Task: "T036 [US2] Stimulus DnD controller in app/javascript/controllers/playlist_sort_controller.js"
Task: "T038 [US2] playlist item component in app/components/playlists/playlist_item_component.rb"
```

---

## Implementation Strategy

### MVP First

1. Complete Phase 1 and Phase 2
2. Complete Phase 3 (US1)
3. Validate US1 independently (upload -> processing -> preview)
4. Demo MVP

### Incremental Delivery

1. Add US2 (playlists + DnD)
2. Add US3 (points/tags/groups)
3. Add US4 (schedules)
4. Add US5 (device playback API)
5. Finish Phase 8 polish

### Parallel Team Strategy

1. Team A: Setup + Foundational
2. Team B: US2 after US1 contracts stabilized
3. Team C: US3 in parallel with US2
4. Team D: US4 + US5 when dependencies ready

