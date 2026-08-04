# frozen_string_literal: true

# == Schema Information
#
# Table name: broadcast_points
#
#  id                  :bigint           not null, primary key
#  city                :string
#  device_token_digest :string
#  name                :string           not null
#  status              :string           default("unknown"), not null
#  time_zone           :string
#  venue_label         :string
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  organization_id     :bigint           not null
#
# Indexes
#
#  index_broadcast_points_on_organization_id             (organization_id)
#  index_broadcast_points_on_organization_id_and_status  (organization_id,status)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#
FactoryBot.define do
  factory :broadcast_point do
    organization
    sequence(:name) { |n| "Broadcast point #{n}" }
  end
end
