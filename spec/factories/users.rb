# frozen_string_literal: true

# == Schema Information
#
# Table name: users
#
#  id              :bigint           not null, primary key
#  email           :string           not null
#  first_name      :string
#  job_title       :string
#  last_name       :string
#  location        :string
#  password_digest :string           not null
#  phone           :string
#  role            :string           default("manager"), not null
#  status          :string           default("active"), not null
#  telegram        :string
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  organization_id :bigint           not null
#
# Indexes
#
#  index_users_on_email            (email) UNIQUE
#  index_users_on_organization_id  (organization_id)
#  index_users_on_role             (role)
#  index_users_on_status           (status)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#
FactoryBot.define do
  factory :user do
    organization
    sequence(:email) { |n| "user#{n}@example.com" }
    password { 'password123456' }
    role { :manager }
    status { :active }

    trait :manager do
      role { :manager }
    end

    trait :accountant do
      role { :accountant }
    end

    trait :administrator do
      role { :administrator }
    end

    trait :blocked do
      status { :blocked }
    end

    trait :with_profile do
      first_name { 'Ivan' }
      last_name { 'Petrov' }
      phone { '+79001234567' }
      job_title { 'Manager' }
      telegram { '@ivan' }
      location { 'Moscow' }
    end
  end
end
