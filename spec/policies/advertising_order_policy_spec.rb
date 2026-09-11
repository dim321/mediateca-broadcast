# frozen_string_literal: true

require "rails_helper"

RSpec.describe AdvertisingOrderPolicy do
  let(:org) { create(:organization, :client) }
  let(:manager) { create(:user, :manager, organization: org) }
  let(:administrator) { create(:user, :administrator, organization: org) }
  let(:accountant) { create(:user, :accountant, organization: org) }
  let(:order) { create(:advertising_order, :draft, organization: org, created_by: manager) }

  describe "index? / show? / print?" do
    it "разрешает менеджеру, администратору и бухгалтеру своей организации (AE10)" do
      [ manager, administrator, accountant ].each do |user|
        expect(described_class.new(user, AdvertisingOrder).index?).to be true
        expect(described_class.new(user, order).show?).to be true
        expect(described_class.new(user, order).print?).to be true
      end
    end

    it "запрещает show/print чужой организации" do
      stranger = create(:user, :manager, organization: create(:organization, :client))

      expect(described_class.new(stranger, order).show?).to be false
      expect(described_class.new(stranger, order).print?).to be false
    end
  end

  describe "create? / update? / activate? / cancel? / replace_clip?" do
    it "разрешает manager и administrator" do
      [ manager, administrator ].each do |user|
        policy = described_class.new(user, order)
        expect(policy.create?).to be true
        expect(policy.update?).to be true
        expect(policy.activate?).to be true
        expect(policy.cancel?).to be true
      end
    end

    it "разрешает замену ролика на активном заказе менеджеру и администратору" do
      order.update!(status: :active)

      [ manager, administrator ].each do |user|
        expect(described_class.new(user, order).replace_clip?).to be true
      end
    end

    it "запрещает accountant (AE10)" do
      policy = described_class.new(accountant, order)

      expect(policy.create?).to be false
      expect(policy.update?).to be false
      expect(policy.activate?).to be false
      expect(policy.cancel?).to be false
      expect(policy.destroy?).to be false
      expect(policy.replace_clip?).to be false
    end
  end

  describe "replace_clip?" do
    it "запрещает замену ролика в черновике" do
      expect(described_class.new(manager, order).replace_clip?).to be false
    end
  end

  describe "destroy?" do
    it "разрешает удаление черновика" do
      expect(described_class.new(manager, order).destroy?).to be true
    end

    it "запрещает удаление не-черновика" do
      order.update!(status: :active)

      expect(described_class.new(manager, order).destroy?).to be false
    end
  end

  describe "update?" do
    it "запрещает правку сетки активного заказа" do
      order.update!(status: :active)

      expect(described_class.new(manager, order).update?).to be false
    end
  end

  describe AdvertisingOrderPolicy::Scope do
    it "ограничивает менеджера и бухгалтера своей организацией" do
      own = order
      foreign = create(:advertising_order, organization: create(:organization, :client))

      expect(described_class.new(manager, AdvertisingOrder).resolve).to contain_exactly(own)
      expect(described_class.new(accountant, AdvertisingOrder).resolve).to contain_exactly(own)
      expect(described_class.new(manager, AdvertisingOrder).resolve).not_to include(foreign)
    end
  end
end
