# frozen_string_literal: true

require "rails_helper"

RSpec.describe ServiceThemes::Create do
  let(:operator) { create(:organization, :operator) }

  it "creates a theme with four empty system-managed rotations (AE1)" do
    theme = described_class.call(organization: operator, name: "Салон красоты")

    expect(theme).to be_persisted
    expect(theme.name).to eq("Салон красоты")
    expect(theme.rotations.size).to eq(4)
    expect(theme.rotations).to all(be_system_managed)
    expect(theme.rotations.map { |rotation| rotation.rotation_items.count }).to all(eq(0))
    expect(theme.header_start_rotation.name).to eq("Салон красоты · header_start")
    expect(theme.rotation_for(:service_welcome)).to eq(theme.welcome_rotation)
  end

  it "rejects a client organization and does not leave rotations" do
    client = create(:organization, :client)

    expect {
      described_class.call(organization: client, name: "Салон красоты")
    }.to raise_error(ActiveRecord::RecordInvalid)

    expect(Rotation.where("name LIKE ?", "Салон красоты%")).to be_empty
    expect(ServiceTheme.count).to eq(0)
  end

  it "rejects a duplicate name in the same organization" do
    described_class.call(organization: operator, name: "Салон красоты")

    expect {
      described_class.call(organization: operator, name: "Салон красоты")
    }.to raise_error(ActiveRecord::RecordInvalid)
  end
end
