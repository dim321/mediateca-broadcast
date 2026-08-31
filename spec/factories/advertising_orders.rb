# frozen_string_literal: true

# == Schema Information
#
# Table name: advertising_orders
#
#  id                  :bigint           not null, primary key
#  business_sphere     :string
#  clip_title          :string
#  coefficient_percent :integer          default(0), not null
#  discount_cents      :integer          default(0), not null
#  document_version    :integer          default(1), not null
#  duration_seconds    :integer
#  placement_kind      :string           default("own_atmosphere"), not null
#  product_name        :string           not null
#  status              :string           default("draft"), not null
#  total_shows         :integer          default(0), not null
#  total_sum_cents     :integer          default(0), not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  created_by_user_id  :bigint           not null
#  media_asset_id      :bigint           not null
#  organization_id     :bigint           not null
#  rotation_id         :bigint           not null
#
# Indexes
#
#  index_advertising_orders_on_created_by_user_id  (created_by_user_id)
#  index_advertising_orders_on_media_asset_id      (media_asset_id)
#  index_advertising_orders_on_organization_id     (organization_id)
#  index_advertising_orders_on_rotation_id         (rotation_id) UNIQUE
#  index_advertising_orders_on_status              (status)
#
# Foreign Keys
#
#  fk_rails_...  (created_by_user_id => users.id) ON DELETE => restrict
#  fk_rails_...  (media_asset_id => media_assets.id) ON DELETE => restrict
#  fk_rails_...  (organization_id => organizations.id) ON DELETE => restrict
#  fk_rails_...  (rotation_id => rotations.id) ON DELETE => restrict
#
FactoryBot.define do
  factory :advertising_order do
    organization
    created_by { association :user, organization: organization }
    media_asset do
      association :media_asset, :ready, :with_png_file, organization: organization, duration_seconds: 10
    end
    rotation { association :rotation, :system_managed, organization: organization }
    product_name { "Triumph" }

    trait :draft do
      status { :draft }
    end

    trait :with_lines do
      after(:create) do |order|
        create(:advertising_order_line, :with_days, advertising_order: order)
      end
    end
  end
end
