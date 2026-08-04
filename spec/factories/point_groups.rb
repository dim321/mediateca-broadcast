# frozen_string_literal: true

# == Schema Information
#
# Table name: point_groups
#
#  id              :bigint           not null, primary key
#  name            :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  organization_id :bigint           not null
#
# Indexes
#
#  index_point_groups_on_organization_id           (organization_id)
#  index_point_groups_on_organization_id_and_name  (organization_id,name) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#
FactoryBot.define do
  factory :point_group do
    organization
    sequence(:name) { |n| "Point group #{n}" }
  end
end
