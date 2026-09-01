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
#  broadcast_point_group_id :bigint           not null
#  organization_id          :bigint           not null
#
# Indexes
#
#  idx_on_organization_id_starts_at_ends_at_f3b48d3772  (organization_id,starts_at,ends_at)
#  index_airtime_bookings_on_broadcast_point_group_id   (broadcast_point_group_id)
#  index_airtime_bookings_on_organization_id            (organization_id)
#  index_airtime_bookings_on_status                     (status)
#
# Foreign Keys
#
#  fk_rails_...  (broadcast_point_group_id => broadcast_point_groups.id)
#  fk_rails_...  (organization_id => organizations.id)
#
FactoryBot.define do
  factory :airtime_booking do
    organization
    broadcast_point_group { association :broadcast_point_group, organization: organization }
    starts_at { Time.utc(2026, 8, 10, 10, 0, 0) }
    ends_at { Time.utc(2026, 8, 10, 10, 10, 0) }
    seconds { 600 }
    status { :confirmed }

    after(:build) do |booking|
      group = booking.broadcast_point_group
      next if group.blank? || group.screens.exists?

      screen = create(:screen)
      create(:broadcast_point_group_membership, broadcast_point_group: group, screen: screen)
    end

    trait :cancelled do
      status { :cancelled }
    end
  end
end
