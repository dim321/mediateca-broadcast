# Media playback and content validation — design

## What We're Building

Cabinet and operator admin show pages play a media asset so a person can judge
its content. Everyone who can already open the media library can play it.
Client traffic managers gain that same read access. Accountants stay out of the
library.

Only a traffic manager can mark the asset's content as validated, and only a
traffic manager can clear that mark. The mark records who set it and when.
The status and the validator's name are visible on the show page and in clip
pickers before save.

An unvalidated asset may sit on a draft advertising order. It cannot be used to
activate an order, to replace clips on an active order, or to enter a catalog
or service-theme rotation. Clearing the mark cancels active orders that carry
the asset, removes it from rotations that are not an order's private rotation,
and enqueues playlist regen. Draft orders keep the asset.

## Why This Approach

Chosen approach: two columns on `media_assets` and two domain services,
`MediaAssets::MarkContentValidated` and `MediaAssets::RevokeContentValidation`.
Gates live on activate, active clip replace, and rotation-item writes. Revoke
reuses `Advertising::CancelOrder` and `Playlists::EnqueueRegen`.

Rejected: a validation event log (only the current mark is required) and a
flag inside `metadata` (no user foreign key, awkward to filter in pickers).

## Key Decisions

- **Columns:** `content_validated_at` (datetime, null) and
  `content_validated_by_id` (FK to `users`, `ON DELETE nullify`). The mark is
  present only when both are set. Migration does not backfill. Existing rows
  stay unmarked.
- **Who plays:** roles that already pass `MediaAssetPolicy` show/index, plus
  `traffic_manager`. Scope matches managers: own organization, plus assets with
  network visibility. Accountant remains denied. This extra access is only on
  `MediaAssetPolicy`, not on `ApplicationPolicy#lk_content_access?`.
- **Who marks:** traffic manager of the asset's organization, or a traffic
  manager whose organization is the operator (any asset). A client traffic
  manager may open a foreign network asset and may not mark it. Admin has no
  Pundit; the admin controller allows the buttons only when
  `Current.user.traffic_manager?`. Any operator user may open the admin show
  page and play.
- **Video source:** the player plays `broadcast_file` (MPEG-TS, `video/mp2t`),
  the transcoded `.ts`. No second preview encode. Native `<video>` is not used
  for `.ts`. One Stimulus controller,
  `app/javascript/controllers/media_asset_player_controller.js`, is registered
  from both the cabinet bundle and `admin.js`. It feeds the signed blob URL to
  mpegts.js (Media Source Extensions).
  Until the video is `ready` and `broadcast_file` is attached, the page shows
  processing status and no player.
- **Non-video source:** images, audio, PDF, and presentations are not
  transcoded and have no `.ts`. Image is an `<img>`, audio is an `<audio>`
  element, PDF is an iframe, presentation is a download link. All use the
  original `file` attachment. Non-video playback waits until
  `processing_status` is `ready`.
- **Draft vs air:** `Advertising::ValidatesMediaAssets` and `CreateOrder` do
  not grow a content-validation check. Drafts may contain unvalidated assets.
  `ActivateOrder` checks the mark before occupy. `UpdateOrderClips` checks it
  only when the order is active.
- **Order rotations stay:** each order keeps its system rotation, including
  after cancel, so the order page still lists the clip. Revoke deletes
  rotation items only where the rotation has no `advertising_order`.
- **Grandfather:** existing rotation items stay until someone changes the item's
  asset or rotation, or until revoke. Create, `media_asset_id` change, and
  `rotation_id` change require a validated asset unless the destination
  rotation belongs to a draft order.
- **Service themes:** upload creates the `MediaAsset` only and redirects to the
  admin show page. The theme folder gains a picker of already validated service
  assets of that organization that are not already in the folder.

## Domain

### Mark

`MediaAssets::MarkContentValidated.call(media_asset:, user:)`

- Video: require `broadcast_ready?` (`ready` and `broadcast_file` attached).
- Other kinds: require `ready?`.
- If the mark is already present, leave both columns unchanged.
- Otherwise set `content_validated_at` to the current time and
  `content_validated_by` to `user`.

The show page hides the mark button until those readiness rules pass.

### Revoke

`MediaAssets::RevokeContentValidation.call(media_asset:)`

If the mark is absent, return without cancelling orders or deleting items.

Otherwise:

1. Cancel every `active` advertising order whose rotation items include this
   asset, via `Advertising::CancelOrder`. Each cancel commits on its own and
   enqueues playlist regen from `Airtime::Cancel`. Completed, cancelled, and
   draft orders are left alone. `pending_moderation` is not a live transition
   and is not cancelled here.
2. In a following transaction, destroy `rotation_items` for this asset whose
   rotation has no advertising order (catalog rotations and service-theme
   rotations), then clear both validation columns.
