# frozen_string_literal: true

require 'rails_helper'

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
RSpec.describe AirtimeQuota, type: :model do
  it 'syncs seconds_remaining from seconds_total on create' do
    group = create(:broadcast_point_group)
    quota = described_class.create!(
      broadcast_point_group: group,
      starts_at: Time.utc(2026, 8, 10),
      ends_at: Time.utc(2026, 8, 11),
      seconds_total: 1_200
    )

    expect(quota.seconds_remaining).to eq(1_200)
  end

  it 'rejects ends_at before starts_at' do
    quota = build(
      :airtime_quota,
      starts_at: Time.utc(2026, 8, 11),
      ends_at: Time.utc(2026, 8, 10)
    )
    expect(quota).not_to be_valid
  end
end
