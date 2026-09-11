# frozen_string_literal: true

module MediaAssetsHelper
  def media_asset_source_link(media_asset)
    return "—" unless media_asset.file.attached?

    link_to(
      media_asset.file.filename.to_s,
      rails_blob_path(media_asset.file, disposition: :attachment),
      class: "link link-hover"
    )
  end

  def media_asset_broadcast_cell(media_asset)
    if media_asset.broadcast_file.attached?
      link_to(
        media_asset.broadcast_file.filename.to_s,
        rails_blob_path(media_asset.broadcast_file, disposition: :attachment),
        class: "link link-hover"
      )
    else
      media_asset_broadcast_placeholder(media_asset)
    end
  end

  def media_asset_broadcast_label(media_asset)
    if media_asset.broadcast_file.attached?
      media_asset.broadcast_file.filename.to_s
    else
      media_asset_broadcast_placeholder(media_asset)
    end
  end

  def media_asset_broadcast_placeholder(media_asset)
    return t("media_assets.index.broadcast_na") unless media_asset.video?

    if media_asset.pending? || media_asset.processing?
      t("media_assets.index.broadcast_processing")
    else
      media_asset.processing_status.to_s.humanize
    end
  end

  def media_asset_select_label(media_asset)
    source = media_asset.file.attached? ? media_asset.file.filename.to_s : "—"
    "#{source} · #{media_asset_broadcast_label(media_asset)}"
  end
end
