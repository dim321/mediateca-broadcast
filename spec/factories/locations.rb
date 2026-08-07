# frozen_string_literal: true

# == Schema Information
#
# Table name: locations
#
#  id         :bigint           not null, primary key
#  name       :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_locations_on_name  (name) UNIQUE
#
FactoryBot.define do
  factory :location do
    sequence(:name) { |n| "Location #{n}" }
  end
end
