# Contract: JSON shapes для кабинета (внутренние API)

Черновик для Turbo-форм и возможных JSON-эндпоинтов. Внешние клиенты не
документируются как публичный продукт в v1.

## PATCH /internal/playlists/:id/reorder

**Request**:

```json
{
  "playlist_item_ids": ["uuid", "uuid", "uuid"]
}
```

**Response** `200`: обновлённый порядок (`positions` 1..n).  
**Errors** `422`: элемент чужой организации или не принадлежит плейлисту.

## Обработка медиа (poll UI)

**GET** ответ фрагмента или JSON для карточки медиа после загрузки:

```json
{
  "id": "uuid",
  "processing_status": "processing",
  "preview_url": "https://...",
  "duration_seconds": null,
  "error_message": null
}
```

Статус обновляется через Turbo Stream или polling до `ready` / `failed`.
