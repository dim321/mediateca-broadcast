# frozen_string_literal: true

# == Schema Information
#
# Table name: media_assets
#
#  id                :bigint           not null, primary key
#  content_kind      :string           not null
#  content_type      :string           not null
#  duration_seconds  :integer
#  metadata          :jsonb            not null
#  processing_status :string           default("pending"), not null
#  visibility        :string           not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  organization_id   :bigint           not null
#  uploaded_by_id    :bigint
#
# Indexes
#
#  index_media_assets_on_content_type                           (content_type)
#  index_media_assets_on_organization_id                        (organization_id)
#  index_media_assets_on_organization_id_and_created_at         (organization_id,created_at DESC)
#  index_media_assets_on_organization_id_and_processing_status  (organization_id,processing_status)
#  index_media_assets_on_uploaded_by_id                         (uploaded_by_id)
#  index_media_assets_on_visibility                             (visibility)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (uploaded_by_id => users.id) ON DELETE => nullify
#
class MediaAsset < ApplicationRecord
  MAX_FILE_SIZE = 1.gigabyte

  belongs_to :organization
  belongs_to :uploaded_by, class_name: "User", optional: true

  has_many :rotation_items, dependent: :restrict_with_exception
  has_many :rotations, through: :rotation_items
  has_many :play_logs, dependent: :restrict_with_exception

  has_one_attached :file
  has_one_attached :preview
  has_one_attached :broadcast_file

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

  # Commercial content class (R11) — distinct from MIME content_kind.
  # No Ruby default: LK upload must choose explicitly (DB default only backfills legacy rows).
  enum :content_type, {
    own: "own",
    commercial: "commercial",
    neutral: "neutral",
    service: "service"
  }, prefix: true

  # Catalog sharing (R12/KTD9). prefix avoids clashing with belongs_to :organization.
  enum :visibility, {
    organization: "organization",
    network: "network"
  }, prefix: true

  validates :organization, presence: true
  validates :content_kind, presence: true, on: :create
  validates :content_type, presence: true
  validates :visibility, presence: true
  validate :file_must_be_present_and_allowed, on: :create
  validate :file_size_within_limit, on: :create

  before_validation :assign_content_kind_from_file, on: :create

  after_create_commit :enqueue_metadata_processing

  after_update_commit :broadcast_card_refresh, if: :should_broadcast_card_refresh?

  def display_duration
    return nil if duration_seconds.blank?

    duration_seconds
  end

  def broadcast_ready?
    return false unless ready?
    return true unless video?

    broadcast_file.attached?
  end

  def broadcast_delivery_attachment
    return unless ready?
    return broadcast_file if video? && broadcast_file.attached?
    return if video?

    file if file.attached?
  end

  private

  def file_must_be_present_and_allowed
    errors.add(:file, :blank) unless file.attached?
    return if errors[:file].any?

    return if ALLOWED_CONTENT_TYPES.key?(file.content_type)

    errors.add(:file, :unsupported_type)
  end

  def file_size_within_limit
    return unless file.attached?
    return if file.byte_size <= MAX_FILE_SIZE

    errors.add(:file, :too_large, max_size: MAX_FILE_SIZE)
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
