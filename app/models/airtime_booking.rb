# frozen_string_literal: true

# == Schema Information
#
# Table name: airtime_bookings
#
#  id                       :bigint           not null, primary key
#  ends_at                  :datetime         not null
#  seconds                  :integer          not null
#  starts_at                :datetime         not null
#  status                   :string           default("confirmed"), not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  airtime_quota_id         :bigint           not null
#  broadcast_point_group_id :bigint           not null
#  organization_id          :bigint           not null
#
# Indexes
#
#  idx_on_organization_id_starts_at_ends_at_f3b48d3772  (organization_id,starts_at,ends_at)
#  index_airtime_bookings_on_airtime_quota_id           (airtime_quota_id)
#  index_airtime_bookings_on_broadcast_point_group_id   (broadcast_point_group_id)
#  index_airtime_bookings_on_organization_id            (organization_id)
#  index_airtime_bookings_on_status                     (status)
#
# Foreign Keys
#
#  fk_rails_...  (airtime_quota_id => airtime_quotas.id)
#  fk_rails_...  (broadcast_point_group_id => broadcast_point_groups.id)
#  fk_rails_...  (organization_id => organizations.id)
#
class AirtimeBooking < ApplicationRecord
  belongs_to :airtime_quota
  belongs_to :organization
  belongs_to :broadcast_point_group
  has_many :media_plans, dependent: :restrict_with_exception

  enum :status, {
    confirmed: 'confirmed',
    cancelled: 'cancelled'
  }, default: :confirmed

  validates :starts_at, :ends_at, :seconds, presence: true
  validates :seconds, numericality: { only_integer: true, greater_than: 0 }
  validate :ends_after_starts

  def covers_plan?(plan)
    plan.starts_at >= starts_at &&
      plan.ends_at <= ends_at &&
      plan.broadcast_point_group_id == broadcast_point_group_id &&
      plan.organization_id == organization_id
  end

  private

  def ends_after_starts
    return if starts_at.blank? || ends_at.blank?
    return if ends_at > starts_at

    errors.add(:ends_at, :must_be_after_starts)
  end
end
