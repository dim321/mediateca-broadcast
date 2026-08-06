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
FactoryBot.define do
  factory :media_plan do
    organization
    rotation { association :rotation, organization: organization }
    broadcast_point_group { association :broadcast_point_group, organization: organization }
    starts_at { Time.utc(2026, 8, 10, 10, 0, 0) }
    ends_at { Time.utc(2026, 8, 10, 12, 0, 0) }
    status { :active }

    after(:build) do |media_plan|
      group = media_plan.broadcast_point_group
      if group && !group.screens.exists?
        screen = create(:screen)
        create(:broadcast_point_group_membership, broadcast_point_group: group, screen: screen)
      end

      next if media_plan.airtime_booking.present?
      next if group.blank? || media_plan.organization.blank?
      next if media_plan.starts_at.blank? || media_plan.ends_at.blank?

      seconds = (media_plan.ends_at - media_plan.starts_at).to_i
      media_plan.airtime_booking = create(
        :airtime_booking,
        organization: media_plan.organization,
        broadcast_point_group: group,
        starts_at: media_plan.starts_at,
        ends_at: media_plan.ends_at,
        seconds: seconds
      )
    end
  end
end
