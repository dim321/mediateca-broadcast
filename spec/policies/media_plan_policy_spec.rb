# frozen_string_literal: true

require "rails_helper"

RSpec.describe MediaPlanPolicy do
  let(:org) { create(:organization) }
  let(:user) { create(:user, :manager, organization: org) }
  let(:plan) { create(:media_plan, organization: org) }

  describe "create?" do
    it "разрешает manager" do
      expect(described_class.new(user, MediaPlan).create?).to be true
    end

    it "разрешает administrator" do
      admin = create(:user, :administrator, organization: org)
      expect(described_class.new(admin, MediaPlan).create?).to be true
    end

    it "запрещает accountant (AE7)" do
      accountant = create(:user, :accountant, organization: org)
      expect(described_class.new(accountant, MediaPlan).create?).to be false
    end
  end

  describe "index?" do
    it "запрещает accountant (KTD11)" do
      accountant = create(:user, :accountant, organization: org)
      expect(described_class.new(accountant, MediaPlan).index?).to be false
    end
  end

  describe "update?" do
    it "разрешает manager в своей org" do
      expect(described_class.new(user, plan).update?).to be true
    end

    it "запрещает accountant" do
      accountant = create(:user, :accountant, organization: org)
      expect(described_class.new(accountant, plan).update?).to be false
    end
  end
end
