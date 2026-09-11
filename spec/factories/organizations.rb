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

    trait :with_profile do
      after(:create) do |organization, evaluator|
        create(
          :profile,
          organization: organization,
          business_sphere: evaluator.profile_business_sphere,
          brand: evaluator.profile_brand,
          holding: evaluator.profile_holding
        )
      end
    end

    transient do
      profile_business_sphere { nil }
      profile_brand { nil }
      profile_holding { nil }
    end
  end
end
