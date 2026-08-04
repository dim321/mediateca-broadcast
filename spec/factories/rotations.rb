# frozen_string_literal: true

# == Schema Information
#
# Table name: rotations
#
#  id              :bigint           not null, primary key
#  name            :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  organization_id :bigint           not null
#
# Indexes
#
#  index_rotations_on_organization_id           (organization_id)
#  index_rotations_on_organization_id_and_name  (organization_id,name) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#
FactoryBot.define do
  factory :rotation do
    organization
    sequence(:name) { |n| "Rotation #{n}" }
  end
end
