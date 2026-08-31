# frozen_string_literal: true

require "rails_helper"

RSpec.describe MediaAssetPolicy do
  let(:org) { create(:organization) }
  let(:other_org) { create(:organization) }
  let(:user) { create(:user, :manager, organization: org) }
  let(:asset) { create(:media_asset, :with_png_file, organization: org) }

  describe "show?" do
    it "разрешает доступ к медиа своей организации" do
      expect(described_class.new(user, asset).show?).to be true
    end

    it "запрещает доступ к приватному медиа другой организации" do
      foreign = create(:media_asset, :with_png_file, organization: other_org, visibility: :organization)
      expect(described_class.new(user, foreign).show?).to be false
    end

    it "разрешает доступ к network-медиа другой организации (AE8)" do
      shared = create(:media_asset, :with_png_file, :network_neutral, organization: other_org)
      expect(described_class.new(user, shared).show?).to be true
    end

    it "разрешает оператору доступ к медиа клиента" do
      operator = create(:user, organization: create(:organization, :operator))
      expect(described_class.new(operator, asset).show?).to be true
    end

    it "запрещает accountant доступ к медиа (KTD11)" do
      accountant = create(:user, :accountant, organization: org)
      expect(described_class.new(accountant, asset).show?).to be false
    end
  end

  describe "create?" do
    it "разрешает manager" do
      expect(described_class.new(user, MediaAsset).create?).to be true
    end

    it "разрешает administrator" do
      admin = create(:user, :administrator, organization: org)
      expect(described_class.new(admin, MediaAsset).create?).to be true
    end

    it "запрещает accountant (AE7)" do
      accountant = create(:user, :accountant, organization: org)
      expect(described_class.new(accountant, MediaAsset).create?).to be false
    end
  end

  describe "update?" do
    it "разрешает обновление в своей организации" do
      expect(described_class.new(user, asset).update?).to be true
    end

    it "запрещает обновление чужого network-ассета" do
      foreign = create(:media_asset, :with_png_file, :network_neutral, organization: other_org)
      expect(described_class.new(user, foreign).update?).to be false
    end

    it "запрещает accountant" do
      accountant = create(:user, :accountant, organization: org)
      expect(described_class.new(accountant, asset).update?).to be false
    end
  end

  describe "destroy?" do
    it "запрещает удаление чужого network-ассета" do
      foreign = create(:media_asset, :with_png_file, :network_neutral, organization: other_org)
      expect(described_class.new(user, foreign).destroy?).to be false
    end
  end

  describe "Scope" do
    it "возвращает свои активы и чужие network (AE8)" do
      own = create(:media_asset, :with_png_file, organization: org)
      shared = create(:media_asset, :with_png_file, :network_neutral, organization: other_org)
      private_foreign = create(:media_asset, :with_png_file, organization: other_org, visibility: :organization)

      resolved = described_class::Scope.new(user, MediaAsset.all).resolve
      expect(resolved).to include(own, shared)
      expect(resolved).not_to include(private_foreign)
    end

    it "возвращает все активы оператору" do
      operator = create(:user, organization: create(:organization, :operator))
      own = create(:media_asset, :with_png_file, organization: org)
      foreign = create(:media_asset, :with_png_file, organization: other_org)

      resolved = described_class::Scope.new(operator, MediaAsset.all).resolve
      expect(resolved).to include(own, foreign)
    end

    it "не возвращает активы accountant" do
      create(:media_asset, :with_png_file, organization: org)
      accountant = create(:user, :accountant, organization: org)

      resolved = described_class::Scope.new(accountant, MediaAsset.all).resolve
      expect(resolved).to be_empty
    end
  end
end
