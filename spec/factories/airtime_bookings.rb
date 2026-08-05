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
FactoryBot.define do
  factory :airtime_booking do
    organization
    broadcast_point_group { association :broadcast_point_group, organization: organization }
    airtime_quota do
      association :airtime_quota, :with_screen, broadcast_point_group: broadcast_point_group
    end
    starts_at { Time.utc(2026, 8, 10, 10, 0, 0) }
    ends_at { Time.utc(2026, 8, 10, 10, 10, 0) }
    seconds { 600 }
    status { :confirmed }

    trait :cancelled do
      status { :cancelled }
    end
  end
end
