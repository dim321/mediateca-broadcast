# frozen_string_literal: true

# == Schema Information
#
# Table name: airtime_quotas
#
#  id                       :bigint           not null, primary key
#  content_type             :string
#  ends_at                  :datetime         not null
#  seconds_remaining        :integer          not null
#  seconds_total            :integer          not null
#  starts_at                :datetime         not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  broadcast_point_group_id :bigint           not null
#
# Indexes
#
#  index_airtime_quotas_on_broadcast_point_group_id  (broadcast_point_group_id)
#  index_airtime_quotas_on_group_and_window          (broadcast_point_group_id,starts_at,ends_at)
#
# Foreign Keys
#
#  fk_rails_...  (broadcast_point_group_id => broadcast_point_groups.id)
#
class AirtimeQuota < ApplicationRecord
  self.table_name = 'airtime_quotas'

  belongs_to :broadcast_point_group
  has_many :airtime_bookings, dependent: :restrict_with_exception

  validates :starts_at, :ends_at, :seconds_total, :seconds_remaining, presence: true
  validates :seconds_total, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :seconds_remaining, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :ends_after_starts
  validate :remaining_not_above_total

  before_validation :sync_remaining_on_create, on: :create

  def covers?(window_starts_at, window_ends_at)
    starts_at <= window_starts_at && ends_at >= window_ends_at
  end

  private

  def sync_remaining_on_create
    self.seconds_remaining = seconds_total if seconds_remaining.nil? && seconds_total.present?
  end

  def ends_after_starts
    return if starts_at.blank? || ends_at.blank?
    return if ends_at > starts_at

    errors.add(:ends_at, :must_be_after_starts)
  end

  def remaining_not_above_total
    return if seconds_total.blank? || seconds_remaining.blank?
    return if seconds_remaining <= seconds_total

    errors.add(:seconds_remaining, :less_than_or_equal_to, count: seconds_total)
  end
end