3. After that transaction commits, call `Playlists::EnqueueRegen.from_rotation`
   for each rotation touched in step 2.

If step 2 fails after step 1, airtime is already freed and the mark is still
set. A later revoke finds no active orders and finishes the item removal and
column clear.

### Gates

- `Advertising::ActivateOrder` raises `Advertising::Error` before occupy when
  any rotation item's asset lacks the mark. No windows are occupied.
- `Advertising::UpdateOrderClips` raises `Advertising::Error` before write when
  the order is active and any replacement asset lacks the mark. Draft replace
  still accepts unvalidated assets.
- `RotationItem` validates the asset's mark on create and when `media_asset_id`
  or `rotation_id` changes, unless `rotation.advertising_order` is draft.
- `ServiceThemes::AddClip` persists the new service asset and does not create a
  rotation item. A separate admin action creates the rotation item; the model
  validation rejects an unvalidated asset.

An active order that contains the asset among several clips is cancelled as a
whole. The asset is found through `rotation_items`, not through the nullable
`advertising_orders.media_asset_id`.

## UI

Cabinet `GET /media_assets/:id` is a new show page (Slim, daisyUI). The library
filename links there. Download of the original file stays on the show page.

Admin show (`app/views/admin/media_assets/show.html.erb`, Flowbite utilities,
no daisyUI classes) gains the same player and mark block.

Cabinet routes: `GET /media_assets/:id`, plus member `POST mark_content_validation`
and `DELETE revoke_content_validation`. Admin gets the same two member actions
on the existing media-asset resource.

The mark block shows «не проверено» or «проверено» plus `user.display_name` and
the timestamp from `l` (locale formats). Mark and revoke buttons render only for a traffic manager who
is allowed to change that asset. Revoke uses `data-turbo-confirm` and states
that active orders carrying the clip will be cancelled and the clip will leave
catalog and service rotations. Both actions redirect back to the show page
with `status: :see_other` and a flash.

Picker labels append the validated / not-validated text:

- `media_asset_select_label` (cabinet rotation add)
- `advertising_clip_option_label` (order form and clip replace)
- admin rotation-item media select (today shows the id; it gains filename and
  status)

The cabinet library table and the admin media-asset index gain a status
badge or column.

Service-theme show keeps the upload form. After upload the browser lands on
the admin media show page. Each theme folder offers a select of validated
service assets of the theme organization that are not already in that rotation,
and a button that adds the chosen asset.

Cabinet Pundit denial uses the existing `user_not_authorized` redirect and
flash. Admin role denial redirects to the show page with an alert.

Copy lives in `config/locales/mediateca.ru.yml` and `mediateca.en.yml`.

## Error handling

| Situation | Result |
| --- | --- |
| Activate with any unvalidated clip | `Advertising::Error`, no occupy, alert on the order page |
| Replace clips on an active order with any unvalidated clip | `Advertising::Error` before write |
| Replace clips on a draft | Allowed |
| New or moved rotation item without a mark, outside a draft order rotation | Model error, form re-render or alert |
| Mark when already marked | No column changes |
| Revoke when unmarked | No cancels, no item deletes |
| Mark before the playable file is ready | Refused by the service; button hidden |
| Client traffic manager marks a foreign network asset | Pundit denial |
| Non-traffic-manager posts mark/revoke in admin | Redirect with alert |

## Testing

- Mark sets both columns for a ready asset; a second mark does not change them.
  Video without `broadcast_file` and a non-ready asset are refused.
- Revoke cancels an active order, leaves a draft and that draft's system
  rotation items, deletes a catalog item and a service-theme item, clears both
  columns, and enqueues regen for the stripped rotations. Revoke of an
  unmarked asset does not cancel.
- `ActivateOrder` does not occupy when a clip is unmarked, and proceeds when
  every clip is marked.
- `UpdateOrderClips` rejects an unmarked clip on an active order and accepts it
  on a draft.
- Creating a rotation item, or changing its asset or rotation, fails without a
  mark unless the destination rotation is a draft order rotation. An unchanged
  grandfathered item still saves.
- Policy: client traffic manager marks own assets and may show but not mark a
  foreign network asset; manager may show and may not mark; accountant may not
  show. Operator traffic manager may mark any asset.
- Show page: ready video markup references `broadcast_file` and the mpegts
  player; an image references the original file.

## Out of scope

- Backfill of existing assets as validated.
- Removing clips from order system rotations on revoke.
- Cancelling draft or completed orders on revoke.
- A validation history table.
- A separate preview transcode besides `broadcast_file`.
- Opening the rest of the cabinet content sections to traffic managers or
  accountants.
- Resetting the mark when metadata is edited. The uploaded file is not
  replaced in place.
