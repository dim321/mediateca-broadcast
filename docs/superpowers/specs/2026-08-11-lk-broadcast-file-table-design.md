# Design: LK media table with source + broadcast (.ts) links

**Date:** 2026-08-11  
**Status:** approved for implementation planning  
**Scope:** Cabinet (ЛК) UI only — display of existing `file` and `broadcast_file` attachments

## Problem

After video upload, Hub transcodes to MPEG-TS and attaches `broadcast_file` (`.ts`). The original `file` (e.g. `.mp4`) stays attached. The media library and other LK surfaces only show `file.filename`, so operators cannot see or download the airtime artifact even when `processing_status` is `ready`.

## Goals

- Show **both** source and broadcast files as **separate download links** where media filenames appear in ЛК.
- Replace the media library card grid with a **table**.
- One row per `MediaAsset`; source and `.ts` in **different columns**.
- When `.ts` is missing: show status text (`Processing…` / `N/A`), not an empty cell.

## Non-goals

- No changes to `ProcessMediaMetadataJob`, `MediaTranscodeJob`, or encode profile.
- No replacing or deleting the original `file` attachment.
- No Administrate / operator dashboard changes.
- No `.ts` preview player; downloads only.
- No dual grid/table toggle.

## Approach

Shared helper for attachment link / placeholder text + table row ViewComponent for the media library. Rotations and select labels reuse the same helper.

## Architecture

### Display helpers (`MediaAssetsHelper`)

| Method (indicative) | Behavior |
|---------------------|----------|
| Source link | `link_to` filename → `rails_blob_path(media_asset.file, disposition: :attachment)` when `file` attached |
| Broadcast cell | If `broadcast_file.attached?` → download link with `.ts` filename; else placeholder (below) |
| Select label | `"#{source} · #{broadcast_or_placeholder}"` for `collection_select` |

**Broadcast placeholder rules:**

| Condition | Text (i18n) |
|-----------|-------------|
| Non-video | `N/A` |
| Video, `broadcast_file` missing, status `pending` or `processing` | `Processing…` |
| Video, `broadcast_file` missing, other status (e.g. `failed`, or `ready` without file — inconsistent) | Humanized `processing_status` (e.g. `Failed`) |

### Components / views

1. **`Media::MediaAssetRowComponent`** — one `<tr>` for the library table. Replaces `Media::MediaAssetCardComponent` usage in the library.
2. **`app/views/media_assets/index.html.slim`** — `#media_assets_grid` card grid → `table.table` (same pattern as `locations#index`), wrapped in `overflow-x-auto`. Upload form unchanged.
3. **`app/views/media_assets/_media_asset.html.slim`** — renders row component. Keep existing `dom_id(media_asset, :card)` on the replaceable root so `broadcast_card_refresh` and `update.turbo_stream` need no rename.
4. **`Rotations::RotationItemComponent`** — keep the sortable list item (not a full table); show source download link and broadcast link/placeholder as two adjacent labeled fields in the row.
5. **`rotations/show` `collection_select`** — label via helper (source · broadcast/placeholder).

### Media library columns

| Column | Content |
|--------|---------|
| Preview | Preview image if attached, else placeholder |
| Source | Download link to original `file` |
| Broadcast (.ts) | Download link or placeholder text |
| Status | Existing badge styling from card component |
| Duration | `duration_seconds` with `s`, or em dash |
| Content type | i18n of `content_type` enum |
| Visibility | i18n of `visibility` enum |

### Live updates

Existing `MediaAsset#broadcast_card_refresh` continues to replace the row after status/metadata changes. Eager-load on index (and rotation show): `file_attachment: :blob`, `broadcast_file_attachment: :blob`, `preview_attachment: :blob` to avoid N+1.

### Auth / delivery

Blob URLs only for assets already authorized by current media library / rotation org scoping. Use Active Storage redirect/proxy paths already used elsewhere in the app (`url_for` / `rails_blob_path`).

## Data flow

Unchanged backend:

```
upload → ProcessMediaMetadataJob → (video) MediaTranscodeJob → attach broadcast_file → ready
```

UI reads `file` + `broadcast_file`; no new models or columns.

## Error handling (UI)

- Failed video without `.ts`: Broadcast column shows failed status text; optional tooltip from `metadata["transcode_error"]` / `metadata["error"]` on the status badge (nice-to-have, not required for MVP of this UI).
- Missing `file` should not occur for valid library rows; if it does, show em dash instead of link.

## Testing

- Helper/component unit specs: video + `.ts` → two links; video without `.ts` → `Processing…`; image → `N/A`.
- Request or system smoke: `GET` media library contains table headers and both column concepts.
- Rotation item markup includes source and broadcast cell content.

## i18n

Add keys under `media_assets` (and rotations if needed) in `config/locales/mediateca.en.yml`:

- Column headers
- `Processing…`, `N/A`
- Reuse existing `content_types.*` / `visibilities.*` where possible

Only English locale file exists in the project today.

## Files likely touched

- `app/helpers/media_assets_helper.rb` (new)
- `app/components/media/media_asset_row_component.rb` + `.html.slim` (new)
- `app/components/media/media_asset_card_component.*` (remove or leave unused → prefer remove if unused)
- `app/views/media_assets/index.html.slim`
- `app/views/media_assets/_media_asset.html.slim`
- `app/components/rotations/rotation_item_component.html.slim`
- `app/views/rotations/show.html.slim`
- `app/controllers/media_assets_controller.rb` (includes for eager load)
- `config/locales/mediateca.en.yml`
- Specs under `spec/helpers`, `spec/components`, and/or `spec/requests`

## Success criteria

1. Media library is a table with the agreed columns.
2. Ready video shows downloadable source and `.ts` in one row.
3. Processing video shows source link + `Processing…` in Broadcast.
4. Non-video shows source link + `N/A` in Broadcast.
5. Rotation item list and add-media select expose both artifacts consistently via the shared helper.
