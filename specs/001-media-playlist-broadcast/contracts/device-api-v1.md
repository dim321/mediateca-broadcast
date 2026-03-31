# Contract: Device API v1

**Audience**: прошивка / WebView-плеер на точке трансляции  
**Base URL**: `https://{host}/api/v1`  
**Auth**: `Authorization: Bearer <device_token>` (выдаётся при регистрации точки)

## POST /device_sessions

Обмен краткоживущего **pairing code** (из кабинета) на `device_token`.

**Request** (JSON):

```json
{
  "pairing_code": "string",
  "device_fingerprint": "optional-string"
}
```

**Response** `201`:

```json
{
  "device_token": "string",
  "broadcast_point_id": "uuid",
  "poll_interval_seconds": 45
}
```

**Errors**: `422` неверный код; `409` точка уже привязана.

---

## GET /device_sessions/current

Проверка токена и получение сводки точки.

**Response** `200`:

```json
{
  "broadcast_point_id": "uuid",
  "organization_id": "uuid",
  "time_zone": "Europe/Moscow",
  "poll_interval_seconds": 45
}
```

---

## GET /playback_assignments/current

Текущее назначение для воспроизведения (MVP: одно активное окно).

**Response** `200`:

```json
{
  "assignment_id": "uuid",
  "starts_at": "2026-03-31T10:00:00Z",
  "ends_at": "2026-03-31T12:00:00Z",
  "playlist": {
    "id": "uuid",
    "items": [
      {
        "position": 1,
        "kind": "video",
        "duration_seconds": 30,
        "media": {
          "id": "uuid",
          "url": "https://...signed...",
          "mime_type": "video/mp4"
        }
      }
    ]
  }
}
```

**Response** `204`: нет активного эфира — плеер показывает заставку/ожидание.

---

## Семантика медиа-URL

- Поле `url` — **временно действующая** подписанная ссылка на blob (Active Storage
  `rails_blob_url` / service signed GET).
- Плеер MUST запрашивать свежий `GET /playback_assignments/current` до истечения
  окна или при `403` на медиа.

---

## Версионирование

- Несовместимые изменения → `/api/v2`. Поле `api_min_version` может быть добавлено
  в `GET /device_sessions/current` в следующей итерации.
