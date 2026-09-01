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
FactoryBot.define do
  factory :broadcast_point_group do
    organization
    sequence(:name) { |n| "Screen group #{n}" }
  end
end
