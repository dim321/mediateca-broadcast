# frozen_string_literal: true

# == Schema Information
#
# Table name: broadcast_point_groups
#
#  id                       :bigint           not null, primary key
#  commercial_quota_percent :integer
#  commercial_quota_period  :string
#  name                     :string           not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  organization_id          :bigint           not null
#
# Indexes
#
#  index_broadcast_point_groups_on_organization_id           (organization_id)
#  index_broadcast_point_groups_on_organization_id_and_name  (organization_id,name) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#
class BroadcastPointGroup < ApplicationRecord
  belongs_to :organization

  has_many :broadcast_point_group_memberships, dependent: :destroy
  has_many :screens, through: :broadcast_point_group_memberships
  has_many :media_plans, dependent: :restrict_with_exception
  has_many :airtime_bookings, dependent: :restrict_with_exception
  has_many :advertising_order_lines, dependent: :restrict_with_exception

  enum :commercial_quota_period, {
    hour: "hour",
    day: "day"
  }, validate: { allow_nil: true }

  validates :name, presence: true, uniqueness: { scope: :organization_id }
  validates :commercial_quota_percent,
    numericality: { only_integer: true, in: 1..100 },
    allow_nil: true
  validate :commercial_quota_pair_consistency
  validate :commercial_quota_assignment_gates, if: :commercial_quota_assigned?

  scope :owner_homogeneous, lambda {
    left_joins(:screens)
      .group("broadcast_point_groups.id")
      .having("COUNT(screens.id) > 0")
      .having("COUNT(screens.id) = COUNT(screens.owner_organization_id)")
      .having("MIN(screens.owner_organization_id) = MAX(screens.owner_organization_id)")
      .having("MIN(screens.owner_organization_id) = broadcast_point_groups.organization_id")
  }

  def self.commercial_eligible_groups_for(placer_organization)
    owner_homogeneous.where.not(organization_id: placer_organization.id)
  end

  def commercial_quota_assigned?
    commercial_quota_percent.present? || commercial_quota_period.present?
  end

  def commercial_quota_configured?
    commercial_quota_percent.present? && commercial_quota_period.present?
  end

  def owner_homogeneous?
    ids = screens.map(&:owner_organization_id).uniq
    ids.size == 1 && ids.first.present? && ids.first == organization_id
  end

  def locations_with_operating_hours?
    location_ids = screens.joins(:station).distinct.pluck("stations.location_id")
    return false if location_ids.empty?

    Location.where(id: location_ids).all?(&:operating_hours_configured?)
  end

  private

  def commercial_quota_pair_consistency
    return if commercial_quota_percent.blank? && commercial_quota_period.blank?
    return if commercial_quota_percent.present? && commercial_quota_period.present?

    errors.add(:base, :commercial_quota_incomplete)
  end

  def commercial_quota_assignment_gates
    # Empty groups may store intended quota; gates apply once screens exist.
    return if screens.none?

    unless owner_homogeneous?
      errors.add(:base, :commercial_quota_requires_homogeneous_owner)
      return
    end

    return if locations_with_operating_hours?

    errors.add(:base, :commercial_quota_requires_operating_hours)
  end
end
