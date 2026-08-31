# frozen_string_literal: true

require "rails_helper"

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
RSpec.describe AdvertisingOrder, type: :model do
  describe "validations" do
    it "requires a product name" do
      order = build(:advertising_order, product_name: "")
      expect(order).not_to be_valid
      expect(order.errors[:product_name]).to be_present
    end

    it "defaults to draft own-atmosphere with document version 1" do
      order = create(:advertising_order)
      expect(order).to be_draft
      expect(order).to be_own_atmosphere
      expect(order.document_version).to eq(1)
      expect(order.coefficient_percent).to eq(0)
      expect(order.discount_cents).to eq(0)
      expect(order.total_shows).to eq(0)
      expect(order.total_sum_cents).to eq(0)
    end

    it "rejects a negative discount" do
      order = build(:advertising_order, discount_cents: -1)
      expect(order).not_to be_valid
      expect(order.errors[:discount_cents]).to be_present
    end

    it "requires the rotation to belong to the same organization" do
      order = build(:advertising_order)
      order.rotation = create(:rotation, :system_managed, organization: create(:organization))
      expect(order).not_to be_valid
      expect(order.errors[:rotation]).to be_present
    end

    it "requires a system-managed rotation" do
      order = build(:advertising_order)
      order.rotation = create(:rotation, organization: order.organization, system_managed: false)
      expect(order).not_to be_valid
      expect(order.errors[:rotation]).to be_present
    end
  end

  describe "clip snapshots" do
    it "fills clip_title and duration_seconds from the media asset when blank" do
      asset = create(:media_asset, :ready, :with_png_file, duration_seconds: 15)
      order = build(:advertising_order, media_asset: asset, organization: asset.organization,
        clip_title: nil, duration_seconds: nil)
      order.created_by = create(:user, organization: asset.organization)
      order.rotation = create(:rotation, :system_managed, organization: asset.organization)

      expect(order).to be_valid
      expect(order.clip_title).to eq("1x1.png")
      expect(order.duration_seconds).to eq(15)
    end

    it "does not overwrite an explicit clip_title" do
      order = create(:advertising_order, clip_title: "Триумф 15 сек")
      expect(order.clip_title).to eq("Триумф 15 сек")
    end
  end

  describe "business sphere snapshot" do
    it "copies the profile sphere name on create" do
      sphere = create(:directory_business_sphere, name: "Ритейл")
      organization = create(:organization, :with_profile, profile_business_sphere: sphere)
      order = create(:advertising_order, organization: organization)

      expect(order.business_sphere).to eq("Ритейл")
    end

    it "leaves the snapshot empty when the profile has no sphere" do
      organization = create(:organization, :with_profile)
      order = create(:advertising_order, organization: organization)

      expect(order.business_sphere).to be_nil
    end

    it "does not rewrite the snapshot when the directory value is renamed" do
      sphere = create(:directory_business_sphere, name: "Ритейл")
      organization = create(:organization, :with_profile, profile_business_sphere: sphere)
      order = create(:advertising_order, organization: organization)

      sphere.update!(name: "СМИ")
      expect(order.reload.business_sphere).to eq("Ритейл")
    end

    it "does not rewrite the snapshot when the profile sphere is changed later" do
      sphere = create(:directory_business_sphere, name: "Ритейл")
      organization = create(:organization, :with_profile, profile_business_sphere: sphere)
      order = create(:advertising_order, organization: organization)

      organization.profile.update!(business_sphere: create(:directory_business_sphere, name: "Другое"))
      expect(order.reload.business_sphere).to eq("Ритейл")
    end
  end

  describe "associations" do
    it "destroys lines and days with the order" do
      order = create(:advertising_order, :with_lines)

      expect { order.destroy! }
        .to change(AdvertisingOrderLine, :count).by(-1)
        .and change(AdvertisingOrderLineDay, :count).by(-1)
    end
  end
end
