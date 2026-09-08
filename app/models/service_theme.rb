# frozen_string_literal: true

# == Schema Information
#
# Table name: service_themes
#
#  id                       :bigint           not null, primary key
#  name                     :string           not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  close_rotation_id        :bigint           not null
#  header_end_rotation_id   :bigint           not null
#  header_start_rotation_id :bigint           not null
#  organization_id          :bigint           not null
#  welcome_rotation_id      :bigint           not null
#
# Indexes
#
#  index_service_themes_on_close_rotation_id         (close_rotation_id)
#  index_service_themes_on_header_end_rotation_id    (header_end_rotation_id)
#  index_service_themes_on_header_start_rotation_id  (header_start_rotation_id)
#  index_service_themes_on_organization_id           (organization_id)
#  index_service_themes_on_organization_id_and_name  (organization_id,name) UNIQUE
#  index_service_themes_on_welcome_rotation_id       (welcome_rotation_id)
#
# Foreign Keys
#
#  fk_rails_...  (close_rotation_id => rotations.id) ON DELETE => restrict
#  fk_rails_...  (header_end_rotation_id => rotations.id) ON DELETE => restrict
#  fk_rails_...  (header_start_rotation_id => rotations.id) ON DELETE => restrict
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

  def self.ransackable_attributes(_auth_object = nil)
    %w[id name created_at updated_at organization_id]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[organization header_start_rotation header_end_rotation welcome_rotation close_rotation]
  end

  belongs_to :organization
  belongs_to :header_start_rotation, class_name: "Rotation"
  belongs_to :header_end_rotation, class_name: "Rotation"
  belongs_to :welcome_rotation, class_name: "Rotation"
  belongs_to :close_rotation, class_name: "Rotation"

  has_many :broadcast_portraits, dependent: :restrict_with_exception
  has_many :broadcast_portrait_blocks, dependent: :restrict_with_exception

  validates :name, presence: true, uniqueness: { scope: :organization_id, case_sensitive: true }
  validate :organization_must_be_operator

  def rotations
    [ header_start_rotation, header_end_rotation, welcome_rotation, close_rotation ]
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
    end
  end

  private

  def organization_must_be_operator
    return if organization&.operator?

    errors.add(:organization, :must_be_operator)
  end
end
