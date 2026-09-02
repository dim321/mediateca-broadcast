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
#
# Indexes
#
#  index_broadcast_portrait_blocks_on_broadcast_portrait_id  (broadcast_portrait_id)
#  index_broadcast_portrait_blocks_on_portrait_and_position  (broadcast_portrait_id,position) UNIQUE
#  index_broadcast_portrait_blocks_on_rotation_id            (rotation_id)
#
# Foreign Keys
#
#  fk_rails_...  (broadcast_portrait_id => broadcast_portraits.id) ON DELETE => cascade
#  fk_rails_...  (rotation_id => rotations.id) ON DELETE => restrict
#
class BroadcastPortraitBlock < ApplicationRecord
  def self.ransackable_attributes(_auth_object = nil)
    %w[id position kind pick_strategy time_of_day created_at updated_at broadcast_portrait_id rotation_id]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[broadcast_portrait rotation]
  end

  belongs_to :broadcast_portrait, inverse_of: :blocks
  belongs_to :rotation, optional: true

  enum :kind, {
    commercial: "commercial",
    filler: "filler",
    insertion: "insertion",
    service_header_start: "service_header_start",
    service_header_end: "service_header_end"
  }

  enum :pick_strategy, {
    sequential: "sequential",
    random: "random",
    ordered: "ordered"
  }

  validates :kind, presence: true
  validates :position, numericality: { only_integer: true, greater_than: 0 },
    uniqueness: { scope: :broadcast_portrait_id }
  validate :fields_match_kind

  private

  def fields_match_kind
    case kind
    when "commercial"
      errors.add(:rotation_id, :present) if rotation_id.present? || rotation.present?
      errors.add(:pick_strategy, :present) if pick_strategy.present?
      errors.add(:time_of_day, :present) if time_of_day.present?
    when "service_header_start", "service_header_end"
      errors.add(:pick_strategy, :present) if pick_strategy.present?
      errors.add(:time_of_day, :present) if time_of_day.present?
    when "filler"
      errors.add(:rotation_id, :blank) if rotation.blank?
      errors.add(:pick_strategy, :blank) if pick_strategy.blank?
      errors.add(:time_of_day, :present) if time_of_day.present?
    when "insertion"
      errors.add(:rotation_id, :blank) if rotation.blank?
      errors.add(:time_of_day, :blank) if time_of_day.blank?
    end
  end
end
