# frozen_string_literal: true

require "rails_helper"

RSpec.describe TagPolicy do
  let(:org) { create(:organization) }
  let(:other_org) { create(:organization) }
  let(:user) { create(:user, organization: org) }

  describe "Scope" do
    it "возвращает теги только своей организации" do
      create(:tag, organization: org, name: "local")
      create(:tag, organization: other_org, name: "remote")

      resolved = described_class::Scope.new(user, Tag.all).resolve
      expect(resolved.map(&:name)).to eq([ "local" ])
    end
  end
end
