# frozen_string_literal: true

require "rails_helper"

RSpec.describe PointGroupPolicy do
  let(:org) { create(:organization) }
  let(:other_org) { create(:organization) }
  let(:user) { create(:user, organization: org) }
  let(:group) { create(:point_group, organization: org) }

  describe "show?" do
    it "разрешает группу своей организации" do
      expect(described_class.new(user, group).show?).to be true
    end

    it "запрещает группу другой организации" do
      foreign = create(:point_group, organization: other_org)
      expect(described_class.new(user, foreign).show?).to be false
    end
  end

  describe "add_points?" do
    it "разрешает в своей организации" do
      expect(described_class.new(user, group).add_points?).to be true
    end

    it "запрещает в чужой организации" do
      foreign = create(:point_group, organization: other_org)
      expect(described_class.new(user, foreign).add_points?).to be false
    end
  end

  describe "Scope" do
    it "ограничивает группы по organization_id" do
      create(:point_group, organization: org)
      create(:point_group, organization: other_org)

      resolved = described_class::Scope.new(user, PointGroup.all).resolve
      expect(resolved.map(&:organization_id).uniq).to eq([ org.id ])
    end
  end
end
