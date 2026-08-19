# frozen_string_literal: true

require "rails_helper"

RSpec.describe Screen, type: :model do
  it "allows saving without an owner" do
    expect(build(:screen)).to be_valid
  end

  it "allows a client owner organization" do
    screen = build(:screen, owner_organization: create(:organization, :client))

    expect(screen).to be_valid
  end

  it "treats the operator organization as no owner" do
    screen = build(:screen, owner_organization: create(:organization, :operator))

    expect(screen).to be_valid
    expect(screen.owner_organization).to be_nil
  end

  it "assigns a default name from the station when name is blank" do
    station = create(:station, name: "Касса", location: create(:location, name: "ТЦ Командор"))

    screen = described_class.create!(station: station)

    expect(screen.name).to eq("ТЦ Командор-Касса_screen_1")
  end

  it "keeps an explicitly provided name" do
    station = create(:station, name: "Касса", location: create(:location, name: "ТЦ Командор"))

    screen = described_class.create!(station: station, name: "Витрина 1")

    expect(screen.name).to eq("Витрина 1")
  end
end
