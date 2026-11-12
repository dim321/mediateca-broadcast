# frozen_string_literal: true

# == Schema Information
#
# Table name: service_themes
#
#  id                       :bigint           not null, primary key
#  medium                   :string           default("video"), not null
#  name                     :string           not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  close_rotation_id        :bigint           not null
#  header_end_rotation_id   :bigint           not null
#  header_start_rotation_id :bigint           not null
#  neutral_rotation_id      :bigint           not null
#  organization_id          :bigint           not null
#  welcome_rotation_id      :bigint           not null
#
# Indexes
#
#  index_service_themes_on_close_rotation_id         (close_rotation_id)
#  index_service_themes_on_header_end_rotation_id    (header_end_rotation_id)
#  index_service_themes_on_header_start_rotation_id  (header_start_rotation_id)
#  index_service_themes_on_neutral_rotation_id       (neutral_rotation_id)
#  index_service_themes_on_organization_id           (organization_id)
#  index_service_themes_on_organization_id_and_name  (organization_id,name) UNIQUE
#  index_service_themes_on_welcome_rotation_id       (welcome_rotation_id)
#
# Foreign Keys
#
#  fk_rails_...  (close_rotation_id => rotations.id) ON DELETE => restrict
#  fk_rails_...  (header_end_rotation_id => rotations.id) ON DELETE => restrict
#  fk_rails_...  (header_start_rotation_id => rotations.id) ON DELETE => restrict
#  fk_rails_...  (neutral_rotation_id => rotations.id) ON DELETE => restrict
#  fk_rails_...  (organization_id => organizations.id) ON DELETE => restrict
#  fk_rails_...  (welcome_rotation_id => rotations.id) ON DELETE => restrict
#
class ServiceTheme < ApplicationRecord
  ROTATION_ROLES = {
    header_start: "service_header_start",
    header_end: "service_header_end",
    welcome: "service_welcome",
    close: "service_close"
  }.freeze

  FOLDER_ROLES = (ROTATION_ROLES.keys + [ :neutral ]).freeze

  CONTENT_TYPE_BY_ROLE = FOLDER_ROLES.index_with { |role|
    role == :neutral ? "neutral" : "service"
  }.freeze

  CLIP_CONTENT_KINDS = {
    "video" => %w[video].freeze,
    "audio" => %w[audio].freeze
  }.freeze

  FILE_ACCEPT = {
    "video" => "video/mp4,video/webm,video/mpeg,.mpg,.mpeg",
    "audio" => "audio/mpeg,audio/mp3,audio/wav,audio/x-wav,.mp3,.wav"
  }.freeze

  enum :medium, { video: "video", audio: "audio" }, default: :video

  def self.ransackable_attributes(_auth_object = nil)
    %w[id name medium created_at updated_at organization_id]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[organization header_start_rotation header_end_rotation welcome_rotation close_rotation neutral_rotation]
  end

  belongs_to :organization
  belongs_to :header_start_rotation, class_name: "Rotation"
  belongs_to :header_end_rotation, class_name: "Rotation"
  belongs_to :welcome_rotation, class_name: "Rotation"
  belongs_to :close_rotation, class_name: "Rotation"
  belongs_to :neutral_rotation, class_name: "Rotation"

  has_many :broadcast_portraits, dependent: :restrict_with_exception
  has_many :broadcast_portrait_blocks, dependent: :restrict_with_exception

  validates :name, presence: true, uniqueness: { scope: :organization_id, case_sensitive: true }
  validates :medium, presence: true
  validate :organization_must_be_operator
  validate :medium_must_not_change, on: :update

  def rotations
    [
      header_start_rotation,
      header_end_rotation,
      welcome_rotation,
      close_rotation,
      neutral_rotation
    ]
  end

  def processing_clips?
    MediaAsset.joins(:rotation_items).where(
      rotation_items: { rotation_id: rotations.map(&:id) },
      processing_status: %w[pending processing]
    ).exists?
  end

  def rotation_for(role)
    case role.to_sym
    when :header_start, :service_header_start then header_start_rotation
    when :header_end, :service_header_end then header_end_rotation
    when :welcome, :service_welcome then welcome_rotation
    when :close, :service_close then close_rotation
    when :neutral then neutral_rotation
    end
  end

  def self.content_type_for_role(role)
    CONTENT_TYPE_BY_ROLE.fetch(role.to_sym)
  rescue KeyError
    nil
  end

  def self.clip_content_kinds_for(medium)
    CLIP_CONTENT_KINDS.fetch(medium.to_s)
  end

  def clip_content_kinds
    self.class.clip_content_kinds_for(medium)
  end

  def accepts_content_kind?(kind)
    clip_content_kinds.include?(kind.to_s)
  end

  def file_accept
    FILE_ACCEPT.fetch(medium)
  end

  private

  def organization_must_be_operator
    return if organization&.operator?

    errors.add(:organization, :must_be_operator)
  end

  def medium_must_not_change
    return unless medium_changed?

    errors.add(:medium, :immutable)
  end
end
