# Data Model: медиатека и трансляция в торговых точках

**Feature**: `001-media-playlist-broadcast`  
**Spec**: [spec.md](./spec.md) | **Research**: [research.md](./research.md)

## Bounded contexts

| Контекст | Ответственность |
|----------|-----------------|
| **Identity & Tenancy** | Организации, пользователи, членство, роли (если есть) |
| **Media Library** | Загрузка, blob, метаданные, статус обработки, превью |
| **Playlists** | Плейлисты, позиции, DnD-порядок |
| **Fleet** | Точки трансляции, теги, группы, членство точки в группах |
| **Scheduling** | Окна эфира, привязка к плейлисту и целям; конфликты |
| **Playback (device)** | Токен устройства, текущее назначание, выдача URL медиа |

## Сущности и поля (черновик схемы)

### Organization

- `id`, `name`, `time_zone` (TZDB, fallback для точек без своего пояса)
- timestamps

### User

- `id`, `email`, `encrypted_password` (или внешний IdP — вне scope MVP)
- `organization_id` FK → organizations (если один user = один tenant; при
  multi-org membership — отдельная таблица `memberships` в следующей итерации)

### MediaAsset

- `id`, `organization_id` FK
- `uploaded_by_id` FK → users (опционально)
- `processing_status`: enum `pending` / `processing` / `ready` / `failed`
- `content_kind`: enum `video` | `audio` | `image` | `document` | `presentation`
  (согласовано с разрешёнными MIME)
- `duration_seconds` (nullable), `metadata` JSONB (codec, container, ошибки ffprobe)
- `active_storage_attachment` связь: один основной файл (`has_one_attached :file`)
- `preview` — через Active Storage variant / отдельное вложение
- timestamps  
**Инвариант**: `organization_id` обязателен; медиа не «шарится» между тенантами.

### Playlist

- `id`, `organization_id`, `name`, `slug` или уникальность `(organization_id, name)`
- timestamps

### PlaylistItem

- `id`, `playlist_id` FK, `media_asset_id` FK
- `position` integer (уникален в рамках `playlist_id`) — порядок для эфира и UI DnD
- опционально `display_duration_seconds` для статичного изображения в эфире
- timestamps  
**Инвариант**: `media_asset.organization_id == playlist.organization_id`.

### Tag

- `id`, `organization_id`, `name` — нормализованный slug или case-insensitive
  уникальность `(organization_id, lower(name))`

### BroadcastPoint

- `id`, `organization_id`
- `name`, `city`, `venue_label` (торговая точка)
- `time_zone` nullable — иначе organization.time_zone
- `status`: `online` / `offline` / `unknown` (по heartbeat)
- `device_token_digest` (не хранить сыро токен)
- timestamps

### BroadcastPointTag (HABTM)

- `broadcast_point_id`, `tag_id` — составной уникальный индекс

### PointGroup

- `id`, `organization_id`, `name`  
**Инвариант**: название уникально в рамках организации (или сгенерированное).

### PointGroupMembership

- `point_group_id`, `broadcast_point_id` — уникальная пара

### ScheduleRule (или BroadcastSchedule)

- `id`, `organization_id`
- `playlist_id` FK
- `starts_at` / `ends_at` timestamptz (UTC)
- `timezone_context`: enum `organization` | `point` (как резолвить отображение;
  расчёт в коде по research)
- timestamps

### ScheduleTarget

Вариант A (рекомендуется для FR-010): связь many-to-many расписания с группами:

- `schedule_rule_id`, `point_group_id`

Опционально точечное исключение/дополнение — отдельные таблицы в следующей
итерации.

**Инвариант**: цели расписания и плейлист одной организации; пересечение двух
`ScheduleRule` на одну и ту же `PointGroup` в один момент — ошибка валидации
(по умолчанию).

### DeviceHeartbeat (опционально)

- `broadcast_point_id`, `last_seen_at`, `app_version` — для SC-004 и UX статуса.

## Индексы (минимум)

- `media_assets(organization_id)`, `playlist_items(playlist_id, position)`
- `broadcast_point_tags(tag_id)`, `broadcast_point_tags(broadcast_point_id)`
- `schedule_rules(organization_id, starts_at, ends_at)` — для поиска активного
  правила; GIST/exclusion constraint на пересечение по `point_group` через
  материализованное представление или проверка в транзакции (уточнить при
  реализации).

## Состояния: обработка медиа

```
pending → processing → ready
                  ↘ failed (retry / manual)
```

## Удаления

- Удаление `MediaAsset`, на который ссылаются `PlaylistItem` или активные
  `ScheduleRule`: либо **restrict** с понятной ошибкой, либо soft-delete;
  решение продукта зафиксировать в политике (пока — **restrict** + сообщение).
