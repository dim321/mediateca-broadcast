# frozen_string_literal: true

require "rails_helper"

RSpec.describe MediaAssetPolicy do
  let(:org) { create(:organization) }
  let(:other_org) { create(:organization) }
  let(:user) { create(:user, organization: org) }
  let(:asset) { create(:media_asset, :with_png_file, organization: org) }

  describe "show?" do
    it "разрешает доступ к медиа своей организации" do
      expect(described_class.new(user, asset).show?).to be true
    end

    it "запрещает доступ к медиа другой организации" do
      foreign = create(:media_asset, :with_png_file, organization: other_org)
      expect(described_class.new(user, foreign).show?).to be false
    end
  end

  describe "update?" do
    it "разрешает обновление в своей организации" do
      expect(described_class.new(user, asset).update?).to be true
    end

    it "запрещает обновление в чужой организации" do
      foreign = create(:media_asset, :with_png_file, organization: other_org)
      expect(described_class.new(user, foreign).update?).to be false
    end
  end

  describe "Scope" do
    it "возвращает только активы текущего тенанта" do
      create(:media_asset, :with_png_file, organization: org)
      create(:media_asset, :with_png_file, organization: other_org)

      resolved = described_class::Scope.new(user, MediaAsset.all).resolve
      expect(resolved).to all(have_attributes(organization_id: org.id))
      expect(resolved.count).to eq(1)
    end
  end
end
