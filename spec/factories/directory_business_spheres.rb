# frozen_string_literal: true

# == Schema Information
#
# Table name: directory_business_spheres
#
#  id         :bigint           not null, primary key
#  name       :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_directory_business_spheres_on_lower_name  (lower((name)::text)) UNIQUE
#
FactoryBot.define do
  factory :directory_business_sphere, class: "Directory::BusinessSphere" do
    sequence(:name) { |n| "sphere#{n}" }
  end
end
