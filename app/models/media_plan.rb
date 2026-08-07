# frozen_string_literal: true

# == Schema Information
#
# Table name: media_plans
#
#  id                       :bigint           not null, primary key
#  ends_at                  :datetime         not null
#  starts_at                :datetime         not null
#  status                   :string           default("active"), not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  airtime_booking_id       :bigint           not null
#  broadcast_point_group_id :bigint           not null
#  organization_id          :bigint           not null
#  rotation_id              :bigint           not null
#
# Indexes
#
#  index_media_plans_on_airtime_booking_id                         (airtime_booking_id)
#  index_media_plans_on_broadcast_point_group_id                   (broadcast_point_group_id)
#  index_media_plans_on_organization_id                            (organization_id)
#  index_media_plans_on_organization_id_and_starts_at_and_ends_at  (organization_id,starts_at,ends_at)
#  index_media_plans_on_rotation_id                                (rotation_id)
#  index_media_plans_on_status                                     (status)
#
# Foreign Keys
#
#  fk_rails_...  (airtime_booking_id => airtime_bookings.id) ON DELETE => restrict
#  fk_rails_...  (broadcast_point_group_id => broadcast_point_groups.id) ON DELETE => restrict
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (rotation_id => rotations.id) ON DELETE => restrict
#
class MediaPlan < ApplicationRecord
  belongs_to :organization
  belongs_to :rotation
  belongs_to :broadcast_point_group
  belongs_to :airtime_booking

  enum :status, {
    active: "active",
    invalidated: "invalidated",
    cancelled: "cancelled"
  }, default: :active

  validates :starts_at, :ends_at, presence: true
  validate :ends_after_starts
  validate :rotation_matches_organization
  validate :broadcast_point_group_matches_organization
  validate :broadcast_point_group_has_screens
  validate :rotation_is_broadcast_ready
  validate :booking_must_be_confirmed
  validate :booking_matches_organization_and_group
  validate :plan_within_booking_window
  validate :no_overlapping_media_plans, if: :active?

  private

  def ends_after_starts
    return if starts_at.blank? || ends_at.blank?
    return if ends_at > starts_at

    errors.add(:ends_at, :must_be_after_starts)
  end

  def rotation_matches_organization
    return if rotation.blank? || organization.blank?
    return if rotation.organization_id == organization_id

    errors.add(:rotation, :wrong_organization)
  end

  def broadcast_point_group_matches_organization
    return if broadcast_point_group.blank? || organization.blank?
    return if broadcast_point_group.organization_id == organization_id

    errors.add(:broadcast_point_group, :wrong_organization)
  end

  def broadcast_point_group_has_screens
    return if broadcast_point_group.blank?
    return if conflict_screen_ids.any?

    errors.add(:broadcast_point_group, :must_have_screens)
  end

  def rotation_is_broadcast_ready
    return if rotation.blank?
    return if rotation.ordered_items.all? { |item| item.media_asset.broadcast_ready? }

    errors.add(:rotation, :not_broadcast_ready)
  end

  def booking_must_be_confirmed
    return if airtime_booking.blank?
    return if airtime_booking.confirmed?

    errors.add(:airtime_booking, :must_be_confirmed)
  end

  def booking_matches_organization_and_group
    return if airtime_booking.blank? || organization.blank?
    errors.add(:airtime_booking, :wrong_organization) unless airtime_booking.organization_id == organization_id
    return if broadcast_point_group.blank?
    return if airtime_booking.broadcast_point_group_id == broadcast_point_group_id

    errors.add(:airtime_booking, :wrong_group)
  end

  def plan_within_booking_window
    return if airtime_booking.blank? || starts_at.blank? || ends_at.blank?
    return if airtime_booking.covers_plan?(self)

    errors.add(:base, :outside_booking_window)
  end

  def no_overlapping_media_plans
    return if broadcast_point_group.blank? || starts_at.blank? || ends_at.blank?
    return if conflict_screen_ids.blank?

    conflicts = Scheduling::MediaPlanConflictDetector.call(
      starts_at: starts_at,
      ends_at: ends_at,
      screen_ids: conflict_screen_ids,
      organization_id: organization_id,
      exclude_media_plan: persisted? ? self : nil
    )
    errors.add(:base, :overlaps_existing) if conflicts.any?
  end

  def conflict_screen_ids
    @conflict_screen_ids ||= broadcast_point_group.screen_ids
  end
end
