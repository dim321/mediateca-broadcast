# frozen_string_literal: true

require "rails_helper"

RSpec.describe BroadcastPointPolicy do
  let(:org) { create(:organization) }
  let(:other_org) { create(:organization) }
  let(:user) { create(:user, organization: org) }
  let(:point) { create(:broadcast_point, organization: org) }

  describe "show?" do
    it "разрешает точку своей организации" do
      expect(described_class.new(user, point).show?).to be true
    end

    it "запрещает точку другой организации" do
      foreign = create(:broadcast_point, organization: other_org)
      expect(described_class.new(user, foreign).show?).to be false
    end
  end

  describe "Scope" do
    it "возвращает только точки текущего тенанта" do
      create(:broadcast_point, organization: org)
      create(:broadcast_point, organization: other_org)

      resolved = described_class::Scope.new(user, BroadcastPoint.all).resolve
      expect(resolved).to all(have_attributes(organization_id: org.id))
      expect(resolved.count).to eq(1)
    end
  end
end
