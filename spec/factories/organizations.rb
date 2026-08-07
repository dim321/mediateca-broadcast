# frozen_string_literal: true

# == Schema Information
#
# Table name: organizations
#
#  id         :bigint           not null, primary key
#  kind       :string           default("client"), not null
#  name       :string           not null
#  time_zone  :string           default("UTC"), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_organizations_one_operator  (kind) UNIQUE WHERE ((kind)::text = 'operator'::text)
#
FactoryBot.define do
  factory :organization do
    sequence(:name) { |n| "Organization #{n}" }
    time_zone { 'UTC' }

    trait :operator do
      kind { :operator }
    end

    trait :client do
      kind { :client }
    end
  end
end
