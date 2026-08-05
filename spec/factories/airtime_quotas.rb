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
FactoryBot.define do
  factory :airtime_quota do
    broadcast_point_group
    starts_at { Time.utc(2026, 8, 10, 0, 0, 0) }
    ends_at { Time.utc(2026, 8, 11, 0, 0, 0) }
    seconds_total { 3_600 }
    seconds_remaining { seconds_total }

    trait :with_screen do
      after(:build) do |quota|
        next if quota.broadcast_point_group.screens.exists?

        screen = create(:screen)
        create(
          :broadcast_point_group_membership,
          broadcast_point_group: quota.broadcast_point_group,
          screen: screen
        )
      end
    end
  end
end
