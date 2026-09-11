# frozen_string_literal: true

require "rails_helper"

RSpec.describe BroadcastPointGroupPolicy do
  let(:org) { create(:organization) }
  let(:user) { create(:user, :manager, organization: org) }
  let(:group) { create(:broadcast_point_group, organization: org) }

  describe "create?" do
    it "разрешает manager" do
      expect(described_class.new(user, BroadcastPointGroup).create?).to be true
    end

    it "запрещает accountant" do
      accountant = create(:user, :accountant, organization: org)
      expect(described_class.new(accountant, BroadcastPointGroup).create?).to be false
    end
  end

  describe "update?" do
    it "разрешает manager" do
      expect(described_class.new(user, group).update?).to be true
    end

    it "запрещает accountant" do
      accountant = create(:user, :accountant, organization: org)
      expect(described_class.new(accountant, group).update?).to be false
    end
  end
end
