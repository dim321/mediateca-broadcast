# frozen_string_literal: true

require "rails_helper"

RSpec.describe TagPolicy do
  let(:operator_user) { create(:user, organization: create(:organization, :operator)) }
  let(:client_user) { create(:user, organization: create(:organization, :client)) }
  let(:tag) { create(:tag) }

  describe "permissions" do
    it "allows any signed-in user to list and view tags" do
      expect(described_class.new(client_user, tag)).to be_index
      expect(described_class.new(client_user, tag)).to be_show
    end

    it "allows only operators to manage tags" do
      expect(described_class.new(operator_user, tag)).to be_create
      expect(described_class.new(operator_user, tag)).to be_update
      expect(described_class.new(operator_user, tag)).to be_destroy

      expect(described_class.new(client_user, tag)).not_to be_create
      expect(described_class.new(client_user, tag)).not_to be_update
      expect(described_class.new(client_user, tag)).not_to be_destroy
    end
  end

  describe "Scope" do
    it "returns all tags for signed-in users" do
      local = create(:tag, name: "local")
      remote = create(:tag, name: "remote")

      resolved = described_class::Scope.new(client_user, Tag.all).resolve
      expect(resolved).to include(local, remote)
    end
  end
end
