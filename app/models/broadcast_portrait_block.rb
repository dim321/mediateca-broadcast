# frozen_string_literal: true

# == Schema Information
#
# Table name: broadcast_portrait_blocks
#
#  id                    :bigint           not null, primary key
#  kind                  :string           not null
#  pick_strategy         :string
#  position              :integer          not null
#  time_of_day           :time
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  broadcast_portrait_id :bigint           not null
#  rotation_id           :bigint
#  service_theme_id      :bigint
#
# Indexes
#
#  index_broadcast_portrait_blocks_on_broadcast_portrait_id  (broadcast_portrait_id)
#  index_broadcast_portrait_blocks_on_portrait_and_position  (broadcast_portrait_id,position) UNIQUE
#  index_broadcast_portrait_blocks_on_rotation_id            (rotation_id)
#  index_broadcast_portrait_blocks_on_service_theme_id       (service_theme_id)
#
# Foreign Keys
#
#  fk_rails_...  (broadcast_portrait_id => broadcast_portraits.id) ON DELETE => cascade
#  fk_rails_...  (rotation_id => rotations.id) ON DELETE => restrict
#  fk_rails_...  (service_theme_id => service_themes.id) ON DELETE => restrict
#
class BroadcastPortraitBlock < ApplicationRecord
  def self.ransackable_attributes(_auth_object = nil)
    %w[id position kind pick_strategy time_of_day created_at updated_at broadcast_portrait_id rotation_id service_theme_id]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[broadcast_portrait rotation service_theme]
  end

  belongs_to :broadcast_portrait, inverse_of: :blocks
  belongs_to :rotation, optional: true
  belongs_to :service_theme, optional: true

  enum :kind, {
    commercial: "commercial",
    filler: "filler",
    insertion: "insertion",
    service_header_start: "service_header_start",
    service_header_end: "service_header_end",
    service_welcome: "service_welcome",
    service_close: "service_close"
  }

  enum :pick_strategy, {
    sequential: "sequential",
    random: "random",
    ordered: "ordered"
  }

  validates :kind, presence: true
  validates :position, numericality: { only_integer: true, greater_than: 0 },
    uniqueness: { scope: :broadcast_portrait_id }
  validate :service_theme_must_exist
  validate :fields_match_kind

  before_validation :assign_rotation_from_service_theme

  def service_kind?
    ServiceTheme::ROTATION_ROLES.value?(kind)
  end

  private

  def assign_rotation_from_service_theme
    return unless service_kind? && service_theme

    self.rotation = service_theme.rotation_for(kind)
  end

  def service_theme_must_exist
    return if service_theme_id.blank?
    return if service_theme.present?

    errors.add(:service_theme_id, :must_be_theme)
  end

  def fields_match_kind
    case kind
    when "commercial"
      reject_rotation
      reject_service_theme
      errors.add(:pick_strategy, :present) if pick_strategy.present?
      errors.add(:time_of_day, :present) if time_of_day.present?
    when "service_header_start", "service_header_end"
      errors.add(:time_of_day, :present) if time_of_day.present?
      if service_source_present?
        errors.add(:pick_strategy, :blank) if pick_strategy.blank?
      elsif pick_strategy.present?
        errors.add(:pick_strategy, :present)
      end
    when "service_welcome", "service_close"
      errors.add(:service_theme_id, :blank) if service_theme.blank? && rotation.blank?
      errors.add(:rotation_id, :blank) if rotation.blank?
      errors.add(:pick_strategy, :blank) if pick_strategy.blank?
      errors.add(:time_of_day, :present) if time_of_day.present?
    when "filler"
      reject_service_theme
      errors.add(:rotation_id, :blank) if rotation.blank?
      errors.add(:pick_strategy, :blank) if pick_strategy.blank?
      errors.add(:time_of_day, :present) if time_of_day.present?
    when "insertion"
      reject_service_theme
      errors.add(:rotation_id, :blank) if rotation.blank?
      errors.add(:time_of_day, :blank) if time_of_day.blank?
    end
  end

  def service_source_present?
    service_theme.present? || rotation.present?
  end

  def reject_rotation
    errors.add(:rotation_id, :present) if rotation_id.present? || rotation.present?
  end

  def reject_service_theme
    errors.add(:service_theme_id, :present) if service_theme_id.present? || service_theme.present?
  end
end
