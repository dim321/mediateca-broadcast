# frozen_string_literal: true

class MediaAsset < ApplicationRecord
  belongs_to :organization
  belongs_to :uploaded_by, class_name: "User", optional: true

  has_many :playlist_items, dependent: :restrict_with_exception
  has_many :playlists, through: :playlist_items

  has_one_attached :file
  has_one_attached :preview

  ALLOWED_CONTENT_TYPES = {
    "video/mp4" => "video",
    "video/webm" => "video",
    "image/png" => "image",
    "image/jpeg" => "image",
    "image/jpg" => "image",
    "image/gif" => "image",
    "image/webp" => "image",
    "audio/mpeg" => "audio",
    "audio/mp3" => "audio",
    "audio/wav" => "audio",
    "audio/x-wav" => "audio",
    "application/pdf" => "document",
    "application/vnd.ms-powerpoint" => "presentation",
    "application/vnd.openxmlformats-officedocument.presentationml.presentation" => "presentation"
  }.freeze

  enum :processing_status, {
    pending: "pending",
    processing: "processing",
    ready: "ready",
    failed: "failed"
  }, default: :pending

  scope :ready, -> { where(processing_status: :ready) }

  enum :content_kind, {
    video: "video",
    audio: "audio",
    image: "image",
    document: "document",
    presentation: "presentation"
  }

  validates :organization, presence: true
  validates :content_kind, presence: true, on: :create
  validate :file_must_be_present_and_allowed, on: :create

  before_validation :assign_content_kind_from_file, on: :create

  after_create_commit :enqueue_metadata_processing

  after_update_commit :broadcast_card_refresh, if: :should_broadcast_card_refresh?

  def display_duration
    return nil if duration_seconds.blank?

    duration_seconds
  end

  private

  def file_must_be_present_and_allowed
    errors.add(:file, :blank) unless file.attached?
    return if errors[:file].any?

    return if ALLOWED_CONTENT_TYPES.key?(file.content_type)

    errors.add(:file, :unsupported_type)
  end

  def assign_content_kind_from_file
    return unless file.attached?

    kind = ALLOWED_CONTENT_TYPES[file.content_type]
    self.content_kind = kind if kind.present?
  end

  def enqueue_metadata_processing
    ProcessMediaMetadataJob.perform_later(id)
  end

  def should_broadcast_card_refresh?
    saved_change_to_processing_status? ||
      saved_change_to_duration_seconds? ||
      saved_change_to_metadata?
  end

  def broadcast_card_refresh
    broadcast_replace_later_to [ organization, :media_library ],
      target: ActionView::RecordIdentifier.dom_id(self, :card),
      partial: "media_assets/media_asset",
      locals: { media_asset: self }
  end
end
